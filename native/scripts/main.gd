extends Node3D

## Native game bootstrap: world, player vehicle, camera rig and HUD.
## This is the first playable Godot vertical slice for the native rebuild.
## Future systems should be added as separate native nodes/scripts
## rather than growing this coordinator.

const WorldBuilderScript := preload("res://scripts/world_builder.gd")
const VehicleScript := preload("res://scripts/vehicle_controller.gd")
const SpeedPostScript := preload("res://scripts/speed_post.gd")
const AtmosphereFxScript := preload("res://scripts/atmosphere_fx.gd")
const HudScript := preload("res://scripts/hud.gd")
const MainMenuScript := preload("res://scripts/main_menu.gd")
const WorldMapScript := preload("res://scripts/world_map.gd")
const RouteGuideScript := preload("res://scripts/route_guide.gd")
const LoadingScreenScript := preload("res://scripts/loading_screen.gd")
const PROFILE_PATH := "user://nitches_profile.cfg"
const NET_CONFIG_PATH := "user://nitches_net.cfg"

## 0.2.61 progression economy: the Shelbie GT500 and RichTown are
## free; the other three cars and two worlds are bought with CR
## earned by driving (200 CR/km), achievements and daily quests.
const START_CREDITS := 15000
const WORLD_PRICES := {"richtown": 0, "desert": 25000, "greenforest": 80000}

## daily quest pool: 10 of these 14 are active each day.  IDs,
## metrics, targets and rewards MUST mirror QUEST_POOL in
## server/src/index.js.  A full day of quests pays roughly
## 6 500-8 000 CR — about a week of quests per car tier, faster
## with driving income and one-off achievements on top.
const QUEST_POOL := [
	{"id": "dist_5", "metric": "distance_km", "target": 5.0, "reward": 400, "title": "Разминка", "detail": "Проехать 5 км", "unit": "км"},
	{"id": "dist_15", "metric": "distance_km", "target": 15.0, "reward": 900, "title": "Дальний круг", "detail": "Проехать 15 км", "unit": "км"},
	{"id": "dist_30", "metric": "distance_km", "target": 30.0, "reward": 1600, "title": "Марафон", "detail": "Проехать 30 км", "unit": "км"},
	{"id": "dist_50", "metric": "distance_km", "target": 50.0, "reward": 2500, "title": "Неутомимый", "detail": "Проехать 50 км", "unit": "км"},
	{"id": "speed_160", "metric": "top_speed_kmh", "target": 160.0, "reward": 500, "title": "Быстрый старт", "detail": "Разогнаться до 160 км/ч", "unit": "км/ч"},
	{"id": "speed_200", "metric": "top_speed_kmh", "target": 200.0, "reward": 900, "title": "Гонщик", "detail": "Разогнаться до 200 км/ч", "unit": "км/ч"},
	{"id": "drift_time_30", "metric": "drift_seconds", "target": 30.0, "reward": 600, "title": "Первый занос", "detail": "Дрифтить суммарно 30 секунд", "unit": "с"},
	{"id": "drift_time_90", "metric": "drift_seconds", "target": 90.0, "reward": 1100, "title": "Мастер заноса", "detail": "Дрифтить суммарно 90 секунд", "unit": "с"},
	{"id": "drift_angle_30", "metric": "drift_angle_deg", "target": 30.0, "reward": 500, "title": "Угол атаки", "detail": "Держать угол дрифта 30°", "unit": "°"},
	{"id": "drift_angle_40", "metric": "drift_angle_deg", "target": 40.0, "reward": 900, "title": "На грани", "detail": "Держать угол дрифта 40°", "unit": "°"},
	{"id": "play_10", "metric": "play_minutes", "target": 10.0, "reward": 350, "title": "Заглянул погонять", "detail": "Играть 10 минут", "unit": "мин"},
	{"id": "play_25", "metric": "play_minutes", "target": 25.0, "reward": 700, "title": "Вечер за рулём", "detail": "Играть 25 минут", "unit": "мин"},
	{"id": "nitro_20", "metric": "nitro_seconds", "target": 20.0, "reward": 550, "title": "Азот!", "detail": "Использовать нитро 20 секунд", "unit": "с"},
	{"id": "earn_2000", "metric": "credits_from_driving", "target": 2000.0, "reward": 600, "title": "Заработок", "detail": "Заработать 2000 CR ездой", "unit": "CR"},
]

## 0.2.62 wheel of fortune (home screen): +1 free spin per day and
## +1 per driver level, capped.  Prizes are CR plus one extra-spin
## slot; average payout ~1000 CR per spin keeps the car/world
## prices meaningful while giving a daily reason to open the game.
const WHEEL_SEGMENTS := [
	{"cr": 200, "kind": "cr"}, {"cr": 750, "kind": "cr"}, {"cr": 300, "kind": "cr"},
	{"cr": 1500, "kind": "cr"}, {"cr": 250, "kind": "cr"}, {"cr": 500, "kind": "cr"},
	{"cr": 5000, "kind": "cr"}, {"cr": 400, "kind": "cr"}, {"cr": 1000, "kind": "cr"},
	{"cr": 0, "kind": "spin"}, {"cr": 600, "kind": "cr"}, {"cr": 2000, "kind": "cr"},
]
const WHEEL_SPIN_CAP := 5
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
var _selected_world_id := "richtown"
var _vehicle: NativeVehicle
var _hud: NativeHud
var _menu: NativeMainMenu
var _world_map: NativeWorldMap
var _route_guide: NativeRouteGuide
var _loading_screen: NativeLoadingScreen
var _is_bootstrapping := false
var _bootstrap_completed := false
var _world_switch_in_progress := false
var _map_open := false
var _in_menu := false
var _has_entered_game := false
var _settings: Dictionary = {}
var _graphics_quality_state: Dictionary = {}
var _menu_orbit_angle := 0.0
var _garage_stage: Node3D
var _garage_active := false
var _garage_return_transform := Transform3D.IDENTITY
var _has_garage_return := false
var _garage_yaw := 0.65
var _garage_pitch := 0.30
var _garage_distance := 10.8
var _garage_idle_time := 0.0
var _session_distance_m := 0.0
var _session_top_speed_kmh := 0.0
var _session_drift_deg := 0.0
var _session_seconds := 0.0
var _credit_distance_bank_m := 0.0

## 0.2.61 online session state: account + multiplayer (main_menu
## collects the input; NitchesNetClient / NitchesMpClient do IO).
var _net: NitchesNetClient
var _mp: NitchesMpClient
var _server_url := ""
var _auth_token := ""
var _account_username := ""
var _account_role := "player"
var _logged_in := false
var _online_quests: Array = []
var _net_sync_timer := 0.0
var _quest_progress_pushed: Dictionary = {}
var _selected_car_id := NativeCarCatalog.DEFAULT_CAR_ID
var _car_customizations: Dictionary = {}
var _car_stats: Dictionary = {}
var _current_car_marketing_shot := 0
var _profile: Dictionary = {}
var _profile_save_timer := 0.0
var _camera: Camera3D
var _speed_post: NativeSpeedPost
var _atmosphere_fx: NativeAtmosphereFX
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

	# 0.2.47: settings must be known before the world is built so
	# the persisted world choice (or --native-world= override used
	# by CI screenshot runs) selects the data set up front.
	_load_settings()
	_selected_world_id = String(_settings.get("selected_world", "richtown"))
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if String(arg).begins_with("--native-world="):
			var wanted := String(arg).trim_prefix("--native-world=")
			if wanted == "richtown" or wanted == "desert" or wanted == "greenforest":
				_selected_world_id = wanted
	_ensure_loading_screen()
	if _smoke_mode or _screenshot_mode:
		_loading_screen.hide_immediately()
		_bootstrap_game_sync()
		return
	_is_bootstrapping = true
	_show_loading_screen("Открываем фестиваль скорости")
	call_deferred("_bootstrap_game_async")


func _bootstrap_game_sync() -> void:
	_create_world_node()
	var stats := _world.build_world()
	_handle_world_build_result(_world, stats)
	_bootstrap_create_vehicle()
	_bootstrap_create_camera_and_systems()
	_bootstrap_create_profile_and_menu()
	_bootstrap_create_world_map()
	_bootstrap_finish_startup()
	_bootstrap_completed = true


func _bootstrap_game_async() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_set_loading_progress(0.04, "Читаем данные мира")
	await get_tree().process_frame
	_create_world_node()
	_world.process_mode = Node.PROCESS_MODE_DISABLED
	await _build_world_with_loading(_world, 0.08, 0.72)
	_world.process_mode = Node.PROCESS_MODE_INHERIT
	_set_loading_progress(0.76, "Готовим автомобиль")
	await get_tree().process_frame
	_bootstrap_create_vehicle()
	_set_loading_progress(0.84, "Настраиваем камеру и эффекты")
	await get_tree().process_frame
	_bootstrap_create_camera_and_systems()
	_set_loading_progress(0.92, "Собираем меню и профиль")
	await get_tree().process_frame
	_bootstrap_create_profile_and_menu()
	_set_loading_progress(0.97, "Подключаем карту и маршрут")
	await get_tree().process_frame
	_bootstrap_create_world_map()
	_set_loading_progress(1.0, "Мир готов")
	_bootstrap_finish_startup()
	_bootstrap_completed = true
	_is_bootstrapping = false
	await _finish_loading_screen()


func _create_world_node() -> void:
	_world = WorldBuilderScript.new() as NativeWorldBuilder
	_world.name = "NativeWorld"
	_world.world_id = _selected_world_id
	add_child(_world)


func _handle_world_build_result(world: NativeWorldBuilder, stats: Dictionary) -> void:
	print("[native] World build stats (%s): " % world.world_id, stats)
	if not world.build_error.is_empty():
		push_error("Native world failed to build: %s" % world.build_error)
		if _loading_screen != null and _loading_screen.visible:
			_loading_screen.set_error(world.build_error)


func _build_world_with_loading(world: NativeWorldBuilder, from_fraction: float, to_fraction: float) -> Dictionary:
	world.begin_build_world()
	while not world.is_build_finished():
		var before: Dictionary = world.get_build_progress_state()
		_set_loading_progress(
			lerpf(from_fraction, to_fraction, float(before.get("fraction", 0.0))),
			String(before.get("stage", "Строим мир"))
		)
		await get_tree().process_frame
		var after: Dictionary = world.build_world_step()
		_set_loading_progress(
			lerpf(from_fraction, to_fraction, float(after.get("fraction", 0.0))),
			String(after.get("completed_stage", after.get("stage", "Строим мир")))
		)
	var stats: Dictionary = {}
	if world.get_world_data().is_empty():
		stats = {"error": world.build_error}
	else:
		stats = world.get_stats()
	_handle_world_build_result(world, stats)
	if not world.build_error.is_empty() and _loading_screen != null and _loading_screen.visible:
		await _loading_screen.error_continue_requested
		_loading_screen.clear_error()
	return stats


func _ensure_loading_screen() -> void:
	if _loading_screen != null:
		return
	_loading_screen = LoadingScreenScript.new() as NativeLoadingScreen
	_loading_screen.name = "LoadingScreen"
	add_child(_loading_screen)


func _show_loading_screen(initial_stage: String) -> void:
	_ensure_loading_screen()
	_loading_screen.restart(_selected_world_id)
	_loading_screen.set_progress(0.0, initial_stage)


func _set_loading_progress(fraction: float, stage: String) -> void:
	if _loading_screen != null:
		_loading_screen.set_progress(fraction, stage)


func _finish_loading_screen() -> void:
	if _loading_screen != null:
		await _loading_screen.finish()


func _bootstrap_create_vehicle() -> void:
	_vehicle = VehicleScript.new() as NativeVehicle
	_selected_car_id = _load_saved_selected_car_id()
	_vehicle.configure_car(_selected_car_id)
	add_child(_vehicle)
	_vehicle.set_world(_world)
	_vehicle.reset_requested.connect(_on_vehicle_reset_requested)
	_vehicle.car_changed.connect(_on_vehicle_car_changed)
	_vehicle.reset_to_transform(_world.spawn_transform)
	_vehicle.global_transform = _world.spawn_transform
	_vehicle.set_audio_camera_mode(_camera_mode)

	# 0.2.5: all AI/parked traffic cars are removed by request.  The
	# freed CPU/GPU budget is spent on the denser static city instead;
	# there is deliberately no hidden traffic node or parked-car fleet.
	print("[native] Traffic removed: player vehicle only")


func _bootstrap_create_camera_and_systems() -> void:
	_create_camera()
	_atmosphere_fx = AtmosphereFxScript.new() as NativeAtmosphereFX
	_atmosphere_fx.configure(_vehicle, _camera, _world)
	_atmosphere_fx.set_active(false)
	add_child(_atmosphere_fx)
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


func _bootstrap_create_profile_and_menu() -> void:
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
	_menu.bind_car_catalog(_car_catalog_view())
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
	_menu.car_selection_requested.connect(_select_car)
	_menu.world_selected.connect(switch_world)
	_menu.car_purchase_requested.connect(_buy_car)
	_menu.world_purchase_requested.connect(_buy_world)
	_menu.daily_quest_claim_requested.connect(_claim_daily_quest)
	_menu.account_register_requested.connect(_on_account_register_requested)
	_menu.account_login_requested.connect(_on_account_login_requested)
	_menu.account_logout_requested.connect(_on_account_logout_requested)
	_menu.feedback_requested.connect(_on_feedback_requested)
	_menu.leaderboard_requested.connect(_on_leaderboard_requested)
	_menu.admin_requested.connect(_on_admin_requested)
	_menu.multiplayer_join_requested.connect(_on_multiplayer_join_requested)
	_menu.multiplayer_leave_requested.connect(_on_multiplayer_leave_requested)
	_menu.wheel_spin_requested.connect(_on_wheel_spin_requested)
	_menu.set_current_world(_selected_world_id)
	_setup_net()
	_apply_settings(_settings, false)


func _bootstrap_create_world_map() -> void:
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


func _bootstrap_finish_startup() -> void:
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
		"graphics_quality": "balanced",
		"selected_world": "richtown",
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
	var graphics_quality := String(result.get("graphics_quality", "balanced"))
	if graphics_quality != "performance" and graphics_quality != "balanced" and graphics_quality != "beauty":
		graphics_quality = "balanced"
	result["graphics_quality"] = graphics_quality
	var selected_world := String(result.get("selected_world", "richtown"))
	if selected_world != "richtown" and selected_world != "desert" and selected_world != "greenforest":
		selected_world = "richtown"
	result["selected_world"] = selected_world
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
	_apply_graphics_quality()
	_refresh_menu_settings()
	if save_settings:
		_save_settings()


