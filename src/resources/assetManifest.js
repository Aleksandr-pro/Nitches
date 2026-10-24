export const ASSET_SCHEMA_VERSION = 1;

const ID_PATTERN = /^[a-z][a-z0-9_-]{1,63}$/;
const VERSION_PATTERN = /^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/;
const SHA256_PATTERN = /^[a-f0-9]{64}$/;
const MAX_POINTER_BYTES = 64 * 1024;
const MAX_MANIFEST_BYTES = 5 * 1024 * 1024;
const MAX_FILES = 10000;
const MAX_ASSETS = 10000;
const ALLOWED_FILE_SUFFIXES = new Set([
  '.basis',
  '.bin',
  '.glb',
  '.gltf',
  '.jpeg',
  '.jpg',
  '.json',
  '.ktx2',
  '.png',
  '.webp',
]);
const COLLIDER_KINDS = new Set(['none', 'circle', 'cylinder', 'sphere', 'box']);

export class AssetManifestError extends Error {
  constructor(message, options) {
    super(message, options);
    this.name = 'AssetManifestError';
  }
}

function fail(message) {
  throw new AssetManifestError(message);
}

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function requirePlainObject(value, label) {
  if (!isPlainObject(value)) fail(`${label} must be an object`);
  return value;
}

function requireString(value, label) {
  if (typeof value !== 'string' || value.length === 0) fail(`${label} must be a non-empty string`);
  return value;
}

function optionalFiniteNumber(value, label) {
  if (value === undefined) return undefined;
  if (!Number.isFinite(value)) fail(`${label} must be a finite number`);
  return value;
}

function validateVector3(value, label) {
  if (!Array.isArray(value) || value.length !== 3 || value.some((item) => !Number.isFinite(item))) {
    fail(`${label} must be an array of three finite numbers`);
  }
  return [...value];
}

export function assertSafeRelativeKey(key, label = 'asset key') {
  requireString(key, label);
  if (key.startsWith('/') || key.includes('\\') || key.includes('?') || key.includes('#')) {
    fail(`${label} must be a relative POSIX key: ${key}`);
  }
  // eslint-disable-next-line no-control-regex
  if (/[\u0000-\u001f\u007f]/.test(key)) fail(`${label} contains control characters`);
  const segments = key.split('/');
  if (segments.some((segment) => !segment || segment === '.' || segment === '..')) {
    fail(`${label} contains an unsafe path segment: ${key}`);
  }
  const bytes = new TextEncoder().encode(key).length;
  if (bytes > 1024) fail(`${label} exceeds the 1024-byte R2 key limit`);
  return key;
}

export function buildAssetUrl(baseUrl, key) {
  requireString(baseUrl, 'asset base URL');
  assertSafeRelativeKey(key);
  const normalizedBase = baseUrl.replace(/\/+$/, '');
  const encodedKey = key.split('/').map((segment) => encodeURIComponent(segment)).join('/');
  return `${normalizedBase}/${encodedKey}`;
}

function validateSha256(value, label) {
  requireString(value, label);
  if (!SHA256_PATTERN.test(value)) fail(`${label} must be a lowercase SHA-256 hex string`);
  return value;
}

function validateSize(value, label, { allowZero = false } = {}) {
  if (!Number.isSafeInteger(value) || value < (allowZero ? 0 : 1)) {
    fail(`${label} must be a ${allowZero ? 'non-negative' : 'positive'} safe integer`);
  }
  return value;
}

export function validateCurrentPointer(data) {
  const pointer = requirePlainObject(data, 'current manifest pointer');
  if (pointer.schemaVersion !== ASSET_SCHEMA_VERSION) {
    fail(`Unsupported asset pointer schemaVersion: ${pointer.schemaVersion}`);
  }
  const catalogVersion = requireString(pointer.catalogVersion, 'pointer.catalogVersion');
  if (!VERSION_PATTERN.test(catalogVersion)) fail(`Invalid catalogVersion: ${catalogVersion}`);
  const manifestPath = assertSafeRelativeKey(pointer.manifestPath, 'pointer.manifestPath');
  const manifestSizeBytes = validateSize(pointer.manifestSizeBytes, 'pointer.manifestSizeBytes');
  if (manifestSizeBytes > MAX_MANIFEST_BYTES) fail('Versioned manifest is too large');
  const manifestSha256 = validateSha256(pointer.manifestSha256, 'pointer.manifestSha256');

  return Object.freeze({
    schemaVersion: ASSET_SCHEMA_VERSION,
    catalogVersion,
    manifestPath,
    manifestSizeBytes,
    manifestSha256,
    publishedAt: typeof pointer.publishedAt === 'string' ? pointer.publishedAt : null,
  });
}

