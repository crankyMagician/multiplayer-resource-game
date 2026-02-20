extends Control

# Settings tab content for PauseMenu.
const UITokens = preload("res://scripts/ui/ui_tokens.gd")

var volume_slider: HSlider
var volume_label: Label
var controls_label: Label

var font_size_slider: HSlider
var font_size_label: Label
var text_speed_slider: HSlider
var text_speed_label: Label

const SETTINGS_PATH := "user://settings.cfg"

const FONT_SCALE_STEPS: Array = [0.85, 1.0, 1.15, 1.3]
const FONT_SCALE_NAMES: Array = ["Small", "Normal", "Large", "Extra Large"]
const TEXT_SPEED_CPS: Array = [20.0, 40.0, 80.0, -1.0]
const TEXT_SPEED_NAMES: Array = ["Slow", "Normal", "Fast", "Instant"]

func _ready() -> void:
	UITheme.init()
	_build_ui()
	_load_settings()

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	# Audio section
	var audio_header := Label.new()
	audio_header.text = "Audio"
	UITheme.style_subheading(audio_header)
	audio_header.add_theme_color_override("font_color", UITokens.STAMP_GOLD)
	vbox.add_child(audio_header)

	var vol_row := HBoxContainer.new()
	vbox.add_child(vol_row)

	var vol_text := Label.new()
	vol_text.text = "Master Volume: "
	UITheme.style_small(vol_text)
	vol_row.add_child(vol_text)

	volume_slider = HSlider.new()
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.05
	volume_slider.value = 1.0
	volume_slider.custom_minimum_size = Vector2(200, 20)
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.value_changed.connect(_on_volume_changed)
	vol_row.add_child(volume_slider)

	volume_label = Label.new()
	volume_label.text = "100%"
	volume_label.custom_minimum_size.x = 60
	UITheme.style_small(volume_label)
	vol_row.add_child(volume_label)

	# Spacer
	var spacer1 := Control.new()
	spacer1.custom_minimum_size.y = 20
	vbox.add_child(spacer1)

	# Accessibility section
	var access_header := Label.new()
	access_header.text = "Accessibility"
	UITheme.style_subheading(access_header)
	access_header.add_theme_color_override("font_color", UITokens.STAMP_GOLD)
	vbox.add_child(access_header)

	# Font Size slider
	var font_row := HBoxContainer.new()
	vbox.add_child(font_row)

	var font_text := Label.new()
	font_text.text = "Font Size: "
	UITheme.style_small(font_text)
	font_row.add_child(font_text)

	font_size_slider = HSlider.new()
	font_size_slider.min_value = 0
	font_size_slider.max_value = 3
	font_size_slider.step = 1
	font_size_slider.value = 1
	font_size_slider.custom_minimum_size = Vector2(200, 20)
	font_size_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	font_size_slider.value_changed.connect(_on_font_size_changed)
	font_row.add_child(font_size_slider)

	font_size_label = Label.new()
	font_size_label.text = "Normal"
	font_size_label.custom_minimum_size.x = 100
	UITheme.style_small(font_size_label)
	font_row.add_child(font_size_label)

	# Text Speed slider
	var speed_row := HBoxContainer.new()
	vbox.add_child(speed_row)

	var speed_text := Label.new()
	speed_text.text = "Text Speed: "
	UITheme.style_small(speed_text)
	speed_row.add_child(speed_text)

	text_speed_slider = HSlider.new()
	text_speed_slider.min_value = 0
	text_speed_slider.max_value = 3
	text_speed_slider.step = 1
	text_speed_slider.value = 1
	text_speed_slider.custom_minimum_size = Vector2(200, 20)
	text_speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_speed_slider.value_changed.connect(_on_text_speed_changed)
	speed_row.add_child(text_speed_slider)

	text_speed_label = Label.new()
	text_speed_label.text = "Normal"
	text_speed_label.custom_minimum_size.x = 100
	UITheme.style_small(text_speed_label)
	speed_row.add_child(text_speed_label)

	# Reset to Defaults button
	var reset_spacer := Control.new()
	reset_spacer.custom_minimum_size.y = 10
	vbox.add_child(reset_spacer)

	var reset_btn := Button.new()
	reset_btn.text = "Reset to Defaults"
	UITheme.style_button(reset_btn, "danger")
	reset_btn.pressed.connect(_reset_to_defaults)
	vbox.add_child(reset_btn)

	# Spacer
	var spacer2 := Control.new()
	spacer2.custom_minimum_size.y = 20
	vbox.add_child(spacer2)

	# Controls reference
	var controls_header := Label.new()
	controls_header.text = "Controls"
	UITheme.style_subheading(controls_header)
	controls_header.add_theme_color_override("font_color", UITokens.STAMP_GOLD)
	vbox.add_child(controls_header)

	controls_label = Label.new()
	controls_label.text = """WASD - Move
Mouse - Look around
E - Interact
V - PvP Challenge
T - Trade

M / Esc - Map
I - Inventory
P - Party (Creatures)
J - Quest Log
K - Compendium
F - Friends & Party
N - NPCs

1-8 - Hotbar slots
Scroll - Cycle hotbar"""
	UITheme.style_small(controls_label)
	controls_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_SMALL))
	controls_label.add_theme_color_override("font_color", UITokens.INK_MEDIUM)
	vbox.add_child(controls_label)

