/*
 * Deterministic 4x4 km heightfield foundation.
 *
 * The sampler is intentionally independent from Three.js and from the legacy
 * 640 m island.  Stage 3 uses an analytic sampler which can later be baked
 * into height tiles without changing chunk or physics-facing APIs.
 */

export const WORLD_SIZE_M = 4000;
export const WORLD_HALF_SIZE_M = WORLD_SIZE_M / 2;
export const DEFAULT_CHUNK_SIZE_M = 250;
export const DEFAULT_CHUNK_CELLS = 25;

function finite(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, finite(value, min)));
}

function lerp(a, b, t) {
  return a + (b - a) * t;
}

function smoothstep(edge0, edge1, value) {
  const t = clamp((value - edge0) / (edge1 - edge0), 0, 1);
  return t * t * (3 - 2 * t);
}

function hash2(ix, iz, seed) {
  let n = (ix * 374761393 + iz * 668265263 + seed * 1442695041) | 0;
  n = Math.imul(n ^ (n >>> 13), 1274126177);
  return ((n ^ (n >>> 16)) >>> 0) / 4294967295;
}

function valueNoise2(x, z, seed) {
  const ix = Math.floor(x);
  const iz = Math.floor(z);
  const fx = x - ix;
  const fz = z - iz;
  const sx = fx * fx * (3 - 2 * fx);
  const sz = fz * fz * (3 - 2 * fz);
  const a = hash2(ix, iz, seed);
  const b = hash2(ix + 1, iz, seed);
  const c = hash2(ix, iz + 1, seed);
  const d = hash2(ix + 1, iz + 1, seed);
  return lerp(lerp(a, b, sx), lerp(c, d, sx), sz);
}

function fbm2(x, z, seed, octaves = 4) {
  let value = 0;
  let amplitude = 0.5;
  let frequency = 1;
  let weight = 0;
  for (let i = 0; i < octaves; i++) {
    value += amplitude * valueNoise2(x * frequency, z * frequency, seed + i * 101);
    weight += amplitude;
    frequency *= 2.03;
    amplitude *= 0.5;
  }
  return value / Math.max(weight, Number.EPSILON);
}

function gaussian(x, z, cx, cz, height, sigma) {
  const dx = x - cx;
  const dz = z - cz;
  return height * Math.exp(-(dx * dx + dz * dz) / (2 * sigma * sigma));
}

function radialBlend(x, z, cx, cz, innerRadius, outerRadius) {
  const distance = Math.hypot(x - cx, z - cz);
  return 1 - smoothstep(innerRadius, outerRadius, distance);
}

/**
 * Raw Festival Britain landform.  Roads are flattened later by
 * the world foundation, using smoothed road elevation profiles.
 */
export function sampleFestivalBritainHeight(x, z, seed = 20261025) {
  const px = finite(x, 0);
  const pz = finite(z, 0);

  let height = 7
    + (fbm2(px * 0.00048 + 3.7, pz * 0.00048 - 1.9, seed, 4) - 0.5) * 24
    + (fbm2(px * 0.0021 - 8.2, pz * 0.0021 + 4.4, seed + 17, 4) - 0.5) * 7.5
    + (fbm2(px * 0.009 + 11.1, pz * 0.009 - 6.3, seed + 31, 3) - 0.5) * 1.5;

  // Lake District / West Highlands massifs and smaller landmark hills.
  height += gaussian(px, pz, -1420, -1150, 92, 500);
  height += gaussian(px, pz, -1550, -250, 72, 430);
  height += gaussian(px, pz, -100, -1250, 28, 540);
  height += gaussian(px, pz, 850, -1450, 48, 315);
  height += gaussian(px, pz, 1050, 850, 18, 380);
  height += gaussian(px, pz, -650, 650, 13, 430);

  // A lake bowl inside the north-western massif.  The road nodes use the
  // eastern shore, so the centre can remain below the water plane.
  const lakeBlend = radialBlend(px, pz, -1200, -1050, 150, 390);
  height = lerp(height, -5.5, lakeBlend * 0.96);

  // Buildable, flatter ground for the festival and city.  This is landform
  // shaping only; building plots arrive with district content stages.
  const festivalBlend = radialBlend(px, pz, 0, 1250, 260, 620);
  height = lerp(height, 6.5, festivalBlend * 0.82);
  const cityBlend = radialBlend(px, pz, 1250, -1050, 330, 700);
  height = lerp(height, 9.0, cityBlend * 0.78);
  const villageBlend = radialBlend(px, pz, -950, 250, 210, 520);
  height = lerp(height, 10.0, villageBlend * 0.52);

  // East and south playable edges become coast/beach.  The far side of the
  // border falls under water to make the playable limit readable.
  const eastCoast = smoothstep(1420, 1930, px);
  const southCoast = smoothstep(1420, 1930, pz);
  const coast = Math.max(eastCoast, southCoast);
  height = lerp(height, 1.4, coast * 0.86);

  const outside = Math.max(
    smoothstep(WORLD_HALF_SIZE_M, WORLD_HALF_SIZE_M + 260, Math.abs(px)),
    smoothstep(WORLD_HALF_SIZE_M, WORLD_HALF_SIZE_M + 260, Math.abs(pz)),
  );
  height = lerp(height, -8, outside);

  return Number.isFinite(height) ? height : 0;
}

