extends Control

# Journal tab content for PauseMenu (formerly Compendium). Includes Items,
# Creatures, Fishing, and Stats sub-tabs with card-grid layout.
# Cards flip in-place on click to reveal details on the back.
const UITokens = preload("res://scripts/ui/ui_tokens.gd")

var tab_bar: TabBar
var count_label: Label
var content_scroll: ScrollContainer
var card_grid: GridContainer
var filter_bar: HBoxContainer

var _current_tab: int = 0
var _current_filter: String = "all"

# Card flip state
var _flipped_cards: Dictionary = {}   # card -> bool
var _card_fronts: Dictionary = {}     # card -> VBoxContainer
var _card_backs: Dictionary = {}      # card -> VBoxContainer

const ITEM_FILTERS = ["all", "ingredient", "food", "tool", "held_item", "battle_item", "recipe_scroll"]
const FILTER_LABELS = {"all": "All", "ingredient": "Ingredients", "food": "Foods", "tool": "Tools", "held_item": "Held Items", "battle_item": "Battle Items", "recipe_scroll": "Scrolls"}

const FISH_FILTERS: Array = ["all", "pond", "river", "ocean"]
const FISH_FILTER_LABELS: Dictionary = {"all": "All", "pond": "Pond", "river": "River", "ocean": "Ocean"}

const MOVEMENT_HINTS: Dictionary = {
	"smooth": "Floating",
	"dart": "Darting",
	"sinker": "Deep",
	"mixed": "Tricky",
}

const STAT_SECTIONS = {
	"Battle": [
		["battles_fought", "Battles Fought"],
		["battles_won", "Battles Won"],
		["battles_lost", "Battles Lost"],
		["wild_battles_fought", "Wild Battles"],
		["trainer_battles_fought", "Trainer Battles"],
		["trainer_battles_won", "Trainer Battles Won"],
		["pvp_battles_fought", "PvP Battles"],
		["pvp_wins", "PvP Wins"],
		["pvp_losses", "PvP Losses"],
		["creatures_fainted", "Creatures Fainted"],
		["player_defeats", "Player Defeats"],
		["total_xp_gained", "Total XP Gained"],
	],
	"Economy": [
		["money_earned", "Money Earned"],
		["money_spent", "Money Spent"],
		["items_crafted", "Items Crafted"],
		["items_bought", "Items Bought"],
		["items_sold", "Items Sold"],
		["trades_completed", "Trades Completed"],
	],
	"Social": [
		["npc_conversations", "NPC Conversations"],
		["gifts_given", "Gifts Given"],
		["quests_completed_side", "Side Quests Completed"],
		["quests_completed_main", "Main Quests Completed"],
		["quests_completed_daily", "Daily Quests Completed"],
		["quests_completed_weekly", "Weekly Quests Completed"],
	],
	"Farming": [
		["crops_planted", "Crops Planted"],
		["crops_harvested", "Crops Harvested"],
	],
	"Exploration": [
		["locations_discovered", "Locations Discovered"],
		["days_played", "Days Played"],
	],
}

func _ready() -> void:
	UITheme.init()
	_build_ui()
	PlayerData.compendium_changed.connect(_refresh)
	PlayerData.stats_changed.connect(_refresh)
	if PlayerData.has_signal("fishing_log_changed"):
		PlayerData.fishing_log_changed.connect(_refresh)

func _build_ui() -> void:
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(main_vbox)

	# Title + count row
	var title_row := HBoxContainer.new()
	main_vbox.add_child(title_row)
	var title := Label.new()
	title.text = "Journal"
	UITheme.style_subheading(title)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	count_label = Label.new()
	UITheme.style_small(count_label)
	count_label.add_theme_color_override("font_color", UITokens.INK_MEDIUM)
	title_row.add_child(count_label)

	# Tab bar
	tab_bar = TabBar.new()
	tab_bar.add_tab("Items")
	tab_bar.add_tab("Creatures")
	tab_bar.add_tab("Fishing")
	tab_bar.add_tab("Stats")
	tab_bar.tab_changed.connect(_on_tab_changed)
	main_vbox.add_child(tab_bar)

	# Filter bar (context-dependent per sub-tab)
	filter_bar = HBoxContainer.new()
	main_vbox.add_child(filter_bar)

	# Content area — full width, no split
	content_scroll = ScrollContainer.new()
	content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(content_scroll)

	card_grid = GridContainer.new()
	card_grid.columns = 4
	card_grid.add_theme_constant_override("h_separation", 8)
	card_grid.add_theme_constant_override("v_separation", 8)
	card_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.add_child(card_grid)

