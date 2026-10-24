import test from 'node:test';
import assert from 'node:assert/strict';

import {
  buildRoadGraph,
  buildRoadRibbonGeometry,
  buildRoadSegments,
  findRoute,
  getReachableNodeIds,
  roadPointAt,
  sampleControlPoints,
} from '../../src/world/roadGraph.js';

function diamondGraph() {
  return buildRoadGraph({
    nodes: [
      { id: 'a', x: 0, z: 0 },
      { id: 'b', x: 1000, z: 0 },
      { id: 'c', x: 500, z: 400 },
      { id: 'isolated', x: 5000, z: 5000 },
    ],
    edges: [
      { id: 'ab', from: 'a', to: 'b', points: [[0, 0], [1000, 0]], widthM: 7.3, speedLimitKmh: 30 },
      { id: 'ac', from: 'a', to: 'c', points: [[0, 0], [500, 400]], widthM: 7.3, speedLimitKmh: 110 },
      { id: 'cb', from: 'c', to: 'b', points: [[500, 400], [1000, 0]], widthM: 7.3, speedLimitKmh: 110 },
    ],
  }, { sampleSpacingM: 10 });
}

test('sampleControlPoints gives monotonic arc length', () => {
  const samples = sampleControlPoints([[0, 0], [300, 40], [600, 0]], 10);
  assert.ok(samples.length > 10);
  for (let i = 1; i < samples.length; i++) assert.ok(samples[i].s >= samples[i - 1].s);
  assert.ok(Math.abs(samples.at(-1).x - 600) < 0.01);
});

test('graph validation rejects duplicates and missing nodes', () => {
  assert.throws(() => buildRoadGraph({
    nodes: [{ id: 'a', x: 0, z: 0 }, { id: 'a', x: 1, z: 1 }],
    edges: [],
  }), /Duplicate/);
  assert.throws(() => buildRoadGraph({
    nodes: [{ id: 'a', x: 0, z: 0 }],
    edges: [{ id: 'e', from: 'a', to: 'nope', points: [[0, 0], [10, 0]] }],
  }), /missing node/);
});

test('reachability and routing respect distance vs time cost', () => {
  const graph = diamondGraph();
  assert.deepEqual([...getReachableNodeIds(graph, 'a')].sort(), ['a', 'b', 'c']);
  assert.equal(findRoute(graph, 'a', 'isolated'), null);

  const byDistance = findRoute(graph, 'a', 'b', { cost: 'distance' });
  assert.deepEqual(byDistance.nodeIds, ['a', 'b']);
  assert.ok(Math.abs(byDistance.distanceM - 1000) < 5);

  const byTime = findRoute(graph, 'a', 'b', { cost: 'time' });
  assert.deepEqual(byTime.nodeIds, ['a', 'c', 'b']);
  assert.ok(byTime.distanceM > byDistance.distanceM);
});

test('roadPointAt interpolates position, height and lateral offset', () => {
  const graph = diamondGraph();
  const edge = graph.edgesById.get('ab');
  edge.samples.forEach((sample) => { sample.y = sample.s * 0.01; });
  const mid = roadPointAt(edge, 500);
  assert.ok(Math.abs(mid.x - 500) < 2);
  assert.ok(Math.abs(mid.z) < 2);
  assert.ok(Math.abs(mid.y - 5) < 0.2);
  const offset = roadPointAt(edge, 500, 4);
  assert.ok(Math.abs(Math.hypot(offset.x - mid.x, offset.z - mid.z) - 4) < 0.01);
});

test('segments and ribbon geometry are chunk-clippable and face up', () => {
  const graph = diamondGraph();
  const edge = graph.edgesById.get('ab');
  const segments = buildRoadSegments(graph).filter((segment) => segment.edgeId === 'ab');
  assert.equal(segments.length, edge.samples.length - 1);
  assert.equal(segments[0].halfWidthM, 3.65);

  const full = buildRoadRibbonGeometry(edge);
  assert.ok(full.triangleCount > 0);
  assert.equal(full.positions.length / 3, full.vertexCount);

  const [i0, i1, i2] = full.indices;
  const p = full.positions;
  const a = [p[i0 * 3], p[i0 * 3 + 1], p[i0 * 3 + 2]];
  const b = [p[i1 * 3], p[i1 * 3 + 1], p[i1 * 3 + 2]];
  const c = [p[i2 * 3], p[i2 * 3 + 1], p[i2 * 3 + 2]];
  const normalY = (b[2] - a[2]) * (c[0] - a[0]) - (b[0] - a[0]) * (c[2] - a[2]);
  assert.ok(normalY > 0, 'first ribbon triangle faces +Y');

  const clipped = buildRoadRibbonGeometry(edge, {
    bounds: { minX: 0, minZ: -20, maxX: 100, maxZ: 20 },
  });
  assert.ok(clipped.triangleCount > 0 && clipped.triangleCount < full.triangleCount);
});
