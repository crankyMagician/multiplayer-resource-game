@tool
extends Node
## Handles live scene manipulation requests (set property, delete, tiles, reparent).


func _convert_typed_value(value) -> Variant:
	if typeof(value) != TYPE_DICTIONARY:
		return value
	if not value.has("_type"):
		var result := {}
		for key in value:
			result[key] = _convert_typed_value(value[key])
		return result
	var t: String = value.get("_type", "")
	match t:
		"Vector2":
			return Vector2(value.get("x", 0.0), value.get("y", 0.0))
		"Vector2i":
			return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
		"Vector3":
			return Vector3(value.get("x", 0.0), value.get("y", 0.0), value.get("z", 0.0))
		"Vector3i":
			return Vector3i(int(value.get("x", 0)), int(value.get("y", 0)), int(value.get("z", 0)))
		"Color":
			return Color(value.get("r", 0.0), value.get("g", 0.0), value.get("b", 0.0), value.get("a", 1.0))
		"Rect2":
			return Rect2(value.get("x", 0.0), value.get("y", 0.0), value.get("w", 0.0), value.get("h", 0.0))
		"NodePath":
			return NodePath(value.get("path", ""))
		"Resource":
			var res_path: String = value.get("path", "")
			if res_path != "" and ResourceLoader.exists(res_path):
				return load(res_path)
			return null
		_:
			return value


func _vector3_to_dict(v: Vector3) -> Dictionary:
	return {"x": v.x, "y": v.y, "z": v.z}


func _safe_get_node_by_path(node_path: String) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	if node_path == "/root":
		return tree.root
	return tree.root.get_node_or_null(node_path.trim_prefix("/root"))


func handle_set_property(params) -> Dictionary:
	if not params is Dictionary:
		return {"error": "Invalid params"}

	var node_path: String = params.get("node_path", "")
	var property: String = params.get("property", "")
	var value = params.get("value", null)

	if node_path.is_empty() or property.is_empty():
		return {"error": "node_path and property are required"}

	var tree := get_tree()
	if tree == null:
		return {"error": "No scene tree available"}

	var node: Node = tree.root.get_node_or_null(node_path.trim_prefix("/root"))
	if node_path == "/root":
		node = tree.root
	if node == null:
		return {"error": "Node not found: %s" % node_path}

	var converted = _convert_typed_value(value)
	node.set(property, converted)

	return {"status": "ok", "node": node_path, "property": property}


func handle_delete_node(params) -> Dictionary:
	if not params is Dictionary:
		return {"error": "Invalid params"}

	var node_path: String = params.get("node_path", "")
	if node_path.is_empty():
		return {"error": "node_path is required"}

	var tree := get_tree()
	if tree == null:
		return {"error": "No scene tree available"}

	var node: Node = tree.root.get_node_or_null(node_path.trim_prefix("/root"))
	if node_path == "/root":
		return {"error": "Cannot delete root node"}
	if node == null:
		return {"error": "Node not found: %s" % node_path}

	var node_name := node.name
	node.get_parent().remove_child(node)
	node.queue_free()

	return {"status": "ok", "deleted": node_path, "name": node_name}


func handle_set_tiles(params) -> Dictionary:
	if not params is Dictionary:
		return {"error": "Invalid params"}

	var node_path: String = params.get("node_path", "")
	var tiles = params.get("tiles", [])

	if node_path.is_empty():
		return {"error": "node_path is required"}

	var tree := get_tree()
	if tree == null:
		return {"error": "No scene tree available"}

	var node: Node = tree.root.get_node_or_null(node_path.trim_prefix("/root"))
	if node == null:
		return {"error": "Node not found: %s" % node_path}
	if not node is TileMapLayer:
		return {"error": "Node is not a TileMapLayer: %s" % node.get_class()}

	var tilemap := node as TileMapLayer
	var count := 0
	if tiles is Array:
		for tile in tiles:
			var coords := Vector2i(int(tile.get("x", 0)), int(tile.get("y", 0)))
			var source_id := int(tile.get("source_id", 0))
			var atlas_coords := Vector2i(int(tile.get("atlas_x", 0)), int(tile.get("atlas_y", 0)))
			tilemap.set_cell(coords, source_id, atlas_coords)
			count += 1

	return {"status": "ok", "node": node_path, "tiles_set": count}


