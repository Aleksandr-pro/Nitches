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
  ['src/assets/models/cars/audi_r8_v10_plus.glb', 'vehicles/audi_r8_v10_plus.glb'],
  ['src/assets/models/cars/chevrolet_camaro_ss.glb', 'vehicles/chevrolet_camaro_ss.glb'],
  ['src/assets/models/cars/mercedes_benz_560_sel.glb', 'vehicles/mercedes_benz_560_sel.glb'],
  ['src/assets/models/props/villa.glb', 'buildings/villa.glb'],
  ['src/assets/models/props/glass_tower.glb', 'buildings/glass_tower.glb'],
  ['src/assets/models/props/main_tower.glb', 'buildings/main_tower.glb'],
  ['src/assets/models/props/hero_building.glb', 'buildings/hero_building.glb'],
  ['src/assets/models/props/townhouse.glb', 'buildings/townhouse.glb'],
  ['src/assets/models/props/opera_house.glb', 'buildings/opera_house.glb'],
  ['src/assets/models/props/mosque.glb', 'buildings/mosque.glb'],
  ['src/assets/models/props/grand_hotel.glb', 'buildings/grand_hotel.glb'],
  ['src/assets/models/props/museum.glb', 'buildings/museum.glb'],
  ['src/assets/models/props/cottage_dune.glb', 'buildings/cottage_dune.glb'],
  ['src/assets/models/props/cottage_courtyard.glb', 'buildings/cottage_courtyard.glb'],
  ['src/assets/models/props/cottage_palm.glb', 'buildings/cottage_palm.glb'],
  ['src/assets/models/props/street_lamp.glb', 'props/street_lamp.glb'],
  ['src/assets/models/props/bus_shelter.glb', 'props/bus_shelter.glb'],
  ['src/assets/models/props/park_bench.glb', 'props/park_bench.glb'],
  ['src/assets/models/props/park_pergola.glb', 'props/park_pergola.glb'],
  ['src/assets/models/props/traffic_signal_short.glb', 'props/traffic_signal_short.glb'],
  ['src/assets/models/props/traffic_signal_long.glb', 'props/traffic_signal_long.glb'],
  ['src/assets/models/props/dubai_premium_cafe.glb', 'props/dubai_premium_cafe.glb'],
  ['src/assets/models/props/school.glb', 'props/school.glb'],
  ['src/assets/models/props/airport_terminal.glb', 'props/airport_terminal.glb'],
  ['src/assets/models/props/atc_tower.glb', 'props/atc_tower.glb'],
  ['src/assets/models/props/hangar_large.glb', 'props/hangar_large.glb'],
  ['src/assets/models/props/hangar_small.glb', 'props/hangar_small.glb'],
  ['src/assets/models/props/airliner.glb', 'props/airliner.glb'],
  ['src/assets/models/props/yacht_sail.glb', 'props/yacht_sail.glb'],
  ['src/assets/models/props/yacht_motor.glb', 'props/yacht_motor.glb'],
  ['src/assets/models/props/cooling_tower.glb', 'props/cooling_tower.glb'],
  ['src/assets/models/props/reactor.glb', 'props/reactor.glb'],
  ['src/assets/models/props/chimney.glb', 'props/chimney.glb'],
  ['src/assets/models/props/radar_station.glb', 'props/radar_station.glb'],
  ['src/assets/models/props/watchtower.glb', 'props/watchtower.glb'],
  ['src/assets/models/props/storage_tank.glb', 'props/storage_tank.glb'],
  ['src/assets/models/props/silo.glb', 'props/silo.glb'],
  ['src/assets/models/props/afv.glb', 'props/afv.glb'],
  ['src/assets/models/props/stadium.glb', 'props/stadium.glb'],
  ['src/assets/models/props/office_tower_low.glb', 'props/office_tower_low.glb'],
  ['src/assets/models/props/office_tower_mid.glb', 'props/office_tower_mid.glb'],
  ['src/assets/models/props/office_tower_high.glb', 'props/office_tower_high.glb'],
  ['src/assets/models/props/midrise_a.glb', 'props/midrise_a.glb'],
  ['src/assets/models/props/midrise_b.glb', 'props/midrise_b.glb'],
  ['src/assets/models/props/warehouse_large.glb', 'props/warehouse_large.glb'],
  ['src/assets/models/props/warehouse_small.glb', 'props/warehouse_small.glb'],
  ['src/assets/models/props/container_red.glb', 'props/container_red.glb'],
  ['src/assets/models/props/container_blue.glb', 'props/container_blue.glb'],
  ['src/assets/models/props/villa_b.glb', 'props/villa_b.glb'],
  ['src/assets/models/props/townhouse_b.glb', 'props/townhouse_b.glb'],
  ['src/assets/models/props/barn.glb', 'props/barn.glb'],
  ['src/assets/models/props/greenhouse.glb', 'props/greenhouse.glb'],
  ['src/assets/models/props/shopping_mall.glb', 'props/shopping_mall.glb'],
  ['src/assets/models/props/turbine_hall_long.glb', 'props/turbine_hall_long.glb'],
  ['src/assets/models/props/turbine_hall_short.glb', 'props/turbine_hall_short.glb'],
  ['src/assets/models/props/port_crane.glb', 'props/port_crane.glb'],
  ['src/assets/models/plants.glb', 'vegetation/plants.glb'],
  ['src/assets/models/props/palm_date.glb', 'vegetation/palm_date.glb'],
  ['src/assets/models/props/palm_royal.glb', 'vegetation/palm_royal.glb'],
  ['src/assets/models/props/grass_tuft.glb', 'vegetation/grass_tuft.glb'],
  ['src/assets/models/props/flower_clump.glb', 'vegetation/flower_clump.glb'],
  ['src/assets/models/props/ornamental_shrub.glb', 'vegetation/ornamental_shrub.glb'],
];

