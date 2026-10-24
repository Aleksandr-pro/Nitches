import * as THREE from 'three';
import './style.css';

/* =====================================================================
   NITCHES HORIZON — мобильный гоночный фестиваль в открытом мире.
   Аркадная физика, гонки с соперниками, чекпоинты, дрифт и нитро.
   ===================================================================== */

const $ = (id) => document.getElementById(id);
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const lerp = (a, b, t) => a + (b - a) * t;
const TAU = Math.PI * 2;

function angleLerp(a, b, t) {
  let d = (b - a) % TAU;
  if (d > Math.PI) d -= TAU;
  if (d < -Math.PI) d += TAU;
  return a + d * t;
}

function fmtTime(sec) {
  if (!isFinite(sec) || sec == null) return '—';
  const m = Math.floor(sec / 60);
  const s = sec - m * 60;
  return `${m}:${s.toFixed(1).padStart(4, '0')}`;
}

// Детерминированный генератор — остров всегда одинаковый
let seed = 1337;
function rnd() {
  seed = (seed * 16807) % 2147483647;
  return (seed - 1) / 2147483646;
}

/* ============================ Машины игрока ============================ */
const CARS = [
  {
    id: 'volt',
    name: 'VOLT GT',
    cls: 'Класс A • баланс',
    emoji: '🏎️',
    color: 0xff5e3a,
    accent: 0xffb03a,
    topSpeed: 52, // м/с ≈ 187 км/ч
    engine: 26,
    grip: 8.5,
    offroad: 0.62,
    stats: { spd: 0.78, acc: 0.8, hnd: 0.82, off: 0.45 },
  },
  {
    id: 'falcon',
    name: 'FALCON RS',
    cls: 'Класс S • гиперкар',
    emoji: '🦅',
    color: 0x2e7bff,
    accent: 0x2ee6ff,
    topSpeed: 62, // ≈ 223 км/ч
    engine: 31,
    grip: 9.5,
    offroad: 0.5,
    stats: { spd: 0.97, acc: 0.95, hnd: 0.9, off: 0.28 },
  },
  {
    id: 'dune',
    name: 'DUNE BREAKER',
    cls: 'Класс B • внедорожник',
    emoji: '🛻',
    color: 0x37c978,
    accent: 0xd9ff4a,
    topSpeed: 46,
    engine: 27,
    grip: 7,
    offroad: 0.94,
    stats: { spd: 0.62, acc: 0.78, hnd: 0.66, off: 0.97 },
  },
];

const RIVAL_NAMES = ['Кира', 'Макс', 'Луна', 'Диего', 'Зара'];
const RIVAL_COLORS = [0xffd23a, 0xb44aff, 0xff3a7a, 0x3affd2, 0xf2f2f2];

let selectedCar = CARS[0];
let selectedMode = 'race'; // 'race' | 'free'

function safeGetЛучшийLap() {
  try {
    return Number(localStorage.getItem('nh_best_lap')) || null;
  } catch (e) {
    return null;
  }
}
function safeSetЛучшийLap(v) {
  try {
    localStorage.setItem('nh_best_lap', String(v));
  } catch (e) { /* приватный режим — не страшно */ }
}

/* ============================ Состояние игры ============================ */
let gameState = 'menu'; // menu | countdown | racing | paused | finished
const TOTAL_LAPS = 3;

const player = {
  mesh: null,
  wheels: [],
  vel: new THREE.Vector3(),
  yaw: 0,
  steerVis: 0,
  nitro: 0.7,
  boosting: false,
  drifting: false,
  offroad: false,
  // прогресс гонки
  s: 0, // пройденные метры вдоль трассы
  prevSampleIdx: 0,
  sampleAccum: 0,
  nextCP: 1,
  lap: 1,
  lapStart: 0,
  лучшийLap: safeGetЛучшийLap(),
  score: 0,
  driftChain: 0,
  driftChainTimer: 0,
  finishTime: null,
};

let rivals = [];
let raceTime = 0;
let countdownT = 0;
let countdownShown = '';
let cameraMode = 0; // 0 — погоня, 1 — далеко, 2 — капот
let menuOrbit = 0;
let crashCooldown = 0;

const input = { gas: false, brake: false, left: false, right: false, nitro: false, handbrake: false };

/* ============================ Сцена ============================ */
const canvas = $('game');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.12;

const scene = new THREE.Scene();
scene.fog = new THREE.Fog(0xf2a56b, 140, 620);

const camera = new THREE.PerspectiveCamera(68, window.innerWidth / window.innerHeight, 0.1, 2000);
camera.position.set(0, 26, -140);

// Свет заката фестиваля
scene.add(new THREE.HemisphereLight(0x9fc4ff, 0x8a5a34, 0.85));
const sun = new THREE.DirectionalLight(0xffb377, 2.0);
sun.castShadow = true;
sun.shadow.mapSize.set(1024, 1024);
sun.shadow.camera.left = -55;
sun.shadow.camera.right = 55;
sun.shadow.camera.top = 55;
sun.shadow.camera.bottom = -55;
sun.shadow.camera.far = 320;
sun.shadow.bias = -0.0015;
scene.add(sun);
scene.add(sun.target);

/* ============================ Текстуры (canvas) ============================ */
function makeRoadTexture() {
  const c = document.createElement('canvas');
  c.width = 256;
  c.height = 256;
  const g = c.getContext('2d');
  g.fillStyle = '#35383f';
  g.fillRect(0, 0, 256, 256);
  // шум асфальта
  for (let i = 0; i < 2600; i++) {
    g.fillStyle = `rgba(${180 + Math.random() * 60},${180 + Math.random() * 60},${
      180 + Math.random() * 60
    },${Math.random() * 0.09})`;
    g.fillRect(Math.random() * 256, Math.random() * 256, 2, 2);
  }
  // бордюры красно-белые по краям
  for (let y = 0; y < 4; y++) {
    g.fillStyle = y % 2 ? '#e8e8e8' : '#d33b2e';
    g.fillRect(0, y * 64, 14, 64);
    g.fillStyle = y % 2 ? '#d33b2e' : '#e8e8e8';
    g.fillRect(242, y * 64, 14, 64);
  }
  g.fillStyle = '#f5f5f5';
  g.fillRect(22, 0, 5, 256);
  g.fillRect(229, 0, 5, 256);
  // центральная прерывистая
  g.fillStyle = '#ffd23a';
  g.fillRect(124, 18, 8, 96);
  const tex = new THREE.CanvasTexture(c);
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 4;
  return tex;
}

