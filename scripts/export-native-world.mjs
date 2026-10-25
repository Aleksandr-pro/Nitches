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
  districts: foundation.districts.filter((district) => district.x >= BOUNDS.minX),
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
  roads: buildRoads(),
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
