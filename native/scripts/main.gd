extends Node3D

## Native game bootstrap: world, player vehicle, camera rig and HUD.
## This is the first playable Godot vertical slice for the native rebuild.
## Future systems should be added as separate native nodes/scripts
## rather than growing this coordinator.

const WorldBuilderScript := preload("res://scripts/world_builder.gd")
const VehicleScript := preload("res://scripts/vehicle_controller.gd")
const HudScript := preload("res://scripts/hud.gd")

const TIME_MODES: Array[String] = ["day", "sunset", "night"]
const CAMERA_CHASE := 0
const CAMERA_HOOD := 1
const CAMERA_TOP := 2

var _world: NativeWorldBuilder
var _vehicle: NativeVehicle
var _hud: NativeHud
var _camera: Camera3D
var _camera_mode := CAMERA_CHASE
var _snap_camera := true
var _time_index := 0
var _smoke_mode := false
var _smoke_frames := 0
var _smoke_completed := false


func _ready() -> void:
	_smoke_mode = OS.get_cmdline_user_args().has("--native-smoke") or OS.get_cmdline_args().has("--native-smoke")
	Engine.max_fps = 60
	if OS.has_feature("android"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	_world = WorldBuilderScript.new() as NativeWorldBuilder
	_world.name = "NativeWorld"
	add_child(_world)
	var stats := _world.build_world()
	print("[native] RichTown build stats: ", stats)
	if not _world.build_error.is_empty():
		push_error("Native world failed to build: %s" % _world.build_error)

	_vehicle = VehicleScript.new() as NativeVehicle
	add_child(_vehicle)
	_vehicle.reset_requested.connect(_on_vehicle_reset_requested)
	_vehicle.reset_to_transform(_world.spawn_transform)
	_vehicle.global_transform = _world.spawn_transform

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


func _create_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "GameCamera"
	_camera.near = 0.12
	_camera.far = 2800.0
	_camera.fov = 65.0
	add_child(_camera)
	_camera.make_current()
	_camera.current = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"camera_toggle"):
		_cycle_camera()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"time_toggle"):
		_cycle_time()
		get_viewport().set_input_as_handled()


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
		_vehicle.set_headlights_enabled(mode == "night")


func _on_vehicle_reset_requested() -> void:
	_reset_vehicle_to_road()


func _reset_vehicle_to_road() -> void:
	if _world == null or _vehicle == null:
		return
	var target := _world.find_nearest_road_transform(_vehicle.global_position)
	_vehicle.reset_to_transform(target)
	_snap_camera = true


func _process(delta: float) -> void:
	if _camera != null and not _camera.is_current():
		_camera.make_current()
	_update_camera(delta, _snap_camera)
	_snap_camera = false
	if _smoke_mode and not _smoke_completed:
		_smoke_frames += 1
		if _smoke_frames >= 90:
			_smoke_completed = true
			_run_smoke_checks()


func _update_camera(delta: float, snap: bool) -> void:
	if _camera == null or _vehicle == null:
		return

	var speed_kmh := _vehicle.get_absolute_speed_kmh()
	var speed_ratio := clampf(speed_kmh / 240.0, 0.0, 1.0)
	var desired_fov := 64.0 + speed_ratio * 10.0 + (5.0 if _vehicle.is_boosting() else 0.0)
	_camera.fov = lerpf(_camera.fov, desired_fov, 1.0 if snap else clampf(delta * 4.5, 0.0, 1.0))

	match _camera_mode:
		CAMERA_HOOD:
			var hood_position := _vehicle.global_transform * Vector3(0.0, 1.12, -0.32)
			var hood_target := _vehicle.global_transform * Vector3(0.0, 0.98, -34.0)
			_camera.global_position = hood_position
			_camera.look_at(hood_target, Vector3.UP)
		CAMERA_TOP:
			var top_position := _vehicle.global_position + Vector3(0.0, 39.0, 18.0)
			_camera.global_position = top_position
			_camera.look_at(_vehicle.global_position + Vector3.UP * 1.0, Vector3(0.0, 0.0, -1.0))
		_:
			var distance := 7.5 + speed_ratio * 2.4
			var height := 2.65 + speed_ratio * 0.45
			var desired_position := _vehicle.global_transform * Vector3(0.0, height, distance)
			if snap or delta <= 0.0:
				_camera.global_position = desired_position
			else:
				var weight := 1.0 - exp(-7.0 * delta)
				_camera.global_position = _camera.global_position.lerp(desired_position, weight)
			var forward := -_vehicle.global_transform.basis.z
			var target := _vehicle.global_position + Vector3.UP * 1.35 + forward * (8.0 + speed_ratio * 7.0)
			if _camera.global_position.distance_squared_to(target) > 0.001:
				_camera.look_at(target, Vector3.UP)


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
	if _camera == null:
		failures.append("camera node is missing")
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
	if int(stats.get("roadEdges", 0)) < 35:
		failures.append("road stats are missing or too small")
	if int(stats.get("buildings", 0)) < 45:
		failures.append("building stats are missing or too small")
	if int(stats.get("landmarks", 0)) != 15:
		failures.append("landmark stats are incomplete")

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
	if int(minimap_counts.get("roads", 0)) < 35 or int(minimap_counts.get("buildings", 0)) < 45:
		failures.append("minimap did not receive complete world data: %s" % str(minimap_counts))
	var performance_text := String(hud_state.get("performance_text", ""))
	if performance_text.is_empty() or performance_text == "FPS —" or performance_text.contains("WORLD DATA ERROR"):
		failures.append("HUD performance label did not update cleanly: %s" % performance_text)
	var viewport_size: Vector2 = hud_state.get("viewport_size", Vector2.ZERO)
	var speed_rect: Rect2 = hud_state.get("speed_rect", Rect2())
	var pedal_rect: Rect2 = hud_state.get("pedal_rect", Rect2())
	if not _rect_is_on_screen(speed_rect, viewport_size):
		failures.append("speed panel is not fully on screen: rect=%s viewport=%s" % [str(speed_rect), str(viewport_size)])
	if not _rect_is_on_screen(pedal_rect, viewport_size):
		failures.append("pedal row is not fully on screen: rect=%s viewport=%s" % [str(pedal_rect), str(viewport_size)])

	if failures.is_empty():
		print("[native-smoke] PASS world_geometry=%d vehicle_geometry=%d vehicle=%s camera=%s minimap=%s" % [
			world_geometry_count,
			vehicle_geometry_count,
			str(_vehicle.global_position),
			str(_camera.global_position),
			str(minimap_counts),
		])
	_finish_smoke(failures)


func _finish_smoke(failures: Array[String]) -> void:
	if failures.is_empty():
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("[native-smoke] FAIL: %s" % failure)
	get_tree().quit(2)
