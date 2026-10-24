/**
 * Three.js loader for the imported Manhattan city GLB.
 *
 * The GLB (converted from the Model Inbox FBX by
 * scripts/blender_convert_city.py) is a single self-contained file with
 * 18 spatial chunk meshes under the `KingsfordManhattanCity` root, one
 * vertex-colour material and no textures.  City-local coordinates are
 * already metres with the origin at the footprint centre and Y=0 at street
 * level, so placement is a single translation onto the Kingsford plateau.
 */
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import {
  MANHATTAN_CITY_BASE_HEIGHT_M,
  MANHATTAN_CITY_CENTER,
  buildManhattanWorldColliders,
  manhattanCityChunks,
  manhattanCityStats,
  manhattanLocalToWorld,
} from './manhattanCity.js';

export const MANHATTAN_CITY_MODEL_URL = `${import.meta.env.BASE_URL || '/'}assets/models/cities/kingsford-manhattan-city/kingsford-manhattan-city.glb`;

/** Tiny lift so the city street plate does not z-fight the terrain mesh. */
const CITY_GROUND_LIFT_M = 0.03;

/** Hide individual chunk meshes beyond this distance from the player. */
export const MANHATTAN_CHUNK_VIEW_DISTANCE_M = 2700;

let loadPromise = null;
const registeredFoundations = new WeakSet();

function loadGltfOnce() {
  if (!loadPromise) {
    loadPromise = new GLTFLoader().loadAsync(MANHATTAN_CITY_MODEL_URL).catch((error) => {
      loadPromise = null;
      throw error;
    });
  }
  return loadPromise;
}

/**
 * Load the city GLB and return a positioned group plus chunk records.
 * The caller adds `group` to the scene and may call
 * `updateManhattanCityVisibility(handle, x, z)` as the player moves.
 */
export async function loadManhattanCityGroup() {
  const gltf = await loadGltfOnce();
  const group = gltf.scene;
  group.name = 'nh-manhattan-city';
  group.position.set(
    MANHATTAN_CITY_CENTER.x,
    MANHATTAN_CITY_BASE_HEIGHT_M + CITY_GROUND_LIFT_M,
    MANHATTAN_CITY_CENTER.z,
  );

  const chunkByMeshName = new Map(
    manhattanCityChunks().map((chunk) => [chunk.meshName, chunk]),
  );
  const chunkMeshes = [];
  group.traverse((object) => {
    if (!object.isMesh) return;
    object.castShadow = true;
    object.receiveShadow = true;
    const materials = Array.isArray(object.material) ? object.material : [object.material];
    for (const material of materials) {
      if (!material) continue;
      // The converter emits COLOR_0 vertex colours as the only shading.
      if (object.geometry?.getAttribute?.('color') && 'vertexColors' in material) {
        material.vertexColors = true;
      }
      // Photogrammetry shells are thin; render both sides to avoid holes.
      material.side = THREE.DoubleSide;
      material.needsUpdate = true;
    }
    const chunk = chunkByMeshName.get(object.name) || null;
    object.userData.manhattanChunk = chunk;
    chunkMeshes.push({ mesh: object, chunk });
  });

  return {
    group,
    chunkMeshes,
    stats: {
      ...manhattanCityStats(),
      meshCount: chunkMeshes.length,
      url: MANHATTAN_CITY_MODEL_URL,
    },
  };
}

/**
 * Toggle chunk mesh visibility by distance from (x, z).  Frustum culling
 * already handles off-screen chunks; this additionally skips the whole
 * 368k-triangle city while the player is on the far side of the map.
 * Returns the number of currently visible chunk meshes.
 */
export function updateManhattanCityVisibility(handle, x, z, viewDistanceM = MANHATTAN_CHUNK_VIEW_DISTANCE_M) {
  if (!handle?.chunkMeshes) return 0;
  const limit2 = viewDistanceM * viewDistanceM;
  let visible = 0;
  for (const { mesh, chunk } of handle.chunkMeshes) {
    let show = true;
    if (chunk) {
      const world = manhattanLocalToWorld(chunk.centerX, chunk.centerZ);
      const dx = world.x - x;
      const dz = world.z - z;
      show = dx * dx + dz * dz <= limit2;
    }
    mesh.visible = show;
    if (show) visible += 1;
  }
  return visible;
}

/**
 * Register the generated city colliders into the foundation index (once per
 * foundation).  Returns how many colliders are registered for the city.
 */
export function registerManhattanCityColliders(foundation) {
  const colliders = buildManhattanWorldColliders();
  if (!foundation?.colliderIndex) return 0;
  if (registeredFoundations.has(foundation)) return colliders.length;
  for (const collider of colliders) foundation.colliderIndex.add(collider);
  registeredFoundations.add(foundation);
  return colliders.length;
}
