extends CharacterBody3D

const RUN_SPEED = 7.0
const SPRINT_SPEED = 10.0
const CROUCH_SPEED = 3.5
const WALK_SPEED = 3.5
const JUMP_VELOCITY = 4.5
const GRAVITY = 9.8

const DEFAULT_CAPSULE_HEIGHT = 1.8
const CROUCH_CAPSULE_HEIGHT = 1.0
const CROUCH_LERP_SPEED = 8.0

enum MoveState { IDLE, WALK, RUN, SPRINT, CROUCH_IDLE, CROUCH_WALK, AIRBORNE }

const TOOL_ACTION_DURATIONS = {
	&"hoe": 1.0, &"axe": 0.8, &"water": 0.5,
	&"harvest": 0.5, &"craft": 1.0, &"fish": 0.8,
	&"fish_idle": 30.0,
}

var character_model: Node3D = null # Built dynamically by CharacterAssembler
@onready var nameplate: Label3D = $Nameplate
@onready var busy_indicator: Label3D = $BusyIndicator
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var camera: Camera3D = $Camera3D

# PhantomCamera created dynamically for local player only (avoids server hang)
var pcam: Node3D = null  # PhantomCamera3D, typed as Node3D to avoid parse errors if addon missing
var _pcam_host: Node3D = null

# Input state (synced via InputSync)
var input_direction: Vector2 = Vector2.ZERO
var camera_yaw: float = 0.0
var camera_pitch: float = 0.0
var interact_pressed: bool = false
var input_sprint: bool = false
var input_crouch: bool = false
var input_jump: bool = false

# Mouse look
var mouse_sensitivity: float = 0.003
var mouse_captured: bool = false
var pitch_limit: float = deg_to_rad(70)

# Visual properties (synced via StateSync on spawn)
var player_color: Color = Color(0.2, 0.5, 0.9)
var player_name_display: String = "Player"
var appearance_data: Dictionary = {} # Synced via StateSync (spawn-only)
var mesh_rotation_y: float = 0.0
var is_busy: bool = false:
	set(value):
		is_busy = value
		if busy_indicator:
			busy_indicator.visible = value
		_update_busy_transparency()

# Movement state (synced via StateSync)
var movement_state: int = MoveState.IDLE
var anim_move_speed: float = 0.0
var anim_action: StringName = &""

var peer_id: int = 1

# Track whether AnimationTree blend graph has been built
var _anim_tree_ready: bool = false

# Client-local airborne animation tracking
var _was_airborne: bool = false
var _landing_timer: float = 0.0
const LANDING_ANIM_DURATION := 0.3

# Footstep audio
var _footstep_timer: float = 0.0
var _prev_anim_action: StringName = &""


func _update_busy_transparency() -> void:
	if character_model == null:
		return
	var local_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else -1
	if peer_id == local_id:
		return
	# Find MeshInstance3D children in the character model and apply transparency
	var meshes = _find_mesh_instances(character_model)
	for mi: MeshInstance3D in meshes:
		if mi.material_override == null:
			continue
		var mat = mi.material_override as StandardMaterial3D
		if mat == null:
			continue
		if is_busy:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = 0.35
		else:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			mat.albedo_color.a = 1.0


func _find_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_mesh_instances(child))
	return result


func _enter_tree() -> void:
	var local_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else -1
	peer_id = _resolve_peer_id(local_id)
	print("[PlayerController] _enter_tree() node=", name, " peer_id=", peer_id, " local_id=", local_id)
	# Synchronizer authority must be set before _ready to avoid spawn-time replication errors.
	var input_sync: MultiplayerSynchronizer = get_node_or_null("InputSync")
	var state_sync: MultiplayerSynchronizer = get_node_or_null("StateSync")
	if input_sync == null or state_sync == null:
		push_error("[PlayerController] Missing synchronizer nodes on player %s (InputSync/StateSync)" % name)
		return
	input_sync.set_multiplayer_authority(peer_id)
	# State replication remains server-authoritative.
	state_sync.set_multiplayer_authority(1)
	print("[PlayerController] _enter_tree() COMPLETE — InputSync auth=", peer_id, " StateSync auth=1")


