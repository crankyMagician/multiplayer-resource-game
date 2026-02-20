@tool
extends Node
## Handles scene tree inspection requests.


func handle_get_tree(params) -> Dictionary:
	var max_depth: int = params.get("depth", 5) if params is Dictionary else 5
	var root_path: String = params.get("root_path", "/root") if params is Dictionary else "/root"
	var include_props: bool = params.get("include_properties", false) if params is Dictionary else false

	var tree := get_tree()
	if tree == null:
		return {"error": "No scene tree available"}

	var root_node: Node = tree.root.get_node_or_null(root_path.trim_prefix("/root"))
	if root_path == "/root":
		root_node = tree.root

	if root_node == null:
		return {"error": "Node not found: %s" % root_path}

	return _serialize_node(root_node, 0, max_depth, include_props)


func handle_get_properties(params) -> Dictionary:
	if not params is Dictionary:
		return {"error": "Invalid params"}

	var node_path: String = params.get("node_path", "")
	var categories = params.get("categories", null)

	if node_path.is_empty():
		return {"error": "node_path is required"}

	var tree := get_tree()
	if tree == null:
		return {"error": "No scene tree available"}

	var node: Node = tree.root.get_node_or_null(node_path.trim_prefix("/root"))
	if node_path == "/root":
		node = tree.root

	if node == null:
		return {"error": "Node not found: %s" % node_path}

	return _get_node_properties(node, categories)


func _serialize_node(node: Node, depth: int, max_depth: int, include_props: bool) -> Dictionary:
	var result := {
		"name": node.name,
		"type": node.get_class(),
		"path": str(node.get_path()),
		"child_count": node.get_child_count(),
	}

	if include_props:
		# Add basic spatial properties
		if node is Node2D:
			var n2d := node as Node2D
			result["position"] = {"x": n2d.position.x, "y": n2d.position.y}
			result["rotation"] = n2d.rotation
			result["scale"] = {"x": n2d.scale.x, "y": n2d.scale.y}
			result["visible"] = n2d.visible
		elif node is Node3D:
			var n3d := node as Node3D
			result["position"] = {"x": n3d.position.x, "y": n3d.position.y, "z": n3d.position.z}
			result["rotation"] = {"x": n3d.rotation.x, "y": n3d.rotation.y, "z": n3d.rotation.z}
			result["scale"] = {"x": n3d.scale.x, "y": n3d.scale.y, "z": n3d.scale.z}
			result["visible"] = n3d.visible
		elif node is Control:
			var ctrl := node as Control
			result["position"] = {"x": ctrl.position.x, "y": ctrl.position.y}
			result["size"] = {"x": ctrl.size.x, "y": ctrl.size.y}
			result["visible"] = ctrl.visible

		# Script info
		var script = node.get_script()
		if script:
			result["script"] = script.resource_path

	# Recurse into children
	if max_depth < 0 or depth < max_depth:
		var children: Array = []
		for child in node.get_children():
			children.append(_serialize_node(child, depth + 1, max_depth, include_props))
		if children.size() > 0:
			result["children"] = children

	return result


func _get_node_properties(node: Node, categories) -> Dictionary:
	var result := {
		"name": node.name,
		"type": node.get_class(),
		"path": str(node.get_path()),
		"properties": {}
	}

	var cat_filter: Array = []
	if categories is Array:
		cat_filter = categories

	var props := node.get_property_list()

	for prop in props:
		var prop_name: String = prop.get("name", "")
		var prop_usage: int = prop.get("usage", 0)

		# Only include editor/exported properties
		if not (prop_usage & PROPERTY_USAGE_EDITOR or prop_usage & PROPERTY_USAGE_STORAGE):
			continue

		# Category filtering
		if cat_filter.size() > 0:
			var prop_category: String = prop.get("class_name", "").to_lower()
			var found := false
			for cat in cat_filter:
				if prop_name.to_lower().begins_with(cat.to_lower()) or prop_category == cat.to_lower():
					found = true
					break
			if not found:
				# Also check common category mappings
				if "transform" in cat_filter and prop_name in ["position", "rotation", "scale", "global_position", "global_rotation", "global_transform", "transform"]:
					found = true
				elif "visibility" in cat_filter and prop_name in ["visible", "modulate", "self_modulate", "show_behind_parent", "z_index", "z_as_relative"]:
					found = true
				elif "script" in cat_filter and prop_name in ["script"]:
					found = true
				if not found:
					continue

		# Skip internal properties
		if prop_name.begins_with("_") or prop_name.is_empty():
			continue

		var value = node.get(prop_name)
		result["properties"][prop_name] = _serialize_value(value)

	return result


