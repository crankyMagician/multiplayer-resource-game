extends Node3D

const PLAYER_SCENE = preload("res://scenes/player/player.tscn")
const FARM_MANAGER_PATH: NodePath = "Zones/FarmZone/FarmManager"

@onready var players_node: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $Players/MultiplayerSpawner

# UI scenes (loaded at runtime for the local player)
var hud_scene = preload("res://scenes/ui/hud.tscn")
var battle_ui_scene = preload("res://scenes/ui/battle_ui.tscn")
var crafting_ui_scene = preload("res://scenes/ui/crafting_ui.tscn")
var pause_menu_scene = preload("res://scenes/ui/pause_menu.tscn")
var storage_ui_scene = preload("res://scenes/ui/storage_ui.tscn")
var shop_ui_scene = preload("res://scenes/ui/shop_ui.tscn")
var trade_ui_scene = preload("res://scenes/ui/trade_ui.tscn")
var dialogue_ui_scene = preload("res://scenes/ui/dialogue_ui.tscn")
var calendar_ui_scene = preload("res://scenes/ui/calendar_ui.tscn")
var compass_ui_scene = preload("res://scenes/ui/compass_ui.tscn")
var creature_destination_ui_scene = preload("res://scenes/ui/creature_destination_ui.tscn")
var hotbar_ui_scene = preload("res://scenes/ui/hotbar_ui.tscn")
var excursion_hud_scene = preload("res://scenes/ui/excursion_hud.tscn")

func _ready() -> void:
	# Initialize DataRegistry
	DataRegistry.ensure_loaded()

	# Generate world decorations (paths, signposts, trees, zone overlays) on all peers
	_generate_paths()
	_generate_signposts()
	_generate_trees()
	_generate_zone_overlays()
	_spawn_calendar_board()
	_generate_harvestables()
	_generate_dig_spots()
	_spawn_excursion_entrance()

	if not multiplayer.is_server():
		_setup_ui()
		_ensure_fallback_camera()
		return

	# Server: load world state from save
	_load_world_state.call_deferred()

	# Spawn existing players
	for peer_id in NetworkManager.players:
		if peer_id != 1: # Don't spawn server "player"
			_spawn_player(peer_id)
	# Listen for new connections / disconnections
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)

func has_spawn_path_ready() -> bool:
	return (
		players_node != null
		and spawner != null
		and is_instance_valid(players_node)
		and is_instance_valid(spawner)
	)

func _load_world_state() -> void:
	# Async load: signal-based for API mode, immediate for file fallback
	SaveManager.world_loaded.connect(_on_world_loaded, CONNECT_ONE_SHOT)
	SaveManager.load_world_async()

func _on_world_loaded(world_data: Dictionary) -> void:
	if world_data.is_empty():
		print("[GameWorld] No saved world state, starting fresh")
		return
	print("[GameWorld] Loading saved world state...")
	# Load season/calendar data
	var season_mgr = $SeasonManager
	if season_mgr:
		var season_data: Dictionary = {
			"current_year": world_data.get("current_year", 1),
			"day_timer": world_data.get("day_timer", 0.0),
			"total_day_count": world_data.get("total_day_count", 1),
			"current_weather": world_data.get("current_weather", 0),
			# Backward compat keys (used if current_month is missing)
			"season_timer": world_data.get("season_timer", 0.0),
			"day_count": world_data.get("day_count", 1),
			"current_season": world_data.get("season", 0),
			"day_in_season": world_data.get("day_in_season", 1),
		}
		# Pass new-format keys if present
		if world_data.has("current_month"):
			season_data["current_month"] = world_data.get("current_month", 3)
			season_data["day_in_month"] = world_data.get("day_in_month", 1)
		season_mgr.load_save_data(season_data)
	# Load farm plot data
	var farm_mgr = get_node_or_null(FARM_MANAGER_PATH)
	if farm_mgr and world_data.has("farm_plots"):
		farm_mgr.load_save_data(world_data.get("farm_plots", []))
	# Load recipe pickup claimed data
	var pickup_data = world_data.get("recipe_pickups", {})
	for pickup in get_tree().get_nodes_in_group("recipe_pickup"):
		if pickup.has_method("load_claimed_data") and pickup.pickup_id in pickup_data:
			pickup.load_claimed_data(pickup_data[pickup.pickup_id])
	# Load world items
	var item_mgr = get_node_or_null("WorldItemManager")
	if item_mgr and world_data.has("world_items"):
		item_mgr.load_save_data(world_data.get("world_items", []))
	# Load restaurant manager data
	var rest_mgr = get_node_or_null("RestaurantManager")
	if rest_mgr and world_data.has("restaurant_manager"):
		rest_mgr.load_save_data(world_data.get("restaurant_manager", {}))

