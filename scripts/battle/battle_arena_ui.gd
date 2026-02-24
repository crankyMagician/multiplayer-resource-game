extends Node

# 3D Battle Arena UI — replaces the old 2D CanvasLayer battle_ui.
# Connects to the same BattleManager signals. Delegates 3D visuals to BattleArena,
# keeps a CanvasLayer child for the 2D action panel (move buttons, log, overlays).
# Pokemon-style: 2D info cards, camera cuts, particle VFX, action menu.

# StatusEffects, FieldEffects available via class_name
const UITokens = preload("res://scripts/ui/ui_tokens.gd")
const BattleArenaScript = preload("res://scripts/battle/battle_arena.gd")
const BattleEffects = preload("res://scripts/battle/battle_effects.gd")
const BattleVFX = preload("res://scripts/battle/battle_vfx.gd")

enum BattlePhase { INTRO, PROMPT, ACTION_SELECT, ANIMATING, WAITING, ENDED }
var _phase: int = BattlePhase.INTRO
var _buffered_turn_logs: Array = []

var battle_mgr: Node = null
var arena: Node3D = null # BattleArena instance
var _saved_player_camera: Camera3D = null

# 2D action panel (CanvasLayer)
var action_layer: CanvasLayer
var battle_log: RichTextLabel
var log_panel: VBoxContainer
var log_content: RichTextLabel
var log_toggle_btn: Button
var _log_expanded: bool = false
var weather_bar: PanelContainer
var weather_label: Label
var prompt_label: Label

# Left panel structure
var left_panel: PanelContainer
var main_vbox: VBoxContainer
var action_menu_section: VBoxContainer
var move_cards_overlay: Control  # Right-side overlay for move cards
var back_button: Button  # Back button shown in left panel during ACTION_SELECT

# Action menu buttons
var action_menu_panel: PanelContainer
var fight_button: Button
var item_button: Button
var switch_button: Button
var flee_button: Button
var move_panel: PanelContainer  # kept for overlay panels referencing it
var move_buttons: Array = []  # Array[Button] — now refers to move card containers
var _move_card_panels: Array = []  # Array[PanelContainer] — the card panels for hover
var action_panel: VBoxContainer  # Legacy reference for phase show/hide

# Enemy card
var enemy_card: PanelContainer
var enemy_card_name: Label
var enemy_card_types: Label
var enemy_card_hp_bar: ProgressBar
var enemy_card_hp_text: Label
var enemy_card_status: Label
var enemy_card_hazards: Label
var enemy_card_stats: Label

# Player card
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

# Screen flash overlay (white flash on crits)
var _flash_overlay: ColorRect = null

# Status effect overlays on creature cards
var enemy_card_status_overlay: ColorRect
var player_card_status_overlay: ColorRect
var _enemy_status_tween: Tween = null
var _player_status_tween: Tween = null

# Enemy card shift tween (clears left panel)
var _enemy_card_tween: Tween = null

# Narration toast system
var _narration_container: VBoxContainer = null
var _active_toasts: Array = []

# Summary data accumulator
var _summary_result: String = ""
var _is_animating_log: bool = false
var _initial_setup: bool = false
var _battle_starting: bool = false  # Guards against battle_ended during _on_battle_started awaits

const TYPE_COLORS = UITokens.TYPE_COLORS

const WEATHER_NAMES = {
	"spicy": "Sizzle Sun",
	"sweet": "Sugar Hail",
	"sour": "Acid Rain",
	"herbal": "Herb Breeze",
	"umami": "Umami Fog",
	"grain": "Grain Dust",
	"mineral": "Crystal Storm",
	"earthy": "Mudslide",
	"liquid": "Downpour",
	"aromatic": "Fragrant Mist",
	"toxic": "Miasma",
	"protein": "Iron Wind",
	"tropical": "Monsoon Heat",
	"dairy": "Cream Fog",
	"bitter": "Dark Drizzle",
	"spoiled": "Rot Cloud",
	"fermented": "Yeast Storm",
	"smoked": "Smoke Screen",
}

const STATUS_MAX_TURNS = {
	"burned": 5,
	"frozen": 5,
	"drowsy": 4,
	"wilted": 3,
	"soured": 3,
	"poisoned": 0,
	"brined": 4,
	"fermented": 3,
	"stuffed": 3,
	"spiced": 3,
	"chilled": 4,
}

const STATUS_COLORS = {
	"burned": Color(0.9, 0.4, 0.1),
	"frozen": Color(0.3, 0.7, 1.0),
	"poisoned": Color(0.6, 0.2, 0.8),
	"drowsy": Color(0.7, 0.6, 0.9),
	"wilted": Color(0.5, 0.6, 0.3),
	"soured": Color(0.8, 0.8, 0.2),
	"brined": Color(0.2, 0.8, 0.8),
	"fermented": Color(0.6, 0.4, 0.7),
	"stuffed": Color(0.7, 0.55, 0.3),
	"spiced": Color(0.95, 0.4, 0.15),
	"chilled": Color(0.5, 0.7, 0.9),
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

	# Floating creature cards (direct children of action_layer, over arena)
	_build_enemy_card()
	_build_player_card()

	# Left-side vertical panel (20% of screen width, full height)
	left_panel = PanelContainer.new()
	left_panel.name = "LeftPanel"
	left_panel.anchor_left = 0.0
	left_panel.anchor_top = 0.0
	left_panel.anchor_right = 0.20
	left_panel.anchor_bottom = 1.0
	left_panel.offset_left = 0
	left_panel.offset_top = 0
	left_panel.offset_right = 0
	left_panel.offset_bottom = 0
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.15, 0.12, 0.1, 0.92)
	panel_style.border_color = Color(0.4, 0.35, 0.25)
	panel_style.border_width_right = 2
	panel_style.set_corner_radius_all(0)
	panel_style.set_content_margin_all(0)
	left_panel.add_theme_stylebox_override("panel", panel_style)
	action_layer.add_child(left_panel)

	var scroll = ScrollContainer.new()
	scroll.name = "ScrollContainer"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	left_panel.add_child(scroll)

	main_vbox = VBoxContainer.new()
	main_vbox.name = "MainVBox"
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_theme_constant_override("separation", 6)
	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	scroll.add_child(margin)
	margin.add_child(main_vbox)

	# Weather section (inside left panel)
	_build_weather_section()

	# Prompt label (inside panel)
	prompt_label = Label.new()
	prompt_label.name = "PromptLabel"
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	prompt_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_H3))
	prompt_label.add_theme_color_override("font_color", UITokens.PAPER_CREAM)
	prompt_label.visible = false
	main_vbox.add_child(prompt_label)

	# Action menu section (FIGHT / ITEM / SWITCH / FLEE — vertical stack)
	action_menu_section = VBoxContainer.new()
	action_menu_section.name = "ActionMenuSection"
	main_vbox.add_child(action_menu_section)
	_build_action_menu()

	# Back button (shown during ACTION_SELECT, hidden otherwise)
	back_button = Button.new()
	back_button.name = "BackButton"
	back_button.text = "< Back"
	back_button.custom_minimum_size.y = 36
	back_button.visible = false
	UITheme.style_button(back_button, "danger")
	back_button.pressed.connect(_on_move_back_pressed)
	main_vbox.add_child(back_button)

	var sep3 = HSeparator.new()
	sep3.add_theme_constant_override("separation", 4)
	main_vbox.add_child(sep3)

	# Battle log section (collapsible)
	_build_log_section()

	# Right-side move cards overlay (fills area right of left panel)
	_build_move_cards_overlay()

	# Waiting label (PvP) — floating overlay, not in panel
	waiting_label = Label.new()
	waiting_label.text = "Waiting for opponent..."
	UITheme.style_toast(waiting_label)
	waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	waiting_label.anchors_preset = Control.PRESET_CENTER
	waiting_label.visible = false
	action_layer.add_child(waiting_label)

	# Screen flash overlay (covers full screen, starts invisible)
	_flash_overlay = ColorRect.new()
	_flash_overlay.name = "FlashOverlay"
	_flash_overlay.color = Color(1, 1, 1, 0)
	_flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	action_layer.add_child(_flash_overlay)

	# Narration toast container (center-top, over arena)
	_narration_container = VBoxContainer.new()
	_narration_container.name = "NarrationContainer"
	_narration_container.anchor_left = 0.20
	_narration_container.anchor_top = 0.02
	_narration_container.anchor_right = 0.80
	_narration_container.anchor_bottom = 0.45
	_narration_container.offset_left = 0
	_narration_container.offset_top = 0
	_narration_container.offset_right = 0
	_narration_container.offset_bottom = 0
	_narration_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_narration_container.add_theme_constant_override("separation", 4)
	_narration_container.alignment = BoxContainer.ALIGNMENT_BEGIN
	action_layer.add_child(_narration_container)

	# Legacy action_panel reference
	action_panel = VBoxContainer.new()
	action_panel.visible = false

	# Legacy move_panel reference (overlay panels check this)
	move_panel = PanelContainer.new()
	move_panel.visible = false

func _build_weather_section() -> void:
	weather_bar = PanelContainer.new()
	weather_bar.name = "WeatherBar"
	weather_bar.visible = false
	weather_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_panel(weather_bar)
	main_vbox.add_child(weather_bar)

	weather_label = Label.new()
	weather_label.name = "WeatherLabel"
	weather_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	weather_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	UITheme.style_small(weather_label)
	weather_bar.add_child(weather_label)

