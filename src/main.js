import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { buildGTR35, GTR_PAINTS } from './gtr.js';
import { buildMustang, preloadMustangModel, MUSTANG_PAINTS } from './mustang.js';
import { installCloudPrototype } from './cloudPrototype.js';
import {
  createPowertrainSpec,
  createPowertrainState,
  resetPowertrainState,
  shapePedalInput,
  updatePowertrain,
} from './vehicle/powertrain.js';
import {
  createAxleWheelState,
  resetAxleWheelState,
  updateAxleWheel,
} from './vehicle/wheelDynamics.js';
import { iconMarkup, setIcon } from './ui/icons.js';
import { createRealWorldFoundation } from './world/realWorld.js';
import { createRealWorldScene } from './world/realWorldScene.js';
import skyDayUrl from './assets/textures/realworld/user_sky_day.jpg';
import skySunsetUrl from './assets/textures/realworld/user_sky_sunset.jpg';
import skyNightUrl from './assets/textures/realworld/user_sky_night.jpg';
import sunGlowUrl from './assets/textures/realworld/sun_glow.jpg';
import cloudPuffUrl from './assets/textures/realworld/cloud_puff.jpg';
import { distanceToCollider } from './world/spatialIndex.js';
import './style.css';

/* =====================================================================
   NITCHES HORIZON — мобильный гоночный фестиваль в открытом мире.
   v0.16.0: мир Real Valley вырос на восток новым районом RichTown в
   стиле Дубая (бульвар с пальмами, стеклянные и золотые небоскрёбы,
   башня-игла, золотая арка, фонтан и марина) на фототекстурах,
   дуб из FBX-модели пользователя и растительный пак из его Obj.obj
   (второе дерево, кусты, кустарник и веерное растение), Mustang
   Fastback из GLB-модели, шинная физика, шоурум, свет, дрифт и нитро.
   Старый остров: ?world=legacy.
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
    silhouette: 'car-coupe',
    color: 0x1167b1,
    accent: 0x2e7bff,
    topSpeed: 64, // ≈ 230 км/ч (ограничитель трансмиссии)
    engine: 34,
    grip: 10,
    offroad: 0.5,
    mass: 1765, powerKW: 421, driveFrontBias: 0.42, wheelbase: 2.78, cgToFront: 1.30, cgHeight: 0.52,
    tireMu: 1.18, dragArea: 0.62, brakeDecel: 10.5, maxSteer: 0.56,
    powertrain: {
      engineType: 'turbo', idleRpm: 850, redlineRpm: 7200, limiterRpm: 7450,
      peakPowerRpm: 6600, peakTorqueNm: 637, gearCount: 6, wheelRadiusM: 0.35,
      efficiency: 0.88, shiftUpMs: 105, shiftDownMs: 125, brakeFrontBias: 0.68,
    },
    stats: { spd: 0.98, acc: 0.99, hnd: 0.96, off: 0.3 },
  },
  {
    id: 'mustang',
    name: 'MUSTANG FASTBACK',
    cls: 'Класс A • реальная 3D-модель',
    silhouette: 'car-muscle',
    color: 0x17181c,
    accent: 0xff7a1a,
    topSpeed: 55, // м/с ≈ 198 км/ч
    engine: 29,
    grip: 8.2,
    offroad: 0.55,
    mass: 1470, powerKW: 271, driveFrontBias: 0, wheelbase: 2.613, cgToFront: 1.37, cgHeight: 0.53,
    tireMu: 1.02, dragArea: 0.78, brakeDecel: 9.2, maxSteer: 0.58,
    powertrain: {
      engineType: 'na', idleRpm: 800, redlineRpm: 6800, limiterRpm: 7050,
      peakPowerRpm: 5400, peakTorqueNm: 540, gearCount: 6, wheelRadiusM: 0.338,
      efficiency: 0.86, shiftUpMs: 150, shiftDownMs: 170, brakeFrontBias: 0.67,
    },
    stats: { spd: 0.84, acc: 0.84, hnd: 0.78, off: 0.38 },
  },
  {
    id: 'volt',
    name: 'VOLT GT',
    cls: 'Класс A • баланс',
    silhouette: 'car-sport',
    color: 0xff5e3a,
    accent: 0xffb03a,
    topSpeed: 52, // м/с ≈ 187 км/ч
    engine: 26,
    grip: 8.5,
    offroad: 0.62,
    mass: 1380, powerKW: 255, driveFrontBias: 0, wheelbase: 2.70, cgToFront: 1.32, cgHeight: 0.50,
    tireMu: 1.08, dragArea: 0.60, brakeDecel: 9.8, maxSteer: 0.58,
    powertrain: {
      engineType: 'turbo', idleRpm: 850, redlineRpm: 7000, limiterRpm: 7250,
      peakPowerRpm: 6000, peakTorqueNm: 450, gearCount: 7, wheelRadiusM: 0.335,
      efficiency: 0.88, shiftUpMs: 120, shiftDownMs: 140, brakeFrontBias: 0.68,
    },
    stats: { spd: 0.78, acc: 0.8, hnd: 0.82, off: 0.45 },
  },
  {
    id: 'falcon',
    name: 'FALCON RS',
    cls: 'Класс S • гиперкар',
    silhouette: 'car-hyper',
    color: 0x2e7bff,
    accent: 0x2ee6ff,
    topSpeed: 62, // ≈ 223 км/ч
    engine: 31,
    grip: 9.5,
    offroad: 0.5,
    mass: 1240, powerKW: 545, driveFrontBias: 0, wheelbase: 2.65, cgToFront: 1.43, cgHeight: 0.42,
    tireMu: 1.28, dragArea: 0.58, brakeDecel: 11.5, maxSteer: 0.52,
    powertrain: {
      engineType: 'na', idleRpm: 900, redlineRpm: 8500, limiterRpm: 8750,
      peakPowerRpm: 8000, peakTorqueNm: 650, gearCount: 7, wheelRadiusM: 0.345,
      efficiency: 0.89, shiftUpMs: 95, shiftDownMs: 115, brakeFrontBias: 0.66,
    },
    stats: { spd: 0.97, acc: 0.95, hnd: 0.9, off: 0.28 },
  },
  {
    id: 'dune',
    name: 'DUNE BREAKER',
    cls: 'Класс B • внедорожник',
    silhouette: 'car-pickup',
    color: 0x37c978,
    accent: 0xd9ff4a,
    topSpeed: 46,
    engine: 27,
    grip: 7,
    offroad: 0.94,
    mass: 1550, powerKW: 210, driveFrontBias: 0.5, wheelbase: 2.85, cgToFront: 1.38, cgHeight: 0.72,
    tireMu: 0.98, dragArea: 0.92, brakeDecel: 8.8, maxSteer: 0.62,
    powertrain: {
      engineType: 'diesel', idleRpm: 750, redlineRpm: 5200, limiterRpm: 5450,
      peakPowerRpm: 3600, peakTorqueNm: 560, gearCount: 6, wheelRadiusM: 0.39,
      efficiency: 0.84, shiftUpMs: 180, shiftDownMs: 200, brakeFrontBias: 0.64,
    },
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
let selectedMustangPaint = Number(safeGetItem('nh_mustang_paint')) || MUSTANG_PAINTS[0].hex;
if (!MUSTANG_PAINTS.some((paint) => paint.hex === selectedMustangPaint)) selectedMustangPaint = MUSTANG_PAINTS[0].hex;
const mustangCatalogCar = CARS.find((car) => car.id === 'mustang');
if (mustangCatalogCar) mustangCatalogCar.color = selectedMustangPaint;
let graphicsQuality = safeGetItem('nh_gfx') === 'fast' ? 'fast' : 'realistic';
let skyMood = ['day', 'sunset', 'night'].includes(safeGetItem('nh_sky')) ? safeGetItem('nh_sky') : 'day';
let applySkyMood = () => {};
const SKY_EXPOSURE = { day: 1.34, sunset: 1.26, night: 1.05 };
let controlScheme = safeGetItem('nh_controls') === 'buttons' ? 'buttons' : 'wheel';
let assistMode = ['arcade', 'sport', 'drift'].includes(safeGetItem('nh_assist'))
  ? safeGetItem('nh_assist') : 'sport';
const ASSIST_PROFILES = {
  arcade: { label: 'Аркада', grip: 1.18, yawDamping: 2.25, stability: 2.55, traction: 0.92, steering: 0.94, handbrakeRearGrip: 0.36, maxYawRate: 2.15 },
  sport: { label: 'Спорт', grip: 1.02, yawDamping: 1.38, stability: 1.0, traction: 0.42, steering: 1.04, handbrakeRearGrip: 0.22, maxYawRate: 2.85 },
  drift: { label: 'Дрифт', grip: 0.90, yawDamping: 0.78, stability: 0.18, traction: 0.06, steering: 1.18, handbrakeRearGrip: 0.12, maxYawRate: 3.55 },
};

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
  // динамика автомобиля
  yawRate: 0,
  steerAngle: 0,
  throttle: 0,
  brakePedal: 0,
  gear: 1,
  selector: 'D',
  engineRpm: 850,
  rpmRatio: 0.12,
  clutch: 0,
  engineLoad: 0,
  shifting: false,
  powertrain: null,
  wheelAxles: null,
  frontWheelOmega: 0,
  rearWheelOmega: 0,
  frontLongSlip: 0,
  rearLongSlip: 0,
  longitudinalSlip: 0,
  slipAngle: 0,
  frontSlip: 0,
  rearSlip: 0,
  longAccel: 0,
  latAccel: 0,
  wheelspin: false,
  surface: 'asphalt',
  surfaceMu: 1,
  surfaceMuSmooth: 1,
  travelDistance: 0,
  smokeAccumulator: 0,
  skidAccumulator: 0,
};

let rivals = [];
let raceTime = 0;
let countdownT = 0;
let countdownShown = '';
let cameraMode = 0; // 0 — погоня, 1 — далеко, 2 — капот
let menuOrbit = 0;
let crashCooldown = 0;

const input = {
  gas: false,
  brake: false,
  left: false,
  right: false,
  nitro: false,
  handbrake: false,
  gasValue: 0,
  brakeValue: 0,
};

const powertrainSpecs = new Map();
function getPowertrainSpec(car = selectedCar) {
  if (!powertrainSpecs.has(car)) powertrainSpecs.set(car, createPowertrainSpec(car));
  return powertrainSpecs.get(car);
}
function syncPowertrainTelemetry() {
  const state = player.powertrain;
  if (!state) return;
  player.gear = state.gear;
  player.selector = state.selector;
  player.engineRpm = state.engineRpm;
  player.rpmRatio = state.rpmRatio;
  player.clutch = state.clutch;
  player.engineLoad = state.engineLoad || 0;
  player.shifting = Boolean(state.shifting);
}
function resetPlayerWheelAxles(car = selectedCar) {
  const spec = getPowertrainSpec(car);
  if (!player.wheelAxles) {
    player.wheelAxles = {
      front: createAxleWheelState(),
      rear: createAxleWheelState(),
    };
  } else {
    resetAxleWheelState(player.wheelAxles.front, 0, spec.wheelRadiusM);
    resetAxleWheelState(player.wheelAxles.rear, 0, spec.wheelRadiusM);
  }
  player.frontWheelOmega = 0;
  player.rearWheelOmega = 0;
  player.frontLongSlip = 0;
  player.rearLongSlip = 0;
  player.longitudinalSlip = 0;
  return player.wheelAxles;
}
function resetPlayerPowertrain(car = selectedCar) {
  const spec = getPowertrainSpec(car);
  if (!player.powertrain) player.powertrain = createPowertrainState(spec);
  else resetPowertrainState(player.powertrain, spec);
  resetPlayerWheelAxles(car);
  syncPowertrainTelemetry();
  return player.powertrain;
}
function pedalTargetValue(key) {
  const touchValue = clamp(Number(input[`${key}Value`]) || 0, 0, 1);
  return shapePedalInput(Math.max(input[key] ? 1 : 0, touchValue));
}

/* Виртуальный руль: rotation — угол обода в радианах, + по часовой (поворот вправо).
   Значение для физики, наоборот, + = влево, диапазон -1..1. */
const steering = {
  rotation: 0,
  velocity: 0,
  value: 0,
  grabbing: false,
  pointerId: null,
  lastPointerAngle: 0,
  maxRotation: 2.75, // ±158° обода
  wasAtLock: false,
};

function resetSteering() {
  steering.rotation = 0;
  steering.velocity = 0;
  steering.value = 0;
  steering.grabbing = false;
  steering.pointerId = null;
  steering.wasAtLock = false;
  updateSteeringVisual();
}

function approachValue(current, target, maxDelta) {
  if (current < target) return Math.min(current + maxDelta, target);
  return Math.max(current - maxDelta, target);
}

function updateSteeringVisual() {
  const rotEl = $('steeringWheelRot');
  if (rotEl) rotEl.style.transform = `rotate(${steering.rotation}rad)`;
  const label = $('steerAngleLabel');
  if (label) {
    const deg = Math.round((player.steerAngle || 0) * 57.2958);
    label.textContent = deg === 0 ? '0°' : `${deg > 0 ? '+' : '-'}${Math.abs(deg)}°`;
  }
}

function updateSteeringInput(dt) {
  if (dt <= 0) return;
  const digital = (input.right ? 1 : 0) + (input.left ? -1 : 0);
  if (!steering.grabbing) {
    if (digital !== 0) {
      const target = digital * steering.maxRotation;
      steering.rotation = approachValue(steering.rotation, target, 8.5 * dt);
      steering.velocity = 0;
    } else {
      // Самовозврат руля: пружина с демпфированием, как aligning torque на настоящей рейке
      const spring = 30;
      const damping = 10.5;
      steering.velocity += (-spring * steering.rotation - damping * steering.velocity) * dt;
      steering.rotation += steering.velocity * dt;
      if (Math.abs(steering.rotation) < 0.002 && Math.abs(steering.velocity) < 0.03) {
        steering.rotation = 0;
        steering.velocity = 0;
      }
    }
  }
  steering.rotation = clamp(steering.rotation, -steering.maxRotation, steering.maxRotation);
  const atLock = Math.abs(steering.rotation) > steering.maxRotation - 0.02;
  if (atLock && !steering.wasAtLock) vibrate(10);
  steering.wasAtLock = atLock;
  const normalized = clamp(steering.rotation / steering.maxRotation, -1, 1);
  const shaped = Math.sign(normalized) * Math.pow(Math.abs(normalized), 1.12);
  steering.value = Math.abs(shaped) < 0.012 ? 0 : -shaped; // + = влево для физики
  updateSteeringVisual();
}

/* Свободная камера: орбита вокруг машины перетаскиванием и щипком/колесом мыши */
const cameraOrbit = {
  yaw: 0,
  pitch: 0,
  distanceScale: 1,
  menuPitch: 0.24,
  menuDistance: 7.4,
  idle: 99,
  menuIdle: 99,
};
let inspectMode = false;
function resetCameraOrbit() {
  cameraOrbit.yaw = 0;
  cameraOrbit.pitch = 0;
  cameraOrbit.distanceScale = 1;
  cameraOrbit.idle = 99;
}

/* ============================ Сцена ============================ */
const canvas = $('game');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.34;
const MAX_ANISO = renderer.capabilities.getMaxAnisotropy();

const scene = new THREE.Scene();
scene.fog = new THREE.Fog(0xdca16f, 150, 880);

const camera = new THREE.PerspectiveCamera(62, window.innerWidth / window.innerHeight, 0.1, 2000);
camera.position.set(0, 26, -140);

// HDR Bloom is reserved for the realistic preset.  A 2x-MSAA half-float
// target keeps sun glints, LEDs and lamps glowing without giving up the
// direct renderer's edge quality; fast mode always renders directly.
let composer = null;
let bloomPass = null;
const syncComposerSize = () => {
  if (!composer) return;
  const pr = graphicsQuality === 'realistic' ? Math.min(window.devicePixelRatio || 1, 1.65) : 1;
  composer.setPixelRatio(pr);
  composer.setSize(window.innerWidth, window.innerHeight);
};
try {
  const composerTarget = new THREE.WebGLRenderTarget(window.innerWidth, window.innerHeight, {
    type: THREE.HalfFloatType,
    samples: 2,
  });
  composer = new EffectComposer(renderer, composerTarget);
  composer.addPass(new RenderPass(scene, camera));
  bloomPass = new UnrealBloomPass(
    new THREE.Vector2(window.innerWidth, window.innerHeight),
    0.2,
    0.55,
    0.84,
  );
  composer.addPass(bloomPass);
  composer.addPass(new OutputPass());
  syncComposerSize();
} catch (error) {
  console.warn('[gfx] HDR Bloom unavailable, using direct renderer:', error);
  composer = null;
  bloomPass = null;
}

/* =====================================================================
   МИР v0.6: Festival Britain 4×4 км — ИГРАБЕЛЬНАЯ карта по умолчанию
   (вертикальный срез: свободная поездка по всей карте; гонки, трафик и
   соперники пока остаются на legacy-острове и придут позже).
   Откат на старую карту 640 м: ?world=legacy или localStorage
   nh_world=legacy. Диагностика: window.__NH_WORLD__ (mode, stats()).
   При любой ошибке инициализации — автоматический fallback на legacy.
   ===================================================================== */
let worldFoundation = null;
let worldStreamer = null;
let worldBackdrop = null;
let realWorldSceneHandle = null;
let worldStreamAccumS = 0;
let britainDistrictId = 'town-centre';
let skyMesh = null;      // заполняются в блоке «Небо» ниже
let sunBallMesh = null;
let sunHaloMesh = null;
const SUN_SKY_OFFSET = new THREE.Vector3(-560, 132, -620);

function resolveWorldMode() {
  try {
    const params = new URLSearchParams(window.location.search);
    if (params.get('world') === 'legacy') return 'legacy';
    if (window.localStorage && window.localStorage.getItem('nh_world') === 'legacy') return 'legacy';
  } catch { /* по умолчанию — новая карта */ }
  return 'britain';
}

let WORLD_MODE = resolveWorldMode();

function isBritainWorld() {
  return WORLD_MODE === 'britain' && worldFoundation !== null;
}

/** Точка спавна Real Valley: главная улица у западного въезда в город. */
function britainSpawnPoint(lane = 0) {
  if (worldFoundation?.spawnPoint) {
    const p = worldFoundation.spawnPoint(lane);
    return { pos: new THREE.Vector3(p.x, p.y, p.z), yaw: p.yaw };
  }
  const fallbackY = worldFoundation ? worldFoundation.heightAt(-208, 4) : 8;
  return { pos: new THREE.Vector3(-208, fallbackY, 4), yaw: Math.PI / 2 };
}

let britainWheelRim = null;

/** Колесо обозрения фестиваля Британии — ориентир у спавна. */
function buildBritainFerrisWheel() {
  const group = new THREE.Group();
  const wx = 96;
  const wz = 1312;
  const wy = worldFoundation.heightAt(wx, wz);
  group.position.set(wx, wy, wz);
  group.rotation.y = Math.PI / 2; // круг смотрит на дорогу фестиваля
  group.name = 'nh-britain-ferris-wheel';

  const frameMat = new THREE.MeshLambertMaterial({ color: 0xdfe6ee });
  const accentMat = new THREE.MeshLambertMaterial({ color: 0xff7a3a });
  for (const side of [-1, 1]) {
    const leg = new THREE.Mesh(new THREE.BoxGeometry(0.8, 19, 0.8), frameMat);
    leg.position.set(side * 5.2, 8.6, 0);
    leg.rotation.z = side * 0.3;
    leg.castShadow = true;
    group.add(leg);
  }
  const base = new THREE.Mesh(new THREE.BoxGeometry(13, 1, 4), accentMat);
  base.position.y = 0.5;
  group.add(base);

  const rim = new THREE.Group();
  rim.position.y = 17;
  const torus = new THREE.Mesh(new THREE.TorusGeometry(15, 0.35, 8, 40), frameMat);
  torus.castShadow = true;
  rim.add(torus);
  const inner = new THREE.Mesh(new THREE.TorusGeometry(9.5, 0.2, 6, 32), accentMat);
  rim.add(inner);
  for (let i = 0; i < 4; i++) {
    const spoke = new THREE.Mesh(new THREE.CylinderGeometry(0.16, 0.16, 29.6, 6), frameMat);
    spoke.rotation.z = (i / 4) * Math.PI;
    rim.add(spoke);
  }
  const cabinColors = [0xff5e8a, 0x35c5ff, 0xffc23a, 0x7dff6a, 0xb78bff, 0xff8a5e, 0x5effd4, 0xff5e5e];
  for (let i = 0; i < 8; i++) {
    const angle = (i / 8) * Math.PI * 2;
    const cabin = new THREE.Mesh(
      new THREE.SphereGeometry(1.7, 10, 8),
      new THREE.MeshLambertMaterial({ color: cabinColors[i] }),
    );
    cabin.position.set(Math.cos(angle) * 15, Math.sin(angle) * 15, 0);
    cabin.castShadow = true;
    rim.add(cabin);
  }
  const hub = new THREE.Mesh(new THREE.SphereGeometry(1.4, 10, 8), accentMat);
  rim.add(hub);
  group.add(rim);
  britainWheelRim = rim;

  worldFoundation.colliderIndex.add({ id: 'landmark-ferris', kind: 'circle', x: wx, z: wz, r: 5 });
  return group;
}

function initWorldMode() {
  const diagnostics = {
    world: 'real-valley',
    version: '0.18.0',
    mode: WORLD_MODE,
    foundation: null,
    streamer: null,
    city: null,
    error: null,
    stats: () => (worldFoundation ? worldFoundation.stats() : null),
    setPreview: (visible) => {
      if (realWorldSceneHandle) realWorldSceneHandle.group.visible = Boolean(visible);
      return Boolean(realWorldSceneHandle);
    },
  };
  window.__NH_WORLD__ = diagnostics;
  if (WORLD_MODE !== 'britain') return diagnostics;
  try {
    // Real Valley 1x1 км: весь мир строится одной статичной сценой на
    // сгенерированных фототекстурах — стриминг для километра не нужен.
    worldFoundation = createRealWorldFoundation();
    realWorldSceneHandle = createRealWorldScene(worldFoundation);
    scene.add(realWorldSceneHandle.group);
    diagnostics.city = { status: 'ready', ...realWorldSceneHandle.stats };

    // Дальность обзора под километр мира и дальнюю землю за ободом.
    scene.fog.near = 140;
    scene.fog.far = 2100;
    camera.far = 5000;
    camera.updateProjectionMatrix();

    selectedMode = 'free'; // гонки на новой карте — следующим этапом
    diagnostics.foundation = worldFoundation;
    diagnostics.streamer = null;
    console.info('[world] Real Valley 1x1 km playable:', worldFoundation.stats(), realWorldSceneHandle.stats);
  } catch (error) {
    WORLD_MODE = 'legacy';
    diagnostics.mode = 'legacy';
    diagnostics.error = String((error && error.message) || error);
    worldFoundation = null;
    worldStreamer = null;
    console.warn('[world] Britain init failed; falling back to legacy island:', error);
  }
  return diagnostics;
}

const worldDiagnostics = initWorldMode();
void worldDiagnostics;

