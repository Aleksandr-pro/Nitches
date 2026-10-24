#!/usr/bin/env node
/*
 * Deterministic Festival Britain world manifest (Stage 3).
 *
 * Usage:
 *   node scripts/generate-world-manifest.mjs           # write manifest
 *   node scripts/generate-world-manifest.mjs --check   # fail if stale
 *
 * The manifest is data-only: world bounds, districts, surface table, the
 * road graph (nodes/edges/lengths) and the 256-chunk index with per-chunk
 * road references and approximate height ranges.  Later stages can ship it
 * via the R2 resource catalog without changing its schema.
 */
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { createFestivalBritainFoundation } from '../src/world/festivalBritain.js';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const outputPath = resolve(repoRoot, 'public/assets/world/festival-britain/manifest.json');

const foundation = createFestivalBritainFoundation();
const manifest = foundation.buildManifest({ includeHeightRanges: true });
const serialized = `${JSON.stringify(manifest, null, 2)}\n`;

if (process.argv.includes('--check')) {
  let existing = '';
  try {
    existing = await readFile(outputPath, 'utf8');
  } catch {
    console.error(`World manifest missing: ${outputPath}`);
    process.exit(1);
  }
  if (existing !== serialized) {
    console.error('World manifest is stale. Run: npm run world:manifest');
    process.exit(1);
  }
  console.log(`World manifest up to date (${manifest.chunks.length} chunks, `
    + `${(manifest.roadGraph.totalLengthM / 1000).toFixed(1)} km of roads).`);
} else {
  await mkdir(dirname(outputPath), { recursive: true });
  await writeFile(outputPath, serialized, 'utf8');
  console.log(`Wrote ${outputPath} (${(serialized.length / 1024).toFixed(0)} KiB, `
    + `${manifest.chunks.length} chunks, ${(manifest.roadGraph.totalLengthM / 1000).toFixed(1)} km of roads).`);
}
