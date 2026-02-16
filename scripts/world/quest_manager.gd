extends Node

# Server-side quest manager. No class_name (follows SocialManager pattern).
# Handles quest acceptance, progress tracking, completion, and daily/weekly resets.

const MAX_ACTIVE_QUESTS: int = 10

func _ready() -> void:
	if not multiplayer.is_server():
		return
	_connect_season_manager.call_deferred()

func _connect_season_manager() -> void:
	var season_mgr = get_node_or_null("/root/Main/GameWorld/SeasonManager")
	if season_mgr and season_mgr.has_signal("day_changed"):
		season_mgr.day_changed.connect(_on_day_changed)

# === Quest State Helpers ===

static func _get_quest_data(peer_id: int) -> Dictionary:
	if peer_id not in NetworkManager.player_data_store:
		return {}
	return NetworkManager.player_data_store[peer_id].get("quests", {})

static func _ensure_quest_data(peer_id: int) -> Dictionary:
	if peer_id not in NetworkManager.player_data_store:
		return {}
	var pdata = NetworkManager.player_data_store[peer_id]
	if not pdata.has("quests"):
		pdata["quests"] = {"active": {}, "completed": {}, "daily_reset_day": 0, "weekly_reset_day": 0, "unlock_flags": []}
	return pdata["quests"]

# === Prerequisite Checking ===

func check_prereqs(peer_id: int, quest_def: Resource) -> bool:
	var qdata = _get_quest_data(peer_id)
	var completed = qdata.get("completed", {})
	var pdata = NetworkManager.player_data_store.get(peer_id, {})

	# Prerequisite quest IDs
	for req_id in quest_def.prereq_quest_ids:
		if req_id not in completed:
			return false

	# Main story prerequisite
	if quest_def.prereq_main_story_quest_id != "":
		if quest_def.prereq_main_story_quest_id not in completed:
			return false

	# Friendship prerequisites
	var friendships = pdata.get("npc_friendships", {})
	for npc_id in quest_def.prereq_friendship:
		var required = int(quest_def.prereq_friendship[npc_id])
		var fs = friendships.get(npc_id, {})
		if int(fs.get("points", 0)) < required:
			return false

	# Location prerequisites
	var discovered = pdata.get("discovered_locations", [])
	for loc_id in quest_def.prereq_locations:
		if loc_id not in discovered:
			return false

	# Season prerequisite
	if quest_def.prereq_season != "":
		var season_mgr = get_node_or_null("/root/Main/GameWorld/SeasonManager")
		if season_mgr:
			var current_season = season_mgr.get_current_season()
			if current_season != quest_def.prereq_season:
				return false

	# Weather prerequisite
	if quest_def.prereq_weather != "":
		var season_mgr = get_node_or_null("/root/Main/GameWorld/SeasonManager")
		if season_mgr:
			var current_weather = season_mgr.get_weather_name()
			if current_weather != quest_def.prereq_weather:
				return false

	return true

# === Available Quests ===

func get_available_quests(peer_id: int, npc_id: String) -> Array:
	DataRegistry.ensure_loaded()
	var qdata = _ensure_quest_data(peer_id)
	var active = qdata.get("active", {})
	var completed = qdata.get("completed", {})
	var available: Array = []

	for quest_id in DataRegistry.quests:
		var qdef = DataRegistry.quests[quest_id]
		if qdef.quest_giver_npc_id != npc_id:
			continue
		# Skip if already active
		if quest_id in active:
			continue
		# Skip if already completed (unless repeatable daily/weekly)
		if quest_id in completed:
			if qdef.category != "daily" and qdef.category != "weekly":
				continue
			# Daily/weekly: only available if reset has cleared it (handled by _on_day_changed)
			# If still in completed dict, it hasn't been reset yet
			continue
		# Check prerequisites
		if not check_prereqs(peer_id, qdef):
			continue
		available.append(quest_id)

	return available

# === Get Completable Quests ===