func activate() -> void:
	NetworkManager.request_compendium_sync.rpc_id(1)
	var fishing_mgr = get_node_or_null("/root/Main/GameWorld/FishingManager")
	if fishing_mgr:
		fishing_mgr.request_fishing_log_sync.rpc_id(1)
	_refresh()

func deactivate() -> void:
	pass

func _on_tab_changed(tab: int) -> void:
	_current_tab = tab
	_current_filter = "all"
	_refresh()

func _on_filter_pressed(filter_id: String) -> void:
	_current_filter = filter_id
	_refresh()

func _refresh() -> void:
	_clear_children(card_grid)
	_flipped_cards.clear()
	_card_fronts.clear()
	_card_backs.clear()
	_rebuild_filter_bar()
	match _current_tab:
		0:
			card_grid.columns = 4
			_refresh_items()
		1:
			card_grid.columns = 4
			_refresh_creatures()
		2:
			card_grid.columns = 4
			_refresh_fishing()
		3:
			card_grid.columns = 1
			_refresh_stats()

func _rebuild_filter_bar() -> void:
	_clear_children(filter_bar)
	if _current_tab == 0:
		filter_bar.visible = true
		for filter_id in ITEM_FILTERS:
			var btn := Button.new()
			btn.text = FILTER_LABELS.get(filter_id, filter_id)
			btn.custom_minimum_size.x = 80
			UITheme.style_button(btn, "secondary")
			btn.pressed.connect(_on_filter_pressed.bind(filter_id))
			filter_bar.add_child(btn)
	elif _current_tab == 2:
		filter_bar.visible = true
		for filter_id in FISH_FILTERS:
			var btn := Button.new()
			btn.text = FISH_FILTER_LABELS.get(filter_id, filter_id)
			btn.custom_minimum_size.x = 70
			UITheme.style_button(btn, "secondary")
			btn.pressed.connect(_on_filter_pressed.bind(filter_id))
			filter_bar.add_child(btn)
	else:
		filter_bar.visible = false

func _clear_children(node: Control) -> void:
	for child in node.get_children():
		child.queue_free()

# === SHARED CARD HELPERS ===

func _make_card_shell(is_locked: bool, border_color: Color = UITokens.ACCENT_CHESTNUT) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size.y = UITheme.scaled(140)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	if is_locked:
		style.bg_color = UITokens.PAPER_EDGE
		style.border_color = Color(border_color.r, border_color.g, border_color.b, 0.3)
	else:
		style.bg_color = UITokens.PAPER_CARD
		style.border_color = border_color
	style.set_corner_radius_all(UITokens.CORNER_RADIUS)
	style.set_border_width_all(1)
	style.content_margin_left = 4
	style.content_margin_top = 4
	style.content_margin_right = 4
	style.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", style)
	return card

func _add_flip_overlay(card: PanelContainer, front: VBoxContainer, back: VBoxContainer) -> void:
	back.visible = false
	_card_fronts[card] = front
	_card_backs[card] = back
	_flipped_cards[card] = false
	var overlay := Button.new()
	overlay.flat = true
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var captured_card := card
	overlay.pressed.connect(func(): _on_card_clicked(captured_card))
	card.add_child(overlay)

func _on_card_clicked(card: PanelContainer) -> void:
	var is_flipped: bool = _flipped_cards.get(card, false)
	_card_fronts[card].visible = is_flipped
	_card_backs[card].visible = not is_flipped
	_flipped_cards[card] = not is_flipped

# === ITEMS TAB ===

