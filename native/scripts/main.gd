extends Node3D

## Native game bootstrap: world, player vehicle, camera rig and HUD.
## This is the first playable Godot vertical slice for the native rebuild.
## Future systems should be added as separate native nodes/scripts
## rather than growing this coordinator.

const WorldBuilderScript := preload("res://scripts/world_builder.gd")
const VehicleScript := preload("res://scripts/vehicle_controller.gd")
const SpeedPostScript := preload("res://scripts/speed_post.gd")
const HudScript := preload("res://scripts/hud.gd")
const MainMenuScript := preload("res://scripts/main_menu.gd")
const WorldMapScript := preload("res://scripts/world_map.gd")
const RouteGuideScript := preload("res://scripts/route_guide.gd")
const PROFILE_PATH := "user://nitches_profile.cfg"
const SETTINGS_PATH := "user://nitches_settings.cfg"

const TIME_MODES: Array[String] = ["day", "sunset", "night"]
const CAMERA_CHASE := 0
const CAMERA_HOOD := 1
const CAMERA_TOP := 2
const CAMERA_ORBIT_TOUCH_SENSITIVITY := 0.0052
const CAMERA_ORBIT_MOUSE_SENSITIVITY := 0.0042
const CAMERA_ORBIT_PITCH_MIN := -0.38
const CAMERA_ORBIT_PITCH_MAX := 0.86
const CAMERA_ORBIT_DISTANCE_MIN := 0.72
const CAMERA_ORBIT_DISTANCE_MAX := 1.50
const GARAGE_STUDIO_ORIGIN := Vector3(0.0, 250.0, 0.0)
const TUNING_COSTS: Array[int] = [0, 5000, 12000]

var _world: NativeWorldBuilder
var _vehicle: NativeVehicle
var _hud: NativeHud
var _menu: NativeMainMenu
var _world_map: NativeWorldMap
var _route_guide: NativeRouteGuide
var _map_open := false
var _in_menu := false
var _has_entered_game := false
var _settings: Dictionary = {}
var _menu_orbit_angle := 0.0
var _garage_stage: Node3D
var _garage_active := false
var _garage_return_transform := Transform3D.IDENTITY
var _has_garage_return := false
var _garage_yaw := 0.65
var _garage_pitch := 0.30
var _garage_distance := 8.2
var _garage_idle_time := 0.0
var _session_distance_m := 0.0
var _session_top_speed_kmh := 0.0
var _session_drift_deg := 0.0
var _session_seconds := 0.0
var _credit_distance_bank_m := 0.0
var _profile: Dictionary = {}
var _profile_save_timer := 0.0
var _camera: Camera3D
var _speed_post: NativeSpeedPost
var _camera_mode := CAMERA_CHASE
var _snap_camera := true
var _time_index := 0
var _smoke_mode := false
var _smoke_frames := 0
var _smoke_completed := false
var _screenshot_mode := false
var _screenshot_dir := ""
var _screenshot_free_camera := false
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
var _camera_orbit_yaw := 0.0
var _camera_orbit_pitch := 0.0
var _camera_orbit_distance_scale := 1.0
var _camera_drag_touch_index := -1
var _camera_mouse_dragging := false
var _camera_manual_timer := 999.0


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
	_route_guide = RouteGuideScript.new() as NativeRouteGuide
	_route_guide.name = "RouteGuide"
	add_child(_route_guide)
	_route_guide.bind(_world, _vehicle)
	_route_guide.path_changed.connect(_on_route_path_changed)
	_route_guide.route_arrived.connect(_on_route_arrived)
	_create_garage_studio()
	_hud = HudScript.new() as NativeHud
	add_child(_hud)
	_hud.bind(_world, _vehicle)
	_hud.camera_requested.connect(_cycle_camera)
	_hud.view_requested.connect(_on_view_requested)
	_hud.sound_toggle_requested.connect(_on_sound_toggle_requested)
	_hud.time_requested.connect(_cycle_time)
	_hud.reset_requested.connect(_reset_vehicle_to_road)
	_hud.menu_requested.connect(_show_menu)

	# 0.2.29: the game opens on the main menu (profile / garage /
	# store / worlds) over a cinematic orbit of the car; Play enters
	# the world.  Smoke and screenshot runs skip straight to driving.
	_load_settings()
	_load_profile()
	_apply_customization_to_vehicle()
	_claim_achievement_rewards()
	_menu = MainMenuScript.new() as NativeMainMenu
	add_child(_menu)
	_menu.bind_specs(_vehicle.get_spec_sheet())
	_menu.refresh_profile(_profile_view())
	_menu.bind_customization(_customization_view())
	_menu.play_requested.connect(_enter_game)
	_menu.world_map_requested.connect(_show_world_map)
	_menu.settings_changed.connect(_on_settings_changed)
	_menu.camera_cycle_requested.connect(_cycle_camera)
	_menu.time_cycle_requested.connect(_cycle_time)
	_menu.panel_changed.connect(_on_menu_panel_changed)
	_menu.garage_dragged.connect(_on_garage_dragged)
	_menu.garage_zoomed.connect(_on_garage_zoomed)
	_menu.customization_changed.connect(_on_customization_changed)
	_menu.tuning_purchase_requested.connect(_on_tuning_purchase_requested)
	_menu.profile_changed.connect(_on_profile_changed)
	_apply_settings(_settings, false)

	# 0.2.32: full-screen named RichTown map over the game.  The HUD
	# minimap and M/Tab open it; the car is frozen while it is read.
	_world_map = WorldMapScript.new() as NativeWorldMap
	add_child(_world_map)
	_world_map.bind(_world, _vehicle)
	_world_map.close_requested.connect(_hide_world_map)
	_world_map.destination_changed.connect(_on_world_map_destination_changed)
	_world_map.fast_travel_requested.connect(_on_fast_travel_requested)
	_world_map.minimap_points_changed.connect(_on_minimap_points_changed)
	_hud.set_minimap_points(_world_map.get_minimap_points())
	_on_world_map_destination_changed(_world_map.get_route_destination())
	_hud.map_requested.connect(_show_world_map)
	if _smoke_mode or _screenshot_mode:
		_enter_game()
	else:
		_show_menu()

	_apply_time_mode()
	_update_camera(0.0, true)
	print("[native] Nitches Horizon Godot alpha is ready")
	if _screenshot_mode:
		_run_screenshot_tour()


func _default_settings() -> Dictionary:
	return {
		"control_type": "wheel",
		"steering_sensitivity": 1.0,
		"steering_dead_zone": 0.03,
		"wheel_size_multiplier": 1.0,
		"sound_enabled": true,
		"developer_mode": false,
		"map_hint_seen": false,
	}


func _sanitize_settings(source: Dictionary) -> Dictionary:
	var result := _default_settings()
	for key in result.keys():
		if source.has(key):
			result[key] = source[key]
	var control_type := String(result.get("control_type", "wheel"))
	if control_type != "wheel" and control_type != "tilt" and control_type != "arrows":
		control_type = "wheel"
	result["control_type"] = control_type
	result["steering_sensitivity"] = clampf(float(result.get("steering_sensitivity", 1.0)), 0.5, 1.8)
	result["steering_dead_zone"] = clampf(float(result.get("steering_dead_zone", 0.03)), 0.0, 0.25)
	result["wheel_size_multiplier"] = clampf(float(result.get("wheel_size_multiplier", 1.0)), 0.75, 1.25)
	result["sound_enabled"] = bool(result.get("sound_enabled", true))
	result["developer_mode"] = bool(result.get("developer_mode", false))
	result["map_hint_seen"] = bool(result.get("map_hint_seen", false))
	return result


func _load_settings() -> void:
	_settings = _default_settings()
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for key in _settings.keys():
			_settings[key] = cfg.get_value("settings", key, _settings[key])
	_settings = _sanitize_settings(_settings)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in _settings.keys():
		cfg.set_value("settings", key, _settings[key])
	cfg.save(SETTINGS_PATH)


