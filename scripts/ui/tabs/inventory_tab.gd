extends Control

# Inventory tab content for PauseMenu. Ported from inventory_ui.gd.

var tab_bar: TabBar
var item_list: VBoxContainer
var seed_label: Label
var scroll_container: ScrollContainer
var current_tab: int = 0

const TAB_NAMES = ["All", "Ingredients", "Held Items", "Food", "Tools", "Scrolls"]
const TAB_CATEGORIES = ["all", "ingredient", "held_item", "food", "tool", "recipe_scroll"]

func _ready() -> void:
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

	# Scrollable item list
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll_container)

	item_list = VBoxContainer.new()
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(item_list)

	# Selected seed display
	var seed_row := HBoxContainer.new()
	vbox.add_child(seed_row)
	seed_label = Label.new()
	seed_label.text = "Selected Seed: None"
	seed_row.add_child(seed_label)

func _on_tab_changed(tab_idx: int) -> void:
	current_tab = tab_idx
	_refresh()

func activate() -> void:
	_refresh()

func deactivate() -> void:
	pass

func _refresh() -> void:
	for child in item_list.get_children():
		child.queue_free()
	DataRegistry.ensure_loaded()
	var filter_category = TAB_CATEGORIES[current_tab] if current_tab < TAB_CATEGORIES.size() else "all"

	for item_id in PlayerData.inventory:
		var count = PlayerData.inventory[item_id]
		if count <= 0:
			continue
		var info = DataRegistry.get_item_display_info(item_id)
		if filter_category != "all":
			var cat = info.get("category", "unknown")
			if filter_category == "recipe_scroll" and cat == "fragment":
				pass
			elif cat != filter_category:
				continue

		var hbox := HBoxContainer.new()
		item_list.add_child(hbox)
		var color_rect := ColorRect.new()
		color_rect.custom_minimum_size = Vector2(20, 20)
		color_rect.color = info.get("icon_color", Color.GRAY)
		hbox.add_child(color_rect)
		var label := Label.new()
		label.text = "  %s x%d" % [info.get("display_name", item_id), count]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(label)
		var category = info.get("category", "unknown")
		match category:
			"ingredient":
				var ingredient = DataRegistry.get_ingredient(item_id)
				if ingredient and ingredient.category == "farm_crop":
					var btn := Button.new()
					btn.text = "Select Seed"
					var sid = item_id
					btn.pressed.connect(func(): _select_seed(sid))
					hbox.add_child(btn)
					var hb_btn := Button.new()
					hb_btn.text = "Hotbar"
					var hb_sid = item_id
					hb_btn.pressed.connect(func(): _show_hotbar_assign(hb_sid, "seed"))
					hbox.add_child(hb_btn)
			"food":
				var food = DataRegistry.get_food(item_id)
				if food:
					if food.buff_type != "" and food.buff_type != "none":
						var btn := Button.new()
						btn.text = "Eat"
						var fid = item_id
						btn.pressed.connect(func(): _use_food(fid))
						hbox.add_child(btn)
					if food.sell_price > 0:
						var sell_btn := Button.new()
						sell_btn.text = "Sell ($%d)" % food.sell_price
						var sid = item_id
						sell_btn.pressed.connect(func(): _sell_item(sid))
						hbox.add_child(sell_btn)
					var hb_btn := Button.new()
					hb_btn.text = "Hotbar"
					var hb_id = item_id
					hb_btn.pressed.connect(func(): _show_hotbar_assign(hb_id, "food"))
					hbox.add_child(hb_btn)
			"recipe_scroll":
				var btn := Button.new()
				btn.text = "Use"
				var sid = item_id
				btn.pressed.connect(func(): _use_scroll(sid))
				hbox.add_child(btn)
			"battle_item":
				var hb_btn := Button.new()
				hb_btn.text = "Hotbar"
				var hb_id = item_id
				hb_btn.pressed.connect(func(): _show_hotbar_assign(hb_id, "battle_item"))
				hbox.add_child(hb_btn)
			"tool":
				var tool_def = DataRegistry.get_tool(item_id)
				if tool_def:
					var equipped_id = PlayerData.equipped_tools.get(tool_def.tool_type, "")
					if equipped_id != item_id:
						var btn := Button.new()
						btn.text = "Equip"
						var tid = item_id
						btn.pressed.connect(func(): _equip_tool(tid))
						hbox.add_child(btn)
					else:
						var lbl := Label.new()
						lbl.text = "[Equipped]"
						lbl.add_theme_color_override("font_color", Color.GREEN)
						hbox.add_child(lbl)
					var hb_btn := Button.new()
					hb_btn.text = "Hotbar"
					var hb_tool_type = tool_def.tool_type
					hb_btn.pressed.connect(func(): _show_hotbar_assign(hb_tool_type, "tool_slot"))
					hbox.add_child(hb_btn)

	if PlayerData.selected_seed_id != "":
		var ingredient = DataRegistry.get_ingredient(PlayerData.selected_seed_id)
		seed_label.text = "Selected Seed: %s" % (ingredient.display_name if ingredient else PlayerData.selected_seed_id)
	else:
		seed_label.text = "Selected Seed: None"

func _select_seed(seed_id: String) -> void:
	PlayerData.selected_seed_id = seed_id
	PlayerData.set_tool("seeds")
	_refresh()

func _use_food(food_id: String) -> void:
	NetworkManager.request_use_food.rpc_id(1, food_id)

func _sell_item(item_id: String) -> void:
	NetworkManager.request_sell_item.rpc_id(1, item_id, 1)

func _use_scroll(scroll_id: String) -> void:
	NetworkManager.request_use_recipe_scroll.rpc_id(1, scroll_id)

func _equip_tool(tool_id: String) -> void:
	NetworkManager.request_equip_tool.rpc_id(1, tool_id)

var _hotbar_popup: PopupPanel = null

func _show_hotbar_assign(item_id: String, item_type: String) -> void:
	if _hotbar_popup and is_instance_valid(_hotbar_popup):
		_hotbar_popup.queue_free()
	_hotbar_popup = PopupPanel.new()
	var vbox := VBoxContainer.new()
	_hotbar_popup.add_child(vbox)
	var title := Label.new()
	title.text = "Assign to slot:"
	vbox.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 4
	vbox.add_child(grid)
	var key_labels = ["1", "2", "3", "4", "5", "6", "7", "8"]
	for i in range(PlayerData.HOTBAR_SIZE):
		var btn := Button.new()
		btn.text = key_labels[i]
		btn.custom_minimum_size = Vector2(36, 36)
		var slot_idx = i
		var sid = item_id
		var stype = item_type
		btn.pressed.connect(func():
			PlayerData.assign_hotbar_slot(slot_idx, sid, stype)
			if _hotbar_popup and is_instance_valid(_hotbar_popup):
				_hotbar_popup.hide()
		)
		grid.add_child(btn)
	add_child(_hotbar_popup)
	_hotbar_popup.popup_centered(Vector2(200, 120))
