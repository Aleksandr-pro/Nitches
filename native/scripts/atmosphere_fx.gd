class_name NativeAtmosphereFX
extends Node3D

## Cheap near-car ambience: drifting leaves/petals, a short road dust wake,
## and camera-space shafts that sell the low sun without volumetric fog.
## All particle draw calls are unlit, shadowless and tightly budgeted on mobile.

const SHAFT_SHADER: Shader = preload("res://shaders/light_shafts.gdshader")

var _vehicle: NativeVehicle
var _camera: Camera3D
var _leaf_particles: GPUParticles3D
var _petal_particles: GPUParticles3D
var _dust_particles: GPUParticles3D
var _shaft_material: ShaderMaterial
var _mode := "day"


func configure(vehicle: NativeVehicle, camera: Camera3D) -> void:
	_vehicle = vehicle
	_camera = camera


func _ready() -> void:
	name = "AtmosphereFX"
	var mobile := OS.has_feature("android")
	_leaf_particles = _make_emitter(
		"DriftingLeaves",
		36 if mobile else 72,
		4.2,
		Vector3(12.0, 2.7, 17.0),
		Vector2(0.14, 0.42),
		Color(0.54, 0.48, 0.22, 0.78),
		0.0,
		Vector3(0.0, -0.32, 0.0)
	)
	_petal_particles = _make_emitter(
		"GoldenPetals",
		16 if mobile else 28,
		3.4,
		Vector3(10.0, 2.0, 15.0),
		Vector2(0.10, 0.22),
		Color(0.92, 0.66, 0.34, 0.72),
		0.0,
		Vector3(0.0, -0.48, 0.0)
	)
	_dust_particles = _make_emitter(
		"RoadWakeDust",
		28 if mobile else 48,
		1.55,
		Vector3(3.6, 0.18, 4.8),
		Vector2(0.12, 0.36),
		Color(0.72, 0.61, 0.43, 0.24),
		0.0,
		Vector3(0.0, 0.28, 0.0)
	)
	_dust_particles.position = Vector3(0.0, 0.13, 0.0)
	_create_light_shafts()
	set_time_mode("day")


func _make_emitter(
	node_name: String,
	particle_count: int,
	lifetime: float,
	box_extents: Vector3,
	quad_size: Vector2,
	color: Color,
	initial_speed: float,
	gravity: Vector3
) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = box_extents
	process.direction = Vector3(0.0, 0.0, 1.0)
	process.spread = 24.0
	process.initial_velocity_min = initial_speed
	process.initial_velocity_max = initial_speed * 1.8 + 0.8
	process.gravity = gravity
	process.damping_min = 0.15
	process.damping_max = 1.1
	process.scale_min = 0.62
	process.scale_max = 1.45
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.angular_velocity_min = -90.0
	process.angular_velocity_max = 90.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color.r, color.g, color.b, 0.0))
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	ramp.add_point(0.12, Color(color.r, color.g, color.b, color.a))
	ramp.add_point(0.70, Color(color.r, color.g, color.b, color.a * 0.72))
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	ramp_texture.width = 32
	process.color_ramp = ramp_texture

	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.metallic_specular = 0.0
	var quad := QuadMesh.new()
	quad.size = quad_size
	quad.material = material

	var emitter := GPUParticles3D.new()
	emitter.name = node_name
	emitter.amount = particle_count
	emitter.amount_ratio = 0.0
	emitter.lifetime = lifetime
	emitter.randomness = 0.84
	emitter.local_coords = false
	emitter.process_material = process
	emitter.draw_pass_1 = quad
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	emitter.visibility_aabb = AABB(Vector3(-22.0, -5.0, -28.0), Vector3(44.0, 12.0, 56.0))
	emitter.emitting = false
	add_child(emitter)
	return emitter


func _create_light_shafts() -> void:
	if _camera == null:
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(2.78, 1.62)
	var instance := MeshInstance3D.new()
	instance.name = "LowSunLightShafts"
	instance.mesh = quad
	instance.position = Vector3(0.0, 0.0, -1.8)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	instance.extra_cull_margin = 8.0
	_shaft_material = ShaderMaterial.new()
	_shaft_material.shader = SHAFT_SHADER
	_shaft_material.render_priority = -127
	_shaft_material.set_shader_parameter("shaft_intensity", 0.0)
	instance.material_override = _shaft_material
	_camera.add_child(instance)


func set_time_mode(mode: String) -> void:
	_mode = mode
	if _shaft_material == null:
		return
	var intensity := 0.72 if mode == "day" else (0.42 if mode == "sunset" else 0.0)
	var tint := Color(1.0, 0.84, 0.62) if mode == "day" else Color(1.0, 0.56, 0.32)
	_shaft_material.set_shader_parameter("shaft_intensity", intensity)
	_shaft_material.set_shader_parameter("shaft_tint", Vector3(tint.r, tint.g, tint.b))


func _process(_delta: float) -> void:
	if _vehicle == null:
		return
	var car_position := _vehicle.global_position
	global_position = car_position
	var velocity := Vector3(_vehicle.linear_velocity.x, 0.0, _vehicle.linear_velocity.z)
	var speed := velocity.length()
	var travel_direction := -velocity.normalized() if speed > 1.0 else _vehicle.global_transform.basis.z.normalized()
	var leaves_process := _leaf_particles.process_material as ParticleProcessMaterial
	var petals_process := _petal_particles.process_material as ParticleProcessMaterial
	if leaves_process != null:
		leaves_process.direction = travel_direction + Vector3(0.0, 0.12, 0.0)
		leaves_process.initial_velocity_min = 0.5 + speed * 0.055
		leaves_process.initial_velocity_max = 1.4 + speed * 0.085
	if petals_process != null:
		petals_process.direction = travel_direction + Vector3(0.0, 0.18, 0.0)
		petals_process.initial_velocity_min = 0.3 + speed * 0.04
		petals_process.initial_velocity_max = 1.0 + speed * 0.065
	var daylight_scale := 0.68 if _mode == "night" else 1.0
	_leaf_particles.emitting = true
	_leaf_particles.amount_ratio = daylight_scale * clampf(0.18 + speed / 115.0, 0.18, 0.66)
	_petal_particles.emitting = _mode != "night"
	_petal_particles.amount_ratio = clampf(0.08 + speed / 210.0, 0.08, 0.32) if _mode != "night" else 0.0
	var surface := _vehicle.get_surface_kind()
	var dusty_surface := surface == "sand" or surface == "grass" or surface == "rock"
	var dust_strength := clampf((speed - 5.0) / 20.0, 0.0, 0.68) if dusty_surface else clampf((speed - 38.0) / 180.0, 0.0, 0.13)
	_dust_particles.emitting = dust_strength > 0.01
	_dust_particles.amount_ratio = dust_strength
	var dust_process := _dust_particles.process_material as ParticleProcessMaterial
	if dust_process != null and speed > 0.5:
		dust_process.direction = travel_direction + Vector3(0.0, 0.08, 0.0)


func get_state() -> Dictionary:
	return {
		"ready": _leaf_particles != null and _petal_particles != null and _dust_particles != null,
		"leaves": _leaf_particles.amount if _leaf_particles != null else 0,
		"petals": _petal_particles.amount if _petal_particles != null else 0,
		"dust": _dust_particles.amount if _dust_particles != null else 0,
		"light_shafts": _shaft_material != null,
		"shaft_intensity": float(_shaft_material.get_shader_parameter("shaft_intensity")) if _shaft_material != null else 0.0,
		"mobile_particle_budget": OS.has_feature("android"),
	}
