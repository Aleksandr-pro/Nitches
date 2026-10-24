#!/usr/bin/env node
/**
 * Deterministic low-poly oak used only for the first Cloudflare R2 vertical
 * slice. It is intentionally generated from code instead of stored in the
 * APK: the same bytes can be reproduced in CI, hashed, published to R2, and
 * then loaded through ResourceManager.
 */
import { createHash } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import * as THREE from 'three';

export const CLOUD_OAK_ASSET_ID = 'tree_oak_001';
export const CLOUD_OAK_VERSION = '1.0.0';
export const CLOUD_OAK_DEFAULT_OUTPUT = '.cloud-assets/generated/tree_oak_001.glb';

const COMPONENT_TYPE = {
  UNSIGNED_INT: 5125,
  FLOAT: 5126,
};
const BUFFER_TARGET = {
  ARRAY_BUFFER: 34962,
  ELEMENT_ARRAY_BUFFER: 34963,
};

const MATERIALS = [
  { name: 'Bark', color: 0x5b3a26, roughness: 0.95 },
  { name: 'OakLeavesDeep', color: 0x1f7a3d, roughness: 0.92 },
  { name: 'OakLeavesBright', color: 0x39a85a, roughness: 0.9 },
  { name: 'OakLeavesCloudAccent', color: 0x19b89a, roughness: 0.88 },
  { name: 'CloudPrototypeMarker', color: 0xff7a1a, roughness: 0.65 },
];

function linearColorFactor(hex) {
  const color = new THREE.Color(hex);
  return [color.r, color.g, color.b, 1];
}

class GeometryBucket {
  constructor(materialIndex) {
    this.materialIndex = materialIndex;
    this.positions = [];
    this.normals = [];
    this.indices = [];
    this.vertexCount = 0;
    this.min = new THREE.Vector3(Infinity, Infinity, Infinity);
    this.max = new THREE.Vector3(-Infinity, -Infinity, -Infinity);
  }

  add(geometry) {
    const position = geometry.getAttribute('position');
    const normal = geometry.getAttribute('normal');
    if (!position || !normal) throw new Error('Generated geometry requires position and normal attributes');

    for (let i = 0; i < position.count; i += 1) {
      const x = position.getX(i);
      const y = position.getY(i);
      const z = position.getZ(i);
      this.positions.push(x, y, z);
      this.normals.push(normal.getX(i), normal.getY(i), normal.getZ(i));
      this.min.min(new THREE.Vector3(x, y, z));
      this.max.max(new THREE.Vector3(x, y, z));
      this.indices.push(this.vertexCount + i);
    }
    this.vertexCount += position.count;
  }

  get triangleCount() {
    return Math.floor(this.indices.length / 3);
  }
}

function makeBuckets() {
  return MATERIALS.map((_, index) => new GeometryBucket(index));
}

function addGeometry(buckets, materialIndex, geometry, {
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = [1, 1, 1],
  quaternion = null,
} = {}) {
  const flatGeometry = geometry.index ? geometry.toNonIndexed() : geometry.clone();
  geometry.dispose?.();
  const q = quaternion?.clone() || new THREE.Quaternion().setFromEuler(
    new THREE.Euler(rotation[0], rotation[1], rotation[2]),
  );
  const matrix = new THREE.Matrix4().compose(
    new THREE.Vector3(...position),
    q,
    new THREE.Vector3(...scale),
  );
  flatGeometry.applyMatrix4(matrix);
  flatGeometry.computeVertexNormals();
  buckets[materialIndex].add(flatGeometry);
  flatGeometry.dispose?.();
}

function addBranch(buckets, from, to, radiusBottom, radiusTop, materialIndex = 0, radialSegments = 8) {
  const start = new THREE.Vector3(...from);
  const end = new THREE.Vector3(...to);
  const direction = end.clone().sub(start);
  const length = direction.length();
  const quaternion = new THREE.Quaternion().setFromUnitVectors(
    new THREE.Vector3(0, 1, 0),
    direction.normalize(),
  );
  addGeometry(
    buckets,
    materialIndex,
    new THREE.CylinderGeometry(radiusTop, radiusBottom, length, radialSegments, 1, false),
    {
      position: start.add(end).multiplyScalar(0.5).toArray(),
      quaternion,
    },
  );
}

