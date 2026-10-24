/**
 * Placement contract for the imported Manhattan city GLB.
 *
 * The model (converted by scripts/blender_convert_city.py from the Model
 * Inbox FBX) replaces the procedural Kingsford City district.  This module
 * is intentionally free of Three.js imports so foundation/dressing/tests can
 * use it in Node: footprint, plateau height and world-space colliders only.
 * The GLB loader lives in manhattanCityModel.js.
 */
import { MANHATTAN_CITY_DATA } from './manhattanCityData.js';

export const MANHATTAN_CITY_DATA_REF = MANHATTAN_CITY_DATA;

/** World position of the city-local origin (Kingsford district centre). */
export const MANHATTAN_CITY_CENTER = Object.freeze({ x: 1250, z: -1050 });

/** Flat plateau height the terrain is shaped to under the city. */
export const MANHATTAN_CITY_BASE_HEIGHT_M = 9.0;

/** Terrain blend distance outside the footprint, in metres. */
export const MANHATTAN_CITY_BLEND_M = 90;

/**
 * Footprint half-extents.  Rounded up from the parsed GLB bounds
 * (1197.7 x 994.2 m) so the plateau, dressing suppression and road masking
 * fully cover the model plus a small apron.
 */
export const MANHATTAN_CITY_HALF_EXTENTS_M = Object.freeze({ x: 606, z: 500 });

export const MANHATTAN_CITY_BOUNDS = Object.freeze({
  minX: MANHATTAN_CITY_CENTER.x - MANHATTAN_CITY_HALF_EXTENTS_M.x,
  maxX: MANHATTAN_CITY_CENTER.x + MANHATTAN_CITY_HALF_EXTENTS_M.x,
  minZ: MANHATTAN_CITY_CENTER.z - MANHATTAN_CITY_HALF_EXTENTS_M.z,
  maxZ: MANHATTAN_CITY_CENTER.z + MANHATTAN_CITY_HALF_EXTENTS_M.z,
});

function finite(value, fallback) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function smoothstep(edge0, edge1, value) {
  const t = Math.min(1, Math.max(0, (value - edge0) / Math.max(1e-9, edge1 - edge0)));
  return t * t * (3 - 2 * t);
}

/** True when (x, z) is inside the city footprint, expanded by marginM. */
export function isInsideManhattanCity(x, z, marginM = 0) {
  const m = Math.max(0, finite(marginM, 0));
  return x >= MANHATTAN_CITY_BOUNDS.minX - m
    && x <= MANHATTAN_CITY_BOUNDS.maxX + m
    && z >= MANHATTAN_CITY_BOUNDS.minZ - m
    && z <= MANHATTAN_CITY_BOUNDS.maxZ + m;
}

/** Signed distance to the footprint rectangle (negative inside). */
export function manhattanCityRectDistanceM(x, z) {
  const dx = Math.max(MANHATTAN_CITY_BOUNDS.minX - x, 0, x - MANHATTAN_CITY_BOUNDS.maxX);
  const dz = Math.max(MANHATTAN_CITY_BOUNDS.minZ - z, 0, z - MANHATTAN_CITY_BOUNDS.maxZ);
  if (dx === 0 && dz === 0) {
    return -Math.min(
      x - MANHATTAN_CITY_BOUNDS.minX,
      MANHATTAN_CITY_BOUNDS.maxX - x,
      z - MANHATTAN_CITY_BOUNDS.minZ,
      MANHATTAN_CITY_BOUNDS.maxZ - z,
    );
  }
  return Math.hypot(dx, dz);
}

/**
 * Plateau blend factor: 1 inside the footprint (fully flat at base height),
 * easing to 0 across MANHATTAN_CITY_BLEND_M outside it.
 */
export function manhattanCityPlateauFactor(x, z) {
  const outsideM = Math.max(0, manhattanCityRectDistanceM(x, z));
  return 1 - smoothstep(0, MANHATTAN_CITY_BLEND_M, outsideM);
}

/** Convert a city-local point to world coordinates (no rotation). */
export function manhattanLocalToWorld(localX, localZ) {
  return {
    x: MANHATTAN_CITY_CENTER.x + finite(localX, 0),
    z: MANHATTAN_CITY_CENTER.z + finite(localZ, 0),
  };
}

let cachedColliders = null;

/**
 * World-space OBB colliders for the foundation ColliderIndex, built from the
 * generated city-local rectangles [centerX, centerZ, halfWidth, halfDepth].
 * The city is placed axis-aligned, so rotationY is 0.
 */
export function buildManhattanWorldColliders() {
  if (cachedColliders) return cachedColliders;
  const rectangles = MANHATTAN_CITY_DATA?.colliders?.rectangles || [];
  cachedColliders = rectangles.map((rect, index) => {
    const world = manhattanLocalToWorld(rect[0], rect[1]);
    return {
      id: `manhattan-${index}`,
      kind: 'obb',
      x: world.x,
      z: world.z,
      halfWidthM: Math.max(0.1, finite(rect[2], 1)),
      halfDepthM: Math.max(0.1, finite(rect[3], 1)),
      rotationY: 0,
    };
  });
  return cachedColliders;
}

/** Chunk descriptors (city-local) straight from the conversion output. */
export function manhattanCityChunks() {
  return MANHATTAN_CITY_DATA?.layout?.chunks || [];
}

export function manhattanCityStats() {
  return {
    assetKey: MANHATTAN_CITY_DATA?.assetKey || 'kingsford-manhattan-city',
    center: { ...MANHATTAN_CITY_CENTER },
    baseHeightM: MANHATTAN_CITY_BASE_HEIGHT_M,
    bounds: { ...MANHATTAN_CITY_BOUNDS },
    localBounds: MANHATTAN_CITY_DATA?.transform?.localBounds || null,
    chunks: manhattanCityChunks().length,
    colliders: buildManhattanWorldColliders().length,
    glbBytes: MANHATTAN_CITY_DATA?.stats?.glbBytes || 0,
    glbSha256: MANHATTAN_CITY_DATA?.stats?.glbSha256 || null,
    outputTriangles: MANHATTAN_CITY_DATA?.stats?.outputTriangles || 0,
  };
}
