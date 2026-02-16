extends Node

## Server-only autoload that handles persistence via HTTP API (MongoDB) or file I/O fallback.
## API mode: Docker/K8s sets SAVE_API_URL env var → async HTTP to Express API.
## File mode: Editor dev with no API → JSON files in user://save/ (same as before).

signal player_loaded(player_name: String, data: Dictionary)
signal player_created(player_name: String, data: Dictionary)
signal world_loaded(data: Dictionary)
signal name_check_complete(player_name: String, exists: bool)

var api_base_url: String = ""
var use_api: bool = false

# File I/O fallback paths
var save_base_path: String = ""

# Auto-save
var auto_save_timer: float = 0.0
const AUTO_SAVE_INTERVAL = 60.0

# HTTP request pool
var _http_pool: Array[HTTPRequest] = []
const HTTP_POOL_SIZE = 5

func _ready() -> void:
	# Check for API URL from environment
	var env_url = OS.get_environment("SAVE_API_URL")
	if env_url != "":
		api_base_url = env_url
		print("[SaveManager] API URL from env: ", api_base_url)
		# Defer health check so tree is ready
		_check_api_health.call_deferred()
	else:
		print("[SaveManager] No SAVE_API_URL set, using file I/O fallback")
		_init_file_fallback()

	# Create HTTP request pool
	for i in HTTP_POOL_SIZE:
		var http = HTTPRequest.new()
		http.name = "HTTPPool_%d" % i
		http.timeout = 10.0
		add_child(http)
		_http_pool.append(http)

func _check_api_health() -> void:
	var http = _get_free_http()
	if http == null:
		print("[SaveManager] No free HTTP request for health check, falling back to file I/O")
		_init_file_fallback()
		return
	var url = api_base_url.trim_suffix("/api") + "/health"
	var err = http.request(url, [], HTTPClient.METHOD_GET)
	if err != OK:
		print("[SaveManager] Health check request failed (err=", err, "), falling back to file I/O")
		_init_file_fallback()
		return
	var result = await http.request_completed
	var response_code = result[1] as int
	if response_code == 200:
		use_api = true
		print("[SaveManager] API health check passed — using MongoDB persistence")
	else:
		print("[SaveManager] API health check failed (HTTP ", response_code, "), falling back to file I/O")
		_init_file_fallback()

func _init_file_fallback() -> void:
	if save_base_path != "":
		return # Already initialized
	if FileAccess.file_exists("/app/data/.docker_marker") or DirAccess.dir_exists_absolute("/app/data"):
		save_base_path = "/app/data/"
	else:
		save_base_path = OS.get_user_data_dir() + "/save/"
	DirAccess.make_dir_recursive_absolute(save_base_path + "players")
	print("[SaveManager] File I/O save path: ", save_base_path)

func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	auto_save_timer += delta
	if auto_save_timer >= AUTO_SAVE_INTERVAL:
		auto_save_timer = 0.0
		auto_save_all()

func auto_save_all() -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	var nm = get_node_or_null("/root/NetworkManager")
	if nm and nm.get("player_data_store"):
		# Tick bond points for time-in-party
		for peer_id in nm.player_data_store:
			nm.server_tick_bond_time(peer_id)
		for peer_id in nm.player_data_store:
			var data: Dictionary = nm.player_data_store[peer_id]
			# Update position from player node (use overworld position if in restaurant)
			var rest_mgr = get_node_or_null("/root/Main/GameWorld/RestaurantManager")
			if rest_mgr and peer_id in rest_mgr.overworld_positions:
				var ow_pos = rest_mgr.overworld_positions[peer_id]
				data["position"] = {"x": ow_pos.x, "y": ow_pos.y, "z": ow_pos.z}
			else:
				var player_node = _get_player_node(peer_id)
				if player_node:
					data["position"] = {"x": player_node.position.x, "y": player_node.position.y, "z": player_node.position.z}
			var player_name = data.get("player_name", "")
			if player_name != "" and player_name != "Server":
				save_player(data)
	# Save world state
	var gw = get_node_or_null("/root/Main/GameWorld")
	if gw and gw.has_method("get_save_data"):
		save_world(gw.get_save_data())
	print("[SaveManager] Auto-save complete")

func _get_player_node(peer_id: int) -> Node3D:
	var players_node = get_node_or_null("/root/Main/GameWorld/Players")
	if players_node:
		return players_node.get_node_or_null(str(peer_id))
	return null

# === HTTP Pool ===

func _get_free_http() -> HTTPRequest:
	for http in _http_pool:
		if http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
			return http
	# All busy — create a temporary one
	var http = HTTPRequest.new()
	http.name = "HTTPTemp_%d" % randi()
	http.timeout = 10.0
	add_child(http)
	# Auto-cleanup after use
	http.request_completed.connect(func(_r, _c, _h, _b): http.queue_free(), CONNECT_ONE_SHOT)
	return http

# === Player Save/Load ===

