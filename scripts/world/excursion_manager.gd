extends Node

## Server-authoritative excursion instance manager.
## Handles instance lifecycle, entry/exit, shared loot routing, and timeout.

signal excursion_member_changed(instance_id: String, peer_id: int, joined: bool)

const EXCURSION_BASE_OFFSET = Vector3(5000, 0, 0)
const EXCURSION_SPACING: float = 200.0
const MAX_EXCURSION_INSTANCES: int = 10
const INSTANCE_TIMEOUT_SEC: float = 900.0 # 15 minutes
const EXIT_COOLDOWN_MS: int = 2000
const WARNING_2MIN_SEC: float = 120.0
const WARNING_30S_SEC: float = 30.0
const STATUS_UPDATE_INTERVAL: float = 10.0

# Excursion bonus drop chances (battle victories)
const EXCURSION_INGREDIENT_DROP_CHANCE: float = 0.15
const EXCURSION_SEED_DROP_CHANCE: float = 0.05

var EXCURSION_BONUS_INGREDIENTS: Array = [
	"mystic_herb", "starfruit_essence", "truffle_shaving", "wild_honey",
]
var EXCURSION_BONUS_SEEDS: Array = [
	"golden_seed", "ancient_grain_seed",
]

# Server state
var excursion_instances: Dictionary = {} # instance_id -> ExcursionInstanceData dict
var player_excursion_map: Dictionary = {} # peer_id -> instance_id
var overworld_positions: Dictionary = {} # peer_id -> Vector3
var _exit_cooldown: Dictionary = {} # peer_id -> timestamp (ms)
var _entry_immunity: Dictionary = {} # peer_id -> timestamp (ms) - prevents instant exit portal trigger on spawn
var _instance_nodes: Dictionary = {} # instance_id -> Node3D (server collision tree)
var _next_offset_index: int = 0
var _status_timer: float = 0.0


func _ready() -> void:
	if not multiplayer.is_server():
		return
	# Connect to FriendManager party signals
	var friend_mgr := get_node_or_null("../FriendManager")
	if friend_mgr:
		if friend_mgr.has_signal("party_member_removed"):
			friend_mgr.party_member_removed.connect(_on_party_member_removed)
		if friend_mgr.has_signal("party_member_added"):
			friend_mgr.party_member_added.connect(_on_party_member_added)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_status_timer += delta
	if _status_timer < STATUS_UPDATE_INTERVAL:
		return
	_status_timer = 0.0

	var now := Time.get_unix_time_from_system()
	var to_cleanup: Array[String] = []

	for instance_id in excursion_instances:
		var inst: Dictionary = excursion_instances[instance_id]
		var elapsed: float = now - inst["created_at"]
		var remaining: float = INSTANCE_TIMEOUT_SEC - elapsed

		if remaining <= 0:
			# Timeout — force exit all members
			to_cleanup.append(instance_id)
			continue

		# Send time warnings
		var sent_warnings: Dictionary = inst.get("sent_warnings", {})
		if remaining <= WARNING_2MIN_SEC and not sent_warnings.get("2min", false):
			sent_warnings["2min"] = true
			inst["sent_warnings"] = sent_warnings
			for peer_id in inst["members"]:
				_excursion_time_warning.rpc_id(peer_id, 120)
		if remaining <= WARNING_30S_SEC and not sent_warnings.get("30s", false):
			sent_warnings["30s"] = true
			inst["sent_warnings"] = sent_warnings
			for peer_id in inst["members"]:
				_excursion_time_warning.rpc_id(peer_id, 30)

		# Send status updates to members
		var member_count: int = inst["members"].size()
		for peer_id in inst["members"]:
			_excursion_status_update.rpc_id(peer_id, int(remaining), member_count)

		# Clean up empty instances
		if inst["members"].is_empty():
			to_cleanup.append(instance_id)

	for instance_id in to_cleanup:
		_cleanup_instance(instance_id)


# === Public Interface (called by other managers) ===

func is_player_in_excursion(peer_id: int) -> bool:
	return peer_id in player_excursion_map


func get_instance_for_peer(peer_id: int) -> Dictionary:
	var instance_id: String = player_excursion_map.get(peer_id, "")
	if instance_id == "":
		return {}
	return excursion_instances.get(instance_id, {})


func get_instance_members(instance_id: String) -> Array:
	var inst: Dictionary = excursion_instances.get(instance_id, {})
	return inst.get("members", [])