func _build_action_menu() -> void:
	action_menu_panel = PanelContainer.new()
	action_menu_panel.name = "ActionMenu"
	action_menu_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.15, 0.12, 0.9)
	style.border_color = Color(0.5, 0.42, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	action_menu_panel.add_theme_stylebox_override("panel", style)
	action_menu_section.add_child(action_menu_panel)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	action_menu_panel.add_child(vbox)

	fight_button = Button.new()
	fight_button.name = "FightButton"
	fight_button.text = "FIGHT"
	fight_button.custom_minimum_size = Vector2(0, 44)
	fight_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(fight_button, "primary")
	fight_button.pressed.connect(_on_fight_pressed)
	vbox.add_child(fight_button)

	item_button = Button.new()
	item_button.name = "ItemButton"
	item_button.text = "ITEM"
	item_button.custom_minimum_size = Vector2(0, 44)
	item_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(item_button, "info")
	item_button.pressed.connect(_on_item_pressed)
	vbox.add_child(item_button)

	switch_button = Button.new()
	switch_button.name = "SwitchButton"
	switch_button.text = "SWITCH"
	switch_button.custom_minimum_size = Vector2(0, 44)
	switch_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(switch_button, "secondary")
	switch_button.pressed.connect(_on_switch_pressed)
	vbox.add_child(switch_button)

	flee_button = Button.new()
	flee_button.name = "FleeButton"
	flee_button.text = "FLEE"
	flee_button.custom_minimum_size = Vector2(0, 44)
	flee_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(flee_button, "danger")
	flee_button.pressed.connect(_on_flee_pressed)
	vbox.add_child(flee_button)

func _build_move_cards_overlay() -> void:
	move_cards_overlay = Control.new()
	move_cards_overlay.name = "MoveCardsOverlay"
	move_cards_overlay.anchor_left = 0.22
	move_cards_overlay.anchor_top = 0.15
	move_cards_overlay.anchor_right = 0.98
	move_cards_overlay.anchor_bottom = 0.85
	move_cards_overlay.offset_left = 0
	move_cards_overlay.offset_top = 0
	move_cards_overlay.offset_right = 0
	move_cards_overlay.offset_bottom = 0
	move_cards_overlay.visible = false
	action_layer.add_child(move_cards_overlay)

	var grid = GridContainer.new()
	grid.name = "MoveGrid"
	grid.columns = 2
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	move_cards_overlay.add_child(grid)

	move_buttons.clear()
	_move_card_panels.clear()

	for i in range(4):
		var card = PanelContainer.new()
		card.name = "MoveCard%d" % (i + 1)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var card_style = StyleBoxFlat.new()
		card_style.bg_color = Color(0.18, 0.15, 0.12, 0.95)
		card_style.border_color = Color(0.5, 0.42, 0.3)
		card_style.set_border_width_all(1)
		card_style.border_width_left = 4
		card_style.set_corner_radius_all(6)
		card_style.set_content_margin_all(8)
		card.add_theme_stylebox_override("panel", card_style)
		_move_card_panels.append(card)

		var card_vbox = VBoxContainer.new()
		card_vbox.add_theme_constant_override("separation", 2)
		card.add_child(card_vbox)

		# Header row: move name + effectiveness badge
		var header = HBoxContainer.new()
		header.name = "Header"
		header.add_theme_constant_override("separation", 6)
		card_vbox.add_child(header)

		var name_label = Label.new()
		name_label.name = "MoveName"
		name_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_BODY))
		name_label.add_theme_color_override("font_color", UITokens.PAPER_CREAM)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(name_label)

		var eff_badge = Label.new()
		eff_badge.name = "EffBadge"
		eff_badge.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
		eff_badge.visible = false
		header.add_child(eff_badge)

		# Info line: Type | Category | Pwr:X | Acc:X%
		var info_label = Label.new()
		info_label.name = "InfoLine"
		info_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_SMALL))
		info_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.65))
		card_vbox.add_child(info_label)

		# PP line
		var pp_label = Label.new()
		pp_label.name = "PPLine"
		pp_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_SMALL))
		pp_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
		card_vbox.add_child(pp_label)

		# Description
		var desc_label = Label.new()
		desc_label.name = "Description"
		desc_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_SMALL))
		desc_label.add_theme_color_override("font_color", Color(0.65, 0.6, 0.5))
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		card_vbox.add_child(desc_label)

		# Effect tags container
		var tags_flow = HFlowContainer.new()
		tags_flow.name = "EffectTags"
		tags_flow.add_theme_constant_override("h_separation", 4)
		tags_flow.add_theme_constant_override("v_separation", 2)
		card_vbox.add_child(tags_flow)

		# Invisible click button overlaying the card
		var click_btn = _make_invisible_overlay_btn()
		click_btn.name = "ClickBtn"
		card.add_child(click_btn)

		var idx = i
		click_btn.pressed.connect(func(): _on_move_pressed(idx))
		click_btn.mouse_entered.connect(func(): _on_move_hover(idx, true))
		click_btn.mouse_exited.connect(func(): _on_move_hover(idx, false))
		move_buttons.append(click_btn)

		grid.add_child(card)

func _build_enemy_card() -> void:
	enemy_card = PanelContainer.new()
	enemy_card.name = "EnemyCard"
	# Floating overlay: top-left over arena
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
	style.border_width_left = 4
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
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

	var hp_container = HBoxContainer.new()
	hp_container.add_theme_constant_override("separation", 6)
	vbox.add_child(hp_container)

	enemy_card_hp_bar = ProgressBar.new()
	enemy_card_hp_bar.max_value = 100
	enemy_card_hp_bar.value = 100
	enemy_card_hp_bar.show_percentage = false
	enemy_card_hp_bar.custom_minimum_size = Vector2(0, 14)
	enemy_card_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_hp_bar(enemy_card_hp_bar)
	hp_container.add_child(enemy_card_hp_bar)

	enemy_card_hp_text = Label.new()
	enemy_card_hp_text.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
	enemy_card_hp_text.add_theme_color_override("font_color", UITokens.PAPER_CREAM)
	enemy_card_hp_text.custom_minimum_size.x = 60
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

	# Status effect overlay (covers card, hidden by default)
	enemy_card_status_overlay = ColorRect.new()
	enemy_card_status_overlay.name = "StatusOverlay"
	enemy_card_status_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	enemy_card_status_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy_card_status_overlay.color = Color(0, 0, 0, 0)
	enemy_card_status_overlay.visible = false
	enemy_card.add_child(enemy_card_status_overlay)

func _build_player_card() -> void:
	player_card = PanelContainer.new()
	player_card.name = "PlayerCard"
	# Floating overlay: right side over arena
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
	style.border_width_left = 4
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
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
	_style_hp_bar(player_card_hp_bar)
	hp_container.add_child(player_card_hp_bar)

	player_card_hp_text = Label.new()
	player_card_hp_text.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
	player_card_hp_text.add_theme_color_override("font_color", UITokens.PAPER_CREAM)
	player_card_hp_text.custom_minimum_size.x = 60
	hp_container.add_child(player_card_hp_text)

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
	player_card_xp_text.custom_minimum_size.x = 60
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

	# Status effect overlay (covers card, hidden by default)
	player_card_status_overlay = ColorRect.new()
	player_card_status_overlay.name = "StatusOverlay"
	player_card_status_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player_card_status_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_card_status_overlay.color = Color(0, 0, 0, 0)
	player_card_status_overlay.visible = false
	player_card.add_child(player_card_status_overlay)

func _build_log_section() -> void:
	log_panel = VBoxContainer.new()
	log_panel.name = "LogSection"
	log_panel.add_theme_constant_override("separation", 2)
	main_vbox.add_child(log_panel)

	log_toggle_btn = Button.new()
	log_toggle_btn.text = "Log v"
	log_toggle_btn.custom_minimum_size.y = 24
	UITheme.style_button(log_toggle_btn, "secondary")
	log_toggle_btn.pressed.connect(_toggle_log)
	log_panel.add_child(log_toggle_btn)

	battle_log = RichTextLabel.new()
	battle_log.name = "BattleLog"
	battle_log.bbcode_enabled = true
	battle_log.scroll_following = true
	battle_log.add_theme_color_override("default_color", UITokens.PAPER_CREAM)
	battle_log.custom_minimum_size = Vector2(0, 60)
	battle_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battle_log.add_theme_font_size_override("normal_font_size", UITheme.scaled(UITokens.FONT_TINY))
	log_panel.add_child(battle_log)

func _toggle_log() -> void:
	_log_expanded = not _log_expanded
	if _log_expanded:
		battle_log.custom_minimum_size.y = 200
		log_toggle_btn.text = "Log ^"
	else:
		battle_log.custom_minimum_size.y = 60
		log_toggle_btn.text = "Log v"

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
	if not PlayerData.inventory_changed.is_connected(_on_player_inventory_changed):
		PlayerData.inventory_changed.connect(_on_player_inventory_changed)

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
			left_panel.visible = false
			_show_move_cards(false)
			prompt_label.visible = false
			_show_action_menu(false)
			back_button.visible = false
			_tween_enemy_card_position(false)
		BattlePhase.PROMPT:
			left_panel.visible = true
			prompt_label.text = "What will you do?"
			prompt_label.visible = true
			_show_action_menu(true)
			back_button.visible = false
			_show_move_cards(false)
			_set_menu_buttons_enabled(true)
			_tween_enemy_card_position(true)
		BattlePhase.ACTION_SELECT:
			left_panel.visible = true
			prompt_label.visible = false
			_show_action_menu(false)
			back_button.visible = true
			_show_move_cards(true)
			_tween_enemy_card_position(true)
		BattlePhase.ANIMATING:
			left_panel.visible = false
			_show_move_cards(false)
			prompt_label.visible = false
			_show_action_menu(false)
			back_button.visible = false
			_tween_enemy_card_position(false)
		BattlePhase.WAITING:
			left_panel.visible = false
			_show_move_cards(false)
			prompt_label.visible = false
			_show_action_menu(false)
			back_button.visible = false
			if waiting_label:
				waiting_label.visible = true
			_tween_enemy_card_position(false)
		BattlePhase.ENDED:
			left_panel.visible = false
			_show_move_cards(false)
			prompt_label.visible = false
			_show_action_menu(false)
			back_button.visible = false
			_tween_enemy_card_position(false)

