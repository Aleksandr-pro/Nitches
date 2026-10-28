class_name NativeRouteGuide
extends Node3D

## 0.2.34 road-following navigation.  A compact AStar2D graph is
## built once from RichTown's exported road samples (plus short
## links between nearby samples at junctions).  The current route
## is drawn in the 3D world as an orange ribbon lying on the road
## and the same polyline is passed to the HUD minimap.

signal path_changed(points: Array, distance_m: float)
signal route_arrived

const NODE_SPACING_M := 14.0
const MERGE_RADIUS_M := 5.0
const JUNCTION_LINK_RADIUS_M := 22.0
const ARRIVAL_RADIUS_M := 30.0

var _world: NativeWorldBuilder
var _vehicle: NativeVehicle
var _astar := AStar2D.new()
var _nodes: Array[Vector2] = []
var _node_y: Array[float] = []
var _node_hash: Dictionary = {}
var _edge_count := 0
var _destination := Vector2.INF
var _path_points: Array[Vector2] = []
var _path_distance_m := 0.0
var _last_start_id := -1
var _last_goal_id := -1
var _update_timer := 0.0
var _route_mesh: MeshInstance3D
var _beacon: MeshInstance3D
var _beacon_material: StandardMaterial3D


func _ready() -> void:
    name = "RouteGuide"
    _route_mesh = MeshInstance3D.new()
    _route_mesh.name = "RouteRibbon"
    _route_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var route_material := StandardMaterial3D.new()
    route_material.albedo_color = Color(1.0, 0.52, 0.05, 0.84)
    route_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    route_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    route_material.emission_enabled = true
    route_material.emission = Color(1.0, 0.42, 0.03)
    route_material.emission_energy_multiplier = 1.4
    _route_mesh.material_override = route_material
    add_child(_route_mesh)

    _beacon = MeshInstance3D.new()
    _beacon.name = "RouteDestinationBeacon"
    var cylinder := CylinderMesh.new()
    cylinder.top_radius = 2.0
    cylinder.bottom_radius = 2.0
    cylinder.height = 38.0
    cylinder.radial_segments = 24
    _beacon.mesh = cylinder
    _beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _beacon_material = StandardMaterial3D.new()
    _beacon_material.albedo_color = Color(1.0, 0.52, 0.05, 0.20)
    _beacon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    _beacon_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _beacon_material.emission_enabled = true
    _beacon_material.emission = Color(1.0, 0.42, 0.03)
    _beacon_material.emission_energy_multiplier = 1.2
    _beacon.material_override = _beacon_material
    _beacon.visible = false
    add_child(_beacon)


func bind(world: NativeWorldBuilder, vehicle: NativeVehicle) -> void:
    _world = world
    _vehicle = vehicle
    _build_graph()


func set_destination(world_position: Vector2) -> void:
    _destination = world_position
    _last_start_id = -1
    _last_goal_id = -1
    _recompute(true)


func clear_route(emit_arrived: bool = false) -> void:
    var had_route := _destination != Vector2.INF
    _destination = Vector2.INF
    _path_points.clear()
    _path_distance_m = 0.0
    _last_start_id = -1
    _last_goal_id = -1
    if _route_mesh != null:
        _route_mesh.mesh = null
    if _beacon != null:
        _beacon.visible = false
    if had_route:
        path_changed.emit([], 0.0)
        if emit_arrived:
            route_arrived.emit()


func has_route() -> bool:
    return _destination != Vector2.INF and not _path_points.is_empty()


func get_destination() -> Vector2:
    return _destination


func get_path_points() -> Array:
    return _path_points.duplicate()


func get_path_distance_m() -> float:
    return _path_distance_m


func update_route(delta: float) -> void:
    if _destination == Vector2.INF or _vehicle == null:
        return
    var vehicle_xz := Vector2(_vehicle.global_position.x, _vehicle.global_position.z)
    if vehicle_xz.distance_to(_destination) <= ARRIVAL_RADIUS_M:
        clear_route(true)
        return
    if _beacon != null and _beacon.visible:
        var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004)
        _beacon.scale = Vector3(0.86 + pulse * 0.28, 1.0, 0.86 + pulse * 0.28)
        if _beacon_material != null:
            _beacon_material.albedo_color.a = 0.14 + pulse * 0.10
    _update_timer += maxf(delta, 0.0)
    if _update_timer < 0.75:
        return
    _update_timer = 0.0
    _recompute(false)


func get_smoke_state() -> Dictionary:
    return {
        "route_guide_0234": true,
        "graph_nodes": _nodes.size(),
        "graph_edges": _edge_count,
        "has_route": has_route(),
        "destination": _destination,
        "path_points": _path_points.size(),
        "path_distance_m": _path_distance_m,
    }


func _hash_key(point: Vector2, cell_size: float) -> Vector2i:
    return Vector2i(floori(point.x / cell_size), floori(point.y / cell_size))


func _find_or_add_node(point: Vector2, y_value: float) -> int:
    var cell := _hash_key(point, 10.0)
    for dx in range(-1, 2):
        for dy in range(-1, 2):
            var indices: Array = _node_hash.get(cell + Vector2i(dx, dy), [])
            for index_variant in indices:
                var index := int(index_variant)
                if _nodes[index].distance_to(point) <= MERGE_RADIUS_M:
                    _node_y[index] = (_node_y[index] + y_value) * 0.5
                    return index
    var new_index := _nodes.size()
    _nodes.append(point)
    _node_y.append(y_value)
    _astar.add_point(new_index, point)
    var own_indices: Array = _node_hash.get(cell, [])
    own_indices.append(new_index)
    _node_hash[cell] = own_indices
    return new_index


