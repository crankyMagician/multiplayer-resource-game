extends GutTest

# Integration tests for quest system lifecycle.
# Uses mock peer_id and NetworkManager.player_data_store.
# QuestManager has no class_name — inline its logic for testing.

var mock_peer_id: int = 200

func before_each() -> void:
	RegistrySeeder.seed_all()
	_setup_mock_player()

func after_each() -> void:
	RegistrySeeder.clear_all()
	NetworkManager.player_data_store.erase(mock_peer_id)

func _setup_mock_player() -> void:
	NetworkManager.player_data_store[mock_peer_id] = {
		"player_name": "QuestTester",
		"inventory": {},
		"party": [],
		"money": 0,
		"defeated_trainers": {},
		"npc_friendships": {},
		"discovered_locations": [],
		"quests": {
			"active": {},
			"completed": {},
			"daily_reset_day": 0,
			"weekly_reset_day": 0,
			"unlock_flags": [],
		},
	}

# === Inline QuestManager helpers ===

func _get_quest_data() -> Dictionary:
	return NetworkManager.player_data_store[mock_peer_id].get("quests", {})

func _accept_quest(quest_id: String) -> void:
	var qdef = DataRegistry.get_quest(quest_id)
	var qdata = _get_quest_data()
	var active = qdata.get("active", {})
	var obj_progress: Array = []
	for _obj in qdef.objectives:
		obj_progress.append({"progress": 0})
	active[quest_id] = {"started_at": 0, "objectives": obj_progress}

func _notify_progress(objective_type: String, target_id: String, count: int = 1) -> void:
	var qdata = _get_quest_data()
	var active = qdata.get("active", {})
	for quest_id in active:
		var qdef = DataRegistry.get_quest(quest_id)
		if qdef == null:
			continue
		var quest_state = active[quest_id]
		var objectives = quest_state.get("objectives", [])
		for i in range(qdef.objectives.size()):
			var obj = qdef.objectives[i]
			var obj_type = str(obj.get("type", ""))
			if obj_type == "deliver":
				continue
			if obj_type == "collect" and obj.get("consumes_items", false):
				continue
			if obj_type != objective_type:
				continue
			var obj_target = str(obj.get("target_id", ""))
			if obj_target != "" and obj_target != target_id:
				continue
			var target_count = int(obj.get("target_count", 1))
			if i < objectives.size():
				var current = int(objectives[i].get("progress", 0))
				objectives[i]["progress"] = mini(current + count, target_count)

func _are_objectives_complete(quest_id: String) -> bool:
	var qdata = _get_quest_data()
	var active = qdata.get("active", {})
	if quest_id not in active:
		return false
	var qdef = DataRegistry.get_quest(quest_id)
	if qdef == null:
		return false
	var quest_state = active[quest_id]
	var objectives = quest_state.get("objectives", [])
	var inv = NetworkManager.player_data_store[mock_peer_id].get("inventory", {})
	for i in range(qdef.objectives.size()):
		var obj = qdef.objectives[i]
		var target_count = int(obj.get("target_count", 1))
		var obj_type = str(obj.get("type", ""))
		var needs_inventory = obj_type == "deliver" or (obj_type == "collect" and obj.get("consumes_items", false))
		if needs_inventory:
			var item_id = str(obj.get("target_id", ""))
			if int(inv.get(item_id, 0)) < target_count:
				return false
		else:
			if i >= objectives.size():
				return false
			if int(objectives[i].get("progress", 0)) < target_count:
				return false
	return true

func _complete_quest(quest_id: String) -> bool:
	if not _are_objectives_complete(quest_id):
		return false
	var qdata = _get_quest_data()
	var active = qdata.get("active", {})
	var completed = qdata.get("completed", {})
	if quest_id not in active or quest_id in completed:
		return false
	var qdef = DataRegistry.get_quest(quest_id)
	var pdata = NetworkManager.player_data_store[mock_peer_id]
	# Deduct delivery items
	for i in range(qdef.objectives.size()):
		var obj = qdef.objectives[i]
		var obj_type = str(obj.get("type", ""))
		var should_consume = obj_type == "deliver" or (obj_type == "collect" and obj.get("consumes_items", false))
		if should_consume:
			var item_id = str(obj.get("target_id", ""))
			var amount = int(obj.get("target_count", 1))
			if item_id != "":
				NetworkManager.server_remove_inventory(mock_peer_id, item_id, amount)
	# Grant rewards
	if qdef.reward_money > 0:
		pdata["money"] = int(pdata.get("money", 0)) + qdef.reward_money
	for item_id in qdef.reward_items:
		NetworkManager.server_add_inventory(mock_peer_id, item_id, int(qdef.reward_items[item_id]))
	if qdef.reward_unlock_flag != "":
		var flags = qdata.get("unlock_flags", [])
		if qdef.reward_unlock_flag not in flags:
			flags.append(qdef.reward_unlock_flag)
	# Move to completed
	active.erase(quest_id)
	completed[quest_id] = 0
	return true

