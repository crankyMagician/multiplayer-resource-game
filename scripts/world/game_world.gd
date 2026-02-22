extends Node3D

const PLAYER_SCENE = preload("res://scenes/player/player.tscn")
const FARM_MANAGER_PATH: NodePath = "Zones/FarmZone/FarmManager"

# Current layout version — increment whenever terrain changes significantly
const LAYOUT_VERSION: int = 2  # v1 = original flat, v2 = terrain massing

@onready var players_node: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $Players/MultiplayerSpawner

# UI scenes (loaded at runtime for the local player)
var hud_scene = preload("res://scenes/ui/hud.tscn")
var battle_ui_scene = preload("res://scenes/battle/battle_arena_ui.tscn")
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
var bank_ui_scene = preload("res://scenes/ui/bank_ui.tscn")

func _ready() -> void:
	# Initialize DataRegistry
	DataRegistry.ensure_loaded()
	_apply_world_label_theme()

	# District visuals are now in Districts/ sub-scenes (no procedural generation)
	_spawn_calendar_board()
	_spawn_bank_npc()
	_generate_harvestables()
	_generate_dig_spots()
	_spawn_excursion_entrance()
	_spawn_fishing_spots()

	# Spawn FishingManager on ALL peers (needed for RPC routing; non-server is inert)
	var fishing_mgr_script = load("res://scripts/world/fishing_manager.gd")
	var fishing_mgr = Node.new()
	fishing_mgr.name = "FishingManager"
	fishing_mgr.set_script(fishing_mgr_script)
	add_child(fishing_mgr)

	if not multiplayer.is_server():
		_setup_ui()
		_ensure_fallback_camera()
		return

	# Connect bank interest to day_changed
	var season_mgr = $SeasonManager
	if season_mgr and season_mgr.has_signal("day_changed"):
		season_mgr.day_changed.connect(NetworkManager._on_day_changed_bank_interest)

	# Server: load world state from save
	_load_world_state.call_deferred()

	# Spawn existing players
	for peer_id in NetworkManager.players:
		if peer_id != 1: # Don't spawn server "player"
			_spawn_player(peer_id)
	# Listen for new connections / disconnections
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)

func _apply_world_label_theme() -> void:
	var label_roles := {
		"Zones/RestaurantZone/CraftingTable/StationLabel": "station",
		"Zones/RestaurantZone/Pantry/StationLabel": "station",
		"Zones/RestaurantZone/Workbench/StationLabel": "station",
		"Zones/WildZone/Cauldron/StationLabel": "station",
		"Zones/RestaurantRow/SignLabel": "landmark",
		"Zones/RestaurantRow/SubSign": "station",
	}
	for label_path in label_roles:
		var label_node := get_node_or_null(label_path)
		if label_node and label_node is Label3D:
			UITheme.style_label3d(label_node, "", label_roles[label_path])

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

	var bank_ui = bank_ui_scene.instantiate()
	ui_node.add_child(bank_ui)

	var fishing_ui_script = load("res://scripts/ui/fishing_ui.gd")
	var fishing_ui = CanvasLayer.new()
	fishing_ui.name = "FishingUI"
	fishing_ui.set_script(fishing_ui_script)
	ui_node.add_child(fishing_ui)

	# Dev debug overlay (editor-only, self-destructs in exports)
	if OS.has_feature("editor"):
		var ddo_script = load("res://scripts/ui/dev_debug_overlay.gd")
		var ddo = CanvasLayer.new()
		ddo.name = "DevDebugOverlay"
		ddo.set_script(ddo_script)
		ui_node.add_child(ddo)

	# Start overworld music + ambience (client only)
	AudioManager.play_music("overworld")
	AudioManager.play_ambience(0, "overworld")

func open_character_creator(_first_time: bool = false) -> void:
	var creator = get_node_or_null("UI/CharacterCreatorUI")
	if not creator:
		var creator_script = load("res://scripts/ui/character_creator_ui.gd")
		creator = CanvasLayer.new()
		creator.name = "CharacterCreatorUI"
		creator.set_script(creator_script)
		$UI.add_child(creator)
		creator.appearance_confirmed.connect(_on_appearance_confirmed)
	creator.open(PlayerData.appearance.duplicate(), false)

