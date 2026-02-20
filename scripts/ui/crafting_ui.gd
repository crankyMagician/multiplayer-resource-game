extends CanvasLayer

const UITokens = preload("res://scripts/ui/ui_tokens.gd")

@onready var recipe_list: VBoxContainer = $Panel/VBox/RecipeScroll/RecipeList
@onready var recipe_scroll: ScrollContainer = $Panel/VBox/RecipeScroll
@onready var close_button: Button = $Panel/VBox/CloseButton

var crafting_system: Node = null
var current_station: String = ""
var title_label: Label = null

# Filter/search state
var filter_row: HBoxContainer = null
var search_edit: LineEdit = null
var craftable_only: bool = false
var _filter_buttons: Array[Button] = []

# Toast overlay
var _toast_label: Label = null
var _toast_container: HBoxContainer = null
var _toast_tween: Tween = null

# Error label (inline)
var _error_label: Label = null
var _error_tween: Tween = null

func _ready() -> void:
	UITheme.init()
	UITheme.style_modal($Panel)
	UITheme.style_button(close_button, "danger")
	close_button.pressed.connect(_close)
	# Create title label
	title_label = Label.new()
	title_label.text = "Crafting"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_heading(title_label)
	var vbox = $Panel/VBox
	vbox.add_child(title_label)
	vbox.move_child(title_label, 0)

	# Build filter row (after title, before scroll)
	_build_filter_row(vbox)

	# Build toast overlay
	_build_toast()

func _build_filter_row(vbox: VBoxContainer) -> void:
	# Search bar
	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 8)
	vbox.add_child(search_row)
	vbox.move_child(search_row, 1) # After title

	search_edit = LineEdit.new()
	search_edit.placeholder_text = "Search recipes..."
	search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_input(search_edit)
	search_edit.text_changed.connect(func(_t: String): refresh())
	search_row.add_child(search_edit)

	# Filter row
	filter_row = HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 4)
	vbox.add_child(filter_row)
	vbox.move_child(filter_row, 2)

	var craftable_btn := Button.new()
	craftable_btn.text = "Craftable"
	craftable_btn.toggle_mode = true
	UITheme.style_button(craftable_btn, "secondary")
	craftable_btn.toggled.connect(func(pressed: bool):
		craftable_only = pressed
		_update_filter_highlights()
		refresh()
	)
	filter_row.add_child(craftable_btn)
	_filter_buttons.append(craftable_btn)

	var all_btn := Button.new()
	all_btn.text = "All"
	all_btn.toggle_mode = true
	all_btn.button_pressed = true
	UITheme.style_button(all_btn, "secondary")
	all_btn.toggled.connect(func(pressed: bool):
		if pressed:
			craftable_only = false
			_filter_buttons[0].button_pressed = false
		_update_filter_highlights()
		refresh()
	)
	filter_row.add_child(all_btn)
	_filter_buttons.append(all_btn)

func _update_filter_highlights() -> void:
	if _filter_buttons.size() >= 2:
		_filter_buttons[0].button_pressed = craftable_only
		_filter_buttons[1].button_pressed = not craftable_only
		# Visual: active button gets primary style
		UITheme.style_button(_filter_buttons[0], "primary" if craftable_only else "secondary")
		UITheme.style_button(_filter_buttons[1], "primary" if not craftable_only else "secondary")

func _build_toast() -> void:
	_toast_container = HBoxContainer.new()
	_toast_container.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_toast_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_toast_container.add_theme_constant_override("separation", 8)
	_toast_container.visible = false
	_toast_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_container)

	_toast_label = Label.new()
	UITheme.style_toast(_toast_label)
	_toast_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_H2))
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_container.add_child(_toast_label)

func _close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	NetworkManager.request_set_busy.rpc_id(1, false)

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()

func setup(craft_sys: Node) -> void:
	crafting_system = craft_sys
	if crafting_system:
		crafting_system.craft_result.connect(_on_craft_result)

func open_for_station(station: String) -> void:
	current_station = station
	if title_label:
		match station:
			"kitchen":
				title_label.text = "Kitchen"
			"workbench":
				title_label.text = "Workbench"
			"cauldron":
				title_label.text = "Cauldron"
			_:
				title_label.text = "Crafting"
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	NetworkManager.request_set_busy.rpc_id(1, true)
	if search_edit:
		search_edit.text = ""
	refresh()

