extends Control

# Creature party tab content for PauseMenu. Full-width cards with vertical
# scrolling. Each card has 4 swipeable panels: Overview, Stats, Moves, Details.
const UITokens = preload("res://scripts/ui/ui_tokens.gd")

const PANEL_COUNT := 4
const SWIPE_THRESHOLD := 40.0

var scroll_container: ScrollContainer
var card_vbox: VBoxContainer

# Per-card panel tracking: card instance -> data
var _card_panel_indices: Dictionary = {}  # PanelContainer -> int (active panel)
var _card_panels: Dictionary = {}         # PanelContainer -> Array[Control]
var _card_dots: Dictionary = {}           # PanelContainer -> Array[Button]

func _ready() -> void:
	UITheme.init()
	_build_ui()
	PlayerData.party_changed.connect(_refresh)

func _build_ui() -> void:
	scroll_container = ScrollContainer.new()
	scroll_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll_container)

	card_vbox = VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 12)
	card_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(card_vbox)

func activate() -> void:
	_refresh()

func deactivate() -> void:
	pass

func _refresh() -> void:
	_card_panel_indices.clear()
	_card_panels.clear()
	_card_dots.clear()
	for child in card_vbox.get_children():
		child.queue_free()
	DataRegistry.ensure_loaded()
	for i in range(PlayerData.party.size()):
		var creature = PlayerData.party[i]
		var card := _build_creature_card(creature, i)
		card_vbox.add_child(card)

func _build_creature_card(creature: Dictionary, idx: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size.y = UITheme.scaled(240)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = UITokens.PAPER_CARD
	style.border_color = UITokens.ACCENT_CHESTNUT
	style.set_corner_radius_all(UITokens.CORNER_RADIUS)
	style.set_border_width_all(2)
	style.content_margin_left = 12
	style.content_margin_top = 8
	style.content_margin_right = 12
	style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", style)

	var card_root := VBoxContainer.new()
	card_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(card_root)

	# Panel host — all 4 panels stacked, only one visible
	var panel_host := Control.new()
	panel_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_host.clip_contents = true
	card_root.add_child(panel_host)

	var species = DataRegistry.get_species(creature.get("species_id", ""))
	var panels: Array = []

	var p0 := _build_overview_panel(creature, species)
	var p1 := _build_stats_panel(creature, species)
	var p2 := _build_moves_panel(creature)
	var p3 := _build_details_panel(creature, idx)

	for p in [p0, p1, p2, p3]:
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel_host.add_child(p)
		panels.append(p)

	# Only first panel visible
	p0.visible = true
	p1.visible = false
	p2.visible = false
	p3.visible = false

	# Swipe gesture on panel_host
	var swipe_start := Vector2.ZERO
	var swiping := false
	var captured_card := card
	panel_host.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					swipe_start = event.position
					swiping = true
				else:
					swiping = false
		elif event is InputEventMouseMotion and swiping:
			var diff: Vector2 = event.position - swipe_start
			if absf(diff.x) > SWIPE_THRESHOLD and absf(diff.x) > absf(diff.y) * 1.5:
				panel_host.accept_event()
				swiping = false
				if diff.x < 0:
					_on_panel_nav(captured_card, 1)
				else:
					_on_panel_nav(captured_card, -1)
	)
	panel_host.mouse_filter = Control.MOUSE_FILTER_STOP

	# Nav bar
	var nav_bar := _build_nav_bar(card, panels)
	card_root.add_child(nav_bar)

	_card_panel_indices[card] = 0
	_card_panels[card] = panels
	return card

# === PANEL BUILDERS ===