func save_player(data: Dictionary) -> void:
	var player_id = data.get("player_id", "")
	if player_id == "":
		var player_name = data.get("player_name", "")
		if player_name != "":
			_save_player_file(player_name, data)
		return

	if use_api:
		_save_player_api(player_id, data)
	else:
		var player_name = data.get("player_name", "")
		if player_name != "":
			_save_player_file(player_name, data)

func _save_player_api(player_id: String, data: Dictionary) -> void:
	var http = _get_free_http()
	if http == null:
		return
	var url = api_base_url + "/players/" + player_id.uri_encode()
	var json_str = JSON.stringify(data)
	var headers = ["Content-Type: application/json"]
	var err = http.request(url, headers, HTTPClient.METHOD_PUT, json_str)
	if err != OK:
		print("[SaveManager] Failed to save player via API (err=", err, ")")

func _save_player_file(player_name: String, data: Dictionary) -> void:
	if save_base_path == "":
		_init_file_fallback()
	var path = _player_path(player_name)
	var json_str = JSON.stringify(data, "\t")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		file.close()

## Async load player by name. Emits player_loaded(name, data) when done.
## If not found, emits player_loaded with empty dict.
func load_player_async(player_name: String) -> void:
	if use_api:
		_load_player_api(player_name)
	else:
		var data = _load_player_file(player_name)
		player_loaded.emit(player_name, data)

func _load_player_api(player_name: String) -> void:
	var http = _get_free_http()
	if http == null:
		player_loaded.emit(player_name, {})
		return
	var url = api_base_url + "/players/by-name/" + player_name.uri_encode()
	var err = http.request(url, [], HTTPClient.METHOD_GET)
	if err != OK:
		print("[SaveManager] Failed to load player via API (err=", err, ")")
		player_loaded.emit(player_name, {})
		return
	var result = await http.request_completed
	var response_code = result[1] as int
	var body = (result[3] as PackedByteArray).get_string_from_utf8()
	if response_code == 200 and body != "":
		var json = JSON.new()
		var parse_err = json.parse(body)
		if parse_err == OK and json.data is Dictionary:
			var data = json.data as Dictionary
			# Empty object means not found
			if data.is_empty():
				player_loaded.emit(player_name, {})
			else:
				player_loaded.emit(player_name, data)
			return
	player_loaded.emit(player_name, {})

## Create a new player via API. Emits player_created(name, data) with the full document including player_id.
func create_player_async(data: Dictionary) -> void:
	var player_name = data.get("player_name", "")
	if use_api:
		_create_player_api(data)
	else:
		# File fallback: generate a local UUID
		data["player_id"] = _generate_uuid()
		_save_player_file(player_name, data)
		player_created.emit(player_name, data)

func _create_player_api(data: Dictionary) -> void:
	var player_name = data.get("player_name", "")
	var http = _get_free_http()
	if http == null:
		player_created.emit(player_name, {})
		return
	var url = api_base_url + "/players"
	var json_str = JSON.stringify(data)
	var headers = ["Content-Type: application/json"]
	var err = http.request(url, headers, HTTPClient.METHOD_POST, json_str)
	if err != OK:
		print("[SaveManager] Failed to create player via API (err=", err, ")")
		player_created.emit(player_name, {})
		return
	var result = await http.request_completed
	var response_code = result[1] as int
	var body = (result[3] as PackedByteArray).get_string_from_utf8()
	if response_code == 201 and body != "":
		var json = JSON.new()
		var parse_err = json.parse(body)
		if parse_err == OK and json.data is Dictionary:
			player_created.emit(player_name, json.data as Dictionary)
			return
	print("[SaveManager] Create player API failed (HTTP ", response_code, "): ", body)
	player_created.emit(player_name, {})

## Synchronous load for file fallback (used internally)
func _load_player_file(player_name: String) -> Dictionary:
	if save_base_path == "":
		_init_file_fallback()
	var path = _player_path(player_name)
	if not FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		print("[SaveManager] Failed to parse player save: ", path)
		return {}
	return json.data if json.data is Dictionary else {}

## Synchronous load for backward compat (editor/offline only)
func load_player(player_name: String) -> Dictionary:
	return _load_player_file(player_name)

func _player_path(player_name: String) -> String:
	var safe_name = player_name.replace("/", "_").replace("\\", "_").replace(".", "_").replace(" ", "_")
	return save_base_path + "players/" + safe_name + ".json"

# === World Save/Load ===

func save_world(data: Dictionary) -> void:
	if use_api:
		_save_world_api(data)
	else:
		_save_world_file(data)

func _save_world_api(data: Dictionary) -> void:
	var http = _get_free_http()
	if http == null:
		return
	var url = api_base_url + "/world"
	var json_str = JSON.stringify(data)
	var headers = ["Content-Type: application/json"]
	var err = http.request(url, headers, HTTPClient.METHOD_PUT, json_str)
	if err != OK:
		print("[SaveManager] Failed to save world via API (err=", err, ")")

func _save_world_file(data: Dictionary) -> void:
	if save_base_path == "":
		_init_file_fallback()
	var path = save_base_path + "world.json"
	var json_str = JSON.stringify(data, "\t")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		file.close()

