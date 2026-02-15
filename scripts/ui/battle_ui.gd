extends CanvasLayer

# StatusEffects, FieldEffects available via class_name

# === Scene node refs (from .tscn) ===
@onready var weather_bar: PanelContainer = $WeatherBar
@onready var weather_label: Label = $WeatherBar/WeatherLabel
@onready var enemy_name: Label = $EnemyPanel/EnemyName
@onready var enemy_type_label: Label = $EnemyPanel/EnemyTypeLabel
@onready var enemy_hp_bar: ProgressBar = $EnemyPanel/EnemyHPBar
@onready var enemy_status: Label = $EnemyPanel/EnemyStatus
@onready var enemy_stat_label: Label = $EnemyPanel/EnemyStatLabel
@onready var enemy_hazard_label: Label = $EnemyPanel/EnemyHazardLabel
@onready var enemy_mesh_rect: ColorRect = $EnemyMesh
@onready var player_name: Label = $PlayerPanel/PlayerCreatureName
@onready var player_type_label: Label = $PlayerPanel/PlayerTypeLabel
@onready var player_hp_bar: ProgressBar = $PlayerPanel/PlayerHPBar
@onready var player_xp_bar: ProgressBar = $PlayerPanel/PlayerXPBar
@onready var player_status: Label = $PlayerPanel/PlayerStatus
@onready var player_ability_label: Label = $PlayerPanel/PlayerAbilityLabel
@onready var player_item_label: Label = $PlayerPanel/PlayerItemLabel
@onready var player_stat_label: Label = $PlayerPanel/PlayerStatLabel
@onready var player_hazard_label: Label = $PlayerPanel/PlayerHazardLabel
@onready var battle_log: RichTextLabel = $LogPanel/BattleLog
@onready var move_buttons: Array = [
	$ActionPanel/MoveGrid/Move1,
	$ActionPanel/MoveGrid/Move2,
	$ActionPanel/MoveGrid/Move3,
	$ActionPanel/MoveGrid/Move4
]
@onready var flee_button: Button = $ActionPanel/BottomButtons/FleeButton
@onready var switch_button: Button = $ActionPanel/BottomButtons/SwitchButton

# Dynamic overlay panels
var switch_panel: PanelContainer = null
var move_replace_panel: PanelContainer = null
var summary_panel: PanelContainer = null
var waiting_label: Label = null

var battle_mgr: Node = null

# Summary data accumulator
var _summary_victory: bool = false
var _summary_ready: bool = false

# Animation state
var _is_animating_log: bool = false
var _initial_setup: bool = false

const TYPE_COLORS = {
	"spicy": Color(0.9, 0.2, 0.1),
	"sweet": Color(0.9, 0.5, 0.7),
	"sour": Color(0.7, 0.8, 0.2),
	"herbal": Color(0.2, 0.7, 0.2),
	"umami": Color(0.5, 0.3, 0.2),
	"grain": Color(0.8, 0.7, 0.3),
}

const WEATHER_NAMES = {
	"spicy": "Sizzle Sun",
	"sweet": "Sugar Hail",
	"sour": "Acid Rain",
	"herbal": "Herb Breeze",
	"umami": "Umami Fog",
	"grain": "Grain Dust",
}

const STATUS_MAX_TURNS = {
	"burned": 5,
	"frozen": 5,
	"drowsy": 4,
	"wilted": 3,
	"soured": 3,
	"poisoned": 0, # escalating, no fixed end
	"brined": 4,
}

const STATUS_COLORS = {
	"burned": Color(0.9, 0.4, 0.1),
	"frozen": Color(0.3, 0.7, 1.0),
	"poisoned": Color(0.6, 0.2, 0.8),
	"drowsy": Color(0.7, 0.6, 0.9),
	"wilted": Color(0.5, 0.6, 0.3),
	"soured": Color(0.8, 0.8, 0.2),
	"brined": Color(0.2, 0.8, 0.8),
}

func _ready() -> void:
	for i in range(move_buttons.size()):
		var idx = i
		move_buttons[i].pressed.connect(func(): _on_move_pressed(idx))
		move_buttons[i].mouse_entered.connect(func(): _on_move_hover(idx, true))
		move_buttons[i].mouse_exited.connect(func(): _on_move_hover(idx, false))
	flee_button.pressed.connect(_on_flee_pressed)
	switch_button.pressed.connect(_on_switch_pressed)
	_create_dynamic_ui()

func _create_dynamic_ui() -> void:
	# Waiting for opponent label (PvP)
	waiting_label = Label.new()
	waiting_label.text = "Waiting for opponent..."
	waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	waiting_label.anchors_preset = Control.PRESET_CENTER
	waiting_label.visible = false
	add_child(waiting_label)

func setup(battle_manager: Node) -> void:
	battle_mgr = battle_manager
	battle_mgr.battle_started.connect(_on_battle_started)
	battle_mgr.battle_ended.connect(_on_battle_ended)
	battle_mgr.turn_result_received.connect(_on_turn_result)
	battle_mgr.xp_result_received.connect(_on_xp_result)
	battle_mgr.pvp_challenge_received.connect(_on_pvp_challenge)
	battle_mgr.trainer_dialogue.connect(_on_trainer_dialogue)
	battle_mgr.battle_state_updated.connect(_on_battle_state_updated)
	battle_mgr.battle_rewards_received.connect(_on_battle_rewards)
	battle_mgr.trainer_rewards_received.connect(_on_trainer_rewards)
	battle_mgr.pvp_loss_received.connect(_on_pvp_loss)
	battle_mgr.defeat_penalty_received.connect(_on_defeat_penalty)

