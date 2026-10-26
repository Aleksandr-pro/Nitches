class_name NativeWorldBuilder
extends Node3D

## Builds the first native RichTown district from engine-neutral JSON data.
## All runtime geometry, materials, collision and lighting are created by
## Godot itself.  The world uses real metres and keeps the legacy data
## coordinates (x 520..1500, z -500..500) so later streaming chunks can use
## exactly the same placement data.

const WORLD_DATA_PATH := "res://data/richtown_native.json"
const DynamicWorldScript := preload("res://scripts/dynamic_world.gd")
const TEXTURE_DIR := "res://assets/textures/"
const WORLD_AABB := AABB(Vector3(500.0, -20.0, -540.0), Vector3(1040.0, 420.0, 1080.0))
const FALLBACK_SPAWN_POSITION := Vector3(760.0, 5.205, 330.0)

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
var _water_materials: Array[StandardMaterial3D] = []
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
var _reflection_probes: Array[ReflectionProbe] = []
var _enhancement_stats: Dictionary = {}
var _reflection_probe_refresh_sign := 1.0
var _gable_mesh: ArrayMesh
var _palm_crown_mesh: ArrayMesh
var _sail_mesh: ArrayMesh
var _elapsed := 0.0


func _process(delta: float) -> void:
	_elapsed += delta
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


func _build_road_surface_index() -> void:
	_road_segment_starts.clear()
	_road_segment_ends.clear()
	_road_segment_half_widths.clear()
	for road_variant in data.get("roads", []):
		var road: Dictionary = road_variant
		var samples: Array = road.get("samples", [])
		var half_width := _f(road, "widthM", 10.0) * 0.5
		for i in range(samples.size() - 1):
			var a := _sample_point(samples[i])
			var b := _sample_point(samples[i + 1])
			if Vector2(b.x - a.x, b.z - a.z).length_squared() < 0.0001:
				continue
			_road_segment_starts.append(a)
			_road_segment_ends.append(b)
			_road_segment_half_widths.append(half_width)


