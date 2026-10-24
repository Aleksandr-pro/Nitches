/*
 * Pure geometry-data builders for terrain tiles.  The Three adapter turns
 * these typed arrays into BufferGeometry objects; tests can verify topology
 * and bounds without a renderer.
 */

function finite(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function normalize3(x, y, z) {
  const length = Math.hypot(x, y, z) || 1;
  return [x / length, y / length, z / length];
}

export function buildTerrainTileGeometry(tile, { colorAt = null, uvScaleM = 32 } = {}) {
  const side = tile.vertexCountPerSide;
  const positions = new Float32Array(side * side * 3);
  const normals = new Float32Array(side * side * 3);
  const uvs = new Float32Array(side * side * 2);
  const colors = colorAt ? new Float32Array(side * side * 3) : null;
  const indices = [];

  const heightAtGrid = (vx, vz) => {
    const cx = Math.max(0, Math.min(side - 1, vx));
    const cz = Math.max(0, Math.min(side - 1, vz));
    return tile.heights[cz * side + cx];
  };

  for (let vz = 0; vz < side; vz++) {
    for (let vx = 0; vx < side; vx++) {
      const index = vz * side + vx;
      const wx = tile.originX + vx * tile.stepM;
      const wz = tile.originZ + vz * tile.stepM;
      const h = tile.heights[index];
      positions[index * 3] = wx;
      positions[index * 3 + 1] = h;
      positions[index * 3 + 2] = wz;

      const dx = (heightAtGrid(vx + 1, vz) - heightAtGrid(vx - 1, vz)) / (2 * tile.stepM);
      const dz = (heightAtGrid(vx, vz + 1) - heightAtGrid(vx, vz - 1)) / (2 * tile.stepM);
      const normal = normalize3(-dx, 1, -dz);
      normals[index * 3] = normal[0];
      normals[index * 3 + 1] = normal[1];
      normals[index * 3 + 2] = normal[2];

      uvs[index * 2] = wx / Math.max(1, finite(uvScaleM, 32));
      uvs[index * 2 + 1] = wz / Math.max(1, finite(uvScaleM, 32));

      if (colors) {
        const slope = Math.hypot(dx, dz);
        const color = colorAt(wx, wz, h, slope) || [0.46, 0.62, 0.34];
        colors[index * 3] = finite(color[0], 0.46);
        colors[index * 3 + 1] = finite(color[1], 0.62);
        colors[index * 3 + 2] = finite(color[2], 0.34);
      }
    }
  }

  for (let vz = 0; vz < tile.cells; vz++) {
    for (let vx = 0; vx < tile.cells; vx++) {
      const a = vz * side + vx;
      const b = a + 1;
      const c = a + side;
      const d = c + 1;
      indices.push(a, c, b, b, c, d);
    }
  }

  return {
    positions,
    normals,
    uvs,
    colors,
    indices: new Uint32Array(indices),
    vertexCount: side * side,
    triangleCount: indices.length / 3,
    bounds: {
      minX: tile.originX,
      minY: tile.minHeightM,
      minZ: tile.originZ,
      maxX: tile.originX + tile.chunkSizeM,
      maxY: tile.maxHeightM,
      maxZ: tile.originZ + tile.chunkSizeM,
    },
  };
}

export function mergeGeometryData(geometries) {
  const list = (geometries || []).filter((geometry) => geometry && geometry.positions?.length);
  if (!list.length) {
    return {
      positions: new Float32Array(),
      normals: null,
      uvs: new Float32Array(),
      indices: new Uint32Array(),
      vertexCount: 0,
      triangleCount: 0,
    };
  }
  let vertexCount = 0;
  let indexCount = 0;
  for (const geometry of list) {
    vertexCount += geometry.positions.length / 3;
    indexCount += geometry.indices.length;
  }
  const hasNormals = list.every((geometry) => geometry.normals?.length === geometry.positions.length);
  const positions = new Float32Array(vertexCount * 3);
  const normals = hasNormals ? new Float32Array(vertexCount * 3) : null;
  const uvs = new Float32Array(vertexCount * 2);
  const indices = new Uint32Array(indexCount);
  let vertexOffset = 0;
  let positionOffset = 0;
  let uvOffset = 0;
  let indexOffset = 0;
  for (const geometry of list) {
    positions.set(geometry.positions, positionOffset);
    if (normals) normals.set(geometry.normals, positionOffset);
    if (geometry.uvs) uvs.set(geometry.uvs, uvOffset);
    for (let i = 0; i < geometry.indices.length; i++) indices[indexOffset + i] = geometry.indices[i] + vertexOffset;
    vertexOffset += geometry.positions.length / 3;
    positionOffset += geometry.positions.length;
    uvOffset += (geometry.uvs?.length || 0);
    indexOffset += geometry.indices.length;
  }
  return {
    positions,
    normals,
    uvs,
    indices,
    vertexCount,
    triangleCount: indices.length / 3,
  };
}
