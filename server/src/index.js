// Nitches game server — Cloudflare Worker.
//
// API (JSON, Bearer token auth after register/login):
//   POST /api/register            {username, password} -> {token, user, profile}
//   POST /api/login               {username, password} -> {token, user, profile}
//   POST /api/logout
//   GET  /api/me                  -> {user, profile}
//   PUT  /api/me/progress         {credits, owned_cars, owned_worlds, stats}
//   GET  /api/quests/today        -> 10 daily quests with progress/claimed
//   POST /api/quests/progress     {quest_id, value}   (server keeps the max)
//   POST /api/quests/claim        {quest_id} -> {credits}
//   POST /api/feedback            {text, category}
//   GET  /api/leaderboard?by=distance|credits
//   POST /api/presence            {world}
//   GET  /api/rooms               -> online counts per world (60 s window)
//   GET  /mp?room=&name=&car=&token=  WebSocket free-roam room (Durable Object)
// Admin (first registered user has role 'admin'):
//   GET  /api/admin/stats, GET /api/admin/users, GET /api/admin/feedback
//   POST /api/admin/grant         {username, amount}
//   POST /api/admin/feedback/delete {id}
// Pages: GET / (info), GET /privacy (privacy policy, RU).
//
// Passwords: PBKDF2-SHA256, 100k iterations, per-user salt.  Sessions are
// opaque random tokens stored in D1 (revocable, 30 days).

const SERVER_VERSION = "0.2.61";
const SESSION_TTL_SEC = 30 * 24 * 3600;
const START_CREDITS = 15000;

// daily quest pool — MUST mirror QUEST_POOL in the game client
// (native/scripts/main.gd): ids, metrics, targets, rewards.
const QUEST_POOL = [
  { id: "dist_5",         metric: "distance_km",         target: 5,    reward: 400 },
  { id: "dist_15",        metric: "distance_km",         target: 15,   reward: 900 },
  { id: "dist_30",        metric: "distance_km",         target: 30,   reward: 1600 },
  { id: "dist_50",        metric: "distance_km",         target: 50,   reward: 2500 },
  { id: "speed_160",      metric: "top_speed_kmh",       target: 160,  reward: 500 },
  { id: "speed_200",      metric: "top_speed_kmh",       target: 200,  reward: 900 },
  { id: "drift_time_30",  metric: "drift_seconds",       target: 30,   reward: 600 },
  { id: "drift_time_90",  metric: "drift_seconds",       target: 90,   reward: 1100 },
  { id: "drift_angle_30", metric: "drift_angle_deg",     target: 30,   reward: 500 },
  { id: "drift_angle_40", metric: "drift_angle_deg",     target: 40,   reward: 900 },
  { id: "play_10",        metric: "play_minutes",        target: 10,   reward: 350 },
  { id: "play_25",        metric: "play_minutes",        target: 25,   reward: 700 },
  { id: "nitro_20",       metric: "nitro_seconds",       target: 20,   reward: 550 },
  { id: "earn_2000",      metric: "credits_from_driving", target: 2000, reward: 600 },
];

// ---------- helpers ----------

const enc = new TextEncoder();

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "access-control-allow-origin": "*",
      "access-control-allow-headers": "authorization, content-type",
      "access-control-allow-methods": "GET, POST, PUT, DELETE, OPTIONS",
    },
  });
}

function err(message, status = 400) {
  return json({ error: message }, status);
}

function b64(bytes) {
  let s = "";
  for (const b of new Uint8Array(bytes)) s += String.fromCharCode(b);
  return btoa(s);
}