func _build_overview_panel(creature: Dictionary, species) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)

	# Left column: color swatch + nickname + level + types
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(left)

	var header := HBoxContainer.new()
	left.add_child(header)
	var color_rect := ColorRect.new()
	color_rect.custom_minimum_size = Vector2(UITheme.scaled(28), UITheme.scaled(28))
	color_rect.color = species.mesh_color if species else Color.GRAY
	header.add_child(color_rect)
	var name_label := Label.new()
	name_label.text = "%s  Lv.%d" % [creature.get("nickname", "???"), creature.get("level", 1)]
	UITheme.style_subheading(name_label)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)

	var types = creature.get("types", [])
	if types.size() > 0:
		var type_label := Label.new()
		var type_parts: Array = []
		for t in types:
			type_parts.append(str(t).capitalize())
		type_label.text = " / ".join(type_parts)
		UITheme.style_caption(type_label)
		left.add_child(type_label)

	# Center: HP bar
	var center := VBoxContainer.new()
	center.add_theme_constant_override("separation", 4)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(center)

	var hp_lbl := Label.new()
	hp_lbl.text = "HP"
	UITheme.style_small(hp_lbl)
	center.add_child(hp_lbl)
	var hp_bar := ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(UITheme.scaled(200), 16)
	hp_bar.show_percentage = false
	hp_bar.max_value = creature.get("max_hp", 1)
	hp_bar.value = creature.get("hp", 0)
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_child(hp_bar)
	var hp_num := Label.new()
	hp_num.text = "%d / %d" % [creature.get("hp", 0), creature.get("max_hp", 1)]
	UITheme.style_small(hp_num)
	center.add_child(hp_num)

	# Right: XP bar
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(right)

	var xp_lbl := Label.new()
	xp_lbl.text = "XP"
	UITheme.style_small(xp_lbl)
	right.add_child(xp_lbl)
	var xp_bar := ProgressBar.new()
	xp_bar.custom_minimum_size = Vector2(UITheme.scaled(200), 14)
	xp_bar.show_percentage = false
	xp_bar.max_value = creature.get("xp_to_next", 100)
	xp_bar.value = creature.get("xp", 0)
	xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(xp_bar)
	var xp_num := Label.new()
	xp_num.text = "%d / %d" % [creature.get("xp", 0), creature.get("xp_to_next", 100)]
	UITheme.style_small(xp_num)
	right.add_child(xp_num)

	return hbox

func _build_stats_panel(creature: Dictionary, species) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)

	# Left: stats grid (3 columns)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	hbox.add_child(left)

	var stats_title := Label.new()
	stats_title.text = "Stats"
	UITheme.style_subheading(stats_title)
	left.add_child(stats_title)

	var stats_grid := GridContainer.new()
	stats_grid.columns = 3
	stats_grid.add_theme_constant_override("h_separation", 16)
	stats_grid.add_theme_constant_override("v_separation", 4)
	left.add_child(stats_grid)
	var stat_pairs: Array = [
		["ATK", creature.get("attack", 0)],
		["DEF", creature.get("defense", 0)],
		["SP.ATK", creature.get("sp_attack", 0)],
		["SP.DEF", creature.get("sp_defense", 0)],
		["SPD", creature.get("speed", 0)],
	]
	for pair in stat_pairs:
		var stat_lbl := Label.new()
		stat_lbl.text = "%s: %d" % [pair[0], pair[1]]
		UITheme.style_small(stat_lbl)
		stats_grid.add_child(stat_lbl)
	# Pad to fill 3 columns
	var remainder := stat_pairs.size() % 3
	if remainder != 0:
		for _i in range(3 - remainder):
			stats_grid.add_child(Control.new())

	# Right: ability
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(right)

	var ability_id = creature.get("ability_id", "")
	if ability_id != "":
		var ability = DataRegistry.get_ability(ability_id)
		var ab_name: String = ability.display_name if ability else ability_id
		var ab_label := Label.new()
		ab_label.text = "Ability: %s" % ab_name
		UITheme.style_small(ab_label)
		right.add_child(ab_label)
		if ability and ability.description != "":
			var ab_desc := Label.new()
			ab_desc.text = ability.description
			UITheme.style_caption(ab_desc)
			ab_desc.add_theme_color_override("font_color", UITokens.INK_SECONDARY)
			ab_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			right.add_child(ab_desc)

	return hbox

