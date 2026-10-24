/*
 * Uniform spatial hash plus road/collider indexes for the 4x4 km world.
 * Records are stored in every cell overlapped by their XZ bounds and are
 * de-duplicated on query.  No full-world scans are needed in physics steps.
 */

function finite(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, finite(value, min)));
}

export function boundsIntersect(a, b) {
  return a.minX <= b.maxX && a.maxX >= b.minX && a.minZ <= b.maxZ && a.maxZ >= b.minZ;
}

export function expandBounds(bounds, padding = 0) {
  const pad = Math.max(0, finite(padding, 0));
  return {
    minX: bounds.minX - pad,
    minZ: bounds.minZ - pad,
    maxX: bounds.maxX + pad,
    maxZ: bounds.maxZ + pad,
  };
}

export function closestPointOnSegment(px, pz, x1, z1, x2, z2) {
  const dx = x2 - x1;
  const dz = z2 - z1;
  const length2 = dx * dx + dz * dz;
  const t = length2 > 0 ? clamp(((px - x1) * dx + (pz - z1) * dz) / length2, 0, 1) : 0;
  const x = x1 + dx * t;
  const z = z1 + dz * t;
  return { x, z, t, distance: Math.hypot(px - x, pz - z) };
}

export class SpatialHash {
  constructor({ cellSizeM = 50 } = {}) {
    this.cellSizeM = Math.max(1, finite(cellSizeM, 50));
    this.cells = new Map();
    this.recordCells = new Map();
    this.records = new Map();
  }

  cellKey(cx, cz) {
    return `${cx},${cz}`;
  }

  cellRange(bounds) {
    return {
      minCx: Math.floor(bounds.minX / this.cellSizeM),
      maxCx: Math.floor(bounds.maxX / this.cellSizeM),
      minCz: Math.floor(bounds.minZ / this.cellSizeM),
      maxCz: Math.floor(bounds.maxZ / this.cellSizeM),
    };
  }

  insert(record, bounds) {
    if (!record || record.id == null) throw new Error('SpatialHash records require an id');
    if (this.records.has(record.id)) this.remove(record.id);
    const safeBounds = {
      minX: finite(bounds?.minX, finite(record.x, 0)),
      minZ: finite(bounds?.minZ, finite(record.z, 0)),
      maxX: finite(bounds?.maxX, finite(record.x, 0)),
      maxZ: finite(bounds?.maxZ, finite(record.z, 0)),
    };
    const range = this.cellRange(safeBounds);
    const keys = [];
    for (let cx = range.minCx; cx <= range.maxCx; cx++) {
      for (let cz = range.minCz; cz <= range.maxCz; cz++) {
        const key = this.cellKey(cx, cz);
        keys.push(key);
        let bucket = this.cells.get(key);
        if (!bucket) {
          bucket = new Set();
          this.cells.set(key, bucket);
        }
        bucket.add(record);
      }
    }
    this.records.set(record.id, record);
    this.recordCells.set(record.id, keys);
    record.__spatialBounds = safeBounds;
    return record;
  }

  remove(recordOrId) {
    const id = typeof recordOrId === 'object' ? recordOrId?.id : recordOrId;
    const record = this.records.get(id);
    if (!record) return false;
    for (const key of this.recordCells.get(id) || []) {
      const bucket = this.cells.get(key);
      bucket?.delete(record);
      if (bucket && bucket.size === 0) this.cells.delete(key);
    }
    this.recordCells.delete(id);
    this.records.delete(id);
    return true;
  }

  queryBounds(bounds) {
    if (!bounds) return [...this.records.values()];
    const range = this.cellRange(bounds);
    const found = new Set();
    for (let cx = range.minCx; cx <= range.maxCx; cx++) {
      for (let cz = range.minCz; cz <= range.maxCz; cz++) {
        const bucket = this.cells.get(this.cellKey(cx, cz));
        if (!bucket) continue;
        for (const record of bucket) {
          if (!record.__spatialBounds || boundsIntersect(record.__spatialBounds, bounds)) found.add(record);
        }
      }
    }
    return [...found];
  }

  queryCircle(x, z, radiusM) {
    const radius = Math.max(0, finite(radiusM, 0));
    return this.queryBounds({
      minX: finite(x, 0) - radius,
      minZ: finite(z, 0) - radius,
      maxX: finite(x, 0) + radius,
      maxZ: finite(z, 0) + radius,
    });
  }

  clear() {
    this.cells.clear();
    this.recordCells.clear();
    this.records.clear();
  }

  stats() {
    return {
      cellSizeM: this.cellSizeM,
      occupiedCells: this.cells.size,
      records: this.records.size,
    };
  }
}

export function segmentBounds(segment, padding = 0) {
  return expandBounds({
    minX: Math.min(segment.x1, segment.x2),
    minZ: Math.min(segment.z1, segment.z2),
    maxX: Math.max(segment.x1, segment.x2),
    maxZ: Math.max(segment.z1, segment.z2),
  }, padding);
}

export class RoadSpatialIndex {
  constructor(segments, { cellSizeM = 50, initialSearchRadiusM = 45, maxSearchRadiusM = 400 } = {}) {
    this.hash = new SpatialHash({ cellSizeM });
    this.segments = segments || [];
    this.initialSearchRadiusM = Math.max(5, finite(initialSearchRadiusM, 45));
    this.maxSearchRadiusM = Math.max(this.initialSearchRadiusM, finite(maxSearchRadiusM, 400));
    for (const segment of this.segments) this.hash.insert(segment, segmentBounds(segment));
  }

  candidatesWithin(x, z, radiusM) {
    return this.hash.queryCircle(x, z, radiusM);
  }