func _show_action_menu(show: bool) -> void:
	if action_menu_section:
		action_menu_section.visible = show

func _show_move_cards(show: bool) -> void:
	if move_cards_overlay:
		move_cards_overlay.visible = show

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

	# Hide other game world UI elements during battle
	var compass = get_node_or_null("/root/Main/GameWorld/UI/CompassUI")
	if compass:
		compass.visible = false
	var excursion_hud = get_node_or_null("/root/Main/GameWorld/UI/ExcursionHUD")
	if excursion_hud:
		excursion_hud.visible = false

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
	_clear_all_toasts()

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
	var theme = battle_mgr.client_arena_theme if battle_mgr else "docks"
	arena.build_arena(mode, battle_mgr.client_enemy, opp_name, theme)

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

	# Battle music — boss for trainer/PvP, regular for wild
	if mode == 0:
		AudioManager.play_music("battle")
	else:
		AudioManager.play_music("boss")
	AudioManager.stop_all_ambience()

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

func _on_battle_ended(result: String) -> void:
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
			_restore_game_world_ui()
			return
	_set_phase(BattlePhase.ENDED)
	_summary_result = result
	# Victory/defeat/fled music
	if result == "victory":
		AudioManager.play_music("victory")
	elif result == "fled":
		AudioManager.play_music("overworld")
	else:
		AudioManager.play_music("defeat")
	await get_tree().create_timer(0.5).timeout
	_show_summary_screen()

func _dismiss_summary() -> void:
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("play_battle_transition"):
		hud.visible = true  # Show for transition
		await hud.play_battle_transition()

	# Clean up panels
	_cleanup_panels()
	_clear_all_toasts()
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

	# Restore other game world UI elements
	_restore_game_world_ui()

	# Restore overworld music + ambience
	AudioManager.restore_previous_music()
	AudioManager.play_ambience(0, "overworld")

	if hud and hud.has_method("clear_battle_transition"):
		await hud.clear_battle_transition()

func _cleanup_panels() -> void:
	if summary_panel:
		if summary_panel.get_parent():
			summary_panel.get_parent().remove_child(summary_panel)
		summary_panel.queue_free()
		summary_panel = null
	if is_instance_valid(switch_panel):
		if switch_panel.get_parent():
			switch_panel.get_parent().remove_child(switch_panel)
		switch_panel.queue_free()
		switch_panel = null
	if is_instance_valid(item_panel):
		if item_panel.get_parent():
			item_panel.get_parent().remove_child(item_panel)
		item_panel.queue_free()
		item_panel = null
	if move_replace_panel:
		if move_replace_panel.get_parent():
			move_replace_panel.get_parent().remove_child(move_replace_panel)
		move_replace_panel.queue_free()
		move_replace_panel = null

func _restore_game_world_ui() -> void:
	var compass = get_node_or_null("/root/Main/GameWorld/UI/CompassUI")
	if compass:
		compass.visible = true
	var excursion_hud = get_node_or_null("/root/Main/GameWorld/UI/ExcursionHUD")
	if excursion_hud:
		excursion_hud.visible = true

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
	_set_hp_bar_color(enemy_card_hp_bar, _hp_tint_color(pct))
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
	var enemy_status_color = STATUS_COLORS.get(es, Color(1.0, 0.8, 0.3))
	enemy_card_status.add_theme_color_override("font_color", enemy_status_color)
	_update_card_status_effect(enemy_card, enemy_card_status_overlay, es, true)

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
	if active_idx < 0 or active_idx >= PlayerData.party.size():
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
	_set_hp_bar_color(player_card_hp_bar, _hp_tint_color(pct))
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
	var player_status_color = STATUS_COLORS.get(ps, Color(1.0, 0.8, 0.3))
	player_card_status.add_theme_color_override("font_color", player_status_color)
	_update_card_status_effect(player_card, player_card_status_overlay, ps, false)

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
		return Color(0.3, 0.8, 0.3)   # bright green
	if pct > 0.25:
		return Color(0.95, 0.75, 0.1)  # bright amber/yellow
	return Color(0.9, 0.2, 0.2)        # bright red

func _style_hp_bar(bar: ProgressBar) -> void:
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.15, 0.12, 0.1, 0.8)
	bg_style.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg_style)
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = Color(0.3, 0.8, 0.3)
	fill_style.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill_style)

func _set_hp_bar_color(bar: ProgressBar, color: Color) -> void:
	var fill = bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill:
		fill.bg_color = color

