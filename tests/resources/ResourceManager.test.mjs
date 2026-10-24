import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import test from 'node:test';
import * as THREE from 'three';
import { MemoryAssetCache } from '../../src/resources/assetCache.js';
import { ResourceManager } from '../../src/resources/ResourceManager.js';
import { buildCloudOakAsset } from '../../scripts/generate-cloud-prototype-tree.mjs';

const BASE_URL = 'https://assets.example.test/root';
const oak = buildCloudOakAsset();
const modelKey = `trees/tree_oak_001/1.0.0/model-${oak.sha256}.glb`;

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

async function hashArrayBuffer(buffer) {
  return sha256(Buffer.from(buffer));
}

function response(bytes) {
  const copy = Uint8Array.from(bytes);
  return {
    ok: true,
    status: 200,
    body: null,
    headers: {
      get(name) {
        if (name.toLowerCase() === 'content-length') return String(copy.byteLength);
        if (name.toLowerCase() === 'content-type') return 'application/octet-stream';
        return null;
      },
    },
    async arrayBuffer() {
      return copy.buffer;
    },
  };
}

function buildCatalog() {
  const rawManifest = {
    schemaVersion: 1,
    catalogVersion: '1.0.0',
    generatedAt: '2026-10-24T00:00:00.000Z',
    minClient: { assetSchemaVersion: 1 },
    categories: [{ id: 'trees' }],
    files: {
      [oak.sha256]: {
        key: modelKey,
        sizeBytes: oak.sizeBytes,
        sha256: oak.sha256,
        mediaType: 'model/gltf-binary',
        role: 'model',
      },
    },
    assets: [
      {
        id: 'tree_oak_001',
        type: 'trees',
        version: '1.0.0',
        modelFile: oak.sha256,
        bounds: oak.bounds,
        pivot: [0, 0, 0],
        collider: {
          kind: 'cylinder',
          center: [0.09, 1.65, 0.04],
          radius: 0.45,
          height: 3.3,
        },
        render: {
          castShadow: true,
          receiveShadow: true,
          instancing: 'allowed',
        },
      },
    ],
  };
  const manifestBytes = Buffer.from(JSON.stringify(rawManifest));
  const manifestSha256 = sha256(manifestBytes);
  const manifestPath = `manifests/versions/1.0.0-${manifestSha256}/manifest.json`;
  const pointerBytes = Buffer.from(JSON.stringify({
    schemaVersion: 1,
    catalogVersion: '1.0.0',
    manifestPath,
    manifestSizeBytes: manifestBytes.length,
    manifestSha256,
    publishedAt: rawManifest.generatedAt,
  }));
  return { manifestBytes, manifestPath, pointerBytes };
}

function createFetch({ offlineCatalog = false } = {}) {
  const catalog = buildCatalog();
  const counts = { pointer: 0, manifest: 0, model: 0 };
  const fetchImpl = async (url) => {
    const value = String(url);
    if (value.endsWith('/manifests/current.json')) {
      counts.pointer += 1;
      if (offlineCatalog) throw new TypeError('offline');
      return response(catalog.pointerBytes);
    }
    if (value.endsWith(`/${catalog.manifestPath}`)) {
      counts.manifest += 1;
      return response(catalog.manifestBytes);
    }
    if (value.endsWith(`/${modelKey}`)) {
      counts.model += 1;
      return response(oak.bytes);
    }
    throw new Error(`Unexpected URL: ${value}`);
  };
  return { counts, fetchImpl };
}

function createManager({ cache, fetchImpl }) {
  const calls = { parse: 0, dispose: 0 };
  let tick = 1000;
  const manager = new ResourceManager({
    baseUrl: BASE_URL,
    configOverrides: {
      downloadRetries: 0,
      parsedTemplateLimit: 2,
    },
    cache,
    fetchImpl,
    hashArrayBuffer,
    parseGltf: async () => {
      calls.parse += 1;
      const scene = new THREE.Group();
      scene.name = `oak-template-${calls.parse}`;
      scene.add(new THREE.Mesh(
        new THREE.BoxGeometry(1, 1, 1),
        new THREE.MeshStandardMaterial(),
      ));
      return { scene };
    },
    instantiateGltf: (gltf) => gltf.scene.clone(true),
    disposeGltf: () => {
      calls.dispose += 1;
    },
    logger: {
      warn() {},
      info() {},
      error() {},
    },
    storageManager: null,
    now: () => {
      tick += 1;
      return tick;
    },
  });
  return { calls, manager };
}

