/*
 * 250 m world chunks and a budgeted streaming planner with hysteresis.
 * This module decides what should exist; Three.js mesh lifetime belongs to
 * the renderer adapter.
 */

function finite(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, finite(value, min)));
}

export class ChunkGrid {
  constructor({ worldSizeM = 4000, chunkSizeM = 250 } = {}) {
    this.worldSizeM = Math.max(chunkSizeM, finite(worldSizeM, 4000));
    this.chunkSizeM = Math.max(1, finite(chunkSizeM, 250));
    this.countPerAxis = Math.max(1, Math.round(this.worldSizeM / this.chunkSizeM));
    this.worldSizeM = this.countPerAxis * this.chunkSizeM;
    this.halfSizeM = this.worldSizeM / 2;
    this.originM = -this.halfSizeM;
    this.totalChunks = this.countPerAxis * this.countPerAxis;
  }

  key(cx, cz) {
    return `${Math.trunc(cx)}_${Math.trunc(cz)}`;
  }

  parseKey(key) {
    const [cx, cz] = String(key).split('_').map((part) => Math.trunc(finite(part, 0)));
    return { cx, cz };
  }

  isValid(cx, cz) {
    return cx >= 0 && cz >= 0 && cx < this.countPerAxis && cz < this.countPerAxis;
  }

  worldToChunk(x, z, { clampToWorld = true } = {}) {
    let cx = Math.floor((finite(x, 0) - this.originM) / this.chunkSizeM);
    let cz = Math.floor((finite(z, 0) - this.originM) / this.chunkSizeM);
    if (clampToWorld) {
      cx = clamp(cx, 0, this.countPerAxis - 1);
      cz = clamp(cz, 0, this.countPerAxis - 1);
    }
    if (!this.isValid(cx, cz)) return null;
    return { cx, cz, key: this.key(cx, cz) };
  }

  chunkBounds(cx, cz) {
    const minX = this.originM + cx * this.chunkSizeM;
    const minZ = this.originM + cz * this.chunkSizeM;
    return {
      minX,
      minZ,
      maxX: minX + this.chunkSizeM,
      maxZ: minZ + this.chunkSizeM,
    };
  }

  chunkCenter(cx, cz) {
    const bounds = this.chunkBounds(cx, cz);
    return { x: (bounds.minX + bounds.maxX) / 2, z: (bounds.minZ + bounds.maxZ) / 2 };
  }

  descriptor(cx, cz) {
    return {
      key: this.key(cx, cz),
      cx,
      cz,
      bounds: this.chunkBounds(cx, cz),
      center: this.chunkCenter(cx, cz),
    };
  }

  allDescriptors() {
    const descriptors = [];
    for (let cz = 0; cz < this.countPerAxis; cz++) {
      for (let cx = 0; cx < this.countPerAxis; cx++) descriptors.push(this.descriptor(cx, cz));
    }
    return descriptors;
  }

  chunksIntersectingBounds(bounds, paddingM = 0) {
    const pad = Math.max(0, finite(paddingM, 0));
    const minCx = clamp(Math.floor((bounds.minX - pad - this.originM) / this.chunkSizeM), 0, this.countPerAxis - 1);
    const maxCx = clamp(Math.floor((bounds.maxX + pad - this.originM) / this.chunkSizeM), 0, this.countPerAxis - 1);
    const minCz = clamp(Math.floor((bounds.minZ - pad - this.originM) / this.chunkSizeM), 0, this.countPerAxis - 1);
    const maxCz = clamp(Math.floor((bounds.maxZ + pad - this.originM) / this.chunkSizeM), 0, this.countPerAxis - 1);
    const result = [];
    for (let cz = minCz; cz <= maxCz; cz++) {
      for (let cx = minCx; cx <= maxCx; cx++) result.push(this.descriptor(cx, cz));
    }
    return result;
  }

  chunksInRadius(cx, cz, radiusChunks) {
    const radius = Math.max(0, Math.trunc(finite(radiusChunks, 0)));
    const result = [];
    for (let z = cz - radius; z <= cz + radius; z++) {
      for (let x = cx - radius; x <= cx + radius; x++) {
        if (this.isValid(x, z)) result.push(this.descriptor(x, z));
      }
    }
    return result;
  }
}

export function lodTierForChunkDistance(distanceChunks) {
  const distance = Math.max(0, finite(distanceChunks, 0));
  if (distance <= 1) return 0;
  if (distance <= 2) return 1;
  return 2;
}

/**
 * Keeps a set of active chunks around a focus.  Chunks inside loadRadius
 * are desired; already-active chunks are retained through unloadRadius to
 * prevent flicker on borders.  Loads are sorted nearest-first and budgeted.
 */
