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
const CREATOR_TIMEOUT_MS = 300000 # 5 min for character creation
const BUFF_CHECK_INTERVAL = 5.0

# Bank system
const BANK_INTEREST_RATE: float = 0.005
const BANK_MAX_DAILY_INTEREST: int = 500
const BANK_MIN_BALANCE: int = 100
const BANK_WITHDRAWAL_FEE: float = 0.02

# Rate limiting
const MAX_RPCS_PER_SECOND = 20
var _rpc_timestamps: Dictionary = {} # peer_id → Array of timestamps (msec)

# Tool cooldown system (server-side)
var tool_cooldowns: Dictionary = {} # peer_id -> {action_type -> last_action_ticks_ms}

const BASE_COOLDOWNS: Dictionary = {
	"farm_clear": 1.0, "farm_till": 0.8, "farm_plant": 0.5,
	"farm_water": 0.5, "farm_harvest": 0.5,
	"chop": 1.5, "mine": 1.5, "dig": 2.0,
}

var player_info: Dictionary = {"name": "Player"}
var players: Dictionary = {} # peer_id -> player_info

# Server-side: full player data for persistence
var player_data_store: Dictionary = {} # peer_id -> full data dict
var join_state: Dictionary = {} # peer_id -> {"state": String, "player_name": String, "joined_at_ms": int}

# Name uniqueness tracking (server-side)
var active_player_names: Dictionary = {} # player_name -> peer_id

var _buff_check_timer: float = 0.0

func _ready() -> void:
	StatTracker.init(player_data_store)
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
			var timeout = CREATOR_TIMEOUT_MS if state == "in_creator" else JOIN_READY_TIMEOUT_MS
			if now - joined_at >= timeout:
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
	# Clean up tool cooldowns
	tool_cooldowns.erase(id)
	# Clear busy state
	server_clear_busy(id)
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
	# Cancel active trade
	if id in player_trade_map:
		_cancel_trade_internal(player_trade_map[id], "Partner disconnected.")
	# Clean up pending creature destination choice
	pending_creature_choices.erase(id)
	# Handle friend/party disconnect
	var friend_mgr = get_node_or_null("/root/Main/GameWorld/FriendManager")
	if friend_mgr and friend_mgr.has_method("handle_disconnect"):
		friend_mgr.handle_disconnect(id)
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
	# Don't load game world yet — wait for player data to decide if creator is needed
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

const INGREDIENT_RENAMES := {
	"grain_core": "flour",
	"sweet_crystal": "sugar",
	"umami_extract": "soy_sauce",
	"herbal_dew": "broth",
	"sour_essence": "vinegar",
	"spicy_essence": "chili_powder",
	"starfruit_essence": "starfruit",
	"frost_essence": "mint",
}

func _backfill_ingredient_renames(data: Dictionary) -> void:
	var inv: Dictionary = data.get("inventory", {})
	var changed := false
	for old_id in INGREDIENT_RENAMES:
		if old_id in inv:
			var new_id: String = INGREDIENT_RENAMES[old_id]
			var count: int = inv[old_id]
			inv.erase(old_id)
			inv[new_id] = inv.get(new_id, 0) + count
			changed = true
	if changed:
		data["inventory"] = inv
	# Migrate compendium items list
	var compendium: Dictionary = data.get("compendium", {})
	var items: Array = compendium.get("items", [])
	for i in range(items.size()):
		if items[i] in INGREDIENT_RENAMES:
			items[i] = INGREDIENT_RENAMES[items[i]]
	# Migrate hotbar references
	var hotbar: Array = data.get("hotbar", [])
	for i in range(hotbar.size()):
		if hotbar[i] is String and hotbar[i] in INGREDIENT_RENAMES:
			hotbar[i] = INGREDIENT_RENAMES[hotbar[i]]

const LOCATION_RENAMES := {
	"npc_brioche": "npc_hubert",
	"npc_ember": "npc_pepper",
	"npc_herbalist": "npc_murphy",
	"npc_old_salt": "npc_captain_sal",
	"cove_general_store": "general_store",
}

func _backfill_location_renames(data: Dictionary) -> void:
	var locations: Array = data.get("discovered_locations", [])
	var changed := false
	var i: int = locations.size() - 1
	while i >= 0:
		if locations[i] in LOCATION_RENAMES:
			var new_id: String = LOCATION_RENAMES[locations[i]]
			if new_id not in locations:
				locations[i] = new_id
			else:
				locations.remove_at(i)
			changed = true
		i -= 1
	if changed:
		data["discovered_locations"] = locations

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
	# Backfill player_id UUID for old saves that lack one
	if not data.has("player_id") or str(data.get("player_id", "")) == "":
		data["player_id"] = _generate_uuid()
	# Backfill creature IDs for old saves
	_backfill_creature_ids(data)
	# Migrate renamed ingredient IDs in old saves
	_backfill_ingredient_renames(data)
	# Migrate renamed location IDs in old saves
	_backfill_location_renames(data)
	# Backfill player color for old saves that lack it
	var pc = data.get("player_color", {})
	if not pc is Dictionary or pc.is_empty():
		data["player_color"] = _generate_player_color(sender_id)
	# Backfill equipped_tools for old saves
	if not data.has("equipped_tools") or not data["equipped_tools"] is Dictionary or data["equipped_tools"].is_empty():
		data["equipped_tools"] = {"hoe": "tool_hoe_basic", "axe": "tool_axe_basic", "watering_can": "tool_watering_can_basic", "shovel": "tool_shovel_basic"}
	elif not data["equipped_tools"].has("shovel"):
		data["equipped_tools"]["shovel"] = "tool_shovel_basic"
	if data["equipped_tools"] is Dictionary and not data["equipped_tools"].has("fishing_rod"):
		data["equipped_tools"]["fishing_rod"] = "tool_fishing_rod_basic"
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
	# Backfill NPC friendships
	if not data.has("npc_friendships"):
		data["npc_friendships"] = {}
	# Backfill discovered locations
	if not data.has("discovered_locations"):
		data["discovered_locations"] = []
	# Backfill quests
	if not data.has("quests"):
		data["quests"] = {"active": {}, "completed": {}, "daily_reset_day": 0, "weekly_reset_day": 0, "unlock_flags": []}
	# Backfill compendium & stats
	if not data.has("stats"):
		data["stats"] = {}
	if not data.has("compendium"):
		data["compendium"] = {"items": [], "creatures_seen": [], "creatures_owned": []}
	# Backfill social data
	if not data.has("social"):
		data["social"] = {"friends": [], "blocked": [], "incoming_requests": [], "outgoing_requests": []}
	# Backfill hotbar
	if not data.has("hotbar"):
		data["hotbar"] = []
	if not data.has("selected_hotbar_slot"):
		data["selected_hotbar_slot"] = 0
	# Backfill dig cooldowns
	if not data.has("dig_cooldowns"):
		data["dig_cooldowns"] = {}
	# Backfill bank data
	if not data.has("bank"):
		data["bank"] = {"balance": 0, "last_interest_day": 0}
	# Backfill character appearance for old saves
	if not data.has("appearance") or not data["appearance"] is Dictionary:
		data["appearance"] = {"needs_customization": true}
	# Prune expired friend requests on login
	_prune_expired_requests(data)
	# Backfill basic tools in inventory
	var inv = data.get("inventory", {})
	for tool_id in ["tool_hoe_basic", "tool_axe_basic", "tool_watering_can_basic", "tool_shovel_basic", "tool_fishing_rod_basic"]:
		if tool_id not in inv:
			inv[tool_id] = 1
	# Grant starter battle items for new players (no battle items yet)
	var has_any_battle_item := false
	for bi_id in DataRegistry.battle_items:
		if bi_id in inv and inv[bi_id] > 0:
			has_any_battle_item = true
			break
	if not has_any_battle_item:
		inv["herb_poultice"] = 3
		inv["revival_soup"] = 1
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
	# Pre-fetch offline friend/blocked names so first sync shows names, not UUIDs
	var friend_mgr = get_node_or_null("/root/Main/GameWorld/FriendManager")
	if friend_mgr:
		await friend_mgr.prefetch_friend_names(sender_id)
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
	player_data_received.emit()
	if PlayerData.appearance.get("needs_customization", false):
		# New player — show character creator before entering game world
		_show_character_creator()
	else:
		# Returning player — go straight to game world
		_enter_game_world()

func _show_character_creator() -> void:
	var main = get_tree().current_scene
	if main == null:
		return
	# Remove ConnectUI
	for child in main.get_children():
		if child.name == "ConnectUI":
			child.queue_free()
	# Tell server we're in the creator (extends timeout to 5 min)
	client_in_character_creator.rpc_id(1)
	# Add character creator scene
	var creator_script = load("res://scripts/ui/character_creator_ui.gd")
	var creator = CanvasLayer.new()
	creator.name = "CharacterCreatorUI"
	creator.set_script(creator_script)
	main.add_child(creator)
	creator.appearance_confirmed.connect(_on_creator_confirmed)
	creator.open(PlayerData.appearance.duplicate(), true)

