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
	# Number keys for tool select
	if Input.is_action_just_pressed("tool_1"):
		PlayerData.set_tool(PlayerData.Tool.HANDS)
	elif Input.is_action_just_pressed("tool_2"):
		PlayerData.set_tool(PlayerData.Tool.HOE)
	elif Input.is_action_just_pressed("tool_3"):
		PlayerData.set_tool(PlayerData.Tool.AXE)
	elif Input.is_action_just_pressed("tool_4"):
		PlayerData.set_tool(PlayerData.Tool.WATERING_CAN)
	elif Input.is_action_just_pressed("tool_5"):
		PlayerData.set_tool(PlayerData.Tool.SEEDS)

func _cycle_tool() -> void:
	var next = (PlayerData.current_tool + 1) % PlayerData.Tool.size()
	PlayerData.set_tool(next as PlayerData.Tool)

func _try_interact() -> void:
	if parent_body == null:
		return
	var pos = parent_body.global_position
	# Check for crafting table proximity
	var crafting_table = _find_nearest_area("crafting_table", pos, 3.0)
	if crafting_table:
		_open_crafting_ui()
		return
	# Check for water source
	var water_source = _find_nearest_area("water_source", pos, 3.0)
	if water_source:
		var water_farm_mgr = get_node_or_null("/root/Main/GameWorld/Zones/FarmZone/FarmManager")
		if water_farm_mgr:
			water_farm_mgr._request_refill.rpc_id(1)
		return
	# Check for farm plots
	var farm_mgr = get_node_or_null("/root/Main/GameWorld/Zones/FarmZone/FarmManager")
	if farm_mgr:
		var plot_idx = farm_mgr.get_nearest_plot(pos, 3.0)
		if plot_idx >= 0:
			_interact_with_plot(farm_mgr, plot_idx)
			return

func _interact_with_plot(farm_mgr: Node, plot_idx: int) -> void:
	var action = ""
	var extra = ""
	match PlayerData.current_tool:
		PlayerData.Tool.AXE:
			action = "clear"
		PlayerData.Tool.HOE:
			action = "till"
		PlayerData.Tool.WATERING_CAN:
			action = "water"
		PlayerData.Tool.SEEDS:
			action = "plant"
			extra = PlayerData.selected_seed_id
			if extra == "":
				print("No seed selected!")
				return
		PlayerData.Tool.HANDS:
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

func _open_crafting_ui() -> void:
	var ui = get_node_or_null("/root/Main/GameWorld/UI/CraftingUI")
	if ui:
		ui.visible = !ui.visible
		if ui.visible and ui.has_method("refresh"):
			ui.refresh()
