#!/usr/bin/env node
/**
 * Parse a GLB with Three.js GLTFLoader.
 *
 * Default mode verifies the car node contract. Passing --generic validates a
 * self-contained environment/model GLB instead (no wheel nodes required).
 */
import { readFile, stat } from 'node:fs/promises';
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

const requiredWheels = ['Wheel_FL', 'Wheel_FR', 'Wheel_RL', 'Wheel_RR'];
const unsupportedRequiredExtensions = new Set([
  'KHR_draco_mesh_compression',
  'EXT_meshopt_compression',
  'KHR_texture_basisu',
]);

function parseGlbJson(buffer) {
  if (buffer.length < 20) throw new Error('file is too small to be a GLB');
  const magic = buffer.readUInt32LE(0);
  if (magic !== 0x46546c67) throw new Error('missing "glTF" magic header');
  const version = buffer.readUInt32LE(4);
  if (version !== 2) throw new Error(`unsupported GLB version ${version}; expected 2`);
  const declaredLength = buffer.readUInt32LE(8);
  if (declaredLength !== buffer.length) {
    throw new Error(`GLB length field is ${declaredLength}, actual file size is ${buffer.length}`);
  }
  const jsonLength = buffer.readUInt32LE(12);
  const jsonType = buffer.readUInt32LE(16);
  if (jsonType !== 0x4e4f534a) throw new Error('first GLB chunk is not JSON');
  if (20 + jsonLength > buffer.length) throw new Error('JSON chunk extends beyond end of file');
  return JSON.parse(buffer.subarray(20, 20 + jsonLength).toString('utf8').trimEnd());
}

function safeNumber(value) {
  return Number(Number(value).toFixed(6));
}

async function validate(file, { generic = false } = {}) {
  const buffer = await readFile(file);
  const info = await stat(file);
  const gltfJson = parseGlbJson(buffer);
  const data = buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
  const loader = new GLTFLoader();
  const gltf = await new Promise((resolve, reject) => loader.parse(data, '', resolve, reject));

  const nodes = [];
  const materials = new Set();
  let meshes = 0;
  let triangles = 0;
  let vertices = 0;
  let meshesWithVertexColors = 0;
  gltf.scene.updateMatrixWorld(true);
  gltf.scene.traverse((object) => {
    if (object.name) nodes.push(object.name);
    if (object.isMesh) {
      meshes += 1;
      const geometry = object.geometry;
      const positionCount = geometry.attributes.position?.count || 0;
      const count = geometry.index ? geometry.index.count : positionCount;
      vertices += positionCount;
      triangles += Math.floor(count / 3);
      if (geometry.getAttribute('color')) meshesWithVertexColors += 1;
      const meshMaterials = Array.isArray(object.material) ? object.material : [object.material];
      meshMaterials.forEach((material) => {
        if (material?.name) materials.add(material.name);
      });
    }
  });

  const box = new THREE.Box3().setFromObject(gltf.scene);
  const size = box.getSize(new THREE.Vector3());
  const center = box.getCenter(new THREE.Vector3());

  let wheels = null;
  if (generic) {
    if (meshes === 0) throw new Error('generic GLB contains no meshes');
    if (triangles === 0) throw new Error('generic GLB contains no triangles');
    if (![box.min.x, box.min.y, box.min.z, box.max.x, box.max.y, box.max.z].every(Number.isFinite)) {
      throw new Error('generic GLB has non-finite bounds');
    }
    if (!(size.x > 0 && size.y > 0 && size.z > 0)) {
      throw new Error(`generic GLB bounds are degenerate: ${size.x} x ${size.y} x ${size.z}`);
    }
    const externalBuffers = (gltfJson.buffers || []).filter((item) => item.uri);
    if (externalBuffers.length) throw new Error('generic GLB must not reference external buffers');
    const requiredExtensions = gltfJson.extensionsRequired || [];
    const unsupported = requiredExtensions.filter((name) => unsupportedRequiredExtensions.has(name));
    if (unsupported.length) {
      throw new Error(`generic GLB requires unsupported extensions: ${unsupported.join(', ')}`);
    }
  } else {
    const missing = requiredWheels.filter((name) => !gltf.scene.getObjectByName(name));
    const missingSpin = requiredWheels.filter((name) => !gltf.scene.getObjectByName(`${name}_Spin`));
    if (missing.length || missingSpin.length) {
      throw new Error(
        `Missing wheel nodes: ${[...missing, ...missingSpin.map((name) => `${name}_Spin`)].join(', ')}`
      );
    }
    wheels = {};
    for (const name of requiredWheels) {
      const pivot = gltf.scene.getObjectByName(name);
      const position = pivot.getWorldPosition(new THREE.Vector3());
      wheels[name] = [position.x, position.y, position.z].map(safeNumber);
    }
  }

  return {
    file,
    mode: generic ? 'generic' : 'car',
    bytes: info.size,
    meshes,
    vertices,
    meshesWithVertexColors,
    triangles,
    nodes,
    materials: [...materials].sort(),
    gltf: {
      images: gltfJson.images?.length || 0,
      textures: gltfJson.textures?.length || 0,
      extensionsUsed: gltfJson.extensionsUsed || [],
      extensionsRequired: gltfJson.extensionsRequired || [],
    },
    bounds: {
      min: [box.min.x, box.min.y, box.min.z].map(safeNumber),
      max: [box.max.x, box.max.y, box.max.z].map(safeNumber),
      sizeXYZ: [size.x, size.y, size.z].map(safeNumber),
      center: [center.x, center.y, center.z].map(safeNumber),
    },
    wheels,
    animations: gltf.animations.length,
  };
}

const rawArgs = process.argv.slice(2);
if (rawArgs.includes('--help') || rawArgs.includes('-h')) {
  console.log('Usage: node scripts/validate-glb-loader.mjs [--generic] <file.glb> [...]');
  process.exit(0);
}
const generic = rawArgs.includes('--generic');
const files = rawArgs.filter((arg) => !arg.startsWith('--'));
if (!files.length) {
  console.error('Usage: node scripts/validate-glb-loader.mjs [--generic] <file.glb> [...]');
  process.exit(2);
}

for (const file of files) {
  const result = await validate(file, { generic });
  console.log(JSON.stringify(result, null, 2));
}