func _refresh_items() -> void:
	DataRegistry.ensure_loaded()
	var unlocked: Array = PlayerData.compendium.get("items", [])

	var all_items: Array = []
	for item_id in DataRegistry.ingredients:
		all_items.append(item_id)
	for item_id in DataRegistry.foods:
		all_items.append(item_id)
	for item_id in DataRegistry.tools:
		all_items.append(item_id)
	for item_id in DataRegistry.held_items:
		all_items.append(item_id)
	for item_id in DataRegistry.battle_items:
		all_items.append(item_id)
	for item_id in DataRegistry.recipe_scrolls:
		all_items.append(item_id)

	var filtered: Array = []
	var unlocked_count: int = 0
	for item_id in all_items:
		var info = DataRegistry.get_item_display_info(item_id)
		if _current_filter != "all" and info.get("category", "") != _current_filter:
			continue
		filtered.append({"item_id": item_id, "info": info, "unlocked": item_id in unlocked})
		if item_id in unlocked:
			unlocked_count += 1

	filtered.sort_custom(func(a, b):
		if a.unlocked != b.unlocked:
			return a.unlocked
		return a.info.display_name < b.info.display_name
	)

	var total = filtered.size()
	count_label.text = "Items: %d/%d" % [unlocked_count, total]

	for entry in filtered:
		var is_unlocked: bool = entry.unlocked
		var card := _make_card_shell(not is_unlocked)

		# Front
		var front := _build_item_front(entry, is_unlocked)
		card.add_child(front)

		# Back
		var back := _build_card_back_items(entry, is_unlocked)
		card.add_child(back)

		_add_flip_overlay(card, front, back)
		card_grid.add_child(card)

func _build_item_front(entry: Dictionary, is_unlocked: bool) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)

	if is_unlocked:
		var icon := UITheme.create_item_icon(entry.info, 48)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(icon)
	else:
		var placeholder := ColorRect.new()
		placeholder.custom_minimum_size = Vector2(UITheme.scaled(48), UITheme.scaled(48))
		placeholder.color = Color(UITokens.INK_DISABLED.r, UITokens.INK_DISABLED.g, UITokens.INK_DISABLED.b, 0.3)
		placeholder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(placeholder)

	var name_lbl := Label.new()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_caption(name_lbl)
	name_lbl.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_SMALL))
	if is_unlocked:
		name_lbl.text = entry.info.display_name
	else:
		name_lbl.text = "???"
		name_lbl.add_theme_color_override("font_color", UITokens.INK_DISABLED)
	vbox.add_child(name_lbl)

	if is_unlocked:
		var cat_lbl := Label.new()
		cat_lbl.text = entry.info.get("category", "").replace("_", " ").capitalize()
		cat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UITheme.style_caption(cat_lbl)
		cat_lbl.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
		cat_lbl.add_theme_color_override("font_color", UITokens.INK_SECONDARY)
		vbox.add_child(cat_lbl)

	return vbox

func _build_card_back_items(entry: Dictionary, is_unlocked: bool) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)

	if not is_unlocked:
		var msg := Label.new()
		msg.text = "Not yet\ndiscovered."
		msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UITheme.style_caption(msg)
		msg.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
		msg.add_theme_color_override("font_color", UITokens.INK_DISABLED)
		vbox.add_child(msg)
		return vbox

	# Larger icon
	var icon := UITheme.create_item_icon(entry.info, 48)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(icon)

	# Name
	var name_lbl := Label.new()
	name_lbl.text = entry.info.display_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_caption(name_lbl)
	name_lbl.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_SMALL))
	vbox.add_child(name_lbl)

	# Category
	var cat_lbl := Label.new()
	cat_lbl.text = entry.info.get("category", "").replace("_", " ").capitalize()
	cat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_caption(cat_lbl)
	cat_lbl.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
	cat_lbl.add_theme_color_override("font_color", UITokens.INK_SECONDARY)
	vbox.add_child(cat_lbl)

	# Sell price
	var price := DataRegistry.get_sell_price(entry.item_id)
	if price > 0:
		var price_lbl := Label.new()
		price_lbl.text = "$%d" % price
		price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UITheme.style_caption(price_lbl)
		price_lbl.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
		price_lbl.add_theme_color_override("font_color", UITokens.STAMP_GOLD)
		vbox.add_child(price_lbl)

	return vbox

# === CREATURES TAB ===