func handle_reparent_node(params) -> Dictionary:
	if not params is Dictionary:
		return {"error": "Invalid params"}

	var node_path: String = params.get("node_path", "")
	var new_parent_path: String = params.get("new_parent_path", "")

	if node_path.is_empty() or new_parent_path.is_empty():
		return {"error": "node_path and new_parent_path are required"}

	var tree := get_tree()
	if tree == null:
		return {"error": "No scene tree available"}

	var node: Node = tree.root.get_node_or_null(node_path.trim_prefix("/root"))
	if node_path == "/root":
		return {"error": "Cannot reparent root node"}
	if node == null:
		return {"error": "Node not found: %s" % node_path}

	var new_parent: Node = tree.root.get_node_or_null(new_parent_path.trim_prefix("/root"))
	if new_parent_path == "/root":
		new_parent = tree.root
	if new_parent == null:
		return {"error": "New parent not found: %s" % new_parent_path}

	node.reparent(new_parent)

	return {"status": "ok", "node": node_path, "new_parent": new_parent_path, "new_path": str(node.get_path())}


func handle_raycast_3d(params) -> Dictionary:
	if not params is Dictionary:
		return {"error": "Invalid params"}

	var from_param = params.get("from", null)
	var to_param = params.get("to", null)
	if typeof(from_param) != TYPE_DICTIONARY or typeof(to_param) != TYPE_DICTIONARY:
		return {"error": "from and to Vector3 dictionaries are required"}

	var from_v := Vector3(float(from_param.get("x", 0.0)), float(from_param.get("y", 0.0)), float(from_param.get("z", 0.0)))
	var to_v := Vector3(float(to_param.get("x", 0.0)), float(to_param.get("y", 0.0)), float(to_param.get("z", 0.0)))

	var root_viewport := get_tree().root
	if root_viewport == null:
		return {"error": "No root viewport available"}
	var world_3d := root_viewport.world_3d
	if world_3d == null:
		return {"error": "No active World3D available"}

	var query := PhysicsRayQueryParameters3D.create(from_v, to_v)
	if params.has("collision_mask"):
		query.collision_mask = int(params.get("collision_mask", 4294967295))
	if params.has("collide_with_areas"):
		query.collide_with_areas = bool(params.get("collide_with_areas", false))
	if params.has("collide_with_bodies"):
		query.collide_with_bodies = bool(params.get("collide_with_bodies", true))
	if params.has("hit_from_inside"):
		query.hit_from_inside = bool(params.get("hit_from_inside", false))
	if params.has("hit_back_faces"):
		query.hit_back_faces = bool(params.get("hit_back_faces", true))

	if params.has("exclude_node_paths") and params["exclude_node_paths"] is Array:
		var exclude_rids: Array = []
		for path_value in params["exclude_node_paths"]:
			var n = _safe_get_node_by_path(str(path_value))
			if n and n.has_method("get_rid"):
				exclude_rids.append(n.get_rid())
		query.exclude = exclude_rids

	var result := world_3d.direct_space_state.intersect_ray(query)
	if result.is_empty():
		return {
			"status": "ok",
			"hit": false,
			"from": _vector3_to_dict(from_v),
			"to": _vector3_to_dict(to_v)
		}

	var position: Vector3 = result.get("position", Vector3.ZERO)
	var normal: Vector3 = result.get("normal", Vector3.ZERO)
	var collider_obj = result.get("collider", null)
	var collider_path := ""
	if collider_obj and collider_obj is Node:
		collider_path = str((collider_obj as Node).get_path())

	return {
		"status": "ok",
		"hit": true,
		"position": _vector3_to_dict(position),
		"normal": _vector3_to_dict(normal),
		"collider_id": int(result.get("collider_id", 0)),
		"shape": int(result.get("shape", -1)),
		"face_index": int(result.get("face_index", -1)),
		"collider_path": collider_path
	}