/** В режиме Britain кнопка «гонка» в меню принудительно показывает free. */
function applyBritainModeUI() {
  if (!isBritainWorld()) return;
  document.querySelectorAll('.mode-btn').forEach((b) => {
    const active = b.dataset.mode === 'free';
    b.classList.toggle('active', active);
    b.setAttribute('aria-pressed', active ? 'true' : 'false');
  });
}

function updateWorldFoundation(dt) {
  if (!isBritainWorld()) return;
  worldStreamAccumS += dt;
  if (worldStreamAccumS < 0.25) return;
  worldStreamAccumS = 0;
  const pos = player.mesh && player.mesh.group ? player.mesh.group.position : null;
  const fx = pos ? pos.x : 0;
  const fz = pos ? pos.z : 0;
  if (worldStreamer) worldStreamer.update(fx, fz, { budget: 2 });

  // Сфера неба (R=950) и облака не покрывают 4 км из начала координат —
  // едут за игроком, как и тень солнца.
  if (skyMesh) skyMesh.position.set(fx, 0, fz);
  if (sunBallMesh) sunBallMesh.position.set(fx + SUN_SKY_OFFSET.x, SUN_SKY_OFFSET.y, fz + SUN_SKY_OFFSET.z);
  if (sunHaloMesh && sunBallMesh) sunHaloMesh.position.copy(sunBallMesh.position);
  cloudGroup.position.set(fx, 0, fz);

  if (pos && gameState === 'racing') {
    const district = worldFoundation.getDistrict(pos.x, pos.z);
    const id = district ? district.id : null;
    if (id && id !== britainDistrictId) {
      britainDistrictId = id;
      showCenterMsg(district.name, 2100, '#2ee6ff', 'map');
    } else if (!id) {
      britainDistrictId = null;
    }
  }
}

// Свет заката фестиваля — более насыщенный и объёмный
const hemiLight = new THREE.HemisphereLight(0xa8cfff, 0x7a4a2a, 0.66);
scene.add(hemiLight);
const sun = new THREE.DirectionalLight(0xffb070, 3.05);
sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048);
sun.shadow.radius = 3.2;
sun.shadow.normalBias = 0.018;
sun.shadow.camera.left = -64;
sun.shadow.camera.right = 64;
sun.shadow.camera.top = 64;
sun.shadow.camera.bottom = -64;
sun.shadow.camera.far = 300;
sun.shadow.bias = -0.0012;
sun.shadow.camera.updateProjectionMatrix();
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

