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

function validateTexturedGenericGlb(file, buffer, info, gltfJson) {
  const jsonLength = buffer.readUInt32LE(12);
  let chunkOffset = 20 + jsonLength;
  let binary = null;
  while (chunkOffset + 8 <= buffer.length) {
    const chunkLength = buffer.readUInt32LE(chunkOffset);
    const chunkType = buffer.readUInt32LE(chunkOffset + 4);
    const chunkStart = chunkOffset + 8;
    if (chunkStart + chunkLength > buffer.length) throw new Error('GLB chunk extends beyond the file');
    if (chunkType === 0x004e4942) binary = buffer.subarray(chunkStart, chunkStart + chunkLength);
    chunkOffset = chunkStart + chunkLength;
  }
  if (!binary) throw new Error('textured generic GLB has no binary chunk');
  if (gltfJson.buffers?.some((item) => item.uri)) throw new Error('generic GLB must not reference external buffers');
  if (gltfJson.buffers?.[0]?.byteLength > binary.length) throw new Error('GLB binary buffer is truncated');
  for (const view of gltfJson.bufferViews ?? []) {
    if ((view.byteOffset ?? 0) + view.byteLength > binary.length) throw new Error('GLB bufferView extends beyond its binary chunk');
  }

  const accessors = gltfJson.accessors ?? [];
  const meshes = gltfJson.meshes ?? [];
  const meshNodes = new Map();
  for (const [nodeIndex, node] of (gltfJson.nodes ?? []).entries()) {
    if (node.mesh !== undefined) {
      const indices = meshNodes.get(node.mesh) ?? [];
      indices.push(nodeIndex);
      meshNodes.set(node.mesh, indices);
    }
  }

  function positionBounds(primitive) {
    const accessorIndex = primitive.attributes?.POSITION;
    if (accessorIndex === undefined) throw new Error('generic mesh primitive has no POSITION accessor');
    const accessor = accessors[accessorIndex];
    if (!accessor || accessor.type !== 'VEC3' || !accessor.count) throw new Error('invalid POSITION accessor');
    if (accessor.min?.length === 3 && accessor.max?.length === 3) {
      return new THREE.Box3(
        new THREE.Vector3(...accessor.min),
        new THREE.Vector3(...accessor.max),
      );
    }
    const view = gltfJson.bufferViews?.[accessor.bufferView];
    if (!view || accessor.componentType !== 5126) throw new Error('POSITION accessor requires min/max bounds');
    const stride = view.byteStride ?? 12;
    const start = (view.byteOffset ?? 0) + (accessor.byteOffset ?? 0);
    const min = [Infinity, Infinity, Infinity];
    const max = [-Infinity, -Infinity, -Infinity];
    for (let i = 0; i < accessor.count; i += 1) {
      for (let axis = 0; axis < 3; axis += 1) {
        const value = binary.readFloatLE(start + i * stride + axis * 4);
        min[axis] = Math.min(min[axis], value);
        max[axis] = Math.max(max[axis], value);
      }
    }
    return new THREE.Box3(new THREE.Vector3(...min), new THREE.Vector3(...max));
  }

  let meshCount = 0;
  let triangles = 0;
  let vertices = 0;
  let meshesWithVertexColors = 0;
  const bounds = new THREE.Box3();
  const root = new THREE.Matrix4();
  function visit(nodeIndex, parentMatrix) {
    const node = gltfJson.nodes?.[nodeIndex];
    if (!node) throw new Error(`scene references missing node ${nodeIndex}`);
    let local = new THREE.Matrix4();
    if (node.matrix) {
      local.fromArray(node.matrix);
    } else {
      local.compose(
        new THREE.Vector3(...(node.translation ?? [0, 0, 0])),
        new THREE.Quaternion(...(node.rotation ?? [0, 0, 0, 1])),
        new THREE.Vector3(...(node.scale ?? [1, 1, 1])),
      );
    }
    const world = parentMatrix.clone().multiply(local);
    if (node.mesh !== undefined) {
      const mesh = meshes[node.mesh];
      if (!mesh) throw new Error(`node references missing mesh ${node.mesh}`);
      for (const primitive of mesh.primitives ?? []) {
        const position = accessors[primitive.attributes?.POSITION];
        const count = primitive.indices === undefined ? position?.count ?? 0 : accessors[primitive.indices]?.count ?? 0;
        const mode = primitive.mode ?? 4;
        if (mode === 4) triangles += Math.floor(count / 3);
        else if (mode === 5 || mode === 6) triangles += Math.max(0, count - 2);
        vertices += position?.count ?? 0;
        meshCount += 1;
        if (primitive.attributes?.COLOR_0 !== undefined) meshesWithVertexColors += 1;
        bounds.union(positionBounds(primitive).applyMatrix4(world));
      }
    }
    for (const child of node.children ?? []) visit(child, world);
  }
  const scene = gltfJson.scenes?.[gltfJson.scene ?? 0];
  if (scene?.nodes?.length) {
    for (const nodeIndex of scene.nodes) visit(nodeIndex, root);
  } else {
    const children = new Set((gltfJson.nodes ?? []).flatMap((node) => node.children ?? []));
    for (let i = 0; i < (gltfJson.nodes ?? []).length; i += 1) if (!children.has(i)) visit(i, root);
  }

  if (!meshCount || !triangles) throw new Error('generic GLB contains no renderable triangles');
  const size = bounds.getSize(new THREE.Vector3());
  if (![bounds.min.x, bounds.min.y, bounds.min.z, bounds.max.x, bounds.max.y, bounds.max.z].every(Number.isFinite)) {
    throw new Error('generic GLB has non-finite bounds');
  }
  if (!(size.x > 0 && size.y > 0 && size.z > 0)) throw new Error('generic GLB has degenerate bounds');
  const extensionsRequired = gltfJson.extensionsRequired ?? [];
  const unsupported = extensionsRequired.filter((name) => unsupportedRequiredExtensions.has(name));
  if (unsupported.length) throw new Error(`generic GLB requires unsupported extensions: ${unsupported.join(', ')}`);
  const nodes = (gltfJson.nodes ?? []).map((node) => node.name).filter(Boolean);
  const materials = (gltfJson.materials ?? []).map((material) => material.name).filter(Boolean).sort();
  const center = bounds.getCenter(new THREE.Vector3());
  return {
    file, mode: 'generic', bytes: info.size, meshes: meshCount, vertices, meshesWithVertexColors, triangles, nodes, materials,
    gltf: {
      images: gltfJson.images?.length ?? 0,
      textures: gltfJson.textures?.length ?? 0,
      extensionsUsed: gltfJson.extensionsUsed ?? [],
      extensionsRequired,
    },
    bounds: {
      min: [bounds.min.x, bounds.min.y, bounds.min.z].map(safeNumber),
      max: [bounds.max.x, bounds.max.y, bounds.max.z].map(safeNumber),
      sizeXYZ: [size.x, size.y, size.z].map(safeNumber),
      center: [center.x, center.y, center.z].map(safeNumber),
    },
    wheels: null,
    animations: gltfJson.animations?.length ?? 0,
  };
}

async function validate(file, { generic = false } = {}) {
  const buffer = await readFile(file);
  const info = await stat(file);
  const gltfJson = parseGlbJson(buffer);
  if (generic && (gltfJson.images?.length ?? 0) > 0) {
    return validateTexturedGenericGlb(file, buffer, info, gltfJson);
  }
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