export class ChunkStreamingPlanner {
  constructor(grid, { loadRadiusChunks = 2, unloadRadiusChunks = 3, loadsPerUpdate = 4 } = {}) {
    this.grid = grid;
    this.loadRadiusChunks = Math.max(0, Math.trunc(finite(loadRadiusChunks, 2)));
    this.unloadRadiusChunks = Math.max(this.loadRadiusChunks, Math.trunc(finite(unloadRadiusChunks, 3)));
    this.loadsPerUpdate = Math.max(1, Math.trunc(finite(loadsPerUpdate, 4)));
    this.active = new Set();
    this.queue = [];
    this.focus = null;
    this.focusChunk = null;
  }

  #distanceToFocus(descriptor) {
    if (!this.focusChunk) return 0;
    return Math.max(Math.abs(descriptor.cx - this.focusChunk.cx), Math.abs(descriptor.cz - this.focusChunk.cz));
  }

  #sortQueue() {
    this.queue.sort((a, b) => {
      const distanceDelta = this.#distanceToFocus(a) - this.#distanceToFocus(b);
      return distanceDelta || a.key.localeCompare(b.key);
    });
  }

  #drain(budget) {
    const loadNow = [];
    const count = Math.min(Math.max(0, Math.trunc(finite(budget, this.loadsPerUpdate))), this.queue.length);
    for (let i = 0; i < count; i++) {
      const descriptor = this.queue.shift();
      if (!descriptor || this.active.has(descriptor.key)) continue;
      this.active.add(descriptor.key);
      loadNow.push({ ...descriptor, lodTier: lodTierForChunkDistance(this.#distanceToFocus(descriptor)) });
    }
    return loadNow;
  }

  update(x, z, { budget = this.loadsPerUpdate } = {}) {
    const focusChunk = this.grid.worldToChunk(x, z);
    if (!focusChunk) return { focus: null, focusChunk: null, loadNow: [], unload: [], queued: [], active: [] };
    this.focus = { x: finite(x, 0), z: finite(z, 0) };
    this.focusChunk = focusChunk;

    const desired = new Map();
    for (const descriptor of this.grid.chunksInRadius(focusChunk.cx, focusChunk.cz, this.loadRadiusChunks)) {
      desired.set(descriptor.key, descriptor);
    }

    const unload = [];
    for (const key of [...this.active]) {
      const { cx, cz } = this.grid.parseKey(key);
      const distance = Math.max(Math.abs(cx - focusChunk.cx), Math.abs(cz - focusChunk.cz));
      if (distance > this.unloadRadiusChunks) {
        this.active.delete(key);
        unload.push({ ...this.grid.descriptor(cx, cz), lodTier: lodTierForChunkDistance(distance) });
      }
    }

    const queuedKeys = new Set(this.queue.map((item) => item.key));
    for (const descriptor of desired.values()) {
      if (!this.active.has(descriptor.key) && !queuedKeys.has(descriptor.key)) this.queue.push(descriptor);
    }
    this.queue = this.queue.filter((descriptor) => desired.has(descriptor.key) && !this.active.has(descriptor.key));
    this.#sortQueue();

    const loadNow = this.#drain(budget);
    const active = [...this.active].map((key) => {
      const { cx, cz } = this.grid.parseKey(key);
      const descriptor = this.grid.descriptor(cx, cz);
      return { ...descriptor, lodTier: lodTierForChunkDistance(this.#distanceToFocus(descriptor)) };
    }).sort((a, b) => a.key.localeCompare(b.key));

    return {
      focus: this.focus,
      focusChunk,
      loadNow,
      unload,
      queued: this.queue.map((descriptor) => ({
        ...descriptor,
        lodTier: lodTierForChunkDistance(this.#distanceToFocus(descriptor)),
      })),
      active,
    };
  }

  drain(budget = this.loadsPerUpdate) {
    const loadNow = this.#drain(budget);
    return { loadNow, queued: [...this.queue], activeKeys: [...this.active] };
  }

  reset() {
    const unload = [...this.active].map((key) => {
      const { cx, cz } = this.grid.parseKey(key);
      return this.grid.descriptor(cx, cz);
    });
    this.active.clear();
    this.queue = [];
    this.focus = null;
    this.focusChunk = null;
    return unload;
  }

  stats() {
    return {
      activeChunks: this.active.size,
      queuedChunks: this.queue.length,
      focusChunk: this.focusChunk,
      loadRadiusChunks: this.loadRadiusChunks,
      unloadRadiusChunks: this.unloadRadiusChunks,
    };
  }
}
