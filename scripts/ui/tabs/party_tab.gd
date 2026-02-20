extends Control

# Creature party tab content for PauseMenu. Ported from party_ui.gd.
const UITokens = preload("res://scripts/ui/ui_tokens.gd")

var creature_list: VBoxContainer
var scroll_container: ScrollContainer

func _ready() -> void:
	UITheme.init()
	_build_ui()
	PlayerData.party_changed.connect(_refresh)

func _build_ui() -> void:
	scroll_container = ScrollContainer.new()
	scroll_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll_container)

	creature_list = VBoxContainer.new()
	creature_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(creature_list)

func activate() -> void:
	_refresh()

func deactivate() -> void:
	pass

func _refresh() -> void:
	for child in creature_list.get_children():
		child.queue_free()
	for i in range(PlayerData.party.size()):
		var creature = PlayerData.party[i]
		var panel := PanelContainer.new()
		UITheme.style_card(panel)
		creature_list.add_child(panel)
		var hbox := HBoxContainer.new()
		panel.add_child(hbox)
		DataRegistry.ensure_loaded()
		var species = DataRegistry.get_species(creature.get("species_id", ""))
		var color_rect := ColorRect.new()
		color_rect.custom_minimum_size = Vector2(30, 30)
		color_rect.color = species.mesh_color if species else Color.GRAY
		hbox.add_child(color_rect)
		var vbox := VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(vbox)
		var name_label := Label.new()
		name_label.text = "%s  Lv.%d" % [creature.get("nickname", "???"), creature.get("level", 1)]
		UITheme.style_body(name_label)
		vbox.add_child(name_label)
		var hp_label := Label.new()
		hp_label.text = "HP: %d/%d" % [creature.get("hp", 0), creature.get("max_hp", 1)]
		UITheme.style_small(hp_label)
		vbox.add_child(hp_label)
		# XP bar
		var xp_hbox := HBoxContainer.new()
		vbox.add_child(xp_hbox)
		var xp_label := Label.new()
		xp_label.text = "XP: "
		UITheme.style_small(xp_label)
		xp_hbox.add_child(xp_label)
		var xp_bar := ProgressBar.new()
		xp_bar.custom_minimum_size = Vector2(100, 12)
		xp_bar.show_percentage = false
		xp_bar.max_value = creature.get("xp_to_next", 100)
		xp_bar.value = creature.get("xp", 0)
		xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		xp_hbox.add_child(xp_bar)
		var xp_num := Label.new()
		xp_num.text = "%d/%d" % [creature.get("xp", 0), creature.get("xp_to_next", 100)]
		UITheme.style_small(xp_num)
		xp_hbox.add_child(xp_num)
		# Stats
		var stats_label := Label.new()
		stats_label.text = "ATK:%d DEF:%d SPATK:%d SPDEF:%d SPD:%d" % [
			creature.get("attack", 0), creature.get("defense", 0),
			creature.get("sp_attack", 0), creature.get("sp_defense", 0),
			creature.get("speed", 0)]
		UITheme.style_small(stats_label)
		vbox.add_child(stats_label)
		# Types
		var types_label := Label.new()
		var types = creature.get("types", [])
		types_label.text = "Types: %s" % ", ".join(PackedStringArray(types))
		UITheme.style_small(types_label)
		vbox.add_child(types_label)
		# Ability
		var ability_id = creature.get("ability_id", "")
		if ability_id != "":
			var ability = DataRegistry.get_ability(ability_id)
			var ability_label := Label.new()
			ability_label.text = "Ability: %s" % (ability.display_name if ability else ability_id)
			UITheme.style_small(ability_label)
			vbox.add_child(ability_label)
		# Held item
		var held_item_id = creature.get("held_item_id", "")
		var item_hbox := HBoxContainer.new()
		vbox.add_child(item_hbox)
		var item_label := Label.new()
		if held_item_id != "":
			var item = DataRegistry.get_held_item(held_item_id)
			item_label.text = "Held: %s" % (item.display_name if item else held_item_id)
		else:
			item_label.text = "Held: (none)"
		item_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_hbox.add_child(item_label)
		UITheme.style_small(item_label)
		if held_item_id != "":
			var unequip_btn := Button.new()
			unequip_btn.text = "Unequip"
			UITheme.style_button(unequip_btn, "secondary")
			var cidx = i
			unequip_btn.pressed.connect(func(): _unequip_item(cidx))
			item_hbox.add_child(unequip_btn)
		else:
			var equip_btn := Button.new()
			equip_btn.text = "Equip"
			UITheme.style_button(equip_btn, "primary")
			var cidx = i
			equip_btn.pressed.connect(func(): _show_equip_options(cidx))
			item_hbox.add_child(equip_btn)
		# Moves
		var moves_text = "Moves: "
		var creature_moves = creature.get("moves", [])
		for m in creature_moves:
			var move = DataRegistry.get_move(m)
			if move:
				moves_text += move.display_name + ", "
		var moves_label := Label.new()
		moves_label.text = moves_text.rstrip(", ")
		UITheme.style_small(moves_label)
		vbox.add_child(moves_label)
		# IVs
		var ivs = creature.get("ivs", {})
		if ivs.size() > 0:
			var iv_label := Label.new()
			iv_label.text = "IVs: HP:%d ATK:%d DEF:%d SPA:%d SPD:%d SPE:%d" % [
				int(ivs.get("hp", 0)), int(ivs.get("attack", 0)), int(ivs.get("defense", 0)),
				int(ivs.get("sp_attack", 0)), int(ivs.get("sp_defense", 0)), int(ivs.get("speed", 0))]
			UITheme.style_small(iv_label)
			iv_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
			iv_label.add_theme_color_override("font_color", UITokens.TEXT_INFO)
			vbox.add_child(iv_label)
		# EVs
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
				vbox.add_child(ev_label)
		# Bond
		var bond_pts = int(creature.get("bond_points", 0))
		var bond_lvl = int(creature.get("bond_level", 0))
		var bond_label := Label.new()
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
				personality_text = " - %s" % aff_names.get(highest_stat, highest_stat.capitalize())
		bond_label.text = "Bond: Level %d (%d pts)%s" % [bond_lvl, bond_pts, personality_text]
		UITheme.style_small(bond_label)
		bond_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
		bond_label.add_theme_color_override("font_color", UITokens.STAMP_GOLD)
		vbox.add_child(bond_label)
		# Relearn Move button
		var relearn_btn := Button.new()
		relearn_btn.text = "Relearn Move"
		relearn_btn.custom_minimum_size.y = 28
		UITheme.style_button(relearn_btn, "secondary")
		var cidx_relearn = i
		relearn_btn.pressed.connect(func(): _show_relearn_overlay(cidx_relearn))
		vbox.add_child(relearn_btn)

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
