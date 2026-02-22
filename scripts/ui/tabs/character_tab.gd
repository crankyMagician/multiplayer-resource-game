extends Control

## Pause menu Character tab — shows current appearance summary and a Customize button.

const UITokens = preload("res://scripts/ui/ui_tokens.gd")

var _appearance_label: Label
var _customize_btn: Button


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", UITheme.scaled(16))
	add_child(vbox)

	# Title
	var title := Label.new()
	UITheme.style_title(title, "Character")
	vbox.add_child(title)

	# Current appearance info
	_appearance_label = Label.new()
	UITheme.style_body_text(_appearance_label, "")
	_appearance_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_appearance_label)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# Customize button
	_customize_btn = Button.new()
	_customize_btn.text = "Customize Character"
	UITheme.style_button(_customize_btn, "primary")
	_customize_btn.custom_minimum_size.x = UITheme.scaled(200)
	_customize_btn.pressed.connect(_on_customize_pressed)
	vbox.add_child(_customize_btn)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		_update_info()


func _update_info() -> void:
	if _appearance_label == null:
		return
	var app: Dictionary = PlayerData.appearance
	if app.is_empty() or app.get("needs_customization", false):
		_appearance_label.text = "No character customized yet.\nClick below to create your character!"
		return
	var pc = app.get("primary_color", {})
	var ac = app.get("accent_color", {})
	var primary_text := "Primary: R%.1f G%.1f B%.1f" % [float(pc.get("r", 0)), float(pc.get("g", 0)), float(pc.get("b", 0))]
	var accent_text := "Accent: R%.1f G%.1f B%.1f" % [float(ac.get("r", 0)), float(ac.get("g", 0)), float(ac.get("b", 0))]
	_appearance_label.text = primary_text + "\n" + accent_text


func _on_customize_pressed() -> void:
	# Close pause menu first, then open character creator
	var pause_menu = get_node_or_null("/root/Main/GameWorld/UI/PauseMenu")
	if pause_menu and pause_menu.has_method("close"):
		pause_menu.close()

	# Open character creator
	var game_world = get_node_or_null("/root/Main/GameWorld")
	if game_world and game_world.has_method("open_character_creator"):
		game_world.open_character_creator()