func get_save_data() -> Dictionary:
	var data = {}
	var season_mgr = $SeasonManager
	if season_mgr:
		var sd = season_mgr.get_save_data()
		data["current_month"] = sd.get("current_month", 3)
		data["day_in_month"] = sd.get("day_in_month", 1)
		data["current_year"] = sd.get("current_year", 1)
		data["day_timer"] = sd.get("day_timer", 0.0)
		data["total_day_count"] = sd.get("total_day_count", 1)
		data["current_weather"] = sd.get("current_weather", 0)
		# Backward compat keys
		data["season"] = sd.get("current_season", 0)
		data["season_timer"] = sd.get("season_timer", 0.0)
		data["day_count"] = sd.get("day_count", 1)
		data["day_in_season"] = sd.get("day_in_season", 1)
	var farm_mgr = get_node_or_null(FARM_MANAGER_PATH)
	if farm_mgr:
		data["farm_plots"] = farm_mgr.get_save_data()
	# Save recipe pickup claimed data
	var pickup_data = {}
	for pickup in get_tree().get_nodes_in_group("recipe_pickup"):
		if pickup.has_method("get_claimed_data") and pickup.pickup_id != "":
			pickup_data[pickup.pickup_id] = pickup.get_claimed_data()
	if not pickup_data.is_empty():
		data["recipe_pickups"] = pickup_data
	# Save world items
	var item_mgr = get_node_or_null("WorldItemManager")
	if item_mgr:
		data["world_items"] = item_mgr.get_save_data()
	# Save restaurant manager data (index allocations)
	var rest_mgr = get_node_or_null("RestaurantManager")
	if rest_mgr:
		rest_mgr.update_all_restaurant_save_data()
		data["restaurant_manager"] = rest_mgr.get_save_data()
	return data

func _ensure_fallback_camera() -> void:
	if get_node_or_null("FallbackCameraRig"):
		return
	var rig: Node3D = Node3D.new()
	rig.name = "FallbackCameraRig"
	rig.position = Vector3(0, 14, 18)
	rig.rotation = Vector3(deg_to_rad(-30), 0, 0)
	add_child(rig)

	var cam: Camera3D = Camera3D.new()
	cam.name = "FallbackCamera"
	cam.current = true
	cam.fov = 70.0
	rig.add_child(cam)

func _setup_ui() -> void:
	# Use the existing UI node from game_world.tscn (contains PvPChallengeUI, TrainerDialogueUI)
	# Creating a new "UI" node would cause Godot to rename it (e.g. @Node@38),
	# breaking all path-based lookups like /root/Main/GameWorld/UI/BattleUI
	var ui_node = $UI

	var hud = hud_scene.instantiate()
	ui_node.add_child(hud)

	var battle_ui = battle_ui_scene.instantiate()
	ui_node.add_child(battle_ui)
	battle_ui.setup($BattleManager)

	var crafting_ui = crafting_ui_scene.instantiate()
	ui_node.add_child(crafting_ui)
	crafting_ui.setup($CraftingSystem)

	var pause_menu = pause_menu_scene.instantiate()
	ui_node.add_child(pause_menu)

	var storage_ui = storage_ui_scene.instantiate()
	ui_node.add_child(storage_ui)

	var shop_ui = shop_ui_scene.instantiate()
	ui_node.add_child(shop_ui)

	var trade_ui = trade_ui_scene.instantiate()
	ui_node.add_child(trade_ui)

	var dialogue_ui = dialogue_ui_scene.instantiate()
	ui_node.add_child(dialogue_ui)

	var calendar_ui = calendar_ui_scene.instantiate()
	ui_node.add_child(calendar_ui)

	var compass_ui = compass_ui_scene.instantiate()
	ui_node.add_child(compass_ui)

	var creature_destination_ui = creature_destination_ui_scene.instantiate()
	ui_node.add_child(creature_destination_ui)

	var hotbar_ui = hotbar_ui_scene.instantiate()
	ui_node.add_child(hotbar_ui)

	var excursion_hud = excursion_hud_scene.instantiate()
	ui_node.add_child(excursion_hud)