function makeGroundTexture() {
  const c = document.createElement('canvas');
  c.width = c.height = 256;
  const g = c.getContext('2d');
  g.fillStyle = '#4f9e46';
  g.fillRect(0, 0, 256, 256);
  for (let i = 0; i < 3200; i++) {
    const shades = ['#57ab4d', '#47913f', '#63ba57', '#5aa94e', '#3f8439'];
    g.fillStyle = shades[(Math.random() * shades.length) | 0];
    g.globalAlpha = 0.35 + Math.random() * 0.4;
    g.fillRect(Math.random() * 256, Math.random() * 256, 3 + Math.random() * 8, 3 + Math.random() * 8);
  }
  const tex = new THREE.CanvasTexture(c);
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.repeat.set(46, 46);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

function makeSkyTexture() {
  const c = document.createElement('canvas');
  c.width = 32;
  c.height = 512;
  const g = c.getContext('2d');
  const grad = g.createLinearGradient(0, 0, 0, 512);
  grad.addColorStop(0, '#274a8f');
  grad.addColorStop(0.42, '#5d7fc4');
  grad.addColorStop(0.62, '#e88a5a');
  grad.addColorStop(0.78, '#ffb03a');
  grad.addColorStop(1, '#ff8a4a');
  g.fillStyle = grad;
  g.fillRect(0, 0, 32, 512);
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

function makeBannerTexture() {
  const c = document.createElement('canvas');
  c.width = 1024;
  c.height = 160;
  const g = c.getContext('2d');
  const grad = g.createLinearGradient(0, 0, 1024, 0);
  grad.addColorStop(0, '#ff5e3a');
  grad.addColorStop(1, '#ffb03a');
  g.fillStyle = grad;
  g.fillRect(0, 0, 1024, 160);
  g.fillStyle = '#fff';
  g.font = 'italic 900 86px Arial, sans-serif';
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  g.fillText('★ NITCHES HORIZON ★', 512, 84);
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

/* ============================ Трасса ============================ */
const TRACK_POINTS = [
  [0, -175], [95, -155], [155, -85], [140, 5], [185, 90], [115, 165],
  [20, 180], [-75, 150], [-155, 110], [-175, 20], [-140, -75], [-70, -145],
].map(([x, z]) => new THREE.Vector3(x, 0, z));

const curve = new THREE.CatmullRomCurve3(TRACK_POINTS, true, 'catmullrom', 0.6);
const TRACK_LENGTH = curve.getLength();
const SAMPLES = curve.getSpacedPoints(800);
const ROAD_HALF = 7.5;

function nearestSampleIdx(pos) {
  let лучший = 0;
  let bd = Infinity;
  for (let i = 0; i < SAMPLES.length; i++) {
    const dx = SAMPLES[i].x - pos.x;
    const dz = SAMPLES[i].z - pos.z;
    const d = dx * dx + dz * dz;
    if (d < bd) {
      bd = d;
      лучший = i;
    }
  }
  return { idx: лучший, dist: Math.sqrt(bd) };
}

function pointAtS(s, lane = 0) {
  const u = ((s / TRACK_LENGTH) % 1 + 1) % 1;
  const p = curve.getPointAt(u);
  const t = curve.getTangentAt(u);
  const n = new THREE.Vector3(-t.z, 0, t.x);
  return { pos: p.clone().addScaledVector(n, lane), tangent: t, yaw: Math.atan2(t.x, t.z), u };
}

// Чекпоинты: 12 штук, индекс 0 — старт/финиш
const CHECKPOINTS = [];
for (let i = 0; i < 12; i++) {
  CHECKPOINTS.push(pointAtS((TRACK_LENGTH / 12) * i));
}

/* ============================ Мир ============================ */
const colliders = []; // {x,z,r}

// Небо
{
  const sky = new THREE.Mesh(
    new THREE.SphereGeometry(950, 24, 16),
    new THREE.MeshBasicMaterial({ map: makeSkyTexture(), side: THREE.BackSide, fog: false })
  );
  scene.add(sky);
  // Солнце-диск
  const sunBall = new THREE.Mesh(
    new THREE.SphereGeometry(38, 16, 16),
    new THREE.MeshBasicMaterial({ color: 0xffd98a, fog: false })
  );
  sunBall.position.set(-560, 120, -620);
  scene.add(sunBall);
}

// Океан и остров
{
  const water = new THREE.Mesh(
    new THREE.PlaneGeometry(2400, 2400),
    new THREE.MeshStandardMaterial({ color: 0x1f7fa8, roughness: 0.35, metalness: 0.1 })
  );
  water.rotation.x = -Math.PI / 2;
  water.position.y = -1.4;
  scene.add(water);

  const sand = new THREE.Mesh(
    new THREE.CircleGeometry(300, 48),
    new THREE.MeshStandardMaterial({ color: 0xe8cf8f, roughness: 1 })
  );
  sand.rotation.x = -Math.PI / 2;
  sand.position.y = -0.25;
  sand.receiveShadow = true;
  scene.add(sand);

  const ground = new THREE.Mesh(
    new THREE.CircleGeometry(282, 48),
    new THREE.MeshStandardMaterial({ map: makeGroundTexture(), roughness: 1 })
  );
  ground.rotation.x = -Math.PI / 2;
  ground.position.y = 0;
  ground.receiveShadow = true;
  scene.add(ground);
}

// Дорога — лента вдоль сплайна
{
  const SEG = 420;
  const positions = [];
  const uvs = [];
  const indices = [];
  for (let i = 0; i <= SEG; i++) {
    const u = i / SEG;
    const p = curve.getPointAt(u % 1);
    const t = curve.getTangentAt(u % 1);
    const n = new THREE.Vector3(-t.z, 0, t.x);
    const l = p.clone().addScaledVector(n, ROAD_HALF);
    const r = p.clone().addScaledVector(n, -ROAD_HALF);
    positions.push(l.x, 0.06, l.z, r.x, 0.06, r.z);
    uvs.push(0, (u * TRACK_LENGTH) / 14, 1, (u * TRACK_LENGTH) / 14);
    if (i < SEG) {
      const a = i * 2;
      indices.push(a, a + 1, a + 2, a + 1, a + 3, a + 2);
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  geo.setAttribute('uv', new THREE.Float32BufferAttribute(uvs, 2));
  geo.setIndex(indices);
  geo.computeVertexNormals();
  const road = new THREE.Mesh(
    geo,
    new THREE.MeshStandardMaterial({ map: makeRoadTexture(), roughness: 0.92 })
  );
  road.receiveShadow = true;
  scene.add(road);
}

// Горы по горизонту и в центре острова
{
  const rockMat = new THREE.MeshStandardMaterial({ color: 0x7a7f8c, roughness: 1, flatShading: true });
  const snowMat = new THREE.MeshStandardMaterial({ color: 0xf4f7ff, roughness: 0.8, flatShading: true });
  function mountain(x, z, h, r) {
    const m = new THREE.Group();
    const body = new THREE.Mesh(new THREE.ConeGeometry(r, h, 7), rockMat);
    body.position.y = h / 2 - 1;
    const cap = new THREE.Mesh(new THREE.ConeGeometry(r * 0.34, h * 0.34, 7), snowMat);
    cap.position.y = h - h * 0.17 - 1;
    m.add(body, cap);
    m.position.set(x, 0, z);
    scene.add(m);
    if (Math.hypot(x, z) < 280) colliders.push({ x, z, r: r * 0.92 });
  }
  mountain(0, 10, 58, 52);
  mountain(-65, -45, 40, 38);
  mountain(70, 60, 34, 32);
  for (let i = 0; i < 9; i++) {
    const a = (i / 9) * TAU + 0.35;
    mountain(Math.cos(a) * 470, Math.sin(a) * 470, 80 + rnd() * 70, 90 + rnd() * 60);
  }
}

// Деревья и камни — инстансинг для мобильных
{
  const treePos = [];
  let guard = 0;
  while (treePos.length < 200 && guard++ < 4000) {
    const a = rnd() * TAU;
    const r = 24 + rnd() * 246;
    const x = Math.cos(a) * r;
    const z = Math.sin(a) * r;
    const near = nearestSampleIdx({ x, z });
    if (near.dist < 14) continue;
    if (Math.hypot(x, z - 10) < 58) continue; // центральная гора
    if (Math.hypot(x + 65, z + 45) < 42 || Math.hypot(x - 70, z - 60) < 36) continue;
    treePos.push([x, z]);
    if (treePos.length % 3 === 0) colliders.push({ x, z, r: 1.0 });
  }
  const trunkGeo = new THREE.CylinderGeometry(0.32, 0.45, 2.6, 6);
  const trunkMat = new THREE.MeshStandardMaterial({ color: 0x7a4a2a, roughness: 1 });
  const leafGeo = new THREE.ConeGeometry(2.1, 5.2, 7);
  const leafMat = new THREE.MeshStandardMaterial({ color: 0x2e7d32, roughness: 1, flatShading: true });
  const palmGeo = new THREE.SphereGeometry(2.0, 7, 6);
  const palmMat = new THREE.MeshStandardMaterial({ color: 0x4caf50, roughness: 1, flatShading: true });
  const trunks = new THREE.InstancedMesh(trunkGeo, trunkMat, treePos.length);
  const pines = new THREE.InstancedMesh(leafGeo, leafMat, treePos.length);
  const palms = new THREE.InstancedMesh(palmGeo, palmMat, treePos.length);
  const dummy = new THREE.Object3D();
  treePos.forEach(([x, z], i) => {
    const s = 0.8 + rnd() * 0.9;
    dummy.position.set(x, 1.3 * s, z);
    dummy.scale.setScalar(s);
    dummy.rotation.set(0, rnd() * TAU, 0);
    dummy.updateMatrix();
    trunks.setMatrixAt(i, dummy.matrix);
    const isPine = i % 2 === 0;
    dummy.position.y = (2.6 + (isPine ? 2.4 : 1.4)) * s;
    dummy.scale.set(s, s * (isPine ? 1 : 0.6), s);
    dummy.updateMatrix();
    (isPine ? pines : palms).setMatrixAt(i, dummy.matrix);
    // вторую крону прячем под землю
    dummy.position.y = -30;
    dummy.updateMatrix();
    (isPine ? palms : pines).setMatrixAt(i, dummy.matrix);
  });
  trunks.castShadow = pines.castShadow = palms.castShadow = true;
  scene.add(trunks, pines, palms);

  const rockGeo = new THREE.DodecahedronGeometry(1.1, 0);
  const rockMat2 = new THREE.MeshStandardMaterial({ color: 0x8b8f99, roughness: 1, flatShading: true });
  const rocks = new THREE.InstancedMesh(rockGeo, rockMat2, 50);
  for (let i = 0; i < 50; i++) {
    let x, z;
    do {
      const a = rnd() * TAU;
      const r = 30 + rnd() * 235;
      x = Math.cos(a) * r;
      z = Math.sin(a) * r;
    } while (nearestSampleIdx({ x, z }).dist < 11);
    dummy.position.set(x, 0.4, z);
    dummy.rotation.set(rnd() * 3, rnd() * 3, rnd() * 3);
    dummy.scale.setScalar(0.6 + rnd() * 1.6);
    dummy.updateMatrix();
    rocks.setMatrixAt(i, dummy.matrix);
  }
  rocks.castShadow = true;
  scene.add(rocks);
}

// Фестивальная зона у старта: арка, шатры, дома, воздушные шары
const balloons = [];
{
  const start = pointAtS(0);
  const arch = new THREE.Group();
  const pillarMat = new THREE.MeshStandardMaterial({ color: 0x22263a, roughness: 0.6 });
  [-1, 1].forEach((side) => {
    const pillar = new THREE.Mesh(new THREE.BoxGeometry(1.4, 9, 1.4), pillarMat);
    pillar.position.set(side * (ROAD_HALF + 1.4), 4.5, 0);
    pillar.castShadow = true;
    arch.add(pillar);
    const ball = new THREE.Mesh(
      new THREE.SphereGeometry(0.8, 10, 10),
      new THREE.MeshStandardMaterial({ color: side > 0 ? 0xff5e3a : 0x2ee6ff, emissive: 0x442200 })
    );
    ball.position.set(side * (ROAD_HALF + 1.4), 9.6, 0);
    arch.add(ball);
  });
  const banner = new THREE.Mesh(
    new THREE.BoxGeometry(ROAD_HALF * 2 + 4.5, 2.6, 0.4),
    new THREE.MeshBasicMaterial({ map: makeBannerTexture() })
  );
  banner.position.y = 8.2;
  arch.add(banner);
  arch.position.copy(start.pos);
  arch.rotation.y = start.yaw;
  scene.add(arch);

  // шатры фестиваля
  const tentColors = [0xff5e3a, 0xffb03a, 0x2ee6ff, 0xb44aff, 0xff3a7a, 0x37c978];
  for (let i = 0; i < 10; i++) {
    const s = -30 + i * 9 + rnd() * 4;
    const side = i % 2 ? 1 : -1;
    const p = pointAtS(s, side * (ROAD_HALF + 9 + rnd() * 5));
    const tent = new THREE.Group();
    const cone = new THREE.Mesh(
      new THREE.ConeGeometry(3.4, 3.2, 8),
      new THREE.MeshStandardMaterial({ color: tentColors[i % tentColors.length], roughness: 0.8, flatShading: true })
    );
    cone.position.y = 2.6;
    cone.castShadow = true;
    const base = new THREE.Mesh(
      new THREE.CylinderGeometry(3.2, 3.2, 1.6, 8),
      new THREE.MeshStandardMaterial({ color: 0xf5f0e6, roughness: 0.9 })
    );
    base.position.y = 0.8;
    tent.add(cone, base);
    tent.position.copy(p.pos);
    scene.add(tent);
    colliders.push({ x: p.pos.x, z: p.pos.z, r: 3.4 });
  }

  // домики деревни
  const wallMat = new THREE.MeshStandardMaterial({ color: 0xf2e3c8, roughness: 0.95 });
  const roofMat = new THREE.MeshStandardMaterial({ color: 0xc04a32, roughness: 0.9, flatShading: true });
  for (let i = 0; i < 12; i++) {
    const s = (TRACK_LENGTH / 12) * i + 40;
    const side = i % 2 ? 1 : -1;
    const p = pointAtS(s, side * (ROAD_HALF + 16 + rnd() * 12));
    if (Math.hypot(p.pos.x, p.pos.z) > 265) continue;
    const house = new THREE.Group();
    const w = 5 + rnd() * 3;
    const walls = new THREE.Mesh(new THREE.BoxGeometry(w, 3.4, w * 0.8), wallMat);
    walls.position.y = 1.7;
    walls.castShadow = true;
    const roof = new THREE.Mesh(new THREE.ConeGeometry(w * 0.78, 2.4, 4), roofMat);
    roof.position.y = 4.6;
    roof.rotation.y = Math.PI / 4;
    roof.castShadow = true;
    house.add(walls, roof);
    house.position.copy(p.pos);
    house.rotation.y = rnd() * TAU;
    scene.add(house);
    colliders.push({ x: p.pos.x, z: p.pos.z, r: w * 0.62 });
  }

  // воздушные шары праздника
  for (let i = 0; i < 5; i++) {
    const b = new THREE.Group();
    const env = new THREE.Mesh(
      new THREE.SphereGeometry(4.5, 12, 10),
      new THREE.MeshStandardMaterial({ color: tentColors[i % tentColors.length], roughness: 0.5, flatShading: true })
    );
    env.scale.y = 1.15;
    const basket = new THREE.Mesh(
      new THREE.BoxGeometry(1.4, 1.2, 1.4),
      new THREE.MeshStandardMaterial({ color: 0x7a4a2a })
    );
    basket.position.y = -6.4;
    b.add(env, basket);
    const a = (i / 5) * TAU;
    b.position.set(Math.cos(a) * (90 + rnd() * 90), 52 + rnd() * 26, Math.sin(a) * (90 + rnd() * 90));
    b.userData.phase = rnd() * TAU;
    scene.add(b);
    balloons.push(b);
  }

  // облака
  const cloudMat = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 1, transparent: true, opacity: 0.88 });
  for (let i = 0; i < 10; i++) {
    const cl = new THREE.Group();
    for (let j = 0; j < 4; j++) {
      const s = new THREE.Mesh(new THREE.SphereGeometry(4 + rnd() * 5, 8, 6), cloudMat);
      s.position.set(j * 5 - 8 + rnd() * 3, rnd() * 2, rnd() * 4);
      s.scale.y = 0.5;
      cl.add(s);
    }
    const a = rnd() * TAU;
    cl.position.set(Math.cos(a) * (120 + rnd() * 260), 90 + rnd() * 50, Math.sin(a) * (120 + rnd() * 260));
    scene.add(cl);
  }
}

// Ворота чекпоинтов
const cpMeshes = [];
{
  const poleGeo = new THREE.CylinderGeometry(0.28, 0.28, 7, 8);
  CHECKPOINTS.forEach((cp, i) => {
    const grp = new THREE.Group();
    const mat = new THREE.MeshBasicMaterial({ color: 0x7cfc4a, transparent: true, opacity: 0.0 });
    const poleMat = new THREE.MeshStandardMaterial({ color: 0x223, roughness: 0.6 });
    [-1, 1].forEach((side) => {
      const pole = new THREE.Mesh(poleGeo, poleMat);
      pole.position.set(side * (ROAD_HALF + 0.6), 3.5, 0);
      grp.add(pole);
    });
    const beam = new THREE.Mesh(new THREE.BoxGeometry(ROAD_HALF * 2 + 1.2, 6.6, 0.5), mat);
    beam.position.y = 3.3;
    grp.add(beam);
    // световой столб следующего чекпоинта
    const pillar = new THREE.Mesh(
      new THREE.CylinderGeometry(2.6, 2.6, 46, 12, 1, true),
      new THREE.MeshBasicMaterial({
        color: 0x7cfc4a, transparent: true, opacity: 0, side: THREE.DoubleSide, depthWrite: false,
      })
    );
    pillar.position.y = 23;
    grp.add(pillar);
    grp.position.copy(cp.pos);
    grp.rotation.y = cp.yaw;
    grp.visible = false;
    scene.add(grp);
    cpMeshes.push({ grp, beamMat: mat, pillarMat: pillar.material });
  });
}

/* ============================ Модель машины ============================ */
function buildCarMesh(color, accent, isBuggy = false) {
  const car = new THREE.Group();
  const paint = new THREE.MeshStandardMaterial({ color, roughness: 0.32, metalness: 0.55 });
  const dark = new THREE.MeshStandardMaterial({ color: 0x15171f, roughness: 0.5, metalness: 0.3 });
  const glass = new THREE.MeshStandardMaterial({ color: 0x9fd8ff, roughness: 0.12, metalness: 0.7 });

  const body = new THREE.Mesh(new THREE.BoxGeometry(2.0, 0.52, 4.3), paint);
  body.position.y = isBuggy ? 0.78 : 0.56;
  body.castShadow = true;
  car.add(body);

  const nose = new THREE.Mesh(new THREE.BoxGeometry(1.86, 0.34, 1.1), paint);
  nose.position.set(0, (isBuggy ? 0.68 : 0.47), 2.15);
  nose.castShadow = true;
  car.add(nose);

  const cabin = new THREE.Mesh(new THREE.BoxGeometry(1.55, 0.5, 1.9), glass);
  cabin.position.set(0, (isBuggy ? 1.28 : 1.0), -0.25);
  cabin.castShadow = true;
  car.add(cabin);

  if (isBuggy) {
    // дуги безопасности багги
    const rollMat = new THREE.MeshStandardMaterial({ color: accent, roughness: 0.4, metalness: 0.5 });
    [-0.75, 0.75].forEach((x) => {
      const bar = new THREE.Mesh(new THREE.BoxGeometry(0.14, 0.9, 2.2), rollMat);
      bar.position.set(x, 1.35, -0.3);
      car.add(bar);
    });
    const top = new THREE.Mesh(new THREE.BoxGeometry(1.7, 0.14, 2.2), rollMat);
    top.position.set(0, 1.82, -0.3);
    car.add(top);
  } else {
    const spoiler = new THREE.Mesh(new THREE.BoxGeometry(1.95, 0.09, 0.45), dark);
    spoiler.position.set(0, 1.12, -2.05);
    spoiler.castShadow = true;
    car.add(spoiler);
    [-0.7, 0.7].forEach((x) => {
      const strut = new THREE.Mesh(new THREE.BoxGeometry(0.1, 0.4, 0.12), dark);
      strut.position.set(x, 0.9, -2.05);
      car.add(strut);
    });
    // гоночная полоса
    const stripe = new THREE.Mesh(
      new THREE.BoxGeometry(0.55, 0.04, 4.32),
      new THREE.MeshStandardMaterial({ color: accent, roughness: 0.4, emissive: accent, emissiveIntensity: 0.25 })
    );
    stripe.position.y = 0.84;
    car.add(stripe);
  }

  // фары / стопы
  const headMat = new THREE.MeshStandardMaterial({ color: 0xfff6c8, emissive: 0xffe9a0, emissiveIntensity: 1.6 });
  const tailMat = new THREE.MeshStandardMaterial({ color: 0xff2222, emissive: 0xff2222, emissiveIntensity: 1.2 });
  [-0.62, 0.62].forEach((x) => {
    const h = new THREE.Mesh(new THREE.BoxGeometry(0.42, 0.16, 0.08), headMat);
    h.position.set(x, 0.6, 2.71);
    car.add(h);
    const t = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.14, 0.08), tailMat);
    t.position.set(x, 0.68, -2.16);
    car.add(t);
  });

  // неоновая подсветка снизу
  const glow = new THREE.Mesh(
    new THREE.PlaneGeometry(2.9, 5.2),
    new THREE.MeshBasicMaterial({ color: accent, transparent: true, opacity: 0.3, depthWrite: false })
  );
  glow.rotation.x = -Math.PI / 2;
  glow.position.y = 0.13;
  car.add(glow);

  // пламя нитро
  const flame = new THREE.Mesh(
    new THREE.ConeGeometry(0.34, 1.8, 8),
    new THREE.MeshBasicMaterial({ color: 0x4ad2ff, transparent: true, opacity: 0.9 })
  );
  flame.rotation.x = -Math.PI / 2;
  flame.position.set(0, 0.5, -3.0);
  flame.visible = false;
  flame.name = 'flame';
  car.add(flame);

  // колёса
  const wheelGeo = new THREE.CylinderGeometry(isBuggy ? 0.48 : 0.4, isBuggy ? 0.48 : 0.4, 0.34, 14);
  const wheelMat = new THREE.MeshStandardMaterial({ color: 0x111111, roughness: 0.9 });
  const hubMat = new THREE.MeshStandardMaterial({ color: 0xdddddd, roughness: 0.3, metalness: 0.8 });
  const wheels = [];
  const wy = isBuggy ? 0.48 : 0.4;
  [[-1.02, 1.45], [1.02, 1.45], [-1.02, -1.45], [1.02, -1.45]].forEach(([x, z], i) => {
    const pivot = new THREE.Group();
    pivot.position.set(x, wy, z);
    const w = new THREE.Mesh(wheelGeo, wheelMat);
    w.rotation.z = Math.PI / 2;
    w.castShadow = true;
    const hub = new THREE.Mesh(new THREE.CylinderGeometry(0.18, 0.18, 0.38, 8), hubMat);
    hub.rotation.z = Math.PI / 2;
    const spin = new THREE.Group();
    spin.add(w, hub);
    pivot.add(spin);
    car.add(pivot);
    wheels.push({ pivot, spin, front: i < 2 });
  });

  return { group: car, wheels, flame };
}

function createPlayerCar() {
  if (player.mesh) {
    scene.remove(player.mesh.group);
  }
  const built = buildCarMesh(selectedCar.color, selectedCar.accent, selectedCar.id === 'dune');
  player.mesh = built;
  player.wheels = built.wheels;
  scene.add(built.group);
}

/* ============================ Звук (WebAudio) ============================ */
const engine = {
  ctx: null, osc: null, osc2: null, gain: null, enabled: true,
  init() {
    if (this.ctx) { this.ctx.resume(); return; }
    try {
      this.ctx = new (window.AudioContext || window.webkitAudioContext)();
      this.osc = this.ctx.createOscillator();
      this.osc.type = 'sawtooth';
      this.osc2 = this.ctx.createOscillator();
      this.osc2.type = 'square';
      const filter = this.ctx.createBiquadFilter();
      filter.type = 'lowpass';
      filter.frequency.value = 620;
      this.filter = filter;
      this.gain = this.ctx.createGain();
      this.gain.gain.value = 0;
      this.osc.connect(filter);
      this.osc2.connect(filter);
      filter.connect(this.gain);
      this.gain.connect(this.ctx.destination);
      this.osc.start();
      this.osc2.start();
    } catch (e) { /* без звука — не страшно */ }
  },
  beep(freq, dur = 0.16, vol = 0.22) {
    if (!this.ctx || !this.enabled) return;
    const o = this.ctx.createOscillator();
    const g = this.ctx.createGain();
    o.type = 'sine';
    o.frequency.value = freq;
    g.gain.setValueAtTime(vol, this.ctx.currentTime);
    g.gain.exponentialRampToValueAtTime(0.001, this.ctx.currentTime + dur);
    o.connect(g).connect(this.ctx.destination);
    o.start();
    o.stop(this.ctx.currentTime + dur);
  },
  update(speedRatio, boosting) {
    if (!this.ctx) return;
    const on = this.enabled && (gameState === 'racing' || gameState === 'countdown');
    const targetGain = on ? 0.045 + speedRatio * 0.05 : 0;
    this.gain.gain.setTargetAtTime(targetGain, this.ctx.currentTime, 0.08);
    const rpm = 55 + speedRatio * 190 + (boosting ? 35 : 0);
    this.osc.frequency.setTargetAtTime(rpm, this.ctx.currentTime, 0.05);
    this.osc2.frequency.setTargetAtTime(rpm * 0.5 + 3, this.ctx.currentTime, 0.05);
    this.filter.frequency.setTargetAtTime(420 + speedRatio * 900, this.ctx.currentTime, 0.1);
  },
};

/* ============================ Сообщения / HUD ============================ */
let centerMsgTimer = null;
function showCenterMsg(text, ms = 1900, color = '#fff') {
  const el = $('centerMsg');
  el.textContent = text;
  el.style.color = color;
  el.style.opacity = '1';
  clearTimeout(centerMsgTimer);
  centerMsgTimer = setTimeout(() => (el.style.opacity = '0'), ms);
}

let driftPopupTimer = null;
function showДрифтPopup(points, chain) {
  const el = $('driftPopup');
  el.textContent = chain > 1 ? `ДРИФТ +${points} ×${chain}` : `ДРИФТ +${points}`;
  el.style.opacity = '1';
  clearTimeout(driftPopupTimer);
  driftPopupTimer = setTimeout(() => (el.style.opacity = '0'), 700);
}

function vibrate(ms) {
  if (navigator.vibrate) navigator.vibrate(ms);
}

/* ============================ Старт гонки ============================ */
function resetPlayerToStart() {
  createPlayerCar();
  const start = pointAtS(-6, -2.5);
  player.mesh.group.position.copy(start.pos);
  player.yaw = start.yaw;
  player.vel.set(0, 0, 0);
  player.nitro = 0.7;
  player.score = 0;
  player.driftChain = 0;
  player.s = -6;
  player.sampleAccum = 0;
  player.prevSampleIdx = nearestSampleIdx(start.pos).idx;
  player.nextCP = 1;
  player.lap = 1;
  player.lapStart = 0;
  player.finishTime = null;
  player.boosting = false;
}

function createRivals() {
  rivals.forEach((r) => scene.remove(r.mesh.group));
  rivals = [];
  const count = selectedMode === 'race' ? 5 : 3;
  for (let i = 0; i < count; i++) {
    const built = buildCarMesh(RIVAL_COLORS[i], RIVAL_COLORS[i], false);
    scene.add(built.group);
    rivals.push({
      name: RIVAL_NAMES[i],
      mesh: built,
      s: selectedMode === 'race' ? 6 + i * 7 : 80 + i * 160,
      speed: 0,
      baseSpeed: 29.5 + i * 1.25, // 106–125 км/ч крейсерская, резиновая лента подтянет
      lane: (i % 2 ? 2.8 : -2.8),
      lanePhase: Math.random() * TAU,
      finishTime: null,
    });
  }
}

function startGame() {
  engine.init();
  resetPlayerToStart();
  createRivals();
  raceTime = 0;
  updateCPVisibility();
  $('menu').classList.add('hidden');
  $('finishMenu').classList.add('hidden');
  $('pauseMenu').classList.add('hidden');
  $('hud').classList.remove('hidden');
  showTouchControls(true);
  updateRotateHint();

  if (selectedMode === 'race') {
    gameState = 'countdown';
    countdownT = 3.6;
    countdownShown = '';
    $('hudLap').textContent = `КРУГ 1/${TOTAL_LAPS}`;
  } else {
    gameState = 'racing';
    showCenterMsg('СВОБОДНАЯ ПОЕЗДКА — твой остров! 🗺️', 2600, '#2ee6ff');
    $('hudPosition').textContent = 'FREE';
    $('hudLap').textContent = 'ОТКРЫТЫЙ МИР';
  }
  updateHUDStatic();
}

function updateHUDStatic() {
  $('hudЛучший').textContent = player.лучшийLap ? fmtTime(player.лучшийLap) : '—';
  $('hudScore').textContent = '0';
}

function updateCPVisibility() {
  cpMeshes.forEach((cp, i) => {
    const isNext = selectedMode === 'race' && i === player.nextCP;
    cp.grp.visible = selectedMode === 'race';
    cp.beamMat.opacity = isNext ? 0.35 : 0.05;
    cp.beamMat.color.setHex(isNext ? 0x7cfc4a : 0xffffff);
    cp.pillarMat.opacity = isNext ? 0.35 : 0;
  });
  $('checkpointArrow').style.display = selectedMode === 'race' ? 'block' : 'none';
}

function finishRace() {
  gameState = 'finished';
  player.finishTime = raceTime;
  showTouchControls(false);
  const pos = currentPosition();
  const medals = ['🥇 ЧЕМПИОН ФЕСТИВАЛЯ!', '🥈 Второе место!', '🥉 Третье место!', 'Финиш!', 'Финиш!', 'Финиш!'];
  $('finishTitle').textContent = pos <= 3 ? 'ПОДИУМ! 🎉' : 'Финиш!';
  $('finishPlace').textContent = medals[pos - 1] || 'Финиш!';

  const rows = [
    { name: `ТЫ (${selectedCar.name})`, time: player.finishTime, me: true },
    ...rivals.map((r) => ({
      name: r.name,
      time: r.finishTime ?? estimateRivalTime(r),
      me: false,
    })),
  ].sort((a, b) => a.time - b.time);

  $('finishTable').innerHTML = rows
    .map((r, i) => `<tr class="${r.me ? 'me' : ''}"><td>${i + 1}. ${r.name}</td><td>${fmtTime(r.time)}</td></tr>`)
    .join('');
  $('finishStats').innerHTML =
    `Лучший круг: <b>${player.лучшийLap ? fmtTime(player.лучшийLap) : '—'}</b><br>` +
    `Очки дрифта: <b>${Math.floor(player.score)}</b> 🔥`;
  $('finishMenu').classList.remove('hidden');
  engine.beep(660, 0.25);
  setTimeout(() => engine.beep(880, 0.3), 180);
  vibrate([60, 60, 120]);
}

function estimateRivalTime(r) {
  const remain = TOTAL_LAPS * TRACK_LENGTH - r.s;
  return raceTime + remain / Math.max(r.baseSpeed, 18);
}

function currentPosition() {
  let pos = 1;
  rivals.forEach((r) => {
    if (r.s > player.s) pos++;
  });
  return pos;
}

function respawn() {
  const near = pointAtS(player.s);
  player.mesh.group.position.copy(near.pos);
  player.yaw = near.yaw;
  player.vel.set(0, 0, 0);
  player.prevSampleIdx = nearestSampleIdx(near.pos).idx;
  showCenterMsg('На трассу! ⟲', 900);
}

/* ============================ Физика игрока ============================ */
const _fwd = new THREE.Vector3();
const _right = new THREE.Vector3();

function updatePlayer(dt) {
  const car = selectedCar;
  const pos = player.mesh.group.position;

  _fwd.set(Math.sin(player.yaw), 0, Math.cos(player.yaw));
  _right.set(_fwd.z, 0, -_fwd.x);

  const fwdSpeed = player.vel.dot(_fwd);
  const near = nearestSampleIdx(pos);
  player.offroad = near.dist > ROAD_HALF + 0.6 || Math.hypot(pos.x, pos.z) > 282;
  const inWater = Math.hypot(pos.x, pos.z) > 298;

  // Прогресс вдоль трассы (без скачков через петлю)
  let dIdx = near.idx - player.prevSampleIdx;
  if (dIdx > 400) dIdx -= 800;
  if (dIdx < -400) dIdx += 800;
  if (Math.abs(dIdx) < 60) player.sampleAccum += dIdx;
  player.prevSampleIdx = near.idx;
  player.s = (player.sampleAccum / 800) * TRACK_LENGTH - 6;

  // Управление активно только в гонке
  const canDrive = gameState === 'racing';
  const steerInput = canDrive ? (input.left ? 1 : 0) + (input.right ? -1 : 0) : 0;
  player.drifting = canDrive && input.handbrake && Math.abs(fwdSpeed) > 9;

  // Нитро
  player.boosting = canDrive && input.nitro && player.nitro > 0.02 && fwdSpeed > 2;
  if (player.boosting) {
    player.nitro = Math.max(0, player.nitro - dt * 0.32);
    player.vel.addScaledVector(_fwd, 17 * dt);
  } else {
    player.nitro = Math.min(1, player.nitro + dt * 0.022);
  }

  const topSpeed = car.topSpeed * (player.offroad ? car.offroad : 1) * (player.boosting ? 1.28 : 1) * (inWater ? 0.25 : 1);

  if (canDrive && input.gas) {
    const power = car.engine * clamp(1 - Math.max(fwdSpeed, 0) / (topSpeed * 1.12), 0, 1);
    player.vel.addScaledVector(_fwd, power * dt);
  }
  if (canDrive && input.brake) {
    if (fwdSpeed > 1) {
      player.vel.addScaledVector(_fwd, -34 * dt);
    } else {
      player.vel.addScaledVector(_fwd, -13 * dt); // задний ход
    }
  }

  // Руль
  const speedAbs = Math.abs(fwdSpeed);
  const steerAuthority = clamp(speedAbs / 7, 0, 1) * (1 - clamp(speedAbs / (car.topSpeed * 1.3), 0, 1) * 0.45);
  const steerRate = (player.drifting ? 2.5 : 1.85) * steerAuthority;
  player.yaw += steerInput * steerRate * dt * (fwdSpeed < -0.5 ? -1 : 1);
  player.steerVis = lerp(player.steerVis, steerInput * 0.42, dt * 10);

  // Сцепление: гасим боковой снос
  const newFwdSpeed = player.vel.dot(_fwd);
  const latSpeed = player.vel.dot(_right);
  const grip = player.drifting ? 1.1 : player.offroad ? car.grip * 0.5 : car.grip;
  const latKept = latSpeed * Math.exp(-grip * dt);
  player.vel.copy(_fwd).multiplyScalar(newFwdSpeed).addScaledVector(_right, latKept);

  // Сопротивление
  const drag = player.offroad ? 0.55 : 0.22;
  player.vel.multiplyScalar(Math.exp(-drag * dt * (player.drifting ? 1.5 : 1)));
  if (!input.gas && !input.brake) player.vel.multiplyScalar(Math.exp(-0.35 * dt));

  // Мягкий кап скорости
  const spd = player.vel.length();
  const hardCap = topSpeed * 1.18 + 6;
  if (spd > hardCap) player.vel.multiplyScalar(lerp(1, hardCap / spd, dt * 3));

  pos.addScaledVector(player.vel, dt);
  pos.y = Math.hypot(pos.x, pos.z) > 300 ? -0.55 : 0; // в воде машина «тонет» и ползёт

  // Граница мира
  const distC = Math.hypot(pos.x, pos.z);
  if (distC > 330) {
    pos.x *= 330 / distC;
    pos.z *= 330 / distC;
    player.vel.multiplyScalar(0.4);
  }

  // Столкновения с объектами
  crashCooldown -= dt;
  for (const col of colliders) {
    const dx = pos.x - col.x;
    const dz = pos.z - col.z;
    const rr = col.r + 1.25;
    const d2 = dx * dx + dz * dz;
    if (d2 < rr * rr && d2 > 0.0001) {
      const d = Math.sqrt(d2);
      pos.x = col.x + (dx / d) * rr;
      pos.z = col.z + (dz / d) * rr;
      if (spd > 6 && crashCooldown <= 0) {
        showCenterMsg('💥 СТОЛКНОВЕНИЕ!', 800, '#ff8a6a');
        player.driftChain = 0;
        vibrate(70);
        engine.beep(110, 0.2, 0.3);
        crashCooldown = 0.7;
      }
      player.vel.multiplyScalar(0.45);
    }
  }

  // Столкновения с соперниками
  for (const r of rivals) {
    const rp = r.mesh.group.position;
    const dx = pos.x - rp.x;
    const dz = pos.z - rp.z;
    const d2 = dx * dx + dz * dz;
    if (d2 < 9.5 && d2 > 0.0001) {
      const d = Math.sqrt(d2);
      pos.x = rp.x + (dx / d) * 3.1;
      pos.z = rp.z + (dz / d) * 3.1;
      player.vel.multiplyScalar(0.72);
      if (crashCooldown <= 0) {
        vibrate(40);
        engine.beep(140, 0.12, 0.2);
        crashCooldown = 0.5;
      }
    }
  }

  // Дрифт: очки за угол сноса
  const velLen = player.vel.length();
  const slip = velLen > 8 ? Math.abs(player.vel.dot(_right)) / velLen : 0;
  player.driftChainTimer -= dt;
  if (player.drifting && slip > 0.22 && velLen > 11) {
    if (player.driftChainTimer <= 0) player.driftChain = Math.min(player.driftChain + 1, 8);
    player.driftChainTimer = 1.4;
    const pts = Math.round(slip * velLen * dt * 14) * Math.max(player.driftChain, 1);
    if (pts > 0) {
      player.score += pts;
      player.nitro = Math.min(1, player.nitro + dt * 0.1);
      showДрифтPopup(pts, player.driftChain);
    }
  } else if (player.driftChainTimer <= 0) {
    player.driftChain = 0;
  }

  // Меш: наклон кузова и колёса
  const g = player.mesh.group;
  g.rotation.y = player.yaw;
  g.rotation.z = lerp(g.rotation.z, -player.steerVis * clamp(speedAbs / 30, 0, 1) * 0.09, dt * 6);
  g.rotation.x = lerp(g.rotation.x, (input.gas && canDrive ? -0.02 : input.brake ? 0.025 : 0), dt * 5);
  player.wheels.forEach((w) => {
    if (w.front) w.pivot.rotation.y = player.steerVis;
    w.spin.rotation.x += (fwdSpeed / 0.4) * dt;
  });
  player.mesh.flame.visible = player.boosting;
  if (player.boosting) player.mesh.flame.scale.set(1, 1, 0.8 + Math.random() * 0.55);

  // Чекпоинты и круги
  if (selectedMode === 'race' && gameState === 'racing') {
    const cp = CHECKPOINTS[player.nextCP];
    const d = Math.hypot(pos.x - cp.pos.x, pos.z - cp.pos.z);
    if (d < 12) {
      const wasStart = player.nextCP === 0;
      player.nextCP = (player.nextCP + 1) % CHECKPOINTS.length;
      if (wasStart) {
        const lapTime = raceTime - player.lapStart;
        if (player.lap >= 1 && raceTime > 5) {
          if (!player.лучшийLap || lapTime < player.лучшийLap) {
            player.лучшийLap = lapTime;
            safeSetЛучшийLap(lapTime);
            showCenterMsg(`🏆 РЕКОРД КРУГА: ${fmtTime(lapTime)}!`, 2200, '#ffb03a');
          }
        }
        player.lapStart = raceTime;
        player.lap++;
        if (player.lap > TOTAL_LAPS) {
          updateCPVisibility();
          finishRace();
          return;
        }
        if (player.lap === TOTAL_LAPS) showCenterMsg('🏁 ФИНАЛЬНЫЙ КРУГ!', 2200, '#ffb03a');
        else showCenterMsg(`КРУГ ${player.lap}/${TOTAL_LAPS}`, 1600);
        engine.beep(880, 0.2);
      } else {
        engine.beep(520, 0.08, 0.14);
        vibrate(18);
      }
      player.nitro = Math.min(1, player.nitro + 0.12);
      updateCPVisibility();
    }
  }

  engine.update(clamp(Math.abs(fwdSpeed) / car.topSpeed, 0, 1), player.boosting);
}

/* ============================ Соперники (ИИ) ============================ */
function updateRivals(dt) {
  for (const r of rivals) {
    if (gameState !== 'racing') {
      r.speed = 0;
    } else {
      // Резиновая лента: отстающие чуть быстрее, лидеры — чуть медленнее
      let target = r.baseSpeed;
      if (selectedMode === 'race') {
        const gap = r.s - player.s;
        target += clamp(-gap * 0.012, -3.5, 5.0);
        // в поворотах притормаживают
        const ahead = pointAtS(r.s + 26);
        const nowTan = pointAtS(r.s).tangent;
        const turn = 1 - nowTan.dot(ahead.tangent);
        target *= 1 - clamp(turn * 2.4, 0, 0.42);
      }
      r.speed = lerp(r.speed, target, dt * 0.7);
      r.s += r.speed * dt;
      if (selectedMode === 'race' && r.finishTime === null && r.s >= TOTAL_LAPS * TRACK_LENGTH) {
        r.finishTime = raceTime;
      }
    }
    r.lanePhase += dt * 0.35;
    const lane = r.lane + Math.sin(r.lanePhase) * 1.1;
    const p = pointAtS(r.s, lane);
    const g = r.mesh.group;
    g.position.copy(p.pos);
    g.rotation.y = angleLerp(g.rotation.y, p.yaw, dt * 5);
    r.mesh.wheels.forEach((w) => {
      w.spin.rotation.x += (r.speed / 0.4) * dt;
    });
  }
}

/* ============================ Камера ============================ */
const camTargetPos = new THREE.Vector3();
function updateCamera(dt) {
  if (gameState === 'menu') {
    // Шоурум: камера медленно кружит вокруг выбранной машины у стартовой арки
    menuOrbit += dt * 0.22;
    const center = player.mesh ? player.mesh.group.position : new THREE.Vector3(0, 0, -170);
    const cx = center.x + Math.cos(menuOrbit) * 10.5;
    const cz = center.z + Math.sin(menuOrbit) * 10.5;
    camera.position.lerp(new THREE.Vector3(cx, 3.2, cz), Math.min(dt * 1.6, 1));
    camera.lookAt(center.x, 1.1, center.z);
    camera.fov = lerp(camera.fov, 55, dt * 2);
    camera.updateProjectionMatrix();
    return;
  }
  if (!player.mesh) return;
  const pos = player.mesh.group.position;
  _fwd.set(Math.sin(player.yaw), 0, Math.cos(player.yaw));
  const speedRatio = clamp(player.vel.length() / selectedCar.topSpeed, 0, 1);

  if (cameraMode === 2) {
    // капот
    camTargetPos.copy(pos).addScaledVector(_fwd, 1.4);
    camTargetPos.y = 1.25;
    camera.position.lerp(camTargetPos, Math.min(dt * 22, 1));
    const look = pos.clone().addScaledVector(_fwd, 18);
    look.y = 1.0;
    camera.lookAt(look);
  } else {
    const dist = cameraMode === 0 ? 10.5 + speedRatio * 2.5 : 17;
    const height = cameraMode === 0 ? 4.0 : 7.5;
    camTargetPos.copy(pos).addScaledVector(_fwd, -dist);
    camTargetPos.y = height;
    camera.position.lerp(camTargetPos, Math.min(dt * (cameraMode === 0 ? 4.2 : 3), 1));
    const look = pos.clone().addScaledVector(_fwd, 9);
    look.y = 1.4;
    camera.lookAt(look);
  }
  const targetFov = 68 + (player.boosting ? 10 : speedRatio * 5);
  camera.fov = lerp(camera.fov, targetFov, dt * 4);
  camera.updateProjectionMatrix();
}

/* ============================ HUD + миникарта ============================ */
const minimap = $('minimap').getContext('2d');
let minimapTimer = 0;

function drawMinimap() {
  const S = 132;
  minimap.clearRect(0, 0, S, S);
  const toMap = (x, z) => [S / 2 + (x / 640) * S, S / 2 + (z / 640) * S];
  // остров
  minimap.beginPath();
  minimap.arc(...toMap(0, 0), (290 / 640) * S, 0, TAU);
  minimap.fillStyle = 'rgba(70,140,60,0.35)';
  minimap.fill();
  // трасса
  minimap.beginPath();
  SAMPLES.forEach((p, i) => {
    const [x, y] = toMap(p.x, p.z);
    if (i === 0) minimap.moveTo(x, y);
    else if (i % 4 === 0) minimap.lineTo(x, y);
  });
  minimap.closePath();
  minimap.strokeStyle = 'rgba(255,255,255,0.9)';
  minimap.lineWidth = 3;
  minimap.stroke();
  // следующий чекпоинт
  if (selectedMode === 'race') {
    const cp = CHECKPOINTS[player.nextCP];
    const [x, y] = toMap(cp.pos.x, cp.pos.z);
    minimap.beginPath();
    minimap.arc(x, y, 4.5, 0, TAU);
    minimap.fillStyle = '#7cfc4a';
    minimap.fill();
  }
  // соперники
  rivals.forEach((r, i) => {
    const p = r.mesh.group.position;
    const [x, y] = toMap(p.x, p.z);
    minimap.beginPath();
    minimap.arc(x, y, 3, 0, TAU);
    minimap.fillStyle = '#' + RIVAL_COLORS[i].toString(16).padStart(6, '0');
    minimap.fill();
  });
  // игрок — стрелка по курсу
  if (player.mesh) {
    const p = player.mesh.group.position;
    const [x, y] = toMap(p.x, p.z);
    minimap.save();
    minimap.translate(x, y);
    minimap.rotate(-player.yaw);
    minimap.beginPath();
    minimap.moveTo(0, 6);
    minimap.lineTo(-4, -5);
    minimap.lineTo(4, -5);
    minimap.closePath();
    minimap.fillStyle = '#ff5e3a';
    minimap.strokeStyle = '#fff';
    minimap.lineWidth = 1.2;
    minimap.fill();
    minimap.stroke();
    minimap.restore();
  }
}

function updateHUD(dt) {
  if (!player.mesh) return;
  const kmh = Math.round(player.vel.length() * 3.6);
  $('hudSpeed').textContent = kmh;
  $('nitroFill').style.width = `${Math.round(player.nitro * 100)}%`;
  document.querySelector('.nitro-bar').classList.toggle('boosting', player.boosting);
  $('offroadTag').classList.toggle('hidden', !player.offroad);
  $('hudTime').textContent = fmtTime(raceTime);
  $('hudScore').textContent = Math.floor(player.score).toLocaleString('ru-RU');
  $('hudЛучший').textContent = player.лучшийLap ? fmtTime(player.лучшийLap) : '—';

  if (selectedMode === 'race') {
    $('hudPosition').textContent = `${currentPosition()}/${rivals.length + 1}`;
    $('hudLap').textContent = `КРУГ ${Math.min(player.lap, TOTAL_LAPS)}/${TOTAL_LAPS}`;
    const cp = CHECKPOINTS[player.nextCP];
    const pos = player.mesh.group.position;
    const d = Math.hypot(pos.x - cp.pos.x, pos.z - cp.pos.z);
    $('hudCheckpoint').textContent = `🎯 ${Math.round(d)} м`;
    // стрелка к чекпоинту
    const toCP = Math.atan2(cp.pos.x - pos.x, cp.pos.z - pos.z);
    let rel = toCP - player.yaw;
    $('checkpointArrow').style.transform = `translateX(-50%) rotate(${-rel}rad)`;
  }

  minimapTimer -= dt;
  if (minimapTimer <= 0) {
    drawMinimap();
    minimapTimer = 0.08;
  }
}

/* ============================ Обратный отсчёт ============================ */
function updateCountdown(dt) {
  countdownT -= dt;
  const el = $('countdown');
  let text = '';
  if (countdownT > 2.6) text = '3';
  else if (countdownT > 1.7) text = '2';
  else if (countdownT > 0.8) text = '1';
  else if (countdownT > 0) text = 'ГО! 🏁';
  if (text !== countdownShown) {
    countdownShown = text;
    el.textContent = text;
    el.classList.remove('pop');
    void el.offsetWidth;
    el.classList.add('pop');
    engine.beep(text === 'ГО! 🏁' ? 990 : 440, 0.18);
    if (text === 'ГО! 🏁') {
      gameState = 'racing';
      player.lapStart = 0;
      vibrate(60);
      setTimeout(() => {
        if (gameState === 'racing') el.textContent = '';
      }, 750);
    }
  }
  if (countdownT <= -0.7) el.textContent = '';
}

/* ============================ Главный цикл ============================ */
const clock = new THREE.Clock();

function animate() {
  requestAnimationFrame(animate);
  const dt = Math.min(clock.getDelta(), 0.05);
  const t = clock.elapsedTime;

  // шары покачиваются
  balloons.forEach((b) => {
    b.position.y += Math.sin(t * 0.5 + b.userData.phase) * dt * 1.4;
    b.position.x += dt * 1.1;
    if (b.position.x > 340) b.position.x = -340;
  });

  // пульс следующего чекпоинта
  if (selectedMode === 'race' && player.mesh) {
    const cp = cpMeshes[player.nextCP];
    if (cp) cp.pillarMat.opacity = 0.26 + Math.sin(t * 4) * 0.1;
  }

  if (gameState === 'countdown') updateCountdown(dt);
  if (gameState === 'racing') raceTime += dt;
  if (gameState === 'racing' || gameState === 'countdown' || gameState === 'finished') {
    if (gameState !== 'finished') updatePlayer(dt);
    else {
      // после финиша машина докатывается
      player.vel.multiplyScalar(Math.exp(-0.8 * dt));
      player.mesh.group.position.addScaledVector(player.vel, dt);
      engine.update(0.1, false);
    }
    updateRivals(dt);
    updateHUD(dt);
  }

  // тень следует за игроком — дешевле для мобильных
  if (player.mesh && gameState !== 'menu') {
    const p = player.mesh.group.position;
    sun.position.set(p.x - 90, 110, p.z - 60);
    sun.target.position.copy(p);
  } else {
    sun.position.set(-90, 110, -140);
    sun.target.position.set(0, 0, -60);
  }

  updateCamera(dt);
  renderer.render(scene, camera);
}

/* ============================ Управление: клавиатура ============================ */
const KEYMAP = {
  KeyW: 'gas', ArrowUp: 'gas',
  KeyS: 'brake', ArrowDown: 'brake',
  KeyA: 'left', ArrowLeft: 'left',
  KeyD: 'right', ArrowRight: 'right',
  ShiftLeft: 'nitro', ShiftRight: 'nitro',
  Space: 'handbrake',
};
window.addEventListener('keydown', (e) => {
  const k = KEYMAP[e.code];
  if (k) {
    input[k] = true;
    e.preventDefault();
  }
  if (e.code === 'KeyC') cycleCamera();
  if (e.code === 'KeyR' && gameState === 'racing') respawn();
  if (e.code === 'Escape' && (gameState === 'racing' || gameState === 'countdown')) pauseGame();
  else if (e.code === 'Escape' && gameState === 'paused') resumeGame();
});
window.addEventListener('keyup', (e) => {
  const k = KEYMAP[e.code];
  if (k) input[k] = false;
});
window.addEventListener('blur', () => Object.keys(input).forEach((k) => (input[k] = false)));

/* ============================ Управление: тач ============================ */
function showTouchControls(show) {
  const el = $('touchControls');
  el.classList.toggle('hidden', !show);
  // На десктопе с мышью кнопки не нужны — но оставим класс для CSS
  const isDesktop = window.matchMedia('(hover: hover) and (pointer: fine)').matches;
  el.classList.toggle('force-hide', isDesktop);
}

function bindHold(btn, key) {
  const on = (e) => {
    e.preventDefault();
    input[key] = true;
    btn.classList.add('pressed');
  };
  const off = (e) => {
    e.preventDefault();
    input[key] = false;
    btn.classList.remove('pressed');
  };
  btn.addEventListener('pointerdown', on);
  btn.addEventListener('pointerup', off);
  btn.addEventListener('pointerleave', off);
  btn.addEventListener('pointercancel', off);
  btn.addEventListener('contextmenu', (e) => e.preventDefault());
}

bindHold($('btnGas'), 'gas');
bindHold($('btnBrake'), 'brake');
bindHold($('btnLeft'), 'left');
bindHold($('btnRight'), 'right');
bindHold($('btnNitro'), 'nitro');
bindHold($('btnДрифт'), 'handbrake');

document.addEventListener('touchmove', (e) => {
  if (gameState === 'racing' || gameState === 'countdown') e.preventDefault();
}, { passive: false });

/* ============================ UI: меню и кнопки ============================ */
function buildCarPicker() {
  const wrap = $('carPicker');
  wrap.innerHTML = '';
  CARS.forEach((car) => {
    const btn = document.createElement('button');
    btn.className = 'car-card' + (car === selectedCar ? ' selected' : '');
    btn.innerHTML = `
      <div class="car-swatch" style="background:#${car.color.toString(16).padStart(6, '0')}">${car.emoji}</div>
      <div class="car-name">${car.name}</div>
      <div class="car-class">${car.cls}</div>
      <div class="stat">СКОР.<span class="bar"><i style="width:${car.stats.spd * 100}%"></i></span></div>
      <div class="stat">РАЗГОН<span class="bar"><i style="width:${car.stats.acc * 100}%"></i></span></div>
      <div class="stat">УПРАВЛ.<span class="bar"><i style="width:${car.stats.hnd * 100}%"></i></span></div>
      <div class="stat">ГРУНТ<span class="bar"><i style="width:${car.stats.off * 100}%"></i></span></div>`;
    btn.addEventListener('click', () => {
      selectedCar = car;
      buildCarPicker();
      previewCarInMenu();
    });
    wrap.appendChild(btn);
  });
}

function previewCarInMenu() {
  createPlayerCar();
  const start = pointAtS(-10, 0);
  player.mesh.group.position.copy(start.pos);
  player.mesh.group.rotation.y = start.yaw + 0.6;
  player.yaw = start.yaw + 0.6;
}

document.querySelectorAll('.mode-btn').forEach((btn) => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.mode-btn').forEach((b) => b.classList.remove('active'));
    btn.classList.add('active');
    selectedMode = btn.dataset.mode;
  });
});

