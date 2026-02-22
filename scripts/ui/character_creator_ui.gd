extends CanvasLayer

## Character creation / customization screen.
## Shows a 3D preview of the character with category tabs and part selection grid.
## Used for first-login customization and from the pause menu.

signal appearance_confirmed(appearance: Dictionary)
signal cancelled

const UITokens = preload("res://scripts/ui/ui_tokens.gd")

var is_first_time: bool = false # Disables cancel button for first-time creation
var current_appearance: Dictionary = {}
var _original_appearance: Dictionary = {}

# UI nodes
var bg: ColorRect
var main_hbox: HBoxContainer
var preview_viewport: SubViewport
var preview_camera: Camera3D
var preview_model: Node3D
var preview_container: SubViewportContainer
var preview_root: Node3D  # Node3D container inside SubViewport for CharacterAssembler
var category_buttons: Array[Button] = []
var category_container: VBoxContainer # Sidebar for category buttons
var parts_grid: GridContainer
var parts_scroll: ScrollContainer
var gender_female_btn: Button
var gender_male_btn: Button
var confirm_btn: Button
var cancel_btn: Button
var active_category: String = "head"

# Arrow/cycle navigation
var _arrow_left_btn: Button
var _arrow_right_btn: Button
var _part_label: Label
var _arrow_container: HBoxContainer

# 3D preview rotation & animation
var _preview_dragging: bool = false
var _preview_rotation: float = 0.0
var _preview_anim_tree: AnimationTree = null


func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	UITheme.init()
	_build_ui()


func open(appearance: Dictionary, first_time: bool = false) -> void:
	is_first_time = first_time
	_original_appearance = appearance.duplicate()
	current_appearance = appearance.duplicate()
	# Ensure required keys
	if not current_appearance.has("gender"):
		current_appearance["gender"] = "female"
	for key in ["head_id", "pants_id", "shoes_id"]:
		if not current_appearance.has(key) or current_appearance[key] == "":
			current_appearance[key] = key.replace("_id", "").to_upper() + "_01_1"
	if not current_appearance.has("torso_id") or current_appearance["torso_id"] == "":
		current_appearance["torso_id"] = "TORSO_02_1"
	if not current_appearance.has("arms_id") or current_appearance["arms_id"] == "":
		current_appearance["arms_id"] = "HANDS_01_1"
	visible = true
	cancel_btn.visible = not is_first_time
	_update_gender_buttons()
	_build_category_buttons()
	_select_category("head")
	_rebuild_preview()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	visible = false
	_clear_preview()