func _spawn_calendar_board() -> void:
	var board_script = load("res://scripts/world/calendar_board.gd")
	var board = Area3D.new()
	board.set_script(board_script)
	board.name = "CalendarBoard"
	board.position = Vector3(5, 0, 5)
	add_child(board)

func _spawn_excursion_entrance() -> void:
	var entrance = Node3D.new()
	entrance.name = "ExcursionEntrance"
	entrance.position = Vector3(-15, 0, 0)
	entrance.add_to_group("excursion_portal")
	add_child(entrance)

	# Signpost
	var post_mat = StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.4, 0.25, 0.1)
	var post = MeshInstance3D.new()
	var post_mesh = BoxMesh.new()
	post_mesh.size = Vector3(0.2, 3.0, 0.2)
	post.mesh = post_mesh
	post.set_surface_override_material(0, post_mat)
	post.position = Vector3(0, 1.5, 0)
	entrance.add_child(post)

	var sign_label = Label3D.new()
	sign_label.text = "Excursion Portal"
	sign_label.font_size = 36
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign_label.modulate = Color(1.0, 0.85, 0.4)
	sign_label.outline_size = 8
	sign_label.position = Vector3(0, 3.5, 0)
	entrance.add_child(sign_label)

	# Glowing portal visual
	var portal_mesh = MeshInstance3D.new()
	var torus = CylinderMesh.new()
	torus.top_radius = 2.0
	torus.bottom_radius = 2.0
	torus.height = 0.3
	portal_mesh.mesh = torus
	var portal_mat = StandardMaterial3D.new()
	portal_mat.albedo_color = Color(0.4, 0.3, 0.8, 0.5)
	portal_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	portal_mat.emission_enabled = true
	portal_mat.emission = Color(0.5, 0.3, 0.9)
	portal_mat.emission_energy_multiplier = 2.0
	portal_mesh.set_surface_override_material(0, portal_mat)
	portal_mesh.position = Vector3(0, 0.2, 0)
	entrance.add_child(portal_mesh)

	# Server-side interaction Area3D
	if multiplayer.is_server():
		var area = Area3D.new()
		area.name = "ExcursionPortalArea"
		area.position = Vector3(0, 0, 0)
		area.collision_layer = 0
		area.collision_mask = 3

		var shape = CylinderShape3D.new()
		shape.radius = 3.0
		shape.height = 4.0
		var coll = CollisionShape3D.new()
		coll.shape = shape
		coll.position = Vector3(0, 2, 0)
		area.add_child(coll)

		area.body_entered.connect(_on_excursion_portal_entered)
		entrance.add_child(area)

	# Hint label for clients
	var hint = Label3D.new()
	hint.text = "Party Required"
	hint.font_size = 24
	hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hint.modulate = Color(0.8, 0.8, 0.8, 0.7)
	hint.outline_size = 4
	hint.position = Vector3(0, 2.5, 0)
	entrance.add_child(hint)


var _excursion_portal_cooldown: Dictionary = {} # peer_id -> timestamp

func _on_excursion_portal_entered(body: Node3D) -> void:
	if not multiplayer.is_server():
		return
	if not body is CharacterBody3D:
		return
	var peer_id = body.name.to_int()
	if peer_id <= 0:
		return

	# Cooldown to prevent spam
	var now = Time.get_ticks_msec()
	if peer_id in _excursion_portal_cooldown and now - _excursion_portal_cooldown[peer_id] < 5000:
		return
	_excursion_portal_cooldown[peer_id] = now

	# Check if player is party leader
	var friend_mgr = get_node_or_null("FriendManager")
	var excursion_mgr = get_node_or_null("ExcursionManager")
	if friend_mgr == null or excursion_mgr == null:
		return

	var player_id = NetworkManager.get_player_id_for_peer(peer_id)
	if player_id == "":
		return

	if player_id not in friend_mgr.player_party_map:
		# Not in a party — show message
		excursion_mgr._excursion_action_result.rpc_id(peer_id, "enter", false, "You need a party to enter an excursion. Form a party first!")
		return

	var party_id = friend_mgr.player_party_map[player_id]
	var party = friend_mgr.parties.get(party_id, {})
	if party.is_empty():
		return

	if str(party["leader_id"]) != player_id:
		# Not the leader
		excursion_mgr._excursion_action_result.rpc_id(peer_id, "enter", false, "Waiting for party leader to start the excursion.")
		return

	# Party leader — auto-trigger entry (server already knows sender from body)
	# We simulate the RPC by calling the server's internal entry logic directly
	# since this runs on the server already
	excursion_mgr._create_excursion_from_portal(peer_id)


