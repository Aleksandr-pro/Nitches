import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { buildGTR35, GTR_PAINTS } from './gtr.js';
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

function smoothstep(a, b, x) {
  const t = clamp((x - a) / (b - a), 0, 1);
  return t * t * (3 - 2 * t);
}
// Value-noise + FBM: рельеф острова и пятна на текстурах
function hashNoise2(ix, iz) {
  let n = Math.sin(ix * 127.1 + iz * 311.7) * 43758.5453123;
  return n - Math.floor(n);
}
function valueNoise2(x, z) {
  const ix = Math.floor(x);
  const iz = Math.floor(z);
  const fx = x - ix;
  const fz = z - iz;
  const sx = fx * fx * (3 - 2 * fx);
  const sz = fz * fz * (3 - 2 * fz);
  const a = hashNoise2(ix, iz);
  const b = hashNoise2(ix + 1, iz);
  const c = hashNoise2(ix, iz + 1);
  const d = hashNoise2(ix + 1, iz + 1);
  return lerp(lerp(a, b, sx), lerp(c, d, sx), sz);
}
function fbm2(x, z, octaves = 4) {
  let v = 0;
  let amp = 0.5;
  let f = 1;
  for (let i = 0; i < octaves; i++) {
    v += amp * valueNoise2(x * f, z * f);
    f *= 2.03;
    amp *= 0.5;
  }
  return v;
}

/* ============================ Машины игрока ============================ */
const CARS = [
  {
    id: 'gtr35',
    name: 'GT-R35 GODZILLA',
    cls: 'Класс S1 • детализированная модель R35',
    emoji: '🇯🇵',
    color: 0x1167b1,
    accent: 0x2e7bff,
    topSpeed: 64, // ≈ 230 км/ч
    engine: 34,
    grip: 10,
    offroad: 0.5,
    stats: { spd: 0.98, acc: 0.99, hnd: 0.96, off: 0.3 },
  },
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
function safeGetItem(key) {
  try { return localStorage.getItem(key); } catch (e) { return null; }
}
function safeSetItem(key, value) {
  try { localStorage.setItem(key, String(value)); } catch (e) { /* noop */ }
}

let selectedGTRPaint = Number(safeGetItem('nh_gtr_paint')) || GTR_PAINTS[0].hex;
if (!GTR_PAINTS.some((paint) => paint.hex === selectedGTRPaint)) selectedGTRPaint = GTR_PAINTS[0].hex;
CARS[0].color = selectedGTRPaint;
let graphicsQuality = safeGetItem('nh_gfx') === 'fast' ? 'fast' : 'realistic';

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
  groundPitch: 0,
  groundRoll: 0,
  groundH: 0,
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
renderer.toneMappingExposure = 1.18;
const MAX_ANISO = renderer.capabilities.getMaxAnisotropy();

const scene = new THREE.Scene();
scene.fog = new THREE.Fog(0xe8a06d, 150, 780);

const camera = new THREE.PerspectiveCamera(62, window.innerWidth / window.innerHeight, 0.1, 2000);
camera.position.set(0, 26, -140);

// Свет заката фестиваля
scene.add(new THREE.HemisphereLight(0x9fc4ff, 0x8a5a34, 0.55));
const sun = new THREE.DirectionalLight(0xffb377, 2.7);
sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048);
sun.shadow.radius = 4;
sun.shadow.normalBias = 0.02;
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
  c.width = c.height = 512;
  const g = c.getContext('2d');
  g.fillStyle = '#2f3136';
  g.fillRect(0, 0, 512, 512);
  // крупные пятна старого/нового асфальта
  for (let i = 0; i < 90; i++) {
    g.fillStyle = `rgba(${20 + Math.random() * 35},${22 + Math.random() * 35},${26 + Math.random() * 35},${0.08 + Math.random() * 0.16})`;
    g.beginPath();
    g.ellipse(Math.random() * 512, Math.random() * 512, 30 + Math.random() * 120, 18 + Math.random() * 70, Math.random() * 3, 0, Math.PI * 2);
    g.fill();
  }
  // мелкое зерно
  for (let i = 0; i < 15000; i++) {
    const v = 120 + Math.random() * 130;
    g.fillStyle = `rgba(${v},${v},${v},${Math.random() * 0.13})`;
    g.fillRect(Math.random() * 512, Math.random() * 512, 1.6, 1.6);
  }
  // тёмные колеи от шин
  [126, 386].forEach((x) => {
    const grad = g.createLinearGradient(x - 42, 0, x + 42, 0);
    grad.addColorStop(0, 'rgba(0,0,0,0)');
    grad.addColorStop(0.5, 'rgba(0,0,0,0.34)');
    grad.addColorStop(1, 'rgba(0,0,0,0)');
    g.fillStyle = grad;
    g.fillRect(x - 42, 0, 84, 512);
  });
  // трещины и гудронные швы
  g.strokeStyle = 'rgba(8,8,10,0.5)';
  for (let i = 0; i < 16; i++) {
    g.lineWidth = 1 + Math.random() * 2;
    g.beginPath();
    let x = Math.random() * 512;
    let y = Math.random() * 512;
    g.moveTo(x, y);
    for (let j = 0; j < 5; j++) {
      x += (Math.random() - 0.5) * 90;
      y += Math.random() * 55;
      g.lineTo(x, y);
    }
    g.stroke();
  }
  g.fillStyle = 'rgba(10,10,12,0.35)';
  g.fillRect(0, 250, 512, 7);
  // красно-белые поребрики
  for (let y = 0; y < 8; y++) {
    g.fillStyle = y % 2 ? '#dedbd4' : '#c6372b';
    g.fillRect(0, y * 64, 24, 64);
    g.fillStyle = y % 2 ? '#c6372b' : '#dedbd4';
    g.fillRect(488, y * 64, 24, 64);
  }
  // потёртые крайние линии
  g.fillStyle = 'rgba(240,240,235,0.92)';
  g.fillRect(38, 0, 8, 512);
  g.fillRect(466, 0, 8, 512);
  // центральная прерывистая
  g.fillStyle = 'rgba(248,207,72,0.94)';
  g.fillRect(250, 34, 12, 150);
  // вытираем краску зерном асфальта
  for (let i = 0; i < 2600; i++) {
    g.fillStyle = `rgba(47,49,54,${Math.random() * 0.55})`;
    const zones = [[0, 24], [488, 24], [38, 8], [466, 8], [250, 12]];
    const [zx, zw] = zones[(Math.random() * zones.length) | 0];
    g.fillRect(zx + Math.random() * zw, Math.random() * 512, 2.4, 2.4);
  }
  const tex = new THREE.CanvasTexture(c);
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = MAX_ANISO;
  return tex;
}

function makeGroundTexture() {
  // Нейтральная микродеталь: основной цвет задают вершинные цвета рельефа
  const c = document.createElement('canvas');
  c.width = c.height = 512;
  const g = c.getContext('2d');
  g.fillStyle = '#c7cabb';
  g.fillRect(0, 0, 512, 512);
  for (let i = 0; i < 240; i++) {
    const v = 150 + Math.random() * 80;
    g.fillStyle = `rgba(${v * 0.82},${v},${v * 0.72},${0.05 + Math.random() * 0.1})`;
    g.beginPath();
    g.ellipse(Math.random() * 512, Math.random() * 512, 12 + Math.random() * 55, 8 + Math.random() * 35, Math.random() * 3, 0, Math.PI * 2);
    g.fill();
  }
  for (let i = 0; i < 15000; i++) {
    const v = 120 + Math.random() * 110;
    g.fillStyle = `rgba(${v * 0.8},${v},${v * 0.68},${Math.random() * 0.25})`;
    g.fillRect(Math.random() * 512, Math.random() * 512, 2, 2 + Math.random() * 3);
  }
  // травинки-штрихи
  g.lineWidth = 1;
  for (let i = 0; i < 2500; i++) {
    const x = Math.random() * 512;
    const y = Math.random() * 512;
    g.strokeStyle = `rgba(70,${110 + Math.random() * 70},55,0.35)`;
    g.beginPath();
    g.moveTo(x, y);
    g.lineTo(x + (Math.random() - 0.5) * 4, y - 3 - Math.random() * 5);
    g.stroke();
  }
  const tex = new THREE.CanvasTexture(c);
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.repeat.set(72, 72);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = MAX_ANISO;
  return tex;
}