func _on_appearance_confirmed(appearance: Dictionary) -> void:
	NetworkManager.request_update_appearance.rpc_id(1, appearance)
	PlayerData.appearance = appearance
	var local_id := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else -1
	var player_node = players_node.get_node_or_null(str(local_id))
	if player_node and player_node.has_method("update_appearance"):
		player_node.update_appearance(appearance)


func _spawn_calendar_board() -> void:
	var board_script = load("res://scripts/world/calendar_board.gd")
	var board = Area3D.new()
	board.set_script(board_script)
	board.name = "CalendarBoard"
	board.position = Vector3(3, 1, 10)  # Town Square, near Town Hall
	add_child(board)

func _spawn_bank_npc() -> void:
	var bank_script = load("res://scripts/world/bank_npc.gd")
	var bank = Area3D.new()
	bank.set_script(bank_script)
	bank.name = "BankNPC"
	bank.position = Vector3(10, 1, 8)  # Town Square, near General Store
	add_child(bank)

const EXCURSION_PORTALS: Array = [
	{"zone_type": "default", "position": Vector3(-5, 0, -15), "label": "The Wilds", "color": Color(0.6, 0.2, 0.8)},
	{"zone_type": "coastal_wreckage", "position": Vector3(-22, 0, -8), "label": "Coastal Wreckage", "color": Color(0.2, 0.6, 0.8)},
	{"zone_type": "fungal_hollow", "position": Vector3(5, 0, -45), "label": "Fungal Hollow", "color": Color(0.4, 0.2, 0.6)},
	{"zone_type": "volcanic_crest", "position": Vector3(30, 0, -8), "label": "Volcanic Crest", "color": Color(0.9, 0.3, 0.1)},
	{"zone_type": "frozen_pantry", "position": Vector3(10, 0, 25), "label": "Frozen Pantry", "color": Color(0.5, 0.8, 0.95)},
]

func _spawn_excursion_entrance() -> void:
	for portal_data in EXCURSION_PORTALS:
		_spawn_single_portal(portal_data)

func _spawn_single_portal(portal_data: Dictionary) -> void:
	var zone_type: String = portal_data["zone_type"]
	var portal_color: Color = portal_data["color"]

	var entrance = Node3D.new()
	entrance.name = "ExcursionEntrance_" + zone_type
	entrance.position = portal_data["position"]
	entrance.add_to_group("excursion_portal")
	entrance.set_meta("zone_type", zone_type)
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
	UITheme.style_label3d(sign_label, portal_data["label"], "station")
	sign_label.font_size = 36
	sign_label.position = Vector3(0, 3.5, 0)
	entrance.add_child(sign_label)

	# Glowing portal visual — color matches zone theme
	var portal_mesh = MeshInstance3D.new()
	var torus = CylinderMesh.new()
	torus.top_radius = 2.0
	torus.bottom_radius = 2.0
	torus.height = 0.3
	portal_mesh.mesh = torus
	var portal_mat = StandardMaterial3D.new()
	portal_mat.albedo_color = Color(portal_color.r, portal_color.g, portal_color.b, 0.5)
	portal_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	portal_mat.emission_enabled = true
	portal_mat.emission = portal_color
	portal_mat.emission_energy_multiplier = 2.0
	portal_mesh.set_surface_override_material(0, portal_mat)
	portal_mesh.position = Vector3(0, 0.2, 0)
	entrance.add_child(portal_mesh)

	# Magic pulse VFX on portal (client-side only)
	if not multiplayer.is_server():
		var vfx_path := "res://assets/vfx/magic_areas/assets/BinbunVFX/magic_areas/effects/pulse_area/pulse_area_vfx_01.tscn"
		if ResourceLoader.exists(vfx_path):
			var vfx_scene = load(vfx_path) as PackedScene
			if vfx_scene:
				var vfx_inst = vfx_scene.instantiate() as Node3D
				vfx_inst.position = Vector3(0, 0.5, 0)
				vfx_inst.scale = Vector3(1.5, 1.5, 1.5)
				entrance.add_child(vfx_inst)

	# Server-side interaction Area3D
	if multiplayer.is_server():
		var area = Area3D.new()
		area.name = "PortalArea"
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

		entrance.add_child(area)

	# Hint label for clients
	var hint = Label3D.new()
	UITheme.style_label3d(hint, "Press E to Enter", "interaction_hint")
	hint.position = Vector3(0, 2.5, 0)
	entrance.add_child(hint)


