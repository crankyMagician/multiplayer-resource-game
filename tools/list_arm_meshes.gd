@tool
extends SceneTree

func _init() -> void:
	var scene: PackedScene = load("res://assets/characters/female/base/modular_female.glb")
	var inst := scene.instantiate()
	var skel: Skeleton3D = _find_skel(inst)
	if not skel:
		print("NO SKELETON")
		quit()
		return
	var arm_meshes: Array[String] = []
	var all_prefixes: Dictionary = {}
	for child in skel.get_children():
		if child is MeshInstance3D:
			var n: String = child.name
			var prefix: String = n.split("_")[0] if "_" in n else n
			if not all_prefixes.has(prefix):
				all_prefixes[prefix] = 0
			all_prefixes[prefix] += 1
			var nl: String = n.to_lower()
			if nl.begins_with("arms") or nl.begins_with("hand"):
				arm_meshes.append(n)
	arm_meshes.sort()
	print("ALL MESH PREFIXES:")
	var keys: Array = all_prefixes.keys()
	keys.sort()
	for k in keys:
		print("  %s: %d meshes" % [k, all_prefixes[k]])
	print("\nARM/HAND MESHES (%d):" % arm_meshes.size())
	for m in arm_meshes:
		print("  " + m)
	inst.free()
	quit()

func _find_skel(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result := _find_skel(child)
		if result:
			return result
	return null