function cycleCamera() {
  cameraMode = (cameraMode + 1) % 3;
  const names = ['Камера: погоня 🎥', 'Камера: издалека 🎥', 'Камера: капот 🎥'];
  showCenterMsg(names[cameraMode], 900);
}

function pauseGame() {
  if (gameState !== 'racing' && gameState !== 'countdown') return;
  player.prevState = gameState;
  gameState = 'paused';
  $('pauseMenu').classList.remove('hidden');
  showTouchControls(false);
  engine.update(0, false);
}

function resumeGame() {
  gameState = player.prevState || 'racing';
  $('pauseMenu').classList.add('hidden');
  showTouchControls(true);
  clock.getDelta();
}

function toMenu() {
  gameState = 'menu';
  $('pauseMenu').classList.add('hidden');
  $('finishMenu').classList.add('hidden');
  $('hud').classList.add('hidden');
  showTouchControls(false);
  $('menu').classList.remove('hidden');
  $('countdown').textContent = '';
  previewCarInMenu();
  rivals.forEach((r) => scene.remove(r.mesh.group));
  rivals = [];
  cpMeshes.forEach((cp) => (cp.grp.visible = false));
}

$('btnStart').addEventListener('click', startGame);
$('btnPause').addEventListener('click', pauseGame);
$('btnResume').addEventListener('click', resumeGame);
$('btnRestart').addEventListener('click', startGame);
$('btnToMenu').addEventListener('click', toMenu);
$('btnRaceAgain').addEventListener('click', startGame);
$('btnFinishToMenu').addEventListener('click', toMenu);
$('btnCamera').addEventListener('click', cycleCamera);
$('btnRespawn').addEventListener('click', () => gameState === 'racing' && respawn());
$('btnSound').addEventListener('click', () => {
  engine.enabled = !engine.enabled;
  $('btnSound').textContent = engine.enabled ? '🔊' : '🔇';
  engine.init();
});

/* ============================ Поворот экрана / ресайз ============================ */
function updateRotateHint() {
  const portrait = window.innerHeight > window.innerWidth;
  const inGame = gameState === 'racing' || gameState === 'countdown';
  $('rotateHint').classList.toggle('hidden', !(portrait && inGame));
}

window.addEventListener('resize', () => {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  updateRotateHint();
});

/* ============================ Старт ============================ */
buildCarPicker();
previewCarInMenu();
drawMinimap();
animate();

// PWA: офлайн-кэш только в продакшен-сборке
if (import.meta.env.PROD && 'serviceWorker' in navigator) {
  navigator.serviceWorker.register('/sw.js').catch(() => {});
}
