extends Node

# 3D Battle Arena UI — replaces the old 2D CanvasLayer battle_ui.
# Connects to the same BattleManager signals. Delegates 3D visuals to BattleArena,
# keeps a CanvasLayer child for the 2D action panel (move buttons, log, overlays).
# Pokemon-style: 2D info cards, camera cuts, particle VFX, action menu.

# StatusEffects, FieldEffects available via class_name
const UITokens = preload("res://scripts/ui/ui_tokens.gd")
const BattleArenaScript = preload("res://scripts/battle/battle_arena.gd")
const BattleEffects = preload("res://scripts/battle/battle_effects.gd")

enum BattlePhase { INTRO, PROMPT, ACTION_SELECT, ANIMATING, WAITING, ENDED }
var _phase: int = BattlePhase.INTRO
var _buffered_turn_logs: Array = []

var battle_mgr: Node = null
var arena: Node3D = null # BattleArena instance
var _saved_player_camera: Camera3D = null

# 2D action panel (CanvasLayer)
var action_layer: CanvasLayer
var battle_log: RichTextLabel
var log_panel: PanelContainer
var weather_bar: PanelContainer
var weather_label: Label
var prompt_label: Label

# Pokemon-style action menu
var action_menu_panel: PanelContainer  # The "What will you do?" menu
var fight_button: Button
var item_button: Button
var switch_button: Button
var flee_button: Button
var move_panel: PanelContainer  # Move selection grid (shown when Fight is pressed)
var move_buttons: Array = []  # Array[Button]
var action_panel: VBoxContainer  # Legacy container reference for phase show/hide

# Enemy card (top-left)
var enemy_card: PanelContainer
var enemy_card_name: Label
var enemy_card_types: Label
var enemy_card_hp_bar: ProgressBar
var enemy_card_hp_text: Label
var enemy_card_status: Label
var enemy_card_hazards: Label
var enemy_card_stats: Label

# Player card (bottom-right, above action area)
var player_card: PanelContainer
var player_card_name: Label
var player_card_types: Label
var player_card_hp_bar: ProgressBar
var player_card_hp_text: Label
var player_card_xp_bar: ProgressBar
var player_card_xp_text: Label
var player_card_ability: Label
var player_card_item: Label
var player_card_status: Label
var player_card_locked: Label

# Dynamic overlay panels
var switch_panel: PanelContainer = null
var item_panel: PanelContainer = null
var move_replace_panel: PanelContainer = null
var summary_panel: PanelContainer = null
var waiting_label: Label = null

# Summary data accumulator
var _summary_victory: bool = false
var _is_animating_log: bool = false
var _initial_setup: bool = false
var _battle_starting: bool = false  # Guards against battle_ended during _on_battle_started awaits


const TYPE_COLORS = {
	"spicy": UITokens.TYPE_SPICY,
	"sweet": UITokens.TYPE_SWEET,
	"sour": UITokens.TYPE_SOUR,
	"herbal": UITokens.TYPE_HERBAL,
	"umami": UITokens.TYPE_UMAMI,
	"grain": UITokens.TYPE_GRAIN,
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
	"poisoned": 0,
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
	UITheme.init()
	_build_action_layer()

func _build_action_layer() -> void:
	action_layer = CanvasLayer.new()
	action_layer.name = "BattleActionLayer"
	action_layer.layer = 12
	action_layer.visible = false
	add_child(action_layer)

	# Semi-transparent background for bottom portion (35% of screen)
	var bg = ColorRect.new()
	bg.name = "ActionBG"
	bg.color = Color(0.15, 0.12, 0.1, 0.85)
	bg.anchor_left = 0.0
	bg.anchor_top = 0.65
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.offset_left = 0
	bg.offset_top = 0
	bg.offset_right = 0
	bg.offset_bottom = 0
	action_layer.add_child(bg)

	# Weather bar at top of screen
	weather_bar = PanelContainer.new()
	weather_bar.name = "WeatherBar"
	weather_bar.anchor_left = 0.1
	weather_bar.anchor_top = 0.01
	weather_bar.anchor_right = 0.9
	weather_bar.anchor_bottom = 0.05
	weather_bar.visible = false
	UITheme.apply_panel(weather_bar)
	action_layer.add_child(weather_bar)

	weather_label = Label.new()
	weather_label.name = "WeatherLabel"
	weather_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_small(weather_label)
	weather_bar.add_child(weather_label)

	# Prompt label (centered, above action panel)
	prompt_label = Label.new()
	prompt_label.name = "PromptLabel"
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.anchor_left = 0.2
	prompt_label.anchor_top = 0.53
	prompt_label.anchor_right = 0.8
	prompt_label.anchor_bottom = 0.59
	prompt_label.offset_left = 0
	prompt_label.offset_top = 0
	prompt_label.offset_right = 0
	prompt_label.offset_bottom = 0
	prompt_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_H3))
	prompt_label.add_theme_color_override("font_color", UITokens.PAPER_CREAM)
	prompt_label.visible = false
	action_layer.add_child(prompt_label)

	# Enemy info card (top-left)
	_build_enemy_card()

	# Player info card (right side, above action area)
	_build_player_card()

	# Battle log — left side of bottom area
	log_panel = PanelContainer.new()
	log_panel.name = "LogPanel"
	log_panel.anchor_left = 0.01
	log_panel.anchor_top = 0.66
	log_panel.anchor_right = 0.54
	log_panel.anchor_bottom = 0.99
	log_panel.offset_left = 0
	log_panel.offset_top = 0
	log_panel.offset_right = 0
	log_panel.offset_bottom = 0
	UITheme.apply_panel(log_panel)
	action_layer.add_child(log_panel)

	battle_log = RichTextLabel.new()
	battle_log.name = "BattleLog"
	battle_log.bbcode_enabled = true
	battle_log.scroll_following = true
	battle_log.add_theme_color_override("default_color", UITokens.INK_DARK)
	log_panel.add_child(battle_log)

	# Pokemon-style action menu (right side, bottom)
	_build_action_menu()

	# Move selection panel (hidden by default, replaces action menu when Fight pressed)
	_build_move_panel()

	# Waiting label (PvP)
	waiting_label = Label.new()
	waiting_label.text = "Waiting for opponent..."
	UITheme.style_toast(waiting_label)
	waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	waiting_label.anchors_preset = Control.PRESET_CENTER
	waiting_label.visible = false
	action_layer.add_child(waiting_label)

	# Legacy action_panel reference (used by _set_phase for visibility toggling)
	action_panel = VBoxContainer.new()
	action_panel.visible = false

