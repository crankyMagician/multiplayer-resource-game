extends Node3D

signal state_changed(new_state: int)

enum PlotState { WILD, CLEARED, TILLED, PLANTED, WATERED, GROWING, READY, WILTING, DEAD }

# Synced state
var plot_state: int = PlotState.WILD
var planted_seed_id: String = ""
var growth_progress: float = 0.0
var water_level: float = 0.0
var owner_peer_id: int = 0

# Config
var grow_time: float = 60.0
var water_drain_rate: float = 0.02 # water drains per second
var wilt_timer: float = 0.0
var wilt_threshold: float = 30.0 # seconds without water before wilting
var dead_threshold: float = 60.0 # seconds wilting before dead

# Visuals
@onready var base_mesh: MeshInstance3D = $BaseMesh
@onready var plant_mesh: MeshInstance3D = $PlantMesh
@onready var fruit_mesh: MeshInstance3D = $FruitMesh
@onready var interaction_area: Area3D = $InteractionArea

# Materials
var mat_wild := StandardMaterial3D.new()
var mat_cleared := StandardMaterial3D.new()
var mat_tilled := StandardMaterial3D.new()
var mat_watered := StandardMaterial3D.new()
var mat_dead := StandardMaterial3D.new()

func _ready() -> void:
	mat_wild.albedo_color = Color(0.25, 0.35, 0.15)
	mat_cleared.albedo_color = Color(0.55, 0.4, 0.25)
	mat_tilled.albedo_color = Color(0.35, 0.25, 0.15)
	mat_watered.albedo_color = Color(0.2, 0.15, 0.1)
	mat_dead.albedo_color = Color(0.4, 0.35, 0.3)
	_update_visuals()

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	match plot_state:
		PlotState.WATERED:
			water_level -= water_drain_rate * delta
			if water_level <= 0:
				water_level = 0
				set_state(PlotState.PLANTED)
		PlotState.GROWING:
			water_level -= water_drain_rate * delta
			if water_level > 0:
				growth_progress += delta / grow_time
				if growth_progress >= 1.0:
					growth_progress = 1.0
					set_state(PlotState.READY)
			else:
				water_level = 0
				wilt_timer += delta
				if wilt_timer >= wilt_threshold:
					set_state(PlotState.WILTING)
		PlotState.WILTING:
			wilt_timer += delta
			if wilt_timer >= dead_threshold:
				set_state(PlotState.DEAD)

func set_state(new_state: int) -> void:
	plot_state = new_state
	_update_visuals()
	state_changed.emit(new_state)
	_sync_state.rpc(plot_state, planted_seed_id, growth_progress, water_level, owner_peer_id)

@rpc("authority", "call_local", "reliable")
func _sync_state(state: int, seed_id: String, growth: float, water: float, owner_id: int) -> void:
	plot_state = state
	planted_seed_id = seed_id
	growth_progress = growth
	water_level = water
	owner_peer_id = owner_id
	_update_visuals()

func try_clear(peer_id: int) -> bool:
	if plot_state != PlotState.WILD and plot_state != PlotState.DEAD:
		return false
	owner_peer_id = peer_id
	wilt_timer = 0
	if plot_state == PlotState.DEAD:
		planted_seed_id = ""
		growth_progress = 0
		set_state(PlotState.TILLED)
	else:
		set_state(PlotState.CLEARED)
	return true

func try_till(_peer_id: int) -> bool:
	if plot_state != PlotState.CLEARED:
		return false
	set_state(PlotState.TILLED)
	return true

func try_plant(peer_id: int, seed_id: String) -> bool:
	if plot_state != PlotState.TILLED:
		return false
	# Check season
	var ingredient = DataRegistry.get_ingredient(seed_id)
	if ingredient == null:
		return false
	var season_mgr = get_node_or_null("/root/Main/GameWorld/SeasonManager")
	if season_mgr and not season_mgr.is_crop_in_season(ingredient.season):
		return false
	planted_seed_id = seed_id
	growth_progress = 0.0
	water_level = 0.0
	owner_peer_id = peer_id
	grow_time = ingredient.grow_time
	set_state(PlotState.PLANTED)
	return true

