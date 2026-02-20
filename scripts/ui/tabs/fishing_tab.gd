extends Control

# Fishing Journal tab for PauseMenu. Shows catch history, fish cards, and stats.
# Follows compendium_tab.gd pattern.

const UITokens = preload("res://scripts/ui/ui_tokens.gd")

var count_label: Label
var filter_bar: HBoxContainer
var content_scroll: ScrollContainer
var card_grid: GridContainer
var detail_scroll: ScrollContainer
var detail_panel: VBoxContainer

var _current_filter: String = "all"
var _selected_fish_id: String = ""

const FILTER_TABS: Array = ["all", "pond", "river", "ocean"]
const FILTER_LABELS: Dictionary = {"all": "All", "pond": "Pond", "river": "River", "ocean": "Ocean"}

const MOVEMENT_HINTS: Dictionary = {
	"smooth": "Floating",
	"dart": "Darting",
	"sinker": "Deep",
	"mixed": "Tricky",
}


func _ready() -> void:
	UITheme.init()
	_build_ui()
	PlayerData.fishing_log_changed.connect(_refresh)


func _build_ui() -> void:
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(main_vbox)

	# Title + count row
	var title_row := HBoxContainer.new()
	main_vbox.add_child(title_row)
	var title := Label.new()
	title.text = "Fishing Journal"
	UITheme.style_subheading(title)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	count_label = Label.new()
	UITheme.style_small(count_label)
	count_label.add_theme_color_override("font_color", UITokens.INK_SECONDARY)
	title_row.add_child(count_label)

	# Filter bar
	filter_bar = HBoxContainer.new()
	main_vbox.add_child(filter_bar)
	for filter_id in FILTER_TABS:
		var btn := Button.new()
		btn.text = FILTER_LABELS.get(filter_id, filter_id)
		btn.custom_minimum_size.x = 70
		UITheme.style_button(btn, "secondary")
		btn.pressed.connect(_on_filter_pressed.bind(filter_id))
		filter_bar.add_child(btn)

	# Content split
	var hsplit := HSplitContainer.new()
	hsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(hsplit)

	# Left: card grid in scroll
	content_scroll = ScrollContainer.new()
	content_scroll.custom_minimum_size = Vector2(380, 0)
	content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsplit.add_child(content_scroll)

	card_grid = GridContainer.new()
	card_grid.columns = 4
	card_grid.add_theme_constant_override("h_separation", 8)
	card_grid.add_theme_constant_override("v_separation", 8)
	card_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.add_child(card_grid)

	# Right: detail panel
	detail_scroll = ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsplit.add_child(detail_scroll)
	detail_panel = VBoxContainer.new()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(detail_panel)


func activate() -> void:
	# Request fishing log sync from server
	var fishing_mgr = get_node_or_null("/root/Main/GameWorld/FishingManager")
	if fishing_mgr:
		fishing_mgr.request_fishing_log_sync.rpc_id(1)
	_refresh()


func deactivate() -> void:
	pass


func _on_filter_pressed(filter_id: String) -> void:
	_current_filter = filter_id
	_refresh()


func _refresh() -> void:
	_clear_children(card_grid)
	_clear_children(detail_panel)

	DataRegistry.ensure_loaded()
	var catches: Dictionary = PlayerData.fishing_log.get("catches", {})

	# Collect all fish from all fishing tables
	var all_fish: Dictionary = {}  # fish_id -> {difficulty, movement_type, tables: [table_id]}
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

	# Filter by location
	var filtered_fish: Array = []
	for fid in all_fish:
		if _current_filter != "all":
			if _current_filter not in all_fish[fid]["tables"]:
				continue
		filtered_fish.append(fid)
	filtered_fish.sort()

	# Count caught species
	var caught_count: int = 0
	for fid in filtered_fish:
		if fid in catches:
			caught_count += 1
	var total: int = filtered_fish.size()
	count_label.text = "%d/%d species" % [caught_count, total]

	# Build cards
	for fid in filtered_fish:
		var is_caught: bool = fid in catches
		var card := _build_fish_card(fid, all_fish[fid], is_caught, catches.get(fid, {}))
		card_grid.add_child(card)

	# Restore detail selection
	if _selected_fish_id != "" and _selected_fish_id in all_fish:
		_show_detail(_selected_fish_id, all_fish[_selected_fish_id], catches.get(_selected_fish_id, {}))