function validateFileReference(sha256, file) {
  validateSha256(sha256, 'files key');
  const ref = requirePlainObject(file, `files.${sha256}`);
  if (ref.sha256 !== sha256) fail(`files.${sha256}.sha256 does not match its map key`);
  const key = assertSafeRelativeKey(ref.key, `files.${sha256}.key`);
  const dot = key.lastIndexOf('.');
  const suffix = dot >= 0 ? key.slice(dot).toLowerCase() : '';
  if (!ALLOWED_FILE_SUFFIXES.has(suffix)) fail(`Unsupported asset file suffix: ${key}`);
  const sizeBytes = validateSize(ref.sizeBytes, `files.${sha256}.sizeBytes`);
  const mediaType = typeof ref.mediaType === 'string' && ref.mediaType
    ? ref.mediaType
    : 'application/octet-stream';
  const role = typeof ref.role === 'string' && ref.role ? ref.role : 'file';

  return Object.freeze({ key, sizeBytes, sha256, mediaType, role });
}

function validateCollider(value, assetId) {
  if (value === undefined || value === null) return Object.freeze({ kind: 'none' });
  const collider = requirePlainObject(value, `assets.${assetId}.collider`);
  const kind = collider.kind || 'none';
  if (!COLLIDER_KINDS.has(kind)) fail(`Unsupported collider kind for ${assetId}: ${kind}`);
  const result = { kind };
  if (collider.center !== undefined) result.center = validateVector3(collider.center, `assets.${assetId}.collider.center`);
  if (collider.radius !== undefined) {
    result.radius = optionalFiniteNumber(collider.radius, `assets.${assetId}.collider.radius`);
    if (result.radius < 0) fail(`assets.${assetId}.collider.radius cannot be negative`);
  }
  if (collider.height !== undefined) {
    result.height = optionalFiniteNumber(collider.height, `assets.${assetId}.collider.height`);
    if (result.height < 0) fail(`assets.${assetId}.collider.height cannot be negative`);
  }
  if (collider.halfExtents !== undefined) {
    result.halfExtents = validateVector3(collider.halfExtents, `assets.${assetId}.collider.halfExtents`);
  }
  if (collider.size !== undefined) {
    result.size = validateVector3(collider.size, `assets.${assetId}.collider.size`);
  }
  return Object.freeze(result);
}

function validateBounds(value, assetId) {
  if (value === undefined || value === null) return null;
  const bounds = requirePlainObject(value, `assets.${assetId}.bounds`);
  return Object.freeze({
    min: validateVector3(bounds.min, `assets.${assetId}.bounds.min`),
    max: validateVector3(bounds.max, `assets.${assetId}.bounds.max`),
    size: bounds.size === undefined
      ? null
      : validateVector3(bounds.size, `assets.${assetId}.bounds.size`),
  });
}