## Async load world state. Emits world_loaded(data) when done.
func load_world_async() -> void:
	if use_api:
		_load_world_api()
	else:
		var data = _load_world_file()
		world_loaded.emit(data)

func _load_world_api() -> void:
	var http = _get_free_http()
	if http == null:
		world_loaded.emit({})
		return
	var url = api_base_url + "/world"
	var err = http.request(url, [], HTTPClient.METHOD_GET)
	if err != OK:
		print("[SaveManager] Failed to load world via API (err=", err, ")")
		world_loaded.emit({})
		return
	var result = await http.request_completed
	var response_code = result[1] as int
	var body = (result[3] as PackedByteArray).get_string_from_utf8()
	if response_code == 200 and body != "":
		var json = JSON.new()
		var parse_err = json.parse(body)
		if parse_err == OK and json.data is Dictionary:
			world_loaded.emit(json.data as Dictionary)
			return
	world_loaded.emit({})

func _load_world_file() -> Dictionary:
	if save_base_path == "":
		_init_file_fallback()
	var path = save_base_path + "world.json"
	if not FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		print("[SaveManager] Failed to parse world save: ", path)
		return {}
	return json.data if json.data is Dictionary else {}

## Synchronous load for backward compat (editor/offline only)
func load_world() -> Dictionary:
	return _load_world_file()

# === Social PATCH (for offline player mutations) ===

## Atomically update social fields for an offline player via PATCH /api/players/:id/social.
## operations: Dictionary of atomic ops like {add_friend: "uuid", remove_incoming_request_from: "uuid", ...}
## Falls back to file I/O if no API.
func update_player_social(player_id: String, operations: Dictionary) -> void:
	if use_api:
		_patch_social_api(player_id, operations)
	else:
		_patch_social_file(player_id, operations)

func _patch_social_api(player_id: String, operations: Dictionary) -> void:
	var http = _get_free_http()
	if http == null:
		return
	var url = api_base_url + "/players/" + player_id.uri_encode() + "/social"
	var json_str = JSON.stringify(operations)
	var headers = ["Content-Type: application/json"]
	var err = http.request(url, headers, HTTPClient.METHOD_PATCH, json_str)
	if err != OK:
		print("[SaveManager] Failed to PATCH social for player ", player_id, " (err=", err, ")")

func _patch_social_file(player_id: String, operations: Dictionary) -> void:
	# File fallback: find player file by scanning save dir, load, modify social, write back
	if save_base_path == "":
		_init_file_fallback()
	var dir = DirAccess.open(save_base_path + "players")
	if dir == null:
		return
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			var path = save_base_path + "players/" + fname
			var file = FileAccess.open(path, FileAccess.READ)
			if file:
				var text = file.get_as_text()
				file.close()
				var json = JSON.new()
				if json.parse(text) == OK and json.data is Dictionary:
					var data = json.data as Dictionary
					if str(data.get("player_id", "")) == player_id:
						_apply_social_ops(data, operations)
						var out = FileAccess.open(path, FileAccess.WRITE)
						if out:
							out.store_string(JSON.stringify(data, "\t"))
							out.close()
						return
		fname = dir.get_next()

func _apply_social_ops(data: Dictionary, ops: Dictionary) -> void:
	if not data.has("social"):
		data["social"] = {"friends": [], "blocked": [], "incoming_requests": [], "outgoing_requests": []}
	var social = data["social"]
	if ops.has("add_friend"):
		if ops["add_friend"] not in social["friends"]:
			social["friends"].append(ops["add_friend"])
	if ops.has("remove_friend"):
		social["friends"].erase(ops["remove_friend"])
	if ops.has("add_blocked"):
		if ops["add_blocked"] not in social["blocked"]:
			social["blocked"].append(ops["add_blocked"])
	if ops.has("remove_blocked"):
		social["blocked"].erase(ops["remove_blocked"])
	if ops.has("add_incoming_request"):
		social["incoming_requests"].append(ops["add_incoming_request"])
	if ops.has("remove_incoming_request_from"):
		var from_id = str(ops["remove_incoming_request_from"])
		var i = social["incoming_requests"].size() - 1
		while i >= 0:
			if str(social["incoming_requests"][i].get("from_id", "")) == from_id:
				social["incoming_requests"].remove_at(i)
			i -= 1
	if ops.has("add_outgoing_request"):
		social["outgoing_requests"].append(ops["add_outgoing_request"])
	if ops.has("remove_outgoing_request_to"):
		var to_id = str(ops["remove_outgoing_request_to"])
		var i = social["outgoing_requests"].size() - 1
		while i >= 0:
			if str(social["outgoing_requests"][i].get("to_id", "")) == to_id:
				social["outgoing_requests"].remove_at(i)
			i -= 1

# === UUID Generation ===

func _generate_uuid() -> String:
	var bytes: Array = []
	for i in 16:
		bytes.append(randi() % 256)
	# Set version 4 bits
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	return "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x" % bytes