func _build_ui() -> void:
	# Dark background
	bg = ColorRect.new()
	bg.color = UITokens.SCRIM_MENU
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	main_hbox = HBoxContainer.new()
	main_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_hbox.set_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_KEEP_SIZE, UITheme.scaled(40))
	main_hbox.add_theme_constant_override("separation", UITheme.scaled(16))
	add_child(main_hbox)

	# --- Left side: 3D Preview ---
	var preview_panel := PanelContainer.new()
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_stretch_ratio = 0.4
	UITheme.style_card(preview_panel)
	main_hbox.add_child(preview_panel)

	var preview_vbox := VBoxContainer.new()
	preview_vbox.add_theme_constant_override("separation", UITheme.scaled(8))
	preview_panel.add_child(preview_vbox)

	# Title
	var title := Label.new()
	UITheme.style_title(title, "Character Creator")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_vbox.add_child(title)

	# SubViewport for 3D preview
	preview_container = SubViewportContainer.new()
	preview_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_container.stretch = true
	preview_vbox.add_child(preview_container)

	preview_viewport = SubViewport.new()
	preview_viewport.size = Vector2i(400, 600)
	preview_viewport.transparent_bg = true
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview_container.add_child(preview_viewport)

	# Node3D root for character model (assemble() requires Node3D parent)
	preview_root = Node3D.new()
	preview_root.name = "PreviewRoot"
	preview_viewport.add_child(preview_root)

	# Camera
	preview_camera = Camera3D.new()
	preview_camera.transform = Transform3D.IDENTITY
	preview_camera.position = Vector3(0, 1.0, 2.5)
	preview_camera.look_at(Vector3(0, 0.8, 0))
	preview_viewport.add_child(preview_camera)

	# Light
	var light := DirectionalLight3D.new()
	light.transform = Transform3D.IDENTITY
	light.rotation_degrees = Vector3(-30, 30, 0)
	light.light_energy = 1.2
	preview_viewport.add_child(light)

	# Ambient light
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = UITokens.PAPER_CARD
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.5
	env.environment = environment
	preview_viewport.add_child(env)

	# Drag hint
	var drag_hint := Label.new()
	UITheme.style_body_text(drag_hint, "Drag to rotate")
	drag_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drag_hint.add_theme_color_override("font_color", UITokens.TEXT_MUTED)
	preview_vbox.add_child(drag_hint)

	# --- Right side: Selection ---
	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 0.6
	UITheme.style_modal(right_panel)
	main_hbox.add_child(right_panel)

	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", UITheme.scaled(12))
	right_panel.add_child(right_vbox)

	# Gender toggle
	var gender_hbox := HBoxContainer.new()
	gender_hbox.add_theme_constant_override("separation", UITheme.scaled(8))
	gender_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	right_vbox.add_child(gender_hbox)

	gender_female_btn = Button.new()
	gender_female_btn.text = "Female"
	UITheme.style_button(gender_female_btn, "secondary")
	gender_female_btn.pressed.connect(_on_gender_selected.bind("female"))
	gender_female_btn.custom_minimum_size.x = UITheme.scaled(120)
	gender_hbox.add_child(gender_female_btn)

	gender_male_btn = Button.new()
	gender_male_btn.text = "Male"
	UITheme.style_button(gender_male_btn, "secondary")
	gender_male_btn.pressed.connect(_on_gender_selected.bind("male"))
	gender_male_btn.custom_minimum_size.x = UITheme.scaled(120)
	gender_hbox.add_child(gender_male_btn)

	# Category + parts area
	var content_hbox := HBoxContainer.new()
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_theme_constant_override("separation", UITheme.scaled(8))
	right_vbox.add_child(content_hbox)

	# Category sidebar
	var cat_scroll := ScrollContainer.new()
	cat_scroll.custom_minimum_size.x = UITheme.scaled(110)
	cat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_hbox.add_child(cat_scroll)

	category_container = VBoxContainer.new()
	category_container.name = "CategoryButtons"
	category_container.add_theme_constant_override("separation", UITheme.scaled(4))
	cat_scroll.add_child(category_container)

	# Parts area: arrow nav + grid
	var parts_vbox := VBoxContainer.new()
	parts_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parts_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parts_vbox.add_theme_constant_override("separation", UITheme.scaled(4))
	content_hbox.add_child(parts_vbox)

	# Arrow navigation row
	_arrow_container = HBoxContainer.new()
	_arrow_container.add_theme_constant_override("separation", UITheme.scaled(4))
	_arrow_container.alignment = BoxContainer.ALIGNMENT_CENTER
	parts_vbox.add_child(_arrow_container)

	_arrow_left_btn = Button.new()
	_arrow_left_btn.text = "<"
	UITheme.style_button(_arrow_left_btn, "secondary")
	_arrow_left_btn.custom_minimum_size = Vector2(UITheme.scaled(28), UITheme.scaled(24))
	_arrow_left_btn.pressed.connect(_cycle_part.bind(-1))
	_arrow_container.add_child(_arrow_left_btn)

	_part_label = Label.new()
	_part_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_part_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_body_text(_part_label, "")
	_arrow_container.add_child(_part_label)

	_arrow_right_btn = Button.new()
	_arrow_right_btn.text = ">"
	UITheme.style_button(_arrow_right_btn, "secondary")
	_arrow_right_btn.custom_minimum_size = Vector2(UITheme.scaled(28), UITheme.scaled(24))
	_arrow_right_btn.pressed.connect(_cycle_part.bind(1))
	_arrow_container.add_child(_arrow_right_btn)

	# Parts grid
	parts_scroll = ScrollContainer.new()
	parts_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parts_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parts_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parts_vbox.add_child(parts_scroll)

	parts_grid = GridContainer.new()
	parts_grid.columns = 4
	parts_grid.add_theme_constant_override("h_separation", UITheme.scaled(8))
	parts_grid.add_theme_constant_override("v_separation", UITheme.scaled(8))
	parts_scroll.add_child(parts_grid)

	# Bottom buttons
	var bottom_hbox := HBoxContainer.new()
	bottom_hbox.add_theme_constant_override("separation", UITheme.scaled(16))
	bottom_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	right_vbox.add_child(bottom_hbox)

	cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	UITheme.style_button(cancel_btn, "secondary")
	cancel_btn.custom_minimum_size.x = UITheme.scaled(140)
	cancel_btn.pressed.connect(_on_cancel)
	bottom_hbox.add_child(cancel_btn)

	var random_btn := Button.new()
	random_btn.text = "Random"
	UITheme.style_button(random_btn, "info")
	random_btn.custom_minimum_size.x = UITheme.scaled(140)
	random_btn.pressed.connect(_on_randomize)
	bottom_hbox.add_child(random_btn)

	confirm_btn = Button.new()
	confirm_btn.text = "Confirm"
	UITheme.style_button(confirm_btn, "primary")
	confirm_btn.custom_minimum_size.x = UITheme.scaled(140)
	confirm_btn.pressed.connect(_on_confirm)
	bottom_hbox.add_child(confirm_btn)

	visible = false


