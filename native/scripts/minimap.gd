class_name NativeMinimap
extends Control

## 0.2.33 circular heading-up minimap.  The visible disc is a
## player-centred local map rather than the whole city squeezed into
## a small rectangle.  It rotates with the car, keeps a fixed N
## marker on the rim, draws the current destination route and uses
## small category icons/colours for nearby points of interest.

const VIEW_RADIUS_M := 260.0
## 0.2.37: the road/park network never changes while driving, so it is
## rendered once into a 2048 px north-up cache (0.2.53: 1024 px
## over the 4 km desert made carriageways nearly invisible).  The per-frame draw
## then submits one textured quad under the existing circular mask
## plus the dynamic route/markers, instead of re-tessellating more
## than a thousand road samples into antialiased CanvasItem lines at
## 30 Hz.  The old vector path remains as the first-frame fallback.
const STATIC_CACHE_SIZE := 2048

var _roads: Array = []
var _trails: Array = []  # 0.3.16: off-road dune routes (RichTown 7x7)
var _parks: Array = []
var _pois: Array = []
var _world_bounds := Rect2(520.0, -500.0, 980.0, 1000.0)
var _player_position := Vector2(5.0, 640.0)
var _player_forward := Vector2(0.0, -1.0)
var _destination := Vector2.INF
var _route_points: Array[Vector2] = []
var _world: NativeWorldBuilder
var _vehicle: NativeVehicle
var _data: Dictionary = {}
var _static_cache_mode := false
var _show_vehicle_marker := false  # 0.3.28: parked-car marker while on foot
var _static_cache_viewport: SubViewport
var _static_cache_texture: Texture2D
var _static_cache_ready := false


func _ready() -> void:
    name = "Minimap"
    clip_contents = true
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _sync_circular_mask_size()


func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        _sync_circular_mask_size()


func _sync_circular_mask_size() -> void:
    if material is ShaderMaterial and size.x > 1.0 and size.y > 1.0:
        (material as ShaderMaterial).set_shader_parameter("rect_size", size)


func bind(world: NativeWorldBuilder, vehicle: NativeVehicle) -> void:
    _world = world
    _vehicle = vehicle
    if _world != null:
        _data = _world.get_world_data()
        var bounds: Dictionary = _data.get("bounds", {})
        var min_x := float(bounds.get("minX", 520.0))
        var min_z := float(bounds.get("minZ", -500.0))
        var max_x := float(bounds.get("maxX", 1500.0))
        var max_z := float(bounds.get("maxZ", 500.0))
        _trails = (_data.get("trails", []) as Array).duplicate(true)
        set_world_data(
            _data.get("roads", []),
            Rect2(min_x, min_z, max_x - min_x, max_z - min_z),
            _world.get_park_map_entries()
        )
    refresh()


func refresh() -> void:
    if _vehicle != null:
        var car_transform := _vehicle.get_global_transform_interpolated()
        set_player(car_transform.origin, -car_transform.basis.z)
    queue_redraw()


func has_data() -> bool:
    return not _data.is_empty() or not _roads.is_empty()


func get_feature_counts() -> Dictionary:
    return {
        "roads": (_data.get("roads", []) as Array).size() if not _data.is_empty() else _roads.size(),
        "buildings": (_data.get("buildings", []) as Array).size(),
        "landmarks": (_data.get("landmarks", []) as Array).size(),
        "parks": _parks.size(),
        "pois": _pois.size(),
    }


func set_world_data(roads: Array, bounds: Rect2, parks: Array = []) -> void:
    _roads = roads.duplicate(true)
    _parks = parks.duplicate(true)
    _world_bounds = bounds
    if not _static_cache_mode:
        _build_static_cache()
    queue_redraw()


func _build_static_cache() -> void:
    if _roads.is_empty() or _world_bounds.size.x <= 1.0 or _world_bounds.size.y <= 1.0:
        return
    if _static_cache_viewport != null:
        _static_cache_viewport.queue_free()
        _static_cache_viewport = null
    _static_cache_texture = null
    _static_cache_ready = false

    var viewport := SubViewport.new()
    viewport.name = "StaticMinimapCache0237"
    viewport.size = Vector2i(STATIC_CACHE_SIZE, STATIC_CACHE_SIZE)
    viewport.transparent_bg = true
    # 0.2.53: UPDATE_ONCE could bake the cache before the canvas
    # control had ever drawn (empty roads on the desert minimap).
    # Render continuously for the first frames, then freeze.
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS

    var cache_control := NativeMinimap.new()
    cache_control.name = "StaticMinimapCanvas0237"
    cache_control._static_cache_mode = true
    cache_control._roads = _roads.duplicate(true)
    cache_control._trails = _trails.duplicate(true)
    cache_control._parks = _parks.duplicate(true)
    cache_control._world_bounds = _world_bounds
    viewport.add_child(cache_control)
    cache_control.set_anchors_preset(Control.PRESET_FULL_RECT)
    cache_control.size = Vector2(float(STATIC_CACHE_SIZE), float(STATIC_CACHE_SIZE))
    add_child(viewport)
    _static_cache_viewport = viewport
    cache_control.queue_redraw()
    _mark_static_cache_ready_later(viewport)


