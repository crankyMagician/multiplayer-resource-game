extends CanvasLayer

# Dev Debug Overlay — F1 toggleable panel with comprehensive game controls.
# Editor-only: self-destructs in exported builds.
# All actions go through NetworkManager.request_debug_action RPC to the server.

const PANEL_WIDTH := 320
const SECTION_GAP := 6
const LABEL_H := 22
const FIELD_H := 28
const BTN_H := 28

# Dev-tool color palette
const BG_COLOR := Color(0.18, 0.18, 0.22, 0.97)
const BORDER_COLOR := Color(0.35, 0.35, 0.42)
const HEADER_BAR_COLOR := Color(0.25, 0.45, 0.72)
const HEADER_TEXT_COLOR := Color(0.95, 0.95, 0.98)
const SECTION_HEADER_COLOR := Color(0.55, 0.78, 1.0)
const SECTION_HEADER_BG := Color(0.22, 0.22, 0.28, 0.8)
const LABEL_COLOR := Color(0.78, 0.78, 0.82)
const FEEDBACK_COLOR := Color(0.4, 0.9, 0.4)
const SEPARATOR_COLOR := Color(0.3, 0.3, 0.36)
const BTN_NORMAL_BG := Color(0.28, 0.28, 0.34)
const BTN_HOVER_BG := Color(0.35, 0.35, 0.42)
const BTN_PRESSED_BG := Color(0.22, 0.22, 0.28)
const BTN_TEXT_COLOR := Color(0.88, 0.88, 0.92)
const FIELD_BG_COLOR := Color(0.14, 0.14, 0.18)
const FIELD_BORDER_COLOR := Color(0.32, 0.32, 0.38)
const FIELD_TEXT_COLOR := Color(0.85, 0.85, 0.9)
const FIELD_PLACEHOLDER_COLOR := Color(0.45, 0.45, 0.52)
const ACCENT_COLOR := Color(0.35, 0.55, 0.85)

var panel: PanelContainer
var scroll: ScrollContainer
var vbox: VBoxContainer
var feedback_label: Label
var time_label: Label
var _info_label: Label
var _refresh_timer: float = 0.0
var _feedback_fade_timer: float = 0.0
var _tween: Tween

# Battle mode detection
var _in_battle: bool = false

# World-mode containers
var world_sections: VBoxContainer
# Battle-mode containers
var battle_sections: VBoxContainer

# Collapsible section tracking: header_button -> content_container
var _section_collapse_map: Dictionary = {}

func _ready() -> void:
	if not OS.has_feature("editor"):
		queue_free()
		return
	layer = 25
	# Register F1 input
	if not InputMap.has_action("toggle_debug_overlay"):
		InputMap.add_action("toggle_debug_overlay")
		var ev := InputEventKey.new()
		ev.keycode = KEY_F1
		InputMap.action_add_event("toggle_debug_overlay", ev)
	_build_ui()
	visible = false

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug_overlay"):
		if visible:
			_close_panel()
		else:
			_open_panel()
		get_viewport().set_input_as_handled()

func _open_panel() -> void:
	if _tween:
		_tween.kill()
	visible = true
	# Start off-screen right
	var vp_width := get_viewport().get_visible_rect().size.x
	panel.offset_left = vp_width
	panel.offset_right = vp_width + PANEL_WIDTH
	# Tween to center
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(panel, "offset_left", -PANEL_WIDTH / 2.0, 0.3)
	_tween.parallel().tween_property(panel, "offset_right", PANEL_WIDTH / 2.0, 0.3)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _close_panel() -> void:
	if _tween:
		_tween.kill()
	var vp_width := get_viewport().get_visible_rect().size.x
	_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(panel, "offset_left", vp_width, 0.25)
	_tween.parallel().tween_property(panel, "offset_right", vp_width + PANEL_WIDTH, 0.25)
	_tween.tween_callback(func(): visible = false)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer += delta
	if _refresh_timer >= 0.5:
		_refresh_timer = 0.0
		_update_time_label()
		_update_battle_mode()
		_update_info_label()
	if _feedback_fade_timer > 0.0:
		_feedback_fade_timer -= delta
		if _feedback_fade_timer <= 1.0:
			feedback_label.modulate.a = maxf(_feedback_fade_timer, 0.0)
		if _feedback_fade_timer <= 0.0:
			feedback_label.text = ""
			feedback_label.modulate.a = 1.0

