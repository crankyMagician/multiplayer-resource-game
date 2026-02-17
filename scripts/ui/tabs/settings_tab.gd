extends Control

# Settings tab content for PauseMenu.

var volume_slider: HSlider
var volume_label: Label
var controls_label: Label

const SETTINGS_PATH := "user://settings.cfg"

func _ready() -> void:
	_build_ui()
	_load_settings()

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	# Audio section
	var audio_header := Label.new()
	audio_header.text = "Audio"
	audio_header.add_theme_font_size_override("font_size", 20)
	audio_header.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	vbox.add_child(audio_header)

	var vol_row := HBoxContainer.new()
	vbox.add_child(vol_row)

	var vol_text := Label.new()
	vol_text.text = "Master Volume: "
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
	volume_label.custom_minimum_size.x = 50
	vol_row.add_child(volume_label)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 20
	vbox.add_child(spacer)

	# Controls reference
	var controls_header := Label.new()
	controls_header.text = "Controls"
	controls_header.add_theme_font_size_override("font_size", 20)
	controls_header.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
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

1-8 - Hotbar slots
Scroll - Cycle hotbar"""
	controls_label.add_theme_font_size_override("font_size", 14)
	controls_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(controls_label)

func activate() -> void:
	pass

func deactivate() -> void:
	pass

func _on_volume_changed(value: float) -> void:
	var db := linear_to_db(value)
	AudioServer.set_bus_volume_db(0, db)
	volume_label.text = "%d%%" % int(value * 100)
	_save_settings()

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		var vol = config.get_value("audio", "master_volume", 1.0)
		volume_slider.value = vol
		AudioServer.set_bus_volume_db(0, linear_to_db(vol))
		volume_label.text = "%d%%" % int(vol * 100)

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", volume_slider.value)
	config.save(SETTINGS_PATH)