function validateAsset(assetData, filesByHash, categoryIds) {
  const asset = requirePlainObject(assetData, 'asset');
  const id = requireString(asset.id, 'asset.id');
  if (!ID_PATTERN.test(id)) fail(`Invalid asset id: ${id}`);
  const type = requireString(asset.type, `assets.${id}.type`);
  if (!ID_PATTERN.test(type)) fail(`Invalid asset type for ${id}: ${type}`);
  if (categoryIds.size && !categoryIds.has(type)) fail(`Asset ${id} uses undeclared category: ${type}`);
  const version = requireString(asset.version, `assets.${id}.version`);
  if (!VERSION_PATTERN.test(version)) fail(`Invalid asset version for ${id}: ${version}`);

  const modelFile = validateSha256(asset.modelFile, `assets.${id}.modelFile`);
  if (!filesByHash.has(modelFile)) fail(`Asset ${id} references a missing model file: ${modelFile}`);

  const fileHashes = asset.fileHashes === undefined ? [] : asset.fileHashes;
  if (!Array.isArray(fileHashes)) fail(`assets.${id}.fileHashes must be an array`);
  const uniqueFileHashes = [...new Set(fileHashes.map((hash, index) => {
    validateSha256(hash, `assets.${id}.fileHashes[${index}]`);
    if (!filesByHash.has(hash)) fail(`Asset ${id} references a missing file: ${hash}`);
    return hash;
  }))];

  const dependencies = asset.dependencies === undefined ? [] : asset.dependencies;
  if (!Array.isArray(dependencies) || dependencies.some((item) => typeof item !== 'string' || !ID_PATTERN.test(item))) {
    fail(`assets.${id}.dependencies must be an array of asset ids`);
  }

  const lodData = asset.lod === undefined ? [] : asset.lod;
  if (!Array.isArray(lodData)) fail(`assets.${id}.lod must be an array`);
  const lodNames = new Set();
  const lod = lodData.map((entry, index) => {
    const item = requirePlainObject(entry, `assets.${id}.lod[${index}]`);
    const name = requireString(item.name, `assets.${id}.lod[${index}].name`);
    if (lodNames.has(name)) fail(`Duplicate LOD name for ${id}: ${name}`);
    lodNames.add(name);
    const file = validateSha256(item.file, `assets.${id}.lod[${index}].file`);
    if (!filesByHash.has(file)) fail(`Asset ${id} LOD ${name} references a missing file: ${file}`);
    const maxDistance = optionalFiniteNumber(item.maxDistance, `assets.${id}.lod[${index}].maxDistance`);
    if (maxDistance !== undefined && maxDistance <= 0) fail(`Asset ${id} LOD maxDistance must be positive`);
    return Object.freeze({ name, file, ...(maxDistance === undefined ? {} : { maxDistance }) });
  });

  const renderInput = asset.render === undefined ? {} : requirePlainObject(asset.render, `assets.${id}.render`);
  const render = Object.freeze({
    castShadow: renderInput.castShadow !== false,
    receiveShadow: renderInput.receiveShadow !== false,
    instancing: typeof renderInput.instancing === 'string' ? renderInput.instancing : 'allowed',
  });

  return Object.freeze({
    id,
    type,
    version,
    modelFile,
    fileHashes: Object.freeze(uniqueFileHashes),
    dependencies: Object.freeze([...new Set(dependencies)]),
    lod: Object.freeze(lod),
    bounds: validateBounds(asset.bounds, id),
    pivot: asset.pivot === undefined ? Object.freeze([0, 0, 0]) : Object.freeze(validateVector3(asset.pivot, `assets.${id}.pivot`)),
    collider: validateCollider(asset.collider, id),
    render,
    gameplay: isPlainObject(asset.gameplay) ? Object.freeze({ ...asset.gameplay }) : Object.freeze({}),
    source: isPlainObject(asset.source) ? Object.freeze({ ...asset.source }) : Object.freeze({}),
  });
}

function assertNoDependencyCycles(assetsById) {
  const visiting = new Set();
  const visited = new Set();

  function visit(id, trail) {
    if (visited.has(id)) return;
    if (visiting.has(id)) fail(`Asset dependency cycle: ${[...trail, id].join(' -> ')}`);
    const asset = assetsById.get(id);
    if (!asset) fail(`Missing asset dependency: ${id}`);
    visiting.add(id);
    for (const dependency of asset.dependencies) visit(dependency, [...trail, id]);
    visiting.delete(id);
    visited.add(id);
  }

  for (const id of assetsById.keys()) visit(id, []);
}

