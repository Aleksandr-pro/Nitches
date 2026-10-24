/*
 * Stage 4a world dressing for Festival Britain: deterministic per-chunk
 * scatter of vegetation, buildings, road furniture and landmarks.
 *
 * Everything here is pure data (plans + low-poly archetype geometry with
 * vertex colours).  The Three streamer instances the archetypes, and the
 * same placement records produce colliders — so swapping an archetype for
 * a GLB template later only changes the streamer, not the placement.
 */

import { isInsideManhattanCity } from './manhattanCity.js';

function finite(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}
function clamp(value, min, max) {
  return Math.max(min, Math.min(max, finite(value, min)));
}

export function mulberry32(seed) {
  let a = seed >>> 0;
  return function next() {
    a |= 0;
    a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function rngForChunk(seed, cx, cz) {
  return mulberry32((finite(seed, 1) ^ Math.imul(cx + 101, 374761393) ^ Math.imul(cz + 57, 668265263)) >>> 0);
}

const BIOME_DENSITY = {
  forest: { trees: 120, bushes: 42, rocks: 10 },
  countryside: { trees: 18, bushes: 24, rocks: 7 },
  farms: { trees: 11, bushes: 15, rocks: 3 },
  moor: { trees: 3, bushes: 20, rocks: 26 },
  highlands: { trees: 4, bushes: 11, rocks: 36 },
  lake: { trees: 28, bushes: 22, rocks: 15 },
  coast: { trees: 7, bushes: 13, rocks: 11 },
  festival: { trees: 9, bushes: 9, rocks: 1 },
  urban: { trees: 6, bushes: 4, rocks: 0 },
  castle: { trees: 15, bushes: 11, rocks: 9 },
};

const URBAN_FACTOR = {
  urban: 1.0,
  festival: 0.55,
  coast: 0.42,
  lake: 0.36,
  farms: 0.32,
  castle: 0.12,
  countryside: 0.05,
};

export const BUILDING_TINTS = [
  [0.92, 0.88, 0.8], [0.85, 0.7, 0.58], [0.78, 0.72, 0.66], [0.9, 0.62, 0.5],
  [0.72, 0.76, 0.82], [0.95, 0.9, 0.72], [0.66, 0.6, 0.55], [0.84, 0.8, 0.88],
];
export const ROOF_TINTS = [
  [0.42, 0.3, 0.24], [0.3, 0.3, 0.34], [0.55, 0.32, 0.22], [0.36, 0.38, 0.4], [0.48, 0.26, 0.2],
];

function slopeApprox(foundation, x, z) {
  const e = 3;
  const dx = (foundation.heightAt(x + e, z) - foundation.heightAt(x - e, z)) / (2 * e);
  const dz = (foundation.heightAt(x, z + e) - foundation.heightAt(x, z - e)) / (2 * e);
  return Math.hypot(dx, dz);
}

function sampleFrame(edge, index) {
  const samples = edge.samples;
  const a = samples[Math.max(0, index - 1)];
  const b = samples[Math.min(samples.length - 1, index + 1)];
  const tx = b.x - a.x;
  const tz = b.z - a.z;
  const len = Math.hypot(tx, tz) || 1;
  return {
    tangent: { x: tx / len, z: tz / len },
    normal: { x: -tz / len, z: tx / len },
    yaw: Math.atan2(tx / len, tz / len),
  };
}

function insideBounds(bounds, x, z, margin = 0) {
  return x >= bounds.minX - margin && x <= bounds.maxX + margin
    && z >= bounds.minZ - margin && z <= bounds.maxZ + margin;
}

/**
 * Plan all dressing instances for one chunk.  Deterministic for a given
 * foundation seed + chunk coordinates, so streamed chunks always match.
 */
export function planChunkDressing(foundation, cx, cz, { lodTier = 0 } = {}) {
  const chunk = foundation.chunkDescriptor(cx, cz);
  const bounds = chunk.bounds;
  const rng = rngForChunk(foundation.seed, cx, cz);
  const plan = {
    chunkKey: chunk.key,
    cx,
    cz,
    trees: [],
    bushes: [],
    rocks: [],
    buildings: [],
    towers: [],
    tents: [],
    lamps: [],
    walls: [],
    colliders: [],
  };
  const collider = (record) => plan.colliders.push({ id: `${chunk.key}:${plan.colliders.length}`, ...record });

  // --- Vegetation & rocks by biome rejection scatter -----------------------
  const centreDistrict = foundation.getDistrict(chunk.center.x, chunk.center.z);
  const attempts = 260;
  const placed = { trees: 0, bushes: 0, rocks: 0 };
  for (let i = 0; i < attempts; i++) {
    const x = bounds.minX + rng() * (bounds.maxX - bounds.minX);
    const z = bounds.minZ + rng() * (bounds.maxZ - bounds.minZ);
    // The imported Manhattan GLB owns its footprint: no procedural scatter.
    if (isInsideManhattanCity(x, z, 2)) continue;
    const district = foundation.getDistrict(x, z);
    const biome = district?.biome || 'countryside';
    const quota = BIOME_DENSITY[biome] || BIOME_DENSITY.countryside;
    const falloff = district ? 1 - district.normalizedDistance * 0.45 : 1;

    const roll = rng() * (quota.trees + quota.bushes + quota.rocks + 60);
    let kind = null;
    if (roll < quota.trees * falloff) kind = 'trees';
    else if (roll < (quota.trees + quota.bushes) * falloff) kind = 'bushes';
    else if (roll < (quota.trees + quota.bushes + quota.rocks) * falloff) kind = 'rocks';
    if (!kind || placed[kind] >= quota[kind === 'trees' ? 'trees' : kind]) continue;

    const y = foundation.heightAt(x, z);
    if (y < 0.4) continue;
    const slope = slopeApprox(foundation, x, z);
    if (slope > (kind === 'rocks' ? 0.95 : 0.55)) continue;
    const clearM = kind === 'trees' ? 4 : kind === 'rocks' ? 3 : 2.2;
    const near = foundation.nearestRoad(x, z, { maxDistanceM: 30 });
    if (near && near.edgeDistanceM < clearM) continue;

    const rotY = rng() * Math.PI * 2;
    const tint = 0.8 + rng() * 0.4;
    if (kind === 'trees') {
      const pineBias = biome === 'forest' ? 0.45 : biome === 'highlands' || biome === 'moor' ? 0.7
        : biome === 'lake' ? 0.4 : 0.16;
      const type = rng() < pineBias || (y > 38 && rng() < 0.6) ? 'pine' : 'oak';
      const s = type === 'pine' ? 0.9 + rng() * 0.7 : 0.8 + rng() * 0.7;
      plan.trees.push({ x, z, y, rotY, s, type, tint: [tint, tint, tint] });
      collider({ kind: 'circle', x, z, r: 0.42 * s });
    } else if (kind === 'bushes') {
      if (lodTier < 2) plan.bushes.push({ x, z, y, rotY, s: 0.7 + rng() * 1.0, tint: [tint, tint, tint] });
    } else {
      const s = 0.6 + rng() * 1.7;
      plan.rocks.push({ x, z, y: y - 0.15 * s, rotY, s, sy: s * (0.55 + rng() * 0.5), tint: [tint, tint, tint] });
      collider({ kind: 'circle', x, z, r: 0.95 * s });
    }
    placed[kind]++;
  }

  // --- Buildings, lamps and walls along this chunk's roads -----------------
  for (const edgeId of chunk.roadEdgeIds) {
    const edge = foundation.roadGraph.edgesById.get(edgeId);
    if (!edge) continue;

    // Buildings
    for (let i = 2; i < edge.samples.length - 2; i++) {
      const sample = edge.samples[i];
      if (!insideBounds(bounds, sample.x, sample.z)) continue;
      if (sample.s % 38 > 5.2) continue;
      const district = foundation.getDistrict(sample.x, sample.z);
      const biome = district?.biome || 'countryside';
      const urban = (URBAN_FACTOR[biome] ?? 0.04) * (district ? 1 - district.normalizedDistance * 0.55 : 1);
      if (rng() > urban) continue;

      const frame = sampleFrame(edge, i);
      const side = rng() < 0.5 ? -1 : 1;
      const isCity = biome === 'urban';
      const isBarn = biome === 'farms' && rng() < 0.32;
      const offset = edge.halfWidthM + (isCity ? 7 + rng() * 6 : 9 + rng() * 10);
      const px = sample.x + frame.normal.x * side * offset;
      const pz = sample.z + frame.normal.z * side * offset;
      if (!insideBounds(bounds, px, pz, 4)) continue;
      if (isInsideManhattanCity(px, pz, 6)) continue;
      const py = foundation.heightAt(px, pz);
      if (py < 0.5 || slopeApprox(foundation, px, pz) > 0.32) continue;
      const nearOther = foundation.nearestRoad(px, pz, { maxDistanceM: 40 });
      if (nearOther && nearOther.edgeDistanceM < 5) continue;

      const toRoadYaw = Math.atan2(-frame.normal.x * side, -frame.normal.z * side);
      const building = isCity
        ? { w: 12 + rng() * 10, d: 12 + rng() * 9, h: 10 + rng() * 20, roofH: 0, kind: 'block' }
        : isBarn
          ? { w: 8 + rng() * 5, d: 6 + rng() * 3, h: 3.4 + rng() * 1.2, roofH: 1.8 + rng(), kind: 'barn' }
          : { w: 7 + rng() * 4, d: 6 + rng() * 3, h: 3.2 + rng() * 1.5, roofH: 1.9 + rng() * 1.1, kind: 'house' };
      plan.buildings.push({
        x: px, z: pz, y: py - 0.25, rotY: toRoadYaw, yOff: 0,
        ...building,
        tint: isBarn ? [0.62, 0.42, 0.3] : BUILDING_TINTS[Math.floor(rng() * BUILDING_TINTS.length)],
        roofTint: ROOF_TINTS[Math.floor(rng() * ROOF_TINTS.length)],
      });
      collider({
        kind: 'obb', x: px, z: pz, halfWidthM: building.w / 2, halfDepthM: building.d / 2, rotationY: toRoadYaw,
      });
    }

    // Lamps in built-up districts
    if (lodTier < 2) {
      for (let i = 2; i < edge.samples.length - 2; i++) {
        const sample = edge.samples[i];
        if (!insideBounds(bounds, sample.x, sample.z)) continue;
        if (sample.s % 44 > 5.2) continue;
        const district = foundation.getDistrict(sample.x, sample.z);
        if (!district || (district.biome !== 'urban' && district.biome !== 'festival')) continue;
        const frame = sampleFrame(edge, i);
        const side = Math.floor(sample.s / 44) % 2 === 0 ? 1 : -1;
        const px = sample.x + frame.normal.x * side * (edge.halfWidthM + 1.15);
        const pz = sample.z + frame.normal.z * side * (edge.halfWidthM + 1.15);
        if (!insideBounds(bounds, px, pz, 2)) continue;
        if (isInsideManhattanCity(px, pz, 2)) continue;
        plan.lamps.push({ x: px, z: pz, y: foundation.heightAt(px, pz), rotY: frame.yaw });
        collider({ kind: 'circle', x: px, z: pz, r: 0.28 });
      }
    }

    // Dry-stone walls (moor/farms/highlands) and fences (countryside)
    if (lodTier < 2) {
      for (let i = 2; i < edge.samples.length - 2; i++) {
        const sample = edge.samples[i];
        if (!insideBounds(bounds, sample.x, sample.z)) continue;
        if (sample.s % 7.5 > 5.2) continue;
        const district = foundation.getDistrict(sample.x, sample.z);
        const biome = district?.biome || 'countryside';
        const wallBiome = biome === 'moor' || biome === 'highlands' || biome === 'farms';
        if (!wallBiome && biome !== 'countryside') continue;
        const frame = sampleFrame(edge, i);
        for (const side of [-1, 1]) {
          if (rng() > 0.52) continue;
          const px = sample.x + frame.normal.x * side * (edge.halfWidthM + 2.3);
          const pz = sample.z + frame.normal.z * side * (edge.halfWidthM + 2.3);
          if (!insideBounds(bounds, px, pz, 2)) continue;
          if (isInsideManhattanCity(px, pz, 2)) continue;
          const py = foundation.heightAt(px, pz);
          if (py < 0.35) continue;
          plan.walls.push({
            // Wall/fence archetypes stretch along local +X, hence yaw - 90°.
            x: px, z: pz, y: py, rotY: frame.yaw - Math.PI / 2, len: 7.5,
            kind: wallBiome ? 'stone' : 'fence',
          });
        }
      }
    }
  }

  // --- Landmarks -------------------------------------------------------------
  addCastleIfInChunk(foundation, chunk, plan, collider);
  addFestivalIfInChunk(foundation, chunk, plan, collider, rngForChunk(foundation.seed ^ 0xFE57, cx, cz));

  if (centreDistrict?.biome === 'urban' && plan.buildings.length === 0
    && !isInsideManhattanCity(chunk.center.x, chunk.center.z)) {
    // Dense centre chunks without road samples still get a skyline block.
    const x = chunk.center.x;
    const z = chunk.center.z;
    const y = foundation.heightAt(x, z);
    plan.buildings.push({
      x, z, y: y - 0.25, rotY: rng() * Math.PI, yOff: 0, w: 18, d: 16, h: 24, roofH: 0,
      kind: 'block', tint: BUILDING_TINTS[4], roofTint: ROOF_TINTS[1],
    });
    collider({ kind: 'obb', x, z, halfWidthM: 9, halfDepthM: 8, rotationY: 0 });
  }

  return plan;
}

function addCastleIfInChunk(foundation, chunk, plan, collider) {
  const node = foundation.roadGraph.nodesById.get('castle');
  if (!node || !insideBounds(chunk.bounds, node.x, node.z, 30)) return;
  const cxp = node.x + 10;
  const czp = node.z - 16;
  if (!insideBounds(chunk.bounds, cxp, czp, 10)) return;
  const baseY = foundation.heightAt(cxp, czp) - 0.4;
  const rotY = 0.35;
  plan.buildings.push({
    x: cxp, z: czp, y: baseY, rotY, yOff: 0, w: 17, d: 13, h: 21, roofH: 4.5,
    kind: 'keep', tint: [0.62, 0.6, 0.58], roofTint: [0.3, 0.3, 0.36],
  });
  collider({ kind: 'obb', x: cxp, z: czp, halfWidthM: 8.5, halfDepthM: 6.5, rotationY: rotY });
  const cos = Math.cos(rotY);
  const sin = Math.sin(rotY);
  for (const [lx, lz] of [[-9, -7], [9, -7], [-9, 7], [9, 7]]) {
    const tx = cxp + lx * cos + lz * sin;
    const tz = czp - lx * sin + lz * cos;
    plan.towers.push({ x: tx, z: tz, y: baseY, rotY, s: 2.7, sy: 6.0, tint: [0.62, 0.6, 0.58] });
    collider({ kind: 'circle', x: tx, z: tz, r: 2.9 });
  }
  for (const [lx, lz, len, yawOff] of [[0, -11, 22, 0], [0, 11, 22, 0], [-13, 0, 22, Math.PI / 2], [13, 0, 22, Math.PI / 2]]) {
    const wx = cxp + lx * cos + lz * sin;
    const wz = czp - lx * sin + lz * cos;
    plan.walls.push({ x: wx, z: wz, y: baseY, rotY: rotY + yawOff, len, kind: 'castleWall' });
    collider({ kind: 'obb', x: wx, z: wz, halfWidthM: len / 2, halfDepthM: 0.8, rotationY: rotY + yawOff });
  }
}

function addFestivalIfInChunk(foundation, chunk, plan, collider, rng) {
  const edge = foundation.roadGraph.edgesById.get('festival-north-festival');
  if (edge) {
    const targetS = Math.max(0, edge.lengthM - 70);
    let idx = edge.samples.findIndex((s) => s.s >= targetS);
    if (idx > 1) {
      const sample = edge.samples[idx];
      if (insideBounds(chunk.bounds, sample.x, sample.z)) {
        const frame = sampleFrame(edge, idx);
        const half = edge.halfWidthM + 1.7;
        for (const side of [-1, 1]) {
          const px = sample.x + frame.normal.x * side * half;
          const pz = sample.z + frame.normal.z * side * half;
          plan.buildings.push({
            x: px, z: pz, y: foundation.heightAt(px, pz) - 0.1, rotY: frame.yaw, yOff: 0,
            w: 0.9, d: 0.9, h: 6.2, roofH: 0, kind: 'archPillar',
            tint: side < 0 ? [1.0, 0.45, 0.75] : [0.3, 0.85, 1.0], roofTint: [1, 1, 1],
          });
          collider({ kind: 'circle', x: px, z: pz, r: 0.85 });
        }
        plan.buildings.push({
          x: sample.x, z: sample.z, y: foundation.heightAt(sample.x, sample.z), rotY: frame.yaw, yOff: 5.5,
          w: half * 2 + 1.4, d: 1.1, h: 1.5, roofH: 0, kind: 'archTop',
          tint: [1.0, 0.62, 0.25], roofTint: [1, 1, 1], collide: false,
        });
      }
    }
  }

  const node = foundation.roadGraph.nodesById.get('festival');
  if (!node) return;
  const tentColors = [[1, 0.45, 0.7], [0.35, 0.85, 1], [1, 0.75, 0.3], [0.6, 1, 0.55], [0.85, 0.55, 1]];
  for (let i = 0; i < 12; i++) {
    const angle = (i / 12) * Math.PI * 2 + rng() * 0.3;
    const radius = 48 + rng() * 55;
    const x = node.x + Math.cos(angle) * radius;
    const z = node.z + Math.sin(angle) * radius;
    if (!insideBounds(chunk.bounds, x, z, 4)) continue;
    const near = foundation.nearestRoad(x, z, { maxDistanceM: 40 });
    if (near && near.edgeDistanceM < 5) continue;
    const y = foundation.heightAt(x, z);
    plan.tents.push({ x, z, y, rotY: rng() * Math.PI * 2, s: 2.6 + rng() * 1.4, tint: tentColors[i % tentColors.length] });
    collider({ kind: 'circle', x, z, r: 2.6 });
  }
}

/* ================= Archetype geometry (pure data) ================= */

function createGeometryBuilder() {
  const positions = [];
  const colors = [];
  const uvs = [];
  let hasUv = false;

  function tri(a, b, c, color, uvTri = null) {
    positions.push(a[0], a[1], a[2], b[0], b[1], b[2], c[0], c[1], c[2]);
    for (let i = 0; i < 3; i++) colors.push(color[0], color[1], color[2]);
    if (uvTri) {
      hasUv = true;
      uvs.push(...uvTri[0], ...uvTri[1], ...uvTri[2]);
    } else {
      uvs.push(0, 0, 0, 0, 0, 0);
    }
  }
  function quad(a, b, c, d, color, withUv = false) {
    const uv1 = withUv ? [[0, 0], [1, 0], [1, 1]] : null;
    const uv2 = withUv ? [[0, 0], [1, 1], [0, 1]] : null;
    tri(a, b, c, color, uv1);
    tri(a, c, d, color, uv2);
  }
  function box(cx, cy, cz, w, h, d, color, withUv = false) {
    const x0 = cx - w / 2; const x1 = cx + w / 2;
    const y0 = cy; const y1 = cy + h;
    const z0 = cz - d / 2; const z1 = cz + d / 2;
    quad([x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1], color, withUv); // +Z
    quad([x1, y0, z0], [x0, y0, z0], [x0, y1, z0], [x1, y1, z0], color, withUv); // -Z
    quad([x1, y0, z1], [x1, y0, z0], [x1, y1, z0], [x1, y1, z1], color, withUv); // +X
    quad([x0, y0, z0], [x0, y0, z1], [x0, y1, z1], [x0, y1, z0], color, withUv); // -X
    quad([x0, y1, z1], [x1, y1, z1], [x1, y1, z0], [x0, y1, z0], color, withUv); // top
  }
  function cylinder(cx, cy, cz, rBottom, rTop, h, segs, color, capTop = true) {
    for (let i = 0; i < segs; i++) {
      const a0 = (i / segs) * Math.PI * 2;
      const a1 = ((i + 1) / segs) * Math.PI * 2;
      const p = (r, a, y) => [cx + Math.cos(a) * r, y, cz + Math.sin(a) * r];
      quad(p(rBottom, a0, cy), p(rBottom, a1, cy), p(rTop, a1, cy + h), p(rTop, a0, cy + h), color);
      if (capTop && rTop > 0.001) tri([cx, cy + h, cz], p(rTop, a1, cy + h), p(rTop, a0, cy + h), color);
    }
  }
  function pyramid(cx, cy, cz, w, h, d, color) {
    const x0 = cx - w / 2; const x1 = cx + w / 2;
    const z0 = cz - d / 2; const z1 = cz + d / 2;
    const apex = [cx, cy + h, cz];
    tri([x0, cy, z1], [x1, cy, z1], apex, color);
    tri([x1, cy, z0], [x0, cy, z0], apex, color);
    tri([x1, cy, z1], [x1, cy, z0], apex, color);
    tri([x0, cy, z0], [x0, cy, z1], apex, color);
  }
  function sphere(cx, cy, cz, r, color, { squashY = 1, seed = 1 } = {}) {
    const rngS = mulberry32(seed);
    const lonSegs = 6;
    const latSegs = 4;
    const pt = (lon, lat) => {
      const theta = (lon / lonSegs) * Math.PI * 2;
      const phi = (lat / latSegs) * Math.PI;
      const jitter = 1 + (rngS() - 0.5) * 0.16;
      const rr = r * jitter;
      return [
        cx + rr * Math.sin(phi) * Math.cos(theta),
        cy + rr * Math.cos(phi) * squashY,
        cz + rr * Math.sin(phi) * Math.sin(theta),
      ];
    };
    for (let lat = 0; lat < latSegs; lat++) {
      for (let lon = 0; lon < lonSegs; lon++) {
        quad(pt(lon, lat), pt(lon + 1, lat), pt(lon + 1, lat + 1), pt(lon, lat + 1), color);
      }
    }
  }
  function build() {
    const pos = new Float32Array(positions);
    const col = new Float32Array(colors);
    const normals = new Float32Array(pos.length);
    for (let i = 0; i < pos.length; i += 9) {
      const ax = pos[i]; const ay = pos[i + 1]; const az = pos[i + 2];
      const bx = pos[i + 3]; const by = pos[i + 4]; const bz = pos[i + 5];
      const cx2 = pos[i + 6]; const cy2 = pos[i + 7]; const cz2 = pos[i + 8];
      const e1x = bx - ax; const e1y = by - ay; const e1z = bz - az;
      const e2x = cx2 - ax; const e2y = cy2 - ay; const e2z = cz2 - az;
      let nx = e1y * e2z - e1z * e2y;
      let ny = e1z * e2x - e1x * e2z;
      let nz = e1x * e2y - e1y * e2x;
      const l = Math.hypot(nx, ny, nz) || 1;
      nx /= l; ny /= l; nz /= l;
      for (let k = 0; k < 3; k++) {
        normals[i + k * 3] = nx;
        normals[i + k * 3 + 1] = ny;
        normals[i + k * 3 + 2] = nz;
      }
    }
    return {
      positions: pos,
      normals,
      colors: col,
      uvs: hasUv ? new Float32Array(uvs) : null,
      vertexCount: pos.length / 3,
      triangleCount: pos.length / 9,
    };
  }
  return { tri, quad, box, cylinder, pyramid, sphere, build };
}

const TRUNK = [0.32, 0.22, 0.14];

export function buildOakGeometry() {
  const g = createGeometryBuilder();
  g.cylinder(0, 0, 0, 0.34, 0.2, 2.3, 6, TRUNK);
  g.sphere(0, 3.7, 0, 1.95, [0.24, 0.46, 0.18], { seed: 11 });
  g.sphere(0.95, 2.95, 0.35, 1.2, [0.3, 0.52, 0.2], { seed: 23 });
  g.sphere(-0.85, 3.05, -0.4, 1.1, [0.2, 0.42, 0.16], { seed: 37 });
  return g.build();
}
export function buildPineGeometry() {
  const g = createGeometryBuilder();
  g.cylinder(0, 0, 0, 0.26, 0.15, 1.7, 6, TRUNK);
  g.cylinder(0, 1.5, 0, 1.55, 0.02, 2.3, 8, [0.13, 0.32, 0.16], false);
  g.cylinder(0, 2.9, 0, 1.18, 0.02, 2.0, 8, [0.16, 0.37, 0.18], false);
  g.cylinder(0, 4.2, 0, 0.8, 0.02, 1.7, 8, [0.19, 0.42, 0.2], false);
  return g.build();
}
export function buildBushGeometry() {
  const g = createGeometryBuilder();
  g.sphere(0, 0.55, 0, 0.95, [0.26, 0.44, 0.2], { squashY: 0.65, seed: 51 });
  return g.build();
}
export function buildRockGeometry() {
  const g = createGeometryBuilder();
  g.sphere(0, 0.35, 0, 1.05, [0.45, 0.44, 0.42], { squashY: 0.72, seed: 77 });
  return g.build();
}
export function buildTowerGeometry() {
  const g = createGeometryBuilder();
  g.cylinder(0, 0, 0, 1, 0.92, 3, 9, [0.62, 0.6, 0.58]);
  g.cylinder(0, 3, 0, 1.28, 0.02, 1.15, 9, [0.3, 0.3, 0.36], false);
  return g.build();
}
export function buildTentGeometry() {
  const g = createGeometryBuilder();
  g.cylinder(0, 0, 0, 1, 1, 0.32, 9, [0.95, 0.93, 0.9], false);
  g.cylinder(0, 0.3, 0, 1.06, 0.03, 1.05, 9, [1, 1, 1], false);
  return g.build();
}
export function buildLampPoleGeometry() {
  const g = createGeometryBuilder();
  g.cylinder(0, 0, 0, 0.09, 0.06, 1, 6, [0.16, 0.17, 0.19], false);
  return g.build();
}
export function buildLampHeadGeometry() {
  const g = createGeometryBuilder();
  g.sphere(0, 0, 0, 0.17, [1, 0.85, 0.55], { seed: 5 });
  return g.build();
}
export function buildWallGeometry() {
  const g = createGeometryBuilder();
  g.box(0, 0, 0, 1, 1, 1, [0.52, 0.5, 0.47]);
  return g.build();
}
export function buildFenceGeometry() {
  const g = createGeometryBuilder();
  const wood = [0.42, 0.3, 0.19];
  g.box(0, 0.72, 0, 7.5, 0.09, 0.07, wood);
  g.box(0, 0.38, 0, 7.5, 0.09, 0.07, wood);
  for (const px of [-3.4, -1.15, 1.15, 3.4]) g.box(px, 0, 0, 0.14, 0.95, 0.14, wood);
  return g.build();
}
export function buildBuildingBodyGeometry() {
  const g = createGeometryBuilder();
  g.box(0, 0, 0, 1, 1, 1, [1, 1, 1], true);
  return g.build();
}
export function buildBuildingRoofGeometry() {
  const g = createGeometryBuilder();
  g.pyramid(0, 0, 0, 1, 1, 1, [1, 1, 1]);
  return g.build();
}

export function buildDressingArchetypes() {
  return {
    oak: buildOakGeometry(),
    pine: buildPineGeometry(),
    bush: buildBushGeometry(),
    rock: buildRockGeometry(),
    tower: buildTowerGeometry(),
    tent: buildTentGeometry(),
    lampPole: buildLampPoleGeometry(),
    lampHead: buildLampHeadGeometry(),
    wall: buildWallGeometry(),
    fence: buildFenceGeometry(),
    buildingBody: buildBuildingBodyGeometry(),
    buildingRoof: buildBuildingRoofGeometry(),
  };
}
