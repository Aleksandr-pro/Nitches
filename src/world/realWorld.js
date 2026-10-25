/**
 * Real Valley — playable world: 1 x 1 km valley plus the RichTown district.
 *
 * v0.10 layout follows the "Nitches Horizon" reference map: a dense city
 * street grid around a wide central avenue with a drag strip at its north
 * end, a roundabout where the avenue meets the east-west highway, a winding
 * river with a riverside road along the west edge, a closed drift circuit
 * in the south-west, a festival plaza and parking lots in the east, and a
 * car shop + cafe on the southern street.
 *
 * v0.15 expands the world 650 m east with RichTown — a modern Dubai-style
 * district: a wide palm-lined boulevard, glass/gold/marble skyscrapers, a
 * 148 m needle tower, a golden frame arch over the boulevard, a fountain
 * plaza and a rectangular marina basin.
 *
 * Pure-data foundation (no Three imports): analytic terrain, road network
 * reusing the shared road-graph/spatial-index code, surfaces, districts and
 * a deterministic dressing plan (city blocks, tents, trees, rocks, lamps)
 * with colliders.  Rendering lives in realWorldScene.js and uses generated
 * photorealistic textures — no bare coloured primitives.
 */
import { buildRoadGraph, buildRoadSegments, findRoute as graphFindRoute, roadPointAt } from './roadGraph.js';
import { ColliderIndex, RoadSpatialIndex } from './spatialIndex.js';

export const REAL_WORLD_ID = 'real-valley';
export const REAL_WORLD_VERSION = '0.16.0';
/** World width (x extent) in metres; the world grew east in v0.15. */
export const REAL_WORLD_SIZE_M = 2000;
export const REAL_WORLD_HALF_M = 500;
export const REAL_WORLD_BOUNDS = Object.freeze({
  minX: -500,
  minZ: -500,
  maxX: 1500,
  maxZ: 500,
});

/** The river hugs the west edge; centreline x as a function of z. */
export function riverCenterX(z) {
  return -385 + 42 * Math.sin(z * 0.011) + 16 * Math.sin(z * 0.023 + 1.7);
}
export const REAL_WORLD_RIVER = Object.freeze({
  waterLevelM: 0.3,
  widthM: 30,
  centerXAt: riverCenterX,
  path: Object.freeze(
    Array.from({ length: 41 }, (_, i) => {
      const z = -500 + i * 25;
      return Object.freeze({ x: riverCenterX(z), z });
    }),
  ),
});

/** Paved/functional rectangles shared by physics surfaces and rendering. */
export const REAL_WORLD_ZONES = Object.freeze({
  plaza: Object.freeze({ minX: 296, maxX: 478, minZ: -274, maxZ: -46 }),
  parkings: Object.freeze([
    Object.freeze({ minX: 296, maxX: 478, minZ: 36, maxZ: 186 }),
    Object.freeze({ minX: -202, maxX: -38, minZ: 348, maxZ: 402 }),
    Object.freeze({ minX: 38, maxX: 202, minZ: 348, maxZ: 402 }),
    Object.freeze({ minX: 300, maxX: 470, minZ: -405, maxZ: -295 }),
    Object.freeze({ minX: -150, maxX: -40, minZ: 245, maxZ: 305, style: 'angled' }),
    Object.freeze({ minX: -375, maxX: -300, minZ: -135, maxZ: -65, style: 'angled' }),
  ]),
  city: Object.freeze({ minX: -185, maxX: 285, minZ: -415, maxZ: 205 }),
  richtown: Object.freeze({ minX: 520, maxX: 1490, minZ: -470, maxZ: 470 }),
  marina: Object.freeze({ minX: 780, maxX: 1045, minZ: 150, maxZ: 380 }),
  sea: Object.freeze({ minX: 1030, maxX: 1500, minZ: -500, maxZ: 500 }),
  beach: Object.freeze({ minX: 940, maxX: 1045, minZ: -480, maxZ: 480 }),
  palmIsland: Object.freeze({ minX: 1140, maxX: 1480, minZ: -430, maxZ: -80 }),
  sailIsland: Object.freeze({ minX: 1110, maxX: 1250, minZ: 10, maxZ: 150 }),
  rtPlaza: Object.freeze({ minX: 600, maxX: 730, minZ: -90, maxZ: 40 }),
  roundabout: Object.freeze({ x: 0, z: 225, r: 34, islandR: 27 }),
  drift: Object.freeze({ x: -292, z: 338 }),
});

export const REAL_WORLD_DISTRICTS = Object.freeze([
  { id: 'city-centre', name: 'Центр города', x: 0, z: -120, radiusM: 240, biome: 'urban' },
  { id: 'drag-strip', name: 'Дрэг-трасса', x: 0, z: -385, radiusM: 150, biome: 'urban' },
  { id: 'festival', name: 'Фестиваль Nitches Horizon', x: 390, z: -160, radiusM: 185, biome: 'urban' },
  { id: 'drift-zone', name: 'Дрифт-зона', x: -292, z: 338, radiusM: 175, biome: 'park' },
  { id: 'riverside', name: 'Риверсайд', x: -355, z: -60, radiusM: 210, biome: 'forest' },
  { id: 'south-quarter', name: 'Южный квартал', x: 0, z: 345, radiusM: 195, biome: 'urban' },
  { id: 'richtown', name: 'RichTown', x: 700, z: -60, radiusM: 360, biome: 'urban' },
  { id: 'richtown-marina', name: 'RichTown Marina', x: 870, z: 265, radiusM: 210, biome: 'urban' },
  { id: 'richtown-beach', name: 'Пляж RichTown', x: 985, z: -60, radiusM: 260, biome: 'park' },
  { id: 'palm-island', name: 'Остров-Пальма', x: 1340, z: -250, radiusM: 240, biome: 'urban' },
]);

export const REAL_WORLD_SURFACES = Object.freeze({
  asphalt: { id: 'asphalt', label: 'АСФАЛЬТ', mu: 1.0, rollingResistance: 0.012 },
  concrete: { id: 'concrete', label: 'БЕТОН', mu: 0.94, rollingResistance: 0.014 },
  gravel: { id: 'gravel', label: 'ГРАВИЙ', mu: 0.68, rollingResistance: 0.04 },
  dirt: { id: 'dirt', label: 'ГРУНТ', mu: 0.72, rollingResistance: 0.055 },
  grass: { id: 'grass', label: 'ТРАВА', mu: 0.66, rollingResistance: 0.05 },
  forest: { id: 'forest', label: 'ЛЕСНАЯ ПОЧВА', mu: 0.58, rollingResistance: 0.065 },
  rock: { id: 'rock', label: 'СКАЛА', mu: 0.55, rollingResistance: 0.05 },
  sand: { id: 'sand', label: 'ПЕСОК', mu: 0.48, rollingResistance: 0.09 },
  water: { id: 'water', label: 'ВОДА', mu: 0.18, rollingResistance: 0.2 },
});

