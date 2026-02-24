extends Node

const RESTAURANT_SCENE = preload("res://scenes/world/restaurant_interior.tscn")

# Server state
var restaurant_instances: Dictionary = {} # owner_name -> RestaurantInterior node
var player_location: Dictionary = {} # peer_id -> {"zone": String, "owner": String}
var overworld_positions: Dictionary = {} # peer_id -> Vector3 (saved before teleport)
var next_restaurant_index: int = 0
var restaurant_index_map: Dictionary = {} # player_name -> int
var _exit_cooldown: Dictionary = {} # peer_id -> timestamp (prevent immediate re-entry)

var _indicator_time: float = 0.0
var _door_node: Node3D = null

func _ready() -> void:
	# Set up the static MyRestaurantDoor node (group + meta + server collision)
	_door_node = get_node_or_null("../Zones/MyRestaurantDoor")
	if _door_node:
		_door_node.add_to_group("restaurant_door")
		_door_node.set_meta("owner_name", "") # empty = use local player's name
		if multiplayer.is_server():
			_door_node.body_entered.connect(_on_static_door_entered)

func _process(delta: float) -> void:
	# Animate floating indicator on the static door
	if _door_node == null:
		return
	var door := _door_node
	_indicator_time += delta
	var bounce_y: float = sin(_indicator_time * 3.0) * 0.3
	var spin: float = _indicator_time * 90.0
	var indicator = door.get_node_or_null("FloatingIndicator")
	if indicator:
		indicator.position.y = 4.2 + bounce_y
		indicator.rotation_degrees.y = spin

func _on_static_door_entered(body: Node3D) -> void:
	if not multiplayer.is_server():
		return
	if not body is CharacterBody3D:
		return
	var peer_id = body.name.to_int()
	if peer_id <= 0:
		return
	# Static door enters the player's OWN restaurant
	var player_name := ""
	if peer_id in NetworkManager.player_data_store:
		player_name = NetworkManager.player_data_store[peer_id].get("player_name", "")
	if player_name == "":
		return
	_enter_restaurant_server(peer_id, player_name)

func allocate_restaurant_index(player_name: String) -> int:
	if player_name in restaurant_index_map:
		return restaurant_index_map[player_name]
	var idx = next_restaurant_index
	next_restaurant_index += 1
	restaurant_index_map[player_name] = idx
	return idx

func get_or_create_restaurant(owner_name: String) -> Node3D:
	if owner_name in restaurant_instances:
		return restaurant_instances[owner_name]
	# Find restaurant data from player_data_store
	var rest_data: Dictionary = {}
	var rest_index: int = -1
	for peer_id in NetworkManager.player_data_store:
		var data = NetworkManager.player_data_store[peer_id]
		if data.get("player_name", "") == owner_name:
			rest_data = data.get("restaurant", {})
			rest_index = rest_data.get("restaurant_index", -1)
			break
	if rest_index == -1:
		# Try the index map
		rest_index = restaurant_index_map.get(owner_name, -1)
	if rest_index == -1:
		rest_index = allocate_restaurant_index(owner_name)
	var instance = RESTAURANT_SCENE.instantiate()
	instance.name = "Restaurant_" + owner_name.replace(" ", "_")
	# Add to scene tree under GameWorld
	var game_world = get_parent()
	game_world.add_child(instance)
	instance.initialize(owner_name, rest_index, rest_data)
	restaurant_instances[owner_name] = instance
	# Connect exit door signal
	var exit_door = instance.get_node_or_null("ExitDoor")
	if exit_door:
		exit_door.body_entered.connect(_on_exit_door_body_entered.bind(owner_name))
	print("[Restaurant] Created restaurant for ", owner_name, " at index ", rest_index)
	return instance

func _on_exit_door_body_entered(body: Node3D, _owner_name: String) -> void:
	if not multiplayer.is_server():
		return
	if not body is CharacterBody3D:
		return
	var peer_id = body.name.to_int()
	if peer_id <= 0:
		return
	_exit_restaurant(peer_id)

# === Teleportation ===

@rpc("any_peer", "reliable")
func request_exit_restaurant() -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	var loc = player_location.get(sender, {})
	if loc.get("zone", "overworld") != "restaurant":
		return
	_exit_restaurant(sender)

