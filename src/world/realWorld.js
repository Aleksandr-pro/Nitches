/**
 * Real Valley — compact 1 x 1 km playable world.
 *
 * v0.10 layout follows the "Nitches Horizon" reference map: a dense city
 * street grid around a wide central avenue with a drag strip at its north
 * end, a roundabout where the avenue meets the east-west highway, a winding
 * river with a riverside road along the west edge, a closed drift circuit
 * in the south-west, a festival plaza and parking lots in the east, and a
 * car shop + cafe on the southern street.
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
export const REAL_WORLD_VERSION = '0.10.0';
export const REAL_WORLD_SIZE_M = 1000;
export const REAL_WORLD_HALF_M = REAL_WORLD_SIZE_M / 2;
export const REAL_WORLD_BOUNDS = Object.freeze({
  minX: -REAL_WORLD_HALF_M,
  minZ: -REAL_WORLD_HALF_M,
  maxX: REAL_WORLD_HALF_M,
  maxZ: REAL_WORLD_HALF_M,
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
  ]),
  city: Object.freeze({ minX: -185, maxX: 285, minZ: -415, maxZ: 205 }),
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
    h = lerp(h, 3.8, rectBlend(px, pz, REAL_WORLD_ZONES.parkings[0], 60) * 0.95);
    h = lerp(h, 4.2, radialBlend(px, pz, REAL_WORLD_ZONES.drift.x, REAL_WORLD_ZONES.drift.z, 105, 200) * 0.92);
    h = lerp(h, 3.9, rectBlend(px, pz, { minX: -250, maxX: 250, minZ: 270, maxZ: 430 }, 70) * 0.8);

    // River channel along the west edge, with a land bridge where the
    // highway and the riverside road cross (z ~ 192..238).
    const dRiver = Math.abs(px - riverCenterX(pz));
    const gap = smoothstep(172, 192, pz) * (1 - smoothstep(238, 258, pz));
    const endFade = 1 - smoothstep(452, 492, Math.abs(pz));
    const riverCut = (1 - smoothstep(10, 34, dRiver)) * (1 - gap) * endFade;
    h = lerp(h, -1.4, riverCut * 0.98);

    // Rim hills close the playable square.
    const edge = Math.max(
      smoothstep(455, 500, Math.abs(px)),
      smoothstep(455, 500, Math.abs(pz)),
    );
    h = lerp(h, h + 18, edge * 0.8);
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
  const grid = CITY_VX.map((col, ix) => CITY_HZ.map((z, iz) => addNode(`n${ix}_${iz}`, col.x, z)));
  CITY_VX.forEach((col, ix) => {
    for (let iz = 0; iz < CITY_HZ.length - 1; iz++) {
      addEdge(
        col.avenue ? `avenue-${iz}` : `street-v${ix}-${iz}`,
        grid[ix][iz + 1], grid[ix][iz],
        straight(col.x, CITY_HZ[iz + 1], col.x, CITY_HZ[iz]),
        { widthM: col.widthM, speedLimitKmh: col.avenue ? 60 : 40 },
      );
    }
  });
  CITY_HZ.forEach((z, iz) => {
    for (let ix = 0; ix < CITY_VX.length - 1; ix++) {
      addEdge(
        `street-h${iz}-${ix}`,
        grid[ix][iz], grid[ix + 1][iz],
        straight(CITY_VX[ix].x, z, CITY_VX[ix + 1].x, z),
        { widthM: z === -110 ? 12 : 10, speedLimitKmh: 40 },
      );
    }
  });

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
    pavedAreas: [
      { ...REAL_WORLD_ZONES.plaza, kind: 'plaza' },
      ...REAL_WORLD_ZONES.parkings.map((r) => ({ ...r, kind: 'parking' })),
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
            ? ['modern', 'glass', 'brick', 'panel']
            : ['brick', 'panel'];
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

  // --- Sparse houses along the riverside road and southern links ------------
  const rural = /^(river-road|north-link|south-st|sw-link|se-link)/;
  for (const e of core.roadGraph.edges) {
    if (plan.buildings.length >= 260) break;
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
        facade: rng() < 0.5 ? 'brick' : 'panel', tint: 0.82 + rng() * 0.36,
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
  const lit = /^(street-|avenue|hw-|drag-|south-|rb-arc|plaza-entry|parking-entry)/;
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
      plan.lamps.push({ x: px, z: pz, y: core.heightAt(px, pz), rotY: frame.yaw });
      addCollider({ kind: 'circle', x: px, z: pz, r: 0.3 });
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
    const x = -485 + rng() * 970;
    const z = -485 + rng() * 970;
    if (Math.abs(x - riverCenterX(z)) < 20) continue;
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
    const x = -488 + rng() * 976;
    const z = -488 + rng() * 976;
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
  const B = 492;
  addCollider({ kind: 'segment', x1: -B, z1: -B, x2: B, z2: -B, r: 2 });
  addCollider({ kind: 'segment', x1: B, z1: -B, x2: B, z2: B, r: 2 });
  addCollider({ kind: 'segment', x1: B, z1: B, x2: -B, z2: B, r: 2 });
  addCollider({ kind: 'segment', x1: -B, z1: B, x2: -B, z2: -B, r: 2 });
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
    if (inRect(x, z, REAL_WORLD_ZONES.plaza) || REAL_WORLD_ZONES.parkings.some((r) => inRect(x, z, r))) {
      return { ...REAL_WORLD_SURFACES.concrete, heightM: h, road: nearest, district };
    }
    if (inRect(x, z, REAL_WORLD_ZONES.city) && h < 9) {
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
    if (inRect(x, z, REAL_WORLD_ZONES.city)) return [0.45, 0.46, 0.46];
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