func _distance_to_segment_xz(point: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(point.x - a.x, point.z - a.z)
	var length_squared := ab.length_squared()
	if length_squared <= 0.0001:
		return ap.length()
	var t := clampf(ap.dot(ab) / length_squared, 0.0, 1.0)
	return ap.distance_to(ab * t)


func _road_clearance_xz(point: Vector3) -> float:
	var best_clearance := INF
	for i in _road_segment_starts.size():
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
	_sky.radiance_size = Sky.RADIANCE_SIZE_512

	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = _sky
	_environment.sky_custom_fov = 0.0
	_environment.sky_rotation = Vector3.ZERO
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_environment.ambient_light_sky_contribution = 0.88
	_environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	_environment.glow_enabled = true
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
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_max_distance = 520.0
	_sun.directional_shadow_split_1 = 0.055
	_sun.directional_shadow_split_2 = 0.16
	_sun.directional_shadow_split_3 = 0.42
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
	match kind:
		"sand":
			return _material("terrain_sand", "user_sand_rippled.jpg", "user_sand_rippled_normal.jpg", Color(1.03, 0.96, 0.82), 0.98)
		"concrete":
			return _material("terrain_concrete", "user_concrete_slabs.jpg", "user_concrete_slabs_normal.jpg", Color(0.86, 0.87, 0.86), 0.94)
		"rock":
			return _material("terrain_rock", "rock.jpg", "rock_normal.jpg", Color(0.82, 0.80, 0.76), 1.0)
		_:
			return _material("terrain_grass", "user_grass.jpg", "user_grass_normal.jpg", Color(0.92, 1.0, 0.82), 0.98)


func _facade_material(facade: String, height: float) -> StandardMaterial3D:
	var albedo := "user_plaster_white.jpg"
	var normal := "user_plaster_white_normal.jpg"
	var roughness := 0.88
	var metallic := 0.0
	var glassy := false
	match facade:
		"glassTower":
			albedo = "user_facade_blue_glass.jpg"
			normal = "user_facade_blue_glass_normal.jpg"
			roughness = 0.16
			metallic = 0.08
			glassy = true
		"goldTower":
			albedo = "user_facade_gold_grid.jpg"
			normal = "user_facade_gold_grid_normal.jpg"
			roughness = 0.29
			metallic = 0.34
			glassy = true
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

	var tier := 0 if height < 18.0 else (1 if height < 52.0 else 2)
	var key := "facade_%s_%d" % [facade, tier]
	var material := _material(
		key,
		albedo,
		normal,
		Color.WHITE,
		roughness,
		metallic,
		Vector3(0.052, 0.047 + float(tier) * 0.006, 0.052),
		true
	)
	material.metallic_specular = 0.92 if glassy else 0.58
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


func _prop_material(material_name: String) -> StandardMaterial3D:
	match material_name:
		"FacadeMain":
			return _material("prop_facade_main", "user_plaster_white.jpg", "user_plaster_white_normal.jpg", Color.WHITE, 0.9)
		"FacadeAccent":
			return _material("prop_facade_accent", "user_travertine.jpg", "user_travertine_normal.jpg", Color.WHITE, 0.84)
		"FacadeGlass":
			var glass := _material("prop_facade_glass", "user_facade_blue_glass.jpg", "user_facade_blue_glass_normal.jpg", Color(0.78, 0.92, 1.05), 0.11, 0.08, Vector3(2.5, 5.0, 1.0))
			glass.metallic_specular = 1.0
			glass.emission_enabled = true
			glass.emission = Color(1.0, 0.76, 0.48)
			glass.emission_texture = glass.albedo_texture
			_register_night_material(glass, 0.0, 0.1, 0.42)
			return glass
		"PropsGlass":
			var panes := _material("prop_glass", "", "", Color(0.58, 0.82, 0.94, 0.58), 0.08, 0.35)
			panes.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			panes.emission_enabled = true
			panes.emission = Color(1.0, 0.78, 0.52)
			_register_night_material(panes, 0.0, 0.06, 0.24)
			return panes
		"PropsMetal":
			return _material("prop_metal", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.72, 0.76, 0.80), 0.38, 0.78)
		"PropsWood":
			return _material("prop_wood", "user_wood_deck.jpg", "user_wood_deck_normal.jpg", Color.WHITE, 0.86)
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
	if _in_zone(x, z, "rtPlaza"):
		return "concrete"
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
	for kind in ["grass", "sand", "concrete", "rock"]:
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
			for vertex in [p00, p11, p10, p00, p01, p11]:
				_terrain_vertex(tool, vertex)

	var terrain_root := Node3D.new()
	terrain_root.name = "Terrain"
	add_child(terrain_root)
	for kind in tools.keys():
		var tool := tools[kind] as SurfaceTool
		tool.index()
		tool.generate_normals()
		tool.generate_tangents()
		var mesh := tool.commit()
		if mesh != null:
			_mesh_instance(terrain_root, mesh, _terrain_material(String(kind)), Transform3D.IDENTITY, "Terrain_%s" % String(kind), false)

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


func _water_material() -> StandardMaterial3D:
	var material := _material(
		"water_sea",
		"user_water_turquoise.jpg",
		"user_water_turquoise_normal.jpg",
		Color(0.20, 0.72, 0.86, 0.80),
		0.055,
		0.0,
		Vector3(90.0, 120.0, 1.0)
	)
	material.normal_scale = 1.22
	material.metallic_specular = 1.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if not _water_materials.has(material):
		_water_materials.append(material)
	return material


func _pool_material() -> StandardMaterial3D:
	var material := _material(
		"water_pool",
		"user_pool_mosaic.jpg",
		"user_pool_mosaic_normal.jpg",
		Color(0.46, 0.90, 1.0, 0.92),
		0.11,
		0.0,
		Vector3(2.0, 2.0, 1.0)
	)
	material.normal_scale = 0.92
	material.metallic_specular = 0.92
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(0.25, 0.72, 0.88)
	_register_night_material(material, 0.0, 0.08, 0.34)
	if not _water_materials.has(material):
		_water_materials.append(material)
	return material