function makeStreetTexture() {
  const c = document.createElement('canvas');
  c.width = c.height = 512;
  const g = c.getContext('2d');
  g.fillStyle = '#303338';
  g.fillRect(0, 0, 512, 512);
  // Пятна ремонта и неравномерного износа
  for (let i = 0; i < 76; i++) {
    const v = 38 + Math.random() * 28;
    g.fillStyle = `rgba(${v},${v + 2},${v + 6},${0.1 + Math.random() * 0.16})`;
    g.beginPath();
    g.ellipse(Math.random() * 512, Math.random() * 512, 28 + Math.random() * 105, 16 + Math.random() * 62, Math.random() * 3, 0, Math.PI * 2);
    g.fill();
  }
  for (let i = 0; i < 18000; i++) {
    const v = 92 + Math.random() * 120;
    g.fillStyle = `rgba(${v},${v},${v},${Math.random() * 0.13})`;
    g.fillRect(Math.random() * 512, Math.random() * 512, 1.6, 1.6);
  }
  // Колеи колёс
  [128, 384].forEach((x) => {
    const grad = g.createLinearGradient(x - 44, 0, x + 44, 0);
    grad.addColorStop(0, 'rgba(0,0,0,0)');
    grad.addColorStop(0.5, 'rgba(0,0,0,0.3)');
    grad.addColorStop(1, 'rgba(0,0,0,0)');
    g.fillStyle = grad;
    g.fillRect(x - 44, 0, 88, 512);
  });
  // Трещины и поперечный шов
  g.strokeStyle = 'rgba(7,7,9,0.48)';
  for (let i = 0; i < 15; i++) {
    g.lineWidth = 1 + Math.random() * 1.8;
    g.beginPath();
    let x = Math.random() * 512;
    let y = Math.random() * 512;
    g.moveTo(x, y);
    for (let j = 0; j < 4; j++) {
      x += (Math.random() - 0.5) * 80;
      y += Math.random() * 52;
      g.lineTo(x, y);
    }
    g.stroke();
  }
  g.fillStyle = 'rgba(8,8,10,0.34)';
  g.fillRect(0, 252, 512, 6);
  // Разметка
  g.fillStyle = 'rgba(245,245,240,0.92)';
  g.fillRect(20, 0, 7, 512);
  g.fillRect(485, 0, 7, 512);
  g.fillStyle = 'rgba(248,207,72,0.9)';
  g.fillRect(251, 30, 10, 150);
  // Стёртость краски зерном асфальта
  for (let i = 0; i < 2200; i++) {
    const zones = [[20, 7], [485, 7], [251, 10]];
    const [zx, zw] = zones[(Math.random() * zones.length) | 0];
    g.fillStyle = `rgba(48,51,56,${Math.random() * 0.55})`;
    g.fillRect(zx + Math.random() * zw, Math.random() * 512, 2.2, 2.2);
  }
  const tex = new THREE.CanvasTexture(c);
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.anisotropy = MAX_ANISO;
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

function makeCrosswalkTexture() {
  const c = document.createElement('canvas'); c.width = 256; c.height = 128;
  const g = c.getContext('2d');
  g.clearRect(0, 0, 256, 128);
  g.fillStyle = 'rgba(250,250,246,0.94)';
  for (let x = 12; x < 245; x += 42) g.fillRect(x, 14, 24, 100);
  const tex = new THREE.CanvasTexture(c); tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}
function makeConcreteTexture() {
  const c = document.createElement('canvas');
  c.width = c.height = 256;
  const g = c.getContext('2d');
  g.fillStyle = '#969b97';
  g.fillRect(0, 0, 256, 256);
  for (let i = 0; i < 70; i++) {
    const v = 126 + Math.random() * 55;
    g.fillStyle = `rgba(${v},${v},${v - 4},${0.08 + Math.random() * 0.13})`;
    g.beginPath();
    g.ellipse(Math.random() * 256, Math.random() * 256, 18 + Math.random() * 58, 10 + Math.random() * 34, Math.random() * 3, 0, Math.PI * 2);
    g.fill();
  }
  for (let i = 0; i < 9000; i++) {
    const v = 105 + Math.random() * 105;
    g.fillStyle = `rgba(${v},${v},${v},${Math.random() * 0.16})`;
    g.fillRect(Math.random() * 256, Math.random() * 256, 1.5, 1.5);
  }
  // Швы плит: при UV ленты v=distance/8 дают стыки примерно каждые 4 м
  g.fillStyle = 'rgba(52,55,54,0.62)';
  g.fillRect(0, 0, 256, 4);
  g.fillRect(0, 126, 256, 4);
  g.fillRect(0, 252, 256, 4);
  g.fillRect(0, 0, 4, 256);
  g.fillRect(252, 0, 4, 256);
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
  grad.addColorStop(0, '#245aa0');
  grad.addColorStop(0.34, '#5e8fc7');
  grad.addColorStop(0.55, '#c98d7d');
  grad.addColorStop(0.68, '#ffab5e');
  grad.addColorStop(0.78, '#ffd083');
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
    g.globalAlpha = Math.random() * 0.3;
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
  g.fillStyle = '#4b7436';
  g.fillRect(0, 0, 256, 256);
  // Объём кроны: тёмные впадины и освещённые внешние пучки
  for (let i = 0; i < 115; i++) {
    const lit = Math.random() > 0.48;
    g.fillStyle = lit ? 'rgba(132,176,82,0.16)' : 'rgba(25,54,25,0.2)';
    g.beginPath();
    g.ellipse(Math.random() * 256, Math.random() * 256, 14 + Math.random() * 42, 9 + Math.random() * 27, Math.random() * Math.PI, 0, Math.PI * 2);
    g.fill();
  }
  for (let i = 0; i < 5600; i++) {
    const warm = Math.random() < 0.065;
    const gr = 92 + Math.random() * 112;
    g.fillStyle = warm
      ? `rgba(${165 + Math.random() * 55},${94 + Math.random() * 42},38,${0.28 + Math.random() * 0.42})`
      : `rgba(${gr * 0.52},${gr},${gr * 0.4},${0.28 + Math.random() * 0.52})`;
    g.save();
    g.translate(Math.random() * 256, Math.random() * 256);
    g.rotate(Math.random() * Math.PI);
    g.beginPath();
    g.ellipse(0, 0, 3 + Math.random() * 4.2, 1.1 + Math.random() * 1.5, 0, 0, Math.PI * 2);
    g.fill();
    g.restore();
  }
  const tex = new THREE.CanvasTexture(c);
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.repeat.set(2, 2);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = MAX_ANISO;
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
  for (let i = 0; i < 145; i++) {
    const x = 5 + Math.random() * 118;
    const h = 42 + Math.random() * 82;
    const lean = (Math.random() - 0.5) * 38;
    if (Math.random() < 0.12) {
      g.strokeStyle = `rgba(${168 + Math.random() * 36},${148 + Math.random() * 28},72,0.92)`;
    } else {
      const gr = 96 + Math.random() * 116;
      g.strokeStyle = `rgba(${gr * 0.46},${gr},${gr * 0.34},0.97)`;
    }
    g.lineWidth = 1.7 + Math.random() * 2.5;
    g.beginPath();
    g.moveTo(x, 128);
    g.quadraticCurveTo(x + lean * 0.3, 128 - h * 0.62, x + lean, 128 - h);
    g.stroke();
  }
  // Несколько мелких полевых цветов добавляют масштаб и цвет у обочины
  const flowerColors = ['#ffffff', '#ffd94d', '#ff9ecf', '#c4b5fd'];
  for (let i = 0; i < 15; i++) {
    g.fillStyle = flowerColors[(Math.random() * flowerColors.length) | 0];
    g.beginPath();
    g.arc(10 + Math.random() * 108, 38 + Math.random() * 58, 1.6 + Math.random() * 1.4, 0, Math.PI * 2);
    g.fill();
  }
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = MAX_ANISO;
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
  if ('environmentIntensity' in scene) scene.environmentIntensity = 1.14;
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
const ROAD_HALF = 4.7; // асфальт 9.4 м: две реальные полосы + узкие обочины (1 ед. = 1 м)

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

/* ==================== Дорожная сеть острова ====================
   Главная кольцевая трасса дополнена обычными дорогами: деревня с круговой
   улицей, подъезд к фестивалю, горный серпантин к ветрякам и прибрежная
   дорога. Все они попадают в поле расстояний: рельеф под ними ровный,
   а физика считает их асфальтом. */
function makeRoadCurve(points, closed = false) {
  return new THREE.CatmullRomCurve3(
    points.map(([x, z]) => new THREE.Vector3(x, 0, z)),
    closed,
    'catmullrom',
    0.45
  );
}
const SECONDARY_ROADS = [];
function addSecondaryRoad(name, points, options = {}) {
  const closed = options.closed || false;
  const roadCurve = makeRoadCurve(points, closed);
  const length = roadCurve.getLength();
  const sampleCount = clamp(Math.round(length / 2), 24, 520);
  let samples = roadCurve.getSpacedPoints(sampleCount);
  if (closed) samples = samples.slice(0, -1);
  const road = {
    name,
    curve: roadCurve,
    closed,
    length,
    halfWidth: options.halfWidth || 3.7,
    sidewalk: options.sidewalk || false,
    surface: options.surface || 'asphalt',
    samples,
    distanceSamples: samples,
  };
  SECONDARY_ROADS.push(road);
  return road;
}

addSecondaryRoad('Деревенский подъезд', [
  [142, 8], [128, -2], [112, -10], [98, -12], [84, -7], [72, 4], [65, 18],
], { halfWidth: 3.7, sidewalk: true });
const villageLoopRoad = addSecondaryRoad('Деревенский круг', [
  [72, -34], [104, -40], [126, -22], [128, 8], [111, 34], [80, 35], [63, 12], [61, -16],
], { closed: true, halfWidth: 3.7, sidewalk: true });
addSecondaryRoad('Фестивальный подъезд', [
  [2, -174], [-8, -158], [-20, -144], [-34, -132], [-43, -119], [-50, -106],
], { halfWidth: 3.4 });
addSecondaryRoad('Горный серпантин', [
  [-174, 22], [-150, 29], [-126, 19], [-108, -2], [-88, -15], [-64, -8], [-50, 12], [-42, 31],
], { halfWidth: 3.5 });
const coastalRoad = addSecondaryRoad('Прибрежная дорога', [
  [116, 164], [142, 184], [178, 190], [209, 169], [224, 132], [210, 105], [187, 91],
], { halfWidth: 3.8 });

function pointOnRoad(road, sPos, lane = 0) {
  const u = road.closed
    ? ((sPos / road.length) % 1 + 1) % 1
    : clamp(sPos / road.length, 0, 1);
  const p = road.curve.getPointAt(u);
  const t = road.curve.getTangentAt(u);
  const n = new THREE.Vector3(-t.z, 0, t.x);
  return { pos: p.clone().addScaledVector(n, lane), tangent: t, normal: n, yaw: Math.atan2(t.x, t.z), u };
}

const ROAD_DISTANCE_SAMPLES = [
  ...SAMPLES.map((pt) => ({ x: pt.x, z: pt.z, halfWidth: ROAD_HALF, surface: 'asphalt' })),
  ...SECONDARY_ROADS.flatMap((road) => road.distanceSamples.map((pt) => ({
    x: pt.x, z: pt.z, halfWidth: road.halfWidth, surface: road.surface,
  }))),
];

// Чекпоинты: 12 штук, индекс 0 — старт/финиш
const CHECKPOINTS = [];
for (let i = 0; i < 12; i++) {
  CHECKPOINTS.push(pointAtS((TRACK_LENGTH / 12) * i));
}

/* ============================ Рельеф острова ============================ */
const ROAD_GRID_CELL = 20;
const roadGrid = new Map();
ROAD_DISTANCE_SAMPLES.forEach((pt) => {
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
function nearestRoadInfoApprox(x, z) {
  const cx = Math.floor(x / ROAD_GRID_CELL);
  const cz = Math.floor(z / ROAD_GRID_CELL);
  let best = null;
  for (let gx = cx - 2; gx <= cx + 2; gx++) {
    for (let gz = cz - 2; gz <= cz + 2; gz++) {
      const cell = roadGrid.get(`${gx},${gz}`);
      if (!cell) continue;
      for (const pt of cell) {
        const dist = Math.hypot(pt.x - x, pt.z - z);
        const edge = dist - pt.halfWidth;
        if (!best || edge < best.edge) {
          best = { dist, edge, halfWidth: pt.halfWidth, surface: pt.surface };
        }
      }
    }
  }
  return best || { dist: 60, edge: 60, halfWidth: ROAD_HALF, surface: 'grass' };
}
function terrainHeight(x, z, roadDist = null) {
  // Festival Britain: высота — из фундамента 4×4 км (рельеф + выравнивание дорог).
  if (isBritainWorld()) return worldFoundation.heightAt(x, z);
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
let bushMesh = null;
let menuStage = null;
let festivalWheel = null;
const windTurbines = [];
const ambientCars = [];
const pedestrians = [];
const birds = [];
const cloudGroup = new THREE.Group();
scene.add(cloudGroup);

/* ============================ Мир ============================ */
const colliders = []; // {x,z,r}
// Метка: все объекты сцены после неё до захвата у «Модели машины» —
// legacy-остров. В режиме Britain они скрываются одним списком.
const LEGACY_SCENE_MARK = scene.children.length;

// Небо
{
  const sky = new THREE.Mesh(
    new THREE.SphereGeometry(950, 32, 20),
    new THREE.MeshBasicMaterial({ map: makeSkyTexture(), side: THREE.BackSide, fog: false })
  );
  scene.add(sky);
  skyMesh = sky;
  const sunBall = new THREE.Mesh(
    new THREE.SphereGeometry(27, 20, 20),
    new THREE.MeshBasicMaterial({ color: 0xffe6ae, fog: false })
  );
  sunBall.position.set(-560, 132, -620);
  scene.add(sunBall);
  sunBallMesh = sunBall;
  const halo = new THREE.Sprite(new THREE.SpriteMaterial({
    map: makeGlowTexture(), color: 0xffc98a, transparent: true, opacity: 0.9,
    blending: THREE.AdditiveBlending, depthWrite: false, fog: false,
  }));
  halo.scale.set(380, 380, 1);
  halo.position.copy(sunBall.position);
  scene.add(halo);
  sunHaloMesh = halo;
}

// Реалистичное небо и солнце (v0.12): сгенерированная фотопанорама заката
// заменяет канвасный градиент на сфере неба и даёт настоящие отражения
// окружения (PMREM) для краски машин и стеклянных фасадов. Канвасные
// текстуры остаются мгновенным фолбэком до загрузки.
{
  const skyLoader = new THREE.TextureLoader();
  // Три панорамы неба пользователя: день / закат / ночь. Каждая даёт и фон
  // неба, и настоящие PMREM-отражения окружения; время суток переключается
  // кнопками «Небо» в меню и сохраняется между запусками.
  const SKY_URLS = { day: skyDayUrl, sunset: skySunsetUrl, night: skyNightUrl };
  const SKY_TUNING = {
    day: { sun: 0xfff1d6, sunI: 3.2, hemi: 0.62, fog: 0xd9e6ea, env: 1.05 },
    sunset: { sun: 0xffa25e, sunI: 2.6, hemi: 0.5, fog: 0xe2ac7e, env: 1.0 },
    night: { sun: 0x8fb4ff, sunI: 0.55, hemi: 0.16, fog: 0x0d1626, env: 0.55 },
  };
  const skyTextures = {};
  const skyEnvs = {};
  const skyPmrem = new THREE.PMREMGenerator(renderer);
  const applySkyTexture = (mood) => {
    const tex = skyTextures[mood];
    if (!tex) return;
    if (skyMesh) {
      skyMesh.material.map = tex;
      skyMesh.material.needsUpdate = true;
    }
    if (!skyEnvs[mood]) skyEnvs[mood] = skyPmrem.fromEquirectangular(tex).texture;
    scene.environment = skyEnvs[mood];
  };
  applySkyMood = (mood, announce = false) => {
    skyMood = SKY_URLS[mood] ? mood : 'day';
    safeSetItem('nh_sky', skyMood);
    const tune = SKY_TUNING[skyMood];
    sun.color.set(tune.sun);
    sun.intensity = tune.sunI;
    hemiLight.intensity = tune.hemi;
    if (scene.fog) scene.fog.color.set(tune.fog);
    if ('environmentIntensity' in scene) scene.environmentIntensity = tune.env;
    renderer.toneMappingExposure = (SKY_EXPOSURE[skyMood] || 1.3)
      * (graphicsQuality === 'realistic' ? 1 : 0.85);
    if (bloomPass) {
      bloomPass.strength = skyMood === 'night' ? 0.55 : skyMood === 'sunset' ? 0.34 : 0.2;
    }
    if (realWorldSceneHandle?.setSkyMood) realWorldSceneHandle.setSkyMood(skyMood);
    if (sunBallMesh) sunBallMesh.visible = skyMood !== 'night';
    if (sunHaloMesh) sunHaloMesh.visible = skyMood !== 'night';
    document.querySelectorAll('[data-sky]').forEach((btn) => {
      const active = btn.dataset.sky === skyMood;
      btn.classList.toggle('active', active);
      btn.setAttribute('aria-pressed', active ? 'true' : 'false');
    });
    if (skyTextures[skyMood]) {
      applySkyTexture(skyMood);
    } else {
      const wanted = skyMood;
      skyLoader.load(SKY_URLS[wanted], (tex) => {
        tex.colorSpace = THREE.SRGBColorSpace;
        tex.mapping = THREE.EquirectangularReflectionMapping;
        skyTextures[wanted] = tex;
        if (skyMood === wanted) applySkyTexture(wanted);
      });
    }
    if (announce) {
      const label = skyMood === 'day' ? 'Небо: день' : skyMood === 'sunset' ? 'Небо: закат' : 'Небо: ночь';
      showCenterMsg(label, 1100, '#fff', 'sparkles');
    }
  };
  applySkyMood(skyMood);
  skyLoader.load(sunGlowUrl, (tex) => {
    tex.colorSpace = THREE.SRGBColorSpace;
    if (sunHaloMesh) {
      sunHaloMesh.material.map = tex;
      sunHaloMesh.material.color.set(0xffffff);
      sunHaloMesh.material.opacity = 0.95;
      sunHaloMesh.material.needsUpdate = true;
      sunHaloMesh.scale.set(540, 540, 1);
    }
    if (sunBallMesh) {
      sunBallMesh.material.color.set(0xfff6dc);
      sunBallMesh.scale.setScalar(0.5);
    }
  });
  // Облака: альфа-канал строится из яркости сгенерированного облака на
  // чёрном фоне — получается мягкий реалистичный спрайт без квадратной рамки.
  const cloudImg = new Image();
  cloudImg.onload = () => {
    const W = 512;
    const H = Math.max(64, Math.round(W * cloudImg.naturalHeight / Math.max(1, cloudImg.naturalWidth)));
    const c = document.createElement('canvas');
    c.width = W;
    c.height = H;
    const g = c.getContext('2d');
    g.drawImage(cloudImg, 0, 0, W, H);
    const data = g.getImageData(0, 0, W, H);
    const px = data.data;
    for (let i = 0; i < px.length; i += 4) {
      const lum = (px[i] * 0.299 + px[i + 1] * 0.587 + px[i + 2] * 0.114) / 255;
      px[i + 3] = Math.round(Math.pow(clamp((lum - 0.03) / 0.97, 0, 1), 1.15) * 255);
    }
    g.putImageData(data, 0, 0);
    const cloudTex = new THREE.CanvasTexture(c);
    cloudTex.colorSpace = THREE.SRGBColorSpace;
    cloudGroup.children.forEach((sprite) => {
      sprite.material.map = cloudTex;
      sprite.material.color.set(0xffffff);
      sprite.material.needsUpdate = true;
    });
    // Дополнительный дальний слой крупных облаков.
    for (let i = 0; i < 14; i++) {
      const sprite = new THREE.Sprite(new THREE.SpriteMaterial({
        map: cloudTex, color: 0xffffff, transparent: true,
        opacity: 0.5 + Math.random() * 0.3, depthWrite: false, fog: false,
      }));
      const a = Math.random() * Math.PI * 2;
      const dist = 320 + Math.random() * 330;
      sprite.position.set(Math.cos(a) * dist, 120 + Math.random() * 90, Math.sin(a) * dist);
      const w = 170 + Math.random() * 190;
      sprite.scale.set(w, w * 0.38, 1);
      sprite.userData.speed = 0.6 + Math.random() * 1.1;
      cloudGroup.add(sprite);
    }
  };
  cloudImg.src = cloudPuffUrl;
}

// Океан и остров (рельефная местность)
{
  const waterNormal = makeWaterNormalTexture();
  waterMaterial = new THREE.MeshPhysicalMaterial({
    color: 0x166f96, roughness: 0.09, metalness: 0,
    normalMap: waterNormal, normalScale: new THREE.Vector2(0.78, 0.78),
    transparent: true, opacity: 0.94, envMapIntensity: 1.52,
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

  const terrainGeo = new THREE.PlaneGeometry(640, 640, 168, 168);
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
  const cGrass = new THREE.Color(0x5f9d43);
  const cDry = new THREE.Color(0x99a454);
  const cForest = new THREE.Color(0x2f6334);
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
      map: groundTex, bumpMap: groundTex, bumpScale: 0.5,
      vertexColors: true, roughness: 1, metalness: 0, envMapIntensity: 0.32,
    })
  );
  terrain.receiveShadow = true;
  scene.add(terrain);
}

const streetTex = makeStreetTexture();
const streetRoadMat = new THREE.MeshStandardMaterial({
  map: streetTex, bumpMap: streetTex, bumpScale: 0.16,
  roughness: 0.9, envMapIntensity: 0.38, side: THREE.DoubleSide,
});
const plainAsphaltMat = new THREE.MeshStandardMaterial({ color: 0x34373c, roughness: 0.92, envMapIntensity: 0.3 });
const concreteTex = makeConcreteTexture();
const sidewalkMat = new THREE.MeshStandardMaterial({
  map: concreteTex, bumpMap: concreteTex, bumpScale: 0.18,
  color: 0xb8bcb8, roughness: 0.98, envMapIntensity: 0.22, side: THREE.DoubleSide,
});
const secondaryShoulderTex = makeGroundTexture();
secondaryShoulderTex.repeat.set(1, 1);
const roadShoulderMat = new THREE.MeshStandardMaterial({
  map: secondaryShoulderTex, bumpMap: secondaryShoulderTex, bumpScale: 0.42,
  color: 0x8a7a5f, roughness: 1.0, side: THREE.DoubleSide,
});
function makeRoadStripGeometry(road, leftOffset, rightOffset, yLift) {
  const samples = road.samples, positions = [], uvs = [], indices = [];
  let travelled = 0;
  for (let i = 0; i < samples.length; i++) {
    const pt = samples[i];
    const prev = samples[(i - 1 + samples.length) % samples.length];
    const next = samples[(i + 1) % samples.length];
    const from = road.closed || i > 0 ? prev : pt;
    const to = road.closed || i < samples.length - 1 ? next : pt;
    const tx = to.x - from.x, tz = to.z - from.z, tl = Math.hypot(tx, tz) || 1;
    const nx = -tz / tl, nz = tx / tl;
    if (i > 0) travelled += Math.hypot(pt.x - samples[i - 1].x, pt.z - samples[i - 1].z);
    const y = terrainHeight(pt.x, pt.z, 0) + yLift;
    positions.push(pt.x + nx * leftOffset, y, pt.z + nz * leftOffset, pt.x + nx * rightOffset, y, pt.z + nz * rightOffset);
    uvs.push(0, travelled / 8, 1, travelled / 8);
  }
  const segments = road.closed ? samples.length : samples.length - 1;
  for (let i = 0; i < segments; i++) {
    const a = i * 2, b = ((i + 1) % samples.length) * 2;
    indices.push(a, b, a + 1, b, b + 1, a + 1);
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  geo.setAttribute('uv', new THREE.Float32BufferAttribute(uvs, 2));
  geo.setIndex(indices); geo.computeVertexNormals();
  return geo;
}
function addRoadDisc(x, z, radius) {
  const disc = new THREE.Mesh(new THREE.CircleGeometry(radius, 28), plainAsphaltMat);
  disc.rotation.x = -Math.PI / 2;
  disc.position.set(x, terrainHeight(x, z, 0) + 0.11, z);
  disc.receiveShadow = true; scene.add(disc); return disc;
}
function buildSecondaryRoads() {
  for (const road of SECONDARY_ROADS) {
    const asphalt = new THREE.Mesh(makeRoadStripGeometry(road, -road.halfWidth, road.halfWidth, 0.075), streetRoadMat);
    asphalt.receiveShadow = true; scene.add(asphalt);
    const shoulderOffset = road.sidewalk ? road.halfWidth + 0.95 : road.halfWidth;
    for (const side of [-1, 1]) {
      if (road.sidewalk) {
        const walk = new THREE.Mesh(makeRoadStripGeometry(road, side * road.halfWidth, side * (road.halfWidth + 0.95), 0.105), sidewalkMat);
        walk.receiveShadow = true; scene.add(walk);
      }
      const shoulder = new THREE.Mesh(makeRoadStripGeometry(road, side * shoulderOffset, side * (shoulderOffset + 0.85), 0.045), roadShoulderMat);
      shoulder.receiveShadow = true; scene.add(shoulder);
    }
    if (!road.closed) {
      const a = road.samples[0], b = road.samples[road.samples.length - 1];
      addRoadDisc(a.x, a.z, road.halfWidth + 2.4); addRoadDisc(b.x, b.z, road.halfWidth + 2.4);
    }
  }
  addRoadDisc(140, 5, 7.2); addRoadDisc(112, -10, 6.4); addRoadDisc(72, 4, 6.4);
  addRoadDisc(2, -174, 6.2); addRoadDisc(-174, 22, 6.2); addRoadDisc(116, 164, 6.5); addRoadDisc(187, 91, 6.5);
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
      map: asphaltTex, bumpMap: asphaltTex, bumpScale: 0.22,
      roughness: 0.9, metalness: 0, envMapIntensity: 0.42,
    })
  );
  road.receiveShadow = true;
  scene.add(road);
  buildSecondaryRoads();
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
  [[2.05, 0, 4.85, 0, 1.18], [1.45, -1.05, 4.15, 0.35, 1], [1.35, 1.1, 4.3, -0.25, 1], [1.05, 0.15, 5.75, 0.55, 0.95], [0.98, -1.55, 5.05, -0.55, 0.85], [0.9, 1.55, 5.18, 0.65, 0.85]].forEach(([r, x, y, z, sy]) => {
    const part = displaceGeo(new THREE.SphereGeometry(r, 11, 8), 0.28, 0.55);
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
  while (treePos.length < 330 && guard++ < 9000) {
    const a = rnd() * TAU;
    const r = 22 + rnd() * 248;
    const x = Math.cos(a) * r;
    const z = Math.sin(a) * r;
    const roadDist = roadDistanceApprox(x, z);
    if (roadDist < 12.6) continue;
    const h = terrainHeight(x, z, roadDist);
    if (h > 7.6 || h < -0.15) continue; // на голых скалах и в воде деревья не растут
    treePos.push({ x, z, h, pine: rnd() > 0.46, s: 0.82 + rnd() * 0.68, rot: rnd() * TAU });
    if (treePos.length % 4 === 0) colliders.push({ x, z, r: 0.4 });
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
    broadleaf.setColorAt(i, tmpC.setHSL(0.29 + rnd() * 0.06, 0.3 + rnd() * 0.18, 0.52 + rnd() * 0.2));
  });
  pineList.forEach((t, i) => {
    dummy.position.set(t.x, t.h - 0.08, t.z);
    dummy.rotation.set(0, t.rot, 0);
    dummy.scale.setScalar(t.s);
    dummy.updateMatrix();
    pines.setMatrixAt(i, dummy.matrix);
    pines.setColorAt(i, tmpC.setHSL(0.33 + rnd() * 0.04, 0.26, 0.48 + rnd() * 0.16));
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
    95
  );
  for (let i = 0; i < 95; i++) {
    let x = 0, z = 0, h = 0;
    for (let tries = 0; tries < 20; tries++) {
      const a = rnd() * TAU;
      const r = 28 + rnd() * 240;
      x = Math.cos(a) * r;
      z = Math.sin(a) * r;
      const roadDist = roadDistanceApprox(x, z);
      if (roadDist < 10.5) continue;
      h = terrainHeight(x, z, roadDist);
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

  // Общая выборка точек растительности: большая часть ставится рядом с
  // дорогами, где её реально видно из машины, а не вдали от маршрутов.
  function sampleVegetationPoint(roadBias, minOffset, maxOffset) {
    const pick = rnd();
    const side = rnd() < 0.5 ? -1 : 1;
    if (pick < roadBias * 0.68) {
      return pointAtS(rnd() * TRACK_LENGTH, side * (ROAD_HALF + minOffset + rnd() * (maxOffset - minOffset))).pos;
    }
    if (pick < roadBias) {
      const road = SECONDARY_ROADS[(rnd() * SECONDARY_ROADS.length) | 0];
      return pointOnRoad(road, rnd() * road.length, side * (road.halfWidth + minOffset + rnd() * (maxOffset - minOffset))).pos;
    }
    const a = rnd() * TAU;
    const r = 12 + Math.pow(rnd(), 0.75) * 262;
    return { x: Math.cos(a) * r, z: Math.sin(a) * r };
  }

  // Низкие кусты закрывают переход «асфальт → трава → лес» и дают глубину обочинам
  const bushGeo = displaceGeo(new THREE.SphereGeometry(1, 11, 8), 0.18, 0.85);
  bushGeo.scale(1.25, 0.62, 1);
  bushGeo.translate(0, 0.48, 0);
  const BUSH_COUNT = 260;
  bushMesh = new THREE.InstancedMesh(
    bushGeo,
    new THREE.MeshStandardMaterial({ map: leafTex, roughness: 1, envMapIntensity: 0.28 }),
    BUSH_COUNT
  );
  let placedBushes = 0;
  guard = 0;
  while (placedBushes < BUSH_COUNT && guard++ < BUSH_COUNT * 7) {
    const pt = sampleVegetationPoint(0.68, 0.8, 14);
    const d = roadDistanceApprox(pt.x, pt.z);
    if (d < 7.4) continue;
    const h = terrainHeight(pt.x, pt.z, d);
    if (h < 0.02 || h > 8.2) continue;
    const bs = 0.7 + rnd() * 1.15;
    dummy.position.set(pt.x, h - 0.05, pt.z);
    dummy.rotation.set(0, rnd() * TAU, 0);
    dummy.scale.set(bs * (0.85 + rnd() * 0.45), bs * (0.72 + rnd() * 0.38), bs * (0.85 + rnd() * 0.45));
    dummy.updateMatrix();
    bushMesh.setMatrixAt(placedBushes, dummy.matrix);
    bushMesh.setColorAt(placedBushes, tmpC.setHSL(0.28 + rnd() * 0.07, 0.3 + rnd() * 0.16, 0.48 + rnd() * 0.2));
    placedBushes++;
  }
  bushMesh.count = placedBushes;
  if (bushMesh.instanceColor) bushMesh.instanceColor.needsUpdate = true;
  bushMesh.receiveShadow = true;
  scene.add(bushMesh);

  // пучки травы крест-накрест
  const bladePlane = new THREE.PlaneGeometry(0.92, 0.58);
  bladePlane.translate(0, 0.28, 0);
  const bladePlane2 = bladePlane.clone();
  bladePlane2.rotateY(Math.PI / 2);
  const grassGeo = mergeGeometries([bladePlane, bladePlane2]);
  const GRASS_COUNT = 3800;
  grassMesh = new THREE.InstancedMesh(
    grassGeo,
    new THREE.MeshStandardMaterial({
      map: makeGrassBladeTexture(), alphaTest: 0.3, side: THREE.DoubleSide, roughness: 1,
    }),
    GRASS_COUNT
  );
  let placedGrass = 0;
  guard = 0;
  while (placedGrass < GRASS_COUNT && guard++ < GRASS_COUNT * 6) {
    const pt = sampleVegetationPoint(0.62, 0.7, 15);
    const x = pt.x;
    const z = pt.z;
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
    grassMesh.setColorAt(placedGrass, tmpC.setHSL(0.26 + rnd() * 0.09, 0.38, 0.5 + rnd() * 0.22));
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
    if (nearestRoadInfoApprox(p.pos.x, p.pos.z).edge < 9.5) continue;
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
  for (let i = 0; i < 32; i++) {
    const sprite = new THREE.Sprite(new THREE.SpriteMaterial({
      map: cloudTex, color: rnd() > 0.45 ? 0xffe3c8 : 0xeaf3ff,
      transparent: true, opacity: 0.36 + rnd() * 0.3,
      depthWrite: false, fog: false,
    }));
    const a = rnd() * TAU;
    const dist = 160 + rnd() * 420;
    sprite.position.set(Math.cos(a) * dist, 95 + rnd() * 85, Math.sin(a) * dist);
    const w = 90 + rnd() * 170;
    sprite.scale.set(w, w * 0.34, 1);
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
    const beam = new THREE.Mesh(new THREE.BoxGeometry(ROAD_HALF * 2 + 1.2, 0.38, 0.3), mat);
    beam.position.y = 4.35;
    grp.add(beam);
    [-1, 1].forEach((side) => {
      const flare = new THREE.Mesh(new THREE.BoxGeometry(0.34, 1.05, 0.34), mat);
      flare.position.set(side * (ROAD_HALF + 0.6), 3.55, 0);
      grp.add(flare);
    });
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


// Сцена шоурума в меню: световые линии и локальный свет вокруг машины у старта
{
  const start = pointAtS(-10, 0);
  menuStage = new THREE.Group();
  const orangeLine = new THREE.MeshBasicMaterial({ color: 0xff8a3a, transparent: true, opacity: 0.82 });
  const cyanLine = new THREE.MeshBasicMaterial({ color: 0x35d5ff, transparent: true, opacity: 0.72 });
  [-1, 1].forEach((side) => {
    const strip = new THREE.Mesh(new THREE.BoxGeometry(0.14, 0.035, 7.4), side < 0 ? orangeLine : cyanLine);
    strip.position.set(side * 1.68, 0, 0);
    menuStage.add(strip);
    const pylon = new THREE.Mesh(
      new THREE.BoxGeometry(0.28, 0.72, 0.28),
      new THREE.MeshStandardMaterial({ color: 0x151a24, roughness: 0.55, metalness: 0.35 })
    );
    pylon.position.set(side * 1.68, 0.36, 3.7);
    pylon.castShadow = true;
    menuStage.add(pylon);
  });
  [-1, 1].forEach((end) => {
    const strip = new THREE.Mesh(new THREE.BoxGeometry(3.5, 0.035, 0.14), end < 0 ? cyanLine : orangeLine);
    strip.position.set(0, 0, end * 3.7);
    menuStage.add(strip);
  });
  const keyLight = new THREE.SpotLight(0xffd7a8, 55, 20, 0.62, 0.65, 1.2);
  keyLight.position.set(-3.4, 5.6, 4.6);
  keyLight.target.position.set(0, 0.65, 0);
  const rimLight = new THREE.PointLight(0x35c5ff, 12, 11, 1.6);
  rimLight.position.set(3.4, 1.5, -3.6);
  menuStage.add(keyLight, keyLight.target, rimLight);
  menuStage.position.copy(start.pos);
  menuStage.position.y = terrainHeight(start.pos.x, start.pos.z, 0) + 0.055;
  menuStage.rotation.y = start.yaw + 0.6;
  scene.add(menuStage);
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
  const churchPos = { x: 99, z: -23 };
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


/* ==================== Инфраструктура острова ==================== */
function infraGroundY(x, z) { return terrainHeight(x, z, 0); }
function infraBox(parent, w, h, d, mat, x, y, z, yaw = 0) {
  const mesh = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
  mesh.position.set(x, y, z);
  mesh.rotation.y = yaw;
  mesh.castShadow = true;
  mesh.receiveShadow = true;
  parent.add(mesh);
  return mesh;
}
function makeDirectionSignTexture(text) {
  const c = document.createElement('canvas');
  c.width = 256; c.height = 96;
  const g = c.getContext('2d');
  g.fillStyle = '#14532d'; g.fillRect(0, 0, 256, 96);
  g.strokeStyle = '#ffffff'; g.lineWidth = 6; g.strokeRect(5, 5, 246, 86);
  g.fillStyle = '#ffffff';
  g.font = '700 30px Arial, sans-serif';
  g.textAlign = 'center'; g.textBaseline = 'middle';
  g.fillText(text, 128, 50);
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}
function addCrosswalkOnRoad(road, sPos) {
  const p = pointOnRoad(road, sPos, 0);
  const mat = new THREE.MeshBasicMaterial({
    map: makeCrosswalkTexture(), transparent: true, depthWrite: false,
    polygonOffset: true, polygonOffsetFactor: -2,
  });
  const mesh = new THREE.Mesh(new THREE.PlaneGeometry(road.halfWidth * 2 - 0.7, 2.7), mat);
  mesh.rotation.x = -Math.PI / 2;
  const group = new THREE.Group();
  group.position.set(p.pos.x, infraGroundY(p.pos.x, p.pos.z) + 0.16, p.pos.z);
  group.rotation.y = p.yaw;
  group.add(mesh);
  scene.add(group);
}
function addGuardrails(road, side, s0, s1) {
  const spots = [];
  for (let sPos = s0; sPos <= s1; sPos += 8) {
    const p = pointOnRoad(road, sPos, side * (road.halfWidth + 0.65));
    spots.push({ x: p.pos.x, y: infraGroundY(p.pos.x, p.pos.z), z: p.pos.z, yaw: p.yaw });
    colliders.push({ x: p.pos.x, z: p.pos.z, r: 0.42 });
  }
  if (spots.length < 2) return;
  const metal = new THREE.MeshStandardMaterial({ color: 0xb8bec4, roughness: 0.38, metalness: 0.72 });
  const postMat = new THREE.MeshStandardMaterial({ color: 0x555c62, roughness: 0.65, metalness: 0.45 });
  const dummy = new THREE.Object3D();
  const posts = new THREE.InstancedMesh(new THREE.BoxGeometry(0.16, 0.75, 0.16), postMat, spots.length);
  spots.forEach((spot, i) => {
    dummy.position.set(spot.x, spot.y + 0.38, spot.z);
    dummy.rotation.set(0, spot.yaw, 0);
    dummy.scale.set(1, 1, 1);
    dummy.updateMatrix();
    posts.setMatrixAt(i, dummy.matrix);
  });
  posts.castShadow = true;
  scene.add(posts);
  const rails = new THREE.InstancedMesh(new THREE.BoxGeometry(0.07, 0.3, 1), metal, spots.length - 1);
  for (let i = 0; i < spots.length - 1; i++) {
    const a = spots[i], b = spots[i + 1];
    const dx = b.x - a.x, dz = b.z - a.z;
    dummy.position.set((a.x + b.x) / 2, (a.y + b.y) / 2 + 0.66, (a.z + b.z) / 2);
    dummy.rotation.set(0, Math.atan2(dx, dz), 0);
    dummy.scale.set(1, 1, Math.hypot(dx, dz) + 0.08);
    dummy.updateMatrix();
    rails.setMatrixAt(i, dummy.matrix);
  }
  rails.castShadow = true;
  scene.add(rails);
}
function addPowerLine(road, side, s0, s1, step = 28) {
  const poleMat = new THREE.MeshStandardMaterial({ color: 0x6b4a32, roughness: 0.92 });
  const tops = [];
  for (let sPos = s0; sPos <= s1; sPos += step) {
    const p = pointOnRoad(road, sPos, side * (road.halfWidth + 2.3));
    const y = infraGroundY(p.pos.x, p.pos.z);
    const group = new THREE.Group();
    group.position.set(p.pos.x, y, p.pos.z);
    group.rotation.y = p.yaw;
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.11, 0.15, 7.8, 7), poleMat);
    pole.position.y = 3.9;
    pole.castShadow = true;
    const cross = infraBox(group, 1.7, 0.13, 0.14, poleMat, 0, 7.35, 0);
    cross.castShadow = true;
    group.add(pole);
    scene.add(group);
    colliders.push({ x: p.pos.x, z: p.pos.z, r: 0.28 });
    tops.push(new THREE.Vector3(p.pos.x, y + 7.35, p.pos.z));
  }
  const wireMat = new THREE.LineBasicMaterial({ color: 0x111318, transparent: true, opacity: 0.72 });
  for (let i = 0; i < tops.length - 1; i++) {
    const pts = [];
    for (let k = 0; k <= 8; k++) {
      const t = k / 8;
      const pt = tops[i].clone().lerp(tops[i + 1], t);
      pt.y -= Math.sin(t * Math.PI) * 0.65;
      pts.push(pt);
    }
    scene.add(new THREE.Line(new THREE.BufferGeometry().setFromPoints(pts), wireMat));
  }
}
function addStreetLamp(x, z, yaw) {
  const y = infraGroundY(x, z);
  const group = new THREE.Group();
  group.position.set(x, y, z);
  group.rotation.y = yaw;
  const poleMat = new THREE.MeshStandardMaterial({ color: 0x3f464d, roughness: 0.45, metalness: 0.65 });
  const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.07, 0.1, 5.4, 8), poleMat);
  pole.position.y = 2.7;
  pole.castShadow = true;
  const head = infraBox(group, 0.28, 0.16, 0.9, new THREE.MeshStandardMaterial({
    color: 0xfff0bb, emissive: 0xffd777, emissiveIntensity: 1.5,
  }), 0, 5.42, 0.35);
  head.castShadow = false;
  group.add(pole);
  scene.add(group);
  colliders.push({ x, z, r: 0.24 });
}
function addDirectionSign(x, z, yaw, text) {
  const y = infraGroundY(x, z);
  const group = new THREE.Group();
  group.position.set(x, y, z);
  group.rotation.y = yaw;
  const poleMat = new THREE.MeshStandardMaterial({ color: 0x777f86, roughness: 0.45, metalness: 0.6 });
  [-0.65, 0.65].forEach((px) => {
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.055, 0.055, 2.5, 7), poleMat);
    pole.position.set(px, 1.25, 0);
    pole.castShadow = true;
    group.add(pole);
  });
  const panel = new THREE.Mesh(
    new THREE.BoxGeometry(2.35, 0.88, 0.07),
    new THREE.MeshStandardMaterial({ map: makeDirectionSignTexture(text), roughness: 0.55 })
  );
  panel.position.y = 2.55;
  panel.castShadow = true;
  group.add(panel);
  scene.add(group);
  colliders.push({ x, z, r: 0.45 });
}
function addStopSign(x, z, yaw) {
  const y = infraGroundY(x, z);
  const group = new THREE.Group();
  group.position.set(x, y, z);
  group.rotation.y = yaw;
  const pole = new THREE.Mesh(
    new THREE.CylinderGeometry(0.05, 0.05, 2.7, 7),
    new THREE.MeshStandardMaterial({ color: 0x7c858d, metalness: 0.55, roughness: 0.45 })
  );
  pole.position.y = 1.35;
  pole.castShadow = true;
  const sign = new THREE.Mesh(
    new THREE.CylinderGeometry(0.48, 0.48, 0.06, 8),
    new THREE.MeshStandardMaterial({ color: 0xb91c1c, roughness: 0.5, emissive: 0x450a0a, emissiveIntensity: 0.35 })
  );
  sign.rotation.x = Math.PI / 2;
  sign.position.y = 2.72;
  sign.castShadow = true;
  group.add(pole, sign);
  scene.add(group);
  colliders.push({ x, z, r: 0.25 });
}
function addBusStop(road, sPos, side) {
  const p = pointOnRoad(road, sPos, side * (road.halfWidth + 2.0));
  const y = infraGroundY(p.pos.x, p.pos.z);
  const group = new THREE.Group();
  group.position.set(p.pos.x, y, p.pos.z);
  group.rotation.y = p.yaw;
  const concrete = new THREE.MeshStandardMaterial({ color: 0x9a9d9b, roughness: 0.95 });
  const frame = new THREE.MeshStandardMaterial({ color: 0x274156, roughness: 0.45, metalness: 0.55 });
  const glass = new THREE.MeshPhysicalMaterial({ color: 0x9fc9d8, roughness: 0.12, metalness: 0.15, transparent: true, opacity: 0.42 });
  infraBox(group, 4.4, 0.14, 1.8, concrete, 0, 0.07, 0);
  [-1.95, 1.95].forEach((x) => {
    infraBox(group, 0.12, 2.35, 0.12, frame, x, 1.18, -0.72);
    infraBox(group, 0.12, 2.35, 0.12, frame, x, 1.18, 0.72);
  });
  infraBox(group, 4.5, 0.13, 1.85, frame, 0, 2.45, 0);
  infraBox(group, 3.7, 1.35, 0.045, glass, 0, 1.32, -0.72);
  infraBox(group, 3.4, 0.12, 0.42, new THREE.MeshStandardMaterial({ color: 0x8a5a34, roughness: 0.85 }), 0, 0.58, -0.35);
  scene.add(group);
  colliders.push({ x: p.pos.x, z: p.pos.z, r: 2.25 });
}
function addParkingLot(x, z, width, depth, yaw) {
  const y = infraGroundY(x, z);
  const group = new THREE.Group();
  group.position.set(x, y + 0.1, z);
  group.rotation.y = yaw;
  const slab = new THREE.Mesh(new THREE.PlaneGeometry(width, depth), plainAsphaltMat);
  slab.rotation.x = -Math.PI / 2;
  slab.receiveShadow = true;
  group.add(slab);
  const lineMat = new THREE.MeshBasicMaterial({ color: 0xf5f5f0 });
  const bayCount = Math.max(2, Math.floor(width / 2.6));
  for (let i = 0; i <= bayCount; i++) {
    const line = new THREE.Mesh(new THREE.PlaneGeometry(0.09, 4.7), lineMat);
    line.rotation.x = -Math.PI / 2;
    line.position.set(-width / 2 + (width / bayCount) * i, 0.025, -depth / 2 + 2.45);
    group.add(line);
  }
  scene.add(group);
}
function addBollards(points) {
  const mat = new THREE.MeshStandardMaterial({ color: 0x293241, roughness: 0.45, metalness: 0.55 });
  const stripeMat = new THREE.MeshStandardMaterial({ color: 0xf8fafc, emissive: 0xffffff, emissiveIntensity: 0.18 });
  const geo = new THREE.CylinderGeometry(0.11, 0.13, 0.85, 9);
  const stripeGeo = new THREE.CylinderGeometry(0.116, 0.116, 0.13, 9);
  const dummy = new THREE.Object3D();
  const posts = new THREE.InstancedMesh(geo, mat, points.length);
  const stripes = new THREE.InstancedMesh(stripeGeo, stripeMat, points.length);
  points.forEach(([x, z], i) => {
    const y = infraGroundY(x, z);
    dummy.position.set(x, y + 0.43, z); dummy.rotation.set(0, 0, 0); dummy.scale.set(1, 1, 1); dummy.updateMatrix();
    posts.setMatrixAt(i, dummy.matrix);
    dummy.position.y = y + 0.68; dummy.updateMatrix();
    stripes.setMatrixAt(i, dummy.matrix);
    colliders.push({ x, z, r: 0.22 });
  });
  posts.castShadow = true;
  scene.add(posts, stripes);
}
function addVillageHouse(x, z, yaw, wallColor, roofColor) {
  const y = infraGroundY(x, z);
  const group = new THREE.Group();
  group.position.set(x, y - 0.15, z);
  group.rotation.y = yaw;
  const walls = infraBox(group, 8.2, 5.4, 6.8, new THREE.MeshStandardMaterial({ color: wallColor, roughness: 0.92 }), 0, 2.7, 0);
  walls.receiveShadow = true;
  const roofGeo = new THREE.ConeGeometry(1, 2.7, 4);
  roofGeo.rotateY(Math.PI / 4);
  roofGeo.scale(6.5, 1, 5.4);
  const roof = new THREE.Mesh(roofGeo, new THREE.MeshStandardMaterial({ color: roofColor, roughness: 0.9, flatShading: true }));
  roof.position.y = 6.75;
  roof.castShadow = true;
  group.add(roof);
  const door = infraBox(group, 0.95, 2.05, 0.08, new THREE.MeshStandardMaterial({ color: 0x4a2d1d, roughness: 0.8 }), -1.6, 1.05, 3.43);
  door.castShadow = false;
  const winMat = new THREE.MeshStandardMaterial({ color: 0xffd98a, emissive: 0xffb84d, emissiveIntensity: 0.55, roughness: 0.2 });
  [1.2, 2.8].forEach((wx) => infraBox(group, 1.05, 1.05, 0.06, winMat, wx, 2.0, 3.44));
  infraBox(group, 2.4, 0.16, 1.0, new THREE.MeshStandardMaterial({ color: 0x8d918e, roughness: 0.95 }), -1.6, 0.08, 3.85);
  scene.add(group);
  colliders.push({ x, z, r: 5.4 });
}
function addParkedCarAt(x, z, yaw, color) {
  const built = buildCarMesh(color, 0x39424e, false);
  built.group.position.set(x, infraGroundY(x, z) + 0.04, z);
  built.group.rotation.y = yaw;
  scene.add(built.group);
  [-1.2, 1.2].forEach((dz) => {
    colliders.push({ x: x + Math.sin(yaw) * dz, z: z + Math.cos(yaw) * dz, r: 1.12 });
  });
}
function addParkedCarOnRoad(road, sPos, side, color) {
  const p = pointOnRoad(road, sPos, side * (road.halfWidth - 1.05));
  addParkedCarAt(p.pos.x, p.pos.z, p.yaw + (side < 0 ? Math.PI : 0), color);
}
function addTrafficCones(points) {
  const orange = new THREE.MeshStandardMaterial({ color: 0xf97316, roughness: 0.65 });
  const white = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.55 });
  points.forEach(([x, z]) => {
    const y = infraGroundY(x, z);
    const cone = new THREE.Mesh(new THREE.ConeGeometry(0.23, 0.68, 10), orange);
    cone.position.set(x, y + 0.34, z);
    cone.castShadow = true;
    const band = new THREE.Mesh(new THREE.CylinderGeometry(0.15, 0.19, 0.13, 10), white);
    band.position.set(x, y + 0.39, z);
    scene.add(cone, band);
    colliders.push({ x, z, r: 0.28 });
  });
}
function buildStaticInfrastructure() {
  addCrosswalkOnRoad(villageLoopRoad, 18);
  addCrosswalkOnRoad(villageLoopRoad, 96);
  addCrosswalkOnRoad(villageLoopRoad, 178);
  addCrosswalkOnRoad(SECONDARY_ROADS[0], 34);
  addBusStop(villageLoopRoad, 88, 1);
  addParkingLot(88, -20, 18, 9, 0.08);
  addParkedCarAt(82.4, -21.8, 0.08, 0x7c8794);
  addParkedCarAt(88.2, -21.9, 0.05, 0x334155);
  addParkedCarAt(93.7, -21.7, 0.1, 0x9a3412);
  addParkedCarOnRoad(villageLoopRoad, 34, 1, 0x64748b);
  addParkedCarOnRoad(villageLoopRoad, 125, -1, 0x7f1d1d);
  addParkedCarOnRoad(villageLoopRoad, 205, 1, 0xe5e7eb);
  addDirectionSign(134, 12, -0.8, 'ДЕРЕВНЯ →');
  addDirectionSign(7, -166, 2.9, 'ФЕСТИВАЛЬ');
  addDirectionSign(-168, 14, 1.2, 'ВЕТРЯКИ →');
  addDirectionSign(124, 156, -2.2, 'ПЛЯЖ →');
  addStopSign(119, -17, 2.2);
  addStopSign(58, 21, -0.7);
  addPowerLine(SECONDARY_ROADS[0], -1, 4, 76, 24);
  addPowerLine(villageLoopRoad, 1, 10, 210, 34);
  const mountainRoad = SECONDARY_ROADS[3];
  addGuardrails(mountainRoad, -1, 36, 96);
  addGuardrails(mountainRoad, 1, 108, 166);
  addGuardrails(coastalRoad, 1, 55, 175);
  for (let sPos = 8; sPos < villageLoopRoad.length; sPos += 34) {
    const p = pointOnRoad(villageLoopRoad, sPos, villageLoopRoad.halfWidth + 1.25);
    addStreetLamp(p.pos.x, p.pos.z, p.yaw + Math.PI / 2);
  }
  const houseSpots = [
    [80, -24, 0.2, 0xe7d8bd, 0x9f4634], [115, -20, -0.35, 0xdfe5d8, 0x51606b],
    [110, 21, -1.2, 0xe4cdb2, 0x6d4a3a], [91, 25, 2.8, 0xf0e6cf, 0x7b4b3a],
    [58, 26, 1.4, 0xd9dfd2, 0x8a4b38], [135, -22, -1.55, 0xe9ddca, 0x5f5047],
  ];
  houseSpots.forEach(([x, z, yaw, wall, roof]) => addVillageHouse(x, z, yaw, wall, roof));
  addBollards([[-52, -102], [-48, -110], [-39, 34], [-45, 28], [221, 135], [215, 109], [86, -15], [90, -15]]);
  const coneBase = pointOnRoad(coastalRoad, 118, coastalRoad.halfWidth - 0.7);
  addTrafficCones([
    [coneBase.pos.x, coneBase.pos.z],
    [coneBase.pos.x + 2.2, coneBase.pos.z + 0.7],
    [coneBase.pos.x + 4.4, coneBase.pos.z + 1.1],
  ]);
}


/* ==================== Живой остров ==================== */
function spawnAmbientCar(road, sPos, lane, speed, color) {
  const built = buildCarMesh(color, 0x475569, false);
  scene.add(built.group);
  const car = {
    mesh: built,
    road,
    s: sPos,
    lane,
    speed,
    direction: lane < 0 ? -1 : 1,
    wheelAngle: 0,
  };
  ambientCars.push(car);
  return car;
}
function createPedestrian() {
  const skinTones = [0xf1c7a5, 0xc98d64, 0x8d5a3b, 0xe8b48c];
  const shirtColors = [0xef4444, 0x2563eb, 0xf59e0b, 0x10b981, 0xec4899, 0xe5e7eb, 0x7c3aed];
  const pantsColors = [0x1f2937, 0x334155, 0x57534e, 0x1e3a5f, 0x713f12];
  const skin = new THREE.MeshStandardMaterial({ color: skinTones[Math.floor(rnd() * skinTones.length)], roughness: 0.75 });
  const shirt = new THREE.MeshStandardMaterial({ color: shirtColors[Math.floor(rnd() * shirtColors.length)], roughness: 0.88 });
  const pants = new THREE.MeshStandardMaterial({ color: pantsColors[Math.floor(rnd() * pantsColors.length)], roughness: 0.92 });
  const group = new THREE.Group();
  const torso = new THREE.Mesh(new THREE.BoxGeometry(0.42, 0.62, 0.24), shirt);
  torso.position.y = 1.14;
  torso.castShadow = true;
  group.add(torso);
  const head = new THREE.Mesh(new THREE.SphereGeometry(0.165, 10, 8), skin);
  head.position.y = 1.66;
  head.castShadow = true;
  group.add(head);
  function makeLimb(x, y, mat, len, thick) {
    const pivot = new THREE.Group();
    pivot.position.set(x, y, 0);
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(thick, len, thick), mat);
    mesh.position.y = -len / 2;
    mesh.castShadow = true;
    pivot.add(mesh);
    group.add(pivot);
    return pivot;
  }
  const leftLeg = makeLimb(-0.11, 0.84, pants, 0.8, 0.14);
  const rightLeg = makeLimb(0.11, 0.84, pants, 0.8, 0.14);
  const leftArm = makeLimb(-0.29, 1.4, shirt, 0.58, 0.105);
  const rightArm = makeLimb(0.29, 1.4, shirt, 0.58, 0.105);
  scene.add(group);
  return { group, leftLeg, rightLeg, leftArm, rightArm };
}
function spawnLoopPedestrian(sPos, side, speed) {
  const body = createPedestrian();
  pedestrians.push({
    ...body,
    mode: 'loop',
    s: sPos,
    lane: side * (villageLoopRoad.halfWidth + 0.55),
    direction: side > 0 ? 1 : -1,
    speed,
    phase: rnd() * TAU,
  });
}
function spawnWanderPedestrian(homeX, homeZ, radius = 11) {
  const body = createPedestrian();
  const ped = {
    ...body,
    mode: 'wander',
    x: homeX,
    z: homeZ,
    homeX,
    homeZ,
    radius,
    targetX: homeX,
    targetZ: homeZ,
    yaw: rnd() * TAU,
    speed: 0.75 + rnd() * 0.45,
    phase: rnd() * TAU,
    wait: rnd() * 2,
  };
  ped.group.position.set(homeX, infraGroundY(homeX, homeZ), homeZ);
  pedestrians.push(ped);
}
function spawnStandingPedestrian(x, z, yaw) {
  const body = createPedestrian();
  body.group.position.set(x, infraGroundY(x, z), z);
  body.group.rotation.y = yaw;
  pedestrians.push({ ...body, mode: 'stand', x, z, yaw, phase: rnd() * TAU, speed: 0 });
}
function createBird(centerX, centerZ, radius, height, speed) {
  const group = new THREE.Group();
  const mat = new THREE.MeshBasicMaterial({ color: 0x17202b, side: THREE.DoubleSide });
  const body = new THREE.Mesh(new THREE.SphereGeometry(0.18, 7, 5), mat);
  body.scale.set(0.75, 0.65, 1.9);
  group.add(body);
  function wing(side) {
    const pivot = new THREE.Group();
    const mesh = new THREE.Mesh(new THREE.PlaneGeometry(1.15, 0.3), mat);
    mesh.position.x = side * 0.58;
    mesh.rotation.x = -Math.PI / 2;
    pivot.add(mesh);
    group.add(pivot);
    return pivot;
  }
  const leftWing = wing(-1);
  const rightWing = wing(1);
  scene.add(group);
  birds.push({ group, leftWing, rightWing, centerX, centerZ, radius, height, speed, phase: rnd() * TAU });
}
function buildLivingWorld() {
  spawnAmbientCar(villageLoopRoad, 12, 1.75, 7.5, 0x94a3b8);
  spawnAmbientCar(villageLoopRoad, 105, -1.75, 6.8, 0x7c2d12);
  spawnAmbientCar(villageLoopRoad, 190, 1.75, 7.2, 0x14532d);
  spawnAmbientCar(SECONDARY_ROADS[0], 12, 1.75, 8.2, 0xeab308);
  spawnAmbientCar(coastalRoad, 28, 1.85, 11.5, 0x0f766e);
  spawnAmbientCar(coastalRoad, 150, -1.85, 10.5, 0xf8fafc);
  spawnAmbientCar(SECONDARY_ROADS[3], 30, 1.7, 9.0, 0x7e22ce);
  spawnAmbientCar(null, 420, 2.5, 15.0, 0x475569);
  spawnAmbientCar(null, 980, -2.5, 14.0, 0xb45309);

  spawnLoopPedestrian(8, 1, 1.05);
  spawnLoopPedestrian(62, -1, 0.9);
  spawnLoopPedestrian(112, 1, 1.18);
  spawnLoopPedestrian(151, -1, 0.82);
  spawnLoopPedestrian(198, 1, 0.98);
  spawnLoopPedestrian(232, -1, 1.1);
  spawnWanderPedestrian(-16, -168, 10);
  spawnWanderPedestrian(17, -181, 11);
  spawnWanderPedestrian(-13, -184, 9);
  spawnWanderPedestrian(18, -165, 10);
  const scenic = pointOnRoad(coastalRoad, 132, coastalRoad.halfWidth + 1.7);
  spawnStandingPedestrian(scenic.pos.x, scenic.pos.z, scenic.yaw + Math.PI / 2);
  const churchWalk = pointOnRoad(SECONDARY_ROADS[0], 40, -(SECONDARY_ROADS[0].halfWidth + 0.55));
  spawnStandingPedestrian(churchWalk.pos.x, churchWalk.pos.z, churchWalk.yaw - Math.PI / 2);

  createBird(95, -10, 48, 30, 0.055);
  createBird(98, -8, 58, 35, -0.045);
  createBird(185, 145, 62, 28, 0.05);
  createBird(190, 150, 44, 34, 0.065);
  createBird(0, -175, 55, 38, -0.04);
  createBird(-110, 0, 70, 42, 0.038);
}
buildStaticInfrastructure();
buildLivingWorld();

/* ==================== Скрытие legacy-острова в режиме Britain ====================
   Остров всегда строится как раньше (нужен для ?world=legacy), но на новой
   карте все его объекты выключаются одним списком. Небо и сцена меню —
   исключения: небо едет за игроком, шоурум переезжает к фестивалю. */
const legacyWorldObjects = scene.children.slice(LEGACY_SCENE_MARK);
function applyBritainWorldVisibility() {
  if (!isBritainWorld()) return;
  const keep = new Set([skyMesh, sunBallMesh, sunHaloMesh, menuStage]);
  legacyWorldObjects.forEach((obj) => {
    if (!keep.has(obj)) obj.visible = false;
  });
  colliders.length = 0; // на новой карте пока нет пропсов — и невидимых стен
  if (menuStage) {
    const spawn = britainSpawnPoint();
    menuStage.position.set(spawn.pos.x, worldFoundation.heightAt(spawn.pos.x, spawn.pos.z) + 0.055, spawn.pos.z);
    menuStage.rotation.y = spawn.yaw + 0.6;
  }
}
applyBritainWorldVisibility();

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

let mustangLoadInFlight = false;
function requestMustangModel() {
  if (mustangLoadInFlight) return;
  mustangLoadInFlight = true;
  preloadMustangModel()
    .then(() => {
      mustangLoadInFlight = false;
      if (selectedCar.id !== 'mustang' || !player.mesh) return;
      // Бесшовно заменяем fallback на настоящий GLB, сохраняя позу машины.
      const oldGroup = player.mesh.group;
      const position = oldGroup.position.clone();
      const quaternion = oldGroup.quaternion.clone();
      const scale = oldGroup.scale.clone();
      createPlayerCar();
      if (player.mesh) {
        player.mesh.group.position.copy(position);
        player.mesh.group.quaternion.copy(quaternion);
        player.mesh.group.scale.copy(scale);
      }
    })
    .catch((error) => {
      mustangLoadInFlight = false;
      console.warn('Mustang GLB не загрузился, остаётся fallback-модель:', error);
    });
}

function createPlayerCar() {
  if (player.mesh) {
    scene.remove(player.mesh.group);
  }
  let built;
  if (selectedCar.id === 'gtr35') {
    built = buildGTR35(selectedGTRPaint);
  } else if (selectedCar.id === 'mustang') {
    built = buildMustang(selectedMustangPaint, selectedCar.accent);
    if (!built) {
      // GLB ещё грузится: мгновенно показываем близкий по размеру fallback.
      built = buildCarMesh(selectedCar.color, selectedCar.accent, false);
      requestMustangModel();
    }
  } else {
    built = buildCarMesh(selectedCar.color, selectedCar.accent, selectedCar.id === 'dune');
  }
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
  update(speedRatio, boosting, engineLoad = 0, shifting = false) {
    if (!this.ctx) return;
    const on = this.enabled && (gameState === 'racing' || gameState === 'countdown');
    const load = clamp(engineLoad, 0, 1);
    const shiftDip = shifting ? 0.52 : 1;
    const targetGain = on ? (0.038 + speedRatio * 0.038 + load * 0.055) * shiftDip : 0;
    this.gain.gain.setTargetAtTime(targetGain, this.ctx.currentTime, shifting ? 0.025 : 0.08);
    const rpm = 55 + speedRatio * 190 + load * 14 + (boosting ? 35 : 0);
    this.osc.frequency.setTargetAtTime(rpm, this.ctx.currentTime, 0.05);
    this.osc2.frequency.setTargetAtTime(rpm * (0.5 + load * 0.035) + 3, this.ctx.currentTime, 0.05);
    this.filter.frequency.setTargetAtTime(
      (360 + speedRatio * 780 + load * 720) * (shifting ? 0.72 : 1),
      this.ctx.currentTime,
      shifting ? 0.03 : 0.1,
    );
  },
};

/* ============================ Сообщения / HUD ============================ */
let centerMsgTimer = null;
function showCenterMsg(text, ms = 1900, color = '#fff', iconName = null) {
  const el = $('centerMsg');
  el.replaceChildren();
  if (iconName) {
    const icon = document.createElement('span');
    icon.className = 'center-msg-icon';
    icon.setAttribute('aria-hidden', 'true');
    icon.innerHTML = iconMarkup(iconName, 'ui-icon');
    el.appendChild(icon);
  }
  const label = document.createElement('span');
  label.textContent = text;
  el.appendChild(label);
  el.style.color = color;
  el.style.opacity = '1';
  clearTimeout(centerMsgTimer);
  centerMsgTimer = setTimeout(() => (el.style.opacity = '0'), ms);
}

let driftPopupTimer = null;
function showДрифтPopup(points, chain) {
  const el = $('driftPopup');
  const label = chain > 1 ? `ДРИФТ +${points} ×${chain}` : `ДРИФТ +${points}`;
  el.innerHTML = `${iconMarkup('flame', 'ui-icon')}<span>${label}</span>`;
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
  const start = isBritainWorld() ? britainSpawnPoint(-2.2) : pointAtS(-6, -2.5);
  player.mesh.group.position.copy(start.pos);
  if (isBritainWorld()) {
    player.mesh.group.position.y = worldFoundation.heightAt(start.pos.x, start.pos.z);
  }
  player.yaw = start.yaw;
  player.vel.set(0, 0, 0);
  player.yawRate = 0;
  player.steerAngle = 0;
  player.throttle = 0;
  player.brakePedal = 0;
  resetPlayerPowertrain();
  player.longAccel = 0;
  player.latAccel = 0;
  player.surfaceMuSmooth = 1;
  resetSteering();
  resetCameraOrbit();
  player.nitro = 0.7;
  player.score = 0;
  player.driftChain = 0;
  player.s = isBritainWorld() ? 0 : -6;
  player.sampleAccum = 0;
  player.prevSampleIdx = isBritainWorld() ? 0 : nearestSampleIdx(start.pos).idx;
  player.nextCP = 1;
  player.lap = 1;
  player.lapStart = 0;
  player.finishTime = null;
  player.boosting = false;
}

function createRivals() {
  rivals.forEach((r) => scene.remove(r.mesh.group));
  rivals = [];
  if (isBritainWorld()) return; // соперники ездят по legacy-сплайну; на новой карте — позже
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
  if (isBritainWorld()) selectedMode = 'free';
  resetPlayerToStart();
  createRivals();
  raceTime = 0;
  updateCPVisibility();
  $('menu').classList.add('hidden');
  $('finishMenu').classList.add('hidden');
  $('pauseMenu').classList.add('hidden');
  inspectMode = false;
  if (menuStage) menuStage.visible = false;
  $('inspectBar').classList.add('hidden');
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
    showCenterMsg(
      isBritainWorld() ? 'СВОБОДНАЯ ПОЕЗДКА — Real Valley, 1×1 км!' : 'СВОБОДНАЯ ПОЕЗДКА — твой остров!',
      2600, '#2ee6ff', 'map',
    );
    $('hudPosition').textContent = 'FREE';
    $('hudLap').textContent = 'ОТКРЫТЫЙ МИР';
  }
  updateHUDStatic();
}

