class_name NativeWorldBuilder
extends Node3D

## Builds the first native RichTown district from engine-neutral JSON data.
## All runtime geometry, materials, collision and lighting are created by
## Godot itself.  The world uses real metres and keeps the legacy data
## coordinates (x 520..1500, z -500..500) so later streaming chunks can use
## exactly the same placement data.

const WORLD_DATA_PATH := "res://data/richtown_native.json"
const DynamicWorldScript := preload("res://scripts/dynamic_world.gd")
const WetAsphaltShader: Shader = preload("res://shaders/wet_asphalt.gdshader")
const WaterSurfaceShader: Shader = preload("res://shaders/water_surface.gdshader")
const FoliageWindShader: Shader = preload("res://shaders/foliage_wind.gdshader")
const CurtainWallGlassShader: Shader = preload("res://shaders/curtain_wall_glass.gdshader")
const CurtainWallFacadeShader: Shader = preload("res://shaders/curtain_wall_facade.gdshader")
const TEXTURE_DIR := "res://assets/textures/"
const WORLD_AABB := AABB(Vector3(500.0, -20.0, -540.0), Vector3(1040.0, 420.0, 1080.0))
const FALLBACK_SPAWN_POSITION := Vector3(760.0, 5.205, 330.0)
const MULTIMESH_CHUNK_SIZE_M := 220.0
const ROAD_GRID_CELL_M := 40.0
const ROAD_GRID_QUERY_CLEARANCE_M := 10.0
const ROAD_SURFACE_OFFSET_M := 0.095
const ROAD_CROWN_M := 0.045

var data: Dictionary = {}
var spawn_transform := Transform3D.IDENTITY
var time_of_day := "day"
var build_error := ""
var is_built := false

var _terrain: Dictionary = {}
var _textures: Dictionary = {}
var _materials: Dictionary = {}
var _model_parts_cache: Dictionary = {}
var _plant_parts: Dictionary = {}
var _terrain_meshes: Dictionary = {}
var _road_mesh: ArrayMesh
var _sidewalk_mesh: ArrayMesh
var _asphalt_material: ShaderMaterial
var _curtain_glass_materials: Array[ShaderMaterial] = []
var _palm_leaf_shader_material: ShaderMaterial
var _foliage_wind_materials: Array[ShaderMaterial] = []
var _water_materials: Array[StandardMaterial3D] = []
var _sea_material: ShaderMaterial
var _night_materials: Array[Dictionary] = []
var _collision_root: StaticBody3D
var _sun: DirectionalLight3D
var _environment: Environment
var _sky: Sky
var _procedural_sky_material: ProceduralSkyMaterial
var _panorama_sky_material: PanoramaSkyMaterial
var _physical_sky_material: PhysicalSkyMaterial
var _dynamic_world: NativeDynamicWorld
var _road_segment_starts: Array[Vector3] = []
var _road_segment_ends: Array[Vector3] = []
var _road_segment_half_widths: Array[float] = []
var _road_segment_grid: Dictionary = {}
var _multimesh_chunk_count := 0
var _pending_batched_models: Dictionary = {}
var _far_proxy_sphere_mesh: SphereMesh
var _infill_buildings: Array[Dictionary] = []
var _reflection_probes: Array[ReflectionProbe] = []
var _enhancement_stats: Dictionary = {}
var _reflection_probe_refresh_sign := 1.0
var _gable_mesh: ArrayMesh
var _palm_crown_mesh: ArrayMesh
var _sail_mesh: ArrayMesh
var _elapsed := 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	if _sea_material != null:
		_sea_material.set_shader_parameter("wave_time", _elapsed)
	for i in _water_materials.size():
		var material := _water_materials[i]
		var speed := 0.018 if i == 0 else 0.026
		material.uv1_offset = Vector3(
			fmod(_elapsed * speed, 1.0),
			fmod(_elapsed * speed * 0.63, 1.0),
			0.0
		)


func build_world() -> Dictionary:
	if is_built:
		return get_stats() if build_error.is_empty() else {"error": build_error}

	_load_data()
	if data.is_empty():
		if build_error.is_empty():
			build_error = "Native world data could not be loaded"
		spawn_transform = make_transform(FALLBACK_SPAWN_POSITION, 0.0, Vector3.ONE)
		_create_collision_root()
		_build_environment()
		_build_emergency_spawn_pad()
		set_time_of_day("day")
		is_built = true
		return {"error": build_error}

	_terrain = data.get("terrain", {})
	_compute_spawn_transform()
	_build_road_surface_index()
	_create_collision_root()
	_build_environment()
	_build_terrain()
	_build_water_and_pools()
	_build_roads()
	_build_buildings()
	_build_landmarks()
	_build_vegetation()
	_build_street_lamps()
	_build_bus_shelters()
	_build_benches()
	_build_city_details()
	_flush_batched_models()
	_build_reflection_probes()
	_build_world_bounds()
	set_time_of_day("day")
	is_built = true
	return get_stats()


func get_stats() -> Dictionary:
	var stats: Dictionary = data.get("stats", {})
	return stats.duplicate(true)


func get_world_data() -> Dictionary:
	return data


func has_world_data() -> bool:
	return build_error.is_empty() and not data.is_empty()


func get_enhancement_stats() -> Dictionary:
	return _enhancement_stats.duplicate(true)


func get_dynamic_world_state() -> Dictionary:
	if _dynamic_world == null:
		return {"presets": 0, "mode": time_of_day, "preset": "", "physical_sky": false}
	return _dynamic_world.get_smoke_state()


func _mesh_winding_cross_y(mesh: Mesh) -> float:
	# Godot treats clockwise triangles as front-facing. For an upward XZ
	# surface this means (b-a) x (c-a) must point DOWN (negative Y), even
	# though the shading normal points up. The 0.2.1 phone screenshot proved
	# why this matters: the previous positive-Y winding made the renderer
	# cull the whole terrain/road from above and showed the sky panorama's
	# lower hemisphere instead of the ground.
	if mesh == null or mesh.get_surface_count() == 0:
		return 0.0
	var arrays := mesh.surface_get_arrays(0)
	if arrays.size() <= Mesh.ARRAY_VERTEX:
		return 0.0
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	if vertices.size() < 3:
		return 0.0
	var indices := PackedInt32Array()
	if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var triangle_count := int(indices.size() / 3) if not indices.is_empty() else int(vertices.size() / 3)
	var sampled := mini(triangle_count, 32)
	var total := 0.0
	var valid := 0
	for triangle in sampled:
		var ia := triangle * 3
		var ib := triangle * 3 + 1
		var ic := triangle * 3 + 2
		if not indices.is_empty():
			ia = indices[ia]
			ib = indices[ib]
			ic = indices[ic]
		if ia < 0 or ib < 0 or ic < 0 or ia >= vertices.size() or ib >= vertices.size() or ic >= vertices.size():
			continue
		var a := vertices[ia]
		var cross_y := (vertices[ib] - a).cross(vertices[ic] - a).y
		if absf(cross_y) > 0.0001:
			total += cross_y
			valid += 1
	return total / float(valid) if valid > 0 else 0.0


func get_road_visual_state() -> Dictionary:
	var asphalt_textures := false
	var asphalt_wear_texture := false
	var asphalt_wetness := -1.0
	if _asphalt_material != null:
		asphalt_textures = bool(_asphalt_material.get_shader_parameter("use_textures"))
		asphalt_wear_texture = bool(_asphalt_material.get_shader_parameter("use_wear_texture"))
		asphalt_wetness = float(_asphalt_material.get_shader_parameter("wetness"))
	var terrain_cross_y := 0.0
	for kind in ["concrete", "plaza", "grass", "sand", "rock"]:
		var candidate := _mesh_winding_cross_y(_terrain_meshes.get(kind) as Mesh)
		if absf(candidate) > 0.0001:
			terrain_cross_y = candidate
			break
	var road_cross_y := _mesh_winding_cross_y(_road_mesh)
	return {
		"asphalt_shader": _asphalt_material != null and _asphalt_material.shader == WetAsphaltShader,
		"asphalt_textures": asphalt_textures,
		"asphalt_wear_texture": asphalt_wear_texture,
		"asphalt_layers": 3 if asphalt_textures and asphalt_wear_texture else 1,
		"road_crown_m": ROAD_CROWN_M,
		"road_surface_offset_m": ROAD_SURFACE_OFFSET_M,
		"asphalt_wetness": asphalt_wetness,
		"terrain_cross_y": terrain_cross_y,
		"road_cross_y": road_cross_y,
		"ground_winding_godot_cw": terrain_cross_y < 0.0 and road_cross_y < 0.0,
		"terrain_meshes": _terrain_meshes.size(),
		"road_mesh_ready": _road_mesh != null,
		"foliage_wind_materials": _foliage_wind_materials.size(),
		"multimesh_chunks": _multimesh_chunk_count,
		"multimesh_chunk_size_m": MULTIMESH_CHUNK_SIZE_M,
		"road_grid_cells": _road_segment_grid.size(),
		"road_segments": _road_segment_starts.size(),
	}


func _road_grid_cell(x: float, z: float) -> Vector2i:
	return Vector2i(
		floori((x - WORLD_AABB.position.x) / ROAD_GRID_CELL_M),
		floori((z - WORLD_AABB.position.z) / ROAD_GRID_CELL_M)
	)


func _build_road_surface_index() -> void:
	_road_segment_starts.clear()
	_road_segment_ends.clear()
	_road_segment_half_widths.clear()
	_road_segment_grid.clear()
	var grid_entries := 0
	for road_variant in data.get("roads", []):
		var road: Dictionary = road_variant
		var samples: Array = road.get("samples", [])
		var half_width := _f(road, "widthM", 10.0) * 0.5
		for i in range(samples.size() - 1):
			var a := _sample_point(samples[i])
			var b := _sample_point(samples[i + 1])
			if Vector2(b.x - a.x, b.z - a.z).length_squared() < 0.0001:
				continue
			var segment_index := _road_segment_starts.size()
			_road_segment_starts.append(a)
			_road_segment_ends.append(b)
			_road_segment_half_widths.append(half_width)

			# The old lookup scanned all 1085 road segments for every tyre,
			# every physics tick. This uniform grid contains every segment
			# that can possibly be within the largest clearance threshold
			# used by the game (10 m), so surface/clearance decisions stay
			# exact while the per-wheel candidate set becomes tiny.
			var expand := half_width + ROAD_GRID_QUERY_CLEARANCE_M + 0.5
			var min_cell := _road_grid_cell(minf(a.x, b.x) - expand, minf(a.z, b.z) - expand)
			var max_cell := _road_grid_cell(maxf(a.x, b.x) + expand, maxf(a.z, b.z) + expand)
			for cell_x in range(min_cell.x, max_cell.x + 1):
				for cell_z in range(min_cell.y, max_cell.y + 1):
					var cell := Vector2i(cell_x, cell_z)
					if not _road_segment_grid.has(cell):
						_road_segment_grid[cell] = []
					(_road_segment_grid[cell] as Array).append(segment_index)
					grid_entries += 1
	_enhancement_stats["road_grid_cells"] = _road_segment_grid.size()
	_enhancement_stats["road_grid_entries"] = grid_entries
	_enhancement_stats["road_segments"] = _road_segment_starts.size()


func _distance_to_segment_xz(point: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(point.x - a.x, point.z - a.z)
	var length_squared := ab.length_squared()
	if length_squared <= 0.0001:
		return ap.length()
	var t := clampf(ap.dot(ab) / length_squared, 0.0, 1.0)
	return ap.distance_to(ab * t)


func _road_clearance_xz(point: Vector3) -> float:
	# Only thresholds up to ROAD_GRID_QUERY_CLEARANCE_M are consumed by
	# get_surface_at()/_is_position_clear(). Returning that cap for an empty
	# cell is therefore decision-identical to the old full scan, without
	# paying for 1085 distance checks per tyre contact.
	if _road_segment_grid.is_empty():
		return ROAD_GRID_QUERY_CLEARANCE_M
	var candidates: Array = _road_segment_grid.get(_road_grid_cell(point.x, point.z), [])
	if candidates.is_empty():
		return ROAD_GRID_QUERY_CLEARANCE_M
	var best_clearance := ROAD_GRID_QUERY_CLEARANCE_M
	for index_variant in candidates:
		var i := int(index_variant)
		var clearance := _distance_to_segment_xz(point, _road_segment_starts[i], _road_segment_ends[i]) - _road_segment_half_widths[i]
		best_clearance = minf(best_clearance, clearance)
	return best_clearance


func _is_position_clear(point: Vector3, building_padding: float, minimum_road_clearance: float) -> bool:
	if _road_clearance_xz(point) < minimum_road_clearance:
		return false
	for building_variant in data.get("buildings", []):
		var building: Dictionary = building_variant
		var center := _item_position(building)
		var local := Basis(Vector3.UP, -_f(building, "rotY")) * (point - center)
		if absf(local.x) <= _f(building, "w", 20.0) * 0.5 + building_padding and absf(local.z) <= _f(building, "d", 16.0) * 0.5 + building_padding:
			return false
	for landmark_variant in data.get("landmarks", []):
		var landmark: Dictionary = landmark_variant
		var center := _item_position(landmark)
		var radius := maxf(_f(landmark, "r", 18.0), 14.0) + building_padding
		if Vector2(point.x - center.x, point.z - center.z).length_squared() < radius * radius:
			return false
	return true


## Returns the driving surface used by the tyre model.  Roads always win
## over the underlying terrain class, which makes bridges and causeways
## behave as asphalt instead of water/grass.
func get_surface_at(world_position: Vector3) -> Dictionary:
	var clearance := _road_clearance_xz(world_position)
	if clearance <= 0.0:
		return {"kind": "asphalt", "label": "АСФАЛЬТ", "mu": 1.16, "rolling_resistance": 0.014}
	if clearance <= 2.05:
		return {"kind": "sidewalk", "label": "БЕТОН", "mu": 0.93, "rolling_resistance": 0.021}

	var h := height_at(world_position.x, world_position.z)
	if ((_in_zone(world_position.x, world_position.z, "sea") or _in_zone(world_position.x, world_position.z, "marina")) and h < 0.45) or world_position.y < 0.18:
		return {"kind": "water", "label": "ВОДА", "mu": 0.27, "rolling_resistance": 0.19}

	var sample_step := 5.0
	var slope := maxf(
		absf(height_at(world_position.x + sample_step, world_position.z) - h),
		absf(height_at(world_position.x, world_position.z + sample_step) - h)
	) / sample_step
	var min_x := _f(_terrain, "minX", 520.0)
	var min_z := _f(_terrain, "minZ", -500.0)
	var step := maxf(_f(_terrain, "stepM", 10.0), 1.0)
	var ix := clampi(int(floor((world_position.x - min_x) / step)), 0, int(_terrain.get("cols", 2)) - 1)
	var iz := clampi(int(floor((world_position.z - min_z) / step)), 0, int(_terrain.get("rows", 2)) - 1)
	match _terrain_class(world_position.x, world_position.z, h, slope, ix, iz):
		"sand":
			return {"kind": "sand", "label": "ПЕСОК", "mu": 0.57, "rolling_resistance": 0.115}
		"rock":
			return {"kind": "rock", "label": "КАМЕНЬ", "mu": 0.74, "rolling_resistance": 0.052}
		"concrete":
			return {"kind": "concrete", "label": "БЕТОН", "mu": 0.89, "rolling_resistance": 0.024}
		"plaza":
			return {"kind": "plaza", "label": "КАМЕНЬ", "mu": 0.86, "rolling_resistance": 0.026}
		_:
			return {"kind": "grass", "label": "ГРУНТ", "mu": 0.62, "rolling_resistance": 0.078}


func get_district_name(world_position: Vector3) -> String:
	var best_name := "RichTown"
	var best_score := INF
	for district_variant in data.get("districts", []):
		var district: Dictionary = district_variant
		var center := Vector2(_f(district, "x"), _f(district, "z"))
		var point := Vector2(world_position.x, world_position.z)
		var radius := maxf(_f(district, "radiusM", 200.0), 1.0)
		var score := center.distance_to(point) / radius
		if score < best_score:
			best_score = score
			best_name = String(district.get("name", best_name))
	return best_name


func height_at(x: float, z: float) -> float:
	if _terrain.is_empty():
		return 0.0
	var cols := int(_terrain.get("cols", 0))
	var rows := int(_terrain.get("rows", 0))
	if cols < 2 or rows < 2:
		return 0.0
	var min_x := _f(_terrain, "minX", 520.0)
	var min_z := _f(_terrain, "minZ", -500.0)
	var step := _f(_terrain, "stepM", 10.0)
	var fx := clampf((x - min_x) / step, 0.0, float(cols - 1))
	var fz := clampf((z - min_z) / step, 0.0, float(rows - 1))
	var ix := mini(int(floor(fx)), cols - 2)
	var iz := mini(int(floor(fz)), rows - 2)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var h00 := _grid_height(ix, iz)
	var h10 := _grid_height(ix + 1, iz)
	var h01 := _grid_height(ix, iz + 1)
	var h11 := _grid_height(ix + 1, iz + 1)
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func find_nearest_road_transform(world_position: Vector3) -> Transform3D:
	var best_point := Vector3(world_position.x, height_at(world_position.x, world_position.z) + 1.1, world_position.z)
	var best_direction := Vector3(0.0, 0.0, -1.0)
	var best_distance_squared := INF

	for road_variant in data.get("roads", []):
		var road: Dictionary = road_variant
		var samples: Array = road.get("samples", [])
		for i in range(samples.size() - 1):
			var a := _sample_point(samples[i])
			var b := _sample_point(samples[i + 1])
			var ab := b - a
			var length_squared := ab.length_squared()
			if length_squared <= 0.0001:
				continue
			var t := clampf((world_position - a).dot(ab) / length_squared, 0.0, 1.0)
			var candidate := a + ab * t
			var distance_squared := Vector2(world_position.x - candidate.x, world_position.z - candidate.z).length_squared()
			if distance_squared < best_distance_squared:
				best_distance_squared = distance_squared
				best_point = candidate + Vector3.UP * 1.1
				best_direction = ab.normalized()

	var yaw := atan2(-best_direction.x, -best_direction.z)
	return make_transform(best_point, yaw, Vector3.ONE)


func make_transform(position_value: Vector3, yaw: float = 0.0, scale_value: Vector3 = Vector3.ONE) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(scale_value), position_value)


func _apply_sky_mode(mode: String) -> void:
	if _sky == null or _procedural_sky_material == null or _panorama_sky_material == null:
		return
	var texture_file := "user_sky_day.jpg"
	var panorama_energy := 1.08
	match mode:
		"sunset":
			texture_file = "user_sky_sunset.jpg"
			panorama_energy = 1.02
			_procedural_sky_material.sky_top_color = Color(0.16, 0.30, 0.59)
			_procedural_sky_material.sky_horizon_color = Color(1.0, 0.58, 0.32)
			_procedural_sky_material.ground_bottom_color = Color(0.16, 0.11, 0.10)
			_procedural_sky_material.ground_horizon_color = Color(0.77, 0.43, 0.30)
			_procedural_sky_material.sky_energy_multiplier = 1.15
		"night":
			texture_file = "user_sky_night.jpg"
			panorama_energy = 0.62
			_procedural_sky_material.sky_top_color = Color(0.008, 0.016, 0.055)
			_procedural_sky_material.sky_horizon_color = Color(0.055, 0.10, 0.22)
			_procedural_sky_material.ground_bottom_color = Color(0.005, 0.008, 0.02)
			_procedural_sky_material.ground_horizon_color = Color(0.03, 0.05, 0.11)
			_procedural_sky_material.sky_energy_multiplier = 0.55
		_:
			_procedural_sky_material.sky_top_color = Color(0.12, 0.42, 0.83)
			_procedural_sky_material.sky_horizon_color = Color(0.62, 0.82, 0.98)
			_procedural_sky_material.ground_bottom_color = Color(0.13, 0.17, 0.16)
			_procedural_sky_material.ground_horizon_color = Color(0.55, 0.66, 0.70)
			_procedural_sky_material.sky_energy_multiplier = 1.25

	var panorama := _texture(texture_file)
	if panorama != null:
		_panorama_sky_material.panorama = panorama
		_panorama_sky_material.energy_multiplier = panorama_energy
		_sky.sky_material = _panorama_sky_material
	elif _physical_sky_material != null:
		# DynamicWorld fallback: физическое небо лучше простого градиента,
		# если панорама вдруг не попала в экспорт.
		_sky.sky_material = _physical_sky_material
	else:
		_sky.sky_material = _procedural_sky_material


func set_time_of_day(mode: String) -> void:
	time_of_day = mode
	if _sun == null or _environment == null or _sky == null:
		return
	_apply_sky_mode(mode)

	match mode:
		"sunset":
			_sun.rotation_degrees = Vector3(-17.0, -112.0, 0.0)
			_sun.light_color = Color(1.0, 0.58, 0.34)
			_sun.light_energy = 1.85
			_sun.shadow_opacity = 0.62
			_environment.background_energy_multiplier = 0.95
			_environment.ambient_light_energy = 0.62
			_environment.tonemap_exposure = 1.08
			_environment.fog_light_color = Color(0.98, 0.67, 0.48)
			_environment.fog_light_energy = 1.05
			_environment.fog_density = 0.00065
			_environment.fog_sun_scatter = 0.48
			_environment.fog_aerial_perspective = 0.42
		"night":
			_sun.rotation_degrees = Vector3(-63.0, 38.0, 0.0)
			_sun.light_color = Color(0.63, 0.74, 1.0)
			_sun.light_energy = 0.42
			_sun.shadow_opacity = 0.48
			_environment.background_energy_multiplier = 0.24
			_environment.ambient_light_energy = 0.34
			_environment.tonemap_exposure = 0.92
			_environment.fog_light_color = Color(0.05, 0.08, 0.16)
			_environment.fog_light_energy = 0.55
			_environment.fog_density = 0.00085
			_environment.fog_sun_scatter = 0.08
			_environment.fog_aerial_perspective = 0.24
		_:
			_sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
			_sun.light_color = Color(1.0, 0.94, 0.84)
			_sun.light_energy = 2.55
			_sun.shadow_opacity = 0.74
			_environment.background_energy_multiplier = 1.2
			_environment.ambient_light_energy = 0.82
			_environment.tonemap_exposure = 1.04
			_environment.fog_light_color = Color(0.68, 0.82, 0.96)
			_environment.fog_light_energy = 0.92
			_environment.fog_density = 0.00045
			_environment.fog_sun_scatter = 0.28
			_environment.fog_aerial_perspective = 0.38

	# DynamicWorld из Drive-базы доводит ACES/bloom/цветокор и плотность
	# тумана по своим пресетам (CLEAR_DAY днём, GOLDEN_HOUR на закате),
	# не заменяя панорамы неба и не трогая ночные материалы RichTown.
	if _dynamic_world != null:
		_dynamic_world.apply_mode(mode, _environment, _sun)
		_enhancement_stats["dynamic_world_presets"] = _dynamic_world.get_preset_count()
		_enhancement_stats["dynamic_world_preset"] = _dynamic_world.get_current_preset_name()
		_enhancement_stats["glow_enabled"] = _environment.glow_enabled
		_enhancement_stats["mobile_performance_mode"] = OS.has_feature("android")

	if _asphalt_material != null:
		var wetness := 0.12
		if mode == "sunset":
			wetness = 0.20
		elif mode == "night":
			wetness = 0.18
		_asphalt_material.set_shader_parameter("wetness", wetness)
		_enhancement_stats["asphalt_wetness"] = wetness

	var curtain_light_strength := 0.0
	if mode == "sunset":
		curtain_light_strength = 0.12
	elif mode == "night":
		curtain_light_strength = 0.90
	for curtain_material in _curtain_glass_materials:
		curtain_material.set_shader_parameter("interior_light_strength", curtain_light_strength)
	_enhancement_stats["curtain_wall_interior_light_strength"] = curtain_light_strength

	for entry in _night_materials:
		var material := entry.get("material") as StandardMaterial3D
		if material == null:
			continue
		material.emission_energy_multiplier = float(entry.get(mode, entry.get("day", 0.0)))

	# UPDATE_ONCE probes recapture when nudged, keeping car paint and glass
	# reflections in sync with day/sunset/night without an UPDATE_ALWAYS cost.
	if not _reflection_probes.is_empty():
		_reflection_probe_refresh_sign = -_reflection_probe_refresh_sign
		for probe in _reflection_probes:
			probe.position.y += 0.01 * _reflection_probe_refresh_sign


func _load_data() -> void:
	build_error = ""
	if not FileAccess.file_exists(WORLD_DATA_PATH):
		build_error = "Native world data is missing from the exported game: %s" % WORLD_DATA_PATH
		push_error(build_error)
		return
	var file := FileAccess.open(WORLD_DATA_PATH, FileAccess.READ)
	if file == null:
		build_error = "Native world data could not be opened: %s" % WORLD_DATA_PATH
		push_error(build_error)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		build_error = "Native world data is not a JSON dictionary"
		push_error(build_error)
		return
	data = parsed


func _f(source: Dictionary, key: String, fallback: float = 0.0) -> float:
	return float(source.get(key, fallback))


func _item_position(item: Dictionary, y_offset: float = 0.0) -> Vector3:
	var x := _f(item, "x")
	var z := _f(item, "z")
	var y := float(item.get("y", height_at(x, z)))
	return Vector3(x, y + y_offset, z)


func _sample_point(sample_variant: Variant) -> Vector3:
	var sample: Array = sample_variant
	if sample.size() < 3:
		return Vector3.ZERO
	return Vector3(float(sample[0]), float(sample[1]), float(sample[2]))


func _compute_spawn_transform() -> void:
	var spawn: Dictionary = data.get("spawn", {})
	spawn_transform = make_transform(_item_position(spawn), _f(spawn, "yaw"), Vector3.ONE)


func _build_emergency_spawn_pad() -> void:
	# This pad is deliberately only a fail-safe for a broken export: it keeps
	# the car and camera usable while the HUD reports the missing world data.
	var root := Node3D.new()
	root.name = "EmergencySpawnPad"
	add_child(root)
	var center := Vector3(FALLBACK_SPAWN_POSITION.x, FALLBACK_SPAWN_POSITION.y - 0.11, FALLBACK_SPAWN_POSITION.z)
	var asphalt := _material(
		"emergency_asphalt",
		"user_asphalt_plain.jpg",
		"user_asphalt_plain_normal.jpg",
		Color(0.42, 0.44, 0.46),
		0.92,
		0.0,
		Vector3(24.0, 24.0, 1.0),
		true
	)
	_add_box(root, Vector3(140.0, 0.22, 140.0), center, asphalt, 0.0, "EmergencyGround")
	_add_box_collider(center, Vector3(140.0, 0.22, 140.0))
	var edge := _material("emergency_edge", "", "", Color(1.0, 0.45, 0.05), 0.72)
	for side in [-1.0, 1.0]:
		_add_box(
			root,
			Vector3(0.45, 0.08, 118.0),
			Vector3(center.x + side * 9.0, FALLBACK_SPAWN_POSITION.y + 0.03, center.z),
			edge,
			0.0,
			"EmergencyRoadEdge"
		)


func _create_collision_root() -> void:
	_collision_root = StaticBody3D.new()
	_collision_root.name = "WorldColliders"
	_collision_root.collision_layer = 1
	_collision_root.collision_mask = 0
	add_child(_collision_root)