## 0.2.44: one user preset drives every scalable graphics cost —
## detail draw distances, shadow range, camera far plane + skyline
## scale, atmosphere particle budgets/effects and the 3D render
## scale.  "balanced" is exactly the shipped 0.2.43 look; nothing is
## silently downgraded for everyone any more.
func _apply_graphics_quality() -> void:
	var quality := String(_settings.get("graphics_quality", "balanced"))
	var detail_scale := 1.0
	var shadow_distance := 175.0
	var camera_far := 2100.0
	var particle_scale := 0.55 if OS.has_feature("android") else 1.0
	var shafts := true
	var bokeh := true
	var render_scale := 1.0
	match quality:
		"performance":
			detail_scale = 0.7
			shadow_distance = 120.0
			camera_far = 1650.0
			particle_scale = 0.3
			shafts = false
			bokeh = false
			render_scale = 0.8
		"beauty":
			detail_scale = 1.7
			shadow_distance = 230.0
			particle_scale = 1.0
	if _world != null:
		_world.set_quality_detail_scale(detail_scale)
		_world.set_quality_shadow_distance(shadow_distance)
		# Skyline rings keep identical angular size at any far plane.
		_world.set_skyline_scale(camera_far / 2100.0)
	if _camera != null:
		_camera.far = camera_far
	if _atmosphere_fx != null:
		_atmosphere_fx.set_quality(particle_scale, shafts, bokeh)
	get_viewport().scaling_3d_scale = render_scale
	_graphics_quality_state = {
		"graphics_quality_0244": true,
		"preset": quality,
		"detail_scale": detail_scale,
		"shadow_distance": shadow_distance,
		"camera_far": camera_far,
		"particle_scale": particle_scale,
		"shafts": shafts,
		"bokeh": bokeh,
		"render_scale": render_scale,
	}


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


func _load_saved_selected_car_id() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_PATH) == OK:
		return NativeCarCatalog.normalize_id(String(cfg.get_value("profile", "selected_car_id", NativeCarCatalog.DEFAULT_CAR_ID)))
	return NativeCarCatalog.DEFAULT_CAR_ID


