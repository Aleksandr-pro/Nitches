class_name NativeVehicle
extends RigidBody3D

## Native arcade vehicle physics.
##
## The body is a real RigidBody3D.  Four raycasts form the suspension, while
## longitudinal/lateral tyre forces are applied at each contact point.  This
## gives us collisions, slopes, roll, drift and weight transfer without a
## browser physics loop or any JavaScript bridge.

signal reset_requested
signal engine_state_changed(state: int)
signal car_changed(car_id: String)

const MUSTANG_PATH := "res://assets/vehicles/mustang.glb"
const CAR_PAINT_SHADER: Shader = preload("res://shaders/car_paint.gdshader")
const WHEEL_RADIUS := 0.3378

const SUSPENSION_REST_LENGTH := 0.72
const SUSPENSION_TRAVEL := 0.30
const SPRING_STIFFNESS := 28000.0
const SPRING_DAMPING_COMPRESSION := 3600.0
const SPRING_DAMPING_REBOUND := 2150.0
const ANTI_ROLL_FRONT := 8000.0
const ANTI_ROLL_REAR := 6400.0
const WHEELBASE := 2.86
const TRACK_WIDTH := 1.64
const CONTACT_PATCH_SAMPLES := 3
const CONTACT_PATCH_LENGTH_M := 0.24
const TYRE_RELAXATION_LENGTH_M := 0.26
const TYRE_FORCE_MIN_ROLL_SPEED := 3.5
const ENGINE_IDLE_RPM := 850.0
const ENGINE_REDLINE_RPM := 6400.0
const ENGINE_OFF := 0
const ENGINE_CRANKING := 1
const ENGINE_RUNNING := 2
const ENGINE_STOPPING := 3
const CRANK_DURATION_S := 1.18
const STOP_DURATION_S := 0.82
const CRANK_RPM := 260.0
# Owner-supplied spec sheet for the player car (Shelby GT500, 428 cid
# V8): 365 hp SAE gross, 569 Nm at 3200 rpm, 0-100 km/h in 6.0 s,
# ~207 km/h top speed.  The drivetrain is the period 4-speed manual
# (2.32/1.69/1.29/1.00) with a 3.91 final drive, so top speed is
# gearing-limited at the 6400 rpm redline: 6400/3.91 wheel rpm on a
# 0.3378 m tyre is 57.9 m/s = 208 km/h, matching the sheet.
const GEAR_RATIOS: Array[float] = [2.32, 1.69, 1.29, 1.00]
const REVERSE_RATIO := 2.78
const FINAL_DRIVE := 3.91
const DRIVETRAIN_EFFICIENCY := 0.86
const AIR_DENSITY := 1.225
const DRAG_AREA := 0.72
const DOWNFORCE_AREA := 0.52
const SPEC_NAME := "Shelby GT500"
const SPEC_YEAR := 1967
const SPEC_ENGINE := "V8, 7.0 л (428 cid)"
const SPEC_POWER_HP := 365
const SPEC_POWER_NOTE := "SAE gross"
const SPEC_TORQUE_NM := 569
const SPEC_TORQUE_RPM := 3200
const SPEC_ACCEL_0_100_S := 6.0
const SPEC_TOP_SPEED_KMH := 207
const SPEC_GEARBOX := "4-ступенчатая механика"
const SPEC_DRIVE := "задний"
const TUNING_TORQUE_MULTIPLIERS: Array[float] = [1.0, 1.08, 1.16]
const TUNING_PERFORMANCE_INDEX: Array[int] = [612, 648, 701]
const TUNING_CLASS_LABELS: Array[String] = ["A", "A", "S1"]

var steering_angle := 0.0
var throttle_input := 0.0
var steering_input := 0.0
var handbrake_active := false
var boost_active := false
var grounded_wheel_count := 0

var _touch_inputs: Dictionary = {
	"accelerate": false,
	"brake_reverse": false,
	"steer_left": false,
	"steer_right": false,
	"handbrake": false,
	"boost": false,
}
var _wheels: Array[Dictionary] = []
var _wheel_visuals: Array[Dictionary] = []
var _visual_root: Node3D
var _world: NativeWorldBuilder
var _headlights: Array[SpotLight3D] = []
var _paint_materials: Dictionary = {}
var _primary_paint_material: ShaderMaterial
var _secondary_paint_material: ShaderMaterial
var _paint_shader_surfaces := 0
var _secondary_paint_shader_surfaces := 0
var _gloss_trim_surfaces := 0
var _textured_material_overrides := 0
var _paint_color := Color(0.48, 0.025, 0.035)
var _secondary_paint_color := Color(0.92, 0.88, 0.80)
var _wheel_finish_surfaces: Array[Dictionary] = []
var _wheel_finish_id := "silver"
var _tuning_level := 0
var _license_plate := "GT500-67"
var _plate_labels: Array[Label3D] = []
var _headlight_materials: Array[StandardMaterial3D] = []
var _tail_light_materials: Array[StandardMaterial3D] = []
var _smoke_emitters: Array[GPUParticles3D] = []
var _nitro_emitters: Array[GPUParticles3D] = []
var _contact_shadow_material: StandardMaterial3D
var _soft_disc_texture: Texture2D
var _vehicle_audio: NativeVehicleAudio
var _audio_suspended := false
var _nitro := 0.72
var _forward_speed := 0.0
var _lateral_speed := 0.0
var _flip_timer := 0.0
var _last_safe_transform := Transform3D.IDENTITY
var _safe_transform_timer := 0.0
var _steering_visual_angle := 0.0
var _steering_command := 0.0
var _touch_steering_value := 0.0
var _touch_steering_engaged := false
var _touch_pedal_values: Dictionary = {"accelerate": 0.0, "brake_reverse": 0.0}
var _control_type := "wheel"
var _steering_sensitivity := 1.0
var _steering_dead_zone := 0.03
var _tilt_steering_value := 0.0
var _tilt_neutral_roll := 0.0
var _tilt_calibrated := false
var _tilt_sensor_available := false
var _steering_speed_smooth := 0.0
var _steering_limit_smooth := NativeArcadeCarAssist.MAX_STEER_RAD
var _visual_forward_speed := 0.0
var _visual_wheelspin_excess := 0.0
var _filtered_yaw_rate := 0.0
var _yaw_stability_torque := 0.0
var _current_gear := 0
var _engine_state := ENGINE_OFF
var _engine_rpm := 0.0
var _engine_transition_timer := 0.0
var _engine_stop_start_rpm := 0.0
var _ignition_key_was_pressed := false
var _gear_shift_timer := 0.0
var _gear_shift_duration := 0.0
var _shift_torque_blend := 1.0
var _throttle_command := 0.0
var _smoothed_drive_force_per_wheel := 0.0
var _drivetrain_forward_speed := 0.0
var _coupled_rpm := 0.0
var _desired_automatic_gear := 0
var _reverse_engaged := false
var _drive_force_per_wheel := 0.0
var _engine_brake_force_per_wheel := 0.0
var _wheelspin_excess_speed := 0.0
var _rear_slip_ratio := 0.0
var _surface_kind := "asphalt"
var _surface_label := "АСФАЛЬТ"
var _surface_mu := 1.16
var _headlights_enabled := false
var _brake_light_active := false

# 0.2.40 per-car definition (NativeCarCatalog).  The Shelby constants
# above remain the fallback/spec record; runtime physics reads these.
var _car_id := "shelby_gt500"
var _car_definition: Dictionary = {}
var _model_path := MUSTANG_PATH
var _model_loaded := false
var _car_switch_pending := false
var _wheel_radius := WHEEL_RADIUS
var _wheelbase := WHEELBASE
var _front_track := TRACK_WIDTH
var _rear_track := TRACK_WIDTH
var _idle_rpm := ENGINE_IDLE_RPM
var _redline_rpm := ENGINE_REDLINE_RPM
var _shift_up_rpm := 5950.0
var _shift_down_rpm := 2050.0
var _gear_ratios: Array[float] = [2.32, 1.69, 1.29, 1.00]
var _reverse_ratio := REVERSE_RATIO
var _final_drive := FINAL_DRIVE
var _drag_area := DRAG_AREA
var _downforce_area := DOWNFORCE_AREA
var _spring_stiffness := SPRING_STIFFNESS
var _spring_damping_compression := SPRING_DAMPING_COMPRESSION
var _spring_damping_rebound := SPRING_DAMPING_REBOUND
var _anti_roll_front := ANTI_ROLL_FRONT
var _anti_roll_rear := ANTI_ROLL_REAR
var _spring_force_limit := 26500.0
var _tyre_grip_multiplier := 1.0
var _brake_force := 21500.0
var _driven_wheel_count := 2
var _drive_peak_load_fraction := 0.47
var _torque_curve_points: Array[Vector2] = []
var _spec_power_hp := SPEC_POWER_HP
var _spec_torque_nm := SPEC_TORQUE_NM
var _spec_accel_0_100_s := SPEC_ACCEL_0_100_S
var _spec_top_speed_kmh := SPEC_TOP_SPEED_KMH
var _performance_index := TUNING_PERFORMANCE_INDEX[0]
var _tuning_pi_add: Array[int] = [0, 36, 89]


func configure_car(car_id: String) -> void:
	_car_id = NativeCarCatalog.normalize_id(car_id)
	_car_definition = NativeCarCatalog.get_car(_car_id)
	_apply_car_definition()


func get_car_id() -> String:
	return _car_id


func get_car_definition() -> Dictionary:
	return _car_definition.duplicate(true)


func is_car_switch_pending() -> bool:
	return _car_switch_pending


func _apply_car_definition() -> void:
	var car := _car_definition
	_model_path = String(car.get("model_path", MUSTANG_PATH))
	_wheel_radius = float(car.get("wheel_radius_m", WHEEL_RADIUS))
	_wheelbase = float(car.get("wheelbase_m", WHEELBASE))
	_front_track = float(car.get("front_track_m", TRACK_WIDTH))
	_rear_track = float(car.get("rear_track_m", TRACK_WIDTH))
	_idle_rpm = float(car.get("idle_rpm", ENGINE_IDLE_RPM))
	_redline_rpm = float(car.get("redline_rpm", ENGINE_REDLINE_RPM))
	_shift_up_rpm = float(car.get("shift_up_rpm", _redline_rpm * 0.93))
	_shift_down_rpm = float(car.get("shift_down_rpm", 2050.0))
	_gear_ratios.clear()
	for ratio in car.get("gear_ratios", GEAR_RATIOS):
		_gear_ratios.append(float(ratio))
	if _gear_ratios.is_empty():
		_gear_ratios.assign(GEAR_RATIOS)
	_reverse_ratio = float(car.get("reverse_ratio", REVERSE_RATIO))
	_final_drive = float(car.get("final_drive", FINAL_DRIVE))
	_drag_area = float(car.get("drag_area", DRAG_AREA))
	_downforce_area = float(car.get("downforce_area", DOWNFORCE_AREA))
	_spring_stiffness = float(car.get("spring_stiffness", SPRING_STIFFNESS))
	_spring_damping_compression = float(car.get("spring_damping_compression", SPRING_DAMPING_COMPRESSION))
	_spring_damping_rebound = float(car.get("spring_damping_rebound", SPRING_DAMPING_REBOUND))
	_anti_roll_front = float(car.get("anti_roll_front", ANTI_ROLL_FRONT))
	_anti_roll_rear = float(car.get("anti_roll_rear", ANTI_ROLL_REAR))
	_spring_force_limit = float(car.get("spring_force_limit", 26500.0))
	_tyre_grip_multiplier = float(car.get("tyre_grip_multiplier", 1.0))
	_brake_force = float(car.get("brake_force", 21500.0))
	var all_wheel_drive := String(car.get("drivetrain", "rwd")) == "awd"
	_driven_wheel_count = 4 if all_wheel_drive else 2
	_drive_peak_load_fraction = 0.94 if all_wheel_drive else 0.47
	_torque_curve_points.clear()
	for point in car.get("torque_curve", []):
		_torque_curve_points.append(point as Vector2)
	_spec_power_hp = int(car.get("power_hp", SPEC_POWER_HP))
	_spec_torque_nm = int(car.get("torque_nm", SPEC_TORQUE_NM))
	_spec_accel_0_100_s = float(car.get("accel_0_100_s", SPEC_ACCEL_0_100_S))
	_spec_top_speed_kmh = int(car.get("top_speed_kmh", SPEC_TOP_SPEED_KMH))
	_performance_index = int(car.get("performance_index", TUNING_PERFORMANCE_INDEX[0]))
	_tuning_pi_add.clear()
	for value in car.get("tuning_pi_add", [0, 36, 89]):
		_tuning_pi_add.append(int(value))
	while _tuning_pi_add.size() < TUNING_TORQUE_MULTIPLIERS.size():
		_tuning_pi_add.append(_tuning_pi_add[_tuning_pi_add.size() - 1] if not _tuning_pi_add.is_empty() else 0)
	_paint_color = car.get("default_paint_color", Color(0.48, 0.025, 0.035)) as Color
	_secondary_paint_color = car.get("secondary_paint_color", Color(0.92, 0.88, 0.80)) as Color
	_wheel_finish_id = String(car.get("default_wheel_finish", "silver"))
	_tuning_level = 0
	_license_plate = String(car.get("default_plate", "NITCHES"))


func _configure_body_properties() -> void:
	# The RigidBody is the one object the camera must follow through
	# Godot's physics interpolation; make that explicit instead of
	# relying on an inherited scene default.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	mass = float(_car_definition.get("mass_kg", 1450.0))
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = _car_definition.get("center_of_mass", Vector3(0.0, 0.38, 0.02)) as Vector3
	linear_damp = 0.012
	angular_damp = float(_car_definition.get("angular_damp", 0.38))
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 10
	can_sleep = false
	collision_layer = 2
	collision_mask = 1
	var physics_material := PhysicsMaterial.new()
	physics_material.friction = 0.12
	physics_material.bounce = 0.0
	physics_material_override = physics_material