func _on_excursion_item_pickup(peer_id: int, uid: int) -> void:
	## Called by WorldItemManager when a player in an excursion picks up an item.
	## Distributes the item to ALL current excursion members.
	var instance_id: String = player_excursion_map.get(peer_id, "")
	if instance_id == "":
		return
	var inst: Dictionary = excursion_instances.get(instance_id, {})
	if inst.is_empty():
		return

	var item_mgr := get_node_or_null("../WorldItemManager")
	if item_mgr == null:
		return
	if uid not in item_mgr.world_items:
		return

	var item_data: Dictionary = item_mgr.world_items[uid]
	var item_id: String = item_data["item_id"]
	var amount: int = item_data["amount"]

	# Grant to all current members
	for member_peer in inst["members"]:
		NetworkManager.server_add_inventory(member_peer, item_id, amount)
		NetworkManager._sync_inventory_full.rpc_id(member_peer,
			NetworkManager.player_data_store[member_peer].get("inventory", {}))
		if item_id.begins_with("fragment_"):
			NetworkManager._check_fragment_combine(member_peer, item_id)
		item_mgr._notify_pickup.rpc_id(member_peer, item_id, amount)

		# Audit log
		_log_loot(instance_id, member_peer, item_id, amount)

	# Remove world item (once, globally)
	item_mgr._remove_world_item(uid)
	print("[Excursion] Shared pickup: %s x%d to %d members" % [item_id, amount, inst["members"].size()])


func distribute_excursion_battle_rewards(peer_id: int, drops: Dictionary) -> void:
	## Called by BattleManager when a player in an excursion wins a battle.
	## Distributes drops to ALL current excursion members.
	var instance_id: String = player_excursion_map.get(peer_id, "")
	if instance_id == "":
		return
	var inst: Dictionary = excursion_instances.get(instance_id, {})
	if inst.is_empty():
		return

	# Add excursion bonus drops
	var bonus_drops := _roll_excursion_bonus_drops()
	for item_id in bonus_drops:
		drops[item_id] = drops.get(item_id, 0) + bonus_drops[item_id]

	# Grant drops to all members
	for member_peer in inst["members"]:
		for item_id in drops:
			NetworkManager.server_add_inventory(member_peer, item_id, drops[item_id])
			if item_id.begins_with("fragment_"):
				NetworkManager._check_fragment_combine(member_peer, item_id)
		NetworkManager._sync_inventory_full.rpc_id(member_peer,
			NetworkManager.player_data_store[member_peer].get("inventory", {}))
		_grant_excursion_battle_rewards.rpc_id(member_peer, drops)

		# Audit log
		for item_id in drops:
			_log_loot(instance_id, member_peer, item_id, drops[item_id])

	print("[Excursion] Shared battle drops to %d members: %s" % [inst["members"].size(), str(drops)])


func _on_excursion_harvest(peer_id: int, drops: Dictionary, object_type: String) -> void:
	## Called by harvestable_object.gd when a player in an excursion harvests something.
	## Distributes drops to ALL current excursion members.
	var instance_id: String = player_excursion_map.get(peer_id, "")
	if instance_id == "":
		return
	var inst: Dictionary = excursion_instances.get(instance_id, {})
	if inst.is_empty():
		return

	for member_peer in inst["members"]:
		for item_id in drops:
			NetworkManager.server_add_inventory(member_peer, item_id, drops[item_id])
		NetworkManager._sync_inventory_full.rpc_id(member_peer,
			NetworkManager.player_data_store[member_peer].get("inventory", {}))
		_notify_excursion_harvest.rpc_id(member_peer, object_type, drops)
		for item_id in drops:
			_log_loot(instance_id, member_peer, item_id, drops[item_id])

	print("[Excursion] Shared harvest (%s) to %d members: %s" % [object_type, inst["members"].size(), str(drops)])


func _on_excursion_dig(peer_id: int, items: Dictionary) -> void:
	## Called by dig_spot.gd when a player in an excursion digs a spot.
	## Distributes items to ALL current excursion members.
	var instance_id: String = player_excursion_map.get(peer_id, "")
	if instance_id == "":
		return
	var inst: Dictionary = excursion_instances.get(instance_id, {})
	if inst.is_empty():
		return

	for member_peer in inst["members"]:
		for item_id in items:
			NetworkManager.server_add_inventory(member_peer, item_id, items[item_id])
		NetworkManager._sync_inventory_full.rpc_id(member_peer,
			NetworkManager.player_data_store[member_peer].get("inventory", {}))
		_notify_excursion_dig.rpc_id(member_peer, items)
		for item_id in items:
			_log_loot(instance_id, member_peer, item_id, items[item_id])

	print("[Excursion] Shared dig to %d members: %s" % [inst["members"].size(), str(items)])


func get_level_boost_for_peer(peer_id: int) -> int:
	## Returns level boost based on party size for excursion encounters.
	var inst := get_instance_for_peer(peer_id)
	if inst.is_empty():
		return 0
	var party_size: int = inst["members"].size()
	# level_boost = floor(0.25 * (party_size - 1) * base_max_level)
	# Approximate with a fixed boost since we don't know base_max_level here
	return int(floor(0.25 * (party_size - 1) * 15))


# === Entry Flow ===