func _serialize_value(value) -> Variant:
	match typeof(value):
		TYPE_VECTOR2:
			return {"_type": "Vector2", "x": value.x, "y": value.y}
		TYPE_VECTOR3:
			return {"_type": "Vector3", "x": value.x, "y": value.y, "z": value.z}
		TYPE_VECTOR2I:
			return {"_type": "Vector2i", "x": value.x, "y": value.y}
		TYPE_VECTOR3I:
			return {"_type": "Vector3i", "x": value.x, "y": value.y, "z": value.z}
		TYPE_COLOR:
			return {"_type": "Color", "r": value.r, "g": value.g, "b": value.b, "a": value.a}
		TYPE_RECT2:
			return {"_type": "Rect2", "x": value.position.x, "y": value.position.y, "w": value.size.x, "h": value.size.y}
		TYPE_TRANSFORM2D:
			return {"_type": "Transform2D", "origin": {"x": value.origin.x, "y": value.origin.y}}
		TYPE_TRANSFORM3D:
			return {"_type": "Transform3D", "origin": {"x": value.origin.x, "y": value.origin.y, "z": value.origin.z}}
		TYPE_BASIS:
			return {"_type": "Basis"}
		TYPE_QUATERNION:
			return {"_type": "Quaternion", "x": value.x, "y": value.y, "z": value.z, "w": value.w}
		TYPE_AABB:
			return {"_type": "AABB", "position": {"x": value.position.x, "y": value.position.y, "z": value.position.z}, "size": {"x": value.size.x, "y": value.size.y, "z": value.size.z}}
		TYPE_NODE_PATH:
			return {"_type": "NodePath", "path": str(value)}
		TYPE_OBJECT:
			if value == null:
				return null
			if value is Resource:
				return {"_type": "Resource", "class": value.get_class(), "path": value.resource_path}
			return {"_type": value.get_class()}
		TYPE_ARRAY:
			var arr: Array = []
			for item in value:
				arr.append(_serialize_value(item))
			return arr
		TYPE_DICTIONARY:
			var dict: Dictionary = {}
			for key in value:
				dict[str(key)] = _serialize_value(value[key])
			return dict
		_:
			return value


func handle_inspect_recursive(params) -> Dictionary:
	if not params is Dictionary:
		return {"error": "Invalid params"}
	var node_path: String = params.get("node_path", "")
	var max_depth: int = int(params.get("depth", 3))
	if node_path.is_empty():
		return {"error": "node_path is required"}
	var tree := get_tree()
	if tree == null:
		return {"error": "No scene tree"}
	var node: Node = tree.root.get_node_or_null(node_path.trim_prefix("/root"))
	if node_path == "/root":
		node = tree.root
	if node == null:
		return {"error": "Node not found: %s" % node_path}
	return {"status": "ok", "tree": _inspect_recursive(node, 0, max_depth)}


func _inspect_recursive(node: Node, depth: int, max_depth: int) -> Dictionary:
	var info := {
		"name": node.name,
		"class": node.get_class(),
		"path": str(node.get_path()),
	}
	# Add spatial info
	if node is Node2D:
		var n2 := node as Node2D
		info["position"] = {"x": n2.position.x, "y": n2.position.y}
		info["visible"] = n2.visible
	elif node is Node3D:
		var n3 := node as Node3D
		info["position"] = {"x": n3.position.x, "y": n3.position.y, "z": n3.position.z}
		info["visible"] = n3.visible
	elif node is Control:
		var c := node as Control
		info["position"] = {"x": c.position.x, "y": c.position.y}
		info["size"] = {"x": c.size.x, "y": c.size.y}
		info["visible"] = c.visible
	# Groups
	var groups := node.get_groups()
	if not groups.is_empty():
		info["groups"] = Array(groups)
	# Script
	var script = node.get_script()
	if script:
		info["script"] = script.resource_path
	# Children
	if depth < max_depth and node.get_child_count() > 0:
		var children: Array = []
		for child in node.get_children():
			children.append(_inspect_recursive(child, depth + 1, max_depth))
		info["children"] = children
	elif node.get_child_count() > 0:
		info["child_count"] = node.get_child_count()
	return info
