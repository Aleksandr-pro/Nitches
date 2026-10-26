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

const [project, preset, mainScene, dataText, mainScript, worldScript, vehicleScript, hudScript, dynamicWorldScript, speedPostScript, arcadeCarScript, carPaintShader, speedPostShader, wetAsphaltShader, foliageWindShader] = await Promise.all([
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
assert(preset.includes('version/code=8'), 'Native 0.2.5 must bump Android versionCode to 8');
assert(preset.includes('version/name="0.2.5-native-alpha"'), 'Native version name must be 0.2.5-native-alpha');
for (const key of ['keystore/debug_password', 'keystore/release_password']) {
  const line = preset.split(/\r?\n/).find((entry) => entry.startsWith(`${key}=`));
  assert(line === `${key}=""`, `${key} must stay empty in Git; CI supplies credentials by environment`);
}

const combinedRuntime = `${mainScript}\n${worldScript}\n${vehicleScript}\n${hudScript}\n${dynamicWorldScript}\n${speedPostScript}\n${arcadeCarScript}\n${carPaintShader}\n${speedPostShader}\n${wetAsphaltShader}\n${foliageWindShader}`;
assert(!combinedRuntime.includes('NativeTrafficManager') && !combinedRuntime.includes('traffic_manager.gd') && !mainScript.includes('TrafficScript'), 'Native 0.2.5 must not load any traffic-car system');
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
  'WetAsphaltShader',
  'FoliageWindShader',
  'get_road_visual_state',
  'ground_winding_godot_cw',
  'user_asphalt_plain.jpg',
  'road_edge_lines',
  'lane_dashes',
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
  assert(combinedRuntime.includes(marker), `Native 0.2.5 marker is missing: ${marker}`);
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
    'assets/buildings/hero_building.glb',
    'assets/buildings/townhouse.glb',
    'assets/props/street_lamp.glb',
    'assets/props/bus_shelter.glb',
    'assets/vegetation/plants.glb',
    'assets/textures/user_asphalt_dashed.jpg',
    'assets/textures/user_asphalt_plain.jpg',
    'assets/textures/user_asphalt_plain_normal.jpg',
    'assets/textures/user_water_turquoise.jpg',
    'assets/textures/user_sky_day.jpg',
    'assets/textures/user_sky_sunset.jpg',
    'assets/textures/user_sky_night.jpg',
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