func _create_excursion_from_portal(peer_id: int) -> void:
	## Called by game_world.gd when party leader walks into portal Area3D.
	## Runs on server — performs same validation as request_enter_excursion.
	_validate_and_enter(peer_id)

@rpc("any_peer", "reliable")
func request_enter_excursion() -> void:
	if not multiplayer.is_server():
		return
	_validate_and_enter(multiplayer.get_remote_sender_id())


func _validate_and_enter(sender_peer: int) -> void:
	var nm := NetworkManager

	var player_id: String = nm.get_player_id_for_peer(sender_peer)
	if player_id == "":
		_excursion_action_result.rpc_id(sender_peer, "enter", false, "Player not found.")
		return

	# Must be in a party
	var friend_mgr := get_node_or_null("../FriendManager")
	if friend_mgr == null:
		_excursion_action_result.rpc_id(sender_peer, "enter", false, "Party system unavailable.")
		return

	# Check max instances
	if excursion_instances.size() >= MAX_EXCURSION_INSTANCES:
		_excursion_action_result.rpc_id(sender_peer, "enter", false, "Too many active excursions. Try again later.")
		return

	var battle_mgr := get_node_or_null("../BattleManager")
	var rest_mgr := get_node_or_null("../RestaurantManager")

	# Solo player (not in a party)
	if player_id not in friend_mgr.player_party_map:
		# Validate solo player state
		if sender_peer in player_excursion_map:
			_excursion_action_result.rpc_id(sender_peer, "enter", false, "You are already in an excursion.")
			return
		if battle_mgr and sender_peer in battle_mgr.player_battle_map:
			_excursion_action_result.rpc_id(sender_peer, "enter", false, "You are in battle.")
			return
		if rest_mgr:
			var loc: Dictionary = rest_mgr.player_location.get(sender_peer, {})
			if loc.get("zone", "") == "restaurant":
				_excursion_action_result.rpc_id(sender_peer, "enter", false, "You are in a restaurant.")
				return
		var solo_node := nm._get_player_node(sender_peer)
		if solo_node and solo_node.get("is_busy"):
			_excursion_action_result.rpc_id(sender_peer, "enter", false, "You are busy.")
			return
		# All solo checks passed — create solo instance
		_create_excursion_instance(-1, {}, [player_id])
		return

	var party_id: int = friend_mgr.player_party_map[player_id]
	var party: Dictionary = friend_mgr.parties.get(party_id, {})
	if party.is_empty():
		_excursion_action_result.rpc_id(sender_peer, "enter", false, "Party not found.")
		return

	# Must be party leader
	if str(party["leader_id"]) != player_id:
		_excursion_action_result.rpc_id(sender_peer, "enter", false, "Only the party leader can start an excursion.")
		return

	# Check no party member is busy/in-battle/in-restaurant/in-excursion
	var members: Array = party["members"]

	for member_id in members:
		var member_peer: int = nm.get_peer_for_player_id(member_id)
		if member_peer <= 0:
			_excursion_action_result.rpc_id(sender_peer, "enter", false, "Party member is offline.")
			return
		if member_peer in player_excursion_map:
			_excursion_action_result.rpc_id(sender_peer, "enter", false, "A party member is already in an excursion.")
			return
		if battle_mgr and member_peer in battle_mgr.player_battle_map:
			_excursion_action_result.rpc_id(sender_peer, "enter", false, "A party member is in battle.")
			return
		if rest_mgr:
			var loc: Dictionary = rest_mgr.player_location.get(member_peer, {})
			if loc.get("zone", "") == "restaurant":
				_excursion_action_result.rpc_id(sender_peer, "enter", false, "A party member is in a restaurant.")
				return
		var player_node := nm._get_player_node(member_peer)
		if player_node and player_node.get("is_busy"):
			_excursion_action_result.rpc_id(sender_peer, "enter", false, "A party member is busy.")
			return

	# All checks passed — create instance
	_create_excursion_instance(party_id, party, members)


