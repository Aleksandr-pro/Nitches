import test from 'node:test';
import assert from 'node:assert/strict';

import { createFestivalBritainFoundation } from '../../src/world/festivalBritain.js';
import { buildRoadRibbonGeometry } from '../../src/world/roadGraph.js';
import {
  MANHATTAN_CITY_BASE_HEIGHT_M,
  MANHATTAN_CITY_BOUNDS,
  MANHATTAN_CITY_CENTER,
  buildManhattanWorldColliders,
  isInsideManhattanCity,
  manhattanCityChunks,
  manhattanCityPlateauFactor,
  manhattanCityStats,
} from '../../src/world/manhattanCity.js';

const foundation = createFestivalBritainFoundation();

test('manhattan placement covers the Kingsford district centre', () => {
  assert.equal(MANHATTAN_CITY_CENTER.x, 1250);
  assert.equal(MANHATTAN_CITY_CENTER.z, -1050);
  assert.ok(isInsideManhattanCity(1250, -1050));
  assert.ok(!isInsideManhattanCity(0, 1250)); // festival spawn stays procedural
  const width = MANHATTAN_CITY_BOUNDS.maxX - MANHATTAN_CITY_BOUNDS.minX;
  const depth = MANHATTAN_CITY_BOUNDS.maxZ - MANHATTAN_CITY_BOUNDS.minZ;
  assert.ok(width >= 1197 && width <= 1220, `footprint width ${width}`);
  assert.ok(depth >= 994 && depth <= 1010, `footprint depth ${depth}`);
  assert.equal(manhattanCityPlateauFactor(1250, -1050), 1);
  assert.equal(manhattanCityPlateauFactor(0, 1250), 0);
  const apron = manhattanCityPlateauFactor(MANHATTAN_CITY_BOUNDS.minX - 45, -1050);
  assert.ok(apron > 0.4 && apron < 0.6, `blend apron factor ${apron}`);
});

test('foundation terrain is a flat plateau under the imported city', () => {
  const points = [
    [1250, -1050],
    [MANHATTAN_CITY_BOUNDS.minX + 5, MANHATTAN_CITY_BOUNDS.minZ + 5],
    [MANHATTAN_CITY_BOUNDS.maxX - 5, MANHATTAN_CITY_BOUNDS.maxZ - 5],
    [1000, -1300],
    [1700, -800],
  ];
  for (const [x, z] of points) {
    const h = foundation.heightAt(x, z);
    assert.ok(Math.abs(h - MANHATTAN_CITY_BASE_HEIGHT_M) < 1e-6, `height at ${x},${z}: ${h}`);
  }
  // Off the Kingsford road corridors the city plate drives as concrete.
  assert.equal(foundation.surfaceAt(1000, -1300).id, 'concrete');
  assert.equal(foundation.surfaceAt(1600, -800).id, 'concrete');
});

test('generated city data yields world colliders inside the footprint', () => {
  const stats = manhattanCityStats();
  assert.equal(stats.chunks, 18);
  assert.ok(stats.outputTriangles > 300000 && stats.outputTriangles <= 450000);
  assert.ok(stats.glbBytes > 10_000_000);
  assert.match(stats.glbSha256, /^[a-f0-9]{64}$/);

  const chunks = manhattanCityChunks();
  assert.equal(chunks.length, 18);
  for (const chunk of chunks) {
    assert.match(chunk.meshName, /^manhattan_\d{2}_\d{2}$/);
    assert.ok(chunk.triangles > 0, chunk.meshName);
    assert.ok(chunk.bounds.maxY <= 96.1, `${chunk.meshName} maxY ${chunk.bounds.maxY}`);
  }

  const colliders = buildManhattanWorldColliders();
  assert.equal(colliders.length, stats.colliders);
  assert.ok(colliders.length > 1500, `colliders ${colliders.length}`);
  const ids = new Set();
  for (const c of colliders) {
    assert.equal(c.kind, 'obb');
    assert.equal(c.rotationY, 0);
    assert.ok(c.halfWidthM > 0 && c.halfDepthM > 0);
    assert.ok(isInsideManhattanCity(c.x, c.z, 1), `collider centre ${c.x},${c.z}`);
    assert.ok(!ids.has(c.id), `duplicate id ${c.id}`);
    ids.add(c.id);
  }
});

test('road ribbons are masked inside the imported city footprint', () => {
  const innerEdge = foundation.roadGraph.edgesById.get('city-west-link');
  assert.ok(innerEdge, 'city-west-link edge exists');
  const unmasked = buildRoadRibbonGeometry(innerEdge, {});
  const masked = buildRoadRibbonGeometry(innerEdge, { excludeBounds: MANHATTAN_CITY_BOUNDS });
  assert.ok(unmasked.triangleCount > 0);
  assert.equal(masked.triangleCount, 0);

  const crossingEdge = foundation.roadGraph.edgesById.get('moor-east-city-west');
  assert.ok(crossingEdge, 'moor-east-city-west edge exists');
  const crossingFull = buildRoadRibbonGeometry(crossingEdge, {});
  const crossingMasked = buildRoadRibbonGeometry(crossingEdge, { excludeBounds: MANHATTAN_CITY_BOUNDS });
  assert.ok(crossingMasked.triangleCount > 0, 'approach road outside the city remains');
  assert.ok(
    crossingMasked.triangleCount < crossingFull.triangleCount,
    `masked ${crossingMasked.triangleCount} < full ${crossingFull.triangleCount}`,
  );
});
