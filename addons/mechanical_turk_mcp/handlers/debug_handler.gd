@tool
extends Node
## Handles debug queries — runtime errors, logs, class info, script source.

var _errors: Array = []
var _warnings: Array = []
var _log_lines: Array = []
var _max_log: int = 500

func _ready() -> void:
	# We can't intercept push_error directly, but we can provide what's available
	pass

func handle_get_runtime_errors(params) -> Dictionary:
	# Return errors captured via custom hook or print output
	var limit: int = 50
	if params is Dictionary:
		limit = int(params.get("limit", 50))
	return {
		"status": "ok",
		"errors": _errors.slice(max(0, _errors.size() - limit)),
		"warnings": _warnings.slice(max(0, _warnings.size() - limit)),
		"error_count": _errors.size(),
		"warning_count": _warnings.size(),
	}

func handle_get_runtime_log(params) -> Dictionary:
	var lines: int = 100
	if params is Dictionary:
		lines = int(params.get("lines", 100))
	# Try to read godot log file
	var log_path := OS.get_user_data_dir() + "/logs/godot.log"
	var content: Array = []
	var f := FileAccess.open(log_path, FileAccess.READ)
	if f:
		var all_text := f.get_as_text()
		f.close()
		var all_lines := all_text.split("\n")
		var start := max(0, all_lines.size() - lines)
		content = Array(all_lines).slice(start)
	return {
		"status": "ok",
		"log_path": log_path,
		"lines": content,
		"line_count": content.size(),
	}

func handle_get_class_info(params) -> Dictionary:
	if not params is Dictionary:
		return {"error": "Invalid params"}
	var class_name_str: String = params.get("class_name", "")
	if class_name_str.is_empty():
		return {"error": "class_name is required"}
	if not ClassDB.class_exists(class_name_str):
		return {"error": "Class not found: %s" % class_name_str}

	var properties: Array = []
	for prop in ClassDB.class_get_property_list(class_name_str, true):
		properties.append({"name": prop.get("name", ""), "type": prop.get("type", 0), "hint": prop.get("hint", 0)})

	var methods: Array = []
	for method in ClassDB.class_get_method_list(class_name_str, true):
		var args_arr: Array = []
		for arg in method.get("args", []):
			args_arr.append({"name": arg.get("name", ""), "type": arg.get("type", 0)})
		methods.append({"name": method.get("name", ""), "args": args_arr})

	var signals_arr: Array = []
	for sig in ClassDB.class_get_signal_list(class_name_str, true):
		signals_arr.append({"name": sig.get("name", "")})

	return {
		"status": "ok",
		"class_name": class_name_str,
		"parent_class": ClassDB.get_parent_class(class_name_str),
		"properties": properties,
		"methods": methods,
		"signals": signals_arr,
		"property_count": properties.size(),
		"method_count": methods.size(),
		"signal_count": signals_arr.size(),
	}

func handle_get_script_source(params) -> Dictionary:
	if not params is Dictionary:
		return {"error": "Invalid params"}
	var node_path: String = params.get("node_path", "")
	if node_path.is_empty():
		return {"error": "node_path is required"}
	var tree := get_tree()
	if tree == null:
		return {"error": "No scene tree"}
	var node := tree.root.get_node_or_null(node_path.trim_prefix("/root"))
	if node_path == "/root":
		node = tree.root
	if node == null:
		return {"error": "Node not found: %s" % node_path}
	var script = node.get_script()
	if script == null:
		return {"error": "Node has no script attached"}
	return {
		"status": "ok",
		"node": node_path,
		"script_path": script.resource_path,
		"source_code": script.source_code,
	}