func _connect(from_id: int, to_id: int) -> void:
    if from_id < 0 or to_id < 0 or from_id == to_id:
        return
    if _astar.are_points_connected(from_id, to_id):
        return
    _astar.connect_points(from_id, to_id, true)
    _edge_count += 1


func _build_graph() -> void:
    if _world == null or not _nodes.is_empty():
        return
    var data := _world.get_world_data()
    for road_variant in data.get("roads", []):
        var road: Dictionary = road_variant
        var previous_id := -1
        var last_kept := Vector2.INF
        var samples: Array = road.get("samples", [])
        for sample_index in samples.size():
            var sample: Array = samples[sample_index]
            if sample.size() < 3:
                continue
            var point := Vector2(float(sample[0]), float(sample[2]))
            var is_last := sample_index == samples.size() - 1
            if last_kept != Vector2.INF and not is_last and point.distance_to(last_kept) < NODE_SPACING_M:
                continue
            var node_id := _find_or_add_node(point, float(sample[1]))
            if previous_id >= 0:
                _connect(previous_id, node_id)
            previous_id = node_id
            last_kept = point

    # Road centrelines cross without always sharing an identical
    # sample.  Link nearby nodes through a spatial hash so those
    # crossings become usable junctions without an O(n²) build.
    var junction_hash: Dictionary = {}
    for node_id in _nodes.size():
        var point := _nodes[node_id]
        var cell := _hash_key(point, JUNCTION_LINK_RADIUS_M)
        for dx in range(-1, 2):
            for dy in range(-1, 2):
                var indices: Array = junction_hash.get(cell + Vector2i(dx, dy), [])
                for other_variant in indices:
                    var other_id := int(other_variant)
                    if point.distance_to(_nodes[other_id]) <= JUNCTION_LINK_RADIUS_M:
                        _connect(node_id, other_id)
        var own_indices: Array = junction_hash.get(cell, [])
        own_indices.append(node_id)
        junction_hash[cell] = own_indices


func _recompute(force: bool) -> void:
    if _destination == Vector2.INF or _vehicle == null or _nodes.is_empty():
        return
    var vehicle_xz := Vector2(_vehicle.global_position.x, _vehicle.global_position.z)
    var start_id := _astar.get_closest_point(vehicle_xz)
    var goal_id := _astar.get_closest_point(_destination)
    if not force and start_id == _last_start_id and goal_id == _last_goal_id:
        return
    _last_start_id = start_id
    _last_goal_id = goal_id

    var ids := _astar.get_id_path(start_id, goal_id)
    _path_points.clear()
    _path_points.append(vehicle_xz)
    if ids.is_empty():
        _path_points.append(_destination)
    else:
        for id in ids:
            var point := _nodes[int(id)]
            if _path_points.is_empty() or _path_points[_path_points.size() - 1].distance_to(point) > 2.0:
                _path_points.append(point)
        if _path_points[_path_points.size() - 1].distance_to(_destination) > 2.0:
            _path_points.append(_destination)

    _path_distance_m = 0.0
    for i in range(1, _path_points.size()):
        _path_distance_m += _path_points[i - 1].distance_to(_path_points[i])

    _build_ribbon(ids)
    _position_beacon(goal_id)
    path_changed.emit(_path_points.duplicate(), _path_distance_m)


func _path_y(index: int, _ids: PackedInt64Array) -> float:
    if index == 0 and _vehicle != null:
        return _vehicle.global_position.y + 0.22
    if index == _path_points.size() - 1:
        return (_world.height_at(_destination.x, _destination.y) if _world != null else 0.0) + 0.22
    var point := _path_points[index]
    var closest_id := _astar.get_closest_point(point)
    if closest_id >= 0 and closest_id < _node_y.size():
        return _node_y[closest_id] + 0.22
    return (_world.height_at(point.x, point.y) if _world != null else 0.0) + 0.22


func _build_ribbon(ids: PackedInt64Array) -> void:
    if _route_mesh == null or _path_points.size() < 2:
        return
    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    var indices := PackedInt32Array()
    for i in _path_points.size():
        var point2d := _path_points[i]
        var direction := Vector2.RIGHT
        if i > 0 and i < _path_points.size() - 1:
            direction = (_path_points[i + 1] - _path_points[i - 1]).normalized()
        elif i == 0:
            direction = (_path_points[1] - _path_points[0]).normalized()
        else:
            direction = (_path_points[i] - _path_points[i - 1]).normalized()
        if direction.length_squared() < 0.001:
            direction = Vector2.RIGHT
        var side := Vector2(-direction.y, direction.x) * 0.58
        var y_value := _path_y(i, ids)
        vertices.append(Vector3(point2d.x - side.x, y_value, point2d.y - side.y))
        vertices.append(Vector3(point2d.x + side.x, y_value, point2d.y + side.y))
        normals.append(Vector3.UP)
        normals.append(Vector3.UP)
        if i > 0:
            var base := (i - 1) * 2
            indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    _route_mesh.mesh = mesh


func _position_beacon(goal_id: int) -> void:
    if _beacon == null:
        return
    var y_value := _world.height_at(_destination.x, _destination.y) if _world != null else 0.0
    if goal_id >= 0 and goal_id < _node_y.size():
        y_value = maxf(y_value, _node_y[goal_id])
    _beacon.global_position = Vector3(_destination.x, y_value + 19.0, _destination.y)
    _beacon.visible = true
