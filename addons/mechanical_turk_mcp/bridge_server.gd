@tool
extends Node
## WebSocket bridge server for MCP communication.
## Listens on port 9080 and dispatches JSON-RPC requests to handlers.

var port: int = 9080
var auth_token: String = ""
var bridge_mode: String = "editor"

var _tcp_server: TCPServer = null
var _peers: Array[WebSocketPeer] = []
var _handlers: Dictionary = {}

# Handler instances
var _screenshot_handler: Node = null
var _input_handler: Node = null
var _scene_tree_handler: Node = null
var _level_handler: Node = null
var _multiplayer_handler: Node = null
var _game_state_handler: Node = null
var _gdscript_exec_handler: Node = null
var _level_eval_handler: Node = null
var _gameplay_handler: Node = null
var _audio_handler: Node = null
var _signal_handler: Node = null
var _juice_handler: Node = null
var _ui_theme_handler: Node = null
var _postfx_handler: Node = null


func _ready() -> void:
	_screenshot_handler = preload("res://addons/mechanical_turk_mcp/handlers/screenshot_handler.gd").new()
	_input_handler = preload("res://addons/mechanical_turk_mcp/handlers/input_handler.gd").new()
	_scene_tree_handler = preload("res://addons/mechanical_turk_mcp/handlers/scene_tree_handler.gd").new()
	_level_handler = preload("res://addons/mechanical_turk_mcp/handlers/level_handler.gd").new()
	_multiplayer_handler = preload("res://addons/mechanical_turk_mcp/handlers/multiplayer_handler.gd").new()
	_game_state_handler = preload("res://addons/mechanical_turk_mcp/handlers/game_state_handler.gd").new()
	_gdscript_exec_handler = preload("res://addons/mechanical_turk_mcp/handlers/gdscript_exec_handler.gd").new()
	_level_eval_handler = preload("res://addons/mechanical_turk_mcp/handlers/level_eval_handler.gd").new()
	_gameplay_handler = preload("res://addons/mechanical_turk_mcp/handlers/gameplay_handler.gd").new()
	_audio_handler = preload("res://addons/mechanical_turk_mcp/handlers/audio_handler.gd").new()
	_signal_handler = preload("res://addons/mechanical_turk_mcp/handlers/signal_handler.gd").new()
	_juice_handler = preload("res://addons/mechanical_turk_mcp/handlers/juice_handler.gd").new()
	_ui_theme_handler = preload("res://addons/mechanical_turk_mcp/handlers/ui_theme_handler.gd").new()
	_postfx_handler = preload("res://addons/mechanical_turk_mcp/handlers/postfx_handler.gd").new()
	add_child(_screenshot_handler)
	add_child(_input_handler)
	add_child(_scene_tree_handler)
	add_child(_level_handler)
	add_child(_multiplayer_handler)
	add_child(_game_state_handler)
	add_child(_gdscript_exec_handler)
	add_child(_level_eval_handler)
	add_child(_gameplay_handler)
	add_child(_audio_handler)
	add_child(_signal_handler)
	add_child(_juice_handler)
	add_child(_ui_theme_handler)
	add_child(_postfx_handler)

	# Register method handlers — existing
	_handlers["ping"] = _handle_ping
	_handlers["capture_screenshot"] = _screenshot_handler.handle
	_handlers["send_input_event"] = _input_handler.handle_input_event
	_handlers["send_action"] = _input_handler.handle_action
	_handlers["get_scene_tree"] = _scene_tree_handler.handle_get_tree
	_handlers["get_node_properties"] = _scene_tree_handler.handle_get_properties
	_handlers["set_node_property"] = _level_handler.handle_set_property
	_handlers["delete_node"] = _level_handler.handle_delete_node
	_handlers["set_tiles"] = _level_handler.handle_set_tiles
	_handlers["reparent_node"] = _level_handler.handle_reparent_node
	_handlers["spawn_node"] = _level_handler.handle_spawn_node
	_handlers["create_shader"] = _level_handler.handle_create_shader
	_handlers["create_particles"] = _level_handler.handle_create_particles
	_handlers["create_ui_node"] = _level_handler.handle_create_ui_node
	_handlers["raycast_3d"] = _level_handler.handle_raycast_3d
	_handlers["capture_performance_snapshot"] = _level_handler.handle_capture_performance_snapshot

	# Multiplayer handlers
	_handlers["multiplayer_get_runtime_capabilities"] = _multiplayer_handler.handle_get_runtime_capabilities
	_handlers["multiplayer_transport_create"] = _multiplayer_handler.handle_transport_create
	_handlers["multiplayer_transport_close"] = _multiplayer_handler.handle_transport_close
	_handlers["multiplayer_peer_assign_to_tree"] = _multiplayer_handler.handle_peer_assign_to_tree
	_handlers["multiplayer_authority_set"] = _multiplayer_handler.handle_authority_set
	_handlers["multiplayer_authority_get"] = _multiplayer_handler.handle_authority_get
	_handlers["multiplayer_rpc_configure"] = _multiplayer_handler.handle_rpc_configure
	_handlers["multiplayer_rpc_invoke"] = _multiplayer_handler.handle_rpc_invoke
	_handlers["multiplayer_replication_spawner_configure"] = _multiplayer_handler.handle_replication_spawner_configure
	_handlers["multiplayer_replication_sync_configure"] = _multiplayer_handler.handle_replication_sync_configure
	_handlers["multiplayer_session_auth_configure"] = _multiplayer_handler.handle_session_auth_configure
	_handlers["multiplayer_session_send_auth"] = _multiplayer_handler.handle_session_send_auth
	_handlers["multiplayer_session_complete_auth"] = _multiplayer_handler.handle_session_complete_auth
	_handlers["multiplayer_telemetry_snapshot"] = _multiplayer_handler.handle_telemetry_snapshot
	_handlers["multiplayer_poll_events"] = _multiplayer_handler.handle_poll_events

	# New handlers — game state, GDScript exec, level eval, gameplay, audio, signals
	_handlers["get_game_state"] = _game_state_handler.handle_get_game_state
	_handlers["toggle_debug_visuals"] = _game_state_handler.handle_toggle_debug_visuals
	_handlers["execute_gdscript"] = _gdscript_exec_handler.handle_execute
	_handlers["evaluate_level"] = _level_eval_handler.handle_evaluate
	_handlers["play_sequence"] = _gameplay_handler.handle_play_sequence
	_handlers["save_game_state"] = _gameplay_handler.handle_save_state
	_handlers["restore_game_state"] = _gameplay_handler.handle_restore_state
	_handlers["simulate_playthrough"] = _gameplay_handler.handle_simulate_playthrough
	_handlers["play_audio"] = _audio_handler.handle_play_audio
	_handlers["stop_audio"] = _audio_handler.handle_stop_audio
	_handlers["subscribe_signal"] = _signal_handler.handle_subscribe_signal
	_handlers["poll_signal_events"] = _signal_handler.handle_poll_events
	_handlers["list_signals"] = _signal_handler.handle_list_signals
	_handlers["emit_signal_on_node"] = _signal_handler.handle_emit_signal

	# Juice handlers
	_handlers["juice_punch_scale"] = _juice_handler.handle_punch_scale
	_handlers["juice_screen_shake"] = _juice_handler.handle_screen_shake
	_handlers["juice_hit_stop"] = _juice_handler.handle_hit_stop
	_handlers["juice_hit_flash"] = _juice_handler.handle_hit_flash
	_handlers["juice_ui_pop"] = _juice_handler.handle_ui_pop

	# UI theme + layout handlers
	_handlers["ui_apply_theme"] = _ui_theme_handler.handle_apply_theme
	_handlers["ui_configure_layout"] = _ui_theme_handler.handle_configure_layout
	_handlers["ui_configure_navigation"] = _ui_theme_handler.handle_configure_navigation
	_handlers["ui_add_transition"] = _ui_theme_handler.handle_add_transition
	_handlers["ui_grab_focus"] = _ui_theme_handler.handle_grab_focus

	# Shader live parameter handler
	_handlers["set_shader_parameter_live"] = _level_handler.handle_set_shader_parameter_live

	# Post-processing handlers
	_handlers["postfx_2d_apply"] = _postfx_handler.handle_postfx_2d_apply
	_handlers["postfx_2d_remove"] = _postfx_handler.handle_postfx_2d_remove
	_handlers["set_environment_property_live"] = _postfx_handler.handle_set_environment_property

	_start_server()


