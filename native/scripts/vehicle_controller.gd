class_name NativeVehicle
extends RigidBody3D

## Native arcade vehicle physics.
##
## The body is a real RigidBody3D.  Four raycasts form the suspension, while
## longitudinal/lateral tyre forces are applied at each contact point.  This
## gives us collisions, slopes, roll, drift and weight transfer without a
## browser physics loop or any JavaScript bridge.

signal reset_requested

const MUSTANG_PATH := "res://assets/vehicles/mustang.glb"
const WHEEL_RADIUS := 0.3378

const SUSPENSION_REST_LENGTH := 0.72
const SUSPENSION_TRAVEL := 0.30
const SPRING_STIFFNESS := 28000.0
const SPRING_DAMPING := 2850.0
const ANTI_ROLL_STIFFNESS := 7200.0
const TYRE_MU := 1.18

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
var _headlights: Array[SpotLight3D] = []
var _engine_player: AudioStreamPlayer
var _nitro := 0.72
var _forward_speed := 0.0
var _lateral_speed := 0.0
var _flip_timer := 0.0
var _last_safe_transform := Transform3D.IDENTITY
var _safe_transform_timer := 0.0
var _steering_visual_angle := 0.0


func _ready() -> void:
	name = "PlayerMustang"
	mass = 1450.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, 0.38, 0.02)
	linear_damp = 0.035
	angular_damp = 1.25
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 10
	can_sleep = false
	collision_layer = 2
	collision_mask = 1

	var physics_material := PhysicsMaterial.new()
	physics_material.friction = 0.18
	physics_material.bounce = 0.03
	physics_material_override = physics_material

	_ensure_input_actions()
	_create_collision_shapes()
	_create_suspension_raycasts()
	_create_visual()
	_create_headlights()
	_create_engine_audio()


func _ensure_input_actions() -> void:
	_ensure_action(&"accelerate", [KEY_W, KEY_UP])
	_ensure_action(&"brake_reverse", [KEY_S, KEY_DOWN])
	_ensure_action(&"steer_left", [KEY_A, KEY_LEFT])
	_ensure_action(&"steer_right", [KEY_D, KEY_RIGHT])
	_ensure_action(&"handbrake", [KEY_SPACE])
	_ensure_action(&"boost", [KEY_SHIFT])
	_ensure_action(&"reset_car", [KEY_R])
	_ensure_action(&"camera_toggle", [KEY_C])
	_ensure_action(&"time_toggle", [KEY_T])


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
	body_shape.size = Vector3(1.84, 0.74, 4.64)
	var body_collision := CollisionShape3D.new()
	body_collision.name = "BodyCollision"
	body_collision.shape = body_shape
	body_collision.position = Vector3(0.0, 0.55, 0.0)
	add_child(body_collision)

	var cabin_shape := BoxShape3D.new()
	cabin_shape.size = Vector3(1.58, 0.54, 2.05)
	var cabin_collision := CollisionShape3D.new()
	cabin_collision.name = "CabinCollision"
	cabin_collision.shape = cabin_shape
	cabin_collision.position = Vector3(0.0, 1.03, 0.18)
	add_child(cabin_collision)


func _create_suspension_raycasts() -> void:
	var definitions: Array[Dictionary] = [
		{"name": "WheelFL", "position": Vector3(-0.82, 0.58, -1.43), "front": true, "driven": false, "side": -1, "axle": 0},
		{"name": "WheelFR", "position": Vector3(0.82, 0.58, -1.43), "front": true, "driven": false, "side": 1, "axle": 0},
		{"name": "WheelRL", "position": Vector3(-0.82, 0.58, 1.43), "front": false, "driven": true, "side": -1, "axle": 1},
		{"name": "WheelRR", "position": Vector3(0.82, 0.58, 1.43), "front": false, "driven": true, "side": 1, "axle": 1},
	]
	for definition in definitions:
		var ray := RayCast3D.new()
		ray.name = String(definition.get("name", "WheelRay"))
		ray.position = definition.get("position", Vector3.ZERO)
		ray.target_position = Vector3(0.0, -1.12, 0.0)
		ray.collision_mask = 1
		ray.enabled = true
		ray.exclude_parent = true
		add_child(ray)
		var wheel := definition.duplicate(true)
		wheel["ray"] = ray
		wheel["grounded"] = false
		wheel["displacement"] = 0.0
		_wheels.append(wheel)