func handle_spawn_node(params) -> Dictionary:
	if not params is Dictionary:
		return {"error": "Invalid params"}

	var node_type: String = params.get("node_type", "Node2D")
	var parent_path: String = params.get("parent_path", "")
	var node_name: String = params.get("name", "")
	var position = params.get("position", null)
	var properties: Dictionary = params.get("properties", {})
	var children: Array = params.get("children", [])
	var metadata: Dictionary = params.get("metadata", {})

	var tree := get_tree()
	if tree == null:
		return {"error": "No scene tree available"}

	# Find parent
	var parent: Node = null
	if not parent_path.is_empty():
		parent = _safe_get_node_by_path(parent_path)
	if parent == null:
		parent = tree.current_scene if tree.current_scene else tree.root

	# Create the node
	var node: Node = _create_node_by_type(node_type)
	if node == null:
		return {"error": "Unknown node type: %s" % node_type}

	if not node_name.is_empty():
		node.name = node_name

	# Set position
	if position is Dictionary:
		if node is Node2D:
			(node as Node2D).position = Vector2(
				float(position.get("x", 0)),
				float(position.get("y", 0))
			)
		elif node is Node3D:
			(node as Node3D).position = Vector3(
				float(position.get("x", 0)),
				float(position.get("y", 0)),
				float(position.get("z", 0))
			)
		elif node is Control:
			(node as Control).position = Vector2(
				float(position.get("x", 0)),
				float(position.get("y", 0))
			)

	# Set properties
	for key in properties:
		var val = _convert_typed_value(properties[key])
		node.set(key, val)

	# Set metadata
	for key in metadata:
		node.set_meta(key, metadata[key])

	# Add children
	for child_def in children:
		if not child_def is Dictionary:
			continue
		var child_type: String = child_def.get("node_type", "Node2D")
		var child: Node = _create_node_by_type(child_type)
		if child == null:
			continue
		if child_def.has("name"):
			child.name = child_def["name"]
		if child_def.has("position") and child_def["position"] is Dictionary:
			var cp: Dictionary = child_def["position"]
			if child is Node2D:
				(child as Node2D).position = Vector2(float(cp.get("x", 0)), float(cp.get("y", 0)))
			elif child is Control:
				(child as Control).position = Vector2(float(cp.get("x", 0)), float(cp.get("y", 0)))
		var child_props: Dictionary = child_def.get("properties", {})
		for key in child_props:
			child.set(key, _convert_typed_value(child_props[key]))
		# Handle shape for CollisionShape2D
		if child is CollisionShape2D and child_def.has("shape"):
			var shape_def: Dictionary = child_def["shape"]
			var shape := _create_shape_2d(shape_def)
			if shape:
				(child as CollisionShape2D).shape = shape
		node.add_child(child)

	parent.add_child(node)

	return {
		"status": "ok",
		"node_type": node_type,
		"path": str(node.get_path()),
		"children_added": children.size(),
	}


func _create_node_by_type(type_name: String) -> Node:
	match type_name:
		"Node": return Node.new()
		"Node2D": return Node2D.new()
		"Node3D": return Node3D.new()
		"Sprite2D": return Sprite2D.new()
		"Sprite3D": return Sprite3D.new()
		"ColorRect": return ColorRect.new()
		"Label": return Label.new()
		"Button": return Button.new()
		"Panel": return Panel.new()
		"HBoxContainer": return HBoxContainer.new()
		"VBoxContainer": return VBoxContainer.new()
		"MarginContainer": return MarginContainer.new()
		"ProgressBar": return ProgressBar.new()
		"LineEdit": return LineEdit.new()
		"TextureRect": return TextureRect.new()
		"CanvasLayer": return CanvasLayer.new()
		"StaticBody2D": return StaticBody2D.new()
		"CharacterBody2D": return CharacterBody2D.new()
		"RigidBody2D": return RigidBody2D.new()
		"Area2D": return Area2D.new()
		"CollisionShape2D": return CollisionShape2D.new()
		"Camera2D": return Camera2D.new()
		"Timer": return Timer.new()
		"AudioStreamPlayer": return AudioStreamPlayer.new()
		"AudioStreamPlayer2D": return AudioStreamPlayer2D.new()
		"StaticBody3D": return StaticBody3D.new()
		"CharacterBody3D": return CharacterBody3D.new()
		"RigidBody3D": return RigidBody3D.new()
		"Area3D": return Area3D.new()
		"CollisionShape3D": return CollisionShape3D.new()
		"Camera3D": return Camera3D.new()
		"MeshInstance3D": return MeshInstance3D.new()
		"DirectionalLight3D": return DirectionalLight3D.new()
		"OmniLight3D": return OmniLight3D.new()
		"SpotLight3D": return SpotLight3D.new()
		"GPUParticles2D": return GPUParticles2D.new()
		"GPUParticles3D": return GPUParticles3D.new()
		"AudioStreamPlayer3D": return AudioStreamPlayer3D.new()
		_: return null


func _create_shape_2d(shape_def: Dictionary) -> Shape2D:
	var shape_type: String = shape_def.get("type", shape_def.get("_type", "RectangleShape2D"))
	match shape_type:
		"RectangleShape2D":
			var shape := RectangleShape2D.new()
			if shape_def.has("size"):
				var s = shape_def["size"]
				if s is Dictionary:
					shape.size = Vector2(float(s.get("x", 32)), float(s.get("y", 32)))
				elif s is Array and s.size() >= 2:
					shape.size = Vector2(float(s[0]), float(s[1]))
			return shape
		"CircleShape2D":
			var shape := CircleShape2D.new()
			shape.radius = float(shape_def.get("radius", 16))
			return shape
		"CapsuleShape2D":
			var shape := CapsuleShape2D.new()
			shape.radius = float(shape_def.get("radius", 16))
			shape.height = float(shape_def.get("height", 32))
			return shape
		_:
			return null