func _update_card_status_effect(card: PanelContainer, overlay: ColorRect, status: String, is_enemy: bool) -> void:
	# Kill existing pulse tween
	var tween_ref: Tween = _enemy_status_tween if is_enemy else _player_status_tween
	if tween_ref and tween_ref.is_valid():
		tween_ref.kill()
	if is_enemy:
		_enemy_status_tween = null
	else:
		_player_status_tween = null

	if status == "" or not STATUS_COLORS.has(status):
		# No status — hide overlay, restore type border
		overlay.visible = false
		# Border will be restored by _update_card_border called earlier in the update func
		return

	var status_color = STATUS_COLORS[status]

	# Tint card border to status color
	var current_style = card.get_theme_stylebox("panel") as StyleBoxFlat
	if current_style:
		current_style.border_color = status_color

	# Show colored overlay
	overlay.visible = true
	overlay.color = Color(status_color.r, status_color.g, status_color.b, 0.15)

	# Pulse animation on overlay alpha
	var pulse = create_tween()
	pulse.set_loops()
	pulse.tween_property(overlay, "color:a", 0.08, 0.8).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(overlay, "color:a", 0.20, 0.8).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	if is_enemy:
		_enemy_status_tween = pulse
	else:
		_player_status_tween = pulse

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
	var target_color = _hp_tint_color(pct)
	var tween = create_tween()
	tween.tween_property(bar, "value", float(target_hp), 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_method(func(c: Color): _set_hp_bar_color(bar, c), _hp_tint_color(float(bar.value) / max_hp if max_hp > 0 else 0.0), target_color, 0.25)
	if text_label:
		text_label.text = "%d/%d" % [target_hp, max_hp]

func _animate_card_xp(xp: int, xp_to_next: int, leveled_up: bool = false) -> void:
	if player_card_xp_bar == null:
		return
	if leveled_up:
		# Fill to max, flash, reset to 0, then fill to new XP
		var tween = create_tween()
		tween.tween_property(player_card_xp_bar, "value", float(player_card_xp_bar.max_value), 0.4).set_ease(Tween.EASE_OUT)
		tween.tween_callback(func():
			# Flash gold
			player_card_xp_bar.modulate = Color(1.0, 0.85, 0.2)
		)
		tween.tween_interval(0.2)
		tween.tween_callback(func():
			player_card_xp_bar.max_value = xp_to_next
			player_card_xp_bar.value = 0
			player_card_xp_bar.modulate = Color(0.4, 0.5, 0.9)
		)
		tween.tween_property(player_card_xp_bar, "value", float(xp), 0.6).set_ease(Tween.EASE_OUT)
	else:
		player_card_xp_bar.max_value = xp_to_next
		var tween = create_tween()
		tween.tween_property(player_card_xp_bar, "value", float(xp), 0.8).set_ease(Tween.EASE_OUT)
	if player_card_xp_text:
		player_card_xp_text.text = "%d/%d" % [xp, xp_to_next]

func _flash_screen(color: Color = Color(1, 1, 1, 0.6), duration: float = 0.1) -> void:
	if _flash_overlay == null:
		return
	_flash_overlay.color = color
	var tween = create_tween()
	tween.tween_property(_flash_overlay, "color:a", 0.0, duration).set_ease(Tween.EASE_OUT)

func _shake_hp_bar(side: String) -> void:
	var bar: ProgressBar
	if side == "enemy":
		bar = enemy_card_hp_bar
	else:
		bar = player_card_hp_bar
	if bar == null:
		return
	var original_x = bar.position.x
	var tween = create_tween()
	for i in range(3):
		var offset = 2.0 if i % 2 == 0 else -2.0
		tween.tween_property(bar, "position:x", original_x + offset, 0.025)
	tween.tween_property(bar, "position:x", original_x, 0.025)

func _juice_button(btn: Button) -> void:
	btn.pivot_offset = btn.size / 2.0
	var tween = create_tween()
	tween.tween_property(btn, "scale", Vector2(1.15, 1.15), 0.07).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(btn, "scale", Vector2.ONE, 0.08).set_ease(Tween.EASE_OUT)

func _juice_card(card: PanelContainer) -> void:
	var card_style = card.get_theme_stylebox("panel") as StyleBoxFlat
	if card_style == null:
		return
	var orig_bg = card_style.bg_color
	card_style.bg_color = Color(0.35, 0.3, 0.22, 0.95)
	var tween = create_tween()
	tween.tween_callback(func(): card_style.bg_color = orig_bg).set_delay(0.1)

func _animate_card_hp_from_battle_mgr() -> void:
	if battle_mgr == null:
		return
	var enemy = battle_mgr.client_enemy
	_animate_card_hp("enemy", enemy.get("hp", 0), enemy.get("max_hp", 1))
	var aidx = battle_mgr.client_active_creature_idx
	if aidx >= 0 and aidx < PlayerData.party.size():
		var pc = PlayerData.party[aidx]
		_animate_card_hp("player", pc.get("hp", 0), pc.get("max_hp", 1))

# === MOVE BUTTON HOVER ===

func _on_move_hover(idx: int, hovering: bool) -> void:
	if idx >= _move_card_panels.size():
		return
	var card = _move_card_panels[idx]
	var card_style = card.get_theme_stylebox("panel") as StyleBoxFlat
	if card_style == null:
		return
	if hovering:
		card_style.bg_color = Color(0.24, 0.2, 0.16, 0.95)
		card_style.set_border_width_all(2)
		card_style.border_width_left = 4
	else:
		card_style.bg_color = Color(0.18, 0.15, 0.12, 0.95)
		card_style.set_border_width_all(1)
		card_style.border_width_left = 4

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
		if arena_active_idx >= 0 and arena_active_idx < PlayerData.party.size():
			arena.update_player_creature(PlayerData.party[arena_active_idx])

	# Move buttons (only visible in ACTION_SELECT phase)
	_refresh_move_buttons()

	_update_weather_display()
	_refresh_cards()
	if _phase == BattlePhase.PROMPT:
		_set_menu_buttons_enabled(true)

func _refresh_move_buttons() -> void:
	_refresh_move_cards()

func _refresh_move_cards() -> void:
	if battle_mgr == null:
		return
	var active_idx = battle_mgr.client_active_creature_idx
	if active_idx < 0 or active_idx >= PlayerData.party.size():
		return
	var creature = PlayerData.party[active_idx]
	var moves = creature.get("moves", [])
	var pp_arr = creature.get("pp", [])

	# Get enemy types for effectiveness calculation
	var enemy = battle_mgr.client_enemy
	var enemy_types: Array = enemy.get("types", [])
	if enemy_types.is_empty():
		var species = DataRegistry.get_species(enemy.get("species_id", ""))
		if species:
			enemy_types = Array(species.types)

	for i in range(4):
		var card = _move_card_panels[i] if i < _move_card_panels.size() else null
		if card == null:
			continue
		if i < moves.size():
			var move = DataRegistry.get_move(moves[i])
			if move == null:
				card.visible = false
				continue
			card.visible = true
			var pp_current = pp_arr[i] if i < pp_arr.size() else 0
			var pp_max = move.pp

			# Update card border color to match move type
			var type_color = TYPE_COLORS.get(move.type, Color(0.5, 0.42, 0.3))
			var card_style = card.get_theme_stylebox("panel") as StyleBoxFlat
			if card_style:
				card_style.border_color = type_color.lerp(Color(0.3, 0.25, 0.2), 0.3)

			var card_vbox = card.get_child(0) as VBoxContainer
			if card_vbox == null:
				continue

			# Header: name + effectiveness badge
			var header = card_vbox.get_node("Header") as HBoxContainer
			var name_label = header.get_node("MoveName") as Label
			name_label.text = move.display_name

			var eff_badge = header.get_node("EffBadge") as Label
			if enemy_types.size() > 0 and move.type != "":
				var eff = BattleCalculator.get_type_effectiveness(move.type, enemy_types)
				var eff_text = BattleCalculator.get_effectiveness_text(eff)
				match eff_text:
					"super_effective":
						eff_badge.text = "SUPER EFF."
						eff_badge.add_theme_color_override("font_color", UITokens.STAMP_GREEN)
						eff_badge.visible = true
					"not_very_effective":
						eff_badge.text = "NOT EFF."
						eff_badge.add_theme_color_override("font_color", UITokens.STAMP_GOLD)
						eff_badge.visible = true
					"immune":
						eff_badge.text = "NO EFFECT"
						eff_badge.add_theme_color_override("font_color", UITokens.STAMP_RED)
						eff_badge.visible = true
					_:
						eff_badge.visible = false
			else:
				eff_badge.visible = false

			# Info line
			var info_label = card_vbox.get_node("InfoLine") as Label
			var info_parts: Array = []
			if move.type != "":
				info_parts.append(move.type.capitalize())
			if move.category == "status":
				info_parts.append("STATUS")
			else:
				info_parts.append("Phys" if move.category == "physical" else "Spec")
				if move.power > 0:
					info_parts.append("Pwr:%d" % move.power)
			if move.accuracy > 0:
				info_parts.append("Acc:%d%%" % move.accuracy)
			info_label.text = " | ".join(info_parts)

			# PP line
			var pp_label = card_vbox.get_node("PPLine") as Label
			pp_label.text = "%d/%d PP" % [pp_current, pp_max]
			if pp_current <= 0:
				pp_label.add_theme_color_override("font_color", UITokens.STAMP_RED)
			else:
				pp_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))

			# Description
			var desc_label = card_vbox.get_node("Description") as Label
			if move.description != "":
				desc_label.text = move.description
				desc_label.visible = true
			else:
				desc_label.visible = false

			# Effect tags
			var tags_flow = card_vbox.get_node("EffectTags") as HFlowContainer
			_build_effect_tags(tags_flow, move)

			# Disabled state for click button
			var click_btn = card.get_node("ClickBtn") as Button
			click_btn.disabled = (pp_current <= 0)
			card.modulate = Color(0.5, 0.5, 0.5) if pp_current <= 0 else Color.WHITE
		else:
			card.visible = false

func _build_effect_tags(container: HFlowContainer, move: Resource) -> void:
	# Clear existing tags
	for child in container.get_children():
		child.queue_free()

	var tags: Array = []

	if move.status_effect != "" and move.status_chance > 0:
		tags.append({"text": "%s %d%%" % [move.status_effect.capitalize(), move.status_chance], "color": Color(0.9, 0.6, 0.2)})
	if move.heal_percent > 0:
		tags.append({"text": "Heals %d%%" % int(move.heal_percent * 100), "color": UITokens.STAMP_GREEN})
	if move.drain_percent > 0:
		tags.append({"text": "Drains %d%%" % int(move.drain_percent * 100), "color": Color(0.4, 0.8, 0.5)})
	if move.recoil_percent > 0:
		tags.append({"text": "Recoil %d%%" % int(move.recoil_percent * 100), "color": UITokens.STAMP_RED})
	if move.is_contact:
		tags.append({"text": "Contact", "color": Color(0.7, 0.65, 0.55)})
	if move.is_protection:
		tags.append({"text": "Protect", "color": Color(0.4, 0.6, 0.9)})
	if move.priority != 0:
		tags.append({"text": "Priority %+d" % move.priority, "color": Color(0.8, 0.7, 0.4)})
	if move.switch_after:
		tags.append({"text": "U-Turn", "color": Color(0.5, 0.8, 0.6)})
	if move.force_switch:
		tags.append({"text": "Forces Switch", "color": Color(0.8, 0.5, 0.4)})
	if move.substitute:
		tags.append({"text": "Substitute", "color": Color(0.6, 0.7, 0.8)})
	if move.taunt:
		tags.append({"text": "Taunt", "color": Color(0.9, 0.5, 0.3)})
	if move.encore:
		tags.append({"text": "Encore", "color": Color(0.8, 0.6, 0.9)})
	if move.knock_off:
		tags.append({"text": "Knock Off", "color": Color(0.7, 0.4, 0.3)})
	if move.weather_set != "":
		tags.append({"text": "Sets Weather", "color": Color(0.5, 0.7, 0.9)})
	if move.hazard_type != "":
		tags.append({"text": "Sets Hazard", "color": Color(0.8, 0.5, 0.3)})
	if move.clears_hazards:
		tags.append({"text": "Clears Hazards", "color": UITokens.STAMP_GREEN})
	if move.trick_room:
		tags.append({"text": "Trick Room", "color": Color(0.7, 0.5, 0.9)})

	# Stat changes (self)
	if move.stat_changes.size() > 0:
		var stat_abbrev = {"attack": "ATK", "defense": "DEF", "sp_attack": "SPA", "sp_defense": "SPD", "speed": "SPE", "accuracy": "ACC", "evasion": "EVA"}
		for stat_key in move.stat_changes:
			var val = int(move.stat_changes[stat_key])
			if val != 0:
				var abbr = stat_abbrev.get(stat_key, stat_key.to_upper())
				var color = UITokens.STAMP_GREEN if val > 0 else UITokens.STAMP_RED
				tags.append({"text": "Self %+d %s" % [val, abbr], "color": color})

	# Target stat changes
	if move.target_stat_changes.size() > 0:
		var stat_abbrev = {"attack": "ATK", "defense": "DEF", "sp_attack": "SPA", "sp_defense": "SPD", "speed": "SPE", "accuracy": "ACC", "evasion": "EVA"}
		for stat_key in move.target_stat_changes:
			var val = int(move.target_stat_changes[stat_key])
			if val != 0:
				var abbr = stat_abbrev.get(stat_key, stat_key.to_upper())
				var color = UITokens.STAMP_GREEN if val < 0 else UITokens.STAMP_RED  # Foe debuff is green for player
				tags.append({"text": "Foe %+d %s" % [val, abbr], "color": color})

	if move.multi_hit_min > 0:
		if move.multi_hit_min == move.multi_hit_max:
			tags.append({"text": "Hits %dx" % move.multi_hit_min, "color": Color(0.7, 0.65, 0.55)})
		else:
			tags.append({"text": "Hits %d-%dx" % [move.multi_hit_min, move.multi_hit_max], "color": Color(0.7, 0.65, 0.55)})

	# Create tag labels
	for tag in tags:
		var lbl = Label.new()
		lbl.text = tag.text
		lbl.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
		lbl.add_theme_color_override("font_color", tag.color)
		# Add a small background
		var tag_style = StyleBoxFlat.new()
		tag_style.bg_color = tag.color.lerp(Color.BLACK, 0.7)
		tag_style.bg_color.a = 0.5
		tag_style.set_corner_radius_all(3)
		tag_style.set_content_margin_all(2)
		tag_style.content_margin_left = 4
		tag_style.content_margin_right = 4
		lbl.add_theme_stylebox_override("normal", tag_style)
		container.add_child(lbl)

