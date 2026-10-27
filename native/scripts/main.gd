extends Node3D

## Native game bootstrap: world, player vehicle, camera rig and HUD.
## This is the first playable Godot vertical slice for the native rebuild.
## Future systems should be added as separate native nodes/scripts
## rather than growing this coordinator.

const WorldBuilderScript := preload("res://scripts/world_builder.gd")
const VehicleScript := preload("res://scripts/vehicle_controller.gd")
const SpeedPostScript := preload("res://scripts/speed_post.gd")
const HudScript := preload("res://scripts/hud.gd")

const TIME_MODES: Array[String] = ["day", "sunset", "night"]
const CAMERA_CHASE := 0
const CAMERA_HOOD := 1
const CAMERA_TOP := 2

var _world: NativeWorldBuilder
var _vehicle: NativeVehicle
var _hud: NativeHud
var _camera: Camera3D
var _speed_post: NativeSpeedPost
var _camera_mode := CAMERA_CHASE
var _snap_camera := true
var _time_index := 0
var _smoke_mode := false
var _smoke_frames := 0
var _smoke_completed := false
var render_quality_state := {}
var _render_scale := 1.0
var _render_quality_accumulated_time := 0.0
var _render_quality_frames := 0
var _render_quality_vote_direction := 0
var _render_quality_vote_count := 0
var _camera_follow_yaw := 0.0
var _camera_target_smooth := Vector3.ZERO
var _camera_drift_offset_smooth := 0.0
var _camera_smoothing_initialized := false


func _ready() -> void:
	_smoke_mode = OS.get_cmdline_user_args().has("--native-smoke") or OS.get_cmdline_args().has("--native-smoke")
	_parse_screenshot_request()
	Engine.max_fps = 0 if _screenshot_mode else 60
	if OS.has_feature("android"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_configure_render_quality(true)

	_world = WorldBuilderScript.new() as NativeWorldBuilder
	_world.name = "NativeWorld"
	add_child(_world)
	var stats := _world.build_world()
	print("[native] RichTown build stats: ", stats)
	if not _world.build_error.is_empty():
		push_error("Native world failed to build: %s" % _world.build_error)

	_vehicle = VehicleScript.new() as NativeVehicle
	add_child(_vehicle)
	_vehicle.set_world(_world)
	_vehicle.reset_requested.connect(_on_vehicle_reset_requested)
	_vehicle.reset_to_transform(_world.spawn_transform)
	_vehicle.global_transform = _world.spawn_transform

	# 0.2.5: all AI/parked traffic cars are removed by request.  The
	# freed CPU/GPU budget is spent on the denser static city instead;
	# there is deliberately no hidden traffic node or parked-car fleet.
	print("[native] Traffic removed: player vehicle only")

	_create_camera()
	_hud = HudScript.new() as NativeHud
	add_child(_hud)
	_hud.bind(_world, _vehicle)
	_hud.camera_requested.connect(_cycle_camera)
	_hud.time_requested.connect(_cycle_time)
	_hud.reset_requested.connect(_reset_vehicle_to_road)

	_apply_time_mode()
	_update_camera(0.0, true)
	print("[native] Nitches Horizon Godot alpha is ready")


func _configure_render_quality(initial: bool) -> void:
	var viewport := get_viewport()
	var is_android := OS.has_feature("android")
	if is_android:
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		# MSAA at full 3D cost does not make sense below 30 FPS. FXAA leaves
		# edges softer but preserves far more GPU time; the sharp UI remains
		# at display resolution because only the 3D buffer is scaled.
		viewport.msaa_3d = Viewport.MSAA_DISABLED
		viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		# 0.2.16: merged Blender parts and the plant pack now carry real
		# generated LOD chains again. Six threshold pixels makes the
		# phone use them at normal street viewing distances instead of
		# reserving simplification for almost-subpixel geometry.
		viewport.mesh_lod_threshold = 6.0
		if initial:
			_render_scale = 0.62
		viewport.scaling_3d_scale = _render_scale
	render_quality_state = {
		"android": is_android,
		"scale": _render_scale,
		"msaa": int(viewport.msaa_3d),
		"screen_space_aa": int(viewport.screen_space_aa),
		"adaptive": is_android,
		"evaluation_seconds": 2.5,
		"hysteresis_votes": 2,
		"min_scale": 0.42,
		"max_scale": 0.80,
		"mesh_lod_threshold": viewport.mesh_lod_threshold,
	}


func _update_adaptive_render_quality(delta: float) -> void:
	if not OS.has_feature("android") or delta <= 0.0:
		return
	_render_quality_accumulated_time += delta
	_render_quality_frames += 1
	# A 2.5-second evaluation window plus a repeated-vote requirement
	# avoids reallocating the 3D render target on every scenery change.
	# The target band is a stable 30-50 FPS rather than chasing 60 on a
	# phone that measured 8-12 FPS in the 0.2.14 city captures.
	if _render_quality_accumulated_time < 2.5:
		return
	var measured_fps := float(_render_quality_frames) / maxf(_render_quality_accumulated_time, 0.001)
	_render_quality_accumulated_time = 0.0
	_render_quality_frames = 0

	var desired_direction := 0
	if measured_fps < 30.0:
		desired_direction = -1
	elif measured_fps > 50.0:
		desired_direction = 1
	if desired_direction == 0:
		_render_quality_vote_direction = 0
		_render_quality_vote_count = 0
		return
	if desired_direction == _render_quality_vote_direction:
		_render_quality_vote_count += 1
	else:
		_render_quality_vote_direction = desired_direction
		_render_quality_vote_count = 1

	var required_votes := 1 if measured_fps < 24.0 else 2
	if _render_quality_vote_count < required_votes:
		return
	_render_quality_vote_count = 0
	var previous_scale := _render_scale
	if desired_direction < 0:
		var step := 0.06 if measured_fps < 18.0 else 0.04
		_render_scale = maxf(0.42, _render_scale - step)
	else:
		_render_scale = minf(0.80, _render_scale + 0.04)
	if not is_equal_approx(previous_scale, _render_scale):
		_configure_render_quality(false)


func _create_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "GameCamera"
	_camera.near = 0.12
	# RichTown's playable diagonal is about 1.4 km; 1.5 km still covers
	# corner-to-corner views while tightening depth precision and culling.
	_camera.far = 1500.0
	_camera.fov = 58.0
	add_child(_camera)
	_camera.make_current()
	_camera.current = true

	# Drive SpeedPost: fullscreen quad lives under the camera exactly as
	# Godot's advanced post-processing pattern prescribes.
	_speed_post = SpeedPostScript.new() as NativeSpeedPost
	_camera.add_child(_speed_post)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"camera_toggle"):
		_cycle_camera()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"time_toggle"):
		_cycle_time()
		get_viewport().set_input_as_handled()
	elif OS.has_feature("pc") and event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F11:
			_toggle_desktop_fullscreen()
			get_viewport().set_input_as_handled()


