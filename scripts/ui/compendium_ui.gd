extends CanvasLayer

# Combined Compendium + Stats UI — toggled with K key.
# Tabs: Items, Creatures, Stats. Data synced on-demand from server via RPC.

var panel: PanelContainer
var tab_bar: TabBar
var count_label: Label
var content_scroll: ScrollContainer
var content_list: VBoxContainer
var detail_scroll: ScrollContainer
var detail_panel: VBoxContainer
var filter_bar: HBoxContainer
var close_button: Button

var _current_tab: int = 0 # 0=Items, 1=Creatures, 2=Stats
var _current_filter: String = "all"
var _selected_item_id: String = ""
var _selected_species_id: String = ""

const ITEM_FILTERS = ["all", "ingredient", "food", "tool", "held_item", "battle_item", "recipe_scroll"]
const FILTER_LABELS = {"all": "All", "ingredient": "Ingredients", "food": "Foods", "tool": "Tools", "held_item": "Held Items", "battle_item": "Battle Items", "recipe_scroll": "Scrolls"}

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
	layer = 10
	visible = false
	_build_ui()
	PlayerData.compendium_changed.connect(_refresh)
	PlayerData.stats_changed.connect(_refresh)

func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.anchor_left = 0.1
	panel.anchor_right = 0.9
	panel.anchor_top = 0.05
	panel.anchor_bottom = 0.95
	add_child(panel)

	var main_vbox = VBoxContainer.new()
	panel.add_child(main_vbox)

	# Title + count
	var title_row = HBoxContainer.new()
	main_vbox.add_child(title_row)
	var title = Label.new()
	title.text = "Compendium"
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	count_label = Label.new()
	count_label.add_theme_font_size_override("font_size", 14)
	count_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	title_row.add_child(count_label)

	# Tab bar
	tab_bar = TabBar.new()
	tab_bar.add_tab("Items")
	tab_bar.add_tab("Creatures")
	tab_bar.add_tab("Stats")
	tab_bar.tab_changed.connect(_on_tab_changed)
	main_vbox.add_child(tab_bar)

	# Filter bar (for Items tab)
	filter_bar = HBoxContainer.new()
	main_vbox.add_child(filter_bar)
	for filter_id in ITEM_FILTERS:
		var btn = Button.new()
		btn.text = FILTER_LABELS.get(filter_id, filter_id)
		btn.custom_minimum_size.x = 80
		btn.pressed.connect(_on_filter_pressed.bind(filter_id))
		filter_bar.add_child(btn)

	# Content split
	var hsplit = HSplitContainer.new()
	hsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(hsplit)

	# Left: list
	content_scroll = ScrollContainer.new()
	content_scroll.custom_minimum_size = Vector2(280, 0)
	content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsplit.add_child(content_scroll)
	content_list = VBoxContainer.new()
	content_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.add_child(content_list)

	# Right: detail
	detail_scroll = ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsplit.add_child(detail_scroll)
	detail_panel = VBoxContainer.new()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(detail_panel)

	# Close button
	close_button = Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(_close)
	main_vbox.add_child(close_button)

func toggle() -> void:
	visible = !visible
	if visible:
		NetworkManager.request_compendium_sync.rpc_id(1)
		_refresh()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		NetworkManager.request_set_busy.rpc_id(1, true)
	else:
		_close()

func _close() -> void:
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	NetworkManager.request_set_busy.rpc_id(1, false)

func _on_tab_changed(tab: int) -> void:
	_current_tab = tab
	_current_filter = "all"
	_selected_item_id = ""
	_selected_species_id = ""
	_refresh()

func _on_filter_pressed(filter_id: String) -> void:
	_current_filter = filter_id
	_refresh()

func _refresh() -> void:
	if not visible:
		return
	_clear_children(content_list)
	_clear_children(detail_panel)
	filter_bar.visible = (_current_tab == 0)
	match _current_tab:
		0:
			_refresh_items()
		1:
			_refresh_creatures()
		2:
			_refresh_stats()

func _clear_children(node: Control) -> void:
	for child in node.get_children():
		child.queue_free()

# === ITEMS TAB ===

