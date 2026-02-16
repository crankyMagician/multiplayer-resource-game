extends Node

# Attached to each player - handles interactions with world objects
var peer_id: int = 0
var parent_body: CharacterBody3D = null

func _ready() -> void:
	parent_body = get_parent() as CharacterBody3D
	if parent_body:
		peer_id = parent_body.name.to_int()

func _process(_delta: float) -> void:
	if peer_id != multiplayer.get_unique_id():
		return
	if Input.is_action_just_pressed("interact"):
		_try_interact()
	if Input.is_action_just_pressed("cycle_tool"):
		_cycle_tool()
	# PvP challenge (V key)
	if Input.is_action_just_pressed("pvp_challenge"):
		_try_pvp_challenge()
	# Trade (T key)
	if Input.is_action_just_pressed("trade"):
		_try_trade()
	# Number keys for tool select
	if Input.is_action_just_pressed("tool_1"):
		PlayerData.set_tool("")
	elif Input.is_action_just_pressed("tool_2"):
		PlayerData.set_tool("hoe")
	elif Input.is_action_just_pressed("tool_3"):
		PlayerData.set_tool("axe")
	elif Input.is_action_just_pressed("tool_4"):
		PlayerData.set_tool("watering_can")
	elif Input.is_action_just_pressed("tool_5"):
		PlayerData.set_tool("seeds")

const TOOL_SLOTS = ["", "hoe", "axe", "watering_can", "seeds"]

func _cycle_tool() -> void:
	var idx = TOOL_SLOTS.find(PlayerData.current_tool_slot)
	if idx < 0:
		idx = 0
	var next = (idx + 1) % TOOL_SLOTS.size()
	PlayerData.set_tool(TOOL_SLOTS[next])

func _try_interact() -> void:
	if parent_body == null:
		return
	var pos = parent_body.global_position
	# Check for calendar board proximity (E key to view)
	var calendar = _find_nearest_area("calendar_board", pos, 3.0)
	if calendar and calendar.has_method("request_open_calendar"):
		calendar.request_open_calendar.rpc_id(1)
		return
	# Check for social NPC proximity (E key to talk)
	var social_npc = _find_nearest_area("social_npc", pos, 3.0)
	if social_npc and social_npc.has_method("request_talk"):
		social_npc.request_talk.rpc_id(1)
		return
	# Check for shop NPC proximity (E key to open shop)
	var shop = _find_nearest_area("shop_npc", pos, 3.0)
	if shop and shop.has_method("request_open_shop"):
		shop.request_open_shop.rpc_id(1)
		return
	# Check for trainer NPC proximity (E key to challenge)
	var trainer = _find_nearest_area("trainer_npc", pos, 4.0)
	if trainer and trainer.has_method("request_challenge"):
		trainer.request_challenge.rpc_id(1)
		return
	# Check for restaurant door proximity (interact key as alternative to walk-over)
	var door = _find_nearest_area("restaurant_door", pos, 3.0)
	if door:
		var door_owner = door.get_meta("owner_name", "") if door.has_meta("owner_name") else ""
		if door_owner != "":
			var rm = get_node_or_null("/root/Main/GameWorld/RestaurantManager")
			if rm:
				rm.request_enter_restaurant.rpc_id(1, door_owner)
			return
	# Check for storage station proximity
	var storage = _find_nearest_area("storage_station", pos, 3.0)
	if storage:
		_open_storage_ui()
		return
	# Check for crafting station proximity
	var station = _find_nearest_crafting_station(pos, 3.0)
	if station:
		_open_crafting_ui(station)
		return
	# Check for water source — find nearest FarmManager (works for both community and restaurant farms)
	var water_source = _find_nearest_area("water_source", pos, 3.0)
	if water_source:
		var nearest_fm = _find_nearest_farm_manager(pos)
		if nearest_fm:
			nearest_fm._request_refill.rpc_id(1)
		return
	# Check for farm plots — find nearest FarmManager
	var nearest_fm = _find_nearest_farm_manager(pos)
	if nearest_fm:
		var plot_idx = nearest_fm.get_nearest_plot(pos, 3.0)
		if plot_idx >= 0:
			_interact_with_plot(nearest_fm, plot_idx)
			return