func get_completable_quests(peer_id: int, npc_id: String) -> Array:
	DataRegistry.ensure_loaded()
	var qdata = _ensure_quest_data(peer_id)
	var active = qdata.get("active", {})
	var completable: Array = []

	for quest_id in active:
		var qdef = DataRegistry.get_quest(quest_id)
		if qdef == null:
			continue
		if qdef.quest_giver_npc_id != npc_id:
			continue
		if _are_objectives_complete(peer_id, quest_id, qdef):
			completable.append(quest_id)

	return completable

# === Accept Quest ===

func handle_accept_quest(peer_id: int, quest_id: String) -> void:
	DataRegistry.ensure_loaded()
	var qdef = DataRegistry.get_quest(quest_id)
	if qdef == null:
		return
	var qdata = _ensure_quest_data(peer_id)
	var active = qdata.get("active", {})

	# Validation
	if quest_id in active:
		return
	if quest_id in qdata.get("completed", {}):
		if qdef.category != "daily" and qdef.category != "weekly":
			return
	if active.size() >= MAX_ACTIVE_QUESTS:
		return
	if not check_prereqs(peer_id, qdef):
		return

	# Create active entry
	var obj_progress: Array = []
	for _obj in qdef.objectives:
		obj_progress.append({"progress": 0})
	active[quest_id] = {
		"started_at": int(Time.get_unix_time_from_system()),
		"objectives": obj_progress,
	}

	# Sync to client
	_sync_quest_state.rpc_id(peer_id, qdata.get("active", {}), qdata.get("completed", {}), qdata.get("unlock_flags", []))

# === Notify Progress ===

func notify_progress(peer_id: int, objective_type: String, target_id: String, count: int = 1) -> void:
	var qdata = _get_quest_data(peer_id)
	if qdata.is_empty():
		return
	var active = qdata.get("active", {})
	if active.is_empty():
		return

	DataRegistry.ensure_loaded()
	var any_updated: bool = false

	for quest_id in active:
		var qdef = DataRegistry.get_quest(quest_id)
		if qdef == null:
			continue
		var quest_state = active[quest_id]
		var objectives = quest_state.get("objectives", [])

		for i in range(qdef.objectives.size()):
			var obj = qdef.objectives[i]
			var obj_type = str(obj.get("type", ""))

			# Skip delivery/inventory-check objectives — they're validated at turn-in
			if obj_type == "deliver":
				continue
			if obj_type == "collect" and obj.get("consumes_items", false):
				continue

			if obj_type != objective_type:
				continue

			# Check target match
			var obj_target = str(obj.get("target_id", ""))
			if obj_target != "" and obj_target != target_id:
				continue

			# Increment progress (capped)
			var target_count = int(obj.get("target_count", 1))
			if i < objectives.size():
				var current = int(objectives[i].get("progress", 0))
				var new_val = mini(current + count, target_count)
				if new_val != current:
					objectives[i]["progress"] = new_val
					any_updated = true
					_notify_quest_progress.rpc_id(peer_id, quest_id, i, new_val, target_count)

	if any_updated:
		# Also send full sync for reliability
		_sync_quest_state.rpc_id(peer_id, qdata.get("active", {}), qdata.get("completed", {}), qdata.get("unlock_flags", []))

# === Complete Quest ===