func _start_server() -> void:
	_tcp_server = TCPServer.new()
	var err := _tcp_server.listen(port)
	if err != OK:
		push_error("[MCP Bridge] Failed to listen on port %d: %s" % [port, error_string(err)])
		return
	print("[MCP Bridge] Server listening on port %d (%s mode)" % [port, bridge_mode])


func stop_server() -> void:
	for peer in _peers:
		peer.close()
	_peers.clear()
	if _tcp_server:
		_tcp_server.stop()
		_tcp_server = null
	print("[MCP Bridge] Server stopped")


func _process(_delta: float) -> void:
	if not _tcp_server:
		return

	# Accept new TCP connections and upgrade to WebSocket
	while _tcp_server.is_connection_available():
		var tcp_conn := _tcp_server.take_connection()
		if tcp_conn:
			var ws_peer := WebSocketPeer.new()
			var err := ws_peer.accept_stream(tcp_conn)
			if err == OK:
				_peers.append(ws_peer)
				print("[MCP Bridge] Client connected")
			else:
				push_error("[MCP Bridge] Failed to accept WebSocket: %s" % error_string(err))

	# Poll all peers
	var to_remove: Array[int] = []
	for i in range(_peers.size()):
		var peer := _peers[i]
		peer.poll()

		match peer.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				while peer.get_available_packet_count() > 0:
					var data := peer.get_packet().get_string_from_utf8()
					_handle_message(peer, data)
			WebSocketPeer.STATE_CLOSING:
				pass  # Wait for close to complete
			WebSocketPeer.STATE_CLOSED:
				to_remove.append(i)
				print("[MCP Bridge] Client disconnected (code: %d)" % peer.get_close_code())

	# Remove disconnected peers (reverse order to preserve indices)
	for i in range(to_remove.size() - 1, -1, -1):
		_peers.remove_at(to_remove[i])