function buildOakBuckets() {
  const buckets = makeBuckets();

  // Slightly leaning trunk, root flare, and five visible branches. Units are
  // meters and the model origin is at ground level in the trunk center.
  addBranch(buckets, [0, 0, 0], [0.18, 3.35, 0.08], 0.39, 0.2, 0, 9);
  addGeometry(buckets, 0, new THREE.CylinderGeometry(0.5, 0.72, 0.46, 9, 1, false), {
    position: [0, 0.23, 0],
  });
  addBranch(buckets, [0.1, 2.35, 0.04], [-1.45, 4.05, 0.3], 0.16, 0.07);
  addBranch(buckets, [0.14, 2.65, 0.05], [1.45, 4.15, -0.2], 0.15, 0.07);
  addBranch(buckets, [0.16, 3.0, 0.06], [0.25, 5.25, -0.25], 0.13, 0.05);
  addBranch(buckets, [0.12, 2.8, 0.05], [-0.45, 4.85, 1.15], 0.12, 0.05);
  addBranch(buckets, [0.13, 2.9, 0.04], [0.95, 4.9, 1.0], 0.11, 0.05);
  addBranch(buckets, [0.16, 3.15, 0.05], [0, 5.9, 0.3], 0.1, 0.04);

  const canopyBlobs = [
    { center: [0, 4.85, 0], scale: [2.3, 1.45, 2.15], material: 2 },
    { center: [-1.55, 4.3, 0.35], scale: [1.35, 1.0, 1.25], material: 1 },
    { center: [1.55, 4.4, -0.25], scale: [1.45, 1.05, 1.3], material: 3 },
    { center: [0.35, 5.9, -0.3], scale: [1.55, 1.05, 1.45], material: 1 },
    { center: [-0.5, 5.35, 1.25], scale: [1.25, 0.9, 1.15], material: 3 },
    { center: [0.95, 5.3, 1.15], scale: [1.2, 0.85, 1.1], material: 2 },
    { center: [-1.0, 5.55, -1.1], scale: [1.15, 0.85, 1.05], material: 2 },
    { center: [1.2, 5.7, -1.0], scale: [1.05, 0.8, 1.0], material: 1 },
    { center: [0, 6.5, 0.35], scale: [1.05, 0.7, 0.95], material: 3 },
  ];
  canopyBlobs.forEach((blob, index) => {
    addGeometry(buckets, blob.material, new THREE.IcosahedronGeometry(1, 1), {
      position: blob.center,
      rotation: [index * 0.17, index * 0.41, index * 0.11],
      scale: blob.scale,
    });
  });

  // Unmistakable but small prototype markers: an orange ground ring, a trunk
  // band, and a few acorn-like points in the lower canopy.
  addGeometry(buckets, 4, new THREE.CylinderGeometry(0.64, 0.7, 0.09, 20, 1, false), {
    position: [0, 0.045, 0],
  });
  addGeometry(buckets, 4, new THREE.TorusGeometry(0.35, 0.05, 6, 20), {
    position: [0.06, 1.05, 0.02],
    rotation: [Math.PI / 2, 0, 0],
  });
  const acorns = [
    [-1.5, 3.55, 0.9], [-0.7, 3.7, -1.2], [0.25, 3.6, 1.55],
    [1.15, 3.75, 0.8], [1.75, 3.9, -0.75], [-0.15, 4.1, -1.65],
    [0.8, 4.2, -1.45], [-1.9, 4.1, -0.5],
  ];
  acorns.forEach((position, index) => {
    addGeometry(buckets, 4, new THREE.IcosahedronGeometry(0.1, 0), {
      position,
      rotation: [index * 0.3, index * 0.7, 0],
      scale: [1, 1.35, 1],
    });
  });

  return buckets;
}

function padTo4(buffer, padByte) {
  const padding = (4 - (buffer.length % 4)) % 4;
  return padding ? Buffer.concat([buffer, Buffer.alloc(padding, padByte)]) : buffer;
}

function typedArrayBytes(array) {
  return Buffer.from(array.buffer, array.byteOffset, array.byteLength);
}

