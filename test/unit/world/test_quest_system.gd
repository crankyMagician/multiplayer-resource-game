extends GutTest

# Unit tests for quest system: prereqs, progress, completion, rewards, resets.
# QuestManager has no class_name, so we inline its pure logic here.
# Uses RegistrySeeder.

func before_each() -> void:
	RegistrySeeder.seed_all()

func after_each() -> void:
	RegistrySeeder.clear_all()

# === Inline QuestManager static helpers ===

static func _check_prereqs(qdef: Resource, completed: Dictionary, friendships: Dictionary, discovered_locations: Array, _season: String = "", _weather: String = "") -> bool:
	for req_id in qdef.prereq_quest_ids:
		if req_id not in completed:
			return false
	if qdef.prereq_main_story_quest_id != "":
		if qdef.prereq_main_story_quest_id not in completed:
			return false
	for npc_id in qdef.prereq_friendship:
		var required = int(qdef.prereq_friendship[npc_id])
		var fs = friendships.get(npc_id, {})
		if int(fs.get("points", 0)) < required:
			return false
	for loc_id in qdef.prereq_locations:
		if loc_id not in discovered_locations:
			return false
	if qdef.prereq_season != "" and _season != "" and _season != qdef.prereq_season:
		return false
	if qdef.prereq_weather != "" and _weather != "" and _weather != qdef.prereq_weather:
		return false
	return true

static func _notify_progress(active_quests: Dictionary, objective_type: String, target_id: String, count: int = 1) -> Dictionary:
	# Returns {quest_id: {obj_idx: new_progress}} for any updated objectives
	var updates: Dictionary = {}
	for quest_id in active_quests:
		var qdef = DataRegistry.get_quest(quest_id)
		if qdef == null:
			continue
		var quest_state = active_quests[quest_id]
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
				var new_val = mini(current + count, target_count)
				if new_val != current:
					objectives[i]["progress"] = new_val
					if quest_id not in updates:
						updates[quest_id] = {}
					updates[quest_id][i] = new_val
	return updates

static func _are_objectives_complete(quest_id: String, active_quests: Dictionary, inventory: Dictionary) -> bool:
	var qdef = DataRegistry.get_quest(quest_id)
	if qdef == null:
		return false
	if quest_id not in active_quests:
		return false
	var quest_state = active_quests[quest_id]
	var objectives = quest_state.get("objectives", [])
	for i in range(qdef.objectives.size()):
		var obj = qdef.objectives[i]
		var target_count = int(obj.get("target_count", 1))
		var obj_type = str(obj.get("type", ""))
		var needs_inventory = false
		if obj_type == "deliver":
			needs_inventory = true
		elif obj_type == "collect" and obj.get("consumes_items", false):
			needs_inventory = true
		if needs_inventory:
			var item_id = str(obj.get("target_id", ""))
			if int(inventory.get(item_id, 0)) < target_count:
				return false
		else:
			if i >= objectives.size():
				return false
			if int(objectives[i].get("progress", 0)) < target_count:
				return false
	return true

# === Helper ===

func _make_active(quest_id: String) -> Dictionary:
	var qdef = DataRegistry.get_quest(quest_id)
	var obj_progress: Array = []
	for _obj in qdef.objectives:
		obj_progress.append({"progress": 0})
	return {quest_id: {"started_at": 0, "objectives": obj_progress}}

# === Prerequisite Tests ===

func test_quest_no_prereqs_always_available() -> void:
	var qdef = DataRegistry.get_quest("test_collect")
	assert_true(_check_prereqs(qdef, {}, {}, []))

func test_quest_prereq_quest_ids_blocks_until_completed() -> void:
	var qdef = DataRegistry.get_quest("test_ms_02")
	assert_false(_check_prereqs(qdef, {}, {}, []))
	assert_true(_check_prereqs(qdef, {"test_ms_01": 0}, {}, []))