func _build_water_and_pools() -> void:
	var water_root := Node3D.new()
	water_root.name = "Water"
	add_child(water_root)

	var sea_mesh := PlaneMesh.new()
	sea_mesh.size = Vector2(760.0, 1040.0)
	sea_mesh.subdivide_width = 24
	sea_mesh.subdivide_depth = 24
	var sea := _mesh_instance(water_root, sea_mesh, _water_material(), make_transform(Vector3(1145.0, 0.04, 0.0)), "SeaAndMarina", false)
	sea.custom_aabb = WORLD_AABB

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
	tool.set_normal(Vector3.UP)
	tool.set_uv(uv)
	tool.add_vertex(position_value)


func _build_road_mesh(extra_width: float, y_offset: float, uv_distance: float) -> ArrayMesh:
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
		var distance := 0.0
		var left_points: Array[Vector3] = []
		var right_points: Array[Vector3] = []
		var distances: Array[float] = []
		for i in points.size():
			if i > 0:
				distance += points[i].distance_to(points[i - 1])
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
			right_points.append(center + side * half_width)
			distances.append(distance)
		for i in range(points.size() - 1):
			var l0 := left_points[i]
			var r0 := right_points[i]
			var l1 := left_points[i + 1]
			var r1 := right_points[i + 1]
			var v0 := distances[i] / uv_distance
			var v1 := distances[i + 1] / uv_distance
			_road_vertex(tool, l0, Vector2(0.0, v0))
			_road_vertex(tool, r1, Vector2(1.0, v1))
			_road_vertex(tool, l1, Vector2(0.0, v1))
			_road_vertex(tool, l0, Vector2(0.0, v0))
			_road_vertex(tool, r0, Vector2(1.0, v0))
			_road_vertex(tool, r1, Vector2(1.0, v1))
	tool.index()
	tool.generate_tangents()
	return tool.commit()


func _build_roads() -> void:
	var roads_root := Node3D.new()
	roads_root.name = "Roads"
	add_child(roads_root)

	var sidewalk_material := _material("sidewalk", "user_concrete_slabs.jpg", "user_concrete_slabs_normal.jpg", Color(0.78, 0.79, 0.78), 0.96)
	sidewalk_material.normal_scale = 0.9
	var sidewalk_mesh := _build_road_mesh(1.9, 0.035, 7.0)
	if sidewalk_mesh != null:
		var sidewalks := _mesh_instance(roads_root, sidewalk_mesh, sidewalk_material, Transform3D.IDENTITY, "Sidewalks", false)
		sidewalks.custom_aabb = WORLD_AABB

	var asphalt_material := _material("asphalt", "user_asphalt_dashed.jpg", "user_asphalt_dashed_normal.jpg", Color(0.74, 0.76, 0.78), 0.68, 0.0)
	asphalt_material.normal_scale = 1.14
	asphalt_material.metallic_specular = 0.42
	var road_mesh := _build_road_mesh(0.0, 0.075, 18.0)
	if road_mesh != null:
		var roads := _mesh_instance(roads_root, road_mesh, asphalt_material, Transform3D.IDENTITY, "Asphalt", false)
		roads.custom_aabb = WORLD_AABB

	_build_road_markings(roads_root)
	_build_bridge_guardrails(roads_root)