func _camera_mode_label() -> String:
	match _camera_mode:
		CAMERA_HOOD:
			return "КАПОТ"
		CAMERA_TOP:
			return "СВЕРХУ"
		_:
			return "ВИД СЗАДИ"


func _time_mode_label() -> String:
	match TIME_MODES[_time_index]:
		"sunset":
			return "ЗАКАТ"
		"night":
			return "НОЧЬ"
		_:
			return "ДЕНЬ"


func _settings_for_menu() -> Dictionary:
	var result := _settings.duplicate(true)
	result["camera_label"] = _camera_mode_label()
	result["time_label"] = _time_mode_label()
	return result


func _refresh_menu_settings() -> void:
	if _menu != null:
		_menu.bind_settings(_settings_for_menu())


func _apply_settings(settings: Dictionary, save_settings: bool) -> void:
	_settings = _sanitize_settings(settings)
	if _vehicle != null:
		_vehicle.set_control_preferences(
			String(_settings.get("control_type", "wheel")),
			float(_settings.get("steering_sensitivity", 1.0)),
			float(_settings.get("steering_dead_zone", 0.03))
		)
	if _hud != null:
		_hud.apply_control_preferences(
			String(_settings.get("control_type", "wheel")),
			float(_settings.get("wheel_size_multiplier", 1.0))
		)
		_hud.set_developer_mode(bool(_settings.get("developer_mode", false)))
		_hud.set_sound_enabled(bool(_settings.get("sound_enabled", true)))
	AudioServer.set_bus_mute(0, not bool(_settings.get("sound_enabled", true)))
	_refresh_menu_settings()
	if save_settings:
		_save_settings()


func _on_settings_changed(settings: Dictionary) -> void:
	_apply_settings(settings, true)


func _on_sound_toggle_requested() -> void:
	var next := _settings.duplicate(true)
	next["sound_enabled"] = not bool(next.get("sound_enabled", true))
	_apply_settings(next, true)


func _on_view_requested() -> void:
	_reset_camera_orbit()
	_snap_camera = true



func _on_world_map_destination_changed(world_position: Vector2) -> void:
	if world_position == Vector2.INF:
		if _route_guide != null:
			_route_guide.clear_route()
		if _hud != null:
			_hud.clear_destination()
		if _world_map != null:
			_world_map.set_route_path([])
		return
	if _hud != null:
		_hud.set_destination(world_position)
	if _route_guide != null:
		_route_guide.set_destination(world_position)


func _on_route_path_changed(points: Array, _distance_m: float) -> void:
	if points.is_empty():
		if _hud != null:
			_hud.clear_destination()
	elif _hud != null:
		_hud.set_route_path(points)
	if _world_map != null:
		_world_map.set_route_path(points)


func _on_route_arrived() -> void:
	if _world_map != null:
		_world_map.clear_route()


func _on_minimap_points_changed(points: Array) -> void:
	if _hud != null:
		_hud.set_minimap_points(points)


func _on_fast_travel_requested(world_position: Vector2, cost: int, poi_name: String) -> void:
	if _world == null or _vehicle == null or world_position == Vector2.INF:
		return
	var credits := int(_profile.get("credits", 35000))
	if credits < cost:
		if _world_map != null:
			_world_map.set_travel_status("НЕ ХВАТАЕТ CR %d ДЛЯ «%s»" % [cost - credits, poi_name])
		return
	var target := _world.find_nearest_road_transform(Vector3(world_position.x, _vehicle.global_position.y, world_position.y))
	if cost > 0:
		_profile["credits"] = credits - cost
	if _world_map != null:
		_world_map.clear_route()
	_vehicle.global_transform = target
	_vehicle.reset_physics_interpolation()
	_vehicle.reset_to_transform(target)
	_reset_camera_orbit()
	_hide_world_map()
	if _in_menu:
		_enter_game()
	_save_profile()
	if _menu != null:
		_menu.refresh_profile(_profile_view())
		_menu.bind_customization(_customization_view())


func _profile_paint_color() -> Color:
	var value: Variant = _profile.get("paint_color", "7a0609ff")
	if value is Color:
		return value
	var parsed := Color.html(String(value))
	return parsed if parsed.a > 0.01 else Color(0.48, 0.025, 0.035)


func _customization_view() -> Dictionary:
	return {
		"paint_id": String(_profile.get("paint_id", "red")),
		"paint_color": _profile_paint_color(),
		"wheel_finish": String(_profile.get("wheel_finish", "silver")),
		"tuning_level": int(_profile.get("tuning_level", 0)),
		"owned_tuning_level": int(_profile.get("owned_tuning_level", 0)),
		"tuning_owned_max": int(_profile.get("owned_tuning_level", 0)),
		"license_plate": String(_profile.get("license_plate", "GT500-67")),
		"credits": int(_profile.get("credits", 35000)),
	}


func _apply_customization_to_vehicle() -> void:
	if _vehicle == null:
		return
	var owned := clampi(int(_profile.get("owned_tuning_level", 0)), 0, TUNING_COSTS.size() - 1)
	var tuning := clampi(int(_profile.get("tuning_level", 0)), 0, owned)
	_profile["owned_tuning_level"] = owned
	_profile["tuning_level"] = tuning
	_vehicle.set_paint_color(_profile_paint_color())
	_vehicle.set_wheel_finish(String(_profile.get("wheel_finish", "silver")))
	_vehicle.set_tuning_level(tuning)
	_vehicle.set_license_plate(String(_profile.get("license_plate", "GT500-67")))


func _refresh_menu_profile_and_customization() -> void:
	if _menu == null:
		return
	_menu.refresh_profile(_profile_view())
	_menu.bind_customization(_customization_view())


func _on_customization_changed(state: Dictionary) -> void:
	if state.has("paint_id"):
		_profile["paint_id"] = String(state.get("paint_id", "red"))
	if state.has("paint_color"):
		_profile["paint_color"] = (state.get("paint_color") as Color).to_html()
	if state.has("wheel_finish"):
		_profile["wheel_finish"] = String(state.get("wheel_finish", "silver"))
	if state.has("license_plate"):
		_profile["license_plate"] = String(state.get("license_plate", "GT500-67"))
	if state.has("tuning_level"):
		var owned := clampi(int(_profile.get("owned_tuning_level", 0)), 0, TUNING_COSTS.size() - 1)
		_profile["tuning_level"] = clampi(int(state.get("tuning_level", 0)), 0, owned)
	_apply_customization_to_vehicle()
	_save_profile()
	_refresh_menu_profile_and_customization()


func _on_tuning_purchase_requested(level: int) -> void:
	var bounded := clampi(level, 0, TUNING_COSTS.size() - 1)
	var owned := clampi(int(_profile.get("owned_tuning_level", 0)), 0, TUNING_COSTS.size() - 1)
	if bounded > owned:
		var cost := TUNING_COSTS[bounded]
		var credits := int(_profile.get("credits", 35000))
		if credits < cost:
			if _menu != null:
				_menu.set_garage_status("НЕ ХВАТАЕТ CR %d • сначала заработайте кредиты в свободном заезде" % (cost - credits))
			return
		_profile["credits"] = credits - cost
		_profile["owned_tuning_level"] = bounded
	_profile["tuning_level"] = bounded
	_apply_customization_to_vehicle()
	_save_profile()
	_refresh_menu_profile_and_customization()


func _on_profile_changed(player_name: String, avatar_id: String) -> void:
	var clean_name := player_name.strip_edges().to_upper()
	_profile["name"] = clean_name.left(16) if not clean_name.is_empty() else "ИГРОК"
	_profile["avatar_id"] = avatar_id if avatar_id in ["wheel", "star", "flag", "helmet"] else "wheel"
	_save_profile()
	_refresh_menu_profile_and_customization()


