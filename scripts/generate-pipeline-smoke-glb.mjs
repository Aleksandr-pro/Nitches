#!/usr/bin/env node
/**
 * Deterministic, dependency-free GLB fixture for the Git LFS pipeline.
 *
 * This is deliberately a tiny blocky car silhouette, not a gameplay model.
 * Keeping its generator in Git lets CI regenerate the expected bytes and
 * prove that the file materialized from Git LFS is the real GLB, byte for
 * byte, rather than an LFS pointer.
 */
import { createHash } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

export const PIPELINE_SMOKE_GLB = 'public/assets/models/_pipeline/pipeline-smoke.glb';

const COMPONENT_TYPE = {
  UNSIGNED_SHORT: 5123,
  FLOAT: 5126,
};
const BUFFER_TARGET = {
  ARRAY_BUFFER: 34962,
  ELEMENT_ARRAY_BUFFER: 34963,
};

function unitBoxGeometry() {
  // 24 vertices: four per face so every face can carry a flat normal.
  const p = 0.5;
  const faces = [
    // +Z
    { n: [0, 0, 1], v: [[-p, -p, p], [p, -p, p], [p, p, p], [-p, p, p]] },
    // -Z
    { n: [0, 0, -1], v: [[p, -p, -p], [-p, -p, -p], [-p, p, -p], [p, p, -p]] },
    // +X
    { n: [1, 0, 0], v: [[p, -p, p], [p, -p, -p], [p, p, -p], [p, p, p]] },
    // -X
    { n: [-1, 0, 0], v: [[-p, -p, -p], [-p, -p, p], [-p, p, p], [-p, p, -p]] },
    // +Y
    { n: [0, 1, 0], v: [[-p, p, p], [p, p, p], [p, p, -p], [-p, p, -p]] },
    // -Y
    { n: [0, -1, 0], v: [[-p, -p, -p], [p, -p, -p], [p, -p, p], [-p, -p, p]] },
  ];

  const positions = [];
  const normals = [];
  const indices = [];
  faces.forEach((face, faceIndex) => {
    const base = faceIndex * 4;
    face.v.forEach((vertex) => {
      positions.push(...vertex);
      normals.push(...face.n);
    });
    indices.push(base, base + 1, base + 2, base, base + 2, base + 3);
  });
  return {
    positions: new Float32Array(positions),
    normals: new Float32Array(normals),
    indices: new Uint16Array(indices),
  };
}

function padTo4(buffer, padByte) {
  const padding = (4 - (buffer.length % 4)) % 4;
  return padding ? Buffer.concat([buffer, Buffer.alloc(padding, padByte)]) : buffer;
}