func _ready() -> void:
	var local_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else -1
	peer_id = _resolve_peer_id(local_id)
	print("[PlayerController] _ready() START node=", name, " peer_id=", peer_id, " local_id=", local_id, " is_server=", multiplayer.is_server())

	if local_id > 0 and peer_id == local_id:
		print("[PlayerController]   LOCAL PLAYER — setting up camera + PhantomCamera")
		_setup_phantom_camera()
		_activate_local_camera()
		_capture_mouse()
	else:
		print("[PlayerController]   REMOTE PLAYER — disabling camera + input")
		camera.current = false
		set_process_input(false)

	# Assemble character model (clients only — server has no visuals)
	if not multiplayer.is_server():
		_assemble_character()

	# Disable AnimationTree on server (no visuals needed)
	if multiplayer.is_server():
		if anim_tree:
			anim_tree.active = false
	else:
		_build_animation_tree()

	_apply_visuals()
	print("[PlayerController] _ready() COMPLETE")


func _input(event: InputEvent) -> void:
	if peer_id != multiplayer.get_unique_id():
		return
	if event is InputEventMouseMotion and mouse_captured:
		camera_yaw -= event.relative.x * mouse_sensitivity
		camera_pitch -= event.relative.y * mouse_sensitivity
		camera_pitch = clamp(camera_pitch, -pitch_limit, pitch_limit)
		# Drive Phantom Camera rotation
		if pcam and pcam.has_method("set_third_person_rotation_degrees"):
			var rot_deg: Vector3 = pcam.get_third_person_rotation_degrees()
			rot_deg.x = rad_to_deg(camera_pitch)
			rot_deg.y = rad_to_deg(camera_yaw)
			pcam.set_third_person_rotation_degrees(rot_deg)
	if event.is_action_pressed("toggle_mouse"):
		if mouse_captured:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			mouse_captured = false
		else:
			_capture_mouse()


func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	mouse_captured = true


func _activate_local_camera() -> void:
	camera.current = true
	var fallback_cam = get_node_or_null("/root/Main/GameWorld/FallbackCameraRig/FallbackCamera")
	if fallback_cam:
		fallback_cam.current = false
	var fallback_rig = get_node_or_null("/root/Main/GameWorld/FallbackCameraRig")
	if fallback_rig and fallback_rig is Node3D:
		(fallback_rig as Node3D).visible = false


func _setup_phantom_camera() -> void:
	# Create PhantomCamera nodes dynamically — only for the local player.
	# PhantomCamera3D uses Engine.get_singleton("PhantomCameraManager") in _enter_tree(),
	# which crashes on headless/dedicated servers. So we never include them in the .tscn.
	print("[PlayerController] _setup_phantom_camera() START")
	print("[PlayerController]   Engine.has_singleton('PhantomCameraManager')=", Engine.has_singleton("PhantomCameraManager"))
	if not Engine.has_singleton("PhantomCameraManager"):
		push_warning("[PlayerController] PhantomCameraManager singleton not found, using manual camera")
		return

	var pcam_host_script = load("res://addons/phantom_camera/scripts/phantom_camera_host/phantom_camera_host.gd")
	var pcam_script = load("res://addons/phantom_camera/scripts/phantom_camera/phantom_camera_3d.gd")
	print("[PlayerController]   pcam_host_script=", pcam_host_script, " pcam_script=", pcam_script)
	if pcam_host_script == null or pcam_script == null:
		push_warning("[PlayerController] PhantomCamera addon scripts not found, using manual camera")
		return

	# PhantomCameraHost on the Camera3D
	print("[PlayerController]   Creating PhantomCameraHost on camera...")
	_pcam_host = Node3D.new()
	_pcam_host.name = "PhantomCameraHost"
	_pcam_host.set_script(pcam_host_script)
	camera.add_child(_pcam_host)
	print("[PlayerController]   PhantomCameraHost added to camera: ", _pcam_host)

	# PhantomCamera3D — set properties BEFORE add_child because _ready() reads
	# follow_mode and spring_length to create the SpringArm3D.
	print("[PlayerController]   Creating PhantomCamera3D node...")
	pcam = Node3D.new()
	pcam.name = "PhantomCamera3D"
	pcam.set_script(pcam_script)
	print("[PlayerController]   Setting pcam properties BEFORE add_child...")
	pcam.set("follow_mode", 6)          # THIRD_PERSON — must be before add_child
	pcam.set("spring_length", 4.2)      # Used in SpringArm3D creation
	pcam.set("collision_mask", 1)       # Terrain layer
	pcam.set("follow_offset", Vector3(0, 1.6, 0))  # Eye height
	print("[PlayerController]   Calling add_child(pcam)...")
	add_child(pcam)
	print("[PlayerController]   pcam added to tree, now setting follow_target...")
	# follow_target MUST be after add_child (setter connects tree_exiting signal)
	pcam.set("follow_target", self)
	print("[PlayerController]   follow_target set. pcam=", pcam, " has_method('set_third_person_rotation_degrees')=", pcam.has_method("set_third_person_rotation_degrees"))
	print("[PlayerController] _setup_phantom_camera() COMPLETE")



