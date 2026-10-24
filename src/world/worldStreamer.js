import { buildRoadRibbonGeometry } from './roadGraph.js';
import { buildTerrainTileGeometry, mergeGeometryData } from './meshBuilders.js';
import { ChunkStreamingPlanner } from './chunks.js';
import { WORLD_WATER_LEVEL_M } from './festivalBritain.js';

const ROAD_MATERIAL_COLORS = {
  asphalt: 0x34373c,
  cobble: 0x67615b,
  concrete: 0x8b8f8c,
  dirt: 0x74604a,
  gravel: 0x837a6c,
};

function toBufferGeometry(THREE, data, { normals = true, colors = false } = {}) {
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.BufferAttribute(data.positions, 3));
  if (normals && data.normals) geometry.setAttribute('normal', new THREE.BufferAttribute(data.normals, 3));
  if (data.uvs?.length) geometry.setAttribute('uv', new THREE.BufferAttribute(data.uvs, 2));
  if (colors && data.colors) geometry.setAttribute('color', new THREE.BufferAttribute(data.colors, 3));
  geometry.setIndex(new THREE.BufferAttribute(data.indices, 1));
  geometry.computeBoundingBox();
  geometry.computeBoundingSphere();
  return geometry;
}

/**
 * Three.js adapter for the dormant Stage 3 foundation.  It never replaces
 * legacy gameplay/collisions: main only creates it behind a feature flag.
 */
export class WorldFoundationStreamer {
  constructor({
    THREE,
    scene,
    foundation,
    loadRadiusChunks = 2,
    unloadRadiusChunks = 3,
    loadsPerUpdate = 3,
    heightOffsetM = -35,
    visible = false,
  } = {}) {
    if (!THREE) throw new Error('WorldFoundationStreamer requires the Three.js module');
    if (!scene) throw new Error('WorldFoundationStreamer requires a scene');
    if (!foundation) throw new Error('WorldFoundationStreamer requires a world foundation');

    this.THREE = THREE;
    this.scene = scene;
    this.foundation = foundation;
    this.grid = foundation.grid;
    this.planner = new ChunkStreamingPlanner(this.grid, {
      loadRadiusChunks,
      unloadRadiusChunks,
      loadsPerUpdate,
    });
    this.loaded = new Map();
    this.root = new THREE.Group();
    this.root.name = 'nh-world-foundation-stage3';
    this.root.position.y = heightOffsetM;
    this.root.visible = Boolean(visible);
    this.heightOffsetM = heightOffsetM;
    this.scene.add(this.root);

    this.terrainMaterial = new THREE.MeshLambertMaterial({ vertexColors: true });
    this.waterMaterial = new THREE.MeshBasicMaterial({
      color: 0x2b708c,
      transparent: true,
      opacity: 0.58,
      depthWrite: false,
    });
    this.roadMaterials = new Map();
    for (const [surface, color] of Object.entries(ROAD_MATERIAL_COLORS)) {
      this.roadMaterials.set(surface, new THREE.MeshBasicMaterial({
        color,
        polygonOffset: true,
        polygonOffsetFactor: -2,
        polygonOffsetUnits: -2,
      }));
    }

    const waterGeometry = new THREE.PlaneGeometry(this.grid.worldSizeM + 400, this.grid.worldSizeM + 400);
    waterGeometry.rotateX(-Math.PI / 2);
    this.waterMesh = new THREE.Mesh(waterGeometry, this.waterMaterial);
    this.waterMesh.name = 'nh-world-foundation-water';
    this.waterMesh.position.y = WORLD_WATER_LEVEL_M + 0.03;
    this.waterMesh.renderOrder = 1;
    this.root.add(this.waterMesh);
  }

  setVisible(visible) {
    this.root.visible = Boolean(visible);
    return this.root.visible;
  }

  setHeightOffsetM(heightOffsetM) {
    const value = Number(heightOffsetM);
    this.heightOffsetM = Number.isFinite(value) ? value : this.heightOffsetM;
    this.root.position.y = this.heightOffsetM;
    return this.heightOffsetM;
  }

  #buildChunk(descriptor) {
    if (this.loaded.has(descriptor.key)) return false;
    const THREE = this.THREE;
    const group = new THREE.Group();
    group.name = `nh-world-chunk-${descriptor.key}`;
    const geometries = [];