func _on_creator_confirmed(appearance: Dictionary) -> void:
	# Send appearance to server
	request_update_appearance.rpc_id(1, appearance)
	PlayerData.appearance = appearance
	# Now enter game world
	_enter_game_world()

func _enter_game_world() -> void:
	GameManager.start_game()
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
func client_in_character_creator() -> void:
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id in join_state:
		join_state[sender_id]["state"] = "in_creator"
		join_state[sender_id]["joined_at_ms"] = Time.get_ticks_msec()

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
	var inv: Dictionary = {
		"tool_hoe_basic": 1,
		"tool_axe_basic": 1,
		"tool_watering_can_basic": 1,
		"tool_shovel_basic": 1,
		"tool_fishing_rod_basic": 1,
	}
	return {
		"player_name": player_name,
		"inventory": inv,
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
			"shovel": "tool_shovel_basic",
			"fishing_rod": "tool_fishing_rod_basic",
		},
		"known_recipes": [],
		"active_buffs": [],
		"creature_storage": [],
		"storage_capacity": 10,
		"npc_friendships": {},
		"stats": {},
		"compendium": {"items": [], "creatures_seen": [], "creatures_owned": []},
		"social": {"friends": [], "blocked": [], "incoming_requests": [], "outgoing_requests": []},
		"hotbar": [],
		"selected_hotbar_slot": 0,
		"discovered_locations": [],
		"dig_cooldowns": {},
		"appearance": {"needs_customization": true},
		"bank": {"balance": 0, "last_interest_day": 0},
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
	# Compendium unlock on first obtain
	StatTracker.unlock_compendium_item(peer_id, item_id)
	# Quest progress: collect objective
	var quest_mgr = get_node_or_null("/root/Main/GameWorld/QuestManager")
	if quest_mgr:
		quest_mgr.notify_progress(peer_id, "collect", item_id, amount)

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
	StatTracker.increment(peer_id, "money_earned", amount)

func server_remove_money(peer_id: int, amount: int) -> bool:
	if peer_id not in player_data_store:
		return false
	var current = int(player_data_store[peer_id].get("money", 0))
	if current < amount:
		return false
	player_data_store[peer_id]["money"] = current - amount
	StatTracker.increment(peer_id, "money_spent", amount)
	return true

func server_update_party(peer_id: int, party_array: Array) -> void:
	if peer_id not in player_data_store:
		return
	player_data_store[peer_id]["party"] = party_array.duplicate(true)

@rpc("any_peer", "reliable")
func request_sync_hotbar(hotbar_data: Array, selected_slot: int) -> void:
	var sender = multiplayer.get_remote_sender_id()
	if sender not in player_data_store:
		return
	if hotbar_data.size() > 8:
		return
	var clean: Array = []
	for entry in hotbar_data:
		if entry is Dictionary:
			clean.append(entry)
		else:
			clean.append({})
	player_data_store[sender]["hotbar"] = clean
	player_data_store[sender]["selected_hotbar_slot"] = clampi(selected_slot, 0, 7)

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

## Check tool cooldown. Returns true if action is allowed (cooldown elapsed), false if still on cooldown.
## Automatically stamps the time if allowed.
func check_tool_cooldown(peer_id: int, action_type: String, tool_type: String) -> bool:
	var base_cd: float = BASE_COOLDOWNS.get(action_type, 0.0)
	if base_cd <= 0.0:
		return true
	# Get speed_mult from equipped tool
	var speed_mult := 1.0
	if peer_id in player_data_store and tool_type != "":
		DataRegistry.ensure_loaded()
		var et = player_data_store[peer_id].get("equipped_tools", {})
		var tool_id: String = str(et.get(tool_type, ""))
		if tool_id != "":
			var tool_def = DataRegistry.get_tool(tool_id)
			if tool_def:
				speed_mult = float(tool_def.effectiveness.get("speed_mult", 1.0))
	var effective_cd: float = base_cd / maxf(speed_mult, 0.1)
	var now = Time.get_ticks_msec()
	if peer_id not in tool_cooldowns:
		tool_cooldowns[peer_id] = {}
	if not tool_cooldowns[peer_id].has(action_type):
		# First time performing this action — always allowed
		tool_cooldowns[peer_id][action_type] = now
		return true
	var last_time: int = int(tool_cooldowns[peer_id][action_type])
	var elapsed_ms: float = float(now - last_time)
	if elapsed_ms < effective_cd * 1000.0:
		return false
	tool_cooldowns[peer_id][action_type] = now
	return true

## Get remaining cooldown in milliseconds for a specific action.
func get_remaining_cooldown_ms(peer_id: int, action_type: String, tool_type: String) -> int:
	var base_cd: float = BASE_COOLDOWNS.get(action_type, 0.0)
	if base_cd <= 0.0:
		return 0
	var speed_mult := 1.0
	if peer_id in player_data_store and tool_type != "":
		DataRegistry.ensure_loaded()
		var et = player_data_store[peer_id].get("equipped_tools", {})
		var tool_id: String = str(et.get(tool_type, ""))
		if tool_id != "":
			var tool_def = DataRegistry.get_tool(tool_id)
			if tool_def:
				speed_mult = float(tool_def.effectiveness.get("speed_mult", 1.0))
	var effective_cd: float = base_cd / maxf(speed_mult, 0.1)
	var now = Time.get_ticks_msec()
	if peer_id not in tool_cooldowns:
		return 0
	if not tool_cooldowns[peer_id].has(action_type):
		return 0
	var last_time: int = int(tool_cooldowns[peer_id][action_type])
	var elapsed_ms: float = float(now - last_time)
	var remaining_ms: int = int(effective_cd * 1000.0 - elapsed_ms)
	return maxi(remaining_ms, 0)

func is_server() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()

func _get_player_node(peer_id: int) -> Node3D:
	var players_node = get_node_or_null("/root/Main/GameWorld/Players")
	if players_node:
		return players_node.get_node_or_null(str(peer_id))
	return null

## Returns peer_id for a given player_id UUID, or 0 if not online.
func get_peer_for_player_id(target_player_id: String) -> int:
	for pid in player_data_store:
		if str(player_data_store[pid].get("player_id", "")) == target_player_id:
			return pid
	return 0

## Returns player_id UUID for a given peer_id, or "" if not found.
func get_player_id_for_peer(peer_id: int) -> String:
	if peer_id in player_data_store:
		return str(player_data_store[peer_id].get("player_id", ""))
	return ""

const FRIEND_REQUEST_TTL_SEC = 604800 # 7 days

func _prune_expired_requests(data: Dictionary) -> void:
	var social = data.get("social", {})
	var now = Time.get_unix_time_from_system()
	for key in ["incoming_requests", "outgoing_requests"]:
		var reqs = social.get(key, [])
		var i = reqs.size() - 1
		while i >= 0:
			var sent_at = float(reqs[i].get("sent_at", 0))
			if sent_at > 0 and (now - sent_at) > FRIEND_REQUEST_TTL_SEC:
				reqs.remove_at(i)
			i -= 1

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

@rpc("authority", "reliable")
func _sync_npc_friendships(friendships: Dictionary) -> void:
	PlayerData.npc_friendships = friendships.duplicate(true)
	PlayerData.friendships_changed.emit()

@rpc("authority", "reliable")
func _notify_location_discovered(location_id: String, display_name: String) -> void:
	if location_id not in PlayerData.discovered_locations:
		PlayerData.discovered_locations.append(location_id)
		PlayerData.discovered_locations_changed.emit()
	# Show HUD toast
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("show_discovery_toast"):
		hud.show_discovery_toast(display_name)

@rpc("authority", "reliable")
func _sync_discovered_locations(location_ids: Array) -> void:
	PlayerData.discovered_locations = location_ids.duplicate()
	PlayerData.discovered_locations_changed.emit()

@rpc("any_peer", "reliable")
func request_compendium_sync() -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if sender not in player_data_store:
		return
	var p_stats = player_data_store[sender].get("stats", {})
	var p_comp = player_data_store[sender].get("compendium", {})
	_sync_compendium_client.rpc_id(sender, p_stats, p_comp)