test('ResourceManager downloads once and reuses the verified Blob in a later session', async () => {
  const cache = new MemoryAssetCache();
  const firstFetch = createFetch();
  const first = createManager({ cache, fetchImpl: firstFetch.fetchImpl });

  const firstHandle = await first.manager.loadGltf('tree_oak_001');
  assert.equal(firstHandle.asset.id, 'tree_oak_001');
  assert.equal(firstFetch.counts.model, 1);
  assert.equal(first.manager.getStats().downloads, 1);
  assert.equal(first.manager.getStats().cacheMisses, 1);

  const instance = firstHandle.instantiate();
  assert.notEqual(instance, firstHandle.scene);
  assert.equal(first.manager.getStats().instantiations, 1);
  firstHandle.release();

  const secondFetch = createFetch();
  const second = createManager({ cache, fetchImpl: secondFetch.fetchImpl });
  const secondHandle = await second.manager.loadGltf('tree_oak_001');
  assert.equal(secondFetch.counts.pointer, 1);
  assert.equal(secondFetch.counts.manifest, 1);
  assert.equal(secondFetch.counts.model, 0);
  assert.equal(second.manager.getStats().downloads, 0);
  assert.equal(second.manager.getStats().cacheHits, 1);
  assert.equal(second.calls.parse, 1);
  secondHandle.release();
});

test('ResourceManager detects a corrupted cached Blob and downloads it again', async () => {
  const cache = new MemoryAssetCache();
  const firstFetch = createFetch();
  const first = createManager({ cache, fetchImpl: firstFetch.fetchImpl });
  const firstHandle = await first.manager.loadGltf('tree_oak_001');
  firstHandle.release();

  const record = await cache.getFile(oak.sha256);
  const corrupted = new Uint8Array(await record.blob.arrayBuffer());
  corrupted[corrupted.length - 1] ^= 0xff;
  await cache.putFile({
    ...record,
    blob: new Blob([corrupted], { type: 'model/gltf-binary' }),
    sizeBytes: corrupted.byteLength,
  });

  const secondFetch = createFetch();
  const second = createManager({ cache, fetchImpl: secondFetch.fetchImpl });
  const secondHandle = await second.manager.loadGltf('tree_oak_001');
  assert.equal(secondFetch.counts.model, 1);
  assert.equal(second.manager.getStats().integrityFailures, 1);
  assert.equal(second.manager.getStats().downloads, 1);
  secondHandle.release();
});

test('ResourceManager falls back to the last known catalog and cached model offline', async () => {
  const cache = new MemoryAssetCache();
  const onlineFetch = createFetch();
  const online = createManager({ cache, fetchImpl: onlineFetch.fetchImpl });
  const onlineHandle = await online.manager.loadGltf('tree_oak_001');
  onlineHandle.release();

  const offlineFetch = createFetch({ offlineCatalog: true });
  const offline = createManager({ cache, fetchImpl: offlineFetch.fetchImpl });
  const offlineHandle = await offline.manager.loadGltf('tree_oak_001');

  assert.equal(offline.manager.getStatus().catalogSource, 'cache');
  assert.equal(offline.manager.getStats().catalogSource, 'cache');
  assert.equal(offlineFetch.counts.pointer, 1);
  assert.equal(offlineFetch.counts.model, 0);
  assert.equal(offline.manager.getStats().cacheHits, 1);
  offlineHandle.release();
});

test('disabled ResourceManager reports status without requiring a catalog', async () => {
  const manager = new ResourceManager({
    baseUrl: '',
    cache: new MemoryAssetCache(),
    logger: {
      warn() {},
      info() {},
      error() {},
    },
    storageManager: null,
  });

  const status = await manager.init();
  assert.equal(status.enabled, false);
  assert.equal(status.ready, false);
  await assert.rejects(
    () => manager.loadGltf('tree_oak_001'),
    /catalog is unavailable/i,
  );
});
