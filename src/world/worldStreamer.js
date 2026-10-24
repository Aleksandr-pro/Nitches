import { buildRoadRibbonGeometry } from './roadGraph.js';
import { buildTerrainTileGeometry, mergeGeometryData } from './meshBuilders.js';
import { ChunkStreamingPlanner } from './chunks.js';
import { WORLD_WATER_LEVEL_M } from './festivalBritain.js';
import { buildDressingArchetypes, mulberry32, planChunkDressing } from './dressing.js';
import { MANHATTAN_CITY_BOUNDS } from './manhattanCity.js';

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
  if (data.indices?.length) geometry.setIndex(new THREE.BufferAttribute(data.indices, 1));
  geometry.computeBoundingBox();
  geometry.computeBoundingSphere();
  return geometry;
}

/** Procedural facade (window grid) for instanced building bodies. */
function makeFacadeTexture(THREE) {
  if (typeof document === 'undefined') return null;
  const canvas = document.createElement('canvas');
  canvas.width = 128;
  canvas.height = 256;
  const g = canvas.getContext('2d');
  if (!g) return null;
  const rng = mulberry32(20261026);
  g.fillStyle = '#d8d2c6';
  g.fillRect(0, 0, 128, 256);
  for (let i = 0; i < 260; i++) {
    g.fillStyle = `rgba(90, 80, 70, ${0.03 + rng() * 0.05})`;
    g.fillRect(rng() * 128, rng() * 256, 2 + rng() * 8, 2 + rng() * 5);
  }
  const cols = 4;
  const rows = 8;
  const ww = 18;
  const wh = 20;
  const gapX = (128 - cols * ww) / (cols + 1);
  const gapY = (256 - rows * wh) / (rows + 1);
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const x = gapX + c * (ww + gapX);
      const y = gapY + r * (wh + gapY);
      const lit = rng() < 0.24;
      g.fillStyle = lit ? '#ffd98a' : '#2c3844';
      g.fillRect(x, y, ww, wh);
      g.fillStyle = 'rgba(255,255,255,0.25)';
      g.fillRect(x, y, ww, 3);
      g.strokeStyle = 'rgba(40,36,30,0.65)';
      g.strokeRect(x + 0.5, y + 0.5, ww - 1, wh - 1);
    }
  }
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.anisotropy = 4;
  return texture;
}

