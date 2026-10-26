class_name NativeTrafficManager
extends Node3D

## Lightweight native traffic for RichTown.
##
## Every traffic and parked vehicle is the player's real Mustang GLB at a
## 1.0 scale.  Moving cars are AnimatableBody3D instances following the
## centre lines already present in richtown_native.json, offset into a
## right-hand traffic lane.  They have real collision boxes, spinning
## wheels, paint variation and distance-limited headlights without paying
## the cost of dozens of full RigidBody3D vehicle simulations.

const MUSTANG_PATH := "res://assets/vehicles/mustang.glb"
const CAR_PAINT_SHADER: Shader = preload("res://shaders/car_paint.gdshader")
const WHEEL_RADIUS := 0.3378
const CAR_COLORS: Array[Color] = [
	Color(0.72, 0.74, 0.76),
	Color(0.08, 0.09, 0.11),
	Color(0.68, 0.05, 0.06),
	Color(0.04, 0.20, 0.55),
	Color(0.92, 0.92, 0.90),
	Color(0.88, 0.47, 0.06),
	Color(0.10, 0.38, 0.29),
	Color(0.34, 0.12, 0.46),
	Color(0.78, 0.64, 0.28),
	Color(0.18, 0.42, 0.65),
]

var _world: NativeWorldBuilder
var _player: NativeVehicle
var _model_scene: PackedScene
var _routes: Array[Dictionary] = []
var _moving_cars: Array[Dictionary] = []
var _parked_cars: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _headlights_enabled := false
var _contact_shadow_texture: Texture2D
var _contact_shadow_material: StandardMaterial3D
var _paint_materials: Dictionary = {}
var _glass_material: StandardMaterial3D
var _tyre_material: StandardMaterial3D
var _chrome_material: StandardMaterial3D


func initialize(world: NativeWorldBuilder, player: NativeVehicle) -> void:
	name = "Traffic"
	_world = world
	_player = player
	_rng.seed = 99173
	if not ResourceLoader.exists(MUSTANG_PATH):
		push_warning("Traffic disabled because the Mustang GLB is not staged")
		return
	_model_scene = load(MUSTANG_PATH) as PackedScene
	if _model_scene == null:
		push_warning("Traffic disabled because the Mustang GLB could not be loaded")
		return
	_build_routes()
	_spawn_moving_cars()
	_spawn_parked_cars()


func get_stats() -> Dictionary:
	return {
		"routes": _routes.size(),
		"moving": _moving_cars.size(),
		"parked": _parked_cars.size(),
		"total": _moving_cars.size() + _parked_cars.size(),
		"paint_materials": _paint_materials.size(),
	}


func set_headlights_enabled(enabled: bool) -> void:
	_headlights_enabled = enabled
	if not enabled:
		for entry in _moving_cars:
			for light_variant in entry.get("lights", []):
				(light_variant as SpotLight3D).light_energy = 0.0


func _physics_process(delta: float) -> void:
	if _moving_cars.is_empty() or _player == null:
		return
	for entry in _moving_cars:
		var route: Dictionary = _routes[int(entry.get("route_index", 0))]
		var route_length := float(route.get("length", 1.0))
		var desired_speed := float(entry.get("cruise_speed", 12.0))
		var direction_sign := int(entry.get("direction_sign", 1))

		for other in _moving_cars:
			if other == entry:
				continue
			if int(other.get("route_index", -1)) != int(entry.get("route_index", -2)):
				continue
			if int(other.get("direction_sign", 0)) != direction_sign:
				continue
			var gap := _route_gap(
				float(entry.get("distance", 0.0)),
				float(other.get("distance", 0.0)),
				route_length,
				direction_sign
			)
			if gap > 0.1 and gap < 18.0:
				var follow_factor := clampf((gap - 7.0) / 11.0, 0.0, 1.0)
				desired_speed = minf(desired_speed, float(other.get("current_speed", desired_speed)) * follow_factor)

		var car_position: Vector3 = entry.get("position", Vector3.ZERO)
		var car_direction: Vector3 = entry.get("direction", Vector3(0.0, 0.0, -1.0))
		var to_player := _player.global_position - car_position
		var ahead := to_player.dot(car_direction)
		var right := Vector3(-car_direction.z, 0.0, car_direction.x)
		var lateral := absf(to_player.dot(right))
		if ahead > -1.0 and ahead < 18.0 and lateral < 2.9:
			if ahead < 8.5:
				desired_speed = 0.0
			else:
				desired_speed = minf(desired_speed, maxf(absf(_player.get_forward_speed_ms()), 0.0))

		var current_speed := float(entry.get("current_speed", 0.0))
		var acceleration := 3.4 if desired_speed > current_speed else 8.0
		current_speed = move_toward(current_speed, desired_speed, acceleration * delta)
		entry["current_speed"] = current_speed
		entry["distance"] = fposmod(
			float(entry.get("distance", 0.0)) + float(direction_sign) * current_speed * delta,
			route_length
		)
		_place_moving_car(entry)

		for wheel_variant in entry.get("wheels", []):
			var wheel: Dictionary = wheel_variant
			var spin := wheel.get("spin") as Node3D
			if spin != null:
				spin.rotation.x -= current_speed * delta / WHEEL_RADIUS

		var light_energy := 0.0
		if _headlights_enabled and car_position.distance_squared_to(_player.global_position) < 95.0 * 95.0:
			light_energy = 2.8
		for light_variant in entry.get("lights", []):
			(light_variant as SpotLight3D).light_energy = light_energy


