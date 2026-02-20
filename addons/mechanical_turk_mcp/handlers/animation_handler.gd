@tool
extends Node
## Handles animation playback control.

signal anim_ready(result: Dictionary)

func handle_play_animation(params) -> Dictionary:
	_play_anim_deferred(params)
	return {"_deferred": anim_ready}

func _play_anim_deferred(params) -> void:
	await get_tree().process_frame
	var node_path: String = params.get("node_path", "")
	var anim_name: String = params.get("animation_name", "")
	var speed: float = float(params.get("speed", 1.0))
	var backwards: bool = params.get("backwards", false)
	var tree := get_tree()
	var node := tree.root.get_node_or_null(node_path.trim_prefix("/root"))
	if node_path == "/root": node = tree.root
	if node == null:
		anim_ready.emit({"error": "Node not found: %s" % node_path})
		return
	if node is AnimationPlayer:
		var player := node as AnimationPlayer
		if backwards:
			player.play_backwards(anim_name)
		else:
			player.play(anim_name, -1, speed)
		anim_ready.emit({"status": "ok", "node": node_path, "animation": anim_name, "type": "AnimationPlayer"})
	elif node is AnimatedSprite2D:
		var sprite := node as AnimatedSprite2D
		if not anim_name.is_empty():
			sprite.animation = anim_name
		sprite.speed_scale = speed
		if backwards:
			sprite.play_backwards()
		else:
			sprite.play()
		anim_ready.emit({"status": "ok", "node": node_path, "animation": anim_name, "type": "AnimatedSprite2D"})
	else:
		anim_ready.emit({"error": "Node is not an AnimationPlayer or AnimatedSprite2D: %s" % node_path})

func handle_stop_animation(params) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var keep_state: bool = params.get("keep_state", false)
	var tree := get_tree()
	if tree == null: return {"error": "No scene tree"}
	var node := tree.root.get_node_or_null(node_path.trim_prefix("/root"))
	if node_path == "/root": node = tree.root
	if node == null: return {"error": "Node not found: %s" % node_path}
	if node is AnimationPlayer:
		var player := node as AnimationPlayer
		player.stop(keep_state)
		return {"status": "ok", "node": node_path}
	elif node is AnimatedSprite2D:
		(node as AnimatedSprite2D).stop()
		return {"status": "ok", "node": node_path}
	return {"error": "Node is not an AnimationPlayer or AnimatedSprite2D"}

func handle_get_animation_state(params) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var tree := get_tree()
	if tree == null: return {"error": "No scene tree"}
	var node := tree.root.get_node_or_null(node_path.trim_prefix("/root"))
	if node_path == "/root": node = tree.root
	if node == null: return {"error": "Node not found: %s" % node_path}
	if node is AnimationPlayer:
		var player := node as AnimationPlayer
		return {
			"status": "ok",
			"node": node_path,
			"type": "AnimationPlayer",
			"current_animation": player.current_animation,
			"current_animation_position": player.current_animation_position,
			"current_animation_length": player.current_animation_length,
			"is_playing": player.is_playing(),
			"animation_list": Array(player.get_animation_list()),
		}
	elif node is AnimatedSprite2D:
		var sprite := node as AnimatedSprite2D
		return {
			"status": "ok",
			"node": node_path,
			"type": "AnimatedSprite2D",
			"animation": sprite.animation,
			"frame": sprite.frame,
			"is_playing": sprite.is_playing(),
		}
	return {"error": "Not an animation node"}