function encodeGlb(buckets) {
  const binaryParts = [];
  const bufferViews = [];
  const accessors = [];
  const primitives = [];
  let byteOffset = 0;

  function appendView(bytes, target) {
    const viewIndex = bufferViews.length;
    bufferViews.push({
      buffer: 0,
      byteOffset,
      byteLength: bytes.length,
      target,
    });
    binaryParts.push(bytes);
    byteOffset += bytes.length;
    const padding = (4 - (byteOffset % 4)) % 4;
    if (padding) {
      binaryParts.push(Buffer.alloc(padding));
      byteOffset += padding;
    }
    return viewIndex;
  }

  for (const bucket of buckets) {
    if (!bucket.vertexCount) continue;
    const positions = new Float32Array(bucket.positions);
    const normals = new Float32Array(bucket.normals);
    const indices = new Uint32Array(bucket.indices);

    const positionView = appendView(typedArrayBytes(positions), BUFFER_TARGET.ARRAY_BUFFER);
    const positionAccessor = accessors.length;
    accessors.push({
      bufferView: positionView,
      componentType: COMPONENT_TYPE.FLOAT,
      count: bucket.vertexCount,
      type: 'VEC3',
      min: bucket.min.toArray(),
      max: bucket.max.toArray(),
    });

    const normalView = appendView(typedArrayBytes(normals), BUFFER_TARGET.ARRAY_BUFFER);
    const normalAccessor = accessors.length;
    accessors.push({
      bufferView: normalView,
      componentType: COMPONENT_TYPE.FLOAT,
      count: bucket.vertexCount,
      type: 'VEC3',
    });

    const indexView = appendView(typedArrayBytes(indices), BUFFER_TARGET.ELEMENT_ARRAY_BUFFER);
    const indexAccessor = accessors.length;
    accessors.push({
      bufferView: indexView,
      componentType: COMPONENT_TYPE.UNSIGNED_INT,
      count: indices.length,
      type: 'SCALAR',
    });

    primitives.push({
      attributes: { POSITION: positionAccessor, NORMAL: normalAccessor },
      indices: indexAccessor,
      material: bucket.materialIndex,
    });
  }

  const binary = Buffer.concat(binaryParts);
  const json = {
    asset: {
      version: '2.0',
      generator: 'Nitches Horizon cloud prototype tree generator',
      copyright: 'Generated in-project test asset for Cloudflare R2 delivery',
    },
    scene: 0,
    scenes: [{ name: 'TreeOak001Scene', nodes: [0] }],
    nodes: [{ name: 'tree_oak_001', mesh: 0 }],
    meshes: [{ name: 'TreeOak001Mesh', primitives }],
    materials: MATERIALS.map((material) => ({
      name: material.name,
      pbrMetallicRoughness: {
        baseColorFactor: linearColorFactor(material.color),
        metallicFactor: 0,
        roughnessFactor: material.roughness,
      },
      doubleSided: false,
    })),
    accessors,
    bufferViews,
    buffers: [{ byteLength: binary.length }],
  };

  const jsonChunk = padTo4(Buffer.from(JSON.stringify(json), 'utf8'), 0x20);
  const binaryChunk = padTo4(binary, 0x00);
  const totalLength = 12 + 8 + jsonChunk.length + 8 + binaryChunk.length;

  const header = Buffer.alloc(12);
  header.writeUInt32LE(0x46546c67, 0);
  header.writeUInt32LE(2, 4);
  header.writeUInt32LE(totalLength, 8);

  const jsonHeader = Buffer.alloc(8);
  jsonHeader.writeUInt32LE(jsonChunk.length, 0);
  jsonHeader.writeUInt32LE(0x4e4f534a, 4);

  const binaryHeader = Buffer.alloc(8);
  binaryHeader.writeUInt32LE(binaryChunk.length, 0);
  binaryHeader.writeUInt32LE(0x004e4942, 4);

  return Buffer.concat([header, jsonHeader, jsonChunk, binaryHeader, binaryChunk]);
}

function combineBounds(buckets) {
  const min = new THREE.Vector3(Infinity, Infinity, Infinity);
  const max = new THREE.Vector3(-Infinity, -Infinity, -Infinity);
  for (const bucket of buckets) {
    if (!bucket.vertexCount) continue;
    min.min(bucket.min);
    max.max(bucket.max);
  }
  const size = max.clone().sub(min);
  return Object.freeze({
    min: min.toArray(),
    max: max.toArray(),
    size: size.toArray(),
  });
}

export function buildCloudOakAsset() {
  const buckets = buildOakBuckets();
  const bytes = encodeGlb(buckets);
  const sha256 = createHash('sha256').update(bytes).digest('hex');
  return Object.freeze({
    bytes,
    sha256,
    sizeBytes: bytes.length,
    bounds: combineBounds(buckets),
    vertexCount: buckets.reduce((sum, bucket) => sum + bucket.vertexCount, 0),
    triangleCount: buckets.reduce((sum, bucket) => sum + bucket.triangleCount, 0),
  });
}

export function buildCloudOakGlb() {
  return buildCloudOakAsset().bytes;
}

async function main() {
  const output = process.argv[2] || CLOUD_OAK_DEFAULT_OUTPUT;
  const asset = buildCloudOakAsset();
  await mkdir(path.dirname(path.resolve(output)), { recursive: true });
  await writeFile(output, asset.bytes);
  console.log(JSON.stringify({
    output,
    sizeBytes: asset.sizeBytes,
    sha256: asset.sha256,
    vertexCount: asset.vertexCount,
    triangleCount: asset.triangleCount,
    bounds: asset.bounds,
  }, null, 2));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
