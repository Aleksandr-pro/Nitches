import test from 'node:test';
import assert from 'node:assert/strict';

import { createRealWorldFoundation } from '../../src/world/realWorld.js';

const foundation = createRealWorldFoundation();

test('Real Valley is a 1x1 km world with a road network and districts', () => {
  const stats = foundation.stats();
  assert.equal(stats.worldSizeM, 1000);
  assert.equal(foundation.bounds.minX, -500);
  assert.equal(foundation.bounds.maxX, 500);
  assert.ok(stats.roadLengthM > 4000, `road length ${stats.roadLengthM}`);
  assert.ok(stats.districts >= 5);
  assert.ok(foundation.findRoute('westgate', 'viewpoint'), 'route to the viewpoint exists');
});

test('road profiles respect the maximum grade', () => {
  for (const e of foundation.roadGraph.edges) {
    for (let i = 1; i < e.samples.length; i++) {
      const a = e.samples[i - 1];
      const b = e.samples[i];
      const ds = Math.max(b.s - a.s, 0.5);
      const grade = Math.abs((b.y - a.y) / ds);
      assert.ok(grade <= 0.165, `${e.id} sample ${i} grade ${grade.toFixed(3)}`);
    }
  }
});

test('heights and surfaces: flat town, sunken lake, high viewpoint', () => {
  assert.ok(Math.abs(foundation.heightAt(0, 0) - 6.4) < 2, 'town centre is nearly flat');
  assert.ok(foundation.heightAt(330, 330) < -1.5, 'lake bed below water level');
  assert.ok(foundation.heightAt(-405, -405) > 45, 'viewpoint is high');
  assert.equal(foundation.surfaceAt(0, 0).id, 'asphalt');
  assert.equal(foundation.surfaceAt(330, 330).id, 'water');
});

test('spawn is on a road inside the world', () => {
  const spawn = foundation.spawnPoint();
  assert.ok(Math.abs(spawn.x) < 500 && Math.abs(spawn.z) < 500);
  assert.equal(foundation.surfaceAt(spawn.x, spawn.z).id, 'asphalt');
  assert.ok(Number.isFinite(spawn.yaw));
});

test('dressing plan is populated and buildings keep off the asphalt', () => {
  const plan = foundation.dressingPlan;
  assert.ok(plan.buildings.length >= 60, `buildings ${plan.buildings.length}`);
  assert.ok(plan.trees.length >= 400, `trees ${plan.trees.length}`);
  assert.ok(plan.rocks.length >= 80);
  assert.ok(plan.lamps.length >= 30);
  for (const b of plan.buildings) {
    const near = foundation.nearestRoad(b.x, b.z, { maxDistanceM: 80 });
    assert.ok(!near || near.edgeDistanceM > 1, `building at ${b.x},${b.z} intrudes on a road`);
    assert.ok(b.h >= 4 && b.w >= 7, 'real-metre building sizes');
  }
});