# === WORLD DECORATION GENERATION ===

func _generate_paths() -> void:
	var paths_node = Node3D.new()
	paths_node.name = "Paths"
	add_child(paths_node)

	var path_mat = StandardMaterial3D.new()
	path_mat.albedo_color = Color(0.55, 0.45, 0.3)

	# Path segments: {pos, size} — each is a BoxMesh strip
	var segments = [
		# Spawn hub to restaurant row (south)
		{"pos": Vector3(0, 0.03, 7.5), "size": Vector3(3.5, 0.05, 9)},
		# Spawn hub to starter fork (north)
		{"pos": Vector3(0, 0.03, -2), "size": Vector3(3.5, 0.05, 10)},
		# Spawn hub to farm zone (east)
		{"pos": Vector3(12.5, 0.03, 3), "size": Vector3(25, 0.05, 3.5)},
		# Starter fork to Herb Garden (west branch)
		{"pos": Vector3(-6, 0.03, -12), "size": Vector3(12, 0.05, 3.5)},
		# Starter fork to Flame Kitchen (east branch)
		{"pos": Vector3(6, 0.03, -12), "size": Vector3(12, 0.05, 3.5)},
		# Main path: starter fork to Chef Umami gate
		{"pos": Vector3(0, 0.03, -14), "size": Vector3(3.5, 0.05, 14)},
		# Past Chef Umami to junction
		{"pos": Vector3(0, 0.03, -25), "size": Vector3(3.5, 0.05, 10)},
		# Junction to Frost Pantry (west)
		{"pos": Vector3(-9, 0.03, -32), "size": Vector3(18, 0.05, 3.5)},
		# Junction to Harvest Field (east)
		{"pos": Vector3(9, 0.03, -32), "size": Vector3(18, 0.05, 3.5)},
		# Main path: junction to Head Chef Roux gate
		{"pos": Vector3(0, 0.03, -35), "size": Vector3(3.5, 0.05, 10)},
		# Past Head Chef Roux to deep zone
		{"pos": Vector3(0, 0.03, -47), "size": Vector3(3.5, 0.05, 14)},
		# Deep zone to Fusion Kitchen (west)
		{"pos": Vector3(-9, 0.03, -48), "size": Vector3(18, 0.05, 3.5)},
		# Deep zone to Sour Springs (east)
		{"pos": Vector3(9, 0.03, -48), "size": Vector3(18, 0.05, 3.5)},
		# Deep path to Cauldron
		{"pos": Vector3(0, 0.03, -52), "size": Vector3(3.5, 0.05, 6)},
		# Side path to Pastry Dulce (-18, -28)
		{"pos": Vector3(-18, 0.03, -31), "size": Vector3(3.5, 0.05, 6)},
		# Side path to Brinemaster Vlad (18, -28)
		{"pos": Vector3(18, 0.03, -31), "size": Vector3(3.5, 0.05, 6)},
		# Side path to Grand Chef Michelin (-25, -55)
		{"pos": Vector3(-12, 0.03, -55), "size": Vector3(26, 0.05, 3.5)},
	]

	for seg in segments:
		var mesh_inst = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = seg.size
		mesh_inst.mesh = box
		mesh_inst.set_surface_override_material(0, path_mat)
		mesh_inst.position = seg.pos
		paths_node.add_child(mesh_inst)