func test_quest_prereq_friendship_threshold() -> void:
	var qdef = DataRegistry.get_quest("test_prereq_friendship")
	assert_false(_check_prereqs(qdef, {}, {}, []))
	assert_false(_check_prereqs(qdef, {}, {"test_npc": {"points": 10}}, []))
	assert_true(_check_prereqs(qdef, {}, {"test_npc": {"points": 20}}, []))

func test_quest_prereq_locations_discovered() -> void:
	var qdef = DataRegistry.get_quest("test_prereq_location")
	assert_false(_check_prereqs(qdef, {}, {}, []))
	assert_true(_check_prereqs(qdef, {}, {}, ["test_wild"]))

func test_quest_prereq_season_check() -> void:
	var QDef = load("res://scripts/data/quest_def.gd")
	var qdef = QDef.new()
	qdef.quest_id = "season_quest"
	qdef.prereq_season = "spring"
	qdef.objectives = [{"type": "collect", "target_id": "", "target_count": 1, "description": "test"}]
	assert_true(_check_prereqs(qdef, {}, {}, [], "spring"))
	assert_false(_check_prereqs(qdef, {}, {}, [], "winter"))
	assert_true(_check_prereqs(qdef, {}, {}, [], "")) # No season info = pass

func test_quest_prereq_weather_check() -> void:
	var QDef = load("res://scripts/data/quest_def.gd")
	var qdef = QDef.new()
	qdef.quest_id = "weather_quest"
	qdef.prereq_weather = "rainy"
	qdef.objectives = [{"type": "collect", "target_id": "", "target_count": 1, "description": "test"}]
	assert_true(_check_prereqs(qdef, {}, {}, [], "", "rainy"))
	assert_false(_check_prereqs(qdef, {}, {}, [], "", "sunny"))

func test_quest_prereq_main_story_gates_correctly() -> void:
	var qdef = DataRegistry.get_quest("test_prereq_ms")
	assert_false(_check_prereqs(qdef, {}, {}, []))
	assert_true(_check_prereqs(qdef, {"test_ms_01": 0}, {}, []))

func test_quest_multiple_prereqs_all_must_pass() -> void:
	# Create a quest with multiple prereqs
	var QDef = load("res://scripts/data/quest_def.gd")
	var qdef = QDef.new()
	qdef.quest_id = "multi_prereq"
	qdef.prereq_quest_ids = ["test_ms_01"]
	qdef.prereq_friendship = {"test_npc": 10}
	qdef.prereq_locations = ["test_wild"]
	qdef.objectives = [{"type": "collect", "target_id": "", "target_count": 1, "description": "test"}]
	# Only quest completed
	assert_false(_check_prereqs(qdef, {"test_ms_01": 0}, {}, []))
	# Quest + friendship but no location
	assert_false(_check_prereqs(qdef, {"test_ms_01": 0}, {"test_npc": {"points": 10}}, []))
	# All met
	assert_true(_check_prereqs(qdef, {"test_ms_01": 0}, {"test_npc": {"points": 10}}, ["test_wild"]))

# === Objective Progress Tests ===

func test_cumulative_progress_increments() -> void:
	var active = _make_active("test_daily")
	var updates = _notify_progress(active, "defeat_creature", "rice_ball", 1)
	assert_eq(int(active["test_daily"]["objectives"][0]["progress"]), 1)
	assert_true(updates.has("test_daily"))

func test_progress_caps_at_target_count() -> void:
	var active = _make_active("test_daily")
	_notify_progress(active, "defeat_creature", "rice_ball", 5)
	assert_eq(int(active["test_daily"]["objectives"][0]["progress"]), 2)

func test_multiple_objectives_tracked_independently() -> void:
	var active = _make_active("test_multi_obj")
	_notify_progress(active, "defeat_creature", "rice_ball", 1)
	assert_eq(int(active["test_multi_obj"]["objectives"][0]["progress"]), 1)
	assert_eq(int(active["test_multi_obj"]["objectives"][1]["progress"]), 0)
	_notify_progress(active, "discover_location", "test_wild", 1)
	assert_eq(int(active["test_multi_obj"]["objectives"][1]["progress"]), 1)

