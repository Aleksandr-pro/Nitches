import test from 'node:test';
import assert from 'node:assert/strict';

import * as THREE from 'three';

import { createFestivalBritainFoundation } from '../../src/world/festivalBritain.js';
import { createWorldFoundationStreamer } from '../../src/world/worldStreamer.js';

test('Three streamer loads, relocates and disposes chunk meshes', () => {
  const scene = new THREE.Scene();
  const foundation = createFestivalBritainFoundation();
  const streamer = createWorldFoundationStreamer({ THREE, scene, foundation });

  assert.ok(scene.children.includes(streamer.root));
  assert.equal(streamer.root.visible, false, 'dormant preview hidden by default');

  streamer.update(0, 1250, { budget: 9 });
  streamer.drain(50);
  let stats = streamer.stats();
  assert.equal(stats.loadedChunks, 25, '5x5 neighbourhood around Festival');
  assert.ok(stats.loadedTriangles > 10000, `triangles ${stats.loadedTriangles}`);
  const festivalGroup = streamer.loaded.get('8_13');
  assert.ok(festivalGroup, 'festival chunk loaded');
  assert.ok(festivalGroup.group.children.length >= 2, 'terrain + road meshes');

  assert.equal(streamer.setVisible(true), true);
  assert.equal(streamer.root.visible, true);

  streamer.update(-1900, -1900, { budget: 3 });
  streamer.drain(50);
  stats = streamer.stats();
  assert.equal(stats.loadedChunks, 9, 'clipped 3x3 neighbourhood in the corner');
  for (const key of stats.loadedKeys) {
    const [cx, cz] = key.split('_').map(Number);
    assert.ok(cx <= 2 && cz <= 2, `stale chunk ${key} remained loaded`);
  }

  streamer.dispose();
  assert.equal(streamer.stats().loadedChunks, 0);
  assert.ok(!scene.children.includes(streamer.root));
});