func _refresh_creatures() -> void:
	DataRegistry.ensure_loaded()
	var seen: Array = PlayerData.compendium.get("creatures_seen", [])
	var owned: Array = PlayerData.compendium.get("creatures_owned", [])

	var all_species: Array = DataRegistry.species.keys()
	all_species.sort()

	var seen_count: int = 0
	var owned_count: int = 0
	for sid in all_species:
		if sid in seen:
			seen_count += 1
		if sid in owned:
			owned_count += 1

	count_label.text = "Creatures: %d/%d seen, %d/%d owned" % [seen_count, all_species.size(), owned_count, all_species.size()]

	for species_id in all_species:
		var sp = DataRegistry.get_species(species_id)
		if sp == null:
			continue
		var is_owned: bool = species_id in owned
		var is_seen: bool = species_id in seen

		var card: PanelContainer
		if is_owned:
			card = _make_card_shell(false, UITokens.ACCENT_CHESTNUT)
		elif is_seen:
			card = _make_card_shell(false, Color.GRAY)
		else:
			card = _make_card_shell(true)

		# Front
		var front := _build_creature_front(sp, is_owned, is_seen)
		card.add_child(front)

		# Back
		var back := _build_card_back_creature(species_id, sp, is_owned, is_seen)
		card.add_child(back)

		_add_flip_overlay(card, front, back)
		card_grid.add_child(card)

func _build_creature_front(sp: CreatureSpecies, is_owned: bool, is_seen: bool) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)

	var icon_rect := ColorRect.new()
	icon_rect.custom_minimum_size = Vector2(UITheme.scaled(48), UITheme.scaled(48))
	icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if is_owned:
		icon_rect.color = sp.mesh_color if sp.mesh_color else Color.GRAY
	elif is_seen:
		icon_rect.color = Color(sp.mesh_color.r, sp.mesh_color.g, sp.mesh_color.b, 0.4) if sp.mesh_color else Color(0.5, 0.5, 0.5, 0.4)
	else:
		icon_rect.color = Color(0.15, 0.12, 0.1, 0.5)
	vbox.add_child(icon_rect)

	var name_lbl := Label.new()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_caption(name_lbl)
	name_lbl.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_SMALL))
	if is_seen or is_owned:
		name_lbl.text = sp.display_name
	else:
		name_lbl.text = "???"
		name_lbl.add_theme_color_override("font_color", UITokens.INK_DISABLED)
	vbox.add_child(name_lbl)

	if is_seen or is_owned:
		var type_lbl := Label.new()
		var type_parts: Array = []
		for t in sp.types:
			type_parts.append(str(t).capitalize())
		type_lbl.text = " / ".join(type_parts)
		type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UITheme.style_caption(type_lbl)
		type_lbl.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
		type_lbl.add_theme_color_override("font_color", UITokens.INK_SECONDARY)
		vbox.add_child(type_lbl)

	return vbox

