class_name NpcAnimator

# Shared NPC character model + animation utility.
# Creates mannequin models with AnimationTree for NPCs (client-side only).
# Server skips all visuals — only needs Area3D + CollisionShape3D.

const MANNEQUIN_PATH = "res://assets/models/mannequin_f.glb"
const ANIM_LIB_PATH = "res://assets/animations/player_animation_library.tres"

const FACE_PLAYER_SPEED := 2.0 # rad/s
const FACE_PLAYER_RANGE := 5.0 # meters
const MOVE_SPEED := 2.0 # units/sec for schedule movement
const SNAP_DISTANCE := 0.1

# --- Per-NPC animation mappings ---

const SOCIAL_NPC_ANIMS := {
	"npc_hubert": { "idle": "Idle", "actions": ["Interact", "Farm_Harvest"] },
	"npc_murphy": { "idle": "Idle", "actions": ["Farm_ScatteringSeeds", "Farm_PlantSeed"] },
	"npc_captain_sal": { "idle": "Fish_Cast_Idle", "actions": ["Fish_Cast", "Fish_Reel"] },
	"npc_pepper": { "idle": "Idle", "actions": ["Mining", "TreeChopping"] },
	"npc_quill": { "idle": "Sitting_Idle", "actions": ["Sitting_Talking"] },
	"npc_mayor": { "idle": "Idle", "actions": ["Yes", "Interact"] },
	"npc_innkeeper": { "idle": "Idle", "actions": ["Counter_Give", "Counter_Show"] },
	"npc_potter": { "idle": "Idle", "actions": ["Interact", "Mining"] },
	"npc_tailor": { "idle": "Idle", "actions": ["Interact", "Farm_ScatteringSeeds"] },
	"npc_gardener": { "idle": "Idle", "actions": ["Farm_PlantSeed", "Farm_Watering"] },
	"npc_doctor": { "idle": "Idle", "actions": ["Interact", "Yes"] },
	"npc_general_store": { "idle": "Idle", "actions": ["Counter_Give", "Counter_Show"] },
	"npc_clementine": { "idle": "Idle", "actions": ["Interact", "Farm_Harvest"] },
	"npc_river": { "idle": "Fish_Cast_Idle", "actions": ["Fish_Cast", "Dance"] },
	"npc_alex": { "idle": "Idle", "actions": ["Yes", "Dance"] },
}

const TRAINER_ANIMS := {
	"easy": { "idle": "Idle", "actions": ["Sword_Idle", "Yes"] },
	"medium": { "idle": "Sword_Idle", "actions": ["Sword_Attack", "Sword_Block"] },
	"hard": { "idle": "Sword_Block", "actions": ["Spell_Simple_Shoot", "Sword_Attack"] },
}

const SHOP_ANIMS := { "idle": "Idle", "actions": ["Counter_Give", "Counter_Show", "Yes"] }
const BANK_ANIMS := { "idle": "Idle", "actions": ["Counter_Give", "Interact"] }

const DEFAULT_ANIMS := { "idle": "Idle", "actions": ["Yes", "Interact"] }

# Animations that must loop (subset relevant to NPCs)
const LOOP_ANIMS := [
	"Idle", "Idle_LookAround", "Idle_Tired", "Idle_Talking", "Idle_FoldArms",
	"Walk_Fwd", "Jog_Fwd", "Sitting_Idle", "Sitting_Talking",
	"Sword_Idle", "Sword_Block", "Spell_Simple_Idle",
	"Counter_Idle", "Fish_Cast_Idle", "TreeChopping", "Mining", "Dance",
]

# --- Factory ---

## Create a character with a custom appearance (AR Kit modular parts).
## Falls back to mannequin if appearance is empty or assembly fails.
static func create_character_from_appearance(parent: Node3D, config: Dictionary, appearance: Dictionary) -> Dictionary:
	var model: Node3D
	if appearance.is_empty():
		return create_character(parent, config)

	model = CharacterAssembler.assemble(parent, appearance)
	if model == null:
		return create_character(parent, config)

	var face_dir: float = config.get("face_direction", 0.0)
	model.rotation.y = face_dir

	return _setup_anim_tree(parent, model, config)