func _build_action_menu() -> void:
	action_menu_panel = PanelContainer.new()
	action_menu_panel.name = "ActionMenu"
	action_menu_panel.anchor_left = 0.56
	action_menu_panel.anchor_top = 0.66
	action_menu_panel.anchor_right = 0.99
	action_menu_panel.anchor_bottom = 0.99
	action_menu_panel.offset_left = 0
	action_menu_panel.offset_top = 0
	action_menu_panel.offset_right = 0
	action_menu_panel.offset_bottom = 0
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.15, 0.12, 0.9)
	style.border_color = Color(0.5, 0.42, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	action_menu_panel.add_theme_stylebox_override("panel", style)
	action_layer.add_child(action_menu_panel)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	action_menu_panel.add_child(grid)

	fight_button = Button.new()
	fight_button.name = "FightButton"
	fight_button.text = "FIGHT"
	fight_button.custom_minimum_size = Vector2(0, 50)
	fight_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fight_button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UITheme.style_button(fight_button, "primary")
	fight_button.pressed.connect(_on_fight_pressed)
	grid.add_child(fight_button)

	item_button = Button.new()
	item_button.name = "ItemButton"
	item_button.text = "ITEM"
	item_button.custom_minimum_size = Vector2(0, 50)
	item_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UITheme.style_button(item_button, "info")
	item_button.pressed.connect(_on_item_pressed)
	grid.add_child(item_button)

	switch_button = Button.new()
	switch_button.name = "SwitchButton"
	switch_button.text = "SWITCH"
	switch_button.custom_minimum_size = Vector2(0, 50)
	switch_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	switch_button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UITheme.style_button(switch_button, "secondary")
	switch_button.pressed.connect(_on_switch_pressed)
	grid.add_child(switch_button)

	flee_button = Button.new()
	flee_button.name = "FleeButton"
	flee_button.text = "FLEE"
	flee_button.custom_minimum_size = Vector2(0, 50)
	flee_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flee_button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UITheme.style_button(flee_button, "danger")
	flee_button.pressed.connect(_on_flee_pressed)
	grid.add_child(flee_button)

func _build_move_panel() -> void:
	move_panel = PanelContainer.new()
	move_panel.name = "MovePanel"
	move_panel.anchor_left = 0.56
	move_panel.anchor_top = 0.66
	move_panel.anchor_right = 0.99
	move_panel.anchor_bottom = 0.99
	move_panel.offset_left = 0
	move_panel.offset_top = 0
	move_panel.offset_right = 0
	move_panel.offset_bottom = 0
	move_panel.visible = false
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.15, 0.12, 0.9)
	style.border_color = Color(0.5, 0.42, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	move_panel.add_theme_stylebox_override("panel", style)
	action_layer.add_child(move_panel)

	var vbox = VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	move_panel.add_child(vbox)

	var move_grid = GridContainer.new()
	move_grid.name = "MoveGrid"
	move_grid.columns = 2
	move_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	move_grid.add_theme_constant_override("h_separation", 6)
	move_grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(move_grid)

	for i in range(4):
		var btn = Button.new()
		btn.name = "Move%d" % (i + 1)
		btn.text = "Move %d" % (i + 1)
		btn.custom_minimum_size = Vector2(0, 40)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		UITheme.style_button(btn, "primary")
		var idx = i
		btn.pressed.connect(func(): _on_move_pressed(idx))
		btn.mouse_entered.connect(func(): _on_move_hover(idx, true))
		btn.mouse_exited.connect(func(): _on_move_hover(idx, false))
		move_grid.add_child(btn)
		move_buttons.append(btn)

	var back_btn = Button.new()
	back_btn.name = "BackButton"
	back_btn.text = "Back"
	back_btn.custom_minimum_size.y = 30
	UITheme.style_button(back_btn, "danger")
	back_btn.pressed.connect(_on_move_back_pressed)
	vbox.add_child(back_btn)

func _build_enemy_card() -> void:
	enemy_card = PanelContainer.new()
	enemy_card.name = "EnemyCard"
	enemy_card.anchor_left = 0.01
	enemy_card.anchor_top = 0.06
	enemy_card.anchor_right = 0.28
	enemy_card.anchor_bottom = 0.32
	enemy_card.offset_left = 0
	enemy_card.offset_top = 0
	enemy_card.offset_right = 0
	enemy_card.offset_bottom = 0
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.08, 0.9)
	style.border_color = Color(0.4, 0.35, 0.25)
	style.set_border_width_all(2)
	style.border_width_left = 4  # Type-colored accent border
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	enemy_card.add_theme_stylebox_override("panel", style)
	action_layer.add_child(enemy_card)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	enemy_card.add_child(vbox)

	enemy_card_name = Label.new()
	enemy_card_name.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_SMALL))
	enemy_card_name.add_theme_color_override("font_color", UITokens.PAPER_CREAM)
	vbox.add_child(enemy_card_name)

	enemy_card_types = Label.new()
	enemy_card_types.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
	enemy_card_types.add_theme_color_override("font_color", Color(0.8, 0.75, 0.65))
	vbox.add_child(enemy_card_types)

	# HP bar
	var hp_container = HBoxContainer.new()
	hp_container.add_theme_constant_override("separation", 6)
	vbox.add_child(hp_container)

	enemy_card_hp_bar = ProgressBar.new()
	enemy_card_hp_bar.max_value = 100
	enemy_card_hp_bar.value = 100
	enemy_card_hp_bar.show_percentage = false
	enemy_card_hp_bar.custom_minimum_size = Vector2(0, 14)
	enemy_card_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_container.add_child(enemy_card_hp_bar)

	enemy_card_hp_text = Label.new()
	enemy_card_hp_text.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
	enemy_card_hp_text.add_theme_color_override("font_color", UITokens.PAPER_CREAM)
	enemy_card_hp_text.custom_minimum_size.x = 70
	hp_container.add_child(enemy_card_hp_text)

	enemy_card_status = Label.new()
	enemy_card_status.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
	enemy_card_status.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	enemy_card_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(enemy_card_status)

	enemy_card_hazards = Label.new()
	enemy_card_hazards.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
	enemy_card_hazards.add_theme_color_override("font_color", Color(0.9, 0.5, 0.3))
	vbox.add_child(enemy_card_hazards)

	enemy_card_stats = Label.new()
	enemy_card_stats.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
	enemy_card_stats.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	enemy_card_stats.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(enemy_card_stats)

func _build_player_card() -> void:
	player_card = PanelContainer.new()
	player_card.name = "PlayerCard"
	player_card.anchor_left = 0.70
	player_card.anchor_top = 0.35
	player_card.anchor_right = 0.99
	player_card.anchor_bottom = 0.63
	player_card.offset_left = 0
	player_card.offset_top = 0
	player_card.offset_right = 0
	player_card.offset_bottom = 0
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.08, 0.9)
	style.border_color = Color(0.4, 0.35, 0.25)
	style.set_border_width_all(2)
	style.border_width_left = 4  # Type-colored accent border
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	player_card.add_theme_stylebox_override("panel", style)
	action_layer.add_child(player_card)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	player_card.add_child(vbox)

	player_card_name = Label.new()
	player_card_name.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_SMALL))
	player_card_name.add_theme_color_override("font_color", UITokens.PAPER_CREAM)
	vbox.add_child(player_card_name)

	player_card_types = Label.new()
	player_card_types.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
	player_card_types.add_theme_color_override("font_color", Color(0.8, 0.75, 0.65))
	vbox.add_child(player_card_types)

	# HP bar
	var hp_container = HBoxContainer.new()
	hp_container.add_theme_constant_override("separation", 6)
	vbox.add_child(hp_container)

	var hp_label = Label.new()
	hp_label.text = "HP"
	hp_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
	hp_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.65))
	hp_container.add_child(hp_label)

	player_card_hp_bar = ProgressBar.new()
	player_card_hp_bar.max_value = 100
	player_card_hp_bar.value = 100
	player_card_hp_bar.show_percentage = false
	player_card_hp_bar.custom_minimum_size = Vector2(0, 14)
	player_card_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_container.add_child(player_card_hp_bar)

	player_card_hp_text = Label.new()
	player_card_hp_text.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
	player_card_hp_text.add_theme_color_override("font_color", UITokens.PAPER_CREAM)
	player_card_hp_text.custom_minimum_size.x = 70
	hp_container.add_child(player_card_hp_text)

	# XP bar
	var xp_container = HBoxContainer.new()
	xp_container.add_theme_constant_override("separation", 6)
	vbox.add_child(xp_container)

	var xp_label = Label.new()
	xp_label.text = "XP"
	xp_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
	xp_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.9))
	xp_container.add_child(xp_label)

	player_card_xp_bar = ProgressBar.new()
	player_card_xp_bar.max_value = 100
	player_card_xp_bar.value = 0
	player_card_xp_bar.show_percentage = false
	player_card_xp_bar.custom_minimum_size = Vector2(0, 10)
	player_card_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_card_xp_bar.modulate = Color(0.4, 0.5, 0.9)
	xp_container.add_child(player_card_xp_bar)

	player_card_xp_text = Label.new()
	player_card_xp_text.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
	player_card_xp_text.add_theme_color_override("font_color", Color(0.5, 0.6, 0.9))
	player_card_xp_text.custom_minimum_size.x = 70
	xp_container.add_child(player_card_xp_text)

	player_card_ability = Label.new()
	player_card_ability.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
	player_card_ability.add_theme_color_override("font_color", Color(0.7, 0.65, 0.5))
	vbox.add_child(player_card_ability)

	player_card_item = Label.new()
	player_card_item.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
	player_card_item.add_theme_color_override("font_color", Color(0.5, 0.7, 0.8))
	vbox.add_child(player_card_item)

	player_card_status = Label.new()
	player_card_status.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
	player_card_status.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	player_card_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(player_card_status)

	player_card_locked = Label.new()
	player_card_locked.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
	player_card_locked.add_theme_color_override("font_color", Color(0.9, 0.5, 0.3))
	vbox.add_child(player_card_locked)