func handle_create_shader(params) -> Dictionary:
	if not params is Dictionary:
		return {"error": "Invalid params"}

	var node_path: String = params.get("node_path", "")
	var shader_code: String = params.get("shader_code", "")
	var shader_params: Dictionary = params.get("params", {})
	var auto_detect: bool = params.get("auto_detect_shader_type", false)

	if node_path.is_empty() or shader_code.is_empty():
		return {"error": "node_path and shader_code are required"}

	var node := _safe_get_node_by_path(node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path}

	# Auto-detect shader type if requested
	if auto_detect:
		if node is CanvasItem:
			shader_code = "shader_type canvas_item;\n" + shader_code
		elif node is Node3D or node is MeshInstance3D:
			shader_code = "shader_type spatial;\n" + shader_code

	var shader := Shader.new()
	shader.code = shader_code

	var mat := ShaderMaterial.new()
	mat.shader = shader

	# Set shader params
	for key in shader_params:
		mat.set_shader_parameter(key, _convert_typed_value(shader_params[key]))

	# Apply to the node
	if node is CanvasItem:
		(node as CanvasItem).material = mat
	elif node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	else:
		return {"error": "Node type '%s' does not support materials" % node.get_class()}

	return {"status": "ok", "node": node_path, "shader_params": shader_params.keys()}


