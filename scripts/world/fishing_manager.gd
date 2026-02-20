extends Node

# Server-authoritative fishing manager. No class_name — child of GameWorld.

var active_sessions: Dictionary = {}  # peer_id -> session dict
var _cast_cooldowns: Dictionary = {}  # peer_id -> Time.get_ticks_msec()

const CAST_COOLDOWN_MS: int = 2000
const MIN_BITE_DELAY: float = 2.0
const MAX_BITE_DELAY: float = 7.0
const MAX_INPUT_LOG_SIZE: int = 1200  # 20s * 60fps
const MINIGAME_TIMEOUT: float = 25.0
const CAST_ANIM_DURATION: float = 0.8

const TIME_LIMITS: Dictionary = {
	1: 20.0,
	2: 18.0,
	3: 15.0,
	4: 13.0,
	5: 10.0,
}


func _ready() -> void:
	if not multiplayer.is_server():
		set_physics_process(false)


func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	var now: float = Time.get_unix_time_from_system()
	var to_remove: Array = []
	for peer_id in active_sessions:
		var session: Dictionary = active_sessions[peer_id]
		var state: String = session.get("state", "")
		match state:
			"casting":
				if now - session["started_at"] >= CAST_ANIM_DURATION:
					# Transition to waiting — set persistent fishing animation
					session["state"] = "waiting"
					var player_node = _get_player_node(peer_id)
					if player_node:
						player_node.anim_action = &"fish_idle"
			"waiting":
				if now >= session["bite_time"]:
					# Fish bites! Transition to hook window (not directly to minigame)
					session["state"] = "hook_window"
					var difficulty: int = session.get("difficulty", 1)
					session["hook_window_expire"] = now + lerpf(3.0, 1.5, float(difficulty - 1) / 4.0)
					var player_node = _get_player_node(peer_id)
					if player_node:
						player_node.anim_action = &"fish_hook"
					_fishing_hook_alert_client.rpc_id(peer_id)
			"hook_window":
				if now >= session.get("hook_window_expire", now):
					# Player didn't react in time — fish escapes
					_end_fishing(peer_id, false)
					to_remove.append(peer_id)
			"minigame":
				if now - session.get("minigame_started_at", now) > MINIGAME_TIMEOUT:
					# Timed out
					_end_fishing(peer_id, false)
					to_remove.append(peer_id)
	for peer_id in to_remove:
		active_sessions.erase(peer_id)


# === Client → Server RPCs ===

