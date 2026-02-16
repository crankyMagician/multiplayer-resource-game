extends Area3D

@export var encounter_table_id: String = ""
@export var grass_color: Color = Color(0.2, 0.6, 0.2, 0.7)
@export var zone_label_text: String = "Wild Munchies"

# Step tracking per player (server only)
var player_step_counters: Dictionary = {} # peer_id -> step_count
var step_threshold: int = 10 # physics frames of movement to count as a step
var encounter_chance: float = 0.15 # 15% per step

func _ready() -> void:
	# Detect players on collision layer 2 (players don't use layer 1 to avoid pushing each other)
	collision_mask = 3 # bits 1 + 2
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# Set visual on grass mesh children
	for child in get_children():
		if child is MeshInstance3D:
			var mat = StandardMaterial3D.new()
			mat.albedo_color = grass_color
			mat.emission_enabled = true
			mat.emission = grass_color.lerp(Color.WHITE, 0.25)
			mat.emission_energy_multiplier = 0.6
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			child.material_override = mat
	if DisplayServer.get_name() != "headless":
		_create_zone_marker()

func _create_zone_marker() -> void:
	if get_node_or_null("WildZoneLabel") != null:
		return
	var marker = Label3D.new()
	marker.name = "WildZoneLabel"
	marker.text = zone_label_text
	marker.font_size = 28
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.modulate = grass_color.lerp(Color.WHITE, 0.35)
	marker.position = Vector3(0, 2.4, 0)
	add_child(marker)

func _on_body_entered(body: Node3D) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if not multiplayer.is_server():
		return
	if body is CharacterBody3D and body.name.is_valid_int():
		var peer_id = body.name.to_int()
		print("[TallGrass] body_entered: peer ", peer_id, " in zone '", zone_label_text, "'")
		player_step_counters[peer_id] = 0
		_show_grass_indicator.rpc_id(peer_id, true)

func _on_body_exited(body: Node3D) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if not multiplayer.is_server():
		return
	if body is CharacterBody3D and body.name.is_valid_int():
		var peer_id = body.name.to_int()
		player_step_counters.erase(peer_id)
		_show_grass_indicator.rpc_id(peer_id, false)

func _physics_process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if not multiplayer.is_server():
		return
	var players_node = get_node_or_null("/root/Main/GameWorld/Players")
	if not players_node:
		return
	var battle_mgr = get_node_or_null("/root/Main/GameWorld/BattleManager")
	for peer_id in player_step_counters.keys():
		# Skip step counting if player is already in a battle
		if battle_mgr and peer_id in battle_mgr.player_battle_map:
			continue
		var player = players_node.get_node_or_null(str(peer_id))
		if player and player is CharacterBody3D:
			if player.get("is_busy"):
				continue
			if player.velocity.length() > 0.5:
				player_step_counters[peer_id] += 1
				if player_step_counters[peer_id] >= step_threshold:
					player_step_counters[peer_id] = 0
					if randf() < encounter_chance:
						_trigger_encounter(peer_id)

func _trigger_encounter(peer_id: int) -> void:
	# Defensive busy guard
	var players_node = get_node_or_null("/root/Main/GameWorld/Players")
	if players_node:
		var player = players_node.get_node_or_null(str(peer_id))
		if player and player.get("is_busy"):
			return
	player_step_counters.erase(peer_id)
	var encounter_mgr = get_node_or_null("/root/Main/GameWorld/EncounterManager")
	if encounter_mgr:
		encounter_mgr.start_encounter(peer_id, encounter_table_id)

@rpc("authority", "reliable")
func _show_grass_indicator(visible_state: bool) -> void:
	# Client-side: show/hide grass overlay indicator
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("show_grass_indicator"):
		hud.show_grass_indicator(visible_state)
