extends Node

signal player_connected(peer_id: int, player_info: Dictionary)
signal player_disconnected(peer_id: int)
signal server_disconnected()
signal connection_failed()
signal connection_succeeded()
signal player_data_received()

const PORT = 7777
const MAX_CLIENTS = 32
const JOIN_READY_TIMEOUT_MS = 15000

var player_info: Dictionary = {"name": "Player"}
var players: Dictionary = {} # peer_id -> player_info

# Server-side: full player data for persistence
var player_data_store: Dictionary = {} # peer_id -> full data dict
var join_state: Dictionary = {} # peer_id -> {"state": String, "player_name": String, "joined_at_ms": int}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	var is_dedicated := DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server") or _has_server_flag()
	if is_dedicated:
		print("Server mode detected — auto-starting server...")
		host_game("Server")
		GameManager.start_game()

static func _has_server_flag() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg == "--server" or arg == "--role=server" or arg == "--instance-index=0":
			return true
	return false

func _process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	if join_state.is_empty():
		return
	var now = Time.get_ticks_msec()
	var timed_out: Array[int] = []
	for peer_id in join_state:
		var state = join_state[peer_id].get("state", "")
		if state == "active":
			continue
		var joined_at = int(join_state[peer_id].get("joined_at_ms", now))
		if now - joined_at >= JOIN_READY_TIMEOUT_MS:
			timed_out.append(peer_id)
	for peer_id in timed_out:
		var pending_name = str(join_state[peer_id].get("player_name", "unknown"))
		print("Join ready timeout for peer ", peer_id, " (", pending_name, "), disconnecting")
		join_state.erase(peer_id)
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(peer_id)

func host_game(player_name: String = "Host") -> Error:
	player_info.name = player_name
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT, MAX_CLIENTS)
	if error:
		print("Failed to create server: ", error)
		return error
	multiplayer.multiplayer_peer = peer
	players[1] = player_info
	print("Server started on port ", PORT)
	return OK

func join_game(address: String = "127.0.0.1", player_name: String = "Client") -> Error:
	player_info.name = player_name
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, PORT)
	if error:
		print("Failed to create client: ", error)
		return error
	multiplayer.multiplayer_peer = peer
	print("Connecting to ", address, ":", PORT)
	return OK

func _on_peer_connected(id: int) -> void:
	print("Peer connected: ", id)

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: ", id)
	join_state.erase(id)
	# Handle battle disconnect (PvP forfeit, cleanup)
	var battle_mgr = get_node_or_null("/root/Main/GameWorld/BattleManager")
	if battle_mgr:
		battle_mgr.handle_player_disconnect(id)
	var encounter_mgr = get_node_or_null("/root/Main/GameWorld/EncounterManager")
	if encounter_mgr:
		encounter_mgr.end_encounter(id)
	# Save player data before removing
	if id in player_data_store:
		var data = player_data_store[id]
		# Update position from player node
		var player_node = _get_player_node(id)
		if player_node:
			data["position"] = {"x": player_node.position.x, "y": player_node.position.y, "z": player_node.position.z}
		var pname = data.get("player_name", "")
		if pname != "" and pname != "Server":
			SaveManager.save_player(pname, data)
			print("[Save] Saved player on disconnect: ", pname)
		player_data_store.erase(id)
	players.erase(id)
	player_disconnected.emit(id)

func _on_connected_to_server() -> void:
	print("Connected to server!")
	connection_succeeded.emit()
	# Send join request with our name
	request_join.rpc_id(1, player_info.name)

func _on_connection_failed() -> void:
	print("Connection failed!")
	multiplayer.multiplayer_peer = null
	connection_failed.emit()

func _on_server_disconnected() -> void:
	print("Server disconnected!")
	multiplayer.multiplayer_peer = null
	players.clear()
	PlayerData.reset()
	GameManager.end_game()
	get_tree().reload_current_scene()
	server_disconnected.emit()

# === Join Flow RPCs ===

