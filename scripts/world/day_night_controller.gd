extends Node
## Client-side day/night cycle controller.
## Drives the sky shader, sun light, and ambient lighting based on SeasonManager time.
## Also spawns weather VFX particles (rain, lightning, wind leaves).
## Exits immediately on dedicated server (no visuals needed).

# Season preset sky colors — saturated pastels for kawaii toon aesthetic
const SEASON_SKY := {
	"spring": {
		"sky_day": Color(0.10, 0.45, 0.70),
		"horizon_day": Color(0.90, 0.92, 0.80),
		"sky_sunset": Color(0.15, 0.25, 0.40),
		"horizon_sunset": Color(1.0, 0.40, 0.22),
		"sky_night": Color(0.12, 0.10, 0.18),
		"horizon_night": Color(0.15, 0.17, 0.20),
		"cloud_density": 1.0,
	},
	"summer": {
		"sky_day": Color(0.10, 0.42, 0.75),
		"horizon_day": Color(0.95, 0.90, 0.72),
		"sky_sunset": Color(0.18, 0.22, 0.42),
		"horizon_sunset": Color(1.0, 0.48, 0.18),
		"sky_night": Color(0.10, 0.08, 0.16),
		"horizon_night": Color(0.12, 0.14, 0.15),
		"cloud_density": 0.7,
	},
	"autumn": {
		"sky_day": Color(0.18, 0.32, 0.58),
		"horizon_day": Color(0.92, 0.80, 0.58),
		"sky_sunset": Color(0.24, 0.18, 0.30),
		"horizon_sunset": Color(0.95, 0.42, 0.24),
		"sky_night": Color(0.11, 0.09, 0.14),
		"horizon_night": Color(0.14, 0.12, 0.16),
		"cloud_density": 1.5,
	},
	"winter": {
		"sky_day": Color(0.30, 0.35, 0.72),
		"horizon_day": Color(0.80, 0.88, 0.95),
		"sky_sunset": Color(0.20, 0.24, 0.38),
		"horizon_sunset": Color(0.90, 0.48, 0.45),
		"sky_night": Color(0.08, 0.10, 0.24),
		"horizon_night": Color(0.13, 0.16, 0.25),
		"cloud_density": 1.8,
	},
}

# Weather light energy targets
const WEATHER_LIGHT := {
	"sunny": 1.0,
	"rainy": 0.5,
	"stormy": 0.3,
	"windy": 0.85,
}

# Weather cloud density offsets (added to season base)
const WEATHER_CLOUD_OFFSET := {
	"sunny": 0.0,
	"rainy": 1.8,
	"stormy": 2.8,
	"windy": 0.3,
}

# Weather wind speed multipliers
const WEATHER_WIND := {
	"sunny": Vector2(0.05, 0.05),
	"rainy": Vector2(0.08, 0.08),
	"stormy": Vector2(0.15, 0.12),
	"windy": Vector2(0.12, 0.10),
}

var _dir_light: DirectionalLight3D
var _sky_material: ShaderMaterial
var _world_env: WorldEnvironment
var _season_mgr: Node
var _target_light_energy: float = 1.0
var _current_season: String = "spring"
var _current_weather: String = "sunny"
var _tween: Tween

# Weather VFX
var _weather_particles: Array[Node] = []
var _lightning_timer: Timer
var _lightning_flash_active: bool = false
var _base_light_energy: float = 1.0
var _camera: Camera3D

