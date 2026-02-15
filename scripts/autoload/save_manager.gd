extends Node

## Server-only autoload that handles JSON file I/O for player and world data.
## Paths: Docker uses /app/data/, local dev uses user://save/

var save_base_path: String = ""
var auto_save_timer: float = 0.0
const AUTO_SAVE_INTERVAL = 60.0

func _ready() -> void:
	# Determine save path based on environment
	if FileAccess.file_exists("/app/data/.docker_marker") or DirAccess.dir_exists_absolute("/app/data"):
		save_base_path = "/app/data/"
	else:
		save_base_path = OS.get_user_data_dir() + "/save/"
	# Ensure directories exist
	DirAccess.make_dir_recursive_absolute(save_base_path + "players")
	print("[SaveManager] Save path: ", save_base_path)

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
	# Save all connected players
	var nm = get_node_or_null("/root/NetworkManager")
	if nm and nm.get("player_data_store"):
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
				save_player(player_name, data)
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

# --- Player save/load ---

func save_player(player_name: String, data: Dictionary) -> void:
	var path = _player_path(player_name)
	var json_str = JSON.stringify(data, "\t")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		file.close()

func load_player(player_name: String) -> Dictionary:
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

func _player_path(player_name: String) -> String:
	# Sanitize player name for filename
	var safe_name = player_name.replace("/", "_").replace("\\", "_").replace(".", "_").replace(" ", "_")
	return save_base_path + "players/" + safe_name + ".json"

# --- World save/load ---

func save_world(data: Dictionary) -> void:
	var path = save_base_path + "world.json"
	var json_str = JSON.stringify(data, "\t")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		file.close()

func load_world() -> Dictionary:
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
