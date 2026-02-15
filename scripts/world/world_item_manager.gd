extends Node

const WORLD_ITEM_SCENE = preload("res://scenes/world/world_item.tscn")

var world_items: Dictionary = {} # uid -> {item_id, amount, position:{x,y,z}, spawn_time, despawn_time, source}
var _next_uid: int = 1
var _items_container: Node3D = null

# Random spawn config
var random_spawn_timer: float = 0.0
var random_spawn_interval: float = 120.0 # seconds between spawn attempts
var max_random_items: int = 10

var random_spawn_points: Array[Vector3] = [
	Vector3(0, 0.5, 5),        # near spawn hub
	Vector3(15, 0.5, 0),       # path to farm
	Vector3(25, 0.5, -3),      # near farm
	Vector3(0, 0.5, -10),      # starter path
	Vector3(-12, 0.5, -15),    # near herb garden
	Vector3(12, 0.5, -15),     # near flame kitchen
	Vector3(-18, 0.5, -35),    # near frost pantry
	Vector3(18, 0.5, -35),     # near harvest field
	Vector3(-18, 0.5, -48),    # near fusion kitchen
	Vector3(18, 0.5, -48),     # near sour springs
]

var random_spawn_table: Array = [
	{"item_id": "mushroom", "weight": 20},
	{"item_id": "herb_basil", "weight": 20},
	{"item_id": "sweet_crystal", "weight": 10},
	{"item_id": "herbal_dew", "weight": 15},
	{"item_id": "grain_core", "weight": 20},
	{"item_id": "sour_essence", "weight": 15},
]

func _ready() -> void:
	_items_container = get_node_or_null("../WorldItems")
	if _items_container == null:
		push_warning("[WorldItemManager] WorldItems container not found")

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	# Check despawn timers
	var now = Time.get_unix_time_from_system()
	var to_remove: Array[int] = []
	for uid in world_items:
		var item_data = world_items[uid]
		if item_data.get("despawn_time", 0.0) > 0.0 and now >= item_data["despawn_time"]:
			to_remove.append(uid)
	for uid in to_remove:
		_remove_world_item(uid)
	# Random spawn timer
	random_spawn_timer += delta
	if random_spawn_timer >= random_spawn_interval:
		random_spawn_timer = 0.0
		_try_random_spawn()

func spawn_world_item(item_id: String, amount: int, pos: Vector3, timeout: float = 300.0, source: String = "world") -> int:
	if not multiplayer.is_server():
		return -1
	var uid = _next_uid
	_next_uid += 1
	var now = Time.get_unix_time_from_system()
	var despawn_time = now + timeout if timeout > 0.0 else 0.0
	world_items[uid] = {
		"item_id": item_id,
		"amount": amount,
		"position": {"x": pos.x, "y": pos.y, "z": pos.z},
		"spawn_time": now,
		"despawn_time": despawn_time,
		"source": source,
	}
	# Create server-side Area3D for pickup detection
	_create_item_node(uid, item_id, amount, pos)
	# Broadcast to all clients
	_spawn_world_item_client.rpc(uid, item_id, amount, pos.x, pos.y, pos.z)
	print("[WorldItemManager] Spawned %s x%d (uid=%d) at %s" % [item_id, amount, uid, str(pos)])
	return uid

func try_pickup(peer_id: int, uid: int) -> void:
	if not multiplayer.is_server():
		return
	if uid not in world_items:
		return
	var item_data = world_items[uid]
	var item_id = item_data["item_id"]
	var amount = item_data["amount"]
	# Grant item to player
	NetworkManager.server_add_inventory(peer_id, item_id, amount)
	NetworkManager._sync_inventory_full.rpc_id(peer_id, NetworkManager.player_data_store[peer_id].get("inventory", {}))
	# Check fragment auto-combine
	if item_id.begins_with("fragment_"):
		NetworkManager._check_fragment_combine(peer_id, item_id)
	# Notify the picker
	_notify_pickup.rpc_id(peer_id, item_id, amount)
	print("[WorldItemManager] Player %d picked up %s x%d (uid=%d)" % [peer_id, item_id, amount, uid])
	# Remove from world
	_remove_world_item(uid)

func _remove_world_item(uid: int) -> void:
	world_items.erase(uid)
	# Remove server node
	if _items_container:
		var node = _items_container.get_node_or_null("WorldItem_" + str(uid))
		if node:
			node.queue_free()
	# Tell all clients to remove
	_despawn_world_item_client.rpc(uid)

