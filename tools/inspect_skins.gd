@tool
extends SceneTree

func _init() -> void:
	_run()
	quit()

func _run() -> void:
	print("\n=== Skin Bind Pose Inspection ===\n")

	# Load mannequin
	var mann_scene: PackedScene = load("res://assets/models/mannequin_f.glb")
	var mann_inst: Node = mann_scene.instantiate()
	var mann_skel := _find_skeleton(mann_inst)
	var mann_mesh: MeshInstance3D = null
	for child in mann_skel.get_children():
		if child is MeshInstance3D:
			mann_mesh = child
			break

	print("--- Mannequin Skin ---")
	if mann_mesh and mann_mesh.skin:
		var skin := mann_mesh.skin
		print("  Bind count: %d" % skin.get_bind_count())
		for i in range(mini(5, skin.get_bind_count())):
			var name := skin.get_bind_name(i)
			var bone := skin.get_bind_bone(i)
			var pose := skin.get_bind_pose(i)
			print("  bind[%d]: name=%s bone_idx=%d origin=%s" % [i, name, bone, pose.origin])
	else:
		print("  NO SKIN on mannequin mesh!")

	# Load AR Kit female
	var arkit_scene: PackedScene = load("res://assets/characters/female/base/modular_female.glb")
	var arkit_inst: Node = arkit_scene.instantiate()
	var arkit_skel := _find_skeleton(arkit_inst)

	# Pick first visible-by-default mesh (head)
	var arkit_mesh: MeshInstance3D = null
	for child in arkit_skel.get_children():
		if child is MeshInstance3D:
			arkit_mesh = child
			break

	print("\n--- AR Kit Female First Mesh (%s) ---" % (arkit_mesh.name if arkit_mesh else "NONE"))
	if arkit_mesh and arkit_mesh.skin:
		var skin := arkit_mesh.skin
		print("  Bind count: %d" % skin.get_bind_count())
		for i in range(mini(5, skin.get_bind_count())):
			var name := skin.get_bind_name(i)
			var bone := skin.get_bind_bone(i)
			var pose := skin.get_bind_pose(i)
			print("  bind[%d]: name=%s bone_idx=%d origin=%s" % [i, name, bone, pose.origin])
	else:
		print("  NO SKIN!")

	# Compare bind poses for shared bone names
	if mann_mesh and mann_mesh.skin and arkit_mesh and arkit_mesh.skin:
		print("\n--- Bind Pose Comparison ---")
		var mann_skin := mann_mesh.skin
		var arkit_skin := arkit_mesh.skin

		# Build name -> bind_pose maps
		var mann_binds: Dictionary = {}
		for i in range(mann_skin.get_bind_count()):
			mann_binds[mann_skin.get_bind_name(i)] = mann_skin.get_bind_pose(i)

		var arkit_binds: Dictionary = {}
		for i in range(arkit_skin.get_bind_count()):
			arkit_binds[arkit_skin.get_bind_name(i)] = arkit_skin.get_bind_pose(i)

		var max_diff := 0.0
		var worst_bone := ""
		var diffs: Array = []
		for bname in mann_binds:
			if arkit_binds.has(bname):
				var m_pose: Transform3D = mann_binds[bname]
				var s_pose: Transform3D = arkit_binds[bname]
				var origin_diff: float = (m_pose.origin - s_pose.origin).length()
				if origin_diff > max_diff:
					max_diff = origin_diff
					worst_bone = bname
				if origin_diff > 0.001:
					diffs.append({"bone": bname, "diff": origin_diff, "mann": m_pose.origin, "arkit": s_pose.origin})
		diffs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["diff"] > b["diff"])

		print("  Max bind pose origin diff: %.6f (bone: %s)" % [max_diff, worst_bone])
		if diffs.size() > 0:
			print("  Bones with significant bind pose differences:")
			for i in range(mini(15, diffs.size())):
				var d: Dictionary = diffs[i]
				print("    %s: diff=%.4f mann=%s arkit=%s" % [d["bone"], d["diff"], d["mann"], d["arkit"]])
		else:
			print("  ALL bind poses match!")

	# Also compare rest poses from the skeleton directly
	print("\n--- Rest Pose (global_rest) Comparison ---")
	var max_rest_diff := 0.0
	var worst_rest := ""
	for i in range(mann_skel.get_bone_count()):
		var bname := mann_skel.get_bone_name(i)
		var arkit_idx := arkit_skel.find_bone(bname)
		if arkit_idx >= 0:
			var m_rest := mann_skel.get_bone_global_rest(i)
			var s_rest := arkit_skel.get_bone_global_rest(arkit_idx)
			var diff: float = (m_rest.origin - s_rest.origin).length()
			if diff > max_rest_diff:
				max_rest_diff = diff
				worst_rest = bname
	print("  Max global rest diff: %.6f (bone: %s)" % [max_rest_diff, worst_rest])

	mann_inst.free()
	arkit_inst.free()


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result := _find_skeleton(child)
		if result:
			return result
	return null