    const tile = this.foundation.buildTileForChunk(descriptor.cx, descriptor.cz, { lodTier: descriptor.lodTier || 0 });
    const terrainData = buildTerrainTileGeometry(tile, { colorAt: this.foundation.terrainColorAt });
    const terrainGeometry = toBufferGeometry(THREE, terrainData, { colors: true });
    geometries.push(terrainGeometry);
    const terrainMesh = new THREE.Mesh(terrainGeometry, this.terrainMaterial);
    terrainMesh.name = `terrain-${descriptor.key}`;
    terrainMesh.matrixAutoUpdate = false;
    terrainMesh.updateMatrix();
    group.add(terrainMesh);

    const chunk = this.foundation.chunkDescriptor(descriptor.cx, descriptor.cz);
    const bySurface = new Map();
    for (const edgeId of chunk.roadEdgeIds) {
      const roadEdge = this.foundation.roadGraph.edgesById.get(edgeId);
      if (!roadEdge) continue;
      // No heightAt override: ribbon corners use the smoothed road sample
      // elevations, giving a flat drivable cross-section.
      const ribbon = buildRoadRibbonGeometry(roadEdge, {
        bounds: descriptor.bounds,
        liftM: 0.14,
      });
      if (!ribbon.positions.length) continue;
      const list = bySurface.get(roadEdge.surface) || [];
      list.push(ribbon);
      bySurface.set(roadEdge.surface, list);
    }
    for (const [surface, ribbons] of bySurface) {
      const merged = mergeGeometryData(ribbons);
      if (!merged.positions.length) continue;
      const roadGeometry = toBufferGeometry(THREE, merged, { normals: false });
      geometries.push(roadGeometry);
      const roadMesh = new THREE.Mesh(roadGeometry, this.roadMaterials.get(surface) || this.roadMaterials.get('asphalt'));
      roadMesh.name = `roads-${surface}-${descriptor.key}`;
      roadMesh.renderOrder = 2;
      roadMesh.matrixAutoUpdate = false;
      roadMesh.updateMatrix();
      group.add(roadMesh);
    }

    const triangles = terrainData.triangleCount + [...bySurface.values()].reduce(
      (sum, ribbons) => sum + ribbons.reduce((ribbonSum, ribbon) => ribbonSum + ribbon.triangleCount, 0),
      0,
    );
    this.loaded.set(descriptor.key, { descriptor, group, geometries, triangles });
    this.root.add(group);
    return true;
  }

  #unloadChunk(descriptorOrKey) {
    const key = typeof descriptorOrKey === 'string' ? descriptorOrKey : descriptorOrKey?.key;
    const record = this.loaded.get(key);
    if (!record) return false;
    this.root.remove(record.group);
    record.group.clear?.();
    for (const geometry of record.geometries) geometry.dispose?.();
    this.loaded.delete(key);
    return true;
  }

  update(x, z, { budget } = {}) {
    const plan = this.planner.update(x, z, { budget });
    for (const descriptor of plan.unload) this.#unloadChunk(descriptor);
    for (const descriptor of plan.loadNow) this.#buildChunk(descriptor);
    return plan;
  }

  drain(budget) {
    const result = this.planner.drain(budget);
    for (const descriptor of result.loadNow) this.#buildChunk(descriptor);
    return result;
  }

  stats() {
    let triangles = 0;
    for (const record of this.loaded.values()) triangles += record.triangles || 0;
    return {
      visible: this.root.visible,
      heightOffsetM: this.heightOffsetM,
      loadedChunks: this.loaded.size,
      loadedTriangles: triangles,
      loadedKeys: [...this.loaded.keys()],
      planner: this.planner.stats(),
      foundation: this.foundation.stats(),
    };
  }

  dispose() {
    for (const key of [...this.loaded.keys()]) this.#unloadChunk(key);
    this.waterMesh.geometry?.dispose?.();
    this.scene.remove(this.root);
    this.terrainMaterial.dispose?.();
    this.waterMaterial.dispose?.();
    for (const material of this.roadMaterials.values()) material.dispose?.();
  }
}

export function createWorldFoundationStreamer(options) {
  return new WorldFoundationStreamer(options);
}
