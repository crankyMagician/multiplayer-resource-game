extends Node
## Runtime bridge autoload — runs the MCP bridge inside a standalone game process.
## Add this as an autoload singleton (Project > Project Settings > Autoload).
## Listens on port 9081 (or MECHTURK_RUNTIME_BRIDGE_PORT env var).
## Optional bearer token auth via MECHTURK_RUNTIME_BRIDGE_TOKEN env var.

var _bridge: Node = null


func _ready() -> void:
	# Don't run in the editor — the editor bridge (plugin.gd) handles that on port 9080
	if Engine.is_editor_hint():
		return

	_bridge = preload("res://addons/mechanical_turk_mcp/bridge_server.gd").new()

	# Configure port
	var port_env := OS.get_environment("MECHTURK_RUNTIME_BRIDGE_PORT")
	if not port_env.is_empty() and port_env.is_valid_int():
		_bridge.port = int(port_env)
	else:
		_bridge.port = 9081

	# Configure auth token
	var token_env := OS.get_environment("MECHTURK_RUNTIME_BRIDGE_TOKEN")
	if not token_env.is_empty():
		_bridge.auth_token = token_env

	_bridge.bridge_mode = "runtime"

	add_child(_bridge)


func _exit_tree() -> void:
	if _bridge and is_instance_valid(_bridge):
		_bridge.stop_server()
		_bridge.queue_free()
		_bridge = null