func handle_create_particles(params) -> Dictionary:
	if not params is Dictionary:
		return {"error": "Invalid params"}

	var tree := get_tree()
	if tree == null:
		return {"error": "No scene tree available"}

	var parent_path: String = params.get("parent_path", "")
	var parent: Node = null
	if not parent_path.is_empty():
		parent = _safe_get_node_by_path(parent_path)
	if parent == null:
		parent = tree.current_scene if tree.current_scene else tree.root

	var is_3d: bool = params.get("is_3d", false)
	var node_name: String = params.get("name", "Particles")

	if is_3d:
		var particles := GPUParticles3D.new()
		particles.name = node_name
		particles.amount = int(params.get("amount", 16))
		particles.lifetime = float(params.get("lifetime", 1.0))
		particles.one_shot = params.get("one_shot", false)
		particles.emitting = params.get("emitting", true)
		particles.explosiveness = float(params.get("explosiveness", 0.0))
		if params.has("position") and params["position"] is Dictionary:
			var p: Dictionary = params["position"]
			particles.position = Vector3(float(p.get("x", 0)), float(p.get("y", 0)), float(p.get("z", 0)))
		# Create process material
		var mat := ParticleProcessMaterial.new()
		if params.has("direction") and params["direction"] is Dictionary:
			var d: Dictionary = params["direction"]
			mat.direction = Vector3(float(d.get("x", 0)), float(d.get("y", -1)), float(d.get("z", 0)))
		mat.spread = float(params.get("spread", 45))
		mat.initial_velocity_min = float(params.get("initial_velocity_min", 20))
		mat.initial_velocity_max = float(params.get("initial_velocity_max", 50))
		if params.has("gravity") and params["gravity"] is Dictionary:
			var g: Dictionary = params["gravity"]
			mat.gravity = Vector3(float(g.get("x", 0)), float(g.get("y", 9.8)), float(g.get("z", 0)))
		mat.scale_min = float(params.get("scale_min", 1.0))
		mat.scale_max = float(params.get("scale_max", 1.0))
		if params.has("color"):
			mat.color = Color(params["color"])
		particles.process_material = mat
		parent.add_child(particles)
		return {"status": "ok", "path": str(particles.get_path()), "type": "GPUParticles3D"}
	else:
		var use_cpu: bool = params.get("use_cpu", false)

		if use_cpu:
			var particles := CPUParticles2D.new()
			particles.name = node_name
			particles.amount = int(params.get("amount", 16))
			particles.lifetime = float(params.get("lifetime", 1.0))
			particles.one_shot = params.get("one_shot", false)
			particles.emitting = params.get("emitting", true)
			particles.explosiveness = float(params.get("explosiveness", 0.0))
			if params.has("position") and params["position"] is Dictionary:
				var p: Dictionary = params["position"]
				particles.position = Vector2(float(p.get("x", 0)), float(p.get("y", 0)))
			if params.has("direction") and params["direction"] is Dictionary:
				var d: Dictionary = params["direction"]
				particles.direction = Vector2(float(d.get("x", 0)), float(d.get("y", -1)))
			particles.spread = float(params.get("spread", 45))
			particles.initial_velocity_min = float(params.get("initial_velocity_min", 20))
			particles.initial_velocity_max = float(params.get("initial_velocity_max", 50))
			if params.has("gravity") and params["gravity"] is Dictionary:
				var g: Dictionary = params["gravity"]
				particles.gravity = Vector2(float(g.get("x", 0)), float(g.get("y", 98)))
			particles.scale_amount_min = float(params.get("scale_min", 1.0))
			particles.scale_amount_max = float(params.get("scale_max", 1.0))
			if params.has("color"):
				particles.color = Color(params["color"])
			# Color ramp for CPU particles
			if params.has("color_ramp") and params["color_ramp"] is Array:
				var gradient := Gradient.new()
				gradient.offsets = PackedFloat32Array()
				gradient.colors = PackedColorArray()
				for stop in params["color_ramp"]:
					if stop is Dictionary:
						gradient.add_point(float(stop.get("offset", 0.0)), Color(stop.get("color", "#ffffff")))
				particles.color_ramp = gradient
			# Emission shape for CPU particles
			var emission_shape_str: String = params.get("emission_shape", "point")
			var emission_radius: float = float(params.get("emission_radius", 50))
			match emission_shape_str:
				"ring":
					particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RING
					particles.emission_ring_radius = emission_radius
					particles.emission_ring_inner_radius = emission_radius * 0.8
					particles.emission_ring_height = 0.0
				"sphere":
					particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
					particles.emission_sphere_radius = emission_radius
				"box":
					particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
					particles.emission_rect_extents = Vector2(emission_radius, emission_radius)
			parent.add_child(particles)
			return {"status": "ok", "path": str(particles.get_path()), "type": "CPUParticles2D"}
		else:
			var particles := GPUParticles2D.new()
			particles.name = node_name
			particles.amount = int(params.get("amount", 16))
			particles.lifetime = float(params.get("lifetime", 1.0))
			particles.one_shot = params.get("one_shot", false)
			particles.emitting = params.get("emitting", true)
			particles.explosiveness = float(params.get("explosiveness", 0.0))
			if params.has("position") and params["position"] is Dictionary:
				var p: Dictionary = params["position"]
				particles.position = Vector2(float(p.get("x", 0)), float(p.get("y", 0)))
			# Create process material
			var mat := ParticleProcessMaterial.new()
			if params.has("direction") and params["direction"] is Dictionary:
				var d: Dictionary = params["direction"]
				mat.direction = Vector3(float(d.get("x", 0)), float(d.get("y", -1)), 0)
			mat.spread = float(params.get("spread", 45))
			mat.initial_velocity_min = float(params.get("initial_velocity_min", 20))
			mat.initial_velocity_max = float(params.get("initial_velocity_max", 50))
			if params.has("gravity") and params["gravity"] is Dictionary:
				var g: Dictionary = params["gravity"]
				mat.gravity = Vector3(float(g.get("x", 0)), float(g.get("y", 98)), 0)
			mat.scale_min = float(params.get("scale_min", 1.0))
			mat.scale_max = float(params.get("scale_max", 1.0))
			if params.has("color"):
				mat.color = Color(params["color"])
			# Color ramp
			if params.has("color_ramp") and params["color_ramp"] is Array:
				var gradient := Gradient.new()
				gradient.offsets = PackedFloat32Array()
				gradient.colors = PackedColorArray()
				for stop in params["color_ramp"]:
					if stop is Dictionary:
						gradient.add_point(float(stop.get("offset", 0.0)), Color(stop.get("color", "#ffffff")))
				var grad_tex := GradientTexture1D.new()
				grad_tex.gradient = gradient
				mat.color_ramp = grad_tex
			# Emission shape
			var emission_shape_str: String = params.get("emission_shape", "point")
			var emission_radius: float = float(params.get("emission_radius", 50))
			match emission_shape_str:
				"ring":
					mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
					mat.emission_ring_radius = emission_radius
					mat.emission_ring_inner_radius = emission_radius * 0.8
					mat.emission_ring_height = 0.0
				"sphere":
					mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
					mat.emission_sphere_radius = emission_radius
				"box":
					mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
					mat.emission_box_extents = Vector3(emission_radius, emission_radius, 0)
			particles.process_material = mat
			parent.add_child(particles)
			return {"status": "ok", "path": str(particles.get_path()), "type": "GPUParticles2D"}