func _update_battle_mode() -> void:
	var bm = _get_battle_manager()
	var now_in_battle := false
	if bm and bm.in_battle:
		now_in_battle = true
	if now_in_battle != _in_battle:
		_in_battle = now_in_battle
		world_sections.visible = !_in_battle
		battle_sections.visible = _in_battle

func _get_battle_manager() -> Node:
	return get_node_or_null("/root/Main/GameWorld/BattleManager")

func _update_time_label() -> void:
	var sm = get_node_or_null("/root/Main/GameWorld/SeasonManager")
	if sm and time_label:
		var progress = sm.get_day_progress() * 100.0
		time_label.text = "Y%d %s %d — %s — %.0f%%" % [
			sm.current_year, sm.get_month_name(), sm.day_in_month,
			sm.get_weather_name().capitalize(), progress
		]

func _update_info_label() -> void:
	if not _info_label:
		return
	if multiplayer and multiplayer.has_multiplayer_peer():
		var peer_id = multiplayer.get_unique_id()
		var pname = PlayerData.player_name if PlayerData.player_name != "" else "?"
		_info_label.text = "%s (peer %d)" % [pname, peer_id]
	else:
		_info_label.text = "Not connected"

# === UI Building ===

func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.name = "DebugPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_color = BORDER_COLOR
	style.border_width_left = 3
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -PANEL_WIDTH / 2.0
	panel.offset_right = PANEL_WIDTH / 2.0
	panel.offset_top = 10
	panel.offset_bottom = -10
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	panel.clip_contents = true
	add_child(panel)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 4)
	outer_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(outer_vbox)

	# Header bar
	var header_panel := PanelContainer.new()
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = HEADER_BAR_COLOR
	header_style.corner_radius_top_left = 3
	header_style.corner_radius_top_right = 3
	header_style.content_margin_left = 8
	header_style.content_margin_right = 8
	header_style.content_margin_top = 4
	header_style.content_margin_bottom = 4
	header_panel.add_theme_stylebox_override("panel", header_style)
	outer_vbox.add_child(header_panel)

	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 4)
	header_panel.add_child(header_hbox)

	var header_vbox := VBoxContainer.new()
	header_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_vbox.add_theme_constant_override("separation", 0)
	header_hbox.add_child(header_vbox)

	var header := Label.new()
	header.text = "DEV DEBUG"
	header.add_theme_color_override("font_color", HEADER_TEXT_COLOR)
	header.add_theme_font_size_override("font_size", 15)
	header_vbox.add_child(header)

	var subtitle := Label.new()
	subtitle.text = "F1 to close"
	subtitle.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95))
	subtitle.add_theme_font_size_override("font_size", 10)
	header_vbox.add_child(subtitle)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(28, 28)
	_apply_button_style(close_btn)
	close_btn.pressed.connect(_close_panel)
	header_hbox.add_child(close_btn)

	# Player info label
	_info_label = Label.new()
	_info_label.text = "..."
	_info_label.add_theme_color_override("font_color", Color(0.65, 0.75, 0.9))
	_info_label.add_theme_font_size_override("font_size", 11)
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer_vbox.add_child(_info_label)

	# Time label (always visible)
	time_label = Label.new()
	time_label.text = "..."
	time_label.add_theme_color_override("font_color", Color(0.65, 0.85, 0.95))
	time_label.add_theme_font_size_override("font_size", 12)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer_vbox.add_child(time_label)

	_add_separator(outer_vbox)

	# Scroll container for sections
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 0
	scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var scroll_grabber := StyleBoxFlat.new()
	scroll_grabber.bg_color = Color(0.4, 0.4, 0.5, 0.6)
	scroll_grabber.corner_radius_top_left = 3
	scroll_grabber.corner_radius_top_right = 3
	scroll_grabber.corner_radius_bottom_left = 3
	scroll_grabber.corner_radius_bottom_right = 3
	var scroll_grabber_hl := scroll_grabber.duplicate()
	scroll_grabber_hl.bg_color = Color(0.5, 0.55, 0.65, 0.8)
	var scroll_grabber_pressed := scroll_grabber.duplicate()
	scroll_grabber_pressed.bg_color = ACCENT_COLOR
	scroll.add_theme_stylebox_override("grabber", scroll_grabber)
	scroll.add_theme_stylebox_override("grabber_highlight", scroll_grabber_hl)
	scroll.add_theme_stylebox_override("grabber_pressed", scroll_grabber_pressed)
	outer_vbox.add_child(scroll)

	var sections_root := VBoxContainer.new()
	sections_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sections_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sections_root.add_theme_constant_override("separation", 4)
	scroll.add_child(sections_root)

	# World sections
	world_sections = VBoxContainer.new()
	world_sections.add_theme_constant_override("separation", 4)
	sections_root.add_child(world_sections)
	_build_world_sections()

	# Battle sections
	battle_sections = VBoxContainer.new()
	battle_sections.add_theme_constant_override("separation", 4)
	battle_sections.visible = false
	sections_root.add_child(battle_sections)
	_build_battle_sections()

	# Feedback label at bottom
	_add_separator(outer_vbox)
	feedback_label = Label.new()
	feedback_label.text = ""
	feedback_label.add_theme_color_override("font_color", FEEDBACK_COLOR)
	feedback_label.add_theme_font_size_override("font_size", 11)
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback_label.custom_minimum_size = Vector2(0, 20)
	outer_vbox.add_child(feedback_label)