func _add_box_collider(center: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	if _collision_root == null:
		return
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = make_transform(center, yaw, Vector3.ONE)
	_collision_root.add_child(collision)


func _add_cylinder_collider(center: Vector3, radius: float, height: float) -> void:
	if _collision_root == null:
		return
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = center
	_collision_root.add_child(collision)


func _build_environment() -> void:
	_dynamic_world = DynamicWorldScript.new() as NativeDynamicWorld
	_dynamic_world.name = "DynamicWorld"
	add_child(_dynamic_world)
	_physical_sky_material = _dynamic_world.get_physical_sky_material()
	_enhancement_stats["dynamic_world_presets"] = _dynamic_world.get_preset_count()

	_procedural_sky_material = ProceduralSkyMaterial.new()
	_procedural_sky_material.sky_curve = 0.12
	_procedural_sky_material.ground_curve = 0.08
	_procedural_sky_material.sun_angle_max = 28.0
	_procedural_sky_material.sun_curve = 0.08

	_panorama_sky_material = PanoramaSkyMaterial.new()
	_panorama_sky_material.filter = true

	_sky = Sky.new()
	_sky.sky_material = _procedural_sky_material
	_sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
	_sky.radiance_size = Sky.RADIANCE_SIZE_256 if OS.has_feature("android") else Sky.RADIANCE_SIZE_512

	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = _sky
	_environment.sky_custom_fov = 0.0
	_environment.sky_rotation = Vector3.ZERO
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_environment.ambient_light_sky_contribution = 0.88
	_environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	_environment.glow_enabled = not OS.has_feature("android")
	_environment.glow_intensity = 1.18
	_environment.glow_strength = 0.86
	_environment.glow_bloom = 0.055
	_environment.glow_hdr_threshold = 0.9
	_environment.set_glow_level(1, 0.35)
	_environment.set_glow_level(2, 0.65)
	_environment.set_glow_level(3, 0.45)
	_environment.fog_enabled = true
	_environment.fog_sky_affect = 0.28
	_environment.adjustment_enabled = true
	_environment.adjustment_brightness = 1.02
	_environment.adjustment_contrast = 1.045
	_environment.adjustment_saturation = 1.055

	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = _environment
	add_child(world_environment)

	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.shadow_enabled = true
	_sun.light_angular_distance = 0.45
	_sun.shadow_bias = 0.045
	_sun.shadow_normal_bias = 1.65
	_sun.shadow_blur = 1.15
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	# 0.2.15 phone budget: the 0.2.14 captures cost 84-119 ms CPU per frame
	# with physics at only ~5 ms, so the render submission itself is the
	# bottleneck. Two splits now cover 175 m: the player, junctions and the
	# buildings that can actually shade the road keep real shadows, while
	# far districts stop paying two extra shadow submissions.
	_sun.directional_shadow_max_distance = 175.0
	_enhancement_stats["shadow_max_distance"] = 175.0
	_enhancement_stats["shadow_splits"] = 2
	_sun.directional_shadow_split_1 = 0.12
	_sun.directional_shadow_split_2 = 0.42
	_sun.directional_shadow_split_3 = 0.72
	_sun.directional_shadow_fade_start = 0.82
	_sun.directional_shadow_blend_splits = true
	_sun.directional_shadow_pancake_size = 18.0
	add_child(_sun)


func _texture(file_name: String) -> Texture2D:
	if file_name.is_empty():
		return null
	if _textures.has(file_name):
		return _textures[file_name] as Texture2D
	var path := TEXTURE_DIR + file_name
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	else:
		push_warning("Native texture is missing: %s" % path)
	_textures[file_name] = texture
	return texture


func _material(
	key: String,
	albedo_file: String = "",
	normal_file: String = "",
	color: Color = Color.WHITE,
	roughness: float = 0.9,
	metallic: float = 0.0,
	uv_scale: Vector3 = Vector3.ONE,
	triplanar: bool = false
) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D

	var material := StandardMaterial3D.new()
	material.resource_name = key
	material.albedo_color = color
	var albedo := _texture(albedo_file)
	var normal := _texture(normal_file)
	if albedo != null:
		material.albedo_texture = albedo
	if normal != null:
		material.normal_enabled = true
		material.normal_texture = normal
		material.normal_scale = 0.72
	material.roughness = roughness
	material.metallic = metallic
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.texture_repeat = true
	material.uv1_scale = uv_scale
	if triplanar:
		material.uv1_triplanar = true
		material.uv1_world_triplanar = true
	if color.a < 0.999:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_materials[key] = material
	return material


func _register_night_material(material: StandardMaterial3D, day: float, sunset: float, night: float) -> void:
	if material == null:
		return
	for entry in _night_materials:
		if entry.get("material") == material:
			return
	_night_materials.append({
		"material": material,
		"day": day,
		"sunset": sunset,
		"night": night,
	})


func _terrain_material(kind: String) -> StandardMaterial3D:
	var material: StandardMaterial3D
	match kind:
		"sand":
			material = _material("terrain_sand", "user_sand_rippled.jpg", "user_sand_rippled_normal.jpg", Color(0.88, 0.78, 0.58), 0.98)
		"concrete":
			material = _material("terrain_concrete", "user_concrete_slabs.jpg", "user_concrete_slabs_normal.jpg", Color(0.60, 0.61, 0.60), 0.94)
		"plaza":
			material = _material("terrain_premium_pavers", "user_travertine.jpg", "user_travertine_normal.jpg", Color(0.76, 0.72, 0.63), 0.78, 0.02, Vector3(0.34, 0.34, 0.34), true)
			material.normal_scale = 0.62
			material.metallic_specular = 0.42
		"rock":
			material = _material("terrain_rock", "rock.jpg", "rock_normal.jpg", Color(0.58, 0.56, 0.52), 1.0)
		_:
			material = _material("terrain_grass", "user_grass.jpg", "user_grass_normal.jpg", Color(0.58, 0.68, 0.42), 0.98)
	# Земля строится процедурно. Правильный winding — основное исправление
	# 0.2.2, а двусторонний материал — страховка: критичная поверхность не
	# должна снова пропасть на телефоне и показать нижнюю половину неба.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.metallic_specular = 0.28
	return material


func _create_asphalt_material() -> ShaderMaterial:
	if _asphalt_material != null:
		return _asphalt_material
	var material := ShaderMaterial.new()
	material.resource_name = "richtown_wet_asphalt"
	material.shader = WetAsphaltShader
	var albedo := _texture("user_asphalt_plain.jpg")
	var normal := _texture("user_asphalt_plain_normal.jpg")
	var wear := _texture("asphalt_city.jpg")
	var has_textures := albedo != null and normal != null
	if albedo != null:
		material.set_shader_parameter("albedo_tex", albedo)
	if normal != null:
		material.set_shader_parameter("normal_tex", normal)
	if wear != null:
		material.set_shader_parameter("wear_tex", wear)
	material.set_shader_parameter("use_textures", has_textures)
	material.set_shader_parameter("use_wear_texture", wear != null)
	material.set_shader_parameter("asphalt_color", Color(0.030, 0.032, 0.036))
	material.set_shader_parameter("texture_brightness", 1.08)
	material.set_shader_parameter("tex_scale", 0.115)
	material.set_shader_parameter("wetness", 0.12)
	material.set_shader_parameter("puddle_amount", 0.22)
	material.set_shader_parameter("dry_roughness", 0.94)
	material.set_shader_parameter("wet_roughness", 0.48)
	material.set_shader_parameter("puddle_roughness", 0.16)
	material.set_shader_parameter("bump_strength", 0.62)
	_asphalt_material = material
	_enhancement_stats["asphalt_shader"] = true
	_enhancement_stats["asphalt_textures"] = has_textures
	_enhancement_stats["asphalt_wear_texture"] = wear != null
	_enhancement_stats["asphalt_layers"] = 3 if has_textures and wear != null else 1
	_enhancement_stats["road_crown_m"] = ROAD_CROWN_M
	_enhancement_stats["asphalt_wetness"] = 0.12
	return material


func _create_curtain_wall_material(
	key: String,
	opaque_facade: bool,
	deep_color: Color,
	smoke_color: Color,
	blind_tint: Color,
	warm_interior: Color,
	floor_height_m: float,
	bay_width_m: float,
	seed: float,
	base_alpha: float = 0.80
) -> ShaderMaterial:
	if _materials.has(key):
		return _materials[key] as ShaderMaterial
	var material := ShaderMaterial.new()
	material.resource_name = key
	material.shader = CurtainWallFacadeShader if opaque_facade else CurtainWallGlassShader
	material.set_shader_parameter("deep_glass_color", deep_color)
	material.set_shader_parameter("smoke_glass_color", smoke_color)
	material.set_shader_parameter("blind_color", blind_tint)
	material.set_shader_parameter("warm_interior_color", warm_interior)
	material.set_shader_parameter("cool_interior_color", Color(0.100, 0.150, 0.180))
	material.set_shader_parameter("floor_height_m", floor_height_m)
	material.set_shader_parameter("bay_width_m", bay_width_m)
	material.set_shader_parameter("base_alpha", base_alpha)
	material.set_shader_parameter("material_seed", seed)
	material.set_shader_parameter("interior_light_strength", 0.0)
	material.set_shader_parameter("weathering_strength", 0.32)
	material.set_shader_parameter("detail_fade_start_m", 90.0)
	material.set_shader_parameter("detail_fade_end_m", 300.0)
	_materials[key] = material
	_curtain_glass_materials.append(material)
	if opaque_facade:
		_enhancement_stats["curtain_wall_opaque_shader"] = true
	else:
		_enhancement_stats["curtain_wall_shader"] = true
	_enhancement_stats["curtain_wall_materials"] = _curtain_glass_materials.size()
	_enhancement_stats["curtain_wall_panel_variation"] = true
	_enhancement_stats["curtain_wall_weathering"] = true
	_enhancement_stats["curtain_wall_neutral_glass"] = true
	_enhancement_stats["curtain_wall_calibrated_0215"] = true
	_enhancement_stats["curtain_wall_reflective_coating_0216"] = true
	_enhancement_stats["curtain_wall_clearcoat_removed"] = true
	_enhancement_stats["curtain_wall_detail_fade_start_m"] = 90.0
	_enhancement_stats["curtain_wall_detail_fade_end_m"] = 300.0
	_enhancement_stats["building_visual_ranges_0215"] = true
	_enhancement_stats["traffic_signal_visual_range_m"] = 220.0
	return material


func _create_foliage_wind_material(
	mesh: Mesh,
	texture_file: String,
	tint: Color,
	alpha_scissor_value: float,
	bend_strength: float,
	use_uv_mask_value: bool = false
) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.resource_name = "richtown_foliage_wind"
	material.shader = FoliageWindShader
	var texture := _texture(texture_file)
	if texture != null:
		material.set_shader_parameter("leaf_texture", texture)
	material.set_shader_parameter("use_texture", texture != null)
	material.set_shader_parameter("leaf_color", Color(0.16, 0.38, 0.10))
	material.set_shader_parameter("leaf_tint", tint)
	material.set_shader_parameter("alpha_scissor", alpha_scissor_value)
	material.set_shader_parameter("wind_dir", Vector2(1.0, 0.35))
	material.set_shader_parameter("wind_speed", 1.15)
	material.set_shader_parameter("bend_strength", bend_strength)
	material.set_shader_parameter("flutter_strength", bend_strength * 0.34)
	material.set_shader_parameter("gust_strength", 0.42)
	material.set_shader_parameter("use_uv_mask", use_uv_mask_value)
	material.set_shader_parameter("backlight_strength", 0.38)
	var aabb := mesh.get_aabb() if mesh != null else AABB(Vector3.ZERO, Vector3(1.0, 2.0, 1.0))
	material.set_shader_parameter("base_y", aabb.position.y)
	material.set_shader_parameter("plant_height", maxf(aabb.size.y, 0.05))
	_foliage_wind_materials.append(material)
	_enhancement_stats["foliage_wind"] = true
	_enhancement_stats["foliage_wind_materials"] = _foliage_wind_materials.size()
	return material


func _facade_material(facade: String, height: float) -> Material:
	# 0.2.14: background glass/gold towers no longer use photographic
	# blue/gold facade sheets. The opaque curtain-wall shader shades
	# real-metre bays with per-instance tenant/blind/roughness states,
	# so reflections come from the actual sky and district probes.
	if facade == "glassTower":
		return _create_curtain_wall_material(
			"facade_glass_tower_physical",
			true,
			Color(0.095, 0.150, 0.190),
			Color(0.170, 0.235, 0.285),
			Color(0.350, 0.340, 0.305),
			Color(0.165, 0.122, 0.082),
			3.30,
			1.75,
			7.0,
			0.84
		)
	if facade == "goldTower":
		return _create_curtain_wall_material(
			"facade_bronze_tower_physical",
			true,
			Color(0.140, 0.105, 0.065),
			Color(0.225, 0.170, 0.110),
			Color(0.370, 0.320, 0.250),
			Color(0.190, 0.140, 0.090),
			3.30,
			1.85,
			9.0,
			0.86
		)
	var albedo := "user_plaster_white.jpg"
	var normal := "user_plaster_white_normal.jpg"
	var roughness := 0.88
	var metallic := 0.0
	var glassy := false
	match facade:
		"hotelTower":
			albedo = "facade_hotel.jpg"
			normal = "facade_hotel_normal.jpg"
			roughness = 0.66
			glassy = true
		"marbleTower", "userMarble":
			albedo = "user_marble_tiles.jpg"
			normal = "user_marble_tiles_normal.jpg"
			roughness = 0.48
			metallic = 0.06
		"sandTower":
			albedo = "facade_sandstone.jpg"
			normal = "facade_sandstone_normal.jpg"
		"userWood":
			albedo = "user_wood_slats_dark.jpg"
			normal = "user_wood_slats_dark_normal.jpg"
			roughness = 0.82
		"userStone":
			albedo = "user_travertine.jpg"
			normal = "user_travertine_normal.jpg"
		"userPlaster":
			pass

	# 0.2.15: do not multiply already-bright photographic stone/plaster by
	# Color.WHITE. On the phone those towers clipped into featureless white
	# slabs beside the (previously too dark) glass. These are exposure tints,
	# not new colours: texture detail and district identity remain intact.
	var facade_tint := Color(0.86, 0.83, 0.76)
	match facade:
		"hotelTower":
			facade_tint = Color(0.82, 0.80, 0.75)
		"marbleTower", "userMarble":
			facade_tint = Color(0.78, 0.76, 0.72)
		"sandTower":
			facade_tint = Color(0.88, 0.82, 0.70)
		"userWood":
			facade_tint = Color(0.90, 0.82, 0.72)
		"userStone":
			facade_tint = Color(0.84, 0.80, 0.72)
	var tier := 0 if height < 18.0 else (1 if height < 52.0 else 2)
	var key := "facade_%s_%d" % [facade, tier]
	var material := _material(
		key,
		albedo,
		normal,
		facade_tint,
		roughness,
		metallic,
		Vector3(0.052, 0.047 + float(tier) * 0.006, 0.052),
		true
	)
	material.metallic_specular = 0.82 if glassy else 0.48
	if glassy or facade == "hotelTower":
		material.emission_enabled = true
		material.emission = Color(1.0, 0.74, 0.45)
		if material.albedo_texture != null:
			material.emission_texture = material.albedo_texture
		_register_night_material(material, 0.0, 0.08, 0.38)
	return material


func _roof_material(pitched: bool) -> StandardMaterial3D:
	if pitched:
		var pitched_material := _material(
			"roof_pitched",
			"user_roof_terracotta.jpg",
			"user_roof_terracotta_normal.jpg",
			Color.WHITE,
			0.94,
			0.0,
			Vector3(0.11, 0.11, 0.11),
			true
		)
		pitched_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		return pitched_material
	return _material(
		"roof_flat",
		"roof_flat.jpg",
		"user_black_rough_normal.jpg",
		Color(0.72, 0.72, 0.72),
		0.98,
		0.0,
		Vector3(0.07, 0.07, 0.07),
		true
	)


func _prop_material(material_name: String) -> Material:
	match material_name:
		"FacadeMain":
			return _material("prop_facade_main", "user_plaster_white.jpg", "user_plaster_white_normal.jpg", Color.WHITE, 0.9)
		"FacadeAccent":
			return _material("prop_facade_accent", "user_travertine.jpg", "user_travertine_normal.jpg", Color.WHITE, 0.84)
		"FacadeGlass":
			# Storefronts use the transparent physical curtain-wall
			# material instead of the old blue photographic sheets.
			return _create_curtain_wall_material(
				"prop_storefront_glass_physical",
				false,
				Color(0.090, 0.140, 0.175),
				Color(0.160, 0.220, 0.265),
				Color(0.340, 0.330, 0.295),
				Color(0.160, 0.118, 0.080),
				2.70,
				1.45,
				4.0,
				0.66
			)
		"PropsGlass":
			var panes := _material("prop_glass", "", "", Color(0.42, 0.65, 0.77, 0.50), 0.055, 0.12)
			panes.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			panes.metallic_specular = 1.0
			panes.clearcoat_enabled = true
			panes.clearcoat = 0.88
			panes.clearcoat_roughness = 0.035
			panes.emission_enabled = true
			panes.emission = Color(1.0, 0.78, 0.52)
			_register_night_material(panes, 0.0, 0.06, 0.24)
			return panes
		"PropsMetal":
			return _material("prop_metal", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.72, 0.76, 0.80), 0.38, 0.78)
		"PropsWood":
			return _material("prop_wood", "user_wood_deck.jpg", "user_wood_deck_normal.jpg", Color.WHITE, 0.86)
		"VillaPlaster":
			# 0.2.8: Building Model No.1 gets world-scale materials. The
			# 0.2.7 shared plaster was stretched over each whole cube UV,
			# so its photographic micro-cracks almost disappeared on the
			# phone. World triplanar mapping keeps the same real-metre
			# grain on every elevation and at every fixed-scale placement.
			var villa_plaster := _material("villa_plaster", "user_plaster_white.jpg", "user_plaster_white_normal.jpg", Color(0.88, 0.82, 0.72), 0.94, 0.0, Vector3(0.17, 0.17, 0.17), true)
			villa_plaster.normal_scale = 1.35
			villa_plaster.metallic_specular = 0.35
			return villa_plaster
		"VillaStone":
			var villa_stone := _material("villa_stone", "user_travertine.jpg", "user_travertine_normal.jpg", Color(0.92, 0.86, 0.76), 0.84, 0.0, Vector3(0.20, 0.20, 0.20), true)
			villa_stone.normal_scale = 1.20
			villa_stone.metallic_specular = 0.55
			return villa_stone
		"VillaLimestone":
			var villa_limestone := _material("villa_limestone", "user_stone_tiles_beige.jpg", "", Color(0.88, 0.80, 0.68), 0.92, 0.0, Vector3(0.18, 0.18, 0.18), true)
			villa_limestone.metallic_specular = 0.42
			return villa_limestone
		"VillaGranite":
			var villa_granite := _material("villa_granite", "user_black_granite.jpg", "user_black_granite_normal.jpg", Color(0.72, 0.74, 0.78), 0.50, 0.04, Vector3(0.24, 0.24, 0.24), true)
			villa_granite.normal_scale = 1.10
			villa_granite.metallic_specular = 0.90
			villa_granite.clearcoat_enabled = true
			villa_granite.clearcoat = 0.35
			villa_granite.clearcoat_roughness = 0.30
			return villa_granite
		"VillaWood":
			var villa_wood := _material("villa_wood", "user_wood_slats_dark.jpg", "user_wood_slats_dark_normal.jpg", Color(0.88, 0.74, 0.58), 0.78, 0.0, Vector3(0.32, 0.32, 0.32), true)
			villa_wood.normal_scale = 1.15
			villa_wood.metallic_specular = 0.45
			return villa_wood
		"VillaGlass":
			var villa_glass := _material("villa_glass", "", "", Color(0.34, 0.55, 0.64, 0.58), 0.08, 0.0)
			villa_glass.metallic_specular = 1.0
			villa_glass.clearcoat_enabled = true
			villa_glass.clearcoat = 1.0
			villa_glass.clearcoat_roughness = 0.06
			villa_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			villa_glass.emission_enabled = true
			villa_glass.emission = Color(1.0, 0.72, 0.44)
			_register_night_material(villa_glass, 0.0, 0.07, 0.30)
			return villa_glass
		"VillaInterior":
			var villa_interior := _material("villa_interior", "user_plaster_white.jpg", "user_plaster_white_normal.jpg", Color(0.112, 0.096, 0.080), 0.96, 0.0, Vector3(0.42, 0.42, 0.42), true)
			villa_interior.metallic_specular = 0.18
			return villa_interior
		"VillaCurtain":
			var villa_curtain := _material("villa_curtain", "user_plaster_white.jpg", "user_plaster_white_normal.jpg", Color(0.72, 0.65, 0.54), 1.0, 0.0, Vector3(0.65, 0.65, 0.65), true)
			villa_curtain.normal_scale = 0.45
			villa_curtain.metallic_specular = 0.22
			return villa_curtain
		"VillaPavement":
			var villa_pavement := _material("villa_pavement", "user_stone_tiles_beige.jpg", "", Color(0.82, 0.78, 0.70), 0.90, 0.0, Vector3(0.34, 0.34, 0.34), true)
			villa_pavement.metallic_specular = 0.45
			return villa_pavement
		"VillaDeck":
			var villa_deck := _material("villa_deck", "user_wood_deck.jpg", "user_wood_deck_normal.jpg", Color(0.62, 0.42, 0.25), 0.86, 0.0, Vector3(0.42, 0.42, 0.42), true)
			villa_deck.normal_scale = 1.0
			villa_deck.metallic_specular = 0.38
			return villa_deck
		"VillaMulch":
			var villa_mulch := _material("villa_mulch", "user_mulch_soil.jpg", "", Color(0.86, 0.78, 0.70), 1.0, 0.0, Vector3(0.65, 0.65, 0.65), true)
			villa_mulch.metallic_specular = 0.20
			return villa_mulch
		"VillaLawn":
			var villa_lawn := _material("villa_lawn", "user_grass.jpg", "user_grass_normal.jpg", Color(0.70, 0.78, 0.58), 1.0, 0.0, Vector3(0.48, 0.48, 0.48), true)
			villa_lawn.normal_scale = 0.90
			villa_lawn.metallic_specular = 0.22
			return villa_lawn
		"VillaHedge":
			var villa_hedge := _material("villa_hedge", "hedge.jpg", "", Color(0.72, 0.84, 0.62), 1.0, 0.0, Vector3(0.90, 0.90, 0.90), true)
			villa_hedge.metallic_specular = 0.25
			return villa_hedge
		"TownPlaster":
			# 0.2.9: Building Model No.2 gets the same world-scale
			# triplanar treatment as the villa, but with a warmer sand
			# render so the semi-detached pair reads as a different house.
			var town_plaster := _material("townhouse_plaster", "user_plaster_white.jpg", "user_plaster_white_normal.jpg", Color(0.92, 0.84, 0.68), 0.94, 0.0, Vector3(0.18, 0.18, 0.18), true)
			town_plaster.normal_scale = 1.30
			town_plaster.metallic_specular = 0.35
			return town_plaster
		"TownStone":
			var town_stone := _material("townhouse_stone", "user_stone_tiles_beige.jpg", "", Color(0.88, 0.79, 0.64), 0.92, 0.0, Vector3(0.18, 0.18, 0.18), true)
			town_stone.metallic_specular = 0.42
			return town_stone
		"TownTrim":
			var town_trim := _material("townhouse_trim", "user_travertine.jpg", "user_travertine_normal.jpg", Color(0.95, 0.91, 0.83), 0.86, 0.0, Vector3(0.28, 0.28, 0.28), true)
			town_trim.normal_scale = 0.90
			town_trim.metallic_specular = 0.50
			return town_trim
		"TownRoof":
			var town_roof := _material("townhouse_roof", "user_roof_terracotta.jpg", "user_roof_terracotta_normal.jpg", Color(0.94, 0.85, 0.76), 0.95, 0.0, Vector3(0.30, 0.30, 0.30), true)
			town_roof.normal_scale = 1.25
			town_roof.metallic_specular = 0.35
			return town_roof
		"TownGarage":
			var town_garage := _material("townhouse_garage", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.30, 0.36, 0.36), 0.48, 0.55, Vector3(0.45, 0.45, 0.45), true)
			town_garage.metallic_specular = 0.85
			return town_garage
		"TownDoor":
			var town_door := _material("townhouse_door", "user_wood_slats_dark.jpg", "user_wood_slats_dark_normal.jpg", Color(0.52, 0.26, 0.14), 0.72, 0.0, Vector3(0.50, 0.50, 0.50), true)
			town_door.normal_scale = 1.05
			town_door.metallic_specular = 0.45
			return town_door
		"TownDoorAccent":
			var town_door_accent := _material("townhouse_door_accent", "user_black_rough.jpg", "user_black_rough_normal.jpg", Color(0.10, 0.34, 0.36), 0.50, 0.10, Vector3(0.50, 0.50, 0.50), true)
			town_door_accent.metallic_specular = 0.60
			return town_door_accent
		"HeroPlaster":
			# 0.2.10: Building Model No.3 keeps the same real-metre
			# triplanar rule as Models No.1/No.2, with a slightly cooler
			# tower render over its darker stone podium and end piers.
			var hero_plaster := _material("hero_plaster", "user_plaster_white.jpg", "user_plaster_white_normal.jpg", Color(0.87, 0.81, 0.70), 0.94, 0.0, Vector3(0.16, 0.16, 0.16), true)
			hero_plaster.normal_scale = 1.30
			hero_plaster.metallic_specular = 0.35
			return hero_plaster
		"HeroStone":
			var hero_stone := _material("hero_stone", "user_stone_tiles_beige.jpg", "", Color(0.60, 0.56, 0.49), 0.92, 0.0, Vector3(0.20, 0.20, 0.20), true)
			hero_stone.metallic_specular = 0.45
			return hero_stone
		"HeroTrim":
			var hero_trim := _material("hero_trim", "user_travertine.jpg", "user_travertine_normal.jpg", Color(0.90, 0.85, 0.75), 0.86, 0.0, Vector3(0.26, 0.26, 0.26), true)
			hero_trim.normal_scale = 0.90
			hero_trim.metallic_specular = 0.50
			return hero_trim
		"HeroWood":
			var hero_wood := _material("hero_wood", "user_wood_slats_dark.jpg", "user_wood_slats_dark_normal.jpg", Color(0.72, 0.48, 0.28), 0.80, 0.0, Vector3(0.38, 0.38, 0.38), true)
			hero_wood.normal_scale = 1.10
			hero_wood.metallic_specular = 0.45
			return hero_wood
		"HeroMetal":
			var hero_metal := _material("hero_metal", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.22, 0.26, 0.29), 0.46, 0.65, Vector3(0.50, 0.50, 0.50), true)
			hero_metal.metallic_specular = 0.90
			return hero_metal
		"TowerGlass":
			# 0.2.14: Building Model No.4 keeps its Blender mullions,
			# spandrels, fins and occupied core, but the uniform bright
			# blue shell becomes dark smoked physical glass. Tenant,
			# blind, roughness and reflection states vary by real bay.
			return _create_curtain_wall_material(
				"tower_glass_physical",
				false,
				Color(0.100, 0.155, 0.195),
				Color(0.175, 0.240, 0.290),
				Color(0.350, 0.340, 0.305),
				Color(0.165, 0.122, 0.082),
				3.45,
				1.85,
				2.0,
				0.72
			)
		"TowerSpandrel":
			var tower_spandrel := _material("tower_spandrel", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.270, 0.290, 0.310), 0.34, 0.72, Vector3(0.35, 0.35, 0.35), true)
			tower_spandrel.metallic_specular = 0.95
			return tower_spandrel
		"TowerStone":
			var tower_stone := _material("tower_stone", "user_stone_tiles_beige.jpg", "", Color(0.68, 0.64, 0.57), 0.92, 0.0, Vector3(0.18, 0.18, 0.18), true)
			tower_stone.metallic_specular = 0.45
			return tower_stone
		"TowerTrim":
			var tower_trim := _material("tower_trim", "user_travertine.jpg", "user_travertine_normal.jpg", Color(0.90, 0.87, 0.79), 0.62, 0.12, Vector3(0.26, 0.26, 0.26), true)
			tower_trim.normal_scale = 0.85
			tower_trim.metallic_specular = 0.62
			return tower_trim
		"TowerMetal":
			var tower_metal := _material("tower_metal", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.200, 0.220, 0.240), 0.38, 0.78, Vector3(0.48, 0.48, 0.48), true)
			tower_metal.metallic_specular = 0.92
			return tower_metal
		"MainGlass":
			# 0.2.14 realism pass on Building Model No.5: the twisting
			# capsule remains Blender geometry over an occupied core, but
			# its shell is no longer one bright blue tint. The shader
			# gives every 1.60 m bay and 3.42 m floor its own smoked,
			# blind, warm-interior or mirror state, with panel tilt and
			# vertical weathering over the real fins and mullions.
			return _create_curtain_wall_material(
				"main_glass_physical",
				false,
				Color(0.105, 0.165, 0.205),
				Color(0.185, 0.255, 0.305),
				Color(0.360, 0.350, 0.315),
				Color(0.170, 0.125, 0.085),
				3.42,
				1.60,
				5.0,
				0.72
			)
		"MainSpandrel":
			var main_spandrel := _material("main_spandrel", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.300, 0.315, 0.330), 0.30, 0.76, Vector3(0.35, 0.35, 0.35), true)
			main_spandrel.metallic_specular = 0.95
			return main_spandrel
		"MainStone":
			var main_stone := _material("main_stone", "user_stone_tiles_beige.jpg", "", Color(0.74, 0.69, 0.61), 0.90, 0.0, Vector3(0.18, 0.18, 0.18), true)
			main_stone.metallic_specular = 0.48
			return main_stone
		"MainTrim":
			var main_trim := _material("main_trim", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.80, 0.62, 0.34), 0.38, 0.55, Vector3(0.35, 0.35, 0.35), true)
			main_trim.metallic_specular = 0.92
			return main_trim
		"MainMetal":
			var main_metal := _material("main_metal", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.230, 0.240, 0.260), 0.36, 0.80, Vector3(0.48, 0.48, 0.48), true)
			main_metal.metallic_specular = 0.92
			return main_metal
		"MainWater":
			var main_water := _material("main_water", "user_pool_mosaic.jpg", "user_pool_mosaic_normal.jpg", Color(0.38, 0.68, 0.78), 0.08, 0.0, Vector3(0.45, 0.45, 0.45), true)
			main_water.metallic_specular = 1.0
			main_water.clearcoat_enabled = true
			main_water.clearcoat = 1.0
			main_water.clearcoat_roughness = 0.06
			return main_water
		"FacadeStone":
			return _material("prop_facade_stone", "facade_sandstone.jpg", "facade_sandstone_normal.jpg", Color(0.82, 0.79, 0.72), 0.92, 0.0, Vector3(0.14, 0.14, 0.14), true)
		"FacadeWoodSlat":
			return _material("prop_facade_wood_slat", "user_wood_slats_dark.jpg", "user_wood_slats_dark_normal.jpg", Color(0.90, 0.78, 0.66), 0.82, 0.0, Vector3(0.32, 0.32, 0.32), true)
		"WindowFrame":
			return _material("prop_window_frame", "user_black_rough.jpg", "user_black_rough_normal.jpg", Color(0.24, 0.26, 0.28), 0.50, 0.38, Vector3(0.45, 0.45, 0.45), true)
		"WindowGlassDark":
			var dark_glass := _material("prop_window_glass_dark", "", "", Color(0.11, 0.27, 0.37, 0.76), 0.07, 0.18)
			dark_glass.metallic_specular = 1.0
			dark_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			dark_glass.emission_enabled = true
			dark_glass.emission = Color(1.0, 0.72, 0.44)
			_register_night_material(dark_glass, 0.0, 0.07, 0.30)
			return dark_glass
		"ConcreteLight":
			return _material("prop_concrete_light", "user_concrete_slabs.jpg", "user_concrete_slabs_normal.jpg", Color(0.76, 0.77, 0.75), 0.95, 0.0, Vector3(0.20, 0.20, 0.20), true)
		"RoofGravel":
			return _material("prop_roof_gravel", "user_black_rough.jpg", "user_black_rough_normal.jpg", Color(0.42, 0.42, 0.43), 1.0, 0.0, Vector3(0.42, 0.42, 0.42), true)
		"SolarCell":
			var solar := _material("prop_solar_cell", "", "", Color(0.025, 0.09, 0.20), 0.16, 0.45)
			solar.metallic_specular = 1.0
			return solar
		"SignalMetal":
			return _material("signal_metal", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.48, 0.52, 0.56), 0.36, 0.84, Vector3(0.55, 0.55, 0.55), true)
		"SignalHousing":
			return _material("signal_housing", "user_black_rough.jpg", "user_black_rough_normal.jpg", Color(0.16, 0.17, 0.18), 0.62, 0.08, Vector3(0.65, 0.65, 0.65), true)
		"SignalRedOn":
			var red_lens := _material("signal_red_on", "", "", Color(0.48, 0.025, 0.015), 0.24, 0.05)
			red_lens.metallic_specular = 0.85
			red_lens.emission_enabled = true
			red_lens.emission = Color(1.0, 0.035, 0.015)
			# Static red only by request: no signal phase logic exists.
			_register_night_material(red_lens, 0.95, 1.65, 2.55)
			return red_lens
		"SignalAmberOff":
			var amber_lens := _material("signal_amber_off", "", "", Color(0.23, 0.105, 0.008), 0.18, 0.08)
			amber_lens.metallic_specular = 0.85
			return amber_lens
		"SignalGreenOff":
			var green_lens := _material("signal_green_off", "", "", Color(0.008, 0.13, 0.045), 0.18, 0.08)
			green_lens.metallic_specular = 0.85
			return green_lens
		"SignalReflector":
			var reflector := _material("signal_reflector", "user_black_rough.jpg", "user_black_rough_normal.jpg", Color(0.78, 0.55, 0.05), 0.42, 0.04)
			reflector.emission_enabled = true
			reflector.emission = Color(1.0, 0.62, 0.05)
			_register_night_material(reflector, 0.02, 0.08, 0.18)
			return reflector
		"SignalCable":
			return _material("signal_cable", "user_black_rough.jpg", "user_black_rough_normal.jpg", Color(0.055, 0.055, 0.06), 0.74, 0.0)
		"RoofDark":
			return _material("prop_roof_dark", "user_black_rough.jpg", "user_black_rough_normal.jpg", Color(0.48, 0.48, 0.50), 0.96)
		"RoofTile":
			return _material("prop_roof_tile", "user_roof_terracotta.jpg", "user_roof_terracotta_normal.jpg", Color.WHITE, 0.94)
		"LampGlow":
			var glow := _material("prop_lamp_glow", "", "", Color(1.0, 0.92, 0.72), 0.35)
			glow.emission_enabled = true
			glow.emission = Color(1.0, 0.82, 0.50)
			_register_night_material(glow, 0.18, 1.5, 4.2)
			return glow
		"nh_foliage":
			var foliage := _material("plant_foliage", "foliage.jpg", "foliage_normal.jpg", Color(0.62, 0.86, 0.52), 1.0)
			foliage.cull_mode = BaseMaterial3D.CULL_DISABLED
			return foliage
		"nh_bark":
			return _material("plant_bark", "oak_bark.jpg", "oak_bark_normal.jpg", Color(0.82, 0.72, 0.62), 1.0)
		_:
			return _material("prop_fallback", "user_concrete_slabs.jpg", "user_concrete_slabs_normal.jpg", Color(0.8, 0.8, 0.8), 0.9)


func _mesh_instance(parent: Node, mesh: Mesh, material: Material, transform_value: Transform3D, node_name: String = "Mesh", cast_shadow: bool = true) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	if material != null:
		instance.material_override = material
	instance.transform = transform_value
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(instance)
	return instance