func _color_from_profile_value(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	var parsed := Color.html(String(value))
	return parsed if parsed.a > 0.01 else fallback


func _customization_view_for(car_id: String) -> Dictionary:
	var normalized := NativeCarCatalog.normalize_id(car_id)
	var defaults := NativeCarCatalog.default_customization(normalized)
	var source := _car_customizations.get(normalized, {}) as Dictionary
	var result := defaults.duplicate(true)
	for key in source.keys():
		result[key] = source[key]
	result["car_id"] = normalized
	result["paint_color"] = _color_from_profile_value(result.get("paint_color", defaults.get("paint_color")), defaults.get("paint_color", Color(0.48, 0.025, 0.035)) as Color)
	result["owned_tuning_level"] = clampi(int(result.get("owned_tuning_level", result.get("tuning_owned_max", 0))), 0, TUNING_COSTS.size() - 1)
	result["tuning_owned_max"] = int(result.get("owned_tuning_level", 0))
	result["tuning_level"] = clampi(int(result.get("tuning_level", 0)), 0, int(result.get("owned_tuning_level", 0)))
	result["credits"] = int(_profile.get("credits", 35000))
	var definition := NativeCarCatalog.get_car(normalized)
	result["car_name"] = String(definition.get("name", normalized))
	result["steering_wheel_texture"] = String(definition.get("steering_wheel_texture", NativeCarCatalog.COMMON_STEERING_WHEEL_TEXTURE))
	result["steering_wheel_id"] = String(definition.get("steering_wheel_id", NativeCarCatalog.COMMON_STEERING_WHEEL_ID))
	return result


func _active_customization() -> Dictionary:
	return _customization_view_for(_selected_car_id)


func _store_active_customization(customization: Dictionary) -> void:
	var stored := customization.duplicate(true)
	stored.erase("credits")
	stored.erase("car_name")
	stored.erase("steering_wheel_texture")
	stored.erase("steering_wheel_id")
	_car_customizations[_selected_car_id] = stored
	_profile["paint_id"] = String(stored.get("paint_id", "red"))
	_profile["paint_color"] = (stored.get("paint_color") as Color).to_html() if stored.get("paint_color") is Color else String(stored.get("paint_color", "7a0609ff"))
	_profile["wheel_finish"] = String(stored.get("wheel_finish", "silver"))
	_profile["tuning_level"] = int(stored.get("tuning_level", 0))
	_profile["owned_tuning_level"] = int(stored.get("owned_tuning_level", 0))
	_profile["license_plate"] = String(stored.get("license_plate", "NITCHES"))


func _profile_paint_color() -> Color:
	return _active_customization().get("paint_color", Color(0.48, 0.025, 0.035)) as Color


func _customization_view() -> Dictionary:
	return _active_customization()


func _apply_customization_to_vehicle() -> void:
	if _vehicle == null:
		return
	var customization := _active_customization()
	_store_active_customization(customization)
	_vehicle.set_paint_color(customization.get("paint_color") as Color)
	_vehicle.set_wheel_finish(String(customization.get("wheel_finish", "silver")))
	_vehicle.set_tuning_level(int(customization.get("tuning_level", 0)))
	_vehicle.set_license_plate(String(customization.get("license_plate", "NITCHES")))
	_apply_steering_wheel_to_hud()


func _apply_steering_wheel_to_hud() -> void:
	if _hud == null or _vehicle == null:
		return
	var specs := _vehicle.get_spec_sheet()
	_hud.set_steering_wheel_texture_path(String(specs.get("steering_wheel_texture", NativeCarCatalog.COMMON_STEERING_WHEEL_TEXTURE)))


func _car_catalog_view() -> Array:
	return NativeCarCatalog.get_menu_cars(_car_customizations, _car_stats, _selected_car_id)


func _capture_active_customization() -> void:
	if _vehicle == null:
		return
	var old_id := _vehicle.get_car_id()
	var customization := _customization_view_for(old_id)
	var state := _vehicle.get_customization_state()
	customization["paint_color"] = state.get("paint_color", customization.get("paint_color"))
	customization["wheel_finish"] = String(state.get("wheel_finish", customization.get("wheel_finish", "silver")))
	customization["tuning_level"] = int(state.get("tuning_level", customization.get("tuning_level", 0)))
	customization["license_plate"] = String(state.get("license_plate", customization.get("license_plate", "NITCHES")))
	_car_customizations[old_id] = customization.duplicate(true)


func _select_car(car_id: String) -> void:
	if _vehicle == null:
		return
	var next_id := NativeCarCatalog.normalize_id(car_id)
	if not _is_car_owned(next_id) and not _smoke_mode and not _screenshot_mode:
		if _menu != null:
			_menu.set_garage_status("%s ещё не куплен — загляните в Магазин." % String(NativeCarCatalog.get_car(next_id).get("name", next_id)))
		_refresh_menu_profile_and_customization()
		return
	if next_id == _vehicle.get_car_id():
		_selected_car_id = next_id
		_refresh_menu_profile_and_customization()
		return
	_capture_active_customization()
	if _vehicle.switch_car(next_id):
		_selected_car_id = next_id


func _on_vehicle_car_changed(car_id: String) -> void:
	_selected_car_id = NativeCarCatalog.normalize_id(car_id)
	_profile["selected_car_id"] = _selected_car_id
	_apply_customization_to_vehicle()
	_apply_time_mode()
	_snap_camera = true
	if _menu != null:
		_menu.bind_specs(_vehicle.get_spec_sheet())
	_refresh_menu_profile_and_customization()
	_save_profile()


func _car_stats_view() -> Array:
	var rows: Array = []
	for car in NativeCarCatalog.get_cars():
		var car_id := String(car.get("id", ""))
		var stats := _car_stats.get(car_id, {}) as Dictionary
		rows.append({
			"car_id": car_id,
			"name": String(car.get("name", car_id)),
			"distance_km": float(stats.get("distance_km", 0.0)),
			"top_speed_kmh": float(stats.get("top_speed_kmh", 0.0)),
			"drift_deg": float(stats.get("drift_deg", 0.0)),
		})
	return rows


func _refresh_menu_profile_and_customization() -> void:
	if _menu == null:
		return
	_menu.refresh_profile(_profile_view())
	_menu.bind_customization(_customization_view())
	_menu.bind_car_catalog(_car_catalog_view())


func _on_customization_changed(state: Dictionary) -> void:
	var customization := _active_customization()
	if state.has("paint_id"):
		customization["paint_id"] = String(state.get("paint_id", "red"))
	if state.has("paint_color"):
		customization["paint_color"] = state.get("paint_color")
	if state.has("wheel_finish"):
		customization["wheel_finish"] = String(state.get("wheel_finish", "silver"))
	if state.has("license_plate"):
		customization["license_plate"] = String(state.get("license_plate", "NITCHES"))
	if state.has("tuning_level"):
		var owned := clampi(int(customization.get("owned_tuning_level", 0)), 0, TUNING_COSTS.size() - 1)
		customization["tuning_level"] = clampi(int(state.get("tuning_level", 0)), 0, owned)
	_store_active_customization(customization)
	_apply_customization_to_vehicle()
	_save_profile()
	_refresh_menu_profile_and_customization()


func _on_tuning_purchase_requested(level: int) -> void:
	var bounded := clampi(level, 0, TUNING_COSTS.size() - 1)
	var customization := _active_customization()
	var owned := clampi(int(customization.get("owned_tuning_level", 0)), 0, TUNING_COSTS.size() - 1)
	if bounded > owned:
		var cost := TUNING_COSTS[bounded]
		var credits := int(_profile.get("credits", 35000))
		if credits < cost:
			if _menu != null:
				_menu.set_garage_status("НЕ ХВАТАЕТ CR %d • сначала заработайте кредиты в свободном заезде" % (cost - credits))
			return
		_profile["credits"] = credits - cost
		customization["owned_tuning_level"] = bounded
	customization["tuning_level"] = bounded
	_store_active_customization(customization)
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
	var floor_material := _studio_material(Color(0.20, 0.215, 0.235), 0.16, 0.34)
	var wall_material := _studio_material(Color(0.13, 0.14, 0.16), 0.72)
	var accent_material := _studio_material(Color(1.0, 0.55, 0.07), 0.45, 0.0, 1.5)
	var white_light_material := _studio_material(Color(0.92, 0.96, 1.0), 0.3, 0.0, 2.4)
	_add_studio_box("StudioFloor", Vector3(30.0, 0.2, 24.0), Vector3(0.0, -0.1, 0.0), floor_material)
	_add_studio_box("StudioWallBack", Vector3(30.0, 7.0, 0.3), Vector3(0.0, 3.5, 12.0), wall_material)
	_add_studio_box("StudioWallFront", Vector3(30.0, 7.0, 0.3), Vector3(0.0, 3.5, -12.0), wall_material)
	_add_studio_box("StudioWallLeft", Vector3(0.3, 7.0, 24.0), Vector3(-15.0, 3.5, 0.0), wall_material)
	_add_studio_box("StudioWallRight", Vector3(0.3, 7.0, 24.0), Vector3(15.0, 3.5, 0.0), wall_material)
	_add_studio_box("StudioCeiling", Vector3(30.0, 0.25, 24.0), Vector3(0.0, 7.0, 0.0), wall_material)
	for z_value in [-6.5, 0.0, 6.5]:
		for x_value in [-8.0, 0.0, 8.0]:
			_add_studio_box("StudioCeilingLight", Vector3(4.6, 0.08, 0.45), Vector3(float(x_value), 6.84, float(z_value)), white_light_material)
	_add_studio_box("StudioAccentBack", Vector3(18.0, 0.14, 0.08), Vector3(0.0, 1.15, 11.82), accent_material)
	_add_studio_box("StudioAccentFront", Vector3(18.0, 0.14, 0.08), Vector3(0.0, 1.15, -11.82), accent_material)
	_add_studio_box("StudioAccentLeft", Vector3(0.08, 0.14, 18.0), Vector3(-14.82, 1.15, 0.0), accent_material)
	_add_studio_box("StudioAccentRight", Vector3(0.08, 0.14, 18.0), Vector3(14.82, 1.15, 0.0), accent_material)
	for x_value in [-9.0, -3.0, 3.0, 9.0]:
		_add_studio_box("StudioWallLightBack", Vector3(0.32, 4.6, 0.08), Vector3(float(x_value), 3.7, 11.80), white_light_material)
		_add_studio_box("StudioWallLightFront", Vector3(0.32, 4.6, 0.08), Vector3(float(x_value), 3.7, -11.80), white_light_material)
	var platform := MeshInstance3D.new()
	platform.name = "StudioTurntable"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 5.8
	cylinder.bottom_radius = 6.1
	cylinder.height = 0.18
	cylinder.radial_segments = 64
	platform.mesh = cylinder
	platform.position = Vector3(0.0, 0.09, 0.0)
	platform.material_override = _studio_material(Color(0.24, 0.25, 0.27), 0.14, 0.46)
	_garage_stage.add_child(platform)
	var reflection_probe := ReflectionProbe.new()
	reflection_probe.name = "StudioReflectionProbe0236"
	reflection_probe.position = Vector3(0.0, 2.2, 0.0)
	reflection_probe.size = Vector3(20.0, 6.5, 20.0)
	reflection_probe.blend_distance = 2.0
	reflection_probe.origin_offset = Vector3.ZERO
	reflection_probe.box_projection = true
	reflection_probe.enable_shadows = false
	reflection_probe.intensity = 0.85
	reflection_probe.max_distance = 28.0
	reflection_probe.mesh_lod_threshold = 0.65
	reflection_probe.ambient_mode = ReflectionProbe.AMBIENT_ENVIRONMENT
	reflection_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	reflection_probe.cull_mask = (1 << 19) - 1
	_garage_stage.add_child(reflection_probe)
	var omni := OmniLight3D.new()
	omni.position = Vector3(0.0, 5.6, 0.0)
	omni.light_color = Color(0.88, 0.94, 1.0)
	omni.light_energy = 0.55
	omni.omni_range = 20.0
	_garage_stage.add_child(omni)
	_add_studio_spot(Vector3(6.5, 6.2, 5.0), Color(1.0, 0.94, 0.86), 2.4)
	_add_studio_spot(Vector3(-6.5, 6.2, -4.0), Color(0.78, 0.88, 1.0), 1.7)
	_add_studio_spot(Vector3(0.0, 6.4, -7.5), Color(1.0, 0.98, 0.94), 1.45)
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
		var target := Transform3D(Basis.IDENTITY, GARAGE_STUDIO_ORIGIN + Vector3(0.0, 0.66 + maxf(float(_vehicle.get_car_definition().get("wheel_ray_y", 0.58)) - 0.58, 0.0), 0.0))
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
	# Garage (1) and Store (2) both present the live selected-car studio.
	_set_garage_active(panel == NativeMainMenu.PANEL_GARAGE or panel == NativeMainMenu.PANEL_STORE)
	_apply_menu_lightweight()


func _on_garage_dragged(relative: Vector2) -> void:
	_garage_yaw = wrapf(_garage_yaw - relative.x * 0.008, -PI, PI)
	_garage_pitch = clampf(_garage_pitch + relative.y * 0.005, 0.12, 0.72)
	_garage_idle_time = 0.0


func _on_garage_zoomed(factor: float) -> void:
	_garage_distance = clampf(_garage_distance * factor, 7.0, 14.0)
	_garage_idle_time = 0.0


func _get_frontend_smoke_state() -> Dictionary:
	return {
		"frontend_0234": true,
		"multi_car_0240": true,
		"selected_car_id": _selected_car_id,
		"catalog_cars": NativeCarCatalog.car_count(),
		"catalog_view_cars": _car_catalog_view().size(),
		"car_customization_slots": _car_customizations.size(),
		"car_stat_slots": _car_stats.size(),
		"marketing_car_shots": _current_car_marketing_shot,
		"garage_stage_created": _garage_stage != null,
		"garage_stage_children": _garage_stage.get_child_count() if _garage_stage != null else 0,
		"garage_active": _garage_active,
		"studio_reflection_probe_0236": _garage_stage != null and _garage_stage.get_node_or_null("StudioReflectionProbe0236") != null,
		"garage_distance_0236": _garage_distance,
		"store_uses_studio_0236": NativeMainMenu.PANEL_STORE == 2,
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
		"credits": START_CREDITS,
		"distance_m": 0.0,
		"top_speed_kmh": 0.0,
		"drift_record_deg": 0.0,
		"play_seconds": 0.0,
		"history": [],
		"achievement_rewards_claimed": [],
		"selected_car_id": NativeCarCatalog.DEFAULT_CAR_ID,
		"car_customizations": {},
		"car_stats": {},
		"owned_cars": [],
		"owned_worlds": [],
		"daily": {},
		"economy_v": 0,
		"wheel_spins": 1,
		"wheel_last_day": "",
		"wheel_level": 1,
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
	_selected_car_id = NativeCarCatalog.normalize_id(String(_profile.get("selected_car_id", _selected_car_id)))
	_profile["selected_car_id"] = _selected_car_id
	if not (_profile.get("car_customizations", {}) is Dictionary):
		_profile["car_customizations"] = {}
	_car_customizations = (_profile.get("car_customizations", {}) as Dictionary).duplicate(true)
	for car_id in NativeCarCatalog.car_ids():
		var defaults := NativeCarCatalog.default_customization(car_id)
		var stored := _car_customizations.get(car_id, {}) as Dictionary
		var merged := defaults.duplicate(true)
		for key in stored.keys():
			merged[key] = stored[key]
		_car_customizations[car_id] = merged
	if (_profile.get("car_customizations", {}) as Dictionary).is_empty():
		# 0.2.40 migration: every pre-catalogue save described the one
		# Shelby, so its paint/wheels/tuning/plate land in that slot;
		# the three new cars start from their catalogue defaults.
		var legacy := _car_customizations.get(NativeCarCatalog.DEFAULT_CAR_ID, {}) as Dictionary
		legacy["paint_id"] = String(_profile.get("paint_id", "red"))
		legacy["paint_color"] = _color_from_profile_value(_profile.get("paint_color", "7a0609ff"), Color(0.48, 0.025, 0.035))
		legacy["wheel_finish"] = String(_profile.get("wheel_finish", "silver"))
		legacy["owned_tuning_level"] = clampi(int(_profile.get("owned_tuning_level", 0)), 0, TUNING_COSTS.size() - 1)
		legacy["tuning_level"] = clampi(int(_profile.get("tuning_level", 0)), 0, int(legacy.get("owned_tuning_level", 0)))
		legacy["license_plate"] = String(_profile.get("license_plate", "GT500-67"))
		_car_customizations[NativeCarCatalog.DEFAULT_CAR_ID] = legacy
	if not (_profile.get("car_stats", {}) is Dictionary):
		_profile["car_stats"] = {}
	_car_stats = (_profile.get("car_stats", {}) as Dictionary).duplicate(true)
	if _car_stats.is_empty():
		_car_stats[NativeCarCatalog.DEFAULT_CAR_ID] = {
			"distance_km": float(_profile.get("distance_m", 0.0)) / 1000.0,
			"top_speed_kmh": float(_profile.get("top_speed_kmh", 0.0)),
			"drift_deg": float(_profile.get("drift_record_deg", 0.0)),
			"play_seconds": float(_profile.get("play_seconds", 0.0)),
		}
	for car_id in NativeCarCatalog.car_ids():
		if not _car_stats.has(car_id):
			_car_stats[car_id] = {"distance_km": 0.0, "top_speed_kmh": 0.0, "drift_deg": 0.0, "play_seconds": 0.0}
	_profile["car_customizations"] = _car_customizations.duplicate(true)
	_profile["car_stats"] = _car_stats.duplicate(true)
	# 0.2.61 progression migration (runs once): pre-economy saves
	# keep every car they actually drove (>=0.5 km) and the desert
	# if the old 50 000 CR balance rule had already unlocked it.
	# New profiles start with the Shelbie + RichTown and buy the
	# rest with CR.  The Green Forest stays a purchase for all.
	if int(_profile.get("economy_v", 0)) < 1:
		var migrated_cars: Array = [NativeCarCatalog.DEFAULT_CAR_ID]
		for car_id in NativeCarCatalog.car_ids():
			var driven := _car_stats.get(car_id, {}) as Dictionary
			if float(driven.get("distance_km", 0.0)) >= 0.5 and car_id not in migrated_cars:
				migrated_cars.append(car_id)
		var migrated_worlds: Array = ["richtown"]
		if int(_profile.get("credits", START_CREDITS)) >= 50000:
			migrated_worlds.append("desert")
		# Worlds were free for everyone in 0.2.48-0.2.60, so an
		# existing player also keeps the world they last played in.
		if _selected_world_id != "richtown" and _selected_world_id not in migrated_worlds and float(_profile.get("distance_m", 0.0)) > 0.0:
			migrated_worlds.append(_selected_world_id)
		_profile["owned_cars"] = migrated_cars
		_profile["owned_worlds"] = migrated_worlds
		_profile["economy_v"] = 1
	if not (_profile.get("owned_cars", []) is Array) or (_profile.get("owned_cars", []) as Array).is_empty():
		_profile["owned_cars"] = [NativeCarCatalog.DEFAULT_CAR_ID]
	if not (_profile.get("owned_worlds", []) is Array) or (_profile.get("owned_worlds", []) as Array).is_empty():
		_profile["owned_worlds"] = ["richtown"]
	if _selected_car_id not in (_profile.get("owned_cars", []) as Array):
		_selected_car_id = NativeCarCatalog.DEFAULT_CAR_ID
		_profile["selected_car_id"] = _selected_car_id
	_grant_wheel_spins()
	_store_active_customization(_active_customization())


func _save_profile(record_history: bool = false) -> void:
	_capture_active_customization()
	_profile["selected_car_id"] = _selected_car_id
	_profile["car_customizations"] = _car_customizations.duplicate(true)
	_profile["car_stats"] = _car_stats.duplicate(true)
	if record_history and _session_distance_m >= 50.0:
		var history: Array = (_profile.get("history", []) as Array).duplicate(true)
		history.append({
			"date": Time.get_date_string_from_system(),
			"car_id": _selected_car_id,
			"car_name": String(NativeCarCatalog.get_car(_selected_car_id).get("name", _selected_car_id)),
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
		if _bootstrap_completed:
			_save_profile(true)
		_save_settings()



func _achievement_specs(distance_km: float, top_speed: float, drift_record: float, play_seconds: float) -> Array:
	var play_minutes := play_seconds / 60.0
	return [
		{"id": "first_km", "title": "Первый километр", "detail": "Проехать 1 км по RichTown", "reward": 250, "unlocked": distance_km >= 1.0, "current": distance_km, "target": 1.0, "unit": "км", "progress": clampf(distance_km / 1.0, 0.0, 1.0)},
		{"id": "distance_50", "title": "Городской марафон", "detail": "Проехать 50 км и открыть уровень 2", "reward": 2500, "unlocked": distance_km >= 50.0, "current": distance_km, "target": 50.0, "unit": "км", "progress": clampf(distance_km / 50.0, 0.0, 1.0)},
		{"id": "speed_150", "title": "Штурм скорости", "detail": "Разогнаться до 150 км/ч", "reward": 750, "unlocked": top_speed >= 150.0, "current": top_speed, "target": 150.0, "unit": "км/ч", "progress": clampf(top_speed / 150.0, 0.0, 1.0)},
		{"id": "speed_200", "title": "Двести по городу", "detail": "Разогнаться до 200 км/ч", "reward": 1500, "unlocked": top_speed >= 200.0, "current": top_speed, "target": 200.0, "unit": "км/ч", "progress": clampf(top_speed / 200.0, 0.0, 1.0)},
		{"id": "drift_25", "title": "Боковой стиль", "detail": "Дрифт с углом не меньше 25°", "reward": 750, "unlocked": drift_record >= 25.0, "current": drift_record, "target": 25.0, "unit": "°", "progress": clampf(drift_record / 25.0, 0.0, 1.0)},
		{"id": "hour", "title": "Час за рулём", "detail": "60 минут свободного заезда", "reward": 2000, "unlocked": play_seconds >= 3600.0, "current": play_minutes, "target": 60.0, "unit": "мин", "progress": clampf(play_minutes / 60.0, 0.0, 1.0)},
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
			_profile["credits"] = _credits() + int(spec.get("reward", 0))
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
			"car_id": _selected_car_id,
			"car_name": String(NativeCarCatalog.get_car(_selected_car_id).get("name", _selected_car_id)),
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
		"owned_cars": (_profile.get("owned_cars", []) as Array).duplicate(),
		"owned_worlds": (_profile.get("owned_worlds", []) as Array).duplicate(),
		"world_prices": WORLD_PRICES.duplicate(),
		"daily_quests": _daily_quests_view(),
		"wheel_spins": int(_profile.get("wheel_spins", 0)),
		"wheel_segments": WHEEL_SEGMENTS.duplicate(true),
		"account": _account_view(),
		"selected_car_id": _selected_car_id,
		"car_stats": _car_stats_view(),
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
	_apply_menu_lightweight()
	if _atmosphere_fx != null:
		_atmosphere_fx.set_active(false)
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
	_apply_menu_lightweight()
	if _atmosphere_fx != null:
		_atmosphere_fx.set_active(true)
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
	if _atmosphere_fx != null:
		_atmosphere_fx.set_active(false)
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
	if _atmosphere_fx != null:
		_atmosphere_fx.set_active(not _in_menu)
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
		var car_definition := _vehicle.get_car_definition()
		var centre := GARAGE_STUDIO_ORIGIN + Vector3(0.0, clampf(float(car_definition.get("height_m", 1.32)) * 0.72, 0.82, 1.18), 0.0)
		var garage_distance := _garage_distance * float(car_definition.get("garage_camera_scale", 1.0))
		var horizontal := cos(_garage_pitch) * garage_distance
		var desired := centre + Vector3(sin(_garage_yaw) * horizontal, sin(_garage_pitch) * garage_distance, cos(_garage_yaw) * horizontal)
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
	var car_definition := _vehicle.get_car_definition()
	var centre := _vehicle.get_global_transform_interpolated().origin + Vector3(0.0, clampf(float(car_definition.get("height_m", 1.32)) * 0.72, 0.82, 1.18), 0.0)
	var offset := Vector3(sin(_menu_orbit_angle), 0.0, cos(_menu_orbit_angle)) * 7.6 * float(car_definition.get("garage_camera_scale", 1.0)) + Vector3(0.0, 2.1, 0.0)
	_camera.global_position = centre + offset
	_camera.look_at(centre, Vector3.UP)


## --- 0.2.61 progression: owned cars/worlds, purchases ---

func _credits() -> int:
	return int(_profile.get("credits", START_CREDITS))


func _fmt_cr(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = " " + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out


func _is_car_owned(car_id: String) -> bool:
	return NativeCarCatalog.normalize_id(car_id) in (_profile.get("owned_cars", []) as Array)


func _is_world_owned(world_id: String) -> bool:
	return world_id in (_profile.get("owned_worlds", []) as Array)


func _buy_car(car_id: String) -> void:
	var id := NativeCarCatalog.normalize_id(car_id)
	if _is_car_owned(id):
		_select_car(id)
		return
	var price := int(NativeCarCatalog.get_car(id).get("price_cr", 0))
	if _credits() < price:
		if _menu != null:
			_menu.set_garage_status("Не хватает CR: нужно %s, у вас %s. Зарабатывайте ездой и ежедневными заданиями (вкладка «Онлайн»)." % [_fmt_cr(price), _fmt_cr(_credits())])
		return
	_profile["credits"] = _credits() - price
	var owned: Array = (_profile.get("owned_cars", []) as Array).duplicate()
	owned.append(id)
	_profile["owned_cars"] = owned
	_save_profile()
	_sync_progress_online()
	_select_car(id)


func _buy_world(world_id: String) -> void:
	if _is_world_owned(world_id):
		switch_world(world_id)
		return
	var price := int(WORLD_PRICES.get(world_id, 0))
	if _credits() < price:
		_refresh_menu_profile_and_customization()
		return
	_profile["credits"] = _credits() - price
	var owned: Array = (_profile.get("owned_worlds", []) as Array).duplicate()
	owned.append(world_id)
	_profile["owned_worlds"] = owned
	_save_profile()
	_sync_progress_online()
	switch_world(world_id)


## --- 0.2.61 daily quests ---

func _daily_today() -> Dictionary:
	var day := Time.get_date_string_from_system()
	var daily := _profile.get("daily", {}) as Dictionary
	if String(daily.get("day", "")) != day:
		daily = {
			"day": day,
			"distance_m": 0.0,
			"drift_seconds": 0.0,
			"drift_angle_deg": 0.0,
			"top_speed_kmh": 0.0,
			"play_seconds": 0.0,
			"nitro_seconds": 0.0,
			"credits_from_driving": 0,
			"claimed": [],
		}
		_profile["daily"] = daily
		_quest_progress_pushed.clear()
	return daily


func _daily_metric(daily: Dictionary, metric: String) -> float:
	match metric:
		"distance_km":
			return float(daily.get("distance_m", 0.0)) / 1000.0
		"top_speed_kmh":
			return float(daily.get("top_speed_kmh", 0.0))
		"drift_seconds":
			return float(daily.get("drift_seconds", 0.0))
		"drift_angle_deg":
			return float(daily.get("drift_angle_deg", 0.0))
		"play_minutes":
			return float(daily.get("play_seconds", 0.0)) / 60.0
		"nitro_seconds":
			return float(daily.get("nitro_seconds", 0.0))
		"credits_from_driving":
			return float(int(daily.get("credits_from_driving", 0)))
		_:
			return 0.0


func _quest_spec(quest_id: String) -> Dictionary:
	for spec_variant in QUEST_POOL:
		var spec: Dictionary = spec_variant
		if String(spec.get("id", "")) == quest_id:
			return spec
	return {}


func _local_daily_quests() -> Array:
	# Offline/guest daily set: deterministic by date + profile name.
	# Logged-in players get the server set instead (authoritative).
	var daily := _daily_today()
	var key := String(daily.get("day", "")) + ":" + String(_profile.get("name", "ИГРОК"))
	var seed_value := 2166136261
	for i in key.length():
		seed_value = int((seed_value ^ key.unicode_at(i)) * 16777619) & 0xFFFFFFFF
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var order: Array = []
	for i in QUEST_POOL.size():
		order.append(i)
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = order[i]
		order[i] = order[j]
		order[j] = tmp
	var claimed: Array = daily.get("claimed", [])
	var out: Array = []
	for k in mini(10, order.size()):
		var spec: Dictionary = (QUEST_POOL[int(order[k])] as Dictionary).duplicate()
		var value := _daily_metric(daily, String(spec.get("metric", "")))
		spec["progress"] = value
		spec["claimed"] = String(spec.get("id", "")) in claimed
		spec["completed"] = value >= float(spec.get("target", 0.0))
		out.append(spec)
	return out


func _daily_quests_view() -> Array:
	if _logged_in and not _online_quests.is_empty():
		var daily := _daily_today()
		var out: Array = []
		for row_variant in _online_quests:
			var row: Dictionary = row_variant
			var spec := _quest_spec(String(row.get("id", "")))
			if spec.is_empty():
				continue
			var merged := spec.duplicate()
			merged["target"] = float(row.get("target", spec.get("target", 0.0)))
			merged["reward"] = int(row.get("reward", spec.get("reward", 0)))
			var value := maxf(_daily_metric(daily, String(spec.get("metric", ""))), float(row.get("progress", 0.0)))
			merged["progress"] = value
			merged["claimed"] = bool(row.get("claimed", false))
			merged["completed"] = value >= float(merged["target"])
			out.append(merged)
		if not out.is_empty():
			return out
	return _local_daily_quests()


func _claim_daily_quest(quest_id: String) -> void:
	var spec := _quest_spec(quest_id)
	if spec.is_empty():
		return
	var daily := _daily_today()
	var value := _daily_metric(daily, String(spec.get("metric", "")))
	if _logged_in and _net != null:
		_net.claim_quest(quest_id, value)
		return
	var claimed: Array = (daily.get("claimed", []) as Array).duplicate()
	if quest_id in claimed or value < float(spec.get("target", 0.0)):
		return
	claimed.append(quest_id)
	daily["claimed"] = claimed
	_profile["daily"] = daily
	_profile["credits"] = _credits() + int(spec.get("reward", 0))
	_save_profile()
	_refresh_menu_profile_and_customization()
	if _menu != null:
		_menu.online_set_status("Награда +%s CR получена (офлайн-режим)!" % _fmt_cr(int(spec.get("reward", 0))))


func _push_quest_progress_online() -> void:
	if not _logged_in or _net == null:
		return
	var daily := _daily_today()
	for row_variant in _daily_quests_view():
		var row: Dictionary = row_variant
		var quest_id := String(row.get("id", ""))
		if quest_id.is_empty() or bool(row.get("claimed", false)):
			continue
		var value := _daily_metric(daily, String(row.get("metric", "")))
		if value > float(_quest_progress_pushed.get(quest_id, -1.0)):
			_quest_progress_pushed[quest_id] = value
			_net.push_quest_progress(quest_id, value)


## --- 0.2.61 online account / multiplayer glue ---

func _account_view() -> Dictionary:
	return {
		"logged_in": _logged_in,
		"username": _account_username,
		"role": _account_role,
		"is_admin": _account_role == "admin",
		"server_url": _server_url,
		"mp_connected": _mp != null and _mp.is_connected_to_room(),
		"mp_peers": _mp.peer_count() if _mp != null else 0,
	}


func _net_config_load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(NET_CONFIG_PATH) == OK:
		_server_url = String(cfg.get_value("net", "server_url", ""))
		_auth_token = String(cfg.get_value("net", "token", ""))
		_account_username = String(cfg.get_value("net", "username", ""))


func _net_config_save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("net", "server_url", _server_url)
	cfg.set_value("net", "token", _auth_token)
	cfg.set_value("net", "username", _account_username)
	cfg.save(NET_CONFIG_PATH)


func _setup_net() -> void:
	_net_config_load()
	_net = NitchesNetClient.new()
	add_child(_net)
	_net.configure(_server_url, _auth_token)
	_net.auth_succeeded.connect(_on_auth_succeeded)
	_net.me_loaded.connect(_on_me_loaded)
	_net.quests_loaded.connect(_on_quests_loaded)
	_net.quest_claimed.connect(_on_quest_claimed_online)
	_net.leaderboard_loaded.connect(_on_leaderboard_loaded)
	_net.rooms_loaded.connect(_on_rooms_loaded)
	_net.admin_data_loaded.connect(_on_admin_data_loaded)
	_net.feedback_sent.connect(_on_feedback_sent)
	_net.request_failed.connect(_on_net_request_failed)
	_mp = NitchesMpClient.new()
	add_child(_mp)
	_mp.connection_changed.connect(_on_mp_connection_changed)
	_mp.peers_changed.connect(_on_mp_peers_changed)
	if not _server_url.is_empty() and not _auth_token.is_empty() and not _smoke_mode:
		_net.fetch_me()


func _apply_server_profile(profile: Dictionary) -> void:
	# Server economy wins on login; lifetime records merge by max so
	# offline driving before the first login is never lost.
	if profile.is_empty():
		return
	_profile["credits"] = int(profile.get("credits", _credits()))
	var cars: Array = profile.get("owned_cars", [])
	if not cars.is_empty():
		_profile["owned_cars"] = cars.duplicate()
	var worlds: Array = profile.get("owned_worlds", [])
	if not worlds.is_empty():
		_profile["owned_worlds"] = worlds.duplicate()
	var stats: Dictionary = profile.get("stats", {})
	_profile["distance_m"] = maxf(float(_profile.get("distance_m", 0.0)), float(stats.get("distance_km", 0.0)) * 1000.0)
	_profile["top_speed_kmh"] = maxf(float(_profile.get("top_speed_kmh", 0.0)), float(stats.get("top_speed_kmh", 0.0)))
	_profile["drift_record_deg"] = maxf(float(_profile.get("drift_record_deg", 0.0)), float(stats.get("drift_deg", 0.0)))
	_profile["play_seconds"] = maxf(float(_profile.get("play_seconds", 0.0)), float(stats.get("play_seconds", 0.0)))
	if _selected_car_id not in (_profile.get("owned_cars", []) as Array):
		_selected_car_id = NativeCarCatalog.DEFAULT_CAR_ID
		_profile["selected_car_id"] = _selected_car_id
	_save_profile()
	if _vehicle != null and _vehicle.get_car_id() != _selected_car_id and not _smoke_mode:
		_select_car(_selected_car_id)


func _sync_progress_online() -> void:
	if not _logged_in or _net == null:
		return
	_net.put_progress({
		"credits": _credits(),
		"owned_cars": (_profile.get("owned_cars", []) as Array).duplicate(),
		"owned_worlds": (_profile.get("owned_worlds", []) as Array).duplicate(),
		"stats": {
			"distance_km": float(_profile.get("distance_m", 0.0)) / 1000.0,
			"top_speed_kmh": float(_profile.get("top_speed_kmh", 0.0)),
			"drift_deg": float(_profile.get("drift_record_deg", 0.0)),
			"play_seconds": float(_profile.get("play_seconds", 0.0)),
		},
	})


func _menu_online_status(text: String) -> void:
	if _menu != null:
		_menu.online_set_status(text)


func _on_auth_succeeded(user: Dictionary, profile: Dictionary, token: String, is_new_account: bool, first_player: bool) -> void:
	_auth_token = token
	_account_username = String(user.get("username", _account_username))
	_account_role = String(user.get("role", "player"))
	_logged_in = true
	_profile["name"] = _account_username
	_net_config_save()
	_apply_server_profile(profile)
	_net.fetch_quests()
	_sync_progress_online()
	_refresh_menu_profile_and_customization()
	if is_new_account:
		_menu_online_status("Аккаунт создан. Добро пожаловать в тест Nitches, %s!" % _account_username)
	else:
		_menu_online_status("Вы вошли как %s. Прогресс синхронизируется с сервером." % _account_username)
	if first_player:
		_menu_online_status("Вы — ПЕРВЫЙ игрок этого сервера: вам выдана роль разработчика (admin). Админ-панель — внизу этой вкладки.")


func _on_me_loaded(user: Dictionary, profile: Dictionary) -> void:
	_logged_in = true
	_account_username = String(user.get("username", _account_username))
	_account_role = String(user.get("role", "player"))
	_profile["name"] = _account_username
	_apply_server_profile(profile)
	_net.fetch_quests()
	_sync_progress_online()
	_refresh_menu_profile_and_customization()
	_menu_online_status("С возвращением, %s!" % _account_username)


func _on_quests_loaded(_day: String, quests: Array) -> void:
	_online_quests = quests.duplicate(true)
	_refresh_menu_profile_and_customization()


func _on_quest_claimed_online(quest_id: String, reward: int, credits: int) -> void:
	_profile["credits"] = credits
	for i in _online_quests.size():
		var row: Dictionary = _online_quests[i]
		if String(row.get("id", "")) == quest_id:
			row["claimed"] = true
			_online_quests[i] = row
	_save_profile()
	_net.fetch_quests()
	_refresh_menu_profile_and_customization()
	_menu_online_status("Награда +%s CR получена!" % _fmt_cr(reward))


func _on_leaderboard_loaded(rows: Array, by: String) -> void:
	if _menu != null:
		_menu.show_leaderboard(rows, by)


func _on_rooms_loaded(data: Dictionary) -> void:
	if _menu != null:
		_menu.show_online_rooms(data)


func _on_admin_data_loaded(kind: String, data: Dictionary) -> void:
	if _menu != null:
		_menu.show_admin_data(kind, data)


func _on_feedback_sent() -> void:
	_menu_online_status("Спасибо! Отзыв отправлен разработчику.")


func _on_net_request_failed(tag: String, message: String) -> void:
	var text := message
	match message:
		"username taken":
			text = "Этот ник уже занят — выберите другой."
		"invalid username or password":
			text = "Неверный логин или пароль."
		"unauthorized":
			text = "Сессия истекла — войдите снова."
		"username: 3-16 chars, letters/digits/_":
			text = "Ник: 3–16 символов, латиница, цифры и подчёркивание."
		"password: 6-128 chars":
			text = "Пароль: от 6 символов."
		"quest not completed":
			text = "Задание ещё не выполнено — прогресс синхронизируется каждые 30 секунд."
		"already claimed":
			text = "Награда за это задание уже получена."
		"no connection":
			text = "Нет соединения с сервером. Проверьте адрес сервера и интернет."
		"admin only":
			text = "Доступ только для разработчика (первый игрок сервера)."
	if tag == "me" and message == "unauthorized":
		_logged_in = false
		_auth_token = ""
		_net_config_save()
	_menu_online_status(text)
	_refresh_menu_profile_and_customization()


func _on_mp_connection_changed(_connected: bool, message: String) -> void:
	_menu_online_status(message)
	_refresh_menu_profile_and_customization()


func _on_mp_peers_changed(_count: int) -> void:
	_refresh_menu_profile_and_customization()


func _remember_server_url(server_url: String) -> void:
	_server_url = server_url.strip_edges().trim_suffix("/")
	_net_config_save()
	if _net != null:
		_net.configure(_server_url, _auth_token)


func _on_account_register_requested(server_url: String, username: String, password: String) -> void:
	_remember_server_url(server_url)
	if _net != null:
		_menu_online_status("Создаю аккаунт…")
		_net.register_account(username.strip_edges(), password)


func _on_account_login_requested(server_url: String, username: String, password: String) -> void:
	_remember_server_url(server_url)
	if _net != null:
		_menu_online_status("Вхожу…")
		_net.login_account(username.strip_edges(), password)


func _on_account_logout_requested() -> void:
	if _mp != null:
		_mp.leave_room()
	if _net != null:
		_net.logout_account()
	_logged_in = false
	_auth_token = ""
	_account_role = "player"
	_online_quests = []
	if _net != null:
		_net.set_token("")
	_net_config_save()
	_refresh_menu_profile_and_customization()
	_menu_online_status("Вы вышли. Локальная игра гостем продолжается.")


func _on_feedback_requested(text: String, category: String) -> void:
	if _logged_in and _net != null:
		_net.send_feedback(text, category)
	else:
		_menu_online_status("Отзыв отправляется с аккаунта — войдите или зарегистрируйтесь выше.")


func _on_leaderboard_requested(by: String) -> void:
	if _net != null:
		_net.fetch_leaderboard(by)
		_net.fetch_rooms()


func _on_admin_requested(action: String, payload: Dictionary) -> void:
	if _net == null or not _logged_in:
		return
	match action:
		"stats":
			_net.admin_fetch("stats")
		"users":
			_net.admin_fetch("users")
		"feedback":
			_net.admin_fetch("feedback")
		"grant":
			_net.admin_grant(String(payload.get("username", "")), int(payload.get("amount", 0)))
		"feedback_delete":
			_net.admin_feedback_delete(int(payload.get("id", 0)))


func _on_multiplayer_join_requested() -> void:
	if not _logged_in:
		_menu_online_status("Мультиплеер доступен после входа в аккаунт.")
		return
	if _mp != null:
		_mp.join_room(_server_url, _auth_token, _selected_world_id, _account_username, _selected_car_id)


func _on_multiplayer_leave_requested() -> void:
	if _mp != null:
		_mp.leave_room()


## --- 0.2.62 lightweight menu background + wheel of fortune ---

func _apply_menu_lightweight() -> void:
	# The main menu no longer renders the live 3D world behind its
	# panels: on phones that made the whole menu stutter.  A static
	# gameplay splash image in the menu layer replaces it (see
	# main_menu.gd), the world node is hidden while the menu is up and
	# the car stays visible only inside the garage studio.  World
	# streaming also pauses (see _process).  Smoke/screenshot flows
	# keep the old always-rendered behaviour for CI stability.
	if _smoke_mode or _screenshot_mode:
		return
	if _world != null:
		_world.visible = not _in_menu
	if _vehicle != null:
		_vehicle.visible = (not _in_menu) or _garage_active


func _grant_wheel_spins() -> void:
	# +1 free wheel spin per calendar day and +1 per driver level
	# (level = 1 + km/50, same formula as the profile view), capped
	# so spins stay a daily treat instead of a farming strategy.
	var spins := int(_profile.get("wheel_spins", 0))
	var today := Time.get_date_string_from_system()
	if String(_profile.get("wheel_last_day", "")) != today:
		_profile["wheel_last_day"] = today
		spins = mini(spins + 1, WHEEL_SPIN_CAP)
	var level := 1 + int(float(_profile.get("distance_m", 0.0)) / 50000.0)
	var granted_level := int(_profile.get("wheel_level", 1))
	if level > granted_level:
		spins = mini(spins + (level - granted_level), WHEEL_SPIN_CAP)
		_profile["wheel_level"] = level
	_profile["wheel_spins"] = spins


func _on_wheel_spin_requested() -> void:
	_grant_wheel_spins()
	var spins := int(_profile.get("wheel_spins", 0))
	if spins <= 0:
		if _menu != null:
			_menu.show_wheel_result(-1, {}, 0)
		return
	_profile["wheel_spins"] = spins - 1
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var index := rng.randi_range(0, WHEEL_SEGMENTS.size() - 1)
	var prize: Dictionary = WHEEL_SEGMENTS[index]
	if String(prize.get("kind", "cr")) == "spin":
		_profile["wheel_spins"] = int(_profile["wheel_spins"]) + 1
	else:
		_profile["credits"] = _credits() + int(prize.get("cr", 0))
	_save_profile()
	_sync_progress_online()
	_refresh_menu_profile_and_customization()
	if _menu != null:
		_menu.show_wheel_result(index, prize, int(_profile.get("wheel_spins", 0)))


func _accumulate_profile(delta: float) -> void:
	if _vehicle == null or delta <= 0.0:
		return
	var speed_kmh := _vehicle.get_absolute_speed_kmh()
	_profile["distance_m"] = float(_profile.get("distance_m", 0.0)) + speed_kmh / 3.6 * delta
	_profile["top_speed_kmh"] = maxf(float(_profile.get("top_speed_kmh", 0.0)), speed_kmh)
	_profile["play_seconds"] = float(_profile.get("play_seconds", 0.0)) + delta
	var drift_deg := _vehicle.get_drift_angle_degrees() if _vehicle.is_drifting() else 0.0
	_profile["drift_record_deg"] = maxf(float(_profile.get("drift_record_deg", 0.0)), drift_deg)
	var car_id := _vehicle.get_car_id()
	var car_stats := _car_stats.get(car_id, {"distance_km": 0.0, "top_speed_kmh": 0.0, "drift_deg": 0.0, "play_seconds": 0.0}) as Dictionary
	car_stats["distance_km"] = float(car_stats.get("distance_km", 0.0)) + speed_kmh / 3.6 * delta / 1000.0
	car_stats["top_speed_kmh"] = maxf(float(car_stats.get("top_speed_kmh", 0.0)), speed_kmh)
	car_stats["drift_deg"] = maxf(float(car_stats.get("drift_deg", 0.0)), drift_deg)
	car_stats["play_seconds"] = float(car_stats.get("play_seconds", 0.0)) + delta
	_car_stats[car_id] = car_stats
	_session_distance_m += speed_kmh / 3.6 * delta
	_session_top_speed_kmh = maxf(_session_top_speed_kmh, speed_kmh)
	_session_drift_deg = maxf(_session_drift_deg, drift_deg)
	_session_seconds += delta
	# 0.2.61 daily quest counters (reset at local midnight).
	var daily := _daily_today()
	daily["distance_m"] = float(daily.get("distance_m", 0.0)) + speed_kmh / 3.6 * delta
	daily["top_speed_kmh"] = maxf(float(daily.get("top_speed_kmh", 0.0)), speed_kmh)
	daily["play_seconds"] = float(daily.get("play_seconds", 0.0)) + delta
	if _vehicle.is_drifting():
		daily["drift_seconds"] = float(daily.get("drift_seconds", 0.0)) + delta
		daily["drift_angle_deg"] = maxf(float(daily.get("drift_angle_deg", 0.0)), drift_deg)
	if _vehicle.is_boosting():
		daily["nitro_seconds"] = float(daily.get("nitro_seconds", 0.0)) + delta
	_profile["daily"] = daily
	_credit_distance_bank_m += speed_kmh / 3.6 * delta
	while _credit_distance_bank_m >= 100.0:
		_credit_distance_bank_m -= 100.0
		_profile["credits"] = _credits() + 20
		var daily_after := _profile.get("daily", {}) as Dictionary
		daily_after["credits_from_driving"] = int(daily_after.get("credits_from_driving", 0)) + 20
		_profile["daily"] = daily_after
	_claim_achievement_rewards()
	_profile_save_timer += delta
	if _profile_save_timer >= 5.0:
		_profile_save_timer = 0.0
		_grant_wheel_spins()
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
	# RichTown geometry keeps its streamed detail budget; the extra far
	# plane is reserved for the two distant unshaded skyline rings.
	_camera.far = 2100.0
	_camera.fov = 58.0
	add_child(_camera)
	_camera.make_current()
	_camera.current = true

	# Drive SpeedPost: fullscreen quad lives under the camera exactly as
	# Godot's advanced post-processing pattern prescribes.
	_speed_post = SpeedPostScript.new() as NativeSpeedPost
	_camera.add_child(_speed_post)


func _unhandled_input(event: InputEvent) -> void:
	if _is_bootstrapping or _world_switch_in_progress:
		get_viewport().set_input_as_handled()
		return
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
	if _vehicle != null:
		_vehicle.set_audio_camera_mode(_camera_mode)
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
	if _atmosphere_fx != null:
		_atmosphere_fx.set_time_mode(mode)
		_atmosphere_fx.set_headlights_enabled(mode != "day")
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
	# 0.2.61 multiplayer relay + periodic account sync (runs even
	# while bootstrapping so logins resolve under the load screen).
	if _mp != null and _mp.is_connected_to_room() and _vehicle != null:
		_mp.update_local_state(_vehicle.get_global_transform_interpolated(), _vehicle.get_absolute_speed_kmh())
	if _logged_in and _net != null and not _smoke_mode:
		_net_sync_timer += delta
		if _net_sync_timer >= 30.0:
			_net_sync_timer = 0.0
			_sync_progress_online()
			_net.send_presence(_selected_world_id)
			_push_quest_progress_online()
	if _is_bootstrapping or _world_switch_in_progress:
		return
	_update_adaptive_render_quality(delta)
	if _world != null and _camera != null and _vehicle != null and not _garage_active and (not _in_menu or _smoke_mode or _screenshot_mode):
		# 0.2.30 directional streaming retired load behind the
		# camera; 0.2.37 also retires whole chunks outside the side
		# of the real horizontal view cone (with a wide margin), so
		# pass the live half-FOV derived from the current vertical
		# FOV and viewport aspect.  Everything inside the view keeps
		# full detail.
		var viewport_size := _camera.get_viewport().get_visible_rect().size
		var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
		var horizontal_half_fov := atan(tan(deg_to_rad(_camera.fov * 0.5)) * maxf(aspect, 0.1))
		_world.update_streaming(_camera.global_position, -_camera.global_transform.basis.z, _vehicle.global_position, _vehicle.linear_velocity, delta, horizontal_half_fov)
	if _world != null and _vehicle != null:
		_world.set_skyline_origin(_vehicle.global_position)
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
	var speed_ratio := clampf(speed_kmh / maxf(float(_vehicle.get_spec_sheet().get("top_speed_kmh", 210)), 120.0), 0.0, 1.0)
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
			post_ratio = clampf(speed_kmh / maxf(float(_vehicle.get_spec_sheet().get("top_speed_kmh", 215)), 120.0), 0.0, 1.0)
			if _vehicle.is_boosting():
				post_ratio = clampf(post_ratio * 1.12 + 0.05, 0.0, 1.0)
		_speed_post.set_speed_ratio(post_ratio)

	match _camera_mode:
		CAMERA_HOOD:
			var hood_position := vehicle_transform * (_vehicle.get_car_definition().get("hood_camera_position", Vector3(0.0, 1.12, -0.32)) as Vector3)
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
			var chase_scale := float(_vehicle.get_car_definition().get("camera_distance_scale", 1.0))
			var base_distance := (6.15 + speed_ratio * 2.15) * chase_scale
			var base_height := (2.05 + speed_ratio * 0.38) * sqrt(chase_scale)
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
			var target := vehicle_position + Vector3.UP * clampf(float(_vehicle.get_car_definition().get("height_m", 1.32)) * 0.82, 0.92, 1.22) + forward * (6.0 + speed_ratio * 6.0) * orbit_forward_factor
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
	elif _camera.far < 1600.0 or absf(_camera.far - float(_graphics_quality_state.get("camera_far", 0.0))) > 0.5:
		failures.append("camera far plane does not match the active graphics preset / skyline reach: %.1f m %s" % [_camera.far, str(_graphics_quality_state)])
	if _speed_post == null:
		failures.append("speed post node is missing")
	if _atmosphere_fx == null:
		failures.append("near-car atmosphere node is missing")
	if _hud == null:
		failures.append("HUD node is missing")
	if _world_map == null:
		failures.append("world map node is missing")
	if _loading_screen == null:
		failures.append("0.2.52 branded loading screen node is missing")
	else:
		var loading_state := _loading_screen.get_visual_state()
		if not bool(loading_state.get("custom_loading_screen_0252", false)) or not bool(loading_state.get("real_gameplay_background", false)) or int(loading_state.get("checkpoints", 0)) < 5:
			failures.append("0.2.52 branded loading screen is incomplete: %s" % str(loading_state))
	if not failures.is_empty():
		_finish_smoke(failures)
		return

	if _selected_world_id == "desert":
		_run_desert_smoke_checks(failures)
		# _finish_smoke() quits(0) silently on success; the PASS line
		# CI greps for is printed by the RichTown battery, so the
		# per-world gates must print their own (0.2.55: a passing
		# forest smoke otherwise looked like a silent failure).
		if failures.is_empty():
			print("[native-smoke] PASS world=desert enhancements=%s" % str(_world.get_enhancement_stats()))
		_finish_smoke(failures)
		return
	if _selected_world_id == "greenforest":
		_run_forest_smoke_checks(failures)
		if failures.is_empty():
			print("[native-smoke] PASS world=greenforest enhancements=%s" % str(_world.get_enhancement_stats()))
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
	if int(enhancement_stats.get("skyline_layers", 0)) < 2 or not bool(enhancement_stats.get("skyline_follows_vehicle", false)) or not bool(enhancement_stats.get("skyline_procedural_windows", false)) or not bool(enhancement_stats.get("skyline_panorama_textures_0243", false)) or int(enhancement_stats.get("skyline_panorama_width", 0)) != 4096 or int(enhancement_stats.get("skyline_panorama_height", 0)) != 512:
		failures.append("0.2.43 two-layer textured skyline is incomplete: %s" % str(enhancement_stats))
	if not bool(enhancement_stats.get("near_field_lod_0243", false)) or String(enhancement_stats.get("range_fade_mode", "")) != "dithered_self" or float(enhancement_stats.get("tree_detail_end_m", 9999.0)) > 110.0 or float(enhancement_stats.get("palm_detail_end_m", 9999.0)) > 140.0 or float(enhancement_stats.get("shrub_detail_end_m", 9999.0)) > 100.0:
		failures.append("0.2.43 near-field HLOD budget is incomplete: %s" % str(enhancement_stats))
	var atmosphere_state := _atmosphere_fx.get_state() if _atmosphere_fx != null else {}
	if not bool(atmosphere_state.get("ready", false)) or not bool(atmosphere_state.get("light_shafts", false)) or not bool(atmosphere_state.get("headlight_bokeh", false)) or not bool(atmosphere_state.get("active", false)) or int(atmosphere_state.get("leaves", 0)) < 16 or int(atmosphere_state.get("petals", 0)) < 8 or float(atmosphere_state.get("foliage_density", 0.0)) <= 0.0:
		failures.append("0.2.43 nearby atmosphere/foliage shaft gate is incomplete: %s" % str(atmosphere_state))
	var vehicle_effect_state := _vehicle.get_effect_state()
	if int(vehicle_effect_state.get("tire_smoke_emitters", 0)) < 2 or int(vehicle_effect_state.get("tire_spark_emitters", 0)) < 2 or not bool(vehicle_effect_state.get("engine_audio", false)) or not bool(vehicle_effect_state.get("speed_wind_audio", false)):
		failures.append("tire smoke/sparks or recorded engine/wind audio is incomplete: %s" % str(vehicle_effect_state))
	if not bool(_graphics_quality_state.get("graphics_quality_0244", false)) or String(_graphics_quality_state.get("preset", "")) != String(_settings.get("graphics_quality", "")) or not bool(enhancement_stats.get("foliage_spatial_grid_0244", false)) or int(enhancement_stats.get("foliage_grid_cells", 0)) < 10 or int(enhancement_stats.get("foliage_points_total", 0)) < 50 or int(enhancement_stats.get("quality_ranged_instances", 0)) < 20 or absf(float(enhancement_stats.get("quality_detail_scale_0244", 0.0)) - float(_graphics_quality_state.get("detail_scale", -1.0))) > 0.01 or absf(float(enhancement_stats.get("quality_shadow_distance_0244", 0.0)) - float(_graphics_quality_state.get("shadow_distance", -1.0))) > 0.5 or not bool(atmosphere_state.get("graphics_quality_0244", false)) or float(atmosphere_state.get("quality_particle_scale", 0.0)) <= 0.0:
		failures.append("0.2.44 user graphics quality / foliage spatial grid is incomplete: quality=%s world=%s atmosphere=%s" % [str(_graphics_quality_state), str(enhancement_stats), str(atmosphere_state)])
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
	if not bool(enhancement_stats.get("road_infrastructure_repair_0236", false)) or not bool(enhancement_stats.get("real_junction_arms_0236", false)) or not bool(enhancement_stats.get("traffic_signals_on_real_arms_0236", false)) or not bool(enhancement_stats.get("continuous_arterial_curbs_0236", false)) or not bool(enhancement_stats.get("rounded_curb_edge_alignment_0236", false)) or not bool(enhancement_stats.get("bike_lane_junction_breaks_0236", false)) or not bool(enhancement_stats.get("bus_shelter_footprints_clear_0236", false)) or not bool(enhancement_stats.get("roadside_footprints_clear_0236", false)) or int(enhancement_stats.get("rejected_fake_junction_pads_0236", 0)) < 1 or int(enhancement_stats.get("real_crosswalk_groups_0236", 0)) < 50 or int(enhancement_stats.get("rejected_fake_crosswalks_0236", 0)) < 10 or int(enhancement_stats.get("rejected_fake_signal_approaches_0236", 0)) < 10 or int(enhancement_stats.get("road_junction_subsegments_0236", 0)) < 100 or int(enhancement_stats.get("rejected_road_palms_0236", 0)) < 1:
		failures.append("0.2.36 real-arm road infrastructure/footprint repair pass is incomplete: %s" % str(enhancement_stats))
	if not bool(enhancement_stats.get("view_sector_streaming_0237", false)) or int(enhancement_stats.get("flat_shadow_casters_disabled_0237", 0)) < 500 or not bool(enhancement_stats.get("sail_island_expanded_0237", false)) or not bool(enhancement_stats.get("sail_island_loop_0237", false)) or not bool(enhancement_stats.get("sail_island_resort_0237", false)) or not bool(enhancement_stats.get("sail_island_infill_excluded_0237", false)) or float(enhancement_stats.get("sail_island_land_area_m2_0237", 0.0)) < 30000.0 or int(enhancement_stats.get("sail_resort_villas_0237", 0)) < 3 or int(enhancement_stats.get("sail_resort_pools_0237", 0)) < 3 or int(enhancement_stats.get("sail_island_palms_0237", 0)) < 12 or int(enhancement_stats.get("sail_island_promenade_segments_0237", 0)) < 48 or int(enhancement_stats.get("sail_island_lamps_0237", 0)) < 8 or not bool(enhancement_stats.get("canonical_building_road_clearance_0237", false)) or int(enhancement_stats.get("canonical_buildings_relocated_0237", 0)) < 3 or float(enhancement_stats.get("canonical_building_min_clearance_0237", 0.0)) < 1.6 or not bool(enhancement_stats.get("canonical_pool_road_clearance_0237", false)) or int(enhancement_stats.get("canonical_pools_relocated_0237", 0)) < 1 or float(enhancement_stats.get("canonical_pool_min_clearance_0237", 0.0)) < 1.2 or not bool(enhancement_stats.get("bridge_roadside_props_removed_0237", false)) or int(enhancement_stats.get("readable_road_signs_0237", 0)) < 20 or not bool(enhancement_stats.get("road_wear_scale_0237", false)):
		failures.append("0.2.37 view-sector streaming / flat-shadow diet / Sail Island resort / canonical footprint repair pass is incomplete: %s" % str(enhancement_stats))
	if not bool(enhancement_stats.get("sail_loop_road_repair_0238", false)) or not bool(enhancement_stats.get("sail_loop_closed_0238", false)) or not bool(enhancement_stats.get("sail_loop_entry_pad_0238", false)) or not bool(enhancement_stats.get("sail_loop_clean_markings_0238", false)) or int(enhancement_stats.get("sail_loop_center_dashes_0238", 0)) < 40 or not bool(enhancement_stats.get("sail_loop_pristine_asphalt_0238", false)) or float(enhancement_stats.get("sail_resort_min_road_clearance_0238", 0.0)) < 0.9 or int(enhancement_stats.get("sail_resort_rejected_road_overlaps_0238", 1)) != 0 or int(enhancement_stats.get("sail_island_paving_0237", 0)) < 4 or int(enhancement_stats.get("sail_island_hedges_0238", 0)) < 14 or int(enhancement_stats.get("sail_pools_final_0238", 0)) < 3 or float(enhancement_stats.get("sail_pool_min_road_clearance_0238", 0.0)) < 1.2 or not bool(enhancement_stats.get("canonical_pool_rim_clearance_0238", false)) or not bool(enhancement_stats.get("canonical_pool_self_excluded_0238", false)) or not bool(enhancement_stats.get("sail_loop_generic_props_removed_0238", false)) or int(enhancement_stats.get("sail_loop_segments_without_props_0238", 0)) < 56:
		failures.append("0.2.38 Sail Island loop road repair (entry pad/clean markings/pristine asphalt/resort footprints off the carriageway) is incomplete: %s" % str(enhancement_stats))
	if not bool(enhancement_stats.get("sail_cottage_estates_0239", false)) or int(enhancement_stats.get("sail_cottage_estates_placed_0239", 0)) != 3 or int(enhancement_stats.get("sail_cottage_models_0239", 0)) != 3 or not bool(enhancement_stats.get("sail_cottage_fixed_scale_0239", false)) or not bool(enhancement_stats.get("sail_cottage_exterior_only_0239", false)) or not bool(enhancement_stats.get("sail_cottage_pbr_roughness_0239", false)) or int(enhancement_stats.get("sail_cottage_roughness_materials_0239", 0)) < 7 or not bool(enhancement_stats.get("sail_cottage_material_pass_0239", false)) or not bool(enhancement_stats.get("sail_cottage_multi_box_colliders_0239", false)) or int(enhancement_stats.get("sail_cottage_colliders_0239", 0)) < 39 or int(enhancement_stats.get("sail_cottage_podiums_0239", 0)) < 9 or int(enhancement_stats.get("sail_cottage_model_parts_0239", 0)) < 45 or int(enhancement_stats.get("sail_cottage_dune_triangles_0239", 0)) < 12000 or int(enhancement_stats.get("sail_cottage_courtyard_triangles_0239", 0)) < 14000 or int(enhancement_stats.get("sail_cottage_palm_triangles_0239", 0)) < 11000 or int(enhancement_stats.get("sail_cottage_garden_palms_0239", 0)) != 3 or not bool(enhancement_stats.get("sail_open_lookout_0239", false)) or not bool(enhancement_stats.get("sail_cottage_resort_fit_0239", false)):
		failures.append("0.2.39 Sail Island cottage estates No.10-12 (three fixed-scale 36x27 m estates, PBR roughness maps, podiums, multi-box colliders, garden palms, open SW lookout) are incomplete: %s" % str(enhancement_stats))
	var sail_loop_surface := _world.get_surface_at(Vector3(1188.0, 3.0, 34.0))
	var sail_lawn_surface := _world.get_surface_at(Vector3(1185.0, 3.0, 8.0))
	if String(sail_loop_surface.get("kind", "")) != "asphalt" or String(sail_lawn_surface.get("kind", "")) != "grass":
		failures.append("0.2.37 Sail Island loop/lawn surfaces are not drivable/landscaped as designed: loop=%s lawn=%s" % [str(sail_loop_surface), str(sail_lawn_surface)])
	var sail_entry_surface := _world.get_surface_at(Vector3(1140.0, 3.0, 80.0))
	var sail_west_branch_surface := _world.get_surface_at(Vector3(1144.8, 3.0, 61.0))
	var sail_east_branch_surface := _world.get_surface_at(Vector3(1236.0, 3.0, 80.0))
	if String(sail_entry_surface.get("kind", "")) != "asphalt" or String(sail_west_branch_surface.get("kind", "")) != "asphalt" or String(sail_east_branch_surface.get("kind", "")) != "asphalt":
		failures.append("0.2.38 Sail Island entry/west/east loop branches are not drivable asphalt: entry=%s west=%s east=%s" % [str(sail_entry_surface), str(sail_west_branch_surface), str(sail_east_branch_surface)])
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
	# 0.2.41 regression: exercise the real automatic-gear helper on a
	# detached vehicle for every catalog car.  In particular the 560 SEL
	# must leave first soon after 64.7 km/h, then reach third/fourth.
	var drivetrain_probe := VehicleScript.new() as NativeVehicle
	var automatic_gears_ok := drivetrain_probe != null
	var automatic_gear_report := {}
	if drivetrain_probe != null:
		for probe_id in NativeCarCatalog.car_ids():
			drivetrain_probe.configure_car(probe_id)
			var probe_car := NativeCarCatalog.get_car(probe_id)
			var ratios: Array = probe_car.get("gear_ratios", [])
			var last_gear := maxi(ratios.size() - 1, 0)
			var gears_at_speed := {}
			for speed_kmh in [40.0, 70.0, 120.0, 180.0, 240.0]:
				gears_at_speed[str(int(speed_kmh))] = drivetrain_probe.get_automatic_gear_for_speed(speed_kmh / 3.6, 0)
			automatic_gear_report[probe_id] = gears_at_speed
			var gears_ok := int(gears_at_speed.get("120", 0)) >= 2 and int(gears_at_speed.get("180", 0)) >= 2 and int(gears_at_speed.get("240", 0)) >= mini(3, last_gear)
			if probe_id == "mercedes_560_sel":
				gears_ok = gears_ok and int(gears_at_speed.get("70", 0)) >= 1 and int(gears_at_speed.get("180", 0)) >= 3
			if not gears_ok:
				automatic_gears_ok = false
		drivetrain_probe.free()
	if not automatic_gears_ok or not bool(drive_base_state.get("automatic_shift_0241", false)) or not bool(drive_base_state.get("paint_finish_0241", false)) or int(drive_base_state.get("paint_shader_surfaces", 0)) < 1 or float(drive_base_state.get("paint_metallic", 0.0)) < 0.6 or float(drive_base_state.get("paint_clearcoat_roughness", 1.0)) > 0.08:
		failures.append("0.2.41 coupled-RPM automatic shifts / glossy paint finish are incomplete: drive=%s gears=%s" % [str(drive_base_state), str(automatic_gear_report)])
	var smoothing_state := _vehicle.get_smoothing_state()
	if not bool(smoothing_state.get("pedal_actuator_smoothing", false)) or not bool(smoothing_state.get("drive_force_smoothing", false)) or not bool(smoothing_state.get("filtered_suspension", false)) or not bool(smoothing_state.get("anti_roll_requires_both_wheels", false)):
		failures.append("0.2.5 acceleration/suspension smoothing is incomplete: %s" % str(smoothing_state))
	var vehicle_audio_state: Dictionary = smoothing_state.get("vehicle_audio", {})
	if not bool(smoothing_state.get("ignition_0235", false)) or int(smoothing_state.get("engine_state", -1)) != NativeVehicle.ENGINE_OFF or bool(smoothing_state.get("engine_running", true)) or _vehicle.get_gear_label() != "N" or _vehicle.get_rpm_ratio() > 0.001 or not bool(vehicle_audio_state.get("recorded_audio_0235", false)) or not bool(vehicle_audio_state.get("recorded_gt500_bank", false)) or int(vehicle_audio_state.get("on_loop_count", 0)) != 18 or int(vehicle_audio_state.get("off_loop_count", 0)) != 18 or not bool(vehicle_audio_state.get("streams_ready", false)) or int(vehicle_audio_state.get("players_created", 0)) < 7 or not bool(vehicle_audio_state.get("bus_ready", false)):
		failures.append("0.2.35 ignition-off spawn / recorded Shelby GT500 audio pass is incomplete: smoothing=%s audio=%s gear=%s rpm_ratio=%.3f" % [str(smoothing_state), str(vehicle_audio_state), _vehicle.get_gear_label(), _vehicle.get_rpm_ratio()])
	var audio_anchor_rpms: Array = vehicle_audio_state.get("anchor_rpms", [])
	if not bool(vehicle_audio_state.get("audio_realism_0242", false)) or int(vehicle_audio_state.get("pops_count", 0)) != 10 or not bool(vehicle_audio_state.get("foley_ready", false)) or not bool(vehicle_audio_state.get("engine_lowpass_ready", false)) or not bool(vehicle_audio_state.get("tire_panner_ready", false)) or int(vehicle_audio_state.get("players_created", 0)) < 14 or audio_anchor_rpms.size() < 18 or int(audio_anchor_rpms[audio_anchor_rpms.size() - 1]) != 5600 or float(vehicle_audio_state.get("pitch_max", 9.0)) > 1.31:
		failures.append("0.2.42 recorded-audio realism pass is incomplete (dense PSOLA ladder, crackle pops, foley buses): %s" % str(vehicle_audio_state))
	if not bool(vehicle_audio_state.get("foliage_rustle_ready_0244", false)):
		failures.append("0.2.44 foliage-rustle ambience is not ready: %s" % str(vehicle_audio_state))
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
	if not bool(hud_state.get("hud_0233", false)) or not bool(hud_state.get("safe_area_3pct_4pct", false)) or not hud_rects_safe or not hud_rects_visible or not bool(minimap_state.get("circular_heading_up_0233", false)) or not bool(minimap_state.get("static_map_cache_0237", false)) or not bool(minimap_state.get("static_cache_created", false)) or int(minimap_state.get("roads", 0)) < 35 or int(minimap_state.get("parks", 0)) < 3 or int(minimap_state.get("pois", 0)) < 20 or not bool(minimap_state.get("has_destination", false)) or not bool(gauge_state.get("circular_gauge_0233", false)) or String(gauge_state.get("speed_text", "")) != "0" or not bool(gas_pedal_state.get("analog_pedal_0233", false)) or not bool(brake_pedal_state.get("analog_pedal_0233", false)) or gas_rect.size.y < viewport_size.y * 0.28 or brake_rect.size.y < viewport_size.y * 0.28 or absf(gas_rect.position.x - brake_rect.end.x - 8.0) > 1.5 or not bool(nitro_button_state.get("round_action_0233", false)) or not bool(drift_button_state.get("round_action_0233", false)) or nitro_rect.position.x - drift_rect.end.x < 15.0 or bool(hud_state.get("performance_visible", true)) != bool(hud_state.get("developer_mode", false)):
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
	if not bool(menu_state.get("created", false)) or int(menu_state.get("panels", 0)) < 6 or int(menu_state.get("tabs", 0)) < 6 or not bool(menu_state.get("specs_bound", false)) or not bool(menu_state.get("profile_bound", false)) or not bool(menu_state.get("world_map_button", false)) or not bool(menu_state.get("settings_panel_0233", false)) or not bool(menu_state.get("graphics_quality_0244", false)) or int(menu_state.get("control_buttons", 0)) < 3 or not bool(menu_state.get("settings_bound", false)) or not bool(menu_state.get("version_button_created", false)) or bool(menu_state.get("visible_now", true)) or int(spec_sheet.get("power_hp", 0)) != 365 or int(spec_sheet.get("torque_nm", 0)) != 569 or int(spec_sheet.get("top_speed_kmh", 0)) != 207 or int(spec_sheet.get("gears", 0)) != 4:
		failures.append("0.2.34 main menu/settings / Shelby GT500 spec pass is incomplete: menu=%s spec=%s" % [str(menu_state), str(spec_sheet)])

	var frontend_state := _get_frontend_smoke_state()
	var route_state: Dictionary = frontend_state.get("route_guide", {})
	var customization_state := _vehicle.get_customization_state()
	var tuning_preview := _vehicle.get_tuning_preview(2)
	if not bool(frontend_state.get("frontend_0234", false)) or not bool(frontend_state.get("garage_stage_created", false)) or int(frontend_state.get("garage_stage_children", 0)) < 12 or not bool(menu_state.get("clean_menu_0234", false)) or not bool(menu_state.get("store_panel_0236", false)) or int(menu_state.get("store_items", 0)) < 4 or not bool(menu_state.get("labeled_tabs_0236", false)) or not bool(menu_state.get("top_xp_bar_0236", false)) or not bool(menu_state.get("clickable_home_cards_0236", false)) or not bool(menu_state.get("wheel_previews_0236", false)) or not bool(menu_state.get("profile_single_scroll_0236", false)) or int(menu_state.get("achievement_cards_0236", 0)) < 6 or not bool(menu_state.get("locked_world_conditions_0236", false)) or not bool(menu_state.get("hover_sound_0236", false)) or not bool(menu_state.get("gameplay_card_textures_0236", false)) or not bool(frontend_state.get("studio_reflection_probe_0236", false)) or float(frontend_state.get("garage_distance_0236", 0.0)) < 10.0 or not bool(menu_state.get("backdrop_blur_0234", false)) or not bool(menu_state.get("customization_bound", false)) or not bool(route_state.get("route_guide_0234", false)) or int(route_state.get("graph_nodes", 0)) < 300 or int(route_state.get("graph_edges", 0)) < 300 or not bool(route_state.get("has_route", false)) or int(route_state.get("path_points", 0)) < 8 or float(route_state.get("path_distance_m", 0.0)) < 350.0 or int(minimap_state.get("route_points", 0)) < 8 or not bool(minimap_state.get("road_route_0234", false)) or not bool(customization_state.get("customization_0234", false)) or int(tuning_preview.get("power_hp", 0)) != 423 or int(tuning_preview.get("torque_nm", 0)) != 660 or int(tuning_preview.get("performance_index", 0)) != 701 or String(tuning_preview.get("class_label", "")) != "S1":
		failures.append("0.2.36 labelled menu / real-content store / reflective garage studio / Shelby customization / AStar road-route pass is incomplete: frontend=%s route=%s custom=%s tuning=%s menu=%s" % [str(frontend_state), str(route_state), str(customization_state), str(tuning_preview), str(menu_state)])

	var catalog_by_id := {}
	for car_variant in NativeCarCatalog.get_cars():
		var car: Dictionary = car_variant
		catalog_by_id[String(car.get("id", ""))] = car
	var audi_spec := catalog_by_id.get("audi_r8_v10_plus", {}) as Dictionary
	var camaro_spec := catalog_by_id.get("chevrolet_camaro_ss", {}) as Dictionary
	var mercedes_spec := catalog_by_id.get("mercedes_560_sel", {}) as Dictionary
	if not bool(frontend_state.get("multi_car_0240", false)) or int(frontend_state.get("catalog_cars", 0)) != 4 or int(frontend_state.get("catalog_view_cars", 0)) != 4 or int(frontend_state.get("car_customization_slots", 0)) != 4 or int(frontend_state.get("car_stat_slots", 0)) != 4 or int(audi_spec.get("power_hp", 0)) != 610 or int(audi_spec.get("torque_nm", 0)) != 560 or int(audi_spec.get("top_speed_kmh", 0)) != 330 or int(camaro_spec.get("power_hp", 0)) != 455 or int(camaro_spec.get("torque_nm", 0)) != 617 or int(camaro_spec.get("top_speed_kmh", 0)) != 290 or int(mercedes_spec.get("power_hp", 0)) != 300 or int(mercedes_spec.get("torque_nm", 0)) != 455 or int(mercedes_spec.get("top_speed_kmh", 0)) != 250 or not bool(menu_state.get("multi_car_0240", false)) or int(menu_state.get("catalog_cars", 0)) != 4 or int(menu_state.get("store_cars", 0)) != 4 or not bool(steering_wheel_state.get("photo_steering_wheel_0240", false)) or not bool(steering_wheel_state.get("replaceable_per_car_0240", false)) or (steering_wheel_state.get("wheel_texture_size", Vector2.ZERO) as Vector2).x < 512.0 or not bool(vehicle_audio_state.get("multi_car_audio_0240", false)) or String(vehicle_audio_state.get("car_id", "")) != _selected_car_id:
		failures.append("0.2.40 four-car catalogue / supplied models / photo steering wheel / per-car audio pass is incomplete: frontend=%s menu=%s wheel=%s audio=%s audi=%s camaro=%s mercedes=%s" % [str(frontend_state), str(menu_state), str(steering_wheel_state), str(vehicle_audio_state), str(audi_spec), str(camaro_spec), str(mercedes_spec)])

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
		{
			"name": "08a_car_audi_r8", "time": "day", "hud": true, "vehicle": "spawn",
			"car_id": "audi_r8_v10_plus", "gameplay_camera": true, "marketing": true, "frames": 6,
		},
		{
			"name": "08b_car_camaro_ss", "time": "day", "hud": true, "vehicle": "spawn",
			"car_id": "chevrolet_camaro_ss", "gameplay_camera": true, "marketing": true, "frames": 6,
		},
		{
			"name": "08c_car_mercedes_560_sel", "time": "day", "hud": true, "vehicle": "spawn",
			"car_id": "mercedes_560_sel", "gameplay_camera": true, "marketing": true, "frames": 6,
		},
		{
			"name": "08d_car_shelby_gt500", "time": "day", "hud": true, "vehicle": "spawn",
			"car_id": "shelby_gt500", "gameplay_camera": true, "marketing": true, "frames": 6,
		},
		{
			"name": "15_corniche_t_junction", "time": "day", "vehicle": "hide",
			"camera": Vector3(895.0, 18.0, -335.0), "target": Vector3(930.0, 1.0, -300.0),
		},
		{
			"name": "16_corniche_l_corner", "time": "day", "vehicle": "hide",
			"camera": Vector3(895.0, 18.0, -395.0), "target": Vector3(930.0, 1.0, -430.0),
		},
		{
			"name": "17_boulevard_full_junction", "time": "day", "vehicle": "hide",
			"camera": Vector3(725.0, 18.0, -145.0), "target": Vector3(760.0, 1.0, -110.0),
		},
		{
			"name": "18_west_t_junction", "time": "day", "vehicle": "hide",
			"camera": Vector3(525.0, 16.0, -335.0), "target": Vector3(560.0, 1.0, -300.0),
		},
		{
			"name": "19_sail_island_resort", "time": "day", "vehicle": "hide",
			"camera": Vector3(1015.0, 42.0, 205.0), "target": Vector3(1185.0, 24.0, 80.0),
		},
		{
			"name": "20_sail_island_arrival", "time": "day", "vehicle": "road",
			"vehicle_at": Vector3(1105.0, 0.0, 80.0),
			"camera": Vector3(1086.0, 4.2, 104.0), "target": Vector3(1182.0, 30.0, 80.0),
		},
		{
			"name": "21_sail_loop_entry", "time": "day", "vehicle": "hide",
			"camera": Vector3(1112.0, 10.0, 112.0), "target": Vector3(1148.0, 1.0, 78.0),
		},
		{
			"name": "22_sail_loop_east", "time": "day", "vehicle": "hide",
			"camera": Vector3(1204.0, 8.0, 122.0), "target": Vector3(1230.0, 1.0, 84.0),
		},
		{
			"name": "23_sail_cottage_dune", "time": "day", "vehicle": "hide",
			"camera": Vector3(1165.0, 6.5, 50.0), "target": Vector3(1157.0, 3.5, 20.0),
		},
		{
			"name": "24_sail_cottage_courtyard", "time": "sunset", "vehicle": "hide",
			"camera": Vector3(1209.0, 7.0, 50.0), "target": Vector3(1218.0, 4.5, 18.0),
		},
		{
			"name": "25_sail_cottage_palm", "time": "day", "vehicle": "hide",
			"camera": Vector3(1197.0, 6.5, 116.0), "target": Vector3(1218.0, 3.5, 142.0),
		},
		{
			"name": "26_sail_cottages_aerial", "time": "day", "vehicle": "hide",
			"camera": Vector3(1188.0, 150.0, 185.0), "target": Vector3(1188.0, 2.0, 75.0),
		},
		{"name": "09_menu_home", "time": "day", "vehicle": "spawn", "menu_panel": NativeMainMenu.PANEL_HOME, "frames": 5},
		{"name": "10_menu_garage", "time": "day", "vehicle": "spawn", "menu_panel": NativeMainMenu.PANEL_GARAGE, "frames": 5},
		{"name": "11_menu_store", "time": "day", "vehicle": "spawn", "menu_panel": NativeMainMenu.PANEL_STORE, "frames": 5},
		{"name": "12_menu_profile", "time": "day", "vehicle": "spawn", "menu_panel": NativeMainMenu.PANEL_PROFILE, "frames": 5},
		{"name": "13_menu_worlds", "time": "day", "vehicle": "spawn", "menu_panel": NativeMainMenu.PANEL_WORLDS, "frames": 5},
		{"name": "14_menu_settings", "time": "day", "vehicle": "spawn", "menu_panel": NativeMainMenu.PANEL_SETTINGS, "frames": 5},
	]
	if _selected_world_id == "desert":
		shots = _desert_screenshot_shots()
	elif _selected_world_id == "greenforest":
		shots = _forest_screenshot_shots()

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
	if shot.has("car_id"):
		var wanted_car := NativeCarCatalog.normalize_id(String(shot.get("car_id", "")))
		_current_car_marketing_shot += 1
		if _vehicle.get_car_id() != wanted_car:
			_select_car(wanted_car)
			var switch_frames := 0
			while _vehicle.is_car_switch_pending() and switch_frames < 30:
				await RenderingServer.frame_post_draw
				switch_frames += 1
			if _vehicle.get_car_id() != wanted_car:
				push_error("[native-screenshots] FAIL: car switch to %s did not finish" % wanted_car)
				return false
	var is_menu_shot := shot.has("menu_panel")
	if _hud != null:
		_hud.visible = bool(shot.get("hud", false)) and not is_menu_shot

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

	if is_menu_shot:
		_screenshot_free_camera = false
		_in_menu = true
		_vehicle.visible = true
		_vehicle.freeze = true
		_vehicle.set_physics_process(false)
		_vehicle.set_audio_suspended(true)
		_snap_camera = true
		if _menu != null:
			_menu.refresh_profile(_profile_view())
			_menu.bind_customization(_customization_view())
			_menu.show_panel_index(int(shot.get("menu_panel", NativeMainMenu.PANEL_HOME)))
	elif bool(shot.get("gameplay_camera", false)):
		_screenshot_free_camera = false
		_camera_mode = CAMERA_CHASE
		_snap_camera = true
	else:
		if _in_menu:
			_set_garage_active(false)
			if _menu != null:
				_menu.hide_menu()
			_in_menu = false
			_vehicle.freeze = false
			_vehicle.set_physics_process(true)
			_vehicle.set_audio_suspended(false)
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


## 0.2.47: live world switch (menu -> Worlds).  Builds the new world
## first, rebinds every system that cached a world reference and only
## then frees the old one, so the car never points at a dead world.
func switch_world(world_id: String) -> void:
	if world_id != "richtown" and world_id != "desert" and world_id != "greenforest":
		return
	if not _is_world_owned(world_id) and not _smoke_mode and not _screenshot_mode:
		return
	if _mp != null:
		_mp.leave_room()
	if world_id == _selected_world_id and _world != null:
		return
	if _is_bootstrapping or _world_switch_in_progress or not _bootstrap_completed:
		return
	_world_switch_in_progress = true
	call_deferred("_switch_world_async", world_id)


func _switch_world_async(world_id: String) -> void:
	_selected_world_id = world_id
	_settings["selected_world"] = world_id
	_save_settings()
	_show_loading_screen("Переезжаем в новый мир")
	_set_loading_progress(0.03, "Сохраняем настройки")
	if _vehicle != null:
		_vehicle.freeze = true
		_vehicle.set_physics_process(false)
		_vehicle.set_audio_suspended(true)
	if _atmosphere_fx != null:
		_atmosphere_fx.set_active(false)
	if _hud != null:
		_hud.visible = false
	if _world_map != null:
		_world_map.hide_map()
	_map_open = false
	await get_tree().process_frame
	await get_tree().process_frame
	var old_world := _world
	if old_world != null:
		old_world.process_mode = Node.PROCESS_MODE_DISABLED
	var new_world := WorldBuilderScript.new() as NativeWorldBuilder
	new_world.name = "NativeWorld"
	new_world.world_id = world_id
	new_world.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(new_world)
	await _build_world_with_loading(new_world, 0.07, 0.84)
	new_world.process_mode = Node.PROCESS_MODE_INHERIT
	_set_loading_progress(0.90, "Подключаем автомобиль и интерфейс")
	await get_tree().process_frame
	_world = new_world
	_vehicle.set_world(_world)
	_vehicle.reset_to_transform(_world.spawn_transform)
	_vehicle.global_transform = _world.spawn_transform
	_atmosphere_fx.configure(_vehicle, _camera, _world)
	_route_guide.bind(_world, _vehicle)
	_hud.bind(_world, _vehicle)
	_world_map.bind(_world, _vehicle)
	_hud.set_minimap_points(_world_map.get_minimap_points())
	_on_world_map_destination_changed(_world_map.get_route_destination())
	_apply_graphics_quality()
	_apply_time_mode()
	if _menu != null:
		_menu.set_current_world(world_id)
	if old_world != null:
		old_world.queue_free()
	_update_camera(0.0, true)
	if _in_menu:
		if _hud != null:
			_hud.visible = false
	else:
		if _atmosphere_fx != null:
			_atmosphere_fx.set_active(true)
		if _hud != null:
			_hud.visible = true
		if _vehicle != null:
			_vehicle.freeze = false
			_vehicle.set_physics_process(true)
			_vehicle.set_audio_suspended(false)
	_set_loading_progress(1.0, "Мир готов")
	_world_switch_in_progress = false
	await _finish_loading_screen()


## 0.2.47 desert smoke gate: the RichTown assert battery below is
## data-specific (boulevard/parks/Sail Island), so the desert build
## gets its own equally strict checklist against the spec numbers.
func _run_desert_smoke_checks(failures: Array[String]) -> void:
	if not _world.has_world_data() or _world.get_world_data().is_empty():
		failures.append("desert world data is empty: %s" % _world.build_error)
		return
	var world_data := _world.get_world_data()
	var terrain: Dictionary = world_data.get("terrain", {})
	if (terrain.get("heights", []) as Array).size() != 251001:
		failures.append("desert terrain heights are incomplete")
	if (world_data.get("roads", []) as Array).size() < 40:
		failures.append("desert road network is incomplete")
	var data_stats: Dictionary = world_data.get("stats", {})
	if float(data_stats.get("roadLengthKm", 0.0)) < 55.0:
		failures.append("desert road length is below the 55 km spec floor: %s" % str(data_stats))
	var es := _world.get_enhancement_stats()
	if not bool(es.get("desert_world_0247", false)):
		failures.append("desert build flag is missing: %s" % str(es))
	if int(es.get("desert_scatter", 0)) < 36000:
		failures.append("desert scatter is below budget: %s" % str(es))
	if int(es.get("desert_structures", 0)) < 700:
		failures.append("desert structures are incomplete: %s" % str(es))
	if int(es.get("desert_terrain_chunks", 0)) < 100:
		failures.append("desert terrain chunks are missing: %s" % str(es))
	if int(es.get("reflection_probes", 0)) < 6:
		failures.append("desert reflection probes are incomplete: %s" % str(es))
	if int(es.get("road_markings", 0)) < 1000:
		failures.append("desert road markings are incomplete: %s" % str(es))
	if int(es.get("desert_bridges", 0)) != 3 or not bool(es.get("desert_tunnel", false)) or not bool(es.get("desert_lake", false)):
		failures.append("desert bridges/tunnel/lake are incomplete: %s" % str(es))
	if int(es.get("skyline_layers", 0)) < 1 or not bool(es.get("skyline_follow", false)):
		failures.append("desert far-mesa skyline is incomplete: %s" % str(es))
	if int(es.get("desert_road_deck_colliders", 0)) < 3000:
		failures.append("desert physical road deck is incomplete: %s" % str(es))
	if int(es.get("desert_scatter_variants", 0)) < 12 or not bool(es.get("desert_detail_0250", false)):
		failures.append("desert 0.2.50 cactus/rock detail is incomplete: %s" % str(es))
	if int(es.get("desert_fences_0251", 0)) < 85:
		failures.append("desert 0.2.51 fences are incomplete: %s" % str(es))
	if not bool(es.get("desert_screenshot_audit_0253", false)) or not bool(es.get("desert_rock_triplanar_0253", false)) or not bool(es.get("desert_race_rings_subtle_0253", false)) or not bool(es.get("desert_lake_calm_0253", false)) or not es.has("desert_pipe_road_gaps_0253"):
		failures.append("desert 0.2.53 screenshot-audit repair is incomplete: %s" % str(es))
	var dz_smoke: Dictionary = world_data.get("desert", {})
	var lake_smoke: Dictionary = dz_smoke.get("lake", {})
	var lake_y_smoke := float(lake_smoke.get("y", 26.2))
	var oasis_deck_ok := false
	for road_variant2 in world_data.get("roads", []):
		var road2: Dictionary = road_variant2
		if String(road2.get("id", "")) != "dz-oasis_road":
			continue
		var min_deck_y := 1e9
		for sample_variant2 in road2.get("samples", []):
			var sample2: Array = sample_variant2
			var d_lake := Vector2(float(sample2[0]) - float(lake_smoke.get("x", 3350.0)), float(sample2[2]) - float(lake_smoke.get("z", 3500.0))).length()
			if d_lake < 95.0:
				min_deck_y = minf(min_deck_y, float(sample2[1]))
		oasis_deck_ok = min_deck_y > lake_y_smoke + 0.1
	if not oasis_deck_ok:
		failures.append("oasis road deck is not above lake level (0.2.53)")
	var salt_point := Vector3(2000.0, _world.height_at(2000.0, 1900.0) + 0.5, 1900.0)
	var salt_surface := _world.get_surface_at(salt_point)
	if String(salt_surface.get("kind", "")) != "salt":
		failures.append("salt flat surface is misclassified: %s" % str(salt_surface))
	var found_gravel := false
	for road_variant in world_data.get("roads", []):
		var road: Dictionary = road_variant
		if String(road.get("surface", "asphalt")) != "gravel":
			continue
		var samples: Array = road.get("samples", [])
		if samples.size() < 3:
			continue
		var sample: Array = samples[samples.size() / 2]
		var road_surface := _world.get_surface_at(Vector3(float(sample[0]), float(sample[1]) + 0.5, float(sample[2])))
		if String(road_surface.get("kind", "")) == "gravel":
			found_gravel = true
			break
	if not found_gravel:
		failures.append("no gravel road classifies as gravel surface")
	var spawn_surface := _world.get_surface_at(_world.spawn_transform.origin + Vector3(0.0, 0.5, 0.0))
	if String(spawn_surface.get("kind", "")) != "asphalt":
		failures.append("desert spawn is not on asphalt: %s" % str(spawn_surface))
	var atmosphere_state := _atmosphere_fx.get_state() if _atmosphere_fx != null else {}
	if not bool(atmosphere_state.get("ready", false)):
		failures.append("atmosphere is not ready in desert: %s" % str(atmosphere_state))
	var vehicle_effect_state := _vehicle.get_effect_state()
	if int(vehicle_effect_state.get("tire_smoke_emitters", 0)) < 2 or not bool(vehicle_effect_state.get("engine_audio", false)):
		failures.append("vehicle effects/audio incomplete in desert: %s" % str(vehicle_effect_state))


func _desert_screenshot_shots() -> Array[Dictionary]:
	return [
		{
			"name": "01_spawn_gameplay", "time": "day", "hud": true,
			"vehicle": "spawn", "gameplay_camera": true, "frames": 6,
		},
		{
			"name": "d02_town_main_street", "time": "day", "vehicle": "road",
			"vehicle_at": Vector3(700.0, 0.0, 2052.0),
			"camera": Vector3(545.0, 6.0, 2078.0), "target": Vector3(820.0, 5.0, 2032.0),
		},
		{
			"name": "d03_quarry", "time": "day", "vehicle": "hide",
			"camera": Vector3(3040.0, 42.0, 800.0), "target": Vector3(3290.0, 8.0, 1100.0),
		},
		{
			"name": "d04_oil_field_sunset", "time": "sunset", "vehicle": "hide",
			"camera": Vector3(3340.0, 10.0, 2240.0), "target": Vector3(3585.0, 10.0, 2100.0),
		},
		{
			"name": "d05_salt_flat", "time": "day", "vehicle": "road",
			"vehicle_at": Vector3(1800.0, 0.0, 2280.0),
			"camera": Vector3(1620.0, 7.0, 2385.0), "target": Vector3(2050.0, 3.0, 2280.0),
		},
		{
			"name": "d06_canyon_arch", "time": "day", "vehicle": "hide",
			"camera": Vector3(762.0, 5.0, 678.0), "target": Vector3(806.0, 8.0, 726.0),
		},
		{
			"name": "d07_dunes_sunset", "time": "sunset", "vehicle": "hide",
			"camera": Vector3(1720.0, 22.0, 3040.0), "target": Vector3(2040.0, 6.0, 3340.0),
		},
		{
			"name": "d08_oasis", "time": "day", "vehicle": "road",
			"vehicle_at": Vector3(3260.0, 0.0, 3450.0),
			"camera": Vector3(3170.0, 8.0, 3370.0), "target": Vector3(3390.0, 4.0, 3520.0),
		},
		{
			"name": "d09_wind_farm", "time": "day", "vehicle": "hide",
			"camera": Vector3(840.0, 16.0, 2660.0), "target": Vector3(1130.0, 26.0, 2870.0),
		},
		{
			"name": "d10_tunnel_portal", "time": "day", "vehicle": "hide",
			"camera": Vector3(2668.0, 5.0, 712.0), "target": Vector3(2745.0, 5.0, 756.0),
		},
		{
			"name": "d11_mesa_serpentine", "time": "day", "vehicle": "hide",
			"camera": Vector3(1480.0, 55.0, 920.0), "target": Vector3(1760.0, 18.0, 640.0),
		},
		{
			"name": "d12_plane_wreck", "time": "day", "vehicle": "hide",
			"camera": Vector3(2928.0, 6.0, 1548.0), "target": Vector3(2954.0, 3.0, 1578.0),
		},
		{
			"name": "d13_basin_aerial", "time": "day", "vehicle": "hide",
			"camera": Vector3(2000.0, 650.0, 150.0), "target": Vector3(2000.0, 0.0, 2300.0),
		},
		{"name": "d14_menu_worlds", "time": "day", "vehicle": "spawn", "menu_panel": NativeMainMenu.PANEL_WORLDS, "frames": 5},
	]


## 0.2.54 GreenForest smoke gate: own strict checklist against the
## forest spec (docs/GREENFOREST_MAP.md), mirroring the desert gate.
func _run_forest_smoke_checks(failures: Array[String]) -> void:
	if not _world.has_world_data() or _world.get_world_data().is_empty():
		failures.append("forest world data is empty: %s" % _world.build_error)
		return
	var world_data := _world.get_world_data()
	var terrain: Dictionary = world_data.get("terrain", {})
	if (terrain.get("heights", []) as Array).size() != 251001:
		failures.append("forest terrain heights are incomplete")
	if (world_data.get("roads", []) as Array).size() < 35:
		failures.append("forest road network is incomplete")
	var data_stats: Dictionary = world_data.get("stats", {})
	if float(data_stats.get("roadLengthKm", 0.0)) < 50.0:
		failures.append("forest road length is below the 50 km floor: %s" % str(data_stats))
	if int(data_stats.get("scatterInstances", 0)) < 90000:
		failures.append("forest data scatter is below budget: %s" % str(data_stats))
	var es := _world.get_enhancement_stats()
	if not bool(es.get("greenforest_world_0254", false)):
		failures.append("forest build flag is missing: %s" % str(es))
	if int(es.get("forest_scatter", 0)) < 90000:
		failures.append("forest built scatter is below budget: %s" % str(es))
	if int(es.get("forest_trees", 0)) < 35000:
		failures.append("forest tree count is below budget: %s" % str(es))
	if int(es.get("desert_structures", 0)) < 380:
		failures.append("forest structures are incomplete: %s" % str(es))
	if int(es.get("forest_terrain_chunks", 0)) < 100:
		failures.append("forest terrain chunks are missing: %s" % str(es))
	if int(es.get("reflection_probes", 0)) < 6:
		failures.append("forest reflection probes are incomplete: %s" % str(es))
	if int(es.get("road_markings", 0)) < 800:
		failures.append("forest road markings are incomplete: %s" % str(es))
	if int(es.get("desert_bridges", 0)) < 8 or int(es.get("forest_tunnels_built", 0)) != 2 or not bool(es.get("forest_lake", false)):
		failures.append("forest bridges/tunnels/lake are incomplete: %s" % str(es))
	if int(es.get("forest_river_segments", 0)) < 100:
		failures.append("forest river ribbons are incomplete: %s" % str(es))
	if int(es.get("skyline_layers", 0)) < 1 or not bool(es.get("forest_skyline_0254", false)):
		failures.append("forest far-ridge skyline is incomplete: %s" % str(es))
	if int(es.get("desert_road_deck_colliders", 0)) < 2500:
		failures.append("forest physical road deck is incomplete: %s" % str(es))
	if int(es.get("forest_deer", 0)) < 25 or int(es.get("forest_bird_flocks", 0)) != 3 or int(es.get("forest_smoke_points", 0)) < 4:
		failures.append("forest living details are incomplete: %s" % str(es))
	if int(es.get("desert_race_rings", 0)) < 40:
		failures.append("forest race rings are incomplete: %s" % str(es))
	var forest_smoke: Dictionary = world_data.get("forest", {})
	var game_smoke: Dictionary = forest_smoke.get("game", {})
	if (game_smoke.get("circuits", []) as Array).size() != 4 or (game_smoke.get("sprints", []) as Array).size() != 3 or (game_smoke.get("drags", []) as Array).size() != 2 or (game_smoke.get("jumps", []) as Array).size() != 12:
		failures.append("forest race content is incomplete: %s" % str(game_smoke.keys()))
	if (world_data.get("landmarks", []) as Array).size() < 25:
		failures.append("forest landmarks are incomplete")
	# The dam deck must stay above lake level across the open water.
	var lake_smoke: Dictionary = forest_smoke.get("lake", {})
	var lake_y_smoke := float(lake_smoke.get("y", 14.0))
	var dam_ok := false
	for road_variant2 in world_data.get("roads", []):
		var road2: Dictionary = road_variant2
		if String(road2.get("id", "")) != "gf-dam_road":
			continue
		var min_deck_y := 1e9
		for sample_variant2 in road2.get("samples", []):
			var sample2: Array = sample_variant2
			var ndx := (float(sample2[0]) - float(lake_smoke.get("x", 3050.0))) / float(lake_smoke.get("rx", 450.0))
			var ndz := (float(sample2[2]) - float(lake_smoke.get("z", 2200.0))) / float(lake_smoke.get("rz", 400.0))
			if Vector2(ndx, ndz).length() < 0.92:
				min_deck_y = minf(min_deck_y, float(sample2[1]))
		dam_ok = min_deck_y > lake_y_smoke + 0.4
	if not dam_ok:
		failures.append("forest dam deck is not above lake level")
	var meadow_surface := _world.get_surface_at(Vector3(1900.0, _world.height_at(1900.0, 1900.0) + 0.5, 1900.0))
	if String(meadow_surface.get("kind", "")) != "grass":
		failures.append("meadow surface is misclassified: %s" % str(meadow_surface))
	var floor_surface := _world.get_surface_at(Vector3(400.0, _world.height_at(400.0, 2400.0) + 0.5, 2400.0))
	if String(floor_surface.get("kind", "")) != "forest_floor":
		failures.append("dark-forest floor surface is misclassified: %s" % str(floor_surface))
	var mud_surface := _world.get_surface_at(Vector3(1250.0, _world.height_at(1250.0, 2750.0) + 0.5, 2750.0))
	if String(mud_surface.get("kind", "")) != "mud":
		failures.append("swamp mud surface is misclassified: %s" % str(mud_surface))
	var field_surface := _world.get_surface_at(Vector3(1580.0, _world.height_at(1580.0, 3120.0) + 0.5, 3120.0))
	if String(field_surface.get("kind", "")) != "field":
		failures.append("field surface is misclassified: %s" % str(field_surface))
	var found_gravel := false
	for road_variant in world_data.get("roads", []):
		var road: Dictionary = road_variant
		if String(road.get("surface", "asphalt")) != "gravel":
			continue
		var samples: Array = road.get("samples", [])
		if samples.size() < 3:
			continue
		var sample: Array = samples[samples.size() / 2]
		var road_surface := _world.get_surface_at(Vector3(float(sample[0]), float(sample[1]) + 0.5, float(sample[2])))
		if String(road_surface.get("kind", "")) == "gravel":
			found_gravel = true
			break
	if not found_gravel:
		failures.append("no forest dirt road classifies as gravel surface")
	var spawn_surface := _world.get_surface_at(_world.spawn_transform.origin + Vector3(0.0, 0.5, 0.0))
	if String(spawn_surface.get("kind", "")) != "asphalt":
		failures.append("forest spawn is not on asphalt: %s" % str(spawn_surface))
	var atmosphere_state := _atmosphere_fx.get_state() if _atmosphere_fx != null else {}
	if not bool(atmosphere_state.get("ready", false)):
		failures.append("atmosphere is not ready in forest: %s" % str(atmosphere_state))
	var vehicle_effect_state := _vehicle.get_effect_state()
	if int(vehicle_effect_state.get("tire_smoke_emitters", 0)) < 2 or not bool(vehicle_effect_state.get("engine_audio", false)):
		failures.append("vehicle effects/audio incomplete in forest: %s" % str(vehicle_effect_state))


func _forest_screenshot_shots() -> Array[Dictionary]:
	return [
		{
			"name": "01_spawn_gameplay", "time": "day", "hud": true,
			"vehicle": "spawn", "gameplay_camera": true, "frames": 6,
		},
		{
			"name": "f02_village_main", "time": "day", "vehicle": "road",
			"vehicle_at": Vector3(3580.0, 0.0, 2150.0),
			"camera": Vector3(3450.0, 26.0, 1980.0), "target": Vector3(3620.0, 18.0, 2150.0),
		},
		{
			"name": "f03_lake_dam", "time": "day", "vehicle": "road",
			"vehicle_at": Vector3(3050.0, 0.0, 2350.0),
			"camera": Vector3(2870.0, 30.0, 2050.0), "target": Vector3(3120.0, 15.0, 2380.0),
		},
		{
			"name": "f04_dark_forest", "time": "day", "vehicle": "road",
			"vehicle_at": Vector3(520.0, 0.0, 2050.0),
			"camera": Vector3(430.0, 28.0, 1900.0), "target": Vector3(560.0, 22.0, 2100.0),
		},
		{
			"name": "f05_meadow_straight", "time": "day", "vehicle": "road",
			"vehicle_at": Vector3(1900.0, 0.0, 2450.0),
			"camera": Vector3(1750.0, 32.0, 2300.0), "target": Vector3(2000.0, 24.0, 2500.0),
		},
		{
			"name": "f06_serpentine", "time": "day", "vehicle": "hide",
			"camera": Vector3(1250.0, 170.0, 1050.0), "target": Vector3(1650.0, 110.0, 650.0),
		},
		{
			"name": "f07_summit_view_sunset", "time": "sunset", "vehicle": "hide",
			"camera": Vector3(1760.0, 160.0, 420.0), "target": Vector3(2400.0, 40.0, 1400.0),
		},
		{
			"name": "f08_waterfall", "time": "day", "vehicle": "hide",
			"camera": Vector3(3300.0, 120.0, 560.0), "target": Vector3(3385.0, 128.0, 655.0),
		},
		{
			"name": "f09_farm_fields", "time": "day", "vehicle": "road",
			"vehicle_at": Vector3(2000.0, 0.0, 3300.0),
			"camera": Vector3(1820.0, 34.0, 3120.0), "target": Vector3(2150.0, 20.0, 3400.0),
		},
		{
			"name": "f10_sawmill", "time": "day", "vehicle": "hide",
			"camera": Vector3(760.0, 30.0, 3360.0), "target": Vector3(940.0, 20.0, 3520.0),
		},
		{
			"name": "f11_swamp_causeway", "time": "day", "vehicle": "road",
			"vehicle_at": Vector3(1000.0, 0.0, 2920.0),
			"camera": Vector3(850.0, 24.0, 2750.0), "target": Vector3(1050.0, 10.0, 2980.0),
		},
		{
			"name": "f12_cliff_gorge_bridge", "time": "day", "vehicle": "hide",
			"camera": Vector3(3400.0, 150.0, 350.0), "target": Vector3(3550.0, 120.0, 560.0),
		},
		{
			"name": "f13_forest_aerial", "time": "day", "vehicle": "hide",
			"camera": Vector3(2000.0, 700.0, 150.0), "target": Vector3(2000.0, 0.0, 2300.0),
		},
		{"name": "f14_menu_worlds", "time": "day", "vehicle": "spawn", "menu_panel": NativeMainMenu.PANEL_WORLDS, "frames": 5},
	]
