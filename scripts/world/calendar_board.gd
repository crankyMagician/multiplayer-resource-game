extends Area3D

var nearby_peers: Dictionary = {}

func _ready() -> void:
	add_to_group("calendar_board")
	collision_layer = 0
	collision_mask = 3 # bits 1+2 to detect players

	# Collision shape (always created at runtime)
	var shape = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 3.0
	shape.shape = sphere
	add_child(shape)

	# Visuals are pre-placed in game_world.tscn as child MeshInstance3D/Label3D nodes.
	# Only create them if missing (e.g. spawned dynamically).
	if not get_node_or_null("BoardMesh"):
		var board_mesh = MeshInstance3D.new()
		board_mesh.name = "BoardMesh"
		var box = BoxMesh.new()
		box.size = Vector3(1.2, 1.8, 0.15)
		board_mesh.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.3, 0.15)
		board_mesh.set_surface_override_material(0, mat)
		board_mesh.position = Vector3(0, 1.2, 0)
		add_child(board_mesh)

		var post_mesh = MeshInstance3D.new()
		post_mesh.name = "PostMesh"
		var cyl = CylinderMesh.new()
		cyl.top_radius = 0.08
		cyl.bottom_radius = 0.1
		cyl.height = 2.0
		post_mesh.mesh = cyl
		var post_mat = StandardMaterial3D.new()
		post_mat.albedo_color = Color(0.35, 0.2, 0.1)
		post_mesh.set_surface_override_material(0, post_mat)
		post_mesh.position = Vector3(0, 1.0, 0)
		add_child(post_mesh)

		var label = Label3D.new()
		label.name = "BoardLabel"
		UITheme.style_label3d(label, "Town Calendar", "station")
		label.font_size = 32
		label.position = Vector3(0, 2.5, 0)
		add_child(label)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if not body is CharacterBody3D:
		return
	var peer_id = body.name.to_int()
	if peer_id <= 0:
		return
	nearby_peers[peer_id] = true
	if multiplayer.is_server():
		if body.get("is_busy"):
			return
		_show_prompt.rpc_id(peer_id)

func _on_body_exited(body: Node3D) -> void:
	if not body is CharacterBody3D:
		return
	var peer_id = body.name.to_int()
	if peer_id <= 0:
		return
	nearby_peers.erase(peer_id)
	if multiplayer.is_server():
		_hide_prompt.rpc_id(peer_id)

@rpc("authority", "reliable")
func _show_prompt() -> void:
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("show_interaction_prompt"):
		hud.show_interaction_prompt("Press E to view Calendar")

@rpc("authority", "reliable")
func _hide_prompt() -> void:
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("hide_trainer_prompt"):
		hud.hide_trainer_prompt()

@rpc("any_peer", "reliable")
func request_open_calendar() -> void:
	if not multiplayer.is_server():
		return
	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id not in nearby_peers:
		return
	# Check busy / battle state
	if peer_id in NetworkManager.player_data_store:
		var player_node = get_node_or_null("/root/Main/GameWorld/Players/" + str(peer_id))
		if player_node and player_node.is_busy:
			return
	var battle_mgr = get_node_or_null("/root/Main/GameWorld/BattleManager")
	if battle_mgr and peer_id in battle_mgr.player_battle_map:
		return
	var season_mgr = get_node_or_null("/root/Main/GameWorld/SeasonManager")
	var month: int = season_mgr.current_month if season_mgr else 3
	var day: int = season_mgr.day_in_month if season_mgr else 1
	var year: int = season_mgr.current_year if season_mgr else 1
	_open_calendar_client.rpc_id(peer_id, month, day, year)

@rpc("authority", "reliable")
func _open_calendar_client(month: int, day: int, year: int) -> void:
	var calendar_ui = get_node_or_null("/root/Main/GameWorld/UI/CalendarUI")
	if calendar_ui and calendar_ui.has_method("open_calendar"):
		calendar_ui.open_calendar(month, day, year)
