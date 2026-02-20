extends Node

signal inventory_changed()
signal party_changed()
signal tool_changed(tool_name: String)
signal known_recipes_changed()
signal buffs_changed()
signal storage_changed()
signal location_changed(zone: String, owner_name: String)
signal friendships_changed()
signal discovered_locations_changed()
signal compass_target_changed(target_id: String)
signal quests_changed()
signal stats_changed()
signal compendium_changed()
signal player_friends_changed()
signal player_party_updated()  # player-to-player party (not creature party)
signal hotbar_changed()
signal hotbar_selection_changed(slot_index: int)
signal fishing_log_changed()

# Location tracking (client-side mirror of server state)
var current_zone: String = "overworld"
var current_restaurant_owner: String = ""
var restaurant_data: Dictionary = {}

# Inventory: item_id -> count (all item types share this namespace)
var inventory: Dictionary = {}

# Party: array of CreatureInstance data (dictionaries for now)
var party: Array = []
const MAX_PARTY_SIZE = 3

# Money
var money: int = 0

# Defeated trainers: trainer_id -> unix timestamp of last defeat
var defeated_trainers: Dictionary = {}

# Current tool slot
var current_tool_slot: String = "" # "hoe", "axe", "watering_can", "shovel", "seeds", "" for hands
var selected_seed_id: String = ""

# Equipped tools: slot -> tool_id
var equipped_tools: Dictionary = {
	"hoe": "tool_hoe_basic",
	"axe": "tool_axe_basic",
	"watering_can": "tool_watering_can_basic",
	"shovel": "tool_shovel_basic",
}

# Hotbar: 8 configurable slots (all start empty, player assigns items)
const HOTBAR_SIZE: int = 8
var hotbar: Array = []  # 8 entries, each {} or {"item_id": String, "item_type": String}
var selected_hotbar_slot: int = 0

# Watering can state (synced from server)
var watering_can_current: int = 10

# Recipe unlock system
var known_recipes: Array = [] # list of unlocked recipe_id strings

# Active buffs
var active_buffs: Array = [] # [{buff_type, buff_value, expires_at}]

# Creature storage
var creature_storage: Array = [] # Array of creature dicts (same format as party)
var storage_capacity: int = 10 # Current max storage slots

# NPC friendships: npc_id -> {points, talked_today, gifted_today, ...}
var npc_friendships: Dictionary = {}

# Location discovery
var discovered_locations: Array = []
var compass_target_id: String = ""

# Quests
var active_quests: Dictionary = {} # quest_id -> {started_at, objectives: [{progress}]}
var completed_quests: Dictionary = {} # quest_id -> unix_timestamp
var unlock_flags: Array = []

# Compendium & Stats (client-side mirror, synced on demand via RPC)
var stats: Dictionary = {}
var compendium: Dictionary = {"items": [], "creatures_seen": [], "creatures_owned": []}

# Fishing log (client-side mirror, synced via FishingManager RPCs)
var fishing_log: Dictionary = {}  # {catches: {fish_id: {count, perfect_count, first_caught_day}}}

# Player-to-player social
var friends: Array = [] # [{player_id, player_name, online}]
var blocked_players: Array = [] # [player_id, ...]
var incoming_friend_requests: Array = [] # [{from_id, from_name, sent_at}]
var outgoing_friend_requests: Array = [] # [{to_id, to_name, sent_at}]

# Player-to-player party (ephemeral, not persisted)
var group_party_id: int = -1
var group_party_leader_id: String = ""
var group_party_members: Array = [] # [{player_id, player_name, online}]

# Player state
var player_id: String = "" # UUID from server
var player_name: String = "Player"
var player_color: Color = Color(0.2, 0.5, 0.9)

func _ready() -> void:
	# Only give starter creature for offline/singleplayer testing
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		if multiplayer.has_multiplayer_peer():
			return # Server doesn't need local player data
		# Offline mode: give starter creature
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
			"types": ["grain"]
		}
		party.append(starter)