function makeSkyTexture() {
  const c = document.createElement('canvas');
  c.width = 1024;
  c.height = 512;
  const g = c.getContext('2d');
  const grad = g.createLinearGradient(0, 0, 0, 512);
  grad.addColorStop(0, '#1d3e74');
  grad.addColorStop(0.34, '#4c72b5');
  grad.addColorStop(0.55, '#b97a79');
  grad.addColorStop(0.68, '#ff9d54');
  grad.addColorStop(0.78, '#ffc06a');
  grad.addColorStop(1, '#8a4b32');
  g.fillStyle = grad;
  g.fillRect(0, 0, 1024, 512);
  // высокие перистые облака ленточками
  for (let i = 0; i < 46; i++) {
    const y = 85 + Math.random() * 215;
    const w = 90 + Math.random() * 280;
    const x = Math.random() * 1024;
    const cg = g.createRadialGradient(x, y, 2, x, y, w / 2);
    const warm = y > 210;
    cg.addColorStop(0, warm ? 'rgba(255,190,145,0.23)' : 'rgba(240,244,255,0.18)');
    cg.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = cg;
    g.save();
    g.translate(x, y);
    g.scale(1, 0.16 + Math.random() * 0.12);
    g.beginPath();
    g.arc(0, 0, w / 2, 0, Math.PI * 2);
    g.fill();
    g.restore();
  }
  // первые звёзды в зените
  g.fillStyle = 'rgba(255,255,255,0.55)';
  for (let i = 0; i < 130; i++) {
    g.globalAlpha = Math.random() * 0.55;
    g.fillRect(Math.random() * 1024, Math.random() * 105, 1.4, 1.4);
  }
  g.globalAlpha = 1;
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

function makeEnvironmentTexture() {
  // Панорама для PBR-отражений на лаке/стекле/воде
  const c = document.createElement('canvas');
  c.width = 1024;
  c.height = 512;
  const g = c.getContext('2d');
  const grad = g.createLinearGradient(0, 0, 0, 512);
  grad.addColorStop(0, '#2d5b9e');
  grad.addColorStop(0.42, '#89aed4');
  grad.addColorStop(0.58, '#ffb06a');
  grad.addColorStop(0.62, '#6b6b58');
  grad.addColorStop(1, '#2e2b24');
  g.fillStyle = grad;
  g.fillRect(0, 0, 1024, 512);
  const sunGrad = g.createRadialGradient(760, 292, 2, 760, 292, 190);
  sunGrad.addColorStop(0, 'rgba(255,255,235,1)');
  sunGrad.addColorStop(0.12, 'rgba(255,205,110,0.95)');
  sunGrad.addColorStop(1, 'rgba(255,150,60,0)');
  g.fillStyle = sunGrad;
  g.fillRect(520, 80, 480, 390);
  g.fillStyle = 'rgba(40,48,42,0.85)';
  g.beginPath();
  g.moveTo(0, 320);
  for (let x = 0; x <= 1024; x += 64) {
    g.lineTo(x, 306 + Math.sin(x * 0.021) * 13 + Math.sin(x * 0.007) * 9);
  }
  g.lineTo(1024, 512);
  g.lineTo(0, 512);
  g.fill();
  const tex = new THREE.CanvasTexture(c);
  tex.mapping = THREE.EquirectangularReflectionMapping;
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

function makeGlowTexture() {
  const c = document.createElement('canvas');
  c.width = c.height = 256;
  const g = c.getContext('2d');
  const grad = g.createRadialGradient(128, 128, 2, 128, 128, 128);
  grad.addColorStop(0, 'rgba(255,240,200,1)');
  grad.addColorStop(0.25, 'rgba(255,180,90,0.46)');
  grad.addColorStop(1, 'rgba(255,140,60,0)');
  g.fillStyle = grad;
  g.fillRect(0, 0, 256, 256);
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

function makeWaterNormalTexture() {
  // Бесшовная карта нормалей из суммы периодических волн
  const size = 256;
  const heights = new Float32Array(size * size);
  const waves = [
    [3, 1, 0.5, 1.0], [5, -2, 2.1, 0.55], [-2, 6, 4.0, 0.45],
    [8, 3, 1.3, 0.3], [-6, -4, 5.2, 0.24], [11, 7, 0.4, 0.15],
  ];
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      let h = 0;
      waves.forEach(([kx, ky, ph, amp]) => {
        h += Math.sin(((kx * x + ky * y) / size) * Math.PI * 2 + ph) * amp;
      });
      heights[y * size + x] = h;
    }
  }
  const c = document.createElement('canvas');
  c.width = c.height = size;
  const g = c.getContext('2d');
  const img = g.createImageData(size, size);
  const at = (x, y) => heights[((y + size) % size) * size + ((x + size) % size)];
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const dx = (at(x + 1, y) - at(x - 1, y)) * 1.15;
      const dy = (at(x, y + 1) - at(x, y - 1)) * 1.15;
      const inv = 1 / Math.hypot(dx, dy, 1);
      const i = (y * size + x) * 4;
      img.data[i] = (-dx * inv * 0.5 + 0.5) * 255;
      img.data[i + 1] = (-dy * inv * 0.5 + 0.5) * 255;
      img.data[i + 2] = inv * 255;
      img.data[i + 3] = 255;
    }
  }
  g.putImageData(img, 0, 0);
  const tex = new THREE.CanvasTexture(c);
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.repeat.set(28, 28);
  return tex;
}

function makeRockTexture() {
  const c = document.createElement('canvas');
  c.width = c.height = 256;
  const g = c.getContext('2d');
  g.fillStyle = '#77716a';
  g.fillRect(0, 0, 256, 256);
  for (let i = 0; i < 300; i++) {
    const v = 85 + Math.random() * 90;
    g.fillStyle = `rgba(${v},${v * 0.96},${v * 0.88},${0.12 + Math.random() * 0.22})`;
    g.beginPath();
    g.ellipse(Math.random() * 256, Math.random() * 256, 12 + Math.random() * 55, 5 + Math.random() * 22, (Math.random() - 0.5) * 0.5, 0, Math.PI * 2);
    g.fill();
  }
  g.strokeStyle = 'rgba(45,42,38,0.45)';
  for (let i = 0; i < 42; i++) {
    g.lineWidth = 1 + Math.random() * 2;
    g.beginPath();
    const y = Math.random() * 256;
    g.moveTo(0, y);
    g.bezierCurveTo(80, y + (Math.random() - 0.5) * 22, 170, y + (Math.random() - 0.5) * 22, 256, y + (Math.random() - 0.5) * 16);
    g.stroke();
  }
  const tex = new THREE.CanvasTexture(c);
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.repeat.set(3, 3);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = MAX_ANISO;
  return tex;
}