func _generate_signposts() -> void:
	var signs_node = Node3D.new()
	signs_node.name = "Signposts"
	add_child(signs_node)

	var post_mat = StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.4, 0.25, 0.1)

	var signposts = [
		{"pos": Vector3(3, 0, 3), "text": "N: Wild Zones\nE: Farm\nS: Restaurants"},
		{"pos": Vector3(0, 0, -8), "text": "W: Herb Garden\nE: Flame Kitchen\nN: Deeper Wilds"},
		{"pos": Vector3(0, 0, -25), "text": "W: Frost Pantry\nE: Harvest Field\nN: Danger Ahead!"},
		{"pos": Vector3(0, 0, -42), "text": "N: Cauldron\nW: Fusion Kitchen\nE: Sour Springs"},
		{"pos": Vector3(18, 0, 0), "text": "E: Community Farm"},
		{"pos": Vector3(0, 0, 10), "text": "S: Restaurant Row"},
	]

	for sp in signposts:
		# Post
		var post = MeshInstance3D.new()
		var post_mesh = BoxMesh.new()
		post_mesh.size = Vector3(0.2, 2.0, 0.2)
		post.mesh = post_mesh
		post.set_surface_override_material(0, post_mat)
		post.position = Vector3(sp.pos.x, 1.0, sp.pos.z)
		signs_node.add_child(post)

		# Sign text
		var label = Label3D.new()
		label.text = sp.text
		label.font_size = 36
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(0.95, 0.85, 0.6)
		label.outline_size = 8
		label.position = Vector3(sp.pos.x, 2.3, sp.pos.z)
		signs_node.add_child(label)

	# Floating direction markers toward Restaurant Row
	var marker_positions = [Vector3(0, 1.5, 6), Vector3(0, 1.5, 9)]
	for mpos in marker_positions:
		var marker = Label3D.new()
		marker.text = "v Restaurant Row v"
		marker.font_size = 24
		marker.outline_size = 6
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.modulate = Color(1.0, 0.9, 0.4)
		marker.position = mpos
		signs_node.add_child(marker)

func _generate_trees() -> void:
	var trees_node = Node3D.new()
	trees_node.name = "Trees"
	add_child(trees_node)

	var trunk_mat = StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.35, 0.2, 0.1)
	var canopy_mat = StandardMaterial3D.new()
	canopy_mat.albedo_color = Color(0.15, 0.45, 0.15)

	var tree_positions = [
		# Along spawn-to-wild path edges
		Vector3(-3, 0, -5), Vector3(3, 0, -5),
		Vector3(-3, 0, -10), Vector3(3, 0, -10),
		# Near starter fork
		Vector3(-5, 0, -8), Vector3(5, 0, -8),
		# Along mid zone path
		Vector3(-3, 0, -22), Vector3(3, 0, -22),
		Vector3(-3, 0, -28), Vector3(3, 0, -28),
		# Along deep path
		Vector3(-3, 0, -45), Vector3(3, 0, -45),
		# Near farm entrance
		Vector3(15, 0, -2), Vector3(15, 0, 5),
		# Near restaurant row
		Vector3(-4, 0, 10), Vector3(4, 0, 10),
		# Decorative clusters near zones
		Vector3(-18, 0, -42), Vector3(-22, 0, -40),
		Vector3(22, 0, -40), Vector3(18, 0, -42),
	]

	for pos in tree_positions:
		# Trunk
		var trunk = MeshInstance3D.new()
		var trunk_mesh = CylinderMesh.new()
		trunk_mesh.top_radius = 0.15
		trunk_mesh.bottom_radius = 0.2
		trunk_mesh.height = 2.5
		trunk.mesh = trunk_mesh
		trunk.set_surface_override_material(0, trunk_mat)
		trunk.position = Vector3(pos.x, 1.25, pos.z)
		trees_node.add_child(trunk)

		# Canopy
		var canopy = MeshInstance3D.new()
		var canopy_mesh = SphereMesh.new()
		canopy_mesh.radius = 1.2
		canopy_mesh.height = 2.0
		canopy.mesh = canopy_mesh
		canopy.set_surface_override_material(0, canopy_mat)
		canopy.position = Vector3(pos.x, 3.0, pos.z)
		trees_node.add_child(canopy)