@rpc("any_peer", "reliable")
func request_enter_restaurant(owner_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	_enter_restaurant_server(sender, owner_name)

func _exit_restaurant(peer_id: int) -> void:
	var loc = player_location.get(peer_id, {})
	if loc.get("zone", "overworld") != "restaurant":
		return
	var player_node = NetworkManager._get_player_node(peer_id)
	if player_node == null:
		return
	# Restore overworld position
	if peer_id in overworld_positions:
		var saved_pos = overworld_positions[peer_id]
		player_node.position = saved_pos
		overworld_positions.erase(peer_id)
	else:
		player_node.position = Vector3(-32.5, 5, 10) # Default: safely away from door
	player_node.velocity = Vector3.ZERO
	# Set cooldown to prevent immediate re-entry
	_exit_cooldown[peer_id] = Time.get_ticks_msec()
	# Update location
	player_location[peer_id] = {"zone": "overworld", "owner": ""}
	# Notify client
	_notify_location_change.rpc_id(peer_id, "overworld", "", -1)
	print("[Restaurant] Player ", peer_id, " exited restaurant")
	# Check if restaurant can be unloaded
	var owner_name = loc.get("owner", "")
	_try_unload_restaurant(owner_name)

func _try_unload_restaurant(owner_name: String) -> void:
	if owner_name not in restaurant_instances:
		return
	# Check if any player is still inside
	for peer_id in player_location:
		var loc = player_location[peer_id]
		if loc.get("zone", "") == "restaurant" and loc.get("owner", "") == owner_name:
			return # Someone is still inside
	# Save restaurant data before unloading
	_save_restaurant_data(owner_name)
	var instance = restaurant_instances[owner_name]
	instance.queue_free()
	restaurant_instances.erase(owner_name)
	print("[Restaurant] Unloaded empty restaurant: ", owner_name)

func _save_restaurant_data(owner_name: String) -> void:
	if owner_name not in restaurant_instances:
		return
	var instance = restaurant_instances[owner_name]
	var save_data = instance.get_save_data()
	# Find the peer_id for this owner and update their data store
	for peer_id in NetworkManager.player_data_store:
		var data = NetworkManager.player_data_store[peer_id]
		if data.get("player_name", "") == owner_name:
			var rest = data.get("restaurant", {})
			rest["farm_plots"] = save_data.get("farm_plots", [])
			data["restaurant"] = rest
			break

func _sync_restaurant_to_client(peer_id: int, instance: Node3D) -> void:
	if instance == null:
		return
	var fm = instance.farm_manager
	if fm == null:
		return
	# Send bulk farm data instead of per-plot RPCs (client may not have plot nodes)
	var plot_data: Array = []
	for plot in fm.plots:
		plot_data.append({
			"state": plot.plot_state,
			"seed_id": plot.planted_seed_id,
			"growth": plot.growth_progress,
			"water": plot.water_level,
			"owner_id": plot.owner_peer_id,
		})
	_receive_restaurant_farm_data.rpc_id(peer_id, plot_data)

func _enter_restaurant_server(peer_id: int, owner_name: String) -> void:
	# Don't allow entering if already in a restaurant
	var loc = player_location.get(peer_id, {})
	if loc.get("zone", "overworld") == "restaurant":
		return
	# Prevent immediate re-entry after exit (1 second cooldown)
	if peer_id in _exit_cooldown:
		if Time.get_ticks_msec() - _exit_cooldown[peer_id] < 1000:
			return
		_exit_cooldown.erase(peer_id)
	# Don't allow entering during battle
	var battle_mgr = get_node_or_null("/root/Main/GameWorld/BattleManager")
	if battle_mgr and battle_mgr.player_battle_map.has(peer_id):
		return
	var instance = get_or_create_restaurant(owner_name)
	if instance == null:
		return
	var player_node = NetworkManager._get_player_node(peer_id)
	if player_node == null:
		return
	overworld_positions[peer_id] = player_node.position
	var entry_pos = instance.position + Vector3(0, 1, 5)
	player_node.position = entry_pos
	player_node.velocity = Vector3.ZERO
	player_location[peer_id] = {"zone": "restaurant", "owner": owner_name}
	var rest_index = restaurant_index_map.get(owner_name, 0)
	# Notify client first (triggers client-side scene instantiation), then sync farm data
	_notify_location_change.rpc_id(peer_id, "restaurant", owner_name, rest_index)
	_sync_restaurant_to_client(peer_id, instance)
	print("[Restaurant] Player ", peer_id, " entered ", owner_name, "'s restaurant")

# === Farm Manager Routing ===

func get_farm_manager_for_peer(peer_id: int) -> Node:
	var loc = player_location.get(peer_id, {})
	if loc.get("zone", "") == "restaurant":
		var owner_name = loc.get("owner", "")
		if owner_name in restaurant_instances:
			return restaurant_instances[owner_name].farm_manager
	return get_node_or_null("/root/Main/GameWorld/Zones/FarmZone/FarmManager")

# === Save/Load ===

func get_save_data() -> Dictionary:
	return {
		"next_restaurant_index": next_restaurant_index,
		"restaurant_index_map": restaurant_index_map.duplicate(),
	}

func load_save_data(data: Dictionary) -> void:
	next_restaurant_index = int(data.get("next_restaurant_index", 0))
	restaurant_index_map = data.get("restaurant_index_map", {}).duplicate()

func update_all_restaurant_save_data() -> void:
	for owner_name in restaurant_instances:
		_save_restaurant_data(owner_name)

# === Disconnect Handling ===

func handle_player_disconnect(peer_id: int) -> void:
	var loc = player_location.get(peer_id, {})
	player_location.erase(peer_id)
	overworld_positions.erase(peer_id)
	var player_name = ""
	if peer_id in NetworkManager.player_data_store:
		player_name = NetworkManager.player_data_store[peer_id].get("player_name", "")
	# Check if any restaurant they were in should be unloaded
	if loc.get("zone", "") == "restaurant":
		var owner_name = loc.get("owner", "")
		if owner_name != "":
			_try_unload_restaurant(owner_name)
	# Also check their own restaurant
	if player_name != "":
		_try_unload_restaurant(player_name)

# === Player Connect ===

func handle_player_connected(peer_id: int) -> void:
	if peer_id not in NetworkManager.player_data_store:
		return
	var data = NetworkManager.player_data_store[peer_id]
	var player_name = data.get("player_name", "")
	if player_name == "" or player_name == "Server":
		return
	# Ensure restaurant index is allocated
	var rest = data.get("restaurant", {})
	if rest.get("restaurant_index", -1) == -1:
		rest["restaurant_index"] = allocate_restaurant_index(player_name)
		data["restaurant"] = rest
	elif player_name not in restaurant_index_map:
		restaurant_index_map[player_name] = rest["restaurant_index"]
		if rest["restaurant_index"] >= next_restaurant_index:
			next_restaurant_index = rest["restaurant_index"] + 1
	# Default location is overworld
	player_location[peer_id] = {"zone": "overworld", "owner": ""}

# === Client RPCs ===

# Client-side restaurant interior instance (only exists while player is inside)
var _client_restaurant_instance: Node3D = null

@rpc("authority", "reliable")
func _notify_location_change(zone: String, owner_name: String, rest_index: int = -1) -> void:
	PlayerData.current_zone = zone
	PlayerData.current_restaurant_owner = owner_name
	if zone == "restaurant" and owner_name != "":
		_client_enter_restaurant(owner_name, rest_index)
	else:
		_client_exit_restaurant()
	PlayerData.location_changed.emit(zone, owner_name)

func _client_enter_restaurant(owner_name: String, rest_index: int) -> void:
	# Remove any existing client-side restaurant
	if _client_restaurant_instance != null:
		_client_restaurant_instance.queue_free()
		_client_restaurant_instance = null
	# Diamond wipe in
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("play_screen_wipe"):
		await hud.play_screen_wipe()
	# Instantiate restaurant interior locally so farm plot RPCs can resolve
	var instance = RESTAURANT_SCENE.instantiate()
	instance.name = "Restaurant_" + owner_name.replace(" ", "_")
	var game_world = get_parent()
	game_world.add_child(instance)
	instance.initialize(owner_name, rest_index, {})
	_client_restaurant_instance = instance
	# Restaurant music + ambience
	AudioManager.play_music("restaurant")
	AudioManager.play_ambience(0, "restaurant")
	AudioManager.play_sfx("item_door")
	# Diamond wipe out
	if hud and hud.has_method("clear_screen_wipe"):
		await hud.clear_screen_wipe()

func _client_exit_restaurant() -> void:
	if _client_restaurant_instance != null:
		# Diamond wipe in
		var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
		if hud and hud.has_method("play_screen_wipe"):
			await hud.play_screen_wipe()
		_client_restaurant_instance.queue_free()
		_client_restaurant_instance = null
		# Restore overworld music + ambience
		AudioManager.play_music("overworld")
		AudioManager.play_ambience(0, "overworld")
		AudioManager.play_sfx("item_door")
		# Diamond wipe out
		if hud and hud.has_method("clear_screen_wipe"):
			await hud.clear_screen_wipe()
	# Reactivate local player camera after leaving restaurant
	var local_peer = multiplayer.get_unique_id()
	var player = get_node_or_null("/root/Main/GameWorld/Players/%d" % local_peer)
	if player and player.has_method("reactivate_camera"):
		player.reactivate_camera()

@rpc("authority", "reliable")
func _receive_restaurant_farm_data(plot_data: Array) -> void:
	if _client_restaurant_instance == null:
		return
	var fm = _client_restaurant_instance.farm_manager
	if fm == null:
		return
	# Apply bulk plot data to client-side farm plots
	for i in range(min(plot_data.size(), fm.plots.size())):
		var d = plot_data[i]
		var plot = fm.plots[i]
		plot.plot_state = d.get("state", 0)
		plot.planted_seed_id = d.get("seed_id", "")
		plot.growth_progress = d.get("growth", 0.0)
		plot.water_level = d.get("water", 0.0)
		plot.owner_peer_id = d.get("owner_id", 0)
		plot._update_visuals()