func _studio_material(color: Color, roughness: float = 0.72, metallic: float = 0.0, emission_energy: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_energy
	return material


func _add_studio_box(box_name: String, size: Vector3, local_position: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = box_name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = local_position
	instance.material_override = material
	_garage_stage.add_child(instance)
	return instance


func _add_studio_spot(local_position: Vector3, color: Color, energy: float) -> void:
	var spot := SpotLight3D.new()
	spot.position = local_position
	spot.light_color = color
	spot.light_energy = energy
	spot.spot_range = 24.0
	spot.spot_angle = 42.0
	spot.shadow_enabled = true
	_garage_stage.add_child(spot)
	spot.look_at(GARAGE_STUDIO_ORIGIN + Vector3(0.0, 0.8, 0.0), Vector3.UP)


func _create_garage_studio() -> void:
	_garage_stage = Node3D.new()
	_garage_stage.name = "GarageStudio0234"
	_garage_stage.position = GARAGE_STUDIO_ORIGIN
	add_child(_garage_stage)
	var floor_material := _studio_material(Color(0.055, 0.06, 0.07), 0.38, 0.08)
	var wall_material := _studio_material(Color(0.10, 0.11, 0.13), 0.82)
	var accent_material := _studio_material(Color(1.0, 0.55, 0.07), 0.45, 0.0, 1.5)
	var white_light_material := _studio_material(Color(0.92, 0.96, 1.0), 0.3, 0.0, 2.4)
	_add_studio_box("StudioFloor", Vector3(30.0, 0.2, 24.0), Vector3(0.0, -0.1, 0.0), floor_material)
	_add_studio_box("StudioWallBack", Vector3(30.0, 7.0, 0.3), Vector3(0.0, 3.5, 12.0), wall_material)
	_add_studio_box("StudioWallFront", Vector3(30.0, 7.0, 0.3), Vector3(0.0, 3.5, -12.0), wall_material)
	_add_studio_box("StudioWallLeft", Vector3(0.3, 7.0, 24.0), Vector3(-15.0, 3.5, 0.0), wall_material)
	_add_studio_box("StudioWallRight", Vector3(0.3, 7.0, 24.0), Vector3(15.0, 3.5, 0.0), wall_material)
	_add_studio_box("StudioCeiling", Vector3(30.0, 0.25, 24.0), Vector3(0.0, 7.0, 0.0), wall_material)
	for x_value in [-8.0, 0.0, 8.0]:
		_add_studio_box("StudioCeilingLight", Vector3(4.6, 0.08, 0.45), Vector3(float(x_value), 6.84, 0.0), white_light_material)
	_add_studio_box("StudioAccentBack", Vector3(18.0, 0.14, 0.08), Vector3(0.0, 1.15, 11.82), accent_material)
	_add_studio_box("StudioAccentFront", Vector3(18.0, 0.14, 0.08), Vector3(0.0, 1.15, -11.82), accent_material)
	var platform := MeshInstance3D.new()
	platform.name = "StudioTurntable"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 5.8
	cylinder.bottom_radius = 6.1
	cylinder.height = 0.18
	cylinder.radial_segments = 64
	platform.mesh = cylinder
	platform.position = Vector3(0.0, 0.09, 0.0)
	platform.material_override = _studio_material(Color(0.16, 0.17, 0.19), 0.30, 0.22)
	_garage_stage.add_child(platform)
	var omni := OmniLight3D.new()
	omni.position = Vector3(0.0, 5.6, 0.0)
	omni.light_color = Color(0.88, 0.94, 1.0)
	omni.light_energy = 0.55
	omni.omni_range = 20.0
	_garage_stage.add_child(omni)
	_add_studio_spot(Vector3(6.5, 6.2, 5.0), Color(1.0, 0.94, 0.86), 2.4)
	_add_studio_spot(Vector3(-6.5, 6.2, -4.0), Color(0.78, 0.88, 1.0), 1.7)
	_garage_stage.visible = false


func _set_garage_active(active: bool) -> void:
	if _vehicle == null or _garage_stage == null or active == _garage_active:
		return
	_garage_active = active
	_garage_idle_time = 0.0
	if active:
		if not _has_garage_return:
			_garage_return_transform = _vehicle.global_transform
			_has_garage_return = true
		_garage_stage.visible = true
		var target := Transform3D(Basis.IDENTITY, GARAGE_STUDIO_ORIGIN + Vector3(0.0, 0.66, 0.0))
		_vehicle.global_transform = target
		_vehicle.reset_physics_interpolation()
		_vehicle.reset_to_transform(target)
	else:
		_garage_stage.visible = false
		if _has_garage_return:
			_vehicle.global_transform = _garage_return_transform
			_vehicle.reset_physics_interpolation()
			_vehicle.reset_to_transform(_garage_return_transform)
			_has_garage_return = false
	_snap_camera = true


func _on_menu_panel_changed(panel: int) -> void:
	_set_garage_active(panel == 1)


func _on_garage_dragged(relative: Vector2) -> void:
	_garage_yaw = wrapf(_garage_yaw - relative.x * 0.008, -PI, PI)
	_garage_pitch = clampf(_garage_pitch + relative.y * 0.005, 0.12, 0.72)
	_garage_idle_time = 0.0


func _on_garage_zoomed(factor: float) -> void:
	_garage_distance = clampf(_garage_distance * factor, 6.0, 11.0)
	_garage_idle_time = 0.0


func _get_frontend_smoke_state() -> Dictionary:
	return {
		"frontend_0234": true,
		"garage_stage_created": _garage_stage != null,
		"garage_stage_children": _garage_stage.get_child_count() if _garage_stage != null else 0,
		"garage_active": _garage_active,
		"route_guide": _route_guide.get_smoke_state() if _route_guide != null else {},
		"customization": _customization_view(),
		"profile_history_entries": (_profile.get("history", []) as Array).size(),
		"profile_avatar": String(_profile.get("avatar_id", "wheel")),
		"achievement_rewards_claimed": (_profile.get("achievement_rewards_claimed", []) as Array).size(),
		"map_hint_seen": bool(_settings.get("map_hint_seen", false)),
	}


func _load_profile() -> void:
	_profile = {
		"name": "ИГРОК",
		"avatar_id": "wheel",
		"credits": 35000,
		"distance_m": 0.0,
		"top_speed_kmh": 0.0,
		"drift_record_deg": 0.0,
		"play_seconds": 0.0,
		"history": [],
		"achievement_rewards_claimed": [],
		"paint_id": "red",
		"paint_color": "7a0609ff",
		"wheel_finish": "silver",
		"tuning_level": 0,
		"owned_tuning_level": 0,
		"license_plate": "GT500-67",
	}
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_PATH) == OK:
		for key in _profile.keys():
			_profile[key] = cfg.get_value("profile", key, _profile[key])
	if not (_profile.get("history", []) is Array):
		_profile["history"] = []
	if not (_profile.get("achievement_rewards_claimed", []) is Array):
		_profile["achievement_rewards_claimed"] = []
	if String(_profile.get("avatar_id", "wheel")) not in ["wheel", "star", "flag", "helmet"]:
		_profile["avatar_id"] = "wheel"


func _save_profile(record_history: bool = false) -> void:
	if record_history and _session_distance_m >= 50.0:
		var history: Array = (_profile.get("history", []) as Array).duplicate(true)
		history.append({
			"date": Time.get_date_string_from_system(),
			"distance_km": _session_distance_m / 1000.0,
			"top_speed_kmh": _session_top_speed_kmh,
			"drift_deg": _session_drift_deg,
			"duration_sec": _session_seconds,
		})
		while history.size() > 12:
			history.pop_front()
		_profile["history"] = history
		_session_distance_m = 0.0
		_session_top_speed_kmh = 0.0
		_session_drift_deg = 0.0
		_session_seconds = 0.0
	var cfg := ConfigFile.new()
	for key in _profile.keys():
		cfg.set_value("profile", key, _profile[key])
	cfg.save(PROFILE_PATH)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		_save_profile(true)
		_save_settings()



func _achievement_specs(distance_km: float, top_speed: float, drift_record: float, play_seconds: float) -> Array:
	return [
		{"id": "first_km", "title": "Первый километр", "detail": "Проехать 1 км по RichTown • награда CR 250", "reward": 250, "unlocked": distance_km >= 1.0},
		{"id": "distance_50", "title": "Городской марафон", "detail": "Проехать 50 км и открыть уровень 2 • награда CR 2 500", "reward": 2500, "unlocked": distance_km >= 50.0},
		{"id": "speed_150", "title": "Штурм скорости", "detail": "Разогнаться до 150 км/ч • награда CR 750", "reward": 750, "unlocked": top_speed >= 150.0},
		{"id": "speed_200", "title": "Почти предел Shelby", "detail": "Разогнаться до 200 км/ч • награда CR 1 500", "reward": 1500, "unlocked": top_speed >= 200.0},
		{"id": "drift_25", "title": "Боковой стиль", "detail": "Дрифт с углом не меньше 25° • награда CR 750", "reward": 750, "unlocked": drift_record >= 25.0},
		{"id": "hour", "title": "Час за рулём", "detail": "60 минут свободного заезда • награда CR 2 000", "reward": 2000, "unlocked": play_seconds >= 3600.0},
	]


func _claim_achievement_rewards() -> void:
	if _profile.is_empty():
		return
	var claimed: Array = (_profile.get("achievement_rewards_claimed", []) as Array).duplicate()
	var specs := _achievement_specs(
		float(_profile.get("distance_m", 0.0)) / 1000.0,
		float(_profile.get("top_speed_kmh", 0.0)),
		float(_profile.get("drift_record_deg", 0.0)),
		float(_profile.get("play_seconds", 0.0))
	)
	var changed := false
	for spec_variant in specs:
		var spec: Dictionary = spec_variant
		var achievement_id := String(spec.get("id", ""))
		if bool(spec.get("unlocked", false)) and not claimed.has(achievement_id):
			claimed.append(achievement_id)
			_profile["credits"] = int(_profile.get("credits", 35000)) + int(spec.get("reward", 0))
			changed = true
	if changed:
		_profile["achievement_rewards_claimed"] = claimed

func _profile_view() -> Dictionary:
	var distance_km := float(_profile.get("distance_m", 0.0)) / 1000.0
	var level := 1 + int(distance_km / 50.0)
	var level_progress_km := fposmod(distance_km, 50.0)
	var top_speed := float(_profile.get("top_speed_kmh", 0.0))
	var drift_record := float(_profile.get("drift_record_deg", 0.0))
	var play_seconds := float(_profile.get("play_seconds", 0.0))
	var history: Array = (_profile.get("history", []) as Array).duplicate(true)
	if _session_distance_m >= 50.0:
		history.append({
			"date": "СЕЙЧАС",
			"distance_km": _session_distance_m / 1000.0,
			"top_speed_kmh": _session_top_speed_kmh,
			"drift_deg": _session_drift_deg,
			"duration_sec": _session_seconds,
		})
	if history.size() > 5:
		history = history.slice(history.size() - 5)
	var achievements := _achievement_specs(distance_km, top_speed, drift_record, play_seconds)
	return {
		"name": String(_profile.get("name", "ИГРОК")),
		"avatar_id": String(_profile.get("avatar_id", "wheel")),
		"credits": int(_profile.get("credits", 35000)),
		"distance_km": distance_km,
		"top_speed_kmh": top_speed,
		"drift_record_deg": drift_record,
		"play_seconds": play_seconds,
		"level": level,
		"xp_progress": level_progress_km / 50.0,
		"xp_to_next_km": 50.0 - level_progress_km,
		"achievements": achievements,
		"history": history,
		"car_stats": [{
			"name": "Shelby GT500",
			"distance_km": distance_km,
			"top_speed_kmh": top_speed,
			"drift_deg": drift_record,
		}],
	}

func _show_menu() -> void:
	if _smoke_mode or _screenshot_mode or _menu == null:
		return
	if _map_open:
		_hide_world_map()
	_camera_drag_touch_index = -1
	_camera_mouse_dragging = false
	if _hud != null:
		_hud.reset_touch_controls()
	_in_menu = true
	if _vehicle != null:
		_vehicle.freeze = true
		_vehicle.set_physics_process(false)
		_vehicle.set_audio_suspended(true)
	if _hud != null:
		_hud.visible = false
	_menu.refresh_profile(_profile_view())
	_menu.bind_customization(_customization_view())
	if _has_entered_game:
		_menu.show_settings()
	else:
		_menu.show_menu()
	_save_profile()


func _enter_game() -> void:
	_has_entered_game = true
	_set_garage_active(false)
	_camera_drag_touch_index = -1
	_camera_mouse_dragging = false
	if _world_map != null:
		_world_map.hide_map()
	_map_open = false
	_in_menu = false
	if _menu != null:
		_menu.hide_menu()
	if _hud != null:
		_hud.visible = true
	if _vehicle != null:
		_vehicle.freeze = false
		_vehicle.set_physics_process(true)
		_vehicle.set_audio_suspended(false)
	_snap_camera = true


func _show_world_map() -> void:
	if _smoke_mode or _screenshot_mode or _map_open or _world_map == null:
		return
	_camera_drag_touch_index = -1
	_camera_mouse_dragging = false
	_map_open = true
	if _hud != null:
		_hud.reset_touch_controls()
	if _vehicle != null:
		_vehicle.freeze = true
		_vehicle.set_physics_process(false)
		_vehicle.set_audio_suspended(true)
	if _hud != null:
		_hud.visible = false
	var first_map_open := not bool(_settings.get("map_hint_seen", false))
	_world_map.set_first_open_hint(first_map_open)
	if first_map_open:
		_settings["map_hint_seen"] = true
		_save_settings()
		_refresh_menu_settings()
	_world_map.show_map()
	_save_profile()


func _hide_world_map() -> void:
	if _world_map != null:
		_world_map.hide_map()
	if not _map_open:
		return
	_map_open = false
	if _in_menu:
		return
	if _hud != null:
		_hud.visible = true
	if _vehicle != null:
		_vehicle.freeze = false
		_vehicle.set_physics_process(true)
		_vehicle.set_audio_suspended(false)
	_snap_camera = true



func _update_menu_camera(delta: float) -> void:
	if _camera == null or _vehicle == null:
		return
	if _garage_active:
		_garage_idle_time += maxf(delta, 0.0)
		if _garage_idle_time > 2.5:
			_garage_yaw = wrapf(_garage_yaw + delta * 0.16, -PI, PI)
		var centre := GARAGE_STUDIO_ORIGIN + Vector3(0.0, 1.05, 0.0)
		var horizontal := cos(_garage_pitch) * _garage_distance
		var desired := centre + Vector3(sin(_garage_yaw) * horizontal, sin(_garage_pitch) * _garage_distance, cos(_garage_yaw) * horizontal)
		if _snap_camera or _camera.global_position.distance_to(desired) > 30.0:
			_camera.global_position = desired
			_snap_camera = false
		else:
			_camera.global_position = _camera.global_position.lerp(desired, 1.0 - exp(-10.0 * maxf(delta, 0.001)))
		_camera.fov = 46.0
		_camera.look_at(centre, Vector3.UP)
		return
	_camera.fov = 58.0
	_menu_orbit_angle += delta * 0.14
	var centre := _vehicle.get_global_transform_interpolated().origin + Vector3(0.0, 1.05, 0.0)
	var offset := Vector3(sin(_menu_orbit_angle), 0.0, cos(_menu_orbit_angle)) * 7.6 + Vector3(0.0, 2.1, 0.0)
	_camera.global_position = centre + offset
	_camera.look_at(centre, Vector3.UP)


func _accumulate_profile(delta: float) -> void:
	if _vehicle == null or delta <= 0.0:
		return
	var speed_kmh := _vehicle.get_absolute_speed_kmh()
	_profile["distance_m"] = float(_profile.get("distance_m", 0.0)) + speed_kmh / 3.6 * delta
	_profile["top_speed_kmh"] = maxf(float(_profile.get("top_speed_kmh", 0.0)), speed_kmh)
	_profile["play_seconds"] = float(_profile.get("play_seconds", 0.0)) + delta
	var drift_deg := _vehicle.get_drift_angle_degrees() if _vehicle.is_drifting() else 0.0
	_profile["drift_record_deg"] = maxf(float(_profile.get("drift_record_deg", 0.0)), drift_deg)
	_session_distance_m += speed_kmh / 3.6 * delta
	_session_top_speed_kmh = maxf(_session_top_speed_kmh, speed_kmh)
	_session_drift_deg = maxf(_session_drift_deg, drift_deg)
	_session_seconds += delta
	_credit_distance_bank_m += speed_kmh / 3.6 * delta
	while _credit_distance_bank_m >= 100.0:
		_credit_distance_bank_m -= 100.0
		_profile["credits"] = int(_profile.get("credits", 35000)) + 20
	_claim_achievement_rewards()
	_profile_save_timer += delta
	if _profile_save_timer >= 5.0:
		_profile_save_timer = 0.0
		_save_profile()



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
	# Manual camera interpolation (Godot's recommended special case):
	# the camera itself is a top-level, non-interpolated node updated in
	# _process, while its target is the vehicle's interpolated physics
	# transform.  Following global_transform directly made the rendered
	# car step against the camera whenever render/physics cadence split.
	_camera.top_level = true
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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
	if _map_open:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed(&"map_toggle"):
			_hide_world_map()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and not _in_menu and not _smoke_mode and not _screenshot_mode:
		_show_menu()
		get_viewport().set_input_as_handled()
		return
	if _in_menu:
		return
	if event.is_action_pressed(&"map_toggle"):
		_show_world_map()
		get_viewport().set_input_as_handled()
		return
	if _handle_camera_orbit_input(event):
		get_viewport().set_input_as_handled()
		return
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


func _reset_camera_orbit() -> void:
	_camera_orbit_yaw = 0.0
	_camera_orbit_pitch = 0.0
	_camera_orbit_distance_scale = 1.0
	_camera_drag_touch_index = -1
	_camera_mouse_dragging = false
	_camera_manual_timer = 999.0


func _rotate_camera_orbit(relative: Vector2, sensitivity: float) -> void:
	_camera_orbit_yaw = wrapf(_camera_orbit_yaw - relative.x * sensitivity, -PI, PI)
	_camera_orbit_pitch = clampf(
		_camera_orbit_pitch - relative.y * sensitivity,
		CAMERA_ORBIT_PITCH_MIN,
		CAMERA_ORBIT_PITCH_MAX
	)
	_camera_manual_timer = 0.0


func _handle_camera_orbit_input(event: InputEvent) -> bool:
	if _smoke_mode or (_screenshot_mode and _screenshot_free_camera):
		return false
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if touch.double_tap:
				_reset_camera_orbit()
				return true
			if _camera_drag_touch_index == -1:
				_camera_drag_touch_index = touch.index
				return true
		elif touch.index == _camera_drag_touch_index:
			_camera_drag_touch_index = -1
			return true
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _camera_drag_touch_index == -1:
			_camera_drag_touch_index = drag.index
		if drag.index != _camera_drag_touch_index:
			return false
		_rotate_camera_orbit(drag.relative, CAMERA_ORBIT_TOUCH_SENSITIVITY)
		return true
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					_camera_orbit_distance_scale = clampf(_camera_orbit_distance_scale * 0.92, CAMERA_ORBIT_DISTANCE_MIN, CAMERA_ORBIT_DISTANCE_MAX)
					_camera_manual_timer = 0.0
				return true
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					_camera_orbit_distance_scale = clampf(_camera_orbit_distance_scale * 1.08, CAMERA_ORBIT_DISTANCE_MIN, CAMERA_ORBIT_DISTANCE_MAX)
					_camera_manual_timer = 0.0
				return true
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				if button.pressed and button.double_click:
					_reset_camera_orbit()
					return true
				_camera_mouse_dragging = button.pressed
				return true
	elif event is InputEventMouseMotion:
		if not _camera_mouse_dragging:
			return false
		var motion := event as InputEventMouseMotion
		_rotate_camera_orbit(motion.relative, CAMERA_ORBIT_MOUSE_SENSITIVITY)
		return true
	elif event is InputEventMagnifyGesture:
		var gesture := event as InputEventMagnifyGesture
		_camera_orbit_distance_scale = clampf(
			_camera_orbit_distance_scale / maxf(gesture.factor, 0.01),
			CAMERA_ORBIT_DISTANCE_MIN,
			CAMERA_ORBIT_DISTANCE_MAX
		)
		_camera_manual_timer = 0.0
		return true
	return false


func _update_camera_orbit_controls(delta: float) -> void:
	_camera_manual_timer += maxf(delta, 0.0)
	if delta <= 0.0 or _smoke_mode or (_screenshot_mode and _screenshot_free_camera):
		return
	var yaw_velocity := 0.0
	var pitch_velocity := 0.0
	if Input.is_key_pressed(KEY_Q):
		yaw_velocity += 1.9
	if Input.is_key_pressed(KEY_E):
		yaw_velocity -= 1.9
	if Input.is_key_pressed(KEY_PAGEUP):
		pitch_velocity += 1.15
	if Input.is_key_pressed(KEY_PAGEDOWN):
		pitch_velocity -= 1.15
	for device in Input.get_connected_joypads():
		var stick_x := Input.get_joy_axis(device, JOY_AXIS_RIGHT_X)
		var stick_y := Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y)
		if absf(stick_x) > 0.12:
			yaw_velocity -= stick_x * 2.6
		if absf(stick_y) > 0.12:
			pitch_velocity += stick_y * 1.7
	if absf(yaw_velocity) > 0.001 or absf(pitch_velocity) > 0.001:
		_camera_orbit_yaw = wrapf(_camera_orbit_yaw + yaw_velocity * delta, -PI, PI)
		_camera_orbit_pitch = clampf(_camera_orbit_pitch + pitch_velocity * delta, CAMERA_ORBIT_PITCH_MIN, CAMERA_ORBIT_PITCH_MAX)
		_camera_manual_timer = 0.0
	if Input.is_key_pressed(KEY_EQUAL):
		_camera_orbit_distance_scale = clampf(_camera_orbit_distance_scale * exp(-0.65 * delta), CAMERA_ORBIT_DISTANCE_MIN, CAMERA_ORBIT_DISTANCE_MAX)
		_camera_manual_timer = 0.0
	if Input.is_key_pressed(KEY_MINUS):
		_camera_orbit_distance_scale = clampf(_camera_orbit_distance_scale * exp(0.65 * delta), CAMERA_ORBIT_DISTANCE_MIN, CAMERA_ORBIT_DISTANCE_MAX)
		_camera_manual_timer = 0.0


