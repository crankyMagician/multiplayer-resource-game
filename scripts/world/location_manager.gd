extends Node

# Server-side location discovery manager.
# No class_name — follows SocialManager pattern to avoid autoload reference issues.

var _locations: Array = [] # Cached array of LocationDef resources
var _frame_counter: int = 0
const CHECK_INTERVAL: int = 10 # Check every 10 physics frames (~6/sec)

func _ready() -> void:
	if not multiplayer.is_server():
		set_physics_process(false)
		return
	DataRegistry.ensure_loaded()
	_locations = DataRegistry.locations.values()
	print("[LocationManager] Loaded ", _locations.size(), " locations for discovery tracking")

func _physics_process(_delta: float) -> void:
	_frame_counter += 1
	if _frame_counter < CHECK_INTERVAL:
		return
	_frame_counter = 0

	var players_node = get_node_or_null("/root/Main/GameWorld/Players")
	if players_node == null:
		return

	var rest_mgr = get_node_or_null("/root/Main/GameWorld/RestaurantManager")

	for player_node in players_node.get_children():
		if player_node is MultiplayerSpawner:
			continue
		var peer_id = int(str(player_node.name))
		if peer_id not in NetworkManager.player_data_store:
			continue

		# Skip players in restaurants
		if rest_mgr:
			var loc = rest_mgr.player_location.get(peer_id, {})
			if loc.get("zone", "overworld") != "overworld":
				continue

		var discovered: Array = NetworkManager.player_data_store[peer_id].get("discovered_locations", [])
		var player_pos: Vector3 = player_node.position

		for loc_def in _locations:
			if loc_def.location_id in discovered:
				continue
			var dist = player_pos.distance_to(loc_def.world_position)
			if dist <= loc_def.discovery_radius:
				discovered.append(loc_def.location_id)
				NetworkManager.player_data_store[peer_id]["discovered_locations"] = discovered
				NetworkManager._notify_location_discovered.rpc_id(peer_id, loc_def.location_id, loc_def.display_name)
				# Quest progress: discover_location
				var quest_mgr = get_node_or_null("/root/Main/GameWorld/QuestManager")
				if quest_mgr:
					quest_mgr.notify_progress(peer_id, "discover_location", loc_def.location_id)
				print("[LocationManager] Player ", peer_id, " discovered: ", loc_def.display_name)
