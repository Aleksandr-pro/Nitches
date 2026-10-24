import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import test from 'node:test';
import { getAssetConfig, normalizeAssetBaseUrl } from '../../src/resources/assetConfig.js';
import {
  buildAssetUrl,
  collectAssetFiles,
  fetchCatalog,
  getAssetModelFile,
  validateManifest,
} from '../../src/resources/assetManifest.js';

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function response(bytes) {
  const copy = Uint8Array.from(bytes);
  return {
    ok: true,
    status: 200,
    headers: {
      get(name) {
        return name.toLowerCase() === 'content-length' ? String(copy.byteLength) : null;
      },
    },
    async arrayBuffer() {
      return copy.buffer;
    },
  };
}

function buildRawCatalog() {
  const contents = {
    dependency: Buffer.from('dependency model'),
    tree: Buffer.from('tree model'),
    leaves: Buffer.from('shared leaves'),
    treeFar: Buffer.from('tree far model'),
  };
  const hashes = Object.fromEntries(
    Object.entries(contents).map(([name, bytes]) => [name, sha256(bytes)]),
  );
  const files = {
    [hashes.dependency]: {
      key: 'props/shared_base/1.0.0/model.glb',
      sizeBytes: contents.dependency.length,
      sha256: hashes.dependency,
      mediaType: 'model/gltf-binary',
      role: 'model',
    },
    [hashes.tree]: {
      key: 'trees/tree_oak_001/1.0.0/model.glb',
      sizeBytes: contents.tree.length,
      sha256: hashes.tree,
      mediaType: 'model/gltf-binary',
      role: 'model',
    },
    [hashes.leaves]: {
      key: 'shared/textures/leaves.webp',
      sizeBytes: contents.leaves.length,
      sha256: hashes.leaves,
      mediaType: 'image/webp',
      role: 'texture',
    },
    [hashes.treeFar]: {
      key: 'trees/tree_oak_001/1.0.0/model-far.glb',
      sizeBytes: contents.treeFar.length,
      sha256: hashes.treeFar,
      mediaType: 'model/gltf-binary',
      role: 'model',
    },
  };

  return {
    contents,
    hashes,
    raw: {
      schemaVersion: 1,
      catalogVersion: '1.2.3',
      generatedAt: '2026-10-24T00:00:00.000Z',
      minClient: { assetSchemaVersion: 1 },
      categories: [{ id: 'trees' }, { id: 'props' }],
      files,
      assets: [
        {
          id: 'shared_base_001',
          type: 'props',
          version: '1.0.0',
          modelFile: hashes.dependency,
        },
        {
          id: 'tree_oak_001',
          type: 'trees',
          version: '1.0.0',
          modelFile: hashes.tree,
          fileHashes: [hashes.leaves],
          dependencies: ['shared_base_001'],
          lod: [{ name: 'far', file: hashes.treeFar, maxDistance: 120 }],
        },
      ],
    },
  };
}

test('asset base URL accepts HTTPS/local HTTP and rejects unsafe forms', () => {
  assert.equal(normalizeAssetBaseUrl('https://assets.example.test/root///'), 'https://assets.example.test/root');
  assert.equal(normalizeAssetBaseUrl('http://localhost:8787/assets'), 'http://localhost:8787/assets');
  assert.equal(normalizeAssetBaseUrl('http://assets.example.test'), null);
  assert.equal(normalizeAssetBaseUrl('https://assets.example.test/?token=secret'), null);
  assert.equal(normalizeAssetBaseUrl('https://user:pass@assets.example.test'), null);
  assert.equal(normalizeAssetBaseUrl('not a URL'), null);

  const config = getAssetConfig({ baseUrl: 'https://assets.example.test/root/' });
  assert.equal(config.enabled, true);
  assert.equal(config.baseUrl, 'https://assets.example.test/root');
});

test('manifest validation indexes assets and rejects unsafe keys', () => {
  const { raw } = buildRawCatalog();
  const manifest = validateManifest(raw);
  assert.equal(manifest.catalogVersion, '1.2.3');
  assert.equal(manifest.assetsByType.get('trees')[0].id, 'tree_oak_001');
  assert.equal(buildAssetUrl('https://cdn.example.test/root', 'trees/oak 1/model.glb'), 'https://cdn.example.test/root/trees/oak%201/model.glb');
  assert.throws(() => buildAssetUrl('https://cdn.example.test', '../secret.glb'), /unsafe path segment/);

  const unsafe = structuredClone(raw);
  const firstHash = Object.keys(unsafe.files)[0];
  unsafe.files[firstHash].key = '../escape.glb';
  assert.throws(() => validateManifest(unsafe), /unsafe path segment/);
});

test('dependency and LOD resolution collect each required file once in dependency order', () => {
  const { raw, hashes } = buildRawCatalog();
  const manifest = validateManifest(raw);
  const asset = manifest.assetsById.get('tree_oak_001');

  assert.equal(getAssetModelFile(manifest, asset).sha256, hashes.tree);
  assert.equal(getAssetModelFile(manifest, asset, { lodName: 'far' }).sha256, hashes.treeFar);
  assert.deepEqual(
    collectAssetFiles(manifest, 'tree_oak_001', { lodName: 'far' }).map((file) => file.sha256),
    [hashes.dependency, hashes.treeFar, hashes.leaves],
  );
});

test('fetchCatalog verifies the pointer, manifest size, hash, and schema', async () => {
  const { raw } = buildRawCatalog();
  const manifestBytes = Buffer.from(JSON.stringify(raw));
  const manifestSha256 = sha256(manifestBytes);
  const manifestPath = `manifests/versions/1.2.3-${manifestSha256}/manifest.json`;
  const pointerBytes = Buffer.from(JSON.stringify({
    schemaVersion: 1,
    catalogVersion: '1.2.3',
    manifestPath,
    manifestSizeBytes: manifestBytes.length,
    manifestSha256,
    publishedAt: raw.generatedAt,
  }));

  const fetched = await fetchCatalog({
    baseUrl: 'https://assets.example.test/root',
    fetchImpl: async (url) => {
      if (url.endsWith('/manifests/current.json')) return response(pointerBytes);
      if (url.endsWith(`/${manifestPath}`)) return response(manifestBytes);
      throw new Error(`Unexpected URL: ${url}`);
    },
    hashArrayBuffer: async (buffer) => sha256(Buffer.from(buffer)),
  });

  assert.equal(fetched.pointer.manifestPath, manifestPath);
  assert.equal(fetched.manifest.catalogVersion, '1.2.3');
  assert.equal(fetched.rawManifest.assets.length, 2);
});
