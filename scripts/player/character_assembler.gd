class_name CharacterAssembler
extends RefCounted

## Assembles a modular character from AR Kit parts on a shared skeleton.
## The base model (modular_male/female.glb) already contains ALL part meshes
## pre-skinned to the skeleton. Assembly works by showing selected parts and
## hiding everything else — no separate GLB loading needed.

const MANNEQUIN_FALLBACK := "res://assets/models/mannequin_f.glb"

# Categories and their appearance dict keys
const PART_CATEGORIES := {
	"head": "head_id",
	"hair": "hair_id",
	"torso": "torso_id",
	"pants": "pants_id",
	"shoes": "shoes_id",
	"arms": "arms_id",
	"hats": "hat_id",
	"glasses": "glasses_id",
	"beard": "beard_id",
}

# Shared atlas material (loaded once, reused)
static var _atlas_material: Material = null


## Assemble a character model from an appearance dictionary.
## Returns the assembled Node3D named "CharacterModel".
## If assembly fails, returns a fallback mannequin.
static func assemble(parent: Node3D, appearance: Dictionary, old_model: Node3D = null) -> Node3D:
	# Free existing model
	if old_model and is_instance_valid(old_model):
		old_model.queue_free()

	var gender: String = appearance.get("gender", "female")
	var base_path := CharacterPartRegistry.get_base_model_path(gender)

	# Try loading base model
	var base_scene: PackedScene = load(base_path)
	if base_scene == null:
		push_warning("[CharacterAssembler] Base model not found at %s, trying fallback" % base_path)
		return _create_fallback(parent, appearance)

	var model: Node3D = base_scene.instantiate()
	model.name = "CharacterModel"

	# Find the Skeleton3D in the base model
	var skeleton := _find_skeleton(model)
	if skeleton == null:
		push_warning("[CharacterAssembler] No Skeleton3D in base model, using fallback")
		model.queue_free()
		return _create_fallback(parent, appearance)

	# Collect the set of part IDs to show (case-insensitive lookup)
	var show_ids: Dictionary = {}  # lowercase part_id -> true
	for category in PART_CATEGORIES:
		var key: String = PART_CATEGORIES[category]
		var part_id: String = appearance.get(key, "")
		if part_id != "":
			show_ids[part_id.to_lower()] = true

	# Show selected parts, hide everything else.
	# Base model meshes are already skinned to the skeleton — no GLB loading needed.
	var atlas_mat := _get_atlas_material()
	_apply_part_visibility(skeleton, show_ids, atlas_mat)

	parent.add_child(model)
	return model


## Reassemble a character in-place (for appearance changes).
## Removes old model, builds new one, returns it.
static func reassemble(parent: Node3D, appearance: Dictionary) -> Node3D:
	var old_model := parent.get_node_or_null("CharacterModel")
	return assemble(parent, appearance, old_model)


## Create a fallback mannequin (original UAL model with color tint).
static func _create_fallback(parent: Node3D, appearance: Dictionary) -> Node3D:
	var scene: PackedScene = load(MANNEQUIN_FALLBACK)
	if scene == null:
		push_error("[CharacterAssembler] Cannot load fallback mannequin!")
		# Last resort: empty Node3D
		var empty := Node3D.new()
		empty.name = "CharacterModel"
		parent.add_child(empty)
		return empty

	var model: Node3D = scene.instantiate()
	model.name = "CharacterModel"
	parent.add_child(model)
	return model


## Show/hide mesh children of the skeleton based on selected part IDs.
## Each MeshInstance3D in the base model is named after its part ID (e.g. "HEAD_01_1").
## We match case-insensitively since a few parts have inconsistent casing.
static func _apply_part_visibility(skeleton: Skeleton3D, show_ids: Dictionary, atlas_mat: Material) -> void:
	for child_idx in skeleton.get_child_count():
		var child: Node = skeleton.get_child(child_idx)
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if show_ids.has(mi.name.to_lower()):
				mi.visible = true
				if atlas_mat:
					mi.material_override = atlas_mat
			else:
				mi.visible = false


## Get or create the shared atlas material.
static func _get_atlas_material() -> Material:
	if _atlas_material:
		return _atlas_material

	var atlas_path := CharacterPartRegistry.get_texture_atlas_path()
	var atlas_tex: Texture2D = load(atlas_path)
	if atlas_tex == null:
		return null

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = atlas_tex
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	_atlas_material = mat
	return _atlas_material



## Find Skeleton3D in node tree.
static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result := _find_skeleton(child)
		if result:
			return result
	return null