func _build_vehicle_children() -> void:
	_create_collision_shapes()
	_create_suspension_raycasts()
	_create_visual()
	_create_headlights()
	_create_vehicle_effects()
	_create_engine_audio()


func _reset_dynamic_state() -> void:
	steering_angle = 0.0
	throttle_input = 0.0
	steering_input = 0.0
	handbrake_active = false
	boost_active = false
	grounded_wheel_count = 0
	for key in _touch_inputs.keys():
		_touch_inputs[key] = false
	_touch_steering_value = 0.0
	_touch_steering_engaged = false
	_touch_pedal_values = {"accelerate": 0.0, "brake_reverse": 0.0}
	_forward_speed = 0.0
	_lateral_speed = 0.0
	_steering_visual_angle = 0.0
	_steering_command = 0.0
	_visual_forward_speed = 0.0
	_visual_wheelspin_excess = 0.0
	_current_gear = 0
	_engine_rpm = 0.0
	_engine_transition_timer = 0.0
	_engine_stop_start_rpm = 0.0
	_gear_shift_timer = 0.0
	_gear_shift_duration = 0.0
	_shift_torque_blend = 1.0
	_throttle_command = 0.0
	_smoothed_drive_force_per_wheel = 0.0
	_drivetrain_forward_speed = 0.0
	_coupled_rpm = 0.0
	_desired_automatic_gear = 0
	_reverse_engaged = false
	_drive_force_per_wheel = 0.0
	_engine_brake_force_per_wheel = 0.0
	_wheelspin_excess_speed = 0.0
	_rear_slip_ratio = 0.0
	_brake_light_active = false
	_set_engine_state(ENGINE_OFF)


func switch_car(car_id: String) -> bool:
	var next_id := NativeCarCatalog.normalize_id(car_id)
	if _car_switch_pending or next_id == _car_id:
		return false
	_car_switch_pending = true
	var was_frozen := freeze
	if _vehicle_audio != null:
		_vehicle_audio.cancel_event()
		_vehicle_audio.stop_engine_loops()
	_reset_dynamic_state()
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_wheels.clear()
	_wheel_visuals.clear()
	_headlights.clear()
	_paint_materials.clear()
	_primary_paint_material = null
	_secondary_paint_material = null
	_paint_shader_surfaces = 0
	_secondary_paint_shader_surfaces = 0
	_gloss_trim_surfaces = 0
	_textured_material_overrides = 0
	_wheel_finish_surfaces.clear()
	_plate_labels.clear()
	_headlight_materials.clear()
	_tail_light_materials.clear()
	_smoke_emitters.clear()
	_nitro_emitters.clear()
	_contact_shadow_material = null
	_vehicle_audio = null
	_visual_root = null
	_model_loaded = false
	configure_car(next_id)
	_configure_body_properties()
	call_deferred("_finish_car_switch", was_frozen)
	return true


func _finish_car_switch(was_frozen: bool) -> void:
	_build_vehicle_children()
	freeze = was_frozen
	reset_physics_interpolation()
	_car_switch_pending = false
	car_changed.emit(_car_id)


func _ready() -> void:
	name = "PlayerVehicle"
	if _car_definition.is_empty():
		configure_car(NativeCarCatalog.DEFAULT_CAR_ID)
	_configure_body_properties()
	_ensure_input_actions()
	_build_vehicle_children()


func set_world(world: NativeWorldBuilder) -> void:
	_world = world


func _ensure_input_actions() -> void:
	_ensure_action(&"accelerate", [KEY_W, KEY_UP])
	_ensure_action(&"brake_reverse", [KEY_S, KEY_DOWN])
	_ensure_action(&"steer_left", [KEY_A, KEY_LEFT])
	_ensure_action(&"steer_right", [KEY_D, KEY_RIGHT])
	_ensure_action(&"handbrake", [KEY_SPACE])
	_ensure_action(&"boost", [KEY_SHIFT])
	_ensure_action(&"ignition_toggle", [KEY_F, KEY_ENTER])
	_ensure_action(&"reset_car", [KEY_R])
	_ensure_action(&"camera_toggle", [KEY_C])
	_ensure_action(&"time_toggle", [KEY_T])
	_ensure_action(&"map_toggle", [KEY_M, KEY_TAB])


func _ensure_action(action_name: StringName, keys: Array) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for key_variant in keys:
		var keycode := int(key_variant)
		var exists := false
		for existing in InputMap.action_get_events(action_name):
			if existing is InputEventKey and (existing as InputEventKey).physical_keycode == keycode:
				exists = true
				break
		if exists:
			continue
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		InputMap.action_add_event(action_name, event)


func _create_collision_shapes() -> void:
	var body_shape := BoxShape3D.new()
	body_shape.size = _car_definition.get("body_collision_size", Vector3(1.84, 0.68, 4.64)) as Vector3
	var body_collision := CollisionShape3D.new()
	body_collision.name = "BodyCollision"
	body_collision.shape = body_shape
	# Keep the collision floor a little higher than the visual sill. At
	# maximum raycast-suspension compression the old box could intermittently
	# scrape the heightmap, adding a second, much harsher ground contact
	# on top of the tyre forces and making the body twitch under load.
	body_collision.position = _car_definition.get("body_collision_position", Vector3(0.0, 0.62, 0.0)) as Vector3
	add_child(body_collision)

	var cabin_shape := BoxShape3D.new()
	cabin_shape.size = _car_definition.get("cabin_collision_size", Vector3(1.58, 0.54, 2.05)) as Vector3
	var cabin_collision := CollisionShape3D.new()
	cabin_collision.name = "CabinCollision"
	cabin_collision.shape = cabin_shape
	cabin_collision.position = _car_definition.get("cabin_collision_position", Vector3(0.0, 1.03, 0.18)) as Vector3
	add_child(cabin_collision)


func _create_suspension_raycasts() -> void:
	var ray_y := float(_car_definition.get("wheel_ray_y", 0.58))
	var half_wheelbase := _wheelbase * 0.5
	var front_x := _front_track * 0.5
	var rear_x := _rear_track * 0.5
	var front_driven := _driven_wheel_count == 4
	var definitions: Array[Dictionary] = [
		{"name": "WheelFL", "position": Vector3(-front_x, ray_y, -half_wheelbase), "front": true, "driven": front_driven, "side": -1, "axle": 0},
		{"name": "WheelFR", "position": Vector3(front_x, ray_y, -half_wheelbase), "front": true, "driven": front_driven, "side": 1, "axle": 0},
		{"name": "WheelRL", "position": Vector3(-rear_x, ray_y, half_wheelbase), "front": false, "driven": true, "side": -1, "axle": 1},
		{"name": "WheelRR", "position": Vector3(rear_x, ray_y, half_wheelbase), "front": false, "driven": true, "side": 1, "axle": 1},
	]
	for definition in definitions:
		var rays: Array = []
		var base_position: Vector3 = definition.get("position", Vector3.ZERO)
		# 0.2.31 contact patch: a real tyre does not meet the road at an
		# infinitesimal centre point.  Centre/front/rear samples spread
		# each HeightMap triangle boundary over the 24 cm patch, removing
		# the one-tick load steps produced by the old single ray.
		for sample_index in CONTACT_PATCH_SAMPLES:
			var patch_offset := 0.0
			if sample_index == 1:
				patch_offset = -CONTACT_PATCH_LENGTH_M * 0.5
			elif sample_index == 2:
				patch_offset = CONTACT_PATCH_LENGTH_M * 0.5
			var ray := RayCast3D.new()
			ray.name = "%sPatch%d" % [String(definition.get("name", "WheelRay")), sample_index]
			ray.position = base_position + Vector3(0.0, 0.0, patch_offset)
			ray.target_position = Vector3(0.0, -1.12, 0.0)
			ray.collision_mask = 1
			ray.enabled = true
			ray.exclude_parent = true
			add_child(ray)
			rays.append(ray)
		var wheel := definition.duplicate(true)
		wheel["ray"] = rays[0]
		wheel["rays"] = rays
		wheel["grounded"] = false
		wheel["displacement"] = 0.0
		wheel["spring_force"] = 0.0
		wheel["slip_angle"] = 0.0
		wheel["filtered_spring_force"] = 0.0
		wheel["filtered_normal"] = Vector3.UP
		wheel["filtered_displacement"] = 0.0
		wheel["filtered_suspension_velocity"] = 0.0
		wheel["filtered_lateral_force"] = 0.0
		wheel["filtered_longitudinal_force"] = 0.0
		wheel["contact_patch_samples"] = 0
		wheel["surface"] = {"kind": "asphalt", "label": "АСФАЛЬТ", "mu": 1.16, "rolling_resistance": 0.014}
		_wheels.append(wheel)


func _create_visual() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	# The supplied GLB is normalised with +Z as its nose.  Godot vehicles use
	# -Z as forward, so the visual wrapper is turned around once.
	_visual_root.rotation.y = PI
	add_child(_visual_root)

	if _load_car_model():
		_create_license_plates()
		return
	_create_fallback_visual()
	_create_license_plates()


func _load_car_model() -> bool:
	if not ResourceLoader.exists(_model_path):
		push_warning("Car GLB is not staged yet (%s); using native fallback visual" % _model_path)
		return false
	var packed := load(_model_path) as PackedScene
	if packed == null:
		push_warning("Car GLB could not be loaded as a PackedScene: %s" % _model_path)
		return false
	var model := packed.instantiate()
	if model == null:
		return false
	model.name = "CarModel"
	if _count_mesh_instances(model) == 0:
		push_warning("Car GLB contained no renderable meshes; using native fallback visual")
		model.free()
		return false
	_visual_root.add_child(model)
	_paint_shader_surfaces = 0
	_secondary_paint_shader_surfaces = 0
	_gloss_trim_surfaces = 0
	_textured_material_overrides = 0
	_apply_model_materials(model)
	_collect_wheel_visuals(model)
	_model_loaded = true
	return true


func _count_mesh_instances(node: Node) -> int:
	var count := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		count += _count_mesh_instances(child)
	return count


func _paint_material(color: Color) -> ShaderMaterial:
	# Drive car_paint.gdshader: metallic flakes + clearcoat + Fresnel tint.
	# It replaces the flat StandardMaterial3D paint only on Paint surfaces.
	if _paint_materials.has(color):
		return _paint_materials[color] as ShaderMaterial
	var material := ShaderMaterial.new()
	material.shader = CAR_PAINT_SHADER
	_configure_paint_material(material, color)
	_paint_materials[color] = material
	return material


func _configure_paint_material(material: ShaderMaterial, color: Color) -> void:
	# 0.2.41: the old warm/orange flake and Fresnel tints were tuned for
	# Shelby's warm factory colours.  On silver and black they produced
	# visible beige/brown speckle and made an active clearcoat shader
	# read as dusty matte paint.  Keep Shelby's defaults, but use the
	# catalog's per-car finish and only keep warm tints for warm colours.
	var flake_target := Color(0.82, 0.88, 0.96)
	var fresnel_target := Color(0.34, 0.56, 0.88)
	if color.r > color.b * 1.18 and color.r > color.g * 1.12:
		flake_target = Color(1.0, 0.86, 0.72)
		fresnel_target = Color(1.0, 0.28, 0.08)
	var flake_amount := clampf(float(_car_definition.get("paint_flake_tint_amount", 0.58)), 0.0, 1.0)
	var fresnel_amount := clampf(float(_car_definition.get("paint_fresnel_tint_amount", 0.32)), 0.0, 1.0)
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("flake_color", color.lerp(flake_target, flake_amount))
	material.set_shader_parameter("fresnel_color", color.lerp(fresnel_target, fresnel_amount))
	material.set_shader_parameter("metallic_amount", clampf(float(_car_definition.get("paint_metallic", 0.68)), 0.0, 1.0))
	material.set_shader_parameter("roughness_amount", clampf(float(_car_definition.get("paint_roughness", 0.19)), 0.02, 1.0))
	material.set_shader_parameter("clearcoat_amount", clampf(float(_car_definition.get("paint_clearcoat", 1.0)), 0.0, 1.0))
	material.set_shader_parameter("clearcoat_rough", clampf(float(_car_definition.get("paint_clearcoat_roughness", 0.075)), 0.005, 1.0))
	material.set_shader_parameter("flake_density", maxf(1.0, float(_car_definition.get("paint_flake_density", 180.0))))
	material.set_shader_parameter("flake_strength", clampf(float(_car_definition.get("paint_flake_strength", 0.5)), 0.0, 1.0))
	material.set_shader_parameter("fresnel_strength", clampf(float(_car_definition.get("paint_fresnel_strength", 0.24)), 0.0, 1.0))


func set_paint_color(color: Color) -> void:
	_paint_color = color
	if _primary_paint_material != null:
		_configure_paint_material(_primary_paint_material, _paint_color)


func set_secondary_paint_color(color: Color) -> void:
	_secondary_paint_color = color
	if _secondary_paint_material != null:
		_configure_paint_material(_secondary_paint_material, _secondary_paint_color)


func get_paint_color() -> Color:
	return _paint_color