// Menu cards are cropped from real in-game CI frames (0.2.36 cards
// from 0.2.35; the three 0.2.40 supplied-car cards are made by
// scripts/make_car_menu_cards.py from shots 08a-08c).  The retired
// photoreal menu renders are deliberately no longer staged.
const uiCopies = [
  ['src/assets/ui/menu_play_gameplay.jpg', 'ui/menu_play_gameplay.jpg'],
  ['src/assets/ui/menu_shelby_gameplay.jpg', 'ui/menu_shelby_gameplay.jpg'],
  ['src/assets/ui/menu_audi_r8_gameplay.jpg', 'ui/menu_audi_r8_gameplay.jpg'],
  ['src/assets/ui/menu_camaro_ss_gameplay.jpg', 'ui/menu_camaro_ss_gameplay.jpg'],
  ['src/assets/ui/menu_mercedes_560_sel_gameplay.jpg', 'ui/menu_mercedes_560_sel_gameplay.jpg'],
  ['src/assets/ui/menu_richtown_gameplay.jpg', 'ui/menu_richtown_gameplay.jpg'],
  ['src/assets/ui/menu_world_gameplay.jpg', 'ui/menu_world_gameplay.jpg'],
  ['src/assets/ui/boot_splash_richtown.jpg', 'ui/boot_splash_richtown.jpg'],
  ['src/assets/ui/steering_wheel_common.png', 'ui/steering_wheel_common.png'],
  ['src/assets/audio/ui_click.wav', 'audio/ui_click.wav'],
];

// 0.2.35 recorded Shelby/Mustang bank.  The phase-aligned GT500 loops
// are staged in both load layers; the long Mustang idle, starter,
// shutdown and tyre recordings complete the vehicle-audio set.
// 0.2.42: 5000/5600 anchors are pulse-synchronous TD-PSOLA
// derivatives of the recorded 4400 loops (recorded texture, gap
// synthesis documented in the bank manifest), and every bank gained
// ten exhaust-pop one-shots cut from the same source loops.
const popNames = Array.from({ length: 10 }, (_, i) => `pop_${String(i + 1).padStart(2, '0')}.wav`);
const shelbyAudioRpms = [900, 1100, 1300, 1500, 1700, 1900, 2100, 2350, 2600, 2850, 3100, 3350, 3600, 3850, 4100, 4400, 5000, 5600];
const shelbyAudioNames = [
  ...shelbyAudioRpms.flatMap((rpm) => [
    `gt500_on_${String(rpm).padStart(4, '0')}.wav`,
    `gt500_off_${String(rpm).padStart(4, '0')}.wav`,
  ]),
  'mustang_idle.wav',
  'mustang_start.wav',
  'mustang_stop.wav',
  'tire_squeal_loop.wav',
  ...popNames,
];
// 0.2.40 recorded banks for the three supplied cars (0.2.42 densified
// with recorded-texture PSOLA anchors + pops).  The generator writes
// phase-trimmed on/off-throttle loops plus idle/start/stop for each
// bank; NativeVehicleAudio selects one bank per catalogue car.
const recordedCarAudioBanks = {
  audi_r8: [1231, 1602, 2400, 3735, 5200, 6800],
  camaro_ss: [635, 1050, 1444, 2265, 2900, 3747, 5000, 6478],
  mercedes_560_sel: [805, 999, 1444, 2265, 2900, 3747, 5000],
};
const recordedCarAudioCopies = Object.entries(recordedCarAudioBanks).flatMap(([bank, rpms]) => {
  const names = [
    ...rpms.flatMap((rpm) => [
      `engine_on_${String(rpm).padStart(4, '0')}.wav`,
      `engine_off_${String(rpm).padStart(4, '0')}.wav`,
    ]),
    'engine_idle.wav',
    'engine_start.wav',
    'engine_stop.wav',
    ...popNames,
  ];
  return names.map((name) => [
    `src/assets/audio/${bank}/${name}`,
    `audio/${bank}/${name}`,
  ]);
});
// 0.2.42 secondary foley: wind/road/impact layers under the recorded
// engine and tyre voices (documented in docs/AUDIO_CREDITS.md).
const foleyAudioNames = [
  'wind_loop.wav', 'road_asphalt.wav', 'road_sidewalk.wav', 'road_grass.wav',
  'road_sand.wav', 'whine_loop.wav', 'impact_soft.wav', 'impact_med.wav',
  'impact_hard.wav', 'suspension_thump.wav', 'shift_clunk.wav', 'scrape_loop.wav',
  'foliage_rustle.wav',
];
const foleyAudioCopies = foleyAudioNames.map((name) => [
  `src/assets/audio/vehicle_foley/${name}`,
  `audio/vehicle_foley/${name}`,
]);
const audioCopies = [
  ...shelbyAudioNames.map((name) => [
    `src/assets/audio/shelby/${name}`,
    `audio/shelby/${name}`,
  ]),
  ...recordedCarAudioCopies,
  ...foleyAudioCopies,
];

