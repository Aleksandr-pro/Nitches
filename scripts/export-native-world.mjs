#!/usr/bin/env node
/**
 * Exports the deterministic RichTown layout used by the legacy web build into
 * a compact, engine-neutral JSON document for the native Godot project.
 *
 * The Godot game does not execute or depend on the Three.js renderer.  This
 * script is a one-way data bridge so the real-metre city layout, road samples
 * and terrain heights that already exist in the repository can be reused
 * while every native runtime system is implemented from scratch in GDScript.
 */
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { createRealWorldFoundation } from '../src/world/realWorld.js';

const outputPath = process.argv[2] ?? 'native/data/richtown_native.json';
const foundation = createRealWorldFoundation();
const plan = foundation.dressingPlan;

const BOUNDS = { minX: 520, maxX: 1500, minZ: -500, maxZ: 500 };
const TERRAIN_STEP_M = 10;

const round = (value, places = 3) => {
  const scale = 10 ** places;
  return Math.round((Number(value) + Number.EPSILON) * scale) / scale;
};

const inBounds = (item, margin = 0) => (
  item.x >= BOUNDS.minX - margin
  && item.x <= BOUNDS.maxX + margin
  && item.z >= BOUNDS.minZ - margin
  && item.z <= BOUNDS.maxZ + margin
);

const point = (item, extra = {}) => ({
  x: round(item.x),
  y: round(item.y ?? foundation.heightAt(item.x, item.z)),
  z: round(item.z),
  rotY: round(item.rotY ?? 0, 5),
  ...extra,
});

function buildTerrain() {
  const cols = Math.floor((BOUNDS.maxX - BOUNDS.minX) / TERRAIN_STEP_M) + 1;
  const rows = Math.floor((BOUNDS.maxZ - BOUNDS.minZ) / TERRAIN_STEP_M) + 1;
  const heights = new Array(cols * rows);
  for (let iz = 0; iz < rows; iz += 1) {
    const z = BOUNDS.minZ + iz * TERRAIN_STEP_M;
    for (let ix = 0; ix < cols; ix += 1) {
      const x = BOUNDS.minX + ix * TERRAIN_STEP_M;
      heights[iz * cols + ix] = round(foundation.heightAt(x, z), 3);
    }
  }
  return {
    ...BOUNDS,
    stepM: TERRAIN_STEP_M,
    cols,
    rows,
    heights,
  };
}

function decimateRoadSamples(edge) {
  const result = [];
  let last = null;
  for (const sample of edge.samples ?? []) {
    if (!inBounds(sample, 40)) continue;
    if (!last || Math.hypot(sample.x - last.x, sample.z - last.z) >= 4.5) {
      result.push([
        round(sample.x),
        round(sample.y ?? foundation.heightAt(sample.x, sample.z)),
        round(sample.z),
      ]);
      last = sample;
    }
  }
  const tail = (edge.samples ?? []).at(-1);
  if (tail && inBounds(tail, 40)) {
    const tailPoint = [
      round(tail.x),
      round(tail.y ?? foundation.heightAt(tail.x, tail.z)),
      round(tail.z),
    ];
    if (JSON.stringify(result.at(-1)) !== JSON.stringify(tailPoint)) result.push(tailPoint);
  }
  return result;
}

function buildRoads() {
  return foundation.roadGraph.edges
    .filter((edge) => edge.id.startsWith('rt-'))
    .map((edge) => ({
      id: edge.id,
      name: edge.name ?? edge.id,
      widthM: round(edge.widthM ?? (edge.halfWidthM ?? 5) * 2, 2),
      lanes: edge.lanes ?? 2,
      speedLimitKmh: edge.speedLimitKmh ?? 50,
      samples: decimateRoadSamples(edge),
    }))
    .filter((edge) => edge.samples.length >= 2);
}