func _handle_message(peer: WebSocketPeer, data: String) -> void:
	var json := JSON.new()
	var err := json.parse(data)
	if err != OK:
		_send_error(peer, "0", -32700, "Parse error: %s" % json.get_error_message())
		return

	var msg = json.get_data()
	if typeof(msg) != TYPE_DICTIONARY:
		_send_error(peer, "0", -32600, "Invalid request: expected object")
		return

	var id: String = str(msg.get("id", "0"))
	var method: String = msg.get("method", "")
	var params = msg.get("params", {})

	# Auth check (skipped when auth_token is empty)
	if not auth_token.is_empty():
		var request_token: String = str(msg.get("auth", ""))
		if request_token != auth_token:
			_send_error(peer, id, -32603, "Authentication failed")
			return

	if method.is_empty():
		_send_error(peer, id, -32600, "Missing method")
		return

	if not _handlers.has(method):
		_send_error(peer, id, -32601, "Method not found: %s" % method)
		return

	# Call the handler
	var handler: Callable = _handlers[method]
	var result = handler.call(params)

	# Handle deferred (async) results
	if result is Dictionary and result.has("_deferred"):
		# The handler returns a signal; we'll wait for it
		var deferred_signal: Signal = result["_deferred"]
		var deferred_result = await deferred_signal
		_send_result(peer, id, deferred_result)
	else:
		_send_result(peer, id, result)


func _send_result(peer: WebSocketPeer, id: String, result) -> void:
	var response := {
		"id": id,
		"result": result
	}
	peer.send_text(JSON.stringify(response))


func _send_error(peer: WebSocketPeer, id: String, code: int, message: String) -> void:
	var response := {
		"id": id,
		"error": {
			"code": code,
			"message": message
		}
	}
	peer.send_text(JSON.stringify(response))


func _handle_ping(_params) -> Dictionary:
	return {
		"status": "ok",
		"server": "mechanical-turk-mcp",
		"version": "0.2.0",
		"mode": bridge_mode
	}
