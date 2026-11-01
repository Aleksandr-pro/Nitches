#!/usr/bin/env node
import { readFile, stat } from 'node:fs/promises';
import path from 'node:path';

const requireAssets = process.argv.includes('--require-assets');
const root = 'native';

async function readText(relative) {
  return readFile(path.join(root, relative), 'utf8');
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function parseGlbJson(bytes) {
  assert(bytes.subarray(0, 4).toString('utf8') === 'glTF', 'GLB header is missing');
  const jsonLength = bytes.readUInt32LE(12);
  const jsonType = bytes.readUInt32LE(16);
  assert(jsonType === 0x4e4f534a, 'First GLB chunk is not JSON');
  return JSON.parse(bytes.subarray(20, 20 + jsonLength).toString('utf8'));
}

function parseJpegDimensions(bytes) {
  assert(bytes[0] === 0xff && bytes[1] === 0xd8, 'JPEG header is missing');
  let offset = 2;
  while (offset + 9 < bytes.length) {
    assert(bytes[offset] === 0xff, 'JPEG marker is missing');
    const marker = bytes[offset + 1];
    if ([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf].includes(marker)) {
      return { height: bytes.readUInt16BE(offset + 5), width: bytes.readUInt16BE(offset + 7) };
    }
    if (marker === 0xd8 || marker === 0xd9 || (marker >= 0xd0 && marker <= 0xd7)) {
      offset += 2;
      continue;
    }
    const segmentLength = bytes.readUInt16BE(offset + 2);
    assert(segmentLength >= 2, 'JPEG segment length is invalid');
    offset += 2 + segmentLength;
  }
  throw new Error('JPEG dimensions are missing');
}

const [project, preset, mainScene, dataText, mainScript, loadingScreenScript, worldScript, vehicleScript, hudScript, minimapScript, dynamicWorldScript, speedPostScript, arcadeCarScript, carPaintShader, speedPostShader, wetAsphaltShader, foliageWindShader, curtainWallGlassShader, curtainWallFacadeShader, concreteSurfaceShader, premiumStonePavingShader, syncScript, blenderScript, desktopWorkflow, mainMenuScript, steeringWheelScript, worldMapScript, dashboardGaugeScript, touchPedalScript, roundActionButtonScript, circularMaskShader, routeGuideScript, carSilhouetteScript, backdropBlurShader, vehicleAudioScript, ignitionButtonScript, audioCredits, avatarIconScript, wheelPreviewScript, lockIconScript, carCatalogScript, desertDataText, forestDataText] = await Promise.all([
  readText('project.godot'),
  readText('export_presets.cfg'),
  readText('scenes/main.tscn'),
  readText('data/richtown_native.json'),
  readText('scripts/main.gd'),
  readText('scripts/loading_screen.gd'),
  readText('scripts/world_builder.gd'),
  readText('scripts/vehicle_controller.gd'),
  readText('scripts/hud.gd'),
  readText('scripts/minimap.gd'),
  readText('scripts/dynamic_world.gd'),
  readText('scripts/speed_post.gd'),
  readText('scripts/arcade_car.gd'),
  readText('shaders/car_paint.gdshader'),
  readText('shaders/speed_post.gdshader'),
  readText('shaders/wet_asphalt.gdshader'),
  readText('shaders/foliage_wind.gdshader'),
  readText('shaders/curtain_wall_glass.gdshader'),
  readText('shaders/curtain_wall_facade.gdshader'),
  readText('shaders/concrete_surface.gdshader'),
  readText('shaders/premium_stone_paving.gdshader'),
  readFile('scripts/sync-native-assets.mjs', 'utf8'),
  readFile('blender/build_props.py', 'utf8'),
  readFile('.github/workflows/native-godot-desktop.yml', 'utf8'),
  readText('scripts/main_menu.gd'),
  readText('scripts/steering_wheel.gd'),
  readText('scripts/world_map.gd'),
  readText('scripts/dashboard_gauge.gd'),
  readText('scripts/touch_pedal.gd'),
  readText('scripts/round_action_button.gd'),
  readText('shaders/circular_mask.gdshader'),
  readText('scripts/route_guide.gd'),
  readText('scripts/car_silhouette_icon.gd'),
  readText('shaders/backdrop_blur.gdshader'),
  readText('scripts/vehicle_audio.gd'),
  readText('scripts/ignition_button.gd'),
  readFile('docs/AUDIO_CREDITS.md', 'utf8'),
  readText('scripts/avatar_icon.gd'),
  readText('scripts/wheel_preview.gd'),
  readText('scripts/lock_icon.gd'),
  readText('scripts/car_catalog.gd'),
  readText('data/desert_native.json'),
  readText('data/greenforest_native.json'),
]);

assert(project.includes('run/main_scene="res://scenes/main.tscn"'), 'project.godot does not point at the native main scene');
assert(project.includes('renderer/rendering_method="mobile"'), 'Godot Mobile renderer is not selected');
assert(project.includes('textures/default_filters/anisotropic_filtering_level=4'), '4x anisotropic filtering is not enabled');
assert(project.includes('lights_and_shadows/directional_shadow/size.mobile=1024'), '0.3.3 phones must use the 1024px mobile directional shadow budget');
assert(mainScene.includes('res://scripts/main.gd'), 'main scene is not wired to main.gd');

assert(preset.includes('platform="Android"'), 'Android export preset is missing');
assert(preset.includes('architectures/arm64-v8a=true'), 'ARM64 Android export is not enabled');
assert(preset.includes('package/unique_name="io.nitches.horizon"'), 'Android package id differs from io.nitches.horizon');
assert(preset.includes('include_filter="*.json"'), 'Android export must explicitly include non-resource JSON world data');
assert(project.includes('config/version="0.3.16-native-alpha"'), 'Native project version metadata must match 0.3.16-native-alpha');
assert(preset.includes('version/code=82'), 'Native 0.3.16 must bump Android versionCode to 82');
assert(preset.includes('version/name="0.3.16-native-alpha"'), 'Native version name must be 0.3.16-native-alpha');
assert(mainMenuScript.includes('Nitches 0.3.16-native-alpha'), 'Main menu version label must match the native export version');
for (const name of ['skyline_rich_town_near.png', 'skyline_rich_town_far.png']) {
  assert(syncScript.includes(`'${name}'`), `Native asset sync must stage ${name}`);
  const png = await readFile(path.join('src/assets/textures/realworld', name));
  assert(png.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])), `${name} is not a valid PNG`);
  assert(png.readUInt32BE(16) === 4096 && png.readUInt32BE(20) === 512, `${name} must be a 4096x512 skyline panorama`);
}
for (const marker of ['skyline_panorama_textures_0243', 'near_field_lod_0243', 'range_fade_mode', 'tree_detail_end_m', 'palm_detail_end_m', 'shrub_detail_end_m']) {
  assert(worldScript.includes(marker), `0.2.43 near-field/skyline validation marker is missing: ${marker}`);
}
assert(project.includes('boot_splash/image="res://assets/ui/boot_splash_richtown.jpg"') && project.includes('boot_splash/fullsize=true') && project.includes('boot_splash/show_image=true') && project.includes('boot_splash/min_display_time=0'), 'Native 0.2.52 must replace the default Godot boot splash with the branded fullscreen RichTown splash');
assert(syncScript.includes('boot_splash_richtown.jpg'), 'Native asset sync must stage the 0.2.52 boot splash');
const bootSplash = await readFile('src/assets/ui/boot_splash_richtown.jpg');
const bootSplashSize = parseJpegDimensions(bootSplash);
assert(bootSplash.length > 150_000 && bootSplashSize.width === 1920 && bootSplashSize.height === 1080, `Native 0.2.52 boot splash must be a detailed 1920x1080 gameplay frame, got ${bootSplashSize.width}x${bootSplashSize.height}`);
for (const marker of ['class_name NativeLoadingScreen', 'custom_loading_screen_0252', 'menu_richtown_gameplay.jpg', 'error_continue_requested', 'get_visual_state', 'hide_immediately']) {
  assert(loadingScreenScript.includes(marker), `Native 0.2.52 loading-screen marker is missing: ${marker}`);
}
for (const marker of ['begin_build_world', 'build_world_step', 'get_build_progress_state', 'is_build_finished']) {
  assert(worldScript.includes(marker), `Native 0.2.52 staged world-build marker is missing: ${marker}`);
}
for (const marker of ['_bootstrap_game_async', '_build_world_with_loading', '_switch_world_async', '0.2.52 branded loading screen']) {
  assert(mainScript.includes(marker), `Native 0.2.52 async bootstrap marker is missing: ${marker}`);
}
for (const marker of ['wet_streak', 'wet_roughness', 'puddle_roughness']) {
  assert(wetAsphaltShader.includes(marker), `0.2.43 low-cost wet-road shading marker is missing: ${marker}`);
}
const atmosphereFxScript = await readText('scripts/atmosphere_fx.gd');
for (const marker of ['get_foliage_density_at', 'get_headlight_world_positions', 'leaves', 'petals', 'light_shafts', 'headlight_bokeh']) {
  assert(atmosphereFxScript.includes(marker), `0.2.43 near-car atmosphere effect marker is missing: ${marker}`);
}
for (const marker of ['0.2.43 two-layer textured skyline', '0.2.43 near-field HLOD budget', '0.2.43 nearby atmosphere/foliage shaft gate', 'camera far plane does not match the active graphics preset', '0.2.44 user graphics quality / foliage spatial grid', '0.2.44 foliage-rustle ambience']) {
  assert(mainScript.includes(marker), `Native smoke test is missing acceptance check: ${marker}`);
}
// 0.2.44: user graphics presets, build-time foliage spatial grid and
// the foliage-rustle ambience gate must stay wired end to end.
for (const marker of ['FOLIAGE_GRID_CELL_M', '_build_foliage_grid', 'foliage_spatial_grid_0244', 'set_quality_detail_scale', 'set_quality_shadow_distance', 'set_skyline_scale', '_quality_ranged_instances']) {
  assert(worldScript.includes(marker), `0.2.44 world quality/grid marker is missing: ${marker}`);
}
for (const marker of ['graphics_quality', '_apply_graphics_quality', '"performance"', '"balanced"', '"beauty"', 'scaling_3d_scale']) {
  assert(mainScript.includes(marker), `0.2.44 graphics-preset marker is missing: ${marker}`);
}
for (const marker of ['СКОРОСТЬ', 'БАЛАНС', 'КРАСОТА', 'graphics_quality']) {
  assert(mainMenuScript.includes(marker), `0.2.44 settings UI marker is missing: ${marker}`);
}
for (const marker of ['set_quality', '_particle_budgets', 'quality_particle_scale']) {
  assert(atmosphereFxScript.includes(marker), `0.2.44 atmosphere quality marker is missing: ${marker}`);
}
assert(vehicleAudioScript.includes('foliage_rustle.wav') && vehicleAudioScript.includes('foliage_rustle_ready_0244') && vehicleScript.includes('"foliage_density"'), '0.2.44 foliage rustle must be gated by the controller-sampled foliage density');
for (const key of ['keystore/debug_password', 'keystore/release_password']) {
  const line = preset.split(/\r?\n/).find((entry) => entry.startsWith(`${key}=`));
  assert(line === `${key}=""`, `${key} must stay empty in Git; CI supplies credentials by environment`);
}

// 0.2.21 desktop parity: Windows/Linux export the identical native game.
assert(preset.includes('platform="Windows Desktop"') && preset.includes('name="Windows"'), 'Windows desktop export preset is missing');
assert(preset.includes('platform="Linux"') && preset.includes('name="Linux"'), 'Linux desktop export preset is missing');
assert((preset.match(/include_filter="\*\.json"/g) ?? []).length >= 3, 'Android, Windows and Linux presets must all include the JSON world data');
assert(preset.includes('application/modify_resources=false'), 'Windows export from Linux CI must not require rcedit (application/modify_resources=false)');
assert(preset.includes('application/file_version="0.3.16"') && preset.includes('application/product_version="0.3.16"'), 'Desktop Windows version metadata must match native 0.3.16');
assert(preset.includes('binary_format/include_pck=true'), 'Desktop exports must embed the PCK for single-file install-and-play builds');
for (const marker of ['--export-release Windows', '--export-release Linux', '--native-smoke', 'NitchesHorizonNative-windows', 'NitchesHorizonNative-linux']) {
  assert(desktopWorkflow.includes(marker), `Desktop workflow marker is missing: ${marker}`);
}
for (const marker of ['--native-screenshots', '_run_screenshot_tour', '_capture_screenshot', '[native-screenshots] DONE']) {
  assert(mainScript.includes(marker), `Visual-audit screenshot tour marker is missing: ${marker}`);
}
assert((mainScript.match(/_run_screenshot_tour/g) ?? []).length >= 2, 'Screenshot tour must be both defined and called from _ready');
assert(curtainWallGlassShader.includes('depth_prepass_alpha') && !curtainWallGlassShader.includes('depth_draw_alpha_prepass'), 'Curtain-wall glass shader must use the Godot 4 depth_prepass_alpha render mode (the Godot 3 name never compiles, found by the screenshot tour)');

