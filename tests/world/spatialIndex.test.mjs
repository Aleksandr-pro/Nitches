import test from 'node:test';
import assert from 'node:assert/strict';

import {
  ColliderIndex,
  RoadSpatialIndex,
  SpatialHash,
  closestPointOnSegment,
  distanceToCollider,
} from '../../src/world/spatialIndex.js';

test('spatial hash de-duplicates records spanning cells and supports removal', () => {
  const hash = new SpatialHash({ cellSizeM: 50 });
  const record = { id: 'big' };
  hash.insert(record, { minX: -10, minZ: -10, maxX: 120, maxZ: 120 });
  hash.insert({ id: 'far', x: 900, z: 900 }, { minX: 900, minZ: 900, maxX: 901, maxZ: 901 });

  const hits = hash.queryCircle(0, 0, 30);
  assert.equal(hits.filter((hit) => hit.id === 'big').length, 1);
  assert.equal(hash.queryCircle(900, 900, 5).length, 1);
  assert.equal(hash.remove('big'), true);
  assert.equal(hash.queryCircle(0, 0, 30).length, 0);
});

test('road index finds exact nearest segment with expanding search', () => {
  const segments = [{
    id: 'e:0', edgeId: 'e', surface: 'asphalt', roadClass: 'A',
    x1: 0, z1: 0, y1: 0, x2: 100, z2: 0, y2: 10, s1: 0, s2: 100, halfWidthM: 3.65,
  }];
  const index = new RoadSpatialIndex(segments, { cellSizeM: 50, initialSearchRadiusM: 20, maxSearchRadiusM: 500 });

  const near = index.nearest(50, 3);
  assert.equal(near.edgeId, 'e');
  assert.ok(Math.abs(near.distanceM - 3) < 1e-6);
  assert.ok(Math.abs(near.point.y - 5) < 1e-6);
  assert.ok(near.edgeDistanceM < 0, 'inside road half-width');

  const far = index.nearest(50, 250);
  assert.ok(Math.abs(far.distanceM - 250) < 1e-6);
  assert.equal(index.nearest(50, 900), null);
  assert.equal(closestPointOnSegment(10, 5, 0, 0, 20, 0).distance, 5);
});

test('collider index reports circle, capsule and OBB overlaps exactly', () => {
  const index = new ColliderIndex([
    { id: 'tree', kind: 'circle', x: 10, z: 0, r: 0.5 },
    { id: 'wall', kind: 'segment', x1: -20, z1: 20, x2: 20, z2: 20, r: 0.4 },
    { id: 'house', kind: 'obb', x: -30, z: -30, halfWidthM: 5, halfDepthM: 4, rotationY: Math.PI / 4 },
  ]);

  const circleHits = index.queryOverlaps(10, 0, 1.2);
  assert.equal(circleHits.length, 1);
  assert.equal(circleHits[0].collider.id, 'tree');
  assert.ok(circleHits[0].penetrationM > 1);

  assert.ok(distanceToCollider(index.colliders[1], 0, 20) < 0);
  assert.ok(distanceToCollider(index.colliders[1], 0, 25) > 4);
  assert.ok(distanceToCollider(index.colliders[2], -30, -30) < 0);
  assert.ok(distanceToCollider(index.colliders[2], -30, 30) > 0);
  assert.equal(index.queryOverlaps(500, 500, 1).length, 0);
});