func _build_routes() -> void:
	_routes.clear()
	var roads_by_id: Dictionary = {}
	var world_data := _world.get_world_data() if _world != null else {}
	for road_variant in world_data.get("roads", []):
		var road: Dictionary = road_variant
		roads_by_id[String(road.get("id", ""))] = road

	_add_route(roads_by_id, ["rt-blvd-0", "rt-blvd-1", "rt-blvd-2", "rt-blvd-3", "rt-blvd-4", "rt-blvd-5"], "Boulevard", 22.0, [3.4, 7.0], 12.5, 17.5)
	_add_route(roads_by_id, ["rt-west-0", "rt-west-1", "rt-west-2", "rt-west-3", "rt-west-4", "rt-west-5"], "West", 11.0, [2.7], 9.0, 13.0)
	_add_route(roads_by_id, ["rt-east-0", "rt-east-1", "rt-east-2", "rt-east-3", "rt-east-4a", "rt-east-4b", "rt-east-5"], "Corniche", 24.0, [3.5, 7.2], 13.0, 19.0)
	_add_route(roads_by_id, ["rt-palm-1", "rt-palm-2", "rt-palm-3"], "Palm", 12.0, [3.0], 14.0, 20.0)
	_add_route(roads_by_id, ["rt-sail-road"], "Sail", 10.0, [2.6], 10.0, 14.0)
	_add_route(roads_by_id, ["rt-highway-1", "rt-highway-2"], "SouthHighway", 16.0, [3.2], 15.0, 21.0)
	_add_route(roads_by_id, ["rt-st-1w", "rt-st-1e"], "CrossNorth", 13.0, [3.0], 9.0, 13.0)
	_add_route(roads_by_id, ["rt-st-3w", "rt-st-3e"], "CrossMuseum", 13.0, [3.0], 9.0, 13.0)
	_add_route(roads_by_id, ["rt-st-4w", "rt-st-4e"], "CrossBeach", 13.0, [3.0], 9.0, 13.0)


func _add_route(
	roads_by_id: Dictionary,
	ids: Array,
	route_name: String,
	width: float,
	lanes: Array,
	min_speed: float,
	max_speed: float
) -> void:
	var points: Array[Vector3] = []
	for id_variant in ids:
		var road: Dictionary = roads_by_id.get(String(id_variant), {})
		if road.is_empty():
			continue
		for sample_variant in road.get("samples", []):
			var sample: Array = sample_variant
			if sample.size() < 3:
				continue
			var point := Vector3(float(sample[0]), float(sample[1]), float(sample[2]))
			if points.is_empty() or points[points.size() - 1].distance_squared_to(point) > 0.01:
				points.append(point)
	if points.size() < 2:
		return
	var cumulative: Array[float] = [0.0]
	for i in range(1, points.size()):
		cumulative.append(cumulative[i - 1] + points[i].distance_to(points[i - 1]))
	_routes.append({
		"name": route_name,
		"points": points,
		"cumulative": cumulative,
		"length": cumulative[cumulative.size() - 1],
		"width": width,
		"lanes": lanes,
		"min_speed": min_speed,
		"max_speed": max_speed,
	})