func _build_road_markings(parent: Node) -> void:
	var stripe_transforms: Array[Transform3D] = []
	var vertical_roads := [
		{"x": 560.0, "width": 11.0},
		{"x": 760.0, "width": 22.0},
		{"x": 930.0, "width": 24.0},
	]
	var cross_z := [-300.0, -250.0, -110.0, 60.0, 225.0]
	var cross_width := 13.0

	for vertical_variant in vertical_roads:
		var vertical: Dictionary = vertical_variant
		var center_x := float(vertical.get("x", 760.0))
		var width := float(vertical.get("width", 12.0))
		for z_variant in cross_z:
			var center_z := float(z_variant)
			# Zebra crossings on both approaches to the vertical road.
			for side in [-1.0, 1.0]:
				var crossing_z: float = center_z + float(side) * (cross_width * 0.5 + 2.35)
				var stripe_count := maxi(int(floor((width - 1.4) / 1.08)), 3)
				var start_x := center_x - float(stripe_count - 1) * 0.54
				for i in stripe_count:
					var x := start_x + float(i) * 1.08
					var y := height_at(x, crossing_z) + 0.165
					stripe_transforms.append(make_transform(Vector3(x, y, crossing_z), 0.0, Vector3(0.58, 0.028, 3.15)))
				var stop_z: float = crossing_z + float(side) * 2.15
				stripe_transforms.append(make_transform(
					Vector3(center_x + width * 0.25, height_at(center_x, stop_z) + 0.165, stop_z),
					0.0,
					Vector3(width * 0.48, 0.028, 0.42)
				))

			# Matching zebras across the horizontal street.
			for side in [-1.0, 1.0]:
				var crossing_x: float = center_x + float(side) * (width * 0.5 + 2.35)
				var stripe_count_h := maxi(int(floor((cross_width - 1.4) / 1.08)), 3)
				var start_z := center_z - float(stripe_count_h - 1) * 0.54
				for i in stripe_count_h:
					var z := start_z + float(i) * 1.08
					var y := height_at(crossing_x, z) + 0.165
					stripe_transforms.append(make_transform(Vector3(crossing_x, y, z), 0.0, Vector3(3.15, 0.028, 0.58)))
				var stop_x: float = crossing_x + float(side) * 2.15
				stripe_transforms.append(make_transform(
					Vector3(stop_x, height_at(stop_x, center_z) + 0.165, center_z - cross_width * 0.25),
					0.0,
					Vector3(0.42, 0.028, cross_width * 0.48)
				))

	var paint := _material("road_paint", "", "", Color(0.88, 0.90, 0.88), 0.74)
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3.ONE
	stripe_mesh.material = paint
	_add_multimesh(parent, stripe_mesh, paint, stripe_transforms, "CrosswalksAndStopLines", false)
	_enhancement_stats["road_markings"] = stripe_transforms.size()


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
		var mesh := tool.commit()
		if mesh != null:
			parts.append({
				"mesh": mesh,
				"material": _prop_material(material_name),
				"material_name": material_name,
			})
	_model_parts_cache[path] = parts
	return parts


func _add_multimesh(parent: Node, mesh: Mesh, material: Material, transforms: Array, node_name: String, cast_shadow: bool = true) -> bool:
	if mesh == null or transforms.is_empty():
		return false
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = false
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i] as Transform3D)

	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multi
	if material != null:
		instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	instance.custom_aabb = WORLD_AABB
	parent.add_child(instance)
	return true


func _add_batched_model(parent: Node, path: String, transforms: Array, node_name: String) -> bool:
	if transforms.is_empty():
		return false
	var parts := _get_model_parts(path)
	if parts.is_empty():
		return false
	var model_root := Node3D.new()
	model_root.name = node_name
	parent.add_child(model_root)
	var built_any := false
	for part_variant in parts:
		var part: Dictionary = part_variant
		built_any = _add_multimesh(
			model_root,
			part.get("mesh") as Mesh,
			part.get("material") as Material,
			transforms,
			String(part.get("material_name", "Part")),
			true
		) or built_any
	return built_any