func _generate_zone_overlays() -> void:
	var overlays_node = Node3D.new()
	overlays_node.name = "ZoneOverlays"
	add_child(overlays_node)

	var zones = [
		{"pos": Vector3(-12, 0.02, -15), "color": Color(0.2, 0.5, 0.2, 0.3), "label": "Herb Garden"},
		{"pos": Vector3(12, 0.02, -15), "color": Color(0.5, 0.25, 0.15, 0.3), "label": "Flame Kitchen"},
		{"pos": Vector3(-18, 0.02, -35), "color": Color(0.25, 0.35, 0.6, 0.3), "label": "Frost Pantry"},
		{"pos": Vector3(18, 0.02, -35), "color": Color(0.5, 0.45, 0.15, 0.3), "label": "Harvest Field"},
		{"pos": Vector3(18, 0.02, -48), "color": Color(0.6, 0.7, 0.15, 0.3), "label": "Sour Springs"},
		{"pos": Vector3(-18, 0.02, -48), "color": Color(0.5, 0.25, 0.5, 0.3), "label": "Fusion Kitchen"},
	]

	for z in zones:
		# Ground overlay
		var overlay = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(14, 0.02, 14)
		overlay.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = z.color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		overlay.set_surface_override_material(0, mat)
		overlay.position = z.pos
		overlays_node.add_child(overlay)

		# Zone label (floating above)
		var label = Label3D.new()
		label.text = z.label
		label.font_size = 36
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(1, 1, 1, 0.9)
		label.outline_size = 6
		label.position = Vector3(z.pos.x, 3.5, z.pos.z)
		overlays_node.add_child(label)

	# Add some rocks/boulders at zone borders for visual separation
	var rock_mat = StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.5, 0.48, 0.45)
	var rock_positions = [
		Vector3(-5, 0.4, -18), Vector3(5, 0.3, -18),
		Vector3(-8, 0.35, -30), Vector3(8, 0.35, -30),
		Vector3(-8, 0.4, -44), Vector3(8, 0.4, -44),
		Vector3(-10, 0.3, -20), Vector3(10, 0.3, -20),
	]
	for rpos in rock_positions:
		var rock = MeshInstance3D.new()
		var rbox = BoxMesh.new()
		var rsize = randf_range(0.6, 1.2)
		rbox.size = Vector3(rsize, rsize * 0.6, rsize * 0.8)
		rock.mesh = rbox
		rock.set_surface_override_material(0, rock_mat)
		rock.position = rpos
		overlays_node.add_child(rock)

func _on_player_connected(peer_id: int, _info: Dictionary) -> void:
	_spawn_player(peer_id)
	# Register with restaurant manager (spawns overworld door, tracks location)
	var rest_mgr = get_node_or_null("RestaurantManager")
	if rest_mgr:
		rest_mgr.handle_player_connected(peer_id)
	# Sync world state to late joiner (deferred so player node exists)
	_sync_world_to_client.call_deferred(peer_id)

func _on_player_disconnected(peer_id: int) -> void:
	# Clean up excursion state (restore overworld position before despawn)
	var excursion_mgr = get_node_or_null("ExcursionManager")
	if excursion_mgr:
		excursion_mgr.handle_disconnect(peer_id)
	# Clean up restaurant state (save data, remove door, eject from restaurant)
	var rest_mgr = get_node_or_null("RestaurantManager")
	if rest_mgr:
		rest_mgr.handle_player_disconnect(peer_id)
	# Clean up battle/encounter state for this peer
	var battle_mgr = get_node_or_null("BattleManager")
	if battle_mgr:
		battle_mgr.handle_player_disconnect(peer_id)
	var encounter_mgr = get_node_or_null("EncounterManager")
	if encounter_mgr:
		encounter_mgr.end_encounter(peer_id)
	_despawn_player(peer_id)

func _spawn_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var player = PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	# Use saved position if available
	if peer_id in NetworkManager.player_data_store:
		var pos_data = NetworkManager.player_data_store[peer_id].get("position", {})
		if not pos_data.is_empty():
			var saved_pos = Vector3(pos_data.get("x", 0.0), pos_data.get("y", 1.0), pos_data.get("z", 3.0))
			# Migration: reset players at old layout positions to spawn
			if _is_old_layout_position(saved_pos):
				print("[GameWorld] Migrating player ", peer_id, " from old position ", saved_pos, " to spawn")
				player.position = _get_spread_spawn_position()
			else:
				player.position = saved_pos
		else:
			player.position = _get_spread_spawn_position()
	else:
		player.position = _get_spread_spawn_position()
	# Set visual properties from server data
	if peer_id in NetworkManager.player_data_store:
		var pdata = NetworkManager.player_data_store[peer_id]
		var cd = pdata.get("player_color", {})
		if cd is Dictionary and not cd.is_empty():
			player.player_color = Color(cd.get("r", 0.2), cd.get("g", 0.5), cd.get("b", 0.9))
		player.player_name_display = str(pdata.get("player_name", "Player"))
	# Keep exact numeric node names (peer_id) so authority/camera logic works on clients.
	players_node.add_child(player)
	print("Spawned player: ", peer_id)