# === POKEMON-STYLE ACTION MENU HANDLERS ===

func _on_fight_pressed() -> void:
	if not is_instance_valid(battle_mgr) or not battle_mgr.awaiting_action:
		return
	if _phase != BattlePhase.PROMPT:
		return
	AudioManager.play_ui_sfx("ui_click")
	_juice_button(fight_button)
	_refresh_move_buttons()
	_set_phase(BattlePhase.ACTION_SELECT)

func _on_move_back_pressed() -> void:
	_set_phase(BattlePhase.PROMPT)

# === MOVE / FLEE / ITEM / SWITCH ACTIONS ===

func _has_usable_battle_items() -> bool:
	DataRegistry.ensure_loaded()
	for item_id in PlayerData.inventory:
		var qty = int(PlayerData.inventory.get(item_id, 0))
		if qty > 0 and DataRegistry.get_battle_item(item_id) != null:
			return true
	return false

func _on_move_pressed(idx: int) -> void:
	if not is_instance_valid(battle_mgr) or not battle_mgr.awaiting_action:
		return
	if _phase != BattlePhase.ACTION_SELECT:
		return
	if idx < _move_card_panels.size():
		_juice_card(_move_card_panels[idx])
	var active_idx = battle_mgr.client_active_creature_idx
	if active_idx < 0 or active_idx >= PlayerData.party.size():
		return
	var moves = PlayerData.party[active_idx].get("moves", [])
	if idx < moves.size():
		battle_mgr.send_move(moves[idx])
		if battle_mgr.client_battle_mode == 2:
			_set_phase(BattlePhase.WAITING)
		else:
			_set_phase(BattlePhase.ANIMATING)

func _on_flee_pressed() -> void:
	if not is_instance_valid(battle_mgr) or not battle_mgr.awaiting_action:
		return
	if _phase != BattlePhase.PROMPT:
		return
	AudioManager.play_sfx("flee")
	_juice_button(flee_button)
	battle_mgr.send_flee()
	_set_phase(BattlePhase.ANIMATING)

func _on_item_pressed() -> void:
	if not is_instance_valid(battle_mgr) or not battle_mgr.awaiting_action:
		return
	if _phase != BattlePhase.PROMPT:
		return
	if not _has_usable_battle_items():
		_show_narration_toast("No battle items available.", Color(0.61, 0.55, 0.48), 1.5)
		return
	AudioManager.play_ui_sfx("ui_click")
	_juice_button(item_button)
	_show_item_panel()

func _on_switch_pressed() -> void:
	if not is_instance_valid(battle_mgr) or not battle_mgr.awaiting_action:
		return
	if _phase != BattlePhase.PROMPT:
		return
	AudioManager.play_ui_sfx("ui_click")
	_juice_button(switch_button)
	_show_switch_panel()

# === ITEM PANEL ===

func _make_invisible_overlay_btn() -> Button:
	var btn = Button.new()
	btn.flat = true
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var s = StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", s)
	btn.add_theme_stylebox_override("pressed", s)
	btn.add_theme_stylebox_override("focus", s)
	btn.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_pressed_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_disabled_color", Color(0, 0, 0, 0))
	return btn

func _make_dark_card_style(accent_color: Color = Color(0.5, 0.42, 0.3)) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.18, 0.15, 0.12, 0.95)
	s.border_color = accent_color
	s.set_border_width_all(1)
	s.border_width_left = 4
	s.set_corner_radius_all(6)
	s.set_content_margin_all(10)
	return s

func _make_dark_card_hover_style(accent_color: Color = Color(0.5, 0.42, 0.3)) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.24, 0.2, 0.16, 0.95)
	s.border_color = accent_color
	s.set_border_width_all(2)
	s.border_width_left = 4
	s.set_corner_radius_all(6)
	s.set_content_margin_all(10)
	return s

func _show_no_items_panel() -> void:
	if action_layer == null:
		return
	if is_instance_valid(item_panel):
		if item_panel.get_parent():
			item_panel.get_parent().remove_child(item_panel)
		item_panel.queue_free()
	item_panel = PanelContainer.new()
	item_panel.anchors_preset = Control.PRESET_CENTER
	item_panel.custom_minimum_size = Vector2(300, 0)
	UITheme.apply_panel(item_panel)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	item_panel.add_child(vbox)

	var title = Label.new()
	title.text = "No Battle Items"
	UITheme.style_subheading(title)
	title.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_H3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var msg = Label.new()
	msg.text = "You don't have any battle items."
	UITheme.style_small(msg)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(msg)

	var close_btn = Button.new()
	close_btn.text = "Close"
	UITheme.style_button(close_btn)
	close_btn.pressed.connect(func():
		if is_instance_valid(item_panel):
			if item_panel.get_parent():
				item_panel.get_parent().remove_child(item_panel)
			item_panel.queue_free()
			item_panel = null
	)
	vbox.add_child(close_btn)

	action_layer.add_child(item_panel)

func _show_item_panel() -> void:
	if not is_instance_valid(battle_mgr) or action_layer == null:
		return
	if not _has_usable_battle_items():
		return
	if is_instance_valid(item_panel):
		if item_panel.get_parent():
			item_panel.get_parent().remove_child(item_panel)
		item_panel.queue_free()
	item_panel = PanelContainer.new()
	item_panel.anchors_preset = Control.PRESET_CENTER
	item_panel.custom_minimum_size = Vector2(400, 0)
	UITheme.apply_panel(item_panel)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	item_panel.add_child(vbox)

	var title = Label.new()
	title.text = "Use Item"
	UITheme.style_subheading(title)
	title.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_H3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	DataRegistry.ensure_loaded()
	var has_items = false
	for item_id in PlayerData.inventory:
		var qty = PlayerData.inventory[item_id]
		if qty <= 0:
			continue
		var bi = DataRegistry.get_battle_item(item_id)
		if bi == null:
			continue
		has_items = true

		var item_btn = Button.new()
		item_btn.custom_minimum_size.y = 60
		item_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		item_btn.text = "%s  x%d\n%s" % [bi.display_name, qty, bi.description]
		UITheme.style_button(item_btn, "secondary")
		item_btn.pressed.connect(_on_item_selected.bind(item_id, bi.effect_type))
		vbox.add_child(item_btn)

	if not has_items:
		var empty_label = Label.new()
		empty_label.text = "No battle items in inventory."
		UITheme.style_small(empty_label)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(empty_label)

	var cancel = Button.new()
	cancel.text = "Cancel"
	UITheme.style_button(cancel, "secondary")
	cancel.pressed.connect(func():
		if is_instance_valid(item_panel):
			if item_panel.get_parent():
				item_panel.get_parent().remove_child(item_panel)
			item_panel.queue_free()
		item_panel = null
	)
	vbox.add_child(cancel)
	action_layer.add_child(item_panel)

func _on_item_selected(item_id: String, effect_type: String) -> void:
	if is_instance_valid(item_panel):
		if item_panel.get_parent():
			item_panel.get_parent().remove_child(item_panel)
		item_panel.queue_free()
	item_panel = null
	_show_item_target_panel(item_id, effect_type)

func _on_item_target_selected(item_id: String, creature_idx: int) -> void:
	if is_instance_valid(battle_mgr):
		battle_mgr.send_item_use(item_id, creature_idx)
		if battle_mgr.client_battle_mode == 2:
			_set_phase(BattlePhase.WAITING)
		else:
			_set_phase(BattlePhase.ANIMATING)
	if is_instance_valid(item_panel):
		if item_panel.get_parent():
			item_panel.get_parent().remove_child(item_panel)
		item_panel.queue_free()
	item_panel = null

func _show_item_target_panel(item_id: String, effect_type: String) -> void:
	if action_layer == null:
		return
	if is_instance_valid(item_panel):
		if item_panel.get_parent():
			item_panel.get_parent().remove_child(item_panel)
		item_panel.queue_free()
	item_panel = PanelContainer.new()
	item_panel.anchors_preset = Control.PRESET_CENTER
	item_panel.custom_minimum_size = Vector2(400, 0)
	UITheme.apply_panel(item_panel)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	item_panel.add_child(vbox)

	# Title with item name context
	var bi = DataRegistry.get_battle_item(item_id)
	var item_display = bi.display_name if bi else item_id
	var title = Label.new()
	title.text = "Use %s on..." % item_display
	UITheme.style_subheading(title)
	title.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_H3))
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

		var target_btn = Button.new()
		target_btn.custom_minimum_size.y = 60
		target_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		target_btn.text = "%s  Lv.%d\nHP %d/%d" % [
			creature.get("nickname", "???"),
			int(creature.get("level", 1)),
			hp,
			max_hp
		]
		UITheme.style_button(target_btn, "secondary")
		target_btn.pressed.connect(_on_item_target_selected.bind(item_id, i))
		vbox.add_child(target_btn)

	var cancel = Button.new()
	cancel.text = "Cancel"
	UITheme.style_button(cancel, "secondary")
	cancel.pressed.connect(func():
		if is_instance_valid(item_panel):
			if item_panel.get_parent():
				item_panel.get_parent().remove_child(item_panel)
			item_panel.queue_free()
		item_panel = null
	)
	vbox.add_child(cancel)
	action_layer.add_child(item_panel)

