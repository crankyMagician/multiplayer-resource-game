extends CanvasLayer

const UITokens = preload("res://scripts/ui/ui_tokens.gd")

const SLOT_SIZE := 64
const SLOT_COUNT := 8
const SLOT_GAP := 0
const KEY_LABELS = ["1", "2", "3", "4", "5", "6", "7", "8"]

var slots: Array[PanelContainer] = []
var slot_icons: Array[ColorRect] = []
var slot_labels: Array[Label] = []
var slot_key_labels: Array[Label] = []
var cooldown_overlays: Array[ColorRect] = []
var water_bars: Array[ColorRect] = []

# Client-side cooldown tracking for visual feedback
var _cooldown_ends: Dictionary = {} # slot_index -> end_time_ms
var _cooldown_durations: Dictionary = {} # slot_index -> duration_ms

var _selected_style: StyleBox
var _normal_style: StyleBox
var _empty_style: StyleBox

func _ready() -> void:
	layer = 2
	UITheme.init()
	_selected_style = _make_hotbar_style(UITokens.PAPER_CREAM, UITokens.STAMP_GOLD, 2)
	_normal_style = _make_hotbar_style(UITokens.PAPER_BASE, UITokens.STAMP_BROWN, 1)
	_empty_style = _make_hotbar_style(UITokens.PARCHMENT_DARK, UITokens.INK_LIGHT, 1)

	_build_ui()
	_refresh_all()

	PlayerData.hotbar_changed.connect(_refresh_all)
	PlayerData.hotbar_selection_changed.connect(_on_selection_changed)
	PlayerData.tool_changed.connect(_on_tool_changed)
	PlayerData.inventory_changed.connect(_refresh_all)

func _build_ui() -> void:
	var container = Control.new()
	container.name = "HotbarContainer"
	container.anchor_left = 0.0
	container.anchor_right = 1.0
	container.anchor_top = 1.0
	container.anchor_bottom = 1.0
	container.offset_top = -(SLOT_SIZE + 16)
	container.offset_bottom = -16
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	var total_width = SLOT_COUNT * SLOT_SIZE + (SLOT_COUNT - 1) * SLOT_GAP
	var hbox = HBoxContainer.new()
	hbox.name = "SlotRow"
	hbox.anchor_left = 0.5
	hbox.anchor_right = 0.5
	hbox.anchor_top = 0.0
	hbox.anchor_bottom = 0.0
	hbox.offset_left = -total_width / 2.0
	hbox.offset_right = total_width / 2.0
	hbox.offset_bottom = SLOT_SIZE
	hbox.add_theme_constant_override("separation", SLOT_GAP)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(hbox)

	for i in SLOT_COUNT:
		var panel = PanelContainer.new()
		panel.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(panel)
		slots.append(panel)

		# Icon color indicator (square, centered)
		var icon = ColorRect.new()
		icon.custom_minimum_size = Vector2(32, 32)
		icon.position = Vector2(16, 6)
		icon.size = Vector2(32, 32)
		icon.color = Color.TRANSPARENT
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(icon)
		slot_icons.append(icon)

		# Item name label (abbreviation)
		var label = Label.new()
		label.text = ""
		UITheme.style_small(label)
		label.add_theme_font_size_override("font_size", UITokens.FONT_TINY)
		label.add_theme_color_override("font_color", UITokens.INK_DARK)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = Vector2(0, 40)
		label.size = Vector2(SLOT_SIZE, 14)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(label)
		slot_labels.append(label)

		# Key number label (top-left)
		var key_label = Label.new()
		key_label.text = KEY_LABELS[i]
		UITheme.style_small(key_label)
		key_label.add_theme_font_size_override("font_size", UITokens.FONT_TINY)
		key_label.add_theme_color_override("font_color", UITokens.INK_MEDIUM)
		key_label.position = Vector2(3, 1)
		key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(key_label)
		slot_key_labels.append(key_label)

		# Cooldown overlay (dark bar that shrinks from top)
		var cd_overlay = ColorRect.new()
		cd_overlay.color = UITokens.SCRIM
		cd_overlay.position = Vector2(0, 0)
		cd_overlay.size = Vector2(SLOT_SIZE, 0)
		cd_overlay.visible = false
		cd_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(cd_overlay)
		cooldown_overlays.append(cd_overlay)

		# Water bar (small bar for watering can)
		var water_bar = ColorRect.new()
		water_bar.color = Color(UITokens.STAMP_BLUE.r, UITokens.STAMP_BLUE.g, UITokens.STAMP_BLUE.b, 0.8)
		water_bar.position = Vector2(2, SLOT_SIZE - 6)
		water_bar.size = Vector2(0, 4)
		water_bar.visible = false
		water_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(water_bar)
		water_bars.append(water_bar)

func _refresh_all() -> void:
	PlayerData._init_hotbar()
	DataRegistry.ensure_loaded()
	for i in SLOT_COUNT:
		_refresh_slot(i)
	_update_selection()

