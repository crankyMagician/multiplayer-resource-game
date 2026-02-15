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
const BUFF_CHECK_INTERVAL = 5.0

# Rate limiting
const MAX_RPCS_PER_SECOND = 20
var _rpc_timestamps: Dictionary = {} # peer_id → Array of timestamps (msec)

var player_info: Dictionary = {"name": "Player"}
var players: Dictionary = {} # peer_id -> player_info

# Server-side: full player data for persistence
var player_data_store: Dictionary = {} # peer_id -> full data dict
var join_state: Dictionary = {} # peer_id -> {"state": String, "player_name": String, "joined_at_ms": int}

# Name uniqueness tracking (server-side)
var active_player_names: Dictionary = {} # player_name -> peer_id

var _buff_check_timer: float = 0.0

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

func _process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	# Join timeout check
	if not join_state.is_empty():
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

	# Buff expiry check
	_buff_check_timer += delta
	if _buff_check_timer >= BUFF_CHECK_INTERVAL:
		_buff_check_timer = 0.0
		_check_buff_expiry()

# === Rate Limiting ===

func _check_rate_limit(peer_id: int) -> bool:
	var now = Time.get_ticks_msec()
	if peer_id not in _rpc_timestamps:
		_rpc_timestamps[peer_id] = []
	var timestamps: Array = _rpc_timestamps[peer_id]
	# Remove timestamps older than 1 second
	var cutoff = now - 1000
	while timestamps.size() > 0 and int(timestamps[0]) < cutoff:
		timestamps.pop_front()
	if timestamps.size() >= MAX_RPCS_PER_SECOND:
		print("[RateLimit] Peer ", peer_id, " exceeded ", MAX_RPCS_PER_SECOND, " RPCs/sec — disconnecting")
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(peer_id)
		return false
	timestamps.append(now)
	return true

func _check_buff_expiry() -> void:
	var now = Time.get_unix_time_from_system()
	for peer_id in player_data_store:
		var buffs = player_data_store[peer_id].get("active_buffs", [])
		var changed = false
		var i = buffs.size() - 1
		while i >= 0:
			if float(buffs[i].get("expires_at", 0)) <= now:
				buffs.remove_at(i)
				changed = true
			i -= 1
		if changed:
			player_data_store[peer_id]["active_buffs"] = buffs
			_sync_active_buffs.rpc_id(peer_id, buffs)

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
	# Clean up rate limit tracking
	_rpc_timestamps.erase(id)
	# Clean up active name tracking
	var disconnecting_name = ""
	for pname in active_player_names:
		if active_player_names[pname] == id:
			disconnecting_name = pname
			break
	if disconnecting_name != "":
		active_player_names.erase(disconnecting_name)
		print("[Names] Released name '", disconnecting_name, "' (peer ", id, " disconnected)")
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
		# Update position from player node (use overworld position if in restaurant)
		var rest_mgr = get_node_or_null("/root/Main/GameWorld/RestaurantManager")
		if rest_mgr and id in rest_mgr.overworld_positions:
			var ow_pos = rest_mgr.overworld_positions[id]
			data["position"] = {"x": ow_pos.x, "y": ow_pos.y, "z": ow_pos.z}
		else:
			var player_node = _get_player_node(id)
			if player_node:
				data["position"] = {"x": player_node.position.x, "y": player_node.position.y, "z": player_node.position.z}
		var pname = data.get("player_name", "")
		if pname != "" and pname != "Server":
			SaveManager.save_player(data)
			print("[Save] Saved player on disconnect: ", pname)
		player_data_store.erase(id)
	players.erase(id)
	player_disconnected.emit(id)

func _on_connected_to_server() -> void:
	print("Connected to server!")
	connection_succeeded.emit()
	# Load game world FIRST so MultiplayerSpawner exists before any spawn RPCs arrive.
	GameManager.start_game()
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

# === Name Validation ===

func _validate_player_name(name: String) -> String:
	# Strip leading/trailing whitespace
	var clean = name.strip_edges()
	# Allow only alphanumeric, spaces, underscores, hyphens
	var regex = RegEx.new()
	regex.compile("[^a-zA-Z0-9 _\\-]")
	clean = regex.sub(clean, "", true)
	# Enforce length
	if clean.length() < 2:
		return ""
	if clean.length() > 16:
		clean = clean.substr(0, 16)
	return clean