func _create_excursion_instance(party_id: int, party: Dictionary, members: Array) -> void:
	var instance_id: String = _generate_uuid()
	var seed_val: int = randi()
	var season: String = _get_current_season()
	var offset_index: int = _next_offset_index
	_next_offset_index += 1
	var offset: Vector3 = EXCURSION_BASE_OFFSET + Vector3(offset_index * EXCURSION_SPACING, 0, 0)

	# Build allowed_player_ids from current party
	var allowed_ids: Array = members.duplicate()

	var inst: Dictionary = {
		"instance_id": instance_id,
		"party_id": party_id,
		"seed": seed_val,
		"season": season,
		"created_at": Time.get_unix_time_from_system(),
		"last_activity": Time.get_unix_time_from_system(),
		"members": [], # peer_ids currently inside (populated below)
		"allowed_player_ids": allowed_ids,
		"offset": {"x": offset.x, "y": offset.y, "z": offset.z},
		"offset_index": offset_index,
		"loot_log": {},
		"sent_warnings": {},
	}

	excursion_instances[instance_id] = inst

	# Generate server-side collision/encounter tree
	var server_node := ExcursionGenerator.generate_server(seed_val, season, offset)
	get_parent().add_child(server_node)
	_instance_nodes[instance_id] = server_node

	# Connect exit portal
	var exit_portal := server_node.get_node_or_null("ExcursionExitPortal")
	if exit_portal:
		exit_portal.body_entered.connect(_on_exit_portal_entered.bind(instance_id))

	# Connect encounter zones to encounter system
	_connect_encounter_zones(server_node, instance_id)

	# Spawn excursion world items
	var item_mgr := get_node_or_null("../WorldItemManager")
	if item_mgr:
		var spawn_points := ExcursionGenerator.get_item_spawn_points(seed_val, season, Vector3.ZERO)
		for sp in spawn_points:
			var world_pos: Vector3 = offset + sp["position"]
			item_mgr.spawn_world_item(sp["item_id"], sp["amount"], world_pos, 0.0, "excursion_" + instance_id)

	# Spawn harvestable objects (trees, rocks, bushes)
	var harvestable_points := ExcursionGenerator.get_harvestable_spawn_points(seed_val, season, Vector3.ZERO)
	var harvestable_script = load("res://scripts/world/harvestable_object.gd")
	for hp in harvestable_points:
		var h_node := Node3D.new()
		h_node.set_script(harvestable_script)
		h_node.harvestable_type = hp["type"]
		h_node.drops = hp["drops"]
		match hp["type"]:
			"tree":
				h_node.required_tool = "axe"
				h_node.max_health = 3
				h_node.respawn_time = 120.0
			"rock":
				h_node.required_tool = "axe"
				h_node.max_health = 4
				h_node.respawn_time = 150.0
			"bush":
				h_node.required_tool = ""
				h_node.max_health = 1
				h_node.respawn_time = 90.0
		h_node.position = offset + hp["position"]
		h_node.name = "ExcursionHarvestable_%d" % harvestable_points.find(hp)
		server_node.add_child(h_node)

	# Spawn dig spots
	var dig_points := ExcursionGenerator.get_dig_spot_points(seed_val, season, Vector3.ZERO)
	var dig_script = load("res://scripts/world/dig_spot.gd")
	for dp in dig_points:
		var d_node := Area3D.new()
		d_node.set_script(dig_script)
		d_node.spot_id = dp["spot_id"]
		d_node.loot_table = dp["loot_table"]
		d_node.position = offset + dp["position"]
		d_node.name = "ExcursionDigSpot_%d" % dig_points.find(dp)
		server_node.add_child(d_node)

	# Teleport all online party members
	var spawn_point: Vector3 = offset + ExcursionGenerator.get_spawn_point(Vector3.ZERO)
	for member_id in members:
		var member_peer: int = NetworkManager.get_peer_for_player_id(member_id)
		if member_peer > 0:
			_enter_member(member_peer, instance_id, spawn_point, seed_val, season, offset)

	print("[Excursion] Created instance %s (seed=%d, season=%s, party=%d, %d members)" % [
		instance_id, seed_val, season, party_id, inst["members"].size()])


func _enter_member(peer_id: int, instance_id: String, spawn_point: Vector3, seed_val: int, season: String, offset: Vector3) -> void:
	var inst: Dictionary = excursion_instances.get(instance_id, {})
	if inst.is_empty():
		return

	# Save overworld position
	var player_node := NetworkManager._get_player_node(peer_id)
	if player_node:
		overworld_positions[peer_id] = player_node.position
		player_node.position = spawn_point
		player_node.velocity = Vector3.ZERO

	# Track state
	player_excursion_map[peer_id] = instance_id
	if peer_id not in inst["members"]:
		inst["members"].append(peer_id)
	# Grace period — prevent exit portal from firing on spawn overlap
	_entry_immunity[peer_id] = Time.get_ticks_msec()

	# Update restaurant manager location tracking
	var rest_mgr := get_node_or_null("../RestaurantManager")
	if rest_mgr:
		rest_mgr.player_location[peer_id] = {"zone": "excursion", "owner": instance_id}

	# Notify client
	_enter_excursion_client.rpc_id(peer_id, instance_id, seed_val, season, offset.x, offset.y, offset.z)

	# Sync world items for this instance
	var item_mgr := get_node_or_null("../WorldItemManager")
	if item_mgr:
		var source_tag: String = "excursion_" + instance_id
		for uid in item_mgr.world_items:
			var item_data: Dictionary = item_mgr.world_items[uid]
			if item_data.get("source", "") == source_tag:
				var pos: Dictionary = item_data["position"]
				item_mgr._spawn_world_item_client.rpc_id(peer_id, uid, item_data["item_id"], item_data["amount"], pos["x"], pos["y"], pos["z"])

	excursion_member_changed.emit(instance_id, peer_id, true)