const combinedRuntime = `${steeringWheelScript}\n${worldMapScript}\n${mainScript}\n${loadingScreenScript}\n${worldScript}\n${vehicleScript}\n${hudScript}\n${dynamicWorldScript}\n${speedPostScript}\n${arcadeCarScript}\n${carPaintShader}\n${speedPostShader}\n${wetAsphaltShader}\n${foliageWindShader}\n${curtainWallGlassShader}\n${curtainWallFacadeShader}\n${concreteSurfaceShader}\n${premiumStonePavingShader}\n${mainMenuScript}\n${minimapScript}\n${dashboardGaugeScript}\n${touchPedalScript}\n${roundActionButtonScript}\n${circularMaskShader}\n${routeGuideScript}\n${carSilhouetteScript}\n${backdropBlurShader}\n${vehicleAudioScript}\n${ignitionButtonScript}\n${avatarIconScript}\n${wheelPreviewScript}\n${lockIconScript}\n${carCatalogScript}`;
for (const marker of ['KEY_F11', '_toggle_desktop_fullscreen', '_ensure_action(&"accelerate"', '_ensure_action(&"boost"', '_ensure_action(&"camera_toggle"']) {
  assert(combinedRuntime.includes(marker), `Native 0.2.21 desktop parity marker is missing: ${marker}`);
}
// 0.2.22 RichTown parks: Central Park, Museum Garden, Corniche Palmetum.
for (const marker of ['PARK_SPECS', '_build_parks', 'parks_0222', 'RichTown Central Park', 'Museum Garden', 'Corniche Palmetum', 'central_park_fountain_garden', 'museum_garden_pergola', 'beach_palmetum_rondel', '_is_in_park', 'get_park_rects', '_park_plant_oak_grove', '_park_plant_palm_grove', '_park_plant_parterre']) {
  assert(combinedRuntime.includes(marker), `Native 0.2.22 parks marker is missing: ${marker}`);
}
assert(minimapScript.includes('_draw_rotated_rect') && minimapScript.includes('get_park_map_entries'), 'Minimap must draw the 0.2.22 RichTown parks from the HUD world-data binding');
// 0.2.23 photoreal model detail pass: denser palms/ground cover and
// fully modelled street/park furniture with per-model triangle stats.
for (const marker of ['photoreal_models_0223', 'photoreal_park_furniture_0223', 'street_lamp_triangles', 'bus_shelter_triangles', 'park_bench_triangles', 'park_pergola_triangles', 'park_bench_models', 'BlenderParkBenches', 'BlenderParkPergola', 'res://assets/props/park_bench.glb', 'res://assets/props/park_pergola.glb']) {
  assert(combinedRuntime.includes(marker), `Native 0.2.23 photoreal-model marker is missing: ${marker}`);
}
for (const marker of ['def build_park_bench():', 'def build_park_pergola():', '(build_park_bench, "park_bench.glb")', '(build_park_pergola, "park_pergola.glb")']) {
  assert(blenderScript.includes(marker), `Blender 0.2.23 park-model marker is missing: ${marker}`);
}
assert(syncScript.includes('park_bench.glb') && syncScript.includes('park_pergola.glb'), 'Native asset sync is missing the 0.2.23 park bench/pergola GLBs');
// 0.2.24 districts/roads: synthetic local streets in the exported data,
// rounded kerb returns, cross-road kerb/paint openings and guardrails
// trimmed clear of the Corniche junctions.
for (const marker of ['district_infrastructure_0224', '_build_district_infrastructure', '_build_rounded_intersection_returns', '_clearance_to_other_roads', 'rounded_intersection_returns', 'rounded_corner_curbs', 'junction_edge_openings_0224', 'junction_paint_breaks_0224', 'guardrail_trim_start_m', 'guardrail_terminals', 'guardrail_min_alignment']) {
  assert(combinedRuntime.includes(marker), `Native 0.2.24 district/road marker is missing: ${marker}`);
}
assert(!combinedRuntime.includes('NativeTrafficManager') && !combinedRuntime.includes('traffic_manager.gd') && !mainScript.includes('TrafficScript'), 'Native 0.2.16 must not load any traffic-car system');
assert(!worldScript.includes('user_facade_blue_glass.jpg') && !worldScript.includes('user_facade_gold_grid.jpg'), 'Native 0.2.16 must not return to photographic blue/gold facade sheets');
assert(!curtainWallGlassShader.includes('\n\tCLEARCOAT') && !curtainWallFacadeShader.includes('\n\tCLEARCOAT'), 'Native 0.2.16 curtain-wall shaders must not pay for a clearcoat lighting layer');
assert(!curtainWallFacadeShader.includes('\n\tALPHA ='), 'Native 0.2.16 opaque curtain-wall facade must not write ALPHA');
assert(curtainWallGlassShader.includes('surface_metallic') && curtainWallFacadeShader.includes('surface_metallic'), 'Native 0.2.16 curtain-wall shaders must use a reflective coating layer');
for (const shader of [curtainWallGlassShader, curtainWallFacadeShader]) {
  assert(shader.includes('RADIANCE =') && shader.includes('sky_reflection_color') && shader.includes('ground_reflection_color') && shader.includes('METALLIC = clamp(surface_metallic, 0.0, 0.96)') && shader.includes('SPECULAR = 0.50'), 'Native 0.2.17 curtain-wall shaders must keep dark near-metallic environment reflections');
}
assert(!worldScript.includes('_get_palm_crown_mesh') && !worldScript.includes('_palm_leaf_material') && !worldScript.includes('"PalmCrowns"') && !worldScript.includes('"PalmTrunks"'), 'Native 0.2.17 must not return to alpha-card palms');
for (const marker of ['paver_id', 'gum_spots', 'macro_stain', 'world_position', 'pattern_scale']) {
  assert(concreteSurfaceShader.includes(marker), `Native 0.2.17 concrete shader marker is missing: ${marker}`);
}
for (const marker of ['stone_texture', 'fine_normal_texture', 'dominant_plane', 'district_variation', 'polished_wear', 'PremiumStone', 'formal_slab_joint', 'formal_slab_id', 'slab_joint']) {
  assert(premiumStonePavingShader.includes(marker) || worldScript.includes(marker), `Native 0.2.19 premium stone paving marker is missing: ${marker}`);
}
assert(wetAsphaltShader.includes('boulevard_mask') && worldScript.includes('boulevard_dark_asphalt_0219'), 'Native 0.2.19 must keep the dark resurfaced RichTown Boulevard asphalt mask');
for (const vegetationModel of ['palm_date.glb', 'palm_royal.glb', 'grass_tuft.glb', 'flower_clump.glb', 'ornamental_shrub.glb']) {
  assert(syncScript.includes(vegetationModel), `Native asset sync is missing ${vegetationModel}`);
  assert(worldScript.includes(`res://assets/vegetation/${vegetationModel}`), `Native world does not load ${vegetationModel}`);
}
assert(syncScript.includes('user_sand_beach_white.jpg'), 'Native asset sync is missing the 0.2.18 white-pebble texture');
for (const marker of ['def build_palm_date():', 'def build_palm_royal():', 'def build_grass_tuft():', 'def build_flower_clump():', 'def build_ornamental_shrub():']) {
  assert(blenderScript.includes(marker), `Blender vegetation builder is missing: ${marker}`);
}
assert(blenderScript.includes('def build_opera():') && blenderScript.includes('(build_opera, "opera_house.glb")'), 'Blender Building Model No.6 opera builder/export is missing');
assert(syncScript.includes('opera_house.glb') && worldScript.includes('res://assets/buildings/opera_house.glb'), 'Native 0.2.20 must stage and load the RichTown Opera GLB');
for (const marker of ['premium_opera_built', 'premium_opera_fixed_scale', 'premium_opera_detail_pass', 'premium_opera_material_pass', 'premium_opera_site_pass', 'premium_opera_fronts_boulevard', 'RichTownOpera', 'opera_glass_physical', 'opera_shell_ceramic']) {
  assert(combinedRuntime.includes(marker), `Native 0.2.20 opera marker is missing: ${marker}`);
}
assert(blenderScript.includes('def build_mosque():') && blenderScript.includes('(build_mosque, "mosque.glb")'), 'Blender Building Model No.7 mosque builder/export is missing');
assert(syncScript.includes('mosque.glb') && worldScript.includes('res://assets/buildings/mosque.glb'), 'Native 0.2.25 must stage and load the RichTown Mosque GLB');
for (const marker of ['premium_mosque_built', 'premium_mosque_fixed_scale', 'premium_mosque_detail_pass', 'premium_mosque_material_pass', 'premium_mosque_site_pass', 'premium_mosque_fronts_east', 'RichTownMosque', 'mosque_glass_physical', 'mosque_dome_copper', 'mosque_glazed_tile']) {
  assert(combinedRuntime.includes(marker), `Native 0.2.25 mosque marker is missing: ${marker}`);
}
assert(blenderScript.includes('def build_hotel():') && blenderScript.includes('(build_hotel, \"grand_hotel.glb\")'), 'Blender Building Model No.8 grand hotel builder/export is missing');
assert(syncScript.includes('grand_hotel.glb') && worldScript.includes('res://assets/buildings/grand_hotel.glb'), 'Native 0.2.26 must stage and load the Grand Hotel GLB');
for (const marker of ['premium_hotel_models', 'premium_hotel_fixed_scale', 'premium_hotel_detail_pass', 'premium_hotel_material_pass', 'premium_hotel_site_pass', 'premium_hotel_fronts_corniche', 'BlenderGrandHotels', 'hotel_glass_physical', 'hotel_travertine', 'hotel_pool_water']) {
  assert(combinedRuntime.includes(marker), `Native 0.2.26 grand hotel marker is missing: ${marker}`);
}
assert(blenderScript.includes('def build_museum():') && blenderScript.includes('(build_museum, "museum.glb")'), 'Blender Building Model No.9 museum builder/export is missing');
assert(syncScript.includes('museum.glb') && worldScript.includes('res://assets/buildings/museum.glb'), 'Native 0.2.29 must stage and load the Museum GLB');
for (const marker of ['premium_museum_built', 'premium_museum_fixed_scale', 'premium_museum_detail_pass', 'premium_museum_material_pass', 'premium_museum_site_pass', 'premium_museum_fronts_fountain', 'RichTownMuseum', 'museum_glass_physical', 'museum_limestone', 'museum_pool_water']) {
  assert(combinedRuntime.includes(marker), `Native 0.2.29 museum marker is missing: ${marker}`);
}
// 0.2.39 Building Models No.10-12: three distinct fixed-scale Dubai
// cottage estates on Sail Island with authored PBR roughness maps,
// retaining podiums, multi-box colliders and an open SW lookout.
for (const marker of ['def build_cottage_dune():', 'def build_cottage_courtyard():', 'def build_cottage_palm():', '(build_cottage_dune, "cottage_dune.glb")', '(build_cottage_courtyard, "cottage_courtyard.glb")', '(build_cottage_palm, "cottage_palm.glb")']) {
  assert(blenderScript.includes(marker), `Blender cottage-estate builder/export is missing: ${marker}`);
}
for (const cottageModel of ['cottage_dune.glb', 'cottage_courtyard.glb', 'cottage_palm.glb']) {
  assert(syncScript.includes(cottageModel), `Native asset sync is missing ${cottageModel}`);
  assert(worldScript.includes(`res://assets/buildings/${cottageModel}`), `Native world does not load ${cottageModel}`);
}
for (const roughnessMap of ['cottage_basalt_roughness.jpg', 'cottage_limestone_blocks_roughness.jpg', 'cottage_paving_roughness.jpg', 'cottage_rammed_sand_roughness.jpg', 'cottage_roof_metal_roughness.jpg', 'cottage_teak_weathered_roughness.jpg', 'cottage_travertine_coarse_roughness.jpg']) {
  assert(syncScript.includes(roughnessMap), `Native asset sync is missing the PBR roughness map ${roughnessMap}`);
  assert(worldScript.includes(roughnessMap), `Native world does not use the PBR roughness map ${roughnessMap}`);
}
for (const marker of ['sail_cottage_estates_0239', 'sail_cottage_models_0239', 'sail_cottage_fixed_scale_0239', 'sail_cottage_exterior_only_0239', 'sail_cottage_pbr_roughness_0239', 'sail_cottage_material_pass_0239', 'sail_cottage_multi_box_colliders_0239', 'sail_cottage_podiums_0239', 'sail_cottage_dune_triangles_0239', 'sail_cottage_courtyard_triangles_0239', 'sail_cottage_palm_triangles_0239', 'sail_cottage_garden_palms_0239', 'sail_open_lookout_0239', 'sail_cottage_resort_fit_0239', 'SailCottageDune', 'SailCottageCourtyard', 'SailCottagePalm', 'SailCottagePodiums', 'cottage_rammed_sand', 'cottage_travertine_coarse', 'cottage_glass_physical', '_cottage_estate_ground_y_0239', '_add_cottage_estate_colliders_0239', 'roughness_texture_channel', '23_rich_hills_villas', '24_beach_sunset', '25_mall', '26_city_aerial_7km']) {
  assert(combinedRuntime.includes(marker), `Native 0.2.39 cottage-estate marker is missing: ${marker}`);
}
for (const marker of ['class_name NativeSteeringWheel', 'steering_changed', 'MAX_LOCK_DEGREES', 'CENTERING_RATE_PER_SEC', 'set_touch_steering', 'touch_steering_wheel_0232', 'class_name NativeWorldMap', 'world_map_0232', 'map_requested', 'world_map_requested', 'map_toggle', 'DISTRICT_NAMES', 'ROAD_LABELS', '_select_poi_at', '_set_zoom_factor', 'get_park_map_entries']) {
  assert(combinedRuntime.includes(marker), `Native 0.2.32 steering-wheel/world-map marker is missing: ${marker}`);
}
assert(hudScript.includes('_control_type == "arrows"') && hudScript.includes('_wheel.visible = _control_type != "arrows"'), 'Native 0.2.33 HUD must default to the steering wheel and expose arrows only as a settings alternative');
for (const marker of ['get_global_transform_interpolated', 'PHYSICS_INTERPOLATION_MODE_OFF', 'reset_physics_interpolation', 'responsive_steering', 'ramp_digital_steering', 'shape_steering_input', 'CONTACT_PATCH_SAMPLES', 'TYRE_RELAXATION_LENGTH_M', 'free_orbit_0231', 'InputEventScreenDrag', 'InputEventMouseMotion', 'JOY_AXIS_RIGHT_X']) {
  assert(combinedRuntime.includes(marker), `Native 0.2.31 anti-jitter/steering/free-camera marker is missing: ${marker}`);
}
assert(project.includes('common/physics_interpolation=true'), 'Native 0.2.31 requires project physics interpolation');
for (const marker of ['directional_streaming_0230', 'update_streaming', '_streaming_tick', '_register_collider', 'streaming_colliders_total', 'STREAM_HIDE_BEHIND_M']) {
  assert(combinedRuntime.includes(marker), `Native 0.2.30 directional-streaming marker is missing: ${marker}`);
}
for (const marker of ['class_name NativeMainMenu', 'play_requested', 'nitches_profile.cfg', 'get_spec_sheet', 'SPEC_TORQUE_NM', 'menu_requested', '_update_menu_camera']) {
  assert(combinedRuntime.includes(marker), `Native 0.2.29 main-menu/spec marker is missing: ${marker}`);
}
for (const marker of ['paving_variety_0228', 'paving_running_bond_0228', 'bond_cell', 'joint_grime', 'batch_drift']) {
  assert(combinedRuntime.includes(marker), `Native 0.2.28 paving-variety marker is missing: ${marker}`);
}
for (const marker of ['scaled_local(scale_value)', 'curtain_wall_reflective_glass_0227', 'glass_smoke_luminance_min_0227', 'guardrail_local_axis_0227']) {
  assert(combinedRuntime.includes(marker), `Native 0.2.27 reflective-glass/local-axis marker is missing: ${marker}`);
}
assert(!worldScript.includes('Basis(Vector3.UP, yaw).scaled('), 'Native 0.2.27 make_transform must not use global-space Basis.scaled()');
for (const forbidden of ['WebView', 'Capacitor', 'JavaScriptBridge', 'http://localhost', 'https://localhost']) {
  assert(!combinedRuntime.includes(forbidden), `Native runtime must not contain ${forbidden}`);
}
for (const marker of ['class_name NativeDashboardGauge', 'class_name NativeTouchPedal', 'class_name NativeRoundActionButton', 'NativeDashboardGauge', 'hud_0233', 'safe_area_3pct_4pct', 'circular_heading_up_0233', 'circular_gauge_0233', 'analog_pedal_0233', 'round_action_0233', 'set_control_preferences', 'set_touch_pedal', 'shape_steering_input_with_preferences', '_update_tilt_steering', 'nitches_settings.cfg', 'settings_panel_0233', 'bind_settings', 'show_settings', 'destination_changed', 'get_minimap_points', 'district_notice_seconds']) {
  assert(combinedRuntime.includes(marker), `Native 0.2.33 HUD/settings marker is missing: ${marker}`);
}
assert(!hudScript.includes('NITCHES HORIZON • NATIVE') && !hudScript.includes('"CAM"') && !hudScript.includes('"TIME"') && !hudScript.includes('"RESET"') && !hudScript.includes('"MENU"'), 'Native 0.2.33 HUD must not restore the removed text panel/buttons');
assert(hudScript.includes('_performance_label.visible = false') && hudScript.includes('set_developer_mode'), 'Native 0.2.33 performance text must stay hidden until developer mode');
// 0.2.34 clean front end: one accent, icon tabs instead of duplicated
// home shortcuts, picture-led PLAY/world cards, a hidden unfinished
// store, frosted translucent panels, click/press feedback, a real
// 3D garage studio and persisted Shelby paint/wheels/tuning/plate.
for (const marker of ['clean_menu_0234', 'store_panel_0236', 'labeled_tabs_0236', 'backdrop_blur_0234', 'hint_screen_texture', 'textureLod(screen_texture', 'FontVariation', 'variation_embolden', 'variation_transform', 'MENU_PLAY_TEXTURE', 'MENU_SHELBY_TEXTURE', 'MENU_RICHTOWN_TEXTURE', 'MENU_WORLD_TEXTURE', 'menu_play_gameplay.jpg', 'menu_shelby_gameplay.jpg', 'menu_richtown_gameplay.jpg', 'menu_world_gameplay.jpg', 'UI_CLICK_STREAM', 'class_name NativeCarSilhouetteIcon', 'car_silhouette_icon_0234', 'panel_changed', 'garage_dragged', 'garage_zoomed', 'customization_changed', 'tuning_purchase_requested', 'profile_changed', 'GarageStudio0234', '_create_garage_studio', '_set_garage_active', 'StudioTurntable', 'set_paint_color', 'set_wheel_finish', 'set_tuning_level', 'get_tuning_preview', 'set_license_plate', 'customization_0234', 'TUNING_TORQUE_MULTIPLIERS', 'xp_progress', 'drift_record_deg', 'achievements', 'car_stats', '_claim_achievement_rewards', '_credit_distance_bank_m']) {
  assert(combinedRuntime.includes(marker), `Native 0.2.34 menu/garage/profile marker is missing: ${marker}`);
}
for (const marker of ['_build_store_panel', 'PANEL_STORE', '_store_items', '_cycle_store_sort', '_on_store_action_pressed', 'StoreDragSurface0236', 'top_xp_bar_0236', 'clickable_home_cards_0236', 'home_goal_0236', 'wheel_previews_0236', 'profile_single_scroll_0236', 'achievement_cards_0236', 'locked_world_conditions_0236', 'hover_sound_0236', 'gameplay_card_textures_0236', 'PANEL_TRANSITION_SECONDS := 0.18', 'MIN_FONT_SIZE := 14', 'MIN_TOUCH_HEIGHT := 48.0', 'StudioReflectionProbe0236', '"current": distance_km', '"unit": "км"', '"progress": clampf', 'NativeMainMenu.PANEL_STORE', '11_menu_store']) {
  assert(combinedRuntime.includes(marker), `Native 0.2.36 readable-menu/store marker is missing: ${marker}`);
}
// 0.2.36 road-infrastructure repair: junction pads, zebras, stop
// lines, tactile paving and signal heads are generated only for road
// arms that really exist; shelters/planters/bins/signs are checked by
// footprint, and curb/paint geometry is subdivided only near real
// junction mouths so openings no longer stop at source-sample bounds.
for (const marker of ['road_infrastructure_repair_0236', '_junction_arm_mask', '_junction_has_both_axes', '_is_footprint_clear_of_roads', '_is_pole_clear_of_road', '_subdivide_road_points_for_junctions', 'rejected_fake_junction_pads_0236', 'real_crosswalk_groups_0236', 'rejected_fake_crosswalks_0236', 'rejected_offroad_crosswalk_stripes_0236', 'traffic_signals_on_real_arms_0236', 'rejected_fake_signal_approaches_0236', 'continuous_arterial_curbs_0236', 'rounded_curb_edge_alignment_0236', 'road_junction_subsegments_0236', 'bike_lane_junction_breaks_0236', 'bus_shelter_footprints_clear_0236', 'roadside_footprints_clear_0236', 'rejected_road_palms_0236', 'rejected_road_trees_0236', 'rejected_road_bushes_0236', 'rejected_road_lamps_0236', '15_corniche_t_junction', '16_corniche_l_corner', '17_plaza_ring_junction', '18_west_t_junction']) {
  assert(combinedRuntime.includes(marker), `Native 0.2.36 road-infrastructure marker is missing: ${marker}`);
}
assert(!worldScript.includes('{"x": 914.0, "z": -300.0') && !worldScript.includes('{"x": 914.0, "z": -110.0') && !worldScript.includes('{"x": 914.0, "z": 70.0'), 'Native 0.2.36 must not restore the Corniche bus shelters centred on cross streets/crosswalks');
// 0.2.37 performance without touching shaders or the car model:
// whole MultiMesh chunks outside the side of the horizontal view cone
// retire with a wide margin, flat kerb/slab/deck layers leave the
// shadow pass, and the minimap renders its static road network once.
// The same pass expands Sail Island into a landscaped resort with a
// loop road and audits every canonical building's true footprint.
for (const marker of ['view_sector_streaming_0237', 'STREAM_SECTOR_HIDE_MARGIN_RAD', 'horizontal_half_fov', '_is_flat_shadow_free_multimesh_0237', 'flat_shadow_casters_disabled_0237', 'static_map_cache_0237', '_draw_cached_world', '_draw_static_cache', 'UPDATE_ONCE', '_expand_sail_island_0237', 'rt-sail-loop', 'sail_island_land_area_m2_0237', '_build_sail_island_resort_0237', 'sail_island_promenade_segments_0237', 'sail_island_infill_excluded_0237', '_sanitize_canonical_buildings_0237', '_sanitize_canonical_pools_0237', '_rect_road_clearance_0237', 'canonical_building_min_clearance_0237', 'canonical_pools_relocated_0237', 'bridge_roadside_props_removed_0237', 'readable_road_signs_0237', 'CityRoadSignBacks0237', 'road_wear_scale_0237', '19_corniche_hotels', '20_cable_bridge_arrival']) {
  assert(combinedRuntime.includes(marker), `Native 0.2.37 performance/Sail Island marker is missing: ${marker}`);
}
assert(minimapScript.includes('func _draw_vector_world() -> void:\n    var radius := _clip_radius()'), 'Native 0.2.37 minimap vector fallback must declare its clip radius locally, not borrow _draw() scope');
// 0.2.38 Sail Island loop road repair from the phone screenshots:
// the closed oval gets a seam tangent + entry pad, single broken
// centreline, no closed-chain arrows and no random wear/props;
// resort paving/hedges/pools are fitted and re-audited against the
// carriageway, and the pool audit counts the concrete rim without
// letting a pool reject its own relocation candidate.
for (const marker of ['closedLoop0238', 'resortRoad0238', 'sail_loop_closed_0238', 'sail_loop_entry_pad_0238', 'sail_loop_center_dashes_0238', 'sail_loop_clean_markings_0238', 'sail_loop_pristine_asphalt_0238', 'sail_resort_min_road_clearance_0238', 'sail_resort_rejected_road_overlaps_0238', 'sail_island_hedges_0238', 'sail_pools_final_0238', 'sail_pool_min_road_clearance_0238', 'sail_loop_road_repair_0238', 'canonical_pool_rim_clearance_0238', 'canonical_pool_self_excluded_0238', 'excluded_pool_index', 'sail_loop_generic_props_removed_0238', 'sail_loop_segments_without_props_0238', '21_stadium', '22_downtown_aerial']) {
  assert(combinedRuntime.includes(marker), `Native 0.2.38 Sail loop road-repair marker is missing: ${marker}`);
}
assert(worldScript.includes('{"x": 1216.0, "z": 80.0, "w": 16.0, "d": 26.0}') && worldScript.includes('{"x": 1149.8, "z": 80.0, "w": 4.4, "d": 18.0'), 'Native 0.2.38 must keep the east Sail pool and arrival apron inside the loop with road clearance');
assert(!worldScript.includes('{"x": 1150.0, "z": 80.0, "w": 30.0, "d": 62.0') && !worldScript.includes('{"x": 1220.0, "z": 61.0, "w": 20.0') && !worldScript.includes('{"x": 1220.0, "z": 99.0, "w": 20.0'), 'Native 0.2.38 must not restore the Sail paving/hedge bars that crossed the loop carriageway');
// 0.2.40 four-car catalogue: one parameterised RigidBody, owner-supplied
// Audi/Camaro/Mercedes GLBs, separate recorded banks, a photographic
// replaceable HUD wheel, per-car customization/stats and a compulsory
// in-game screenshot for every car.
for (const marker of ['class_name NativeCarCatalog', 'get_menu_cars', 'car_count', 'get_cars', 'car_selection_requested', 'bind_car_catalog', 'multi_car_0240', 'configure_car', 'switch_car', 'car_changed', 'configure_for_car', 'multi_car_audio_0240', 'photo_steering_wheel_0240', 'replaceable_per_car_0240', 'set_wheel_texture_path', 'set_steering_wheel_texture_path', '08a_car_audi_r8', '08b_car_camaro_ss', '08c_car_mercedes_560_sel', '08d_car_shelby_gt500', 'audi_r8_v10_plus', 'chevrolet_camaro_ss', 'mercedes_560_sel', '_car_customizations', '_car_stats', 'selected_car_id', '_load_car_model', '_license_plate_font_size']) {
  assert(combinedRuntime.includes(marker), `Native 0.2.40 multi-car marker is missing: ${marker}`);
}
for (const [carId, power, torque, topSpeed] of [['shelby_gt500', 365, 569, 207], ['audi_r8_v10_plus', 610, 560, 330], ['chevrolet_camaro_ss', 455, 617, 290], ['mercedes_560_sel', 300, 455, 250]]) {
  assert(carCatalogScript.includes(`"id": "${carId}"`), `Native catalogue is missing ${carId}`);
  assert(carCatalogScript.includes(`"power_hp": ${power}`) && carCatalogScript.includes(`"torque_nm": ${torque}`) && carCatalogScript.includes(`"top_speed_kmh": ${topSpeed}`), `Native catalogue spec sheet drifted for ${carId}`);
}
assert(syncScript.includes('recordedCarAudioBanks') && syncScript.includes('steering_wheel_common.png') && syncScript.includes('audi_r8_v10_plus.glb') && syncScript.includes('chevrolet_camaro_ss.glb') && syncScript.includes('mercedes_benz_560_sel.glb'), 'Native asset sync must stage all 0.2.40 car GLBs, recorded banks and the photographic steering wheel');
assert(mainScript.includes('"car_id": "audi_r8_v10_plus"') && mainScript.includes('"car_id": "chevrolet_camaro_ss"') && mainScript.includes('"car_id": "mercedes_560_sel"') && mainScript.includes('catalog_by_id.get("mercedes_560_sel"') && !mainScript.includes('"car_id": "mercedes_benz_560_sel"') && !mainScript.includes('catalog_by_id.get("mercedes_benz_560_sel"') && mainMenuScript.includes('"mercedes_560_sel":\n            path = "res://assets/ui/menu_mercedes_560_sel_gameplay.jpg"'), 'Native screenshot/menu code must use the exact catalogue car IDs, distinct from GLB filenames');
assert(audioCredits.includes('JaimeLopes') && audioCredits.includes('564373') && audioCredits.includes('637184') && audioCredits.includes('391671') && audioCredits.includes('610771') && audioCredits.includes('CC BY-SA 4.0') && mainMenuScript.includes('Altair78 (CC BY-SA 4.0)') && mainMenuScript.includes('docs/AUDIO_CREDITS.md'), 'Native 0.2.40 audio credits must preserve every supplied-car bank source and attribution/share-alike note');
// 0.2.41 supplied-car hotfix: the automatic gearbox must use road-speed
// coupled RPM (the 560 SEL first gear ends at 64.7 km/h and must not trap
// the car at 67-68), and the silver/black finishes need per-car glossy
// paint plus exact semantic handling so BlackGloss is not rebuilt as
// glass merely because its lowercase name contains "glass".
for (const marker of ['automatic_shift_0241', '_desired_automatic_gear_for_speed', 'get_automatic_gear_for_speed', '_coupled_rpm_for_gear', 'shift_speeds_kmh', 'paint_finish_0241', 'paint_metallic', 'paint_clearcoat_roughness', 'paint_flake_tint_amount', '_textured_material_override', 'paint_shader_surfaces', 'blackgloss']) {
  assert(combinedRuntime.includes(marker), `Native 0.2.41 drivetrain/paint marker is missing: ${marker}`);
}
assert(carCatalogScript.includes('"paint_roughness": 0.075') && carCatalogScript.includes('"paint_roughness": 0.065') && carCatalogScript.includes('"paint_flake_strength": 0.16') && carCatalogScript.includes('"paint_flake_strength": 0.12'), 'Native 0.2.41 must give the silver R8 and black 560 SEL smooth, fine-flake glossy factory finishes');
assert(vehicleScript.includes('lower_name == "blackgloss"') && vehicleScript.includes('lower_name == "glasswindow"') && !vehicleScript.includes('lower_name.contains("glass") or lower_name.contains("window")'), 'Native 0.2.41 must handle BlackGloss and GlassWindow as exact distinct exterior semantics');
assert(mainScript.includes('0.2.41 coupled-RPM automatic shifts') && mainScript.includes('get_automatic_gear_for_speed(speed_kmh / 3.6, 0)') && mainScript.includes('for probe_id in NativeCarCatalog.car_ids()'), 'Native 0.2.41 smoke must exercise the real automatic-gear helper for every catalogue car');
// 0.2.42 recorded-audio realism pass: dense PSOLA anchor ladders,
// log-domain crossfades, dynamic engine lowpass, exhaust crackle,
// shift clunks/downshift blips, wind/road/whine/scrape foley,
// delta-V impacts and a camera-aware listener — while engine and
// tyre voices remain real recordings (no synthesized engine tone).
for (const marker of ['audio_realism_0242', 'AudioEffectLowPassFilter', 'AudioEffectStereoEnhance', 'AudioEffectPanner', 'AudioEffectCompressor', 'play_shift', 'play_impact', 'play_thump', '_update_audio_impacts', 'set_audio_camera_mode', '_crackle_energy', 'VehicleAudio0235Engine', 'VehicleAudio0235Tires', 'VehicleAudio0235Road', 'VehicleAudio0235Events', 'exhaust', 'pop_%02d.wav', 'vehicle_foley', 'wind_loop.wav', 'whine_loop.wav']) {
  assert(combinedRuntime.includes(marker), `Native 0.2.42 audio-realism marker is missing: ${marker}`);
}
assert(audioCredits.includes('TD-PSOLA') && audioCredits.includes('0.2.42'), 'Native 0.2.42 audio credits must document the recorded-texture PSOLA anchors and foley honestly');
assert(mainMenuScript.includes('МАГАЗИН') && mainMenuScript.includes('Фейковых машин без моделей здесь нет'), 'Native 0.2.36 store must be present and explicitly limited to real in-game content');
assert(!mainMenuScript.includes('menu_shelby.jpg') && !mainMenuScript.includes('menu_richtown.jpg') && !mainMenuScript.includes('menu_garage.jpg'), 'Native 0.2.36 must not restore the retired photoreal menu renders');
assert(avatarIconScript.includes('class_name NativeAvatarIcon') && wheelPreviewScript.includes('class_name NativeWheelPreview') && lockIconScript.includes('class_name NativeLockIcon'), 'Native 0.2.36 avatar/wheel/lock vector controls are missing');
assert(!mainMenuScript.includes('COL_TEAL') && !mainMenuScript.includes('COL_MAGENTA') && !mainMenuScript.includes('COL_YELLOW'), 'Native 0.2.34 menu must not return to the rejected multi-neon palette');
// 0.2.34 map/navigation: labels are selected by zoom tier and then
// deconflicted by rectangle priority, debug district circles are
// gone, and an explicit route is solved on the road graph for the
// fullscreen map, minimap and an orange 3D road ribbon.
for (const marker of ['world_map_0234', 'zoom_label_tiers_0234', '_try_position_label', 'district_circles_removed', 'fast_travel_requested', 'minimap_points_changed', '_set_filter', 'set_first_open_hint', 'map_hint_seen', 'class_name NativeRouteGuide', 'route_guide_0234', 'AStar2D', 'get_id_path', 'RouteRibbon', 'RouteDestinationBeacon', 'road_route_0234', 'set_route_path', '_on_fast_travel_requested', 'find_nearest_road_transform']) {
  assert(combinedRuntime.includes(marker), `Native 0.2.34 map/route marker is missing: ${marker}`);
}
assert(!worldMapScript.includes('_canvas.draw_circle(centre, radius, color)'), 'Native 0.2.34 world map must not draw the removed debug district circles');
assert(syncScript.includes('menu_play_gameplay.jpg') && syncScript.includes('menu_shelby_gameplay.jpg') && syncScript.includes('menu_audi_r8_gameplay.jpg') && syncScript.includes('menu_camaro_ss_gameplay.jpg') && syncScript.includes('menu_mercedes_560_sel_gameplay.jpg') && syncScript.includes('menu_richtown_gameplay.jpg') && syncScript.includes('menu_world_gameplay.jpg') && syncScript.includes('ui_click.wav') && !syncScript.includes("menu_garage.jpg"), 'Native asset sync must stage real-gameplay menu screenshots for every car and the click sound, not retired photoreal renders');
// 0.2.35 ignition + recorded Shelby audio: the car spawns off, a
// handbrake-sized power button sits under the minimap, F/Enter also
// toggles the engine, and the old synthesized 55 Hz loop is gone.
// The continuous voice is a 16-point recorded GT500 bank in on/off
// throttle layers, with recorded Mustang idle/start/stop and tyre
// squeal on a dedicated limited bus.
for (const marker of ['class_name NativeVehicleAudio', 'class_name NativeIgnitionButton', 'recorded_audio_0235', 'recorded_gt500_bank', 'gt500_on_0900.wav', 'gt500_on_4400.wav', 'gt500_off_0900.wav', 'gt500_off_4400.wav', 'mustang_idle.wav', 'mustang_start.wav', 'mustang_stop.wav', 'tire_squeal_loop.wav', 'AudioEffectLimiter', 'VehicleAudio0235', 'ENGINE_CRANKING', 'ENGINE_STOPPING', 'toggle_engine', 'start_engine', 'stop_engine', '_ensure_action(&"ignition_toggle"', 'set_audio_suspended', 'ignition_0235', 'hud_0235', 'ignition_button_0235', 'ignition_under_minimap', 'ignition_same_size_as_drift']) {
  assert(combinedRuntime.includes(marker), `Native 0.2.35 ignition/recorded-audio marker is missing: ${marker}`);
}
assert(!vehicleScript.includes('_engine_player') && !vehicleScript.includes('AudioStreamWAV.new()') && !vehicleScript.includes('sin(phase) * 0.42'), 'Native 0.2.35 must not restore the synthesized procedural engine loop');
assert(syncScript.includes('shelbyAudioRpms') && syncScript.includes('shelbyAudioNames') && syncScript.includes('assertRealWav'), 'Native asset sync must stage and header-check the complete 0.2.35 Shelby WAV bank');
assert(audioCredits.includes('VacekH') && audioCredits.includes('205510') && audioCredits.includes('lmbubec') && audioCredits.includes('119449') && audioCredits.includes('Tom Haigh') && audioCredits.includes('CC BY 3.0') && audioCredits.includes('CC0'), 'Native 0.2.35 audio credits must preserve the CC0 provenance and the required CC BY 3.0 tyre attribution');
assert(mainMenuScript.includes('Tom Haigh (CC BY 3.0)'), 'Native 0.2.35 settings must carry the in-app CC BY 3.0 tyre-sound attribution');
for (const expectedClass of ['class_name NativeWorldBuilder', 'class_name NativeVehicle', 'class_name NativeHud', 'class_name NativeDynamicWorld', 'class_name NativeSpeedPost', 'class_name NativeArcadeCarAssist', 'class_name NativeMainMenu', 'class_name NativeSteeringWheel', 'class_name NativeWorldMap', 'class_name NativeMinimap', 'class_name NativeDashboardGauge', 'class_name NativeTouchPedal', 'class_name NativeRoundActionButton', 'class_name NativeRouteGuide', 'class_name NativeCarSilhouetteIcon', 'class_name NativeVehicleAudio', 'class_name NativeIgnitionButton', 'class_name NativeAvatarIcon', 'class_name NativeWheelPreview', 'class_name NativeLockIcon', 'class_name NativeCarCatalog']) {
  assert(combinedRuntime.includes(expectedClass), `Missing ${expectedClass}`);
}
for (const marker of [
  'PanoramaSkyMaterial',
  'user_sky_day.jpg',
  'ReflectionProbe.UPDATE_ONCE',
  'get_surface_at',
  '_pacejka',
  '_ackermann_angle',
  'GEAR_RATIOS',
  'GPUParticles3D',
  'get_visual_aabb_size',
  'PhysicalSkyMaterial',
  'GOLDEN_HOUR',
  'CLEARCOAT',
  'hint_screen_texture',
  'roll_reduced_force_point',
  'steering_limit',
  'get_drive_base_state',
  'paint_reflections_ready',
  'ReflectionProbe',
  'probe.box_projection = true',
  'reflection_probe_box_projection',
  'glow_enabled = true',
  'cinematic_contrast',
  'always_on_vignette',
  'film_grain',
  'WetAsphaltShader',
  'WaterSurfaceShader',
  'water_surface.gdshader',
  'get_water_visual_state',
  'foam_strength',
  'depth_foam',
  'FoliageWindShader',
  'CurtainWallGlassShader',
  'CurtainWallFacadeShader',
  'curtain_wall_glass.gdshader',
  'curtain_wall_facade.gdshader',
  'curtain_wall_shader',
  'curtain_wall_opaque_shader',
  'curtain_wall_materials',
  'curtain_wall_panel_variation',
  'curtain_wall_weathering',
  'curtain_wall_neutral_glass',
  'curtain_wall_calibrated_0215',
  'curtain_wall_reflective_coating_0216',
  'surface_metallic',
  'runtime_lods_0216',
  'runtime_lod_meshes',
  'runtime_lod_levels',
  'runtime_lod_min_index_ratio',
  'batched_models_merged_0216',
  'building_hlod_0216',
  'building_far_proxy_models',
  'vegetation_hlod_0216',
  'vegetation_far_proxies',
  'curtain_wall_environment_reflection_0217',
  'sky_radiance_size',
  'reflection_probe_mobile_calibration_0217',
  'ConcreteSurfaceShader',
  'concrete_surface.gdshader',
  'concrete_stochastic_0217',
  'concrete_shader_materials',
  'detailed_palms_0217',
  'detailed_palms',
  'date_palms',
  'royal_palms',
  'palm_date_triangles',
  'palm_royal_triangles',
  'palm_far_proxy_0217',
  'palm_far_proxies',
  'geometric_ground_cover_0217',
  'grass_tufts',
  'flower_clumps',
  'ornamental_shrubs',
  'ground_cover_total',
  'grass_tuft_triangles',
  'flower_clump_triangles',
  'ornamental_shrub_triangles',
  'PalmTrunk',
  'PalmCrownshaft',
  'PalmLeafDry',
  'PalmFruit',
  'GrassBladeDry',
  'OrnamentalLeaf',
  'FlowerCentre',
  'mesh_lod_threshold',
  'curtain_wall_clearcoat_removed',
  'curtain_wall_detail_fade_start_m',
  'curtain_wall_detail_fade_end_m',
  'building_visual_ranges_0215',
  'model_parts_without_shadow_pass',
  'traffic_signal_visual_range_m',
  'curtain_wall_interior_light_strength',
  'tall_reflection_probes',
  'main_glass_physical',
  'tower_glass_physical',
  'facade_glass_tower_physical',
  'facade_bronze_tower_physical',
  'interior_light_strength',
  'weathering_strength',
  'get_road_visual_state',
  'ground_winding_godot_cw',
  'user_asphalt_plain.jpg',
  'asphalt_city.jpg',
  'user_asphalt_pothole.jpg',
  'wear_tex',
  'ROAD_CROWN_M',
  '_build_road_edges',
  '_build_road_details',
  '_build_intersection_pads',
  'road_edge_lines',
  'lane_dashes',
  'center_lines',
  'raised_sidewalk_slabs',
  'concrete_curbs',
  'road_gutters',
  'manholes',
  'drainage_grates',
  'road_studs',
  'traffic_signals',
  'traffic_signal_models',
  'traffic_signal_static_red',
  'traffic_signal_short.glb',
  'traffic_signal_long.glb',
  'SignalRedOn',
  'premium_villa_models',
  'premium_villa_fixed_scale',
  'premium_villa_detail_pass',
  'premium_villa_material_pass',
  'premium_villa_site_pass',
  'premium_townhouse_models',
  'premium_townhouse_fixed_scale',
  'premium_townhouse_detail_pass',
  'premium_townhouse_material_pass',
  'premium_townhouse_site_pass',
  'TownPlaster',
  'TownStone',
  'TownTrim',
  'TownRoof',
  'TownGarage',
  'TownDoor',
  'TownDoorAccent',
  '_townhouse_model_fit',
  'premium_hero_models',
  'premium_hero_fixed_scale',
  'premium_hero_detail_pass',
  'premium_hero_material_pass',
  'premium_hero_site_pass',
  'HeroPlaster',
  'HeroStone',
  'HeroTrim',
  'HeroWood',
  'HeroMetal',
  '_hero_model_fit',
  '_hero_exported_position',
  'premium_glass_models',
  'premium_glass_fixed_scale',
  'premium_glass_detail_pass',
  'premium_glass_material_pass',
  'premium_glass_site_pass',
  'premium_main_tower_built',
  'premium_main_tower_fixed_scale',
  'premium_main_tower_detail_pass',
  'premium_main_tower_material_pass',
  'premium_main_tower_site_pass',
  'MainGlass',
  'MainSpandrel',
  'MainStone',
  'MainTrim',
  'MainMetal',
  'MainWater',
  'TowerGlass',
  'TowerSpandrel',
  'TowerStone',
  'TowerTrim',
  'TowerMetal',
  '_glass_model_fit',
  'main_tower.glb',
  'VillaPlaster',
  'VillaStone',
  'VillaLimestone',
  'VillaGranite',
  'VillaWood',
  'VillaGlass',
  'VillaInterior',
  'VillaCurtain',
  'VillaPavement',
  'VillaDeck',
  'VillaMulch',
  'VillaLawn',
  'VillaHedge',
  'user_stone_tiles_beige.jpg',
  'user_black_granite.jpg',
  'user_mulch_soil.jpg',
  'hedge.jpg',
  'FacadeStone',
  'WindowGlassDark',
  'BACKLIGHT',
  'ALPHA_SCISSOR_THRESHOLD',
  'visibility_range_end',
  'shadow_max_distance',
  'reflection_probe_max_distance',
  'MULTIMESH_CHUNK_SIZE_M',
  'ROAD_GRID_CELL_M',
  '_configure_render_quality',
  'Viewport.SCALING_3D_MODE_BILINEAR',
  'Viewport.MSAA_DISABLED',
  'Viewport.SCREEN_SPACE_AA_FXAA',
  'lod_bias',
  'SHADOW_PARALLEL_2_SPLITS',
  '_build_infill_buildings',
  '_build_city_details',
  '_build_premium_boulevard_details',
  'func _make_paving_patch_mesh',
  'in_promenade',
  'dubai_premium_cafe.glb',
  'CafeTravertine',
  'CafeGlass',
  'CafeBronze',
  'DubaiPremiumCafes',
  'dubai_premium_cafe_model',
  'dubai_premium_cafe_triangles',
  'dubai_premium_cafe_pbr_0219',
  'premium_boulevard_paving',
  'boulevard_cafes',
  'boulevard_spawn_cafes',
  'boulevard_palm_planters',
  'boulevard_lawn_islands',
  'WashingtoniaWhiteGravelBeds',
  'CafeWarmLight',
  'CafeFabric',
  'cafe_linen_normal.png',
  'premium_boulevard_promenade_m2',
  'PremiumStonePavingShader',
  'premium_stone_paving.gdshader',
  'premium_stone_paving_shader_0218',
  'boulevard_rebuild_0218',
  'boulevard_reference_0219',
  'boulevard_dark_asphalt_0219',
  'boulevard_granite_curbs',
  'boulevard_premium_sidewalk_slabs',
  'boulevard_fresh_markings',
  'boulevard_yellow_edge_lines',
  'BoulevardYellowEdgeLines',
  'boulevard_arcades',
  'boulevard_cafe_tables',
  'boulevard_cafe_umbrellas',
  'boulevard_drip_emitters',
  'boulevard_date_palms',
  'boulevard_extra_date_palms',
  'boulevard_lawn_area_m2',
  'boulevard_topiary',
  'boulevard_continuous_hedges',
  'boulevard_modern_lamps',
  'BoulevardStreetLampPoles',
  'boulevard_stone_benches',
  'BoulevardStoneBenches',
  'boulevard_pool_decks',
  'BoulevardPoolDecks',
  'boulevard_marina_deck_segments',
  'BoulevardMarinaPromenadeDeck',
  'boulevard_frontage_infill',
  'boulevard_ground_cover',
  'PremiumPromenade_ScreenshotAxis',
  'BoulevardGraniteCurbs',
  'BoulevardPremiumSidewalkSlabs',
  'BoulevardLooseWhitePebbles',
  'infill_buildings',
  'city_detail_props',
  'get_smoothing_state',
  '_throttle_command',
  '_smoothed_drive_force_per_wheel',
  '_shift_torque_blend',
  'anti_roll_requires_both_wheels',
  '_camera_follow_yaw',
  '_render_quality_vote_count',
]) {
  assert(combinedRuntime.includes(marker), `Native 0.2.19 marker is missing: ${marker}`);
}