func _build_card_back_creature(species_id: String, sp: CreatureSpecies, is_owned: bool, is_seen: bool) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 1)

	if not is_seen and not is_owned:
		var msg := Label.new()
		msg.text = "Not yet\nencountered."
		msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UITheme.style_caption(msg)
		msg.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
		msg.add_theme_color_override("font_color", UITokens.INK_DISABLED)
		vbox.add_child(msg)
		return vbox

	if is_seen and not is_owned:
		# Type info
		var type_lbl := Label.new()
		var type_parts: Array = []
		for t in sp.types:
			type_parts.append(str(t).capitalize())
		type_lbl.text = " / ".join(type_parts)
		type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UITheme.style_caption(type_lbl)
		type_lbl.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
		vbox.add_child(type_lbl)
		var hint := Label.new()
		hint.text = "Own to see\nfull details"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UITheme.style_caption(hint)
		hint.add_theme_font_size_override("font_size", UITheme.scaled(9))
		hint.add_theme_color_override("font_color", UITokens.INK_SECONDARY)
		vbox.add_child(hint)
		return vbox

	# Owned — show base stats in 3-column grid
	var small_fs := UITheme.scaled(UITokens.FONT_SMALL)
	var tiny_fs := UITheme.scaled(UITokens.FONT_TINY)
	var stats_grid := GridContainer.new()
	stats_grid.columns = 3
	stats_grid.add_theme_constant_override("h_separation", 8)
	stats_grid.add_theme_constant_override("v_separation", 2)
	var stat_pairs: Array = [
		["HP", sp.base_hp], ["ATK", sp.base_attack], ["DEF", sp.base_defense],
		["SPA", sp.base_sp_attack], ["SPD", sp.base_sp_defense], ["SPE", sp.base_speed],
	]
	for pair in stat_pairs:
		var lbl := Label.new()
		lbl.text = "%s: %d" % [pair[0], pair[1]]
		UITheme.style_caption(lbl)
		lbl.add_theme_font_size_override("font_size", small_fs)
		stats_grid.add_child(lbl)
	vbox.add_child(stats_grid)

	# Ability + description
	if sp.ability_ids.size() > 0:
		var ab = DataRegistry.get_ability(sp.ability_ids[0])
		if ab:
			var ab_lbl := Label.new()
			ab_lbl.text = ab.display_name
			ab_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			UITheme.style_caption(ab_lbl)
			ab_lbl.add_theme_font_size_override("font_size", small_fs)
			ab_lbl.add_theme_color_override("font_color", UITokens.STAMP_GOLD)
			vbox.add_child(ab_lbl)
			if ab.description != "":
				var ab_desc := Label.new()
				ab_desc.text = ab.description
				ab_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				ab_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				UITheme.style_caption(ab_desc)
				ab_desc.add_theme_font_size_override("font_size", tiny_fs)
				ab_desc.add_theme_color_override("font_color", UITokens.INK_SECONDARY)
				vbox.add_child(ab_desc)

	# Evolution info
	if sp.evolves_to != "":
		var evo_sp = DataRegistry.get_species(sp.evolves_to)
		var evo_name: String = evo_sp.display_name if evo_sp else sp.evolves_to
		var evo_lbl := Label.new()
		evo_lbl.text = "-> %s Lv%d" % [evo_name, sp.evolution_level]
		evo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UITheme.style_caption(evo_lbl)
		evo_lbl.add_theme_font_size_override("font_size", tiny_fs)
		evo_lbl.add_theme_color_override("font_color", UITokens.INK_SECONDARY)
		vbox.add_child(evo_lbl)

	# Rarity
	if sp.rarity != "" and sp.rarity != "common":
		var rarity_lbl := Label.new()
		rarity_lbl.text = sp.rarity.capitalize()
		rarity_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UITheme.style_caption(rarity_lbl)
		rarity_lbl.add_theme_font_size_override("font_size", tiny_fs)
		rarity_lbl.add_theme_color_override("font_color", UITokens.ACCENT_HONEY)
		vbox.add_child(rarity_lbl)

	return vbox

# === FISHING TAB ===

func _refresh_fishing() -> void:
	DataRegistry.ensure_loaded()
	var catches: Dictionary = PlayerData.fishing_log.get("catches", {})

	var all_fish: Dictionary = {}
	for table_id in DataRegistry.fishing_tables:
		var table: FishingTable = DataRegistry.fishing_tables[table_id]
		for entry in table.entries:
			var fid: String = entry.get("fish_id", "")
			if fid == "":
				continue
			if fid not in all_fish:
				all_fish[fid] = {
					"difficulty": entry.get("difficulty", 1),
					"movement_type": entry.get("movement_type", "smooth"),
					"min_rod_tier": entry.get("min_rod_tier", 0),
					"season": entry.get("season", ""),
					"tables": [],
				}
			if table_id not in all_fish[fid]["tables"]:
				all_fish[fid]["tables"].append(table_id)

	var filtered_fish: Array = []
	for fid in all_fish:
		if _current_filter != "all":
			if _current_filter not in all_fish[fid]["tables"]:
				continue
		filtered_fish.append(fid)
	filtered_fish.sort()

	var caught_count: int = 0
	for fid in filtered_fish:
		if fid in catches:
			caught_count += 1
	count_label.text = "%d/%d species" % [caught_count, filtered_fish.size()]

	for fid in filtered_fish:
		var is_caught: bool = fid in catches
		var fish_data: Dictionary = all_fish[fid]
		var catch_data: Dictionary = catches.get(fid, {})
		var card := _make_card_shell(not is_caught)

		# Front
		var front := _build_fish_front(fid, fish_data, is_caught, catch_data)
		card.add_child(front)

		# Back
		var back := _build_card_back_fish(fid, fish_data, is_caught, catch_data)
		card.add_child(back)

		_add_flip_overlay(card, front, back)
		card_grid.add_child(card)