// ---------------------------------------------------------------------------
// 0.2.24 district streets.  The exported master plan only had the coarse
// 170--205 m arterial grid: whole villa blocks stood 40--80 m from the
// nearest carriageway with no local street, driveway or frontage at all.
// These native-only streets are threaded through the *existing* building
// rows (every corridor below was checked against the exported building,
// pool and landmark footprints):
//
//   * South Villa District (x 560..760, z 225..430): two new east-west
//     streets in the clear bands between the villa rows (z=286 between
//     the z~266 and z~306 rows, z=368 between the z~350 and z~389 rows),
//     two north-south locals between the building columns (x=638, split
//     around the mosque forecourt at x=620,z=335, and x~689 with a gentle
//     eastward chicane around the pool at x=681,z=390), plus a rounded
//     southern crescent that extends the built-up street network from
//     z=430 to z~457.
//   * Palm Island locals: the trunk is extended to the hotel frontage and
//     short curved connectors finally give the western frond villas a street
//     address instead of open grass.
//
// Points are Catmull-Rom sampled exactly like src/world/roadGraph.js, so
// bends are genuine curves in the exported samples, not polylines.
function catmullPoint(p0, p1, p2, p3, t) {
  const t2 = t * t;
  const t3 = t2 * t;
  return [
    0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t
      + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
      + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3),
    0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t
      + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
      + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3),
  ];
}

function sampleDistrictPath(points, spacingM = 3.5) {
  const samples = [];
  for (let i = 0; i < points.length - 1; i += 1) {
    const p0 = points[Math.max(0, i - 1)];
    const p1 = points[i];
    const p2 = points[i + 1];
    const p3 = points[Math.min(points.length - 1, i + 2)];
    const rough = Math.hypot(p2[0] - p1[0], p2[1] - p1[1]);
    const divisions = Math.max(1, Math.ceil(rough / spacingM));
    for (let j = (i === 0 ? 0 : 1); j <= divisions; j += 1) {
      const [x, z] = catmullPoint(p0, p1, p2, p3, j / divisions);
      const prev = samples[samples.length - 1];
      if (prev && Math.hypot(x - prev[0], z - prev[2]) < 0.05) continue;
      samples.push([round(x), round(foundation.heightAt(x, z)), round(z)]);
    }
  }
  return samples;
}

function districtRoad(id, name, widthM, points, speedLimitKmh = 30) {
  return {
    id,
    name,
    widthM,
    lanes: 2,
    speedLimitKmh,
    samples: sampleDistrictPath(points),
  };
}

function buildDistrictRoads() {
  return [
    // South Villa District grid (see header comment for the clear bands).
    districtRoad('rt-villa-st-286', 'Villa District East-West 286', 9,
      [[560, 286], [660, 286], [760, 286]]),
    districtRoad('rt-villa-st-368', 'Villa District East-West 368', 9,
      [[560, 368], [660, 368], [760, 368]]),
    districtRoad('rt-villa-west-n', 'Villa District West (north)', 8,
      [[638, 225], [638, 268], [638, 312]]),
    districtRoad('rt-villa-west-s', 'Villa District West (south)', 8,
      [[640.5, 358], [640.5, 394], [640.5, 430]]),
    districtRoad('rt-villa-east', 'Villa District East', 8,
      [[689, 225], [689, 300], [687, 345], [689, 364], [692, 378], [694, 390], [692, 402], [688, 416], [686, 430]]),
    districtRoad('rt-villa-crescent', 'Villa District Southern Crescent', 8,
      [[640.5, 430], [640.5, 443], [646, 452], [656, 457], [670, 457], [680, 452], [686, 443], [686, 430]]),
    // Palm Island local connectors.
    districtRoad('rt-palm-local-centre', 'Palm Island Hotel Frontage', 9,
      [[1395, -250], [1411, -250], [1428, -250]], 40),
    districtRoad('rt-palm-local-nw', 'Palm Island North-West Frond', 8,
      [[1395, -345], [1379, -350], [1364, -352]], 30),
    districtRoad('rt-palm-local-sw', 'Palm Island South-West Frond', 8,
      [[1395, -155], [1381, -146], [1368, -136], [1359, -129]], 30),
  ];
}

function distanceSquaredTo(item, x, z) {
  return (item.x - x) ** 2 + (item.z - z) ** 2;
}

