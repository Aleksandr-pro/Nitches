#!/usr/bin/env node
/**
 * Fail a build when a required 3D asset is still a Git LFS pointer.
 *
 * Vite happily copies a 130-byte pointer text file as if it were a .glb;
 * without this guard, a broken model would only be discovered in the browser
 * or inside an APK. This script checks the real file signatures/structure
 * before the build and compares public/ against dist/ after the build.
 */
import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { access, open, readdir, readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { PIPELINE_SMOKE_GLB, buildPipelineSmokeGlb } from './generate-pipeline-smoke-glb.mjs';

const ROOT = process.cwd();
const LFS_POINTER_PREFIX = 'version https://git-lfs.github.com/spec/v1\n';
const MODEL_EXTENSIONS = new Set([
  '.glb', '.fbx', '.blend', '.blend1', '.dae', '.3ds', '.max', '.ma', '.mb',
  '.obj', '.mtl', '.stl', '.ply', '.usdz', '.usdc',
]);
const TEXTURE_EXTENSIONS = new Set([
  '.png', '.jpg', '.jpeg', '.webp', '.ktx2', '.basis', '.tga', '.hdr', '.exr', '.dds', '.psd', '.xcf', '.tif', '.tiff',
]);
const ARCHIVE_EXTENSIONS = new Set(['.zip', '.7z', '.rar', '.tar', '.tgz']);
const IGNORED_DIRS = new Set(['.git', 'node_modules', 'dist', '.gradle']);
const WHEEL_NODE_NAMES = ['Wheel_FL', 'Wheel_FR', 'Wheel_RL', 'Wheel_RR'];

const args = new Set(process.argv.slice(2));
const checkDist = args.has('--dist');
// Runtime builds must never ship pointer files from public/. Editable source
// packages in asset-source/ can be large and are not needed to build the
// game, so by default an unmaterialized source pointer is only a warning.
// Use --all/--strict-source after `git lfs pull` when editing sources.
const strictSource = args.has('--all') || args.has('--strict-source');

function posixRelative(file) {
  return path.relative(ROOT, file).split(path.sep).join('/');
}

function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KiB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MiB`;
}

async function exists(file) {
  try {
    await access(file);
    return true;
  } catch {
    return false;
  }
}

async function readRange(file, start, length) {
  const handle = await open(file, 'r');
  try {
    const buffer = Buffer.alloc(length);
    const { bytesRead } = await handle.read(buffer, 0, length, start);
    return buffer.subarray(0, bytesRead);
  } finally {
    await handle.close();
  }
}

function sha256File(file) {
  return new Promise((resolve, reject) => {
    const hash = createHash('sha256');
    const stream = createReadStream(file);
    stream.on('error', reject);
    stream.on('data', (chunk) => hash.update(chunk));
    stream.on('end', () => resolve(hash.digest('hex')));
  });
}

async function inspectPointer(file, size) {
  if (size > 2048) return null;
  const head = await readRange(file, 0, Math.min(size, 1024));
  const text = head.toString('utf8');
  if (!text.startsWith(LFS_POINTER_PREFIX)) return null;
  const oid = text.match(/^oid sha256:([a-f0-9]{64})$/m)?.[1] || 'unknown';
  const declaredSize = text.match(/^size ([0-9]+)$/m)?.[1] || 'unknown';
  return { oid, declaredSize };
}

function isRelevant(file) {
  const rel = posixRelative(file);
  const ext = path.extname(file).toLowerCase();
  if (ext === '.gltf' || MODEL_EXTENSIONS.has(ext) || ext === '.bin') return true;
  const inAssetTree = rel.startsWith('public/assets/') || rel.startsWith('asset-source/');
  if (!inAssetTree) return false;
  if (TEXTURE_EXTENSIONS.has(ext)) return true;
  if (ARCHIVE_EXTENSIONS.has(ext)) return true;
  return rel.endsWith('.tar.gz');
}

async function walk(dir, out = []) {
  let entries;
  try {
    entries = await readdir(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    const rel = posixRelative(full);
    if (entry.isDirectory()) {
      if (IGNORED_DIRS.has(entry.name)) continue;
      if (rel === 'android/app/build' || rel.startsWith('android/app/build/')) continue;
      if (rel === 'android/app/src/main/assets/public' || rel.startsWith('android/app/src/main/assets/public/')) continue;
      await walk(full, out);
    } else if (entry.isFile() && isRelevant(full)) {
      out.push(full);
    }
  }
  return out;
}

async function parseGlb(file, size) {
  if (size < 20) throw new Error('file is too small to be a GLB');
  const header = await readRange(file, 0, 20);
  const magic = header.readUInt32LE(0);
  if (magic !== 0x46546c67) throw new Error('missing "glTF" magic header');
  const version = header.readUInt32LE(4);
  if (version !== 2) throw new Error(`unsupported GLB version ${version}; expected 2`);
  const declaredLength = header.readUInt32LE(8);
  if (declaredLength !== size) {
    throw new Error(`GLB length field is ${declaredLength}, actual file size is ${size}`);
  }

  const jsonLength = header.readUInt32LE(12);
  const jsonType = header.readUInt32LE(16);
  if (jsonType !== 0x4e4f534a) throw new Error('first GLB chunk is not JSON');
  if (20 + jsonLength > size) throw new Error('JSON chunk extends beyond end of file');
  const jsonText = (await readRange(file, 20, jsonLength)).toString('utf8').trimEnd();
  let gltf;
  try {
    gltf = JSON.parse(jsonText);
  } catch (error) {
    throw new Error(`invalid glTF JSON: ${error.message}`);
  }
  if (!String(gltf.asset?.version || '').startsWith('2')) {
    throw new Error(`glTF asset.version must be 2.x, got ${gltf.asset?.version || 'missing'}`);
  }

  const binaryHeaderOffset = 20 + jsonLength;
  let binaryLength = 0;
  if (binaryHeaderOffset + 8 <= size) {
    const binaryHeader = await readRange(file, binaryHeaderOffset, 8);
    binaryLength = binaryHeader.readUInt32LE(0);
    const binaryType = binaryHeader.readUInt32LE(4);
    if (binaryType !== 0x004e4942) throw new Error('second GLB chunk is not BIN');
    if (binaryHeaderOffset + 8 + binaryLength > size) throw new Error('BIN chunk extends beyond end of file');
  }
  const embeddedBufferLength = gltf.buffers?.[0]?.byteLength || 0;
  if (embeddedBufferLength > binaryLength) {
    throw new Error(`embedded buffer needs ${embeddedBufferLength} bytes, BIN chunk has ${binaryLength}`);
  }
  if (gltf.buffers?.[0]?.uri) {
    throw new Error('GLB first buffer must be embedded, not an external URI');
  }

  let triangles = 0;
  for (const mesh of gltf.meshes || []) {
    for (const primitive of mesh.primitives || []) {
      const indexAccessor = primitive.indices !== undefined ? gltf.accessors?.[primitive.indices] : null;
      const positionAccessor = primitive.attributes?.POSITION !== undefined
        ? gltf.accessors?.[primitive.attributes.POSITION]
        : null;
      const vertexOrIndexCount = indexAccessor?.count || positionAccessor?.count || 0;
      triangles += Math.floor(vertexOrIndexCount / 3);
    }
  }

  return {
    meshes: gltf.meshes?.length || 0,
    nodes: gltf.nodes?.length || 0,
    nodeNames: new Set((gltf.nodes || []).map((node) => node.name).filter(Boolean)),
    triangles,
  };
}

async function checkExternalGltf(file, errors, warnings) {
  const rel = posixRelative(file);
  let gltf;
  try {
    gltf = JSON.parse(await readFile(file, 'utf8'));
  } catch (error) {
    errors.push(`${rel}: invalid .gltf JSON (${error.message})`);
    return;
  }
  if (!String(gltf.asset?.version || '').startsWith('2')) {
    errors.push(`${rel}: glTF asset.version must be 2.x`);
  }
  const refs = [
    ...(gltf.buffers || []).map((item) => item.uri),
    ...(gltf.images || []).map((item) => item.uri),
  ].filter(Boolean);
  for (const uri of refs) {
    if (/^(data:|https?:)/i.test(uri)) {
      if (/^https?:/i.test(uri)) warnings.push(`${rel}: external HTTP resource is not bundled/offline-safe: ${uri}`);
      continue;
    }
    const sibling = path.resolve(path.dirname(file), decodeURIComponent(uri.split(/[?#]/)[0]));
    if (!(await exists(sibling))) {
      errors.push(`${rel}: referenced file is missing: ${uri}`);
      continue;
    }
    const siblingSize = (await stat(sibling)).size;
    const pointer = await inspectPointer(sibling, siblingSize);
    if (pointer) {
      errors.push(`${posixRelative(sibling)}: referenced by ${rel}, but is still an LFS pointer (oid ${pointer.oid})`);
    }
  }
}

function checkTextureMagic(ext, head, rel, warnings) {
  const is = (...bytes) => bytes.every((byte, index) => head[index] === byte);
  let ok = true;
  if (ext === '.png') ok = is(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a);
  else if (ext === '.jpg' || ext === '.jpeg') ok = is(0xff, 0xd8, 0xff);
  else if (ext === '.webp') ok = head.subarray(0, 4).toString('ascii') === 'RIFF' && head.subarray(8, 12).toString('ascii') === 'WEBP';
  else if (ext === '.ktx2') ok = is(0xab, 0x4b, 0x54, 0x58, 0x20, 0x32, 0x30, 0xbb);
  else if (ext === '.hdr') ok = head.subarray(0, 2).toString('ascii') === '#?';
  if (!ok) warnings.push(`${rel}: extension is ${ext}, but the file signature does not match`);
}

async function inspectAsset(file, errors, warnings) {
  const rel = posixRelative(file);
  const ext = path.extname(file).toLowerCase();
  const size = (await stat(file)).size;
  const pointer = await inspectPointer(file, size);
  if (pointer) {
    if (rel.startsWith('asset-source/') && !strictSource) {
      warnings.push(
        `${rel}: source LFS pointer is not materialized (oid ${pointer.oid}, real size ${pointer.declaredSize} bytes); ` +
        'not required for a runtime build. Pull asset-source/** and run npm run assets:check-all before editing this source.'
      );
      return null;
    }
    const pullHint = rel.startsWith('asset-source/')
      ? 'git lfs pull --include="asset-source/**" --exclude=""'
      : 'git lfs pull --include="public/assets/models/**" --exclude=""';
    errors.push(
      `${rel}: still a Git LFS pointer (oid ${pointer.oid}, real size ${pointer.declaredSize} bytes). Run: ${pullHint}`
    );
    return null;
  }
  if (size === 0) {
    errors.push(`${rel}: file is empty`);
    return null;
  }

  let detail = '';
  if (ext === '.glb') {
    try {
      const parsed = await parseGlb(file, size);
      detail = `, ${parsed.meshes} meshes, ${parsed.nodes} nodes, ~${parsed.triangles} triangles`;
      if (rel.startsWith('public/assets/models/cars/')) {
        const missingWheels = WHEEL_NODE_NAMES.filter((name) => !parsed.nodeNames.has(name));
        if (missingWheels.length) {
          warnings.push(`${rel}: missing recommended wheel node names: ${missingWheels.join(', ')}`);
        }
      }
      if (rel === PIPELINE_SMOKE_GLB) {
        const expected = buildPipelineSmokeGlb();
        if (size !== expected.length) {
          errors.push(`${rel}: pipeline fixture size differs from its generator (${size} vs ${expected.length})`);
        }
      }
    } catch (error) {
      errors.push(`${rel}: invalid GLB (${error.message})`);
    }
  } else if (ext === '.gltf') {
    await checkExternalGltf(file, errors, warnings);
    detail = ', glTF JSON + sidecars checked';
  } else if (TEXTURE_EXTENSIONS.has(ext)) {
    const head = await readRange(file, 0, Math.min(size, 16));
    checkTextureMagic(ext, head, rel, warnings);
  }

  const sha256 = await sha256File(file);
  if (rel === PIPELINE_SMOKE_GLB) {
    const expectedSha = createHash('sha256').update(buildPipelineSmokeGlb()).digest('hex');
    if (sha256 !== expectedSha) {
      errors.push(`${rel}: pipeline fixture SHA-256 differs from scripts/generate-pipeline-smoke-glb.mjs`);
    } else {
      detail += ', generator hash match';
    }
  }

  return { file, rel, size, sha256, detail };
}

async function checkDistCounterparts(sourceAssets, errors) {
  const distRoot = path.join(ROOT, 'dist');
  if (!(await exists(distRoot))) {
    errors.push('dist/: directory does not exist; run the Vite build before --dist validation');
    return;
  }
  for (const asset of sourceAssets) {
    if (!asset.rel.startsWith('public/')) continue;
    const distRel = `dist/${asset.rel.slice('public/'.length)}`;
    const distFile = path.join(ROOT, distRel);
    if (!(await exists(distFile))) {
      errors.push(`${distRel}: runtime asset was not copied from ${asset.rel}`);
      continue;
    }
    const distSize = (await stat(distFile)).size;
    const pointer = await inspectPointer(distFile, distSize);
    if (pointer) {
      errors.push(`${distRel}: build output is an LFS pointer, not real asset bytes`);
      continue;
    }
    const distSha = await sha256File(distFile);
    if (distSha !== asset.sha256) {
      errors.push(`${distRel}: SHA-256 does not match ${asset.rel}`);
    }
  }
}

async function main() {
  const files = (await walk(ROOT)).sort();
  const errors = [];
  const warnings = [];
  const assets = [];

  if (!files.length) {
    warnings.push('No LFS-managed 3D/texture assets were found. Add runtime .glb files under public/assets/models/ or sources under asset-source/.');
  }

  for (const file of files) {
    const asset = await inspectAsset(file, errors, warnings);
    if (asset) assets.push(asset);
  }

  if (checkDist) await checkDistCounterparts(assets, errors);

  for (const asset of assets) {
    console.log(`✓ ${asset.rel} (${formatBytes(asset.size)}, sha256 ${asset.sha256.slice(0, 12)}…${asset.detail})`);
  }
  for (const warning of warnings) console.warn(`⚠ ${warning}`);

  if (errors.length) {
    console.error('\nGit LFS / 3D asset validation failed:');
    for (const error of errors) console.error(`✗ ${error}`);
    process.exitCode = 1;
    return;
  }
  console.log(`✓ Git LFS asset validation passed (${assets.length} real asset file${assets.length === 1 ? '' : 's'} checked${checkDist ? ', including dist/' : ''}).`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