func _spawn_moving_cars() -> void:
	var allocations := [4, 2, 3, 2, 1, 1, 1, 1, 1]
	var car_index := 0
	for route_index in mini(allocations.size(), _routes.size()):
		var route: Dictionary = _routes[route_index]
		var count := int(allocations[route_index])
		var lanes: Array = route.get("lanes", [3.0])
		var length := float(route.get("length", 100.0))
		for local_index in count:
			var direction_sign := 1 if local_index % 2 == 0 else -1
			var lane := float(lanes[local_index % lanes.size()])
			var group_index := local_index / 2
			var group_count := maxi((count + 1) / 2, 1)
			var distance := length * (float(group_index) + 0.5) / float(group_count)
			distance += _rng.randf_range(-28.0, 28.0)
			if direction_sign < 0:
				distance = length - distance
			distance = fposmod(distance, length)
			var sample := _sample_route(route, distance, lane, direction_sign)
			if _player != null and (sample.get("position", Vector3.ZERO) as Vector3).distance_squared_to(_player.global_position) < 38.0 * 38.0:
				distance = fposmod(distance + 85.0, length)
			var created := _create_car(car_index, false)
			car_index += 1
			var entry: Dictionary = {
				"body": created.get("body"),
				"wheels": created.get("wheels", []),
				"lights": created.get("lights", []),
				"route_index": route_index,
				"distance": distance,
				"direction_sign": direction_sign,
				"lane": lane,
				"cruise_speed": _rng.randf_range(float(route.get("min_speed", 9.0)), float(route.get("max_speed", 15.0))),
				"current_speed": 0.0,
				"position": Vector3.ZERO,
				"direction": Vector3(0.0, 0.0, -1.0),
			}
			entry["current_speed"] = float(entry.get("cruise_speed", 10.0)) * 0.72
			_moving_cars.append(entry)
			_place_moving_car(entry)


func _spawn_parked_cars() -> void:
	var allocations := [5, 3, 4, 2, 0, 0, 1, 1, 2]
	var car_index := 100
	for route_index in mini(allocations.size(), _routes.size()):
		var route: Dictionary = _routes[route_index]
		var count := int(allocations[route_index])
		var length := float(route.get("length", 100.0))
		var lane := maxf(float(route.get("width", 12.0)) * 0.5 - 1.02, 2.4)
		for local_index in count:
			var direction_sign := 1 if local_index % 2 == 0 else -1
			var distance := length * (float(local_index) + 0.5) / float(maxi(count, 1))
			distance += _rng.randf_range(-18.0, 18.0)
			distance = fposmod(distance, length)
			var sample := _sample_route(route, distance, lane, direction_sign)
			var position_value: Vector3 = sample.get("position", Vector3.ZERO)
			if _player != null and position_value.distance_squared_to(_player.global_position) < 28.0 * 28.0:
				distance = fposmod(distance + 65.0, length)
				sample = _sample_route(route, distance, lane, direction_sign)
				position_value = sample.get("position", Vector3.ZERO)
			var created := _create_car(car_index, true)
			car_index += 1
			var body := created.get("body") as Node3D
			var direction: Vector3 = sample.get("direction", Vector3(0.0, 0.0, -1.0))
			var yaw := atan2(-direction.x, -direction.z)
			body.global_transform = Transform3D(Basis(Vector3.UP, yaw), position_value)
			_parked_cars.append({
				"body": body,
				"route_index": route_index,
				"distance": distance,
			})


func _create_car(index: int, parked: bool) -> Dictionary:
	var body: PhysicsBody3D
	if parked:
		body = StaticBody3D.new()
		body.name = "ParkedMustang%03d" % index
	else:
		var moving_body := AnimatableBody3D.new()
		moving_body.name = "TrafficMustang%03d" % index
		moving_body.sync_to_physics = true
		body = moving_body
	body.collision_layer = 1
	body.collision_mask = 1
	var physics_material := PhysicsMaterial.new()
	physics_material.friction = 0.35
	physics_material.bounce = 0.02
	body.physics_material_override = physics_material
	add_child(body)

	var shape := BoxShape3D.new()
	shape.size = Vector3(1.84, 1.28, 4.66)
	var collision := CollisionShape3D.new()
	collision.name = "TrafficCollision"
	collision.shape = shape
	collision.position = Vector3(0.0, 0.66, 0.0)
	body.add_child(collision)

	var visual_root := Node3D.new()
	visual_root.name = "VisualRoot"
	visual_root.rotation.y = PI
	body.add_child(visual_root)
	var model := _model_scene.instantiate()
	model.name = "MustangModel"
	visual_root.add_child(model)
	var color := CAR_COLORS[index % CAR_COLORS.size()]
	_apply_model_materials(model, color, parked)
	_add_contact_shadow(body)

	var lights: Array = []
	if not parked:
		for x in [-0.62, 0.62]:
			var light := SpotLight3D.new()
			light.name = "TrafficHeadlight"
			light.position = Vector3(x, 0.74, -2.22)
			light.light_color = Color(1.0, 0.92, 0.76)
			light.light_energy = 0.0
			light.spot_range = 42.0
			light.spot_angle = 26.0
			light.spot_attenuation = 1.25
			light.shadow_enabled = false
			body.add_child(light)
			lights.append(light)

	return {
		"body": body,
		"wheels": _collect_wheels(model),
		"lights": lights,
	}


