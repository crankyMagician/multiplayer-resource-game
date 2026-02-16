extends Control

# 2D top-down minimap drawn via _draw(). Client-only.
# North (-Z in game world) = up on screen.

const DEFAULT_ZOOM: float = 3.0 # pixels per world unit
const MIN_ZOOM: float = 1.0 # ~120 unit view
const MAX_ZOOM: float = 8.0 # ~20 unit view
const ICON_RADIUS: float = 5.0
const PLAYER_SIZE: float = 8.0

var zoom_level: float = DEFAULT_ZOOM
var _locations_cache: Array = [] # Array of LocationDef

func _ready() -> void:
	DataRegistry.ensure_loaded()
	_locations_cache = DataRegistry.locations.values()
	PlayerData.discovered_locations_changed.connect(_on_locations_changed)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _on_locations_changed() -> void:
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_level = minf(zoom_level * 1.2, MAX_ZOOM)
			queue_redraw()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_level = maxf(zoom_level / 1.2, MIN_ZOOM)
			queue_redraw()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_click(event.position)
			accept_event()

func _handle_click(click_pos: Vector2) -> void:
	var player_pos = _get_player_position()
	var map_center = size / 2.0
	DataRegistry.ensure_loaded()
	# Find closest discovered location to click
	var best_dist: float = 20.0 # max click distance in pixels
	var best_id: String = ""
	for loc in _locations_cache:
		if loc.location_id not in PlayerData.discovered_locations:
			continue
		var screen_pos = _world_to_map(loc.world_position, player_pos, map_center)
		var d = click_pos.distance_to(screen_pos)
		if d < best_dist:
			best_dist = d
			best_id = loc.location_id
	PlayerData.set_compass_target(best_id)
	queue_redraw()

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

func _draw() -> void:
	var player_pos = _get_player_position()
	var map_center = size / 2.0

	# Background
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.08, 0.12, 0.85))

	# Grid lines (every 10 world units)
	_draw_grid(player_pos, map_center)

	# Draw discovered location icons
	for loc in _locations_cache:
		if loc.location_id not in PlayerData.discovered_locations:
			continue
		var sp = _world_to_map(loc.world_position, player_pos, map_center)
		if sp.x < -20 or sp.x > size.x + 20 or sp.y < -20 or sp.y > size.y + 20:
			continue

		# Highlight selected target
		if loc.location_id == PlayerData.compass_target_id:
			draw_arc(sp, ICON_RADIUS + 4, 0, TAU, 24, Color(1, 1, 0.3, 0.8), 2.0)

		draw_circle(sp, ICON_RADIUS, loc.icon_color)

		# Small label
		var font = ThemeDB.fallback_font
		var font_size = 10
		var text_size = font.get_string_size(loc.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(font, sp + Vector2(-text_size.x / 2.0, ICON_RADIUS + 12), loc.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.9, 0.9, 0.9, 0.8))

	# Player marker (triangle pointing in facing direction)
	var camera_yaw = _get_camera_yaw()
	# Camera yaw 0 = facing +Z = south in our map (+Y screen), so map_angle = PI (pointing down)
	# Camera yaw PI = facing -Z = north = up on screen, so map_angle = 0
	var map_angle = PI - camera_yaw # Convert: yaw=0 → south (PI), yaw=PI → north (0)
	var tri_points = PackedVector2Array()
	for i in 3:
		var a = map_angle + i * TAU / 3.0 - PI / 2.0
		tri_points.append(map_center + Vector2(cos(a), sin(a)) * PLAYER_SIZE)
	draw_colored_polygon(tri_points, Color(0.3, 0.8, 1.0))
	draw_circle(map_center, 3.0, Color(1, 1, 1))

	# Compass rose in top-right corner
	var rose_pos = Vector2(size.x - 30, 30)
	var rose_font_size = 12
	draw_string(ThemeDB.fallback_font, rose_pos + Vector2(-4, -15), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, rose_font_size, Color(1, 0.3, 0.3))
	draw_string(ThemeDB.fallback_font, rose_pos + Vector2(-4, 22), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, rose_font_size, Color(0.8, 0.8, 0.8))
	draw_string(ThemeDB.fallback_font, rose_pos + Vector2(12, 4), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, rose_font_size, Color(0.8, 0.8, 0.8))
	draw_string(ThemeDB.fallback_font, rose_pos + Vector2(-20, 4), "W", HORIZONTAL_ALIGNMENT_LEFT, -1, rose_font_size, Color(0.8, 0.8, 0.8))

func _draw_grid(player_pos: Vector3, map_center: Vector2) -> void:
	var grid_spacing: float = 10.0
	var grid_color = Color(0.3, 0.3, 0.35, 0.3)
	# Calculate grid range visible
	var half_view = size / (2.0 * zoom_level)
	var min_x = snappedf(player_pos.x - half_view.x, grid_spacing) - grid_spacing
	var max_x = player_pos.x + half_view.x + grid_spacing
	var min_z = snappedf(player_pos.z - half_view.y, grid_spacing) - grid_spacing
	var max_z = player_pos.z + half_view.y + grid_spacing

	var x = min_x
	while x <= max_x:
		var sp = _world_to_map(Vector3(x, 0, player_pos.z), player_pos, map_center)
		draw_line(Vector2(sp.x, 0), Vector2(sp.x, size.y), grid_color, 1.0)
		x += grid_spacing

	var z = min_z
	while z <= max_z:
		var sp = _world_to_map(Vector3(player_pos.x, 0, z), player_pos, map_center)
		draw_line(Vector2(0, sp.y), Vector2(size.x, sp.y), grid_color, 1.0)
		z += grid_spacing

func _world_to_map(world_pos: Vector3, player_pos: Vector3, map_center: Vector2) -> Vector2:
	var dx = world_pos.x - player_pos.x
	var dz = -(world_pos.z - player_pos.z) # negate so -Z (north) is up
	return map_center + Vector2(dx, dz) * zoom_level

func _get_player_position() -> Vector3:
	var local_player = _get_local_player()
	if local_player:
		return local_player.position
	return Vector3.ZERO

func _get_camera_yaw() -> float:
	var local_player = _get_local_player()
	if local_player and "camera_yaw" in local_player:
		return local_player.camera_yaw
	return 0.0

func _get_local_player() -> Node:
	var players_node = get_node_or_null("/root/Main/GameWorld/Players")
	if players_node == null:
		return null
	var local_id = str(multiplayer.get_unique_id())
	return players_node.get_node_or_null(local_id)