static func create_character(parent: Node3D, config: Dictionary) -> Dictionary:
	var idle_anim: String = config.get("idle", "Idle")
	var action_anims: Array = config.get("actions", ["Yes"])
	var color_tint: Color = config.get("color", Color.WHITE)
	var face_dir: float = config.get("face_direction", 0.0)

	# Load and instance mannequin
	var glb = load(MANNEQUIN_PATH)
	if glb == null:
		push_error("[NpcAnimator] Failed to load mannequin GLB")
		return {}
	var model: Node3D = glb.instantiate()
	model.name = "CharacterModel"
	parent.add_child(model)

	# Apply color tint to all mesh surfaces
	_apply_color_tint(model, color_tint)

	# Set initial rotation
	model.rotation.y = face_dir

	return _setup_anim_tree(parent, model, config)


## Shared AnimationTree setup for both mannequin and modular characters.
static func _setup_anim_tree(parent: Node3D, model: Node3D, config: Dictionary) -> Dictionary:
	var idle_anim: String = config.get("idle", "Idle")
	var action_anims: Array = config.get("actions", ["Yes"])

	# Create AnimationTree as standalone AnimationMixer
	var anim_tree := AnimationTree.new()
	anim_tree.name = "NpcAnimTree"
	anim_tree.anim_player = NodePath("")
	var lib = load(ANIM_LIB_PATH)
	if lib == null:
		push_error("[NpcAnimator] Failed to load animation library")
		return {}
	anim_tree.add_animation_library(&"", lib)
	# Must add to tree before get_path_to() works
	parent.add_child(anim_tree)
	if model.is_inside_tree() and anim_tree.is_inside_tree():
		anim_tree.root_node = anim_tree.get_path_to(model)
	else:
		anim_tree.root_node = NodePath("../CharacterModel")

	# Build blend tree: IdleAnim -> ActionBlend (Blend2) -> WalkBlend (Blend2) -> output
	var blend_tree := AnimationNodeBlendTree.new()

	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = StringName(idle_anim)
	blend_tree.add_node(&"IdleAnim", idle_node, Vector2(0, 0))

	var action_node := AnimationNodeAnimation.new()
	action_node.animation = StringName(action_anims[0] if action_anims.size() > 0 else "Yes")
	blend_tree.add_node(&"ActionAnim", action_node, Vector2(0, 200))

	var walk_node := AnimationNodeAnimation.new()
	walk_node.animation = &"Walk_Fwd"
	blend_tree.add_node(&"WalkAnim", walk_node, Vector2(0, 400))

	# ActionBlend: 0=idle, 1=action
	var action_blend := AnimationNodeBlend2.new()
	blend_tree.add_node(&"ActionBlend", action_blend, Vector2(300, 100))
	blend_tree.connect_node(&"ActionBlend", 0, &"IdleAnim")
	blend_tree.connect_node(&"ActionBlend", 1, &"ActionAnim")

	# WalkBlend: 0=action_blend, 1=walk
	var walk_blend := AnimationNodeBlend2.new()
	blend_tree.add_node(&"WalkBlend", walk_blend, Vector2(600, 200))
	blend_tree.connect_node(&"WalkBlend", 0, &"ActionBlend")
	blend_tree.connect_node(&"WalkBlend", 1, &"WalkAnim")

	blend_tree.connect_node(&"output", 0, &"WalkBlend")

	# Fix loop modes
	for anim_name in LOOP_ANIMS:
		var anim = anim_tree.get_animation(anim_name)
		if anim:
			anim.loop_mode = Animation.LOOP_LINEAR

	anim_tree.tree_root = blend_tree
	anim_tree.active = true

	var state := {
		"model": model,
		"anim_tree": anim_tree,
		"idle_anim": idle_anim,
		"action_anims": action_anims,
		"action_timer": randf_range(5.0, 15.0),
		"action_interval": randf_range(8.0, 15.0),
		"action_blend": 0.0,
		"action_playing": false,
		"action_duration": 0.0,
		"action_elapsed": 0.0,
		"walk_blend": 0.0,
		"is_walking": false,
		"reaction_playing": false,
	}
	return state

