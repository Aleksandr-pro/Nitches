#!/usr/bin/env node
/**
 * Copies the runtime assets needed by the Godot project into native/assets.
 *
 * The copied files are generated build inputs, are ignored by Git, and keep
 * the existing canonical asset locations as the single source of truth.  In
 * CI, Git LFS must materialise the Mustang before this script is run.
 */
import { copyFile, mkdir, readFile, rm, stat } from 'node:fs/promises';
import path from 'node:path';

const allowMissingMustang = process.argv.includes('--allow-missing-mustang');
const destinationRoot = 'native/assets';

const modelCopies = [
  ['public/assets/models/cars/mustang/mustang.glb', 'vehicles/mustang.glb', 'mustang'],
  ['src/assets/models/props/villa.glb', 'buildings/villa.glb'],
  ['src/assets/models/props/glass_tower.glb', 'buildings/glass_tower.glb'],
  ['src/assets/models/props/main_tower.glb', 'buildings/main_tower.glb'],
  ['src/assets/models/props/hero_building.glb', 'buildings/hero_building.glb'],
  ['src/assets/models/props/townhouse.glb', 'buildings/townhouse.glb'],
  ['src/assets/models/props/opera_house.glb', 'buildings/opera_house.glb'],
  ['src/assets/models/props/mosque.glb', 'buildings/mosque.glb'],
  ['src/assets/models/props/grand_hotel.glb', 'buildings/grand_hotel.glb'],
  ['src/assets/models/props/museum.glb', 'buildings/museum.glb'],
  ['src/assets/models/props/street_lamp.glb', 'props/street_lamp.glb'],
  ['src/assets/models/props/bus_shelter.glb', 'props/bus_shelter.glb'],
  ['src/assets/models/props/park_bench.glb', 'props/park_bench.glb'],
  ['src/assets/models/props/park_pergola.glb', 'props/park_pergola.glb'],
  ['src/assets/models/props/traffic_signal_short.glb', 'props/traffic_signal_short.glb'],
  ['src/assets/models/props/traffic_signal_long.glb', 'props/traffic_signal_long.glb'],
  ['src/assets/models/props/dubai_premium_cafe.glb', 'props/dubai_premium_cafe.glb'],
  ['src/assets/models/plants.glb', 'vegetation/plants.glb'],
  ['src/assets/models/props/palm_date.glb', 'vegetation/palm_date.glb'],
  ['src/assets/models/props/palm_royal.glb', 'vegetation/palm_royal.glb'],
  ['src/assets/models/props/grass_tuft.glb', 'vegetation/grass_tuft.glb'],
  ['src/assets/models/props/flower_clump.glb', 'vegetation/flower_clump.glb'],
  ['src/assets/models/props/ornamental_shrub.glb', 'vegetation/ornamental_shrub.glb'],
];

// 0.2.36 menu cards are cropped from real 0.2.35 in-game CI frames;
// the retired photoreal menu renders are deliberately no longer staged.
const uiCopies = [
  ['src/assets/ui/menu_play_gameplay.jpg', 'ui/menu_play_gameplay.jpg'],
  ['src/assets/ui/menu_shelby_gameplay.jpg', 'ui/menu_shelby_gameplay.jpg'],
  ['src/assets/ui/menu_richtown_gameplay.jpg', 'ui/menu_richtown_gameplay.jpg'],
  ['src/assets/ui/menu_world_gameplay.jpg', 'ui/menu_world_gameplay.jpg'],
  ['src/assets/audio/ui_click.wav', 'audio/ui_click.wav'],
];

// 0.2.35 recorded Shelby/Mustang bank.  The phase-aligned GT500 loops
// are staged in both load layers; the long Mustang idle, starter,
// shutdown and tyre recordings complete the vehicle-audio set.
const shelbyAudioRpms = [900, 1100, 1300, 1500, 1700, 1900, 2100, 2350, 2600, 2850, 3100, 3350, 3600, 3850, 4100, 4400];
const shelbyAudioNames = [
  ...shelbyAudioRpms.flatMap((rpm) => [
    `gt500_on_${String(rpm).padStart(4, '0')}.wav`,
    `gt500_off_${String(rpm).padStart(4, '0')}.wav`,
  ]),
  'mustang_idle.wav',
  'mustang_start.wav',
  'mustang_stop.wav',
  'tire_squeal_loop.wav',
];
const audioCopies = shelbyAudioNames.map((name) => [
  `src/assets/audio/shelby/${name}`,
  `audio/shelby/${name}`,
]);