func refresh() -> void:
	for child in recipe_list.get_children():
		child.queue_free()
	if crafting_system == null:
		return
	var recipes = crafting_system.get_available_recipes(current_station)

	# Apply search filter
	var search_text := search_edit.text.strip_edges().to_lower() if search_edit else ""
	if search_text != "":
		var filtered := []
		for r in recipes:
			if search_text in r.display_name.to_lower():
				filtered.append(r)
		recipes = filtered

	# Apply craftable filter
	if craftable_only:
		var filtered := []
		for r in recipes:
			if r.can_craft and not r.get("locked", false):
				filtered.append(r)
		recipes = filtered

	# Group recipes by type
	var creature_recipes := []
	var item_recipes := []
	var food_recipes := []
	var tool_recipes := []
	for recipe in recipes:
		if recipe.get("result_species_id", "") != "":
			creature_recipes.append(recipe)
		elif recipe.get("result_tool_id", "") != "":
			tool_recipes.append(recipe)
		elif recipe.get("result_food_id", "") != "":
			food_recipes.append(recipe)
		elif recipe.get("result_item_id", "") != "":
			item_recipes.append(recipe)

	# Sort each group: craftable first, then uncraftable, then locked
	creature_recipes = _sort_recipes(creature_recipes)
	food_recipes = _sort_recipes(food_recipes)
	item_recipes = _sort_recipes(item_recipes)
	tool_recipes = _sort_recipes(tool_recipes)

	# Creature recipes section
	if creature_recipes.size() > 0:
		_add_section_header("-- Creature Recipes --")
		for recipe in creature_recipes:
			_add_recipe_row(recipe)

	# Food recipes section
	if food_recipes.size() > 0:
		_add_section_header("-- Food Recipes --")
		for recipe in food_recipes:
			_add_recipe_row(recipe)

	# Held item recipes section
	if item_recipes.size() > 0:
		_add_section_header("-- Held Item Recipes --")
		for recipe in item_recipes:
			_add_recipe_row(recipe)

	# Tool upgrade recipes section
	if tool_recipes.size() > 0:
		_add_section_header("-- Tool Upgrades --")
		for recipe in tool_recipes:
			_add_recipe_row(recipe)

	# Scroll back to top
	if recipe_scroll:
		recipe_scroll.scroll_vertical = 0

func _sort_recipes(recipes: Array) -> Array:
	var craftable := []
	var uncraftable := []
	var locked := []
	for r in recipes:
		if r.get("locked", false):
			locked.append(r)
		elif r.can_craft:
			craftable.append(r)
		else:
			uncraftable.append(r)
	return craftable + uncraftable + locked

func _add_section_header(text: String) -> void:
	var header = Label.new()
	header.text = text
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_subheading(header)
	recipe_list.add_child(header)

func _add_recipe_row(recipe: Dictionary) -> void:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 2)
	recipe_list.add_child(card)

	# Top row: icon + name + badge + craft button
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	card.add_child(hbox)

	# Result icon (32x32)
	DataRegistry.ensure_loaded()
	var result_id := _get_result_id(recipe)
	if result_id != "":
		var result_info = DataRegistry.get_item_display_info(result_id)
		var icon = UITheme.create_item_icon(result_info, 32)
		hbox.add_child(icon)

	# Lock icon for locked recipes
	if recipe.get("locked", false):
		var lock_label = Label.new()
		lock_label.text = "[Locked] "
		UITheme.style_small(lock_label)
		lock_label.add_theme_color_override("font_color", UITokens.INK_LIGHT)
		hbox.add_child(lock_label)

	# Recipe name
	var label = Label.new()
	label.text = recipe.display_name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_body(label)
	if recipe.get("locked", false):
		label.add_theme_color_override("font_color", UITokens.INK_LIGHT)
	hbox.add_child(label)

	# READY badge
	if recipe.can_craft and not recipe.get("locked", false):
		var badge := Label.new()
		badge.text = "READY"
		UITheme.style_badge(badge, "success")
		hbox.add_child(badge)

	# Craft button
	var btn = Button.new()
	btn.text = "Craft"
	UITheme.style_button(btn, "primary")
	btn.disabled = not recipe.can_craft
	var rid = recipe.recipe_id
	btn.pressed.connect(func(): _craft(rid))
	hbox.add_child(btn)

	# Description row (if available)
	var desc_text: String = recipe.get("description", "")
	if desc_text != "":
		var desc_label := Label.new()
		desc_label.text = desc_text
		UITheme.style_caption(desc_label)
		desc_label.add_theme_color_override("font_color", UITokens.INK_SECONDARY)
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(desc_label)
	elif recipe.get("locked", false):
		var hint_label := Label.new()
		hint_label.text = "Find the recipe scroll to unlock"
		UITheme.style_caption(hint_label)
		hint_label.add_theme_color_override("font_color", UITokens.INK_LIGHT)
		card.add_child(hint_label)

	# Result info row (buff info for foods, effect for held items)
	_add_result_info(card, recipe)

	# Ingredients row with icons
	var ing_hbox = HBoxContainer.new()
	ing_hbox.add_theme_constant_override("separation", 4)
	for ing_id in recipe.ingredients:
		var info = recipe.ingredients[ing_id]
		var item_info = DataRegistry.get_item_display_info(ing_id)
		var icon = UITheme.create_item_icon(item_info, 20)
		ing_hbox.add_child(icon)
		var count_label = Label.new()
		count_label.text = "%d/%d " % [info.have, info.needed]
		UITheme.style_small(count_label)
		if info.have >= info.needed:
			count_label.add_theme_color_override("font_color", UITokens.TEXT_SUCCESS)
		else:
			count_label.add_theme_color_override("font_color", UITokens.TEXT_DANGER)
		ing_hbox.add_child(count_label)
	# Show tool requirement
	if recipe.get("requires_tool_ingredient", "") != "":
		var tool_info = DataRegistry.get_item_display_info(recipe.requires_tool_ingredient)
		var tool_icon = UITheme.create_item_icon(tool_info, 20)
		ing_hbox.add_child(tool_icon)
		var tool_label = Label.new()
		var has_it = recipe.get("has_tool_ingredient", false)
		tool_label.text = "OK " if has_it else "Need "
		UITheme.style_small(tool_label)
		if has_it:
			tool_label.add_theme_color_override("font_color", UITokens.TEXT_SUCCESS)
		else:
			tool_label.add_theme_color_override("font_color", UITokens.TEXT_DANGER)
		ing_hbox.add_child(tool_label)
	card.add_child(ing_hbox)

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	card.add_child(sep)

