@tool
extends SceneTree

func _init() -> void:
	_run()
	quit()

func _run() -> void:
	print("\n=== Node Hierarchy Inspection ===\n")

	var models := {
		"mannequin": "res://assets/models/mannequin_f.glb",
		"arkit_female": "res://assets/characters/female/base/modular_female.glb",
	}

	for label in models:
		var path: String = models[label]
		var scene: PackedScene = load(path)
		if scene == null:
			print("ERROR: Could not load %s" % path)
			continue
		var inst: Node = scene.instantiate()
		print("--- %s (%s) ---" % [label, path])
		_print_tree(inst, 0, 3)  # Print 3 levels deep
		print("")
		inst.free()

	# Also check animation track paths
	print("--- Animation Track Paths (first Idle anim) ---")
	var lib: AnimationLibrary = load("res://assets/animations/player_animation_library.tres")
	if lib:
		for anim_name in ["Idle", "Walk_Fwd", "Jog_Fwd"]:
			var sname := StringName(anim_name)
			if lib.has_animation(sname):
				var anim: Animation = lib.get_animation(sname)
				print("%s: %d tracks" % [anim_name, anim.get_track_count()])
				for i in range(mini(5, anim.get_track_count())):
					print("  track[%d]: path=%s type=%d" % [i, anim.track_get_path(i), anim.track_get_type(i)])
				if anim.get_track_count() > 5:
					print("  ... and %d more" % (anim.get_track_count() - 5))
	else:
		print("ERROR: Could not load animation library")


func _print_tree(node: Node, depth: int, max_depth: int) -> void:
	var indent := "  ".repeat(depth)
	var type_name := node.get_class()
	var extra := ""
	if node is Skeleton3D:
		extra = " [%d bones]" % (node as Skeleton3D).get_bone_count()
	elif node is MeshInstance3D:
		var mi := node as MeshInstance3D
		extra = " [skin=%s]" % ("yes" if mi.skin else "null")
	print("%s%s (%s)%s" % [indent, node.name, type_name, extra])

	if depth < max_depth:
		var child_count := node.get_child_count()
		var shown := 0
		for child in node.get_children():
			if child is MeshInstance3D and shown >= 3 and depth == max_depth - 1:
				print("%s  ... and %d more mesh children" % [indent, child_count - shown])
				break
			_print_tree(child, depth + 1, max_depth)
			shown += 1
			if shown >= 10 and child_count > 10:
				print("%s  ... and %d more children" % [indent, child_count - shown])
				break