func set_wheel_finish(finish_id: String) -> void:
	_wheel_finish_id = finish_id
	if _wheel_finish_surfaces.is_empty():
		for wheel_variant in _wheel_visuals:
			var spin := wheel_variant.get("spin", null) as Node
			if spin != null:
				_collect_wheel_finish_surfaces(spin)
	var finish := StandardMaterial3D.new()
	match finish_id:
		"black":
			finish.albedo_color = Color(0.018, 0.02, 0.024)
			finish.metallic = 0.72
			finish.roughness = 0.34
		"bronze":
			finish.albedo_color = Color(0.48, 0.27, 0.09)
			finish.metallic = 0.95
			finish.roughness = 0.24
		"white":
			finish.albedo_color = Color(0.88, 0.89, 0.90)
			finish.metallic = 0.35
			finish.roughness = 0.28
		_:
			_wheel_finish_id = "silver"
			finish.albedo_color = Color(0.72, 0.75, 0.78)
			finish.metallic = 1.0
			finish.roughness = 0.16
	for surface_variant in _wheel_finish_surfaces:
		var mesh_instance := surface_variant.get("mesh", null) as MeshInstance3D
		if mesh_instance != null:
			mesh_instance.set_surface_override_material(int(surface_variant.get("surface", 0)), finish)


func _collect_wheel_finish_surfaces(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var node_name := String(mesh_instance.name).to_lower()
		if mesh_instance.mesh != null and not node_name.contains("tyre") and not node_name.contains("tire"):
			for surface_index in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.get_surface_override_material(surface_index)
				if material == null:
					material = mesh_instance.mesh.surface_get_material(surface_index)
				var material_name := String(material.resource_name).to_lower() if material != null else ""
				if material_name.contains("tyre") or material_name.contains("tire") or material_name.contains("rubber") or material_name.contains("brake") or material_name.contains("disc") or material_name.contains("caliper"):
					continue
				if material is StandardMaterial3D:
					var standard := material as StandardMaterial3D
					if standard.roughness > 0.90 and standard.albedo_color.get_luminance() < 0.05:
						continue
				_wheel_finish_surfaces.append({"mesh": mesh_instance, "surface": surface_index})
	for child in node.get_children():
		_collect_wheel_finish_surfaces(child)


func set_tuning_level(level: int) -> void:
	_tuning_level = clampi(level, 0, TUNING_TORQUE_MULTIPLIERS.size() - 1)


func get_tuning_level() -> int:
	return _tuning_level


func _tuning_performance_index(level: int) -> int:
	var safe_level := clampi(level, 0, TUNING_TORQUE_MULTIPLIERS.size() - 1)
	var add := _tuning_pi_add[safe_level] if safe_level < _tuning_pi_add.size() else 0
	return _performance_index + add


func get_tuning_preview(level: int) -> Dictionary:
	var safe_level := clampi(level, 0, TUNING_TORQUE_MULTIPLIERS.size() - 1)
	var multiplier := TUNING_TORQUE_MULTIPLIERS[safe_level]
	var pi := _tuning_performance_index(safe_level)
	return {
		"level": safe_level,
		"power_hp": int(round(float(_spec_power_hp) * multiplier)),
		"torque_nm": int(round(float(_spec_torque_nm) * multiplier)),
		"accel_0_100_s": _spec_accel_0_100_s / sqrt(multiplier),
		"top_speed_kmh": _spec_top_speed_kmh,
		"performance_index": pi,
		"class_label": NativeCarCatalog.class_label_for_pi(pi),
		"torque_multiplier": multiplier,
	}


func set_license_plate(value: String) -> void:
	var cleaned := value.strip_edges().to_upper()
	if cleaned.is_empty():
		cleaned = String(_car_definition.get("default_plate", "NITCHES"))
	_license_plate = cleaned.left(9)
	for label in _plate_labels:
		label.text = _license_plate
		label.font_size = _license_plate_font_size(_license_plate)


func _license_plate_font_size(text: String) -> int:
	# The white plate is 0.54 m wide.  Keep the longest editable
	# plates (9 chars, e.g. CAMARO-SS) inside that panel instead of
	# letting the outer glyphs spill onto the bumper.
	return clampi(int(round(720.0 / float(maxi(1, text.length())))), 64, 96)


func _create_license_plates() -> void:
	if not _plate_labels.is_empty():
		return
	var rear := _car_definition.get("plate_rear_position", Vector3(0.0, 0.58, 2.335)) as Vector3
	var front := _car_definition.get("plate_front_position", Vector3(0.0, 0.58, -2.335)) as Vector3
	_add_license_plate(rear, 0.0)
	_add_license_plate(front, PI)


func _add_license_plate(position_value: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.name = "LicensePlateRear" if position_value.z > 0.0 else "LicensePlateFront"
	root.position = position_value
	root.rotation.y = yaw
	add_child(root)
	var panel := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.54, 0.15, 0.018)
	panel.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.94, 0.95, 0.96)
	material.metallic = 0.08
	material.roughness = 0.42
	panel.material_override = material
	root.add_child(panel)
	var label := Label3D.new()
	label.text = _license_plate
	label.position = Vector3(0.0, 0.0, 0.016)
	label.pixel_size = 0.00135
	label.font_size = _license_plate_font_size(_license_plate)
	label.modulate = Color(0.025, 0.035, 0.05)
	label.outline_modulate = Color(0.94, 0.95, 0.96)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(label)
	_plate_labels.append(label)


func get_customization_state() -> Dictionary:
	return {
		"customization_0234": true,
		"multi_car_0240": true,
		"car_id": _car_id,
		"model_path": _model_path,
		"model_loaded": _model_loaded,
		"wheel_visuals": _wheel_visuals.size(),
		"paint_color": _paint_color,
		"wheel_finish": _wheel_finish_id,
		"wheel_finish_surfaces": _wheel_finish_surfaces.size(),
		"tuning_level": _tuning_level,
		"tuning": get_tuning_preview(_tuning_level),
		"license_plate": _license_plate,
		"license_plate_labels": _plate_labels.size(),
	}


func _apply_model_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if mesh_instance.mesh != null:
			for surface_index in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.get_surface_override_material(surface_index)
				if material == null:
					material = mesh_instance.mesh.surface_get_material(surface_index)
				if material == null:
					continue
				var material_name := String(material.resource_name)
				var lower_name := material_name.to_lower()
				var authored_texture := false
				if material is StandardMaterial3D:
					authored_texture = (material as StandardMaterial3D).albedo_texture != null
				if authored_texture and material_name != "Paint" and material_name != "PaintSecondary":
					# 0.2.40 supplied-car GLBs carry real authored PBR
					# textures (Mercedes interior/tyres/lights, the
					# Camaro livery shell and atlas wheels).  Semantic
					# flat replacements below are only for untextured
					# surfaces; never flatten a textured one.  0.2.41:
					# preserve the texture but normalise scalar response;
					# several imported materials omit glTF roughness, so
					# Godot correctly reads them as fully matte (1.0).
					var textured_override := _textured_material_override(material as StandardMaterial3D, lower_name)
					if textured_override != null:
						mesh_instance.set_surface_override_material(surface_index, textured_override)
						_textured_material_overrides += 1
				elif material_name == "Paint":
					_primary_paint_material = _paint_material(_paint_color)
					mesh_instance.set_surface_override_material(surface_index, _primary_paint_material)
					_paint_shader_surfaces += 1
				elif material_name == "PaintSecondary":
					_secondary_paint_material = _paint_material(_secondary_paint_color)
					mesh_instance.set_surface_override_material(surface_index, _secondary_paint_material)
					_secondary_paint_shader_surfaces += 1
				elif lower_name == "blackgloss" or lower_name.contains("black gloss"):
					# Give the converter's exact BlackGloss semantic its
					# own opaque piano-black clearcoat.  Previously it
					# fell through every runtime branch and kept the
					# softer imported scalar finish at gameplay range.
					var piano_black := StandardMaterial3D.new()
					piano_black.albedo_color = Color(0.012, 0.013, 0.016)
					piano_black.metallic = 0.28
					piano_black.roughness = 0.16
					piano_black.metallic_specular = 1.0
					piano_black.clearcoat_enabled = true
					piano_black.clearcoat = 0.9
					piano_black.clearcoat_roughness = 0.05
					mesh_instance.set_surface_override_material(surface_index, piano_black)
					_gloss_trim_surfaces += 1
				elif lower_name == "blacktrim" or lower_name.contains("black trim"):
					var black_trim := StandardMaterial3D.new()
					black_trim.albedo_color = Color(0.014, 0.015, 0.017)
					black_trim.metallic = 0.08
					black_trim.roughness = 0.46
					black_trim.clearcoat_enabled = true
					black_trim.clearcoat = 0.35
					black_trim.clearcoat_roughness = 0.18
					mesh_instance.set_surface_override_material(surface_index, black_trim)
					_gloss_trim_surfaces += 1
				elif lower_name == "greytrim" or lower_name == "graytrim":
					var grey_trim := StandardMaterial3D.new()
					grey_trim.albedo_color = Color(0.16, 0.165, 0.17)
					grey_trim.metallic = 0.12
					grey_trim.roughness = 0.50
					grey_trim.clearcoat_enabled = true
					grey_trim.clearcoat = 0.25
					grey_trim.clearcoat_roughness = 0.22
					mesh_instance.set_surface_override_material(surface_index, grey_trim)
					_gloss_trim_surfaces += 1
				elif lower_name == "redtrim":
					var red_trim := StandardMaterial3D.new()
					red_trim.albedo_color = Color(0.48, 0.012, 0.018)
					red_trim.metallic = 0.18
					red_trim.roughness = 0.20
					red_trim.clearcoat_enabled = true
					red_trim.clearcoat = 0.7
					red_trim.clearcoat_roughness = 0.08
					mesh_instance.set_surface_override_material(surface_index, red_trim)
					_gloss_trim_surfaces += 1
				elif lower_name == "glass" or lower_name == "glasswindow" or lower_name.contains("window") or lower_name.contains("windshield"):
					var glass := StandardMaterial3D.new()
					glass.albedo_color = Color(0.025, 0.055, 0.078, 0.70)
					glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					glass.metallic = 0.08
					glass.roughness = 0.055
					glass.metallic_specular = 1.0
					glass.clearcoat_enabled = true
					glass.clearcoat = 0.92
					glass.clearcoat_roughness = 0.035
					mesh_instance.set_surface_override_material(surface_index, glass)
				elif lower_name.contains("tyre") or lower_name.contains("tire") or lower_name.contains("rubber"):
					var tyre := StandardMaterial3D.new()
					tyre.albedo_color = Color(0.018, 0.018, 0.02)
					tyre.metallic = 0.0
					tyre.roughness = 0.94
					mesh_instance.set_surface_override_material(surface_index, tyre)
				elif lower_name.contains("chrome"):
					var chrome := StandardMaterial3D.new()
					chrome.albedo_color = Color(0.72, 0.75, 0.78)
					chrome.metallic = 1.0
					chrome.roughness = 0.16
					mesh_instance.set_surface_override_material(surface_index, chrome)
				elif lower_name.contains("carbon"):
					var carbon := StandardMaterial3D.new()
					carbon.albedo_color = Color(0.025, 0.028, 0.032)
					carbon.metallic = 0.32
					carbon.roughness = 0.38
					carbon.clearcoat_enabled = true
					carbon.clearcoat = 0.65
					carbon.clearcoat_roughness = 0.18
					mesh_instance.set_surface_override_material(surface_index, carbon)
				elif lower_name.contains("tail") or lower_name.contains("rearlight") or lower_name.contains("brakelight"):
					var tail := StandardMaterial3D.new()
					tail.albedo_color = Color(0.38, 0.015, 0.025)
					tail.metallic = 0.05
					tail.roughness = 0.2
					tail.emission_enabled = true
					tail.emission = Color(1.0, 0.03, 0.04)
					tail.emission_energy_multiplier = 0.75
					_tail_light_materials.append(tail)
					mesh_instance.set_surface_override_material(surface_index, tail)
				elif lower_name.contains("headlight") or lower_name.contains("headlamp"):
					var lens := StandardMaterial3D.new()
					lens.albedo_color = Color(0.72, 0.84, 0.92)
					lens.metallic = 0.08
					lens.roughness = 0.08
					lens.metallic_specular = 1.0
					lens.emission_enabled = true
					lens.emission = Color(1.0, 0.94, 0.78)
					lens.emission_energy_multiplier = 0.0
					_headlight_materials.append(lens)
					mesh_instance.set_surface_override_material(surface_index, lens)
	for child in node.get_children():
		_apply_model_materials(child)


func _textured_material_override(material: StandardMaterial3D, lower_name: String) -> StandardMaterial3D:
	if material == null:
		return null
	# Atlas-painted wheels already encode tyre and metal in one texture;
	# leave that two-material albedo exactly as authored.
	if lower_name == "tirerimtexture":
		return null
	var roughness := -1.0
	var metallic := -1.0
	var clearcoat := 0.0
	var clearcoat_roughness := 0.12
	if lower_name.contains("livery"):
		roughness = 0.22
		metallic = 0.38
		clearcoat = 0.85
		clearcoat_roughness = 0.06
	elif lower_name.contains("lighttexture") or lower_name.contains("headlight") or lower_name.contains("taillight"):
		roughness = 0.16
		metallic = 0.08
		clearcoat = 0.75
		clearcoat_roughness = 0.05
	elif lower_name.contains("plastic"):
		roughness = 0.52
		metallic = 0.04
		clearcoat = 0.28
		clearcoat_roughness = 0.20
	elif lower_name.contains("chassis"):
		roughness = 0.48
		metallic = 0.22
		clearcoat = 0.22
		clearcoat_roughness = 0.18
	elif lower_name.contains("engine"):
		roughness = 0.58
		metallic = 0.35
	elif lower_name.contains("leather"):
		roughness = 0.72
		metallic = 0.0
	elif lower_name.contains("velvet") or lower_name.contains("cover"):
		roughness = 0.88
		metallic = 0.0
	elif lower_name.contains("interior"):
		roughness = 0.68
		metallic = 0.02
	elif lower_name.contains("tire") or lower_name.contains("tyre"):
		roughness = 0.94
		metallic = 0.0
	else:
		return null
	var tuned := material.duplicate() as StandardMaterial3D
	if tuned == null:
		return null
	tuned.roughness = roughness
	tuned.metallic = metallic
	tuned.metallic_specular = maxf(tuned.metallic_specular, 0.75)
	if clearcoat > 0.0:
		tuned.clearcoat_enabled = true
		tuned.clearcoat = clearcoat
		tuned.clearcoat_roughness = clearcoat_roughness
	return tuned