func _refresh_slot(index: int) -> void:
	if index >= PlayerData.hotbar.size():
		return
	var slot_data: Dictionary = PlayerData.hotbar[index]
	var icon_color := Color.TRANSPARENT
	var label_text := ""
	var is_empty := slot_data.is_empty()

	if not is_empty:
		var item_type: String = str(slot_data.get("item_type", ""))
		var item_id: String = str(slot_data.get("item_id", ""))
		match item_type:
			"tool_slot":
				match item_id:
					"hoe":
						icon_color = UITokens.STAMP_BROWN
						var tid = PlayerData.equipped_tools.get("hoe", "")
						label_text = _tool_short_name(tid, "Hoe")
					"axe":
						icon_color = UITokens.INK_MEDIUM
						var tid = PlayerData.equipped_tools.get("axe", "")
						label_text = _tool_short_name(tid, "Axe")
					"watering_can":
						icon_color = UITokens.STAMP_BLUE
						var tid = PlayerData.equipped_tools.get("watering_can", "")
						label_text = _tool_short_name(tid, "W. Can")
					"shovel":
						icon_color = UITokens.PARCHMENT_DARK
						var tid = PlayerData.equipped_tools.get("shovel", "")
						label_text = _tool_short_name(tid, "Shovel")
					_:
						icon_color = UITokens.INK_LIGHT
						label_text = item_id.substr(0, 8).capitalize()
			"seed":
				icon_color = UITokens.STAMP_GREEN
				if item_id != "" and item_id != "seeds":
					var info = DataRegistry.get_item_display_info(item_id)
					label_text = str(info.get("display_name", item_id)).substr(0, 8)
				elif PlayerData.selected_seed_id != "":
					var info = DataRegistry.get_item_display_info(PlayerData.selected_seed_id)
					label_text = str(info.get("display_name", "Seeds")).substr(0, 8)
				else:
					label_text = "Seeds"
			"food":
				var info = DataRegistry.get_item_display_info(item_id)
				icon_color = info.get("icon_color", UITokens.STAMP_GOLD)
				label_text = str(info.get("display_name", item_id)).substr(0, 8)
			"battle_item":
				var info = DataRegistry.get_item_display_info(item_id)
				icon_color = info.get("icon_color", UITokens.STAMP_RED)
				label_text = str(info.get("display_name", item_id)).substr(0, 8)
			_:
				var info = DataRegistry.get_item_display_info(item_id)
				icon_color = info.get("icon_color", UITokens.INK_LIGHT)
				label_text = str(info.get("display_name", item_id)).substr(0, 8)

	slot_icons[index].color = icon_color
	slot_labels[index].text = label_text

	# Water bar
	var show_water := false
	if not is_empty and str(slot_data.get("item_type", "")) == "tool_slot" and str(slot_data.get("item_id", "")) == "watering_can":
		show_water = true
		var cap = PlayerData.get_watering_can_capacity()
		var pct = float(PlayerData.watering_can_current) / float(max(cap, 1))
		water_bars[index].size.x = (SLOT_SIZE - 4) * pct
	water_bars[index].visible = show_water

func _tool_short_name(tool_id: String, fallback: String) -> String:
	if tool_id == "":
		return fallback
	var tool_def = DataRegistry.get_tool(tool_id)
	if tool_def:
		# Show tier prefix
		var tier_names = ["", "Brz ", "Irn ", "Gld "]
		var prefix = tier_names[clampi(tool_def.tier, 0, 3)]
		return prefix + fallback
	return fallback

func _make_hotbar_style(bg_color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_corner_radius_all(4)
	style.set_border_width_all(border_width)
	style.content_margin_left = 4
	style.content_margin_top = 4
	style.content_margin_right = 4
	style.content_margin_bottom = 4
	return style

func _update_selection() -> void:
	for i in SLOT_COUNT:
		var slot_data: Dictionary = PlayerData.hotbar[i] if i < PlayerData.hotbar.size() else {}
		if i == PlayerData.selected_hotbar_slot:
			slots[i].add_theme_stylebox_override("panel", _selected_style)
		elif slot_data.is_empty():
			slots[i].add_theme_stylebox_override("panel", _empty_style)
		else:
			slots[i].add_theme_stylebox_override("panel", _normal_style)

func _on_selection_changed(_slot_index: int) -> void:
	_update_selection()
	_refresh_all()

func _on_tool_changed(_tool_name: String) -> void:
	_refresh_all()

func _process(_delta: float) -> void:
	# Update cooldown overlays
	var now = Time.get_ticks_msec()
	for i in _cooldown_ends:
		var end_time: int = _cooldown_ends[i]
		var duration: int = _cooldown_durations.get(i, 1000)
		if now >= end_time:
			cooldown_overlays[i].visible = false
			continue
		cooldown_overlays[i].visible = true
		var remaining = float(end_time - now)
		var pct = remaining / float(max(duration, 1))
		cooldown_overlays[i].size.y = SLOT_SIZE * pct
	# Clean up expired
	var expired: Array = []
	for i in _cooldown_ends:
		if now >= int(_cooldown_ends[i]):
			expired.append(i)
	for i in expired:
		_cooldown_ends.erase(i)
		_cooldown_durations.erase(i)
		if i < cooldown_overlays.size():
			cooldown_overlays[i].visible = false

	# Update water bar every frame (watering can changes frequently)
	for i in SLOT_COUNT:
		if i >= PlayerData.hotbar.size():
			continue
		var sd: Dictionary = PlayerData.hotbar[i]
		if not sd.is_empty() and str(sd.get("item_type", "")) == "tool_slot" and str(sd.get("item_id", "")) == "watering_can":
			water_bars[i].visible = true
			var cap = PlayerData.get_watering_can_capacity()
			var pct = float(PlayerData.watering_can_current) / float(max(cap, 1))
			water_bars[i].size.x = (SLOT_SIZE - 4) * pct

## Start a visual cooldown on the currently selected hotbar slot.
func start_cooldown(duration_sec: float) -> void:
	var idx = PlayerData.selected_hotbar_slot
	if idx < 0 or idx >= SLOT_COUNT:
		return
	var now = Time.get_ticks_msec()
	var dur_ms = int(duration_sec * 1000.0)
	_cooldown_ends[idx] = now + dur_ms
	_cooldown_durations[idx] = dur_ms