func _interact_with_plot(farm_mgr: Node, plot_idx: int) -> void:
	var action = ""
	var extra = ""
	match PlayerData.current_tool_slot:
		"axe":
			action = "clear"
		"hoe":
			action = "till"
		"watering_can":
			action = "water"
		"seeds":
			action = "plant"
			extra = PlayerData.selected_seed_id
			if extra == "":
				print("No seed selected!")
				return
		"":
			action = "harvest"
	if action != "":
		farm_mgr.request_farm_action.rpc_id(1, plot_idx, action, extra)

func _try_pvp_challenge() -> void:
	if parent_body == null:
		return
	# Find nearest other player within 5 units
	var players_node = get_node_or_null("/root/Main/GameWorld/Players")
	if players_node == null:
		return
	var my_pos = parent_body.global_position
	var closest_peer: int = 0
	var closest_dist: float = 5.0
	for child in players_node.get_children():
		if child is CharacterBody3D:
			var other_peer = child.name.to_int()
			if other_peer == peer_id or other_peer <= 0:
				continue
			var dist = child.global_position.distance_to(my_pos)
			if dist < closest_dist:
				closest_dist = dist
				closest_peer = other_peer
	if closest_peer > 0:
		var battle_mgr = get_node_or_null("/root/Main/GameWorld/BattleManager")
		if battle_mgr:
			battle_mgr.send_pvp_challenge(closest_peer)
			print("Sent PvP challenge to peer ", closest_peer)

func _try_trade() -> void:
	if parent_body == null:
		return
	var players_node = get_node_or_null("/root/Main/GameWorld/Players")
	if players_node == null:
		return
	var my_pos = parent_body.global_position
	var closest_peer: int = 0
	var closest_dist: float = 5.0
	for child in players_node.get_children():
		if child is CharacterBody3D:
			var other_peer = child.name.to_int()
			if other_peer == peer_id or other_peer <= 0:
				continue
			var dist = child.global_position.distance_to(my_pos)
			if dist < closest_dist:
				closest_dist = dist
				closest_peer = other_peer
	if closest_peer > 0:
		NetworkManager.request_trade.rpc_id(1, closest_peer)
		print("Sent trade request to peer ", closest_peer)

func _find_nearest_area(meta_tag: String, pos: Vector3, max_dist: float) -> Area3D:
	var areas = get_tree().get_nodes_in_group(meta_tag)
	var closest: Area3D = null
	var closest_dist = max_dist
	for area in areas:
		if area is Area3D:
			var dist = area.global_position.distance_to(pos)
			if dist < closest_dist:
				closest_dist = dist
				closest = area
	return closest

func _find_nearest_farm_manager(pos: Vector3) -> Node:
	var farm_managers = get_tree().get_nodes_in_group("farm_manager")
	var closest: Node = null
	var closest_dist: float = INF
	for fm in farm_managers:
		if fm is Node3D:
			var dist = fm.global_position.distance_to(pos)
			if dist < closest_dist:
				closest_dist = dist
				closest = fm
	return closest

func _find_nearest_crafting_station(pos: Vector3, max_dist: float) -> Area3D:
	# Check for station-typed crafting areas
	for station_type in ["kitchen", "workbench", "cauldron"]:
		var area = _find_nearest_area("crafting_" + station_type, pos, max_dist)
		if area:
			return area
	# Fallback: check old "crafting_table" group (generic station)
	return _find_nearest_area("crafting_table", pos, max_dist)

func _open_storage_ui() -> void:
	var ui = get_node_or_null("/root/Main/GameWorld/UI/StorageUI")
	if ui and ui.has_method("open"):
		ui.open()

func _open_crafting_ui(station: Area3D = null) -> void:
	var ui = get_node_or_null("/root/Main/GameWorld/UI/CraftingUI")
	if ui:
		# Determine station type from group membership
		var station_type = ""
		if station:
			for stype in ["kitchen", "workbench", "cauldron"]:
				if station.is_in_group("crafting_" + stype):
					station_type = stype
					break
		if ui.has_method("open_for_station"):
			ui.open_for_station(station_type)
		else:
			ui.visible = !ui.visible
			if ui.visible and ui.has_method("refresh"):
				ui.refresh()