func _build_moves_panel(creature: Dictionary) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	var creature_moves = creature.get("moves", [])
	if creature_moves.size() == 0:
		var empty_lbl := Label.new()
		empty_lbl.text = "No moves learned"
		UITheme.style_caption(empty_lbl)
		empty_lbl.add_theme_color_override("font_color", UITokens.INK_DISABLED)
		hbox.add_child(empty_lbl)
		return hbox

	# 2x2 grid of move cards
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(grid)

	var small_fs := UITheme.scaled(UITokens.FONT_SMALL)
	var tiny_fs := UITheme.scaled(UITokens.FONT_TINY)

	for m in creature_moves:
		var move = DataRegistry.get_move(m)
		if move == null:
			continue
		var move_panel := PanelContainer.new()
		move_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ms := StyleBoxFlat.new()
		ms.bg_color = Color(UITokens.PAPER_EDGE.r, UITokens.PAPER_EDGE.g, UITokens.PAPER_EDGE.b, 0.5)
		ms.set_corner_radius_all(4)
		ms.content_margin_left = 6
		ms.content_margin_top = 4
		ms.content_margin_right = 6
		ms.content_margin_bottom = 4
		move_panel.add_theme_stylebox_override("panel", ms)

		var mvbox := VBoxContainer.new()
		mvbox.add_theme_constant_override("separation", 2)
		move_panel.add_child(mvbox)

		# Name + type row
		var header_row := HBoxContainer.new()
		mvbox.add_child(header_row)
		var name_lbl := Label.new()
		name_lbl.text = move.display_name
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.style_small(name_lbl)
		header_row.add_child(name_lbl)
		var type_badge := Label.new()
		type_badge.text = move.type.capitalize()
		UITheme.style_caption(type_badge)
		type_badge.add_theme_font_size_override("font_size", tiny_fs)
		type_badge.add_theme_color_override("font_color", UITokens.ACCENT_HONEY)
		header_row.add_child(type_badge)

		# Core stats line: Category | Pwr | Acc | PP
		var stats_parts: Array = [move.category.capitalize()]
		if move.power > 0:
			stats_parts.append("Pwr:%d" % move.power)
		stats_parts.append("Acc:%d%%" % move.accuracy)
		stats_parts.append("PP:%d" % move.pp)
		if move.priority != 0:
			stats_parts.append("Pri:%+d" % move.priority)
		var stats_lbl := Label.new()
		stats_lbl.text = " | ".join(stats_parts)
		UITheme.style_caption(stats_lbl)
		stats_lbl.add_theme_font_size_override("font_size", small_fs)
		stats_lbl.add_theme_color_override("font_color", UITokens.INK_SECONDARY)
		mvbox.add_child(stats_lbl)

		# Description (if any)
		if move.description != "":
			var desc_lbl := Label.new()
			desc_lbl.text = move.description
			desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			UITheme.style_caption(desc_lbl)
			desc_lbl.add_theme_font_size_override("font_size", tiny_fs)
			desc_lbl.add_theme_color_override("font_color", UITokens.INK_MEDIUM)
			mvbox.add_child(desc_lbl)

		# Special property tags
		var tags := _build_move_tags(move)
		if tags != "":
			var tags_lbl := Label.new()
			tags_lbl.text = tags
			tags_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			UITheme.style_caption(tags_lbl)
			tags_lbl.add_theme_font_size_override("font_size", tiny_fs)
			tags_lbl.add_theme_color_override("font_color", UITokens.ACCENT_CHESTNUT)
			mvbox.add_child(tags_lbl)

		grid.add_child(move_panel)

	return hbox

