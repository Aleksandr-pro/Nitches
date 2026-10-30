class_name NitchesMpClient
extends Node3D

## 0.2.61 free-roam multiplayer: one WebSocket room per world on the
## Cloudflare Worker (Durable Object relay, see server/src/index.js).
## The local car transform is pushed ~10x/s; remote players appear as
## smoothly interpolated ghost cars — real catalogue models with a
## floating nickname.  Test-build v1 has no player-vs-player
## collision by design: cruise together, chase, drift in convoy.

signal connection_changed(connected: bool, message: String)
signal peers_changed(count: int)

const SEND_INTERVAL := 0.1
const SNAP_DISTANCE_M := 80.0

var _peer: WebSocketPeer
var _connected := false
var _own_id := ""
var _ghosts: Dictionary = {}
var _scene_cache: Dictionary = {}
var _local_xform := Transform3D.IDENTITY
var _local_speed := 0.0
var _has_local := false
var _send_timer := 0.0


func is_connected_to_room() -> bool:
	return _connected


func peer_count() -> int:
	return _ghosts.size()


func join_room(server_url: String, token: String, room: String, display_name: String, car_id: String) -> void:
	leave_room()
	var base := server_url.strip_edges().trim_suffix("/")
	if base.begins_with("https://"):
		base = "wss://" + base.trim_prefix("https://")
	elif base.begins_with("http://"):
		base = "ws://" + base.trim_prefix("http://")
	if base.is_empty():
		connection_changed.emit(false, "Сначала укажите адрес сервера.")
		return
	var url := "%s/mp?room=%s&name=%s&car=%s&token=%s" % [
		base, room.uri_encode(), display_name.uri_encode(), car_id.uri_encode(), token.uri_encode()]
	_peer = WebSocketPeer.new()
	var err := _peer.connect_to_url(url)
	if err != OK:
		_peer = null
		connection_changed.emit(false, "Не удалось подключиться к комнате.")
		return
	connection_changed.emit(false, "Подключение к комнате мира…")


func leave_room() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	var was_connected := _connected
	_connected = false
	_own_id = ""
	_clear_ghosts()
	if was_connected:
		connection_changed.emit(false, "Вы покинули комнату.")


func update_local_state(xform: Transform3D, speed_kmh: float) -> void:
	_local_xform = xform
	_local_speed = speed_kmh
	_has_local = true


func _process(delta: float) -> void:
	if _peer != null:
		_peer.poll()
		var state := _peer.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			if not _connected:
				_connected = true
				connection_changed.emit(true, "Вы в комнате. Приятной езды!")
				_send_json({"t": "hello"})
			while _peer.get_available_packet_count() > 0:
				_handle_packet(_peer.get_packet())
			_send_timer += delta
			if _send_timer >= SEND_INTERVAL:
				_send_timer = 0.0
				_send_state()
		elif state == WebSocketPeer.STATE_CLOSED:
			var was_open := _connected
			_peer = null
			_connected = false
			_clear_ghosts()
			connection_changed.emit(false, "Соединение с комнатой закрыто." if was_open else "Комната недоступна: сервер без мультиплеера или нет сети.")
	_update_ghosts(delta)


func _send_state() -> void:
	if not _has_local:
		return
	var p := _local_xform.origin
	var q := _local_xform.basis.get_rotation_quaternion()
	_send_json({"t": "state", "p": [p.x, p.y, p.z], "q": [q.x, q.y, q.z, q.w], "s": _local_speed})


func _send_json(payload: Dictionary) -> void:
	if _peer != null and _peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_peer.send_text(JSON.stringify(payload))


func _handle_packet(packet: PackedByteArray) -> void:
	var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
	if not (parsed is Dictionary):
		return
	var data: Dictionary = parsed
	match String(data.get("t", "")):
		"welcome":
			_own_id = String(data.get("id", ""))
		"join":
			_upsert_ghost(data, false)
		"state":
			_upsert_ghost(data, true)
		"peers":
			for peer_variant in data.get("peers", []):
				var peer_data: Dictionary = peer_variant
				_upsert_ghost(peer_data, false)
		"leave":
			_remove_ghost(String(data.get("id", "")))
		"announce_request":
			_send_state()


