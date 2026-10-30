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
const ConcreteSurfaceShader: Shader = preload("res://shaders/concrete_surface.gdshader")
const PremiumStonePavingShader: Shader = preload("res://shaders/premium_stone_paving.gdshader")
const HorizonSkylineShader: Shader = preload("res://shaders/horizon_skyline.gdshader")
const TEXTURE_DIR := "res://assets/textures/"
const WORLD_AABB := AABB(Vector3(500.0, -20.0, -540.0), Vector3(1040.0, 420.0, 1080.0))
## 0.2.47 second world: ``world_id`` selects the data file and build
## path ("richtown" default, "desert"); ``_active_aabb`` is the world
## bounds every generic system (road/foliage grids, streaming cells,
## terrain culling) must use instead of the RichTown constant.
var world_id := "richtown"
var _is_desert := false
var _is_forest := false
var _gf_field_rects: Array[Rect2] = []
var _gf_lake_y := 0.0
var _gf_bird_flocks: Array[Dictionary] = []
var _gf_leaf_emitter: GPUParticles3D
var _stream_focus_pos := Vector3.ZERO
var _gf_scatter_total_acc := 0
var _gf_scatter_trees_acc := 0
var _active_aabb := WORLD_AABB
const FALLBACK_SPAWN_POSITION := Vector3(760.0, 5.205, 330.0)
const MULTIMESH_CHUNK_SIZE_M := 220.0
const STREAM_CELL_M := 64.0
# 0.2.44: foliage density queries (atmosphere shafts, rustle audio)
# run against a build-time spatial grid instead of scanning every
# vegetation point on each sample.
const FOLIAGE_GRID_CELL_M := 55.0
const COLLIDER_ACTIVE_RADIUS_M := 150.0
const COLLIDER_RELEASE_RADIUS_M := 175.0
const STREAM_HIDE_BEHIND_M := 85.0
const STREAM_SHOW_BEHIND_M := 68.0
## 0.2.37 view-sector streaming: the 0.2.30 pass only retired chunks
## behind the camera.  A chunk whose whole bounding sphere is also
## outside the *side* of the horizontal view cone cannot contribute a
## pixel either, so it is retired with a wide safety margin while
## everything inside the view direction keeps its full detail.
const STREAM_SECTOR_HIDE_MARGIN_RAD := 0.34
const STREAM_SECTOR_SHOW_MARGIN_RAD := 0.18
const SAIL_ISLAND_CENTRE := Vector2(1185.0, 80.0)
const SAIL_ISLAND_RADII := Vector2(132.0, 108.0)
const ROAD_GRID_CELL_M := 40.0
const ROAD_GRID_QUERY_CLEARANCE_M := 10.0
const ROAD_SURFACE_OFFSET_M := 0.095
const ROAD_CROWN_M := 0.045

## 0.2.22 designed parks (see _build_parks).  Rects use Rect2 with the
## second axis as world Z.  The same table drives terrain class,
## infill exclusion, ground-cover exclusion and the minimap, so the
## parks stay consistent everywhere.
const PARK_SPECS := [
	{
		"id": "central",
		"label": "RichTown Central Park",
		"rect": Rect2(580.0, -98.0, 100.0, 146.0),
		"axis_x": 630.0,
		"axis_z": 23.0,
		"axis_half": 4.0,
		"focal": Vector2(665.0, -25.0),
		"focal_radius": 19.0,
		"focal_kind": "fountain",
		"perimeter": "oak",
		"alleys": "both",
		"extra_paths": [Rect2(659.0, -9.0, 12.0, 32.0)],
		"diagonals": [
			{"a": Vector2(630.0, 23.0), "b": Vector2(592.0, -86.0), "w": 4.5},
			{"a": Vector2(648.0, -38.0), "b": Vector2(592.0, -86.0), "w": 4.0},
			{"a": Vector2(630.0, 23.0), "b": Vector2(594.0, 40.0), "w": 4.0},
		],
		"zones": [
			{"rect": Rect2(586.0, -92.0, 38.0, 62.0), "pattern": "oak_grove"},
			{"rect": Rect2(586.0, -24.0, 38.0, 41.0), "pattern": "parterre"},
			{"rect": Rect2(636.0, -92.0, 38.0, 40.0), "pattern": "palm_grove"},
			{"rect": Rect2(636.0, -47.0, 38.0, 64.0), "pattern": "parterre"},
			{"rect": Rect2(586.0, 29.0, 38.0, 13.0), "pattern": "palm_grove"},
			{"rect": Rect2(636.0, 29.0, 38.0, 13.0), "pattern": "open_lawn"},
		],
	},
	{
		"id": "museum",
		"label": "Museum Garden",
		"rect": Rect2(576.0, -374.0, 64.0, 66.0),
		"axis_x": 608.0,
		"axis_z": -341.0,
		"axis_half": 3.0,
		"focal": Vector2(608.0, -341.0),
		"focal_radius": 8.5,
		"focal_kind": "pergola",
		"perimeter": "oak",
		"alleys": "ew",
		"extra_paths": [Rect2(599.0, -350.0, 18.0, 18.0)],
		"diagonals": [
			{"a": Vector2(608.0, -341.0), "b": Vector2(584.0, -366.0), "w": 3.5},
			{"a": Vector2(608.0, -341.0), "b": Vector2(632.0, -316.0), "w": 3.5},
		],
		"zones": [
			{"rect": Rect2(582.0, -368.0, 22.0, 22.0), "pattern": "parterre"},
			{"rect": Rect2(612.0, -368.0, 22.0, 22.0), "pattern": "oak_grove"},
			{"rect": Rect2(582.0, -336.0, 22.0, 22.0), "pattern": "palm_grove"},
			{"rect": Rect2(612.0, -336.0, 22.0, 22.0), "pattern": "open_lawn"},
		],
	},
	{
		"id": "beach",
		"label": "Corniche Palmetum",
		"rect": Rect2(946.0, -150.0, 60.0, 110.0),
		"axis_x": 976.0,
		"axis_z": -95.0,
		"axis_half": 3.5,
		"focal": Vector2(976.0, -95.0),
		"focal_radius": 10.0,
		"focal_kind": "rondel",
		"perimeter": "palm",
		"alleys": "ns",
		"sea_benches": true,
		"cross_z": [[-122.5, 2.0], [-67.5, 2.0]],
		"extra_paths": [Rect2(964.0, -107.0, 24.0, 24.0)],
		"zones": [
			{"rect": Rect2(952.0, -144.0, 20.0, 19.0), "pattern": "palm_grove"},
			{"rect": Rect2(980.0, -144.0, 20.0, 19.0), "pattern": "open_lawn"},
			{"rect": Rect2(952.0, -120.0, 20.0, 21.0), "pattern": "open_lawn"},
			{"rect": Rect2(980.0, -120.0, 20.0, 21.0), "pattern": "palm_grove"},
			{"rect": Rect2(952.0, -91.0, 20.0, 21.0), "pattern": "palm_grove"},
			{"rect": Rect2(980.0, -91.0, 20.0, 21.0), "pattern": "open_lawn"},
			{"rect": Rect2(952.0, -65.0, 20.0, 19.0), "pattern": "open_lawn"},
			{"rect": Rect2(980.0, -65.0, 20.0, 19.0), "pattern": "palm_grove"},
		],
	},
]

var data: Dictionary = {}
var spawn_transform := Transform3D.IDENTITY
var time_of_day := "day"
var build_error := ""
var is_built := false
var _build_stages: Array[Dictionary] = []
var _build_stage_index := 0
var _build_profile_parts: Array[String] = []
var _build_completed_weight := 0.0
var _build_total_weight := 1.0
var _build_started := false

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
var _road_segment_ids: Array[String] = []
var _road_segment_surfaces: Array[String] = []
var _road_segment_grid: Dictionary = {}
var _road_junction_subsegments_0236 := 0
var _multimesh_chunk_count := 0
var _flat_shadow_free_instances_0237 := 0
var _stream_horizontal_half_fov_rad := 1.05
var _stream_sector_hidden_0237 := 0
var _pending_batched_models: Dictionary = {}
var _far_proxy_sphere_mesh: SphereMesh
var _infill_buildings: Array[Dictionary] = []
var _reflection_probes: Array[ReflectionProbe] = []
var _skyline_root: Node3D
var _skyline_materials: Array[ShaderMaterial] = []
var _foliage_points: Array[Vector3] = []
var _foliage_grid: Dictionary = {}
# 0.2.44 graphics-quality: every MultiMesh chunk that received a
# visibility range registers its base begin/end here so the user
# quality preset can rescale detail distances at runtime.
var _quality_ranged_instances: Array[Dictionary] = []
var _quality_detail_scale := 1.0
var _skyline_scale := 1.0
var _enhancement_stats: Dictionary = {}
var _reflection_probe_refresh_sign := 1.0
var _gable_mesh: ArrayMesh
var _sail_mesh: ArrayMesh
var _elapsed := 0.0
var _stream_chunks: Array[Dictionary] = []
var _collider_cells: Dictionary = {}
var _active_collider_cells: Dictionary = {}
var _streaming_timer := 0.0
var _streaming_initialized := false


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
	if _is_desert or _is_forest:
		_dz_animate(delta)
	if _gf_leaf_emitter != null and is_instance_valid(_gf_leaf_emitter):
		_gf_leaf_emitter.global_position = Vector3(_stream_focus_pos.x, _stream_focus_pos.y + 10.0, _stream_focus_pos.z)


func build_world() -> Dictionary:
	if is_built:
		return get_stats() if build_error.is_empty() else {"error": build_error}
	begin_build_world()
	while not is_built:
		build_world_step()
	if data.is_empty():
		return {"error": build_error}
	return get_stats()


## 0.2.52 staged build: prepare the ordered build steps without
## running them.  Main can execute one step per rendered frame
## behind the branded loading screen, while the synchronous
## build_world() above keeps smoke/screenshot runs deterministic.
func begin_build_world() -> void:
	if is_built or _build_started:
		return
	_build_started = true
	_is_desert = world_id == "desert"
	_is_forest = world_id == "greenforest"
	_active_aabb = DESERT_AABB if (_is_desert or _is_forest) else WORLD_AABB
	_load_data()
	_build_stages.clear()
	_build_stage_index = 0
	_build_profile_parts.clear()
	_build_completed_weight = 0.0
	_build_total_weight = 0.0
	if data.is_empty():
		if build_error.is_empty():
			build_error = "Native world data could not be loaded"
		spawn_transform = make_transform(FALLBACK_SPAWN_POSITION, 0.0, Vector3.ONE)
		_queue_emergency_build_stages()
	else:
		_terrain = data.get("terrain", {})
		if _is_desert:
			_queue_desert_build_stages()
		elif _is_forest:
			_queue_forest_build_stages()
		else:
			_queue_richtown_build_stages()
	if _build_total_weight <= 0.0:
		_build_total_weight = 1.0


func build_world_step() -> Dictionary:
	if is_built:
		_attach_collision_root()
		return get_build_progress_state()
	if not _build_started:
		begin_build_world()
	if _build_stage_index >= _build_stages.size():
		is_built = true
		return get_build_progress_state()
	var stage: Dictionary = _build_stages[_build_stage_index]
	var stage_label := String(stage.get("label", "Строим мир"))
	var stage_weight := float(stage.get("weight", 1.0))
	var callable_variant: Variant = stage.get("callable", Callable())
	var stage_started_msec := Time.get_ticks_msec()
	if callable_variant is Callable:
		var stage_callable: Callable = callable_variant
		if stage_callable.is_valid():
			stage_callable.call()
		elif build_error.is_empty():
			build_error = "Native world build stage is missing: %s" % stage_label
	elif build_error.is_empty():
		build_error = "Native world build stage is invalid: %s" % stage_label
	# 0.2.54 diagnostics: cumulative build profile after every stage.
	# The GreenForest smoke timed out at 600 s in CI and the same wall
	# looked like a mid-loading crash on a phone.  The last flushed
	# line always lists every completed stage with its cost, even if
	# the process is killed inside the next stage.
	_build_profile_parts.append("%s=%dms" % [stage_label, Time.get_ticks_msec() - stage_started_msec])
	print("[native-build] world=%s profile %s" % [world_id, "; ".join(PackedStringArray(_build_profile_parts))])
	if is_built:
		_attach_collision_root()
	_build_stage_index += 1
	_build_completed_weight += maxf(stage_weight, 0.01)
	if _build_stage_index >= _build_stages.size() and not is_built:
		is_built = true
	var state := get_build_progress_state()
	state["completed_stage"] = stage_label
	return state


func get_build_progress_state() -> Dictionary:
	var stage_label := "Мир готов"
	if _build_stage_index < _build_stages.size():
		stage_label = String(_build_stages[_build_stage_index].get("label", stage_label))
	elif _build_stage_index > 0:
		stage_label = String(_build_stages[_build_stage_index - 1].get("label", stage_label))
	var fraction: float = clampf(_build_completed_weight / maxf(_build_total_weight, 0.001), 0.0, 1.0)
	if is_built:
		fraction = 1.0
	return {
		"stage": stage_label,
		"fraction": fraction,
		"finished": is_built,
		"stage_index": _build_stage_index,
		"stage_count": _build_stages.size(),
	}


func is_build_finished() -> bool:
	return is_built


func _add_build_stage(label: String, stage_callable: Callable, weight: float = 1.0) -> void:
	var safe_weight := maxf(weight, 0.01)
	_build_stages.append({"label": label, "callable": stage_callable, "weight": safe_weight})
	_build_total_weight += safe_weight


func _queue_emergency_build_stages() -> void:
	_add_build_stage("Готовим физику мира", Callable(self, "_create_collision_root"), 0.5)
	_add_build_stage("Настраиваем небо и освещение", Callable(self, "_build_environment"), 1.0)
	_add_build_stage("Создаём аварийную площадку", Callable(self, "_build_emergency_spawn_pad"), 0.5)
	_add_build_stage("Рисуем дальний горизонт", Callable(self, "_build_skyline_backdrop"), 0.5)
	_add_build_stage("Завершаем аварийный мир", Callable(self, "_finish_emergency_build"), 0.5)


func _queue_richtown_build_stages() -> void:
	_add_build_stage("Подготавливаем остров Паруса", Callable(self, "_expand_sail_island_0237"), 1.0)
	_add_build_stage("Выбираем точку старта", Callable(self, "_compute_spawn_transform"), 0.3)
	_add_build_stage("Индексируем дороги", Callable(self, "_build_road_surface_index"), 1.0)
	_add_build_stage("Проверяем здания у дорог", Callable(self, "_sanitize_canonical_buildings_0237"), 1.5)
	_add_build_stage("Проверяем бассейны и участки", Callable(self, "_sanitize_canonical_pools_0237"), 0.8)
	_add_build_stage("Готовим физику мира", Callable(self, "_create_collision_root"), 0.3)
	_add_build_stage("Настраиваем небо и освещение", Callable(self, "_build_environment"), 1.0)
	_add_build_stage("Строим ландшафт RichTown", Callable(self, "_build_terrain"), 3.0)
	_add_build_stage("Заполняем море и бассейны", Callable(self, "_build_water_and_pools"), 1.0)
	_add_build_stage("Прокладываем дороги", Callable(self, "_build_roads"), 3.0)
	_add_build_stage("Возводим здания", Callable(self, "_build_buildings"), 4.0)
	_add_build_stage("Строим достопримечательности", Callable(self, "_build_landmarks"), 2.0)
	_add_build_stage("Обустраиваем остров Паруса", Callable(self, "_build_sail_island_resort_0237"), 2.0)
	_add_build_stage("Высаживаем деревья и пальмы", Callable(self, "_build_vegetation"), 3.0)
	_add_build_stage("Добавляем газоны и клумбы", Callable(self, "_build_ground_cover"), 2.0)
	_add_build_stage("Ставим уличные фонари", Callable(self, "_build_street_lamps"), 1.0)
	_add_build_stage("Ставим остановки", Callable(self, "_build_bus_shelters"), 0.5)
	_add_build_stage("Расставляем скамейки", Callable(self, "_build_benches"), 0.5)
	_add_build_stage("Добавляем городские детали", Callable(self, "_build_city_details"), 2.0)
	_add_build_stage("Строим инфраструктуру районов", Callable(self, "_build_district_infrastructure"), 2.0)
	_add_build_stage("Обустраиваем парки", Callable(self, "_build_parks"), 2.0)
	_add_build_stage("Собираем модели города", Callable(self, "_flush_batched_models"), 2.0)
	_add_build_stage("Настраиваем отражения", Callable(self, "_build_reflection_probes"), 1.0)
	_add_build_stage("Закрываем границы мира", Callable(self, "_build_world_bounds"), 0.5)
	_add_build_stage("Рисуем дальний горизонт", Callable(self, "_build_skyline_backdrop"), 1.0)
	_add_build_stage("Финализируем RichTown", Callable(self, "_finish_richtown_build"), 1.0)


func _queue_desert_build_stages() -> void:
	_add_build_stage("Выбираем точку старта", Callable(self, "_compute_spawn_transform"), 0.3)
	_add_build_stage("Индексируем дороги каньона", Callable(self, "_build_road_surface_index"), 1.0)
	_add_build_stage("Готовим физику мира", Callable(self, "_create_collision_root"), 0.3)
	_add_build_stage("Настраиваем небо и освещение", Callable(self, "_build_environment"), 1.0)
	_add_build_stage("Формируем дюны и каньоны", Callable(self, "_build_desert_terrain"), 4.0)
	_add_build_stage("Заполняем озеро оазиса", Callable(self, "_build_desert_water"), 0.5)
	_add_build_stage("Прокладываем трассы и тропы", Callable(self, "_build_desert_roads"), 4.0)
	_add_build_stage("Строим городок и ранчо", Callable(self, "_build_desert_structures"), 3.0)
	_add_build_stage("Наполняем пустыню деталями", Callable(self, "_build_desert_scatter"), 4.0)
	_add_build_stage("Ставим гоночные маркеры", Callable(self, "_build_desert_game_markers"), 1.0)
	_add_build_stage("Собираем модели пустыни", Callable(self, "_flush_batched_models"), 2.0)
	_add_build_stage("Настраиваем отражения", Callable(self, "_build_desert_reflection_probes"), 1.0)
	_add_build_stage("Закрываем границы котловины", Callable(self, "_build_desert_bounds"), 0.5)
	_add_build_stage("Рисуем дальние месы", Callable(self, "_build_desert_skyline"), 1.0)
	_add_build_stage("Финализируем Пустынный каньон", Callable(self, "_finish_desert_build"), 1.0)


func _queue_forest_build_stages() -> void:
	_add_build_stage("Выбираем точку старта", Callable(self, "_compute_spawn_transform"), 0.3)
	_add_build_stage("Индексируем лесные дороги", Callable(self, "_build_road_surface_index"), 1.0)
	_add_build_stage("Готовим физику мира", Callable(self, "_create_collision_root"), 0.3)
	_add_build_stage("Настраиваем небо и освещение", Callable(self, "_build_environment"), 1.0)
	_add_build_stage("Формируем холмы и долины", Callable(self, "_build_forest_terrain"), 4.0)
	_add_build_stage("Заполняем озеро и реку", Callable(self, "_build_forest_water"), 0.5)
	_add_build_stage("Прокладываем дороги и мосты", Callable(self, "_build_desert_roads"), 4.0)
	_add_build_stage("Строим посёлок, ферму и лесопилку", Callable(self, "_build_desert_structures"), 3.0)
	# 0.2.55: scatter is built in three slices so one stage never
	# monopolises a loading frame long enough to trip Android ANR.
	_add_build_stage("Высаживаем лес: деревья", Callable(self, "_gf_scatter_build").bind(["spruce", "pine", "birch", "leafy", "oak", "dead_tree"]), 2.2)
	_add_build_stage("Высаживаем лес: подлесок", Callable(self, "_gf_scatter_build").bind(["bush", "fern", "flower", "mushroom", "stump", "fallen_log", "reed", "grass_tuft"]), 1.0)
	_add_build_stage("Высаживаем лес: камни и поля", Callable(self, "_gf_scatter_build").bind(["hay_bale", "crop_wheat", "crop_corn", "crop_sunflower", "rock_small", "rock_medium", "rock_large"]), 0.8)
	_add_build_stage("Добавляем оленей, птиц и дым", Callable(self, "_build_forest_extras"), 0.5)
	_add_build_stage("Ставим гоночные маркеры", Callable(self, "_build_desert_game_markers"), 1.0)
	_add_build_stage("Собираем модели леса", Callable(self, "_flush_batched_models"), 2.0)
	_add_build_stage("Настраиваем отражения", Callable(self, "_build_forest_reflection_probes"), 1.0)
	_add_build_stage("Закрываем границы леса", Callable(self, "_build_forest_bounds"), 0.5)
	_add_build_stage("Рисуем дальние хребты", Callable(self, "_build_forest_skyline"), 1.0)
	_add_build_stage("Финализируем Зелёный лес", Callable(self, "_finish_forest_build"), 1.0)


func _finish_emergency_build() -> void:
	set_time_of_day("day")
	is_built = true


func _finish_richtown_build() -> void:
	_enhancement_stats["near_field_lod_0243"] = true
	_enhancement_stats["tree_detail_end_m"] = 105.0
	_enhancement_stats["palm_detail_end_m"] = 130.0
	_enhancement_stats["shrub_detail_end_m"] = 90.0
	_enhancement_stats["range_fade_mode"] = "dithered_self"
	_enhancement_stats["wet_asphalt_streaks_0243"] = true
	_enhancement_stats["rich_town_vertical_slice_0243"] = true
	_enhancement_stats["vertical_slice_width_m"] = _active_aabb.size.x
	_enhancement_stats["vertical_slice_depth_m"] = _active_aabb.size.z
	set_time_of_day("day")
	# 0.2.30: register streaming totals and sectorise colliders
	# around the spawn point before the first frame; chunk hiding
	# itself stays off until the reflection probes have captured.
	var collider_total := 0
	for cell_variant in _collider_cells.keys():
		collider_total += (_collider_cells[cell_variant] as Array).size()
	_enhancement_stats["streaming_colliders_total"] = collider_total
	_enhancement_stats["streaming_collider_cells"] = _collider_cells.size()
	# All vegetation points exist by now; bucket them once so density
	# queries stay O(local) on phones (0.2.44).
	_build_foliage_grid()
	_streaming_tick(spawn_transform.origin, -spawn_transform.basis.z, spawn_transform.origin, Vector3.ZERO)
	is_built = true


func _finish_desert_build() -> void:
	_enhancement_stats["desert_world_0247"] = true
	_enhancement_stats["desert_screenshot_audit_0253"] = true
	_enhancement_stats["desert_rock_triplanar_0253"] = true
	_enhancement_stats["desert_scatter_road_audit_0253"] = true
	_enhancement_stats["desert_oasis_deck_0253"] = true
	_enhancement_stats["near_field_lod_0243"] = true
	_enhancement_stats["tree_detail_end_m"] = 105.0
	_enhancement_stats["palm_detail_end_m"] = 130.0
	_enhancement_stats["shrub_detail_end_m"] = 90.0
	_enhancement_stats["range_fade_mode"] = "dithered_self"
	set_time_of_day("day")
	var collider_total := 0
	for cell_variant in _collider_cells.keys():
		collider_total += (_collider_cells[cell_variant] as Array).size()
	_enhancement_stats["streaming_colliders_total"] = collider_total
	_enhancement_stats["streaming_collider_cells"] = _collider_cells.size()
	_build_foliage_grid()
	_streaming_tick(spawn_transform.origin, -spawn_transform.basis.z, spawn_transform.origin, Vector3.ZERO)
	is_built = true


func get_stats() -> Dictionary:
	var stats: Dictionary = data.get("stats", {})
	return stats.duplicate(true)


func get_world_data() -> Dictionary:
	return data


func has_world_data() -> bool:
	return build_error.is_empty() and not data.is_empty()


func get_enhancement_stats() -> Dictionary:
	return _enhancement_stats.duplicate(true)


func _foliage_grid_cell(world_position: Vector3) -> Vector2i:
	return Vector2i(
		floori((world_position.x - _active_aabb.position.x) / FOLIAGE_GRID_CELL_M),
		floori((world_position.z - _active_aabb.position.z) / FOLIAGE_GRID_CELL_M)
	)


## 0.2.44: bucket every foliage point into a 55 m spatial grid once,
## at world build.  Density samples then only distance-check the
## points inside the cells overlapped by the query circle instead of
## the whole vegetation list (atmosphere shafts sample at ~3.6 Hz and
## the rustle-audio gate samples too, including on phones).
func _build_foliage_grid() -> void:
	_foliage_grid.clear()
	for foliage_position in _foliage_points:
		var cell := _foliage_grid_cell(foliage_position)
		if not _foliage_grid.has(cell):
			_foliage_grid[cell] = []
		(_foliage_grid[cell] as Array).append(foliage_position)
	_enhancement_stats["foliage_spatial_grid_0244"] = true
	_enhancement_stats["foliage_grid_cells"] = _foliage_grid.size()
	_enhancement_stats["foliage_points_total"] = _foliage_points.size()
	_enhancement_stats["foliage_grid_cell_m"] = FOLIAGE_GRID_CELL_M


func get_foliage_density_at(world_position: Vector3, radius_m: float = 110.0) -> float:
	var radius_squared := radius_m * radius_m
	var nearby := 0
	if _foliage_grid.is_empty():
		# Only reachable before build_world finishes; keep the exact
		# legacy result as a defensive fallback.
		for foliage_position in _foliage_points:
			var dx := foliage_position.x - world_position.x
			var dz := foliage_position.z - world_position.z
			if dx * dx + dz * dz <= radius_squared:
				nearby += 1
		return clampf(float(nearby) / 9.0, 0.0, 1.0)
	var min_cell := _foliage_grid_cell(world_position - Vector3(radius_m, 0.0, radius_m))
	var max_cell := _foliage_grid_cell(world_position + Vector3(radius_m, 0.0, radius_m))
	for cell_x in range(min_cell.x, max_cell.x + 1):
		for cell_y in range(min_cell.y, max_cell.y + 1):
			var bucket: Array = _foliage_grid.get(Vector2i(cell_x, cell_y), [])
			for foliage_variant in bucket:
				var foliage_position := foliage_variant as Vector3
				var dx := foliage_position.x - world_position.x
				var dz := foliage_position.z - world_position.z
				if dx * dx + dz * dz <= radius_squared:
					nearby += 1
	return clampf(float(nearby) / 9.0, 0.0, 1.0)


## 0.2.44 user graphics quality: rescale every registered detail
## range (foliage HLODs, far proxies) around its shipped base value.
## Begin and end scale together so detailed/proxy handoffs stay in
## sync; instances without a range are untouched.
func set_quality_detail_scale(scale: float) -> void:
	_quality_detail_scale = clampf(scale, 0.3, 3.0)
	for entry in _quality_ranged_instances:
		var instance := entry.get("node") as GeometryInstance3D
		if instance == null or not is_instance_valid(instance):
			continue
		var base_begin := float(entry.get("begin", 0.0))
		var base_end := float(entry.get("end", 0.0))
		if base_begin > 0.0:
			instance.visibility_range_begin = base_begin * _quality_detail_scale
		if base_end > 0.0:
			instance.visibility_range_end = base_end * _quality_detail_scale
	_enhancement_stats["quality_detail_scale_0244"] = _quality_detail_scale
	_enhancement_stats["quality_ranged_instances"] = _quality_ranged_instances.size()


func set_quality_shadow_distance(distance_m: float) -> void:
	var clamped := clampf(distance_m, 60.0, 400.0)
	if _sun != null:
		_sun.directional_shadow_max_distance = clamped
	_enhancement_stats["shadow_max_distance"] = clamped
	_enhancement_stats["quality_shadow_distance_0244"] = clamped


## Uniformly scaling the skyline root keeps the rings' angular size
## identical while letting the camera far plane (and its depth
## precision budget) shrink on the performance preset.
func set_skyline_scale(scale: float) -> void:
	_skyline_scale = clampf(scale, 0.4, 1.5)
	if _skyline_root != null:
		_skyline_root.scale = Vector3.ONE * _skyline_scale
	_enhancement_stats["skyline_scale_0244"] = _skyline_scale


func set_skyline_origin(world_position: Vector3) -> void:
	if _skyline_root != null:
		_skyline_root.global_position = Vector3(world_position.x, 0.0, world_position.z)


func _make_skyline_ring_mesh(radius: float, height: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEGMENTS := 512
	for segment in SEGMENTS:
		var u0 := float(segment) / float(SEGMENTS)
		var u1 := float(segment + 1) / float(SEGMENTS)
		var a0 := TAU * u0
		var a1 := TAU * u1
		var bottom0 := Vector3(sin(a0) * radius, -4.0, cos(a0) * radius)
		var bottom1 := Vector3(sin(a1) * radius, -4.0, cos(a1) * radius)
		var top0 := Vector3(sin(a0) * radius, height, cos(a0) * radius)
		var top1 := Vector3(sin(a1) * radius, height, cos(a1) * radius)
		var vertices: Array[Vector3] = [bottom0, bottom1, top1, bottom0, top1, top0]
		var uvs: Array[Vector2] = [
			Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, 1.0),
			Vector2(u0, 0.0), Vector2(u1, 1.0), Vector2(u0, 1.0),
		]
		for vertex_index in vertices.size():
			surface.set_uv(uvs[vertex_index])
			surface.add_vertex(vertices[vertex_index])
	return surface.commit()


func _build_skyline_backdrop() -> void:
	if _skyline_root != null:
		return
	_skyline_root = Node3D.new()
	_skyline_root.name = "HorizonSkyline"
	add_child(_skyline_root)
	var layers: Array[Dictionary] = [
		{"radius": 1640.0, "height": 205.0, "file": "skyline_rich_town_near.png", "opacity": 0.82, "seed": 1.7, "density": 126.0},
		{"radius": 1870.0, "height": 325.0, "file": "skyline_rich_town_far.png", "opacity": 0.70, "seed": 8.3, "density": 176.0},
	]
	var loaded_textures := 0
	for index in layers.size():
		var layer: Dictionary = layers[index]
		var panorama := _texture(String(layer.get("file", "")))
		if panorama == null:
			continue
		loaded_textures += 1
		var material := ShaderMaterial.new()
		material.shader = HorizonSkylineShader
		material.set_shader_parameter("skyline_tex", panorama)
		material.set_shader_parameter("skyline_tint", Color(0.92, 0.97, 1.0, 1.0) if index == 0 else Color(0.82, 0.91, 1.0, 1.0))
		material.set_shader_parameter("layer_opacity", float(layer.get("opacity", 0.7)))
		material.set_shader_parameter("layer_seed", float(layer.get("seed", 1.0)))
		material.set_shader_parameter("skyline_density", float(layer.get("density", 144.0)))
		material.set_shader_parameter("night_factor", 0.0)
		var skyline := MeshInstance3D.new()
		skyline.name = "SkylineLayer%d" % (index + 1)
		skyline.mesh = _make_skyline_ring_mesh(float(layer.get("radius", 1600.0)), float(layer.get("height", 200.0)))
		skyline.material_override = material
		skyline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		skyline.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		skyline.custom_aabb = AABB(Vector3(-1900.0, -5.0, -1900.0), Vector3(3800.0, 340.0, 3800.0))
		_skyline_root.add_child(skyline)
		_skyline_materials.append(material)
	_enhancement_stats["skyline_layers"] = _skyline_materials.size()
	_enhancement_stats["skyline_follows_vehicle"] = true
	_enhancement_stats["skyline_procedural_windows"] = true
	_enhancement_stats["skyline_panorama_textures_0243"] = loaded_textures == layers.size()
	_enhancement_stats["skyline_panorama_width"] = 4096
	_enhancement_stats["skyline_panorama_height"] = 512
	set_skyline_origin(spawn_transform.origin)
	_set_skyline_time(time_of_day)


func _set_skyline_time(mode: String) -> void:
	var near_color := Color(0.20, 0.29, 0.38, 1.0)
	var far_color := Color(0.46, 0.57, 0.69, 1.0)
	var night_factor := 0.0
	if mode == "sunset":
		near_color = Color(0.34, 0.22, 0.25, 1.0)
		far_color = Color(0.62, 0.38, 0.34, 1.0)
	elif mode == "night":
		near_color = Color(0.035, 0.065, 0.12, 1.0)
		far_color = Color(0.055, 0.09, 0.17, 1.0)
		night_factor = 1.0
	for index in _skyline_materials.size():
		_skyline_materials[index].set_shader_parameter("skyline_tint", near_color if index == 0 else far_color)
		_skyline_materials[index].set_shader_parameter("night_factor", night_factor)


func get_park_rects() -> Array:
	if _is_desert:
		return [Rect2(3030.0, 3180.0, 640.0, 640.0)]
	var rects: Array = []
	for spec_variant in PARK_SPECS:
		var spec: Dictionary = spec_variant
		rects.append(spec.get("rect", Rect2()))
	return rects


## Named park entries for the 0.2.32 full-screen world map.  The
## minimap only needs rectangles; the big map also shows names.
func get_park_map_entries() -> Array:
	if _is_desert:
		return [{"id": "oasis", "label": "Оазис", "rect": Rect2(3030.0, 3180.0, 640.0, 640.0)}]
	if _is_forest:
		return [{"id": "meadows", "label": "Центральные луга", "rect": Rect2(1150.0, 1250.0, 1400.0, 1300.0)}]
	var entries: Array = []
	for spec_variant in PARK_SPECS:
		var spec: Dictionary = spec_variant
		entries.append({
			"id": String(spec.get("id", "park")),
			"label": String(spec.get("label", "Парк")),
			"rect": spec.get("rect", Rect2()),
		})
	return entries


func _is_in_park(x: float, z: float, pad: float = 0.0) -> bool:
	if _is_desert:
		return false
	for spec_variant in PARK_SPECS:
		var spec: Dictionary = spec_variant
		var rect: Rect2 = spec.get("rect", Rect2())
		if x >= rect.position.x - pad and x <= rect.position.x + rect.size.x + pad and z >= rect.position.y - pad and z <= rect.position.y + rect.size.y + pad:
			return true
	return false



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
		floori((x - _active_aabb.position.x) / ROAD_GRID_CELL_M),
		floori((z - _active_aabb.position.z) / ROAD_GRID_CELL_M)
	)


func _build_road_surface_index() -> void:
	_road_segment_surfaces.clear()
	_road_segment_starts.clear()
	_road_segment_ends.clear()
	_road_segment_half_widths.clear()
	_road_segment_ids.clear()
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
			_road_segment_ids.append(String(road.get("id", "")))
			_road_segment_surfaces.append(String(road.get("surface", "asphalt")))

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


## Clearance to every road *except* one named road.  0.2.24 uses this to
## cut real openings in curbs, sidewalk slabs, gutters and lane paint
## wherever another carriageway crosses or joins mid-segment; the old
## endpoint-only junction trims could not see those intersections at
## all, so kerbs ran straight across side-street mouths.
func _clearance_to_other_roads(point: Vector3, current_id: String, current_direction: Vector3 = Vector3.ZERO) -> float:
	if _road_segment_grid.is_empty():
		return ROAD_GRID_QUERY_CLEARANCE_M
	var candidates: Array = _road_segment_grid.get(_road_grid_cell(point.x, point.z), [])
	var best_clearance := ROAD_GRID_QUERY_CLEARANCE_M
	var flat_direction := current_direction
	flat_direction.y = 0.0
	var has_direction := flat_direction.length_squared() > 0.0001
	if has_direction:
		flat_direction = flat_direction.normalized()
	for index_variant in candidates:
		var i := int(index_variant)
		if _road_segment_ids[i] == current_id:
			continue
		if has_direction:
			# A collinear continuation under a different edge id is
			# the same physical carriageway, not a crossing street:
			# do not punch kerb/paint gaps at invisible chain seams.
			var other_direction := _road_segment_ends[i] - _road_segment_starts[i]
			other_direction.y = 0.0
			if other_direction.length_squared() > 0.0001 and absf(flat_direction.dot(other_direction.normalized())) > 0.85:
				continue
		var clearance := _distance_to_segment_xz(point, _road_segment_starts[i], _road_segment_ends[i]) - _road_segment_half_widths[i]
		best_clearance = minf(best_clearance, clearance)
	return best_clearance


# 0.2.36 road-furniture safety pass.  Junction furniture used to be
# emitted from a hard-coded 3x7 street grid, so T/L junctions received
# crosswalks and signal heads for approaches that do not exist (most
# visibly on the beach east of the Corniche).  Probe the exported road
# segments instead: an arm exists only when sampled points just beyond
# the junction mouth and farther along that approach are still on
# asphalt.  Requiring two probes prevents the perpendicular street
# itself from masquerading as a missing collinear approach.
func _is_road_arm_present(center: Vector3, direction: Vector3, mouth_distance: float) -> bool:
	var flat_direction := Vector3(direction.x, 0.0, direction.z)
	if flat_direction.length_squared() <= 0.0001:
		return false
	flat_direction = flat_direction.normalized()
	for probe_distance in [mouth_distance + 3.0, mouth_distance + 9.0]:
		var probe := center + flat_direction * float(probe_distance)
		if _road_clearance_xz(probe) > 0.25:
			return false
	return true


func _junction_arm_mask(center: Vector3, half_width_x: float, half_width_z: float) -> Dictionary:
	return {
		"x_plus": _is_road_arm_present(center, Vector3.RIGHT, half_width_x),
		"x_minus": _is_road_arm_present(center, Vector3.LEFT, half_width_x),
		"z_plus": _is_road_arm_present(center, Vector3.BACK, half_width_z),
		"z_minus": _is_road_arm_present(center, Vector3.FORWARD, half_width_z),
	}


func _junction_has_both_axes(arms: Dictionary) -> bool:
	var has_x_arm := bool(arms.get("x_plus", false)) or bool(arms.get("x_minus", false))
	var has_z_arm := bool(arms.get("z_plus", false)) or bool(arms.get("z_minus", false))
	return has_x_arm and has_z_arm


# A centre-point test is not enough for a shelter, planter or picnic
# table: its 2-6 m footprint can still project across the carriageway
# at a corner.  Test the rectangle corners and edge midpoints, and ask
# for a real kerbside clearance rather than merely "not on asphalt".
func _is_footprint_clear_of_roads(center: Vector3, size_xz: Vector2, yaw: float, minimum_clearance: float = 0.45) -> bool:
	var basis := Basis(Vector3.UP, yaw)
	var half_x := size_xz.x * 0.5
	var half_z := size_xz.y * 0.5
	var local_offsets: Array[Vector3] = [
		Vector3.ZERO,
		Vector3(-half_x, 0.0, -half_z), Vector3(half_x, 0.0, -half_z),
		Vector3(-half_x, 0.0, half_z), Vector3(half_x, 0.0, half_z),
		Vector3(0.0, 0.0, -half_z), Vector3(0.0, 0.0, half_z),
		Vector3(-half_x, 0.0, 0.0), Vector3(half_x, 0.0, 0.0),
	]
	for local_offset in local_offsets:
		var sample_point: Vector3 = center + basis * local_offset
		if _road_clearance_xz(sample_point) < minimum_clearance:
			return false
		if not _is_position_clear(sample_point, 0.25, 0.0):
			return false
	return true


func _is_pole_clear_of_road(point: Vector3, minimum_clearance: float = 0.45) -> bool:
	# Road-only on purpose: _is_position_clear() also applies generic
	# landmark exclusion circles, which would delete valid corner
	# signal poles around the Boulevard arch at (760, 60).
	return _road_clearance_xz(point) >= minimum_clearance


# Curb/slab/paint generators consume the exported 5-8 m road samples
# as whole boxes.  Near a junction that made every opening stop or
# restart at sample granularity, leaving one whole box across a side
# street or a multi-metre unexplained gap.  Split only the samples
# near an endpoint junction or another carriageway; ordinary straight
# runs keep their existing instancing density and draw cost.
func _subdivide_road_points_for_junctions(
	points: Array[Vector3],
	trim_start: float,
	trim_end: float,
	total_length: float,
	road_id: String
) -> Array[Vector3]:
	if points.size() < 2 or total_length <= 0.0:
		return points
	var result: Array[Vector3] = []
	var travelled := 0.0
	for segment_index in range(points.size() - 1):
		var a: Vector3 = points[segment_index]
		var b: Vector3 = points[segment_index + 1]
		var segment_length := Vector2(b.x - a.x, b.z - a.z).length()
		var segment_start := travelled
		var segment_end := travelled + segment_length
		var midpoint := (a + b) * 0.5
		var segment_direction := b - a
		segment_direction.y = 0.0
		var near_junction := (
			(trim_start > 0.0 and segment_start < trim_start + 6.0)
			or (trim_end > 0.0 and total_length - segment_end < trim_end + 6.0)
			or _clearance_to_other_roads(midpoint, road_id, segment_direction) < 5.5
		)
		if result.is_empty():
			result.append(a)
		var pieces := 1
		if near_junction and segment_length > 1.35:
			pieces = clampi(int(ceil(segment_length / 1.25)), 1, 8)
		var fractions: Array[float] = []
		for piece_index in range(1, pieces + 1):
			fractions.append(float(piece_index) / float(pieces))
		# Also split exactly on the endpoint trim distances.  Equal
		# 1.25 m pieces alone could still resume a kerb up to one
		# piece before/after the rounded-return tangent.
		if segment_length > 0.001:
			for boundary_distance in [trim_start, total_length - trim_end]:
				var boundary := float(boundary_distance)
				if boundary > segment_start + 0.001 and boundary < segment_end - 0.001:
					var boundary_fraction := (boundary - segment_start) / segment_length
					var already_present := false
					for existing_fraction in fractions:
						if absf(existing_fraction - boundary_fraction) < 0.001:
							already_present = true
							break
					if not already_present:
						fractions.append(boundary_fraction)
		fractions.sort()
		for fraction in fractions:
			result.append(a.lerp(b, fraction))
		if fractions.size() > 1:
			_road_junction_subsegments_0236 += fractions.size() - 1
		travelled = segment_end
	return result


func _is_position_clear(point: Vector3, building_padding: float, minimum_road_clearance: float, include_generated_buildings: bool = true, excluded_pool_index: int = -1) -> bool:
	if _road_clearance_xz(point) < minimum_road_clearance:
		return false
	for building_variant in data.get("buildings", []):
		var building: Dictionary = building_variant
		var center := _item_position(building)
		var local := Basis(Vector3.UP, -_f(building, "rotY")) * (point - center)
		if absf(local.x) <= _f(building, "w", 20.0) * 0.5 + building_padding and absf(local.z) <= _f(building, "d", 16.0) * 0.5 + building_padding:
			return false
	# Infill buildings are generated before vegetation/city details,
	# so random ground-cover and roadside props must respect those
	# footprints too.  Fixed Blender replacements can be wider and
	# yawed relative to their generic search envelope; use a safe
	# square based on the largest true footprint dimension for them.
	for building in (_infill_buildings if include_generated_buildings else []):
		var centre := _item_position(building)
		var footprint_w := _f(building, "w", 20.0)
		var footprint_d := _f(building, "d", 16.0)
		match String(building.get("model", "generic")):
			"glass":
				footprint_w = maxf(footprint_w, 34.0)
				footprint_d = maxf(footprint_d, 34.0)
			"hero":
				footprint_w = maxf(footprint_w, 32.4)
				footprint_d = maxf(footprint_d, 32.4)
			"townhouse":
				footprint_w = maxf(footprint_w, 18.87)
				footprint_d = maxf(footprint_d, 18.87)
		if absf(point.x - centre.x) <= footprint_w * 0.5 + building_padding and absf(point.z - centre.z) <= footprint_d * 0.5 + building_padding:
			return false
	var all_pools: Array = data.get("pools", [])
	for pool_index in all_pools.size():
		if pool_index == excluded_pool_index:
			continue
		var pool: Dictionary = all_pools[pool_index]
		var centre := _item_position(pool)
		var local := Basis(Vector3.UP, -_f(pool, "rotY")) * (point - centre)
		if absf(local.x) <= (_f(pool, "w", 8.0) + 1.3) * 0.5 + building_padding and absf(local.z) <= (_f(pool, "d", 5.0) + 1.3) * 0.5 + building_padding:
			return false
	for landmark_variant in data.get("landmarks", []):
		var landmark: Dictionary = landmark_variant
		var center := _item_position(landmark)
		# Building Model No.6 has a rectangular 56 x 52 m world parcel
		# after its Boulevard-facing yaw.  The generic landmark circle
		# is only 14 m for this data row, which would let infill corners
		# and roadside props land on the opera forecourt/service yard.
		if String(landmark.get("kind", "")) == "rt-opera":
			if absf(point.x - center.x) <= 28.0 + building_padding and absf(point.z - center.z) <= 26.0 + building_padding:
				return false
			continue
		# Building Model No.7 occupies a rectangular 38.4 x 36.0 m
		# terrace; its data radius is 0 (14 m generic floor), which
		# would let district trees/props spawn inside the prayer-hall
		# corners and side arcades.
		if String(landmark.get("kind", "")) == "rt-mosque":
			if absf(point.x - center.x) <= 19.2 + building_padding and absf(point.z - center.z) <= 18.0 + building_padding:
				return false
			continue
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
		if (_is_desert or _is_forest) and _road_surface_kind_at(world_position) == "gravel":
			return {"kind": "gravel", "label": "ГРАВИЙ", "mu": 0.80, "rolling_resistance": 0.045}
		return {"kind": "asphalt", "label": "АСФАЛЬТ", "mu": 1.16, "rolling_resistance": 0.014}
	if clearance <= 2.05:
		if _is_forest:
			return {"kind": "dirt", "label": "ГРУНТ", "mu": 0.68, "rolling_resistance": 0.060}
		if _is_desert:
			return {"kind": "packed_sand", "label": "ПЕСОК", "mu": 0.70, "rolling_resistance": 0.055}
		return {"kind": "sidewalk", "label": "БЕТОН", "mu": 0.93, "rolling_resistance": 0.021}

	var h := height_at(world_position.x, world_position.z)
	var is_water := false
	if _is_forest:
		is_water = _in_zone(world_position.x, world_position.z, "gfLake") and world_position.y < 15.3
	elif _is_desert:
		is_water = _in_zone(world_position.x, world_position.z, "oasisLake") and world_position.y < 27.4
	else:
		is_water = ((_in_zone(world_position.x, world_position.z, "sea") or _in_zone(world_position.x, world_position.z, "marina")) and h < 0.45) or world_position.y < 0.18
	if is_water:
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
		"sand", "dune":
			return {"kind": "sand", "label": "ПЕСОК", "mu": 0.57, "rolling_resistance": 0.115}
		"salt":
			return {"kind": "salt", "label": "СОЛЬ", "mu": 0.60, "rolling_resistance": 0.010}
		"packed":
			return {"kind": "packed_sand", "label": "ПЕСОК", "mu": 0.70, "rolling_resistance": 0.055}
		"gravel":
			return {"kind": "gravel", "label": "ГРАВИЙ", "mu": 0.80, "rolling_resistance": 0.045}
		"rock", "gf_rock":
			return {"kind": "rock", "label": "КАМЕНЬ", "mu": 0.74, "rolling_resistance": 0.052}
		"gf_meadow":
			return {"kind": "grass", "label": "ТРАВА", "mu": 0.62, "rolling_resistance": 0.078}
		"gf_forest_floor":
			return {"kind": "forest_floor", "label": "ПОДСТИЛКА", "mu": 0.58, "rolling_resistance": 0.090}
		"gf_mud":
			return {"kind": "mud", "label": "ГРЯЗЬ", "mu": 0.42, "rolling_resistance": 0.140}
		"gf_field":
			return {"kind": "field", "label": "ПОЛЕ", "mu": 0.55, "rolling_resistance": 0.100}
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


## Ground height for Boulevard furniture/planting.  East of the road at
## Z=140..390 the exported 10 m height grid falls into the marina, but
## the master-plan promenade is a raised quay at carriageway level.
## `_build_premium_boulevard_details()` now builds that deck explicitly;
## using raw `height_at()` there buried the east cafes/lawns roughly
## 1-4 m below the road and was a major part of the empty spawn view.
func _boulevard_ground_y(x: float, z: float) -> float:
	if x >= 771.0 and x <= 790.0 and z >= 140.0 and z <= 390.0:
		return height_at(760.0, z) - 0.18
	return height_at(x, z)


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
	# 0.2.27: Basis.scaled() multiplies matrix ROWS = a GLOBAL (parent-
	# space) scale, so at yaw +/-90deg a box long local Z ended up
	# long in WORLD Z -- bridge guardrail sections rendered ACROSS the
	# east-west causeways (user screenshots 27.10) and every rotated
	# far-proxies got its footprint swapped.  scaled_local() multiplies
	# COLUMNS = the authored local axes every caller intended.
	return Transform3D(Basis(Vector3.UP, yaw).scaled_local(scale_value), position_value)


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
	_set_skyline_time(mode)
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
	var curtain_sky_reflection := Color(0.30, 0.53, 0.86)
	var curtain_ground_reflection := Color(0.16, 0.155, 0.135)
	if mode == "sunset":
		curtain_sky_reflection = Color(0.96, 0.46, 0.25)
		curtain_ground_reflection = Color(0.20, 0.13, 0.10)
	elif mode == "night":
		curtain_sky_reflection = Color(0.025, 0.050, 0.120)
		curtain_ground_reflection = Color(0.030, 0.032, 0.036)
	for curtain_material in _curtain_glass_materials:
		curtain_material.set_shader_parameter("interior_light_strength", curtain_light_strength)
		curtain_material.set_shader_parameter("sky_reflection_color", curtain_sky_reflection)
		curtain_material.set_shader_parameter("ground_reflection_color", curtain_ground_reflection)
	_enhancement_stats["curtain_wall_interior_light_strength"] = curtain_light_strength
	_enhancement_stats["curtain_wall_environment_reflection_0217"] = true

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
	var data_path := DESERT_DATA_PATH if world_id == "desert" else (FOREST_DATA_PATH if world_id == "greenforest" else WORLD_DATA_PATH)
	if not FileAccess.file_exists(data_path):
		build_error = "Native world data is missing from the exported game: %s" % data_path
		push_error(build_error)
		return
	var file := FileAccess.open(data_path, FileAccess.READ)
	if file == null:
		build_error = "Native world data could not be opened: %s" % data_path
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
	# 0.2.55: the body deliberately stays OUT of the tree while the
	# world builds.  Adding CollisionShape3D children to a live
	# in-space StaticBody costs more per shape the more shapes the
	# body already has (measured 2.3 ms -> 12 ms per add across a
	# 19k-shape build), which made the GreenForest scatter stages
	# take ~110 s and killed loading on Android.  Out of tree, shape
	# adds are plain node operations; _attach_collision_root() puts
	# the finished body into the space once, at build completion.


func _attach_collision_root() -> void:
	if _collision_root != null and _collision_root.get_parent() == null:
		add_child(_collision_root)



## 0.2.30 directional streaming: MultiMesh chunks behind the camera
## retire from every render pass (including shadow maps), and static
## colliders are only live in a radius around the car.  Geometry,
## materials and shaders are untouched -- the city in front of the
## camera keeps full detail; what is behind simply stops costing
## CPU/GPU.  Decisions use the camera position shifted along the car
## velocity (lookahead), a whole-chunk clear distance (centre distance
## minus AABB radius, so tall shadow casters effectively stay), and
## separate hide/show thresholds against flicker.
func update_streaming(cam_pos: Vector3, cam_forward: Vector3, focus_pos: Vector3, focus_velocity: Vector3, delta: float, horizontal_half_fov_rad: float = 1.05) -> void:
	if horizontal_half_fov_rad > 0.20:
		_stream_horizontal_half_fov_rad = clampf(horizontal_half_fov_rad, 0.55, 1.45)
	_stream_focus_pos = focus_pos
	_streaming_timer += delta
	if _streaming_initialized and _streaming_timer < 0.2:
		return
	_streaming_timer = 0.0
	_streaming_initialized = true
	_streaming_tick(cam_pos, cam_forward, focus_pos, focus_velocity)


func _streaming_tick(cam_pos: Vector3, cam_forward: Vector3, focus_pos: Vector3, focus_velocity: Vector3) -> void:
	var fwd := Vector2(cam_forward.x, cam_forward.z)
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector2(0.0, -1.0)
	var lookahead := Vector3(focus_velocity.x, 0.0, focus_velocity.z) * 0.9
	if lookahead.length() > 45.0:
		lookahead = lookahead.normalized() * 45.0
	var anchor := cam_pos + lookahead
	# Reflection probes capture once at startup; do not hide anything
	# until they have seen the complete city.
	var allow_hide := _elapsed > 2.5
	var hidden_count := 0
	var sector_hidden_count := 0
	for chunk in _stream_chunks:
		var node := chunk.get("node") as MultiMeshInstance3D
		if node == null:
			continue
		var centre: Vector3 = chunk.get("centre", Vector3.ZERO)
		var radius := float(chunk.get("radius", 0.0))
		var is_hidden := bool(chunk.get("hidden", false))
		if radius > 210.0:
			if is_hidden:
				node.visible = true
				chunk["hidden"] = false
			continue
		var to := Vector2(centre.x - anchor.x, centre.z - anchor.z)
		var dist := to.length()
		var clear := dist - radius
		var dot := 1.0
		if dist > 0.01:
			dot = (to / dist).dot(fwd)
		# Angular test against the chunk's whole bounding sphere.  The
		# 0.34 rad (~19.5 degree) hide margin beyond the real horizontal
		# frustum is deliberately generous: a fast orbit/steering swing
		# brings a side chunk back through the earlier show margin
		# before any part of it can reach the screen edge, so the view
		# direction itself is never degraded or popped.
		var view_angle := acos(clampf(dot, -1.0, 1.0))
		var angular_radius := asin(clampf(radius / maxf(dist, 1.0), 0.0, 1.0))
		var outside_view_sector := view_angle - angular_radius > _stream_horizontal_half_fov_rad + STREAM_SECTOR_HIDE_MARGIN_RAD
		var safely_in_view_sector := view_angle - angular_radius < _stream_horizontal_half_fov_rad + STREAM_SECTOR_SHOW_MARGIN_RAD
		var was_sector_hidden := bool(chunk.get("sector_hidden_0237", false))
		if allow_hide and not is_hidden and clear > STREAM_HIDE_BEHIND_M and (dot < -0.18 or outside_view_sector):
			node.visible = false
			chunk["hidden"] = true
			chunk["sector_hidden_0237"] = outside_view_sector and dot >= -0.18
			is_hidden = true
		elif is_hidden and (clear < STREAM_SHOW_BEHIND_M or (dot > -0.05 and safely_in_view_sector)):
			node.visible = true
			chunk["hidden"] = false
			chunk["sector_hidden_0237"] = false
			is_hidden = false
		else:
			chunk["sector_hidden_0237"] = is_hidden and was_sector_hidden
		if is_hidden:
			hidden_count += 1
			if bool(chunk.get("sector_hidden_0237", false)):
				sector_hidden_count += 1

	var focus_2d := Vector2(focus_pos.x, focus_pos.z)
	var active_shapes := 0
	for cell_variant in _collider_cells.keys():
		var cell := cell_variant as Vector2i
		var cell_centre := Vector2(
			_active_aabb.position.x + (float(cell.x) + 0.5) * STREAM_CELL_M,
			_active_aabb.position.z + (float(cell.y) + 0.5) * STREAM_CELL_M
		)
		var cell_dist := cell_centre.distance_to(focus_2d)
		var was_active := bool(_active_collider_cells.get(cell, true))
		var want_active := was_active
		if cell_dist < COLLIDER_ACTIVE_RADIUS_M:
			want_active = true
		elif cell_dist > COLLIDER_RELEASE_RADIUS_M:
			want_active = false
		if want_active != was_active or not _active_collider_cells.has(cell):
			for shape_variant in (_collider_cells[cell] as Array):
				var shape := shape_variant as CollisionShape3D
				if shape != null:
					shape.disabled = not want_active
			_active_collider_cells[cell] = want_active
		if want_active:
			active_shapes += (_collider_cells[cell] as Array).size()

	_stream_sector_hidden_0237 = sector_hidden_count
	_enhancement_stats["directional_streaming_0230"] = true
	_enhancement_stats["view_sector_streaming_0237"] = true
	_enhancement_stats["streaming_chunks_total"] = _stream_chunks.size()
	_enhancement_stats["streaming_chunks_hidden"] = hidden_count
	_enhancement_stats["streaming_sector_hidden_0237"] = sector_hidden_count
	_enhancement_stats["streaming_horizontal_half_fov_0237"] = _stream_horizontal_half_fov_rad
	_enhancement_stats["streaming_colliders_active"] = active_shapes


func _register_collider(collision: CollisionShape3D, centre: Vector3) -> void:
	var cell := Vector2i(
		floori((centre.x - _active_aabb.position.x) / STREAM_CELL_M),
		floori((centre.z - _active_aabb.position.z) / STREAM_CELL_M)
	)
	if not _collider_cells.has(cell):
		_collider_cells[cell] = []
		# 0.2.55: seed the streaming state from the spawn focus so
		# far shapes are created disabled (a free property write
		# while the body is out of the tree) and the first
		# _streaming_tick does not rewrite `disabled` on every
		# shape of a huge body (that pass alone cost 55 s).
		var cell_centre := Vector2(
			_active_aabb.position.x + (float(cell.x) + 0.5) * STREAM_CELL_M,
			_active_aabb.position.z + (float(cell.y) + 0.5) * STREAM_CELL_M
		)
		var spawn_2d := Vector2(spawn_transform.origin.x, spawn_transform.origin.z)
		_active_collider_cells[cell] = cell_centre.distance_to(spawn_2d) < COLLIDER_ACTIVE_RADIUS_M
	collision.disabled = not bool(_active_collider_cells[cell])
	(_collider_cells[cell] as Array).append(collision)


func _add_box_collider(center: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	if _collision_root == null:
		return
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = make_transform(center, yaw, Vector3.ONE)
	_collision_root.add_child(collision)
	_register_collider(collision, center)


func _add_pitched_box_collider(center: Vector3, size: Vector3, yaw: float, pitch: float) -> void:
	if _collision_root == null:
		return
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), center)
	_collision_root.add_child(collision)
	_register_collider(collision, center)


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
	_register_collider(collision, center)


# --- 0.2.39 Sail cottage estates (Models No.10-12) -------------------
# The flat authored estate must sit on the highest sampled point of
# its rotated lot; the basalt retaining podium below then absorbs the
# remaining 0.46-0.60 m island fall instead of a floating corner.
func _cottage_estate_ground_y_0239(centre: Vector3, yaw: float) -> float:
	var basis := Basis(Vector3.UP, yaw)
	var ground_y := -INF
	for fx_variant in [-0.5, -0.25, 0.0, 0.25, 0.5]:
		var fx: float = fx_variant
		for fz_variant in [-0.5, -0.25, 0.0, 0.25, 0.5]:
			var fz: float = fz_variant
			var point: Vector3 = centre + basis * Vector3(fx * 35.96, 0.0, fz * 27.01)
			ground_y = maxf(ground_y, height_at(point.x, point.z))
	return ground_y - 0.03


func _cottage_podium_transforms_0239(origin: Vector3, yaw: float) -> Array[Transform3D]:
	var root_transform := make_transform(origin, yaw, Vector3.ONE)
	var result: Array[Transform3D] = []
	# Same three-slab chamfered plan as the GLB site base, sunk into
	# the slope so only a low dark retaining edge shows downhill.
	for spec in [
		[Vector3(0.0, -0.46, 0.0), Vector3(35.2, 0.95, 19.0)],
		[Vector3(0.0, -0.46, 11.3), Vector3(28.2, 0.95, 3.7)],
		[Vector3(0.0, -0.46, -11.3), Vector3(28.2, 0.95, 3.7)],
	]:
		var local_center: Vector3 = spec[0]
		var local_size: Vector3 = spec[1]
		result.append(root_transform * Transform3D(Basis.IDENTITY.scaled(local_size), local_center))
	return result


func _add_cottage_local_box_0239(origin: Vector3, yaw: float, local_center: Vector3, size: Vector3, local_yaw: float = 0.0) -> void:
	var world_center: Vector3 = origin + Basis(Vector3.UP, yaw) * local_center
	_add_box_collider(world_center, size, yaw + local_yaw)


func _add_cottage_estate_colliders_0239(origin: Vector3, yaw: float, model: String) -> int:
	var count := 0
	# Real perimeter, not one invisible estate-sized cube: front wall
	# with its closed gates, rear wall, both sides and the four
	# chamfer runs (local +Z is the estate front in Godot space).
	_add_cottage_local_box_0239(origin, yaw, Vector3(0.0, 1.19, 13.2), Vector3(28.0, 2.38, 0.55))
	_add_cottage_local_box_0239(origin, yaw, Vector3(0.0, 1.19, -13.2), Vector3(28.0, 2.38, 0.55))
	_add_cottage_local_box_0239(origin, yaw, Vector3(-17.7, 1.19, 0.0), Vector3(0.55, 2.38, 19.0))
	_add_cottage_local_box_0239(origin, yaw, Vector3(17.7, 1.19, 0.0), Vector3(0.55, 2.38, 19.0))
	_add_cottage_local_box_0239(origin, yaw, Vector3(-15.85, 1.19, 11.35), Vector3(5.25, 2.38, 0.55), -PI * 0.25)
	_add_cottage_local_box_0239(origin, yaw, Vector3(15.85, 1.19, 11.35), Vector3(5.25, 2.38, 0.55), PI * 0.25)
	_add_cottage_local_box_0239(origin, yaw, Vector3(-15.85, 1.19, -11.35), Vector3(5.25, 2.38, 0.55), PI * 0.25)
	_add_cottage_local_box_0239(origin, yaw, Vector3(15.85, 1.19, -11.35), Vector3(5.25, 2.38, 0.55), -PI * 0.25)
	count += 8
	match model:
		"cottage_dune":
			_add_cottage_local_box_0239(origin, yaw, Vector3(3.8, 3.80, -1.8), Vector3(16.8, 7.60, 10.6))
			_add_cottage_local_box_0239(origin, yaw, Vector3(-4.9, 4.23, -0.55), Vector3(2.35, 8.46, 12.1))
			_add_cottage_local_box_0239(origin, yaw, Vector3(-10.6, 1.95, 1.15), Vector3(8.1, 3.90, 7.1))
			_add_cottage_local_box_0239(origin, yaw, Vector3(-2.2, 1.88, 2.65), Vector3(5.2, 3.76, 4.35))
			_add_cottage_local_box_0239(origin, yaw, Vector3(2.5, 0.40, -10.35), Vector3(12.5, 0.80, 3.7))
			count += 5
		"cottage_courtyard":
			_add_cottage_local_box_0239(origin, yaw, Vector3(-9.7, 3.35, -2.0), Vector3(6.7, 6.70, 13.0))
			_add_cottage_local_box_0239(origin, yaw, Vector3(9.7, 3.35, -2.0), Vector3(6.7, 6.70, 13.0))
			_add_cottage_local_box_0239(origin, yaw, Vector3(0.0, 3.80, -7.15), Vector3(14.8, 7.60, 6.1))
			_add_cottage_local_box_0239(origin, yaw, Vector3(-4.15, 3.10, 4.28), Vector3(4.0, 6.20, 0.72))
			_add_cottage_local_box_0239(origin, yaw, Vector3(4.15, 3.10, 4.28), Vector3(4.0, 6.20, 0.72))
			_add_cottage_local_box_0239(origin, yaw, Vector3(-7.9, 5.82, -7.3), Vector3(3.15, 11.64, 3.15))
			_add_cottage_local_box_0239(origin, yaw, Vector3(15.05, 0.40, -6.8), Vector3(3.15, 0.80, 9.6))
			count += 7
		"cottage_palm":
			_add_cottage_local_box_0239(origin, yaw, Vector3(-6.4, 4.00, -1.0), Vector3(13.0, 8.00, 10.0))
			_add_cottage_local_box_0239(origin, yaw, Vector3(8.6, 3.70, -0.55), Vector3(9.2, 7.40, 8.6))
			_add_cottage_local_box_0239(origin, yaw, Vector3(1.0, 1.97, 1.05), Vector3(5.0, 3.94, 5.9))
			_add_cottage_local_box_0239(origin, yaw, Vector3(-13.35, 4.40, -2.2), Vector3(1.55, 8.81, 4.7))
			_add_cottage_local_box_0239(origin, yaw, Vector3(-1.5, 0.40, -10.25), Vector3(15.5, 0.80, 3.9))
			count += 5
	return count


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
	# 0.2.17: curtain-wall reflections are a primary visual feature.
	# A 512 radiance cubemap is still a one-time static-sky cost, while
	# 256 visibly smeared sky/cloud contrast across curved tower glass.
	_sky.radiance_size = Sky.RADIANCE_SIZE_512
	_enhancement_stats["sky_radiance_size"] = 512

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
	triplanar: bool = false,
	roughness_file: String = ""
) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D

	var material := StandardMaterial3D.new()
	material.resource_name = key
	material.albedo_color = color
	var albedo := _texture(albedo_file)
	var normal := _texture(normal_file)
	var roughness_map := _texture(roughness_file)
	if albedo != null:
		material.albedo_texture = albedo
	if normal != null:
		material.normal_enabled = true
		material.normal_texture = normal
		material.normal_scale = 0.72
	if roughness_map != null:
		# 0.2.39: authored cottage PBR sets carry absolute roughness
		# in the red channel.  The scalar below stays as a calibrated
		# multiplier (1.0 = use the map exactly as authored).
		material.roughness_texture = roughness_map
		material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
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


func _create_concrete_material(
	key: String,
	tint: Color,
	roughness: float = 0.95,
	pattern_scale: float = 1.0,
	joint_strength: float = 0.92,
	normal_strength: float = 0.62
) -> ShaderMaterial:
	if _materials.has(key):
		return _materials[key] as ShaderMaterial
	var material := ShaderMaterial.new()
	material.resource_name = key
	material.shader = ConcreteSurfaceShader
	var slab := _texture("user_concrete_slabs.jpg")
	var slab_normal := _texture("user_concrete_slabs_normal.jpg")
	var fine := _texture("user_plaster_white.jpg")
	if slab != null:
		material.set_shader_parameter("slab_texture", slab)
	if slab_normal != null:
		material.set_shader_parameter("slab_normal_texture", slab_normal)
	if fine != null:
		material.set_shader_parameter("fine_texture", fine)
	material.set_shader_parameter("use_textures", slab != null and slab_normal != null and fine != null)
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("base_roughness", roughness)
	material.set_shader_parameter("pattern_scale", pattern_scale)
	material.set_shader_parameter("joint_strength", joint_strength)
	material.set_shader_parameter("normal_strength", normal_strength)
	_materials[key] = material
	_enhancement_stats["concrete_stochastic_0217"] = true
	_enhancement_stats["paving_variety_0228"] = true
	_enhancement_stats["concrete_shader_materials"] = int(_enhancement_stats.get("concrete_shader_materials", 0)) + 1
	return material


func _create_premium_paving_material(
	key: String,
	tint: Color,
	roughness: float = 0.76,
	texture_scale: float = 0.115,
	normal_strength: float = 0.42
) -> ShaderMaterial:
	if _materials.has(key):
		return _materials[key] as ShaderMaterial
	var material := ShaderMaterial.new()
	material.resource_name = key
	material.shader = PremiumStonePavingShader
	var stone := _texture("user_stone_tiles_beige.jpg")
	var fine := _texture("user_plaster_white.jpg")
	var fine_normal := _texture("user_plaster_white_normal.jpg")
	if stone != null:
		material.set_shader_parameter("stone_texture", stone)
	if fine != null:
		material.set_shader_parameter("fine_texture", fine)
	if fine_normal != null:
		material.set_shader_parameter("fine_normal_texture", fine_normal)
	material.set_shader_parameter("use_textures", stone != null and fine != null and fine_normal != null)
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("base_roughness", roughness)
	material.set_shader_parameter("texture_scale", texture_scale)
	material.set_shader_parameter("normal_strength", normal_strength)
	_materials[key] = material
	_enhancement_stats["premium_stone_paving_shader_0218"] = true
	_enhancement_stats["paving_running_bond_0228"] = true
	_enhancement_stats["premium_stone_paving_materials"] = int(_enhancement_stats.get("premium_stone_paving_materials", 0)) + 1
	return material


func _terrain_material(kind: String) -> Material:
	if kind == "concrete":
		return _create_concrete_material(
			"terrain_concrete_shader",
			Color(0.58, 0.59, 0.58),
			0.96,
			1.0,
			0.88,
			0.54
		)
	if kind == "plaza":
		return _create_premium_paving_material(
			"terrain_premium_pavers_shader",
			Color(0.84, 0.80, 0.70),
			0.68,
			0.140,
			0.50
		)
	var material: StandardMaterial3D
	match kind:
		"gf_meadow":
			material = _material("terrain_gf_meadow", "gf_meadow.jpg", "gf_meadow_normal.jpg", Color(1.0, 1.0, 1.0), 1.0, 0.0, Vector3.ONE, false, "gf_meadow_roughness.jpg")
		"gf_forest_floor":
			material = _material("terrain_gf_floor", "gf_forest_floor.jpg", "gf_forest_floor_normal.jpg", Color(1.0, 1.0, 1.0), 1.0, 0.0, Vector3.ONE, false, "gf_forest_floor_roughness.jpg")
		"gf_mud":
			material = _material("terrain_gf_mud", "gf_mud.jpg", "gf_mud_normal.jpg", Color(1.0, 1.0, 1.0), 0.85, 0.0, Vector3.ONE, false, "gf_mud_roughness.jpg")
		"gf_field":
			material = _material("terrain_gf_field", "gf_field_soil.jpg", "gf_field_soil_normal.jpg", Color(1.0, 1.0, 1.0), 1.0, 0.0, Vector3.ONE, false, "gf_field_soil_roughness.jpg")
		"gf_rock":
			material = _material("terrain_gf_rock", "gf_rock_gray.jpg", "gf_rock_gray_normal.jpg", Color(1.0, 1.0, 0.99), 1.0, 0.0, Vector3(0.055, 0.055, 0.055), true, "gf_rock_gray_roughness.jpg")
		"sand":
			material = _material("terrain_sand", "user_sand_rippled.jpg", "user_sand_rippled_normal.jpg", Color(0.88, 0.78, 0.58), 0.98)
		"dune":
			material = _material("terrain_dune_sand_dz", "dz_sand_dune.jpg", "dz_sand_dune_normal.jpg", Color(1.0, 0.98, 0.94), 1.0, 0.0, Vector3.ONE, false, "dz_sand_dune_roughness.jpg")
		"salt":
			material = _material("terrain_salt_dz", "dz_salt_crust.jpg", "dz_salt_crust_normal.jpg", Color(1.0, 1.0, 0.99), 1.0, 0.0, Vector3.ONE, false, "dz_salt_crust_roughness.jpg")
		"packed":
			material = _material("terrain_packed_dz", "dz_packed_earth.jpg", "dz_packed_earth_normal.jpg", Color(1.0, 0.98, 0.95), 1.0, 0.0, Vector3.ONE, false, "dz_packed_earth_roughness.jpg")
		"gravel":
			if _is_desert:
				material = _material("terrain_gravel_dz", "dz_trail_gravel.jpg", "dz_trail_gravel_normal.jpg", Color(1.0, 0.99, 0.96), 1.0, 0.0, Vector3.ONE, false, "dz_trail_gravel_roughness.jpg")
			else:
				material = _material("terrain_gravel_rubble", "user_stone_rubble.jpg", "user_stone_rubble_normal.jpg", Color(0.68, 0.61, 0.52), 1.0)
		"rock":
			if _is_desert:
				material = _material("terrain_red_rock_dz", "dz_rock_red.jpg", "dz_rock_red_normal.jpg", Color(0.96, 0.92, 0.86), 1.0, 0.0, Vector3(0.055, 0.055, 0.055), true, "dz_rock_red_roughness.jpg")
			else:
				material = _material("terrain_rock", "rock.jpg", "rock_normal.jpg", Color(0.58, 0.56, 0.52), 1.0)
		_:
			material = _material("terrain_grass", "user_grass.jpg", "user_grass_normal.jpg", Color(0.54, 0.63, 0.38), 0.98)
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
	_enhancement_stats["boulevard_dark_asphalt_0219"] = true
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
	material.set_shader_parameter("cool_interior_color", Color(0.075, 0.130, 0.175))
	material.set_shader_parameter("sky_reflection_color", Color(0.30, 0.53, 0.86))
	material.set_shader_parameter("ground_reflection_color", Color(0.16, 0.155, 0.135))
	material.set_shader_parameter("environment_tint_strength", 0.19)
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
	_enhancement_stats["curtain_wall_environment_reflection_0217"] = true
	_enhancement_stats["curtain_wall_clearcoat_removed"] = true
	_enhancement_stats["curtain_wall_reflective_glass_0227"] = true
	var smoke_luminance := 0.2126 * smoke_color.r + 0.7152 * smoke_color.g + 0.0722 * smoke_color.b
	_enhancement_stats["glass_smoke_luminance_min_0227"] = minf(float(_enhancement_stats.get("glass_smoke_luminance_min_0227", smoke_luminance)), smoke_luminance)
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
			Color(0.105, 0.185, 0.275),
			Color(0.215, 0.345, 0.490),
			Color(0.235, 0.225, 0.200),
			Color(0.150, 0.104, 0.065),
			3.30,
			1.75,
			7.0,
			0.84
		)
	if facade == "goldTower":
		return _create_curtain_wall_material(
			"facade_bronze_tower_physical",
			true,
			Color(0.185, 0.118, 0.052),
			Color(0.355, 0.232, 0.112),
			Color(0.270, 0.225, 0.170),
			Color(0.178, 0.124, 0.075),
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
				Color(0.105, 0.185, 0.275),
				Color(0.215, 0.345, 0.490),
				Color(0.235, 0.225, 0.200),
				Color(0.150, 0.104, 0.065),
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
		"CafeTravertine":
			var cafe_travertine := _material("dubai_cafe_travertine", "user_travertine.jpg", "user_travertine_normal.jpg", Color(0.90, 0.84, 0.72), 0.76, 0.0, Vector3(0.22, 0.22, 0.22), true)
			cafe_travertine.normal_scale = 0.92
			cafe_travertine.metallic_specular = 0.48
			return cafe_travertine
		"CafeLimestone":
			return _material("dubai_cafe_limestone", "user_stone_tiles_beige.jpg", "", Color(0.90, 0.84, 0.73), 0.88, 0.0, Vector3(0.24, 0.24, 0.24), true)
		"CafeBronze":
			var cafe_bronze := _material("dubai_cafe_bronze", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.74, 0.48, 0.25), 0.34, 0.78, Vector3(0.40, 0.40, 0.40), true)
			cafe_bronze.metallic_specular = 0.92
			return cafe_bronze
		"CafeSteel":
			var cafe_steel := _material("dubai_cafe_steel", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.46, 0.54, 0.56), 0.38, 0.78, Vector3(0.44, 0.44, 0.44), true)
			cafe_steel.metallic_specular = 0.92
			return cafe_steel
		"CafeGlass":
			var cafe_glass := _material("dubai_cafe_glass", "", "", Color(0.30, 0.53, 0.62, 0.40), 0.055, 0.15)
			cafe_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			cafe_glass.metallic_specular = 1.0
			cafe_glass.clearcoat_enabled = true
			cafe_glass.clearcoat = 0.92
			cafe_glass.clearcoat_roughness = 0.035
			cafe_glass.emission_enabled = true
			cafe_glass.emission = Color(0.20, 0.34, 0.39)
			_register_night_material(cafe_glass, 0.0, 0.08, 0.32)
			return cafe_glass
		"CafeOak":
			return _material("dubai_cafe_oak", "user_wood_slats_dark.jpg", "user_wood_slats_dark_normal.jpg", Color(0.82, 0.63, 0.42), 0.78, 0.0, Vector3(0.32, 0.32, 0.32), true)
		"CafeWarmLight":
			var cafe_warm_light := _material("dubai_cafe_warm_light", "", "", Color(1.0, 0.67, 0.32), 0.34, 0.0)
			cafe_warm_light.emission_enabled = true
			cafe_warm_light.emission = Color(0.78, 0.34, 0.09)
			_register_night_material(cafe_warm_light, 0.0, 0.08, 0.54)
			return cafe_warm_light
		"CafeCream":
			return _material("dubai_cafe_cream", "user_travertine.jpg", "user_travertine_normal.jpg", Color(0.93, 0.88, 0.77), 0.70, 0.0, Vector3(0.36, 0.36, 0.36), true)
		"CafeCounter":
			var cafe_counter := _material("dubai_cafe_counter", "user_black_granite.jpg", "user_black_granite_normal.jpg", Color(0.30, 0.32, 0.32), 0.30, 0.12, Vector3(0.34, 0.34, 0.34), true)
			cafe_counter.metallic_specular = 0.76
			return cafe_counter
		"CafeGreen":
			var cafe_green := _material("dubai_cafe_greenery", "foliage.jpg", "foliage_normal.jpg", Color(0.58, 0.76, 0.45), 0.96, 0.0, Vector3(0.72, 0.72, 0.72), true)
			cafe_green.cull_mode = BaseMaterial3D.CULL_DISABLED
			return cafe_green
		"CafeCeramic":
			return _material("dubai_cafe_ceramic", "user_marble_tiles.jpg", "user_marble_tiles_normal.jpg", Color(0.94, 0.89, 0.79), 0.36, 0.08, Vector3(0.22, 0.22, 0.22), true)
		"CafeFabric":
			return _material("dubai_cafe_linen", "cafe_linen.jpg", "cafe_linen_normal.png", Color(0.98, 0.94, 0.86), 0.92, 0.0, Vector3(8.0, 8.0, 8.0), true)
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
			var villa_curtain := _material("villa_curtain", "user_plaster_white.jpg", "user_plaster_white_normal.jpg", Color(0.43, 0.39, 0.33), 1.0, 0.0, Vector3(0.65, 0.65, 0.65), true)
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
		# 0.2.39 Building Models No.10-12: the Sail cottage estates use
		# their own seven authored PBR sets.  Roughness comes from the
		# maps (rammed sand ~0.95 down to roof metal ~0.63), so a wall,
		# a bronze gate and a metal roof no longer share one scalar.
		"CottageSand":
			var cottage_sand := _material("cottage_rammed_sand", "cottage_rammed_sand.jpg", "cottage_rammed_sand_normal.jpg", Color(0.94, 0.88, 0.76), 1.0, 0.0, Vector3(0.20, 0.20, 0.20), true, "cottage_rammed_sand_roughness.jpg")
			cottage_sand.normal_scale = 1.25
			cottage_sand.metallic_specular = 0.35
			return cottage_sand
		"CottageTravertine":
			var cottage_travertine := _material("cottage_travertine_coarse", "cottage_travertine_coarse.jpg", "cottage_travertine_coarse_normal.jpg", Color(0.95, 0.90, 0.80), 1.0, 0.0, Vector3(0.24, 0.24, 0.24), true, "cottage_travertine_coarse_roughness.jpg")
			cottage_travertine.normal_scale = 1.05
			cottage_travertine.metallic_specular = 0.52
			return cottage_travertine
		"CottageLimestone":
			var cottage_limestone := _material("cottage_limestone_blocks", "cottage_limestone_blocks.jpg", "cottage_limestone_blocks_normal.jpg", Color(0.93, 0.87, 0.74), 1.0, 0.0, Vector3(0.20, 0.20, 0.20), true, "cottage_limestone_blocks_roughness.jpg")
			cottage_limestone.normal_scale = 1.20
			cottage_limestone.metallic_specular = 0.42
			return cottage_limestone
		"CottageBasalt":
			var cottage_basalt := _material("cottage_basalt", "cottage_basalt.jpg", "cottage_basalt_normal.jpg", Color(0.80, 0.84, 0.92), 1.0, 0.04, Vector3(0.22, 0.22, 0.22), true, "cottage_basalt_roughness.jpg")
			cottage_basalt.normal_scale = 1.15
			cottage_basalt.metallic_specular = 0.65
			return cottage_basalt
		"CottageTeak":
			var cottage_teak := _material("cottage_teak_weathered", "cottage_teak_weathered.jpg", "cottage_teak_weathered_normal.jpg", Color(0.90, 0.78, 0.62), 1.0, 0.0, Vector3(0.34, 0.34, 0.34), true, "cottage_teak_weathered_roughness.jpg")
			cottage_teak.normal_scale = 1.10
			cottage_teak.metallic_specular = 0.42
			return cottage_teak
		"CottageBronze":
			var cottage_bronze := _material("cottage_bronze", "cottage_roof_metal.jpg", "cottage_roof_metal_normal.jpg", Color(0.72, 0.45, 0.22), 0.60, 0.82, Vector3(0.50, 0.50, 0.50), true, "cottage_roof_metal_roughness.jpg")
			cottage_bronze.normal_scale = 0.70
			cottage_bronze.metallic_specular = 0.95
			return cottage_bronze
		"CottageRoofMetal":
			var cottage_roof_metal := _material("cottage_roof_metal", "cottage_roof_metal.jpg", "cottage_roof_metal_normal.jpg", Color(0.64, 0.57, 0.50), 0.82, 0.66, Vector3(0.42, 0.42, 0.42), true, "cottage_roof_metal_roughness.jpg")
			cottage_roof_metal.normal_scale = 0.80
			cottage_roof_metal.metallic_specular = 0.90
			return cottage_roof_metal
		"CottagePaving":
			var cottage_paving := _material("cottage_paving", "cottage_paving.jpg", "cottage_paving_normal.jpg", Color(0.91, 0.87, 0.77), 1.0, 0.0, Vector3(0.17, 0.17, 0.17), true, "cottage_paving_roughness.jpg")
			cottage_paving.normal_scale = 1.10
			cottage_paving.metallic_specular = 0.42
			return cottage_paving
		"CottageGravel":
			var cottage_gravel := _material("cottage_gravel", "cottage_paving.jpg", "cottage_paving_normal.jpg", Color(0.70, 0.64, 0.55), 1.0, 0.0, Vector3(0.50, 0.50, 0.50), true, "cottage_paving_roughness.jpg")
			cottage_gravel.normal_scale = 1.20
			cottage_gravel.metallic_specular = 0.22
			return cottage_gravel
		"CottageGlass":
			var cottage_glass := _material("cottage_glass_physical", "", "", Color(0.34, 0.55, 0.64, 0.52), 0.07, 0.0)
			cottage_glass.metallic_specular = 1.0
			cottage_glass.clearcoat_enabled = true
			cottage_glass.clearcoat = 1.0
			cottage_glass.clearcoat_roughness = 0.055
			cottage_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			cottage_glass.emission_enabled = true
			cottage_glass.emission = Color(1.0, 0.72, 0.44)
			_register_night_material(cottage_glass, 0.0, 0.07, 0.30)
			return cottage_glass
		"CottageCore":
			# Exterior-only backing behind the glass: a near-black
			# volume so windows never show a hollow shell or sky.
			var cottage_core := _material("cottage_core", "cottage_basalt.jpg", "cottage_basalt_normal.jpg", Color(0.16, 0.15, 0.14), 1.0, 0.0, Vector3(0.40, 0.40, 0.40), true, "cottage_basalt_roughness.jpg")
			cottage_core.metallic_specular = 0.18
			return cottage_core
		"CottageBlind":
			var cottage_blind := _material("cottage_blind", "cottage_rammed_sand.jpg", "cottage_rammed_sand_normal.jpg", Color(0.52, 0.46, 0.38), 1.0, 0.0, Vector3(0.70, 0.70, 0.70), true, "cottage_rammed_sand_roughness.jpg")
			cottage_blind.normal_scale = 0.40
			cottage_blind.metallic_specular = 0.22
			return cottage_blind
		"CottageLawn":
			var cottage_lawn := _material("cottage_lawn", "user_grass.jpg", "user_grass_normal.jpg", Color(0.68, 0.76, 0.56), 1.0, 0.0, Vector3(0.50, 0.50, 0.50), true)
			cottage_lawn.normal_scale = 0.90
			cottage_lawn.metallic_specular = 0.22
			return cottage_lawn
		"CottageHedge":
			var cottage_hedge := _material("cottage_hedge", "hedge.jpg", "", Color(0.70, 0.82, 0.60), 1.0, 0.0, Vector3(0.90, 0.90, 0.90), true)
			cottage_hedge.metallic_specular = 0.25
			return cottage_hedge
		"CottageWater":
			var cottage_water := _material("cottage_pool_water", "user_pool_mosaic.jpg", "user_pool_mosaic_normal.jpg", Color(0.30, 0.62, 0.72, 0.96), 0.075, 0.0, Vector3(0.55, 0.55, 0.55), true)
			cottage_water.normal_scale = 0.42
			cottage_water.metallic_specular = 1.0
			cottage_water.clearcoat_enabled = true
			cottage_water.clearcoat = 0.90
			cottage_water.clearcoat_roughness = 0.045
			cottage_water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			return cottage_water
		"CottageLight":
			var cottage_light := _material("cottage_warm_light", "", "", Color(1.0, 0.67, 0.32), 0.34, 0.0)
			cottage_light.emission_enabled = true
			cottage_light.emission = Color(0.78, 0.34, 0.09)
			_register_night_material(cottage_light, 0.0, 0.10, 0.62)
			return cottage_light
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
				Color(0.105, 0.185, 0.275),
				Color(0.215, 0.345, 0.490),
				Color(0.235, 0.225, 0.200),
				Color(0.150, 0.104, 0.065),
				3.45,
				1.85,
				2.0,
				0.72
			)
		"TowerSpandrel":
			var tower_spandrel := _material("tower_spandrel", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.105, 0.130, 0.155), 0.38, 0.72, Vector3(0.35, 0.35, 0.35), true)
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
				Color(0.110, 0.195, 0.288),
				Color(0.225, 0.358, 0.505),
				Color(0.240, 0.230, 0.205),
				Color(0.156, 0.109, 0.068),
				3.42,
				1.60,
				5.0,
				0.72
			)
		"MainSpandrel":
			var main_spandrel := _material("main_spandrel", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.105, 0.130, 0.155), 0.38, 0.72, Vector3(0.35, 0.35, 0.35), true)
			main_spandrel.metallic_specular = 0.95
			return main_spandrel
		"MainStone":
			var main_stone := _material("main_stone", "user_stone_tiles_beige.jpg", "", Color(0.50, 0.46, 0.39), 0.90, 0.0, Vector3(0.18, 0.18, 0.18), true)
			main_stone.metallic_specular = 0.48
			return main_stone
		"MainTrim":
			var main_trim := _material("main_trim", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.46, 0.34, 0.18), 0.42, 0.60, Vector3(0.35, 0.35, 0.35), true)
			main_trim.metallic_specular = 0.92
			return main_trim
		"MainMetal":
			var main_metal := _material("main_metal", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.075, 0.090, 0.105), 0.42, 0.82, Vector3(0.48, 0.48, 0.48), true)
			main_metal.metallic_specular = 0.92
			return main_metal
		"MainWater":
			var main_water := _material("main_water", "user_pool_mosaic.jpg", "user_pool_mosaic_normal.jpg", Color(0.38, 0.68, 0.78), 0.08, 0.0, Vector3(0.45, 0.45, 0.45), true)
			main_water.metallic_specular = 1.0
			main_water.clearcoat_enabled = true
			main_water.clearcoat = 1.0
			main_water.clearcoat_roughness = 0.06
			return main_water
		"OperaShell":
			# Building Model No.6: glazed ceramic shell panels.  Marble
			# micro-veining is only a fine ceramic grain at this world
			# scale; the pleats, panel ribs and movement joints are real
			# Blender geometry on the merged parametric vaults.
			var opera_shell := _material("opera_shell_ceramic", "user_marble_tiles.jpg", "user_marble_tiles_normal.jpg", Color(0.94, 0.89, 0.79), 0.46, 0.04, Vector3(0.20, 0.20, 0.20), true)
			opera_shell.normal_scale = 0.65
			opera_shell.metallic_specular = 0.72
			opera_shell.clearcoat_enabled = true
			opera_shell.clearcoat = 0.28
			opera_shell.clearcoat_roughness = 0.28
			opera_shell.cull_mode = BaseMaterial3D.CULL_DISABLED
			return opera_shell
		"OperaStone":
			var opera_stone := _material("opera_travertine", "user_travertine.jpg", "user_travertine_normal.jpg", Color(0.86, 0.78, 0.64), 0.88, 0.0, Vector3(0.18, 0.18, 0.18), true)
			opera_stone.normal_scale = 1.15
			opera_stone.metallic_specular = 0.48
			return opera_stone
		"OperaBronze":
			var opera_bronze := _material("opera_bronze", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.62, 0.38, 0.18), 0.34, 0.82, Vector3(0.45, 0.45, 0.45), true)
			opera_bronze.metallic_specular = 0.95
			return opera_bronze
		"OperaGlass":
			# The curved foyer and shell lunettes use the same reflective
			# physical coating as the towers, calibrated more transparent
			# so the modelled balconies, stairs and crimson curtain read
			# through the glass instead of becoming an opaque blue sheet.
			return _create_curtain_wall_material(
				"opera_glass_physical",
				false,
				Color(0.108, 0.182, 0.252),
				Color(0.220, 0.335, 0.452),
				Color(0.250, 0.238, 0.214),
				Color(0.187, 0.122, 0.065),
				3.60,
				3.00,
				6.0,
				0.56
			)
		"OperaInterior":
			var opera_interior := _material("opera_interior", "user_plaster_white.jpg", "user_plaster_white_normal.jpg", Color(0.160, 0.120, 0.090), 0.96, 0.0, Vector3(0.40, 0.40, 0.40), true)
			opera_interior.metallic_specular = 0.22
			return opera_interior
		"OperaWood":
			var opera_wood := _material("opera_oak", "user_wood_slats_dark.jpg", "user_wood_slats_dark_normal.jpg", Color(0.78, 0.48, 0.26), 0.76, 0.0, Vector3(0.36, 0.36, 0.36), true)
			opera_wood.normal_scale = 1.10
			opera_wood.metallic_specular = 0.46
			return opera_wood
		"OperaGranite":
			var opera_granite := _material("opera_black_granite", "user_black_granite.jpg", "user_black_granite_normal.jpg", Color(0.42, 0.44, 0.46), 0.36, 0.08, Vector3(0.26, 0.26, 0.26), true)
			opera_granite.normal_scale = 0.95
			opera_granite.metallic_specular = 0.86
			opera_granite.clearcoat_enabled = true
			opera_granite.clearcoat = 0.32
			opera_granite.clearcoat_roughness = 0.24
			return opera_granite
		"OperaCurtain":
			var opera_curtain := _material("opera_curtain_velvet", "cafe_linen.jpg", "cafe_linen_normal.png", Color(0.42, 0.050, 0.070), 0.98, 0.0, Vector3(2.50, 2.50, 2.50), true)
			opera_curtain.normal_scale = 0.55
			opera_curtain.metallic_specular = 0.20
			return opera_curtain
		"OperaWater":
			var opera_water := _material("opera_reflecting_water", "user_pool_mosaic.jpg", "user_pool_mosaic_normal.jpg", Color(0.30, 0.62, 0.72, 0.96), 0.075, 0.0, Vector3(0.55, 0.55, 0.55), true)
			opera_water.normal_scale = 0.42
			opera_water.metallic_specular = 1.0
			opera_water.clearcoat_enabled = true
			opera_water.clearcoat = 0.90
			opera_water.clearcoat_roughness = 0.045
			opera_water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			return opera_water
		"OperaLight":
			var opera_light := _material("opera_warm_light", "", "", Color(1.0, 0.70, 0.36), 0.32, 0.0)
			opera_light.emission_enabled = true
			opera_light.emission = Color(1.0, 0.55, 0.20)
			_register_night_material(opera_light, 0.0, 0.10, 0.62)
			return opera_light
		"MosqueStone":
			# Building Model No.7: warm carved sandstone at world scale;
			# the piers, seams and arch orders are Blender geometry.
			var mosque_stone := _material("mosque_sandstone", "facade_sandstone.jpg", "facade_sandstone_normal.jpg", Color(0.88, 0.79, 0.62), 0.92, 0.0, Vector3(0.16, 0.16, 0.16), true)
			mosque_stone.normal_scale = 1.05
			mosque_stone.metallic_specular = 0.46
			return mosque_stone
		"MosqueLimestone":
			var mosque_limestone := _material("mosque_limestone", "user_travertine.jpg", "user_travertine_normal.jpg", Color(0.92, 0.84, 0.68), 0.86, 0.0, Vector3(0.18, 0.18, 0.18), true)
			mosque_limestone.normal_scale = 1.05
			mosque_limestone.metallic_specular = 0.52
			return mosque_limestone
		"MosqueDome":
			# Patinated turquoise copper: brushed-metal microtexture,
			# near-metallic reflections and a clearcoat sheen over the
			# real lathed onion profile and brass rib geometry.
			var mosque_dome := _material("mosque_dome_copper", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.10, 0.52, 0.55), 0.34, 0.68, Vector3(0.30, 0.30, 0.30), true)
			mosque_dome.normal_scale = 0.72
			mosque_dome.metallic_specular = 0.96
			mosque_dome.clearcoat_enabled = true
			mosque_dome.clearcoat = 0.38
			mosque_dome.clearcoat_roughness = 0.22
			mosque_dome.cull_mode = BaseMaterial3D.CULL_DISABLED
			return mosque_dome
		"MosqueBrass":
			var mosque_brass := _material("mosque_brass", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.66, 0.42, 0.18), 0.32, 0.85, Vector3(0.45, 0.45, 0.45), true)
			mosque_brass.normal_scale = 0.72
			mosque_brass.metallic_specular = 0.96
			mosque_brass.cull_mode = BaseMaterial3D.CULL_DISABLED
			return mosque_brass
		"MosqueGlass":
			# Reflective physical glazing calibrated transparent enough
			# for the dark iwan/interior reveals behind the arches.
			return _create_curtain_wall_material(
				"mosque_glass_physical",
				false,
				Color(0.105, 0.185, 0.255),
				Color(0.212, 0.340, 0.460),
				Color(0.250, 0.238, 0.214),
				Color(0.187, 0.126, 0.065),
				3.20,
				1.80,
				7.0,
				0.60
			)
		"MosqueInterior":
			var mosque_interior := _material("mosque_interior", "user_plaster_white.jpg", "user_plaster_white_normal.jpg", Color(0.150, 0.112, 0.082), 0.96, 0.0, Vector3(0.40, 0.40, 0.40), true)
			mosque_interior.metallic_specular = 0.22
			mosque_interior.cull_mode = BaseMaterial3D.CULL_DISABLED
			return mosque_interior
		"MosqueWood":
			var mosque_wood := _material("mosque_cedar", "user_wood_slats_dark.jpg", "user_wood_slats_dark_normal.jpg", Color(0.74, 0.46, 0.24), 0.78, 0.0, Vector3(0.36, 0.36, 0.36), true)
			mosque_wood.normal_scale = 1.10
			mosque_wood.metallic_specular = 0.46
			return mosque_wood
		"MosqueTile":
			# Glazed turquoise tile: mosaic texture at small world scale
			# with a hard clearcoat so bands read ceramic, not paint.
			var mosque_tile := _material("mosque_glazed_tile", "user_pool_mosaic.jpg", "user_pool_mosaic_normal.jpg", Color(0.10, 0.58, 0.62), 0.22, 0.04, Vector3(0.55, 0.55, 0.55), true)
			mosque_tile.normal_scale = 0.62
			mosque_tile.metallic_specular = 0.92
			mosque_tile.clearcoat_enabled = true
			mosque_tile.clearcoat = 0.72
			mosque_tile.clearcoat_roughness = 0.10
			return mosque_tile
		"MosqueGranite":
			var mosque_granite := _material("mosque_black_granite", "user_black_granite.jpg", "user_black_granite_normal.jpg", Color(0.42, 0.44, 0.46), 0.36, 0.08, Vector3(0.26, 0.26, 0.26), true)
			mosque_granite.normal_scale = 0.95
			mosque_granite.metallic_specular = 0.86
			mosque_granite.clearcoat_enabled = true
			mosque_granite.clearcoat = 0.32
			mosque_granite.clearcoat_roughness = 0.24
			return mosque_granite
		"MosqueLight":
			var mosque_light := _material("mosque_warm_light", "", "", Color(1.0, 0.70, 0.36), 0.32, 0.0)
			mosque_light.emission_enabled = true
			mosque_light.emission = Color(1.0, 0.55, 0.20)
			_register_night_material(mosque_light, 0.0, 0.10, 0.62)
			return mosque_light
		"HotelStone":
			# Building Model No.8: travertine podium/end piers at world
			# scale; the colonnade rhythm is Blender geometry.
			var hotel_stone := _material("hotel_travertine", "user_travertine.jpg", "user_travertine_normal.jpg", Color(0.90, 0.83, 0.70), 0.86, 0.0, Vector3(0.18, 0.18, 0.18), true)
			hotel_stone.normal_scale = 1.0
			hotel_stone.metallic_specular = 0.52
			return hotel_stone
		"HotelPlaster":
			var hotel_plaster := _material("hotel_plaster", "user_plaster_white.jpg", "user_plaster_white_normal.jpg", Color(0.94, 0.90, 0.82), 0.90, 0.0, Vector3(0.20, 0.20, 0.20), true)
			hotel_plaster.normal_scale = 0.85
			hotel_plaster.metallic_specular = 0.44
			return hotel_plaster
		"HotelBronze":
			var hotel_bronze := _material("hotel_bronze", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.62, 0.40, 0.20), 0.32, 0.85, Vector3(0.45, 0.45, 0.45), true)
			hotel_bronze.normal_scale = 0.72
			hotel_bronze.metallic_specular = 0.96
			hotel_bronze.cull_mode = BaseMaterial3D.CULL_DISABLED
			return hotel_bronze
		"HotelGlass":
			# Reflective physical glazing over the inhabited interior
			# layers, calibrated like the mosque/storefront glass.
			return _create_curtain_wall_material(
				"hotel_glass_physical",
				false,
				Color(0.102, 0.180, 0.262),
				Color(0.205, 0.332, 0.472),
				Color(0.245, 0.234, 0.210),
				Color(0.170, 0.116, 0.061),
				3.10,
				1.75,
				6.0,
				0.62
			)
		"HotelInterior":
			var hotel_interior := _material("hotel_interior", "user_plaster_white.jpg", "user_plaster_white_normal.jpg", Color(0.160, 0.120, 0.088), 0.96, 0.0, Vector3(0.40, 0.40, 0.40), true)
			hotel_interior.metallic_specular = 0.22
			hotel_interior.cull_mode = BaseMaterial3D.CULL_DISABLED
			return hotel_interior
		"HotelGranite":
			var hotel_granite := _material("hotel_black_granite", "user_black_granite.jpg", "user_black_granite_normal.jpg", Color(0.42, 0.44, 0.46), 0.36, 0.08, Vector3(0.26, 0.26, 0.26), true)
			hotel_granite.normal_scale = 0.95
			hotel_granite.metallic_specular = 0.86
			hotel_granite.clearcoat_enabled = true
			hotel_granite.clearcoat = 0.32
			hotel_granite.clearcoat_roughness = 0.24
			return hotel_granite
		"HotelWood":
			var hotel_wood := _material("hotel_teak", "user_wood_deck.jpg", "user_wood_deck_normal.jpg", Color(0.85, 0.62, 0.38), 0.80, 0.0, Vector3(0.30, 0.30, 0.30), true)
			hotel_wood.normal_scale = 1.05
			hotel_wood.metallic_specular = 0.46
			return hotel_wood
		"HotelWater":
			var hotel_water := _material("hotel_pool_water", "user_pool_mosaic.jpg", "user_pool_mosaic_normal.jpg", Color(0.30, 0.62, 0.72, 0.96), 0.075, 0.0, Vector3(0.55, 0.55, 0.55), true)
			hotel_water.normal_scale = 0.42
			hotel_water.metallic_specular = 1.0
			hotel_water.clearcoat_enabled = true
			hotel_water.clearcoat = 0.90
			hotel_water.clearcoat_roughness = 0.045
			hotel_water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			return hotel_water
		"HotelCurtain":
			var hotel_curtain := _material("hotel_curtain_linen", "cafe_linen.jpg", "cafe_linen_normal.png", Color(0.88, 0.80, 0.66), 1.0, 0.0, Vector3(2.50, 2.50, 2.50), true)
			hotel_curtain.normal_scale = 0.55
			hotel_curtain.metallic_specular = 0.20
			hotel_curtain.cull_mode = BaseMaterial3D.CULL_DISABLED
			return hotel_curtain
		"HotelAccent":
			var hotel_accent := _material("hotel_accent_teal", "", "", Color(0.05, 0.42, 0.45), 0.58, 0.0)
			hotel_accent.metallic_specular = 0.40
			hotel_accent.cull_mode = BaseMaterial3D.CULL_DISABLED
			return hotel_accent
		"HotelLight":
			var hotel_light := _material("hotel_warm_light", "", "", Color(1.0, 0.72, 0.40), 0.32, 0.0)
			hotel_light.emission_enabled = true
			hotel_light.emission = Color(1.0, 0.57, 0.22)
			_register_night_material(hotel_light, 0.0, 0.10, 0.62)
			return hotel_light
		"MuseumStone":
			# Building Model No.9: limestone rainscreen panels at world
			# scale; every panel/joint is Blender geometry.
			var museum_stone := _material("museum_limestone", "user_travertine.jpg", "user_travertine_normal.jpg", Color(0.86, 0.78, 0.63), 0.88, 0.0, Vector3(0.18, 0.18, 0.18), true)
			museum_stone.normal_scale = 1.0
			museum_stone.metallic_specular = 0.50
			return museum_stone
		"MuseumStonePale":
			var museum_stone_pale := _material("museum_limestone_pale", "user_travertine.jpg", "user_travertine_normal.jpg", Color(0.96, 0.90, 0.77), 0.88, 0.0, Vector3(0.18, 0.18, 0.18), true)
			museum_stone_pale.normal_scale = 1.0
			museum_stone_pale.metallic_specular = 0.50
			return museum_stone_pale
		"MuseumCore":
			var museum_core := _material("museum_core_dark", "user_black_rough.jpg", "user_black_rough_normal.jpg", Color(0.32, 0.30, 0.26), 0.95, 0.0, Vector3(0.30, 0.30, 0.30), true)
			museum_core.metallic_specular = 0.30
			return museum_core
		"MuseumBronze":
			var museum_bronze := _material("museum_bronze", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.60, 0.39, 0.20), 0.32, 0.85, Vector3(0.45, 0.45, 0.45), true)
			museum_bronze.normal_scale = 0.72
			museum_bronze.metallic_specular = 0.96
			museum_bronze.cull_mode = BaseMaterial3D.CULL_DISABLED
			return museum_bronze
		"MuseumGlass":
			# Atrium/rear-slot glazing over the real stair, mezzanines
			# and cafe depth; 1.22 m bay matches the Blender mullions.
			return _create_curtain_wall_material(
				"museum_glass_physical",
				false,
				Color(0.102, 0.180, 0.262),
				Color(0.205, 0.332, 0.472),
				Color(0.245, 0.234, 0.210),
				Color(0.170, 0.116, 0.061),
				3.90,
				1.22,
				8.0,
				0.56
			)
		"MuseumInterior":
			var museum_interior := _material("museum_interior", "user_plaster_white.jpg", "user_plaster_white_normal.jpg", Color(0.170, 0.125, 0.090), 0.96, 0.0, Vector3(0.40, 0.40, 0.40), true)
			museum_interior.metallic_specular = 0.22
			museum_interior.cull_mode = BaseMaterial3D.CULL_DISABLED
			return museum_interior
		"MuseumWhite":
			var museum_white := _material("museum_gallery_white", "user_plaster_white.jpg", "user_plaster_white_normal.jpg", Color(0.93, 0.91, 0.86), 0.85, 0.0, Vector3(0.20, 0.20, 0.20), true)
			museum_white.normal_scale = 0.85
			museum_white.metallic_specular = 0.44
			return museum_white
		"MuseumGranite":
			var museum_granite := _material("museum_black_granite", "user_black_granite.jpg", "user_black_granite_normal.jpg", Color(0.42, 0.44, 0.46), 0.36, 0.08, Vector3(0.26, 0.26, 0.26), true)
			museum_granite.normal_scale = 0.95
			museum_granite.metallic_specular = 0.86
			museum_granite.clearcoat_enabled = true
			museum_granite.clearcoat = 0.32
			museum_granite.clearcoat_roughness = 0.24
			return museum_granite
		"MuseumTravertine":
			var museum_travertine := _material("museum_travertine", "user_travertine.jpg", "user_travertine_normal.jpg", Color(0.93, 0.86, 0.73), 0.86, 0.0, Vector3(0.18, 0.18, 0.18), true)
			museum_travertine.normal_scale = 1.0
			museum_travertine.metallic_specular = 0.52
			return museum_travertine
		"MuseumWater":
			var museum_water := _material("museum_pool_water", "user_pool_mosaic.jpg", "user_pool_mosaic_normal.jpg", Color(0.30, 0.62, 0.72, 0.96), 0.075, 0.0, Vector3(0.55, 0.55, 0.55), true)
			museum_water.normal_scale = 0.42
			museum_water.metallic_specular = 1.0
			museum_water.clearcoat_enabled = true
			museum_water.clearcoat = 0.90
			museum_water.clearcoat_roughness = 0.045
			museum_water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			return museum_water
		"MuseumBannerTeal":
			var museum_banner_teal := _material("museum_banner_teal", "", "", Color(0.03, 0.36, 0.38), 0.85, 0.0)
			museum_banner_teal.metallic_specular = 0.35
			museum_banner_teal.cull_mode = BaseMaterial3D.CULL_DISABLED
			return museum_banner_teal
		"MuseumBannerOchre":
			var museum_banner_ochre := _material("museum_banner_ochre", "", "", Color(0.74, 0.43, 0.11), 0.85, 0.0)
			museum_banner_ochre.metallic_specular = 0.35
			museum_banner_ochre.cull_mode = BaseMaterial3D.CULL_DISABLED
			return museum_banner_ochre
		"MuseumLight":
			var museum_light := _material("museum_warm_light", "", "", Color(1.0, 0.72, 0.40), 0.32, 0.0)
			museum_light.emission_enabled = true
			museum_light.emission = Color(1.0, 0.57, 0.22)
			_register_night_material(museum_light, 0.0, 0.10, 0.62)
			return museum_light
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
			return _create_concrete_material("prop_concrete_light_shader", Color(0.68, 0.69, 0.67), 0.95, 0.82, 0.72, 0.50)
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
		"PalmTrunk":
			var palm_trunk := _material("palm_trunk", "oak_bark.jpg", "oak_bark_normal.jpg", Color(0.50, 0.38, 0.26), 1.0, 0.0, Vector3.ONE, false)
			palm_trunk.normal_scale = 1.15
			palm_trunk.metallic_specular = 0.18
			return palm_trunk
		"PalmCrown":
			var palm_crown := _material("palm_crown_fibre", "oak_bark.jpg", "oak_bark_normal.jpg", Color(0.38, 0.28, 0.16), 1.0, 0.0, Vector3(1.4, 1.4, 1.4), false)
			palm_crown.normal_scale = 1.25
			palm_crown.metallic_specular = 0.16
			return palm_crown
		"PalmCrownshaft":
			var crownshaft := _material("palm_crownshaft", "", "", Color(0.20, 0.36, 0.15), 0.74)
			crownshaft.metallic_specular = 0.42
			return crownshaft
		"PalmRachis":
			var rachis := _material("palm_rachis", "oak_bark.jpg", "oak_bark_normal.jpg", Color(0.34, 0.34, 0.18), 0.94, 0.0, Vector3(0.7, 0.7, 0.7), false)
			rachis.normal_scale = 0.80
			rachis.metallic_specular = 0.24
			return rachis
		"PalmFruit":
			var dates := _material("palm_dates", "", "", Color(0.58, 0.22, 0.045), 0.50)
			dates.metallic_specular = 0.58
			return dates
		"ShrubBranch":
			return _material("shrub_branch", "oak_bark.jpg", "oak_bark_normal.jpg", Color(0.40, 0.29, 0.19), 1.0, 0.0, Vector3(0.8, 0.8, 0.8), false)
		"ShrubBerry":
			var berries := _material("shrub_berries", "", "", Color(0.50, 0.07, 0.16), 0.44)
			berries.metallic_specular = 0.62
			return berries
		"FlowerCoral":
			var coral := _material("flower_coral", "", "", Color(0.78, 0.17, 0.11), 0.74)
			coral.cull_mode = BaseMaterial3D.CULL_DISABLED
			coral.metallic_specular = 0.34
			return coral
		"FlowerWhite":
			var white_flower := _material("flower_white", "", "", Color(0.84, 0.78, 0.65), 0.78)
			white_flower.cull_mode = BaseMaterial3D.CULL_DISABLED
			white_flower.metallic_specular = 0.34
			return white_flower
		"FlowerYellow":
			var yellow_flower := _material("flower_yellow", "", "", Color(0.84, 0.55, 0.07), 0.72)
			yellow_flower.cull_mode = BaseMaterial3D.CULL_DISABLED
			yellow_flower.metallic_specular = 0.34
			return yellow_flower
		"FlowerCentre":
			var flower_centre := _material("flower_centre", "", "", Color(0.52, 0.26, 0.035), 0.82)
			flower_centre.metallic_specular = 0.30
			return flower_centre
		"nh_foliage":
			var foliage := _material("plant_foliage", "foliage.jpg", "foliage_normal.jpg", Color(0.62, 0.86, 0.52), 1.0)
			foliage.cull_mode = BaseMaterial3D.CULL_DISABLED
			return foliage
		"nh_bark":
			return _material("plant_bark", "oak_bark.jpg", "oak_bark_normal.jpg", Color(0.82, 0.72, 0.62), 1.0)
		_:
			return _create_concrete_material("prop_fallback_shader", Color(0.70, 0.70, 0.69), 0.93, 0.78, 0.55, 0.45)


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


func _sail_island_q_0237(x: float, z: float) -> float:
	return Vector2(
		(x - SAIL_ISLAND_CENTRE.x) / SAIL_ISLAND_RADII.x,
		(z - SAIL_ISLAND_CENTRE.y) / SAIL_ISLAND_RADII.y
	).length()


## 0.2.37 Sail Island expansion.  The exported island was only the
## 1110-1250 x 10-150 m zone with dry land roughly 95 x 90 m, and the
## causeway centreline ran to (1180,80) -- the centre of the sail
## podium.  This pass reshapes the same 10 m height grid (visual mesh
## and HeightMapShape3D therefore agree) into a 264 x 216 m elliptical
## resort island, ends the causeway at a new oval loop around the
## hotel, and registers the island's villas/pools before every other
## builder so roads, vegetation, minimap and navigation all see the
## same final layout.
func _expand_sail_island_0237() -> void:
	if _terrain.is_empty():
		return
	var heights: Array = _terrain.get("heights", [])
	var cols := int(_terrain.get("cols", 0))
	var rows := int(_terrain.get("rows", 0))
	if heights.size() < cols * rows or cols < 2 or rows < 2:
		return
	var min_x := _f(_terrain, "minX", 520.0)
	var min_z := _f(_terrain, "minZ", -500.0)
	var step := _f(_terrain, "stepM", 10.0)
	var land_cells := 0
	for iz in rows:
		var z := min_z + float(iz) * step
		for ix in cols:
			var x := min_x + float(ix) * step
			var q := _sail_island_q_0237(x, z)
			if q > 1.08:
				continue
			var index := iz * cols + ix
			var shore_t := clampf((1.0 - q) / 0.30, 0.0, 1.0)
			var shore_s := shore_t * shore_t * (3.0 - 2.0 * shore_t)
			var desired := lerpf(-2.14, 2.14, shore_s)
			heights[index] = maxf(float(heights[index]), desired)
			if float(heights[index]) > 0.05:
				land_cells += 1
	_terrain["heights"] = heights
	data["terrain"] = _terrain

	var zones: Dictionary = data.get("zones", {})
	zones["sailIsland"] = {
		"minX": SAIL_ISLAND_CENTRE.x - SAIL_ISLAND_RADII.x,
		"maxX": SAIL_ISLAND_CENTRE.x + SAIL_ISLAND_RADII.x,
		"minZ": SAIL_ISLAND_CENTRE.y - SAIL_ISLAND_RADII.y,
		"maxZ": SAIL_ISLAND_CENTRE.y + SAIL_ISLAND_RADII.y,
	}
	data["zones"] = zones

	var districts: Array = data.get("districts", [])
	var has_sail_district := false
	for district_variant in districts:
		var district: Dictionary = district_variant
		if String(district.get("id", "")) == "sail-island":
			has_sail_district = true
			break
	if not has_sail_district:
		districts.append({
			"id": "sail-island",
			"name": "Остров Паруса",
			"x": SAIL_ISLAND_CENTRE.x,
			"z": SAIL_ISLAND_CENTRE.y,
			"radiusM": 155.0,
			"biome": "park",
		})
		data["districts"] = districts

	var roads: Array = data.get("roads", [])
	var has_loop := false
	for road_variant in roads:
		var road: Dictionary = road_variant
		var road_id := String(road.get("id", ""))
		if road_id == "rt-sail-loop":
			has_loop = true
		elif road_id == "rt-sail-road":
			var trimmed: Array = []
			for sample_variant in road.get("samples", []):
				var sample: Array = sample_variant
				if sample.size() >= 3 and float(sample[0]) < 1140.0:
					trimmed.append(sample)
			trimmed.append([1140.0, height_at(1140.0, 80.0) + 0.11, 80.0])
			road["samples"] = trimmed
	if not has_loop:
		var loop_samples: Array = []
		var loop_centre := Vector2(1188.0, 80.0)
		for step_index in range(57):
			var angle := PI + TAU * float(step_index) / 56.0
			var px := loop_centre.x + cos(angle) * 48.0
			var pz := loop_centre.y + sin(angle) * 46.0
			loop_samples.append([px, height_at(px, pz) + 0.10, pz])
		roads.append({
			"id": "rt-sail-loop",
			"name": "Sail Island Loop",
			"widthM": 9.0,
			"lanes": 2,
			"speedLimitKmh": 30,
			"closedLoop0238": true,
			"resortRoad0238": true,
			"samples": loop_samples,
		})
		data["roads"] = roads

	var buildings: Array = data.get("buildings", [])
	var resort_villas := 0
	for building_variant in buildings:
		var existing: Dictionary = building_variant
		if bool(existing.get("sail_resort_0237", false)):
			resort_villas += 1
	if resort_villas == 0:
		# 0.2.39: the four repeated 19 m villas become the three
		# approved 36 x 27 m Dubai cottage estates (Models No.10-12).
		# Dense runtime-terrain/road audit: each rotated full-size
		# rectangle stays >=4.4 m clear of the loop asphalt, outside
		# the raised sidewalk band and inside the promenade, with
		# only 0.46-0.60 m of fall across the lot.  Every estate front
		# (+Z) faces the loop centre; the south-west corner stays an
		# open public lookout garden -- no fourth copy is placed.
		for villa_spec in [
			{"x": 1158.0, "z": 18.0, "rotY": 0.450661, "model": "cottage_dune", "h": 8.0, "roofH": 0.90},
			{"x": 1218.0, "z": 18.0, "rotY": -0.450661, "model": "cottage_courtyard", "h": 10.8, "roofH": 0.84},
			{"x": 1218.0, "z": 142.0, "rotY": -2.690931, "model": "cottage_palm", "h": 8.0, "roofH": 0.81},
		]:
			var vx := _f(villa_spec, "x")
			var vz := _f(villa_spec, "z")
			buildings.append({
				"x": vx,
				"y": height_at(vx, vz),
				"z": vz,
				"rotY": _f(villa_spec, "rotY"),
				"w": 35.96,
				"d": 27.01,
				"h": _f(villa_spec, "h", 8.0),
				"roofH": _f(villa_spec, "roofH", 0.85),
				"kind": "rt-cottage-estate",
				"facade": "userPlaster",
				"tint": 1.0,
				"model": String(villa_spec.get("model", "cottage_dune")),
				"sail_resort_0237": true,
				"sail_cottage_0239": true,
			})
			resort_villas += 1
		data["buildings"] = buildings

	var pools: Array = data.get("pools", [])
	var resort_pools := 0
	for pool_variant in pools:
		var existing_pool: Dictionary = pool_variant
		if bool(existing_pool.get("sail_resort_0237", false)):
			resort_pools += 1
	if resort_pools == 0:
		for pool_spec in [
			# 0.2.38: keep the built rims inside the loop with real
			# clearance.  The first east pool touched the inner lane
			# edge, so the generic sanitizer exiled it east of the
			# carriageway (the blue slab in the phone screenshots).
			{"x": 1216.0, "z": 80.0, "w": 16.0, "d": 26.0},
			{"x": 1186.0, "z": 50.0, "w": 34.0, "d": 6.0},
			{"x": 1186.0, "z": 110.0, "w": 34.0, "d": 6.0},
		]:
			var px := _f(pool_spec, "x")
			var pz := _f(pool_spec, "z")
			pools.append({
				"x": px,
				"y": height_at(px, pz) + 0.10,
				"z": pz,
				"rotY": 0.0,
				"w": _f(pool_spec, "w"),
				"d": _f(pool_spec, "d"),
				"sail_resort_0237": true,
			})
			resort_pools += 1
		data["pools"] = pools

	# One exported causeway lamp stood at (1154,73.6), inside the sail
	# podium footprint (x1152-1208, z65-95), so its pole pierced the
	# podium roof.  The loop gets its own lamps in the resort builder.
	var kept_lamps: Array = []
	var removed_podium_lamps := 0
	for lamp_variant in data.get("lamps", []):
		var lamp: Dictionary = lamp_variant
		var lx := _f(lamp, "x")
		var lz := _f(lamp, "z")
		if lx >= 1147.0 and lx <= 1213.0 and lz >= 58.0 and lz <= 102.0:
			removed_podium_lamps += 1
			continue
		kept_lamps.append(lamp)
	data["lamps"] = kept_lamps

	_enhancement_stats["sail_island_expanded_0237"] = true
	_enhancement_stats["sail_island_loop_0237"] = true
	_enhancement_stats["sail_loop_closed_0238"] = true
	_enhancement_stats["sail_island_land_area_m2_0237"] = float(land_cells) * step * step
	_enhancement_stats["sail_island_radii_0237"] = SAIL_ISLAND_RADII
	_enhancement_stats["sail_resort_villas_0237"] = resort_villas
	_enhancement_stats["sail_cottage_estates_placed_0239"] = resort_villas
	_enhancement_stats["sail_resort_pools_0237"] = resort_pools
	_enhancement_stats["sail_removed_podium_lamps_0237"] = removed_podium_lamps


func _canonical_building_footprint_0237(building: Dictionary) -> Vector2:
	var model := String(building.get("model", "generic"))
	var kind := String(building.get("kind", "building"))
	var w := _f(building, "w", 20.0)
	var d := _f(building, "d", 16.0)
	var h := _f(building, "h", 10.0)
	var total_height := maxf(h + _f(building, "roofH"), 5.0)
	if model == "villa":
		return Vector2(19.20, 15.24)
	if model.begins_with("cottage_"):
		# Full fenced estate lot (36 x 27 m with chamfered corners);
		# audit the whole rectangle, not just the house volume.
		return Vector2(35.96, 27.01)
	if model == "glass_tower":
		return Vector2(34.00, 34.00)
	if kind == "rt-villa" and w <= 29.0 and d <= 22.0 and total_height <= 13.0:
		return Vector2(18.87, 16.37)
	if kind == "rt-hotel" and h > 38.0 and w >= 33.0 and w <= 36.0 and d >= 25.0 and d <= 28.0:
		return Vector2(33.60, 26.00)
	if kind == "rt-hotel" and h >= 15.0 and h <= 38.0 and w <= 55.0 and d <= 38.0:
		return Vector2(32.40, 24.60)
	return Vector2(w, d)


func _rect_road_clearance_0237(centre: Vector3, size: Vector2, yaw: float) -> float:
	var basis := Basis(Vector3.UP, yaw)
	var best := INF
	for fx_variant in [-0.5, -0.25, 0.0, 0.25, 0.5]:
		var fx: float = fx_variant
		for fz_variant in [-0.5, -0.25, 0.0, 0.25, 0.5]:
			var fz: float = fz_variant
			var point := centre + basis * Vector3(fx * size.x, 0.0, fz * size.y)
			best = minf(best, _road_clearance_xz(point))
	return best


## Map-wide canonical-building audit.  The phone captures showed the
## Marina hero block's exported parcel overlapping the z430 carriage-
## way; checking every exported building with the footprint of the
## fixed-scale Blender replacement that will actually be built found
## the same class of error on Palm Island.  Any parcel whose real
## footprint comes within 1.6 m of asphalt is shifted by the smallest
## whole offset that clears every road on level, dry terrain.
func _sanitize_canonical_buildings_0237() -> void:
	var relocated := 0
	var unresolved := 0
	var checked := 0
	var minimum_after := INF
	for building_variant in data.get("buildings", []):
		var building: Dictionary = building_variant
		checked += 1
		var centre := _item_position(building)
		var yaw := _f(building, "rotY")
		var footprint := _canonical_building_footprint_0237(building)
		var clearance := _rect_road_clearance_0237(centre, footprint, yaw)
		if clearance >= 1.6:
			minimum_after = minf(minimum_after, clearance)
			continue
		var offsets: Array = [Vector3.ZERO]
		for distance_variant in [2.0, 4.0, 6.0, 8.0, 10.0, 12.0, 14.0, 16.0]:
			var distance: float = distance_variant
			offsets.append_array([
				Vector3(0.0, 0.0, -distance), Vector3(0.0, 0.0, distance),
				Vector3(-distance, 0.0, 0.0), Vector3(distance, 0.0, 0.0),
				Vector3(-distance, 0.0, -distance), Vector3(distance, 0.0, -distance),
				Vector3(-distance, 0.0, distance), Vector3(distance, 0.0, distance),
			])
		var found := false
		var basis := Basis(Vector3.UP, yaw)
		for offset_variant in offsets:
			var offset: Vector3 = offset_variant
			var candidate := Vector3(centre.x + offset.x, 0.0, centre.z + offset.z)
			candidate.y = height_at(candidate.x, candidate.z)
			if candidate.y < 0.7:
				continue
			var candidate_clearance := _rect_road_clearance_0237(candidate, footprint, yaw)
			if candidate_clearance < 1.6:
				continue
			var heights: Array[float] = [candidate.y]
			for local_variant in [Vector3(-0.5, 0.0, -0.5), Vector3(0.5, 0.0, -0.5), Vector3(-0.5, 0.0, 0.5), Vector3(0.5, 0.0, 0.5)]:
				var local: Vector3 = local_variant
				var corner := candidate + basis * Vector3(local.x * footprint.x, 0.0, local.z * footprint.y)
				heights.append(height_at(corner.x, corner.z))
			if heights.max() - heights.min() > 1.2:
				continue
			building["x"] = candidate.x
			building["y"] = candidate.y
			building["z"] = candidate.z
			clearance = candidate_clearance
			relocated += 1
			found = true
			break
		if not found:
			unresolved += 1
		minimum_after = minf(minimum_after, clearance)
	_enhancement_stats["canonical_building_road_clearance_0237"] = unresolved == 0
	_enhancement_stats["canonical_buildings_checked_0237"] = checked
	_enhancement_stats["canonical_buildings_relocated_0237"] = relocated
	_enhancement_stats["canonical_buildings_unresolved_0237"] = unresolved
	_enhancement_stats["canonical_building_min_clearance_0237"] = minimum_after


## Same audit for exported pools: one Palm Island pool lay across
## the rt-palm-2 carriageway.  A relocated pool must clear roads by
## 1.2 m and every sampled point of its rectangle must also clear
## buildings, other pools and landmarks.  0.2.38: the audited
## rectangle is the built concrete rim (water + 1.3 m), not just the
## water plane, and the pool being moved is excluded from its own
## object test -- the old self-overlap rejection threw the Sail
## Island east pool 32 m outside the loop into the grass.
func _sanitize_canonical_pools_0237() -> void:
	var relocated := 0
	var unresolved := 0
	var minimum_after := INF
	var pools: Array = data.get("pools", [])
	for pool_index in pools.size():
		var pool: Dictionary = pools[pool_index]
		var centre := _item_position(pool)
		var yaw := _f(pool, "rotY")
		var size := Vector2(_f(pool, "w", 8.0) + 1.3, _f(pool, "d", 5.0) + 1.3)
		var clearance := _rect_road_clearance_0237(centre, size, yaw)
		if clearance >= 1.2:
			minimum_after = minf(minimum_after, clearance)
			continue
		var found := false
		var basis := Basis(Vector3.UP, yaw)
		for distance_variant in [4.0, 8.0, 12.0, 16.0, 20.0, 24.0, 28.0, 32.0]:
			var distance: float = distance_variant
			for offset in [Vector3(0.0, 0.0, -distance), Vector3(0.0, 0.0, distance), Vector3(-distance, 0.0, 0.0), Vector3(distance, 0.0, 0.0), Vector3(-distance, 0.0, -distance), Vector3(distance, 0.0, -distance), Vector3(-distance, 0.0, distance), Vector3(distance, 0.0, distance)]:
				var candidate := Vector3(centre.x + offset.x, 0.0, centre.z + offset.z)
				candidate.y = height_at(candidate.x, candidate.z)
				if candidate.y < 0.7:
					continue
				var candidate_clearance := _rect_road_clearance_0237(candidate, size, yaw)
				if candidate_clearance < 1.2:
					continue
				var clear_of_objects := true
				for fx_variant in [-0.5, -0.25, 0.0, 0.25, 0.5]:
					var fx: float = fx_variant
					for fz_variant in [-0.5, -0.25, 0.0, 0.25, 0.5]:
						var fz: float = fz_variant
						var point := candidate + basis * Vector3(fx * size.x, 0.0, fz * size.y)
						point.y = height_at(point.x, point.z)
						if not _is_position_clear(point, 0.35, 0.0, true, pool_index):
							clear_of_objects = false
							break
					if not clear_of_objects:
						break
				if not clear_of_objects:
					continue
				pool["x"] = candidate.x
				pool["y"] = candidate.y + 0.12
				pool["z"] = candidate.z
				clearance = candidate_clearance
				relocated += 1
				found = true
				break
			if found:
				break
		if not found:
			unresolved += 1
		minimum_after = minf(minimum_after, clearance)
	_enhancement_stats["canonical_pool_road_clearance_0237"] = unresolved == 0
	_enhancement_stats["canonical_pools_relocated_0237"] = relocated
	_enhancement_stats["canonical_pools_unresolved_0237"] = unresolved
	_enhancement_stats["canonical_pool_min_clearance_0237"] = minimum_after
	_enhancement_stats["canonical_pool_rim_clearance_0238"] = unresolved == 0
	_enhancement_stats["canonical_pool_self_excluded_0238"] = true


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
	if _is_forest:
		# GreenForest splat: grey rock on cliffs/summits, ploughed soil
		# on the authored field rectangles, wet mud in the swamp and on
		# lake shores, needle floor under the forest zones, meadow
		# grass everywhere else.
		if slope > 0.34 or h > 136.0:
			return "gf_rock"
		if _gf_in_field(x, z):
			return "gf_field"
		if _in_zone(x, z, "swamp"):
			return "gf_mud"
		if h < 15.6 and _in_zone(x, z, "gfLake"):
			return "gf_mud"
		if _in_zone(x, z, "darkForest") or _in_zone(x, z, "hills") or _in_zone(x, z, "birchGrove") or _in_zone(x, z, "sawmill") or _in_zone(x, z, "cliff"):
			return "gf_forest_floor"
		return "gf_meadow"
	if _is_desert:
		# Desert splat (spec: asphalt/gravel handled by roads, the other
		# four layers live here): salt pan, red rock, soft dune sand and
		# packed cracked dirt.  The oasis bowl stays packed dirt so the
		# green scatter reads against earth, not loose dune sand.
		if _in_zone(x, z, "salt") and h < 35.4:
			return "salt"
		if Vector2(x - 3350.0, z - 3500.0).length() < 430.0:
			# The oasis bowl overlaps the dune zone rectangle; keep its
			# packed-earth shore so the green scatter reads against soil.
			return "packed"
		if _in_zone(x, z, "dunes"):
			# Dune slip faces are intentionally steep (sampled slopes can
			# exceed 1.0 on the 8 m grid).  They are still sand, not rock:
			# classifying them by the generic slope gate produced a hard
			# black/orange checkerboard across every ridge in the sunset
			# screenshot audit.  Rocky outcrops in the dune sea come from
			# scatter boulders, not from the terrain splat.
			return "dune"
		if slope > 0.30 or h > 108.0:
			return "rock"
		if _in_zone(x, z, "quarry") and slope < 0.22:
			return "gravel"
		return "packed"
	if _is_in_park(x, z):
		return "grass"
	var in_focus_promenade := z >= -100.0 and z <= 52.0 and ((x >= 682.0 and x <= 744.0) or (x >= 776.0 and x <= 790.0))
	var in_boulevard_promenade := z >= -430.0 and z <= 430.0 and ((x >= 730.0 and x < 749.0) or (x > 771.0 and x <= 790.0))
	var in_promenade := in_focus_promenade or in_boulevard_promenade
	if _in_zone(x, z, "rtPlaza") or in_promenade:
		return "plaza"
	if (_in_zone(x, z, "sea") or _in_zone(x, z, "marina")) and h < 0.5:
		return "sand"
	if _in_zone(x, z, "beach") and h < 3.45:
		return "sand"
	if slope > 0.34 or h > 17.0:
		return "rock"
	if _in_zone(x, z, "sailIsland"):
		# Landscaped resort core, then a narrow grass/sand transition,
		# then the beach ring -- not the old 10 m sand/grass checker.
		var sail_q := _sail_island_q_0237(x, z)
		if sail_q <= 0.78:
			return "grass"
		if sail_q <= 0.90:
			return "grass" if _hash01(ix * 7 + 3, iz * 11 + 5) < 0.35 else "sand"
		return "sand"
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
			instance.custom_aabb = _active_aabb
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
	_sea_material.set_shader_parameter("wave_height", 0.22 if _is_forest else (0.16 if _is_desert else 0.62))
	_sea_material.set_shader_parameter("wind_direction", Vector2(0.82, 0.57))
	_sea_material.set_shader_parameter("foam_strength", 0.28 if _is_forest else (0.36 if _is_desert else 0.66))
	_sea_material.set_shader_parameter("normal_strength", 0.74 if _is_forest else (0.50 if _is_desert else 0.78))
	# 0.2.56: the forest lake read as a milky sky mirror; lower the
	# reflection mix and roughen the normals so the deep water colour
	# carries the surface instead.
	_sea_material.set_shader_parameter("reflection_strength", 0.58 if _is_forest else (0.88 if _is_desert else 0.82))
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
		# 0.2.38: a closed chain (the Sail Island oval) repeats its
		# first sample at the end.  Give both copies of that seam the
		# same through-tangent; using only the outgoing segment at
		# the start and only the incoming segment at the end twisted
		# the ribbon edges into a small wedge at the entry junction.
		var is_closed_loop := points.size() > 3 and points[0].distance_to(points[points.size() - 1]) < 0.05
		for i in points.size():
			var direction := Vector3.ZERO
			if i == 0:
				direction = points[1] - (points[points.size() - 2] if is_closed_loop else points[0])
			elif i == points.size() - 1:
				direction = (points[1] if is_closed_loop else points[i]) - points[i - 1]
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

	var sidewalk_material := _create_concrete_material(
		"sidewalk_shader",
		Color(0.52, 0.53, 0.52),
		0.96,
		0.92,
		1.0,
		0.62
	)
	_sidewalk_mesh = _build_road_mesh(1.9, 0.050, 7.0)
	if _sidewalk_mesh != null:
		var sidewalks := _mesh_instance(roads_root, _sidewalk_mesh, sidewalk_material, Transform3D.IDENTITY, "Sidewalks", false)
		sidewalks.custom_aabb = _active_aabb

	# Plain (not dashed) user asphalt feeds the adapted Drive wet_asphalt
	# shader. Lane paint is real geometry below, so it no longer depends on
	# a baked centre line stretched across roads of different widths.
	var asphalt_material := _create_asphalt_material()
	_road_mesh = _build_road_mesh(0.0, ROAD_SURFACE_OFFSET_M, 18.0, ROAD_CROWN_M)
	if _road_mesh != null:
		var roads := _mesh_instance(roads_root, _road_mesh, asphalt_material, Transform3D.IDENTITY, "Asphalt", false)
		roads.custom_aabb = _active_aabb
	_enhancement_stats["ground_winding_godot_cw"] = bool(get_road_visual_state().get("ground_winding_godot_cw", false))

	_build_intersection_pads(roads_root, asphalt_material)
	_build_rounded_intersection_returns(roads_root, asphalt_material)
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
	var rejected_fake_junctions := 0
	for vertical_variant in vertical_roads:
		var vertical: Dictionary = vertical_variant
		var center_x := float(vertical.get("x", 760.0))
		var width := float(vertical.get("width", 12.0))
		for z_variant in cross_z:
			var center_z := float(z_variant)
			var cross_width := 16.0 if absf(center_z - 225.0) <= 0.1 else 13.0
			var arms := _junction_arm_mask(Vector3(center_x, 0.0, center_z), width * 0.5, cross_width * 0.5)
			if not _junction_has_both_axes(arms):
				rejected_fake_junctions += 1
				continue
			var y := height_at(center_x, center_z) + ROAD_SURFACE_OFFSET_M + 0.007
			# Build the pad as the union of the two carriageway
			# strips that actually exist.  One full rectangle filled
			# the missing quadrant of L-corners with an asphalt patch
			# on sand/grass.  The horizontal strip is 1 mm higher so
			# the intentional central overlap cannot z-fight.
			var half_width := width * 0.5
			var cross_half := cross_width * 0.5
			var z_min := -cross_half if bool(arms.get("z_minus", false)) else 0.0
			var z_max := cross_half if bool(arms.get("z_plus", false)) else 0.0
			transforms.append(make_transform(
				Vector3(center_x, y, center_z + (z_min + z_max) * 0.5),
				0.0,
				Vector3(width + 0.04, 0.012, z_max - z_min + 0.04)
			))
			var x_min := -half_width if bool(arms.get("x_minus", false)) else 0.0
			var x_max := half_width if bool(arms.get("x_plus", false)) else 0.0
			transforms.append(make_transform(
				Vector3(center_x + (x_min + x_max) * 0.5, y + 0.001, center_z),
				0.0,
				Vector3(x_max - x_min + 0.04, 0.012, cross_width + 0.04)
			))
	# 0.2.38 Sail Island entry: the 10 m causeway meets the closed
	# 9 m oval at its westernmost point (1140,80), where the loop
	# tangent is north-south.  The city-grid loop above cannot see
	# that T-junction, so the two ribbons simply overlapped with
	# coplanar patches at the seam.  One pad over the exact union
	# box (loop width x causeway width) gives the entry a single
	# asphalt surface; its height follows the loop samples, which
	# are registered 0.10 m above the reshaped island plateau.
	transforms.append(make_transform(
		Vector3(1140.0, height_at(1140.0, 80.0) + 0.202, 80.0),
		0.0,
		Vector3(9.04, 0.012, 10.04)
	))
	var pad_mesh := BoxMesh.new()
	pad_mesh.size = Vector3.ONE
	pad_mesh.material = asphalt_material
	_add_multimesh(parent, pad_mesh, asphalt_material, transforms, "IntersectionPads", false)
	_enhancement_stats["intersection_pads"] = transforms.size()
	_enhancement_stats["rejected_fake_junction_pads_0236"] = rejected_fake_junctions
	_enhancement_stats["real_junction_arms_0236"] = true
	_enhancement_stats["sail_loop_entry_pad_0238"] = true



## 0.2.24 rounded kerb returns.  Every exported carriageway is a straight
## axial ribbon, so junctions used to meet as literal rectangles with
## square 90-degree kerb corners.  For each real junction quadrant this
## builds the missing turning geometry: a tangent quarter-arc of asphalt
## between the two road edges plus short curb boxes that follow the arc.
## Quadrant arms are probed against the road-surface index, so T-junctions
## only receive returns on the side where both carriageways actually run.
func _build_rounded_intersection_returns(parent: Node, asphalt_material: ShaderMaterial) -> void:
	var specs: Array[Dictionary] = []
	var vertical_roads := [
		{"x": 560.0, "width": 11.0},
		{"x": 760.0, "width": 22.0},
		{"x": 930.0, "width": 24.0},
	]
	var cross_z := [-430.0, -300.0, -250.0, -110.0, 60.0, 225.0, 430.0]
	for vertical_variant in vertical_roads:
		var vertical: Dictionary = vertical_variant
		for z_variant in cross_z:
			var z_value := float(z_variant)
			if is_equal_approx(float(vertical.get("x", 0.0)), 930.0) and is_equal_approx(z_value, 225.0):
				continue # No east-west street reaches the Corniche at z=225.
			specs.append({
				"x": float(vertical.get("x", 760.0)),
				"z": z_value,
				"a": float(vertical.get("width", 12.0)) * 0.5,
				"b": (16.0 if is_equal_approx(z_value, 225.0) else 13.0) * 0.5,
			})
	specs.append({"x": 930.0, "z": 80.0, "a": 12.0, "b": 5.0}) # Sail causeway T.
	specs.append({"x": 1395.0, "z": -250.0, "a": 4.5, "b": 5.5}) # Palm trunk/fronds.
	# South Villa District local junctions (0.2.24 synthetic streets).
	for local_x in [638.0, 689.0]:
		for local_z in [225.0, 286.0, 368.0]:
			specs.append({"x": local_x, "z": local_z, "a": 4.0, "b": 4.5 if not is_equal_approx(local_z, 225.0) else 8.0})
	specs.append({"x": 640.5, "z": 430.0, "a": 4.0, "b": 6.5})
	specs.append({"x": 686.0, "z": 430.0, "a": 4.0, "b": 6.5})
	for outer_x in [560.0, 760.0]:
		for local_z in [286.0, 368.0]:
			specs.append({"x": outer_x, "z": local_z, "a": 5.5 if is_equal_approx(outer_x, 560.0) else 11.0, "b": 4.5})

	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var curb_transforms: Array[Transform3D] = []
	var return_count := 0
	var triangle_count := 0
	var junctions_with_returns := 0
	const ARC_STEPS := 7
	for spec in specs:
		var center := Vector3(_f(spec, "x"), 0.0, _f(spec, "z"))
		var a := _f(spec, "a", 5.0)
		var b := _f(spec, "b", 5.0)
		var radius := clampf(minf(a, b) * 0.9, 3.2, 7.0)
		var junction_had_return := false
		for sx_variant in [-1.0, 1.0]:
			var sx := float(sx_variant)
			# The horizontal arm must really extend into this quadrant.
			var h_probe := center + Vector3(sx * (a + radius + 3.0), 0.0, 0.0)
			if _road_clearance_xz(h_probe) > 0.25:
				continue
			for sz_variant in [-1.0, 1.0]:
				var sz := float(sz_variant)
				var v_probe := center + Vector3(0.0, 0.0, sz * (b + radius + 3.0))
				if _road_clearance_xz(v_probe) > 0.25:
					continue
				var arc_center := center + Vector3(sx * (a + radius), 0.0, sz * (b + radius))
				var corner := center + Vector3(sx * a, 0.0, sz * b)
				corner.y = height_at(corner.x, corner.z) + ROAD_SURFACE_OFFSET_M + 0.019
				var arc_points: Array[Vector3] = []
				for step in range(ARC_STEPS + 1):
					var t := float(step) / float(ARC_STEPS)
					# Quarter arc from the vertical-road edge tangent
					# (a, b+R) to the horizontal-road edge tangent
					# (a+R, b) in quadrant-local coordinates.
					var angle := t * PI * 0.5
					var offset := Vector3(-cos(angle) * radius * sx, 0.0, -sin(angle) * radius * sz)
					var arc_point := arc_center + offset
					arc_point.y = height_at(arc_point.x, arc_point.z) + ROAD_SURFACE_OFFSET_M + 0.019
					arc_points.append(arc_point)
				for step in range(ARC_STEPS):
					var v0 := corner
					var v1 := arc_points[step]
					var v2 := arc_points[step + 1]
					if (v1 - v0).cross(v2 - v0).y > 0.0:
						var swap := v1
						v1 = v2
						v2 = swap
					for vertex in [v0, v1, v2]:
						tool.set_normal(Vector3.UP)
						tool.set_uv(Vector2(vertex.x / 18.0, vertex.z / 18.0))
						tool.add_vertex(vertex)
					triangle_count += 1
				for step in range(ARC_STEPS):
					var p0 := arc_points[step]
					var p1 := arc_points[step + 1]
					var tangent := p1 - p0
					tangent.y = 0.0
					var tangent_length := tangent.length()
					if tangent_length < 0.05:
						continue
					var mid := (p0 + p1) * 0.5
					# Straight kerbs are centred 0.20 m outside the
					# carriageway edge.  Offset arc kerbs radially by
					# the same amount instead of centring them on the
					# asphalt edge, where half the box covered the lane
					# and the tangent joint stepped sideways.
					var radial := mid - arc_center
					radial.y = 0.0
					if radial.length_squared() > 0.0001:
						mid += radial.normalized() * 0.20
					curb_transforms.append(make_transform(
						Vector3(mid.x, height_at(mid.x, mid.z) + 0.145, mid.z),
						atan2(tangent.x, tangent.z),
						Vector3(0.26, 0.19, tangent_length + 0.05)
					))
				return_count += 1
				junction_had_return = true
		if junction_had_return:
			junctions_with_returns += 1

	var mesh := tool.commit()
	if mesh != null:
		var instance := _mesh_instance(parent, mesh, asphalt_material, Transform3D.IDENTITY, "RoundedIntersectionReturns", false)
		instance.custom_aabb = _active_aabb
	var curb_mesh := BoxMesh.new()
	curb_mesh.size = Vector3.ONE
	var curb_material := _create_concrete_material(
		"road_curb_shader",
		Color(0.37, 0.38, 0.37),
		0.97,
		0.72,
		0.55,
		0.48
	)
	curb_mesh.material = curb_material
	_add_multimesh(parent, curb_mesh, curb_material, curb_transforms, "RoundedCornerCurbs", true)
	_enhancement_stats["rounded_returns_0224"] = return_count > 0
	_enhancement_stats["rounded_intersection_returns"] = return_count
	_enhancement_stats["rounded_return_triangles"] = triangle_count
	_enhancement_stats["rounded_corner_curbs"] = curb_transforms.size()
	_enhancement_stats["junctions_with_rounded_returns"] = junctions_with_returns
	_enhancement_stats["rounded_curb_edge_alignment_0236"] = true

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
	var boulevard_slab_transforms: Array[Transform3D] = []
	var boulevard_granite_curb_transforms: Array[Transform3D] = []
	var driveway_gaps := 0
	var junction_opening_gaps := 0
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
		var is_boulevard := road_id.begins_with("rt-blvd-")
		var is_sail_loop := road_id == "rt-sail-loop"
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
		var start_junction := _junction_info(points[0], road_id, start_direction)
		var end_junction := _junction_info(points[points.size() - 1], road_id, end_direction)
		var trim_start := float(start_junction.get("trim_m", 0.0))
		var trim_end := float(end_junction.get("trim_m", 0.0))
		# 0.2.36: use the same return-radius formula as the rounded
		# corner builder.  The old fixed +3.6 m trim resumed straight
		# kerbs about 1.35 m before the actual arc tangent on the main
		# grid and much later on local streets, producing the broken
		# corner joints in the user's Corniche screenshots.
		var start_cross_half := float(start_junction.get("cross_half_width_m", 0.0))
		var end_cross_half := float(end_junction.get("cross_half_width_m", 0.0))
		var start_return_radius := clampf(minf(half_width, start_cross_half) * 0.9, 3.2, 7.0) if start_cross_half > 0.0 else 0.0
		var end_return_radius := clampf(minf(half_width, end_cross_half) * 0.9, 3.2, 7.0) if end_cross_half > 0.0 else 0.0
		var edge_trim_start := start_cross_half + start_return_radius if start_cross_half > 0.0 else 0.0
		var edge_trim_end := end_cross_half + end_return_radius if end_cross_half > 0.0 else 0.0
		points = _subdivide_road_points_for_junctions(points, edge_trim_start, edge_trim_end, total_length, road_id)
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
			if segment_end <= edge_trim_start + 0.5 or segment_start >= total_length - edge_trim_end - 0.5:
				continue
			var direction := segment / length
			var side := Vector3(-direction.z, 0.0, direction.x)
			var yaw := atan2(direction.x, direction.z)
			var midpoint := (a + b) * 0.5
			var crown_scale := _road_crown_scale(segment_start + length * 0.5, total_length, trim_start, trim_end)
			var near_junction := (trim_start > 0.0 and segment_start < trim_start + 11.0) or (trim_end > 0.0 and segment_end > total_length - trim_end - 11.0)
			for side_sign_variant in [-1.0, 1.0]:
				var side_sign := float(side_sign_variant)
				# 0.2.24 junction openings: test both segment ends and
				# the midpoint of each edge element against every OTHER
				# carriageway.  A side street joining mid-segment (all
				# new district streets do) now cuts a clean mouth in
				# the gutter/slab/curb instead of leaving a concrete
				# bar across the turning path.
				var gutter_offset := half_width - 0.22
				var gutter_center: Vector3 = midpoint + side * side_sign * gutter_offset
				var gutter_clearance := minf(
					_clearance_to_other_roads(gutter_center, road_id, direction),
					minf(
						_clearance_to_other_roads(a + side * side_sign * gutter_offset, road_id, direction),
						_clearance_to_other_roads(b + side * side_sign * gutter_offset, road_id, direction)
					)
				)
				if gutter_clearance < 0.9:
					junction_opening_gaps += 1
				else:
					gutter_transforms.append(make_transform(
						Vector3(gutter_center.x, _road_surface_y(midpoint.y, gutter_offset, half_width, crown_scale) + 0.006, gutter_center.z),
						yaw,
						Vector3(0.60, 0.016, length + 0.05)
					))

				var slab_offset := half_width + 1.28
				var slab_center: Vector3 = midpoint + side * side_sign * slab_offset
				var slab_clearance := minf(
					_clearance_to_other_roads(slab_center, road_id, direction),
					minf(
						_clearance_to_other_roads(a + side * side_sign * slab_offset, road_id, direction),
						_clearance_to_other_roads(b + side * side_sign * slab_offset, road_id, direction)
					)
				)
				if slab_clearance < 1.8:
					junction_opening_gaps += 1
				else:
					var slab_transform := make_transform(
						Vector3(slab_center.x, midpoint.y + 0.155, slab_center.z),
						yaw,
						Vector3(1.90, 0.15, length + 0.06)
					)
					if is_boulevard:
						boulevard_slab_transforms.append(slab_transform)
					else:
						slab_transforms.append(slab_transform)

				# Random kerb gaps used to appear in the middle of main
				# streets with no driveway behind them.  Keep dropped
				# kerbs only on the low-rise villa/Palm local streets;
				# every arterial kerb is continuous between real
				# junction mouths.
				var has_local_driveways := road_id.contains("villa") or road_id.contains("palm-local")
				var driveway_roll := _hash01(road_index * 197 + i * 13, int(side_sign) * 37 + 101)
				if has_local_driveways and driveway_roll < 0.07 and not near_junction and not is_boulevard:
					driveway_gaps += 1
					continue
				var curb_offset := half_width + 0.20
				var curb_center: Vector3 = midpoint + side * side_sign * curb_offset
				var curb_clearance := minf(
					_clearance_to_other_roads(curb_center, road_id, direction),
					minf(
						_clearance_to_other_roads(a + side * side_sign * curb_offset, road_id, direction),
						_clearance_to_other_roads(b + side * side_sign * curb_offset, road_id, direction)
					)
				)
				if curb_clearance < 2.7:
					junction_opening_gaps += 1
					continue
				var curb_transform := make_transform(
					Vector3(curb_center.x, midpoint.y + 0.145, curb_center.z),
					yaw,
					Vector3(0.26, 0.19, length + 0.05)
				)
				if is_boulevard:
					boulevard_granite_curb_transforms.append(curb_transform)
				elif near_junction and i % 2 == 0 and not is_sail_loop:
					painted_curb_transforms.append(curb_transform)
				else:
					curb_transforms.append(curb_transform)
		road_index += 1

	var slab_material := _create_concrete_material(
		"sidewalk_shader",
		Color(0.52, 0.53, 0.52),
		0.96,
		0.92,
		1.0,
		0.62
	)
	var curb_material := _create_concrete_material(
		"road_curb_shader",
		Color(0.37, 0.38, 0.37),
		0.97,
		0.72,
		0.55,
		0.48
	)
	var painted_curb_material := _create_concrete_material(
		"road_curb_painted_shader",
		Color(0.72, 0.48, 0.08),
		0.91,
		0.72,
		0.35,
		0.40
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
	var boulevard_granite_material := _material("boulevard_granite", "user_black_granite.jpg", "user_black_granite_normal.jpg", Color(0.66, 0.68, 0.69), 0.34, 0.12, Vector3(0.35, 0.35, 0.35), true)
	boulevard_granite_material.normal_scale = 0.52
	boulevard_granite_material.metallic_specular = 0.82
	var boulevard_slab_material := _create_premium_paving_material(
		"terrain_premium_pavers_shader",
		Color(0.84, 0.80, 0.70),
		0.68,
		0.140,
		0.50
	)
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3.ONE
	box_mesh.material = slab_material
	_add_multimesh(parent, box_mesh, gutter_material, gutter_transforms, "RoadGutters", false)
	_add_multimesh(parent, box_mesh, curb_material, curb_transforms, "RoadCurbs", true)
	_add_multimesh(parent, box_mesh, painted_curb_material, painted_curb_transforms, "RoadPaintedCurbs", true)
	_add_multimesh(parent, box_mesh, slab_material, slab_transforms, "RaisedSidewalkSlabs", true)
	_add_multimesh(parent, box_mesh, boulevard_granite_material, boulevard_granite_curb_transforms, "BoulevardGraniteCurbs", true)
	_add_multimesh(parent, box_mesh, boulevard_slab_material, boulevard_slab_transforms, "BoulevardPremiumSidewalkSlabs", true)
	_enhancement_stats["road_gutters"] = gutter_transforms.size()
	_enhancement_stats["concrete_curbs"] = curb_transforms.size() + painted_curb_transforms.size() + boulevard_granite_curb_transforms.size()
	_enhancement_stats["painted_curbs"] = painted_curb_transforms.size()
	_enhancement_stats["raised_sidewalk_slabs"] = slab_transforms.size() + boulevard_slab_transforms.size()
	_enhancement_stats["boulevard_granite_curbs"] = boulevard_granite_curb_transforms.size()
	_enhancement_stats["boulevard_premium_sidewalk_slabs"] = boulevard_slab_transforms.size()
	_enhancement_stats["driveway_curb_gaps"] = driveway_gaps
	_enhancement_stats["junction_edge_openings_0224"] = junction_opening_gaps
	_enhancement_stats["road_junction_subsegments_0236"] = _road_junction_subsegments_0236
	_enhancement_stats["continuous_arterial_curbs_0236"] = true


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
	var boulevard_edge_transforms: Array[Transform3D] = []
	var bike_transforms: Array[Transform3D] = []
	var tactile_transforms: Array[Transform3D] = []
	var lane_arrow_count := 0
	var boulevard_fresh_markings := 0
	var junction_paint_breaks := 0
	var sail_loop_center_dashes := 0
	var road_index := 0

	for road_variant in data.get("roads", []):
		var road: Dictionary = road_variant
		var road_id := String(road.get("id", ""))
		var is_boulevard := road_id.begins_with("rt-blvd-")
		var is_sail_loop := road_id == "rt-sail-loop"
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
		if is_sail_loop:
			# 0.2.38 resort-ring paint: one broken white centreline
			# (the dash pass below) instead of a double-yellow solid
			# pair wrapped around a tight 9 m oval.
			divider_offsets = [0.0]
		var points: Array[Vector3] = []
		for sample in samples:
			points.append(_sample_point(sample))
		var total_length := 0.0
		for point_index in range(points.size() - 1):
			var flat_segment := points[point_index + 1] - points[point_index]
			flat_segment.y = 0.0
			total_length += flat_segment.length()
		var is_closed_loop := points.size() > 3 and points[0].distance_to(points[points.size() - 1]) < 0.05
		var start_direction := points[1] - points[0]
		var end_direction := points[points.size() - 1] - points[points.size() - 2]
		var start_info := _junction_info(points[0], road_id, start_direction)
		var end_info := _junction_info(points[points.size() - 1], road_id, end_direction)
		var trim_start := float(start_info.get("trim_m", 0.0))
		var trim_end := float(end_info.get("trim_m", 0.0))
		points = _subdivide_road_points_for_junctions(points, trim_start, trim_end, total_length, road_id)
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
			# 0.2.24: a street crossing mid-segment is invisible to the
			# endpoint trims above; without this test the double-yellow
			# centreline and edge paint ran straight through the new
			# district junctions.
			if _clearance_to_other_roads(midpoint, road_id, direction) < 1.1:
				near_edge_break = true
				near_paint_break = true
				junction_paint_breaks += 1

			if not near_edge_break:
				for edge_side_variant in [-1.0, 1.0]:
					var edge_side := float(edge_side_variant)
					var edge_offset := edge_side * maxf(half_width - 0.42, 0.6)
					var edge_center: Vector3 = midpoint + side * edge_offset
					var edge_transform := make_transform(
						Vector3(edge_center.x, _road_surface_y(midpoint.y, edge_offset, half_width, crown_scale) + 0.019, edge_center.z),
						yaw,
						Vector3(0.20 if is_boulevard else 0.16, 0.034, length + 0.05)
					)
					if is_boulevard:
						# Reference-corridor treatment: both kerb lines
						# are fresh yellow, framing the dark resurfaced
						# carriageway in perspective.
						boulevard_edge_transforms.append(edge_transform)
						boulevard_fresh_markings += 1
					else:
						var edge_group := mini(2, int(_hash01(road_index * 271 + i * 11, int(edge_side) * 43 + 17) * 3.0))
						(edge_groups[edge_group] as Array).append(edge_transform)

			if not near_paint_break:
				# Opposing traffic is separated by a double yellow solid
				# centreline. White dashes below are only between lanes
				# travelling in the same direction.  The Sail resort
				# ring is the one exception: it uses the single broken
				# centre dash configured above.
				if not is_sail_loop:
					for center_offset_variant in [-0.18, 0.18]:
						var center_offset := float(center_offset_variant)
						var center_point: Vector3 = midpoint + side * center_offset
						var center_group := 0 if is_boulevard or _hash01(road_index * 149 + i * 7, 91) < 0.68 else 1
						(center_groups[center_group] as Array).append(make_transform(
							Vector3(center_point.x, _road_surface_y(midpoint.y, center_offset, half_width, crown_scale) + 0.018, center_point.z),
							yaw,
							Vector3(0.16 if is_boulevard else 0.145, 0.032, length + 0.04)
						))
						if is_boulevard:
							boulevard_fresh_markings += 1

				for lane_offset in divider_offsets:
					# Do not turn the finely split junction pieces into
					# a dotted line, and do not randomly delete whole
					# dashes elsewhere: wear is represented by the
					# paint shade, while the dash rhythm stays legible.
					if length < 2.6:
						continue
					var wear_roll := _hash01(road_index * 331 + i * 19, int(lane_offset * 10.0) + 53)
					var dash_center: Vector3 = midpoint + side * lane_offset
					var dash_group := 0 if is_boulevard else mini(2, int(wear_roll * 3.0))
					var dash_length := minf(3.0, length * 0.52)
					(dash_groups[dash_group] as Array).append(make_transform(
						Vector3(dash_center.x, _road_surface_y(midpoint.y, lane_offset, half_width, crown_scale) + 0.020, dash_center.z),
						yaw,
						Vector3(0.18 if is_boulevard else 0.17, 0.036, dash_length)
					))
					if is_boulevard:
						boulevard_fresh_markings += 1
					if is_sail_loop:
						sail_loop_center_dashes += 1

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

			if has_bike_lane and not near_paint_break:
				# The seaward side of the Corniche is world +X regardless
				# of the exported chain direction.  Stop both the green
				# surface and its white boundary at junction/crosswalk
				# paint breaks; previously the dark-green band continued
				# straight through the intersection box.
				var seaward_sign := 1.0 if side.x >= 0.0 else -1.0
				var bike_offset := seaward_sign * (half_width - 1.24)
				var bike_center: Vector3 = midpoint + side * bike_offset
				bike_transforms.append(make_transform(
					Vector3(bike_center.x, _road_surface_y(midpoint.y, bike_offset, half_width, crown_scale) + 0.007, bike_center.z),
					yaw,
					Vector3(1.52, 0.018, length + 0.03)
				))
				# (boundary line follows below under the same guard)
				if true:
					var bike_line_offset := seaward_sign * (half_width - 2.06)
					var bike_line_center: Vector3 = midpoint + side * bike_line_offset
					var bike_group := mini(2, int(_hash01(road_index * 181 + i * 29, 73) * 3.0))
					(edge_groups[bike_group] as Array).append(make_transform(
						Vector3(bike_line_center.x, _road_surface_y(midpoint.y, bike_line_offset, half_width, crown_scale) + 0.018, bike_line_center.z),
						yaw,
						Vector3(0.14, 0.032, length + 0.04)
					))

		# Closed chains have no distinct start/end approach: the
		# generic arrow pass extrapolated a straight 15 m chord from
		# the seam and painted arrows across the oval's forecourt.
		if total_length > 34.0 and not is_closed_loop:
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
						var arrow_group := 0 if is_boulevard else mini(2, int(_hash01(road_index * 211, int(lane_offset * 10.0) + 31) * 3.0))
						_append_lane_arrow(
							arrow_groups[arrow_group] as Array,
							lane_center,
							-chain_direction,
							_road_surface_y(points[0].y, lane_offset, half_width, start_crown)
						)
						lane_arrow_count += 1
						if is_boulevard:
							boulevard_fresh_markings += 1
				if bool(end_info.get("is_junction", false)):
					var end_centerline: Vector3 = points[points.size() - 1] - chain_direction * 15.0
					var end_crown := _road_crown_scale(total_length - 15.0, total_length, trim_start, trim_end)
					for lane_offset in lane_centers:
						if lane_offset <= 0.0:
							continue
						var lane_center: Vector3 = end_centerline + chain_side * lane_offset
						var arrow_group := 0 if is_boulevard else mini(2, int(_hash01(road_index * 223 + 7, int(lane_offset * 10.0) + 37) * 3.0))
						_append_lane_arrow(
							arrow_groups[arrow_group] as Array,
							lane_center,
							chain_direction,
							_road_surface_y(points[points.size() - 1].y, lane_offset, half_width, end_crown)
						)
						lane_arrow_count += 1
						if is_boulevard:
							boulevard_fresh_markings += 1
				if is_boulevard:
					var boulevard_arrow_distance := 42.0
					while boulevard_arrow_distance < total_length - 32.0:
						var boulevard_centerline: Vector3 = points[0] + chain_direction * boulevard_arrow_distance
						var boulevard_crown := _road_crown_scale(boulevard_arrow_distance, total_length, trim_start, trim_end)
						for lane_offset in lane_centers:
							var boulevard_lane_center: Vector3 = boulevard_centerline + chain_side * lane_offset
							var boulevard_lane_direction := chain_direction if lane_offset > 0.0 else -chain_direction
							_append_lane_arrow(
								arrow_groups[0] as Array,
								boulevard_lane_center,
								boulevard_lane_direction,
								_road_surface_y(height_at(boulevard_lane_center.x, boulevard_lane_center.z), lane_offset, half_width, boulevard_crown)
							)
							lane_arrow_count += 1
							boulevard_fresh_markings += 1
						boulevard_arrow_distance += 58.0
		road_index += 1

	var vertical_roads := [
		{"x": 560.0, "width": 11.0},
		{"x": 760.0, "width": 22.0},
		{"x": 930.0, "width": 24.0},
	]
	var cross_z := [-430.0, -300.0, -250.0, -110.0, 60.0, 225.0, 430.0]
	var rejected_crosswalk_groups := 0
	var rejected_crosswalk_stripes := 0
	var real_crosswalk_groups := 0

	for vertical_variant in vertical_roads:
		var vertical: Dictionary = vertical_variant
		var center_x := float(vertical.get("x", 760.0))
		var width := float(vertical.get("width", 12.0))
		for z_variant in cross_z:
			var center_z := float(z_variant)
			var cross_width := 16.0 if absf(center_z - 225.0) < 0.1 else 13.0
			var junction_center := Vector3(center_x, 0.0, center_z)
			var arms := _junction_arm_mask(junction_center, width * 0.5, cross_width * 0.5)
			if not _junction_has_both_axes(arms):
				rejected_crosswalk_groups += 4
				continue
			# Zebra crossings on each real approach to the vertical road.
			for side_variant in [-1.0, 1.0]:
				var side := float(side_variant)
				if not bool(arms.get("z_plus" if side > 0.0 else "z_minus", false)):
					rejected_crosswalk_groups += 1
					continue
				real_crosswalk_groups += 1
				var crossing_z: float = center_z + side * (cross_width * 0.5 + 2.35)
				var stripe_count := maxi(int(floor((width - 1.4) / 1.08)), 3)
				var start_x := center_x - float(stripe_count - 1) * 0.54
				for i in stripe_count:
					var wear_roll := _hash01(int(center_x) + i * 17, int(crossing_z) + 431)
					var x := start_x + float(i) * 1.08
					if _road_clearance_xz(Vector3(x, 0.0, crossing_z)) > -0.30:
						rejected_crosswalk_stripes += 1
						continue
					var y := _road_surface_y(height_at(x, crossing_z), x - center_x, width * 0.5, 0.34) + 0.016
					var stripe_group := 0 if is_equal_approx(center_x, 760.0) else mini(2, int(wear_roll * 3.0))
					(stripe_groups[stripe_group] as Array).append(make_transform(
						Vector3(x, y, crossing_z),
						0.0,
						Vector3(0.58, 0.028, 3.15 * (0.96 + 0.06 * wear_roll))
					))
					if is_equal_approx(center_x, 760.0):
						boulevard_fresh_markings += 1
				var stop_z: float = crossing_z + side * 2.15
				var stop_center_x := center_x + side * width * 0.25
				if _road_clearance_xz(Vector3(stop_center_x, 0.0, stop_z)) <= -0.30:
					var stop_group := 0 if is_equal_approx(center_x, 760.0) else mini(2, int(_hash01(int(stop_center_x), int(stop_z) + 907) * 3.0))
					(stripe_groups[stop_group] as Array).append(make_transform(
						Vector3(stop_center_x, _road_surface_y(height_at(stop_center_x, stop_z), width * 0.25, width * 0.5, 0.64) + 0.016, stop_z),
						0.0,
						Vector3(width * 0.48, 0.028, 0.42)
					))
				for end_sign_variant in [-1.0, 1.0]:
					var end_sign := float(end_sign_variant)
					# Tactile paving belongs on the formed corner where
					# the crossing street's sidewalk actually exists.
					# On the beach side of a Corniche T-junction that
					# corner is absent, so do not float a yellow pad on
					# sand just because the through road has a slab.
					if not bool(arms.get("x_plus" if end_sign > 0.0 else "x_minus", false)):
						continue
					var tactile_x := center_x + end_sign * (width * 0.5 + 0.95)
					tactile_transforms.append(make_transform(
						Vector3(tactile_x, height_at(tactile_x, crossing_z) + 0.242, crossing_z),
						0.0,
						Vector3(0.95, 0.024, 0.75)
					))

			# Matching zebras across each real horizontal approach.
			for side_variant in [-1.0, 1.0]:
				var side := float(side_variant)
				if not bool(arms.get("x_plus" if side > 0.0 else "x_minus", false)):
					rejected_crosswalk_groups += 1
					continue
				real_crosswalk_groups += 1
				var crossing_x: float = center_x + side * (width * 0.5 + 2.35)
				var stripe_count_h := maxi(int(floor((cross_width - 1.4) / 1.08)), 3)
				var start_z := center_z - float(stripe_count_h - 1) * 0.54
				for i in stripe_count_h:
					var wear_roll := _hash01(int(crossing_x) + 613, int(center_z) + i * 19)
					var z := start_z + float(i) * 1.08
					if _road_clearance_xz(Vector3(crossing_x, 0.0, z)) > -0.30:
						rejected_crosswalk_stripes += 1
						continue
					var y := _road_surface_y(height_at(crossing_x, z), z - center_z, cross_width * 0.5, 0.34) + 0.016
					var stripe_group := 0 if is_equal_approx(center_x, 760.0) else mini(2, int(wear_roll * 3.0))
					(stripe_groups[stripe_group] as Array).append(make_transform(
						Vector3(crossing_x, y, z),
						0.0,
						Vector3(3.15 * (0.96 + 0.06 * wear_roll), 0.028, 0.58)
					))
					if is_equal_approx(center_x, 760.0):
						boulevard_fresh_markings += 1
				var stop_x: float = crossing_x + side * 2.15
				var stop_center_z := center_z - side * cross_width * 0.25
				if _road_clearance_xz(Vector3(stop_x, 0.0, stop_center_z)) <= -0.30:
					var stop_group := 0 if is_equal_approx(center_x, 760.0) else mini(2, int(_hash01(int(stop_x) + 719, int(stop_center_z)) * 3.0))
					(stripe_groups[stop_group] as Array).append(make_transform(
						Vector3(stop_x, _road_surface_y(height_at(stop_x, stop_center_z), cross_width * 0.25, cross_width * 0.5, 0.64) + 0.016, stop_center_z),
						0.0,
						Vector3(0.42, 0.028, cross_width * 0.48)
					))
				for end_sign_variant in [-1.0, 1.0]:
					var end_sign := float(end_sign_variant)
					if not bool(arms.get("z_plus" if end_sign > 0.0 else "z_minus", false)):
						continue
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
	edge_total += boulevard_edge_transforms.size()
	_add_multimesh(parent, stripe_mesh, yellow_paints[0], boulevard_edge_transforms, "BoulevardYellowEdgeLines", false, -1.0, 380.0, 220.0)
	_add_multimesh(parent, stripe_mesh, bike_material, bike_transforms, "BikeLaneSurfaces", false)
	_add_multimesh(parent, stripe_mesh, tactile_material, tactile_transforms, "TactilePaving", false)

	_enhancement_stats["crosswalk_markings"] = stripe_total
	_enhancement_stats["road_edge_lines"] = edge_total
	_enhancement_stats["lane_dashes"] = dash_total
	_enhancement_stats["center_lines"] = center_total
	_enhancement_stats["lane_arrows"] = lane_arrow_count
	_enhancement_stats["sail_loop_center_dashes_0238"] = sail_loop_center_dashes
	_enhancement_stats["sail_loop_clean_markings_0238"] = sail_loop_center_dashes >= 40
	_enhancement_stats["boulevard_fresh_markings"] = boulevard_fresh_markings
	_enhancement_stats["boulevard_yellow_edge_lines"] = boulevard_edge_transforms.size()
	_enhancement_stats["parking_markings"] = parking_total
	_enhancement_stats["bike_lane_segments"] = bike_transforms.size()
	_enhancement_stats["tactile_paving"] = tactile_transforms.size()
	_enhancement_stats["road_markings"] = stripe_total + edge_total + dash_total + center_total + arrow_total + parking_total
	_enhancement_stats["junction_paint_breaks_0224"] = junction_paint_breaks
	_enhancement_stats["real_crosswalk_groups_0236"] = real_crosswalk_groups
	_enhancement_stats["rejected_fake_crosswalks_0236"] = rejected_crosswalk_groups
	_enhancement_stats["rejected_offroad_crosswalk_stripes_0236"] = rejected_crosswalk_stripes
	_enhancement_stats["bike_lane_junction_breaks_0236"] = true
	_enhancement_stats["road_infrastructure_repair_0236"] = true


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
	var sail_loop_seen := false
	var bridge_ids := ["rt-palm-1", "rt-sail-road"]

	for road_variant in data.get("roads", []):
		var road: Dictionary = road_variant
		var road_id := String(road.get("id", ""))
		var is_sail_loop := road_id == "rt-sail-loop"
		if is_sail_loop:
			sail_loop_seen = true
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
			if is_sail_loop:
				# Pristine resort asphalt: no random black repair
				# rectangles, tar seams or oil in the driving lanes.
				detail_roll = 1.0
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
					Vector3(1.3 + lane_roll * 0.9, 0.014, 2.4 + detail_roll * 14.0)
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
					Vector3(0.72 + lane_roll * 0.55, 0.012, 1.5 + detail_roll * 2.2)
				))

			var add_studs := not is_sail_loop and ((width >= 17.0 and i % 2 == 0) or (width < 17.0 and i % 3 == 0))
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

		if not is_sail_loop and total_length > 45.0 and _hash01(road_index * 521, 71) < 0.62:
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
	var rejected_signal_approaches := 0
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
			var arms := _junction_arm_mask(Vector3(center_x, 0.0, center_z), vertical_half, cross_half)
			if not _junction_has_both_axes(arms):
				rejected_signal_approaches += 4
				continue
			var approaches := [
				{"head": Vector2(vertical_width * 0.25, -(cross_half + 1.0)), "arm_dir": Vector2(-1.0, 0.0), "yaw": PI, "long": vertical_width >= 17.0, "approach_arm": "z_minus"},
				{"head": Vector2(-vertical_width * 0.25, cross_half + 1.0), "arm_dir": Vector2(1.0, 0.0), "yaw": 0.0, "long": vertical_width >= 17.0, "approach_arm": "z_plus"},
				{"head": Vector2(vertical_half + 1.0, cross_width * 0.25), "arm_dir": Vector2(0.0, -1.0), "yaw": PI * 0.5, "long": cross_width >= 16.0, "approach_arm": "x_plus"},
				{"head": Vector2(-(vertical_half + 1.0), -cross_width * 0.25), "arm_dir": Vector2(0.0, 1.0), "yaw": -PI * 0.5, "long": cross_width >= 16.0, "approach_arm": "x_minus"},
			]
			for approach_variant in approaches:
				var approach: Dictionary = approach_variant
				var head_offset: Vector2 = approach.get("head", Vector2.ZERO)
				var arm_dir: Vector2 = approach.get("arm_dir", Vector2.RIGHT)
				var is_long := bool(approach.get("long", false))
				if not bool(arms.get(String(approach.get("approach_arm", "")), false)):
					rejected_signal_approaches += 1
					continue
				# The far/only Blender signal head is 4.18 m from the
				# short pole and 6.68 m from the long pole.
				var head_reach := 6.68 if is_long else 4.18
				var pole_offset: Vector2 = head_offset - arm_dir * head_reach
				var pole_x := center_x + pole_offset.x
				var pole_z := center_z + pole_offset.y
				var pole_point := Vector3(pole_x, 0.0, pole_z)
				var head_point := Vector3(center_x + head_offset.x, 0.0, center_z + head_offset.y)
				# The pole belongs on the corner footway; the suspended
				# head belongs over the approach it serves.  This also
				# rejects any stale hard-coded corner swallowed by a
				# widened side street or diagonal link road.
				if not _is_pole_clear_of_road(pole_point, 0.40) or _road_clearance_xz(head_point) > -0.50:
					rejected_signal_approaches += 1
					continue
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
	var oil_material := _material("oil_stain", "", "", Color(0.012, 0.014, 0.018, 0.27), 0.30)
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

	_enhancement_stats["road_wear_scale_0237"] = true
	_enhancement_stats["sail_loop_pristine_asphalt_0238"] = sail_loop_seen
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
	_enhancement_stats["rejected_fake_signal_approaches_0236"] = rejected_signal_approaches
	_enhancement_stats["traffic_signals_on_real_arms_0236"] = true


func _build_bridge_guardrails(parent: Node) -> void:
	var post_transforms: Array[Transform3D] = []
	var rail_transforms: Array[Transform3D] = []
	var terminal_transforms: Array[Transform3D] = []
	var bridge_ids := ["rt-palm-1", "rt-sail-road"]
	var trimmed_subsegments := 0
	var min_alignment := 1.0
	var trim_start_min := 0.0
	for road_variant in data.get("roads", []):
		var road: Dictionary = road_variant
		var road_id := String(road.get("id", ""))
		if not bridge_ids.has(road_id):
			continue
		var samples: Array = road.get("samples", [])
		if samples.size() < 2:
			continue
		var half_width := _f(road, "widthM", 12.0) * 0.5 - 0.38
		var points: Array[Vector3] = []
		for sample in samples:
			points.append(_sample_point(sample))
		var total_length := 0.0
		for i in range(points.size() - 1):
			var flat := points[i + 1] - points[i]
			flat.y = 0.0
			total_length += flat.length()
		# 0.2.24 fix for rails "across the road": both causeways start at
		# the centre of the 24 m Corniche, and the old loop laid posts,
		# rails AND their box colliders from sample zero -- the first
		# ~13 m of guardrail physically crossed the Corniche driving
		# lanes.  Rails now start one junction trim (crossing half
		# width + 0.9 m) plus a 1.6 m safety flare from each end, with
		# segments subdivided so the cut lands on the boundary instead
		# of the next 5--9 m sample.
		var start_trim := float(_junction_info(points[0], road_id, points[1] - points[0]).get("trim_m", 0.0))
		var end_trim := float(_junction_info(points[points.size() - 1], road_id, points[points.size() - 1] - points[points.size() - 2]).get("trim_m", 0.0))
		var guard_start := start_trim + (1.6 if start_trim > 0.0 else 0.0)
		var guard_end := total_length - end_trim - (1.6 if end_trim > 0.0 else 0.0)
		if guard_start > 0.0:
			trim_start_min = guard_start if trim_start_min <= 0.0 else minf(trim_start_min, guard_start)
		for side_variant in [-1.0, 1.0]:
			var side := float(side_variant)
			var kept_index := 0
			var terminal_added := false
			var distance_from_start := 0.0
			for i in range(points.size() - 1):
				var a := points[i]
				var b := points[i + 1]
				var direction := b - a
				direction.y = 0.0
				var segment_length := direction.length()
				if segment_length < 0.001:
					continue
				direction /= segment_length
				var side_vector := Vector3(-direction.z, 0.0, direction.x)
				var yaw := atan2(-direction.x, -direction.z)
				var subdivisions := maxi(1, int(ceil(segment_length / 2.5)))
				for sub in range(subdivisions):
					var sub_start := distance_from_start + segment_length * float(sub) / float(subdivisions)
					var sub_end := distance_from_start + segment_length * float(sub + 1) / float(subdivisions)
					if sub_start < guard_start or sub_end > guard_end:
						trimmed_subsegments += 1
						continue
					var pa := a.lerp(b, float(sub) / float(subdivisions))
					var pb := a.lerp(b, float(sub + 1) / float(subdivisions))
					var sub_length := sub_end - sub_start
					var edge_a: Vector3 = pa + side_vector * half_width * side + Vector3.UP * 0.10
					var edge_b: Vector3 = pb + side_vector * half_width * side + Vector3.UP * 0.10
					if kept_index % 2 == 0:
						post_transforms.append(make_transform(edge_a + Vector3.UP * 0.43, yaw, Vector3(0.16, 0.86, 0.16)))
					if not terminal_added and guard_start > 0.0:
						# Flared yellow end shoe at the first kept post,
						# offset outward so the rail line reads as a
						# deliberate terminal, not a broken fence.
						terminal_transforms.append(make_transform(
							edge_a + side_vector * side * 0.12 + Vector3.UP * 0.55,
							yaw,
							Vector3(0.30, 0.68, 0.95)
						))
						terminal_added = true
					var centre: Vector3 = (edge_a + edge_b) * 0.5
					_add_box_collider(centre + Vector3.UP * 0.45, Vector3(0.24, 0.92, sub_length + 0.05), yaw)
					for rail_height in [0.52, 0.82]:
						rail_transforms.append(make_transform(centre + Vector3.UP * rail_height, yaw, Vector3(0.09, 0.13, sub_length + 0.08)))
					# Measure the real rendered axis (post scaled_local),
					# not the unscaled yaw basis that hid the 0.2.24 bug.
					var rail_axis := make_transform(Vector3.ZERO, yaw, Vector3(0.09, 0.13, sub_length + 0.08)).basis.z.normalized()
					min_alignment = minf(min_alignment, absf(rail_axis.dot(direction)))
					kept_index += 1
				distance_from_start += segment_length

	var metal := _prop_material("PropsMetal")
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3.ONE
	post_mesh.material = metal
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3.ONE
	rail_mesh.material = metal
	_add_multimesh(parent, post_mesh, metal, post_transforms, "BridgeGuardrailPosts", true)
	_add_multimesh(parent, rail_mesh, metal, rail_transforms, "BridgeGuardrails", true)
	var terminal_material := _material("guardrail_terminal", "", "", Color(0.85, 0.62, 0.08), 0.55, 0.35)
	var terminal_mesh := BoxMesh.new()
	terminal_mesh.size = Vector3.ONE
	terminal_mesh.material = terminal_material
	_add_multimesh(parent, terminal_mesh, terminal_material, terminal_transforms, "BridgeGuardrailTerminals", true)
	_enhancement_stats["guardrail_local_axis_0227"] = true
	_enhancement_stats["guardrail_posts"] = post_transforms.size()
	_enhancement_stats["guardrail_rails"] = rail_transforms.size()
	_enhancement_stats["guardrail_terminals"] = terminal_transforms.size()
	_enhancement_stats["guardrail_trimmed_subsegments"] = trimmed_subsegments
	_enhancement_stats["guardrail_trim_start_m"] = trim_start_min
	_enhancement_stats["guardrail_min_alignment"] = min_alignment

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


func _mesh_triangle_count(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for surface_index in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_index)
		if arrays.size() <= Mesh.ARRAY_VERTEX:
			continue
		var indices: Variant = arrays[Mesh.ARRAY_INDEX] if arrays.size() > Mesh.ARRAY_INDEX else null
		var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
		if indices is PackedInt32Array:
			total += int((indices as PackedInt32Array).size() / 3)
		elif vertices is PackedVector3Array:
			total += int((vertices as PackedVector3Array).size() / 3)
	return total


func _model_part_material(material_name: String, mesh: Mesh) -> Material:
	match material_name:
		"PalmLeaf":
			return _create_foliage_wind_material(mesh, "foliage.jpg", Color(0.60, 0.88, 0.48), 0.0, 0.055, true)
		"PalmLeafDry":
			return _create_foliage_wind_material(mesh, "foliage.jpg", Color(0.96, 0.68, 0.32), 0.0, 0.034, true)
		"GrassBlade":
			var grass := _create_foliage_wind_material(mesh, "", Color.WHITE, 0.0, 0.028, true)
			grass.set_shader_parameter("leaf_color", Color(0.095, 0.315, 0.065))
			return grass
		"GrassBladeDry":
			var dry_grass := _create_foliage_wind_material(mesh, "", Color.WHITE, 0.0, 0.021, true)
			dry_grass.set_shader_parameter("leaf_color", Color(0.42, 0.335, 0.105))
			return dry_grass
		"OrnamentalLeaf":
			return _create_foliage_wind_material(mesh, "foliage.jpg", Color(0.54, 0.84, 0.46), 0.0, 0.012, true)
		"FlowerLeaf":
			return _create_foliage_wind_material(mesh, "foliage.jpg", Color(0.56, 0.86, 0.47), 0.0, 0.010, true)
		_:
			return _prop_material(material_name)


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

	var is_vegetation_model := path.contains("/vegetation/")
	var normal_merge_angle := 78.0 if is_vegetation_model else 62.0
	var model_triangle_count := 0
	for material_name_variant in tools.keys():
		var material_name := String(material_name_variant)
		var tool := tools[material_name] as SurfaceTool
		# ImporterMesh LOD generation requires an indexed surface; the
		# index also stops the vertex shader reprocessing every shared
		# Blender box corner once per incident triangle.
		tool.index()
		var source_mesh := tool.commit()
		model_triangle_count += _mesh_triangle_count(source_mesh)
		var mesh := _mesh_with_runtime_lods(source_mesh, normal_merge_angle) if source_mesh != null else null
		if mesh != null:
			parts.append({
				"mesh": mesh,
				"material": _model_part_material(material_name, mesh) if is_vegetation_model else _prop_material(material_name),
				"material_name": material_name,
			})
	var is_photoreal_prop_0223 := path.ends_with("street_lamp.glb") or path.ends_with("bus_shelter.glb") or path.ends_with("park_bench.glb") or path.ends_with("park_pergola.glb")
	if is_vegetation_model or is_photoreal_prop_0223:
		var triangle_key := "%s_triangles" % path.get_file().trim_suffix(".glb")
		_enhancement_stats[triangle_key] = model_triangle_count
		if model_triangle_count > 0:
			_enhancement_stats["photoreal_models_0223"] = true
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
	if key.contains("main148mtower") or key.contains("richtownopera") or key.contains("richtownmosque"):
		return 0.0
	if key.contains("blendervillas") or key.contains("blendertownhouses"):
		return 140.0
	if key.contains("blenderherobuildings"):
		return 200.0
	if key.contains("blenderglasstowers"):
		return 280.0
	if key.contains("trafficsignal"):
		return 170.0
	if key.contains("busshelter"):
		return 175.0
	if key.contains("streetlamp") or key.contains("guardrail"):
		return 180.0
	if key.contains("bush") or key.contains("shrub") or key.contains("fan_foliage"):
		return 90.0
	if key.contains("crosswalk") or key.contains("roadedge") or key.contains("roadlane") or key.contains("roadcenter") or key.contains("lanearrow") or key.contains("parkingbay") or key.contains("bikelane"):
		return 380.0
	if key.contains("sidewalkslab") or key.contains("roadcurb") or key.contains("roadgutter") or key.contains("intersectionpad"):
		return 250.0
	if key.contains("manhole") or key.contains("drainage") or key.contains("roadstud") or key.contains("asphaltpatch") or key.contains("tarseam") or key.contains("oilstain") or key.contains("skidmark") or key.contains("tactile"):
		return 120.0
	if key.contains("pool"):
		return 260.0
	if key.contains("palm"):
		return 145.0
	if key.contains("tree"):
		return 125.0
	if key.contains("bollard") or key.contains("planter") or key.contains("hedge") or key.contains("trashbin") or key.contains("roadsign") or key.contains("storefront") or key.contains("awning") or key.contains("balcony"):
		return 150.0
	if key.contains("beach"):
		return 360.0
	if key.contains("marina"):
		return 520.0
	if key.contains("rooftop") or key.contains("watertank"):
		return 300.0
	return 0.0


## 0.2.37 shadow-pass diet.  Kerbs, raised pavement slabs and deck
## plates are only 0.10-0.18 m proud of the surface they sit on: their
## cast shadow is a sub-centimetre contact line that is not readable
## in game, yet every one of the thousands of instances was drawn a
## second time into the 2048 px directional shadow map.  Removing
## only these flat layers from the shadow pass changes no model, no
## material and no shader; buildings, palms, lamps and furniture keep
## casting exactly as before.
func _is_flat_shadow_free_multimesh_0237(node_name: String) -> bool:
	var key := node_name.to_lower()
	return key.contains("curb") or key.contains("slab") or key.contains("promenadedeck") or key.contains("cottagegravel") or key.contains("cottagelawn") or key.contains("cottagepaving")


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
	var effective_cast_shadow := cast_shadow and not _is_flat_shadow_free_multimesh_0237(node_name)
	if cast_shadow and not effective_cast_shadow:
		_flat_shadow_free_instances_0237 += transforms.size()
		_enhancement_stats["flat_shadow_casters_disabled_0237"] = _flat_shadow_free_instances_0237

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
			floori((transform_value.origin.x - _active_aabb.position.x) / effective_chunk_size_m),
			floori((transform_value.origin.z - _active_aabb.position.z) / effective_chunk_size_m)
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
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if effective_cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		instance.custom_aabb = chunk_aabb.grow(1.5) if have_chunk_aabb else _active_aabb
		var visual_begin := visibility_begin_m
		var visual_end := visibility_end_m if visibility_end_m >= 0.0 else _multimesh_visual_range(node_name)
		if visual_begin > 0.0:
			instance.visibility_range_begin = visual_begin
		if visual_end > 0.0:
			instance.visibility_range_end = visual_end
		if visual_begin > 0.0 or visual_end > 0.0:
			# Dithered self-fades soften HLOD handoffs instead of hard pops.
			instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			instance.lod_bias = 0.45
			# 0.2.44: register the shipped base range so the user's
			# graphics preset can rescale detail distances live.
			_quality_ranged_instances.append({
				"node": instance,
				"begin": maxf(visual_begin, 0.0),
				"end": maxf(visual_end, 0.0),
			})
		else:
			# Skyline geometry keeps generated/imported mesh LODs, but
			# switches to them earlier than the desktop bias.
			instance.lod_bias = 0.65
		parent.add_child(instance)
		_stream_chunks.append({
			"node": instance,
			"centre": chunk_aabb.get_center(),
			"radius": chunk_aabb.size.length() * 0.5,
			"hidden": false,
			"sector_hidden_0237": false,
		})
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
	if path.ends_with("opera_house.glb"):
		return "RichTownOpera"
	if path.ends_with("mosque.glb"):
		return "RichTownMosque"
	if path.ends_with("grand_hotel.glb"):
		return "BlenderGrandHotels"
	if path.ends_with("museum.glb"):
		return "RichTownMuseum"
	if path.ends_with("cottage_dune.glb"):
		return "SailCottageDune"
	if path.ends_with("cottage_courtyard.glb"):
		return "SailCottageCourtyard"
	if path.ends_with("cottage_palm.glb"):
		return "SailCottagePalm"
	if path.ends_with("street_lamp.glb"):
		return "BlenderStreetLamps"
	if path.ends_with("bus_shelter.glb"):
		return "BlenderBusShelters"
	if path.ends_with("park_bench.glb"):
		return "BlenderParkBenches"
	if path.ends_with("park_pergola.glb"):
		return "BlenderParkPergola"
	if path.ends_with("palm_date.glb"):
		return "BlenderDatePalms"
	if path.ends_with("palm_royal.glb"):
		return "BlenderRoyalPalms"
	if path.ends_with("grass_tuft.glb"):
		return "BlenderGrassTufts"
	if path.ends_with("flower_clump.glb"):
		return "BlenderFlowerClumps"
	if path.ends_with("ornamental_shrub.glb"):
		return "BlenderOrnamentalShrubs"
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
	if path.ends_with("grand_hotel.glb"):
		return 340.0
	if path.ends_with("museum.glb"):
		return 340.0
	if path.ends_with("cottage_dune.glb") or path.ends_with("cottage_courtyard.glb") or path.ends_with("cottage_palm.glb"):
		# One 13.5-16.7k-triangle estate each: full architectural
		# detail around the whole Sail loop, simple massing beyond.
		return 240.0
	if path.ends_with("palm_date.glb") or path.ends_with("palm_royal.glb"):
		return 390.0
	if path.ends_with("dubai_premium_cafe.glb"):
		return 220.0
	if path.ends_with("grass_tuft.glb"):
		return 52.0
	if path.ends_with("flower_clump.glb"):
		return 72.0
	if path.ends_with("ornamental_shrub.glb"):
		return 105.0
	if path.ends_with("park_bench.glb"):
		return 220.0
	if path.ends_with("park_pergola.glb"):
		return 320.0
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
		if key.contains("roofdark"):
			return 130.0
		return 120.0 if key.contains("glow") else 180.0
	if path.ends_with("bus_shelter.glb"):
		if key.contains("solar"):
			return 130.0
		if key.contains("glow"):
			return 140.0
		return 140.0 if key.contains("glass") else 175.0
	if path.ends_with("park_bench.glb"):
		return 120.0 if key.contains("roofdark") else 165.0
	if path.ends_with("park_pergola.glb"):
		return 180.0 if key.contains("propsmetal") else 240.0

	var base_range := _batched_model_base_range(path)
	if base_range <= 0.0:
		return 0.0
	if path.contains("cottage_"):
		if key.contains("hedge") or key.contains("lawn") or key.contains("gravel") or key.contains("solar"):
			return 150.0
		if key.contains("paving") or key.contains("water") or key.contains("light"):
			return 190.0
		if key.contains("blind") or key.contains("core"):
			return 210.0
		return base_range
	var architectural_limit := base_range
	if path.ends_with("villa.glb") or path.ends_with("townhouse.glb"):
		architectural_limit = 125.0
	elif path.ends_with("hero_building.glb"):
		architectural_limit = 180.0
	elif path.ends_with("glass_tower.glb"):
		architectural_limit = 240.0
	if path.ends_with("palm_date.glb") or path.ends_with("palm_royal.glb"):
		return 130.0
	if key.contains("fruit"):
		return minf(architectural_limit, 220.0)
	if key.contains("leafdry"):
		return minf(architectural_limit, 320.0)
	if key.contains("dry"):
		return minf(architectural_limit, 44.0)
	# Site dressing and emissive/solar accents are sub-pixel long before
	# the architectural mass is. Retire them first, then curtains and
	# window frames; wall/glass/spandrel cores keep the full HLOD range.
	if key.contains("hedge") or key.contains("lawn") or key.contains("mulch") or key.contains("glow") or key.contains("solar"):
		return minf(architectural_limit, 90.0)
	if key.contains("pavement") or key.contains("deck"):
		return minf(architectural_limit, 100.0)
	if key.contains("curtain") or key.contains("interior"):
		return minf(architectural_limit, 200.0)
	if key.contains("windowframe"):
		return minf(architectural_limit, 230.0)
	return minf(base_range, architectural_limit)


func _batched_model_chunk_size(path: String) -> float:
	if path.ends_with("main_tower.glb"):
		return MULTIMESH_CHUNK_SIZE_M
	if path.contains("traffic_signal"):
		return 170.0
	if path.ends_with("palm_date.glb") or path.ends_with("palm_royal.glb"):
		return 155.0
	if path.ends_with("grass_tuft.glb"):
		return 42.0
	if path.ends_with("flower_clump.glb"):
		return 55.0
	if path.ends_with("ornamental_shrub.glb"):
		return 70.0
	if path.ends_with("park_bench.glb"):
		return 120.0
	if path.ends_with("park_pergola.glb"):
		return 220.0
	return 180.0


func _add_palm_far_proxy(parent: Node, path: String, transforms: Array, node_name: String) -> void:
	if transforms.is_empty() or not (path.ends_with("palm_date.glb") or path.ends_with("palm_royal.glb")):
		return
	var is_date := path.ends_with("palm_date.glb")
	var crown_height := 7.46 if is_date else 8.76
	var crown_centre := Vector3(0.60, crown_height, -0.11) if is_date else Vector3(0.42, crown_height, -0.08)

	var trunk := CylinderMesh.new()
	trunk.bottom_radius = 0.32
	trunk.top_radius = 0.20
	trunk.height = crown_height
	trunk.radial_segments = 10
	trunk.rings = 1
	var trunk_local := Transform3D(Basis.IDENTITY, Vector3(crown_centre.x * 0.45, crown_height * 0.5, crown_centre.z * 0.45))
	var trunk_transforms: Array = []
	for transform_variant in transforms:
		trunk_transforms.append((transform_variant as Transform3D) * trunk_local)
	_add_multimesh(parent, trunk, _prop_material("PalmTrunk"), trunk_transforms, "%sFarProxyTrunk" % node_name, false, 105.0, 850.0, 260.0)

	var crown := SphereMesh.new()
	crown.radius = 0.5
	crown.height = 1.0
	crown.radial_segments = 14
	crown.rings = 7
	var crown_size := Vector3(7.2, 2.55, 7.2) if is_date else Vector3(6.8, 2.75, 6.8)
	var crown_local := Transform3D(Basis.IDENTITY.scaled(crown_size), crown_centre + Vector3(0.0, 0.28, 0.0))
	var crown_transforms: Array = []
	for transform_variant in transforms:
		crown_transforms.append((transform_variant as Transform3D) * crown_local)
	_add_multimesh(
		parent,
		crown,
		_create_foliage_wind_material(crown, "foliage.jpg", Color(0.55, 0.82, 0.44), 0.0, 0.012, true),
		crown_transforms,
		"%sFarProxyCrown" % node_name,
		false,
		105.0,
		850.0,
		260.0
	)
	_enhancement_stats["palm_far_proxy_0217"] = true
	_enhancement_stats["palm_far_proxies"] = int(_enhancement_stats.get("palm_far_proxies", 0)) + transforms.size()


## Far HLOD volumes preserve the real footprint/height and podium/shaft
## split of each fixed-scale building after its detailed Blender parts
## retire. They sit slightly inside the true envelope so the short
## detailed/proxy overlap does not wrap the near model in a box.
func _add_building_far_proxy(parent: Node, path: String, transforms: Array, node_name: String) -> void:
	var base_range := _batched_model_base_range(path)
	if base_range <= 0.0 or transforms.is_empty():
		return
	var proxy_begin := maxf(base_range - 20.0, 0.0)
	if path.ends_with("villa.glb") or path.ends_with("townhouse.glb"):
		proxy_begin = 95.0
	elif path.ends_with("hero_building.glb"):
		proxy_begin = 145.0
	elif path.ends_with("glass_tower.glb"):
		proxy_begin = 200.0
	var proxy_end := 1050.0
	var specs: Array[Dictionary] = []
	if path.ends_with("villa.glb"):
		specs = [
			{"size": Vector3(18.60, 8.00, 14.70), "center": Vector3(0.0, 4.00, 0.05), "material": _prop_material("VillaPlaster"), "name": "Mass"},
			{"size": Vector3(19.20, 0.50, 15.24), "center": Vector3(0.0, 8.42, 0.05), "material": _prop_material("RoofDark"), "name": "Roof"},
		]
	elif path.ends_with("cottage_dune.glb"):
		specs = [
			{"size": Vector3(34.50, 0.25, 25.50), "center": Vector3(0.0, 0.13, 0.0), "material": _prop_material("CottageGravel"), "name": "Lot"},
			{"size": Vector3(16.40, 7.30, 10.20), "center": Vector3(3.8, 3.65, -1.8), "material": _prop_material("CottageSand"), "name": "Main"},
			{"size": Vector3(2.10, 8.20, 11.70), "center": Vector3(-4.9, 4.10, -0.55), "material": _prop_material("CottageTravertine"), "name": "Blade"},
			{"size": Vector3(7.70, 3.60, 6.70), "center": Vector3(-10.6, 1.80, 1.15), "material": _prop_material("CottageLimestone"), "name": "Garage"},
		]
	elif path.ends_with("cottage_courtyard.glb"):
		specs = [
			{"size": Vector3(34.50, 0.25, 25.50), "center": Vector3(0.0, 0.13, 0.01), "material": _prop_material("CottageGravel"), "name": "Lot"},
			{"size": Vector3(6.30, 6.40, 12.60), "center": Vector3(-9.7, 3.20, -2.0), "material": _prop_material("CottageSand"), "name": "WestWing"},
			{"size": Vector3(6.30, 6.40, 12.60), "center": Vector3(9.7, 3.20, -2.0), "material": _prop_material("CottageSand"), "name": "EastWing"},
			{"size": Vector3(14.40, 7.30, 5.70), "center": Vector3(0.0, 3.65, -7.15), "material": _prop_material("CottageLimestone"), "name": "RearWing"},
			{"size": Vector3(2.90, 11.30, 2.90), "center": Vector3(-7.9, 5.65, -7.3), "material": _prop_material("CottageTravertine"), "name": "Barjeel"},
		]
	elif path.ends_with("cottage_palm.glb"):
		specs = [
			{"size": Vector3(34.50, 0.25, 25.50), "center": Vector3(0.0, 0.13, 0.0), "material": _prop_material("CottageGravel"), "name": "Lot"},
			{"size": Vector3(12.60, 7.70, 9.60), "center": Vector3(-6.4, 3.85, -1.0), "material": _prop_material("CottageSand"), "name": "WestPavilion"},
			{"size": Vector3(8.80, 7.00, 8.20), "center": Vector3(8.6, 3.50, -0.55), "material": _prop_material("CottageLimestone"), "name": "EastPavilion"},
			{"size": Vector3(1.35, 8.50, 4.40), "center": Vector3(-13.35, 4.25, -2.2), "material": _prop_material("CottageBasalt"), "name": "Chimney"},
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
	elif path.ends_with("grand_hotel.glb"):
		proxy_end = 1350.0
		specs = [
			{"size": Vector3(32.00, 7.20, 22.00), "center": Vector3(0.0, 3.60, 0.0), "material": _prop_material("HotelStone"), "name": "Podium"},
			{"size": Vector3(25.60, 36.30, 17.20), "center": Vector3(0.0, 25.75, -1.0), "material": _prop_material("HotelPlaster"), "name": "Shaft"},
			{"size": Vector3(19.60, 3.40, 13.20), "center": Vector3(0.0, 46.10, -1.2), "material": _prop_material("HotelStone"), "name": "Crown"},
		]
	elif path.ends_with("museum.glb"):
		proxy_end = 1350.0
		specs = [
			{"size": Vector3(53.60, 0.60, 37.60), "center": Vector3(0.0, 0.30, 0.0), "material": _prop_material("MuseumGranite"), "name": "Plinth"},
			{"size": Vector3(45.20, 15.60, 29.20), "center": Vector3(0.0, 8.40, -1.0), "material": _prop_material("MuseumStone"), "name": "Mass"},
			{"size": Vector3(49.20, 0.55, 33.20), "center": Vector3(0.0, 16.48, -1.0), "material": _prop_material("MuseumWhite"), "name": "Roof"},
			{"size": Vector3(31.00, 2.30, 10.00), "center": Vector3(0.0, 17.90, -1.0), "material": _prop_material("MuseumTravertine"), "name": "Lantern"},
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
				or material_key.contains("leaf")
				or material_key.contains("grass")
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
			_add_palm_far_proxy(model_root, path, transforms, node_name)
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
	var hotel_items: Array[Dictionary] = []
	var hotel_transforms: Array[Transform3D] = []
	var cottage_dune_items: Array[Dictionary] = []
	var cottage_dune_transforms: Array[Transform3D] = []
	var cottage_courtyard_items: Array[Dictionary] = []
	var cottage_courtyard_transforms: Array[Transform3D] = []
	var cottage_palm_items: Array[Dictionary] = []
	var cottage_palm_transforms: Array[Transform3D] = []
	var cottage_podium_transforms: Array[Transform3D] = []
	var cottage_collider_count := 0

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
		if model.begins_with("cottage_"):
			# Building Models No.10-12 are complete fenced estates,
			# not stretch-to-parcel houses: exactly 35.96 x 27.01 m
			# at scale 1.0 (AABB centre x = 0, z = +0.004/+0.014).
			# The origin sits on the highest sampled lot point and
			# the basalt podium below absorbs the island fall; the
			# 8-part perimeter + per-volume colliders keep the closed
			# gates honest without one estate-sized invisible cube.
			var estate_position := position_value
			estate_position.y = _cottage_estate_ground_y_0239(position_value, yaw)
			var estate_transform := _centered_model_transform(
				estate_position,
				yaw,
				Vector3.ONE,
				Vector3(0.0, 0.0, 0.014 if model == "cottage_courtyard" else 0.004)
			)
			match model:
				"cottage_dune":
					cottage_dune_items.append(building)
					cottage_dune_transforms.append(estate_transform)
				"cottage_courtyard":
					cottage_courtyard_items.append(building)
					cottage_courtyard_transforms.append(estate_transform)
				"cottage_palm":
					cottage_palm_items.append(building)
					cottage_palm_transforms.append(estate_transform)
			cottage_podium_transforms.append_array(_cottage_podium_transforms_0239(estate_position, yaw))
			cottage_collider_count += _add_cottage_estate_colliders_0239(estate_position, yaw, model)
		elif model == "villa":
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
		elif kind == "rt-hotel" and h > 38.0 and w >= 33.0 and w <= 36.0 and d >= 25.0 and d <= 28.0:
			# Building Model No.8 is one finished beachfront grand
			# hotel measuring exactly 33.60 x 26.00 m and 49.07 m high
			# (GLB AABB centre x/z = 0.0 / 0.0), authored for the three
			# 34 x 26 m Corniche parcels on the X892 strip whose data
			# heights (42/46/54 m) previously produced plain textured
			# boxes.  Fixed scale keeps its 3.25 m guest floors,
			# balconies and porte-cochere true at all three parcels.
			# The exported rotY faces the authored entrance west,
			# away from the X930 corniche road; a grand hotel must
			# present its porte-cochere to the road (and its front
			# balconies to the sea), so No.8 turns 180 degrees on
			# the same rectangular parcel.
			var hotel_yaw := yaw + PI
			hotel_items.append(building)
			hotel_transforms.append(_centered_model_transform(
				position_value,
				hotel_yaw,
				Vector3.ONE,
				Vector3.ZERO
			))
			_add_box_collider(position_value + Vector3(0.0, 3.80, 0.0), Vector3(32.40, 7.60, 22.40), hotel_yaw)
			_add_box_collider(position_value + Vector3(0.0, 25.75, 0.0) + Basis(Vector3.UP, hotel_yaw) * Vector3(0.0, 0.0, -1.0), Vector3(26.80, 36.50, 18.40), hotel_yaw)
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
	var premium_hotel_built := _add_batched_model(buildings_root, "res://assets/buildings/grand_hotel.glb", hotel_transforms, "BlenderGrandHotels")
	if not premium_hotel_built:
		for item in hotel_items:
			_add_generic_building(buildings_root, item)
	var cottage_dune_built := _add_batched_model(buildings_root, "res://assets/buildings/cottage_dune.glb", cottage_dune_transforms, "SailCottageDune")
	if not cottage_dune_built:
		for item in cottage_dune_items:
			_add_generic_building(buildings_root, item)
	var cottage_courtyard_built := _add_batched_model(buildings_root, "res://assets/buildings/cottage_courtyard.glb", cottage_courtyard_transforms, "SailCottageCourtyard")
	if not cottage_courtyard_built:
		for item in cottage_courtyard_items:
			_add_generic_building(buildings_root, item)
	var cottage_palm_built := _add_batched_model(buildings_root, "res://assets/buildings/cottage_palm.glb", cottage_palm_transforms, "SailCottagePalm")
	if not cottage_palm_built:
		for item in cottage_palm_items:
			_add_generic_building(buildings_root, item)
	var cottage_podium_box := BoxMesh.new()
	cottage_podium_box.size = Vector3.ONE
	var cottage_podiums_built := _add_multimesh(
		buildings_root,
		cottage_podium_box,
		_prop_material("CottageBasalt"),
		cottage_podium_transforms,
		"SailCottagePodiums",
		true,
		0.0,
		240.0,
		180.0
	)
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
	# The 0.2.26 smoke proves the same chain for Building Model No.8:
	# the grand-hotel GLB in the export must be the fixed-scale
	# 33.60 x 26.00 x 49.07 m design with its dedicated Hotel*
	# materials resolved to Godot PBR materials.
	var premium_hotel_triangles := 0
	var premium_hotel_parts := 0
	if premium_hotel_built:
		var hotel_parts := _get_model_parts("res://assets/buildings/grand_hotel.glb")
		premium_hotel_parts = hotel_parts.size()
		for hotel_part_variant in hotel_parts:
			var hotel_part: Dictionary = hotel_part_variant
			premium_hotel_triangles += _mesh_triangle_count(hotel_part.get("mesh") as Mesh)
	_enhancement_stats["premium_hotel_models"] = hotel_transforms.size() if premium_hotel_built else 0
	_enhancement_stats["premium_hotel_fixed_scale"] = premium_hotel_built
	_enhancement_stats["premium_hotel_detail_pass"] = premium_hotel_built and premium_hotel_triangles >= 30000 and premium_hotel_parts >= 10
	_enhancement_stats["premium_hotel_material_pass"] = premium_hotel_built and _materials.has("hotel_travertine") and _materials.has("hotel_bronze") and _materials.has("hotel_glass_physical") and _materials.has("hotel_black_granite") and _materials.has("hotel_pool_water")
	_enhancement_stats["premium_hotel_site_pass"] = premium_hotel_built and _materials.has("hotel_teak") and _materials.has("hotel_warm_light") and _materials.has("hotel_accent_teal")
	_enhancement_stats["premium_hotel_triangles"] = premium_hotel_triangles
	_enhancement_stats["premium_hotel_model_parts"] = premium_hotel_parts
	_enhancement_stats["premium_hotel_fronts_corniche"] = premium_hotel_built
	_enhancement_stats["premium_hotel_height_m"] = 49.07
	_enhancement_stats["premium_hotel_width_m"] = 33.60
	_enhancement_stats["premium_hotel_depth_m"] = 26.00
	# The 0.2.39 smoke proves the full chain for Building Models
	# No.10-12: three distinct fixed-scale estate GLBs, their Cottage*
	# semantic materials with real roughness maps, retaining podiums
	# and the multi-box perimeter/house colliders.
	var cottage_triangles := {"cottage_dune": 0, "cottage_courtyard": 0, "cottage_palm": 0}
	var cottage_model_parts := 0
	for cottage_entry in [
		["cottage_dune", "res://assets/buildings/cottage_dune.glb", cottage_dune_built],
		["cottage_courtyard", "res://assets/buildings/cottage_courtyard.glb", cottage_courtyard_built],
		["cottage_palm", "res://assets/buildings/cottage_palm.glb", cottage_palm_built],
	]:
		if not bool(cottage_entry[2]):
			continue
		var cottage_parts := _get_model_parts(String(cottage_entry[1]))
		cottage_model_parts += cottage_parts.size()
		var cottage_part_triangles := 0
		for cottage_part_variant in cottage_parts:
			var cottage_part: Dictionary = cottage_part_variant
			cottage_part_triangles += _mesh_triangle_count(cottage_part.get("mesh") as Mesh)
		cottage_triangles[String(cottage_entry[0])] = cottage_part_triangles
	var cottage_roughness_materials := 0
	for material_key_variant in _materials.keys():
		var material_key := String(material_key_variant)
		if not material_key.begins_with("cottage_"):
			continue
		var cottage_material := _materials[material_key] as StandardMaterial3D
		if cottage_material != null and cottage_material.roughness_texture != null:
			cottage_roughness_materials += 1
	var cottage_models_built := cottage_dune_built and cottage_courtyard_built and cottage_palm_built
	_enhancement_stats["sail_cottage_estates_0239"] = cottage_models_built and cottage_podiums_built and cottage_collider_count >= 39
	_enhancement_stats["sail_cottage_models_0239"] = (cottage_dune_transforms.size() + cottage_courtyard_transforms.size() + cottage_palm_transforms.size()) if cottage_models_built else 0
	_enhancement_stats["sail_cottage_fixed_scale_0239"] = cottage_models_built
	_enhancement_stats["sail_cottage_exterior_only_0239"] = cottage_models_built and _materials.has("cottage_core") and _materials.has("cottage_blind")
	_enhancement_stats["sail_cottage_pbr_roughness_0239"] = cottage_roughness_materials >= 7
	_enhancement_stats["sail_cottage_roughness_materials_0239"] = cottage_roughness_materials
	_enhancement_stats["sail_cottage_material_pass_0239"] = cottage_models_built and _materials.has("cottage_rammed_sand") and _materials.has("cottage_travertine_coarse") and _materials.has("cottage_limestone_blocks") and _materials.has("cottage_basalt") and _materials.has("cottage_teak_weathered") and _materials.has("cottage_glass_physical")
	_enhancement_stats["sail_cottage_multi_box_colliders_0239"] = cottage_collider_count >= 39
	_enhancement_stats["sail_cottage_colliders_0239"] = cottage_collider_count
	_enhancement_stats["sail_cottage_podiums_0239"] = cottage_podium_transforms.size() if cottage_podiums_built else 0
	_enhancement_stats["sail_cottage_model_parts_0239"] = cottage_model_parts
	_enhancement_stats["sail_cottage_dune_triangles_0239"] = int(cottage_triangles.get("cottage_dune", 0))
	_enhancement_stats["sail_cottage_courtyard_triangles_0239"] = int(cottage_triangles.get("cottage_courtyard", 0))
	_enhancement_stats["sail_cottage_palm_triangles_0239"] = int(cottage_triangles.get("cottage_palm", 0))
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
			if _road_clearance_xz(corner) < 2.7 or not _is_position_clear(corner, 2.0, 0.0, false):
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
			if _road_clearance_xz(corner) < 2.7 or not _is_position_clear(corner, 2.0, 0.0, false):
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
		if _road_clearance_xz(corner) < 2.7 or not _is_position_clear(corner, 2.0, 0.0, false):
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
				if _is_in_park(x, z, 18.0):
					continue
				# The expanded Sail Island is a designed resort (loop,
				# villas, pools, promenade), not a random infill field.
				if _in_zone(x, z, "sailIsland"):
					continue

				var w := 15.0 + _hash01(ix, iz) * 9.0
				var d := 13.0 + _hash01(iz, ix) * 8.0
				var h := 8.0 + _hash01(ix + 9, iz + 4) * 20.0
				# 0.2.19: the reference is a continuous urban wall, not a
				# downtown cluster that dissolves into detached villas
				# before the spawn.  Keep the exported villas/landmarks,
				# but make every genuinely empty Boulevard parcel a
				# mid/high-rise frontage parcel from Z=-430 to Z=430.
				var boulevard_frontage := x >= 690.0 and x <= 880.0 and z >= -430.0 and z <= 430.0
				if boulevard_frontage:
					w = 17.0 + _hash01(ix, iz) * 8.0
					d = 15.0 + _hash01(iz, ix) * 8.0
					h = 18.0 + _hash01(ix + 9, iz + 4) * 38.0
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
				if boulevard_frontage:
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
					"boulevardFrontage": boulevard_frontage,
				})

	# Targeted 0.2.19 Boulevard frontage.  The citywide 24 x 27 m search
	# grid almost never lands in the narrow gaps between the exported
	# Boulevard towers (the first CI smoke found only two qualifying
	# parcels), so test a small deterministic set of real gaps on both
	# faces.  These are still genuine infill buildings: every corner is
	# checked against roads/exported buildings/pools/landmarks and
	# against the generic infill accepted above.  East Z=150..380 is
	# marina water and is deliberately left as the raised quay built by
	# the premium Boulevard pass.
	var targeted_frontage_specs: Array[Dictionary] = [
		{"x": 710.0, "z": -364.0, "w": 20.0, "d": 16.0, "h": 30.0, "facade": "hotelTower"},
		{"x": 710.0, "z": -320.0, "w": 20.0, "d": 16.0, "h": 42.0, "facade": "glassTower"},
		{"x": 710.0, "z": -232.0, "w": 20.0, "d": 16.0, "h": 36.0, "facade": "marbleTower"},
		{"x": 710.0, "z": -180.0, "w": 20.0, "d": 14.0, "h": 48.0, "facade": "glassTower"},
		{"x": 710.0, "z": 143.0, "w": 20.0, "d": 18.0, "h": 38.0, "facade": "hotelTower"},
		{"x": 710.0, "z": 242.0, "w": 20.0, "d": 14.0, "h": 30.0, "facade": "marbleTower"},
		{"x": 710.0, "z": 287.0, "w": 20.0, "d": 16.0, "h": 34.0, "facade": "glassTower"},
		{"x": 710.0, "z": 371.0, "w": 20.0, "d": 14.0, "h": 28.0, "facade": "hotelTower"},
		{"x": 710.0, "z": 408.0, "w": 20.0, "d": 14.0, "h": 32.0, "facade": "goldTower"},
		{"x": 804.0, "z": -366.0, "w": 20.0, "d": 16.0, "h": 30.0, "facade": "marbleTower"},
		{"x": 804.0, "z": -320.0, "w": 20.0, "d": 16.0, "h": 44.0, "facade": "glassTower"},
		{"x": 804.0, "z": -232.0, "w": 20.0, "d": 16.0, "h": 38.0, "facade": "hotelTower"},
		{"x": 804.0, "z": -181.0, "w": 20.0, "d": 14.0, "h": 46.0, "facade": "glassTower"},
		{"x": 804.0, "z": -128.0, "w": 20.0, "d": 14.0, "h": 34.0, "facade": "goldTower"},
		{"x": 804.0, "z": 82.0, "w": 20.0, "d": 18.0, "h": 40.0, "facade": "glassTower"},
		{"x": 804.0, "z": 120.0, "w": 20.0, "d": 18.0, "h": 32.0, "facade": "hotelTower"},
	]
	for targeted_spec in targeted_frontage_specs:
		var targeted_x := _f(targeted_spec, "x")
		var targeted_z := _f(targeted_spec, "z")
		var targeted_w := _f(targeted_spec, "w", 20.0)
		var targeted_d := _f(targeted_spec, "d", 16.0)
		if _is_in_park(targeted_x, targeted_z, 16.0):
			continue
		var targeted_y := height_at(targeted_x, targeted_z)
		if targeted_y < 1.55:
			continue
		var targeted_valid := true
		var targeted_min_height := INF
		var targeted_max_height := -INF
		for targeted_corner in [
			Vector3(targeted_x - targeted_w * 0.5, 0.0, targeted_z - targeted_d * 0.5),
			Vector3(targeted_x + targeted_w * 0.5, 0.0, targeted_z - targeted_d * 0.5),
			Vector3(targeted_x - targeted_w * 0.5, 0.0, targeted_z + targeted_d * 0.5),
			Vector3(targeted_x + targeted_w * 0.5, 0.0, targeted_z + targeted_d * 0.5),
		]:
			var targeted_corner_height := height_at(targeted_corner.x, targeted_corner.z)
			targeted_min_height = minf(targeted_min_height, targeted_corner_height)
			targeted_max_height = maxf(targeted_max_height, targeted_corner_height)
			if _road_clearance_xz(targeted_corner) < 2.7 or not _is_position_clear(targeted_corner, 1.2, 0.0):
				targeted_valid = false
				break
		if not targeted_valid or targeted_max_height - targeted_min_height > 1.1:
			continue
		for existing_frontage in accepted:
			if absf(targeted_x - _f(existing_frontage, "x")) < (targeted_w + _f(existing_frontage, "w")) * 0.5 + 3.0 and absf(targeted_z - _f(existing_frontage, "z")) < (targeted_d + _f(existing_frontage, "d")) * 0.5 + 3.0:
				targeted_valid = false
				break
		if not targeted_valid:
			continue
		for landmark_variant in data.get("landmarks", []):
			var landmark: Dictionary = landmark_variant
			var landmark_pos := _item_position(landmark)
			var safe_radius := maxf(_f(landmark, "r", 26.0), 26.0) + maxf(targeted_w, targeted_d) * 0.55
			if Vector2(targeted_x - landmark_pos.x, targeted_z - landmark_pos.z).length() < safe_radius:
				targeted_valid = false
				break
		if not targeted_valid:
			continue
		accepted.append({
			"x": targeted_x,
			"y": targeted_y,
			"z": targeted_z,
			"w": targeted_w,
			"d": targeted_d,
			"h": _f(targeted_spec, "h", 30.0),
			"roofH": 0.0,
			"rotY": 0.0,
			"kind": "rt-infill",
			"model": "generic",
			"facade": String(targeted_spec.get("facade", "glassTower")),
			"boulevardFrontage": true,
		})

	_infill_buildings = accepted
	_enhancement_stats["sail_island_infill_excluded_0237"] = true
	_enhancement_stats["infill_buildings"] = accepted.size()
	var boulevard_frontage_count := 0
	for frontage_item in accepted:
		if bool(frontage_item.get("boulevardFrontage", false)) and _f(frontage_item, "h") >= 18.0:
			boulevard_frontage_count += 1
	_enhancement_stats["boulevard_frontage_infill"] = boulevard_frontage_count
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
				# Building Model No.9 is a finished fixed-scale civic
				# museum measuring 54.00 x 38.00 m and exactly 19.00 m
				# to the clerestory lantern cap.  Blender -Y is the
				# public front, so at yaw 0 the glazed atrium slot
				# faces +Z toward the fountain axis (Z-25), with the
				# reflecting pool/sculpture court on the same side and
				# the garden slot + loading dock behind.  The primitive
				# metal torus on a marble slab is gone.
				var museum_path := "res://assets/buildings/museum.glb"
				var museum_parts := _get_model_parts(museum_path)
				var museum_triangles := 0
				var museum_aabb := AABB()
				var museum_has_aabb := false
				for museum_part_variant in museum_parts:
					var museum_part: Dictionary = museum_part_variant
					var museum_mesh := museum_part.get("mesh") as Mesh
					if museum_mesh == null:
						continue
					museum_triangles += _mesh_triangle_count(museum_mesh)
					var museum_part_aabb := museum_mesh.get_aabb()
					museum_aabb = museum_part_aabb if not museum_has_aabb else museum_aabb.merge(museum_part_aabb)
					museum_has_aabb = true
				var museum_size := museum_aabb.size if museum_has_aabb else Vector3.ZERO
				var museum_center := museum_aabb.get_center() if museum_has_aabb else Vector3.ZERO
				museum_center.y = 0.0
				var museum_transform := _centered_model_transform(pos, 0.0, Vector3.ONE, museum_center)
				var museum_built := _add_batched_model(root, museum_path, [museum_transform], "RichTownMuseum")
				_enhancement_stats["premium_museum_built"] = museum_built
				_enhancement_stats["premium_museum_fixed_scale"] = museum_built and museum_has_aabb and absf(museum_size.x - 54.00) <= 0.25 and absf(museum_size.y - 19.00) <= 0.20 and absf(museum_size.z - 38.00) <= 0.25
				_enhancement_stats["premium_museum_detail_pass"] = museum_built and museum_parts.size() >= 14 and museum_triangles >= 12000
				_enhancement_stats["premium_museum_material_pass"] = museum_built and _materials.has("museum_limestone") and _materials.has("museum_limestone_pale") and _materials.has("museum_bronze") and _materials.has("museum_glass_physical") and _materials.has("museum_interior") and _materials.has("museum_gallery_white") and _materials.has("museum_black_granite") and _materials.has("museum_travertine") and _materials.has("museum_pool_water") and _materials.has("museum_warm_light")
				_enhancement_stats["premium_museum_site_pass"] = museum_built and _materials.has("museum_black_granite") and _materials.has("museum_travertine") and _materials.has("museum_warm_light")
				_enhancement_stats["premium_museum_model_parts"] = museum_parts.size()
				_enhancement_stats["premium_museum_triangles"] = museum_triangles
				_enhancement_stats["premium_museum_width_m"] = museum_size.x
				_enhancement_stats["premium_museum_height_m"] = museum_size.y
				_enhancement_stats["premium_museum_depth_m"] = museum_size.z
				_enhancement_stats["premium_museum_fronts_fountain"] = museum_built
				if not museum_built:
					_add_box(root, Vector3(42.0, 3.0, 16.0), pos + Vector3(0.0, 1.5, 0.0), marble)
				_add_box_collider(pos + Vector3(0.0, 0.25, 0.0), Vector3(54.00, 0.50, 38.00))
				_add_box_collider(pos + Vector3(0.0, 8.40, -1.00), Vector3(45.60, 15.60, 29.60))
				_add_box_collider(pos + Vector3(-15.50, 0.45, 15.35), Vector3(17.00, 0.90, 2.70))
			"rt-opera":
				# Building Model No.6 is a fixed-scale 52.00 x 56.00 m
				# civic parcel and exactly 22.00 m high.  Blender -Y is
				# the public front; -PI/2 turns that curved foyer west
				# toward RichTown Boulevard (x=760), leaving the fly
				# tower and loading dock on the eastern service side.
				# The primitive marble box and three sand spheres are gone.
				var opera_path := "res://assets/buildings/opera_house.glb"
				var opera_parts := _get_model_parts(opera_path)
				var opera_triangles := 0
				var opera_aabb := AABB()
				var opera_has_aabb := false
				for opera_part_variant in opera_parts:
					var opera_part: Dictionary = opera_part_variant
					var opera_mesh := opera_part.get("mesh") as Mesh
					if opera_mesh == null:
						continue
					opera_triangles += _mesh_triangle_count(opera_mesh)
					var opera_part_aabb := opera_mesh.get_aabb()
					opera_aabb = opera_part_aabb if not opera_has_aabb else opera_aabb.merge(opera_part_aabb)
					opera_has_aabb = true
				var opera_size := opera_aabb.size if opera_has_aabb else Vector3.ZERO
				var opera_yaw := -PI * 0.5
				var opera_transform := _centered_model_transform(pos, opera_yaw, Vector3.ONE, Vector3.ZERO)
				var opera_built := _add_batched_model(root, opera_path, [opera_transform], "RichTownOpera")
				_enhancement_stats["premium_opera_built"] = opera_built
				_enhancement_stats["premium_opera_fixed_scale"] = opera_built and opera_has_aabb and absf(opera_size.x - 52.0) <= 0.25 and absf(opera_size.y - 22.0) <= 0.20 and absf(opera_size.z - 56.0) <= 0.25
				_enhancement_stats["premium_opera_detail_pass"] = opera_built and opera_parts.size() >= 14 and opera_triangles >= 18000
				_enhancement_stats["premium_opera_material_pass"] = opera_built and _materials.has("opera_shell_ceramic") and _materials.has("opera_travertine") and _materials.has("opera_bronze") and _materials.has("opera_glass_physical") and _materials.has("opera_interior") and _materials.has("opera_oak") and _materials.has("opera_black_granite") and _materials.has("opera_curtain_velvet") and _materials.has("opera_reflecting_water") and _materials.has("opera_warm_light")
				_enhancement_stats["premium_opera_site_pass"] = opera_built and _materials.has("villa_pavement") and _materials.has("villa_limestone") and _materials.has("villa_lawn") and _materials.has("villa_hedge") and _materials.has("villa_mulch")
				_enhancement_stats["premium_opera_model_parts"] = opera_parts.size()
				_enhancement_stats["premium_opera_triangles"] = opera_triangles
				_enhancement_stats["premium_opera_width_m"] = opera_size.x
				_enhancement_stats["premium_opera_height_m"] = opera_size.y
				_enhancement_stats["premium_opera_depth_m"] = opera_size.z
				_enhancement_stats["premium_opera_fronts_boulevard"] = opera_built and absf(opera_yaw + PI * 0.5) <= 0.001
				if not opera_built:
					_add_box(root, Vector3(48.0, 6.0, 28.0), pos + Vector3(0.0, 3.0, 0.0), marble)
					for i in 3:
						_add_sphere(root, 11.0 - float(i) * 1.4, h, pos + Vector3(-14.0 + float(i) * 14.0, 6.0 + h * 0.24, 0.0), sand)
				var opera_basis := Basis(Vector3.UP, opera_yaw)
				_add_box_collider(pos + Vector3(0.0, 0.25, 0.0), Vector3(52.0, 0.50, 56.0), opera_yaw)
				_add_box_collider(pos + opera_basis * Vector3(0.0, 11.0, 2.0), Vector3(46.70, 22.00, 36.70), opera_yaw)
				_add_box_collider(pos + opera_basis * Vector3(0.0, 10.10, 14.50), Vector3(25.55, 20.20, 10.55), opera_yaw)
				_add_box_collider(pos + opera_basis * Vector3(0.0, 0.45, -21.55), Vector3(39.00, 0.90, 3.82), opera_yaw)
				_add_box_collider(pos + opera_basis * Vector3(0.0, 0.80, -25.65), Vector3(10.50, 1.60, 0.60), opera_yaw)
				_add_cylinder_collider(pos + opera_basis * Vector3(-20.20, 2.50, -22.40), 1.55, 5.00)
			"rt-mosque":
				# Building Model No.7 is a finished fixed-scale mosque
				# measuring 38.40 x 36.00 m and exactly 30.00 m to the
				# minaret finials.  Blender +X is the eastern pishtaq
				# front, so at yaw 0 the portal faces the South Villa
				# District street gap and forecourt built in 0.2.24.
				# The sand box, plain sphere and two bare cylinders
				# are gone.
				var mosque_path := "res://assets/buildings/mosque.glb"
				var mosque_parts := _get_model_parts(mosque_path)
				var mosque_triangles := 0
				var mosque_aabb := AABB()
				var mosque_has_aabb := false
				for mosque_part_variant in mosque_parts:
					var mosque_part: Dictionary = mosque_part_variant
					var mosque_mesh := mosque_part.get("mesh") as Mesh
					if mosque_mesh == null:
						continue
					mosque_triangles += _mesh_triangle_count(mosque_mesh)
					var mosque_part_aabb := mosque_mesh.get_aabb()
					mosque_aabb = mosque_part_aabb if not mosque_has_aabb else mosque_aabb.merge(mosque_part_aabb)
					mosque_has_aabb = true
				var mosque_size := mosque_aabb.size if mosque_has_aabb else Vector3.ZERO
				var mosque_center := mosque_aabb.get_center() if mosque_has_aabb else Vector3.ZERO
				mosque_center.y = 0.0
				var mosque_transform := _centered_model_transform(pos, 0.0, Vector3.ONE, mosque_center)
				var mosque_built := _add_batched_model(root, mosque_path, [mosque_transform], "RichTownMosque")
				_enhancement_stats["premium_mosque_built"] = mosque_built
				_enhancement_stats["premium_mosque_fixed_scale"] = mosque_built and mosque_has_aabb and absf(mosque_size.x - 38.40) <= 0.25 and absf(mosque_size.y - 30.00) <= 0.20 and absf(mosque_size.z - 36.00) <= 0.25
				_enhancement_stats["premium_mosque_detail_pass"] = mosque_built and mosque_parts.size() >= 10 and mosque_triangles >= 30000
				_enhancement_stats["premium_mosque_material_pass"] = mosque_built and _materials.has("mosque_sandstone") and _materials.has("mosque_limestone") and _materials.has("mosque_dome_copper") and _materials.has("mosque_brass") and _materials.has("mosque_glass_physical") and _materials.has("mosque_interior") and _materials.has("mosque_cedar") and _materials.has("mosque_glazed_tile") and _materials.has("mosque_black_granite") and _materials.has("mosque_warm_light")
				_enhancement_stats["premium_mosque_site_pass"] = mosque_built and _materials.has("mosque_black_granite") and _materials.has("mosque_limestone") and _materials.has("mosque_warm_light")
				_enhancement_stats["premium_mosque_model_parts"] = mosque_parts.size()
				_enhancement_stats["premium_mosque_triangles"] = mosque_triangles
				_enhancement_stats["premium_mosque_width_m"] = mosque_size.x
				_enhancement_stats["premium_mosque_height_m"] = mosque_size.y
				_enhancement_stats["premium_mosque_depth_m"] = mosque_size.z
				_enhancement_stats["premium_mosque_fronts_east"] = mosque_built
				if not mosque_built:
					_add_box(root, Vector3(34.0, 13.0, 30.0), pos + Vector3(0.0, 6.5, 0.0), sand)
					_add_sphere(root, 11.5, 19.0, pos + Vector3(0.0, 15.0, 0.0), marble)
					for side in [-1.0, 1.0]:
						var fallback_minaret_pos := pos + Vector3(19.0 * side, h * 0.5, 0.0)
						_add_cylinder(root, 1.4, h, fallback_minaret_pos, sand, 0.0, 14)
				_add_box_collider(pos + Vector3(0.0, 0.25, 0.0), Vector3(38.40, 0.50, 36.00))
				_add_box_collider(pos + Vector3(0.0, 6.60, 0.0), Vector3(28.00, 13.20, 32.00))
				_add_box_collider(pos + Vector3(16.10, 9.20, 0.0), Vector3(4.40, 18.40, 16.20))
				_add_box_collider(pos + Vector3(-14.70, 4.60, 0.0), Vector3(1.60, 9.20, 8.60))
				for side in [-1.0, 1.0]:
					_add_box_collider(pos + Vector3(1.0, 2.80, 16.90 * side), Vector3(24.50, 5.60, 2.30))
					_add_box_collider(pos + Vector3(-16.55, 3.00, 13.50 * side), Vector3(5.30, 6.00, 5.30))
					_add_cylinder_collider(pos + Vector3(-16.55, 15.00, 13.50 * side), 1.45, 30.00)

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


## 0.2.37 Sail Island resort landscaping.  Terrain, loop road, villas
## and pools are registered by `_expand_sail_island_0237()`; this pass
## dresses the enlarged island with a stone arrival forecourt, pool
## terraces, clipped hedges, a continuous seaside promenade, a small
## pier, palm alleys and real Blender lamps/benches/pergolas.  All
## repeated geometry goes through the existing MultiMesh/model queues
## (with their HLOD ranges), so the island does not become hundreds
## of individual draw calls.
func _build_sail_island_resort_0237() -> void:
	var root := Node3D.new()
	root.name = "SailIslandResort0237"
	add_child(root)

	var unit_box := BoxMesh.new()
	unit_box.size = Vector3.ONE
	var unit_cylinder := CylinderMesh.new()
	unit_cylinder.top_radius = 0.5
	unit_cylinder.bottom_radius = 0.5
	unit_cylinder.height = 1.0
	unit_cylinder.radial_segments = 28
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

	var paving_material := _terrain_material("plaza")
	var stone_material := _prop_material("VillaStone")
	var hedge_material := _prop_material("VillaHedge")
	var wood_material := _prop_material("PropsWood")
	var metal_material := _prop_material("PropsMetal")
	var lawn_material := _material("park_lawn", "user_grass.jpg", "user_grass_normal.jpg", Color(0.52, 0.74, 0.38), 0.96, 0.0, Vector3(0.55, 0.55, 0.55), true)

	# Arrival apron west of the podium, the east infinity-pool
	# deck, the north/south reflecting-pool terraces and a stone pad
	# under every resort villa (read back from data so a sanitized
	# parcel and its pad can never drift apart).  0.2.38 sizes are
	# fitted to the inside of the 48x46 m oval and then re-checked
	# against the road grid: the 0.2.37 rectangles all crossed the
	# carriageway (the beige slabs cutting the loop in the phone
	# screenshots), because nobody audited them against the road
	# they were built around.
	var resort_min_road_clearance := INF
	var resort_rejected_road_overlaps := 0
	var paving_transforms: Array = []
	for spec in [
		{"x": 1149.8, "z": 80.0, "w": 4.4, "d": 18.0, "yaw": 0.0},
		{"x": 1216.0, "z": 80.0, "w": 20.0, "d": 32.0, "yaw": 0.0},
		{"x": 1186.0, "z": 50.0, "w": 39.0, "d": 8.5, "yaw": 0.0},
		{"x": 1186.0, "z": 110.0, "w": 39.0, "d": 8.5, "yaw": 0.0},
	]:
		var px := _f(spec, "x")
		var pz := _f(spec, "z")
		var spec_yaw := _f(spec, "yaw")
		var spec_clearance := _rect_road_clearance_0237(Vector3(px, 0.0, pz), Vector2(_f(spec, "w"), _f(spec, "d")), spec_yaw)
		resort_min_road_clearance = minf(resort_min_road_clearance, spec_clearance)
		if spec_clearance < 0.9:
			resort_rejected_road_overlaps += 1
			continue
		paving_transforms.append(make_transform(
			Vector3(px, height_at(px, pz) + 0.08, pz),
			spec_yaw,
			Vector3(_f(spec, "w"), 0.16, _f(spec, "d"))
		))
	var resort_villa_count := 0
	for building_variant in data.get("buildings", []):
		var building: Dictionary = building_variant
		if not bool(building.get("sail_resort_0237", false)):
			continue
		resort_villa_count += 1
		var villa_pos := _item_position(building)
		var villa_yaw := _f(building, "rotY")
		var is_cottage_estate := String(building.get("model", "")).begins_with("cottage_")
		var pad_size := Vector2(35.96, 27.01) if is_cottage_estate else Vector2(24.0, 20.0)
		var pad_clearance := _rect_road_clearance_0237(villa_pos, pad_size, villa_yaw)
		resort_min_road_clearance = minf(resort_min_road_clearance, pad_clearance)
		if pad_clearance < 0.9:
			resort_rejected_road_overlaps += 1
			continue
		if is_cottage_estate:
			# 0.2.39: each cottage GLB already carries its own
			# mineral site, drive, paths and pool terrace on the
			# basalt podium -- the old plain 24 x 20 m villa pad
			# would only z-fight underneath it.
			continue
		paving_transforms.append(make_transform(
			Vector3(villa_pos.x, villa_pos.y + 0.05, villa_pos.z),
			villa_yaw,
			Vector3(24.0, 0.12, 20.0)
		))
	_add_multimesh(root, unit_box, paving_material, paving_transforms, "SailIslandPaving", false, -1.0, 420.0, 180.0)

	var lawn_transforms: Array = []
	for spec in [
		# 0.2.39: the old 54 x 22 m north/south ellipses ran under
		# the new 36 x 27 m estate lots.  Fit the public lawns to
		# the real gaps between the estates and the promenade, and
		# give the open south-west corner its own lookout lawn.
		{"x": 1185.0, "z": 0.0, "w": 28.0, "d": 10.0},
		{"x": 1185.0, "z": 160.0, "w": 28.0, "d": 10.0},
		{"x": 1266.0, "z": 80.0, "w": 30.0, "d": 54.0},
		{"x": 1104.0, "z": 35.0, "w": 36.0, "d": 28.0},
		{"x": 1104.0, "z": 125.0, "w": 36.0, "d": 28.0},
		{"x": 1145.0, "z": 141.0, "w": 30.0, "d": 21.0},
	]:
		var px := _f(spec, "x")
		var pz := _f(spec, "z")
		lawn_transforms.append(make_transform(
			Vector3(px, height_at(px, pz) + 0.05, pz),
			0.0,
			Vector3(_f(spec, "w"), 0.12, _f(spec, "d"))
		))
	_add_multimesh(root, unit_cylinder, lawn_material, lawn_transforms, "SailIslandLawns", false, -1.0, 420.0, 180.0)

	var hedge_transforms: Array = []
	for hx in range(1162, 1210, 11):
		for hz in [57.5, 102.5]:
			var hedge_pos := Vector3(float(hx), height_at(float(hx), hz) + 0.45, hz)
			var row_clearance := _rect_road_clearance_0237(hedge_pos, Vector2(9.0, 1.0), 0.0)
			resort_min_road_clearance = minf(resort_min_road_clearance, row_clearance)
			if row_clearance < 0.9:
				resort_rejected_road_overlaps += 1
				continue
			hedge_transforms.append(make_transform(hedge_pos, 0.0, Vector3(9.0, 0.9, 1.0)))
	# Short end hedges stop well inside the oval; the 0.2.37
	# 14-20 m bars ran straight across both driving lanes.
	for spec in [
		{"x": 1157.0, "z": 61.0, "w": 8.0, "d": 1.0},
		{"x": 1157.0, "z": 99.0, "w": 8.0, "d": 1.0},
		{"x": 1215.0, "z": 61.0, "w": 10.0, "d": 1.0},
		{"x": 1215.0, "z": 99.0, "w": 10.0, "d": 1.0},
	]:
		var px := _f(spec, "x")
		var pz := _f(spec, "z")
		var hedge_clearance := _rect_road_clearance_0237(Vector3(px, 0.0, pz), Vector2(_f(spec, "w"), _f(spec, "d")), 0.0)
		resort_min_road_clearance = minf(resort_min_road_clearance, hedge_clearance)
		if hedge_clearance < 0.9:
			resort_rejected_road_overlaps += 1
			continue
		hedge_transforms.append(make_transform(
			Vector3(px, height_at(px, pz) + 0.45, pz),
			0.0,
			Vector3(_f(spec, "w"), 0.9, _f(spec, "d"))
		))
	_add_multimesh(root, unit_box, hedge_material, hedge_transforms, "SailIslandHedges", false, -1.0, 260.0, 180.0)

	# Continuous stone promenade on the beach ring with a low sea
	# wall on its outer edge.  The terrain height is a function of the
	# same elliptical coordinate, so each flat segment sits on the
	# shore without floating ends.
	var promenade_transforms: Array = []
	var seawall_transforms: Array = []
	var promenade_segments := 64
	for i in promenade_segments:
		var a0 := TAU * float(i) / float(promenade_segments)
		var a1 := TAU * float(i + 1) / float(promenade_segments)
		var p0 := Vector2(SAIL_ISLAND_CENTRE.x + cos(a0) * 112.0, SAIL_ISLAND_CENTRE.y + sin(a0) * 92.0)
		var p1 := Vector2(SAIL_ISLAND_CENTRE.x + cos(a1) * 112.0, SAIL_ISLAND_CENTRE.y + sin(a1) * 92.0)
		var mid := (p0 + p1) * 0.5
		# The ellipse meets the causeway on the west shore; leave a
		# clean gap there instead of laying a stone band across the
		# carriageway.
		if _road_clearance_xz(Vector3(mid.x, 0.0, mid.y)) < 2.5:
			continue
		var direction := Vector3(p1.x - p0.x, 0.0, p1.y - p0.y)
		var segment_yaw := _yaw_for_x_direction(direction)
		var segment_length := p0.distance_to(p1) + 0.35
		promenade_transforms.append(make_transform(
			Vector3(mid.x, height_at(mid.x, mid.y) + 0.10, mid.y),
			segment_yaw,
			Vector3(segment_length, 0.18, 3.2)
		))
		var am := (a0 + a1) * 0.5
		var outer := Vector2(SAIL_ISLAND_CENTRE.x + cos(am) * 115.5, SAIL_ISLAND_CENTRE.y + sin(am) * 95.5)
		seawall_transforms.append(make_transform(
			Vector3(outer.x, height_at(outer.x, outer.y) + 0.28, outer.y),
			segment_yaw,
			Vector3(segment_length, 0.55, 0.55)
		))
	_add_multimesh(root, unit_box, stone_material, promenade_transforms, "SailIslandPromenade", false, -1.0, 560.0, 180.0)
	_add_multimesh(root, unit_box, _terrain_material("concrete"), seawall_transforms, "SailIslandPromenadeCurbs", false, -1.0, 420.0, 180.0)

	# East pier: deck, piles and a simple handrail over the water.
	var pier_deck_transforms: Array = [make_transform(Vector3(1314.0, 0.68, 80.0), 0.0, Vector3(36.0, 0.28, 4.2))]
	var pier_post_transforms: Array = []
	for px in range(1298, 1331, 8):
		for pz in [78.1, 81.9]:
			pier_post_transforms.append(make_transform(Vector3(float(px), 0.05, pz), 0.0, Vector3(0.34, 1.7, 0.34)))
	var pier_rail_transforms: Array = [
		make_transform(Vector3(1314.0, 1.55, 78.0), 0.0, Vector3(36.0, 0.08, 0.08)),
		make_transform(Vector3(1314.0, 1.55, 82.0), 0.0, Vector3(36.0, 0.08, 0.08)),
	]
	_add_multimesh(root, unit_box, wood_material, pier_deck_transforms, "SailIslandPierDeck", false, -1.0, 520.0, 180.0)
	_add_multimesh(root, unit_cylinder, wood_material, pier_post_transforms, "SailIslandPierPosts", false, -1.0, 420.0, 180.0)
	_add_multimesh(root, unit_box, metal_material, pier_rail_transforms, "SailIslandPierRails", false, -1.0, 420.0, 180.0)
	_add_box_collider(Vector3(1314.0, 0.7, 80.0), Vector3(36.0, 1.4, 4.2))

	# Palm alleys: one ring outside the loop (skipping the causeway
	# axis to the west) plus two beach groves.  Detailed Blender
	# palms only -- the far proxies are generated by the model queue.
	var date_palm_transforms: Array = []
	var royal_palm_transforms: Array = []
	var palm_points: Array[Vector2] = []
	for degree_variant in [-150.0, -120.0, -90.0, -60.0, -30.0, 0.0, 30.0, 60.0, 90.0, 120.0, 150.0]:
		var angle := deg_to_rad(degree_variant)
		palm_points.append(Vector2(1188.0 + cos(angle) * 57.0, 80.0 + sin(angle) * 55.0))
	for point in [Vector2(1248, 150), Vector2(1215, 164), Vector2(1155, 164), Vector2(1122, 150), Vector2(1122, 10), Vector2(1155, -4), Vector2(1215, -4), Vector2(1248, 10)]:
		palm_points.append(point)
	var palm_index := 0
	for point in palm_points:
		var palm_pos := Vector3(point.x, height_at(point.x, point.y) - 0.03, point.y)
		if not _is_position_clear(palm_pos, 1.5, 2.5):
			continue
		var palm_scale := 0.92 + _hash01(palm_index * 13 + 7, palm_index * 17 + 3) * 0.16
		var palm_transform := make_transform(palm_pos, _hash01(palm_index * 19 + 5, palm_index * 23 + 11) * TAU, Vector3.ONE * palm_scale)
		if palm_index % 2 == 0:
			date_palm_transforms.append(palm_transform)
		else:
			royal_palm_transforms.append(palm_transform)
		_add_cylinder_collider(palm_pos + Vector3(0.0, 2.8, 0.0), 0.34, 5.8)
		palm_index += 1
	# One detailed garden palm per cottage estate, on the front lawn
	# opposite its gate.  The GLBs deliberately ship without palms so
	# the game reuses the high-detail date/royal vegetation models;
	# these authored local points clear the house, drive and pool.
	var cottage_garden_palms := 0
	for building_variant in data.get("buildings", []):
		var building: Dictionary = building_variant
		if not bool(building.get("sail_cottage_0239", false)):
			continue
		var cottage_model := String(building.get("model", ""))
		var estate_pos := _item_position(building)
		var estate_yaw := _f(building, "rotY")
		estate_pos.y = _cottage_estate_ground_y_0239(estate_pos, estate_yaw)
		var garden_local := Vector3(13.0, 0.05, 9.5) if cottage_model == "cottage_dune" else Vector3(-13.0, 0.05, 9.5)
		var garden_palm_pos: Vector3 = estate_pos + Basis(Vector3.UP, estate_yaw) * garden_local
		var garden_palm_transform := make_transform(garden_palm_pos, estate_yaw + 0.7 + float(cottage_garden_palms) * 0.85, Vector3.ONE * 0.95)
		if cottage_model == "cottage_courtyard":
			royal_palm_transforms.append(garden_palm_transform)
		else:
			date_palm_transforms.append(garden_palm_transform)
		_add_cylinder_collider(garden_palm_pos + Vector3(0.0, 2.8, 0.0), 0.34, 5.8)
		cottage_garden_palms += 1
	var island_palms_built := _add_batched_model(root, "res://assets/vegetation/palm_date.glb", date_palm_transforms, "BlenderDatePalms")
	island_palms_built = _add_batched_model(root, "res://assets/vegetation/palm_royal.glb", royal_palm_transforms, "BlenderRoyalPalms") or island_palms_built

	# Real lamp/bench/pergola models around the loop and promenade.
	var lamp_transforms: Array = []
	var lamp_points: Array[Vector2] = []
	for degree_variant in [-157.0, -112.0, -67.0, -22.0, 22.0, 67.0, 112.0, 157.0]:
		var angle := deg_to_rad(degree_variant)
		lamp_points.append(Vector2(1188.0 + cos(angle) * 56.0, 80.0 + sin(angle) * 54.0))
	for degree_variant in [-90.0, 0.0, 90.0]:
		var angle := deg_to_rad(degree_variant)
		lamp_points.append(Vector2(SAIL_ISLAND_CENTRE.x + cos(angle) * 109.0, SAIL_ISLAND_CENTRE.y + sin(angle) * 89.0))
	for point_index in lamp_points.size():
		var point := lamp_points[point_index]
		var lamp_pos := Vector3(point.x, height_at(point.x, point.y) + 0.02, point.y)
		if not _is_position_clear(lamp_pos, 0.6, 1.0):
			continue
		var radial := Vector3(point.x - 1187.0, 0.0, point.y - 80.0)
		# Lamp GLB arm reaches along local +Z: loop lamps reach
		# inward over the carriageway, promenade lamps reach outward
		# over the seaside path.
		var lamp_target := -radial if point_index < 8 else radial
		lamp_transforms.append(make_transform(lamp_pos, _yaw_for_z_normal(lamp_target), Vector3.ONE))
		_add_cylinder_collider(lamp_pos + Vector3(0.0, 3.2, 0.0), 0.18, 6.6)
	_add_batched_model(root, "res://assets/props/street_lamp.glb", lamp_transforms, "BlenderStreetLamps")

	var bench_transforms: Array = []
	var bench_index := 0
	for degree_variant in [22.0, 67.0, 112.0, 157.0, 202.0, 247.0, 292.0, 337.0]:
		var angle := deg_to_rad(degree_variant)
		var point := Vector2(SAIL_ISLAND_CENTRE.x + cos(angle) * 109.0, SAIL_ISLAND_CENTRE.y + sin(angle) * 89.0)
		var bench_pos := Vector3(point.x, height_at(point.x, point.y) + 0.04, point.y)
		if not _is_position_clear(bench_pos, 0.8, 1.0):
			continue
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		# Park-bench GLB seat front faces local -Z: point local +Z
		# back toward the island so sitters face the sea.
		var bench_yaw := _yaw_for_z_normal(-outward)
		bench_transforms.append(make_transform(bench_pos, bench_yaw, Vector3.ONE))
		_add_box_collider(bench_pos + Vector3(0.0, 0.5, 0.0), Vector3(2.4, 1.0, 0.8), bench_yaw)
		bench_index += 1
	_add_batched_model(root, "res://assets/props/park_bench.glb", bench_transforms, "BlenderParkBenches")

	var pergola_transforms: Array = []
	for spec in [
		{"x": 1185.0, "z": 8.0, "yaw": 0.0},
		{"x": 1185.0, "z": 152.0, "yaw": PI},
		# 0.2.39: the south-west corner stays an open lookout
		# garden instead of a fourth cottage copy.
		{"x": 1145.0, "z": 141.0, "yaw": 0.75},
	]:
		var px := _f(spec, "x")
		var pz := _f(spec, "z")
		var yaw := _f(spec, "yaw")
		var pergola_pos := Vector3(px, height_at(px, pz) + 0.04, pz)
		pergola_transforms.append(make_transform(pergola_pos, yaw, Vector3.ONE))
		# The GLB is the hexagonal Museum pergola: six columns on a
		# 5.2 m ring at 30-degree offset (see the parks pass).
		for column_index in 6:
			var column_angle := yaw + TAU * float(column_index) / 6.0 + PI / 6.0
			var post_pos := pergola_pos + Vector3(cos(column_angle) * 5.2, 0.0, sin(column_angle) * 5.2)
			post_pos.y = height_at(post_pos.x, post_pos.z)
			_add_cylinder_collider(post_pos + Vector3(0.0, 1.55, 0.0), 0.4, 3.1)
	_add_batched_model(root, "res://assets/props/park_pergola.glb", pergola_transforms, "BlenderParkPergola")

	# A neat double row of beach umbrellas/loungers on the east
	# beach, replacing the random mainland scatter on this shore.
	var cabana_pole_transforms: Array = []
	var cabana_canopy_transforms: Array = [[], [], []]
	var cabana_lounger_transforms: Array = []
	var cabana_materials: Array[StandardMaterial3D] = [
		_material("beach_umbrella_red", "", "", Color(0.78, 0.12, 0.10), 0.78),
		_material("beach_umbrella_blue", "", "", Color(0.08, 0.34, 0.74), 0.78),
		_material("beach_umbrella_teal", "", "", Color(0.05, 0.58, 0.54), 0.78),
	]
	var cabana_index := 0
	for degree_variant in [25.0, 40.0, 55.0, 125.0, 140.0, 155.0]:
		var angle := deg_to_rad(degree_variant)
		var point := Vector2(SAIL_ISLAND_CENTRE.x + cos(angle) * 118.0, SAIL_ISLAND_CENTRE.y + sin(angle) * 98.0)
		var cabana_pos := Vector3(point.x, height_at(point.x, point.y), point.y)
		cabana_pole_transforms.append(make_transform(cabana_pos + Vector3(0.0, 1.05, 0.0), angle, Vector3.ONE))
		(cabana_canopy_transforms[cabana_index % 3] as Array).append(make_transform(cabana_pos + Vector3(0.0, 2.05, 0.0), angle, Vector3.ONE))
		var outward := Vector2(cos(angle), sin(angle))
		var lounger_point := point + outward * 2.1
		var lounger_pos := Vector3(lounger_point.x, height_at(lounger_point.x, lounger_point.y) + 0.22, lounger_point.y)
		cabana_lounger_transforms.append(make_transform(lounger_pos, _yaw_for_x_direction(Vector3(outward.x, 0.0, outward.y)), Vector3(1.8, 0.18, 0.65)))
		cabana_index += 1
	_add_multimesh(root, umbrella_pole_mesh, metal_material, cabana_pole_transforms, "SailIslandBeachPoles", false, -1.0, 360.0, 180.0)
	for cabana_group in 3:
		_add_multimesh(root, umbrella_canopy_mesh, cabana_materials[cabana_group], cabana_canopy_transforms[cabana_group], "SailIslandBeachUmbrellas_%d" % cabana_group, false, -1.0, 360.0, 180.0)
	_add_multimesh(root, unit_box, _material("city_white_painted", "", "", Color(0.90, 0.92, 0.90), 0.52, 0.05), cabana_lounger_transforms, "SailIslandBeachLoungers", false, -1.0, 360.0, 180.0)

	# Read the pools back after the canonical sanitizer: the stats
	# below describe where the water/rims were actually built.
	var sail_pool_count := 0
	var sail_pool_min_clearance := INF
	for pool_variant in data.get("pools", []):
		var pool: Dictionary = pool_variant
		if not bool(pool.get("sail_resort_0237", false)):
			continue
		sail_pool_count += 1
		sail_pool_min_clearance = minf(sail_pool_min_clearance, _rect_road_clearance_0237(
			_item_position(pool),
			Vector2(_f(pool, "w", 8.0) + 1.3, _f(pool, "d", 5.0) + 1.3),
			_f(pool, "rotY")
		))

	_enhancement_stats["sail_island_resort_0237"] = true
	_enhancement_stats["sail_island_paving_0237"] = paving_transforms.size()
	_enhancement_stats["sail_island_hedges_0238"] = hedge_transforms.size()
	_enhancement_stats["sail_resort_min_road_clearance_0238"] = resort_min_road_clearance
	_enhancement_stats["sail_resort_rejected_road_overlaps_0238"] = resort_rejected_road_overlaps
	_enhancement_stats["sail_pools_final_0238"] = sail_pool_count
	_enhancement_stats["sail_pool_min_road_clearance_0238"] = sail_pool_min_clearance
	_enhancement_stats["sail_loop_road_repair_0238"] = resort_min_road_clearance >= 0.9 and resort_rejected_road_overlaps == 0 and sail_pool_count >= 3 and sail_pool_min_clearance >= 1.2 and bool(_enhancement_stats.get("sail_loop_entry_pad_0238", false)) and bool(_enhancement_stats.get("sail_loop_clean_markings_0238", false)) and bool(_enhancement_stats.get("sail_loop_pristine_asphalt_0238", false))
	_enhancement_stats["sail_island_promenade_segments_0237"] = promenade_transforms.size()
	_enhancement_stats["sail_island_palms_0237"] = date_palm_transforms.size() + royal_palm_transforms.size() if island_palms_built else 0
	_enhancement_stats["sail_island_lamps_0237"] = lamp_transforms.size()
	_enhancement_stats["sail_island_benches_0237"] = bench_transforms.size()
	_enhancement_stats["sail_island_pergolas_0237"] = pergola_transforms.size()
	_enhancement_stats["sail_island_cabanas_0237"] = cabana_pole_transforms.size()
	_enhancement_stats["sail_resort_villas_built_0237"] = resort_villa_count
	_enhancement_stats["sail_cottage_garden_palms_0239"] = cottage_garden_palms
	_enhancement_stats["sail_open_lookout_0239"] = pergola_transforms.size() >= 3 and lawn_transforms.size() >= 6
	_enhancement_stats["sail_cottage_resort_fit_0239"] = resort_villa_count == 3 and cottage_garden_palms == 3 and resort_rejected_road_overlaps == 0


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
	_foliage_points.clear()
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
		var rejected_road_trees := 0
		for tree_variant in trees:
			var tree: Dictionary = tree_variant
			var tree_base := _item_position(tree, -0.04)
			if _road_clearance_xz(tree_base) < 0.65:
				rejected_road_trees += 1
				continue
			_foliage_points.append(tree_base)
			var scale_value := 2.85 * _f(tree, "s", 1.0)
			tree_transforms.append(make_transform(tree_base, _f(tree, "rotY"), Vector3.ONE * scale_value))
			_add_cylinder_collider(_item_position(tree, 1.4), 0.38, 3.2)
		_enhancement_stats["rejected_road_trees_0236"] = rejected_road_trees
		for part_name in ["tree2_bark", "tree2_foliage"]:
			if _plant_parts.has(part_name):
				var part: Dictionary = _plant_parts[part_name]
				var source_mesh := part.get("mesh") as Mesh
				# The 199-triangle trunk can stay visible much farther
				# than the 7.8k canopy. Trunks keep a grounding shadow;
				# the canopy HLOD ellipsoid takes over after 220 m.
				var detail_end := 150.0 if part_name == "tree2_bark" else 105.0
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
					_add_foliage_far_proxy(root, source_mesh, tree_transforms, part_name, 90.0, 650.0)

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
		var rejected_road_bushes := 0
		for i in bushes.size():
			var bush: Dictionary = bushes[i]
			var bush_base := _item_position(bush, -0.03)
			if _road_clearance_xz(bush_base) < 0.65:
				rejected_road_bushes += 1
				continue
			var part_name := bush_names[i % bush_names.size()]
			var target_height := 1.45 if part_name == "bush_round_foliage" else (2.25 if part_name == "shrub_cone_foliage" else 1.25)
			var source_height := 0.77 if part_name == "bush_round_foliage" else (1.65 if part_name == "shrub_cone_foliage" else 0.60)
			var scale_value := target_height / source_height * _f(bush, "s", 1.0)
			(bush_transforms[part_name] as Array).append(make_transform(bush_base, _f(bush, "rotY"), Vector3.ONE * scale_value))
		_enhancement_stats["rejected_road_bushes_0236"] = rejected_road_bushes
		for part_name in bush_transforms.keys():
			if _plant_parts.has(part_name):
				var part: Dictionary = _plant_parts[part_name]
				var source_mesh := part.get("mesh") as Mesh
				var part_transforms: Array = bush_transforms[part_name]
				# Detailed shrubs retire near the road; fitted low-poly
				# ellipsoids preserve only larger planting masses beyond.
				_add_multimesh(
					root,
					source_mesh,
					part.get("material") as Material,
					part_transforms,
					String(part_name),
					false,
					0.0,
					90.0,
					180.0
				)
				_add_foliage_far_proxy(root, source_mesh, part_transforms, String(part_name), 80.0, 260.0)

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

	# 0.2.17: replace the old cylinder + ten flat alpha-card fronds with
	# two fixed-metre Blender species.  The GLBs already contain curved
	# segmented trunks, individual V-folded leaflets, petiole/rachis
	# tubes, a fibrous crown (and date clusters/skirt on the date palm).
	# Normalising the 8.8 m / 10.2 m source heights to the exported
	# street-palm envelope preserves the master-plan positions without
	# shrinking RichTown or the player car.
	var date_palm_transforms: Array[Transform3D] = []
	var royal_palm_transforms: Array[Transform3D] = []
	var boulevard_date_palm_count := 0
	var rejected_road_palms := 0
	for palm_index in palms.size():
		var palm: Dictionary = palms[palm_index]
		var exported_scale := clampf(_f(palm, "s", 1.0), 0.82, 1.30)
		var base := _item_position(palm, -0.03)
		# Four exported master-plan palms sit inside carriageways
		# (including one in the Boulevard/St-4 junction).  A trunk is
		# a collision object, so reject any palm base without a real
		# kerbside clearance instead of planting it in a lane.
		if _road_clearance_xz(base) < 0.65:
			rejected_road_palms += 1
			continue
		_foliage_points.append(base)
		var variation := _hash01(palm_index * 17 + 41, palm_index * 29 + 7)
		var is_boulevard_row := minf(absf(base.x - 745.5), absf(base.x - 774.5)) < 0.75
		var use_royal := false
		if is_boulevard_row:
			# 0.2.19: the reference avenue is planted with broad, dense
			# date palms.  The 0.2.18 royal row was stretched 1.30x in
			# height and narrowed to 0.90x, which read as bare poles
			# with a few drooping strands on the phone.
			use_royal = false
		elif base.x >= 620.0 and base.x <= 720.0 and base.z >= -180.0 and base.z <= 120.0:
			use_royal = palm_index % 3 != 0
		elif base.x >= 720.0 and base.x <= 805.0:
			use_royal = palm_index % 2 == 0
		elif base.x < 260.0:
			use_royal = palm_index % 4 == 0
		else:
			use_royal = variation > 0.82
		var species_scale := 0.76 if use_royal else 0.78
		var uniform_scale := exported_scale * species_scale
		var width_scale := uniform_scale * (0.94 + variation * 0.12)
		var height_scale := uniform_scale * (0.94 + _hash01(palm_index * 31 + 5, palm_index * 13 + 53) * 0.12)
		if is_boulevard_row:
			# Source date palm: 8.47 m crown width x 8.82 m high.
			# At the exported scale this produces roughly a 7.5-8.0 m
			# crown over a 7.7-8.5 m trunk, matching the reference
			# instead of a 10 m Washingtonia-like pole.
			width_scale = uniform_scale * 1.18
			height_scale = uniform_scale * 1.12
			boulevard_date_palm_count += 1
		var palm_transform := make_transform(base, _f(palm, "rotY") + variation * 0.37, Vector3(width_scale, height_scale, width_scale))
		if use_royal:
			royal_palm_transforms.append(palm_transform)
		else:
			date_palm_transforms.append(palm_transform)
		_add_cylinder_collider(base + Vector3(0.0, 3.0 * exported_scale, 0.0), 0.34, 6.2 * exported_scale)
	var date_palms_built := _add_batched_model(root, "res://assets/vegetation/palm_date.glb", date_palm_transforms, "BlenderDatePalms")
	var royal_palms_built := _add_batched_model(root, "res://assets/vegetation/palm_royal.glb", royal_palm_transforms, "BlenderRoyalPalms")
	_enhancement_stats["detailed_palms_0217"] = date_palms_built or royal_palms_built
	_enhancement_stats["date_palms"] = date_palm_transforms.size() if date_palms_built else 0
	_enhancement_stats["royal_palms"] = royal_palm_transforms.size() if royal_palms_built else 0
	_enhancement_stats["boulevard_date_palms"] = boulevard_date_palm_count if date_palms_built else 0
	_enhancement_stats["boulevard_royal_palms"] = 0
	_enhancement_stats["detailed_palms"] = int(_enhancement_stats.get("date_palms", 0)) + int(_enhancement_stats.get("royal_palms", 0))
	_enhancement_stats["rejected_road_palms_0236"] = rejected_road_palms


func _is_soft_ground_cover_surface(candidate: Vector3, allow_sand: bool = false) -> bool:
	if candidate.y < 1.02:
		return false
	if _in_zone(candidate.x, candidate.z, "sea") or _in_zone(candidate.x, candidate.z, "marina"):
		return false
	if _is_in_park(candidate.x, candidate.z):
		return false
	var slope := maxf(
		absf(height_at(candidate.x + 1.2, candidate.z) - candidate.y),
		absf(height_at(candidate.x, candidate.z + 1.2) - candidate.y)
	) / 1.2
	if slope > 0.42:
		return false
	var kind := String(get_surface_at(candidate).get("kind", ""))
	if kind == "grass":
		return true
	return allow_sand and kind == "sand"


func _build_ground_cover() -> void:
	var root := Node3D.new()
	root.name = "DetailedGroundCover"
	add_child(root)

	# Desired counts are caps per district, not unconditional spawn
	# quotas.  Every candidate still has to land on actual grass (or
	# dune sand for grass/shrubs), above water, on a gentle slope and
	# clear of carriageways/buildings/landmarks.  That keeps flowers
	# out of asphalt and intersections while filling the previously
	# flat green terrain rectangles with real geometry.
	var patches: Array[Dictionary] = [
		{"rect": Rect2(690.0, 235.0, 150.0, 190.0), "grass": 620, "flowers": 125, "shrubs": 34},
		{"rect": Rect2(585.0, -115.0, 165.0, 180.0), "grass": 520, "flowers": 150, "shrubs": 36},
		{"rect": Rect2(590.0, -270.0, 215.0, 205.0), "grass": 520, "flowers": 105, "shrubs": 34},
		{"rect": Rect2(700.0, -445.0, 125.0, 890.0), "grass": 720, "flowers": 140, "shrubs": 44},
		{"rect": Rect2(520.0, -445.0, 100.0, 890.0), "grass": 620, "flowers": 115, "shrubs": 42},
		{"rect": Rect2(865.0, -455.0, 145.0, 910.0), "grass": 620, "flowers": 100, "shrubs": 40},
		{"rect": Rect2(1000.0, -455.0, 480.0, 910.0), "grass": 760, "flowers": 90, "shrubs": 50},
		{"rect": Rect2(810.0, 120.0, 220.0, 280.0), "grass": 420, "flowers": 75, "shrubs": 30},
	]
	var species_specs: Array[Dictionary] = [
		{
			"key": "grass",
			"stat": "grass_tufts",
			"allow_sand": true,
			"building_padding": 0.8,
			"road_clearance": 2.35,
			"min_scale": 0.85,
			"max_scale": 1.55,
		},
		{
			"key": "flowers",
			"stat": "flower_clumps",
			"allow_sand": false,
			"building_padding": 0.9,
			"road_clearance": 2.45,
			"min_scale": 0.80,
			"max_scale": 1.35,
		},
		{
			"key": "shrubs",
			"stat": "ornamental_shrubs",
			"allow_sand": true,
			"building_padding": 1.6,
			"road_clearance": 2.85,
			"min_scale": 0.80,
			"max_scale": 1.50,
		},
	]
	var transforms_by_species: Dictionary = {"grass": [], "flowers": [], "shrubs": []}

	for species_index in species_specs.size():
		var species: Dictionary = species_specs[species_index]
		var species_key := String(species.get("key", "grass"))
		var target_transforms: Array = transforms_by_species[species_key]
		for patch_index in patches.size():
			var patch: Dictionary = patches[patch_index]
			var rect: Rect2 = patch.get("rect", Rect2())
			var desired := int(patch.get(species_key, 0))
			var accepted := 0
			for attempt in desired * 12:
				if accepted >= desired:
					break
				var seed_base := patch_index * 100000 + species_index * 1000000 + attempt
				var candidate := Vector3(
					rect.position.x + _hash01(seed_base * 3 + 11, seed_base * 5 + 71) * rect.size.x,
					0.0,
					rect.position.y + _hash01(seed_base * 7 + 31, seed_base * 11 + 97) * rect.size.y
				)
				candidate.y = height_at(candidate.x, candidate.z) + 0.006
				if not _is_soft_ground_cover_surface(candidate, bool(species.get("allow_sand", false))):
					continue
				if not _is_position_clear(
					candidate,
					float(species.get("building_padding", 1.0)),
					float(species.get("road_clearance", 2.4))
				):
					continue
				var width_variation := _hash01(seed_base * 13 + 17, seed_base * 17 + 43)
				var height_variation := _hash01(seed_base * 19 + 23, seed_base * 23 + 59)
				var min_scale := float(species.get("min_scale", 0.8))
				var max_scale := float(species.get("max_scale", 1.4))
				var width_scale := lerpf(min_scale, max_scale, width_variation)
				var height_scale := lerpf(min_scale, max_scale, height_variation)
				target_transforms.append(make_transform(
					candidate,
					_hash01(seed_base * 29 + 3, seed_base * 31 + 13) * TAU,
					Vector3(width_scale, height_scale, width_scale)
				))
				accepted += 1
		transforms_by_species[species_key] = target_transforms

	var grass_built := _add_batched_model(root, "res://assets/vegetation/grass_tuft.glb", transforms_by_species["grass"], "BlenderGrassTufts")
	var flowers_built := _add_batched_model(root, "res://assets/vegetation/flower_clump.glb", transforms_by_species["flowers"], "BlenderFlowerClumps")
	var shrubs_built := _add_batched_model(root, "res://assets/vegetation/ornamental_shrub.glb", transforms_by_species["shrubs"], "BlenderOrnamentalShrubs")
	_enhancement_stats["geometric_ground_cover_0217"] = grass_built or flowers_built or shrubs_built
	_enhancement_stats["grass_tufts"] = (transforms_by_species["grass"] as Array).size() if grass_built else 0
	_enhancement_stats["flower_clumps"] = (transforms_by_species["flowers"] as Array).size() if flowers_built else 0
	_enhancement_stats["ornamental_shrubs"] = (transforms_by_species["shrubs"] as Array).size() if shrubs_built else 0
	_enhancement_stats["ground_cover_total"] = int(_enhancement_stats.get("grass_tufts", 0)) + int(_enhancement_stats.get("flower_clumps", 0)) + int(_enhancement_stats.get("ornamental_shrubs", 0))


func _build_street_lamps() -> void:
	var root := Node3D.new()
	root.name = "StreetLamps"
	add_child(root)
	var transforms: Array[Transform3D] = []
	var rejected_road_lamps := 0
	for lamp_variant in data.get("lamps", []):
		var lamp: Dictionary = lamp_variant
		var position_value := _item_position(lamp)
		if not _is_pole_clear_of_road(position_value, 0.45):
			rejected_road_lamps += 1
			continue
		transforms.append(make_transform(position_value, _f(lamp, "rotY"), Vector3.ONE))
		_add_cylinder_collider(position_value + Vector3(0.0, 3.2, 0.0), 0.18, 6.6)
	_add_batched_model(root, "res://assets/props/street_lamp.glb", transforms, "BlenderStreetLamps")
	_enhancement_stats["rejected_road_lamps_0236"] = rejected_road_lamps


func _build_bus_shelters() -> void:
	var root := Node3D.new()
	root.name = "BusShelters"
	add_child(root)
	var transforms: Array[Transform3D] = []
	var rejected_shelters := 0
	var placements: Array[Dictionary] = [
		{"x": 744.2, "z": -383.0, "yaw": PI * 0.5},
		{"x": 744.2, "z": -174.0, "yaw": PI * 0.5},
		{"x": 744.2, "z": 16.0, "yaw": PI * 0.5},
		{"x": 744.2, "z": 204.0, "yaw": PI * 0.5},
		{"x": 775.8, "z": -282.0, "yaw": -PI * 0.5},
		{"x": 775.8, "z": -90.0, "yaw": -PI * 0.5},
		{"x": 775.8, "z": 78.0, "yaw": -PI * 0.5},
		{"x": 775.8, "z": 235.0, "yaw": -PI * 0.5},
		{"x": 914.0, "z": -282.0, "yaw": PI * 0.5},
		{"x": 914.0, "z": -92.0, "yaw": PI * 0.5},
		{"x": 914.0, "z": 92.0, "yaw": PI * 0.5},
		{"x": 914.0, "z": 250.0, "yaw": PI * 0.5},
		{"x": 551.0, "z": -270.0, "yaw": PI * 0.5},
		{"x": 569.0, "z": 30.0, "yaw": -PI * 0.5},
		{"x": 551.0, "z": 300.0, "yaw": PI * 0.5},
		{"x": 640.0, "z": 50.7, "yaw": 0.0},
		{"x": 840.0, "z": 69.3, "yaw": PI},
	]
	for placement in placements:
		var position_value := Vector3(_f(placement, "x"), 0.0, _f(placement, "z"))
		position_value.y = height_at(position_value.x, position_value.z) + 0.02
		var yaw := _f(placement, "yaw")
		# The two former Corniche shelters were centred exactly on
		# cross-street centrelines.  Validate the whole 5.75x2.35 m
		# shelter footprint now, not only its centre point.
		if not _is_footprint_clear_of_roads(position_value, Vector2(5.75, 2.35), yaw, 0.45):
			rejected_shelters += 1
			continue
		transforms.append(make_transform(position_value, yaw, Vector3.ONE))
		_add_box_collider(position_value + Vector3(0.0, 1.53, 0.0), Vector3(5.75, 3.06, 2.35), yaw)
	var built := _add_batched_model(root, "res://assets/props/bus_shelter.glb", transforms, "BlenderBusShelters")
	_enhancement_stats["bus_shelters"] = transforms.size() if built else 0
	_enhancement_stats["rejected_unsafe_bus_shelters_0236"] = rejected_shelters
	_enhancement_stats["bus_shelter_footprints_clear_0236"] = true


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


func _is_boulevard_rect_clear(center: Vector3, size: Vector2, padding: float = 1.0) -> bool:
	var sample_points := [
		center,
		center + Vector3(-size.x * 0.5, 0.0, -size.y * 0.5),
		center + Vector3(size.x * 0.5, 0.0, -size.y * 0.5),
		center + Vector3(-size.x * 0.5, 0.0, size.y * 0.5),
		center + Vector3(size.x * 0.5, 0.0, size.y * 0.5),
	]
	for sample_point in sample_points:
		if not _is_position_clear(sample_point, padding, 2.35):
			return false
	return true


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


## 0.2.19 RichTown Boulevard reference corridor: dark resurfaced asphalt
## with yellow kerb lines, premium stone promenades, granite rules,
## near-continuous lawn/hedge bands, dense date palms, modern lamps and
## stone benches, detailed PR #61 cafes, attached glass arcades and a
## higher Boulevard building frontage from spawn to the X738/Z23 focus.
func _build_premium_boulevard_details(parent: Node) -> void:
	# Native 0.2.18 boulevard rebuild.  The four-lane carriageway stays on
	# X=760, but the photograph at X=738/Z=23 was taken from its western
	# pedestrian field: one repeated slab texture previously continued
	# almost uninterrupted from the buildings to the road.  This pass turns
	# that field into legible urban rooms: granite road edge, royal-palm
	# allée, dark central walking spine, formal lawns/topiary, cafe decks
	# and glass arcades.  The same paving/curb/palm-bed language continues
	# south to the spawn so the result is visible immediately at start.
	var pavers := _create_premium_paving_material(
		"terrain_premium_pavers_shader",
		Color(0.84, 0.80, 0.70),
		0.68,
		0.140,
		0.50
	)
	var spine_pavers := _create_premium_paving_material(
		"boulevard_spine_pavers_shader",
		Color(0.62, 0.60, 0.55),
		0.72,
		0.120,
		0.46
	)
	var promenade_area_m2 := 0.0
	var patch_index := 0
	var continuity_segments: Array[Vector2] = [
		Vector2(-405.0, -318.0),
		Vector2(-292.0, -268.0),
		Vector2(-242.0, -118.0),
		Vector2(68.0, 218.0),
		Vector2(232.0, 405.0),
	]
	for segment in continuity_segments:
		var segment_length := segment.y - segment.x
		var west_continuity := _make_paving_patch_mesh(730.0, 744.0, segment.x, segment.y, 2.0, 0.042)
		var east_continuity := _make_paving_patch_mesh(776.0, 790.0, segment.x, segment.y, 2.0, 0.042)
		if west_continuity != null:
			_mesh_instance(parent, west_continuity, pavers, Transform3D.IDENTITY, "PremiumPromenade_West_%d" % patch_index, false)
			promenade_area_m2 += 14.0 * segment_length
		if east_continuity != null:
			_mesh_instance(parent, east_continuity, pavers, Transform3D.IDENTITY, "PremiumPromenade_East_%d" % patch_index, false)
			promenade_area_m2 += 14.0 * segment_length
		patch_index += 1

	var focus_patches: Array[Dictionary] = [
		{"min_x": 682.0, "max_x": 706.0, "min_z": -100.0, "max_z": 52.0, "lift": 0.038, "dark": false, "name": "PremiumPromenade_PlazaForecourt"},
		{"min_x": 706.0, "max_x": 744.0, "min_z": -100.0, "max_z": 52.0, "lift": 0.044, "dark": false, "name": "PremiumPromenade_FocusWest"},
		{"min_x": 776.0, "max_x": 790.0, "min_z": -100.0, "max_z": 52.0, "lift": 0.044, "dark": false, "name": "PremiumPromenade_FocusEast"},
		{"min_x": 728.0, "max_x": 737.0, "min_z": -100.0, "max_z": 52.0, "lift": 0.058, "dark": true, "name": "PremiumPromenade_WestSpine"},
		{"min_x": 777.5, "max_x": 783.0, "min_z": -100.0, "max_z": 52.0, "lift": 0.058, "dark": true, "name": "PremiumPromenade_EastSpine"},
		{"min_x": 682.0, "max_x": 744.0, "min_z": 17.0, "max_z": 29.0, "lift": 0.072, "dark": true, "name": "PremiumPromenade_ScreenshotAxis"},
	]
	for patch in focus_patches:
		var patch_mesh := _make_paving_patch_mesh(
			_f(patch, "min_x"),
			_f(patch, "max_x"),
			_f(patch, "min_z"),
			_f(patch, "max_z"),
			2.0,
			_f(patch, "lift", 0.044)
		)
		if patch_mesh != null:
			_mesh_instance(parent, patch_mesh, spine_pavers if bool(patch.get("dark", false)) else pavers, Transform3D.IDENTITY, String(patch.get("name", "PremiumPromenade")), false)
			promenade_area_m2 += (_f(patch, "max_x") - _f(patch, "min_x")) * (_f(patch, "max_z") - _f(patch, "min_z"))

	var granite := _material("boulevard_granite", "user_black_granite.jpg", "user_black_granite_normal.jpg", Color(0.66, 0.68, 0.69), 0.34, 0.12, Vector3(0.35, 0.35, 0.35), true)
	granite.normal_scale = 0.52
	granite.metallic_specular = 0.82
	var curb_mesh := BoxMesh.new()
	curb_mesh.size = Vector3.ONE
	var promenade_curb_transforms: Array[Transform3D] = []
	for z in range(-98, 51, 2):
		for curb_x in [706.2, 743.8, 776.2, 788.8]:
			var center_z := float(z) + 1.0
			# Keep the two sidewalk shelter pads and the screenshot-axis
			# pedestrian opening clear of the raised granite edge.
			if (is_equal_approx(curb_x, 743.8) and absf(center_z - 16.0) < 4.0) or (is_equal_approx(curb_x, 776.2) and absf(center_z + 90.0) < 4.0):
				continue
			if is_equal_approx(curb_x, 706.2) and center_z >= 15.0 and center_z <= 31.0:
				continue
			var y := _boulevard_ground_y(curb_x, center_z) + 0.08
			promenade_curb_transforms.append(make_transform(Vector3(curb_x, y, center_z), 0.0, Vector3(0.22, 0.16, 2.05)))
	# Flat black-granite inlays subdivide the remaining stone into formal
	# walking rooms.  They follow terrain in 4 m bites and remain one
	# MultiMesh, so the zoning is readable without hundreds of new nodes.
	for z in range(-98, 50, 4):
		var band_z := float(z) + 2.0
		for band_x in [716.5, 728.2, 736.8, 777.8, 782.8, 788.0]:
			promenade_curb_transforms.append(make_transform(
				Vector3(float(band_x), _boulevard_ground_y(float(band_x), band_z) + 0.082, band_z),
				0.0,
				Vector3(0.34, 0.035, 3.90)
			))
	for band_z in [-88.0, -64.0, -40.0, -16.0, 8.0, 32.0]:
		for x in range(708, 744, 4):
			var west_band_x := float(x) + 2.0
			promenade_curb_transforms.append(make_transform(
				Vector3(west_band_x, _boulevard_ground_y(west_band_x, float(band_z)) + 0.082, float(band_z)),
				0.0,
				Vector3(3.90, 0.035, 0.44)
			))
		for x in range(776, 790, 4):
			var east_band_x := float(x) + 2.0
			promenade_curb_transforms.append(make_transform(
				Vector3(east_band_x, _boulevard_ground_y(east_band_x, float(band_z)) + 0.082, float(band_z)),
				0.0,
				Vector3(3.90, 0.035, 0.44)
			))
	for axis_z in [17.0, 29.0]:
		for x in range(682, 744, 4):
			var axis_x := float(x) + 2.0
			promenade_curb_transforms.append(make_transform(
				Vector3(axis_x, _boulevard_ground_y(axis_x, float(axis_z)) + 0.090, float(axis_z)),
				0.0,
				Vector3(3.90, 0.035, 0.48)
			))

	# 0.2.19: in 0.2.18 the longitudinal granite rules stopped after the
	# focus block, so the spawn screenshots still showed an unstructured
	# cream field.  Continue the same two dark rules through every block,
	# with a transverse rule every 42 m.  All of it remains in the one
	# PremiumGraniteEdging MultiMesh above/below.
	var reference_cross_streets := [-430.0, -300.0, -250.0, -110.0, 60.0, 225.0, 430.0]
	for z in range(-420, 420, 4):
		var reference_z := float(z) + 2.0
		if reference_z >= -104.0 and reference_z <= 56.0:
			continue
		var near_reference_crossing := false
		for cross_z in reference_cross_streets:
			if absf(reference_z - float(cross_z)) < 9.0:
				near_reference_crossing = true
				break
		if near_reference_crossing:
			continue
		for reference_x in [743.8, 776.2, 788.8]:
			var reference_x_value := float(reference_x)
			promenade_curb_transforms.append(make_transform(
				Vector3(reference_x_value, _boulevard_ground_y(reference_x_value, reference_z) + 0.080, reference_z),
				0.0,
				Vector3(0.22, 0.15, 4.05)
			))
	for z in range(-420, 421, 42):
		var transverse_z := float(z)
		if transverse_z >= -104.0 and transverse_z <= 56.0:
			continue
		var near_transverse_crossing := false
		for cross_z in reference_cross_streets:
			if absf(transverse_z - float(cross_z)) < 10.0:
				near_transverse_crossing = true
				break
		if near_transverse_crossing:
			continue
		for transverse_x in [734.0, 738.0, 742.0, 778.0, 782.0, 786.0]:
			var transverse_x_value := float(transverse_x)
			promenade_curb_transforms.append(make_transform(
				Vector3(transverse_x_value, _boulevard_ground_y(transverse_x_value, transverse_z) + 0.082, transverse_z),
				0.0,
				Vector3(3.90, 0.035, 0.44)
			))
	_add_multimesh(parent, curb_mesh, granite, promenade_curb_transforms, "PremiumGraniteEdging", false)

	# East marina quay, Z=140..390.  The height grid falls from the road
	# into marina water immediately east of X=771, so a flat object at
	# local terrain height is buried on its west side and floating on
	# its east side.  Build the intended raised stone promenade deck in
	# road-following segments, finish its water edge with a granite
	# quay wall, and give the deck real box collision.  All east-side
	# 0.2.19 planting/furniture/cafes in this district use
	# `_boulevard_ground_y()` and therefore sit on this deck.
	var marina_deck_transforms: Array[Transform3D] = []
	var marina_quay_transforms: Array[Transform3D] = []
	for deck_z in range(145, 390, 10):
		var deck_center_z := float(deck_z)
		var deck_y := _boulevard_ground_y(780.5, deck_center_z)
		var deck_center := Vector3(780.5, deck_y - 0.175, deck_center_z)
		var deck_size := Vector3(19.0, 0.35, 10.45)
		marina_deck_transforms.append(make_transform(deck_center, 0.0, deck_size))
		_add_box_collider(deck_center, deck_size)
		marina_quay_transforms.append(make_transform(
			Vector3(789.7, deck_y - 2.70, deck_center_z),
			0.0,
			Vector3(0.70, 5.40, 10.45)
		))
	_add_multimesh(parent, curb_mesh, pavers, marina_deck_transforms, "BoulevardMarinaPromenadeDeck", true)
	_add_multimesh(parent, curb_mesh, granite, marina_quay_transforms, "BoulevardMarinaQuayWall", true)
	_enhancement_stats["boulevard_marina_deck_segments"] = marina_deck_transforms.size()

	# Large formal lawn rooms replace the eight small 3.35 m strips from
	# the first boulevard pass.  West rooms occupy both the cafe band and
	# the central spine; palm-side ribbons sit between the exported royal
	# palms; two horizontal lawns frame the screenshot axis at Z=23.
	var lawn := _material("boulevard_lawn", "user_grass.jpg", "user_grass_normal.jpg", Color(0.60, 0.76, 0.43), 0.96, 0.0, Vector3(0.55, 0.55, 0.55), true)
	lawn.normal_scale = 0.82
	var hedge := _material("boulevard_topiary", "foliage.jpg", "foliage_normal.jpg", Color(0.24, 0.47, 0.23), 0.92, 0.0, Vector3(0.85, 0.85, 0.85), true)
	hedge.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mulch := _prop_material("VillaMulch")
	var sphere_hedge_mesh := SphereMesh.new()
	sphere_hedge_mesh.radius = 0.55
	sphere_hedge_mesh.height = 1.12
	sphere_hedge_mesh.radial_segments = 18
	sphere_hedge_mesh.rings = 10
	var cone_hedge_mesh := CylinderMesh.new()
	cone_hedge_mesh.top_radius = 0.08
	cone_hedge_mesh.bottom_radius = 0.58
	cone_hedge_mesh.height = 1.55
	cone_hedge_mesh.radial_segments = 14
	var lawn_mesh := BoxMesh.new()
	lawn_mesh.size = Vector3.ONE
	var planter_mesh := BoxMesh.new()
	planter_mesh.size = Vector3.ONE
	var lawn_transforms: Array[Transform3D] = []
	var planter_transforms: Array[Transform3D] = []
	var mulch_transforms: Array[Transform3D] = []
	var ball_topiary_transforms: Array[Transform3D] = []
	var hedge_block_transforms: Array[Transform3D] = []
	var cone_topiary_transforms: Array[Transform3D] = []
	var boulevard_grass_transforms: Array = []
	var boulevard_flower_transforms: Array = []
	var boulevard_shrub_transforms: Array = []
	var lawn_island_specs: Array[Vector4] = [
		Vector4(716.0, -86.0, 11.0, 14.0),
		Vector4(716.0, -43.0, 11.0, 14.0),
		Vector4(716.0, 0.0, 11.0, 10.0),
		Vector4(716.0, 45.0, 11.0, 9.0),
		Vector4(732.5, -76.0, 7.5, 19.0),
		Vector4(732.5, -52.0, 7.5, 19.0),
		Vector4(732.5, -28.0, 7.5, 19.0),
		Vector4(732.5, -4.0, 7.5, 19.0),
		Vector4(732.5, 20.0, 7.5, 19.0),
		Vector4(732.5, 44.0, 7.5, 19.0),
		Vector4(741.8, -68.5, 4.4, 17.0),
		Vector4(741.8, -47.5, 4.4, 17.0),
		Vector4(741.8, -26.5, 4.4, 17.0),
		Vector4(741.8, -5.5, 4.4, 17.0),
		Vector4(741.8, 36.5, 4.4, 17.0),
		Vector4(780.0, -86.0, 5.4, 18.0),
		Vector4(780.0, -2.0, 5.4, 18.0),
		Vector4(780.0, 39.0, 5.4, 18.0),
		Vector4(706.0, 9.0, 44.0, 4.2),
		Vector4(706.0, 37.0, 44.0, 4.2),
	]
	var cross_street_z := [-430.0, -300.0, -250.0, -110.0, 60.0, 225.0, 430.0]
	# 0.2.19: this was the main visual failure at spawn.  The old 44 m
	# candidate pitch produced a 14 m planter followed by ~30 m of empty
	# stone.  The reference has an almost continuous formal planting
	# band between the palms, so generate a 16.5 m module in every 21 m
	# palm bay.  The remaining ~4.5 m is the white-pebble palm bed and a
	# narrow stone maintenance joint.
	for candidate_z in range(-404, 405, 21):
		var west_z := float(candidate_z)
		var east_z := west_z + 10.0
		var west_blocked := west_z > -110.0 and west_z < 60.0
		var east_blocked := east_z > -110.0 and east_z < 60.0
		for cross_z in cross_street_z:
			if absf(west_z - float(cross_z)) < 17.0:
				west_blocked = true
			if absf(east_z - float(cross_z)) < 17.0:
				east_blocked = true
		# The two new eastern cafe terraces occupy the planting band; the
		# cafe itself becomes the frontage object in those bays.
		if absf(east_z - 150.0) < 14.0 or absf(east_z - 330.0) < 14.0:
			east_blocked = true
		if not west_blocked:
			lawn_island_specs.append(Vector4(742.3, west_z, 5.0, 16.5))
		if not east_blocked and east_z <= 405.0:
			lawn_island_specs.append(Vector4(778.8, east_z, 5.4, 16.5))

	var accepted_lawn_islands := 0
	var accepted_lawn_area_m2 := 0.0
	var continuous_hedge_count := 0
	for island_index in lawn_island_specs.size():
		var island_spec := lawn_island_specs[island_index]
		var island_size := Vector2(island_spec.z, island_spec.w)
		var center := Vector3(island_spec.x, 0.0, island_spec.y)
		center.y = _boulevard_ground_y(center.x, center.z)
		if not _is_boulevard_rect_clear(center, island_size, 0.85):
			continue
		accepted_lawn_islands += 1
		accepted_lawn_area_m2 += island_size.x * island_size.y
		planter_transforms.append(make_transform(center + Vector3(0.0, 0.15, 0.0), 0.0, Vector3(island_size.x, 0.30, island_size.y)))
		lawn_transforms.append(make_transform(center + Vector3(0.0, 0.32, 0.0), 0.0, Vector3(maxf(island_size.x - 0.55, 0.8), 0.10, maxf(island_size.y - 0.55, 0.8))))
		mulch_transforms.append(make_transform(center + Vector3(0.0, 0.385, 0.0), 0.0, Vector3(maxf(island_size.x * 0.42, 0.7), 0.045, maxf(island_size.y * 0.72, 0.7))))
		_add_box_collider(center + Vector3(0.0, 0.18, 0.0), Vector3(island_size.x, 0.36, island_size.y))

		# The defining green element in the reference is not an isolated
		# sphere: it is a clipped hedge running along the road edge of
		# every planting bay.  Keep it in the same hedge MultiMesh so the
		# visual continuity does not cost another draw-call family.
		if island_size.y >= 14.0 and island_size.x <= 8.0:
			var road_side_sign := 1.0 if center.x < 760.0 else -1.0
			var continuous_hedge_x := center.x + road_side_sign * (island_size.x * 0.5 - 0.78)
			hedge_block_transforms.append(make_transform(
				Vector3(continuous_hedge_x, center.y + 0.76, center.z),
				0.0,
				Vector3(1.12, 0.82, island_size.y - 1.1)
			))
			continuous_hedge_count += 1

		var corner_x := maxf(island_size.x * 0.5 - 1.05, 0.35)
		var corner_z := maxf(island_size.y * 0.5 - 1.05, 0.35)
		var ball_index := 0
		for corner_sign_x in [-1.0, 1.0]:
			for corner_sign_z in [-1.0, 1.0]:
				var ball_scale := 0.78 + _hash01(island_index * 31 + ball_index * 7, island_index * 17 + ball_index * 3) * 0.38
				ball_topiary_transforms.append(make_transform(
					center + Vector3(float(corner_sign_x) * corner_x, 0.37 + 0.55 * ball_scale, float(corner_sign_z) * corner_z),
					_hash01(island_index * 13 + ball_index, island_index * 29 + ball_index) * TAU,
					Vector3.ONE * ball_scale
				))
				ball_index += 1
		var long_axis_is_x := island_size.x >= island_size.y
		match island_index % 3:
			0:
				cone_topiary_transforms.append(make_transform(center + Vector3(0.0, 1.16, 0.0), 0.0, Vector3.ONE))
			1:
				var hedge_size := Vector3(island_size.x * 0.56, 0.78, minf(island_size.y * 0.44, 1.45)) if long_axis_is_x else Vector3(minf(island_size.x * 0.44, 1.65), 0.78, island_size.y * 0.54)
				hedge_block_transforms.append(make_transform(center + Vector3(0.0, 0.78, 0.0), 0.0, hedge_size))
			_:
				for hedge_sign in [-1.0, 1.0]:
					var hedge_offset := Vector3(float(hedge_sign) * island_size.x * 0.23, 0.74, 0.0) if long_axis_is_x else Vector3(0.0, 0.74, float(hedge_sign) * island_size.y * 0.23)
					var split_hedge_size := Vector3(island_size.x * 0.30, 0.70, minf(island_size.y * 0.42, 1.35)) if long_axis_is_x else Vector3(minf(island_size.x * 0.42, 1.55), 0.70, island_size.y * 0.29)
					hedge_block_transforms.append(make_transform(center + hedge_offset, 0.0, split_hedge_size))

		var grass_count := clampi(int(round(island_size.x * island_size.y / 13.0)), 5, 12)
		for grass_index in grass_count:
			var grass_seed := island_index * 101 + grass_index * 17
			var grass_local := Vector3(
				(_hash01(grass_seed * 3 + 11, grass_seed * 5 + 71) - 0.5) * maxf(island_size.x - 1.5, 0.6),
				0.375,
				(_hash01(grass_seed * 7 + 31, grass_seed * 11 + 97) - 0.5) * maxf(island_size.y - 1.5, 0.6)
			)
			var grass_scale := 0.82 + _hash01(grass_seed * 13 + 17, grass_seed * 19 + 43) * 0.58
			boulevard_grass_transforms.append(make_transform(center + grass_local, _hash01(grass_seed * 29 + 3, grass_seed * 31 + 13) * TAU, Vector3(grass_scale, grass_scale * 0.94, grass_scale)))
		var flower_count := 3 if island_size.x * island_size.y > 70.0 else 2
		for flower_index in flower_count:
			var flower_seed := island_index * 211 + flower_index * 37
			var flower_local := Vector3(
				(_hash01(flower_seed * 3 + 19, flower_seed * 7 + 83) - 0.5) * maxf(island_size.x - 1.8, 0.6),
				0.385,
				(_hash01(flower_seed * 11 + 23, flower_seed * 13 + 59) - 0.5) * maxf(island_size.y - 1.8, 0.6)
			)
			var flower_scale := 0.80 + _hash01(flower_seed * 17 + 5, flower_seed * 23 + 41) * 0.42
			boulevard_flower_transforms.append(make_transform(center + flower_local, _hash01(flower_seed * 29 + 7, flower_seed * 31 + 17) * TAU, Vector3.ONE * flower_scale))
		for shrub_sign in [-1.0, 1.0]:
			var shrub_local := Vector3(float(shrub_sign) * island_size.x * 0.24, 0.41, 0.0) if long_axis_is_x else Vector3(0.0, 0.41, float(shrub_sign) * island_size.y * 0.24)
			var shrub_scale := 0.84 + _hash01(island_index * 43 + int(shrub_sign) * 7, island_index * 53 + 19) * 0.30
			boulevard_shrub_transforms.append(make_transform(center + shrub_local, _hash01(island_index * 61 + int(shrub_sign) * 3, island_index * 71 + 23) * TAU, Vector3.ONE * shrub_scale))
	_add_multimesh(parent, planter_mesh, granite, planter_transforms, "BoulevardRaisedPlanters", false)
	_add_multimesh(parent, lawn_mesh, lawn, lawn_transforms, "BoulevardLawnIslands", false)
	_add_multimesh(parent, lawn_mesh, mulch, mulch_transforms, "BoulevardPlantingMulch", false)
	_add_multimesh(parent, sphere_hedge_mesh, hedge, ball_topiary_transforms, "BoulevardRoundTopiary", false)
	_add_multimesh(parent, lawn_mesh, hedge, hedge_block_transforms, "BoulevardClippedHedges", false)
	_add_multimesh(parent, cone_hedge_mesh, hedge, cone_topiary_transforms, "BoulevardConeTopiary", false)

	# The dense date-palm rows already run on both sides of the avenue.
	# Extend their circular white-pebble beds, granite rings and visible
	# drip loops over the whole boulevard, with loose pebble geometry and
	# individual emitters in the screenshot and spawn districts.  Seven
	# additional date palms frame the western plaza edge/screenshot axis.
	var pebble_material := _material("boulevard_white_pebbles", "user_sand_beach_white.jpg", "user_sand_rippled_normal.jpg", Color(0.98, 0.97, 0.93), 0.94, 0.0, Vector3(1.65, 1.65, 1.65), true)
	pebble_material.normal_scale = 0.72
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
	var loose_pebble_mesh := SphereMesh.new()
	loose_pebble_mesh.radius = 0.5
	loose_pebble_mesh.height = 1.0
	loose_pebble_mesh.radial_segments = 8
	loose_pebble_mesh.rings = 4
	var emitter_mesh := BoxMesh.new()
	emitter_mesh.size = Vector3.ONE
	var palm_bed_centers: Array[Vector3] = []
	for palm_variant in data.get("palms", []):
		var palm: Dictionary = palm_variant
		var palm_x := _f(palm, "x")
		var palm_z := _f(palm, "z")
		if palm_z < -430.0 or palm_z > 430.0 or minf(absf(palm_x - 745.5), absf(palm_x - 774.5)) > 1.0:
			continue
		var palm_bed_center := Vector3(palm_x, _boulevard_ground_y(palm_x, palm_z), palm_z)
		if _road_clearance_xz(palm_bed_center) < 0.65:
			continue
		palm_bed_centers.append(palm_bed_center)

	var extra_date_palm_transforms: Array = []
	var extra_palm_specs: Array[Vector2] = [
		Vector2(704.5, -82.0),
		Vector2(704.5, -40.0),
		Vector2(704.5, 44.0),
		Vector2(690.0, 13.0),
		Vector2(690.0, 33.0),
		Vector2(705.0, 13.0),
		Vector2(705.0, 33.0),
	]
	for extra_index in extra_palm_specs.size():
		var extra_spec := extra_palm_specs[extra_index]
		var extra_base := Vector3(extra_spec.x, _boulevard_ground_y(extra_spec.x, extra_spec.y) - 0.03, extra_spec.y)
		if not _is_position_clear(extra_base, 2.0, 3.0):
			continue
		_foliage_points.append(extra_base)
		palm_bed_centers.append(Vector3(extra_spec.x, _boulevard_ground_y(extra_spec.x, extra_spec.y), extra_spec.y))
		extra_date_palm_transforms.append(make_transform(
			extra_base,
			_hash01(extra_index * 37 + 91, extra_index * 41 + 17) * TAU,
			Vector3(0.86, 0.84, 0.86)
		))
		_add_cylinder_collider(extra_base + Vector3(0.0, 3.2, 0.0), 0.34, 6.4)
	var extra_palms_built := _add_batched_model(parent, "res://assets/vegetation/palm_date.glb", extra_date_palm_transforms, "BoulevardExtraDatePalms")
	if extra_palms_built:
		_enhancement_stats["date_palms"] = int(_enhancement_stats.get("date_palms", 0)) + extra_date_palm_transforms.size()
		_enhancement_stats["boulevard_date_palms"] = int(_enhancement_stats.get("boulevard_date_palms", 0)) + extra_date_palm_transforms.size()
		_enhancement_stats["detailed_palms"] = int(_enhancement_stats.get("detailed_palms", 0)) + extra_date_palm_transforms.size()

	var pebble_transforms: Array[Transform3D] = []
	var ring_transforms: Array[Transform3D] = []
	var drip_transforms: Array[Transform3D] = []
	var loose_pebble_transforms: Array[Transform3D] = []
	var drip_emitter_transforms: Array[Transform3D] = []
	for bed_index in palm_bed_centers.size():
		var bed_center := palm_bed_centers[bed_index]
		pebble_transforms.append(make_transform(bed_center + Vector3(0.0, 0.07, 0.0), 0.0, Vector3(1.58, 1.0, 1.58)))
		ring_transforms.append(make_transform(bed_center + Vector3(0.0, 0.14, 0.0), 0.0, Vector3(1.58, 1.0, 1.58)))
		drip_transforms.append(make_transform(bed_center + Vector3(0.0, 0.12, 0.0), 0.0, Vector3(1.10, 1.0, 1.10)))
		var detailed_bed := (bed_center.z >= -110.0 and bed_center.z <= 60.0) or (bed_center.z >= 250.0 and bed_center.z <= 395.0)
		if not detailed_bed:
			continue
		for emitter_index in 4:
			var emitter_angle := TAU * float(emitter_index) / 4.0 + 0.39
			drip_emitter_transforms.append(make_transform(
				bed_center + Vector3(cos(emitter_angle) * 0.61, 0.145, sin(emitter_angle) * 0.61),
				emitter_angle,
				Vector3(0.10, 0.07, 0.10)
			))
		for stone_index in 7:
			var stone_seed := bed_index * 71 + stone_index * 13
			var stone_angle := _hash01(stone_seed * 3 + 7, stone_seed * 5 + 29) * TAU
			var stone_radius := 0.35 + _hash01(stone_seed * 7 + 13, stone_seed * 11 + 43) * 0.92
			var stone_width := 0.14 + _hash01(stone_seed * 17 + 19, stone_seed * 19 + 53) * 0.13
			loose_pebble_transforms.append(make_transform(
				bed_center + Vector3(cos(stone_angle) * stone_radius, 0.125, sin(stone_angle) * stone_radius),
				stone_angle,
				Vector3(stone_width, 0.065, stone_width * 0.78)
			))
		# Low ornamental tufts break the perfect white discs and link
		# each trunk bed visually into the continuous planting band.
		for planting_index in 3:
			var planting_angle := TAU * float(planting_index) / 3.0 + float(bed_index % 5) * 0.23
			boulevard_grass_transforms.append(make_transform(
				bed_center + Vector3(cos(planting_angle) * 1.18, 0.145, sin(planting_angle) * 1.18),
				planting_angle,
				Vector3.ONE * 0.72
			))
		if bed_index % 2 == 0:
			var flower_angle := 0.71 + float(bed_index % 7) * 0.19
			boulevard_flower_transforms.append(make_transform(
				bed_center + Vector3(cos(flower_angle) * 1.22, 0.145, sin(flower_angle) * 1.22),
				flower_angle,
				Vector3.ONE * 0.68
			))
	_add_multimesh(parent, pebble_disk, pebble_material, pebble_transforms, "WashingtoniaWhiteGravelBeds", false)
	_add_multimesh(parent, ring_mesh, granite, ring_transforms, "WashingtoniaGraniteRings", false)
	_add_multimesh(parent, drip_ring_mesh, irrigation_material, drip_transforms, "WashingtoniaDripIrrigation", false)
	_add_multimesh(parent, emitter_mesh, irrigation_material, drip_emitter_transforms, "BoulevardDripEmitters", false)
	_add_multimesh(parent, loose_pebble_mesh, pebble_material, loose_pebble_transforms, "BoulevardLooseWhitePebbles", false)

	# Reference street furniture.  The exported heroic lamps are useful
	# landmarks but are far too sparse to establish the avenue rhythm in
	# the photograph.  Add a slim contemporary L-arm lamp in every palm
	# bay and a long stone bench in every second bay.  Four MultiMesh
	# families cover the whole 860 m corridor; no per-lamp nodes.
	var furniture_metal := _material("boulevard_modern_lamp_metal", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.22, 0.27, 0.29), 0.32, 0.72)
	var furniture_head := _material("boulevard_modern_lamp_head", "", "", Color(1.0, 0.74, 0.40), 0.30, 0.05)
	furniture_head.emission_enabled = true
	furniture_head.emission = Color(0.36, 0.17, 0.045)
	_register_night_material(furniture_head, 0.04, 0.72, 2.15)
	var lamp_pole_mesh := CylinderMesh.new()
	lamp_pole_mesh.top_radius = 0.055
	lamp_pole_mesh.bottom_radius = 0.075
	lamp_pole_mesh.height = 5.6
	lamp_pole_mesh.radial_segments = 10
	var furniture_box_mesh := BoxMesh.new()
	furniture_box_mesh.size = Vector3.ONE
	var modern_lamp_poles: Array[Transform3D] = []
	var modern_lamp_arms: Array[Transform3D] = []
	var modern_lamp_heads: Array[Transform3D] = []
	var stone_bench_transforms: Array[Transform3D] = []
	var modern_lamp_count := 0
	var stone_bench_count := 0
	for furniture_z in range(-404, 405, 21):
		var west_furniture_z := float(furniture_z)
		var east_furniture_z := west_furniture_z + 10.0
		for side_index in 2:
			var is_west_side := side_index == 0
			var side_z := west_furniture_z if is_west_side else east_furniture_z
			if side_z > 405.0:
				continue
			var near_furniture_crossing := false
			for cross_z in reference_cross_streets:
				if absf(side_z - float(cross_z)) < 8.0:
					near_furniture_crossing = true
					break
			if near_furniture_crossing:
				continue
			var lamp_x := 746.9 if is_west_side else 773.1
			var road_direction := 1.0 if is_west_side else -1.0
			var lamp_base := Vector3(lamp_x, _boulevard_ground_y(lamp_x, side_z), side_z)
			modern_lamp_poles.append(make_transform(lamp_base + Vector3(0.0, 2.80, 0.0), 0.0, Vector3.ONE))
			modern_lamp_arms.append(make_transform(
				lamp_base + Vector3(road_direction * 0.78, 5.62, 0.0),
				0.0,
				Vector3(1.62, 0.09, 0.10)
			))
			modern_lamp_heads.append(make_transform(
				lamp_base + Vector3(road_direction * 1.55, 5.54, 0.0),
				0.0,
				Vector3(0.72, 0.09, 0.24)
			))
			_add_cylinder_collider(lamp_base + Vector3(0.0, 2.80, 0.0), 0.13, 5.6)
			modern_lamp_count += 1

			var bench_clear_of_cafe := true
			if not is_west_side:
				for cafe_frontage_z in [-58.0, 18.0, 150.0, 330.0]:
					if absf(side_z - float(cafe_frontage_z)) < 7.0:
						bench_clear_of_cafe = false
						break
			if bench_clear_of_cafe and int((furniture_z + 404) / 21) % 2 == 0:
				# Benches sit on the stone side of the planting band and
				# look across the hedge/palms to the carriageway.
				var bench_x := 739.0 if is_west_side else 783.0
				var bench_center := Vector3(bench_x, _boulevard_ground_y(bench_x, side_z), side_z)
				stone_bench_transforms.append(make_transform(
					bench_center + Vector3(0.0, 0.38, 0.0),
					0.0,
					Vector3(0.62, 0.16, 2.55)
				))
				for bench_leg_sign in [-1.0, 1.0]:
					stone_bench_transforms.append(make_transform(
						bench_center + Vector3(0.0, 0.16, float(bench_leg_sign) * 0.95),
						0.0,
						Vector3(0.48, 0.32, 0.24)
					))
				_add_box_collider(bench_center + Vector3(0.0, 0.30, 0.0), Vector3(0.68, 0.60, 2.60))
				stone_bench_count += 1
	_add_multimesh(parent, lamp_pole_mesh, furniture_metal, modern_lamp_poles, "BoulevardStreetLampPoles", true, -1.0, 240.0, 180.0)
	_add_multimesh(parent, furniture_box_mesh, furniture_metal, modern_lamp_arms, "BoulevardStreetLampArms", true, -1.0, 240.0, 180.0)
	_add_multimesh(parent, furniture_box_mesh, furniture_head, modern_lamp_heads, "BoulevardStreetLampHeads", false, -1.0, 240.0, 180.0)
	_add_multimesh(parent, furniture_box_mesh, pavers, stone_bench_transforms, "BoulevardStoneBenches", true, -1.0, 220.0, 180.0)

	# The flat blue rectangles in the rejection screenshots are private
	# villa pools whose water slab reaches almost exactly to the public
	# promenade.  Finish every Boulevard-adjacent pool as a private yard:
	# stone deck, raised granite coping and a clipped hedge screen on the
	# public side.  This keeps the real pools, but removes the raw
	# editor-plane read from the drive-by view.
	var pool_deck_transforms: Array[Transform3D] = []
	var pool_coping_transforms: Array[Transform3D] = []
	var pool_screen_transforms: Array[Transform3D] = []
	var boulevard_pool_deck_count := 0
	for pool_variant in data.get("pools", []):
		var pool: Dictionary = pool_variant
		var pool_x := _f(pool, "x")
		var pool_z := _f(pool, "z")
		var west_pool := pool_x >= 720.0 and pool_x <= 744.0
		var east_pool := pool_x >= 776.0 and pool_x <= 800.0
		if pool_z < -430.0 or pool_z > 430.0 or not (west_pool or east_pool):
			continue
		var pool_center := _item_position(pool)
		var pool_w := maxf(_f(pool, "w", 10.0), 4.0)
		var pool_d := maxf(_f(pool, "d", 6.0), 3.0)
		pool_deck_transforms.append(make_transform(
			pool_center + Vector3(0.0, 0.10, 0.0),
			0.0,
			Vector3(pool_w + 2.6, 0.16, pool_d + 2.6)
		))
		for coping_sign in [-1.0, 1.0]:
			pool_coping_transforms.append(make_transform(
				pool_center + Vector3(0.0, 0.22, float(coping_sign) * (pool_d * 0.5 + 0.28)),
				0.0,
				Vector3(pool_w + 0.8, 0.12, 0.38)
			))
			pool_coping_transforms.append(make_transform(
				pool_center + Vector3(float(coping_sign) * (pool_w * 0.5 + 0.28), 0.22, 0.0),
				0.0,
				Vector3(0.38, 0.12, pool_d + 0.8)
			))
		var pool_screen_x := pool_center.x + (pool_w * 0.5 + 1.55 if west_pool else -(pool_w * 0.5 + 1.55))
		pool_screen_transforms.append(make_transform(
			Vector3(pool_screen_x, pool_center.y + 0.55, pool_center.z),
			0.0,
			Vector3(0.85, 0.78, pool_d + 2.4)
		))
		for lounger_sign in [-1.0, 1.0]:
			var lounger_x := pool_center.x + (-(pool_w * 0.5 - 0.95) if west_pool else pool_w * 0.5 - 0.95)
			pool_deck_transforms.append(make_transform(
				Vector3(lounger_x, pool_center.y + 0.25, pool_center.z + float(lounger_sign) * minf(pool_d * 0.24, 1.25)),
				0.0,
				Vector3(0.58, 0.13, 1.65)
			))
		boulevard_pool_deck_count += 1
	_add_multimesh(parent, furniture_box_mesh, pavers, pool_deck_transforms, "BoulevardPoolDecks", false)
	_add_multimesh(parent, furniture_box_mesh, granite, pool_coping_transforms, "BoulevardPoolCoping", false)
	_add_multimesh(parent, furniture_box_mesh, hedge, pool_screen_transforms, "BoulevardPoolHedgeScreens", false)

	# Nine placements of the second agent's detailed PR #61 cafe GLB:
	# five west-facing terraces and four rotated east-facing terraces,
	# including one pair at the X760/Z330 spawn.  The 2.86 MB PBR model
	# supplies its interior, counters, glass, mashrabiya screens,
	# planters, terrace tables and linen umbrellas; the procedural
	# batches below dress the attached building arcades.
	var glass: Material = _prop_material("FacadeGlass")
	var canopy_material := _material("boulevard_cafe_canopy", "user_wood_slats_dark.jpg", "user_wood_slats_dark_normal.jpg", Color(0.78, 0.68, 0.56), 0.72, 0.02, Vector3(0.35, 0.35, 0.35), true)
	canopy_material.normal_scale = 0.82
	var counter_material := _material("boulevard_cafe_counter", "user_black_granite.jpg", "user_black_granite_normal.jpg", Color(0.39, 0.43, 0.44), 0.34, 0.20, Vector3(0.35, 0.35, 0.35), true)
	var warm_sign := _material("boulevard_cafe_sign", "", "", Color(0.95, 0.53, 0.16), 0.34, 0.05)
	warm_sign.emission_enabled = true
	warm_sign.emission = Color(0.42, 0.12, 0.025)
	var table_material := _material("boulevard_cafe_table", "user_stone_tiles_beige.jpg", "", Color(0.86, 0.82, 0.73), 0.48, 0.03)
	var chair_material := _material("boulevard_cafe_chair", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.24, 0.30, 0.32), 0.36, 0.54)
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
	var cafe_specs: Array[Dictionary] = [
		{"x": 718.0, "z": -67.0, "facing": 1.0},
		{"x": 718.0, "z": -20.0, "facing": 1.0},
		{"x": 718.0, "z": 27.0, "facing": 1.0},
		{"x": 782.0, "z": -58.0, "facing": -1.0},
		{"x": 782.0, "z": 18.0, "facing": -1.0},
		{"x": 718.0, "z": 330.0, "facing": 1.0},
		{"x": 782.0, "z": 330.0, "facing": -1.0},
		{"x": 718.0, "z": -132.0, "facing": 1.0},
		{"x": 782.0, "z": 150.0, "facing": -1.0},
	]
	var cafe_transforms: Array[Transform3D] = []
	var accepted_cafes := 0
	var accepted_spawn_cafes := 0
	for cafe_spec in cafe_specs:
		var facing := _f(cafe_spec, "facing", 1.0)
		var base := Vector3(_f(cafe_spec, "x"), 0.0, _f(cafe_spec, "z"))
		base.y = _boulevard_ground_y(base.x, base.z)
		# The reusable GLB is 11.42 x 9.02 m in plan.  Check the whole
		# footprint, not only its centre, against exported/infill buildings.
		if not _is_boulevard_rect_clear(base, Vector2(11.6, 9.2), 0.55):
			continue
		accepted_cafes += 1
		if absf(base.z - 330.0) < 1.0:
			accepted_spawn_cafes += 1
		var cafe_yaw := 0.0
		if facing < 0.0:
			cafe_yaw = PI
		var cafe_position := base + Vector3(0.0, 0.055, 0.0)
		cafe_transforms.append(make_transform(cafe_position, cafe_yaw))
		# Interior shell collider; the GLB terrace furniture stays decorative.
		_add_box_collider(
			cafe_position + Vector3(-facing * 2.1, 1.9, 0.0),
			Vector3(6.55, 3.6, 7.6)
		)
	var cafe_model_path := "res://assets/props/dubai_premium_cafe.glb"
	var cafe_model_parts := _get_model_parts(cafe_model_path)
	var cafe_model_triangles := 0
	for cafe_part_variant in cafe_model_parts:
		var cafe_part: Dictionary = cafe_part_variant
		cafe_model_triangles += _mesh_triangle_count(cafe_part.get("mesh") as Mesh)
	var cafes_built := _add_batched_model(
		parent,
		cafe_model_path,
		cafe_transforms,
		"DubaiPremiumCafes"
	)
	if not cafes_built:
		accepted_cafes = 0
		accepted_spawn_cafes = 0

	# Attached storefront arcades for exported buildings that actually
	# front RichTown Boulevard.  Their glass line, columns, canopy and
	# planters sit in the promenade rather than being a flat facade decal.
	var arcade_specs: Array[Dictionary] = [
		{"front_x": 786.0, "z": -26.0, "length": 24.0, "facing": -1.0, "tables": true},
		{"front_x": 729.3, "z": 102.0, "length": 24.0, "facing": 1.0, "tables": true},
		{"front_x": 728.1, "z": 186.0, "length": 24.0, "facing": 1.0, "tables": true},
		{"front_x": 728.7, "z": -156.0, "length": 24.0, "facing": 1.0, "tables": false},
		{"front_x": 787.0, "z": -206.0, "length": 24.0, "facing": -1.0, "tables": false},
		# 0.2.19 frontage extensions use faces that are clear in the
		# exported city: hotel/generic blocks north of the focus and two
		# promenade galleries near spawn.  Villa lots with pools are
		# deliberately not dressed as shopfronts.
		{"front_x": 726.0, "z": -274.0, "length": 18.0, "facing": 1.0, "tables": true},
		{"front_x": 725.8, "z": -205.0, "length": 28.0, "facing": 1.0, "tables": true},
		{"front_x": 791.0, "z": -274.0, "length": 18.0, "facing": -1.0, "tables": true},
		{"front_x": 788.7, "z": -156.0, "length": 28.0, "facing": -1.0, "tables": true},
		{"front_x": 788.0, "z": 286.0, "length": 28.0, "facing": -1.0, "tables": true},
		{"front_x": 788.0, "z": 374.0, "length": 28.0, "facing": -1.0, "tables": false},
	]
	var accepted_arcades := 0
	for arcade_index in arcade_specs.size():
		var arcade := arcade_specs[arcade_index]
		var front_x := _f(arcade, "front_x")
		var arcade_z := _f(arcade, "z")
		var arcade_length := _f(arcade, "length", 24.0)
		var arcade_facing := _f(arcade, "facing", 1.0)
		var arcade_base := Vector3(front_x, _boulevard_ground_y(front_x, arcade_z), arcade_z)
		var column_probe := arcade_base + Vector3(arcade_facing * 2.8, 0.0, 0.0)
		if not _is_position_clear(column_probe, 0.55, 2.4):
			continue
		accepted_arcades += 1
		var panel_count := maxi(4, int(round(arcade_length / 4.0)))
		var panel_width := arcade_length / float(panel_count)
		for panel_index in panel_count:
			var panel_z := arcade_z - arcade_length * 0.5 + panel_width * (float(panel_index) + 0.5)
			glass_wall_transforms.append(make_transform(Vector3(front_x + arcade_facing * 0.08, arcade_base.y + 1.66, panel_z), 0.0, Vector3(0.09, 3.12, panel_width - 0.18)))
		for boundary_index in range(panel_count + 1):
			var boundary_z := arcade_z - arcade_length * 0.5 + panel_width * float(boundary_index)
			frame_transforms.append(make_transform(Vector3(front_x + arcade_facing * 0.16, arcade_base.y + 1.66, boundary_z), 0.0, Vector3(0.14, 3.28, 0.14)))
			frame_transforms.append(make_transform(Vector3(front_x + arcade_facing * 2.82, arcade_base.y + 1.82, boundary_z), 0.0, Vector3(0.22, 3.64, 0.22)))
		frame_transforms.append(make_transform(Vector3(front_x + arcade_facing * 0.16, arcade_base.y + 3.28, arcade_z), 0.0, Vector3(0.15, 0.15, arcade_length + 0.15)))
		frame_transforms.append(make_transform(Vector3(front_x + arcade_facing * 0.16, arcade_base.y + 0.12, arcade_z), 0.0, Vector3(0.15, 0.20, arcade_length + 0.15)))
		# One-metre shopfront mullions and two horizontal rails keep the
		# glass from reading as one uninterrupted transparent sheet.
		for mullion_offset in range(int(-arcade_length * 0.5) + 1, int(arcade_length * 0.5)):
			frame_transforms.append(make_transform(
				Vector3(front_x + arcade_facing * 0.19, arcade_base.y + 1.66, arcade_z + float(mullion_offset)),
				0.0,
				Vector3(0.07, 3.08, 0.07)
			))
		for rail_y in [1.05, 2.18]:
			frame_transforms.append(make_transform(
				Vector3(front_x + arcade_facing * 0.19, arcade_base.y + float(rail_y), arcade_z),
				0.0,
				Vector3(0.09, 0.09, arcade_length)
			))
		for pier_sign in [-1.0, 1.0]:
			counter_transforms.append(make_transform(
				Vector3(front_x + arcade_facing * 0.28, arcade_base.y + 1.86, arcade_z + float(pier_sign) * arcade_length * 0.5),
				0.0,
				Vector3(0.52, 3.72, 0.52)
			))
		sign_transforms.append(make_transform(
			Vector3(front_x + arcade_facing * 2.98, arcade_base.y + 3.62, arcade_z),
			0.0,
			Vector3(0.08, 0.08, arcade_length * 0.92)
		))
		canopy_transforms.append(make_transform(Vector3(front_x + arcade_facing * 1.48, arcade_base.y + 3.78, arcade_z), 0.0, Vector3(3.25, 0.18, arcade_length + 1.0)))
		for slat_index in range(int(round(arcade_length / 2.0)) + 1):
			var slat_z := arcade_z - arcade_length * 0.5 + float(slat_index) * 2.0
			canopy_transforms.append(make_transform(Vector3(front_x + arcade_facing * 1.48, arcade_base.y + 3.93, slat_z), 0.0, Vector3(3.65, 0.07, 0.22)))
		sign_transforms.append(make_transform(Vector3(front_x + arcade_facing * 0.22, arcade_base.y + 3.02, arcade_z), 0.0, Vector3(0.12, 0.50, arcade_length * 0.58)))
		for planter_index in panel_count:
			var arcade_planter_z := arcade_z - arcade_length * 0.5 + panel_width * (float(planter_index) + 0.5)
			var arcade_planter_center := Vector3(front_x + arcade_facing * 3.35, _boulevard_ground_y(front_x + arcade_facing * 3.35, arcade_planter_z) + 0.24, arcade_planter_z)
			counter_transforms.append(make_transform(arcade_planter_center, 0.0, Vector3(0.65, 0.46, 2.45)))
			boulevard_shrub_transforms.append(make_transform(arcade_planter_center + Vector3(0.0, 0.25, 0.0), float(arcade_index * 3 + planter_index) * 0.63, Vector3.ONE * 0.84))
		if bool(arcade.get("tables", false)):
			var table_offsets := [-10.0, -6.0, -2.0, 2.0, 6.0, 10.0] if arcade_length >= 24.0 else [-6.0, -2.0, 2.0, 6.0]
			for table_offset_z in table_offsets:
				var arcade_table_center := Vector3(front_x + arcade_facing * 1.55, 0.0, arcade_z + float(table_offset_z))
				arcade_table_center.y = _boulevard_ground_y(arcade_table_center.x, arcade_table_center.z)
				table_top_transforms.append(make_transform(arcade_table_center + Vector3(0.0, 0.82, 0.0), 0.0, Vector3(1.38, 0.10, 1.38)))
				table_leg_transforms.append(make_transform(arcade_table_center + Vector3(0.0, 0.43, 0.0), 0.0, Vector3(0.35, 0.76, 0.35)))
				for arcade_chair_index in 3:
					var arcade_chair_angle := TAU * float(arcade_chair_index) / 3.0 + float(arcade_index) * 0.43
					var arcade_outward := Vector3(cos(arcade_chair_angle), 0.0, sin(arcade_chair_angle))
					var arcade_chair_center := arcade_table_center + arcade_outward * 1.16
					var arcade_chair_yaw := atan2(-arcade_outward.x, -arcade_outward.z)
					chair_seat_transforms.append(make_transform(arcade_chair_center + Vector3(0.0, 0.48, 0.0), arcade_chair_yaw, Vector3(0.48, 0.10, 0.48)))
					chair_back_transforms.append(make_transform(arcade_chair_center + arcade_outward * 0.20 + Vector3(0.0, 0.77, 0.0), arcade_chair_yaw, Vector3(0.48, 0.55, 0.09)))
					chair_leg_transforms.append(make_transform(arcade_chair_center + Vector3(0.0, 0.24, 0.0), arcade_chair_yaw, Vector3(0.45, 0.58, 0.45)))

	var boulevard_grass_built := _add_batched_model(parent, "res://assets/vegetation/grass_tuft.glb", boulevard_grass_transforms, "BoulevardGrassTufts")
	var boulevard_flowers_built := _add_batched_model(parent, "res://assets/vegetation/flower_clump.glb", boulevard_flower_transforms, "BoulevardFlowerClumps")
	var boulevard_shrubs_built := _add_batched_model(parent, "res://assets/vegetation/ornamental_shrub.glb", boulevard_shrub_transforms, "BoulevardOrnamentalShrubs")
	var boulevard_ground_cover_count := 0
	if boulevard_grass_built:
		boulevard_ground_cover_count += boulevard_grass_transforms.size()
		_enhancement_stats["grass_tufts"] = int(_enhancement_stats.get("grass_tufts", 0)) + boulevard_grass_transforms.size()
	if boulevard_flowers_built:
		boulevard_ground_cover_count += boulevard_flower_transforms.size()
		_enhancement_stats["flower_clumps"] = int(_enhancement_stats.get("flower_clumps", 0)) + boulevard_flower_transforms.size()
	if boulevard_shrubs_built:
		boulevard_ground_cover_count += boulevard_shrub_transforms.size()
		_enhancement_stats["ornamental_shrubs"] = int(_enhancement_stats.get("ornamental_shrubs", 0)) + boulevard_shrub_transforms.size()
	_enhancement_stats["ground_cover_total"] = int(_enhancement_stats.get("grass_tufts", 0)) + int(_enhancement_stats.get("flower_clumps", 0)) + int(_enhancement_stats.get("ornamental_shrubs", 0))

	var unit_box := BoxMesh.new()
	unit_box.size = Vector3.ONE
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
	_enhancement_stats["boulevard_cafes"] = accepted_cafes
	_enhancement_stats["boulevard_spawn_cafes"] = accepted_spawn_cafes
	_enhancement_stats["boulevard_arcades"] = accepted_arcades
	# Each GLB cafe contains three terrace tables and three parasols;
	# table_top_transforms now contains only the attached-arcade tables.
	_enhancement_stats["boulevard_cafe_tables"] = table_top_transforms.size() + accepted_cafes * 3
	_enhancement_stats["boulevard_cafe_umbrellas"] = accepted_cafes * 3
	_enhancement_stats["dubai_premium_cafe_model"] = cafes_built
	_enhancement_stats["dubai_premium_cafe_model_parts"] = cafe_model_parts.size()
	_enhancement_stats["dubai_premium_cafe_triangles"] = cafe_model_triangles
	_enhancement_stats["dubai_premium_cafe_pbr_0219"] = cafes_built and cafe_model_parts.size() >= 12 and cafe_model_triangles >= 10000
	_enhancement_stats["boulevard_palm_planters"] = pebble_transforms.size()
	_enhancement_stats["boulevard_drip_emitters"] = drip_emitter_transforms.size()
	_enhancement_stats["boulevard_lawn_islands"] = accepted_lawn_islands
	_enhancement_stats["boulevard_lawn_area_m2"] = accepted_lawn_area_m2
	_enhancement_stats["boulevard_topiary"] = ball_topiary_transforms.size() + hedge_block_transforms.size() + cone_topiary_transforms.size()
	_enhancement_stats["boulevard_continuous_hedges"] = continuous_hedge_count
	_enhancement_stats["boulevard_modern_lamps"] = modern_lamp_count
	_enhancement_stats["boulevard_stone_benches"] = stone_bench_count
	_enhancement_stats["boulevard_pool_decks"] = boulevard_pool_deck_count
	_enhancement_stats["boulevard_ground_cover"] = boulevard_ground_cover_count
	_enhancement_stats["boulevard_extra_date_palms"] = extra_date_palm_transforms.size() if extra_palms_built else 0
	_enhancement_stats["boulevard_extra_royal_palms"] = 0
	_enhancement_stats["premium_boulevard_promenade_m2"] = promenade_area_m2
	_enhancement_stats["boulevard_rebuild_0218"] = (
		bool(_enhancement_stats.get("premium_stone_paving_shader_0218", false))
		and int(_enhancement_stats.get("boulevard_granite_curbs", 0)) >= 180
		and int(_enhancement_stats.get("boulevard_premium_sidewalk_slabs", 0)) >= 180
		and int(_enhancement_stats.get("boulevard_fresh_markings", 0)) >= 450
		and accepted_cafes >= 5
		and accepted_arcades >= 4
		and accepted_lawn_islands >= 24
		and pebble_transforms.size() >= 60
		and boulevard_ground_cover_count >= 180
	)
	_enhancement_stats["boulevard_reference_0219"] = (
		bool(_enhancement_stats.get("boulevard_rebuild_0218", false))
		and bool(_enhancement_stats.get("boulevard_dark_asphalt_0219", false))
		and bool(_enhancement_stats.get("dubai_premium_cafe_pbr_0219", false))
		and accepted_cafes >= 8
		and accepted_spawn_cafes >= 1
		and accepted_arcades >= 9
		and accepted_lawn_islands >= 45
		and continuous_hedge_count >= 45
		and modern_lamp_count >= 55
		and stone_bench_count >= 25
		and boulevard_pool_deck_count >= 3
		and int(_enhancement_stats.get("boulevard_marina_deck_segments", 0)) >= 20
		and int(_enhancement_stats.get("boulevard_date_palms", 0)) >= 60
		and int(_enhancement_stats.get("boulevard_frontage_infill", 0)) >= 8
	)


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
	var sign_back_transforms_0237: Array = []
	var sign_symbol_transforms_0237: Array = []

	var segment_counter := 0
	var bollard_counter := 0
	var planter_counter := 0
	var bin_counter := 0
	var sign_counter := 0
	var rejected_roadside_footprints := 0
	var bridge_segments_skipped_0237 := 0
	var sail_loop_segments_skipped_0238 := 0
	for road_variant in data.get("roads", []):
		var road: Dictionary = road_variant
		var samples: Array = road.get("samples", [])
		if samples.size() < 2:
			continue
		var width := _f(road, "widthM", 10.0)
		var half_width := width * 0.5
		# Bridges/causeways have guardrails, not pavements: the old
		# scatter put planter crates, bins and sign posts on the sand
		# or water just outside the Sail/Palm causeway rails.
		var is_bridge_road_0237 := String(road.get("id", "")) in ["rt-sail-road", "rt-palm-1", "rt-highway-1"]
		# The resort oval has its own designed lamps/palms/hedges;
		# the generic city scatter dropped sign posts, bins and
		# planters onto its narrow pavements and entry mouth.
		var is_sail_loop_0238 := String(road.get("id", "")) == "rt-sail-loop"
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
			if is_bridge_road_0237 or is_sail_loop_0238:
				if is_bridge_road_0237:
					bridge_segments_skipped_0237 += 1
				if is_sail_loop_0238:
					sail_loop_segments_skipped_0238 += 1
				segment_counter += 1
				continue

			if width >= 17.0 and segment_counter % 3 == 0:
				var bollard_side := -1.0 if bollard_counter % 2 == 0 else 1.0
				bollard_counter += 1
				var bollard_pos := midpoint + side_vector * bollard_side * (half_width + 1.45)
				bollard_pos.y = maxf(height_at(bollard_pos.x, bollard_pos.z), midpoint.y + 0.04)
				if _is_roadside_position_valid(bollard_pos):
					if _is_footprint_clear_of_roads(bollard_pos, Vector2(0.20, 0.20), road_yaw, 0.45):
						bollard_transforms.append(make_transform(bollard_pos + Vector3(0.0, 0.43, 0.0), road_yaw, Vector3.ONE))
					else:
						rejected_roadside_footprints += 1

			if width >= 8.0 and segment_counter % 5 == 1:
				var planter_side := -1.0 if planter_counter % 2 == 0 else 1.0
				planter_counter += 1
				var planter_pos := midpoint + side_vector * planter_side * (half_width + 1.58)
				planter_pos.y = maxf(height_at(planter_pos.x, planter_pos.z), midpoint.y + 0.04)
				if _is_roadside_position_valid(planter_pos):
					if _is_footprint_clear_of_roads(planter_pos, Vector2(1.90, 0.75), road_yaw, 0.45):
						planter_transforms.append(make_transform(planter_pos + Vector3(0.0, 0.28, 0.0), road_yaw, Vector3(1.9, 0.55, 0.75)))
						hedge_transforms.append(make_transform(planter_pos + Vector3(0.0, 0.76, 0.0), road_yaw, Vector3(1.68, 0.55, 0.56)))
					else:
						rejected_roadside_footprints += 1

			if segment_counter % 11 == 4:
				var bin_side := -1.0 if bin_counter % 2 == 0 else 1.0
				bin_counter += 1
				var bin_pos := midpoint + side_vector * bin_side * (half_width + 1.50)
				bin_pos.y = maxf(height_at(bin_pos.x, bin_pos.z), midpoint.y + 0.04)
				if _is_roadside_position_valid(bin_pos):
					if _is_footprint_clear_of_roads(bin_pos, Vector2(0.65, 0.65), road_yaw, 0.45):
						bin_transforms.append(make_transform(bin_pos + Vector3(0.0, 0.39, 0.0), road_yaw, Vector3.ONE))
					else:
						rejected_roadside_footprints += 1

			if segment_counter % 14 == 7:
				var sign_side := -1.0 if sign_counter % 2 == 0 else 1.0
				var sign_group := sign_counter % 3
				sign_counter += 1
				var sign_pos := midpoint + side_vector * sign_side * (half_width + 1.65)
				sign_pos.y = maxf(height_at(sign_pos.x, sign_pos.z), midpoint.y + 0.04)
				if _is_roadside_position_valid(sign_pos):
					var panel_normal := -side_vector * sign_side
					var panel_yaw := _yaw_for_z_normal(panel_normal)
					if (
						_is_footprint_clear_of_roads(sign_pos, Vector2(0.12, 0.12), road_yaw, 0.45)
						and _is_footprint_clear_of_roads(sign_pos, Vector2(1.35, 0.09), panel_yaw, 0.45)
					):
						sign_post_transforms.append(make_transform(sign_pos + Vector3(0.0, 1.4, 0.0), road_yaw, Vector3.ONE))
						var panel_center := sign_pos + Vector3(0.0, 2.62, 0.0)
						(sign_panel_transforms[sign_group] as Array).append(make_transform(
							panel_center,
							panel_yaw,
							Vector3(1.35, 0.82, 0.09)
						))
						# A real sign is not a blank emissive slab from
						# behind: galvanized back plate on the rear
						# face, three white legend bars on the front.
						var panel_basis := Basis(Vector3.UP, panel_yaw)
						sign_back_transforms_0237.append(make_transform(
							panel_center + panel_basis * Vector3(0.0, 0.0, -0.062),
							panel_yaw,
							Vector3(1.43, 0.90, 0.035)
						))
						sign_symbol_transforms_0237.append(make_transform(panel_center + panel_basis * Vector3(-0.08, 0.19, 0.056), panel_yaw, Vector3(0.88, 0.10, 0.018)))
						sign_symbol_transforms_0237.append(make_transform(panel_center + panel_basis * Vector3(-0.08, 0.0, 0.056), panel_yaw, Vector3(0.88, 0.10, 0.018)))
						sign_symbol_transforms_0237.append(make_transform(panel_center + panel_basis * Vector3(-0.23, -0.19, 0.056), panel_yaw, Vector3(0.58, 0.10, 0.018)))
					else:
						rejected_roadside_footprints += 1

			segment_counter += 1

	_add_multimesh(root, bollard_mesh, metal, bollard_transforms, "CityBollards", false)
	_add_multimesh(root, unit_box, concrete, planter_transforms, "CityPlanters", false)
	_add_multimesh(root, unit_box, hedge, hedge_transforms, "CityHedges", false)
	_add_multimesh(root, bin_mesh, metal, bin_transforms, "CityTrashBins", false)
	_add_multimesh(root, sign_post_mesh, metal, sign_post_transforms, "CityRoadSignPosts", false)
	for group_index in 3:
		_add_multimesh(root, unit_box, sign_materials[group_index], sign_panel_transforms[group_index], "CityRoadSigns_%d" % group_index, false)
	_add_multimesh(root, unit_box, metal, sign_back_transforms_0237, "CityRoadSignBacks0237", false)
	_add_multimesh(root, unit_box, white_painted, sign_symbol_transforms_0237, "CityRoadSignSymbols0237", false)

	var roadside_prop_count := bollard_transforms.size() + planter_transforms.size() + bin_transforms.size() + sign_post_transforms.size()
	_enhancement_stats["bridge_roadside_props_removed_0237"] = bridge_segments_skipped_0237 > 0
	_enhancement_stats["bridge_segments_without_props_0237"] = bridge_segments_skipped_0237
	_enhancement_stats["sail_loop_generic_props_removed_0238"] = sail_loop_segments_skipped_0238 >= 56
	_enhancement_stats["sail_loop_segments_without_props_0238"] = sail_loop_segments_skipped_0238
	_enhancement_stats["readable_road_signs_0237"] = sign_back_transforms_0237.size()
	_enhancement_stats["city_detail_props"] = roadside_prop_count
	_enhancement_stats["roadside_bollards"] = bollard_transforms.size()
	_enhancement_stats["roadside_planters"] = planter_transforms.size()
	_enhancement_stats["rejected_roadside_footprints_0236"] = rejected_roadside_footprints
	_enhancement_stats["roadside_footprints_clear_0236"] = true

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
		# 0.2.17: Godot's Mobile probe path applies extra radiance
		# energy relative to Forward+.  At 1.24 the near-metallic
		# main-tower panes clipped toward white; 0.62 keeps the same
		# box-projected district image under the dark tinted F0.
		probe.intensity = 0.68
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
	_enhancement_stats["reflection_probe_intensity"] = 0.68
	_enhancement_stats["reflection_probe_mobile_calibration_0217"] = true


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


## 0.2.22 RichTown parks: three designed green rooms instead of leftover
## empty terrain.  The Central Park turns the exported rtPlaza into a
## formal garden around the existing fountain (its east-west axis at
## Z=23 continues the Boulevard screenshot axis), the Museum Garden is a
## quiet parterre/pergola square west of the museum torus and the
## Corniche Palmetum is an irrigated palm park on the beach.  Layouts
## are planned, not scattered: perimeter promenades, main axes with
## palm alleys, diagonal alleys, lawn panels, clipped-hedge flower
## parterres, oak groves and palm clusters on white-pebble beds.  All
## planting reuses the batched plant-pack/palm/ground-cover systems, so
## the density costs a handful of MultiMesh chunks per park, not nodes.
func _make_diagonal_path_mesh(a: Vector2, b: Vector2, width: float, step_m: float = 2.5, lift_m: float = 0.092) -> ArrayMesh:
	var axis := b - a
	var length := axis.length()
	if length < 2.0:
		return null
	var dir := axis / length
	var side := Vector2(-dir.y, dir.x) * (width * 0.5)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var columns := maxi(1, ceili(length / step_m))
	for i in columns:
		var c0 := a + axis * (float(i) / float(columns))
		var c1 := a + axis * (float(i + 1) / float(columns))
		var corners: Array[Vector2] = [c0 - side, c1 - side, c1 + side, c0 + side]
		var pts: Array[Vector3] = []
		for corner in corners:
			pts.append(Vector3(corner.x, height_at(corner.x, corner.y) + lift_m, corner.y))
		for vertex in [pts[0], pts[1], pts[2], pts[0], pts[2], pts[3]]:
			_terrain_vertex(tool, vertex)
	tool.index()
	tool.generate_normals()
	tool.generate_tangents()
	return tool.commit()


func _park_dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 <= 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _park_on_path(ctx: Dictionary, p: Vector2, pad: float) -> bool:
	for rect_variant in ctx.get("path_rects", []):
		var r: Rect2 = rect_variant
		if r.grow(pad).has_point(p):
			return true
	for seg_variant in ctx.get("diagonals", []):
		var seg: Dictionary = seg_variant
		if _park_dist_to_segment(p, seg.get("a", Vector2.ZERO), seg.get("b", Vector2.ZERO)) < float(seg.get("w", 4.0)) * 0.5 + pad:
			return true
	return false


func _park_accept_large(ctx: Dictionary, pos: Vector3, min_spacing: float, ignore_focal: bool = false) -> bool:
	var p := Vector2(pos.x, pos.z)
	if _park_on_path(ctx, p, 0.9):
		return false
	var focal: Vector2 = ctx.get("focal", Vector2.ZERO)
	if not ignore_focal and p.distance_to(focal) < float(ctx.get("focal_radius", 10.0)) + 2.0:
		return false
	if pos.y < 0.55:
		return false
	if not _is_position_clear(pos, 1.2, 3.2):
		return false
	var accepted: Array = ctx.get("accepted_large", [])
	for other_variant in accepted:
		var other: Vector2 = other_variant
		if p.distance_squared_to(other) < min_spacing * min_spacing:
			return false
	accepted.append(p)
	ctx["accepted_large"] = accepted
	return true


func _park_accept_small(ctx: Dictionary, pos: Vector3) -> bool:
	var p := Vector2(pos.x, pos.z)
	if _park_on_path(ctx, p, 0.30):
		return false
	var focal: Vector2 = ctx.get("focal", Vector2.ZERO)
	if p.distance_to(focal) < float(ctx.get("focal_radius", 10.0)) + 0.4:
		return false
	return pos.y > 0.45


func _park_add_oak(ctx: Dictionary, pos: Vector3, yaw: float, s: float) -> void:
	(ctx["oak_transforms"] as Array).append(make_transform(pos + Vector3(0.0, -0.04, 0.0), yaw, Vector3.ONE * (2.85 * s)))
	_add_cylinder_collider(pos + Vector3(0.0, 1.4, 0.0), 0.38, 3.2)


func _park_add_palm(ctx: Dictionary, pos: Vector3, yaw: float, royal: bool, s: float) -> void:
	var uniform := (0.78 if royal else 0.80) * s
	var key := "royal_transforms" if royal else "date_transforms"
	(ctx[key] as Array).append(make_transform(pos + Vector3(0.0, -0.03, 0.0), yaw, Vector3(uniform, uniform * 1.03, uniform)))
	_add_cylinder_collider(pos + Vector3(0.0, 3.0, 0.0), 0.34, 6.2)


func _park_add_bench(ctx: Dictionary, pos: Vector3, yaw: float) -> void:
	# 0.2.23: one cast-iron/hardwood Blender bench per seat.  The GLB
	# seat front faces local -Z after Y-up export, so the extra PI turn
	# keeps focal benches facing their fountain/pergola/rondel centre.
	(ctx["bench_transforms"] as Array).append(make_transform(pos + Vector3(0.0, 0.030, 0.0), yaw + PI, Vector3.ONE))
	_add_box_collider(pos + Vector3(0.0, 0.45, 0.0), Vector3(2.4, 0.95, 0.85), yaw)
	ctx["bench_count"] = int(ctx.get("bench_count", 0)) + 1


func _park_scatter(ctx: Dictionary, zone: Rect2, key: String, density_per_m2: float, seed_base: int, min_scale: float, max_scale: float, margin: float = 1.2) -> void:
	var desired := int(round(zone.size.x * zone.size.y * density_per_m2))
	if desired <= 0:
		return
	var accepted := 0
	for attempt in desired * 7:
		if accepted >= desired:
			break
		var seed := seed_base + attempt * 131
		var px := zone.position.x + margin + _hash01(seed * 3 + 11, seed * 5 + 71) * maxf(zone.size.x - margin * 2.0, 0.5)
		var pz := zone.position.y + margin + _hash01(seed * 7 + 31, seed * 11 + 97) * maxf(zone.size.y - margin * 2.0, 0.5)
		var candidate := Vector3(px, height_at(px, pz) + 0.045, pz)
		if not _park_accept_small(ctx, candidate):
			continue
		var width_scale := lerpf(min_scale, max_scale, _hash01(seed * 13 + 17, seed * 17 + 43))
		var height_scale := lerpf(min_scale, max_scale, _hash01(seed * 19 + 23, seed * 23 + 59))
		(ctx[key] as Array).append(make_transform(candidate, _hash01(seed * 29 + 3, seed * 31 + 13) * TAU, Vector3(width_scale, height_scale, width_scale)))
		accepted += 1


func _park_scatter_bushes(ctx: Dictionary, zone: Rect2, density_per_m2: float, seed_base: int) -> void:
	var desired := int(round(zone.size.x * zone.size.y * density_per_m2))
	if desired <= 0:
		return
	var part_names: Array[String] = ["bush_round_foliage", "shrub_cone_foliage", "fan_foliage"]
	var accepted := 0
	for attempt in desired * 7:
		if accepted >= desired:
			break
		var seed := seed_base + attempt * 149
		var px := zone.position.x + 1.4 + _hash01(seed * 3 + 11, seed * 5 + 71) * maxf(zone.size.x - 2.8, 0.5)
		var pz := zone.position.y + 1.4 + _hash01(seed * 7 + 31, seed * 11 + 97) * maxf(zone.size.y - 2.8, 0.5)
		var candidate := Vector3(px, height_at(px, pz) + 0.02, pz)
		if not _park_accept_small(ctx, candidate):
			continue
		var part_name := part_names[accepted % part_names.size()]
		var target_height := 1.45 if part_name == "bush_round_foliage" else (2.25 if part_name == "shrub_cone_foliage" else 1.25)
		var source_height := 0.77 if part_name == "bush_round_foliage" else (1.65 if part_name == "shrub_cone_foliage" else 0.60)
		var scale_value := target_height / source_height * (0.85 + _hash01(seed * 13 + 17, seed * 17 + 43) * 0.4)
		(ctx["bush_" + part_name] as Array).append(make_transform(candidate, _hash01(seed * 29 + 3, seed * 31 + 13) * TAU, Vector3.ONE * scale_value))
		accepted += 1


func _park_plant_oak_grove(ctx: Dictionary, zone: Rect2, seed_base: int) -> void:
	var spacing := 11.5
	var margin := 4.5
	var ix := 0
	var x := zone.position.x + margin
	while x <= zone.position.x + zone.size.x - margin + 0.1:
		var iz := 0
		var z := zone.position.y + margin + (float(ix % 2) * spacing * 0.5)
		while z <= zone.position.y + zone.size.y - margin + 0.1:
			var seed := seed_base + ix * 101 + iz * 17
			var px := x + (_hash01(seed * 3 + 7, seed * 5 + 13) - 0.5) * 4.6
			var pz := z + (_hash01(seed * 7 + 19, seed * 11 + 23) - 0.5) * 4.6
			var pos := Vector3(px, height_at(px, pz), pz)
			if _park_accept_large(ctx, pos, 6.0):
				_park_add_oak(ctx, pos, _hash01(seed * 13 + 3, seed * 17 + 5) * TAU, 0.92 + _hash01(seed * 19 + 11, seed * 23 + 7) * 0.30)
			iz += 1
			z += spacing
		ix += 1
		x += spacing
	_park_scatter(ctx, zone, "grass_transforms", 0.16, seed_base + 5000, 0.85, 1.55)
	_park_scatter(ctx, zone, "flower_transforms", 0.016, seed_base + 7000, 0.80, 1.30)
	_park_scatter_bushes(ctx, zone, 0.014, seed_base + 9000)


func _park_plant_palm_grove(ctx: Dictionary, zone: Rect2, seed_base: int) -> void:
	var spacing := 15.5 if minf(zone.size.x, zone.size.y) >= 30.0 else 12.0
	var margin := 5.5
	var focal: Vector2 = ctx.get("focal", Vector2.ZERO)
	var focal_radius := float(ctx.get("focal_radius", 10.0))
	var ix := 0
	var x := zone.position.x + margin
	while x <= zone.position.x + zone.size.x - margin + 0.1:
		var iz := 0
		var z := zone.position.y + margin + (float(ix % 2) * spacing * 0.5)
		while z <= zone.position.y + zone.size.y - margin + 0.1:
			var seed := seed_base + ix * 111 + iz * 19
			var centre := Vector3(x, height_at(x, z), z)
			if _park_accept_large(ctx, centre, 5.5):
				(ctx["pebble_transforms"] as Array).append(make_transform(centre + Vector3(0.0, 0.06, 0.0), 0.0, Vector3(3.4, 1.0, 3.4)))
				var base_angle := _hash01(seed * 3 + 7, seed * 5 + 11) * TAU
				_park_add_palm(ctx, centre, base_angle * 1.31, ix % 2 == 1, 1.02)
				for member in 3:
					var ang := base_angle + TAU * float(member) / 3.0
					var mp := Vector3(centre.x + cos(ang) * 2.4, 0.0, centre.z + sin(ang) * 2.4)
					mp.y = height_at(mp.x, mp.z)
					if _park_on_path(ctx, Vector2(mp.x, mp.z), 0.7):
						continue
					if Vector2(mp.x, mp.z).distance_to(focal) < focal_radius + 1.5:
						continue
					_park_add_palm(ctx, mp, _hash01(seed * 13 + member * 7, seed * 17 + member * 3) * TAU, member == 2 and ix % 2 == 0, 0.94 + _hash01(seed * 19 + member, seed * 23 + member) * 0.16)
					(ctx["accepted_large"] as Array).append(Vector2(mp.x, mp.z))
			iz += 1
			z += spacing
		ix += 1
		x += spacing
	_park_scatter(ctx, zone, "grass_transforms", 0.12, seed_base + 5000, 0.85, 1.55)
	_park_scatter(ctx, zone, "shrub_transforms", 0.010, seed_base + 7000, 0.84, 1.40)
	_park_scatter_bushes(ctx, zone, 0.008, seed_base + 9000)


func _park_plant_parterre(ctx: Dictionary, zone: Rect2, seed_base: int, park_root: Node, mulch_material: Material, park_id: String, zone_index: int) -> void:
	var focal: Vector2 = ctx.get("focal", Vector2.ZERO)
	var focal_radius := float(ctx.get("focal_radius", 10.0))
	var beds: Array[Rect2] = []
	var inner := zone.grow(-5.0)
	if inner.size.x > 10.0 and inner.size.y > 10.0:
		var half_x := inner.size.x * 0.5
		var half_z := inner.size.y * 0.5
		beds.append(Rect2(inner.position.x, inner.position.y, half_x - 2.0, half_z - 2.0))
		beds.append(Rect2(inner.position.x + half_x + 2.0, inner.position.y + half_z + 2.0, half_x - 2.0, half_z - 2.0))
	for bed_i in beds.size():
		var bed: Rect2 = beds[bed_i]
		var bed_mesh := _make_paving_patch_mesh(bed.position.x, bed.position.x + bed.size.x, bed.position.y, bed.position.y + bed.size.y, 2.0, 0.068)
		if bed_mesh != null:
			_mesh_instance(park_root, bed_mesh, mulch_material, Transform3D.IDENTITY, "ParkFlowerBed_%s_%d_%d" % [park_id, zone_index, bed_i], false)
			ctx["flower_bed_area_m2"] = float(ctx.get("flower_bed_area_m2", 0.0)) + bed.size.x * bed.size.y
		_park_scatter(ctx, bed, "flower_transforms", 0.50, seed_base + bed_i * 3000 + 11000, 0.80, 1.30, 0.7)
		_park_scatter(ctx, bed, "shrub_transforms", 0.045, seed_base + bed_i * 3000 + 13000, 0.84, 1.35, 0.9)
	var corner_inset := 3.4
	var corners: Array[Vector2] = [
		Vector2(zone.position.x + corner_inset, zone.position.y + corner_inset),
		Vector2(zone.position.x + zone.size.x - corner_inset, zone.position.y + corner_inset),
		Vector2(zone.position.x + corner_inset, zone.position.y + zone.size.y - corner_inset),
		Vector2(zone.position.x + zone.size.x - corner_inset, zone.position.y + zone.size.y - corner_inset),
	]
	for ci in corners.size():
		var cp := corners[ci]
		if _park_on_path(ctx, cp, 0.4):
			continue
		if cp.distance_to(focal) < focal_radius + 1.0:
			continue
		var cpos := Vector3(cp.x, height_at(cp.x, cp.y), cp.y)
		var ball_scale := 1.30
		(ctx["topiary_ball_transforms"] as Array).append(make_transform(cpos + Vector3(0.0, 0.56 * ball_scale + 0.04, 0.0), float(ci) * 0.7, Vector3.ONE * ball_scale))
	if zone.size.x > 26.0 and zone.size.y > 26.0:
		var cc := zone.get_center()
		if not _park_on_path(ctx, cc, 0.4) and cc.distance_to(focal) >= focal_radius + 1.0:
			var cpos := Vector3(cc.x, height_at(cc.x, cc.y), cc.y)
			(ctx["topiary_cone_transforms"] as Array).append(make_transform(cpos + Vector3(0.0, 0.82, 0.0), 0.0, Vector3.ONE * 1.05))
	_park_scatter(ctx, zone, "grass_transforms", 0.10, seed_base + 5000, 0.85, 1.45)
	_park_scatter_bushes(ctx, zone, 0.006, seed_base + 9000)


func _park_add_hedge_border(ctx: Dictionary, zone: Rect2) -> void:
	var focal: Vector2 = ctx.get("focal", Vector2.ZERO)
	var focal_radius := float(ctx.get("focal_radius", 10.0))
	var edges: Array = [
		{"a": Vector2(zone.position.x, zone.position.y + 0.6), "b": Vector2(zone.position.x + zone.size.x, zone.position.y + 0.6)},
		{"a": Vector2(zone.position.x, zone.position.y + zone.size.y - 0.6), "b": Vector2(zone.position.x + zone.size.x, zone.position.y + zone.size.y - 0.6)},
		{"a": Vector2(zone.position.x + 0.6, zone.position.y), "b": Vector2(zone.position.x + 0.6, zone.position.y + zone.size.y)},
		{"a": Vector2(zone.position.x + zone.size.x - 0.6, zone.position.y), "b": Vector2(zone.position.x + zone.size.x - 0.6, zone.position.y + zone.size.y)},
	]
	for edge_variant in edges:
		var edge: Dictionary = edge_variant
		var a: Vector2 = edge.get("a", Vector2.ZERO)
		var b: Vector2 = edge.get("b", Vector2.ZERO)
		var length := a.distance_to(b)
		var dir := (b - a) / maxf(length, 0.01)
		var horizontal := absf(dir.x) > 0.5
		var mid := (a + b) * 0.5
		var d := 2.1
		while d <= length - 2.0:
			var p := a + dir * d
			d += 4.2
			if p.distance_to(mid) < 3.4:
				continue
			if _park_on_path(ctx, p, 0.15):
				continue
			if p.distance_to(focal) < focal_radius + 0.8:
				continue
			var size := Vector3(3.9, 0.85, 0.95) if horizontal else Vector3(0.95, 0.85, 3.9)
			(ctx["hedge_transforms"] as Array).append(make_transform(Vector3(p.x, height_at(p.x, p.y) + 0.45, p.y), 0.0, size))
			ctx["hedge_length_m"] = float(ctx.get("hedge_length_m", 0.0)) + 3.9


func _park_plant_open_lawn(ctx: Dictionary, zone: Rect2, seed_base: int) -> void:
	var spots: Array[Vector2] = [Vector2(0.30, 0.35), Vector2(0.68, 0.62), Vector2(0.46, 0.82)]
	for si in spots.size():
		var f := spots[si]
		var px := zone.position.x + zone.size.x * f.x
		var pz := zone.position.y + zone.size.y * f.y
		var pos := Vector3(px, height_at(px, pz), pz)
		if _park_accept_large(ctx, pos, 6.0):
			var yaw := _hash01(seed_base + si * 43, si * 29 + 7) * TAU
			if si == 1:
				_park_add_palm(ctx, pos, yaw, false, 1.02)
			else:
				_park_add_oak(ctx, pos, yaw, 1.02)
	_park_scatter(ctx, zone, "grass_transforms", 0.20, seed_base + 5000, 0.85, 1.55)
	_park_scatter(ctx, zone, "flower_transforms", 0.020, seed_base + 7000, 0.80, 1.30)
	_park_scatter_bushes(ctx, zone, 0.010, seed_base + 9000)
	_park_scatter(ctx, zone, "shrub_transforms", 0.008, seed_base + 11000, 0.84, 1.40)


func _park_plant_perimeter(ctx: Dictionary, spec: Dictionary, seed_base: int) -> void:
	var kind := String(spec.get("perimeter", "none"))
	if kind == "none":
		return
	var rect: Rect2 = spec.get("rect", Rect2())
	var inset := 7.6
	var x0 := rect.position.x + inset
	var x1 := rect.position.x + rect.size.x - inset
	var z0 := rect.position.y + inset
	var z1 := rect.position.y + rect.size.y - inset
	var step := 13.5 if kind == "oak" else 14.5
	var points: Array[Vector2] = []
	var t := 0.0
	while t <= (x1 - x0) + 0.1:
		points.append(Vector2(x0 + t, z0))
		points.append(Vector2(x0 + t, z1))
		t += step
	t = step
	while t <= (z1 - z0) - step * 0.4:
		points.append(Vector2(x0, z0 + t))
		points.append(Vector2(x1, z0 + t))
		t += step
	for i in points.size():
		var p := points[i]
		var seed := seed_base + i * 37
		var px := p.x + (_hash01(seed * 3 + 5, seed * 7 + 11) - 0.5) * 1.6
		var pz := p.y + (_hash01(seed * 11 + 3, seed * 13 + 7) - 0.5) * 1.6
		var pos := Vector3(px, height_at(px, pz), pz)
		if not _park_accept_large(ctx, pos, 5.5):
			continue
		var yaw := _hash01(seed * 17 + 3, seed * 19 + 5) * TAU
		if kind == "oak":
			_park_add_oak(ctx, pos, yaw, 0.95 + _hash01(seed * 23 + 7, seed * 29 + 11) * 0.25)
		else:
			_park_add_palm(ctx, pos, yaw, i % 3 == 0, 0.95 + _hash01(seed * 23 + 7, seed * 29 + 11) * 0.20)


func _park_plant_alleys(ctx: Dictionary, spec: Dictionary, seed_base: int) -> void:
	var mode := String(spec.get("alleys", "none"))
	if mode == "none":
		return
	var rect: Rect2 = spec.get("rect", Rect2())
	var axis_x := float(spec.get("axis_x", 0.0))
	var axis_z := float(spec.get("axis_z", 0.0))
	var half := float(spec.get("axis_half", 3.5))
	var index := 0
	if mode == "both" or mode == "ns":
		for side in [-1.0, 1.0]:
			var x := axis_x + float(side) * (half + 1.9)
			var z := rect.position.y + 11.0
			while z <= rect.position.y + rect.size.y - 11.0 + 0.1:
				if absf(z - axis_z) > half + 5.0:
					var pos := Vector3(x, height_at(x, z), z)
					if _park_accept_large(ctx, pos, 5.5):
						_park_add_palm(ctx, pos, _hash01(seed_base + index * 41, index * 23 + 7) * TAU, index % 4 == 3, 0.98)
					index += 1
				z += 13.5
	if mode == "both" or mode == "ew":
		for side in [-1.0, 1.0]:
			var z := axis_z + float(side) * (half + 1.9)
			var x := rect.position.x + 11.0
			while x <= rect.position.x + rect.size.x - 11.0 + 0.1:
				if absf(x - axis_x) > half + 5.0:
					var pos := Vector3(x, height_at(x, z), z)
					if _park_accept_large(ctx, pos, 5.5):
						_park_add_palm(ctx, pos, _hash01(seed_base + index * 41, index * 23 + 7) * TAU, index % 4 == 3, 0.98)
					index += 1
				x += 13.5


func _park_build_focal(ctx: Dictionary, spec: Dictionary, seed_base: int) -> void:
	var focal: Vector2 = spec.get("focal", Vector2.ZERO)
	var kind := String(spec.get("focal_kind", ""))
	match kind:
		"fountain":
			var ring := 0
			for i in 32:
				var ang := TAU * float(i) / 32.0
				var r := 17.6 + _hash01(seed_base + i * 31, i * 17 + 3) * 0.9
				var p := focal + Vector2(cos(ang), sin(ang)) * r
				if _park_on_path(ctx, p, 0.25):
					continue
				var pos := Vector3(p.x, height_at(p.x, p.y) + 0.04, p.y)
				var s := 0.95 + _hash01(seed_base + i * 37, i * 19 + 5) * 0.35
				(ctx["flower_transforms"] as Array).append(make_transform(pos, ang * 1.7, Vector3.ONE * s))
				ring += 1
			for i in 8:
				var ang := TAU * (float(i) + 0.5) / 8.0
				var p := focal + Vector2(cos(ang), sin(ang)) * 21.0
				if _park_on_path(ctx, p, 0.3):
					continue
				var pos := Vector3(p.x, height_at(p.x, p.y), p.y)
				(ctx["topiary_ball_transforms"] as Array).append(make_transform(pos + Vector3(0.0, 0.95, 0.0), ang, Vector3.ONE * 1.65))
			ctx["focal_done"] = ring >= 20
		"pergola":
			var centre := Vector3(focal.x, height_at(focal.x, focal.y), focal.y)
			var stone: Array = ctx["pergola_stone_transforms"]
			var column_points: Array[Vector3] = []
			for i in 6:
				var ang := TAU * float(i) / 6.0 + PI / 6.0
				var cp := centre + Vector3(cos(ang) * 5.2, 0.0, sin(ang) * 5.2)
				cp.y = height_at(cp.x, cp.z)
				column_points.append(cp)
				_add_cylinder_collider(cp + Vector3(0.0, 1.55, 0.0), 0.4, 3.1)
			# 0.2.23: the whole hexagonal structure is one Blender GLB
			# whose six columns land exactly on the colliders above.
			(ctx["pergola_model_transforms"] as Array).append(make_transform(centre + Vector3(0.0, 0.04, 0.0), 0.0, Vector3.ONE))
			stone.append(make_transform(centre + Vector3(0.0, 0.10, 0.0), 0.0, Vector3(4.6, 0.2, 4.6)))
			for i in 4:
				var ang := TAU * (float(i) + 0.5) / 4.0
				var bp := centre + Vector3(cos(ang) * 3.3, 0.0, sin(ang) * 3.3)
				bp.y = height_at(bp.x, bp.z) + 0.10
				_park_add_bench(ctx, bp, _yaw_for_x_direction(Vector3(-sin(ang), 0.0, cos(ang))))
			var flower_ring := 0
			for i in 24:
				var ang := TAU * float(i) / 24.0
				var p := focal + Vector2(cos(ang), sin(ang)) * 13.8
				var pos := Vector3(p.x, height_at(p.x, p.y) + 0.04, p.y)
				if not _park_accept_small(ctx, pos):
					continue
				(ctx["flower_transforms"] as Array).append(make_transform(pos, ang * 1.7, Vector3.ONE * (0.9 + _hash01(seed_base + i * 37, i * 19 + 5) * 0.3)))
				flower_ring += 1
			for i in 8:
				var ang := TAU * (float(i) + 0.25) / 8.0
				var p := focal + Vector2(cos(ang), sin(ang)) * 14.5
				var pos := Vector3(p.x, height_at(p.x, p.y), p.y)
				if _park_accept_large(ctx, pos, 5.0, true):
					_park_add_palm(ctx, pos, ang * 1.3, true, 0.92)
			for corner_sign in [Vector2(-9.8, -9.8), Vector2(9.8, -9.8), Vector2(-9.8, 9.8), Vector2(9.8, 9.8)]:
				var corner_p: Vector2 = focal + corner_sign
				if _park_on_path(ctx, corner_p, 0.3):
					continue
				var corner_pos := Vector3(corner_p.x, height_at(corner_p.x, corner_p.y), corner_p.y)
				(ctx["topiary_ball_transforms"] as Array).append(make_transform(corner_pos + Vector3(0.0, 0.78, 0.0), 0.4, Vector3.ONE * 1.35))
			ctx["focal_done"] = column_points.size() == 6 and flower_ring >= 10
		"rondel":
			var ring_palms := 0
			for i in 8:
				var ang := TAU * (float(i) + 0.5) / 8.0
				var p := focal + Vector2(cos(ang), sin(ang)) * 9.2
				var pos := Vector3(p.x, height_at(p.x, p.y), p.y)
				_park_add_palm(ctx, pos, ang * 1.9, true, 1.0)
				(ctx["pebble_transforms"] as Array).append(make_transform(pos + Vector3(0.0, 0.10, 0.0), 0.0, Vector3(1.9, 1.0, 1.9)))
				(ctx["accepted_large"] as Array).append(p)
				ring_palms += 1
			for i in 4:
				var ang := TAU * float(i) / 4.0 + PI / 4.0
				var tp := Vector3(focal.x + cos(ang) * 11.5, 0.0, focal.y + sin(ang) * 11.5)
				tp.y = height_at(tp.x, tp.z)
				(ctx["topiary_ball_transforms"] as Array).append(make_transform(tp + Vector3(0.0, 0.72, 0.0), ang, Vector3.ONE * 1.20))
			for i in 6:
				var ang := TAU * float(i) / 6.0 + PI / 6.0
				var bp := Vector3(focal.x + cos(ang) * 6.0, 0.0, focal.y + sin(ang) * 6.0)
				bp.y = height_at(bp.x, bp.z) + 0.08
				_park_add_bench(ctx, bp, _yaw_for_x_direction(Vector3(-sin(ang), 0.0, cos(ang))))
			for i in 20:
				var ang := TAU * float(i) / 20.0
				var p := focal + Vector2(cos(ang), sin(ang)) * 13.2
				var pos := Vector3(p.x, height_at(p.x, p.y) + 0.04, p.y)
				if not _park_accept_small(ctx, pos):
					continue
				(ctx["flower_transforms"] as Array).append(make_transform(pos, ang * 1.7, Vector3.ONE * (0.9 + _hash01(seed_base + i * 37, i * 19 + 5) * 0.3)))
			ctx["focal_done"] = ring_palms >= 7


func _park_place_furniture(ctx: Dictionary, spec: Dictionary) -> void:
	var rect: Rect2 = spec.get("rect", Rect2())
	var axis_x := float(spec.get("axis_x", 0.0))
	var axis_z := float(spec.get("axis_z", 0.0))
	var half := float(spec.get("axis_half", 3.5))
	var focal: Vector2 = ctx.get("focal", Vector2.ZERO)
	var focal_radius := float(ctx.get("focal_radius", 10.0))
	var bench_index := 0
	var bz := rect.position.y + 15.0
	while bz <= rect.position.y + rect.size.y - 13.0:
		if absf(bz - axis_z) > half + 6.0:
			var side := 1.0 if bench_index % 2 == 0 else -1.0
			var p := Vector2(axis_x + side * (half + 1.15), bz)
			if not _park_on_path(ctx, p, 0.55) and p.distance_to(focal) > focal_radius + 1.5:
				_park_add_bench(ctx, Vector3(p.x, height_at(p.x, p.y), p.y), PI * 0.5)
			bench_index += 1
		bz += 17.0
	var bx := rect.position.x + 15.0
	while bx <= rect.position.x + rect.size.x - 13.0:
		if absf(bx - axis_x) > half + 6.0:
			var side := 1.0 if bench_index % 2 == 0 else -1.0
			var p := Vector2(bx, axis_z + side * (half + 1.15))
			if not _park_on_path(ctx, p, 0.55) and p.distance_to(focal) > focal_radius + 1.5:
				_park_add_bench(ctx, Vector3(p.x, height_at(p.x, p.y), p.y), 0.0)
			bench_index += 1
		bx += 17.0
	if bool(spec.get("sea_benches", false)):
		var sz := rect.position.y + 13.0
		while sz <= rect.position.y + rect.size.y - 11.0:
			var p := Vector2(rect.position.x + rect.size.x - 4.4, sz)
			if not _park_on_path(ctx, p, 0.55) and p.distance_to(focal) > focal_radius + 1.5:
				_park_add_bench(ctx, Vector3(p.x, height_at(p.x, p.y), p.y), PI * 0.5)
			sz += 18.0
	var lamp_index := 0
	var lz := rect.position.y + 13.0
	while lz <= rect.position.y + rect.size.y - 11.0:
		if absf(lz - axis_z) > half + 6.0:
			var side := -1.0 if lamp_index % 2 == 0 else 1.0
			var p := Vector2(axis_x + side * (half + 1.3), lz)
			if not _park_on_path(ctx, p, 0.5) and p.distance_to(focal) > focal_radius + 1.0:
				var pos := Vector3(p.x, height_at(p.x, p.y), p.y)
				(ctx["lamp_transforms"] as Array).append(make_transform(pos, _yaw_for_z_normal(Vector3(-side, 0.0, 0.0)), Vector3.ONE))
				_add_cylinder_collider(pos + Vector3(0.0, 3.2, 0.0), 0.18, 6.6)
			lamp_index += 1
		lz += 22.0
	var lx := rect.position.x + 13.0
	while lx <= rect.position.x + rect.size.x - 11.0:
		if absf(lx - axis_x) > half + 6.0:
			var side := 1.0 if lamp_index % 2 == 0 else -1.0
			var p := Vector2(lx, axis_z + side * (half + 1.3))
			if not _park_on_path(ctx, p, 0.5) and p.distance_to(focal) > focal_radius + 1.0:
				var pos := Vector3(p.x, height_at(p.x, p.y), p.y)
				(ctx["lamp_transforms"] as Array).append(make_transform(pos, _yaw_for_z_normal(Vector3(0.0, 0.0, -side)), Vector3.ONE))
				_add_cylinder_collider(pos + Vector3(0.0, 3.2, 0.0), 0.18, 6.6)
			lamp_index += 1
		lx += 22.0
	# Benches and lamps also line the perimeter promenade (the axis
	# furniture above is sparse where diagonals and crossings intervene).
	var min_x := rect.position.x
	var min_z := rect.position.y
	var max_x := rect.position.x + rect.size.x
	var max_z := rect.position.y + rect.size.y
	var sides: Array = [
		{"a": Vector2(min_x + 6.3, min_z + 6.3), "b": Vector2(max_x - 6.3, min_z + 6.3), "yaw": 0.0, "n": Vector2(0.0, -1.0)},
		{"a": Vector2(min_x + 6.3, max_z - 6.3), "b": Vector2(max_x - 6.3, max_z - 6.3), "yaw": 0.0, "n": Vector2(0.0, 1.0)},
		{"a": Vector2(min_x + 6.3, min_z + 6.3), "b": Vector2(min_x + 6.3, max_z - 6.3), "yaw": PI * 0.5, "n": Vector2(-1.0, 0.0)},
		{"a": Vector2(max_x - 6.3, min_z + 6.3), "b": Vector2(max_x - 6.3, max_z - 6.3), "yaw": PI * 0.5, "n": Vector2(1.0, 0.0)},
	]
	for side_variant in sides:
		var side_spec: Dictionary = side_variant
		var a: Vector2 = side_spec.get("a", Vector2.ZERO)
		var b: Vector2 = side_spec.get("b", Vector2.ZERO)
		var normal: Vector2 = side_spec.get("n", Vector2.ZERO)
		var side_length := a.distance_to(b)
		var dir := (b - a) / maxf(side_length, 0.01)
		var bd := 8.0
		while bd <= side_length - 6.0:
			var p := a + dir * bd
			bd += 23.0
			if _park_on_path(ctx, p, 0.55) or p.distance_to(focal) <= focal_radius + 1.5:
				continue
			_park_add_bench(ctx, Vector3(p.x, height_at(p.x, p.y), p.y), float(side_spec.get("yaw", 0.0)))
		var ld := 19.0
		while ld <= side_length - 6.0:
			var p := a + dir * ld
			ld += 31.0
			if _park_on_path(ctx, p, 0.5) or p.distance_to(focal) <= focal_radius + 1.0:
				continue
			var pos := Vector3(p.x, height_at(p.x, p.y), p.y)
			(ctx["lamp_transforms"] as Array).append(make_transform(pos, _yaw_for_z_normal(Vector3(normal.x, 0.0, normal.y)), Vector3.ONE))
			_add_cylinder_collider(pos + Vector3(0.0, 3.2, 0.0), 0.18, 6.6)



## 0.2.24 South Villa District + Palm local streetscape.  The synthetic
## district carriageways themselves come from the exported road data
## (so asphalt, kerbs, markings, tyre surface and the minimap all see
## them); this pass gives the existing villas an actual address:
## paved driveways to the correct street edge, front hedges with a
## driveway gap, street lamps, shade trees/palms, a mosque forecourt
## in the deliberate gap in the west street, a mini-roundabout island
## and a bus shelter.  Palm Island villas get the same driveway
## treatment to their nearest carriageway.
func _build_district_infrastructure() -> void:
	var root := Node3D.new()
	root.name = "DistrictInfrastructure"
	add_child(root)

	var paving_material := _create_premium_paving_material(
		"terrain_premium_pavers_shader",
		Color(0.84, 0.80, 0.70),
		0.68,
		0.140,
		0.50
	)
	var hedge_material := _material(
		"city_hedge",
		"foliage.jpg",
		"foliage_normal.jpg",
		Color(0.42, 0.72, 0.33),
		1.0,
		0.0,
		Vector3(0.35, 0.35, 0.35),
		true
	)
	hedge_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var unit_box := BoxMesh.new()
	unit_box.size = Vector3.ONE

	var hedge_transforms: Array[Transform3D] = []
	var lamp_transforms: Array[Transform3D] = []
	var bench_transforms: Array[Transform3D] = []
	var date_palm_transforms: Array[Transform3D] = []
	var royal_palm_transforms: Array[Transform3D] = []
	var tree_transforms: Array[Transform3D] = []
	var flower_transforms: Array[Transform3D] = []
	var shrub_transforms: Array[Transform3D] = []
	var palm_driveway_transforms: Array[Transform3D] = []
	var driveway_count := 0
	var palm_driveway_count := 0

	# Street inventory for smoke/stats.
	var district_street_count := 0
	var district_street_length := 0.0
	var palm_local_count := 0
	var palm_local_length := 0.0
	for road_variant in data.get("roads", []):
		var road: Dictionary = road_variant
		var road_id := String(road.get("id", ""))
		var is_district := road_id.begins_with("rt-villa-")
		var is_palm_local := road_id.begins_with("rt-palm-local-")
		if not is_district and not is_palm_local:
			continue
		var samples: Array = road.get("samples", [])
		var length_value := 0.0
		for i in range(samples.size() - 1):
			var pa := _sample_point(samples[i])
			var pb := _sample_point(samples[i + 1])
			length_value += Vector2(pb.x - pa.x, pb.z - pa.z).length()
		if is_district:
			district_street_count += 1
			district_street_length += length_value
		else:
			palm_local_count += 1
			palm_local_length += length_value

	# --- South Villa District driveways, hedges and front gardens ---
	for building_variant in data.get("buildings", []):
		var building: Dictionary = building_variant
		if String(building.get("kind", "")) != "rt-villa":
			continue
		var centre := _item_position(building)
		if centre.x < 560.0 or centre.x > 760.0 or centre.z < 225.0 or centre.z > 460.0:
			continue
		var w := _f(building, "w", 20.0)
		var d := _f(building, "d", 15.0)
		var from_x := 0.0
		var to_x := 0.0
		var front_x := 0.0
		if centre.x < 635.0:
			# West column faces the new west street (x=638 north of
			# the mosque, x=640.5 south of it).
			from_x = centre.x + w * 0.5
			to_x = 634.0 if centre.z < 340.0 else 636.5
			front_x = from_x + 2.0
		elif centre.x < 680.0:
			# Middle column faces west to the same street pair.
			to_x = centre.x - w * 0.5
			from_x = 642.0 if centre.z < 340.0 else 644.5
			front_x = to_x - 2.0
		else:
			# East column faces the east local (x~689, chicane to
			# x=694 around the pool at z=390).
			var road_center_x := 689.0
			if centre.z > 372.0 and centre.z < 408.0:
				road_center_x = 694.0
			elif centre.z >= 340.0:
				road_center_x = 690.0
			to_x = centre.x - w * 0.5
			from_x = road_center_x + 4.0
			front_x = to_x - 2.0
		var min_x := minf(from_x, to_x)
		var max_x := maxf(from_x, to_x)
		if max_x - min_x < 2.0:
			continue
		# One exported pool sits in a front garden (x=627,z=389);
		# jog that driveway to the north side of its plot instead
		# of paving over the water.
		var driveway_z := centre.z
		for pool_variant in data.get("pools", []):
			var pool: Dictionary = pool_variant
			var pool_centre := _item_position(pool)
			if pool_centre.x > min_x - 2.0 and pool_centre.x < max_x + 2.0 and absf(pool_centre.z - centre.z) < _f(pool, "d", 5.0) * 0.5 + 3.4:
				driveway_z = centre.z - d * 0.5 + 3.0
				break
		var driveway_mesh := _make_paving_patch_mesh(min_x, max_x, driveway_z - 2.6, driveway_z + 2.6, 1.5, 0.075)
		if driveway_mesh != null:
			_mesh_instance(root, driveway_mesh, paving_material, Transform3D.IDENTITY, "DistrictDriveway", false)
			driveway_count += 1
		# Front hedge along the plot boundary, split at the driveway.
		for span in [
			[centre.z - d * 0.5, driveway_z - 3.4],
			[driveway_z + 3.4, centre.z + d * 0.5],
		]:
			var span_min := float(span[0])
			var span_max := float(span[1])
			if span_max - span_min < 1.2:
				continue
			var mid_z := (span_min + span_max) * 0.5
			hedge_transforms.append(make_transform(
				Vector3(front_x, height_at(front_x, mid_z) + 0.42, mid_z),
				0.0,
				Vector3(0.70, 0.85, span_max - span_min)
			))
		# Front-garden flowers/shrubs flanking the driveway.
		var garden_x := (min_x + max_x) * 0.5
		for side_sign in [-1.0, 1.0]:
			var flower_pos := Vector3(garden_x, 0.0, driveway_z + float(side_sign) * 4.1)
			flower_pos.y = height_at(flower_pos.x, flower_pos.z) + 0.02
			if _is_position_clear(flower_pos, 0.8, 1.2):
				flower_transforms.append(make_transform(flower_pos, driveway_z * 0.37 + float(side_sign), Vector3.ONE * 1.05))
			var shrub_pos := Vector3(front_x, 0.0, centre.z + float(side_sign) * (d * 0.5 - 1.2))
			shrub_pos.y = height_at(shrub_pos.x, shrub_pos.z) + 0.02
			if _is_position_clear(shrub_pos, 0.8, 0.8):
				shrub_transforms.append(make_transform(shrub_pos, centre.x * 0.21 + float(side_sign) * 0.7, Vector3.ONE * 1.15))

	# --- Mosque forecourt in the west-street gap (x=620, z=335) ---
	var plaza_mesh := _make_paving_patch_mesh(596.0, 644.0, 318.0, 352.0, 2.0, 0.075)
	var mosque_plaza := 0
	if plaza_mesh != null:
		_mesh_instance(root, plaza_mesh, paving_material, Transform3D.IDENTITY, "MosqueForecourt", false)
		mosque_plaza = 1
	for bench_pos_variant in [Vector2(598.0, 322.0), Vector2(598.0, 348.0), Vector2(646.5, 322.0), Vector2(646.5, 348.0)]:
		var bench_pos2: Vector2 = bench_pos_variant
		var bench_pos := Vector3(bench_pos2.x, height_at(bench_pos2.x, bench_pos2.y) + 0.09, bench_pos2.y)
		var to_mosque := Vector3(620.0 - bench_pos.x, 0.0, 335.0 - bench_pos.z).normalized()
		# Park-bench GLB seat front faces local -Z (see parks pass).
		# The former x=642 pair stood on the x=638 local carriageway.
		var bench_yaw := atan2(to_mosque.x, to_mosque.z) + PI
		if not _is_footprint_clear_of_roads(bench_pos, Vector2(2.0, 0.8), bench_yaw, 0.45):
			continue
		bench_transforms.append(make_transform(bench_pos, bench_yaw, Vector3.ONE))

	# --- Mini-roundabout island where the east local crosses z=368 ---
	var roundabout_center := Vector3(690.0, 0.0, 368.0)
	roundabout_center.y = height_at(roundabout_center.x, roundabout_center.z)
	var island_mesh := CylinderMesh.new()
	island_mesh.top_radius = 0.5
	island_mesh.bottom_radius = 0.5
	island_mesh.height = 1.0
	island_mesh.radial_segments = 28
	island_mesh.material = paving_material
	_add_multimesh(
		root,
		island_mesh,
		paving_material,
		[make_transform(roundabout_center + Vector3(0.0, ROAD_SURFACE_OFFSET_M + 0.09, 0.0), 0.0, Vector3(6.0, 0.18, 6.0))],
		"DistrictRoundaboutIsland",
		false
	)
	var ring_curb_transforms: Array[Transform3D] = []
	for i in 14:
		var angle := TAU * float(i) / 14.0
		var next_angle := TAU * float(i + 1) / 14.0
		var p0 := roundabout_center + Vector3(cos(angle) * 3.15, 0.0, sin(angle) * 3.15)
		var p1 := roundabout_center + Vector3(cos(next_angle) * 3.15, 0.0, sin(next_angle) * 3.15)
		var tangent := p1 - p0
		var mid := (p0 + p1) * 0.5
		ring_curb_transforms.append(make_transform(
			Vector3(mid.x, roundabout_center.y + 0.16, mid.z),
			atan2(tangent.x, tangent.z),
			Vector3(0.24, 0.20, tangent.length() + 0.05)
		))
	var ring_material := _create_concrete_material("road_curb_shader", Color(0.37, 0.38, 0.37), 0.97, 0.72, 0.55, 0.48)
	_add_multimesh(root, unit_box, ring_material, ring_curb_transforms, "DistrictRoundaboutCurbs", true)
	shrub_transforms.append(make_transform(roundabout_center + Vector3(0.0, ROAD_SURFACE_OFFSET_M + 0.18, 0.0), 0.4, Vector3.ONE * 1.25))
	for i in 6:
		var angle := TAU * float(i) / 6.0 + 0.3
		var flower_pos := roundabout_center + Vector3(cos(angle) * 1.8, ROAD_SURFACE_OFFSET_M + 0.18, sin(angle) * 1.8)
		flower_transforms.append(make_transform(flower_pos, angle * 1.7, Vector3.ONE * 0.95))

	# --- District street lamps (data lamps only cover arterials) ---
	var lamp_specs: Array[Dictionary] = []
	var lamp_index := 0
	for street_z in [286.0, 368.0]:
		for x_value in range(575, 746, 34):
			var side_offset := 5.8 if lamp_index % 2 == 0 else -5.8
			lamp_specs.append({"x": float(x_value), "z": street_z + side_offset, "yaw": PI * 0.5})
			lamp_index += 1
	for z_value in range(240, 421, 34):
		var west_center := 638.0 if float(z_value) < 340.0 else 640.5
		var west_side := 5.3 if lamp_index % 2 == 0 else -5.3
		lamp_specs.append({"x": west_center + west_side, "z": float(z_value), "yaw": 0.0})
		lamp_index += 1
		var east_center := 689.0
		if float(z_value) > 372.0 and float(z_value) < 408.0:
			east_center = 694.0
		var east_side := -5.3 if lamp_index % 2 == 0 else 5.3
		lamp_specs.append({"x": east_center + east_side, "z": float(z_value), "yaw": 0.0})
		lamp_index += 1
	for lamp_spec in lamp_specs:
		var lamp_pos := Vector3(_f(lamp_spec, "x"), 0.0, _f(lamp_spec, "z"))
		lamp_pos.y = height_at(lamp_pos.x, lamp_pos.z) + 0.02
		if not _is_roadside_position_valid(lamp_pos):
			continue
		lamp_transforms.append(make_transform(lamp_pos, _f(lamp_spec, "yaw"), Vector3.ONE))
		_add_cylinder_collider(lamp_pos + Vector3(0.0, 3.2, 0.0), 0.18, 6.6)

	# --- Street trees and palms on the local verges ---
	var verge_candidates: Array[Vector3] = []
	var verge_index := 0
	for street_z in [286.0, 368.0]:
		for x_value in range(578, 746, 28):
			var offset := 8.0 if verge_index % 2 == 0 else -8.0
			verge_candidates.append(Vector3(float(x_value), 0.0, street_z + offset))
			verge_index += 1
	for z_value in range(242, 451, 28):
		var west_center := 638.0 if float(z_value) < 340.0 else 640.5
		var west_offset := -8.0 if verge_index % 2 == 0 else 8.0
		verge_candidates.append(Vector3(west_center + west_offset, 0.0, float(z_value)))
		verge_index += 1
		if float(z_value) <= 426.0:
			var east_center := 689.0
			if float(z_value) > 372.0 and float(z_value) < 408.0:
				east_center = 694.0
			var east_offset := 8.0 if verge_index % 2 == 0 else -8.0
			verge_candidates.append(Vector3(east_center + east_offset, 0.0, float(z_value)))
			verge_index += 1
	for crescent_pos in [Vector3(648.0, 0.0, 445.0), Vector3(662.0, 0.0, 446.0), Vector3(676.0, 0.0, 445.0)]:
		verge_candidates.append(crescent_pos)
	var accepted_verge: Array[Vector3] = []
	for candidate_variant in verge_candidates:
		var candidate: Vector3 = candidate_variant
		candidate.y = height_at(candidate.x, candidate.z)
		if candidate.y < 1.2 or not _is_position_clear(candidate, 2.2, 2.25):
			continue
		var too_close := false
		for accepted in accepted_verge:
			if Vector2(candidate.x - accepted.x, candidate.z - accepted.z).length() < 9.0:
				too_close = true
				break
		if too_close:
			continue
		accepted_verge.append(candidate)
		var accepted_index := accepted_verge.size() - 1
		var yaw := _hash01(int(candidate.x) * 3 + 17, int(candidate.z) * 5 + 29) * TAU
		if accepted_index % 3 == 2:
			var palm_transform := make_transform(candidate + Vector3(0.0, -0.03, 0.0), yaw, Vector3.ONE * (0.92 + _hash01(accepted_index + 7, 41) * 0.18))
			if accepted_index % 2 == 0:
				date_palm_transforms.append(palm_transform)
			else:
				royal_palm_transforms.append(palm_transform)
			_add_cylinder_collider(candidate + Vector3(0.0, 2.75, 0.0), 0.30, 5.5)
		else:
			tree_transforms.append(make_transform(candidate + Vector3(0.0, -0.04, 0.0), yaw, Vector3.ONE * 2.85 * (0.82 + _hash01(accepted_index + 3, 53) * 0.25)))
			_add_cylinder_collider(candidate + Vector3(0.0, 1.4, 0.0), 0.38, 3.2)

	# --- Palm Island villa/hotel driveways to nearest carriageway ---
	for building_variant in data.get("buildings", []):
		var building: Dictionary = building_variant
		var centre := _item_position(building)
		if centre.x < 1200.0:
			continue
		if String(building.get("kind", "")) != "rt-villa" and centre.x < 1430.0:
			continue
		var best_point := Vector3.ZERO
		var best_distance := INF
		var best_half := 4.0
		for road_variant in data.get("roads", []):
			var road: Dictionary = road_variant
			var samples: Array = road.get("samples", [])
			var half_value := _f(road, "widthM", 9.0) * 0.5
			for i in range(samples.size() - 1):
				var pa := _sample_point(samples[i])
				var pb := _sample_point(samples[i + 1])
				var ab := Vector2(pb.x - pa.x, pb.z - pa.z)
				var length_squared := ab.length_squared()
				if length_squared <= 0.0001:
					continue
				var t := clampf(Vector2(centre.x - pa.x, centre.z - pa.z).dot(ab) / length_squared, 0.0, 1.0)
				var closest := pa.lerp(pb, t)
				var dist := Vector2(centre.x - closest.x, centre.z - closest.z).length()
				if dist < best_distance:
					best_distance = dist
					best_point = closest
					best_half = half_value
		if best_distance == INF or best_distance > 48.0:
			continue
		var direction := best_point - centre
		direction.y = 0.0
		if direction.length_squared() < 0.0001:
			continue
		direction = direction.normalized()
		var local_dir := Basis(Vector3.UP, -_f(building, "rotY")) * direction
		var denom := maxf(absf(local_dir.x) / maxf(_f(building, "w", 20.0) * 0.5, 0.1), absf(local_dir.z) / maxf(_f(building, "d", 14.0) * 0.5, 0.1))
		if denom <= 0.0001:
			continue
		var start_point: Vector3 = centre + direction * (1.0 / denom)
		var end_point: Vector3 = best_point - direction * best_half
		var driveway_length := Vector2(end_point.x - start_point.x, end_point.z - start_point.z).length()
		if driveway_length < 1.5:
			continue
		var segments := maxi(1, int(ceil(driveway_length / 4.0)))
		var driveway_yaw := atan2(direction.x, direction.z)
		for seg in range(segments):
			var seg_a := start_point.lerp(end_point, float(seg) / float(segments))
			var seg_b := start_point.lerp(end_point, float(seg + 1) / float(segments))
			var seg_mid := (seg_a + seg_b) * 0.5
			var seg_y := maxf(height_at(seg_a.x, seg_a.z), height_at(seg_b.x, seg_b.z)) + 0.10
			palm_driveway_transforms.append(make_transform(
				Vector3(seg_mid.x, seg_y, seg_mid.z),
				driveway_yaw,
				Vector3(4.4, 0.12, driveway_length / float(segments) + 0.10)
			))
		palm_driveway_count += 1

	# --- Submit batches ---
	_add_multimesh(root, unit_box, hedge_material, hedge_transforms, "DistrictFrontHedges", true, -1.0, 240.0, 180.0)
	if not palm_driveway_transforms.is_empty():
		var palm_driveway_mesh := BoxMesh.new()
		palm_driveway_mesh.size = Vector3.ONE
		palm_driveway_mesh.material = paving_material
		_add_multimesh(root, palm_driveway_mesh, paving_material, palm_driveway_transforms, "PalmIslandDriveways", false)
	var lamps_built := _add_batched_model(root, "res://assets/props/street_lamp.glb", lamp_transforms, "DistrictStreetLamps")
	var benches_built := _add_batched_model(root, "res://assets/props/park_bench.glb", bench_transforms, "DistrictBenches")
	var date_built := _add_batched_model(root, "res://assets/vegetation/palm_date.glb", date_palm_transforms, "DistrictDatePalms")
	var royal_built := _add_batched_model(root, "res://assets/vegetation/palm_royal.glb", royal_palm_transforms, "DistrictRoyalPalms")
	if date_built:
		_add_palm_far_proxy(root, "res://assets/vegetation/palm_date.glb", date_palm_transforms, "DistrictDatePalms")
	if royal_built:
		_add_palm_far_proxy(root, "res://assets/vegetation/palm_royal.glb", royal_palm_transforms, "DistrictRoyalPalms")
	var flowers_built := _add_batched_model(root, "res://assets/vegetation/flower_clump.glb", flower_transforms, "DistrictFlowers")
	var shrubs_built := _add_batched_model(root, "res://assets/vegetation/ornamental_shrub.glb", shrub_transforms, "DistrictShrubs")
	if not tree_transforms.is_empty():
		for part_name in ["tree2_bark", "tree2_foliage"]:
			if _plant_parts.has(part_name):
				var part: Dictionary = _plant_parts[part_name]
				var source_mesh := part.get("mesh") as Mesh
				var detail_end := 150.0 if part_name == "tree2_bark" else 105.0
				_add_multimesh(root, source_mesh, part.get("material") as Material, tree_transforms, "District_%s" % part_name, part_name == "tree2_bark", 0.0, detail_end, 180.0)
				if part_name == "tree2_foliage":
					_add_foliage_far_proxy(root, source_mesh, tree_transforms, "DistrictTree2Foliage", 90.0, 650.0)
	# One shelter on the district's east-west spine.
	var shelter_pos := Vector3(660.0, height_at(660.0, 376.0) + 0.02, 376.0)
	var shelter_footprint_clear := _is_footprint_clear_of_roads(shelter_pos, Vector2(5.75, 2.35), 0.0, 0.45)
	var shelter_transforms: Array[Transform3D] = []
	if shelter_footprint_clear:
		shelter_transforms.append(make_transform(shelter_pos, 0.0, Vector3.ONE))
	var shelter_built := _add_batched_model(root, "res://assets/props/bus_shelter.glb", shelter_transforms, "DistrictBusShelter") and not shelter_transforms.is_empty()
	if shelter_built:
		_add_box_collider(shelter_pos + Vector3(0.0, 1.53, 0.0), Vector3(5.75, 3.06, 2.35), 0.0)
		_enhancement_stats["bus_shelters"] = int(_enhancement_stats.get("bus_shelters", 0)) + 1

	_enhancement_stats["district_infrastructure_0224"] = true
	_enhancement_stats["district_streets"] = district_street_count
	_enhancement_stats["district_street_length_m"] = snappedf(district_street_length, 0.1)
	_enhancement_stats["palm_local_roads"] = palm_local_count
	_enhancement_stats["palm_local_length_m"] = snappedf(palm_local_length, 0.1)
	_enhancement_stats["district_driveways"] = driveway_count
	_enhancement_stats["palm_driveways"] = palm_driveway_count
	_enhancement_stats["district_hedges"] = hedge_transforms.size()
	_enhancement_stats["district_lamps"] = lamp_transforms.size() if lamps_built else 0
	_enhancement_stats["district_benches"] = bench_transforms.size() if benches_built else 0
	_enhancement_stats["district_street_trees"] = tree_transforms.size()
	_enhancement_stats["district_palms"] = (date_palm_transforms.size() if date_built else 0) + (royal_palm_transforms.size() if royal_built else 0)
	_enhancement_stats["district_flowers"] = flower_transforms.size() if flowers_built else 0
	_enhancement_stats["district_shrubs"] = shrub_transforms.size() if shrubs_built else 0
	_enhancement_stats["district_roundabout"] = 1
	_enhancement_stats["district_mosque_plaza"] = mosque_plaza
	_enhancement_stats["district_bus_shelter"] = 1 if shelter_built else 0

func _build_parks() -> void:
	var root := Node3D.new()
	root.name = "RichTownParks"
	add_child(root)
	_load_plant_parts()

	var lawn_material := _material("park_lawn", "user_grass.jpg", "user_grass_normal.jpg", Color(0.52, 0.74, 0.38), 0.96, 0.0, Vector3(0.55, 0.55, 0.55), true)
	lawn_material.normal_scale = 0.82
	var path_material := _create_premium_paving_material("park_path_pavers_shader", Color(0.86, 0.82, 0.72), 0.70, 0.135, 0.48)
	var axis_material := _create_premium_paving_material("park_axis_pavers_shader", Color(0.60, 0.58, 0.53), 0.74, 0.120, 0.44)
	var pebble_material := _material("park_white_pebbles", "user_sand_beach_white.jpg", "user_sand_rippled_normal.jpg", Color(0.98, 0.97, 0.93), 0.94, 0.0, Vector3(1.65, 1.65, 1.65), true)
	pebble_material.normal_scale = 0.72
	var mulch_material := _prop_material("VillaMulch")
	var hedge_material := _prop_material("VillaHedge")
	var topiary_material := _material("park_topiary", "foliage.jpg", "foliage_normal.jpg", Color(0.24, 0.47, 0.23), 0.92, 0.0, Vector3(0.85, 0.85, 0.85), true)
	topiary_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var unit_box := BoxMesh.new()
	unit_box.size = Vector3.ONE
	var pebble_mesh := CylinderMesh.new()
	pebble_mesh.top_radius = 1.0
	pebble_mesh.bottom_radius = 1.0
	pebble_mesh.height = 0.08
	pebble_mesh.radial_segments = 20
	var topiary_ball_mesh := SphereMesh.new()
	topiary_ball_mesh.radius = 0.55
	topiary_ball_mesh.height = 1.12
	topiary_ball_mesh.radial_segments = 18
	topiary_ball_mesh.rings = 10
	var topiary_cone_mesh := CylinderMesh.new()
	topiary_cone_mesh.top_radius = 0.08
	topiary_cone_mesh.bottom_radius = 0.58
	topiary_cone_mesh.height = 1.55
	topiary_cone_mesh.radial_segments = 14

	var total_parks := 0
	var total_area := 0.0
	var total_lawn_area := 0.0
	var total_path_area := 0.0
	var total_trees := 0
	var total_palms := 0
	var total_bushes := 0
	var total_ground_cover := 0
	var total_bed_area := 0.0
	var total_hedge_length := 0.0
	var total_benches := 0
	var total_lamps := 0
	var total_topiary := 0

	for park_index in PARK_SPECS.size():
		var spec: Dictionary = PARK_SPECS[park_index]
		var park_id := String(spec.get("id", "park"))
		var rect: Rect2 = spec.get("rect", Rect2())
		var focal_kind := String(spec.get("focal_kind", ""))
		var park_root := Node3D.new()
		park_root.name = "Park_%s" % park_id
		root.add_child(park_root)
		total_parks += 1
		total_area += rect.size.x * rect.size.y

		var ctx: Dictionary = {
			"id": park_id,
			"rect": rect,
			"focal": spec.get("focal", Vector2.ZERO),
			"focal_radius": float(spec.get("focal_radius", 10.0)),
			"path_rects": [],
			"diagonals": spec.get("diagonals", []),
			"accepted_large": [],
			"oak_transforms": [],
			"date_transforms": [],
			"royal_transforms": [],
			"bush_bush_round_foliage": [],
			"bush_shrub_cone_foliage": [],
			"bush_fan_foliage": [],
			"grass_transforms": [],
			"flower_transforms": [],
			"shrub_transforms": [],
			"hedge_transforms": [],
			"topiary_ball_transforms": [],
			"topiary_cone_transforms": [],
			"pebble_transforms": [],
			"bench_transforms": [],
			"lamp_transforms": [],
			"pergola_stone_transforms": [],
			"pergola_wood_transforms": [],
			"pergola_model_transforms": [],
			"bench_count": 0,
			"hedge_length_m": 0.0,
			"flower_bed_area_m2": 0.0,
			"focal_done": false,
		}

		var min_x := rect.position.x
		var min_z := rect.position.y
		var max_x := rect.position.x + rect.size.x
		var max_z := rect.position.y + rect.size.y
		var axis_x := float(spec.get("axis_x", (min_x + max_x) * 0.5))
		var axis_z := float(spec.get("axis_z", (min_z + max_z) * 0.5))
		var axis_half := float(spec.get("axis_half", 3.5))

		var path_rects: Array = ctx["path_rects"]
		var path_styles: Array = []
		path_rects.append(Rect2(min_x + 2.2, min_z + 2.2, 3.2, rect.size.y - 4.4))
		path_styles.append("perimeter")
		path_rects.append(Rect2(max_x - 5.4, min_z + 2.2, 3.2, rect.size.y - 4.4))
		path_styles.append("perimeter")
		path_rects.append(Rect2(min_x + 5.4, min_z + 2.2, rect.size.x - 10.8, 3.2))
		path_styles.append("perimeter")
		path_rects.append(Rect2(min_x + 5.4, max_z - 5.4, rect.size.x - 10.8, 3.2))
		path_styles.append("perimeter")
		path_rects.append(Rect2(axis_x - axis_half, min_z + 2.2, axis_half * 2.0, rect.size.y - 4.4))
		path_styles.append("axis")
		path_rects.append(Rect2(min_x + 2.2, axis_z - axis_half, rect.size.x - 4.4, axis_half * 2.0))
		path_styles.append("axis")
		for cross_variant in spec.get("cross_z", []):
			var cross: Array = cross_variant
			path_rects.append(Rect2(min_x + 2.2, float(cross[0]) - float(cross[1]), rect.size.x - 4.4, float(cross[1]) * 2.0))
			path_styles.append("cross")
		for extra_variant in spec.get("extra_paths", []):
			path_rects.append(extra_variant)
			path_styles.append("extra")

		for path_i in path_rects.size():
			var pr: Rect2 = path_rects[path_i]
			var style := String(path_styles[path_i])
			var lift := 0.070
			var mat: Material = path_material
			match style:
				"axis":
					lift = 0.084
					mat = axis_material
				"cross":
					lift = 0.076
				"extra":
					lift = 0.100
					if focal_kind == "rondel":
						mat = pebble_material
			var path_mesh := _make_paving_patch_mesh(pr.position.x, pr.position.x + pr.size.x, pr.position.y, pr.position.y + pr.size.y, 2.5, lift)
			if path_mesh != null:
				_mesh_instance(park_root, path_mesh, mat, Transform3D.IDENTITY, "ParkPath_%s_%d" % [park_id, path_i], false)
			total_path_area += pr.size.x * pr.size.y

		var diagonals: Array = spec.get("diagonals", [])
		for diag_i in diagonals.size():
			var diag: Dictionary = diagonals[diag_i]
			var diag_mesh := _make_diagonal_path_mesh(diag.get("a", Vector2.ZERO), diag.get("b", Vector2.ZERO), float(diag.get("w", 4.0)))
			if diag_mesh != null:
				_mesh_instance(park_root, diag_mesh, axis_material, Transform3D.IDENTITY, "ParkDiagonal_%s_%d" % [park_id, diag_i], false)

		var z_bands: Array = [Vector2(axis_z - axis_half, axis_z + axis_half)]
		for cross_variant in spec.get("cross_z", []):
			var cross: Array = cross_variant
			z_bands.append(Vector2(float(cross[0]) - float(cross[1]), float(cross[0]) + float(cross[1])))
		z_bands.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var z_intervals: Array = []
		var z_cursor := min_z + 5.4
		for band_variant in z_bands:
			var band: Vector2 = band_variant
			if band.x > z_cursor + 4.0:
				z_intervals.append(Vector2(z_cursor, band.x))
			z_cursor = maxf(z_cursor, band.y)
		if max_z - 5.4 > z_cursor + 4.0:
			z_intervals.append(Vector2(z_cursor, max_z - 5.4))
		var x_intervals: Array = [Vector2(min_x + 5.4, axis_x - axis_half), Vector2(axis_x + axis_half, max_x - 5.4)]
		var lawn_i := 0
		for xi_variant in x_intervals:
			var xi: Vector2 = xi_variant
			if xi.y - xi.x < 6.0:
				continue
			for zi_variant in z_intervals:
				var zi: Vector2 = zi_variant
				if zi.y - zi.x < 6.0:
					continue
				var lawn_mesh := _make_paving_patch_mesh(xi.x, xi.y, zi.x, zi.y, 2.5, 0.052)
				if lawn_mesh != null:
					_mesh_instance(park_root, lawn_mesh, lawn_material, Transform3D.IDENTITY, "ParkLawn_%s_%d" % [park_id, lawn_i], false)
					total_lawn_area += (xi.y - xi.x) * (zi.y - zi.x)
				lawn_i += 1

		var seed_base := 220000 + park_index * 100000
		_park_plant_perimeter(ctx, spec, seed_base)
		_park_plant_alleys(ctx, spec, seed_base + 20000)
		var zones: Array = spec.get("zones", [])
		for zone_i in zones.size():
			var zone_spec: Dictionary = zones[zone_i]
			var zone: Rect2 = zone_spec.get("rect", Rect2())
			var pattern := String(zone_spec.get("pattern", "open_lawn"))
			var zone_seed := seed_base + 30000 + zone_i * 5000
			match pattern:
				"oak_grove":
					_park_plant_oak_grove(ctx, zone, zone_seed)
				"palm_grove":
					_park_plant_palm_grove(ctx, zone, zone_seed)
					_park_add_hedge_border(ctx, zone)
				"parterre":
					_park_plant_parterre(ctx, zone, zone_seed, park_root, mulch_material, park_id, zone_i)
					_park_add_hedge_border(ctx, zone)
				_:
					_park_plant_open_lawn(ctx, zone, zone_seed)
		_park_build_focal(ctx, spec, seed_base + 80000)
		_park_place_furniture(ctx, spec)

		var oak_transforms: Array = ctx["oak_transforms"]
		var oaks_built := false
		if not oak_transforms.is_empty():
			for part_name in ["tree2_bark", "tree2_foliage"]:
				if _plant_parts.has(part_name):
					var part: Dictionary = _plant_parts[part_name]
					var source_mesh := part.get("mesh") as Mesh
					var detail_end := 150.0 if part_name == "tree2_bark" else 105.0
					oaks_built = _add_multimesh(park_root, source_mesh, part.get("material") as Material, oak_transforms, "ParkOaks_%s_%s" % [park_id, part_name], part_name == "tree2_bark", 0.0, detail_end, 180.0) or oaks_built
					if part_name == "tree2_foliage":
						_add_foliage_far_proxy(park_root, source_mesh, oak_transforms, "ParkOaks_%s_%s" % [park_id, part_name], 90.0, 650.0)
		total_trees += oak_transforms.size() if oaks_built else 0

		var park_bush_count := 0
		for part_name in ["bush_round_foliage", "shrub_cone_foliage", "fan_foliage"]:
			var bush_transforms: Array = ctx.get("bush_" + part_name, [])
			if bush_transforms.is_empty() or not _plant_parts.has(part_name):
				continue
			var part: Dictionary = _plant_parts[part_name]
			var source_mesh := part.get("mesh") as Mesh
			if _add_multimesh(park_root, source_mesh, part.get("material") as Material, bush_transforms, "ParkBushes_%s_%s" % [park_id, part_name], false, 0.0, 90.0, 180.0):
				park_bush_count += bush_transforms.size()
				_add_foliage_far_proxy(park_root, source_mesh, bush_transforms, "ParkBushes_%s_%s" % [park_id, part_name], 80.0, 260.0)
		total_bushes += park_bush_count

		var date_transforms: Array = ctx["date_transforms"]
		var royal_transforms: Array = ctx["royal_transforms"]
		var date_built := _add_batched_model(park_root, "res://assets/vegetation/palm_date.glb", date_transforms, "ParkDatePalms")
		var royal_built := _add_batched_model(park_root, "res://assets/vegetation/palm_royal.glb", royal_transforms, "ParkRoyalPalms")
		var park_palm_count := (date_transforms.size() if date_built else 0) + (royal_transforms.size() if royal_built else 0)
		total_palms += park_palm_count
		if date_built:
			_enhancement_stats["date_palms"] = int(_enhancement_stats.get("date_palms", 0)) + date_transforms.size()
		if royal_built:
			_enhancement_stats["royal_palms"] = int(_enhancement_stats.get("royal_palms", 0)) + royal_transforms.size()
		if park_palm_count > 0:
			_enhancement_stats["detailed_palms"] = int(_enhancement_stats.get("detailed_palms", 0)) + park_palm_count

		var grass_transforms: Array = ctx["grass_transforms"]
		var flower_transforms: Array = ctx["flower_transforms"]
		var shrub_transforms: Array = ctx["shrub_transforms"]
		if _add_batched_model(park_root, "res://assets/vegetation/grass_tuft.glb", grass_transforms, "ParkGrassTufts"):
			total_ground_cover += grass_transforms.size()
		if _add_batched_model(park_root, "res://assets/vegetation/flower_clump.glb", flower_transforms, "ParkFlowerClumps"):
			total_ground_cover += flower_transforms.size()
		if _add_batched_model(park_root, "res://assets/vegetation/ornamental_shrub.glb", shrub_transforms, "ParkOrnamentalShrubs"):
			total_ground_cover += shrub_transforms.size()

		if _add_multimesh(park_root, unit_box, hedge_material, ctx["hedge_transforms"], "ParkClippedHedges_%s" % park_id, false, 0.0, 320.0, 180.0):
			total_hedge_length += float(ctx.get("hedge_length_m", 0.0))
		var park_topiary_count := 0
		if _add_multimesh(park_root, topiary_ball_mesh, topiary_material, ctx["topiary_ball_transforms"], "ParkTopiaryBalls_%s" % park_id, false, 0.0, 260.0, 180.0):
			park_topiary_count += (ctx["topiary_ball_transforms"] as Array).size()
		if _add_multimesh(park_root, topiary_cone_mesh, topiary_material, ctx["topiary_cone_transforms"], "ParkTopiaryCones_%s" % park_id, false, 0.0, 260.0, 180.0):
			park_topiary_count += (ctx["topiary_cone_transforms"] as Array).size()
		total_topiary += park_topiary_count
		_add_multimesh(park_root, pebble_mesh, pebble_material, ctx["pebble_transforms"], "ParkPalmPebbleBeds_%s" % park_id, false, 0.0, 220.0, 180.0)
		if _add_batched_model(park_root, "res://assets/props/park_bench.glb", ctx["bench_transforms"], "ParkBenches"):
			total_benches += int(ctx.get("bench_count", 0))
		var lamp_transforms: Array = ctx["lamp_transforms"]
		if _add_batched_model(park_root, "res://assets/props/street_lamp.glb", lamp_transforms, "ParkLamps"):
			total_lamps += lamp_transforms.size()
		var pergola_built := false
		if not (ctx["pergola_model_transforms"] as Array).is_empty():
			pergola_built = _add_batched_model(park_root, "res://assets/props/park_pergola.glb", ctx["pergola_model_transforms"], "MuseumPergola")
			_add_multimesh(park_root, unit_box, _prop_material("VillaStone"), ctx["pergola_stone_transforms"], "MuseumPergolaCentrePlinth", true, 0.0, 300.0, 180.0)
			ctx["focal_done"] = bool(ctx.get("focal_done", false)) and pergola_built

		total_bed_area += float(ctx.get("flower_bed_area_m2", 0.0))
		match park_id:
			"central":
				_enhancement_stats["central_park_fountain_garden"] = bool(ctx.get("focal_done", false))
			"museum":
				_enhancement_stats["museum_garden_pergola"] = bool(ctx.get("focal_done", false))
			"beach":
				_enhancement_stats["beach_palmetum_rondel"] = bool(ctx.get("focal_done", false))

	_enhancement_stats["parks_0222"] = total_parks >= 3 and total_trees > 0 and total_palms > 0
	_enhancement_stats["parks"] = total_parks
	_enhancement_stats["park_area_m2"] = total_area
	_enhancement_stats["park_lawn_area_m2"] = total_lawn_area
	_enhancement_stats["park_path_area_m2"] = total_path_area
	_enhancement_stats["park_trees"] = total_trees
	_enhancement_stats["park_palms"] = total_palms
	_enhancement_stats["park_bushes"] = total_bushes
	_enhancement_stats["park_ground_cover"] = total_ground_cover
	_enhancement_stats["park_flower_bed_area_m2"] = total_bed_area
	_enhancement_stats["park_hedge_length_m"] = total_hedge_length
	_enhancement_stats["park_benches"] = total_benches
	_enhancement_stats["park_bench_models"] = total_benches
	_enhancement_stats["photoreal_park_furniture_0223"] = total_benches >= 34 and bool(_enhancement_stats.get("museum_garden_pergola", false))
	_enhancement_stats["park_lamps"] = total_lamps
	_enhancement_stats["park_topiary"] = total_topiary


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


# --------------------------------------------------------------------------- #
# 0.2.47 Desert ("Пустынный каньон") — second world.  Data comes from
# native/data/desert_native.json, generated offline by
# scripts/generate_desert_world.py from the owner's spec in
# docs/DESERT_MAP.md (4x4 km basin, mesas/canyons north, quarry NE, oil
# field east, salt flat centre, town "Дюны" west, wind farm SW, dune
# sea south, oasis SE).  Everything below only runs when
# world_id == "desert"; the RichTown path above is untouched.  Static
# dressing is merged per 256 m chunk per material, scatter is chunked
# MultiMesh, and the generic systems (road surface index, collider
# streaming, foliage grid, sky/time, probes) are reused as-is.
# --------------------------------------------------------------------------- #

const DESERT_DATA_PATH := "res://data/desert_native.json"
const FOREST_DATA_PATH := "res://data/greenforest_native.json"
const DESERT_AABB := AABB(Vector3(0.0, -20.0, 0.0), Vector3(4000.0, 500.0, 4000.0))
const DZ_CHUNK_M := 256.0

var _dz_merge: Dictionary = {}
var _dz_prim_cache: Dictionary = {}
var _dz_pumpjack_pivots: Array[Dictionary] = []
var _dz_rotors: Array[Dictionary] = []
var _dz_beacon_material: StandardMaterial3D
var _dz_flare_material: StandardMaterial3D
var _dz_scatter_material: StandardMaterial3D


func _road_surface_kind_at(point: Vector3) -> String:
	if _road_segment_grid.is_empty():
		return "asphalt"
	var candidates: Array = _road_segment_grid.get(_road_grid_cell(point.x, point.z), [])
	var best_clearance := ROAD_GRID_QUERY_CLEARANCE_M
	var best_kind := "asphalt"
	for index_variant in candidates:
		var i := int(index_variant)
		var clearance := _distance_to_segment_xz(point, _road_segment_starts[i], _road_segment_ends[i]) - _road_segment_half_widths[i]
		if clearance < best_clearance:
			best_clearance = clearance
			if i < _road_segment_surfaces.size():
				best_kind = _road_segment_surfaces[i]
	return best_kind


func _build_desert_world() -> Dictionary:
	# Synchronous compatibility wrapper; staged loading uses
	# _queue_desert_build_stages through begin_build_world().
	world_id = "desert"
	return build_world()


func _dz_data() -> Dictionary:
	# 0.2.54: the desert build path (roads, bridges, merged structures,
	# game markers) is data-driven; GreenForest ships the same schema
	# under its own key and reuses all of it.
	if _is_forest:
		return data.get("forest", {})
	return data.get("desert", {})


func _dz_ground_y(x: float, z: float, sink: float = 0.05) -> float:
	return height_at(x, z) - sink


func _dz_footprint_y(cx: float, cz: float, w: float, d: float, yaw: float) -> float:
	var basis := Basis(Vector3.UP, yaw)
	var gy := height_at(cx, cz)
	for fx in [-0.5, 0.5]:
		for fz in [-0.5, 0.5]:
			var p: Vector3 = Vector3(cx, 0.0, cz) + basis * Vector3(fx * w, 0.0, fz * d)
			gy = maxf(gy, height_at(p.x, p.z))
	return gy - 0.12


# --- terrain ----------------------------------------------------------------

func _build_desert_terrain() -> void:
	var cols := int(_terrain.get("cols", 0))
	var rows := int(_terrain.get("rows", 0))
	if cols < 2 or rows < 2:
		return
	var min_x := _f(_terrain, "minX", 0.0)
	var min_z := _f(_terrain, "minZ", 0.0)
	var step := _f(_terrain, "stepM", 8.0)
	var terrain_root := Node3D.new()
	terrain_root.name = "Terrain"
	add_child(terrain_root)
	_terrain_meshes.clear()
	var chunk_cells := maxi(int(DZ_CHUNK_M / step), 1)
	var chunk_count := 0
	for cz0 in range(0, rows - 1, chunk_cells):
		for cx0 in range(0, cols - 1, chunk_cells):
			var tools: Dictionary = {}
			var min_y := INF
			var max_y := -INF
			var iz_end := mini(cz0 + chunk_cells, rows - 1)
			var ix_end := mini(cx0 + chunk_cells, cols - 1)
			for iz in range(cz0, iz_end):
				for ix in range(cx0, ix_end):
					var x0 := min_x + float(ix) * step
					var z0 := min_z + float(iz) * step
					var x1 := x0 + step
					var z1 := z0 + step
					var p00 := Vector3(x0, _grid_height(ix, iz), z0)
					var p10 := Vector3(x1, _grid_height(ix + 1, iz), z0)
					var p11 := Vector3(x1, _grid_height(ix + 1, iz + 1), z1)
					var p01 := Vector3(x0, _grid_height(ix, iz + 1), z1)
					min_y = minf(min_y, minf(p00.y, p11.y))
					max_y = maxf(max_y, maxf(p10.y, p01.y))
					var center := (p00 + p11) * 0.5
					var slope := maxf(absf(p10.y - p00.y), absf(p01.y - p00.y)) / step
					var kind := _terrain_class(center.x, center.z, center.y, slope, ix, iz)
					if not tools.has(kind):
						var new_tool := SurfaceTool.new()
						new_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
						tools[kind] = new_tool
					var tool := tools[kind] as SurfaceTool
					for vertex in [p00, p10, p11, p00, p11, p01]:
						_terrain_vertex(tool, vertex)
			for kind in tools.keys():
				var tool := tools[kind] as SurfaceTool
				tool.index()
				tool.generate_normals()
				tool.generate_tangents()
				var mesh := tool.commit()
				if mesh == null:
					continue
				if not _terrain_meshes.has(String(kind)):
					_terrain_meshes[String(kind)] = mesh
				var instance := _mesh_instance(terrain_root, mesh, _terrain_material(String(kind)), Transform3D.IDENTITY, "Terrain_%s_%d_%d" % [String(kind), cx0, cz0], false)
				instance.custom_aabb = AABB(
					Vector3(min_x + float(cx0) * step, min_y - 2.0, min_z + float(cz0) * step),
					Vector3(float(chunk_cells) * step, (max_y - min_y) + 4.0, float(chunk_cells) * step))
				chunk_count += 1
	_enhancement_stats["desert_terrain_chunks"] = chunk_count
	_enhancement_stats["terrain_meshes"] = _terrain_meshes.size()

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


func _build_desert_water() -> void:
	var root := Node3D.new()
	root.name = "Water"
	add_child(root)
	var lake: Dictionary = _dz_data().get("lake", {})
	var lake_x := _f(lake, "x", 3350.0)
	var lake_z := _f(lake, "z", 3500.0)
	var lake_y := _f(lake, "y", 26.2)
	var lake_r := _f(lake, "radius", 78.0)
	var lake_mesh := CylinderMesh.new()
	lake_mesh.top_radius = lake_r + 12.0
	lake_mesh.bottom_radius = lake_r + 12.0
	lake_mesh.height = 0.24
	lake_mesh.radial_segments = 72
	lake_mesh.rings = 1
	_mesh_instance(root, lake_mesh, _water_material(), make_transform(Vector3(lake_x, lake_y - 0.12, lake_z)), "OasisLake", false)
	# Stream ribbon flowing into the lake from the west.
	var stream: Array = _dz_data().get("stream", [])
	if stream.size() >= 2:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var pts: Array[Vector3] = []
		for p_variant in stream:
			var p: Array = p_variant
			pts.append(Vector3(float(p[0]), 0.0, float(p[1])))
		for i in range(pts.size() - 1):
			var a := pts[i]
			var b := pts[i + 1]
			var dir := Vector2(b.x - a.x, b.z - a.z).normalized()
			var perp := Vector2(-dir.y, dir.x) * 3.6
			var ya := minf(height_at(a.x, a.z) + 0.32, lake_y + 0.4)
			var yb := minf(height_at(b.x, b.z) + 0.32, lake_y + 0.4)
			var v0 := Vector3(a.x - perp.x, ya, a.z - perp.y)
			var v1 := Vector3(a.x + perp.x, ya, a.z + perp.y)
			var v2 := Vector3(b.x + perp.x, yb, b.z + perp.y)
			var v3 := Vector3(b.x - perp.x, yb, b.z - perp.y)
			for vertex in [v0, v1, v2, v0, v2, v3]:
				tool.set_uv(Vector2(vertex.x / 9.0, vertex.z / 9.0))
				tool.add_vertex(vertex)
		tool.generate_normals()
		var stream_mesh := tool.commit()
		if stream_mesh != null:
			_mesh_instance(root, stream_mesh, _water_material(), Transform3D.IDENTITY, "OasisStream", false)
	_enhancement_stats["desert_lake"] = true
	_enhancement_stats["desert_lake_calm_0253"] = true


# --- roads ------------------------------------------------------------------

func _dz_road_points(road: Dictionary) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for s_variant in road.get("samples", []):
		pts.append(_sample_point(s_variant))
	# 0.2.49: smooth the driving profile.  The raw sample heights come
	# from the 8 m heightmap, whose steps and junction stamps made the
	# car hop on climbs.  A few Laplacian passes plus a grade clamp
	# give rounded vertical curves; ribbon, bridges and tunnel all
	# read heights through here, so they stay consistent.
	var n := pts.size()
	if n >= 3:
		var closed := bool(road.get("closed", false))
		var ys: Array[float] = []
		ys.resize(n)
		for i in range(n):
			ys[i] = pts[i].y
		for pass_i in range(3):
			var src: Array[float] = []
			src.resize(n)
			for i in range(n):
				src[i] = ys[i]
			for i in range(n):
				var ip := i - 1
				var inx := i + 1
				if closed:
					ip = (i - 1 + n) % n
					inx = (i + 1) % n
				else:
					ip = maxi(i - 1, 0)
					inx = mini(i + 1, n - 1)
				ys[i] = src[i] + 0.30 * ((src[ip] + src[inx]) * 0.5 - src[i])
		var surf := String(road.get("surface", "asphalt"))
		var max_grade := 0.17
		if surf == "asphalt":
			max_grade = 0.12
		elif String(road.get("id", "")).begins_with("dz-trail_"):
			max_grade = 0.20
		for pass_i in range(2):
			for i in range(n - 1):
				var seg := Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z).length()
				var lim := max_grade * maxf(seg, 1.0)
				ys[i + 1] = clampf(ys[i + 1], ys[i] - lim, ys[i] + lim)
			for i in range(n - 2, -1, -1):
				var seg2 := Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z).length()
				var lim2 := max_grade * maxf(seg2, 1.0)
				ys[i] = clampf(ys[i], ys[i + 1] - lim2, ys[i + 1] + lim2)
		for i in range(n):
			var smoothed := pts[i]
			smoothed.y = ys[i]
			pts[i] = smoothed
	return pts


func _dz_point_perps(pts: Array[Vector3], closed: bool) -> Array[Vector2]:
	var perps: Array[Vector2] = []
	var n := pts.size()
	for i in range(n):
		var prev_i := i - 1
		var next_i := i + 1
		if closed:
			prev_i = (i - 1 + n) % n
			next_i = (i + 1) % n
		else:
			prev_i = maxi(i - 1, 0)
			next_i = mini(i + 1, n - 1)
		var d := Vector2(pts[next_i].x - pts[prev_i].x, pts[next_i].z - pts[prev_i].z)
		if d.length_squared() < 0.0001:
			d = Vector2(1.0, 0.0)
		d = d.normalized()
		perps.append(Vector2(-d.y, d.x))
	return perps


func _build_desert_roads() -> void:
	var root := Node3D.new()
	root.name = "DesertRoads"
	add_child(root)
	var asphalt_tool := SurfaceTool.new()
	asphalt_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gravel_tool := SurfaceTool.new()
	gravel_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var marking_tool := SurfaceTool.new()
	marking_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var marking_count := 0
	var deck_colliders := 0
	var crown_offsets: Array = [-1.0, -0.42, 0.42, 1.0]
	var crown_heights: Array = [0.0, 0.045, 0.045, 0.0]
	var road_ordinal := 0
	for road_variant in data.get("roads", []):
		var road: Dictionary = road_variant
		road_ordinal += 1
		var pts := _dz_road_points(road)
		if pts.size() < 2:
			continue
		var width := _f(road, "widthM", 8.0)
		var half_w := width * 0.5
		var surf := String(road.get("surface", "asphalt"))
		var closed := bool(road.get("closed", false))
		var tool := asphalt_tool if surf == "asphalt" else gravel_tool
		# 0.2.56 flush junctions: wider surface tiers plus a
		# deterministic 4 mm per-road micro-lift, so overlapping deck
		# ribbons at crossings always have one clear winner instead of
		# z-fighting against each other.
		var y_off := (0.12 if surf == "asphalt" else 0.06) + float(road_ordinal % 8) * 0.004
		var perps := _dz_point_perps(pts, closed)
		var cumlen: Array[float] = [0.0]
		for i in range(1, pts.size()):
			cumlen.append(cumlen[i - 1] + Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length())
		var seg_count := pts.size() if closed else pts.size() - 1
		# Physical driving deck (0.2.49): pitched box colliders follow
		# the smoothed sample profile, so the wheels ride the road
		# surface itself instead of the 8 m heightmap steps below it.
		for i in range(seg_count):
			var j := (i + 1) % pts.size()
			var a := pts[i]
			var b := pts[j]
			var flat := Vector2(b.x - a.x, b.z - a.z)
			var seg_len := flat.length()
			if seg_len < 0.5:
				continue
			var mid := (a + b) * 0.5
			var yaw := atan2(-flat.x, -flat.y)
			var pitch := atan2(b.y - a.y, seg_len)
			_add_pitched_box_collider(Vector3(mid.x, mid.y + y_off - 0.205, mid.z), Vector3(width + 0.4, 0.5, seg_len + 0.6), yaw, pitch)
			deck_colliders += 1
		for i in range(seg_count):
			var j := (i + 1) % pts.size()
			# Closed loops wrap to sample 0: keep the travelled-metre
			# UV continuous across the seam instead of snapping to 0.
			var len_j := cumlen[j] if j > i else cumlen[pts.size() - 1] + Vector2(pts[0].x - pts[i].x, pts[0].z - pts[i].z).length()
			for k in range(3):
				var oa := float(crown_offsets[k])
				var ob := float(crown_offsets[k + 1])
				var ha := float(crown_heights[k])
				var hb := float(crown_heights[k + 1])
				var a0 := Vector3(pts[i].x + perps[i].x * oa * half_w, pts[i].y + y_off + ha, pts[i].z + perps[i].y * oa * half_w)
				var a1 := Vector3(pts[i].x + perps[i].x * ob * half_w, pts[i].y + y_off + hb, pts[i].z + perps[i].y * ob * half_w)
				var b1 := Vector3(pts[j].x + perps[j].x * ob * half_w, pts[j].y + y_off + hb, pts[j].z + perps[j].y * ob * half_w)
				var b0 := Vector3(pts[j].x + perps[j].x * oa * half_w, pts[j].y + y_off + ha, pts[j].z + perps[j].y * oa * half_w)
				# Asphalt shader contract: UV.x lateral 0..1, UV.y metres/18.
				# Gravel (StandardMaterial) gets world-scale UVs instead.
				var uva := Vector2((oa + 1.0) * 0.5, cumlen[i] / 18.0) if surf == "asphalt" else Vector2(a0.x / 8.0, a0.z / 8.0)
				var uvb := Vector2((ob + 1.0) * 0.5, cumlen[i] / 18.0) if surf == "asphalt" else Vector2(a1.x / 8.0, a1.z / 8.0)
				var uvc := Vector2((ob + 1.0) * 0.5, len_j / 18.0) if surf == "asphalt" else Vector2(b1.x / 8.0, b1.z / 8.0)
				var uvd := Vector2((oa + 1.0) * 0.5, len_j / 18.0) if surf == "asphalt" else Vector2(b0.x / 8.0, b0.z / 8.0)
				for pair in [[a0, uva], [a1, uvb], [b1, uvc], [a0, uva], [b1, uvc], [b0, uvd]]:
					tool.set_uv(pair[1])
					tool.add_vertex(pair[0])
			if surf == "asphalt":
				# Edge lines (continuous) + one centre dash per segment.
				for side in [-1.0, 1.0]:
					var eo: float = side * (half_w - 0.55)
					var e0 := Vector3(pts[i].x + perps[i].x * (eo - 0.09), pts[i].y + y_off + 0.02, pts[i].z + perps[i].y * (eo - 0.09))
					var e1 := Vector3(pts[i].x + perps[i].x * (eo + 0.09), pts[i].y + y_off + 0.02, pts[i].z + perps[i].y * (eo + 0.09))
					var e2 := Vector3(pts[j].x + perps[j].x * (eo + 0.09), pts[j].y + y_off + 0.02, pts[j].z + perps[j].y * (eo + 0.09))
					var e3 := Vector3(pts[j].x + perps[j].x * (eo - 0.09), pts[j].y + y_off + 0.02, pts[j].z + perps[j].y * (eo - 0.09))
					for vertex in [e0, e1, e2, e0, e2, e3]:
						marking_tool.set_uv(Vector2(vertex.x / 4.0, vertex.z / 4.0))
						marking_tool.add_vertex(vertex)
					marking_count += 1
				var dash_end := pts[i].lerp(pts[j], 0.24)
				var d0 := Vector3(pts[i].x - perps[i].x * 0.10, pts[i].y + y_off + 0.055, pts[i].z - perps[i].y * 0.10)
				var d1 := Vector3(pts[i].x + perps[i].x * 0.10, pts[i].y + y_off + 0.055, pts[i].z + perps[i].y * 0.10)
				var d2 := Vector3(dash_end.x + perps[j].x * 0.10, dash_end.y + y_off + 0.055, dash_end.z + perps[j].y * 0.10)
				var d3 := Vector3(dash_end.x - perps[j].x * 0.10, dash_end.y + y_off + 0.055, dash_end.z - perps[j].y * 0.10)
				for vertex in [d0, d1, d2, d0, d2, d3]:
					marking_tool.set_uv(Vector2(vertex.x / 4.0, vertex.z / 4.0))
					marking_tool.add_vertex(vertex)
				marking_count += 1
		if not closed:
			# Junction / trailhead discs so ribbons meet cleanly.
			for end_i in [0, pts.size() - 1]:
				var c := pts[end_i]
				var r := width * 0.62
				var cy := c.y + y_off - 0.005
				for k in range(12):
					var a0 := TAU * float(k) / 12.0
					var a1 := TAU * float(k + 1) / 12.0
					var center_v := Vector3(c.x, cy, c.z)
					var va := Vector3(c.x + cos(a0) * r, cy, c.z + sin(a0) * r)
					var vb := Vector3(c.x + cos(a1) * r, cy, c.z + sin(a1) * r)
					for vertex in [center_v, va, vb]:
						if surf == "asphalt":
							tool.set_uv(Vector2(clampf((vertex.x - c.x) / maxf(r, 0.01) * 0.5 + 0.5, 0.0, 1.0), (cumlen[end_i] if end_i < cumlen.size() else 0.0) / 18.0))
						else:
							tool.set_uv(Vector2(vertex.x / 8.0, vertex.z / 8.0))
						tool.add_vertex(vertex)
	asphalt_tool.index()
	asphalt_tool.generate_normals()
	asphalt_tool.generate_tangents()
	var asphalt_mesh := asphalt_tool.commit()
	if asphalt_mesh != null:
		_road_mesh = asphalt_mesh
		var inst := _mesh_instance(root, asphalt_mesh, _create_asphalt_material(), Transform3D.IDENTITY, "DesertAsphalt", false)
		inst.custom_aabb = _active_aabb
	gravel_tool.index()
	gravel_tool.generate_normals()
	gravel_tool.generate_tangents()
	var gravel_mesh := gravel_tool.commit()
	if gravel_mesh != null:
		var gravel_mat := _material("dz_gravel_road_dz", "dz_trail_gravel.jpg", "dz_trail_gravel_normal.jpg", Color(1.0, 0.99, 0.96), 1.0, 0.0, Vector3.ONE, false, "dz_trail_gravel_roughness.jpg")
		gravel_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var inst := _mesh_instance(root, gravel_mesh, gravel_mat, Transform3D.IDENTITY, "DesertGravel", false)
		inst.custom_aabb = _active_aabb
	marking_tool.index()
	marking_tool.generate_normals()
	var marking_mesh := marking_tool.commit()
	if marking_mesh != null:
		var marking_mat := _material("dz_road_marking", "", "", Color(0.92, 0.91, 0.86), 0.6)
		marking_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var inst := _mesh_instance(root, marking_mesh, marking_mat, Transform3D.IDENTITY, "DesertMarkings", false)
		inst.custom_aabb = _active_aabb
	_enhancement_stats["road_markings"] = marking_count
	_enhancement_stats["desert_road_deck_colliders"] = deck_colliders
	_enhancement_stats["desert_smooth_roads_0249"] = deck_colliders > 3000
	_dz_build_bridges(root)
	_dz_build_tunnel(root)


func _dz_find_road(road_id: String) -> Dictionary:
	for road_variant in data.get("roads", []):
		var road: Dictionary = road_variant
		if String(road.get("id", "")) == road_id:
			return road
	return {}


func _dz_span_indices(pts: Array[Vector3], centre: Vector2, half_length: float) -> Vector2i:
	var best_i := 0
	var best_d := INF
	var cumlen: Array[float] = [0.0]
	for i in range(pts.size()):
		if i > 0:
			cumlen.append(cumlen[i - 1] + Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length())
		var d := Vector2(pts[i].x - centre.x, pts[i].z - centre.y).length()
		if d < best_d:
			best_d = d
			best_i = i
	var s0 := cumlen[best_i] - half_length
	var s1 := cumlen[best_i] + half_length
	var i0 := best_i
	var i1 := best_i
	while i0 > 0 and cumlen[i0] > s0:
		i0 -= 1
	while i1 < pts.size() - 1 and cumlen[i1] < s1:
		i1 += 1
	return Vector2i(i0, i1)


func _dz_build_bridges(root: Node) -> void:
	for bridge_variant in _dz_data().get("bridges", []):
		var bridge: Dictionary = bridge_variant
		var road := _dz_find_road(String(bridge.get("road", "")))
		if road.is_empty():
			continue
		var pts := _dz_road_points(road)
		var width := _f(road, "widthM", 10.0)
		var half_w := width * 0.5
		var centre := Vector2(_f(bridge, "x"), _f(bridge, "z"))
		var span := _dz_span_indices(pts, centre, _f(bridge, "halfLength", 40.0))
		var perps := _dz_point_perps(pts, bool(road.get("closed", false)))
		# Deck colliders: the heightmap keeps the wadi dip, so the car
		# physically rides these boxes while the ribbon floats above.
		for i in range(span.x, span.y):
			var a := pts[i]
			var b := pts[i + 1]
			var mid := (a + b) * 0.5
			var seg_len := Vector2(b.x - a.x, b.z - a.z).length()
			var yaw := atan2(-(b.x - a.x), -(b.z - a.z))
			# Deck collision: the pitched road-deck colliders from
			# _build_desert_roads (flat boxes left steps at joints).
			for side in [-1.0, 1.0]:
				var ea := Vector3(a.x + perps[i].x * side * (half_w + 0.18), a.y - 0.28, a.z + perps[i].y * side * (half_w + 0.18))
				var eb := Vector3(b.x + perps[i + 1].x * side * (half_w + 0.18), b.y - 0.28, b.z + perps[i + 1].y * side * (half_w + 0.18))
				_dz_beam("dz_concrete", ea, eb, 0.38, 0.85)
				var ta := Vector3(a.x + perps[i].x * side * (half_w + 0.18), a.y + 0.82, a.z + perps[i].y * side * (half_w + 0.18))
				var tb := Vector3(b.x + perps[i + 1].x * side * (half_w + 0.18), b.y + 0.82, b.z + perps[i + 1].y * side * (half_w + 0.18))
				_dz_beam("dz_metal", ta, tb, 0.07, 0.30)
				var pmid := (ta + tb) * 0.5
				_add_pitched_box_collider(Vector3(pmid.x, pmid.y - 0.32, pmid.z), Vector3(0.35, 1.0, seg_len + 0.5), yaw, atan2(b.y - a.y, seg_len))
		for i in range(span.x, span.y + 1):
			var pp := pts[i]
			for side in [-1.0, 1.0]:
				_dz_box("dz_metal_dark", Vector3(pp.x + perps[i].x * side * (half_w + 0.18), pp.y + 0.42, pp.z + perps[i].y * side * (half_w + 0.18)), Vector3(0.14, 0.85, 0.14))
		# Piers at thirds + abutments at both ends.
		var pier_indices: Array = [span.x, int(lerpf(float(span.x), float(span.y), 0.36)), int(lerpf(float(span.x), float(span.y), 0.66)), span.y]
		for pi_variant in pier_indices:
			var pi := int(pi_variant)
			var p := pts[pi]
			var bed_y := height_at(p.x, p.z)
			var top_y := p.y - 0.42
			var h := maxf(top_y - bed_y + 1.2, 1.5)
			_dz_box("dz_concrete", Vector3(p.x, top_y - h * 0.5, p.z), Vector3(width * 0.72, h, 1.6), atan2(-perps[pi].x, -perps[pi].y) + PI * 0.5)
	_enhancement_stats["desert_bridges"] = (_dz_data().get("bridges", []) as Array).size()


func _dz_build_tunnel(root: Node) -> void:
	# 0.2.54: worlds may declare several tunnels (`tunnels` list);
	# the desert's single `tunnel` dict remains the fallback.
	var tunnel_list: Array = _dz_data().get("tunnels", [])
	if tunnel_list.is_empty():
		var single: Dictionary = _dz_data().get("tunnel", {})
		if not single.is_empty():
			tunnel_list = [single]
	for tunnel_variant in tunnel_list:
		_dz_build_one_tunnel(root, tunnel_variant)


func _dz_build_one_tunnel(root: Node, tunnel: Dictionary) -> void:
	if tunnel.is_empty():
		return
	var road := _dz_find_road(String(tunnel.get("road", "")))
	if road.is_empty():
		return
	var pts := _dz_road_points(road)
	var width := _f(road, "widthM", 15.0)
	var half_w := width * 0.5
	var centre := Vector2(_f(tunnel, "x"), _f(tunnel, "z"))
	var span := _dz_span_indices(pts, centre, _f(tunnel, "halfLength", 55.0))
	var perps := _dz_point_perps(pts, bool(road.get("closed", false)))
	var opening_h := 6.4
	for i in range(span.x, span.y):
		var a := pts[i]
		var b := pts[i + 1]
		var mid := (a + b) * 0.5
		var seg_len := Vector2(b.x - a.x, b.z - a.z).length()
		var yaw := atan2(-(b.x - a.x), -(b.z - a.z))
		var roof_y := mid.y + opening_h + 0.5
		_dz_box("dz_tunnel_roof", Vector3(mid.x, roof_y, mid.z), Vector3(width + 3.4, 0.8, seg_len + 0.75), yaw)
		for side in [-1.0, 1.0]:
			var wall_pos := Vector3(mid.x + perps[i].x * side * (half_w + 0.75), mid.y + opening_h * 0.5, mid.z + perps[i].y * side * (half_w + 0.75))
			_dz_box("dz_tunnel_wall", wall_pos, Vector3(0.7, opening_h + 0.6, seg_len + 0.75), yaw)
			_add_box_collider(Vector3(wall_pos.x, mid.y + 2.2, wall_pos.z), Vector3(0.9, 5.0, seg_len + 0.75), yaw)
		if i % 2 == 0:
			_dz_box("dz_lamp", Vector3(mid.x, roof_y - 0.55, mid.z), Vector3(1.4, 0.18, 0.5), yaw)
	# Rock portals: three boxes framing the opening at both ends.
	for end_i in [span.x, span.y]:
		var p := pts[end_i]
		var yaw := atan2(-perps[end_i].x, -perps[end_i].y)
		var basis := Basis(Vector3.UP, yaw)
		for side in [-1.0, 1.0]:
			var leg: Vector3 = p + basis * Vector3(side * (half_w + 2.6), 0.0, 0.0)
			_dz_box("dz_rock", Vector3(leg.x, p.y + 4.6, leg.z), Vector3(5.4, 10.5, 2.6), yaw)
		_dz_box("dz_rock", Vector3(p.x, p.y + opening_h + 2.1, p.z), Vector3(width + 10.4, 3.6, 2.6), yaw)
		_dz_box("dz_rock", Vector3(p.x, p.y + opening_h + 5.0, p.z), Vector3(width + 5.0, 2.6, 2.2), yaw + 0.04)
	_enhancement_stats["desert_tunnel"] = true
	_enhancement_stats["forest_tunnels_built"] = int(_enhancement_stats.get("forest_tunnels_built", 0)) + 1


# --- merged static geometry ---------------------------------------------------

func _dz_material(key: String) -> Material:
	match key:
		"dz_adobe":
			return _material("dz_adobe", "cottage_rammed_sand.jpg", "cottage_rammed_sand_normal.jpg", Color(0.88, 0.74, 0.56), 0.95)
		"dz_adobe_dark":
			return _material("dz_adobe_dark", "cottage_rammed_sand.jpg", "cottage_rammed_sand_normal.jpg", Color(0.72, 0.57, 0.42), 0.95)
		"dz_plaster":
			return _material("dz_plaster", "user_plaster_white.jpg", "user_plaster_white_normal.jpg", Color(0.93, 0.89, 0.80), 0.92)
		"dz_brick":
			return _material("dz_brick", "facade_brick.jpg", "facade_brick_normal.jpg", Color(0.82, 0.66, 0.55), 0.95)
		"dz_sandstone":
			return _material("dz_sandstone", "facade_sandstone.jpg", "facade_sandstone_normal.jpg", Color(0.88, 0.76, 0.58), 0.94)
		"dz_roof_red":
			return _material("dz_roof_red", "user_roof_terracotta.jpg", "user_roof_terracotta_normal.jpg", Color(0.72, 0.42, 0.30), 0.92)
		"dz_roof_dark":
			return _material("dz_roof_dark", "roof_slate.jpg", "roof_slate_normal.jpg", Color(0.42, 0.40, 0.40), 0.9)
		"dz_roof_metal":
			return _material("dz_roof_metal", "cottage_roof_metal.jpg", "cottage_roof_metal_normal.jpg", Color(0.62, 0.50, 0.42), 0.75, 0.35)
		"dz_wood":
			return _material("dz_wood", "user_wood_deck.jpg", "user_wood_deck_normal.jpg", Color(0.62, 0.48, 0.33), 0.95)
		"dz_wood_dark":
			return _material("dz_wood_dark", "user_wood_slats_dark.jpg", "user_wood_slats_dark_normal.jpg", Color(0.45, 0.34, 0.24), 0.95)
		"dz_metal":
			return _material("dz_metal", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.66, 0.68, 0.71), 0.45, 0.7)
		"dz_metal_dark":
			return _material("dz_metal_dark", "user_black_rough.jpg", "user_black_rough_normal.jpg", Color(0.34, 0.35, 0.38), 0.6, 0.55)
		"dz_pole":
			return _material("dz_pole", "metal_pole.jpg", "metal_pole_normal.jpg", Color(0.45, 0.40, 0.34), 0.8, 0.3)
		"dz_yellow":
			return _material("dz_yellow", "user_brushed_metal.jpg", "", Color(0.88, 0.64, 0.16), 0.55, 0.25)
		"dz_rust":
			return _material("dz_rust", "rock.jpg", "", Color(0.50, 0.30, 0.20), 0.95)
		"dz_rust_light":
			return _material("dz_rust_light", "rock.jpg", "", Color(0.66, 0.47, 0.33), 0.95)
		"dz_wreck_blue":
			return _material("dz_wreck_blue", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.30, 0.42, 0.55), 0.72, 0.25)
		"dz_wreck_red":
			return _material("dz_wreck_red", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.48, 0.22, 0.16), 0.72, 0.25)
		"dz_wreck_cream":
			return _material("dz_wreck_cream", "user_brushed_metal.jpg", "user_brushed_metal_normal.jpg", Color(0.62, 0.55, 0.42), 0.75, 0.20)
		"dz_concrete":
			return _material("dz_concrete", "user_concrete_slabs.jpg", "user_concrete_slabs_normal.jpg", Color(0.70, 0.69, 0.66), 0.95)
		"dz_tunnel_wall":
			return _material("dz_tunnel_wall", "user_concrete_slabs.jpg", "", Color(0.38, 0.37, 0.36), 0.95)
		"dz_tunnel_roof":
			return _material("dz_tunnel_roof", "rock.jpg", "rock_normal.jpg", Color(0.55, 0.40, 0.32), 1.0)
		"dz_rock":
			return _material("dz_rock", "rock.jpg", "rock_normal.jpg", Color(0.68, 0.45, 0.34), 1.0)
		"gf_waterfall":
			var wf := _material("gf_waterfall", "", "", Color(0.78, 0.89, 0.96, 0.55), 0.15)
			wf.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			wf.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			return wf
		"gf_tractor_green":
			return _material("gf_tractor_green", "brushed_metal.jpg", "brushed_metal_normal.jpg", Color(0.16, 0.34, 0.14), 0.45, 0.55)
		"gf_tractor_red":
			return _material("gf_tractor_red", "brushed_metal.jpg", "brushed_metal_normal.jpg", Color(0.44, 0.12, 0.10), 0.45, 0.55)
		"gf_deer":
			return _material("gf_deer", "cafe_linen.jpg", "cafe_linen_normal.jpg", Color(0.48, 0.34, 0.21), 0.95)
		"gf_deer_belly":
			return _material("gf_deer_belly", "cafe_linen.jpg", "cafe_linen_normal.jpg", Color(0.68, 0.58, 0.44), 0.95)
		"gf_bird":
			return _material("gf_bird", "", "", Color(0.10, 0.10, 0.12), 0.9)
		"dz_glass":
			var glass := _material("dz_glass", "", "", Color(0.10, 0.15, 0.19), 0.12, 0.9)
			return glass
		"dz_white":
			return _material("dz_white", "user_plaster_white.jpg", "", Color(0.94, 0.93, 0.90), 0.6, 0.1)
		"dz_sign_blue":
			return _material("dz_sign_blue", "", "", Color(0.16, 0.34, 0.62), 0.5, 0.15)
		"dz_sign_red":
			return _material("dz_sign_red", "", "", Color(0.66, 0.20, 0.16), 0.5, 0.15)
		"dz_sign_cream":
			return _material("dz_sign_cream", "", "", Color(0.88, 0.80, 0.62), 0.55, 0.1)
		"dz_canvas":
			return _material("dz_canvas", "cafe_linen.jpg", "", Color(0.78, 0.66, 0.48), 0.95)
		"dz_dirt":
			return _material("dz_dirt", "user_dirt_cracked.jpg", "", Color(0.76, 0.62, 0.45), 1.0)
		"dz_lamp":
			var lamp := _material("dz_lamp", "", "", Color(1.0, 0.85, 0.60), 0.4)
			if not lamp.emission_enabled:
				lamp.emission_enabled = true
				lamp.emission = Color(1.0, 0.78, 0.48)
				_register_night_material(lamp, 0.0, 0.9, 2.0)
			return lamp
	return _material("dz_fallback", "user_dirt_cracked.jpg", "", Color(0.7, 0.6, 0.5), 0.95)


func _dz_unit_box() -> Mesh:
	if not _dz_prim_cache.has("box"):
		var m := BoxMesh.new()
		m.size = Vector3.ONE
		_dz_prim_cache["box"] = m
	return _dz_prim_cache["box"]


func _dz_unit_cyl(segs: int, top_ratio: float) -> Mesh:
	var key := "cyl_%d_%.2f" % [segs, top_ratio]
	if not _dz_prim_cache.has(key):
		var m := CylinderMesh.new()
		m.top_radius = 0.5 * top_ratio
		m.bottom_radius = 0.5
		m.height = 1.0
		m.radial_segments = segs
		_dz_prim_cache[key] = m
	return _dz_prim_cache[key]


func _dz_unit_sphere(segs: int, rings: int) -> Mesh:
	var key := "sph_%d_%d" % [segs, rings]
	if not _dz_prim_cache.has(key):
		var m := SphereMesh.new()
		m.radius = 0.5
		m.height = 1.0
		m.radial_segments = segs
		m.rings = rings
		_dz_prim_cache[key] = m
	return _dz_prim_cache[key]


func _dz_chunk_key(pos: Vector3, mat_key: String) -> String:
	return "%d,%d,%s" % [int(floor(pos.x / DZ_CHUNK_M)), int(floor(pos.z / DZ_CHUNK_M)), mat_key]


func _dz_prim(mat_key: String, prim: Mesh, xform: Transform3D, uv_scale: float = 0.25) -> void:
	var key := _dz_chunk_key(xform.origin, mat_key)
	if not _dz_merge.has(key):
		_dz_merge[key] = {
			"verts": PackedVector3Array(),
			"normals": PackedVector3Array(),
			"uvs": PackedVector2Array(),
			"min": Vector3(INF, INF, INF),
			"max": Vector3(-INF, -INF, -INF),
		}
	var entry: Dictionary = _dz_merge[key]
	var arrays: Array = prim.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var ev: PackedVector3Array = entry["verts"]
	var en: PackedVector3Array = entry["normals"]
	var euv: PackedVector2Array = entry["uvs"]
	var mn: Vector3 = entry["min"]
	var mx: Vector3 = entry["max"]
	var order: Array = []
	if index.is_empty():
		for i in range(verts.size()):
			order.append(i)
	else:
		for i in range(index.size()):
			order.append(int(index[i]))
	for vi_variant in order:
		var vi := int(vi_variant)
		var wp: Vector3 = xform.basis * verts[vi] + xform.origin
		ev.append(wp)
		en.append((xform.basis * normals[vi]).normalized())
		if vi < uvs.size():
			euv.append(uvs[vi] * uv_scale)
		else:
			euv.append(Vector2.ZERO)
		mn = mn.min(wp)
		mx = mx.max(wp)
	entry["verts"] = ev
	entry["normals"] = en
	entry["uvs"] = euv
	entry["min"] = mn
	entry["max"] = mx
	_dz_merge[key] = entry


func _dz_box(mat_key: String, center: Vector3, size: Vector3, yaw: float = 0.0, pitch: float = 0.0, roll: float = 0.0) -> void:
	var basis := Basis.from_euler(Vector3(pitch, yaw, roll)) * Basis.IDENTITY.scaled(size)
	_dz_prim(mat_key, _dz_unit_box(), Transform3D(basis, center), maxf(size.x, maxf(size.y, size.z)) * 0.25)


func _dz_lbox(mat_key: String, origin: Vector3, basis: Basis, local_center: Vector3, size: Vector3, local_yaw: float = 0.0, local_pitch: float = 0.0, local_roll: float = 0.0) -> void:
	var world_basis := basis * Basis.from_euler(Vector3(local_pitch, local_yaw, local_roll)) * Basis.IDENTITY.scaled(size)
	_dz_prim(mat_key, _dz_unit_box(), Transform3D(world_basis, origin + basis * local_center), maxf(size.x, maxf(size.y, size.z)) * 0.25)


func _dz_lcyl(mat_key: String, origin: Vector3, basis: Basis, local_center: Vector3, radius: float, height: float, local_yaw: float = 0.0, local_pitch: float = 0.0, local_roll: float = 0.0, top_ratio: float = 1.0, segs: int = 12) -> void:
	var world_basis := basis * Basis.from_euler(Vector3(local_pitch, local_yaw, local_roll)) * Basis.IDENTITY.scaled(Vector3(radius * 2.0, height, radius * 2.0))
	_dz_prim(mat_key, _dz_unit_cyl(segs, top_ratio), Transform3D(world_basis, origin + basis * local_center), maxf(radius * 2.0, height) * 0.25)


func _dz_lsphere(mat_key: String, origin: Vector3, basis: Basis, local_center: Vector3, radii: Vector3, local_yaw: float = 0.0) -> void:
	var world_basis := basis * Basis.from_euler(Vector3(0.0, local_yaw, 0.0)) * Basis.IDENTITY.scaled(radii * 2.0)
	_dz_prim(mat_key, _dz_unit_sphere(12, 8), Transform3D(world_basis, origin + basis * local_center), radii.x * 0.5)


func _dz_beam(mat_key: String, a: Vector3, b: Vector3, thick_x: float, thick_y: float) -> void:
	var dir := b - a
	var len := dir.length()
	if len < 0.02:
		return
	var up := Vector3.UP
	if absf(dir.normalized().dot(Vector3.UP)) > 0.97:
		up = Vector3.RIGHT
	var basis := Basis.looking_at(dir.normalized(), up) * Basis.IDENTITY.scaled(Vector3(thick_x, thick_y, len))
	_dz_prim(mat_key, _dz_unit_box(), Transform3D(basis, (a + b) * 0.5), len * 0.2)


func _dz_flush_merge(root: Node) -> int:
	var count := 0
	for key_variant in _dz_merge.keys():
		var key := String(key_variant)
		var entry: Dictionary = _dz_merge[key]
		var verts: PackedVector3Array = entry["verts"]
		if verts.is_empty():
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = entry["normals"]
		arrays[Mesh.ARRAY_TEX_UV] = entry["uvs"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat_key := key.rsplit(",", true, 1)[1]
		var instance := _mesh_instance(root, mesh, _dz_material(mat_key), Transform3D.IDENTITY, "DzMerged_" + mat_key, true)
		var mn: Vector3 = entry["min"]
		var mx: Vector3 = entry["max"]
		var aabb := AABB(mn, mx - mn)
		instance.custom_aabb = aabb
		_stream_chunks.append({
			"node": instance,
			"centre": aabb.get_center(),
			"radius": aabb.size.length() * 0.5,
			"hidden": false,
			"sector_hidden_0237": false,
		})
		count += 1
	_dz_merge.clear()
	return count


func _dz_pipe_beam(mat_key: String, a: Vector3, b: Vector3, radius: float) -> void:
	var dir := b - a
	var len := dir.length()
	if len < 0.02:
		return
	var up := Vector3.UP
	if absf(dir.normalized().dot(Vector3.UP)) > 0.95:
		up = Vector3.RIGHT
	var basis := Basis.looking_at(dir.normalized(), up) * Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)) * Basis.IDENTITY.scaled(Vector3(radius * 2.0, len, radius * 2.0))
	_dz_prim(mat_key, _dz_unit_cyl(10, 1.0), Transform3D(basis, (a + b) * 0.5), len * 0.2)


func _dz_collider(origin: Vector3, basis: Basis, yaw: float, local_center: Vector3, size: Vector3) -> void:
	_add_box_collider(origin + basis * local_center, size, yaw)


func _dz_gable_roof(mat_key: String, origin: Vector3, basis: Basis, y: float, w: float, d: float, rise: float, overhang: float = 0.5) -> void:
	var half_d := d * 0.5 + overhang
	var slope_len := sqrt(half_d * half_d + rise * rise) + 0.15
	var ang := atan2(rise, half_d)
	for side in [-1.0, 1.0]:
		_dz_lbox(mat_key, origin, basis, Vector3(0.0, y + rise * 0.5, side * half_d * 0.5), Vector3(w + overhang * 2.0, 0.16, slope_len), 0.0, side * ang, 0.0)
	_dz_lbox(mat_key, origin, basis, Vector3(0.0, y + rise + 0.02, 0.0), Vector3(w + overhang * 2.0, 0.14, 0.5))


func _dz_flat_roof(mat_key: String, origin: Vector3, basis: Basis, y: float, w: float, d: float, parapet: float = 0.45) -> void:
	_dz_lbox(mat_key, origin, basis, Vector3(0.0, y + 0.10, 0.0), Vector3(w + 0.5, 0.22, d + 0.5))
	if parapet > 0.01:
		_dz_lbox(mat_key, origin, basis, Vector3(0.0, y + 0.22 + parapet * 0.5, -d * 0.5 - 0.13), Vector3(w + 0.5, parapet, 0.24))
		_dz_lbox(mat_key, origin, basis, Vector3(0.0, y + 0.22 + parapet * 0.5, d * 0.5 + 0.13), Vector3(w + 0.5, parapet, 0.24))
		_dz_lbox(mat_key, origin, basis, Vector3(-w * 0.5 - 0.13, y + 0.22 + parapet * 0.5, 0.0), Vector3(0.24, parapet, d + 0.5))
		_dz_lbox(mat_key, origin, basis, Vector3(w * 0.5 + 0.13, y + 0.22 + parapet * 0.5, 0.0), Vector3(0.24, parapet, d + 0.5))


func _dz_building(origin: Vector3, basis: Basis, yaw: float, w: float, d: float, h: float, wall: String, roof: String, gable: bool, windows: bool = true) -> void:
	_dz_lbox("dz_concrete", origin, basis, Vector3(0.0, 0.02, 0.0), Vector3(w + 0.5, 0.85, d + 0.5))
	_dz_lbox(wall, origin, basis, Vector3(0.0, h * 0.5, 0.0), Vector3(w, h, d))
	if gable:
		_dz_gable_roof(roof, origin, basis, h, w, d, maxf(1.1, d * 0.24))
	else:
		_dz_flat_roof(roof, origin, basis, h, w, d)
	if windows:
		var win_y := clampf(h * 0.55, 1.4, 3.2)
		var n := maxi(2, int(w / 3.4))
		for i in range(n):
			var fx := -w * 0.5 + w * float(i + 1) / float(n + 1)
			_dz_lbox("dz_glass", origin, basis, Vector3(fx, win_y, -d * 0.5 - 0.03), Vector3(1.15, 1.05, 0.08))
			_dz_lbox("dz_glass", origin, basis, Vector3(fx, win_y, d * 0.5 + 0.03), Vector3(1.15, 1.05, 0.08))
		_dz_lbox("dz_wood_dark", origin, basis, Vector3(0.0, 1.05, -d * 0.5 - 0.03), Vector3(1.05, 2.1, 0.08))
	_dz_collider(origin, basis, yaw, Vector3(0.0, 1.3, 0.0), Vector3(w, 2.6, d))


func _dz_setup_dynamic_materials() -> void:
	_dz_beacon_material = StandardMaterial3D.new()
	_dz_beacon_material.albedo_color = Color(0.9, 0.16, 0.12)
	_dz_beacon_material.emission_enabled = true
	_dz_beacon_material.emission = Color(1.0, 0.18, 0.12)
	_dz_beacon_material.emission_energy_multiplier = 2.4
	_dz_flare_material = StandardMaterial3D.new()
	_dz_flare_material.albedo_color = Color(1.0, 0.55, 0.2)
	_dz_flare_material.emission_enabled = true
	_dz_flare_material.emission = Color(1.0, 0.5, 0.16)
	_dz_flare_material.emission_energy_multiplier = 3.2


func _dz_build_fence(o: Vector3, basis: Basis, yaw: float, w: float) -> void:
	# 0.2.51: terrain-following wooden fence.  Every post is
	# planted on its own ground height with a little weathered
	# height/tilt jitter, and the rails are individual planks
	# sloped span-by-span between the posts, so a long fence
	# hugs a hillside instead of floating as one rigid slab.
	# Short town/yard fences get three solid planks; long
	# ranch runs get two planks, a top wire strand and
	# diagonal end braces.  Kept as its own function: the
	# inline match-branch version shadowed the structures
	# ground-Y local and Godot rejected the whole script.
	var fence_is_ranch: bool = w >= 18.0
	var fence_spans: int = maxi(1, int(round(w / 2.4)))
	var fence_side: Vector3 = basis * Vector3(0.0, 0.0, 0.105)
	var fence_bases: Array = []
	for fence_pi in range(fence_spans + 1):
		var fence_lx: float = -w * 0.5 + w * float(fence_pi) / float(fence_spans)
		var fence_wp: Vector3 = o + basis * Vector3(fence_lx, 0.0, 0.0)
		var fence_ground_y: float = height_at(fence_wp.x, fence_wp.z)
		var fence_jitter: float = _hash01(int(round(fence_wp.x * 7.0)), int(round(fence_wp.z * 7.0)))
		var fence_post_h: float = 1.08 + (fence_jitter - 0.5) * 0.10
		var fence_tilt: float = (fence_jitter - 0.5) * 0.07
		_dz_box("dz_wood_dark", Vector3(fence_wp.x, fence_ground_y + fence_post_h * 0.5 - 0.07, fence_wp.z), Vector3(0.16, fence_post_h, 0.16), yaw, fence_tilt, fence_tilt * 0.6)
		fence_bases.append(Vector3(fence_wp.x, fence_ground_y, fence_wp.z))
	var fence_levels: Array = []
	if fence_is_ranch:
		fence_levels.append(0.55)
		fence_levels.append(0.92)
	else:
		fence_levels.append(0.32)
		fence_levels.append(0.64)
		fence_levels.append(0.96)
	for fence_si in range(fence_spans):
		var fence_ba: Vector3 = fence_bases[fence_si]
		var fence_bb: Vector3 = fence_bases[fence_si + 1]
		for fence_lvl_variant in fence_levels:
			var fence_lvl: float = float(fence_lvl_variant)
			_dz_beam("dz_wood", fence_ba + fence_side + Vector3(0.0, fence_lvl, 0.0), fence_bb + fence_side + Vector3(0.0, fence_lvl, 0.0), 0.05, 0.15)
		if fence_is_ranch:
			_dz_beam("dz_metal_dark", fence_ba + Vector3(0.0, 1.10, 0.0), fence_bb + Vector3(0.0, 1.10, 0.0), 0.025, 0.025)
			if fence_si == 0 or fence_si == fence_spans - 1:
				_dz_beam("dz_wood_dark", fence_ba + Vector3(0.0, 0.06, 0.0), fence_bb + Vector3(0.0, 0.95, 0.0), 0.07, 0.07)
	_dz_collider(o, basis, yaw, Vector3(0.0, 0.5, 0.0), Vector3(w, 1.0, 0.3))
	_enhancement_stats["desert_fences_0251"] = int(_enhancement_stats.get("desert_fences_0251", 0)) + 1


func _build_desert_structures() -> void:
	var root := Node3D.new()
	root.name = "DesertStructures"
	add_child(root)
	var anim_root := Node3D.new()
	anim_root.name = "DesertAnimated"
	root.add_child(anim_root)
	_dz_setup_dynamic_materials()
	var dz := _dz_data()
	var structures: Array = dz.get("structures", [])
	for s_variant in structures:
		_dz_structure(anim_root, s_variant)
	var pipe_road_gaps_0253 := 0
	for pipe_variant in dz.get("pipes", []):
		var pipe: Array = pipe_variant
		if pipe.size() < 4:
			continue
		var a := Vector3(float(pipe[0]), 0.0, float(pipe[1]))
		var b := Vector3(float(pipe[2]), 0.0, float(pipe[3]))
		var steps := maxi(1, int(Vector2(b.x - a.x, b.z - a.z).length() / 14.0))
		var prev := Vector3(a.x, height_at(a.x, a.z) + 1.15, a.z)
		for si in range(1, steps + 1):
			var t := float(si) / float(steps)
			var p := a.lerp(b, t)
			var top := Vector3(p.x, height_at(p.x, p.z) + 1.15, p.z)
			var pipe_mid3 := (prev + top) * 0.5
			var pipe_clear := minf(_road_clearance_xz(prev), minf(_road_clearance_xz(top), _road_clearance_xz(pipe_mid3)))
			if pipe_clear < 0.25:
				pipe_road_gaps_0253 += 1
				prev = top
				continue
			_dz_pipe_beam("dz_rust_light", prev, top, 0.30)
			if _road_clearance_xz(top) >= 0.45:
				_dz_beam("dz_metal_dark", Vector3(p.x, height_at(p.x, p.z) - 0.2, p.z), top, 0.16, 0.16)
			var pipe_flat := Vector2(top.x - prev.x, top.z - prev.z)
			var pipe_len := pipe_flat.length()
			if pipe_len > 0.5:
				var pipe_mid := (prev + top) * 0.5
				_add_pitched_box_collider(pipe_mid, Vector3(0.75, 0.85, pipe_len + 0.4), atan2(-pipe_flat.x, -pipe_flat.y), atan2(top.y - prev.y, pipe_len))
			prev = top
	for rail_variant in dz.get("guardrails", []):
		var rail: Array = rail_variant
		if rail.size() < 4:
			continue
		var a := Vector3(float(rail[0]), 0.0, float(rail[1]))
		var b := Vector3(float(rail[2]), 0.0, float(rail[3]))
		var ay := height_at(a.x, a.z)
		var by := height_at(b.x, b.z)
		_dz_beam("dz_metal", Vector3(a.x, ay + 0.78, a.z), Vector3(b.x, by + 0.78, b.z), 0.07, 0.30)
		var len2d := Vector2(b.x - a.x, b.z - a.z).length()
		var posts := maxi(2, int(len2d / 4.5))
		for pi in range(posts + 1):
			var p := a.lerp(b, float(pi) / float(posts))
			var py := height_at(p.x, p.z)
			_dz_box("dz_metal_dark", Vector3(p.x, py + 0.4, p.z), Vector3(0.14, 0.85, 0.14))
		var mid := (a + b) * 0.5
		_add_box_collider(Vector3(mid.x, (ay + by) * 0.5 + 0.5, mid.z), Vector3(0.4, 1.1, len2d), atan2(-(b.x - a.x), -(b.z - a.z)))
	var line: Array = dz.get("poleLine", [])
	for li in range(line.size() - 1):
		var pa: Array = line[li]
		var pb: Array = line[li + 1]
		var va := Vector2(float(pa[0]), float(pa[1]))
		var vb := Vector2(float(pb[0]), float(pb[1]))
		var dist := (vb - va).length()
		if dist < 5.0 or dist > 75.0:
			continue
		var dir := (vb - va) / dist
		var perp := Vector2(-dir.y, dir.x)
		for off in [-1.8, 0.0, 1.8]:
			var top_off := 11.2 if absf(off) > 0.01 else 11.6
			var a3 := Vector3(va.x + perp.x * off, height_at(va.x, va.y) + top_off, va.y + perp.y * off)
			var b3 := Vector3(vb.x + perp.x * off, height_at(vb.x, vb.y) + top_off, vb.y + perp.y * off)
			var wire_prev := a3
			for wi in range(1, 4):
				var wt := float(wi) / 4.0
				var wp := a3.lerp(b3, wt)
				wp.y -= sin(wt * PI) * (dist * 0.03 + 0.5)
				_dz_beam("dz_metal_dark", wire_prev, wp, 0.075, 0.075)
				wire_prev = wp
			_dz_beam("dz_metal_dark", wire_prev, b3, 0.075, 0.075)
	var merged := _dz_flush_merge(root)
	_enhancement_stats["desert_structures"] = structures.size()
	_enhancement_stats["desert_merged_chunks"] = merged
	_enhancement_stats["desert_poles"] = line.size()
	_enhancement_stats["desert_pipe_road_gaps_0253"] = pipe_road_gaps_0253


func _dz_structure(anim_root: Node3D, s: Dictionary) -> void:
	var kind := String(s.get("kind", ""))
	var x := _f(s, "x")
	var z := _f(s, "z")
	var yaw := _f(s, "yaw")
	var w := _f(s, "w", 6.0)
	var d := _f(s, "d", 6.0)
	var h := _f(s, "h", 4.0)
	var basis := Basis(Vector3.UP, yaw)
	if kind == "conveyor":
		var x2 := _f(s, "x2", x)
		var z2 := _f(s, "z2", z)
		var a := Vector3(x, height_at(x, z) + h, z)
		var b := Vector3(x2, height_at(x2, z2) + 1.6, z2)
		_dz_beam("dz_yellow", a, b, 2.0, 0.7)
		var steps := int(Vector2(x2 - x, z2 - z).length() / 22.0)
		for ci in range(1, maxi(steps, 1)):
			var p := a.lerp(b, float(ci) / float(maxi(steps, 1)))
			if _road_clearance_xz(p) < 1.0:
				continue
			_dz_beam("dz_metal_dark", Vector3(p.x, height_at(p.x, p.z) - 0.3, p.z), p + Vector3(0, -0.3, 0), 0.35, 0.35)
			var support_ground := height_at(p.x, p.z) - 0.3
			var support_h := maxf(p.y - 0.3 - support_ground, 1.0)
			_add_cylinder_collider(Vector3(p.x, support_ground + support_h * 0.5, p.z), 0.32, support_h)
		return
	var big_kinds := ["gas_station", "garage", "motel", "diner", "warehouse", "church", "house", "ranch_house", "barn", "oasis_house", "office", "shed", "roadstop", "stage", "crusher", "station_ruin"]
	var gy := _dz_footprint_y(x, z, w, d, yaw) if kind in big_kinds else _dz_ground_y(x, z, 0.04)
	var o := Vector3(x, gy, z)
	var hash_pick := int(absf(x) * 3.0 + absf(z) * 7.0) % 3
	if _is_forest and _gf_structure_kind(kind, o, basis, w, d, h, hash_pick):
		return
	match kind:
		"gas_station":
			_dz_building(o, basis, yaw, w, d, h, "dz_plaster", "dz_roof_metal", false)
			for cx in [-0.35, 0.35]:
				_dz_lcyl("dz_metal", o, basis, Vector3(cx * w, 2.4, -d * 0.5 - 4.6), 0.16, 4.8)
				_dz_lbox("dz_metal_dark", o, basis, Vector3(cx * w * 0.6, 0.75, -d * 0.5 - 3.2), Vector3(0.7, 1.5, 0.5))
				_dz_lbox("dz_sign_red", o, basis, Vector3(cx * w * 0.6, 1.65, -d * 0.5 - 3.2), Vector3(0.72, 0.3, 0.52))
			_dz_lbox("dz_roof_red", o, basis, Vector3(0.0, 4.9, -d * 0.5 - 4.6), Vector3(w * 0.95, 0.25, 7.0))
			_dz_lcyl("dz_pole", o, basis, Vector3(w * 0.5 + 3.0, 4.0, -d * 0.5 - 6.0), 0.14, 8.0)
			_dz_lbox("dz_sign_red", o, basis, Vector3(w * 0.5 + 3.0, 8.3, -d * 0.5 - 6.0), Vector3(3.2, 1.1, 0.2))
		"garage":
			_dz_building(o, basis, yaw, w, d, h, "dz_sandstone", "dz_roof_metal", false, false)
			_dz_lbox("dz_metal_dark", o, basis, Vector3(-w * 0.2, 1.7, -d * 0.5 - 0.04), Vector3(5.4, 3.4, 0.1))
			_dz_lbox("dz_metal_dark", o, basis, Vector3(w * 0.25, 1.7, -d * 0.5 - 0.04), Vector3(5.4, 3.4, 0.1))
			_dz_lbox("dz_sign_cream", o, basis, Vector3(0.0, h + 0.9, -d * 0.5 - 0.2), Vector3(w * 0.6, 1.0, 0.18))
		"motel":
			_dz_building(o, basis, yaw, w, d, h, "dz_plaster", "dz_roof_red", false, false)
			_dz_lbox("dz_concrete", o, basis, Vector3(0.0, 3.1, -d * 0.5 - 0.85), Vector3(w, 0.18, 1.7))
			_dz_lbox("dz_metal_dark", o, basis, Vector3(0.0, 3.75, -d * 0.5 - 1.65), Vector3(w, 0.5, 0.06))
			for i in range(6):
				var fx := -w * 0.5 + w * float(i + 1) / 7.0
				_dz_lbox("dz_wood_dark", o, basis, Vector3(fx, 1.05, -d * 0.5 - 0.04), Vector3(1.0, 2.1, 0.08))
				_dz_lbox("dz_wood_dark", o, basis, Vector3(fx, 4.2, -d * 0.5 - 0.04), Vector3(1.0, 2.1, 0.08))
			_dz_lcyl("dz_pole", o, basis, Vector3(w * 0.5 + 4.0, 4.5, -d * 0.5 - 4.0), 0.15, 9.0)
			_dz_lbox("dz_sign_blue", o, basis, Vector3(w * 0.5 + 4.0, 9.4, -d * 0.5 - 4.0), Vector3(3.6, 1.3, 0.2))
		"diner":
			_dz_building(o, basis, yaw, w, d, h, "dz_metal", "dz_roof_red", false, false)
			_dz_lbox("dz_glass", o, basis, Vector3(0.0, 1.9, -d * 0.5 - 0.04), Vector3(w * 0.85, 1.7, 0.08))
			_dz_lbox("dz_sign_red", o, basis, Vector3(0.0, h + 1.0, -d * 0.5 - 0.2), Vector3(w * 0.5, 1.1, 0.2))
		"warehouse":
			_dz_building(o, basis, yaw, w, d, h, "dz_adobe_dark", "dz_roof_metal", true, false)
			_dz_lbox("dz_metal_dark", o, basis, Vector3(0.0, 2.0, -d * 0.5 - 0.04), Vector3(6.0, 4.0, 0.1))
		"office", "roadstop":
			_dz_building(o, basis, yaw, w, d, h, "dz_sandstone", "dz_roof_dark", false)
			if kind == "roadstop":
				_dz_lbox("dz_roof_red", o, basis, Vector3(0.0, 3.0, -d * 0.5 - 1.6), Vector3(w * 0.8, 0.15, 3.2))
				_dz_lcyl("dz_pole", o, basis, Vector3(-w * 0.5 - 2.5, 3.4, -d * 0.5 - 3.0), 0.13, 6.8)
				_dz_lbox("dz_sign_cream", o, basis, Vector3(-w * 0.5 - 2.5, 7.0, -d * 0.5 - 3.0), Vector3(2.8, 1.0, 0.18))
		"shed":
			_dz_building(o, basis, yaw, w, d, h, "dz_wood", "dz_roof_metal", false, false)
		"church":
			_dz_building(o, basis, yaw, w, d, h, "dz_plaster", "dz_roof_dark", true, false)
			var tower_top := h + 3.4
			_dz_lbox("dz_plaster", o, basis, Vector3(w * 0.32, tower_top * 0.5, -d * 0.5 + 1.2), Vector3(3.2, tower_top, 3.2))
			_dz_lcyl("dz_roof_dark", o, basis, Vector3(w * 0.32, tower_top + 1.3, -d * 0.5 + 1.2), 2.3, 2.6, PI * 0.25, 0.0, 0.0, 0.02, 4)
			_dz_lbox("dz_wood_dark", o, basis, Vector3(w * 0.32, tower_top + 3.1, -d * 0.5 + 1.2), Vector3(0.16, 1.4, 0.16))
			_dz_lbox("dz_wood_dark", o, basis, Vector3(w * 0.32, tower_top + 3.25, -d * 0.5 + 1.2), Vector3(0.8, 0.16, 0.16))
			_dz_lbox("dz_glass", o, basis, Vector3(w * 0.32, tower_top - 1.3, -d * 0.5 - 0.44), Vector3(0.9, 1.7, 0.08))
			_dz_lbox("dz_wood_dark", o, basis, Vector3(0.0, 1.3, -d * 0.5 - 0.04), Vector3(1.6, 2.6, 0.08))
		"house":
			var wall := "dz_adobe" if hash_pick != 0 else "dz_plaster"
			var roof := "dz_roof_red" if hash_pick != 1 else "dz_roof_dark"
			_dz_building(o, basis, yaw, w, d, h, wall, roof, true)
		"ranch_house":
			_dz_building(o, basis, yaw, w, d, h, "dz_plaster", "dz_roof_red", true)
			for px in [-0.4, 0.0, 0.4]:
				_dz_lcyl("dz_wood", o, basis, Vector3(px * w, 1.3, -d * 0.5 - 2.0), 0.09, 2.6)
			_dz_lbox("dz_roof_red", o, basis, Vector3(0.0, 2.75, -d * 0.5 - 1.05), Vector3(w * 0.95, 0.14, 2.3), 0.0, 0.10, 0.0)
		"barn":
			_dz_building(o, basis, yaw, w, d, h, "dz_brick", "dz_roof_dark", true, false)
			_dz_lbox("dz_wood_dark", o, basis, Vector3(0.0, 2.0, -d * 0.5 - 0.04), Vector3(4.4, 4.0, 0.1))
			_dz_lbox("dz_wood_dark", o, basis, Vector3(0.0, h - 0.9, -d * 0.5 - 0.04), Vector3(1.4, 1.2, 0.08))
		"oasis_house":
			_dz_building(o, basis, yaw, w, d, h, "dz_plaster", "dz_roof_red", false)
			_dz_lbox("dz_canvas", o, basis, Vector3(0.0, 2.6, -d * 0.5 - 1.3), Vector3(w * 0.7, 0.1, 2.4), 0.0, 0.12, 0.0)
		"water_tower":
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var foot: Vector3 = o + basis * Vector3(sx * w * 0.42, 0.0, sz * d * 0.42)
					var topc: Vector3 = o + basis * Vector3(sx * w * 0.26, h - 4.6, sz * d * 0.26)
					_dz_beam("dz_metal_dark", foot, topc, 0.22, 0.22)
			for lv in [0.35, 0.7]:
				var y: float = (h - 4.6) * lv
				var spread := lerpf(w * 0.42, w * 0.26, lv)
				_dz_lbox("dz_metal_dark", o, basis, Vector3(0.0, y, -spread), Vector3(spread * 2.0, 0.14, 0.14))
				_dz_lbox("dz_metal_dark", o, basis, Vector3(0.0, y, spread), Vector3(spread * 2.0, 0.14, 0.14))
				_dz_lbox("dz_metal_dark", o, basis, Vector3(-spread, y, 0.0), Vector3(0.14, 0.14, spread * 2.0))
				_dz_lbox("dz_metal_dark", o, basis, Vector3(spread, y, 0.0), Vector3(0.14, 0.14, spread * 2.0))
			_dz_lcyl("dz_metal", o, basis, Vector3(0.0, h - 2.2, 0.0), w * 0.5, 4.6, 0.0, 0.0, 0.0, 1.0, 16)
			_dz_lcyl("dz_roof_red", o, basis, Vector3(0.0, h + 0.75, 0.0), w * 0.56, 1.5, 0.0, 0.0, 0.0, 0.05, 16)
			_dz_collider(o, basis, yaw, Vector3(0.0, 1.2, 0.0), Vector3(w * 0.7, 2.4, d * 0.7))
		"stall":
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_dz_lcyl("dz_wood", o, basis, Vector3(sx * w * 0.45, h * 0.45, sz * d * 0.45), 0.07, h * 0.9)
			_dz_lbox("dz_canvas", o, basis, Vector3(0.0, h, 0.0), Vector3(w + 0.7, 0.1, d + 0.7), 0.0, 0.16, 0.0)
			_dz_lbox("dz_wood", o, basis, Vector3(0.0, 0.55, -d * 0.3), Vector3(w * 0.9, 1.1, d * 0.45))
			_dz_collider(o, basis, yaw, Vector3(0.0, 0.55, -d * 0.3), Vector3(w * 0.9, 1.1, d * 0.45))
		"stage":
			_dz_lbox("dz_wood", o, basis, Vector3(0.0, 0.6, 0.0), Vector3(w, 1.2, d))
			_dz_lbox("dz_wood_dark", o, basis, Vector3(0.0, h * 0.55, d * 0.5 - 0.3), Vector3(w, h * 1.1, 0.3))
			for sx in [-1.0, 1.0]:
				_dz_lcyl("dz_wood", o, basis, Vector3(sx * w * 0.47, h * 0.6, -d * 0.42), 0.1, h * 1.2)
			_dz_lbox("dz_canvas", o, basis, Vector3(0.0, h + 1.2, 0.0), Vector3(w + 1.0, 0.14, d + 1.2), 0.0, 0.1, 0.0)
			_dz_collider(o, basis, yaw, Vector3(0.0, 0.7, 0.0), Vector3(w, 1.4, d))
		"fence":
			_dz_build_fence(o, basis, yaw, w)
		"crate":
			_dz_lbox("dz_wood", o, basis, Vector3(0.0, 0.6, 0.0), Vector3(1.2, 1.2, 1.2))
			if hash_pick != 0:
				_dz_lbox("dz_wood", o, basis, Vector3(0.75, 0.45, 0.5), Vector3(0.9, 0.9, 0.9), 0.4)
			if hash_pick == 2:
				_dz_lbox("dz_wood_dark", o, basis, Vector3(-0.15, 1.55, 0.1), Vector3(0.85, 0.85, 0.85), -0.3)
			_dz_collider(o, basis, yaw, Vector3(0.0, 0.65, 0.0), Vector3(1.7, 1.3, 1.7))
		"barrel_group":
			var spots := [Vector3.ZERO, Vector3(0.65, 0, 0.3), Vector3(0.25, 0, -0.6), Vector3(-0.6, 0, -0.35)]
			for bi in range(3 + hash_pick):
				var bp: Vector3 = spots[bi % spots.size()]
				var bm := "dz_rust" if (bi + hash_pick) % 2 == 0 else "dz_metal_dark"
				_dz_lcyl(bm, o, basis, Vector3(bp.x, 0.45, bp.z), 0.30, 0.9, 0.0, 0.0, 0.0, 1.0, 10)
			_dz_collider(o, basis, yaw, Vector3(0.0, 0.5, 0.0), Vector3(1.8, 0.95, 1.8))
		"tank_small":
			_dz_lcyl("dz_rust_light", o, basis, Vector3(0.0, 0.85, 0.0), 0.55, 1.9, 0.0, 0.0, PI * 0.5, 1.0, 12)
			for fx in [-0.6, 0.6]:
				_dz_lbox("dz_metal_dark", o, basis, Vector3(fx, 0.25, 0.0), Vector3(0.14, 0.5, 0.8))
			_dz_collider(o, basis, yaw, Vector3(0.0, 0.8, 0.0), Vector3(1.9, 1.6, 1.1))
		"town_pole":
			_dz_lcyl("dz_pole", o, basis, Vector3(0.0, h * 0.5, 0.0), 0.09, h, 0.0, 0.0, 0.0, 0.7, 8)
			_dz_lbox("dz_pole", o, basis, Vector3(0.8, h - 0.15, 0.0), Vector3(1.7, 0.09, 0.09))
			_dz_lbox("dz_lamp", o, basis, Vector3(1.55, h - 0.3, 0.0), Vector3(0.55, 0.14, 0.28))
			_add_cylinder_collider(Vector3(x, gy + 1.4, z), 0.16, 2.8)
		"power_pole":
			_dz_lcyl("dz_pole", o, basis, Vector3(0.0, h * 0.5, 0.0), 0.19, h, 0.0, 0.0, 0.0, 0.65, 8)
			_dz_lbox("dz_pole", o, basis, Vector3(0.0, h - 0.7, 0.0), Vector3(4.2, 0.18, 0.18))
			_dz_lbox("dz_pole", o, basis, Vector3(0.0, h - 1.7, 0.0), Vector3(3.0, 0.15, 0.15))
			_add_cylinder_collider(Vector3(x, gy + 1.5, z), 0.26, 3.0)
		"crusher":
			_dz_lbox("dz_concrete", o, basis, Vector3(0.0, h * 0.5, 0.0), Vector3(w, h, d))
			_dz_lbox("dz_metal", o, basis, Vector3(0.0, h + 1.5, 0.0), Vector3(w * 0.6, 3.0, d * 0.6))
			_dz_lcyl("dz_yellow", o, basis, Vector3(0.0, h * 0.72, -d * 0.5 - 1.6), 2.2, 3.0, 0.0, 0.0, 0.0, 0.3, 12)
			_dz_lbox("dz_metal_dark", o, basis, Vector3(w * 0.3, 1.6, -d * 0.5 - 0.05), Vector3(3.4, 3.2, 0.12))
			_dz_collider(o, basis, yaw, Vector3(0.0, 1.4, 0.0), Vector3(w, 2.8, d))
		"silo":
			_dz_lcyl("dz_metal", o, basis, Vector3(0.0, h * 0.5, 0.0), w * 0.5, h, 0.0, 0.0, 0.0, 1.0, 18)
			_dz_lsphere("dz_metal", o, basis, Vector3(0.0, h, 0.0), Vector3(w * 0.5, w * 0.26, w * 0.5))
			_add_cylinder_collider(Vector3(x, gy + 1.5, z), w * 0.52, 3.0)
		"excavator":
			for sx in [-1.0, 1.0]:
				_dz_lbox("dz_metal_dark", o, basis, Vector3(sx * 1.15, 0.5, 0.0), Vector3(0.8, 1.0, 5.2))
			_dz_lbox("dz_yellow", o, basis, Vector3(0.0, 1.85, 0.4), Vector3(3.0, 1.7, 4.6))
			_dz_lbox("dz_glass", o, basis, Vector3(-0.9, 3.3, -0.6), Vector3(1.3, 1.6, 1.5))
			_dz_lbox("dz_yellow", o, basis, Vector3(0.55, 4.4, -3.0), Vector3(0.55, 0.7, 6.4), 0.0, 0.72, 0.0)
			_dz_lbox("dz_yellow", o, basis, Vector3(0.55, 3.9, -6.3), Vector3(0.45, 0.55, 3.6), 0.0, -0.5, 0.0)
			_dz_lbox("dz_metal_dark", o, basis, Vector3(0.55, 1.0, -7.6), Vector3(1.5, 1.1, 1.1), 0.0, 0.5, 0.0)
			_dz_collider(o, basis, yaw, Vector3(0.0, 1.4, -0.6), Vector3(3.2, 2.8, 7.0))
		"dumptruck":
			_dz_lbox("dz_metal_dark", o, basis, Vector3(0.0, 0.85, 0.0), Vector3(2.5, 0.5, 8.6))
			_dz_lbox("dz_yellow", o, basis, Vector3(0.0, 2.0, -3.4), Vector3(2.5, 1.9, 1.9))
			_dz_lbox("dz_glass", o, basis, Vector3(0.0, 2.45, -4.15), Vector3(2.2, 0.9, 0.4))
			_dz_lbox("dz_yellow", o, basis, Vector3(0.0, 1.55, 1.1), Vector3(2.7, 0.3, 6.2))
			for sx in [-1.0, 1.0]:
				_dz_lbox("dz_yellow", o, basis, Vector3(sx * 1.32, 2.2, 1.1), Vector3(0.09, 1.3, 6.2))
				for wz in [-3.1, 2.2, 3.5]:
					_dz_lcyl("dz_metal_dark", o, basis, Vector3(sx * 1.25, 0.62, wz), 0.62, 0.45, 0.0, 0.0, PI * 0.5, 1.0, 12)
			_dz_lbox("dz_yellow", o, basis, Vector3(0.0, 2.2, 4.15), Vector3(2.7, 1.3, 0.09))
			_dz_collider(o, basis, yaw, Vector3(0.0, 1.3, 0.0), Vector3(2.7, 2.6, 8.6))
		"loader":
			_dz_lbox("dz_yellow", o, basis, Vector3(0.0, 1.7, 0.8), Vector3(2.7, 1.8, 5.4))
			_dz_lbox("dz_glass", o, basis, Vector3(0.0, 3.3, 0.6), Vector3(1.9, 1.7, 1.9))
			for sx in [-1.0, 1.0]:
				for wz in [-2.0, 2.4]:
					_dz_lcyl("dz_metal_dark", o, basis, Vector3(sx * 1.35, 0.85, wz), 0.85, 0.6, 0.0, 0.0, PI * 0.5, 1.0, 14)
				_dz_lbox("dz_yellow", o, basis, Vector3(sx * 1.1, 1.8, -3.3), Vector3(0.4, 0.6, 3.4), 0.0, 0.35, 0.0)
			_dz_lbox("dz_metal_dark", o, basis, Vector3(0.0, 0.9, -5.1), Vector3(3.2, 1.3, 1.2), 0.0, 0.45, 0.0)
			_dz_collider(o, basis, yaw, Vector3(0.0, 1.3, -0.5), Vector3(3.0, 2.6, 8.0))
		"container":
			var cm: String = ["dz_rust_light", "dz_sign_blue", "dz_metal"][hash_pick]
			_dz_lbox(cm, o, basis, Vector3(0.0, 1.3, 0.0), Vector3(w, 2.6, d))
			_dz_lbox("dz_metal_dark", o, basis, Vector3(0.0, 2.68, 0.0), Vector3(w + 0.1, 0.14, d + 0.1))
			_dz_collider(o, basis, yaw, Vector3(0.0, 1.3, 0.0), Vector3(w, 2.6, d))
		"oil_tank":
			var tr := w * 0.5
			_dz_lcyl("dz_metal", o, basis, Vector3(0.0, h * 0.5, 0.0), tr, h, 0.0, 0.0, 0.0, 1.0, 22)
			_dz_lcyl("dz_metal_dark", o, basis, Vector3(0.0, h + 0.15, 0.0), tr * 1.01, 0.3, 0.0, 0.0, 0.0, 1.0, 22)
			_dz_lbox("dz_metal_dark", o, basis, Vector3(tr * 0.72, h * 0.5, -tr * 0.72), Vector3(0.5, h, 0.08), -PI * 0.25)
			_dz_lbox("dz_dirt", o, basis, Vector3(0.0, 0.3, 0.0), Vector3(w * 1.7, 0.6, d * 1.7))
			_add_cylinder_collider(Vector3(x, gy + 1.5, z), tr + 0.1, 3.0)
		"ranch_tank":
			_dz_lcyl("dz_metal", o, basis, Vector3(0.0, h * 0.55, 0.0), w * 0.5, h * 0.8, 0.0, 0.0, 0.0, 1.0, 16)
			_dz_lcyl("dz_roof_red", o, basis, Vector3(0.0, h, 0.0), w * 0.55, 0.8, 0.0, 0.0, 0.0, 0.1, 16)
			_add_cylinder_collider(Vector3(x, gy + 1.3, z), w * 0.53, 2.6)
		"flare":
			_dz_lcyl("dz_rust", o, basis, Vector3(0.0, h * 0.5, 0.0), 0.42, h, 0.0, 0.0, 0.0, 0.55, 10)
			_dz_lcyl("dz_metal_dark", o, basis, Vector3(0.0, h + 0.35, 0.0), 0.34, 0.7, 0.0, 0.0, 0.0, 1.25, 10)
			var flame := SphereMesh.new()
			flame.radius = 0.85
			flame.height = 3.4
			flame.radial_segments = 10
			flame.rings = 6
			var flame_inst := _mesh_instance(anim_root, flame, _dz_flare_material, make_transform(Vector3(x, gy + h + 2.0, z)), "FlareFlame", false)
			flame_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_add_cylinder_collider(Vector3(x, gy + 1.4, z), 0.55, 2.8)
		"pumpjack":
			_dz_lbox("dz_concrete", o, basis, Vector3(0.0, 0.2, 0.0), Vector3(7.5, 0.4, 2.4))
			for sx in [-1.0, 1.0]:
				var foot: Vector3 = o + basis * Vector3(0.0, 0.3, sx * 0.95)
				var apex: Vector3 = o + basis * Vector3(0.0, 4.3, 0.0)
				_dz_beam("dz_metal_dark", foot + basis * Vector3(-1.5, 0.0, 0.0), apex, 0.2, 0.2)
				_dz_beam("dz_metal_dark", foot + basis * Vector3(1.5, 0.0, 0.0), apex, 0.2, 0.2)
			_dz_lbox("dz_rust", o, basis, Vector3(-3.4, 0.75, 0.0), Vector3(1.6, 1.1, 1.1))
			_dz_lcyl("dz_metal_dark", o, basis, Vector3(-2.4, 1.35, 0.0), 0.85, 0.35, 0.0, PI * 0.5, 0.0, 1.0, 14)
			_dz_lcyl("dz_metal_dark", o, basis, Vector3(3.6, 0.9, 0.0), 0.22, 1.8, 0.0, 0.0, 0.0, 1.0, 8)
			var jack := Node3D.new()
			jack.name = "Pumpjack"
			jack.position = o
			jack.rotation.y = yaw
			anim_root.add_child(jack)
			var pivot := Node3D.new()
			pivot.position = Vector3(0.0, 4.35, 0.0)
			jack.add_child(pivot)
			var beam_mat := _dz_material("dz_rust_light")
			_add_box(pivot, Vector3(8.2, 0.5, 0.34), Vector3(0.2, 0.28, 0.0), beam_mat, 0.0, "Beam")
			_add_box(pivot, Vector3(0.5, 1.15, 0.3), Vector3(4.15, -0.15, 0.0), beam_mat, 0.0, "HorseHead")
			_add_box(pivot, Vector3(1.3, 1.05, 0.55), Vector3(-3.4, 0.0, 0.0), _dz_material("dz_metal_dark"), 0.0, "Counterweight")
			var phase := float(int(absf(x) * 7.0 + absf(z) * 13.0) % 100) / 100.0 * TAU
			_dz_pumpjack_pivots.append({"node": pivot, "phase": phase, "speed": 0.85 + phase * 0.06})
			_dz_collider(o, basis, yaw, Vector3(0.0, 1.2, 0.0), Vector3(6.6, 2.4, 2.2))
		"wind_turbine":
			var tower_h := 34.0
			_dz_lcyl("dz_white", o, basis, Vector3(0.0, tower_h * 0.5, 0.0), 1.7, tower_h, 0.0, 0.0, 0.0, 0.5, 14)
			_dz_lbox("dz_white", o, basis, Vector3(0.0, tower_h + 0.6, 1.4), Vector3(2.0, 2.2, 6.4))
			_dz_lbox("dz_concrete", o, basis, Vector3(0.0, 0.3, 0.0), Vector3(6.0, 0.6, 6.0))
			var rotor_root := Node3D.new()
			rotor_root.name = "TurbineRotor"
			rotor_root.position = o + basis * Vector3(0.0, tower_h + 0.6, -2.4)
			rotor_root.rotation.y = yaw
			anim_root.add_child(rotor_root)
			var spinner := Node3D.new()
			rotor_root.add_child(spinner)
			var white := _dz_material("dz_white")
			for bi in range(3):
				var blade_pivot := Node3D.new()
				blade_pivot.rotation.z = TAU * float(bi) / 3.0
				spinner.add_child(blade_pivot)
				_add_box(blade_pivot, Vector3(0.62, 15.6, 0.14), Vector3(0.0, 8.4, 0.0), white, 0.0, "Blade")
			_add_sphere(spinner, 1.05, 2.1, Vector3.ZERO, white, "Hub")
			var spin_speed := 0.65 + float(int(absf(x) + absf(z)) % 40) / 100.0
			_dz_rotors.append({"node": spinner, "speed": spin_speed})
			_add_cylinder_collider(Vector3(x, gy + 1.6, z), 1.85, 3.2)
		"windmill":
			var mh := h
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_dz_beam("dz_metal_dark", o + basis * Vector3(sx * 1.5, 0.0, sz * 1.5), o + basis * Vector3(sx * 0.35, mh, sz * 0.35), 0.12, 0.12)
			for bi in range(8):
				var ang := TAU * float(bi) / 8.0
				_dz_lbox("dz_metal", o, basis, Vector3(cos(ang) * 1.25, mh + 0.2 + sin(ang) * 1.25, -0.35), Vector3(0.55, 1.7, 0.06), 0.0, 0.0, -ang)
			_dz_lbox("dz_metal", o, basis, Vector3(-1.5, mh + 0.2, 1.2), Vector3(1.3, 1.0, 0.06), PI * 0.25)
			_dz_collider(o, basis, yaw, Vector3(0.0, 1.2, 0.0), Vector3(2.4, 2.4, 2.4))
		"viewpoint":
			var deck_y := maxf(h, 3.4)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_dz_lcyl("dz_wood", o, basis, Vector3(sx * w * 0.42, deck_y * 0.5, sz * d * 0.42), 0.12, deck_y)
					_dz_lcyl("dz_wood", o, basis, Vector3(sx * w * 0.42, deck_y + 0.55, sz * d * 0.42), 0.08, 1.1)
			_dz_lbox("dz_wood", o, basis, Vector3(0.0, deck_y, 0.0), Vector3(w, 0.18, d))
			_dz_lbox("dz_wood_dark", o, basis, Vector3(0.0, deck_y + 1.05, -d * 0.46), Vector3(w, 0.09, 0.09))
			_dz_lbox("dz_wood_dark", o, basis, Vector3(0.0, deck_y + 1.05, d * 0.46), Vector3(w, 0.09, 0.09))
			_dz_lbox("dz_canvas", o, basis, Vector3(0.0, deck_y + 2.2, 0.0), Vector3(w + 0.8, 0.1, d + 0.8), 0.0, 0.08, 0.0)
			_dz_collider(o, basis, yaw, Vector3(0.0, 1.2, 0.0), Vector3(w * 0.85, 2.4, d * 0.85))
		"radio_tower":
			var th := h
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_dz_beam("dz_metal_dark", o + basis * Vector3(sx * w * 0.5, 0.0, sz * d * 0.5), o + basis * Vector3(sx * 0.5, th * 0.82, sz * 0.5), 0.18, 0.18)
			for lv in [0.22, 0.45, 0.68]:
				var y: float = th * 0.82 * lv
				var spread := lerpf(w * 0.5, 0.5, lv)
				_dz_lbox("dz_metal_dark", o, basis, Vector3(0.0, y, -spread), Vector3(spread * 2.0, 0.12, 0.12))
				_dz_lbox("dz_metal_dark", o, basis, Vector3(0.0, y, spread), Vector3(spread * 2.0, 0.12, 0.12))
				_dz_lbox("dz_metal_dark", o, basis, Vector3(-spread, y, 0.0), Vector3(0.12, 0.12, spread * 2.0))
				_dz_lbox("dz_metal_dark", o, basis, Vector3(spread, y, 0.0), Vector3(0.12, 0.12, spread * 2.0))
			_dz_lcyl("dz_metal", o, basis, Vector3(0.0, th * 0.91, 0.0), 0.16, th * 0.2, 0.0, 0.0, 0.0, 0.5, 8)
			_dz_lsphere("dz_white", o, basis, Vector3(1.6, th * 0.55, 0.0), Vector3(1.3, 1.3, 0.45))
			var beacon := SphereMesh.new()
			beacon.radius = 0.42
			beacon.height = 0.84
			beacon.radial_segments = 10
			beacon.rings = 6
			var beacon_inst := _mesh_instance(anim_root, beacon, _dz_beacon_material, make_transform(Vector3(x, gy + th + 0.4, z)), "TowerBeacon", false)
			beacon_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_dz_collider(o, basis, yaw, Vector3(0.0, 1.3, 0.0), Vector3(w * 0.8, 2.6, d * 0.8))
		"stone_arch":
			_dz_lbox("dz_rock", o, basis, Vector3(-w * 0.38, h * 0.42, 0.0), Vector3(3.4, h * 0.84, 4.2), 0.12, 0.0, 0.05)
			_dz_lbox("dz_rock", o, basis, Vector3(w * 0.38, h * 0.42, 0.6), Vector3(3.4, h * 0.84, 4.2), -0.08, 0.0, -0.04)
			_dz_lbox("dz_rock", o, basis, Vector3(0.0, h * 0.92, 0.3), Vector3(w + 2.4, h * 0.2, 4.0), 0.03, 0.0, 0.02)
			_dz_lsphere("dz_rock", o, basis, Vector3(-w * 0.55, 0.7, 2.6), Vector3(1.5, 0.9, 1.4))
			_dz_lsphere("dz_rock", o, basis, Vector3(w * 0.5, 0.5, -2.8), Vector3(1.1, 0.7, 1.0))
			_dz_collider(o, basis, yaw, Vector3(-w * 0.38, 1.4, 0.0), Vector3(3.4, 2.8, 4.2))
			_dz_collider(o, basis, yaw, Vector3(w * 0.38, 1.4, 0.6), Vector3(3.4, 2.8, 4.2))
		"plane_wreck":
			_dz_lcyl("dz_rust_light", o, basis, Vector3(0.0, 2.0, 0.0), 1.9, 15.0, 0.0, PI * 0.5, 0.0, 1.0, 14)
			_dz_lsphere("dz_rust_light", o, basis, Vector3(0.0, 2.0, -8.2), Vector3(1.9, 1.9, 2.6))
			_dz_lbox("dz_rust", o, basis, Vector3(0.0, 4.6, 7.2), Vector3(0.28, 3.4, 2.6), 0.0, -0.35, 0.0)
			_dz_lbox("dz_rust", o, basis, Vector3(-6.4, 2.2, -0.8), Vector3(9.0, 0.22, 2.6), 0.0, 0.0, 0.08)
			_dz_lbox("dz_rust", o, basis, Vector3(5.2, 0.35, 2.8), Vector3(5.6, 0.2, 2.4), 0.5, 0.0, -0.16)
			_dz_lbox("dz_glass", o, basis, Vector3(0.0, 3.15, -6.8), Vector3(2.6, 0.9, 2.2))
			_dz_lcyl("dz_metal_dark", o, basis, Vector3(-4.2, 1.1, -1.2), 0.95, 3.0, 0.0, PI * 0.5, 0.0, 1.0, 12)
			_dz_collider(o, basis, yaw, Vector3(0.0, 1.6, 0.0), Vector3(4.0, 3.2, 15.0))
		"station_ruin":
			_dz_lbox("dz_adobe_dark", o, basis, Vector3(0.0, h * 0.5, -d * 0.5), Vector3(w, h, 0.4))
			_dz_lbox("dz_adobe_dark", o, basis, Vector3(-w * 0.5, h * 0.36, 0.0), Vector3(0.4, h * 0.72, d))
			_dz_lbox("dz_adobe_dark", o, basis, Vector3(w * 0.5, h * 0.22, 0.0), Vector3(0.4, h * 0.44, d))
			_dz_lbox("dz_wood_dark", o, basis, Vector3(1.0, 0.5, 1.5), Vector3(5.0, 0.3, 0.4), 0.7, 0.0, 0.2)
			_dz_lbox("dz_concrete", o, basis, Vector3(0.0, 0.55, -d * 0.5 - 3.2), Vector3(w * 1.15, 1.1, 3.6))
			_dz_collider(o, basis, yaw, Vector3(0.0, 1.2, -d * 0.5), Vector3(w, 2.4, 0.6))
		"rail_stub":
			for sx in [-0.75, 0.75]:
				_dz_lbox("dz_metal_dark", o, basis, Vector3(sx, 0.22, 0.0), Vector3(0.14, 0.2, d))
			var sleepers := int(d / 0.9)
			for si in range(sleepers):
				_dz_lbox("dz_wood_dark", o, basis, Vector3(0.0, 0.08, -d * 0.5 + 0.5 + float(si) * 0.9), Vector3(2.3, 0.12, 0.5))
		"station_sign":
			for sx in [-1.4, 1.4]:
				_dz_lcyl("dz_wood", o, basis, Vector3(sx, h * 0.42, 0.0), 0.09, h * 0.85)
			_dz_lbox("dz_sign_cream", o, basis, Vector3(0.0, h * 0.88, 0.0), Vector3(4.4, 0.95, 0.12))
			for sx in [-1.4, 1.4]:
				_add_cylinder_collider(o + basis * Vector3(sx, 1.3, 0.0), 0.16, 2.6)
		"car_wreck":
			var wm: String = ["dz_wreck_blue", "dz_wreck_cream", "dz_wreck_red"][hash_pick]
			var roll := 0.10 if hash_pick == 1 else 0.0
			_dz_lbox(wm, o, basis, Vector3(0.0, 0.58, 0.0), Vector3(1.82, 0.58, 4.35), 0.0, 0.0, roll)
			_dz_lbox(wm, o, basis, Vector3(0.0, 0.78, -1.85), Vector3(1.70, 0.28, 1.05), 0.0, -0.16, roll)
			_dz_lbox(wm, o, basis, Vector3(0.0, 0.80, 1.82), Vector3(1.72, 0.30, 1.00), 0.0, 0.12, roll)
			_dz_lbox(wm, o, basis, Vector3(0.0, 1.06, 0.18), Vector3(1.58, 0.50, 2.05), 0.0, 0.0, roll)
			_dz_lbox("dz_glass", o, basis, Vector3(0.0, 1.10, 0.18), Vector3(1.62, 0.30, 1.82), 0.0, 0.0, roll)
			_dz_lbox(wm, o, basis, Vector3(0.0, 1.34, 0.18), Vector3(1.48, 0.10, 1.75), 0.0, 0.0, roll)
			_dz_lbox("dz_rust", o, basis, Vector3(0.45, 0.48, -0.9), Vector3(0.55, 0.18, 1.0), 0.0, 0.0, roll)
			_dz_lbox("dz_metal_dark", o, basis, Vector3(0.0, 0.42, -2.23), Vector3(1.86, 0.22, 0.16), 0.0, 0.0, roll)
			_dz_lbox("dz_metal_dark", o, basis, Vector3(0.0, 0.42, 2.23), Vector3(1.86, 0.22, 0.16), 0.0, 0.0, roll)
			for sx in [-1.0, 1.0]:
				for wz in [-1.45, 1.45]:
					if hash_pick == 0 and wz > 0.0 and sx > 0.0:
						continue
					_dz_lcyl("dz_metal_dark", o, basis, Vector3(sx * 0.82, 0.34, wz), 0.34, 0.22, 0.0, 0.0, PI * 0.5, 1.0, 10)
					_dz_lcyl("dz_metal", o, basis, Vector3(sx * 0.82, 0.34, wz), 0.16, 0.24, 0.0, 0.0, PI * 0.5, 1.0, 10)
			_dz_collider(o, basis, yaw, Vector3(0.0, 0.8, 0.0), Vector3(1.9, 1.6, 4.5))
		"salt_gate":
			for sx in [-1.0, 1.0]:
				_dz_lcyl("dz_wood", o, basis, Vector3(sx * w * 0.48, h * 0.5, 0.0), 0.16, h)
				_add_cylinder_collider(o + basis * Vector3(sx * w * 0.48, 1.4, 0.0), 0.24, 2.8)
			_dz_lbox("dz_wood_dark", o, basis, Vector3(0.0, h - 0.25, 0.0), Vector3(w + 0.8, 0.3, 0.3))
			_dz_lbox("dz_sign_cream", o, basis, Vector3(0.0, h - 0.95, 0.0), Vector3(minf(w * 0.55, 5.2), 0.9, 0.1))
		"salt_marker":
			_dz_lcyl("dz_concrete", o, basis, Vector3(0.0, h * 0.5, 0.0), 0.42, h, PI * 0.25, 0.0, 0.0, 0.55, 4)
			_add_cylinder_collider(Vector3(x, gy + 1.2, z), 0.5, 2.4)
		"salt_pylon":
			_dz_lcyl("dz_concrete", o, basis, Vector3(0.0, h * 0.5, 0.0), 1.15, h, PI * 0.25, 0.0, 0.0, 0.45, 4)
			_dz_lsphere("dz_sign_red", o, basis, Vector3(0.0, h + 0.8, 0.0), Vector3(0.8, 0.8, 0.8))
			_dz_lbox("dz_concrete", o, basis, Vector3(0.0, 0.4, 0.0), Vector3(4.2, 0.8, 4.2))
			_add_cylinder_collider(Vector3(x, gy + 1.5, z), 1.25, 3.0)
		"tent":
			_dz_lbox("dz_canvas", o, basis, Vector3(-w * 0.24, h * 0.52, 0.0), Vector3(w * 0.62, 0.1, d), 0.0, 0.0, 0.78)
			_dz_lbox("dz_canvas", o, basis, Vector3(w * 0.24, h * 0.52, 0.0), Vector3(w * 0.62, 0.1, d), 0.0, 0.0, -0.78)
			_dz_lbox("dz_dirt", o, basis, Vector3(0.0, 0.05, 0.0), Vector3(w + 0.6, 0.1, d + 0.6))
			_dz_collider(o, basis, yaw, Vector3(0.0, h * 0.4, 0.0), Vector3(w * 0.8, h * 0.8, d * 0.85))
		"pier":
			var plen := maxf(maxf(w, d), 12.0)
			var pier_lake: Dictionary = _dz_data().get("lake", {})
			var pier_deck_y := maxf(1.15, _f(pier_lake, "y", gy + 1.15) - gy + 0.55)
			_dz_lbox("dz_wood", o, basis, Vector3(0.0, pier_deck_y, -plen * 0.5), Vector3(2.6, 0.18, plen))
			_dz_collider(o, basis, yaw, Vector3(0.0, pier_deck_y - 0.13, -plen * 0.5), Vector3(2.6, 0.4, plen))
			var psteps := int(plen / 3.5)
			for pi in range(psteps + 1):
				for sx in [-1.1, 1.1]:
					_dz_lcyl("dz_wood_dark", o, basis, Vector3(sx, pier_deck_y * 0.5 - 0.45, -1.0 - float(pi) * 3.5), 0.09, pier_deck_y + 1.3)
		"billboard":
			for sx in [-1.0, 1.0]:
				_dz_lcyl("dz_pole", o, basis, Vector3(sx * w * 0.3, 2.85, 0.35), 0.14, 6.5)
				_add_cylinder_collider(o + basis * Vector3(sx * w * 0.3, 1.4, 0.35), 0.2, 2.8)
			_dz_lbox("dz_metal_dark", o, basis, Vector3(0.0, h - 1.35, 0.12), Vector3(w + 0.25, 2.9, 0.14))
			_dz_lbox("dz_sign_cream", o, basis, Vector3(0.0, h - 1.35, -0.02), Vector3(w, 2.6, 0.1))
			_dz_lbox("dz_sign_cream", o, basis, Vector3(0.0, h - 1.35, 0.26), Vector3(w, 2.6, 0.1))
		"sign", "sign_smash":
			_dz_lcyl("dz_pole", o, basis, Vector3(0.0, h * 0.38, 0.0), 0.06, h * 0.95, 0.0, 0.0, 0.0, 1.0, 8)
			var sm := "dz_sign_red" if kind == "sign_smash" else ("dz_sign_blue" if hash_pick != 1 else "dz_sign_cream")
			_dz_lbox(sm, o, basis, Vector3(0.0, h * 0.9, 0.0), Vector3(1.15, 0.85, 0.07))
			_dz_lbox("dz_white", o, basis, Vector3(0.0, h * 0.9, -0.05), Vector3(0.85, 0.24, 0.03))
			_add_cylinder_collider(Vector3(x, gy + 1.2, z), 0.14, 2.4)
		_:
			_dz_building(o, basis, yaw, w, d, h, "dz_adobe", "dz_roof_metal", false)


# --- scatter ------------------------------------------------------------------

func _dz_scatter_part(prim: Mesh, pos: Vector3, scale: Vector3, color: Color, yaw: float = 0.0, pitch: float = 0.0, roll: float = 0.0) -> Dictionary:
	return {"prim": prim, "xform": Transform3D(Basis.from_euler(Vector3(pitch, yaw, roll)) * Basis.IDENTITY.scaled(scale), pos), "color": color}


func _dz_scatter_mesh(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	for part_variant in parts:
		var part: Dictionary = part_variant
		var prim := part["prim"] as Mesh
		var xform := part["xform"] as Transform3D
		var color := part["color"] as Color
		var arrays: Array = prim.surface_get_arrays(0)
		var pv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var puv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var order: Array = []
		if idx.is_empty():
			for i in range(pv.size()):
				order.append(i)
		else:
			for i in range(idx.size()):
				order.append(int(idx[i]))
		for vi_variant in order:
			var vi := int(vi_variant)
			verts.append(xform.basis * pv[vi] + xform.origin)
			normals.append((xform.basis * pn[vi]).normalized())
			colors.append(color)
			uvs.append(puv[vi] if vi < puv.size() else Vector2.ZERO)
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colors
	out[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh


func _dz_saguaro_mesh(variant: int) -> ArrayMesh:
	# 0.2.50: three authored saguaro silhouettes (classic two-arm,
	# tall one-arm, squat three-arm) instead of identical clones.
	# Parts stay white: the ribbed dz_cactus_skin PBR material
	# colours them through the cylinder UVs that _dz_scatter_mesh
	# preserves.  Elbow spheres hide the arm joints.
	var trunk_prim := _dz_unit_cyl(14, 0.86)
	var arm_prim := _dz_unit_cyl(12, 0.82)
	var cap_prim := _dz_unit_sphere(12, 8)
	var skin := Color(1.0, 1.0, 1.0)
	var trunk_h := 4.6
	var trunk_r := 0.30
	var arms: Array = [[-1.0, 2.4, 1.5, 0.17], [1.0, 1.9, 1.1, 0.15]]
	match variant:
		1:
			trunk_h = 5.4
			trunk_r = 0.27
			arms = [[-1.0, 3.0, 1.7, 0.16]]
		2:
			trunk_h = 3.8
			trunk_r = 0.34
			arms = [[-1.0, 2.0, 1.2, 0.17], [1.0, 2.5, 1.4, 0.16], [1.0, 1.4, 0.7, 0.13]]
	var parts: Array = []
	parts.append(_dz_scatter_part(trunk_prim, Vector3(0.0, trunk_h * 0.5, 0.0), Vector3(trunk_r * 2.0, trunk_h, trunk_r * 2.0), skin))
	parts.append(_dz_scatter_part(cap_prim, Vector3(0.0, trunk_h, 0.0), Vector3(trunk_r * 1.72, trunk_r * 1.1, trunk_r * 1.72), skin))
	for arm_variant in arms:
		var arm: Array = arm_variant
		var side := float(arm[0])
		var ay := float(arm[1])
		var ah := float(arm[2])
		var ar := float(arm[3])
		var reach := trunk_r + ar + 0.34
		var elbow_x := side * reach
		parts.append(_dz_scatter_part(arm_prim, Vector3(side * (trunk_r * 0.4 + reach * 0.5), ay, 0.0), Vector3(ar * 2.0, reach + trunk_r * 0.6, ar * 2.0), skin, 0.0, 0.0, side * PI * 0.5))
		parts.append(_dz_scatter_part(cap_prim, Vector3(elbow_x, ay, 0.0), Vector3(ar * 2.1, ar * 2.1, ar * 2.1), skin))
		parts.append(_dz_scatter_part(arm_prim, Vector3(elbow_x, ay + ah * 0.5, 0.0), Vector3(ar * 2.0, ah, ar * 2.0), skin))
		parts.append(_dz_scatter_part(cap_prim, Vector3(elbow_x, ay + ah, 0.0), Vector3(ar * 1.65, ar * 1.0, ar * 1.65), skin))
	return _dz_scatter_mesh(parts)


func _dz_rock_mesh(seed_i: int, color: Color) -> ArrayMesh:
	# 0.2.50: coherent multi-octave displacement on a denser sphere
	# (the old 9x6 sphere with per-vertex hash jitter read as crumpled
	# paper).  Flat shading and baked face tints stay; the fine surface
	# detail comes from the world-triplanar dz_rock_red PBR set, and
	# the squashed underside lets boulders sit in the ground.
	var prim := _dz_unit_sphere(18, 12)
	var arrays: Array = prim.surface_get_arrays(0)
	var pv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var ph := float(seed_i) * 1.73
	var stretch_x := 0.88 + _hash01(seed_i * 7 + 1, 13) * 0.30
	var stretch_z := 0.88 + _hash01(seed_i * 11 + 5, 29) * 0.30
	var displaced := PackedVector3Array()
	displaced.resize(pv.size())
	for i in range(pv.size()):
		var p := pv[i]
		var noise := 0.55 * sin(p.x * 3.1 + ph) * sin(p.y * 2.7 + ph * 1.3) * sin(p.z * 3.4 - ph)
		noise += 0.30 * sin(p.x * 6.3 - ph * 0.7) * sin(p.y * 5.1 + ph) * sin(p.z * 5.7 + ph * 0.5)
		noise += 0.15 * sin(p.x * 11.0 + ph * 2.1) * sin(p.y * 9.3 - ph * 0.4) * sin(p.z * 9.0 - ph)
		var ridge := 1.0 - absf(sin(p.x * 4.7 + ph * 0.8) * sin(p.z * 4.1 - ph))
		noise -= ridge * 0.18
		noise += (_hash01(int((p.x + 0.5) * 14.0) + seed_i * 23, int((p.y + 0.5) * 17.0) + int((p.z + 0.5) * 19.0)) - 0.5) * 0.16
		var r := clampf(1.0 + noise * 0.36, 0.56, 1.38)
		var y := p.y * 0.70 * r
		if y < -0.34:
			y = -0.34 + (y + 0.34) * 0.22
		displaced[i] = Vector3(p.x * r * stretch_x, y, p.z * r * stretch_z)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var tri_count := idx.size() / 3
	for t in range(tri_count):
		var a := displaced[int(idx[t * 3])]
		var b := displaced[int(idx[t * 3 + 1])]
		var c := displaced[int(idx[t * 3 + 2])]
		var n := (b - a).cross(c - a)
		if n.length_squared() < 0.000001:
			continue
		n = n.normalized()
		var shade := 0.70 + clampf(n.y * 0.5 + 0.5, 0.0, 1.0) * 0.40
		shade *= 0.93 + _hash01(t * 3 + seed_i, seed_i * 31 + t) * 0.14
		var face_color := Color(color.r * shade, color.g * shade, color.b * shade)
		for v in [a, b, c]:
			verts.append(v)
			normals.append(n)
			colors.append(face_color)
			uvs.append(Vector2.ZERO)
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colors
	out[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh


func _dz_unit_torus() -> Mesh:
	if not _dz_prim_cache.has("torus"):
		var m := TorusMesh.new()
		m.inner_radius = 0.34
		m.outer_radius = 0.5
		m.rings = 12
		m.ring_segments = 6
		_dz_prim_cache["torus"] = m
	return _dz_prim_cache["torus"]


func _dz_emit_multimesh(root: Node, mesh: Mesh, material: Material, transforms: Array, node_name: String, range_end: float, shadows: bool) -> void:
	if transforms.is_empty():
		return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for i in range(transforms.size()):
		var t := transforms[i] as Transform3D
		multi.set_instance_transform(i, t)
		mn = mn.min(t.origin)
		mx = mx.max(t.origin)
	var inst := MultiMeshInstance3D.new()
	inst.name = node_name
	inst.multimesh = multi
	inst.material_override = material
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var pad := Vector3(7.0, 9.0, 7.0)
	var aabb := AABB(mn - pad, (mx - mn) + pad * 2.0)
	inst.custom_aabb = aabb
	if range_end > 0.0:
		inst.visibility_range_begin = 0.0
		inst.visibility_range_end = range_end
		inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		inst.lod_bias = 0.45
		_quality_ranged_instances.append({"node": inst, "begin": 0.0, "end": range_end})
	root.add_child(inst)
	_stream_chunks.append({"node": inst, "centre": aabb.get_center(), "radius": aabb.size.length() * 0.5, "hidden": false, "sector_hidden_0237": false})
	_multimesh_chunk_count += 1


func _build_desert_scatter() -> void:
	var root := Node3D.new()
	root.name = "DesertScatter"
	add_child(root)
	if _dz_scatter_material == null:
		_dz_scatter_material = StandardMaterial3D.new()
		_dz_scatter_material.vertex_color_use_as_albedo = true
		_dz_scatter_material.roughness = 0.95
		_dz_scatter_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var cyl7 := _dz_unit_cyl(7, 0.4)
	var cyl11 := _dz_unit_cyl(11, 0.05)
	var sph := _dz_unit_sphere(10, 7)
	var torus := _dz_unit_torus()
	# 0.2.50: dedicated PBR materials for the hero scatter kinds.
	# The shared vertex-colour material still serves shrubs/bones.
	var cactus_mat := _material("dz_cactus_skin_mat", "dz_cactus_skin.jpg", "dz_cactus_skin_normal.jpg", Color(0.86, 0.94, 0.84), 1.0, 0.0, Vector3(1.0, 2.0, 1.0), false, "dz_cactus_skin_roughness.jpg")
	var rock_mat := _material("dz_rock_red_mat", "dz_rock_red.jpg", "dz_rock_red_normal.jpg", Color(0.90, 0.85, 0.78), 1.0, 0.0, Vector3(0.16, 0.16, 0.16), true, "dz_rock_red_roughness.jpg")
	rock_mat.vertex_color_use_as_albedo = true
	var pile_mat := _material("dz_gravel_pile_mat", "dz_trail_gravel.jpg", "dz_trail_gravel_normal.jpg", Color(0.84, 0.80, 0.74), 1.0, 0.0, Vector3(0.35, 0.35, 0.35), true, "dz_trail_gravel_roughness.jpg")
	pile_mat.vertex_color_use_as_albedo = true
	var saguaro_meshes: Array = [_dz_saguaro_mesh(0), _dz_saguaro_mesh(1), _dz_saguaro_mesh(2)]
	var barrel_mesh := _dz_scatter_mesh([
		_dz_scatter_part(sph, Vector3(0, 0.42, 0), Vector3(0.78, 0.95, 0.78), Color(0.15, 0.27, 0.12)),
		_dz_scatter_part(sph, Vector3(0, 0.92, 0), Vector3(0.2, 0.16, 0.2), Color(0.55, 0.27, 0.07)),
	])
	var prickly_parts: Array = []
	for pi in range(5):
		var ang := TAU * float(pi) / 5.0
		prickly_parts.append(_dz_scatter_part(sph, Vector3(cos(ang) * 0.42, 0.34, sin(ang) * 0.42), Vector3(0.55, 0.72, 0.15), Color(0.14, 0.27, 0.12), -ang, 0.0, 0.24))
	prickly_parts.append(_dz_scatter_part(sph, Vector3(0, 0.3, 0), Vector3(0.5, 0.62, 0.15), Color(0.14, 0.27, 0.12), 0.4))
	var prickly_mesh := _dz_scatter_mesh(prickly_parts)
	var shrub_mesh := _dz_scatter_mesh([
		_dz_scatter_part(cyl7, Vector3(0, 0.25, 0), Vector3(0.16, 0.5, 0.16), Color(0.16, 0.10, 0.05), 0.0, 0.0, 0.15),
		_dz_scatter_part(sph, Vector3(0, 0.38, 0), Vector3(1.30, 0.70, 1.20), Color(0.075, 0.105, 0.045)),
		_dz_scatter_part(sph, Vector3(0.52, 0.55, 0.22), Vector3(0.82, 0.52, 0.76), Color(0.10, 0.13, 0.055)),
		_dz_scatter_part(sph, Vector3(-0.52, 0.48, -0.28), Vector3(0.74, 0.46, 0.70), Color(0.065, 0.095, 0.040)),
		_dz_scatter_part(sph, Vector3(-0.18, 0.66, 0.40), Vector3(0.62, 0.40, 0.58), Color(0.16, 0.125, 0.065)),
		_dz_scatter_part(sph, Vector3(0.30, 0.30, -0.52), Vector3(0.66, 0.42, 0.60), Color(0.085, 0.11, 0.048)),
	])
	var dead_tree_mesh := _dz_scatter_mesh([
		_dz_scatter_part(cyl7, Vector3(0, 1.8, 0), Vector3(0.5, 3.6, 0.5), Color(0.20, 0.14, 0.09), 0.0, 0.0, 0.07),
		_dz_scatter_part(cyl7, Vector3(0.75, 3.2, 0.1), Vector3(0.2, 1.9, 0.2), Color(0.20, 0.14, 0.09), 0.0, 0.0, -0.85),
		_dz_scatter_part(cyl7, Vector3(-0.65, 2.8, -0.2), Vector3(0.17, 1.6, 0.17), Color(0.23, 0.16, 0.10), 0.0, 0.35, 0.9),
		_dz_scatter_part(cyl7, Vector3(0.15, 3.9, -0.6), Vector3(0.14, 1.4, 0.14), Color(0.23, 0.16, 0.10), 0.0, 0.8, 0.2),
	])
	var bone_color := Color(0.48, 0.42, 0.32)
	var bones_mesh := _dz_scatter_mesh([
		_dz_scatter_part(_dz_unit_box(), Vector3(0, 0.28, 0), Vector3(0.22, 0.22, 2.2), bone_color),
		_dz_scatter_part(torus, Vector3(0, 0.32, -0.55), Vector3(1.15, 1.3, 1.15), bone_color, 0.0, PI * 0.5, 0.0),
		_dz_scatter_part(torus, Vector3(0, 0.3, 0.05), Vector3(1.05, 1.2, 1.05), bone_color, 0.0, PI * 0.5, 0.0),
		_dz_scatter_part(torus, Vector3(0, 0.26, 0.6), Vector3(0.9, 1.05, 0.9), bone_color, 0.0, PI * 0.5, 0.0),
		_dz_scatter_part(sph, Vector3(0.35, 0.22, -1.45), Vector3(0.55, 0.45, 0.8), bone_color, 0.4),
	])
	var tumble_mesh := _dz_scatter_mesh([
		_dz_scatter_part(torus, Vector3(0, 0.42, 0), Vector3(0.9, 0.9, 0.9), Color(0.30, 0.22, 0.12)),
		_dz_scatter_part(torus, Vector3(0, 0.42, 0), Vector3(0.85, 0.85, 0.85), Color(0.27, 0.20, 0.11), 0.0, PI * 0.5, 0.0),
		_dz_scatter_part(torus, Vector3(0, 0.42, 0), Vector3(0.8, 0.8, 0.8), Color(0.33, 0.24, 0.13), 0.7, PI * 0.25, 0.5),
	])
	var reed_parts: Array = []
	for ri in range(6):
		var rang := TAU * float(ri) / 6.0
		reed_parts.append(_dz_scatter_part(cyl7, Vector3(cos(rang) * 0.3, 0.72, sin(rang) * 0.3), Vector3(0.085, 1.5, 0.085), Color(0.14, 0.24, 0.09), 0.0, cos(rang) * 0.18, sin(rang) * 0.18))
		if ri % 2 == 0:
			reed_parts.append(_dz_scatter_part(cyl7, Vector3(cos(rang) * 0.38, 1.48, sin(rang) * 0.38), Vector3(0.09, 0.34, 0.09), Color(0.24, 0.15, 0.07), 0.0, cos(rang) * 0.18, sin(rang) * 0.18))
	var reed_mesh := _dz_scatter_mesh(reed_parts)
	var pile_mesh := _dz_scatter_mesh([
		_dz_scatter_part(cyl11, Vector3(0, 1.10, 0), Vector3(6.2, 2.2, 6.2), Color(0.72, 0.68, 0.62)),
		_dz_scatter_part(cyl11, Vector3(3.4, 0.62, 1.6), Vector3(3.4, 1.25, 3.4), Color(0.64, 0.60, 0.55)),
	])
	var rock_small_meshes: Array = [_dz_rock_mesh(11, Color(0.78, 0.72, 0.64)), _dz_rock_mesh(12, Color(0.74, 0.68, 0.60)), _dz_rock_mesh(13, Color(0.82, 0.75, 0.66))]
	var rock_medium_meshes: Array = [_dz_rock_mesh(21, Color(0.84, 0.76, 0.66)), _dz_rock_mesh(22, Color(0.80, 0.73, 0.63)), _dz_rock_mesh(23, Color(0.86, 0.78, 0.68))]
	var rock_large_meshes: Array = [_dz_rock_mesh(31, Color(0.88, 0.80, 0.69)), _dz_rock_mesh(32, Color(0.85, 0.77, 0.66)), _dz_rock_mesh(33, Color(0.90, 0.82, 0.71))]

	var cfg := {
		"cactus_saguaro": {"meshes": saguaro_meshes, "material": cactus_mat, "base": 1.0, "range": 430.0, "shadow": true, "sink": 0.10, "collider_r": 0.36, "collider_h": 2.6, "foliage": true},
		"cactus_barrel": {"mesh": barrel_mesh, "base": 1.0, "range": 220.0, "shadow": true, "sink": 0.05, "collider_r": 0.34, "collider_h": 0.8},
		"cactus_prickly": {"mesh": prickly_mesh, "base": 1.0, "range": 220.0, "shadow": true, "sink": 0.05, "collider_r": 0.38, "collider_h": 0.6},
		"shrub": {"mesh": shrub_mesh, "base": 1.0, "range": 220.0, "shadow": false, "sink": 0.14, "foliage": true},
		"rock_small": {"meshes": rock_small_meshes, "material": rock_mat, "base": 0.55, "range": 220.0, "shadow": false, "sink": 0.16},
		"rock_medium": {"meshes": rock_medium_meshes, "material": rock_mat, "base": 1.15, "range": 430.0, "shadow": true, "sink": 0.22, "collider_r": 0.62, "collider_h": 1.6},
		"rock_large": {"meshes": rock_large_meshes, "material": rock_mat, "base": 2.7, "range": 1200.0, "shadow": true, "sink": 0.45, "collider_r": 1.35, "collider_h": 2.4},
		"dead_tree": {"mesh": dead_tree_mesh, "base": 1.0, "range": 430.0, "shadow": true, "sink": 0.06, "collider_r": 0.30, "collider_h": 2.6},
		"bones": {"mesh": bones_mesh, "base": 1.0, "range": 220.0, "shadow": false, "sink": 0.04},
		"tumbleweed": {"mesh": tumble_mesh, "base": 1.0, "range": 220.0, "shadow": false, "sink": 0.03},
		"oasis_reed": {"mesh": reed_mesh, "base": 1.0, "range": 220.0, "shadow": false, "sink": 0.18},
		"gravel_pile": {"mesh": pile_mesh, "material": pile_mat, "base": 1.0, "range": 900.0, "shadow": true, "sink": 0.15, "collider_r": 1.9, "collider_h": 1.6},
	}
	var scatter: Dictionary = _dz_data().get("scatter", {})
	var total := 0
	for kind_variant in cfg.keys():
		var kind := String(kind_variant)
		var conf: Dictionary = cfg[kind]
		var items: Array = scatter.get(kind, [])
		if items.is_empty():
			continue
		var buckets: Dictionary = {}
		var base := float(conf.get("base", 1.0))
		var sink := float(conf.get("sink", 0.05))
		var collider_r := float(conf.get("collider_r", 0.0))
		var collider_h := float(conf.get("collider_h", 2.0))
		var is_foliage := bool(conf.get("foliage", false))
		for item_variant in items:
			var item: Array = item_variant
			if item.size() < 4:
				continue
			var px := float(item[0])
			var pz := float(item[1])
			var sc := float(item[2]) * base
			var pyaw := float(item[3])
			var pos := Vector3(px, height_at(px, pz) - sink, pz)
			var key := "%d,%d" % [int(floor(px / DZ_CHUNK_M)), int(floor(pz / DZ_CHUNK_M))]
			if not buckets.has(key):
				buckets[key] = []
			(buckets[key] as Array).append(make_transform(pos, pyaw, Vector3.ONE * sc))
			total += 1
			if collider_r > 0.0:
				_add_cylinder_collider(Vector3(px, pos.y + collider_h * 0.5, pz), collider_r * sc, collider_h * sc)
			elif kind == "rock_small" and sc > 0.70:
				_add_cylinder_collider(Vector3(px, pos.y + 0.35 * sc, pz), 0.30 * sc, 0.7 * sc)
			if is_foliage:
				_foliage_points.append(pos)
		var kind_meshes: Array = conf.get("meshes", [])
		var kind_mat: Material = conf.get("material", _dz_scatter_material) as Material
		for key_variant in buckets.keys():
			var bucket_xforms: Array = buckets[key_variant]
			if kind_meshes.is_empty():
				_dz_emit_multimesh(root, conf["mesh"] as Mesh, kind_mat, bucket_xforms, "DzScatter_" + kind, float(conf.get("range", 300.0)), bool(conf.get("shadow", false)))
			else:
				for vi in range(kind_meshes.size()):
					var sub: Array = []
					for ti in range(bucket_xforms.size()):
						if ti % kind_meshes.size() == vi:
							sub.append(bucket_xforms[ti])
					_dz_emit_multimesh(root, kind_meshes[vi] as Mesh, kind_mat, sub, "DzScatter_" + kind + "_v" + str(vi), float(conf.get("range", 300.0)), bool(conf.get("shadow", false)))
	# Oasis palms reuse the detailed date/royal GLBs (same batching path
	# as RichTown so LOD/streaming treatment is identical).
	var palm_items: Array = scatter.get("oasis_palm", [])
	var date_t: Array = []
	var royal_t: Array = []
	for i in range(palm_items.size()):
		var item: Array = palm_items[i]
		if item.size() < 4:
			continue
		var px := float(item[0])
		var pz := float(item[1])
		var pos := Vector3(px, height_at(px, pz) - 0.06, pz)
		_foliage_points.append(pos)
		var palm_scale := float(item[2])
		_add_cylinder_collider(Vector3(px, pos.y + 2.9 * palm_scale, pz), 0.34 * palm_scale, 5.8 * palm_scale)
		var t := make_transform(pos, float(item[3]), Vector3.ONE * float(item[2]))
		if i % 5 < 3:
			date_t.append(t)
		else:
			royal_t.append(t)
		total += 1
	_add_batched_model(root, "res://assets/vegetation/palm_date.glb", date_t, "DesertOasisPalms")
	_add_batched_model(root, "res://assets/vegetation/palm_royal.glb", royal_t, "DesertOasisPalms")
	_enhancement_stats["desert_scatter"] = total
	_enhancement_stats["desert_detail_0250"] = true
	_enhancement_stats["desert_scatter_variants"] = saguaro_meshes.size() + rock_small_meshes.size() + rock_medium_meshes.size() + rock_large_meshes.size()
	_enhancement_stats["palm_count"] = palm_items.size()


# --- game dressing --------------------------------------------------------------

func _dz_banner(root: Node3D, pos: Vector3, yaw: float, mat_key: String) -> void:
	var basis := Basis(Vector3.UP, yaw)
	for sx in [-1.0, 1.0]:
		_dz_lcyl("dz_pole", pos, basis, Vector3(sx * 5.4, 3.5, 0.0), 0.13, 7.0)
		_add_cylinder_collider(pos + basis * Vector3(sx * 5.4, 1.5, 0.0), 0.2, 3.0)
	_dz_lbox(mat_key, pos, basis, Vector3(0.0, 6.6, 0.0), Vector3(11.4, 0.95, 0.16))
	_dz_lbox("dz_white", pos, basis, Vector3(0.0, 6.6, -0.1), Vector3(6.4, 0.5, 0.06))


func _build_desert_game_markers() -> void:
	var root := Node3D.new()
	root.name = "DesertGameMarkers"
	add_child(root)
	var game: Dictionary = _dz_data().get("game", {})
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.55, 0.12, 0.20)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring_mat.no_depth_test = false
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 3.0
	ring_mesh.outer_radius = 3.42
	ring_mesh.rings = 26
	ring_mesh.ring_segments = 8
	var ring_count := 0
	var banner_count := 0
	for list_key in ["circuits", "sprints"]:
		for route_variant in game.get(list_key, []):
			var route: Dictionary = route_variant
			var points: Array = route.get("points", [])
			var acc := 0.0
			var prev := Vector2.INF
			for pi in range(points.size()):
				var p: Array = points[pi]
				var v := Vector2(float(p[0]), float(p[1]))
				if prev != Vector2.INF:
					acc += (v - prev).length()
				var is_first := pi == 0
				var is_last := pi == points.size() - 1
				if is_first or is_last or acc >= 150.0:
					# TorusMesh lies in the local XZ plane.  Rotate it
					# upright and yaw it with the route so each marker is
					# a checkpoint gate across the road, not a flat halo
					# hovering parallel to the ground (screenshot audit).
					var route_dir := Vector2.RIGHT
					if pi + 1 < points.size():
						var next_point: Array = points[pi + 1]
						route_dir = Vector2(float(next_point[0]), float(next_point[1])) - v
					elif prev != Vector2.INF:
						route_dir = v - prev
					if route_dir.length_squared() < 0.01:
						route_dir = Vector2.RIGHT
					var ring_yaw := atan2(-route_dir.x, -route_dir.y)
					var ring_basis := (Basis(Vector3.UP, ring_yaw) * Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0))).scaled_local(Vector3.ONE * 0.92)
					var ring := _mesh_instance(root, ring_mesh, ring_mat, Transform3D(ring_basis, Vector3(v.x, height_at(v.x, v.y) + 3.35, v.y)), "RaceRing", false)
					ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					ring.visibility_range_begin = 14.0
					ring.visibility_range_begin_margin = 8.0
					ring.visibility_range_end = 340.0
					ring.visibility_range_end_margin = 60.0
					ring.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
					ring_count += 1
					acc = 0.0
					if points.size() >= 2 and (is_first or is_last):
						var other: Array = points[1] if is_first else points[points.size() - 2]
						var ov := Vector2(float(other[0]), float(other[1]))
						var dir := (v - ov) if is_last else (ov - v)
						var yaw := atan2(-dir.x, -dir.y)
						_dz_banner(root, Vector3(v.x, height_at(v.x, v.y) - 0.05, v.y), yaw, "dz_sign_red" if is_first else "dz_sign_blue")
						banner_count += 1
				prev = v
	for drag_variant in game.get("drags", []):
		var drag: Dictionary = drag_variant
		var start: Array = drag.get("start", [])
		var finish: Array = drag.get("finish", [])
		if start.size() < 2 or finish.size() < 2:
			continue
		var sv := Vector2(float(start[0]), float(start[1]))
		var fv := Vector2(float(finish[0]), float(finish[1]))
		var dir := fv - sv
		var yaw := atan2(-dir.x, -dir.y)
		_dz_banner(root, Vector3(sv.x, height_at(sv.x, sv.y) - 0.05, sv.y), yaw, "dz_sign_red")
		_dz_banner(root, Vector3(fv.x, height_at(fv.x, fv.y) - 0.05, fv.y), yaw, "dz_sign_blue")
		banner_count += 2
	for jump_variant in game.get("jumps", []):
		var jump: Dictionary = jump_variant
		var jx := _f(jump, "x")
		var jz := _f(jump, "z")
		var jyaw := _f(jump, "yaw")
		var origin := Vector3(jx, height_at(jx, jz) - 0.05, jz)
		var basis := Basis(Vector3.UP, jyaw)
		_dz_lbox("dz_dirt", origin, basis, Vector3(0.0, 0.55, 0.0), Vector3(4.6, 1.1, 7.0), 0.0, -0.16, 0.0)
		_dz_lbox("dz_wood", origin, basis, Vector3(0.0, 1.05, -0.4), Vector3(4.2, 0.14, 6.4), 0.0, -0.16, 0.0)
		var ramp_shape := CollisionShape3D.new()
		var ramp_box := BoxShape3D.new()
		ramp_box.size = Vector3(4.6, 0.9, 7.0)
		ramp_shape.shape = ramp_box
		var ramp_centre := origin + basis * Vector3(0.0, 0.6, -0.2)
		ramp_shape.transform = Transform3D(basis * Basis.from_euler(Vector3(-0.16, 0.0, 0.0)), ramp_centre)
		if _collision_root != null:
			_collision_root.add_child(ramp_shape)
		_register_collider(ramp_shape, ramp_centre)
	for ft_variant in game.get("fastTravel", []):
		var ft: Dictionary = ft_variant
		var fx := _f(ft, "x")
		var fz := _f(ft, "z")
		var origin := Vector3(fx, height_at(fx, fz) - 0.03, fz)
		var basis := Basis.IDENTITY
		_dz_lcyl("dz_pole", origin, basis, Vector3(3.4, 2.2, 0.0), 0.1, 4.4)
		_dz_lbox("dz_sign_blue", origin, basis, Vector3(3.4, 4.5, 0.0), Vector3(1.7, 0.9, 0.12))
		_dz_lbox("dz_concrete", origin, basis, Vector3(0.0, 0.06, 0.0), Vector3(7.5, 0.12, 5.2))
	for tr_variant in game.get("treasures", []):
		var tr: Dictionary = tr_variant
		var tx := _f(tr, "x")
		var tz := _f(tr, "z")
		var origin := Vector3(tx, height_at(tx, tz) - 0.03, tz)
		var basis := Basis(Vector3.UP, _hash01(int(tx), int(tz)) * TAU)
		_dz_lbox("dz_rust", origin, basis, Vector3(0.0, 0.5, 0.0), Vector3(1.5, 1.0, 1.0))
		_dz_lbox("dz_yellow", origin, basis, Vector3(0.0, 1.02, 0.0), Vector3(1.5, 0.16, 1.0))
		_dz_lbox("dz_dirt", origin, basis, Vector3(1.3, 0.3, 0.8), Vector3(1.6, 0.5, 1.4))
	var merged := _dz_flush_merge(root)
	_enhancement_stats["desert_race_rings"] = ring_count
	_enhancement_stats["desert_race_rings_subtle_0253"] = true
	_enhancement_stats["desert_banners"] = banner_count
	_enhancement_stats["desert_game_merged_chunks"] = merged


# --- probes, skyline, animation -------------------------------------------------

func _build_desert_reflection_probes() -> void:
	_reflection_probes.clear()
	var root := Node3D.new()
	root.name = "ReflectionProbes"
	add_child(root)
	var specs := [
		["Town", 820.0, 2050.0, 30.0],
		["Quarry", 3280.0, 1080.0, 42.0],
		["Oasis", 3350.0, 3500.0, 26.0],
		["Salt", 2000.0, 2280.0, 24.0],
		["Oil", 3520.0, 2380.0, 32.0],
		["Canyon", 900.0, 1000.0, 36.0],
	]
	for spec_variant in specs:
		var spec: Array = spec_variant
		var label := String(spec[0])
		var px := float(spec[1])
		var pz := float(spec[2])
		var ph := float(spec[3])
		var probe := ReflectionProbe.new()
		probe.name = "Probe" + label
		probe.size = Vector3(340.0, 130.0, 340.0)
		probe.position = Vector3(px, height_at(px, pz) + ph, pz)
		probe.origin_offset = Vector3(0.0, ph * 0.5 - ph, 0.0)
		probe.box_projection = true
		probe.enable_shadows = false
		probe.intensity = 0.68
		probe.max_distance = 240.0
		probe.mesh_lod_threshold = 0.65
		probe.ambient_mode = ReflectionProbe.AMBIENT_ENVIRONMENT
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		probe.cull_mask = (1 << 19) - 1
		probe.blend_distance = 60.0
		root.add_child(probe)
		_reflection_probes.append(probe)
	_enhancement_stats["reflection_probes"] = _reflection_probes.size()
	_enhancement_stats["reflection_probe_mode"] = "once_box_projected_cell_grid"
	_enhancement_stats["reflection_probe_update_budget_ms"] = 1.2
	_enhancement_stats["reflection_probe_stagger"] = "per_4_cells"


func _build_desert_bounds() -> void:
	# Desert terrain reaches ~148 m (mesa tops at the north rim),
	# far above the RichTown-height shared bounds, so the desert
	# gets its own walls: span y -20..200 around the 4x4 km basin
	# and a safety floor just under the lowest drivable ground
	# (oasis lake bed, 23.6 m).
	_add_box_collider(Vector3(-3.0, 90.0, 2000.0), Vector3(6.0, 220.0, 4012.0))
	_add_box_collider(Vector3(4003.0, 90.0, 2000.0), Vector3(6.0, 220.0, 4012.0))
	_add_box_collider(Vector3(2000.0, 90.0, -3.0), Vector3(4012.0, 220.0, 6.0))
	_add_box_collider(Vector3(2000.0, 90.0, 4003.0), Vector3(4012.0, 220.0, 6.0))
	_add_box_collider(Vector3(2000.0, 18.0, 2000.0), Vector3(4080.0, 2.0, 4080.0))


func _build_desert_skyline() -> void:
	if _skyline_root == null:
		_skyline_root = Node3D.new()
		_skyline_root.name = "DistantSkyline"
		add_child(_skyline_root)
	# The first screenshot audit showed the original skyline as huge,
	# pale rectangular slabs: one rock texture was stretched across a
	# 0.5-1.0 km BoxMesh face and the long axis pointed AT the player.
	# These mesas are tapered nine-sided frustums with their long axis
	# tangential to the horizon ring.  Local (not world) triplanar
	# mapping keeps the rock detail attached to each mesa while the
	# skyline root follows the car.
	var mat := _material("dz_far_mesa_local", "rock.jpg", "rock_normal.jpg", Color(0.52, 0.34, 0.25), 1.0, 0.0, Vector3(26.0, 7.0, 26.0), true)
	mat.uv1_world_triplanar = false
	var mat_light := _material("dz_far_mesa_local_light", "rock.jpg", "rock_normal.jpg", Color(0.67, 0.46, 0.34), 1.0, 0.0, Vector3(26.0, 7.0, 26.0), true)
	mat_light.uv1_world_triplanar = false
	var base_mesh := _dz_unit_cyl(9, 0.66)
	var cap_mesh := _dz_unit_cyl(9, 0.84)
	var count := 0
	for i in range(22):
		var ang := TAU * float(i) / 22.0 + _hash01(i * 3 + 1, 7) * 0.18
		var radius := 1780.0 + _hash01(i * 5 + 2, 11) * 280.0
		var w := 620.0 + _hash01(i * 7 + 3, 13) * 560.0
		var depth := 300.0 + _hash01(i * 13 + 4, 19) * 180.0
		var hgt := 95.0 + _hash01(i * 11 + 5, 17) * 80.0
		var base_h := hgt * 0.78
		var cap_h := hgt * 0.30
		var yaw := -ang + (_hash01(i * 17 + 6, 23) - 0.5) * 0.10
		# make_transform()'s local X is radial at yaw=-ang and local Z is
		# tangential, so scale is (radial depth, height, horizon width).
		var base_pos := Vector3(cos(ang) * radius, base_h * 0.5 - 22.0, sin(ang) * radius)
		var inst := _mesh_instance(_skyline_root, base_mesh, mat if i % 2 == 0 else mat_light, make_transform(base_pos, yaw, Vector3(depth, base_h, w)), "FarMesa", false)
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var cap_pos := Vector3(base_pos.x, base_h - 22.0 + cap_h * 0.5 - 5.0, base_pos.z)
		var cap := _mesh_instance(_skyline_root, cap_mesh, mat_light if i % 2 == 0 else mat, make_transform(cap_pos, yaw + 0.04, Vector3(depth * 0.72, cap_h, w * 0.62)), "FarMesaCap", false)
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		count += 2
	set_skyline_origin(spawn_transform.origin)
	_set_skyline_time(time_of_day)
	_enhancement_stats["skyline_layers"] = 1
	_enhancement_stats["skyline_assets"] = count
	_enhancement_stats["skyline_follow"] = true
	_enhancement_stats["skyline_shader"] = false


func _dz_animate(delta: float) -> void:
	_gf_animate_birds()
	if _dz_pumpjack_pivots.is_empty() and _dz_rotors.is_empty() and _dz_beacon_material == null:
		return
	for entry in _dz_pumpjack_pivots:
		var pivot := entry["node"] as Node3D
		if pivot != null and is_instance_valid(pivot):
			pivot.rotation.z = sin(_elapsed * float(entry["speed"]) + float(entry["phase"])) * 0.14
	for entry in _dz_rotors:
		var spinner := entry["node"] as Node3D
		if spinner != null and is_instance_valid(spinner):
			spinner.rotation.z += float(entry["speed"]) * delta
	if _dz_beacon_material != null:
		_dz_beacon_material.emission_energy_multiplier = 3.2 if fmod(_elapsed, 1.6) < 0.18 else 0.12
	if _dz_flare_material != null:
		_dz_flare_material.emission_energy_multiplier = 2.9 + sin(_elapsed * 11.0) * 0.45 + sin(_elapsed * 23.7) * 0.25


# --- GreenForest (0.2.54) -------------------------------------------------
# Third world.  Roads/bridges/tunnels/merged structures/game markers
# reuse the data-driven desert path above through _dz_data(); the
# functions below are the forest-specific terrain splat, water,
# vegetation scatter, authored structure kinds and living details.

func _gf_in_field(x: float, z: float) -> bool:
	for rect in _gf_field_rects:
		if rect.has_point(Vector2(x, z)):
			return true
	return false


func _build_forest_terrain() -> void:
	_gf_field_rects.clear()
	for field_variant in _dz_data().get("fields", []):
		var field: Dictionary = field_variant
		var fw := _f(field, "w", 100.0)
		var fd := _f(field, "d", 100.0)
		_gf_field_rects.append(Rect2(_f(field, "x") - fw * 0.5, _f(field, "z") - fd * 0.5, fw, fd))
	var lake: Dictionary = _dz_data().get("lake", {})
	_gf_lake_y = _f(lake, "y", 14.0)
	_build_desert_terrain()
	_enhancement_stats["forest_terrain_chunks"] = int(_enhancement_stats.get("desert_terrain_chunks", 0))
	_enhancement_stats["greenforest_world_0254"] = true


func _build_forest_water() -> void:
	var root := Node3D.new()
	root.name = "Water"
	add_child(root)
	var lake: Dictionary = _dz_data().get("lake", {})
	var lake_x := _f(lake, "x", 3050.0)
	var lake_z := _f(lake, "z", 2200.0)
	var lake_y := _f(lake, "y", 14.0)
	var lake_rx := _f(lake, "rx", 450.0)
	var lake_rz := _f(lake, "rz", 400.0)
	var lake_mesh := CylinderMesh.new()
	lake_mesh.top_radius = 1.0
	lake_mesh.bottom_radius = 1.0
	lake_mesh.height = 0.24
	lake_mesh.radial_segments = 72
	lake_mesh.rings = 1
	_mesh_instance(root, lake_mesh, _water_material(),
		make_transform(Vector3(lake_x, lake_y - 0.12, lake_z), 0.0, Vector3(lake_rx + 12.0, 1.0, lake_rz + 12.0)),
		"ForestLake", false)
	# Swamp sheet: terrain humps poke through it as boggy islets.
	var swamp: Dictionary = _dz_data().get("swamp", {})
	if not swamp.is_empty():
		var swamp_mesh := CylinderMesh.new()
		swamp_mesh.top_radius = 1.0
		swamp_mesh.bottom_radius = 1.0
		swamp_mesh.height = 0.18
		swamp_mesh.radial_segments = 48
		_mesh_instance(root, swamp_mesh, _water_material(),
			make_transform(Vector3(_f(swamp, "x"), _f(swamp, "y", 8.9) - 0.08, _f(swamp, "z")), 0.0,
				Vector3(_f(swamp, "rx", 370.0), 1.0, _f(swamp, "rz", 285.0))),
			"ForestSwamp", false)
	# River ribbons follow the generator's stored water heights.
	var river_segments := 0
	for river_variant in _dz_data().get("river", []):
		var river: Array = river_variant
		if river.size() < 2:
			continue
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var pts: Array[Vector3] = []
		for p_variant in river:
			var p: Array = p_variant
			if p.size() < 3:
				continue
			pts.append(Vector3(float(p[0]), float(p[2]), float(p[1])))
		for i in range(pts.size() - 1):
			var a := pts[i]
			var b := pts[i + 1]
			var dir := Vector2(b.x - a.x, b.z - a.z).normalized()
			var perp := Vector2(-dir.y, dir.x) * 5.5
			var v0 := Vector3(a.x - perp.x, a.y, a.z - perp.y)
			var v1 := Vector3(a.x + perp.x, a.y, a.z + perp.y)
			var v2 := Vector3(b.x + perp.x, b.y, b.z + perp.y)
			var v3 := Vector3(b.x - perp.x, b.y, b.z - perp.y)
			for vertex in [v0, v1, v2, v0, v2, v3]:
				tool.set_uv(Vector2(vertex.x / 9.0, vertex.z / 9.0))
				tool.add_vertex(vertex)
			river_segments += 1
		tool.generate_normals()
		var river_mesh := tool.commit()
		if river_mesh != null:
			_mesh_instance(root, river_mesh, _water_material(), Transform3D.IDENTITY, "ForestRiver", false)
	_enhancement_stats["forest_lake"] = true
	_enhancement_stats["forest_river_segments"] = river_segments


func _build_forest_reflection_probes() -> void:
	_reflection_probes.clear()
	var root := Node3D.new()
	root.name = "ReflectionProbes"
	add_child(root)
	var specs := [
		["Village", 3600.0, 2150.0, 26.0],
		["Lake", 3050.0, 2200.0, 24.0],
		["Farm", 2050.0, 3450.0, 26.0],
		["DarkForest", 650.0, 2000.0, 30.0],
		["Summit", 1850.0, 350.0, 34.0],
		["Sawmill", 920.0, 3520.0, 26.0],
	]
	for spec_variant in specs:
		var spec: Array = spec_variant
		var label := String(spec[0])
		var px := float(spec[1])
		var pz := float(spec[2])
		var ph := float(spec[3])
		var probe := ReflectionProbe.new()
		probe.name = "Probe" + label
		probe.size = Vector3(340.0, 130.0, 340.0)
		probe.position = Vector3(px, height_at(px, pz) + ph, pz)
		probe.origin_offset = Vector3(0.0, ph * 0.5 - ph, 0.0)
		probe.box_projection = true
		probe.enable_shadows = false
		probe.intensity = 0.68
		probe.max_distance = 240.0
		probe.mesh_lod_threshold = 0.65
		probe.ambient_mode = ReflectionProbe.AMBIENT_ENVIRONMENT
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		probe.cull_mask = (1 << 19) - 1
		probe.blend_distance = 60.0
		root.add_child(probe)
		_reflection_probes.append(probe)
	_enhancement_stats["reflection_probes"] = _reflection_probes.size()
	_enhancement_stats["reflection_probe_mode"] = "once_box_projected_cell_grid"
	_enhancement_stats["reflection_probe_update_budget_ms"] = 1.2
	_enhancement_stats["reflection_probe_stagger"] = "per_4_cells"


func _build_forest_bounds() -> void:
	# Hills reach ~158 m; the lowest drivable ground is the river
	# bed (~9 m), so the safety floor sits just under y=1.
	_add_box_collider(Vector3(-3.0, 95.0, 2000.0), Vector3(6.0, 230.0, 4012.0))
	_add_box_collider(Vector3(4003.0, 95.0, 2000.0), Vector3(6.0, 230.0, 4012.0))
	_add_box_collider(Vector3(2000.0, 95.0, -3.0), Vector3(4012.0, 230.0, 6.0))
	_add_box_collider(Vector3(2000.0, 95.0, 4003.0), Vector3(4012.0, 230.0, 6.0))
	_add_box_collider(Vector3(2000.0, 0.0, 2000.0), Vector3(4080.0, 2.0, 4080.0))


func _build_forest_skyline() -> void:
	if _skyline_root == null:
		_skyline_root = Node3D.new()
		_skyline_root.name = "DistantSkyline"
		add_child(_skyline_root)
	# Forested far ridges: tapered frustums in two mossy greens with
	# local (not world) triplanar mapping, tangential to the horizon
	# ring like the desert mesas, plus a nearer spruce-spike ring.
	var mat := _material("gf_far_ridge_local", "gf_forest_floor.jpg", "gf_forest_floor_normal.jpg", Color(0.30, 0.42, 0.24), 1.0, 0.0, Vector3(26.0, 7.0, 26.0), true)
	mat.uv1_world_triplanar = false
	var mat_light := _material("gf_far_ridge_local_light", "gf_meadow.jpg", "gf_meadow_normal.jpg", Color(0.38, 0.50, 0.28), 1.0, 0.0, Vector3(26.0, 7.0, 26.0), true)
	mat_light.uv1_world_triplanar = false
	var base_mesh := _dz_unit_cyl(9, 0.66)
	var cap_mesh := _dz_unit_cyl(9, 0.84)
	var spike_mesh := _dz_unit_cyl(7, 0.03)
	var spike_mat := _material("gf_far_spruce", "", "", Color(0.10, 0.20, 0.10), 1.0)
	var count := 0
	for i in range(22):
		var ang := TAU * float(i) / 22.0 + _hash01(i * 3 + 1, 7) * 0.18
		var radius := 1780.0 + _hash01(i * 5 + 2, 11) * 280.0
		var w := 620.0 + _hash01(i * 7 + 3, 13) * 560.0
		var depth := 300.0 + _hash01(i * 13 + 4, 19) * 180.0
		var hgt := 110.0 + _hash01(i * 11 + 5, 17) * 90.0
		var base_h := hgt * 0.78
		var cap_h := hgt * 0.30
		var yaw := -ang + (_hash01(i * 17 + 6, 23) - 0.5) * 0.10
		var base_pos := Vector3(cos(ang) * radius, base_h * 0.5 - 22.0, sin(ang) * radius)
		var inst := _mesh_instance(_skyline_root, base_mesh, mat if i % 2 == 0 else mat_light, make_transform(base_pos, yaw, Vector3(depth, base_h, w)), "FarRidge", false)
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var cap_pos := Vector3(base_pos.x, base_h - 22.0 + cap_h * 0.5 - 5.0, base_pos.z)
		var cap := _mesh_instance(_skyline_root, cap_mesh, mat_light if i % 2 == 0 else mat, make_transform(cap_pos, yaw + 0.04, Vector3(depth * 0.72, cap_h, w * 0.62)), "FarRidgeCap", false)
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		count += 2
		for si in range(3):
			var sang := ang + (float(si) - 1.0) * 0.055
			var sradius := radius - 260.0 - _hash01(i * 31 + si, 41) * 120.0
			var sh := 130.0 + _hash01(i * 37 + si, 43) * 90.0
			var spike_pos := Vector3(cos(sang) * sradius, sh * 0.5 - 26.0, sin(sang) * sradius)
			var spike := _mesh_instance(_skyline_root, spike_mesh, spike_mat, make_transform(spike_pos, sang, Vector3(95.0, sh, 95.0)), "FarSpruce", false)
			spike.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			count += 1
	set_skyline_origin(spawn_transform.origin)
	_set_skyline_time(time_of_day)
	_enhancement_stats["skyline_layers"] = 1
	_enhancement_stats["skyline_assets"] = count
	_enhancement_stats["forest_skyline_0254"] = true


func _finish_forest_build() -> void:
	_enhancement_stats["greenforest_world_0254"] = true
	_enhancement_stats["near_field_lod_0243"] = true
	_enhancement_stats["tree_detail_end_m"] = 105.0
	_enhancement_stats["palm_detail_end_m"] = 130.0
	_enhancement_stats["shrub_detail_end_m"] = 90.0
	_enhancement_stats["range_fade_mode"] = "dithered_self"
	set_time_of_day("day")
	var collider_total := 0
	for cell_variant in _collider_cells.keys():
		collider_total += (_collider_cells[cell_variant] as Array).size()
	_enhancement_stats["streaming_colliders_total"] = collider_total
	_enhancement_stats["streaming_collider_cells"] = _collider_cells.size()
	_build_foliage_grid()
	_streaming_tick(spawn_transform.origin, -spawn_transform.basis.z, spawn_transform.origin, Vector3.ZERO)
	is_built = true


func _gf_structure_kind(kind: String, o: Vector3, basis: Basis, w: float, d: float, h: float, hash_pick: int) -> bool:
	# Forest-only structure kinds; returns false so shared kinds fall
	# through to the desert catalogue in _dz_structure.
	match kind:
		"silo":
			_dz_lcyl("dz_metal", o, basis, Vector3(0.0, h * 0.5, 0.0), w * 0.5, h, 0.0, 0.0, 0.0, 0.92, 14)
			_dz_lcyl("dz_roof_metal", o, basis, Vector3(0.0, h + w * 0.22, 0.0), w * 0.54, w * 0.44, 0.0, 0.0, 0.0, 0.05, 14)
			_dz_lbox("dz_metal_dark", o, basis, Vector3(w * 0.52, h * 0.5, 0.0), Vector3(0.18, h, 0.5))
			_dz_lbox("dz_concrete", o, basis, Vector3(0.0, 0.25, d * 0.7), Vector3(w * 0.8, 0.5, d * 0.6))
			_add_cylinder_collider(o + basis * Vector3(0.0, 2.2, 0.0), w * 0.52, 4.4)
		"greenhouse":
			var gh := 2.9
			_dz_lbox("dz_concrete", o, basis, Vector3(0.0, 0.18, 0.0), Vector3(w + 0.6, 0.36, d + 0.6))
			for px in [-0.5, 0.5]:
				_dz_lbox("dz_glass", o, basis, Vector3(px * w, gh * 0.55, 0.0), Vector3(0.12, gh * 1.1, d))
				_dz_lbox("dz_white", o, basis, Vector3(px * w, gh + 0.35, 0.0), Vector3(0.2, 0.24, d))
			for pz in [-0.5, -0.17, 0.17, 0.5]:
				_dz_lbox("dz_white", o, basis, Vector3(0.0, gh * 0.55, pz * d), Vector3(w, gh * 1.1, 0.14))
			var roof_pitch := 0.62
			for sx in [-1.0, 1.0]:
				_dz_lbox("dz_glass", o, basis, Vector3(sx * w * 0.25, gh + w * 0.16, 0.0), Vector3(w * 0.62, 0.1, d), 0.0, 0.0, sx * roof_pitch)
			_dz_lbox("dz_white", o, basis, Vector3(0.0, gh + w * 0.30, 0.0), Vector3(0.28, 0.22, d))
			_dz_lbox("gf_deer_belly", o, basis, Vector3(0.0, 0.55, 0.0), Vector3(w * 0.7, 0.4, d * 0.8))
			_add_box_collider(o + basis * Vector3(0.0, 1.2, 0.0), Vector3(w, 2.4, d), atan2(-basis.z.x, -basis.z.z))
		"tractor":
			var paint := "gf_tractor_green" if hash_pick % 2 == 0 else "gf_tractor_red"
			_dz_lbox(paint, o, basis, Vector3(0.0, 1.05, -0.9), Vector3(1.15, 0.85, 2.2))
			_dz_lbox("dz_metal_dark", o, basis, Vector3(0.0, 0.55, 0.4), Vector3(1.3, 0.5, 3.4))
			_dz_lbox("dz_glass", o, basis, Vector3(0.0, 2.0, 0.85), Vector3(1.35, 1.25, 1.3))
			_dz_lbox(paint, o, basis, Vector3(0.0, 2.72, 0.85), Vector3(1.5, 0.18, 1.5))
			_dz_lcyl("dz_metal_dark", o, basis, Vector3(0.42, 1.85, -1.5), 0.07, 1.1)
			for tx in [-0.85, 0.85]:
				_dz_lcyl("dz_metal_dark", o, basis, Vector3(tx, 0.78, 1.35), 0.78, 0.42, 0.0, 0.0, PI * 0.5, 1.0, 12)
				_dz_lcyl("dz_yellow", o, basis, Vector3(tx * 1.06, 0.78, 1.35), 0.36, 0.46, 0.0, 0.0, PI * 0.5, 1.0, 10)
				_dz_lcyl("dz_metal_dark", o, basis, Vector3(tx * 0.88, 0.45, -1.55), 0.45, 0.3, 0.0, 0.0, PI * 0.5, 1.0, 10)
			_add_box_collider(o + basis * Vector3(0.0, 1.0, 0.0), Vector3(1.9, 2.0, 4.0), atan2(-basis.z.x, -basis.z.z))
		"log_stack":
			var layers := [4, 3, 2]
			for li in range(layers.size()):
				var count: int = layers[li]
				for ci in range(count):
					var lx := (float(ci) - float(count - 1) * 0.5) * 0.62
					_dz_lcyl("dz_wood", o, basis, Vector3(lx, 0.32 + float(li) * 0.54, 0.0), 0.30, d, 0.0, PI * 0.5, 0.0, 0.96, 9)
			_add_box_collider(o + basis * Vector3(0.0, 0.9, 0.0), Vector3(w, 1.8, d), atan2(-basis.z.x, -basis.z.z))
		"log_truck":
			_dz_lbox("dz_metal_dark", o, basis, Vector3(0.0, 0.95, 0.0), Vector3(2.2, 0.5, d))
			_dz_lbox("dz_orange", o, basis, Vector3(0.0, 1.7, -d * 0.38), Vector3(2.2, 1.5, 1.9))
			_dz_lbox("dz_glass", o, basis, Vector3(0.0, 2.05, -d * 0.38 - 0.6), Vector3(2.0, 0.7, 0.8))
			for li in range(3):
				for ci in range(3 - (1 if li == 2 else 0)):
					var lx := (float(ci) - 1.0) * 0.66 + (0.33 if li == 2 else 0.0)
					_dz_lcyl("dz_wood", o, basis, Vector3(lx, 1.55 + float(li) * 0.56, d * 0.12), 0.31, d * 0.62, 0.0, PI * 0.5, 0.0, 0.96, 9)
			for wz in [-d * 0.36, d * 0.30, d * 0.42]:
				for wx in [-1.05, 1.05]:
					_dz_lcyl("dz_metal_dark", o, basis, Vector3(wx, 0.52, wz), 0.52, 0.34, 0.0, 0.0, PI * 0.5, 1.0, 10)
			_add_box_collider(o + basis * Vector3(0.0, 1.2, 0.0), Vector3(2.4, 2.4, d), atan2(-basis.z.x, -basis.z.z))
		"sawmill_hall":
			var post_h := 4.6
			for px in [-0.5, 0.5]:
				for pz in [-0.5, 0.0, 0.5]:
					_dz_lbox("dz_wood_dark", o, basis, Vector3(px * w, post_h * 0.5, pz * d), Vector3(0.42, post_h, 0.42))
			var rp := 0.34
			for sx in [-1.0, 1.0]:
				_dz_lbox("dz_roof_metal", o, basis, Vector3(sx * w * 0.26, post_h + w * 0.075, 0.0), Vector3(w * 0.62, 0.16, d + 1.2), 0.0, 0.0, sx * rp)
			_dz_lbox("dz_concrete", o, basis, Vector3(0.0, 0.12, 0.0), Vector3(w + 1.0, 0.24, d + 1.0))
			_dz_lbox("dz_yellow", o, basis, Vector3(-w * 0.2, 1.0, 0.0), Vector3(1.2, 1.6, d * 0.5))
			_dz_lcyl("dz_metal", o, basis, Vector3(-w * 0.2, 1.9, -d * 0.1), 0.75, 0.1, 0.0, 0.0, PI * 0.5, 1.0, 16)
			_dz_lcyl("dz_wood", o, basis, Vector3(w * 0.18, 0.85, 0.0), 0.34, d * 0.55, 0.0, PI * 0.5, 0.0, 0.96, 9)
			_add_box_collider(o + basis * Vector3(-w * 0.5, 2.0, 0.0), Vector3(0.6, 4.0, d), atan2(-basis.z.x, -basis.z.z))
			_add_box_collider(o + basis * Vector3(w * 0.5, 2.0, 0.0), Vector3(0.6, 4.0, d), atan2(-basis.z.x, -basis.z.z))
		"lighthouse":
			_dz_lcyl("dz_white", o, basis, Vector3(0.0, h * 0.42, 0.0), w * 0.5, h * 0.84, 0.0, 0.0, 0.0, 0.68, 12)
			_dz_lcyl("dz_sign_red", o, basis, Vector3(0.0, h * 0.55, 0.0), w * 0.42, h * 0.16, 0.0, 0.0, 0.0, 0.96, 12)
			_dz_lcyl("dz_metal_dark", o, basis, Vector3(0.0, h * 0.86, 0.0), w * 0.44, 0.35, 0.0, 0.0, 0.0, 1.0, 12)
			_dz_lcyl("dz_lamp", o, basis, Vector3(0.0, h * 0.94, 0.0), w * 0.3, h * 0.12, 0.0, 0.0, 0.0, 1.0, 10)
			_dz_lcyl("dz_roof_red", o, basis, Vector3(0.0, h * 1.05, 0.0), w * 0.42, h * 0.12, 0.0, 0.0, 0.0, 0.05, 10)
			_add_cylinder_collider(o + basis * Vector3(0.0, 2.4, 0.0), w * 0.52, 4.8)
		"waterfall":
			# Rock cleft + translucent falling sheet + foam pool.
			_dz_lbox("dz_rock", o, basis, Vector3(-w * 0.42, h * 0.45, d * 0.18), Vector3(w * 0.4, h * 0.9, d * 0.7), 0.06)
			_dz_lbox("dz_rock", o, basis, Vector3(w * 0.42, h * 0.45, d * 0.18), Vector3(w * 0.4, h * 0.9, d * 0.7), -0.05)
			_dz_lbox("dz_rock", o, basis, Vector3(0.0, h * 0.92, d * 0.3), Vector3(w * 0.7, h * 0.2, d * 0.5))
			_dz_lbox("gf_waterfall", o, basis, Vector3(0.0, h * 0.48, 0.0), Vector3(w * 0.34, h * 0.9, 0.5), 0.0, -0.10, 0.0)
			_dz_lcyl("gf_waterfall", o, basis, Vector3(0.0, 0.35, -d * 0.22), w * 0.34, 0.7, 0.0, 0.0, 0.0, 1.0, 12)
			_add_box_collider(o + basis * Vector3(-w * 0.42, 2.5, d * 0.18), Vector3(w * 0.4, 5.0, d * 0.7), atan2(-basis.z.x, -basis.z.z))
			_add_box_collider(o + basis * Vector3(w * 0.42, 2.5, d * 0.18), Vector3(w * 0.4, 5.0, d * 0.7), atan2(-basis.z.x, -basis.z.z))
		_:
			return false
	return true


func _gf_near_road(px: float, pz: float, limit: float) -> bool:
	# Exact uncapped near-road test over the 3x3 road-grid
	# neighbourhood.  _road_clearance_xz() caps its answer at
	# ROAD_GRID_QUERY_CLEARANCE_M (10 m), so the 0.2.54 test
	# `clearance < 22` was true for EVERY tree and the scatter stage
	# tried to create 37.5k physics colliders: CI timed out at 600 s
	# and Android killed the app mid-loading.  True roadside trees
	# within 22 m number ~6.9k (verified against the data).
	var centre := _road_grid_cell(px, pz)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var candidates: Array = _road_segment_grid.get(Vector2i(centre.x + dx, centre.y + dz), [])
			for index_variant in candidates:
				var i := int(index_variant)
				var a: Vector3 = _road_segment_starts[i]
				var b: Vector3 = _road_segment_ends[i]
				var ab := Vector2(b.x - a.x, b.z - a.z)
				var ap := Vector2(px - a.x, pz - a.z)
				var length_squared := ab.length_squared()
				var dist := ap.length()
				if length_squared > 0.0001:
					var t := clampf(ap.dot(ab) / length_squared, 0.0, 1.0)
					dist = ap.distance_to(ab * t)
				if dist - float(_road_segment_half_widths[i]) < limit:
					return true
	return false


# 0.2.57 photoreal-leaning foliage: alpha-cut card materials, card
# surface packing and per-species tree builders (textured bark trunk
# + dark crown core + painted leaf/needle cards).
func _gf_foliage_material(key: String, file: String, tint: Color) -> StandardMaterial3D:
	var material := _material(key, file, "", tint, 0.92, 0.0, Vector3.ONE, false, "")
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.42
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	return material


func _gf_cards_surface(cards: Array) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	for card_variant in cards:
		var card: Dictionary = card_variant
		var c := card["c"] as Vector3
		var r := card["r"] as Vector3
		var u := card["u"] as Vector3
		var n := (card["n"] as Vector3).normalized()
		var col := card["col"] as Color
		var corners: Array = [c - r - u, c + r - u, c + r + u, c - r + u]
		var uv_corners: Array = [Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0)]
		if bool(card.get("flip", false)):
			uv_corners = [Vector2(1.0, 1.0), Vector2(0.0, 1.0), Vector2(0.0, 0.0), Vector2(1.0, 0.0)]
		for vi in [0, 1, 2, 0, 2, 3]:
			verts.append(corners[vi])
			normals.append(n)
			colors.append(col)
			uvs.append(uv_corners[vi])
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colors
	out[Mesh.ARRAY_TEX_UV] = uvs
	return out


func _gf_branch_part(prim: Mesh, p0: Vector3, p1: Vector3, r_bottom: float, color: Color) -> Dictionary:
	var dirv := p1 - p0
	var len := maxf(dirv.length(), 0.001)
	var up := dirv / len
	var ref := Vector3.RIGHT if absf(up.y) > 0.92 else Vector3.UP
	var side := ref.cross(up).normalized()
	var fwd := up.cross(side).normalized()
	var basis := Basis(side * (r_bottom * 2.0), up * len, fwd * (r_bottom * 2.0))
	return {"prim": prim, "xform": Transform3D(basis, (p0 + p1) * 0.5), "color": color}


func _gf_tree_mesh(trunk_parts: Array, core_parts: Array, cards: Array, bark_material: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if not trunk_parts.is_empty():
		var trunk_mesh := _dz_scatter_mesh(trunk_parts)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, trunk_mesh.surface_get_arrays(0))
		if bark_material != null:
			mesh.surface_set_material(mesh.get_surface_count() - 1, bark_material)
	if not core_parts.is_empty():
		var core_mesh := _dz_scatter_mesh(core_parts)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, core_mesh.surface_get_arrays(0))
		mesh.surface_set_material(mesh.get_surface_count() - 1, _dz_scatter_material)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _gf_cards_surface(cards))
	return mesh


func _gf_apply_wind(mesh: ArrayMesh, texture_file: String, tint: Color, bend: float) -> ArrayMesh:
	var wind := _create_foliage_wind_material(mesh, texture_file, tint, 0.32, bend, false)
	mesh.surface_set_material(mesh.get_surface_count() - 1, wind)
	return mesh


# One foliage cluster: two crossed cards centred on a branch tip.
func _gf_add_cluster(cards: Array, centre: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	var base_yaw := rng.randf() * TAU
	for ci in range(2):
		var yaw := base_yaw + float(ci) * PI * 0.5 + rng.randf_range(-0.22, 0.22)
		var right := Vector3(cos(yaw), 0.0, sin(yaw)) * size * 0.5
		var flat := Vector3(-sin(yaw), 0.0, cos(yaw))
		var upv := (Vector3.UP + flat * rng.randf_range(-0.35, 0.35)).normalized() * size * 0.47
		var b := rng.randf_range(0.85, 1.08)
		cards.append({"c": centre, "r": right, "u": upv, "n": (flat + Vector3.UP * 0.45).normalized(), "col": Color(b, b, b), "flip": rng.randf() < 0.5})


# 0.2.58 branching skeletons: real trunk -> primary -> secondary
# branch cylinders with foliage clusters at the branch ends, so the
# woody structure reads through the crown instead of a round blob.
func _gf_broadleaf_mesh(variant: int, is_oak: bool, bark_material: Material, foliage_file: String, foliage_tint: Color) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = (20261653 if is_oak else 20261801) + variant * 181
	var branch_prim := _dz_unit_cyl(6, 0.62)
	var core_prim := _dz_unit_sphere(6, 4)
	var white := Color(1.0, 1.0, 1.0)
	var trunk_r := 0.42 if is_oak else 0.27
	var trunk_h := rng.randf_range(2.9, 3.5) if is_oak else rng.randf_range(3.2, 3.9)
	var parts: Array = []
	var core: Array = []
	var cards: Array = []
	var core_col := Color(0.030, 0.078, 0.022) if is_oak else Color(0.034, 0.088, 0.025)
	var p_base := Vector3(0.0, -0.2, 0.0)
	var p_mid := Vector3(rng.randf_range(-0.14, 0.14), trunk_h * 0.55, rng.randf_range(-0.14, 0.14))
	var collar := Vector3(rng.randf_range(-0.2, 0.2), trunk_h, rng.randf_range(-0.2, 0.2))
	parts.append(_gf_branch_part(branch_prim, p_base, p_mid, trunk_r, white))
	parts.append(_gf_branch_part(branch_prim, p_mid, collar, trunk_r * 0.72, white))
	parts.append(_dz_scatter_part(branch_prim, Vector3(0.0, 0.28, 0.0), Vector3(trunk_r * 3.1, 0.75, trunk_r * 3.1), white))
	var prim_count := (5 if is_oak else 4) + variant
	var reach := rng.randf_range(2.1, 2.7) if is_oak else rng.randf_range(1.7, 2.3)
	var cluster := 2.05 if is_oak else 1.78
	for i in range(prim_count):
		var yaw := TAU * float(i) / float(prim_count) + rng.randf_range(-0.3, 0.3)
		var elev := rng.randf_range(0.32, 0.62) if is_oak else rng.randf_range(0.45, 0.8)
		var dir1 := Vector3(cos(yaw) * cos(elev), sin(elev), sin(yaw) * cos(elev))
		var p1 := collar + dir1 * (reach * rng.randf_range(0.5, 0.65))
		var dir2 := (dir1 + Vector3.UP * rng.randf_range(0.25, 0.5) + Vector3(rng.randf_range(-0.18, 0.18), 0.0, rng.randf_range(-0.18, 0.18))).normalized()
		var p2 := p1 + dir2 * (reach * rng.randf_range(0.5, 0.75))
		parts.append(_gf_branch_part(branch_prim, collar, p1, trunk_r * 0.42, white))
		parts.append(_gf_branch_part(branch_prim, p1, p2, trunk_r * 0.24, white))
		_gf_add_cluster(cards, p2 + Vector3.UP * cluster * 0.16, cluster, rng)
		core.append(_dz_scatter_part(core_prim, p2, Vector3(cluster * 0.62, cluster * 0.52, cluster * 0.62), core_col))
		_gf_add_cluster(cards, p1.lerp(p2, 0.55) + Vector3.UP * cluster * 0.22, cluster * 0.9, rng)
		for k in range(2):
			var origin := p1.lerp(p2, 0.25 + 0.35 * float(k))
			var syaw := yaw + rng.randf_range(0.5, 0.95) * (1.0 if k == 0 else -1.0)
			var selev := elev + rng.randf_range(0.05, 0.35)
			var sdir := Vector3(cos(syaw) * cos(selev), sin(selev), sin(syaw) * cos(selev))
			var send := origin + sdir * (reach * rng.randf_range(0.42, 0.62))
			parts.append(_gf_branch_part(branch_prim, origin, send, trunk_r * 0.13, white))
			_gf_add_cluster(cards, send + Vector3.UP * cluster * 0.13, cluster * 0.78, rng)
	var lead_end := collar + Vector3(rng.randf_range(-0.3, 0.3), reach * rng.randf_range(0.75, 1.0), rng.randf_range(-0.3, 0.3))
	parts.append(_gf_branch_part(branch_prim, collar, lead_end, trunk_r * 0.3, white))
	_gf_add_cluster(cards, lead_end + Vector3.UP * cluster * 0.2, cluster * 1.05, rng)
	core.append(_dz_scatter_part(core_prim, lead_end, Vector3(cluster * 0.6, cluster * 0.5, cluster * 0.6), core_col))
	var mesh := _gf_tree_mesh(parts, core, cards, bark_material)
	return _gf_apply_wind(mesh, foliage_file, foliage_tint, 0.08)


func _gf_birch_mesh(variant: int, bark_material: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261477 + variant * 167
	var branch_prim := _dz_unit_cyl(6, 0.6)
	var white := Color(1.0, 1.0, 1.0)
	var trunk_r := 0.16
	var trunk_h := rng.randf_range(4.4, 5.2)
	var parts: Array = []
	var cards: Array = []
	var p_base := Vector3(0.0, -0.2, 0.0)
	var p_mid := Vector3(rng.randf_range(-0.2, 0.2), trunk_h * 0.55, rng.randf_range(-0.2, 0.2))
	var collar := Vector3(rng.randf_range(-0.25, 0.25), trunk_h, rng.randf_range(-0.25, 0.25))
	parts.append(_gf_branch_part(branch_prim, p_base, p_mid, trunk_r, white))
	parts.append(_gf_branch_part(branch_prim, p_mid, collar, trunk_r * 0.7, white))
	for i in range(5 + variant):
		var from := p_mid.lerp(collar, rng.randf_range(0.15, 0.9))
		var yaw := TAU * float(i) / 5.0 + rng.randf_range(-0.35, 0.35)
		var elev := rng.randf_range(0.7, 1.15)
		var dir1 := Vector3(cos(yaw) * cos(elev), sin(elev), sin(yaw) * cos(elev))
		var p1 := from + dir1 * rng.randf_range(1.0, 1.5)
		var dir2 := (dir1 + Vector3.UP * rng.randf_range(0.1, 0.35)).normalized()
		var p2 := p1 + dir2 * rng.randf_range(0.9, 1.4)
		parts.append(_gf_branch_part(branch_prim, from, p1, trunk_r * 0.45, white))
		parts.append(_gf_branch_part(branch_prim, p1, p2, trunk_r * 0.22, white))
		_gf_add_cluster(cards, p2 + Vector3.UP * 0.22, 1.55, rng)
		_gf_add_cluster(cards, p1.lerp(p2, 0.5) + Vector3.UP * 0.3, 1.35, rng)
	var lead_end := collar + Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(1.4, 1.9), rng.randf_range(-0.2, 0.2))
	parts.append(_gf_branch_part(branch_prim, collar, lead_end, trunk_r * 0.4, white))
	_gf_add_cluster(cards, lead_end + Vector3.UP * 0.25, 1.6, rng)
	var mesh := _gf_tree_mesh(parts, [], cards, bark_material)
	return _gf_apply_wind(mesh, "gf_birch_cluster.png", Color(1.0, 1.0, 1.0), 0.09)


func _gf_pine_mesh(variant: int, bark_material: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261301 + variant * 149
	var branch_prim := _dz_unit_cyl(6, 0.6)
	var core_prim := _dz_unit_sphere(6, 4)
	var white := Color(1.0, 1.0, 1.0)
	var trunk_r := 0.23
	var trunk_h := rng.randf_range(5.4, 6.4)
	var lean := rng.randf_range(-0.35, 0.35)
	var parts: Array = []
	var core: Array = []
	var cards: Array = []
	var p_base := Vector3(0.0, -0.2, 0.0)
	var p_mid := Vector3(lean * 0.5, trunk_h * 0.55, rng.randf_range(-0.12, 0.12))
	var collar := Vector3(lean, trunk_h, rng.randf_range(-0.15, 0.15))
	parts.append(_gf_branch_part(branch_prim, p_base, p_mid, trunk_r, white))
	parts.append(_gf_branch_part(branch_prim, p_mid, collar, trunk_r * 0.68, white))
	parts.append(_dz_scatter_part(branch_prim, Vector3(0.0, 0.26, 0.0), Vector3(trunk_r * 3.0, 0.7, trunk_r * 3.0), white))
	var core_col := Color(0.022, 0.058, 0.018)
	core.append(_dz_scatter_part(core_prim, collar + Vector3(0.0, 0.55, 0.0), Vector3(2.2, 1.0, 2.2), core_col))
	for i in range(6 + variant):
		var from := p_mid.lerp(collar, rng.randf_range(0.45, 0.95))
		var yaw := TAU * float(i) / 6.0 + rng.randf_range(-0.3, 0.3)
		var elev := rng.randf_range(0.12, 0.45)
		var dir1 := Vector3(cos(yaw) * cos(elev), sin(elev), sin(yaw) * cos(elev))
		var p1 := from + dir1 * rng.randf_range(1.3, 1.9)
		var dir2 := (dir1 + Vector3.UP * rng.randf_range(0.3, 0.55)).normalized()
		var p2 := p1 + dir2 * rng.randf_range(0.9, 1.4)
		parts.append(_gf_branch_part(branch_prim, from, p1, trunk_r * 0.4, white))
		parts.append(_gf_branch_part(branch_prim, p1, p2, trunk_r * 0.2, white))
		_gf_add_cluster(cards, p2 + Vector3.UP * 0.3, 2.15, rng)
		if i % 2 == 0:
			_gf_add_cluster(cards, p1 + Vector3.UP * 0.35, 1.8, rng)
	var lead_end := collar + Vector3(lean * 0.3, rng.randf_range(1.2, 1.7), 0.0)
	parts.append(_gf_branch_part(branch_prim, collar, lead_end, trunk_r * 0.32, white))
	_gf_add_cluster(cards, lead_end + Vector3.UP * 0.3, 2.0, rng)
	var mesh := _gf_tree_mesh(parts, core, cards, bark_material)
	return _gf_apply_wind(mesh, "gf_pine_spray.png", Color(1.0, 1.0, 1.0), 0.065)


func _gf_spruce_mesh(variant: int, bark_material: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261117 + variant * 131
	var cyl := _dz_unit_cyl(8, 0.35)
	var cone := _dz_unit_cyl(9, 0.04)
	var branch_prim := _dz_unit_cyl(5, 0.5)
	var white := Color(1.0, 1.0, 1.0)
	var top := 9.7 if variant == 0 else 10.5
	var trunk: Array = [_dz_scatter_part(cyl, Vector3(0.0, 2.3, 0.0), Vector3(0.52, 4.6, 0.52), white)]
	var core: Array = []
	var cards: Array = []
	var tiers := 7
	for t in range(tiers):
		var ft := float(t) / float(tiers - 1)
		var tier_y := lerpf(1.9, top - 1.1, ft)
		var tier_r := lerpf(2.25, 0.55, pow(ft, 0.85))
		core.append(_dz_scatter_part(cone, Vector3(0.0, tier_y + 0.6, 0.0), Vector3(tier_r * 1.02, 2.1, tier_r * 1.02), Color(0.016, 0.044, 0.014)))
		for si in range(6):
			var ang := TAU * float(si) / 6.0 + float(t) * 0.52 + rng.randf_range(-0.10, 0.10)
			var out := Vector3(cos(ang), 0.0, sin(ang))
			var tangent := Vector3(-out.z, 0.0, out.x)
			var b_start := Vector3(0.0, tier_y + 0.45, 0.0)
			var b_end := Vector3(out.x * tier_r * 1.02, tier_y - tier_r * 0.16, out.z * tier_r * 1.02)
			trunk.append(_gf_branch_part(branch_prim, b_start, b_end, 0.045, white))
			var centre := Vector3(out.x * tier_r * 0.78, tier_y + 0.26, out.z * tier_r * 0.78)
			var right := out * (tier_r * 0.78)
			right.y = -tier_r * rng.randf_range(0.22, 0.34)
			var upv := tangent * (tier_r * 0.46)
			var b := rng.randf_range(0.78, 1.05) + ft * 0.08
			cards.append({"c": centre, "r": right, "u": upv, "n": Vector3.UP, "col": Color(b, b, b), "flip": rng.randf() < 0.5})
	core.append(_dz_scatter_part(cone, Vector3(0.0, top - 0.35, 0.0), Vector3(0.55, 1.5, 0.55), Color(0.020, 0.052, 0.016)))
	var mesh := _gf_tree_mesh(trunk, core, cards, bark_material)
	return _gf_apply_wind(mesh, "gf_spruce_spray.png", Color(1.0, 1.0, 1.0), 0.05)


func _gf_bush_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261999
	var sph := _dz_unit_sphere(7, 5)
	var branch_prim := _dz_unit_cyl(5, 0.55)
	var white := Color(1.0, 1.0, 1.0)
	var core_col := Color(0.032, 0.082, 0.024)
	var twigs: Array = []
	for i in range(5):
		var yaw := TAU * float(i) / 5.0 + rng.randf_range(-0.3, 0.3)
		var end := Vector3(cos(yaw) * rng.randf_range(0.3, 0.5), rng.randf_range(0.5, 0.8), sin(yaw) * rng.randf_range(0.3, 0.5))
		twigs.append(_gf_branch_part(branch_prim, Vector3(0.0, 0.0, 0.0), end, 0.035, Color(0.09, 0.055, 0.030)))
	var core: Array = [
		_dz_scatter_part(sph, Vector3(0.0, 0.45, 0.0), Vector3(1.35, 0.78, 1.26), core_col),
		_dz_scatter_part(sph, Vector3(0.45, 0.6, 0.22), Vector3(0.88, 0.55, 0.82), core_col),
		_dz_scatter_part(sph, Vector3(-0.48, 0.54, -0.26), Vector3(0.8, 0.5, 0.75), core_col),
	]
	var cards: Array = []
	for ci in range(7):
		var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.05, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		var centre := Vector3(dir.x * 0.6, 0.56 + dir.y * 0.34, dir.z * 0.6)
		_gf_add_cluster(cards, centre, 1.05, rng)
	var mesh := _gf_tree_mesh([], twigs + core, cards, null)
	return _gf_apply_wind(mesh, "gf_leaf_cluster.png", Color(1.0, 1.0, 1.0), 0.06)


# Crossed vertical cards for ground tufts (grass, ferns).
func _gf_cross_mesh(planes: int, half_w: float, height: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var base_col := Color(0.5, 0.55, 0.45)
	var top_col := Color(1.0, 1.0, 1.0)
	for pi in range(planes):
		var ang := float(pi) * PI / float(planes)
		var right := Vector3(cos(ang), 0.0, sin(ang)) * half_w
		var corners: Array = [
			Vector3(-right.x, 0.0, -right.z), Vector3(right.x, 0.0, right.z),
			Vector3(right.x, height, right.z), Vector3(-right.x, height, -right.z),
		]
		var uv_corners: Array = [Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0)]
		var cols: Array = [base_col, base_col, top_col, top_col]
		for vi in [0, 1, 2, 0, 2, 3]:
			verts.append(corners[vi])
			normals.append(Vector3.UP)
			colors.append(cols[vi])
			uvs.append(uv_corners[vi])
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colors
	out[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh


func _gf_vnoise3(lat: PackedFloat32Array, p: Vector3) -> float:
	# Trilinear value noise on a wrapped 8^3 lattice — the coherent
	# low-frequency field that shapes real-looking boulders.
	const LS := 8
	var xi := int(floor(p.x))
	var yi := int(floor(p.y))
	var zi := int(floor(p.z))
	var xf := p.x - float(xi)
	var yf := p.y - float(yi)
	var zf := p.z - float(zi)
	var xs := xf * xf * (3.0 - 2.0 * xf)
	var ys := yf * yf * (3.0 - 2.0 * yf)
	var zs := zf * zf * (3.0 - 2.0 * zf)
	var x0 := posmod(xi, LS)
	var x1 := posmod(xi + 1, LS)
	var y0 := posmod(yi, LS) * LS
	var y1 := posmod(yi + 1, LS) * LS
	var z0 := posmod(zi, LS) * LS * LS
	var z1 := posmod(zi + 1, LS) * LS * LS
	var c000 := lat[x0 + y0 + z0]
	var c100 := lat[x1 + y0 + z0]
	var c010 := lat[x0 + y1 + z0]
	var c110 := lat[x1 + y1 + z0]
	var c001 := lat[x0 + y0 + z1]
	var c101 := lat[x1 + y0 + z1]
	var c011 := lat[x0 + y1 + z1]
	var c111 := lat[x1 + y1 + z1]
	return lerpf(lerpf(lerpf(c000, c100, xs), lerpf(c010, c110, xs), ys),
		lerpf(lerpf(c001, c101, xs), lerpf(c011, c111, xs), ys), zs)


func _gf_rock_mid(verts: Array, cache: Dictionary, a: int, b: int) -> int:
	var key := mini(a, b) * 100000 + maxi(a, b)
	if cache.has(key):
		return int(cache[key])
	var m: Vector3 = (verts[a] + verts[b]) * 0.5
	verts.append(m.normalized())
	var idx := verts.size() - 1
	cache[key] = idx
	return idx


func _gf_rock_mesh(seed_i: int, sharpness: float) -> ArrayMesh:
	# 0.2.59 ground-cover pass: icosphere displaced by 3-D value noise
	# (broad shape + chip detail), three random planar joint cuts and
	# a flattened seat. Flat-shaded facets; vertex colours carry moss
	# on damp flat tops and a dark soil skirt at the base, while the
	# triplanar gf_rock_gray PBR set does the micro-surface.
	var rng := RandomNumberGenerator.new()
	rng.seed = 41000 + seed_i * 131
	const LS := 8
	var lat := PackedFloat32Array()
	lat.resize(LS * LS * LS)
	for li in range(lat.size()):
		lat[li] = rng.randf()
	var t := 1.6180339887
	var src: Array = []
	for v in [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
			Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
			Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]:
		src.append((v as Vector3).normalized())
	var faces: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var cache: Dictionary = {}
	for sub in range(2):
		var nf: Array = []
		for f in faces:
			var a := int(f[0])
			var b := int(f[1])
			var c := int(f[2])
			var ab := _gf_rock_mid(src, cache, a, b)
			var bc := _gf_rock_mid(src, cache, b, c)
			var ca := _gf_rock_mid(src, cache, c, a)
			nf.append([a, ab, ca])
			nf.append([b, bc, ab])
			nf.append([c, ca, bc])
			nf.append([ab, bc, ca])
		faces = nf
	var planes: Array = []
	for pi in range(3):
		var pn := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.5, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		planes.append(Vector4(pn.x, pn.y, pn.z, rng.randf_range(0.55, 0.85)))
	var stretch := Vector3(rng.randf_range(0.85, 1.25), rng.randf_range(0.62, 0.90), rng.randf_range(0.85, 1.25))
	var disp := PackedVector3Array()
	disp.resize(src.size())
	var broad := PackedFloat32Array()
	broad.resize(src.size())
	for vi in range(src.size()):
		var p: Vector3 = src[vi]
		var n1 := _gf_vnoise3(lat, p * 1.7 + Vector3(2.0, 2.0, 2.0))
		var n2 := _gf_vnoise3(lat, p * 4.6 + Vector3(5.0, 1.0, 7.0))
		var n3 := _gf_vnoise3(lat, p * 9.0 + Vector3(1.0, 6.0, 3.0))
		broad[vi] = n1
		var r := 1.0 + (n1 - 0.5) * 0.66 + (n2 - 0.5) * 0.26 * sharpness + (n3 - 0.5) * 0.10 * sharpness
		var dp := p * clampf(r, 0.5, 1.45)
		for plv in planes:
			var pl: Vector4 = plv
			var pn2 := Vector3(pl.x, pl.y, pl.z)
			var dist := dp.dot(pn2)
			if dist > pl.w:
				dp -= pn2 * (dist - pl.w)
		if dp.y < -0.32:
			dp.y = -0.32 + (dp.y + 0.32) * 0.18
		disp[vi] = Vector3(dp.x * stretch.x, dp.y * stretch.y, dp.z * stretch.z)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var moss_col := Color(0.52, 0.72, 0.42)
	var soil_col := Color(0.46, 0.39, 0.31)
	for ti in range(faces.size()):
		var f: Array = faces[ti]
		var ia := int(f[0])
		var ib := int(f[1])
		var ic := int(f[2])
		var a := disp[ia]
		var b := disp[ib]
		var c := disp[ic]
		var n := (b - a).cross(c - a)
		if n.length_squared() < 0.0000001:
			continue
		n = n.normalized()
		var face_broad := (broad[ia] + broad[ib] + broad[ic]) / 3.0
		var moss := smoothstep(0.35, 0.85, n.y) * smoothstep(0.45, 0.75, face_broad)
		var shade := 0.86 + _hash01(ti * 7 + seed_i, seed_i * 13 + ti) * 0.24
		var base_col := Color(0.94 * shade, 0.94 * shade, 0.93 * shade)
		base_col = base_col.lerp(moss_col, moss * 0.55)
		for v in [a, b, c]:
			var soil := smoothstep(0.02, -0.28, v.y)
			verts.append(v)
			normals.append(n)
			colors.append(base_col.lerp(soil_col, soil * 0.6))
			uvs.append(Vector2.ZERO)
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colors
	out[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh


func _gf_rock_cluster_mesh(seed_i: int) -> ArrayMesh:
	# Rock formation: one hero boulder plus two satellites leaning on
	# it — reads as a natural outcrop instead of a lone ball.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(_gf_rock_mesh(seed_i * 3, 1.15), 0, Transform3D.IDENTITY)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777 + seed_i * 17
	for sat in range(2):
		var ang := rng.randf_range(0.0, TAU)
		var off := Vector3(cos(ang) * 0.85, -0.10, sin(ang) * 0.85)
		var bs := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * rng.randf_range(0.45, 0.62))
		st.append_from(_gf_rock_mesh(seed_i * 3 + 1 + sat, 1.2), 0, Transform3D(bs, off))
	return st.commit()


func _gf_grass_blades_mesh(seed_i: int) -> ArrayMesh:
	# 0.2.59: real geometry grass — 30 curved, tapering blades per
	# tuft instead of flat alpha cards. Two segments per blade so the
	# wind shader height mask bends them smoothly; colour comes from
	# the shader root-to-tip gradient, so no texture is needed.
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100 + seed_i * 37
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var wscales := [1.0, 0.62, 0.05]
	for blade in range(30):
		var ra := rng.randf_range(0.0, TAU)
		var rr := sqrt(rng.randf()) * 0.5
		var root := Vector3(cos(ra) * rr, 0.0, sin(ra) * rr)
		var yaw := rng.randf_range(0.0, TAU)
		var right := Vector3(cos(yaw), 0.0, sin(yaw))
		var fwd := Vector3(-sin(yaw), 0.0, cos(yaw))
		var lean := fwd.rotated(Vector3.UP, rng.randf_range(-0.8, 0.8))
		var h := rng.randf_range(0.5, 0.95)
		var w := rng.randf_range(0.045, 0.075)
		var bend := rng.randf_range(0.10, 0.30)
		var nrm := (fwd * 0.6 + Vector3.UP * 0.8).normalized()
		var rows: Array = []
		for row in range(3):
			var tt := float(row) * 0.5
			var centre := root + Vector3.UP * (tt * h) + lean * (bend * tt * tt)
			rows.append([centre - right * w * 0.5 * float(wscales[row]), centre + right * w * 0.5 * float(wscales[row])])
		for seg in range(2):
			var a0: Vector3 = rows[seg][0]
			var b0: Vector3 = rows[seg][1]
			var a1: Vector3 = rows[seg + 1][0]
			var b1: Vector3 = rows[seg + 1][1]
			var vseq: Array = [a0, b0, b1, a0, b1, a1]
			var useq: Array = [Vector2(0.0, float(seg) * 0.5), Vector2(1.0, float(seg) * 0.5),
				Vector2(1.0, float(seg + 1) * 0.5), Vector2(0.0, float(seg) * 0.5),
				Vector2(1.0, float(seg + 1) * 0.5), Vector2(0.0, float(seg + 1) * 0.5)]
			for k in range(6):
				verts.append(vseq[k])
				normals.append(nrm)
				colors.append(Color.WHITE)
				uvs.append(useq[k])
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colors
	out[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh


func _gf_roadside_grass(buckets: Dictionary, base: float, sink: float) -> int:
	# 0.2.59: dense blade tufts hugging every road verge — the strip
	# of ground the player actually looks at. Generated from road
	# samples at build time, so the world data file stays untouched.
	# Relative-height rejects keep tufts off bridges, tunnel roofs
	# and lake beds.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261159
	var added := 0
	for road_variant in data.get("roads", []):
		var road: Dictionary = road_variant
		var samples: Array = road.get("samples", [])
		var half_w := _f(road, "widthM", 10.0) * 0.5
		for si in range(0, samples.size() - 1, 2):
			var a := _sample_point(samples[si])
			var b := _sample_point(samples[si + 1])
			var dir2 := Vector2(b.x - a.x, b.z - a.z)
			if dir2.length_squared() < 0.01:
				continue
			dir2 = dir2.normalized()
			var perp := Vector2(-dir2.y, dir2.x)
			for side in [-1.0, 1.0]:
				var off := half_w + rng.randf_range(0.7, 4.6)
				var along := rng.randf_range(-3.0, 3.0)
				var px := a.x + perp.x * off * side + dir2.x * along
				var pz := a.z + perp.y * off * side + dir2.y * along
				if _gf_in_field(px, pz):
					continue
				var gy := height_at(px, pz)
				if gy < a.y - 2.2 or gy > a.y + 4.5:
					continue
				var sc := base * rng.randf_range(0.8, 1.45)
				var pos := Vector3(px, gy - sink, pz)
				var key := "%d,%d" % [int(floor(px / DZ_CHUNK_M)), int(floor(pz / DZ_CHUNK_M))]
				if not buckets.has(key):
					buckets[key] = []
				(buckets[key] as Array).append(make_transform(pos, rng.randf_range(0.0, TAU), Vector3.ONE * sc))
				added += 1
	return added


func _build_forest_scatter() -> void:
	_gf_scatter_build([])


func _gf_scatter_build(kinds_filter: Array) -> void:
	var root := Node3D.new()
	root.name = "ForestScatter"
	add_child(root)
	if _dz_scatter_material == null:
		_dz_scatter_material = StandardMaterial3D.new()
		_dz_scatter_material.vertex_color_use_as_albedo = true
		_dz_scatter_material.roughness = 0.95
		_dz_scatter_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var cyl7 := _dz_unit_cyl(7, 0.4)
	var cyl11 := _dz_unit_cyl(11, 0.05)
	var sph := _dz_unit_sphere(10, 7)
	var rock_mat := _material("gf_rock_gray_mat", "gf_rock_gray.jpg", "gf_rock_gray_normal.jpg", Color(0.92, 0.92, 0.90), 1.0, 0.0, Vector3(0.16, 0.16, 0.16), true, "gf_rock_gray_roughness.jpg")
	rock_mat.vertex_color_use_as_albedo = true
	var bark := Color(0.09, 0.055, 0.030)
	# 0.2.57 photoreal-leaning trees: textured bark trunks, dark
	# crown cores and alpha-cut foliage cards (painted leaf/needle
	# sprays) instead of solid plastic cones and blobs.
	var bark_oak_mat := _material("gf_bark_oak_mat", "oak_bark.jpg", "oak_bark_normal.jpg", Color(0.88, 0.83, 0.78), 1.0, 0.0, Vector3(1.2, 2.2, 1.2), false)
	var bark_pine_mat := _material("gf_bark_pine_mat", "gf_pine_bark.jpg", "gf_pine_bark_normal.jpg", Color(0.95, 0.90, 0.85), 1.0, 0.0, Vector3(1.2, 2.0, 1.2), false, "gf_pine_bark_roughness.jpg")
	var bark_spruce_mat := _material("gf_bark_spruce_mat", "gf_pine_bark.jpg", "gf_pine_bark_normal.jpg", Color(0.60, 0.57, 0.54), 1.0, 0.0, Vector3(1.1, 1.8, 1.1), false, "gf_pine_bark_roughness.jpg")
	var bark_birch_mat := _material("gf_bark_birch_mat", "gf_birch_bark.jpg", "gf_birch_bark_normal.jpg", Color(1.0, 1.0, 1.0), 0.85, 0.0, Vector3(1.0, 1.6, 1.0), false, "gf_birch_bark_roughness.jpg")
	var spruce_a := _gf_spruce_mesh(0, bark_spruce_mat)
	var spruce_b := _gf_spruce_mesh(1, bark_spruce_mat)
	var pine_meshes: Array = [_gf_pine_mesh(0, bark_pine_mat), _gf_pine_mesh(1, bark_pine_mat)]
	var birch_meshes: Array = [_gf_birch_mesh(0, bark_birch_mat), _gf_birch_mesh(1, bark_birch_mat)]
	var leafy_meshes: Array = [_gf_broadleaf_mesh(0, false, bark_oak_mat, "gf_leaf_cluster.png", Color(1.0, 1.0, 1.0)), _gf_broadleaf_mesh(1, false, bark_oak_mat, "gf_leaf_cluster.png", Color(1.0, 1.0, 1.0))]
	var oak_meshes: Array = [_gf_broadleaf_mesh(0, true, bark_oak_mat, "gf_leaf_cluster.png", Color(0.85, 0.92, 0.82)), _gf_broadleaf_mesh(1, true, bark_oak_mat, "gf_leaf_cluster.png", Color(0.85, 0.92, 0.82))]
	var dead_mesh := _dz_scatter_mesh([
		_dz_scatter_part(cyl7, Vector3(0, 1.9, 0), Vector3(0.45, 3.8, 0.45), Color(0.16, 0.13, 0.10), 0.0, 0.0, 0.06),
		_dz_scatter_part(cyl7, Vector3(0.8, 3.4, 0.1), Vector3(0.18, 2.0, 0.18), Color(0.16, 0.13, 0.10), 0.0, 0.0, -0.85),
		_dz_scatter_part(cyl7, Vector3(-0.7, 3.0, -0.2), Vector3(0.15, 1.7, 0.15), Color(0.18, 0.15, 0.11), 0.0, 0.35, 0.9),
	])
	var bush_card_mesh := _gf_bush_mesh()
	var fern_card_mesh := _gf_cross_mesh(3, 0.55, 0.95)
	var fern_mat := _create_foliage_wind_material(fern_card_mesh, "gf_fern_frond.png", Color(1.0, 1.0, 1.0), 0.30, 0.05, false)
	var flower_mesh := _dz_scatter_mesh([
		_dz_scatter_part(cyl7, Vector3(0, 0.26, 0), Vector3(0.05, 0.52, 0.05), Color(0.05, 0.12, 0.03)),
		_dz_scatter_part(sph, Vector3(0, 0.58, 0), Vector3(0.17, 0.17, 0.17), Color(0.55, 0.34, 0.02)),
		_dz_scatter_part(cyl7, Vector3(0.28, 0.22, 0.14), Vector3(0.05, 0.44, 0.05), Color(0.05, 0.12, 0.03)),
		_dz_scatter_part(sph, Vector3(0.28, 0.5, 0.14), Vector3(0.15, 0.15, 0.15), Color(0.62, 0.62, 0.57)),
		_dz_scatter_part(cyl7, Vector3(-0.24, 0.2, -0.1), Vector3(0.05, 0.4, 0.05), Color(0.05, 0.12, 0.03)),
		_dz_scatter_part(sph, Vector3(-0.24, 0.46, -0.1), Vector3(0.14, 0.14, 0.14), Color(0.24, 0.14, 0.38)),
	])
	var mushroom_mesh := _dz_scatter_mesh([
		_dz_scatter_part(cyl7, Vector3(0, 0.18, 0), Vector3(0.12, 0.36, 0.12), Color(0.42, 0.36, 0.26)),
		_dz_scatter_part(sph, Vector3(0, 0.4, 0), Vector3(0.44, 0.2, 0.44), Color(0.34, 0.09, 0.04)),
		_dz_scatter_part(cyl7, Vector3(0.3, 0.13, 0.18), Vector3(0.09, 0.26, 0.09), Color(0.42, 0.36, 0.26)),
		_dz_scatter_part(sph, Vector3(0.3, 0.29, 0.18), Vector3(0.3, 0.14, 0.3), Color(0.30, 0.08, 0.035)),
		_dz_scatter_part(cyl7, Vector3(-0.26, 0.1, -0.14), Vector3(0.08, 0.2, 0.08), Color(0.42, 0.36, 0.26)),
		_dz_scatter_part(sph, Vector3(-0.26, 0.22, -0.14), Vector3(0.24, 0.11, 0.24), Color(0.38, 0.12, 0.05)),
	])
	var stump_mesh := _dz_scatter_mesh([
		_dz_scatter_part(cyl7, Vector3(0, 0.27, 0), Vector3(0.85, 0.55, 0.85), Color(0.20, 0.135, 0.08)),
		_dz_scatter_part(sph, Vector3(0, 0.55, 0), Vector3(0.78, 0.1, 0.78), Color(0.36, 0.27, 0.18)),
	])
	var log_mesh := _dz_scatter_mesh([
		_dz_scatter_part(cyl7, Vector3(0, 0.26, 0), Vector3(0.5, 4.8, 0.5), Color(0.14, 0.09, 0.05), 0.0, PI * 0.5, 0.0),
		_dz_scatter_part(sph, Vector3(0.05, 0.52, -0.8), Vector3(0.45, 0.18, 1.6), Color(0.05, 0.11, 0.035)),
		_dz_scatter_part(cyl7, Vector3(0.35, 0.5, 1.2), Vector3(0.12, 0.8, 0.12), Color(0.14, 0.09, 0.05), 0.0, 0.0, -0.7),
	])
	var reed_parts: Array = []
	for ri in range(6):
		var rang := TAU * float(ri) / 6.0
		reed_parts.append(_dz_scatter_part(cyl7, Vector3(cos(rang) * 0.3, 0.75, sin(rang) * 0.3), Vector3(0.08, 1.55, 0.08), Color(0.07, 0.16, 0.05), 0.0, cos(rang) * 0.16, sin(rang) * 0.16))
		if ri % 2 == 0:
			reed_parts.append(_dz_scatter_part(cyl7, Vector3(cos(rang) * 0.38, 1.52, sin(rang) * 0.38), Vector3(0.09, 0.36, 0.09), Color(0.20, 0.12, 0.05), 0.0, cos(rang) * 0.16, sin(rang) * 0.16))
	var reed_mesh := _dz_scatter_mesh(reed_parts)
	var hay_mesh := _dz_scatter_mesh([
		_dz_scatter_part(cyl11, Vector3(0, 0.75, 0), Vector3(1.5, 1.25, 1.5), Color(0.46, 0.33, 0.10), 0.0, PI * 0.5, 0.0),
	])
	var wheat_mesh := _dz_scatter_mesh([
		_dz_scatter_part(cyl7, Vector3(0, 0.57, 0), Vector3(0.34, 1.15, 0.34), Color(0.44, 0.32, 0.09)),
		_dz_scatter_part(cyl7, Vector3(0.45, 0.5, 0.28), Vector3(0.3, 1.0, 0.3), Color(0.48, 0.35, 0.10)),
		_dz_scatter_part(cyl7, Vector3(-0.4, 0.53, -0.22), Vector3(0.31, 1.06, 0.31), Color(0.41, 0.29, 0.08)),
	])
	var corn_mesh := _dz_scatter_mesh([
		_dz_scatter_part(cyl7, Vector3(0, 0.95, 0), Vector3(0.09, 1.9, 0.09), Color(0.05, 0.13, 0.035)),
		_dz_scatter_part(cyl11, Vector3(0, 1.15, 0), Vector3(0.55, 0.95, 0.55), Color(0.055, 0.14, 0.038)),
		_dz_scatter_part(cyl7, Vector3(0.5, 0.85, 0.3), Vector3(0.08, 1.7, 0.08), Color(0.05, 0.13, 0.035)),
		_dz_scatter_part(cyl11, Vector3(0.5, 1.05, 0.3), Vector3(0.48, 0.85, 0.48), Color(0.05, 0.13, 0.035)),
	])
	var sunflower_mesh := _dz_scatter_mesh([
		_dz_scatter_part(cyl7, Vector3(0, 0.85, 0), Vector3(0.08, 1.7, 0.08), Color(0.05, 0.12, 0.03)),
		_dz_scatter_part(sph, Vector3(0.12, 1.78, 0), Vector3(0.56, 0.56, 0.16), Color(0.56, 0.37, 0.03), 0.0, 0.0, 0.35),
		_dz_scatter_part(sph, Vector3(0.16, 1.78, 0.02), Vector3(0.34, 0.34, 0.18), Color(0.18, 0.10, 0.03), 0.0, 0.0, 0.35),
		_dz_scatter_part(cyl7, Vector3(0.55, 0.75, 0.35), Vector3(0.07, 1.5, 0.07), Color(0.05, 0.12, 0.03)),
		_dz_scatter_part(sph, Vector3(0.64, 1.56, 0.35), Vector3(0.46, 0.46, 0.14), Color(0.56, 0.37, 0.03), 0.0, 0.0, 0.3),
	])
	# 0.2.59: value-noise boulders with joint cuts, moss and soil
	# skirts; large rocks are three-boulder outcrop clusters.
	var rock_small_meshes: Array = [_gf_rock_mesh(1, 1.0), _gf_rock_mesh(2, 1.0), _gf_rock_mesh(3, 1.1), _gf_rock_mesh(4, 0.9)]
	var rock_medium_meshes: Array = [_gf_rock_mesh(11, 1.1), _gf_rock_mesh(12, 1.0), _gf_rock_mesh(13, 1.25)]
	var rock_large_meshes: Array = [_gf_rock_cluster_mesh(21), _gf_rock_cluster_mesh(22), _gf_rock_cluster_mesh(23)]
	# 0.2.59: geometric grass blades, no alpha card — the wind shader
	# runs in its no-texture root-to-tip gradient mode.
	var grass_blade_meshes: Array = [_gf_grass_blades_mesh(1), _gf_grass_blades_mesh(2), _gf_grass_blades_mesh(3)]
	var grass_mat := _create_foliage_wind_material(grass_blade_meshes[0], "", Color(1.18, 1.12, 0.78), 0.0, 0.06, false)
	var cfg := {
		"spruce": {"meshes": [spruce_a, spruce_b], "material": null, "base": 1.45, "range": 470.0, "shadow": true, "sink": 0.12, "tree": true, "foliage_every": 14},
		"pine": {"meshes": pine_meshes, "material": null, "base": 1.5, "range": 470.0, "shadow": true, "sink": 0.12, "tree": true, "foliage_every": 14},
		"birch": {"meshes": birch_meshes, "material": null, "base": 1.4, "range": 430.0, "shadow": true, "sink": 0.10, "tree": true, "foliage_every": 14},
		"leafy": {"meshes": leafy_meshes, "material": null, "base": 1.4, "range": 420.0, "shadow": true, "sink": 0.12, "tree": true, "foliage_every": 14},
		"oak": {"meshes": oak_meshes, "material": null, "base": 1.5, "range": 430.0, "shadow": true, "sink": 0.15, "tree": true, "foliage_every": 8},
		"dead_tree": {"mesh": dead_mesh, "material": bark_spruce_mat, "base": 1.2, "range": 370.0, "shadow": true, "sink": 0.06, "collider_r": 0.30, "collider_h": 2.6},
		"bush": {"mesh": bush_card_mesh, "material": null, "base": 1.0, "range": 200.0, "shadow": false, "sink": 0.14, "foliage_every": 8},
		"fern": {"mesh": fern_card_mesh, "material": fern_mat, "base": 1.1, "range": 165.0, "shadow": false, "sink": 0.06},
		"flower": {"mesh": flower_mesh, "base": 1.0, "range": 130.0, "shadow": false, "sink": 0.02},
		"mushroom": {"mesh": mushroom_mesh, "base": 1.0, "range": 110.0, "shadow": false, "sink": 0.02},
		"stump": {"mesh": stump_mesh, "base": 1.0, "range": 260.0, "shadow": true, "sink": 0.05, "collider_r": 0.42, "collider_h": 0.6},
		"fallen_log": {"mesh": log_mesh, "base": 1.0, "range": 280.0, "shadow": true, "sink": 0.05, "collider_r": 0.55, "collider_h": 0.7},
		"reed": {"mesh": reed_mesh, "base": 1.0, "range": 210.0, "shadow": false, "sink": 0.18},
		"hay_bale": {"mesh": hay_mesh, "base": 1.0, "range": 300.0, "shadow": true, "sink": 0.04, "collider_r": 0.8, "collider_h": 1.2},
		"crop_wheat": {"mesh": wheat_mesh, "base": 1.15, "range": 330.0, "shadow": false, "sink": 0.03},
		"crop_corn": {"mesh": corn_mesh, "base": 1.15, "range": 330.0, "shadow": false, "sink": 0.03},
		"crop_sunflower": {"mesh": sunflower_mesh, "base": 1.15, "range": 330.0, "shadow": false, "sink": 0.03},
		"grass_tuft": {"meshes": grass_blade_meshes, "material": grass_mat, "base": 1.25, "range": 95.0, "shadow": false, "sink": 0.02},
		"rock_small": {"meshes": rock_small_meshes, "material": rock_mat, "base": 0.55, "range": 210.0, "shadow": false, "sink": 0.16},
		"rock_medium": {"meshes": rock_medium_meshes, "material": rock_mat, "base": 1.15, "range": 370.0, "shadow": true, "sink": 0.22, "collider_r": 0.72, "collider_h": 1.2},
		"rock_large": {"meshes": rock_large_meshes, "material": rock_mat, "base": 2.7, "range": 900.0, "shadow": true, "sink": 0.45, "collider_r": 1.10, "collider_h": 1.05},
	}
	var scatter: Dictionary = _dz_data().get("scatter", {})
	var total := 0
	var trees := 0
	for kind_variant in cfg.keys():
		var kind := String(kind_variant)
		if not kinds_filter.is_empty() and not kinds_filter.has(kind):
			continue
		var conf: Dictionary = cfg[kind]
		var items: Array = scatter.get(kind, [])
		if items.is_empty():
			continue
		var buckets: Dictionary = {}
		var base := float(conf.get("base", 1.0))
		var sink := float(conf.get("sink", 0.05))
		var collider_r := float(conf.get("collider_r", 0.0))
		var collider_h := float(conf.get("collider_h", 2.0))
		var is_tree := bool(conf.get("tree", false))
		var foliage_every := int(conf.get("foliage_every", 0))
		var item_index := 0
		for item_variant in items:
			var item: Array = item_variant
			item_index += 1
			if item.size() < 4:
				continue
			var px := float(item[0])
			var pz := float(item[1])
			var sc := float(item[2]) * base
			var pyaw := float(item[3])
			var pos := Vector3(px, height_at(px, pz) - sink, pz)
			var key := "%d,%d" % [int(floor(px / DZ_CHUNK_M)), int(floor(pz / DZ_CHUNK_M))]
			if not buckets.has(key):
				buckets[key] = []
			(buckets[key] as Array).append(make_transform(pos, pyaw, Vector3.ONE * sc))
			total += 1
			if is_tree:
				trees += 1
			if collider_r > 0.0:
				_add_cylinder_collider(Vector3(px, pos.y + collider_h * 0.5, pz), collider_r * sc, collider_h * sc)
			elif is_tree and _gf_near_road(px, pz, 22.0):
				# Only roadside trees need physics; deep forest stays
				# collider-free so the streaming grid stays light.
				_add_cylinder_collider(Vector3(px, pos.y + 1.5 * sc, pz), 0.34 * sc, 3.0 * sc)
			elif kind == "rock_small" and sc > 0.70:
				_add_cylinder_collider(Vector3(px, pos.y + 0.30 * sc, pz), 0.60 * sc, 1.1 * sc)
			if foliage_every > 0 and item_index % foliage_every == 0:
				_foliage_points.append(pos)
		if kind == "grass_tuft":
			total += _gf_roadside_grass(buckets, base, sink)
		var kind_meshes: Array = conf.get("meshes", [])
		var kind_mat: Material = conf.get("material", _dz_scatter_material) as Material
		for key_variant in buckets.keys():
			var bucket_xforms: Array = buckets[key_variant]
			if kind_meshes.is_empty():
				_dz_emit_multimesh(root, conf["mesh"] as Mesh, kind_mat, bucket_xforms, "GfScatter_" + kind, float(conf.get("range", 300.0)), bool(conf.get("shadow", false)))
			else:
				for vi in range(kind_meshes.size()):
					var sub: Array = []
					for ti in range(bucket_xforms.size()):
						if ti % kind_meshes.size() == vi:
							sub.append(bucket_xforms[ti])
					_dz_emit_multimesh(root, kind_meshes[vi] as Mesh, kind_mat, sub, "GfScatter_" + kind + "_v" + str(vi), float(conf.get("range", 300.0)), bool(conf.get("shadow", false)))
	_gf_scatter_total_acc += total
	_gf_scatter_trees_acc += trees
	_enhancement_stats["forest_scatter"] = _gf_scatter_total_acc
	_enhancement_stats["forest_trees"] = _gf_scatter_trees_acc
	_enhancement_stats["forest_scatter_0254"] = true
	_enhancement_stats["forest_photoreal_trees_0257"] = true
	_enhancement_stats["forest_ground_cover_0259"] = true


func _build_forest_extras() -> void:
	var root := Node3D.new()
	root.name = "ForestExtras"
	add_child(root)
	# Falling leaves around the car (0.2.58): world-locked particles,
	# the emitter recentres on the streaming focus every frame.
	var leaf_emitter := GPUParticles3D.new()
	leaf_emitter.name = "ForestFallingLeaves"
	leaf_emitter.amount = 170
	leaf_emitter.lifetime = 8.0
	leaf_emitter.local_coords = false
	leaf_emitter.visibility_aabb = AABB(Vector3(-70.0, -35.0, -70.0), Vector3(140.0, 70.0, 140.0))
	var leaf_pm := ParticleProcessMaterial.new()
	leaf_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	leaf_pm.emission_box_extents = Vector3(26.0, 4.0, 26.0)
	leaf_pm.direction = Vector3(0.0, -1.0, 0.0)
	leaf_pm.spread = 26.0
	leaf_pm.gravity = Vector3(0.25, -0.85, 0.1)
	leaf_pm.initial_velocity_min = 0.15
	leaf_pm.initial_velocity_max = 0.5
	leaf_pm.angular_velocity_min = -170.0
	leaf_pm.angular_velocity_max = 170.0
	leaf_pm.angle_min = -180.0
	leaf_pm.angle_max = 180.0
	leaf_pm.scale_min = 0.7
	leaf_pm.scale_max = 1.3
	leaf_pm.hue_variation_min = -0.07
	leaf_pm.hue_variation_max = 0.10
	leaf_emitter.process_material = leaf_pm
	var leaf_quad := QuadMesh.new()
	leaf_quad.size = Vector2(0.17, 0.17)
	leaf_quad.material = _gf_foliage_material("gf_fall_leaf_mat", "gf_leaf_single.png", Color(1.0, 1.0, 1.0))
	leaf_emitter.draw_pass_1 = leaf_quad
	root.add_child(leaf_emitter)
	_gf_leaf_emitter = leaf_emitter
	_enhancement_stats["forest_falling_leaves_0258"] = true
	# Deer herds: merged low-poly animals grazing the meadows and
	# clearings (static poses, one collider each).
	var deer_count := 0
	for group_variant in _dz_data().get("deerGroups", []):
		# Data ships herd centres {x, z, count}; expand them into
		# individual deer deterministically around the centre.
		var group: Dictionary = group_variant
		var gx := _f(group, "x")
		var gz := _f(group, "z")
		var group_count := int(group.get("count", 3))
		for di in range(group_count):
			var ang := _hash01(int(gx) + di * 17, int(gz) + di * 29) * TAU
			var rad := 4.0 + _hash01(int(gx) + di * 31, int(gz) + di * 13) * 16.0
			var dx := gx + cos(ang) * rad
			var dz := gz + sin(ang) * rad
			var dyaw := _hash01(int(dx) * 3 + di * 7, int(dz) * 7 + di) * TAU
			var o := Vector3(dx, height_at(dx, dz), dz)
			var dbasis := Basis(Vector3.UP, dyaw)
			var graze := int(absf(dx) * 3.0 + absf(dz) * 7.0) % 3 == 0
			_dz_lbox("gf_deer", o, dbasis, Vector3(0.0, 1.02, 0.0), Vector3(0.52, 0.62, 1.35))
			_dz_lbox("gf_deer_belly", o, dbasis, Vector3(0.0, 0.78, 0.05), Vector3(0.46, 0.3, 1.1))
			if graze:
				_dz_lbox("gf_deer", o, dbasis, Vector3(0.0, 0.95, -0.85), Vector3(0.2, 0.62, 0.2), 0.0, 0.85, 0.0)
				_dz_lbox("gf_deer", o, dbasis, Vector3(0.0, 0.62, -1.15), Vector3(0.26, 0.3, 0.5), 0.0, 0.5, 0.0)
			else:
				_dz_lbox("gf_deer", o, dbasis, Vector3(0.0, 1.45, -0.75), Vector3(0.2, 0.65, 0.2), 0.0, -0.35, 0.0)
				_dz_lbox("gf_deer", o, dbasis, Vector3(0.0, 1.72, -1.02), Vector3(0.26, 0.3, 0.52))
				if int(absf(dx) * 5.0 + absf(dz)) % 2 == 0:
					for ax in [-0.12, 0.12]:
						_dz_lbox("dz_sign_cream", o, dbasis, Vector3(ax, 2.05, -0.95), Vector3(0.06, 0.45, 0.06), 0.0, 0.3, ax * 2.4)
			for lx in [-0.18, 0.18]:
				for lz in [-0.5, 0.5]:
					_dz_lbox("gf_deer", o, dbasis, Vector3(lx, 0.38, lz), Vector3(0.11, 0.76, 0.11))
			_dz_lbox("gf_deer_belly", o, dbasis, Vector3(0.0, 1.12, 0.72), Vector3(0.16, 0.3, 0.1), 0.0, 0.4, 0.0)
			_add_cylinder_collider(o + dbasis * Vector3(0.0, 0.9, 0.0), 0.55, 1.8)
			deer_count += 1
	var deer_chunks := _dz_flush_merge(root)
	_enhancement_stats["forest_deer"] = deer_count
	_enhancement_stats["forest_deer_chunks"] = deer_chunks
	# Bird flocks: three V-formations circling the lake, meadows and
	# summit; animated in _gf_animate_birds from _dz_animate.
	_gf_bird_flocks.clear()
	var bird_mesh := _dz_scatter_mesh([
		_dz_scatter_part(_dz_unit_box(), Vector3(0, 0, 0), Vector3(1.5, 0.05, 0.34), Color(0.08, 0.08, 0.10)),
		_dz_scatter_part(_dz_unit_box(), Vector3(0, 0, 0.05), Vector3(0.22, 0.1, 0.85), Color(0.10, 0.10, 0.12)),
	])
	var bird_mat := _dz_material("gf_bird")
	var flock_specs := [
		[3050.0, 2200.0, 62.0, 340.0, 0.055],
		[1900.0, 1900.0, 74.0, 420.0, 0.045],
		[1850.0, 420.0, 196.0, 380.0, 0.05],
	]
	for fi in range(flock_specs.size()):
		var spec: Array = flock_specs[fi]
		var flock := Node3D.new()
		flock.name = "BirdFlock%d" % fi
		root.add_child(flock)
		for bi in range(7):
			var bird := MeshInstance3D.new()
			bird.mesh = bird_mesh
			bird.material_override = bird_mat
			bird.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var row := float((bi + 1) / 2)
			var side := 1.0 if bi % 2 == 0 else -1.0
			if bi == 0:
				side = 0.0
				row = 0.0
			bird.position = Vector3(side * row * 3.2, -row * 0.5, row * 3.4)
			flock.add_child(bird)
		_gf_bird_flocks.append({
			"node": flock,
			"cx": float(spec[0]), "cz": float(spec[1]),
			"h": float(spec[2]), "r": float(spec[3]),
			"speed": float(spec[4]), "phase": float(fi) * 2.1,
		})
	_enhancement_stats["forest_bird_flocks"] = _gf_bird_flocks.size()
	# Chimney smoke over the village and farmsteads.
	var smoke_count := 0
	for point_variant in _dz_data().get("smokePoints", []):
		var point: Array = point_variant
		if point.size() < 2:
			continue
		var sx := float(point[0])
		var sz := float(point[1])
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		process.emission_sphere_radius = 0.3
		process.direction = Vector3(0.0, 1.0, 0.0)
		process.spread = 10.0
		process.initial_velocity_min = 1.1
		process.initial_velocity_max = 1.9
		process.gravity = Vector3(0.35, 0.55, 0.0)
		process.damping_min = 0.1
		process.damping_max = 0.4
		process.scale_min = 0.8
		process.scale_max = 2.2
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.82, 0.83, 0.85, 0.0))
		ramp.set_color(1, Color(0.82, 0.83, 0.85, 0.0))
		ramp.add_point(0.15, Color(0.82, 0.83, 0.85, 0.34))
		ramp.add_point(0.7, Color(0.84, 0.85, 0.87, 0.16))
		var ramp_texture := GradientTexture1D.new()
		ramp_texture.gradient = ramp
		ramp_texture.width = 32
		process.color_ramp = ramp_texture
		var smoke_mat := StandardMaterial3D.new()
		smoke_mat.albedo_color = Color.WHITE
		smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		smoke_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		smoke_mat.vertex_color_use_as_albedo = true
		var quad := QuadMesh.new()
		quad.size = Vector2(1.6, 1.6)
		quad.material = smoke_mat
		var emitter := GPUParticles3D.new()
		emitter.name = "ChimneySmoke"
		emitter.amount = 22
		emitter.lifetime = 4.2
		emitter.randomness = 0.7
		emitter.local_coords = false
		emitter.process_material = process
		emitter.draw_pass_1 = quad
		emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		emitter.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		emitter.visibility_aabb = AABB(Vector3(-14.0, -2.0, -14.0), Vector3(28.0, 26.0, 28.0))
		emitter.position = Vector3(sx, height_at(sx, sz) + 6.4, sz)
		emitter.emitting = true
		root.add_child(emitter)
		smoke_count += 1
	_enhancement_stats["forest_smoke_points"] = smoke_count
	_enhancement_stats["forest_extras_0254"] = true


func _gf_animate_birds() -> void:
	for entry in _gf_bird_flocks:
		var flock := entry["node"] as Node3D
		if flock == null or not is_instance_valid(flock):
			continue
		var ang := _elapsed * float(entry["speed"]) + float(entry["phase"])
		var r := float(entry["r"])
		flock.position = Vector3(
			float(entry["cx"]) + cos(ang) * r,
			float(entry["h"]) + sin(_elapsed * 0.23 + float(entry["phase"])) * 3.0,
			float(entry["cz"]) + sin(ang) * r)
		flock.rotation.y = -ang
		var flap := sin(_elapsed * 7.0 + float(entry["phase"])) * 0.35
		for bi in range(flock.get_child_count()):
			var bird := flock.get_child(bi) as Node3D
			if bird != null:
				bird.rotation.z = flap if bi % 2 == 0 else -flap
