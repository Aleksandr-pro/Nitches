/**
 * Real Valley — compact 1 x 1 km playable world that replaces both the
 * procedural Festival Britain dressing and the imported Manhattan plate.
 *
 * Pure-data foundation (no Three imports): analytic terrain with a valley
 * town, a road network reusing the shared road-graph/spatial-index code,
 * surfaces, districts and a deterministic dressing plan (buildings, trees,
 * rocks, lamps) with colliders.  Rendering lives in realWorldScene.js and
 * uses generated photorealistic textures — no bare coloured primitives.
 */
import { buildRoadGraph, buildRoadSegments, findRoute as graphFindRoute, roadPointAt } from './roadGraph.js';
import { ColliderIndex, RoadSpatialIndex } from './spatialIndex.js';

export const REAL_WORLD_ID = 'real-valley';
export const REAL_WORLD_VERSION = '0.9.0';
export const REAL_WORLD_SIZE_M = 1000;
export const REAL_WORLD_HALF_M = REAL_WORLD_SIZE_M / 2;
export const REAL_WORLD_BOUNDS = Object.freeze({
  minX: -REAL_WORLD_HALF_M,
  minZ: -REAL_WORLD_HALF_M,
  maxX: REAL_WORLD_HALF_M,
  maxZ: REAL_WORLD_HALF_M,
});
export const REAL_WORLD_LAKE = Object.freeze({ x: 330, z: 330, radiusM: 150, waterLevelM: 0.2 });

export const REAL_WORLD_DISTRICTS = Object.freeze([
  { id: 'town-centre', name: 'Центр города', x: 0, z: 0, radiusM: 250, biome: 'urban' },
  { id: 'lakeside', name: 'Озёрный берег', x: 300, z: 260, radiusM: 220, biome: 'lake' },
  { id: 'mountain-pass', name: 'Горный перевал', x: -350, z: -340, radiusM: 240, biome: 'highlands' },
  { id: 'pine-forest', name: 'Сосновый лес', x: -300, z: 190, radiusM: 230, biome: 'forest' },
  { id: 'east-hills', name: 'Восточные холмы', x: 330, z: -250, radiusM: 220, biome: 'moor' },
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
    let h = 6
      + (fbm(px * 0.0016 + 3.1, pz * 0.0016 - 1.4, seed, 4) - 0.5) * 7
      + (fbm(px * 0.008 - 5.2, pz * 0.008 + 2.8, seed + 17, 3) - 0.5) * 1.6;

    // Mountain rim to the north-west, gentler hills elsewhere.  Peaks are
    // kept away from road junctions so every road profile can satisfy the
    // 16% grade limit between its pinned endpoints.
    h += gaussian(px, pz, -430, -420, 55, 175);
    h += gaussian(px, pz, -60, -460, 30, 220);
    h += gaussian(px, pz, -470, 20, 20, 160);
    h += gaussian(px, pz, 440, -300, 20, 180);
    h += gaussian(px, pz, -340, 340, 12, 180);

    // Flat, buildable town bowl in the centre.
    const town = radialBlend(px, pz, 0, 0, 185, 340);
    h = lerp(h, 6.2, town * 0.92);

    // Lake bowl in the south-east.
    const lake = radialBlend(px, pz, REAL_WORLD_LAKE.x, REAL_WORLD_LAKE.z, 120, 245);
    h = lerp(h, -3.2, lake * 0.97);

    // Rim mountains close the playable square.
    const edge = Math.max(
      smoothstep(448, 500, Math.abs(px)),
      smoothstep(448, 500, Math.abs(pz)),
    );
    h = lerp(h, h + 26, edge * 0.85);
    return Number.isFinite(h) ? h : 0;
  };
}

const NODES = [
  ['westgate', -430, 30], ['west', -250, 5], ['centre', 0, 0], ['east', 250, -5], ['eastgate', 430, -35],
  ['northgate', -15, -430], ['north', 0, -250], ['south', 5, 250], ['southgate', 35, 430],
  ['nw', -285, -225], ['ne', 285, -225], ['se', 255, 175], ['sw', -285, 225],
  ['lakewest', 150, 285], ['viewpoint', -405, -405], ['forestgate', -430, 300],
].map(([id, x, z]) => ({ id, x, z, type: 'junction', districtId: null }));

function edge(id, from, to, points, options = {}) {
  return {
    id, from, to, points,
    roadClass: options.roadClass || 'A',
    surface: options.surface || 'asphalt',
    widthM: options.widthM || 7.6,
    lanes: options.lanes || 2,
    speedLimitKmh: options.speedLimitKmh || 80,
    name: options.name || id,
  };
}