func _on_player_connected(peer_id: int, _info: Dictionary) -> void:
	_spawn_player(peer_id)
	# Register with restaurant manager (spawns overworld door, tracks location)
	var rest_mgr = get_node_or_null("RestaurantManager")
	if rest_mgr:
		rest_mgr.handle_player_connected(peer_id)
	# Sync world state to late joiner (deferred so player node exists)
	_sync_world_to_client.call_deferred(peer_id)

func _on_player_disconnected(peer_id: int) -> void:
	# Clean up fishing state
	var fishing_mgr = get_node_or_null("FishingManager")
	if fishing_mgr:
		fishing_mgr.handle_disconnect(peer_id)
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
	# Use saved position if layout version matches, otherwise reset to spawn
	if peer_id in NetworkManager.player_data_store:
		var pdata = NetworkManager.player_data_store[peer_id]
		var pos_data = pdata.get("position", {})
		var saved_version: int = int(pdata.get("layout_version", 0))
		if saved_version >= LAYOUT_VERSION and not pos_data.is_empty():
			var saved_pos = Vector3(pos_data.get("x", 0.0), pos_data.get("y", 1.0), pos_data.get("z", 3.0))
			player.position = saved_pos
		else:
			if not pos_data.is_empty():
				print("[GameWorld] Layout v", saved_version, " < v", LAYOUT_VERSION, " — resetting player ", peer_id, " to spawn")
			player.position = _get_spread_spawn_position()
			pdata["layout_version"] = LAYOUT_VERSION
	else:
		player.position = _get_spread_spawn_position()
	# Set visual properties from server data (BEFORE add_child for StateSync spawn-only replication)
	if peer_id in NetworkManager.player_data_store:
		var pdata = NetworkManager.player_data_store[peer_id]
		var cd = pdata.get("player_color", {})
		if cd is Dictionary and not cd.is_empty():
			player.player_color = Color(cd.get("r", 0.2), cd.get("g", 0.5), cd.get("b", 0.9))
		player.player_name_display = str(pdata.get("player_name", "Player"))
		player.appearance_data = pdata.get("appearance", {})
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

func _get_spread_spawn_position() -> Vector3:
	# Spread new players in a circle using golden angle to avoid overlap/stacking
	var idx = players_node.get_child_count() # 0-based count of existing children
	var angle = idx * 2.399 # golden angle in radians
	var radius = 2.0
	return Vector3(cos(angle) * radius, 1.0, sin(angle) * radius + 6.0)  # Town Square center

