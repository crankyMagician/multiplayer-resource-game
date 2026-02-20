@tool
extends Node
## Handles game state queries — returns structured state of the running game.

signal game_state_ready(result: Dictionary)


func handle_get_game_state(params) -> Dictionary:
	_collect_state_deferred(params)
	return {"_deferred": game_state_ready}


func _collect_state_deferred(params) -> void:
	await get_tree().process_frame

	var include_objects: bool = true
	var include_metadata: bool = true
	if params is Dictionary:
		include_objects = params.get("include_objects", true)
		include_metadata = params.get("include_metadata", true)

	var tree := get_tree()
	if tree == null:
		game_state_ready.emit({"error": "No scene tree available"})
		return

	var root := tree.root
	if root == null:
		game_state_ready.emit({"error": "No root viewport"})
		return

	var result := {}

	# Game engine state — try RuleEngine singleton first, then scan generically
	var rule_engine = root.get_node_or_null("RuleEngine")
	if rule_engine:
		result["score"] = rule_engine.get("score")
		result["health"] = rule_engine.get("health")
		result["game_active"] = rule_engine.get("game_active")
		result["game_won"] = rule_engine.get("game_won")
		result["game_lost"] = rule_engine.get("game_lost")
		if rule_engine.has_method("get_game_type"):
			result["game_type"] = rule_engine.get_game_type()
		if rule_engine.has_method("get_title"):
			result["title"] = rule_engine.get_title()
		if rule_engine.has_method("get_win_condition"):
			result["win_condition"] = rule_engine.get_win_condition()
		if rule_engine.has_method("get_lose_condition"):
			result["lose_condition"] = rule_engine.get_lose_condition()
		if rule_engine.has_method("get_config"):
			result["config"] = rule_engine.get_config()
	else:
		# Generic scan: look for common game state properties in autoloads and current scene
		var game_vars := _scan_game_state_generic(root, tree.current_scene)
		result.merge(game_vars)
		# Ensure standard keys exist even if not found
		if not result.has("score"):
			result["score"] = null
		if not result.has("health"):
			result["health"] = null
		if not result.has("game_active"):
			result["game_active"] = null

	# Find the player node
	var player_data := _find_player(root)
	result["player"] = player_data

	# Collect all game objects
	if include_objects:
		result["objects"] = _collect_objects(root, include_metadata)

	# Scene info
	var current_scene := tree.current_scene
	if current_scene:
		result["current_scene"] = str(current_scene.get_path())
		result["scene_name"] = current_scene.name

	result["timestamp_msec"] = Time.get_ticks_msec()

	game_state_ready.emit(result)


func _scan_game_state_generic(root: Node, current_scene: Node) -> Dictionary:
	var result := {}
	# Known state property names to look for
	var state_keys := ["score", "health", "lives", "level", "game_active", "game_over",
		"game_won", "game_lost", "coins", "time_left", "enemies_remaining"]

	# Scan autoload singletons (direct children of root)
	for child in root.get_children():
		if child == current_scene:
			continue
		for key in state_keys:
			var val = child.get(key)
			if val != null and not result.has(key):
				result[key] = val

	# Scan current scene root for state properties
	if current_scene:
		for key in state_keys:
			var val = current_scene.get(key)
			if val != null and not result.has(key):
				result[key] = val

	return result


func _find_player(root: Node) -> Dictionary:
	# Look for common player node patterns
	var player: Node = null
	var tree := get_tree()
	var current_scene := tree.current_scene if tree else null

	# Search bases: current scene first, then known game loader paths, then root
	var bases: Array[Node] = []
	if current_scene:
		bases.append(current_scene)
	var game_loader := root.get_node_or_null("GameLoader/Game")
	if game_loader and game_loader != current_scene:
		bases.append(game_loader)
	if root not in bases:
		bases.append(root)

	for base in bases:
		player = _find_node_recursive(base, func(n: Node) -> bool:
			if n.name.to_lower().contains("player"):
				return true
			# Check if it's a CharacterBody with no "enemy" meta
			if n is CharacterBody2D and not n.has_meta("enemy"):
				return true
			if n is CharacterBody3D and not n.has_meta("enemy"):
				return true
			return false
		)
		if player:
			break

	if player == null:
		return {"found": false}

	var data := {
		"found": true,
		"path": str(player.get_path()),
		"position": {"x": player.position.x, "y": player.position.y},
	}

	if player is CharacterBody2D:
		var cb := player as CharacterBody2D
		data["velocity"] = {"x": cb.velocity.x, "y": cb.velocity.y}
		data["on_floor"] = cb.is_on_floor()
		data["on_wall"] = cb.is_on_wall()
		data["on_ceiling"] = cb.is_on_ceiling()
	elif player is CharacterBody3D:
		var cb := player as CharacterBody3D
		data["position"] = {"x": cb.position.x, "y": cb.position.y, "z": cb.position.z}
		data["velocity"] = {"x": cb.velocity.x, "y": cb.velocity.y, "z": cb.velocity.z}
		data["on_floor"] = cb.is_on_floor()

	return data