export function buildPipelineSmokeGlb() {
  const geometry = unitBoxGeometry();
  const positionBytes = Buffer.from(geometry.positions.buffer, geometry.positions.byteOffset, geometry.positions.byteLength);
  const normalBytes = Buffer.from(geometry.normals.buffer, geometry.normals.byteOffset, geometry.normals.byteLength);
  const indexBytes = Buffer.from(geometry.indices.buffer, geometry.indices.byteOffset, geometry.indices.byteLength);
  const binary = Buffer.concat([positionBytes, normalBytes, indexBytes]);

  const json = {
    asset: {
      version: '2.0',
      generator: 'Nitches Horizon pipeline-smoke generator',
      copyright: 'Pipeline test fixture; not a gameplay car model',
    },
    scene: 0,
    scenes: [{ name: 'PipelineSmokeCarScene', nodes: [6] }],
    nodes: [
      { name: 'Body', mesh: 0, translation: [0, 0.55, 0], scale: [1.8, 0.55, 4.3] },
      { name: 'Cabin', mesh: 1, translation: [0, 1.06, -0.25], scale: [1.45, 0.48, 1.75] },
      { name: 'Wheel_FL', mesh: 2, translation: [-0.82, 0.34, 1.38], scale: [0.3, 0.68, 0.68] },
      { name: 'Wheel_FR', mesh: 2, translation: [0.82, 0.34, 1.38], scale: [0.3, 0.68, 0.68] },
      { name: 'Wheel_RL', mesh: 2, translation: [-0.82, 0.34, -1.38], scale: [0.3, 0.68, 0.68] },
      { name: 'Wheel_RR', mesh: 2, translation: [0.82, 0.34, -1.38], scale: [0.3, 0.68, 0.68] },
      { name: 'PipelineSmokeCar', children: [0, 1, 2, 3, 4, 5] },
    ],
    meshes: [
      { name: 'BodyBox', primitives: [{ attributes: { POSITION: 0, NORMAL: 1 }, indices: 2, material: 0 }] },
      { name: 'CabinBox', primitives: [{ attributes: { POSITION: 0, NORMAL: 1 }, indices: 2, material: 1 }] },
      { name: 'WheelBox', primitives: [{ attributes: { POSITION: 0, NORMAL: 1 }, indices: 2, material: 2 }] },
    ],
    materials: [
      {
        name: 'Paint',
        pbrMetallicRoughness: { baseColorFactor: [0.55, 0.08, 0.04, 1], metallicFactor: 0.35, roughnessFactor: 0.38 },
      },
      {
        name: 'Glass',
        pbrMetallicRoughness: { baseColorFactor: [0.03, 0.08, 0.12, 1], metallicFactor: 0.1, roughnessFactor: 0.18 },
      },
      {
        name: 'Tire',
        pbrMetallicRoughness: { baseColorFactor: [0.015, 0.015, 0.015, 1], metallicFactor: 0, roughnessFactor: 0.92 },
      },
    ],
    accessors: [
      {
        bufferView: 0,
        componentType: COMPONENT_TYPE.FLOAT,
        count: geometry.positions.length / 3,
        type: 'VEC3',
        min: [-0.5, -0.5, -0.5],
        max: [0.5, 0.5, 0.5],
      },
      {
        bufferView: 1,
        componentType: COMPONENT_TYPE.FLOAT,
        count: geometry.normals.length / 3,
        type: 'VEC3',
      },
      {
        bufferView: 2,
        componentType: COMPONENT_TYPE.UNSIGNED_SHORT,
        count: geometry.indices.length,
        type: 'SCALAR',
      },
    ],
    bufferViews: [
      { buffer: 0, byteOffset: 0, byteLength: positionBytes.length, target: BUFFER_TARGET.ARRAY_BUFFER },
      { buffer: 0, byteOffset: positionBytes.length, byteLength: normalBytes.length, target: BUFFER_TARGET.ARRAY_BUFFER },
      {
        buffer: 0,
        byteOffset: positionBytes.length + normalBytes.length,
        byteLength: indexBytes.length,
        target: BUFFER_TARGET.ELEMENT_ARRAY_BUFFER,
      },
    ],
    buffers: [{ byteLength: binary.length }],
  };

  const jsonChunk = padTo4(Buffer.from(JSON.stringify(json), 'utf8'), 0x20);
  const binaryChunk = padTo4(binary, 0x00);
  const totalLength = 12 + 8 + jsonChunk.length + 8 + binaryChunk.length;
  const header = Buffer.alloc(12);
  header.writeUInt32LE(0x46546c67, 0); // "glTF"
  header.writeUInt32LE(2, 4);
  header.writeUInt32LE(totalLength, 8);

  const jsonHeader = Buffer.alloc(8);
  jsonHeader.writeUInt32LE(jsonChunk.length, 0);
  jsonHeader.writeUInt32LE(0x4e4f534a, 4); // "JSON"

  const binaryHeader = Buffer.alloc(8);
  binaryHeader.writeUInt32LE(binaryChunk.length, 0);
  binaryHeader.writeUInt32LE(0x004e4942, 4); // "BIN\0"

  return Buffer.concat([header, jsonHeader, jsonChunk, binaryHeader, binaryChunk]);
}

export function pipelineSmokeGlbSha256() {
  return createHash('sha256').update(buildPipelineSmokeGlb()).digest('hex');
}

async function main() {
  const output = process.argv[2] || PIPELINE_SMOKE_GLB;
  const bytes = buildPipelineSmokeGlb();
  await mkdir(path.dirname(output), { recursive: true });
  await writeFile(output, bytes);
  const sha256 = createHash('sha256').update(bytes).digest('hex');
  console.log(`Wrote ${output} (${bytes.length} bytes, sha256 ${sha256})`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
