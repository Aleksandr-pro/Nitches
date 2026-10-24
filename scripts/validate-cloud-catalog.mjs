#!/usr/bin/env node
/**
 * Validate a local R2 staging bundle or an already-published public catalog.
 * Unlike the vehicle loader checker, this validator is profile-neutral: a
 * cloud GLB must be self-contained and parseable, but static assets do not
 * need car wheel nodes.
 */
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import * as THREE from 'three';
import { normalizeAssetBaseUrl } from '../src/resources/assetConfig.js';
import {
  buildAssetUrl,
  collectAssetFiles,
  fetchCatalog,
  validateCurrentPointer,
  validateManifest,
} from '../src/resources/assetManifest.js';
import {
  assertSelfContainedGlb,
  disposeObject3D,
  parseGltfArrayBuffer,
} from '../src/resources/gltfAssetFactory.js';

export const CLOUD_CATALOG_VALIDATION_DEFAULT_BUNDLE = '.cloud-assets/staging';

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function toArrayBuffer(bytes) {
  if (bytes instanceof ArrayBuffer) return bytes;
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
}

function parseJson(bytes, label) {
  try {
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch (error) {
    throw new Error(`${label} is not valid JSON`, { cause: error });
  }
}

function resolveBundleKey(bundleDir, key) {
  const destination = path.resolve(bundleDir, ...key.split('/'));
  const relative = path.relative(bundleDir, destination);
  if (relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) {
    throw new Error(`Catalog key escapes the staging bundle: ${key}`);
  }
  return destination;
}

export function summarizeObject3D(root) {
  let meshCount = 0;
  let triangleCount = 0;
  let vertexCount = 0;

  root?.traverse?.((object) => {
    if (!object.isMesh || !object.geometry) return;
    meshCount += 1;
    const geometry = object.geometry;
    const positionCount = geometry.getAttribute?.('position')?.count || 0;
    vertexCount += positionCount;
    let drawCount = geometry.index?.count ?? positionCount;
    const drawRangeCount = geometry.drawRange?.count;
    if (Number.isFinite(drawRangeCount)) drawCount = Math.min(drawCount, drawRangeCount);
    triangleCount += Math.floor(drawCount / 3);
  });

  const box = root ? new THREE.Box3().setFromObject(root) : null;
  const bounds = box && !box.isEmpty()
    ? {
      min: box.min.toArray(),
      max: box.max.toArray(),
      size: box.getSize(new THREE.Vector3()).toArray(),
    }
    : null;

  return { meshCount, triangleCount, vertexCount, bounds };
}

async function inspectGlb(bytes) {
  const buffer = toArrayBuffer(bytes);
  assertSelfContainedGlb(buffer);
  const gltf = await parseGltfArrayBuffer(buffer);
  try {
    return summarizeObject3D(gltf.scene);
  } finally {
    disposeObject3D(gltf.scene);
  }
}

async function checkFileBytes(fileRef, bytes, { parseGlb }) {
  if (bytes.byteLength !== fileRef.sizeBytes) {
    throw new Error(
      `Size mismatch for ${fileRef.key}: expected ${fileRef.sizeBytes}, got ${bytes.byteLength}`,
    );
  }
  const actualSha256 = sha256(bytes);
  if (actualSha256 !== fileRef.sha256) {
    throw new Error(
      `SHA-256 mismatch for ${fileRef.key}: expected ${fileRef.sha256}, got ${actualSha256}`,
    );
  }

  return {
    key: fileRef.key,
    sha256: fileRef.sha256,
    sizeBytes: fileRef.sizeBytes,
    mediaType: fileRef.mediaType,
    role: fileRef.role,
    ...(parseGlb && fileRef.key.toLowerCase().endsWith('.glb')
      ? { glb: await inspectGlb(bytes) }
      : {}),
  };
}

function selectFiles(manifest, assetId) {
  return assetId
    ? collectAssetFiles(manifest, assetId)
    : [...manifest.filesByHash.values()];
}

function summary({ source, location, pointer, manifest, assetId, checkedFiles }) {
  return {
    valid: true,
    source,
    location,
    catalogVersion: manifest.catalogVersion,
    pointer,
    assetCount: manifest.assetsById.size,
    checkedAssets: assetId ? [assetId] : [...manifest.assetsById.keys()],
    checkedFiles,
  };
}

export async function validateCloudCatalogBundle({
  bundleDir = CLOUD_CATALOG_VALIDATION_DEFAULT_BUNDLE,
  assetId = null,
  parseGlb = true,
} = {}) {
  const resolvedBundleDir = path.resolve(bundleDir);
  const pointerBytes = await readFile(resolveBundleKey(resolvedBundleDir, 'manifests/current.json'));
  const pointer = validateCurrentPointer(parseJson(pointerBytes, 'Current catalog pointer'));

  const manifestBytes = await readFile(resolveBundleKey(resolvedBundleDir, pointer.manifestPath));
  if (manifestBytes.length !== pointer.manifestSizeBytes) {
    throw new Error(
      `Versioned manifest size mismatch: expected ${pointer.manifestSizeBytes}, got ${manifestBytes.length}`,
    );
  }
  const actualManifestSha256 = sha256(manifestBytes);
  if (actualManifestSha256 !== pointer.manifestSha256) {
    throw new Error(
      `Versioned manifest SHA-256 mismatch: expected ${pointer.manifestSha256}, got ${actualManifestSha256}`,
    );
  }

  const manifest = validateManifest(parseJson(manifestBytes, 'Versioned asset manifest'));
  if (manifest.catalogVersion !== pointer.catalogVersion) {
    throw new Error(
      `Catalog version mismatch: pointer ${pointer.catalogVersion}, manifest ${manifest.catalogVersion}`,
    );
  }

  const checkedFiles = [];
  for (const fileRef of selectFiles(manifest, assetId)) {
    const bytes = await readFile(resolveBundleKey(resolvedBundleDir, fileRef.key));
    checkedFiles.push(await checkFileBytes(fileRef, bytes, { parseGlb }));
  }

  return summary({
    source: 'local',
    location: resolvedBundleDir,
    pointer,
    manifest,
    assetId,
    checkedFiles,
  });
}

export async function validateRemoteCloudCatalog({
  baseUrl,
  assetId = null,
  parseGlb = true,
  fetchImpl = globalThis.fetch?.bind(globalThis),
} = {}) {
  const normalizedBaseUrl = normalizeAssetBaseUrl(baseUrl);
  if (!normalizedBaseUrl) throw new Error(`Invalid public asset base URL: ${baseUrl}`);
  if (typeof fetchImpl !== 'function') throw new Error('fetch is unavailable in this runtime');

  const fetched = await fetchCatalog({
    baseUrl: normalizedBaseUrl,
    fetchImpl,
    hashArrayBuffer: async (buffer) => sha256(Buffer.from(buffer)),
  });

  const checkedFiles = [];
  for (const fileRef of selectFiles(fetched.manifest, assetId)) {
    const url = buildAssetUrl(normalizedBaseUrl, fileRef.key);
    const response = await fetchImpl(url, {
      method: 'GET',
      credentials: 'omit',
    });
    if (!response.ok) throw new Error(`Remote asset request failed (${response.status}): ${url}`);
    const bytes = Buffer.from(await response.arrayBuffer());
    checkedFiles.push(await checkFileBytes(fileRef, bytes, { parseGlb }));
  }

  return summary({
    source: 'remote',
    location: normalizedBaseUrl,
    pointer: fetched.pointer,
    manifest: fetched.manifest,
    assetId,
    checkedFiles,
  });
}

export async function validateCloudCatalog(options = {}) {
  return options.baseUrl
    ? validateRemoteCloudCatalog(options)
    : validateCloudCatalogBundle(options);
}

function parseArgs(argv) {
  const options = {};
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = () => {
      i += 1;
      if (i >= argv.length) throw new Error(`Missing value for ${arg}`);
      return argv[i];
    };
    if (arg === '--bundle') options.bundleDir = next();
    else if (arg === '--base-url') options.baseUrl = next();
    else if (arg === '--asset') options.assetId = next();
    else if (arg === '--skip-parse') options.parseGlb = false;
    else if (!arg.startsWith('-') && !options.bundleDir) options.bundleDir = arg;
    else throw new Error(`Unknown argument: ${arg}`);
  }
  return options;
}

async function main() {
  const result = await validateCloudCatalog(parseArgs(process.argv.slice(2)));
  console.log(JSON.stringify(result, null, 2));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