func _refresh_items() -> void:
	DataRegistry.ensure_loaded()
	var unlocked: Array = PlayerData.compendium.get("items", [])

	# Build full item list from all registries
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

	# Filter by category
	var filtered: Array = []
	var unlocked_count: int = 0
	for item_id in all_items:
		var info = DataRegistry.get_item_display_info(item_id)
		if _current_filter != "all" and info.get("category", "") != _current_filter:
			continue
		filtered.append({"item_id": item_id, "info": info, "unlocked": item_id in unlocked})
		if item_id in unlocked:
			unlocked_count += 1

	# Sort: unlocked first, then alphabetical
	filtered.sort_custom(func(a, b):
		if a.unlocked != b.unlocked:
			return a.unlocked
		return a.info.display_name < b.info.display_name
	)

	var total = filtered.size()
	count_label.text = "Items: " + str(unlocked_count) + "/" + str(total)

	for entry in filtered:
		var btn = Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if entry.unlocked:
			btn.text = "  " + entry.info.display_name
			btn.add_theme_color_override("font_color", entry.info.get("icon_color", Color.WHITE))
		else:
			btn.text = "  ???"
			btn.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		btn.pressed.connect(_on_item_selected.bind(entry.item_id, entry.unlocked))
		content_list.add_child(btn)

func _on_item_selected(item_id: String, is_unlocked: bool) -> void:
	_clear_children(detail_panel)
	if not is_unlocked:
		var label = Label.new()
		label.text = "???\n\nNot yet discovered."
		label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		detail_panel.add_child(label)
		return

	var info = DataRegistry.get_item_display_info(item_id)
	var name_label = Label.new()
	name_label.text = info.get("display_name", item_id)
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", info.get("icon_color", Color.WHITE))
	detail_panel.add_child(name_label)

	var cat_label = Label.new()
	cat_label.text = "Category: " + info.get("category", "unknown").replace("_", " ").capitalize()
	cat_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	detail_panel.add_child(cat_label)

	var id_label = Label.new()
	id_label.text = "ID: " + item_id
	id_label.add_theme_font_size_override("font_size", 12)
	id_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	detail_panel.add_child(id_label)

	# Show sell price if available
	var sell_price = DataRegistry.get_sell_price(item_id)
	if sell_price > 0:
		var price_label = Label.new()
		price_label.text = "Sell Price: $" + str(sell_price)
		detail_panel.add_child(price_label)

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

	count_label.text = "Creatures: " + str(seen_count) + "/" + str(all_species.size()) + " seen, " + str(owned_count) + "/" + str(all_species.size()) + " owned"

	for species_id in all_species:
		var sp = DataRegistry.get_species(species_id)
		if sp == null:
			continue
		var btn = Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if species_id in owned:
			btn.text = "  " + sp.display_name + "  [Owned]"
			btn.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
		elif species_id in seen:
			btn.text = "  " + sp.display_name
			btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.5))
		else:
			btn.text = "  ???"
			btn.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		btn.pressed.connect(_on_creature_selected.bind(species_id))
		content_list.add_child(btn)

func _on_creature_selected(species_id: String) -> void:
	_clear_children(detail_panel)
	var seen: Array = PlayerData.compendium.get("creatures_seen", [])
	var owned: Array = PlayerData.compendium.get("creatures_owned", [])

	if species_id not in seen:
		var label = Label.new()
		label.text = "???\n\nNot yet encountered."
		label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		detail_panel.add_child(label)
		return

	var sp = DataRegistry.get_species(species_id)
	if sp == null:
		return

	var name_label = Label.new()
	name_label.text = sp.display_name
	name_label.add_theme_font_size_override("font_size", 20)
	detail_panel.add_child(name_label)

	var type_label = Label.new()
	var type_str = ""
	for t in sp.types:
		if type_str != "":
			type_str += " / "
		type_str += str(t).capitalize()
	type_label.text = "Type: " + type_str
	detail_panel.add_child(type_label)

	if species_id in owned:
		# Show full stats
		var stats_label = Label.new()
		stats_label.text = "Base Stats:\n" \
			+ "  HP: " + str(sp.base_hp) + "\n" \
			+ "  ATK: " + str(sp.base_attack) + "\n" \
			+ "  DEF: " + str(sp.base_defense) + "\n" \
			+ "  SPA: " + str(sp.base_sp_attack) + "\n" \
			+ "  SPD: " + str(sp.base_sp_defense) + "\n" \
			+ "  SPE: " + str(sp.base_speed)
		detail_panel.add_child(stats_label)

		# Abilities
		if sp.ability_ids.size() > 0:
			var ab_label = Label.new()
			var ab_str = "Abilities: "
			for ab_id in sp.ability_ids:
				var ab = DataRegistry.get_ability(ab_id)
				if ab:
					ab_str += ab.display_name + " "
				else:
					ab_str += str(ab_id) + " "
			ab_label.text = ab_str
			detail_panel.add_child(ab_label)

		# Evolution
		if sp.evolves_to != "":
			var evo_sp = DataRegistry.get_species(sp.evolves_to)
			var evo_name = evo_sp.display_name if evo_sp else sp.evolves_to
			var evo_label = Label.new()
			evo_label.text = "Evolves to: " + evo_name + " at Lv " + str(sp.evolution_level)
			evo_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
			detail_panel.add_child(evo_label)

		# Species-specific stats from player
		var stats = PlayerData.stats
		var encounters = stats.get("species_encounters", {}).get(species_id, 0)
		var catches = stats.get("species_catches", {}).get(species_id, 0)
		var evolutions = stats.get("species_evolutions", {}).get(species_id, 0)
		if encounters > 0 or catches > 0 or evolutions > 0:
			var sep = HSeparator.new()
			detail_panel.add_child(sep)
			var your_label = Label.new()
			your_label.text = "Your Stats:"
			your_label.add_theme_font_size_override("font_size", 16)
			detail_panel.add_child(your_label)
			if encounters > 0:
				_add_stat_row(detail_panel, "Encounters", encounters)
			if catches > 0:
				_add_stat_row(detail_panel, "Obtained", catches)
			if evolutions > 0:
				_add_stat_row(detail_panel, "Evolutions", evolutions)
	else:
		var hint = Label.new()
		hint.text = "\nOwn this creature to see full details."
		hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		detail_panel.add_child(hint)