function updateHUDStatic() {
  $('hudЛучший').textContent = player.лучшийLap ? fmtTime(player.лучшийLap) : '—';
  $('hudScore').textContent = '0';
  const progressPct = $('hudProgressPct');
  const progressBar = $('hudProgressBar');
  if (progressPct) progressPct.textContent = selectedMode === 'race' ? '0%' : 'FREE';
  if (progressBar) progressBar.style.width = '0%';
  if (speedFxEl) speedFxEl.style.opacity = '0';
}

function updateCPVisibility() {
  cpMeshes.forEach((cp, i) => {
    const isNext = selectedMode === 'race' && i === player.nextCP;
    cp.grp.visible = selectedMode === 'race';
    cp.beamMat.opacity = isNext ? 0.92 : 0.14;
    cp.beamMat.color.setHex(isNext ? 0x7cfc4a : 0xffffff);
    cp.pillarMat.opacity = isNext ? 0.32 : 0;
  });
  $('checkpointArrow').style.display = selectedMode === 'race' ? 'block' : 'none';
}

function finishRace() {
  gameState = 'finished';
  player.finishTime = raceTime;
  showTouchControls(false);
  const pos = currentPosition();
  const placeLabels = [
    '1 место — чемпион фестиваля!',
    '2 место — серебро фестиваля!',
    '3 место — бронза фестиваля!',
    'Финиш!',
    'Финиш!',
    'Финиш!',
  ];
  $('finishTitle').textContent = pos <= 3 ? 'ПОДИУМ!' : 'Финиш!';
  $('finishPlace').innerHTML = pos <= 3
    ? `${iconMarkup('medal', 'ui-icon finish-place-icon')}<span>${placeLabels[pos - 1]}</span>`
    : (placeLabels[pos - 1] || 'Финиш!');

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
    `Очки дрифта: <b>${Math.floor(player.score)}</b> ${iconMarkup('flame', 'ui-icon inline-icon')}`;
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
  if (isBritainWorld()) {
    const pos = player.mesh.group.position;
    const nearRoad = worldFoundation.nearestRoad(pos.x, pos.z, { maxDistanceM: 600 });
    if (nearRoad && nearRoad.segment) {
      const seg = nearRoad.segment;
      let yaw = Math.atan2(seg.x2 - seg.x1, seg.z2 - seg.z1);
      // не разворачиваем игрока против текущего курса без нужды
      const fwdX = Math.sin(player.yaw);
      const fwdZ = Math.cos(player.yaw);
      if (Math.sin(yaw) * fwdX + Math.cos(yaw) * fwdZ < 0) yaw += Math.PI;
      pos.set(nearRoad.point.x, nearRoad.point.y, nearRoad.point.z);
      player.yaw = yaw;
    } else {
      const spawn = britainSpawnPoint();
      pos.copy(spawn.pos);
      player.yaw = spawn.yaw;
    }
    player.vel.set(0, 0, 0);
    player.yawRate = 0;
    player.steerAngle = 0;
    player.throttle = 0;
    player.brakePedal = 0;
    resetPlayerPowertrain();
    player.longAccel = 0;
    player.latAccel = 0;
    player.surfaceMuSmooth = 1;
    resetSteering();
    showCenterMsg('На дорогу!', 900, '#fff', 'rotate-ccw');
    return;
  }
  const near = pointAtS(player.s);
  player.mesh.group.position.copy(near.pos);
  player.yaw = near.yaw;
  player.vel.set(0, 0, 0);
  player.yawRate = 0;
  player.steerAngle = 0;
  player.throttle = 0;
  player.brakePedal = 0;
  resetPlayerPowertrain();
  player.longAccel = 0;
  player.latAccel = 0;
  player.surfaceMuSmooth = 1;
  resetSteering();
  player.prevSampleIdx = nearestSampleIdx(near.pos).idx;
  showCenterMsg('На трассу!', 900, '#fff', 'rotate-ccw');
}