func _update_gender_buttons() -> void:
	var gender: String = current_appearance.get("gender", "female")
	var active_color := UITokens.ACCENT_HONEY
	var inactive_color := UITokens.PAPER_CARD
	gender_female_btn.add_theme_color_override("font_color", UITokens.TEXT_INK if gender == "female" else UITokens.TEXT_MUTED)
	gender_male_btn.add_theme_color_override("font_color", UITokens.TEXT_INK if gender == "male" else UITokens.TEXT_MUTED)
	# Style active gender button
	var fem_style := gender_female_btn.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
	fem_style.bg_color = active_color if gender == "female" else inactive_color
	gender_female_btn.add_theme_stylebox_override("normal", fem_style)
	var male_style := gender_male_btn.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
	male_style.bg_color = active_color if gender == "male" else inactive_color
	gender_male_btn.add_theme_stylebox_override("normal", male_style)


func _build_category_buttons() -> void:
	for btn in category_buttons:
		btn.queue_free()
	category_buttons.clear()

	if category_container == null:
		return

	var gender: String = current_appearance.get("gender", "female")
	var categories := CharacterPartRegistry.get_categories(gender)

	for cat in categories:
		var btn := Button.new()
		var display_name := cat.capitalize()
		btn.text = display_name
		UITheme.style_button(btn, "secondary")
		btn.custom_minimum_size = Vector2(UITheme.scaled(100), UITheme.scaled(36))
		btn.pressed.connect(_select_category.bind(cat))
		category_container.add_child(btn)
		category_buttons.append(btn)


func _select_category(category: String) -> void:
	active_category = category
	AudioManager.play_ui_sfx("ui_tab")
	# Highlight active category button
	for i in range(category_buttons.size()):
		var btn := category_buttons[i]
		var gender: String = current_appearance.get("gender", "female")
		var categories := CharacterPartRegistry.get_categories(gender)
		if i < categories.size() and categories[i] == category:
			var style := btn.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
			if style:
				style.bg_color = UITokens.ACCENT_HONEY
				btn.add_theme_stylebox_override("normal", style)
		else:
			var style := btn.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
			if style:
				style.bg_color = UITokens.PAPER_CARD
				btn.add_theme_stylebox_override("normal", style)
	_build_parts_grid()


func _build_parts_grid() -> void:
	# Clear grid
	for child in parts_grid.get_children():
		child.queue_free()

	var gender: String = current_appearance.get("gender", "female")
	var key: String = CharacterPartRegistry.CATEGORY_KEYS.get(active_category, "")
	var current_part: String = current_appearance.get(key, "")
	var is_optional: bool = active_category in CharacterPartRegistry.OPTIONAL_CATEGORIES

	# Update arrow label with current selection
	_update_arrow_label()

	# "None" option for optional categories
	if is_optional:
		var none_btn := _create_part_button("None", "", current_part == "")
		none_btn.pressed.connect(_on_part_selected.bind(""))
		parts_grid.add_child(none_btn)

	# Available parts
	var parts := CharacterPartRegistry.get_parts(gender, active_category)
	for part_id in parts:
		var is_selected := (part_id == current_part)
		var btn := _create_part_button(part_id, part_id, is_selected)
		btn.pressed.connect(_on_part_selected.bind(part_id))
		parts_grid.add_child(btn)

	# If no parts found, show placeholder
	if parts.is_empty() and not is_optional:
		var placeholder := Label.new()
		UITheme.style_body_text(placeholder, "No parts available.\nImport character assets first.")
		placeholder.add_theme_color_override("font_color", UITokens.TEXT_MUTED)
		parts_grid.add_child(placeholder)