# === SETUP (called from game_world.gd) ===

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

# === CAMERA HELPERS ===

func _get_local_player_camera() -> Camera3D:
	var local_peer = multiplayer.get_unique_id()
	var player = get_node_or_null("/root/Main/GameWorld/Players/%d" % local_peer)
	if player:
		return player.get_node_or_null("Camera3D")
	return null

func _enter_arena_camera() -> void:
	_saved_player_camera = _get_local_player_camera()
	if arena and arena.arena_camera:
		arena.arena_camera.current = true

func _restore_player_camera() -> void:
	if _saved_player_camera and is_instance_valid(_saved_player_camera):
		_saved_player_camera.current = true
	_saved_player_camera = null

# === PHASE HELPERS ===

func _set_phase(new_phase: int) -> void:
	_phase = new_phase
	match new_phase:
		BattlePhase.INTRO:
			prompt_label.visible = true
			_show_action_menu(false)
			_show_move_panel(false)
		BattlePhase.PROMPT:
			prompt_label.text = "What will you do?"
			prompt_label.visible = true
			_show_action_menu(true)
			_show_move_panel(false)
			_set_menu_buttons_enabled(true)
		BattlePhase.ACTION_SELECT:
			prompt_label.visible = false
			_show_action_menu(false)
			_show_move_panel(true)
		BattlePhase.ANIMATING:
			prompt_label.visible = false
			_show_action_menu(false)
			_show_move_panel(false)
		BattlePhase.WAITING:
			prompt_label.visible = false
			_show_action_menu(false)
			_show_move_panel(false)
			if waiting_label:
				waiting_label.visible = true
		BattlePhase.ENDED:
			prompt_label.visible = false
			_show_action_menu(false)
			_show_move_panel(false)

func _show_action_menu(show: bool) -> void:
	if action_menu_panel:
		action_menu_panel.visible = show

func _show_move_panel(show: bool) -> void:
	if move_panel:
		move_panel.visible = show

# === BATTLE LIFECYCLE ===

func _on_battle_started() -> void:
	_battle_starting = true
	_initial_setup = true
	_is_animating_log = false
	_buffered_turn_logs.clear()

	# Hide PvP challenge UI if showing
	var pvp_ui = get_node_or_null("/root/Main/GameWorld/UI/PvPChallengeUI")
	if pvp_ui:
		pvp_ui.visible = false

	# Hide trainer prompt
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("hide_trainer_prompt"):
		hud.hide_trainer_prompt()

	# Hide HUD during battle (CanvasLayer hide)
	if hud:
		hud.visible = false

	# Fade to black
	if hud and hud.has_method("play_battle_transition"):
		hud.visible = true  # Temporarily show for transition animation
		await hud.play_battle_transition()
		hud.visible = false

	# Clean up previous arena
	if arena and is_instance_valid(arena):
		arena.queue_free()
		arena = null

	# Clean up leftover panels
	_cleanup_panels()

	# Create 3D arena
	var mode = battle_mgr.client_battle_mode if battle_mgr else 0
	arena = Node3D.new()
	arena.set_script(BattleArenaScript)
	arena.name = "BattleArena"
	var game_world = get_node_or_null("/root/Main/GameWorld")
	if game_world:
		game_world.add_child(arena)
	else:
		add_child(arena)

	var opp_name = battle_mgr.client_opponent_name if battle_mgr else ""
	arena.build_arena(mode, battle_mgr.client_enemy, opp_name)

	# Switch camera
	_enter_arena_camera()

	# Show action panel
	action_layer.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	battle_log.clear()

	# Restore panel visibility
	weather_bar.visible = false
	if waiting_label:
		waiting_label.visible = false
	enemy_card.visible = true
	player_card.visible = true

	# INTRO phase — hide action panel, show intro text
	_set_phase(BattlePhase.INTRO)

	var intro_text = ""
	match mode:
		0: # WILD
			var enemy_name = battle_mgr.client_enemy.get("nickname", "creature")
			intro_text = "A wild %s appeared!" % enemy_name
		1: # TRAINER
			intro_text = "Trainer battle!"
		2: # PVP
			intro_text = "PvP battle!"

	prompt_label.text = intro_text
	battle_log.append_text(intro_text + "\n")

	flee_button.visible = (mode == 0)
	item_button.visible = (mode != 2)

	_refresh_ui()
	_initial_setup = false

	# Clear fade — reveal 3D arena
	if hud and hud.has_method("clear_battle_transition"):
		hud.visible = true
		await hud.clear_battle_transition()
		hud.visible = false

	# Entry animations
	if arena:
		arena.play_creature_entry("enemy")
		await get_tree().create_timer(0.5).timeout
		arena.play_creature_entry("player")
		await get_tree().create_timer(0.5).timeout

	# Transition to PROMPT phase
	_set_phase(BattlePhase.PROMPT)

	# Replay any buffered turn results that arrived during INTRO
	if _buffered_turn_logs.size() > 0:
		var buffered = _buffered_turn_logs.duplicate()
		_buffered_turn_logs.clear()
		for tl in buffered:
			_on_turn_result(tl)
	_battle_starting = false

func _on_battle_ended(victory: bool) -> void:
	# Wait for _on_battle_started to finish its await chain before tearing down
	if _battle_starting:
		while _battle_starting:
			await get_tree().process_frame
		# Re-check arena validity after waiting
		if not is_instance_valid(arena):
			_restore_player_camera()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			var hud2 = get_node_or_null("/root/Main/GameWorld/UI/HUD")
			if hud2:
				hud2.visible = true
			return
	_set_phase(BattlePhase.ENDED)
	_summary_victory = victory
	await get_tree().create_timer(0.5).timeout
	_show_summary_screen()