func _create_visual() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	# The supplied GLB is normalised with +Z as its nose.  Godot vehicles use
	# -Z as forward, so the visual wrapper is turned around once.
	_visual_root.rotation.y = PI
	add_child(_visual_root)

	if _load_mustang_model():
		return
	_create_fallback_visual()


func _load_mustang_model() -> bool:
	if not ResourceLoader.exists(MUSTANG_PATH):
		push_warning("Mustang GLB is not staged yet; using native fallback visual")
		return false
	var packed := load(MUSTANG_PATH) as PackedScene
	if packed == null:
		push_warning("Mustang GLB could not be loaded as a PackedScene")
		return false
	var model := packed.instantiate()
	if model == null:
		return false
	model.name = "MustangModel"
	if _count_mesh_instances(model) == 0:
		push_warning("Mustang GLB contained no renderable meshes; using native fallback visual")
		model.free()
		return false
	_visual_root.add_child(model)
	_apply_model_materials(model)
	_collect_wheel_visuals(model)
	return true


func _count_mesh_instances(node: Node) -> int:
	var count := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		count += _count_mesh_instances(child)
	return count


func _paint_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.62
	material.roughness = 0.30
	material.clearcoat_enabled = true
	material.clearcoat = 1.0
	material.clearcoat_roughness = 0.08
	return material


func _apply_model_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mesh_instance.receive_shadow = true
		if mesh_instance.mesh != null:
			for surface_index in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.get_surface_override_material(surface_index)
				if material == null:
					material = mesh_instance.mesh.surface_get_material(surface_index)
				if material == null:
					continue
				var material_name := String(material.resource_name)
				var lower_name := material_name.to_lower()
				if material_name == "Paint":
					mesh_instance.set_surface_override_material(surface_index, _paint_material(Color(0.48, 0.025, 0.035)))
				elif material_name == "PaintSecondary":
					mesh_instance.set_surface_override_material(surface_index, _paint_material(Color(0.94, 0.36, 0.05)))
				elif lower_name.contains("glass") or lower_name.contains("window"):
					var glass := StandardMaterial3D.new()
					glass.albedo_color = Color(0.035, 0.075, 0.11, 0.82)
					glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					glass.metallic = 0.72
					glass.roughness = 0.07
					mesh_instance.set_surface_override_material(surface_index, glass)
	for child in node.get_children():
		_apply_model_materials(child)


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
		{"pivot": "Wheel_FL", "spin": "Wheel_FL_Spin", "front": true},
		{"pivot": "Wheel_FR", "spin": "Wheel_FR_Spin", "front": true},
		{"pivot": "Wheel_RL", "spin": "Wheel_RL_Spin", "front": false},
		{"pivot": "Wheel_RR", "spin": "Wheel_RR_Spin", "front": false},
	]:
		var pivot := _find_node_by_name(model, String(definition.get("pivot", ""))) as Node3D
		var spin := _find_node_by_name(model, String(definition.get("spin", ""))) as Node3D
		if pivot != null and spin != null:
			_wheel_visuals.append({
				"pivot": pivot,
				"spin": spin,
				"front": bool(definition.get("front", false)),
				"pivot_y": pivot.rotation.y,
			})
	if _wheel_visuals.size() != 4:
		push_warning("Mustang wheel pivots found: %d/4" % _wheel_visuals.size())


