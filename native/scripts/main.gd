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


func _ready() -> void:
	Engine.max_fps = 60
	if OS.has_feature("android"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	_world = WorldBuilderScript.new() as NativeWorldBuilder
	_world.name = "NativeWorld"
	add_child(_world)
	var stats := _world.build_world()
	print("[native] RichTown build stats: ", stats)

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
	_camera.current = true
	_camera.near = 0.12
	_camera.far = 2800.0
	_camera.fov = 65.0
	add_child(_camera)


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
	_update_camera(delta, _snap_camera)
	_snap_camera = false


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