func _ready() -> void:
	# Server headless guard — no visuals needed
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	# Also skip on server peer (even if not headless, server doesn't render game world)
	if multiplayer.is_server():
		set_process(false)
		return

	# Find existing DirectionalLight3D
	_dir_light = get_node_or_null("../Environment/DirectionalLight3D")
	if not _dir_light:
		push_warning("[DayNightController] No DirectionalLight3D found at Environment/DirectionalLight3D")
		set_process(false)
		return

	# Load the spring sky material as base
	var base_mat := load("res://assets/sky/material/basic/warm_material_01.tres") as ShaderMaterial
	if not base_mat:
		push_warning("[DayNightController] Could not load sky material")
		set_process(false)
		return

	# Duplicate so we don't modify the shared resource
	_sky_material = base_mat.duplicate() as ShaderMaterial
	_sky_material.set_shader_parameter("use_directional_light", true)
	_sky_material.set_shader_parameter("day_night_mix", 1.0)

	# Cartoon sky overrides: puffier clouds, cel-shading, bigger sun
	_sky_material.set_shader_parameter("cloud_shape_exponent", 0.4)
	_sky_material.set_shader_parameter("cloud_tiling", Vector2(0.25, 0.25))
	_sky_material.set_shader_parameter("cloud_depth", 0.0)
	_sky_material.set_shader_parameter("cloud_steps", 4)
	_sky_material.set_shader_parameter("sun_scale", 0.08)

	# Create Sky + WorldEnvironment
	var sky := Sky.new()
	sky.sky_material = _sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0

	_world_env = WorldEnvironment.new()
	_world_env.name = "SkyEnvironment"
	_world_env.environment = env
	add_child(_world_env)

	# Find SeasonManager
	_season_mgr = get_node_or_null("../SeasonManager")
	if _season_mgr:
		if _season_mgr.has_signal("season_changed"):
			_season_mgr.season_changed.connect(_on_season_changed)
		if _season_mgr.has_signal("weather_changed"):
			_season_mgr.weather_changed.connect(_on_weather_changed)
		# Initialize to current state
		if _season_mgr.has_method("get_current_season"):
			_current_season = _season_mgr.get_current_season()
			_apply_season_colors_immediate(_current_season)
		if _season_mgr.has_method("get_weather_name"):
			_current_weather = _season_mgr.get_weather_name()
			_apply_weather_immediate(_current_weather)

func _process(_delta: float) -> void:
	if not _season_mgr or not _dir_light or not _sky_material:
		return

	# Get day progress (0-1)
	var progress: float = _season_mgr.get_day_progress()

	# Map progress to sun angle:
	# 0.0 = sunrise (east), 0.25 = noon (top), 0.5 = sunset (west), 0.75 = midnight (bottom)
	var sun_angle: float = (progress - 0.25) * TAU
	_dir_light.rotation.x = sun_angle
	# Keep Y rotation for sun direction (slightly angled, not straight overhead)
	_dir_light.rotation.y = deg_to_rad(-30)

	# Compute day_factor from sun height (how much "daytime" there is)
	# sin of sun_angle: 1.0 at noon, -1.0 at midnight
	var sun_height: float = -sin(sun_angle) # Negative because Godot's -Z is forward
	var day_factor: float = clampf(sun_height * 2.0 + 0.5, 0.0, 1.0)

	# Lerp light properties (skip if lightning flash is active)
	if not _lightning_flash_active:
		var night_energy := 0.05
		_base_light_energy = lerpf(night_energy, _target_light_energy, day_factor)
		_dir_light.light_energy = _base_light_energy
	_dir_light.light_color = Color(1.0, 0.97, 0.92).lerp(Color(0.4, 0.45, 0.7), 1.0 - day_factor)

	# Shadow softness at night
	_dir_light.shadow_enabled = day_factor > 0.05

	# Ambient light (skip if lightning flash)
	if _world_env and _world_env.environment and not _lightning_flash_active:
		_world_env.environment.ambient_light_energy = lerpf(0.05, 0.3, day_factor)

	# Day/night mix for sky shader (-1 = night, 0 = sunset, 1 = day)
	var mix: float = clampf(sun_height * 2.0, -1.0, 1.0)
	_sky_material.set_shader_parameter("day_night_mix", mix)

	# Follow camera for weather particles
	_update_weather_particle_positions()

func _on_season_changed(new_season: String) -> void:
	_current_season = new_season
	_tween_season_colors(new_season)