export function validateManifest(data) {
  const manifest = requirePlainObject(data, 'asset manifest');
  if (manifest.schemaVersion !== ASSET_SCHEMA_VERSION) {
    fail(`Unsupported asset manifest schemaVersion: ${manifest.schemaVersion}`);
  }
  const catalogVersion = requireString(manifest.catalogVersion, 'manifest.catalogVersion');
  if (!VERSION_PATTERN.test(catalogVersion)) fail(`Invalid catalogVersion: ${catalogVersion}`);

  const minClient = manifest.minClient === undefined
    ? {}
    : requirePlainObject(manifest.minClient, 'manifest.minClient');
  if (minClient.assetSchemaVersion !== undefined
    && minClient.assetSchemaVersion > ASSET_SCHEMA_VERSION) {
    fail(`Catalog requires asset schema ${minClient.assetSchemaVersion}, client supports ${ASSET_SCHEMA_VERSION}`);
  }

  const categories = new Set();
  if (manifest.categories !== undefined) {
    if (!Array.isArray(manifest.categories)) fail('manifest.categories must be an array');
    for (const category of manifest.categories) {
      const id = typeof category === 'string' ? category : category?.id;
      if (typeof id !== 'string' || !ID_PATTERN.test(id)) fail(`Invalid category id: ${id}`);
      categories.add(id);
    }
  }

  const filesInput = requirePlainObject(manifest.files, 'manifest.files');
  const fileEntries = Object.entries(filesInput);
  if (fileEntries.length > MAX_FILES) fail(`Manifest has too many files: ${fileEntries.length}`);
  const filesByHash = new Map(fileEntries.map(([sha, file]) => [sha, validateFileReference(sha, file)]));

  if (!Array.isArray(manifest.assets)) fail('manifest.assets must be an array');
  if (manifest.assets.length > MAX_ASSETS) fail(`Manifest has too many assets: ${manifest.assets.length}`);
  const assetsById = new Map();
  const assetsByType = new Map();
  for (const assetData of manifest.assets) {
    const asset = validateAsset(assetData, filesByHash, categories);
    if (assetsById.has(asset.id)) fail(`Duplicate asset id: ${asset.id}`);
    assetsById.set(asset.id, asset);
    if (!assetsByType.has(asset.type)) assetsByType.set(asset.type, []);
    assetsByType.get(asset.type).push(asset);
    categories.add(asset.type);
  }
  for (const asset of assetsById.values()) {
    for (const dependency of asset.dependencies) {
      if (!assetsById.has(dependency)) fail(`Asset ${asset.id} depends on missing asset: ${dependency}`);
    }
  }
  assertNoDependencyCycles(assetsById);

  for (const assets of assetsByType.values()) Object.freeze(assets);

  return Object.freeze({
    schemaVersion: ASSET_SCHEMA_VERSION,
    catalogVersion,
    generatedAt: typeof manifest.generatedAt === 'string' ? manifest.generatedAt : null,
    categories,
    filesByHash,
    assetsById,
    assetsByType,
  });
}

export function getAssetModelFile(manifest, asset, { lodName = null } = {}) {
  let hash = asset.modelFile;
  if (lodName) {
    const lod = asset.lod.find((entry) => entry.name === lodName);
    if (!lod) fail(`Asset ${asset.id} has no LOD named ${lodName}`);
    hash = lod.file;
  }
  const file = manifest.filesByHash.get(hash);
  if (!file) fail(`Asset ${asset.id} model file is missing from the catalog: ${hash}`);
  return file;
}

export function collectAssetFiles(manifest, assetId, { lodName = null } = {}) {
  const result = [];
  const seenFiles = new Set();
  const seenAssets = new Set();

  function addFile(hash) {
    if (seenFiles.has(hash)) return;
    const file = manifest.filesByHash.get(hash);
    if (!file) fail(`Catalog file is missing: ${hash}`);
    seenFiles.add(hash);
    result.push(file);
  }

  function visit(id, useRequestedLod) {
    if (seenAssets.has(id)) return;
    const asset = manifest.assetsById.get(id);
    if (!asset) fail(`Asset not found in catalog: ${id}`);
    seenAssets.add(id);
    for (const dependency of asset.dependencies) visit(dependency, false);
    addFile(getAssetModelFile(manifest, asset, { lodName: useRequestedLod ? lodName : null }).sha256);
    for (const hash of asset.fileHashes) addFile(hash);
  }

  visit(assetId, true);
  return result;
}

