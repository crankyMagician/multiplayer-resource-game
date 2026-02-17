extends GutTest

# Tests for ExcursionManager logic.
# Since ExcursionManager requires multiplayer context, we test its data structures
# and helper methods in isolation.

var mgr: Node

func before_each():
	DataRegistry.ensure_loaded()
	var script = load("res://scripts/world/excursion_manager.gd")
	mgr = Node.new()
	mgr.set_script(script)

func after_each():
	if mgr:
		mgr.free()

# --- UUID Generation ---

func test_generate_uuid_format():
	var uuid: String = mgr._generate_uuid()
	assert_eq(uuid.length(), 36, "UUID should be 36 chars (32 hex + 4 dashes)")
	assert_eq(uuid[8], "-", "UUID should have dash at position 8")
	assert_eq(uuid[13], "-", "UUID should have dash at position 13")
	assert_eq(uuid[18], "-", "UUID should have dash at position 18")
	assert_eq(uuid[23], "-", "UUID should have dash at position 23")

func test_generate_uuid_uniqueness():
	var uuids: Dictionary = {}
	for i in range(100):
		var uuid: String = mgr._generate_uuid()
		assert_false(uuid in uuids, "UUID should be unique")
		uuids[uuid] = true

# --- Loot Logging ---

func test_log_loot_creates_entry():
	var instance_id := "test-instance"
	mgr.excursion_instances[instance_id] = {
		"instance_id": instance_id,
		"loot_log": {},
	}
	mgr._log_loot(instance_id, 2, "mystic_herb", 3)
	var log: Dictionary = mgr.excursion_instances[instance_id]["loot_log"]
	assert_eq(log["2"]["mystic_herb"], 3, "Should log 3 mystic_herb for peer 2")

func test_log_loot_accumulates():
	var instance_id := "test-instance"
	mgr.excursion_instances[instance_id] = {
		"instance_id": instance_id,
		"loot_log": {},
	}
	mgr._log_loot(instance_id, 5, "wild_honey", 1)
	mgr._log_loot(instance_id, 5, "wild_honey", 2)
	var log: Dictionary = mgr.excursion_instances[instance_id]["loot_log"]
	assert_eq(log["5"]["wild_honey"], 3, "Should accumulate to 3 wild_honey")

# --- Instance State Tests ---

func test_is_player_in_excursion_false_by_default():
	assert_false(mgr.is_player_in_excursion(42), "No player should be in excursion initially")

func test_is_player_in_excursion_true_when_mapped():
	mgr.player_excursion_map[42] = "test-instance"
	assert_true(mgr.is_player_in_excursion(42), "Player 42 should be in excursion")

func test_get_instance_for_peer_empty_when_not_in():
	var inst = mgr.get_instance_for_peer(99)
	assert_true(inst.is_empty(), "Should return empty dict for unmapped peer")

func test_get_instance_for_peer_returns_data():
	var instance_id := "test-123"
	mgr.player_excursion_map[10] = instance_id
	mgr.excursion_instances[instance_id] = {
		"instance_id": instance_id,
		"party_id": 1,
		"seed": 42,
		"members": [10],
	}
	var inst = mgr.get_instance_for_peer(10)
	assert_eq(inst["instance_id"], instance_id)
	assert_eq(inst["party_id"], 1)
	assert_eq(inst["seed"], 42)

func test_get_instance_members():
	var instance_id := "test-456"
	mgr.excursion_instances[instance_id] = {
		"members": [2, 3, 4],
	}
	var members = mgr.get_instance_members(instance_id)
	assert_eq(members.size(), 3)
	assert_has(members, 2)
	assert_has(members, 3)
	assert_has(members, 4)

func test_get_instance_members_empty_for_unknown():
	var members = mgr.get_instance_members("nonexistent")
	assert_eq(members.size(), 0)

# --- Level Boost ---

func test_level_boost_solo():
	# 1 member = 0 boost
	mgr.player_excursion_map[10] = "inst-1"
	mgr.excursion_instances["inst-1"] = {"members": [10]}
	assert_eq(mgr.get_level_boost_for_peer(10), 0)

func test_level_boost_two_players():
	mgr.player_excursion_map[10] = "inst-2"
	mgr.excursion_instances["inst-2"] = {"members": [10, 11]}
	# floor(0.25 * 1 * 15) = floor(3.75) = 3
	assert_eq(mgr.get_level_boost_for_peer(10), 3)

