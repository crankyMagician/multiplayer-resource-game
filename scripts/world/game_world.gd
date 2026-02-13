extends Node3D

const PLAYER_SCENE = preload("res://scenes/player/player.tscn")
const FARM_MANAGER_PATH: NodePath = "Zones/FarmZone/FarmManager"

@onready var players_node: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $Players/MultiplayerSpawner

# UI scenes (loaded at runtime for the local player)
var hud_scene = preload("res://scenes/ui/hud.tscn")
var battle_ui_scene = preload("res://scenes/ui/battle_ui.tscn")
var crafting_ui_scene = preload("res://scenes/ui/crafting_ui.tscn")
var inventory_ui_scene = preload("res://scenes/ui/inventory_ui.tscn")
var party_ui_scene = preload("res://scenes/ui/party_ui.tscn")

func _ready() -> void:
	# Initialize DataRegistry
	DataRegistry.ensure_loaded()

	# Setup UI for the local player (clients only)
	if not multiplayer.is_server() or not (DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server")):
		_setup_ui()

	if not multiplayer.is_server():
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
	var world_data = SaveManager.load_world()
	if world_data.is_empty():
		print("[GameWorld] No saved world state, starting fresh")
		return
	print("[GameWorld] Loading saved world state...")
	# Load season data
	var season_mgr = $SeasonManager
	if season_mgr and world_data.has("season"):
		season_mgr.load_save_data({
			"current_season": world_data.get("season", 0),
			"season_timer": world_data.get("season_timer", 0.0),
			"day_count": world_data.get("day_count", 1)
		})
	# Load farm plot data
	var farm_mgr = get_node_or_null(FARM_MANAGER_PATH)
	if farm_mgr and world_data.has("farm_plots"):
		farm_mgr.load_save_data(world_data.get("farm_plots", []))

func get_save_data() -> Dictionary:
	var data = {}
	var season_mgr = $SeasonManager
	if season_mgr:
		var sd = season_mgr.get_save_data()
		data["season"] = sd.get("current_season", 0)
		data["season_timer"] = sd.get("season_timer", 0.0)
		data["day_count"] = sd.get("day_count", 1)
	var farm_mgr = get_node_or_null(FARM_MANAGER_PATH)
	if farm_mgr:
		data["farm_plots"] = farm_mgr.get_save_data()
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
	var ui_node = Node.new()
	ui_node.name = "UI"
	add_child(ui_node)

	var hud = hud_scene.instantiate()
	ui_node.add_child(hud)

	var battle_ui = battle_ui_scene.instantiate()
	ui_node.add_child(battle_ui)
	battle_ui.setup($BattleManager)

	var crafting_ui = crafting_ui_scene.instantiate()
	ui_node.add_child(crafting_ui)
	crafting_ui.setup($CraftingSystem)

	var inventory_ui = inventory_ui_scene.instantiate()
	ui_node.add_child(inventory_ui)

	var party_ui = party_ui_scene.instantiate()
	ui_node.add_child(party_ui)

func _on_player_connected(peer_id: int, _info: Dictionary) -> void:
	_spawn_player(peer_id)
	# Sync world state to late joiner (deferred so player node exists)
	_sync_world_to_client.call_deferred(peer_id)

func _on_player_disconnected(peer_id: int) -> void:
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
			player.position = Vector3(pos_data.get("x", 0.0), pos_data.get("y", 1.0), pos_data.get("z", 3.0))
		else:
			player.position = Vector3(randf_range(-2, 2), 1, randf_range(2, 4))
	else:
		player.position = Vector3(randf_range(-2, 2), 1, randf_range(2, 4))
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

func _sync_world_to_client(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	# Sync season
	var season_mgr = $SeasonManager
	if season_mgr:
		season_mgr._broadcast_season.rpc_id(peer_id, season_mgr.current_season, season_mgr.day_count)
	# Sync farm plots
	var farm_mgr = get_node_or_null(FARM_MANAGER_PATH)
	if farm_mgr:
		for plot in farm_mgr.plots:
			plot._sync_state.rpc_id(peer_id, plot.plot_state, plot.planted_seed_id, plot.growth_progress, plot.water_level, plot.owner_peer_id)