func _add_box(parent: Node, size: Vector3, center: Vector3, material: Material, yaw: float = 0.0, node_name: String = "Box") -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh_instance(parent, mesh, material, make_transform(center, yaw, Vector3.ONE), node_name)


func _add_cylinder(parent: Node, radius: float, height: float, center: Vector3, material: Material, yaw: float = 0.0, segments: int = 24, node_name: String = "Cylinder") -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	return _mesh_instance(parent, mesh, material, make_transform(center, yaw, Vector3.ONE), node_name)


func _add_sphere(parent: Node, radius: float, height: float, center: Vector3, material: Material, node_name: String = "Sphere") -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 28
	mesh.rings = 14
	return _mesh_instance(parent, mesh, material, make_transform(center), node_name)


func _grid_height(ix: int, iz: int) -> float:
	var heights: Array = _terrain.get("heights", [])
	var cols := int(_terrain.get("cols", 0))
	var rows := int(_terrain.get("rows", 0))
	ix = clampi(ix, 0, max(cols - 1, 0))
	iz = clampi(iz, 0, max(rows - 1, 0))
	var index := iz * cols + ix
	if index < 0 or index >= heights.size():
		return 0.0
	return float(heights[index])


func _in_zone(x: float, z: float, zone_name: String) -> bool:
	var zones: Dictionary = data.get("zones", {})
	var zone: Dictionary = zones.get(zone_name, {})
	if zone.is_empty():
		return false
	return x >= _f(zone, "minX") and x <= _f(zone, "maxX") and z >= _f(zone, "minZ") and z <= _f(zone, "maxZ")


func _hash01(ix: int, iz: int) -> float:
	var value := sin(float(ix) * 127.1 + float(iz) * 311.7) * 43758.5453
	return value - floor(value)


func _terrain_class(x: float, z: float, h: float, slope: float, ix: int, iz: int) -> String:
	var in_promenade := z >= -94.0 and z <= 48.0 and ((x >= 713.0 and x <= 744.0) or (x >= 776.0 and x <= 789.0))
	if _in_zone(x, z, "rtPlaza") or in_promenade:
		return "plaza"
	if (_in_zone(x, z, "sea") or _in_zone(x, z, "marina")) and h < 0.5:
		return "sand"
	if _in_zone(x, z, "beach") and h < 3.45:
		return "sand"
	if slope > 0.34 or h > 17.0:
		return "rock"
	if (_in_zone(x, z, "palmIsland") or _in_zone(x, z, "sailIsland")) and h < 2.35:
		return "sand" if _hash01(ix, iz) < 0.58 else "grass"
	if x >= 520.0 and x < 945.0 and _in_zone(x, z, "richtown"):
		return "grass" if _hash01(ix * 3 + 17, iz * 5 + 9) < 0.18 else "concrete"
	return "grass"


func _terrain_vertex(tool: SurfaceTool, position_value: Vector3) -> void:
	tool.set_uv(Vector2(position_value.x / 9.0, position_value.z / 9.0))
	tool.add_vertex(position_value)


func _build_terrain() -> void:
	var cols := int(_terrain.get("cols", 0))
	var rows := int(_terrain.get("rows", 0))
	if cols < 2 or rows < 2:
		return
	var min_x := _f(_terrain, "minX", 520.0)
	var min_z := _f(_terrain, "minZ", -500.0)
	var step := _f(_terrain, "stepM", 10.0)

	var tools: Dictionary = {}
	for kind in ["grass", "sand", "concrete", "plaza", "rock"]:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[kind] = tool

	for iz in range(rows - 1):
		for ix in range(cols - 1):
			var x0 := min_x + float(ix) * step
			var z0 := min_z + float(iz) * step
			var x1 := x0 + step
			var z1 := z0 + step
			var p00 := Vector3(x0, _grid_height(ix, iz), z0)
			var p10 := Vector3(x1, _grid_height(ix + 1, iz), z0)
			var p11 := Vector3(x1, _grid_height(ix + 1, iz + 1), z1)
			var p01 := Vector3(x0, _grid_height(ix, iz + 1), z1)
			var center := (p00 + p11) * 0.5
			var slope := maxf(abs(p10.y - p00.y), abs(p01.y - p00.y)) / step
			var kind := _terrain_class(center.x, center.z, center.y, slope, ix, iz)
			var tool := tools[kind] as SurfaceTool
			# Godot front faces are clockwise as seen from the camera side.
			# For a ground plane viewed from above, the geometric cross
			# product therefore points down. The reversed pre-0.2.2 order
			# was back-face culled on the phone, leaving only sky below the
			# horizon. Keep this order paired with get_road_visual_state().
			for vertex in [p00, p10, p11, p00, p11, p01]:
				_terrain_vertex(tool, vertex)

	var terrain_root := Node3D.new()
	terrain_root.name = "Terrain"
	add_child(terrain_root)
	_terrain_meshes.clear()
	for kind in tools.keys():
		var tool := tools[kind] as SurfaceTool
		tool.index()
		tool.generate_normals()
		tool.generate_tangents()
		var mesh := tool.commit()
		if mesh != null:
			_terrain_meshes[String(kind)] = mesh
			var instance := _mesh_instance(terrain_root, mesh, _terrain_material(String(kind)), Transform3D.IDENTITY, "Terrain_%s" % String(kind), false)
			instance.custom_aabb = WORLD_AABB
	_enhancement_stats["terrain_meshes"] = _terrain_meshes.size()
	_enhancement_stats["premium_boulevard_paving"] = _terrain_meshes.has("plaza")
	_enhancement_stats["ground_winding_godot_cw"] = bool(get_road_visual_state().get("ground_winding_godot_cw", false)) if _road_mesh != null else false

	var heights: Array = _terrain.get("heights", [])
	var map_data := PackedFloat32Array()
	map_data.resize(heights.size())
	for i in heights.size():
		map_data[i] = float(heights[i])
	var height_shape := HeightMapShape3D.new()
	height_shape.map_width = cols
	height_shape.map_depth = rows
	height_shape.map_data = map_data
	var collision := CollisionShape3D.new()
	collision.name = "TerrainHeightMap"
	collision.shape = height_shape
	var center := Vector3(min_x + float(cols - 1) * step * 0.5, 0.0, min_z + float(rows - 1) * step * 0.5)
	collision.transform = make_transform(center, 0.0, Vector3(step, 1.0, step))
	_collision_root.add_child(collision)


func _water_material() -> ShaderMaterial:
	if _sea_material != null:
		return _sea_material
	_sea_material = ShaderMaterial.new()
	_sea_material.resource_name = "sea_surface_pbr"
	_sea_material.shader = WaterSurfaceShader
	_sea_material.set_shader_parameter("wave_time", _elapsed)
	_sea_material.set_shader_parameter("wave_height", 0.62)
	_sea_material.set_shader_parameter("wind_direction", Vector2(0.82, 0.57))
	_sea_material.set_shader_parameter("foam_strength", 0.66)
	_sea_material.set_shader_parameter("normal_strength", 0.78)
	_sea_material.set_shader_parameter("reflection_strength", 0.82)
	return _sea_material


func get_water_visual_state() -> Dictionary:
	return {
		"sea_shader": _sea_material != null and _sea_material.shader == WaterSurfaceShader,
		"animated_waves": _sea_material != null and float(_sea_material.get_shader_parameter("wave_height")) > 0.0,
		"depth_foam": _sea_material != null and float(_sea_material.get_shader_parameter("foam_strength")) > 0.0,
		"reflection_strength": float(_sea_material.get_shader_parameter("reflection_strength")) if _sea_material != null else 0.0,
		"sea_vertices_x": 97,
		"sea_vertices_z": 133,
		"pool_surfaces": _water_materials.size(),
	}


func _pool_material() -> StandardMaterial3D:
	var material := _material(
		"water_pool",
		"user_pool_mosaic.jpg",
		"user_pool_mosaic_normal.jpg",
		Color(0.22, 0.60, 0.68, 0.96),
		0.075,
		0.0,
		Vector3(2.0, 2.0, 1.0)
	)
	material.normal_scale = 0.48
	material.metallic_specular = 0.98
	material.clearcoat_enabled = true
	material.clearcoat = 0.85
	material.clearcoat_roughness = 0.045
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(0.025, 0.085, 0.10)
	_register_night_material(material, 0.0, 0.025, 0.10)
	if not _water_materials.has(material):
		_water_materials.append(material)
	return material


func _build_water_and_pools() -> void:
	var water_root := Node3D.new()
	water_root.name = "Water"
	add_child(water_root)

	var sea_mesh := PlaneMesh.new()
	sea_mesh.size = Vector2(760.0, 1040.0)
	# The denser grid carries the low-frequency geometric swell smoothly;
	# fine ripples/normals are evaluated per fragment in water_surface.gdshader.
	sea_mesh.subdivide_width = 96
	sea_mesh.subdivide_depth = 132
	var sea := _mesh_instance(water_root, sea_mesh, _water_material(), make_transform(Vector3(1145.0, 0.04, 0.0)), "SeaAndMarina", false)
	# The sea plane only exists east of the shoreline; WORLD_AABB forced
	# its 45k vertices through the vertex shader even when looking inland.
	sea.custom_aabb = AABB(Vector3(-382.0, -2.0, -522.0), Vector3(764.0, 5.0, 1044.0))

	var pools: Array = data.get("pools", [])
	if pools.is_empty():
		return
	var rim_transforms: Array[Transform3D] = []
	var water_transforms: Array[Transform3D] = []
	for pool_variant in pools:
		var pool: Dictionary = pool_variant
		var center := _item_position(pool)
		var yaw := _f(pool, "rotY")
		var w := _f(pool, "w", 8.0)
		var d := _f(pool, "d", 5.0)
		rim_transforms.append(make_transform(center + Vector3(0.0, -0.03, 0.0), yaw, Vector3(w + 1.3, 1.0, d + 1.3)))
		water_transforms.append(make_transform(center + Vector3(0.0, 0.08, 0.0), yaw, Vector3(w, 1.0, d)))

	var slab := BoxMesh.new()
	slab.size = Vector3(1.0, 0.20, 1.0)
	_add_multimesh(water_root, slab, _terrain_material("concrete"), rim_transforms, "PoolRims", false)
	_add_multimesh(water_root, slab, _pool_material(), water_transforms, "Pools", false)


func _road_vertex(tool: SurfaceTool, position_value: Vector3, uv: Vector2) -> void:
	# Normals are generated from the indexed geometry below. A forced
	# Vector3.UP hid both longitudinal grades and the 0.2.6 road Crown.
	tool.set_uv(uv)
	tool.add_vertex(position_value)


func _road_surface_y(center_y: float, lateral_offset: float, half_width: float, crown_scale: float = 1.0) -> float:
	var lateral_ratio := clampf(absf(lateral_offset) / maxf(half_width, 0.1), 0.0, 1.0)
	return center_y + ROAD_SURFACE_OFFSET_M + ROAD_CROWN_M * (1.0 - lateral_ratio) * clampf(crown_scale, 0.0, 1.0)


func _junction_info(point: Vector3, current_id: String, current_direction: Vector3) -> Dictionary:
	var current_flat := Vector2(current_direction.x, current_direction.z)
	if current_flat.length_squared() < 0.0001:
		current_flat = Vector2(0.0, 1.0)
	current_flat = current_flat.normalized()
	var is_junction := false
	var cross_half_width := 0.0
	for road_variant in data.get("roads", []):
		var road: Dictionary = road_variant
		if String(road.get("id", "")) == current_id:
			continue
		var samples: Array = road.get("samples", [])
		if samples.size() < 2:
			continue
		for endpoint_index in [0, samples.size() - 1]:
			var endpoint := _sample_point(samples[endpoint_index])
			if Vector2(endpoint.x - point.x, endpoint.z - point.z).length() > 2.5:
				continue
			is_junction = true
			var neighbour_index := 1 if endpoint_index == 0 else samples.size() - 2
			var neighbour := _sample_point(samples[neighbour_index])
			var other_flat := Vector2(neighbour.x - endpoint.x, neighbour.z - endpoint.z)
			if other_flat.length_squared() < 0.0001:
				continue
			other_flat = other_flat.normalized()
			# A continuation of the same street is not a cross street. Only
			# a non-collinear road determines how much of this carriageway
			# belongs to the flat intersection box.
			if absf(current_flat.dot(other_flat)) < 0.70:
				cross_half_width = maxf(cross_half_width, _f(road, "widthM", 10.0) * 0.5)
	var trim := cross_half_width + 0.9 if is_junction and cross_half_width > 0.0 else 0.0
	return {"is_junction": is_junction, "trim_m": trim, "cross_half_width_m": cross_half_width}


func _road_crown_scale(distance_from_start: float, total_length: float, trim_start: float, trim_end: float) -> float:
	var start_scale := clampf((distance_from_start - trim_start) / 7.0, 0.0, 1.0)
	var end_scale := clampf(((total_length - distance_from_start) - trim_end) / 7.0, 0.0, 1.0)
	return minf(start_scale, end_scale)


func _build_road_mesh(extra_width: float, y_offset: float, uv_distance: float, crown_height: float = 0.0) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for road_variant in data.get("roads", []):
		var road: Dictionary = road_variant
		var samples: Array = road.get("samples", [])
		if samples.size() < 2:
			continue
		var half_width := _f(road, "widthM", 10.0) * 0.5 + extra_width
		var points: Array[Vector3] = []
		for sample in samples:
			points.append(_sample_point(sample))
		var distances: Array[float] = []
		var total_length := 0.0
		for i in points.size():
			if i > 0:
				total_length += points[i].distance_to(points[i - 1])
			distances.append(total_length)
		var road_id := String(road.get("id", ""))
		var start_direction := points[1] - points[0]
		var end_direction := points[points.size() - 1] - points[points.size() - 2]
		var trim_start := float(_junction_info(points[0], road_id, start_direction).get("trim_m", 0.0)) if crown_height > 0.0 else 0.0
		var trim_end := float(_junction_info(points[points.size() - 1], road_id, end_direction).get("trim_m", 0.0)) if crown_height > 0.0 else 0.0
		var left_points: Array[Vector3] = []
		var center_points: Array[Vector3] = []
		var right_points: Array[Vector3] = []
		for i in points.size():
			var direction := Vector3.ZERO
			if i == 0:
				direction = points[1] - points[0]
			elif i == points.size() - 1:
				direction = points[i] - points[i - 1]
			else:
				direction = points[i + 1] - points[i - 1]
			direction.y = 0.0
			if direction.length_squared() < 0.0001:
				direction = Vector3(0.0, 0.0, -1.0)
			direction = direction.normalized()
			var side := Vector3(-direction.z, 0.0, direction.x)
			var center := points[i] + Vector3.UP * y_offset
			left_points.append(center - side * half_width)
			var crown_scale := _road_crown_scale(distances[i], total_length, trim_start, trim_end)
			center_points.append(center + Vector3.UP * crown_height * crown_scale)
			right_points.append(center + side * half_width)
		for i in range(points.size() - 1):
			var l0 := left_points[i]
			var c0 := center_points[i]
			var r0 := right_points[i]
			var l1 := left_points[i + 1]
			var c1 := center_points[i + 1]
			var r1 := right_points[i + 1]
			var v0 := distances[i] / uv_distance
			var v1 := distances[i + 1] / uv_distance
			# Same Godot clockwise-front-face rule as the terrain: viewed
			# from above these triangles are front-facing. Generated
			# normals then shade the Crown and longitudinal slope.
			if crown_height > 0.0:
				_road_vertex(tool, l0, Vector2(0.0, v0))
				_road_vertex(tool, l1, Vector2(0.0, v1))
				_road_vertex(tool, c1, Vector2(0.5, v1))
				_road_vertex(tool, l0, Vector2(0.0, v0))
				_road_vertex(tool, c1, Vector2(0.5, v1))
				_road_vertex(tool, c0, Vector2(0.5, v0))
				_road_vertex(tool, c0, Vector2(0.5, v0))
				_road_vertex(tool, c1, Vector2(0.5, v1))
				_road_vertex(tool, r1, Vector2(1.0, v1))
				_road_vertex(tool, c0, Vector2(0.5, v0))
				_road_vertex(tool, r1, Vector2(1.0, v1))
				_road_vertex(tool, r0, Vector2(1.0, v0))
			else:
				_road_vertex(tool, l0, Vector2(0.0, v0))
				_road_vertex(tool, l1, Vector2(0.0, v1))
				_road_vertex(tool, r1, Vector2(1.0, v1))
				_road_vertex(tool, l0, Vector2(0.0, v0))
				_road_vertex(tool, r1, Vector2(1.0, v1))
				_road_vertex(tool, r0, Vector2(1.0, v0))
	tool.index()
	tool.generate_normals()
	tool.generate_tangents()
	return tool.commit()


func _build_roads() -> void:
	var roads_root := Node3D.new()
	roads_root.name = "Roads"
	add_child(roads_root)

	var sidewalk_material := _material(
		"sidewalk",
		"user_concrete_slabs.jpg",
		"user_concrete_slabs_normal.jpg",
		Color(0.52, 0.53, 0.52),
		0.96,
		0.0,
		Vector3(0.16, 0.16, 0.16),
		true
	)
	sidewalk_material.normal_scale = 0.9
	sidewalk_material.metallic_specular = 0.28
	sidewalk_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_sidewalk_mesh = _build_road_mesh(1.9, 0.050, 7.0)
	if _sidewalk_mesh != null:
		var sidewalks := _mesh_instance(roads_root, _sidewalk_mesh, sidewalk_material, Transform3D.IDENTITY, "Sidewalks", false)
		sidewalks.custom_aabb = WORLD_AABB

	# Plain (not dashed) user asphalt feeds the adapted Drive wet_asphalt
	# shader. Lane paint is real geometry below, so it no longer depends on
	# a baked centre line stretched across roads of different widths.
	var asphalt_material := _create_asphalt_material()
	_road_mesh = _build_road_mesh(0.0, ROAD_SURFACE_OFFSET_M, 18.0, ROAD_CROWN_M)
	if _road_mesh != null:
		var roads := _mesh_instance(roads_root, _road_mesh, asphalt_material, Transform3D.IDENTITY, "Asphalt", false)
		roads.custom_aabb = WORLD_AABB
	_enhancement_stats["ground_winding_godot_cw"] = bool(get_road_visual_state().get("ground_winding_godot_cw", false))

	_build_intersection_pads(roads_root, asphalt_material)
	_build_road_edges(roads_root)
	_build_road_markings(roads_root)
	_build_road_details(roads_root)
	_build_bridge_guardrails(roads_root)


func _build_intersection_pads(parent: Node, asphalt_material: ShaderMaterial) -> void:
	# The exported ribbons deliberately overlap inside junction boxes. A
	# 13 mm proud asphalt pad hides coplanar depth fighting and gives each
	# main intersection one continuous surface; the Crown has already been
	# flattened there by _build_road_mesh(). Lane paint stops before the
	# pad, so the pad never covers a crosswalk or stop line.
	var transforms: Array[Transform3D] = []
	var vertical_roads := [
		{"x": 560.0, "width": 11.0},
		{"x": 760.0, "width": 22.0},
		{"x": 930.0, "width": 24.0},
	]
	var cross_z := [-430.0, -300.0, -250.0, -110.0, 60.0, 225.0, 430.0]
	for vertical_variant in vertical_roads:
		var vertical: Dictionary = vertical_variant
		var center_x := float(vertical.get("x", 760.0))
		var width := float(vertical.get("width", 12.0))
		for z_variant in cross_z:
			var center_z := float(z_variant)
			var y := height_at(center_x, center_z) + ROAD_SURFACE_OFFSET_M + 0.007
			transforms.append(make_transform(
				Vector3(center_x, y, center_z),
				0.0,
				Vector3(width + 0.04, 0.012, 13.04 if absf(center_z - 225.0) > 0.1 else 16.04)
			))
	var pad_mesh := BoxMesh.new()
	pad_mesh.size = Vector3.ONE
	pad_mesh.material = asphalt_material
	_add_multimesh(parent, pad_mesh, asphalt_material, transforms, "IntersectionPads", false)
	_enhancement_stats["intersection_pads"] = transforms.size()


func _build_road_edges(parent: Node) -> void:
	# 0.2.6 gives the carriageway a physical edge instead of a flat
	# sidewalk ribbon lying below the asphalt: dark gutter, concrete curb
	# and a raised slab. They are visual-only in this pass by design; no
	# new colliders are introduced while the user asked not to touch the
	# remaining drive-twitch investigation.
	var slab_transforms: Array[Transform3D] = []
	var curb_transforms: Array[Transform3D] = []
	var painted_curb_transforms: Array[Transform3D] = []
	var gutter_transforms: Array[Transform3D] = []
	var driveway_gaps := 0
	var road_index := 0
	var bridgeless_ids := ["rt-palm-1", "rt-sail-road", "rt-highway-1"]

	for road_variant in data.get("roads", []):
		var road: Dictionary = road_variant
		var road_id := String(road.get("id", ""))
		var samples: Array = road.get("samples", [])
		if samples.size() < 2 or bridgeless_ids.has(road_id):
			road_index += 1
			continue
		var width := _f(road, "widthM", 10.0)
		var half_width := width * 0.5
		var points: Array[Vector3] = []
		for sample in samples:
			points.append(_sample_point(sample))
		var total_length := 0.0
		for i in range(points.size() - 1):
			var flat := points[i + 1] - points[i]
			flat.y = 0.0
			total_length += flat.length()
		var start_direction := points[1] - points[0]
		var end_direction := points[points.size() - 1] - points[points.size() - 2]
		var trim_start := float(_junction_info(points[0], road_id, start_direction).get("trim_m", 0.0))
		var trim_end := float(_junction_info(points[points.size() - 1], road_id, end_direction).get("trim_m", 0.0))
		var distance_from_start := 0.0
		for i in range(points.size() - 1):
			var a := points[i]
			var b := points[i + 1]
			var segment := b - a
			segment.y = 0.0
			var length := segment.length()
			var segment_start := distance_from_start
			distance_from_start += length
			var segment_end := distance_from_start
			if length < 0.45:
				continue
			if segment_end <= trim_start + 0.5 or segment_start >= total_length - trim_end - 0.5:
				continue
			var direction := segment / length
			var side := Vector3(-direction.z, 0.0, direction.x)
			var yaw := atan2(direction.x, direction.z)
			var midpoint := (a + b) * 0.5
			var crown_scale := _road_crown_scale(segment_start + length * 0.5, total_length, trim_start, trim_end)
			var near_junction := (trim_start > 0.0 and segment_start < trim_start + 11.0) or (trim_end > 0.0 and segment_end > total_length - trim_end - 11.0)
			for side_sign_variant in [-1.0, 1.0]:
				var side_sign := float(side_sign_variant)
				var gutter_offset := half_width - 0.22
				var gutter_center: Vector3 = midpoint + side * side_sign * gutter_offset
				gutter_transforms.append(make_transform(
					Vector3(gutter_center.x, _road_surface_y(midpoint.y, gutter_offset, half_width, crown_scale) + 0.006, gutter_center.z),
					yaw,
					Vector3(0.60, 0.016, length + 0.05)
				))

				var slab_center: Vector3 = midpoint + side * side_sign * (half_width + 1.28)
				slab_transforms.append(make_transform(
					Vector3(slab_center.x, midpoint.y + 0.155, slab_center.z),
					yaw,
					Vector3(1.90, 0.15, length + 0.06)
				))

				var driveway_roll := _hash01(road_index * 197 + i * 13, int(side_sign) * 37 + 101)
				if driveway_roll < 0.07 and not near_junction:
					driveway_gaps += 1
					continue
				var curb_center: Vector3 = midpoint + side * side_sign * (half_width + 0.20)
				var curb_transform := make_transform(
					Vector3(curb_center.x, midpoint.y + 0.145, curb_center.z),
					yaw,
					Vector3(0.26, 0.19, length + 0.05)
				)
				if near_junction and i % 2 == 0:
					painted_curb_transforms.append(curb_transform)
				else:
					curb_transforms.append(curb_transform)
		road_index += 1

	var slab_material := _material(
		"sidewalk",
		"user_concrete_slabs.jpg",
		"user_concrete_slabs_normal.jpg",
		Color(0.52, 0.53, 0.52),
		0.96,
		0.0,
		Vector3(0.16, 0.16, 0.16),
		true
	)
	var curb_material := _material(
		"road_curb",
		"user_concrete_slabs.jpg",
		"user_concrete_slabs_normal.jpg",
		Color(0.36, 0.37, 0.36),
		0.97,
		0.0,
		Vector3(0.30, 0.30, 0.30),
		true
	)
	var painted_curb_material := _material(
		"road_curb_painted",
		"user_concrete_slabs.jpg",
		"user_concrete_slabs_normal.jpg",
		Color(0.72, 0.48, 0.08),
		0.90,
		0.0,
		Vector3(0.30, 0.30, 0.30),
		true
	)
	var gutter_material := _material(
		"road_gutter",
		"asphalt_city.jpg",
		"",
		Color(0.34, 0.35, 0.36),
		0.94,
		0.0,
		Vector3(0.18, 0.18, 0.18),
		true
	)
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3.ONE
	box_mesh.material = slab_material
	_add_multimesh(parent, box_mesh, gutter_material, gutter_transforms, "RoadGutters", false)
	_add_multimesh(parent, box_mesh, curb_material, curb_transforms, "RoadCurbs", true)
	_add_multimesh(parent, box_mesh, painted_curb_material, painted_curb_transforms, "RoadPaintedCurbs", true)
	_add_multimesh(parent, box_mesh, slab_material, slab_transforms, "RaisedSidewalkSlabs", true)
	_enhancement_stats["road_gutters"] = gutter_transforms.size()
	_enhancement_stats["concrete_curbs"] = curb_transforms.size() + painted_curb_transforms.size()
	_enhancement_stats["painted_curbs"] = painted_curb_transforms.size()
	_enhancement_stats["raised_sidewalk_slabs"] = slab_transforms.size()
	_enhancement_stats["driveway_curb_gaps"] = driveway_gaps


func _append_lane_arrow(transforms: Array, lane_center: Vector3, direction: Vector3, surface_y: float) -> void:
	var flat_direction := direction
	flat_direction.y = 0.0
	if flat_direction.length_squared() < 0.0001:
		return
	flat_direction = flat_direction.normalized()
	var side := Vector3(-flat_direction.z, 0.0, flat_direction.x)
	var yaw := atan2(flat_direction.x, flat_direction.z)
	var paint_y := surface_y + 0.019
	var shaft_center: Vector3 = lane_center - flat_direction * 0.48
	transforms.append(make_transform(
		Vector3(shaft_center.x, paint_y, shaft_center.z),
		yaw,
		Vector3(0.34, 0.032, 2.70)
	))
	var tip: Vector3 = lane_center + flat_direction * 1.15
	for wing_sign_variant in [-1.0, 1.0]:
		var wing_direction: Vector3 = (-flat_direction * 0.72 + side * float(wing_sign_variant) * 0.69).normalized()
		var wing_center: Vector3 = tip + wing_direction * 0.48
		transforms.append(make_transform(
			Vector3(wing_center.x, paint_y, wing_center.z),
			atan2(wing_direction.x, wing_direction.z),
			Vector3(0.29, 0.032, 1.22)
		))