## 0.2.21 desktop parity: Windows/Linux run the identical game content,
## physics and HUD as Android.  F11 is purely a window-management
## shortcut for keyboards; it never changes gameplay state.
func _toggle_desktop_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _cycle_camera() -> void:
	_camera_mode = (_camera_mode + 1) % 3
	_snap_camera = true


func _cycle_time() -> void:
	_time_index = (_time_index + 1) % TIME_MODES.size()
	_apply_time_mode()


func _apply_time_mode() -> void:
	if _world == null:
		return
	var mode := TIME_MODES[_time_index]
	_world.set_time_of_day(mode)
	if _vehicle != null:
		_vehicle.set_headlights_enabled(mode != "day")


func _on_vehicle_reset_requested() -> void:
	_reset_vehicle_to_road()


func _reset_vehicle_to_road() -> void:
	if _world == null or _vehicle == null:
		return
	var target := _world.find_nearest_road_transform(_vehicle.global_position)
	_vehicle.reset_to_transform(target)
	_snap_camera = true


func _process(delta: float) -> void:
	_update_adaptive_render_quality(delta)
	if _camera != null and not _camera.is_current():
		_camera.make_current()
	_update_camera(delta, _snap_camera)
	_snap_camera = false
	if _smoke_mode and not _smoke_completed:
		_smoke_frames += 1
		if _smoke_frames >= 90:
			_smoke_completed = true
			_run_smoke_checks()


func _vehicle_horizontal_yaw() -> float:
	if _vehicle == null:
		return 0.0
	var forward := -_vehicle.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return _camera_follow_yaw
	forward = forward.normalized()
	return atan2(-forward.x, -forward.z)


func _update_camera(delta: float, snap: bool) -> void:
	if _camera == null or _vehicle == null:
		return

	var speed_kmh := _vehicle.get_absolute_speed_kmh()
	var speed_ratio := clampf(speed_kmh / 240.0, 0.0, 1.0)
	var raw_follow_yaw := _vehicle_horizontal_yaw()
	if snap or not _camera_smoothing_initialized or delta <= 0.0:
		_camera_follow_yaw = raw_follow_yaw
		_camera_drift_offset_smooth = 0.0
		_camera_smoothing_initialized = true
	elif _camera_mode == CAMERA_CHASE:
		# Yaw-only, exponentially damped follow heading.  The chase camera
		# no longer inherits every small suspension roll/pitch/yaw sample
		# from the RigidBody basis, a common source of visible twitching
		# even when the car's centre-of-mass path is smooth.
		_camera_follow_yaw = lerp_angle(_camera_follow_yaw, raw_follow_yaw, 1.0 - exp(-6.5 * delta))
	else:
		_camera_follow_yaw = raw_follow_yaw
	# The car stays at its real 1.0 scale; it reads larger because the
	# chase camera now sits closer/lower with a narrower lens.
	var desired_fov := 58.0 + speed_ratio * 14.0 + (5.0 if _vehicle.is_boosting() else 0.0)
	_camera.fov = lerpf(_camera.fov, desired_fov, 1.0 if snap else clampf(delta * 4.5, 0.0, 1.0))

	if _speed_post != null:
		var post_ratio := 0.0
		if _camera_mode != CAMERA_TOP:
			post_ratio = clampf(speed_kmh / 215.0, 0.0, 1.0)
			if _vehicle.is_boosting():
				post_ratio = clampf(post_ratio * 1.12 + 0.05, 0.0, 1.0)
		_speed_post.set_speed_ratio(post_ratio)

	match _camera_mode:
		CAMERA_HOOD:
			var hood_position := _vehicle.global_transform * Vector3(0.0, 1.12, -0.32)
			var hood_target := _vehicle.global_transform * Vector3(0.0, 0.98, -34.0)
			_camera.global_position = hood_position
			_camera.look_at(hood_target, Vector3.UP)
		CAMERA_TOP:
			var top_position := _vehicle.global_position + Vector3(0.0, 31.0, 14.0)
			_camera.global_position = top_position
			_camera.look_at(_vehicle.global_position + Vector3.UP * 1.0, Vector3(0.0, 0.0, -1.0))
		_:
			var distance := 6.15 + speed_ratio * 2.15
			var height := 2.05 + speed_ratio * 0.38
			var drift_offset_target := clampf(-_vehicle.get_lateral_speed_ms() * 0.055, -0.65, 0.65)
			if snap or delta <= 0.0:
				_camera_drift_offset_smooth = drift_offset_target
			else:
				_camera_drift_offset_smooth = lerpf(
					_camera_drift_offset_smooth,
					drift_offset_target,
					1.0 - exp(-7.0 * delta)
				)
			var follow_basis := Basis(Vector3.UP, _camera_follow_yaw)
			var desired_position := _vehicle.global_position + follow_basis * Vector3(_camera_drift_offset_smooth, height, distance)
			desired_position = _get_safe_camera_position(desired_position)
			if snap or delta <= 0.0:
				_camera.global_position = desired_position
			else:
				var weight := 1.0 - exp(-7.5 * delta)
				_camera.global_position = _camera.global_position.lerp(desired_position, weight)
			var forward := -follow_basis.z
			var target := _vehicle.global_position + Vector3.UP * 1.12 + forward * (6.0 + speed_ratio * 6.0)
			if snap or delta <= 0.0:
				_camera_target_smooth = target
			else:
				_camera_target_smooth = _camera_target_smooth.lerp(target, 1.0 - exp(-12.0 * delta))
			if _camera.global_position.distance_squared_to(_camera_target_smooth) > 0.001:
				_camera.look_at(_camera_target_smooth, Vector3.UP)
				var roll := clampf(_camera_drift_offset_smooth * 0.055, -0.035, 0.035)
				_camera.rotate_object_local(Vector3.FORWARD, roll)

	# Almost imperceptible vibration only while nitro is active.  Using
	# camera offsets avoids changing the smoothed global position.
	var shake := 0.0
	if _vehicle.is_boosting():
		shake = 0.010 + speed_ratio * 0.012
	var shake_time := float(Time.get_ticks_msec()) * 0.043
	_camera.h_offset = sin(shake_time * 1.37) * shake
	_camera.v_offset = cos(shake_time * 1.71) * shake * 0.7