function unb64(text) {
  const bin = atob(text);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function hex(bytes) {
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function hashPassword(password, saltB64) {
  const salt = saltB64 ? unb64(saltB64) : crypto.getRandomValues(new Uint8Array(16));
  const key = await crypto.subtle.importKey("raw", enc.encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", hash: "SHA-256", salt, iterations: 100000 }, key, 256);
  return { hash: b64(bits), salt: b64(salt) };
}

function validUsername(u) {
  return typeof u === "string" && /^[A-Za-z0-9_]{3,16}$/.test(u);
}

function utcDay() {
  return new Date().toISOString().slice(0, 10);
}

function fnv1a(text) {
  let h = 2166136261 >>> 0;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 16777619) >>> 0;
  }
  return h >>> 0;
}

function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function dailyQuests(day, userId) {
  const rng = mulberry32(fnv1a(`${day}:${userId}`));
  const idx = QUEST_POOL.map((_, i) => i);
  for (let i = idx.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [idx[i], idx[j]] = [idx[j], idx[i]];
  }
  return idx.slice(0, 10).map((i) => QUEST_POOL[i]);
}

function parseProfile(row) {
  if (!row) return null;
  let cars = ["shelby_gt500"], worlds = ["richtown"], stats = {};
  try { cars = JSON.parse(row.owned_cars); } catch {}
  try { worlds = JSON.parse(row.owned_worlds); } catch {}
  try { stats = JSON.parse(row.stats); } catch {}
  return {
    credits: row.credits,
    owned_cars: cars,
    owned_worlds: worlds,
    stats,
    updated_at: row.updated_at,
  };
}

async function ensureProfile(env, userId) {
  await env.DB.prepare(
    "INSERT OR IGNORE INTO profiles (user_id, credits, updated_at) VALUES (?1, ?2, ?3)"
  ).bind(userId, START_CREDITS, Date.now()).run();
  const row = await env.DB.prepare("SELECT * FROM profiles WHERE user_id = ?1").bind(userId).first();
  return parseProfile(row);
}

async function createSession(env, userId) {
  const token = hex(crypto.getRandomValues(new Uint8Array(32)));
  const now = Date.now();
  await env.DB.prepare(
    "INSERT INTO sessions (token, user_id, created_at, expires_at) VALUES (?1, ?2, ?3, ?4)"
  ).bind(token, userId, now, now + SESSION_TTL_SEC * 1000).run();
  return token;
}

async function authenticate(env, request) {
  const header = request.headers.get("authorization") || "";
  const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
  if (!token) return null;
  const row = await env.DB.prepare(
    `SELECT u.id, u.username, u.role, u.created_at
       FROM sessions s JOIN users u ON u.id = s.user_id
      WHERE s.token = ?1 AND s.expires_at > ?2`
  ).bind(token, Date.now()).first();
  if (!row) return null;
  await env.DB.prepare("UPDATE users SET last_seen = ?1 WHERE id = ?2").bind(Date.now(), row.id).run();
  return { id: row.id, username: row.username, role: row.role, created_at: row.created_at, token };
}

async function readJson(request) {
  try { return await request.json(); } catch { return null; }
}

function clampInt(v, lo, hi, fallback) {
  const n = Number.isFinite(v) ? Math.trunc(v) : fallback;
  return Math.max(lo, Math.min(hi, n));
}

function stringArray(v, fallback) {
  if (!Array.isArray(v)) return fallback;
  return v.filter((x) => typeof x === "string").slice(0, 64);
}

// ---------- routes ----------

async function handleRegister(env, request) {
  const body = await readJson(request);
  if (!body) return err("bad json");
  const username = String(body.username || "").trim();
  const password = String(body.password || "");
  if (!validUsername(username)) return err("username: 3-16 chars, letters/digits/_");
  if (password.length < 6 || password.length > 128) return err("password: 6-128 chars");
  const existing = await env.DB.prepare(
    "SELECT id FROM users WHERE username = ?1 COLLATE NOCASE").bind(username).first();
  if (existing) return err("username taken", 409);
  const countRow = await env.DB.prepare("SELECT COUNT(*) AS n FROM users").first();
  const role = Number(countRow?.n || 0) === 0 ? "admin" : "player"; // first player = developer
  const { hash, salt } = await hashPassword(password);
  const now = Date.now();
  const res = await env.DB.prepare(
    "INSERT INTO users (username, pass_hash, salt, role, created_at, last_seen) VALUES (?1, ?2, ?3, ?4, ?5, ?5)"
  ).bind(username, hash, salt, role, now).run();
  const userId = res.meta.last_row_id;
  const profile = await ensureProfile(env, userId);
  const token = await createSession(env, userId);
  return json({
    token,
    user: { id: userId, username, role, created_at: now },
    profile,
    first_player: role === "admin",
  }, 201);
}

async function handleLogin(env, request) {
  const body = await readJson(request);
  if (!body) return err("bad json");
  const username = String(body.username || "").trim();
  const password = String(body.password || "");
  const row = await env.DB.prepare(
    "SELECT id, username, pass_hash, salt, role, created_at FROM users WHERE username = ?1 COLLATE NOCASE"
  ).bind(username).first();
  if (!row) return err("invalid username or password", 401);
  const { hash } = await hashPassword(password, row.salt);
  if (!timingSafeEqual(hash, row.pass_hash)) return err("invalid username or password", 401);
  const profile = await ensureProfile(env, row.id);
  const token = await createSession(env, row.id);
  return json({
    token,
    user: { id: row.id, username: row.username, role: row.role, created_at: row.created_at },
    profile,
  });
}

async function handleProgressPut(env, request, user) {
  const body = await readJson(request);
  if (!body) return err("bad json");
  const current = await ensureProfile(env, user.id);
  const credits = clampInt(body.credits, 0, 100000000, current.credits);
  const cars = stringArray(body.owned_cars, current.owned_cars);
  const worlds = stringArray(body.owned_worlds, current.owned_worlds);
  const statsIn = (body.stats && typeof body.stats === "object") ? body.stats : {};
  const stats = {
    distance_km: Math.max(0, Number(statsIn.distance_km) || 0),
    top_speed_kmh: Math.max(0, Number(statsIn.top_speed_kmh) || 0),
    drift_deg: Math.max(0, Number(statsIn.drift_deg) || 0),
    play_seconds: Math.max(0, Number(statsIn.play_seconds) || 0),
  };
  await env.DB.prepare(
    "UPDATE profiles SET credits = ?1, owned_cars = ?2, owned_worlds = ?3, stats = ?4, updated_at = ?5 WHERE user_id = ?6"
  ).bind(credits, JSON.stringify(cars), JSON.stringify(worlds), JSON.stringify(stats), Date.now(), user.id).run();
  return json({ profile: await ensureProfile(env, user.id) });
}

async function handleQuestsToday(env, user) {
  const day = utcDay();
  const quests = dailyQuests(day, user.id);
  const ids = quests.map((q) => q.id);
  const marks = ids.map(() => "?").join(",");
  const prog = await env.DB.prepare(
    `SELECT quest_id, value FROM quest_progress WHERE user_id = ? AND day = ? AND quest_id IN (${marks})`
  ).bind(user.id, day, ...ids).all();
  const claimed = await env.DB.prepare(
    `SELECT quest_id FROM quest_claims WHERE user_id = ? AND day = ? AND quest_id IN (${marks})`
  ).bind(user.id, day, ...ids).all();
  const progMap = {};
  for (const r of prog.results || []) progMap[r.quest_id] = r.value;
  const claimedSet = new Set((claimed.results || []).map((r) => r.quest_id));
  return json({
    day,
    quests: quests.map((q) => ({
      ...q,
      progress: progMap[q.id] || 0,
      claimed: claimedSet.has(q.id),
    })),
  });
}

async function handleQuestProgress(env, request, user) {
  const body = await readJson(request);
  if (!body) return err("bad json");
  const quest = QUEST_POOL.find((q) => q.id === String(body.quest_id || ""));
  if (!quest) return err("unknown quest", 404);
  const value = Math.max(0, Number(body.value) || 0);
  const day = utcDay();
  await env.DB.prepare(
    `INSERT INTO quest_progress (user_id, day, quest_id, value) VALUES (?1, ?2, ?3, ?4)
     ON CONFLICT(user_id, day, quest_id) DO UPDATE SET value = MAX(value, excluded.value)`
  ).bind(user.id, day, quest.id, value).run();
  return json({ ok: true });
}

async function handleQuestClaim(env, request, user) {
  const body = await readJson(request);
  if (!body) return err("bad json");
  const quest = QUEST_POOL.find((q) => q.id === String(body.quest_id || ""));
  if (!quest) return err("unknown quest", 404);
  const day = utcDay();
  if (!dailyQuests(day, user.id).some((q) => q.id === quest.id)) return err("quest not active today", 409);
  const prog = await env.DB.prepare(
    "SELECT value FROM quest_progress WHERE user_id = ?1 AND day = ?2 AND quest_id = ?3"
  ).bind(user.id, day, quest.id).first();
  if (!prog || Number(prog.value) < quest.target) return err("quest not completed", 409);
  const ins = await env.DB.prepare(
    "INSERT OR IGNORE INTO quest_claims (user_id, day, quest_id, claimed_at) VALUES (?1, ?2, ?3, ?4)"
  ).bind(user.id, day, quest.id, Date.now()).run();
  if (!ins.meta.changes) return err("already claimed", 409);
  await ensureProfile(env, user.id);
  await env.DB.prepare(
    "UPDATE profiles SET credits = credits + ?1, updated_at = ?2 WHERE user_id = ?3"
  ).bind(quest.reward, Date.now(), user.id).run();
  const profile = await ensureProfile(env, user.id);
  return json({ ok: true, reward: quest.reward, credits: profile.credits });
}

async function handleFeedback(env, request, user) {
  const body = await readJson(request);
  if (!body) return err("bad json");
  const text = String(body.text || "").trim().slice(0, 2000);
  if (text.length < 3) return err("feedback too short");
  const category = String(body.category || "general").slice(0, 32);
  await env.DB.prepare(
    "INSERT INTO feedback (user_id, username, category, text, created_at) VALUES (?1, ?2, ?3, ?4, ?5)"
  ).bind(user.id, user.username, category, text, Date.now()).run();
  return json({ ok: true }, 201);
}

async function handleLeaderboard(env, url) {
  const by = url.searchParams.get("by") === "credits" ? "credits" : "distance";
  const rows = await env.DB.prepare(
    "SELECT u.username, p.credits, p.stats FROM profiles p JOIN users u ON u.id = p.user_id LIMIT 500"
  ).all();
  const list = (rows.results || []).map((r) => {
    let stats = {};
    try { stats = JSON.parse(r.stats); } catch {}
    const distance = Number(stats.distance_km) || 0;
    return {
      username: r.username,
      credits: r.credits,
      distance_km: Math.round(distance * 10) / 10,
      level: 1 + Math.floor(distance / 50),
    };
  });
  list.sort((a, b) => (by === "credits" ? b.credits - a.credits : b.distance_km - a.distance_km));
  return json({ by, rows: list.slice(0, 20) });
}

async function handlePresence(env, request, user) {
  const body = await readJson(request);
  const world = ["richtown", "desert", "greenforest"].includes(body?.world) ? body.world : "richtown";
  await env.DB.prepare(
    `INSERT INTO presence (user_id, world, updated_at) VALUES (?1, ?2, ?3)
     ON CONFLICT(user_id) DO UPDATE SET world = excluded.world, updated_at = excluded.updated_at`
  ).bind(user.id, world, Date.now()).run();
  return json({ ok: true });
}

async function handleRooms(env) {
  const since = Date.now() - 60000;
  const rows = await env.DB.prepare(
    "SELECT world, COUNT(*) AS n FROM presence WHERE updated_at > ?1 GROUP BY world"
  ).bind(since).all();
  const counts = { richtown: 0, desert: 0, greenforest: 0 };
  let total = 0;
  for (const r of rows.results || []) { counts[r.world] = r.n; total += r.n; }
  return json({ total, worlds: counts });
}

// ---------- admin ----------

function requireAdmin(user) {
  return user && user.role === "admin";
}

async function handleAdmin(env, request, user, parts) {
  if (!requireAdmin(user)) return err("admin only", 403);
  const action = parts[2] || "";
  if (request.method === "GET" && action === "stats") {
    const users = await env.DB.prepare("SELECT COUNT(*) AS n FROM users").first();
    const fb = await env.DB.prepare("SELECT COUNT(*) AS n FROM feedback").first();
    const online = await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM presence WHERE updated_at > ?1").bind(Date.now() - 60000).first();
    const claims = await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM quest_claims WHERE day = ?1").bind(utcDay()).first();
    return json({ users: users?.n || 0, feedback: fb?.n || 0, online: online?.n || 0, claims_today: claims?.n || 0 });
  }
  if (request.method === "GET" && action === "users") {
    const rows = await env.DB.prepare(
      `SELECT u.id, u.username, u.role, u.created_at, u.last_seen, p.credits
         FROM users u LEFT JOIN profiles p ON p.user_id = u.id
        ORDER BY u.id ASC LIMIT 200`).all();
    return json({ users: rows.results || [] });
  }
  if (request.method === "GET" && action === "feedback") {
    const rows = await env.DB.prepare(
      "SELECT id, username, category, text, created_at FROM feedback ORDER BY id DESC LIMIT 100").all();
    return json({ feedback: rows.results || [] });
  }
  if (request.method === "POST" && action === "grant") {
    const body = await readJson(request);
    if (!body) return err("bad json");
    const amount = clampInt(body.amount, -1000000, 1000000, 0);
    if (amount === 0) return err("amount is 0");
    const target = await env.DB.prepare(
      "SELECT id, username FROM users WHERE username = ?1 COLLATE NOCASE"
    ).bind(String(body.username || "")).first();
    if (!target) return err("user not found", 404);
    await ensureProfile(env, target.id);
    await env.DB.prepare(
      "UPDATE profiles SET credits = MAX(0, credits + ?1), updated_at = ?2 WHERE user_id = ?3"
    ).bind(amount, Date.now(), target.id).run();
    const profile = await ensureProfile(env, target.id);
    return json({ ok: true, username: target.username, credits: profile.credits });
  }
  if (request.method === "POST" && action === "feedback" && parts[3] === "delete") {
    const body = await readJson(request);
    await env.DB.prepare("DELETE FROM feedback WHERE id = ?1").bind(clampInt(body?.id, 0, 1e9, 0)).run();
    return json({ ok: true });
  }
  return err("unknown admin action", 404);
}

// ---------- multiplayer room (Durable Object) ----------

export class RoomDO {
  constructor(state, env) {
    this.state = state;
    this.env = env;
  }

  broadcast(sender, obj) {
    const msg = JSON.stringify(obj);
    for (const ws of this.state.getWebSockets()) {
      if (ws === sender) continue;
      try { ws.send(msg); } catch {}
    }
  }

  async fetch(request) {
    if (request.headers.get("Upgrade") !== "websocket") {
      return new Response("expected websocket", { status: 426 });
    }
    const url = new URL(request.url);
    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    const meta = {
      id: crypto.randomUUID().slice(0, 8),
      name: (url.searchParams.get("name") || "ИГРОК").slice(0, 16),
      car: (url.searchParams.get("car") || "shelby_gt500").slice(0, 32),
    };
    server.serializeAttachment(meta);
    this.state.acceptWebSocket(server);
    try { server.send(JSON.stringify({ t: "welcome", id: meta.id })); } catch {}
    this.broadcast(server, { t: "join", id: meta.id, name: meta.name, car: meta.car });
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws, message) {
    let data;
    try { data = JSON.parse(message); } catch { return; }
    const meta = ws.deserializeAttachment() || {};
    if (data.t === "state" && Array.isArray(data.p) && Array.isArray(data.q)) {
      this.broadcast(ws, {
        t: "state", id: meta.id, name: meta.name, car: meta.car,
        p: data.p.slice(0, 3), q: data.q.slice(0, 4), s: Number(data.s) || 0,
      });
    } else if (data.t === "hello") {
      const peers = [];
      for (const other of this.state.getWebSockets()) {
        if (other === ws) continue;
        const m = other.deserializeAttachment() || {};
        peers.push({ id: m.id, name: m.name, car: m.car });
      }
      try { ws.send(JSON.stringify({ t: "peers", peers })); } catch {}
      this.broadcast(ws, { t: "announce_request" });
    }
  }

  async webSocketClose(ws) {
    const meta = ws.deserializeAttachment() || {};
    this.broadcast(ws, { t: "leave", id: meta.id });
  }

  async webSocketError(ws) {
    const meta = ws.deserializeAttachment() || {};
    this.broadcast(ws, { t: "leave", id: meta.id });
  }
}

const PRIVACY_HTML = `<!doctype html><html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Nitches — Политика конфиденциальности</title></head>
<body style="font-family:system-ui,sans-serif;max-width:760px;margin:2em auto;padding:0 1em;line-height:1.55">
<h1>Политика конфиденциальности игры Nitches</h1>
<p><i>Версия от 30 октября 2026 г. Игра находится в тестовой разработке (alpha).</i></p>
<h2>1. Кто обрабатывает данные</h2>
<p>Разработчик игры Nitches (физическое лицо, инди-проект). Серверная часть работает на инфраструктуре Cloudflare (Workers и база D1); Cloudflare выступает техническим обработчиком (хостинг), его собственная политика — cloudflare.com/privacypolicy.</p>
<h2>2. Какие данные мы собираем</h2>
<ul>
<li><b>Аккаунт:</b> имя пользователя (никнейм) и пароль — пароль хранится только в виде криптографического хэша PBKDF2 с индивидуальной солью; сам пароль нам неизвестен.</li>
<li><b>Игровой прогресс:</b> внутриигровая валюта (CR), купленные машины и карты, статистика вождения (пробег, максимальная скорость, дрифт, время в игре), прогресс ежедневных заданий.</li>
<li><b>Онлайн-присутствие и мультиплеер:</b> текущий мир/комната, позиция и модель автомобиля в сессии свободной езды (передаётся другим игрокам комнаты в реальном времени и не записывается в базу).</li>
<li><b>Отзывы:</b> текст, который вы отправляете через форму отзыва, и ваш никнейм.</li>
<li><b>Технические логи Cloudflare:</b> IP-адрес и метаданные запросов могут кратковременно обрабатываться Cloudflare для защиты от злоупотреблений; мы не ведём собственных логов IP.</li>
</ul>
<p>Мы <b>не собираем</b>: настоящее имя, e-mail (не запрашивается), телефон, геолокацию устройства, контакты, фото, платёжные данные. В игре нет рекламы и сторонних аналитических SDK.</p>
<h2>3. Зачем данные нужны</h2>
<p>Только для работы игры: вход в аккаунт, сохранение прогресса между устройствами, экономика и задания, мультиплеер, таблицы лидеров (никнейм, пробег, уровень), обработка отзывов и защита от накруток.</p>
<h2>4. Кому данные передаются</h2>
<p>Никому, кроме: (а) Cloudflare как хостинга; (б) других игроков в мультиплеерной комнате — им видны ваш никнейм, машина и её положение; (в) таблицы лидеров — никнейм и игровая статистика. Данные не продаются и не передаются в рекламных целях.</p>
<h2>5. Хранение и безопасность</h2>
<p>Данные хранятся в базе Cloudflare D1, пока существует аккаунт. Сессионные токены действуют до 30 дней и могут быть отозваны выходом из аккаунта. Поскольку игра — тестовая версия, возможны сбросы прогресса при крупных обновлениях; о таких случаях мы постараемся предупреждать в описаниях обновлений.</p>
<h2>6. Ваши права</h2>
<ul>
<li>Запросить экспорт или полное удаление аккаунта и всех связанных данных — через форму отзыва в игре (категория «Аккаунт») с вашего аккаунта; удаляем в течение 30 дней.</li>
<li>Играть полностью офлайн гостем без аккаунта — тогда на сервер ничего не отправляется, прогресс хранится только на устройстве.</li>
</ul>
<h2>7. Дети</h2>
<p>Игра не предназначена для детей младше 13 лет; если вы узнали, что ребёнок создал аккаунт, напишите через форму отзыва — удалим.</p>
<h2>8. Изменения политики</h2>
<p>При изменениях обновляем эту страницу и дату версии; существенные изменения дополнительно покажем в игре.</p>
<h2>9. Контакт</h2>
<p>Форма отзыва в игре (вкладка «Онлайн») или Issues репозитория проекта на GitHub (Aleksandr-pro/Nitches).</p>
</body></html>`;

// ---------- main fetch ----------

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";
    if (request.method === "OPTIONS") return json({ ok: true });

    try {
      if (path === "/" && request.method === "GET") {
        return json({
          name: "Nitches Server",
          version: SERVER_VERSION,
          multiplayer: Boolean(env.ROOMS),
          day: utcDay(),
        });
      }
      if (path === "/privacy" && request.method === "GET") {
        return new Response(PRIVACY_HTML, {
          headers: { "content-type": "text/html; charset=utf-8" },
        });
      }

      // Multiplayer WebSocket room.
      if (path === "/mp") {
        if (!env.ROOMS) return err("multiplayer is not configured on this server (no Durable Objects binding)", 501);
        const token = url.searchParams.get("token") || "";
        const session = await env.DB.prepare(
          "SELECT user_id FROM sessions WHERE token = ?1 AND expires_at > ?2"
        ).bind(token, Date.now()).first();
        if (!session) return err("unauthorized", 401);
        const room = (url.searchParams.get("room") || "richtown").slice(0, 32);
        const stub = env.ROOMS.get(env.ROOMS.idFromName(room));
        return stub.fetch(request);
      }

      if (path === "/api/register" && request.method === "POST") return handleRegister(env, request);
      if (path === "/api/login" && request.method === "POST") return handleLogin(env, request);
      if (path === "/api/leaderboard" && request.method === "GET") return handleLeaderboard(env, url);
      if (path === "/api/rooms" && request.method === "GET") return handleRooms(env);

      // Authenticated routes.
      const user = await authenticate(env, request);
      if (!user) return err("unauthorized", 401);

      if (path === "/api/logout" && request.method === "POST") {
        await env.DB.prepare("DELETE FROM sessions WHERE token = ?1").bind(user.token).run();
        return json({ ok: true });
      }
      if (path === "/api/me" && request.method === "GET") {
        const profile = await ensureProfile(env, user.id);
        return json({
          user: { id: user.id, username: user.username, role: user.role, created_at: user.created_at },
          profile,
        });
      }
      if (path === "/api/me/progress" && request.method === "PUT") return handleProgressPut(env, request, user);
      if (path === "/api/quests/today" && request.method === "GET") return handleQuestsToday(env, user);
      if (path === "/api/quests/progress" && request.method === "POST") return handleQuestProgress(env, request, user);
      if (path === "/api/quests/claim" && request.method === "POST") return handleQuestClaim(env, request, user);
      if (path === "/api/feedback" && request.method === "POST") return handleFeedback(env, request, user);
      if (path === "/api/presence" && request.method === "POST") return handlePresence(env, request, user);

      const parts = path.split("/").filter(Boolean); // ["api","admin",...]
      if (parts[0] === "api" && parts[1] === "admin") return handleAdmin(env, request, user, parts);

      return err("not found", 404);
    } catch (e) {
      return json({ error: "internal error", detail: String(e && e.message || e) }, 500);
    }
  },
};