func _collect_objects(root: Node, include_metadata: bool) -> Array:
	var objects: Array = []
	var tree := get_tree()

	# Prefer current scene as game root, fall back to known paths, then viewport root
	var game_root: Node = null
	if tree and tree.current_scene:
		game_root = tree.current_scene
	else:
		for path in ["GameLoader/Game", ""]:
			if path.is_empty():
				game_root = root
			else:
				game_root = root.get_node_or_null(path)
			if game_root:
				break

	if game_root == null:
		return objects

	_collect_objects_recursive(game_root, objects, include_metadata, 0)
	return objects


func _collect_objects_recursive(node: Node, objects: Array, include_metadata: bool, depth: int) -> void:
	if depth > 20:
		return  # Safety limit

	for child in node.get_children():
		var obj := _node_to_object(child, include_metadata)
		if obj != null:
			objects.append(obj)
		# Don't recurse into nodes we've already captured as objects — their children are internal
		# But do recurse into container nodes
		if obj == null or child.get_child_count() > 5:
			_collect_objects_recursive(child, objects, include_metadata, depth + 1)


func _node_to_object(node: Node, include_metadata: bool) -> Variant:
	# Only report interesting game objects, not internal children
	var obj_type := ""

	if node.has_meta("enemy"):
		obj_type = "enemy"
	elif node is StaticBody2D:
		obj_type = "platform"
	elif node is Area2D:
		# Could be collectible, portal, hitbox, etc.
		if node.collision_layer == 2:
			obj_type = "collectible"
		elif node.name.to_lower().contains("portal"):
			obj_type = "portal"
		elif node.has_meta("bullet"):
			obj_type = "projectile"
		else:
			# Check for portal-like Area2D (body_entered connected)
			obj_type = "area"
	elif node is CharacterBody2D and not node.has_meta("enemy"):
		# Skip player — reported separately
		return null
	else:
		return null

	var data := {
		"type": obj_type,
		"name": node.name,
		"path": str(node.get_path()),
		"class": node.get_class(),
	}

	if node is Node2D:
		data["position"] = {"x": (node as Node2D).position.x, "y": (node as Node2D).position.y}
	elif node is Node3D:
		var n3 := node as Node3D
		data["position"] = {"x": n3.position.x, "y": n3.position.y, "z": n3.position.z}

	if node is CharacterBody2D:
		var cb := node as CharacterBody2D
		data["velocity"] = {"x": cb.velocity.x, "y": cb.velocity.y}

	if include_metadata:
		var meta_dict := {}
		for key in node.get_meta_list():
			var val = node.get_meta(key)
			# Only include serializable values
			if val is String or val is float or val is int or val is bool:
				meta_dict[key] = val
			elif val is Vector2:
				meta_dict[key] = {"x": val.x, "y": val.y}
			elif val is Vector3:
				meta_dict[key] = {"x": val.x, "y": val.y, "z": val.z}
		if not meta_dict.is_empty():
			data["metadata"] = meta_dict

	return data


func _find_node_recursive(root: Node, predicate: Callable) -> Node:
	for child in root.get_children():
		if predicate.call(child):
			return child
		var found := _find_node_recursive(child, predicate)
		if found:
			return found
	return null


func handle_toggle_debug_visuals(params) -> Dictionary:
	if not params is Dictionary:
		return {"error": "Invalid params"}

	var enable: bool = params.get("enable", true)
	var show_collision: bool = params.get("show_collision", true)
	var show_navigation: bool = params.get("show_navigation", false)

	var tree := get_tree()
	if tree == null:
		return {"error": "No scene tree available"}

	if show_collision:
		tree.debug_collisions_hint = enable
	if show_navigation:
		tree.debug_navigation_hint = enable

	return {
		"status": "ok",
		"debug_collisions": tree.debug_collisions_hint,
		"debug_navigation": tree.debug_navigation_hint,
	}
