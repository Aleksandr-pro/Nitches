import test from 'node:test';
import assert from 'node:assert/strict';

import { createRealWorldFoundation, riverCenterX } from '../../src/world/realWorld.js';

const foundation = createRealWorldFoundation();

test('Real Valley is a 1x1 km world with a dense street network', () => {
  const stats = foundation.stats();
  assert.equal(stats.worldSizeM, 1000);
  assert.equal(foundation.bounds.minX, -500);
  assert.equal(foundation.bounds.maxX, 500);
  assert.ok(stats.roadLengthM > 7500, `road length ${stats.roadLengthM}`);
  assert.ok(stats.roadEdges >= 85, `road edges ${stats.roadEdges}`);
  assert.ok(stats.districts >= 6);
  assert.ok(foundation.findRoute('drag-north', 'drift-3'), 'route drag strip -> drift zone exists');
  assert.ok(foundation.findRoute('west-gate', 'plaza-gate'), 'route highway -> festival exists');
});

test('reference-map infrastructure: roundabout, drift loop, drag strip', () => {
  const arcs = foundation.roadGraph.edges.filter((e) => e.id.startsWith('rb-arc'));
  assert.equal(arcs.length, 8, 'roundabout is a closed 8-arc ring');
  const loop = foundation.roadGraph.edges.filter((e) => e.id.startsWith('drift-loop'));
  assert.equal(loop.length, 7, 'drift circuit is a closed loop');
  const drag = foundation.roadGraph.edgesById.get('drag-strip');
  assert.ok(drag && drag.lengthM > 85, 'drag strip edge exists');
  assert.ok(foundation.roadGraph.edgesById.get('alley-v-0'), 'N-S mid-block alley exists');
  assert.ok(foundation.roadGraph.edgesById.get('alley-h-0'), 'E-W mid-block alley exists');
  assert.ok(foundation.findRoute('ax3', 'south-gate'), 'alley junctions are graph-connected');
  const parkingAreas = foundation.dressingPlan.pavedAreas.filter((a) => a.kind === 'parking');
  assert.ok(parkingAreas.length >= 6, `parking lots ${parkingAreas.length}`);
  assert.equal(foundation.getDistrict(-292, 338)?.id, 'drift-zone');
  assert.equal(foundation.getDistrict(0, -390)?.id, 'drag-strip');
  assert.equal(foundation.getDistrict(390, -160)?.id, 'festival');
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

test('heights and surfaces: flat city, sunken river, paved plaza', () => {
  assert.ok(Math.abs(foundation.heightAt(0, -110) - 3.6) < 1.6, 'city centre is nearly flat');
  const rx = riverCenterX(0);
  assert.ok(foundation.heightAt(rx, 0) < -0.5, 'river bed below water level');
  assert.equal(foundation.surfaceAt(rx, 0).id, 'water');
  assert.equal(foundation.surfaceAt(0, -110).id, 'asphalt', 'central avenue');
  assert.equal(foundation.surfaceAt(390, -170).id, 'concrete', 'festival plaza');
  assert.equal(foundation.surfaceAt(390, 110).id, 'concrete', 'main parking');
  // Highway crosses the river on the land bridge, not in the water.
  assert.ok(foundation.heightAt(riverCenterX(225), 225) > 1.5, 'bridge causeway stays dry');
});

test('spawn is on the avenue heading into the city', () => {
  const spawn = foundation.spawnPoint();
  assert.ok(Math.abs(spawn.x) < 500 && Math.abs(spawn.z) < 500);
  assert.equal(foundation.surfaceAt(spawn.x, spawn.z).id, 'asphalt');
  assert.ok(Math.abs(Math.abs(spawn.yaw) - Math.PI) < 0.2, `heading north, yaw=${spawn.yaw}`);
});

test('dressing plan is dense and buildings keep off the asphalt', () => {
  const plan = foundation.dressingPlan;
  assert.ok(plan.buildings.length >= 100, `buildings ${plan.buildings.length}`);
  assert.ok(plan.trees.length >= 500, `trees ${plan.trees.length}`);
  assert.ok(plan.lamps.length >= 80, `lamps ${plan.lamps.length}`);
  assert.ok(plan.festival.tents.length >= 8, 'festival tents planned');
  assert.ok(plan.festival.stage, 'festival stage planned');
  assert.ok(plan.busStops.length >= 12, `bus stops ${plan.busStops.length}`);
  assert.ok(plan.benches.length >= 14, `benches ${plan.benches.length}`);
  assert.ok(plan.hedges.length >= 24, `hedges ${plan.hedges.length}`);
  assert.ok(plan.lamps.every((l) => l.side === 1 || l.side === -1), 'lamps know their road side');
  assert.ok(plan.signs.length >= 16, `road signs ${plan.signs.length}`);
  assert.ok(plan.bins.length >= 18, `litter bins ${plan.bins.length}`);
  assert.ok(plan.bollards.length >= 14, `bollards ${plan.bollards.length}`);
  assert.ok(plan.fences.length >= 20, `fences ${plan.fences.length}`);
  assert.ok(plan.powerPoles.length >= 20, `power poles ${plan.powerPoles.length}`);
  const poleGroups = new Set(plan.powerPoles.map((p) => p.group));
  assert.ok(poleGroups.size >= 3, 'power lines form chains');
  const kinds = new Set(plan.buildings.map((b) => b.kind));
  assert.ok(kinds.has('shop') && kinds.has('cafe'), 'shop and cafe landmarks exist');
  const facades = new Set(plan.buildings.map((b) => b.facade));
  assert.ok(facades.size >= 7, `facade variety: ${[...facades].join(',')}`);
  for (const b of plan.buildings) {
    const near = foundation.nearestRoad(b.x, b.z, { maxDistanceM: 80 });
    assert.ok(!near || near.edgeDistanceM > 1, `building at ${b.x},${b.z} intrudes on a road`);
    assert.ok(b.h >= 4 && b.w >= 7, 'real-metre building sizes');
  }
});