func _resolve_peer_id(local_id: int) -> int:
	var parsed = name.to_int()
	if parsed > 0:
		return parsed
	if local_id > 0:
		push_warning("Player node name is not numeric, falling back to local peer id: %s" % name)
		return local_id
	return 1


func _assemble_character() -> void:
	var has_parts := appearance_data.has("head_id") and str(appearance_data.get("head_id", "")) != ""
	if appearance_data.is_empty() or not has_parts:
		# No valid parts — show mannequin until character creator completes
		var fallback_scene: PackedScene = load("res://assets/models/mannequin_f.glb")
		if fallback_scene:
			character_model = fallback_scene.instantiate()
			character_model.name = "CharacterModel"
			add_child(character_model)
		else:
			push_error("[PlayerController] Cannot load fallback mannequin!")
			character_model = Node3D.new()
			character_model.name = "CharacterModel"
			add_child(character_model)
	else:
		character_model = CharacterAssembler.assemble(self, appearance_data)

	# Re-point AnimationTree root to the new model
	if anim_tree and character_model:
		anim_tree.root_node = anim_tree.get_path_to(character_model)


func _apply_visuals() -> void:
	# Apply player color tint only to fallback mannequin (no custom appearance).
	# Modular characters use the AR Kit atlas texture and don't need color tinting.
	var has_parts := appearance_data.has("head_id") and str(appearance_data.get("head_id", "")) != ""
	if character_model and not has_parts:
		var meshes = _find_mesh_instances(character_model)
		for mi: MeshInstance3D in meshes:
			if mi.get_surface_override_material_count() > 0:
				for surface_idx in mi.get_surface_override_material_count():
					var base_mat = mi.get_surface_override_material(surface_idx)
					if base_mat == null:
						base_mat = mi.mesh.surface_get_material(surface_idx) if mi.mesh else null
					if base_mat is StandardMaterial3D:
						var mat = base_mat.duplicate() as StandardMaterial3D
						mat.albedo_color = player_color
						mi.set_surface_override_material(surface_idx, mat)
			elif mi.material_override:
				var mat = mi.material_override.duplicate() as StandardMaterial3D
				if mat:
					mat.albedo_color = player_color
					mi.material_override = mat
	if nameplate:
		nameplate.text = player_name_display
		UITheme.style_label3d(nameplate, "", "npc_name")
	if busy_indicator:
		UITheme.style_label3d(busy_indicator, "", "interaction_hint")
		# Hide own nameplate and busy indicator
		var local_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else -1
		if peer_id == local_id:
			nameplate.visible = false
			if busy_indicator:
				busy_indicator.visible = false