# === Exit Flow ===

@rpc("any_peer", "reliable")
func request_exit_excursion() -> void:
	if not multiplayer.is_server():
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	if sender_peer not in player_excursion_map:
		return
	# Cooldown check
	var now_ms: int = Time.get_ticks_msec()
	if sender_peer in _exit_cooldown and now_ms - _exit_cooldown[sender_peer] < EXIT_COOLDOWN_MS:
		return
	_exit_cooldown[sender_peer] = now_ms
	_exit_member(sender_peer)


func _exit_member(peer_id: int) -> void:
	var instance_id: String = player_excursion_map.get(peer_id, "")
	if instance_id == "":
		return

	# Restore overworld position
	var player_node := NetworkManager._get_player_node(peer_id)
	if player_node and peer_id in overworld_positions:
		player_node.position = overworld_positions[peer_id]
		player_node.velocity = Vector3.ZERO
	overworld_positions.erase(peer_id)
	_entry_immunity.erase(peer_id)

	# Clear maps
	player_excursion_map.erase(peer_id)

	# Update restaurant manager location tracking
	var rest_mgr := get_node_or_null("../RestaurantManager")
	if rest_mgr:
		rest_mgr.player_location[peer_id] = {"zone": "overworld", "owner": ""}

	# Toggle monitoring on overworld excursion portal to reset body_entered tracking after teleport
	var portal_area := get_node_or_null("../ExcursionEntrance/ExcursionPortalArea")
	if portal_area and portal_area is Area3D:
		portal_area.monitoring = false
		portal_area.set_deferred("monitoring", true)

	# Remove from instance members
	var inst: Dictionary = excursion_instances.get(instance_id, {})
	if not inst.is_empty():
		inst["members"].erase(peer_id)

	# Notify client
	_exit_excursion_client.rpc_id(peer_id)

	excursion_member_changed.emit(instance_id, peer_id, false)

	# Clean up if no members remain
	if not inst.is_empty() and inst["members"].is_empty():
		_cleanup_instance(instance_id)


func _on_exit_portal_entered(body: Node3D, instance_id: String) -> void:
	if not multiplayer.is_server():
		return
	if not body is CharacterBody3D:
		return
	var peer_id: int = body.name.to_int()
	if peer_id <= 0:
		return
	if player_excursion_map.get(peer_id, "") != instance_id:
		return
	# Grace period — player spawns near the exit portal, skip for 3 seconds
	if peer_id in _entry_immunity:
		var elapsed: int = Time.get_ticks_msec() - _entry_immunity[peer_id]
		if elapsed < 3000:
			return
		_entry_immunity.erase(peer_id)
	_exit_member(peer_id)


# === Late-Join Flow ===

@rpc("any_peer", "reliable")
func request_excursion_late_join() -> void:
	if not multiplayer.is_server():
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	var player_id: String = NetworkManager.get_player_id_for_peer(sender_peer)
	if player_id == "":
		_excursion_action_result.rpc_id(sender_peer, "late_join", false, "Player not found.")
		return

	# Already in excursion?
	if sender_peer in player_excursion_map:
		_excursion_action_result.rpc_id(sender_peer, "late_join", false, "Already in an excursion.")
		return

	# Find party → instance
	var friend_mgr := get_node_or_null("../FriendManager")
	if friend_mgr == null or player_id not in friend_mgr.player_party_map:
		_excursion_action_result.rpc_id(sender_peer, "late_join", false, "Not in a party.")
		return

	var party_id: int = friend_mgr.player_party_map[player_id]

	# Find instance for this party
	var target_instance_id: String = ""
	for inst_id in excursion_instances:
		if excursion_instances[inst_id]["party_id"] == party_id:
			target_instance_id = inst_id
			break

	if target_instance_id == "":
		_excursion_action_result.rpc_id(sender_peer, "late_join", false, "No active excursion for your party.")
		return

	var inst: Dictionary = excursion_instances[target_instance_id]

	# Check allowed
	if player_id not in inst["allowed_player_ids"]:
		_excursion_action_result.rpc_id(sender_peer, "late_join", false, "Not authorized for this excursion.")
		return

	# Check not timed out
	var now := Time.get_unix_time_from_system()
	if now - inst["created_at"] >= INSTANCE_TIMEOUT_SEC:
		_excursion_action_result.rpc_id(sender_peer, "late_join", false, "Excursion has expired.")
		return

	# Check busy/battle state
	var battle_mgr := get_node_or_null("../BattleManager")
	if battle_mgr and sender_peer in battle_mgr.player_battle_map:
		_excursion_action_result.rpc_id(sender_peer, "late_join", false, "Cannot join while in battle.")
		return
	var player_node := NetworkManager._get_player_node(sender_peer)
	if player_node and player_node.get("is_busy"):
		_excursion_action_result.rpc_id(sender_peer, "late_join", false, "Cannot join while busy.")
		return

	# Enter
	var offset := Vector3(inst["offset"]["x"], inst["offset"]["y"], inst["offset"]["z"])
	var spawn_point: Vector3 = offset + ExcursionGenerator.get_spawn_point(Vector3.ZERO)
	_enter_member(sender_peer, target_instance_id, spawn_point, inst["seed"], inst["season"], offset)
	_excursion_action_result.rpc_id(sender_peer, "late_join", true, "Joined the excursion!")
	print("[Excursion] Late-joiner peer %d entered instance %s" % [sender_peer, target_instance_id])


