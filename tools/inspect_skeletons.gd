@tool
extends SceneTree

func _init() -> void:
	_run()
	quit()

func _run() -> void:
	print("\n=== Skeleton Inspection ===\n")

	var models := {
		"mannequin": "res://assets/models/mannequin_f.glb",
		"arkit_female": "res://assets/characters/female/base/modular_female.glb",
		"arkit_male": "res://assets/characters/male/base/modular_male.glb",
	}

	var bone_sets: Dictionary = {}

	for label in models:
		var path: String = models[label]
		var scene: PackedScene = load(path)
		if scene == null:
			print("ERROR: Could not load %s" % path)
			continue
		var inst: Node = scene.instantiate()
		var skel := _find_skeleton(inst)
		if skel == null:
			print("ERROR: No Skeleton3D in %s" % path)
			inst.free()
			continue

		var bones: Array[String] = []
		var rests: Dictionary = {}
		for i in range(skel.get_bone_count()):
			var bname := skel.get_bone_name(i)
			bones.append(bname)
			rests[bname] = skel.get_bone_rest(i)

		bone_sets[label] = {"bones": bones, "rests": rests}
		print("%s: %d bones" % [label, bones.size()])
		bones.sort()
		print("  Bones: %s" % str(bones))

		# Check skin on mesh children
		var mesh_count := 0
		var skin_count := 0
		var null_skin_count := 0
		for child in skel.get_children():
			if child is MeshInstance3D:
				mesh_count += 1
				if child.skin:
					skin_count += 1
				else:
					null_skin_count += 1
		print("  Meshes: %d (skin: %d, null-skin: %d)" % [mesh_count, skin_count, null_skin_count])
		print("")
		inst.free()

	# Compare mannequin vs arkit_female
	if bone_sets.has("mannequin") and bone_sets.has("arkit_female"):
		var mann_bones: Array = bone_sets["mannequin"]["bones"]
		var arkit_bones: Array = bone_sets["arkit_female"]["bones"]
		var mann_set: Dictionary = {}
		var arkit_set: Dictionary = {}
		for b in mann_bones:
			mann_set[b] = true
		for b in arkit_bones:
			arkit_set[b] = true

		var only_mann: Array[String] = []
		var only_arkit: Array[String] = []
		for b in mann_bones:
			if not arkit_set.has(b):
				only_mann.append(b)
		for b in arkit_bones:
			if not mann_set.has(b):
				only_arkit.append(b)

		print("=== Comparison: mannequin vs arkit_female ===")
		print("  Shared: %d" % (mann_bones.size() - only_mann.size()))
		if only_mann.size() > 0:
			print("  ONLY in mannequin: %s" % str(only_mann))
		if only_arkit.size() > 0:
			print("  ONLY in arkit: %s" % str(only_arkit))
		if only_mann.size() == 0 and only_arkit.size() == 0:
			print("  PERFECT MATCH!")

		# Compare rest poses for shared bones
		var mann_rests: Dictionary = bone_sets["mannequin"]["rests"]
		var arkit_rests: Dictionary = bone_sets["arkit_female"]["rests"]
		var max_diff := 0.0
		var worst_bone := ""
		for b in mann_bones:
			if arkit_set.has(b):
				var diff: float = (mann_rests[b].origin - arkit_rests[b].origin).length()
				if diff > max_diff:
					max_diff = diff
					worst_bone = b
		print("  Max rest pose origin diff: %.6f (bone: %s)" % [max_diff, worst_bone])

		if max_diff > 0.001:
			print("\n  Top rest pose differences:")
			var diffs: Array = []
			for b in mann_bones:
				if arkit_set.has(b):
					var diff: float = (mann_rests[b].origin - arkit_rests[b].origin).length()
					if diff > 0.001:
						diffs.append({"bone": b, "diff": diff, "mann": mann_rests[b].origin, "arkit": arkit_rests[b].origin})
			diffs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["diff"] > b["diff"])
			for i in range(mini(10, diffs.size())):
				var d: Dictionary = diffs[i]
				print("    %s: diff=%.4f mann=%s arkit=%s" % [d["bone"], d["diff"], d["mann"], d["arkit"]])


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result := _find_skeleton(child)
		if result:
			return result
	return null