func _on_weather_changed(new_weather: String) -> void:
	_current_weather = new_weather
	_tween_weather(new_weather)
	_update_weather_vfx(new_weather)

func _apply_season_colors_immediate(season: String) -> void:
	if not _sky_material:
		return
	var preset: Dictionary = SEASON_SKY.get(season, SEASON_SKY["spring"])
	for param in ["sky_day", "horizon_day", "sky_sunset", "horizon_sunset", "sky_night", "horizon_night"]:
		if preset.has(param):
			_sky_material.set_shader_parameter(param, preset[param])
	_sky_material.set_shader_parameter("cloud_density", float(preset.get("cloud_density", 0.7)))

func _tween_season_colors(season: String) -> void:
	if not _sky_material:
		return
	var preset: Dictionary = SEASON_SKY.get(season, SEASON_SKY["spring"])
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	for param in ["sky_day", "horizon_day", "sky_sunset", "horizon_sunset", "sky_night", "horizon_night"]:
		if preset.has(param):
			var current: Color = _sky_material.get_shader_parameter(param)
			_tween.tween_method(
				func(val: Color): _sky_material.set_shader_parameter(param, val),
				current, preset[param] as Color, 3.0
			)
	var current_density: float = _sky_material.get_shader_parameter("cloud_density")
	var target_density: float = float(preset.get("cloud_density", 0.7)) + float(WEATHER_CLOUD_OFFSET.get(_current_weather, 0.0))
	_tween.tween_method(
		func(val: float): _sky_material.set_shader_parameter("cloud_density", val),
		current_density, target_density, 3.0
	)

func _apply_weather_immediate(weather: String) -> void:
	_target_light_energy = float(WEATHER_LIGHT.get(weather, 1.0))
	if _sky_material:
		var season_preset: Dictionary = SEASON_SKY.get(_current_season, SEASON_SKY["spring"])
		var base_density: float = float(season_preset.get("cloud_density", 0.7))
		var offset: float = float(WEATHER_CLOUD_OFFSET.get(weather, 0.0))
		_sky_material.set_shader_parameter("cloud_density", base_density + offset)
		var wind: Vector2 = WEATHER_WIND.get(weather, Vector2(0.05, 0.05))
		_sky_material.set_shader_parameter("wind_speed", wind)
	_update_weather_vfx(weather)

func _tween_weather(weather: String) -> void:
	_target_light_energy = float(WEATHER_LIGHT.get(weather, 1.0))
	if not _sky_material:
		return
	var season_preset: Dictionary = SEASON_SKY.get(_current_season, SEASON_SKY["spring"])
	var base_density: float = float(season_preset.get("cloud_density", 0.7))
	var offset: float = float(WEATHER_CLOUD_OFFSET.get(weather, 0.0))
	var target_density: float = base_density + offset
	var target_wind: Vector2 = WEATHER_WIND.get(weather, Vector2(0.05, 0.05))
	var current_density: float = _sky_material.get_shader_parameter("cloud_density")
	var current_wind: Vector2 = _sky_material.get_shader_parameter("wind_speed")
	var tw := create_tween().set_parallel(true)
	tw.tween_method(
		func(val: float): _sky_material.set_shader_parameter("cloud_density", val),
		current_density, target_density, 2.0
	)
	tw.tween_method(
		func(val: Vector2): _sky_material.set_shader_parameter("wind_speed", val),
		current_wind, target_wind, 2.0
	)

# ── Weather VFX ──────────────────────────────────────────────────────────────

func _update_weather_vfx(weather: String) -> void:
	_clear_weather_particles()
	match weather:
		"rainy":
			_spawn_rain(false)
		"stormy":
			_spawn_rain(true)
			_start_lightning()
		"windy":
			_spawn_wind_leaves()

func _clear_weather_particles() -> void:
	for node in _weather_particles:
		if is_instance_valid(node):
			node.queue_free()
	_weather_particles.clear()
	_stop_lightning()