# === Disconnect Handling ===

func handle_disconnect(peer_id: int) -> void:
	if peer_id in player_excursion_map:
		_exit_member(peer_id)


# === Party Event Handling ===

func _on_party_member_removed(party_id: int, player_id: String, _reason: String) -> void:
	## When a player is removed from a party, force exit them from excursion if applicable.
	var peer_id: int = NetworkManager.get_peer_for_player_id(player_id)
	if peer_id <= 0:
		return
	if peer_id not in player_excursion_map:
		return
	var instance_id: String = player_excursion_map[peer_id]
	var inst: Dictionary = excursion_instances.get(instance_id, {})
	if inst.is_empty():
		return
	if inst["party_id"] == party_id:
		_exit_member(peer_id)


func _on_party_member_added(party_id: int, player_id: String) -> void:
	## When a new member joins a party with an active excursion, add them to allowed list.
	for instance_id in excursion_instances:
		var inst: Dictionary = excursion_instances[instance_id]
		if inst["party_id"] == party_id:
			if player_id not in inst["allowed_player_ids"]:
				inst["allowed_player_ids"].append(player_id)
			break


# === Cleanup ===

func _cleanup_instance(instance_id: String) -> void:
	var inst: Dictionary = excursion_instances.get(instance_id, {})
	if inst.is_empty():
		excursion_instances.erase(instance_id)
		return

	# Force exit remaining members
	var remaining_members: Array = inst["members"].duplicate()
	for peer_id in remaining_members:
		_exit_member(peer_id)

	# Remove server collision tree
	if instance_id in _instance_nodes:
		var node: Node3D = _instance_nodes[instance_id]
		if is_instance_valid(node):
			node.queue_free()
		_instance_nodes.erase(instance_id)

	# Remove excursion world items
	var item_mgr := get_node_or_null("../WorldItemManager")
	if item_mgr:
		var source_tag: String = "excursion_" + instance_id
		var uids_to_remove: Array[int] = []
		for uid in item_mgr.world_items:
			if item_mgr.world_items[uid].get("source", "") == source_tag:
				uids_to_remove.append(uid)
		for uid in uids_to_remove:
			item_mgr._remove_world_item(uid)

	excursion_instances.erase(instance_id)
	print("[Excursion] Cleaned up instance %s" % instance_id)


# === Encounter Zone Wiring ===

func _connect_encounter_zones(server_node: Node3D, instance_id: String) -> void:
	## Connects excursion encounter Area3Ds to the encounter system.
	for child in server_node.get_children():
		if child is Area3D and child.has_meta("is_excursion_encounter"):
			child.body_entered.connect(_on_excursion_zone_entered.bind(child, instance_id))
			child.body_exited.connect(_on_excursion_zone_exited.bind(child))


var _excursion_step_counters: Dictionary = {} # peer_id -> step_count

func _on_excursion_zone_entered(body: Node3D, zone: Area3D, _instance_id: String) -> void:
	if not multiplayer.is_server():
		return
	if not body is CharacterBody3D:
		return
	var peer_id: int = body.name.to_int()
	if peer_id <= 0:
		return
	_excursion_step_counters[peer_id] = 0
	# Show grass indicator on client
	_show_excursion_grass.rpc_id(peer_id, true, zone.get_meta("is_rare", false))


func _on_excursion_zone_exited(body: Node3D, _zone: Area3D) -> void:
	if not multiplayer.is_server():
		return
	if not body is CharacterBody3D:
		return
	var peer_id: int = body.name.to_int()
	if peer_id <= 0:
		return
	_excursion_step_counters.erase(peer_id)
	_show_excursion_grass.rpc_id(peer_id, false, false)


# Excursion encounter processing (called from _physics_process of excursion encounter areas)
# We handle this in ExcursionManager's own processing to avoid needing a script on each Area3D
var _encounter_check_timer: float = 0.0