@rpc("any_peer", "reliable")
func request_cast_line(fishing_table_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	print("[Fishing Server] request_cast_line from peer=", peer_id, " table=", fishing_table_id)
	if peer_id not in NetworkManager.player_data_store:
		print("[Fishing Server] REJECTED: peer not in player_data_store")
		return

	# Validate: not busy
	var player_node = _get_player_node(peer_id)
	if player_node == null:
		print("[Fishing Server] REJECTED: player_node is null")
		return
	if player_node.is_busy:
		print("[Fishing Server] REJECTED: player is busy (is_busy=true)")
		return

	# Validate: no active session
	if peer_id in active_sessions:
		print("[Fishing Server] REJECTED: already has active session")
		return

	# Validate: cooldown
	var now_ms: int = Time.get_ticks_msec()
	if peer_id in _cast_cooldowns and now_ms - _cast_cooldowns[peer_id] < CAST_COOLDOWN_MS:
		print("[Fishing Server] REJECTED: cooldown (elapsed=", now_ms - _cast_cooldowns[peer_id], "ms)")
		return

	# Validate: has fishing rod equipped
	var data: Dictionary = NetworkManager.player_data_store[peer_id]
	var equipped_tools: Dictionary = data.get("equipped_tools", {})
	var rod_id: String = equipped_tools.get("fishing_rod", "")
	print("[Fishing Server] equipped_tools=", equipped_tools, " rod_id=", rod_id)
	if rod_id == "":
		print("[Fishing Server] REJECTED: no fishing rod equipped (equipped_tools=", equipped_tools, ")")
		return

	# Validate: fishing table exists
	var table = DataRegistry.get_fishing_table(fishing_table_id)
	if table == null:
		print("[Fishing Server] REJECTED: fishing table '", fishing_table_id, "' not found in DataRegistry")
		return

	# Validate: near a fishing spot
	if not _is_near_fishing_spot(player_node):
		print("[Fishing Server] REJECTED: not near fishing spot (pos=", player_node.global_position, ")")
		return

	# Get rod tier
	var rod_def = DataRegistry.get_tool(rod_id)
	var rod_tier: int = rod_def.tier if rod_def else 0

	# Roll fish
	var fish_entry: Dictionary = _roll_fish(fishing_table_id, rod_tier, peer_id)
	if fish_entry.is_empty():
		print("[Fishing Server] REJECTED: _roll_fish returned empty (table=", fishing_table_id, " rod_tier=", rod_tier, ")")
		return

	# Calculate bar size
	var bar_size: float = _calculate_bar_size(peer_id, rod_id)

	# Calculate time limit
	var difficulty: int = fish_entry.get("difficulty", 1)
	var time_limit: float = TIME_LIMITS.get(difficulty, 15.0)

	# Roll bite delay
	var bite_delay: float = randf_range(MIN_BITE_DELAY, MAX_BITE_DELAY)

	# Generate seed for deterministic minigame
	var seed_val: int = randi()

	# Get fish display name
	var fish_id: String = fish_entry.get("fish_id", "")
	var fish_def = DataRegistry.get_ingredient(fish_id)
	var fish_display_name: String = fish_def.display_name if fish_def else fish_id.capitalize()

	# Set busy + start session
	_set_player_busy(peer_id, true)

	# Play cast animation
	if player_node:
		player_node.play_tool_action(&"fish")

	_cast_cooldowns[peer_id] = now_ms
	var now: float = Time.get_unix_time_from_system()

	active_sessions[peer_id] = {
		"fish_id": fish_id,
		"fish_display_name": fish_display_name,
		"difficulty": difficulty,
		"movement_type": str(fish_entry.get("movement_type", "smooth")),
		"seed": seed_val,
		"bar_size": bar_size,
		"time_limit": time_limit,
		"state": "casting",
		"started_at": now,
		"bite_time": now + CAST_ANIM_DURATION + bite_delay,
	}

	# Tell client cast started
	print("[Fishing Server] All checks passed! Starting session for peer=", peer_id, " fish=", fish_id, " difficulty=", difficulty)
	_fishing_cast_client.rpc_id(peer_id)


@rpc("any_peer", "reliable")
func request_reel_result(input_log: PackedFloat32Array, claimed_success: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if peer_id not in active_sessions:
		return

	var session: Dictionary = active_sessions[peer_id]
	if session.get("state", "") != "minigame":
		return

	# Validate input log size
	if input_log.size() > MAX_INPUT_LOG_SIZE:
		_end_fishing(peer_id, false)
		active_sessions.erase(peer_id)
		return

	# Replay minigame deterministically
	var result: Dictionary = FishingMinigame.simulate(
		session["seed"],
		session["difficulty"],
		session["movement_type"],
		session["bar_size"],
		session["time_limit"],
		input_log
	)

	var server_success: bool = result.get("success", false)
	var is_perfect: bool = result.get("perfect", false)

	# Verify client claim matches server replay
	if claimed_success != server_success:
		# Mismatch — use server result (anti-cheat)
		print("[FishingManager] Client claim mismatch for peer ", peer_id,
			" — claimed=", claimed_success, " server=", server_success)

	if server_success:
		_grant_catch(peer_id, session, is_perfect)

	_end_fishing(peer_id, server_success, is_perfect)
	active_sessions.erase(peer_id)


@rpc("any_peer", "reliable")
func request_hook_fish() -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if peer_id not in active_sessions:
		return
	var session: Dictionary = active_sessions[peer_id]
	if session.get("state", "") != "hook_window":
		return

	# Player reacted in time! Transition to minigame
	session["state"] = "minigame"
	session["minigame_started_at"] = Time.get_unix_time_from_system()
	var player_node = _get_player_node(peer_id)
	if player_node:
		player_node.anim_action = &"fish_idle"
	_fishing_bite_client.rpc_id(peer_id,
		session["seed"],
		session["difficulty"],
		session["movement_type"],
		session["time_limit"],
		session["bar_size"],
		session["fish_display_name"])


@rpc("any_peer", "reliable")
func request_cancel_fishing() -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if peer_id not in active_sessions:
		return
	_end_fishing(peer_id, false)
	active_sessions.erase(peer_id)


# === Server → Client RPCs ===

@rpc("authority", "reliable")
func _fishing_cast_client() -> void:
	print("[Fishing Client] _fishing_cast_client received!")
	# Client: show "waiting for bite" hint
	var fishing_ui = get_node_or_null("/root/Main/GameWorld/UI/FishingUI")
	print("[Fishing Client] FishingUI=", fishing_ui)
	if fishing_ui:
		fishing_ui.show_casting()
	else:
		print("[Fishing Client] FAILED: FishingUI not found at /root/Main/GameWorld/UI/FishingUI")


@rpc("authority", "reliable")
func _fishing_hook_alert_client() -> void:
	# Client: show hook window alert ("! HOOK IT !")
	var fishing_ui = get_node_or_null("/root/Main/GameWorld/UI/FishingUI")
	if fishing_ui:
		fishing_ui.show_hook_alert()


@rpc("authority", "reliable")
func _fishing_bite_client(seed_val: int, difficulty: int, movement_type: String,
		time_limit: float, bar_size: float, fish_display_name: String) -> void:
	# Client: start minigame
	var fishing_ui = get_node_or_null("/root/Main/GameWorld/UI/FishingUI")
	if fishing_ui:
		fishing_ui.start_minigame(seed_val, difficulty, movement_type, time_limit, bar_size, fish_display_name)


@rpc("authority", "reliable")
func _fishing_complete_client(success: bool, fish_id: String,
		fish_display_name: String, sell_value: int,
		difficulty: int, is_perfect: bool, is_new_species: bool = false) -> void:
	# Client: show result
	var fishing_ui = get_node_or_null("/root/Main/GameWorld/UI/FishingUI")
	if fishing_ui:
		fishing_ui.show_result(success, fish_id, fish_display_name, sell_value, difficulty, is_perfect, is_new_species)


@rpc("authority", "reliable")
func _fishing_cancelled_client() -> void:
	var fishing_ui = get_node_or_null("/root/Main/GameWorld/UI/FishingUI")
	if fishing_ui:
		fishing_ui.close()


@rpc("authority", "reliable")
func _sync_fishing_log(fishing_log: Dictionary) -> void:
	PlayerData.fishing_log = fishing_log
	PlayerData.fishing_log_changed.emit()


@rpc("any_peer", "reliable")
func request_fishing_log_sync() -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if peer_id not in NetworkManager.player_data_store:
		return
	var data: Dictionary = NetworkManager.player_data_store[peer_id]
	var fishing_log: Dictionary = data.get("fishing_log", {})
	_sync_fishing_log.rpc_id(peer_id, fishing_log)


# === Internal Helpers ===

func _end_fishing(peer_id: int, success: bool, is_perfect: bool = false) -> void:
	var session: Dictionary = active_sessions.get(peer_id, {})
	var fish_id: String = session.get("fish_id", "")
	var fish_display_name: String = session.get("fish_display_name", "")
	var difficulty: int = session.get("difficulty", 1)
	var is_new_species: bool = session.get("is_new_species", false)

	# Clear animation
	var player_node = _get_player_node(peer_id)
	if player_node:
		player_node.anim_action = &""

	# Clear busy
	_set_player_busy(peer_id, false)

	# Get sell value for display
	var sell_value: int = 0
	if success and fish_id != "":
		sell_value = DataRegistry.get_sell_price(fish_id)

	# Notify client
	if success:
		_fishing_complete_client.rpc_id(peer_id, true, fish_id, fish_display_name,
			sell_value, difficulty, is_perfect, is_new_species)
	else:
		var state: String = session.get("state", "")
		if state == "minigame" or state == "hook_window":
			_fishing_complete_client.rpc_id(peer_id, false, fish_id, fish_display_name,
				0, difficulty, false, false)
		else:
			_fishing_cancelled_client.rpc_id(peer_id)


func _grant_catch(peer_id: int, session: Dictionary, is_perfect: bool = false) -> void:
	var fish_id: String = session.get("fish_id", "")
	if fish_id == "":
		return

	# Check if this is a new species (before adding to compendium)
	var data: Dictionary = NetworkManager.player_data_store[peer_id]
	var fishing_log: Dictionary = data.get("fishing_log", {})
	var catches: Dictionary = fishing_log.get("catches", {})
	var is_new_species: bool = fish_id not in catches

	# Update fishing log
	var season_mgr = get_node_or_null("/root/Main/GameWorld/SeasonManager")
	var current_day: int = 0
	if season_mgr and "total_days" in season_mgr:
		current_day = season_mgr.total_days

	if fish_id in catches:
		catches[fish_id]["count"] = catches[fish_id].get("count", 0) + 1
		if is_perfect:
			catches[fish_id]["perfect_count"] = catches[fish_id].get("perfect_count", 0) + 1
	else:
		catches[fish_id] = {
			"count": 1,
			"perfect_count": 1 if is_perfect else 0,
			"first_caught_day": current_day,
		}
	fishing_log["catches"] = catches
	data["fishing_log"] = fishing_log

	# Store new species flag in session for _end_fishing to read
	session["is_new_species"] = is_new_species

	# Add fish to inventory
	NetworkManager.server_add_inventory(peer_id, fish_id, 1)

	# Sync inventory to client
	var inv: Dictionary = data.get("inventory", {})
	NetworkManager._sync_inventory_full.rpc_id(peer_id, inv)

	# Sync fishing log to client
	_sync_fishing_log.rpc_id(peer_id, fishing_log)

	# Track stats
	StatTracker.increment(peer_id, "fish_caught")
	StatTracker.increment(peer_id, "fishing_skill")

	# Perfect catch bonus: +1 extra fishing_skill
	if is_perfect:
		StatTracker.increment(peer_id, "fishing_skill")
		StatTracker.increment(peer_id, "perfect_catches")


func _roll_fish(table_id: String, rod_tier: int, _peer_id: int) -> Dictionary:
	var table = DataRegistry.get_fishing_table(table_id)
	if table == null:
		return {}

	var season: String = _get_current_season()
	var weather: String = _get_current_weather()
	var valid_entries: Array = []

	for entry in table.entries:
		if entry.get("min_rod_tier", 0) > rod_tier:
			continue
		var fish_season: String = entry.get("season", "")
		if fish_season != "" and fish_season != season:
			continue
		var w: int = entry.get("weight", 10)
		# Weather bonus
		if table.weather_bonus.get(weather, "") == entry.get("fish_id", ""):
			w = int(w * 1.5)
		valid_entries.append({"entry": entry, "weight": w})

	if valid_entries.is_empty():
		return {}

	return _weighted_pick(valid_entries)


func _weighted_pick(entries: Array) -> Dictionary:
	var total_weight: int = 0
	for e in entries:
		total_weight += e.get("weight", 0)
	if total_weight <= 0:
		return {}

	var roll: int = randi() % total_weight
	var cumulative: int = 0
	for e in entries:
		cumulative += e.get("weight", 0)
		if roll < cumulative:
			return e.get("entry", {})
	return entries.back().get("entry", {})


func _calculate_bar_size(peer_id: int, rod_id: String) -> float:
	var stats: Dictionary = NetworkManager.player_data_store[peer_id].get("stats", {})
	var fishing_skill: int = stats.get("fishing_skill", 0)
	var rod_def = DataRegistry.get_tool(rod_id)
	var rod_bonus: float = rod_def.effectiveness.get("bar_bonus", 0.0) if rod_def else 0.0
	return clampf(0.25 + fishing_skill * 0.005 + rod_bonus, 0.2, 0.5)


func _get_current_season() -> String:
	var season_mgr = get_node_or_null("/root/Main/GameWorld/SeasonManager")
	if season_mgr and "current_month" in season_mgr:
		var month: int = season_mgr.current_month
		if month >= 3 and month <= 5:
			return "spring"
		elif month >= 6 and month <= 8:
			return "summer"
		elif month >= 9 and month <= 11:
			return "autumn"
		else:
			return "winter"
	return ""


func _get_current_weather() -> String:
	var season_mgr = get_node_or_null("/root/Main/GameWorld/SeasonManager")
	if season_mgr and "current_weather" in season_mgr:
		# Weather enum: 0=sunny, 1=rainy, 2=windy, 3=stormy
		match season_mgr.current_weather:
			1: return "rainy"
			2: return "windy"
			3: return "stormy"
	return "sunny"


func _is_near_fishing_spot(player_node: CharacterBody3D) -> bool:
	var pos: Vector3 = player_node.global_position
	var spots = get_tree().get_nodes_in_group("fishing_spot")
	for spot in spots:
		if spot is Node3D:
			if spot.global_position.distance_to(pos) < 5.0:
				return true
	return false


func _get_player_node(peer_id: int) -> CharacterBody3D:
	var players = get_node_or_null("/root/Main/GameWorld/Players")
	if players == null:
		return null
	var node = players.get_node_or_null(str(peer_id))
	if node is CharacterBody3D:
		return node
	return null


func _set_player_busy(peer_id: int, busy: bool) -> void:
	var player_node = _get_player_node(peer_id)
	if player_node:
		player_node.is_busy = busy


func handle_disconnect(peer_id: int) -> void:
	if peer_id in active_sessions:
		var player_node = _get_player_node(peer_id)
		if player_node:
			player_node.anim_action = &""
		_set_player_busy(peer_id, false)
		active_sessions.erase(peer_id)