# === Full Lifecycle Tests ===

func test_accept_progress_complete_cycle() -> void:
	_accept_quest("test_collect")
	var active = _get_quest_data().get("active", {})
	assert_true(active.has("test_collect"))

	# Progress
	_notify_progress("collect", "herb_basil", 3)
	assert_eq(int(active["test_collect"]["objectives"][0]["progress"]), 3)

	_notify_progress("collect", "wheat", 2)
	assert_eq(int(active["test_collect"]["objectives"][0]["progress"]), 5)

	# Completable
	assert_true(_are_objectives_complete("test_collect"))

	# Complete
	assert_true(_complete_quest("test_collect"))
	var pdata = NetworkManager.player_data_store[mock_peer_id]
	assert_eq(int(pdata["money"]), 100)
	assert_true(_get_quest_data().get("completed", {}).has("test_collect"))
	assert_false(_get_quest_data().get("active", {}).has("test_collect"))

func test_delivery_quest_full_flow() -> void:
	_accept_quest("test_delivery")

	# Can't complete without items
	assert_false(_are_objectives_complete("test_delivery"))

	# Add items to inventory
	NetworkManager.server_add_inventory(mock_peer_id, "wheat", 3)

	# Now completable
	assert_true(_are_objectives_complete("test_delivery"))

	# Complete — items deducted, rewards granted
	assert_true(_complete_quest("test_delivery"))
	var inv = NetworkManager.player_data_store[mock_peer_id].get("inventory", {})
	assert_eq(int(inv.get("wheat", 0)), 0) # Consumed
	assert_eq(int(inv.get("herb_basil", 0)), 5) # Reward
	assert_eq(int(NetworkManager.player_data_store[mock_peer_id]["money"]), 200)

func test_multi_objective_quest_flow() -> void:
	_accept_quest("test_multi_obj")

	# Complete first objective only
	_notify_progress("defeat_creature", "rice_ball", 2)
	assert_false(_are_objectives_complete("test_multi_obj"))

	# Complete second objective
	_notify_progress("discover_location", "test_wild", 1)
	assert_true(_are_objectives_complete("test_multi_obj"))

	# Complete
	assert_true(_complete_quest("test_multi_obj"))
	assert_eq(int(NetworkManager.player_data_store[mock_peer_id]["money"]), 300)

func test_daily_reset_flow() -> void:
	_accept_quest("test_daily")
	_notify_progress("defeat_creature", "rice_ball", 2)
	assert_true(_complete_quest("test_daily"))

	# Quest is completed
	var completed = _get_quest_data().get("completed", {})
	assert_true(completed.has("test_daily"))

	# Simulate daily reset
	var to_remove: Array = []
	for quest_id in completed:
		var qdef = DataRegistry.get_quest(quest_id)
		if qdef and qdef.category == "daily":
			to_remove.append(quest_id)
	for qid in to_remove:
		completed.erase(qid)

	# Now re-offerable
	assert_false(completed.has("test_daily"))

	# Can accept again
	_accept_quest("test_daily")
	assert_true(_get_quest_data().get("active", {}).has("test_daily"))

func test_main_story_chain_flow() -> void:
	# Accept and complete ms_01
	_accept_quest("test_ms_01")
	_notify_progress("talk_to", "test_npc", 1)
	assert_true(_are_objectives_complete("test_ms_01"))
	assert_true(_complete_quest("test_ms_01"))

	# Verify rewards
	assert_eq(int(NetworkManager.player_data_store[mock_peer_id]["money"]), 50)
	var flags = _get_quest_data().get("unlock_flags", [])
	assert_true("ms_01_done" in flags)

	# ms_02 now available (prereq met)
	var completed = _get_quest_data().get("completed", {})
	assert_true(completed.has("test_ms_01"))

	# Accept and complete ms_02
	_accept_quest("test_ms_02")
	_notify_progress("defeat_trainer", "test_easy", 1)
	assert_true(_are_objectives_complete("test_ms_02"))
	assert_true(_complete_quest("test_ms_02"))

	assert_eq(int(NetworkManager.player_data_store[mock_peer_id]["money"]), 200) # 50 + 150

func test_quest_state_persistence_format() -> void:
	_accept_quest("test_collect")
	_notify_progress("collect", "wheat", 3)

	var qdata = _get_quest_data()
	# Verify structure matches expected save format
	assert_true(qdata.has("active"))
	assert_true(qdata.has("completed"))
	assert_true(qdata.has("daily_reset_day"))
	assert_true(qdata.has("weekly_reset_day"))
	assert_true(qdata.has("unlock_flags"))

	var active_entry = qdata["active"]["test_collect"]
	assert_true(active_entry.has("started_at"))
	assert_true(active_entry.has("objectives"))
	assert_eq(active_entry["objectives"].size(), 1)
	assert_eq(int(active_entry["objectives"][0]["progress"]), 3)