@rpc("authority", "reliable")
func _sync_compendium_client(p_stats: Dictionary, p_comp: Dictionary) -> void:
	PlayerData.stats = p_stats.duplicate(true)
	PlayerData.compendium = p_comp.duplicate(true)
	PlayerData.stats_changed.emit()
	PlayerData.compendium_changed.emit()

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
	var sell_price = DataRegistry.get_sell_price(item_id)
	if sell_price <= 0:
		return
	var total = sell_price * qty
	server_remove_inventory(sender, item_id, qty)
	server_add_money(sender, total)
	StatTracker.increment(sender, "items_sold", qty)
	_sync_inventory_full.rpc_id(sender, player_data_store[sender].get("inventory", {}))
	_sync_money.rpc_id(sender, int(player_data_store[sender].get("money", 0)))
	var info = DataRegistry.get_item_display_info(item_id)
	print("[Sell] ", sender, " sold ", qty, "x ", info.get("display_name", item_id), " for $", total)

@rpc("any_peer", "reliable")
func request_buy_item(item_id: String, qty: int, shop_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if not _check_rate_limit(sender):
		return
	if qty <= 0:
		return
	DataRegistry.ensure_loaded()
	var shop = DataRegistry.get_shop(shop_id)
	if shop == null:
		return
	# Validate item is in shop catalog
	var buy_price = -1
	for entry in shop.items_for_sale:
		if str(entry.get("item_id", "")) == item_id:
			buy_price = int(entry.get("buy_price", 0))
			break
	if buy_price < 0:
		return
	var total = buy_price * qty
	if not server_remove_money(sender, total):
		return
	server_add_inventory(sender, item_id, qty)
	StatTracker.increment(sender, "items_bought", qty)
	_sync_inventory_full.rpc_id(sender, player_data_store[sender].get("inventory", {}))
	_sync_money.rpc_id(sender, int(player_data_store[sender].get("money", 0)))
	var info = DataRegistry.get_item_display_info(item_id)
	print("[Buy] ", sender, " bought ", qty, "x ", info.get("display_name", item_id), " for $", total)

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
	{"name": "Walk-in Freezer", "capacity": 30, "cost": 2000, "ingredients": {"sugar": 5}},
	{"name": "Deep Freeze Vault", "capacity": 50, "cost": 5000, "ingredients": {"sugar": 8, "mint": 5}},
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

# === Trade System ===

signal trade_request_received(peer_name: String, peer_id: int)
signal trade_started(partner_name: String)
signal trade_offer_updated(my_offer: Dictionary, their_offer: Dictionary)
signal trade_creature_offer_updated(my_creature: Dictionary, their_creature: Dictionary)
signal trade_receive_pref_updated(my_pref: Dictionary)
signal trade_confirmed(who: String)
signal trade_completed(received_items: Dictionary, received_creature: Dictionary)
signal trade_cancelled(reason: String)
signal creature_destination_requested(creature_data: Dictionary, current_party: Array, storage_size: int, storage_capacity: int)

var active_trades: Dictionary = {} # trade_id -> {peer_a, peer_b, offer_a, offer_b, confirmed_a, confirmed_b, ...creature fields}
var player_trade_map: Dictionary = {} # peer_id -> trade_id
var next_trade_id: int = 1

# Universal creature destination chooser (server-side pending state)
var pending_creature_choices: Dictionary = {} # peer_id -> {creature_data, source_type, source_id}

@rpc("any_peer", "reliable")
func request_trade(target_peer: int) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if not _check_rate_limit(sender):
		return
	if sender == target_peer:
		return
	# Check neither in battle, trade, or busy
	var battle_mgr = get_node_or_null("/root/Main/GameWorld/BattleManager")
	if battle_mgr and (sender in battle_mgr.player_battle_map or target_peer in battle_mgr.player_battle_map):
		return
	if sender in player_trade_map or target_peer in player_trade_map:
		return
	var sender_node = _get_player_node(sender)
	var target_node = _get_player_node(target_peer)
	if sender_node and sender_node.get("is_busy"):
		return
	if target_node and target_node.get("is_busy"):
		return
	# Check proximity
	if sender_node == null or target_node == null:
		return
	if sender_node.position.distance_to(target_node.position) > 5.0:
		return
	var sender_name = players.get(sender, {}).get("name", "Player")
	_trade_request_client.rpc_id(target_peer, sender_name, sender)

@rpc("any_peer", "reliable")
func respond_trade(initiator_peer: int, accepted: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if not _check_rate_limit(sender):
		return
	if not accepted:
		_trade_declined_client.rpc_id(initiator_peer)
		return
	# Create trade
	var trade_id = next_trade_id
	next_trade_id += 1
	active_trades[trade_id] = {
		"peer_a": initiator_peer,
		"peer_b": sender,
		"offer_a": {},
		"offer_b": {},
		"offer_creature_a": {},
		"offer_creature_b": {},
		"receive_pref_a": {},
		"receive_pref_b": {},
		"confirmed_a": false,
		"confirmed_b": false,
	}
	player_trade_map[initiator_peer] = trade_id
	player_trade_map[sender] = trade_id
	var name_a = players.get(initiator_peer, {}).get("name", "Player")
	var name_b = players.get(sender, {}).get("name", "Player")
	_trade_started_client.rpc_id(initiator_peer, name_b)
	_trade_started_client.rpc_id(sender, name_a)

@rpc("any_peer", "reliable")
func update_trade_offer(item_id: String, count: int) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if not _check_rate_limit(sender):
		return
	if sender not in player_trade_map:
		return
	var trade_id = player_trade_map[sender]
	var trade = active_trades.get(trade_id)
	if trade == null:
		return
	var side = "a" if trade.peer_a == sender else "b"
	var offer_key = "offer_" + side
	# Validate inventory
	if count > 0:
		if not server_has_inventory(sender, item_id, count):
			return
		# Reject non-tradeable items (recipe scrolls, fragments)
		DataRegistry.ensure_loaded()
		if not DataRegistry.is_item_tradeable(item_id):
			return
		trade[offer_key][item_id] = count
	else:
		trade[offer_key].erase(item_id)
	# Reset confirmations when offer changes
	trade.confirmed_a = false
	trade.confirmed_b = false
	# Sync offers to both
	_trade_offer_sync.rpc_id(trade.peer_a, trade.offer_a, trade.offer_b)
	_trade_offer_sync.rpc_id(trade.peer_b, trade.offer_b, trade.offer_a)

@rpc("any_peer", "reliable")
func update_trade_creature_offer(source: String, index: int, offered: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if not _check_rate_limit(sender):
		return
	if sender not in player_trade_map:
		return
	var trade_id = player_trade_map[sender]
	var trade = active_trades.get(trade_id)
	if trade == null:
		return
	var side = "a" if trade.peer_a == sender else "b"
	var offer_key = "offer_creature_" + side

	if offered:
		# Validate source and index
		if source != "party" and source != "storage":
			return
		var pool: Array = []
		if source == "party":
			pool = player_data_store[sender].get("party", [])
			# Must keep at least 1 creature in party
			if pool.size() <= 1:
				return
		else:
			pool = player_data_store[sender].get("creature_storage", [])
		if index < 0 or index >= pool.size():
			return
		var creature = pool[index]
		var cid = str(creature.get("creature_id", ""))
		if cid == "":
			return
		trade[offer_key] = {"source": source, "index": index, "creature_id": cid}
	else:
		trade[offer_key] = {}

	# Reset confirmations
	trade.confirmed_a = false
	trade.confirmed_b = false
	# Sync creature offers to both
	_sync_trade_creatures(trade)

@rpc("any_peer", "reliable")
func set_trade_receive_preference(destination: String, swap_party_idx: int) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if not _check_rate_limit(sender):
		return
	if sender not in player_trade_map:
		return
	var trade_id = player_trade_map[sender]
	var trade = active_trades.get(trade_id)
	if trade == null:
		return
	var side = "a" if trade.peer_a == sender else "b"
	var pref_key = "receive_pref_" + side

	if destination == "party":
		trade[pref_key] = {"destination": "party", "swap_party_idx": swap_party_idx}
	elif destination == "storage":
		trade[pref_key] = {"destination": "storage", "swap_party_idx": -1}
	else:
		return

	# Reset confirmations
	trade.confirmed_a = false
	trade.confirmed_b = false
	# Sync to both
	_sync_trade_creatures(trade)

func _sync_trade_creatures(trade: Dictionary) -> void:
	var oc_a = _resolve_creature_preview(trade.offer_creature_a, int(trade.peer_a))
	var oc_b = _resolve_creature_preview(trade.offer_creature_b, int(trade.peer_b))
	_trade_creature_offer_sync.rpc_id(int(trade.peer_a), oc_a, oc_b, trade.receive_pref_a)
	_trade_creature_offer_sync.rpc_id(int(trade.peer_b), oc_b, oc_a, trade.receive_pref_b)
	# Also re-sync item offers (since confirmations were reset)
	_trade_offer_sync.rpc_id(int(trade.peer_a), trade.offer_a, trade.offer_b)
	_trade_offer_sync.rpc_id(int(trade.peer_b), trade.offer_b, trade.offer_a)

func _resolve_creature_preview(offer_creature: Dictionary, peer_id: int) -> Dictionary:
	if offer_creature.is_empty():
		return {}
	var source: String = str(offer_creature.get("source", ""))
	var idx: int = int(offer_creature.get("index", -1))
	var cid: String = str(offer_creature.get("creature_id", ""))
	if peer_id not in player_data_store:
		return {}
	var pool: Array = []
	if source == "party":
		pool = player_data_store[peer_id].get("party", [])
	elif source == "storage":
		pool = player_data_store[peer_id].get("creature_storage", [])
	# Re-resolve by creature_id for safety
	for c in pool:
		if str(c.get("creature_id", "")) == cid:
			return {"species_id": c.get("species_id", ""), "nickname": c.get("nickname", ""), "level": c.get("level", 1), "types": c.get("types", []), "creature_id": cid}
	return {}

@rpc("any_peer", "reliable")
func confirm_trade() -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if not _check_rate_limit(sender):
		return
	if sender not in player_trade_map:
		return
	var trade_id = player_trade_map[sender]
	var trade = active_trades.get(trade_id)
	if trade == null:
		return
	var side = "a" if trade.peer_a == sender else "b"
	trade["confirmed_" + side] = true
	# Notify both
	var who = players.get(sender, {}).get("name", "Player")
	_trade_confirmed_client.rpc_id(trade.peer_a, who)
	_trade_confirmed_client.rpc_id(trade.peer_b, who)
	# Check if both confirmed
	if trade.confirmed_a and trade.confirmed_b:
		_execute_trade(trade_id)

func _execute_trade(trade_id: int) -> void:
	var trade = active_trades.get(trade_id)
	if trade == null:
		return
	var peer_a = int(trade.peer_a)
	var peer_b = int(trade.peer_b)
	# Final validation: both still have items
	for item_id in trade.offer_a:
		if not server_has_inventory(peer_a, item_id, int(trade.offer_a[item_id])):
			_cancel_trade_internal(trade_id, "Trade failed — items no longer available.")
			return
	for item_id in trade.offer_b:
		if not server_has_inventory(peer_b, item_id, int(trade.offer_b[item_id])):
			_cancel_trade_internal(trade_id, "Trade failed — items no longer available.")
			return

	# Validate creature offers (re-resolve by creature_id)
	var creature_a_data: Dictionary = {}
	var creature_a_src: String = ""
	var creature_a_idx: int = -1
	if not trade.offer_creature_a.is_empty():
		var resolved = _resolve_trade_creature(peer_a, trade.offer_creature_a)
		if resolved.is_empty():
			_cancel_trade_internal(trade_id, "Trade failed — offered creature no longer available.")
			return
		creature_a_data = resolved["creature"]
		creature_a_src = resolved["source"]
		creature_a_idx = resolved["index"]
	var creature_b_data: Dictionary = {}
	var creature_b_src: String = ""
	var creature_b_idx: int = -1
	if not trade.offer_creature_b.is_empty():
		var resolved = _resolve_trade_creature(peer_b, trade.offer_creature_b)
		if resolved.is_empty():
			_cancel_trade_internal(trade_id, "Trade failed — offered creature no longer available.")
			return
		creature_b_data = resolved["creature"]
		creature_b_src = resolved["source"]
		creature_b_idx = resolved["index"]

	# Validate receive prefs for creature destination
	if not creature_b_data.is_empty():
		# Peer A is receiving creature_b
		var pref_a = trade.get("receive_pref_a", {})
		if not _validate_trade_receive_pref(peer_a, pref_a, creature_a_idx if creature_a_src == "party" else -1):
			_cancel_trade_internal(trade_id, "Trade failed — destination invalid for received creature.")
			return
	if not creature_a_data.is_empty():
		# Peer B is receiving creature_a
		var pref_b = trade.get("receive_pref_b", {})
		if not _validate_trade_receive_pref(peer_b, pref_b, creature_b_idx if creature_b_src == "party" else -1):
			_cancel_trade_internal(trade_id, "Trade failed — destination invalid for received creature.")
			return

	# === Atomic execution ===

	# 1. Item swap (existing)
	for item_id in trade.offer_a:
		server_remove_inventory(peer_a, item_id, int(trade.offer_a[item_id]))
		server_add_inventory(peer_b, item_id, int(trade.offer_a[item_id]))
	for item_id in trade.offer_b:
		server_remove_inventory(peer_b, item_id, int(trade.offer_b[item_id]))
		server_add_inventory(peer_a, item_id, int(trade.offer_b[item_id]))

	# 2. Remove offered creatures (remove higher index first if both from same peer's party)
	if not creature_a_data.is_empty():
		_remove_creature_from_pool(peer_a, creature_a_src, creature_a_idx)
	if not creature_b_data.is_empty():
		# If peer_a already had a creature removed from party, adjust index for peer_b if needed
		_remove_creature_from_pool(peer_b, creature_b_src, creature_b_idx)

	# 3. Place received creatures using prefs
	var received_creature_a: Dictionary = {} # what peer_a received
	var received_creature_b: Dictionary = {} # what peer_b received
	if not creature_b_data.is_empty():
		_place_creature_by_pref(peer_a, creature_b_data, trade.get("receive_pref_a", {}))
		received_creature_a = creature_b_data
		StatTracker.increment(peer_a, "creatures_traded")
		StatTracker.unlock_creature_owned(peer_a, str(creature_b_data.get("species_id", "")))
	if not creature_a_data.is_empty():
		_place_creature_by_pref(peer_b, creature_a_data, trade.get("receive_pref_b", {}))
		received_creature_b = creature_a_data
		StatTracker.increment(peer_b, "creatures_traded")
		StatTracker.unlock_creature_owned(peer_b, str(creature_a_data.get("species_id", "")))

	# Sync everything
	_sync_inventory_full.rpc_id(peer_a, player_data_store[peer_a].get("inventory", {}))
	_sync_inventory_full.rpc_id(peer_b, player_data_store[peer_b].get("inventory", {}))
	if not creature_a_data.is_empty() or not creature_b_data.is_empty():
		_sync_party_full.rpc_id(peer_a, player_data_store[peer_a].get("party", []))
		_sync_party_full.rpc_id(peer_b, player_data_store[peer_b].get("party", []))
		_sync_storage_full.rpc_id(peer_a, player_data_store[peer_a].get("creature_storage", []), int(player_data_store[peer_a].get("storage_capacity", 10)))
		_sync_storage_full.rpc_id(peer_b, player_data_store[peer_b].get("creature_storage", []), int(player_data_store[peer_b].get("storage_capacity", 10)))

	# Track trade stats
	StatTracker.increment(peer_a, "trades_completed")
	StatTracker.increment(peer_b, "trades_completed")
	# Notify completion
	_trade_completed_client.rpc_id(peer_a, trade.offer_b.duplicate(), received_creature_a)
	_trade_completed_client.rpc_id(peer_b, trade.offer_a.duplicate(), received_creature_b)
	# Cleanup
	player_trade_map.erase(peer_a)
	player_trade_map.erase(peer_b)
	active_trades.erase(trade_id)
	print("[Trade] Completed between peer ", peer_a, " and peer ", peer_b)

func _resolve_trade_creature(peer_id: int, offer_creature: Dictionary) -> Dictionary:
	if peer_id not in player_data_store:
		return {}
	var cid: String = str(offer_creature.get("creature_id", ""))
	var source: String = str(offer_creature.get("source", ""))
	var pool: Array = []
	if source == "party":
		pool = player_data_store[peer_id].get("party", [])
		# Min-party check
		if pool.size() <= 1:
			return {}
	elif source == "storage":
		pool = player_data_store[peer_id].get("creature_storage", [])
	else:
		return {}
	for i in range(pool.size()):
		if str(pool[i].get("creature_id", "")) == cid:
			return {"creature": pool[i].duplicate(true), "source": source, "index": i}
	return {}

func _validate_trade_receive_pref(peer_id: int, pref: Dictionary, offered_party_idx: int) -> bool:
	if pref.is_empty():
		# Default to party if space, else storage
		return true
	var dest: String = str(pref.get("destination", "party"))
	var party = player_data_store[peer_id].get("party", [])
	var effective_party_size: int = party.size()
	if offered_party_idx >= 0:
		effective_party_size -= 1 # One will be removed
	if dest == "party":
		if effective_party_size < PlayerData.MAX_PARTY_SIZE:
			return true
		# Party full after removal — need swap
		var swap_idx: int = int(pref.get("swap_party_idx", -1))
		if swap_idx < 0 or swap_idx >= party.size():
			return false
		if swap_idx == offered_party_idx:
			return false # Can't swap with the one being traded
		var storage = player_data_store[peer_id].get("creature_storage", [])
		var capacity = int(player_data_store[peer_id].get("storage_capacity", 10))
		return storage.size() < capacity
	elif dest == "storage":
		var storage = player_data_store[peer_id].get("creature_storage", [])
		var capacity = int(player_data_store[peer_id].get("storage_capacity", 10))
		return storage.size() < capacity
	return false

func _remove_creature_from_pool(peer_id: int, source: String, index: int) -> void:
	if source == "party":
		var party = player_data_store[peer_id].get("party", [])
		if index >= 0 and index < party.size():
			party.remove_at(index)
			player_data_store[peer_id]["party"] = party
	elif source == "storage":
		var storage = player_data_store[peer_id].get("creature_storage", [])
		if index >= 0 and index < storage.size():
			storage.remove_at(index)
			player_data_store[peer_id]["creature_storage"] = storage

func _place_creature_by_pref(peer_id: int, creature_data: Dictionary, pref: Dictionary) -> void:
	var dest: String = str(pref.get("destination", "party"))
	var party = player_data_store[peer_id].get("party", [])

	if dest == "party":
		if party.size() < PlayerData.MAX_PARTY_SIZE:
			party.append(creature_data)
			player_data_store[peer_id]["party"] = party
		else:
			# Swap
			var swap_idx: int = int(pref.get("swap_party_idx", -1))
			if swap_idx >= 0 and swap_idx < party.size():
				var swapped = party[swap_idx]
				var storage = player_data_store[peer_id].get("creature_storage", [])
				storage.append(swapped)
				party[swap_idx] = creature_data
				player_data_store[peer_id]["party"] = party
				player_data_store[peer_id]["creature_storage"] = storage
			else:
				# Fallback: try storage
				var storage = player_data_store[peer_id].get("creature_storage", [])
				storage.append(creature_data)
				player_data_store[peer_id]["creature_storage"] = storage
	elif dest == "storage":
		var storage = player_data_store[peer_id].get("creature_storage", [])
		storage.append(creature_data)
		player_data_store[peer_id]["creature_storage"] = storage
	else:
		# Fallback: party or storage
		if party.size() < PlayerData.MAX_PARTY_SIZE:
			party.append(creature_data)
			player_data_store[peer_id]["party"] = party
		else:
			var storage = player_data_store[peer_id].get("creature_storage", [])
			storage.append(creature_data)
			player_data_store[peer_id]["creature_storage"] = storage

@rpc("any_peer", "reliable")
func cancel_trade() -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if sender not in player_trade_map:
		return
	_cancel_trade_internal(player_trade_map[sender], "Trade cancelled.")

func _cancel_trade_internal(trade_id: int, reason: String) -> void:
	var trade = active_trades.get(trade_id)
	if trade == null:
		return
	var peer_a = int(trade.peer_a)
	var peer_b = int(trade.peer_b)
	_trade_cancelled_client.rpc_id(peer_a, reason)
	_trade_cancelled_client.rpc_id(peer_b, reason)
	player_trade_map.erase(peer_a)
	player_trade_map.erase(peer_b)
	active_trades.erase(trade_id)

# Trade client RPCs
@rpc("authority", "reliable")
func _trade_request_client(requester_name: String, requester_peer: int) -> void:
	trade_request_received.emit(requester_name, requester_peer)

@rpc("authority", "reliable")
func _trade_declined_client() -> void:
	trade_cancelled.emit("Trade declined.")

@rpc("authority", "reliable")
func _trade_started_client(partner_name: String) -> void:
	trade_started.emit(partner_name)

@rpc("authority", "reliable")
func _trade_offer_sync(my_offer: Dictionary, their_offer: Dictionary) -> void:
	trade_offer_updated.emit(my_offer, their_offer)

@rpc("authority", "reliable")
func _trade_confirmed_client(who: String) -> void:
	trade_confirmed.emit(who)

@rpc("authority", "reliable")
func _trade_creature_offer_sync(my_creature: Dictionary, their_creature: Dictionary, my_pref: Dictionary) -> void:
	trade_creature_offer_updated.emit(my_creature, their_creature)
	trade_receive_pref_updated.emit(my_pref)

@rpc("authority", "reliable")
func _trade_completed_client(received_items: Dictionary, received_creature: Dictionary) -> void:
	trade_completed.emit(received_items, received_creature)

@rpc("authority", "reliable")
func _trade_cancelled_client(reason: String) -> void:
	trade_cancelled.emit(reason)

# === Busy State ===

@rpc("any_peer", "reliable")
func request_set_busy(busy: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if not _check_rate_limit(sender):
		return
	var player_node = _get_player_node(sender)
	if player_node:
		player_node.is_busy = busy
		if busy:
			_clear_prompts_client.rpc_id(sender)

func server_clear_busy(peer_id: int) -> void:
	var player_node = _get_player_node(peer_id)
	if player_node:
		player_node.is_busy = false

@rpc("authority", "reliable")
func _clear_prompts_client() -> void:
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("hide_trainer_prompt"):
		hud.hide_trainer_prompt()

# === Universal Creature Give (server-side entry point for ALL creature receipts) ===

func server_give_creature(peer_id: int, creature_data: Dictionary, source_type: String, source_id: String) -> void:
	if peer_id not in player_data_store:
		return
	# Track stats
	var species_id: String = str(creature_data.get("species_id", ""))
	StatTracker.unlock_creature_owned(peer_id, species_id)
	StatTracker.increment_species(peer_id, "species_catches", species_id)

	var party = player_data_store[peer_id].get("party", [])
	if party.size() < PlayerData.MAX_PARTY_SIZE:
		# Party has space — add directly
		party.append(creature_data)
		player_data_store[peer_id]["party"] = party
		_sync_party_full.rpc_id(peer_id, party)
		_notify_creature_received.rpc_id(peer_id, creature_data, "party", source_type, source_id)
		print("[Creature] ", peer_id, " received ", species_id, " to party from ", source_type)
	else:
		# Party full — store pending and ask client for destination
		pending_creature_choices[peer_id] = {
			"creature_data": creature_data,
			"source_type": source_type,
			"source_id": source_id,
		}
		var storage = player_data_store[peer_id].get("creature_storage", [])
		var capacity = int(player_data_store[peer_id].get("storage_capacity", 10))
		_show_creature_destination_chooser.rpc_id(peer_id, creature_data, party.duplicate(true), storage.size(), capacity)
		print("[Creature] ", peer_id, " party full, showing destination chooser for ", species_id)

@rpc("any_peer", "reliable")
func request_creature_destination(choice: String, swap_party_idx: int) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if not _check_rate_limit(sender):
		return
	if sender not in pending_creature_choices:
		return
	var pending = pending_creature_choices[sender]
	var creature_data: Dictionary = pending["creature_data"]
	var source_type: String = str(pending["source_type"])
	var source_id: String = str(pending["source_id"])

	if choice == "storage":
		var storage = player_data_store[sender].get("creature_storage", [])
		var capacity = int(player_data_store[sender].get("storage_capacity", 10))
		if storage.size() >= capacity:
			_creature_destination_error.rpc_id(sender, "Storage is full!")
			return
		storage.append(creature_data)
		player_data_store[sender]["creature_storage"] = storage
		pending_creature_choices.erase(sender)
		_sync_storage_full.rpc_id(sender, storage, capacity)
		_notify_creature_received.rpc_id(sender, creature_data, "storage", source_type, source_id)
		print("[Creature] ", sender, " sent ", creature_data.get("species_id", ""), " to storage")

	elif choice == "swap":
		var party = player_data_store[sender].get("party", [])
		var storage = player_data_store[sender].get("creature_storage", [])
		var capacity = int(player_data_store[sender].get("storage_capacity", 10))
		if swap_party_idx < 0 or swap_party_idx >= party.size():
			_creature_destination_error.rpc_id(sender, "Invalid party slot.")
			return
		if party.size() <= 1:
			_creature_destination_error.rpc_id(sender, "Must keep at least 1 creature in party.")
			return
		if storage.size() >= capacity:
			_creature_destination_error.rpc_id(sender, "Storage is full, cannot swap.")
			return
		# Move party creature to storage, put incoming in party slot
		var swapped_out = party[swap_party_idx]
		storage.append(swapped_out)
		party[swap_party_idx] = creature_data
		player_data_store[sender]["party"] = party
		player_data_store[sender]["creature_storage"] = storage
		pending_creature_choices.erase(sender)
		_sync_party_full.rpc_id(sender, party)
		_sync_storage_full.rpc_id(sender, storage, capacity)
		_notify_creature_received.rpc_id(sender, creature_data, "party", source_type, source_id)
		print("[Creature] ", sender, " swapped party slot ", swap_party_idx, " for ", creature_data.get("species_id", ""))

@rpc("any_peer", "reliable")
func cancel_creature_destination() -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if sender in pending_creature_choices:
		print("[Creature] ", sender, " cancelled creature destination — creature lost")
		pending_creature_choices.erase(sender)

@rpc("authority", "reliable")
func _show_creature_destination_chooser(creature_data: Dictionary, current_party: Array, storage_size: int, storage_cap: int) -> void:
	creature_destination_requested.emit(creature_data, current_party, storage_size, storage_cap)

@rpc("authority", "reliable")
func _creature_destination_error(msg: String) -> void:
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("show_toast"):
		hud.show_toast("Error: " + msg)

@rpc("authority", "reliable")
func _notify_creature_received(creature_data: Dictionary, destination: String, source_type: String, _source_id: String) -> void:
	var species_id: String = str(creature_data.get("species_id", ""))
	DataRegistry.ensure_loaded()
	var species = DataRegistry.get_species(species_id)
	var display_name: String = species.display_name if species else species_id
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("show_toast"):
		var dest_text = "party" if destination == "party" else "storage"
		var source_text = ""
		match source_type:
			"craft": source_text = "Crafted "
			"npc_trade": source_text = "Received "
			"npc_gift": source_text = "Gift: "
			"trade": source_text = "Traded: "
			_: source_text = "Received "
		hud.show_toast(source_text + display_name + " sent to " + dest_text + "!")

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

# === Bank System ===

func _apply_bank_interest(peer_id: int) -> int:
	if peer_id not in player_data_store:
		return 0
	var data = player_data_store[peer_id]
	var bank = data.get("bank", {"balance": 0, "last_interest_day": 0})
	var balance = int(bank.get("balance", 0))
	var last_day = int(bank.get("last_interest_day", 0))
	var season_mgr = get_node_or_null("/root/Main/GameWorld/SeasonManager")
	var current_day = season_mgr.total_day_count if season_mgr else 1

	if balance < BANK_MIN_BALANCE or current_day <= last_day:
		bank["last_interest_day"] = current_day
		data["bank"] = bank
		return 0

	var days_elapsed = current_day - last_day
	var total_interest = 0
	for _i in range(days_elapsed):
		var daily = int(floor(balance * BANK_INTEREST_RATE))
		daily = min(daily, BANK_MAX_DAILY_INTEREST)
		balance += daily
		total_interest += daily

	bank["balance"] = balance
	bank["last_interest_day"] = current_day
	data["bank"] = bank
	return total_interest

func server_deposit_money(peer_id: int, amount: int) -> bool:
	if peer_id not in player_data_store:
		return false
	if amount <= 0:
		return false
	var data = player_data_store[peer_id]
	var wallet = int(data.get("money", 0))
	if wallet < amount:
		return false
	var bank = data.get("bank", {"balance": 0, "last_interest_day": 0})
	data["money"] = wallet - amount
	bank["balance"] = int(bank.get("balance", 0)) + amount
	data["bank"] = bank
	return true

func server_withdraw_money(peer_id: int, amount: int) -> bool:
	if peer_id not in player_data_store:
		return false
	if amount <= 0:
		return false
	var data = player_data_store[peer_id]
	var bank = data.get("bank", {"balance": 0, "last_interest_day": 0})
	var balance = int(bank.get("balance", 0))
	var fee = max(1, int(floor(amount * BANK_WITHDRAWAL_FEE)))
	if balance < amount:
		return false
	bank["balance"] = balance - amount
	data["bank"] = bank
	# Player receives amount minus fee
	var net_amount = amount - fee
	data["money"] = int(data.get("money", 0)) + net_amount
	return true

func _handle_open_bank(peer_id: int) -> void:
	if not _check_rate_limit(peer_id):
		return
	if peer_id not in player_data_store:
		return
	# Apply any accumulated interest
	var interest = _apply_bank_interest(peer_id)
	var data = player_data_store[peer_id]
	var bank = data.get("bank", {"balance": 0, "last_interest_day": 0})
	_open_bank_client.rpc_id(peer_id, int(bank.get("balance", 0)), int(data.get("money", 0)), interest, BANK_INTEREST_RATE, BANK_WITHDRAWAL_FEE)

@rpc("any_peer", "reliable")
func request_deposit(amount: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id = multiplayer.get_remote_sender_id()
	if not _check_rate_limit(peer_id):
		return
	if peer_id not in player_data_store:
		return
	if amount <= 0:
		_bank_action_failed.rpc_id(peer_id, "Invalid amount.")
		return
	if server_deposit_money(peer_id, amount):
		var data = player_data_store[peer_id]
		var bank = data.get("bank", {"balance": 0, "last_interest_day": 0})
		_sync_bank_data.rpc_id(peer_id, int(bank.get("balance", 0)), int(data.get("money", 0)), "Deposited $%d." % amount)
		# Sync wallet to client PlayerData
		_sync_money.rpc_id(peer_id, int(data.get("money", 0)))
	else:
		_bank_action_failed.rpc_id(peer_id, "Insufficient funds to deposit.")

@rpc("any_peer", "reliable")
func request_withdraw(amount: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id = multiplayer.get_remote_sender_id()
	if not _check_rate_limit(peer_id):
		return
	if peer_id not in player_data_store:
		return
	if amount <= 0:
		_bank_action_failed.rpc_id(peer_id, "Invalid amount.")
		return
	var fee = max(1, int(floor(amount * BANK_WITHDRAWAL_FEE)))
	if server_withdraw_money(peer_id, amount):
		var data = player_data_store[peer_id]
		var bank = data.get("bank", {"balance": 0, "last_interest_day": 0})
		var net = amount - fee
		_sync_bank_data.rpc_id(peer_id, int(bank.get("balance", 0)), int(data.get("money", 0)), "Withdrew $%d (fee: $%d)." % [net, fee])
		_sync_money.rpc_id(peer_id, int(data.get("money", 0)))
	else:
		_bank_action_failed.rpc_id(peer_id, "Insufficient bank balance.")

@rpc("any_peer", "reliable")
func request_close_bank() -> void:
	if not multiplayer.is_server():
		return
	# Nothing special needed server-side; busy state cleared via request_set_busy

@rpc("authority", "reliable")
func _open_bank_client(balance: int, money: int, interest_earned: int, rate: float, fee_pct: float) -> void:
	var bank_ui = get_node_or_null("/root/Main/GameWorld/UI/BankUI")
	if bank_ui and bank_ui.has_method("open_bank"):
		bank_ui.open_bank(balance, money, interest_earned, rate, fee_pct)

@rpc("authority", "reliable")
func _sync_bank_data(balance: int, money: int, message: String) -> void:
	PlayerData.money = money
	var bank_ui = get_node_or_null("/root/Main/GameWorld/UI/BankUI")
	if bank_ui and bank_ui.has_method("update_data"):
		bank_ui.update_data(balance, money, message)

@rpc("authority", "reliable")
func _bank_action_failed(reason: String) -> void:
	var bank_ui = get_node_or_null("/root/Main/GameWorld/UI/BankUI")
	if bank_ui and bank_ui.has_method("show_error"):
		bank_ui.show_error(reason)

func _on_day_changed_bank_interest() -> void:
	# Apply interest to all online players on day change
	for peer_id in player_data_store:
		_apply_bank_interest(peer_id)

# ---------- Character Appearance ----------

@rpc("any_peer", "reliable")
func request_update_appearance(appearance: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id not in player_data_store:
		return
	# Validate appearance
	if not _validate_appearance(appearance):
		print("[NetworkManager] Invalid appearance from peer ", sender_id)
		return
	# Remove needs_customization flag
	appearance.erase("needs_customization")
	# Update server store
	player_data_store[sender_id]["appearance"] = appearance
	# Save
	SaveManager.save_player(player_data_store[sender_id])
	# Update the spawned player node
	var player_node = get_node_or_null("/root/Main/GameWorld/Players/" + str(sender_id))
	if player_node:
		player_node.appearance_data = appearance
	# Broadcast to all clients
	_sync_appearance.rpc(sender_id, appearance)


@rpc("authority", "reliable")
func _sync_appearance(peer_id: int, appearance: Dictionary) -> void:
	# Client-side: update the target player's appearance
	var player_node = get_node_or_null("/root/Main/GameWorld/Players/" + str(peer_id))
	if player_node and player_node.has_method("update_appearance"):
		player_node.update_appearance(appearance)
	# Update local mirror if it's our player
	if multiplayer.has_multiplayer_peer() and peer_id == multiplayer.get_unique_id():
		PlayerData.appearance = appearance


# === Dev Debug Actions (editor-only) ===

@rpc("any_peer", "reliable")
func request_debug_action(action: String, params: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	if not OS.has_feature("editor"):
		var sender = multiplayer.get_remote_sender_id()
		_debug_action_result.rpc_id(sender, action, "Rejected: server is not an editor build")
		return
	var peer := multiplayer.get_remote_sender_id()
	var msg := _handle_debug_action(peer, action, params)
	_debug_action_result.rpc_id(peer, action, msg)

@rpc("authority", "reliable")
func _debug_action_result(action: String, message: String) -> void:
	var overlay = get_node_or_null("/root/Main/GameWorld/UI/DevDebugOverlay")
	if overlay and overlay.has_method("_on_debug_result"):
		overlay._on_debug_result(action, message)
	print("[Debug] %s: %s" % [action, message])

func _handle_debug_action(peer: int, action: String, params: Dictionary) -> String:
	match action:
		"set_time":
			var sm = get_node_or_null("/root/Main/GameWorld/SeasonManager")
			if not sm:
				return "SeasonManager not found"
			sm.current_year = int(params.get("year", sm.current_year))
			sm.current_month = clampi(int(params.get("month", sm.current_month)), 1, 12)
			sm.day_in_month = clampi(int(params.get("day", sm.day_in_month)), 1, 28)
			sm.current_weather = int(params.get("weather", sm.current_weather))
			sm._broadcast_time.rpc(sm.current_year, sm.current_month, sm.day_in_month, sm.total_day_count, sm.current_weather, sm.day_timer)
			return "Time set to Y%d M%d D%d W%d" % [sm.current_year, sm.current_month, sm.day_in_month, sm.current_weather]

		"advance_day":
			var sm = get_node_or_null("/root/Main/GameWorld/SeasonManager")
			if not sm:
				return "SeasonManager not found"
			sm.day_timer = sm.DAY_DURATION
			return "Day timer maxed — will advance next frame"

		"set_time_speed":
			var sm = get_node_or_null("/root/Main/GameWorld/SeasonManager")
			if not sm:
				return "SeasonManager not found"
			var mult := clampi(int(params.get("multiplier", 1)), 1, 100)
			sm.set_meta("debug_speed_mult", mult)
			return "Time speed set to %dx" % mult

		"wild_battle":
			var species_id: String = str(params.get("species_id", ""))
			var species = DataRegistry.get_species(species_id)
			if not species:
				return "Unknown species: %s" % species_id
			var bm = get_node_or_null("/root/Main/GameWorld/BattleManager")
			if not bm:
				return "BattleManager not found"
			if peer in bm.player_battle_map:
				return "Already in battle"
			var enemy := CreatureInstance.create_from_species(species, 10).to_dict()
			bm.server_start_battle(peer, enemy)
			return "Wild battle started vs %s" % species_id

		"trainer_battle":
			var trainer_id: String = str(params.get("trainer_id", ""))
			var bm = get_node_or_null("/root/Main/GameWorld/BattleManager")
			if not bm:
				return "BattleManager not found"
			if peer in bm.player_battle_map:
				return "Already in battle"
			bm.server_start_trainer_battle(peer, trainer_id)
			return "Trainer battle started: %s" % trainer_id

		"give_item":
			var item_id: String = str(params.get("item_id", ""))
			var qty: int = int(params.get("qty", 1))
			if peer not in player_data_store:
				return "No player data"
			server_add_inventory(peer, item_id, qty)
			_sync_inventory_full.rpc_id(peer, player_data_store[peer].get("inventory", {}))
			return "Gave %dx %s" % [qty, item_id]

		"give_money":
			var amount: int = int(params.get("amount", 0))
			if peer not in player_data_store:
				return "No player data"
			server_add_money(peer, amount)
			_sync_money.rpc_id(peer, int(player_data_store[peer].get("money", 0)))
			return "Gave $%d" % amount

		"teleport":
			var x: float = float(params.get("x", 0))
			var y: float = float(params.get("y", 1))
			var z: float = float(params.get("z", 3))
			var player_node = get_node_or_null("/root/Main/GameWorld/Players/%d" % peer)
			if not player_node:
				return "Player node not found"
			player_node.position = Vector3(x, y, z)
			return "Teleported to (%.1f, %.1f, %.1f)" % [x, y, z]

		"heal_party":
			if peer not in player_data_store:
				return "No player data"
			var party: Array = player_data_store[peer].get("party", [])
			for creature in party:
				creature["hp"] = creature.get("max_hp", creature.get("hp", 1))
				creature["status"] = ""
				creature["status_turns"] = 0
				# Restore PP
				var moves: Array = creature.get("moves", [])
				var pp: Array = []
				for mid in moves:
					var mdef = DataRegistry.get_move(str(mid))
					pp.append(mdef.pp if mdef else 10)
				creature["pp"] = pp
			player_data_store[peer]["party"] = party
			_sync_party_full.rpc_id(peer, party)
			return "Party healed (%d creatures)" % party.size()

		"unlock_all_recipes":
			if peer not in player_data_store:
				return "No player data"
			DataRegistry.ensure_loaded()
			var all_recipes: Array = []
			for rid in DataRegistry.recipes:
				all_recipes.append(rid)
			player_data_store[peer]["known_recipes"] = all_recipes
			_sync_known_recipes.rpc_id(peer, all_recipes)
			return "Unlocked %d recipes" % all_recipes.size()

		"set_creature_level":
			if peer not in player_data_store:
				return "No player data"
			var party: Array = player_data_store[peer].get("party", [])
			var idx: int = int(params.get("party_idx", 0))
			var lvl: int = clampi(int(params.get("level", 1)), 1, 50)
			if idx < 0 or idx >= party.size():
				return "Invalid party index %d (party size %d)" % [idx, party.size()]
			party[idx]["level"] = lvl
			var bm = get_node_or_null("/root/Main/GameWorld/BattleManager")
			if bm:
				bm._recalc_stats(party[idx])
			party[idx]["hp"] = party[idx].get("max_hp", party[idx].get("hp", 1))
			_sync_party_full.rpc_id(peer, party)
			return "Set party[%d] to level %d" % [idx, lvl]

		"max_all_creatures":
			if peer not in player_data_store:
				return "No player data"
			var party: Array = player_data_store[peer].get("party", [])
			var bm = get_node_or_null("/root/Main/GameWorld/BattleManager")
			for creature in party:
				creature["level"] = 50
				if bm:
					bm._recalc_stats(creature)
				creature["hp"] = creature.get("max_hp", creature.get("hp", 1))
			_sync_party_full.rpc_id(peer, party)
			return "Maxed %d creatures to level 50" % party.size()

		"force_evolve":
			if peer not in player_data_store:
				return "No player data"
			var party: Array = player_data_store[peer].get("party", [])
			var idx: int = int(params.get("party_idx", 0))
			if idx < 0 or idx >= party.size():
				return "Invalid party index %d" % idx
			var creature = party[idx]
			var species = DataRegistry.get_species(creature.get("species_id", ""))
			if not species or species.evolves_to == "":
				return "Species %s has no evolution" % creature.get("species_id", "?")
			var evo_species = DataRegistry.get_species(species.evolves_to)
			if not evo_species:
				return "Evolution species %s not found" % species.evolves_to
			creature["species_id"] = species.evolves_to
			creature["nickname"] = evo_species.display_name
			creature["types"] = Array(evo_species.types)
			var bm = get_node_or_null("/root/Main/GameWorld/BattleManager")
			if bm:
				bm._recalc_stats(creature)
			creature["hp"] = creature.get("max_hp", creature.get("hp", 1))
			_sync_party_full.rpc_id(peer, party)
			return "Evolved party[%d] to %s" % [idx, species.evolves_to]

		"set_friendship":
			if peer not in player_data_store:
				return "No player data"
			var npc_id: String = str(params.get("npc_id", ""))
			var points: int = clampi(int(params.get("points", 0)), -100, 100)
			var friendships: Dictionary = player_data_store[peer].get("npc_friendships", {})
			if npc_id not in friendships:
				friendships[npc_id] = {"points": 0, "talked_today": false, "gifted_today": false}
			friendships[npc_id]["points"] = points
			player_data_store[peer]["npc_friendships"] = friendships
			_sync_npc_friendships.rpc_id(peer, friendships)
			return "Set %s friendship to %d" % [npc_id, points]

		"max_all_friendships":
			if peer not in player_data_store:
				return "No player data"
			var friendships: Dictionary = player_data_store[peer].get("npc_friendships", {})
			DataRegistry.ensure_loaded()
			for npc_id in DataRegistry.npcs:
				if npc_id not in friendships:
					friendships[npc_id] = {"points": 0, "talked_today": false, "gifted_today": false}
				friendships[npc_id]["points"] = 100
			player_data_store[peer]["npc_friendships"] = friendships
			_sync_npc_friendships.rpc_id(peer, friendships)
			return "Maxed all NPC friendships"

		"force_grow_plots":
			var fm = get_node_or_null("/root/Main/GameWorld/Zones/FarmZone/FarmManager")
			if not fm:
				return "FarmManager not found"
			var count := 0
			for plot in fm.plots:
				if plot.plot_state == plot.PlotState.PLANTED or plot.plot_state == plot.PlotState.WATERED or plot.plot_state == plot.PlotState.GROWING:
					plot.set_state(plot.PlotState.READY)
					count += 1
			return "Grew %d plots to READY" % count

		"reset_plots":
			var fm = get_node_or_null("/root/Main/GameWorld/Zones/FarmZone/FarmManager")
			if not fm:
				return "FarmManager not found"
			for plot in fm.plots:
				plot.set_state(plot.PlotState.TILLED)
				plot.planted_seed_id = ""
				plot.growth_progress = 0.0
				plot.water_level = 0.0
				plot.owner_peer_id = 0
			return "Reset %d plots to TILLED" % fm.plots.size()

		"complete_quest":
			var quest_id: String = str(params.get("quest_id", ""))
			var qm = get_node_or_null("/root/Main/GameWorld/QuestManager")
			if not qm:
				return "QuestManager not found"
			DataRegistry.ensure_loaded()
			var qdata = qm._ensure_quest_data(peer)
			var active: Dictionary = qdata.get("active", {})
			if quest_id not in active:
				# Try to accept it first
				qm.handle_accept_quest(peer, quest_id)
				qdata = qm._ensure_quest_data(peer)
				active = qdata.get("active", {})
				if quest_id not in active:
					return "Quest %s not found/startable" % quest_id
			# Force all objectives to complete by maxing progress
			var qdef = DataRegistry.get_quest(quest_id)
			if qdef:
				var objectives: Array = active[quest_id].get("objectives", [])
				for i in range(qdef.objectives.size()):
					if i < objectives.size():
						var target_count: int = int(qdef.objectives[i].get("target_count", 1))
						objectives[i]["progress"] = target_count
			# Complete it
			qm.handle_complete_quest(peer, quest_id)
			return "Completed quest: %s" % quest_id

		"reset_quests":
			if peer not in player_data_store:
				return "No player data"
			player_data_store[peer]["quests"] = {"active": {}, "completed": {}, "daily_reset_day": 0, "weekly_reset_day": 0, "unlock_flags": []}
			var qm = get_node_or_null("/root/Main/GameWorld/QuestManager")
			if qm:
				qm._sync_quest_state.rpc_id(peer, {}, {}, [])
			return "All quests reset"

		"end_excursion":
			var em = get_node_or_null("/root/Main/GameWorld/ExcursionManager")
			if not em:
				return "ExcursionManager not found"
			em.handle_disconnect(peer)
			return "Excursion ended"

		# === Battle Actions ===

		"battle_force_win":
			var bm = get_node_or_null("/root/Main/GameWorld/BattleManager")
			if not bm:
				return "BattleManager not found"
			var battle = bm._get_battle_for_peer(peer)
			if not battle:
				return "Not in a battle"
			# Set all enemy party creatures to 0 HP
			for c in battle.side_b_party:
				c["hp"] = 0
			# Set active enemy to 1 HP and process a move turn to trigger win
			var enemy = battle.side_b_party[battle.side_b_active_idx]
			enemy["hp"] = 1
			battle.state = "processing"
			var player_creature = battle.side_a_party[battle.side_a_active_idx]
			var moves = player_creature.get("moves", [])
			if moves.size() > 0:
				bm._process_move_turn(battle, "move", str(moves[0]))
			return "Forced win"

		"battle_force_lose":
			var bm = get_node_or_null("/root/Main/GameWorld/BattleManager")
			if not bm:
				return "BattleManager not found"
			var battle = bm._get_battle_for_peer(peer)
			if not battle:
				return "Not in a battle"
			# Set all player party creatures to 0 HP
			for c in battle.side_a_party:
				c["hp"] = 0
			var player_creature = battle.side_a_party[battle.side_a_active_idx]
			player_creature["hp"] = 1
			battle.state = "processing"
			var enemy = battle.side_b_party[battle.side_b_active_idx]
			var emoves = enemy.get("moves", [])
			if emoves.size() > 0:
				bm._process_move_turn(battle, "move", str(emoves[0]))
			return "Forced loss"

		"battle_set_hp":
			var bm = get_node_or_null("/root/Main/GameWorld/BattleManager")
			if not bm:
				return "BattleManager not found"
			var battle = bm._get_battle_for_peer(peer)
			if not battle:
				return "Not in a battle"
			var side: String = str(params.get("side", "player"))
			var hp: int = int(params.get("hp", 1))
			var creature: Dictionary
			if side == "player":
				creature = battle.side_a_party[battle.side_a_active_idx]
			else:
				creature = battle.side_b_party[battle.side_b_active_idx]
			creature["hp"] = clampi(hp, 0, creature.get("max_hp", 999))
			bm._send_state_to_peer(battle, peer)
			return "Set %s HP to %d" % [side, creature["hp"]]

		"battle_set_status":
			var bm = get_node_or_null("/root/Main/GameWorld/BattleManager")
			if not bm:
				return "BattleManager not found"
			var battle = bm._get_battle_for_peer(peer)
			if not battle:
				return "Not in a battle"
			var side: String = str(params.get("side", "player"))
			var status: String = str(params.get("status", ""))
			var creature: Dictionary
			if side == "player":
				creature = battle.side_a_party[battle.side_a_active_idx]
			else:
				creature = battle.side_b_party[battle.side_b_active_idx]
			creature["status"] = status
			creature["status_turns"] = 3 if status != "" else 0
			bm._send_state_to_peer(battle, peer)
			return "Set %s status to '%s'" % [side, status if status != "" else "none"]

		"battle_set_stat_stage":
			var bm = get_node_or_null("/root/Main/GameWorld/BattleManager")
			if not bm:
				return "BattleManager not found"
			var battle = bm._get_battle_for_peer(peer)
			if not battle:
				return "Not in a battle"
			var side: String = str(params.get("side", "player"))
			var stat: String = str(params.get("stat", "attack"))
			var val: int = clampi(int(params.get("value", 0)), -6, 6)
			var creature: Dictionary
			if side == "player":
				creature = battle.side_a_party[battle.side_a_active_idx]
			else:
				creature = battle.side_b_party[battle.side_b_active_idx]
			creature[stat + "_stage"] = val
			bm._send_state_to_peer(battle, peer)
			return "Set %s %s stage to %d" % [side, stat, val]

		"battle_heal":
			var bm = get_node_or_null("/root/Main/GameWorld/BattleManager")
			if not bm:
				return "BattleManager not found"
			var battle = bm._get_battle_for_peer(peer)
			if not battle:
				return "Not in a battle"
			var creature = battle.side_a_party[battle.side_a_active_idx]
			creature["hp"] = creature.get("max_hp", creature.get("hp", 1))
			creature["status"] = ""
			creature["status_turns"] = 0
			bm._send_state_to_peer(battle, peer)
			return "Healed player's active creature"

		"battle_set_weather":
			var bm = get_node_or_null("/root/Main/GameWorld/BattleManager")
			if not bm:
				return "BattleManager not found"
			var battle = bm._get_battle_for_peer(peer)
			if not battle:
				return "Not in a battle"
			var weather: String = str(params.get("weather", "none"))
			var turns: int = clampi(int(params.get("turns", 5)), 0, 10)
			battle["weather"] = weather if weather != "none" else ""
			battle["weather_turns"] = turns if weather != "none" else 0
			bm._send_state_to_peer(battle, peer)
			return "Set battle weather to %s (%d turns)" % [weather, turns]

		"battle_clear_hazards":
			var bm = get_node_or_null("/root/Main/GameWorld/BattleManager")
			if not bm:
				return "BattleManager not found"
			var battle = bm._get_battle_for_peer(peer)
			if not battle:
				return "Not in a battle"
			battle["side_a_hazards"] = []
			battle["side_b_hazards"] = []
			bm._send_state_to_peer(battle, peer)
			return "Cleared all hazards"

		"battle_max_pp":
			var bm = get_node_or_null("/root/Main/GameWorld/BattleManager")
			if not bm:
				return "BattleManager not found"
			var battle = bm._get_battle_for_peer(peer)
			if not battle:
				return "Not in a battle"
			var creature = battle.side_a_party[battle.side_a_active_idx]
			var moves: Array = creature.get("moves", [])
			var pp: Array = []
			for mid in moves:
				var mdef = DataRegistry.get_move(str(mid))
				pp.append(mdef.pp if mdef else 10)
			creature["pp"] = pp
			bm._send_state_to_peer(battle, peer)
			return "Restored all PP"

		_:
			return "Unknown action: %s" % action

func _validate_appearance(app: Dictionary) -> bool:
	var gender: String = app.get("gender", "")
	if gender != "female" and gender != "male":
		return false
	# Required parts: head, torso, pants, shoes
	for required_key in ["head_id", "torso_id", "pants_id", "shoes_id", "arms_id"]:
		var val: String = app.get(required_key, "")
		if val == "":
			return false
	return true