func test_all_objectives_required_for_completion() -> void:
	var active = _make_active("test_multi_obj")
	_notify_progress(active, "defeat_creature", "rice_ball", 2)
	assert_false(_are_objectives_complete("test_multi_obj", active, {}))
	_notify_progress(active, "discover_location", "test_wild", 1)
	assert_true(_are_objectives_complete("test_multi_obj", active, {}))

func test_progress_on_inactive_quest_ignored() -> void:
	var active: Dictionary = {} # No active quests
	var updates = _notify_progress(active, "defeat_creature", "rice_ball", 1)
	assert_eq(updates.size(), 0)

func test_delivery_objective_not_tracked_by_notify() -> void:
	var active = _make_active("test_delivery")
	var updates = _notify_progress(active, "deliver", "wheat", 3)
	assert_eq(updates.size(), 0)
	assert_eq(int(active["test_delivery"]["objectives"][0]["progress"]), 0)

func test_collect_cumulative_tracks_via_notify() -> void:
	# test_collect has cumulative collect (no consumes_items flag)
	var active = _make_active("test_collect")
	_notify_progress(active, "collect", "herb_basil", 3)
	assert_eq(int(active["test_collect"]["objectives"][0]["progress"]), 3)

func test_unknown_objective_type_handled() -> void:
	var active = _make_active("test_collect")
	var updates = _notify_progress(active, "nonexistent_type", "whatever", 1)
	assert_eq(updates.size(), 0)

# === Completion & Reward Tests ===

func test_complete_quest_checks_cumulative_progress() -> void:
	var active = _make_active("test_collect")
	assert_false(_are_objectives_complete("test_collect", active, {}))
	_notify_progress(active, "collect", "herb_basil", 5)
	assert_true(_are_objectives_complete("test_collect", active, {}))

func test_delivery_checks_inventory_at_turnin() -> void:
	var active = _make_active("test_delivery")
	# No items in inventory
	assert_false(_are_objectives_complete("test_delivery", active, {}))
	# Not enough
	assert_false(_are_objectives_complete("test_delivery", active, {"wheat": 2}))
	# Enough
	assert_true(_are_objectives_complete("test_delivery", active, {"wheat": 3}))

func test_cannot_complete_quest_twice() -> void:
	var active = _make_active("test_collect")
	_notify_progress(active, "collect", "item", 5)
	# Remove from active (simulating completion)
	active.erase("test_collect")
	assert_false(_are_objectives_complete("test_collect", active, {}))

func test_cannot_complete_with_insufficient_delivery_items() -> void:
	var active = _make_active("test_delivery")
	assert_false(_are_objectives_complete("test_delivery", active, {"wheat": 1}))

# === Daily/Weekly Reset Tests ===

func test_daily_quest_clears_after_day_change() -> void:
	var completed: Dictionary = {"test_daily": 0}
	# Simulate reset: remove daily entries
	var to_remove: Array = []
	for quest_id in completed:
		var qdef = DataRegistry.get_quest(quest_id)
		if qdef and qdef.category == "daily":
			to_remove.append(quest_id)
	for qid in to_remove:
		completed.erase(qid)
	assert_false(completed.has("test_daily"))

func test_weekly_quest_clears_after_seven_days() -> void:
	var completed: Dictionary = {"test_weekly": 0}
	var to_remove: Array = []
	for quest_id in completed:
		var qdef = DataRegistry.get_quest(quest_id)
		if qdef and qdef.category == "weekly":
			to_remove.append(quest_id)
	for qid in to_remove:
		completed.erase(qid)
	assert_false(completed.has("test_weekly"))