# --- Update (call every frame on client) ---

static func update(state: Dictionary, delta: float, npc_node: Node3D) -> void:
	if state.is_empty():
		return
	var anim_tree: AnimationTree = state.get("anim_tree")
	if anim_tree == null or not anim_tree.active:
		return

	var model: Node3D = state.get("model")
	var is_walking: bool = state.get("is_walking", false)

	# Walk blend
	var walk_target := 1.0 if is_walking else 0.0
	var walk_blend: float = state.get("walk_blend", 0.0)
	walk_blend = move_toward(walk_blend, walk_target, delta * 4.0)
	state["walk_blend"] = walk_blend
	anim_tree.set("parameters/WalkBlend/blend_amount", walk_blend)

	# Action animation timer (skip while walking or reaction playing)
	if not is_walking and not state.get("reaction_playing", false):
		if state.get("action_playing", false):
			state["action_elapsed"] = state.get("action_elapsed", 0.0) + delta
			var blend: float = state.get("action_blend", 0.0)
			blend = move_toward(blend, 1.0, delta * 5.0)
			state["action_blend"] = blend
			anim_tree.set("parameters/ActionBlend/blend_amount", blend)
			if state["action_elapsed"] >= state.get("action_duration", 1.5):
				state["action_playing"] = false
				state["action_elapsed"] = 0.0
				state["action_timer"] = randf_range(8.0, 15.0)
		else:
			# Blend back to idle
			var blend: float = state.get("action_blend", 0.0)
			blend = move_toward(blend, 0.0, delta * 3.0)
			state["action_blend"] = blend
			anim_tree.set("parameters/ActionBlend/blend_amount", blend)
			# Countdown to next action
			state["action_timer"] = state.get("action_timer", 10.0) - delta
			if state["action_timer"] <= 0.0:
				_trigger_random_action(state, anim_tree)
	elif state.get("reaction_playing", false):
		state["action_elapsed"] = state.get("action_elapsed", 0.0) + delta
		var blend: float = state.get("action_blend", 0.0)
		blend = move_toward(blend, 1.0, delta * 5.0)
		state["action_blend"] = blend
		anim_tree.set("parameters/ActionBlend/blend_amount", blend)
		if state["action_elapsed"] >= state.get("action_duration", 1.5):
			state["reaction_playing"] = false
			state["action_playing"] = false
			state["action_elapsed"] = 0.0
			state["action_timer"] = randf_range(8.0, 15.0)
			# Blend back
			state["action_blend"] = 0.0
			anim_tree.set("parameters/ActionBlend/blend_amount", 0.0)

	# Face toward nearest local player
	if model and npc_node:
		_face_toward_player(model, npc_node, delta)

# --- Reaction animation (triggered by interaction) ---

static func play_reaction(state: Dictionary, anim_name: String) -> void:
	if state.is_empty():
		return
	var anim_tree: AnimationTree = state.get("anim_tree")
	if anim_tree == null:
		return

	# Set action animation to reaction anim
	var action_node_path = "parameters/ActionAnim/animation"
	anim_tree.set(action_node_path, StringName(anim_name))

	# Get duration
	var anim = anim_tree.get_animation(anim_name)
	var duration := 1.5
	if anim:
		duration = anim.length

	state["reaction_playing"] = true
	state["action_playing"] = true
	state["action_elapsed"] = 0.0
	state["action_duration"] = duration
	state["action_blend"] = 0.0

# --- Schedule movement (client-side lerp) ---

