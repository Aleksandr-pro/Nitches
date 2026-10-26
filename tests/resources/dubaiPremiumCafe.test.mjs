import assert from 'node:assert/strict';
import { readFile, stat } from 'node:fs/promises';
import test from 'node:test';
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

const modelPath = 'src/assets/models/props/dubai_premium_cafe.glb';
const expectedMaterials = [
  'CafeBronze',
  'CafeCeramic',
  'CafeCounter',
  'CafeCream',
  'CafeGlass',
  'CafeGreen',
  'CafeLimestone',
  'CafeOak',
  'CafeSteel',
  'CafeTravertine',
  'CafeWarmLight',
];

async function loadCafe() {
  const buffer = await readFile(modelPath);
  const data = buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
  const loader = new GLTFLoader();
  return new Promise((resolve, reject) => loader.parse(data, '', resolve, reject));
}

test('Dubai premium cafe GLB is a compact, reusable, ground-level asset', async () => {
  const info = await stat(modelPath);
  assert.ok(info.size > 100_000 && info.size < 1_000_000, `unexpected GLB size: ${info.size}`);

  const gltf = await loadCafe();
  const box = new THREE.Box3().setFromObject(gltf.scene);
  const size = box.getSize(new THREE.Vector3());
  assert.ok(size.x > 10.8 && size.x < 11.6, `unexpected frontage: ${size.x}`);
  assert.ok(size.y > 4.3 && size.y < 4.6, `unexpected height: ${size.y}`);
  assert.ok(size.z > 8.5 && size.z < 9.1, `unexpected depth: ${size.z}`);
  assert.ok(Math.abs(box.min.y) < 0.001, 'model origin must sit on the ground plane');

  const materialNames = new Set();
  let meshCount = 0;
  let triangleCount = 0;
  gltf.scene.traverse((node) => {
    if (!node.isMesh) return;
    meshCount += 1;
    const count = node.geometry.index?.count ?? node.geometry.attributes.position.count;
    triangleCount += Math.floor(count / 3);
    const materials = Array.isArray(node.material) ? node.material : [node.material];
    materials.forEach((material) => material?.name && materialNames.add(material.name));
  });
  assert.equal(meshCount, 11, 'expected a small number of material-batched meshes');
  assert.ok(triangleCount > 5_000 && triangleCount < 12_000, `unexpected triangle count: ${triangleCount}`);
  assert.deepEqual([...materialNames].sort(), expectedMaterials);
});