func _centered_model_transform(position_value: Vector3, yaw: float, scale_value: Vector3, source_center: Vector3) -> Transform3D:
	return make_transform(position_value, yaw, scale_value) * Transform3D(Basis.IDENTITY, -source_center)


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
			villa_items.append(building)
			villa_transforms.append(_centered_model_transform(
				position_value,
				yaw,
				Vector3(w / 19.15, total_height / 7.90, d / 15.14),
				Vector3(-0.325, 0.0, -0.23)
			))
			_add_box_collider(position_value + Vector3(0.0, h * 0.5, 0.0), Vector3(w, h + roof_h, d), yaw)
		elif model == "glass_tower":
			tower_items.append(building)
			tower_transforms.append(make_transform(
				position_value,
				yaw,
				Vector3(w / 33.60, h / 70.71, d / 33.60)
			))
			_add_box_collider(position_value + Vector3(0.0, h * 0.5, 0.0), Vector3(w, h, d), yaw)
		elif kind == "rt-villa" and w <= 29.0 and d <= 22.0 and total_height <= 13.0:
			townhouse_items.append(building)
			townhouse_transforms.append(_centered_model_transform(
				position_value,
				yaw,
				Vector3(w / 13.15, total_height / 9.99, d / 13.40),
				Vector3(0.075, 0.0, 1.075)
			))
			_add_box_collider(position_value + Vector3(0.0, h * 0.5, 0.0), Vector3(w, h + roof_h, d), yaw)
		elif kind == "rt-hotel" and h >= 15.0 and h <= 38.0 and w <= 55.0 and d <= 38.0:
			hero_items.append(building)
			hero_transforms.append(make_transform(
				position_value,
				yaw,
				Vector3(w / 24.50, h / 18.40, d / 18.20)
			))
			_add_box_collider(position_value + Vector3(0.0, h * 0.5, 0.0), Vector3(w, h, d), yaw)
		else:
			_add_generic_building(buildings_root, building)

	if not _add_batched_model(buildings_root, "res://assets/buildings/villa.glb", villa_transforms, "BlenderVillas"):
		for item in villa_items:
			_add_generic_building(buildings_root, item)
	if not _add_batched_model(buildings_root, "res://assets/buildings/glass_tower.glb", tower_transforms, "BlenderGlassTowers"):
		for item in tower_items:
			_add_generic_building(buildings_root, item)
	if not _add_batched_model(buildings_root, "res://assets/buildings/townhouse.glb", townhouse_transforms, "BlenderTownhouses"):
		for item in townhouse_items:
			_add_generic_building(buildings_root, item)
	if not _add_batched_model(buildings_root, "res://assets/buildings/hero_building.glb", hero_transforms, "BlenderHeroBuildings"):
		for item in hero_items:
			_add_generic_building(buildings_root, item)
	_enhancement_stats["townhouse_models"] = townhouse_transforms.size()
	_enhancement_stats["hero_building_models"] = hero_transforms.size()


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
	var vertices: Array[Vector3] = [
		a, b, c,
		b2, a2, c2,
		a, a2, b2, a, b2, b,
		b, b2, c2, b, c2, c,
		c, c2, a2, c, a2, a,
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
				var transform_value := make_transform(pos, 0.0, Vector3(38.0 / 30.0, h / 66.0, 38.0 / 30.0))
				if not _add_batched_model(root, "res://assets/buildings/glass_tower.glb", [transform_value], "Main148mTower"):
					_add_box(root, Vector3(38.0, h, 38.0), pos + Vector3(0.0, h * 0.5, 0.0), glass)
				_add_box_collider(pos + Vector3(0.0, h * 0.5, 0.0), Vector3(38.0, h, 38.0))
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
				_plant_parts[part_name] = {
					"mesh": mesh_instance.mesh,
					"material": _prop_material(material_name),
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


func _palm_leaf_material() -> StandardMaterial3D:
	var material := _material("palm_leaf", "user_palm_leaf.png", "", Color(0.72, 0.96, 0.62), 1.0)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.32
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


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
		for z in range(-390, 391, 65):
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
		for z in range(-390, 391, 65):
			var candidate: Vector3 = Vector3(912.0, height_at(912.0, float(z)), float(z))
			if _is_position_clear(candidate, 2.0, 4.0):
				trees.append({"x": candidate.x, "y": candidate.y, "z": candidate.z, "rotY": float(promenade_index) * 0.71, "s": 0.84 + float(promenade_index % 3) * 0.07, "type": "oak"})
				extra_tree_count += 1
			promenade_index += 1
		var boulevard_index := 0
		for z in range(-380, 386, 85):
			for x in [738.0, 782.0]:
				var candidate := Vector3(x, height_at(x, float(z)), float(z))
				if _is_position_clear(candidate, 2.0, 4.0):
					trees.append({"x": candidate.x, "y": candidate.y, "z": candidate.z, "rotY": float(boulevard_index) * 0.93, "s": 0.82 + float(boulevard_index % 4) * 0.06, "type": "oak"})
					extra_tree_count += 1
				boulevard_index += 1

		# Deterministic hillside woodland.  Candidates are rejected on
		# roads, landmarks, steep/underwater terrain and building plots.
		var hill_ix := 0
		for base_x in range(970, 1241, 34):
			var hill_iz := 0
			for base_z in range(-470, 471, 38):
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
				_add_multimesh(root, part.get("mesh") as Mesh, part.get("material") as Material, tree_transforms, part_name)

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
				_add_multimesh(root, part.get("mesh") as Mesh, part.get("material") as Material, bush_transforms[part_name], String(part_name))

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.15
	trunk_mesh.bottom_radius = 0.29
	trunk_mesh.height = 5.8
	trunk_mesh.radial_segments = 10
	var trunk_transforms: Array[Transform3D] = []
	var crown_transforms: Array[Transform3D] = []
	for palm_variant in data.get("palms", []):
		var palm: Dictionary = palm_variant
		var scale_value := _f(palm, "s", 1.0)
		var base := _item_position(palm)
		trunk_transforms.append(make_transform(base + Vector3(0.0, 2.9 * scale_value, 0.0), _f(palm, "rotY"), Vector3.ONE * scale_value))
		crown_transforms.append(make_transform(base + Vector3(0.0, 5.72 * scale_value, 0.0), _f(palm, "rotY") * 1.7, Vector3.ONE * scale_value))
		_add_cylinder_collider(base + Vector3(0.0, 2.5, 0.0), 0.30, 5.2)
	_add_multimesh(root, trunk_mesh, _prop_material("nh_bark"), trunk_transforms, "PalmTrunks")
	_add_multimesh(root, _get_palm_crown_mesh(), _palm_leaf_material(), crown_transforms, "PalmCrowns")


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


func _build_reflection_probes() -> void:
	_reflection_probes.clear()
	var root := Node3D.new()
	root.name = "ReflectionProbes"
	add_child(root)
	for centre in [
		Vector3(720.0, 0.0, 0.0),
		Vector3(680.0, 0.0, -300.0),
		Vector3(720.0, 0.0, 330.0),
		Vector3(940.0, 0.0, 0.0),
		Vector3(1180.0, 0.0, 80.0),
		Vector3(1340.0, 0.0, -250.0),
	]:
		var probe := ReflectionProbe.new()
		probe.name = "DistrictReflection"
		probe.position = Vector3(centre.x, height_at(centre.x, centre.z) + 12.0, centre.z)
		probe.size = Vector3(300.0, 110.0, 300.0)
		probe.blend_distance = 45.0
		probe.origin_offset = Vector3(0.0, -4.0, 0.0)
		probe.box_projection = true
		probe.enable_shadows = false
		probe.intensity = 1.12
		probe.max_distance = 450.0
		probe.mesh_lod_threshold = 0.35
		probe.ambient_mode = ReflectionProbe.AMBIENT_ENVIRONMENT
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		# Слои 1-19: слой 20 зарезервирован под камеру SpeedPost и не должен
		# попадать в захват отражений.
		probe.cull_mask = (1 << 19) - 1
		root.add_child(probe)
		_reflection_probes.append(probe)
	_enhancement_stats["reflection_probes"] = _reflection_probes.size()


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