func _find_node_by_name(node: Node, target_name: String) -> Node:
	if String(node.name) == target_name:
		return node
	for child in node.get_children():
		var found := _find_node_by_name(child, target_name)
		if found != null:
			return found
	return null


func _collect_wheel_visuals(model: Node) -> void:
	_wheel_visuals.clear()
	for definition in [
		{"pivot": "Wheel_FL", "spin": "Wheel_FL_Spin", "front": true, "side": -1},
		{"pivot": "Wheel_FR", "spin": "Wheel_FR_Spin", "front": true, "side": 1},
		{"pivot": "Wheel_RL", "spin": "Wheel_RL_Spin", "front": false, "side": -1},
		{"pivot": "Wheel_RR", "spin": "Wheel_RR_Spin", "front": false, "side": 1},
	]:
		var pivot := _find_node_by_name(model, String(definition.get("pivot", ""))) as Node3D
		var spin := _find_node_by_name(model, String(definition.get("spin", ""))) as Node3D
		if pivot != null and spin != null:
			# Wheel locals are animated in _process, so only their local
			# transforms opt out; the interpolated RigidBody parent still
			# carries them smoothly through the world.
			pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			spin.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			_wheel_visuals.append({
				"pivot": pivot,
				"spin": spin,
				"front": bool(definition.get("front", false)),
				"driven": not bool(definition.get("front", false)) or _driven_wheel_count == 4,
				"side": int(definition.get("side", 1)),
				"pivot_y": pivot.rotation.y,
				"base_position": pivot.position,
			})
	if _wheel_visuals.size() != 4:
		push_warning("Car wheel pivots found for %s: %d/4" % [_car_id, _wheel_visuals.size()])


func _create_fallback_visual() -> void:
	var paint := _paint_material(_paint_color)
	_primary_paint_material = paint
	_paint_shader_surfaces = 2
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.025, 0.03, 0.04)
	dark.metallic = 0.45
	dark.roughness = 0.32

	_add_visual_box(Vector3(float(_car_definition.get("width_m", 1.82)) * 0.96, 0.46, float(_car_definition.get("length_m", 4.58)) * 0.97), Vector3(0.0, 0.50, 0.0), paint, "FallbackBody")
	_add_visual_box(Vector3(1.56, 0.42, 2.05), Vector3(0.0, 0.90, -0.16), dark, "FallbackCabin")
	_add_visual_box(Vector3(1.70, 0.16, 0.55), Vector3(0.0, 0.72, 1.95), paint, "FallbackSpoiler")

	_wheel_visuals.clear()
	for definition in [
		{"position": Vector3(-_front_track * 0.5, _wheel_radius, _wheelbase * 0.5), "front": true, "side": -1},
		{"position": Vector3(_front_track * 0.5, _wheel_radius, _wheelbase * 0.5), "front": true, "side": 1},
		{"position": Vector3(-_rear_track * 0.5, _wheel_radius, -_wheelbase * 0.5), "front": false, "side": -1},
		{"position": Vector3(_rear_track * 0.5, _wheel_radius, -_wheelbase * 0.5), "front": false, "side": 1},
	]:
		var pivot := Node3D.new()
		pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		pivot.position = definition.get("position", Vector3.ZERO)
		_visual_root.add_child(pivot)
		var spin := Node3D.new()
		spin.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		pivot.add_child(spin)
		var tyre := MeshInstance3D.new()
		tyre.name = "FallbackTyre"
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = _wheel_radius
		cylinder.bottom_radius = _wheel_radius
		cylinder.height = 0.28
		cylinder.radial_segments = 24
		tyre.mesh = cylinder
		tyre.material_override = dark
		tyre.rotation.z = PI * 0.5
		spin.add_child(tyre)
		_wheel_visuals.append({
			"pivot": pivot,
			"spin": spin,
			"front": bool(definition.get("front", false)),
			"driven": not bool(definition.get("front", false)) or _driven_wheel_count == 4,
			"side": int(definition.get("side", 1)),
			"pivot_y": 0.0,
			"base_position": pivot.position,
		})


func _add_visual_box(size: Vector3, center: Vector3, material: Material, node_name: String) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = material
	instance.position = center
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_visual_root.add_child(instance)


func _create_headlights() -> void:
	var anchor := _car_definition.get("headlight_position", Vector3(0.62, 0.74, -2.22)) as Vector3
	for x in [-anchor.x, anchor.x]:
		var light := SpotLight3D.new()
		light.name = "Headlight"
		light.position = Vector3(x, anchor.y, anchor.z)
		light.light_color = Color(1.0, 0.92, 0.76)
		light.light_energy = 0.0
		light.spot_range = 48.0
		light.spot_angle = 27.0
		light.spot_attenuation = 1.2
		light.shadow_enabled = false
		add_child(light)
		_headlights.append(light)


func set_headlights_enabled(enabled: bool) -> void:
	_headlights_enabled = enabled
	for light in _headlights:
		light.light_energy = 4.2 if enabled else 0.0
	for material in _headlight_materials:
		material.emission_energy_multiplier = 3.2 if enabled else 0.0


