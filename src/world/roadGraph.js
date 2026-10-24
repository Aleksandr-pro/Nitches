/*
 * Pure 2D road graph, spline sampling, routing and ribbon geometry.
 * Coordinates are world metres in the XZ plane; +X is east and +Z is south
 * in map space.  Rendering code can lift samples with a height callback.
 */

function finite(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, finite(value, min)));
}

function point(x, z) {
  return { x: finite(x, 0), z: finite(z, 0) };
}

function catmullRom(p0, p1, p2, p3, t) {
  const t2 = t * t;
  const t3 = t2 * t;
  return {
    x: 0.5 * ((2 * p1.x)
      + (-p0.x + p2.x) * t
      + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2
      + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3),
    z: 0.5 * ((2 * p1.z)
      + (-p0.z + p2.z) * t
      + (2 * p0.z - 5 * p1.z + 4 * p2.z - p3.z) * t2
      + (-p0.z + 3 * p1.z - 3 * p2.z + p3.z) * t3),
  };
}

export function sampleControlPoints(points, spacingM = 5) {
  const controls = (points || []).map((p) => Array.isArray(p) ? point(p[0], p[1]) : point(p.x, p.z));
  if (controls.length < 2) return controls;
  const spacing = Math.max(1, finite(spacingM, 5));
  const samples = [];

  for (let i = 0; i < controls.length - 1; i++) {
    const p0 = controls[Math.max(0, i - 1)];
    const p1 = controls[i];
    const p2 = controls[i + 1];
    const p3 = controls[Math.min(controls.length - 1, i + 2)];
    const roughLength = Math.hypot(p2.x - p1.x, p2.z - p1.z);
    const divisions = Math.max(1, Math.ceil(roughLength / spacing));
    for (let j = i === 0 ? 0 : 1; j <= divisions; j++) {
      const sample = catmullRom(p0, p1, p2, p3, j / divisions);
      const prev = samples[samples.length - 1];
      if (!prev || Math.hypot(sample.x - prev.x, sample.z - prev.z) > 0.01) samples.push(sample);
    }
  }

  let cumulative = 0;
  for (let i = 0; i < samples.length; i++) {
    if (i > 0) cumulative += Math.hypot(samples[i].x - samples[i - 1].x, samples[i].z - samples[i - 1].z);
    samples[i].s = cumulative;
  }
  return samples;
}

function buildEdge(definition, nodesById, sampleSpacingM) {
  const fromNode = nodesById.get(definition.from);
  const toNode = nodesById.get(definition.to);
  if (!fromNode || !toNode) throw new Error(`Road edge ${definition.id} references a missing node`);
  const controls = (definition.points || []).map((p) => Array.isArray(p) ? [finite(p[0], 0), finite(p[1], 0)] : [finite(p.x, 0), finite(p.z, 0)]);
  if (controls.length < 2) throw new Error(`Road edge ${definition.id} needs at least two control points`);
  controls[0] = [fromNode.x, fromNode.z];
  controls[controls.length - 1] = [toNode.x, toNode.z];

  const widthM = Math.max(2.5, finite(definition.widthM, 7.3));
  const samples = sampleControlPoints(controls, sampleSpacingM);
  const lengthM = samples.length ? samples[samples.length - 1].s : 0;
  let minX = Infinity;
  let minZ = Infinity;
  let maxX = -Infinity;
  let maxZ = -Infinity;
  for (const sample of samples) {
    sample.edgeId = definition.id;
    minX = Math.min(minX, sample.x);
    minZ = Math.min(minZ, sample.z);
    maxX = Math.max(maxX, sample.x);
    maxZ = Math.max(maxZ, sample.z);
  }
  const halfWidthM = widthM / 2;
  return {
    ...definition,
    points: controls,
    widthM,
    halfWidthM,
    lanes: Math.max(1, Math.trunc(finite(definition.lanes, 2))),
    surface: definition.surface || 'asphalt',
    roadClass: definition.roadClass || definition.class || 'A',
    speedLimitKmh: Math.max(10, finite(definition.speedLimitKmh, 80)),
    samples,
    lengthM,
    bounds: {
      minX: minX - halfWidthM,
      minZ: minZ - halfWidthM,
      maxX: maxX + halfWidthM,
      maxZ: maxZ + halfWidthM,
    },
  };
}