# === SWITCH PANEL ===

func _show_switch_panel() -> void:
	if not is_instance_valid(battle_mgr) or action_layer == null:
		return
	if is_instance_valid(switch_panel):
		if switch_panel.get_parent():
			switch_panel.get_parent().remove_child(switch_panel)
		switch_panel.queue_free()
	switch_panel = PanelContainer.new()
	switch_panel.anchors_preset = Control.PRESET_CENTER
	switch_panel.custom_minimum_size = Vector2(420, 0)
	UITheme.apply_panel(switch_panel)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	switch_panel.add_child(vbox)

	var title = Label.new()
	title.text = "Switch Creature"
	UITheme.style_subheading(title)
	title.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_H3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var current = battle_mgr.client_active_creature_idx
	var found_any = false
	for i in range(PlayerData.party.size()):
		var c = PlayerData.party[i]
		var hp = int(c.get("hp", 0))
		var max_hp = int(c.get("max_hp", 1))
		var is_fainted = hp <= 0
		var is_active = i == current

		# Card style: gold accent for active, normal for others
		var accent = UITokens.STAMP_GOLD if is_active else Color(0.5, 0.42, 0.3)
		var card = PanelContainer.new()
		card.add_theme_stylebox_override("panel", _make_dark_card_style(accent))
		card.custom_minimum_size.y = 64

		# Dim fainted creatures
		if is_fainted:
			card.modulate.a = 0.5

		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		card.add_child(hbox)

		# Creature color swatch
		var species = DataRegistry.get_species(c.get("species_id", ""))
		var swatch = ColorRect.new()
		swatch.custom_minimum_size = Vector2(24, 24)
		swatch.color = species.mesh_color if species else Color.WHITE
		hbox.add_child(swatch)

		var text_vbox = VBoxContainer.new()
		text_vbox.add_theme_constant_override("separation", 2)
		text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(text_vbox)

		# Top line: name + level
		var top_row = HBoxContainer.new()
		text_vbox.add_child(top_row)

		var name_label = Label.new()
		var name_text = c.get("nickname", "???")
		if is_active:
			name_text += " (Active)"
		name_label.text = name_text
		name_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_BODY))
		name_label.add_theme_color_override("font_color", UITokens.PAPER_CREAM)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top_row.add_child(name_label)

		var level_label = Label.new()
		level_label.text = "Lv.%d" % c.get("level", 1)
		level_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_SMALL))
		level_label.add_theme_color_override("font_color", Color(0.65, 0.58, 0.48))
		top_row.add_child(level_label)

		# HP row
		var hp_row = HBoxContainer.new()
		hp_row.add_theme_constant_override("separation", 6)
		text_vbox.add_child(hp_row)

		var hp_bar = ProgressBar.new()
		hp_bar.custom_minimum_size = Vector2(120, 12)
		hp_bar.max_value = max_hp
		hp_bar.value = hp
		hp_bar.show_percentage = false
		var hp_ratio = float(hp) / max(1, max_hp)
		var bar_style = StyleBoxFlat.new()
		if hp_ratio > 0.5:
			bar_style.bg_color = Color(0.36, 0.55, 0.35)
		elif hp_ratio > 0.25:
			bar_style.bg_color = Color(0.83, 0.66, 0.26)
		else:
			bar_style.bg_color = Color(0.76, 0.33, 0.31)
		bar_style.set_corner_radius_all(3)
		hp_bar.add_theme_stylebox_override("fill", bar_style)
		var bar_bg = StyleBoxFlat.new()
		bar_bg.bg_color = Color(0.15, 0.12, 0.1)
		bar_bg.set_corner_radius_all(3)
		hp_bar.add_theme_stylebox_override("background", bar_bg)
		hp_row.add_child(hp_bar)

		var hp_text = Label.new()
		hp_text.text = "%d/%d" % [hp, max_hp]
		hp_text.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_SMALL))
		hp_text.add_theme_color_override("font_color", Color(0.65, 0.58, 0.48))
		hp_row.add_child(hp_text)

		# Status line
		var status_id = c.get("status", "")
		if is_fainted:
			var fainted_label = Label.new()
			fainted_label.text = "Fainted"
			fainted_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_SMALL))
			fainted_label.add_theme_color_override("font_color", UITokens.STAMP_RED)
			text_vbox.add_child(fainted_label)
		elif status_id != "":
			var status_display = StatusEffects.get_status_display_name(status_id)
			if status_display != "":
				var status_label = Label.new()
				status_label.text = "[%s]" % status_display
				status_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_SMALL))
				status_label.add_theme_color_override("font_color", Color(0.85, 0.6, 0.3))
				text_vbox.add_child(status_label)

		# Click handler — only for available (not active, not fainted)
		if not is_active and not is_fainted:
			found_any = true
			var idx = i
			var card_ref = card
			var normal_style = _make_dark_card_style(accent)
			var hover_style = _make_dark_card_hover_style(accent)
			card.mouse_filter = Control.MOUSE_FILTER_STOP
			card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			card.mouse_entered.connect(func(): card_ref.add_theme_stylebox_override("panel", hover_style))
			card.mouse_exited.connect(func(): card_ref.add_theme_stylebox_override("panel", normal_style))
			card.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					battle_mgr.send_switch(idx)
					if battle_mgr.client_battle_mode == 2:
						_set_phase(BattlePhase.WAITING)
					else:
						_set_phase(BattlePhase.ANIMATING)
					if is_instance_valid(switch_panel):
						if switch_panel.get_parent():
							switch_panel.get_parent().remove_child(switch_panel)
						switch_panel.queue_free()
					switch_panel = null
			)

		vbox.add_child(card)

	if not found_any:
		var lbl = Label.new()
		lbl.text = "No other creatures available!"
		UITheme.style_small(lbl)
		vbox.add_child(lbl)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	UITheme.style_button(cancel_btn, "secondary")
	cancel_btn.pressed.connect(func():
		if is_instance_valid(switch_panel):
			if switch_panel.get_parent():
				switch_panel.get_parent().remove_child(switch_panel)
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
	match _summary_result:
		"victory":
			title.text = "Victory!"
			title.add_theme_color_override("font_color", UITokens.STAMP_GREEN)
		"fled":
			title.text = "Escaped!"
			title.add_theme_color_override("font_color", UITokens.STAMP_GOLD)
		_:
			title.text = "Defeat..."
			title.add_theme_color_override("font_color", UITokens.STAMP_RED)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_heading(title)
	vbox.add_child(title)

	# Fled subtitle
	if _summary_result == "fled":
		var subtitle = Label.new()
		subtitle.text = "Got away safely."
		subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UITheme.style_body(subtitle)
		vbox.add_child(subtitle)

	# XP section (skip when fled — nothing earned)
	if _summary_result != "fled" and battle_mgr.summary_xp_results.size() > 0:
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
			UITheme.style_body(lbl)
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
			UITheme.style_body(lbl)
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
				UITheme.style_body(lbl)
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
			UITheme.style_body(lbl)
			vbox.add_child(lbl)

	# Trainer rewards
	if battle_mgr.summary_trainer_money > 0:
		var lbl = Label.new()
		lbl.text = "$%d earned!" % battle_mgr.summary_trainer_money
		UITheme.style_body(lbl)
		lbl.add_theme_color_override("font_color", UITokens.STAMP_GOLD)
		vbox.add_child(lbl)
	if battle_mgr.summary_trainer_ingredients.size() > 0:
		for item_id in battle_mgr.summary_trainer_ingredients:
			var ingredient = DataRegistry.get_ingredient(item_id)
			var item_name = ingredient.display_name if ingredient else item_id
			var lbl = Label.new()
			lbl.text = "  Bonus: %s x%d" % [item_name, battle_mgr.summary_trainer_ingredients[item_id]]
			UITheme.style_body(lbl)
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
			UITheme.style_body(lbl)
			vbox.add_child(lbl)

	# Defeat penalty
	if battle_mgr.summary_defeat_penalty > 0:
		var lbl = Label.new()
		lbl.text = "Lost $%d. Returned to camp." % battle_mgr.summary_defeat_penalty
		UITheme.style_body(lbl)
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
			# Camera cut to attacker side (smooth tween)
			var attacker_preset = "player_attack" if actor == "player" else "enemy_attack"
			if arena:
				arena.cut_camera(attacker_preset, 0.35)

			# Spawn move-type particles + BinbunVFX scene at target
			var move_type = entry.get("move_type", "")
			var move_category = entry.get("category", "physical")
			var target_side = "enemy" if actor == "player" else "player"
			if move_type != "" and not entry.get("missed", false) and arena:
				effect_pos = arena.get_creature_position(target_side)
				BattleEffects.spawn_move_effect(arena, effect_pos, move_type)
				BattleVFX.spawn_move_vfx(arena, effect_pos, move_type, move_category)

			# Log text + narration toasts
			if msg != "":
				battle_log.append_text(msg + "\n")
				_narrate_entry(entry)
				await get_tree().create_timer(0.3).timeout

			# Damage dealt — hit VFX + knockback + damage number + flash + card HP update
			if entry.has("damage") and entry.damage > 0:
				var is_crit = entry.get("critical", false)
				var effectiveness = entry.get("effectiveness", "")
				var is_super = (effectiveness == "super_effective")

				# Combat SFX
				if is_crit:
					AudioManager.play_sfx("hit_crit")
				elif move_category == "physical":
					AudioManager.play_sfx_varied("hit_physical")
				else:
					AudioManager.play_sfx_varied("hit_special")
				if is_super:
					AudioManager.play_sfx("super_effective")
				elif effectiveness == "not_very_effective":
					AudioManager.play_sfx("not_effective")

				if arena:
					effect_pos = arena.get_creature_position(target_side)

					# Rich scene-based hit VFX
					BattleVFX.spawn_hit_vfx(arena, effect_pos, effectiveness, is_crit)
					# Keep existing particle hit for layering
					BattleEffects.spawn_hit_effect(arena, effect_pos, effectiveness)

					arena.spawn_damage_number(entry.damage, target_side, effectiveness)
					arena.flash_creature(target_side)

					# Knockback — scale with damage impact
					var knock_intensity = 0.2
					if is_crit:
						knock_intensity = 0.5
					elif is_super:
						knock_intensity = 0.4
					arena.knockback_creature(target_side, knock_intensity)

					# Critical hit: screen flash + hit-stop + crit camera punch
					if is_crit:
						_flash_screen(Color(1, 1, 1, 0.6), 0.12)
						arena.hit_stop(0.06)
						arena.crit_camera_punch(target_side)
						await get_tree().create_timer(0.15).timeout
					elif is_super:
						# Super effective: camera shake + mild flash
						arena.camera_shake(0.25, 0.12)
						_flash_screen(Color(0.3, 0.8, 0.3, 0.3), 0.15)

				# HP bar shake + tween
				_shake_hp_bar(target_side)
				_animate_card_hp_from_battle_mgr()
				await get_tree().create_timer(0.3).timeout

				# KO check — dramatic wide camera if creature fainted
				if arena and entry.has("target_fainted") and entry.target_fainted:
					AudioManager.play_sfx("faint")
					arena.ko_camera(target_side)
					await get_tree().create_timer(0.8).timeout
			elif entry.get("missed", false):
				AudioManager.play_sfx("miss")
				_animate_card_hp_from_battle_mgr()
			else:
				# No damage, but still sync HP
				_animate_card_hp_from_battle_mgr()

			# Stat change effects
			if entry.has("stat_changes") and arena:
				actor_side = actor if actor in ["player", "enemy"] else "player"
				effect_pos = arena.get_creature_position(actor_side)
				BattleEffects.spawn_stat_effect(arena, effect_pos, _has_any_positive(entry.stat_changes))
			if entry.has("target_stat_changes") and arena:
				effect_pos = arena.get_creature_position(target_side)
				BattleEffects.spawn_stat_effect(arena, effect_pos, _has_any_positive(entry.target_stat_changes))

			# Status applied effect + aura
			if entry.has("status_applied") and arena:
				AudioManager.play_sfx("status_apply")
				effect_pos = arena.get_creature_position(target_side)
				BattleEffects.spawn_status_effect(arena, effect_pos, entry.status_applied)
				arena.update_status_aura(target_side, entry.status_applied)

			# Heal effect
			if (entry.has("heal") or entry.has("drain_heal") or entry.has("ability_heal")) and arena:
				AudioManager.play_sfx("heal")
				actor_side = actor if actor in ["player", "enemy"] else "player"
				effect_pos = arena.get_creature_position(actor_side)
				BattleEffects.spawn_heal_effect(arena, effect_pos)

		elif entry_type in ["status_damage", "hazard_damage"]:
			# Camera to the creature taking damage
			actor_side = actor if actor in ["player", "enemy"] else "player"
			var cam_preset = "enemy_attack" if actor_side == "player" else "player_attack"
			if arena:
				arena.cut_camera(cam_preset, 0.35)
			if msg != "":
				battle_log.append_text(msg + "\n")
				_narrate_entry(entry)
			if entry.has("damage") and entry.damage > 0 and arena:
				effect_pos = arena.get_creature_position(actor_side)
				BattleEffects.spawn_hit_effect(arena, effect_pos, "")
				BattleVFX.spawn_hit_vfx(arena, effect_pos, "", false)
				arena.flash_creature(actor_side)
				arena.knockback_creature(actor_side, 0.15)
			_shake_hp_bar(actor_side)
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
				_narrate_entry(entry)
			_animate_card_hp_from_battle_mgr()
			if msg != "":
				await get_tree().create_timer(0.3).timeout

		elif entry_type in ["switch", "trainer_switch", "forced_switch"]:
			# Swap animation — stop idle bob, swap, restart
			if arena and battle_mgr:
				var side = "player" if entry.get("actor", "player") == "player" else "enemy"
				if entry_type == "trainer_switch":
					side = "enemy"
				arena.stop_idle_bob(side)
				arena.update_status_aura(side, "")  # Clear aura on swap
				var creature_data: Dictionary = {}
				if side == "player":
					var aidx = battle_mgr.client_active_creature_idx
					if aidx >= 0 and aidx < PlayerData.party.size():
						creature_data = PlayerData.party[aidx]
				else:
					creature_data = battle_mgr.client_enemy
				if creature_data.size() > 0:
					arena.swap_creature_animation(side, creature_data)
			if msg != "":
				battle_log.append_text(msg + "\n")
				_narrate_entry(entry)
				await get_tree().create_timer(0.5).timeout
			_refresh_cards()
			# Restart idle bob after swap
			if arena:
				arena.start_idle_bobs()

		else:
			# All other entry types (weather, taunt, encore, etc.)
			if msg != "":
				battle_log.append_text(msg + "\n")
				_narrate_entry(entry)
				await get_tree().create_timer(0.3).timeout

		# Return camera to neutral after each entry
		if arena:
			arena.cut_camera("neutral", 0.3)

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
			AudioManager.play_sfx("xp_gain")
			battle_log.append_text("[color=#5B7EA6]+%d XP[/color]\n" % xp)
			_show_narration_toast("+%d XP" % xp, Color(0.36, 0.49, 0.65), 1.2)
		for lvl in r.get("level_ups", []):
			AudioManager.play_sfx("level_up")
			battle_log.append_text("[color=#D4A843]Level up! Now Lv.%d![/color]\n" % lvl)
			_show_narration_toast("Level up! Lv.%d!" % lvl, Color(0.83, 0.66, 0.26), 2.0)
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
	var any_level_up = false
	for r2 in results.get("results", []):
		if r2.get("level_ups", []).size() > 0:
			any_level_up = true
	if active_idx >= 0 and active_idx < PlayerData.party.size():
		var creature = PlayerData.party[active_idx]
		_animate_card_xp(creature.get("xp", 0), creature.get("xp_to_next", 100), any_level_up)

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
			if entry.has("confused_self_hit"):
				return "[color=#9966BB]%s is tipsy and hurt itself for %d damage![/color]" % [actor_name, entry.confused_self_hit]
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
			if entry.get("heal_blocked", false):
				text += " [color=#B38C4D]Too stuffed to heal![/color]"
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

# === ENEMY CARD SHIFT ===

func _tween_enemy_card_position(shifted: bool) -> void:
	if _enemy_card_tween and _enemy_card_tween.is_valid():
		_enemy_card_tween.kill()
	_enemy_card_tween = create_tween().set_parallel(true)
	var target_left = 0.22 if shifted else 0.01
	var target_right = 0.49 if shifted else 0.28
	_enemy_card_tween.tween_property(enemy_card, "anchor_left", target_left, 0.25) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_enemy_card_tween.tween_property(enemy_card, "anchor_right", target_right, 0.25) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

# === NARRATION TOAST SYSTEM ===

func _show_narration_toast(text: String, color: Color, linger: float) -> void:
	if _narration_container == null:
		return
	# Evict oldest if at max
	while _active_toasts.size() >= 3:
		var oldest = _active_toasts.pop_front()
		if is_instance_valid(oldest):
			var evict_tween = create_tween()
			evict_tween.tween_property(oldest, "modulate:a", 0.0, 0.15).set_ease(Tween.EASE_IN)
			evict_tween.tween_callback(oldest.queue_free)

	# Build toast panel
	var panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = UITheme.make_panel_style(
		Color(0.12, 0.1, 0.08, 0.92),
		Color(0.5, 0.42, 0.3, 0.7),
		6,
		2
	)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)

	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_H3))
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)

	# Start invisible + offset for slide-in
	panel.modulate = Color(1, 1, 1, 0)
	panel.position.y = -20
	_narration_container.add_child(panel)
	_active_toasts.append(panel)

	# Fade in + slide down
	var tw = create_tween().set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.2).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "position:y", 0.0, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	await tw.finished

	# Linger
	await get_tree().create_timer(linger).timeout

	# Fade out (check still valid — battle may have ended)
	if not is_instance_valid(panel):
		return
	var fade = create_tween()
	fade.tween_property(panel, "modulate:a", 0.0, 0.4).set_ease(Tween.EASE_IN)
	await fade.finished
	if is_instance_valid(panel):
		_active_toasts.erase(panel)
		panel.queue_free()