/**
 * Three.js adapter for the Festival Britain foundation.  Since v0.6 main
 * creates it as the playable world by default (legacy island: ?world=legacy).
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
      // Lambert (not Basic) so roads take sun lighting and car shadows.
      this.roadMaterials.set(surface, new THREE.MeshLambertMaterial({
        color,
        polygonOffset: true,
        polygonOffsetFactor: -2,
        polygonOffsetUnits: -2,
      }));
    }

    // Stage 4 dressing: shared low-poly archetypes, instanced per chunk.
    this.archetypeData = buildDressingArchetypes();
    this.archetypeGeometries = new Map();
    for (const [name, data] of Object.entries(this.archetypeData)) {
      this.archetypeGeometries.set(name, toBufferGeometry(THREE, data, { colors: true }));
    }
    this.vegetationMaterial = new THREE.MeshLambertMaterial({ vertexColors: true });
    this.lampHeadMaterial = new THREE.MeshBasicMaterial({ vertexColors: true });
    this.facadeTexture = makeFacadeTexture(THREE);
    this.buildingMaterial = new THREE.MeshLambertMaterial({
      color: 0xffffff,
      ...(this.facadeTexture ? { map: this.facadeTexture } : {}),
    });
    this.roofMaterial = new THREE.MeshLambertMaterial({ color: 0xffffff });
    this.dressingTotals = { instances: 0, colliders: 0 };

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

  #addInstanced(group, descriptor, name, geometryName, material, items, place, {
    castShadow = true,
    receiveShadow = false,
    tintOf = null,
  } = {}) {
    if (!items.length) return 0;
    const THREE = this.THREE;
    const geometry = this.archetypeGeometries.get(geometryName);
    if (!geometry) return 0;
    const mesh = new THREE.InstancedMesh(geometry, material, items.length);
    const dummy = new THREE.Object3D();
    const color = new THREE.Color();
    items.forEach((item, i) => {
      place(dummy, item);
      dummy.updateMatrix();
      mesh.setMatrixAt(i, dummy.matrix);
      const tint = tintOf ? tintOf(item) : item.tint;
      if (tint) mesh.setColorAt(i, color.setRGB(tint[0], tint[1], tint[2]));
    });
    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
    mesh.computeBoundingSphere?.();
    mesh.name = `${name}-${descriptor.key}`;
    mesh.castShadow = castShadow;
    mesh.receiveShadow = receiveShadow;
    group.add(mesh);
    return (this.archetypeData[geometryName]?.triangleCount || 0) * items.length;
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
    terrainMesh.receiveShadow = true;
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
        // Kingsford's procedural road decals stop at the imported city edge;
        // inside, the Manhattan plate carries its own streets.
        excludeBounds: MANHATTAN_CITY_BOUNDS,
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
      const roadGeometry = toBufferGeometry(THREE, merged, { normals: true });
      geometries.push(roadGeometry);
      const roadMesh = new THREE.Mesh(roadGeometry, this.roadMaterials.get(surface) || this.roadMaterials.get('asphalt'));
      roadMesh.name = `roads-${surface}-${descriptor.key}`;
      roadMesh.receiveShadow = true;
      roadMesh.renderOrder = 2;
      roadMesh.matrixAutoUpdate = false;
      roadMesh.updateMatrix();
      group.add(roadMesh);
    }

    // Stage 4 dressing: vegetation, buildings, road furniture, landmarks.
    const plan = planChunkDressing(this.foundation, descriptor.cx, descriptor.cz, {
      lodTier: descriptor.lodTier || 0,
    });
    const veg = this.vegetationMaterial;
    const placeUniform = (dummy, item) => {
      dummy.position.set(item.x, item.y, item.z);
      dummy.rotation.set(0, item.rotY || 0, 0);
      dummy.scale.set(item.s || 1, item.s || 1, item.s || 1);
    };
    const placeScaledY = (dummy, item) => {
      dummy.position.set(item.x, item.y, item.z);
      dummy.rotation.set(0, item.rotY || 0, 0);
      dummy.scale.set(item.s || 1, item.sy || item.s || 1, item.s || 1);
    };
    let dressingTriangles = 0;
    dressingTriangles += this.#addInstanced(group, descriptor, 'oaks', 'oak', veg,
      plan.trees.filter((t) => t.type === 'oak'), placeUniform);
    dressingTriangles += this.#addInstanced(group, descriptor, 'pines', 'pine', veg,
      plan.trees.filter((t) => t.type === 'pine'), placeUniform);
    dressingTriangles += this.#addInstanced(group, descriptor, 'bushes', 'bush', veg,
      plan.bushes, placeUniform, { castShadow: false });
    dressingTriangles += this.#addInstanced(group, descriptor, 'rocks', 'rock', veg,
      plan.rocks, placeScaledY);
    dressingTriangles += this.#addInstanced(group, descriptor, 'towers', 'tower', veg,
      plan.towers, placeScaledY, { receiveShadow: true });
    dressingTriangles += this.#addInstanced(group, descriptor, 'tents', 'tent', veg,
      plan.tents, placeUniform);
    dressingTriangles += this.#addInstanced(group, descriptor, 'buildings', 'buildingBody', this.buildingMaterial,
      plan.buildings, (dummy, b) => {
        dummy.position.set(b.x, (b.y || 0) + (b.yOff || 0), b.z);
        dummy.rotation.set(0, b.rotY || 0, 0);
        dummy.scale.set(b.w, b.h, b.d);
      }, { receiveShadow: true });
    dressingTriangles += this.#addInstanced(group, descriptor, 'roofs', 'buildingRoof', this.roofMaterial,
      plan.buildings, (dummy, b) => {
        dummy.position.set(b.x, (b.y || 0) + (b.yOff || 0) + b.h, b.z);
        dummy.rotation.set(0, b.rotY || 0, 0);
        dummy.scale.set(b.w * 1.12, b.roofH > 0 ? b.roofH : 0.3, b.d * 1.12);
      }, { tintOf: (b) => b.roofTint });
    dressingTriangles += this.#addInstanced(group, descriptor, 'lamp-poles', 'lampPole', veg,
      plan.lamps, (dummy, l) => {
        dummy.position.set(l.x, l.y, l.z);
        dummy.rotation.set(0, l.rotY || 0, 0);
        dummy.scale.set(1, 5.4, 1);
      }, { castShadow: false });
    dressingTriangles += this.#addInstanced(group, descriptor, 'lamp-heads', 'lampHead', this.lampHeadMaterial,
      plan.lamps, (dummy, l) => {
        dummy.position.set(l.x, l.y + 5.45, l.z);
        dummy.rotation.set(0, 0, 0);
        dummy.scale.set(1, 1, 1);
      }, { castShadow: false });
    dressingTriangles += this.#addInstanced(group, descriptor, 'stone-walls', 'wall', veg,
      plan.walls.filter((w) => w.kind === 'stone'), (dummy, w) => {
        dummy.position.set(w.x, w.y, w.z);
        dummy.rotation.set(0, w.rotY || 0, 0);
        dummy.scale.set(w.len, 0.95, 0.45);
      }, { receiveShadow: true });
    dressingTriangles += this.#addInstanced(group, descriptor, 'castle-walls', 'wall', veg,
      plan.walls.filter((w) => w.kind === 'castleWall'), (dummy, w) => {
        dummy.position.set(w.x, w.y, w.z);
        dummy.rotation.set(0, w.rotY || 0, 0);
        dummy.scale.set(w.len, 6, 1.4);
      }, { receiveShadow: true });
    dressingTriangles += this.#addInstanced(group, descriptor, 'fences', 'fence', veg,
      plan.walls.filter((w) => w.kind === 'fence'), (dummy, w) => {
        dummy.position.set(w.x, w.y, w.z);
        dummy.rotation.set(0, w.rotY || 0, 0);
        dummy.scale.set(w.len / 7.5, 1, 1);
      }, { castShadow: false });

    for (const collider of plan.colliders) this.foundation.colliderIndex.add(collider);
    const colliderIds = plan.colliders.map((c) => c.id);
    const dressingInstances = plan.trees.length + plan.bushes.length + plan.rocks.length
      + plan.buildings.length + plan.towers.length + plan.tents.length
      + plan.lamps.length + plan.walls.length;
    this.dressingTotals.instances += dressingInstances;
    this.dressingTotals.colliders += colliderIds.length;

    const triangles = terrainData.triangleCount + [...bySurface.values()].reduce(
      (sum, ribbons) => sum + ribbons.reduce((ribbonSum, ribbon) => ribbonSum + ribbon.triangleCount, 0),
      0,
    ) + dressingTriangles;
    this.loaded.set(descriptor.key, { descriptor, group, geometries, triangles, colliderIds, dressingInstances });
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
    if (record.colliderIds?.length) {
      for (const id of record.colliderIds) this.foundation.colliderIndex.remove(id);
      this.dressingTotals.colliders -= record.colliderIds.length;
    }
    if (record.dressingInstances) this.dressingTotals.instances -= record.dressingInstances;
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
      dressing: { ...this.dressingTotals },
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
    for (const geometry of this.archetypeGeometries.values()) geometry.dispose?.();
    this.vegetationMaterial.dispose?.();
    this.lampHeadMaterial.dispose?.();
    this.buildingMaterial.dispose?.();
    this.roofMaterial.dispose?.();
    this.facadeTexture?.dispose?.();
  }
}

export function createWorldFoundationStreamer(options) {
  return new WorldFoundationStreamer(options);
}