func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_encounter_check_timer += delta
	if _encounter_check_timer < 0.1: # Check every ~6 physics frames
		return
	_encounter_check_timer = 0.0

	var players_node := get_node_or_null("/root/Main/GameWorld/Players")
	var battle_mgr := get_node_or_null("/root/Main/GameWorld/BattleManager")
	var encounter_mgr := get_node_or_null("/root/Main/GameWorld/EncounterManager")

	if players_node == null or encounter_mgr == null:
		return

	for peer_id in _excursion_step_counters.keys():
		if battle_mgr and peer_id in battle_mgr.player_battle_map:
			continue
		var player := players_node.get_node_or_null(str(peer_id))
		if player == null or not player is CharacterBody3D:
			continue
		if player.get("is_busy"):
			continue
		if player.velocity.length() > 0.5:
			_excursion_step_counters[peer_id] += 1
			if _excursion_step_counters[peer_id] >= 10: # step_threshold
				_excursion_step_counters[peer_id] = 0
				if randf() < 0.15: # encounter_chance
					# Determine which zone the player is in
					var table_id: String = _get_encounter_table_for_peer(peer_id)
					if table_id != "":
						# Apply level boost
						encounter_mgr.start_encounter(peer_id, table_id)


func _get_encounter_table_for_peer(peer_id: int) -> String:
	## Finds the encounter table for the zone the player is currently overlapping.
	for instance_id in _instance_nodes:
		var node: Node3D = _instance_nodes[instance_id]
		if not is_instance_valid(node):
			continue
		for child in node.get_children():
			if child is Area3D and child.has_meta("is_excursion_encounter"):
				if child.has_overlapping_bodies():
					for body in child.get_overlapping_bodies():
						if body.name.to_int() == peer_id:
							return child.get_meta("encounter_table_id", "excursion_common")
	return ""


# === Helpers ===

func _generate_uuid() -> String:
	var chars := "abcdef0123456789"
	var uuid := ""
	for i in range(32):
		if i in [8, 12, 16, 20]:
			uuid += "-"
		uuid += chars[randi() % chars.length()]
	return uuid


func _get_current_season() -> String:
	var season_mgr := get_node_or_null("../SeasonManager")
	if season_mgr and season_mgr.has_method("get_season_name"):
		return season_mgr.get_season_name()
	return "spring"


func _roll_excursion_bonus_drops() -> Dictionary:
	var drops: Dictionary = {}
	if randf() < EXCURSION_INGREDIENT_DROP_CHANCE:
		var ing: String = EXCURSION_BONUS_INGREDIENTS[randi() % EXCURSION_BONUS_INGREDIENTS.size()]
		drops[ing] = 1
	if randf() < EXCURSION_SEED_DROP_CHANCE:
		var seed_item: String = EXCURSION_BONUS_SEEDS[randi() % EXCURSION_BONUS_SEEDS.size()]
		drops[seed_item] = 1
	return drops


func _log_loot(instance_id: String, peer_id: int, item_id: String, amount: int) -> void:
	var inst: Dictionary = excursion_instances.get(instance_id, {})
	if inst.is_empty():
		return
	var log: Dictionary = inst.get("loot_log", {})
	var peer_key: String = str(peer_id)
	if peer_key not in log:
		log[peer_key] = {}
	log[peer_key][item_id] = log[peer_key].get(item_id, 0) + amount
	inst["loot_log"] = log


# === Client RPCs ===

@rpc("authority", "reliable")
func _enter_excursion_client(instance_id: String, seed_val: int, season: String, offset_x: float, offset_y: float, offset_z: float) -> void:
	if multiplayer.is_server():
		return
	var offset := Vector3(offset_x, offset_y, offset_z)
	# Generate client-side visuals
	var visuals := ExcursionGenerator.generate_client(seed_val, season, offset)
	var game_world := get_node_or_null("/root/Main/GameWorld")
	if game_world:
		game_world.add_child(visuals)
	# Create client-side harvestable nodes at deterministic positions
	var harvestable_points := ExcursionGenerator.get_harvestable_spawn_points(seed_val, season, Vector3.ZERO)
	var harvestable_script = load("res://scripts/world/harvestable_object.gd")
	for i in range(harvestable_points.size()):
		var hp: Dictionary = harvestable_points[i]
		var h_node := Node3D.new()
		h_node.set_script(harvestable_script)
		h_node.harvestable_type = hp["type"]
		h_node.drops = hp["drops"]
		match hp["type"]:
			"tree":
				h_node.required_tool = "axe"
				h_node.max_health = 3
				h_node.respawn_time = 120.0
			"rock":
				h_node.required_tool = "axe"
				h_node.max_health = 4
				h_node.respawn_time = 150.0
			"bush":
				h_node.required_tool = ""
				h_node.max_health = 1
				h_node.respawn_time = 90.0
		h_node.position = offset + hp["position"]
		h_node.name = "ExcursionHarvestable_%d" % i
		visuals.add_child(h_node)

	# Create client-side dig spot nodes at deterministic positions
	var dig_points := ExcursionGenerator.get_dig_spot_points(seed_val, season, Vector3.ZERO)
	var dig_script = load("res://scripts/world/dig_spot.gd")
	for i in range(dig_points.size()):
		var dp: Dictionary = dig_points[i]
		var d_node := Area3D.new()
		d_node.set_script(dig_script)
		d_node.spot_id = dp["spot_id"]
		d_node.loot_table = dp["loot_table"]
		d_node.position = offset + dp["position"]
		d_node.name = "ExcursionDigSpot_%d" % i
		visuals.add_child(d_node)

	# Store reference for cleanup
	set_meta("_client_visuals", visuals)
	set_meta("_in_excursion", true)
	set_meta("_excursion_id", instance_id)
	# Show excursion HUD
	var excursion_hud := get_node_or_null("/root/Main/GameWorld/UI/ExcursionHUD")
	if excursion_hud:
		excursion_hud.show_excursion()
	# Update PlayerData location
	PlayerData.current_zone = "excursion"
	print("[Excursion Client] Entered excursion %s" % instance_id)