# === World Mode Sections ===

var _year_spin: SpinBox
var _month_spin: SpinBox
var _day_spin: SpinBox
var _weather_option: OptionButton
var _species_field: LineEdit
var _trainer_option: OptionButton
var _item_field: LineEdit
var _item_qty_spin: SpinBox
var _money_spin: SpinBox
var _party_idx_spin: SpinBox
var _level_spin: SpinBox
var _npc_option: OptionButton
var _friendship_spin: SpinBox
var _quest_field: LineEdit
var _teleport_x: SpinBox
var _teleport_y: SpinBox
var _teleport_z: SpinBox

func _build_world_sections() -> void:
	# --- Time & Weather ---
	var time_content := _add_collapsible_section(world_sections, "Time & Weather")
	var time_grid := GridContainer.new()
	time_grid.columns = 3
	time_grid.add_theme_constant_override("h_separation", 4)
	time_content.add_child(time_grid)
	_add_label(time_grid, "Year")
	_add_label(time_grid, "Month")
	_add_label(time_grid, "Day")
	_year_spin = _add_spinbox(time_grid, 1, 99, 1)
	_month_spin = _add_spinbox(time_grid, 1, 12, 3)
	_day_spin = _add_spinbox(time_grid, 1, 28, 1)

	var weather_row := HBoxContainer.new()
	weather_row.add_theme_constant_override("separation", 4)
	time_content.add_child(weather_row)
	_add_label(weather_row, "Weather:")
	_weather_option = OptionButton.new()
	_weather_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weather_option.custom_minimum_size.y = FIELD_H
	for w in ["Sunny", "Rainy", "Stormy", "Windy"]:
		_weather_option.add_item(w)
	_apply_field_style(_weather_option)
	weather_row.add_child(_weather_option)

	var time_btns := HBoxContainer.new()
	time_btns.add_theme_constant_override("separation", 4)
	time_content.add_child(time_btns)
	_add_button(time_btns, "Set Time", _on_set_time)
	_add_button(time_btns, "Adv Day", _on_advance_day)

	var speed_btns := HBoxContainer.new()
	speed_btns.add_theme_constant_override("separation", 4)
	time_content.add_child(speed_btns)
	_add_label(speed_btns, "Speed:")
	for mult in [1, 3, 10, 50]:
		_add_button(speed_btns, "%dx" % mult, _on_set_speed.bind(mult))

	# --- Battles ---
	var battle_content := _add_collapsible_section(world_sections, "Battles")
	var wild_row := HBoxContainer.new()
	wild_row.add_theme_constant_override("separation", 4)
	battle_content.add_child(wild_row)
	_species_field = LineEdit.new()
	_species_field.placeholder_text = "species_id"
	_species_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_species_field.custom_minimum_size.y = FIELD_H
	_apply_field_style(_species_field)
	wild_row.add_child(_species_field)
	_add_button(wild_row, "Wild Battle", _on_wild_battle)

	var trainer_row := HBoxContainer.new()
	trainer_row.add_theme_constant_override("separation", 4)
	battle_content.add_child(trainer_row)
	_trainer_option = OptionButton.new()
	_trainer_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trainer_option.custom_minimum_size.y = FIELD_H
	DataRegistry.ensure_loaded()
	var trainer_ids := DataRegistry.trainers.keys()
	trainer_ids.sort()
	for tid in trainer_ids:
		_trainer_option.add_item(str(tid))
	_apply_field_style(_trainer_option)
	trainer_row.add_child(_trainer_option)
	_add_button(trainer_row, "Trainer", _on_trainer_battle)

	# --- Items & Money ---
	var items_content := _add_collapsible_section(world_sections, "Items & Money")
	var item_row := HBoxContainer.new()
	item_row.add_theme_constant_override("separation", 4)
	items_content.add_child(item_row)
	_item_field = LineEdit.new()
	_item_field.placeholder_text = "item_id"
	_item_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_field.custom_minimum_size.y = FIELD_H
	_apply_field_style(_item_field)
	item_row.add_child(_item_field)
	_item_qty_spin = _add_spinbox(item_row, 1, 999, 10)
	_add_button(item_row, "Give", _on_give_item)

	var money_row := HBoxContainer.new()
	money_row.add_theme_constant_override("separation", 4)
	items_content.add_child(money_row)
	_add_label(money_row, "$")
	_money_spin = _add_spinbox(money_row, 1, 99999, 10000)
	_add_button(money_row, "Give $", _on_give_money)

	# --- Player ---
	var player_content := _add_collapsible_section(world_sections, "Player")
	_add_button(player_content, "Heal Party", _on_heal_party)

	var tp_row := HBoxContainer.new()
	tp_row.add_theme_constant_override("separation", 4)
	player_content.add_child(tp_row)
	_add_label(tp_row, "Teleport:")
	_teleport_x = _add_spinbox(tp_row, -100, 100, 0)
	_teleport_y = _add_spinbox(tp_row, -10, 50, 1)
	_teleport_z = _add_spinbox(tp_row, -100, 100, 3)
	_add_button(tp_row, "Go", _on_teleport)

	var tp_presets := HBoxContainer.new()
	tp_presets.add_theme_constant_override("separation", 4)
	player_content.add_child(tp_presets)
	_add_button(tp_presets, "Spawn", _on_teleport_preset.bind(Vector3(-32.5, 5, 13.75)))
	_add_button(tp_presets, "Farm", _on_teleport_preset.bind(Vector3(-12.5, 3, 16.25)))
	_add_button(tp_presets, "Wharf", _on_teleport_preset.bind(Vector3(-55, 2, -28)))
	_add_button(tp_presets, "Harbor", _on_teleport_preset.bind(Vector3(32, 7, 50)))

	# --- Creatures ---
	var creature_content := _add_collapsible_section(world_sections, "Creatures")
	var creature_row := HBoxContainer.new()
	creature_row.add_theme_constant_override("separation", 4)
	creature_content.add_child(creature_row)
	_add_label(creature_row, "Party#")
	_party_idx_spin = _add_spinbox(creature_row, 0, 2, 0)
	_add_label(creature_row, "Lv")
	_level_spin = _add_spinbox(creature_row, 1, 50, 50)
	_add_button(creature_row, "Set", _on_set_creature_level)

	var creature_btns := HBoxContainer.new()
	creature_btns.add_theme_constant_override("separation", 4)
	creature_content.add_child(creature_btns)
	_add_button(creature_btns, "Max All", _on_max_all_creatures)
	_add_button(creature_btns, "Force Evolve", _on_force_evolve)

	# --- Recipes ---
	var recipe_content := _add_collapsible_section(world_sections, "Recipes")
	_add_button(recipe_content, "Unlock All Recipes", _on_unlock_all_recipes)

	# --- Farming ---
	var farm_content := _add_collapsible_section(world_sections, "Farming")
	var farm_btns := HBoxContainer.new()
	farm_btns.add_theme_constant_override("separation", 4)
	farm_content.add_child(farm_btns)
	_add_button(farm_btns, "Force Grow", _on_force_grow_plots)
	_add_button(farm_btns, "Reset Plots", _on_reset_plots)

	# --- Quests ---
	var quest_content := _add_collapsible_section(world_sections, "Quests")
	var quest_row := HBoxContainer.new()
	quest_row.add_theme_constant_override("separation", 4)
	quest_content.add_child(quest_row)
	_quest_field = LineEdit.new()
	_quest_field.placeholder_text = "quest_id"
	_quest_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quest_field.custom_minimum_size.y = FIELD_H
	_apply_field_style(_quest_field)
	quest_row.add_child(_quest_field)
	_add_button(quest_row, "Complete", _on_complete_quest)
	_add_button(quest_content, "Reset All Quests", _on_reset_quests)

	# --- Social ---
	var social_content := _add_collapsible_section(world_sections, "Social")
	var social_row := HBoxContainer.new()
	social_row.add_theme_constant_override("separation", 4)
	social_content.add_child(social_row)
	_npc_option = OptionButton.new()
	_npc_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_npc_option.custom_minimum_size.y = FIELD_H
	var npc_ids := DataRegistry.npcs.keys()
	npc_ids.sort()
	for nid in npc_ids:
		_npc_option.add_item(str(nid))
	_apply_field_style(_npc_option)
	social_row.add_child(_npc_option)
	_friendship_spin = _add_spinbox(social_row, -100, 100, 100)
	_add_button(social_row, "Set", _on_set_friendship)
	_add_button(social_content, "Max All Friendships", _on_max_all_friendships)

	# --- Excursion ---
	var excursion_content := _add_collapsible_section(world_sections, "Excursion")
	_add_button(excursion_content, "End Current Excursion", _on_end_excursion)