func _build_move_tags(move: MoveDef) -> String:
	var tags: Array = []

	# Contact
	if move.is_contact:
		tags.append("Contact")

	# Status effect
	if move.status_effect != "":
		if move.status_chance > 0 and move.status_chance < 100:
			tags.append("%d%% %s" % [move.status_chance, move.status_effect.capitalize()])
		elif move.status_chance >= 100:
			tags.append(move.status_effect.capitalize())

	# Self stat changes
	if move.stat_changes.size() > 0:
		var parts: Array = []
		for stat in move.stat_changes:
			var val: int = int(move.stat_changes[stat])
			parts.append("%s%+d" % [stat.to_upper().left(3), val])
		tags.append("Self: %s" % ", ".join(parts))

	# Target stat changes
	if move.target_stat_changes.size() > 0:
		var parts: Array = []
		for stat in move.target_stat_changes:
			var val: int = int(move.target_stat_changes[stat])
			parts.append("%s%+d" % [stat.to_upper().left(3), val])
		tags.append("Target: %s" % ", ".join(parts))

	# Heal / Drain / Recoil
	if move.heal_percent > 0:
		tags.append("Heal %d%%" % int(move.heal_percent))
	if move.drain_percent > 0:
		tags.append("Drain %d%%" % int(move.drain_percent))
	if move.recoil_percent > 0:
		tags.append("Recoil %d%%" % int(move.recoil_percent))

	# Multi-hit
	if move.multi_hit_min > 0:
		if move.multi_hit_min == move.multi_hit_max:
			tags.append("%d hits" % move.multi_hit_min)
		else:
			tags.append("%d-%d hits" % [move.multi_hit_min, move.multi_hit_max])

	# Protection
	if move.is_protection:
		tags.append("Protection")

	# Charging
	if move.is_charging:
		tags.append("Charge move")

	# Weather
	if move.weather_set != "":
		tags.append("Sets %s" % move.weather_set.capitalize())

	# Hazards
	if move.hazard_type != "":
		tags.append("Hazard: %s" % move.hazard_type.capitalize())
	if move.clears_hazards:
		tags.append("Clears hazards")

	# Switching
	if move.switch_after:
		tags.append("Switch after")
	if move.force_switch:
		tags.append("Force switch")

	# Field effects / misc boolean flags
	if move.trick_room:
		tags.append("Trick Room")
	if move.taunt:
		tags.append("Taunt")
	if move.encore:
		tags.append("Encore")
	if move.substitute:
		tags.append("Substitute")
	if move.knock_off:
		tags.append("Knock Off")
	if move.sleep_talk:
		tags.append("Sleep Talk")

	# Crit stage
	if move.self_crit_stage_change != 0:
		tags.append("Crit %+d" % move.self_crit_stage_change)

	return " | ".join(tags)