func _dismiss_summary() -> void:
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("play_battle_transition"):
		hud.visible = true  # Show for transition
		await hud.play_battle_transition()

	# Clean up panels
	_cleanup_panels()
	action_layer.visible = false

	# Destroy arena
	if arena and is_instance_valid(arena):
		arena.queue_free()
		arena = null

	# Restore camera
	_restore_player_camera()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Restore HUD visibility
	if hud:
		hud.visible = true

	if hud and hud.has_method("clear_battle_transition"):
		await hud.clear_battle_transition()

func _cleanup_panels() -> void:
	if summary_panel:
		summary_panel.queue_free()
		summary_panel = null
	if switch_panel:
		switch_panel.queue_free()
		switch_panel = null
	if item_panel:
		item_panel.queue_free()
		item_panel = null
	if move_replace_panel:
		move_replace_panel.queue_free()
		move_replace_panel = null

# === DISPLAY HELPERS (ported from battle_ui.gd) ===

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

# === WEATHER / HAZARDS / STATS ===

func _update_weather_display() -> void:
	if battle_mgr == null:
		return
	var w = battle_mgr.client_weather
	var trick_room = battle_mgr.client_trick_room_turns if battle_mgr else 0
	if w == "" and trick_room <= 0:
		weather_bar.visible = false
		if arena:
			arena.update_weather("")
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
		if arena:
			arena.update_weather(w)
	if trick_room > 0:
		parts.append("Trick Room (%d turns)" % trick_room)
	weather_label.text = " | ".join(parts)

func _on_battle_state_updated() -> void:
	_update_weather_display()
	_refresh_cards()

# === CARD UPDATES ===

func _refresh_cards() -> void:
	_update_enemy_card()
	_update_player_card()

func _update_enemy_card() -> void:
	if battle_mgr == null:
		return
	DataRegistry.ensure_loaded()

	var enemy = battle_mgr.client_enemy
	var mode = battle_mgr.client_battle_mode if battle_mgr else 0
	var enemy_prefix = "Wild " if mode == 0 else ""
	enemy_card_name.text = "%s%s  Lv.%d" % [enemy_prefix, enemy.get("nickname", "???"), enemy.get("level", 1)]

	var species = DataRegistry.get_species(enemy.get("species_id", ""))
	var enemy_types: Array = enemy.get("types", [])
	if enemy_types.is_empty() and species:
		enemy_types = Array(species.types)
	enemy_card_types.text = "Types: %s" % _format_types(enemy_types)

	# Update type-colored left border
	var primary_type = enemy_types[0] if enemy_types.size() > 0 else ""
	_update_card_border(enemy_card, primary_type)

	var ehp = enemy.get("hp", 0)
	var emax = enemy.get("max_hp", 1)
	enemy_card_hp_bar.max_value = emax
	enemy_card_hp_bar.value = ehp
	var pct = float(ehp) / emax if emax > 0 else 0.0
	enemy_card_hp_bar.modulate = _hp_tint_color(pct)
	enemy_card_hp_text.text = "%d/%d" % [ehp, emax]

	# Status
	var es = enemy.get("status", "")
	var enemy_status_parts: Array = []
	var estatus_text = _format_status_with_turns(es, battle_mgr.client_enemy_status_turns)
	if estatus_text != "":
		enemy_status_parts.append(estatus_text)
	if battle_mgr.client_enemy_taunt_turns > 0:
		enemy_status_parts.append("Taunted(%d)" % battle_mgr.client_enemy_taunt_turns)
	if battle_mgr.client_enemy_encore_turns > 0:
		enemy_status_parts.append("Encored(%d)" % battle_mgr.client_enemy_encore_turns)
	if battle_mgr.client_enemy_substitute_hp > 0:
		enemy_status_parts.append("Sub(%d HP)" % battle_mgr.client_enemy_substitute_hp)
	enemy_card_status.text = " | ".join(enemy_status_parts)

	# Hazards
	var eh = battle_mgr.client_enemy_hazards
	enemy_card_hazards.text = "Hazards: %s" % _format_hazards(eh) if eh.size() > 0 else ""

	# Stats
	var e_stats = _format_stat_stages(battle_mgr.client_enemy_stat_stages)
	enemy_card_stats.text = "Stats: %s" % e_stats if e_stats != "" else ""

func _update_player_card() -> void:
	if battle_mgr == null:
		return
	DataRegistry.ensure_loaded()

	var active_idx = battle_mgr.client_active_creature_idx
	if active_idx >= PlayerData.party.size():
		return
	var creature = PlayerData.party[active_idx]

	player_card_name.text = "%s  Lv.%d" % [creature.get("nickname", "???"), creature.get("level", 1)]

	var p_species = DataRegistry.get_species(creature.get("species_id", ""))
	var p_types: Array = creature.get("types", [])
	if p_types.is_empty() and p_species:
		p_types = Array(p_species.types)
	player_card_types.text = "Types: %s" % _format_types(p_types)

	# Update type-colored left border
	var primary_type = p_types[0] if p_types.size() > 0 else ""
	_update_card_border(player_card, primary_type)

	# HP
	var php = creature.get("hp", 0)
	var pmax = creature.get("max_hp", 1)
	player_card_hp_bar.max_value = pmax
	player_card_hp_bar.value = php
	var pct = float(php) / pmax if pmax > 0 else 0.0
	player_card_hp_bar.modulate = _hp_tint_color(pct)
	player_card_hp_text.text = "%d/%d" % [php, pmax]

	# XP
	var xp = creature.get("xp", 0)
	var xp_next = creature.get("xp_to_next", 100)
	player_card_xp_bar.max_value = xp_next
	player_card_xp_bar.value = xp
	player_card_xp_text.text = "%d/%d" % [xp, xp_next]

	# Ability
	var ability_id = creature.get("ability_id", "")
	if ability_id != "":
		var ability = DataRegistry.get_ability(ability_id)
		player_card_ability.text = "Ability: %s" % (ability.display_name if ability else ability_id)
	else:
		player_card_ability.text = ""

	# Held item
	var item_id = creature.get("held_item_id", "")
	if item_id != "":
		var item = DataRegistry.get_held_item(item_id)
		player_card_item.text = "Item: %s" % (item.display_name if item else item_id)
	else:
		player_card_item.text = ""

	# Status
	var ps = creature.get("status", "")
	var player_status_parts: Array = []
	var pstatus_text = _format_status_with_turns(ps, battle_mgr.client_player_status_turns)
	if pstatus_text != "":
		player_status_parts.append(pstatus_text)
	if battle_mgr.client_player_taunt_turns > 0:
		player_status_parts.append("Taunted(%d)" % battle_mgr.client_player_taunt_turns)
	if battle_mgr.client_player_encore_turns > 0:
		player_status_parts.append("Encored(%d)" % battle_mgr.client_player_encore_turns)
	if battle_mgr.client_player_substitute_hp > 0:
		player_status_parts.append("Sub(%d HP)" % battle_mgr.client_player_substitute_hp)
	player_card_status.text = " | ".join(player_status_parts)

	# Choice-locked move
	if battle_mgr.client_player_choice_locked != "":
		var locked_move = DataRegistry.get_move(battle_mgr.client_player_choice_locked)
		var locked_name = locked_move.display_name if locked_move else battle_mgr.client_player_choice_locked
		player_card_locked.text = "Locked: %s" % locked_name
	else:
		player_card_locked.text = ""

	# Hazards (show on player card too)
	var ph = battle_mgr.client_player_hazards
	# (Hazards shown in log, not on player card to keep it clean)