func _create_fallback_visual() -> void:
	var paint := _paint_material(Color(0.48, 0.025, 0.035))
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.025, 0.03, 0.04)
	dark.metallic = 0.45
	dark.roughness = 0.32

	_add_visual_box(Vector3(1.82, 0.46, 4.58), Vector3(0.0, 0.50, 0.0), paint, "FallbackBody")
	_add_visual_box(Vector3(1.56, 0.42, 2.05), Vector3(0.0, 0.90, -0.16), dark, "FallbackCabin")
	_add_visual_box(Vector3(1.70, 0.16, 0.55), Vector3(0.0, 0.72, 1.95), paint, "FallbackSpoiler")

	_wheel_visuals.clear()
	for definition in [
		{"position": Vector3(-0.82, WHEEL_RADIUS, 1.43), "front": true},
		{"position": Vector3(0.82, WHEEL_RADIUS, 1.43), "front": true},
		{"position": Vector3(-0.82, WHEEL_RADIUS, -1.43), "front": false},
		{"position": Vector3(0.82, WHEEL_RADIUS, -1.43), "front": false},
	]:
		var pivot := Node3D.new()
		pivot.position = definition.get("position", Vector3.ZERO)
		_visual_root.add_child(pivot)
		var spin := Node3D.new()
		pivot.add_child(spin)
		var tyre := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = WHEEL_RADIUS
		cylinder.bottom_radius = WHEEL_RADIUS
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
			"pivot_y": 0.0,
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
	instance.receive_shadow = true
	_visual_root.add_child(instance)


func _create_headlights() -> void:
	for x in [-0.62, 0.62]:
		var light := SpotLight3D.new()
		light.name = "Headlight"
		light.position = Vector3(x, 0.74, -2.22)
		light.light_color = Color(1.0, 0.92, 0.76)
		light.light_energy = 0.0
		light.spot_range = 48.0
		light.spot_angle = 27.0
		light.spot_attenuation = 1.2
		light.shadow_enabled = false
		add_child(light)
		_headlights.append(light)


func set_headlights_enabled(enabled: bool) -> void:
	for light in _headlights:
		light.light_energy = 3.6 if enabled else 0.0


