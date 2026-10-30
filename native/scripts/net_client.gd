class_name NitchesNetClient
extends Node

## 0.2.61 HTTP client for the Nitches Cloudflare Worker
## (server/src/index.js in the repo): accounts, progress sync, daily
## quests, feedback, leaderboard, presence and the admin API.
##
## Every request runs through one HTTPRequest queue so slow mobile
## networks never see overlapping calls.  Failures are reported via
## request_failed (server message or "no connection"); nothing throws.
## The game keeps working fully offline when no server is set.

signal auth_succeeded(user: Dictionary, profile: Dictionary, token: String, is_new_account: bool, first_player: bool)
signal me_loaded(user: Dictionary, profile: Dictionary)
signal quests_loaded(day: String, quests: Array)
signal quest_claimed(quest_id: String, reward: int, credits: int)
signal feedback_sent
signal leaderboard_loaded(rows: Array, by: String)
signal rooms_loaded(data: Dictionary)
signal admin_data_loaded(kind: String, data: Dictionary)
signal progress_synced(profile: Dictionary)
signal request_failed(tag: String, message: String)

var _base_url := ""
var _token := ""
var _http: HTTPRequest
var _queue: Array = []
var _busy := false
var _pending_claim_id := ""
var _claim_inflight_id := ""


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func configure(server_url: String, token: String) -> void:
	_base_url = server_url.strip_edges().trim_suffix("/")
	_token = token


func set_token(token: String) -> void:
	_token = token


func has_server() -> bool:
	return not _base_url.is_empty()


# --- public API ---

func register_account(username: String, password: String) -> void:
	_enqueue("register", HTTPClient.METHOD_POST, "/api/register", {"username": username, "password": password}, false)


func login_account(username: String, password: String) -> void:
	_enqueue("login", HTTPClient.METHOD_POST, "/api/login", {"username": username, "password": password}, false)


func logout_account() -> void:
	_enqueue("logout", HTTPClient.METHOD_POST, "/api/logout", {}, true)


func fetch_me() -> void:
	_enqueue("me", HTTPClient.METHOD_GET, "/api/me", {}, true)


func put_progress(payload: Dictionary) -> void:
	_enqueue("progress_put", HTTPClient.METHOD_PUT, "/api/me/progress", payload, true)


func fetch_quests() -> void:
	_enqueue("quests_today", HTTPClient.METHOD_GET, "/api/quests/today", {}, true)


func push_quest_progress(quest_id: String, value: float) -> void:
	_enqueue("quest_progress", HTTPClient.METHOD_POST, "/api/quests/progress", {"quest_id": quest_id, "value": value}, true)


func claim_quest(quest_id: String, local_value: float) -> void:
	# The server grants the reward from ITS stored progress, so push
	# the freshest local value first, then claim (chained below).
	_pending_claim_id = quest_id
	_enqueue("quest_progress_for_claim", HTTPClient.METHOD_POST, "/api/quests/progress", {"quest_id": quest_id, "value": local_value}, true)


func send_feedback(text: String, category: String) -> void:
	_enqueue("feedback", HTTPClient.METHOD_POST, "/api/feedback", {"text": text, "category": category}, true)


func fetch_leaderboard(by: String) -> void:
	_enqueue("leaderboard", HTTPClient.METHOD_GET, "/api/leaderboard?by=" + by, {}, false)


func fetch_rooms() -> void:
	_enqueue("rooms", HTTPClient.METHOD_GET, "/api/rooms", {}, false)


func send_presence(world_id: String) -> void:
	_enqueue("presence", HTTPClient.METHOD_POST, "/api/presence", {"world": world_id}, true)


func admin_fetch(kind: String) -> void:
	_enqueue("admin_" + kind, HTTPClient.METHOD_GET, "/api/admin/" + kind, {}, true)