func _build_details_panel(creature: Dictionary, idx: int) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)

	# Left: held item
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(left)

	var details_title := Label.new()
	details_title.text = "Details"
	UITheme.style_subheading(details_title)
	left.add_child(details_title)

	var held_item_id = creature.get("held_item_id", "")
	var item_hbox := HBoxContainer.new()
	left.add_child(item_hbox)
	var item_label := Label.new()
	if held_item_id != "":
		var item = DataRegistry.get_held_item(held_item_id)
		item_label.text = "Held: %s" % (item.display_name if item else held_item_id)
	else:
		item_label.text = "Held: (none)"
	item_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_small(item_label)
	item_hbox.add_child(item_label)
	if held_item_id != "":
		var unequip_btn := Button.new()
		unequip_btn.text = "Unequip"
		UITheme.style_button(unequip_btn, "secondary")
		var cidx = idx
		unequip_btn.pressed.connect(func(): _unequip_item(cidx))
		item_hbox.add_child(unequip_btn)
	else:
		var equip_btn := Button.new()
		equip_btn.text = "Equip"
		UITheme.style_button(equip_btn, "primary")
		var cidx = idx
		equip_btn.pressed.connect(func(): _show_equip_options(cidx))
		item_hbox.add_child(equip_btn)

	# Center: IVs + EVs
	var center := VBoxContainer.new()
	center.add_theme_constant_override("separation", 4)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(center)

	var ivs = creature.get("ivs", {})
	if ivs.size() > 0:
		var iv_label := Label.new()
		iv_label.text = "IVs: HP:%d ATK:%d DEF:%d\nSPA:%d SPD:%d SPE:%d" % [
			int(ivs.get("hp", 0)), int(ivs.get("attack", 0)), int(ivs.get("defense", 0)),
			int(ivs.get("sp_attack", 0)), int(ivs.get("sp_defense", 0)), int(ivs.get("speed", 0))]
		UITheme.style_small(iv_label)
		iv_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
		iv_label.add_theme_color_override("font_color", UITokens.TEXT_INFO)
		center.add_child(iv_label)

	var evs = creature.get("evs", {})
	if evs.size() > 0:
		var ev_text = "EVs: "
		for stat in evs:
			if int(evs[stat]) > 0:
				ev_text += "%s:%d " % [stat, int(evs[stat])]
		if ev_text != "EVs: ":
			var ev_label := Label.new()
			ev_label.text = ev_text
			UITheme.style_small(ev_label)
			ev_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
			center.add_child(ev_label)

	# Right: bond + relearn
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(right)

	var bond_pts = int(creature.get("bond_points", 0))
	var bond_lvl = int(creature.get("bond_level", 0))
	var personality_text = ""
	var affinities = creature.get("battle_affinities", {})
	if affinities.size() > 0:
		var highest_stat = ""
		var highest_val = -1.0
		for aff_stat in affinities:
			if float(affinities[aff_stat]) > highest_val:
				highest_val = float(affinities[aff_stat])
				highest_stat = aff_stat
		if highest_stat != "":
			var aff_names = {"attack": "Physical Attacker", "sp_attack": "Special Attacker",
				"defense": "Defender", "sp_defense": "Special Defender",
				"speed": "Speedster", "hp": "Endurance"}
			personality_text = "\n%s" % aff_names.get(highest_stat, highest_stat.capitalize())
	var bond_label := Label.new()
	bond_label.text = "Bond: Lv %d (%d pts)%s" % [bond_lvl, bond_pts, personality_text]
	UITheme.style_small(bond_label)
	bond_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
	bond_label.add_theme_color_override("font_color", UITokens.STAMP_GOLD)
	right.add_child(bond_label)

	var relearn_btn := Button.new()
	relearn_btn.text = "Relearn Move"
	relearn_btn.custom_minimum_size.y = 28
	UITheme.style_button(relearn_btn, "secondary")
	var cidx_relearn = idx
	relearn_btn.pressed.connect(func(): _show_relearn_overlay(cidx_relearn))
	right.add_child(relearn_btn)

	return hbox

# === NAV BAR ===

func _build_nav_bar(card: PanelContainer, panels: Array) -> HBoxContainer:
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 4)
	nav.custom_minimum_size.y = UITheme.scaled(28)

	# Left arrow
	var left_btn := Button.new()
	left_btn.text = "<"
	left_btn.custom_minimum_size = Vector2(UITheme.scaled(28), UITheme.scaled(24))
	UITheme.style_button(left_btn, "secondary")
	left_btn.pressed.connect(_on_panel_nav.bind(card, -1))
	nav.add_child(left_btn)

	# Dots
	var dots: Array = []
	for i in PANEL_COUNT:
		var dot := Button.new()
		dot.custom_minimum_size = Vector2(UITheme.scaled(12), UITheme.scaled(12))
		dot.flat = true
		dot.mouse_filter = Control.MOUSE_FILTER_STOP
		_style_dot(dot, i == 0)
		dot.pressed.connect(_on_panel_jump.bind(card, i))
		nav.add_child(dot)
		dots.append(dot)
	_card_dots[card] = dots

	# Right arrow
	var right_btn := Button.new()
	right_btn.text = ">"
	right_btn.custom_minimum_size = Vector2(UITheme.scaled(28), UITheme.scaled(24))
	UITheme.style_button(right_btn, "secondary")
	right_btn.pressed.connect(_on_panel_nav.bind(card, 1))
	nav.add_child(right_btn)

	return nav

# === PANEL SWITCHING ===

func _on_panel_nav(card: PanelContainer, direction: int) -> void:
	var current: int = _card_panel_indices.get(card, 0)
	_switch_panel(card, current + direction)