func handle_create_ui_node(params) -> Dictionary:
	if not params is Dictionary:
		return {"error": "Invalid params"}

	var tree := get_tree()
	if tree == null:
		return {"error": "No scene tree available"}

	var node_type: String = params.get("node_type", "Label")
	var parent_path: String = params.get("parent_path", "")
	var node_name: String = params.get("name", node_type)

	var parent: Node = null
	if not parent_path.is_empty():
		parent = _safe_get_node_by_path(parent_path)
	if parent == null:
		parent = tree.current_scene if tree.current_scene else tree.root

	var node: Node = _create_node_by_type(node_type)
	if node == null:
		return {"error": "Unknown node type: %s" % node_type}

	node.name = node_name

	# Set position
	if params.has("position") and params["position"] is Dictionary:
		var p: Dictionary = params["position"]
		if node is Control:
			(node as Control).position = Vector2(float(p.get("x", 0)), float(p.get("y", 0)))

	# Set size
	if params.has("size") and params["size"] is Dictionary:
		var s: Dictionary = params["size"]
		if node is Control:
			(node as Control).size = Vector2(float(s.get("x", 100)), float(s.get("y", 30)))

	# Set text
	if params.has("text") and params["text"] is String:
		if node is Label:
			(node as Label).text = params["text"]
		elif node is Button:
			(node as Button).text = params["text"]
		elif node is LineEdit:
			(node as LineEdit).text = params["text"]

	# Font size
	if params.has("font_size"):
		if node is Label or node is Button or node is LineEdit:
			node.add_theme_font_size_override("font_size", int(params["font_size"]))

	# Color
	if params.has("color"):
		var color_str: String = params["color"]
		if node is ColorRect:
			(node as ColorRect).color = Color(color_str)
		elif node is Label:
			(node as Label).add_theme_color_override("font_color", Color(color_str))

	# Value (ProgressBar)
	if params.has("value") and node is ProgressBar:
		(node as ProgressBar).value = float(params["value"]) * 100.0

	# Layer (CanvasLayer)
	if node is CanvasLayer:
		(node as CanvasLayer).layer = int(params.get("layer", 10))

	# Additional properties
	if params.has("properties") and params["properties"] is Dictionary:
		for key in params["properties"]:
			node.set(key, _convert_typed_value(params["properties"][key]))

	parent.add_child(node)

	return {
		"status": "ok",
		"node_type": node_type,
		"path": str(node.get_path()),
		"name": node_name,
	}


func handle_set_shader_parameter_live(params) -> Dictionary:
	if not params is Dictionary:
		return {"error": "Invalid params"}

	var node_path: String = params.get("node_path", "")
	var parameter_name: String = params.get("parameter_name", "")
	var value = params.get("value", null)
	var return_previous: bool = params.get("return_previous", false)

	if node_path.is_empty() or parameter_name.is_empty():
		return {"error": "node_path and parameter_name are required"}

	var node := _safe_get_node_by_path(node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path}

	var mat: ShaderMaterial = null
	if node is CanvasItem and (node as CanvasItem).material is ShaderMaterial:
		mat = (node as CanvasItem).material as ShaderMaterial
	elif node is MeshInstance3D and (node as MeshInstance3D).material_override is ShaderMaterial:
		mat = (node as MeshInstance3D).material_override as ShaderMaterial
	elif node is GeometryInstance3D and (node as GeometryInstance3D).material_override is ShaderMaterial:
		mat = (node as GeometryInstance3D).material_override as ShaderMaterial

	if mat == null:
		return {"error": "No ShaderMaterial found on node: %s" % node_path}

	var previous_value = null
	if return_previous:
		previous_value = mat.get_shader_parameter(parameter_name)

	mat.set_shader_parameter(parameter_name, _convert_typed_value(value))

	var result := {"status": "ok", "node": node_path, "parameter": parameter_name}
	if return_previous:
		result["previous_value"] = previous_value
	return result


func handle_batch_shader_updates(params) -> Dictionary:
	if not params is Dictionary:
		return {"error": "Invalid params"}

	var node_path: String = params.get("node_path", "")
	var parameters: Dictionary = params.get("parameters", {})

	if node_path.is_empty() or parameters.is_empty():
		return {"error": "node_path and parameters are required"}

	var node := _safe_get_node_by_path(node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path}

	var mat: ShaderMaterial = null
	if node is CanvasItem and (node as CanvasItem).material is ShaderMaterial:
		mat = (node as CanvasItem).material as ShaderMaterial
	elif node is MeshInstance3D and (node as MeshInstance3D).material_override is ShaderMaterial:
		mat = (node as MeshInstance3D).material_override as ShaderMaterial
	elif node is GeometryInstance3D and (node as GeometryInstance3D).material_override is ShaderMaterial:
		mat = (node as GeometryInstance3D).material_override as ShaderMaterial

	if mat == null:
		return {"error": "No ShaderMaterial found on node: %s" % node_path}

	var count := 0
	for key in parameters:
		mat.set_shader_parameter(key, _convert_typed_value(parameters[key]))
		count += 1

	return {"status": "ok", "node": node_path, "updated_count": count, "parameters": parameters.keys()}


## --- Group management ---

func handle_add_to_group(params) -> Dictionary:
	if not params is Dictionary:
		return {"error": "Invalid params"}
	var node_path: String = params.get("node_path", "")
	var group: String = params.get("group", "")
	if node_path.is_empty() or group.is_empty():
		return {"error": "node_path and group are required"}
	var node := _safe_get_node_by_path(node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path}
	var persistent: bool = params.get("persistent", false)
	node.add_to_group(group, persistent)
	return {"status": "ok", "node": node_path, "group": group, "persistent": persistent}