func _upsert_ghost(data: Dictionary, has_state: bool) -> void:
	var peer_id := String(data.get("id", ""))
	if peer_id.is_empty() or peer_id == _own_id:
		return
	var ghost: Dictionary = _ghosts.get(peer_id, {})
	if ghost.is_empty():
		ghost = {
			"node": _build_ghost_node(String(data.get("car", NativeCarCatalog.DEFAULT_CAR_ID)), String(data.get("name", "ИГРОК"))),
			"target_pos": Vector3(0.0, -100.0, 0.0),
			"target_quat": Quaternion.IDENTITY,
			"has_target": false,
		}
		_ghosts[peer_id] = ghost
		peers_changed.emit(_ghosts.size())
	if has_state:
		var p: Array = data.get("p", [])
		var q: Array = data.get("q", [])
		if p.size() == 3 and q.size() == 4:
			var target_pos := Vector3(float(p[0]), float(p[1]), float(p[2]))
			var target_quat := Quaternion(float(q[0]), float(q[1]), float(q[2]), float(q[3])).normalized()
			ghost["target_pos"] = target_pos
			ghost["target_quat"] = target_quat
			if not bool(ghost.get("has_target", false)):
				ghost["has_target"] = true
				var node: Node3D = ghost.get("node") as Node3D
				if node != null:
					node.global_transform = Transform3D(Basis(target_quat), target_pos)
					node.visible = true
			_ghosts[peer_id] = ghost


func _build_ghost_node(car_id: String, display_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = "GhostCar"
	root.visible = false
	var model_path := String(NativeCarCatalog.get_car(car_id).get("model_path", ""))
	var scene: PackedScene = _scene_cache.get(car_id) as PackedScene
	if scene == null and not model_path.is_empty() and ResourceLoader.exists(model_path):
		scene = ResourceLoader.load(model_path) as PackedScene
		_scene_cache[car_id] = scene
	if scene != null:
		root.add_child(scene.instantiate())
	else:
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.8, 0.6, 4.2)
		box.mesh = mesh
		box.position.y = 0.5
		root.add_child(box)
	var label := Label3D.new()
	label.text = display_name
	label.font_size = 64
	label.pixel_size = 0.0035
	label.position = Vector3(0.0, 2.3, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1.0, 1.0, 1.0, 0.95)
	label.outline_size = 10
	label.outline_modulate = Color(0.05, 0.06, 0.1, 0.9)
	root.add_child(label)
	add_child(root)
	return root


func _update_ghosts(delta: float) -> void:
	if _ghosts.is_empty() or delta <= 0.0:
		return
	var blend := 1.0 - exp(-10.0 * delta)
	for peer_id in _ghosts.keys():
		var ghost: Dictionary = _ghosts[peer_id]
		if not bool(ghost.get("has_target", false)):
			continue
		var node: Node3D = ghost.get("node") as Node3D
		if node == null:
			continue
		var target_pos: Vector3 = ghost["target_pos"]
		var target_quat: Quaternion = ghost["target_quat"]
		var current := node.global_transform
		if current.origin.distance_to(target_pos) > SNAP_DISTANCE_M:
			node.global_transform = Transform3D(Basis(target_quat), target_pos)
			continue
		var quat := current.basis.get_rotation_quaternion().slerp(target_quat, blend)
		node.global_transform = Transform3D(Basis(quat), current.origin.lerp(target_pos, blend))


func _remove_ghost(peer_id: String) -> void:
	if not _ghosts.has(peer_id):
		return
	var ghost: Dictionary = _ghosts[peer_id]
	var node: Node3D = ghost.get("node") as Node3D
	if node != null:
		node.queue_free()
	_ghosts.erase(peer_id)
	peers_changed.emit(_ghosts.size())


func _clear_ghosts() -> void:
	for peer_id in _ghosts.keys():
		var ghost: Dictionary = _ghosts[peer_id]
		var node: Node3D = ghost.get("node") as Node3D
		if node != null:
			node.queue_free()
	_ghosts.clear()
	peers_changed.emit(0)