func _update_card_border(card: PanelContainer, type_id: String) -> void:
	var border_color = TYPE_COLORS.get(type_id, Color(0.4, 0.35, 0.25))
	var current_style = card.get_theme_stylebox("panel") as StyleBoxFlat
	if current_style:
		current_style.border_color = border_color
		current_style.border_width_left = 4

func _hp_tint_color(pct: float) -> Color:
	if pct > 0.5:
		return UITokens.STAMP_GREEN
	if pct > 0.25:
		return UITokens.STAMP_GOLD
	return UITokens.STAMP_RED

func _animate_card_hp(side: String, target_hp: int, max_hp: int) -> void:
	var bar: ProgressBar
	var text_label: Label
	if side == "enemy":
		bar = enemy_card_hp_bar
		text_label = enemy_card_hp_text
	else:
		bar = player_card_hp_bar
		text_label = player_card_hp_text
	if bar == null:
		return
	bar.max_value = max_hp
	var pct = float(target_hp) / max_hp if max_hp > 0 else 0.0
	var color = _hp_tint_color(pct)
	var tween = create_tween()
	tween.tween_property(bar, "value", float(target_hp), 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(bar, "modulate", color, 0.25)
	if text_label:
		text_label.text = "%d/%d" % [target_hp, max_hp]

func _animate_card_xp(xp: int, xp_to_next: int) -> void:
	if player_card_xp_bar == null:
		return
	player_card_xp_bar.max_value = xp_to_next
	var tween = create_tween()
	tween.tween_property(player_card_xp_bar, "value", float(xp), 0.8).set_ease(Tween.EASE_OUT)
	if player_card_xp_text:
		player_card_xp_text.text = "%d/%d" % [xp, xp_to_next]

func _animate_card_hp_from_battle_mgr() -> void:
	if battle_mgr == null:
		return
	var enemy = battle_mgr.client_enemy
	_animate_card_hp("enemy", enemy.get("hp", 0), enemy.get("max_hp", 1))
	var aidx = battle_mgr.client_active_creature_idx
	if aidx < PlayerData.party.size():
		var pc = PlayerData.party[aidx]
		_animate_card_hp("player", pc.get("hp", 0), pc.get("max_hp", 1))

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

# === REFRESH UI ===

func _refresh_ui() -> void:
	if battle_mgr == null:
		return
	DataRegistry.ensure_loaded()

	# Update 3D arena creatures
	if arena:
		var enemy = battle_mgr.client_enemy
		arena.update_enemy_creature(enemy)
		var arena_active_idx = battle_mgr.client_active_creature_idx
		if arena_active_idx < PlayerData.party.size():
			arena.update_player_creature(PlayerData.party[arena_active_idx])

	# Move buttons (only visible in ACTION_SELECT phase)
	_refresh_move_buttons()

	_update_weather_display()
	_refresh_cards()

func _refresh_move_buttons() -> void:
	if battle_mgr == null:
		return
	var active_idx = battle_mgr.client_active_creature_idx
	if active_idx >= PlayerData.party.size():
		return
	var creature = PlayerData.party[active_idx]
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
				move_buttons[i].scale = Vector2.ONE
				move_buttons[i].pivot_offset = move_buttons[i].size / 2.0
			else:
				move_buttons[i].visible = false
		else:
			move_buttons[i].visible = false

# === POKEMON-STYLE ACTION MENU HANDLERS ===

func _on_fight_pressed() -> void:
	if battle_mgr == null or not battle_mgr.awaiting_action:
		return
	if _phase != BattlePhase.PROMPT:
		return
	_refresh_move_buttons()
	_set_phase(BattlePhase.ACTION_SELECT)

func _on_move_back_pressed() -> void:
	_set_phase(BattlePhase.PROMPT)

# === MOVE / FLEE / ITEM / SWITCH ACTIONS ===

func _on_move_pressed(idx: int) -> void:
	if battle_mgr == null or not battle_mgr.awaiting_action:
		return
	if _phase != BattlePhase.ACTION_SELECT:
		return
	var active_idx = battle_mgr.client_active_creature_idx
	if active_idx >= PlayerData.party.size():
		return
	var moves = PlayerData.party[active_idx].get("moves", [])
	if idx < moves.size():
		battle_mgr.send_move(moves[idx])
		if battle_mgr.client_battle_mode == 2:
			_set_phase(BattlePhase.WAITING)
		else:
			_set_phase(BattlePhase.ANIMATING)

func _on_flee_pressed() -> void:
	if battle_mgr:
		battle_mgr.send_flee()
		_set_phase(BattlePhase.ANIMATING)

func _on_item_pressed() -> void:
	if battle_mgr == null or not battle_mgr.awaiting_action:
		return
	if _phase != BattlePhase.PROMPT:
		return
	_show_item_panel()

func _on_switch_pressed() -> void:
	if battle_mgr == null or not battle_mgr.awaiting_action:
		return
	if _phase != BattlePhase.PROMPT:
		return
	_show_switch_panel()

# === ITEM PANEL ===

func _show_item_panel() -> void:
	if item_panel:
		item_panel.queue_free()
	item_panel = PanelContainer.new()
	item_panel.anchors_preset = Control.PRESET_CENTER
	item_panel.custom_minimum_size = Vector2(350, 0)
	UITheme.apply_panel(item_panel)
	var vbox = VBoxContainer.new()
	item_panel.add_child(vbox)

	var title = Label.new()
	title.text = "Use Item"
	UITheme.style_subheading(title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	DataRegistry.ensure_loaded()
	var has_items = false
	for item_id in PlayerData.inventory:
		if PlayerData.inventory[item_id] <= 0:
			continue
		var bi = DataRegistry.get_battle_item(item_id)
		if bi == null:
			continue
		has_items = true
		var btn = Button.new()
		btn.text = "%s x%d — %s" % [bi.display_name, PlayerData.inventory[item_id], bi.description]
		btn.custom_minimum_size.y = 32
		UITheme.style_button(btn, "secondary")
		var iid = item_id
		var effect = bi.effect_type
		btn.pressed.connect(func(): _on_item_selected(iid, effect))
		vbox.add_child(btn)

	if not has_items:
		var empty_label = Label.new()
		empty_label.text = "No battle items in inventory."
		UITheme.style_small(empty_label)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(empty_label)

	var cancel = Button.new()
	cancel.text = "Cancel"
	UITheme.style_button(cancel, "danger")
	cancel.pressed.connect(func():
		item_panel.queue_free()
		item_panel = null
	)
	vbox.add_child(cancel)
	action_layer.add_child(item_panel)

func _on_item_selected(item_id: String, effect_type: String) -> void:
	if item_panel:
		item_panel.queue_free()
		item_panel = null
	_show_item_target_panel(item_id, effect_type)

func _show_item_target_panel(item_id: String, effect_type: String) -> void:
	if item_panel:
		item_panel.queue_free()
	item_panel = PanelContainer.new()
	item_panel.anchors_preset = Control.PRESET_CENTER
	item_panel.custom_minimum_size = Vector2(350, 0)
	UITheme.apply_panel(item_panel)
	var vbox = VBoxContainer.new()
	item_panel.add_child(vbox)

	var title = Label.new()
	title.text = "Select Target"
	UITheme.style_subheading(title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	for i in range(PlayerData.party.size()):
		var creature = PlayerData.party[i]
		var hp = int(creature.get("hp", 0))
		var max_hp = int(creature.get("max_hp", 1))
		var is_fainted = hp <= 0
		if effect_type == "revive" and not is_fainted:
			continue
		if effect_type != "revive" and is_fainted:
			continue
		var btn = Button.new()
		btn.text = "%s — HP: %d/%d" % [creature.get("nickname", "???"), hp, max_hp]
		btn.custom_minimum_size.y = 28
		UITheme.style_button(btn, "secondary")
		var cidx = i
		var iid = item_id
		btn.pressed.connect(func():
			if battle_mgr:
				battle_mgr.send_item_use(iid, cidx)
				if battle_mgr.client_battle_mode == 2:
					_set_phase(BattlePhase.WAITING)
				else:
					_set_phase(BattlePhase.ANIMATING)
			if item_panel:
				item_panel.queue_free()
				item_panel = null
		)
		vbox.add_child(btn)

	var cancel = Button.new()
	cancel.text = "Cancel"
	UITheme.style_button(cancel, "danger")
	cancel.pressed.connect(func():
		item_panel.queue_free()
		item_panel = null
	)
	vbox.add_child(cancel)
	action_layer.add_child(item_panel)

# === SWITCH PANEL ===

func _show_switch_panel() -> void:
	if switch_panel:
		switch_panel.queue_free()
	switch_panel = PanelContainer.new()
	switch_panel.anchors_preset = Control.PRESET_CENTER
	switch_panel.custom_minimum_size = Vector2(400, 0)
	UITheme.apply_panel(switch_panel)
	var vbox = VBoxContainer.new()
	switch_panel.add_child(vbox)

	var title = Label.new()
	title.text = "Switch Creature"
	UITheme.style_subheading(title)
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
		UITheme.style_button(btn, "secondary")
		if i == current or hp <= 0:
			btn.disabled = true
		else:
			found_any = true
			var idx = i
			btn.pressed.connect(func():
				battle_mgr.send_switch(idx)
				if battle_mgr.client_battle_mode == 2:
					_set_phase(BattlePhase.WAITING)
				else:
					_set_phase(BattlePhase.ANIMATING)
				switch_panel.queue_free()
				switch_panel = null
			)
		vbox.add_child(btn)

	if not found_any:
		var lbl = Label.new()
		lbl.text = "No other creatures available!"
		UITheme.style_small(lbl)
		vbox.add_child(lbl)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	UITheme.style_button(cancel_btn, "danger")
	cancel_btn.pressed.connect(func():
		switch_panel.queue_free()
		switch_panel = null
	)
	vbox.add_child(cancel_btn)
	action_layer.add_child(switch_panel)

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
	UITheme.apply_panel(move_replace_panel)
	var vbox = VBoxContainer.new()
	move_replace_panel.add_child(vbox)

	var title = Label.new()
	title.text = "Learn %s?" % new_move.display_name
	UITheme.style_subheading(title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var desc = Label.new()
	var power_text = "Pwr:%d" % new_move.power if new_move.power > 0 else "Status"
	desc.text = "%s | %s | %s | Acc:%d%%" % [new_move.type.capitalize(), new_move.category.capitalize(), power_text, new_move.accuracy]
	UITheme.style_small(desc)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(desc)

	var sep = Label.new()
	sep.text = "Replace which move?"
	UITheme.style_body(sep)
	sep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sep)

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
		UITheme.style_button(btn, "secondary")
		var move_idx = i
		var nid = new_move_id
		var cidx = creature_idx
		btn.pressed.connect(func():
			battle_mgr.request_move_replace.rpc_id(1, cidx, move_idx, nid)
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
			battle_log.append_text("[color=#5B8C5A]Replaced with %s![/color]\n" % new_move.display_name)
			move_replace_panel.queue_free()
			move_replace_panel = null
			_refresh_ui()
		)
		vbox.add_child(btn)

	var skip_btn = Button.new()
	skip_btn.text = "Don't learn %s" % new_move.display_name
	UITheme.style_button(skip_btn, "danger")
	skip_btn.pressed.connect(func():
		battle_mgr.skip_move_learn.rpc_id(1)
		battle_log.append_text("Chose not to learn %s.\n" % new_move.display_name)
		move_replace_panel.queue_free()
		move_replace_panel = null
	)
	vbox.add_child(skip_btn)
	action_layer.add_child(move_replace_panel)

# === SUMMARY SCREEN ===

func _show_summary_screen() -> void:
	if summary_panel:
		summary_panel.queue_free()

	summary_panel = PanelContainer.new()
	summary_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	summary_panel.add_theme_stylebox_override("panel", UITheme.make_panel_style(UITokens.PAPER_CREAM, UITokens.STAMP_BROWN, 10, 3))
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
		title.add_theme_color_override("font_color", UITokens.STAMP_GREEN)
	else:
		title.text = "Defeat..."
		title.add_theme_color_override("font_color", UITokens.STAMP_RED)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_heading(title)
	vbox.add_child(title)

	# XP section
	if battle_mgr.summary_xp_results.size() > 0:
		var xp_header = Label.new()
		xp_header.text = "Experience:"
		UITheme.style_body(xp_header)
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
			UITheme.style_small(lbl)
			if r.get("level_ups", []).size() > 0:
				lbl.add_theme_color_override("font_color", UITokens.STAMP_GOLD)
			vbox.add_child(lbl)

	# Evolutions
	if battle_mgr.summary_evolutions.size() > 0:
		for evo in battle_mgr.summary_evolutions:
			var lbl = Label.new()
			var new_species = DataRegistry.get_species(evo.get("new_species_id", ""))
			var evo_name = new_species.display_name if new_species else evo.get("new_species_id", "")
			lbl.text = "  Evolved into %s!" % evo_name
			UITheme.style_small(lbl)
			lbl.add_theme_color_override("font_color", UITokens.TYPE_SWEET)
			vbox.add_child(lbl)

	# New moves
	if battle_mgr.summary_new_moves.size() > 0:
		for nm in battle_mgr.summary_new_moves:
			if nm.get("auto", false):
				var move_def = DataRegistry.get_move(nm.get("move_id", ""))
				var move_name = move_def.display_name if move_def else nm.get("move_id", "???")
				var lbl = Label.new()
				lbl.text = "  Learned %s!" % move_name
				UITheme.style_small(lbl)
				lbl.add_theme_color_override("font_color", UITokens.STAMP_GREEN)
				vbox.add_child(lbl)

	# Drops
	if battle_mgr.summary_drops.size() > 0:
		var drop_header = Label.new()
		drop_header.text = "Items received:"
		UITheme.style_body(drop_header)
		vbox.add_child(drop_header)
		for item_id in battle_mgr.summary_drops:
			var ingredient = DataRegistry.get_ingredient(item_id)
			var item_name = ingredient.display_name if ingredient else item_id
			var lbl = Label.new()
			lbl.text = "  %s x%d" % [item_name, battle_mgr.summary_drops[item_id]]
			UITheme.style_small(lbl)
			vbox.add_child(lbl)

	# Trainer rewards
	if battle_mgr.summary_trainer_money > 0:
		var lbl = Label.new()
		lbl.text = "$%d earned!" % battle_mgr.summary_trainer_money
		UITheme.style_small(lbl)
		lbl.add_theme_color_override("font_color", UITokens.STAMP_GOLD)
		vbox.add_child(lbl)
	if battle_mgr.summary_trainer_ingredients.size() > 0:
		for item_id in battle_mgr.summary_trainer_ingredients:
			var ingredient = DataRegistry.get_ingredient(item_id)
			var item_name = ingredient.display_name if ingredient else item_id
			var lbl = Label.new()
			lbl.text = "  Bonus: %s x%d" % [item_name, battle_mgr.summary_trainer_ingredients[item_id]]
			UITheme.style_small(lbl)
			vbox.add_child(lbl)

	# PvP loss
	if battle_mgr.summary_pvp_loss.size() > 0:
		var pvp_header = Label.new()
		pvp_header.text = "Items lost:"
		UITheme.style_body(pvp_header)
		pvp_header.add_theme_color_override("font_color", UITokens.STAMP_RED)
		vbox.add_child(pvp_header)
		for item_id in battle_mgr.summary_pvp_loss:
			var ingredient = DataRegistry.get_ingredient(item_id)
			var item_name = ingredient.display_name if ingredient else item_id
			var lbl = Label.new()
			lbl.text = "  %s x%d" % [item_name, battle_mgr.summary_pvp_loss[item_id]]
			UITheme.style_small(lbl)
			vbox.add_child(lbl)

	# Defeat penalty
	if battle_mgr.summary_defeat_penalty > 0:
		var lbl = Label.new()
		lbl.text = "Lost $%d. Returned to camp." % battle_mgr.summary_defeat_penalty
		UITheme.style_small(lbl)
		lbl.add_theme_color_override("font_color", UITokens.STAMP_RED)
		vbox.add_child(lbl)

	# Continue button
	var continue_btn = Button.new()
	continue_btn.text = "Continue"
	continue_btn.custom_minimum_size.y = 40
	UITheme.style_button(continue_btn, "primary")
	continue_btn.pressed.connect(_dismiss_summary)
	vbox.add_child(continue_btn)

	action_layer.add_child(summary_panel)

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
		battle_log.append_text("[color=#5B7EA6]Drops: %s[/color]\n" % drop_text.strip_edges())

func _on_trainer_rewards(money: int, ingredients: Dictionary) -> void:
	battle_mgr.summary_trainer_money = money
	battle_mgr.summary_trainer_ingredients = ingredients
	battle_log.append_text("[color=#D4A843]Trainer reward: $%d[/color]\n" % money)
	for item_id in ingredients:
		var ingredient = DataRegistry.get_ingredient(item_id)
		var item_name = ingredient.display_name if ingredient else item_id
		battle_log.append_text("[color=#D4A843]  + %s x%d[/color]\n" % [item_name, ingredients[item_id]])

func _on_pvp_loss(lost_items: Dictionary) -> void:
	battle_mgr.summary_pvp_loss = lost_items
	battle_log.append_text("[color=#C25450]Lost items in PvP defeat![/color]\n")

func _on_defeat_penalty(money_lost: int) -> void:
	battle_mgr.summary_defeat_penalty = money_lost
	if money_lost > 0:
		battle_log.append_text("[color=#C25450]Lost $%d![/color]\n" % money_lost)
	battle_log.append_text("[color=#C25450]Returned to camp.[/color]\n")

# === TURN RESULT + XP ===

func _on_turn_result(turn_log: Array) -> void:
	# Buffer turn results during INTRO phase
	if _phase == BattlePhase.INTRO:
		_buffered_turn_logs.append(turn_log)
		return

	if waiting_label:
		waiting_label.visible = false
	_set_phase(BattlePhase.ANIMATING)
	_is_animating_log = true
	_animate_turn_log(turn_log)

func _animate_turn_log(turn_log: Array) -> void:
	# Hoisted variables to avoid GDScript duplicate-var-in-same-scope errors
	var effect_pos: Vector3
	var actor_side: String

	for entry in turn_log:
		var msg = _format_log_entry(entry)
		var actor = entry.get("actor", "")
		var entry_type = entry.get("type", "move")

		if entry_type == "move":
			# Camera cut to attacker side
			var attacker_preset = "player_attack" if actor == "player" else "enemy_attack"
			if arena:
				arena.cut_camera(attacker_preset)

			# Spawn move-type particle at target
			var move_type = entry.get("move_type", "")
			var target_side = "enemy" if actor == "player" else "player"
			if move_type != "" and not entry.get("missed", false) and arena:
				effect_pos = arena.get_creature_position(target_side)
				BattleEffects.spawn_move_effect(arena, effect_pos, move_type)

			# Log text
			if msg != "":
				battle_log.append_text(msg + "\n")
				await get_tree().create_timer(0.3).timeout

			# Damage dealt — hit effect + damage number + flash + card HP update
			if entry.has("damage") and entry.damage > 0:
				if arena:
					effect_pos = arena.get_creature_position(target_side)
					BattleEffects.spawn_hit_effect(arena, effect_pos, entry.get("effectiveness", ""))
					arena.spawn_damage_number(entry.damage, target_side, entry.get("effectiveness", ""))
					arena.flash_creature(target_side)
					if entry.get("critical", false):
						arena.camera_shake()
				_animate_card_hp_from_battle_mgr()
				await get_tree().create_timer(0.3).timeout

			# Stat change effects
			if entry.has("stat_changes") and arena:
				actor_side = actor if actor in ["player", "enemy"] else "player"
				effect_pos = arena.get_creature_position(actor_side)
				BattleEffects.spawn_stat_effect(arena, effect_pos, _has_any_positive(entry.stat_changes))
			if entry.has("target_stat_changes") and arena:
				effect_pos = arena.get_creature_position(target_side)
				BattleEffects.spawn_stat_effect(arena, effect_pos, _has_any_positive(entry.target_stat_changes))

			# Status applied effect
			if entry.has("status_applied") and arena:
				effect_pos = arena.get_creature_position(target_side)
				BattleEffects.spawn_status_effect(arena, effect_pos, entry.status_applied)

			# Heal effect
			if (entry.has("heal") or entry.has("drain_heal") or entry.has("ability_heal")) and arena:
				actor_side = actor if actor in ["player", "enemy"] else "player"
				effect_pos = arena.get_creature_position(actor_side)
				BattleEffects.spawn_heal_effect(arena, effect_pos)

		elif entry_type in ["status_damage", "hazard_damage"]:
			# Camera to the creature taking damage
			actor_side = actor if actor in ["player", "enemy"] else "player"
			var cam_preset = "enemy_attack" if actor_side == "player" else "player_attack"
			if arena:
				arena.cut_camera(cam_preset)
			if msg != "":
				battle_log.append_text(msg + "\n")
			if entry.has("damage") and entry.damage > 0 and arena:
				effect_pos = arena.get_creature_position(actor_side)
				BattleEffects.spawn_hit_effect(arena, effect_pos, "")
				arena.flash_creature(actor_side)
			_animate_card_hp_from_battle_mgr()
			if msg != "":
				await get_tree().create_timer(0.3).timeout

		elif entry_type in ["ability_heal", "item_heal"]:
			if arena:
				actor_side = actor if actor in ["player", "enemy"] else "player"
				effect_pos = arena.get_creature_position(actor_side)
				BattleEffects.spawn_heal_effect(arena, effect_pos)
			if msg != "":
				battle_log.append_text(msg + "\n")
			_animate_card_hp_from_battle_mgr()
			if msg != "":
				await get_tree().create_timer(0.3).timeout

		elif entry_type in ["switch", "trainer_switch", "forced_switch"]:
			# Swap animation (existing logic)
			if arena and battle_mgr:
				var side = "player" if entry.get("actor", "player") == "player" else "enemy"
				if entry_type == "trainer_switch":
					side = "enemy"
				var creature_data: Dictionary = {}
				if side == "player":
					var aidx = battle_mgr.client_active_creature_idx
					if aidx < PlayerData.party.size():
						creature_data = PlayerData.party[aidx]
				else:
					creature_data = battle_mgr.client_enemy
				if creature_data.size() > 0:
					arena.swap_creature_animation(side, creature_data)
			if msg != "":
				battle_log.append_text(msg + "\n")
				await get_tree().create_timer(0.5).timeout
			_refresh_cards()

		else:
			# All other entry types (weather, taunt, encore, etc.)
			if msg != "":
				battle_log.append_text(msg + "\n")
				await get_tree().create_timer(0.3).timeout

		# Return camera to neutral after each entry
		if arena:
			arena.cut_camera("neutral")

	_is_animating_log = false
	_refresh_ui()
	if battle_mgr and battle_mgr.awaiting_action:
		_set_phase(BattlePhase.PROMPT)

func _has_any_positive(stat_changes: Dictionary) -> bool:
	for key in stat_changes:
		if int(stat_changes[key]) > 0:
			return true
	return false

func _on_xp_result(results: Dictionary) -> void:
	for r in results.get("results", []):
		battle_mgr.summary_xp_results.append(r)
		var xp = r.get("xp_gained", 0)
		if xp > 0:
			battle_log.append_text("[color=#5B7EA6]+%d XP[/color]\n" % xp)
		for lvl in r.get("level_ups", []):
			battle_log.append_text("[color=#D4A843]Level up! Now Lv.%d![/color]\n" % lvl)
		for m in r.get("new_moves", []):
			battle_mgr.summary_new_moves.append(m)
			var move_def = DataRegistry.get_move(m.get("move_id", ""))
			var move_name = move_def.display_name if move_def else m.get("move_id", "???")
			if m.get("auto", false):
				battle_log.append_text("[color=#5B8C5A]Learned %s![/color]\n" % move_name)
			else:
				battle_log.append_text("[color=#D4A843]Wants to learn %s! (Full moveset)[/color]\n" % move_name)
				_show_move_replace_dialog(r.get("creature_idx", 0), m.get("move_id", ""))
		if r.get("evolved", false):
			battle_mgr.summary_evolutions.append({"creature_idx": r.get("creature_idx", 0), "new_species_id": r.get("new_species_id", "")})
			var new_species = DataRegistry.get_species(r.get("new_species_id", ""))
			var evo_name = new_species.display_name if new_species else r.get("new_species_id", "")
			battle_log.append_text("[color=#E8879B]Evolved into %s![/color]\n" % evo_name)

	# Update XP card bar
	var active_idx = battle_mgr.client_active_creature_idx if battle_mgr else 0
	if active_idx < PlayerData.party.size():
		var creature = PlayerData.party[active_idx]
		_animate_card_xp(creature.get("xp", 0), creature.get("xp_to_next", 100))

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
		battle_log.append_text("[color=#D4A843]%s: %s[/color]\n" % [trainer_name, text])

# === LOG FORMATTING (identical to battle_ui.gd) ===

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
				return text + " [color=#9B8B7B]It doesn't affect the target...[/color]"
			if entry.has("damage"):
				text += " Dealt %d damage." % entry.damage
			if entry.get("hit_count", 1) > 1:
				text += " Hit %d times!" % entry.hit_count
			if entry.get("effectiveness") == "super_effective":
				text += " [color=#5B8C5A]Super effective![/color]"
			elif entry.get("effectiveness") == "not_very_effective":
				text += " [color=#D4A843]Not very effective...[/color]"
			elif entry.get("effectiveness") == "immune":
				text += " [color=#9B8B7B]No effect![/color]"
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
				text += " [color=#5B7EA6]Held on with Focus Spatula![/color]"
			if entry.get("bond_endure_triggered", false):
				text += " [color=#D4A843]Toughed it out from the bond with its trainer![/color]"
			if entry.has("life_orb_recoil"):
				text += " Lost %d HP from Flavor Crystal!" % entry.life_orb_recoil
			if entry.get("switch_after", false):
				text += " Dashed back!"
			if entry.get("force_switch_failed", false):
				text += " But it failed!"
			if entry.has("defender_item_trigger"):
				var dmsg = entry.defender_item_trigger.get("message", "")
				if dmsg != "":
					text += " Foe " + dmsg
			if entry.has("attacker_item_trigger"):
				var amsg = entry.attacker_item_trigger.get("message", "")
				if amsg != "":
					text += " " + actor_name + " " + amsg
			if entry.has("ability_messages"):
				for amsg in entry.ability_messages:
					text += "\n  [color=#8B6B4A]%s[/color]" % amsg
			if entry.has("item_messages"):
				for imsg in entry.item_messages:
					text += "\n  [color=#5B7EA6]%s[/color]" % imsg
			return text
		"ability_trigger":
			var actor_name = "Your creature" if entry.get("actor") == "player" else "Enemy"
			return "[color=#8B6B4A]%s's %s[/color]" % [actor_name, entry.get("message", "")]
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
			return "[color=#8B6B4A]Trick Room distorted the dimensions![/color]"
		"trick_room_ended":
			return "[color=#8B6B4A]Trick Room wore off.[/color]"
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
			return "[color=#D4A843]%s's bond cured its %s![/color]" % [actor_name2, entry.get("status", "status")]
		"sleep_talk_move":
			var actor_name2 = "Your creature" if entry.get("actor") == "player" else "Enemy"
			return "%s used a move in its sleep!" % actor_name2
		"item_use":
			var item_name = entry.get("item_name", "Item")
			var creature_name = entry.get("creature_name", "creature")
			var imsg = entry.get("message", "")
			return "[color=#5B7EA6]Used %s on %s! %s[/color]" % [item_name, creature_name, imsg]
		"trainer_switch":
			return "Trainer sent out the next creature!"
		"victory":
			return "[color=#5B8C5A]Victory![/color]"
		"defeat":
			return "[color=#C25450]All your creatures fainted![/color]"
		"fled":
			return "Got away safely!"
		"flee_failed":
			return "Couldn't escape!"
		"fainted":
			return "[color=#C25450]Your creature fainted![/color] Switch to another!"
		"switch":
			return "Switched creature!"
	return ""

func _set_menu_buttons_enabled(enabled: bool) -> void:
	var mode = battle_mgr.client_battle_mode if battle_mgr else 0
	fight_button.disabled = not enabled
	flee_button.disabled = not enabled
	flee_button.visible = (mode == 0)
	switch_button.disabled = not enabled
	item_button.disabled = not enabled
	item_button.visible = (mode != 2)

func _set_buttons_enabled(enabled: bool) -> void:
	# For move buttons specifically
	if not enabled:
		for btn in move_buttons:
			btn.disabled = true
		return
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
		if i < pp.size() and pp[i] <= 0:
			is_disabled = true
		if is_taunted and not is_disabled:
			var move = DataRegistry.get_move(moves[i])
			if move and move.category == "status":
				is_disabled = true
		if choice_locked != "" and moves[i] != choice_locked:
			is_disabled = true
		if encore_turns > 0 and encore_move != "" and moves[i] != encore_move:
			is_disabled = true
		move_buttons[i].disabled = is_disabled
