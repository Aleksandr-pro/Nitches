class_name NativeMinimap
extends Control

## Compact real-metre RichTown minimap rendered directly by Godot CanvasItem
## drawing calls.  North (minimum Z) is at the top, matching the world data
## coordinates used by the native scene.

var _world: NativeWorldBuilder
var _vehicle: NativeVehicle
var _data: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(184.0, 190.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func bind(world: NativeWorldBuilder, vehicle: NativeVehicle) -> void:
	_world = world
	_vehicle = vehicle
	if _world != null:
		_data = _world.get_world_data()
	queue_redraw()


func refresh() -> void:
	queue_redraw()


func has_data() -> bool:
	return not _data.is_empty()


func get_feature_counts() -> Dictionary:
	return {
		"roads": (_data.get("roads", []) as Array).size(),
		"buildings": (_data.get("buildings", []) as Array).size(),
		"landmarks": (_data.get("landmarks", []) as Array).size(),
		"parks": _world.get_park_rects().size() if _world != null else 0,
	}


func _bounds() -> Dictionary:
	return _data.get("bounds", {"minX": 520.0, "maxX": 1500.0, "minZ": -500.0, "maxZ": 500.0})


func _map_point(x: float, z: float) -> Vector2:
	var bounds := _bounds()
	var min_x := float(bounds.get("minX", 520.0))
	var max_x := float(bounds.get("maxX", 1500.0))
	var min_z := float(bounds.get("minZ", -500.0))
	var max_z := float(bounds.get("maxZ", 500.0))
	var usable := size - Vector2(12.0, 12.0)
	var nx := clampf((x - min_x) / maxf(max_x - min_x, 1.0), 0.0, 1.0)
	var nz := clampf((z - min_z) / maxf(max_z - min_z, 1.0), 0.0, 1.0)
	return Vector2(6.0 + nx * usable.x, 6.0 + (1.0 - nz) * usable.y)


func _draw_zone(zone_name: String, color: Color) -> void:
	var zones: Dictionary = _data.get("zones", {})
	var zone: Dictionary = zones.get(zone_name, {})
	if zone.is_empty():
		return
	var top_left := _map_point(float(zone.get("minX", 0.0)), float(zone.get("maxZ", 0.0)))
	var bottom_right := _map_point(float(zone.get("maxX", 0.0)), float(zone.get("minZ", 0.0)))
	draw_rect(Rect2(top_left, bottom_right - top_left), color, true)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.015, 0.045, 0.075, 0.88), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.62, 0.12, 0.70), false, 1.5)
	if _data.is_empty():
		var inset := Vector2(10.0, 10.0)
		draw_line(inset, size - inset, Color(1.0, 0.18, 0.08, 0.90), 3.0, true)
		draw_line(Vector2(size.x - inset.x, inset.y), Vector2(inset.x, size.y - inset.y), Color(1.0, 0.18, 0.08, 0.90), 3.0, true)
		return

	_draw_zone("sea", Color(0.05, 0.42, 0.66, 0.82))
	_draw_zone("marina", Color(0.08, 0.55, 0.76, 0.86))
	_draw_zone("beach", Color(0.78, 0.64, 0.38, 0.38))
	_draw_zone("palmIsland", Color(0.25, 0.58, 0.32, 0.42))
	_draw_zone("sailIsland", Color(0.25, 0.58, 0.32, 0.42))
	_draw_zone("rtPlaza", Color(0.72, 0.72, 0.70, 0.34))
	if _world != null:
		for rect_variant in _world.get_park_rects():
			var park_rect: Rect2 = rect_variant
			var park_top_left := _map_point(park_rect.position.x, park_rect.position.y + park_rect.size.y)
			var park_bottom_right := _map_point(park_rect.position.x + park_rect.size.x, park_rect.position.y)
			draw_rect(Rect2(park_top_left, park_bottom_right - park_top_left), Color(0.16, 0.62, 0.24, 0.55), true)

	for building_variant in _data.get("buildings", []):
		var building: Dictionary = building_variant
		var point := _map_point(float(building.get("x", 0.0)), float(building.get("z", 0.0)))
		var color := Color(0.78, 0.82, 0.88, 0.72)
		if String(building.get("model", "generic")) != "generic":
			color = Color(1.0, 0.68, 0.20, 0.90)
		draw_rect(Rect2(point - Vector2(1.4, 1.4), Vector2(2.8, 2.8)), color, true)

	for road_variant in _data.get("roads", []):
		var road: Dictionary = road_variant
		var samples: Array = road.get("samples", [])
		if samples.size() < 2:
			continue
		var points := PackedVector2Array()
		for sample_variant in samples:
			var sample: Array = sample_variant
			if sample.size() >= 3:
				points.append(_map_point(float(sample[0]), float(sample[2])))
		if points.size() >= 2:
			draw_polyline(points, Color(0.92, 0.94, 0.96, 0.86), 1.35, true)

	for landmark_variant in _data.get("landmarks", []):
		var landmark: Dictionary = landmark_variant
		var point := _map_point(float(landmark.get("x", 0.0)), float(landmark.get("z", 0.0)))
		draw_circle(point, 2.4, Color(1.0, 0.45, 0.12, 0.95))

	if _vehicle == null:
		return
	var player_position := _vehicle.global_position
	var player_point := _map_point(player_position.x, player_position.z)
	var forward := -_vehicle.global_transform.basis.z
	var screen_direction := Vector2(forward.x, -forward.z)
	if screen_direction.length_squared() < 0.001:
		screen_direction = Vector2.UP
	screen_direction = screen_direction.normalized()
	var right := Vector2(-screen_direction.y, screen_direction.x)
	var triangle := PackedVector2Array([
		player_point + screen_direction * 7.0,
		player_point - screen_direction * 4.5 + right * 3.4,
		player_point - screen_direction * 4.5 - right * 3.4,
	])
	draw_colored_polygon(triangle, Color(1.0, 0.48, 0.08, 1.0))
	draw_circle(player_point, 1.7, Color.WHITE)