func _process(delta: float) -> void:
	# Apply synced rotation to character model (ALL clients + server)
	if character_model:
		character_model.rotation.y = mesh_rotation_y

	# Drive animation from synced state (ALL clients except server)
	if _anim_tree_ready:
		_update_animation_tree()

	# Crouch collision lerp (ALL clients)
	_update_crouch_collision(delta)

	if peer_id != multiplayer.get_unique_id():
		return

	# Footstep audio (local player only)
	if movement_state in [MoveState.RUN, MoveState.SPRINT, MoveState.WALK, MoveState.CROUCH_WALK]:
		var step_interval := 0.45 if movement_state == MoveState.SPRINT else 0.55
		if movement_state == MoveState.CROUCH_WALK:
			step_interval = 0.7
		_footstep_timer -= delta
		if _footstep_timer <= 0.0:
			AudioManager.play_sfx_varied("footstep_grass")
			_footstep_timer = step_interval
	else:
		_footstep_timer = 0.0

	# Tool use SFX (fire once when action starts)
	if anim_action != &"" and anim_action != _prev_anim_action:
		match String(anim_action):
			"hoe": AudioManager.play_sfx("tool_hoe")
			"axe": AudioManager.play_sfx("tool_axe")
			"water": AudioManager.play_sfx("tool_water")
			"harvest": AudioManager.play_sfx("tool_harvest")
	_prev_anim_action = anim_action

	# Gather input (LOCAL player only)
	input_direction = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	interact_pressed = Input.is_action_just_pressed("interact")
	input_sprint = Input.is_action_pressed("sprint")
	input_crouch = Input.is_action_pressed("crouch")
	input_jump = Input.is_action_just_pressed("jump")


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	# Gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	# Busy lock
	if is_busy:
		velocity.x = move_toward(velocity.x, 0, RUN_SPEED * delta * 5)
		velocity.z = move_toward(velocity.z, 0, RUN_SPEED * delta * 5)
		movement_state = MoveState.IDLE
		anim_move_speed = 0.0
		move_and_slide()
		return

	# Tool action lock: freeze movement during tool animation
	if anim_action != &"":
		velocity.x = move_toward(velocity.x, 0, RUN_SPEED * delta * 5)
		velocity.z = move_toward(velocity.z, 0, RUN_SPEED * delta * 5)
		move_and_slide()
		return

	# Jump
	if input_jump and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Determine movement state + speed
	var gait_speed := RUN_SPEED
	var new_state := MoveState.IDLE
	var has_input := input_direction.length() > 0.1

	if not is_on_floor():
		new_state = MoveState.AIRBORNE
	elif input_crouch:
		if has_input:
			new_state = MoveState.CROUCH_WALK
			gait_speed = CROUCH_SPEED
		else:
			new_state = MoveState.CROUCH_IDLE
	elif has_input:
		if input_sprint:
			new_state = MoveState.SPRINT
			gait_speed = SPRINT_SPEED
		else:
			new_state = MoveState.RUN
			gait_speed = RUN_SPEED

	movement_state = new_state

	# Movement direction
	var forward = Vector3(sin(camera_yaw), 0, cos(camera_yaw))
	var right = Vector3(cos(camera_yaw), 0, -sin(camera_yaw))
	var move_dir = (forward * input_direction.y + right * input_direction.x).normalized()

	if has_input:
		var speed_mult = 1.0
		var speed_buff = NetworkManager.server_get_buff_value(peer_id, "speed_boost")
		if speed_buff > 0.0:
			speed_mult = speed_buff
		velocity.x = move_dir.x * gait_speed * speed_mult
		velocity.z = move_dir.z * gait_speed * speed_mult

		var target_angle = atan2(move_dir.x, move_dir.z)
		mesh_rotation_y = lerp_angle(mesh_rotation_y, target_angle, 15 * delta)

		anim_move_speed = clamp(Vector2(velocity.x, velocity.z).length() / SPRINT_SPEED, 0.0, 1.0)
	else:
		velocity.x = move_toward(velocity.x, 0, gait_speed * delta * 5)
		velocity.z = move_toward(velocity.z, 0, gait_speed * delta * 5)
		anim_move_speed = 0.0

	move_and_slide()


# ---------- Animation Tree ----------