/* ============================ Физика игрока ============================ */
const _fwd = new THREE.Vector3();
const _right = new THREE.Vector3();

function tireLateralForce(alpha, load, mu) {
  const peak = Math.max(mu * load, 0);
  // Pacejka-подобная кривая: alpha в радианах, B — жёсткость на радиан увода.
  // Пик широкий (~10–17°), при глубоком скольжении остаётся ~85% пика.
  const B = 10.5;
  const C = 1.35;
  const E = 0.85;
  const Bx = B * alpha;
  const shape = Math.sin(C * Math.atan(Bx - E * (Bx - Math.atan(Bx))));
  return -peak * shape;
}

function surfaceInfoAt(x, z, groundH) {
  if (isBritainWorld()) {
    const s = worldFoundation.surfaceAt(x, z, { heightM: groundH });
    const hard = s.id === 'asphalt' || s.id === 'concrete' || s.id === 'cobble';
    const offroadSkill = hard ? 1 : 0.8 + selectedCar.offroad * 0.3;
    return {
      name: s.id,
      label: s.label,
      mu: s.mu * offroadSkill,
      rolling: s.rollingResistance,
      roadInfo: null,
    };
  }
  const roadInfo = nearestRoadInfoApprox(x, z);
  const radial = Math.hypot(x, z);
  if (roadInfo.edge <= 0) {
    return { name: 'asphalt', label: 'АСФАЛЬТ', mu: 1.0, rolling: 0.012, roadInfo };
  }
  if (roadInfo.edge <= 1.6) {
    return { name: 'gravel', label: 'ОБОЧИНА', mu: 0.68, rolling: 0.036, roadInfo };
  }
  if (radial > 258 && groundH < 0.55) {
    return { name: 'sand', label: 'ПЕСОК', mu: 0.5, rolling: 0.085, roadInfo };
  }
  if (groundH > 7.0) {
    return { name: 'rock', label: 'СКАЛА', mu: 0.6, rolling: 0.052, roadInfo };
  }
  const offroadSkill = 0.78 + selectedCar.offroad * 0.34;
  return {
    name: 'grass', label: 'ТРАВА',
    mu: 0.66 * offroadSkill,
    rolling: lerp(0.052, 0.034, selectedCar.offroad),
    roadInfo,
  };
}

function simulateVehicleStep(h, car, profile, surface, slopeLong, slopeLat, canDrive, inWater) {
  const pos = player.mesh.group.position;
  const mass = car.mass;
  const gravity = 9.81;
  const a = car.cgToFront;
  const b = car.wheelbase - a;
  const wheelbase = car.wheelbase;
  const yawInertia = mass * (0.9 + (wheelbase * wheelbase) / 12);

  let fx = Math.sin(player.yaw);
  let fz = Math.cos(player.yaw);
  let rx = fz;
  let rz = -fx;
  let u = player.vel.x * fx + player.vel.z * fz;   // вперёд
  let v = player.vel.x * rx + player.vel.z * rz;   // вправо
  let yawRate = player.yawRate;
  const speed = Math.hypot(u, v);

  // Рулевая рейка: нелинейное уменьшение угла + быстрее отклик
  const absU = Math.abs(u);
  const speedSensitiveSteer = car.maxSteer / (1 + Math.pow(absU / 15.5, 1.35));
  const steerTarget = canDrive ? steering.value * speedSensitiveSteer * profile.steering : 0;
  const rackRate = Math.abs(steerTarget) > Math.abs(player.steerAngle) ? 4.2 : 5.6;
  player.steerAngle = approachValue(player.steerAngle, steerTarget, rackRate * h);
  player.steerVis = player.steerAngle;
  const delta = player.steerAngle;
  const cosD = Math.cos(delta);
  const sinD = Math.sin(delta);

  // Нагрузки на оси: продольный + поперечный перенос веса
  const staticFront = mass * gravity * b / wheelbase;
  const staticRear = mass * gravity * a / wheelbase;
  const transfer = mass * player.longAccel * car.cgHeight / wheelbase;
  const loadFront = clamp(staticFront - transfer, staticFront * 0.08, mass * gravity * 0.92);
  const loadRear = clamp(staticRear + transfer, staticRear * 0.08, mass * gravity * 0.92);
  // Поперечный перенос не меняет суммарную нагрузку оси в bicycle-модели:
  // внешнее колесо перегружается, внутреннее разгружается, а суммарный запас
  // оси слегка падает из-за чувствительности шины к нагрузке (load sensitivity).
  const trackWidth = 1.56;
  const latTransferTotal = Math.abs(mass * player.latAccel * car.cgHeight / trackWidth);
  const frontLatTransfer = latTransferTotal * (staticFront / (staticFront + staticRear));
  const rearLatTransfer = latTransferTotal - frontLatTransfer;
  const loadSensitivity = (axleTransfer, axleLoad) => {
    const r = clamp((2 * axleTransfer) / Math.max(axleLoad, 1), 0, 0.95);
    return clamp(0.5 * (Math.pow(1 + r, 0.85) + Math.pow(1 - r, 0.85)), 0.86, 1);
  };
  const frontLoadSensitivity = loadSensitivity(frontLatTransfer, loadFront);
  const rearLoadSensitivity = loadSensitivity(rearLatTransfer, loadRear);

  // Углы увода шин (меньший порог на малых скоростях)
  const frontAxleLat = v + a * yawRate;
  const rearAxleLat = v - b * yawRate;
  const frontWheelLong = u * cosD + frontAxleLat * sinD;
  const frontWheelLat = -u * sinD + frontAxleLat * cosD;
  const longFloor = lerp(1.05, 2.0, smoothstep(1.0, 8.0, Math.abs(u)));
  const alphaFront = Math.atan2(frontWheelLat, Math.max(Math.abs(frontWheelLong), longFloor));
  const alphaRear = Math.atan2(rearAxleLat, Math.max(Math.abs(u), longFloor));

  // Плавный переход сцепления при смене покрытия
  player.surfaceMuSmooth = lerp(player.surfaceMuSmooth ?? surface.mu, surface.mu, clamp(h * 6, 0, 1));
  let muFront = car.tireMu * player.surfaceMuSmooth * profile.grip * frontLoadSensitivity;
  let muRear = car.tireMu * player.surfaceMuSmooth * profile.grip * rearLoadSensitivity;
  if (canDrive && input.handbrake) muRear *= profile.handbrakeRearGrip;
  if (inWater) { muFront *= 0.28; muRear *= 0.28; }
  const tireSpeedFactor = smoothstep(0.35, 3.2, speed);
  let frontLatWheel = tireLateralForce(alphaFront, loadFront, muFront) * tireSpeedFactor;
  let rearLat = tireLateralForce(alphaRear, loadRear, muRear) * tireSpeedFactor;

  // Physics v2.1: настоящий момент двигателя, передачи, сцепление и D/N/R.
  // Коробка видит скорость ведущих колёс, поэтому пробуксовка даёт flare RPM.
  const powertrainSpec = getPowertrainSpec(car);
  if (!player.powertrain || !player.wheelAxles) resetPlayerPowertrain(car);
  const drivenWheelSpeedMps = player.wheelAxles.front.surfaceSpeedMps * car.driveFrontBias
    + player.wheelAxles.rear.surfaceSpeedMps * (1 - car.driveFrontBias);
  const surfaceTopFactor = surface.name === 'asphalt' ? 1 : lerp(0.7, 0.98, car.offroad);
  const effectiveTop = car.topSpeed * surfaceTopFactor * (player.boosting ? 1.16 : 1) * (inWater ? 0.3 : 1);
  const powertrain = updatePowertrain(player.powertrain, powertrainSpec, {
    dt: h,
    longitudinalSpeedMps: u,
    drivenWheelSpeedMps,
    throttlePedal: player.throttle,
    brakePedal: player.brakePedal,
    canDrive,
    speedLimiterMps: effectiveTop,
    boostForceN: canDrive && player.boosting && player.throttle > 0.01 && u < effectiveTop * 1.08
      ? mass * 3.7
      : 0,
  });
  syncPowertrainTelemetry();

  // Physics v2.1: продольная сила рождается из угловой скорости оси и
  // slip ratio, а не из мгновенной обрезки force demand по кругу сцепления.
  const wheelRadiusM = powertrainSpec.wheelRadiusM;
  let driveTorqueFront = powertrain.driveForceN * wheelRadiusM * car.driveFrontBias;
  let driveTorqueRear = powertrain.driveForceN * wheelRadiusM * (1 - car.driveFrontBias);

  // TCS профиля помощи смотрит на фактическую пробуксовку прошлого шага.
  // Arcade сильно душит момент, Sport оставляет заметный slip, Drift почти
  // не вмешивается. Engine braking при отпущенном газе TCS не ослабляет.
  if (powertrain.drivePedal > 0.03) {
    const tractionScale = (wheelState, torqueNm) => {
      if (Math.abs(torqueNm) < 1) return 1;
      const drivingSlip = torqueNm >= 0 ? wheelState.slipRatio : -wheelState.slipRatio;
      // Target-slip TCS: Arcade stays near the tire peak, Sport permits a
      // visible but controlled launch slip, Drift mostly lets it spin.
      const targetSlip = lerp(0.30, 0.13, profile.traction);
      const excessSlip = Math.max(0, drivingSlip - targetSlip);
      const gain = lerp(1.1, 5.2, profile.traction);
      const floorScale = lerp(0.72, 0.14, profile.traction);
      return clamp(1 - excessSlip * gain, floorScale, 1);
    };
    driveTorqueFront *= tractionScale(player.wheelAxles.front, driveTorqueFront);
    driveTorqueRear *= tractionScale(player.wheelAxles.rear, driveTorqueRear);
  }

  const serviceBrakeTorqueNm = Math.abs(powertrain.serviceBrakeForceN) * wheelRadiusM;
  const brakeTorqueFront = serviceBrakeTorqueNm * powertrainSpec.brakeFrontBias;
  let brakeTorqueRear = serviceBrakeTorqueNm * (1 - powertrainSpec.brakeFrontBias);
  if (canDrive && input.handbrake && Math.abs(u) > 0.2) {
    brakeTorqueRear += mass * 4.3 * wheelRadiusM;
  }

  // Effective axle inertia is gear-dependent: in first gear the engine and
  // shafts reflected through a ~19:1 total ratio resist instant wheel
  // runaway, while a free-rolling axle only has wheels/brakes to spin.
  const activeGearForInertia = Math.max(1, Math.abs(powertrain.gear) || 1);
  const activeTotalRatio = (powertrainSpec.gearRatios[activeGearForInertia - 1] || powertrainSpec.gearRatios[0])
    * powertrainSpec.finalDrive;
  const reflectedInertia = Math.min(
    15,
    0.035 * activeTotalRatio * activeTotalRatio * (0.25 + 0.75 * powertrain.clutch),
  );
  const frontInertiaKgM2 = 2.1 + reflectedInertia * car.driveFrontBias;
  const rearInertiaKgM2 = 2.3 + reflectedInertia * (1 - car.driveFrontBias);

  const frontAxle = updateAxleWheel(player.wheelAxles.front, {
    dt: h,
    groundSpeedMps: frontWheelLong,
    driveTorqueNm: driveTorqueFront,
    brakeTorqueNm: brakeTorqueFront,
    loadN: loadFront,
    mu: muFront,
    lateralForceN: frontLatWheel,
    wheelRadiusM,
    inertiaKgM2: frontInertiaKgM2,
    absStrength: profile.traction,
  });
  const rearAxle = updateAxleWheel(player.wheelAxles.rear, {
    dt: h,
    groundSpeedMps: u,
    driveTorqueNm: driveTorqueRear,
    brakeTorqueNm: brakeTorqueRear,
    loadN: loadRear,
    mu: muRear,
    lateralForceN: rearLat,
    wheelRadiusM,
    inertiaKgM2: rearInertiaKgM2,
    absStrength: profile.traction,
  });

  let frontLongWheel = frontAxle.tireForceN;
  let rearLong = rearAxle.tireForceN;
  const frontSpin = powertrain.drivePedal > 0.2 && Math.abs(frontAxle.slipRatio) > 0.19;
  const rearSpin = powertrain.drivePedal > 0.2 && Math.abs(rearAxle.slipRatio) > 0.19;
  player.wheelspin = frontSpin || rearSpin;
  player.frontWheelOmega = frontAxle.omegaRadPerS;
  player.rearWheelOmega = rearAxle.omegaRadPerS;
  player.frontLongSlip = frontAxle.slipRatio;
  player.rearLongSlip = rearAxle.slipRatio;
  player.longitudinalSlip = Math.max(Math.abs(frontAxle.slipRatio), Math.abs(rearAxle.slipRatio));
  if (frontSpin) frontLatWheel *= lerp(0.48, 0.9, profile.traction);
  if (rearSpin) rearLat *= lerp(0.4, 0.9, profile.traction);
  if (powertrain.serviceBrakePedal > 0.82 && Math.abs(frontAxle.slipRatio) > 0.2) frontLatWheel *= lerp(0.72, 0.94, profile.traction);
  if (powertrain.serviceBrakePedal > 0.82 && Math.abs(rearAxle.slipRatio) > 0.2) rearLat *= lerp(0.62, 0.9, profile.traction);

  // Передняя ось: из координат повернутого колеса в координаты кузова
  const frontLongBody = frontLongWheel * cosD - frontLatWheel * sinD;
  const frontLatBody = frontLongWheel * sinD + frontLatWheel * cosD;

  const aeroLong = -0.5 * 1.225 * car.dragArea * u * Math.abs(u);
  const aeroLat = -1.15 * v * Math.abs(v);
  const rollingLong = -mass * gravity * surface.rolling * Math.tanh(u / 0.65);
  const slopeLongForce = -mass * gravity * slopeLong;
  const slopeLatForce = -mass * gravity * slopeLat;
  const totalLong = frontLongBody + rearLong + aeroLong + rollingLong + slopeLongForce;
  const totalLat = frontLatBody + rearLat + aeroLat + slopeLatForce;

  // Момент рыскания + электронная стабилизация профиля помощи
  const kinematicYawRate = (u / wheelbase) * Math.tan(delta);
  let yawAccel = (a * frontLatBody - b * rearLat) / yawInertia;
  yawAccel -= yawRate * profile.yawDamping;
  yawAccel += (kinematicYawRate - yawRate) * profile.stability * 1.45;
  const dynamicBlend = smoothstep(2.0, 7.0, Math.abs(u));
  yawAccel += (kinematicYawRate - yawRate) * (1 - dynamicBlend) * 16;
  if (inWater) yawAccel -= yawRate * 2.2;
  yawRate = clamp(yawRate + yawAccel * h, -profile.maxYawRate, profile.maxYawRate);

  const longAccel = totalLong / mass;
  const latAccel = totalLat / mass;
  u += (longAccel + yawRate * v) * h;
  v += (latAccel - yawRate * u) * h;

  // На парковочных скоростях плавно переходим к кинематике Аккермана
  const kinematicV = u * (b / wheelbase) * Math.tan(delta);
  v = lerp(v, kinematicV, (1 - dynamicBlend) * clamp(h * 16, 0, 1));

  const reverseRequested = powertrain.selector === 'R';
  const holdingAtStop = reverseRequested || powertrain.braking || powertrain.drivePedal > 0.03;
  if (Math.abs(u) < 0.13 && !holdingAtStop && Math.abs(slopeLong) < 0.035) u = 0;
  if (Math.hypot(u, v) < 0.06 && !holdingAtStop) {
    v = 0;
    yawRate = 0;
  }
  if (inWater) {
    const waterDamp = Math.exp(-1.9 * h);
    u *= waterDamp;
    v *= waterDamp;
  }
  const hardForward = Math.max(effectiveTop * 1.16 + 4, 9);
  if (u > hardForward) u = lerp(u, hardForward, clamp(h * 3, 0, 1));
  const hardReverse = -powertrainSpec.maxReverseSpeedMps * 1.12;
  if (u < hardReverse) u = lerp(u, hardReverse, clamp(h * 5, 0, 1));

  player.yawRate = yawRate;
  player.yaw += yawRate * h;
  fx = Math.sin(player.yaw);
  fz = Math.cos(player.yaw);
  rx = fz;
  rz = -fx;
  player.vel.set(fx * u + rx * v, 0, fz * u + rz * v);
  pos.addScaledVector(player.vel, h);
  player.travelDistance += Math.hypot(u, v) * h;

  const accelBlend = clamp(h * 18, 0, 1);
  player.longAccel = lerp(player.longAccel, longAccel, accelBlend);
  player.latAccel = lerp(player.latAccel, latAccel, accelBlend);
  player.frontSlip = alphaFront;
  player.rearSlip = alphaRear;
  player.slipAngle = Math.atan2(v, Math.max(Math.abs(u), 0.1));
}

/** Collisions on the Britain map: SDF push-out via the foundation index. */
function resolveBritainCollisions(pos, preSpeed) {
  const hits = worldFoundation.colliderIndex.queryOverlaps(pos.x, pos.z, 1.25);
  for (const hit of hits) {
    if (hit.penetrationM <= 0) continue;
    const c = hit.collider;
    const e = 0.35;
    const gx = distanceToCollider(c, pos.x + e, pos.z) - distanceToCollider(c, pos.x - e, pos.z);
    const gz = distanceToCollider(c, pos.x, pos.z + e) - distanceToCollider(c, pos.x, pos.z - e);
    const gl = Math.hypot(gx, gz);
    if (gl < 1e-6) continue;
    const nx = gx / gl;
    const nz = gz / gl;
    pos.x += nx * hit.penetrationM;
    pos.z += nz * hit.penetrationM;
    const vn = player.vel.x * nx + player.vel.z * nz;
    if (vn < 0) {
      const restitution = preSpeed > 14 ? 0.12 : 0.04;
      player.vel.x -= vn * (1 + restitution) * nx;
      player.vel.z -= vn * (1 + restitution) * nz;
      player.yawRate *= 0.88;
    }
    player.yawRate *= 0.68;
    if (preSpeed > 6 && crashCooldown <= 0) {
      showCenterMsg('СТОЛКНОВЕНИЕ!', 800, '#ff8a6a', 'alert-triangle');
      player.driftChain = 0;
      vibrate(70);
      engine.beep(110, 0.2, 0.3);
      crashCooldown = 0.7;
    }
  }
}

