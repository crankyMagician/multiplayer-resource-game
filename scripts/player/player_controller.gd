extends CharacterBody3D

const SPEED = 7.0
const JUMP_VELOCITY = 4.5
const GRAVITY = 9.8

@onready var mesh: MeshInstance3D = $PlayerMesh
@onready var nameplate: Label3D = $Nameplate
@onready var busy_indicator: Label3D = $BusyIndicator
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D

# Input state (synced via InputSync)
var input_direction: Vector2 = Vector2.ZERO
var camera_yaw: float = 0.0
var camera_pitch: float = 0.0
var interact_pressed: bool = false
var tool_action_pressed: bool = false

# Mouse look
var mouse_sensitivity: float = 0.003
var mouse_captured: bool = false
var pitch_limit: float = deg_to_rad(70)

# Visual properties (synced via StateSync on spawn)
var player_color: Color = Color(0.2, 0.5, 0.9)
var player_name_display: String = "Player"
var mesh_rotation_y: float = 0.0
var is_busy: bool = false:
	set(value):
		is_busy = value
		if busy_indicator:
			busy_indicator.visible = value

var peer_id: int = 1

func _enter_tree() -> void:
	var local_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else -1
	peer_id = _resolve_peer_id(local_id)
	# Synchronizer authority must be set before _ready to avoid spawn-time replication errors.
	var input_sync: MultiplayerSynchronizer = get_node_or_null("InputSync")
	var state_sync: MultiplayerSynchronizer = get_node_or_null("StateSync")
	if input_sync == null or state_sync == null:
		push_error("Missing synchronizer nodes on player %s (InputSync/StateSync)" % name)
		return
	input_sync.set_multiplayer_authority(peer_id)
	# State replication remains server-authoritative.
	state_sync.set_multiplayer_authority(1)

func _ready() -> void:
	var local_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else -1
	peer_id = _resolve_peer_id(local_id)
	print("[PlayerController] node=", name, " peer_id=", peer_id, " local_id=", local_id)

	if local_id > 0 and peer_id == local_id:
		# This is our player
		_activate_local_camera()
		_capture_mouse()
	else:
		# Not our player - disable camera
		camera.current = false
		# Disable processing input for non-local players
		set_process_input(false)

	_apply_visuals()

func _input(event: InputEvent) -> void:
	if peer_id != multiplayer.get_unique_id():
		return
	if event is InputEventMouseMotion and mouse_captured:
		camera_yaw -= event.relative.x * mouse_sensitivity
		camera_pitch -= event.relative.y * mouse_sensitivity
		camera_pitch = clamp(camera_pitch, -pitch_limit, pitch_limit)
		camera_pivot.rotation.y = camera_yaw
		camera_pivot.rotation.x = camera_pitch
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

func _resolve_peer_id(local_id: int) -> int:
	var parsed = name.to_int()
	if parsed > 0:
		return parsed
	if local_id > 0:
		push_warning("Player node name is not numeric, falling back to local peer id: %s" % name)
		return local_id
	return 1

func _apply_visuals() -> void:
	# Duplicate material so each player has unique color
	if mesh and mesh.material_override:
		var mat = mesh.material_override.duplicate() as StandardMaterial3D
		mat.albedo_color = player_color
		mesh.material_override = mat
	if nameplate:
		nameplate.text = player_name_display
		# Hide own nameplate and busy indicator
		var local_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else -1
		if peer_id == local_id:
			nameplate.visible = false
			if busy_indicator:
				busy_indicator.visible = false

func _process(_delta: float) -> void:
	# Apply synced rotation to mesh (all clients + server)
	if mesh:
		mesh.rotation.y = mesh_rotation_y
	if peer_id != multiplayer.get_unique_id():
		return
	# Gather input
	input_direction = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	interact_pressed = Input.is_action_just_pressed("interact")
	tool_action_pressed = Input.is_action_just_pressed("cycle_tool")

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	# Server processes physics for all players
	# Apply gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	# Busy lock: decay horizontal velocity, skip input
	if is_busy:
		velocity.x = move_toward(velocity.x, 0, SPEED * delta * 5)
		velocity.z = move_toward(velocity.z, 0, SPEED * delta * 5)
		move_and_slide()
		return

	# Calculate movement direction based on camera yaw
	var forward = Vector3(sin(camera_yaw), 0, cos(camera_yaw))
	var right = Vector3(cos(camera_yaw), 0, -sin(camera_yaw))
	var move_dir = (forward * input_direction.y + right * input_direction.x).normalized()

	if move_dir.length() > 0.1:
		var speed_mult = 1.0
		var speed_buff = NetworkManager.server_get_buff_value(peer_id, "speed_boost")
		if speed_buff > 0.0:
			speed_mult = speed_buff
		velocity.x = move_dir.x * SPEED * speed_mult
		velocity.z = move_dir.z * SPEED * speed_mult
		# Rotate mesh to face movement direction (synced via StateSync)
		var target_angle = atan2(move_dir.x, move_dir.z)
		mesh_rotation_y = lerp_angle(mesh_rotation_y, target_angle, 10 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED * delta * 5)
		velocity.z = move_toward(velocity.z, 0, SPEED * delta * 5)

	move_and_slide()