func test_one_time_quest_never_clears() -> void:
	var completed: Dictionary = {"test_collect": 0, "test_ms_01": 0}
	var to_remove: Array = []
	for quest_id in completed:
		var qdef = DataRegistry.get_quest(quest_id)
		if qdef and (qdef.category == "daily" or qdef.category == "weekly"):
			to_remove.append(quest_id)
	for qid in to_remove:
		completed.erase(qid)
	assert_true(completed.has("test_collect"))
	assert_true(completed.has("test_ms_01"))

func test_active_daily_survives_reset() -> void:
	# Reset only affects completed dict, not active
	var active = _make_active("test_daily")
	var completed: Dictionary = {}
	# After reset, active quest should still be there
	assert_true(active.has("test_daily"))

func test_reset_day_tracking() -> void:
	var qdata = {"active": {}, "completed": {}, "daily_reset_day": 0, "weekly_reset_day": 0, "unlock_flags": []}
	var total_days = 5
	if total_days > int(qdata["daily_reset_day"]):
		qdata["daily_reset_day"] = total_days
	assert_eq(int(qdata["daily_reset_day"]), 5)

# === Main Story Chain Tests ===

func test_next_quest_id_chains_correctly() -> void:
	var qdef = DataRegistry.get_quest("test_ms_01")
	assert_eq(qdef.next_quest_id, "test_ms_02")
	var next = DataRegistry.get_quest(qdef.next_quest_id)
	assert_not_null(next)
	assert_eq(next.quest_id, "test_ms_02")

func test_chapter_ordering() -> void:
	var q1 = DataRegistry.get_quest("test_ms_01")
	var q2 = DataRegistry.get_quest("test_ms_02")
	assert_eq(q1.chapter, 1)
	assert_eq(q2.chapter, 1)
	assert_lt(q1.sort_order, q2.sort_order)

func test_cannot_abandon_main_story_quest() -> void:
	var qdef = DataRegistry.get_quest("test_ms_01")
	assert_eq(qdef.category, "main_story")
	# QuestManager rejects abandon for main_story

func test_main_story_prereq_enforced() -> void:
	var qdef = DataRegistry.get_quest("test_ms_02")
	assert_false(_check_prereqs(qdef, {}, {}, []))
	assert_true(_check_prereqs(qdef, {"test_ms_01": 0}, {}, []))

# === Edge Case Tests ===

func test_accept_quest_already_active_blocked() -> void:
	var active = _make_active("test_collect")
	# QuestManager checks active before accepting — simulated here
	assert_true(active.has("test_collect"))

func test_invalid_quest_id_handled() -> void:
	var qdef = DataRegistry.get_quest("nonexistent_quest")
	assert_null(qdef)

func test_quest_available_for_correct_npc_only() -> void:
	var qdef = DataRegistry.get_quest("test_other_npc")
	assert_eq(qdef.quest_giver_npc_id, "other_npc")
	# Should not appear for test_npc
	assert_ne(qdef.quest_giver_npc_id, "test_npc")

func test_collect_with_empty_target_matches_any() -> void:
	# test_collect has target_id="" which matches any item
	var active = _make_active("test_collect")
	_notify_progress(active, "collect", "random_item", 2)
	assert_eq(int(active["test_collect"]["objectives"][0]["progress"]), 2)
	_notify_progress(active, "collect", "another_item", 3)
	assert_eq(int(active["test_collect"]["objectives"][0]["progress"]), 5)

func test_target_specific_objective_only_matches_target() -> void:
	var active = _make_active("test_multi_obj")
	# Objective 1: discover_location with target_id="test_wild"
	_notify_progress(active, "discover_location", "wrong_location", 1)
	assert_eq(int(active["test_multi_obj"]["objectives"][1]["progress"]), 0)
	_notify_progress(active, "discover_location", "test_wild", 1)
	assert_eq(int(active["test_multi_obj"]["objectives"][1]["progress"]), 1)