func _on_battle_started() -> void:
	_initial_setup = true
	_is_animating_log = false

	# Hide PvP challenge UI if still showing (e.g. acceptor's dialog)
	var pvp_ui = get_node_or_null("/root/Main/GameWorld/UI/PvPChallengeUI")
	if pvp_ui:
		pvp_ui.visible = false

	# Hide trainer prompt if player was near a trainer
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("hide_trainer_prompt"):
		hud.hide_trainer_prompt()

	# Fade to black via HUD, then show battle UI
	if hud and hud.has_method("play_battle_transition"):
		await hud.play_battle_transition()

	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	battle_log.clear()
	_summary_ready = false

	# Clean up leftover panels from previous battle
	if summary_panel:
		summary_panel.queue_free()
		summary_panel = null
	if switch_panel:
		switch_panel.queue_free()
		switch_panel = null
	if move_replace_panel:
		move_replace_panel.queue_free()
		move_replace_panel = null

	# Restore child visibility (summary screen hides all children)
	for child in get_children():
		if child is Control:
			child.visible = true
	weather_bar.visible = false  # Hidden by default, shown when weather is set
	if waiting_label:
		waiting_label.visible = false  # Only shown in PvP after move submit

	var mode = battle_mgr.client_battle_mode if battle_mgr else 0
	match mode:
		0: # WILD
			battle_log.append_text("A wild creature appeared!\n")
		1: # TRAINER
			battle_log.append_text("Trainer battle!\n")
		2: # PVP
			battle_log.append_text("PvP battle!\n")

	# Hide flee for trainer/PvP
	flee_button.visible = (mode == 0)

	_refresh_ui()
	_initial_setup = false

	# Clear the fade
	if hud and hud.has_method("clear_battle_transition"):
		await hud.clear_battle_transition()

func _on_battle_ended(victory: bool) -> void:
	_summary_victory = victory
	# Wait a brief moment for reward RPCs to arrive, then show summary
	await get_tree().create_timer(0.5).timeout
	_show_summary_screen()

func _dismiss_summary() -> void:
	# Fade to black, hide UI, then clear
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("play_battle_transition"):
		await hud.play_battle_transition()

	if summary_panel:
		summary_panel.queue_free()
		summary_panel = null
	visible = false
	weather_bar.visible = false
	if waiting_label:
		waiting_label.visible = false
	if switch_panel:
		switch_panel.queue_free()
		switch_panel = null
	if move_replace_panel:
		move_replace_panel.queue_free()
		move_replace_panel = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if hud and hud.has_method("clear_battle_transition"):
		await hud.clear_battle_transition()

# === DISPLAY HELPERS ===

func _format_stat_stages(stages: Dictionary) -> String:
	var parts: Array = []
	var stat_abbrev = {
		"attack": "ATK", "defense": "DEF", "sp_attack": "SPA",
		"sp_defense": "SPD", "speed": "SPE", "accuracy": "ACC", "evasion": "EVA"
	}
	for stat_key in stages:
		var val = int(stages[stat_key])
		if val == 0:
			continue
		var abbr = stat_abbrev.get(stat_key, stat_key.to_upper())
		var prefix = "+" if val > 0 else ""
		parts.append("%s%s%d" % [abbr, prefix, val])
	return " ".join(parts)

func _format_hazards(hazards: Array) -> String:
	var names: Array = []
	for h in hazards:
		var data = FieldEffects.HAZARD_DATA.get(h, {})
		names.append(data.get("name", h))
	return ", ".join(names)

func _format_status_with_turns(status: String, turns: int) -> String:
	if status == "":
		return ""
	var display = StatusEffects.get_status_display_name(status)
	var max_t = STATUS_MAX_TURNS.get(status, 0)
	if status == "poisoned":
		return "%s (escalating)" % display
	if max_t > 0:
		return "%s (%d/%d turns)" % [display, turns, max_t]
	return display

func _format_types(types: Array) -> String:
	var names: Array = []
	for t in types:
		names.append(str(t).capitalize())
	return ", ".join(names)

func _update_weather_display() -> void:
	if battle_mgr == null:
		return
	var w = battle_mgr.client_weather
	var trick_room = battle_mgr.client_trick_room_turns if battle_mgr else 0
	if w == "" and trick_room <= 0:
		weather_bar.visible = false
		return
	weather_bar.visible = true
	var parts: Array = []
	if w != "":
		var wdata = FieldEffects.WEATHER_DATA.get(w, {})
		var wname = wdata.get("name", WEATHER_NAMES.get(w, w))
		var boost = wdata.get("boost_type", "").capitalize()
		var weaken = wdata.get("weaken_type", "").capitalize()
		var turns = battle_mgr.client_weather_turns
		parts.append("%s (%d turns) — %s +50%%, %s -50%%" % [wname, turns, boost, weaken])
	if trick_room > 0:
		parts.append("Trick Room (%d turns)" % trick_room)
	weather_label.text = " | ".join(parts)

func _update_hazard_display() -> void:
	if battle_mgr == null:
		return
	var ph = battle_mgr.client_player_hazards
	var eh = battle_mgr.client_enemy_hazards
	player_hazard_label.text = "Hazards: %s" % _format_hazards(ph) if ph.size() > 0 else ""
	enemy_hazard_label.text = "Hazards: %s" % _format_hazards(eh) if eh.size() > 0 else ""

func _update_stat_display() -> void:
	if battle_mgr == null:
		return
	var ps = _format_stat_stages(battle_mgr.client_player_stat_stages)
	var es = _format_stat_stages(battle_mgr.client_enemy_stat_stages)
	player_stat_label.text = "Stats: %s" % ps if ps != "" else ""
	enemy_stat_label.text = "Stats: %s" % es if es != "" else ""

func _on_battle_state_updated() -> void:
	_update_weather_display()
	_update_hazard_display()
	_update_stat_display()
	# Update status turns display
	_refresh_status_display()

