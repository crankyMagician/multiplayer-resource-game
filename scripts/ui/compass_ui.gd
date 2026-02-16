extends CanvasLayer

# Always-visible compass strip at top-center of screen.
# Client-only — no server interaction.

const STRIP_WIDTH: float = 400.0
const STRIP_HEIGHT: float = 30.0
const PIXELS_PER_RADIAN: float = STRIP_WIDTH / (PI * 1.0) # ~127 px per radian, shows ~PI range

# Cardinal directions: yaw value when camera faces that direction
# North = -Z (toward wild zones), camera_yaw = PI
# East = +X, camera_yaw = PI/2
# South = +Z (toward restaurants), camera_yaw = 0
# West = -X, camera_yaw = -PI/2
const CARDINALS: Array = [
	{"label": "N", "yaw": PI, "color": Color(1, 0.3, 0.3)},
	{"label": "NE", "yaw": 3.0 * PI / 4.0, "color": Color(0.8, 0.8, 0.8)},
	{"label": "E", "yaw": PI / 2.0, "color": Color(1, 1, 1)},
	{"label": "SE", "yaw": PI / 4.0, "color": Color(0.8, 0.8, 0.8)},
	{"label": "S", "yaw": 0.0, "color": Color(1, 1, 1)},
	{"label": "SW", "yaw": -PI / 4.0, "color": Color(0.8, 0.8, 0.8)},
	{"label": "W", "yaw": -PI / 2.0, "color": Color(1, 1, 1)},
	{"label": "NW", "yaw": -3.0 * PI / 4.0, "color": Color(0.8, 0.8, 0.8)},
]

var strip: Control
var target_label: Label
var target_dropdown: MenuButton
var _indoor: bool = false

func _ready() -> void:
	layer = 5
	_build_ui()
	PlayerData.compass_target_changed.connect(_on_target_changed)
	PlayerData.discovered_locations_changed.connect(_rebuild_dropdown)
	PlayerData.location_changed.connect(_on_location_changed)

func _build_ui() -> void:
	# Background strip
	strip = Control.new()
	strip.clip_contents = true
	strip.custom_minimum_size = Vector2(STRIP_WIDTH, STRIP_HEIGHT)
	strip.set_anchors_preset(Control.PRESET_CENTER_TOP)
	strip.position = Vector2(-STRIP_WIDTH / 2.0, 8)
	strip.size = Vector2(STRIP_WIDTH, STRIP_HEIGHT)
	add_child(strip)

	# Dark background for strip
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.5)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	strip.add_child(bg)

	# Center tick mark
	var tick = ColorRect.new()
	tick.color = Color(1, 1, 0.3, 0.9)
	tick.position = Vector2(STRIP_WIDTH / 2.0 - 1, 0)
	tick.size = Vector2(2, STRIP_HEIGHT)
	strip.add_child(tick)

	# Target distance label (below strip)
	target_label = Label.new()
	target_label.text = ""
	target_label.add_theme_font_size_override("font_size", 12)
	target_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	target_label.position = Vector2(-100, STRIP_HEIGHT + 10)
	target_label.size = Vector2(200, 20)
	add_child(target_label)

	# Target selection dropdown
	target_dropdown = MenuButton.new()
	target_dropdown.text = "Target"
	target_dropdown.flat = true
	target_dropdown.add_theme_font_size_override("font_size", 11)
	target_dropdown.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	target_dropdown.set_anchors_preset(Control.PRESET_CENTER_TOP)
	target_dropdown.position = Vector2(STRIP_WIDTH / 2.0 + 4, 8)
	target_dropdown.size = Vector2(60, STRIP_HEIGHT)
	add_child(target_dropdown)
	target_dropdown.get_popup().id_pressed.connect(_on_dropdown_selected)
	_rebuild_dropdown()

func _process(_delta: float) -> void:
	if _indoor:
		return
	# Get camera yaw from local player
	var camera_yaw: float = _get_camera_yaw()
	_draw_compass(camera_yaw)