func _mark_static_cache_ready_later(viewport: SubViewport) -> void:
    await RenderingServer.frame_post_draw
    await RenderingServer.frame_post_draw
    await RenderingServer.frame_post_draw
    if not is_instance_valid(viewport) or viewport != _static_cache_viewport:
        return
    _static_cache_texture = viewport.get_texture()
    _static_cache_ready = _static_cache_texture != null
    if _static_cache_ready:
        viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
        queue_redraw()


func set_points_of_interest(points: Array) -> void:
    _pois = points.duplicate(true)
    queue_redraw()


func set_player(world_position: Vector3, forward: Vector3) -> void:
    _player_position = Vector2(world_position.x, world_position.z)
    var flat := Vector2(forward.x, forward.z)
    if flat.length() > 0.001:
        _player_forward = flat.normalized()
    queue_redraw()


func set_vehicle_marker_visible(value: bool) -> void:
    _show_vehicle_marker = value
    queue_redraw()


func set_destination(world_position: Vector2) -> void:
    _destination = world_position
    queue_redraw()


func set_route_path(points: Array) -> void:
    _route_points.clear()
    for point_variant in points:
        _route_points.append(point_variant as Vector2)
    if not _route_points.is_empty():
        _destination = _route_points[_route_points.size() - 1]
    queue_redraw()


func clear_destination() -> void:
    _destination = Vector2.INF
    _route_points.clear()
    queue_redraw()


func get_destination() -> Vector2:
    return _destination


func get_smoke_state() -> Dictionary:
    return {
        "circular_heading_up_0233": true,
        "roads": _roads.size(),
        "parks": _parks.size(),
        "pois": _pois.size(),
        "view_radius_m": VIEW_RADIUS_M,
        "has_destination": _destination != Vector2.INF,
        "route_points": _route_points.size(),
        "road_route_0234": true,
        "static_map_cache_0237": true,
        "minimap_contrast_0253": true,
        "static_cache_always_until_ready_0253": true,
        "static_cache_created": _static_cache_viewport != null,
        "static_cache_ready": _static_cache_ready,
        "static_cache_size": STATIC_CACHE_SIZE,
        "player_position": _player_position,
        "bounds": _world_bounds,
        "rect": get_global_rect(),
    }


func _rotate_to_vehicle(delta_world: Vector2) -> Vector2:
    # Vehicle forward must always point to the top of the disc.
    # Vehicle right in world X/Z coordinates is (forward.y,-forward.x)
    # for the map convention x=east, y=south.
    var forward := _player_forward
    var right := Vector2(-forward.y, forward.x)
    return Vector2(delta_world.dot(right), -delta_world.dot(forward))


func _world_to_map(world_position: Vector2) -> Vector2:
    var centre := size * 0.5
    var radius := minf(size.x, size.y) * 0.5
    var scale := radius / VIEW_RADIUS_M
    return centre + _rotate_to_vehicle(world_position - _player_position) * scale


func _clip_radius() -> float:
    return minf(size.x, size.y) * 0.5


func _inside(point: Vector2, margin: float = 0.0) -> bool:
    return point.distance_to(size * 0.5) <= _clip_radius() - margin


func _draw_clipped_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
    var centre := size * 0.5
    var radius := _clip_radius() - 2.0
    var clipped_from := from
    var clipped_to := to
    if clipped_from.distance_to(centre) > radius:
        clipped_from = centre + (clipped_from - centre).normalized() * radius
    if clipped_to.distance_to(centre) > radius:
        clipped_to = centre + (clipped_to - centre).normalized() * radius
    # Cull route/road pieces that only touch opposite rim points after
    # this inexpensive radial clamp.
    if clipped_from.distance_to(clipped_to) < 1.0:
        return
    draw_line(clipped_from, clipped_to, color, width, true)