func _create_engine_audio() -> void:
	var sample_rate := 22050
	var samples := PackedByteArray()
	samples.resize(sample_rate)
	for i in sample_rate:
		var phase := TAU * 55.0 * float(i) / float(sample_rate)
		var value := sin(phase) * 0.42 + sin(phase * 2.0) * 0.25 + sin(phase * 3.0) * 0.14 + signf(sin(phase)) * 0.07
		samples[i] = int(clampf(128.0 + value * 92.0, 3.0, 252.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_rate
	stream.data = samples

	_engine_player = AudioStreamPlayer.new()
	_engine_player.name = "EngineAudio"
	_engine_player.stream = stream
	_engine_player.volume_db = -24.0
	_engine_player.pitch_scale = 0.72
	add_child(_engine_player)
	_engine_player.play()


func set_touch_input(action_name: String, pressed: bool) -> void:
	_touch_inputs[action_name] = pressed


func _touch_pressed(action_name: String) -> bool:
	return bool(_touch_inputs.get(action_name, false))


func _read_inputs() -> void:
	var keyboard_throttle := Input.get_axis(&"brake_reverse", &"accelerate")
	var touch_throttle := 0.0
	if _touch_pressed("accelerate"):
		touch_throttle += 1.0
	if _touch_pressed("brake_reverse"):
		touch_throttle -= 1.0
	throttle_input = clampf(touch_throttle if absf(touch_throttle) > 0.01 else keyboard_throttle, -1.0, 1.0)

	var keyboard_steering := Input.get_axis(&"steer_left", &"steer_right")
	var touch_steering := 0.0
	if _touch_pressed("steer_left"):
		touch_steering -= 1.0
	if _touch_pressed("steer_right"):
		touch_steering += 1.0
	steering_input = clampf(touch_steering if absf(touch_steering) > 0.01 else keyboard_steering, -1.0, 1.0)

	handbrake_active = Input.is_action_pressed(&"handbrake") or _touch_pressed("handbrake")
	boost_active = (Input.is_action_pressed(&"boost") or _touch_pressed("boost")) and throttle_input > 0.05 and _nitro > 0.02


func _physics_process(delta: float) -> void:
	_read_inputs()
	if Input.is_action_just_pressed(&"reset_car"):
		reset_requested.emit()

	_forward_speed = linear_velocity.dot(-global_transform.basis.z)
	_lateral_speed = linear_velocity.dot(global_transform.basis.x)

	var speed_factor := clampf(absf(_forward_speed) / 55.0, 0.0, 1.0)
	var max_steer := lerpf(0.54, 0.15, speed_factor)
	var steering_target := -steering_input * max_steer
	var steering_rate := 5.2 if absf(steering_input) > 0.03 else 6.5
	steering_angle = move_toward(steering_angle, steering_target, steering_rate * delta)
	_steering_visual_angle = steering_angle

	if boost_active:
		_nitro = maxf(_nitro - delta * 0.42, 0.0)
	else:
		_nitro = minf(_nitro + delta * (0.16 if is_drifting() else 0.055), 1.0)

	_apply_suspension_and_tyres(delta)
	_apply_aerodynamics()
	_update_flip_recovery(delta)
	_update_safe_transform(delta)


func _apply_suspension_and_tyres(_delta: float) -> void:
	grounded_wheel_count = 0
	var com_global := global_transform * center_of_mass

	# First pass: raycast and suspension compression for anti-roll bars.
	for wheel in _wheels:
		var ray := wheel.get("ray") as RayCast3D
		wheel["grounded"] = false
		wheel["displacement"] = 0.0
		wheel["spring_force"] = 0.0
		if ray == null:
			continue
		ray.force_raycast_update()
		if not ray.is_colliding():
			continue
		var hit_point := ray.get_collision_point()
		var ground_normal := ray.get_collision_normal().normalized()
		var distance := ray.global_position.distance_to(hit_point)
		var displacement := clampf(SUSPENSION_REST_LENGTH - distance, 0.0, SUSPENSION_TRAVEL)
		if displacement <= 0.0005 and distance > SUSPENSION_REST_LENGTH:
			continue
		wheel["grounded"] = true
		wheel["hit_point"] = hit_point
		wheel["ground_normal"] = ground_normal
		wheel["distance"] = distance
		wheel["displacement"] = displacement
		grounded_wheel_count += 1

	# Anti-roll coupling per axle.
	var axle_adjustments := {0: 0.0, 1: 0.0}
	for axle in [0, 1]:
		var left_displacement := 0.0
		var right_displacement := 0.0
		for wheel in _wheels:
			if int(wheel.get("axle", 0)) != axle or not bool(wheel.get("grounded", false)):
				continue
			if int(wheel.get("side", 0)) < 0:
				left_displacement = float(wheel.get("displacement", 0.0))
			else:
				right_displacement = float(wheel.get("displacement", 0.0))
		axle_adjustments[axle] = (left_displacement - right_displacement) * ANTI_ROLL_STIFFNESS

	# Second pass: spring/damper plus tyre forces at actual contacts.
	for wheel in _wheels:
		if not bool(wheel.get("grounded", false)):
			continue
		var hit_point: Vector3 = wheel.get("hit_point", global_position)
		var ground_normal: Vector3 = wheel.get("ground_normal", Vector3.UP)
		var relative_position := hit_point - com_global
		var point_velocity := linear_velocity + angular_velocity.cross(relative_position)
		var suspension_velocity := point_velocity.dot(ground_normal)
		var displacement := float(wheel.get("displacement", 0.0))
		var spring_force := displacement * SPRING_STIFFNESS - suspension_velocity * SPRING_DAMPING
		var adjustment := float(axle_adjustments.get(int(wheel.get("axle", 0)), 0.0))
		spring_force += adjustment if int(wheel.get("side", 0)) < 0 else -adjustment
		spring_force = clampf(spring_force, 0.0, 22000.0)
		wheel["spring_force"] = spring_force
		apply_force(ground_normal * spring_force, relative_position)

		var forward := -global_transform.basis.z
		if bool(wheel.get("front", false)):
			forward = Basis(ground_normal, steering_angle) * forward
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
		var grip_factor := 1.0
		if handbrake_active and is_rear:
			grip_factor = 0.24
		elif handbrake_active:
			grip_factor = 0.82

		var max_lateral_force := spring_force * TYRE_MU * grip_factor
		var lateral_force_magnitude := clampf(-lateral_velocity * (mass * 0.25) * 15.0, -max_lateral_force, max_lateral_force)
		var tyre_force := right * lateral_force_magnitude

		var longitudinal_force := 0.0
		if throttle_input > 0.03:
			if bool(wheel.get("driven", false)):
				var taper := clampf(1.0 - absf(_forward_speed) / 68.0, 0.20, 1.0)
				var boost_multiplier := 1.55 if boost_active else 1.0
				longitudinal_force += 15800.0 * throttle_input * taper * boost_multiplier * 0.5
		elif throttle_input < -0.03:
			if _forward_speed > 0.45:
				longitudinal_force += -signf(forward_velocity) * 5600.0 * absf(throttle_input)
			elif bool(wheel.get("driven", false)):
				longitudinal_force += -7600.0 * absf(throttle_input) * 0.5
		else:
			longitudinal_force += -forward_velocity * 22.0

		if handbrake_active and is_rear:
			longitudinal_force += -signf(forward_velocity) * minf(absf(forward_velocity) * 850.0, 7200.0)

		# Rolling resistance, kept small enough for a 240 km/h arcade top end.
		longitudinal_force += -forward_velocity * 9.0
		tyre_force += forward * longitudinal_force

		var max_combined_force := spring_force * 1.58
		if tyre_force.length() > max_combined_force and tyre_force.length() > 0.001:
			tyre_force = tyre_force.normalized() * max_combined_force
		apply_force(tyre_force, relative_position)

	if grounded_wheel_count > 0 and absf(throttle_input) < 0.03 and not handbrake_active:
		var horizontal_velocity := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
		if horizontal_velocity.length() < 0.45:
			apply_central_force(-horizontal_velocity * mass * 5.5)


func _apply_aerodynamics() -> void:
	var velocity := linear_velocity
	var speed := velocity.length()
	if speed > 0.01:
		apply_central_force(-velocity.normalized() * speed * speed * 0.34)
	var downforce := clampf(_forward_speed * _forward_speed * 2.1, 0.0, 6800.0)
	if grounded_wheel_count > 0:
		apply_central_force(-global_transform.basis.y * downforce)


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
	for wheel_visual in _wheel_visuals:
		var pivot := wheel_visual.get("pivot") as Node3D
		var spin := wheel_visual.get("spin") as Node3D
		if pivot == null or spin == null:
			continue
		if bool(wheel_visual.get("front", false)):
			pivot.rotation.y = float(wheel_visual.get("pivot_y", 0.0)) + _steering_visual_angle
		spin.rotation.x -= _forward_speed * delta / WHEEL_RADIUS

	if _engine_player != null:
		var rpm := get_rpm_ratio()
		_engine_player.pitch_scale = 0.68 + rpm * 1.65
		_engine_player.volume_db = -25.0 + absf(throttle_input) * 7.0 + (4.0 if boost_active else 0.0)


func reset_to_transform(target: Transform3D) -> void:
	call_deferred("_apply_reset_transform", target)


func _apply_reset_transform(target: Transform3D) -> void:
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, target)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	global_transform = target
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = false
	_last_safe_transform = target


func get_forward_speed_ms() -> float:
	return _forward_speed


func get_speed_kmh() -> float:
	return _forward_speed * 3.6


func get_absolute_speed_kmh() -> float:
	return absf(_forward_speed) * 3.6


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
	if _forward_speed < -0.45 or (throttle_input < -0.05 and _forward_speed <= 0.45):
		return "R"
	if absf(_forward_speed) < 0.25 and absf(throttle_input) < 0.03:
		return "N"
	var speed := absf(_forward_speed)
	if speed < 13.0:
		return "1"
	if speed < 24.0:
		return "2"
	if speed < 36.0:
		return "3"
	if speed < 49.0:
		return "4"
	if speed < 62.0:
		return "5"
	return "6"


func get_rpm_ratio() -> float:
	var speed := absf(_forward_speed)
	var lower := 0.0
	var upper := 13.0
	if speed >= 62.0:
		lower = 62.0
		upper = 76.0
	elif speed >= 49.0:
		lower = 49.0
		upper = 62.0
	elif speed >= 36.0:
		lower = 36.0
		upper = 49.0
	elif speed >= 24.0:
		lower = 24.0
		upper = 36.0
	elif speed >= 13.0:
		lower = 13.0
		upper = 24.0
	var in_gear := clampf((speed - lower) / maxf(upper - lower, 0.001), 0.0, 1.0)
	var throttle_blip := absf(throttle_input) * 0.12
	return clampf(0.18 + in_gear * 0.72 + throttle_blip, 0.0, 1.0)