func _build_animation_tree() -> void:
	if not anim_tree:
		return

	# Use AnimationTree as a standalone AnimationMixer — add the animation library
	# directly to it instead of routing through a separate AnimationPlayer.
	# In Godot 4.x, AnimationTree inherits AnimationMixer and can own animation
	# libraries. Using a separate AnimationPlayer with anim_player path doesn't
	# properly drive Skeleton3D bone poses through the blend tree.
	anim_tree.anim_player = NodePath("")
	var lib = load("res://assets/animations/player_animation_library.tres")
	if lib == null:
		push_error("[PlayerController] Failed to load animation library")
		return
	anim_tree.add_animation_library(&"", lib)
	anim_tree.root_node = NodePath("../CharacterModel")

	var blend_tree := AnimationNodeBlendTree.new()

	# Locomotion animation nodes
	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = &"Idle"
	blend_tree.add_node(&"Idle", idle_node, Vector2(0, 0))

	var jog_node := AnimationNodeAnimation.new()
	jog_node.animation = &"Jog_Fwd"
	blend_tree.add_node(&"Jog", jog_node, Vector2(0, 200))

	var run_node := AnimationNodeAnimation.new()
	run_node.animation = &"Sprint"
	blend_tree.add_node(&"Run", run_node, Vector2(0, 400))

	var crouch_idle_node := AnimationNodeAnimation.new()
	crouch_idle_node.animation = &"Crouch_Idle"
	blend_tree.add_node(&"CrouchIdle", crouch_idle_node, Vector2(0, 600))

	var crouch_walk_node := AnimationNodeAnimation.new()
	crouch_walk_node.animation = &"Crouch_Fwd"
	blend_tree.add_node(&"CrouchWalk", crouch_walk_node, Vector2(0, 800))

	var falling_node := AnimationNodeAnimation.new()
	falling_node.animation = &"Jump"
	blend_tree.add_node(&"Falling", falling_node, Vector2(0, 1000))

	var jump_up_node := AnimationNodeAnimation.new()
	jump_up_node.animation = &"Jump_Start"
	blend_tree.add_node(&"JumpUp", jump_up_node, Vector2(0, 1100))

	var landing_node := AnimationNodeAnimation.new()
	landing_node.animation = &"Jump_Land"
	blend_tree.add_node(&"Landing", landing_node, Vector2(0, 1200))

	# Tool action animation node
	var tool_node := AnimationNodeAnimation.new()
	tool_node.animation = &"Farm_PlantSeed"
	blend_tree.add_node(&"ToolAnim", tool_node, Vector2(0, 1400))

	# Standing locomotion transition: Idle / Jog / Run
	var stand_loco := AnimationNodeTransition.new()
	stand_loco.add_input("Idle")
	stand_loco.add_input("Jog")
	stand_loco.add_input("Run")
	stand_loco.xfade_time = 0.2
	blend_tree.add_node(&"StandingLoco", stand_loco, Vector2(300, 100))
	blend_tree.connect_node(&"StandingLoco", 0, &"Idle")
	blend_tree.connect_node(&"StandingLoco", 1, &"Jog")
	blend_tree.connect_node(&"StandingLoco", 2, &"Run")

	# Crouch locomotion transition: Idle / Walk
	var crouch_loco := AnimationNodeTransition.new()
	crouch_loco.add_input("Idle")
	crouch_loco.add_input("Walk")
	crouch_loco.xfade_time = 0.2
	blend_tree.add_node(&"CrouchLoco", crouch_loco, Vector2(300, 700))
	blend_tree.connect_node(&"CrouchLoco", 0, &"CrouchIdle")
	blend_tree.connect_node(&"CrouchLoco", 1, &"CrouchWalk")

	# Stance transition: Stand / Crouch
	var stance := AnimationNodeTransition.new()
	stance.add_input("stand")
	stance.add_input("crouch")
	stance.xfade_time = 0.3
	blend_tree.add_node(&"Stance", stance, Vector2(600, 400))
	blend_tree.connect_node(&"Stance", 0, &"StandingLoco")
	blend_tree.connect_node(&"Stance", 1, &"CrouchLoco")

	# Airborne state transition: JumpUp / Falling / Landing
	var airborne_state := AnimationNodeTransition.new()
	airborne_state.add_input("JumpUp")
	airborne_state.add_input("Falling")
	airborne_state.add_input("Landing")
	airborne_state.xfade_time = 0.15
	blend_tree.add_node(&"AirborneState", airborne_state, Vector2(600, 1000))
	blend_tree.connect_node(&"AirborneState", 0, &"JumpUp")
	blend_tree.connect_node(&"AirborneState", 1, &"Falling")
	blend_tree.connect_node(&"AirborneState", 2, &"Landing")

	# InAir blend: 0=locomotion, 1=airborne state
	var in_air := AnimationNodeBlend2.new()
	blend_tree.add_node(&"InAir", in_air, Vector2(900, 500))
	blend_tree.connect_node(&"InAir", 0, &"Stance")
	blend_tree.connect_node(&"InAir", 1, &"AirborneState")

	# ToolAction blend: 0=locomotion, 1=tool animation
	var tool_action := AnimationNodeBlend2.new()
	blend_tree.add_node(&"ToolAction", tool_action, Vector2(1200, 600))
	blend_tree.connect_node(&"ToolAction", 0, &"InAir")
	blend_tree.connect_node(&"ToolAction", 1, &"ToolAnim")

	# Connect to output
	blend_tree.connect_node(&"output", 0, &"ToolAction")

	# Fix loop modes for locomotion animations (safety net — build tool already sets these)
	var loop_anims := ["Idle", "Jog_Fwd", "Sprint", "Crouch_Idle", "Crouch_Fwd",
		"Jump", "Fish_Cast_Idle", "TreeChopping", "Mining", "Dance",
		"Swim_Fwd", "Swim_Idle", "Walk_Fwd", "Walk"]
	for anim_name in loop_anims:
		var anim := anim_tree.get_animation(anim_name)
		if anim:
			anim.loop_mode = Animation.LOOP_LINEAR

	anim_tree.tree_root = blend_tree
	anim_tree.active = true
	_anim_tree_ready = true