function updatePlayer(dt) {
  const car = selectedCar;
  const profile = ASSIST_PROFILES[assistMode] || ASSIST_PROFILES.sport;
  const pos = player.mesh.group.position;
  const canDrive = gameState === 'racing';

  updateSteeringInput(dt);
  if (!player.powertrain) resetPlayerPowertrain(car);
  const throttleTarget = canDrive ? pedalTargetValue('gas') : 0;
  const brakeTarget = canDrive ? pedalTargetValue('brake') : 0;
  player.throttle = approachValue(player.throttle, throttleTarget, (throttleTarget > player.throttle ? 5.2 : 7.2) * dt);
  player.brakePedal = approachValue(player.brakePedal, brakeTarget, (brakeTarget > player.brakePedal ? 8.2 : 10.5) * dt);

  _fwd.set(Math.sin(player.yaw), 0, Math.cos(player.yaw));
  _right.set(_fwd.z, 0, -_fwd.x);
  let fwdSpeed = player.vel.dot(_fwd);

  const britain = isBritainWorld();
  const near = britain ? null : nearestSampleIdx(pos);
  const roadInfoForGround = britain ? null : nearestRoadInfoApprox(pos.x, pos.z);
  const groundH = terrainHeight(pos.x, pos.z, roadInfoForGround ? roadInfoForGround.dist : null);
  player.groundH = groundH;
  const surface = surfaceInfoAt(pos.x, pos.z, groundH);
  player.surface = surface.label;
  player.surfaceMu = car.tireMu * surface.mu;
  player.offroad = surface.name !== 'asphalt';
  const inWater = britain ? groundH < -0.3 : (Math.hypot(pos.x, pos.z) > 289 || groundH < -0.85);

  if (britain) {
    player.s = player.travelDistance;
  } else {
    // Прогресс вдоль трассы (без скачков через петлю)
    let dIdx = near.idx - player.prevSampleIdx;
    if (dIdx > 400) dIdx -= 800;
    if (dIdx < -400) dIdx += 800;
    if (Math.abs(dIdx) < 60) player.sampleAccum += dIdx;
    player.prevSampleIdx = near.idx;
    player.s = (player.sampleAccum / 800) * TRACK_LENGTH - 6;
  }

  // Уклон рельефа в осях машины
  const hF = terrainHeight(pos.x + _fwd.x * 2.2, pos.z + _fwd.z * 2.2);
  const hB = terrainHeight(pos.x - _fwd.x * 2.2, pos.z - _fwd.z * 2.2);
  const hR = terrainHeight(pos.x + _right.x * 1.5, pos.z + _right.z * 1.5);
  const hL = terrainHeight(pos.x - _right.x * 1.5, pos.z - _right.z * 1.5);
  const slopeLong = clamp((hF - hB) / 4.4, -0.75, 0.75);
  const slopeLat = clamp((hR - hL) / 3.0, -0.75, 0.75);
  player.groundPitch = clamp(-Math.atan2(hF - hB, 4.4), -0.55, 0.55);
  player.groundRoll = clamp(Math.atan2(hR - hL, 3.0), -0.55, 0.55);

  // Нитро
  player.boosting = canDrive && input.nitro && player.nitro > 0.02 && fwdSpeed > 2;
  if (player.boosting) {
    player.nitro = Math.max(0, player.nitro - dt * 0.32);
  } else {
    player.nitro = Math.min(1, player.nitro + dt * 0.022);
  }

  const preCollisionSpeed = player.vel.length();
  const steps = clamp(Math.ceil(dt / (1 / 240)), 1, 12);
  const stepDt = dt / steps;
  for (let i = 0; i < steps; i++) {
    simulateVehicleStep(stepDt, car, profile, surface, slopeLong, slopeLat, canDrive, inWater);
  }

  _fwd.set(Math.sin(player.yaw), 0, Math.cos(player.yaw));
  _right.set(_fwd.z, 0, -_fwd.x);
  fwdSpeed = player.vel.dot(_fwd);
  const latSpeed = player.vel.dot(_right);
  const speedAbs = Math.abs(fwdSpeed);
  const velLen = player.vel.length();
  syncPowertrainTelemetry();

  const newGroundH = terrainHeight(pos.x, pos.z, britain ? 0 : nearestRoadInfoApprox(pos.x, pos.z).dist);
  player.groundH = newGroundH;
  pos.y = inWater ? Math.max(newGroundH, britain ? -0.35 : -0.58) : newGroundH;

  // Граница мира
  if (britain) {
    const halfW = (worldFoundation.worldSizeM || 1000) / 2;
    const wb = worldFoundation.bounds || { minX: -halfW, maxX: halfW, minZ: -halfW, maxZ: halfW };
    let hitBound = false;
    if (pos.x > wb.maxX - 6) { pos.x = wb.maxX - 6; hitBound = true; }
    if (pos.x < wb.minX + 6) { pos.x = wb.minX + 6; hitBound = true; }
    if (pos.z > wb.maxZ - 6) { pos.z = wb.maxZ - 6; hitBound = true; }
    if (pos.z < wb.minZ + 6) { pos.z = wb.minZ + 6; hitBound = true; }
    if (hitBound) {
      player.vel.multiplyScalar(0.4);
      player.yawRate *= 0.5;
    }
  } else {
    const distC = Math.hypot(pos.x, pos.z);
    if (distC > 322) {
      pos.x *= 322 / distC;
      pos.z *= 322 / distC;
      player.vel.multiplyScalar(0.4);
      player.yawRate *= 0.5;
    }
  }

  // Столкновения с объектами: убираем скорость в препятствие, касательную частично сохраняем
  crashCooldown -= dt;
  if (britain) resolveBritainCollisions(pos, preCollisionSpeed);
  for (const col of colliders) {
    const dx = pos.x - col.x;
    const dz = pos.z - col.z;
    const rr = col.r + 1.25;
    const d2 = dx * dx + dz * dz;
    if (d2 < rr * rr && d2 > 0.0001) {
      const d = Math.sqrt(d2);
      const nx = dx / d;
      const nz = dz / d;
      pos.x = col.x + nx * rr;
      pos.z = col.z + nz * rr;
      const vn = player.vel.x * nx + player.vel.z * nz;
      if (vn < 0) {
        // Убираем только скорость, направленную внутрь препятствия:
        // касательная скорость сохраняется, поэтому машина не «прилипает» к стене.
        const restitution = preCollisionSpeed > 14 ? 0.12 : 0.04;
        player.vel.x -= vn * (1 + restitution) * nx;
        player.vel.z -= vn * (1 + restitution) * nz;
        player.yawRate *= 0.88;
      }
      player.yawRate *= 0.68;
      if (preCollisionSpeed > 6 && crashCooldown <= 0) {
        showCenterMsg('СТОЛКНОВЕНИЕ!', 800, '#ff8a6a', 'alert-triangle');
        player.driftChain = 0;
        vibrate(70);
        engine.beep(110, 0.2, 0.3);
        crashCooldown = 0.7;
      }
    }
  }

  // Столкновения с соперниками и обычным трафиком
  for (const r of rivals) {
    const rp = r.mesh.group.position;
    const dx = pos.x - rp.x;
    const dz = pos.z - rp.z;
    const d2 = dx * dx + dz * dz;
    if (d2 < 9.5 && d2 > 0.0001) {
      const d = Math.sqrt(d2);
      const nx = dx / d;
      const nz = dz / d;
      pos.x = rp.x + nx * 3.1;
      pos.z = rp.z + nz * 3.1;
      const vn = player.vel.x * nx + player.vel.z * nz;
      if (vn < 0) {
        player.vel.x -= vn * nx * 1.15;
        player.vel.z -= vn * nz * 1.15;
      }
      player.vel.multiplyScalar(0.9);
      player.yawRate *= 0.78;
      if (crashCooldown <= 0) {
        vibrate(40);
        engine.beep(140, 0.12, 0.2);
        crashCooldown = 0.5;
      }
    }
  }
  for (const traffic of ambientCars) {
    const rp = traffic.mesh.group.position;
    const dx = pos.x - rp.x;
    const dz = pos.z - rp.z;
    const d2 = dx * dx + dz * dz;
    if (d2 < 8.4 && d2 > 0.0001) {
      const d = Math.sqrt(d2);
      const nx = dx / d;
      const nz = dz / d;
      pos.x = rp.x + nx * 2.9;
      pos.z = rp.z + nz * 2.9;
      const vn = player.vel.x * nx + player.vel.z * nz;
      if (vn < 0) {
        player.vel.x -= vn * nx * 1.1;
        player.vel.z -= vn * nz * 1.1;
      }
      player.vel.multiplyScalar(0.88);
      player.yawRate *= 0.75;
      traffic.hitTimer = 1.4;
      if (crashCooldown <= 0) {
        showCenterMsg('Авария с трафиком!', 850, '#ff8a6a', 'alert-triangle');
        vibrate(55);
        engine.beep(125, 0.16, 0.24);
        crashCooldown = 0.6;
      }
    }
  }

  // Дрифт определяется настоящим углом скольжения кузова и задней оси
  const absSlip = Math.abs(player.slipAngle);
  player.drifting = velLen > 9 && absSlip > 0.16 && (input.handbrake || Math.abs(player.rearSlip) > 0.17 || player.throttle > 0.35);
  player.driftChainTimer -= dt;
  if (player.drifting && velLen > 10) {
    if (player.driftChainTimer <= 0) player.driftChain = Math.min(player.driftChain + 1, 8);
    player.driftChainTimer = 1.4;
    const pts = Math.round(absSlip * velLen * dt * 46) * Math.max(player.driftChain, 1);
    if (pts > 0) {
      player.score += pts;
      player.nitro = Math.min(1, player.nitro + dt * 0.1);
      showДрифтPopup(pts, player.driftChain);
    }
  } else if (player.driftChainTimer <= 0) {
    player.driftChain = 0;
  }

  const maxTireSlip = Math.max(Math.abs(player.frontSlip), Math.abs(player.rearSlip));
  const burningOut = player.longitudinalSlip > 0.2 && (player.wheelspin || velLen > 3);
  if ((velLen > 5 && maxTireSlip > 0.18) || (velLen > 0.8 && burningOut)) {
    player.smokeAccumulator = Math.min(1, player.smokeAccumulator + dt * (2 + maxTireSlip * 8 + player.longitudinalSlip * 7));
    player.skidAccumulator = Math.min(1, player.skidAccumulator + dt * (2.4 + player.longitudinalSlip * 3));
  }

  // Кузов: рельеф + крен/тангаж от измеренных ускорений
  const g = player.mesh.group;
  g.rotation.y = player.yaw;
  const rollTarget = player.groundRoll - clamp(player.latAccel * 0.015, -0.16, 0.16) * (car.cgHeight / 0.52);
  const pitchTarget = player.groundPitch - clamp(player.longAccel * 0.010, -0.105, 0.125);
  g.rotation.z = lerp(g.rotation.z, rollTarget, clamp(dt * 6.2, 0, 1));
  g.rotation.x = lerp(g.rotation.x, pitchTarget, clamp(dt * 5.4, 0, 1));
  const wheelR = player.mesh.wheelRadius || 0.4;
  player.wheels.forEach((w) => {
    if (w.front) w.pivot.rotation.y = player.steerAngle;
    // Visual wheel speed is the physical axle speed, so wheelspin/lock-up
    // is visible instead of every wheel simply following body speed.
    const omega = w.front ? player.frontWheelOmega : player.rearWheelOmega;
    w.spin.rotation.x += (Number.isFinite(omega) ? omega : fwdSpeed / wheelR) * dt;
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
            showCenterMsg(`РЕКОРД КРУГА: ${fmtTime(lapTime)}!`, 2200, '#ffb03a', 'trophy');
          }
        }
        player.lapStart = raceTime;
        player.lap++;
        if (player.lap > TOTAL_LAPS) {
          updateCPVisibility();
          finishRace();
          return;
        }
        if (player.lap === TOTAL_LAPS) showCenterMsg('ФИНАЛЬНЫЙ КРУГ!', 2200, '#ffb03a', 'flag');
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


  engine.update(player.rpmRatio, player.boosting, player.engineLoad, player.shifting);
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


/* ============================ Живой трафик, пешеходы и птицы ============================ */
function animatePedestrianLimbs(ped, moving, dt, t) {
  if (moving) ped.phase += dt * (4.2 + ped.speed * 2.4);
  const swing = moving ? Math.sin(ped.phase) * 0.55 : 0;
  ped.leftLeg.rotation.x = swing;
  ped.rightLeg.rotation.x = -swing;
  ped.leftArm.rotation.x = -swing * 0.72;
  ped.rightArm.rotation.x = swing * 0.72;
  if (!moving) {
    ped.leftArm.rotation.x = Math.sin(t * 1.3 + ped.phase) * 0.06;
    ped.rightArm.rotation.x = Math.cos(t * 1.1 + ped.phase) * 0.06;
  }
}
function updateAmbientCars(dt) {
  for (const car of ambientCars) {
    if (car.hitTimer > 0) car.hitTimer = Math.max(0, car.hitTimer - dt);
    let speedNow = car.hitTimer > 0 ? 0 : car.speed;
    const group = car.mesh.group;
    if (player.mesh) {
      const pp = player.mesh.group.position;
      const dx = pp.x - group.position.x;
      const dz = pp.z - group.position.z;
      const dist = Math.hypot(dx, dz);
      const forwardX = Math.sin(group.rotation.y);
      const forwardZ = Math.cos(group.rotation.y);
      const ahead = dist > 0.01 ? (dx * forwardX + dz * forwardZ) / dist : 0;
      if (dist < 15 && ahead > 0.35) speedNow *= clamp((dist - 5) / 10, 0.08, 1);
    }
    car.s += car.direction * speedNow * dt;
    let roadPoint;
    if (car.road) {
      if (!car.road.closed) {
        if (car.s > car.road.length - 4) { car.s = car.road.length - 4; car.direction = -1; car.lane = -Math.abs(car.lane); }
        if (car.s < 4) { car.s = 4; car.direction = 1; car.lane = Math.abs(car.lane); }
      }
      roadPoint = pointOnRoad(car.road, car.s, car.lane);
    } else {
      roadPoint = pointAtS(car.s, car.lane);
    }
    const targetYaw = roadPoint.yaw + (car.direction < 0 ? Math.PI : 0);
    const yawDelta = wrapAnglePi(targetYaw - group.rotation.y);
    group.position.set(roadPoint.pos.x, terrainHeight(roadPoint.pos.x, roadPoint.pos.z, 0) + 0.04, roadPoint.pos.z);
    group.rotation.y = dt === 0 ? targetYaw : angleLerp(group.rotation.y, targetYaw, Math.min(dt * 5, 1));
    car.mesh.wheels.forEach((w) => {
      if (w.front) w.pivot.rotation.y = clamp(yawDelta * 1.4, -0.42, 0.42);
      w.spin.rotation.x += (speedNow / (car.mesh.wheelRadius || 0.34)) * dt;
    });
  }
}
function updatePedestrians(dt, t) {
  const playerPos = player.mesh ? player.mesh.group.position : null;
  for (const ped of pedestrians) {
    let moving = false;
    if (ped.mode === 'loop') {
      ped.s += ped.direction * ped.speed * dt;
      const p = pointOnRoad(villageLoopRoad, ped.s, ped.lane);
      ped.group.position.set(p.pos.x, infraGroundY(p.pos.x, p.pos.z), p.pos.z);
      ped.group.rotation.y = p.yaw + (ped.direction < 0 ? Math.PI : 0);
      moving = dt > 0;
    } else if (ped.mode === 'wander') {
      if (ped.wait > 0) {
        ped.wait -= dt;
      } else {
        const dx = ped.targetX - ped.x;
        const dz = ped.targetZ - ped.z;
        const dist = Math.hypot(dx, dz);
        if (dist < 0.35) {
          const a = rnd() * TAU;
          const r = 3 + rnd() * ped.radius;
          ped.targetX = ped.homeX + Math.cos(a) * r;
          ped.targetZ = ped.homeZ + Math.sin(a) * r;
          ped.wait = 0.6 + rnd() * 2.6;
        } else {
          const targetYaw = Math.atan2(dx, dz);
          ped.yaw = angleLerp(ped.yaw, targetYaw, Math.min(dt * 6, 1));
          ped.x += Math.sin(ped.yaw) * ped.speed * dt;
          ped.z += Math.cos(ped.yaw) * ped.speed * dt;
          moving = dt > 0;
        }
      }
      ped.group.position.set(ped.x, infraGroundY(ped.x, ped.z), ped.z);
      ped.group.rotation.y = ped.yaw;
    } else {
      ped.group.rotation.y = ped.yaw + Math.sin(t * 0.45 + ped.phase) * 0.1;
      if (Math.sin(t * 0.35 + ped.phase) > 0.72) {
        ped.rightArm.rotation.z = -2.45 + Math.sin(t * 7 + ped.phase) * 0.28;
      } else {
        ped.rightArm.rotation.z = 0;
      }
    }
    if (playerPos && ped.mode !== 'stand') {
      const dx = ped.group.position.x - playerPos.x;
      const dz = ped.group.position.z - playerPos.z;
      const dist = Math.hypot(dx, dz);
      if (dist > 0.01 && dist < 5.5) {
        const push = (5.5 - dist) * 0.28;
        ped.group.position.x += (dx / dist) * push;
        ped.group.position.z += (dz / dist) * push;
        ped.group.position.y = infraGroundY(ped.group.position.x, ped.group.position.z);
      }
    }
    animatePedestrianLimbs(ped, moving, dt, t);
    if (moving) ped.group.position.y += Math.abs(Math.sin(ped.phase)) * 0.035;
  }
}
function updateBirds(t) {
  for (const bird of birds) {
    const angle = bird.phase + t * bird.speed;
    const x = bird.centerX + Math.cos(angle) * bird.radius;
    const z = bird.centerZ + Math.sin(angle) * bird.radius;
    const y = bird.height + Math.sin(t * 0.65 + bird.phase) * 2.2;
    bird.group.position.set(x, y, z);
    const vx = -Math.sin(angle) * Math.sign(bird.speed || 1);
    const vz = Math.cos(angle) * Math.sign(bird.speed || 1);
    bird.group.rotation.y = Math.atan2(vx, vz);
    const flap = Math.sin(t * 8 + bird.phase) * 0.62;
    bird.leftWing.rotation.z = flap;
    bird.rightWing.rotation.z = -flap;
  }
}
function updateLivingWorld(dt, t) {
  updateAmbientCars(dt);
  updatePedestrians(dt, t);
  updateBirds(t);
}

/* Дым шин и следы резины */
const tireSmokePool = [];
let tireSmokeCursor = 0;
let tireSmokeReady = false;
const _wheelWorld = new THREE.Vector3();
let skidMesh = null;
let skidCursor = 0;
const skidDummy = new THREE.Object3D();
const lastSkidPoints = [null, null];
function ensureTireEffects() {
  if (tireSmokeReady) return;
  tireSmokeReady = true;
  const tex = makeCloudSpriteTexture();
  for (let i = 0; i < 78; i++) {
    const sprite = new THREE.Sprite(new THREE.SpriteMaterial({
      map: tex, color: 0xd8d8d8, transparent: true, opacity: 0, depthWrite: false,
    }));
    sprite.scale.setScalar(0.5);
    sprite.visible = false;
    scene.add(sprite);
    tireSmokePool.push({ sprite, life: 0, maxLife: 1, vel: new THREE.Vector3() });
  }
  const skidGeo = new THREE.PlaneGeometry(0.27, 1);
  skidGeo.rotateX(-Math.PI / 2);
  skidMesh = new THREE.InstancedMesh(skidGeo, new THREE.MeshBasicMaterial({
    color: 0x0b0b0d, transparent: true, opacity: 0.58, depthWrite: false,
    polygonOffset: true, polygonOffsetFactor: -3,
  }), 280);
  skidDummy.position.set(0, -10, 0);
  skidDummy.scale.set(0.001, 0.001, 0.001);
  skidDummy.updateMatrix();
  for (let i = 0; i < 280; i++) skidMesh.setMatrixAt(i, skidDummy.matrix);
  skidMesh.instanceMatrix.needsUpdate = true;
  scene.add(skidMesh);
}
function emitTireSmoke(x, y, z) {
  const p = tireSmokePool[tireSmokeCursor];
  tireSmokeCursor = (tireSmokeCursor + 1) % tireSmokePool.length;
  p.life = p.maxLife = 0.7 + Math.random() * 0.55;
  p.sprite.position.set(x + (Math.random() - 0.5) * 0.3, y + 0.2, z + (Math.random() - 0.5) * 0.3);
  p.sprite.scale.setScalar(0.62 + Math.random() * 0.42);
  p.sprite.material.opacity = 0.34;
  p.sprite.visible = true;
  p.vel.set(player.vel.x * 0.13 + (Math.random() - 0.5) * 0.55, 0.7 + Math.random() * 0.55, player.vel.z * 0.13 + (Math.random() - 0.5) * 0.55);
}
function addSkidSegment(a, b) {
  const dx = b.x - a.x;
  const dz = b.z - a.z;
  const len = Math.hypot(dx, dz);
  if (len < 0.25) return;
  const mx = (a.x + b.x) / 2;
  const mz = (a.z + b.z) / 2;
  skidDummy.position.set(mx, terrainHeight(mx, mz, 0) + 0.095, mz);
  skidDummy.rotation.set(0, Math.atan2(dx, dz), 0);
  skidDummy.scale.set(1, 1, len + 0.08);
  skidDummy.updateMatrix();
  skidMesh.setMatrixAt(skidCursor, skidDummy.matrix);
  skidCursor = (skidCursor + 1) % 280;
  skidMesh.instanceMatrix.needsUpdate = true;
}
function updateTireEffects(dt) {
  ensureTireEffects();
  for (const p of tireSmokePool) {
    if (p.life <= 0) continue;
    p.life -= dt;
    if (p.life <= 0) { p.sprite.visible = false; continue; }
    p.sprite.position.addScaledVector(p.vel, dt);
    p.sprite.scale.multiplyScalar(1 + dt * 2.05);
    p.sprite.material.opacity = 0.34 * (p.life / p.maxLife);
  }
  if (!player.mesh || gameState !== 'racing') {
    player.smokeAccumulator = Math.max(0, player.smokeAccumulator - dt * 2);
    lastSkidPoints[0] = lastSkidPoints[1] = null;
    return;
  }
  const maxSlip = Math.max(Math.abs(player.frontSlip), Math.abs(player.rearSlip));
  const sliding = (player.vel.length() > 5 && maxSlip > 0.18)
    || (player.vel.length() > 0.8 && player.longitudinalSlip > 0.2 && player.wheelspin);
  const rearWheels = player.wheels.filter((w) => !w.front);
  if (sliding && player.smokeAccumulator > 0.13) {
    rearWheels.forEach((w) => {
      w.pivot.getWorldPosition(_wheelWorld);
      emitTireSmoke(_wheelWorld.x, _wheelWorld.y, _wheelWorld.z);
    });
    player.smokeAccumulator = Math.max(0, player.smokeAccumulator - 0.14);
  }
  rearWheels.forEach((w, i) => {
    w.pivot.getWorldPosition(_wheelWorld);
    const current = { x: _wheelWorld.x, z: _wheelWorld.z };
    if (sliding && lastSkidPoints[i]) addSkidSegment(lastSkidPoints[i], current);
    lastSkidPoints[i] = sliding ? current : null;
  });
  player.skidAccumulator = Math.max(0, player.skidAccumulator - dt * 2.5);
}

/* ============================ Камера ============================ */
const camTargetPos = new THREE.Vector3();
const _menuLookTarget = new THREE.Vector3();
function wrapAnglePi(angle) {
  let d = angle % TAU;
  if (d > Math.PI) d -= TAU;
  if (d < -Math.PI) d += TAU;
  return d;
}

function updateCamera(dt) {
  if (gameState === 'menu') {
    // Шоурум: автоматический облёт, который можно перехватить перетаскиванием
    cameraOrbit.menuIdle += dt;
    if (cameraOrbit.menuIdle > 2.5) menuOrbit += dt * 0.22;
    const center = player.mesh ? player.mesh.group.position : new THREE.Vector3(0, 0, -170);
    const angle = menuOrbit + cameraOrbit.yaw;
    const pitch = clamp(cameraOrbit.menuPitch, -0.04, 1.05);
    const distance = clamp(cameraOrbit.menuDistance, 4.2, 16);
    const horizontal = distance * Math.cos(pitch);
    camTargetPos.set(
      center.x + Math.sin(angle) * horizontal,
      center.y + 0.78 + distance * Math.sin(pitch),
      center.z + Math.cos(angle) * horizontal
    );
    camTargetPos.y = Math.max(camTargetPos.y, terrainHeight(camTargetPos.x, camTargetPos.z) + 0.5);
    camera.position.lerp(camTargetPos, Math.min(dt * 5, 1));
    // В ландшафте сдвигаем точку взгляда влево от машины: авто оказывается
    // в открытой правой части шоурума, а не за левой панелью гаража.
    const viewX = center.x - camera.position.x;
    const viewZ = center.z - camera.position.z;
    const viewLen = Math.max(0.001, Math.hypot(viewX, viewZ));
    const stageOffset = window.innerWidth > 820 && window.innerWidth > window.innerHeight
      ? clamp(distance * 0.15, 0, 1.35)
      : 0;
    _menuLookTarget.set(
      center.x + (viewZ / viewLen) * stageOffset,
      center.y + 0.78,
      center.z - (viewX / viewLen) * stageOffset
    );
    camera.lookAt(_menuLookTarget);
    camera.fov = lerp(camera.fov, 49, dt * 2);
    camera.updateProjectionMatrix();
    return;
  }
  if (!player.mesh) return;
  const pos = player.mesh.group.position;
  _fwd.set(Math.sin(player.yaw), 0, Math.cos(player.yaw));
  const speedRatio = clamp(player.vel.length() / selectedCar.topSpeed, 0, 1);
  cameraOrbit.idle += dt;

  const shouldRecenter = !inspectMode && gameState !== 'paused' && cameraOrbit.idle > 3.5;
  if (shouldRecenter) {
    cameraOrbit.yaw = angleLerp(cameraOrbit.yaw, 0, clamp(dt * 1.35, 0, 1));
    cameraOrbit.pitch = lerp(cameraOrbit.pitch, 0, clamp(dt * 1.1, 0, 1));
    cameraOrbit.distanceScale = lerp(cameraOrbit.distanceScale, 1, clamp(dt * 0.65, 0, 1));
  }

  if (cameraMode === 2 && !inspectMode) {
    // капот
    camTargetPos.copy(pos).addScaledVector(_fwd, 1.4);
    camTargetPos.y = pos.y + 1.25;
    camera.position.lerp(camTargetPos, Math.min(dt * 22, 1));
    const look = pos.clone().addScaledVector(_fwd, 18);
    look.y = pos.y + 1.0;
    camera.lookAt(look);
  } else {
    const absoluteSpeedRatio = clamp(player.vel.length() / 60, 0, 1);
    const baseDist = cameraMode === 0 ? 7.05 + absoluteSpeedRatio * 1.75 : 12.5;
    const baseHeight = cameraMode === 0 ? 2.38 + absoluteSpeedRatio * 0.28 : 4.6;
    const basePitch = Math.atan2(baseHeight, baseDist);
    const pitch = clamp(basePitch + cameraOrbit.pitch, -0.02, 1.25);
    const distance = clamp(baseDist * cameraOrbit.distanceScale, 3.8, 24);
    const horizontal = distance * Math.cos(pitch);
    const orbitYaw = player.yaw + Math.PI + cameraOrbit.yaw;
    camTargetPos.set(
      pos.x + Math.sin(orbitYaw) * horizontal,
      pos.y + 0.78 + distance * Math.sin(pitch),
      pos.z + Math.cos(orbitYaw) * horizontal
    );
    camTargetPos.y = Math.max(camTargetPos.y, terrainHeight(camTargetPos.x, camTargetPos.z) + 0.55);
    const followRate = inspectMode || gameState === 'paused' ? 11 : (cameraMode === 0 ? 4.6 : 3.2);
    camera.position.lerp(camTargetPos, Math.min(dt * followRate, 1));
    const orbitAmount = clamp(Math.abs(wrapAnglePi(cameraOrbit.yaw)) / 1.15 + Math.abs(cameraOrbit.pitch) * 0.55, 0, 1);
    const look = pos.clone().addScaledVector(_fwd, inspectMode ? 0 : 9 * (1 - orbitAmount));
    look.y = pos.y + lerp(1.4, 0.78, inspectMode ? 1 : orbitAmount);
    camera.lookAt(look);
  }
  const targetFov = inspectMode
    ? 50
    : 62 + clamp(player.vel.length() / 60, 0, 1) * 11 + (player.boosting ? 6 : 0);
  camera.fov = lerp(camera.fov, targetFov, dt * 4);
  camera.updateProjectionMatrix();
}

/* ============================ HUD + миникарта ============================ */
const minimap = $('minimap').getContext('2d');
const speedFxEl = $('speedFx');
let minimapTimer = 0;

let britainMinimapBase = null;

function buildBritainMinimapBase(S) {
  const c = document.createElement('canvas');
  c.width = S;
  c.height = S;
  const g = c.getContext('2d');
  const halfW = (worldFoundation.worldSizeM || 1000) / 2;
  const wb = worldFoundation.bounds || { minX: -halfW, maxX: halfW, minZ: -halfW, maxZ: halfW };
  const scale = S / (Math.max(wb.maxX - wb.minX, wb.maxZ - wb.minZ) * 1.08);
  const mcx = (wb.minX + wb.maxX) / 2;
  const mcz = (wb.minZ + wb.maxZ) / 2;
  const toMap = (x, z) => [S / 2 + (x - mcx) * scale, S / 2 + (z - mcz) * scale];
  g.beginPath();
  g.arc(S / 2, S / 2, S / 2 - 1, 0, TAU);
  g.clip();
  g.fillStyle = '#0a2a3d';
  g.fillRect(0, 0, S, S);
  const [lx, ly] = toMap(wb.minX, wb.minZ);
  const [rx, ry] = toMap(wb.maxX, wb.maxZ);
  g.fillStyle = 'rgba(49, 92, 55, 0.94)';
  g.fillRect(lx, ly, rx - lx, ry - ly);
  g.strokeStyle = 'rgba(236, 211, 156, 0.78)';
  g.lineWidth = 2;
  g.strokeRect(lx, ly, rx - lx, ry - ly);
  if (worldFoundation.zones?.marina) {
    const m = worldFoundation.zones.marina;
    const [mx0, mz0] = toMap(m.minX, m.minZ);
    const [mx1, mz1] = toMap(m.maxX, m.maxZ);
    g.fillStyle = '#155e7d';
    g.fillRect(mx0, mz0, mx1 - mx0, mz1 - mz0);
  }
  if (worldFoundation.river) {
    g.beginPath();
    worldFoundation.river.path.forEach((pt, i) => {
      const [x, y] = toMap(pt.x, pt.z);
      if (i === 0) g.moveTo(x, y); else g.lineTo(x, y);
    });
    g.strokeStyle = '#155e7d';
    g.lineWidth = Math.max(3, worldFoundation.river.widthM * scale);
    g.stroke();
  }
  g.lineCap = 'round';
  g.lineJoin = 'round';
  const strokeEdge = (edge, style, width) => {
    g.strokeStyle = style;
    g.lineWidth = width;
    g.beginPath();
    let started = false;
    edge.samples.forEach((pt, i) => {
      if (i % 2 !== 0 && i !== edge.samples.length - 1) return;
      const [x, y] = toMap(pt.x, pt.z);
      if (!started) { g.moveTo(x, y); started = true; } else g.lineTo(x, y);
    });
    g.stroke();
  };
  worldFoundation.roadGraph.edges.forEach((e) => strokeEdge(e, 'rgba(7, 13, 20, 0.92)', 2.6));
  worldFoundation.roadGraph.edges.forEach((e) => strokeEdge(
    e,
    e.surface === 'dirt' ? 'rgba(196, 160, 110, 0.9)' : 'rgba(220, 232, 238, 0.92)',
    1.3,
  ));
  worldFoundation.districts.forEach((d) => {
    const [x, y] = toMap(d.x, d.z);
    g.beginPath();
    g.arc(x, y, d.id === 'town-centre' ? 3.2 : 2.2, 0, TAU);
    g.fillStyle = d.id === 'town-centre' ? '#f0abfc' : '#facc15';
    g.fill();
    g.strokeStyle = 'rgba(0,0,0,0.45)';
    g.lineWidth = 1;
    g.stroke();
  });
  return c;
}

function drawBritainMinimap() {
  const S = 132;
  if (!britainMinimapBase) britainMinimapBase = buildBritainMinimapBase(S);
  const halfW = (worldFoundation.worldSizeM || 1000) / 2;
  const wb = worldFoundation.bounds || { minX: -halfW, maxX: halfW, minZ: -halfW, maxZ: halfW };
  const scale = S / (Math.max(wb.maxX - wb.minX, wb.maxZ - wb.minZ) * 1.08);
  const toMap = (x, z) => [S / 2 + (x - (wb.minX + wb.maxX) / 2) * scale, S / 2 + (z - (wb.minZ + wb.maxZ) / 2) * scale];
  minimap.clearRect(0, 0, S, S);
  minimap.save();
  minimap.beginPath();
  minimap.arc(S / 2, S / 2, S / 2 - 1, 0, TAU);
  minimap.clip();
  minimap.drawImage(britainMinimapBase, 0, 0);
  if (player.mesh) {
    const p = player.mesh.group.position;
    const [x, y] = toMap(p.x, p.z);
    minimap.save();
    minimap.translate(x, y);
    minimap.rotate(-player.yaw);
    minimap.beginPath();
    minimap.moveTo(0, 6.5);
    minimap.lineTo(-4.4, -5.2);
    minimap.lineTo(0, -2.6);
    minimap.lineTo(4.4, -5.2);
    minimap.closePath();
    minimap.fillStyle = '#ff5e3a';
    minimap.strokeStyle = '#fff';
    minimap.lineWidth = 1.3;
    minimap.fill();
    minimap.stroke();
    minimap.restore();
  }
  minimap.fillStyle = 'rgba(255,255,255,0.92)';
  minimap.font = '900 10px system-ui, sans-serif';
  minimap.textAlign = 'center';
  minimap.fillText('N', S / 2, 13);
  minimap.restore();
}

function drawMinimap() {
  if (isBritainWorld()) {
    drawBritainMinimap();
    return;
  }
  const S = 132;
  const scale = S / 610;
  const toMap = (x, z) => [S / 2 + x * scale, S / 2 + z * scale];
  minimap.clearRect(0, 0, S, S);
  minimap.save();
  minimap.beginPath();
  minimap.arc(S / 2, S / 2, S / 2 - 1, 0, TAU);
  minimap.clip();

  // Вода и остров: читаемый тёмный фон, как в современных гоночных интерфейсах
  minimap.fillStyle = '#0a2a3d';
  minimap.fillRect(0, 0, S, S);
  minimap.beginPath();
  minimap.arc(...toMap(0, 0), 292 * scale, 0, TAU);
  minimap.fillStyle = 'rgba(49, 92, 55, 0.94)';
  minimap.fill();
  minimap.strokeStyle = 'rgba(236, 211, 156, 0.78)';
  minimap.lineWidth = 2;
  minimap.stroke();

  const strokeSamples = (samples, step = 3, closed = false) => {
    minimap.beginPath();
    let started = false;
    samples.forEach((pt, i) => {
      if (i % step !== 0 && i !== samples.length - 1) return;
      const [x, y] = toMap(pt.x, pt.z);
      if (!started) {
        minimap.moveTo(x, y);
        started = true;
      } else {
        minimap.lineTo(x, y);
      }
    });
    if (closed) minimap.closePath();
    minimap.stroke();
  };

  minimap.lineCap = 'round';
  minimap.lineJoin = 'round';

  // Второстепенные дороги: тёмная подложка + светлая нитка асфальта
  minimap.strokeStyle = 'rgba(7, 13, 20, 0.92)';
  minimap.lineWidth = 4.4;
  SECONDARY_ROADS.forEach((road) => strokeSamples(road.samples, 3, road.closed));
  minimap.strokeStyle = 'rgba(174, 187, 194, 0.9)';
  minimap.lineWidth = 2.1;
  SECONDARY_ROADS.forEach((road) => strokeSamples(road.samples, 3, road.closed));

  // Главная трасса
  minimap.strokeStyle = 'rgba(7, 13, 20, 0.96)';
  minimap.lineWidth = 5.6;
  strokeSamples(SAMPLES, 4, true);
  minimap.strokeStyle = 'rgba(238, 246, 250, 0.96)';
  minimap.lineWidth = 3;
  strokeSamples(SAMPLES, 4, true);

  // Ближайший отрезок маршрута до следующего чекпоинта
  if (selectedMode === 'race' && player.mesh) {
    const startIdx = ((player.prevSampleIdx || 0) % 800 + 800) % 800;
    const targetIdx = Math.round((player.nextCP * 800) / CHECKPOINTS.length) % 800;
    const steps = (targetIdx - startIdx + 800) % 800;
    if (steps > 2 && steps <= 150) {
      const drawRoute = (style, width) => {
        minimap.beginPath();
        for (let offset = 0; offset <= steps; offset += 4) {
          const pt = SAMPLES[(startIdx + offset) % 800];
          const [x, y] = toMap(pt.x, pt.z);
          if (offset === 0) minimap.moveTo(x, y);
          else minimap.lineTo(x, y);
        }
        const last = SAMPLES[targetIdx];
        const [lx, ly] = toMap(last.x, last.z);
        minimap.lineTo(lx, ly);
        minimap.strokeStyle = style;
        minimap.lineWidth = width;
        minimap.stroke();
      };
      drawRoute('rgba(46, 230, 255, 0.34)', 5);
      drawRoute('#35e0ff', 2.4);
    }
  }

  // ориентиры: фестиваль и деревенская церковь
  [[0, -175, '#f0abfc'], [99, -23, '#facc15']].forEach(([wx, wz, color]) => {
    const [x, y] = toMap(wx, wz);
    minimap.beginPath();
    minimap.arc(x, y, 3.1, 0, TAU);
    minimap.fillStyle = color;
    minimap.fill();
    minimap.strokeStyle = 'rgba(0,0,0,0.45)';
    minimap.lineWidth = 1;
    minimap.stroke();
  });

  // следующий чекпоинт
  if (selectedMode === 'race') {
    const cp = CHECKPOINTS[player.nextCP];
    const [x, y] = toMap(cp.pos.x, cp.pos.z);
    minimap.beginPath();
    minimap.arc(x, y, 5.2, 0, TAU);
    minimap.fillStyle = '#7cfc4a';
    minimap.fill();
    minimap.strokeStyle = '#ffffff';
    minimap.lineWidth = 1.4;
    minimap.stroke();
  }

  // обычный трафик
  ambientCars.forEach((car) => {
    const p = car.mesh.group.position;
    const [x, y] = toMap(p.x, p.z);
    minimap.beginPath();
    minimap.arc(x, y, 1.7, 0, TAU);
    minimap.fillStyle = 'rgba(255,255,255,0.74)';
    minimap.fill();
  });

  // соперники
  rivals.forEach((r, i) => {
    const p = r.mesh.group.position;
    const [x, y] = toMap(p.x, p.z);
    minimap.beginPath();
    minimap.arc(x, y, 3.2, 0, TAU);
    minimap.fillStyle = '#' + RIVAL_COLORS[i].toString(16).padStart(6, '0');
    minimap.fill();
    minimap.strokeStyle = 'rgba(0,0,0,0.55)';
    minimap.lineWidth = 1;
    minimap.stroke();
  });

  // игрок — стрелка по курсу
  if (player.mesh) {
    const p = player.mesh.group.position;
    const [x, y] = toMap(p.x, p.z);
    minimap.save();
    minimap.translate(x, y);
    minimap.rotate(-player.yaw);
    minimap.beginPath();
    minimap.moveTo(0, 6.5);
    minimap.lineTo(-4.4, -5.2);
    minimap.lineTo(0, -2.6);
    minimap.lineTo(4.4, -5.2);
    minimap.closePath();
    minimap.fillStyle = '#ff5e3a';
    minimap.strokeStyle = '#fff';
    minimap.lineWidth = 1.3;
    minimap.fill();
    minimap.stroke();
    minimap.restore();
  }

  minimap.fillStyle = 'rgba(255,255,255,0.92)';
  minimap.font = '900 10px system-ui, sans-serif';
  minimap.textAlign = 'center';
  minimap.fillText('N', S / 2, 13);
  minimap.restore();
}

function updateHUD(dt) {
  if (!player.mesh) return;
  const kmh = Math.round(player.vel.length() * 3.6);
  if (speedFxEl) {
    const speedRatio = clamp(player.vel.length() / selectedCar.topSpeed, 0, 1);
    speedFxEl.style.opacity = graphicsQuality === 'realistic'
      ? (Math.pow(speedRatio, 1.7) * (player.boosting ? 0.9 : 0.52)).toFixed(3)
      : '0';
  }
  $('hudSpeed').textContent = kmh;
  $('hudGear').textContent = player.gear === -1 ? 'R' : (player.gear === 0 ? 'N' : player.gear);
  $('rpmFill').style.width = `${Math.round(player.rpmRatio * 100)}%`;
  $('rpmFill').classList.toggle('redline', player.rpmRatio > 0.86);
  $('hudSurface').textContent = player.surface;
  $('nitroFill').style.width = `${Math.round(player.nitro * 100)}%`;
  document.querySelector('.nitro-bar').classList.toggle('boosting', player.boosting);
  $('offroadLabel').textContent = player.surface;
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
    $('hudCheckpoint').textContent = `${Math.round(d)} м`;
    const raceProgress = clamp(player.s / (TOTAL_LAPS * TRACK_LENGTH), 0, 1);
    $('hudProgressPct').textContent = `${Math.round(raceProgress * 100)}%`;
    $('hudProgressBar').style.width = `${raceProgress * 100}%`;
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
  else if (countdownT > 0) text = 'ГО!';
  if (text !== countdownShown) {
    countdownShown = text;
    el.textContent = text;
    el.classList.remove('pop');
    void el.offsetWidth;
    el.classList.add('pop');
    engine.beep(text === 'ГО!' ? 990 : 440, 0.18);
    if (text === 'ГО!') {
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
  if (realWorldSceneHandle && realWorldSceneHandle.tick) realWorldSceneHandle.tick(t);
  if (foamRing) foamRing.material.opacity = 0.11 + Math.sin(t * 0.8) * 0.045;
  if (festivalWheel) festivalWheel.rotation.z += dt * 0.11;
  if (britainWheelRim) britainWheelRim.rotation.z += dt * 0.14;
  windTurbines.forEach((rotor, i) => {
    rotor.rotation.z += dt * (0.65 + i * 0.13);
  });
  cloudGroup.children.forEach((sprite) => {
    sprite.position.x += dt * (sprite.userData.speed || 1);
    if (sprite.position.x > 620) sprite.position.x = -620;
  });
  if (!isBritainWorld()) updateLivingWorld(gameState === 'paused' ? 0 : dt, t);
  updateTireEffects(dt);
  updateWorldFoundation(dt); // стриминг чанков Britain; в legacy — no-op

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

  // тень следует за игроком — дешевле для мобильных; в меню она нужна шоуруму
  if (player.mesh) {
    const p = player.mesh.group.position;
    sun.position.set(p.x - 90, p.y + 125, p.z - 60);
    sun.target.position.copy(p);
  } else {
    sun.position.set(-90, 110, -140);
    sun.target.position.set(0, 0, -60);
  }

  updateCamera(dt);
  if (composer && graphicsQuality === 'realistic') composer.render();
  else renderer.render(scene, camera);
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
  if (e.code === 'KeyV') resetOrbitView(true);
  if (e.code === 'KeyI') {
    if (inspectMode) exitInspectMode();
    else if (gameState === 'paused') enterInspectMode();
    else if (gameState === 'racing' || gameState === 'countdown') { pauseGame(); enterInspectMode(); }
  }
  if (e.code === 'Escape' && inspectMode) exitInspectMode();
  else if (e.code === 'Escape' && (gameState === 'racing' || gameState === 'countdown')) pauseGame();
  else if (e.code === 'Escape' && gameState === 'paused') resumeGame();
});
window.addEventListener('keyup', (e) => {
  const k = KEYMAP[e.code];
  if (k) input[k] = false;
});
window.addEventListener('blur', () => {
  ['gas', 'brake', 'left', 'right', 'nitro', 'handbrake'].forEach((k) => (input[k] = false));
  input.gasValue = 0;
  input.brakeValue = 0;
});

/* ============================ Управление: тач ============================ */
function showTouchControls(show) {
  const el = $('touchControls');
  el.classList.toggle('hidden', !show);
  const useWheel = controlScheme === 'wheel';
  $('steeringWheel').classList.toggle('hidden', !useWheel);
  $('steeringButtons').classList.toggle('hidden', useWheel);
  const isDesktop = window.matchMedia('(hover: hover) and (pointer: fine)').matches;
  el.classList.toggle('force-hide', isDesktop && !useWheel);
  el.classList.toggle('desktop-wheel', isDesktop && useWheel);
}

function bindHold(btn, key) {
  const on = (e) => {
    e.preventDefault();
    try { btn.setPointerCapture(e.pointerId); } catch (err) { /* noop */ }
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

function bindPedal(btn, key) {
  const valueKey = `${key}Value`;
  let activePointerId = null;
  let startY = 0;

  const setValue = (value) => {
    const next = clamp(Number(value) || 0, 0, 1);
    input[valueKey] = next;
    btn.classList.toggle('pressed', next > 0.02);
    btn.dataset.pedalValue = next.toFixed(2);
    btn.style.setProperty('--pedal-value', next.toFixed(3));
    btn.style.transform = next > 0.02 ? `scale(${(1 - next * 0.08).toFixed(3)})` : '';
  };

  const on = (e) => {
    e.preventDefault();
    activePointerId = e.pointerId;
    startY = e.clientY;
    try { btn.setPointerCapture(e.pointerId); } catch (err) { /* noop */ }
    // A normal tap is full travel.  Dragging down feathers the pedal;
    // dragging back up restores full travel without lifting the finger.
    const pressure = Number(e.pressure);
    setValue(pressure > 0.02 && pressure < 0.98 ? Math.max(0.25, pressure) : 1);
  };
  const move = (e) => {
    if (e.pointerId !== activePointerId) return;
    e.preventDefault();
    const dragDownPx = e.clientY - startY;
    setValue(dragDownPx > 0 ? 1 - dragDownPx / 115 : 1);
  };
  const off = (e) => {
    if (e.pointerId !== activePointerId) return;
    e.preventDefault();
    activePointerId = null;
    setValue(0);
  };

  btn.addEventListener('pointerdown', on);
  btn.addEventListener('pointermove', move);
  btn.addEventListener('pointerup', off);
  btn.addEventListener('pointercancel', off);
  btn.addEventListener('contextmenu', (e) => e.preventDefault());
}

bindPedal($('btnGas'), 'gas');
bindPedal($('btnBrake'), 'brake');
bindHold($('btnLeft'), 'left');
bindHold($('btnRight'), 'right');
bindHold($('btnNitro'), 'nitro');
bindHold($('btnДрифт'), 'handbrake');

/* Аналоговый виртуальный руль */
const steeringWheelEl = $('steeringWheel');
let lastSteerPointerTime = 0;
function steeringPointerAngle(e) {
  const rect = steeringWheelEl.getBoundingClientRect();
  return Math.atan2(e.clientY - (rect.top + rect.height / 2), e.clientX - (rect.left + rect.width / 2));
}
steeringWheelEl.addEventListener('pointerdown', (e) => {
  e.preventDefault();
  steering.grabbing = true;
  steering.pointerId = e.pointerId;
  steering.lastPointerAngle = steeringPointerAngle(e);
  steering.velocity = 0;
  lastSteerPointerTime = performance.now();
  input.left = false;
  input.right = false;
  steeringWheelEl.classList.add('grabbing');
  try { steeringWheelEl.setPointerCapture(e.pointerId); } catch (err) { /* noop */ }
});
steeringWheelEl.addEventListener('pointermove', (e) => {
  if (!steering.grabbing || e.pointerId !== steering.pointerId) return;
  e.preventDefault();
  const angle = steeringPointerAngle(e);
  const delta = wrapAnglePi(angle - steering.lastPointerAngle);
  const now = performance.now();
  const dt = Math.max((now - lastSteerPointerTime) / 1000, 0.001);
  steering.rotation = clamp(steering.rotation + delta, -steering.maxRotation, steering.maxRotation);
  steering.velocity = clamp(delta / dt, -14, 14);
  steering.lastPointerAngle = angle;
  lastSteerPointerTime = now;
});
function releaseSteeringWheel(e) {
  if (e.pointerId !== steering.pointerId) return;
  steering.grabbing = false;
  steering.pointerId = null;
  steeringWheelEl.classList.remove('grabbing');
}
steeringWheelEl.addEventListener('pointerup', releaseSteeringWheel);
steeringWheelEl.addEventListener('pointercancel', releaseSteeringWheel);
steeringWheelEl.addEventListener('dblclick', resetSteering);
steeringWheelEl.addEventListener('contextmenu', (e) => e.preventDefault());

/* Свободная орбита камеры: перетаскивание, щипок, колесо мыши, двойной тап */
const orbitPointers = new Map();
let orbitPinchDistance = 0;
let lastOrbitTapTime = 0;
function isOrbitInteractiveTarget(target) {
  return !target || (target.closest && target.closest('button, input, select, textarea, a, .panel, #steeringWheel, .touch-btn'));
}
function canOrbitFromEvent(e) {
  if (isOrbitInteractiveTarget(e.target)) return false;
  if (gameState === 'menu') return e.target === renderer.domElement || e.target === $('menu') || (e.target.closest && e.target.closest('.logo, .showroom-stage, .menu-topbar'));
  return !!player.mesh && e.target === renderer.domElement;
}
function markOrbitInteraction() {
  if (gameState === 'menu') cameraOrbit.menuIdle = 0;
  else cameraOrbit.idle = 0;
}
function resetOrbitView(announce = true) {
  if (gameState === 'menu') {
    cameraOrbit.yaw = 0;
    cameraOrbit.menuPitch = 0.24;
    cameraOrbit.menuDistance = 7.4;
    cameraOrbit.menuIdle = 0;
  } else {
    resetCameraOrbit();
  }
  if (announce && gameState !== 'menu') showCenterMsg('Обзор камеры сброшен', 850, '#fff', 'crosshair');
}
window.addEventListener('pointerdown', (e) => {
  if (e.button !== undefined && e.button > 0) return;
  if (!canOrbitFromEvent(e)) return;
  const now = performance.now();
  if (e.pointerType === 'touch' && now - lastOrbitTapTime < 320 && orbitPointers.size === 0) {
    resetOrbitView(true);
    lastOrbitTapTime = 0;
    return;
  }
  lastOrbitTapTime = now;
  orbitPointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
  if (orbitPointers.size === 2) {
    const [a, b] = [...orbitPointers.values()];
    orbitPinchDistance = Math.hypot(a.x - b.x, a.y - b.y);
  }
  try { e.target.setPointerCapture(e.pointerId); } catch (err) { /* noop */ }
});
window.addEventListener('pointermove', (e) => {
  const stored = orbitPointers.get(e.pointerId);
  if (!stored) return;
  const dx = e.clientX - stored.x;
  const dy = e.clientY - stored.y;
  stored.x = e.clientX;
  stored.y = e.clientY;
  markOrbitInteraction();
  if (orbitPointers.size === 2) {
    const [a, b] = [...orbitPointers.values()];
    const dist = Math.hypot(a.x - b.x, a.y - b.y);
    if (orbitPinchDistance > 0 && dist > 0) {
      const factor = orbitPinchDistance / dist;
      if (gameState === 'menu') cameraOrbit.menuDistance = clamp(cameraOrbit.menuDistance * factor, 4.2, 16);
      else cameraOrbit.distanceScale = clamp(cameraOrbit.distanceScale * factor, 0.5, 2.0);
    }
    orbitPinchDistance = dist;
    return;
  }
  cameraOrbit.yaw -= dx * 0.0072;
  if (gameState === 'menu') {
    cameraOrbit.menuPitch = clamp(cameraOrbit.menuPitch - dy * 0.005, -0.04, 1.05);
  } else {
    cameraOrbit.pitch = clamp(cameraOrbit.pitch - dy * 0.005, -0.28, 0.98);
  }
});
function releaseOrbitPointer(e) {
  orbitPointers.delete(e.pointerId);
  if (orbitPointers.size < 2) orbitPinchDistance = 0;
}
window.addEventListener('pointerup', releaseOrbitPointer);
window.addEventListener('pointercancel', releaseOrbitPointer);
renderer.domElement.addEventListener('dblclick', () => resetOrbitView(true));
window.addEventListener('wheel', (e) => {
  if (isOrbitInteractiveTarget(e.target)) return;
  if (gameState === 'menu' && !(e.target === renderer.domElement || e.target === $('menu') || (e.target.closest && e.target.closest('.logo, .showroom-stage, .menu-topbar')))) return;
  if (gameState !== 'menu' && !player.mesh) return;
  const factor = Math.exp(e.deltaY * 0.0011);
  markOrbitInteraction();
  if (gameState === 'menu') cameraOrbit.menuDistance = clamp(cameraOrbit.menuDistance * factor, 4.2, 16);
  else cameraOrbit.distanceScale = clamp(cameraOrbit.distanceScale * factor, 0.5, 2.0);
}, { passive: true });



document.addEventListener('touchmove', (e) => {
  if (gameState === 'racing' || gameState === 'countdown') e.preventDefault();
}, { passive: false });

/* ============================ UI: меню и кнопки ============================ */
function carClassCode(car) {
  const match = car.cls.match(/Класс\s+([A-Z]\d?)/);
  return match ? match[1] : 'A';
}

function carPerformanceIndex(car) {
  const weighted = car.stats.spd * 0.34 + car.stats.acc * 0.28 + car.stats.hnd * 0.26 + car.stats.off * 0.12;
  const bases = { S1: 900, S: 830, A: 720, B: 560 };
  return Math.round((bases[carClassCode(car)] || 700) + weighted * 72);
}

function carDriveLabel(car) {
  if (car.driveFrontBias >= 0.49) return 'AWD 50/50';
  if (car.driveFrontBias > 0) {
    const front = Math.round(car.driveFrontBias * 100);
    return `AWD ${front}/${100 - front}`;
  }
  return 'RWD';
}

function updateMenuHero() {
  const heroName = $('heroCarName');
  if (!heroName) return;
  const car = selectedCar;
  heroName.textContent = car.name;
  $('heroCarClass').textContent = carClassCode(car);
  $('heroCarPI').textContent = `PI ${carPerformanceIndex(car)}`;
  $('heroCarClassLine').textContent = car.cls;
  $('heroPower').textContent = `${Math.round(car.powerKW * 1.341)} л.с.`;
  $('heroDrive').textContent = carDriveLabel(car);
  $('heroTopSpeed').textContent = `${Math.round(car.topSpeed * 3.6)} км/ч`;
  $('heroMass').textContent = `${car.mass} кг`;
  $('menuЛучшийLap').textContent = player.лучшийLap ? fmtTime(player.лучшийLap) : '—';
  $('menuProfileClass').textContent = carClassCode(car);
  $('menuCarsOwned').textContent = `${CARS.length} АВТО`;
  $('startModeLabel').textContent = selectedMode === 'race'
    ? `Гонка • ${TOTAL_LAPS} круга • 5 соперников`
    : 'Свободный заезд • открытый остров';
}

function buildCarPicker() {
  const wrap = $('carPicker');
  wrap.innerHTML = '';
  CARS.forEach((car) => {
    const btn = document.createElement('button');
    btn.className = 'car-card' + (car === selectedCar ? ' selected' : '');
    btn.type = 'button';
    btn.setAttribute('aria-pressed', car === selectedCar ? 'true' : 'false');
    btn.innerHTML = `
      <div class="car-card-top">
        <div class="car-swatch" style="background:#${car.color.toString(16).padStart(6, '0')}">${iconMarkup(car.silhouette || 'car-coupe', 'car-silhouette')}</div>
        <div class="car-heading">
          <div class="car-name">${car.name}</div>
          <div class="car-class">${car.cls}</div>
          <div class="car-drive-badge">${carDriveLabel(car)}</div>
        </div>
        <div class="car-pi"><span>${carClassCode(car)}</span><b>${carPerformanceIndex(car)}</b></div>
      </div>
      <div class="car-stats">
        <div class="stat">СКОР.<span class="bar"><i style="width:${car.stats.spd * 100}%"></i></span></div>
        <div class="stat">РАЗГОН<span class="bar"><i style="width:${car.stats.acc * 100}%"></i></span></div>
        <div class="stat">УПРАВЛ.<span class="bar"><i style="width:${car.stats.hnd * 100}%"></i></span></div>
        <div class="stat">ГРУНТ<span class="bar"><i style="width:${car.stats.off * 100}%"></i></span></div>
      </div>`;
    btn.addEventListener('click', () => {
      selectedCar = car;
      buildCarPicker();
      previewCarInMenu();
    });
    wrap.appendChild(btn);
  });
  buildPaintPicker();
  updateMenuHero();
}

function buildPaintPicker() {
  const wrap = $('paintPicker');
  if (!wrap) return;
  const paintConfig = selectedCar.id === 'gtr35'
    ? {
      list: GTR_PAINTS,
      currentHex: selectedGTRPaint,
      label: 'GT-R35',
      apply: (hex) => { selectedGTRPaint = hex; safeSetItem('nh_gtr_paint', hex); },
    }
    : selectedCar.id === 'mustang'
      ? {
        list: MUSTANG_PAINTS,
        currentHex: selectedMustangPaint,
        label: 'Mustang',
        apply: (hex) => { selectedMustangPaint = hex; safeSetItem('nh_mustang_paint', hex); },
      }
      : null;
  wrap.classList.remove('hidden');
  if (!paintConfig) {
    const factoryHex = `#${selectedCar.color.toString(16).padStart(6, '0')}`;
    wrap.innerHTML = `<div class="paint-title">${iconMarkup('palette', 'ui-icon')} Цвет кузова: <b>заводской ${factoryHex.toUpperCase()}</b></div>`;
    const row = document.createElement('div');
    row.className = 'paint-row';
    const sw = document.createElement('button');
    sw.className = 'paint-swatch selected';
    sw.type = 'button';
    sw.disabled = true;
    sw.title = 'Заводской цвет';
    sw.setAttribute('aria-label', `Заводской цвет ${factoryHex.toUpperCase()}`);
    sw.setAttribute('aria-pressed', 'true');
    sw.style.background = factoryHex;
    row.appendChild(sw);
    wrap.appendChild(row);
    return;
  }
  const current = paintConfig.list.find((paint) => paint.hex === paintConfig.currentHex);
  wrap.innerHTML = `<div class="paint-title">${iconMarkup('palette', 'ui-icon')} Краска ${paintConfig.label}: <b>${current ? current.name : ''}</b></div>`;
  const row = document.createElement('div');
  row.className = 'paint-row';
  paintConfig.list.forEach((paint) => {
    const sw = document.createElement('button');
    sw.className = 'paint-swatch' + (paint.hex === paintConfig.currentHex ? ' selected' : '');
    sw.type = 'button';
    sw.title = paint.name;
    sw.setAttribute('aria-label', `Краска: ${paint.name}`);
    sw.setAttribute('aria-pressed', paint.hex === paintConfig.currentHex ? 'true' : 'false');
    sw.style.background = `#${paint.hex.toString(16).padStart(6, '0')}`;
    sw.addEventListener('click', () => {
      paintConfig.apply(paint.hex);
      selectedCar.color = paint.hex;
      buildCarPicker();
      previewCarInMenu();
    });
    row.appendChild(sw);
  });
  wrap.appendChild(row);
}

function previewCarInMenu() {
  createPlayerCar();
  const start = isBritainWorld() ? britainSpawnPoint() : pointAtS(-10, 0);
  player.mesh.group.position.copy(start.pos);
  if (isBritainWorld()) {
    player.mesh.group.position.y = worldFoundation.heightAt(start.pos.x, start.pos.z);
  }
  player.mesh.group.rotation.set(0, start.yaw + 0.6, 0);
  player.yaw = start.yaw + 0.6;
  if (menuStage) menuStage.visible = true;
  // Передний три-четвертной ракурс: камера перед машиной и чуть сбоку.
  menuOrbit = player.yaw + 0.78;
  cameraOrbit.yaw = 0;
  cameraOrbit.menuPitch = 0.18;
  cameraOrbit.menuDistance = 8.6;
  cameraOrbit.menuIdle = 0;
  updateMenuHero();
}

document.querySelectorAll('.mode-btn').forEach((btn) => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.mode-btn').forEach((b) => {
      const active = b === btn;
      b.classList.toggle('active', active);
      b.setAttribute('aria-pressed', active ? 'true' : 'false');
    });
    selectedMode = btn.dataset.mode;
    if (isBritainWorld()) {
      selectedMode = 'free'; // гонки на новой карте — следующим этапом
      applyBritainModeUI();
    }
    updateMenuHero();
  });
});