func _get_safe_camera_position(desired_position: Vector3) -> Vector3:
	if _vehicle == null:
		return desired_position
	var origin := _vehicle.global_position + Vector3.UP * 1.25
	if origin.distance_squared_to(desired_position) < 0.04:
		return desired_position
	var query := PhysicsRayQueryParameters3D.create(origin, desired_position, 1, [_vehicle.get_rid()])
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return desired_position
	var hit_position: Vector3 = hit.get("position", desired_position)
	var toward_vehicle := (origin - desired_position).normalized()
	return hit_position + toward_vehicle * 0.28


func _count_geometry_instances(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D or node is MultiMeshInstance3D:
		count += 1
	for child in node.get_children():
		count += _count_geometry_instances(child)
	return count


func _rect_is_on_screen(rect: Rect2, viewport_size: Vector2) -> bool:
	return rect.size.x > 1.0 and rect.size.y > 1.0 and rect.position.x >= -1.0 and rect.position.y >= -1.0 and rect.end.x <= viewport_size.x + 1.0 and rect.end.y <= viewport_size.y + 1.0


func _run_smoke_checks() -> void:
	var failures: Array[String] = []
	if _world == null:
		failures.append("world node is missing")
	if _vehicle == null:
		failures.append("vehicle node is missing")
	if find_child("NativeTraffic", true, false) != null or find_child("TrafficManager", true, false) != null:
		failures.append("traffic node must be completely removed in 0.2.5")
	if _camera == null:
		failures.append("camera node is missing")
	if _speed_post == null:
		failures.append("speed post node is missing")
	if _hud == null:
		failures.append("HUD node is missing")
	if not failures.is_empty():
		_finish_smoke(failures)
		return

	var stats := _world.get_stats()
	var world_data := _world.get_world_data()
	if not _world.has_world_data() or world_data.is_empty():
		failures.append("exported world data is empty: %s" % _world.build_error)
	if int(stats.get("terrainVertices", 0)) < 9000:
		failures.append("terrain stats are missing or too small")
	if int(stats.get("roadEdges", 0)) < 50:
		failures.append("road stats are missing or too small")
	if int(stats.get("buildings", 0)) < 45:
		failures.append("building stats are missing or too small")
	if int(stats.get("landmarks", 0)) != 15:
		failures.append("landmark stats are incomplete")

	var enhancement_stats := _world.get_enhancement_stats()
	if int(enhancement_stats.get("reflection_probes", 0)) < 6 or not bool(enhancement_stats.get("reflection_probe_box_projection", false)) or float(enhancement_stats.get("reflection_probe_intensity", 0.0)) < 0.5 or float(enhancement_stats.get("reflection_probe_intensity", 0.0)) > 0.75:
		failures.append("local environment reflection cubemaps are incomplete: %s" % str(enhancement_stats))
	if int(enhancement_stats.get("road_markings", 0)) < 700:
		failures.append("road markings are incomplete: %s" % str(enhancement_stats))
	if not bool(enhancement_stats.get("premium_boulevard_paving", false)) or not bool(enhancement_stats.get("premium_stone_paving_shader_0218", false)) or not bool(enhancement_stats.get("boulevard_rebuild_0218", false)) or not bool(enhancement_stats.get("boulevard_reference_0219", false)) or not bool(enhancement_stats.get("boulevard_dark_asphalt_0219", false)) or not bool(enhancement_stats.get("dubai_premium_cafe_model", false)) or not bool(enhancement_stats.get("dubai_premium_cafe_pbr_0219", false)) or int(enhancement_stats.get("dubai_premium_cafe_model_parts", 0)) < 12 or int(enhancement_stats.get("dubai_premium_cafe_triangles", 0)) < 10000 or int(enhancement_stats.get("boulevard_granite_curbs", 0)) < 180 or int(enhancement_stats.get("boulevard_premium_sidewalk_slabs", 0)) < 180 or int(enhancement_stats.get("boulevard_fresh_markings", 0)) < 450 or int(enhancement_stats.get("boulevard_yellow_edge_lines", 0)) < 240 or int(enhancement_stats.get("boulevard_cafes", 0)) < 8 or int(enhancement_stats.get("boulevard_spawn_cafes", 0)) < 1 or int(enhancement_stats.get("boulevard_arcades", 0)) < 9 or int(enhancement_stats.get("boulevard_cafe_tables", 0)) < 55 or int(enhancement_stats.get("boulevard_cafe_umbrellas", 0)) < 24 or int(enhancement_stats.get("boulevard_palm_planters", 0)) < 60 or int(enhancement_stats.get("boulevard_drip_emitters", 0)) < 80 or int(enhancement_stats.get("boulevard_date_palms", 0)) < 60 or int(enhancement_stats.get("boulevard_lawn_islands", 0)) < 45 or float(enhancement_stats.get("boulevard_lawn_area_m2", 0.0)) < 4000.0 or int(enhancement_stats.get("boulevard_topiary", 0)) < 220 or int(enhancement_stats.get("boulevard_continuous_hedges", 0)) < 45 or int(enhancement_stats.get("boulevard_ground_cover", 0)) < 350 or int(enhancement_stats.get("boulevard_extra_date_palms", 0)) < 6 or int(enhancement_stats.get("boulevard_modern_lamps", 0)) < 55 or int(enhancement_stats.get("boulevard_stone_benches", 0)) < 25 or int(enhancement_stats.get("boulevard_pool_decks", 0)) < 3 or int(enhancement_stats.get("boulevard_marina_deck_segments", 0)) < 20 or int(enhancement_stats.get("boulevard_frontage_infill", 0)) < 8:
		failures.append("0.2.19 RichTown Boulevard reference corridor/PR61 PBR cafe rebuild is incomplete: %s" % str(enhancement_stats))
	var promenade_surface := _world.get_surface_at(Vector3(738.0, 4.0, 23.0))
	if String(promenade_surface.get("kind", "")) != "plaza":
		failures.append("spawn-side RichTown promenade is not classified as premium stone: %s" % str(promenade_surface))
	if not bool(enhancement_stats.get("parks_0222", false)) or int(enhancement_stats.get("parks", 0)) < 3 or float(enhancement_stats.get("park_area_m2", 0.0)) < 22000.0 or float(enhancement_stats.get("park_lawn_area_m2", 0.0)) < 9000.0 or int(enhancement_stats.get("park_trees", 0)) < 38 or int(enhancement_stats.get("park_palms", 0)) < 70 or int(enhancement_stats.get("park_bushes", 0)) < 55 or int(enhancement_stats.get("park_ground_cover", 0)) < 1600 or float(enhancement_stats.get("park_hedge_length_m", 0.0)) < 420.0 or int(enhancement_stats.get("park_benches", 0)) < 34 or int(enhancement_stats.get("park_lamps", 0)) < 18 or int(enhancement_stats.get("park_topiary", 0)) < 14 or not bool(enhancement_stats.get("central_park_fountain_garden", false)) or not bool(enhancement_stats.get("museum_garden_pergola", false)) or not bool(enhancement_stats.get("beach_palmetum_rondel", false)):
		failures.append("0.2.22 RichTown parks (Central Park/Museum Garden/Corniche Palmetum) pass is incomplete: %s" % str(enhancement_stats))
	var park_surface := _world.get_surface_at(Vector3(610.0, 4.0, -60.0))
	if String(park_surface.get("kind", "")) != "grass":
		failures.append("Central Park lawn is not classified as grass: %s" % str(park_surface))
	if int(enhancement_stats.get("bus_shelters", 0)) < 12:
		failures.append("bus shelters are incomplete: %s" % str(enhancement_stats))
	if not bool(enhancement_stats.get("photoreal_models_0223", false)) or not bool(enhancement_stats.get("photoreal_park_furniture_0223", false)) or int(enhancement_stats.get("palm_date_triangles", 0)) < 15000 or int(enhancement_stats.get("palm_royal_triangles", 0)) < 11000 or int(enhancement_stats.get("grass_tuft_triangles", 0)) < 900 or int(enhancement_stats.get("flower_clump_triangles", 0)) < 3500 or int(enhancement_stats.get("ornamental_shrub_triangles", 0)) < 4200 or int(enhancement_stats.get("street_lamp_triangles", 0)) < 4500 or int(enhancement_stats.get("bus_shelter_triangles", 0)) < 7500 or int(enhancement_stats.get("park_bench_triangles", 0)) < 3500 or int(enhancement_stats.get("park_pergola_triangles", 0)) < 7000 or int(enhancement_stats.get("park_bench_models", 0)) < 34:
		failures.append("0.2.23 photoreal model detail pass (palms/ground cover/lamps/shelters/park furniture) is incomplete: %s" % str(enhancement_stats))
	if not bool(enhancement_stats.get("district_infrastructure_0224", false)) or not bool(enhancement_stats.get("rounded_returns_0224", false)) or int(enhancement_stats.get("district_streets", 0)) < 6 or float(enhancement_stats.get("district_street_length_m", 0.0)) < 750.0 or int(enhancement_stats.get("palm_local_roads", 0)) < 3 or float(enhancement_stats.get("palm_local_length_m", 0.0)) < 90.0 or int(enhancement_stats.get("district_driveways", 0)) < 9 or int(enhancement_stats.get("district_hedges", 0)) < 14 or int(enhancement_stats.get("district_lamps", 0)) < 16 or int(enhancement_stats.get("district_street_trees", 0)) < 12 or int(enhancement_stats.get("district_palms", 0)) < 5 or int(enhancement_stats.get("district_benches", 0)) < 4 or int(enhancement_stats.get("district_roundabout", 0)) < 1 or int(enhancement_stats.get("district_mosque_plaza", 0)) < 1 or int(enhancement_stats.get("rounded_intersection_returns", 0)) < 80 or int(enhancement_stats.get("rounded_corner_curbs", 0)) < 400 or int(enhancement_stats.get("junctions_with_rounded_returns", 0)) < 25 or int(enhancement_stats.get("junction_edge_openings_0224", 0)) < 40 or int(enhancement_stats.get("junction_paint_breaks_0224", 0)) < 20 or int(enhancement_stats.get("guardrail_terminals", 0)) < 4 or int(enhancement_stats.get("guardrail_trimmed_subsegments", 0)) < 10 or float(enhancement_stats.get("guardrail_trim_start_m", 0.0)) < 13.0 or float(enhancement_stats.get("guardrail_min_alignment", 0.0)) < 0.99:
		failures.append("0.2.24 district streets/rounded junctions/guardrail alignment pass is incomplete: %s" % str(enhancement_stats))
	var district_surface := _world.get_surface_at(Vector3(638.0, 4.0, 300.0))
	var crescent_surface := _world.get_surface_at(Vector3(662.0, 4.0, 457.0))
	if String(district_surface.get("kind", "")) != "asphalt" or String(crescent_surface.get("kind", "")) != "asphalt":
		failures.append("0.2.24 South Villa District streets are not drivable asphalt: %s / %s" % [str(district_surface), str(crescent_surface)])
	if int(enhancement_stats.get("townhouse_models", 0)) + int(enhancement_stats.get("hero_building_models", 0)) < 10:
		failures.append("detailed Blender building models are incomplete: %s" % str(enhancement_stats))
	if int(enhancement_stats.get("premium_villa_models", 0)) < 14 or not bool(enhancement_stats.get("premium_villa_fixed_scale", false)) or not bool(enhancement_stats.get("premium_villa_detail_pass", false)) or not bool(enhancement_stats.get("premium_villa_material_pass", false)) or not bool(enhancement_stats.get("premium_villa_site_pass", false)):
		failures.append("0.2.8 Building Model No.1 premium villa second pass is incomplete: %s" % str(enhancement_stats))
	if int(enhancement_stats.get("premium_townhouse_models", 0)) < 9 or not bool(enhancement_stats.get("premium_townhouse_fixed_scale", false)) or not bool(enhancement_stats.get("premium_townhouse_detail_pass", false)) or not bool(enhancement_stats.get("premium_townhouse_material_pass", false)) or not bool(enhancement_stats.get("premium_townhouse_site_pass", false)):
		failures.append("0.2.9 Building Model No.2 premium townhouse pass is incomplete: %s" % str(enhancement_stats))
	if int(enhancement_stats.get("premium_hero_models", 0)) < 8 or not bool(enhancement_stats.get("premium_hero_fixed_scale", false)) or not bool(enhancement_stats.get("premium_hero_detail_pass", false)) or not bool(enhancement_stats.get("premium_hero_material_pass", false)) or not bool(enhancement_stats.get("premium_hero_site_pass", false)):
		failures.append("0.2.10 Building Model No.3 premium hero block pass is incomplete: %s" % str(enhancement_stats))
	if int(enhancement_stats.get("premium_glass_models", 0)) < 8 or not bool(enhancement_stats.get("premium_glass_fixed_scale", false)) or not bool(enhancement_stats.get("premium_glass_detail_pass", false)) or not bool(enhancement_stats.get("premium_glass_material_pass", false)) or not bool(enhancement_stats.get("premium_glass_site_pass", false)):
		failures.append("0.2.11 Building Model No.4 premium glass tower pass is incomplete: %s" % str(enhancement_stats))
	if not bool(enhancement_stats.get("premium_main_tower_built", false)) or not bool(enhancement_stats.get("premium_main_tower_fixed_scale", false)) or not bool(enhancement_stats.get("premium_main_tower_detail_pass", false)) or not bool(enhancement_stats.get("premium_main_tower_material_pass", false)) or not bool(enhancement_stats.get("premium_main_tower_site_pass", false)):
		failures.append("0.2.13 Building Model No.5 premium 148 m main tower pass is incomplete: %s" % str(enhancement_stats))
	if not bool(enhancement_stats.get("premium_opera_built", false)) or not bool(enhancement_stats.get("premium_opera_fixed_scale", false)) or not bool(enhancement_stats.get("premium_opera_detail_pass", false)) or not bool(enhancement_stats.get("premium_opera_material_pass", false)) or not bool(enhancement_stats.get("premium_opera_site_pass", false)) or not bool(enhancement_stats.get("premium_opera_fronts_boulevard", false)) or int(enhancement_stats.get("premium_opera_model_parts", 0)) < 14 or int(enhancement_stats.get("premium_opera_triangles", 0)) < 18000 or absf(float(enhancement_stats.get("premium_opera_height_m", 0.0)) - 22.0) > 0.20:
		failures.append("0.2.20 Building Model No.6 RichTown Opera pass is incomplete: %s" % str(enhancement_stats))
	if not bool(enhancement_stats.get("premium_mosque_built", false)) or not bool(enhancement_stats.get("premium_mosque_fixed_scale", false)) or not bool(enhancement_stats.get("premium_mosque_detail_pass", false)) or not bool(enhancement_stats.get("premium_mosque_material_pass", false)) or not bool(enhancement_stats.get("premium_mosque_site_pass", false)) or not bool(enhancement_stats.get("premium_mosque_fronts_east", false)) or int(enhancement_stats.get("premium_mosque_model_parts", 0)) < 10 or int(enhancement_stats.get("premium_mosque_triangles", 0)) < 30000 or absf(float(enhancement_stats.get("premium_mosque_height_m", 0.0)) - 30.0) > 0.20 or absf(float(enhancement_stats.get("premium_mosque_width_m", 0.0)) - 38.4) > 0.25 or absf(float(enhancement_stats.get("premium_mosque_depth_m", 0.0)) - 36.0) > 0.25:
		failures.append("0.2.25 Building Model No.7 RichTown Mosque pass is incomplete: %s" % str(enhancement_stats))
	if int(enhancement_stats.get("curtain_wall_materials", 0)) < 5 or not bool(enhancement_stats.get("curtain_wall_shader", false)) or not bool(enhancement_stats.get("curtain_wall_opaque_shader", false)) or not bool(enhancement_stats.get("curtain_wall_panel_variation", false)) or not bool(enhancement_stats.get("curtain_wall_weathering", false)) or not bool(enhancement_stats.get("curtain_wall_neutral_glass", false)) or int(enhancement_stats.get("tall_reflection_probes", 0)) < 2:
		failures.append("0.2.14 physical curtain-wall realism pass is incomplete: %s" % str(enhancement_stats))
	if not bool(enhancement_stats.get("curtain_wall_calibrated_0215", false)) or not bool(enhancement_stats.get("curtain_wall_clearcoat_removed", false)) or not bool(enhancement_stats.get("building_visual_ranges_0215", false)) or int(enhancement_stats.get("model_parts_without_shadow_pass", 0)) < 10 or float(enhancement_stats.get("curtain_wall_detail_fade_start_m", 9999.0)) > 90.0 or float(enhancement_stats.get("curtain_wall_detail_fade_end_m", 9999.0)) > 300.0 or float(enhancement_stats.get("traffic_signal_visual_range_m", 9999.0)) > 360.0:
		failures.append("0.2.15 glass calibration/render-cost pass is incomplete: %s" % str(enhancement_stats))
	if not bool(enhancement_stats.get("curtain_wall_reflective_coating_0216", false)) or not bool(enhancement_stats.get("runtime_lods_0216", false)) or int(enhancement_stats.get("runtime_lod_meshes", 0)) < 20 or int(enhancement_stats.get("runtime_lod_levels", 0)) < 40 or float(enhancement_stats.get("runtime_lod_min_index_ratio", 1.0)) > 0.65 or not bool(enhancement_stats.get("batched_models_merged_0216", false)) or int(enhancement_stats.get("batched_model_paths_0216", 0)) < 8 or int(enhancement_stats.get("batched_model_instances_0216", 0)) < 200 or not bool(enhancement_stats.get("building_hlod_0216", false)) or int(enhancement_stats.get("building_far_proxy_models", 0)) < 40 or int(enhancement_stats.get("building_far_proxy_boxes", 0)) < 80 or not bool(enhancement_stats.get("vegetation_hlod_0216", false)) or int(enhancement_stats.get("vegetation_far_proxies", 0)) < 150 or float(enhancement_stats.get("traffic_signal_visual_range_m", 9999.0)) > 220.0:
		failures.append("0.2.16 reflective-glass/HLOD/runtime-LOD pass is incomplete: %s" % str(enhancement_stats))
	if not bool(enhancement_stats.get("detailed_palms_0217", false)) or int(enhancement_stats.get("date_palms", 0)) < 80 or int(enhancement_stats.get("royal_palms", 0)) < 10 or int(enhancement_stats.get("detailed_palms", 0)) < 110 or int(enhancement_stats.get("palm_date_triangles", 0)) < 9000 or int(enhancement_stats.get("palm_royal_triangles", 0)) < 6500 or not bool(enhancement_stats.get("geometric_ground_cover_0217", false)) or int(enhancement_stats.get("grass_tufts", 0)) < 1200 or int(enhancement_stats.get("flower_clumps", 0)) < 180 or int(enhancement_stats.get("ornamental_shrubs", 0)) < 80 or int(enhancement_stats.get("ground_cover_total", 0)) < 1500 or int(enhancement_stats.get("grass_tuft_triangles", 0)) < 300 or int(enhancement_stats.get("flower_clump_triangles", 0)) < 1000 or int(enhancement_stats.get("ornamental_shrub_triangles", 0)) < 1600 or not bool(enhancement_stats.get("palm_far_proxy_0217", false)) or int(enhancement_stats.get("palm_far_proxies", 0)) < 100 or not bool(enhancement_stats.get("concrete_stochastic_0217", false)) or int(enhancement_stats.get("concrete_shader_materials", 0)) < 5 or not bool(enhancement_stats.get("curtain_wall_environment_reflection_0217", false)) or int(enhancement_stats.get("sky_radiance_size", 0)) != 512 or not bool(enhancement_stats.get("reflection_probe_mobile_calibration_0217", false)):
		failures.append("0.2.17 detailed palms/ground-cover/concrete/environment-glass pass is incomplete: %s" % str(enhancement_stats))
	if int(enhancement_stats.get("extra_trees", 0)) < 35 or int(enhancement_stats.get("extra_bushes", 0)) < 20:
		failures.append("extra vegetation is incomplete: %s" % str(enhancement_stats))
	if int(enhancement_stats.get("infill_buildings", 0)) < 50 or int(enhancement_stats.get("infill_model_buildings", 0)) < 25:
		failures.append("0.2.5 infill city density is incomplete: %s" % str(enhancement_stats))
	if int(enhancement_stats.get("building_details", 0)) < 180 or int(enhancement_stats.get("city_detail_props", 0)) < 250:
		failures.append("0.2.5 architectural/street detail density is incomplete: %s" % str(enhancement_stats))
	if int(enhancement_stats.get("beach_props", 0)) < 50 or int(enhancement_stats.get("marina_boats", 0)) < 8:
		failures.append("0.2.5 beach/marina detail is incomplete: %s" % str(enhancement_stats))

	var dynamic_world_state := _world.get_dynamic_world_state()
	if int(dynamic_world_state.get("presets", 0)) < 5 or String(dynamic_world_state.get("preset", "")) != "clear_day" or not bool(dynamic_world_state.get("physical_sky", false)):
		failures.append("DynamicWorld Drive base is not active: %s" % str(dynamic_world_state))
	if not bool(dynamic_world_state.get("bloom_enabled", false)) or float(dynamic_world_state.get("cinematic_contrast", 0.0)) < 1.05 or float(dynamic_world_state.get("cinematic_brightness", 1.0)) >= 1.0:
		failures.append("cinematic bloom/color grade is not active: %s" % str(dynamic_world_state))
	var speed_post_state := _speed_post.get_smoke_state()
	if not bool(speed_post_state.get("ready", false)) or not bool(speed_post_state.get("cinematic_grade", false)) or not bool(speed_post_state.get("always_on_vignette", false)) or not bool(speed_post_state.get("film_grain", false)):
		failures.append("SpeedPost cinematic grade/vignette/grain is incomplete: %s" % str(speed_post_state))
	var drive_base_state := _vehicle.get_drive_base_state()
	if not bool(drive_base_state.get("car_paint_shader", false)) or not bool(drive_base_state.get("paint_reflections_ready", false)) or float(drive_base_state.get("roll_reduction", 0.0)) <= 0.0 or int(drive_base_state.get("paint_materials", 0)) < 1:
		failures.append("ArcadeCar reflective paint Drive base is not active: %s" % str(drive_base_state))
	var smoothing_state := _vehicle.get_smoothing_state()
	if not bool(smoothing_state.get("pedal_actuator_smoothing", false)) or not bool(smoothing_state.get("drive_force_smoothing", false)) or not bool(smoothing_state.get("filtered_suspension", false)) or not bool(smoothing_state.get("anti_roll_requires_both_wheels", false)):
		failures.append("0.2.5 acceleration/suspension smoothing is incomplete: %s" % str(smoothing_state))
	if not _camera_smoothing_initialized or not is_finite(_camera_follow_yaw):
		failures.append("0.2.5 chase-camera smoothing is not initialized")

	var water_visual_state := _world.get_water_visual_state()
	if not bool(water_visual_state.get("sea_shader", false)) or not bool(water_visual_state.get("animated_waves", false)) or not bool(water_visual_state.get("depth_foam", false)) or float(water_visual_state.get("reflection_strength", 0.0)) < 0.5:
		failures.append("0.2.x sea PBR/wave/shoreline water is incomplete: %s" % str(water_visual_state))

	var road_visual_state := _world.get_road_visual_state()
	if not bool(road_visual_state.get("asphalt_shader", false)) or not bool(road_visual_state.get("asphalt_textures", false)) or not bool(road_visual_state.get("asphalt_wear_texture", false)) or int(road_visual_state.get("asphalt_layers", 0)) < 3 or float(road_visual_state.get("road_crown_m", 0.0)) < 0.03 or not bool(road_visual_state.get("ground_winding_godot_cw", false)) or not bool(road_visual_state.get("road_mesh_ready", false)):
		failures.append("0.2.6 road/terrain visual state would be culled or untextured: %s" % str(road_visual_state))
	if int(road_visual_state.get("foliage_wind_materials", 0)) < 3:
		failures.append("foliage wind Drive base is incomplete: %s" % str(road_visual_state))
	if int(road_visual_state.get("multimesh_chunks", 0)) < 40 or float(road_visual_state.get("multimesh_chunk_size_m", 9999.0)) > 260.0 or int(road_visual_state.get("road_grid_cells", 0)) < 40:
		failures.append("0.2.4 spatial chunking/road grid is incomplete: %s" % str(road_visual_state))
	if render_quality_state.is_empty():
		failures.append("adaptive render quality state is missing")
	if int(enhancement_stats.get("road_edge_lines", 0)) < 1500 or int(enhancement_stats.get("lane_dashes", 0)) < 450 or int(enhancement_stats.get("center_lines", 0)) < 1400:
		failures.append("0.2.6 lane/centre road paint is incomplete: %s" % str(enhancement_stats))
	if int(enhancement_stats.get("raised_sidewalk_slabs", 0)) < 1200 or int(enhancement_stats.get("concrete_curbs", 0)) < 1200 or int(enhancement_stats.get("road_gutters", 0)) < 1200:
		failures.append("0.2.6 raised sidewalk/curb/gutter road edge is incomplete: %s" % str(enhancement_stats))
	if int(enhancement_stats.get("manholes", 0)) < 80 or int(enhancement_stats.get("drainage_grates", 0)) < 80 or int(enhancement_stats.get("asphalt_patches", 0)) < 70 or int(enhancement_stats.get("road_studs", 0)) < 600:
		failures.append("0.2.6 road-surface detail is incomplete: %s" % str(enhancement_stats))
	if int(enhancement_stats.get("lane_arrows", 0)) < 80 or int(enhancement_stats.get("traffic_signals", 0)) < 48 or int(enhancement_stats.get("traffic_signal_models", 0)) < 48 or not bool(enhancement_stats.get("traffic_signal_static_red", false)) or int(enhancement_stats.get("intersection_pads", 0)) < 18:
		failures.append("0.2.7 Blender traffic-signal/intersection furniture is incomplete: %s" % str(enhancement_stats))

	var traffic_stats := {"moving": 0, "parked": 0, "total": 0, "removed": true}
	if float(enhancement_stats.get("shadow_max_distance", 9999.0)) > 180.0 or float(enhancement_stats.get("reflection_probe_max_distance", 9999.0)) > 260.0:
		failures.append("mobile shadow/reflection ranges are not bounded: %s" % str(enhancement_stats))
	var spawn_surface := _world.get_surface_at(_vehicle.global_position)
	if String(spawn_surface.get("kind", "")) != "asphalt":
		failures.append("spawn surface is not asphalt: %s" % str(spawn_surface))
	if _vehicle.get_surface_kind() != "asphalt":
		failures.append("vehicle tyre surface is not asphalt after spawn: %s" % _vehicle.get_surface_kind())
	if _vehicle.get_gear_label() != "N" and _vehicle.get_gear_label() != "1":
		failures.append("vehicle gearbox state is invalid after spawn: %s rpm=%.0f" % [_vehicle.get_gear_label(), _vehicle.get_engine_rpm()])
	var vehicle_aabb_size := _vehicle.get_visual_aabb_size()
	var horizontal_max := maxf(vehicle_aabb_size.x, vehicle_aabb_size.z)
	var horizontal_min := minf(vehicle_aabb_size.x, vehicle_aabb_size.z)
	if horizontal_max < 4.2 or horizontal_max > 5.3 or horizontal_min < 1.6 or horizontal_min > 2.25 or vehicle_aabb_size.y < 1.05 or vehicle_aabb_size.y > 1.8:
		failures.append("Mustang visual AABB is outside real-car scale bounds: %s" % str(vehicle_aabb_size))

	var world_geometry_count := _count_geometry_instances(_world)
	if world_geometry_count < 20:
		failures.append("world geometry count is too low: %d" % world_geometry_count)
	var vehicle_geometry_count := _count_geometry_instances(_vehicle)
	if vehicle_geometry_count == 0:
		failures.append("vehicle has no renderable geometry")
	if _vehicle.grounded_wheel_count < 2:
		failures.append("vehicle is not grounded after spawn: wheels=%d position=%s" % [_vehicle.grounded_wheel_count, str(_vehicle.global_position)])

	var terrain_height := _world.height_at(_vehicle.global_position.x, _vehicle.global_position.z)
	if _vehicle.global_position.y < terrain_height - 1.0 or _vehicle.global_position.y > terrain_height + 8.0:
		failures.append("vehicle is outside the expected spawn height band: y=%.2f terrain=%.2f" % [_vehicle.global_position.y, terrain_height])

	if not _camera.is_current() or get_viewport().get_camera_3d() != _camera:
		failures.append("game camera is not the viewport's current camera")
	var vehicle_view_point := _vehicle.global_position + Vector3.UP * 0.75
	if _camera.is_position_behind(vehicle_view_point):
		failures.append("vehicle is behind the game camera")
	if not _camera.is_position_in_frustum(vehicle_view_point):
		failures.append("vehicle is outside the game camera frustum")

	var hud_state := _hud.get_smoke_state()
	var minimap_counts: Dictionary = hud_state.get("minimap_counts", {})
	if int(minimap_counts.get("roads", 0)) < 35 or int(minimap_counts.get("buildings", 0)) < 45 or int(minimap_counts.get("parks", 0)) < 3:
		failures.append("minimap did not receive complete world data: %s" % str(minimap_counts))
	var performance_text := String(hud_state.get("performance_text", ""))
	if performance_text.is_empty() or performance_text == "FPS —" or performance_text.contains("WORLD DATA ERROR"):
		failures.append("HUD performance label did not update cleanly: %s" % performance_text)
	var coordinates_text := String(hud_state.get("coordinates_text", ""))
	if not coordinates_text.contains("КООРДИНАТЫ") or not coordinates_text.contains("X 760") or not coordinates_text.contains("Z 330") or not coordinates_text.contains("Y "):
		failures.append("0.2.12 HUD live coordinates did not update at spawn: %s" % coordinates_text)
	var viewport_size: Vector2 = hud_state.get("viewport_size", Vector2.ZERO)
	var coordinates_rect: Rect2 = hud_state.get("coordinates_rect", Rect2())
	if not _rect_is_on_screen(coordinates_rect, viewport_size):
		failures.append("coordinates label is not fully on screen: rect=%s viewport=%s" % [str(coordinates_rect), str(viewport_size)])
	var speed_rect: Rect2 = hud_state.get("speed_rect", Rect2())
	var pedal_rect: Rect2 = hud_state.get("pedal_rect", Rect2())
	if not _rect_is_on_screen(speed_rect, viewport_size):
		failures.append("speed panel is not fully on screen: rect=%s viewport=%s" % [str(speed_rect), str(viewport_size)])
	if not _rect_is_on_screen(pedal_rect, viewport_size):
		failures.append("pedal row is not fully on screen: rect=%s viewport=%s" % [str(pedal_rect), str(viewport_size)])

	if failures.is_empty():
		print("[native-smoke] PASS world_geometry=%d vehicle_geometry=%d vehicle=%s camera=%s minimap=%s traffic=%s enhancements=%s vehicle_aabb=%s surface=%s gear=%s rpm=%.0f dynamic=%s speed_post=%s drive_base=%s smoothing=%s road_visual=%s render_quality=%s" % [
			world_geometry_count,
			vehicle_geometry_count,
			str(_vehicle.global_position),
			str(_camera.global_position),
			str(minimap_counts),
			str(traffic_stats),
			str(enhancement_stats),
			str(vehicle_aabb_size),
			str(spawn_surface),
			_vehicle.get_gear_label(),
			_vehicle.get_engine_rpm(),
			str(dynamic_world_state),
			str(speed_post_state),
			str(drive_base_state),
			str(smoothing_state),
			str(road_visual_state),
			str(render_quality_state),
		])
	_finish_smoke(failures)


func _finish_smoke(failures: Array[String]) -> void:
	if failures.is_empty():
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("[native-smoke] FAIL: %s" % failure)
	get_tree().quit(2)


## ---------------------------------------------------------------------
## Visual-audit screenshot tour (`--native-screenshots[=<dir>]`).
##
## The same shipped game scene drives its own camera through authored
## viewpoints of RichTown, saves real rendered PNG frames and quits.
## CI (`.github/workflows/native-screenshots.yml`) runs it on a virtual
## display with software Vulkan, so every delivery can be checked with
## actual in-game screenshots instead of logs alone.  The mode is inert
## unless the command-line flag (or the NITCHES_SCREENSHOT_DIR fallback
## used together with the flag) is present; normal players never see it.
## Camera/target Y values are metres above the terrain at that XZ.
func _parse_screenshot_request() -> void:
	var args: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		args.append(arg)
	for arg in OS.get_cmdline_args():
		args.append(arg)
	for arg in args:
		if arg == "--native-screenshots":
			_screenshot_mode = true
		elif arg.begins_with("--native-screenshots="):
			_screenshot_mode = true
			_screenshot_dir = arg.trim_prefix("--native-screenshots=")
	if not _screenshot_mode:
		return
	if _screenshot_dir.is_empty():
		_screenshot_dir = OS.get_environment("NITCHES_SCREENSHOT_DIR")
	if _screenshot_dir.is_empty():
		_screenshot_dir = "user://screenshots"
	if _screenshot_dir.begins_with("res://") or _screenshot_dir.begins_with("user://"):
		_screenshot_dir = ProjectSettings.globalize_path(_screenshot_dir)
	print("[native-screenshots] mode enabled, output dir: ", _screenshot_dir)


func _run_screenshot_tour() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# Software rendering in CI produces very slow frames; let each one
	# advance physics far enough for the car to settle on its wheels.
	Engine.max_physics_steps_per_frame = 60
	var make_err := DirAccess.make_dir_recursive_absolute(_screenshot_dir)
	if make_err != OK and not DirAccess.dir_exists_absolute(_screenshot_dir):
		push_error("[native-screenshots] FAIL: cannot create output dir %s (error %d)" % [_screenshot_dir, make_err])
		get_tree().quit(1)
		return

	var shots: Array[Dictionary] = [
		{
			"name": "01_spawn_gameplay", "time": "day", "hud": true,
			"vehicle": "spawn", "gameplay_camera": true, "frames": 10,
		},
		{
			"name": "02_mosque_east", "time": "day", "vehicle": "hide",
			"camera": Vector3(678.0, 13.0, 366.0), "target": Vector3(622.0, 11.0, 335.0),
		},
		{
			"name": "03_mosque_street", "time": "day", "vehicle": "road",
			"vehicle_at": Vector3(655.0, 0.0, 335.0),
			"camera": Vector3(670.0, 2.4, 358.0), "target": Vector3(628.0, 9.0, 336.0),
		},
		{
			"name": "04_opera_boulevard", "time": "day", "vehicle": "hide",
			"camera": Vector3(768.0, 9.0, 72.0), "target": Vector3(820.0, 9.0, 25.0),
		},
		{
			"name": "05_boulevard_cafe", "time": "day", "vehicle": "road",
			"vehicle_at": Vector3(740.0, 0.0, 30.0),
			"camera": Vector3(724.0, 2.6, 68.0), "target": Vector3(758.0, 4.5, 6.0),
		},
		{
			"name": "06_main_tower", "time": "day", "vehicle": "hide",
			"camera": Vector3(552.0, 26.0, -64.0), "target": Vector3(665.0, 58.0, -170.0),
		},
		{
			"name": "07_central_park_sunset", "time": "sunset", "vehicle": "hide",
			"camera": Vector3(548.0, 15.0, 2.0), "target": Vector3(622.0, 3.0, -68.0),
		},
		{
			"name": "08_city_aerial_sunset", "time": "sunset", "vehicle": "hide",
			"camera": Vector3(430.0, 165.0, 240.0), "target": Vector3(730.0, 8.0, -30.0),
		},
	]

	# Warm-up: import/runtime LOD, reflection probes and visibility
	# ranges all settle over the first rendered frames.
	for i in range(8):
		await RenderingServer.frame_post_draw

	var saved := 0
	for shot in shots:
		if await _capture_screenshot(shot):
			saved += 1
	print("[native-screenshots] DONE saved=%d/%d dir=%s" % [saved, shots.size(), _screenshot_dir])
	get_tree().quit(0 if saved == shots.size() else 1)


func _capture_screenshot(shot: Dictionary) -> bool:
	var shot_name := String(shot.get("name", "shot"))
	_time_index = maxi(TIME_MODES.find(String(shot.get("time", "day"))), 0)
	_apply_time_mode()
	if _hud != null:
		_hud.visible = bool(shot.get("hud", false))

	match String(shot.get("vehicle", "hide")):
		"spawn":
			_vehicle.visible = true
			_vehicle.reset_to_transform(_world.spawn_transform)
		"road":
			_vehicle.visible = true
			var anchor: Vector3 = shot.get("vehicle_at", Vector3.ZERO)
			_vehicle.reset_to_transform(_world.find_nearest_road_transform(anchor))
		_:
			_vehicle.visible = false

	if bool(shot.get("gameplay_camera", false)):
		_screenshot_free_camera = false
		_camera_mode = CAMERA_CHASE
		_snap_camera = true
	else:
		_screenshot_free_camera = true
		var cam_spec: Vector3 = shot.get("camera", Vector3.ZERO)
		var target_spec: Vector3 = shot.get("target", Vector3.ZERO)
		var cam_pos := Vector3(
			cam_spec.x,
			_world.height_at(cam_spec.x, cam_spec.z) + cam_spec.y,
			cam_spec.z
		)
		var target := Vector3(
			target_spec.x,
			_world.height_at(target_spec.x, target_spec.z) + target_spec.y,
			target_spec.z
		)
		_camera.fov = float(shot.get("fov", 55.0))
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
		_camera.global_position = cam_pos
		if cam_pos.distance_squared_to(target) > 0.01:
			_camera.look_at(target, Vector3.UP)
		print("[native-screenshots] %s camera=%s target=%s" % [shot_name, str(cam_pos), str(target)])

	var frames := int(shot.get("frames", 6))
	for i in range(frames):
		await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		push_error("[native-screenshots] FAIL: empty viewport image for %s" % shot_name)
		return false
	var path := _screenshot_dir.path_join(shot_name + ".png")
	var err := image.save_png(path)
	if err != OK:
		push_error("[native-screenshots] FAIL: save_png(%s) error %d" % [path, err])
		return false
	print("[native-screenshots] SAVED %s (%dx%d)" % [path, image.get_width(), image.get_height()])
	return true