export async function sha256ArrayBuffer(buffer, subtle = globalThis.crypto?.subtle) {
  if (!subtle?.digest) throw new AssetManifestError('Web Crypto SHA-256 is unavailable in this runtime');
  const digest = await subtle.digest('SHA-256', buffer);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function makeTimeoutSignal(parentSignal, timeoutMs) {
  const controller = new AbortController();
  let timeout = null;
  const abort = () => controller.abort(parentSignal?.reason);
  if (parentSignal?.aborted) controller.abort(parentSignal.reason);
  else parentSignal?.addEventListener?.('abort', abort, { once: true });
  if (Number.isFinite(timeoutMs) && timeoutMs > 0) {
    timeout = setTimeout(() => controller.abort(new Error(`Timed out after ${timeoutMs} ms`)), timeoutMs);
  }
  return {
    signal: controller.signal,
    cleanup() {
      if (timeout) clearTimeout(timeout);
      parentSignal?.removeEventListener?.('abort', abort);
    },
  };
}

async function fetchLimitedBytes(fetchImpl, url, { signal, timeoutMs, maxBytes, cacheMode = 'no-store' }) {
  const timeout = makeTimeoutSignal(signal, timeoutMs);
  try {
    const response = await fetchImpl(url, {
      method: 'GET',
      cache: cacheMode,
      credentials: 'omit',
      signal: timeout.signal,
    });
    if (!response.ok) fail(`Asset catalog request failed (${response.status}): ${url}`);
    const declared = Number(response.headers?.get?.('content-length'));
    if (Number.isFinite(declared) && declared > maxBytes) {
      fail(`Asset catalog response is too large: ${declared} bytes`);
    }
    const buffer = await response.arrayBuffer();
    if (buffer.byteLength > maxBytes) fail(`Asset catalog response is too large: ${buffer.byteLength} bytes`);
    return buffer;
  } finally {
    timeout.cleanup();
  }
}

function parseJsonBuffer(buffer, label) {
  try {
    return JSON.parse(new TextDecoder().decode(buffer));
  } catch (error) {
    throw new AssetManifestError(`${label} is not valid JSON`, { cause: error });
  }
}

export async function fetchCatalog({
  baseUrl,
  currentPath = 'manifests/current.json',
  fetchImpl = globalThis.fetch?.bind(globalThis),
  signal,
  timeoutMs = 8000,
  hashArrayBuffer = sha256ArrayBuffer,
} = {}) {
  if (typeof fetchImpl !== 'function') fail('fetch is unavailable in this runtime');
  assertSafeRelativeKey(currentPath, 'current manifest path');

  const pointerUrl = buildAssetUrl(baseUrl, currentPath);
  const pointerBuffer = await fetchLimitedBytes(fetchImpl, pointerUrl, {
    signal,
    timeoutMs,
    maxBytes: MAX_POINTER_BYTES,
  });
  const pointer = validateCurrentPointer(parseJsonBuffer(pointerBuffer, 'Current manifest pointer'));

  const manifestUrl = buildAssetUrl(baseUrl, pointer.manifestPath);
  const manifestBuffer = await fetchLimitedBytes(fetchImpl, manifestUrl, {
    signal,
    timeoutMs,
    maxBytes: pointer.manifestSizeBytes,
    cacheMode: 'force-cache',
  });
  if (manifestBuffer.byteLength !== pointer.manifestSizeBytes) {
    fail(`Versioned manifest size mismatch: ${manifestBuffer.byteLength} !== ${pointer.manifestSizeBytes}`);
  }
  const actualSha = await hashArrayBuffer(manifestBuffer.slice(0));
  if (actualSha !== pointer.manifestSha256) {
    fail(`Versioned manifest SHA-256 mismatch: ${actualSha}`);
  }
  const rawManifest = parseJsonBuffer(manifestBuffer, 'Versioned asset manifest');
  const manifest = validateManifest(rawManifest);
  if (manifest.catalogVersion !== pointer.catalogVersion) {
    fail(`Catalog version mismatch: pointer ${pointer.catalogVersion}, manifest ${manifest.catalogVersion}`);
  }

  return Object.freeze({ pointer, manifest, rawManifest });
}