func _sync_world_to_client(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	# Sync season/calendar/weather
	var season_mgr = $SeasonManager
	if season_mgr:
		season_mgr._broadcast_time.rpc_id(peer_id, season_mgr.current_year, season_mgr.current_month, season_mgr.day_in_month, season_mgr.total_day_count, season_mgr.current_weather, season_mgr.day_timer)
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
			{"item_id": "chili_powder", "min": 1, "max": 1, "weight": 0.1},
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
		{"pos": Vector3(-14, 0, -13), "id": "herb_1", "loot": [{"item_id": "broth", "weight": 0.6, "min": 1, "max": 1}, {"item_id": "herb_basil", "weight": 0.4, "min": 1, "max": 2}]},
		{"pos": Vector3(-10, 0, -17), "id": "herb_2", "loot": [{"item_id": "broth", "weight": 0.5, "min": 1, "max": 1}, {"item_id": "herb_basil", "weight": 0.5, "min": 1, "max": 2}]},
		# Flame Kitchen (2)
		{"pos": Vector3(14, 0, -13), "id": "flame_1", "loot": [{"item_id": "chili_powder", "weight": 0.5, "min": 1, "max": 1}, {"item_id": "chili_pepper", "weight": 0.5, "min": 1, "max": 2}]},
		{"pos": Vector3(10, 0, -17), "id": "flame_2", "loot": [{"item_id": "chili_powder", "weight": 0.6, "min": 1, "max": 1}, {"item_id": "chili_pepper", "weight": 0.4, "min": 1, "max": 1}]},
		# Frost Pantry (2)
		{"pos": Vector3(-20, 0, -33), "id": "frost_1", "loot": [{"item_id": "mint", "weight": 0.6, "min": 1, "max": 2}]},
		{"pos": Vector3(-16, 0, -37), "id": "frost_2", "loot": [{"item_id": "mint", "weight": 0.5, "min": 1, "max": 1}]},
		# Harvest Field (2)
		{"pos": Vector3(20, 0, -33), "id": "harvest_1", "loot": [{"item_id": "wheat", "weight": 0.6, "min": 1, "max": 2}, {"item_id": "flour", "weight": 0.3, "min": 1, "max": 1}]},
		{"pos": Vector3(16, 0, -37), "id": "harvest_2", "loot": [{"item_id": "wheat", "weight": 0.5, "min": 1, "max": 2}, {"item_id": "flour", "weight": 0.4, "min": 1, "max": 1}]},
		# Sour Springs (1)
		{"pos": Vector3(20, 0, -46), "id": "sour_1", "loot": [{"item_id": "mushroom", "weight": 0.5, "min": 1, "max": 2}]},
		# Fusion Kitchen (1)
		{"pos": Vector3(-20, 0, -46), "id": "fusion_1", "loot": [{"item_id": "sugar", "weight": 0.4, "min": 1, "max": 1}, {"item_id": "soy_sauce", "weight": 0.3, "min": 1, "max": 1}]},
	]

	for spot in spots:
		var ds = Area3D.new()
		ds.set_script(dig_spot_script)
		ds.name = "DigSpot_" + str(spot["id"])
		ds.position = spot["pos"]
		ds.spot_id = str(spot["id"])
		ds.loot_table = spot["loot"]
		digs_node.add_child(ds)

# === Fishing Spots ===

func _spawn_fishing_spots() -> void:
	var fishing_node = Node3D.new()
	fishing_node.name = "FishingSpots"
	add_child(fishing_node)

	var spots = [
		{"pos": Vector3(-14, 0, -8), "table_id": "pond", "label": "Cove Pond"},
		{"pos": Vector3(-12, 0, -10), "table_id": "river", "label": "Wharf Pier"},
		{"pos": Vector3(-22, 0, 0), "table_id": "ocean", "label": "Open Ocean"},
	]

	var water_mat = StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.2, 0.4, 0.7, 0.5)
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	for spot in spots:
		var spot_node = Node3D.new()
		spot_node.name = "FishingSpot_" + spot["table_id"]
		spot_node.position = spot["pos"]
		spot_node.add_to_group("fishing_spot")
		spot_node.set_meta("fishing_table_id", spot["table_id"])
		fishing_node.add_child(spot_node)

		# Water visual (flat disc)
		var water = MeshInstance3D.new()
		var disc = CylinderMesh.new()
		disc.top_radius = 3.0
		disc.bottom_radius = 3.0
		disc.height = 0.1
		water.mesh = disc
		water.set_surface_override_material(0, water_mat)
		water.position = Vector3(0, 0.05, 0)
		spot_node.add_child(water)

		# Label
		var label = Label3D.new()
		UITheme.style_label3d(label, spot["label"] + " - Fishing Spot", "station")
		label.font_size = 28
		label.position = Vector3(0, 2.5, 0)
		spot_node.add_child(label)

		# Hint
		var hint = Label3D.new()
		UITheme.style_label3d(hint, "Equip Rod + Press E", "interaction_hint")
		hint.position = Vector3(0, 2.0, 0)
		spot_node.add_child(hint)