func _cycle_camera() -> void:
	_camera_mode = (_camera_mode + 1) % 3
	_reset_camera_orbit()
	_snap_camera = true
	_refresh_menu_settings()


func _cycle_time() -> void:
	_time_index = (_time_index + 1) % TIME_MODES.size()
	_apply_time_mode()
	_refresh_menu_settings()


func _apply_time_mode() -> void:
	if _world == null:
		return
	var mode := TIME_MODES[_time_index]
	_world.set_time_of_day(mode)
	if _vehicle != null:
		_vehicle.set_headlights_enabled(mode != "day")
	_refresh_menu_settings()


func _on_vehicle_reset_requested() -> void:
	_reset_vehicle_to_road()


func _reset_vehicle_to_road() -> void:
	if _world == null or _vehicle == null:
		return
	var target := _world.find_nearest_road_transform(_vehicle.global_position)
	_vehicle.reset_to_transform(target)
	_reset_camera_orbit()
	_snap_camera = true


func _process(delta: float) -> void:
	_update_adaptive_render_quality(delta)
	if _world != null and _camera != null and _vehicle != null and not _garage_active:
		# 0.2.30 directional streaming: full detail in the view
		# direction, retired render/physics load behind the camera.
		_world.update_streaming(_camera.global_position, -_camera.global_transform.basis.z, _vehicle.global_position, _vehicle.linear_velocity, delta)
	if _in_menu:
		if _camera != null and not _camera.is_current():
			_camera.make_current()
		_update_menu_camera(delta)
		return
	if _map_open:
		if _camera != null and not _camera.is_current():
			_camera.make_current()
		return
	_accumulate_profile(delta)
	if _route_guide != null:
		_route_guide.update_route(delta)
	if _camera != null and not _camera.is_current():
		_camera.make_current()
	if _screenshot_mode and _screenshot_free_camera:
		# The screenshot tour owns the camera for the current shot; the
		# follow rig must not fight the authored viewpoint.
		pass
	else:
		_update_camera_orbit_controls(delta)
		_update_camera(delta, _snap_camera)
		_snap_camera = false
	if _smoke_mode and not _smoke_completed:
		_smoke_frames += 1
		if _smoke_frames >= 90:
			_smoke_completed = true
			_run_smoke_checks()