func handle_complete_quest(peer_id: int, quest_id: String) -> void:
	DataRegistry.ensure_loaded()
	var qdef = DataRegistry.get_quest(quest_id)
	if qdef == null:
		return
	var qdata = _ensure_quest_data(peer_id)
	var active = qdata.get("active", {})
	var completed = qdata.get("completed", {})

	if quest_id not in active:
		return
	if quest_id in completed:
		return

	# Validate all objectives complete
	if not _are_objectives_complete(peer_id, quest_id, qdef):
		return

	# Deduct delivery/collect-consume items
	for i in range(qdef.objectives.size()):
		var obj = qdef.objectives[i]
		var obj_type = str(obj.get("type", ""))
		var should_consume = false
		if obj_type == "deliver":
			should_consume = true
		elif obj_type == "collect" and obj.get("consumes_items", false):
			should_consume = true

		if should_consume:
			var item_id = str(obj.get("target_id", ""))
			var amount = int(obj.get("target_count", 1))
			if item_id != "":
				NetworkManager.server_remove_inventory(peer_id, item_id, amount)

	# Grant rewards
	var pdata = NetworkManager.player_data_store[peer_id]
	if qdef.reward_money > 0:
		NetworkManager.server_add_money(peer_id, qdef.reward_money)
	for item_id in qdef.reward_items:
		NetworkManager.server_add_inventory(peer_id, item_id, int(qdef.reward_items[item_id]))
	for npc_id in qdef.reward_friendship:
		var points = int(qdef.reward_friendship[npc_id])
		var friendships = pdata.get("npc_friendships", {})
		if npc_id not in friendships:
			friendships[npc_id] = {"points": 0, "talked_today": false, "gifted_today": false, "last_interaction_day": 0, "gifts_received": []}
			pdata["npc_friendships"] = friendships
		friendships[npc_id]["points"] = clampi(int(friendships[npc_id].get("points", 0)) + points, -100, 100)
	if qdef.reward_recipe_scroll_id != "":
		NetworkManager.server_add_inventory(peer_id, qdef.reward_recipe_scroll_id, 1)
	if qdef.reward_unlock_flag != "":
		var flags = qdata.get("unlock_flags", [])
		if qdef.reward_unlock_flag not in flags:
			flags.append(qdef.reward_unlock_flag)

	# Move to completed
	active.erase(quest_id)
	completed[quest_id] = int(Time.get_unix_time_from_system())

	# Sync inventory + money + quest state
	NetworkManager._sync_inventory_full.rpc_id(peer_id, pdata.get("inventory", {}))
	NetworkManager._sync_money.rpc_id(peer_id, int(pdata.get("money", 0)))
	if pdata.has("npc_friendships"):
		NetworkManager._sync_npc_friendships.rpc_id(peer_id, pdata["npc_friendships"])
	_sync_quest_state.rpc_id(peer_id, qdata.get("active", {}), qdata.get("completed", {}), qdata.get("unlock_flags", []))

	# Notify client of completion
	var rewards_info = {"money": qdef.reward_money, "items": qdef.reward_items}
	_notify_quest_complete.rpc_id(peer_id, quest_id, qdef.display_name, rewards_info)

	# Auto-offer next quest in chain
	if qdef.next_quest_id != "":
		var next_def = DataRegistry.get_quest(qdef.next_quest_id)
		if next_def and check_prereqs(peer_id, next_def):
			var next_data = {"quest_id": next_def.quest_id, "display_name": next_def.display_name, "description": next_def.description, "objectives": next_def.objectives, "reward_money": next_def.reward_money, "reward_items": next_def.reward_items}
			_offer_next_quest.rpc_id(peer_id, next_def.quest_id, next_def.quest_giver_npc_id, next_def.offer_dialogue, next_data)

	print("[QuestManager] ", peer_id, " completed quest: ", qdef.display_name)

# === Abandon Quest ===

func handle_abandon_quest(peer_id: int, quest_id: String) -> void:
	DataRegistry.ensure_loaded()
	var qdef = DataRegistry.get_quest(quest_id)
	if qdef == null:
		return
	# Cannot abandon main story quests
	if qdef.category == "main_story":
		return
	var qdata = _ensure_quest_data(peer_id)
	var active = qdata.get("active", {})
	if quest_id not in active:
		return
	active.erase(quest_id)
	_sync_quest_state.rpc_id(peer_id, qdata.get("active", {}), qdata.get("completed", {}), qdata.get("unlock_flags", []))

# === Objective Validation ===