const textureNames = [
  'user_grass.jpg', 'user_grass_normal.jpg',
  'user_sand_rippled.jpg', 'user_sand_rippled_normal.jpg', 'user_sand_beach_white.jpg',
  'user_concrete_slabs.jpg', 'user_concrete_slabs_normal.jpg',
  'rock.jpg', 'rock_normal.jpg',
  'user_asphalt_dashed.jpg', 'user_asphalt_dashed_normal.jpg',
  'user_asphalt_plain.jpg', 'user_asphalt_plain_normal.jpg',
  'asphalt_city.jpg',
  'user_asphalt_pothole.jpg', 'user_asphalt_pothole_normal.jpg',
  'sidewalk.jpg',
  'user_water_turquoise.jpg', 'user_water_turquoise_normal.jpg',
  'user_pool_mosaic.jpg', 'user_pool_mosaic_normal.jpg',
  'user_facade_blue_glass.jpg', 'user_facade_blue_glass_normal.jpg',
  'user_facade_gold_grid.jpg', 'user_facade_gold_grid_normal.jpg',
  'facade_hotel.jpg', 'facade_hotel_normal.jpg',
  'facade_sandstone.jpg', 'facade_sandstone_normal.jpg',
  'user_marble_tiles.jpg', 'user_marble_tiles_normal.jpg',
  'user_travertine.jpg', 'user_travertine_normal.jpg',
  'user_stone_tiles_beige.jpg',
  'user_black_granite.jpg', 'user_black_granite_normal.jpg',
  'user_mulch_soil.jpg', 'hedge.jpg',
  'user_plaster_white.jpg', 'user_plaster_white_normal.jpg',
  'user_wood_slats_dark.jpg', 'user_wood_slats_dark_normal.jpg',
  'facade_modern.jpg', 'facade_modern_normal.jpg',
  'facade_brick.jpg', 'facade_brick_normal.jpg',
  'roof_flat.jpg', 'roof_tiles.jpg', 'user_roof_terracotta.jpg',
  'user_roof_terracotta_normal.jpg', 'roof_slate.jpg', 'roof_slate_normal.jpg',
  'user_brushed_metal.jpg', 'user_brushed_metal_normal.jpg',
  'user_black_rough.jpg', 'user_black_rough_normal.jpg',
  'user_wood_deck.jpg', 'user_wood_deck_normal.jpg',
  'oak_bark.jpg', 'oak_bark_normal.jpg',
  'foliage.jpg', 'foliage_normal.jpg',
  'user_palm_leaf.png',
  'user_sky_day.jpg', 'user_sky_sunset.jpg', 'user_sky_night.jpg',
  'cafe_linen.jpg', 'cafe_linen_normal.png',
];

async function readHeader(file, length = 64) {
  const data = await readFile(file);
  return data.subarray(0, Math.min(length, data.length));
}

async function assertRealGlb(file, optionalRole = '') {
  let info;
  try {
    info = await stat(file);
  } catch {
    if (optionalRole === 'mustang' && allowMissingMustang) return false;
    throw new Error(`Required native model is missing: ${file}`);
  }
  const header = await readHeader(file, 32);
  const signature = header.subarray(0, 4).toString('utf8');
  if (signature !== 'glTF') {
    if (optionalRole === 'mustang' && allowMissingMustang) {
      console.warn(`Skipping ${file}: local checkout contains an LFS pointer (${info.size} bytes).`);
      return false;
    }
    throw new Error(`${file} is not a real GLB (signature: ${JSON.stringify(signature)}, size: ${info.size}).`);
  }
  return true;
}

async function assertRealWav(file) {
  const info = await stat(file);
  const header = await readHeader(file, 44);
  const riff = header.subarray(0, 4).toString('utf8');
  const wave = header.subarray(8, 12).toString('utf8');
  if (info.size <= 44 || riff !== 'RIFF' || wave !== 'WAVE') {
    throw new Error(`${file} is not a real WAV (riff: ${JSON.stringify(riff)}, wave: ${JSON.stringify(wave)}, size: ${info.size}).`);
  }
}

async function copyOne(source, relativeDestination, role = '') {
  if (source.endsWith('.glb') && !(await assertRealGlb(source, role))) {
    return 0;
  }
  if (source.endsWith('.wav')) {
    await assertRealWav(source);
  }
  const destination = path.join(destinationRoot, relativeDestination);
  await mkdir(path.dirname(destination), { recursive: true });
  await copyFile(source, destination);
  const info = await stat(destination);
  console.log(`${source} -> ${destination} (${info.size} bytes)`);
  return info.size;
}

await rm(destinationRoot, { recursive: true, force: true });
await mkdir(destinationRoot, { recursive: true });

let totalBytes = 0;
for (const [source, destination, role] of modelCopies) {
  totalBytes += await copyOne(source, destination, role ?? '');
}
for (const [source, destination] of uiCopies) {
  totalBytes += await copyOne(source, destination);
}
for (const [source, destination] of audioCopies) {
  totalBytes += await copyOne(source, destination);
}
for (const name of textureNames) {
  totalBytes += await copyOne(
    path.join('src/assets/textures/realworld', name),
    path.join('textures', name),
  );
}

console.log(`Native asset staging complete: ${totalBytes} bytes in ${destinationRoot}`);