func _create_part_button(display_name: String, part_id: String, is_selected: bool) -> Button:
	var btn := Button.new()
	var size := UITheme.scaled(80)
	btn.custom_minimum_size = Vector2(size, size + UITheme.scaled(24))

	# Try loading sprite icon
	var gender: String = current_appearance.get("gender", "female")
	var icon_path := CharacterPartRegistry.get_icon_path(gender, part_id)
	var icon_tex: Texture2D = load(icon_path) if part_id != "" else null

	if icon_tex:
		btn.icon = icon_tex
		btn.expand_icon = true
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		btn.text = display_name.substr(0, 12) if display_name.length() > 12 else display_name
		btn.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_SMALL))

	# Style
	var style := StyleBoxFlat.new()
	style.bg_color = UITokens.ACCENT_HONEY if is_selected else UITokens.PAPER_CARD
	style.corner_radius_top_left = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	if is_selected:
		style.border_width_bottom = 3
		style.border_width_top = 3
		style.border_width_left = 3
		style.border_width_right = 3
		style.border_color = UITokens.ACCENT_HONEY.darkened(0.2)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)

	return btn


func _on_part_selected(part_id: String) -> void:
	var key: String = CharacterPartRegistry.CATEGORY_KEYS.get(active_category, "")
	if key == "":
		return
	current_appearance[key] = part_id
	AudioManager.play_ui_sfx("ui_click")
	_build_parts_grid()
	_rebuild_preview()


func _on_gender_selected(gender: String) -> void:
	if current_appearance.get("gender", "") == gender:
		return
	AudioManager.play_ui_sfx("ui_tab")
	current_appearance["gender"] = gender
	# Reset to defaults for new gender
	current_appearance["head_id"] = "HEAD_01_1"
	current_appearance["hair_id"] = "HAIR_01_1"
	current_appearance["torso_id"] = "TORSO_02_1"
	current_appearance["pants_id"] = "PANTS_01_1"
	current_appearance["shoes_id"] = "SHOES_01_1"
	current_appearance["arms_id"] = "HANDS_01_1"
	current_appearance["hat_id"] = ""
	current_appearance["glasses_id"] = ""
	current_appearance["beard_id"] = ""
	_update_gender_buttons()
	_build_category_buttons()
	_select_category("head")
	_rebuild_preview()


func _rebuild_preview() -> void:
	_clear_preview()
	if current_appearance.is_empty():
		return
	preview_model = CharacterAssembler.assemble(preview_root, current_appearance)
	if preview_model:
		preview_model.rotation.y = _preview_rotation
		_setup_preview_animation(preview_model)


func _setup_preview_animation(model: Node3D) -> void:
	var lib: AnimationLibrary = load("res://assets/animations/player_animation_library.tres")
	if lib == null:
		return
	# Find the idle animation name
	var idle_name := &"Idle"
	if not lib.has_animation("Idle"):
		var found := false
		for candidate in ["idle", "Idle_Neutral"]:
			if lib.has_animation(candidate):
				idle_name = StringName(candidate)
				found = true
				break
		if not found:
			for anim_name in lib.get_animation_list():
				if "idle" in anim_name.to_lower():
					idle_name = StringName(anim_name)
					found = true
					break
		if not found:
			return
	# Use AnimationTree as standalone AnimationMixer (same as player_controller.gd)
	var anim_tree := AnimationTree.new()
	anim_tree.name = "PreviewAnimTree"
	anim_tree.anim_player = NodePath("")
	anim_tree.add_animation_library(&"", lib)
	model.add_child(anim_tree)
	anim_tree.root_node = anim_tree.get_path_to(model)
	var blend_tree := AnimationNodeBlendTree.new()
	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = idle_name
	blend_tree.add_node(&"Idle", idle_node, Vector2(0, 0))
	blend_tree.connect_node(&"output", 0, &"Idle")
	anim_tree.tree_root = blend_tree
	anim_tree.active = true
	_preview_anim_tree = anim_tree