func handle_remove_from_group(params) -> Dictionary:
	if not params is Dictionary:
		return {"error": "Invalid params"}
	var node_path: String = params.get("node_path", "")
	var group: String = params.get("group", "")
	if node_path.is_empty() or group.is_empty():
		return {"error": "node_path and group are required"}
	var node := _safe_get_node_by_path(node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path}
	if not node.is_in_group(group):
		return {"error": "Node is not in group '%s'" % group}
	node.remove_from_group(group)
	return {"status": "ok", "node": node_path, "group": group}


func handle_get_nodes_in_group(params) -> Dictionary:
	if not params is Dictionary:
		return {"error": "Invalid params"}
	var group: String = params.get("group", "")
	if group.is_empty():
		return {"error": "group is required"}
	var tree := get_tree()
	if tree == null:
		return {"error": "No scene tree available"}
	var nodes: Array = []
	for node in tree.get_nodes_in_group(group):
		nodes.append({
			"path": str(node.get_path()),
			"name": node.name,
			"class": node.get_class(),
		})
	return {"status": "ok", "group": group, "nodes": nodes, "count": nodes.size()}


## --- Scene transitions ---

signal scene_changed(result: Dictionary)

func handle_change_scene(params) -> Dictionary:
	_change_scene_deferred(params)
	return {"_deferred": scene_changed}


func _change_scene_deferred(params) -> void:
	await get_tree().process_frame
	if not params is Dictionary:
		scene_changed.emit({"error": "Invalid params"})
		return
	var scene_path: String = params.get("scene_path", "")
	if scene_path.is_empty():
		scene_changed.emit({"error": "scene_path is required"})
		return
	var tree := get_tree()
	if tree == null:
		scene_changed.emit({"error": "No scene tree available"})
		return
	if not ResourceLoader.exists(scene_path):
		scene_changed.emit({"error": "Scene file not found: %s" % scene_path})
		return
	var err := tree.change_scene_to_file(scene_path)
	if err != OK:
		scene_changed.emit({"error": "Failed to change scene: %s" % error_string(err)})
		return
	# Wait for scene to load
	await tree.process_frame
	await tree.process_frame
	var new_scene := tree.current_scene
	scene_changed.emit({
		"status": "ok",
		"scene_path": scene_path,
		"root_node": new_scene.name if new_scene else "unknown",
		"root_class": new_scene.get_class() if new_scene else "unknown",
	})


func handle_get_current_scene(params) -> Dictionary:
	var tree := get_tree()
	if tree == null:
		return {"error": "No scene tree available"}
	var scene := tree.current_scene
	if scene == null:
		return {"error": "No current scene"}
	return {
		"status": "ok",
		"scene_path": scene.scene_file_path,
		"root_name": scene.name,
		"root_class": scene.get_class(),
		"child_count": scene.get_child_count(),
	}


## --- Scene instantiation ---

signal instance_ready(result: Dictionary)

func handle_instantiate_scene(params) -> Dictionary:
	_instantiate_scene_deferred(params)
	return {"_deferred": instance_ready}


func _instantiate_scene_deferred(params) -> void:
	await get_tree().process_frame
	if not params is Dictionary:
		instance_ready.emit({"error": "Invalid params"})
		return
	var scene_path: String = params.get("scene_path", "")
	if scene_path.is_empty():
		instance_ready.emit({"error": "scene_path is required"})
		return
	if not ResourceLoader.exists(scene_path):
		instance_ready.emit({"error": "Scene file not found: %s" % scene_path})
		return
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		instance_ready.emit({"error": "Failed to load scene: %s" % scene_path})
		return

	var tree := get_tree()
	var parent_path: String = params.get("parent_path", "")
	var parent: Node = null
	if not parent_path.is_empty():
		parent = _safe_get_node_by_path(parent_path)
	if parent == null:
		parent = tree.current_scene if tree.current_scene else tree.root

	var count: int = max(1, int(params.get("count", 1)))
	var instance_name: String = params.get("name", "")
	var pos = params.get("position", null)
	var props = params.get("properties", {})
	var instances: Array = []

	for i in range(count):
		var inst: Node = packed.instantiate()
		if not instance_name.is_empty():
			inst.name = instance_name if count == 1 else "%s_%d" % [instance_name, i]
		if pos is Dictionary and inst is Node2D:
			(inst as Node2D).position = Vector2(float(pos.get("x", 0)), float(pos.get("y", 0)))
		elif pos is Dictionary and inst is Node3D:
			(inst as Node3D).position = Vector3(float(pos.get("x", 0)), float(pos.get("y", 0)), float(pos.get("z", 0)))
		# Apply additional properties
		if props is Dictionary:
			for key in props:
				var val = _convert_typed_value(props[key])
				inst.set(key, val)
		parent.add_child(inst)
		instances.append({
			"path": str(inst.get_path()),
			"name": inst.name,
			"class": inst.get_class(),
		})

	instance_ready.emit({
		"status": "ok",
		"scene_path": scene_path,
		"instances": instances,
		"count": instances.size(),
	})