static func update_movement(state: Dictionary, npc_node: Node3D, delta: float) -> void:
	if state.is_empty() or npc_node == null:
		return
	if not npc_node.has_meta("schedule_target"):
		return
	var target: Vector3 = npc_node.get_meta("schedule_target")
	var current := npc_node.global_position
	var dist := current.distance_to(target)
	if dist < SNAP_DISTANCE:
		npc_node.global_position = target
		state["is_walking"] = false
		return

	state["is_walking"] = true
	var direction := (target - current).normalized()
	npc_node.global_position = current + direction * minf(MOVE_SPEED * delta, dist)

	# Rotate model toward movement direction
	var model: Node3D = state.get("model")
	if model and direction.length_squared() > 0.01:
		var target_angle := atan2(direction.x, direction.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_angle, delta * FACE_PLAYER_SPEED * 2.0)

# --- Private helpers ---

static func _trigger_random_action(state: Dictionary, anim_tree: AnimationTree) -> void:
	var actions: Array = state.get("action_anims", [])
	if actions.is_empty():
		return
	var chosen: String = actions[randi() % actions.size()]
	var action_node_path = "parameters/ActionAnim/animation"
	anim_tree.set(action_node_path, StringName(chosen))

	var anim = anim_tree.get_animation(chosen)
	var duration := 1.5
	if anim:
		duration = anim.length

	state["action_playing"] = true
	state["action_elapsed"] = 0.0
	state["action_duration"] = duration
	state["action_blend"] = 0.0

static func _apply_color_tint(model: Node3D, color: Color) -> void:
	for child in model.get_children():
		if child is Node3D:
			_apply_color_tint(child, color)
		if child is MeshInstance3D:
			var mesh_inst: MeshInstance3D = child
			for i in mesh_inst.get_surface_override_material_count():
				var base_mat = mesh_inst.mesh.surface_get_material(i) if mesh_inst.mesh else null
				var mat := StandardMaterial3D.new()
				if base_mat and base_mat is StandardMaterial3D:
					mat = base_mat.duplicate()
				mat.albedo_color = color
				mesh_inst.set_surface_override_material(i, mat)

static func _face_toward_player(model: Node3D, npc_node: Node3D, delta: float) -> void:
	# Find nearest local player
	var players_node = npc_node.get_node_or_null("/root/Main/GameWorld/Players")
	if players_node == null:
		return
	var npc_pos := npc_node.global_position
	var closest_dist := FACE_PLAYER_RANGE + 1.0
	var closest_pos := Vector3.ZERO
	var found := false
	for player in players_node.get_children():
		if player is CharacterBody3D:
			var d := npc_pos.distance_to(player.global_position)
			if d < closest_dist and d < FACE_PLAYER_RANGE:
				closest_dist = d
				closest_pos = player.global_position
				found = true
	if not found:
		return
	var dir := closest_pos - npc_pos
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		return
	var target_angle := atan2(dir.x, dir.z)
	model.rotation.y = lerp_angle(model.rotation.y, target_angle, delta * FACE_PLAYER_SPEED)

static func resolve_schedule_position(npc_def: Resource, time_fraction: float, season: String) -> Vector3:
	for entry in npc_def.schedule:
		var t_start: float = float(entry.get("time_start", 0.0))
		var t_end: float = float(entry.get("time_end", 1.0))
		var seasons: Array = entry.get("seasons", [])
		if time_fraction >= t_start and time_fraction < t_end:
			if seasons.is_empty() or season in seasons:
				var pos_dict: Dictionary = entry.get("position", {})
				return Vector3(
					float(pos_dict.get("x", 0)),
					float(pos_dict.get("y", 1)),
					float(pos_dict.get("z", 0))
				)
	return Vector3.ZERO

static func move_toward(current: float, target: float, max_delta: float) -> float:
	if absf(target - current) <= max_delta:
		return target
	return current + signf(target - current) * max_delta