func try_water(_peer_id: int) -> bool:
	if plot_state not in [PlotState.PLANTED, PlotState.GROWING, PlotState.WILTING]:
		return false
	water_level = 1.0
	wilt_timer = 0
	if plot_state == PlotState.PLANTED or plot_state == PlotState.WILTING:
		set_state(PlotState.GROWING)
	return true

func try_harvest(_peer_id: int) -> Dictionary:
	if plot_state != PlotState.READY:
		return {}
	var ingredient = DataRegistry.get_ingredient(planted_seed_id)
	if ingredient == null:
		return {}
	var amount = randi_range(ingredient.harvest_min, ingredient.harvest_max)
	var result = {planted_seed_id: amount}
	# Reset plot
	planted_seed_id = ""
	growth_progress = 0.0
	water_level = 0.0
	wilt_timer = 0
	set_state(PlotState.TILLED)
	return result

func rain_water() -> void:
	if plot_state in [PlotState.PLANTED, PlotState.GROWING, PlotState.WILTING]:
		try_water(0)

func _update_visuals() -> void:
	if not is_inside_tree():
		return
	# Update base mesh color
	match plot_state:
		PlotState.WILD:
			base_mesh.material_override = mat_wild
			plant_mesh.visible = false
			fruit_mesh.visible = false
		PlotState.CLEARED:
			base_mesh.material_override = mat_cleared
			plant_mesh.visible = false
			fruit_mesh.visible = false
		PlotState.TILLED:
			base_mesh.material_override = mat_tilled
			plant_mesh.visible = false
			fruit_mesh.visible = false
		PlotState.PLANTED:
			base_mesh.material_override = mat_tilled
			plant_mesh.visible = true
			plant_mesh.scale = Vector3(0.1, 0.1, 0.1)
			_set_plant_color(Color(0.5, 0.4, 0.3))
			fruit_mesh.visible = false
		PlotState.WATERED, PlotState.GROWING:
			base_mesh.material_override = mat_watered
			plant_mesh.visible = true
			var s = 0.1 + growth_progress * 0.9
			plant_mesh.scale = Vector3(0.3, s, 0.3)
			_set_plant_color(Color(0.2, 0.6, 0.2))
			fruit_mesh.visible = false
		PlotState.READY:
			base_mesh.material_override = mat_tilled
			plant_mesh.visible = true
			plant_mesh.scale = Vector3(0.3, 1.0, 0.3)
			_set_plant_color(Color(0.2, 0.7, 0.2))
			fruit_mesh.visible = true
			_set_fruit_color()
		PlotState.WILTING:
			base_mesh.material_override = mat_tilled
			plant_mesh.visible = true
			plant_mesh.rotation_degrees.z = 30
			_set_plant_color(Color(0.6, 0.5, 0.2))
			fruit_mesh.visible = false
		PlotState.DEAD:
			base_mesh.material_override = mat_dead
			plant_mesh.visible = true
			plant_mesh.scale = Vector3(0.3, 0.3, 0.3)
			plant_mesh.rotation_degrees.z = 45
			_set_plant_color(Color(0.3, 0.25, 0.2))
			fruit_mesh.visible = false

func _set_plant_color(color: Color) -> void:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	plant_mesh.material_override = mat

func _set_fruit_color() -> void:
	var ingredient = DataRegistry.get_ingredient(planted_seed_id)
	var mat = StandardMaterial3D.new()
	if ingredient:
		mat.albedo_color = ingredient.icon_color
	else:
		mat.albedo_color = Color.RED
	fruit_mesh.material_override = mat

func get_save_data() -> Dictionary:
	return {
		"state": plot_state,
		"seed_id": planted_seed_id,
		"growth": growth_progress,
		"water": water_level,
		"owner": owner_peer_id,
		"wilt_timer": wilt_timer
	}

func load_save_data(data: Dictionary) -> void:
	plot_state = data.get("state", PlotState.WILD)
	planted_seed_id = data.get("seed_id", "")
	growth_progress = data.get("growth", 0.0)
	water_level = data.get("water", 0.0)
	owner_peer_id = data.get("owner", 0)
	wilt_timer = data.get("wilt_timer", 0.0)
	# Restore grow_time from ingredient data if planted
	if planted_seed_id != "":
		var ingredient = DataRegistry.get_ingredient(planted_seed_id)
		if ingredient:
			grow_time = ingredient.grow_time
	_update_visuals()