func get_watering_can_capacity() -> int:
	DataRegistry.ensure_loaded()
	var tool_id = equipped_tools.get("watering_can", "tool_watering_can_basic")
	var tool_def = DataRegistry.get_tool(tool_id)
	if tool_def:
		return int(tool_def.effectiveness.get("capacity", 10))
	return 10

func get_tool_effectiveness(tool_type: String) -> Dictionary:
	DataRegistry.ensure_loaded()
	var tool_id = equipped_tools.get(tool_type, "")
	if tool_id == "":
		return {}
	var tool_def = DataRegistry.get_tool(tool_id)
	if tool_def:
		return tool_def.effectiveness
	return {}

func get_tool_display_name(tool_type: String) -> String:
	DataRegistry.ensure_loaded()
	var tool_id = equipped_tools.get(tool_type, "")
	if tool_id == "":
		return tool_type.capitalize()
	var tool_def = DataRegistry.get_tool(tool_id)
	if tool_def:
		return tool_def.display_name
	return tool_type.capitalize()

func has_active_buff(buff_type: String) -> bool:
	var now = Time.get_unix_time_from_system()
	for buff in active_buffs:
		if buff.get("buff_type", "") == buff_type and float(buff.get("expires_at", 0)) > now:
			return true
	return false

func get_buff_value(buff_type: String) -> float:
	var now = Time.get_unix_time_from_system()
	for buff in active_buffs:
		if buff.get("buff_type", "") == buff_type and float(buff.get("expires_at", 0)) > now:
			return float(buff.get("buff_value", 0.0))
	return 0.0

func load_from_server(data: Dictionary) -> void:
	player_id = str(data.get("player_id", ""))
	player_name = data.get("player_name", "Player")
	# Load inventory
	inventory.clear()
	var inv = data.get("inventory", {})
	for key in inv:
		inventory[key] = int(inv[key])
	# Load party
	party.clear()
	var party_data = data.get("party", [])
	for creature in party_data:
		party.append(creature)
	# Load watering can
	watering_can_current = int(data.get("watering_can_current", 10))
	# Load money and trainer defeats
	money = int(data.get("money", 0))
	defeated_trainers = data.get("defeated_trainers", {})
	# Load player color
	var cd = data.get("player_color", {})
	if cd is Dictionary and not cd.is_empty():
		player_color = Color(cd.get("r", 0.2), cd.get("g", 0.5), cd.get("b", 0.9))
	# Load equipped tools
	var et = data.get("equipped_tools", {})
	if et is Dictionary and not et.is_empty():
		equipped_tools = et.duplicate()
	# Load known recipes
	known_recipes = data.get("known_recipes", []).duplicate()
	# Load active buffs
	active_buffs = data.get("active_buffs", []).duplicate()
	# Load creature storage
	creature_storage = data.get("creature_storage", []).duplicate(true)
	storage_capacity = int(data.get("storage_capacity", 10))
	# Load restaurant data
	restaurant_data = data.get("restaurant", {}).duplicate(true)
	# Load NPC friendships
	npc_friendships = data.get("npc_friendships", {}).duplicate(true)
	# Load discovered locations
	discovered_locations = data.get("discovered_locations", []).duplicate()
	# Load quests
	var quest_data = data.get("quests", {})
	active_quests = quest_data.get("active", {}).duplicate(true)
	completed_quests = quest_data.get("completed", {}).duplicate(true)
	unlock_flags = quest_data.get("unlock_flags", []).duplicate()
	# Load compendium & stats
	stats = data.get("stats", {}).duplicate(true)
	compendium = data.get("compendium", {"items": [], "creatures_seen": [], "creatures_owned": []}).duplicate(true)
	# Load fishing log
	fishing_log = data.get("fishing_log", {}).duplicate(true)
	# Load player social (friends are synced separately via FriendManager, but incoming/outgoing stored in save)
	# Social data is synced on-demand via FriendManager.request_friends_sync()
	# Load hotbar
	var hb = data.get("hotbar", [])
	hotbar.clear()
	for entry in hb:
		if entry is Dictionary:
			hotbar.append(entry.duplicate())
		else:
			hotbar.append({})
	_init_hotbar()
	# Restore selected hotbar slot from server data
	selected_hotbar_slot = clampi(int(data.get("selected_hotbar_slot", 0)), 0, HOTBAR_SIZE - 1)
	# Reset tool
	current_tool_slot = ""
	selected_seed_id = ""
	compass_target_id = ""
	print("[Hotbar Debug] load_from_server: hotbar=", hotbar)
	print("[Hotbar Debug] load_from_server: selected_hotbar_slot=", selected_hotbar_slot)
	print("[Hotbar Debug] load_from_server: current_tool_slot RESET to ''")
	# NOTE: current_tool_slot stays "" until user presses a hotbar key.
	# selected_hotbar_slot is restored but select_hotbar_slot() is NOT called,
	# so the tool isn't actually activated after login.
	# Reset party group (ephemeral, not persisted)
	group_party_id = -1
	group_party_leader_id = ""
	group_party_members.clear()
	inventory_changed.emit()
	party_changed.emit()
	known_recipes_changed.emit()
	buffs_changed.emit()
	storage_changed.emit()
	friendships_changed.emit()
	discovered_locations_changed.emit()
	quests_changed.emit()
	stats_changed.emit()
	compendium_changed.emit()
	fishing_log_changed.emit()