func _are_objectives_complete(peer_id: int, quest_id: String, qdef: Resource) -> bool:
	var qdata = _get_quest_data(peer_id)
	var active = qdata.get("active", {})
	if quest_id not in active:
		return false
	var quest_state = active[quest_id]
	var objectives = quest_state.get("objectives", [])

	for i in range(qdef.objectives.size()):
		var obj = qdef.objectives[i]
		var target_count = int(obj.get("target_count", 1))
		var obj_type = str(obj.get("type", ""))

		# Delivery and inventory-check collect: validate inventory at turn-in
		var needs_inventory_check = false
		if obj_type == "deliver":
			needs_inventory_check = true
		elif obj_type == "collect" and obj.get("consumes_items", false):
			needs_inventory_check = true

		if needs_inventory_check:
			var item_id = str(obj.get("target_id", ""))
			if not NetworkManager.server_has_inventory(peer_id, item_id, target_count):
				return false
		else:
			# Cumulative progress check
			if i >= objectives.size():
				return false
			var progress = int(objectives[i].get("progress", 0))
			if progress < target_count:
				return false

	return true

# === Daily/Weekly Reset ===

func _on_day_changed() -> void:
	if not multiplayer.is_server():
		return
	var season_mgr = get_node_or_null("/root/Main/GameWorld/SeasonManager")
	var total_days: int = season_mgr.total_day_count if season_mgr else 0

	for peer_id in NetworkManager.player_data_store:
		var qdata = _ensure_quest_data(peer_id)
		var completed = qdata.get("completed", {})
		var last_daily = int(qdata.get("daily_reset_day", 0))
		var last_weekly = int(qdata.get("weekly_reset_day", 0))
		var changed: bool = false

		# Daily reset
		if total_days > last_daily:
			qdata["daily_reset_day"] = total_days
			DataRegistry.ensure_loaded()
			var to_remove: Array = []
			for quest_id in completed:
				var qdef = DataRegistry.get_quest(quest_id)
				if qdef and qdef.category == "daily":
					to_remove.append(quest_id)
			for qid in to_remove:
				completed.erase(qid)
				changed = true

		# Weekly reset (every 7 days)
		if total_days - last_weekly >= 7:
			qdata["weekly_reset_day"] = total_days
			DataRegistry.ensure_loaded()
			var to_remove: Array = []
			for quest_id in completed:
				var qdef = DataRegistry.get_quest(quest_id)
				if qdef and qdef.category == "weekly":
					to_remove.append(quest_id)
			for qid in to_remove:
				completed.erase(qid)
				changed = true

		if changed and multiplayer.get_peers().has(peer_id):
			_sync_quest_state.rpc_id(peer_id, qdata.get("active", {}), completed, qdata.get("unlock_flags", []))

# === Server-side Quest Data Sender ===

func _send_quest_data_to_peer(peer_id: int, npc_id: String) -> void:
	var available = get_available_quests(peer_id, npc_id)
	var completable = get_completable_quests(peer_id, npc_id)

	DataRegistry.ensure_loaded()
	var quests_data: Array = []
	for quest_id in available:
		var qdef = DataRegistry.get_quest(quest_id)
		if qdef:
			quests_data.append({
				"quest_id": qdef.quest_id,
				"display_name": qdef.display_name,
				"description": qdef.description,
				"objectives": qdef.objectives,
				"reward_money": qdef.reward_money,
				"reward_items": qdef.reward_items,
				"offer_dialogue": qdef.offer_dialogue,
				"category": qdef.category,
				"status": "available",
			})
	for quest_id in completable:
		var qdef = DataRegistry.get_quest(quest_id)
		if qdef:
			quests_data.append({
				"quest_id": qdef.quest_id,
				"display_name": qdef.display_name,
				"description": qdef.description,
				"completion_dialogue": qdef.completion_dialogue,
				"category": qdef.category,
				"status": "completable",
			})

	var qdata = _ensure_quest_data(peer_id)
	var active = qdata.get("active", {})
	for quest_id in active:
		if quest_id in completable:
			continue
		var qdef = DataRegistry.get_quest(quest_id)
		if qdef and qdef.quest_giver_npc_id == npc_id:
			quests_data.append({
				"quest_id": qdef.quest_id,
				"display_name": qdef.display_name,
				"in_progress_dialogue": qdef.in_progress_dialogue,
				"category": qdef.category,
				"status": "in_progress",
			})

	_send_available_quests.rpc_id(peer_id, quests_data)