func _despawn_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var player_node = players_node.get_node_or_null(str(peer_id))
	if player_node:
		player_node.queue_free()
		print("Despawned player: ", peer_id)

func _is_old_layout_position(pos: Vector3) -> bool:
	# Old layout had WildZone at (-20,0,0) with zones at offsets like (-28,-12), (-36,16), etc.
	# New layout has everything along Z axis (north-south). Old positions had x < -15.
	# Also old farm was at (20,0,0), new is (25,0,0).
	# Old restaurant row was at (0,0,-15), now at (0,0,12).
	# Check if position is in old wild zone area (x < -15)
	if pos.x < -15.0:
		return true
	# Check if near old farm position (20,0,0) but not new (25,0,0)
	if abs(pos.x - 20.0) < 3.0 and abs(pos.z) < 10.0:
		return true
	return false

func _get_spread_spawn_position() -> Vector3:
	# Spread new players in a circle using golden angle to avoid overlap/stacking
	var idx = players_node.get_child_count() # 0-based count of existing children
	var angle = idx * 2.399 # golden angle in radians
	var radius = 2.0
	return Vector3(cos(angle) * radius, 1.0, sin(angle) * radius + 3.0)

func _sync_world_to_client(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	# Sync season/calendar/weather
	var season_mgr = $SeasonManager
	if season_mgr:
		season_mgr._broadcast_time.rpc_id(peer_id, season_mgr.current_year, season_mgr.current_month, season_mgr.day_in_month, season_mgr.total_day_count, season_mgr.current_weather)
	# Sync farm plots
	var farm_mgr = get_node_or_null(FARM_MANAGER_PATH)
	if farm_mgr:
		for plot in farm_mgr.plots:
			plot._sync_state.rpc_id(peer_id, plot.plot_state, plot.planted_seed_id, plot.growth_progress, plot.water_level, plot.owner_peer_id)
	# Sync world items
	var item_mgr = get_node_or_null("WorldItemManager")
	if item_mgr:
		item_mgr.sync_all_to_client(peer_id)
	# Sync restaurant doors to late joiner
	var rest_mgr = get_node_or_null("RestaurantManager")
	if rest_mgr:
		rest_mgr.sync_doors_to_client(peer_id)
	# Sync gatekeeper states (open gates for defeated trainers)
	for npc in get_tree().get_nodes_in_group("trainer_npc"):
		if npc.is_gatekeeper:
			npc.update_gate_for_peer(peer_id)
	# Sync harvestable objects
	for h in get_tree().get_nodes_in_group("harvestable_object"):
		if h.has_method("sync_to_client"):
			h.sync_to_client(peer_id)
	# Sync dig spots
	for ds in get_tree().get_nodes_in_group("dig_spot"):
		if ds.has_method("sync_to_client"):
			ds.sync_to_client(peer_id)

# === World Harvestable Objects ===

var harvestable_scene = preload("res://scenes/world/harvestable_object.tscn")

func _generate_harvestables() -> void:
	var harvestables_node = Node3D.new()
	harvestables_node.name = "Harvestables"
	add_child(harvestables_node)

	# Trees: axe, 3 hits, 120s respawn
	var tree_positions = [
		Vector3(-8, 0, -12), Vector3(8, 0, -12),
		Vector3(-14, 0, -32), Vector3(14, 0, -32),
		Vector3(-14, 0, -45), Vector3(14, 0, -45),
	]
	for pos in tree_positions:
		var h = harvestable_scene.instantiate()
		h.harvestable_type = "tree"
		h.required_tool = "axe"
		h.max_health = 3
		h.respawn_time = 120.0
		h.drops = [
			{"item_id": "wood", "min": 1, "max": 3, "weight": 1.0},
			{"item_id": "herb_basil", "min": 1, "max": 1, "weight": 0.2},
		]
		h.position = pos
		h.name = "Tree_%d_%d" % [int(pos.x), int(pos.z)]
		harvestables_node.add_child(h)

	# Rocks: axe, 4 hits, 150s respawn
	var rock_positions = [
		Vector3(-16, 0, -18), Vector3(16, 0, -18),
		Vector3(-12, 0, -50), Vector3(12, 0, -50),
	]
	for pos in rock_positions:
		var h = harvestable_scene.instantiate()
		h.harvestable_type = "rock"
		h.required_tool = "axe"
		h.max_health = 4
		h.respawn_time = 150.0
		h.drops = [
			{"item_id": "stone", "min": 1, "max": 2, "weight": 1.0},
			{"item_id": "spicy_essence", "min": 1, "max": 1, "weight": 0.1},
		]
		h.position = pos
		h.name = "Rock_%d_%d" % [int(pos.x), int(pos.z)]
		harvestables_node.add_child(h)

	# Bushes: no tool (hands), 1 hit, 90s respawn
	var bush_positions = [
		Vector3(-10, 0, -14), Vector3(10, 0, -14),
		Vector3(-16, 0, -38), Vector3(16, 0, -38),
	]
	for pos in bush_positions:
		var h = harvestable_scene.instantiate()
		h.harvestable_type = "bush"
		h.required_tool = ""
		h.max_health = 1
		h.respawn_time = 90.0
		h.drops = [
			{"item_id": "berry", "min": 1, "max": 2, "weight": 1.0},
		]
		h.position = pos
		h.name = "Bush_%d_%d" % [int(pos.x), int(pos.z)]
		harvestables_node.add_child(h)

# === Dig Spots ===

func _generate_dig_spots() -> void:
	var digs_node = Node3D.new()
	digs_node.name = "DigSpots"
	add_child(digs_node)

	var dig_spot_script = load("res://scripts/world/dig_spot.gd")
	var spots = [
		# Herb Garden (2)
		{"pos": Vector3(-14, 0, -13), "id": "herb_1", "loot": [{"item_id": "herbal_dew", "weight": 0.6, "min": 1, "max": 1}, {"item_id": "herb_basil", "weight": 0.4, "min": 1, "max": 2}]},
		{"pos": Vector3(-10, 0, -17), "id": "herb_2", "loot": [{"item_id": "herbal_dew", "weight": 0.5, "min": 1, "max": 1}, {"item_id": "herb_basil", "weight": 0.5, "min": 1, "max": 2}]},
		# Flame Kitchen (2)
		{"pos": Vector3(14, 0, -13), "id": "flame_1", "loot": [{"item_id": "spicy_essence", "weight": 0.5, "min": 1, "max": 1}, {"item_id": "chili_pepper", "weight": 0.5, "min": 1, "max": 2}]},
		{"pos": Vector3(10, 0, -17), "id": "flame_2", "loot": [{"item_id": "spicy_essence", "weight": 0.6, "min": 1, "max": 1}, {"item_id": "chili_pepper", "weight": 0.4, "min": 1, "max": 1}]},
		# Frost Pantry (2)
		{"pos": Vector3(-20, 0, -33), "id": "frost_1", "loot": [{"item_id": "mint", "weight": 0.6, "min": 1, "max": 2}]},
		{"pos": Vector3(-16, 0, -37), "id": "frost_2", "loot": [{"item_id": "mint", "weight": 0.5, "min": 1, "max": 1}]},
		# Harvest Field (2)
		{"pos": Vector3(20, 0, -33), "id": "harvest_1", "loot": [{"item_id": "wheat", "weight": 0.6, "min": 1, "max": 2}, {"item_id": "grain_core", "weight": 0.3, "min": 1, "max": 1}]},
		{"pos": Vector3(16, 0, -37), "id": "harvest_2", "loot": [{"item_id": "wheat", "weight": 0.5, "min": 1, "max": 2}, {"item_id": "grain_core", "weight": 0.4, "min": 1, "max": 1}]},
		# Sour Springs (1)
		{"pos": Vector3(20, 0, -46), "id": "sour_1", "loot": [{"item_id": "mushroom", "weight": 0.5, "min": 1, "max": 2}]},
		# Fusion Kitchen (1)
		{"pos": Vector3(-20, 0, -46), "id": "fusion_1", "loot": [{"item_id": "sweet_crystal", "weight": 0.4, "min": 1, "max": 1}, {"item_id": "umami_extract", "weight": 0.3, "min": 1, "max": 1}]},
	]

	for spot in spots:
		var ds = Area3D.new()
		ds.set_script(dig_spot_script)
		ds.name = "DigSpot_" + str(spot["id"])
		ds.position = spot["pos"]
		ds.spot_id = str(spot["id"])
		ds.loot_table = spot["loot"]
		digs_node.add_child(ds)