func _add_result_info(card: VBoxContainer, recipe: Dictionary) -> void:
	var food_id: String = recipe.get("result_food_id", "")
	if food_id != "":
		var food = DataRegistry.get_food(food_id)
		if food and food.buff_type != "":
			var info_label := Label.new()
			var buff_text := "Buff: %s" % food.buff_type.replace("_", " ").capitalize()
			if food.buff_value != 0:
				buff_text += " x%.1f" % food.buff_value
			if food.buff_duration_sec > 0:
				buff_text += " (%ds)" % int(food.buff_duration_sec)
			info_label.text = buff_text
			UITheme.style_caption(info_label)
			info_label.add_theme_color_override("font_color", UITokens.TEXT_INFO)
			card.add_child(info_label)
		return

	var item_id: String = recipe.get("result_item_id", "")
	if item_id != "":
		var held = DataRegistry.get_held_item(item_id)
		if held and held.description != "":
			var info_label := Label.new()
			info_label.text = held.description
			UITheme.style_caption(info_label)
			info_label.add_theme_color_override("font_color", UITokens.TEXT_INFO)
			card.add_child(info_label)
		return

	var species_id: String = recipe.get("result_species_id", "")
	if species_id != "":
		var species = DataRegistry.get_species(species_id)
		if species:
			var info_label := Label.new()
			var types_text := ", ".join(PackedStringArray(species.types)) if species.types.size() > 0 else "???"
			info_label.text = "Creature: %s (%s)" % [species.display_name, types_text]
			UITheme.style_caption(info_label)
			info_label.add_theme_color_override("font_color", UITokens.TEXT_INFO)
			card.add_child(info_label)

func _get_result_id(recipe: Dictionary) -> String:
	if recipe.get("result_food_id", "") != "":
		return recipe.result_food_id
	if recipe.get("result_item_id", "") != "":
		return recipe.result_item_id
	if recipe.get("result_tool_id", "") != "":
		return recipe.result_tool_id
	if recipe.get("result_species_id", "") != "":
		return recipe.result_species_id
	return ""

func _craft(recipe_id: String) -> void:
	if crafting_system:
		crafting_system.request_craft.rpc_id(1, recipe_id)

func _on_craft_result(success: bool, result_name: String, message: String) -> void:
	if success:
		_show_toast("Crafted %s!" % result_name, result_name)
	else:
		_show_error(message)
	refresh()

func _show_toast(text: String, _item_name: String) -> void:
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_label.text = text
	_toast_label.add_theme_color_override("font_color", UITokens.STAMP_GOLD)
	_toast_container.modulate = Color(1, 1, 1, 1)
	_toast_container.visible = true
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.5)
	_toast_tween.tween_property(_toast_container, "modulate:a", 0.0, 0.5)
	_toast_tween.tween_callback(func(): _toast_container.visible = false)

func _show_error(message: String) -> void:
	if _error_tween and _error_tween.is_valid():
		_error_tween.kill()
	if _error_label == null:
		_error_label = Label.new()
		_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UITheme.style_small(_error_label)
		_error_label.add_theme_color_override("font_color", UITokens.TEXT_DANGER)
		var vbox = $Panel/VBox
		vbox.add_child(_error_label)
		# Place before close button
		vbox.move_child(_error_label, vbox.get_child_count() - 2)
	_error_label.text = message
	_error_label.visible = true
	_error_label.modulate = Color(1, 1, 1, 1)
	_error_tween = create_tween()
	_error_tween.tween_interval(2.5)
	_error_tween.tween_property(_error_label, "modulate:a", 0.0, 0.5)
	_error_tween.tween_callback(func(): _error_label.visible = false)