# === UUID Generation ===

func _generate_uuid() -> String:
	var bytes: Array = []
	for i in 16:
		bytes.append(randi() % 256)
	# Set version 4 bits
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	return "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x" % bytes

# === Creature UUID Backfill ===

func _backfill_creature_ids(data: Dictionary) -> void:
	for creature in data.get("party", []):
		if not creature.has("creature_id") or creature["creature_id"] == "":
			creature["creature_id"] = _generate_uuid()
		_backfill_creature_stats(creature)
	for creature in data.get("creature_storage", []):
		if not creature.has("creature_id") or creature["creature_id"] == "":
			creature["creature_id"] = _generate_uuid()
		_backfill_creature_stats(creature)

func _backfill_creature_stats(creature: Dictionary) -> void:
	# Backfill IVs for old saves
	if not creature.has("ivs") or creature["ivs"].is_empty():
		creature["ivs"] = {}
		for stat in ["hp", "attack", "defense", "sp_attack", "sp_defense", "speed"]:
			creature["ivs"][stat] = randi_range(0, 31)
	# Backfill bond data
	if not creature.has("bond_points"):
		creature["bond_points"] = 0
	if not creature.has("bond_level"):
		creature["bond_level"] = 0
	if not creature.has("battle_affinities"):
		creature["battle_affinities"] = {}

# === Join Flow RPCs ===

