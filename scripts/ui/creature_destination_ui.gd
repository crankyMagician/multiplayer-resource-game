extends CanvasLayer

var panel: PanelContainer = null
var title_label: Label = null
var creature_info_label: Label = null
var storage_button: Button = null
var party_list: VBoxContainer = null
var cancel_button: Button = null
var status_label: Label = null

var pending_creature: Dictionary = {}
var pending_party: Array = []

func _ready() -> void:
	visible = false
	_build_ui()
	NetworkManager.creature_destination_requested.connect(_on_destination_requested)

func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.name = "DestPanel"
	panel.anchors_preset = Control.PRESET_CENTER
	panel.custom_minimum_size = Vector2(400, 350)
	add_child(panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	title_label = Label.new()
	title_label.text = "Party Full — Choose Destination"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title_label)

	creature_info_label = Label.new()
	creature_info_label.text = ""
	creature_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	creature_info_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	vbox.add_child(creature_info_label)

	# Send to Storage button
	storage_button = Button.new()
	storage_button.text = "Send to Storage"
	storage_button.custom_minimum_size.y = 35
	storage_button.pressed.connect(_on_storage_pressed)
	vbox.add_child(storage_button)

	# Separator
	var sep_label = Label.new()
	sep_label.text = "— Or swap with a party member —"
	sep_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sep_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(sep_label)

	# Party list for swapping
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = 120
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	party_list = VBoxContainer.new()
	party_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(party_list)

	# Status label
	status_label = Label.new()
	status_label.text = ""
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color.YELLOW)
	vbox.add_child(status_label)

	# Cancel button
	cancel_button = Button.new()
	cancel_button.text = "Cancel (Creature Lost)"
	cancel_button.custom_minimum_size.y = 30
	cancel_button.pressed.connect(_on_cancel_pressed)
	vbox.add_child(cancel_button)

func _on_destination_requested(creature_data: Dictionary, current_party: Array, storage_size: int, storage_cap: int) -> void:
	pending_creature = creature_data
	pending_party = current_party

	# Update creature info
	DataRegistry.ensure_loaded()
	var species_id: String = str(creature_data.get("species_id", ""))
	var species = DataRegistry.get_species(species_id)
	var display_name: String = species.display_name if species else species_id
	var level: int = int(creature_data.get("level", 1))
	var types: Array = creature_data.get("types", [])
	creature_info_label.text = "%s (Lv %d) [%s]" % [display_name, level, ", ".join(types)]

	# Storage button
	if storage_size >= storage_cap:
		storage_button.text = "Storage Full (%d/%d)" % [storage_size, storage_cap]
		storage_button.disabled = true
	else:
		storage_button.text = "Send to Storage (%d/%d)" % [storage_size, storage_cap]
		storage_button.disabled = false

	# Build party swap list
	for child in party_list.get_children():
		child.queue_free()
	for i in range(current_party.size()):
		var c = current_party[i]
		var c_species_id: String = str(c.get("species_id", ""))
		var c_species = DataRegistry.get_species(c_species_id)
		var c_name: String = c_species.display_name if c_species else c_species_id
		var c_level: int = int(c.get("level", 1))

		var hbox = HBoxContainer.new()
		party_list.add_child(hbox)

		var lbl = Label.new()
		lbl.text = "%s (Lv %d)" % [c_name, c_level]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(lbl)

		var btn = Button.new()
		btn.text = "Swap"
		btn.custom_minimum_size.x = 60
		# Disable swap if only 1 creature or storage full
		if current_party.size() <= 1 or storage_size >= storage_cap:
			btn.disabled = true
		var idx = i
		btn.pressed.connect(func(): _on_swap_pressed(idx))
		hbox.add_child(btn)

	status_label.text = ""
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	NetworkManager.request_set_busy.rpc_id(1, true)

func _on_storage_pressed() -> void:
	NetworkManager.request_creature_destination.rpc_id(1, "storage", -1)
	_close()

func _on_swap_pressed(party_idx: int) -> void:
	NetworkManager.request_creature_destination.rpc_id(1, "swap", party_idx)
	_close()

func _on_cancel_pressed() -> void:
	NetworkManager.cancel_creature_destination.rpc_id(1)
	_close()

func _close() -> void:
	visible = false
	pending_creature = {}
	pending_party = []
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	NetworkManager.request_set_busy.rpc_id(1, false)