func to_dict() -> Dictionary:
	return {
		"player_name": player_name,
		"inventory": inventory.duplicate(),
		"party": party.duplicate(true),
		"watering_can_current": watering_can_current,
		"money": money,
		"defeated_trainers": defeated_trainers.duplicate(),
		"player_color": {"r": player_color.r, "g": player_color.g, "b": player_color.b},
		"equipped_tools": equipped_tools.duplicate(),
		"known_recipes": known_recipes.duplicate(),
		"active_buffs": active_buffs.duplicate(),
		"creature_storage": creature_storage.duplicate(true),
		"storage_capacity": storage_capacity,
		"restaurant": restaurant_data.duplicate(true),
		"npc_friendships": npc_friendships.duplicate(true),
		"discovered_locations": discovered_locations.duplicate(),
		"quests": {
			"active": active_quests.duplicate(true),
			"completed": completed_quests.duplicate(true),
			"unlock_flags": unlock_flags.duplicate(),
		},
		"stats": stats.duplicate(true),
		"compendium": compendium.duplicate(true),
		"fishing_log": fishing_log.duplicate(true),
		"hotbar": hotbar.duplicate(true),
		"selected_hotbar_slot": selected_hotbar_slot,
	}

func reset() -> void:
	inventory.clear()
	party.clear()
	current_tool_slot = ""
	selected_seed_id = ""
	equipped_tools = {
		"hoe": "tool_hoe_basic",
		"axe": "tool_axe_basic",
		"watering_can": "tool_watering_can_basic",
		"shovel": "tool_shovel_basic",
	}
	watering_can_current = 10
	hotbar.clear()
	_init_hotbar()
	selected_hotbar_slot = 0
	player_id = ""
	player_name = "Player"
	player_color = Color(0.2, 0.5, 0.9)
	money = 0
	defeated_trainers.clear()
	known_recipes.clear()
	active_buffs.clear()
	creature_storage.clear()
	storage_capacity = 10
	npc_friendships.clear()
	discovered_locations.clear()
	compass_target_id = ""
	active_quests.clear()
	completed_quests.clear()
	unlock_flags.clear()
	stats.clear()
	compendium = {"items": [], "creatures_seen": [], "creatures_owned": []}
	fishing_log.clear()
	friends.clear()
	blocked_players.clear()
	incoming_friend_requests.clear()
	outgoing_friend_requests.clear()
	group_party_id = -1
	group_party_leader_id = ""
	group_party_members.clear()
	current_zone = "overworld"
	current_restaurant_owner = ""
	restaurant_data.clear()
	inventory_changed.emit()
	party_changed.emit()
	known_recipes_changed.emit()
	buffs_changed.emit()
	storage_changed.emit()
	friendships_changed.emit()
	discovered_locations_changed.emit()
	quests_changed.emit()
	stats_changed.emit()
	compendium_changed.emit()
	fishing_log_changed.emit()