func _build_road_markings(parent: Node) -> void:
	# Paint is split into new/worn/faded batches. The geometry is still
	# cheap thin boxes, but adjacent segments no longer look like one
	# perfectly clean plastic strip laid over the whole city.
	var stripe_groups: Array[Array] = [[], [], []]
	var edge_groups: Array[Array] = [[], [], []]
	var dash_groups: Array[Array] = [[], [], []]
	var arrow_groups: Array[Array] = [[], [], []]
	var parking_groups: Array[Array] = [[], [], []]
	var center_groups: Array[Array] = [[], []]
	var bike_transforms: Array[Transform3D] = []
	var tactile_transforms: Array[Transform3D] = []
	var lane_arrow_count := 0
	var road_index := 0

	for road_variant in data.get("roads", []):
		var road: Dictionary = road_variant
		var road_id := String(road.get("id", ""))
		var samples: Array = road.get("samples", [])
		if samples.size() < 2:
			road_index += 1
			continue
		var width := _f(road, "widthM", 10.0)
		var half_width := width * 0.5
		var lanes := maxi(int(road.get("lanes", 2)), 1)
		var divider_offsets: Array[float] = []
		var lane_centers: Array[float] = [-width * 0.25, width * 0.25]
		if lanes >= 4 or width >= 17.0:
			divider_offsets = [-width * 0.25, width * 0.25]
			lane_centers = [-width * 0.375, -width * 0.125, width * 0.125, width * 0.375]
		var points: Array[Vector3] = []
		for sample in samples:
			points.append(_sample_point(sample))
		var total_length := 0.0
		for point_index in range(points.size() - 1):
			var flat_segment := points[point_index + 1] - points[point_index]
			flat_segment.y = 0.0
			total_length += flat_segment.length()
		var start_direction := points[1] - points[0]
		var end_direction := points[points.size() - 1] - points[points.size() - 2]
		var start_info := _junction_info(points[0], road_id, start_direction)
		var end_info := _junction_info(points[points.size() - 1], road_id, end_direction)
		var trim_start := float(start_info.get("trim_m", 0.0))
		var trim_end := float(end_info.get("trim_m", 0.0))
		var has_parking := road_id.begins_with("rt-west") or road_id.begins_with("rt-st")
		var parking_side := 1.0 if road_index % 2 == 0 else -1.0
		var has_bike_lane := road_id.begins_with("rt-east")
		var distance_from_start := 0.0

		for i in range(points.size() - 1):
			var a := points[i]
			var b := points[i + 1]
			var segment := b - a
			segment.y = 0.0
			var length := segment.length()
			var segment_start := distance_from_start
			distance_from_start += length
			var segment_end := distance_from_start
			if length < 0.45:
				continue
			var direction := segment / length
			var side := Vector3(-direction.z, 0.0, direction.x)
			var yaw := atan2(direction.x, direction.z)
			var midpoint := (a + b) * 0.5
			var crown_scale := _road_crown_scale(segment_start + length * 0.5, total_length, trim_start, trim_end)
			var near_edge_break := (trim_start > 0.0 and segment_start < trim_start + 1.0) or (trim_end > 0.0 and segment_end > total_length - trim_end - 1.0)
			var near_paint_break := (trim_start > 0.0 and segment_start < trim_start + 4.2) or (trim_end > 0.0 and segment_end > total_length - trim_end - 4.2)

			if not near_edge_break:
				for edge_side_variant in [-1.0, 1.0]:
					var edge_side := float(edge_side_variant)
					var edge_offset := edge_side * maxf(half_width - 0.42, 0.6)
					var edge_center: Vector3 = midpoint + side * edge_offset
					var edge_group := mini(2, int(_hash01(road_index * 271 + i * 11, int(edge_side) * 43 + 17) * 3.0))
					(edge_groups[edge_group] as Array).append(make_transform(
						Vector3(edge_center.x, _road_surface_y(midpoint.y, edge_offset, half_width, crown_scale) + 0.019, edge_center.z),
						yaw,
						Vector3(0.16, 0.034, length + 0.05)
					))

			if not near_paint_break:
				# Opposing traffic is separated by a double yellow solid
				# centreline. White dashes below are only between lanes
				# travelling in the same direction.
				for center_offset_variant in [-0.18, 0.18]:
					var center_offset := float(center_offset_variant)
					var center_point: Vector3 = midpoint + side * center_offset
					var center_group := 0 if _hash01(road_index * 149 + i * 7, 91) < 0.68 else 1
					(center_groups[center_group] as Array).append(make_transform(
						Vector3(center_point.x, _road_surface_y(midpoint.y, center_offset, half_width, crown_scale) + 0.018, center_point.z),
						yaw,
						Vector3(0.145, 0.032, length + 0.04)
					))

				for lane_offset in divider_offsets:
					var wear_roll := _hash01(road_index * 331 + i * 19, int(lane_offset * 10.0) + 53)
					if wear_roll < 0.08:
						continue
					var dash_center: Vector3 = midpoint + side * lane_offset
					var dash_group := mini(2, int(wear_roll * 3.0))
					var dash_length := minf(3.0, length * (0.46 + 0.12 * wear_roll))
					(dash_groups[dash_group] as Array).append(make_transform(
						Vector3(dash_center.x, _road_surface_y(midpoint.y, lane_offset, half_width, crown_scale) + 0.020, dash_center.z),
						yaw,
						Vector3(0.17, 0.036, dash_length)
					))

				if has_parking:
					var parking_group := mini(2, int(_hash01(road_index * 113 + i * 23, 61) * 3.0))
					var boundary_offset := parking_side * (half_width - 2.28)
					var boundary_center: Vector3 = midpoint + side * boundary_offset
					(parking_groups[parking_group] as Array).append(make_transform(
						Vector3(boundary_center.x, _road_surface_y(midpoint.y, boundary_offset, half_width, crown_scale) + 0.017, boundary_center.z),
						yaw,
						Vector3(0.13, 0.030, length + 0.03)
					))
					var tick_offset := parking_side * (half_width - 1.28)
					var tick_center: Vector3 = midpoint + side * tick_offset
					(parking_groups[parking_group] as Array).append(make_transform(
						Vector3(tick_center.x, _road_surface_y(midpoint.y, tick_offset, half_width, crown_scale) + 0.017, tick_center.z),
						yaw + PI * 0.5,
						Vector3(0.13, 0.030, 1.90)
					))

			if has_bike_lane:
				# The seaward side of the Corniche is world +X regardless
				# of the exported chain direction.
				var seaward_sign := 1.0 if side.x >= 0.0 else -1.0
				var bike_offset := seaward_sign * (half_width - 1.24)
				var bike_center: Vector3 = midpoint + side * bike_offset
				bike_transforms.append(make_transform(
					Vector3(bike_center.x, _road_surface_y(midpoint.y, bike_offset, half_width, crown_scale) + 0.007, bike_center.z),
					yaw,
					Vector3(1.52, 0.018, length + 0.03)
				))
				if not near_paint_break:
					var bike_line_offset := seaward_sign * (half_width - 2.06)
					var bike_line_center: Vector3 = midpoint + side * bike_line_offset
					var bike_group := mini(2, int(_hash01(road_index * 181 + i * 29, 73) * 3.0))
					(edge_groups[bike_group] as Array).append(make_transform(
						Vector3(bike_line_center.x, _road_surface_y(midpoint.y, bike_line_offset, half_width, crown_scale) + 0.018, bike_line_center.z),
						yaw,
						Vector3(0.14, 0.032, length + 0.04)
					))

		if total_length > 34.0:
			var chain_direction := start_direction
			chain_direction.y = 0.0
			if chain_direction.length_squared() > 0.0001:
				chain_direction = chain_direction.normalized()
				var chain_side := Vector3(-chain_direction.z, 0.0, chain_direction.x)
				if bool(start_info.get("is_junction", false)):
					var start_centerline: Vector3 = points[0] + chain_direction * 15.0
					var start_crown := _road_crown_scale(15.0, total_length, trim_start, trim_end)
					for lane_offset in lane_centers:
						if lane_offset >= 0.0:
							continue
						var lane_center: Vector3 = start_centerline + chain_side * lane_offset
						var arrow_group := mini(2, int(_hash01(road_index * 211, int(lane_offset * 10.0) + 31) * 3.0))
						_append_lane_arrow(
							arrow_groups[arrow_group] as Array,
							lane_center,
							-chain_direction,
							_road_surface_y(points[0].y, lane_offset, half_width, start_crown)
						)
						lane_arrow_count += 1
				if bool(end_info.get("is_junction", false)):
					var end_centerline: Vector3 = points[points.size() - 1] - chain_direction * 15.0
					var end_crown := _road_crown_scale(total_length - 15.0, total_length, trim_start, trim_end)
					for lane_offset in lane_centers:
						if lane_offset <= 0.0:
							continue
						var lane_center: Vector3 = end_centerline + chain_side * lane_offset
						var arrow_group := mini(2, int(_hash01(road_index * 223 + 7, int(lane_offset * 10.0) + 37) * 3.0))
						_append_lane_arrow(
							arrow_groups[arrow_group] as Array,
							lane_center,
							chain_direction,
							_road_surface_y(points[points.size() - 1].y, lane_offset, half_width, end_crown)
						)
						lane_arrow_count += 1
		road_index += 1

	var vertical_roads := [
		{"x": 560.0, "width": 11.0},
		{"x": 760.0, "width": 22.0},
		{"x": 930.0, "width": 24.0},
	]
	var cross_z := [-430.0, -300.0, -250.0, -110.0, 60.0, 225.0, 430.0]

	for vertical_variant in vertical_roads:
		var vertical: Dictionary = vertical_variant
		var center_x := float(vertical.get("x", 760.0))
		var width := float(vertical.get("width", 12.0))
		for z_variant in cross_z:
			var center_z := float(z_variant)
			var cross_width := 16.0 if absf(center_z - 225.0) < 0.1 else 13.0
			# Zebra crossings on both approaches to the vertical road.
			for side_variant in [-1.0, 1.0]:
				var side := float(side_variant)
				var crossing_z: float = center_z + side * (cross_width * 0.5 + 2.35)
				var stripe_count := maxi(int(floor((width - 1.4) / 1.08)), 3)
				var start_x := center_x - float(stripe_count - 1) * 0.54
				for i in stripe_count:
					var wear_roll := _hash01(int(center_x) + i * 17, int(crossing_z) + 431)
					if wear_roll < 0.035:
						continue
					var x := start_x + float(i) * 1.08
					var y := _road_surface_y(height_at(x, crossing_z), x - center_x, width * 0.5, 0.34) + 0.016
					var stripe_group := mini(2, int(wear_roll * 3.0))
					(stripe_groups[stripe_group] as Array).append(make_transform(
						Vector3(x, y, crossing_z),
						0.0,
						Vector3(0.58, 0.028, 3.15 * (0.96 + 0.06 * wear_roll))
					))
				var stop_z: float = crossing_z + side * 2.15
				var stop_center_x := center_x + side * width * 0.25
				var stop_group := mini(2, int(_hash01(int(stop_center_x), int(stop_z) + 907) * 3.0))
				(stripe_groups[stop_group] as Array).append(make_transform(
					Vector3(stop_center_x, _road_surface_y(height_at(stop_center_x, stop_z), width * 0.25, width * 0.5, 0.64) + 0.016, stop_z),
					0.0,
					Vector3(width * 0.48, 0.028, 0.42)
				))
				for end_sign_variant in [-1.0, 1.0]:
					var end_sign := float(end_sign_variant)
					var tactile_x := center_x + end_sign * (width * 0.5 + 0.95)
					tactile_transforms.append(make_transform(
						Vector3(tactile_x, height_at(tactile_x, crossing_z) + 0.242, crossing_z),
						0.0,
						Vector3(0.95, 0.024, 0.75)
					))

			# Matching zebras across the horizontal street.
			for side_variant in [-1.0, 1.0]:
				var side := float(side_variant)
				var crossing_x: float = center_x + side * (width * 0.5 + 2.35)
				var stripe_count_h := maxi(int(floor((cross_width - 1.4) / 1.08)), 3)
				var start_z := center_z - float(stripe_count_h - 1) * 0.54
				for i in stripe_count_h:
					var wear_roll := _hash01(int(crossing_x) + 613, int(center_z) + i * 19)
					if wear_roll < 0.035:
						continue
					var z := start_z + float(i) * 1.08
					var y := _road_surface_y(height_at(crossing_x, z), z - center_z, cross_width * 0.5, 0.34) + 0.016
					var stripe_group := mini(2, int(wear_roll * 3.0))
					(stripe_groups[stripe_group] as Array).append(make_transform(
						Vector3(crossing_x, y, z),
						0.0,
						Vector3(3.15 * (0.96 + 0.06 * wear_roll), 0.028, 0.58)
					))
				var stop_x: float = crossing_x + side * 2.15
				var stop_center_z := center_z - side * cross_width * 0.25
				var stop_group := mini(2, int(_hash01(int(stop_x) + 719, int(stop_center_z)) * 3.0))
				(stripe_groups[stop_group] as Array).append(make_transform(
					Vector3(stop_x, _road_surface_y(height_at(stop_x, stop_center_z), cross_width * 0.25, cross_width * 0.5, 0.64) + 0.016, stop_center_z),
					0.0,
					Vector3(0.42, 0.028, cross_width * 0.48)
				))
				for end_sign_variant in [-1.0, 1.0]:
					var end_sign := float(end_sign_variant)
					var tactile_z := center_z + end_sign * (cross_width * 0.5 + 0.95)
					tactile_transforms.append(make_transform(
						Vector3(crossing_x, height_at(crossing_x, tactile_z) + 0.242, tactile_z),
						0.0,
						Vector3(0.75, 0.024, 0.95)
					))

	var white_paints: Array[StandardMaterial3D] = [
		_material("road_paint_new", "", "user_asphalt_plain_normal.jpg", Color(0.88, 0.90, 0.88), 0.68),
		_material("road_paint_worn", "", "user_asphalt_plain_normal.jpg", Color(0.735, 0.755, 0.725), 0.79),
		_material("road_paint_faded", "", "user_asphalt_plain_normal.jpg", Color(0.60, 0.62, 0.59), 0.87),
	]
	for paint in white_paints:
		paint.metallic_specular = 0.30
		paint.normal_scale = 0.38
	var yellow_paints: Array[StandardMaterial3D] = [
		_material("road_center_paint", "", "user_asphalt_plain_normal.jpg", Color(0.78, 0.55, 0.075), 0.72),
		_material("road_center_paint_worn", "", "user_asphalt_plain_normal.jpg", Color(0.63, 0.45, 0.08), 0.84),
	]
	for paint in yellow_paints:
		paint.metallic_specular = 0.28
		paint.normal_scale = 0.38
	var bike_material := _material("bike_lane", "user_asphalt_plain.jpg", "user_asphalt_plain_normal.jpg", Color(0.10, 0.35, 0.24), 0.89, 0.0, Vector3(0.22, 0.22, 0.22), true)
	bike_material.metallic_specular = 0.30
	var tactile_material := _material("tactile_paving", "", "user_black_rough_normal.jpg", Color(0.70, 0.56, 0.21), 0.92)
	tactile_material.normal_scale = 0.85

	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3.ONE
	stripe_mesh.material = white_paints[0]
	var stripe_total := 0
	var edge_total := 0
	var dash_total := 0
	var arrow_total := 0
	var parking_total := 0
	var center_total := 0
	for group in 3:
		stripe_total += (stripe_groups[group] as Array).size()
		edge_total += (edge_groups[group] as Array).size()
		dash_total += (dash_groups[group] as Array).size()
		arrow_total += (arrow_groups[group] as Array).size()
		parking_total += (parking_groups[group] as Array).size()
		# One batch per paint shade, not one per marking category: all
		# five categories share the same unit box and material, so this
		# preserves the worn look without multiplying draw submissions.
		var combined_white: Array = []
		combined_white.append_array(stripe_groups[group])
		combined_white.append_array(edge_groups[group])
		combined_white.append_array(dash_groups[group])
		combined_white.append_array(arrow_groups[group])
		combined_white.append_array(parking_groups[group])
		_add_multimesh(parent, stripe_mesh, white_paints[group], combined_white, "CrosswalkRoadEdgeLanePaint_W%d" % group, false)
	for group in 2:
		center_total += (center_groups[group] as Array).size()
		_add_multimesh(parent, stripe_mesh, yellow_paints[group], center_groups[group], "RoadCenterLines_Y%d" % group, false)
	_add_multimesh(parent, stripe_mesh, bike_material, bike_transforms, "BikeLaneSurfaces", false)
	_add_multimesh(parent, stripe_mesh, tactile_material, tactile_transforms, "TactilePaving", false)

	_enhancement_stats["crosswalk_markings"] = stripe_total
	_enhancement_stats["road_edge_lines"] = edge_total
	_enhancement_stats["lane_dashes"] = dash_total
	_enhancement_stats["center_lines"] = center_total
	_enhancement_stats["lane_arrows"] = lane_arrow_count
	_enhancement_stats["parking_markings"] = parking_total
	_enhancement_stats["bike_lane_segments"] = bike_transforms.size()
	_enhancement_stats["tactile_paving"] = tactile_transforms.size()
	_enhancement_stats["road_markings"] = stripe_total + edge_total + dash_total + center_total + arrow_total + parking_total


func _build_road_details(parent: Node) -> void:
	# Small repeated furniture sells the road at chase-camera height:
	# inspection covers, curb drains, repaired rectangles, tar seams,
	# oil, braking rubber and reflective studs. Everything is instanced
	# and chunked by _add_multimesh(); there are no per-item nodes.
	var manhole_transforms: Array[Transform3D] = []
	var drainage_transforms: Array[Transform3D] = []
	var patch_city_transforms: Array[Transform3D] = []
	var patch_pothole_transforms: Array[Transform3D] = []
	var tar_transforms: Array[Transform3D] = []
	var oil_transforms: Array[Transform3D] = []
	var skid_transforms: Array[Transform3D] = []
	var stud_white_transforms: Array[Transform3D] = []
	var stud_yellow_transforms: Array[Transform3D] = []
	var stud_red_transforms: Array[Transform3D] = []
	var road_index := 0
	var bridge_ids := ["rt-palm-1", "rt-sail-road"]

	for road_variant in data.get("roads", []):
		var road: Dictionary = road_variant
		var road_id := String(road.get("id", ""))
		var samples: Array = road.get("samples", [])
		if samples.size() < 2:
			road_index += 1
			continue
		var width := _f(road, "widthM", 10.0)
		var half_width := width * 0.5
		var lanes := maxi(int(road.get("lanes", 2)), 1)
		var lane_centers: Array[float] = [-width * 0.25, width * 0.25]
		var divider_offsets: Array[float] = []
		if lanes >= 4 or width >= 17.0:
			lane_centers = [-width * 0.375, -width * 0.125, width * 0.125, width * 0.375]
			divider_offsets = [-width * 0.25, width * 0.25]
		var points: Array[Vector3] = []
		for sample in samples:
			points.append(_sample_point(sample))
		var total_length := 0.0
		for point_index in range(points.size() - 1):
			var flat_segment := points[point_index + 1] - points[point_index]
			flat_segment.y = 0.0
			total_length += flat_segment.length()
		var start_direction := points[1] - points[0]
		var end_direction := points[points.size() - 1] - points[points.size() - 2]
		var start_info := _junction_info(points[0], road_id, start_direction)
		var end_info := _junction_info(points[points.size() - 1], road_id, end_direction)
		var trim_start := float(start_info.get("trim_m", 0.0))
		var trim_end := float(end_info.get("trim_m", 0.0))
		var is_bridge := bridge_ids.has(road_id)
		var distance_from_start := 0.0

		for i in range(points.size() - 1):
			var a := points[i]
			var b := points[i + 1]
			var segment := b - a
			segment.y = 0.0
			var length := segment.length()
			var segment_start := distance_from_start
			distance_from_start += length
			var segment_end := distance_from_start
			if length < 0.45:
				continue
			var direction := segment / length
			var side := Vector3(-direction.z, 0.0, direction.x)
			var yaw := atan2(direction.x, direction.z)
			var midpoint := (a + b) * 0.5
			var crown_scale := _road_crown_scale(segment_start + length * 0.5, total_length, trim_start, trim_end)
			var near_junction := (trim_start > 0.0 and segment_start < trim_start + 2.0) or (trim_end > 0.0 and segment_end > total_length - trim_end - 2.0)
			var detail_roll := _hash01(road_index * 401 + i * 31, 17)
			var lane_roll := _hash01(road_index * 419 + i * 37, 29)
			var lane_offset := lane_centers[mini(lane_centers.size() - 1, int(lane_roll * float(lane_centers.size())))]

			if is_bridge and i % 2 == 0:
				tar_transforms.append(make_transform(
					Vector3(midpoint.x, _road_surface_y(midpoint.y, half_width * 0.5, half_width, crown_scale) + 0.007, midpoint.z),
					yaw,
					Vector3(width - 1.1, 0.012, 0.18)
				))

			if near_junction:
				continue

			if not is_bridge and i % 7 == road_index % 7:
				var manhole_center: Vector3 = midpoint + side * lane_offset
				manhole_transforms.append(make_transform(
					Vector3(manhole_center.x, _road_surface_y(midpoint.y, lane_offset, half_width, crown_scale) + 0.012, manhole_center.z),
					yaw,
					Vector3(0.86, 0.022, 0.86)
				))

			if not is_bridge and i % 6 == (road_index + 2) % 6:
				var drain_side := 1.0 if int(i / 6) % 2 == 0 else -1.0
				var drain_offset := drain_side * (half_width - 0.62)
				var drain_center: Vector3 = midpoint + side * drain_offset
				drainage_transforms.append(make_transform(
					Vector3(drain_center.x, _road_surface_y(midpoint.y, drain_offset, half_width, crown_scale) + 0.013, drain_center.z),
					yaw,
					Vector3(0.58, 0.024, 0.92)
				))

			if detail_roll < 0.11:
				var patch_center: Vector3 = midpoint + side * lane_offset
				var patch_transform := make_transform(
					Vector3(patch_center.x, _road_surface_y(midpoint.y, lane_offset, half_width, crown_scale) + 0.008, patch_center.z),
					yaw + (detail_roll - 0.055) * 0.7,
					Vector3(1.9 + lane_roll * 1.5, 0.014, 3.6 + detail_roll * 24.0)
				)
				if detail_roll < 0.035:
					patch_pothole_transforms.append(patch_transform)
				else:
					patch_city_transforms.append(patch_transform)
			elif detail_roll < 0.30:
				var tar_offset := lane_offset + (lane_roll - 0.5) * 1.4
				var tar_center: Vector3 = midpoint + side * tar_offset
				tar_transforms.append(make_transform(
					Vector3(tar_center.x, _road_surface_y(midpoint.y, tar_offset, half_width, crown_scale) + 0.007, tar_center.z),
					yaw + (lane_roll - 0.5) * 0.45,
					Vector3(0.13, 0.012, 2.2 + detail_roll * 7.0)
				))
			elif detail_roll < 0.42:
				var oil_center: Vector3 = midpoint + side * lane_offset
				oil_transforms.append(make_transform(
					Vector3(oil_center.x, _road_surface_y(midpoint.y, lane_offset, half_width, crown_scale) + 0.006, oil_center.z),
					yaw,
					Vector3(1.25 + lane_roll * 1.1, 0.012, 2.7 + detail_roll * 4.0)
				))

			var add_studs := (width >= 17.0 and i % 2 == 0) or (width < 17.0 and i % 3 == 0)
			if add_studs:
				stud_yellow_transforms.append(make_transform(
					Vector3(midpoint.x, _road_surface_y(midpoint.y, 0.0, half_width, crown_scale) + 0.016, midpoint.z),
					yaw,
					Vector3(0.11, 0.028, 0.11)
				))
				if width >= 17.0:
					for divider_offset in divider_offsets:
						var stud_center: Vector3 = midpoint + side * divider_offset
						stud_white_transforms.append(make_transform(
							Vector3(stud_center.x, _road_surface_y(midpoint.y, divider_offset, half_width, crown_scale) + 0.016, stud_center.z),
							yaw,
							Vector3(0.11, 0.028, 0.11)
						))
					for edge_sign_variant in [-1.0, 1.0]:
						var edge_offset := float(edge_sign_variant) * (half_width - 0.24)
						var edge_stud: Vector3 = midpoint + side * edge_offset
						stud_red_transforms.append(make_transform(
							Vector3(edge_stud.x, _road_surface_y(midpoint.y, edge_offset, half_width, crown_scale) + 0.016, edge_stud.z),
							yaw,
							Vector3(0.11, 0.028, 0.11)
						))

		if total_length > 45.0 and _hash01(road_index * 521, 71) < 0.62:
			var chain_direction := start_direction
			chain_direction.y = 0.0
			if chain_direction.length_squared() > 0.0001:
				chain_direction = chain_direction.normalized()
				var chain_side := Vector3(-chain_direction.z, 0.0, chain_direction.x)
				var chain_yaw := atan2(chain_direction.x, chain_direction.z)
				if bool(start_info.get("is_junction", false)):
					var start_centerline: Vector3 = points[0] + chain_direction * 20.0
					var start_crown := _road_crown_scale(20.0, total_length, trim_start, trim_end)
					for lane_offset in lane_centers:
						if lane_offset >= 0.0:
							continue
						for wheel_delta_variant in [-0.78, 0.78]:
							var wheel_offset := lane_offset + float(wheel_delta_variant)
							var skid_center: Vector3 = start_centerline + chain_side * wheel_offset
							skid_transforms.append(make_transform(
								Vector3(skid_center.x, _road_surface_y(points[0].y, wheel_offset, half_width, start_crown) + 0.005, skid_center.z),
								chain_yaw,
								Vector3(0.27, 0.009, 10.0)
							))
				if bool(end_info.get("is_junction", false)):
					var end_centerline: Vector3 = points[points.size() - 1] - chain_direction * 20.0
					var end_crown := _road_crown_scale(total_length - 20.0, total_length, trim_start, trim_end)
					for lane_offset in lane_centers:
						if lane_offset <= 0.0:
							continue
						for wheel_delta_variant in [-0.78, 0.78]:
							var wheel_offset := lane_offset + float(wheel_delta_variant)
							var skid_center: Vector3 = end_centerline + chain_side * wheel_offset
							skid_transforms.append(make_transform(
								Vector3(skid_center.x, _road_surface_y(points[points.size() - 1].y, wheel_offset, half_width, end_crown) + 0.005, skid_center.z),
								chain_yaw,
								Vector3(0.27, 0.009, 10.0)
							))
		road_index += 1

	# Detailed Blender mast-arm signals replace the 0.2.6 primitive
	# pole/arm/head boxes. There is deliberately no phase controller:
	# the GLB's SignalRedOn lens is lit, amber and green are dark.
	# Model convention after glTF Y-up export: pole at the origin, arm
	# along local +X and lenses facing local -Z.
	var signal_short_transforms: Array[Transform3D] = []
	var signal_long_transforms: Array[Transform3D] = []
	var signal_count := 0
	var signal_verticals := [
		{"x": 560.0, "width": 11.0},
		{"x": 760.0, "width": 22.0},
		{"x": 930.0, "width": 24.0},
	]
	var signal_cross_z := [-430.0, -300.0, -250.0, -110.0, 60.0, 225.0, 430.0]
	for vertical_variant in signal_verticals:
		var vertical: Dictionary = vertical_variant
		var center_x := float(vertical.get("x", 760.0))
		var vertical_width := float(vertical.get("width", 12.0))
		var vertical_half := vertical_width * 0.5
		for z_variant in signal_cross_z:
			var center_z := float(z_variant)
			var cross_width := 16.0 if absf(center_z - 225.0) < 0.1 else 13.0
			var cross_half := cross_width * 0.5
			var approaches := [
				{"head": Vector2(vertical_width * 0.25, -(cross_half + 1.0)), "arm_dir": Vector2(-1.0, 0.0), "yaw": PI, "long": vertical_width >= 17.0},
				{"head": Vector2(-vertical_width * 0.25, cross_half + 1.0), "arm_dir": Vector2(1.0, 0.0), "yaw": 0.0, "long": vertical_width >= 17.0},
				{"head": Vector2(vertical_half + 1.0, cross_width * 0.25), "arm_dir": Vector2(0.0, -1.0), "yaw": PI * 0.5, "long": false},
				{"head": Vector2(-(vertical_half + 1.0), -cross_width * 0.25), "arm_dir": Vector2(0.0, 1.0), "yaw": -PI * 0.5, "long": false},
			]
			for approach_variant in approaches:
				var approach: Dictionary = approach_variant
				var head_offset: Vector2 = approach.get("head", Vector2.ZERO)
				var arm_dir: Vector2 = approach.get("arm_dir", Vector2.RIGHT)
				var is_long := bool(approach.get("long", false))
				# The far/only Blender signal head is 4.18 m from the
				# short pole and 6.68 m from the long pole.
				var head_reach := 6.68 if is_long else 4.18
				var pole_offset: Vector2 = head_offset - arm_dir * head_reach
				var pole_x := center_x + pole_offset.x
				var pole_z := center_z + pole_offset.y
				var ground_y := height_at(pole_x, pole_z) + 0.14
				var signal_transform := make_transform(
					Vector3(pole_x, ground_y, pole_z),
					float(approach.get("yaw", 0.0)),
					Vector3.ONE
				)
				if is_long:
					signal_long_transforms.append(signal_transform)
				else:
					signal_short_transforms.append(signal_transform)
				_add_cylinder_collider(Vector3(pole_x, ground_y + 2.95, pole_z), 0.14, 5.90)
				signal_count += 1


	var manhole_material := _material("manhole_metal", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.20, 0.22, 0.24), 0.48, 0.72, Vector3(2.5, 2.5, 1.0))
	var drainage_material := _material("drainage_metal", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.13, 0.15, 0.17), 0.42, 0.76, Vector3(4.0, 4.0, 1.0))
	var patch_city_material := _material("asphalt_patch_city", "asphalt_city.jpg", "", Color(0.44, 0.45, 0.46), 0.96)
	var patch_pothole_material := _material("asphalt_patch_pothole", "user_asphalt_pothole.jpg", "user_asphalt_pothole_normal.jpg", Color(0.46, 0.46, 0.47), 0.98)
	var tar_material := _material("tar_seam", "user_black_rough.jpg", "user_black_rough_normal.jpg", Color(0.10, 0.10, 0.11), 0.82)
	var oil_material := _material("oil_stain", "", "", Color(0.012, 0.014, 0.018, 0.36), 0.30)
	oil_material.metallic_specular = 0.80
	var skid_material := _material("skid_mark", "", "", Color(0.010, 0.010, 0.012, 0.28), 0.55)
	skid_material.metallic_specular = 0.35

	var stud_white := _material("road_stud_white", "", "", Color(0.82, 0.84, 0.80), 0.42)
	stud_white.emission_enabled = true
	stud_white.emission = Color(0.9, 0.95, 0.9)
	_register_night_material(stud_white, 0.03, 0.45, 1.25)
	var stud_yellow := _material("road_stud_yellow", "", "", Color(0.78, 0.55, 0.07), 0.44)
	stud_yellow.emission_enabled = true
	stud_yellow.emission = Color(1.0, 0.62, 0.08)
	_register_night_material(stud_yellow, 0.03, 0.45, 1.25)
	var stud_red := _material("road_stud_red", "", "", Color(0.52, 0.06, 0.045), 0.44)
	stud_red.emission_enabled = true
	stud_red.emission = Color(1.0, 0.08, 0.04)
	_register_night_material(stud_red, 0.03, 0.45, 1.25)

	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3.ONE
	box_mesh.material = tar_material
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 0.5
	disc_mesh.bottom_radius = 0.5
	disc_mesh.height = 1.0
	disc_mesh.radial_segments = 20
	disc_mesh.rings = 1
	disc_mesh.material = manhole_material

	_add_multimesh(parent, disc_mesh, manhole_material, manhole_transforms, "Manholes", false)
	_add_multimesh(parent, box_mesh, drainage_material, drainage_transforms, "DrainageGrates", false)
	_add_multimesh(parent, box_mesh, patch_city_material, patch_city_transforms, "AsphaltPatchesCity", false)
	_add_multimesh(parent, box_mesh, patch_pothole_material, patch_pothole_transforms, "AsphaltPatchesPothole", false)
	_add_multimesh(parent, box_mesh, tar_material, tar_transforms, "TarSeams", false)
	_add_multimesh(parent, disc_mesh, oil_material, oil_transforms, "OilStains", false)
	_add_multimesh(parent, box_mesh, skid_material, skid_transforms, "SkidMarks", false)
	_add_multimesh(parent, box_mesh, stud_white, stud_white_transforms, "RoadStudsWhite", false)
	_add_multimesh(parent, box_mesh, stud_yellow, stud_yellow_transforms, "RoadStudsYellow", false)
	_add_multimesh(parent, box_mesh, stud_red, stud_red_transforms, "RoadStudsRed", false)
	var signal_short_built := _add_batched_model(parent, "res://assets/props/traffic_signal_short.glb", signal_short_transforms, "BlenderTrafficSignalsShort")
	var signal_long_built := _add_batched_model(parent, "res://assets/props/traffic_signal_long.glb", signal_long_transforms, "BlenderTrafficSignalsLong")

	_enhancement_stats["manholes"] = manhole_transforms.size()
	_enhancement_stats["drainage_grates"] = drainage_transforms.size()
	_enhancement_stats["asphalt_patches"] = patch_city_transforms.size() + patch_pothole_transforms.size()
	_enhancement_stats["tar_seams"] = tar_transforms.size()
	_enhancement_stats["oil_stains"] = oil_transforms.size()
	_enhancement_stats["skid_marks"] = skid_transforms.size()
	_enhancement_stats["road_studs"] = stud_white_transforms.size() + stud_yellow_transforms.size() + stud_red_transforms.size()
	_enhancement_stats["traffic_signals"] = signal_count
	_enhancement_stats["traffic_signal_models"] = (signal_short_transforms.size() if signal_short_built else 0) + (signal_long_transforms.size() if signal_long_built else 0)
	_enhancement_stats["traffic_signal_static_red"] = signal_short_built and signal_long_built


func _build_bridge_guardrails(parent: Node) -> void:
	var post_transforms: Array[Transform3D] = []
	var rail_transforms: Array[Transform3D] = []
	var bridge_ids := ["rt-palm-1", "rt-sail-road"]
	for road_variant in data.get("roads", []):
		var road: Dictionary = road_variant
		if not bridge_ids.has(String(road.get("id", ""))):
			continue
		var samples: Array = road.get("samples", [])
		var half_width := _f(road, "widthM", 12.0) * 0.5 - 0.38
		for i in range(samples.size() - 1):
			var a := _sample_point(samples[i])
			var b := _sample_point(samples[i + 1])
			var direction := b - a
			direction.y = 0.0
			if direction.length_squared() < 0.001:
				continue
			direction = direction.normalized()
			var side_vector := Vector3(-direction.z, 0.0, direction.x)
			var yaw := atan2(-direction.x, -direction.z)
			var segment_length := a.distance_to(b)
			for side in [-1.0, 1.0]:
				var edge_a: Vector3 = a + side_vector * half_width * float(side) + Vector3.UP * 0.10
				var edge_b: Vector3 = b + side_vector * half_width * float(side) + Vector3.UP * 0.10
				if i % 2 == 0:
					post_transforms.append(make_transform(edge_a + Vector3.UP * 0.43, yaw, Vector3(0.16, 0.86, 0.16)))
				var centre: Vector3 = (edge_a + edge_b) * 0.5
				_add_box_collider(centre + Vector3.UP * 0.45, Vector3(0.24, 0.92, segment_length + 0.05), yaw)
				for rail_height in [0.52, 0.82]:
					rail_transforms.append(make_transform(centre + Vector3.UP * rail_height, yaw, Vector3(0.09, 0.13, segment_length + 0.08)))

	var metal := _prop_material("PropsMetal")
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3.ONE
	post_mesh.material = metal
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3.ONE
	rail_mesh.material = metal
	_add_multimesh(parent, post_mesh, metal, post_transforms, "BridgeGuardrailPosts", true)
	_add_multimesh(parent, rail_mesh, metal, rail_transforms, "BridgeGuardrails", true)
	_enhancement_stats["guardrail_posts"] = post_transforms.size()
	_enhancement_stats["guardrail_rails"] = rail_transforms.size()


