extends CanvasLayer

# Pause overlay with minimap. Toggle with M key.
# Client-only. Sets busy state via existing RPC.

var is_open: bool = false
var bg: ColorRect
var title_label: Label
var hint_label: Label
var minimap: Control # MinimapUI
var indoor_label: Label

func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_set_visible(false)

func _build_ui() -> void:
	# Dark semi-transparent background
	bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Title
	title_label = Label.new()
	title_label.text = "MAP"
	title_label.add_theme_font_size_override("font_size", 28)
	title_label.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title_label.position = Vector2(-100, 20)
	title_label.size = Vector2(200, 40)
	add_child(title_label)

	# Minimap control (centered, square)
	var map_size = 500.0
	var minimap_script = load("res://scripts/ui/minimap_ui.gd")
	minimap = Control.new()
	minimap.set_script(minimap_script)
	minimap.set_anchors_preset(Control.PRESET_CENTER)
	minimap.position = Vector2(-map_size / 2.0, -map_size / 2.0 + 20)
	minimap.size = Vector2(map_size, map_size)
	add_child(minimap)

	# Indoor label (shown when in restaurant)
	indoor_label = Label.new()
	indoor_label.text = "Indoor - Map unavailable"
	indoor_label.add_theme_font_size_override("font_size", 20)
	indoor_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	indoor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	indoor_label.set_anchors_preset(Control.PRESET_CENTER)
	indoor_label.position = Vector2(-150, -20)
	indoor_label.size = Vector2(300, 40)
	indoor_label.visible = false
	add_child(indoor_label)

	# Close hint
	hint_label = Label.new()
	hint_label.text = "M to close  |  Scroll to zoom  |  Click to set target"
	hint_label.add_theme_font_size_override("font_size", 14)
	hint_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.position = Vector2(-250, -40)
	hint_label.size = Vector2(500, 30)
	add_child(hint_label)

func _input(event: InputEvent) -> void:
	if not _is_local_client():
		return

	var toggle = false
	if event.is_action_pressed("open_map") and not _is_other_ui_open():
		toggle = true

	if toggle:
		if is_open:
			_close()
		else:
			_open()
		get_viewport().set_input_as_handled()

func _open() -> void:
	is_open = true
	var is_indoor = (PlayerData.current_zone == "restaurant")
	minimap.visible = not is_indoor
	indoor_label.visible = is_indoor
	_set_visible(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if multiplayer.multiplayer_peer != null:
		NetworkManager.request_set_busy.rpc_id(1, true)

func _close() -> void:
	is_open = false
	_set_visible(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if multiplayer.multiplayer_peer != null:
		NetworkManager.request_set_busy.rpc_id(1, false)

func _set_visible(v: bool) -> void:
	bg.visible = v
	title_label.visible = v
	hint_label.visible = v
	if not v:
		minimap.visible = false
		indoor_label.visible = false

func _is_other_ui_open() -> bool:
	var ui_node = get_node_or_null("/root/Main/GameWorld/UI")
	if ui_node == null:
		return false
	var blocking_names := ["BattleUI", "CraftingUI", "InventoryUI", "PartyUI",
		"StorageUI", "ShopUI", "TradeUI", "DialogueUI", "CalendarUI",
		"QuestLogUI", "CompendiumUI", "CreatureDestinationUI", "FriendListUI"]
	for ui_name in blocking_names:
		var child = ui_node.get_node_or_null(ui_name)
		if child == null:
			continue
		if child is CanvasLayer:
			if not child.visible:
				continue
			for sub in child.get_children():
				if sub is Control and sub.visible:
					return true
		elif child is Control and child.visible:
			for sub in child.get_children():
				if sub is Control and sub.visible:
					return true
	return false

func _is_local_client() -> bool:
	if multiplayer.multiplayer_peer == null:
		return true
	return not multiplayer.is_server()
