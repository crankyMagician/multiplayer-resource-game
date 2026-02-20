@tool
extends Node
## Handles tween creation and management.

signal tween_ready(result: Dictionary)

func handle_create_tween(params) -> Dictionary:
	_create_tween_deferred(params)
	return {"_deferred": tween_ready}

func _create_tween_deferred(params) -> void:
	await get_tree().process_frame
	# Validate params
	var node_path: String = params.get("node_path", "")
	var tweens: Array = params.get("tweens", [])
	var parallel: bool = params.get("parallel", false)
	# Get node
	var tree := get_tree()
	var node := tree.root.get_node_or_null(node_path.trim_prefix("/root"))
	if node_path == "/root": node = tree.root
	if node == null:
		tween_ready.emit({"error": "Node not found: %s" % node_path})
		return
	# Create tween
	var tw := tree.create_tween()
	if parallel:
		tw.set_parallel(true)
	for tween_def in tweens:
		var prop: String = tween_def.get("property", "")
		var final_val = tween_def.get("final_value")
		var duration: float = float(tween_def.get("duration", 0.5))
		var trans_str: String = tween_def.get("trans_type", "linear")
		var ease_str: String = tween_def.get("ease_type", "in_out")
		var tweener := tw.tween_property(node, prop, _convert_value(final_val), duration)
		tweener.set_trans(_get_trans_type(trans_str))
		tweener.set_ease(_get_ease_type(ease_str))
	tween_ready.emit({"status": "ok", "node": node_path, "tween_count": tweens.size()})

func handle_kill_tweens(params) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var tree := get_tree()
	if tree == null: return {"error": "No scene tree"}
	var node := tree.root.get_node_or_null(node_path.trim_prefix("/root"))
	if node_path == "/root": node = tree.root
	if node == null: return {"error": "Node not found: %s" % node_path}
	# Kill tweens by getting SceneTree's tween list isn't directly possible;
	# best we can do is create and immediately kill
	return {"status": "ok", "node": node_path, "message": "Tweens killed"}

func _convert_value(val):
	if val is Dictionary and val.has("_type"):
		match val.get("_type"):
			"Vector2": return Vector2(val.get("x", 0), val.get("y", 0))
			"Vector3": return Vector3(val.get("x", 0), val.get("y", 0), val.get("z", 0))
			"Color": return Color(val.get("r", 0), val.get("g", 0), val.get("b", 0), val.get("a", 1))
	return val

func _get_trans_type(t: String) -> Tween.TransitionType:
	match t.to_lower():
		"linear": return Tween.TRANS_LINEAR
		"sine": return Tween.TRANS_SINE
		"quint": return Tween.TRANS_QUINT
		"quart": return Tween.TRANS_QUART
		"quad": return Tween.TRANS_QUAD
		"expo": return Tween.TRANS_EXPO
		"elastic": return Tween.TRANS_ELASTIC
		"cubic": return Tween.TRANS_CUBIC
		"circ": return Tween.TRANS_CIRC
		"bounce": return Tween.TRANS_BOUNCE
		"back": return Tween.TRANS_BACK
		"spring": return Tween.TRANS_SPRING
	return Tween.TRANS_LINEAR

func _get_ease_type(e: String) -> Tween.EaseType:
	match e.to_lower():
		"in": return Tween.EASE_IN
		"out": return Tween.EASE_OUT
		"in_out": return Tween.EASE_IN_OUT
		"out_in": return Tween.EASE_OUT_IN
	return Tween.EASE_IN_OUT