func _get_gable_mesh() -> ArrayMesh:
	if _gable_mesh != null:
		return _gable_mesh
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(-0.5, 0.0, -0.5)
	var b := Vector3(0.5, 0.0, -0.5)
	var c := Vector3(0.5, 0.0, 0.5)
	var d := Vector3(-0.5, 0.0, 0.5)
	var ridge_a := Vector3(-0.5, 1.0, 0.0)
	var ridge_b := Vector3(0.5, 1.0, 0.0)
	var triangles: Array[Vector3] = [
		a, b, ridge_b, a, ridge_b, ridge_a,
		c, d, ridge_a, c, ridge_a, ridge_b,
		d, a, ridge_a,
		b, c, ridge_b,
	]
	for vertex in triangles:
		tool.set_uv(Vector2(vertex.x + 0.5, vertex.z + vertex.y + 0.5))
		tool.add_vertex(vertex)
	tool.index()
	tool.generate_normals()
	tool.generate_tangents()
	_gable_mesh = tool.commit()
	return _gable_mesh


func _add_generic_building(parent: Node, item: Dictionary) -> void:
	var position_value := _item_position(item)
	var yaw := _f(item, "rotY")
	var w := _f(item, "w", 20.0)
	var d := _f(item, "d", 16.0)
	var h := _f(item, "h", 10.0)
	var roof_h := _f(item, "roofH")
	var facade := String(item.get("facade", "userPlaster"))
	var kind := String(item.get("kind", "building"))
	var material := _facade_material(facade, h)

	if kind == "rt-tower":
		var base_sizes := [Vector2(w, d), Vector2(w * 0.86, d * 0.86), Vector2(w * 0.70, d * 0.70)]
		var heights := [h * 0.52, h * 0.31, h * 0.17]
		var y_cursor := position_value.y - 0.25
		for i in 3:
			var tier_height := float(heights[i])
			var tier_size: Vector2 = base_sizes[i]
			_add_box(
				parent,
				Vector3(tier_size.x, tier_height, tier_size.y),
				Vector3(position_value.x, y_cursor + tier_height * 0.5, position_value.z),
				material,
				yaw,
				"SteppedTower"
			)
			y_cursor += tier_height
	else:
		_add_box(parent, Vector3(w, h, d), position_value + Vector3(0.0, h * 0.5 - 0.25, 0.0), material, yaw, "Building")

	if roof_h > 0.25:
		var roof_transform := make_transform(position_value + Vector3(0.0, h - 0.20, 0.0), yaw, Vector3(w + 0.9, roof_h, d + 0.9))
		_mesh_instance(parent, _get_gable_mesh(), _roof_material(true), roof_transform, "GableRoof")
	else:
		_add_box(parent, Vector3(w + 0.55, 0.42, d + 0.55), position_value + Vector3(0.0, h - 0.02, 0.0), _roof_material(false), yaw, "RoofSlab")

	_add_box_collider(position_value + Vector3(0.0, h * 0.5, 0.0), Vector3(w, h + roof_h, d), yaw)


func _collect_model_parts(node: Node, parent_transform: Transform3D, tools: Dictionary) -> void:
	var local_transform := parent_transform
	if node is Node3D:
		local_transform = parent_transform * (node as Node3D).transform

	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh != null:
			for surface_index in mesh.get_surface_count():
				var material := mesh_instance.get_surface_override_material(surface_index)
				if material == null:
					material = mesh.surface_get_material(surface_index)
				var material_name := "PropsMetal"
				if material != null and not String(material.resource_name).is_empty():
					material_name = String(material.resource_name)
				if not tools.has(material_name):
					var new_tool := SurfaceTool.new()
					new_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
					tools[material_name] = new_tool
				(tools[material_name] as SurfaceTool).append_from(mesh, surface_index, local_transform)

	for child in node.get_children():
		_collect_model_parts(child, local_transform, tools)


## SurfaceTool merging is necessary to turn thousands of Blender nodes
## into one mesh per material, but it discards the LOD chain Godot
## generated for the imported GLB. Rebuild that chain once per distinct
## merged part with the engine's own meshoptimizer importer. If a
## surface is non-indexed, too small, or a build lacks the simplifier,
## the original mesh is returned unchanged.
func _mesh_with_runtime_lods(mesh: Mesh, normal_merge_angle: float = 62.0) -> Mesh:
	if mesh == null or mesh.get_surface_count() != 1:
		return mesh
	var arrays := mesh.surface_get_arrays(0)
	if arrays.size() <= Mesh.ARRAY_INDEX:
		return mesh
	var index_variant: Variant = arrays[Mesh.ARRAY_INDEX]
	var vertex_variant: Variant = arrays[Mesh.ARRAY_VERTEX]
	var indices := PackedInt32Array()
	var vertices := PackedVector3Array()
	if index_variant is PackedInt32Array:
		indices = index_variant
	if vertex_variant is PackedVector3Array:
		vertices = vertex_variant
	var triangle_count := int(indices.size() / 3) if not indices.is_empty() else int(vertices.size() / 3)
	if indices.is_empty() or triangle_count < 48:
		return mesh

	var importer := ImporterMesh.from_mesh(mesh)
	if importer == null or importer.get_surface_count() != 1:
		return mesh
	importer.generate_lods(normal_merge_angle, 25.0, [])
	var lod_count := importer.get_surface_lod_count(0)
	if lod_count <= 0:
		return mesh
	var generated := importer.get_mesh()
	if generated == null or generated.get_surface_count() != 1:
		return mesh

	var smallest_index_count := indices.size()
	for lod_index in lod_count:
		smallest_index_count = mini(smallest_index_count, importer.get_surface_lod_indices(0, lod_index).size())
	_enhancement_stats["runtime_lod_meshes"] = int(_enhancement_stats.get("runtime_lod_meshes", 0)) + 1
	_enhancement_stats["runtime_lod_levels"] = int(_enhancement_stats.get("runtime_lod_levels", 0)) + lod_count
	var previous_ratio := float(_enhancement_stats.get("runtime_lod_min_index_ratio", 1.0))
	_enhancement_stats["runtime_lod_min_index_ratio"] = minf(previous_ratio, float(smallest_index_count) / float(maxi(indices.size(), 1)))
	_enhancement_stats["runtime_lods_0216"] = true
	return generated


func _get_model_parts(path: String) -> Array:
	if _model_parts_cache.has(path):
		return _model_parts_cache[path]
	var parts: Array = []
	if not ResourceLoader.exists(path):
		push_warning("Native model is missing: %s" % path)
		_model_parts_cache[path] = parts
		return parts

	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("Could not load PackedScene: %s" % path)
		_model_parts_cache[path] = parts
		return parts

	var root := packed.instantiate()
	if root == null:
		_model_parts_cache[path] = parts
		return parts

	var tools: Dictionary = {}
	_collect_model_parts(root, Transform3D.IDENTITY, tools)
	root.free()

	for material_name_variant in tools.keys():
		var material_name := String(material_name_variant)
		var tool := tools[material_name] as SurfaceTool
		# ImporterMesh LOD generation requires an indexed surface; the
		# index also stops the vertex shader reprocessing every shared
		# Blender box corner once per incident triangle.
		tool.index()
		var source_mesh := tool.commit()
		var mesh := _mesh_with_runtime_lods(source_mesh, 62.0) if source_mesh != null else null
		if mesh != null:
			parts.append({
				"mesh": mesh,
				"material": _prop_material(material_name),
				"material_name": material_name,
			})
	_model_parts_cache[path] = parts
	return parts


func _multimesh_visual_range(node_name: String) -> float:
	var key := node_name.to_lower()
	# 0.2.16 HLOD budgets. The 0.2.15 phone captures still submitted
	# 867-1074 draw calls and 2.0-3.3M primitives at Q42, so these
	# fallback ranges now describe the *detailed* layer only. Repeated
	# Blender buildings and high-poly foliage receive explicit far
	# proxies in their builders; small street furniture simply retires
	# once it is only a few pixels high. The unique 148 m flagship is
	# never range-hidden and relies on generated mesh LOD instead.
	if key.contains("main148mtower"):
		return 0.0
	if key.contains("blendervillas") or key.contains("blendertownhouses"):
		return 210.0
	if key.contains("blenderherobuildings"):
		return 260.0
	if key.contains("blenderglasstowers"):
		return 340.0
	if key.contains("trafficsignal"):
		return 220.0
	if key.contains("busshelter"):
		return 260.0
	if key.contains("streetlamp") or key.contains("guardrail"):
		return 240.0
	if key.contains("bush") or key.contains("shrub") or key.contains("fan_foliage"):
		return 180.0
	if key.contains("crosswalk") or key.contains("roadedge") or key.contains("roadlane") or key.contains("roadcenter") or key.contains("lanearrow") or key.contains("parkingbay") or key.contains("bikelane"):
		return 380.0
	if key.contains("sidewalkslab") or key.contains("roadcurb") or key.contains("roadgutter") or key.contains("intersectionpad"):
		return 360.0
	if key.contains("manhole") or key.contains("drainage") or key.contains("roadstud") or key.contains("asphaltpatch") or key.contains("tarseam") or key.contains("oilstain") or key.contains("skidmark") or key.contains("tactile"):
		return 220.0
	if key.contains("pool"):
		return 360.0
	if key.contains("palm"):
		return 620.0
	if key.contains("tree"):
		return 300.0
	if key.contains("bollard") or key.contains("planter") or key.contains("hedge") or key.contains("trashbin") or key.contains("roadsign") or key.contains("storefront") or key.contains("awning") or key.contains("balcony"):
		return 220.0
	if key.contains("beach"):
		return 360.0
	if key.contains("marina"):
		return 520.0
	if key.contains("rooftop") or key.contains("watertank"):
		return 300.0
	return 0.0


func _add_multimesh(
	parent: Node,
	mesh: Mesh,
	material: Material,
	transforms: Array,
	node_name: String,
	cast_shadow: bool = true,
	visibility_begin_m: float = -1.0,
	visibility_end_m: float = -1.0,
	chunk_size_m: float = MULTIMESH_CHUNK_SIZE_M
) -> bool:
	if mesh == null or transforms.is_empty():
		return false

	# Spatial chunks keep frustum/distance culling local. Detailed HLOD
	# layers can request smaller cells so a whole 220 m block does not
	# switch detail at once, while cheap far proxies use larger cells
	# to keep their draw-call count down.
	var effective_chunk_size_m := maxf(chunk_size_m, 40.0)
	var grouped: Dictionary = {}
	var mesh_aabb := mesh.get_aabb()
	for transform_variant in transforms:
		var transform_value := transform_variant as Transform3D
		var cell := Vector2i(
			floori((transform_value.origin.x - WORLD_AABB.position.x) / effective_chunk_size_m),
			floori((transform_value.origin.z - WORLD_AABB.position.z) / effective_chunk_size_m)
		)
		if not grouped.has(cell):
			grouped[cell] = []
		(grouped[cell] as Array).append(transform_value)

	var built_any := false
	for cell_variant in grouped.keys():
		var cell := cell_variant as Vector2i
		var cell_transforms: Array = grouped[cell]
		if cell_transforms.is_empty():
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = false
		multi.mesh = mesh
		multi.instance_count = cell_transforms.size()
		var chunk_aabb := AABB()
		var have_chunk_aabb := false
		for i in cell_transforms.size():
			var transform_value := cell_transforms[i] as Transform3D
			multi.set_instance_transform(i, transform_value)
			var instance_aabb: AABB = transform_value * mesh_aabb
			chunk_aabb = instance_aabb if not have_chunk_aabb else chunk_aabb.merge(instance_aabb)
			have_chunk_aabb = true

		var instance := MultiMeshInstance3D.new()
		instance.name = "%s_C%d_%d" % [node_name, cell.x, cell.y]
		instance.multimesh = multi
		if material != null:
			instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		instance.custom_aabb = chunk_aabb.grow(1.5) if have_chunk_aabb else WORLD_AABB
		var visual_begin := visibility_begin_m
		var visual_end := visibility_end_m if visibility_end_m >= 0.0 else _multimesh_visual_range(node_name)
		if visual_begin > 0.0:
			instance.visibility_range_begin = visual_begin
		if visual_end > 0.0:
			instance.visibility_range_end = visual_end
		if visual_begin > 0.0 or visual_end > 0.0:
			instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			instance.lod_bias = 0.45
		else:
			# Skyline geometry keeps generated/imported mesh LODs, but
			# switches to them earlier than the desktop bias.
			instance.lod_bias = 0.65
		parent.add_child(instance)
		_multimesh_chunk_count += 1
		built_any = true

	_enhancement_stats["multimesh_chunks"] = _multimesh_chunk_count
	_enhancement_stats["multimesh_chunk_size_m"] = MULTIMESH_CHUNK_SIZE_M
	return built_any


func _canonical_batched_model_name(path: String, node_name: String) -> String:
	if path.ends_with("villa.glb"):
		return "BlenderVillas"
	if path.ends_with("townhouse.glb"):
		return "BlenderTownhouses"
	if path.ends_with("hero_building.glb"):
		return "BlenderHeroBuildings"
	if path.ends_with("glass_tower.glb"):
		return "BlenderGlassTowers"
	if path.ends_with("main_tower.glb"):
		return "Main148mTower"
	if path.ends_with("street_lamp.glb"):
		return "BlenderStreetLamps"
	if path.ends_with("bus_shelter.glb"):
		return "BlenderBusShelters"
	return node_name.trim_prefix("Infill")


## Queueing is a draw-call optimization: exported parcels and later
## infill parcels use exactly the same GLB/mesh/material, but building
## them immediately created duplicate MultiMesh chunks for every part
## in every shared spatial cell. `_flush_batched_models()` submits one
## combined transform list per model after all placements are known.
func _add_batched_model(parent: Node, path: String, transforms: Array, node_name: String) -> bool:
	if transforms.is_empty():
		return false
	var parts := _get_model_parts(path)
	if parts.is_empty():
		return false
	if not _pending_batched_models.has(path):
		_pending_batched_models[path] = {
			"parent": parent,
			"node_name": _canonical_batched_model_name(path, node_name),
			"transforms": [],
		}
	var entry: Dictionary = _pending_batched_models[path]
	(entry.get("transforms", []) as Array).append_array(transforms)
	_pending_batched_models[path] = entry
	return true


func _batched_model_base_range(path: String) -> float:
	if path.ends_with("villa.glb") or path.ends_with("townhouse.glb"):
		return 210.0
	if path.ends_with("hero_building.glb"):
		return 260.0
	if path.ends_with("glass_tower.glb"):
		return 340.0
	return 0.0


func _batched_model_detail_range(path: String, material_name: String) -> float:
	if path.ends_with("main_tower.glb"):
		return 0.0
	var key := material_name.to_lower()
	if path.contains("traffic_signal"):
		if key.contains("redon") or key.contains("amberoff") or key.contains("greenoff") or key.contains("reflector") or key.contains("cable"):
			return 150.0
		return 220.0
	if path.ends_with("street_lamp.glb"):
		return 180.0 if key.contains("glow") else 240.0
	if path.ends_with("bus_shelter.glb"):
		return 200.0 if key.contains("glass") else 260.0

	var base_range := _batched_model_base_range(path)
	if base_range <= 0.0:
		return 0.0
	# Site dressing and emissive/solar accents are sub-pixel long before
	# the architectural mass is. Retire them first, then curtains and
	# window frames; wall/glass/spandrel cores keep the full HLOD range.
	if key.contains("hedge") or key.contains("lawn") or key.contains("mulch") or key.contains("glow") or key.contains("solar"):
		return minf(base_range, 150.0)
	if key.contains("pavement") or key.contains("deck"):
		return minf(base_range, 180.0)
	if key.contains("curtain") or key.contains("interior"):
		return base_range if path.ends_with("glass_tower.glb") else minf(base_range, 200.0)
	if key.contains("windowframe"):
		return base_range if path.ends_with("glass_tower.glb") else minf(base_range, 230.0)
	return base_range


func _batched_model_chunk_size(path: String) -> float:
	if path.ends_with("main_tower.glb"):
		return MULTIMESH_CHUNK_SIZE_M
	if path.contains("traffic_signal"):
		return 170.0
	return 180.0


## Far HLOD volumes preserve the real footprint/height and podium/shaft
## split of each fixed-scale building after its detailed Blender parts
## retire. They sit slightly inside the true envelope so the short
## detailed/proxy overlap does not wrap the near model in a box.
func _add_building_far_proxy(parent: Node, path: String, transforms: Array, node_name: String) -> void:
	var base_range := _batched_model_base_range(path)
	if base_range <= 0.0 or transforms.is_empty():
		return
	var proxy_begin := maxf(base_range - 20.0, 0.0)
	var proxy_end := 1050.0
	var specs: Array[Dictionary] = []
	if path.ends_with("villa.glb"):
		specs = [
			{"size": Vector3(18.60, 8.00, 14.70), "center": Vector3(0.0, 4.00, 0.05), "material": _prop_material("VillaPlaster"), "name": "Mass"},
			{"size": Vector3(19.20, 0.50, 15.24), "center": Vector3(0.0, 8.42, 0.05), "material": _prop_material("RoofDark"), "name": "Roof"},
		]
	elif path.ends_with("townhouse.glb"):
		specs = [
			{"size": Vector3(18.30, 9.20, 15.80), "center": Vector3(0.0, 4.60, 0.047), "material": _prop_material("TownPlaster"), "name": "Mass"},
			{"size": Vector3(18.87, 1.40, 16.37), "center": Vector3(0.0, 10.15, 0.047), "material": _prop_material("TownRoof"), "name": "Roof"},
		]
	elif path.ends_with("hero_building.glb"):
		proxy_end = 1250.0
		specs = [
			{"size": Vector3(32.40, 5.00, 24.60), "center": Vector3(0.0, 2.50, 0.0), "material": _prop_material("HeroStone"), "name": "Podium"},
			{"size": Vector3(27.00, 23.56, 20.00), "center": Vector3(0.0, 16.78, 0.0), "material": _prop_material("HeroPlaster"), "name": "Shaft"},
		]
	elif path.ends_with("glass_tower.glb"):
		proxy_end = 1500.0
		specs = [
			{"size": Vector3(34.00, 6.00, 34.00), "center": Vector3(0.0, 3.00, 0.0), "material": _prop_material("TowerStone"), "name": "Podium"},
			{"size": Vector3(25.00, 66.90, 25.00), "center": Vector3(0.0, 39.45, 0.0), "material": _facade_material("glassTower", 72.9), "name": "Shaft"},
		]
	if specs.is_empty():
		return

	var unit_box := BoxMesh.new()
	unit_box.size = Vector3.ONE
	var proxy_boxes := 0
	for spec in specs:
		var size: Vector3 = spec.get("size", Vector3.ONE)
		var centre: Vector3 = spec.get("center", Vector3.ZERO)
		var local_transform := Transform3D(Basis.IDENTITY.scaled(size), centre)
		var proxy_transforms: Array = []
		for transform_variant in transforms:
			proxy_transforms.append((transform_variant as Transform3D) * local_transform)
		var built := _add_multimesh(
			parent,
			unit_box,
			spec.get("material") as Material,
			proxy_transforms,
			"%sFarProxy_%s" % [node_name, String(spec.get("name", "Mass"))],
			false,
			proxy_begin,
			proxy_end,
			260.0
		)
		if built:
			proxy_boxes += transforms.size()
	_enhancement_stats["building_far_proxy_models"] = int(_enhancement_stats.get("building_far_proxy_models", 0)) + transforms.size()
	_enhancement_stats["building_far_proxy_boxes"] = int(_enhancement_stats.get("building_far_proxy_boxes", 0)) + proxy_boxes
	_enhancement_stats["building_hlod_0216"] = true


func _flush_batched_models() -> void:
	if _pending_batched_models.is_empty():
		return
	var path_count := _pending_batched_models.size()
	var instance_count := 0
	for path_variant in _pending_batched_models.keys():
		var path := String(path_variant)
		var entry: Dictionary = _pending_batched_models[path]
		var transforms: Array = entry.get("transforms", [])
		if transforms.is_empty():
			continue
		var parts := _get_model_parts(path)
		if parts.is_empty():
			continue
		var parent := entry.get("parent") as Node
		if parent == null:
			parent = self
		var node_name := String(entry.get("node_name", "BatchedModel"))
		var model_root := Node3D.new()
		model_root.name = node_name
		parent.add_child(model_root)
		instance_count += transforms.size()
		var built_any := false
		for part_variant in parts:
			var part: Dictionary = part_variant
			var material_name := String(part.get("material_name", "Part"))
			var material_key := material_name.to_lower()
			# Transparent shells, emissive panes and interior infill sit
			# inside or directly over a real opaque core/wall that
			# already casts the building shadow.
			var casts_shadow := not (
				material_key.contains("glass")
				or material_key.contains("curtain")
				or material_key.contains("interior")
				or material_key.contains("glow")
				or material_key.contains("solar")
				or material_key.contains("water")
			)
			if not casts_shadow:
				_enhancement_stats["model_parts_without_shadow_pass"] = int(_enhancement_stats.get("model_parts_without_shadow_pass", 0)) + 1
			built_any = _add_multimesh(
				model_root,
				part.get("mesh") as Mesh,
				part.get("material") as Material,
				transforms,
				"%s_%s" % [node_name, material_name],
				casts_shadow,
				0.0,
				_batched_model_detail_range(path, material_name),
				_batched_model_chunk_size(path)
			) or built_any
		if built_any:
			_add_building_far_proxy(model_root, path, transforms, node_name)
	_enhancement_stats["batched_model_paths_0216"] = path_count
	_enhancement_stats["batched_model_instances_0216"] = instance_count
	_enhancement_stats["batched_models_merged_0216"] = true
	_pending_batched_models.clear()


func _centered_model_transform(position_value: Vector3, yaw: float, scale_value: Vector3, source_center: Vector3) -> Transform3D:
	return make_transform(position_value, yaw, scale_value) * Transform3D(Basis.IDENTITY, -source_center)


func _nearest_road_point(point: Vector3) -> Dictionary:
	var best_point := point
	var best_direction := Vector3(0.0, 0.0, -1.0)
	var best_distance_squared := INF
	for i in _road_segment_starts.size():
		var a := _road_segment_starts[i]
		var b := _road_segment_ends[i]
		var ab := b - a
		var ab_xz := Vector2(ab.x, ab.z)
		var length_squared := ab_xz.length_squared()
		if length_squared <= 0.0001:
			continue
		var t := clampf(Vector2(point.x - a.x, point.z - a.z).dot(ab_xz) / length_squared, 0.0, 1.0)
		var candidate := a + ab * t
		var distance_squared := Vector2(point.x - candidate.x, point.z - candidate.z).length_squared()
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_point = candidate
			best_direction = Vector3(ab_xz.x, 0.0, ab_xz.y).normalized()
	return {
		"point": best_point,
		"direction": best_direction,
		"distance": sqrt(best_distance_squared) if best_distance_squared < INF else INF,
	}


## Building Model No.3 has a fixed 32.40 x 24.60 m footprint. Most
## exported hero parcels were authored around a stretch-to-fit proxy,
## and one parcel centre sits only about 8.5 m from the nearest asphalt
## edge, so centring the real footprint there would put its podium on
## the road. This search keeps the parcel yaw and tries the smallest
## whole-metre offsets (at most 12 m) whose corners clear every road
## and stay on reasonably level terrain; seven of the eight exported
## parcels accept the original centre unchanged.
func _hero_exported_position(position_value: Vector3, yaw: float) -> Vector3:
	var basis := Basis(Vector3.UP, yaw)
	var offsets: Array = [Vector3.ZERO]
	for distance_variant in [2.0, 4.0, 6.0, 8.0, 10.0, 12.0]:
		var distance: float = distance_variant
		offsets.append_array([
			Vector3(0.0, 0.0, -distance), Vector3(0.0, 0.0, distance),
			Vector3(-distance, 0.0, 0.0), Vector3(distance, 0.0, 0.0),
			Vector3(-distance, 0.0, -distance), Vector3(distance, 0.0, -distance),
			Vector3(-distance, 0.0, distance), Vector3(distance, 0.0, distance),
		])
	for offset_variant in offsets:
		var offset: Vector3 = offset_variant
		var candidate := Vector3(position_value.x + offset.x, 0.0, position_value.z + offset.z)
		candidate.y = height_at(candidate.x, candidate.z)
		var heights: Array[float] = [candidate.y]
		var clear := true
		for local_variant in [Vector3(-16.20, 0.0, -12.30), Vector3(16.20, 0.0, -12.30), Vector3(-16.20, 0.0, 12.30), Vector3(16.20, 0.0, 12.30)]:
			var local_corner: Vector3 = local_variant
			var corner := candidate + basis * local_corner
			heights.append(height_at(corner.x, corner.z))
			if _road_clearance_xz(corner) < 1.2:
				clear = false
				break
		if clear and heights.max() - heights.min() <= 1.1:
			return candidate
	return position_value


func _build_buildings() -> void:
	var buildings_root := Node3D.new()
	buildings_root.name = "Buildings"
	add_child(buildings_root)

	var villa_items: Array[Dictionary] = []
	var villa_transforms: Array[Transform3D] = []
	var tower_items: Array[Dictionary] = []
	var tower_transforms: Array[Transform3D] = []
	var townhouse_items: Array[Dictionary] = []
	var townhouse_transforms: Array[Transform3D] = []
	var hero_items: Array[Dictionary] = []
	var hero_transforms: Array[Transform3D] = []

	for building_variant in data.get("buildings", []):
		var building: Dictionary = building_variant
		var model := String(building.get("model", "generic"))
		var position_value := _item_position(building)
		var yaw := _f(building, "rotY")
		var w := _f(building, "w", 20.0)
		var d := _f(building, "d", 16.0)
		var h := _f(building, "h", 10.0)
		var roof_h := _f(building, "roofH")
		var kind := String(building.get("kind", "building"))
		var total_height := maxf(h + roof_h, 5.0)
		# Exact world-space AABBs of the user's Blender GLBs, measured with
		# node transforms included.  These denominators preserve the JSON
		# footprint/height instead of the earlier approximate 7-12% oversize.
		if model == "villa":
			# Building Model No.1 is a fixed architectural design, not a
			# massing proxy. Keeping scale exactly 1.0 preserves its
			# 19.20 x 15.24 m footprint, 8.84 m height, door/window sizes
			# and floor heights at every villa parcel.
			villa_items.append(building)
			villa_transforms.append(_centered_model_transform(
				position_value,
				yaw,
				Vector3.ONE,
				Vector3(0.0, 0.0, 0.05)
			))
			_add_box_collider(position_value + Vector3(0.0, 4.42, 0.0), Vector3(19.20, 8.84, 15.24), yaw)
		elif model == "glass_tower":
			# Building Model No.4 is a finished district tower measuring
			# exactly 34.00 x 34.00 m and 72.90 m high (GLB AABB centre
			# x/z = 0.0 / 0.0). The old proxy was non-uniformly scaled
			# 0.62-1.32x over these parcels; all eight fixed envelopes
			# were re-audited against roads and neighbouring buildings
			# with at least 6.9 m road clearance and no overlaps.
			tower_items.append(building)
			tower_transforms.append(_centered_model_transform(
				position_value,
				yaw,
				Vector3.ONE,
				Vector3.ZERO
			))
			_add_box_collider(position_value + Vector3(0.0, 36.45, 0.0), Vector3(34.00, 72.90, 34.00), yaw)
		elif kind == "rt-villa" and w <= 29.0 and d <= 22.0 and total_height <= 13.0:
			# Building Model No.2 is likewise one finished architectural
			# design: a semi-detached townhouse pair measuring exactly
			# 18.87 x 16.37 m and 11.05 m high (GLB AABB centre z +0.047).
			# The old model was stretched up to 1.96x over these parcels;
			# the measured clear space around all nine exported parcels
			# exceeds 23 m, so the fixed design fits without distortion.
			townhouse_items.append(building)
			townhouse_transforms.append(_centered_model_transform(
				position_value,
				yaw,
				Vector3.ONE,
				Vector3(0.0, 0.0, 0.047)
			))
			_add_box_collider(position_value + Vector3(0.0, 5.525, 0.0), Vector3(18.87, 11.05, 16.37), yaw)
		elif kind == "rt-hotel" and h >= 15.0 and h <= 38.0 and w <= 55.0 and d <= 38.0:
			# Building Model No.3 is a finished podium residential/hotel
			# block measuring exactly 32.40 x 24.60 m and 28.56 m high
			# (GLB AABB centre x/z = 0.0 / 0.0). It replaces a proxy that
			# was stretched up to 2.20x in width and 2.07x in height,
			# which turned real 3.2 m floors into double-height slabs.
			var hero_position := _hero_exported_position(position_value, yaw)
			hero_items.append(building)
			hero_transforms.append(_centered_model_transform(
				hero_position,
				yaw,
				Vector3.ONE,
				Vector3.ZERO
			))
			_add_box_collider(hero_position + Vector3(0.0, 14.279, 0.0), Vector3(32.40, 28.56, 24.60), yaw)
		else:
			_add_generic_building(buildings_root, building)

	var premium_villa_built := _add_batched_model(buildings_root, "res://assets/buildings/villa.glb", villa_transforms, "BlenderVillas")
	if not premium_villa_built:
		for item in villa_items:
			_add_generic_building(buildings_root, item)
	var premium_glass_built := _add_batched_model(buildings_root, "res://assets/buildings/glass_tower.glb", tower_transforms, "BlenderGlassTowers")
	if not premium_glass_built:
		for item in tower_items:
			_add_generic_building(buildings_root, item)
	var premium_townhouse_built := _add_batched_model(buildings_root, "res://assets/buildings/townhouse.glb", townhouse_transforms, "BlenderTownhouses")
	if not premium_townhouse_built:
		for item in townhouse_items:
			_add_generic_building(buildings_root, item)
	var premium_hero_built := _add_batched_model(buildings_root, "res://assets/buildings/hero_building.glb", hero_transforms, "BlenderHeroBuildings")
	if not premium_hero_built:
		for item in hero_items:
			_add_generic_building(buildings_root, item)
	_enhancement_stats["townhouse_models"] = townhouse_transforms.size()
	_enhancement_stats["hero_building_models"] = hero_transforms.size()
	_enhancement_stats["premium_villa_models"] = villa_transforms.size() if premium_villa_built else 0
	_enhancement_stats["premium_villa_fixed_scale"] = premium_villa_built
	# The 0.2.8 smoke must prove that the new GLB's dedicated semantic
	# materials actually reached Godot materials, not merely that an
	# older villa file happened to load under the same path.
	_enhancement_stats["premium_villa_detail_pass"] = premium_villa_built
	_enhancement_stats["premium_villa_material_pass"] = premium_villa_built and _materials.has("villa_plaster") and _materials.has("villa_stone") and _materials.has("villa_granite") and _materials.has("villa_glass") and _materials.has("villa_interior")
	_enhancement_stats["premium_villa_site_pass"] = premium_villa_built and _materials.has("villa_pavement") and _materials.has("villa_mulch") and _materials.has("villa_lawn") and _materials.has("villa_hedge")
	# The 0.2.9 smoke proves the same chain for Building Model No.2:
	# the townhouse GLB in the export must be the new fixed-scale pair
	# with its dedicated Town* materials resolved to Godot materials.
	_enhancement_stats["premium_townhouse_models"] = townhouse_transforms.size() if premium_townhouse_built else 0
	_enhancement_stats["premium_townhouse_fixed_scale"] = premium_townhouse_built
	_enhancement_stats["premium_townhouse_detail_pass"] = premium_townhouse_built
	_enhancement_stats["premium_townhouse_material_pass"] = premium_townhouse_built and _materials.has("townhouse_plaster") and _materials.has("townhouse_stone") and _materials.has("townhouse_trim") and _materials.has("townhouse_roof") and _materials.has("townhouse_garage")
	_enhancement_stats["premium_townhouse_site_pass"] = premium_townhouse_built and _materials.has("townhouse_door") and _materials.has("villa_pavement") and _materials.has("villa_lawn") and _materials.has("villa_hedge")
	# The 0.2.10 smoke proves the same chain for Building Model No.3:
	# the hero GLB in the export must be the new fixed-scale podium
	# block with its dedicated Hero* materials resolved in Godot.
	_enhancement_stats["premium_hero_models"] = hero_transforms.size() if premium_hero_built else 0
	_enhancement_stats["premium_hero_fixed_scale"] = premium_hero_built
	_enhancement_stats["premium_hero_detail_pass"] = premium_hero_built
	_enhancement_stats["premium_hero_material_pass"] = premium_hero_built and _materials.has("hero_plaster") and _materials.has("hero_stone") and _materials.has("hero_trim") and _materials.has("hero_wood") and _materials.has("hero_metal")
	_enhancement_stats["premium_hero_site_pass"] = premium_hero_built and _materials.has("villa_pavement") and _materials.has("villa_lawn") and _materials.has("villa_hedge")
	# The 0.2.11 smoke proves the same chain for Building Model No.4:
	# the glass-tower GLB in the export must be the new fixed-scale
	# curtain-wall tower with its Tower* materials resolved in Godot.
	# The separate main-tower GLB is Building Model No.5; No.4 is
	# never stretched vertically to impersonate the 148 m flagship.
	_enhancement_stats["premium_glass_models"] = tower_transforms.size() if premium_glass_built else 0
	_enhancement_stats["premium_glass_fixed_scale"] = premium_glass_built
	_enhancement_stats["premium_glass_detail_pass"] = premium_glass_built
	_enhancement_stats["premium_glass_material_pass"] = premium_glass_built and _materials.has("tower_glass_physical") and _materials.has("tower_spandrel") and _materials.has("tower_stone") and _materials.has("tower_trim") and _materials.has("tower_metal")
	_enhancement_stats["premium_glass_site_pass"] = premium_glass_built and _materials.has("villa_pavement") and _materials.has("villa_lawn") and _materials.has("villa_hedge")
	_build_infill_buildings(buildings_root)