function finite(value, fallback) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}
function clamp(value, min, max) {
  return Math.max(min, Math.min(max, finite(value, min)));
}
function lerp(a, b, t) {
  return a + (b - a) * t;
}
function smoothstep(edge0, edge1, value) {
  const t = clamp((value - edge0) / Math.max(1e-9, edge1 - edge0), 0, 1);
  return t * t * (3 - 2 * t);
}
function gaussian(x, z, cx, cz, height, sigma) {
  const dx = x - cx;
  const dz = z - cz;
  return height * Math.exp(-(dx * dx + dz * dz) / (2 * sigma * sigma));
}
function radialBlend(x, z, cx, cz, inner, outer) {
  return 1 - smoothstep(inner, outer, Math.hypot(x - cx, z - cz));
}
function rectDistance(x, z, rect) {
  const dx = Math.max(rect.minX - x, 0, x - rect.maxX);
  const dz = Math.max(rect.minZ - z, 0, z - rect.maxZ);
  return Math.hypot(dx, dz);
}
function rectBlend(x, z, rect, feather) {
  return 1 - smoothstep(0, feather, rectDistance(x, z, rect));
}
function inRect(x, z, rect, pad = 0) {
  return x >= rect.minX - pad && x <= rect.maxX + pad && z >= rect.minZ - pad && z <= rect.maxZ + pad;
}
function hash2(ix, iz, seed) {
  let n = (Math.imul(ix, 374761393) + Math.imul(iz, 668265263) + Math.imul(seed, 974634211)) >>> 0;
  n = Math.imul(n ^ (n >>> 13), 1274126177) >>> 0;
  return ((n ^ (n >>> 16)) >>> 0) / 4294967295;
}
function valueNoise(x, z, seed) {
  const ix = Math.floor(x);
  const iz = Math.floor(z);
  const fx = x - ix;
  const fz = z - iz;
  const sx = fx * fx * (3 - 2 * fx);
  const sz = fz * fz * (3 - 2 * fz);
  const a = hash2(ix, iz, seed);
  const b = hash2(ix + 1, iz, seed);
  const c = hash2(ix, iz + 1, seed);
  const d = hash2(ix + 1, iz + 1, seed);
  return lerp(lerp(a, b, sx), lerp(c, d, sx), sz);
}
function fbm(x, z, seed, octaves = 4) {
  let sum = 0;
  let amp = 0.5;
  let freq = 1;
  let norm = 0;
  for (let i = 0; i < octaves; i++) {
    sum += amp * valueNoise(x * freq, z * freq, seed + i * 131);
    norm += amp;
    amp *= 0.5;
    freq *= 2.03;
  }
  return sum / Math.max(norm, 1e-9);
}
export function mulberry32(seed) {
  let a = seed >>> 0;
  return function next() {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function rawHeightSampler(seed) {
  return (x, z) => {
    const px = finite(x, 0);
    const pz = finite(z, 0);
    let h = 3.4
      + (fbm(px * 0.0016 + 3.1, pz * 0.0016 - 1.4, seed, 4) - 0.5) * 4.4
      + (fbm(px * 0.008 - 5.2, pz * 0.008 + 2.8, seed + 17, 3) - 0.5) * 1.2;

    // Gentle framing hills; peaks stay away from road junctions so every
    // pinned road profile can satisfy the 16% grade limit.
    h += gaussian(px, pz, -260, -480, 11, 200);
    h += gaussian(px, pz, 430, -380, 11, 200);
    h += gaussian(px, pz, 420, 430, 9, 210);
    h += gaussian(px, pz, -470, -160, 7, 170);

    // Flat buildable zones: city grid, festival/parking, drift, south.
    h = lerp(h, 3.6, radialBlend(px, pz, 30, -110, 250, 430) * 0.94);
    h = lerp(h, 3.8, rectBlend(px, pz, REAL_WORLD_ZONES.plaza, 60) * 0.95);
    for (const r of REAL_WORLD_ZONES.parkings) {
      h = lerp(h, 3.8, rectBlend(px, pz, r, 55) * 0.92);
    }
    h = lerp(h, 4.2, radialBlend(px, pz, REAL_WORLD_ZONES.drift.x, REAL_WORLD_ZONES.drift.z, 105, 200) * 0.92);
    h = lerp(h, 3.9, rectBlend(px, pz, { minX: -250, maxX: 250, minZ: 270, maxZ: 430 }, 70) * 0.8);

    // RichTown plateau, beach shelf, then the marina inlet cut (the x=930
    // Corniche crosses the inlet on a land bridge, like the river causeway).
    h = lerp(h, 4.0, rectBlend(px, pz, { minX: 520, maxX: 1045, minZ: -470, maxZ: 470 }, 80) * 0.95);
    h = lerp(h, 1.5, rectBlend(px, pz, REAL_WORLD_ZONES.beach, 30) * 0.96);
    const marinaBridge = rectBlend(px, pz, { minX: 912, maxX: 948, minZ: 140, maxZ: 390 }, 8);
    h = lerp(h, -1.4, rectBlend(px, pz, REAL_WORLD_ZONES.marina, 10) * 0.99 * (1 - marinaBridge * 0.98));

    // River channel along the west edge, with a land bridge where the
    // highway and the riverside road cross (z ~ 192..238).
    const dRiver = Math.abs(px - riverCenterX(pz));
    const gap = smoothstep(172, 192, pz) * (1 - smoothstep(238, 258, pz));
    const endFade = 1 - smoothstep(452, 492, Math.abs(pz));
    const riverCut = (1 - smoothstep(10, 34, dRiver)) * (1 - gap) * endFade;
    h = lerp(h, -1.4, riverCut * 0.98);

    // Rim hills close the playable area along the (now rectangular) bounds.
    const dEdge = Math.min(
      px - REAL_WORLD_BOUNDS.minX,
      REAL_WORLD_BOUNDS.maxX - px,
      pz - REAL_WORLD_BOUNDS.minZ,
      REAL_WORLD_BOUNDS.maxZ - pz,
    );
    const edge = 1 - smoothstep(0, 45, dEdge);
    h = lerp(h, h + 18, edge * 0.8);

    // Sea and artificial islands are applied after the rim so the eastern
    // border stays open water (no rim wall in the sea). Causeways are land
    // bridges at road level, the same trick as the river crossing.
    h = lerp(h, -2.2, rectBlend(px, pz, REAL_WORLD_ZONES.sea, 26) * 0.99);
    h = lerp(h, 2.5, rectBlend(px, pz, { minX: 930, maxX: 1340, minZ: -264, maxZ: -236 }, 10) * 0.98);
    h = lerp(h, 2.5, rectBlend(px, pz, { minX: 930, maxX: 1195, minZ: 67, maxZ: 93 }, 10) * 0.98);
    h = lerp(h, 2.2, rectBlend(px, pz, { minX: 1240, maxX: 1400, minZ: -282, maxZ: -218 }, 26) * 0.97);
    for (const [cx, cz] of [[1360, -350], [1410, -300], [1435, -240], [1410, -180], [1355, -125]]) {
      h = lerp(h, 2.1, radialBlend(px, pz, cx, cz, 38, 82) * 0.97);
    }
    h = lerp(h, 2.2, radialBlend(px, pz, 1180, 80, 34, 74) * 0.97);
    return Number.isFinite(h) ? h : 0;
  };
}

// --- Road network definition -------------------------------------------------
const CITY_VX = [
  { x: -150, widthM: 10 },
  { x: 0, widthM: 16, avenue: true },
  { x: 140, widthM: 10 },
  { x: 250, widthM: 10 },
];
const CITY_HZ = [-380, -290, -200, -110, -20, 70, 150];
const HIGHWAY_Z = 225;

function edge(id, from, to, points, options = {}) {
  return {
    id, from, to, points,
    roadClass: options.roadClass || 'A',
    surface: options.surface || 'asphalt',
    widthM: options.widthM || 9,
    lanes: options.lanes || 2,
    speedLimitKmh: options.speedLimitKmh || 60,
    name: options.name || id,
  };
}

function buildRoadDefinition() {
  const nodes = [];
  const edges = [];
  const idByKey = new Map();
  const addNode = (id, x, z) => {
    const key = `${Math.round(x * 10)},${Math.round(z * 10)}`;
    if (idByKey.has(key)) return idByKey.get(key);
    idByKey.set(key, id);
    nodes.push({ id, x, z, type: 'junction', districtId: null });
    return id;
  };
  const addEdge = (id, from, to, points, options) => {
    edges.push(edge(id, from, to, points, options));
  };
  const straight = (x1, z1, x2, z2) => [[x1, z1], [(x1 + x2) / 2, (z1 + z2) / 2], [x2, z2]];

  // City grid: verticals run south->north so avenue tangents face north.
  // Two mid-block alleys cut the grid with real junction nodes: a N-S alley
  // at x=70 (z -200..-20) and an E-W alley at z=-65 (x -150..0).
  const grid = CITY_VX.map((col, ix) => CITY_HZ.map((z, iz) => addNode(`n${ix}_${iz}`, col.x, z)));
  const ewAlleyNodes = {};
  CITY_VX.forEach((col, ix) => {
    for (let iz = 0; iz < CITY_HZ.length - 1; iz++) {
      const baseId = col.avenue ? `avenue-${iz}` : `street-v${ix}-${iz}`;
      const opt = { widthM: col.widthM, speedLimitKmh: col.avenue ? 60 : 40 };
      if ((ix === 0 || ix === 1) && iz === 3) {
        const midId = addNode(`am${ix}`, col.x, -65);
        ewAlleyNodes[ix] = midId;
        addEdge(`${baseId}a`, grid[ix][4], midId, straight(col.x, -20, col.x, -65), opt);
        addEdge(`${baseId}b`, midId, grid[ix][3], straight(col.x, -65, col.x, -110), opt);
        continue;
      }
      addEdge(
        baseId,
        grid[ix][iz + 1], grid[ix][iz],
        straight(col.x, CITY_HZ[iz + 1], col.x, CITY_HZ[iz]),
        opt,
      );
    }
  });
  addEdge('alley-h-0', ewAlleyNodes[0], ewAlleyNodes[1], straight(-150, -65, 0, -65), { widthM: 7, speedLimitKmh: 30 });
  const nsAlleyNodes = {};
  CITY_HZ.forEach((z, iz) => {
    for (let ix = 0; ix < CITY_VX.length - 1; ix++) {
      const opt = { widthM: z === -110 ? 12 : 10, speedLimitKmh: 40 };
      if (ix === 1 && iz >= 2 && iz <= 4) {
        const midId = addNode(`ax${iz}`, 70, z);
        nsAlleyNodes[iz] = midId;
        addEdge(`street-h${iz}-1a`, grid[1][iz], midId, straight(0, z, 70, z), opt);
        addEdge(`street-h${iz}-1b`, midId, grid[2][iz], straight(70, z, 140, z), opt);
        continue;
      }
      addEdge(
        `street-h${iz}-${ix}`,
        grid[ix][iz], grid[ix + 1][iz],
        straight(CITY_VX[ix].x, z, CITY_VX[ix + 1].x, z),
        opt,
      );
    }
  });
  addEdge('alley-v-0', nsAlleyNodes[3], nsAlleyNodes[2], straight(70, -110, 70, -200), { widthM: 7, speedLimitKmh: 30 });
  addEdge('alley-v-1', nsAlleyNodes[4], nsAlleyNodes[3], straight(70, -20, 70, -110), { widthM: 7, speedLimitKmh: 30 });

  // Drag strip: avenue continues dead-straight to the north edge.
  const dragNorth = addNode('drag-north', 0, -472);
  addEdge('drag-strip', grid[1][0], dragNorth, straight(0, -380, 0, -472), { widthM: 17, speedLimitKmh: 120 });

  // Roundabout where the avenue meets the highway.
  const RB = REAL_WORLD_ZONES.roundabout;
  const rbNodes = [];
  for (let i = 0; i < 8; i++) {
    const a = (i / 8) * Math.PI * 2;
    rbNodes.push(addNode(`rb-${i}`, RB.x + Math.cos(a) * RB.r, RB.z + Math.sin(a) * RB.r));
  }
  for (let i = 0; i < 8; i++) {
    const a1 = (i / 8) * Math.PI * 2;
    const aM = ((i + 0.5) / 8) * Math.PI * 2;
    const a2 = ((i + 1) / 8) * Math.PI * 2;
    addEdge(`rb-arc-${i}`, rbNodes[i], rbNodes[(i + 1) % 8], [
      [RB.x + Math.cos(a1) * RB.r, RB.z + Math.sin(a1) * RB.r],
      [RB.x + Math.cos(aM) * RB.r, RB.z + Math.sin(aM) * RB.r],
      [RB.x + Math.cos(a2) * RB.r, RB.z + Math.sin(a2) * RB.r],
    ], { widthM: 11, speedLimitKmh: 40 });
  }
  const rbEast = rbNodes[0];   // ( 34, 225)
  const rbSouth = rbNodes[2];  // (  0, 259)
  const rbWest = rbNodes[4];   // (-34, 225)
  const rbNorth = rbNodes[6];  // (  0, 191)

  // Southern grid columns and the avenue plug into the highway/roundabout.
  const hwNode = {};
  [0, 2, 3].forEach((ix) => {
    hwNode[ix] = addNode(`hw${ix}`, CITY_VX[ix].x, HIGHWAY_Z);
    addEdge(`street-s${ix}`, grid[ix][6], hwNode[ix], straight(CITY_VX[ix].x, 150, CITY_VX[ix].x, HIGHWAY_Z), { widthM: 10, speedLimitKmh: 40 });
  });
  addEdge('avenue-rb', grid[1][6], rbNorth, straight(0, 150, 0, RB.z - RB.r), { widthM: 16, speedLimitKmh: 60 });

  // East-west highway through the roundabout.
  const westGate = addNode('west-gate', -472, HIGHWAY_Z);
  const hwRiver = addNode('hw-river', -380, HIGHWAY_Z);
  const hwDrift = addNode('hw-drift', -265, HIGHWAY_Z);
  const hwPark = addNode('hw-park', 360, HIGHWAY_Z);
  const eastGate = addNode('east-gate', 472, HIGHWAY_Z);
  const highwayOpt = { widthM: 15, speedLimitKmh: 90 };
  addEdge('hw-w1', westGate, hwRiver, straight(-472, HIGHWAY_Z, -380, HIGHWAY_Z), highwayOpt);
  addEdge('hw-w2', hwRiver, hwDrift, straight(-380, HIGHWAY_Z, -265, HIGHWAY_Z), highwayOpt);
  addEdge('hw-w3', hwDrift, hwNode[0], straight(-265, HIGHWAY_Z, -150, HIGHWAY_Z), highwayOpt);
  addEdge('hw-w4', hwNode[0], rbWest, straight(-150, HIGHWAY_Z, -RB.r, HIGHWAY_Z), highwayOpt);
  addEdge('hw-e1', rbEast, hwNode[2], straight(RB.r, HIGHWAY_Z, 140, HIGHWAY_Z), highwayOpt);
  addEdge('hw-e2', hwNode[2], hwNode[3], straight(140, HIGHWAY_Z, 250, HIGHWAY_Z), highwayOpt);
  addEdge('hw-e3', hwNode[3], hwPark, straight(250, HIGHWAY_Z, 360, HIGHWAY_Z), highwayOpt);
  addEdge('hw-e4', hwPark, eastGate, straight(360, HIGHWAY_Z, 472, HIGHWAY_Z), highwayOpt);

  // Avenue south + southern commercial street (shop & cafe).
  const southC = addNode('south-st-c', 0, 330);
  const southGate = addNode('south-gate', 0, 472);
  addEdge('avenue-south-1', rbSouth, southC, straight(0, RB.z + RB.r, 0, 330), { widthM: 14, speedLimitKmh: 60 });
  addEdge('avenue-south-2', southC, southGate, straight(0, 330, 0, 472), { widthM: 12, speedLimitKmh: 80 });
  const southW = addNode('south-st-w', -220, 330);
  const southE = addNode('south-st-e', 220, 330);
  addEdge('south-st-1', southW, southC, straight(-220, 330, 0, 330), { widthM: 10, speedLimitKmh: 40 });
  addEdge('south-st-2', southC, southE, straight(0, 330, 220, 330), { widthM: 10, speedLimitKmh: 40 });
  addEdge('se-link', southE, hwNode[3], [[220, 330], [248, 278], [250, HIGHWAY_Z]], { widthM: 9, speedLimitKmh: 50 });
  addEdge('sw-link', southW, hwNode[0], [[-220, 330], [-188, 282], [-150, HIGHWAY_Z]], { widthM: 9, speedLimitKmh: 50 });

  // Riverside road following the river, plus a northern link to the grid.
  const rrZ = [-430, -320, -210, -100, 10, 120];
  const rr = rrZ.map((z, i) => addNode(`rr-${i}`, Math.round(riverCenterX(z) + 42), z));
  for (let i = 0; i < rr.length - 1; i++) {
    const z1 = rrZ[i];
    const z2 = rrZ[i + 1];
    const zm = (z1 + z2) / 2;
    addEdge(`river-road-${i}`, rr[i], rr[i + 1], [
      [Math.round(riverCenterX(z1) + 42), z1],
      [Math.round(riverCenterX(zm) + 42), zm],
      [Math.round(riverCenterX(z2) + 42), z2],
    ], { roadClass: 'B', widthM: 8, speedLimitKmh: 60 });
  }
  addEdge('river-bridge', rr[rr.length - 1], hwRiver, [
    [Math.round(riverCenterX(120) + 42), 120],
    [Math.round(riverCenterX(175) + 30), 175],
    [-380, HIGHWAY_Z],
  ], { roadClass: 'B', widthM: 8, speedLimitKmh: 50 });
  addEdge('north-link', rr[0], grid[0][0], [
    [Math.round(riverCenterX(-430) + 42), -430],
    [-235, -420],
    [-150, -380],
  ], { roadClass: 'B', widthM: 8.5, speedLimitKmh: 60 });

  // Drift zone: closed peanut circuit in the south-west.
  const driftPts = [
    [-360, 275], [-285, 252], [-205, 282], [-200, 362],
    [-262, 422], [-345, 415], [-385, 345],
  ];
  const driftNodes = driftPts.map(([x, z], i) => addNode(`drift-${i}`, x, z));
  const DC = REAL_WORLD_ZONES.drift;
  for (let i = 0; i < driftPts.length; i++) {
    const [x1, z1] = driftPts[i];
    const [x2, z2] = driftPts[(i + 1) % driftPts.length];
    const mx = (x1 + x2) / 2;
    const mz = (z1 + z2) / 2;
    const ox = mx - DC.x;
    const oz = mz - DC.z;
    const olen = Math.hypot(ox, oz) || 1;
    addEdge(`drift-loop-${i}`, driftNodes[i], driftNodes[(i + 1) % driftPts.length], [
      [x1, z1],
      [mx + (ox / olen) * 13, mz + (oz / olen) * 13],
      [x2, z2],
    ], { widthM: 11, speedLimitKmh: 70 });
  }
  addEdge('drift-entry', driftNodes[2], hwDrift, [[-205, 282], [-238, 252], [-265, HIGHWAY_Z]], { widthM: 8, speedLimitKmh: 50 });
  addEdge('drift-west-entry', driftNodes[0], hwRiver, [[-360, 275], [-374, 250], [-380, HIGHWAY_Z]], { widthM: 8, speedLimitKmh: 50 });

  // Festival plaza and parking entries.
  const plazaGate = addNode('plaza-gate', 345, -110);
  addEdge('plaza-entry', grid[3][3], plazaGate, straight(250, -110, 345, -110), { widthM: 10, speedLimitKmh: 30 });
  const parkingGate = addNode('parking-gate', 335, 70);
  addEdge('parking-entry', grid[3][5], parkingGate, straight(250, 70, 335, 70), { widthM: 10, speedLimitKmh: 30 });
  const parking2Gate = addNode('parking2-gate', 340, -290);
  addEdge('parking2-entry', grid[3][1], parking2Gate, straight(250, -290, 340, -290), { widthM: 10, speedLimitKmh: 30 });

  // --- RichTown (v0.16): sea-to-inland zoning east of the old rim -------------
  // Shore highway (Corniche, x=930) -> boulevard (760) -> west frontage
  // (560). The marina inlet opens to the sea; the Corniche crosses it on a
  // land bridge. Causeways lead east to Sail Island (z=80) and Palm Island
  // (z=-250).
  const RT_Z = [-430, -300, -250, -110, 60, HIGHWAY_Z, 430];
  const rtW = RT_Z.map((z, i) => addNode(`rt-w${i}`, 560, z));
  const rtB = RT_Z.map((z, i) => addNode(`rt-b${i}`, 760, z));
  const rtE = RT_Z.map((z, i) => addNode(`rt-e${i}`, 930, z));
  const rtStreet = { widthM: 13, speedLimitKmh: 50 };
  const corniche = { widthM: 24, lanes: 4, speedLimitKmh: 80, name: 'RichTown Corniche' };
  let sailJunction = null;
  for (let i = 0; i < RT_Z.length - 1; i++) {
    addEdge(`rt-blvd-${i}`, rtB[i], rtB[i + 1], straight(760, RT_Z[i], 760, RT_Z[i + 1]), { widthM: 22, lanes: 4, speedLimitKmh: 70, name: 'RichTown Boulevard' });
    addEdge(`rt-west-${i}`, rtW[i], rtW[i + 1], straight(560, RT_Z[i], 560, RT_Z[i + 1]), { widthM: 11, speedLimitKmh: 50 });
    if (RT_Z[i] === 60) {
      sailJunction = addNode('rt-sail-j', 930, 80);
      addEdge(`rt-east-${i}a`, rtE[i], sailJunction, straight(930, 60, 930, 80), corniche);
      addEdge(`rt-east-${i}b`, sailJunction, rtE[i + 1], straight(930, 80, 930, RT_Z[i + 1]), corniche);
    } else {
      addEdge(`rt-east-${i}`, rtE[i], rtE[i + 1], straight(930, RT_Z[i], 930, RT_Z[i + 1]), corniche);
    }
  }
  RT_Z.forEach((z, i) => {
    if (z === HIGHWAY_Z) return;
    addEdge(`rt-st-${i}w`, rtW[i], rtB[i], straight(560, z, 760, z), rtStreet);
    addEdge(`rt-st-${i}e`, rtB[i], rtE[i], straight(760, z, 930, z), rtStreet);
  });
  addEdge('rt-highway-1', eastGate, rtW[5], straight(472, HIGHWAY_Z, 560, HIGHWAY_Z), { widthM: 15, speedLimitKmh: 90 });
  addEdge('rt-highway-2', rtW[5], rtB[5], straight(560, HIGHWAY_Z, 760, HIGHWAY_Z), { widthM: 16, speedLimitKmh: 70 });
  addEdge('rt-link-plaza', plazaGate, rtW[3], straight(345, -110, 560, -110), { widthM: 11, speedLimitKmh: 40 });
  addEdge('rt-link-south', southE, rtW[6], [[220, 330], [380, 395], [560, 430]], { widthM: 10, speedLimitKmh: 60 });
  const palmMid = addNode('rt-palm-mid', 1150, -250);
  const palmTrunk = addNode('rt-palm-trunk', 1330, -250);
  const palmCrown = addNode('rt-palm-crown', 1395, -250);
  addEdge('rt-palm-1', rtE[2], palmMid, straight(930, -250, 1150, -250), { widthM: 13, speedLimitKmh: 60, name: 'Palm Island Bridge' });
  addEdge('rt-palm-2', palmMid, palmTrunk, straight(1150, -250, 1330, -250), { widthM: 12, speedLimitKmh: 50 });
  addEdge('rt-palm-3', palmTrunk, palmCrown, straight(1330, -250, 1395, -250), { widthM: 11, speedLimitKmh: 40 });
  const palmN = addNode('rt-palm-n', 1395, -345);
  const palmS = addNode('rt-palm-s', 1395, -155);
  addEdge('rt-palm-frond-n', palmCrown, palmN, [[1395, -250], [1412, -300], [1395, -345]], { widthM: 9, speedLimitKmh: 40 });
  addEdge('rt-palm-frond-s', palmCrown, palmS, [[1395, -250], [1412, -200], [1395, -155]], { widthM: 9, speedLimitKmh: 40 });
  const sailEnd = addNode('rt-sail-end', 1180, 80);
  addEdge('rt-sail-road', sailJunction, sailEnd, straight(930, 80, 1180, 80), { widthM: 10, speedLimitKmh: 50, name: 'Sail Island Causeway' });

  return { id: 'real-valley-roads', version: REAL_WORLD_VERSION, nodes, edges };
}

function movingAverageByDistance(samples, values, radiusM) {
  return samples.map((sample, i) => {
    let sum = 0;
    let count = 0;
    for (let k = 0; k < samples.length; k++) {
      if (Math.abs(samples[k].s - sample.s) <= radiusM) {
        sum += values[k];
        count++;
      }
    }
    return count ? sum / count : values[i];
  });
}

function clampGradesPinned(samples, values, maxGrade = 0.16) {
  if (values.length < 2) return values.slice();
  const out = values.slice();
  const start = out[0];
  const end = out[out.length - 1];
  // Alternating Lipschitz sweeps need many passes when a pinned junction
  // sits next to a steep hillside profile; stop as soon as every segment
  // satisfies the grade limit (same strategy as the large world).
  for (let iter = 0; iter < 64; iter++) {
    out[0] = start;
    for (let i = 1; i < out.length; i++) {
      const ds = Math.max(samples[i].s - samples[i - 1].s, 0.5);
      const maxDelta = maxGrade * ds;
      out[i] = clamp(out[i], out[i - 1] - maxDelta, out[i - 1] + maxDelta);
    }
    out[out.length - 1] = end;
    for (let i = out.length - 2; i >= 0; i--) {
      const ds = Math.max(samples[i + 1].s - samples[i].s, 0.5);
      const maxDelta = maxGrade * ds;
      out[i] = clamp(out[i], out[i + 1] - maxDelta, out[i + 1] + maxDelta);
    }
    out[0] = start;
    out[out.length - 1] = end;
    let ok = true;
    for (let i = 1; i < out.length; i++) {
      const ds = Math.max(samples[i].s - samples[i - 1].s, 0.5);
      if (Math.abs(out[i] - out[i - 1]) > maxGrade * ds + 1e-6) { ok = false; break; }
    }
    if (ok) break;
  }
  return out;
}

function smoothEdgeHeights(graph, rawHeightAt) {
  const profiles = new Map();
  for (const e of graph.edges) {
    const raw = e.samples.map((s) => rawHeightAt(s.x, s.z));
    let values = movingAverageByDistance(e.samples, raw, 28);
    values = movingAverageByDistance(e.samples, values, 28);
    values[0] = raw[0];
    values[values.length - 1] = raw[raw.length - 1];
    profiles.set(e.id, clampGradesPinned(e.samples, values));
  }
  // Average shared junction elevations, blend them in and clamp again so
  // stitched edges cannot reopen a seam at a junction.
  const endpointValues = new Map();
  for (const e of graph.edges) {
    const values = profiles.get(e.id);
    for (const [nodeId, value] of [[e.from, values[0]], [e.to, values[values.length - 1]]]) {
      const list = endpointValues.get(nodeId) || [];
      list.push(value);
      endpointValues.set(nodeId, list);
    }
  }
  const nodeElevation = new Map(
    [...endpointValues.entries()].map(([id, list]) => [id, list.reduce((a, b) => a + b, 0) / list.length]),
  );
  for (const e of graph.edges) {
    const startY = nodeElevation.get(e.from);
    const endY = nodeElevation.get(e.to);
    const blendM = Math.min(55, e.lengthM * 0.45);
    let values = profiles.get(e.id).map((value, i) => {
      const s = e.samples[i].s;
      let next = value;
      const fromStart = smoothstep(0, blendM, s);
      const fromEnd = smoothstep(0, blendM, e.lengthM - s);
      if (fromStart < 1) next = lerp(startY, next, fromStart);
      if (fromEnd < 1) next = lerp(endY, next, fromEnd);
      return next;
    });
    values[0] = startY;
    values[values.length - 1] = endY;
    values = clampGradesPinned(e.samples, values);
    e.samples.forEach((s, i) => { s.y = values[i]; });
  }
}

function districtAt(x, z) {
  let best = null;
  for (const d of REAL_WORLD_DISTRICTS) {
    const distanceM = Math.hypot(x - d.x, z - d.z);
    const normalizedDistance = distanceM / d.radiusM;
    if (normalizedDistance <= 1 && (!best || normalizedDistance < best.normalizedDistance)) {
      best = { ...d, distanceM, normalizedDistance };
    }
  }
  return best;
}

function slopeApprox(heightAt, x, z) {
  const e = 5;
  const dx = (heightAt(x + e, z) - heightAt(x - e, z)) / (2 * e);
  const dz = (heightAt(x, z + e) - heightAt(x, z - e)) / (2 * e);
  return Math.hypot(dx, dz);
}

function sampleFrame(edgeSamples, index) {
  const a = edgeSamples[Math.max(0, index - 1)];
  const b = edgeSamples[Math.min(edgeSamples.length - 1, index + 1)];
  const tx = b.x - a.x;
  const tz = b.z - a.z;
  const len = Math.hypot(tx, tz) || 1;
  const tangent = { x: tx / len, z: tz / len };
  return { tangent, normal: { x: -tangent.z, z: tangent.x }, yaw: Math.atan2(tangent.x, tangent.z) };
}

const FESTIVAL_COLORS = [0xf2f2f2, 0x2f7fe0, 0xf5c518, 0xe0409a, 0x35c4b5];

function planDressing(core, seed) {
  const rng = mulberry32(seed ^ 0x5EED);
  const plan = {
    buildings: [], trees: [], bushes: [], rocks: [], lamps: [], colliders: [],
    busStops: [], benches: [], hedges: [],
    signs: [], bins: [], bollards: [], fences: [], powerPoles: [],
    palms: [], landmarks: [], pools: [],
    pavedAreas: [
      { ...REAL_WORLD_ZONES.plaza, kind: 'plaza' },
      ...REAL_WORLD_ZONES.parkings.map((r) => ({ ...r, kind: 'parking' })),
      { ...REAL_WORLD_ZONES.rtPlaza, kind: 'promenade' },
    ],
    roundabout: { ...REAL_WORLD_ZONES.roundabout },
    festival: { stage: null, tents: [], banners: [] },
  };
  const addCollider = (record) => plan.colliders.push({ id: `real-${plan.colliders.length}`, ...record });
  const overlapsBuilding = (x, z, pad) => plan.buildings.some(
    (b) => Math.hypot(x - b.x, z - b.z) < Math.max(b.w, b.d) * 0.62 + pad,
  );
  const pushBuilding = (b) => {
    plan.buildings.push(b);
    addCollider({ kind: 'obb', x: b.x, z: b.z, halfWidthM: b.w / 2, halfDepthM: b.d / 2, rotationY: b.rotY });
  };

  // --- City blocks: dense axis-aligned buildings between the streets -------
  const colHalf = CITY_VX.map((c) => c.widthM / 2);
  for (let ix = 0; ix < CITY_VX.length - 1; ix++) {
    for (let iz = 0; iz < CITY_HZ.length - 1; iz++) {
      const x0 = CITY_VX[ix].x + colHalf[ix] + 8;
      const x1 = CITY_VX[ix + 1].x - colHalf[ix + 1] - 8;
      const z0 = CITY_HZ[iz] + 12;
      const z1 = CITY_HZ[iz + 1] - 12;
      const cols = Math.max(1, Math.floor((x1 - x0) / 28));
      const rows = Math.max(1, Math.floor((z1 - z0) / 26));
      const cellW = (x1 - x0) / cols;
      const cellD = (z1 - z0) / rows;
      for (let cx = 0; cx < cols; cx++) {
        for (let cz = 0; cz < rows; cz++) {
          if (plan.buildings.length >= 230) break;
          if (rng() < 0.18) continue; // courtyard gap
          const px = x0 + cellW * (cx + 0.5) + (rng() - 0.5) * 3;
          const pz = z0 + cellD * (cz + 0.5) + (rng() - 0.5) * 3;
          const distCentre = Math.hypot(px, pz + 110);
          const kind = distCentre < 150
            ? 'apartment'
            : distCentre < 280
              ? (rng() < 0.6 ? 'apartment' : 'townhouse')
              : (rng() < 0.55 ? 'townhouse' : 'house');
          const w = clamp(cellW * (0.55 + rng() * 0.25), 10, 30);
          const d = clamp(cellD * (0.55 + rng() * 0.25), 9, 28);
          const h = kind === 'apartment'
            ? (distCentre < 150 ? 15 + rng() * 17 : 10 + rng() * 10)
            : kind === 'townhouse' ? 7 + rng() * 4 : 4.6 + rng() * 2.2;
          const roofH = kind === 'apartment' ? 0 : (rng() < 0.55 ? 2 + rng() * 1.6 : 0);
          const facadePool = kind === 'apartment'
            ? ['modern', 'glass', 'brick', 'panel', 'loft', 'pastel']
            : ['brick', 'panel', 'pastel'];
          const facade = facadePool[Math.floor(rng() * facadePool.length)];
          const py = core.heightAt(px, pz);
          if (py < 0.8 || slopeApprox(core.heightAt, px, pz) > 0.3) continue;
          const near = core.nearestRoad(px, pz, { maxDistanceM: 40 });
          if (near && near.edgeDistanceM < 4.5) continue;
          pushBuilding({
            x: px, z: pz, y: py - 0.25, rotY: 0, w, d, h, roofH, kind, facade,
            tint: 0.82 + rng() * 0.36,
          });
        }
      }
    }
  }

  // --- Landmarks: car shop and cafe on the southern street ------------------
  const shopY = core.heightAt(-118, 298);
  pushBuilding({
    x: -118, z: 298, y: shopY - 0.25, rotY: 0, w: 48, d: 24, h: 9, roofH: 0,
    kind: 'shop', facade: 'shop', tint: 1,
  });
  const cafeY = core.heightAt(112, 303);
  pushBuilding({
    x: 112, z: 303, y: cafeY - 0.25, rotY: 0, w: 26, d: 16, h: 6.5, roofH: 0,
    kind: 'cafe', facade: 'shop', tint: 1,
  });
  // Two light-industrial warehouses south of the highway, gates facing it.
  for (const wx of [180, 335]) {
    pushBuilding({
      x: wx, z: 264, y: core.heightAt(wx, 264) - 0.25, rotY: Math.PI, w: 38, d: 20, h: 8, roofH: 0,
      kind: 'warehouse', facade: 'industrial', tint: 0.95,
    });
  }

  // --- RichTown: skyscraper blocks, landmarks, palms, fountain plaza ---------
  {
    const RT_COLS_X = [560, 760, 930];
    const RT_ROWS_Z = [-430, -300, -250, -110, 60, 225, 430];
    const pushPool = (x, z, w = 11, d = 5.5) => {
      plan.pools.push({ x, z, y: core.heightAt(x, z) + 0.02, w, d, rotY: 0 });
      addCollider({ kind: 'obb', x, z, halfWidthM: w / 2, halfDepthM: d / 2, rotationY: 0 });
    };
    const landmarkPlots = [
      [665, -340, 40], [820, 25, 34], [620, 335, 44], [812, 118, 34],
      [812, 412, 34], [872, 118, 32], [712, 150, 36], [868, -330, 40],
    ];
    // Mall and the five shore hotels go in first so the block generator
    // keeps their plots clear. Each hotel gets its own facade.
    pushBuilding({
      x: 628, z: 150, y: core.heightAt(628, 150) - 0.3, rotY: 0, w: 84, d: 56, h: 16, roofH: 0,
      kind: 'rt-mall', facade: 'userMarble', tint: 1,
    });
    const shoreHotels = [
      [892, -385, 42, 'glassTower'], [892, -185, 54, 'goldTower'], [892, -35, 38, 'hotelTower'],
      [892, 105, 46, 'marbleTower'], [892, 415, 34, 'sandTower'],
    ];
    for (const [hx, hz, hh, hf] of shoreHotels) {
      pushBuilding({
        x: hx, z: hz, y: core.heightAt(hx, hz) - 0.3, rotY: -Math.PI / 2, w: 34, d: 26, h: hh, roofH: 0,
        kind: 'rt-hotel', facade: hf, tint: 0.95 + rng() * 0.15,
      });
    }
    const towerFacades = ['glassTower', 'goldTower', 'marbleTower'];
    const hotelFacades = ['hotelTower', 'glassTower', 'marbleTower', 'sandTower'];
    const midFacades = ['sandTower', 'marbleTower', 'hotelTower', 'glassTower'];
    for (let ix = 0; ix < RT_COLS_X.length - 1; ix++) {
      for (let iz = 0; iz < RT_ROWS_Z.length - 1; iz++) {
        const x0 = RT_COLS_X[ix] + 22;
        const x1 = RT_COLS_X[ix + 1] - 22;
        const z0 = RT_ROWS_Z[iz] + 20;
        const z1 = RT_ROWS_Z[iz + 1] - 20;
        const cols = Math.max(1, Math.floor((x1 - x0) / 40));
        const rows = Math.max(1, Math.floor((z1 - z0) / 40));
        const cellW = (x1 - x0) / cols;
        const cellD = (z1 - z0) / rows;
        for (let cx = 0; cx < cols; cx++) {
          for (let cz = 0; cz < rows; cz++) {
            const px = x0 + cellW * (cx + 0.5) + (rng() - 0.5) * 4;
            const pz = z0 + cellD * (cz + 0.5) + (rng() - 0.5) * 4;
            if (inRect(px, pz, REAL_WORLD_ZONES.marina, 26)) continue;
            if (inRect(px, pz, REAL_WORLD_ZONES.rtPlaza, 14)) continue;
            if (Math.hypot(px - 665, pz + 170) < 46) continue; // landmark tower plot
            if (landmarkPlots.some(([lx, lz, lr]) => Math.hypot(px - lx, pz - lz) < lr)) continue;
            if (rng() < 0.08) continue; // open plot / plaza gap
            const py = core.heightAt(px, pz);
            if (py < 0.8 || slopeApprox(core.heightAt, px, pz) > 0.25) continue;
            const near = core.nearestRoad(px, pz, { maxDistanceM: 40 });
            if (near && near.edgeDistanceM < 5) continue;
            // Residential zoning: villas with pools south-west and far north,
            // towers/hotels in the downtown-business-marina core.
            const villaZone = (pz > 240 && px < 745) || pz < -320;
            if (villaZone) {
              const w = 16 + rng() * 10;
              const d = 12 + rng() * 7;
              if (overlapsBuilding(px, pz, Math.max(w, d) * 0.5)) continue;
              pushBuilding({
                x: px, z: pz, y: py - 0.25, rotY: 0, w, d, h: 5.5 + rng() * 3.5,
                roofH: 2.2 + rng() * 1.2, kind: 'rt-villa',
                facade: ['userPlaster', 'userStone', 'userWood'][Math.floor(rng() * 3)],
                tint: 0.92 + rng() * 0.2,
              });
              if (rng() < 0.65) pushPool(px + w / 2 + 8, pz, 10 + rng() * 3, 5 + rng() * 1.5);
              continue;
            }
            const distCore = Math.hypot(px - 760, pz - 60);
            const kind = distCore < 270 ? 'rt-tower' : distCore < 430 ? 'rt-hotel' : 'rt-mid';
            const h = kind === 'rt-tower' ? 42 + rng() * 63
              : kind === 'rt-hotel' ? 22 + rng() * 33 : 10 + rng() * 16;
            const pool = kind === 'rt-tower' ? towerFacades : kind === 'rt-hotel' ? hotelFacades : midFacades;
            const w = clamp(cellW * (0.5 + rng() * 0.22), 18, 40);
            const d = clamp(cellD * (0.5 + rng() * 0.22), 18, 40);
            if (overlapsBuilding(px, pz, Math.max(w, d) * 0.4)) continue;
            pushBuilding({
              x: px, z: pz, y: py - 0.3, rotY: rng() < 0.12 ? Math.PI / 4 : 0,
              w, d, h, roofH: 0, kind,
              facade: pool[Math.floor(rng() * pool.length)],
              tint: 0.88 + rng() * 0.28,
            });
          }
        }
      }
    }

    // Palm Island: villas on the frond lobes + the Atlantis hotel at the tip.
    const palmVillaSpots = [
      [1348, -352], [1424, -304], [1440, -222], [1424, -176], [1343, -122], [1285, -270], [1285, -230],
    ];
    palmVillaSpots.forEach(([vx, vz], i) => {
      pushBuilding({
        x: vx, z: vz, y: core.heightAt(vx, vz) - 0.25, rotY: 0, w: 20, d: 14, h: 7, roofH: 2.6,
        kind: 'rt-villa', facade: i % 2 ? 'userStone' : 'userPlaster', tint: 1,
      });
      pushPool(vx, vz + 14, 11, 5.5);
    });
    pushBuilding({
      x: 1448, z: -250, y: core.heightAt(1448, -250) - 0.3, rotY: Math.PI / 2, w: 54, d: 28, h: 34, roofH: 0,
      kind: 'rt-hotel', facade: 'goldTower', tint: 1,
    });

    // Landmarks are rendered bespoke by the scene; here only data + colliders.
    plan.landmarks.push({ kind: 'rt-tower', x: 665, z: -170, y: core.heightAt(665, -170) - 0.3, h: 148 });
    addCollider({ kind: 'obb', x: 665, z: -170, halfWidthM: 24, halfDepthM: 24, rotationY: 0 });
    plan.landmarks.push({ kind: 'rt-arch', x: 760, z: 60, y: core.heightAt(760, 60), h: 43 });
    for (const px of [745, 775]) {
      addCollider({ kind: 'obb', x: px, z: 60, halfWidthM: 2.4, halfDepthM: 3.2, rotationY: 0 });
    }
    plan.landmarks.push({ kind: 'rt-fountain', x: 665, z: -25, y: core.heightAt(665, -25), r: 16 });
    addCollider({ kind: 'circle', x: 665, z: -25, r: 16.8 });
    const addLandmark = (kind, x, z, extra, col) => {
      plan.landmarks.push({ kind, x, z, y: core.heightAt(x, z) - 0.1, ...extra });
      if (col) addCollider(col);
    };
    addLandmark('rt-sail', 1180, 80, { h: 95 }, { kind: 'obb', x: 1180, z: 80, halfWidthM: 20, halfDepthM: 14, rotationY: 0 });
    addLandmark('rt-museum', 665, -340, { h: 26 }, { kind: 'circle', x: 665, z: -340, r: 24 });
    addLandmark('rt-opera', 820, 25, { h: 22 }, { kind: 'obb', x: 820, z: 25, halfWidthM: 26, halfDepthM: 20, rotationY: 0 });
    addLandmark('rt-mosque', 620, 335, { h: 30 }, { kind: 'obb', x: 620, z: 335, halfWidthM: 24, halfDepthM: 24, rotationY: 0 });
    addLandmark('rt-twist', 812, 118, { h: 105 }, { kind: 'obb', x: 812, z: 118, halfWidthM: 15, halfDepthM: 15, rotationY: 0 });
    addLandmark('rt-lean', 812, 412, { h: 88 }, { kind: 'obb', x: 812, z: 412, halfWidthM: 15, halfDepthM: 15, rotationY: 0 });
    addLandmark('rt-hole', 872, 118, { h: 78 }, { kind: 'obb', x: 872, z: 118, halfWidthM: 18, halfDepthM: 14, rotationY: 0 });
    addLandmark('rt-parking', 712, 150, { h: 15 }, { kind: 'obb', x: 712, z: 150, halfWidthM: 20, halfDepthM: 26, rotationY: 0 });
    addLandmark('rt-aquapark', 868, -330, { r: 26 }, { kind: 'circle', x: 868, z: -330, r: 27 });
    for (const lz of [-180, -20, 115]) {
      addLandmark('rt-lifeguard', 985, lz, { h: 6 }, { kind: 'circle', x: 985, z: lz, r: 2.2 });
    }

    // Palms: boulevard sidewalks, marina promenade, fountain ring.
    const pushPalm = (x, z) => {
      plan.palms.push({ x, z, y: core.heightAt(x, z) - 0.05, rotY: rng() * Math.PI * 2, s: 0.9 + rng() * 0.35 });
      addCollider({ kind: 'circle', x, z, r: 0.35 });
    };
    for (let z = -415; z <= 415; z += 21) {
      if (RT_ROWS_Z.some((rz) => Math.abs(z - rz) < 13)) continue;
      pushPalm(745.5, z);
      pushPalm(774.5, z + 10);
    }
    for (let z = -420; z <= 420; z += 28) {
      if (RT_ROWS_Z.some((rz) => Math.abs(z - rz) < 12)) continue;
      pushPalm(946, z);
    }
    for (const [vx, vz] of palmVillaSpots) {
      pushPalm(vx - 14, vz + 10);
      pushPalm(vx + 14, vz - 10);
    }
    pushPalm(1160, 58);
    pushPalm(1202, 102);
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * Math.PI * 2 + 0.39;
      pushPalm(665 + Math.cos(a) * 26, -25 + Math.sin(a) * 26);
    }

    // Fountain-plaza furniture: benches, bins, bollards, hedge.
    for (let i = 0; i < 6; i++) {
      const a = (i / 6) * Math.PI * 2 + 0.2;
      const bx = 665 + Math.cos(a) * 21;
      const bz = -25 + Math.sin(a) * 21;
      plan.benches.push({ x: bx, z: bz, y: core.heightAt(bx, bz), rotY: Math.atan2(-Math.cos(a), -Math.sin(a)) });
      addCollider({ kind: 'circle', x: bx, z: bz, r: 0.85 });
      if (i % 2 === 0) {
        const nx = bx + 2.2;
        const nz = bz + 0.6;
        plan.bins.push({ x: nx, z: nz, y: core.heightAt(nx, nz), rotY: rng() * Math.PI });
        addCollider({ kind: 'circle', x: nx, z: nz, r: 0.34 });
      }
    }
    for (let z = -80; z <= 30; z += 11) {
      plan.bollards.push({ x: 736, z, y: core.heightAt(736, z) });
      addCollider({ kind: 'circle', x: 736, z, r: 0.2 });
    }
    for (let x = 606; x <= 724; x += 11) {
      plan.hedges.push({ x, z: 46, y: core.heightAt(x, 46), rotY: 0, w: 10.4 });
      addCollider({ kind: 'obb', x, z: 46, halfWidthM: 5.2, halfDepthM: 0.65, rotationY: 0 });
    }
    // District gateway signs.
    const rtSign = (x, z, rotY, text) => {
      plan.signs.push({ x, z, y: core.heightAt(x, z), rotY, type: 'text', text });
      addCollider({ kind: 'circle', x, z, r: 0.22 });
    };
    rtSign(505, 242, -Math.PI / 2, 'RICHTOWN');
    rtSign(748, 412, Math.PI, 'RICHTOWN');
    rtSign(832, 72, -Math.PI / 2, 'MARINA');
    rtSign(914, -236, -Math.PI / 2, 'PALM ISLAND');
    rtSign(914, 96, -Math.PI / 2, 'BEACH');
  }

  // --- Sparse houses along the riverside road and southern links ------------
  const rural = /^(river-road|north-link|south-st|sw-link|se-link)/;
  for (const e of core.roadGraph.edges) {
    if (plan.buildings.length >= 400) break;
    if (!rural.test(e.id)) continue;
    for (let i = 3; i < e.samples.length - 3; i++) {
      const sample = e.samples[i];
      if (sample.s % 34 > 5 || rng() > 0.4) continue;
      const frame = sampleFrame(e.samples, i);
      const side = rng() < 0.5 ? -1 : 1;
      const dims = { w: 8 + rng() * 5, d: 7 + rng() * 4, h: 4.6 + rng() * 2.4, roofH: 2 + rng() * 1.6 };
      const offset = e.halfWidthM + Math.max(dims.w, dims.d) * 0.42 + 5 + rng() * 6;
      const px = sample.x + frame.normal.x * side * offset;
      const pz = sample.z + frame.normal.z * side * offset;
      if (Math.abs(px) > 468 || Math.abs(pz) > 468) continue;
      if (Math.abs(px - riverCenterX(pz)) < 34) continue;
      if (Math.hypot(px + 118, pz - 298) < 40 || Math.hypot(px - 112, pz - 303) < 30) continue;
      if (plan.pavedAreas.some((r) => inRect(px, pz, r, 6))) continue;
      const py = core.heightAt(px, pz);
      if (py < 0.9 || slopeApprox(core.heightAt, px, pz) > 0.3) continue;
      const near = core.nearestRoad(px, pz, { maxDistanceM: 40 });
      if (near && near.edgeDistanceM < 5.5) continue;
      if (overlapsBuilding(px, pz, Math.max(dims.w, dims.d) * 0.55)) continue;
      const rotY = Math.atan2(-frame.normal.x * side, -frame.normal.z * side);
      pushBuilding({
        x: px, z: pz, y: py - 0.25, rotY, ...dims, kind: 'house',
        facade: ['brick', 'panel', 'loft'][Math.floor(rng() * 3)], tint: 0.82 + rng() * 0.36,
      });
    }
  }

  // --- Festival plaza: stage, tents, banner poles ----------------------------
  const stage = { x: 405, z: -250, y: 0, w: 54, d: 16, h: 11, rotY: 0 };
  stage.y = core.heightAt(stage.x, stage.z);
  plan.festival.stage = stage;
  addCollider({ kind: 'obb', x: stage.x, z: stage.z, halfWidthM: stage.w / 2, halfDepthM: stage.d / 2, rotationY: 0 });
  const tentSpots = [
    [315, -240], [315, -203], [315, -166], [315, -129], [315, -92],
    [459, -228], [459, -184], [459, -140], [459, -96],
    [352, -262], [448, -262],
  ];
  tentSpots.forEach(([x, z], i) => {
    const s = 0.9 + rng() * 0.35;
    plan.festival.tents.push({
      x, z, y: core.heightAt(x, z), rotY: (rng() - 0.5) * 0.6, s,
      color: FESTIVAL_COLORS[i % FESTIVAL_COLORS.length],
    });
    addCollider({ kind: 'circle', x, z, r: 3.4 * s });
  });
  for (let i = 0; i < 6; i++) {
    const x = 322 + i * 27;
    const z = -58;
    plan.festival.banners.push({
      x, z, y: core.heightAt(x, z), rotY: 0,
      color: FESTIVAL_COLORS[(i + 1) % FESTIVAL_COLORS.length],
    });
    addCollider({ kind: 'circle', x, z, r: 0.3 });
  }

  // --- Roundabout island collider ---------------------------------------------
  addCollider({ kind: 'circle', x: plan.roundabout.x, z: plan.roundabout.z, r: 24 });

  // --- Lamps along lit streets --------------------------------------------------
  const lit = /^(street-|avenue|hw-|drag-|south-|rb-arc|plaza-entry|parking-entry|rt-)/;
  for (const e of core.roadGraph.edges) {
    if (!lit.test(e.id)) continue;
    for (let i = 3; i < e.samples.length - 3; i++) {
      const sample = e.samples[i];
      if (sample.s % 44 > 5) continue;
      const frame = sampleFrame(e.samples, i);
      const side = Math.floor(sample.s / 44) % 2 === 0 ? 1 : -1;
      const px = sample.x + frame.normal.x * side * (e.halfWidthM + 1.4);
      const pz = sample.z + frame.normal.z * side * (e.halfWidthM + 1.4);
      if (Math.hypot(px - plan.roundabout.x, pz - plan.roundabout.z) < 30) continue;
      // rotY faces the road so the modelled arm reaches over the asphalt.
      plan.lamps.push({
        x: px, z: pz, y: core.heightAt(px, pz),
        rotY: Math.atan2(-frame.normal.x * side, -frame.normal.z * side),
        side,
      });
      addCollider({ kind: 'circle', x: px, z: pz, r: 0.3 });
    }
  }

  // --- Bus stops along the avenue, highway and southern street ------------------
  const busEdges = /^(avenue-\d|avenue-rb|avenue-south|hw-|south-st|rt-blvd|rt-highway)/;
  for (const e of core.roadGraph.edges) {
    if (plan.busStops.length >= 26) break;
    if (!busEdges.test(e.id)) continue;
    for (let i = 4; i < e.samples.length - 4; i++) {
      const sample = e.samples[i];
      const sMod = sample.s % 80;
      if (sMod < 36 || sMod > 41) continue;
      const frame = sampleFrame(e.samples, i);
      const side = plan.busStops.length % 2 === 0 ? 1 : -1;
      const px = sample.x + frame.normal.x * side * (e.halfWidthM + 4.4);
      const pz = sample.z + frame.normal.z * side * (e.halfWidthM + 4.4);
      if (Math.abs(px) > 470 || Math.abs(pz) > 470) continue;
      if (Math.hypot(px - plan.roundabout.x, pz - plan.roundabout.z) < 46) continue;
      // Sidewalk shelters sit close to facades; reject only real overlaps.
      if (plan.buildings.some((b) => Math.hypot(b.x - px, b.z - pz) < Math.max(b.w, b.d) * 0.5 + 3.5)) continue;
      if (plan.busStops.some((b) => Math.hypot(b.x - px, b.z - pz) < 40)) continue;
      const rotY = Math.atan2(-frame.normal.x * side, -frame.normal.z * side);
      plan.busStops.push({ x: px, z: pz, y: core.heightAt(px, pz), rotY });
      // Shelter posts as colliders in local frame corners.
      const fx = Math.sin(rotY);
      const fz = Math.cos(rotY);
      const rxv = fz;
      const rzv = -fx;
      for (const lx of [-2.3, 2.3]) {
        addCollider({ kind: 'circle', x: px + rxv * lx - fx * 0.8, z: pz + rzv * lx - fz * 0.8, r: 0.28 });
      }
    }
  }

  // --- Benches: plaza edges and the roundabout island -----------------------------
  const pushBench = (x, z, rotY, lift = 0) => {
    plan.benches.push({ x, z, y: core.heightAt(x, z) + lift, rotY });
    addCollider({ kind: 'circle', x, z, r: 0.85 });
  };
  for (let x = 322; x <= 462; x += 28) pushBench(x, -62, Math.PI);
  for (let z = -238; z <= -80; z += 40) pushBench(306, z, Math.PI / 2);
  for (let i = 0; i < 4; i++) {
    const a = (i / 4) * Math.PI * 2 + 0.4;
    pushBench(
      plan.roundabout.x + Math.cos(a) * 17,
      plan.roundabout.z + Math.sin(a) * 17,
      Math.atan2(-Math.cos(a), -Math.sin(a)),
      0.38,
    );
  }
  pushBench(-70, 318, 0);
  pushBench(70, 318, 0);

  // --- Trimmed hedges along the plaza and main parking ----------------------------
  const pushHedge = (x, z) => {
    plan.hedges.push({ x, z, y: core.heightAt(x, z), rotY: 0, w: 10.4 });
    addCollider({ kind: 'obb', x, z, halfWidthM: 5.2, halfDepthM: 0.65, rotationY: 0 });
  };
  for (let x = 312; x <= 466; x += 11) pushHedge(x, -52);
  for (let x = 312; x <= 466; x += 11) pushHedge(x, 31);

  // --- Road signs: district plates, parking and speed signs ------------------------
  const pushSign = (x, z, rotY, type, text) => {
    plan.signs.push({ x, z, y: core.heightAt(x, z), rotY, type, text });
    addCollider({ kind: 'circle', x, z, r: 0.22 });
  };
  pushSign(-252, 242, Math.PI, 'text', 'ДРИФТ-ЗОНА');
  pushSign(258, -96, -Math.PI / 2, 'text', 'ФЕСТИВАЛЬ');
  pushSign(11, -196, 0, 'text', 'ДРЭГ-ТРАССА');
  pushSign(-452, 210, Math.PI / 2, 'text', 'REAL VALLEY');
  pushSign(452, 240, -Math.PI / 2, 'text', 'REAL VALLEY');
  pushSign(330, 56, -Math.PI / 2, 'parking');
  pushSign(336, -276, -Math.PI / 2, 'parking');
  pushSign(-44, 344, Math.PI, 'parking');
  pushSign(44, 344, Math.PI, 'parking');
  pushSign(-146, 241, Math.PI, 'parking');
  pushSign(-296, -62, Math.PI / 2, 'parking');
  for (const e of core.roadGraph.edges) {
    if (!/^(hw-|avenue-\d|rt-highway|rt-blvd)/.test(e.id)) continue;
    let nextAt = 60;
    for (let i = 2; i < e.samples.length - 2; i++) {
      const sample = e.samples[i];
      if (sample.s < nextAt) continue;
      nextAt += 175;
      const frame = sampleFrame(e.samples, i);
      const px = sample.x + frame.normal.x * (e.halfWidthM + 2.4);
      const pz = sample.z + frame.normal.z * (e.halfWidthM + 2.4);
      if (Math.hypot(px - plan.roundabout.x, pz - plan.roundabout.z) < 44) continue;
      // Plate faces oncoming traffic travelling along +tangent.
      pushSign(px, pz, Math.atan2(-frame.tangent.x, -frame.tangent.z), 'speed');
    }
  }

  // --- Litter bins at bus stops and benches ------------------------------------------
  const pushBin = (x, z) => {
    plan.bins.push({ x, z, y: core.heightAt(x, z), rotY: rng() * Math.PI });
    addCollider({ kind: 'circle', x, z, r: 0.34 });
  };
  for (const stop of plan.busStops) {
    const fx = Math.sin(stop.rotY);
    const fz = Math.cos(stop.rotY);
    pushBin(stop.x + fz * 3.0 + fx * 0.7, stop.z - fx * 3.0 + fz * 0.7);
  }
  plan.benches.forEach((b, i) => {
    if (i % 2 === 0) pushBin(b.x + 1.9, b.z + 0.5);
  });

  // --- Bollards guarding shopfronts and the plaza gate --------------------------------
  const pushBollard = (x, z) => {
    plan.bollards.push({ x, z, y: core.heightAt(x, z) });
    addCollider({ kind: 'circle', x, z, r: 0.2 });
  };
  for (let x = -139; x <= -97; x += 5.2) pushBollard(x, 313);
  for (let x = 101; x <= 123; x += 5.4) pushBollard(x, 313.5);
  pushBollard(352, -97);
  pushBollard(352, -123);
  pushBollard(342, 57);
  pushBollard(342, 83);

  // --- Stone fences around parking lots ------------------------------------------------
  const pushFence = (x, z, rotY, w = 11.6) => {
    plan.fences.push({ x, z, y: core.heightAt(x, z), rotY, w });
    addCollider({ kind: 'obb', x, z, halfWidthM: w / 2, halfDepthM: 0.3, rotationY: rotY });
  };
  for (let x = 308; x <= 466; x += 12) pushFence(x, 191, 0);
  for (let x = -144; x <= -46; x += 12) pushFence(x, 242, 0);
  for (let z = -128; z <= -72; z += 12) pushFence(-379, z, Math.PI / 2);

  // --- Power line poles along the highway and riverside road ----------------------------
  const poleGroups = [
    { match: /^hw-w/, group: 'hw-west', spacing: 55 },
    { match: /^hw-e/, group: 'hw-east', spacing: 55 },
    { match: /^river-road/, group: 'river', spacing: 62 },
  ];
  const poleSeq = new Map();
  for (const e of core.roadGraph.edges) {
    const cfg = poleGroups.find((g) => g.match.test(e.id));
    if (!cfg) continue;
    let nextAt = 26;
    for (let i = 2; i < e.samples.length - 2; i++) {
      const sample = e.samples[i];
      if (sample.s < nextAt) continue;
      nextAt += cfg.spacing;
      const frame = sampleFrame(e.samples, i);
      const px = sample.x - frame.normal.x * (e.halfWidthM + 6);
      const pz = sample.z - frame.normal.z * (e.halfWidthM + 6);
      if (Math.abs(px - riverCenterX(pz)) < 30) continue;
      if (Math.hypot(px - plan.roundabout.x, pz - plan.roundabout.z) < 48) continue;
      const seq = poleSeq.get(cfg.group) || 0;
      poleSeq.set(cfg.group, seq + 1);
      plan.powerPoles.push({ x: px, z: pz, y: core.heightAt(px, pz), rotY: frame.yaw, group: cfg.group, seq });
      addCollider({ kind: 'circle', x: px, z: pz, r: 0.35 });
    }
  }

  // --- Street trees along the avenue ---------------------------------------------
  for (const e of core.roadGraph.edges) {
    if (!/^avenue/.test(e.id)) continue;
    for (let i = 3; i < e.samples.length - 3; i++) {
      const sample = e.samples[i];
      if (sample.s % 26 > 5) continue;
      const frame = sampleFrame(e.samples, i);
      for (const side of [-1, 1]) {
        if (rng() > 0.62) continue;
        const px = sample.x + frame.normal.x * side * (e.halfWidthM + 3.1);
        const pz = sample.z + frame.normal.z * side * (e.halfWidthM + 3.1);
        if (overlapsBuilding(px, pz, 4)) continue;
        if (plan.busStops.some((b) => Math.hypot(b.x - px, b.z - pz) < 6)) continue;
        const py = core.heightAt(px, pz);
        const s = 0.8 + rng() * 0.5;
        plan.trees.push({ x: px, z: pz, y: py - 0.1, rotY: rng() * Math.PI * 2, s, type: 'oak', tint: 0.85 + rng() * 0.35 });
        addCollider({ kind: 'circle', x: px, z: pz, r: 0.4 * s });
      }
    }
  }

  // --- Scattered trees and bushes --------------------------------------------------
  let attempts = 0;
  while (plan.trees.length < 620 && attempts < 6500) {
    attempts++;
    const x = -485 + rng() * 1970;
    const z = -485 + rng() * 970;
    if (Math.abs(x - riverCenterX(z)) < 20) continue;
    if (inRect(x, z, REAL_WORLD_ZONES.richtown, 10)) continue; // palms dress the district instead
    if (plan.pavedAreas.some((r) => inRect(x, z, r, 4))) continue;
    const y = core.heightAt(x, z);
    if (y < 0.9) continue;
    if (inRect(x, z, REAL_WORLD_ZONES.city) && rng() > 0.1) continue; // blocks are built-up
    const forestNoise = fbm(x * 0.006 + 9, z * 0.006 - 4, seed + 77, 3);
    const westWoods = x < -240 && z < 160;
    if (!westWoods && forestNoise < 0.44 && rng() > 0.35) continue;
    if (slopeApprox(core.heightAt, x, z) > 0.72) continue;
    const near = core.nearestRoad(x, z, { maxDistanceM: 30 });
    if (near && near.edgeDistanceM < 4.6) continue;
    if (overlapsBuilding(x, z, 5)) continue;
    const pine = westWoods ? rng() < 0.45 : rng() < 0.16;
    const s = pine ? 0.9 + rng() * 0.8 : 0.85 + rng() * 0.85;
    plan.trees.push({ x, z, y: y - 0.1, rotY: rng() * Math.PI * 2, s, type: pine ? 'pine' : 'oak', tint: 0.8 + rng() * 0.45 });
    addCollider({ kind: 'circle', x, z, r: 0.4 * s });
    if (rng() < 0.4 && plan.bushes.length < 320) {
      plan.bushes.push({
        x: x + (rng() - 0.5) * 7, z: z + (rng() - 0.5) * 7,
        y: core.heightAt(x, z) - 0.05, rotY: rng() * Math.PI * 2,
        s: 0.7 + rng() * 1.1, tint: 0.8 + rng() * 0.4,
      });
    }
  }

  // --- Rocks on the river banks and hill slopes --------------------------------------
  attempts = 0;
  while (plan.rocks.length < 90 && attempts < 2600) {
    attempts++;
    const x = -488 + rng() * 1976;
    const z = -488 + rng() * 976;
    if (inRect(x, z, REAL_WORLD_ZONES.richtown, 6)) continue;
    const y = core.heightAt(x, z);
    if (y < 0.3) continue;
    const slope = slopeApprox(core.heightAt, x, z);
    const bank = Math.abs(Math.abs(x - riverCenterX(z)) - 24) < 9;
    if (!(slope > 0.34 || bank)) continue;
    const near = core.nearestRoad(x, z, { maxDistanceM: 30 });
    if (near && near.edgeDistanceM < 3.2) continue;
    if (overlapsBuilding(x, z, 4)) continue;
    const s = 0.8 + rng() * 2.4;
    plan.rocks.push({ x, z, y: y - 0.25 * s, rotY: rng() * Math.PI * 2, s, sy: s * (0.55 + rng() * 0.55), tint: 0.8 + rng() * 0.4 });
    addCollider({ kind: 'circle', x, z, r: 0.95 * s });
  }

  // --- Invisible boundary walls just inside the rim -------------------------------
  const bx0 = REAL_WORLD_BOUNDS.minX + 8;
  const bx1 = REAL_WORLD_BOUNDS.maxX - 8;
  const bz0 = REAL_WORLD_BOUNDS.minZ + 8;
  const bz1 = REAL_WORLD_BOUNDS.maxZ - 8;
  addCollider({ kind: 'segment', x1: bx0, z1: bz0, x2: bx1, z2: bz0, r: 2 });
  addCollider({ kind: 'segment', x1: bx1, z1: bz0, x2: bx1, z2: bz1, r: 2 });
  addCollider({ kind: 'segment', x1: bx1, z1: bz1, x2: bx0, z2: bz1, r: 2 });
  addCollider({ kind: 'segment', x1: bx0, z1: bz1, x2: bx0, z2: bz0, r: 2 });
  return plan;
}

export function createRealWorldFoundation({ seed = 20261026, colliderCellM = 40 } = {}) {
  const rawHeightAt = rawHeightSampler(seed);
  const roadGraph = buildRoadGraph(buildRoadDefinition(), { sampleSpacingM: 5 });
  smoothEdgeHeights(roadGraph, rawHeightAt);
  const roadSegments = buildRoadSegments(roadGraph);
  const roadIndex = new RoadSpatialIndex(roadSegments, { cellSizeM: 40, initialSearchRadiusM: 35, maxSearchRadiusM: 320 });
  const colliderIndex = new ColliderIndex([], { cellSizeM: colliderCellM });

  function heightAt(x, z) {
    const raw = rawHeightAt(x, z);
    const nearest = roadIndex.nearest(x, z, { maxDistanceM: 70 });
    if (!nearest) return raw;
    const blend = 1 - smoothstep(0.5, 15, nearest.edgeDistanceM);
    return lerp(raw, nearest.point.y, blend);
  }
  function slopeAt(x, z) {
    const e = 6;
    const dx = (heightAt(x + e, z) - heightAt(x - e, z)) / (2 * e);
    const dz = (heightAt(x, z + e) - heightAt(x, z - e)) / (2 * e);
    return { x: dx, z: dz, magnitude: Math.hypot(dx, dz) };
  }
  function getDistrict(x, z) {
    return districtAt(x, z);
  }
  function surfaceAt(x, z, { nearestRoad = undefined, heightM = undefined } = {}) {
    const nearest = nearestRoad === undefined ? roadIndex.nearest(x, z, { maxDistanceM: 80 }) : nearestRoad;
    const h = heightM === undefined ? heightAt(x, z) : finite(heightM, 0);
    const district = getDistrict(x, z);
    if (nearest && nearest.edgeDistanceM <= 0) {
      const surface = REAL_WORLD_SURFACES[nearest.surface] || REAL_WORLD_SURFACES.asphalt;
      return { ...surface, heightM: h, road: nearest, district };
    }
    if (nearest && nearest.edgeDistanceM <= 1.7) {
      return { ...REAL_WORLD_SURFACES.gravel, heightM: h, road: nearest, district };
    }
    if (h <= REAL_WORLD_RIVER.waterLevelM + 0.05 && Math.abs(x - riverCenterX(z)) < 40) {
      return { ...REAL_WORLD_SURFACES.water, heightM: h, road: nearest, district };
    }
    if (h <= REAL_WORLD_RIVER.waterLevelM + 0.05 && inRect(x, z, REAL_WORLD_ZONES.marina, 4)) {
      return { ...REAL_WORLD_SURFACES.water, heightM: h, road: nearest, district };
    }
    if (h <= REAL_WORLD_RIVER.waterLevelM + 0.05 && inRect(x, z, REAL_WORLD_ZONES.sea, 2)) {
      return { ...REAL_WORLD_SURFACES.water, heightM: h, road: nearest, district };
    }
    if (h < 2.8 && (inRect(x, z, REAL_WORLD_ZONES.beach) || inRect(x, z, REAL_WORLD_ZONES.palmIsland) || inRect(x, z, REAL_WORLD_ZONES.sailIsland))) {
      return { ...REAL_WORLD_SURFACES.sand, heightM: h, road: nearest, district };
    }
    if (inRect(x, z, REAL_WORLD_ZONES.plaza) || REAL_WORLD_ZONES.parkings.some((r) => inRect(x, z, r))) {
      return { ...REAL_WORLD_SURFACES.concrete, heightM: h, road: nearest, district };
    }
    if ((inRect(x, z, REAL_WORLD_ZONES.city) || inRect(x, z, REAL_WORLD_ZONES.richtown)) && h < 9) {
      return { ...REAL_WORLD_SURFACES.concrete, heightM: h, road: nearest, district };
    }
    const slope = slopeAt(x, z).magnitude;
    let surface = REAL_WORLD_SURFACES.grass;
    if (slope > 0.52) surface = REAL_WORLD_SURFACES.rock;
    else if (Math.abs(x - riverCenterX(z)) < 36 && h < 2) surface = REAL_WORLD_SURFACES.sand;
    else if (district?.biome === 'forest') surface = REAL_WORLD_SURFACES.forest;
    else if (slope > 0.3) surface = REAL_WORLD_SURFACES.dirt;
    return { ...surface, heightM: h, slope, road: nearest, district };
  }
  function terrainColorAt(x, z, h, slope) {
    if (h <= 0.4) return [0.45, 0.42, 0.3];
    if (slope > 0.5) return [0.42, 0.4, 0.37];
    if (inRect(x, z, REAL_WORLD_ZONES.city) || inRect(x, z, REAL_WORLD_ZONES.richtown)) return [0.45, 0.46, 0.46];
    return [0.3, 0.48, 0.21];
  }
  function spawnPoint(lane = 0) {
    // Southern avenue just north of the roundabout, heading into the city.
    const e = roadGraph.edgesById.get('avenue-5');
    const p = e ? roadPointAt(e, 22, finite(lane, 0)) : null;
    if (!p) return { x: 2, y: heightAt(2, 128), z: 128, yaw: Math.PI };
    return { x: p.x, y: p.y, z: p.z, yaw: p.yaw };
  }

  const core = {
    heightAt,
    roadGraph,
    nearestRoad: (x, z, options) => roadIndex.nearest(x, z, options),
  };
  const dressingPlan = planDressing(core, seed);
  for (const c of dressingPlan.colliders) colliderIndex.add(c);

  function stats() {
    return {
      id: REAL_WORLD_ID,
      version: REAL_WORLD_VERSION,
      seed,
      worldSizeM: REAL_WORLD_SIZE_M,
      chunks: 1,
      chunksWithRoads: 1,
      districts: REAL_WORLD_DISTRICTS.length,
      roadNodes: roadGraph.nodes.length,
      roadEdges: roadGraph.edges.length,
      roadLengthM: Math.round(roadGraph.totalLengthM),
      roadSegments: roadSegments.length,
      roadIndex: roadIndex.stats(),
      colliders: colliderIndex.stats(),
      dressing: {
        buildings: dressingPlan.buildings.length,
        trees: dressingPlan.trees.length,
        bushes: dressingPlan.bushes.length,
        rocks: dressingPlan.rocks.length,
        lamps: dressingPlan.lamps.length,
        tents: dressingPlan.festival.tents.length,
        busStops: dressingPlan.busStops.length,
        benches: dressingPlan.benches.length,
        hedges: dressingPlan.hedges.length,
        signs: dressingPlan.signs.length,
        bins: dressingPlan.bins.length,
        bollards: dressingPlan.bollards.length,
        fences: dressingPlan.fences.length,
        powerPoles: dressingPlan.powerPoles.length,
        palms: dressingPlan.palms.length,
        pools: dressingPlan.pools.length,
        landmarks: dressingPlan.landmarks.length,
      },
    };
  }

  return {
    id: REAL_WORLD_ID,
    version: REAL_WORLD_VERSION,
    isRealWorld: true,
    seed,
    bounds: REAL_WORLD_BOUNDS,
    worldSizeM: REAL_WORLD_SIZE_M,
    districts: REAL_WORLD_DISTRICTS,
    surfaces: REAL_WORLD_SURFACES,
    river: REAL_WORLD_RIVER,
    zones: REAL_WORLD_ZONES,
    rawHeightAt,
    heightAt,
    slopeAt,
    roadGraph,
    roadSegments,
    roadIndex,
    colliderIndex,
    nearestRoad: core.nearestRoad,
    findRoute: (from, to, options = {}) => graphFindRoute(roadGraph, from, to, { cost: options.cost || options.mode || 'distance' }),
    getDistrict,
    surfaceAt,
    terrainColorAt,
    spawnPoint,
    dressingPlan,
    stats,
  };
}