function cycleCamera() {
  cameraMode = (cameraMode + 1) % 3;
  if (cameraMode === 2 && !inspectMode) resetCameraOrbit();
  const names = ['Камера: погоня', 'Камера: издалека', 'Камера: капот'];
  showCenterMsg(names[cameraMode], 900, '#fff', 'camera');
}

function pauseGame() {
  if (inspectMode) { exitInspectMode(); return; }
  if (gameState !== 'racing' && gameState !== 'countdown') return;
  player.prevState = gameState;
  gameState = 'paused';
  $('pauseMenu').classList.remove('hidden');
  showTouchControls(false);
  engine.update(0, false);
}

function resumeGame() {
  inspectMode = false;
  $('inspectBar').classList.add('hidden');
  gameState = player.prevState || 'racing';
  $('pauseMenu').classList.add('hidden');
  showTouchControls(true);
  clock.getDelta();
}

function toMenu() {
  inspectMode = false;
  $('inspectBar').classList.add('hidden');
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


function enterInspectMode() {
  if (gameState !== 'paused') return;
  inspectMode = true;
  $('pauseMenu').classList.add('hidden');
  $('inspectBar').classList.remove('hidden');
  showTouchControls(false);
  cameraOrbit.idle = 0;
  if (cameraMode === 2) cameraMode = 0;
  showCenterMsg('Осматривай машину со всех сторон', 1300, '#2ee6ff', 'eye');
}
function exitInspectMode() {
  inspectMode = false;
  $('inspectBar').classList.add('hidden');
  if (gameState === 'paused') $('pauseMenu').classList.remove('hidden');
}
function applyControlScheme(scheme, announce = false) {
  controlScheme = scheme === 'buttons' ? 'buttons' : 'wheel';
  safeSetItem('nh_controls', controlScheme);
  document.querySelectorAll('.control-btn').forEach((btn) => {
    const active = btn.dataset.control === controlScheme;
    btn.classList.toggle('active', active);
    btn.setAttribute('aria-pressed', active ? 'true' : 'false');
  });
  resetSteering();
  if (gameState === 'racing' || gameState === 'countdown') showTouchControls(true);
  else showTouchControls(false);
  if (announce) {
    showCenterMsg(
      controlScheme === 'wheel' ? 'Управление: аналоговый руль' : 'Управление: сенсорные кнопки',
      1000,
      '#fff',
      controlScheme === 'wheel' ? 'steering-wheel' : 'gamepad',
    );
  }
}
function applyAssistMode(mode, announce = false) {
  assistMode = ASSIST_PROFILES[mode] ? mode : 'sport';
  safeSetItem('nh_assist', assistMode);
  document.querySelectorAll('.assist-btn').forEach((btn) => {
    const active = btn.dataset.assist === assistMode;
    btn.classList.toggle('active', active);
    btn.setAttribute('aria-pressed', active ? 'true' : 'false');
  });
  if (announce) showCenterMsg(`Ассистенты: ${ASSIST_PROFILES[assistMode].label}`, 1000);
}
document.querySelectorAll('.control-btn').forEach((btn) => {
  btn.addEventListener('click', () => applyControlScheme(btn.dataset.control, true));
});
document.querySelectorAll('.assist-btn').forEach((btn) => {
  btn.addEventListener('click', () => applyAssistMode(btn.dataset.assist, true));
});

function applyGraphicsQuality(quality, announce = false) {
  graphicsQuality = quality === 'fast' ? 'fast' : 'realistic';
  safeSetItem('nh_gfx', graphicsQuality);
  document.querySelectorAll('[data-gfx]').forEach((btn) => {
    const active = btn.dataset.gfx === graphicsQuality;
    btn.classList.toggle('active', active);
    btn.setAttribute('aria-pressed', active ? 'true' : 'false');
  });
  renderer.setPixelRatio(graphicsQuality === 'realistic' ? Math.min(window.devicePixelRatio, 2) : 1);
  renderer.setSize(window.innerWidth, window.innerHeight);
  syncComposerSize();
  const shadowSize = graphicsQuality === 'realistic' ? 2048 : 1024;
  sun.shadow.radius = graphicsQuality === 'realistic' ? 3.2 : 2;
  sun.shadow.camera.left = graphicsQuality === 'realistic' ? -64 : -40;
  sun.shadow.camera.right = -sun.shadow.camera.left;
  sun.shadow.camera.top = -sun.shadow.camera.left;
  sun.shadow.camera.bottom = sun.shadow.camera.left;
  sun.shadow.camera.updateProjectionMatrix();
  renderer.toneMappingExposure = (SKY_EXPOSURE[skyMood] || 1.3) * (graphicsQuality === 'realistic' ? 1 : 0.85);

  if (sun.shadow.mapSize.x !== shadowSize) {
    sun.shadow.mapSize.set(shadowSize, shadowSize);
    if (sun.shadow.map) {
      sun.shadow.map.dispose();
      sun.shadow.map = null;
    }
  }
  if (grassMesh) grassMesh.visible = graphicsQuality === 'realistic';
  if (bushMesh) bushMesh.visible = graphicsQuality === 'realistic';
  if (speedFxEl && graphicsQuality !== 'realistic') speedFxEl.style.opacity = '0';
  cloudGroup.visible = graphicsQuality === 'realistic';
  if (announce) {
    showCenterMsg(
      graphicsQuality === 'realistic' ? 'Графика: реалистичная' : 'Графика: быстрая',
      1100,
      '#fff',
      graphicsQuality === 'realistic' ? 'sparkles' : 'zap',
    );
  }
}
document.querySelectorAll('[data-gfx]').forEach((btn) => {
  btn.addEventListener('click', () => applyGraphicsQuality(btn.dataset.gfx, true));
});
document.querySelectorAll('[data-sky]').forEach((btn) => {
  btn.addEventListener('click', () => applySkyMood(btn.dataset.sky, true));
});

$('btnStart').addEventListener('click', startGame);
$('btnPause').addEventListener('click', pauseGame);
$('btnResume').addEventListener('click', resumeGame);
$('btnRestart').addEventListener('click', startGame);
$('btnToMenu').addEventListener('click', toMenu);
$('btnRaceAgain').addEventListener('click', startGame);
$('btnFinishToMenu').addEventListener('click', toMenu);
$('btnCamera').addEventListener('click', cycleCamera);
$('btnCameraReset').addEventListener('click', () => resetOrbitView(true));
$('btnInspect').addEventListener('click', () => {
  if (inspectMode) exitInspectMode();
  else if (gameState === 'paused') enterInspectMode();
  else if (gameState === 'racing' || gameState === 'countdown') { pauseGame(); enterInspectMode(); }
});
$('btnInspectPause').addEventListener('click', enterInspectMode);
$('btnInspectDone').addEventListener('click', exitInspectMode);
$('btnInspectCamera').addEventListener('click', cycleCamera);
$('btnRespawn').addEventListener('click', () => gameState === 'racing' && respawn());
$('btnSound').addEventListener('click', () => {
  engine.enabled = !engine.enabled;
  const btn = $('btnSound');
  setIcon(btn, engine.enabled ? 'volume-2' : 'volume-x');
  btn.setAttribute('aria-pressed', engine.enabled ? 'true' : 'false');
  btn.title = engine.enabled ? 'Выключить звук' : 'Включить звук';
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
  renderer.setPixelRatio(graphicsQuality === 'realistic' ? Math.min(window.devicePixelRatio, 2) : 1);
  syncComposerSize();
  updateRotateHint();
});

/* ============================ Старт ============================ */
buildCarPicker();
applyBritainModeUI();
applyControlScheme(controlScheme);
applyAssistMode(assistMode);
applyGraphicsQuality(graphicsQuality);
previewCarInMenu();
drawMinimap();
animate();

// Необязательный облачный контент не должен блокировать встроенный мир/APK.
// Если CDN не настроен или недоступен, игра продолжит работу без прототипа.
// Облачный дуб привязан к legacy-сплайну — на новой карте его пока нет.
if (!isBritainWorld()) {
  void installCloudPrototype({
    scene,
    colliders,
    terrainHeight,
    pointAtS,
    roadDistanceApprox,
  });
}

// PWA: офлайн-кэш только в продакшен-сборке
if (import.meta.env.PROD && 'serviceWorker' in navigator) {
  navigator.serviceWorker.register('/sw.js').catch(() => {});
}