# === Battle Mode Sections ===

var _battle_player_hp_spin: SpinBox
var _battle_enemy_hp_spin: SpinBox
var _battle_status_option: OptionButton
var _battle_status_side: OptionButton
var _battle_stat_option: OptionButton
var _battle_stat_value_spin: SpinBox
var _battle_stat_side: OptionButton
var _battle_weather_option: OptionButton
var _battle_weather_turns_spin: SpinBox

func _build_battle_sections() -> void:
	var controls_content := _add_collapsible_section(battle_sections, "Battle Controls")
	var outcome_btns := HBoxContainer.new()
	outcome_btns.add_theme_constant_override("separation", 4)
	controls_content.add_child(outcome_btns)
	_add_button(outcome_btns, "Force Win", _on_battle_force_win)
	_add_button(outcome_btns, "Force Lose", _on_battle_force_lose)

	# --- HP ---
	var hp_content := _add_collapsible_section(battle_sections, "Creature HP")
	_add_button(hp_content, "Heal Active", _on_battle_heal)

	var hp_player_row := HBoxContainer.new()
	hp_player_row.add_theme_constant_override("separation", 4)
	hp_content.add_child(hp_player_row)
	_add_label(hp_player_row, "Player HP:")
	_battle_player_hp_spin = _add_spinbox(hp_player_row, 0, 999, 100)
	_add_button(hp_player_row, "Set", _on_battle_set_player_hp)

	var hp_enemy_row := HBoxContainer.new()
	hp_enemy_row.add_theme_constant_override("separation", 4)
	hp_content.add_child(hp_enemy_row)
	_add_label(hp_enemy_row, "Enemy HP:")
	_battle_enemy_hp_spin = _add_spinbox(hp_enemy_row, 0, 999, 1)
	_add_button(hp_enemy_row, "Set", _on_battle_set_enemy_hp)

	# --- Status ---
	var status_content := _add_collapsible_section(battle_sections, "Status Effects")
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 4)
	status_content.add_child(status_row)
	_battle_status_side = OptionButton.new()
	_battle_status_side.custom_minimum_size.y = FIELD_H
	_battle_status_side.add_item("Player")
	_battle_status_side.add_item("Enemy")
	_apply_field_style(_battle_status_side)
	status_row.add_child(_battle_status_side)
	_battle_status_option = OptionButton.new()
	_battle_status_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_battle_status_option.custom_minimum_size.y = FIELD_H
	for s in ["(clear)", "burn", "freeze", "paralyze", "poison", "sleep", "confuse"]:
		_battle_status_option.add_item(s)
	_apply_field_style(_battle_status_option)
	status_row.add_child(_battle_status_option)
	_add_button(status_row, "Set", _on_battle_set_status)

	# --- Stat Stages ---
	var stat_content := _add_collapsible_section(battle_sections, "Stat Stages")
	var stat_row := HBoxContainer.new()
	stat_row.add_theme_constant_override("separation", 4)
	stat_content.add_child(stat_row)
	_battle_stat_side = OptionButton.new()
	_battle_stat_side.custom_minimum_size.y = FIELD_H
	_battle_stat_side.add_item("Player")
	_battle_stat_side.add_item("Enemy")
	_apply_field_style(_battle_stat_side)
	stat_row.add_child(_battle_stat_side)
	_battle_stat_option = OptionButton.new()
	_battle_stat_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_battle_stat_option.custom_minimum_size.y = FIELD_H
	for st in ["attack", "defense", "sp_attack", "sp_defense", "speed", "accuracy", "evasion"]:
		_battle_stat_option.add_item(st)
	_apply_field_style(_battle_stat_option)
	stat_row.add_child(_battle_stat_option)
	_battle_stat_value_spin = _add_spinbox(stat_row, -6, 6, 6)
	_add_button(stat_row, "Set", _on_battle_set_stat_stage)

	# --- Field ---
	var field_content := _add_collapsible_section(battle_sections, "Field Effects")
	var field_row := HBoxContainer.new()
	field_row.add_theme_constant_override("separation", 4)
	field_content.add_child(field_row)
	_battle_weather_option = OptionButton.new()
	_battle_weather_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_battle_weather_option.custom_minimum_size.y = FIELD_H
	for bw in ["none", "rain", "sun", "sandstorm", "hail"]:
		_battle_weather_option.add_item(bw)
	_apply_field_style(_battle_weather_option)
	field_row.add_child(_battle_weather_option)
	_add_label(field_row, "Turns:")
	_battle_weather_turns_spin = _add_spinbox(field_row, 1, 10, 5)
	_add_button(field_row, "Set", _on_battle_set_weather)

	var field_btns := HBoxContainer.new()
	field_btns.add_theme_constant_override("separation", 4)
	field_content.add_child(field_btns)
	_add_button(field_btns, "Clear Hazards", _on_battle_clear_hazards)
	_add_button(field_btns, "Max PP", _on_battle_max_pp)