func _vehicle_horizontal_yaw(vehicle_transform: Transform3D) -> float:
	var forward := -vehicle_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return _camera_follow_yaw
	forward = forward.normalized()
	return atan2(-forward.x, -forward.z)


func _update_camera(delta: float, snap: bool) -> void:
	if _camera == null or _vehicle == null:
		return

	var speed_kmh := _vehicle.get_absolute_speed_kmh()
	var speed_ratio := clampf(speed_kmh / 210.0, 0.0, 1.0)
	var vehicle_transform := _vehicle.get_global_transform_interpolated()
	var vehicle_position := vehicle_transform.origin
	var raw_follow_yaw := _vehicle_horizontal_yaw(vehicle_transform)
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
			var hood_position := vehicle_transform * Vector3(0.0, 1.12, -0.32)
			var hood_look := Vector3(
				-sin(_camera_orbit_yaw) * cos(_camera_orbit_pitch),
				-sin(_camera_orbit_pitch),
				-cos(_camera_orbit_yaw) * cos(_camera_orbit_pitch)
			)
			var hood_target := hood_position + vehicle_transform.basis * hood_look * 34.0
			_camera.global_position = hood_position
			_camera.look_at(hood_target, Vector3.UP)
		CAMERA_TOP:
			var top_basis := Basis(Vector3.UP, _camera_follow_yaw + _camera_orbit_yaw)
			var top_position := vehicle_position + top_basis * Vector3(0.0, 31.0, 14.0 * _camera_orbit_distance_scale)
			var top_up := -top_basis.z
			top_up.y = 0.0
			top_up = top_up.normalized() if top_up.length_squared() > 0.0001 else Vector3(0.0, 0.0, -1.0)
			_camera.global_position = top_position
			_camera.look_at(vehicle_position + Vector3.UP * 1.0, top_up)
		_:
			var base_distance := 6.15 + speed_ratio * 2.15
			var base_height := 2.05 + speed_ratio * 0.38
			var distance := base_distance * _camera_orbit_distance_scale
			var base_pitch := atan2(base_height, base_distance)
			var total_pitch := clampf(base_pitch + _camera_orbit_pitch, -0.04, 1.18)
			var height := tan(total_pitch) * distance
			var orbit_forward_factor := clampf(cos(_camera_orbit_yaw), 0.0, 1.0)
			var drift_offset_target := clampf(-_vehicle.get_lateral_speed_ms() * 0.055, -0.65, 0.65) * orbit_forward_factor
			if snap or delta <= 0.0:
				_camera_drift_offset_smooth = drift_offset_target
			else:
				_camera_drift_offset_smooth = lerpf(
					_camera_drift_offset_smooth,
					drift_offset_target,
					1.0 - exp(-7.0 * delta)
				)
			var follow_basis := Basis(Vector3.UP, _camera_follow_yaw)
			var orbit_basis := Basis(Vector3.UP, _camera_follow_yaw + _camera_orbit_yaw)
			var desired_position := vehicle_position + orbit_basis * Vector3(_camera_drift_offset_smooth, height, distance)
			desired_position = _get_safe_camera_position(desired_position, vehicle_position)
			if snap or delta <= 0.0:
				_camera.global_position = desired_position
			else:
				var position_rate := 14.0 if _camera_manual_timer < 0.30 else 7.5
				var weight := 1.0 - exp(-position_rate * delta)
				_camera.global_position = _camera.global_position.lerp(desired_position, weight)
			var forward := -follow_basis.z
			var target := vehicle_position + Vector3.UP * 1.12 + forward * (6.0 + speed_ratio * 6.0) * orbit_forward_factor
			if snap or delta <= 0.0:
				_camera_target_smooth = target
			else:
				var target_rate := 17.0 if _camera_manual_timer < 0.30 else 12.0
				_camera_target_smooth = _camera_target_smooth.lerp(target, 1.0 - exp(-target_rate * delta))
			if _camera.global_position.distance_squared_to(_camera_target_smooth) > 0.001:
				_camera.look_at(_camera_target_smooth, Vector3.UP)
				var roll := clampf(_camera_drift_offset_smooth * 0.055, -0.035, 0.035) * orbit_forward_factor
				_camera.rotate_object_local(Vector3.FORWARD, roll)

	# Almost imperceptible vibration only while nitro is active.  Using
	# camera offsets avoids changing the smoothed global position.
	var shake := 0.0
	if _vehicle.is_boosting():
		shake = 0.010 + speed_ratio * 0.012
	var shake_time := float(Time.get_ticks_msec()) * 0.043
	_camera.h_offset = sin(shake_time * 1.37) * shake
	_camera.v_offset = cos(shake_time * 1.71) * shake * 0.7