func _build_fish_front(fish_id: String, fish_data: Dictionary, is_caught: bool, catch_data: Dictionary) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)

	# Icon
	if is_caught:
		var info := DataRegistry.get_item_display_info(fish_id)
		if not info.is_empty():
			var icon := UITheme.create_item_icon(info, 48)
			icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			vbox.add_child(icon)
		else:
			var placeholder := Control.new()
			placeholder.custom_minimum_size = Vector2(UITheme.scaled(48), UITheme.scaled(48))
			vbox.add_child(placeholder)
	else:
		var placeholder := ColorRect.new()
		placeholder.custom_minimum_size = Vector2(UITheme.scaled(48), UITheme.scaled(48))
		placeholder.color = Color(UITokens.INK_DISABLED.r, UITokens.INK_DISABLED.g, UITokens.INK_DISABLED.b, 0.3)
		placeholder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(placeholder)

	# Name
	var name_label := Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_caption(name_label)
	name_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_SMALL))
	if is_caught:
		var fish_def = DataRegistry.get_ingredient(fish_id)
		name_label.text = fish_def.display_name if fish_def else fish_id.capitalize()
	else:
		name_label.text = "???"
		name_label.add_theme_color_override("font_color", UITokens.INK_DISABLED)
	vbox.add_child(name_label)

	# Stars
	var difficulty: int = fish_data.get("difficulty", 1)
	var stars_text := ""
	for s_i in 5:
		if s_i < difficulty:
			stars_text += "\u2605"
		else:
			stars_text += "\u2606"
	var stars_label := Label.new()
	stars_label.text = stars_text
	stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_caption(stars_label)
	stars_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
	if is_caught:
		stars_label.add_theme_color_override("font_color", UITokens.ACCENT_HONEY)
	else:
		stars_label.add_theme_color_override("font_color", UITokens.INK_DISABLED)
	vbox.add_child(stars_label)

	return vbox

func _build_card_back_fish(fish_id: String, fish_data: Dictionary, is_caught: bool, catch_data: Dictionary) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	var small_fs := UITheme.scaled(UITokens.FONT_SMALL)
	var tiny_fs := UITheme.scaled(UITokens.FONT_TINY)

	# Stars always shown
	var difficulty: int = fish_data.get("difficulty", 1)
	var stars_text := ""
	for s_i in 5:
		if s_i < difficulty:
			stars_text += "\u2605"
		else:
			stars_text += "\u2606"
	var stars_label := Label.new()
	stars_label.text = stars_text
	stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_caption(stars_label)
	stars_label.add_theme_font_size_override("font_size", small_fs)
	if is_caught:
		stars_label.add_theme_color_override("font_color", UITokens.ACCENT_HONEY)
	else:
		stars_label.add_theme_color_override("font_color", UITokens.INK_DISABLED)
	vbox.add_child(stars_label)

	if not is_caught:
		var msg := Label.new()
		msg.text = "Not yet\ncaught."
		msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UITheme.style_caption(msg)
		msg.add_theme_font_size_override("font_size", small_fs)
		msg.add_theme_color_override("font_color", UITokens.INK_DISABLED)
		vbox.add_child(msg)
		return vbox

	# Season
	var season: String = fish_data.get("season", "")
	if season != "":
		var s_lbl := Label.new()
		s_lbl.text = "Season: %s" % season.capitalize()
		s_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UITheme.style_caption(s_lbl)
		s_lbl.add_theme_font_size_override("font_size", small_fs)
		s_lbl.add_theme_color_override("font_color", UITokens.INK_SECONDARY)
		vbox.add_child(s_lbl)

	# Movement type
	var move_type: String = fish_data.get("movement_type", "smooth")
	var move_lbl := Label.new()
	move_lbl.text = "Movement: %s" % MOVEMENT_HINTS.get(move_type, move_type.capitalize())
	move_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_caption(move_lbl)
	move_lbl.add_theme_font_size_override("font_size", small_fs)
	vbox.add_child(move_lbl)

	# Rod tier
	var rod_tier: int = fish_data.get("min_rod_tier", 0)
	if rod_tier > 0:
		var rod_lbl := Label.new()
		rod_lbl.text = "Rod Tier %d+" % rod_tier
		rod_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UITheme.style_caption(rod_lbl)
		rod_lbl.add_theme_font_size_override("font_size", tiny_fs)
		rod_lbl.add_theme_color_override("font_color", UITokens.INK_SECONDARY)
		vbox.add_child(rod_lbl)

	# Location
	var tables: Array = fish_data.get("tables", [])
	if tables.size() > 0:
		var loc_parts: Array = []
		for t in tables:
			loc_parts.append(str(t).capitalize())
		var loc_lbl := Label.new()
		loc_lbl.text = "Location: %s" % ", ".join(loc_parts)
		loc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UITheme.style_caption(loc_lbl)
		loc_lbl.add_theme_font_size_override("font_size", tiny_fs)
		loc_lbl.add_theme_color_override("font_color", UITokens.INK_SECONDARY)
		vbox.add_child(loc_lbl)

	# Catch count
	var count: int = catch_data.get("count", 0)
	if count > 0:
		var count_lbl := Label.new()
		count_lbl.text = "Caught: x%d" % count
		count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UITheme.style_caption(count_lbl)
		count_lbl.add_theme_font_size_override("font_size", small_fs)
		count_lbl.add_theme_color_override("font_color", UITokens.STAMP_GOLD)
		vbox.add_child(count_lbl)

	# Sell price
	var sell_price := DataRegistry.get_sell_price(fish_id)
	if sell_price > 0:
		var price_lbl := Label.new()
		price_lbl.text = "Sell: $%d" % sell_price
		price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UITheme.style_caption(price_lbl)
		price_lbl.add_theme_font_size_override("font_size", tiny_fs)
		price_lbl.add_theme_color_override("font_color", UITokens.STAMP_GOLD)
		vbox.add_child(price_lbl)

	return vbox

