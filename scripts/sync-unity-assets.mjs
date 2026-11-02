#!/usr/bin/env node
/**
 * Copy runtime car models + recorded audio banks into the Unity
 * project's StreamingAssets, from the shared repo asset tree.
 *
 * Committed in git (plain, no LFS - see unity/.gitattributes):
 *   - Cars/bugatti_chiron_super_sport.glb
 *   - Audio/bugatti_chiron/** (anchors + idle + start/stop)
 * Everything else is copied too but git-ignored
 * (unity/Assets/StreamingAssets/.gitignore) to keep the repo lean;
 * CI runs this script before building.
 *
 * The Mustang lives in Git LFS (public/assets/models/cars/mustang);
 * if it is still a pointer file we warn and skip it - run
 * `git lfs pull` first to include it.
 */
import { cp, mkdir, stat, readFile } from 'node:fs/promises';
import path from 'node:path';

const ROOT = process.cwd();
const DEST_CARS = path.join(ROOT, 'unity/Assets/StreamingAssets/Cars');
const DEST_AUDIO = path.join(ROOT, 'unity/Assets/StreamingAssets/Audio');

const LFS_POINTER_PREFIX = 'version https://git-lfs.github.com/spec/v1';

async function isLfsPointer(file) {
  try {
    const head = (await readFile(file)).subarray(0, 64).toString('utf8');
    return head.startsWith(LFS_POINTER_PREFIX);
  } catch {
    return false;
  }
}

async function copyFile(srcRel, destDir, destName) {
  const src = path.join(ROOT, srcRel);
  try {
    await stat(src);
  } catch {
    console.warn(`[skip] missing: ${srcRel}`);
    return false;
  }
  if (await isLfsPointer(src)) {
    console.warn(`[skip] LFS pointer not materialized: ${srcRel} (run: git lfs pull)`);
    return false;
  }
  await mkdir(destDir, { recursive: true });
  await cp(src, path.join(destDir, destName ?? path.basename(srcRel)));
  console.log(`[ok] ${srcRel} -> ${path.relative(ROOT, path.join(destDir, destName ?? path.basename(srcRel)))}`);
  return true;
}

async function copyBank(bank) {
  const srcDir = path.join(ROOT, 'src/assets/audio', bank);
  const destDir = path.join(DEST_AUDIO, bank);
  try {
    await stat(srcDir);
  } catch {
    console.warn(`[skip] missing bank: ${bank}`);
    return;
  }
  await mkdir(destDir, { recursive: true });
  // Anchors + idle + start/stop only; pops/manifests stay in src.
  const { readdir } = await import('node:fs/promises');
  for (const name of await readdir(srcDir)) {
    if (!name.endsWith('.wav')) continue;
    if (name.startsWith('pop_')) continue;
    await cp(path.join(srcDir, name), path.join(destDir, name));
  }
  console.log(`[ok] audio bank: ${bank}`);
}

const cars = [
  'src/assets/models/cars/bugatti_chiron_super_sport.glb',
  'src/assets/models/cars/audi_r8_v10_plus.glb',
  'src/assets/models/cars/chevrolet_camaro_ss.glb',
  'src/assets/models/cars/mercedes_benz_560_sel.glb',
  'public/assets/models/cars/mustang/mustang.glb',
];

for (const car of cars) await copyFile(car, DEST_CARS);
for (const bank of ['bugatti_chiron', 'shelby', 'audi_r8', 'camaro_ss', 'mercedes_560_sel']) await copyBank(bank);

console.log('Unity StreamingAssets sync complete.');
