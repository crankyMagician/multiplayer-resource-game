extends CanvasLayer

## Character creation / customization screen.
## Shows a 3D preview of the character with color palette selection.
## Used for first-login customization and from the pause menu.

signal appearance_confirmed(appearance: Dictionary)
signal cancelled

const UITokens = preload("res://scripts/ui/ui_tokens.gd")

# Curated color palette
const COLOR_PALETTE: Array[Color] = [
	# Skin tones
	Color(0.96, 0.87, 0.77), Color(0.87, 0.72, 0.58), Color(0.76, 0.57, 0.42),
	Color(0.55, 0.38, 0.26),
	# Vibrant
	Color(0.2, 0.5, 0.9), Color(0.9, 0.3, 0.3), Color(0.3, 0.8, 0.4),
	Color(0.9, 0.7, 0.2), Color(0.7, 0.3, 0.8), Color(0.2, 0.8, 0.8),
	Color(0.9, 0.5, 0.2), Color(0.8, 0.6, 0.7),
	# Neutrals
	Color(0.9, 0.9, 0.9), Color(0.5, 0.5, 0.5), Color(0.2, 0.2, 0.2),
	Color(0.1, 0.1, 0.15),
]

var is_first_time: bool = false
var current_appearance: Dictionary = {}
var _original_appearance: Dictionary = {}

# UI nodes
var bg: ColorRect
var main_hbox: HBoxContainer
var preview_viewport: SubViewport
var preview_camera: Camera3D
var preview_model: Node3D
var preview_container: SubViewportContainer
var preview_root: Node3D
var confirm_btn: Button
var cancel_btn: Button
var _primary_swatches: Array[Button] = []
var _accent_swatches: Array[Button] = []

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
	# Ensure required color keys
	if not current_appearance.has("primary_color") or not current_appearance["primary_color"] is Dictionary:
		current_appearance["primary_color"] = {"r": 0.2, "g": 0.5, "b": 0.9}
	if not current_appearance.has("accent_color") or not current_appearance["accent_color"] is Dictionary:
		current_appearance["accent_color"] = {"r": 0.9, "g": 0.9, "b": 0.9}
	visible = true
	cancel_btn.visible = not is_first_time
	_update_swatch_highlights()
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

	# Node3D root for character model
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

	# --- Right side: Color Selection ---
	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 0.6
	UITheme.style_modal(right_panel)
	main_hbox.add_child(right_panel)

	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", UITheme.scaled(20))
	right_panel.add_child(right_vbox)

	# Primary color section
	var primary_label := Label.new()
	UITheme.style_title(primary_label, "Body Color")
	right_vbox.add_child(primary_label)

	var primary_grid := GridContainer.new()
	primary_grid.columns = 8
	primary_grid.add_theme_constant_override("h_separation", UITheme.scaled(6))
	primary_grid.add_theme_constant_override("v_separation", UITheme.scaled(6))
	right_vbox.add_child(primary_grid)
	_build_color_swatches(primary_grid, _primary_swatches, "_on_primary_color_selected")

	# Accent color section
	var accent_label := Label.new()
	UITheme.style_title(accent_label, "Accent Color")
	right_vbox.add_child(accent_label)

	var accent_grid := GridContainer.new()
	accent_grid.columns = 8
	accent_grid.add_theme_constant_override("h_separation", UITheme.scaled(6))
	accent_grid.add_theme_constant_override("v_separation", UITheme.scaled(6))
	right_vbox.add_child(accent_grid)
	_build_color_swatches(accent_grid, _accent_swatches, "_on_accent_color_selected")

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(spacer)

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


func _build_color_swatches(grid: GridContainer, swatch_array: Array[Button], callback: String) -> void:
	for i in COLOR_PALETTE.size():
		var btn := Button.new()
		var swatch_size := UITheme.scaled(44)
		btn.custom_minimum_size = Vector2(swatch_size, swatch_size)
		btn.text = ""

		var style := StyleBoxFlat.new()
		style.bg_color = COLOR_PALETTE[i]
		style.corner_radius_top_left = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_right = 6
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style.duplicate())
		btn.add_theme_stylebox_override("pressed", style.duplicate())

		btn.pressed.connect(Callable(self, callback).bind(i))
		grid.add_child(btn)
		swatch_array.append(btn)


func _update_swatch_highlights() -> void:
	var primary := CharacterAssembler._extract_color(current_appearance, "primary_color", Color(0.2, 0.5, 0.9))
	var accent := CharacterAssembler._extract_color(current_appearance, "accent_color", Color(0.9, 0.9, 0.9))
	_highlight_swatches(_primary_swatches, primary)
	_highlight_swatches(_accent_swatches, accent)


func _highlight_swatches(swatches: Array[Button], selected_color: Color) -> void:
	for i in swatches.size():
		var btn := swatches[i]
		var style := btn.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
		if style == null:
			continue
		style.bg_color = COLOR_PALETTE[i]
		if COLOR_PALETTE[i].is_equal_approx(selected_color):
			style.border_width_bottom = 3
			style.border_width_top = 3
			style.border_width_left = 3
			style.border_width_right = 3
			style.border_color = UITokens.ACCENT_HONEY
		else:
			style.border_width_bottom = 0
			style.border_width_top = 0
			style.border_width_left = 0
			style.border_width_right = 0
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style.duplicate())
		btn.add_theme_stylebox_override("pressed", style.duplicate())


func _on_primary_color_selected(index: int) -> void:
	var c := COLOR_PALETTE[index]
	current_appearance["primary_color"] = {"r": c.r, "g": c.g, "b": c.b}
	AudioManager.play_ui_sfx("ui_click")
	_update_swatch_highlights()
	_rebuild_preview()


func _on_accent_color_selected(index: int) -> void:
	var c := COLOR_PALETTE[index]
	current_appearance["accent_color"] = {"r": c.r, "g": c.g, "b": c.b}
	AudioManager.play_ui_sfx("ui_click")
	_update_swatch_highlights()
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
	AudioManager.play_ui_sfx("ui_confirm")
	current_appearance.erase("needs_customization")
	appearance_confirmed.emit(current_appearance)
	close()


func _on_cancel() -> void:
	AudioManager.play_ui_sfx("ui_cancel")
	current_appearance = _original_appearance.duplicate()
	cancelled.emit()
	close()


func _on_randomize() -> void:
	AudioManager.play_ui_sfx("ui_click")
	var pc := COLOR_PALETTE[randi() % COLOR_PALETTE.size()]
	var ac := COLOR_PALETTE[randi() % COLOR_PALETTE.size()]
	current_appearance["primary_color"] = {"r": pc.r, "g": pc.g, "b": pc.b}
	current_appearance["accent_color"] = {"r": ac.r, "g": ac.g, "b": ac.b}
	_update_swatch_highlights()
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