## Building Model No.2 is a fixed 18.87 x 16.37 m design (11.05 m high,
## GLB AABB centre x/z = 0.0 / +0.047). Infill parcels were generated
## for generic massing boxes, so a parcel only receives the detailed
## townhouse when the model's real footprint — in either orientation —
## clears roads, exported buildings, terrain slope and every other
## infill parcel. Anything smaller keeps the textured facade fallback
## instead of stretching doors, floor heights and the pitched roof.
func _townhouse_model_fit(item: Dictionary, self_index: int, accepted: Array, placed_rects: Array) -> Dictionary:
	var centre := Vector2(_f(item, "x"), _f(item, "z"))
	for footprint_variant in [Vector2(18.87, 16.37), Vector2(16.37, 18.87)]:
		var size: Vector2 = footprint_variant
		var rect := Rect2(centre - size * 0.5 - Vector2.ONE, size + Vector2(2.0, 2.0))
		var clear := true
		var heights: Array[float] = [height_at(centre.x, centre.y)]
		for corner_offset_variant in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]:
			var corner_offset: Vector2 = corner_offset_variant
			var corner_xz := centre + Vector2(corner_offset.x * size.x, corner_offset.y * size.y)
			var corner := Vector3(corner_xz.x, 0.0, corner_xz.y)
			heights.append(height_at(corner_xz.x, corner_xz.y))
			if _road_clearance_xz(corner) < 2.7 or not _is_position_clear(corner, 2.0, 0.0):
				clear = false
				break
		if clear and heights.max() - heights.min() > 1.1:
			clear = false
		if clear:
			for other_index in accepted.size():
				if other_index == self_index:
					continue
				var other: Dictionary = accepted[other_index]
				var other_size := Vector2(_f(other, "w", 18.0), _f(other, "d", 15.0))
				var other_rect := Rect2(Vector2(_f(other, "x"), _f(other, "z")) - other_size * 0.5, other_size)
				if rect.intersects(other_rect):
					clear = false
					break
		if clear:
			for placed_variant in placed_rects:
				var placed_rect: Rect2 = placed_variant
				if rect.intersects(placed_rect):
					clear = false
					break
		if clear:
			return {"fits": true, "yaw": 0.0 if size.x > size.y else PI * 0.5, "rect": rect}
	return {"fits": false, "yaw": 0.0, "rect": Rect2()}


## Building Model No.3 is a fixed 32.40 x 24.60 m design (28.56 m high,
## GLB AABB centre x/z = 0.0 / 0.0). An infill parcel only receives it
## when that real footprint — in either orientation — clears roads,
## exported buildings, terrain slope, every other infill parcel and
## every already-placed fixed-scale townhouse/hero model. Parcels that
## cannot take it keep the textured facade fallback at their authored
## height instead of a stretched copy with distorted floors.
func _hero_model_fit(item: Dictionary, self_index: int, accepted: Array, placed_rects: Array) -> Dictionary:
	var centre := Vector2(_f(item, "x"), _f(item, "z"))
	for footprint_variant in [Vector2(32.40, 24.60), Vector2(24.60, 32.40)]:
		var size: Vector2 = footprint_variant
		var rect := Rect2(centre - size * 0.5 - Vector2.ONE, size + Vector2(2.0, 2.0))
		var clear := true
		var heights: Array[float] = [height_at(centre.x, centre.y)]
		for corner_offset_variant in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]:
			var corner_offset: Vector2 = corner_offset_variant
			var corner_xz := centre + Vector2(corner_offset.x * size.x, corner_offset.y * size.y)
			var corner := Vector3(corner_xz.x, 0.0, corner_xz.y)
			heights.append(height_at(corner_xz.x, corner_xz.y))
			if _road_clearance_xz(corner) < 2.7 or not _is_position_clear(corner, 2.0, 0.0):
				clear = false
				break
		if clear and heights.max() - heights.min() > 1.1:
			clear = false
		if clear:
			for other_index in accepted.size():
				if other_index == self_index:
					continue
				var other: Dictionary = accepted[other_index]
				var other_size := Vector2(_f(other, "w", 18.0), _f(other, "d", 15.0))
				var other_rect := Rect2(Vector2(_f(other, "x"), _f(other, "z")) - other_size * 0.5, other_size)
				if rect.intersects(other_rect):
					clear = false
					break
		if clear:
			for placed_variant in placed_rects:
				var placed_rect: Rect2 = placed_variant
				if rect.intersects(placed_rect):
					clear = false
					break
		if clear:
			return {"fits": true, "yaw": 0.0 if size.x > size.y else PI * 0.5, "rect": rect}
	return {"fits": false, "yaw": 0.0, "rect": Rect2()}


## Building Model No.4 is a fixed 34.00 x 34.00 m design (72.90 m high,
## GLB AABB centre x/z = 0.0 / 0.0). Tall infill parcels only receive it
## when that complete plaza footprint clears roads, exported buildings,
## terrain slope, every other infill parcel and every already-placed
## fixed-scale model. Tighter tall parcels keep their authored generic
## massing rather than squeezing the tower's podium and floor heights.
func _glass_model_fit(item: Dictionary, self_index: int, accepted: Array, placed_rects: Array) -> Dictionary:
	var centre := Vector2(_f(item, "x"), _f(item, "z"))
	var size := Vector2(34.00, 34.00)
	var rect := Rect2(centre - size * 0.5 - Vector2.ONE, size + Vector2(2.0, 2.0))
	var heights: Array[float] = [height_at(centre.x, centre.y)]
	for corner_offset_variant in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]:
		var corner_offset: Vector2 = corner_offset_variant
		var corner_xz := centre + Vector2(corner_offset.x * size.x, corner_offset.y * size.y)
		var corner := Vector3(corner_xz.x, 0.0, corner_xz.y)
		heights.append(height_at(corner_xz.x, corner_xz.y))
		if _road_clearance_xz(corner) < 2.7 or not _is_position_clear(corner, 2.0, 0.0):
			return {"fits": false, "yaw": 0.0, "rect": Rect2()}
	if heights.max() - heights.min() > 0.8:
		return {"fits": false, "yaw": 0.0, "rect": Rect2()}
	for other_index in accepted.size():
		if other_index == self_index:
			continue
		var other: Dictionary = accepted[other_index]
		var other_size := Vector2(_f(other, "w", 18.0), _f(other, "d", 15.0))
		var other_rect := Rect2(Vector2(_f(other, "x"), _f(other, "z")) - other_size * 0.5, other_size)
		if rect.intersects(other_rect):
			return {"fits": false, "yaw": 0.0, "rect": Rect2()}
	for placed_variant in placed_rects:
		var placed_rect: Rect2 = placed_variant
		if rect.intersects(placed_rect):
			return {"fits": false, "yaw": 0.0, "rect": Rect2()}
	return {"fits": true, "yaw": 0.0, "rect": rect}


func _build_infill_buildings(parent: Node) -> void:
	_infill_buildings.clear()
	var accepted: Array[Dictionary] = []
	var search_ranges: Array[Vector2] = [
		Vector2(535.0, 935.0),
		Vector2(1150.0, 1470.0),
	]

	# The exported master plan deliberately contains only its hero parcels.
	# This deterministic second pass fills genuinely empty city blocks:
	# every footprint corner must clear roads and existing buildings, and
	# candidates also avoid landmarks, pools, steep height changes and
	# one another.  Building scale/mass follows the surrounding district.
	for x_range in search_ranges:
		for grid_z in range(-450, 451, 27):
			var iz := int(floor((float(grid_z) + 500.0) / 27.0))
			for grid_x in range(int(x_range.x), int(x_range.y) + 1, 24):
				var ix := int(floor((float(grid_x) - 520.0) / 24.0))
				var x := float(grid_x) + (_hash01(ix * 3 + 1, iz * 5 + 2) - 0.5) * 7.0
				var z := float(grid_z) + (_hash01(ix * 7 + 4, iz * 11 + 3) - 0.5) * 8.0
				if _in_zone(x, z, "rtPlaza"):
					continue

				var w := 15.0 + _hash01(ix, iz) * 9.0
				var d := 13.0 + _hash01(iz, ix) * 8.0
				var h := 8.0 + _hash01(ix + 9, iz + 4) * 20.0
				if x >= 690.0 and x <= 880.0 and z >= -260.0 and z <= 240.0:
					w = 16.0 + _hash01(ix, iz) * 9.0
					d = 15.0 + _hash01(iz, ix) * 8.0
					h = 18.0 + _hash01(ix + 9, iz + 4) * 42.0
				elif x >= 1150.0:
					w = 14.0 + _hash01(ix, iz) * 8.0
					d = 11.0 + _hash01(iz, ix) * 7.0
					h = 6.0 + _hash01(ix + 9, iz + 4) * 10.0
				elif x >= 840.0:
					w = 16.0 + _hash01(ix, iz) * 8.0
					d = 14.0 + _hash01(iz, ix) * 7.0
					h = 10.0 + _hash01(ix + 9, iz + 4) * 24.0
				elif x < 650.0 and absf(z) > 230.0:
					w = 13.0 + _hash01(ix, iz) * 8.0
					d = 11.0 + _hash01(iz, ix) * 7.0
					h = 6.0 + _hash01(ix + 9, iz + 4) * 8.0

				x = clampf(x, 520.0 + w * 0.5 + 3.0, 1500.0 - w * 0.5 - 3.0)
				z = clampf(z, -500.0 + d * 0.5 + 3.0, 500.0 - d * 0.5 - 3.0)
				var centre_y := height_at(x, z)
				if centre_y < 1.55:
					continue
				var corners: Array[Vector3] = [
					Vector3(x - w * 0.5, 0.0, z - d * 0.5),
					Vector3(x + w * 0.5, 0.0, z - d * 0.5),
					Vector3(x - w * 0.5, 0.0, z + d * 0.5),
					Vector3(x + w * 0.5, 0.0, z + d * 0.5),
				]
				var valid := true
				var min_corner_height := INF
				var max_corner_height := -INF
				for corner in corners:
					var corner_height := height_at(corner.x, corner.z)
					min_corner_height = minf(min_corner_height, corner_height)
					max_corner_height = maxf(max_corner_height, corner_height)
					if _road_clearance_xz(corner) < 2.7 or not _is_position_clear(corner, 4.5, 0.0):
						valid = false
						break
				if not valid or max_corner_height - min_corner_height > 1.1:
					continue
				for existing in accepted:
					if absf(x - _f(existing, "x")) < (w + _f(existing, "w")) * 0.5 + 5.0 and absf(z - _f(existing, "z")) < (d + _f(existing, "d")) * 0.5 + 5.0:
						valid = false
						break
				if not valid:
					continue
				for landmark_variant in data.get("landmarks", []):
					var landmark: Dictionary = landmark_variant
					var landmark_pos := _item_position(landmark)
					var safe_radius := maxf(_f(landmark, "r", 26.0), 26.0) + maxf(w, d) * 0.55
					if Vector2(x - landmark_pos.x, z - landmark_pos.z).length() < safe_radius:
						valid = false
						break
				if not valid:
					continue
				for pool_variant in data.get("pools", []):
					var pool: Dictionary = pool_variant
					var pool_pos := _item_position(pool)
					if absf(x - pool_pos.x) < (w + _f(pool, "w", 8.0)) * 0.5 + 5.0 and absf(z - pool_pos.z) < (d + _f(pool, "d", 5.0)) * 0.5 + 5.0:
						valid = false
						break
				if not valid:
					continue

				var facade_roll := _hash01(ix * 17 + 5, iz * 19 + 8)
				var facade := "userPlaster"
				if x >= 690.0 and x <= 880.0 and z >= -260.0 and z <= 240.0:
					facade = "glassTower" if facade_roll < 0.42 else ("hotelTower" if facade_roll < 0.68 else ("marbleTower" if facade_roll < 0.86 else "goldTower"))
				elif x >= 840.0 and x < 1150.0:
					facade = "hotelTower" if facade_roll < 0.42 else ("glassTower" if facade_roll < 0.66 else ("sandTower" if facade_roll < 0.84 else "marbleTower"))
				elif facade_roll < 0.34:
					facade = "userStone"
				elif facade_roll < 0.58:
					facade = "userWood"
				elif facade_roll < 0.78:
					facade = "sandTower"
				elif facade_roll < 0.91:
					facade = "hotelTower"

				accepted.append({
					"x": x,
					"y": centre_y,
					"z": z,
					"w": w,
					"d": d,
					"h": h,
					"roofH": 0.0,
					"rotY": 0.0,
					"kind": "rt-infill",
					"model": "generic",
					"facade": facade,
				})

	_infill_buildings = accepted
	_enhancement_stats["infill_buildings"] = accepted.size()
	if accepted.is_empty():
		_enhancement_stats["building_details"] = 0
		return

	var unit_box := BoxMesh.new()
	unit_box.size = Vector3.ONE
	var unit_cylinder := CylinderMesh.new()
	unit_cylinder.top_radius = 0.5
	unit_cylinder.bottom_radius = 0.5
	unit_cylinder.height = 1.0
	unit_cylinder.radial_segments = 12

	var facade_transforms: Dictionary = {}
	var infill_townhouse_transforms: Array = []
	var fixed_model_placed_rects: Array = []
	var infill_hero_transforms: Array = []
	var infill_glass_transforms: Array = []
	var flat_roof_transforms: Array = []
	var pitched_roof_transforms: Array = []
	var storefront_transforms: Array = []
	var balcony_transforms: Array = []
	var rooftop_transforms: Array = []
	var tank_transforms: Array = []
	var sign_transforms: Array = [[], [], []]
	var awning_transforms: Array = [[], [], []]

	var sign_materials: Array[StandardMaterial3D] = []
	for sign_spec in [
		["city_sign_blue", Color(0.08, 0.34, 0.82)],
		["city_sign_orange", Color(0.98, 0.38, 0.07)],
		["city_sign_teal", Color(0.03, 0.58, 0.52)],
	]:
		var sign_material := _material(String(sign_spec[0]), "", "", sign_spec[1] as Color, 0.42, 0.04)
		sign_material.emission_enabled = true
		sign_material.emission = sign_spec[1] as Color
		_register_night_material(sign_material, 0.10, 0.75, 2.3)
		sign_materials.append(sign_material)
	var awning_materials: Array[StandardMaterial3D] = [
		_material("city_awning_red", "", "", Color(0.48, 0.07, 0.07), 0.82),
		_material("city_awning_sand", "", "", Color(0.72, 0.58, 0.38), 0.86),
		_material("city_awning_green", "", "", Color(0.08, 0.34, 0.24), 0.84),
	]

	for item_index in accepted.size():
		var item := accepted[item_index]
		var base := _item_position(item)
		var w := _f(item, "w", 18.0)
		var d := _f(item, "d", 15.0)
		var h := _f(item, "h", 9.0)
		var facade := String(item.get("facade", "userPlaster"))
		var detail_roll := _hash01(item_index * 23 + 7, item_index * 31 + 11)
		# Reuse the user's detailed Blender buildings wherever the parcel
		# proportions allow it.  Only the remaining infill massing uses the
		# textured facade-box fallback, avoiding a city of plain cuboids.
		var model_kind := ""
		var townhouse_fit: Dictionary = {}
		if h <= 13.5 and detail_roll < 0.76:
			townhouse_fit = _townhouse_model_fit(item, item_index, accepted, fixed_model_placed_rects)
		var hero_fit: Dictionary = {}
		if h >= 15.0 and h < 34.0 and detail_roll < 0.72:
			hero_fit = _hero_model_fit(item, item_index, accepted, fixed_model_placed_rects)
		var glass_fit: Dictionary = {}
		if h >= 34.0:
			glass_fit = _glass_model_fit(item, item_index, accepted, fixed_model_placed_rects)
		if bool(glass_fit.get("fits", false)):
			model_kind = "glass"
			fixed_model_placed_rects.append(glass_fit.get("rect", Rect2()))
			infill_glass_transforms.append(_centered_model_transform(
				base,
				float(glass_fit.get("yaw", 0.0)),
				Vector3.ONE,
				Vector3.ZERO
			))
		elif bool(hero_fit.get("fits", false)):
			model_kind = "hero"
			fixed_model_placed_rects.append(hero_fit.get("rect", Rect2()))
			infill_hero_transforms.append(_centered_model_transform(
				base,
				float(hero_fit.get("yaw", 0.0)),
				Vector3.ONE,
				Vector3.ZERO
			))
		elif bool(townhouse_fit.get("fits", false)):
			model_kind = "townhouse"
			fixed_model_placed_rects.append(townhouse_fit.get("rect", Rect2()))
			infill_townhouse_transforms.append(_centered_model_transform(
				base,
				float(townhouse_fit.get("yaw", 0.0)),
				Vector3.ONE,
				Vector3(0.0, 0.0, 0.047)
			))
		else:
			if not facade_transforms.has(facade):
				facade_transforms[facade] = []
			(facade_transforms[facade] as Array).append(make_transform(
				base + Vector3(0.0, h * 0.5 - 0.30, 0.0),
				0.0,
				Vector3(w, h, d)
			))
		var uses_model := not model_kind.is_empty()
		item["model"] = model_kind if uses_model else "generic"

		var roof_height := 0.0
		var pitched := not uses_model and h <= 11.5 and detail_roll < 0.55
		if pitched:
			roof_height = 2.0 + detail_roll * 1.6
			item["roofH"] = roof_height
			pitched_roof_transforms.append(make_transform(
				base + Vector3(0.0, h - 0.20, 0.0),
				0.0,
				Vector3(w + 0.9, roof_height, d + 0.9)
			))
		else:
			if not uses_model:
				flat_roof_transforms.append(make_transform(
					base + Vector3(0.0, h - 0.02, 0.0),
					0.0,
					Vector3(w + 0.55, 0.42, d + 0.55)
				))
			var unit_count := 0
			if not uses_model:
				unit_count = 1 if detail_roll < 0.68 else 2
			for unit_index in unit_count:
				var local_x := (_hash01(item_index * 13 + unit_index * 7, item_index * 3 + 2) - 0.5) * maxf(w - 7.0, 1.0)
				var local_z := (_hash01(item_index * 5 + 1, item_index * 17 + unit_index * 9) - 0.5) * maxf(d - 6.0, 1.0)
				rooftop_transforms.append(make_transform(
					base + Vector3(local_x, h + 0.62, local_z),
					detail_roll * TAU,
					Vector3(2.5, 1.05, 1.8)
				))
			if h > 24.0 and detail_roll > 0.62 and not uses_model:
				tank_transforms.append(make_transform(
					base + Vector3(w * 0.24, h + 1.85, -d * 0.18),
					0.0,
					Vector3(3.4, 3.7, 3.4)
				))
		if model_kind == "glass":
			_add_box_collider(base + Vector3(0.0, 36.45, 0.0), Vector3(34.00, 72.90, 34.00), float(glass_fit.get("yaw", 0.0)))
		elif model_kind == "hero":
			_add_box_collider(base + Vector3(0.0, 14.279, 0.0), Vector3(32.40, 28.56, 24.60), float(hero_fit.get("yaw", 0.0)))
		elif model_kind == "townhouse":
			_add_box_collider(base + Vector3(0.0, 5.525, 0.0), Vector3(18.87, 11.05, 16.37), float(townhouse_fit.get("yaw", 0.0)))
		else:
			_add_box_collider(base + Vector3(0.0, (h + roof_height) * 0.5, 0.0), Vector3(w, h + roof_height, d))

		# Ground-floor frontage and balconies face the nearest actual road.
		# They are all instanced thin boxes, so the city gains close-range
		# architectural rhythm without hundreds of individual nodes.
		var nearest := _nearest_road_point(base)
		var nearest_point: Vector3 = nearest.get("point", base)
		var to_road := nearest_point - base
		to_road.y = 0.0
		if to_road.length_squared() < 0.01:
			continue
		var outward := Vector3.ZERO
		if absf(to_road.x) >= absf(to_road.z):
			outward = Vector3(signf(to_road.x), 0.0, 0.0)
		else:
			outward = Vector3(0.0, 0.0, signf(to_road.z))
		var front_is_x_face := absf(outward.x) > 0.5
		var half_extent := w * 0.5 if front_is_x_face else d * 0.5
		var front_width := d if front_is_x_face else w
		var front_yaw := PI * 0.5 if front_is_x_face else 0.0
		var face_centre := base + outward * (half_extent + 0.07)
		if h >= 6.5 and model_kind != "townhouse" and model_kind != "hero" and model_kind != "glass":
			storefront_transforms.append(make_transform(
				face_centre + Vector3(0.0, 1.45, 0.0),
				front_yaw,
				Vector3(minf(front_width * 0.62, 14.0), 2.35, 0.14)
			))
			(sign_transforms[item_index % 3] as Array).append(make_transform(
				face_centre + outward * 0.10 + Vector3(0.0, 3.05, 0.0),
				front_yaw,
				Vector3(minf(front_width * 0.38, 7.0), 0.72, 0.16)
			))
			(awning_transforms[item_index % 3] as Array).append(make_transform(
				face_centre + outward * 0.62 + Vector3(0.0, 2.72, 0.0),
				front_yaw,
				Vector3(minf(front_width * 0.55, 11.0), 0.16, 1.35)
			))
		if h >= 12.0 and detail_roll < 0.72 and model_kind != "townhouse" and model_kind != "hero" and model_kind != "glass":
			var lateral := Vector3(outward.z, 0.0, -outward.x)
			var floor_y := 4.4
			while floor_y < h - 1.4:
				for offset_ratio in [-0.28, 0.0, 0.28]:
					balcony_transforms.append(make_transform(
						face_centre + outward * 0.48 + lateral * front_width * float(offset_ratio) + Vector3(0.0, floor_y, 0.0),
						front_yaw,
						Vector3(2.4, 0.18, 1.0)
					))
				floor_y += 3.15

	for facade_variant in facade_transforms.keys():
		var facade_name := String(facade_variant)
		_add_multimesh(
			parent,
			unit_box,
			_facade_material(facade_name, 28.0),
			facade_transforms[facade_name],
			"InfillBuildings_%s" % facade_name,
			true
		)
	_add_batched_model(parent, "res://assets/buildings/townhouse.glb", infill_townhouse_transforms, "InfillBlenderTownhouses")
	_add_batched_model(parent, "res://assets/buildings/hero_building.glb", infill_hero_transforms, "InfillBlenderHeroBuildings")
	_add_batched_model(parent, "res://assets/buildings/glass_tower.glb", infill_glass_transforms, "InfillBlenderGlassTowers")
	_enhancement_stats["infill_model_buildings"] = infill_townhouse_transforms.size() + infill_hero_transforms.size() + infill_glass_transforms.size()
	_add_multimesh(parent, unit_box, _roof_material(false), flat_roof_transforms, "InfillFlatRoofs", false)
	_add_multimesh(parent, _get_gable_mesh(), _roof_material(true), pitched_roof_transforms, "InfillPitchedRoofs", true)
	_add_multimesh(parent, unit_box, _prop_material("FacadeGlass"), storefront_transforms, "CityStorefrontGlass", false)
	_add_multimesh(parent, unit_box, _terrain_material("concrete"), balcony_transforms, "CityBalconySlabs", false)
	_add_multimesh(parent, unit_box, _prop_material("PropsMetal"), rooftop_transforms, "CityRooftopUnits", false)
	_add_multimesh(parent, unit_cylinder, _prop_material("PropsMetal"), tank_transforms, "CityWaterTanks", false)
	for group_index in 3:
		_add_multimesh(parent, unit_box, sign_materials[group_index], sign_transforms[group_index], "CityRoadSigns_%d" % group_index, false)
		_add_multimesh(parent, unit_box, awning_materials[group_index], awning_transforms[group_index], "CityAwnings_%d" % group_index, false)

	var detail_count := storefront_transforms.size() + balcony_transforms.size() + rooftop_transforms.size() + tank_transforms.size()
	for group in sign_transforms:
		detail_count += (group as Array).size()
	for group in awning_transforms:
		detail_count += (group as Array).size()
	_enhancement_stats["building_details"] = detail_count

	# Expose the completed parcels to vegetation placement and the minimap
	# only after generation, so candidates never test against themselves
	# through the generic clearance helper during the search.
	var all_buildings: Array = data.get("buildings", [])
	for item in accepted:
		all_buildings.append(item)
	data["buildings"] = all_buildings


func _get_sail_mesh() -> ArrayMesh:
	if _sail_mesh != null:
		return _sail_mesh
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var front := 0.5
	var back := -0.5
	var a := Vector3(-0.5, 0.0, front)
	var b := Vector3(0.5, 0.0, front)
	var c := Vector3(0.30, 1.0, front)
	var a2 := Vector3(-0.5, 0.0, back)
	var b2 := Vector3(0.5, 0.0, back)
	var c2 := Vector3(0.30, 1.0, back)
	# Clockwise-as-seen-from-outside winding for Godot front faces; the
	# intuitive outward-cross order made this prism hollow from outside.
	var vertices: Array[Vector3] = [
		a, c, b,
		b2, c2, a2,
		a, b2, a2, a, b, b2,
		b, c2, b2, b, c, c2,
		c, a2, c2, c, a, a2,
	]
	for vertex in vertices:
		tool.set_uv(Vector2(vertex.x + 0.5, vertex.y))
		tool.add_vertex(vertex)
	tool.index()
	tool.generate_normals()
	tool.generate_tangents()
	_sail_mesh = tool.commit()
	return _sail_mesh