func _draw_compass(camera_yaw: float) -> void:
	# Remove old cardinal labels (keep bg at index 0, tick at index 1)
	while strip.get_child_count() > 2:
		var child = strip.get_child(2)
		strip.remove_child(child)
		child.queue_free()

	var center_x = STRIP_WIDTH / 2.0

	# Draw cardinal markers
	for card in CARDINALS:
		var rel = _normalize_angle(card.yaw - camera_yaw)
		var px = center_x + rel * PIXELS_PER_RADIAN
		if px < -30 or px > STRIP_WIDTH + 30:
			continue
		var lbl = Label.new()
		lbl.text = card.label
		lbl.add_theme_font_size_override("font_size", 14 if card.label.length() == 1 else 11)
		lbl.add_theme_color_override("font_color", card.color)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.position = Vector2(px - 12, 2 if card.label.length() == 1 else 5)
		lbl.size = Vector2(24, 20)
		strip.add_child(lbl)

	# Draw target marker
	if PlayerData.compass_target_id != "":
		DataRegistry.ensure_loaded()
		var loc = DataRegistry.get_location(PlayerData.compass_target_id)
		if loc:
			var player_pos = _get_player_position()
			var dx = loc.world_position.x - player_pos.x
			var dz = loc.world_position.z - player_pos.z
			var target_yaw = atan2(dx, dz)
			var rel_angle = _normalize_angle(target_yaw - camera_yaw)
			# Clamp to strip edges
			var clamped_px = clampf(center_x + rel_angle * PIXELS_PER_RADIAN, 4, STRIP_WIDTH - 4)

			var marker = ColorRect.new()
			marker.color = loc.icon_color
			marker.position = Vector2(clamped_px - 4, STRIP_HEIGHT - 8)
			marker.size = Vector2(8, 6)
			strip.add_child(marker)

			# Distance text
			var dist = Vector2(dx, dz).length()
			target_label.text = "%s — %dm" % [loc.display_name, int(dist)]
		else:
			target_label.text = ""
	else:
		target_label.text = ""

func _normalize_angle(angle: float) -> float:
	while angle > PI:
		angle -= TAU
	while angle < -PI:
		angle += TAU
	return angle

func _get_camera_yaw() -> float:
	var local_player = _get_local_player()
	if local_player and "camera_yaw" in local_player:
		return local_player.camera_yaw
	return 0.0

func _get_player_position() -> Vector3:
	var local_player = _get_local_player()
	if local_player:
		return local_player.position
	return Vector3.ZERO

func _get_local_player() -> Node:
	var players_node = get_node_or_null("/root/Main/GameWorld/Players")
	if players_node == null:
		return null
	var local_id = str(multiplayer.get_unique_id())
	return players_node.get_node_or_null(local_id)

func _on_location_changed(zone: String, _owner_name: String) -> void:
	_indoor = (zone == "restaurant")
	strip.visible = not _indoor
	target_label.visible = not _indoor
	target_dropdown.visible = not _indoor

func _on_target_changed(_target_id: String) -> void:
	pass # Compass updates in _process anyway

var _dropdown_ids: Array = [] # Maps popup index -> location_id

func _rebuild_dropdown() -> void:
	if target_dropdown == null:
		return
	var popup = target_dropdown.get_popup()
	popup.clear()
	_dropdown_ids.clear()
	DataRegistry.ensure_loaded()

	# "None" option
	popup.add_item("Clear Target", 0)
	_dropdown_ids.append("")

	# Group discovered locations by category
	var by_category: Dictionary = {}
	for loc_id in PlayerData.discovered_locations:
		var loc = DataRegistry.get_location(loc_id)
		if loc == null:
			continue
		var cat: String = loc.category
		if cat not in by_category:
			by_category[cat] = []
		by_category[cat].append(loc)

	var cat_order = ["zone", "wild_zone", "crafting", "shop", "trainer", "social_npc", "landmark"]
	var idx = 1
	for cat in cat_order:
		if cat not in by_category:
			continue
		popup.add_separator(cat.replace("_", " ").capitalize())
		_dropdown_ids.append("") # separator placeholder
		idx += 1
		for loc in by_category[cat]:
			popup.add_item(loc.display_name, idx)
			_dropdown_ids.append(loc.location_id)
			idx += 1

func _on_dropdown_selected(id: int) -> void:
	if id >= 0 and id < _dropdown_ids.size():
		PlayerData.set_compass_target(_dropdown_ids[id])