export function buildRoadGraph(definition, { sampleSpacingM = 5 } = {}) {
  const nodesById = new Map();
  for (const node of definition.nodes || []) {
    if (!node.id || nodesById.has(node.id)) throw new Error(`Duplicate or missing road node id: ${node.id}`);
    nodesById.set(node.id, { ...node, x: finite(node.x, 0), z: finite(node.z, 0) });
  }
  const edgesById = new Map();
  const edges = [];
  for (const edgeDefinition of definition.edges || []) {
    if (!edgeDefinition.id || edgesById.has(edgeDefinition.id)) {
      throw new Error(`Duplicate or missing road edge id: ${edgeDefinition.id}`);
    }
    const edge = buildEdge(edgeDefinition, nodesById, sampleSpacingM);
    edges.push(edge);
    edgesById.set(edge.id, edge);
  }

  const adjacency = new Map();
  for (const nodeId of nodesById.keys()) adjacency.set(nodeId, []);
  for (const edge of edges) {
    adjacency.get(edge.from).push({ nodeId: edge.to, edge, direction: 1 });
    adjacency.get(edge.to).push({ nodeId: edge.from, edge, direction: -1 });
  }

  const totalLengthM = edges.reduce((sum, edge) => sum + edge.lengthM, 0);
  return {
    id: definition.id || 'road-graph',
    version: definition.version || '1.0.0',
    nodes: [...nodesById.values()],
    nodesById,
    edges,
    edgesById,
    adjacency,
    totalLengthM,
    sampleSpacingM,
  };
}

export function getReachableNodeIds(graph, startNodeId) {
  if (!graph?.adjacency?.has(startNodeId)) return new Set();
  const seen = new Set([startNodeId]);
  const queue = [startNodeId];
  while (queue.length) {
    const current = queue.shift();
    for (const next of graph.adjacency.get(current) || []) {
      if (!seen.has(next.nodeId)) {
        seen.add(next.nodeId);
        queue.push(next.nodeId);
      }
    }
  }
  return seen;
}

export function findRoute(graph, fromNodeId, toNodeId, { cost = 'distance' } = {}) {
  if (!graph?.nodesById?.has(fromNodeId) || !graph?.nodesById?.has(toNodeId)) return null;
  const distances = new Map([[fromNodeId, 0]]);
  const previous = new Map();
  const visited = new Set();

  while (visited.size < graph.nodesById.size) {
    let current = null;
    let bestDistance = Infinity;
    for (const [nodeId, distance] of distances) {
      if (!visited.has(nodeId) && distance < bestDistance) {
        bestDistance = distance;
        current = nodeId;
      }
    }
    if (current === null) break;
    if (current === toNodeId) break;
    visited.add(current);
    for (const link of graph.adjacency.get(current) || []) {
      const edgeCost = cost === 'time'
        ? edgeCostTime(link.edge)
        : link.edge.lengthM;
      const nextDistance = bestDistance + edgeCost;
      if (nextDistance < (distances.get(link.nodeId) ?? Infinity)) {
        distances.set(link.nodeId, nextDistance);
        previous.set(link.nodeId, { nodeId: current, edge: link.edge, direction: link.direction });
      }
    }
  }

  if (!distances.has(toNodeId)) return null;
  const nodeIds = [toNodeId];
  const steps = [];
  let cursor = toNodeId;
  while (cursor !== fromNodeId) {
    const step = previous.get(cursor);
    if (!step) return null;
    steps.unshift({ edgeId: step.edge.id, from: step.nodeId, to: cursor, direction: step.direction, lengthM: step.edge.lengthM });
    cursor = step.nodeId;
    nodeIds.unshift(cursor);
  }
  return {
    from: fromNodeId,
    to: toNodeId,
    nodeIds,
    steps,
    distanceM: steps.reduce((sum, step) => sum + step.lengthM, 0),
    cost: distances.get(toNodeId),
  };
}

function edgeCostTime(edge) {
  const speedMps = Math.max(3, edge.speedLimitKmh / 3.6);
  return edge.lengthM / speedMps;
}

