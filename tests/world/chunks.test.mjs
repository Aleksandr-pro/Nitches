import test from 'node:test';
import assert from 'node:assert/strict';

import { ChunkGrid, ChunkStreamingPlanner, lodTierForChunkDistance } from '../../src/world/chunks.js';

test('chunk grid covers 4x4 km in 256 tiles of 250 m', () => {
  const grid = new ChunkGrid();
  assert.equal(grid.countPerAxis, 16);
  assert.equal(grid.totalChunks, 256);
  assert.equal(grid.allDescriptors().length, 256);

  assert.equal(grid.worldToChunk(-2000, -2000).key, '0_0');
  assert.equal(grid.worldToChunk(1999, 1999).key, '15_15');
  assert.equal(grid.worldToChunk(0, 0).key, '8_8');
  assert.equal(grid.worldToChunk(-5000, 0, { clampToWorld: false }), null);

  const descriptor = grid.descriptor(8, 8);
  assert.deepEqual(descriptor.bounds, { minX: 0, minZ: 0, maxX: 250, maxZ: 250 });
  assert.deepEqual(descriptor.center, { x: 125, z: 125 });
  assert.deepEqual(grid.parseKey('3_12'), { cx: 3, cz: 12 });

  const hit = grid.chunksIntersectingBounds({ minX: -10, minZ: -10, maxX: 10, maxZ: 10 });
  assert.deepEqual(hit.map((chunk) => chunk.key).sort(), ['7_7', '7_8', '8_7', '8_8']);
});

test('streaming planner budgets loads, keeps hysteresis ring and LOD tiers', () => {
  const grid = new ChunkGrid();
  const planner = new ChunkStreamingPlanner(grid, {
    loadRadiusChunks: 2,
    unloadRadiusChunks: 3,
    loadsPerUpdate: 4,
  });

  const first = planner.update(0, 0);
  assert.equal(first.focusChunk.key, '8_8');
  assert.equal(first.loadNow.length, 4, 'load budget respected');
  assert.equal(first.loadNow[0].key, '8_8', 'nearest chunk loads first');

  for (let i = 0; i < 12 && planner.stats().queuedChunks > 0; i++) planner.drain(4);
  assert.equal(planner.stats().activeChunks, 25, '5x5 neighbourhood active');

  // One chunk east: previous border column is inside the hysteresis ring.
  const moved = planner.update(375, 125);
  assert.equal(moved.focusChunk.key, '9_8');
  assert.equal(moved.unload.length, 0);
  assert.ok(moved.active.some((chunk) => chunk.key === '6_8' && chunk.lodTier === 2));

  // Teleport far away: everything old is beyond the unload radius.
  const before = planner.stats().activeChunks;
  const jumped = planner.update(-1900, -1900);
  assert.equal(jumped.focusChunk.key, '0_0');
  assert.equal(jumped.unload.length, before);
  assert.ok(jumped.active.every((chunk) => chunk.cx <= 2 && chunk.cz <= 2));

  assert.equal(lodTierForChunkDistance(0), 0);
  assert.equal(lodTierForChunkDistance(2), 1);
  assert.equal(lodTierForChunkDistance(3), 2);
});