func _get_safe_camera_position(desired_position: Vector3, focus_position: Vector3) -> Vector3:
	if _vehicle == null:
		return desired_position
	var origin := focus_position + Vector3.UP * 1.25
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


func get_camera_control_state() -> Dictionary:
	return {
		"free_orbit_0231": true,
		"camera_interpolation_off": _camera != null and _camera.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF,
		"camera_top_level": _camera != null and _camera.top_level,
		"target_interpolated": true,
		"physics_interpolation_project": bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false)),
		"mode": _camera_mode,
		"orbit_yaw": _camera_orbit_yaw,
		"orbit_pitch": _camera_orbit_pitch,
		"orbit_distance_scale": _camera_orbit_distance_scale,
		"touch_orbit": true,
		"mouse_orbit": true,
		"gamepad_orbit": true,
	}


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
	if _world_map == null:
		failures.append("world map node is missing")
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
	if not bool(enhancement_stats.get("curtain_wall_reflective_glass_0227", false)) or float(enhancement_stats.get("glass_smoke_luminance_min_0227", 0.0)) < 0.24 or not bool(enhancement_stats.get("guardrail_local_axis_0227", false)):
		failures.append("0.2.27 reflective glass/guardrail local-axis pass is incomplete: %s" % str(enhancement_stats))
	if not bool(enhancement_stats.get("paving_variety_0228", false)) or not bool(enhancement_stats.get("paving_running_bond_0228", false)):
		failures.append("0.2.28 paving variety pass is incomplete: %s" % str(enhancement_stats))
	if not bool(enhancement_stats.get("directional_streaming_0230", false)) or int(enhancement_stats.get("streaming_chunks_total", 0)) < 60 or int(enhancement_stats.get("streaming_colliders_total", 0)) < 300 or int(enhancement_stats.get("streaming_colliders_active", 0)) >= int(enhancement_stats.get("streaming_colliders_total", 0)):
		failures.append("0.2.30 directional streaming pass is incomplete: %s" % str(enhancement_stats))
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
	if int(enhancement_stats.get("premium_hotel_models", 0)) < 3 or not bool(enhancement_stats.get("premium_hotel_fixed_scale", false)) or not bool(enhancement_stats.get("premium_hotel_detail_pass", false)) or not bool(enhancement_stats.get("premium_hotel_material_pass", false)) or not bool(enhancement_stats.get("premium_hotel_site_pass", false)) or not bool(enhancement_stats.get("premium_hotel_fronts_corniche", false)) or int(enhancement_stats.get("premium_hotel_model_parts", 0)) < 10 or int(enhancement_stats.get("premium_hotel_triangles", 0)) < 30000 or absf(float(enhancement_stats.get("premium_hotel_height_m", 0.0)) - 49.07) > 0.20 or absf(float(enhancement_stats.get("premium_hotel_width_m", 0.0)) - 33.6) > 0.25 or absf(float(enhancement_stats.get("premium_hotel_depth_m", 0.0)) - 26.0) > 0.25:
		failures.append("0.2.26 Building Model No.8 RichTown Grand Hotel pass is incomplete: %s" % str(enhancement_stats))
	if not bool(enhancement_stats.get("premium_museum_built", false)) or not bool(enhancement_stats.get("premium_museum_fixed_scale", false)) or not bool(enhancement_stats.get("premium_museum_detail_pass", false)) or not bool(enhancement_stats.get("premium_museum_material_pass", false)) or not bool(enhancement_stats.get("premium_museum_site_pass", false)) or not bool(enhancement_stats.get("premium_museum_fronts_fountain", false)) or int(enhancement_stats.get("premium_museum_model_parts", 0)) < 14 or int(enhancement_stats.get("premium_museum_triangles", 0)) < 12000 or absf(float(enhancement_stats.get("premium_museum_height_m", 0.0)) - 19.0) > 0.20 or absf(float(enhancement_stats.get("premium_museum_width_m", 0.0)) - 54.0) > 0.25 or absf(float(enhancement_stats.get("premium_museum_depth_m", 0.0)) - 38.0) > 0.25:
		failures.append("0.2.29 Building Model No.9 RichTown Museum pass is incomplete: %s" % str(enhancement_stats))
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
	var vehicle_audio_state: Dictionary = smoothing_state.get("vehicle_audio", {})
	if not bool(smoothing_state.get("ignition_0235", false)) or int(smoothing_state.get("engine_state", -1)) != NativeVehicle.ENGINE_OFF or bool(smoothing_state.get("engine_running", true)) or _vehicle.get_gear_label() != "N" or _vehicle.get_rpm_ratio() > 0.001 or not bool(vehicle_audio_state.get("recorded_audio_0235", false)) or not bool(vehicle_audio_state.get("recorded_gt500_bank", false)) or int(vehicle_audio_state.get("on_loop_count", 0)) != 16 or int(vehicle_audio_state.get("off_loop_count", 0)) != 16 or not bool(vehicle_audio_state.get("streams_ready", false)) or int(vehicle_audio_state.get("players_created", 0)) < 7 or not bool(vehicle_audio_state.get("bus_ready", false)):
		failures.append("0.2.35 ignition-off spawn / recorded Shelby GT500 audio pass is incomplete: smoothing=%s audio=%s gear=%s rpm_ratio=%.3f" % [str(smoothing_state), str(vehicle_audio_state), _vehicle.get_gear_label(), _vehicle.get_rpm_ratio()])
	var camera_control_state := get_camera_control_state()
	if not bool(smoothing_state.get("physics_interpolation_vehicle", false)) or int(smoothing_state.get("contact_patch_samples", 0)) < 3 or not bool(smoothing_state.get("tyre_relaxation", false)) or not bool(smoothing_state.get("filtered_suspension_velocity", false)) or not bool(smoothing_state.get("precision_steering_0231", false)) or float(drive_base_state.get("steer_response", 0.0)) < 20.0 or float(drive_base_state.get("steer_actuator_rate_low", 0.0)) < 6.0 or float(drive_base_state.get("digital_steer_attack", 0.0)) < 5.0 or float(drive_base_state.get("digital_steer_initial_bite", 0.0)) < 0.15 or not bool(camera_control_state.get("free_orbit_0231", false)) or not bool(camera_control_state.get("camera_interpolation_off", false)) or not bool(camera_control_state.get("camera_top_level", false)) or not bool(camera_control_state.get("target_interpolated", false)) or not bool(camera_control_state.get("physics_interpolation_project", false)) or not bool(camera_control_state.get("touch_orbit", false)) or not bool(camera_control_state.get("mouse_orbit", false)) or not bool(camera_control_state.get("gamepad_orbit", false)) or not is_finite(float(camera_control_state.get("orbit_yaw", 0.0))) or not is_finite(float(camera_control_state.get("orbit_pitch", 0.0))):
		failures.append("0.2.31 anti-jitter / precision steering / free-orbit camera pass is incomplete: smoothing=%s drive=%s camera=%s" % [str(smoothing_state), str(drive_base_state), str(camera_control_state)])
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

	_on_world_map_destination_changed(Vector2(665.0, -170.0))
	var hud_state := _hud.get_smoke_state()
	var minimap_state: Dictionary = hud_state.get("minimap", {})
	var gauge_state: Dictionary = hud_state.get("dashboard_gauge", {})
	var gas_pedal_state: Dictionary = hud_state.get("gas_pedal", {})
	var brake_pedal_state: Dictionary = hud_state.get("brake_pedal", {})
	var nitro_button_state: Dictionary = hud_state.get("nitro_button", {})
	var drift_button_state: Dictionary = hud_state.get("drift_button", {})
	var ignition_button_state: Dictionary = hud_state.get("ignition_button", {})
	var viewport_size: Vector2 = hud_state.get("viewport_size", Vector2.ZERO)
	var minimap_rect: Rect2 = minimap_state.get("rect", Rect2())
	var gauge_rect: Rect2 = gauge_state.get("rect", Rect2())
	var gas_rect: Rect2 = gas_pedal_state.get("rect", Rect2())
	var brake_rect: Rect2 = brake_pedal_state.get("rect", Rect2())
	var nitro_rect: Rect2 = nitro_button_state.get("rect", Rect2())
	var drift_rect: Rect2 = drift_button_state.get("rect", Rect2())
	var ignition_rect: Rect2 = ignition_button_state.get("rect", Rect2())
	var safe_left := viewport_size.x * 0.03 - 1.0
	var safe_top := viewport_size.y * 0.04 - 1.0
	var safe_right := viewport_size.x * 0.97 + 1.0
	var safe_bottom := viewport_size.y * 0.96 + 1.0
	var hud_rects_safe := minimap_rect.position.x >= safe_left and minimap_rect.position.y >= safe_top and gauge_rect.end.x <= safe_right and gauge_rect.position.y >= safe_top and gas_rect.end.x <= safe_right and gas_rect.end.y <= safe_bottom
	var hud_rects_visible := _rect_is_on_screen(minimap_rect, viewport_size) and _rect_is_on_screen(gauge_rect, viewport_size) and _rect_is_on_screen(gas_rect, viewport_size) and _rect_is_on_screen(brake_rect, viewport_size) and _rect_is_on_screen(nitro_rect, viewport_size) and _rect_is_on_screen(drift_rect, viewport_size) and _rect_is_on_screen(ignition_rect, viewport_size)
	if not bool(hud_state.get("hud_0233", false)) or not bool(hud_state.get("safe_area_3pct_4pct", false)) or not hud_rects_safe or not hud_rects_visible or not bool(minimap_state.get("circular_heading_up_0233", false)) or int(minimap_state.get("roads", 0)) < 35 or int(minimap_state.get("parks", 0)) < 3 or int(minimap_state.get("pois", 0)) < 20 or not bool(minimap_state.get("has_destination", false)) or not bool(gauge_state.get("circular_gauge_0233", false)) or String(gauge_state.get("speed_text", "")) != "0" or not bool(gas_pedal_state.get("analog_pedal_0233", false)) or not bool(brake_pedal_state.get("analog_pedal_0233", false)) or gas_rect.size.y < viewport_size.y * 0.28 or brake_rect.size.y < viewport_size.y * 0.28 or absf(gas_rect.position.x - brake_rect.end.x - 8.0) > 1.5 or not bool(nitro_button_state.get("round_action_0233", false)) or not bool(drift_button_state.get("round_action_0233", false)) or nitro_rect.position.x - drift_rect.end.x < 15.0 or bool(hud_state.get("performance_visible", true)) != bool(hud_state.get("developer_mode", false)):
		failures.append("0.2.34 safe-area circular HUD / analog pedals / road route pass is incomplete: hud=%s minimap=%s gauge=%s" % [str(hud_state), str(minimap_state), str(gauge_state)])
	if not bool(hud_state.get("hud_0235", false)) or not bool(ignition_button_state.get("ignition_button_0235", false)) or not bool(hud_state.get("ignition_under_minimap", false)) or not bool(hud_state.get("ignition_same_size_as_drift", false)) or ignition_rect.size.x < 56.0 or ignition_rect.size.y < 56.0:
		failures.append("0.2.35 ignition button under the minimap / handbrake-size pass is incomplete: hud=%s ignition=%s drift_rect=%s" % [str(hud_state), str(ignition_button_state), str(drift_rect)])
	var menu_state := _menu.get_smoke_state()
	var spec_sheet := _vehicle.get_spec_sheet()
	var world_map_state := _world_map.get_smoke_state()
	var steering_wheel_state: Dictionary = hud_state.get("steering_wheel", {})
	var steering_wheel_rect: Rect2 = steering_wheel_state.get("rect", Rect2())
	if not bool(world_map_state.get("world_map_0232", false)) or not bool(world_map_state.get("created", false)) or not bool(world_map_state.get("data_bound", false)) or bool(world_map_state.get("visible_now", true)) or int(world_map_state.get("districts", 0)) < 5 or int(world_map_state.get("district_labels", 0)) < 5 or int(world_map_state.get("roads", 0)) < 50 or int(world_map_state.get("road_labels", 0)) < 6 or int(world_map_state.get("pois", 0)) < 20 or int(world_map_state.get("poi_labels", 0)) < 20 or int(world_map_state.get("parks", 0)) < 3 or not bool(steering_wheel_state.get("touch_steering_wheel_0232", false)) or not bool(steering_wheel_state.get("created", false)) or float(steering_wheel_state.get("max_lock_degrees", 0.0)) < 130.0 or float(steering_wheel_state.get("centering_rate", 0.0)) < 4.0 or not _rect_is_on_screen(steering_wheel_rect, viewport_size) or steering_wheel_rect.size.x < 230.0 or not bool(steering_wheel_state.get("configurable_size_0233", false)) or not bool(smoothing_state.get("touch_steering_wheel_0232", false)) or not bool(smoothing_state.get("analog_touch_pedals_0233", false)) or int(world_map_state.get("minimap_points", 0)) < 20 or not bool(world_map_state.get("world_map_0234", false)) or not bool(world_map_state.get("route_button_created", false)) or not bool(world_map_state.get("fast_travel_button_created", false)) or int(world_map_state.get("filter_buttons", 0)) < 5 or not bool(world_map_state.get("district_circles_removed", false)) or not bool(world_map_state.get("zoom_label_tiers_0234", false)):
		failures.append("0.2.34 steering-wheel / filtered zoom-tier world-map pass is incomplete: map=%s wheel=%s smoothing=%s" % [str(world_map_state), str(steering_wheel_state), str(smoothing_state)])
	if not bool(menu_state.get("created", false)) or int(menu_state.get("panels", 0)) < 5 or int(menu_state.get("tabs", 0)) < 5 or not bool(menu_state.get("specs_bound", false)) or not bool(menu_state.get("profile_bound", false)) or not bool(menu_state.get("world_map_button", false)) or not bool(menu_state.get("settings_panel_0233", false)) or int(menu_state.get("control_buttons", 0)) < 3 or not bool(menu_state.get("settings_bound", false)) or not bool(menu_state.get("version_button_created", false)) or bool(menu_state.get("visible_now", true)) or int(spec_sheet.get("power_hp", 0)) != 365 or int(spec_sheet.get("torque_nm", 0)) != 569 or int(spec_sheet.get("top_speed_kmh", 0)) != 207 or int(spec_sheet.get("gears", 0)) != 4:
		failures.append("0.2.34 main menu/settings / Shelby GT500 spec pass is incomplete: menu=%s spec=%s" % [str(menu_state), str(spec_sheet)])

	var frontend_state := _get_frontend_smoke_state()
	var route_state: Dictionary = frontend_state.get("route_guide", {})
	var customization_state := _vehicle.get_customization_state()
	var tuning_preview := _vehicle.get_tuning_preview(2)
	if not bool(frontend_state.get("frontend_0234", false)) or not bool(frontend_state.get("garage_stage_created", false)) or int(frontend_state.get("garage_stage_children", 0)) < 12 or not bool(menu_state.get("clean_menu_0234", false)) or not bool(menu_state.get("store_hidden_0234", false)) or not bool(menu_state.get("icon_tabs_0234", false)) or not bool(menu_state.get("backdrop_blur_0234", false)) or not bool(menu_state.get("customization_bound", false)) or not bool(route_state.get("route_guide_0234", false)) or int(route_state.get("graph_nodes", 0)) < 300 or int(route_state.get("graph_edges", 0)) < 300 or not bool(route_state.get("has_route", false)) or int(route_state.get("path_points", 0)) < 8 or float(route_state.get("path_distance_m", 0.0)) < 350.0 or int(minimap_state.get("route_points", 0)) < 8 or not bool(minimap_state.get("road_route_0234", false)) or not bool(customization_state.get("customization_0234", false)) or int(tuning_preview.get("power_hp", 0)) != 423 or int(tuning_preview.get("torque_nm", 0)) != 660 or int(tuning_preview.get("performance_index", 0)) != 701 or String(tuning_preview.get("class_label", "")) != "S1":
		failures.append("0.2.34 clean menu / garage studio / Shelby customization / AStar road-route pass is incomplete: frontend=%s route=%s custom=%s tuning=%s" % [str(frontend_state), str(route_state), str(customization_state), str(tuning_preview)])

	if failures.is_empty():
		print("[native-smoke] PASS world_geometry=%d vehicle_geometry=%d vehicle=%s camera=%s minimap=%s traffic=%s enhancements=%s vehicle_aabb=%s surface=%s gear=%s rpm=%.0f dynamic=%s speed_post=%s drive_base=%s smoothing=%s road_visual=%s render_quality=%s" % [
			world_geometry_count,
			vehicle_geometry_count,
			str(_vehicle.global_position),
			str(_camera.global_position),
			str(minimap_state),
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
	# CI renders on Mesa lavapipe (software Vulkan): MSAA is the one
	# full-screen cost that changes almost nothing for a visual audit,
	# so swap it for FXAA in this mode only.  Shipped quality settings
	# on real devices are untouched.
	var viewport := get_viewport()
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	print("[native-screenshots] adapter=%s vendor=%s" % [
		RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_vendor(),
	])
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
			"vehicle": "spawn", "gameplay_camera": true, "frames": 6,
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
	for i in range(4):
		await RenderingServer.frame_post_draw

	var saved := 0
	for shot in shots:
		if await _capture_screenshot(shot):
			saved += 1
	print("[native-screenshots] DONE saved=%d/%d dir=%s" % [saved, shots.size(), _screenshot_dir])
	get_tree().quit(0 if saved == shots.size() else 1)


func _capture_screenshot(shot: Dictionary) -> bool:
	var shot_started_ms := Time.get_ticks_msec()
	var shot_name := String(shot.get("name", "shot"))
	var wanted_time_index := maxi(TIME_MODES.find(String(shot.get("time", "day"))), 0)
	if wanted_time_index != _time_index:
		_time_index = wanted_time_index
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

	var frames := int(shot.get("frames", 3))
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
	print("[native-screenshots] SAVED %s (%dx%d) in %.1fs" % [
		path, image.get_width(), image.get_height(),
		float(Time.get_ticks_msec() - shot_started_ms) / 1000.0,
	])
	return true