# === STATS TAB ===

func _refresh_stats() -> void:
	count_label.text = ""
	var stats = PlayerData.stats

	for section_name in STAT_SECTIONS:
		var header := Label.new()
		header.text = section_name
		UITheme.style_subheading(header)
		header.add_theme_color_override("font_color", UITokens.STAMP_GOLD)
		card_grid.add_child(header)

		var entries: Array = STAT_SECTIONS[section_name]
		for entry in entries:
			var stat_key: String = entry[0]
			var stat_label: String = entry[1]
			var value = stats.get(stat_key, 0)
			_add_stat_row(card_grid, stat_label, value)

		var spacer := Control.new()
		spacer.custom_minimum_size.y = 8
		card_grid.add_child(spacer)

	var species_encounters = stats.get("species_encounters", {})
	var species_catches = stats.get("species_catches", {})
	var species_evolutions = stats.get("species_evolutions", {})
	var has_species_data = not species_encounters.is_empty() or not species_catches.is_empty() or not species_evolutions.is_empty()

	if has_species_data:
		var sep := HSeparator.new()
		card_grid.add_child(sep)
		var header := Label.new()
		header.text = "Species Breakdown"
		UITheme.style_subheading(header)
		header.add_theme_color_override("font_color", UITokens.STAMP_GOLD)
		card_grid.add_child(header)

		var all_species_dict: Dictionary = {}
		for sid in species_encounters:
			all_species_dict[sid] = true
		for sid in species_catches:
			all_species_dict[sid] = true
		for sid in species_evolutions:
			all_species_dict[sid] = true

		for sid in all_species_dict:
			DataRegistry.ensure_loaded()
			var sp = DataRegistry.get_species(sid)
			var display_name = sp.display_name if sp else sid

			var enc = species_encounters.get(sid, 0)
			var cat = species_catches.get(sid, 0)
			var evo = species_evolutions.get(sid, 0)

			var row := Label.new()
			var parts: Array = []
			if enc > 0:
				parts.append(str(enc) + " enc")
			if cat > 0:
				parts.append(str(cat) + " caught")
			if evo > 0:
				parts.append(str(evo) + " evo")
			row.text = "  " + display_name + ": " + ", ".join(parts)
			UITheme.style_small(row)
			card_grid.add_child(row)

func _add_stat_row(parent: Control, label_text: String, value: int) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = "  " + label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_small(lbl)
	row.add_child(lbl)

	var val := Label.new()
	val.text = _format_number(value)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.custom_minimum_size.x = 80
	UITheme.style_small(val)
	row.add_child(val)

func _format_number(n: int) -> String:
	if n >= 1000000:
		return str(n / 1000000) + "." + str((n / 100000) % 10) + "M"
	elif n >= 1000:
		return str(n / 1000) + "." + str((n / 100) % 10) + "K"
	return str(n)