func add_to_inventory(item_id: String, amount: int = 1) -> void:
	if item_id in inventory:
		inventory[item_id] += amount
	else:
		inventory[item_id] = amount
	inventory_changed.emit()

func remove_from_inventory(item_id: String, amount: int = 1) -> bool:
	if item_id not in inventory or inventory[item_id] < amount:
		return false
	inventory[item_id] -= amount
	if inventory[item_id] <= 0:
		inventory.erase(item_id)
	inventory_changed.emit()
	return true

func has_item(item_id: String, amount: int = 1) -> bool:
	return item_id in inventory and inventory[item_id] >= amount

func get_item_count(item_id: String) -> int:
	return inventory.get(item_id, 0)

func add_creature_to_party(creature_data: Dictionary) -> bool:
	if party.size() >= MAX_PARTY_SIZE:
		return false
	party.append(creature_data)
	party_changed.emit()
	return true

func remove_creature_from_party(index: int) -> void:
	if index >= 0 and index < party.size() and party.size() > 1:
		party.remove_at(index)
		party_changed.emit()

func get_first_alive_creature() -> int:
	for i in range(party.size()):
		if party[i]["hp"] > 0:
			return i
	return -1

func heal_all_creatures() -> void:
	for creature in party:
		creature["hp"] = creature["max_hp"]
		pass
	party_changed.emit()

func set_tool(tool_slot: String) -> void:
	print("[Hotbar Debug] set_tool('", tool_slot, "') — current_tool_slot changing from '", current_tool_slot, "' to '", tool_slot, "'")
	current_tool_slot = tool_slot
	tool_changed.emit(tool_slot)

func _init_hotbar() -> void:
	if hotbar.size() == HOTBAR_SIZE:
		return
	hotbar.clear()
	# All slots start empty — player assigns items from inventory
	while hotbar.size() < HOTBAR_SIZE:
		hotbar.append({})

func _sync_hotbar_to_server() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server() and multiplayer.get_unique_id() != 1:
		NetworkManager.request_sync_hotbar.rpc_id(1, hotbar, selected_hotbar_slot)

func select_hotbar_slot(index: int) -> void:
	if index < 0 or index >= HOTBAR_SIZE:
		return
	selected_hotbar_slot = index
	hotbar_selection_changed.emit(index)
	_sync_hotbar_to_server()
	# Translate to existing tool system for backward compat
	var slot_data = hotbar[index]
	if slot_data.is_empty():
		set_tool("")
		return
	var item_type: String = str(slot_data.get("item_type", ""))
	var item_id: String = str(slot_data.get("item_id", ""))
	print("[Hotbar Debug] select_hotbar_slot(", index, ") slot_data=", slot_data, " -> item_type=", item_type, " item_id=", item_id)
	match item_type:
		"tool_slot":
			set_tool(item_id)
		"seed":
			set_tool("seeds")
		_:
			set_tool("")

func assign_hotbar_slot(index: int, item_id: String, item_type: String) -> void:
	print("[Hotbar Debug] assign_hotbar_slot(", index, ", ", item_id, ", ", item_type, ")")
	if index < 0 or index >= HOTBAR_SIZE:
		return
	hotbar[index] = {"item_id": item_id, "item_type": item_type}
	hotbar_changed.emit()
	_sync_hotbar_to_server()
	# Re-apply selection if this was the active slot
	if index == selected_hotbar_slot:
		select_hotbar_slot(index)

func clear_hotbar_slot(index: int) -> void:
	if index < 0 or index >= HOTBAR_SIZE:
		return
	hotbar[index] = {}
	hotbar_changed.emit()
	_sync_hotbar_to_server()
	if index == selected_hotbar_slot:
		select_hotbar_slot(index)

func refill_watering_can() -> void:
	watering_can_current = get_watering_can_capacity()

func use_watering_can() -> bool:
	if watering_can_current > 0:
		watering_can_current -= 1
		return true
	return false

func set_compass_target(id: String) -> void:
	compass_target_id = id
	compass_target_changed.emit(id)