for (const [relative, minimumSize] of [['src/assets/ui/menu_play_gameplay.jpg', 100_000], ['src/assets/ui/menu_shelby_gameplay.jpg', 100_000], ['src/assets/ui/menu_audi_r8_gameplay.jpg', 40_000], ['src/assets/ui/menu_camaro_ss_gameplay.jpg', 40_000], ['src/assets/ui/menu_mercedes_560_sel_gameplay.jpg', 40_000], ['src/assets/ui/menu_richtown_gameplay.jpg', 100_000], ['src/assets/ui/menu_world_gameplay.jpg', 100_000], ['src/assets/ui/boot_splash_richtown.jpg', 150_000], ['src/assets/audio/ui_click.wav', 1_000]]) {
  const info = await stat(relative);
  assert(info.size > minimumSize, `Native 0.2.36 canonical UI asset is unexpectedly small: ${relative}`);
  if (relative.endsWith('.jpg')) {
    const bytes = await readFile(relative);
    assert(bytes[0] === 0xff && bytes[1] === 0xd8 && (bytes.includes(Buffer.from([0xff, 0xc0])) || bytes.includes(Buffer.from([0xff, 0xc2]))), `${relative} is not a JPEG gameplay screenshot`);
  }
}

const data = JSON.parse(dataText);
assert(data.schemaVersion === 1, 'Unexpected native world schema');
assert(data.units === 'metres', 'Native world must use real metres');
assert(data.terrain.heights.length === data.terrain.cols * data.terrain.rows, 'Terrain height count mismatch');
assert(data.layout === 'richtown7', 'RichTown must ship the 0.3.0 7x7 km layout');
assert(data.bounds.minX === -3500 && data.bounds.maxX === 3500 && data.bounds.minZ === -3500 && data.bounds.maxZ === 3500, 'RichTown 7x7 bounds changed unexpectedly');
assert(data.terrain.cols === 501 && data.terrain.rows === 501 && data.terrain.stepM === 14, 'RichTown 7x7 terrain grid must stay 501x501 at 14 m');
assert(data.roads.length >= 300, 'Too few RichTown 7x7 road edges exported');
assert(data.stats.roadLengthKm >= 110, 'RichTown 7x7 road network must exceed 110 km');
assert(data.roads.filter((r) => r.id.startsWith('rt7-hwy')).length >= 10 && data.roads.some((r) => r.id === 'rt7-plaza-ring'), 'RichTown 7x7 big ring + plaza ring roads are missing');
assert(data.roads.filter((r) => r.id.includes('bridge')).length >= 6, 'RichTown 7x7 must export six canal bridges (incl. the Corniche mouth)');
assert(data.districts.some((d) => d.id === 'downtown') && data.districts.some((d) => d.id === 'rich-hills') && data.districts.some((d) => d.id === 'port'), 'RichTown 7x7 district metadata is missing');
assert(data.buildings.length >= 400, 'Too few RichTown 7x7 buildings exported');
assert(data.buildings.filter((b) => b.model === 'villa').length >= 14, 'Expected at least 14 Blender villas');
assert(data.buildings.filter((b) => b.model === 'glass_tower').length >= 8, 'Expected at least 8 Blender glass towers');
assert(data.landmarks.length >= 20, 'Expected at least 20 RichTown 7x7 landmarks');
const richTower = data.landmarks.find((landmark) => landmark.kind === 'rt-tower');
assert(richTower && richTower.x === 0 && richTower.z === 0 && richTower.h === 148, 'Rich Tower must anchor the 7x7 centre at 148 m');
assert(data.landmarks.some((l) => l.kind === 'rt7-stadium') && data.landmarks.some((l) => l.kind === 'rt7-cable-bridge'), 'RichTown 7x7 stadium/cable-bridge landmarks are missing');
assert(data.palms.length >= 900, 'Expected at least 900 RichTown 7x7 palms');
assert(data.buildings.length >= 1400, 'RichTown 0.3.1 densification must export at least 1400 buildings');
assert(data.landmarks.length >= 70, 'RichTown 0.3.1 must export at least 70 landmarks');
for (const kind of ['rt7-terminal', 'rt7-atc', 'rt7-plane', 'rt7-cooling', 'rt7-reactor', 'rt7-chimney', 'rt7-radar', 'rt7-watchtower', 'rt7-helipad', 'rt7-afv', 'rt7-hangar', 'rt7-tank']) {
  assert(data.landmarks.some((l) => l.kind === kind), `RichTown 0.3.1 landmark kind is missing: ${kind}`);
}
assert(data.landmarks.filter((l) => l.kind === 'rt7-school').length >= 10, 'RichTown 0.3.1 needs one school per residential district (10)');
assert(data.roads.some((r) => r.id.startsWith('rt7-runway')), 'RichTown 0.3.1 airport runway roads are missing');
const cityModelSet032 = new Set(['office_tower_low', 'office_tower_mid', 'office_tower_high', 'midrise_a', 'midrise_b', 'warehouse_large', 'warehouse_small', 'container_red', 'container_blue', 'villa_b', 'townhouse_b', 'barn', 'greenhouse']);
assert(data.buildings.filter((b) => cityModelSet032.has(b.model)).length >= 700, 'RichTown 0.3.2 must place at least 700 fixed-scale Blender city archetypes');
assert(data.stats.cityBlenderBuildings >= 700, 'RichTown 0.3.2 stats must count the Blender city archetypes');
assert(data.landmarks.filter((l) => l.kind === 'rt7-crane').length >= 3, 'RichTown 0.3.2 needs three port cranes on the canal quay');
assert(data.spawn.x === 5 && data.spawn.z === 640, 'Unexpected RichTown 7x7 spawn point');

