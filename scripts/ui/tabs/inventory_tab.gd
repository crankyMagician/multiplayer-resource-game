extends Control

# Inventory tab content for PauseMenu. Card grid with flip-to-reveal details.
const UITokens = preload("res://scripts/ui/ui_tokens.gd")

var tab_bar: TabBar
var card_grid: GridContainer
var content_scroll: ScrollContainer
var current_tab: int = 0

# Card flip state
var _flipped_cards: Dictionary = {}   # card -> bool
var _card_fronts: Dictionary = {}     # card -> VBoxContainer
var _card_backs: Dictionary = {}      # card -> VBoxContainer

const TAB_NAMES = ["All", "Seeds", "Ingredients", "Held Items", "Food", "Tools", "Scrolls", "Battle Items"]
const TAB_CATEGORIES = ["all", "seed", "ingredient", "held_item", "food", "tool", "recipe_scroll", "battle_item"]

func _ready() -> void:
	UITheme.init()
	_build_ui()
	PlayerData.inventory_changed.connect(_refresh)

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	# Tab bar
	tab_bar = TabBar.new()
	for tab_name in TAB_NAMES:
		tab_bar.add_tab(tab_name)
	tab_bar.tab_changed.connect(_on_tab_changed)
	vbox.add_child(tab_bar)

	# Scrollable card grid (full width, no split)
	content_scroll = ScrollContainer.new()
	content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(content_scroll)

	card_grid = GridContainer.new()
	card_grid.columns = 4
	card_grid.add_theme_constant_override("h_separation", 8)
	card_grid.add_theme_constant_override("v_separation", 8)
	card_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.add_child(card_grid)


func _on_tab_changed(tab_idx: int) -> void:
	current_tab = tab_idx
	_refresh()

func activate() -> void:
	_refresh()

func deactivate() -> void:
	pass

func _refresh() -> void:
	_clear_children(card_grid)
	_flipped_cards.clear()
	_card_fronts.clear()
	_card_backs.clear()
	DataRegistry.ensure_loaded()
	var filter_category = TAB_CATEGORIES[current_tab] if current_tab < TAB_CATEGORIES.size() else "all"

	for item_id in PlayerData.inventory:
		var count = PlayerData.inventory[item_id]
		if count <= 0:
			continue
		var info = DataRegistry.get_item_display_info(item_id)
		var is_seed_item = _is_seed_item(item_id)
		if filter_category != "all":
			var cat = info.get("category", "unknown")
			if filter_category == "seed":
				if not is_seed_item:
					continue
			elif filter_category == "ingredient":
				if cat != "ingredient" or is_seed_item:
					continue
			elif filter_category == "recipe_scroll" and cat == "fragment":
				pass
			elif cat != filter_category:
				continue

		var card := _build_item_card(item_id, info, count)
		card_grid.add_child(card)


# === CARD BUILDING ===

func _build_item_card(item_id: String, info: Dictionary, count: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size.y = UITheme.scaled(140)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = UITokens.PAPER_CARD
	style.border_color = UITokens.ACCENT_CHESTNUT
	style.set_corner_radius_all(UITokens.CORNER_RADIUS)
	style.set_border_width_all(1)
	style.content_margin_left = 6
	style.content_margin_top = 6
	style.content_margin_right = 6
	style.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", style)

	# Front
	var front := _build_card_front(item_id, info, count)
	card.add_child(front)

	# Back
	var back := _build_card_back(item_id, info, count)
	card.add_child(back)

	# Flip overlay
	_add_flip_overlay(card, front, back)

	return card

func _build_card_front(item_id: String, info: Dictionary, count: int) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)

	# Icon
	var icon := UITheme.create_item_icon(info, 48)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(icon)

	# Name
	var name_lbl := Label.new()
	name_lbl.text = info.get("display_name", item_id)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_caption(name_lbl)
	name_lbl.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_SMALL))
	vbox.add_child(name_lbl)

	# Quantity badge
	var qty_lbl := Label.new()
	qty_lbl.text = "x%d" % count
	qty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_caption(qty_lbl)
	qty_lbl.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
	qty_lbl.add_theme_color_override("font_color", UITokens.INK_SECONDARY)
	vbox.add_child(qty_lbl)

	return vbox