func admin_grant(username: String, amount: int) -> void:
	_enqueue("admin_grant", HTTPClient.METHOD_POST, "/api/admin/grant", {"username": username, "amount": amount}, true)


func admin_feedback_delete(feedback_id: int) -> void:
	_enqueue("admin_feedback_delete", HTTPClient.METHOD_POST, "/api/admin/feedback/delete", {"id": feedback_id}, true)


# --- queue plumbing ---

func _enqueue(tag: String, method: HTTPClient.Method, path: String, body: Dictionary, needs_auth: bool) -> void:
	if _base_url.is_empty():
		request_failed.emit(tag, "no connection")
		return
	_queue.append({"tag": tag, "method": int(method), "path": path, "body": body, "auth": needs_auth})
	_pump()


func _method_from_int(value: int) -> HTTPClient.Method:
	match value:
		HTTPClient.METHOD_POST:
			return HTTPClient.METHOD_POST
		HTTPClient.METHOD_PUT:
			return HTTPClient.METHOD_PUT
		HTTPClient.METHOD_DELETE:
			return HTTPClient.METHOD_DELETE
		_:
			return HTTPClient.METHOD_GET


func _pump() -> void:
	if _busy or _queue.is_empty() or _http == null:
		return
	var job: Dictionary = _queue[0]
	var headers := PackedStringArray(["Content-Type: application/json"])
	if bool(job.get("auth", false)) and not _token.is_empty():
		headers.append("Authorization: Bearer " + _token)
	var method := _method_from_int(int(job.get("method", HTTPClient.METHOD_GET)))
	var body_text := ""
	if method != HTTPClient.METHOD_GET:
		body_text = JSON.stringify(job.get("body", {}))
	var err := _http.request(_base_url + String(job.get("path", "")), headers, method, body_text)
	if err != OK:
		_queue.pop_front()
		request_failed.emit(String(job.get("tag", "")), "no connection")
		_pump()
		return
	_busy = true


func _on_request_completed(result: int, _response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	if _queue.is_empty():
		return
	var job: Dictionary = _queue.pop_front()
	var tag := String(job.get("tag", ""))
	if result != HTTPRequest.RESULT_SUCCESS:
		request_failed.emit(tag, "no connection")
		_pump()
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	var data: Dictionary = parsed if parsed is Dictionary else {}
	if data.has("error"):
		request_failed.emit(tag, String(data.get("error", "error")))
		_pump()
		return
	_route_success(tag, data)
	_pump()


func _route_success(tag: String, data: Dictionary) -> void:
	match tag:
		"register", "login":
			_token = String(data.get("token", ""))
			var user: Dictionary = data.get("user", {})
			var profile: Dictionary = data.get("profile", {})
			auth_succeeded.emit(user, profile, _token, tag == "register", bool(data.get("first_player", false)))
		"me":
			me_loaded.emit(data.get("user", {}), data.get("profile", {}))
		"progress_put":
			progress_synced.emit(data.get("profile", {}))
		"quests_today":
			quests_loaded.emit(String(data.get("day", "")), data.get("quests", []))
		"quest_progress_for_claim":
			if not _pending_claim_id.is_empty():
				_claim_inflight_id = _pending_claim_id
				_pending_claim_id = ""
				_enqueue("quest_claim", HTTPClient.METHOD_POST, "/api/quests/claim", {"quest_id": _claim_inflight_id}, true)
		"quest_claim":
			quest_claimed.emit(_claim_inflight_id, int(data.get("reward", 0)), int(data.get("credits", 0)))
			_claim_inflight_id = ""
		"feedback":
			feedback_sent.emit()
		"leaderboard":
			leaderboard_loaded.emit(data.get("rows", []), String(data.get("by", "distance")))
		"rooms":
			rooms_loaded.emit(data)
		"admin_stats", "admin_users", "admin_feedback", "admin_grant", "admin_feedback_delete":
			admin_data_loaded.emit(tag.trim_prefix("admin_"), data)
		_:
			pass