func _build_fish_card(fish_id: String, fish_data: Dictionary, is_caught: bool, catch_data: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	var card_size := UITheme.scaled(80)
	card.custom_minimum_size = Vector2(card_size, card_size)

	var card_style := StyleBoxFlat.new()
	if is_caught:
		card_style.bg_color = UITokens.PAPER_CARD
		card_style.border_color = UITokens.ACCENT_CHESTNUT
	else:
		card_style.bg_color = UITokens.PAPER_EDGE
		card_style.border_color = Color(UITokens.ACCENT_CHESTNUT.r, UITokens.ACCENT_CHESTNUT.g, UITokens.ACCENT_CHESTNUT.b, 0.4)
	card_style.set_corner_radius_all(UITokens.CORNER_RADIUS)
	card_style.set_border_width_all(1)
	card_style.content_margin_left = 4
	card_style.content_margin_top = 4
	card_style.content_margin_right = 4
	card_style.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", card_style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	card.add_child(vbox)

	# Icon
	if is_caught:
		var info := DataRegistry.get_item_display_info(fish_id)
		if not info.is_empty():
			var icon := UITheme.create_item_icon(info, 32)
			icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			vbox.add_child(icon)
		else:
			var placeholder := Control.new()
			placeholder.custom_minimum_size = Vector2(UITheme.scaled(32), UITheme.scaled(32))
			vbox.add_child(placeholder)
	else:
		# Silhouette placeholder
		var placeholder := ColorRect.new()
		placeholder.custom_minimum_size = Vector2(UITheme.scaled(32), UITheme.scaled(32))
		placeholder.color = Color(UITokens.INK_DISABLED.r, UITokens.INK_DISABLED.g, UITokens.INK_DISABLED.b, 0.3)
		placeholder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(placeholder)

	# Name
	var name_label := Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if is_caught:
		var fish_def = DataRegistry.get_ingredient(fish_id)
		var display_name: String = fish_def.display_name if fish_def else fish_id.capitalize()
		name_label.text = display_name
		UITheme.style_caption(name_label)
		name_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
	else:
		name_label.text = "???"
		UITheme.style_caption(name_label)
		name_label.add_theme_color_override("font_color", UITokens.INK_DISABLED)
		name_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
	vbox.add_child(name_label)

	# Count (if caught)
	if is_caught:
		var count_lbl := Label.new()
		count_lbl.text = "x%d" % catch_data.get("count", 0)
		UITheme.style_caption(count_lbl)
		count_lbl.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
		count_lbl.add_theme_color_override("font_color", UITokens.INK_SECONDARY)
		count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(count_lbl)

	# Stars
	var difficulty: int = fish_data.get("difficulty", 1)
	var stars_text := ""
	for i in 5:
		if i < difficulty:
			stars_text += "\u2605"
		else:
			stars_text += "\u2606"
	var stars_label := Label.new()
	stars_label.text = stars_text
	stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_caption(stars_label)
	stars_label.add_theme_font_size_override("font_size", UITheme.scaled(12))
	if is_caught:
		stars_label.add_theme_color_override("font_color", UITokens.ACCENT_HONEY)
	else:
		stars_label.add_theme_color_override("font_color", UITokens.INK_DISABLED)
	vbox.add_child(stars_label)

	# Make card clickable
	var btn := Button.new()
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.flat = true
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.pressed.connect(_on_card_pressed.bind(fish_id, fish_data))
	card.add_child(btn)

	return card


func _on_card_pressed(fish_id: String, fish_data: Dictionary) -> void:
	_selected_fish_id = fish_id
	var catches: Dictionary = PlayerData.fishing_log.get("catches", {})
	_show_detail(fish_id, fish_data, catches.get(fish_id, {}))


func _show_detail(fish_id: String, fish_data: Dictionary, catch_data: Dictionary) -> void:
	_clear_children(detail_panel)

	var is_caught: bool = not catch_data.is_empty()

	if not is_caught:
		var label := Label.new()
		label.text = "???\n\nNot yet caught."
		UITheme.style_small(label)
		label.add_theme_color_override("font_color", UITokens.INK_DISABLED)
		detail_panel.add_child(label)

		# Show stars
		var difficulty: int = fish_data.get("difficulty", 1)
		var stars_text := ""
		for i in 5:
			if i < difficulty:
				stars_text += "\u2605"
			else:
				stars_text += "\u2606"
		var stars_label := Label.new()
		stars_label.text = stars_text
		UITheme.style_emphasis(stars_label)
		stars_label.add_theme_color_override("font_color", UITokens.INK_DISABLED)
		detail_panel.add_child(stars_label)
		return

	# Large icon
	var info := DataRegistry.get_item_display_info(fish_id)
	if not info.is_empty():
		var icon := UITheme.create_item_icon(info, 64)
		detail_panel.add_child(icon)

	# Fish name
	var fish_def = DataRegistry.get_ingredient(fish_id)
	var display_name: String = fish_def.display_name if fish_def else fish_id.capitalize()
	var name_label := Label.new()
	UITheme.style_emphasis(name_label, display_name)
	name_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_H3))
	detail_panel.add_child(name_label)

	# Stars
	var difficulty: int = fish_data.get("difficulty", 1)
	var stars_text := ""
	for i in 5:
		if i < difficulty:
			stars_text += "\u2605"
		else:
			stars_text += "\u2606"
	var stars_label := Label.new()
	UITheme.style_emphasis(stars_label, stars_text)
	detail_panel.add_child(stars_label)

	# Info row
	var info_parts: Array = []
	var season: String = fish_data.get("season", "")
	if season != "":
		info_parts.append("Season: %s" % season.capitalize())
	else:
		info_parts.append("Season: Any")

	var sell_price: int = DataRegistry.get_sell_price(fish_id)
	if sell_price > 0:
		info_parts.append("Value: %dg" % sell_price)

	var rod_tier: int = fish_data.get("min_rod_tier", 0)
	var rod_names: Array = ["Basic+", "Bronze+", "Iron+", "Gold"]
	if rod_tier >= 0 and rod_tier < rod_names.size():
		info_parts.append("Rod: %s" % rod_names[rod_tier])

	var movement: String = MOVEMENT_HINTS.get(fish_data.get("movement_type", "smooth"), "Unknown")
	info_parts.append(movement)

	var info_label := Label.new()
	info_label.text = " | ".join(info_parts)
	UITheme.style_caption(info_label)
	info_label.add_theme_color_override("font_color", UITokens.INK_SECONDARY)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_panel.add_child(info_label)

	# Location(s)
	var tables: Array = fish_data.get("tables", [])
	if not tables.is_empty():
		var table_names: Array = []
		for tid in tables:
			var table: FishingTable = DataRegistry.fishing_tables.get(tid)
			if table:
				table_names.append(table.display_name)
			else:
				table_names.append(str(tid).capitalize())
		var loc_label := Label.new()
		loc_label.text = "Location: %s" % ", ".join(table_names)
		UITheme.style_caption(loc_label)
		loc_label.add_theme_color_override("font_color", UITokens.INK_SECONDARY)
		detail_panel.add_child(loc_label)

	# Separator
	var sep := HSeparator.new()
	detail_panel.add_child(sep)

	# Catch stats
	var stats_header := Label.new()
	UITheme.style_body_text(stats_header, "Your Stats")
	detail_panel.add_child(stats_header)

	var caught_count: int = catch_data.get("count", 0)
	_add_stat_row("Caught", caught_count)

	var perfect_count: int = catch_data.get("perfect_count", 0)
	if perfect_count > 0:
		_add_stat_row("Perfect", perfect_count)

	var first_day: int = catch_data.get("first_caught_day", 0)
	if first_day > 0:
		_add_stat_row("First catch", first_day, "Day %d")


func _add_stat_row(label_text: String, value: int, format_str: String = "%d") -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.add_child(row)

	var lbl := Label.new()
	lbl.text = "  " + label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_small(lbl)
	row.add_child(lbl)

	var val := Label.new()
	val.text = format_str % value
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.custom_minimum_size.x = 80
	UITheme.style_small(val)
	row.add_child(val)


func _clear_children(node: Control) -> void:
	for child in node.get_children():
		child.queue_free()
