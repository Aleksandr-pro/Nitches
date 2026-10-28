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
var _headlight_materials: Array[StandardMaterial3D] = []
var _tail_light_materials: Array[StandardMaterial3D] = []
var _smoke_emitters: Array[GPUParticles3D] = []
var _nitro_emitters: Array[GPUParticles3D] = []
var _contact_shadow_material: StandardMaterial3D
var _soft_disc_texture: Texture2D
var _engine_player: AudioStreamPlayer
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
var _steering_speed_smooth := 0.0
var _steering_limit_smooth := NativeArcadeCarAssist.MAX_STEER_RAD
var _visual_forward_speed := 0.0
var _visual_wheelspin_excess := 0.0
var _filtered_yaw_rate := 0.0
var _yaw_stability_torque := 0.0
var _current_gear := 0
var _engine_rpm := ENGINE_IDLE_RPM
var _gear_shift_timer := 0.0
var _gear_shift_duration := 0.0
var _shift_torque_blend := 1.0
var _throttle_command := 0.0
var _smoothed_drive_force_per_wheel := 0.0
var _drivetrain_forward_speed := 0.0
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


func _ready() -> void:
	name = "PlayerMustang"
	# The RigidBody is the one object the camera must follow through
	# Godot's physics interpolation; make that explicit instead of
	# relying on an inherited scene default.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	mass = 1450.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, 0.38, 0.02)
	linear_damp = 0.012
	angular_damp = 0.38
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

	_ensure_input_actions()
	_create_collision_shapes()
	_create_suspension_raycasts()
	_create_visual()
	_create_headlights()
	_create_vehicle_effects()
	_create_engine_audio()


func set_world(world: NativeWorldBuilder) -> void:
	_world = world


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
	body_shape.size = Vector3(1.84, 0.68, 4.64)
	var body_collision := CollisionShape3D.new()
	body_collision.name = "BodyCollision"
	body_collision.shape = body_shape
	# Keep the collision floor a little higher than the visual sill. At
	# maximum raycast-suspension compression the old box could intermittently
	# scrape the heightmap, adding a second, much harsher ground contact
	# on top of the tyre forces and making the body twitch under load.
	body_collision.position = Vector3(0.0, 0.62, 0.0)
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