function makeLeafTexture() {
  const c = document.createElement('canvas');
  c.width = c.height = 256;
  const g = c.getContext('2d');
  g.fillStyle = '#557f3d';
  g.fillRect(0, 0, 256, 256);
  for (let i = 0; i < 4200; i++) {
    const gr = 95 + Math.random() * 105;
    g.fillStyle = `rgba(${gr * 0.55},${gr},${gr * 0.42},${0.25 + Math.random() * 0.5})`;
    g.save();
    g.translate(Math.random() * 256, Math.random() * 256);
    g.rotate(Math.random() * Math.PI);
    g.fillRect(-3, -1, 6 + Math.random() * 5, 2.2);
    g.restore();
  }
  const tex = new THREE.CanvasTexture(c);
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.repeat.set(2, 2);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

function makeBarkTexture() {
  const c = document.createElement('canvas');
  c.width = 128;
  c.height = 256;
  const g = c.getContext('2d');
  g.fillStyle = '#6f4a2f';
  g.fillRect(0, 0, 128, 256);
  for (let i = 0; i < 160; i++) {
    const x = Math.random() * 128;
    g.strokeStyle = `rgba(${35 + Math.random() * 55},${22 + Math.random() * 38},14,${0.3 + Math.random() * 0.45})`;
    g.lineWidth = 1 + Math.random() * 3;
    g.beginPath();
    g.moveTo(x, -8);
    g.bezierCurveTo(x + 8, 70, x - 8, 160, x + 5, 264);
    g.stroke();
  }
  const tex = new THREE.CanvasTexture(c);
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

function makeFacadeTexture(base = '#e8dcc5', shutter = '#31556e') {
  const c = document.createElement('canvas');
  c.width = c.height = 256;
  const g = c.getContext('2d');
  g.fillStyle = base;
  g.fillRect(0, 0, 256, 256);
  for (let i = 0; i < 1800; i++) {
    g.fillStyle = `rgba(90,75,55,${Math.random() * 0.08})`;
    g.fillRect(Math.random() * 256, Math.random() * 256, 3, 3);
  }
  function window_(x, y, w, h, warm) {
    g.fillStyle = '#f7f2e7';
    g.fillRect(x - 5, y - 5, w + 10, h + 10);
    const grad = g.createLinearGradient(x, y, x + w, y + h);
    grad.addColorStop(0, warm ? '#ffd27a' : '#87b5cf');
    grad.addColorStop(0.55, warm ? '#b97236' : '#28465e');
    grad.addColorStop(1, '#162738');
    g.fillStyle = grad;
    g.fillRect(x, y, w, h);
    g.strokeStyle = '#f7f2e7';
    g.lineWidth = 3;
    g.beginPath();
    g.moveTo(x + w / 2, y);
    g.lineTo(x + w / 2, y + h);
    g.moveTo(x, y + h / 2);
    g.lineTo(x + w, y + h / 2);
    g.stroke();
    g.fillStyle = shutter;
    g.fillRect(x - 17, y - 3, 11, h + 6);
    g.fillRect(x + w + 6, y - 3, 11, h + 6);
  }
  window_(24, 38, 38, 54, false);
  window_(109, 38, 38, 54, true);
  window_(194, 38, 38, 54, false);
  window_(24, 142, 38, 54, true);
  window_(109, 142, 38, 54, false);
  // дверь входная ~2.1 м при высоте фасада 5.8 м
  g.fillStyle = '#5a3825';
  g.fillRect(194, 148, 38, 108);
  g.fillStyle = '#d8b36a';
  g.beginPath();
  g.arc(224, 204, 3.5, 0, Math.PI * 2);
  g.fill();
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = MAX_ANISO;
  return tex;
}

function makeGrassBladeTexture() {
  const c = document.createElement('canvas');
  c.width = c.height = 128;
  const g = c.getContext('2d');
  g.clearRect(0, 0, 128, 128);
  for (let i = 0; i < 90; i++) {
    const x = 8 + Math.random() * 112;
    const h = 45 + Math.random() * 78;
    const lean = (Math.random() - 0.5) * 34;
    const gr = 100 + Math.random() * 110;
    g.strokeStyle = `rgba(${gr * 0.48},${gr},${gr * 0.36},0.96)`;
    g.lineWidth = 2 + Math.random() * 2.4;
    g.beginPath();
    g.moveTo(x, 128);
    g.quadraticCurveTo(x + lean * 0.3, 128 - h * 0.62, x + lean, 128 - h);
    g.stroke();
  }
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

function makeCloudSpriteTexture() {
  const c = document.createElement('canvas');
  c.width = 256;
  c.height = 128;
  const g = c.getContext('2d');
  g.clearRect(0, 0, 256, 128);
  for (let i = 0; i < 42; i++) {
    const x = 35 + Math.random() * 186;
    const y = 48 + Math.random() * 38;
    const r = 16 + Math.random() * 34;
    const grad = g.createRadialGradient(x, y, 1, x, y, r);
    grad.addColorStop(0, 'rgba(255,246,238,0.34)');
    grad.addColorStop(0.65, 'rgba(255,205,175,0.14)');
    grad.addColorStop(1, 'rgba(255,190,160,0)');
    g.fillStyle = grad;
    g.beginPath();
    g.arc(x, y, r, 0, Math.PI * 2);
    g.fill();
  }
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

{
  const pmrem = new THREE.PMREMGenerator(renderer);
  const envSource = makeEnvironmentTexture();
  scene.environment = pmrem.fromEquirectangular(envSource).texture;
  if ('environmentIntensity' in scene) scene.environmentIntensity = 0.8;
  envSource.dispose();
  pmrem.dispose();
}

/* ============================ Трасса ============================ */
const TRACK_POINTS = [
  [0, -175], [95, -155], [155, -85], [140, 5], [185, 90], [115, 165],
  [20, 180], [-75, 150], [-155, 110], [-175, 20], [-140, -75], [-70, -145],
].map(([x, z]) => new THREE.Vector3(x, 0, z));

const curve = new THREE.CatmullRomCurve3(TRACK_POINTS, true, 'catmullrom', 0.6);
const TRACK_LENGTH = curve.getLength();
const SAMPLES = curve.getSpacedPoints(800);
const ROAD_HALF = 5.6; // асфальт 11.2 м: две гоночные полосы + края (шкала мира: 1 ед. = 1 м)

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

/* ============================ Рельеф острова ============================ */
const ROAD_GRID_CELL = 20;
const roadGrid = new Map();
SAMPLES.forEach((pt) => {
  const key = `${Math.floor(pt.x / ROAD_GRID_CELL)},${Math.floor(pt.z / ROAD_GRID_CELL)}`;
  if (!roadGrid.has(key)) roadGrid.set(key, []);
  roadGrid.get(key).push(pt);
});
function roadDistanceApprox(x, z) {
  const cx = Math.floor(x / ROAD_GRID_CELL);
  const cz = Math.floor(z / ROAD_GRID_CELL);
  let best2 = 60 * 60;
  for (let gx = cx - 2; gx <= cx + 2; gx++) {
    for (let gz = cz - 2; gz <= cz + 2; gz++) {
      const cell = roadGrid.get(`${gx},${gz}`);
      if (!cell) continue;
      for (const pt of cell) {
        const dx = pt.x - x;
        const dz = pt.z - z;
        const d2 = dx * dx + dz * dz;
        if (d2 < best2) best2 = d2;
      }
    }
  }
  return Math.sqrt(best2);
}
function terrainHeight(x, z, roadDist = null) {
  const d = roadDist === null ? roadDistanceApprox(x, z) : roadDist;
  const roadFactor = smoothstep(15, 48, d); // сетка рельефа не должна вылезать на асфальт
  const rolling = 1.0 + (fbm2(x * 0.011 + 7.3, z * 0.011 - 2.9) - 0.5) * 5.2
    + (fbm2(x * 0.045 - 4.1, z * 0.045 + 6.2, 3) - 0.5) * 1.3;
  const peak = (cx, cz, h, sigma) => {
    const dx = x - cx;
    const dz = z - cz;
    return h * Math.exp(-(dx * dx + dz * dz) / (2 * sigma * sigma));
  };
  const peaks = peak(0, 15, 19, 43) + peak(-68, -48, 12, 30) + peak(72, 62, 9, 27) + peak(-12, -102, 6, 30);
  let h = (rolling + peaks) * roadFactor;
  // ровная площадка фестиваля у старта
  const festivalFlat = smoothstep(20, 68, Math.hypot(x, z + 175));
  h *= 0.2 + 0.8 * festivalFlat;
  const shore = smoothstep(274, 307, Math.hypot(x, z));
  return lerp(h, -3.4, shore);
}

let waterMaterial = null;
let foamRing = null;
let grassMesh = null;
let festivalWheel = null;
const windTurbines = [];
const cloudGroup = new THREE.Group();
scene.add(cloudGroup);

/* ============================ Мир ============================ */
const colliders = []; // {x,z,r}

// Небо
{
  const sky = new THREE.Mesh(
    new THREE.SphereGeometry(950, 32, 20),
    new THREE.MeshBasicMaterial({ map: makeSkyTexture(), side: THREE.BackSide, fog: false })
  );
  scene.add(sky);
  const sunBall = new THREE.Mesh(
    new THREE.SphereGeometry(27, 20, 20),
    new THREE.MeshBasicMaterial({ color: 0xffe6ae, fog: false })
  );
  sunBall.position.set(-560, 132, -620);
  scene.add(sunBall);
  const halo = new THREE.Sprite(new THREE.SpriteMaterial({
    map: makeGlowTexture(), color: 0xffc98a, transparent: true, opacity: 0.9,
    blending: THREE.AdditiveBlending, depthWrite: false, fog: false,
  }));
  halo.scale.set(380, 380, 1);
  halo.position.copy(sunBall.position);
  scene.add(halo);
}

// Океан и остров (рельефная местность)
{
  const waterNormal = makeWaterNormalTexture();
  waterMaterial = new THREE.MeshPhysicalMaterial({
    color: 0x166f96, roughness: 0.12, metalness: 0,
    normalMap: waterNormal, normalScale: new THREE.Vector2(0.65, 0.65),
    transparent: true, opacity: 0.94, envMapIntensity: 1.35,
  });
  const water = new THREE.Mesh(new THREE.PlaneGeometry(2400, 2400), waterMaterial);
  water.rotation.x = -Math.PI / 2;
  water.position.y = -1.12;
  scene.add(water);

  foamRing = new THREE.Mesh(
    new THREE.RingGeometry(281, 300, 160),
    new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.15, depthWrite: false })
  );
  foamRing.rotation.x = -Math.PI / 2;
  foamRing.position.y = -0.92;
  scene.add(foamRing);

  const terrainGeo = new THREE.PlaneGeometry(640, 640, 150, 150);
  terrainGeo.rotateX(-Math.PI / 2);
  const posAttr = terrainGeo.attributes.position;
  for (let i = 0; i < posAttr.count; i++) {
    const x = posAttr.getX(i);
    const z = posAttr.getZ(i);
    posAttr.setY(i, terrainHeight(x, z));
  }
  terrainGeo.computeVertexNormals();
  const normAttr = terrainGeo.attributes.normal;
  const colors = new Float32Array(posAttr.count * 3);
  const cGrass = new THREE.Color(0x619e48);
  const cDry = new THREE.Color(0x99a454);
  const cForest = new THREE.Color(0x356735);
  const cSand = new THREE.Color(0xdcc088);
  const cDirt = new THREE.Color(0x8a6b49);
  const cRock = new THREE.Color(0x767068);
  const tmpColor = new THREE.Color();
  for (let i = 0; i < posAttr.count; i++) {
    const x = posAttr.getX(i);
    const z = posAttr.getZ(i);
    const h = posAttr.getY(i);
    const ny = normAttr.getY(i);
    const variation = fbm2(x * 0.024 + 11, z * 0.024 - 6, 3);
    tmpColor.copy(cForest).lerp(cGrass, clamp(variation * 1.35, 0, 1));
    if (variation > 0.62) tmpColor.lerp(cDry, (variation - 0.62) * 1.5);
    const sandiness = 1 - smoothstep(-0.25, 0.65, h);
    if (sandiness > 0) tmpColor.lerp(cSand, sandiness);
    if (h < -1) tmpColor.lerp(cDirt, 0.35);
    const rockiness = Math.max(1 - smoothstep(0.56, 0.84, ny), smoothstep(7, 15, h) * 0.7);
    if (rockiness > 0) tmpColor.lerp(cRock, clamp(rockiness, 0, 1));
    colors[i * 3] = tmpColor.r;
    colors[i * 3 + 1] = tmpColor.g;
    colors[i * 3 + 2] = tmpColor.b;
  }
  terrainGeo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
  const groundTex = makeGroundTexture();
  const terrain = new THREE.Mesh(
    terrainGeo,
    new THREE.MeshStandardMaterial({
      map: groundTex, bumpMap: groundTex, bumpScale: 0.35,
      vertexColors: true, roughness: 1, metalness: 0, envMapIntensity: 0.25,
    })
  );
  terrain.receiveShadow = true;
  scene.add(terrain);
}

// Дорога — лента вдоль сплайна (+ гравийная обочина)
{
  function buildRibbon(halfWidth, y) {
    const SEG = 420;
    const positions = [];
    const uvs = [];
    const indices = [];
    for (let i = 0; i <= SEG; i++) {
      const u = i / SEG;
      const p = curve.getPointAt(u % 1);
      const t = curve.getTangentAt(u % 1);
      const n = new THREE.Vector3(-t.z, 0, t.x);
      const l = p.clone().addScaledVector(n, halfWidth);
      const r = p.clone().addScaledVector(n, -halfWidth);
      positions.push(l.x, y, l.z, r.x, y, r.z);
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
    return geo;
  }

  const gravelTex = makeGroundTexture();
  gravelTex.repeat.set(2, 2);
  const shoulder = new THREE.Mesh(
    buildRibbon(ROAD_HALF + 1.4, 0.012),
    new THREE.MeshStandardMaterial({ color: 0x9a8563, map: gravelTex, bumpMap: gravelTex, bumpScale: 0.5, roughness: 1 })
  );
  shoulder.receiveShadow = true;
  scene.add(shoulder);

  const asphaltTex = makeRoadTexture();
  const road = new THREE.Mesh(
    buildRibbon(ROAD_HALF, 0.025),
    new THREE.MeshStandardMaterial({
      map: asphaltTex, bumpMap: asphaltTex, bumpScale: 0.18,
      roughness: 0.94, metalness: 0, envMapIntensity: 0.3,
    })
  );
  road.receiveShadow = true;
  scene.add(road);
}

// Горные пики острова — часть рельефа; на горизонте — скалистый хребет
{
  colliders.push(
    { x: 0, z: 15, r: 34 },
    { x: -68, z: -48, r: 21 },
    { x: 72, z: 62, r: 17 }
  );
  const rockTex = makeRockTexture();
  const rockMat = new THREE.MeshStandardMaterial({
    map: rockTex, bumpMap: rockTex, bumpScale: 0.8, roughness: 1, flatShading: true,
  });
  const snowMat = new THREE.MeshStandardMaterial({ color: 0xeef3fb, roughness: 0.72, flatShading: true });
  function jaggedCone(radius, height, seedOffset) {
    const geo = new THREE.ConeGeometry(radius, height, 26, 6);
    const attr = geo.attributes.position;
    for (let i = 0; i < attr.count; i++) {
      const x = attr.getX(i);
      const y = attr.getY(i);
      const z = attr.getZ(i);
      const rr = Math.hypot(x, z);
      if (rr > 0.01) {
        const n = fbm2(x * 0.035 + seedOffset, (z + y * 0.7) * 0.035, 3);
        const scale = 0.78 + n * 0.55;
        attr.setX(i, x * scale);
        attr.setZ(i, z * scale);
      }
    }
    geo.computeVertexNormals();
    return geo;
  }
  function distantMountain(x, z, h, r, i) {
    const m = new THREE.Group();
    const body = new THREE.Mesh(jaggedCone(r, h, i * 7.7), rockMat);
    body.position.y = h / 2 - 4;
    const cap = new THREE.Mesh(jaggedCone(r * 0.36, h * 0.34, i * 3.1), snowMat);
    cap.position.y = h - h * 0.17 - 4;
    m.add(body, cap);
    m.position.set(x, 0, z);
    m.rotation.y = rnd() * Math.PI;
    scene.add(m);
  }
  for (let i = 0; i < 11; i++) {
    const a = (i / 11) * TAU + 0.32;
    distantMountain(Math.cos(a) * (455 + rnd() * 90), Math.sin(a) * (455 + rnd() * 90), 85 + rnd() * 85, 95 + rnd() * 70, i);
  }
}

// Деревья, камни и трава — инстансинг для мобильных
{
  function displaceGeo(geo, amount, freq) {
    const attr = geo.attributes.position;
    const v = new THREE.Vector3();
    for (let i = 0; i < attr.count; i++) {
      v.fromBufferAttribute(attr, i);
      const n = fbm2(v.x * freq + 3.7, (v.z + v.y) * freq - 1.2, 3) - 0.5;
      const len = v.length() || 1;
      v.addScaledVector(v.clone().divideScalar(len), n * amount);
      attr.setXYZ(i, v.x, v.y, v.z);
    }
    geo.computeVertexNormals();
    return geo;
  }

  const broadleafParts = [];
  [[2.05, 0, 4.85, 0, 1.18], [1.45, -1.05, 4.15, 0.35, 1], [1.35, 1.1, 4.3, -0.25, 1], [1.05, 0.15, 5.75, 0.55, 0.95]].forEach(([r, x, y, z, sy]) => {
    const part = displaceGeo(new THREE.SphereGeometry(r, 12, 9), 0.24, 0.55);
    part.scale(1.08, sy * 0.78, 1);
    part.translate(x, y, z);
    broadleafParts.push(part);
  });
  const broadleafGeo = mergeGeometries(broadleafParts);
  const pineParts = [];
  [[2.05, 2.6, 3.7], [1.6, 2.4, 5.25], [1.1, 2.2, 6.8]].forEach(([r, h, y]) => {
    const part = displaceGeo(new THREE.ConeGeometry(r, h, 11, 3), 0.12, 0.7);
    part.translate(0, y, 0);
    pineParts.push(part);
  });
  const pineGeo = mergeGeometries(pineParts);
  const trunkGeo = new THREE.CylinderGeometry(0.13, 0.28, 3.6, 8);
  trunkGeo.translate(0, 1.8, 0);

  const treePos = [];
  let guard = 0;
  while (treePos.length < 230 && guard++ < 6000) {
    const a = rnd() * TAU;
    const r = 22 + rnd() * 248;
    const x = Math.cos(a) * r;
    const z = Math.sin(a) * r;
    const near = nearestSampleIdx({ x, z });
    if (near.dist < 13.5) continue;
    const h = terrainHeight(x, z, near.dist);
    if (h > 7.6 || h < -0.15) continue; // на голых скалах и в воде деревья не растут
    treePos.push({ x, z, h, pine: rnd() > 0.46, s: 0.8 + rnd() * 0.55, rot: rnd() * TAU });
    if (treePos.length % 3 === 0) colliders.push({ x, z, r: 0.4 });
  }
  const broadList = treePos.filter((t) => !t.pine);
  const pineList = treePos.filter((t) => t.pine);
  const barkTex = makeBarkTexture();
  const leafTex = makeLeafTexture();
  const trunks = new THREE.InstancedMesh(
    trunkGeo,
    new THREE.MeshStandardMaterial({ map: barkTex, bumpMap: barkTex, bumpScale: 0.7, roughness: 1 }),
    treePos.length
  );
  const broadleaf = new THREE.InstancedMesh(
    broadleafGeo,
    new THREE.MeshStandardMaterial({ map: leafTex, roughness: 1, envMapIntensity: 0.3 }),
    broadList.length
  );
  const pines = new THREE.InstancedMesh(
    pineGeo,
    new THREE.MeshStandardMaterial({ map: leafTex, color: 0x87a96f, roughness: 1, envMapIntensity: 0.3 }),
    pineList.length
  );
  const dummy = new THREE.Object3D();
  const tmpC = new THREE.Color();
  treePos.forEach((t, i) => {
    dummy.position.set(t.x, t.h - 0.08, t.z);
    dummy.rotation.set(0, t.rot, 0);
    dummy.scale.setScalar(t.s);
    dummy.updateMatrix();
    trunks.setMatrixAt(i, dummy.matrix);
  });
  broadList.forEach((t, i) => {
    dummy.position.set(t.x, t.h - 0.08, t.z);
    dummy.rotation.set(0, t.rot, 0);
    dummy.scale.setScalar(t.s);
    dummy.updateMatrix();
    broadleaf.setMatrixAt(i, dummy.matrix);
    broadleaf.setColorAt(i, tmpC.setHSL(0.29 + rnd() * 0.06, 0.22 + rnd() * 0.18, 0.66 + rnd() * 0.24));
  });
  pineList.forEach((t, i) => {
    dummy.position.set(t.x, t.h - 0.08, t.z);
    dummy.rotation.set(0, t.rot, 0);
    dummy.scale.setScalar(t.s);
    dummy.updateMatrix();
    pines.setMatrixAt(i, dummy.matrix);
    pines.setColorAt(i, tmpC.setHSL(0.33 + rnd() * 0.04, 0.2, 0.62 + rnd() * 0.2));
  });
  if (broadleaf.instanceColor) broadleaf.instanceColor.needsUpdate = true;
  if (pines.instanceColor) pines.instanceColor.needsUpdate = true;
  trunks.castShadow = broadleaf.castShadow = pines.castShadow = true;
  broadleaf.receiveShadow = pines.receiveShadow = true;
  scene.add(trunks, broadleaf, pines);

  // камни и скальные выходы
  const rockTex = makeRockTexture();
  const rockGeo = displaceGeo(new THREE.DodecahedronGeometry(1.15, 1), 0.22, 0.8);
  const rocks = new THREE.InstancedMesh(
    rockGeo,
    new THREE.MeshStandardMaterial({ map: rockTex, bumpMap: rockTex, bumpScale: 0.55, roughness: 1, flatShading: true }),
    80
  );
  for (let i = 0; i < 80; i++) {
    let x = 0, z = 0, h = 0;
    for (let tries = 0; tries < 20; tries++) {
      const a = rnd() * TAU;
      const r = 28 + rnd() * 240;
      x = Math.cos(a) * r;
      z = Math.sin(a) * r;
      const near = nearestSampleIdx({ x, z });
      if (near.dist < 10.5) continue;
      h = terrainHeight(x, z, near.dist);
      break;
    }
    const sc = 0.35 + rnd() * 1.15;
    dummy.position.set(x, h + sc * 0.22, z);
    dummy.rotation.set(rnd() * 3, rnd() * 3, rnd() * 3);
    dummy.scale.set(sc * (0.8 + rnd() * 0.5), sc * (0.55 + rnd() * 0.5), sc);
    dummy.updateMatrix();
    rocks.setMatrixAt(i, dummy.matrix);
  }
  rocks.castShadow = rocks.receiveShadow = true;
  scene.add(rocks);

  // пучки травы крест-накрест
  const bladePlane = new THREE.PlaneGeometry(0.75, 0.48);
  bladePlane.translate(0, 0.23, 0);
  const bladePlane2 = bladePlane.clone();
  bladePlane2.rotateY(Math.PI / 2);
  const grassGeo = mergeGeometries([bladePlane, bladePlane2]);
  const GRASS_COUNT = 2300;
  grassMesh = new THREE.InstancedMesh(
    grassGeo,
    new THREE.MeshStandardMaterial({
      map: makeGrassBladeTexture(), alphaTest: 0.34, side: THREE.DoubleSide, roughness: 1,
    }),
    GRASS_COUNT
  );
  let placedGrass = 0;
  guard = 0;
  while (placedGrass < GRASS_COUNT && guard++ < GRASS_COUNT * 5) {
    const a = rnd() * TAU;
    const r = 12 + Math.pow(rnd(), 0.75) * 262;
    const x = Math.cos(a) * r;
    const z = Math.sin(a) * r;
    const d = roadDistanceApprox(x, z);
    if (d < 8.6) continue;
    const h = terrainHeight(x, z, d);
    if (h < 0.05 || h > 8.5) continue;
    dummy.position.set(x, h - 0.03, z);
    dummy.rotation.set(0, rnd() * TAU, 0);
    const gs = 0.7 + rnd() * 0.7;
    dummy.scale.set(gs, gs * (0.75 + rnd() * 0.5), gs);
    dummy.updateMatrix();
    grassMesh.setMatrixAt(placedGrass, dummy.matrix);
    grassMesh.setColorAt(placedGrass, tmpC.setHSL(0.26 + rnd() * 0.09, 0.3, 0.64 + rnd() * 0.24));
    placedGrass++;
  }
  grassMesh.count = placedGrass;
  if (grassMesh.instanceColor) grassMesh.instanceColor.needsUpdate = true;
  scene.add(grassMesh);
}

// Фестивальная зона у старта: арка, шатры, дома, воздушные шары
const balloons = [];
{
  const start = pointAtS(0);
  const arch = new THREE.Group();
  const pillarMat = new THREE.MeshStandardMaterial({ color: 0x22263a, roughness: 0.6 });
  [-1, 1].forEach((side) => {
    const pillar = new THREE.Mesh(new THREE.BoxGeometry(1.1, 7.6, 1.1), pillarMat);
    pillar.position.set(side * (ROAD_HALF + 1.2), 3.8, 0);
    pillar.castShadow = true;
    arch.add(pillar);
    const ball = new THREE.Mesh(
      new THREE.SphereGeometry(0.8, 10, 10),
      new THREE.MeshStandardMaterial({ color: side > 0 ? 0xff5e3a : 0x2ee6ff, emissive: 0x442200 })
    );
    ball.position.set(side * (ROAD_HALF + 1.2), 8.0, 0);
    arch.add(ball);
  });
  const banner = new THREE.Mesh(
    new THREE.BoxGeometry(ROAD_HALF * 2 + 3.6, 2.2, 0.35),
    new THREE.MeshBasicMaterial({ map: makeBannerTexture() })
  );
  banner.position.y = 6.7;
  arch.add(banner);
  arch.position.copy(start.pos);
  arch.rotation.y = start.yaw;
  scene.add(arch);

  // шатры фестиваля
  const tentColors = [0xff5e3a, 0xffb03a, 0x2ee6ff, 0xb44aff, 0xff3a7a, 0x37c978];
  for (let i = 0; i < 10; i++) {
    const s = -30 + i * 9 + rnd() * 4;
    const side = i % 2 ? 1 : -1;
    const p = pointAtS(s, side * (ROAD_HALF + 7.5 + rnd() * 4));
    const tent = new THREE.Group();
    const cone = new THREE.Mesh(
      new THREE.ConeGeometry(2.8, 2.5, 8),
      new THREE.MeshStandardMaterial({ color: tentColors[i % tentColors.length], roughness: 0.8, flatShading: true })
    );
    cone.position.y = 2.15;
    cone.castShadow = true;
    const base = new THREE.Mesh(
      new THREE.CylinderGeometry(2.65, 2.65, 1.5, 8),
      new THREE.MeshStandardMaterial({ color: 0xf5f0e6, roughness: 0.9 })
    );
    base.position.y = 0.75;
    tent.add(cone, base);
    tent.position.copy(p.pos);
    scene.add(tent);
    colliders.push({ x: p.pos.x, z: p.pos.z, r: 2.8 });
  }

  // домики деревни с текстурированными фасадами
  const facadeA = makeFacadeTexture('#eadfc7', '#31556e');
  const facadeB = makeFacadeTexture('#e4cdb2', '#6e4631');
  const facadeC = makeFacadeTexture('#dfe5d8', '#3f6250');
  const facades = [facadeA, facadeB, facadeC].map((tex) => new THREE.MeshStandardMaterial({
    map: tex, bumpMap: tex, bumpScale: 0.12, roughness: 0.92, envMapIntensity: 0.35,
  }));
  const plainWallMat = new THREE.MeshStandardMaterial({ color: 0xd8c9ac, roughness: 0.95 });
  const roofMats = [0x9f4634, 0x6d4a3a, 0x51606b].map((color) => new THREE.MeshStandardMaterial({
    color, roughness: 0.9, flatShading: true,
  }));
  const chimneyMat = new THREE.MeshStandardMaterial({ color: 0x8a7a6c, roughness: 1 });
  for (let i = 0; i < 14; i++) {
    const s = (TRACK_LENGTH / 14) * i + 42;
    const side = i % 2 ? 1 : -1;
    const p = pointAtS(s, side * (ROAD_HALF + 21 + rnd() * 15));
    if (Math.hypot(p.pos.x, p.pos.z) > 255) continue;
    const groundY = terrainHeight(p.pos.x, p.pos.z);
    const house = new THREE.Group();
    const w = 8.5 + rnd() * 3; // ширина фасада 8.5–11.5 м
    const d = 7 + rnd() * 2;   // глубина 7–9 м
    const facadeMat = facades[i % facades.length];
    const walls = new THREE.Mesh(
      new THREE.BoxGeometry(w, 5.8, d), // два этажа по 2.9 м
      [facadeMat, facadeMat, plainWallMat, plainWallMat, facadeMat, facadeMat]
    );
    walls.position.y = 2.9;
    walls.castShadow = walls.receiveShadow = true;
    const roofGeo = new THREE.ConeGeometry(1, 3.0, 4);
    roofGeo.rotateY(Math.PI / 4);
    roofGeo.scale(w * 0.79, 1, d * 0.79);
    const roof = new THREE.Mesh(roofGeo, roofMats[i % roofMats.length]);
    roof.position.y = 7.3;
    roof.castShadow = true;
    const chimney = new THREE.Mesh(new THREE.BoxGeometry(0.55, 1.5, 0.55), chimneyMat);
    chimney.position.set(w * 0.22, 8.2, 0);
    chimney.castShadow = true;
    house.add(walls, roof, chimney);
    house.position.set(p.pos.x, groundY - 0.3, p.pos.z);
    house.rotation.y = rnd() * TAU;
    scene.add(house);
    colliders.push({ x: p.pos.x, z: p.pos.z, r: Math.max(w, d) * 0.58 });
  }

  // воздушные шары праздника
  for (let i = 0; i < 5; i++) {
    const b = new THREE.Group();
    const env = new THREE.Mesh(
      new THREE.SphereGeometry(6.2, 14, 12),
      new THREE.MeshStandardMaterial({ color: tentColors[i % tentColors.length], roughness: 0.5, flatShading: true })
    );
    env.scale.y = 1.15;
    const basket = new THREE.Mesh(
      new THREE.BoxGeometry(1.4, 1.2, 1.4),
      new THREE.MeshStandardMaterial({ color: 0x7a4a2a })
    );
    basket.position.y = -8.6;
    b.add(env, basket);
    const a = (i / 5) * TAU;
    b.position.set(Math.cos(a) * (90 + rnd() * 90), 62 + rnd() * 30, Math.sin(a) * (90 + rnd() * 90));
    b.userData.phase = rnd() * TAU;
    scene.add(b);
    balloons.push(b);
  }

  // облака: мягкие спрайты в закатном свете
  const cloudTex = makeCloudSpriteTexture();
  for (let i = 0; i < 26; i++) {
    const sprite = new THREE.Sprite(new THREE.SpriteMaterial({
      map: cloudTex, transparent: true, opacity: 0.42 + rnd() * 0.3,
      depthWrite: false, fog: false,
    }));
    const a = rnd() * TAU;
    const dist = 160 + rnd() * 420;
    sprite.position.set(Math.cos(a) * dist, 95 + rnd() * 85, Math.sin(a) * dist);
    const w = 85 + rnd() * 150;
    sprite.scale.set(w, w * 0.36, 1);
    sprite.userData.speed = 0.7 + rnd() * 1.3;
    cloudGroup.add(sprite);
  }

}

// Ворота чекпоинтов
const cpMeshes = [];
{
  const poleGeo = new THREE.CylinderGeometry(0.16, 0.16, 4.6, 8);
  CHECKPOINTS.forEach((cp, i) => {
    const grp = new THREE.Group();
    const mat = new THREE.MeshBasicMaterial({ color: 0x7cfc4a, transparent: true, opacity: 0.0 });
    const poleMat = new THREE.MeshStandardMaterial({ color: 0x223, roughness: 0.6 });
    [-1, 1].forEach((side) => {
      const pole = new THREE.Mesh(poleGeo, poleMat);
      pole.position.set(side * (ROAD_HALF + 0.6), 2.3, 0);
      grp.add(pole);
    });
    const beam = new THREE.Mesh(new THREE.BoxGeometry(ROAD_HALF * 2 + 1.2, 4.4, 0.5), mat);
    beam.position.y = 2.2;
    grp.add(beam);
    // световой столб следующего чекпоинта
    const pillar = new THREE.Mesh(
      new THREE.CylinderGeometry(2.6, 2.6, 34, 12, 1, true),
      new THREE.MeshBasicMaterial({
        color: 0x7cfc4a, transparent: true, opacity: 0, side: THREE.DoubleSide, depthWrite: false,
      })
    );
    pillar.position.y = 17;
    grp.add(pillar);
    grp.position.copy(cp.pos);
    grp.rotation.y = cp.yaw;
    grp.visible = false;
    scene.add(grp);
    cpMeshes.push({ grp, beamMat: mat, pillarMat: pillar.material });
  });
}

/* ============================ Детали окружения ============================ */
{
  // Уличные фонари вдоль трассы
  const poleMat = new THREE.MeshStandardMaterial({ color: 0x2c3138, metalness: 0.65, roughness: 0.45 });
  const lampMat = new THREE.MeshStandardMaterial({ color: 0xffe2a8, emissive: 0xffbd67, emissiveIntensity: 1.5 });
  for (let i = 0; i < 20; i++) {
    const s = (TRACK_LENGTH / 20) * i + 24;
    const side = i % 2 ? 1 : -1;
    const p = pointAtS(s, side * (ROAD_HALF + 2.2));
    const lamp = new THREE.Group();
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.09, 0.13, 6.4, 8), poleMat);
    pole.position.y = 3.2;
    pole.castShadow = true;
    const arm = new THREE.Mesh(new THREE.BoxGeometry(1.9, 0.09, 0.09), poleMat);
    arm.position.set(side > 0 ? 0.85 : -0.85, 6.25, 0);
    const head = new THREE.Mesh(new THREE.SphereGeometry(0.17, 10, 8), lampMat);
    head.position.set(side > 0 ? 1.7 : -1.7, 6.15, 0);
    lamp.add(pole, arm, head);
    lamp.position.set(p.pos.x, terrainHeight(p.pos.x, p.pos.z), p.pos.z);
    lamp.rotation.y = p.yaw;
    scene.add(lamp);
    colliders.push({ x: p.pos.x, z: p.pos.z, r: 0.35 });
  }

  // Стопки шин на внешней стороне поворотов
  const tireGeo = new THREE.TorusGeometry(0.34, 0.125, 8, 18);
  const tirePositions = [];
  for (let i = 0; i < 16; i++) {
    const s = (TRACK_LENGTH / 16) * i + 34;
    const here = pointAtS(s);
    const ahead = pointAtS(s + 24);
    const crossY = here.tangent.z * ahead.tangent.x - here.tangent.x * ahead.tangent.z;
    const outside = crossY >= 0 ? -1 : 1;
    for (let k = -1; k <= 2; k++) {
      const p = pointAtS(s + k * 1.35, outside * (ROAD_HALF + 1.15));
      tirePositions.push(p.pos);
      colliders.push({ x: p.pos.x, z: p.pos.z, r: 0.5 });
    }
  }
  const tireStacks = new THREE.InstancedMesh(
    tireGeo,
    new THREE.MeshStandardMaterial({ roughness: 0.95 }),
    tirePositions.length * 3
  );
  const dummy2 = new THREE.Object3D();
  const tmpColor2 = new THREE.Color();
  let ti = 0;
  tirePositions.forEach((pos, colIdx) => {
    const gy = terrainHeight(pos.x, pos.z);
    for (let level = 0; level < 3; level++) {
      dummy2.position.set(pos.x, gy + 0.14 + level * 0.23, pos.z);
      dummy2.rotation.set(Math.PI / 2, 0, colIdx * 0.7 + level);
      dummy2.scale.setScalar(1);
      dummy2.updateMatrix();
      tireStacks.setMatrixAt(ti, dummy2.matrix);
      tireStacks.setColorAt(ti, tmpColor2.setHex((colIdx + level) % 3 === 0 ? 0xc6372b : (colIdx + level) % 3 === 1 ? 0xe8e5dd : 0x1b1b1e));
      ti++;
    }
  });
  if (tireStacks.instanceColor) tireStacks.instanceColor.needsUpdate = true;
  tireStacks.castShadow = tireStacks.receiveShadow = true;
  scene.add(tireStacks);

  // Колесо обозрения фестиваля
  const wheelBase = new THREE.Group();
  const wheelPos = new THREE.Vector3(-38, 0, -126);
  wheelBase.position.set(wheelPos.x, terrainHeight(wheelPos.x, wheelPos.z), wheelPos.z);
  wheelBase.rotation.y = 0.22;
  const frameMat = new THREE.MeshStandardMaterial({ color: 0xd9dce2, metalness: 0.7, roughness: 0.35 });
  [-1, 1].forEach((side) => {
    const leg = new THREE.Mesh(new THREE.CylinderGeometry(0.26, 0.36, 14.8, 8), frameMat);
    leg.position.set(side * 3.0, 6.9, 0);
    leg.rotation.z = side * 0.42;
    leg.castShadow = true;
    wheelBase.add(leg);
  });
  festivalWheel = new THREE.Group();
  festivalWheel.position.y = 13.4;
  [0, 0.9].forEach((zo) => {
    const rim = new THREE.Mesh(new THREE.TorusGeometry(10, 0.22, 8, 48), frameMat);
    rim.position.z = zo - 0.45;
    festivalWheel.add(rim);
  });
  for (let i = 0; i < 6; i++) {
    const spoke = new THREE.Mesh(new THREE.CylinderGeometry(0.09, 0.09, 19.8, 6), frameMat);
    spoke.rotation.z = (i / 6) * Math.PI;
    festivalWheel.add(spoke);
  }
  const hubWheel = new THREE.Mesh(new THREE.CylinderGeometry(0.8, 0.8, 1.5, 14), frameMat);
  hubWheel.rotation.x = Math.PI / 2;
  festivalWheel.add(hubWheel);
  const gondolaColors = [0xff5e3a, 0xffb03a, 0x2ee6ff, 0xb44aff, 0xff3a7a, 0x37c978];
  for (let i = 0; i < 10; i++) {
    const a = (i / 10) * TAU;
    const gondola = new THREE.Mesh(
      new THREE.BoxGeometry(1.5, 1.25, 1.3),
      new THREE.MeshStandardMaterial({ color: gondolaColors[i % gondolaColors.length], roughness: 0.5, emissive: gondolaColors[i % gondolaColors.length], emissiveIntensity: 0.18 })
    );
    gondola.position.set(Math.cos(a) * 10, Math.sin(a) * 10, 0);
    gondola.castShadow = true;
    festivalWheel.add(gondola);
    const bulb = new THREE.Mesh(
      new THREE.SphereGeometry(0.16, 8, 6),
      new THREE.MeshStandardMaterial({ color: 0xffe8b0, emissive: 0xffca70, emissiveIntensity: 2 })
    );
    bulb.position.set(Math.cos(a + 0.31) * 10, Math.sin(a + 0.31) * 10, 0.55);
    festivalWheel.add(bulb);
  }
  wheelBase.add(festivalWheel);
  scene.add(wheelBase);
  colliders.push({ x: wheelPos.x, z: wheelPos.z, r: 6.5 });

  // Ветряки на холмах
  const turbineMat = new THREE.MeshStandardMaterial({ color: 0xe8ebef, metalness: 0.35, roughness: 0.5 });
  [[-42, 32], [36, -28], [94, 34]].forEach(([x, z], idx) => {
    const gy = terrainHeight(x, z);
    const turbine = new THREE.Group();
    const tower = new THREE.Mesh(new THREE.CylinderGeometry(0.35, 0.7, 21, 10), turbineMat);
    tower.position.y = 10.5;
    tower.castShadow = true;
    turbine.add(tower);
    const rotor = new THREE.Group();
    rotor.position.set(0, 21, 0.7);
    for (let i = 0; i < 3; i++) {
      const blade = new THREE.Mesh(new THREE.BoxGeometry(0.32, 8.6, 0.08), turbineMat);
      blade.position.y = 4.1;
      const holder = new THREE.Group();
      holder.rotation.z = (i / 3) * TAU;
      holder.add(blade);
      rotor.add(holder);
    }
    rotor.rotation.y = idx * 0.8 + 0.4;
    const rotorSpin = new THREE.Group();
    rotorSpin.add(rotor);
    turbine.add(rotorSpin);
    turbine.position.set(x, gy - 0.1, z);
    scene.add(turbine);
    windTurbines.push(rotor);
    colliders.push({ x, z, r: 0.9 });
  });

  // Сельская церковь — ориентир на востоке острова
  const churchPos = { x: 98, z: -12 };
  const churchY = terrainHeight(churchPos.x, churchPos.z);
  const church = new THREE.Group();
  const churchWall = new THREE.MeshStandardMaterial({ map: makeFacadeTexture('#f3ead6', '#28455c'), roughness: 0.92 });
  const nave = new THREE.Mesh(new THREE.BoxGeometry(7, 5, 12), churchWall);
  nave.position.y = 2.5;
  nave.castShadow = nave.receiveShadow = true;
  const churchRoof = new THREE.Mesh(
    new THREE.ConeGeometry(5.4, 3, 4),
    new THREE.MeshStandardMaterial({ color: 0x74513e, roughness: 0.9, flatShading: true })
  );
  churchRoof.position.y = 6.5;
  churchRoof.rotation.y = Math.PI / 4;
  churchRoof.scale.z = 1.55;
  churchRoof.castShadow = true;
  const tower = new THREE.Mesh(new THREE.BoxGeometry(3.4, 10, 3.4), churchWall);
  tower.position.set(0, 5, 6.8);
  tower.castShadow = true;
  const spire = new THREE.Mesh(
    new THREE.ConeGeometry(2.7, 5.5, 4),
    new THREE.MeshStandardMaterial({ color: 0x3e4e5c, roughness: 0.75, flatShading: true })
  );
  spire.position.set(0, 12.7, 6.8);
  spire.rotation.y = Math.PI / 4;
  spire.castShadow = true;
  church.add(nave, churchRoof, tower, spire);
  church.scale.setScalar(1.18);
  church.position.set(churchPos.x, churchY, churchPos.z);
  church.rotation.y = -0.5;
  scene.add(church);
  colliders.push({ x: churchPos.x, z: churchPos.z, r: 8.2 });
}

/* ============================ Модель машины ============================ */
function buildCarMesh(color, accent, isBuggy = false) {
  const car = new THREE.Group();
  car.rotation.order = 'YXZ';
  const paint = new THREE.MeshPhysicalMaterial({
    color, roughness: 0.3, metalness: 0.62, clearcoat: 1, clearcoatRoughness: 0.1, envMapIntensity: 1.35,
  });
  const dark = new THREE.MeshStandardMaterial({ color: 0x15171f, roughness: 0.5, metalness: 0.3 });
  const glass = new THREE.MeshPhysicalMaterial({
    color: 0x0e1a28, roughness: 0.07, metalness: 0.9, clearcoat: 1, envMapIntensity: 1.8,
  });

  const body = new THREE.Mesh(new THREE.BoxGeometry(1.84, 0.5, 3.9), paint);
  body.position.set(0, isBuggy ? 0.76 : 0.55, -0.05);
  body.castShadow = true;
  car.add(body);

  const nose = new THREE.Mesh(new THREE.BoxGeometry(1.72, 0.32, 0.85), paint);
  nose.position.set(0, (isBuggy ? 0.66 : 0.46), 1.95);
  nose.castShadow = true;
  car.add(nose);

  const cabin = new THREE.Mesh(new THREE.BoxGeometry(1.45, 0.48, 1.75), glass);
  cabin.position.set(0, (isBuggy ? 1.24 : 0.98), -0.2);
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
    const spoiler = new THREE.Mesh(new THREE.BoxGeometry(1.78, 0.08, 0.4), dark);
    spoiler.position.set(0, 1.08, -1.9);
    spoiler.castShadow = true;
    car.add(spoiler);
    [-0.62, 0.62].forEach((x) => {
      const strut = new THREE.Mesh(new THREE.BoxGeometry(0.1, 0.4, 0.12), dark);
      strut.position.set(x, 0.88, -1.9);
      car.add(strut);
    });
    // гоночная полоса
    const stripe = new THREE.Mesh(
      new THREE.BoxGeometry(0.5, 0.04, 3.95),
      new THREE.MeshStandardMaterial({ color: accent, roughness: 0.4, emissive: accent, emissiveIntensity: 0.25 })
    );
    stripe.position.y = 0.84;
    car.add(stripe);
  }

  // фары / стопы
  const headMat = new THREE.MeshStandardMaterial({ color: 0xfff6c8, emissive: 0xffe9a0, emissiveIntensity: 1.6 });
  const tailMat = new THREE.MeshStandardMaterial({ color: 0xff2222, emissive: 0xff2222, emissiveIntensity: 1.2 });
  [-0.56, 0.56].forEach((x) => {
    const h = new THREE.Mesh(new THREE.BoxGeometry(0.38, 0.15, 0.08), headMat);
    h.position.set(x, 0.6, 2.39);
    car.add(h);
    const t = new THREE.Mesh(new THREE.BoxGeometry(0.44, 0.13, 0.08), tailMat);
    t.position.set(x, 0.68, -2.01);
    car.add(t);
  });

  // неоновая подсветка снизу
  const glow = new THREE.Mesh(
    new THREE.PlaneGeometry(2.5, 4.9),
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
  flame.position.set(0, 0.42, -2.8);
  flame.visible = false;
  flame.name = 'flame';
  car.add(flame);

  // колёса
  const wheelGeo = new THREE.CylinderGeometry(isBuggy ? 0.43 : 0.34, isBuggy ? 0.43 : 0.34, 0.3, 18);
  const wheelMat = new THREE.MeshStandardMaterial({ color: 0x111111, roughness: 0.9 });
  const hubMat = new THREE.MeshStandardMaterial({ color: 0xdddddd, roughness: 0.3, metalness: 0.8 });
  const wheels = [];
  const wy = isBuggy ? 0.43 : 0.34;
  [[-0.82, 1.35], [0.82, 1.35], [-0.82, -1.35], [0.82, -1.35]].forEach(([x, z], i) => {
    const pivot = new THREE.Group();
    pivot.position.set(x, wy, z);
    const w = new THREE.Mesh(wheelGeo, wheelMat);
    w.rotation.z = Math.PI / 2;
    w.castShadow = true;
    const hub = new THREE.Mesh(new THREE.CylinderGeometry(0.16, 0.16, 0.34, 10), hubMat);
    hub.rotation.z = Math.PI / 2;
    const spin = new THREE.Group();
    spin.add(w, hub);
    pivot.add(spin);
    car.add(pivot);
    wheels.push({ pivot, spin, front: i < 2 });
  });

  return { group: car, wheels, flame, wheelRadius: wy };
}

function createPlayerCar() {
  if (player.mesh) {
    scene.remove(player.mesh.group);
  }
  const built = selectedCar.id === 'gtr35'
    ? buildGTR35(selectedGTRPaint)
    : buildCarMesh(selectedCar.color, selectedCar.accent, selectedCar.id === 'dune');
  built.group.rotation.order = 'YXZ';
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
  player.offroad = near.dist > ROAD_HALF + 0.6 || Math.hypot(pos.x, pos.z) > 278;
  const inWater = Math.hypot(pos.x, pos.z) > 289 || terrainHeight(pos.x, pos.z, near.dist) < -0.85;

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

  // Гравитация на склонах бездорожья: подъёмы тормозят, спуски разгоняют
  if (player.offroad && !inWater && near.dist > ROAD_HALF + 2) {
    const hAhead = terrainHeight(pos.x + _fwd.x * 2.2, pos.z + _fwd.z * 2.2);
    const hBack = terrainHeight(pos.x - _fwd.x * 2.2, pos.z - _fwd.z * 2.2);
    const slope = (hAhead - hBack) / 4.4;
    player.vel.addScaledVector(_fwd, -slope * 8.2 * dt);
  }

  // Сопротивление
  const drag = player.offroad ? 0.55 : 0.22;
  player.vel.multiplyScalar(Math.exp(-drag * dt * (player.drifting ? 1.5 : 1)));
  if (!input.gas && !input.brake) player.vel.multiplyScalar(Math.exp(-0.35 * dt));

  // Мягкий кап скорости
  const spd = player.vel.length();
  const hardCap = topSpeed * 1.18 + 6;
  if (spd > hardCap) player.vel.multiplyScalar(lerp(1, hardCap / spd, dt * 3));

  pos.addScaledVector(player.vel, dt);
  const groundH = terrainHeight(pos.x, pos.z, near.dist);
  player.groundH = groundH;
  pos.y = inWater ? Math.max(groundH, -0.58) : groundH; // машина повторяет рельеф

  // Граница мира
  const distC = Math.hypot(pos.x, pos.z);
  if (distC > 322) {
    pos.x *= 322 / distC;
    pos.z *= 322 / distC;
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

  // Меш: кузов наклоняется по рельефу + крены от руля/газа
  const g = player.mesh.group;
  g.rotation.y = player.yaw;
  if (!inWater && near.dist > ROAD_HALF - 1) {
    const hF = terrainHeight(pos.x + _fwd.x * 1.7, pos.z + _fwd.z * 1.7);
    const hB = terrainHeight(pos.x - _fwd.x * 1.7, pos.z - _fwd.z * 1.7);
    const hR = terrainHeight(pos.x + _right.x * 1.1, pos.z + _right.z * 1.1);
    const hL = terrainHeight(pos.x - _right.x * 1.1, pos.z - _right.z * 1.1);
    player.groundPitch = clamp(-Math.atan2(hF - hB, 3.4), -0.5, 0.5);
    player.groundRoll = clamp(Math.atan2(hR - hL, 2.2), -0.5, 0.5);
  } else {
    player.groundPitch = lerp(player.groundPitch, 0, dt * 6);
    player.groundRoll = lerp(player.groundRoll, 0, dt * 6);
  }
  g.rotation.z = lerp(
    g.rotation.z,
    player.groundRoll - player.steerVis * clamp(speedAbs / 30, 0, 1) * 0.09,
    dt * 7
  );
  g.rotation.x = lerp(
    g.rotation.x,
    player.groundPitch + (input.gas && canDrive ? -0.02 : input.brake ? 0.025 : 0),
    dt * 6
  );
  const wheelR = player.mesh.wheelRadius || 0.4;
  player.wheels.forEach((w) => {
    if (w.front) w.pivot.rotation.y = player.steerVis;
    w.spin.rotation.x += (fwdSpeed / wheelR) * dt;
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
      w.spin.rotation.x += (r.speed / (r.mesh.wheelRadius || 0.4)) * dt;
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
    const cx = center.x + Math.cos(menuOrbit) * 7.4;
    const cz = center.z + Math.sin(menuOrbit) * 7.4;
    camera.position.lerp(new THREE.Vector3(cx, center.y + 1.9, cz), Math.min(dt * 1.6, 1));
    camera.lookAt(center.x, center.y + 0.75, center.z);
    camera.fov = lerp(camera.fov, 52, dt * 2);
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
    camTargetPos.y = pos.y + 1.25;
    camera.position.lerp(camTargetPos, Math.min(dt * 22, 1));
    const look = pos.clone().addScaledVector(_fwd, 18);
    look.y = pos.y + 1.0;
    camera.lookAt(look);
  } else {
    const dist = cameraMode === 0 ? 7.6 + speedRatio * 1.8 : 12.5;
    const height = cameraMode === 0 ? 2.55 : 4.6;
    camTargetPos.copy(pos).addScaledVector(_fwd, -dist);
    camTargetPos.y = pos.y + height;
    // камера не должна уходить под склон позади машины
    camTargetPos.y = Math.max(camTargetPos.y, terrainHeight(camTargetPos.x, camTargetPos.z) + 1.2);
    camera.position.lerp(camTargetPos, Math.min(dt * (cameraMode === 0 ? 4.2 : 3), 1));
    const look = pos.clone().addScaledVector(_fwd, 9);
    look.y = pos.y + 1.4;
    camera.lookAt(look);
  }
  const targetFov = 62 + (player.boosting ? 8 : speedRatio * 4);
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

  // живая вода, пена, колесо обозрения, ветряки и дрейф облаков
  if (waterMaterial && waterMaterial.normalMap) {
    waterMaterial.normalMap.offset.set((t * 0.014) % 1, (t * 0.009) % 1);
  }
  if (foamRing) foamRing.material.opacity = 0.11 + Math.sin(t * 0.8) * 0.045;
  if (festivalWheel) festivalWheel.rotation.z += dt * 0.11;
  windTurbines.forEach((rotor, i) => {
    rotor.rotation.z += dt * (0.65 + i * 0.13);
  });
  cloudGroup.children.forEach((sprite) => {
    sprite.position.x += dt * (sprite.userData.speed || 1);
    if (sprite.position.x > 620) sprite.position.x = -620;
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
    sun.position.set(p.x - 90, p.y + 125, p.z - 60);
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
  buildPaintPicker();
}

function buildPaintPicker() {
  const wrap = $('paintPicker');
  if (!wrap) return;
  const isGTR = selectedCar.id === 'gtr35';
  wrap.classList.toggle('hidden', !isGTR);
  if (!isGTR) {
    wrap.innerHTML = '';
    return;
  }
  const current = GTR_PAINTS.find((paint) => paint.hex === selectedGTRPaint);
  wrap.innerHTML = `<div class="paint-title">🎨 Краска GT-R35: <b>${current ? current.name : ''}</b></div>`;
  const row = document.createElement('div');
  row.className = 'paint-row';
  GTR_PAINTS.forEach((paint) => {
    const sw = document.createElement('button');
    sw.className = 'paint-swatch' + (paint.hex === selectedGTRPaint ? ' selected' : '');
    sw.title = paint.name;
    sw.style.background = `#${paint.hex.toString(16).padStart(6, '0')}`;
    sw.addEventListener('click', () => {
      selectedGTRPaint = paint.hex;
      selectedCar.color = paint.hex;
      safeSetItem('nh_gtr_paint', paint.hex);
      buildCarPicker();
      previewCarInMenu();
    });
    row.appendChild(sw);
  });
  wrap.appendChild(row);
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

function applyGraphicsQuality(quality, announce = false) {
  graphicsQuality = quality === 'fast' ? 'fast' : 'realistic';
  safeSetItem('nh_gfx', graphicsQuality);
  document.querySelectorAll('.gfx-btn').forEach((btn) => {
    btn.classList.toggle('active', btn.dataset.gfx === graphicsQuality);
  });
  renderer.setPixelRatio(graphicsQuality === 'realistic' ? Math.min(window.devicePixelRatio, 2) : 1);
  renderer.setSize(window.innerWidth, window.innerHeight);
  const shadowSize = graphicsQuality === 'realistic' ? 2048 : 1024;
  if (sun.shadow.mapSize.x !== shadowSize) {
    sun.shadow.mapSize.set(shadowSize, shadowSize);
    if (sun.shadow.map) {
      sun.shadow.map.dispose();
      sun.shadow.map = null;
    }
  }
  if (grassMesh) grassMesh.visible = graphicsQuality === 'realistic';
  cloudGroup.visible = graphicsQuality === 'realistic';
  if (announce) {
    showCenterMsg(
      graphicsQuality === 'realistic' ? 'Графика: реалистичная ✨' : 'Графика: быстрая ⚡',
      1100
    );
  }
}
document.querySelectorAll('.gfx-btn').forEach((btn) => {
  btn.addEventListener('click', () => applyGraphicsQuality(btn.dataset.gfx, true));
});

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
applyGraphicsQuality(graphicsQuality);
previewCarInMenu();
drawMinimap();
animate();

// PWA: офлайн-кэш только в продакшен-сборке
if (import.meta.env.PROD && 'serviceWorker' in navigator) {
  navigator.serviceWorker.register('/sw.js').catch(() => {});
}