const detailedCafeInfo = await stat('src/assets/models/props/dubai_premium_cafe.glb');
assert(detailedCafeInfo.size > 2_500_000, 'Native 0.2.19 must use the detailed 2.86 MB PR #61 Dubai Premium Cafe, not the earlier lightweight GLB');
const operaInfo = await stat('src/assets/models/props/opera_house.glb');
assert(operaInfo.size > 250_000, 'Native 0.2.20 RichTown Opera GLB is unexpectedly small');
const operaBytes = await readFile('src/assets/models/props/opera_house.glb');
assert(operaBytes.subarray(0, 4).toString('utf8') === 'glTF', 'RichTown Opera source is an LFS pointer or corrupt GLB');
const operaLandmark = data.landmarks.find((landmark) => landmark.kind === 'rt-opera');
assert(operaLandmark && operaLandmark.x === -700 && operaLandmark.z === 500 && operaLandmark.h === 22, 'RichTown Opera landmark must stay at X-700 Z500 with the authored 22 m height');
const mosqueInfo = await stat('src/assets/models/props/mosque.glb');
assert(mosqueInfo.size > 1_000_000, 'Native 0.2.25 RichTown Mosque GLB is unexpectedly small');
const mosqueBytes = await readFile('src/assets/models/props/mosque.glb');
assert(mosqueBytes.subarray(0, 4).toString('utf8') === 'glTF', 'RichTown Mosque source is an LFS pointer or corrupt GLB');
const mosqueLandmark = data.landmarks.find((landmark) => landmark.kind === 'rt-mosque');
assert(mosqueLandmark && mosqueLandmark.x === 950 && mosqueLandmark.z === 1365 && mosqueLandmark.h === 30, 'RichTown Mosque landmark must stay at X950 Z1365 with the authored 30 m height');
const hotelInfo = await stat('src/assets/models/props/grand_hotel.glb');
assert(hotelInfo.size > 1_000_000, 'Native 0.2.26 Grand Hotel GLB is unexpectedly small');
const hotelBytes = await readFile('src/assets/models/props/grand_hotel.glb');
assert(hotelBytes.subarray(0, 4).toString('utf8') === 'glTF', 'Grand Hotel source is an LFS pointer or corrupt GLB');
const grandHotelParcels = data.buildings.filter((b) => b.kind === 'rt-hotel' && b.h > 38 && b.w >= 33 && b.w <= 36 && b.d >= 25 && b.d <= 28);
assert(grandHotelParcels.length === 3 && grandHotelParcels.every((b) => b.x === -2450), 'Building Model No.8 must land on exactly the three tall 34x26 Corniche parcels at X-2450');
const museumInfo = await stat('src/assets/models/props/museum.glb');
assert(museumInfo.size > 1_000_000, 'Native 0.2.29 Museum GLB is unexpectedly small');
const museumBytes = await readFile('src/assets/models/props/museum.glb');
assert(museumBytes.subarray(0, 4).toString('utf8') === 'glTF', 'Museum source is an LFS pointer or corrupt GLB');
const museumLandmark = data.landmarks.find((landmark) => landmark.kind === 'rt-museum');
assert(museumLandmark && museumLandmark.x === 500 && museumLandmark.z === -700, 'RichTown Museum landmark must stay at X500 Z-700');
for (const cottageModel of ['cottage_dune.glb', 'cottage_courtyard.glb', 'cottage_palm.glb']) {
  const cottageSource = `src/assets/models/props/${cottageModel}`;
  const cottageInfo = await stat(cottageSource);
  const cottageBytes = await readFile(cottageSource);
  // 0.3.4 merged-by-material exports and the 0.3.8 panel/bevel pass legitimately shrink these GLBs; the floor still rejects LFS pointers/truncation.
  assert(cottageInfo.size > 500_000, `Native 0.2.39 ${cottageModel} GLB is unexpectedly small`);
  assert(cottageBytes.subarray(0, 4).toString('utf8') === 'glTF', `${cottageModel} source is an LFS pointer or corrupt GLB`);
}
for (const cottageTextureStem of ['cottage_basalt', 'cottage_limestone_blocks', 'cottage_paving', 'cottage_rammed_sand', 'cottage_roof_metal', 'cottage_teak_weathered', 'cottage_travertine_coarse']) {
  for (const cottageTextureSuffix of ['', '_normal', '_roughness']) {
    const cottageTexture = `src/assets/textures/realworld/${cottageTextureStem}${cottageTextureSuffix}.jpg`;
    const cottageTextureInfo = await stat(cottageTexture);
    assert(cottageTextureInfo.size > 10_000, `${cottageTexture} is unexpectedly small`);
  }
}

const shelbyAudioRpms = [900, 1100, 1300, 1500, 1700, 1900, 2100, 2350, 2600, 2850, 3100, 3350, 3600, 3850, 4100, 4400, 5000, 5600];
const shelbyAudioFiles = [
  ...shelbyAudioRpms.flatMap((rpm) => [
    `gt500_on_${String(rpm).padStart(4, '0')}.wav`,
    `gt500_off_${String(rpm).padStart(4, '0')}.wav`,
  ]),
  'mustang_idle.wav',
  'mustang_start.wav',
  'mustang_stop.wav',
  'tire_squeal_loop.wav',
];
assert(shelbyAudioFiles.length === 40, 'Native 0.2.42 must ship 36 GT500 loops (incl. PSOLA 5000/5600) plus idle/start/stop/tyre recordings');
for (const name of shelbyAudioFiles) {
  const source = `src/assets/audio/shelby/${name}`;
  const info = await stat(source);
  const bytes = await readFile(source);
  const minimumSize = /_(5000|5600)\.wav$/.test(name) ? 15_000 : 40_000;
  assert(info.size > minimumSize, `${source} is unexpectedly small`);
  assert(bytes.subarray(0, 4).toString('utf8') === 'RIFF' && bytes.subarray(8, 12).toString('utf8') === 'WAVE', `${source} is not a real WAV`);
  assert(bytes.readUInt16LE(22) === 1 && bytes.readUInt32LE(24) === 32000 && bytes.readUInt16LE(34) === 16, `${source} must stay mono 32 kHz/16-bit for the mobile audio bank`);
}
const shelbyManifest = JSON.parse(await readFile('src/assets/audio/shelby/bank_manifest.json', 'utf8'));
assert(shelbyManifest.sample_rate === 32000 && shelbyManifest.channels === 1 && shelbyManifest.engine_loops.length === 36, 'Native 0.2.42 Shelby bank manifest must describe all 36 mono engine loops');
assert(shelbyManifest.engine_loops.filter((loop) => loop.derivation).length === 4, 'Shelby 5000/5600 PSOLA derivatives must stay honestly documented in the manifest');