export function buildRoadSegments(graph) {
  const segments = [];
  for (const edge of graph.edges || []) {
    for (let i = 0; i < edge.samples.length - 1; i++) {
      const a = edge.samples[i];
      const b = edge.samples[i + 1];
      segments.push({
        id: `${edge.id}:${i}`,
        edgeId: edge.id,
        roadClass: edge.roadClass,
        surface: edge.surface,
        halfWidthM: edge.halfWidthM,
        x1: a.x,
        z1: a.z,
        y1: finite(a.y, 0),
        x2: b.x,
        z2: b.z,
        y2: finite(b.y, 0),
        s1: a.s,
        s2: b.s,
        lengthM: Math.max(0, b.s - a.s),
      });
    }
  }
  return segments;
}

export function roadPointAt(edge, distanceM, lateralM = 0) {
  if (!edge?.samples?.length) return null;
  const samples = edge.samples;
  const targetS = clamp(distanceM, 0, edge.lengthM || samples[samples.length - 1].s || 0);
  let lo = 0;
  let hi = samples.length - 1;
  while (lo < hi) {
    const mid = Math.floor((lo + hi) / 2);
    if (samples[mid].s < targetS) lo = mid + 1;
    else hi = mid;
  }
  const i = Math.max(1, lo);
  const a = samples[i - 1];
  const b = samples[i];
  const segmentLength = Math.max(b.s - a.s, Number.EPSILON);
  const t = clamp((targetS - a.s) / segmentLength, 0, 1);
  const tx = b.x - a.x;
  const tz = b.z - a.z;
  const length = Math.hypot(tx, tz) || 1;
  const tangent = { x: tx / length, z: tz / length };
  const normal = { x: -tangent.z, z: tangent.x };
  const lateral = finite(lateralM, 0);
  return {
    x: a.x + tx * t + normal.x * lateral,
    z: a.z + tz * t + normal.z * lateral,
    y: finite(a.y, 0) + (finite(b.y, 0) - finite(a.y, 0)) * t,
    s: targetS,
    tangent,
    normal,
    yaw: Math.atan2(tangent.x, tangent.z),
  };
}

function segmentIntersectsBounds(a, b, bounds, padding) {
  if (!bounds) return true;
  return Math.max(a.x, b.x) >= bounds.minX - padding
    && Math.min(a.x, b.x) <= bounds.maxX + padding
    && Math.max(a.z, b.z) >= bounds.minZ - padding
    && Math.min(a.z, b.z) <= bounds.maxZ + padding;
}

/**
 * Build independent ribbon quads per sample segment.  Duplicating vertices
 * makes chunk clipping and disposal straightforward and is still small at
 * the 5 m foundation sampling used here.
 */
export function buildRoadRibbonGeometry(edge, {
  bounds = null,
  heightAt = null,
  liftM = 0.08,
  uvScaleM = 8,
} = {}) {
  const positions = [];
  const uvs = [];
  const indices = [];
  const samples = edge?.samples || [];
  const half = finite(edge?.halfWidthM, 3.65);
  const uvScale = Math.max(1, finite(uvScaleM, 8));

  for (let i = 0; i < samples.length - 1; i++) {
    const a = samples[i];
    const b = samples[i + 1];
    if (!segmentIntersectsBounds(a, b, bounds, half + 1)) continue;
    const tx = b.x - a.x;
    const tz = b.z - a.z;
    const length = Math.hypot(tx, tz) || 1;
    const nx = -tz / length;
    const nz = tx / length;
    const corners = [
      { x: a.x + nx * half, z: a.z + nz * half, y: finite(a.y, 0), s: a.s },
      { x: a.x - nx * half, z: a.z - nz * half, y: finite(a.y, 0), s: a.s },
      { x: b.x + nx * half, z: b.z + nz * half, y: finite(b.y, 0), s: b.s },
      { x: b.x - nx * half, z: b.z - nz * half, y: finite(b.y, 0), s: b.s },
    ];
    const base = positions.length / 3;
    corners.forEach((corner, cornerIndex) => {
      const y = heightAt ? finite(heightAt(corner.x, corner.z), corner.y) : corner.y;
      positions.push(corner.x, y + liftM, corner.z);
      uvs.push(cornerIndex % 2 === 0 ? 0 : 1, corner.s / uvScale);
    });
    // Winding chosen so ribbon triangles face +Y (visible from above).
    indices.push(base, base + 2, base + 1, base + 1, base + 2, base + 3);
  }

  return {
    positions: new Float32Array(positions),
    uvs: new Float32Array(uvs),
    indices: new Uint32Array(indices),
    vertexCount: positions.length / 3,
    triangleCount: indices.length / 3,
  };
}