# === UI Helpers ===

func _add_collapsible_section(parent: Control, text: String) -> VBoxContainer:
	_add_separator(parent)
	var header_btn := Button.new()
	header_btn.text = "▾ %s" % text
	header_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header_btn.custom_minimum_size = Vector2(0, 24)
	# Style the section header button
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = SECTION_HEADER_BG
	normal_style.content_margin_left = 6
	normal_style.content_margin_right = 6
	normal_style.content_margin_top = 2
	normal_style.content_margin_bottom = 2
	normal_style.corner_radius_top_left = 2
	normal_style.corner_radius_top_right = 2
	normal_style.corner_radius_bottom_left = 2
	normal_style.corner_radius_bottom_right = 2
	var hover_style := normal_style.duplicate()
	hover_style.bg_color = Color(0.28, 0.28, 0.35, 0.9)
	header_btn.add_theme_stylebox_override("normal", normal_style)
	header_btn.add_theme_stylebox_override("hover", hover_style)
	header_btn.add_theme_stylebox_override("pressed", normal_style)
	header_btn.add_theme_color_override("font_color", SECTION_HEADER_COLOR)
	header_btn.add_theme_color_override("font_hover_color", Color(0.7, 0.88, 1.0))
	header_btn.add_theme_font_size_override("font_size", 14)
	parent.add_child(header_btn)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	parent.add_child(content)

	_section_collapse_map[header_btn] = content
	header_btn.pressed.connect(_on_section_header_pressed.bind(header_btn))
	return content

