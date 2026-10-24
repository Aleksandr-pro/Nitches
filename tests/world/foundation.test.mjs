import test from 'node:test';
import assert from 'node:assert/strict';

import { createFestivalBritainFoundation } from '../../src/world/festivalBritain.js';
import { getReachableNodeIds } from '../../src/world/roadGraph.js';
import { buildTerrainTileGeometry, mergeGeometryData } from '../../src/world/meshBuilders.js';
import {
  MANHATTAN_CITY_BASE_HEIGHT_M,
  manhattanCityPlateauFactor,
} from '../../src/world/manhattanCity.js';

const foundation = createFestivalBritainFoundation();

test('foundation road network spans the whole map and is fully connected', () => {
  const stats = foundation.stats();
  assert.equal(stats.chunks, 256);
  assert.equal(stats.districts, 10);
  assert.ok(stats.roadLengthM > 35000, `core network ${(stats.roadLengthM / 1000).toFixed(1)} km`);
  assert.ok(stats.roadSegments > 5000);
  assert.ok(stats.chunksWithRoads > 100);

  const reachable = getReachableNodeIds(foundation.roadGraph, 'festival');
  assert.equal(reachable.size, foundation.roadGraph.nodes.length);
  for (const districtNode of ['city', 'castle', 'lake-town', 'farms', 'coast', 'forest', 'airfield', 'highlands']) {
    assert.ok(reachable.has(districtNode), `${districtNode} reachable`);
  }
});

test('routing returns distance and driving time across the map', () => {
  const route = foundation.findRoute('festival', 'city', { mode: 'time' });
  assert.ok(route);
  const straight = Math.hypot(1250 - 0, -1050 - 1250);
  assert.ok(route.distanceM > straight);
  assert.ok(route.distanceM < straight * 1.8);
  assert.ok(route.estimatedTimeS > 60);
  assert.equal(route.edgeIds.length, route.steps.length);
  assert.equal(foundation.findRoute('festival', 'nope'), null);
});

test('road elevations are grade-limited and junction seams are exact', () => {
  const endByNode = new Map();
  for (const edge of foundation.roadGraph.edges) {
    for (let i = 1; i < edge.samples.length; i++) {
      const ds = Math.max(0.1, edge.samples[i].s - edge.samples[i - 1].s);
      const grade = Math.abs(edge.samples[i].y - edge.samples[i - 1].y) / ds;
      assert.ok(grade <= 0.1401, `${edge.id} grade ${grade} at sample ${i}`);
    }
    for (const [nodeId, y] of [[edge.from, edge.samples[0].y], [edge.to, edge.samples.at(-1).y]]) {
      if (endByNode.has(nodeId)) assert.ok(Math.abs(endByNode.get(nodeId) - y) < 1e-6, `seam at ${nodeId}`);
      else endByNode.set(nodeId, y);
    }
  }
});

test('terrain is flattened onto the road corridor centreline', () => {
  for (const edge of foundation.roadGraph.edges) {
    for (let i = 0; i < edge.samples.length; i += 29) {
      const sample = edge.samples[i];
      const h = foundation.heightAt(sample.x, sample.z);
      // On a road centreline the pre-plateau height is the road profile
      // itself; inside the imported city footprint (and its blend apron,
      // which the north ring crosses) the flat plateau then overrides it.
      const plateau = manhattanCityPlateauFactor(sample.x, sample.z);
      const expected = sample.y + (MANHATTAN_CITY_BASE_HEIGHT_M - sample.y) * plateau;
      const delta = Math.abs(h - expected);
      assert.ok(delta < 0.05, `${edge.id} centreline delta ${delta}`);
    }
  }
});

test('surface and district lookup classify key locations', () => {
  assert.equal(foundation.surfaceAt(0, 1250).id, 'asphalt');
  assert.equal(foundation.surfaceAt(-1200, -1050).id, 'water');
  assert.equal(foundation.getDistrict(1250, -1050).id, 'kingsford-city');
  assert.equal(foundation.getDistrict(0, 1250).id, 'festival-vale');
  const offRoad = foundation.surfaceAt(-700, 420);
  assert.ok(['field', 'grass'].includes(offRoad.id), `farm surface ${offRoad.id}`);
  assert.ok(offRoad.mu < foundation.surfaces.asphalt.mu);
});

test('chunk tiles honour LOD resolution and terrain geometry is valid', () => {
  assert.equal(foundation.buildTileForChunk(8, 8, { lodTier: 0 }).cells, 25);
  assert.equal(foundation.buildTileForChunk(8, 8, { lodTier: 1 }).cells, 12);
  assert.equal(foundation.buildTileForChunk('8_8', undefined, { lodTier: 2 }).cells, 6);

  const tile = foundation.buildTileForChunk(8, 13);
  const geometry = buildTerrainTileGeometry(tile, { colorAt: foundation.terrainColorAt });
  assert.equal(geometry.vertexCount, 26 * 26);
  assert.equal(geometry.triangleCount, 25 * 25 * 2);
  assert.ok(geometry.colors);
  for (let i = 0; i < geometry.indices.length; i++) {
    assert.ok(geometry.indices[i] < geometry.vertexCount);
  }
  const n = geometry.normals;
  assert.ok(Math.abs(Math.hypot(n[0], n[1], n[2]) - 1) < 1e-3);

  const merged = mergeGeometryData([
    { positions: new Float32Array([0, 0, 0, 1, 0, 0, 0, 0, 1]), normals: new Float32Array([0, 1, 0, 0, 1, 0, 0, 1, 0]), uvs: new Float32Array(6), indices: new Uint32Array([0, 1, 2]) },
    { positions: new Float32Array([2, 0, 0, 3, 0, 0, 2, 0, 1]), normals: new Float32Array([0, 1, 0, 0, 1, 0, 0, 1, 0]), uvs: new Float32Array(6), indices: new Uint32Array([0, 1, 2]) },
  ]);
  assert.equal(merged.vertexCount, 6);
  assert.deepEqual([...merged.indices], [0, 1, 2, 3, 4, 5]);
  assert.equal(merged.normals.length, merged.positions.length);
});

test('manifest serializes all 256 chunks with road references', () => {
  const manifest = foundation.buildManifest();
  assert.equal(manifest.schemaVersion, 1);
  assert.equal(manifest.chunks.length, 256);
  assert.equal(manifest.world.totalChunks, 256);
  assert.ok(manifest.roadGraph.totalLengthM > 35000);
  const festivalChunk = manifest.chunks.find((chunk) => chunk.key === '8_13');
  assert.ok(festivalChunk.roadEdgeIds.length > 0);
  assert.ok(festivalChunk.districtIds.includes('festival-vale'));
  const roundTrip = JSON.parse(JSON.stringify(manifest));
  assert.equal(roundTrip.chunks.length, 256);
});