# === RPCs: Client -> Server ===

@rpc("any_peer", "reliable")
func request_available_quests(npc_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id = multiplayer.get_remote_sender_id()
	_send_quest_data_to_peer(peer_id, npc_id)

@rpc("any_peer", "reliable")
func request_accept_quest(quest_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id = multiplayer.get_remote_sender_id()
	handle_accept_quest(peer_id, quest_id)

@rpc("any_peer", "reliable")
func request_complete_quest(quest_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id = multiplayer.get_remote_sender_id()
	handle_complete_quest(peer_id, quest_id)

@rpc("any_peer", "reliable")
func request_abandon_quest(quest_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id = multiplayer.get_remote_sender_id()
	handle_abandon_quest(peer_id, quest_id)

# === RPCs: Server -> Client ===

@rpc("authority", "reliable")
func _send_available_quests(quests_data: Array) -> void:
	# Client-side: forward to QuestLogUI or DialogueUI
	var quest_log = get_node_or_null("/root/Main/GameWorld/UI/QuestLogUI")
	if quest_log and quest_log.has_method("show_npc_quests"):
		quest_log.show_npc_quests(quests_data)

@rpc("authority", "reliable")
func _sync_quest_state(active: Dictionary, completed: Dictionary, flags: Array) -> void:
	PlayerData.active_quests = active.duplicate(true)
	PlayerData.completed_quests = completed.duplicate(true)
	PlayerData.unlock_flags = flags.duplicate()
	PlayerData.quests_changed.emit()

@rpc("authority", "reliable")
func _notify_quest_progress(quest_id: String, obj_idx: int, progress: int, target: int) -> void:
	# Update local active quest state
	if quest_id in PlayerData.active_quests:
		var objectives = PlayerData.active_quests[quest_id].get("objectives", [])
		if obj_idx < objectives.size():
			objectives[obj_idx]["progress"] = progress
	PlayerData.quests_changed.emit()
	# Show HUD toast for progress
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("show_toast"):
		DataRegistry.ensure_loaded()
		var qdef = DataRegistry.get_quest(quest_id)
		var quest_name = qdef.display_name if qdef else quest_id
		var obj_desc = ""
		if qdef and obj_idx < qdef.objectives.size():
			obj_desc = str(qdef.objectives[obj_idx].get("description", ""))
		if obj_desc != "":
			hud.show_toast(quest_name + ": " + obj_desc + " (" + str(progress) + "/" + str(target) + ")")
		else:
			hud.show_toast(quest_name + " (" + str(progress) + "/" + str(target) + ")")

@rpc("authority", "reliable")
func _notify_quest_complete(quest_id: String, quest_name: String, rewards: Dictionary) -> void:
	# Move from active to completed locally
	PlayerData.active_quests.erase(quest_id)
	PlayerData.completed_quests[quest_id] = int(Time.get_unix_time_from_system())
	PlayerData.quests_changed.emit()
	# Show completion toast
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("show_toast"):
		var msg = "Quest Complete: " + quest_name
		var money = int(rewards.get("money", 0))
		if money > 0:
			msg += " (+$" + str(money) + ")"
		hud.show_toast(msg)

@rpc("authority", "reliable")
func _offer_next_quest(_quest_id: String, _npc_id: String, _dialogue: String, _quest_data: Dictionary) -> void:
	# Client: show auto-offer for next quest in chain
	var quest_log = get_node_or_null("/root/Main/GameWorld/UI/QuestLogUI")
	if quest_log and quest_log.has_method("show_next_quest_offer"):
		quest_log.show_next_quest_offer(_quest_id, _npc_id, _dialogue, _quest_data)