func _clear_preview() -> void:
	_preview_anim_tree = null
	if preview_model and is_instance_valid(preview_model):
		preview_model.queue_free()
		preview_model = null


func _on_confirm() -> void:
	# Validate all required parts are selected
	var gender: String = current_appearance.get("gender", "female")
	var categories := CharacterPartRegistry.get_categories(gender)
	for cat in categories:
		if cat in CharacterPartRegistry.OPTIONAL_CATEGORIES:
			continue
		var key: String = CharacterPartRegistry.CATEGORY_KEYS.get(cat, "")
		if key == "":
			continue
		var val: String = current_appearance.get(key, "")
		if val == "":
			_show_validation_warning("Please select all required parts before confirming.")
			return
	AudioManager.play_ui_sfx("ui_confirm")
	current_appearance.erase("needs_customization")
	appearance_confirmed.emit(current_appearance)
	close()


func _show_validation_warning(text: String) -> void:
	AudioManager.play_ui_sfx("ui_error")
	# Find or create a warning label above the confirm button
	var existing := confirm_btn.get_parent().get_node_or_null("ValidationWarning")
	if existing:
		existing.text = text
		return
	var warning := Label.new()
	warning.name = "ValidationWarning"
	warning.text = text
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.add_theme_color_override("font_color", UITokens.TEXT_DANGER)
	warning.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_SMALL))
	confirm_btn.get_parent().add_child(warning)
	confirm_btn.get_parent().move_child(warning, 0)


func _on_cancel() -> void:
	AudioManager.play_ui_sfx("ui_cancel")
	current_appearance = _original_appearance.duplicate()
	cancelled.emit()
	close()


func _cycle_part(direction: int) -> void:
	var gender: String = current_appearance.get("gender", "female")
	var key: String = CharacterPartRegistry.CATEGORY_KEYS.get(active_category, "")
	if key == "":
		return
	var parts := CharacterPartRegistry.get_parts(gender, active_category)
	var is_optional: bool = active_category in CharacterPartRegistry.OPTIONAL_CATEGORIES

	# Build full list including "None" for optional categories
	var full_list: Array[String] = []
	if is_optional:
		full_list.append("")
	full_list.append_array(parts)

	if full_list.is_empty():
		return

	var current_part: String = current_appearance.get(key, "")
	var idx := full_list.find(current_part)
	if idx == -1:
		idx = 0
	else:
		idx = (idx + direction) % full_list.size()
		if idx < 0:
			idx += full_list.size()

	AudioManager.play_ui_sfx("ui_click")
	_on_part_selected(full_list[idx])


func _update_arrow_label() -> void:
	if _part_label == null:
		return
	var key: String = CharacterPartRegistry.CATEGORY_KEYS.get(active_category, "")
	var current_part: String = current_appearance.get(key, "")
	if current_part == "":
		_part_label.text = "None"
	else:
		_part_label.text = current_part


func _on_randomize() -> void:
	AudioManager.play_ui_sfx("ui_click")
	var gender: String = current_appearance.get("gender", "female")
	var categories := CharacterPartRegistry.get_categories(gender)
	for cat in categories:
		var key: String = CharacterPartRegistry.CATEGORY_KEYS.get(cat, "")
		if key == "":
			continue
		var parts := CharacterPartRegistry.get_parts(gender, cat)
		if parts.is_empty():
			continue
		var is_optional: bool = cat in CharacterPartRegistry.OPTIONAL_CATEGORIES
		if is_optional and randf() < 0.5:
			current_appearance[key] = ""
		else:
			current_appearance[key] = parts[randi() % parts.size()]
	_build_parts_grid()
	_rebuild_preview()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	# ESC to cancel (if not first-time)
	if event.is_action_pressed("ui_cancel") and not is_first_time:
		get_viewport().set_input_as_handled()
		_on_cancel()
		return
	# Mouse drag to rotate preview
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_preview_dragging = event.pressed
	if event is InputEventMouseMotion and _preview_dragging:
		_preview_rotation += event.relative.x * 0.01
		if preview_model and is_instance_valid(preview_model):
			preview_model.rotation.y = _preview_rotation