const suppliedCarAudioBanks = {
  audi_r8: [1231, 1602, 2400, 3735, 5200, 6800],
  camaro_ss: [635, 1050, 1444, 2265, 2900, 3747, 5000, 6478],
  mercedes_560_sel: [805, 999, 1444, 2265, 2900, 3747, 5000],
};
const suppliedCarAudioFiles = Object.entries(suppliedCarAudioBanks).flatMap(([bank, rpms]) => [
  ...rpms.flatMap((rpm) => [
    `${bank}/engine_on_${String(rpm).padStart(4, '0')}.wav`,
    `${bank}/engine_off_${String(rpm).padStart(4, '0')}.wav`,
  ]),
  `${bank}/engine_idle.wav`,
  `${bank}/engine_start.wav`,
  `${bank}/engine_stop.wav`,
]);
assert(suppliedCarAudioFiles.length === 51, 'Native 0.2.42 must ship 42 supplied-car loops plus idle/start/stop for all three banks');
for (const [bank, rpms] of Object.entries(suppliedCarAudioBanks)) {
  const manifest = JSON.parse(await readFile(`src/assets/audio/${bank}/bank_manifest.json`, 'utf8'));
  assert(manifest.bank === bank && manifest.format === 'mono WAV 32000 Hz 16-bit' && manifest.anchors.length === rpms.length, `${bank} audio manifest does not describe its complete mono bank`);
  assert(manifest.anchors.every((anchor, index) => anchor.rpm === rpms[index] && anchor.on.sample_rate === 32000 && anchor.off.sample_rate === 32000 && anchor.on.channels === 1 && anchor.off.channels === 1 && anchor.source_recording && anchor.author && anchor.license && anchor.url), `${bank} audio manifest is missing per-anchor provenance`);
}
for (const name of suppliedCarAudioFiles) {
  const source = `src/assets/audio/${name}`;
  const info = await stat(source);
  const bytes = await readFile(source);
  assert(info.size > 15_000, `${source} is unexpectedly small`);
  assert(bytes.subarray(0, 4).toString('utf8') === 'RIFF' && bytes.subarray(8, 12).toString('utf8') === 'WAVE', `${source} is not a real WAV`);
  assert(bytes.readUInt16LE(22) === 1 && bytes.readUInt32LE(24) === 32000 && bytes.readUInt16LE(34) === 16, `${source} must stay mono 32 kHz/16-bit`);
}

// 0.2.42: every bank also ships ten exhaust-pop one-shots sliced
// from its own recorded loops, plus a small secondary foley set
// (wind/road/impact/whine/scrape) layered under the recorded
// engine and tyre voices.
const popBanks = ['shelby', 'audi_r8', 'camaro_ss', 'mercedes_560_sel'];
for (const bank of popBanks) {
  for (let i = 1; i <= 10; i += 1) {
    const source = `src/assets/audio/${bank}/pop_${String(i).padStart(2, '0')}.wav`;
    const info = await stat(source);
    const bytes = await readFile(source);
    assert(info.size > 2_500, `${source} is unexpectedly small`);
    assert(bytes.subarray(0, 4).toString('utf8') === 'RIFF' && bytes.subarray(8, 12).toString('utf8') === 'WAVE', `${source} is not a real WAV`);
    assert(bytes.readUInt16LE(22) === 1 && bytes.readUInt32LE(24) === 32000 && bytes.readUInt16LE(34) === 16, `${source} must stay mono 32 kHz/16-bit`);
  }
}
const foleyAudioFiles = [
  'wind_loop.wav', 'road_asphalt.wav', 'road_sidewalk.wav', 'road_grass.wav',
  'road_sand.wav', 'whine_loop.wav', 'impact_soft.wav', 'impact_med.wav',
  'impact_hard.wav', 'suspension_thump.wav', 'shift_clunk.wav', 'scrape_loop.wav',
  'foliage_rustle.wav',
];
for (const name of foleyAudioFiles) {
  const source = `src/assets/audio/vehicle_foley/${name}`;
  const info = await stat(source);
  const bytes = await readFile(source);
  assert(info.size > 4_000, `${source} is unexpectedly small`);
  assert(bytes.subarray(0, 4).toString('utf8') === 'RIFF' && bytes.subarray(8, 12).toString('utf8') === 'WAVE', `${source} is not a real WAV`);
  const expectedChannels = (name === 'wind_loop.wav' || name === 'foliage_rustle.wav') ? 2 : 1;
  assert(bytes.readUInt16LE(22) === expectedChannels && bytes.readUInt32LE(24) === 32000 && bytes.readUInt16LE(34) === 16, `${source} must stay 32 kHz/16-bit (${expectedChannels}ch)`);
}

const steeringWheelBytes = await readFile('src/assets/ui/steering_wheel_common.png');
assert(steeringWheelBytes.length > 500_000 && steeringWheelBytes.readUInt32BE(16) === 1024 && steeringWheelBytes.readUInt32BE(20) === 1024 && steeringWheelBytes[25] === 6, 'Native 0.2.40 photographic steering wheel must be a 1024x1024 RGBA PNG');
assert([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].every((value, index) => steeringWheelBytes[index] === value), 'Native steering-wheel PNG signature is invalid');

const suppliedCars = [
  { stem: 'audi_r8_v10_plus', minimumBytes: 5_000_000, size: [1.966872, 1.200647, 4.426], materials: ['Paint', 'GlassWindow', 'Headlight', 'TailLight', 'RimMetal', 'TireRubber'] },
  { stem: 'chevrolet_camaro_ss', minimumBytes: 3_500_000, size: [2.037753, 1.346721, 4.790135], materials: ['Paint', 'GlassWindow', 'LiveryTexture', 'TireRimTexture'] },
  { stem: 'mercedes_benz_560_sel', minimumBytes: 5_000_000, size: [1.955433, 1.559742, 5.16], materials: ['Paint', 'PaintSecondary', 'GlassWindow', 'Headlight', 'TailLight', 'RimMetal', 'TireTreadTexture'] },
];
for (const car of suppliedCars) {
  const source = `src/assets/models/cars/${car.stem}.glb`;
  const info = await stat(source);
  const bytes = await readFile(source);
  const gltf = parseGlbJson(bytes);
  const report = JSON.parse(await readFile(`src/assets/models/cars/${car.stem}_report.json`, 'utf8'));
  const nodeNames = new Set((gltf.nodes ?? []).map((node) => node.name));
  const materialNames = new Set((gltf.materials ?? []).map((material) => material.name));
  assert(info.size > car.minimumBytes && report.outputBytes === info.size, `${source} byte size does not match its conversion report`);
  assert(report.boundsGltfSizeXYZ.every((value, index) => Math.abs(value - car.size[index]) < 0.02), `${source} real-scale bounds drifted`);
  for (const nodeName of ['Body', 'Wheel_FL', 'Wheel_FR', 'Wheel_RL', 'Wheel_RR', 'Wheel_FL_Spin', 'Wheel_FR_Spin', 'Wheel_RL_Spin', 'Wheel_RR_Spin']) {
    assert(nodeNames.has(nodeName), `${source} is missing runtime node ${nodeName}`);
  }
  for (const materialName of car.materials) {
    assert(materialNames.has(materialName), `${source} is missing semantic material ${materialName}`);
  }
}

if (requireAssets) {
  const required = [
    'assets/vehicles/mustang.glb',
    'assets/vehicles/audi_r8_v10_plus.glb',
    'assets/vehicles/chevrolet_camaro_ss.glb',
    'assets/vehicles/mercedes_benz_560_sel.glb',
    'assets/buildings/villa.glb',
    'assets/buildings/glass_tower.glb',
    'assets/buildings/main_tower.glb',
    'assets/buildings/hero_building.glb',
    'assets/buildings/townhouse.glb',
    'assets/buildings/opera_house.glb',
    'assets/buildings/mosque.glb',
    'assets/buildings/grand_hotel.glb',
    'assets/buildings/museum.glb',
    'assets/buildings/cottage_dune.glb',
    'assets/buildings/cottage_courtyard.glb',
    'assets/buildings/cottage_palm.glb',
    'assets/props/street_lamp.glb',
    'assets/props/bus_shelter.glb',
    'assets/props/park_bench.glb',
    'assets/props/park_pergola.glb',
    'assets/props/traffic_signal_short.glb',
    'assets/props/traffic_signal_long.glb',
    'assets/props/dubai_premium_cafe.glb',
    'assets/props/school.glb',
    'assets/props/airport_terminal.glb',
    'assets/props/atc_tower.glb',
    'assets/props/hangar_large.glb',
    'assets/props/hangar_small.glb',
    'assets/props/airliner.glb',
    'assets/props/cooling_tower.glb',
    'assets/props/reactor.glb',
    'assets/props/chimney.glb',
    'assets/props/radar_station.glb',
    'assets/props/watchtower.glb',
    'assets/props/storage_tank.glb',
    'assets/props/silo.glb',
    'assets/props/afv.glb',
    'assets/props/stadium.glb',
    'assets/props/office_tower_low.glb',
    'assets/props/office_tower_mid.glb',
    'assets/props/office_tower_high.glb',
    'assets/props/midrise_a.glb',
    'assets/props/midrise_b.glb',
    'assets/props/warehouse_large.glb',
    'assets/props/warehouse_small.glb',
    'assets/props/container_red.glb',
    'assets/props/container_blue.glb',
    'assets/props/villa_b.glb',
    'assets/props/townhouse_b.glb',
    'assets/props/barn.glb',
    'assets/props/greenhouse.glb',
    'assets/props/port_crane.glb',
    'assets/props/barge.glb',
    'assets/props/bleacher.glb',
    'assets/vegetation/plants.glb',
    'assets/vegetation/palm_date.glb',
    'assets/vegetation/palm_royal.glb',
    'assets/vegetation/grass_tuft.glb',
    'assets/vegetation/flower_clump.glb',
    'assets/vegetation/ornamental_shrub.glb',
    'assets/textures/user_asphalt_dashed.jpg',
    'assets/textures/user_asphalt_plain.jpg',
    'assets/textures/user_asphalt_plain_normal.jpg',
    'assets/textures/asphalt_city.jpg',
    'assets/textures/user_asphalt_pothole.jpg',
    'assets/textures/user_asphalt_pothole_normal.jpg',
    'assets/textures/user_water_turquoise.jpg',
    'assets/textures/user_travertine.jpg',
    'assets/textures/user_travertine_normal.jpg',
    'assets/textures/user_stone_tiles_beige.jpg',
    'assets/textures/user_black_granite.jpg',
    'assets/textures/user_black_granite_normal.jpg',
    'assets/textures/user_brushed_metal.jpg',
    'assets/textures/user_brushed_metal_normal.jpg',
    'assets/textures/user_brushed_metal_seamless.jpg',
    'assets/textures/user_brushed_metal_seamless_normal.jpg',
    'assets/textures/user_mulch_soil.jpg',
    'assets/textures/hedge.jpg',
    'assets/textures/user_sky_day.jpg',
    'assets/textures/user_sky_sunset.jpg',
    'assets/textures/user_sky_night.jpg',
    'assets/textures/cafe_linen.jpg',
    'assets/textures/cafe_linen_normal.png',
    ...['cottage_basalt', 'cottage_limestone_blocks', 'cottage_paving', 'cottage_rammed_sand', 'cottage_roof_metal', 'cottage_teak_weathered', 'cottage_travertine_coarse'].flatMap((stem) => ['', '_normal', '_roughness'].map((suffix) => `assets/textures/${stem}${suffix}.jpg`)),
    'assets/ui/menu_play_gameplay.jpg',
    'assets/ui/menu_shelby_gameplay.jpg',
    'assets/ui/menu_audi_r8_gameplay.jpg',
    'assets/ui/menu_camaro_ss_gameplay.jpg',
    'assets/ui/menu_mercedes_560_sel_gameplay.jpg',
    'assets/ui/menu_richtown_gameplay.jpg',
    'assets/ui/menu_world_gameplay.jpg',
    'assets/ui/boot_splash_richtown.jpg',
    'assets/ui/steering_wheel_common.png',
    'assets/audio/ui_click.wav',
    ...shelbyAudioFiles.map((name) => `assets/audio/shelby/${name}`),
    ...suppliedCarAudioFiles.map((name) => `assets/audio/${name}`),
  ];
  for (const relative of required) {
    const file = path.join(root, relative);
    const info = await stat(file);
    assert(info.size > 1000, `${file} is unexpectedly small`);
    if (file.endsWith('.glb')) {
      const bytes = await readFile(file);
      assert(bytes.subarray(0, 4).toString('utf8') === 'glTF', `${file} is an LFS pointer or corrupt GLB`);
    }
    if (file.endsWith('.wav')) {
      const bytes = await readFile(file);
      assert(bytes.subarray(0, 4).toString('utf8') === 'RIFF' && bytes.subarray(8, 12).toString('utf8') === 'WAVE', `${file} is not a real WAV`);
    }
  }
}

