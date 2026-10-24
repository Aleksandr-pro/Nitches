import test from 'node:test';
import assert from 'node:assert/strict';

import { createFestivalBritainFoundation } from '../../src/world/festivalBritain.js';
import { buildDressingArchetypes, planChunkDressing } from '../../src/world/dressing.js';

const foundation = createFestivalBritainFoundation();

test('chunk dressing is deterministic for a seed', () => {
  const a = planChunkDressing(foundation, 8, 13);
  const b = planChunkDressing(foundation, 8, 13);
  assert.equal(a.trees.length, b.trees.length);
  assert.equal(a.buildings.length, b.buildings.length);
  assert.deepEqual(a.trees[0], b.trees[0]);
  assert.deepEqual(a.colliders[0], b.colliders[0]);
});

test('biomes shape the scatter: forest dense, moor rocky, city built-up', () => {
  const forest = planChunkDressing(foundation, 12, 11);
  const moor = planChunkDressing(foundation, 7, 2);
  const city = planChunkDressing(foundation, 13, 3);
  assert.ok(forest.trees.length > 60, `forest trees ${forest.trees.length}`);
  assert.ok(moor.rocks.length > forest.rocks.length);
  assert.ok(city.buildings.length > 8, `city buildings ${city.buildings.length}`);
  assert.ok(city.buildings.some((b) => b.kind === 'block' && b.h >= 10));
  assert.ok(city.lamps.length > 0);
});

test('dressing never lands on roads or in water', () => {
  for (const [cx, cz] of [[8, 13], [12, 11], [13, 3], [4, 9], [3, 3]]) {
    const plan = planChunkDressing(foundation, cx, cz);
    for (const item of [...plan.trees, ...plan.rocks]) {
      const near = foundation.nearestRoad(item.x, item.z, { maxDistanceM: 30 });
      assert.ok(!near || near.edgeDistanceM >= 1.5, `instance on road in ${cx}_${cz}`);
      assert.ok(foundation.heightAt(item.x, item.z) >= 0.3, `instance in water in ${cx}_${cz}`);
    }
    for (const b of plan.buildings) {
      const near = foundation.nearestRoad(b.x, b.z, { maxDistanceM: 40 });
      assert.ok(!near || near.edgeDistanceM >= 2, `building on road in ${cx}_${cz}`);
    }
  }
});

test('landmarks: castle keep with towers and the festival arch', () => {
  const castle = planChunkDressing(foundation, 11, 2);
  assert.equal(castle.buildings.filter((b) => b.kind === 'keep').length, 1);
  assert.equal(castle.towers.length, 4);
  assert.equal(castle.walls.filter((w) => w.kind === 'castleWall').length, 4);

  let archPillars = 0;
  let archTops = 0;
  for (const [cx, cz] of [[7, 12], [8, 12], [7, 13], [8, 13]]) {
    const plan = planChunkDressing(foundation, cx, cz);
    archPillars += plan.buildings.filter((b) => b.kind === 'archPillar').length;
    archTops += plan.buildings.filter((b) => b.kind === 'archTop').length;
  }
  assert.equal(archPillars, 2);
  assert.equal(archTops, 1);
});

test('every plan produces usable colliders with unique ids', () => {
  const plan = planChunkDressing(foundation, 13, 3);
  assert.ok(plan.colliders.length > 10);
  const ids = new Set(plan.colliders.map((c) => c.id));
  assert.equal(ids.size, plan.colliders.length);
  for (const c of plan.colliders) {
    assert.ok(['circle', 'obb'].includes(c.kind), `kind ${c.kind}`);
    assert.ok(c.id.startsWith('13_3:'));
  }
  assert.ok(plan.colliders.some((c) => c.kind === 'obb'));
});

test('far LOD drops small dressing but keeps silhouettes and colliders', () => {
  const near = planChunkDressing(foundation, 4, 9, { lodTier: 0 });
  const far = planChunkDressing(foundation, 4, 9, { lodTier: 2 });
  assert.equal(far.bushes.length, 0);
  assert.equal(far.walls.length, 0);
  assert.equal(far.trees.length, near.trees.length);
  assert.ok(far.colliders.length > 0);
});

test('archetype geometries are valid non-indexed meshes with colours', () => {
  const archetypes = buildDressingArchetypes();
  for (const [name, geo] of Object.entries(archetypes)) {
    assert.ok(geo.vertexCount > 0, name);
    assert.equal(geo.normals.length, geo.positions.length, name);
    assert.equal(geo.colors.length, geo.positions.length, name);
    assert.ok(geo.triangleCount > 0, name);
  }
  assert.ok(archetypes.buildingBody.uvs, 'building body carries facade UVs');
});