func _clear_all_toasts() -> void:
	for toast in _active_toasts:
		if is_instance_valid(toast):
			toast.queue_free()
	_active_toasts.clear()

func _narrate_entry(entry: Dictionary) -> void:
	var actor = entry.get("actor", "")
	var entry_type = entry.get("type", "move")
	var is_player = (actor == "player")
	var actor_name = "You" if is_player else "Enemy"
	var cream = Color(0.96, 0.94, 0.88)
	var warm_peach = Color(0.95, 0.78, 0.65)

	match entry_type:
		"move":
			var move_name = entry.get("move", "???")

			# Special cases that produce a single toast
			if entry.has("confused_self_hit"):
				_show_narration_toast("Hurt itself — %d damage!" % entry.confused_self_hit, STATUS_COLORS.get("fermented", Color(0.6, 0.4, 0.7)), 2.0)
				return
			if entry.get("missed", false):
				_show_narration_toast("%s used %s — missed!" % [actor_name, move_name], Color(0.83, 0.66, 0.26), 1.5)
				return
			if entry.get("skipped", false):
				_show_narration_toast("%s can't move!" % actor_name, Color(0.83, 0.66, 0.26), 1.5)
				return
			if entry.get("charging", false):
				_show_narration_toast("%s is charging up!" % actor_name, cream if is_player else warm_peach, 1.5)
				return
			if entry.get("protecting", false):
				_show_narration_toast("%s protected itself!" % actor_name, cream if is_player else warm_peach, 1.5)
				return
			if entry.get("blocked", false):
				_show_narration_toast("Attack was blocked!", Color(0.83, 0.66, 0.26), 1.5)
				return
			if entry.get("immune", false):
				_show_narration_toast("%s used %s — no effect!" % [actor_name, move_name], Color(0.61, 0.55, 0.48), 1.5)
				return

			# Move used toast
			var move_color = cream if is_player else warm_peach
			_show_narration_toast("%s used %s!" % [actor_name, move_name], move_color, 1.8)

			# Damage + effectiveness combined toast
			if entry.has("damage") and entry.damage > 0:
				var dmg_text = "%d damage!" % entry.damage
				var dmg_color = cream
				var dmg_linger = 1.2
				var effectiveness = entry.get("effectiveness", "")
				if effectiveness == "super_effective":
					dmg_text += " Super effective!"
					dmg_color = Color(0.36, 0.55, 0.35)
					dmg_linger = 1.5
				elif effectiveness == "not_very_effective":
					dmg_text += " Not very effective..."
					dmg_color = Color(0.83, 0.66, 0.26)
					dmg_linger = 1.5
				if entry.get("critical", false):
					dmg_text += " Critical hit!"
					dmg_color = Color(1.0, 0.85, 0.2)
					dmg_linger = 1.5
				_show_narration_toast(dmg_text, dmg_color, dmg_linger)

			# Status applied toast
			if entry.has("status_applied"):
				var status_name = StatusEffects.get_status_display_name(entry.status_applied)
				var status_color = STATUS_COLORS.get(entry.status_applied, Color(1.0, 0.8, 0.3))
				_show_narration_toast("Inflicted %s!" % status_name, status_color, 2.0)

			# Stat changes toast
			if entry.has("stat_changes"):
				for stat in entry.stat_changes:
					var change = entry.stat_changes[stat]
					var direction = "rose" if change > 0 else "fell"
					var amount = "sharply " if abs(change) >= 2 else ""
					var sc_color = Color(0.36, 0.49, 0.65) if change > 0 else Color(0.85, 0.4, 0.3)
					_show_narration_toast("%s %s%s!" % [stat.capitalize(), amount, direction], sc_color, 1.5)
			if entry.has("target_stat_changes"):
				for stat in entry.target_stat_changes:
					var change = entry.target_stat_changes[stat]
					var direction = "rose" if change > 0 else "fell"
					var sc_color = Color(0.36, 0.49, 0.65) if change > 0 else Color(0.85, 0.4, 0.3)
					_show_narration_toast("Foe's %s %s!" % [stat.capitalize(), direction], sc_color, 1.5)

			# Heal toast
			if entry.has("heal"):
				_show_narration_toast("Healed %d HP!" % entry.heal, Color(0.36, 0.55, 0.35), 1.5)
			if entry.has("drain_heal"):
				_show_narration_toast("Drained %d HP!" % entry.drain_heal, Color(0.36, 0.55, 0.35), 1.5)

			# Heal blocked toast
			if entry.get("heal_blocked", false):
				_show_narration_toast("Too stuffed to heal!", STATUS_COLORS.get("stuffed", Color(0.7, 0.55, 0.3)), 1.8)

			# Weather set toast
			if entry.has("weather_set"):
				var wname = WEATHER_NAMES.get(entry.weather_set, entry.weather_set)
				_show_narration_toast("%s started!" % wname, Color(0.7, 0.65, 0.85), 2.0)

			# Faint check
			if entry.has("target_fainted") and entry.target_fainted:
				var target_name = "Enemy" if is_player else "Your creature"
				_show_narration_toast("%s fainted!" % target_name, Color(0.76, 0.33, 0.31), 2.5)

		"status_damage":
			var dmg = entry.get("damage", 0)
			_show_narration_toast("%s took %d status damage!" % [actor_name, dmg], STATUS_COLORS.get(entry.get("status", ""), cream), 1.5)

		"hazard_damage":
			var dmg = entry.get("damage", 0)
			var hazard = entry.get("hazard", "hazards")
			_show_narration_toast("Hurt by %s! %d damage!" % [hazard, dmg], Color(0.9, 0.5, 0.3), 1.5)

		"ability_heal", "item_heal":
			var heal = entry.get("heal", 0)
			_show_narration_toast("Healed %d HP!" % heal, Color(0.36, 0.55, 0.35), 1.5)

		"ability_trigger":
			var ability_msg = entry.get("message", "")
			_show_narration_toast(ability_msg, Color(0.55, 0.42, 0.29), 1.8)

		"weather_cleared":
			var wname = WEATHER_NAMES.get(entry.get("weather", ""), "weather")
			_show_narration_toast("%s subsided." % wname, Color(0.7, 0.65, 0.85), 2.0)

		"switch", "trainer_switch", "forced_switch":
			_show_narration_toast("Switched creature!", cream, 1.5)

		"victory":
			_show_narration_toast("Victory!", Color(0.36, 0.55, 0.35), 2.5)
		"defeat":
			_show_narration_toast("All creatures fainted!", Color(0.76, 0.33, 0.31), 2.5)
		"fled":
			_show_narration_toast("Got away safely!", cream, 1.8)
		"flee_failed":
			_show_narration_toast("Couldn't escape!", Color(0.83, 0.66, 0.26), 1.5)
		"fainted":
			_show_narration_toast("Your creature fainted!", Color(0.76, 0.33, 0.31), 2.5)
		"item_use":
			var item_name = entry.get("item_name", "Item")
			_show_narration_toast("Used %s!" % item_name, Color(0.36, 0.49, 0.65), 2.0)
		"trick_room_set":
			_show_narration_toast("Trick Room!", Color(0.55, 0.42, 0.29), 2.0)
		"trick_room_ended":
			_show_narration_toast("Trick Room wore off.", Color(0.55, 0.42, 0.29), 1.5)
		"taunt_applied":
			_show_narration_toast("Taunted!", Color(0.85, 0.4, 0.3), 1.5)
		"encore_applied":
			_show_narration_toast("Encore!", Color(0.83, 0.66, 0.26), 1.5)
		_:
			# Fallback for any unhandled type — show as generic toast if there's a message
			var fallback_msg = entry.get("message", "")
			if fallback_msg != "":
				_show_narration_toast(fallback_msg, cream, 1.5)