func _refresh_status_display() -> void:
	if battle_mgr == null:
		return
	# Player status with turns + field effect badges
	var active_idx = battle_mgr.client_active_creature_idx
	if active_idx < PlayerData.party.size():
		var creature = PlayerData.party[active_idx]
		var s = creature.get("status", "")
		var parts: Array = []
		var status_text = _format_status_with_turns(s, battle_mgr.client_player_status_turns)
		if status_text != "":
			parts.append(status_text)
		if battle_mgr.client_player_taunt_turns > 0:
			parts.append("Taunted(%d)" % battle_mgr.client_player_taunt_turns)
		if battle_mgr.client_player_encore_turns > 0:
			parts.append("Encored(%d)" % battle_mgr.client_player_encore_turns)
		if battle_mgr.client_player_substitute_hp > 0:
			parts.append("Sub(%d HP)" % battle_mgr.client_player_substitute_hp)
		if battle_mgr.client_player_choice_locked != "":
			var locked_move = DataRegistry.get_move(battle_mgr.client_player_choice_locked)
			var locked_name = locked_move.display_name if locked_move else battle_mgr.client_player_choice_locked
			parts.append("Locked: %s" % locked_name)
		player_status.text = " | ".join(parts)
	# Enemy status with turns + field effect badges
	var enemy = battle_mgr.client_enemy
	var es = enemy.get("status", "")
	var eparts: Array = []
	var estatus_text = _format_status_with_turns(es, battle_mgr.client_enemy_status_turns)
	if estatus_text != "":
		eparts.append(estatus_text)
	if battle_mgr.client_enemy_taunt_turns > 0:
		eparts.append("Taunted(%d)" % battle_mgr.client_enemy_taunt_turns)
	if battle_mgr.client_enemy_encore_turns > 0:
		eparts.append("Encored(%d)" % battle_mgr.client_enemy_encore_turns)
	if battle_mgr.client_enemy_substitute_hp > 0:
		eparts.append("Sub(%d HP)" % battle_mgr.client_enemy_substitute_hp)
	enemy_status.text = " | ".join(eparts)

# === HP BAR TWEEN ===