func activate() -> void:
	pass

func deactivate() -> void:
	pass

func _reset_to_defaults() -> void:
	volume_slider.value = 1.0
	font_size_slider.value = 1
	text_speed_slider.value = 1

func _on_volume_changed(value: float) -> void:
	var db := linear_to_db(value)
	AudioServer.set_bus_volume_db(0, db)
	volume_label.text = "%d%%" % int(value * 100)
	_save_settings()

func _on_font_size_changed(value: float) -> void:
	var idx := int(value)
	font_size_label.text = FONT_SCALE_NAMES[idx]
	UITheme.set_font_scale(FONT_SCALE_STEPS[idx])
	_save_settings()

func _on_text_speed_changed(value: float) -> void:
	var idx := int(value)
	text_speed_label.text = TEXT_SPEED_NAMES[idx]
	UITheme.set_text_speed(TEXT_SPEED_CPS[idx])
	_save_settings()

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		var vol = config.get_value("audio", "master_volume", 1.0)
		volume_slider.value = vol
		AudioServer.set_bus_volume_db(0, linear_to_db(vol))
		volume_label.text = "%d%%" % int(vol * 100)

		# Font scale — prefer saved index, fall back to float lookup for old configs
		var font_idx: int = config.get_value("accessibility", "font_scale_idx", -1)
		if font_idx < 0 or font_idx >= FONT_SCALE_STEPS.size():
			var font_scale: float = config.get_value("accessibility", "font_scale", 1.0)
			font_idx = FONT_SCALE_STEPS.find(font_scale)
			if font_idx < 0:
				font_idx = 1
		font_size_slider.value = font_idx
		font_size_label.text = FONT_SCALE_NAMES[font_idx]
		UITheme.set_font_scale(FONT_SCALE_STEPS[font_idx])

		# Text speed — prefer saved index, fall back to float lookup for old configs
		var speed_idx: int = config.get_value("accessibility", "text_speed_idx", -1)
		if speed_idx < 0 or speed_idx >= TEXT_SPEED_CPS.size():
			var text_cps: float = config.get_value("accessibility", "text_speed_cps", 40.0)
			speed_idx = TEXT_SPEED_CPS.find(text_cps)
			if speed_idx < 0:
				speed_idx = 1
		text_speed_slider.value = speed_idx
		text_speed_label.text = TEXT_SPEED_NAMES[speed_idx]
		UITheme.set_text_speed(TEXT_SPEED_CPS[speed_idx])

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", volume_slider.value)
	var font_idx := int(font_size_slider.value)
	config.set_value("accessibility", "font_scale", FONT_SCALE_STEPS[font_idx])
	config.set_value("accessibility", "font_scale_idx", font_idx)
	var speed_idx := int(text_speed_slider.value)
	config.set_value("accessibility", "text_speed_cps", TEXT_SPEED_CPS[speed_idx])
	config.set_value("accessibility", "text_speed_idx", speed_idx)
	config.save(SETTINGS_PATH)
