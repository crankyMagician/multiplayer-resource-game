extends Area3D

@export var trainer_id: String = ""
@export var is_gatekeeper: bool = false

var mesh_instance: MeshInstance3D = null
var label_3d: Label3D = null
var gate_mesh: MeshInstance3D = null
var gate_label: Label3D = null
var nearby_peers: Dictionary = {} # peer_id -> true

func _ready() -> void:
	add_to_group("trainer_npc")
	# Detect players on collision layer 2
	collision_mask = 3 # bits 1 + 2
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_create_visual()

func _create_visual() -> void:
	DataRegistry.ensure_loaded()
	var trainer = DataRegistry.get_trainer(trainer_id)
	var display_name = trainer.display_name if trainer else trainer_id

	# Collision shape
	var col = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 4.0 if is_gatekeeper else 3.0
	col.shape = shape
	add_child(col)

	# NPC mesh
	mesh_instance = MeshInstance3D.new()
	var capsule = CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.5
	mesh_instance.mesh = capsule
	var mat = StandardMaterial3D.new()
	if trainer:
		match trainer.ai_difficulty:
			"easy":
				mat.albedo_color = Color(0.3, 0.7, 0.3) # Green
			"medium":
				mat.albedo_color = Color(0.7, 0.7, 0.2) # Yellow
			"hard":
				mat.albedo_color = Color(0.8, 0.2, 0.2) # Red
			_:
				mat.albedo_color = Color(0.5, 0.5, 0.5)
	mesh_instance.set_surface_override_material(0, mat)
	mesh_instance.position.y = 0.75
	add_child(mesh_instance)

	# Label
	label_3d = Label3D.new()
	label_3d.text = display_name
	label_3d.font_size = 24
	label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label_3d.position.y = 2.0
	add_child(label_3d)

	# Gatekeeper gate mesh
	if is_gatekeeper:
		_create_gate()

func _create_gate() -> void:
	gate_mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(8, 2.5, 0.5)
	gate_mesh.mesh = box
	var gate_mat = StandardMaterial3D.new()
	gate_mat.albedo_color = Color(0.7, 0.2, 0.15, 0.85)
	gate_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gate_mesh.set_surface_override_material(0, gate_mat)
	gate_mesh.position = Vector3(0, 1.25, -2.5)
	add_child(gate_mesh)

	gate_label = Label3D.new()
	gate_label.text = "Defeat %s to Pass!" % (DataRegistry.get_trainer(trainer_id).display_name if DataRegistry.get_trainer(trainer_id) else trainer_id)
	gate_label.font_size = 28
	gate_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	gate_label.modulate = Color(1.0, 0.3, 0.3)
	gate_label.position = Vector3(0, 3.2, -2.5)
	add_child(gate_label)

func _on_body_entered(body: Node3D) -> void:
	if not multiplayer.is_server():
		return
	if not body is CharacterBody3D:
		return
	var peer_id = body.name.to_int()
	if peer_id <= 0:
		return

	nearby_peers[peer_id] = true

	# Check if already in battle
	var battle_mgr = get_node_or_null("/root/Main/GameWorld/BattleManager")
	if battle_mgr and peer_id in battle_mgr.player_battle_map:
		return

	if is_gatekeeper:
		_handle_gatekeeper_enter(peer_id, body)
	else:
		_handle_optional_enter(peer_id)

func _on_body_exited(body: Node3D) -> void:
	if not multiplayer.is_server():
		return
	if body is CharacterBody3D:
		var peer_id = body.name.to_int()
		nearby_peers.erase(peer_id)
		_hide_trainer_prompt.rpc_id(peer_id)

func _handle_optional_enter(peer_id: int) -> void:
	DataRegistry.ensure_loaded()
	var trainer = DataRegistry.get_trainer(trainer_id)
	var display_name = trainer.display_name if trainer else trainer_id
	_show_trainer_prompt.rpc_id(peer_id, display_name)

func _handle_gatekeeper_enter(peer_id: int, body: CharacterBody3D) -> void:
	# Check if already defeated
	if _has_defeated(peer_id):
		return # Gate is open for this player

	DataRegistry.ensure_loaded()
	var trainer = DataRegistry.get_trainer(trainer_id)
	var display_name = trainer.display_name if trainer else trainer_id
	var dialogue = trainer.dialogue_before if trainer else "You shall not pass!"

	# Push player back and show challenge
	var push_dir = (body.global_position - global_position).normalized()
	push_dir.y = 0
	body.velocity = push_dir * 5.0

	_show_gatekeeper_challenge.rpc_id(peer_id, trainer_id, display_name, dialogue)

func _has_defeated(peer_id: int) -> bool:
	if peer_id in NetworkManager.player_data_store:
		var pdata = NetworkManager.player_data_store[peer_id]
		var defeated = pdata.get("defeated_trainers", {})
		return trainer_id in defeated
	return false

# Called from player_interaction.gd E-key or from gatekeeper accept
@rpc("any_peer", "reliable")
func request_challenge() -> void:
	if not multiplayer.is_server():
		return
	var peer_id = multiplayer.get_remote_sender_id()
	# Validate proximity
	if peer_id not in nearby_peers:
		return
	# Check not in battle
	var battle_mgr = get_node_or_null("/root/Main/GameWorld/BattleManager")
	if battle_mgr == null:
		return
	if peer_id in battle_mgr.player_battle_map:
		return
	var encounter_mgr = get_node_or_null("/root/Main/GameWorld/EncounterManager")
	if encounter_mgr and encounter_mgr.is_in_encounter(peer_id):
		return
	# Check rematch cooldown (for optional trainers)
	if not is_gatekeeper:
		DataRegistry.ensure_loaded()
		var trainer = DataRegistry.get_trainer(trainer_id)
		if trainer and peer_id in NetworkManager.player_data_store:
			var pdata = NetworkManager.player_data_store[peer_id]
			var defeated = pdata.get("defeated_trainers", {})
			if trainer_id in defeated:
				var last_time = int(defeated[trainer_id])
				var now = int(Time.get_unix_time_from_system())
				if now - last_time < trainer.rematch_cooldown_sec:
					return
	battle_mgr.server_start_trainer_battle(peer_id, trainer_id)

# Server notifies client that gate is now open
func update_gate_for_peer(peer_id: int) -> void:
	if is_gatekeeper and _has_defeated(peer_id):
		_notify_gate_opened.rpc_id(peer_id, trainer_id)

# === Client RPCs ===

@rpc("authority", "reliable")
func _show_trainer_prompt(trainer_name: String) -> void:
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("show_trainer_prompt"):
		hud.show_trainer_prompt(trainer_name)

@rpc("authority", "reliable")
func _hide_trainer_prompt() -> void:
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("hide_trainer_prompt"):
		hud.hide_trainer_prompt()

@rpc("authority", "reliable")
func _show_gatekeeper_challenge(_trainer_id: String, trainer_name: String, dialogue: String) -> void:
	var ui = get_node_or_null("/root/Main/GameWorld/UI/TrainerDialogueUI")
	if ui and ui.has_method("show_challenge"):
		ui.show_challenge(trainer_name, dialogue, _trainer_id)

@rpc("authority", "reliable")
func _notify_gate_opened(_trainer_id: String) -> void:
	# Find the gatekeeper trainer NPC node and hide its gate visuals
	for npc in get_tree().get_nodes_in_group("trainer_npc"):
		if npc.trainer_id == _trainer_id and npc.is_gatekeeper:
			if npc.gate_mesh:
				npc.gate_mesh.visible = false
			if npc.gate_label:
				npc.gate_label.visible = false