func _on_panel_jump(card: PanelContainer, index: int) -> void:
	_switch_panel(card, index)

func _switch_panel(card: PanelContainer, new_index: int) -> void:
	new_index = clampi(new_index, 0, PANEL_COUNT - 1)
	var old_index: int = _card_panel_indices.get(card, 0)
	if new_index == old_index:
		return

	var panels: Array = _card_panels.get(card, [])
	if panels.size() != PANEL_COUNT:
		return

	panels[old_index].visible = false
	panels[new_index].visible = true
	_card_panel_indices[card] = new_index

	# Update dots
	var dots: Array = _card_dots.get(card, [])
	for i in dots.size():
		_style_dot(dots[i], i == new_index)

func _style_dot(dot: Button, is_active: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 0
	sb.content_margin_top = 0
	sb.content_margin_right = 0
	sb.content_margin_bottom = 0
	if is_active:
		sb.bg_color = UITokens.ACCENT_CHESTNUT
	else:
		sb.bg_color = UITokens.PAPER_EDGE
		sb.border_color = UITokens.ACCENT_CHESTNUT
		sb.set_border_width_all(1)
	dot.add_theme_stylebox_override("normal", sb)
	dot.add_theme_stylebox_override("hover", sb)
	dot.add_theme_stylebox_override("pressed", sb)
	dot.add_theme_stylebox_override("focus", sb)

# === EQUIP / RELEARN (unchanged) ===

func _unequip_item(creature_idx: int) -> void:
	NetworkManager.request_unequip_held_item.rpc_id(1, creature_idx)

var _equip_panel: PanelContainer = null

func _show_equip_options(creature_idx: int) -> void:
	if _equip_panel:
		_equip_panel.queue_free()
		_equip_panel = null
	DataRegistry.ensure_loaded()
	var available_items := []
	for item_id in PlayerData.inventory:
		var item = DataRegistry.get_held_item(item_id)
		if item and PlayerData.inventory[item_id] > 0:
			available_items.append(item_id)
	if available_items.size() == 0:
		return

	_equip_panel = PanelContainer.new()
	_equip_panel.anchors_preset = Control.PRESET_CENTER
	_equip_panel.custom_minimum_size = Vector2(400, 0)
	UITheme.style_modal(_equip_panel)

	var vbox := VBoxContainer.new()
	_equip_panel.add_child(vbox)

	var title := Label.new()
	title.text = "Equip Held Item"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_subheading(title)
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 200
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var item_list := VBoxContainer.new()
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(item_list)

	for item_id in available_items:
		var item = DataRegistry.get_held_item(item_id)
		if item == null:
			continue
		var btn := Button.new()
		var effect_text := ""
		if item.description != "":
			effect_text = " — " + item.description
		btn.text = "%s (x%d)%s" % [item.display_name, PlayerData.inventory[item_id], effect_text]
		btn.custom_minimum_size.y = 32
		UITheme.style_button(btn, "secondary")
		var captured_id = item_id
		var cidx = creature_idx
		btn.pressed.connect(func():
			NetworkManager.request_equip_held_item.rpc_id(1, cidx, captured_id)
			_equip_panel.queue_free()
			_equip_panel = null
		)
		item_list.add_child(btn)

	var cancel := Button.new()
	cancel.text = "Cancel"
	UITheme.style_button(cancel, "danger")
	cancel.pressed.connect(func():
		_equip_panel.queue_free()
		_equip_panel = null
	)
	vbox.add_child(cancel)
	add_child(_equip_panel)

var _relearn_panel: PanelContainer = null

func _show_relearn_overlay(creature_idx: int) -> void:
	if _relearn_panel:
		_relearn_panel.queue_free()
	if creature_idx >= PlayerData.party.size():
		return
	DataRegistry.ensure_loaded()
	var creature = PlayerData.party[creature_idx]
	var species_id = creature.get("species_id", "")
	var species = DataRegistry.get_species(species_id)
	if species == null:
		return
	var current_level = int(creature.get("level", 1))
	var current_moves = creature.get("moves", [])
	if current_moves is PackedStringArray:
		current_moves = Array(current_moves)

	var learnable: Array = []
	var learnset = species.learnset if species else {}
	for level_str in learnset:
		var lvl = int(level_str)
		if lvl <= current_level:
			var move_id = learnset[level_str]
			if move_id not in current_moves and move_id not in learnable:
				learnable.append(move_id)
	if learnable.size() == 0:
		return

	_relearn_panel = PanelContainer.new()
	_relearn_panel.anchors_preset = Control.PRESET_CENTER
	_relearn_panel.custom_minimum_size = Vector2(450, 0)
	UITheme.style_modal(_relearn_panel)
	var vbox := VBoxContainer.new()
	_relearn_panel.add_child(vbox)

	var title := Label.new()
	title.text = "Relearn Move for %s" % creature.get("nickname", "???")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_subheading(title)
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "Select a move to learn, then pick a slot to replace."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_small(sub)
	sub.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
	vbox.add_child(sub)

	for move_id in learnable:
		var move = DataRegistry.get_move(move_id)
		if move == null:
			continue
		var btn := Button.new()
		var power_text = "Pwr:%d" % move.power if move.power > 0 else "Status"
		btn.text = "%s — %s | %s | %s" % [move.display_name, move.type.capitalize(), move.category.capitalize(), power_text]
		btn.custom_minimum_size.y = 32
		UITheme.style_button(btn, "secondary")
		var mid = move_id
		var cidx = creature_idx
		btn.pressed.connect(func(): _show_relearn_replace(cidx, mid))
		vbox.add_child(btn)

	var cancel := Button.new()
	cancel.text = "Cancel"
	UITheme.style_button(cancel, "danger")
	cancel.pressed.connect(func():
		_relearn_panel.queue_free()
		_relearn_panel = null
	)
	vbox.add_child(cancel)
	add_child(_relearn_panel)

func _show_relearn_replace(creature_idx: int, new_move_id: String) -> void:
	if _relearn_panel:
		_relearn_panel.queue_free()
		_relearn_panel = null
	if creature_idx >= PlayerData.party.size():
		return
	DataRegistry.ensure_loaded()
	var creature = PlayerData.party[creature_idx]
	var current_moves = creature.get("moves", [])
	var new_move = DataRegistry.get_move(new_move_id)
	if new_move == null:
		return

	_relearn_panel = PanelContainer.new()
	_relearn_panel.anchors_preset = Control.PRESET_CENTER
	_relearn_panel.custom_minimum_size = Vector2(450, 0)
	UITheme.style_modal(_relearn_panel)
	var vbox := VBoxContainer.new()
	_relearn_panel.add_child(vbox)

	var title := Label.new()
	title.text = "Replace which move with %s?" % new_move.display_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_subheading(title)
	vbox.add_child(title)

	for i in range(current_moves.size()):
		var old_move = DataRegistry.get_move(current_moves[i])
		if old_move == null:
			continue
		var btn := Button.new()
		var old_power = "Pwr:%d" % old_move.power if old_move.power > 0 else "Status"
		btn.text = "%s — %s | %s" % [old_move.display_name, old_move.type.capitalize(), old_power]
		btn.custom_minimum_size.y = 32
		UITheme.style_button(btn, "secondary")
		var replace_idx = i
		var mid = new_move_id
		var cidx = creature_idx
		btn.pressed.connect(func():
			NetworkManager.request_relearn_move.rpc_id(1, cidx, mid, replace_idx)
			_relearn_panel.queue_free()
			_relearn_panel = null
		)
		vbox.add_child(btn)

	var cancel := Button.new()
	cancel.text = "Cancel"
	UITheme.style_button(cancel, "danger")
	cancel.pressed.connect(func():
		_relearn_panel.queue_free()
		_relearn_panel = null
	)
	vbox.add_child(cancel)
	add_child(_relearn_panel)
