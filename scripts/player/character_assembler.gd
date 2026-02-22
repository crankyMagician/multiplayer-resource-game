class_name CharacterAssembler
extends RefCounted

## Assembles a character by loading the UAL mannequin and applying two-color tinting.

const MANNEQUIN_PATH := "res://assets/models/mannequin_f.glb"


## Assemble a character model with primary + accent color tinting.
## Returns the assembled Node3D named "CharacterModel".
static func assemble(parent: Node3D, appearance: Dictionary, old_model: Node3D = null) -> Node3D:
	# Free existing model
	if old_model and is_instance_valid(old_model):
		old_model.queue_free()

	var scene: PackedScene = load(MANNEQUIN_PATH)
	if scene == null:
		push_error("[CharacterAssembler] Cannot load mannequin at %s" % MANNEQUIN_PATH)
		var empty := Node3D.new()
		empty.name = "CharacterModel"
		parent.add_child(empty)
		return empty

	var model: Node3D = scene.instantiate()
	model.name = "CharacterModel"
	parent.add_child(model)

	# Apply colors
	apply_colors(model, appearance)
	return model


## Reassemble a character in-place (for appearance changes).
static func reassemble(parent: Node3D, appearance: Dictionary) -> Node3D:
	var old_model := parent.get_node_or_null("CharacterModel")
	return assemble(parent, appearance, old_model)


## Apply primary and accent colors to a mannequin model's mesh surfaces.
## Primary color goes to the first surface of each mesh, accent to subsequent surfaces.
static func apply_colors(model: Node3D, appearance: Dictionary) -> void:
	var primary := _extract_color(appearance, "primary_color", Color(0.2, 0.5, 0.9))
	var accent := _extract_color(appearance, "accent_color", Color(0.9, 0.9, 0.9))

	var meshes := _find_mesh_instances(model)
	for mi: MeshInstance3D in meshes:
		var surface_count := mi.get_surface_override_material_count()
		if surface_count > 0:
			for surface_idx in surface_count:
				var base_mat = mi.get_surface_override_material(surface_idx)
				if base_mat == null and mi.mesh:
					base_mat = mi.mesh.surface_get_material(surface_idx)
				var mat := StandardMaterial3D.new()
				if base_mat is StandardMaterial3D:
					mat = base_mat.duplicate()
				mat.albedo_color = primary if surface_idx == 0 else accent
				mi.set_surface_override_material(surface_idx, mat)
		elif mi.material_override:
			var mat = mi.material_override.duplicate() as StandardMaterial3D
			if mat:
				mat.albedo_color = primary
				mi.material_override = mat


static func _extract_color(appearance: Dictionary, key: String, fallback: Color) -> Color:
	var val = appearance.get(key, {})
	if val is Dictionary and not val.is_empty():
		return Color(float(val.get("r", fallback.r)), float(val.get("g", fallback.g)), float(val.get("b", fallback.b)))
	if val is Color:
		return val
	return fallback


static func _find_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_mesh_instances(child))
	return result