function buildBuildings() {
  const richtownBuildings = plan.buildings.filter((building) => inBounds(building));

  const villaSet = new Set(
    richtownBuildings
      .filter((b) => b.kind === 'rt-villa' && b.w <= 25 && b.d <= 18 && (b.h + (b.roofH || 0)) <= 11)
      .sort((a, c) => (
        ((a.x > 1100 ? 0 : 1_000_000) + distanceSquaredTo(a, 760, 60))
        - ((c.x > 1100 ? 0 : 1_000_000) + distanceSquaredTo(c, 760, 60))
      ))
      .slice(0, 14),
  );

  const glassTowerSet = new Set(
    richtownBuildings
      .filter((b) => b.kind === 'rt-tower')
      .sort((a, c) => distanceSquaredTo(a, 760, 60) - distanceSquaredTo(c, 760, 60))
      .slice(0, 8),
  );

  return richtownBuildings.map((building) => ({
    ...point(building),
    w: round(building.w, 2),
    d: round(building.d, 2),
    h: round(building.h, 2),
    roofH: round(building.roofH ?? 0, 2),
    kind: building.kind,
    facade: building.facade ?? 'userPlaster',
    tint: round(building.tint ?? 1, 3),
    model: villaSet.has(building)
      ? 'villa'
      : glassTowerSet.has(building)
        ? 'glass_tower'
        : 'generic',
  }));
}

const simpleFiltered = (items, mapper = (item) => point(item)) => (
  (items ?? []).filter((item) => inBounds(item)).map(mapper)
);

const world = {
  schemaVersion: 1,
  name: 'RichTown Native Alpha',
  units: 'metres',
  seed: foundation.seed,
  bounds: BOUNDS,
  spawn: {
    x: 760,
    y: round(foundation.heightAt(760, 330) + 1.1),
    z: 330,
    // Godot vehicle bodies drive towards local -Z; zero faces the car north
    // along RichTown Boulevard towards the arch and downtown core.
    yaw: 0,
  },
  districts: [
    ...foundation.districts.filter((district) => district.x >= BOUNDS.minX),
    { id: 'south-villa-district', name: 'South Villa District', x: 662, z: 340, radiusM: 145, biome: 'urban' },
  ],
  zones: {
    marina: foundation.zones.marina,
    sea: foundation.zones.sea,
    beach: foundation.zones.beach,
    palmIsland: foundation.zones.palmIsland,
    sailIsland: foundation.zones.sailIsland,
    rtPlaza: foundation.zones.rtPlaza,
    richtown: foundation.zones.richtown,
  },
  terrain: buildTerrain(),
  roads: [...buildRoads(), ...buildDistrictRoads()],
  buildings: buildBuildings(),
  landmarks: simpleFiltered(plan.landmarks, (item) => ({
    ...point(item),
    kind: item.kind,
    h: round(item.h ?? 0, 2),
    r: round(item.r ?? 0, 2),
  })),
  pools: simpleFiltered(plan.pools, (item) => ({
    ...point(item),
    w: round(item.w, 2),
    d: round(item.d, 2),
  })),
  trees: simpleFiltered(plan.trees, (item) => ({
    ...point(item),
    s: round(item.s ?? 1, 3),
    type: item.type ?? 'tree',
    tint: round(item.tint ?? 1, 3),
  })),
  bushes: simpleFiltered(plan.bushes, (item) => ({
    ...point(item),
    s: round(item.s ?? 1, 3),
    tint: round(item.tint ?? 1, 3),
  })),
  palms: simpleFiltered(plan.palms, (item) => ({
    ...point(item),
    s: round(item.s ?? 1, 3),
  })),
  lamps: simpleFiltered(plan.lamps, (item) => ({
    ...point(item),
    side: item.side ?? 1,
  })),
  benches: simpleFiltered(plan.benches),
};

world.stats = {
  terrainVertices: world.terrain.cols * world.terrain.rows,
  roadEdges: world.roads.length,
  roadSamples: world.roads.reduce((sum, road) => sum + road.samples.length, 0),
  buildings: world.buildings.length,
  blenderVillas: world.buildings.filter((b) => b.model === 'villa').length,
  blenderGlassTowers: world.buildings.filter((b) => b.model === 'glass_tower').length,
  genericBuildings: world.buildings.filter((b) => b.model === 'generic').length,
  landmarks: world.landmarks.length,
  pools: world.pools.length,
  trees: world.trees.length,
  bushes: world.bushes.length,
  palms: world.palms.length,
  lamps: world.lamps.length,
  benches: world.benches.length,
};

await mkdir(path.dirname(outputPath), { recursive: true });
await writeFile(outputPath, `${JSON.stringify(world)}\n`, 'utf8');
console.log(`Native world written to ${outputPath}`);
console.log(JSON.stringify(world.stats, null, 2));