const TOWN_EDGE_IDS = new Set([
  'main-west', 'main-centre-west', 'main-centre-east', 'main-east',
  'avenue-north', 'avenue-centre-north', 'avenue-centre-south', 'avenue-south',
  'ring-west-nw', 'ring-nw-north', 'ring-north-ne', 'ring-ne-east',
  'ring-east-se', 'ring-se-south', 'ring-south-sw', 'ring-sw-west',
]);

const ROAD_DEFINITION = Object.freeze({
  id: 'real-valley-roads',
  version: REAL_WORLD_VERSION,
  nodes: NODES,
  edges: [
    edge('main-west', 'westgate', 'west', [[-430, 30], [-340, 18], [-250, 5]]),
    edge('main-centre-west', 'west', 'centre', [[-250, 5], [-120, 2], [0, 0]], { widthM: 9, speedLimitKmh: 50 }),
    edge('main-centre-east', 'centre', 'east', [[0, 0], [130, -3], [250, -5]], { widthM: 9, speedLimitKmh: 50 }),
    edge('main-east', 'east', 'eastgate', [[250, -5], [340, -20], [430, -35]]),
    edge('avenue-north', 'northgate', 'north', [[-15, -430], [-5, -340], [0, -250]]),
    edge('avenue-centre-north', 'north', 'centre', [[0, -250], [-4, -120], [0, 0]], { widthM: 9, speedLimitKmh: 50 }),
    edge('avenue-centre-south', 'centre', 'south', [[0, 0], [2, 130], [5, 250]], { widthM: 9, speedLimitKmh: 50 }),
    edge('avenue-south', 'south', 'southgate', [[5, 250], [20, 340], [35, 430]]),
    edge('ring-west-nw', 'west', 'nw', [[-250, 5], [-300, -110], [-285, -225]], { widthM: 7.4, speedLimitKmh: 60 }),
    edge('ring-nw-north', 'nw', 'north', [[-285, -225], [-150, -275], [0, -250]], { widthM: 7.4, speedLimitKmh: 60 }),
    edge('ring-north-ne', 'north', 'ne', [[0, -250], [150, -270], [285, -225]], { widthM: 7.4, speedLimitKmh: 60 }),
    edge('ring-ne-east', 'ne', 'east', [[285, -225], [305, -120], [250, -5]], { widthM: 7.4, speedLimitKmh: 60 }),
    edge('ring-east-se', 'east', 'se', [[250, -5], [300, 85], [255, 175]], { widthM: 7.4, speedLimitKmh: 60 }),
    edge('ring-se-south', 'se', 'south', [[255, 175], [150, 245], [5, 250]], { widthM: 7.4, speedLimitKmh: 60 }),
    edge('ring-south-sw', 'south', 'sw', [[5, 250], [-150, 255], [-285, 225]], { widthM: 7.4, speedLimitKmh: 60 }),
    edge('ring-sw-west', 'sw', 'west', [[-285, 225], [-305, 110], [-250, 5]], { widthM: 7.4, speedLimitKmh: 60 }),
    edge('mountain-pass', 'nw', 'viewpoint', [[-285, -225], [-365, -258], [-312, -318], [-388, -352], [-405, -405]], { roadClass: 'B', widthM: 6.2, speedLimitKmh: 50 }),
    edge('lake-approach', 'south', 'lakewest', [[5, 250], [80, 286], [150, 285]], { roadClass: 'B', widthM: 6.8, speedLimitKmh: 60 }),
    edge('lake-shore', 'lakewest', 'se', [[150, 285], [205, 225], [255, 175]], { roadClass: 'B', widthM: 6.8, speedLimitKmh: 60 }),
    edge('forest-road', 'sw', 'forestgate', [[-285, 225], [-360, 255], [-430, 300]], { roadClass: 'B', widthM: 6.4, speedLimitKmh: 60 }),
  ],
});

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
  // Average shared junction elevations, blend them in over 55 m and clamp
  // again — the same seam strategy as the large world, scaled down.
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
    let values = profiles.get(e.id).map((value, i) => {
      const s = e.samples[i].s;
      let next = value;
      const fromStart = smoothstep(0, 55, s);
      const fromEnd = smoothstep(0, 55, e.lengthM - s);
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

function planDressing(core, seed) {
  const rng = mulberry32(seed ^ 0x5EED);
  const plan = { buildings: [], trees: [], bushes: [], rocks: [], lamps: [], colliders: [] };
  const addCollider = (record) => plan.colliders.push({ id: `real-${plan.colliders.length}`, ...record });
  const overlapsBuilding = (x, z, pad) => plan.buildings.some(
    (b) => Math.hypot(x - b.x, z - b.z) < Math.max(b.w, b.d) * 0.62 + pad,
  );

  // --- Buildings along the town streets -------------------------------------
  for (const e of core.roadGraph.edges) {
    if (plan.buildings.length >= 170) break;
    if (!TOWN_EDGE_IDS.has(e.id)) continue;
    for (let i = 3; i < e.samples.length - 3; i++) {
      if (plan.buildings.length >= 170) break;
      const sample = e.samples[i];
      if (sample.s % 21 > 5) continue;
      const distCentre = Math.hypot(sample.x, sample.z);
      if (distCentre > 345) continue;
      const density = distCentre < 150 ? 0.92 : distCentre < 260 ? 0.72 : 0.45;
      if (rng() > density) continue;
      const frame = sampleFrame(e.samples, i);
      const sides = rng() < 0.35 ? [-1, 1] : [rng() < 0.5 ? -1 : 1];
      for (const side of sides) {
        if (plan.buildings.length >= 170) break;
        const kind = distCentre < 125
          ? (rng() < 0.72 ? 'apartment' : 'townhouse')
          : distCentre < 225
            ? (rng() < 0.55 ? 'townhouse' : 'house')
            : 'house';
        const dims = kind === 'apartment'
          ? { w: 16 + rng() * 10, d: 14 + rng() * 8, h: 13 + rng() * 13, roofH: 0 }
          : kind === 'townhouse'
            ? { w: 11 + rng() * 7, d: 10 + rng() * 6, h: 7 + rng() * 5, roofH: rng() < 0.45 ? 2 + rng() * 1.6 : 0 }
            : { w: 8 + rng() * 5, d: 7 + rng() * 4, h: 4.6 + rng() * 2.4, roofH: 2 + rng() * 1.6 };
        const offset = e.halfWidthM + Math.max(dims.w, dims.d) * 0.42 + 4.5 + rng() * 6;
        const px = sample.x + frame.normal.x * side * offset;
        const pz = sample.z + frame.normal.z * side * offset;
        if (Math.abs(px) > 468 || Math.abs(pz) > 468) continue;
        if (Math.hypot(px - REAL_WORLD_LAKE.x, pz - REAL_WORLD_LAKE.z) < 185) continue;
        const py = core.heightAt(px, pz);
        if (py < 1 || slopeApprox(core.heightAt, px, pz) > 0.3) continue;
        const near = core.nearestRoad(px, pz, { maxDistanceM: 40 });
        if (near && near.edgeDistanceM < 5.5) continue;
        if (overlapsBuilding(px, pz, Math.max(dims.w, dims.d) * 0.55)) continue;
        const rotY = Math.atan2(-frame.normal.x * side, -frame.normal.z * side);
        const facade = kind === 'apartment' ? (rng() < 0.62 ? 'modern' : 'brick') : 'brick';
        plan.buildings.push({
          x: px, z: pz, y: py - 0.25, rotY, ...dims, kind, facade,
          tint: 0.82 + rng() * 0.36,
        });
        addCollider({ kind: 'obb', x: px, z: pz, halfWidthM: dims.w / 2, halfDepthM: dims.d / 2, rotationY: rotY });
      }
    }
  }

  // --- Lamps along the lit streets -------------------------------------------
  for (const e of core.roadGraph.edges) {
    if (!TOWN_EDGE_IDS.has(e.id)) continue;
    for (let i = 3; i < e.samples.length - 3; i++) {
      const sample = e.samples[i];
      if (sample.s % 46 > 5) continue;
      if (Math.hypot(sample.x, sample.z) > 330) continue;
      const frame = sampleFrame(e.samples, i);
      const side = Math.floor(sample.s / 46) % 2 === 0 ? 1 : -1;
      const px = sample.x + frame.normal.x * side * (e.halfWidthM + 1.3);
      const pz = sample.z + frame.normal.z * side * (e.halfWidthM + 1.3);
      plan.lamps.push({ x: px, z: pz, y: core.heightAt(px, pz), rotY: frame.yaw });
      addCollider({ kind: 'circle', x: px, z: pz, r: 0.3 });
    }
  }

  // --- Trees and bushes --------------------------------------------------------
  let attempts = 0;
  while (plan.trees.length < 520 && attempts < 4200) {
    attempts++;
    const x = -485 + rng() * 970;
    const z = -485 + rng() * 970;
    if (Math.hypot(x - REAL_WORLD_LAKE.x, z - REAL_WORLD_LAKE.z) < 162) continue;
    const y = core.heightAt(x, z);
    if (y < 0.9) continue;
    const distCentre = Math.hypot(x, z);
    const forestNoise = fbm(x * 0.006 + 9, z * 0.006 - 4, seed + 77, 3);
    const inForest = x < -140 && z > 40;
    if (distCentre < 215 && rng() > 0.16) continue; // sparse street/park trees in town
    if (!inForest && forestNoise < 0.44 && rng() > 0.35) continue;
    if (slopeApprox(core.heightAt, x, z) > 0.72) continue;
    const near = core.nearestRoad(x, z, { maxDistanceM: 30 });
    if (near && near.edgeDistanceM < 4.6) continue;
    if (overlapsBuilding(x, z, 5)) continue;
    const pine = y > 24 ? rng() < 0.75 : inForest ? rng() < 0.55 : rng() < 0.18;
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

  // --- Rocks on slopes and the lakeshore --------------------------------------
  attempts = 0;
  while (plan.rocks.length < 120 && attempts < 2600) {
    attempts++;
    const x = -488 + rng() * 976;
    const z = -488 + rng() * 976;
    const y = core.heightAt(x, z);
    const slope = slopeApprox(core.heightAt, x, z);
    const shore = Math.abs(Math.hypot(x - REAL_WORLD_LAKE.x, z - REAL_WORLD_LAKE.z) - 165) < 22;
    if (!(slope > 0.32 || y > 24 || shore)) continue;
    if (y < 0.2) continue;
    const near = core.nearestRoad(x, z, { maxDistanceM: 30 });
    if (near && near.edgeDistanceM < 3.2) continue;
    if (overlapsBuilding(x, z, 4)) continue;
    const s = 0.8 + rng() * 2.6;
    plan.rocks.push({ x, z, y: y - 0.25 * s, rotY: rng() * Math.PI * 2, s, sy: s * (0.55 + rng() * 0.55), tint: 0.8 + rng() * 0.4 });
    addCollider({ kind: 'circle', x, z, r: 0.95 * s });
  }

  // --- Invisible boundary walls just inside the rim ----------------------------
  const B = 492;
  addCollider({ kind: 'segment', x1: -B, z1: -B, x2: B, z2: -B, r: 2 });
  addCollider({ kind: 'segment', x1: B, z1: -B, x2: B, z2: B, r: 2 });
  addCollider({ kind: 'segment', x1: B, z1: B, x2: -B, z2: B, r: 2 });
  addCollider({ kind: 'segment', x1: -B, z1: B, x2: -B, z2: -B, r: 2 });
  return plan;
}

export function createRealWorldFoundation({ seed = 20261026, colliderCellM = 40 } = {}) {
  const rawHeightAt = rawHeightSampler(seed);
  const roadGraph = buildRoadGraph(ROAD_DEFINITION, { sampleSpacingM: 5 });
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
    if (h <= REAL_WORLD_LAKE.waterLevelM + 0.05) {
      return { ...REAL_WORLD_SURFACES.water, heightM: h, road: nearest, district };
    }
    if (Math.hypot(x, z) < 225 && h < 12) {
      return { ...REAL_WORLD_SURFACES.concrete, heightM: h, road: nearest, district };
    }
    const slope = slopeAt(x, z).magnitude;
    let surface = REAL_WORLD_SURFACES.grass;
    if (slope > 0.52 || h > 46) surface = REAL_WORLD_SURFACES.rock;
    else if (Math.hypot(x - REAL_WORLD_LAKE.x, z - REAL_WORLD_LAKE.z) < 235 && h < 2.4) surface = REAL_WORLD_SURFACES.sand;
    else if (district?.biome === 'forest') surface = REAL_WORLD_SURFACES.forest;
    else if (slope > 0.3) surface = REAL_WORLD_SURFACES.dirt;
    return { ...surface, heightM: h, slope, road: nearest, district };
  }
  function terrainColorAt(x, z, h, slope) {
    if (h <= 0.4) return [0.45, 0.42, 0.3];
    if (slope > 0.5 || h > 46) return [0.42, 0.4, 0.37];
    if (Math.hypot(x, z) < 225) return [0.45, 0.46, 0.46];
    return [0.3, 0.48, 0.21];
  }
  function spawnPoint(lane = 0) {
    const e = roadGraph.edgesById.get('main-centre-west');
    const p = roadPointAt(e, 42, finite(lane, 0));
    if (!p) return { x: -210, y: heightAt(-210, 4), z: 4, yaw: Math.PI / 2 };
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
    lake: REAL_WORLD_LAKE,
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