# === STATS TAB ===

func _refresh_stats() -> void:
	count_label.text = ""
	var stats = PlayerData.stats

	for section_name in STAT_SECTIONS:
		# Section header
		var header = Label.new()
		header.text = section_name
		header.add_theme_font_size_override("font_size", 18)
		header.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
		content_list.add_child(header)

		var entries: Array = STAT_SECTIONS[section_name]
		for entry in entries:
			var stat_key: String = entry[0]
			var stat_label: String = entry[1]
			var value = stats.get(stat_key, 0)
			_add_stat_row(content_list, stat_label, value)

		# Spacer
		var spacer = Control.new()
		spacer.custom_minimum_size.y = 8
		content_list.add_child(spacer)

	# Species breakdown section
	var species_encounters = stats.get("species_encounters", {})
	var species_catches = stats.get("species_catches", {})
	var species_evolutions = stats.get("species_evolutions", {})
	var has_species_data = not species_encounters.is_empty() or not species_catches.is_empty() or not species_evolutions.is_empty()

	if has_species_data:
		var sep = HSeparator.new()
		content_list.add_child(sep)
		var header = Label.new()
		header.text = "Species Breakdown"
		header.add_theme_font_size_override("font_size", 18)
		header.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
		content_list.add_child(header)

		# Collect all species IDs
		var all_species: Dictionary = {}
		for sid in species_encounters:
			all_species[sid] = true
		for sid in species_catches:
			all_species[sid] = true
		for sid in species_evolutions:
			all_species[sid] = true

		for sid in all_species:
			DataRegistry.ensure_loaded()
			var sp = DataRegistry.get_species(sid)
			var display_name = sp.display_name if sp else sid

			var enc = species_encounters.get(sid, 0)
			var cat = species_catches.get(sid, 0)
			var evo = species_evolutions.get(sid, 0)

			var row = Label.new()
			var parts: Array = []
			if enc > 0:
				parts.append(str(enc) + " enc")
			if cat > 0:
				parts.append(str(cat) + " caught")
			if evo > 0:
				parts.append(str(evo) + " evo")
			row.text = "  " + display_name + ": " + ", ".join(parts)
			row.add_theme_font_size_override("font_size", 14)
			content_list.add_child(row)

func _add_stat_row(parent: Control, label_text: String, value: int) -> void:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)

	var lbl = Label.new()
	lbl.text = "  " + label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var val = Label.new()
	val.text = _format_number(value)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.custom_minimum_size.x = 80
	row.add_child(val)

func _format_number(n: int) -> String:
	if n >= 1000000:
		return str(n / 1000000) + "." + str((n / 100000) % 10) + "M"
	elif n >= 1000:
		return str(n / 1000) + "." + str((n / 100) % 10) + "K"
	return str(n)