func _get_soft_disc_texture() -> Texture2D:
	if _soft_disc_texture != null:
		return _soft_disc_texture
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var nx := (float(x) / float(size - 1) - 0.5) * 2.0
			var ny := (float(y) / float(size - 1) - 0.5) * 2.0
			var radius := sqrt(nx * nx + ny * ny)
			var alpha := clampf(1.0 - smoothstep(0.42, 1.0, radius), 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_soft_disc_texture = ImageTexture.create_from_image(image)
	return _soft_disc_texture


func _particle_material(color: Color, emissive: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.albedo_texture = _get_soft_disc_texture()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.metallic_specular = 0.0
	if emissive:
		material.emission_enabled = true
		material.emission = Color(color.r, color.g, color.b)
		material.emission_energy_multiplier = 2.4
	return material


func _make_particle_emitter(
	node_name: String,
	position_value: Vector3,
	amount: int,
	lifetime: float,
	direction: Vector3,
	spread: float,
	min_velocity: float,
	max_velocity: float,
	min_scale: float,
	max_scale: float,
	quad_size: float,
	material: Material,
	gravity: Vector3 = Vector3.ZERO
) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	if material is StandardMaterial3D:
		process.color = (material as StandardMaterial3D).albedo_color
	process.direction = direction
	process.spread = spread
	process.initial_velocity_min = min_velocity
	process.initial_velocity_max = max_velocity
	process.gravity = gravity
	process.damping_min = 1.6
	process.damping_max = 3.8
	process.scale_min = min_scale
	process.scale_max = max_scale
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.20
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.16, Color(1.0, 1.0, 1.0, 0.82))
	gradient.add_point(0.72, Color(1.0, 1.0, 1.0, 0.42))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var gradient_texture := GradientTexture1D.new()
	gradient_texture.gradient = gradient
	gradient_texture.width = 64
	process.color_ramp = gradient_texture

	var quad := QuadMesh.new()
	quad.size = Vector2(quad_size, quad_size)
	quad.material = material

	var emitter := GPUParticles3D.new()
	emitter.name = node_name
	emitter.position = position_value
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.randomness = 0.62
	emitter.local_coords = false
	emitter.process_material = process
	emitter.draw_pass_1 = quad
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.visibility_aabb = AABB(Vector3(-16.0, -4.0, -20.0), Vector3(32.0, 10.0, 40.0))
	emitter.emitting = false
	add_child(emitter)
	return emitter


func _create_vehicle_effects() -> void:
	_contact_shadow_material = StandardMaterial3D.new()
	_contact_shadow_material.albedo_color = Color(0.0, 0.0, 0.0, 0.30)
	_contact_shadow_material.albedo_texture = _get_soft_disc_texture()
	_contact_shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_contact_shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_contact_shadow_material.metallic_specular = 0.0
	var shadow_mesh := PlaneMesh.new()
	shadow_mesh.size = _car_definition.get("contact_shadow_size", Vector2(2.28, 5.08)) as Vector2
	shadow_mesh.material = _contact_shadow_material
	var contact_shadow := MeshInstance3D.new()
	contact_shadow.name = "ContactShadow"
	contact_shadow.mesh = shadow_mesh
	contact_shadow.position = Vector3(0.0, 0.035, 0.0)
	contact_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	contact_shadow.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(contact_shadow)

	var smoke_x := float(_car_definition.get("smoke_x", 0.82))
	var smoke_z := float(_car_definition.get("smoke_z", 1.50))
	for x in [-smoke_x, smoke_x]:
		_smoke_emitters.append(_make_particle_emitter(
			"RearTyreSmoke",
			Vector3(x, 0.20, smoke_z),
			52,
			0.92,
			Vector3(0.0, 0.24, 1.0),
			28.0,
			0.7,
			2.8,
			0.55,
			1.25,
			0.62,
			_particle_material(Color(0.72, 0.72, 0.74, 0.34)),
			Vector3(0.0, 0.45, 0.0)
		))
	var exhaust := _car_definition.get("exhaust_position", Vector3(0.56, 0.36, 2.34)) as Vector3
	for x in [-exhaust.x, exhaust.x]:
		_nitro_emitters.append(_make_particle_emitter(
			"NitroFlame",
			Vector3(x, exhaust.y, exhaust.z),
			38,
			0.30,
			Vector3(0.0, 0.0, 1.0),
			7.0,
			7.0,
			12.0,
			0.55,
			1.0,
			0.28,
			_particle_material(Color(0.25, 0.82, 1.0, 0.72), true)
		))


func _create_engine_audio() -> void:
	_vehicle_audio = NativeVehicleAudio.new()
	_vehicle_audio.configure_for_car(_car_id)
	add_child(_vehicle_audio)
	_vehicle_audio.set_suspended(_audio_suspended)
	engine_state_changed.emit(_engine_state)


func _set_engine_state(next_state: int) -> void:
	var clamped_state := clampi(next_state, ENGINE_OFF, ENGINE_STOPPING)
	if clamped_state == _engine_state:
		return
	_engine_state = clamped_state
	engine_state_changed.emit(_engine_state)


func get_engine_state() -> int:
	return _engine_state


func is_engine_running() -> bool:
	return _engine_state == ENGINE_RUNNING


func start_engine() -> void:
	if _engine_state == ENGINE_RUNNING or _engine_state == ENGINE_CRANKING:
		return
	_engine_transition_timer = CRANK_DURATION_S
	_engine_stop_start_rpm = 0.0
	_reverse_engaged = false
	_current_gear = 0
	_gear_shift_timer = 0.0
	_gear_shift_duration = 0.0
	_shift_torque_blend = 1.0
	_set_engine_state(ENGINE_CRANKING)
	if _vehicle_audio != null:
		_vehicle_audio.play_start()


func stop_engine(play_sound: bool = true) -> void:
	if _engine_state == ENGINE_OFF or _engine_state == ENGINE_STOPPING:
		return
	_engine_stop_start_rpm = maxf(_engine_rpm, _idle_rpm if _engine_state == ENGINE_RUNNING else CRANK_RPM)
	_engine_transition_timer = STOP_DURATION_S
	boost_active = false
	_reverse_engaged = false
	_set_engine_state(ENGINE_STOPPING)
	if _vehicle_audio != null:
		if play_sound:
			_vehicle_audio.play_stop()
		else:
			_vehicle_audio.cancel_event()
			_vehicle_audio.stop_engine_loops()


func toggle_engine() -> void:
	match _engine_state:
		ENGINE_RUNNING, ENGINE_CRANKING:
			stop_engine()
		_:
			start_engine()


func set_audio_suspended(suspended: bool) -> void:
	_audio_suspended = suspended
	if _vehicle_audio != null:
		_vehicle_audio.set_suspended(suspended)


func get_engine_load() -> float:
	if _engine_state != ENGINE_RUNNING:
		return 0.0
	var load := 0.0
	if _reverse_engaged:
		load = absf(minf(throttle_input, 0.0))
	elif throttle_input > 0.0:
		load = throttle_input
	load *= _shift_torque_blend
	if boost_active:
		load = minf(load * 1.08 + 0.08, 1.0)
	return clampf(load, 0.0, 1.0)


func get_audio_state() -> Dictionary:
	if _vehicle_audio == null:
		return {
			"recorded_audio_0235": false,
			"streams_ready": false,
			"engine_state": _engine_state,
			"engine_rpm": _engine_rpm,
		}
	var state := _vehicle_audio.get_smoke_state()
	state["engine_state"] = _engine_state
	state["engine_rpm"] = _engine_rpm
	state["engine_load"] = get_engine_load()
	return state


func _update_engine_state(delta: float) -> void:
	var ignition_down := Input.is_action_pressed(&"ignition_toggle")
	if ignition_down and not _ignition_key_was_pressed:
		toggle_engine()
	_ignition_key_was_pressed = ignition_down

	match _engine_state:
		ENGINE_CRANKING:
			_engine_transition_timer = maxf(_engine_transition_timer - delta, 0.0)
			var progress := clampf(1.0 - _engine_transition_timer / CRANK_DURATION_S, 0.0, 1.0)
			if progress < 0.62:
				var crank_target := CRANK_RPM + sin(progress * TAU * 3.0) * 24.0
				_engine_rpm = move_toward(_engine_rpm, crank_target, 1500.0 * delta)
			else:
				# The recorded catch flares briefly, then settles onto
				# this car's idle used by the drivetrain and gauge.
				var settle := smoothstep(0.62, 1.0, progress)
				_engine_rpm = lerpf(_idle_rpm * 1.42, _idle_rpm, settle)
			if _engine_transition_timer <= 0.0:
				_engine_rpm = maxf(_engine_rpm, _idle_rpm)
				_set_engine_state(ENGINE_RUNNING)
		ENGINE_STOPPING:
			_engine_transition_timer = maxf(_engine_transition_timer - delta, 0.0)
			var stop_progress := clampf(1.0 - _engine_transition_timer / STOP_DURATION_S, 0.0, 1.0)
			var eased := 1.0 - pow(1.0 - stop_progress, 3.0)
			var shudder := sin(stop_progress * 34.0) * 34.0 * (1.0 - stop_progress) * (1.0 if stop_progress >= 0.18 else 0.0)
			_engine_rpm = maxf(_engine_stop_start_rpm * (1.0 - eased) + shudder, 0.0)
			if _engine_transition_timer <= 0.0:
				_engine_rpm = 0.0
				_current_gear = 0
				_reverse_engaged = false
				_set_engine_state(ENGINE_OFF)
				if _vehicle_audio != null:
					_vehicle_audio.stop_engine_loops()
		ENGINE_OFF:
			_engine_rpm = move_toward(_engine_rpm, 0.0, 2400.0 * delta)
		ENGINE_RUNNING:
			pass


func _update_vehicle_audio(delta: float) -> void:
	if _vehicle_audio == null or _audio_suspended:
		return
	var tire_level := 0.0
	if grounded_wheel_count >= 2:
		var speed_factor := smoothstep(4.5, 12.0, absf(_forward_speed))
		if speed_factor > 0.0:
			tire_level = maxf(tire_level, clampf((get_drift_angle_degrees() - 7.0) / 28.0, 0.0, 1.0) * speed_factor)
		if handbrake_active:
			tire_level = maxf(tire_level, 0.62 * speed_factor)
		if absf(_rear_slip_ratio) > 0.18 and absf(throttle_input) > 0.05:
			tire_level = maxf(tire_level, clampf((absf(_rear_slip_ratio) - 0.18) / 0.55, 0.0, 1.0))
	var tire_pitch := 0.72 + clampf(absf(_forward_speed) / 42.0, 0.0, 1.0) * 0.38 + clampf(absf(_rear_slip_ratio), 0.0, 1.0) * 0.12
	_vehicle_audio.update_audio(delta, _engine_state, _engine_rpm, get_engine_load(), boost_active, tire_level, tire_pitch)


func set_touch_input(action_name: String, pressed: bool) -> void:
	_touch_inputs[action_name] = pressed


## 0.2.33 HUD settings: control source and steering feel are user
## preferences, persisted by Main.  Switching away from the wheel
## immediately releases any stale analog wheel engagement.
func set_control_preferences(control_type: String, sensitivity: float, dead_zone: float) -> void:
	var next_type := control_type
	if next_type != "wheel" and next_type != "tilt" and next_type != "arrows":
		next_type = "wheel"
	if next_type != _control_type and next_type == "tilt":
		_tilt_calibrated = false
		_tilt_sensor_available = false
		_tilt_steering_value = 0.0
	_control_type = next_type
	_steering_sensitivity = clampf(sensitivity, 0.5, 1.8)
	_steering_dead_zone = clampf(dead_zone, 0.0, 0.25)
	if _control_type != "wheel":
		_touch_steering_engaged = false
		_touch_steering_value = 0.0


func set_touch_pedal(action_name: String, value: float) -> void:
	if _touch_pedal_values.has(action_name):
		_touch_pedal_values[action_name] = clampf(value, 0.0, 1.0)


## 0.2.32: direct analog value from the on-screen steering wheel.
## While engaged it is the highest-priority steering source; the
## wheel keeps emitting during its spring return so the rack follows
## the visible rim all the way back to centre.
func set_touch_steering(value: float, engaged: bool) -> void:
	_touch_steering_value = clampf(value, -1.0, 1.0)
	_touch_steering_engaged = engaged and _control_type == "wheel"
	if _touch_steering_engaged:
		_steering_command = _touch_steering_value


func _touch_pressed(action_name: String) -> bool:
	return bool(_touch_inputs.get(action_name, false))


func _read_inputs(delta: float) -> void:
	var keyboard_throttle := Input.get_axis(&"brake_reverse", &"accelerate")
	var touch_throttle := float(_touch_pedal_values.get("accelerate", 0.0)) - float(_touch_pedal_values.get("brake_reverse", 0.0))
	if absf(touch_throttle) <= 0.01:
		if _touch_pressed("accelerate"):
			touch_throttle += 1.0
		if _touch_pressed("brake_reverse"):
			touch_throttle -= 1.0
	_throttle_command = clampf(touch_throttle if absf(touch_throttle) > 0.01 else keyboard_throttle, -1.0, 1.0)
	if _engine_state != ENGINE_RUNNING:
		# A dead engine cannot launch or reverse.  Preserve the
		# negative pedal because the tyre model uses it as the service
		# brake while the car is still rolling forward.
		_throttle_command = minf(_throttle_command, 0.0)

	var keyboard_steering := Input.get_axis(&"steer_left", &"steer_right")
	var digital_steering_target := 0.0
	if keyboard_steering < -0.5 or _touch_pressed("steer_left"):
		digital_steering_target -= 1.0
	if keyboard_steering > 0.5 or _touch_pressed("steer_right"):
		digital_steering_target += 1.0

	var analog_steering := 0.0
	for device in Input.get_connected_joypads():
		var axis_value := Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
		if absf(axis_value) > absf(analog_steering):
			analog_steering = axis_value
	if _control_type == "tilt":
		_update_tilt_steering(delta)
	if _control_type == "wheel" and _touch_steering_engaged:
		steering_input = NativeArcadeCarAssist.shape_steering_input_with_preferences(_touch_steering_value, _steering_sensitivity, _steering_dead_zone)
		_steering_command = _touch_steering_value
	elif _control_type == "tilt" and _tilt_sensor_available:
		steering_input = NativeArcadeCarAssist.shape_steering_input_with_preferences(_tilt_steering_value, _steering_sensitivity, _steering_dead_zone)
		_steering_command = _tilt_steering_value
	elif absf(analog_steering) > 0.08:
		steering_input = NativeArcadeCarAssist.shape_steering_input_with_preferences(analog_steering, _steering_sensitivity, _steering_dead_zone)
		_steering_command = clampf(analog_steering, -1.0, 1.0)
	else:
		_steering_command = NativeArcadeCarAssist.ramp_digital_steering(
			_steering_command,
			digital_steering_target,
			delta,
			_steering_speed_smooth
		)
		steering_input = NativeArcadeCarAssist.shape_steering_input_with_preferences(_steering_command, _steering_sensitivity, _steering_dead_zone)

	handbrake_active = Input.is_action_pressed(&"handbrake") or _touch_pressed("handbrake")
	boost_active = (Input.is_action_pressed(&"boost") or _touch_pressed("boost")) and _throttle_command > 0.05 and _nitro > 0.02 and _engine_state == ENGINE_RUNNING


func _update_tilt_steering(delta: float) -> void:
	var gravity := Input.get_gravity()
	if gravity.length() < 0.5:
		gravity = Input.get_accelerometer()
	if gravity.length() < 0.5:
		_tilt_sensor_available = false
		_tilt_steering_value = move_toward(_tilt_steering_value, 0.0, 3.0 * maxf(delta, 0.0))
		return
	_tilt_sensor_available = true
	var roll := atan2(gravity.x, -gravity.y)
	if not _tilt_calibrated:
		_tilt_neutral_roll = roll
		_tilt_calibrated = true
		_tilt_steering_value = 0.0
		return
	var delta_roll := wrapf(roll - _tilt_neutral_roll, -PI, PI)
	# Device gravity roll decreases when the screen is tilted clockwise;
	# clockwise must mean steer-right, matching the on-screen wheel.
	var target := clampf(-sin(delta_roll) * 2.4, -1.0, 1.0)
	_tilt_steering_value = lerpf(_tilt_steering_value, target, 1.0 - exp(-18.0 * maxf(delta, 0.0)))


func _physics_process(delta: float) -> void:
	_update_engine_state(delta)
	_read_inputs(delta)
	if Input.is_action_just_pressed(&"reset_car"):
		reset_requested.emit()

	_forward_speed = linear_velocity.dot(-global_transform.basis.z)
	_lateral_speed = linear_velocity.dot(global_transform.basis.x)

	# Touch/keyboard pedals are digital, but a real throttle/brake actuator
	# is not instantaneous.  Ramp the effective pedal instead of jumping
	# 0 -> 100% in one 60 Hz physics tick; braking still applies almost
	# twice as quickly as the throttle.  A filtered copy of forward speed
	# also keeps tiny RigidBody velocity noise out of RPM/gear decisions.
	var pedal_rate := 11.0 if _throttle_command < throttle_input else 5.4
	throttle_input = lerpf(throttle_input, _throttle_command, 1.0 - exp(-pedal_rate * delta))
	if absf(throttle_input - _throttle_command) < 0.002:
		throttle_input = _throttle_command
	_drivetrain_forward_speed = lerpf(_drivetrain_forward_speed, _forward_speed, 1.0 - exp(-10.0 * delta))

	# 0.2.31 precision steering: filter the speed used for the speed-
	# sensitive lock, then drive a rate-limited rack.  Initial response
	# is immediate, small corrections settle without overshoot, and
	# centre/counter-steer are deliberately faster than turn-in.  The
	# visual wheel angle is smoothed separately at render rate below.
	_steering_speed_smooth = lerpf(_steering_speed_smooth, _forward_speed, 1.0 - exp(-9.0 * delta))
	_filtered_yaw_rate = lerpf(_filtered_yaw_rate, angular_velocity.y, 1.0 - exp(-22.0 * delta))
	var desired_steer_limit := NativeArcadeCarAssist.steering_limit(_steering_speed_smooth)
	_steering_limit_smooth = lerpf(_steering_limit_smooth, desired_steer_limit, 1.0 - exp(-5.5 * delta))
	var steering_target := -steering_input * _steering_limit_smooth
	steering_angle = NativeArcadeCarAssist.responsive_steering(
		steering_angle,
		steering_target,
		delta,
		_steering_speed_smooth
	)
	if absf(steering_input) < 0.001 and absf(steering_angle) < 0.0008:
		steering_angle = 0.0

	if boost_active:
		_nitro = maxf(_nitro - delta * 0.42, 0.0)
	else:
		_nitro = minf(_nitro + delta * (0.16 if is_drifting() else 0.055), 1.0)

	_brake_light_active = handbrake_active or (throttle_input < -0.03 and _forward_speed > 0.45)
	_update_drivetrain(delta)
	_apply_suspension_and_tyres(delta)
	_apply_aerodynamics()
	_update_flip_recovery(delta)
	_update_safe_transform(delta)


func _engine_torque_curve(rpm: float) -> float:
	# Per-car normalized curve from NativeCarCatalog, scaled by that
	# car's real peak torque (Shelby 569 Nm @ 3200, LT1 617 @ 4400,
	# M117 455 @ 3750, R8 V10 560 @ 6500).
	var points := _torque_curve_points
	var tuning_multiplier := TUNING_TORQUE_MULTIPLIERS[_tuning_level]
	if points.is_empty():
		return float(_spec_torque_nm) * tuning_multiplier
	if rpm <= points[0].x:
		return float(_spec_torque_nm) * tuning_multiplier * points[0].y
	for i in range(1, points.size()):
		if rpm <= points[i].x:
			var t := (rpm - points[i - 1].x) / maxf(points[i].x - points[i - 1].x, 1.0)
			return float(_spec_torque_nm) * tuning_multiplier * lerpf(points[i - 1].y, points[i].y, t)
	return float(_spec_torque_nm) * tuning_multiplier * points[points.size() - 1].y

func _pacejka(slip: float, stiffness: float, shape: float, curvature: float) -> float:
	var bx := stiffness * slip
	return sin(shape * atan(bx - curvature * (bx - atan(bx))))


func _ackermann_angle(side: int) -> float:
	return _ackermann_angle_for(steering_angle, side)


func _ackermann_angle_for(angle: float, side: int) -> float:
	if absf(angle) < 0.0005:
		return 0.0
	var turn_radius := _wheelbase / tan(absf(angle))
	var is_inner := (angle > 0.0 and side < 0) or (angle < 0.0 and side > 0)
	var denominator := maxf(turn_radius + (-_front_track * 0.5 if is_inner else _front_track * 0.5), 0.25)
	return signf(angle) * atan(_wheelbase / denominator)


func _coupled_rpm_for_gear(speed_ms: float, gear_index: int) -> float:
	if _gear_ratios.is_empty():
		return _idle_rpm
	var safe_gear := clampi(gear_index, 0, _gear_ratios.size() - 1)
	return absf(speed_ms) / maxf(_wheel_radius, 0.01) * 60.0 / TAU * float(_gear_ratios[safe_gear]) * _final_drive


func _desired_automatic_gear_for_speed(speed_ms: float, current_gear: int) -> int:
	if _gear_ratios.is_empty():
		return 0
	var desired := clampi(current_gear, 0, _gear_ratios.size() - 1)
	var minimum_next_gear_rpm := maxf(_idle_rpm + 250.0, _shift_down_rpm * 0.82)
	while desired < _gear_ratios.size() - 1:
		if _coupled_rpm_for_gear(speed_ms, desired) < _shift_up_rpm:
			break
		if _coupled_rpm_for_gear(speed_ms, desired + 1) < minimum_next_gear_rpm:
			break
		desired += 1
	while desired > 0:
		if _coupled_rpm_for_gear(speed_ms, desired) >= _shift_down_rpm:
			break
		if _coupled_rpm_for_gear(speed_ms, desired - 1) > _redline_rpm * 0.97:
			break
		desired -= 1
	return desired


func get_automatic_gear_for_speed(speed_ms: float, current_gear: int) -> int:
	return _desired_automatic_gear_for_speed(speed_ms, current_gear)


func _update_drivetrain(delta: float) -> void:
	if _engine_state != ENGINE_RUNNING:
		_reverse_engaged = false
		_coupled_rpm = 0.0
		_desired_automatic_gear = _current_gear
		_gear_shift_timer = 0.0
		_gear_shift_duration = 0.0
		_shift_torque_blend = 1.0
		_smoothed_drive_force_per_wheel = move_toward(_smoothed_drive_force_per_wheel, 0.0, 42000.0 * delta)
		_drive_force_per_wheel = _smoothed_drive_force_per_wheel
		_engine_brake_force_per_wheel = 0.0
		var stopped_excess := -_forward_speed if handbrake_active else 0.0
		var stopped_rate := 18.0 if absf(stopped_excess) > absf(_wheelspin_excess_speed) else 9.0
		_wheelspin_excess_speed = move_toward(_wheelspin_excess_speed, stopped_excess, stopped_rate * delta)
		_rear_slip_ratio = _wheelspin_excess_speed / maxf(absf(_forward_speed), 4.0)
		return

	if throttle_input > 0.03:
		_reverse_engaged = false
	elif throttle_input < -0.03 and _forward_speed <= 0.45:
		_reverse_engaged = true
	elif _forward_speed > 0.6:
		_reverse_engaged = false

	_gear_shift_timer = maxf(_gear_shift_timer - delta, 0.0)
	var ratio := _reverse_ratio if _reverse_engaged else _gear_ratios[_current_gear]
	_coupled_rpm = absf(_drivetrain_forward_speed) / maxf(_wheel_radius, 0.01) * 60.0 / TAU * ratio * _final_drive
	_desired_automatic_gear = _current_gear
	if not _reverse_engaged:
		_desired_automatic_gear = _desired_automatic_gear_for_speed(_drivetrain_forward_speed, _current_gear)
	var target_rpm := maxf(_coupled_rpm, _idle_rpm)
	if absf(throttle_input) > 0.03 and absf(_drivetrain_forward_speed) < 7.0:
		target_rpm = maxf(target_rpm, _idle_rpm + absf(throttle_input) * 1750.0)
	_engine_rpm = clampf(move_toward(_engine_rpm, target_rpm, 4600.0 * delta), _idle_rpm, _redline_rpm)

	# 0.2.41 automatic shift fix.  The old box looked only at the
	# heavily rate-limited display/engine RPM and also required the
	# accelerator to be above a small threshold.  Near an upshift that
	# can leave a short-geared car (notably the 560 SEL, whose first
	# gear ends at 64.7 km/h) sitting against the low gear while the
	# road-speed-coupled gearbox is already past the shift point.
	# Decide from output-shaft/road speed instead: step one gear at a
	# time towards the gear whose coupled RPM is actually viable, then
	# resynchronise engine RPM to that new gear's coupled RPM.
	if not _reverse_engaged and _gear_shift_timer <= 0.0:
		if _desired_automatic_gear > _current_gear and throttle_input > -0.03:
			_current_gear += 1
			ratio = _gear_ratios[_current_gear]
			_coupled_rpm = _coupled_rpm_for_gear(_drivetrain_forward_speed, _current_gear)
			_engine_rpm = clampf(maxf(_coupled_rpm, _idle_rpm), _idle_rpm, _redline_rpm)
			_gear_shift_timer = 0.24
			_gear_shift_duration = 0.24
		elif _desired_automatic_gear < _current_gear and absf(_forward_speed) > 3.0:
			_current_gear -= 1
			ratio = _gear_ratios[_current_gear]
			_coupled_rpm = _coupled_rpm_for_gear(_drivetrain_forward_speed, _current_gear)
			_engine_rpm = clampf(maxf(_coupled_rpm, _idle_rpm), _idle_rpm, _redline_rpm)
			_gear_shift_timer = 0.17
			_gear_shift_duration = 0.17

	var throttle_magnitude := 0.0
	if _reverse_engaged:
		throttle_magnitude = absf(minf(throttle_input, 0.0))
	elif throttle_input > 0.03:
		throttle_magnitude = throttle_input
	var torque := _engine_torque_curve(_engine_rpm) * throttle_magnitude
	if boost_active and not _reverse_engaged:
		torque *= 1.34
	_shift_torque_blend = 1.0
	if _gear_shift_timer > 0.0 and _gear_shift_duration > 0.0:
		var shift_progress := clampf(1.0 - _gear_shift_timer / _gear_shift_duration, 0.0, 1.0)
		# The previous rectangular 84% torque cut/restore felt like the whole
		# car was tugging at every gear change.  A sinusoidal dip keeps the
		# perceptible shift pause but has no force discontinuity.
		_shift_torque_blend = 1.0 - 0.58 * sin(PI * shift_progress)
		torque *= _shift_torque_blend
	elif _gear_shift_duration > 0.0:
		_gear_shift_duration = 0.0
	var total_drive_force := torque * ratio * _final_drive * DRIVETRAIN_EFFICIENCY / _wheel_radius
	var target_drive_force_per_wheel := total_drive_force / float(_driven_wheel_count) * (-1.0 if _reverse_engaged else 1.0)
	# One final 75 ms torque-actuator lag absorbs high-frequency changes
	# from the RPM target and the wheelspin estimator without making the
	# pedal feel disconnected.
	_smoothed_drive_force_per_wheel = lerpf(
		_smoothed_drive_force_per_wheel,
		target_drive_force_per_wheel,
		1.0 - exp(-13.0 * delta)
	)
	_drive_force_per_wheel = _smoothed_drive_force_per_wheel

	var engine_brake_torque := clampf((_engine_rpm - _idle_rpm) * 0.018, 0.0, 110.0)
	_engine_brake_force_per_wheel = 0.0
	if absf(throttle_input) <= 0.03 and not _reverse_engaged and absf(_forward_speed) > 0.4:
		_engine_brake_force_per_wheel = engine_brake_torque * ratio * _final_drive * DRIVETRAIN_EFFICIENCY / _wheel_radius / float(_driven_wheel_count)

	# A single limited-slip driven-axle state is enough for believable
	# launches: requested force beyond the available driven-tyre
	# friction (rear axle on RWD cars, both axles on the R8) becomes
	# wheelspin, then the longitudinal Pacejka curve and traction
	# control decide how much of it reaches the road.
	var approximate_rear_peak := mass * 9.81 * _drive_peak_load_fraction * maxf(_surface_mu, 0.05)
	var load_ratio := absf(_smoothed_drive_force_per_wheel) * float(_driven_wheel_count) / maxf(approximate_rear_peak, 1.0)
	var target_excess := clampf((load_ratio - 0.72) * 7.0, 0.0, 11.0)
	if _reverse_engaged:
		target_excess = -target_excess
	if handbrake_active:
		target_excess = -_forward_speed
	var excess_rate := 18.0 if absf(target_excess) > absf(_wheelspin_excess_speed) else 9.0
	_wheelspin_excess_speed = move_toward(_wheelspin_excess_speed, target_excess, excess_rate * delta)
	_rear_slip_ratio = _wheelspin_excess_speed / maxf(absf(_forward_speed), 4.0)


func _apply_suspension_and_tyres(delta: float) -> void:
	grounded_wheel_count = 0
	var com_global := global_transform * center_of_mass

	# First pass: sample each tyre contact patch and derive suspension
	# compression for the anti-roll bars.  Time-based (not per-tick)
	# filters keep this identical at any physics/render cadence.
	var unload_alpha := 1.0 - exp(-20.0 * maxf(delta, 0.0))
	for wheel in _wheels:
		var rays: Array = wheel.get("rays", [])
		if rays.is_empty() and wheel.get("ray") != null:
			rays = [wheel.get("ray")]
		wheel["grounded"] = false
		wheel["displacement"] = 0.0
		wheel["spring_force"] = 0.0
		wheel["slip_angle"] = 0.0
		wheel["contact_patch_samples"] = 0
		if rays.is_empty():
			wheel["filtered_displacement"] = 0.0
			wheel["filtered_spring_force"] = 0.0
			wheel["filtered_suspension_velocity"] = 0.0
			wheel["filtered_lateral_force"] = 0.0
			wheel["filtered_longitudinal_force"] = 0.0
			continue

		var weighted_displacement := 0.0
		var total_weight := 0.0
		var weighted_normal := Vector3.ZERO
		var weighted_hit := Vector3.ZERO
		var centre_hit := false
		var centre_distance := SUSPENSION_REST_LENGTH + 1.0
		var centre_hit_point := global_position
		var hit_samples := 0
		for sample_index in rays.size():
			var ray := rays[sample_index] as RayCast3D
			if ray == null:
				continue
			ray.force_raycast_update()
			if not ray.is_colliding():
				continue
			var weight := 0.5 if sample_index == 0 else 0.25
			var sample_point := ray.get_collision_point()
			var sample_distance := ray.global_position.distance_to(sample_point)
			var sample_displacement := clampf(SUSPENSION_REST_LENGTH - sample_distance, -0.08, SUSPENSION_TRAVEL)
			weighted_displacement += sample_displacement * weight
			weighted_normal += ray.get_collision_normal().normalized() * weight
			weighted_hit += sample_point * weight
			total_weight += weight
			hit_samples += 1
			if sample_index == 0:
				centre_hit = true
				centre_distance = sample_distance
				centre_hit_point = sample_point

		var displacement := clampf(weighted_displacement, 0.0, SUSPENSION_TRAVEL)
		if hit_samples == 0 or total_weight <= 0.001 or displacement <= 0.0005:
			wheel["filtered_displacement"] = lerpf(float(wheel.get("filtered_displacement", 0.0)), 0.0, unload_alpha)
			wheel["filtered_spring_force"] = lerpf(float(wheel.get("filtered_spring_force", 0.0)), 0.0, unload_alpha)
			wheel["filtered_suspension_velocity"] = lerpf(float(wheel.get("filtered_suspension_velocity", 0.0)), 0.0, unload_alpha)
			wheel["filtered_lateral_force"] = lerpf(float(wheel.get("filtered_lateral_force", 0.0)), 0.0, unload_alpha)
			wheel["filtered_longitudinal_force"] = lerpf(float(wheel.get("filtered_longitudinal_force", 0.0)), 0.0, unload_alpha)
			continue

		var ground_normal := (weighted_normal / total_weight).normalized()
		var hit_point := centre_hit_point if centre_hit else weighted_hit / total_weight
		var distance := centre_distance if centre_hit else SUSPENSION_REST_LENGTH - displacement
		# The patch average handles spatial steps; these short temporal
		# filters handle the remaining normal/load noise.  Their rates are
		# in 1/s, rather than fixed per-tick factors that change feel if
		# the physics tick rate changes.
		var previous_normal: Vector3 = wheel.get("filtered_normal", ground_normal)
		if previous_normal.length_squared() < 0.0001:
			previous_normal = ground_normal
		var filtered_normal := previous_normal.lerp(ground_normal, 1.0 - exp(-20.0 * maxf(delta, 0.0))).normalized()
		var filtered_displacement := lerpf(
			float(wheel.get("filtered_displacement", displacement)),
			displacement,
			1.0 - exp(-30.0 * maxf(delta, 0.0))
		)
		wheel["grounded"] = true
		wheel["hit_point"] = hit_point
		wheel["ground_normal"] = filtered_normal
		wheel["filtered_normal"] = filtered_normal
		wheel["distance"] = distance
		wheel["displacement"] = filtered_displacement
		wheel["filtered_displacement"] = filtered_displacement
		wheel["raw_displacement"] = displacement
		wheel["contact_patch_samples"] = hit_samples
		if _world != null:
			wheel["surface"] = _world.get_surface_at(hit_point)
		grounded_wheel_count += 1

	# Anti-roll coupling per axle.
	var axle_adjustments := {0: 0.0, 1: 0.0}
	for axle in [0, 1]:
		var left_displacement := 0.0
		var right_displacement := 0.0
		var left_grounded := false
		var right_grounded := false
		for wheel in _wheels:
			if int(wheel.get("axle", 0)) != axle or not bool(wheel.get("grounded", false)):
				continue
			if int(wheel.get("side", 0)) < 0:
				left_displacement = float(wheel.get("displacement", 0.0))
				left_grounded = true
			else:
				right_displacement = float(wheel.get("displacement", 0.0))
				right_grounded = true
		# An anti-roll bar can only couple two loaded wheels.  Treating an
		# airborne wheel as displacement 0 used to invent a large roll
		# correction on the other side whenever one ray briefly unloaded.
		if left_grounded and right_grounded:
			axle_adjustments[axle] = (left_displacement - right_displacement) * (_anti_roll_front if axle == 0 else _anti_roll_rear)

	# Second pass: spring/damper plus tyre forces at actual contacts.
	for wheel in _wheels:
		if not bool(wheel.get("grounded", false)):
			continue
		var hit_point: Vector3 = wheel.get("hit_point", global_position)
		var ground_normal: Vector3 = wheel.get("ground_normal", Vector3.UP)
		var relative_position := hit_point - com_global
		var point_velocity := linear_velocity + angular_velocity.cross(relative_position)
		var suspension_velocity := point_velocity.dot(ground_normal)
		var filtered_suspension_velocity := lerpf(
			float(wheel.get("filtered_suspension_velocity", suspension_velocity)),
			suspension_velocity,
			1.0 - exp(-34.0 * maxf(delta, 0.0))
		)
		wheel["filtered_suspension_velocity"] = filtered_suspension_velocity
		var displacement := float(wheel.get("displacement", 0.0))
		var compression_ratio := clampf(displacement / SUSPENSION_TRAVEL, 0.0, 1.0)
		var progressive_force := displacement * _spring_stiffness + compression_ratio * compression_ratio * 7200.0
		var damping := _spring_damping_compression if filtered_suspension_velocity < 0.0 else _spring_damping_rebound
		var spring_force := progressive_force - filtered_suspension_velocity * damping
		var adjustment := float(axle_adjustments.get(int(wheel.get("axle", 0)), 0.0))
		spring_force += adjustment if int(wheel.get("side", 0)) < 0 else -adjustment
		spring_force = clampf(spring_force, 0.0, _spring_force_limit)
		var previous_spring_force := float(wheel.get("filtered_spring_force", 0.0))
		if previous_spring_force > 0.01:
			spring_force = lerpf(previous_spring_force, spring_force, 1.0 - exp(-38.0 * maxf(delta, 0.0)))
			spring_force = clampf(
				spring_force,
				previous_spring_force - 180000.0 * maxf(delta, 0.0),
				previous_spring_force + 180000.0 * maxf(delta, 0.0)
			)
		wheel["filtered_spring_force"] = spring_force
		wheel["spring_force"] = spring_force
		apply_force(ground_normal * spring_force, relative_position)

		var forward := -global_transform.basis.z
		if bool(wheel.get("front", false)):
			forward = Basis(ground_normal, _ackermann_angle(int(wheel.get("side", 1)))) * forward
		forward = forward - ground_normal * forward.dot(ground_normal)
		if forward.length_squared() < 0.0001:
			forward = -global_transform.basis.z
		forward = forward.normalized()
		var right := forward.cross(ground_normal)
		if right.length_squared() < 0.0001:
			right = global_transform.basis.x
		right = right.normalized()

		var forward_velocity := point_velocity.dot(forward)
		var lateral_velocity := point_velocity.dot(right)
		var is_rear := not bool(wheel.get("front", false))
		var surface: Dictionary = wheel.get("surface", {"mu": 1.16, "rolling_resistance": 0.014})
		var surface_mu := float(surface.get("mu", 1.16))
		var load_sensitivity := clampf(1.08 - spring_force / 45000.0, 0.88, 1.08)
		var peak_force := spring_force * surface_mu * load_sensitivity * _tyre_grip_multiplier
		var grip_factor := 1.0
		if handbrake_active and is_rear:
			grip_factor = 0.22
		elif handbrake_active:
			grip_factor = 0.84

		var slip_angle := atan2(lateral_velocity, maxf(absf(forward_velocity), 2.0))
		wheel["slip_angle"] = slip_angle
		var pacejka_lateral := -_pacejka(slip_angle, 8.6, 1.34, 0.86) * peak_force * grip_factor
		var low_speed_lateral := clampf(-lateral_velocity * (mass * 0.25) * 13.0, -peak_force, peak_force)
		var lateral_blend := 0.25 + 0.75 * clampf(absf(forward_velocity) / 6.0, 0.0, 1.0)
		var lateral_force := lerpf(low_speed_lateral, pacejka_lateral, lateral_blend)

		var longitudinal_force := 0.0
		if bool(wheel.get("driven", false)):
			var requested_drive := _drive_force_per_wheel
			if absf(requested_drive) > 1.0:
				var slip_ratio := _rear_slip_ratio
				if (requested_drive < 0.0 and slip_ratio > 0.0) or (requested_drive > 0.0 and slip_ratio < 0.0):
					slip_ratio = -slip_ratio
				var traction_limit := 0.30 if boost_active else 0.19
				if handbrake_active:
					traction_limit = 10.0
				var curve_force := absf(_pacejka(maxf(absf(slip_ratio), 0.035), 13.0, 1.30, 0.90)) * peak_force
				var available_drive := minf(absf(requested_drive), maxf(curve_force, absf(requested_drive) * 0.25))
				if absf(slip_ratio) > traction_limit:
					# Traction control targets the force at the optimal
					# slip ratio instead of multiplying a huge first-gear
					# request by a tiny factor and killing the launch.
					var optimal_force := absf(_pacejka(traction_limit, 13.0, 1.30, 0.90)) * peak_force
					var recovery := clampf(traction_limit / absf(slip_ratio), 0.84, 1.0)
					available_drive = minf(available_drive, optimal_force * recovery)
				longitudinal_force += signf(requested_drive) * available_drive
			if absf(throttle_input) <= 0.03 and not _reverse_engaged:
				longitudinal_force += -signf(forward_velocity) * _engine_brake_force_per_wheel

		if throttle_input < -0.03 and _forward_speed > 0.45:
			# 64/36 front/rear brake bias.  The friction-circle clamp below
			# preserves lateral force first, which is the ABS-like part of
			# this model: steering grip is not consumed by locked brakes.
			var brake_share := 0.32 if bool(wheel.get("front", false)) else 0.18
			longitudinal_force += -signf(forward_velocity) * _brake_force * brake_share * absf(throttle_input)

		if handbrake_active and is_rear:
			longitudinal_force += clampf(-forward_velocity * 1800.0, -peak_force, peak_force)

		var rolling_coefficient := float(surface.get("rolling_resistance", 0.014))
		if absf(forward_velocity) > 0.15:
			longitudinal_force += -signf(forward_velocity) * spring_force * rolling_coefficient
		else:
			longitudinal_force += -forward_velocity * 48.0

		# Friction circle with lateral priority.
		lateral_force = clampf(lateral_force, -peak_force * grip_factor, peak_force * grip_factor)
		var available_longitudinal := sqrt(maxf(peak_force * peak_force - lateral_force * lateral_force, 0.0))
		longitudinal_force = clampf(longitudinal_force, -available_longitudinal, available_longitudinal)

		# 0.2.31 tyre relaxation: carcass force builds over roughly one
		# contact-patch-to-axle rolling distance, not in a single physics
		# tick.  This is both physically recognisable and the final guard
		# against one-tick Pacejka force steps becoming body twitches.
		var roll_speed := maxf(absf(forward_velocity), TYRE_FORCE_MIN_ROLL_SPEED)
		var lateral_alpha := 1.0 - exp(-roll_speed * maxf(delta, 0.0) / TYRE_RELAXATION_LENGTH_M)
		var longitudinal_alpha := 1.0 - exp(-roll_speed * maxf(delta, 0.0) / (TYRE_RELAXATION_LENGTH_M * 0.78))
		lateral_force = lerpf(float(wheel.get("filtered_lateral_force", lateral_force)), lateral_force, lateral_alpha)
		longitudinal_force = lerpf(float(wheel.get("filtered_longitudinal_force", longitudinal_force)), longitudinal_force, longitudinal_alpha)
		var relaxed_magnitude := Vector2(lateral_force, longitudinal_force).length()
		if relaxed_magnitude > peak_force and relaxed_magnitude > 0.001:
			var force_scale := peak_force / relaxed_magnitude
			lateral_force *= force_scale
			longitudinal_force *= force_scale
		wheel["filtered_lateral_force"] = lateral_force
		wheel["filtered_longitudinal_force"] = longitudinal_force
		# Drive ArcadeCar roll_reduction: tyre forces are applied closer to
		# the centre-of-mass height. Suspension above still acts at the real
		# contact, but lateral/longitudinal forces rock the body less.
		var tyre_force_point := NativeArcadeCarAssist.roll_reduced_force_point(relative_position, ground_normal)
		apply_force(right * lateral_force + forward * longitudinal_force, tyre_force_point)

	if grounded_wheel_count > 0:
		var mu_total := 0.0
		var surface_votes: Dictionary = {}
		for wheel in _wheels:
			if not bool(wheel.get("grounded", false)):
				continue
			var wheel_surface: Dictionary = wheel.get("surface", {})
			mu_total += float(wheel_surface.get("mu", 1.16))
			var kind := String(wheel_surface.get("kind", "asphalt"))
			surface_votes[kind] = int(surface_votes.get(kind, 0)) + 1
			if int(surface_votes.get(kind, 0)) >= int(surface_votes.get(_surface_kind, 0)):
				_surface_kind = kind
				_surface_label = String(wheel_surface.get("label", "АСФАЛЬТ"))
		_surface_mu = mu_total / float(maxi(grounded_wheel_count, 1))

		# Bicycle-model yaw damping.  It replaces the old heavy global
		# angular damping with a targeted stability torque and is mostly
		# released while handbraking or already in a controlled drift.
		if grounded_wheel_count >= 2 and absf(_steering_speed_smooth) > 3.0:
			var understeer_gradient := 0.0028
			var desired_yaw_rate := _steering_speed_smooth / _wheelbase * tan(steering_angle) / (1.0 + understeer_gradient * _steering_speed_smooth * _steering_speed_smooth)
			var grip_limited_yaw_rate := clampf(_surface_mu * 9.81 * 0.92 / maxf(absf(_steering_speed_smooth), 1.0), 0.22, 1.15)
			desired_yaw_rate = clampf(desired_yaw_rate, -grip_limited_yaw_rate, grip_limited_yaw_rate)
			var yaw_error := desired_yaw_rate - _filtered_yaw_rate
			if absf(yaw_error) <= 0.006:
				yaw_error = 0.0
			else:
				yaw_error -= signf(yaw_error) * 0.006
			var stability_strength := 900.0 if handbrake_active else (1900.0 if is_drifting() else 5200.0)
			var desired_yaw_torque := clampf(yaw_error * stability_strength, -9000.0, 9000.0)
			_yaw_stability_torque = move_toward(_yaw_stability_torque, desired_yaw_torque, 65000.0 * maxf(delta, 0.0))
			apply_torque(Vector3.UP * _yaw_stability_torque)
		else:
			_yaw_stability_torque = move_toward(_yaw_stability_torque, 0.0, 65000.0 * maxf(delta, 0.0))

	if grounded_wheel_count > 0 and absf(throttle_input) < 0.03 and not handbrake_active:
		var horizontal_velocity := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
		if horizontal_velocity.length() < 0.45:
			apply_central_force(-horizontal_velocity * mass * 5.5)


func _apply_aerodynamics() -> void:
	var velocity := linear_velocity
	var speed := velocity.length()
	if speed > 0.01:
		var drag_force := 0.5 * AIR_DENSITY * _drag_area * speed * speed
		apply_central_force(-velocity.normalized() * drag_force)
	var downforce := clampf(0.5 * AIR_DENSITY * _downforce_area * _forward_speed * _forward_speed, 0.0, 6500.0)
	if grounded_wheel_count > 0:
		var rear_bias := global_transform.basis * Vector3(0.0, 0.0, 0.32)
		apply_force(-global_transform.basis.y * downforce, rear_bias)


func _update_safe_transform(delta: float) -> void:
	_safe_transform_timer += delta
	if grounded_wheel_count >= 3 and global_transform.basis.y.dot(Vector3.UP) > 0.72 and _safe_transform_timer > 1.25:
		_last_safe_transform = global_transform
		_safe_transform_timer = 0.0


func _update_flip_recovery(delta: float) -> void:
	if global_transform.basis.y.dot(Vector3.UP) < 0.12 and linear_velocity.length() < 4.0:
		_flip_timer += delta
		if _flip_timer > 1.5:
			var forward := -global_transform.basis.z
			forward.y = 0.0
			if forward.length_squared() < 0.001:
				forward = Vector3(0.0, 0.0, -1.0)
			forward = forward.normalized()
			var yaw := atan2(-forward.x, -forward.z)
			var upright := Transform3D(Basis(Vector3.UP, yaw), global_position + Vector3.UP * 1.0)
			reset_to_transform(upright)
			_flip_timer = 0.0
	else:
		_flip_timer = 0.0


func _process(delta: float) -> void:
	# Physics-rate scalars are intentionally re-filtered at render rate
	# for wheel spin/steer visuals; gameplay forces above keep using the
	# unfiltered physics state.  This removes visible 60 Hz steps when
	# rendering and physics cadences differ, especially on phones.
	_steering_visual_angle = lerpf(_steering_visual_angle, steering_angle, 1.0 - exp(-38.0 * maxf(delta, 0.0)))
	_visual_forward_speed = lerpf(_visual_forward_speed, _forward_speed, 1.0 - exp(-32.0 * maxf(delta, 0.0)))
	_visual_wheelspin_excess = lerpf(_visual_wheelspin_excess, _wheelspin_excess_speed, 1.0 - exp(-26.0 * maxf(delta, 0.0)))
	for i in _wheel_visuals.size():
		var wheel_visual: Dictionary = _wheel_visuals[i]
		var pivot := wheel_visual.get("pivot") as Node3D
		var spin := wheel_visual.get("spin") as Node3D
		if pivot == null or spin == null:
			continue
		if i < _wheels.size():
			var base_position: Vector3 = wheel_visual.get("base_position", pivot.position)
			var displacement := float(_wheels[i].get("displacement", 0.0))
			var visual_displacement := lerpf(
				float(wheel_visual.get("visual_displacement", displacement)),
				displacement,
				1.0 - exp(-20.0 * maxf(delta, 0.0))
			)
			wheel_visual["visual_displacement"] = visual_displacement
			pivot.position = base_position + Vector3.UP * visual_displacement * 0.86
		if bool(wheel_visual.get("front", false)):
			pivot.rotation.y = float(wheel_visual.get("pivot_y", 0.0)) + _ackermann_angle_for(_steering_visual_angle, int(wheel_visual.get("side", 1)))
		var visual_speed := _visual_forward_speed
		if bool(wheel_visual.get("driven", not bool(wheel_visual.get("front", false)))):
			visual_speed += _visual_wheelspin_excess
		spin.rotation.x -= visual_speed * delta / _wheel_radius

	var smoke_intensity := 0.0
	if grounded_wheel_count >= 2:
		if is_drifting():
			smoke_intensity = maxf(smoke_intensity, clampf(get_drift_angle_degrees() / 38.0, 0.35, 1.0))
		if absf(_rear_slip_ratio) > 0.24 and absf(throttle_input) > 0.05:
			smoke_intensity = maxf(smoke_intensity, clampf(absf(_rear_slip_ratio) / 0.75, 0.30, 1.0))
		if (_surface_kind == "sand" or _surface_kind == "grass" or _surface_kind == "rock") and absf(_forward_speed) > 9.0:
			smoke_intensity = maxf(smoke_intensity, 0.42)
	var smoke_color := Color(0.72, 0.72, 0.74, 0.34)
	if _surface_kind == "sand":
		smoke_color = Color(0.78, 0.66, 0.45, 0.38)
	elif _surface_kind == "grass" or _surface_kind == "rock":
		smoke_color = Color(0.48, 0.44, 0.34, 0.36)
	for emitter in _smoke_emitters:
		emitter.emitting = smoke_intensity > 0.03
		emitter.amount_ratio = smoke_intensity
		var process := emitter.process_material as ParticleProcessMaterial
		if process != null:
			process.color = smoke_color
	for emitter in _nitro_emitters:
		emitter.emitting = boost_active
		emitter.amount_ratio = 1.0 if boost_active else 0.0
	if _contact_shadow_material != null:
		_contact_shadow_material.albedo_color.a = 0.30 if grounded_wheel_count >= 2 else 0.12
	for material in _tail_light_materials:
		material.emission_energy_multiplier = 4.6 if _brake_light_active else (1.1 if _headlights_enabled else 0.65)

	_update_vehicle_audio(delta)


func reset_to_transform(target: Transform3D) -> void:
	call_deferred("_apply_reset_transform", target)


func _apply_reset_transform(target: Transform3D) -> void:
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, target)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	global_transform = target
	reset_physics_interpolation()
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = false
	_current_gear = 0
	if _engine_state == ENGINE_RUNNING:
		_engine_rpm = _idle_rpm
	else:
		_engine_rpm = 0.0
		_engine_transition_timer = 0.0
		_engine_stop_start_rpm = 0.0
		_set_engine_state(ENGINE_OFF)
		if _vehicle_audio != null:
			_vehicle_audio.cancel_event()
			_vehicle_audio.stop_engine_loops()
	boost_active = false
	_gear_shift_timer = 0.0
	_gear_shift_duration = 0.0
	_shift_torque_blend = 1.0
	_throttle_command = 0.0
	throttle_input = 0.0
	_smoothed_drive_force_per_wheel = 0.0
	_drivetrain_forward_speed = 0.0
	_reverse_engaged = false
	_drive_force_per_wheel = 0.0
	_wheelspin_excess_speed = 0.0
	_rear_slip_ratio = 0.0
	steering_input = 0.0
	steering_angle = 0.0
	_steering_command = 0.0
	_touch_steering_value = 0.0
	_touch_steering_engaged = false
	_touch_pedal_values["accelerate"] = 0.0
	_touch_pedal_values["brake_reverse"] = 0.0
	_tilt_steering_value = 0.0
	_steering_speed_smooth = 0.0
	_steering_limit_smooth = NativeArcadeCarAssist.MAX_STEER_RAD
	_steering_visual_angle = 0.0
	_visual_forward_speed = 0.0
	_visual_wheelspin_excess = 0.0
	_filtered_yaw_rate = 0.0
	_yaw_stability_torque = 0.0
	for wheel in _wheels:
		wheel["filtered_suspension_velocity"] = 0.0
		wheel["filtered_lateral_force"] = 0.0
		wheel["filtered_longitudinal_force"] = 0.0
	_last_safe_transform = target