func _draw_rotated_rect(world_rect: Rect2, color: Color) -> void:
    var corners := PackedVector2Array()
    corners.append(_world_to_map(Vector2(world_rect.position.x, world_rect.position.y)))
    corners.append(_world_to_map(Vector2(world_rect.end.x, world_rect.position.y)))
    corners.append(_world_to_map(Vector2(world_rect.end.x, world_rect.end.y)))
    corners.append(_world_to_map(Vector2(world_rect.position.x, world_rect.end.y)))
    var centre := size * 0.5
    for i in corners.size():
        if corners[i].distance_to(centre) > _clip_radius() * 1.6:
            return
    draw_colored_polygon(corners, color)


func _static_world_to_cache(world_position: Vector2) -> Vector2:
    return Vector2(
        (world_position.x - _world_bounds.position.x) / maxf(_world_bounds.size.x, 1.0) * size.x,
        (world_position.y - _world_bounds.position.y) / maxf(_world_bounds.size.y, 1.0) * size.y
    )


func _draw_static_cache() -> void:
    if size.x < 24.0 or size.y < 24.0:
        return
    var pixels_per_meter := size.x / maxf(_world_bounds.size.x, 1.0)
    for park_data in _parks:
        if not (park_data is Dictionary):
            continue
        var rect: Rect2 = (park_data as Dictionary).get("rect", Rect2())
        if rect.size.x <= 0.0 or rect.size.y <= 0.0:
            continue
        var corners := PackedVector2Array([
            _static_world_to_cache(Vector2(rect.position.x, rect.position.y)),
            _static_world_to_cache(Vector2(rect.end.x, rect.position.y)),
            _static_world_to_cache(Vector2(rect.end.x, rect.end.y)),
            _static_world_to_cache(Vector2(rect.position.x, rect.end.y)),
        ])
        draw_colored_polygon(corners, Color(0.08, 0.42, 0.18, 0.68))

    for road in _roads:
        if not (road is Dictionary):
            continue
        var road_data := road as Dictionary
        var samples: Array = road_data.get("samples", [])
        if samples.size() < 2:
            continue
        var points := PackedVector2Array()
        for sample_variant in samples:
            var sample: Array = sample_variant
            if sample.size() < 3:
                continue
            points.append(_static_world_to_cache(Vector2(float(sample[0]), float(sample[2]))))
        if points.size() < 2:
            continue
        var width_world := float(road_data.get("widthM", road_data.get("width", 16.0)))
        var road_width := clampf(width_world * pixels_per_meter, 3.2, 26.0)
        draw_polyline(points, Color(0.02, 0.03, 0.05, 0.85), road_width + 2.4, true)
        draw_polyline(points, Color(0.62, 0.70, 0.80, 0.96), road_width, true)
        draw_polyline(points, Color(0.95, 0.97, 1.0, 0.30), 1.2, true)

    # 0.3.16: off-road trails as tan tracks over the dunes.
    for trail in _trails:
        if not (trail is Dictionary):
            continue
        var trail_data := trail as Dictionary
        var waypoints: Array = trail_data.get("points", [])
        if waypoints.size() < 2:
            continue
        var tpoints := PackedVector2Array()
        for wp_variant in waypoints:
            var wp: Array = wp_variant
            if wp.size() < 2:
                continue
            tpoints.append(_static_world_to_cache(Vector2(float(wp[0]), float(wp[1]))))
        if bool(trail_data.get("closed", false)) and tpoints.size() > 2:
            tpoints.append(tpoints[0])
        if tpoints.size() < 2:
            continue
        draw_polyline(tpoints, Color(0.30, 0.20, 0.10, 0.85), 4.4, true)
        draw_polyline(tpoints, Color(0.92, 0.72, 0.42, 0.95), 2.6, true)


func _draw_cached_world() -> bool:
    if not _static_cache_ready or _static_cache_texture == null:
        return false
    var centre := size * 0.5
    var radius := _clip_radius()
    var scale := radius / VIEW_RADIUS_M
    var forward := _player_forward
    var right := Vector2(-forward.y, forward.x)
    var cache_size := Vector2(float(STATIC_CACHE_SIZE), float(STATIC_CACHE_SIZE))
    var x_axis := Vector2(right.x, -forward.x) * scale * (_world_bounds.size.x / cache_size.x)
    var y_axis := Vector2(right.y, -forward.y) * scale * (_world_bounds.size.y / cache_size.y)
    var origin := centre + _rotate_to_vehicle(_world_bounds.position - _player_position) * scale
    draw_set_transform_matrix(Transform2D(x_axis, y_axis, origin))
    draw_texture(_static_cache_texture, Vector2.ZERO)
    draw_set_transform_matrix(Transform2D.IDENTITY)
    return true