func _paint_material(color: Color) -> ShaderMaterial:
	# Drive car_paint.gdshader: metallic flakes + clearcoat + Fresnel tint.
	# It replaces the flat StandardMaterial3D paint only on Paint surfaces.
	if _paint_materials.has(color):
		return _paint_materials[color] as ShaderMaterial
	var material := ShaderMaterial.new()
	material.shader = CAR_PAINT_SHADER
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("flake_color", color.lerp(Color(1.0, 0.86, 0.72), 0.58))
	material.set_shader_parameter("fresnel_color", color.lerp(Color(1.0, 0.28, 0.08), 0.32))
	# Automotive basecoat plus polished clear: slightly less metallic and
	# considerably smoother than the old uniform/plasticky finish. Probe/sky
	# specular carries the environment reflection in Godot's Mobile renderer.
	material.set_shader_parameter("metallic_amount", 0.68)
	material.set_shader_parameter("roughness_amount", 0.19)
	material.set_shader_parameter("clearcoat_amount", 1.0)
	material.set_shader_parameter("clearcoat_rough", 0.075)
	material.set_shader_parameter("flake_density", 180.0)
	material.set_shader_parameter("flake_strength", 0.5)
	material.set_shader_parameter("fresnel_strength", 0.24)
	_paint_materials[color] = material
	return material


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
				if material_name == "Paint":
					mesh_instance.set_surface_override_material(surface_index, _paint_material(Color(0.48, 0.025, 0.035)))
				elif material_name == "PaintSecondary":
					mesh_instance.set_surface_override_material(surface_index, _paint_material(Color(0.94, 0.36, 0.05)))
				elif lower_name.contains("glass") or lower_name.contains("window"):
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
				"side": int(definition.get("side", 1)),
				"pivot_y": pivot.rotation.y,
				"base_position": pivot.position,
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
		{"position": Vector3(-0.82, WHEEL_RADIUS, 1.43), "front": true, "side": -1},
		{"position": Vector3(0.82, WHEEL_RADIUS, 1.43), "front": true, "side": 1},
		{"position": Vector3(-0.82, WHEEL_RADIUS, -1.43), "front": false, "side": -1},
		{"position": Vector3(0.82, WHEEL_RADIUS, -1.43), "front": false, "side": 1},
	]:
		var pivot := Node3D.new()
		pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		pivot.position = definition.get("position", Vector3.ZERO)
		_visual_root.add_child(pivot)
		var spin := Node3D.new()
		spin.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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
	shadow_mesh.size = Vector2(2.28, 5.08)
	shadow_mesh.material = _contact_shadow_material
	var contact_shadow := MeshInstance3D.new()
	contact_shadow.name = "ContactShadow"
	contact_shadow.mesh = shadow_mesh
	contact_shadow.position = Vector3(0.0, 0.035, 0.0)
	contact_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	contact_shadow.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(contact_shadow)

	for x in [-0.82, 0.82]:
		_smoke_emitters.append(_make_particle_emitter(
			"RearTyreSmoke",
			Vector3(x, 0.20, 1.50),
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
	for x in [-0.56, 0.56]:
		_nitro_emitters.append(_make_particle_emitter(
			"NitroFlame",
			Vector3(x, 0.36, 2.34),
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


## 0.2.32: direct analog value from the on-screen steering wheel.
## While engaged it is the highest-priority steering source; the
## wheel keeps emitting during its spring return so the rack follows
## the visible rim all the way back to centre.
func set_touch_steering(value: float, engaged: bool) -> void:
	_touch_steering_value = clampf(value, -1.0, 1.0)
	_touch_steering_engaged = engaged
	if engaged:
		_steering_command = _touch_steering_value


func _touch_pressed(action_name: String) -> bool:
	return bool(_touch_inputs.get(action_name, false))


func _read_inputs(delta: float) -> void:
	var keyboard_throttle := Input.get_axis(&"brake_reverse", &"accelerate")
	var touch_throttle := 0.0
	if _touch_pressed("accelerate"):
		touch_throttle += 1.0
	if _touch_pressed("brake_reverse"):
		touch_throttle -= 1.0
	_throttle_command = clampf(touch_throttle if absf(touch_throttle) > 0.01 else keyboard_throttle, -1.0, 1.0)

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
	if _touch_steering_engaged:
		steering_input = NativeArcadeCarAssist.shape_steering_input(_touch_steering_value)
		_steering_command = _touch_steering_value
	elif absf(analog_steering) > 0.08:
		steering_input = NativeArcadeCarAssist.shape_steering_input(analog_steering)
		_steering_command = clampf(analog_steering, -1.0, 1.0)
	else:
		_steering_command = NativeArcadeCarAssist.ramp_digital_steering(
			_steering_command,
			digital_steering_target,
			delta,
			_steering_speed_smooth
		)
		steering_input = NativeArcadeCarAssist.shape_steering_input(_steering_command)

	handbrake_active = Input.is_action_pressed(&"handbrake") or _touch_pressed("handbrake")
	boost_active = (Input.is_action_pressed(&"boost") or _touch_pressed("boost")) and _throttle_command > 0.05 and _nitro > 0.02


func _physics_process(delta: float) -> void:
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
	# 428 big-block shape: peak 569 Nm at 3200 rpm, still 88% at the
	# 5400 rpm power peak (569*0.88 at 5400 rpm = 380 hp gross, close
	# to the 365 hp SAE gross rating once accessory losses land).
	var points: Array[Vector2] = [
		Vector2(850.0, 0.62),
		Vector2(1800.0, 0.80),
		Vector2(3200.0, 1.00),
		Vector2(4400.0, 0.97),
		Vector2(5400.0, 0.88),
		Vector2(6000.0, 0.78),
		Vector2(6400.0, 0.66),
	]
	if rpm <= points[0].x:
		return 569.0 * points[0].y
	for i in range(1, points.size()):
		if rpm <= points[i].x:
			var t := (rpm - points[i - 1].x) / maxf(points[i].x - points[i - 1].x, 1.0)
			return 569.0 * lerpf(points[i - 1].y, points[i].y, t)
	return 569.0 * points[points.size() - 1].y


func _pacejka(slip: float, stiffness: float, shape: float, curvature: float) -> float:
	var bx := stiffness * slip
	return sin(shape * atan(bx - curvature * (bx - atan(bx))))


func _ackermann_angle(side: int) -> float:
	return _ackermann_angle_for(steering_angle, side)


func _ackermann_angle_for(angle: float, side: int) -> float:
	if absf(angle) < 0.0005:
		return 0.0
	var turn_radius := WHEELBASE / tan(absf(angle))
	var is_inner := (angle > 0.0 and side < 0) or (angle < 0.0 and side > 0)
	var denominator := maxf(turn_radius + (-TRACK_WIDTH * 0.5 if is_inner else TRACK_WIDTH * 0.5), 0.25)
	return signf(angle) * atan(WHEELBASE / denominator)


func _update_drivetrain(delta: float) -> void:
	if throttle_input > 0.03:
		_reverse_engaged = false
	elif throttle_input < -0.03 and _forward_speed <= 0.45:
		_reverse_engaged = true
	elif _forward_speed > 0.6:
		_reverse_engaged = false

	_gear_shift_timer = maxf(_gear_shift_timer - delta, 0.0)
	var ratio := REVERSE_RATIO if _reverse_engaged else GEAR_RATIOS[_current_gear]
	var wheel_rpm := absf(_drivetrain_forward_speed) / WHEEL_RADIUS * 60.0 / TAU
	var coupled_rpm := wheel_rpm * ratio * FINAL_DRIVE
	var target_rpm := maxf(coupled_rpm, ENGINE_IDLE_RPM)
	if absf(throttle_input) > 0.03 and absf(_drivetrain_forward_speed) < 7.0:
		target_rpm = maxf(target_rpm, ENGINE_IDLE_RPM + absf(throttle_input) * 1750.0)
	_engine_rpm = clampf(move_toward(_engine_rpm, target_rpm, 4600.0 * delta), ENGINE_IDLE_RPM, ENGINE_REDLINE_RPM)

	if not _reverse_engaged and _gear_shift_timer <= 0.0:
		if throttle_input > 0.04 and _engine_rpm > 5950.0 and _current_gear < GEAR_RATIOS.size() - 1:
			var old_ratio := GEAR_RATIOS[_current_gear]
			_current_gear += 1
			ratio = GEAR_RATIOS[_current_gear]
			_engine_rpm *= ratio / old_ratio
			_gear_shift_timer = 0.24
			_gear_shift_duration = 0.24
		elif _current_gear > 0 and _engine_rpm < 2050.0 and absf(_forward_speed) > 3.0:
			var old_ratio_down := GEAR_RATIOS[_current_gear]
			_current_gear -= 1
			ratio = GEAR_RATIOS[_current_gear]
			_engine_rpm *= ratio / old_ratio_down
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
	var total_drive_force := torque * ratio * FINAL_DRIVE * DRIVETRAIN_EFFICIENCY / WHEEL_RADIUS
	var target_drive_force_per_wheel := total_drive_force * 0.5 * (-1.0 if _reverse_engaged else 1.0)
	# One final 75 ms torque-actuator lag absorbs high-frequency changes
	# from the RPM target and the wheelspin estimator without making the
	# pedal feel disconnected.
	_smoothed_drive_force_per_wheel = lerpf(
		_smoothed_drive_force_per_wheel,
		target_drive_force_per_wheel,
		1.0 - exp(-13.0 * delta)
	)
	_drive_force_per_wheel = _smoothed_drive_force_per_wheel

	var engine_brake_torque := clampf((_engine_rpm - ENGINE_IDLE_RPM) * 0.018, 0.0, 110.0)
	_engine_brake_force_per_wheel = 0.0
	if absf(throttle_input) <= 0.03 and not _reverse_engaged and absf(_forward_speed) > 0.4:
		_engine_brake_force_per_wheel = engine_brake_torque * ratio * FINAL_DRIVE * DRIVETRAIN_EFFICIENCY / WHEEL_RADIUS * 0.5

	# A single limited-slip rear axle state is enough for believable
	# launches: requested force beyond the available rear-axle friction
	# becomes wheelspin, then the longitudinal Pacejka curve and traction
	# control decide how much of it reaches the road.
	var approximate_rear_peak := mass * 9.81 * 0.47 * maxf(_surface_mu, 0.05)
	var load_ratio := absf(_smoothed_drive_force_per_wheel) * 2.0 / maxf(approximate_rear_peak, 1.0)
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
			axle_adjustments[axle] = (left_displacement - right_displacement) * (ANTI_ROLL_FRONT if axle == 0 else ANTI_ROLL_REAR)

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
		var progressive_force := displacement * SPRING_STIFFNESS + compression_ratio * compression_ratio * 7200.0
		var damping := SPRING_DAMPING_COMPRESSION if filtered_suspension_velocity < 0.0 else SPRING_DAMPING_REBOUND
		var spring_force := progressive_force - filtered_suspension_velocity * damping
		var adjustment := float(axle_adjustments.get(int(wheel.get("axle", 0)), 0.0))
		spring_force += adjustment if int(wheel.get("side", 0)) < 0 else -adjustment
		spring_force = clampf(spring_force, 0.0, 26500.0)
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
		var peak_force := spring_force * surface_mu * load_sensitivity
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
			longitudinal_force += -signf(forward_velocity) * 21500.0 * brake_share * absf(throttle_input)

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
			var desired_yaw_rate := _steering_speed_smooth / WHEELBASE * tan(steering_angle) / (1.0 + understeer_gradient * _steering_speed_smooth * _steering_speed_smooth)
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
		var drag_force := 0.5 * AIR_DENSITY * DRAG_AREA * speed * speed
		apply_central_force(-velocity.normalized() * drag_force)
	var downforce := clampf(0.5 * AIR_DENSITY * DOWNFORCE_AREA * _forward_speed * _forward_speed, 0.0, 6500.0)
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
		if not bool(wheel_visual.get("front", false)):
			visual_speed += _visual_wheelspin_excess
		spin.rotation.x -= visual_speed * delta / WHEEL_RADIUS

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
	reset_physics_interpolation()
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = false
	_current_gear = 0
	_engine_rpm = ENGINE_IDLE_RPM
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


## Owner-supplied Shelby GT500 figures shown in the garage.  The
## drivetrain constants above are tuned so the simulated car lands on
## the same numbers (569 Nm peak, gearing-limited ~207 km/h).
func get_spec_sheet() -> Dictionary:
	return {
		"name": SPEC_NAME,
		"year": SPEC_YEAR,
		"engine": SPEC_ENGINE,
		"power_hp": SPEC_POWER_HP,
		"power_note": SPEC_POWER_NOTE,
		"torque_nm": SPEC_TORQUE_NM,
		"torque_rpm": SPEC_TORQUE_RPM,
		"accel_0_100_s": SPEC_ACCEL_0_100_S,
		"top_speed_kmh": SPEC_TOP_SPEED_KMH,
		"gearbox": SPEC_GEARBOX,
		"drive": SPEC_DRIVE,
		"gears": GEAR_RATIOS.size(),
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
	if _reverse_engaged or _forward_speed < -0.45:
		return "R"
	if absf(_forward_speed) < 0.25 and absf(throttle_input) < 0.03:
		return "N"
	return str(_current_gear + 1)


func get_rpm_ratio() -> float:
	return clampf((_engine_rpm - ENGINE_IDLE_RPM) / maxf(ENGINE_REDLINE_RPM - ENGINE_IDLE_RPM, 1.0), 0.08, 1.0)


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
		"steering_limit_smooth": _steering_limit_smooth,
		"throttle_command": _throttle_command,
		"effective_throttle": throttle_input,
	}


func get_drive_base_state() -> Dictionary:
	var state := NativeArcadeCarAssist.get_smoke_state()
	var paint_reflections_ready := false
	var paint_roughness := 1.0
	var paint_clearcoat := 0.0
	for paint_variant in _paint_materials.values():
		var paint := paint_variant as ShaderMaterial
		if paint == null or paint.shader != CAR_PAINT_SHADER:
			continue
		paint_roughness = minf(paint_roughness, float(paint.get_shader_parameter("roughness_amount")))
		paint_clearcoat = maxf(paint_clearcoat, float(paint.get_shader_parameter("clearcoat_amount")))
		paint_reflections_ready = paint_roughness <= 0.24 and paint_clearcoat >= 0.9 and float(paint.get_shader_parameter("metallic_amount")) > 0.5
	state["car_paint_shader"] = CAR_PAINT_SHADER != null
	state["paint_materials"] = _paint_materials.size()
	state["paint_reflections_ready"] = paint_reflections_ready
	state["paint_roughness"] = paint_roughness
	state["paint_clearcoat"] = paint_clearcoat
	return state