@rpc("any_peer", "reliable")
func request_join(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if not _check_rate_limit(sender_id):
		return
	print("Join request from peer ", sender_id, ": ", player_name)

	# Validate name
	var clean_name = _validate_player_name(player_name)
	if clean_name == "":
		print("  -> Rejected: invalid name '", player_name, "'")
		_join_rejected.rpc_id(sender_id, "Invalid name. Use 2-16 characters (letters, numbers, spaces, underscores).")
		return

	# Check name uniqueness (already online)
	if clean_name in active_player_names:
		print("  -> Rejected: name '", clean_name, "' already online (peer ", active_player_names[clean_name], ")")
		_join_rejected.rpc_id(sender_id, "Name '" + clean_name + "' is already in use by another player.")
		return

	# Track pending join
	join_state[sender_id] = {
		"state": "loading",
		"player_name": clean_name,
		"joined_at_ms": Time.get_ticks_msec()
	}

	# Async load via SaveManager
	SaveManager.player_loaded.connect(_on_player_loaded.bind(sender_id, clean_name), CONNECT_ONE_SHOT)
	SaveManager.load_player_async(clean_name)

func _on_player_loaded(loaded_name: String, data: Dictionary, sender_id: int, expected_name: String) -> void:
	# Verify this callback matches the expected join
	if loaded_name != expected_name:
		return
	if sender_id not in join_state or join_state[sender_id].get("state", "") != "loading":
		return
	# Check peer is still connected
	if not multiplayer.multiplayer_peer:
		return

	if data.is_empty():
		# New player — create with UUID
		var default_data = _create_default_player_data(expected_name)
		SaveManager.player_created.connect(_on_player_created.bind(sender_id, expected_name), CONNECT_ONE_SHOT)
		SaveManager.create_player_async(default_data)
		print("  -> New player, creating with UUID...")
	else:
		# Existing player loaded
		print("  -> Loaded saved data for ", expected_name)
		_finalize_join(sender_id, expected_name, data)

func _on_player_created(created_name: String, data: Dictionary, sender_id: int, expected_name: String) -> void:
	if created_name != expected_name:
		return
	if sender_id not in join_state or join_state[sender_id].get("state", "") != "loading":
		return
	if data.is_empty():
		print("  -> Failed to create player for ", expected_name)
		_join_rejected.rpc_id(sender_id, "Server error: failed to create player data.")
		join_state.erase(sender_id)
		return
	print("  -> Created new player with UUID: ", data.get("player_id", "?"))
	_finalize_join(sender_id, expected_name, data)

func _finalize_join(sender_id: int, player_name: String, data: Dictionary) -> void:
	# Backfill creature IDs for old saves
	_backfill_creature_ids(data)
	# Backfill player color for old saves that lack it
	var pc = data.get("player_color", {})
	if not pc is Dictionary or pc.is_empty():
		data["player_color"] = _generate_player_color(sender_id)
	# Backfill equipped_tools for old saves
	if not data.has("equipped_tools") or not data["equipped_tools"] is Dictionary or data["equipped_tools"].is_empty():
		data["equipped_tools"] = {"hoe": "tool_hoe_basic", "axe": "tool_axe_basic", "watering_can": "tool_watering_can_basic"}
	# Backfill known_recipes/active_buffs/storage
	if not data.has("known_recipes"):
		data["known_recipes"] = []
	if not data.has("active_buffs"):
		data["active_buffs"] = []
	if not data.has("creature_storage"):
		data["creature_storage"] = []
	if not data.has("storage_capacity"):
		data["storage_capacity"] = 10
	if not data.has("restaurant"):
		data["restaurant"] = {
			"restaurant_index": -1,
			"tier": 0,
			"name": player_name + "'s Restaurant",
			"farm_plots": [],
			"appliances": {},
			"permissions": {
				"default": {"water": false, "harvest": false, "craft": false},
				"overrides": {},
			},
		}
	# Backfill basic tools in inventory
	var inv = data.get("inventory", {})
	for tool_id in ["tool_hoe_basic", "tool_axe_basic", "tool_watering_can_basic"]:
		if tool_id not in inv:
			inv[tool_id] = 1
	data["inventory"] = inv
	# Allocate restaurant index if needed
	var rest = data.get("restaurant", {})
	if rest.get("restaurant_index", -1) == -1:
		var rm = get_node_or_null("/root/Main/GameWorld/RestaurantManager")
		if rm:
			rest["restaurant_index"] = rm.allocate_restaurant_index(player_name)
			data["restaurant"] = rest
	# Store server-side
	player_data_store[sender_id] = data
	active_player_names[player_name] = sender_id
	join_state[sender_id] = {
		"state": "pending_world_ready",
		"player_name": player_name,
		"joined_at_ms": Time.get_ticks_msec()
	}
	# Send data to client
	_receive_player_data.rpc_id(sender_id, data)

@rpc("authority", "reliable")
func _join_rejected(reason: String) -> void:
	print("[NetworkManager] Join rejected: ", reason)
	# Disconnect and show error to player
	multiplayer.multiplayer_peer = null
	connection_failed.emit()

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
		"moves": ["grain_bash", "quick_bite", "bread_wall", "syrup_trap"],
		"pp": [15, 25, 10, 10],
		"types": ["grain"],
		"xp": 0,
		"xp_to_next": 100,
		"ability_id": "crusty_armor",
		"held_item_id": "",
		"evs": {},
		"creature_id": _generate_uuid(),
	}
	return {
		"player_name": player_name,
		"inventory": {
			"tool_hoe_basic": 1,
			"tool_axe_basic": 1,
			"tool_watering_can_basic": 1,
		},
		"party": [starter],
		"position": {},
		"watering_can_current": 10,
		"money": 0,
		"defeated_trainers": {},
		"player_color": {},
		"equipped_tools": {
			"hoe": "tool_hoe_basic",
			"axe": "tool_axe_basic",
			"watering_can": "tool_watering_can_basic",
		},
		"known_recipes": [],
		"active_buffs": [],
		"creature_storage": [],
		"storage_capacity": 10,
		"restaurant": {
			"restaurant_index": -1,
			"tier": 0,
			"name": player_name + "'s Restaurant",
			"farm_plots": [],
			"appliances": {},
			"permissions": {
				"default": {"water": false, "harvest": false, "craft": false},
				"overrides": {},
			},
		},
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

func server_has_inventory(peer_id: int, item_id: String, amount: int = 1) -> bool:
	if peer_id not in player_data_store:
		return false
	var inv = player_data_store[peer_id].get("inventory", {})
	return item_id in inv and inv[item_id] >= amount

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
	player_data_store[peer_id]["party"] = party_array.duplicate(true)

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
	player_data_store[peer_id]["watering_can_current"] = server_get_watering_can_capacity(peer_id)

func server_get_watering_can_capacity(peer_id: int) -> int:
	if peer_id not in player_data_store:
		return 10
	DataRegistry.ensure_loaded()
	var et = player_data_store[peer_id].get("equipped_tools", {})
	var tool_id = et.get("watering_can", "tool_watering_can_basic")
	var tool_def = DataRegistry.get_tool(tool_id)
	if tool_def:
		return int(tool_def.effectiveness.get("capacity", 10))
	return 10

# === Recipe System ===

func server_add_known_recipe(peer_id: int, recipe_id: String) -> bool:
	if peer_id not in player_data_store:
		return false
	var recipes = player_data_store[peer_id].get("known_recipes", [])
	if recipe_id in recipes:
		return false
	recipes.append(recipe_id)
	player_data_store[peer_id]["known_recipes"] = recipes
	_sync_known_recipes.rpc_id(peer_id, recipes)
	return true

func server_has_known_recipe(peer_id: int, recipe_id: String) -> bool:
	if peer_id not in player_data_store:
		return false
	var recipes = player_data_store[peer_id].get("known_recipes", [])
	return recipe_id in recipes

# === Buff System ===

func server_add_buff(peer_id: int, buff_type: String, buff_value: float, duration_sec: float) -> void:
	if peer_id not in player_data_store:
		return
	var buffs = player_data_store[peer_id].get("active_buffs", [])
	# Remove existing buff of same type
	var i = buffs.size() - 1
	while i >= 0:
		if buffs[i].get("buff_type", "") == buff_type:
			buffs.remove_at(i)
		i -= 1
	var expires_at = Time.get_unix_time_from_system() + duration_sec
	buffs.append({"buff_type": buff_type, "buff_value": buff_value, "expires_at": expires_at})
	player_data_store[peer_id]["active_buffs"] = buffs
	_sync_active_buffs.rpc_id(peer_id, buffs)

func server_get_active_buffs(peer_id: int) -> Array:
	if peer_id not in player_data_store:
		return []
	return player_data_store[peer_id].get("active_buffs", [])

func server_has_buff(peer_id: int, buff_type: String) -> bool:
	var now = Time.get_unix_time_from_system()
	for buff in server_get_active_buffs(peer_id):
		if buff.get("buff_type", "") == buff_type and float(buff.get("expires_at", 0)) > now:
			return true
	return false

func server_get_buff_value(peer_id: int, buff_type: String) -> float:
	var now = Time.get_unix_time_from_system()
	for buff in server_get_active_buffs(peer_id):
		if buff.get("buff_type", "") == buff_type and float(buff.get("expires_at", 0)) > now:
			return float(buff.get("buff_value", 0.0))
	return 0.0

# === Tool System ===

func server_equip_tool(peer_id: int, slot: String, tool_id: String) -> bool:
	if peer_id not in player_data_store:
		return false
	if not server_has_inventory(peer_id, tool_id):
		return false
	DataRegistry.ensure_loaded()
	var tool_def = DataRegistry.get_tool(tool_id)
	if tool_def == null:
		return false
	if tool_def.tool_type != slot:
		return false
	var et = player_data_store[peer_id].get("equipped_tools", {})
	et[slot] = tool_id
	player_data_store[peer_id]["equipped_tools"] = et
	# Update watering can capacity if applicable
	if slot == "watering_can":
		var cap = int(tool_def.effectiveness.get("capacity", 10))
		var current = int(player_data_store[peer_id].get("watering_can_current", 0))
		if current > cap:
			player_data_store[peer_id]["watering_can_current"] = cap
	_sync_equipped_tools.rpc_id(peer_id, et)
	return true

# === NPC Friendship stubs ===

func server_get_npc_friendship(_peer_id: int, _npc_id: String) -> int:
	return 0

func server_add_npc_friendship(_peer_id: int, _npc_id: String, _amount: int) -> void:
	pass

func server_check_friendship_recipe_unlock(_peer_id: int, _npc_id: String) -> void:
	pass

# === Utility ===

func is_server() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()

func _get_player_node(peer_id: int) -> Node3D:
	var players_node = get_node_or_null("/root/Main/GameWorld/Players")
	if players_node:
		return players_node.get_node_or_null(str(peer_id))
	return null

# === New RPCs ===

@rpc("authority", "reliable")
func _sync_known_recipes(recipes: Array) -> void:
	PlayerData.known_recipes = recipes.duplicate()
	PlayerData.known_recipes_changed.emit()

@rpc("authority", "reliable")
func _sync_active_buffs(buffs: Array) -> void:
	PlayerData.active_buffs = buffs.duplicate()
	PlayerData.buffs_changed.emit()

@rpc("authority", "reliable")
func _sync_equipped_tools(tools_dict: Dictionary) -> void:
	PlayerData.equipped_tools = tools_dict.duplicate()
	PlayerData.tool_changed.emit(PlayerData.current_tool_slot)

@rpc("authority", "reliable")
func _notify_recipe_unlocked(recipe_id: String, recipe_name: String) -> void:
	print("Recipe unlocked: ", recipe_name)
	if recipe_id not in PlayerData.known_recipes:
		PlayerData.known_recipes.append(recipe_id)
		PlayerData.known_recipes_changed.emit()

@rpc("authority", "reliable")
func _sync_inventory_full(new_inventory: Dictionary) -> void:
	PlayerData.inventory.clear()
	for key in new_inventory:
		PlayerData.inventory[key] = int(new_inventory[key])
	PlayerData.inventory_changed.emit()

@rpc("authority", "reliable")
func _sync_money(amount: int) -> void:
	PlayerData.money = amount

@rpc("authority", "reliable")
func _sync_party_full(party_array: Array) -> void:
	PlayerData.party = party_array.duplicate(true)
	PlayerData.party_changed.emit()

# === Client->Server RPCs ===

@rpc("any_peer", "reliable")
func request_use_food(food_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if not _check_rate_limit(sender):
		return
	if not server_has_inventory(sender, food_id):
		return
	DataRegistry.ensure_loaded()
	var food = DataRegistry.get_food(food_id)
	if food == null:
		return
	# Consume the food
	server_remove_inventory(sender, food_id, 1)
	_sync_inventory_full.rpc_id(sender, player_data_store[sender].get("inventory", {}))

	match food.buff_type:
		"creature_heal":
			# Heal all creatures
			var party = player_data_store[sender].get("party", [])
			for creature in party:
				creature["hp"] = creature.get("max_hp", 40)
			player_data_store[sender]["party"] = party
			_sync_party_full.rpc_id(sender, party)
			print("[Food] ", sender, " used ", food.display_name, " — healed all creatures")
		"speed_boost", "xp_multiplier", "encounter_rate":
			server_add_buff(sender, food.buff_type, food.buff_value, food.buff_duration_sec)
			print("[Food] ", sender, " used ", food.display_name, " — ", food.buff_type, " x", food.buff_value, " for ", food.buff_duration_sec, "s")
		_:
			print("[Food] ", sender, " used ", food.display_name, " (no effect)")

@rpc("any_peer", "reliable")
func request_use_recipe_scroll(scroll_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if not _check_rate_limit(sender):
		return
	if not server_has_inventory(sender, scroll_id):
		return
	DataRegistry.ensure_loaded()
	var scroll = DataRegistry.get_recipe_scroll(scroll_id)
	if scroll == null:
		return
	# Check if already known
	if server_has_known_recipe(sender, scroll.unlocks_recipe_id):
		return
	# Consume scroll and unlock recipe
	server_remove_inventory(sender, scroll_id, 1)
	server_add_known_recipe(sender, scroll.unlocks_recipe_id)
	var recipe = DataRegistry.get_recipe(scroll.unlocks_recipe_id)
	var recipe_name = recipe.display_name if recipe else scroll.unlocks_recipe_id
	_notify_recipe_unlocked.rpc_id(sender, scroll.unlocks_recipe_id, recipe_name)
	_sync_inventory_full.rpc_id(sender, player_data_store[sender].get("inventory", {}))
	print("[Scroll] ", sender, " unlocked recipe: ", recipe_name)

@rpc("any_peer", "reliable")
func request_equip_held_item(creature_idx: int, item_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if not _check_rate_limit(sender):
		return
	if sender not in player_data_store:
		return
	var party = player_data_store[sender].get("party", [])
	if creature_idx < 0 or creature_idx >= party.size():
		return
	if not server_has_inventory(sender, item_id):
		return
	DataRegistry.ensure_loaded()
	var held_item = DataRegistry.get_held_item(item_id)
	if held_item == null:
		return
	# Unequip current item if any
	var current_item = party[creature_idx].get("held_item_id", "")
	if current_item != "":
		server_add_inventory(sender, current_item, 1)
	# Equip new item
	server_remove_inventory(sender, item_id, 1)
	party[creature_idx]["held_item_id"] = item_id
	player_data_store[sender]["party"] = party
	_sync_party_full.rpc_id(sender, party)
	_sync_inventory_full.rpc_id(sender, player_data_store[sender].get("inventory", {}))

@rpc("any_peer", "reliable")
func request_unequip_held_item(creature_idx: int) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if not _check_rate_limit(sender):
		return
	if sender not in player_data_store:
		return
	var party = player_data_store[sender].get("party", [])
	if creature_idx < 0 or creature_idx >= party.size():
		return
	var current_item = party[creature_idx].get("held_item_id", "")
	if current_item == "":
		return
	# Return to inventory
	server_add_inventory(sender, current_item, 1)
	party[creature_idx]["held_item_id"] = ""
	player_data_store[sender]["party"] = party
	_sync_party_full.rpc_id(sender, party)
	_sync_inventory_full.rpc_id(sender, player_data_store[sender].get("inventory", {}))

@rpc("any_peer", "reliable")
func request_sell_item(item_id: String, qty: int) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if not _check_rate_limit(sender):
		return
	if qty <= 0:
		return
	if not server_has_inventory(sender, item_id, qty):
		return
	DataRegistry.ensure_loaded()
	var food = DataRegistry.get_food(item_id)
	if food == null or food.sell_price <= 0:
		return
	var total = food.sell_price * qty
	server_remove_inventory(sender, item_id, qty)
	server_add_money(sender, total)
	_sync_inventory_full.rpc_id(sender, player_data_store[sender].get("inventory", {}))
	_sync_money.rpc_id(sender, int(player_data_store[sender].get("money", 0)))
	print("[Sell] ", sender, " sold ", qty, "x ", food.display_name, " for $", total)

@rpc("any_peer", "reliable")
func request_equip_tool(tool_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if not _check_rate_limit(sender):
		return
	DataRegistry.ensure_loaded()
	var tool_def = DataRegistry.get_tool(tool_id)
	if tool_def == null:
		return
	server_equip_tool(sender, tool_def.tool_type, tool_id)

# === Creature Storage ===

const STORAGE_TIERS = [
	{"name": "Pantry", "capacity": 10, "cost": 0, "ingredients": {}},
	{"name": "Cold Storage", "capacity": 20, "cost": 500, "ingredients": {}},
	{"name": "Walk-in Freezer", "capacity": 30, "cost": 2000, "ingredients": {"sweet_crystal": 5}},
	{"name": "Deep Freeze Vault", "capacity": 50, "cost": 5000, "ingredients": {"sweet_crystal": 8, "frost_essence": 5}},
]

func server_deposit_creature(peer_id: int, party_idx: int) -> bool:
	if peer_id not in player_data_store:
		return false
	var party = player_data_store[peer_id].get("party", [])
	var storage = player_data_store[peer_id].get("creature_storage", [])
	var capacity = int(player_data_store[peer_id].get("storage_capacity", 10))
	# Must keep at least 1 creature in party
	if party.size() <= 1:
		return false
	if party_idx < 0 or party_idx >= party.size():
		return false
	if storage.size() >= capacity:
		return false
	var creature = party[party_idx]
	party.remove_at(party_idx)
	storage.append(creature)
	player_data_store[peer_id]["party"] = party
	player_data_store[peer_id]["creature_storage"] = storage
	return true

func server_withdraw_creature(peer_id: int, storage_idx: int) -> bool:
	if peer_id not in player_data_store:
		return false
	var party = player_data_store[peer_id].get("party", [])
	var storage = player_data_store[peer_id].get("creature_storage", [])
	if party.size() >= PlayerData.MAX_PARTY_SIZE:
		return false
	if storage_idx < 0 or storage_idx >= storage.size():
		return false
	var creature = storage[storage_idx]
	storage.remove_at(storage_idx)
	party.append(creature)
	player_data_store[peer_id]["party"] = party
	player_data_store[peer_id]["creature_storage"] = storage
	return true

func _get_storage_tier(capacity: int) -> int:
	for i in range(STORAGE_TIERS.size()):
		if STORAGE_TIERS[i]["capacity"] == capacity:
			return i
	return 0

@rpc("any_peer", "reliable")
func request_deposit_creature(party_idx: int) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if not _check_rate_limit(sender):
		return
	if server_deposit_creature(sender, party_idx):
		_sync_party_full.rpc_id(sender, player_data_store[sender].get("party", []))
		_sync_storage_full.rpc_id(sender, player_data_store[sender].get("creature_storage", []), int(player_data_store[sender].get("storage_capacity", 10)))
		print("[Storage] ", sender, " deposited creature from party slot ", party_idx)

@rpc("any_peer", "reliable")
func request_withdraw_creature(storage_idx: int) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if not _check_rate_limit(sender):
		return
	if server_withdraw_creature(sender, storage_idx):
		_sync_party_full.rpc_id(sender, player_data_store[sender].get("party", []))
		_sync_storage_full.rpc_id(sender, player_data_store[sender].get("creature_storage", []), int(player_data_store[sender].get("storage_capacity", 10)))
		print("[Storage] ", sender, " withdrew creature from storage slot ", storage_idx)

@rpc("any_peer", "reliable")
func request_upgrade_storage(tier: int) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if not _check_rate_limit(sender):
		return
	if sender not in player_data_store:
		return
	if tier < 0 or tier >= STORAGE_TIERS.size():
		return
	var current_capacity = int(player_data_store[sender].get("storage_capacity", 10))
	var current_tier = _get_storage_tier(current_capacity)
	if tier <= current_tier:
		return
	var tier_data = STORAGE_TIERS[tier]
	# Check money
	if not server_remove_money(sender, tier_data["cost"]):
		return
	# Check and deduct ingredients
	var ingredients = tier_data["ingredients"] as Dictionary
	for item_id in ingredients:
		if not server_has_inventory(sender, item_id, int(ingredients[item_id])):
			# Refund money
			server_add_money(sender, tier_data["cost"])
			return
	for item_id in ingredients:
		server_remove_inventory(sender, item_id, int(ingredients[item_id]))
	# Apply upgrade
	player_data_store[sender]["storage_capacity"] = tier_data["capacity"]
	_sync_storage_full.rpc_id(sender, player_data_store[sender].get("creature_storage", []), tier_data["capacity"])
	_sync_inventory_full.rpc_id(sender, player_data_store[sender].get("inventory", {}))
	_sync_money.rpc_id(sender, int(player_data_store[sender].get("money", 0)))
	print("[Storage] ", sender, " upgraded to ", tier_data["name"], " (capacity: ", tier_data["capacity"], ")")

@rpc("authority", "reliable")
func _sync_storage_full(storage: Array, capacity: int) -> void:
	PlayerData.creature_storage = storage.duplicate(true)
	PlayerData.storage_capacity = capacity
	PlayerData.storage_changed.emit()

# === Fragment auto-combine ===

func _check_fragment_combine(peer_id: int, fragment_id: String) -> void:
	if not fragment_id.begins_with("fragment_"):
		return
	var scroll_id = fragment_id.substr(9) # Remove "fragment_" prefix
	DataRegistry.ensure_loaded()
	var scroll_def = DataRegistry.get_recipe_scroll(scroll_id)
	if scroll_def == null or scroll_def.fragment_count <= 0:
		return
	var inv = player_data_store[peer_id].get("inventory", {})
	var count = inv.get(fragment_id, 0)
	if count >= scroll_def.fragment_count:
		# Combine fragments into scroll
		server_remove_inventory(peer_id, fragment_id, scroll_def.fragment_count)
		server_add_inventory(peer_id, scroll_id, 1)
		_sync_inventory_full.rpc_id(peer_id, player_data_store[peer_id].get("inventory", {}))
		_notify_recipe_unlocked.rpc_id(peer_id, "", "Assembled " + scroll_def.display_name + "!")
		print("[Fragment] ", peer_id, " assembled ", scroll_def.display_name, " from ", scroll_def.fragment_count, " fragments")

# === Move Relearner ===

@rpc("any_peer", "reliable")
func request_relearn_move(creature_idx: int, new_move_id: String, replace_idx: int) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if not _check_rate_limit(sender):
		return
	if sender not in player_data_store:
		return
	var party = player_data_store[sender].get("party", [])
	if creature_idx < 0 or creature_idx >= party.size():
		return
	var creature = party[creature_idx]
	# Validate: move must be in species learnset at level <= creature's level
	DataRegistry.ensure_loaded()
	var species = DataRegistry.get_species(creature.get("species_id", ""))
	if species == null:
		return
	var level = creature.get("level", 1)
	var found_in_learnset = false
	for lvl in species.learnset:
		if int(lvl) <= level and species.learnset[lvl] == new_move_id:
			found_in_learnset = true
			break
	if not found_in_learnset:
		return
	# Check that new_move_id isn't already known
	var moves = creature.get("moves", [])
	if new_move_id in moves:
		return
	# Replace
	if replace_idx < 0 or replace_idx >= moves.size():
		return
	if moves is PackedStringArray:
		moves = Array(moves)
	moves[replace_idx] = new_move_id
	creature["moves"] = moves
	# Reset PP for new move
	var move_def = DataRegistry.get_move(new_move_id)
	var pp_arr = creature.get("pp", [])
	if pp_arr is PackedInt32Array:
		pp_arr = Array(pp_arr)
	if replace_idx < pp_arr.size():
		pp_arr[replace_idx] = move_def.pp if move_def else 10
	creature["pp"] = pp_arr
	player_data_store[sender]["party"] = party
	_sync_party_full.rpc_id(sender, party)
	print("[Relearn] ", sender, " relearned ", new_move_id, " on creature ", creature_idx)

# === Feed Creature (Bond Points) ===

@rpc("any_peer", "reliable")
func request_feed_creature(creature_idx: int, food_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if not _check_rate_limit(sender):
		return
	if sender not in player_data_store:
		return
	var party = player_data_store[sender].get("party", [])
	if creature_idx < 0 or creature_idx >= party.size():
		return
	if not server_has_inventory(sender, food_id):
		return
	DataRegistry.ensure_loaded()
	var food = DataRegistry.get_food(food_id)
	if food == null:
		return
	# Consume food and grant bond points
	server_remove_inventory(sender, food_id, 1)
	var creature = party[creature_idx]
	creature["bond_points"] = creature.get("bond_points", 0) + 15
	creature["bond_level"] = CreatureInstance.compute_bond_level(creature["bond_points"])
	player_data_store[sender]["party"] = party
	_sync_party_full.rpc_id(sender, party)
	_sync_inventory_full.rpc_id(sender, player_data_store[sender].get("inventory", {}))
	print("[Bond] ", sender, " fed creature ", creature_idx, " with ", food_id, " — bond now ", creature["bond_points"])

# === Bond Points — Battle Win ===

func server_grant_bond_points_battle(peer_id: int) -> void:
	if peer_id not in player_data_store:
		return
	var party = player_data_store[peer_id].get("party", [])
	for creature in party:
		if creature.get("hp", 0) > 0:
			creature["bond_points"] = creature.get("bond_points", 0) + 10
			creature["bond_level"] = CreatureInstance.compute_bond_level(creature["bond_points"])

# === Bond Points — Time in Party (called from auto-save tick) ===

func server_tick_bond_time(peer_id: int) -> void:
	if peer_id not in player_data_store:
		return
	var party = player_data_store[peer_id].get("party", [])
	for creature in party:
		creature["bond_points"] = creature.get("bond_points", 0) + 1
		creature["bond_level"] = CreatureInstance.compute_bond_level(creature["bond_points"])
