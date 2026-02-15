extends Node3D

var plots: Array[Node] = []
var is_raining: bool = false

const FARM_PLOT_SCENE = preload("res://scenes/world/farm_plot.tscn")
@export var grid_size: int = 6
const PLOT_SPACING = 2.0

func _ready() -> void:
	add_to_group("farm_manager")
	# Generate farm plot grid
	_generate_plots()
	# Collect all farm plots
	for child in get_children():
		if child.has_method("try_clear"):
			plots.append(child)

func _generate_plots() -> void:
	var offset = -(grid_size - 1) * PLOT_SPACING / 2.0
	for row in range(grid_size):
		for col in range(grid_size):
			var plot = FARM_PLOT_SCENE.instantiate()
			plot.name = "Plot_%d_%d" % [row, col]
			plot.position = Vector3(
				offset + col * PLOT_SPACING,
				0,
				offset + row * PLOT_SPACING
			)
			add_child(plot)

func rain_water_all() -> void:
	# Called by SeasonManager when daily weather is rainy/stormy
	is_raining = true
	_broadcast_rain.rpc(true)
	for plot in plots:
		if plot.has_method("rain_water"):
			plot.rain_water()
	print("[FarmManager] Rain watered all plots")

@rpc("authority", "call_local", "reliable")
func _broadcast_rain(raining: bool) -> void:
	is_raining = raining

@rpc("any_peer", "reliable")
func request_farm_action(plot_index: int, action: String, extra: String) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if plot_index < 0 or plot_index >= plots.size():
		return
	var plot = plots[plot_index]
	var success = false
	var result = {}
	match action:
		"clear":
			var was_wild = (plot.plot_state == plot.PlotState.WILD)
			success = plot.try_clear(sender)
			if success and was_wild:
				var item_mgr = get_node_or_null("/root/Main/GameWorld/WorldItemManager")
				if item_mgr:
					var drop_pos = plot.global_position + Vector3(randf_range(-0.5, 0.5), 0.5, randf_range(-0.5, 0.5))
					var drops = ["mushroom", "herb_basil", "grain_core"]
					item_mgr.spawn_world_item(drops[randi() % drops.size()], 1, drop_pos, 120.0, "farm")
		"till":
			success = plot.try_till(sender)
		"plant":
			if extra != "":
				if NetworkManager.server_remove_inventory(sender, extra, 1):
					success = plots[plot_index].try_plant(sender, extra)
					if success:
						_sync_inventory_remove.rpc_id(sender, extra, 1)
					else:
						NetworkManager.server_add_inventory(sender, extra, 1)
		"water":
			if NetworkManager.server_use_watering_can(sender):
				success = plot.try_water(sender)
				var remaining = int(NetworkManager.player_data_store[sender].get("watering_can_current", 0))
				_sync_watering_can.rpc_id(sender, remaining)
			else:
				_farm_action_result.rpc_id(sender, plot_index, action, false)
				return
		"harvest":
			result = plot.try_harvest(sender)
			if result.size() > 0:
				success = true
				_grant_harvest.rpc_id(sender, result)
				# Server-side inventory tracking
				for item_id in result:
					NetworkManager.server_add_inventory(sender, item_id, result[item_id])
	_farm_action_result.rpc_id(sender, plot_index, action, success)

@rpc("authority", "reliable")
func _farm_action_result(_plot_index: int, _action: String, _success: bool) -> void:
	# Client receives result - could show feedback
	pass

@rpc("authority", "reliable")
func _sync_watering_can(amount: int) -> void:
	PlayerData.watering_can_current = amount

@rpc("authority", "reliable")
func _grant_harvest(items: Dictionary) -> void:
	for item_id in items:
		PlayerData.add_to_inventory(item_id, items[item_id])

@rpc("authority", "reliable")
func _sync_inventory_remove(item_id: String, _amount: int) -> void:
	PlayerData.remove_from_inventory(item_id, _amount)

@rpc("any_peer", "reliable")
func _request_refill() -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	NetworkManager.server_refill_watering_can(sender)
	var amount = int(NetworkManager.player_data_store[sender].get("watering_can_current", 10))
	_receive_refill.rpc_id(sender, amount)

@rpc("authority", "reliable")
func _receive_refill(amount: int) -> void:
	PlayerData.watering_can_current = amount
	print("Watering can refilled!")

func get_save_data() -> Array:
	var data = []
	for plot in plots:
		data.append(plot.get_save_data())
	return data

func load_save_data(data: Array) -> void:
	for i in range(min(data.size(), plots.size())):
		plots[i].load_save_data(data[i])

func get_nearest_plot(world_pos: Vector3, max_distance: float = 3.0) -> int:
	var closest_dist = max_distance
	var closest_idx = -1
	for i in range(plots.size()):
		var dist = plots[i].global_position.distance_to(world_pos)
		if dist < closest_dist:
			closest_dist = dist
			closest_idx = i
	return closest_idx
