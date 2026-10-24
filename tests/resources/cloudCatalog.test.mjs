import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { buildCloudCatalog } from '../../scripts/build-cloud-catalog.mjs';
import { buildCloudOakAsset } from '../../scripts/generate-cloud-prototype-tree.mjs';
import { validateCloudCatalogBundle } from '../../scripts/validate-cloud-catalog.mjs';
import { assertSelfContainedGlb } from '../../src/resources/gltfAssetFactory.js';

function makeJsonOnlyGlb(json) {
  let jsonChunk = Buffer.from(JSON.stringify(json), 'utf8');
  const padding = (4 - (jsonChunk.length % 4)) % 4;
  if (padding) jsonChunk = Buffer.concat([jsonChunk, Buffer.alloc(padding, 0x20)]);

  const header = Buffer.alloc(12);
  header.writeUInt32LE(0x46546c67, 0);
  header.writeUInt32LE(2, 4);
  header.writeUInt32LE(20 + jsonChunk.length, 8);

  const jsonHeader = Buffer.alloc(8);
  jsonHeader.writeUInt32LE(jsonChunk.length, 0);
  jsonHeader.writeUInt32LE(0x4e4f534a, 4);
  return Buffer.concat([header, jsonHeader, jsonChunk]);
}

test('generated oak is deterministic and self-contained', () => {
  const first = buildCloudOakAsset();
  const second = buildCloudOakAsset();

  assert.equal(first.sha256, second.sha256);
  assert.equal(first.bytes.equals(second.bytes), true);
  assert.equal(first.triangleCount, 1464);
  assert.doesNotThrow(() => assertSelfContainedGlb(first.bytes));

  const external = makeJsonOnlyGlb({
    asset: { version: '2.0' },
    buffers: [{ uri: 'external.bin', byteLength: 0 }],
  });
  assert.throws(() => assertSelfContainedGlb(external), /external resources/);
});

test('cloud catalog staging bundle is reproducible and validates end to end', async (t) => {
  const tempDir = await mkdtemp(path.join(os.tmpdir(), 'nitches-cloud-'));
  t.after(() => rm(tempDir, { recursive: true, force: true }));

  const oak = buildCloudOakAsset();
  const firstBundle = path.join(tempDir, 'bundle-1');
  const secondBundle = path.join(tempDir, 'bundle-2');
  const firstReport = await buildCloudCatalog({
    outputDir: firstBundle,
    clean: true,
    reportPath: path.join(tempDir, 'publishing.json'),
    oakAsset: oak,
  });
  const secondReport = await buildCloudCatalog({
    outputDir: secondBundle,
    clean: true,
    oakAsset: oak,
  });

  assert.deepEqual(firstReport.objects.map((object) => object.uploadOrder), [1, 2, 3]);
  assert.deepEqual(
    firstReport.objects.map((object) => [object.key, object.sha256, object.sizeBytes]),
    secondReport.objects.map((object) => [object.key, object.sha256, object.sizeBytes]),
  );
  assert.equal(firstReport.objects[0].contentType, 'model/gltf-binary');
  assert.match(firstReport.objects[2].cacheControl, /max-age=30/);

  const validation = await validateCloudCatalogBundle({ bundleDir: firstBundle });
  assert.equal(validation.valid, true);
  assert.equal(validation.catalogVersion, '1.0.0');
  assert.deepEqual(validation.checkedAssets, ['tree_oak_001']);
  assert.equal(validation.checkedFiles.length, 1);
  assert.equal(validation.checkedFiles[0].glb.triangleCount, oak.triangleCount);
  assert.deepEqual(validation.checkedFiles[0].glb.bounds, oak.bounds);
});