export function createHeightSampler({ seed = 20261025 } = {}) {
  const safeSeed = Math.trunc(finite(seed, 20261025)) | 0;
  return (x, z) => sampleFestivalBritainHeight(x, z, safeSeed);
}

export function estimateHeightSlope(sampleHeight, x, z, epsilonM = 6) {
  const eps = Math.max(0.5, finite(epsilonM, 6));
  const dx = (sampleHeight(x + eps, z) - sampleHeight(x - eps, z)) / (2 * eps);
  const dz = (sampleHeight(x, z + eps) - sampleHeight(x, z - eps)) / (2 * eps);
  return {
    gradientX: dx,
    gradientZ: dz,
    magnitude: Math.hypot(dx, dz),
    angleRad: Math.atan(Math.hypot(dx, dz)),
  };
}

/**
 * Build one inclusive-vertex height tile.  Adjacent tiles duplicate the
 * shared edge vertices; because they call the same sampler, seams match.
 */
export function buildHeightTile({
  chunkX,
  chunkZ,
  chunkSizeM = DEFAULT_CHUNK_SIZE_M,
  cells = DEFAULT_CHUNK_CELLS,
  worldOriginM = -WORLD_HALF_SIZE_M,
  sampleHeight = createHeightSampler(),
} = {}) {
  const safeCells = Math.max(1, Math.trunc(finite(cells, DEFAULT_CHUNK_CELLS)));
  const size = Math.max(1, finite(chunkSizeM, DEFAULT_CHUNK_SIZE_M));
  const originX = worldOriginM + Math.trunc(chunkX) * size;
  const originZ = worldOriginM + Math.trunc(chunkZ) * size;
  const stepM = size / safeCells;
  const vertexCountPerSide = safeCells + 1;
  const heights = new Float32Array(vertexCountPerSide * vertexCountPerSide);
  let minHeightM = Infinity;
  let maxHeightM = -Infinity;

  for (let vz = 0; vz < vertexCountPerSide; vz++) {
    for (let vx = 0; vx < vertexCountPerSide; vx++) {
      const wx = originX + vx * stepM;
      const wz = originZ + vz * stepM;
      const h = finite(sampleHeight(wx, wz), 0);
      heights[vz * vertexCountPerSide + vx] = h;
      if (h < minHeightM) minHeightM = h;
      if (h > maxHeightM) maxHeightM = h;
    }
  }

  return {
    chunkX: Math.trunc(chunkX),
    chunkZ: Math.trunc(chunkZ),
    chunkKey: `${Math.trunc(chunkX)}_${Math.trunc(chunkZ)}`,
    originX,
    originZ,
    chunkSizeM: size,
    cells: safeCells,
    stepM,
    vertexCountPerSide,
    heights,
    minHeightM,
    maxHeightM,
  };
}

export function sampleHeightTile(tile, x, z) {
  if (!tile || !tile.heights) return 0;
  const localX = clamp((finite(x, tile.originX) - tile.originX) / tile.chunkSizeM, 0, 1) * tile.cells;
  const localZ = clamp((finite(z, tile.originZ) - tile.originZ) / tile.chunkSizeM, 0, 1) * tile.cells;
  const ix = Math.min(tile.cells - 1, Math.floor(localX));
  const iz = Math.min(tile.cells - 1, Math.floor(localZ));
  const fx = clamp(localX - ix, 0, 1);
  const fz = clamp(localZ - iz, 0, 1);
  const stride = tile.vertexCountPerSide;
  const i00 = iz * stride + ix;
  const h00 = tile.heights[i00];
  const h10 = tile.heights[i00 + 1];
  const h01 = tile.heights[i00 + stride];
  const h11 = tile.heights[i00 + stride + 1];
  return lerp(lerp(h00, h10, fx), lerp(h01, h11, fx), fz);
}