func _place_moving_car(entry: Dictionary) -> void:
	var body := entry.get("body") as Node3D
	if body == null:
		return
	var route: Dictionary = _routes[int(entry.get("route_index", 0))]
	var sample := _sample_route(
		route,
		float(entry.get("distance", 0.0)),
		float(entry.get("lane", 3.0)),
		int(entry.get("direction_sign", 1))
	)
	var position_value: Vector3 = sample.get("position", Vector3.ZERO)
	var direction: Vector3 = sample.get("direction", Vector3(0.0, 0.0, -1.0))
	entry["position"] = position_value
	entry["direction"] = direction
	var yaw := atan2(-direction.x, -direction.z)
	body.global_transform = Transform3D(Basis(Vector3.UP, yaw), position_value)


func _sample_route(route: Dictionary, distance: float, lane_offset: float, direction_sign: int) -> Dictionary:
	var points: Array = route.get("points", [])
	var cumulative: Array = route.get("cumulative", [])
	if points.size() < 2:
		return {"position": Vector3.ZERO, "direction": Vector3(0.0, 0.0, -1.0)}
	var route_length := float(route.get("length", 1.0))
	var clamped := clampf(fposmod(distance, route_length), 0.0, route_length - 0.001)
	var segment := 0
	while segment < cumulative.size() - 2 and float(cumulative[segment + 1]) < clamped:
		segment += 1
	var a: Vector3 = points[segment]
	var b: Vector3 = points[segment + 1]
	var segment_length := maxf(float(cumulative[segment + 1]) - float(cumulative[segment]), 0.001)
	var t := clampf((clamped - float(cumulative[segment])) / segment_length, 0.0, 1.0)
	var centre := a.lerp(b, t)
	var route_direction := b - a
	route_direction.y = 0.0
	if route_direction.length_squared() < 0.0001:
		route_direction = Vector3(0.0, 0.0, -1.0)
	route_direction = route_direction.normalized()
	var travel_direction := route_direction * float(direction_sign)
	var right := Vector3(-travel_direction.z, 0.0, travel_direction.x)
	var position_value := centre + right * lane_offset + Vector3.UP * 0.10
	return {"position": position_value, "direction": travel_direction}


func _route_gap(from_distance: float, to_distance: float, route_length: float, direction_sign: int) -> float:
	if direction_sign >= 0:
		return fposmod(to_distance - from_distance, route_length)
	return fposmod(from_distance - to_distance, route_length)


func _paint_material(color: Color) -> ShaderMaterial:
	# The same Drive metallic-flake clearcoat paint as the player car,
	# cached by colour so the whole fleet shares a handful of materials.
	if _paint_materials.has(color):
		return _paint_materials[color] as ShaderMaterial
	var material := ShaderMaterial.new()
	material.shader = CAR_PAINT_SHADER
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("flake_color", color.lerp(Color(1.0, 0.86, 0.72), 0.52))
	material.set_shader_parameter("fresnel_color", color.lerp(Color(0.95, 0.42, 0.16), 0.24))
	material.set_shader_parameter("metallic_amount", 0.80)
	material.set_shader_parameter("roughness_amount", 0.31)
	material.set_shader_parameter("clearcoat_amount", 1.0)
	material.set_shader_parameter("clearcoat_rough", 0.045)
	material.set_shader_parameter("flake_density", 165.0)
	material.set_shader_parameter("flake_strength", 0.42)
	material.set_shader_parameter("fresnel_strength", 0.20)
	_paint_materials[color] = material
	return material