func _build_card_back(item_id: String, info: Dictionary, count: int) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 3)

	var small_fs := UITheme.scaled(UITokens.FONT_SMALL)
	var tiny_fs := UITheme.scaled(UITokens.FONT_TINY)

	# Name
	var name_lbl := Label.new()
	name_lbl.text = info.get("display_name", item_id)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_caption(name_lbl)
	name_lbl.add_theme_font_size_override("font_size", small_fs)
	vbox.add_child(name_lbl)

	# Category
	var category: String = info.get("category", "unknown")
	var cat_lbl := Label.new()
	cat_lbl.text = category.replace("_", " ").capitalize()
	cat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_caption(cat_lbl)
	cat_lbl.add_theme_font_size_override("font_size", tiny_fs)
	cat_lbl.add_theme_color_override("font_color", UITokens.INK_SECONDARY)
	vbox.add_child(cat_lbl)

	# Quantity
	var qty_lbl := Label.new()
	qty_lbl.text = "Owned: x%d" % count
	qty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_caption(qty_lbl)
	qty_lbl.add_theme_font_size_override("font_size", tiny_fs)
	vbox.add_child(qty_lbl)

	# Sell price
	var sell_price = DataRegistry.get_sell_price(item_id)
	if sell_price > 0:
		var price_lbl := Label.new()
		price_lbl.text = "$%d" % sell_price
		price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UITheme.style_caption(price_lbl)
		price_lbl.add_theme_font_size_override("font_size", tiny_fs)
		price_lbl.add_theme_color_override("font_color", UITokens.STAMP_GOLD)
		vbox.add_child(price_lbl)

	# Action buttons
	var is_seed_item = _is_seed_item(item_id)
	match category:
		"food":
			var food = DataRegistry.get_food(item_id)
			if food:
				if food.buff_type != "" and food.buff_type != "none":
					var eat_btn := Button.new()
					eat_btn.text = "Eat"
					eat_btn.custom_minimum_size.y = 24
					UITheme.style_button(eat_btn, "primary")
					var fid = item_id
					eat_btn.pressed.connect(func(): _use_food(fid))
					vbox.add_child(eat_btn)
				if food.sell_price > 0:
					var sell_btn := Button.new()
					sell_btn.text = "Sell ($%d)" % food.sell_price
					sell_btn.custom_minimum_size.y = 24
					UITheme.style_button(sell_btn, "secondary")
					var sid = item_id
					sell_btn.pressed.connect(func(): _sell_item(sid))
					vbox.add_child(sell_btn)
		"recipe_scroll":
			var use_btn := Button.new()
			use_btn.text = "Use"
			use_btn.custom_minimum_size.y = 24
			UITheme.style_button(use_btn, "primary")
			var sid = item_id
			use_btn.pressed.connect(func(): _use_scroll(sid))
			vbox.add_child(use_btn)
		"tool":
			var tool_def = DataRegistry.get_tool(item_id)
			if tool_def:
				var equipped_id = PlayerData.equipped_tools.get(tool_def.tool_type, "")
				if equipped_id != item_id:
					var equip_btn := Button.new()
					equip_btn.text = "Equip"
					equip_btn.custom_minimum_size.y = 24
					UITheme.style_button(equip_btn, "primary")
					var tid = item_id
					equip_btn.pressed.connect(func(): _equip_tool(tid))
					vbox.add_child(equip_btn)
				else:
					var lbl := Label.new()
					lbl.text = "[Equipped]"
					lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					UITheme.style_small(lbl)
					lbl.add_theme_color_override("font_color", UITokens.TEXT_SUCCESS)
					vbox.add_child(lbl)

	return vbox

# === FLIP HELPERS ===

func _add_flip_overlay(card: PanelContainer, front: VBoxContainer, back: VBoxContainer) -> void:
	back.visible = false
	_card_fronts[card] = front
	_card_backs[card] = back
	_flipped_cards[card] = false
	var overlay := Button.new()
	overlay.flat = true
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	overlay.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var captured_card := card
	overlay.pressed.connect(func(): _on_card_clicked(captured_card))
	card.add_child(overlay)

func _on_card_clicked(card: PanelContainer) -> void:
	var is_flipped: bool = _flipped_cards.get(card, false)
	_card_fronts[card].visible = is_flipped
	_card_backs[card].visible = not is_flipped
	_flipped_cards[card] = not is_flipped

# === ACTION METHODS ===

func _is_seed_item(item_id: String) -> bool:
	var ingredient = DataRegistry.get_ingredient(item_id)
	if ingredient == null:
		return false
	if ingredient.category == "farm_crop":
		return true
	if item_id.ends_with("_seed"):
		return true
	return ingredient.display_name.to_lower().ends_with(" seed")

func _use_food(food_id: String) -> void:
	NetworkManager.request_use_food.rpc_id(1, food_id)

func _sell_item(item_id: String) -> void:
	NetworkManager.request_sell_item.rpc_id(1, item_id, 1)

func _use_scroll(scroll_id: String) -> void:
	NetworkManager.request_use_recipe_scroll.rpc_id(1, scroll_id)

func _equip_tool(tool_id: String) -> void:
	NetworkManager.request_equip_tool.rpc_id(1, tool_id)

func _clear_children(node: Control) -> void:
	for child in node.get_children():
		child.queue_free()