func _update_animation_tree() -> void:
	if not anim_tree or not anim_tree.active:
		return

	# Tool action overlay
	if anim_action != &"":
		anim_tree.set(&"parameters/ToolAction/blend_amount", 1.0)
		var tool_anim_name := _get_tool_animation_name(anim_action)
		anim_tree.set(&"parameters/ToolAnim/animation", tool_anim_name)
		return
	else:
		anim_tree.set(&"parameters/ToolAction/blend_amount", 0.0)

	# Airborne + landing
	var is_airborne := movement_state == MoveState.AIRBORNE
	if is_airborne:
		if velocity.y > 0.5:
			anim_tree.set(&"parameters/AirborneState/transition_request", "JumpUp")
		else:
			anim_tree.set(&"parameters/AirborneState/transition_request", "Falling")
		anim_tree.set(&"parameters/InAir/blend_amount", 1.0)
		_was_airborne = true
	elif _was_airborne:
		# Just landed — play landing animation
		_was_airborne = false
		_landing_timer = LANDING_ANIM_DURATION
		anim_tree.set(&"parameters/AirborneState/transition_request", "Landing")
		anim_tree.set(&"parameters/InAir/blend_amount", 1.0)
	elif _landing_timer > 0.0:
		_landing_timer -= get_process_delta_time()
		anim_tree.set(&"parameters/InAir/blend_amount", 1.0)
	else:
		anim_tree.set(&"parameters/InAir/blend_amount", 0.0)

	# Stance (use String, not StringName — transition_request expects String)
	var is_crouching := movement_state in [MoveState.CROUCH_IDLE, MoveState.CROUCH_WALK]
	anim_tree.set(&"parameters/Stance/transition_request", "crouch" if is_crouching else "stand")

	# Standing locomotion
	match movement_state:
		MoveState.IDLE:
			anim_tree.set(&"parameters/StandingLoco/transition_request", "Idle")
		MoveState.RUN:
			anim_tree.set(&"parameters/StandingLoco/transition_request", "Jog")
		MoveState.SPRINT:
			anim_tree.set(&"parameters/StandingLoco/transition_request", "Run")

	# Crouch locomotion
	match movement_state:
		MoveState.CROUCH_IDLE:
			anim_tree.set(&"parameters/CrouchLoco/transition_request", "Idle")
		MoveState.CROUCH_WALK:
			anim_tree.set(&"parameters/CrouchLoco/transition_request", "Walk")