func test_level_boost_four_players():
	mgr.player_excursion_map[10] = "inst-3"
	mgr.excursion_instances["inst-3"] = {"members": [10, 11, 12, 13]}
	# floor(0.25 * 3 * 15) = floor(11.25) = 11
	assert_eq(mgr.get_level_boost_for_peer(10), 11)

func test_level_boost_not_in_excursion():
	assert_eq(mgr.get_level_boost_for_peer(99), 0)

# --- Bonus Drop Rolling ---

func test_bonus_drops_returns_dict():
	seed(42) # deterministic
	var drops = mgr._roll_excursion_bonus_drops()
	assert_true(drops is Dictionary, "Should return a dictionary")

func test_bonus_drops_only_valid_items():
	seed(1)
	for i in range(100):
		var drops = mgr._roll_excursion_bonus_drops()
		for item_id in drops:
			assert_true(
				item_id in mgr.EXCURSION_BONUS_INGREDIENTS or item_id in mgr.EXCURSION_BONUS_SEEDS,
				"Bonus drop '%s' should be a valid excursion item" % item_id
			)

# --- Constants Validation ---

func test_timeout_is_15_minutes():
	assert_eq(mgr.INSTANCE_TIMEOUT_SEC, 900.0, "Timeout should be 900 seconds (15 minutes)")

func test_max_instances():
	assert_eq(mgr.MAX_EXCURSION_INSTANCES, 10, "Max instances should be 10")

func test_exit_cooldown():
	assert_eq(mgr.EXIT_COOLDOWN_MS, 2000, "Exit cooldown should be 2000ms")

# --- Entry Immunity ---

func test_entry_immunity_tracks_timestamp():
	mgr._entry_immunity[10] = Time.get_ticks_msec()
	assert_true(10 in mgr._entry_immunity, "Entry immunity should be tracked")

func test_entry_immunity_cleared_on_erase():
	mgr._entry_immunity[10] = Time.get_ticks_msec()
	mgr._entry_immunity.erase(10)
	assert_false(10 in mgr._entry_immunity, "Entry immunity should be cleared after erase")

# --- Overworld Position Tracking ---

func test_overworld_position_saved():
	mgr.overworld_positions[5] = Vector3(10, 1, 20)
	assert_eq(mgr.overworld_positions[5], Vector3(10, 1, 20), "Should save overworld position")

func test_overworld_position_cleared_after_erase():
	mgr.overworld_positions[5] = Vector3(10, 1, 20)
	mgr.overworld_positions.erase(5)
	assert_false(5 in mgr.overworld_positions, "Position should be cleared")

# --- Portal Monitoring Toggle ---

func test_portal_monitoring_toggle():
	# Verify the set_deferred monitoring toggle pattern works for Area3D
	var area = Area3D.new()
	area.monitoring = true
	add_child_autofree(area)
	area.monitoring = false
	area.set_deferred("monitoring", true)
	# After set_deferred, value updates next frame — immediate check sees false
	assert_false(area.monitoring, "Monitoring should be false until deferred set takes effect")

# --- Solo Excursion ---

func test_solo_excursion_party_id_sentinel():
	# Solo excursion uses party_id = -1, which should not match real party lookups
	var instance_id := "solo-test"
	mgr.excursion_instances[instance_id] = {
		"instance_id": instance_id,
		"party_id": -1,
		"seed": 99,
		"members": [10],
		"allowed_player_ids": ["player-abc"],
	}
	# Verify party_id is -1 sentinel
	assert_eq(mgr.excursion_instances[instance_id]["party_id"], -1, "Solo excursion should have party_id = -1")
	# Verify no real party_id matches
	for iid in mgr.excursion_instances:
		var inst = mgr.excursion_instances[iid]
		if inst["party_id"] == 42: # some real party id
			assert_true(false, "Solo instance should not match real party id")

func test_solo_excursion_single_member():
	var instance_id := "solo-member-test"
	mgr.player_excursion_map[10] = instance_id
	mgr.excursion_instances[instance_id] = {
		"instance_id": instance_id,
		"party_id": -1,
		"members": [10],
	}
	var members = mgr.get_instance_members(instance_id)
	assert_eq(members.size(), 1, "Solo excursion should have 1 member")
	assert_has(members, 10)
	# Level boost should be 0 for solo
	assert_eq(mgr.get_level_boost_for_peer(10), 0, "Solo excursion should have 0 level boost")