func _on_section_header_pressed(header_btn: Button) -> void:
	var content: VBoxContainer = _section_collapse_map.get(header_btn)
	if not content:
		return
	content.visible = !content.visible
	var section_name := header_btn.text.substr(2)  # Strip "▾ " or "▸ "
	if content.visible:
		header_btn.text = "▾ %s" % section_name
	else:
		header_btn.text = "▸ %s" % section_name

func _add_section_header(parent: Control, text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", SECTION_HEADER_COLOR)
	lbl.add_theme_font_size_override("font_size", 14)
	parent.add_child(lbl)
	return lbl

func _add_label(parent: Control, text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", LABEL_COLOR)
	parent.add_child(lbl)
	return lbl

func _add_separator(parent: Control) -> void:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", SECTION_GAP)
	sep.add_theme_stylebox_override("separator", _make_separator_style())
	parent.add_child(sep)

func _make_separator_style() -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = SEPARATOR_COLOR
	s.thickness = 1
	return s

func _apply_button_style(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = BTN_NORMAL_BG
	normal.corner_radius_top_left = 3
	normal.corner_radius_top_right = 3
	normal.corner_radius_bottom_left = 3
	normal.corner_radius_bottom_right = 3
	normal.content_margin_left = 6
	normal.content_margin_right = 6
	normal.content_margin_top = 2
	normal.content_margin_bottom = 2
	var hover := normal.duplicate()
	hover.bg_color = BTN_HOVER_BG
	var pressed := normal.duplicate()
	pressed.bg_color = BTN_PRESSED_BG
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", BTN_TEXT_COLOR)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	btn.add_theme_font_size_override("font_size", 12)

func _apply_field_style(control: Control) -> void:
	var field_style := StyleBoxFlat.new()
	field_style.bg_color = FIELD_BG_COLOR
	field_style.border_color = FIELD_BORDER_COLOR
	field_style.border_width_left = 1
	field_style.border_width_right = 1
	field_style.border_width_top = 1
	field_style.border_width_bottom = 1
	field_style.corner_radius_top_left = 3
	field_style.corner_radius_top_right = 3
	field_style.corner_radius_bottom_left = 3
	field_style.corner_radius_bottom_right = 3
	field_style.content_margin_left = 4
	field_style.content_margin_right = 4
	field_style.content_margin_top = 2
	field_style.content_margin_bottom = 2
	var focus_style := field_style.duplicate()
	focus_style.border_color = ACCENT_COLOR
	if control is LineEdit:
		control.add_theme_stylebox_override("normal", field_style)
		control.add_theme_stylebox_override("focus", focus_style)
		control.add_theme_color_override("font_color", FIELD_TEXT_COLOR)
		control.add_theme_color_override("font_placeholder_color", FIELD_PLACEHOLDER_COLOR)
		control.add_theme_color_override("caret_color", ACCENT_COLOR)
		control.add_theme_font_size_override("font_size", 12)
	elif control is OptionButton:
		control.add_theme_stylebox_override("normal", field_style)
		control.add_theme_stylebox_override("hover", focus_style)
		control.add_theme_stylebox_override("pressed", field_style)
		control.add_theme_stylebox_override("focus", focus_style)
		control.add_theme_color_override("font_color", FIELD_TEXT_COLOR)
		control.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
		control.add_theme_font_size_override("font_size", 12)

func _add_button(parent: Control, text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, BTN_H)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_button_style(btn)
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn

func _add_spinbox(parent: Control, min_val: float, max_val: float, default: float) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = min_val
	sb.max_value = max_val
	sb.value = default
	sb.custom_minimum_size = Vector2(60, FIELD_H)
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# SpinBox inner LineEdit styling
	var line := sb.get_line_edit()
	_apply_field_style(line)
	parent.add_child(sb)
	return sb

# === Action Dispatchers ===

var _send_log: Array = []  # For test introspection

func _send(action: String, params: Dictionary = {}) -> void:
	_send_log.append({"action": action, "params": params})
	feedback_label.text = "Sent: %s" % action
	feedback_label.modulate.a = 1.0
	_feedback_fade_timer = 3.0
	NetworkManager.request_debug_action.rpc_id(1, action, params)

# World actions
func _on_set_time() -> void:
	_send("set_time", {"year": int(_year_spin.value), "month": int(_month_spin.value), "day": int(_day_spin.value), "weather": _weather_option.selected})

func _on_advance_day() -> void:
	_send("advance_day")

func _on_set_speed(mult: int) -> void:
	_send("set_time_speed", {"multiplier": mult})

func _on_wild_battle() -> void:
	var sid := _species_field.text.strip_edges()
	if sid == "":
		feedback_label.text = "Enter a species_id first"
		feedback_label.modulate.a = 1.0
		_feedback_fade_timer = 3.0
		return
	_send("wild_battle", {"species_id": sid})

func _on_trainer_battle() -> void:
	if _trainer_option.item_count == 0:
		return
	_send("trainer_battle", {"trainer_id": _trainer_option.get_item_text(_trainer_option.selected)})

func _on_give_item() -> void:
	var iid := _item_field.text.strip_edges()
	if iid == "":
		feedback_label.text = "Enter an item_id first"
		feedback_label.modulate.a = 1.0
		_feedback_fade_timer = 3.0
		return
	_send("give_item", {"item_id": iid, "qty": int(_item_qty_spin.value)})

func _on_give_money() -> void:
	_send("give_money", {"amount": int(_money_spin.value)})

func _on_heal_party() -> void:
	_send("heal_party")

func _on_teleport() -> void:
	_send("teleport", {"x": _teleport_x.value, "y": _teleport_y.value, "z": _teleport_z.value})

func _on_teleport_preset(pos: Vector3) -> void:
	_send("teleport", {"x": pos.x, "y": pos.y, "z": pos.z})

func _on_set_creature_level() -> void:
	_send("set_creature_level", {"party_idx": int(_party_idx_spin.value), "level": int(_level_spin.value)})

func _on_max_all_creatures() -> void:
	_send("max_all_creatures")

func _on_force_evolve() -> void:
	_send("force_evolve", {"party_idx": int(_party_idx_spin.value)})

func _on_unlock_all_recipes() -> void:
	_send("unlock_all_recipes")

func _on_force_grow_plots() -> void:
	_send("force_grow_plots")

func _on_reset_plots() -> void:
	_send("reset_plots")

func _on_complete_quest() -> void:
	var qid := _quest_field.text.strip_edges()
	if qid == "":
		feedback_label.text = "Enter a quest_id first"
		feedback_label.modulate.a = 1.0
		_feedback_fade_timer = 3.0
		return
	_send("complete_quest", {"quest_id": qid})

func _on_reset_quests() -> void:
	_send("reset_quests")

func _on_set_friendship() -> void:
	if _npc_option.item_count == 0:
		return
	_send("set_friendship", {"npc_id": _npc_option.get_item_text(_npc_option.selected), "points": int(_friendship_spin.value)})

func _on_max_all_friendships() -> void:
	_send("max_all_friendships")

func _on_end_excursion() -> void:
	_send("end_excursion")

# Battle actions
func _on_battle_force_win() -> void:
	_send("battle_force_win")

func _on_battle_force_lose() -> void:
	_send("battle_force_lose")

func _on_battle_heal() -> void:
	_send("battle_heal")

func _on_battle_set_player_hp() -> void:
	_send("battle_set_hp", {"side": "player", "hp": int(_battle_player_hp_spin.value)})

func _on_battle_set_enemy_hp() -> void:
	_send("battle_set_hp", {"side": "enemy", "hp": int(_battle_enemy_hp_spin.value)})

func _on_battle_set_status() -> void:
	var side := "player" if _battle_status_side.selected == 0 else "enemy"
	var status_text: String = _battle_status_option.get_item_text(_battle_status_option.selected)
	if status_text == "(clear)":
		status_text = ""
	_send("battle_set_status", {"side": side, "status": status_text})

func _on_battle_set_stat_stage() -> void:
	var side := "player" if _battle_stat_side.selected == 0 else "enemy"
	var stat_name: String = _battle_stat_option.get_item_text(_battle_stat_option.selected)
	_send("battle_set_stat_stage", {"side": side, "stat": stat_name, "value": int(_battle_stat_value_spin.value)})

func _on_battle_set_weather() -> void:
	var weather_name: String = _battle_weather_option.get_item_text(_battle_weather_option.selected)
	_send("battle_set_weather", {"weather": weather_name, "turns": int(_battle_weather_turns_spin.value)})

func _on_battle_clear_hazards() -> void:
	_send("battle_clear_hazards")

func _on_battle_max_pp() -> void:
	_send("battle_max_pp")

# === Debug Result Callback ===

func _on_debug_result(action: String, message: String) -> void:
	feedback_label.text = "[%s] %s" % [action, message]
	feedback_label.modulate.a = 1.0
	_feedback_fade_timer = 4.0