func _build_landmarks() -> void:
	var root := Node3D.new()
	root.name = "Landmarks"
	add_child(root)
	var glass := _facade_material("glassTower", 90.0)
	var gold := _facade_material("goldTower", 70.0)
	var marble := _facade_material("marbleTower", 45.0)
	var hotel := _facade_material("hotelTower", 45.0)
	var sand := _facade_material("sandTower", 35.0)
	var concrete := _terrain_material("concrete")
	var wood := _prop_material("PropsWood")
	var metal := _prop_material("PropsMetal")

	for landmark_variant in data.get("landmarks", []):
		var item: Dictionary = landmark_variant
		var kind := String(item.get("kind", ""))
		var pos := _item_position(item)
		var h := _f(item, "h")
		var r := _f(item, "r")
		match kind:
			"rt-tower":
				# Building Model No.5 is a finished flagship measuring
				# exactly 50.00 x 42.00 m and 148.00 m high (GLB AABB
				# centre x/z = 0.0 / 0.0). It is placed at scale 1.0:
				# the old 70.71 m square proxy and its 2.09x vertical
				# stretch are gone, so the podium doors, 3.42 m floors,
				# oval taper, 30-degree twist and crown keep real sizes.
				var transform_value := _centered_model_transform(pos, 0.0, Vector3.ONE, Vector3.ZERO)
				var main_tower_built := _add_batched_model(root, "res://assets/buildings/main_tower.glb", [transform_value], "Main148mTower")
				_enhancement_stats["premium_main_tower_built"] = main_tower_built
				_enhancement_stats["premium_main_tower_fixed_scale"] = main_tower_built
				_enhancement_stats["premium_main_tower_detail_pass"] = main_tower_built
				_enhancement_stats["premium_main_tower_material_pass"] = main_tower_built and _materials.has("main_glass_physical") and _materials.has("main_spandrel") and _materials.has("main_stone") and _materials.has("main_trim") and _materials.has("main_metal") and _materials.has("main_water")
				_enhancement_stats["premium_main_tower_site_pass"] = main_tower_built and _materials.has("villa_pavement") and _materials.has("villa_lawn") and _materials.has("villa_hedge")
				if not main_tower_built:
					_add_box(root, Vector3(50.0, h, 42.0), pos + Vector3(0.0, h * 0.5, 0.0), glass)
				_add_box_collider(pos + Vector3(0.0, 74.0, 0.0), Vector3(50.00, 148.00, 42.00))
			"rt-arch":
				for side in [-1.0, 1.0]:
					var pillar_pos := pos + Vector3(19.0 * side, h * 0.5, 0.0)
					_add_box(root, Vector3(5.0, h, 5.5), pillar_pos, gold)
					_add_box_collider(pillar_pos, Vector3(5.0, h, 5.5))
				_add_box(root, Vector3(43.0, 6.0, 5.5), pos + Vector3(0.0, h - 3.0, 0.0), gold)
			"rt-fountain":
				_add_cylinder(root, r, 1.0, pos + Vector3(0.0, 0.5, 0.0), concrete, 0.0, 36)
				_add_cylinder(root, r - 1.5, 0.22, pos + Vector3(0.0, 0.96, 0.0), _pool_material(), 0.0, 36)
				_add_cylinder(root, 1.25, 4.2, pos + Vector3(0.0, 2.1, 0.0), marble, 0.0, 20)
				_add_fountain_particles(root, pos + Vector3(0.0, 4.05, 0.0))
				_add_cylinder_collider(pos + Vector3(0.0, 1.0, 0.0), r, 2.0)
			"rt-sail":
				_add_box(root, Vector3(56.0, 3.0, 30.0), pos + Vector3(0.0, 0.8, 0.0), marble)
				_mesh_instance(root, _get_sail_mesh(), glass, make_transform(pos + Vector3(0.0, 2.0, 0.0), PI * 0.5, Vector3(48.0, h, 15.0)), "SailHotel")
				_add_cylinder(root, 0.45, 22.0, pos + Vector3(15.0, h + 8.0, 0.0), metal, 0.0, 12)
				_add_box_collider(pos + Vector3(0.0, h * 0.5, 0.0), Vector3(46.0, h, 18.0), PI * 0.5)
			"rt-museum":
				var torus := TorusMesh.new()
				torus.inner_radius = 11.0
				torus.outer_radius = 19.0
				torus.rings = 36
				torus.ring_segments = 14
				var torus_transform := Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(1.0, 1.25, 0.42)), pos + Vector3(0.0, 15.0, 0.0))
				_mesh_instance(root, torus, metal, torus_transform, "MuseumRing")
				_add_box(root, Vector3(42.0, 3.0, 16.0), pos + Vector3(0.0, 1.5, 0.0), marble)
				_add_box_collider(pos + Vector3(0.0, 9.0, 0.0), Vector3(40.0, 18.0, 10.0))
			"rt-opera":
				_add_box(root, Vector3(48.0, 6.0, 28.0), pos + Vector3(0.0, 3.0, 0.0), marble)
				for i in 3:
					_add_sphere(root, 11.0 - float(i) * 1.4, h, pos + Vector3(-14.0 + float(i) * 14.0, 6.0 + h * 0.24, 0.0), sand)
				_add_box_collider(pos + Vector3(0.0, h * 0.5, 0.0), Vector3(48.0, h, 28.0))
			"rt-mosque":
				_add_box(root, Vector3(34.0, 13.0, 30.0), pos + Vector3(0.0, 6.5, 0.0), sand)
				_add_sphere(root, 11.5, 19.0, pos + Vector3(0.0, 15.0, 0.0), marble)
				for side in [-1.0, 1.0]:
					var minaret_pos := pos + Vector3(19.0 * side, h * 0.5, 0.0)
					_add_cylinder(root, 1.4, h, minaret_pos, sand, 0.0, 14)
					_add_cylinder_collider(minaret_pos, 1.6, h)
				_add_box_collider(pos + Vector3(0.0, 8.0, 0.0), Vector3(34.0, 16.0, 30.0))
			"rt-twist":
				var tiers := 8
				var tier_h := h / float(tiers)
				for i in tiers:
					_add_box(root, Vector3(29.0, tier_h + 0.05, 29.0), pos + Vector3(0.0, tier_h * (float(i) + 0.5), 0.0), glass, float(i) * 0.085)
				_add_box_collider(pos + Vector3(0.0, h * 0.5, 0.0), Vector3(31.0, h, 31.0))
			"rt-lean":
				var lean_basis := Basis(Vector3.FORWARD, 0.075)
				var mesh := BoxMesh.new()
				mesh.size = Vector3(28.0, h, 28.0)
				_mesh_instance(root, mesh, hotel, Transform3D(lean_basis, pos + Vector3(0.0, h * 0.48, 0.0)), "LeaningTower")
				_add_box_collider(pos + Vector3(0.0, h * 0.5, 0.0), Vector3(31.0, h, 31.0))
			"rt-hole":
				for side in [-1.0, 1.0]:
					var pillar_pos := pos + Vector3(13.0 * side, h * 0.5, 0.0)
					_add_box(root, Vector3(9.0, h, 28.0), pillar_pos, glass)
					_add_box_collider(pillar_pos, Vector3(9.0, h, 28.0))
				_add_box(root, Vector3(35.0, 14.0, 28.0), pos + Vector3(0.0, h - 7.0, 0.0), glass)
			"rt-parking":
				for level in 5:
					_add_box(root, Vector3(48.0, 0.7, 30.0), pos + Vector3(0.0, 1.6 + float(level) * 3.1, 0.0), concrete)
				for sx in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						_add_box(root, Vector3(1.1, h, 1.1), pos + Vector3(22.0 * sx, h * 0.5, 13.0 * sz), concrete)
				_add_box_collider(pos + Vector3(0.0, h * 0.5, 0.0), Vector3(48.0, h, 30.0))
			"rt-aquapark":
				_add_cylinder(root, r, 1.0, pos + Vector3(0.0, 0.4, 0.0), concrete, 0.0, 36)
				_add_cylinder(root, r - 3.0, 0.25, pos + Vector3(0.0, 0.95, 0.0), _pool_material(), 0.0, 36)
				_add_box(root, Vector3(7.0, 15.0, 7.0), pos + Vector3(-16.0, 7.5, 0.0), hotel)
				_add_cylinder_collider(pos + Vector3(0.0, 1.0, 0.0), r, 2.0)
			"rt-lifeguard":
				for sx in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						_add_cylinder(root, 0.12, 3.6, pos + Vector3(1.1 * sx, 1.8, 1.1 * sz), wood, 0.0, 8)
				_add_box(root, Vector3(3.4, 2.4, 3.2), pos + Vector3(0.0, 4.4, 0.0), wood)
				_mesh_instance(root, _get_gable_mesh(), _roof_material(true), make_transform(pos + Vector3(0.0, 5.55, 0.0), 0.0, Vector3(4.2, 1.2, 4.0)), "LifeguardRoof")
				_add_box_collider(pos + Vector3(0.0, 3.0, 0.0), Vector3(3.6, 6.0, 3.6))
			_:
				var fallback_height := maxf(h, 8.0)
				_add_box(root, Vector3(24.0, fallback_height, 24.0), pos + Vector3(0.0, fallback_height * 0.5, 0.0), hotel)
				_add_box_collider(pos + Vector3(0.0, fallback_height * 0.5, 0.0), Vector3(24.0, fallback_height, 24.0))


func _add_fountain_particles(parent: Node, origin: Vector3) -> void:
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 11.0
	process.initial_velocity_min = 6.1
	process.initial_velocity_max = 7.3
	process.gravity = Vector3(0.0, -9.8, 0.0)
	process.damping_min = 0.0
	process.damping_max = 0.08
	process.scale_min = 0.7
	process.scale_max = 1.25
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.32

	var droplet := SphereMesh.new()
	droplet.radius = 0.045
	droplet.height = 0.09
	droplet.radial_segments = 6
	droplet.rings = 3
	var droplet_material := StandardMaterial3D.new()
	droplet_material.albedo_color = Color(0.55, 0.84, 1.0, 0.50)
	droplet_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	droplet_material.roughness = 0.05
	droplet_material.metallic = 0.0
	droplet_material.metallic_specular = 1.0
	droplet.material = droplet_material

	var particles := GPUParticles3D.new()
	particles.name = "FountainWater"
	particles.position = origin
	particles.amount = 320
	particles.lifetime = 1.35
	particles.preprocess = 1.35
	particles.randomness = 0.55
	particles.local_coords = false
	particles.process_material = process
	particles.draw_pass_1 = droplet
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-14.0, -5.0, -14.0), Vector3(28.0, 18.0, 28.0))
	parent.add_child(particles)
	_enhancement_stats["fountain_particles"] = particles.amount


func _find_node_by_name(node: Node, target_name: String) -> Node:
	if String(node.name) == target_name:
		return node
	for child in node.get_children():
		var found := _find_node_by_name(child, target_name)
		if found != null:
			return found
	return null


func _load_plant_parts() -> bool:
	if not _plant_parts.is_empty():
		return true
	var path := "res://assets/vegetation/plants.glb"
	if not ResourceLoader.exists(path):
		push_warning("Native plant pack is missing: %s" % path)
		return false
	var packed := load(path) as PackedScene
	if packed == null:
		return false
	var root := packed.instantiate()
	if root == null:
		return false
	for part_name in ["tree2_bark", "tree2_foliage", "bush_round_foliage", "shrub_cone_foliage", "fan_foliage"]:
		var found := _find_node_by_name(root, part_name)
		if found is MeshInstance3D:
			var mesh_instance := found as MeshInstance3D
			if mesh_instance.mesh != null:
				var material_name := "nh_foliage"
				var mat := mesh_instance.get_surface_override_material(0)
				if mat == null and mesh_instance.mesh.get_surface_count() > 0:
					mat = mesh_instance.mesh.surface_get_material(0)
				if mat != null and not String(mat.resource_name).is_empty():
					material_name = String(mat.resource_name)
				# The oak canopy alone is 7.8k triangles and every bush
				# is 3.0-3.5k. Give these five source meshes an explicit
				# aggressive LOD chain before they are instanced hundreds
				# of times; the HLOD ellipsoids below take over farther out.
				var lod_mesh := _mesh_with_runtime_lods(mesh_instance.mesh, 78.0)
				var part_material: Material
				if String(part_name).contains("foliage"):
					# Drive foliage_wind: per-part AABB gives the shader a
					# truthful sway mask for each source mesh. The local
					# bend is deliberately small because tree MultiMeshes
					# scale these parts by roughly 2.85 in world space.
					part_material = _create_foliage_wind_material(
						lod_mesh,
						"foliage.jpg",
						Color(0.62, 0.86, 0.52),
						0.0,
						0.030
					)
				else:
					part_material = _prop_material(material_name)
				_plant_parts[part_name] = {
					"mesh": lod_mesh,
					"material": part_material,
				}
	root.free()
	return not _plant_parts.is_empty()


func _get_palm_crown_mesh() -> ArrayMesh:
	if _palm_crown_mesh != null:
		return _palm_crown_mesh
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 10:
		var angle := TAU * float(i) / 10.0
		var basis := Basis(Vector3.UP, angle)
		var local_points: Array[Vector3] = [
			Vector3(-0.34, 0.0, 0.0),
			Vector3(0.34, 0.0, 0.0),
			Vector3(0.18, -0.82, 3.25),
			Vector3(-0.18, -0.82, 3.25),
		]
		var points: Array[Vector3] = []
		for point_value in local_points:
			points.append(basis * point_value)
		var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for index in [0, 1, 2, 0, 2, 3]:
			tool.set_uv(uvs[index])
			tool.add_vertex(points[index])
	tool.index()
	tool.generate_normals()
	tool.generate_tangents()
	_palm_crown_mesh = tool.commit()
	return _palm_crown_mesh


func _palm_leaf_material() -> Material:
	if _palm_leaf_shader_material != null:
		return _palm_leaf_shader_material
	# Palm fronds droop below their local origin, so a height mask would
	# clamp to zero. Their UV.y already runs base -> tip and is the correct
	# wind mask for this custom crown mesh.
	_palm_leaf_shader_material = _create_foliage_wind_material(
		_get_palm_crown_mesh(),
		"user_palm_leaf.png",
		Color(0.72, 0.96, 0.62),
		0.32,
		0.11,
		true
	)
	return _palm_leaf_shader_material


func _get_far_proxy_sphere_mesh() -> SphereMesh:
	if _far_proxy_sphere_mesh != null:
		return _far_proxy_sphere_mesh
	_far_proxy_sphere_mesh = SphereMesh.new()
	_far_proxy_sphere_mesh.radius = 1.0
	_far_proxy_sphere_mesh.height = 2.0
	_far_proxy_sphere_mesh.radial_segments = 10
	_far_proxy_sphere_mesh.rings = 6
	return _far_proxy_sphere_mesh


## The plant-pack canopy/bushes are attractive up close but cost
## 3.0-7.8k triangles per instance. Beyond the detailed HLOD range a
## textured ellipsoid fitted to the exact source AABB preserves the
## canopy mass and placement for roughly a hundred triangles.
func _add_foliage_far_proxy(parent: Node, source_mesh: Mesh, transforms: Array, node_name: String, begin_m: float, end_m: float) -> void:
	if source_mesh == null or transforms.is_empty():
		return
	var aabb := source_mesh.get_aabb()
	var local_transform := Transform3D(Basis.IDENTITY.scaled(aabb.size * 0.5), aabb.get_center())
	var proxy_transforms: Array = []
	for transform_variant in transforms:
		proxy_transforms.append((transform_variant as Transform3D) * local_transform)
	var built := _add_multimesh(
		parent,
		_get_far_proxy_sphere_mesh(),
		_prop_material("nh_foliage"),
		proxy_transforms,
		"%sFarProxy" % node_name,
		false,
		begin_m,
		end_m,
		260.0
	)
	if built:
		_enhancement_stats["vegetation_far_proxies"] = int(_enhancement_stats.get("vegetation_far_proxies", 0)) + transforms.size()
		_enhancement_stats["vegetation_hlod_0216"] = true


func _build_vegetation() -> void:
	var root := Node3D.new()
	root.name = "Vegetation"
	add_child(root)

	if _load_plant_parts():
		var trees: Array = data.get("trees", []).duplicate()
		var extra_tree_count := 0

		# Plaza ring: mature oaks frame the fountain instead of leaving the
		# exported six distant hill trees as the city's only broadleaf trees.
		for i in 10:
			var angle := TAU * float(i) / 10.0 + 0.18
			var candidate: Vector3 = Vector3(665.0 + cos(angle) * 30.0, 0.0, -25.0 + sin(angle) * 30.0)
			candidate.y = height_at(candidate.x, candidate.z)
			if _is_position_clear(candidate, 2.0, 2.5):
				trees.append({"x": candidate.x, "y": candidate.y, "z": candidate.z, "rotY": angle * 1.7, "s": 0.92, "type": "oak"})
				extra_tree_count += 1

		# Street trees along the western residential avenue.
		var west_index := 0
		for z in range(-390, 391, 45):
			var x := 546.0 if west_index % 2 == 0 else 574.0
			var candidate: Vector3 = Vector3(x, height_at(x, float(z)), float(z))
			if _is_position_clear(candidate, 2.0, 4.0):
				trees.append({"x": candidate.x, "y": candidate.y, "z": candidate.z, "rotY": float(west_index) * 0.83, "s": 0.86 + float(west_index % 3) * 0.08, "type": "oak"})
				extra_tree_count += 1
			west_index += 1

		# Shade trees on the Corniche and outer Boulevard verges.  The
		# building/road clearance test removes candidates in hotel plots,
		# intersections and driveways while keeping a continuous canopy.
		var promenade_index := 0
		for z in range(-390, 391, 45):
			var candidate: Vector3 = Vector3(912.0, height_at(912.0, float(z)), float(z))
			if _is_position_clear(candidate, 2.0, 4.0):
				trees.append({"x": candidate.x, "y": candidate.y, "z": candidate.z, "rotY": float(promenade_index) * 0.71, "s": 0.84 + float(promenade_index % 3) * 0.07, "type": "oak"})
				extra_tree_count += 1
			promenade_index += 1
		var boulevard_index := 0
		for z in range(-380, 386, 55):
			for x in [738.0, 782.0]:
				var candidate := Vector3(x, height_at(x, float(z)), float(z))
				if _is_position_clear(candidate, 2.0, 4.0):
					trees.append({"x": candidate.x, "y": candidate.y, "z": candidate.z, "rotY": float(boulevard_index) * 0.93, "s": 0.82 + float(boulevard_index % 4) * 0.06, "type": "oak"})
					extra_tree_count += 1
				boulevard_index += 1

		# Deterministic hillside woodland.  Candidates are rejected on
		# roads, landmarks, steep/underwater terrain and building plots.
		var hill_ix := 0
		for base_x in range(970, 1241, 28):
			var hill_iz := 0
			for base_z in range(-470, 471, 32):
				var jitter_x := (_hash01(hill_ix * 13 + 7, hill_iz * 17 + 3) - 0.5) * 18.0
				var jitter_z := (_hash01(hill_ix * 19 + 11, hill_iz * 23 + 5) - 0.5) * 20.0
				var candidate := Vector3(float(base_x) + jitter_x, 0.0, float(base_z) + jitter_z)
				candidate.y = height_at(candidate.x, candidate.z)
				var slope := absf(height_at(candidate.x + 4.0, candidate.z) - candidate.y) / 4.0
				if candidate.y > 5.4 and slope < 0.55 and _is_position_clear(candidate, 4.0, 9.0):
					trees.append({
						"x": candidate.x,
						"y": candidate.y,
						"z": candidate.z,
						"rotY": _hash01(hill_ix + 41, hill_iz + 97) * TAU,
						"s": 0.82 + _hash01(hill_ix + 3, hill_iz + 29) * 0.38,
						"type": "oak",
					})
					extra_tree_count += 1
				hill_iz += 1
			hill_ix += 1
		_enhancement_stats["extra_trees"] = extra_tree_count

		var tree_transforms: Array[Transform3D] = []
		for tree_variant in trees:
			var tree: Dictionary = tree_variant
			var scale_value := 2.85 * _f(tree, "s", 1.0)
			tree_transforms.append(make_transform(_item_position(tree, -0.04), _f(tree, "rotY"), Vector3.ONE * scale_value))
			_add_cylinder_collider(_item_position(tree, 1.4), 0.38, 3.2)
		for part_name in ["tree2_bark", "tree2_foliage"]:
			if _plant_parts.has(part_name):
				var part: Dictionary = _plant_parts[part_name]
				var source_mesh := part.get("mesh") as Mesh
				# The 199-triangle trunk can stay visible much farther
				# than the 7.8k canopy. Trunks keep a grounding shadow;
				# the canopy HLOD ellipsoid takes over after 220 m.
				var detail_end := 500.0 if part_name == "tree2_bark" else 240.0
				_add_multimesh(
					root,
					source_mesh,
					part.get("material") as Material,
					tree_transforms,
					part_name,
					part_name == "tree2_bark",
					0.0,
					detail_end,
					180.0
				)
				if part_name == "tree2_foliage":
					_add_foliage_far_proxy(root, source_mesh, tree_transforms, part_name, 220.0, 650.0)

		var bush_transforms: Dictionary = {
			"bush_round_foliage": [],
			"shrub_cone_foliage": [],
			"fan_foliage": [],
		}
		var bushes: Array = data.get("bushes", []).duplicate()
		for pool_variant in data.get("pools", []):
			var pool: Dictionary = pool_variant
			var base := _item_position(pool)
			for offset in [Vector3(-7.0, 0.0, -4.6), Vector3(7.0, 0.0, -4.6), Vector3(-7.0, 0.0, 4.6), Vector3(7.0, 0.0, 4.6)]:
				bushes.append({
					"x": base.x + offset.x,
					"y": height_at(base.x + offset.x, base.z + offset.z),
					"z": base.z + offset.z,
					"rotY": fmod(abs(base.x * 0.37 + base.z * 0.71 + offset.x), TAU),
					"s": 0.95,
				})
		var extra_bush_count := 0
		for building_variant in data.get("buildings", []):
			var building: Dictionary = building_variant
			var centre := _item_position(building)
			var building_yaw := _f(building, "rotY")
			var building_basis := Basis(Vector3.UP, building_yaw)
			var w := _f(building, "w", 20.0)
			var d := _f(building, "d", 16.0)
			for local_offset in [Vector3(-w * 0.34, 0.0, d * 0.5 + 2.1), Vector3(w * 0.34, 0.0, d * 0.5 + 2.1), Vector3(-w * 0.34, 0.0, -d * 0.5 - 2.1), Vector3(w * 0.34, 0.0, -d * 0.5 - 2.1)]:
				var candidate: Vector3 = centre + building_basis * local_offset
				candidate.y = height_at(candidate.x, candidate.z)
				var surface_kind := String(get_surface_at(candidate).get("kind", ""))
				if surface_kind != "asphalt" and surface_kind != "water" and candidate.y > 1.2:
					bushes.append({
						"x": candidate.x,
						"y": candidate.y,
						"z": candidate.z,
						"rotY": fmod(abs(candidate.x * 0.43 + candidate.z * 0.67), TAU),
						"s": 0.88,
					})
					extra_bush_count += 1
		for i in 12:
			var angle := TAU * float(i) / 12.0 + 0.12
			var candidate := Vector3(665.0 + cos(angle) * 22.0, 0.0, -25.0 + sin(angle) * 22.0)
			candidate.y = height_at(candidate.x, candidate.z)
			if _is_position_clear(candidate, 1.0, 2.0):
				bushes.append({"x": candidate.x, "y": candidate.y, "z": candidate.z, "rotY": angle, "s": 0.95})
				extra_bush_count += 1
		_enhancement_stats["extra_bushes"] = extra_bush_count

		var bush_names: Array[String] = ["bush_round_foliage", "shrub_cone_foliage", "fan_foliage"]
		for i in bushes.size():
			var bush: Dictionary = bushes[i]
			var part_name := bush_names[i % bush_names.size()]
			var target_height := 1.45 if part_name == "bush_round_foliage" else (2.25 if part_name == "shrub_cone_foliage" else 1.25)
			var source_height := 0.77 if part_name == "bush_round_foliage" else (1.65 if part_name == "shrub_cone_foliage" else 0.60)
			var scale_value := target_height / source_height * _f(bush, "s", 1.0)
			(bush_transforms[part_name] as Array).append(make_transform(_item_position(bush, -0.03), _f(bush, "rotY"), Vector3.ONE * scale_value))
		for part_name in bush_transforms.keys():
			if _plant_parts.has(part_name):
				var part: Dictionary = _plant_parts[part_name]
				var source_mesh := part.get("mesh") as Mesh
				var part_transforms: Array = bush_transforms[part_name]
				# Detailed 3.0-3.5k shrubs are a near-field layer only;
				# fitted ellipsoids preserve planting beds to 420 m.
				_add_multimesh(
					root,
					source_mesh,
					part.get("material") as Material,
					part_transforms,
					String(part_name),
					false,
					0.0,
					180.0,
					180.0
				)
				_add_foliage_far_proxy(root, source_mesh, part_transforms, String(part_name), 160.0, 420.0)

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.15
	trunk_mesh.bottom_radius = 0.29
	trunk_mesh.height = 5.8
	trunk_mesh.radial_segments = 10
	var palms: Array = data.get("palms", []).duplicate()
	var extra_palm_count := 0
	var beach_palm_index := 0
	for palm_z in range(-420, 421, 42):
		var palm_x := 950.0 + float(beach_palm_index % 3) * 9.0
		var palm_candidate := Vector3(palm_x, height_at(palm_x, float(palm_z)), float(palm_z))
		if palm_candidate.y > 0.7 and _is_position_clear(palm_candidate, 2.5, 5.0) and String(get_surface_at(palm_candidate).get("kind", "")) != "water":
			palms.append({
				"x": palm_candidate.x,
				"y": palm_candidate.y,
				"z": palm_candidate.z,
				"rotY": float(beach_palm_index) * 0.77,
				"s": 0.92 + float(beach_palm_index % 3) * 0.07,
			})
			extra_palm_count += 1
		beach_palm_index += 1
	_enhancement_stats["extra_palms"] = extra_palm_count

	var trunk_transforms: Array[Transform3D] = []
	var crown_transforms: Array[Transform3D] = []
	for palm_variant in palms:
		var palm: Dictionary = palm_variant
		var scale_value := _f(palm, "s", 1.0)
		var base := _item_position(palm)
		trunk_transforms.append(make_transform(base + Vector3(0.0, 2.9 * scale_value, 0.0), _f(palm, "rotY"), Vector3.ONE * scale_value))
		crown_transforms.append(make_transform(base + Vector3(0.0, 5.72 * scale_value, 0.0), _f(palm, "rotY") * 1.7, Vector3.ONE * scale_value))
		_add_cylinder_collider(base + Vector3(0.0, 2.5, 0.0), 0.30, 5.2)
	_add_multimesh(root, trunk_mesh, _prop_material("nh_bark"), trunk_transforms, "PalmTrunks")
	_add_multimesh(root, _get_palm_crown_mesh(), _palm_leaf_material(), crown_transforms, "PalmCrowns", false)


func _build_street_lamps() -> void:
	var root := Node3D.new()
	root.name = "StreetLamps"
	add_child(root)
	var transforms: Array[Transform3D] = []
	for lamp_variant in data.get("lamps", []):
		var lamp: Dictionary = lamp_variant
		var position_value := _item_position(lamp)
		transforms.append(make_transform(position_value, _f(lamp, "rotY"), Vector3.ONE))
		_add_cylinder_collider(position_value + Vector3(0.0, 3.2, 0.0), 0.18, 6.6)
	_add_batched_model(root, "res://assets/props/street_lamp.glb", transforms, "BlenderStreetLamps")


func _build_bus_shelters() -> void:
	var root := Node3D.new()
	root.name = "BusShelters"
	add_child(root)
	var transforms: Array[Transform3D] = []
	var placements: Array[Dictionary] = [
		{"x": 744.2, "z": -383.0, "yaw": PI * 0.5},
		{"x": 744.2, "z": -174.0, "yaw": PI * 0.5},
		{"x": 744.2, "z": 16.0, "yaw": PI * 0.5},
		{"x": 744.2, "z": 215.0, "yaw": PI * 0.5},
		{"x": 775.8, "z": -290.0, "yaw": -PI * 0.5},
		{"x": 775.8, "z": -90.0, "yaw": -PI * 0.5},
		{"x": 775.8, "z": 78.0, "yaw": -PI * 0.5},
		{"x": 775.8, "z": 235.0, "yaw": -PI * 0.5},
		{"x": 914.0, "z": -300.0, "yaw": PI * 0.5},
		{"x": 914.0, "z": -110.0, "yaw": PI * 0.5},
		{"x": 914.0, "z": 70.0, "yaw": PI * 0.5},
		{"x": 914.0, "z": 250.0, "yaw": PI * 0.5},
		{"x": 551.0, "z": -260.0, "yaw": PI * 0.5},
		{"x": 569.0, "z": 30.0, "yaw": -PI * 0.5},
		{"x": 551.0, "z": 300.0, "yaw": PI * 0.5},
		{"x": 640.0, "z": 50.7, "yaw": 0.0},
		{"x": 840.0, "z": 69.3, "yaw": PI},
	]
	for placement in placements:
		var position_value := Vector3(_f(placement, "x"), 0.0, _f(placement, "z"))
		position_value.y = height_at(position_value.x, position_value.z) + 0.02
		var yaw := _f(placement, "yaw")
		transforms.append(make_transform(position_value, yaw, Vector3.ONE))
		_add_box_collider(position_value + Vector3(0.0, 1.53, 0.0), Vector3(5.75, 3.06, 2.35), yaw)
	var built := _add_batched_model(root, "res://assets/props/bus_shelter.glb", transforms, "BlenderBusShelters")
	_enhancement_stats["bus_shelters"] = transforms.size() if built else 0


func _yaw_for_x_direction(direction: Vector3) -> float:
	return atan2(-direction.z, direction.x)


func _yaw_for_z_normal(normal: Vector3) -> float:
	return atan2(normal.x, normal.z)


func _is_roadside_position_valid(candidate: Vector3) -> bool:
	var clearance := _road_clearance_xz(candidate)
	if clearance < 0.55 or clearance > 3.4:
		return false
	if not _is_position_clear(candidate, 0.35, 0.0):
		return false
	return String(get_surface_at(candidate).get("kind", "")) != "water"


func _make_paving_patch_mesh(min_x: float, max_x: float, min_z: float, max_z: float, step_m: float = 2.0, lift_m: float = 0.035) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var columns := maxi(1, ceili((max_x - min_x) / step_m))
	var rows := maxi(1, ceili((max_z - min_z) / step_m))
	for iz in rows:
		for ix in columns:
			var x0 := min_x + float(ix) * step_m
			var x1 := minf(min_x + float(ix + 1) * step_m, max_x)
			var z0 := min_z + float(iz) * step_m
			var z1 := minf(min_z + float(iz + 1) * step_m, max_z)
			var p00 := Vector3(x0, height_at(x0, z0) + lift_m, z0)
			var p10 := Vector3(x1, height_at(x1, z0) + lift_m, z0)
			var p11 := Vector3(x1, height_at(x1, z1) + lift_m, z1)
			var p01 := Vector3(x0, height_at(x0, z1) + lift_m, z1)
			for vertex in [p00, p10, p11, p00, p11, p01]:
				_terrain_vertex(tool, vertex)
	tool.index()
	tool.generate_normals()
	tool.generate_tangents()
	return tool.commit()