func _find_camera() -> Camera3D:
	if is_instance_valid(_camera):
		return _camera
	_camera = get_viewport().get_camera_3d()
	return _camera

func _update_weather_particle_positions() -> void:
	var cam := _find_camera()
	if not cam:
		return
	var cam_pos := cam.global_position
	for node in _weather_particles:
		if is_instance_valid(node) and node is GPUParticles3D:
			node.global_position = cam_pos + Vector3(0.0, 12.0, 0.0)

# ── Rain ─────────────────────────────────────────────────────────────────────

func _spawn_rain(is_storm: bool) -> void:
	var rain := GPUParticles3D.new()
	rain.name = "RainParticles"
	rain.amount = 600 if is_storm else 300
	rain.lifetime = 1.5
	rain.visibility_aabb = AABB(Vector3(-15, -15, -15), Vector3(30, 30, 30))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 5.0 if not is_storm else 15.0
	mat.initial_velocity_min = 10.0
	mat.initial_velocity_max = 14.0 if is_storm else 12.0
	mat.gravity = Vector3(0, -2, 0)

	# Box emitter 20x1x20
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(10.0, 0.5, 10.0)

	rain.process_material = mat

	# Mesh: tiny stretched quad for rain streaks
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.02, 0.15)
	rain.draw_pass_1 = mesh

	# Material: semi-transparent white-blue, y-billboard
	var draw_mat := StandardMaterial3D.new()
	draw_mat.albedo_color = Color(0.7, 0.8, 1.0, 0.35)
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.no_depth_test = true
	mesh.material = draw_mat

	add_child(rain)
	_weather_particles.append(rain)

# ── Lightning ────────────────────────────────────────────────────────────────

func _start_lightning() -> void:
	_stop_lightning()
	_lightning_timer = Timer.new()
	_lightning_timer.name = "LightningTimer"
	_lightning_timer.one_shot = true
	_lightning_timer.timeout.connect(_on_lightning_strike)
	add_child(_lightning_timer)
	_lightning_timer.start(randf_range(8.0, 20.0))

func _stop_lightning() -> void:
	if is_instance_valid(_lightning_timer):
		_lightning_timer.queue_free()
		_lightning_timer = null
	_lightning_flash_active = false

func _on_lightning_strike() -> void:
	if not _dir_light or _current_weather != "stormy":
		return

	_lightning_flash_active = true
	_dir_light.light_energy = 3.0
	if _world_env and _world_env.environment:
		_world_env.environment.ambient_light_energy = 0.8

	# Flash duration 0.1s, then restore
	var tw := create_tween()
	tw.tween_interval(0.1)
	tw.tween_callback(_end_lightning_flash)

	# Schedule next strike
	if is_instance_valid(_lightning_timer):
		_lightning_timer.start(randf_range(8.0, 20.0))

func _end_lightning_flash() -> void:
	_lightning_flash_active = false
	# _process will restore normal light energy on next frame

# ── Wind Leaves ──────────────────────────────────────────────────────────────

func _spawn_wind_leaves() -> void:
	var leaves := GPUParticles3D.new()
	leaves.name = "WindLeaves"
	leaves.amount = 30
	leaves.lifetime = 4.0
	leaves.visibility_aabb = AABB(Vector3(-15, -15, -15), Vector3(30, 30, 30))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(1, 0.1, 0.3).normalized()
	mat.spread = 25.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 4.0
	mat.gravity = Vector3(0, -0.3, 0)
	mat.angular_velocity_min = -180.0
	mat.angular_velocity_max = 180.0

	# Box emitter around camera
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(8.0, 4.0, 8.0)

	leaves.process_material = mat

	# Mesh: small flat quad for leaf shape
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.08, 0.06)
	leaves.draw_pass_1 = mesh

	# Material: green-brown tinted, billboard
	var draw_mat := StandardMaterial3D.new()
	draw_mat.albedo_color = Color(0.45, 0.55, 0.25, 0.8)
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = draw_mat

	add_child(leaves)
	_weather_particles.append(leaves)
