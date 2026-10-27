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

const [project, preset, mainScene, dataText, mainScript, worldScript, vehicleScript, hudScript, dynamicWorldScript, speedPostScript, arcadeCarScript, carPaintShader, speedPostShader, wetAsphaltShader, foliageWindShader, curtainWallGlassShader, curtainWallFacadeShader, concreteSurfaceShader, premiumStonePavingShader, syncScript, blenderScript, desktopWorkflow] = await Promise.all([
  readText('project.godot'),
  readText('export_presets.cfg'),
  readText('scenes/main.tscn'),
  readText('data/richtown_native.json'),
  readText('scripts/main.gd'),
  readText('scripts/world_builder.gd'),
  readText('scripts/vehicle_controller.gd'),
  readText('scripts/hud.gd'),
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
]);

assert(project.includes('run/main_scene="res://scenes/main.tscn"'), 'project.godot does not point at the native main scene');
assert(project.includes('renderer/rendering_method="mobile"'), 'Godot Mobile renderer is not selected');
assert(project.includes('textures/default_filters/anisotropic_filtering_level=4'), '4x anisotropic filtering is not enabled');
assert(project.includes('lights_and_shadows/directional_shadow/size.mobile=2048'), '2048px mobile directional shadows are not enabled');
assert(mainScene.includes('res://scripts/main.gd'), 'main scene is not wired to main.gd');

assert(preset.includes('platform="Android"'), 'Android export preset is missing');
assert(preset.includes('architectures/arm64-v8a=true'), 'ARM64 Android export is not enabled');
assert(preset.includes('package/unique_name="io.nitches.horizon"'), 'Android package id differs from io.nitches.horizon');
assert(preset.includes('include_filter="*.json"'), 'Android export must explicitly include non-resource JSON world data');
assert(preset.includes('version/code=24'), 'Native 0.2.21 must bump Android versionCode to 24');
assert(preset.includes('version/name="0.2.21-native-alpha"'), 'Native version name must be 0.2.21-native-alpha');
for (const key of ['keystore/debug_password', 'keystore/release_password']) {
  const line = preset.split(/\r?\n/).find((entry) => entry.startsWith(`${key}=`));
  assert(line === `${key}=""`, `${key} must stay empty in Git; CI supplies credentials by environment`);
}

// 0.2.21 desktop parity: Windows/Linux export the identical native game.
assert(preset.includes('platform="Windows Desktop"') && preset.includes('name="Windows"'), 'Windows desktop export preset is missing');
assert(preset.includes('platform="Linux"') && preset.includes('name="Linux"'), 'Linux desktop export preset is missing');
assert((preset.match(/include_filter="\*\.json"/g) ?? []).length >= 3, 'Android, Windows and Linux presets must all include the JSON world data');
assert(preset.includes('application/modify_resources=false'), 'Windows export from Linux CI must not require rcedit (application/modify_resources=false)');
assert(preset.includes('binary_format/include_pck=true'), 'Desktop exports must embed the PCK for single-file install-and-play builds');
for (const marker of ['--export-release Windows', '--export-release Linux', '--native-smoke', 'NitchesHorizonNative-windows', 'NitchesHorizonNative-linux']) {
  assert(desktopWorkflow.includes(marker), `Desktop workflow marker is missing: ${marker}`);
}