func _tween_hp_bar(bar: ProgressBar, new_value: float, duration: float = 0.5) -> void:
	var tween = create_tween()
	tween.tween_property(bar, "value", new_value, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	# Color tint based on percentage
	var pct = new_value / bar.max_value if bar.max_value > 0 else 0.0
	var color: Color
	if pct > 0.5:
		color = Color(0.2, 0.8, 0.2)
	elif pct > 0.25:
		color = Color(0.9, 0.8, 0.1)
	else:
		color = Color(0.9, 0.2, 0.1)
	tween.parallel().tween_property(bar, "modulate", color, duration * 0.5)

# === HIT FLASH ===

func _flash_enemy_mesh() -> void:
	var tween = create_tween()
	tween.tween_property(enemy_mesh_rect, "modulate", Color(3.0, 3.0, 3.0), 0.05)
	tween.tween_property(enemy_mesh_rect, "modulate", Color.WHITE, 0.15)

func _flash_player_panel() -> void:
	var panel = get_node_or_null("PlayerPanel")
	if panel == null:
		return
	var tween = create_tween()
	tween.tween_property(panel, "modulate", Color(1.5, 0.5, 0.5), 0.05)
	tween.tween_property(panel, "modulate", Color.WHITE, 0.15)

# === SCREEN SHAKE ===

func _screen_shake(duration: float = 0.3, intensity: float = 8.0) -> void:
	var bg = get_node_or_null("BG")
	if bg == null:
		return
	var original_left = bg.offset_left
	var original_top = bg.offset_top
	var tween = create_tween()
	var steps = 6
	var step_dur = duration / steps
	for i in range(steps):
		var offset_x = randf_range(-intensity, intensity)
		var offset_y = randf_range(-intensity, intensity)
		tween.tween_property(bg, "offset_left", original_left + offset_x, step_dur)
		tween.parallel().tween_property(bg, "offset_top", original_top + offset_y, step_dur)
	tween.tween_property(bg, "offset_left", original_left, step_dur)
	tween.parallel().tween_property(bg, "offset_top", original_top, step_dur)

# === DAMAGE NUMBER POPUP ===

func _spawn_damage_number(amount: int, target: String, effectiveness: String = "") -> void:
	var lbl = Label.new()
	lbl.text = str(amount)
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.z_index = 100

	# Color based on effectiveness
	match effectiveness:
		"super_effective":
			lbl.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
		"not_very_effective":
			lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
		_:
			lbl.add_theme_color_override("font_color", Color.WHITE)

	# Position over target
	if target == "enemy":
		var rect = enemy_mesh_rect
		lbl.position = Vector2(rect.position.x + rect.size.x / 2.0 - 30, rect.position.y)
	else:
		var panel = get_node_or_null("PlayerPanel")
		if panel:
			lbl.position = Vector2(panel.position.x + panel.size.x / 2.0 - 30, panel.position.y)
		else:
			lbl.position = Vector2(200, 400)

	add_child(lbl)

	# Float up + fade out
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(lbl, "position:y", lbl.position.y - 60, 1.0).set_ease(Tween.EASE_OUT)
	tween.tween_property(lbl, "modulate:a", 0.0, 1.0).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(lbl.queue_free)

# === MOVE BUTTON HOVER ===

func _on_move_hover(idx: int, hovering: bool) -> void:
	if idx >= move_buttons.size():
		return
	var btn = move_buttons[idx]
	btn.pivot_offset = btn.size / 2.0
	var tween = create_tween()
	if hovering:
		tween.tween_property(btn, "scale", Vector2(1.05, 1.05), 0.1).set_ease(Tween.EASE_OUT)
	else:
		tween.tween_property(btn, "scale", Vector2.ONE, 0.1).set_ease(Tween.EASE_OUT)

func _refresh_ui() -> void:
	if battle_mgr == null:
		return
	DataRegistry.ensure_loaded()
	# Enemy info
	var enemy = battle_mgr.client_enemy
	var mode = battle_mgr.client_battle_mode if battle_mgr else 0
	var enemy_prefix = "Wild " if mode == 0 else ""
	enemy_name.text = "%s%s Lv.%d" % [enemy_prefix, enemy.get("nickname", "???"), enemy.get("level", 1)]
	var enemy_max_hp = enemy.get("max_hp", 1)
	enemy_hp_bar.max_value = enemy_max_hp
	if _initial_setup:
		enemy_hp_bar.value = enemy.get("hp", 0)
		# Reset HP bar color on initial setup
		var pct = float(enemy.get("hp", 0)) / enemy_max_hp if enemy_max_hp > 0 else 0.0
		enemy_hp_bar.modulate = Color(0.2, 0.8, 0.2) if pct > 0.5 else (Color(0.9, 0.8, 0.1) if pct > 0.25 else Color(0.9, 0.2, 0.1))
	# Enemy types
	var species = DataRegistry.get_species(enemy.get("species_id", ""))
	var enemy_types: Array = enemy.get("types", [])
	if enemy_types.is_empty() and species:
		enemy_types = Array(species.types)
	enemy_type_label.text = "Types: %s" % _format_types(enemy_types)
	# Set enemy color
	if species:
		enemy_mesh_rect.color = species.mesh_color
	# Enemy status (with turns from battle state)
	var es = enemy.get("status", "")
	enemy_status.text = _format_status_with_turns(es, battle_mgr.client_enemy_status_turns)

	# Player creature
	var active_idx = battle_mgr.client_active_creature_idx
	if active_idx < PlayerData.party.size():
		var creature = PlayerData.party[active_idx]
		player_name.text = "%s Lv.%d" % [creature.get("nickname", "???"), creature.get("level", 1)]
		var max_hp = creature.get("max_hp", 1)
		player_hp_bar.max_value = max_hp
		if _initial_setup:
			player_hp_bar.value = creature.get("hp", 0)
			var php = float(creature.get("hp", 0)) / max_hp if max_hp > 0 else 0.0
			player_hp_bar.modulate = Color(0.2, 0.8, 0.2) if php > 0.5 else (Color(0.9, 0.8, 0.1) if php > 0.25 else Color(0.9, 0.2, 0.1))
		# Player types
		var p_species = DataRegistry.get_species(creature.get("species_id", ""))
		var p_types: Array = creature.get("types", [])
		if p_types.is_empty() and p_species:
			p_types = Array(p_species.types)
		player_type_label.text = "Types: %s" % _format_types(p_types)
		# Player status
		var ps = creature.get("status", "")
		player_status.text = _format_status_with_turns(ps, battle_mgr.client_player_status_turns)
		# XP bar
		player_xp_bar.max_value = creature.get("xp_to_next", 100)
		if _initial_setup:
			player_xp_bar.value = creature.get("xp", 0)
		# Ability
		var ability_id = creature.get("ability_id", "")
		if ability_id != "":
			var ability = DataRegistry.get_ability(ability_id)
			player_ability_label.text = "Ability: %s" % (ability.display_name if ability else ability_id)
		else:
			player_ability_label.text = ""
		# Held item
		var item_id = creature.get("held_item_id", "")
		if item_id != "":
			var item = DataRegistry.get_held_item(item_id)
			player_item_label.text = "Item: %s" % (item.display_name if item else item_id)
		else:
			player_item_label.text = ""
		# Move buttons — 3-line detail
		var moves = creature.get("moves", [])
		var pp = creature.get("pp", [])
		for i in range(4):
			if i < moves.size():
				var move = DataRegistry.get_move(moves[i])
				if move:
					var pp_current = pp[i] if i < pp.size() else 0
					var pp_max = move.pp
					var line1 = move.display_name
					var line2 = ""
					if move.power > 0:
						line2 = "%s | %s | Pwr:%d" % [move.type.capitalize(), "Phys" if move.category == "physical" else "Spec", move.power]
					elif move.category == "status":
						line2 = "Status"
						if move.priority != 0:
							line2 += " | Pri:%+d" % move.priority
					else:
						line2 = "%s | %s" % [move.type.capitalize(), move.category.capitalize()]
					var line3 = ""
					if move.accuracy > 0:
						line3 = "Acc:%d%% | %d/%d PP" % [move.accuracy, pp_current, pp_max]
					else:
						line3 = "%d/%d PP" % [pp_current, pp_max]
					move_buttons[i].text = "%s\n%s\n%s" % [line1, line2, line3]
					var color = TYPE_COLORS.get(move.type, Color.GRAY)
					move_buttons[i].modulate = color.lerp(Color.WHITE, 0.5)
					move_buttons[i].visible = true
					move_buttons[i].disabled = (i < pp.size() and pp[i] <= 0)
					# Reset scale and set pivot for hover
					move_buttons[i].scale = Vector2.ONE
					move_buttons[i].pivot_offset = move_buttons[i].size / 2.0
				else:
					move_buttons[i].visible = false
			else:
				move_buttons[i].visible = false

	# Update weather/hazards/stats from battle state
	_update_weather_display()
	_update_hazard_display()
	_update_stat_display()

func _on_move_pressed(idx: int) -> void:
	if battle_mgr == null or not battle_mgr.awaiting_action:
		return
	var active_idx = battle_mgr.client_active_creature_idx
	if active_idx >= PlayerData.party.size():
		return
	var moves = PlayerData.party[active_idx].get("moves", [])
	if idx < moves.size():
		battle_mgr.send_move(moves[idx])
		_set_buttons_enabled(false)
		if battle_mgr.client_battle_mode == 2: # PVP
			waiting_label.visible = true

func _on_flee_pressed() -> void:
	if battle_mgr:
		battle_mgr.send_flee()
		_set_buttons_enabled(false)

# === PARTY SWITCH PICKER ===

func _on_switch_pressed() -> void:
	if battle_mgr == null or not battle_mgr.awaiting_action:
		return
	_show_switch_panel()

func _show_switch_panel() -> void:
	if switch_panel:
		switch_panel.queue_free()
	switch_panel = PanelContainer.new()
	switch_panel.anchors_preset = Control.PRESET_CENTER
	switch_panel.custom_minimum_size = Vector2(400, 0)
	var vbox = VBoxContainer.new()
	switch_panel.add_child(vbox)

	var title = Label.new()
	title.text = "Switch Creature"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var current = battle_mgr.client_active_creature_idx
	var found_any = false
	for i in range(PlayerData.party.size()):
		var c = PlayerData.party[i]
		var hp = c.get("hp", 0)
		var max_hp = c.get("max_hp", 1)
		var status_text = StatusEffects.get_status_display_name(c.get("status", ""))
		if status_text != "":
			status_text = " [%s]" % status_text
		var btn = Button.new()
		btn.text = "%s Lv.%d — HP: %d/%d%s" % [c.get("nickname", "???"), c.get("level", 1), hp, max_hp, status_text]
		btn.custom_minimum_size.y = 36
		if i == current or hp <= 0:
			btn.disabled = true
		else:
			found_any = true
			var idx = i
			btn.pressed.connect(func():
				battle_mgr.send_switch(idx)
				_set_buttons_enabled(false)
				if battle_mgr.client_battle_mode == 2:
					waiting_label.visible = true
				switch_panel.queue_free()
				switch_panel = null
			)
		vbox.add_child(btn)

	if not found_any:
		var lbl = Label.new()
		lbl.text = "No other creatures available!"
		vbox.add_child(lbl)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(func():
		switch_panel.queue_free()
		switch_panel = null
	)
	vbox.add_child(cancel_btn)

	add_child(switch_panel)

# === MOVE REPLACE DIALOG ===

func _show_move_replace_dialog(creature_idx: int, new_move_id: String) -> void:
	if move_replace_panel:
		move_replace_panel.queue_free()
	DataRegistry.ensure_loaded()
	var new_move = DataRegistry.get_move(new_move_id)
	if new_move == null:
		return

	move_replace_panel = PanelContainer.new()
	move_replace_panel.anchors_preset = Control.PRESET_CENTER
	move_replace_panel.custom_minimum_size = Vector2(450, 0)
	var vbox = VBoxContainer.new()
	move_replace_panel.add_child(vbox)

	var title = Label.new()
	title.text = "Learn %s?" % new_move.display_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var desc = Label.new()
	var power_text = "Pwr:%d" % new_move.power if new_move.power > 0 else "Status"
	desc.text = "%s | %s | %s | Acc:%d%%" % [new_move.type.capitalize(), new_move.category.capitalize(), power_text, new_move.accuracy]
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(desc)

	var sep = Label.new()
	sep.text = "Replace which move?"
	sep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sep)

	# Current moves
	var creature = PlayerData.party[creature_idx] if creature_idx < PlayerData.party.size() else {}
	var current_moves = creature.get("moves", [])
	var current_pp = creature.get("pp", [])
	for i in range(current_moves.size()):
		var old_move = DataRegistry.get_move(current_moves[i])
		if old_move == null:
			continue
		var old_pp = current_pp[i] if i < current_pp.size() else 0
		var btn = Button.new()
		var old_power_text = "Pwr:%d" % old_move.power if old_move.power > 0 else "Status"
		btn.text = "%s — %s | %s | %d/%d PP" % [old_move.display_name, old_move.type.capitalize(), old_power_text, old_pp, old_move.pp]
		btn.custom_minimum_size.y = 36
		var move_idx = i
		var nid = new_move_id
		var cidx = creature_idx
		btn.pressed.connect(func():
			battle_mgr.request_move_replace.rpc_id(1, cidx, move_idx, nid)
			# Update local party data
			if cidx < PlayerData.party.size():
				var m = PlayerData.party[cidx].get("moves", [])
				if m is PackedStringArray:
					m = Array(m)
				if move_idx < m.size():
					m[move_idx] = nid
					PlayerData.party[cidx]["moves"] = m
				var pp_arr = PlayerData.party[cidx].get("pp", [])
				if pp_arr is PackedInt32Array:
					pp_arr = Array(pp_arr)
				if move_idx < pp_arr.size():
					pp_arr[move_idx] = new_move.pp
					PlayerData.party[cidx]["pp"] = pp_arr
			battle_log.append_text("[color=green]Replaced with %s![/color]\n" % new_move.display_name)
			move_replace_panel.queue_free()
			move_replace_panel = null
			_refresh_ui()
		)
		vbox.add_child(btn)

	var skip_btn = Button.new()
	skip_btn.text = "Don't learn %s" % new_move.display_name
	skip_btn.pressed.connect(func():
		battle_mgr.skip_move_learn.rpc_id(1)
		battle_log.append_text("Chose not to learn %s.\n" % new_move.display_name)
		move_replace_panel.queue_free()
		move_replace_panel = null
	)
	vbox.add_child(skip_btn)

	add_child(move_replace_panel)

