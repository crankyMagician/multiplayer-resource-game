extends Node3D

## Server-authoritative harvestable world object (tree, rock, bush).
## Players press E with the correct tool equipped to damage it.
## When health reaches 0, it drops items and enters a respawn timer.

@export var harvestable_type: String = "tree" # tree, rock, bush
@export var required_tool: String = "axe" # tool_type needed, "" = hands
@export var max_health: int = 3
@export var respawn_time: float = 120.0
@export var drops: Array = [] # [{item_id, min, max, weight}]

var current_health: int = 3
var is_harvested: bool = false
var _respawn_timer: float = 0.0

var _mesh: MeshInstance3D = null
var _canopy: MeshInstance3D = null
var _interaction_area: Area3D = null

func _ready() -> void:
	add_to_group("harvestable_object")
	current_health = max_health
	_build_visuals()

func _build_visuals() -> void:
	match harvestable_type:
		"tree":
			_build_tree()
		"rock":
			_build_rock()
		"bush":
			_build_bush()
	# Interaction area
	_interaction_area = Area3D.new()
	_interaction_area.name = "InteractionArea"
	var col = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 2.0
	col.shape = shape
	_interaction_area.add_child(col)
	_interaction_area.collision_layer = 0
	_interaction_area.collision_mask = 2
	add_child(_interaction_area)

func _build_tree() -> void:
	var trunk_mat = StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.4, 0.25, 0.12)
	_mesh = MeshInstance3D.new()
	var trunk = CylinderMesh.new()
	trunk.top_radius = 0.2
	trunk.bottom_radius = 0.3
	trunk.height = 3.0
	_mesh.mesh = trunk
	_mesh.set_surface_override_material(0, trunk_mat)
	_mesh.position.y = 1.5
	add_child(_mesh)

	var canopy_mat = StandardMaterial3D.new()
	canopy_mat.albedo_color = Color(0.12, 0.5, 0.12)
	_canopy = MeshInstance3D.new()
	var canopy = SphereMesh.new()
	canopy.radius = 1.5
	canopy.height = 2.5
	_canopy.mesh = canopy
	_canopy.set_surface_override_material(0, canopy_mat)
	_canopy.position.y = 3.8
	add_child(_canopy)

func _build_rock() -> void:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.48, 0.42)
	_mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(1.2, 0.9, 1.0)
	_mesh.mesh = box
	_mesh.set_surface_override_material(0, mat)
	_mesh.position.y = 0.45
	add_child(_mesh)

func _build_bush() -> void:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.55, 0.15)
	_mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.7
	sphere.height = 1.0
	_mesh.mesh = sphere
	_mesh.set_surface_override_material(0, mat)
	_mesh.position.y = 0.5
	add_child(_mesh)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not is_harvested:
		return
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_respawn()

func _respawn() -> void:
	is_harvested = false
	current_health = max_health
	_respawn_timer = 0.0
	_sync_state.rpc(current_health, false)

@rpc("any_peer", "reliable")
func request_harvest() -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if is_harvested:
		return
	# Validate proximity
	var player_node = NetworkManager._get_player_node(sender)
	if player_node == null:
		return
	if player_node.global_position.distance_to(global_position) > 4.0:
		return
	# Check busy
	if player_node.get("is_busy"):
		return
	# Validate tool
	if required_tool != "":
		var et = NetworkManager.player_data_store.get(sender, {}).get("equipped_tools", {})
		var has_tool := false
		# Check if the player's current tool slot matches
		# We don't trust client's current_tool_slot; we just check if they own the tool type
		if et.has(required_tool):
			has_tool = true
		if not has_tool:
			return
	# Cooldown check
	var cd_action = "chop" if harvestable_type == "tree" else ("mine" if harvestable_type == "rock" else "chop")
	if not NetworkManager.check_tool_cooldown(sender, cd_action, required_tool):
		return
	# Trigger tool animation on player
	var anim_name: StringName = &"axe" if harvestable_type == "tree" else (&"axe" if harvestable_type == "rock" else &"harvest")
	if player_node.has_method("play_tool_action"):
		player_node.play_tool_action(anim_name)
	# Deal damage
	current_health -= 1
	if current_health <= 0:
		current_health = 0
		is_harvested = true
		_respawn_timer = respawn_time
		_grant_drops(sender)
	_sync_state.rpc(current_health, is_harvested)

func _grant_drops(peer_id: int) -> void:
	# Roll drops first
	var rolled_drops: Dictionary = {}
	for drop in drops:
		var item_id: String = str(drop.get("item_id", ""))
		var min_qty: int = int(drop.get("min", 1))
		var max_qty: int = int(drop.get("max", 1))
		var weight: float = float(drop.get("weight", 1.0))
		if randf() > weight:
			continue
		var qty = randi_range(min_qty, max_qty)
		if qty <= 0:
			continue
		rolled_drops[item_id] = rolled_drops.get(item_id, 0) + qty

	# Check if player is in an excursion — route through shared loot
	var excursion_mgr = get_node_or_null("/root/Main/GameWorld/ExcursionManager")
	if excursion_mgr and excursion_mgr.is_player_in_excursion(peer_id):
		excursion_mgr._on_excursion_harvest(peer_id, rolled_drops, harvestable_type)
		return

	# Standard single-player grant
	for item_id in rolled_drops:
		NetworkManager.server_add_inventory(peer_id, item_id, rolled_drops[item_id])
	# Sync inventory
	if peer_id in NetworkManager.player_data_store:
		NetworkManager._sync_inventory_full.rpc_id(peer_id, NetworkManager.player_data_store[peer_id].get("inventory", {}))
	_notify_harvest_client.rpc_id(peer_id, harvestable_type)

@rpc("authority", "reliable")
func _notify_harvest_client(object_type: String) -> void:
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("show_toast"):
		hud.show_toast("Harvested " + object_type + "!")

@rpc("authority", "call_local", "reliable")
func _sync_state(health: int, harvested: bool) -> void:
	current_health = health
	is_harvested = harvested
	# Hide/show visuals
	if _mesh:
		_mesh.visible = not harvested
	if _canopy:
		_canopy.visible = not harvested

## Sync current state to a specific late-joining peer.
func sync_to_client(peer_id: int) -> void:
	_sync_state.rpc_id(peer_id, current_health, is_harvested)