func _draw_vector_world() -> void:
    var radius := _clip_radius()
    for park_data in _parks:
        if park_data is Dictionary:
            _draw_rotated_rect((park_data as Dictionary).get("rect", Rect2()), Color(0.08, 0.42, 0.18, 0.68))

    for road in _roads:
        if not (road is Dictionary):
            continue
        var road_data := road as Dictionary
        var width_world := float(road_data.get("widthM", road_data.get("width", 16.0)))
        var road_width := clampf(width_world * radius / VIEW_RADIUS_M, 3.0, 12.0)
        var samples: Array = road_data.get("samples", [])
        if samples.size() >= 2:
            for i in range(samples.size() - 1):
                var first: Array = samples[i]
                var second: Array = samples[i + 1]
                if first.size() < 3 or second.size() < 3:
                    continue
                var from := Vector2(float(first[0]), float(first[2]))
                var to := Vector2(float(second[0]), float(second[2]))
                if from.distance_to(_player_position) > VIEW_RADIUS_M * 2.2 and to.distance_to(_player_position) > VIEW_RADIUS_M * 2.2:
                    continue
                var a2 := _world_to_map(from)
                var b2 := _world_to_map(to)
                _draw_clipped_line(a2, b2, Color(0.02, 0.03, 0.05, 0.85), road_width + 2.0)
                _draw_clipped_line(a2, b2, Color(0.62, 0.70, 0.80, 0.96), road_width)
                _draw_clipped_line(a2, b2, Color(0.95, 0.97, 1.0, 0.30), 1.0)
            continue
        var from: Vector2 = road_data.get("from", Vector2.ZERO)
        var to: Vector2 = road_data.get("to", Vector2.ZERO)
        if from.distance_to(_player_position) > VIEW_RADIUS_M * 2.2 and to.distance_to(_player_position) > VIEW_RADIUS_M * 2.2:
            continue
        var a := _world_to_map(from)
        var b := _world_to_map(to)
        _draw_clipped_line(a, b, Color(0.02, 0.03, 0.05, 0.85), road_width + 2.0)
        _draw_clipped_line(a, b, Color(0.62, 0.70, 0.80, 0.96), road_width)
        _draw_clipped_line(a, b, Color(0.95, 0.97, 1.0, 0.30), 1.0)

    # 0.3.16: off-road trails (vector fallback path).
    for trail in _trails:
        if not (trail is Dictionary):
            continue
        var trail_data2 := trail as Dictionary
        var waypoints2: Array = trail_data2.get("points", [])
        if waypoints2.size() < 2:
            continue
        var seg_count: int = waypoints2.size() if bool(trail_data2.get("closed", false)) else waypoints2.size() - 1
        for i in range(seg_count):
            var first2: Array = waypoints2[i]
            var second2: Array = waypoints2[(i + 1) % waypoints2.size()]
            if first2.size() < 2 or second2.size() < 2:
                continue
            var from2 := Vector2(float(first2[0]), float(first2[1]))
            var to2 := Vector2(float(second2[0]), float(second2[1]))
            if from2.distance_to(_player_position) > VIEW_RADIUS_M * 2.2 and to2.distance_to(_player_position) > VIEW_RADIUS_M * 2.2:
                continue
            var a3 := _world_to_map(from2)
            var b3 := _world_to_map(to2)
            _draw_clipped_line(a3, b3, Color(0.30, 0.20, 0.10, 0.85), 4.0)
            _draw_clipped_line(a3, b3, Color(0.92, 0.72, 0.42, 0.95), 2.4)