@rpc("authority", "reliable")
func _exit_excursion_client() -> void:
	if multiplayer.is_server():
		return
	# Remove client visuals
	var visuals = get_meta("_client_visuals") if has_meta("_client_visuals") else null
	if visuals != null and is_instance_valid(visuals):
		visuals.queue_free()
	remove_meta("_client_visuals")
	remove_meta("_in_excursion")
	remove_meta("_excursion_id")
	# Hide excursion HUD
	var excursion_hud := get_node_or_null("/root/Main/GameWorld/UI/ExcursionHUD")
	if excursion_hud:
		excursion_hud.hide_excursion()
	# Update PlayerData location
	PlayerData.current_zone = "overworld"
	print("[Excursion Client] Exited excursion")


@rpc("authority", "reliable")
func _excursion_action_result(action: String, success: bool, message: String) -> void:
	if multiplayer.is_server():
		return
	var hud := get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("show_toast"):
		hud.show_toast(message)
	print("[Excursion Client] %s: %s - %s" % [action, str(success), message])


@rpc("authority", "reliable")
func _excursion_status_update(time_remaining_sec: int, member_count: int) -> void:
	if multiplayer.is_server():
		return
	var excursion_hud := get_node_or_null("/root/Main/GameWorld/UI/ExcursionHUD")
	if excursion_hud and excursion_hud.has_method("update_status"):
		excursion_hud.update_status(time_remaining_sec, member_count)


@rpc("authority", "reliable")
func _excursion_time_warning(seconds_remaining: int) -> void:
	if multiplayer.is_server():
		return
	var hud := get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("show_toast"):
		if seconds_remaining >= 60:
			hud.show_toast("Excursion ends in %d minutes!" % (seconds_remaining / 60))
		else:
			hud.show_toast("Excursion ends in %d seconds!" % seconds_remaining)
	var excursion_hud := get_node_or_null("/root/Main/GameWorld/UI/ExcursionHUD")
	if excursion_hud and excursion_hud.has_method("flash_warning"):
		excursion_hud.flash_warning()


@rpc("authority", "reliable")
func _grant_excursion_battle_rewards(drops: Dictionary) -> void:
	if multiplayer.is_server():
		return
	for item_id in drops:
		PlayerData.add_to_inventory(item_id, drops[item_id])
	# Show pickup notifications
	var hud := get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("show_pickup_notification"):
		DataRegistry.ensure_loaded()
		for item_id in drops:
			var info := DataRegistry.get_item_display_info(item_id)
			var display_name: String = info.get("display_name", item_id)
			hud.show_pickup_notification(display_name, drops[item_id])


@rpc("authority", "reliable")
func _show_excursion_grass(visible_state: bool, is_rare: bool) -> void:
	if multiplayer.is_server():
		return
	var hud := get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("show_grass_indicator"):
		hud.show_grass_indicator(visible_state)


@rpc("authority", "reliable")
func _notify_excursion_harvest(object_type: String, drops: Dictionary) -> void:
	if multiplayer.is_server():
		return
	for item_id in drops:
		PlayerData.add_to_inventory(item_id, drops[item_id])
	var hud := get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("show_toast"):
		hud.show_toast("Party harvested %s!" % object_type)
	if hud and hud.has_method("show_pickup_notification"):
		DataRegistry.ensure_loaded()
		for item_id in drops:
			var info := DataRegistry.get_item_display_info(item_id)
			var display_name: String = info.get("display_name", item_id)
			hud.show_pickup_notification(display_name, drops[item_id])


@rpc("authority", "reliable")
func _notify_excursion_dig(items: Dictionary) -> void:
	if multiplayer.is_server():
		return
	for item_id in items:
		PlayerData.add_to_inventory(item_id, items[item_id])
	var hud := get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("show_pickup_notification"):
		DataRegistry.ensure_loaded()
		for item_id in items:
			var info := DataRegistry.get_item_display_info(item_id)
			var display_name: String = info.get("display_name", item_id)
			hud.show_pickup_notification(display_name, items[item_id])
	if hud and hud.has_method("show_toast"):
		hud.show_toast("Party dug up items!")