func get_forward_speed_ms() -> float:
	return _forward_speed


func get_lateral_speed_ms() -> float:
	return _lateral_speed


func get_steering_angle() -> float:
	return steering_angle


func get_engine_rpm() -> float:
	return _engine_rpm


func get_current_gear_index() -> int:
	return _current_gear


func get_rear_slip_ratio() -> float:
	return _rear_slip_ratio


func get_surface_kind() -> String:
	return _surface_kind


func get_surface_label() -> String:
	return _surface_label


func _accumulate_visual_aabb(node: Node, current: AABB, has_aabb: bool) -> Dictionary:
	var result := {"aabb": current, "has": has_aabb}
	if String(node.name) == "ContactShadow":
		return result
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var transformed := mesh_instance.global_transform * mesh_instance.get_aabb()
			current = transformed if not has_aabb else current.merge(transformed)
			has_aabb = true
			result = {"aabb": current, "has": has_aabb}
	for child in node.get_children():
		result = _accumulate_visual_aabb(child, result.get("aabb", current), bool(result.get("has", has_aabb)))
	return result


func get_visual_aabb_size() -> Vector3:
	if _visual_root == null:
		return Vector3.ZERO
	var result := _accumulate_visual_aabb(_visual_root, AABB(), false)
	if not bool(result.get("has", false)):
		return Vector3.ZERO
	var aabb: AABB = result.get("aabb", AABB())
	return aabb.size


