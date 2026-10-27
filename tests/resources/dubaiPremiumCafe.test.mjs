import assert from 'node:assert/strict';
import { readFile, stat } from 'node:fs/promises';
import test from 'node:test';

const modelPath = 'src/assets/models/props/dubai_premium_cafe.glb';
const expectedMaterials = [
  'CafeBronze',
  'CafeCeramic',
  'CafeCounter',
  'CafeCream',
  'CafeFabric',
  'CafeGlass',
  'CafeGreen',
  'CafeLimestone',
  'CafeOak',
  'CafeSteel',
  'CafeTravertine',
  'CafeWarmLight',
];

async function loadGlbJson() {
  const buffer = await readFile(modelPath);
  assert.equal(buffer.toString('utf8', 0, 4), 'glTF');
  assert.equal(buffer.readUInt32LE(4), 2);
  assert.equal(buffer.readUInt32LE(8), buffer.length);
  assert.equal(buffer.readUInt32LE(16), 0x4e4f534a, 'first GLB chunk must be JSON');
  const jsonLength = buffer.readUInt32LE(12);
  const gltf = JSON.parse(buffer.toString('utf8', 20, 20 + jsonLength).trimEnd());
  return { buffer, gltf };
}

test('Dubai premium cafe is a detailed self-contained PBR asset at real-world scale', async () => {
  const info = await stat(modelPath);
  assert.ok(info.size > 500_000 && info.size < 5_000_000, `unexpected GLB size: ${info.size}`);

  const { gltf } = await loadGlbJson();
  const meshCount = gltf.meshes.length;
  let triangleCount = 0;
  const vertexBounds = [];
  for (const mesh of gltf.meshes) {
    for (const primitive of mesh.primitives) {
      const positionAccessor = gltf.accessors[primitive.attributes.POSITION];
      assert.ok(positionAccessor, `${mesh.name} is missing vertex positions`);
      assert.ok(positionAccessor.min && positionAccessor.max, `${mesh.name} is missing bounds`);
      vertexBounds.push(positionAccessor);
      const vertexCount = primitive.indices === undefined
        ? positionAccessor.count
        : gltf.accessors[primitive.indices].count;
      triangleCount += Math.floor(vertexCount / 3);
      assert.ok(primitive.attributes.TEXCOORD_0 !== undefined, `${mesh.name} has no PBR UVs`);
    }
  }

  const min = [0, 1, 2].map((axis) => Math.min(...vertexBounds.map((accessor) => accessor.min[axis])));
  const max = [0, 1, 2].map((axis) => Math.max(...vertexBounds.map((accessor) => accessor.max[axis])));
  const size = max.map((value, axis) => value - min[axis]);
  assert.ok(size[0] > 10.8 && size[0] < 11.6, `unexpected frontage: ${size[0]}`);
  assert.ok(size[1] > 4.3 && size[1] < 4.6, `unexpected height: ${size[1]}`);
  assert.ok(size[2] > 8.5 && size[2] < 9.1, `unexpected depth: ${size[2]}`);
  assert.ok(Math.abs(min[1]) < 0.001, 'model origin must sit on the ground plane');

  assert.equal(meshCount, 12, 'expected distinct batched PBR material meshes');
  assert.ok(triangleCount > 10_000 && triangleCount < 20_000, `unexpected triangle count: ${triangleCount}`);
  assert.deepEqual(gltf.materials.map((material) => material.name).sort(), expectedMaterials);
  assert.ok(gltf.images.length >= 10, 'expected embedded albedo and normal maps');
  assert.ok(gltf.images.every((image) => Number.isInteger(image.bufferView) && !image.uri), 'all maps must be embedded in the GLB');
  assert.ok(gltf.materials.filter((material) => material.pbrMetallicRoughness?.baseColorTexture).length >= 8);
  assert.ok(gltf.materials.filter((material) => material.normalTexture).length >= 6);
});