# === BATTLE SUMMARY SCREEN ===

func _show_summary_screen() -> void:
	if summary_panel:
		summary_panel.queue_free()

	# Hide battle panels so summary is clickable
	for child in get_children():
		if child is Control:
			child.visible = false

	summary_panel = PanelContainer.new()
	summary_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Start invisible for slide-in animation
	summary_panel.modulate.a = 0.0
	summary_panel.visible = true
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	summary_panel.add_child(center)
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(500, 0)
	center.add_child(vbox)

	# Title
	var title = Label.new()
	if _summary_victory:
		title.text = "Victory!"
		title.add_theme_color_override("font_color", Color(0.2, 0.9, 0.2))
	else:
		title.text = "Defeat..."
		title.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	# XP section
	if battle_mgr.summary_xp_results.size() > 0:
		var xp_header = Label.new()
		xp_header.text = "Experience:"
		xp_header.add_theme_font_size_override("font_size", 16)
		vbox.add_child(xp_header)
		for r in battle_mgr.summary_xp_results:
			var idx = r.get("creature_idx", 0)
			var xp = r.get("xp_gained", 0)
			var creature_name = "Creature"
			if idx < PlayerData.party.size():
				creature_name = PlayerData.party[idx].get("nickname", "Creature")
			var text = "  %s: +%d XP" % [creature_name, xp]
			for lvl in r.get("level_ups", []):
				text += " (Level %d!)" % lvl
			var lbl = Label.new()
			lbl.text = text
			if r.get("level_ups", []).size() > 0:
				lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
			vbox.add_child(lbl)

	# Evolutions
	if battle_mgr.summary_evolutions.size() > 0:
		for evo in battle_mgr.summary_evolutions:
			var lbl = Label.new()
			var new_species = DataRegistry.get_species(evo.get("new_species_id", ""))
			var evo_name = new_species.display_name if new_species else evo.get("new_species_id", "")
			lbl.text = "  Evolved into %s!" % evo_name
			lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.8))
			vbox.add_child(lbl)

	# New moves
	if battle_mgr.summary_new_moves.size() > 0:
		for nm in battle_mgr.summary_new_moves:
			if nm.get("auto", false):
				var move_def = DataRegistry.get_move(nm.get("move_id", ""))
				var move_name = move_def.display_name if move_def else nm.get("move_id", "???")
				var lbl = Label.new()
				lbl.text = "  Learned %s!" % move_name
				lbl.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
				vbox.add_child(lbl)

	# Drops section
	if battle_mgr.summary_drops.size() > 0:
		var drop_header = Label.new()
		drop_header.text = "Items received:"
		drop_header.add_theme_font_size_override("font_size", 16)
		vbox.add_child(drop_header)
		for item_id in battle_mgr.summary_drops:
			var ingredient = DataRegistry.get_ingredient(item_id)
			var item_name = ingredient.display_name if ingredient else item_id
			var lbl = Label.new()
			lbl.text = "  %s x%d" % [item_name, battle_mgr.summary_drops[item_id]]
			vbox.add_child(lbl)

	# Trainer rewards
	if battle_mgr.summary_trainer_money > 0:
		var lbl = Label.new()
		lbl.text = "$%d earned!" % battle_mgr.summary_trainer_money
		lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
		vbox.add_child(lbl)
	if battle_mgr.summary_trainer_ingredients.size() > 0:
		for item_id in battle_mgr.summary_trainer_ingredients:
			var ingredient = DataRegistry.get_ingredient(item_id)
			var item_name = ingredient.display_name if ingredient else item_id
			var lbl = Label.new()
			lbl.text = "  Bonus: %s x%d" % [item_name, battle_mgr.summary_trainer_ingredients[item_id]]
			vbox.add_child(lbl)

	# PvP loss
	if battle_mgr.summary_pvp_loss.size() > 0:
		var pvp_header = Label.new()
		pvp_header.text = "Items lost:"
		pvp_header.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		vbox.add_child(pvp_header)
		for item_id in battle_mgr.summary_pvp_loss:
			var ingredient = DataRegistry.get_ingredient(item_id)
			var item_name = ingredient.display_name if ingredient else item_id
			var lbl = Label.new()
			lbl.text = "  %s x%d" % [item_name, battle_mgr.summary_pvp_loss[item_id]]
			vbox.add_child(lbl)

	# Defeat penalty
	if battle_mgr.summary_defeat_penalty > 0:
		var lbl = Label.new()
		lbl.text = "Lost $%d. Returned to camp." % battle_mgr.summary_defeat_penalty
		lbl.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		vbox.add_child(lbl)

	# Continue button
	var continue_btn = Button.new()
	continue_btn.text = "Continue"
	continue_btn.custom_minimum_size.y = 40
	continue_btn.pressed.connect(_dismiss_summary)
	vbox.add_child(continue_btn)

	add_child(summary_panel)

	# Slide-in animation
	var start_offset = summary_panel.offset_top
	summary_panel.offset_top = start_offset + 100
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(summary_panel, "modulate:a", 1.0, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(summary_panel, "offset_top", start_offset, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

# === REWARD SIGNAL HANDLERS ===

func _on_battle_rewards(drops: Dictionary) -> void:
	battle_mgr.summary_drops = drops
	if drops.size() > 0:
		var drop_text = ""
		for item_id in drops:
			var ingredient = DataRegistry.get_ingredient(item_id)
			var item_name = ingredient.display_name if ingredient else item_id
			drop_text += "%s x%d  " % [item_name, drops[item_id]]
		battle_log.append_text("[color=cyan]Drops: %s[/color]\n" % drop_text.strip_edges())

func _on_trainer_rewards(money: int, ingredients: Dictionary) -> void:
	battle_mgr.summary_trainer_money = money
	battle_mgr.summary_trainer_ingredients = ingredients
	battle_log.append_text("[color=yellow]Trainer reward: $%d[/color]\n" % money)
	for item_id in ingredients:
		var ingredient = DataRegistry.get_ingredient(item_id)
		var item_name = ingredient.display_name if ingredient else item_id
		battle_log.append_text("[color=yellow]  + %s x%d[/color]\n" % [item_name, ingredients[item_id]])

func _on_pvp_loss(lost_items: Dictionary) -> void:
	battle_mgr.summary_pvp_loss = lost_items
	battle_log.append_text("[color=red]Lost items in PvP defeat![/color]\n")

func _on_defeat_penalty(money_lost: int) -> void:
	battle_mgr.summary_defeat_penalty = money_lost
	if money_lost > 0:
		battle_log.append_text("[color=red]Lost $%d![/color]\n" % money_lost)
	battle_log.append_text("[color=red]Returned to camp.[/color]\n")

# === TURN RESULT + XP ===

func _on_turn_result(turn_log: Array) -> void:
	if waiting_label:
		waiting_label.visible = false
	_set_buttons_enabled(false)
	_is_animating_log = true
	_animate_turn_log(turn_log)

func _animate_turn_log(turn_log: Array) -> void:
	for entry in turn_log:
		var msg = _format_log_entry(entry)
		if msg != "":
			battle_log.append_text(msg + "\n")

		# Visual effects per entry
		var actor = entry.get("actor", "")
		var entry_type = entry.get("type", "move")

		if entry_type == "move" and entry.has("damage") and entry.damage > 0:
			# Damage number popup
			var target = "enemy" if actor == "player" else "player"
			_spawn_damage_number(entry.damage, target, entry.get("effectiveness", ""))
			# Hit flash
			if actor == "player":
				_flash_enemy_mesh()
			else:
				_flash_player_panel()
			# Screen shake on critical hit
			if entry.get("critical", false):
				_screen_shake()

		# Tween HP bars after each entry with damage/heal
		if entry_type in ["move", "status_damage", "ability_heal", "item_heal", "hazard_damage", "substitute_created", "substitute_broken"]:
			if battle_mgr:
				var enemy = battle_mgr.client_enemy
				_tween_hp_bar(enemy_hp_bar, enemy.get("hp", 0))
				var aidx = battle_mgr.client_active_creature_idx
				if aidx < PlayerData.party.size():
					_tween_hp_bar(player_hp_bar, PlayerData.party[aidx].get("hp", 0))

		# Stagger delay between entries
		if msg != "":
			await get_tree().create_timer(0.3).timeout

	_is_animating_log = false
	_refresh_ui()
	if battle_mgr and battle_mgr.awaiting_action:
		_set_buttons_enabled(true)

func _on_xp_result(results: Dictionary) -> void:
	for r in results.get("results", []):
		# Accumulate for summary
		battle_mgr.summary_xp_results.append(r)
		var xp = r.get("xp_gained", 0)
		if xp > 0:
			battle_log.append_text("[color=cyan]+%d XP[/color]\n" % xp)
		for lvl in r.get("level_ups", []):
			battle_log.append_text("[color=yellow]Level up! Now Lv.%d![/color]\n" % lvl)
		for m in r.get("new_moves", []):
			battle_mgr.summary_new_moves.append(m)
			var move_def = DataRegistry.get_move(m.get("move_id", ""))
			var move_name = move_def.display_name if move_def else m.get("move_id", "???")
			if m.get("auto", false):
				battle_log.append_text("[color=green]Learned %s![/color]\n" % move_name)
			else:
				battle_log.append_text("[color=yellow]Wants to learn %s! (Full moveset)[/color]\n" % move_name)
				# Show move-replace dialog
				_show_move_replace_dialog(r.get("creature_idx", 0), m.get("move_id", ""))
		if r.get("evolved", false):
			battle_mgr.summary_evolutions.append({"creature_idx": r.get("creature_idx", 0), "new_species_id": r.get("new_species_id", "")})
			var new_species = DataRegistry.get_species(r.get("new_species_id", ""))
			var evo_name = new_species.display_name if new_species else r.get("new_species_id", "")
			battle_log.append_text("[color=magenta]Evolved into %s![/color]\n" % evo_name)

	# Tween XP bar
	var active_idx = battle_mgr.client_active_creature_idx if battle_mgr else 0
	if active_idx < PlayerData.party.size():
		var creature = PlayerData.party[active_idx]
		player_xp_bar.max_value = creature.get("xp_to_next", 100)
		var tween = create_tween()
		tween.tween_property(player_xp_bar, "value", float(creature.get("xp", 0)), 0.8).set_ease(Tween.EASE_OUT)

	_refresh_ui()

func _on_pvp_challenge(challenger_name: String, challenger_peer: int) -> void:
	var ui = get_node_or_null("/root/Main/GameWorld/UI/PvPChallengeUI")
	if ui and ui.has_method("show_challenge"):
		ui.show_challenge(challenger_name, challenger_peer)

func _on_trainer_dialogue(trainer_name: String, text: String, _is_before: bool) -> void:
	var ui = get_node_or_null("/root/Main/GameWorld/UI/TrainerDialogueUI")
	if ui and ui.has_method("show_dialogue"):
		ui.show_dialogue(trainer_name, text)
	else:
		battle_log.append_text("[color=orange]%s: %s[/color]\n" % [trainer_name, text])

# === LOG FORMATTING ===

func _format_log_entry(entry: Dictionary) -> String:
	var entry_type = entry.get("type", "move")
	match entry_type:
		"move":
			var actor_name = "You" if entry.get("actor") == "player" else "Enemy"
			var move_name = entry.get("move", "???")
			var text = "%s used %s!" % [actor_name, move_name]
			if entry.get("missed", false):
				return text + " But it missed!"
			if entry.get("skipped", false):
				return "%s %s" % [actor_name, entry.get("message", "can't move!")]
			if entry.get("charging", false):
				return "%s %s" % [actor_name, entry.get("message", "is charging up!")]
			if entry.get("protecting", false):
				return "%s %s" % [actor_name, entry.get("message", "protected itself!")]
			if entry.get("blocked", false):
				return "%s's attack %s" % [actor_name, entry.get("message", "was blocked!")]
			if entry.get("immune", false):
				return text + " [color=gray]It doesn't affect the target...[/color]"
			if entry.has("damage"):
				text += " Dealt %d damage." % entry.damage
			if entry.get("hit_count", 1) > 1:
				text += " Hit %d times!" % entry.hit_count
			if entry.get("effectiveness") == "super_effective":
				text += " [color=green]Super effective![/color]"
			elif entry.get("effectiveness") == "not_very_effective":
				text += " [color=yellow]Not very effective...[/color]"
			elif entry.get("effectiveness") == "immune":
				text += " [color=gray]No effect![/color]"
			if entry.get("critical", false):
				text += " Critical hit!"
			if entry.has("recoil"):
				text += " %s took %d recoil!" % [actor_name, entry.recoil]
			if entry.has("drain_heal"):
				text += " Drained %d HP!" % entry.drain_heal
			if entry.has("ability_heal"):
				text += " Absorbed %d HP!" % entry.ability_heal
			if entry.has("status_applied"):
				text += " Inflicted %s!" % StatusEffects.get_status_display_name(entry.status_applied)
			if entry.has("heal"):
				text += " Healed %d HP!" % entry.heal
			if entry.has("stat_changes"):
				for stat in entry.stat_changes:
					var change = entry.stat_changes[stat]
					var direction = "rose" if change > 0 else "fell"
					var amount = "sharply " if abs(change) >= 2 else ""
					text += " %s %s%s!" % [stat.capitalize(), amount, direction]
			if entry.has("target_stat_changes"):
				for stat in entry.target_stat_changes:
					var change = entry.target_stat_changes[stat]
					var direction = "rose" if change > 0 else "fell"
					text += " Foe's %s %s!" % [stat.capitalize(), direction]
			if entry.has("weather_set"):
				var wname = WEATHER_NAMES.get(entry.weather_set, entry.weather_set)
				text += " %s started!" % wname
			if entry.has("hazard_set"):
				text += " Set %s!" % entry.hazard_set
			if entry.has("hazards_cleared"):
				text += " Cleared hazards!"
			if entry.get("substitute_created", false):
				text += " Created a substitute!"
			if entry.get("substitute_broke", false):
				text += " The substitute broke!"
			if entry.get("substitute_blocked", false):
				text += " The substitute took the hit!"
			if entry.has("knocked_off_item"):
				text += " Knocked off %s!" % entry.knocked_off_item
			if entry.get("focus_sash_triggered", false):
				text += " [color=cyan]Held on with Focus Spatula![/color]"
			if entry.get("bond_endure_triggered", false):
				text += " [color=yellow]Toughed it out from the bond with its trainer![/color]"
			if entry.has("life_orb_recoil"):
				text += " Lost %d HP from Flavor Crystal!" % entry.life_orb_recoil
			if entry.get("switch_after", false):
				text += " Dashed back!"
			if entry.get("force_switch_failed", false):
				text += " But it failed!"
			if entry.has("defender_item_trigger"):
				var msg = entry.defender_item_trigger.get("message", "")
				if msg != "":
					text += " Foe " + msg
			if entry.has("attacker_item_trigger"):
				var msg = entry.attacker_item_trigger.get("message", "")
				if msg != "":
					text += " " + actor_name + " " + msg
			# Ability messages
			if entry.has("ability_messages"):
				for amsg in entry.ability_messages:
					text += "\n  [color=purple]%s[/color]" % amsg
			# Item messages
			if entry.has("item_messages"):
				for imsg in entry.item_messages:
					text += "\n  [color=cyan]%s[/color]" % imsg
			return text
		"ability_trigger":
			var actor_name = "Your creature" if entry.get("actor") == "player" else "Enemy"
			return "[color=purple]%s's %s[/color]" % [actor_name, entry.get("message", "")]
		"status_damage":
			var actor_name = "Your creature" if entry.get("actor") == "player" else "Enemy"
			return "%s %s (%d damage)" % [actor_name, entry.get("message", ""), entry.get("damage", 0)]
		"ability_heal":
			var actor_name = "Your creature" if entry.get("actor") == "player" else "Enemy"
			return "%s %s (+%d HP)" % [actor_name, entry.get("message", ""), entry.get("heal", 0)]
		"item_heal":
			var actor_name = "Your creature" if entry.get("actor") == "player" else "Enemy"
			return "%s %s (+%d HP)" % [actor_name, entry.get("message", ""), entry.get("heal", 0)]
		"weather_cleared":
			var wname = WEATHER_NAMES.get(entry.get("weather", ""), "weather")
			return "The %s subsided." % wname
		"hazard_damage":
			var actor_name = "Your creature" if entry.get("actor") == "player" else "Enemy"
			return "%s was hurt by %s! (%d damage)" % [actor_name, entry.get("hazard", "hazards"), entry.get("damage", 0)]
		"hazard_effect":
			var actor_name = "Your creature" if entry.get("actor") == "player" else "Enemy"
			return "%s was affected by %s!" % [actor_name, entry.get("hazard", "hazards")]
		"trick_room_set":
			return "[color=purple]Trick Room distorted the dimensions![/color]"
		"trick_room_ended":
			return "[color=purple]Trick Room wore off.[/color]"
		"taunt_applied":
			var target_name = "Your creature" if entry.get("actor") == "enemy" else "Enemy"
			return "%s was taunted!" % target_name
		"taunt_ended":
			var actor_name2 = "Your creature" if entry.get("actor") == "player" else "Enemy"
			return "%s's taunt wore off." % actor_name2
		"encore_applied":
			var target_name = "Your creature" if entry.get("actor") == "enemy" else "Enemy"
			return "%s got an encore!" % target_name
		"encore_ended":
			var actor_name2 = "Your creature" if entry.get("actor") == "player" else "Enemy"
			return "%s's encore ended." % actor_name2
		"substitute_created":
			var actor_name2 = "Your creature" if entry.get("actor") == "player" else "Enemy"
			return "%s put up a substitute!" % actor_name2
		"substitute_broken":
			var actor_name2 = "Your creature" if entry.get("actor") == "player" else "Enemy"
			return "%s's substitute broke!" % actor_name2
		"forced_switch":
			var actor_name2 = "Your creature" if entry.get("actor") == "player" else "Enemy"
			return "%s was forced out!" % actor_name2
		"force_switch_failed":
			return "But it failed!"
		"bond_cured":
			var actor_name2 = "Your creature" if entry.get("actor") == "player" else "Enemy"
			return "[color=yellow]%s's bond cured its %s![/color]" % [actor_name2, entry.get("status", "status")]
		"sleep_talk_move":
			var actor_name2 = "Your creature" if entry.get("actor") == "player" else "Enemy"
			return "%s used a move in its sleep!" % actor_name2
		"trainer_switch":
			return "Trainer sent out the next creature!"
		"victory":
			return "[color=green]Victory![/color]"
		"defeat":
			return "[color=red]All your creatures fainted![/color]"
		"fled":
			return "Got away safely!"
		"flee_failed":
			return "Couldn't escape!"
		"fainted":
			return "[color=red]Your creature fainted![/color] Switch to another!"
		"switch":
			return "Switched creature!"
	return ""

func _set_buttons_enabled(enabled: bool) -> void:
	var mode = battle_mgr.client_battle_mode if battle_mgr else 0
	flee_button.disabled = not enabled
	flee_button.visible = (mode == 0) # Only show flee for wild
	switch_button.disabled = not enabled
	if not enabled:
		for btn in move_buttons:
			btn.disabled = true
		return
	# Enable moves but respect taunt/choice lock/encore restrictions
	if battle_mgr == null:
		for btn in move_buttons:
			btn.disabled = false
		return
	var active_idx = battle_mgr.client_active_creature_idx
	if active_idx >= PlayerData.party.size():
		return
	var creature = PlayerData.party[active_idx]
	var moves = creature.get("moves", [])
	var pp = creature.get("pp", [])
	var is_taunted = battle_mgr.client_player_taunt_turns > 0
	var choice_locked = battle_mgr.client_player_choice_locked
	var encore_turns = battle_mgr.client_player_encore_turns
	var encore_move = battle_mgr.client_player_encore_move
	for i in range(move_buttons.size()):
		if i >= moves.size() or not move_buttons[i].visible:
			continue
		var is_disabled = false
		# Out of PP
		if i < pp.size() and pp[i] <= 0:
			is_disabled = true
		# Taunted: disable status moves
		if is_taunted and not is_disabled:
			var move = DataRegistry.get_move(moves[i])
			if move and move.category == "status":
				is_disabled = true
		# Choice locked: disable non-locked moves
		if choice_locked != "" and moves[i] != choice_locked:
			is_disabled = true
		# Encored: disable non-encore moves
		if encore_turns > 0 and encore_move != "" and moves[i] != encore_move:
			is_disabled = true
		move_buttons[i].disabled = is_disabled