func get_speed_kmh() -> float:
	return _forward_speed * 3.6


func get_absolute_speed_kmh() -> float:
	return absf(_forward_speed) * 3.6


## Catalogue figures shown in the garage.  The drivetrain values in
## NativeCarCatalog are chosen so each simulated car lands on its own
## sheet (Shelby 569 Nm/~207 km/h, R8 560 Nm/330, LT1 617/290,
## M117 455/250).
func get_spec_sheet() -> Dictionary:
	var car := _car_definition
	var pi := _tuning_performance_index(_tuning_level)
	var tuning_pis: Array[int] = []
	var tuning_classes: Array[String] = []
	for level in TUNING_TORQUE_MULTIPLIERS.size():
		var level_pi := _tuning_performance_index(level)
		tuning_pis.append(level_pi)
		tuning_classes.append(NativeCarCatalog.class_label_for_pi(level_pi))
	return {
		"car_id": _car_id,
		"name": String(car.get("name", SPEC_NAME)),
		"short_name": String(car.get("short_name", car.get("name", SPEC_NAME))),
		"year": int(car.get("year", SPEC_YEAR)),
		"year_label": String(car.get("year_label", "'67")),
		"category": String(car.get("category", "МАСЛКАР • ЗАДНИЙ ПРИВОД")),
		"engine": String(car.get("engine", SPEC_ENGINE)),
		"power_hp": int(car.get("power_hp", SPEC_POWER_HP)),
		"power_note": String(car.get("power_note", SPEC_POWER_NOTE)),
		"torque_nm": int(car.get("torque_nm", SPEC_TORQUE_NM)),
		"torque_rpm": int(car.get("torque_rpm", SPEC_TORQUE_RPM)),
		"accel_0_100_s": float(car.get("accel_0_100_s", SPEC_ACCEL_0_100_S)),
		"top_speed_kmh": int(car.get("top_speed_kmh", SPEC_TOP_SPEED_KMH)),
		"gearbox": String(car.get("gearbox", SPEC_GEARBOX)),
		"drive": String(car.get("drive", SPEC_DRIVE)),
		"drivetrain": String(car.get("drivetrain", "rwd")),
		"gears": _gear_ratios.size(),
		"mass_kg": float(car.get("mass_kg", 1450.0)),
		"length_m": float(car.get("length_m", 4.64)),
		"width_m": float(car.get("width_m", 1.84)),
		"height_m": float(car.get("height_m", 1.32)),
		"wheelbase_m": _wheelbase,
		"ratings": (car.get("ratings", {}) as Dictionary).duplicate(true),
		"performance_index": pi,
		"base_performance_index": _performance_index,
		"tuning_performance_index": tuning_pis,
		"tuning_class_labels": tuning_classes,
		"class_label": NativeCarCatalog.class_label_for_pi(pi),
		"tuning_level": _tuning_level,
		"effective_power_hp": int(round(float(_spec_power_hp) * TUNING_TORQUE_MULTIPLIERS[_tuning_level])),
		"effective_torque_nm": int(round(float(_spec_torque_nm) * TUNING_TORQUE_MULTIPLIERS[_tuning_level])),
		"steering_wheel_texture": String(car.get("steering_wheel_texture", NativeCarCatalog.COMMON_STEERING_WHEEL_TEXTURE)),
		"steering_wheel_id": String(car.get("steering_wheel_id", NativeCarCatalog.COMMON_STEERING_WHEEL_ID)),
	}


