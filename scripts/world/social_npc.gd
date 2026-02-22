extends Area3D

@export var npc_id: String = ""

const UITokens = preload("res://scripts/ui/ui_tokens.gd")

var nearby_peers: Dictionary = {} # peer_id -> true
var quest_indicator: Label3D = null
var _anim_state: Dictionary = {}
var _schedule_throttle: int = 0

func _ready() -> void:
	add_to_group("social_npc")
	collision_mask = 3 # bits 1 + 2
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_create_visual()

func _create_visual() -> void:
	DataRegistry.ensure_loaded()
	var npc_def = DataRegistry.get_npc(npc_id)
	var display_name: String = npc_def.display_name if npc_def else npc_id
	var npc_color: Color = npc_def.visual_color if npc_def else Color(0.7, 0.5, 0.8)
	var occupation: String = npc_def.occupation if npc_def else ""

	# Collision shape
	var col = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 3.0
	col.shape = shape
	add_child(col)

	# Animated character model (client only — server skips visuals)
	if not multiplayer.is_server():
		var anim_config: Dictionary = NpcAnimator.SOCIAL_NPC_ANIMS.get(npc_id, NpcAnimator.DEFAULT_ANIMS)
		var config := {
			"idle": anim_config.get("idle", "Idle"),
			"actions": anim_config.get("actions", ["Yes"]),
			"color": npc_color,
		}
		_anim_state = NpcAnimator.create_character(self, config)

	# Name label
	var label = Label3D.new()
	var label_text = display_name
	if occupation != "":
		label_text += "\n[" + occupation + "]"
	UITheme.style_label3d(label, label_text, "npc_name")
	label.position.y = 2.0
	add_child(label)

	# Quest indicator (! or ?) — client-side only
	quest_indicator = Label3D.new()
	UITheme.style_label3d(quest_indicator, "", "quest_marker")
	quest_indicator.position.y = 2.6
	quest_indicator.visible = false
	add_child(quest_indicator)

func _process(delta: float) -> void:
	# Schedule resolution — runs on BOTH server and client
	# Both compute the same position from the synced SeasonManager clock
	_schedule_throttle += 1
	if _schedule_throttle >= 30:
		_schedule_throttle = 0
		_update_schedule_position()

	if multiplayer.is_server():
		return
	# Animate mannequin (client only)
	NpcAnimator.update_movement(_anim_state, self, delta)
	NpcAnimator.update(_anim_state, delta, self)
	if quest_indicator == null:
		return
	# Update quest indicator based on local player quest state
	DataRegistry.ensure_loaded()
	var has_completable: bool = false
	var has_available: bool = false
	# Check for completable quests (?) — active quests from this NPC
	for quest_id in PlayerData.active_quests:
		var qdef = DataRegistry.get_quest(quest_id)
		if qdef and qdef.quest_giver_npc_id == npc_id:
			has_completable = true
			break
	# Check for available quests (!) — not active, not completed, from this NPC
	if not has_completable:
		for quest_id in DataRegistry.quests:
			var qdef = DataRegistry.quests[quest_id]
			if qdef.quest_giver_npc_id != npc_id:
				continue
			if quest_id in PlayerData.active_quests:
				continue
			if quest_id in PlayerData.completed_quests:
				continue
			has_available = true
			break
	if has_completable:
		quest_indicator.text = "?"
		quest_indicator.modulate = UITokens.TEXT_SUCCESS
		quest_indicator.visible = true
	elif has_available:
		quest_indicator.text = "!"
		quest_indicator.modulate = UITokens.STAMP_GOLD
		quest_indicator.visible = true
	else:
		quest_indicator.visible = false

func _update_schedule_position() -> void:
	var season_mgr = get_node_or_null("/root/Main/GameWorld/SeasonManager")
	if season_mgr == null:
		return
	DataRegistry.ensure_loaded()
	var npc_def = DataRegistry.get_npc(npc_id)
	if npc_def == null or npc_def.schedule.is_empty():
		return
	var time_fraction: float = season_mgr.day_timer / season_mgr.DAY_DURATION if season_mgr.DAY_DURATION > 0 else 0.0
	var season_str: String = season_mgr.get_current_season()
	var target_pos: Vector3 = NpcAnimator.resolve_schedule_position(npc_def, time_fraction, season_str)
	if target_pos == Vector3.ZERO:
		return
	if multiplayer.is_server():
		# Server teleports for accurate Area3D proximity
		global_position = target_pos
	else:
		# Client stores target for smooth lerp via NpcAnimator.update_movement()
		set_meta("schedule_target", target_pos)

func _on_body_entered(body: Node3D) -> void:
	if not multiplayer.is_server():
		return
	if not body is CharacterBody3D:
		return
	var peer_id = body.name.to_int()
	if peer_id <= 0:
		return
	nearby_peers[peer_id] = true
	if body.get("is_busy"):
		return
	_show_npc_prompt.rpc_id(peer_id, npc_id)

func _on_body_exited(body: Node3D) -> void:
	if not multiplayer.is_server():
		return
	if body is CharacterBody3D:
		var peer_id = body.name.to_int()
		nearby_peers.erase(peer_id)
		_hide_npc_prompt.rpc_id(peer_id)

@rpc("any_peer", "reliable")
func request_talk() -> void:
	if not multiplayer.is_server():
		return
	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id not in nearby_peers:
		return
	# Check not busy/in battle
	var player_node = NetworkManager._get_player_node(peer_id)
	if player_node and player_node.get("is_busy"):
		return
	var battle_mgr = get_node_or_null("/root/Main/GameWorld/BattleManager")
	if battle_mgr and peer_id in battle_mgr.player_battle_map:
		return
	# Delegate to SocialManager
	var social_mgr = get_node_or_null("/root/Main/GameWorld/SocialManager")
	if social_mgr:
		social_mgr.handle_talk_request(peer_id, npc_id)
	# Also check for quests from this NPC (server-side call, sends RPC to client)
	var quest_mgr = get_node_or_null("/root/Main/GameWorld/QuestManager")
	if quest_mgr:
		var available = quest_mgr.get_available_quests(peer_id, npc_id)
		var completable = quest_mgr.get_completable_quests(peer_id, npc_id)
		if available.size() > 0 or completable.size() > 0:
			quest_mgr._send_quest_data_to_peer(peer_id, npc_id)

@rpc("any_peer", "reliable")
func request_give_gift(item_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id not in nearby_peers:
		return
	var player_node = NetworkManager._get_player_node(peer_id)
	if player_node and player_node.get("is_busy"):
		return
	var battle_mgr = get_node_or_null("/root/Main/GameWorld/BattleManager")
	if battle_mgr and peer_id in battle_mgr.player_battle_map:
		return
	var social_mgr = get_node_or_null("/root/Main/GameWorld/SocialManager")
	if social_mgr:
		social_mgr.handle_gift_request(peer_id, npc_id, item_id)

@rpc("authority", "reliable")
func _show_npc_prompt(_npc_id: String) -> void:
	NpcAnimator.play_reaction(_anim_state, "Yes")
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("show_interaction_prompt"):
		DataRegistry.ensure_loaded()
		var npc_def = DataRegistry.get_npc(_npc_id)
		var name_text = npc_def.display_name if npc_def else _npc_id
		hud.show_interaction_prompt(name_text + " (E: Talk)")

@rpc("authority", "reliable")
func _hide_npc_prompt() -> void:
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("hide_trainer_prompt"):
		hud.hide_trainer_prompt()