func _set_menu_buttons_enabled(enabled: bool) -> void:
	var mode = battle_mgr.client_battle_mode if battle_mgr else 0
	var can_use_items = _has_usable_battle_items() if enabled and mode != 2 else false
	fight_button.disabled = not enabled
	flee_button.disabled = not enabled
	flee_button.visible = (mode == 0)
	switch_button.disabled = not enabled
	item_button.disabled = (not enabled) or (mode != 2 and not can_use_items)
	item_button.visible = (mode != 2)

func _on_player_inventory_changed() -> void:
	if _phase == BattlePhase.PROMPT:
		_set_menu_buttons_enabled(true)

func _set_buttons_enabled(enabled: bool) -> void:
	# For move card click buttons specifically
	if not enabled:
		for i in range(move_buttons.size()):
			move_buttons[i].disabled = true
			if i < _move_card_panels.size():
				_move_card_panels[i].modulate = Color(0.5, 0.5, 0.5)
		return
	if battle_mgr == null:
		for i in range(move_buttons.size()):
			move_buttons[i].disabled = false
			if i < _move_card_panels.size():
				_move_card_panels[i].modulate = Color.WHITE
		return
	var active_idx = battle_mgr.client_active_creature_idx
	if active_idx < 0 or active_idx >= PlayerData.party.size():
		return
	var creature = PlayerData.party[active_idx]
	var moves = creature.get("moves", [])
	var pp = creature.get("pp", [])
	var is_taunted = battle_mgr.client_player_taunt_turns > 0
	var choice_locked = battle_mgr.client_player_choice_locked
	var encore_turns = battle_mgr.client_player_encore_turns
	var encore_move = battle_mgr.client_player_encore_move
	for i in range(move_buttons.size()):
		if i >= moves.size():
			continue
		var card_visible = _move_card_panels[i].visible if i < _move_card_panels.size() else false
		if not card_visible:
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
		if i < _move_card_panels.size():
			_move_card_panels[i].modulate = Color(0.5, 0.5, 0.5) if is_disabled else Color.WHITE
