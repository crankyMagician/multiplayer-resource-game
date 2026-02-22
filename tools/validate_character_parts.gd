@tool
extends SceneTree

## Validates that converted Synty character parts have UAL-compatible bone names.
## Run: '/Applications/Mechanical Turk.app/Contents/MacOS/Mechanical Turk' --path . --script tools/validate_synty_parts.gd

const CHARACTERS_DIR := "res://assets/characters/"

# Expected UAL bone names (from mannequin_f.glb)
const UAL_BONES: Array[String] = [
	"root", "pelvis", "spine_01", "spine_02", "spine_03",
	"neck_01", "Head", "Head_leaf",
	"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
	"clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
	"thigh_l", "calf_l", "foot_l", "ball_l", "ball_leaf_l",
	"thigh_r", "calf_r", "foot_r", "ball_r", "ball_leaf_r",
	"thumb_01_l", "thumb_02_l", "thumb_03_l", "thumb_03_leaf_l",
	"thumb_01_r", "thumb_02_r", "thumb_03_r", "thumb_03_leaf_r",
	"index_01_l", "index_02_l", "index_03_l", "index_03_leaf_l",
	"index_01_r", "index_02_r", "index_03_r", "index_03_leaf_r",
	"middle_01_l", "middle_02_l", "middle_03_l", "middle_03_leaf_l",
	"middle_01_r", "middle_02_r", "middle_03_r", "middle_03_leaf_r",
	"ring_01_l", "ring_02_l", "ring_03_l", "ring_03_leaf_l",
	"ring_01_r", "ring_02_r", "ring_03_r", "ring_03_leaf_r",
	"pinky_01_l", "pinky_02_l", "pinky_03_l", "pinky_03_leaf_l",
	"pinky_01_r", "pinky_02_r", "pinky_03_r", "pinky_03_leaf_r",
]

var total_files := 0
var pass_count := 0
var warn_count := 0
var fail_count := 0


func _init() -> void:
	_run_validation()
	quit()


func _run_validation() -> void:
	print("=== Synty Character Part Validation ===")
	print("")

	# Build set for fast lookup
	var ual_set := {}
	for bone in UAL_BONES:
		ual_set[bone] = true

	# Also load reference skeleton from UAL mannequin
	var ref_skeleton: Skeleton3D = null
	var mannequin_scene := load("res://assets/models/mannequin_f.glb")
	if mannequin_scene:
		var inst := mannequin_scene.instantiate()
		ref_skeleton = _find_skeleton(inst)
		if ref_skeleton:
			print("Reference skeleton: %d bones" % ref_skeleton.get_bone_count())
			# Add any bones from reference not in our static list
			for i in range(ref_skeleton.get_bone_count()):
				var bname := ref_skeleton.get_bone_name(i)
				if not ual_set.has(bname):
					ual_set[bname] = true
					print("  Extra reference bone: %s" % bname)
		inst.queue_free()
	else:
		print("WARNING: Could not load mannequin_f.glb for reference")

	print("")

	# Scan all GLB files under assets/characters/
	_scan_directory(CHARACTERS_DIR, ual_set)

	print("")
	print("=== Summary ===")
	print("  Total files: %d" % total_files)
	print("  Pass: %d" % pass_count)
	print("  Warnings: %d" % warn_count)
	print("  Failures: %d" % fail_count)


func _scan_directory(path: String, ual_set: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if not dir:
		print("WARNING: Cannot open directory: %s" % path)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		var full_path := path.path_join(file_name)
		if dir.current_is_dir():
			if not file_name.begins_with("."):
				_scan_directory(full_path, ual_set)
		elif file_name.ends_with(".glb") or file_name.ends_with(".glb.remap"):
			var glb_path := full_path
			if file_name.ends_with(".remap"):
				glb_path = full_path.replace(".remap", "")
			_validate_glb(glb_path, ual_set)
		file_name = dir.get_next()
	dir.list_dir_end()


func _validate_glb(glb_path: String, ual_set: Dictionary) -> void:
	total_files += 1
	var scene := load(glb_path)
	if not scene:
		print("FAIL: Cannot load %s" % glb_path)
		fail_count += 1
		return

	var inst := scene.instantiate()
	var skeleton := _find_skeleton(inst)

	if not skeleton:
		# Part might be a standalone mesh without skeleton (icons, etc.)
		# Check if it has any MeshInstance3D
		var meshes := _find_meshes(inst)
		if meshes.size() > 0:
			print("INFO: %s — mesh only (no skeleton), %d meshes" % [
				glb_path.replace(CHARACTERS_DIR, ""), meshes.size()])
		else:
			print("WARN: %s — no skeleton or meshes" % glb_path.replace(CHARACTERS_DIR, ""))
			warn_count += 1
		inst.queue_free()
		return

	# Check bone names
	var bone_count := skeleton.get_bone_count()
	var missing_ual: Array[String] = []
	var extra_bones: Array[String] = []
	var matched := 0

	for i in range(bone_count):
		var bname := skeleton.get_bone_name(i)
		if ual_set.has(bname):
			matched += 1
		else:
			extra_bones.append(bname)

	# Check vertex groups on mesh instances
	var mesh_bones: Array[String] = []
	var meshes := _find_meshes(inst)
	for mesh_inst: MeshInstance3D in meshes:
		if mesh_inst.skin:
			for i in range(mesh_inst.skin.get_bind_count()):
				var bname := mesh_inst.skin.get_bind_name(i)
				if not mesh_bones.has(bname):
					mesh_bones.append(bname)

	var short_path := glb_path.replace(CHARACTERS_DIR, "")

	if extra_bones.size() == 0:
		print("PASS: %s — %d/%d bones matched" % [short_path, matched, bone_count])
		pass_count += 1
	else:
		print("WARN: %s — %d matched, %d extra: %s" % [
			short_path, matched, extra_bones.size(), str(extra_bones)])
		warn_count += 1

	inst.queue_free()


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result := _find_skeleton(child)
		if result:
			return result
	return null


func _find_meshes(node: Node) -> Array:
	var result: Array = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_meshes(child))
	return result