func get_nitro_ratio() -> float:
	return _nitro


func is_boosting() -> bool:
	return boost_active


func get_drift_angle_degrees() -> float:
	if absf(_forward_speed) < 0.5:
		return 0.0
	return rad_to_deg(atan2(absf(_lateral_speed), absf(_forward_speed)))


func is_drifting() -> bool:
	return grounded_wheel_count >= 2 and absf(_forward_speed) > 7.0 and get_drift_angle_degrees() > 11.0


func get_gear_label() -> String:
	if _engine_state != ENGINE_RUNNING:
		return "N"
	if _reverse_engaged or _forward_speed < -0.45:
		return "R"
	if absf(_forward_speed) < 0.25 and absf(throttle_input) < 0.03:
		return "N"
	return str(_current_gear + 1)


func get_rpm_ratio() -> float:
	if _engine_rpm <= _idle_rpm:
		return clampf(0.08 * _engine_rpm / _idle_rpm, 0.0, 0.08)
	return clampf(0.08 + 0.92 * (_engine_rpm - _idle_rpm) / maxf(_redline_rpm - _idle_rpm, 1.0), 0.08, 1.0)


func get_smoothing_state() -> Dictionary:
	return {
		"pedal_actuator_smoothing": true,
		"drive_force_smoothing": true,
		"gear_shift_torque_blend": _shift_torque_blend,
		"filtered_suspension": true,
		"anti_roll_requires_both_wheels": true,
		"physics_interpolation_vehicle": physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_ON,
		"contact_patch_samples": CONTACT_PATCH_SAMPLES,
		"tyre_relaxation": true,
		"filtered_suspension_velocity": true,
		"precision_steering_0231": true,
		"steering_command": _steering_command,
		"touch_steering_wheel_0232": true,
		"touch_steering_value": _touch_steering_value,
		"touch_steering_engaged": _touch_steering_engaged,
		"control_type": _control_type,
		"steering_sensitivity": _steering_sensitivity,
		"steering_dead_zone": _steering_dead_zone,
		"tilt_sensor_available": _tilt_sensor_available,
		"analog_touch_pedals_0233": true,
		"steering_limit_smooth": _steering_limit_smooth,
		"throttle_command": _throttle_command,
		"effective_throttle": throttle_input,
		"ignition_0235": true,
		"engine_state": _engine_state,
		"engine_running": is_engine_running(),
		"engine_rpm": _engine_rpm,
		"engine_load": get_engine_load(),
		"vehicle_audio": get_audio_state(),
	}


func get_drive_base_state() -> Dictionary:
	var state := NativeArcadeCarAssist.get_smoke_state()
	var paint_reflections_ready := false
	var paint_roughness := 1.0
	var paint_metallic := 0.0
	var paint_clearcoat := 0.0
	var paint_clearcoat_roughness := 1.0
	var paint_flake_strength := 1.0
	for paint_variant in _paint_materials.values():
		var paint := paint_variant as ShaderMaterial
		if paint == null or paint.shader != CAR_PAINT_SHADER:
			continue
		paint_roughness = minf(paint_roughness, float(paint.get_shader_parameter("roughness_amount")))
		paint_metallic = maxf(paint_metallic, float(paint.get_shader_parameter("metallic_amount")))
		paint_clearcoat = maxf(paint_clearcoat, float(paint.get_shader_parameter("clearcoat_amount")))
		paint_clearcoat_roughness = minf(paint_clearcoat_roughness, float(paint.get_shader_parameter("clearcoat_rough")))
		paint_flake_strength = minf(paint_flake_strength, float(paint.get_shader_parameter("flake_strength")))
		paint_reflections_ready = paint_roughness <= 0.24 and paint_clearcoat >= 0.9 and paint_metallic > 0.5
	var shift_speeds_kmh: Array = []
	for gear_index in _gear_ratios.size():
		var speed_ms := _shift_up_rpm * TAU * maxf(_wheel_radius, 0.01) / (60.0 * float(_gear_ratios[gear_index]) * _final_drive)
		shift_speeds_kmh.append(speed_ms * 3.6)
	state["car_paint_shader"] = CAR_PAINT_SHADER != null
	state["paint_finish_0241"] = true
	state["paint_materials"] = _paint_materials.size()
	state["paint_shader_surfaces"] = _paint_shader_surfaces
	state["secondary_paint_shader_surfaces"] = _secondary_paint_shader_surfaces
	state["gloss_trim_surfaces"] = _gloss_trim_surfaces
	state["textured_material_overrides"] = _textured_material_overrides
	state["paint_reflections_ready"] = paint_reflections_ready and _paint_shader_surfaces > 0
	state["paint_roughness"] = paint_roughness
	state["paint_metallic"] = paint_metallic
	state["paint_clearcoat"] = paint_clearcoat
	state["paint_clearcoat_roughness"] = paint_clearcoat_roughness
	state["paint_flake_strength"] = paint_flake_strength
	state["automatic_shift_0241"] = true
	state["current_gear"] = _current_gear
	state["desired_automatic_gear"] = _desired_automatic_gear
	state["coupled_rpm"] = _coupled_rpm
	state["shift_speeds_kmh"] = shift_speeds_kmh
	state["customization"] = get_customization_state()
	return state