// 0.2.47 second world: the generated Desert data set and the runtime
// world-switch wiring (menu signal -> main.switch_world -> builder).
const desertData = JSON.parse(desertDataText);
assert(desertData.bounds.maxX === 4000 && desertData.bounds.maxZ === 4000, 'Desert bounds must cover the full 4x4 km basin');
assert(desertData.terrain.heights.length === 251001, 'Desert terrain must ship the full 501x501 height grid');
assert(desertData.terrain.heights.every((v) => v > 0), 'Desert heights must not contain cumulative-carve trenches below zero');
assert(desertData.desert.guardrails.length >= 180, 'Desert cliff-edge guardrails are incomplete');
assert(desertData.stats.roadLengthKm >= 55, 'Desert road network must meet the 55 km spec floor');
assert(desertData.roads.length >= 40, 'Desert road list is incomplete');
assert(desertData.desert.structures.length >= 700, 'Desert structures are incomplete');
// 0.2.51: no fence or guardrail may sit on the carriageway.
// Baseline before the fix: 12/72 fences and 21/209 rails on-road.
const roadSegs = [];
for (const road of desertData.roads) {
  const pts = road.samples.map((sm) => [sm[0], sm[2]]);
  if (road.closed && pts.length) pts.push(pts[0]);
  for (let i = 0; i + 1 < pts.length; i++) roadSegs.push([pts[i], pts[i + 1], road.widthM * 0.5]);
}
function edgeClearance(points) {
  let best = Infinity;
  for (const [px, pz] of points) {
    for (const [[ax, az], [bx, bz], hw] of roadSegs) {
      const abx = bx - ax, abz = bz - az;
      const l2 = Math.max(abx * abx + abz * abz, 1e-9);
      let t = ((px - ax) * abx + (pz - az) * abz) / l2;
      t = Math.min(1, Math.max(0, t));
      const dx = px - (ax + abx * t), dz2 = pz - (az + abz * t);
      best = Math.min(best, Math.hypot(dx, dz2) - hw);
    }
  }
  return best;
}
let fenceCount = 0;
let worstFence = Infinity;
for (const st of desertData.desert.structures) {
  if (st.kind !== 'fence') continue;
  fenceCount += 1;
  const dx = Math.cos(st.yaw), dz = -Math.sin(st.yaw);
  const pts = [];
  const n = Math.max(2, Math.round(st.w / 0.5));
  for (let i = 0; i <= n; i++) {
    const t = -st.w / 2 + (st.w * i) / n;
    pts.push([st.x + dx * t, st.z + dz * t]);
  }
  worstFence = Math.min(worstFence, edgeClearance(pts));
}
assert(fenceCount >= 85, `Desert fences are incomplete: ${fenceCount}`);
assert(worstFence >= 1.2, `Desert fence sits on a road (edge clearance ${worstFence})`);
let worstRail = Infinity;
for (const g of desertData.desert.guardrails) {
  const pts = [];
  const n = Math.max(2, Math.round(Math.hypot(g[2] - g[0], g[3] - g[1])));
  for (let i = 0; i <= n; i++) pts.push([g[0] + ((g[2] - g[0]) * i) / n, g[1] + ((g[3] - g[1]) * i) / n]);
  worstRail = Math.min(worstRail, edgeClearance(pts));
}
assert(worstRail >= 0.5, `Desert guardrail sits on a road (edge clearance ${worstRail})`);
const desertScatterTotal = Object.values(desertData.desert.scatter).reduce((sum, items) => sum + items.length, 0);
assert(desertScatterTotal >= 37000, 'Desert scatter is below the authored budget');
// 0.2.53 screenshot audit: scatter used centreline-distance raster
// thresholds below road half-widths, so rocks/shrubs/cacti legally
// spawned on carriageways.  Grid-accelerated exact check: no scatter
// centre may remain on a carriageway.
const segGrid0253 = new Map();
const SEG_CELL_0253 = 100;
roadSegs.forEach((seg, idx) => {
  const [[ax, az], [bx, bz], hw] = seg;
  const pad = hw + 40;
  const x0 = Math.floor((Math.min(ax, bx) - pad) / SEG_CELL_0253);
  const x1 = Math.floor((Math.max(ax, bx) + pad) / SEG_CELL_0253);
  const z0 = Math.floor((Math.min(az, bz) - pad) / SEG_CELL_0253);
  const z1 = Math.floor((Math.max(az, bz) + pad) / SEG_CELL_0253);
  for (let cx = x0; cx <= x1; cx++) for (let cz = z0; cz <= z1; cz++) {
    const key = `${cx},${cz}`;
    if (!segGrid0253.has(key)) segGrid0253.set(key, []);
    segGrid0253.get(key).push(idx);
  }
});
function fastEdgeClearance0253(px, pz) {
  const key = `${Math.floor(px / SEG_CELL_0253)},${Math.floor(pz / SEG_CELL_0253)}`;
  const cand = segGrid0253.get(key) ?? [];
  let best = Infinity;
  for (const idx of cand) {
    const [[ax, az], [bx, bz], hw] = roadSegs[idx];
    const abx = bx - ax, abz = bz - az;
    const l2 = Math.max(abx * abx + abz * abz, 1e-9);
    let t = ((px - ax) * abx + (pz - az) * abz) / l2;
    t = Math.min(1, Math.max(0, t));
    best = Math.min(best, Math.hypot(px - (ax + abx * t), pz - (az + abz * t)) - hw);
  }
  return best;
}
let scatterOnRoad0253 = 0;
for (const items of Object.values(desertData.desert.scatter)) {
  for (const it of items) if (fastEdgeClearance0253(it[0], it[1]) < 0) scatterOnRoad0253 += 1;
}
assert(scatterOnRoad0253 === 0, `Desert scatter instances on carriageways after the 0.2.53 audit: ${scatterOnRoad0253}`);
const lake0253 = desertData.desert.lake;
const oasisRoad0253 = desertData.roads.find((r) => r.id === 'dz-oasis_road');
assert(oasisRoad0253, 'Desert oasis road is missing');
const oasisNearLake0253 = oasisRoad0253.samples.filter((sm) => Math.hypot(sm[0] - lake0253.x, sm[2] - lake0253.z) < 95);
assert(oasisNearLake0253.length >= 8 && Math.min(...oasisNearLake0253.map((sm) => sm[1])) > lake0253.y + 0.1, 'Oasis road deck must stay above lake level across the bridge span (0.2.53)');
const wreckCluster0253 = desertData.desert.structures.filter((st) => st.kind === 'car_wreck' && Math.abs(st.z - 2050) < 0.11 && st.x > 1000 && st.x < 1350).length;
assert(wreckCluster0253 <= 2, `Town Main car-wreck sampler cluster regressed (0.2.53): ${wreckCluster0253}`);
assert(desertData.desert.game.fastTravel.length === 8 && desertData.desert.game.photoSpots.length === 10, 'Desert game markers are incomplete');
assert(desertData.spawn.x > 0 && desertData.spawn.x < 4000 && desertData.spawn.z > 0 && desertData.spawn.z < 4000, 'Desert spawn must be inside the basin');
for (const marker of ['DESERT_DATA_PATH', '_build_desert_world', 'desert_world_0247', '_build_desert_scatter', '_dz_animate', '_add_pitched_box_collider', 'desert_road_deck_colliders', 'desert_smooth_roads_0249', 'desert_detail_0250', '_dz_saguaro_mesh', 'dz_cactus_skin.jpg', 'dz_packed_earth_roughness.jpg', 'dz_trail_gravel_roughness.jpg', 'desert_fences_0251']) {
  assert(worldScript.includes(marker), `0.2.47 desert builder marker is missing: ${marker}`);
}
for (const marker of ['desert_screenshot_audit_0253', 'desert_rock_triplanar_0253', 'desert_scatter_road_audit_0253', 'desert_oasis_deck_0253', 'desert_pipe_road_gaps_0253', 'desert_race_rings_subtle_0253', 'desert_lake_calm_0253', 'dz_wreck_blue', 'minimap_contrast_0253', 'static_cache_always_until_ready_0253', 'route_beacon_subtle_0253']) {
  assert(combinedRuntime.includes(marker), `0.2.53 screenshot-audit marker is missing: ${marker}`);
}
assert(minimapScript.includes('SubViewport.UPDATE_ALWAYS') && minimapScript.includes('SubViewport.UPDATE_DISABLED'), '0.2.53 minimap static cache must render continuously until ready, then freeze');
assert(hudScript.includes('vh * 0.15') && hudScript.includes('Vector2(56.0, 48.0)'), '0.2.53 reverse indicator must stay a compact top-centre chip off the car');
for (const marker of ['switch_world', '--native-world=', '_run_desert_smoke_checks', '_desert_screenshot_shots', '"selected_world": "richtown"', 'desert_road_deck_colliders', 'desert_scatter_variants', 'desert_fences_0251']) {
  assert(mainScript.includes(marker), `0.2.47 world-switch marker is missing: ${marker}`);
}
for (const marker of ['signal world_selected(world_id: String)', 'func set_current_world', '_on_world_card_pressed', 'WORLD_CANYON_REQUIRED_CREDITS := 25000']) {
  assert(mainMenuScript.includes(marker), `0.2.47 menu world-selection marker is missing: ${marker}`);
}
assert(mainMenuScript.includes('const WORLDS_FREE_FOR_ALL := false'), '0.2.61 progression must switch the temporary free-world flag off');
assert(mainMenuScript.includes('worlds_free_for_all_0248'), '0.2.48 free-world smoke marker is missing');
for (const marker of ['_build_desert_pois', '_road_labels_data']) {
  assert(worldMapScript.includes(marker), `0.2.47 world-map desert marker is missing: ${marker}`);
}
for (const name of ['user_dirt_cracked.jpg', 'user_stone_rubble.jpg', 'user_stone_rubble_normal.jpg', 'metal_pole.jpg', 'metal_pole_normal.jpg', 'dz_packed_earth.jpg', 'dz_packed_earth_normal.jpg', 'dz_packed_earth_roughness.jpg', 'dz_trail_gravel.jpg', 'dz_trail_gravel_normal.jpg', 'dz_trail_gravel_roughness.jpg', 'dz_sand_dune.jpg', 'dz_sand_dune_normal.jpg', 'dz_sand_dune_roughness.jpg', 'dz_salt_crust.jpg', 'dz_salt_crust_normal.jpg', 'dz_salt_crust_roughness.jpg', 'dz_rock_red.jpg', 'dz_rock_red_normal.jpg', 'dz_rock_red_roughness.jpg', 'dz_cactus_skin.jpg', 'dz_cactus_skin_normal.jpg', 'dz_cactus_skin_roughness.jpg']) {
  assert(syncScript.includes(`'${name}'`), `Native asset sync must stage the desert texture ${name}`);
}


// 0.2.54 third world: the generated GreenForest data set and its
// runtime wiring (builder stages, smoke gate, menu card, world map).
const forestData = JSON.parse(forestDataText);
assert(forestData.bounds.maxX === 4000 && forestData.bounds.maxZ === 4000, 'GreenForest bounds must cover the full 4x4 km map');
assert(forestData.terrain.heights.length === 251001, 'GreenForest terrain must ship the full 501x501 height grid');
assert(forestData.terrain.heights.every((v) => v > 0), 'GreenForest heights must stay above the safety floor');
assert(forestData.terrain.heights.reduce((m, v) => Math.max(m, v), 0) < 165, 'GreenForest northern hills must stay under the 160 m spec ceiling');
assert(forestData.stats.roadLengthKm >= 50, 'GreenForest road network must meet the 50 km floor');
assert(forestData.roads.length >= 35, 'GreenForest road list is incomplete');
assert(forestData.forest.structures.length >= 380, 'GreenForest structures are incomplete');
assert(forestData.forest.bridges.length >= 8, 'GreenForest must ship at least eight bridges');
assert(forestData.forest.tunnels.length === 2, 'GreenForest must ship exactly two tunnels');
assert(forestData.forest.game.circuits.length === 4 && forestData.forest.game.sprints.length === 3 && forestData.forest.game.drags.length === 2 && forestData.forest.game.jumps.length === 12 && forestData.forest.game.fastTravel.length === 8 && forestData.forest.game.photoSpots.length === 10, 'GreenForest game content is incomplete');
assert(forestData.landmarks.length >= 25, 'GreenForest landmarks are incomplete');
const forestScatterTotal = Object.values(forestData.forest.scatter).reduce((sum, items) => sum + items.length, 0);
assert(forestScatterTotal >= 90000, 'GreenForest scatter is below the authored budget');
const forestTreeKinds = ['spruce', 'pine', 'birch', 'leafy', 'oak', 'dead_tree'];
const forestTreeTotal = forestTreeKinds.reduce((sum, kind) => sum + (forestData.forest.scatter[kind]?.length ?? 0), 0);
assert(forestTreeTotal >= 35000, 'GreenForest tree count is below budget');
// Exact on-road audit, same grid approach as the 0.2.53 desert gate.
const forestSegs = [];
for (const road of forestData.roads) {
  const pts = road.samples.map((sm) => [sm[0], sm[2]]);
  if (road.closed && pts.length) pts.push(pts[0]);
  for (let i = 0; i + 1 < pts.length; i++) forestSegs.push([pts[i], pts[i + 1], road.widthM * 0.5]);
}
const forestSegGrid = new Map();
forestSegs.forEach((seg, idx) => {
  const [[ax, az], [bx, bz], hw] = seg;
  const pad = hw + 40;
  const x0 = Math.floor((Math.min(ax, bx) - pad) / 100);
  const x1 = Math.floor((Math.max(ax, bx) + pad) / 100);
  const z0 = Math.floor((Math.min(az, bz) - pad) / 100);
  const z1 = Math.floor((Math.max(az, bz) + pad) / 100);
  for (let cx = x0; cx <= x1; cx++) for (let cz = z0; cz <= z1; cz++) {
    const key = `${cx},${cz}`;
    if (!forestSegGrid.has(key)) forestSegGrid.set(key, []);
    forestSegGrid.get(key).push(idx);
  }
});
function forestEdgeClearance(px, pz) {
  const key = `${Math.floor(px / 100)},${Math.floor(pz / 100)}`;
  const cand = forestSegGrid.get(key) ?? [];
  let best = Infinity;
  for (const idx of cand) {
    const [[ax, az], [bx, bz], hw] = forestSegs[idx];
    const abx = bx - ax, abz = bz - az;
    const l2 = Math.max(abx * abx + abz * abz, 1e-9);
    let t = ((px - ax) * abx + (pz - az) * abz) / l2;
    t = Math.min(1, Math.max(0, t));
    best = Math.min(best, Math.hypot(px - (ax + abx * t), pz - (az + abz * t)) - hw);
  }
  return best;
}
let forestScatterOnRoad = 0;
for (const items of Object.values(forestData.forest.scatter)) {
  for (const it of items) if (forestEdgeClearance(it[0], it[1]) < 0) forestScatterOnRoad += 1;
}
assert(forestScatterOnRoad === 0, `GreenForest scatter instances on carriageways: ${forestScatterOnRoad}`);
const forestLake = forestData.forest.lake;
const damRoad = forestData.roads.find((r) => r.id === 'gf-dam_road');
assert(damRoad, 'GreenForest dam road is missing');
const damOverWater = damRoad.samples.filter((sm) => Math.hypot((sm[0] - forestLake.x) / forestLake.rx, (sm[2] - forestLake.z) / forestLake.rz) < 0.92);
assert(damOverWater.length >= 8 && Math.min(...damOverWater.map((sm) => sm[1])) > forestLake.y + 0.4, 'GreenForest dam deck must stay above lake level across the open water');
assert(forestData.spawn.x > 0 && forestData.spawn.x < 4000 && forestData.spawn.z > 0 && forestData.spawn.z < 4000, 'GreenForest spawn must be inside the map');
for (const marker of ['FOREST_DATA_PATH', 'greenforest_world_0254', '_queue_forest_build_stages', '_build_forest_terrain', '_build_forest_water', '_build_forest_scatter', '_gf_structure_kind', '_gf_near_road', '_gf_scatter_build', '_build_forest_extras', '_build_forest_skyline', 'forest_tunnels_built', 'gf_meadow.jpg', 'gf_forest_floor_roughness.jpg', 'gf_rock_gray_normal.jpg']) {
  assert(worldScript.includes(marker), `0.2.54 forest builder marker is missing: ${marker}`);
}
for (const marker of ['_run_forest_smoke_checks', '_forest_screenshot_shots', 'greenforest']) {
  assert(mainScript.includes(marker), `0.2.54 forest main marker is missing: ${marker}`);
}
for (const marker of ['_forest_card', 'ЗЕЛЁНЫЙ ЛЕС', 'forest_world_0254']) {
  assert(mainMenuScript.includes(marker), `0.2.54 forest menu marker is missing: ${marker}`);
}
assert(worldMapScript.includes('forest_map_0254'), '0.2.54 forest world-map marker is missing');
assert(loadingScreenScript.includes('ЗЕЛЁНЫЙ ЛЕС'), '0.2.54 forest loading label is missing');
for (const name of ['gf_meadow.jpg', 'gf_meadow_normal.jpg', 'gf_meadow_roughness.jpg', 'gf_forest_floor.jpg', 'gf_forest_floor_normal.jpg', 'gf_forest_floor_roughness.jpg', 'gf_mud.jpg', 'gf_mud_normal.jpg', 'gf_mud_roughness.jpg', 'gf_rock_gray.jpg', 'gf_rock_gray_normal.jpg', 'gf_rock_gray_roughness.jpg', 'gf_field_soil.jpg', 'gf_field_soil_normal.jpg', 'gf_field_soil_roughness.jpg']) {
  assert(syncScript.includes(`'${name}'`), `Native asset sync must stage the forest texture ${name}`);
}


// 0.2.61 online release: purchasable cars/worlds, server accounts,
// 10 daily quests, multiplayer rooms, fictionalised car names.
for (const marker of ['START_CREDITS := 15000', 'WORLD_PRICES', 'QUEST_POOL', 'func _buy_car', 'func _buy_world', 'func _daily_quests_view', 'func _setup_net', 'NitchesNetClient', 'NitchesMpClient', 'economy_v']) {
  assert(mainScript.includes(marker), `0.2.61 progression/online marker is missing in main.gd: ${marker}`);
}
for (const marker of ['PANEL_ONLINE := 6', 'signal car_purchase_requested', 'signal account_register_requested', 'signal daily_quest_claim_requested', 'func _build_online_panel', 'func show_admin_data', 'ONLINE_PRIVACY_TEXT', 'ONLINE_WELCOME_TEXT', '_is_car_owned_menu', '_is_world_owned_menu']) {
  assert(mainMenuScript.includes(marker), `0.2.61 online menu marker is missing: ${marker}`);
}
const netClientScript = await readText('scripts/net_client.gd');
const mpClientScript = await readText('scripts/multiplayer_client.gd');
assert(netClientScript.includes('class_name NitchesNetClient') && netClientScript.includes('/api/quests/claim') && netClientScript.includes('/api/admin/'), '0.2.61 net client is incomplete');
assert(mpClientScript.includes('class_name NitchesMpClient') && mpClientScript.includes('WebSocketPeer') && mpClientScript.includes('Label3D'), '0.2.61 multiplayer client is incomplete');
const serverScript = await readFile('server/src/index.js', 'utf8');
for (const marker of ['export class RoomDO', '/api/register', 'PBKDF2', 'QUEST_POOL', '/api/admin/grant', 'PRIVACY_HTML']) {
  assert(serverScript.includes(marker), `0.2.61 server marker is missing: ${marker}`);
}
const carCatalogScript61 = await readText('scripts/car_catalog.gd');
for (const marker of ['Shelbie GT500', 'Audo R8 V10 plus', 'Chevrole Kamaro SS', 'Mercedez-Bens 560 SEL', '"price_cr": 50000', '"price_cr": 95000', '"price_cr": 160000']) {
  assert(carCatalogScript61.includes(marker), `0.2.61 catalog marker is missing: ${marker}`);
}


// 0.2.62: lightweight menu splash (no live world render in menu),
// classified store filters (class/power/ownership), wheel of fortune.
for (const marker of ['func _apply_menu_lightweight', 'WHEEL_SEGMENTS', 'func _grant_wheel_spins', 'func _on_wheel_spin_requested', 'wheel_spin_requested']) {
  assert(mainScript.includes(marker), `0.2.62 main marker is missing: ${marker}`);
}
for (const marker of ['MenuBackground0262', 'class WheelView', 'func show_wheel_result', '_store_class_filter', '_store_power_filter', '_store_owned_filter', '_store_item_matches_filters', 'menu_light_bg_0262', 'wheel_ui_0262', 'store_filters_0262']) {
  assert(mainMenuScript.includes(marker), `0.2.62 menu marker is missing: ${marker}`);
}