func _draw() -> void:
    if _static_cache_mode:
        _draw_static_cache()
        return
    if size.x < 24.0 or size.y < 24.0:
        return
    var centre := size * 0.5
    var radius := _clip_radius()
    var font := get_theme_default_font()
    var north_font_size := int(clampf(radius * 0.14, 11.0, 19.0))

    # The parent applies a circular shader mask; drawing the base as
    # a full disc also keeps the control correct without material.
    draw_circle(centre, radius, Color(0.010, 0.015, 0.030, 0.66))
    draw_arc(centre, radius * 0.72, 0.0, TAU, 72, Color(0.62, 0.74, 0.86, 0.10), 1.0, true)
    draw_arc(centre, radius * 0.42, 0.0, TAU, 56, Color(0.62, 0.74, 0.86, 0.08), 1.0, true)

    if not _draw_cached_world():
        _draw_vector_world()

    if _destination != Vector2.INF:
        if _route_points.size() >= 2:
            for i in range(1, _route_points.size()):
                var from := _world_to_map(_route_points[i - 1])
                var to := _world_to_map(_route_points[i])
                if not _inside(from, -40.0) and not _inside(to, -40.0):
                    continue
                _draw_clipped_line(from, to, Color(0.08, 0.78, 1.0, 0.30), 7.0)
                _draw_clipped_line(from, to, Color(0.18, 0.88, 1.0, 0.96), 3.0)
        else:
            var straight_destination := _world_to_map(_destination)
            _draw_clipped_line(centre, straight_destination, Color(0.08, 0.78, 1.0, 0.34), 7.0)
            _draw_clipped_line(centre, straight_destination, Color(0.18, 0.88, 1.0, 0.96), 3.0)
        var destination_point := _world_to_map(_destination)
        var marker := destination_point
        if not _inside(marker, 10.0):
            marker = centre + (marker - centre).normalized() * (radius - 13.0)
        draw_circle(marker, 6.0, Color(0.10, 0.82, 1.0, 0.96))
        draw_arc(marker, 8.5, 0.0, TAU, 28, Color.WHITE, 1.4, true)

    for poi_data in _pois:
        if not (poi_data is Dictionary):
            continue
        var poi := poi_data as Dictionary
        var world_point: Vector2 = poi.get("position", Vector2.ZERO)
        if world_point.distance_to(_player_position) > VIEW_RADIUS_M:
            continue
        var point := _world_to_map(world_point)
        if not _inside(point, 7.0):
            continue
        # Compact category icons: coloured core plus a category glyph.
        var category: String = poi.get("category", "")
        var color := Color(1.0, 0.72, 0.26)
        if category in ["Религия", "Мечеть", "Культ"]:
            color = Color(0.72, 0.50, 1.0)
        elif category in ["Отель", "Пляж", "Старт"]:
            color = Color(0.35, 0.72, 1.0)
        elif category in ["Кафе", "Инфраструктура", "Достопримечательность"]:
            color = Color(1.0, 0.48, 0.30)
        draw_circle(point, 3.4, color)

    # 0.3.28: while on foot the parked car keeps its own marker,
    # clamped to the rim when it lies beyond the visible radius so
    # the way back to the car is always readable.
    if _show_vehicle_marker and _vehicle != null:
        var car_point := _world_to_map(Vector2(_vehicle.global_position.x, _vehicle.global_position.z))
        var car_offset := car_point - centre
        var car_limit := radius - 16.0
        if car_offset.length() > car_limit:
            car_point = centre + car_offset.normalized() * car_limit
        draw_circle(car_point, 7.0, Color(1.0, 1.0, 1.0, 0.95))
        draw_circle(car_point, 4.6, Color(1.0, 0.58, 0.10, 1.0))

    # The vehicle marker is always centred and points up because the
    # world rotates underneath it in heading-up mode.
    var arrow := PackedVector2Array([
        centre + Vector2(0.0, -10.0),
        centre + Vector2(6.5, 7.0),
        centre + Vector2(0.0, 3.4),
        centre + Vector2(-6.5, 7.0),
    ])
    draw_colored_polygon(arrow, Color(1.0, 0.58, 0.10, 1.0))

    # Fixed north indicator on the rim.  World north is -Z; after the
    # heading transform its direction rotates opposite the car.
    var north_direction := _rotate_to_vehicle(Vector2(0.0, -1.0)).normalized()
    var north_point := centre + north_direction * (radius - 13.0)
    draw_circle(north_point, 9.0, Color(0.012, 0.025, 0.05, 0.66))
    draw_arc(north_point, 9.0, 0.0, TAU, 28, Color(0.72, 0.86, 1.0, 0.72), 1.0, true)
    if font != null:
        draw_string(font, north_point + Vector2(-4.2, 4.8), "N", HORIZONTAL_ALIGNMENT_LEFT, -1.0, north_font_size, Color(0.86, 0.94, 1.0, 0.98))

    draw_arc(centre, radius - 0.8, 0.0, TAU, 96, Color(1.0, 0.64, 0.16, 0.76), 1.6, true)
