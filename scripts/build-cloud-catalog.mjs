#!/usr/bin/env node
/**
 * Build the exact local directory tree that will later be uploaded to the
 * public Cloudflare R2 runtime bucket. This script does not upload anything
 * and never needs R2 credentials.
 */
import { createHash } from 'node:crypto';
import { mkdir, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import {
  ASSET_SCHEMA_VERSION,
  validateCurrentPointer,
  validateManifest,
} from '../src/resources/assetManifest.js';
import {
  CLOUD_OAK_ASSET_ID,
  CLOUD_OAK_VERSION,
  buildCloudOakAsset,
} from './generate-cloud-prototype-tree.mjs';

export const CLOUD_CATALOG_DEFAULT_OUTPUT = '.cloud-assets/staging';
export const CLOUD_CATALOG_DEFAULT_VERSION = '1.0.0';
export const CLOUD_CATALOG_DEFAULT_GENERATED_AT = '2026-10-24T00:00:00.000Z';
export const CLOUD_ASSET_CATEGORIES = Object.freeze([
  'vehicles',
  'buildings',
  'trees',
  'vegetation',
  'roads',
  'infrastructure',
  'props',
  'terrain',
  'effects',
]);

const VERSION_PATTERN = /^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/;
const IMMUTABLE_CACHE_CONTROL = 'public, max-age=31536000, immutable';
const POINTER_CACHE_CONTROL = 'public, max-age=30, s-maxage=30, stale-while-revalidate=60';

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function stableJsonBytes(value) {
  return Buffer.from(`${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

function displayPath(absolutePath) {
  const relative = path.relative(process.cwd(), absolutePath);
  return relative && !relative.startsWith(`..${path.sep}`) ? relative : absolutePath;
}

function assertSafeCleanDir(outputDir) {
  const resolved = path.resolve(outputDir);
  const parsed = path.parse(resolved);
  const segments = resolved.split(path.sep).filter(Boolean);
  if (
    resolved === parsed.root
    || resolved === process.cwd()
    || resolved === path.dirname(process.cwd())
    || segments.length < 2
  ) {
    throw new Error(`Refusing to clean an unsafe output directory: ${resolved}`);
  }
  return resolved;
}

function resolveKey(outputDir, key) {
  const destination = path.resolve(outputDir, ...key.split('/'));
  const relative = path.relative(outputDir, destination);
  if (relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) {
    throw new Error(`Catalog key escapes the staging directory: ${key}`);
  }
  return destination;
}

async function writeKey(outputDir, key, bytes) {
  const destination = resolveKey(outputDir, key);
  await mkdir(path.dirname(destination), { recursive: true });
  await writeFile(destination, bytes);
  return destination;
}

export async function buildCloudCatalog({
  outputDir = CLOUD_CATALOG_DEFAULT_OUTPUT,
  catalogVersion = CLOUD_CATALOG_DEFAULT_VERSION,
  generatedAt = CLOUD_CATALOG_DEFAULT_GENERATED_AT,
  clean = false,
  reportPath = null,
  oakAsset = buildCloudOakAsset(),
} = {}) {
  if (!VERSION_PATTERN.test(catalogVersion)) {
    throw new Error(`Invalid catalog version: ${catalogVersion}`);
  }
  if (!Number.isFinite(Date.parse(generatedAt))) {
    throw new Error(`Invalid generatedAt timestamp: ${generatedAt}`);
  }

  const resolvedOutputDir = clean
    ? assertSafeCleanDir(outputDir)
    : path.resolve(outputDir);
  if (clean) await rm(resolvedOutputDir, { recursive: true, force: true });
  await mkdir(resolvedOutputDir, { recursive: true });

  const modelKey = `trees/${CLOUD_OAK_ASSET_ID}/${CLOUD_OAK_VERSION}/model-${oakAsset.sha256}.glb`;
  const rawManifest = {
    schemaVersion: ASSET_SCHEMA_VERSION,
    catalogVersion,
    generatedAt,
    minClient: { assetSchemaVersion: ASSET_SCHEMA_VERSION },
    categories: CLOUD_ASSET_CATEGORIES.map((id) => ({ id })),
    files: {
      [oakAsset.sha256]: {
        key: modelKey,
        sizeBytes: oakAsset.sizeBytes,
        sha256: oakAsset.sha256,
        mediaType: 'model/gltf-binary',
        role: 'model',
      },
    },
    assets: [
      {
        id: CLOUD_OAK_ASSET_ID,
        type: 'trees',
        version: CLOUD_OAK_VERSION,
        modelFile: oakAsset.sha256,
        dependencies: [],
        lod: [
          {
            name: 'lod0',
            maxDistance: 120,
            file: oakAsset.sha256,
          },
        ],
        bounds: oakAsset.bounds,
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
        gameplay: {
          prototype: true,
          triangleCount: oakAsset.triangleCount,
          vertexCount: oakAsset.vertexCount,
        },
        source: {
          name: 'Generated in-project prototype oak',
          generator: 'scripts/generate-cloud-prototype-tree.mjs',
          license: 'Project-generated',
        },
      },
    ],
  };

  // Use the exact same validator as the browser/Android client.
  validateManifest(rawManifest);

  const manifestBytes = stableJsonBytes(rawManifest);
  const manifestSha256 = sha256(manifestBytes);
  const manifestKey = `manifests/versions/${catalogVersion}-${manifestSha256}/manifest.json`;
  const rawPointer = {
    schemaVersion: ASSET_SCHEMA_VERSION,
    catalogVersion,
    manifestPath: manifestKey,
    manifestSizeBytes: manifestBytes.length,
    manifestSha256,
    publishedAt: generatedAt,
  };
  validateCurrentPointer(rawPointer);
  const pointerBytes = stableJsonBytes(rawPointer);
  const pointerSha256 = sha256(pointerBytes);
  const pointerKey = 'manifests/current.json';

  const modelPath = await writeKey(resolvedOutputDir, modelKey, oakAsset.bytes);
  const manifestPath = await writeKey(resolvedOutputDir, manifestKey, manifestBytes);
  const pointerPath = await writeKey(resolvedOutputDir, pointerKey, pointerBytes);

  const report = {
    catalogVersion,
    generatedAt,
    outputDir: displayPath(resolvedOutputDir),
    asset: {
      id: CLOUD_OAK_ASSET_ID,
      type: 'trees',
      version: CLOUD_OAK_VERSION,
      sha256: oakAsset.sha256,
      sizeBytes: oakAsset.sizeBytes,
      bounds: oakAsset.bounds,
      vertexCount: oakAsset.vertexCount,
      triangleCount: oakAsset.triangleCount,
    },
    objects: [
      {
        uploadOrder: 1,
        key: modelKey,
        localPath: displayPath(modelPath),
        sizeBytes: oakAsset.sizeBytes,
        sha256: oakAsset.sha256,
        contentType: 'model/gltf-binary',
        cacheControl: IMMUTABLE_CACHE_CONTROL,
      },
      {
        uploadOrder: 2,
        key: manifestKey,
        localPath: displayPath(manifestPath),
        sizeBytes: manifestBytes.length,
        sha256: manifestSha256,
        contentType: 'application/json',
        cacheControl: IMMUTABLE_CACHE_CONTROL,
      },
      {
        uploadOrder: 3,
        key: pointerKey,
        localPath: displayPath(pointerPath),
        sizeBytes: pointerBytes.length,
        sha256: pointerSha256,
        contentType: 'application/json',
        cacheControl: POINTER_CACHE_CONTROL,
      },
    ],
  };

  if (reportPath) {
    const resolvedReportPath = path.resolve(reportPath);
    await mkdir(path.dirname(resolvedReportPath), { recursive: true });
    await writeFile(resolvedReportPath, stableJsonBytes(report));
    report.reportPath = displayPath(resolvedReportPath);
  }

  return report;
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
    if (arg === '--out') options.outputDir = next();
    else if (arg === '--catalog-version') options.catalogVersion = next();
    else if (arg === '--generated-at') options.generatedAt = next();
    else if (arg === '--report') options.reportPath = next();
    else if (arg === '--clean') options.clean = true;
    else throw new Error(`Unknown argument: ${arg}`);
  }
  return options;
}

async function main() {
  const report = await buildCloudCatalog(parseArgs(process.argv.slice(2)));
  console.log(JSON.stringify(report, null, 2));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