const textureNames = [
  'user_grass.jpg', 'user_grass_normal.jpg',
  'user_sand_rippled.jpg', 'user_sand_rippled_normal.jpg', 'user_sand_beach_white.jpg',
  'user_dirt_cracked.jpg',
  'user_stone_rubble.jpg', 'user_stone_rubble_normal.jpg',
  'dz_packed_earth.jpg', 'dz_packed_earth_normal.jpg', 'dz_packed_earth_roughness.jpg',
  'dz_trail_gravel.jpg', 'dz_trail_gravel_normal.jpg', 'dz_trail_gravel_roughness.jpg',
  'dz_sand_dune.jpg', 'dz_sand_dune_normal.jpg', 'dz_sand_dune_roughness.jpg',
  'dz_salt_crust.jpg', 'dz_salt_crust_normal.jpg', 'dz_salt_crust_roughness.jpg',
  'dz_rock_red.jpg', 'dz_rock_red_normal.jpg', 'dz_rock_red_roughness.jpg',
  'dz_cactus_skin.jpg', 'dz_cactus_skin_normal.jpg', 'dz_cactus_skin_roughness.jpg',
  'gf_meadow.jpg', 'gf_meadow_normal.jpg', 'gf_meadow_roughness.jpg',
  'gf_forest_floor.jpg', 'gf_forest_floor_normal.jpg', 'gf_forest_floor_roughness.jpg',
  'gf_mud.jpg', 'gf_mud_normal.jpg', 'gf_mud_roughness.jpg',
  'gf_rock_gray.jpg', 'gf_rock_gray_normal.jpg', 'gf_rock_gray_roughness.jpg', 'gf_rock_gray_ao.jpg',
  'gf_field_soil.jpg', 'gf_field_soil_normal.jpg', 'gf_field_soil_roughness.jpg',
  'gf_birch_bark.jpg', 'gf_birch_bark_normal.jpg', 'gf_birch_bark_roughness.jpg', 'gf_birch_bark_ao.jpg',
  'gf_pine_bark.jpg', 'gf_pine_bark_normal.jpg', 'gf_pine_bark_roughness.jpg', 'gf_pine_bark_ao.jpg',
  'gf_meadow_ao.jpg', 'gf_forest_floor_ao.jpg',
  'gf_leaf_cluster.png', 'gf_birch_cluster.png', 'gf_spruce_spray.png',
  'gf_pine_spray.png', 'gf_grass_tuft.png', 'gf_fern_frond.png',
  'gf_leaf_single.png',
  'metal_pole.jpg', 'metal_pole_normal.jpg',
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
  'oak_bark.jpg', 'oak_bark_normal.jpg', 'oak_bark_roughness.jpg', 'oak_bark_ao.jpg',
  'foliage.jpg', 'foliage_normal.jpg',
  'user_palm_leaf.png',
  'user_sky_day.jpg', 'user_sky_sunset.jpg', 'user_sky_night.jpg',
  'skyline_rich_town_near.png', 'skyline_rich_town_far.png',
  'cafe_linen.jpg', 'cafe_linen_normal.png',
  // 0.2.39 Sail cottage estates: seven authored PBR sets, each with a
  // real roughness map instead of one scalar for every surface.
  'cottage_basalt.jpg', 'cottage_basalt_normal.jpg', 'cottage_basalt_roughness.jpg',
  'cottage_limestone_blocks.jpg', 'cottage_limestone_blocks_normal.jpg', 'cottage_limestone_blocks_roughness.jpg',
  'cottage_paving.jpg', 'cottage_paving_normal.jpg', 'cottage_paving_roughness.jpg',
  'cottage_rammed_sand.jpg', 'cottage_rammed_sand_normal.jpg', 'cottage_rammed_sand_roughness.jpg',
  'cottage_roof_metal.jpg', 'cottage_roof_metal_normal.jpg', 'cottage_roof_metal_roughness.jpg',
  'cottage_teak_weathered.jpg', 'cottage_teak_weathered_normal.jpg', 'cottage_teak_weathered_roughness.jpg',
  'cottage_travertine_coarse.jpg', 'cottage_travertine_coarse_normal.jpg', 'cottage_travertine_coarse_roughness.jpg',
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
