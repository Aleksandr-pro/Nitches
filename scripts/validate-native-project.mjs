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

const [project, preset, mainScene, dataText, mainScript, worldScript, vehicleScript, hudScript, dynamicWorldScript, speedPostScript, atmosphereFxScript, arcadeCarScript, carPaintShader, speedPostShader, lightShaftShader, horizonSkylineShader, wetAsphaltShader, foliageWindShader, curtainWallGlassShader, curtainWallFacadeShader, concreteSurfaceShader, premiumStonePavingShader, syncScript, blenderScript] = await Promise.all([
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
  readText('scripts/atmosphere_fx.gd'),
  readText('scripts/arcade_car.gd'),
  readText('shaders/car_paint.gdshader'),
  readText('shaders/speed_post.gdshader'),
  readText('shaders/light_shafts.gdshader'),
  readText('shaders/horizon_skyline.gdshader'),
  readText('shaders/wet_asphalt.gdshader'),
  readText('shaders/foliage_wind.gdshader'),
  readText('shaders/curtain_wall_glass.gdshader'),
  readText('shaders/curtain_wall_facade.gdshader'),
  readText('shaders/concrete_surface.gdshader'),
  readText('shaders/premium_stone_paving.gdshader'),
  readFile('scripts/sync-native-assets.mjs', 'utf8'),
  readFile('blender/build_props.py', 'utf8'),
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
assert(preset.includes('version/code=22'), 'Native 0.2.19 must bump Android versionCode to 22');
assert(preset.includes('version/name="0.2.19-native-alpha"'), 'Native version name must be 0.2.19-native-alpha');
for (const key of ['keystore/debug_password', 'keystore/release_password']) {
  const line = preset.split(/\r?\n/).find((entry) => entry.startsWith(`${key}=`));
  assert(line === `${key}=""`, `${key} must stay empty in Git; CI supplies credentials by environment`);
}

const combinedRuntime = `${mainScript}\n${worldScript}\n${vehicleScript}\n${hudScript}\n${dynamicWorldScript}\n${speedPostScript}\n${atmosphereFxScript}\n${arcadeCarScript}\n${carPaintShader}\n${speedPostShader}\n${lightShaftShader}\n${horizonSkylineShader}\n${wetAsphaltShader}\n${foliageWindShader}\n${curtainWallGlassShader}\n${curtainWallFacadeShader}\n${concreteSurfaceShader}\n${premiumStonePavingShader}`;
const skylineSourceFiles = [
  'src/assets/textures/realworld/skyline_rich_town_near.png',
  'src/assets/textures/realworld/skyline_rich_town_far.png',
];
for (const file of skylineSourceFiles) {
  const bytes = await readFile(file);
  assert(bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])), `${file} is not a PNG`);
  assert(bytes.readUInt32BE(16) === 4096 && bytes.readUInt32BE(20) === 512, `${file} must be a 4096x512 skyline panorama`);
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
for (const marker of ['stone_texture', 'fine_normal_texture', 'dominant_plane', 'district_variation', 'polished_wear', 'PremiumStone']) {
  assert(premiumStonePavingShader.includes(marker) || worldScript.includes(marker), `Native 0.2.18 premium stone paving marker is missing: ${marker}`);
}
for (const vegetationModel of ['palm_date.glb', 'palm_royal.glb', 'grass_tuft.glb', 'flower_clump.glb', 'ornamental_shrub.glb']) {
  assert(syncScript.includes(vegetationModel), `Native asset sync is missing ${vegetationModel}`);
  assert(worldScript.includes(`res://assets/vegetation/${vegetationModel}`), `Native world does not load ${vegetationModel}`);
}
assert(syncScript.includes('user_sand_beach_white.jpg'), 'Native asset sync is missing the 0.2.18 white-pebble texture');
for (const skylineTexture of ['skyline_rich_town_near.png', 'skyline_rich_town_far.png']) {
  assert(syncScript.includes(skylineTexture), `Native asset sync is missing ${skylineTexture}`);
}
for (const marker of ['def build_palm_date():', 'def build_palm_royal():', 'def build_grass_tuft():', 'def build_flower_clump():', 'def build_ornamental_shrub():']) {
  assert(blenderScript.includes(marker), `Blender vegetation builder is missing: ${marker}`);
}
for (const forbidden of ['WebView', 'Capacitor', 'JavaScriptBridge', 'http://localhost', 'https://localhost']) {
  assert(!combinedRuntime.includes(forbidden), `Native runtime must not contain ${forbidden}`);
}
for (const expectedClass of ['class_name NativeWorldBuilder', 'class_name NativeVehicle', 'class_name NativeHud', 'class_name NativeDynamicWorld', 'class_name NativeSpeedPost', 'class_name NativeAtmosphereFX', 'class_name NativeArcadeCarAssist']) {
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
  'DriftingLeaves',
  'GoldenPetals',
  'RoadWakeDust',
  'HeadlightBokehLayer',
  'headlight_bokeh',
  'get_foliage_density_at',
  'foliage_gate',
  'skyline_rich_town_near.png',
  'skyline_rich_town_far.png',
  'skyline_tex',
  'VISIBILITY_RANGE_FADE_SELF',
  'near_field_lod_0219',
  'rich_town_vertical_slice_0219',
  'golden_hour',
  'wet_streak',
  'HandbrakeTireSparks',
  'SpeedWindAudio',
  'light_shafts.gdshader',
  'shaft_intensity',
  'HorizonSkyline',
  'skyline_density',
  'skyline_follows_vehicle',
  'get_effect_state',
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
  'ripple_weight',
  'ReflectionProbe.UPDATE_ONCE',
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
  'premium_boulevard_paving',
  'boulevard_cafes',
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
  'boulevard_granite_curbs',
  'boulevard_premium_sidewalk_slabs',
  'boulevard_fresh_markings',
  'boulevard_arcades',
  'boulevard_cafe_tables',
  'boulevard_cafe_umbrellas',
  'boulevard_drip_emitters',
  'boulevard_royal_palms',
  'boulevard_extra_royal_palms',
  'boulevard_lawn_area_m2',
  'boulevard_topiary',
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
  assert(combinedRuntime.includes(marker), `Native 0.2.18 marker is missing: ${marker}`);
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

if (requireAssets) {
  const required = [
    'assets/vehicles/mustang.glb',
    'assets/buildings/villa.glb',
    'assets/buildings/glass_tower.glb',
    'assets/buildings/main_tower.glb',
    'assets/buildings/hero_building.glb',
    'assets/buildings/townhouse.glb',
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
    'assets/textures/skyline_rich_town_near.png',
    'assets/textures/skyline_rich_town_far.png',
  ];
  for (const relative of required) {
    const file = path.join(root, relative);
    const info = await stat(file);
    assert(info.size > 1000, `${file} is unexpectedly small`);
    if (file.endsWith('.glb')) {
      const bytes = await readFile(file);
      assert(bytes.subarray(0, 4).toString('utf8') === 'glTF', `${file} is an LFS pointer or corrupt GLB`);
    }
    if (file.includes('skyline_rich_town_')) {
      const bytes = await readFile(file);
      assert(bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])), `${file} is not a PNG`);
      assert(bytes.readUInt32BE(16) === 4096 && bytes.readUInt32BE(20) === 512, `${file} must be a 4096x512 skyline panorama`);
    }
  }
}

console.log('Native Godot project validation OK');
console.log(JSON.stringify(data.stats, null, 2));
