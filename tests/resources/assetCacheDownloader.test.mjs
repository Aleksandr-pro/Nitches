import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import test from 'node:test';
import {
  MemoryAssetCache,
  selectEvictionCandidates,
} from '../../src/resources/assetCache.js';
import {
  AssetDownloader,
  sha256Blob,
} from '../../src/resources/assetDownloader.js';

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function response(bytes, { status = 200 } = {}) {
  const copy = Uint8Array.from(bytes);
  return {
    ok: status >= 200 && status < 300,
    status,
    body: null,
    headers: {
      get(name) {
        if (name.toLowerCase() === 'content-length') return String(copy.byteLength);
        if (name.toLowerCase() === 'content-type') return 'model/gltf-binary';
        return null;
      },
    },
    async arrayBuffer() {
      return copy.buffer;
    },
  };
}

test('MemoryAssetCache stages, commits, touches, and cleans stale records', async () => {
  const cache = new MemoryAssetCache();
  const blob = new Blob(['model bytes'], { type: 'model/gltf-binary' });
  const hash = sha256(Buffer.from('model bytes'));

  await cache.putStaging({
    id: 'stage-1',
    sha256: hash,
    blob,
    sizeBytes: blob.size,
    createdAt: 1000,
  });
  const committed = await cache.commitStaging('stage-1', {
    sha256: hash,
    key: 'trees/tree_oak_001/1.0.0/model.glb',
    mediaType: 'model/gltf-binary',
    sizeBytes: blob.size,
    createdAt: 1100,
    lastAccessedAt: 1100,
    catalogVersions: ['1.0.0'],
  });

  assert.equal(committed.sha256, hash);
  assert.equal(await cache.getStaging('stage-1'), null);
  assert.equal((await cache.getFile(hash)).sizeBytes, blob.size);

  await cache.touchFile(hash, { catalogVersion: '1.1.0', accessedAt: 2000 });
  const touched = await cache.getFile(hash);
  assert.equal(touched.lastAccessedAt, 2000);
  assert.deepEqual(touched.catalogVersions, ['1.0.0', '1.1.0']);

  await cache.putStaging({ id: 'old', blob, createdAt: 1000 });
  await cache.putStaging({ id: 'fresh', blob, createdAt: 9500 });
  assert.equal(await cache.cleanupStaging(1000, 10000), 1);
  assert.equal(await cache.getStaging('old'), null);
  assert.ok(await cache.getStaging('fresh'));
});

test('LRU eviction keeps protected hashes', () => {
  const records = [
    { sha256: 'a', sizeBytes: 100, createdAt: 1, lastAccessedAt: 10 },
    { sha256: 'b', sizeBytes: 100, createdAt: 2, lastAccessedAt: 20 },
    { sha256: 'c', sizeBytes: 100, createdAt: 3, lastAccessedAt: 30 },
  ];
  assert.deepEqual(
    selectEvictionCandidates(records, { softLimitBytes: 200 }),
    ['a'],
  );
  assert.deepEqual(
    selectEvictionCandidates(records, {
      softLimitBytes: 200,
      protectedHashes: new Set(['a']),
    }),
    ['b'],
  );
});

test('AssetDownloader deduplicates parallel downloads and reports progress', async () => {
  const bytes = Buffer.from('cloud model');
  const fileRef = {
    key: 'trees/tree_oak_001/1.0.0/model.glb',
    sha256: sha256(bytes),
    sizeBytes: bytes.length,
    mediaType: 'model/gltf-binary',
  };
  let fetchCalls = 0;
  const downloader = new AssetDownloader({
    fetchImpl: async () => {
      fetchCalls += 1;
      await new Promise((resolve) => setTimeout(resolve, 5));
      return response(bytes);
    },
    retries: 0,
  });
  const progress = [];

  const [first, second] = await Promise.all([
    downloader.download(fileRef, 'https://assets.example.test/model.glb', {
      onProgress: (event) => progress.push(event),
    }),
    downloader.download(fileRef, 'https://assets.example.test/model.glb'),
  ]);

  assert.equal(fetchCalls, 1);
  assert.equal(first, second);
  assert.equal(await first.text(), 'cloud model');
  assert.equal(progress.at(-1).loaded, bytes.length);
  assert.equal(progress.at(-1).total, bytes.length);
});

test('AssetDownloader retries temporary failures and rejects oversized bodies', async () => {
  const bytes = Buffer.from('retry me');
  const fileRef = {
    key: 'props/retry/model.glb',
    sha256: sha256(bytes),
    sizeBytes: bytes.length,
    mediaType: 'model/gltf-binary',
  };
  let attempts = 0;
  const downloader = new AssetDownloader({
    fetchImpl: async () => {
      attempts += 1;
      return attempts === 1 ? response(Buffer.alloc(0), { status: 503 }) : response(bytes);
    },
    retries: 1,
    sleep: async () => {},
    random: () => 0,
  });

  assert.equal(await (await downloader.download(fileRef, 'https://assets.example.test/retry.glb')).text(), 'retry me');
  assert.equal(attempts, 2);

  const oversizedDownloader = new AssetDownloader({
    fetchImpl: async () => response(Buffer.from('too large')),
    retries: 0,
  });
  await assert.rejects(
    () => oversizedDownloader.download(
      { ...fileRef, sizeBytes: 4 },
      'https://assets.example.test/oversized.glb',
    ),
    /larger than the catalog declares/,
  );
});

test('sha256Blob uses the supplied ArrayBuffer hash implementation', async () => {
  const hash = await sha256Blob(
    new Blob(['abc']),
    async (buffer) => sha256(Buffer.from(buffer)),
  );
  assert.equal(hash, 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
});