@rpc("any_peer", "reliable")
func request_join(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	print("Join request from peer ", sender_id, ": ", player_name)
	# Load or create player data
	var data = SaveManager.load_player(player_name)
	if data.is_empty():
		data = _create_default_player_data(player_name)
		print("  -> New player, created default data")
	else:
		print("  -> Loaded saved data for ", player_name)
	# Backfill player color for old saves that lack it
	var pc = data.get("player_color", {})
	if not pc is Dictionary or pc.is_empty():
		data["player_color"] = _generate_player_color(sender_id)
	# Store server-side
	player_data_store[sender_id] = data
	join_state[sender_id] = {
		"state": "pending_world_ready",
		"player_name": player_name,
		"joined_at_ms": Time.get_ticks_msec()
	}
	# Send data to client
	_receive_player_data.rpc_id(sender_id, data)

@rpc("authority", "reliable")
func _receive_player_data(data: Dictionary) -> void:
	PlayerData.load_from_server(data)
	GameManager.start_game()
	player_data_received.emit()
	_send_ready_when_world_loaded.call_deferred()

func _send_ready_when_world_loaded() -> void:
	var spawn_ready = await _wait_for_spawn_path_ready()
	if not spawn_ready:
		print("Client world did not become spawn-ready in time; skipping ready ack")
		return
	if multiplayer.multiplayer_peer == null:
		return
	client_ready_for_spawn.rpc_id(1)

func _wait_for_spawn_path_ready(timeout_sec: float = 8.0) -> bool:
	var deadline = Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var game_world = get_node_or_null("/root/Main/GameWorld")
		if game_world and game_world.has_method("has_spawn_path_ready") and game_world.has_spawn_path_ready():
			return true
		if get_node_or_null("/root/Main/GameWorld/Players/MultiplayerSpawner"):
			return true
		await get_tree().process_frame
	return false

@rpc("any_peer", "reliable")
func client_ready_for_spawn() -> void:
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id not in join_state:
		print("Ignoring ready ack from unknown peer ", sender_id)
		return
	var state = str(join_state[sender_id].get("state", ""))
	if state == "active":
		return
	var info = {"name": str(join_state[sender_id].get("player_name", "Player"))}
	players[sender_id] = info
	join_state[sender_id]["state"] = "active"
	print("Client ready for spawn: ", sender_id)
	player_connected.emit(sender_id, info)

func _generate_player_color(peer_id: int) -> Dictionary:
	# Golden-angle hue distribution for visually distinct colors
	var hue = fmod(peer_id * 0.618033988749895, 1.0)
	var c = Color.from_hsv(hue, 0.7, 0.9)
	return {"r": c.r, "g": c.g, "b": c.b}

func _create_default_player_data(player_name: String) -> Dictionary:
	var starter = {
		"species_id": "rice_ball",
		"nickname": "Rice Ball",
		"level": 5,
		"hp": 45,
		"max_hp": 45,
		"attack": 12,
		"defense": 14,
		"sp_attack": 10,
		"sp_defense": 14,
		"speed": 10,
		"moves": ["grain_bash", "quick_bite", "bread_wall", "taste_test"],
		"pp": [15, 25, 10, 5],
		"types": ["grain"],
		"xp": 0,
		"xp_to_next": 100,
		"ability_id": "crusty_armor",
		"held_item_id": "",
		"evs": {},
	}
	return {
		"player_name": player_name,
		"inventory": {},
		"party": [starter],
		"position": {"x": 0.0, "y": 1.0, "z": 3.0},
		"watering_can_current": 10,
		"money": 0,
		"defeated_trainers": {},
		"player_color": {},
	}

# === Server-side player data tracking ===

func server_add_inventory(peer_id: int, item_id: String, amount: int) -> void:
	if peer_id not in player_data_store:
		return
	var inv = player_data_store[peer_id].get("inventory", {})
	if item_id in inv:
		inv[item_id] = inv[item_id] + amount
	else:
		inv[item_id] = amount
	player_data_store[peer_id]["inventory"] = inv

func server_remove_inventory(peer_id: int, item_id: String, amount: int) -> bool:
	if peer_id not in player_data_store:
		return false
	var inv = player_data_store[peer_id].get("inventory", {})
	if item_id not in inv or inv[item_id] < amount:
		return false
	inv[item_id] -= amount
	if inv[item_id] <= 0:
		inv.erase(item_id)
	player_data_store[peer_id]["inventory"] = inv
	return true

func server_add_money(peer_id: int, amount: int) -> void:
	if peer_id not in player_data_store:
		return
	var current = int(player_data_store[peer_id].get("money", 0))
	player_data_store[peer_id]["money"] = current + amount

func server_remove_money(peer_id: int, amount: int) -> bool:
	if peer_id not in player_data_store:
		return false
	var current = int(player_data_store[peer_id].get("money", 0))
	if current < amount:
		return false
	player_data_store[peer_id]["money"] = current - amount
	return true

func server_update_party(peer_id: int, party_array: Array) -> void:
	if peer_id not in player_data_store:
		return
	player_data_store[peer_id]["party"] = party_array

func server_use_watering_can(peer_id: int) -> bool:
	if peer_id not in player_data_store:
		return false
	var current = int(player_data_store[peer_id].get("watering_can_current", 0))
	if current <= 0:
		return false
	player_data_store[peer_id]["watering_can_current"] = current - 1
	return true

func server_refill_watering_can(peer_id: int) -> void:
	if peer_id not in player_data_store:
		return
	player_data_store[peer_id]["watering_can_current"] = 10

func is_server() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()

func _get_player_node(peer_id: int) -> Node3D:
	var players_node = get_node_or_null("/root/Main/GameWorld/Players")
	if players_node:
		return players_node.get_node_or_null(str(peer_id))
	return null
