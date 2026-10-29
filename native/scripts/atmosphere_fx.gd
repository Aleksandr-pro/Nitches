class_name NativeAtmosphereFX
extends Node3D

## Low-cost near-car ambience: movement-swept leaves/petals/dust, foliage-aware
## camera-space sun shafts, and subtle headlamp lens ghosts for sunset/night.
## All particle draw calls are unlit, shadowless and tightly budgeted on mobile.

const SHAFT_SHADER: Shader = preload("res://shaders/light_shafts.gdshader")
const BOKEH_SIZE := 128

var _vehicle: NativeVehicle
var _camera: Camera3D
var _world: NativeWorldBuilder
var _leaf_particles: GPUParticles3D
var _petal_particles: GPUParticles3D
var _dust_particles: GPUParticles3D
var _shaft_material: ShaderMaterial
var _bokeh_layer: CanvasLayer
var _bokeh_texture: ImageTexture
var _bokeh_items: Array[Dictionary] = []
var _mode := "day"
var _active := false
var _headlights_enabled := false
var _foliage_density := 0.0
var _foliage_update_timer := 0.0


func configure(vehicle: NativeVehicle, camera: Camera3D, world: NativeWorldBuilder) -> void:
	_vehicle = vehicle
	_camera = camera
	_world = world


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
	_create_headlight_bokeh()
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


func _create_headlight_bokeh() -> void:
	var image := Image.create(BOKEH_SIZE, BOKEH_SIZE, false, Image.FORMAT_RGBA8)
	var centre := float(BOKEH_SIZE - 1) * 0.5
	for y in BOKEH_SIZE:
		for x in BOKEH_SIZE:
			var dx := (float(x) - centre) / centre
			var dy := (float(y) - centre) / centre
			var radius := sqrt(dx * dx + dy * dy)
			var halo := exp(-pow((radius - 0.58) / 0.105, 2.0)) * 0.20
			var core := exp(-radius * radius * 15.0) * 0.64
			var cross := (exp(-abs(dx) * 78.0) * exp(-abs(dy) * 5.0)
				+ exp(-abs(dy) * 78.0) * exp(-abs(dx) * 5.0)) * 0.10
			var alpha := clampf(halo + core + cross, 0.0, 0.92)
			image.set_pixel(x, y, Color(1.0, 0.82, 0.56, alpha))
	_bokeh_texture = ImageTexture.create_from_image(image)
	_bokeh_layer = CanvasLayer.new()
	_bokeh_layer.name = "HeadlightBokehLayer"
	_bokeh_layer.layer = 8
	add_child(_bokeh_layer)
	for source_index in 2:
		for ghost in [false, true]:
			var rect := TextureRect.new()
			rect.name = ("HeadlampGhost%d" % source_index) if ghost else ("HeadlampGlint%d" % source_index)
			rect.texture = _bokeh_texture
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_SCALE
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rect.modulate = Color(1.0, 0.82, 0.58, 0.0)
			_bokeh_layer.add_child(rect)
			_bokeh_items.append({"rect": rect, "source": source_index, "ghost": ghost})


func set_time_mode(mode: String) -> void:
	_mode = mode
	if _shaft_material != null:
		var intensity := 0.72 if mode == "day" else (0.42 if mode == "sunset" else 0.0)
		var tint := Color(1.0, 0.84, 0.62) if mode == "day" else Color(1.0, 0.56, 0.32)
		_shaft_material.set_shader_parameter("shaft_tint", Vector3(tint.r, tint.g, tint.b))
		var foliage_gate := smoothstep(0.04, 0.52, _foliage_density)
		_shaft_material.set_shader_parameter("shaft_intensity", intensity * foliage_gate if _active else 0.0)


func set_headlights_enabled(enabled: bool) -> void:
	_headlights_enabled = enabled


func set_active(active: bool) -> void:
	_active = active
	if not active:
		if _leaf_particles != null:
			_leaf_particles.emitting = false
		if _petal_particles != null:
			_petal_particles.emitting = false
		if _dust_particles != null:
			_dust_particles.emitting = false
		if _shaft_material != null:
			_shaft_material.set_shader_parameter("shaft_intensity", 0.0)
		for item in _bokeh_items:
			var rect := item.get("rect") as TextureRect
			if rect != null:
				rect.modulate.a = 0.0


func _update_foliage_shafts(delta: float) -> void:
	_foliage_update_timer -= delta
	if _foliage_update_timer <= 0.0 and _world != null and _vehicle != null:
		_foliage_density = _world.get_foliage_density_at(_vehicle.global_position, 110.0)
		_foliage_update_timer = 0.28
	if _shaft_material == null:
		return
	var mode_intensity := 0.72 if _mode == "day" else (0.42 if _mode == "sunset" else 0.0)
	var foliage_gate := smoothstep(0.04, 0.52, _foliage_density)
	_shaft_material.set_shader_parameter("shaft_intensity", mode_intensity * foliage_gate)


func _update_headlight_bokeh() -> void:
	if _camera == null or _vehicle == null or _bokeh_items.is_empty():
		return
	var viewport := _camera.get_viewport()
	if viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	var screen_centre := viewport_size * 0.5
	var flare_mode := _mode != "day" and _headlights_enabled
	var lens_positions := _vehicle.get_headlight_world_positions()
	if lens_positions.size() < 2:
		return
	for item in _bokeh_items:
		var rect := item.get("rect") as TextureRect
		if rect == null:
			continue
		var source_index := int(item.get("source", 0))
		var ghost := bool(item.get("ghost", false))
		var world_position: Vector3 = lens_positions[source_index]
		if not flare_mode or _camera.is_position_behind(world_position):
			rect.modulate.a = 0.0
			continue
		var source_screen := _camera.unproject_position(world_position)
		if source_screen.x < -30.0 or source_screen.y < -30.0 or source_screen.x > viewport_size.x + 30.0 or source_screen.y > viewport_size.y + 30.0:
			rect.modulate.a = 0.0
			continue
		var flare_position := screen_centre + (screen_centre - source_screen) * 0.38 if ghost else source_screen
		var flare_size := Vector2(124.0, 124.0) if ghost else Vector2(76.0, 76.0)
		rect.position = flare_position - flare_size * 0.5
		rect.size = flare_size
		rect.modulate.a = 0.11 if ghost else (0.24 if _mode == "sunset" else 0.32)


func _process(delta: float) -> void:
	if _vehicle == null:
		return
	if not _active:
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
	_update_foliage_shafts(delta)
	_update_headlight_bokeh()


func get_state() -> Dictionary:
	return {
		"ready": _leaf_particles != null and _petal_particles != null and _dust_particles != null,
		"leaves": _leaf_particles.amount if _leaf_particles != null else 0,
		"petals": _petal_particles.amount if _petal_particles != null else 0,
		"dust": _dust_particles.amount if _dust_particles != null else 0,
		"light_shafts": _shaft_material != null,
		"active": _active,
		"shaft_intensity": float(_shaft_material.get_shader_parameter("shaft_intensity")) if _shaft_material != null else 0.0,
		"foliage_density": _foliage_density,
		"headlight_bokeh": _bokeh_texture != null,
		"headlight_glints_enabled": _headlights_enabled and _mode != "day",
		"mobile_particle_budget": OS.has_feature("android"),
	}