  nearest(x, z, { maxDistanceM = this.maxSearchRadiusM } = {}) {
    const px = finite(x, 0);
    const pz = finite(z, 0);
    const maxDistance = Math.max(1, finite(maxDistanceM, this.maxSearchRadiusM));
    let radius = Math.min(this.initialSearchRadiusM, maxDistance);
    let best = null;

    while (radius <= maxDistance) {
      const candidates = this.candidatesWithin(px, pz, radius);
      for (const segment of candidates) {
        const closest = closestPointOnSegment(px, pz, segment.x1, segment.z1, segment.x2, segment.z2);
        if (!best || closest.distance < best.distanceM) {
          const y = finite(segment.y1, 0) + (finite(segment.y2, 0) - finite(segment.y1, 0)) * closest.t;
          best = {
            segment,
            edgeId: segment.edgeId,
            surface: segment.surface,
            roadClass: segment.roadClass,
            point: { x: closest.x, z: closest.z, y },
            distanceM: closest.distance,
            edgeDistanceM: closest.distance - finite(segment.halfWidthM, 0),
            sM: finite(segment.s1, 0) + (finite(segment.s2, 0) - finite(segment.s1, 0)) * closest.t,
            searchRadiusM: radius,
            candidatesChecked: candidates.length,
          };
        }
      }
      // The query square contains every segment that could be closer than
      // the current radius, so a hit within it is the true nearest result.
      if (best && best.distanceM <= radius) return best;
      if (radius === maxDistance) break;
      radius = Math.min(maxDistance, radius * 2);
    }
    return best && best.distanceM <= maxDistance ? best : null;
  }

  stats() {
    return {
      segments: this.segments.length,
      ...this.hash.stats(),
    };
  }
}

export function colliderBounds(collider) {
  if (!collider) return { minX: 0, minZ: 0, maxX: 0, maxZ: 0 };
  if (collider.kind === 'circle') {
    const r = Math.max(0, finite(collider.r ?? collider.radiusM, 0));
    return { minX: collider.x - r, minZ: collider.z - r, maxX: collider.x + r, maxZ: collider.z + r };
  }
  if (collider.kind === 'segment') {
    return segmentBounds(collider, Math.max(0, finite(collider.r ?? collider.radiusM, 0)));
  }
  if (collider.kind === 'obb') {
    const hw = Math.max(0, finite(collider.halfWidthM, 0));
    const hd = Math.max(0, finite(collider.halfDepthM, 0));
    const cos = Math.abs(Math.cos(finite(collider.rotationY, 0)));
    const sin = Math.abs(Math.sin(finite(collider.rotationY, 0)));
    const ex = hw * cos + hd * sin;
    const ez = hw * sin + hd * cos;
    return { minX: collider.x - ex, minZ: collider.z - ez, maxX: collider.x + ex, maxZ: collider.z + ez };
  }
  return {
    minX: finite(collider.minX, finite(collider.x, 0)),
    minZ: finite(collider.minZ, finite(collider.z, 0)),
    maxX: finite(collider.maxX, finite(collider.x, 0)),
    maxZ: finite(collider.maxZ, finite(collider.z, 0)),
  };
}

/** Signed outside distance: negative means the point is inside. */
export function distanceToCollider(collider, x, z) {
  const px = finite(x, 0);
  const pz = finite(z, 0);
  if (!collider) return Infinity;
  if (collider.kind === 'circle') {
    return Math.hypot(px - collider.x, pz - collider.z) - Math.max(0, finite(collider.r ?? collider.radiusM, 0));
  }
  if (collider.kind === 'segment') {
    return closestPointOnSegment(px, pz, collider.x1, collider.z1, collider.x2, collider.z2).distance
      - Math.max(0, finite(collider.r ?? collider.radiusM, 0));
  }
  if (collider.kind === 'obb') {
    const rotation = finite(collider.rotationY, 0);
    const cos = Math.cos(rotation);
    const sin = Math.sin(rotation);
    const dx = px - collider.x;
    const dz = pz - collider.z;
    const localX = dx * cos - dz * sin;
    const localZ = dx * sin + dz * cos;
    const qx = Math.abs(localX) - Math.max(0, finite(collider.halfWidthM, 0));
    const qz = Math.abs(localZ) - Math.max(0, finite(collider.halfDepthM, 0));
    const outside = Math.hypot(Math.max(qx, 0), Math.max(qz, 0));
    const inside = Math.min(Math.max(qx, qz), 0);
    return outside + inside;
  }
  return Infinity;
}

export class ColliderIndex {
  constructor(colliders = [], { cellSizeM = 50 } = {}) {
    this.hash = new SpatialHash({ cellSizeM });
    this.colliders = [];
    for (const collider of colliders) this.add(collider);
  }

  add(collider) {
    this.colliders.push(collider);
    this.hash.insert(collider, colliderBounds(collider));
    return collider;
  }

  remove(colliderOrId) {
    const id = typeof colliderOrId === 'object' ? colliderOrId?.id : colliderOrId;
    this.colliders = this.colliders.filter((collider) => collider.id !== id);
    return this.hash.remove(id);
  }

  queryPotential(x, z, radiusM = 0) {
    return this.hash.queryCircle(x, z, radiusM);
  }

  queryOverlaps(x, z, radiusM = 0) {
    const radius = Math.max(0, finite(radiusM, 0));
    return this.queryPotential(x, z, radius)
      .map((collider) => {
        const distanceM = distanceToCollider(collider, x, z);
        return { collider, distanceM, penetrationM: Math.max(0, radius - distanceM) };
      })
      .filter((hit) => hit.distanceM <= radius)
      .sort((a, b) => a.distanceM - b.distanceM);
  }

  stats() {
    return {
      colliders: this.colliders.length,
      ...this.hash.stats(),
    };
  }
}