func _build_premium_boulevard_details(parent: Node) -> void:
	# The main four-lane RichTown Boulevard already has the road mesh, lane
	# paint and curb system. Replace the adjacent monotonous slab field around
	# the screenshot location with a broad premium promenade and cafe arcades.
	var pavers := _material(
		"boulevard_premium_pavers",
		"user_travertine.jpg",
		"user_travertine_normal.jpg",
		Color(0.78, 0.75, 0.68),
		0.78,
		0.02,
		Vector3(0.34, 0.34, 0.34),
		true
	)
	pavers.normal_scale = 0.58
	pavers.metallic_specular = 0.42
	pavers.cull_mode = BaseMaterial3D.CULL_DISABLED
	var west_walk := _make_paving_patch_mesh(713.0, 744.0, -94.0, 48.0, 2.0, 0.045)
	var east_walk := _make_paving_patch_mesh(776.0, 789.0, -94.0, 48.0, 2.0, 0.045)
	if west_walk != null:
		_mesh_instance(parent, west_walk, pavers, Transform3D.IDENTITY, "PremiumPromenade_West", false)
	if east_walk != null:
		_mesh_instance(parent, east_walk, pavers, Transform3D.IDENTITY, "PremiumPromenade_East", false)

	var granite := _material("boulevard_granite", "user_black_granite.jpg", "user_black_granite_normal.jpg", Color(0.66, 0.68, 0.69), 0.34, 0.12, Vector3(0.35, 0.35, 0.35), true)
	granite.normal_scale = 0.52
	var curb_mesh := BoxMesh.new()
	curb_mesh.size = Vector3.ONE
	var promenade_curb_transforms: Array[Transform3D] = []
	for z in range(-92, 47, 2):
		for curb_x in [713.2, 743.8, 776.2, 788.8]:
			var center_z := float(z) + 1.0
			# Keep the two sidewalk shelter pads clear; the original shelter
			# models continue to use their exported locations and footprints.
			if (is_equal_approx(curb_x, 743.8) and absf(center_z - 16.0) < 4.0) or (is_equal_approx(curb_x, 776.2) and absf(center_z + 90.0) < 4.0):
				continue
			var y := height_at(curb_x, center_z) + 0.08
			promenade_curb_transforms.append(make_transform(Vector3(curb_x, y, center_z), 0.0, Vector3(0.22, 0.16, 2.05)))
	_add_multimesh(parent, curb_mesh, granite, promenade_curb_transforms, "PremiumGraniteEdging", false)

	# Formal lawn beds, clipped hedges and topiary break the paving into
	# comfortable walking rooms without narrowing the carriageway.
	var lawn := _material("boulevard_lawn", "user_grass.jpg", "user_grass_normal.jpg", Color(0.60, 0.76, 0.43), 0.96)
	var hedge := _material("boulevard_topiary", "foliage.jpg", "foliage_normal.jpg", Color(0.24, 0.47, 0.23), 0.92)
	hedge.cull_mode = BaseMaterial3D.CULL_DISABLED
	var sphere_hedge_mesh := SphereMesh.new()
	sphere_hedge_mesh.radius = 0.55
	sphere_hedge_mesh.height = 1.12
	sphere_hedge_mesh.radial_segments = 18
	sphere_hedge_mesh.rings = 10
	var lawn_mesh := BoxMesh.new()
	lawn_mesh.size = Vector3.ONE
	var planter_mesh := BoxMesh.new()
	planter_mesh.size = Vector3.ONE
	var lawn_transforms: Array[Transform3D] = []
	var planter_transforms: Array[Transform3D] = []
	var ball_topiary_transforms: Array[Transform3D] = []
	var hedge_block_transforms: Array[Transform3D] = []
	for side_x in [717.5, 784.5]:
		for z in [-82.0, -39.0, 4.0, 43.0]:
			var center := Vector3(float(side_x), 0.0, float(z))
			center.y = height_at(center.x, center.z)
			planter_transforms.append(make_transform(center + Vector3(0.0, 0.13, 0.0), 0.0, Vector3(3.8, 0.26, 8.2)))
			lawn_transforms.append(make_transform(center + Vector3(0.0, 0.29, 0.0), 0.0, Vector3(3.35, 0.08, 7.75)))
			if int(round(z / 30.0)) % 2 == 0:
				ball_topiary_transforms.append(make_transform(center + Vector3(0.0, 0.93, 0.0), 0.0, Vector3.ONE))
			else:
				hedge_block_transforms.append(make_transform(center + Vector3(0.0, 0.77, 0.0), 0.0, Vector3(2.6, 0.86, 0.92)))
	_add_multimesh(parent, planter_mesh, granite, planter_transforms, "BoulevardRaisedPlanters", false)
	_add_multimesh(parent, lawn_mesh, lawn, lawn_transforms, "BoulevardLawnIslands", false)
	_add_multimesh(parent, sphere_hedge_mesh, hedge, ball_topiary_transforms, "BoulevardRoundTopiary", false)
	_add_multimesh(parent, lawn_mesh, hedge, hedge_block_transforms, "BoulevardClippedHedges", false)

	# The Washingtonia row is already laid out on both sides of this avenue.
	# Give each trunk a white-pebble bed, granite ring and a visible drip line.
	var pebble_material := _material("boulevard_white_pebbles", "user_stone_tiles_beige.jpg", "", Color(0.96, 0.95, 0.91), 0.94, 0.0, Vector3(0.72, 0.72, 0.72), true)
	var irrigation_material := _material("boulevard_irrigation", "user_black_rough.jpg", "user_black_rough_normal.jpg", Color(0.10, 0.12, 0.12), 0.74, 0.0)
	var pebble_disk := CylinderMesh.new()
	pebble_disk.top_radius = 1.0
	pebble_disk.bottom_radius = 1.0
	pebble_disk.height = 0.08
	pebble_disk.radial_segments = 24
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.86
	ring_mesh.outer_radius = 1.0
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 8
	var drip_ring_mesh := TorusMesh.new()
	drip_ring_mesh.inner_radius = 0.50
	drip_ring_mesh.outer_radius = 0.59
	drip_ring_mesh.rings = 16
	drip_ring_mesh.ring_segments = 6
	var pebble_transforms: Array[Transform3D] = []
	var ring_transforms: Array[Transform3D] = []
	var drip_transforms: Array[Transform3D] = []
	for palm_variant in data.get("palms", []):
		var palm: Dictionary = palm_variant
		var palm_x := _f(palm, "x")
		var palm_z := _f(palm, "z")
		if palm_z < -98.0 or palm_z > 67.0 or minf(absf(palm_x - 745.5), absf(palm_x - 774.5)) > 1.0:
			continue
		var ground_y := height_at(palm_x, palm_z)
		pebble_transforms.append(make_transform(Vector3(palm_x, ground_y + 0.07, palm_z), 0.0, Vector3(1.58, 1.0, 1.58)))
		ring_transforms.append(make_transform(Vector3(palm_x, ground_y + 0.14, palm_z), 0.0, Vector3(1.58, 1.0, 1.58)))
		drip_transforms.append(make_transform(Vector3(palm_x, ground_y + 0.12, palm_z), 0.0, Vector3(1.10, 1.0, 1.10)))
	_add_multimesh(parent, pebble_disk, pebble_material, pebble_transforms, "WashingtoniaWhiteGravelBeds", false)
	_add_multimesh(parent, ring_mesh, granite, ring_transforms, "WashingtoniaGraniteRings", false)
	_add_multimesh(parent, drip_ring_mesh, irrigation_material, drip_transforms, "WashingtoniaDripIrrigation", false)

	# Three compact glass-and-metal cafe pavilions with attached umbrella
	# terraces. All repetitions are MultiMesh batches to keep draw calls low.
	var glass := _material("boulevard_cafe_glass", "", "", Color(0.36, 0.59, 0.66, 0.40), 0.055, 0.10)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic_specular = 1.0
	glass.clearcoat_enabled = true
	glass.clearcoat = 0.92
	glass.clearcoat_roughness = 0.035
	var canopy_material := _material("boulevard_cafe_canopy", "user_travertine.jpg", "user_travertine_normal.jpg", Color(0.88, 0.84, 0.74), 0.64, 0.02)
	var counter_material := _material("boulevard_cafe_counter", "user_black_granite.jpg", "user_black_granite_normal.jpg", Color(0.39, 0.43, 0.44), 0.34, 0.20)
	var warm_sign := _material("boulevard_cafe_sign", "", "", Color(0.95, 0.53, 0.16), 0.34, 0.05)
	warm_sign.emission_enabled = true
	warm_sign.emission = Color(0.42, 0.12, 0.025)
	var table_material := _material("boulevard_cafe_table", "user_stone_tiles_beige.jpg", "", Color(0.86, 0.82, 0.73), 0.48, 0.03)
	var chair_material := _material("boulevard_cafe_chair", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.24, 0.30, 0.32), 0.36, 0.54)
	var umbrella_material := _material("boulevard_cafe_umbrella", "", "", Color(0.88, 0.84, 0.73), 0.78)
	var accent_umbrella := _material("boulevard_cafe_umbrella_teal", "", "", Color(0.10, 0.42, 0.42), 0.76)
	var glass_wall_transforms: Array[Transform3D] = []
	var canopy_transforms: Array[Transform3D] = []
	var frame_transforms: Array[Transform3D] = []
	var counter_transforms: Array[Transform3D] = []
	var sign_transforms: Array[Transform3D] = []
	var table_top_transforms: Array[Transform3D] = []
	var table_leg_transforms: Array[Transform3D] = []
	var chair_seat_transforms: Array[Transform3D] = []
	var chair_back_transforms: Array[Transform3D] = []
	var chair_leg_transforms: Array[Transform3D] = []
	var umbrella_pole_transforms: Array[Transform3D] = []
	var umbrella_canopy_transforms: Array[Transform3D] = []
	var accent_canopy_transforms: Array[Transform3D] = []
	var cafe_locations := [Vector2(718.0, -67.0), Vector2(718.0, -20.0), Vector2(718.0, 27.0)]
	for cafe_index in cafe_locations.size():
		var location: Vector2 = cafe_locations[cafe_index]
		var base := Vector3(location.x, height_at(location.x, location.y), location.y)
		# Glass walls on the back and two ends; the boulevard-facing side is open.
		glass_wall_transforms.append(make_transform(base + Vector3(-2.85, 1.34, 0.0), 0.0, Vector3(0.08, 2.55, 5.9)))
		glass_wall_transforms.append(make_transform(base + Vector3(0.0, 1.34, -2.92), 0.0, Vector3(5.7, 2.55, 0.08)))
		glass_wall_transforms.append(make_transform(base + Vector3(0.0, 1.34, 2.92), 0.0, Vector3(5.7, 2.55, 0.08)))
		canopy_transforms.append(make_transform(base + Vector3(0.0, 2.77, 0.0), 0.0, Vector3(6.5, 0.20, 6.6)))
		counter_transforms.append(make_transform(base + Vector3(-1.05, 0.58, 0.0), 0.0, Vector3(2.7, 0.95, 4.7)))
		sign_transforms.append(make_transform(base + Vector3(0.0, 2.43, 0.0), 0.0, Vector3(3.5, 0.20, 0.10)))
		for post_x in [-2.95, 2.95]:
			for post_z in [-2.95, 2.95]:
				frame_transforms.append(make_transform(base + Vector3(post_x, 1.42, post_z), 0.0, Vector3(0.10, 2.84, 0.10)))
		for table_z_offset in [-2.2, 2.2]:
			var table_center := base + Vector3(8.0, 0.0, table_z_offset)
			table_top_transforms.append(make_transform(table_center + Vector3(0.0, 0.82, 0.0), 0.0, Vector3(1.38, 0.10, 1.38)))
			table_leg_transforms.append(make_transform(table_center + Vector3(0.0, 0.43, 0.0), 0.0, Vector3(0.35, 0.76, 0.35)))
			umbrella_pole_transforms.append(make_transform(table_center + Vector3(0.0, 2.05, 0.0), 0.0, Vector3.ONE))
			var canopy_transform := make_transform(table_center + Vector3(0.0, 3.20, 0.0), 0.0, Vector3.ONE)
			if (cafe_index + int(table_z_offset > 0.0)) % 2 == 0:
				umbrella_canopy_transforms.append(canopy_transform)
			else:
				accent_canopy_transforms.append(canopy_transform)
			for chair_index in 4:
				var angle := TAU * float(chair_index) / 4.0
				var outward := Vector3(cos(angle), 0.0, sin(angle))
				var chair_center := table_center + outward * 1.18
				var chair_yaw := atan2(-outward.x, -outward.z)
				chair_seat_transforms.append(make_transform(chair_center + Vector3(0.0, 0.48, 0.0), chair_yaw, Vector3(0.48, 0.10, 0.48)))
				chair_back_transforms.append(make_transform(chair_center + outward * 0.20 + Vector3(0.0, 0.77, 0.0), chair_yaw, Vector3(0.48, 0.55, 0.09)))
				chair_leg_transforms.append(make_transform(chair_center + Vector3(-0.16, 0.23, -0.16), chair_yaw, Vector3(0.30, 0.46, 0.30)))
				chair_leg_transforms.append(make_transform(chair_center + Vector3(0.16, 0.23, -0.16), chair_yaw, Vector3(0.30, 0.46, 0.30)))
				chair_leg_transforms.append(make_transform(chair_center + Vector3(-0.16, 0.23, 0.16), chair_yaw, Vector3(0.30, 0.46, 0.30)))
				chair_leg_transforms.append(make_transform(chair_center + Vector3(0.16, 0.23, 0.16), chair_yaw, Vector3(0.30, 0.46, 0.30)))

	var unit_box := BoxMesh.new()
	unit_box.size = Vector3.ONE
	var cafe_pole_mesh := CylinderMesh.new()
	cafe_pole_mesh.top_radius = 0.035
	cafe_pole_mesh.bottom_radius = 0.045
	cafe_pole_mesh.height = 2.15
	cafe_pole_mesh.radial_segments = 10
	var cafe_umbrella_mesh := CylinderMesh.new()
	cafe_umbrella_mesh.top_radius = 0.06
	cafe_umbrella_mesh.bottom_radius = 1.42
	cafe_umbrella_mesh.height = 0.30
	cafe_umbrella_mesh.radial_segments = 16
	var cafe_table_mesh := CylinderMesh.new()
	cafe_table_mesh.top_radius = 0.69
	cafe_table_mesh.bottom_radius = 0.69
	cafe_table_mesh.height = 0.10
	cafe_table_mesh.radial_segments = 20
	var cafe_leg_mesh := CylinderMesh.new()
	cafe_leg_mesh.top_radius = 0.06
	cafe_leg_mesh.bottom_radius = 0.10
	cafe_leg_mesh.height = 0.76
	cafe_leg_mesh.radial_segments = 10
	_add_multimesh(parent, unit_box, glass, glass_wall_transforms, "BoulevardCafeGlassArcades", false)
	_add_multimesh(parent, unit_box, canopy_material, canopy_transforms, "BoulevardCafeCanopies", false)
	_add_multimesh(parent, unit_box, chair_material, frame_transforms, "BoulevardCafeHighTechFrames", false)
	_add_multimesh(parent, unit_box, counter_material, counter_transforms, "BoulevardCafeCounters", false)
	_add_multimesh(parent, unit_box, warm_sign, sign_transforms, "BoulevardCafeLightboxSigns", false)
	_add_multimesh(parent, cafe_table_mesh, table_material, table_top_transforms, "BoulevardCafeTables", false)
	_add_multimesh(parent, cafe_leg_mesh, chair_material, table_leg_transforms, "BoulevardCafeTablePedestals", false)
	_add_multimesh(parent, unit_box, chair_material, chair_seat_transforms, "BoulevardCafeChairSeats", false)
	_add_multimesh(parent, unit_box, chair_material, chair_back_transforms, "BoulevardCafeChairBacks", false)
	_add_multimesh(parent, cafe_leg_mesh, chair_material, chair_leg_transforms, "BoulevardCafeChairLegs", false)
	_add_multimesh(parent, cafe_pole_mesh, chair_material, umbrella_pole_transforms, "BoulevardCafeUmbrellaPoles", false)
	_add_multimesh(parent, cafe_umbrella_mesh, umbrella_material, umbrella_canopy_transforms, "BoulevardCafeUmbrellasIvory", false)
	_add_multimesh(parent, cafe_umbrella_mesh, accent_umbrella, accent_canopy_transforms, "BoulevardCafeUmbrellasTeal", false)
	_enhancement_stats["boulevard_cafes"] = cafe_locations.size()
	_enhancement_stats["boulevard_palm_planters"] = pebble_transforms.size()
	_enhancement_stats["boulevard_lawn_islands"] = lawn_transforms.size()
	_enhancement_stats["premium_boulevard_promenade_m2"] = (31.0 + 13.0) * 142.0


func _build_city_details() -> void:
	var root := Node3D.new()
	root.name = "CityDetails"
	add_child(root)
	_build_premium_boulevard_details(root)

	var unit_box := BoxMesh.new()
	unit_box.size = Vector3.ONE
	var bollard_mesh := CylinderMesh.new()
	bollard_mesh.top_radius = 0.09
	bollard_mesh.bottom_radius = 0.09
	bollard_mesh.height = 0.85
	bollard_mesh.radial_segments = 10
	var bin_mesh := CylinderMesh.new()
	bin_mesh.top_radius = 0.30
	bin_mesh.bottom_radius = 0.27
	bin_mesh.height = 0.78
	bin_mesh.radial_segments = 12
	var sign_post_mesh := CylinderMesh.new()
	sign_post_mesh.top_radius = 0.045
	sign_post_mesh.bottom_radius = 0.045
	sign_post_mesh.height = 2.8
	sign_post_mesh.radial_segments = 8
	var umbrella_pole_mesh := CylinderMesh.new()
	umbrella_pole_mesh.top_radius = 0.035
	umbrella_pole_mesh.bottom_radius = 0.035
	umbrella_pole_mesh.height = 2.1
	umbrella_pole_mesh.radial_segments = 8
	var umbrella_canopy_mesh := CylinderMesh.new()
	umbrella_canopy_mesh.top_radius = 0.06
	umbrella_canopy_mesh.bottom_radius = 1.35
	umbrella_canopy_mesh.height = 0.42
	umbrella_canopy_mesh.radial_segments = 10
	var mast_mesh := CylinderMesh.new()
	mast_mesh.top_radius = 0.05
	mast_mesh.bottom_radius = 0.05
	mast_mesh.height = 7.2
	mast_mesh.radial_segments = 8

	var metal := _prop_material("PropsMetal")
	var wood := _prop_material("PropsWood")
	var concrete := _terrain_material("concrete")
	var hedge := _material(
		"city_hedge",
		"foliage.jpg",
		"foliage_normal.jpg",
		Color(0.42, 0.72, 0.33),
		1.0,
		0.0,
		Vector3(0.35, 0.35, 0.35),
		true
	)
	hedge.cull_mode = BaseMaterial3D.CULL_DISABLED
	var white_painted := _material("city_white_painted", "", "", Color(0.90, 0.92, 0.90), 0.52, 0.05)
	var boat_blue := _material("city_boat_blue", "", "", Color(0.05, 0.28, 0.58), 0.38, 0.08)

	var sign_materials: Array[StandardMaterial3D] = []
	for sign_spec in [
		["city_sign_blue", Color(0.08, 0.34, 0.82)],
		["city_sign_orange", Color(0.98, 0.38, 0.07)],
		["city_sign_teal", Color(0.03, 0.58, 0.52)],
	]:
		var sign_material := _material(String(sign_spec[0]), "", "", sign_spec[1] as Color, 0.42, 0.04)
		sign_material.emission_enabled = true
		sign_material.emission = sign_spec[1] as Color
		_register_night_material(sign_material, 0.10, 0.75, 2.3)
		sign_materials.append(sign_material)

	var bollard_transforms: Array = []
	var planter_transforms: Array = []
	var hedge_transforms: Array = []
	var bin_transforms: Array = []
	var sign_post_transforms: Array = []
	var sign_panel_transforms: Array = [[], [], []]

	var segment_counter := 0
	var bollard_counter := 0
	var planter_counter := 0
	var bin_counter := 0
	var sign_counter := 0
	for road_variant in data.get("roads", []):
		var road: Dictionary = road_variant
		var samples: Array = road.get("samples", [])
		if samples.size() < 2:
			continue
		var width := _f(road, "widthM", 10.0)
		var half_width := width * 0.5
		for i in range(samples.size() - 1):
			var a := _sample_point(samples[i])
			var b := _sample_point(samples[i + 1])
			var direction := b - a
			direction.y = 0.0
			if direction.length_squared() < 0.01:
				continue
			direction = direction.normalized()
			var side_vector := Vector3(-direction.z, 0.0, direction.x)
			var midpoint := (a + b) * 0.5
			var road_yaw := _yaw_for_x_direction(direction)

			if width >= 17.0 and segment_counter % 3 == 0:
				var bollard_side := -1.0 if bollard_counter % 2 == 0 else 1.0
				bollard_counter += 1
				var bollard_pos := midpoint + side_vector * bollard_side * (half_width + 1.45)
				bollard_pos.y = maxf(height_at(bollard_pos.x, bollard_pos.z), midpoint.y + 0.04)
				if _is_roadside_position_valid(bollard_pos):
					bollard_transforms.append(make_transform(bollard_pos + Vector3(0.0, 0.43, 0.0), road_yaw, Vector3.ONE))

			if width >= 8.0 and segment_counter % 5 == 1:
				var planter_side := -1.0 if planter_counter % 2 == 0 else 1.0
				planter_counter += 1
				var planter_pos := midpoint + side_vector * planter_side * (half_width + 1.58)
				planter_pos.y = maxf(height_at(planter_pos.x, planter_pos.z), midpoint.y + 0.04)
				if _is_roadside_position_valid(planter_pos):
					planter_transforms.append(make_transform(planter_pos + Vector3(0.0, 0.28, 0.0), road_yaw, Vector3(1.9, 0.55, 0.75)))
					hedge_transforms.append(make_transform(planter_pos + Vector3(0.0, 0.76, 0.0), road_yaw, Vector3(1.68, 0.55, 0.56)))

			if segment_counter % 11 == 4:
				var bin_side := -1.0 if bin_counter % 2 == 0 else 1.0
				bin_counter += 1
				var bin_pos := midpoint + side_vector * bin_side * (half_width + 1.50)
				bin_pos.y = maxf(height_at(bin_pos.x, bin_pos.z), midpoint.y + 0.04)
				if _is_roadside_position_valid(bin_pos):
					bin_transforms.append(make_transform(bin_pos + Vector3(0.0, 0.39, 0.0), road_yaw, Vector3.ONE))

			if segment_counter % 14 == 7:
				var sign_side := -1.0 if sign_counter % 2 == 0 else 1.0
				var sign_group := sign_counter % 3
				sign_counter += 1
				var sign_pos := midpoint + side_vector * sign_side * (half_width + 1.65)
				sign_pos.y = maxf(height_at(sign_pos.x, sign_pos.z), midpoint.y + 0.04)
				if _is_roadside_position_valid(sign_pos):
					sign_post_transforms.append(make_transform(sign_pos + Vector3(0.0, 1.4, 0.0), road_yaw, Vector3.ONE))
					var panel_normal := -side_vector * sign_side
					(sign_panel_transforms[sign_group] as Array).append(make_transform(
						sign_pos + Vector3(0.0, 2.62, 0.0),
						_yaw_for_z_normal(panel_normal),
						Vector3(1.35, 0.82, 0.09)
					))

			segment_counter += 1

	_add_multimesh(root, bollard_mesh, metal, bollard_transforms, "CityBollards", false)
	_add_multimesh(root, unit_box, concrete, planter_transforms, "CityPlanters", false)
	_add_multimesh(root, unit_box, hedge, hedge_transforms, "CityHedges", false)
	_add_multimesh(root, bin_mesh, metal, bin_transforms, "CityTrashBins", false)
	_add_multimesh(root, sign_post_mesh, metal, sign_post_transforms, "CityRoadSignPosts", false)
	for group_index in 3:
		_add_multimesh(root, unit_box, sign_materials[group_index], sign_panel_transforms[group_index], "CityRoadSigns_%d" % group_index, false)

	var roadside_prop_count := bollard_transforms.size() + planter_transforms.size() + bin_transforms.size() + sign_post_transforms.size()
	_enhancement_stats["city_detail_props"] = roadside_prop_count
	_enhancement_stats["roadside_bollards"] = bollard_transforms.size()
	_enhancement_stats["roadside_planters"] = planter_transforms.size()

	# Beach furniture follows the actual exported sand surface.  It adds
	# colour and human scale to the Corniche without placing objects in
	# the marina water or on the carriageway.
	var beach_pole_transforms: Array = []
	var beach_canopy_transforms: Array = [[], [], [], []]
	var beach_lounger_transforms: Array = []
	var beach_materials: Array[StandardMaterial3D] = [
		_material("beach_umbrella_red", "", "", Color(0.78, 0.12, 0.10), 0.78),
		_material("beach_umbrella_blue", "", "", Color(0.08, 0.34, 0.74), 0.78),
		_material("beach_umbrella_yellow", "", "", Color(0.94, 0.68, 0.12), 0.78),
		_material("beach_umbrella_teal", "", "", Color(0.05, 0.58, 0.54), 0.78),
	]
	for grid_z in range(-430, 431, 24):
		var beach_iz := int(floor((float(grid_z) + 500.0) / 24.0))
		for grid_x in range(952, 1021, 14):
			var beach_ix := int(floor((float(grid_x) - 520.0) / 14.0))
			if _hash01(beach_ix * 7 + 3, beach_iz * 11 + 5) < 0.38:
				continue
			var beach_pos := Vector3(
				float(grid_x) + (_hash01(beach_ix, beach_iz) - 0.5) * 6.0,
				0.0,
				float(grid_z) + (_hash01(beach_iz, beach_ix) - 0.5) * 9.0
			)
			beach_pos.y = height_at(beach_pos.x, beach_pos.z)
			if beach_pos.y < 0.65 or beach_pos.y > 3.3:
				continue
			if _road_clearance_xz(beach_pos) < 2.2:
				continue
			if String(get_surface_at(beach_pos).get("kind", "")) != "sand":
				continue
			var beach_yaw := _hash01(beach_ix * 13, beach_iz * 17) * TAU
			beach_pole_transforms.append(make_transform(beach_pos + Vector3(0.0, 1.05, 0.0), beach_yaw, Vector3.ONE))
			(beach_canopy_transforms[(beach_ix + beach_iz) % 4] as Array).append(make_transform(
				beach_pos + Vector3(0.0, 2.05, 0.0),
				beach_yaw,
				Vector3.ONE
			))
			var lounger_pos := beach_pos + Vector3(1.25, 0.0, 0.45)
			lounger_pos.y = height_at(lounger_pos.x, lounger_pos.z) + 0.22
			beach_lounger_transforms.append(make_transform(lounger_pos, PI * 0.5, Vector3(0.65, 0.18, 1.8)))

	_add_multimesh(root, umbrella_pole_mesh, metal, beach_pole_transforms, "BeachUmbrellaPoles", false)
	for beach_group in 4:
		_add_multimesh(root, umbrella_canopy_mesh, beach_materials[beach_group], beach_canopy_transforms[beach_group], "BeachUmbrellas_%d" % beach_group, false)
	_add_multimesh(root, unit_box, white_painted, beach_lounger_transforms, "BeachLoungers", false)
	_enhancement_stats["beach_props"] = beach_pole_transforms.size() + beach_lounger_transforms.size()

	# The marina channel west of the Corniche was previously just a flat
	# water strip.  A wooden dock, fingers and simple sailboats make the
	# district read correctly from the road at almost no triangle cost.
	var dock_transforms: Array = []
	dock_transforms.append(make_transform(Vector3(889.0, 0.38, 270.0), 0.0, Vector3(3.0, 0.28, 205.0)))
	for dock_z in range(176, 365, 24):
		dock_transforms.append(make_transform(Vector3(862.0, 0.32, float(dock_z)), 0.0, Vector3(54.0, 0.24, 2.4)))
	var hull_transforms: Array = []
	var hull_stripe_transforms: Array = []
	var cabin_transforms: Array = []
	var boat_mast_transforms: Array = []
	var boat_sail_transforms: Array = []
	var boat_index := 0
	for boat_z in range(184, 361, 22):
		var boat_pos := Vector3(848.0 if boat_index % 2 == 0 else 874.0, 0.0, float(boat_z))
		hull_transforms.append(make_transform(boat_pos + Vector3(0.0, 0.28, 0.0), 0.0, Vector3(2.3, 0.75, 7.2)))
		hull_stripe_transforms.append(make_transform(boat_pos + Vector3(0.0, 0.62, 0.0), 0.0, Vector3(2.36, 0.18, 7.25)))
		cabin_transforms.append(make_transform(boat_pos + Vector3(0.0, 0.98, 0.45), 0.0, Vector3(1.5, 0.75, 2.1)))
		boat_mast_transforms.append(make_transform(boat_pos + Vector3(0.0, 4.15, -0.25), 0.0, Vector3.ONE))
		boat_sail_transforms.append(make_transform(boat_pos + Vector3(0.0, 1.22, -0.25), PI * 0.5, Vector3(3.0, 4.8, 0.10)))
		boat_index += 1
	_add_multimesh(root, unit_box, wood, dock_transforms, "MarinaDocks", false)
	_add_multimesh(root, unit_box, white_painted, hull_transforms, "MarinaBoatHulls", false)
	_add_multimesh(root, unit_box, boat_blue, hull_stripe_transforms, "MarinaBoatStripes", false)
	_add_multimesh(root, unit_box, white_painted, cabin_transforms, "MarinaBoatCabins", false)
	_add_multimesh(root, mast_mesh, metal, boat_mast_transforms, "MarinaBoatMasts", false)
	_add_multimesh(root, _get_sail_mesh(), white_painted, boat_sail_transforms, "MarinaBoatSails", false)
	_enhancement_stats["marina_boats"] = hull_transforms.size()
	_enhancement_stats["marina_docks"] = dock_transforms.size()


func _build_reflection_probes() -> void:
	_reflection_probes.clear()
	var root := Node3D.new()
	root.name = "ReflectionProbes"
	add_child(root)
	# 0.2.15: keep the tall-probe coverage introduced for the 148 m
	# flagship, but stop stacking a second standard probe underneath
	# each tall one. Six district probes (two tall) cover the same
	# shoreline/downtown/islands with fewer overlapping cubemap blends
	# on every reflective fragment.
	var probe_specs: Array[Dictionary] = [
		{"centre": Vector3(680.0, 0.0, -300.0), "height": 56.0, "size": Vector3(320.0, 150.0, 320.0), "capture": 24.0, "tall": false},
		{"centre": Vector3(940.0, 0.0, 0.0), "height": 44.0, "size": Vector3(320.0, 120.0, 320.0), "capture": 20.0, "tall": false},
		{"centre": Vector3(1180.0, 0.0, 80.0), "height": 44.0, "size": Vector3(320.0, 120.0, 320.0), "capture": 20.0, "tall": false},
		{"centre": Vector3(1340.0, 0.0, -250.0), "height": 50.0, "size": Vector3(320.0, 140.0, 320.0), "capture": 22.0, "tall": false},
		{"centre": Vector3(712.0, 0.0, -118.0), "height": 86.0, "size": Vector3(320.0, 205.0, 320.0), "capture": 30.0, "tall": true},
		{"centre": Vector3(762.0, 0.0, 188.0), "height": 58.0, "size": Vector3(320.0, 160.0, 320.0), "capture": 24.0, "tall": true},
	]
	var tall_probe_count := 0
	for spec in probe_specs:
		var centre: Vector3 = spec.get("centre", Vector3.ZERO)
		var probe_height := float(spec.get("height", 24.0))
		var capture_height := float(spec.get("capture", 12.0))
		var probe := ReflectionProbe.new()
		probe.name = "TallDistrictReflection" if bool(spec.get("tall", false)) else "DistrictReflection"
		probe.position = Vector3(centre.x, height_at(centre.x, centre.z) + probe_height, centre.z)
		probe.size = spec.get("size", Vector3(320.0, 150.0, 320.0))
		probe.blend_distance = 52.0
		probe.origin_offset = Vector3(0.0, capture_height - probe_height, 0.0)
		probe.box_projection = true
		probe.enable_shadows = false
		# Slightly lifted reflection energy makes car clearcoat and curtain-wall
		# windows read their local cubemap, while the tall probes stay balanced.
		probe.intensity = 1.24
		probe.max_distance = 240.0
		probe.mesh_lod_threshold = 0.65
		probe.ambient_mode = ReflectionProbe.AMBIENT_ENVIRONMENT
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		# Слои 1-19: слой 20 зарезервирован под камеру SpeedPost и не должен
		# попадать в захват отражений.
		probe.cull_mask = (1 << 19) - 1
		root.add_child(probe)
		_reflection_probes.append(probe)
		if bool(spec.get("tall", false)):
			tall_probe_count += 1
	_enhancement_stats["reflection_probes"] = _reflection_probes.size()
	_enhancement_stats["tall_reflection_probes"] = tall_probe_count
	_enhancement_stats["reflection_probe_max_distance"] = 240.0
	_enhancement_stats["reflection_probe_box_projection"] = true
	_enhancement_stats["reflection_probe_intensity"] = 1.24


func _build_benches() -> void:
	var root := Node3D.new()
	root.name = "Benches"
	add_child(root)
	var wood := _prop_material("PropsWood")
	var metal := _prop_material("PropsMetal")
	for bench_variant in data.get("benches", []):
		var bench: Dictionary = bench_variant
		var position_value := _item_position(bench)
		var yaw := _f(bench, "rotY")
		var bench_basis := Basis(Vector3.UP, yaw)
		var seat_offset := bench_basis * Vector3(0.0, 0.48, 0.0)
		_add_box(root, Vector3(2.25, 0.16, 0.62), position_value + seat_offset, wood, yaw, "BenchSeat")
		var back_offset := bench_basis * Vector3(0.0, 0.92, -0.28)
		_add_box(root, Vector3(2.25, 0.55, 0.12), position_value + back_offset, wood, yaw, "BenchBack")
		for side in [-0.9, 0.9]:
			var leg_offset := bench_basis * Vector3(side, 0.24, 0.0)
			_add_box(root, Vector3(0.12, 0.48, 0.55), position_value + leg_offset, metal, yaw, "BenchLeg")
		_add_box_collider(position_value + Vector3(0.0, 0.55, 0.0), Vector3(2.3, 1.1, 0.8), yaw)


func _build_world_bounds() -> void:
	var bounds: Dictionary = data.get("bounds", {})
	var min_x := _f(bounds, "minX", 520.0)
	var max_x := _f(bounds, "maxX", 1500.0)
	var min_z := _f(bounds, "minZ", -500.0)
	var max_z := _f(bounds, "maxZ", 500.0)
	var center_x := (min_x + max_x) * 0.5
	var center_z := (min_z + max_z) * 0.5
	_add_box_collider(Vector3(min_x - 3.0, 24.0, center_z), Vector3(6.0, 60.0, max_z - min_z + 12.0))
	_add_box_collider(Vector3(max_x + 3.0, 24.0, center_z), Vector3(6.0, 60.0, max_z - min_z + 12.0))
	_add_box_collider(Vector3(center_x, 24.0, min_z - 3.0), Vector3(max_x - min_x + 12.0, 60.0, 6.0))
	_add_box_collider(Vector3(center_x, 24.0, max_z + 3.0), Vector3(max_x - min_x + 12.0, 60.0, 6.0))
	_add_box_collider(Vector3(center_x, -6.5, center_z), Vector3(max_x - min_x + 80.0, 2.0, max_z - min_z + 80.0))