func _shared_material(kind: String) -> StandardMaterial3D:
	match kind:
		"glass":
			if _glass_material == null:
				_glass_material = StandardMaterial3D.new()
				_glass_material.albedo_color = Color(0.035, 0.075, 0.11, 0.78)
				_glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				_glass_material.metallic = 0.05
				_glass_material.roughness = 0.05
				_glass_material.metallic_specular = 1.0
			return _glass_material
		"tyre":
			if _tyre_material == null:
				_tyre_material = StandardMaterial3D.new()
				_tyre_material.albedo_color = Color(0.018, 0.018, 0.02)
				_tyre_material.metallic = 0.0
				_tyre_material.roughness = 0.94
			return _tyre_material
		_:
			if _chrome_material == null:
				_chrome_material = StandardMaterial3D.new()
				_chrome_material.albedo_color = Color(0.72, 0.75, 0.78)
				_chrome_material.metallic = 1.0
				_chrome_material.roughness = 0.18
			return _chrome_material


func _apply_model_materials(node: Node, color: Color, parked: bool) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if mesh_instance.mesh != null:
			var paint := _paint_material(color)
			var accent := _paint_material(color.lerp(Color(0.05, 0.05, 0.06), 0.55))
			for surface_index in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.get_surface_override_material(surface_index)
				if material == null:
					material = mesh_instance.mesh.surface_get_material(surface_index)
				if material == null:
					continue
				var material_name := String(material.resource_name)
				var lower_name := material_name.to_lower()
				if material_name == "Paint":
					mesh_instance.set_surface_override_material(surface_index, paint)
				elif material_name == "PaintSecondary":
					mesh_instance.set_surface_override_material(surface_index, accent)
				elif lower_name.contains("glass") or lower_name.contains("window"):
					mesh_instance.set_surface_override_material(surface_index, _shared_material("glass"))
				elif lower_name.contains("tyre") or lower_name.contains("tire") or lower_name.contains("rubber"):
					mesh_instance.set_surface_override_material(surface_index, _shared_material("tyre"))
				elif lower_name.contains("chrome"):
					mesh_instance.set_surface_override_material(surface_index, _shared_material("chrome"))
				elif (lower_name.contains("tail") or lower_name.contains("rearlight")) and not parked:
					var tail := StandardMaterial3D.new()
					tail.albedo_color = Color(0.38, 0.015, 0.025)
					tail.metallic = 0.05
					tail.roughness = 0.22
					tail.emission_enabled = true
					tail.emission = Color(1.0, 0.03, 0.04)
					tail.emission_energy_multiplier = 0.65
					mesh_instance.set_surface_override_material(surface_index, tail)
	for child in node.get_children():
		_apply_model_materials(child, color, parked)


func _find_node_by_name(node: Node, target_name: String) -> Node:
	if String(node.name) == target_name:
		return node
	for child in node.get_children():
		var found := _find_node_by_name(child, target_name)
		if found != null:
			return found
	return null


func _collect_wheels(model: Node) -> Array:
	var wheels: Array = []
	for wheel_name in ["Wheel_FL_Spin", "Wheel_FR_Spin", "Wheel_RL_Spin", "Wheel_RR_Spin"]:
		var spin := _find_node_by_name(model, wheel_name) as Node3D
		if spin != null:
			wheels.append({"spin": spin})
	return wheels


func _get_soft_disc_texture() -> Texture2D:
	if _contact_shadow_texture != null:
		return _contact_shadow_texture
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var nx := (float(x) / float(size - 1) - 0.5) * 2.0
			var ny := (float(y) / float(size - 1) - 0.5) * 2.0
			var radius := sqrt(nx * nx + ny * ny)
			var alpha := clampf(1.0 - smoothstep(0.48, 1.0, radius), 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_contact_shadow_texture = ImageTexture.create_from_image(image)
	return _contact_shadow_texture


func _add_contact_shadow(parent: Node3D) -> void:
	if _contact_shadow_material == null:
		_contact_shadow_material = StandardMaterial3D.new()
		_contact_shadow_material.albedo_color = Color(0.0, 0.0, 0.0, 0.34)
		_contact_shadow_material.albedo_texture = _get_soft_disc_texture()
		_contact_shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_contact_shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_contact_shadow_material.metallic_specular = 0.0
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(2.25, 5.05)
	mesh.material = _contact_shadow_material
	var instance := MeshInstance3D.new()
	instance.name = "ContactShadow"
	instance.mesh = mesh
	instance.position = Vector3(0.0, 0.035, 0.0)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(instance)