## --- Navigation 2D bridge ---

func handle_bake_navigation_2d(params) -> Dictionary:
	if not params is Dictionary:
		return {"error": "Invalid params"}
	var node_path: String = params.get("node_path", "")
	if node_path.is_empty():
		return {"error": "node_path is required"}
	var node := _safe_get_node_by_path(node_path)
	if node == null or not node is NavigationRegion2D:
		return {"error": "NavigationRegion2D not found: %s" % node_path}
	var region := node as NavigationRegion2D
	region.bake_navigation_polygon()
	return {"status": "ok", "node": node_path}


func handle_set_navigation_target(params) -> Dictionary:
	if not params is Dictionary:
		return {"error": "Invalid params"}
	var node_path: String = params.get("node_path", "")
	var pos = params.get("position", {})
	if node_path.is_empty():
		return {"error": "node_path is required"}
	var node := _safe_get_node_by_path(node_path)
	if node == null or not node is NavigationAgent2D:
		return {"error": "NavigationAgent2D not found: %s" % node_path}
	var agent := node as NavigationAgent2D
	var target := Vector2(float(pos.get("x", 0)), float(pos.get("y", 0)))
	agent.target_position = target
	return {"status": "ok", "node": node_path, "target": {"x": target.x, "y": target.y}}


func handle_capture_performance_snapshot(params) -> Dictionary:
	var include_raw := false
	if params is Dictionary:
		include_raw = bool(params.get("include_raw", false))

	var raw := {
		"time_fps": Performance.get_monitor(Performance.TIME_FPS),
		"time_process": Performance.get_monitor(Performance.TIME_PROCESS),
		"time_physics_process": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS),
		"memory_static": Performance.get_monitor(Performance.MEMORY_STATIC),
		"object_count": Performance.get_monitor(Performance.OBJECT_COUNT),
		"object_node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"render_total_objects_in_frame": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"render_total_primitives_in_frame": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"render_total_draw_calls_in_frame": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"render_video_mem_used": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"render_texture_mem_used": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),
		"render_buffer_mem_used": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),
		"physics_3d_active_objects": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		"physics_3d_collision_pairs": Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		"physics_3d_island_count": Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT),
		"navigation_3d_active_maps": Performance.get_monitor(Performance.NAVIGATION_3D_ACTIVE_MAPS),
		"navigation_3d_region_count": Performance.get_monitor(Performance.NAVIGATION_3D_REGION_COUNT),
		"navigation_3d_agent_count": Performance.get_monitor(Performance.NAVIGATION_3D_AGENT_COUNT),
		"navigation_3d_link_count": Performance.get_monitor(Performance.NAVIGATION_3D_LINK_COUNT),
		"navigation_3d_obstacle_count": Performance.get_monitor(Performance.NAVIGATION_3D_OBSTACLE_COUNT),
	}

	var summary := {
		"fps": raw["time_fps"],
		"frame_time_ms": float(raw["time_process"]) * 1000.0,
		"physics_time_ms": float(raw["time_physics_process"]) * 1000.0,
		"draw_calls": raw["render_total_draw_calls_in_frame"],
		"primitives": raw["render_total_primitives_in_frame"],
		"rendered_objects": raw["render_total_objects_in_frame"],
		"video_memory_mb": float(raw["render_video_mem_used"]) / (1024.0 * 1024.0),
		"texture_memory_mb": float(raw["render_texture_mem_used"]) / (1024.0 * 1024.0),
		"buffer_memory_mb": float(raw["render_buffer_mem_used"]) / (1024.0 * 1024.0),
		"static_memory_mb": float(raw["memory_static"]) / (1024.0 * 1024.0),
		"physics_active_bodies": raw["physics_3d_active_objects"],
		"physics_collision_pairs": raw["physics_3d_collision_pairs"],
		"navigation_active_maps": raw["navigation_3d_active_maps"],
		"navigation_regions": raw["navigation_3d_region_count"],
		"navigation_agents": raw["navigation_3d_agent_count"],
		"object_count": raw["object_count"],
		"node_count": raw["object_node_count"],
		"timestamp_msec": Time.get_ticks_msec(),
	}

	if include_raw:
		summary["raw"] = raw

	return summary