// 0.3.0: RichTown 7x7 km rebuild (stages 1-2) + LOD model budgets.
for (const marker of ['_is_rt7', '_queue_rt7_build_stages', '_rt7_junction_candidates', '_rt7_terrain_class', 'model_lod_budget_0300', 'generic_building_batches_0300', 'rt7_stadium_0300', 'rt7_cable_bridge_0300', 'hero_avenue_x', 'richtown7']) {
  assert(worldScript.includes(marker), `0.3.0 world builder marker is missing: ${marker}`);
}
for (const marker of ['_run_rt7_world_smoke_checks', 'richtown7_0300']) {
  assert(mainScript.includes(marker), `0.3.0 main marker is missing: ${marker}`);
}
assert(worldMapScript.includes('rt7-stadium') && worldMapScript.includes('richtown7'), '0.3.0 world map must know the 7x7 POIs/labels');
assert(wetAsphaltShader.includes('hero_avenue_x') && wetAsphaltShader.includes('boulevard_mask'), '0.3.0 wet-asphalt hero-avenue mask must be parameterised, not removed');
// 0.3.1: airport + NPP + military base + district schools + densification.
for (const marker of ['rt7_airport_0310', 'rt7_npp_0310', 'rt7_milbase_0310', 'rt7_schools_0310', 'rt7_cooling_towers_0310', 'rt7_planes_0310', 'rt7_hangars_0310']) {
  assert(worldScript.includes(marker), `0.3.1 world builder marker is missing: ${marker}`);
}
assert(worldMapScript.includes('rt7-terminal') && worldMapScript.includes('rt7-school'), '0.3.1 world map must know the airport/school POIs');
// 0.3.2: every building/mega-structure is a Blender GLB (city pack).
for (const marker of ['CITY_MODELS_0320', 'city_blender_instances_0320', 'city_landmark_glb_0320', 'rt7_cranes_0320', 'CityWhitePaint', 'CityFieldGreen', 'res://assets/props/stadium.glb', 'res://assets/props/cooling_tower.glb', 'res://assets/props/airport_terminal.glb', 'res://assets/props/port_crane.glb']) {
  assert(worldScript.includes(marker), `0.3.2 world builder marker is missing: ${marker}`);
}
assert(mainScript.includes('city_blender_instances_0320'), '0.3.2 main smoke must verify the Blender city pack');
for (const cityGlb of ['school.glb', 'airport_terminal.glb', 'atc_tower.glb', 'hangar_large.glb', 'hangar_small.glb', 'airliner.glb', 'cooling_tower.glb', 'reactor.glb', 'chimney.glb', 'radar_station.glb', 'watchtower.glb', 'storage_tank.glb', 'silo.glb', 'afv.glb', 'stadium.glb', 'office_tower_low.glb', 'office_tower_mid.glb', 'office_tower_high.glb', 'midrise_a.glb', 'midrise_b.glb', 'warehouse_large.glb', 'warehouse_small.glb', 'container_red.glb', 'container_blue.glb', 'villa_b.glb', 'townhouse_b.glb', 'barn.glb', 'greenhouse.glb', 'port_crane.glb']) {
  assert(syncScript.includes(cityGlb), `0.3.2 sync must stage ${cityGlb}`);
}

// 0.3.3: phone performance rescue (wide compensated city chunks,
// streaming fast paths, Android budgets + FPS governor).
for (const marker of ['_is_city_pack_path', 'radius_comp_0330', 'perf_streaming_0330', 'perf_city_hlod_0330', '_collider_cell_list', 'return 620.0', 'proxy_chunk_m = 820.0']) {
  assert(worldScript.includes(marker), `0.3.3 world performance marker is missing: ${marker}`);
}
for (const marker of ['_update_performance_governor_0330', '_apply_performance_governor_0330', 'android_perf_budgets_0330', 'perf_governor_level_0330']) {
  assert(mainScript.includes(marker), `0.3.3 main performance marker is missing: ${marker}`);
}
assert(project.includes('shadows/positional_shadow/atlas_size.mobile=1024'), '0.3.3 phones must cap the positional shadow atlas at 1024px');

// 0.3.4: model detail + compression + performance audit.
// blenderScript is loaded with the other sources at the top of this validator.
for (const marker of ['_merge_meshes_by_material_for_export', 'school_win_mullion', 'villab_glass_mullion', 'townb_bay_mullion_v', 'wh_dock_seam', 'cont_data_plate', 'term_door_mullion', 'hangar_door_leaf', 'stadium_portal']) {
  assert(blenderScript.includes(marker), `0.3.4 Blender detail/compression marker is missing: ${marker}`);
}
for (const marker of ['model_perf_audit_0340', 'model_source_triangles_total_0340', 'model_source_mesh_objects_total_0340']) {
  assert(worldScript.includes(marker), `0.3.4 world performance-audit marker is missing: ${marker}`);
}
const auditStat034 = await stat('scripts/audit-model-performance.py');
assert(auditStat034.size > 0, '0.3.4 model performance audit script is missing');

// 0.3.5: the last generic city buildings become Blender models, the
// premium repeats get wide HLOD cells + caps, infill filler joins the
// cheap city townhouse batch, and weak phones get governor level 4.
for (const marker of ['build_shopping_mall', 'build_turbine_hall_long', 'build_turbine_hall_short', 'mall_storefront', 'turbine_ribbon']) {
  assert(blenderScript.includes(marker), `0.3.5 Blender marker is missing: ${marker}`);
}
for (const marker of ['perf_premium_hlod_0350', 'infill_city_townhouses_0350', 'shopping_mall.glb', 'turbine_hall_long.glb', 'return 360.0', 'proxy_chunk_m = 560.0', 'windowframe']) {
  assert(worldScript.includes(marker), `0.3.5 world marker is missing: ${marker}`);
}
for (const marker of ['mini(4, next_level + 2)', '[1.0, 0.78, 0.58, 0.42, 0.30][level]', '[6.0, 8.0, 11.0, 14.0, 18.0][level]']) {
  assert(mainScript.includes(marker), `0.3.5 main governor marker is missing: ${marker}`);
}
for (const newModel of ['shopping_mall.glb', 'turbine_hall_long.glb', 'turbine_hall_short.glb']) {
  const newModelInfo = await stat(`src/assets/models/props/${newModel}`);
  assert(newModelInfo.size > 50_000, `0.3.5 ${newModel} GLB is missing or truncated`);
  assert(syncScript.includes(`props/${newModel}`), `0.3.5 ${newModel} must sync into the native assets`);
}
const rtMall035 = data.buildings.find((b) => b.model === 'shopping_mall');
assert(rtMall035 && rtMall035.w === 230 && rtMall035.d === 130, '0.3.5 RichTown Mall must use the shopping_mall GLB on its 230x130 parcel');
assert(data.buildings.filter((b) => b.model === 'turbine_hall_long' || b.model === 'turbine_hall_short').length === 2, '0.3.5 both NPP turbine halls must use their GLBs');
assert(data.stats.genericBuildings === 300 && data.stats.cityBlenderBuildings === 1274, '0.3.5/0.3.11 generator stats must show the last three generic boxes converted (0.3.11 tunnel reserve frees four parcels; 0.3.15 container terminal adds 90 city archetypes)');

// 0.3.6: ten-model perfection pass.  Premium window layers become
// outward facade quads (same materials/parts, far fewer triangles);
// five city archetypes gain rear/side detail inside strict budgets.
for (const marker of ['def panel(', 'def wquad', 'detail_036', 'villab_rear_door', 'townb_rear_win', 'wh_clerestory', 'mid_sill_band', 'mid_balcony_toprail', 'office_podium_glass_back', 'segments=14, ring_count=10']) {
  assert(blenderScript.includes(marker), `0.3.6 Blender marker is missing: ${marker}`);
}
for (const tenModel of ['townhouse.glb', 'villa.glb', 'hero_building.glb', 'glass_tower.glb', 'grand_hotel.glb', 'villa_b.glb', 'townhouse_b.glb', 'midrise_a.glb', 'office_tower_low.glb', 'warehouse_large.glb']) {
  const tenInfo = await stat(`src/assets/models/props/${tenModel}`);
  assert(tenInfo.size > 20_000, `0.3.6 ${tenModel} is missing or truncated`);
}

// 0.3.7: second ten-model perfection pass.  Landmark glazing that is
// backed by a solid core/frame becomes outward merged quads; mosque
// tori/spheres and opera shell seam tubes use size-appropriate
// segment counts; repeated street furniture loses invisible 6-22 mm
// bevels while hero bevels and freestanding shelter glass stay solid.
for (const marker of ['def local_panel(', 'def builder_panel(', 'cross_segments = 28', 'length_segments = 14', 'segments = 16 if radius > 2.0 else 12', 'major_segments=28 if major > 3.0 else 20']) {
  assert(blenderScript.includes(marker), `0.3.7 Blender marker is missing: ${marker}`);
}
assert(worldScript.includes('premium_hotel_triangles >= 24000'), '0.3.7 must keep the Grand Hotel smoke floor aligned with the optimized 0.3.6 model');
for (const marker of ['premium_hotel_triangles", 0)) < 24000', 'street_lamp_triangles", 0)) < 1800', 'bus_shelter_triangles", 0)) < 2800', 'park_bench_triangles", 0)) < 1200', 'park_pergola_triangles", 0)) < 2400']) {
  assert(mainScript.includes(marker), `0.3.7 runtime triangle floor is missing: ${marker}`);
}
const modelBudgets037 = {
  'opera_house.glb': [47_000, 18],
  'mosque.glb': [32_000, 12],
  'main_tower.glb': [34_500, 18],
  'museum.glb': [31_800, 16],
  'traffic_signal_long.glb': [6_200, 8],
  'traffic_signal_short.glb': [4_200, 8],
  'bus_shelter.glb': [3_800, 6],
  'park_pergola.glb': [3_600, 3],
  'street_lamp.glb': [2_300, 3],
  'park_bench.glb': [1_600, 3],
};
for (const [model037, [triangleCap037, expectedParts037]] of Object.entries(modelBudgets037)) {
  const modelBytes037 = await readFile(`src/assets/models/props/${model037}`);
  assert(modelBytes037.subarray(0, 4).toString('utf8') === 'glTF', `0.3.7 ${model037} is not a real GLB`);
  const modelJson037 = parseGlbJson(modelBytes037);
  let triangles037 = 0;
  let parts037 = 0;
  for (const mesh037 of modelJson037.meshes ?? []) {
    for (const primitive037 of mesh037.primitives ?? []) {
      parts037 += 1;
      const vertexCount037 = primitive037.indices !== undefined
        ? modelJson037.accessors[primitive037.indices].count
        : modelJson037.accessors[primitive037.attributes.POSITION].count;
      const mode037 = primitive037.mode ?? 4;
      triangles037 += mode037 === 4 ? Math.floor(vertexCount037 / 3) : (mode037 === 5 || mode037 === 6 ? Math.max(vertexCount037 - 2, 0) : 0);
    }
  }
  assert(parts037 === expectedParts037, `0.3.7 ${model037} part count changed: ${parts037} !== ${expectedParts037}`);
  assert(triangles037 <= triangleCap037, `0.3.7 ${model037} exceeds its triangle budget: ${triangles037} > ${triangleCap037}`);
}

// 0.3.8: third ten-model perfection pass.  Cottage window/door/garage
// glazing layers backed by basalt reveals become outward panels,
// garden boulders and the courtyard fountain use size-appropriate
// sphere segments, 12-20 mm bevels leave small stone parts (main
// volume and hedge bevels stay), the stadium lathes match their 36
// facade ribs, midrise_b dark glass becomes panels behind solid
// balcony rails, container corrugation keeps its silhouette at a
// wider pitch, and office_tower_mid/high plus warehouse_small gain
// the detail their sibling variants already had.
for (const marker of ['panel("cottage_window_glass"', 'panel("cottage_mashrabiya_core"', 'segments=12, ring_count=8', '_ct_lathe("stadium_bowl", profile, concrete, segments=36', 'def _build_midrise(width, depth, floors, detail_036=False, panel_038=False)', 'office_upper_corner_fin', 'panel("cont_data_plate"']) {
  assert(blenderScript.includes(marker), `0.3.8 Blender marker is missing: ${marker}`);
}
for (const marker of ['sail_cottage_dune_triangles_0239", 0)) < 7500', 'sail_cottage_courtyard_triangles_0239", 0)) < 8500', 'sail_cottage_palm_triangles_0239", 0)) < 6500']) {
  assert(mainScript.includes(marker), `0.3.8 runtime triangle floor is missing: ${marker}`);
}
const modelBudgets038 = {
  'cottage_courtyard.glb': [11_500, 17],
  'cottage_dune.glb': [9_800, 17],
  'cottage_palm.glb': [9_200, 16],
  'midrise_b.glb': [2_450, 8],
  'stadium.glb': [2_350, 7],
  'container_blue.glb': [660, 4],
  'container_red.glb': [660, 4],
  'office_tower_mid.glb': [720, 7],
  'office_tower_high.glb': [830, 8],
  'warehouse_small.glb': [830, 6],
};
for (const [model038, [triangleCap038, expectedParts038]] of Object.entries(modelBudgets038)) {
  const modelBytes038 = await readFile(`src/assets/models/props/${model038}`);
  assert(modelBytes038.subarray(0, 4).toString('utf8') === 'glTF', `0.3.8 ${model038} is not a real GLB`);
  const modelJson038 = parseGlbJson(modelBytes038);
  let triangles038 = 0;
  let parts038 = 0;
  for (const mesh038 of modelJson038.meshes ?? []) {
    for (const primitive038 of mesh038.primitives ?? []) {
      parts038 += 1;
      const vertexCount038 = primitive038.indices !== undefined
        ? modelJson038.accessors[primitive038.indices].count
        : modelJson038.accessors[primitive038.attributes.POSITION].count;
      const mode038 = primitive038.mode ?? 4;
      triangles038 += mode038 === 4 ? Math.floor(vertexCount038 / 3) : (mode038 === 5 || mode038 === 6 ? Math.max(vertexCount038 - 2, 0) : 0);
    }
  }
  assert(parts038 === expectedParts038, `0.3.8 ${model038} part count changed: ${parts038} !== ${expectedParts038}`);
  assert(triangles038 <= triangleCap038, `0.3.8 ${model038} exceeds its triangle budget: ${triangles038} > ${triangleCap038}`);
}

// 0.3.9: fourth ten-model perfection pass.  The hero/villa solid
// frame slabs and reveal plates (backed by wall/reveal layers) become
// outward panels and the blind rails fully embedded inside those
// slabs are removed; townhouse reveal rails and blind rails become
// merged quads; glass-tower blind headrails, fin shadow strips, slab
// nosings and sill transoms become quads behind the vision glass and
// its rooftop smalls use size-appropriate radial segments; midrise_a
// joins midrise_b on panel glazing; mall/school/airport/villa_b/
// townhouse_b wall-backed glass becomes panels on the old outer
// faces, round timber/plaster posts become square posts, and the
// school gains a name band and roof plant.
for (const marker of ['panel("hero_window_frame"', 'panel("villa_window_frame"', 'wquad(frame, 0.0, 0.083', 'backing_out + 0.030', 'sphere("tower_flag_finial"', '_build_midrise(34.0, 26.0, 7, detail_036=True, panel_038=True)', 'panel("mall_storefront"', 'panel("school_win_front"', 'school_sign', 'panel("term_glass_upper"', 'win_recess_0312("villab_glass"', 'win_recess_0312("townb_window"']) {
  assert(blenderScript.includes(marker), `0.3.9 Blender marker is missing: ${marker}`);
}
const modelBudgets039 = {
  'glass_tower.glb': [22_000, 18],
  'hero_building.glb': [22_500, 18],
  'townhouse.glb': [17_500, 22],
  'villa.glb': [12_600, 19],
  'midrise_a.glb': [1_820, 8],
  'shopping_mall.glb': [2_400, 9],
  'school.glb': [1_750, 11],
  'airport_terminal.glb': [1_150, 5],
  'villa_b.glb': [700, 8],
  'townhouse_b.glb': [910, 9],
};
for (const [model039, [triangleCap039, expectedParts039]] of Object.entries(modelBudgets039)) {
  const modelBytes039 = await readFile(`src/assets/models/props/${model039}`);
  assert(modelBytes039.subarray(0, 4).toString('utf8') === 'glTF', `0.3.9 ${model039} is not a real GLB`);
  const modelJson039 = parseGlbJson(modelBytes039);
  let triangles039 = 0;
  let parts039 = 0;
  for (const mesh039 of modelJson039.meshes ?? []) {
    for (const primitive039 of mesh039.primitives ?? []) {
      parts039 += 1;
      const vertexCount039 = primitive039.indices !== undefined
        ? modelJson039.accessors[primitive039.indices].count
        : modelJson039.accessors[primitive039.attributes.POSITION].count;
      const mode039 = primitive039.mode ?? 4;
      triangles039 += mode039 === 4 ? Math.floor(vertexCount039 / 3) : (mode039 === 5 || mode039 === 6 ? Math.max(vertexCount039 - 2, 0) : 0);
    }
  }
  assert(parts039 === expectedParts039, `0.3.9 ${model039} part count changed: ${parts039} !== ${expectedParts039}`);
  assert(triangles039 <= triangleCap039, `0.3.9 ${model039} exceeds its triangle budget: ${triangles039} > ${triangleCap039}`);
}

// 0.3.10: fifth and final model pass - the 17 remaining industrial/
// airfield/farm models.  Oversized UV spheres (reactor/radar/tank
// domes were 704 tris each at 24x16) and radial parts use
// size-appropriate segment counts; wall-backed glass/louvers/stripes
// become outward panels; the watchtower gains its guard railing, the
// port crane leg cross-bracing and a cab window band, and the ATC
// base a window band.  Greenhouse glass and crop rows stay solid.
for (const marker of ['panel("hangar_door_rail"', 'panel("turbine_louver"', 'segments=20, ring_count=12', 'watch_rail_top', 'crane_brace_a', 'win_recess_0312("barn_win"', 'atc_base_windows', 'range(-21, 22, 7)', 'sphere("tank_roof"']) {
  assert(blenderScript.includes(marker), `0.3.10 Blender marker is missing: ${marker}`);
}
const modelBudgets0310 = {
  'cooling_tower.glb': [1_350, 2],
  'reactor.glb': [850, 6],
  'turbine_hall_long.glb': [920, 8],
  'turbine_hall_short.glb': [720, 8],
  'storage_tank.glb': [620, 4],
  'radar_station.glb': [560, 6],
  'airliner.glb': [660, 6],
  'afv.glb': [570, 4],
  'greenhouse.glb': [730, 5],
  'chimney.glb': [410, 3],
  'atc_tower.glb': [440, 6],
  'hangar_large.glb': [330, 5],
  'hangar_small.glb': [330, 5],
  'port_crane.glb': [400, 7],
  'barge.glb': [400, 5],
  'bleacher.glb': [380, 4],
  'barn.glb': [330, 5],
  'watchtower.glb': [380, 4],
  'silo.glb': [200, 3],
};
for (const [model0310, [triangleCap0310, expectedParts0310]] of Object.entries(modelBudgets0310)) {
  const modelBytes0310 = await readFile(`src/assets/models/props/${model0310}`);
  assert(modelBytes0310.subarray(0, 4).toString('utf8') === 'glTF', `0.3.10 ${model0310} is not a real GLB`);
  const modelJson0310 = parseGlbJson(modelBytes0310);
  let triangles0310 = 0;
  let parts0310 = 0;
  for (const mesh0310 of modelJson0310.meshes ?? []) {
    for (const primitive0310 of mesh0310.primitives ?? []) {
      parts0310 += 1;
      const vertexCount0310 = primitive0310.indices !== undefined
        ? modelJson0310.accessors[primitive0310.indices].count
        : modelJson0310.accessors[primitive0310.attributes.POSITION].count;
      const mode0310 = primitive0310.mode ?? 4;
      triangles0310 += mode0310 === 4 ? Math.floor(vertexCount0310 / 3) : (mode0310 === 5 || mode0310 === 6 ? Math.max(vertexCount0310 - 2, 0) : 0);
    }
  }
  assert(parts0310 === expectedParts0310, `0.3.10 ${model0310} part count changed: ${parts0310} !== ${expectedParts0310}`);
  assert(triangles0310 <= triangleCap0310, `0.3.10 ${model0310} exceeds its triangle budget: ${triangles0310} > ${triangleCap0310}`);
}