func _get_tool_animation_name(action: StringName) -> StringName:
	match action:
		# Farming
		&"hoe":         return &"Farm_PlantSeed"
		&"axe":         return &"TreeChopping"
		&"water":       return &"Farm_Watering"
		&"harvest":     return &"Farm_Harvest"
		&"plant":       return &"Farm_ScatteringSeeds"
		&"pick_tree":   return &"Farm_PickingTree"
		&"mine":        return &"Mining"
		# Crafting & interaction
		&"craft":       return &"Interact"
		&"interact":    return &"Interact"
		&"pickup":      return &"PickUp_Kneeling"
		&"pickup_table": return &"PickUp_Table"
		&"consume":     return &"Consume"
		&"drink":       return &"Drink"
		# Fishing
		&"fish":        return &"Fish_Cast"
		&"fish_idle":   return &"Fish_Cast_Idle"
		&"fish_hook":   return &"Fish_Reel"
		&"fish_fail":   return &"Fish_Reel_Failed"
		# Combat
		&"punch":       return &"Punch_Jab"
		&"kick":        return &"Kick"
		&"sword":       return &"Sword_Attack"
		&"spell":       return &"Spell_Simple_Shoot"
		&"hit":         return &"Hit_Chest"
		&"knockback":   return &"Hit_Knockback"
		&"death":       return &"Death01"
		&"roll":        return &"Roll"
		&"dodge_left":  return &"Dodge_Left"
		&"dodge_right": return &"Dodge_Right"
		# Emotes & social
		&"wave":        return &"Yes"
		&"celebrate":   return &"Celebration"
		&"dance":       return &"Dance"
		&"cry":         return &"Crying"
		&"surprise":    return &"Surprise"
		&"backflip":    return &"BackFlip"
		&"sit":         return &"Sitting_Enter"
		&"push":        return &"Push"
		&"throw":       return &"OverhandThrow"
		# Movement transitions
		&"climb":       return &"Climb_Up"
		&"climb_enter": return &"Climb_Enter"
		&"climb_exit":  return &"Climb_Exit"
		&"slide":       return &"Slide"
		&"swim":        return &"Swim_Fwd"
		&"jump_double": return &"DoubleJump"
		# Counter/shop
		&"counter_give":  return &"Counter_Give"
		&"counter_show":  return &"Counter_Show"
		# Default
		_:              return &"Farm_Harvest"


# ---------- Crouch Collision ----------

func _update_crouch_collision(delta: float) -> void:
	if not collision_shape or not collision_shape.shape is CapsuleShape3D:
		return
	var capsule := collision_shape.shape as CapsuleShape3D
	var is_crouching := movement_state in [MoveState.CROUCH_IDLE, MoveState.CROUCH_WALK]
	var target_height := CROUCH_CAPSULE_HEIGHT if is_crouching else DEFAULT_CAPSULE_HEIGHT
	capsule.height = lerp(capsule.height, target_height, delta * CROUCH_LERP_SPEED)
	collision_shape.position.y = lerp(collision_shape.position.y, capsule.height / 2.0, delta * CROUCH_LERP_SPEED)
	capsule.radius = clamp(capsule.height / 3.6, 0.28, 0.5)


# ---------- Tool Action (called by server managers) ----------

func play_tool_action(action: StringName) -> void:
	anim_action = action
	var duration: float = TOOL_ACTION_DURATIONS.get(action, 0.5)
	get_tree().create_timer(duration).timeout.connect(_clear_tool_action)


func _clear_tool_action() -> void:
	anim_action = &""


func set_persistent_anim(action: StringName) -> void:
	anim_action = action


func clear_persistent_anim() -> void:
	anim_action = &""


func reactivate_camera() -> void:
	if camera:
		camera.current = true


## Rebuild character model from updated appearance data (called after appearance change RPC).
func update_appearance(new_appearance: Dictionary) -> void:
	appearance_data = new_appearance
	if multiplayer.is_server():
		return
	# Deactivate AnimationTree while rebuilding
	if anim_tree:
		anim_tree.active = false
		_anim_tree_ready = false
	# Reassemble
	_assemble_character()
	_build_animation_tree()
	_apply_visuals()
