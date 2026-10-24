import test from 'node:test';
import assert from 'node:assert/strict';

import {
  WORLD_HALF_SIZE_M,
  WORLD_SIZE_M,
  buildHeightTile,
  createHeightSampler,
  estimateHeightSlope,
  sampleFestivalBritainHeight,
  sampleHeightTile,
} from '../../src/world/heightfield.js';

test('height sampler is deterministic and seed-sensitive', () => {
  const a = createHeightSampler({ seed: 42 });
  const b = createHeightSampler({ seed: 42 });
  const c = createHeightSampler({ seed: 7 });
  for (const [x, z] of [[0, 0], [300, -700], [-1450, 900], [1999, 1999]]) {
    assert.equal(a(x, z), b(x, z));
  }
  assert.notEqual(a(300, -700), c(300, -700));
});

test('Festival Britain landform anchors', () => {
  const sample = createHeightSampler();
  // Lake bowl sits below the water plane, landmass peaks are high.
  assert.ok(sample(-1200, -1050) < 0, 'lake centre below water');
  // The lake is carved into the massif, so the summit ring sits west of it.
  assert.ok(sample(-1650, -1250) > 60, 'Lake District massif is high');
  assert.ok(sample(-1550, -250) > 60, 'West Highlands are high');
  assert.ok(sample(850, -1450) > 25, 'Castle Hill is elevated');
  // Festival ground is comparatively flat/buildable.
  const slope = estimateHeightSlope(sample, 0, 1250, 10);
  assert.ok(slope.magnitude < 0.25, `festival slope ${slope.magnitude}`);
  // Outside playable bounds the terrain falls under water.
  assert.ok(sampleFestivalBritainHeight(0, WORLD_HALF_SIZE_M + 300) < 0);
  assert.equal(WORLD_SIZE_M, 4000);
});

test('height tile has inclusive vertices and matching seams', () => {
  const sample = createHeightSampler();
  const tile = buildHeightTile({ chunkX: 8, chunkZ: 8, sampleHeight: sample });
  assert.equal(tile.vertexCountPerSide, 26);
  assert.equal(tile.heights.length, 26 * 26);
  assert.equal(tile.stepM, 10);
  assert.equal(tile.originX, 0);
  assert.equal(tile.originZ, 0);

  const east = buildHeightTile({ chunkX: 9, chunkZ: 8, sampleHeight: sample });
  for (let vz = 0; vz < 26; vz++) {
    assert.equal(tile.heights[vz * 26 + 25], east.heights[vz * 26]);
  }
});

test('sampleHeightTile interpolates within tile range', () => {
  const tile = buildHeightTile({ chunkX: 4, chunkZ: 11 });
  assert.equal(sampleHeightTile(tile, tile.originX, tile.originZ), tile.heights[0]);
  const mid = sampleHeightTile(tile, tile.originX + 125, tile.originZ + 125);
  assert.ok(mid >= tile.minHeightM - 1e-6 && mid <= tile.maxHeightM + 1e-6);
});