func _create_item_node(uid: int, item_id: String, amount: int, pos: Vector3) -> void:
	if _items_container == null:
		return
	var item_node = WORLD_ITEM_SCENE.instantiate()
	item_node.setup(uid, item_id, amount, pos)
	_items_container.add_child(item_node)

func _try_random_spawn() -> void:
	# Count current random items
	var random_count = 0
	for uid in world_items:
		if world_items[uid].get("source", "") == "world":
			random_count += 1
	if random_count >= max_random_items:
		return
	# Pick a random spawn point with jitter
	var point = random_spawn_points[randi() % random_spawn_points.size()]
	var jitter = Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
	var spawn_pos = point + jitter
	# Pick a random item from weighted table
	var total_weight = 0
	for entry in random_spawn_table:
		total_weight += entry["weight"]
	var roll = randi() % total_weight
	var cumulative = 0
	var chosen_id = random_spawn_table[0]["item_id"]
	for entry in random_spawn_table:
		cumulative += entry["weight"]
		if roll < cumulative:
			chosen_id = entry["item_id"]
			break
	spawn_world_item(chosen_id, 1, spawn_pos, 300.0, "world")

# --- Late-joiner sync ---
func sync_all_to_client(peer_id: int) -> void:
	for uid in world_items:
		var d = world_items[uid]
		var pos = d["position"]
		_spawn_world_item_client.rpc_id(peer_id, uid, d["item_id"], d["amount"], pos["x"], pos["y"], pos["z"])

# --- Save/Load ---
func get_save_data() -> Array:
	var data: Array = []
	for uid in world_items:
		var d = world_items[uid].duplicate()
		d["uid"] = uid
		data.append(d)
	return data

func load_save_data(data: Array) -> void:
	var now = Time.get_unix_time_from_system()
	for entry in data:
		var uid: int = entry.get("uid", _next_uid)
		if uid >= _next_uid:
			_next_uid = uid + 1
		var pos_data = entry.get("position", {})
		var pos = Vector3(pos_data.get("x", 0.0), pos_data.get("y", 0.5), pos_data.get("z", 0.0))
		# Recalculate despawn time relative to current time
		var original_spawn = entry.get("spawn_time", now)
		var original_despawn = entry.get("despawn_time", 0.0)
		var despawn_time = 0.0
		if original_despawn > 0.0:
			var remaining = original_despawn - original_spawn
			if remaining <= 0.0:
				continue # already expired
			despawn_time = now + remaining
		world_items[uid] = {
			"item_id": entry.get("item_id", ""),
			"amount": entry.get("amount", 1),
			"position": {"x": pos.x, "y": pos.y, "z": pos.z},
			"spawn_time": now,
			"despawn_time": despawn_time,
			"source": entry.get("source", "world"),
		}
		_create_item_node(uid, entry.get("item_id", ""), entry.get("amount", 1), pos)
	print("[WorldItemManager] Loaded %d world items from save" % world_items.size())

# --- Client RPCs ---
@rpc("authority", "call_local", "reliable")
func _spawn_world_item_client(uid: int, item_id: String, amount: int, x: float, y: float, z: float) -> void:
	if multiplayer.is_server():
		return # Server already has its nodes
	if _items_container == null:
		_items_container = get_node_or_null("../WorldItems")
	if _items_container == null:
		return
	# Guard against duplicates
	if _items_container.get_node_or_null("WorldItem_" + str(uid)):
		return
	var item_node = WORLD_ITEM_SCENE.instantiate()
	item_node.setup(uid, item_id, amount, Vector3(x, y, z))
	_items_container.add_child(item_node)

@rpc("authority", "call_local", "reliable")
func _despawn_world_item_client(uid: int) -> void:
	if multiplayer.is_server():
		return
	if _items_container == null:
		_items_container = get_node_or_null("../WorldItems")
	if _items_container == null:
		return
	var node = _items_container.get_node_or_null("WorldItem_" + str(uid))
	if node:
		node.queue_free()

@rpc("authority", "reliable")
func _notify_pickup(item_id: String, amount: int) -> void:
	# Show pickup notification on client HUD
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("show_pickup_notification"):
		DataRegistry.ensure_loaded()
		var info = DataRegistry.get_item_display_info(item_id)
		var display_name = info.get("display_name", item_id)
		hud.show_pickup_notification(display_name, amount)