const combinedRuntime = `${mainScript}\n${worldScript}\n${vehicleScript}\n${hudScript}\n${dynamicWorldScript}\n${speedPostScript}\n${arcadeCarScript}\n${carPaintShader}\n${speedPostShader}\n${wetAsphaltShader}\n${foliageWindShader}\n${curtainWallGlassShader}\n${curtainWallFacadeShader}\n${concreteSurfaceShader}\n${premiumStonePavingShader}`;
for (const marker of ['DesktopControlsHint', 'is_touchscreen_available', 'KEY_F11', '_toggle_desktop_fullscreen', '_ensure_action(&"accelerate"', '_ensure_action(&"boost"', '_ensure_action(&"camera_toggle"']) {
  assert(combinedRuntime.includes(marker), `Native 0.2.21 desktop parity marker is missing: ${marker}`);
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
for (const forbidden of ['WebView', 'Capacitor', 'JavaScriptBridge', 'http://localhost', 'https://localhost']) {
  assert(!combinedRuntime.includes(forbidden), `Native runtime must not contain ${forbidden}`);
}
for (const expectedClass of ['class_name NativeWorldBuilder', 'class_name NativeVehicle', 'class_name NativeHud', 'class_name NativeDynamicWorld', 'class_name NativeSpeedPost', 'class_name NativeArcadeCarAssist']) {
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
  '_coordinates_label',
  '_update_coordinates_label',
  'coordinates_text',
  'coordinates_rect',
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

const data = JSON.parse(dataText);
assert(data.schemaVersion === 1, 'Unexpected native world schema');
assert(data.units === 'metres', 'Native world must use real metres');
assert(data.terrain.heights.length === data.terrain.cols * data.terrain.rows, 'Terrain height count mismatch');
assert(data.bounds.minX === 520 && data.bounds.maxX === 1500, 'RichTown X bounds changed unexpectedly');
assert(data.roads.length >= 35, 'Too few RichTown road edges exported');
assert(data.buildings.length >= 45, 'Too few RichTown buildings exported');
assert(data.buildings.filter((b) => b.model === 'villa').length === 14, 'Expected 14 Blender villas');
assert(data.buildings.filter((b) => b.model === 'glass_tower').length === 8, 'Expected 8 Blender glass towers');
assert(data.landmarks.length === 15, 'Expected all 15 RichTown landmarks');
assert(data.palms.length === 112, 'Expected 112 RichTown palms');
assert(data.spawn.x === 760 && data.spawn.z === 330, 'Unexpected native spawn point');

const detailedCafeInfo = await stat('src/assets/models/props/dubai_premium_cafe.glb');
assert(detailedCafeInfo.size > 2_500_000, 'Native 0.2.19 must use the detailed 2.86 MB PR #61 Dubai Premium Cafe, not the earlier lightweight GLB');
const operaInfo = await stat('src/assets/models/props/opera_house.glb');
assert(operaInfo.size > 250_000, 'Native 0.2.20 RichTown Opera GLB is unexpectedly small');
const operaBytes = await readFile('src/assets/models/props/opera_house.glb');
assert(operaBytes.subarray(0, 4).toString('utf8') === 'glTF', 'RichTown Opera source is an LFS pointer or corrupt GLB');
const operaLandmark = data.landmarks.find((landmark) => landmark.kind === 'rt-opera');
assert(operaLandmark && operaLandmark.x === 820 && operaLandmark.z === 25 && operaLandmark.h === 22, 'RichTown Opera landmark must stay at X820 Z25 with the authored 22 m height');

if (requireAssets) {
  const required = [
    'assets/vehicles/mustang.glb',
    'assets/buildings/villa.glb',
    'assets/buildings/glass_tower.glb',
    'assets/buildings/main_tower.glb',
    'assets/buildings/hero_building.glb',
    'assets/buildings/townhouse.glb',
    'assets/buildings/opera_house.glb',
    'assets/props/street_lamp.glb',
    'assets/props/bus_shelter.glb',
    'assets/props/traffic_signal_short.glb',
    'assets/props/traffic_signal_long.glb',
    'assets/props/dubai_premium_cafe.glb',
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
    'assets/textures/user_mulch_soil.jpg',
    'assets/textures/hedge.jpg',
    'assets/textures/user_sky_day.jpg',
    'assets/textures/user_sky_sunset.jpg',
    'assets/textures/user_sky_night.jpg',
    'assets/textures/cafe_linen.jpg',
    'assets/textures/cafe_linen_normal.png',
  ];
  for (const relative of required) {
    const file = path.join(root, relative);
    const info = await stat(file);
    assert(info.size > 1000, `${file} is unexpectedly small`);
    if (file.endsWith('.glb')) {
      const bytes = await readFile(file);
      assert(bytes.subarray(0, 4).toString('utf8') === 'glTF', `${file} is an LFS pointer or corrupt GLB`);
    }
  }
}

console.log('Native Godot project validation OK');
console.log(JSON.stringify(data.stats, null, 2));