// 0.3.11: RichTown 7x7 stages 3+4 - detailed downtown and marinas.
// Rich Tower plaza (paving discs, planters, flags), the Roses Avenue
// land tunnel (cut-and-cover tube with colliders, emissive ceiling
// strips and a green roof slab), the stadium forecourt, and two
// carved marina basins with quay/finger piers, breakwaters and 32
// moored Blender yachts.  All repeated primitives ride eight chunked
// MultiMesh batches; no building detail budget changes.
for (const marker of ['rt7-plaza', 'rt7-tunnel', 'rt7-pier', 'rt7-breakwater', 'rt7-yacht-sail', 'rt7-yacht-motor', 'Stage34Concrete0311', 'Stage34PierDecks0311', 'marinaBasinS', 'marinaBasinN', 'rt7_stage34_batches_0311', 'rt7_stadium_forecourt_0311']) {
  assert(worldScript.includes(marker), `0.3.11 world builder marker is missing: ${marker}`);
}
for (const marker of ['build_yacht_sail', 'build_yacht_motor', '_yacht_hull', 'yacht_sail.glb', 'yacht_motor.glb']) {
  assert(blenderScript.includes(marker), `0.3.11 Blender marker is missing: ${marker}`);
}
for (const yachtGlb of ['yacht_sail.glb', 'yacht_motor.glb']) {
  assert(syncScript.includes(yachtGlb), `0.3.11 sync must stage ${yachtGlb}`);
}
const modelBudgets0311 = {
  'yacht_sail.glb': [320, 4],
  'yacht_motor.glb': [420, 4],
};
for (const [model0311, [triangleCap0311, expectedParts0311]] of Object.entries(modelBudgets0311)) {
  const modelBytes0311 = await readFile(`src/assets/models/props/${model0311}`);
  assert(modelBytes0311.subarray(0, 4).toString('utf8') === 'glTF', `0.3.11 ${model0311} is not a real GLB`);
  const modelJson0311 = parseGlbJson(modelBytes0311);
  let triangles0311 = 0;
  let parts0311 = 0;
  for (const mesh0311 of modelJson0311.meshes ?? []) {
    for (const primitive0311 of mesh0311.primitives ?? []) {
      parts0311 += 1;
      const vertexCount0311 = primitive0311.indices !== undefined
        ? modelJson0311.accessors[primitive0311.indices].count
        : modelJson0311.accessors[primitive0311.attributes.POSITION].count;
      const mode0311 = primitive0311.mode ?? 4;
      triangles0311 += mode0311 === 4 ? Math.floor(vertexCount0311 / 3) : (mode0311 === 5 || mode0311 === 6 ? Math.max(vertexCount0311 - 2, 0) : 0);
    }
  }
  assert(parts0311 === expectedParts0311, `0.3.11 ${model0311} part count changed: ${parts0311} !== ${expectedParts0311}`);
  assert(triangles0311 <= triangleCap0311, `0.3.11 ${model0311} exceeds its triangle budget: ${triangles0311} > ${triangleCap0311}`);
}
const landmarkKinds0311 = new Map();
for (const landmark0311 of data.landmarks) {
  landmarkKinds0311.set(landmark0311.kind, (landmarkKinds0311.get(landmark0311.kind) ?? 0) + 1);
}
assert(landmarkKinds0311.get('rt7-plaza') === 1 && landmarkKinds0311.get('rt7-tunnel') === 1, '0.3.11 downtown must place one plaza and one tunnel');
assert((landmarkKinds0311.get('rt7-pier') ?? 0) >= 10 && (landmarkKinds0311.get('rt7-breakwater') ?? 0) >= 4, '0.3.11 marinas must place 10 piers and 4 breakwaters');
assert((landmarkKinds0311.get('rt7-yacht-sail') ?? 0) >= 16 && (landmarkKinds0311.get('rt7-yacht-motor') ?? 0) >= 16, '0.3.11 marinas must moor at least 32 yachts');
assert(data.zones?.marinaBasinS && data.zones?.marinaBasinN, '0.3.11 world must expose both marina basin water zones');
assert(data.benches.length >= 70, '0.3.11 plaza/stadium/marina benches must ship in the world data');
const tunnelLamp0311 = data.lamps.some((lamp0311) => lamp0311.x > 1480 && lamp0311.x < 1820 && Math.abs(Math.abs(lamp0311.z) - 18.5) < 1.0);
assert(!tunnelLamp0311, '0.3.11 Roses tunnel tube must stay free of street lamps');
const basinBuilding0311 = data.buildings.some((b0311) => b0311.x > -3010 && b0311.x < -2660 && Math.abs(b0311.z) > 600 && Math.abs(b0311.z) < 1100);
assert(!basinBuilding0311, '0.3.11 marina basins must stay free of buildings');

// 0.3.12: realism pass - world-density UV bake + recessed windows.
// The mass-city materials (PropsMetal, RoofDark, FacadeMain/Accent,
// CityWhitePaint, container accents...) run tiling photo textures
// with uv1_scale == 1 and no triplanar, so the old per-face 0..1 box
// UVs stretched one texture repeat over whole roofs/walls.  The
// Blender export now rewrites those UVs from model-space metres
// (dominant-axis projection, near-cardinal objects only), villa_b /
// townhouse_b windows become recessed frames with real returns, the
// midrises gain facade piers and the warehouses dock headers.  Part
// counts and the detail-node budget are frozen; raised caps above
// carry the extra triangles inside the audited worst-frame gate.
for (const marker of ['_bake_world_uv_density_0312', '_UV_DENSITY_TILES_0312', 'win_recess_0312', 'mid_pier0312', 'wh_dock_header0312']) {
  assert(blenderScript.includes(marker), `0.3.12 Blender marker is missing: ${marker}`);
}
{
  const uvBytes0312 = await readFile('src/assets/models/props/warehouse_large.glb');
  const uvJson0312 = parseGlbJson(uvBytes0312);
  const jsonLen0312 = uvBytes0312.readUInt32LE(12);
  const binStart0312 = 20 + jsonLen0312 + 8;
  const matIdx0312 = (uvJson0312.materials ?? []).findIndex((m) => m.name === 'PropsMetal');
  assert(matIdx0312 >= 0, '0.3.12 warehouse_large lost its PropsMetal cladding');
  let uvMax0312 = 0;
  for (const mesh0312 of uvJson0312.meshes ?? []) {
    for (const prim0312 of mesh0312.primitives ?? []) {
      if (prim0312.material !== matIdx0312) continue;
      const acc0312 = uvJson0312.accessors[prim0312.attributes.TEXCOORD_0];
      const bv0312 = uvJson0312.bufferViews[acc0312.bufferView];
      const start0312 = binStart0312 + (bv0312.byteOffset ?? 0) + (acc0312.byteOffset ?? 0);
      const view0312 = new DataView(uvBytes0312.buffer, uvBytes0312.byteOffset + start0312, acc0312.count * 8);
      for (let i0312 = 0; i0312 < acc0312.count * 2; i0312 += 1) {
        uvMax0312 = Math.max(uvMax0312, Math.abs(view0312.getFloat32(i0312 * 4, true)));
      }
    }
  }
  assert(uvMax0312 > 5.0, `0.3.12 warehouse PropsMetal UVs are not world-density baked (max |uv| = ${uvMax0312})`);
}

// 0.3.13: realism pass 2 - seamless brushed metal + framed glass.
// The shared brushed-metal photo carried a hard horizontal seam
// (row-mean step ~50/255 at mid-height and again at the wrap), so
// every tiled metal surface banded visibly once 0.3.12 gave it
// world-scale UVs; it is now a seamless derivative (FFT low-tone
// equalisation + edge/centre mirror blends, originals kept) and
// every runtime material points at it.  Office shafts gain
// vertical face fins, the mall/school/terminal glass bands get
// head/sill transom rails, and the school wing/gym panes become
// recessed windows.  Parts and detail-node budgets stay frozen.
for (const marker of ['office_face_fin0313', 'office_upper_fin0313', 'mall_storefront_rail0313', 'mall_clerestory_rail0313', 'school_win_rail0313', 'term_glass_rail0313']) {
  assert(blenderScript.includes(marker), `0.3.13 Blender marker is missing: ${marker}`);
}
assert(worldScript.includes('user_brushed_metal_seamless.jpg') && worldScript.includes('user_brushed_metal_seamless_normal.jpg'), '0.3.13 world builder must use the seamless brushed-metal pair');
assert(!worldScript.includes('"user_brushed_metal.jpg"') && !worldScript.includes('"user_brushed_metal_normal.jpg"'), '0.3.13 no runtime material may keep the seamed brushed-metal originals');
assert(syncScript.includes('user_brushed_metal_seamless.jpg'), '0.3.13 sync must stage the seamless brushed-metal textures');
for (const [tex0313, minBytes0313] of [['user_brushed_metal_seamless.jpg', 50_000], ['user_brushed_metal_seamless_normal.jpg', 10_000]]) {
  const texInfo0313 = await stat(`src/assets/textures/realworld/${tex0313}`);
  assert(texInfo0313.size > minBytes0313, `0.3.13 ${tex0313} is missing or truncated`);
}
{
  const lowBytes0313 = await readFile('src/assets/models/props/office_tower_low.glb');
  const lowJson0313 = parseGlbJson(lowBytes0313);
  let lowTris0313 = 0;
  let lowParts0313 = 0;
  for (const mesh0313 of lowJson0313.meshes ?? []) {
    for (const prim0313 of mesh0313.primitives ?? []) {
      lowParts0313 += 1;
      const count0313 = prim0313.indices !== undefined
        ? lowJson0313.accessors[prim0313.indices].count
        : lowJson0313.accessors[prim0313.attributes.POSITION].count;
      const mode0313 = prim0313.mode ?? 4;
      lowTris0313 += mode0313 === 4 ? Math.floor(count0313 / 3) : (mode0313 === 5 || mode0313 === 6 ? Math.max(count0313 - 2, 0) : 0);
    }
  }
  assert(lowParts0313 === 7 && lowTris0313 <= 540, `0.3.13 office_tower_low budget blown: ${lowTris0313} tris / ${lowParts0313} parts`);
}

// 0.3.14: TZ stage 5 (model part) - lived-in residential detail.
// Mass housing was clean to the point of sterility: no services, no
// street-level clutter.  villa_b gains a tilted garage-roof solar
// array and two AC outdoor units; townhouse_b gains wheelie bins at
// the front wall and a side-wall AC unit per home.  Realism-pass
// leftovers close in the same pass: barn flat window panel pairs
// become recessed openings, hangar sliding doors get a portal
// surround and their side glazing gets head/sill rails, container
// plain rear ends get corrugation ribs, and the NPP turbine-hall
// ribbon glazing gets head/sill rails.  Street furniture (lamp,
// bench, signal) was render-inspected and needs no geometry.  All
// detail reuses each model's existing materials, so merged parts
// and the detail-node budget stay frozen; worst-frame triangles
// stay under the 7.0M discipline line (6,990,138 audited).
for (const marker of ['villab_solar0314', 'villab_ac0314', 'townb_bin0314', 'townb_ac0314', 'hangar_door_post0314', 'hangar_glass_rail0314', 'cont_rear_rib0314', 'turbine_ribbon_rail0314']) {
  assert(blenderScript.includes(marker), `0.3.14 Blender marker is missing: ${marker}`);
}
{
  const townBytes0314 = await readFile('src/assets/models/props/townhouse_b.glb');
  const townJson0314 = parseGlbJson(townBytes0314);
  let townTris0314 = 0;
  let townParts0314 = 0;
  for (const mesh0314 of townJson0314.meshes ?? []) {
    for (const prim0314 of mesh0314.primitives ?? []) {
      townParts0314 += 1;
      const count0314 = prim0314.indices !== undefined
        ? townJson0314.accessors[prim0314.indices].count
        : townJson0314.accessors[prim0314.attributes.POSITION].count;
      const mode0314 = prim0314.mode ?? 4;
      townTris0314 += mode0314 === 4 ? Math.floor(count0314 / 3) : (mode0314 === 5 || mode0314 === 6 ? Math.max(count0314 - 2, 0) : 0);
    }
  }
  assert(townParts0314 === 9 && townTris0314 <= 910, `0.3.14 townhouse_b budget blown: ${townTris0314} tris / ${townParts0314} parts`);
}
// 0.3.14 world-data part (TZ stage 5): courtyard landscaping is
// baked into the committed world JSON by generate_richtown7_world.py
// (foundation hedges, side-yard oaks, accent/pool palms per house).
// The entries only ever append to the plant arrays, so every
// pre-0.3.14 placement stays byte-identical.
assert(data.bushes.length >= 2000, '0.3.14 courtyard hedge bushes must ship in the world data');
assert(data.trees.length >= 1050, '0.3.14 courtyard yard oaks must ship in the world data');
assert(data.palms.length >= 1150, '0.3.14 courtyard/pool palms must ship in the world data');

// 0.3.15: TZ stage 6 - canal/port/farm detail.  A new Blender
// canal barge (344 tris, 5 parts) moors along both canal walls; the
// runtime raises concrete quay walls with copings and mooring
// bollards along the full 4.7 km channel and builds the farm field
// patches (soil/meadow slabs + crop ridge rows) from the new
// data["fields"] array - five chunked MultiMesh batches total.
// The generator appends an organised container terminal (+90),
// three more quay cranes, farm silo pairs and a port fuel-tank row;
// every pre-0.3.15 placement stays byte-identical (append-only).
for (const marker of ['build_barge', 'barge_hull0315', 'barge_wheelhouse0315']) {
  assert(blenderScript.includes(marker), `0.3.15 Blender marker is missing: ${marker}`);
}
for (const marker of ['rt7-barge', '_build_rt7_stage6_0315', 'CanalQuay0315', 'FarmFieldSoil0315', 'FarmFieldRows0315', 'rt7_barges_0315', 'rt7_fields_0315']) {
  assert(worldScript.includes(marker), `0.3.15 world-builder marker is missing: ${marker}`);
}
assert(syncScript.includes('props/barge.glb'), '0.3.15 sync must stage the canal barge GLB');
assert(data.landmarks.filter((l) => l.kind === 'rt7-crane').length >= 6, '0.3.15 must ship six canal quay cranes');
assert(data.landmarks.filter((l) => l.kind === 'rt7-barge').length >= 10, '0.3.15 must ship ten moored canal barges');
assert(data.landmarks.filter((l) => l.kind === 'rt7-tank').length >= 15, '0.3.15 farm silos + port fuel tanks must ship in the world data');
assert(Array.isArray(data.fields) && data.fields.length >= 18, '0.3.15 farm fields must ship in the world data');
assert(data.buildings.filter((b) => b.model === 'container_red' || b.model === 'container_blue').length >= 210, '0.3.15 container terminal rows must ship in the world data');

// 0.3.16: TZ stage 7 - eastern dune desert.  Three off-road routes
// ship as waypoint polylines in data["trails"] (two loops + the north
// raid); the runtime lays packed-sand ribbons over the raw dunes,
// plants marker flags/start banners/rocks and registers trail
// segments so the tyre model grants packed-sand grip on the marked
// line.  The flat drift zone becomes a paved arena: asphalt disc
// with painted rings, tyre-stack border, cone course, floodlights
// and two Blender grandstands (324 tris, 4 parts).  Trails never
// enter the road network, and every pre-0.3.16 placement stays
// byte-identical (append-only data).
for (const marker of ['build_bleacher', 'bleacher_tiers0316', 'bleacher_roof0316']) {
  assert(blenderScript.includes(marker), `0.3.16 Blender marker is missing: ${marker}`);
}
for (const marker of ['_build_rt7_stage7_0316', '_trail_clearance_xz', 'TrailFlags0316', 'DriftPad0316', 'DriftBleachers0316', 'rt7_stage7_trails0316']) {
  assert(worldScript.includes(marker), `0.3.16 world-builder marker is missing: ${marker}`);
}
assert(minimapScript.includes('_trails'), '0.3.16 minimap must draw the off-road trails');
assert(syncScript.includes('props/bleacher.glb'), '0.3.16 sync must stage the drift-arena grandstand GLB');
assert(Array.isArray(data.trails) && data.trails.length === 3, '0.3.16 must ship three off-road dune routes');
assert(data.trails.filter((t) => t.closed).length === 2, '0.3.16 must ship two closed dune loops');
assert(data.trails.reduce((n, t) => n + t.points.length, 0) >= 24, '0.3.16 trails must carry their waypoints');
assert(data.trails.every((t) => t.points.every((p) => p[0] >= 2400)), '0.3.16 trails must stay in the eastern dune desert');
assert(data.stats.trails === 3, '0.3.16 generator stats must count the trails');

console.log('Native Godot project validation OK');
console.log(JSON.stringify(data.stats, null, 2));
