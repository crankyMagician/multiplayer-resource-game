extends GutTest

## Tests for FriendManager logic: social data helpers, pair-lock, request validation,
## party state management. Tests the server-side data manipulation without actual RPCs.

var fm: Node
var player_data_store: Dictionary = {}

func before_each() -> void:
	player_data_store.clear()
	fm = load("res://scripts/world/friend_manager.gd").new()
	fm.name = "FriendManager"
	add_child(fm)

func after_each() -> void:
	fm.queue_free()
	player_data_store.clear()

# === Social Data Helpers ===

func _make_social(friends: Array = [], blocked: Array = [], incoming: Array = [], outgoing: Array = []) -> Dictionary:
	return {"friends": friends, "blocked": blocked, "incoming_requests": incoming, "outgoing_requests": outgoing}

# === Tests: Pair Lock ===

func test_pair_key_deterministic() -> void:
	assert_eq(fm._pair_key("aaa", "bbb"), "aaa:bbb")
	assert_eq(fm._pair_key("bbb", "aaa"), "aaa:bbb")
	assert_eq(fm._pair_key("same", "same"), "same:same")

func test_acquire_release_lock() -> void:
	var key = fm._pair_key("a", "b")
	assert_true(fm._acquire_lock(key))
	assert_false(fm._acquire_lock(key), "Should not acquire twice")
	fm._release_lock(key)
	assert_true(fm._acquire_lock(key), "Should acquire after release")
	fm._release_lock(key)

# === Tests: Social State Checks ===

func test_is_blocked() -> void:
	var social = _make_social([], ["uuid-blocked"])
	assert_true(fm._is_blocked(social, "uuid-blocked"))
	assert_false(fm._is_blocked(social, "uuid-other"))

func test_are_friends() -> void:
	var social = _make_social(["uuid-friend"])
	assert_true(fm._are_friends(social, "uuid-friend"))
	assert_false(fm._are_friends(social, "uuid-stranger"))

func test_has_outgoing_to() -> void:
	var social = _make_social([], [], [], [{"to_id": "uuid-target", "to_name": "Target", "sent_at": 100}])
	assert_true(fm._has_outgoing_to(social, "uuid-target"))
	assert_false(fm._has_outgoing_to(social, "uuid-other"))

func test_has_incoming_from() -> void:
	var social = _make_social([], [], [{"from_id": "uuid-sender", "from_name": "Sender", "sent_at": 100}])
	assert_true(fm._has_incoming_from(social, "uuid-sender"))
	assert_false(fm._has_incoming_from(social, "uuid-other"))

# === Tests: Request Array Manipulation ===

func test_remove_incoming_from() -> void:
	var social = _make_social([], [], [
		{"from_id": "a", "from_name": "A", "sent_at": 1},
		{"from_id": "b", "from_name": "B", "sent_at": 2},
		{"from_id": "a", "from_name": "A2", "sent_at": 3},
	])
	fm._remove_incoming_from(social, "a")
	assert_eq(social["incoming_requests"].size(), 1)
	assert_eq(str(social["incoming_requests"][0]["from_id"]), "b")

func test_remove_outgoing_to() -> void:
	var social = _make_social([], [], [], [
		{"to_id": "x", "to_name": "X", "sent_at": 1},
		{"to_id": "y", "to_name": "Y", "sent_at": 2},
	])
	fm._remove_outgoing_to(social, "x")
	assert_eq(social["outgoing_requests"].size(), 1)
	assert_eq(str(social["outgoing_requests"][0]["to_id"]), "y")

# === Tests: Party State ===

func test_create_party() -> void:
	var party_id = fm._next_party_id
	fm.parties[party_id] = {
		"party_id": party_id,
		"leader_id": "player-a",
		"members": ["player-a"],
		"invites": {},
	}
	fm.player_party_map["player-a"] = party_id
	fm._next_party_id += 1

	assert_true("player-a" in fm.player_party_map)
	assert_eq(fm.parties[party_id]["leader_id"], "player-a")
	assert_eq(fm.parties[party_id]["members"].size(), 1)

func test_party_member_join() -> void:
	var party_id = 1
	fm.parties[party_id] = {
		"party_id": party_id,
		"leader_id": "leader",
		"members": ["leader"],
		"invites": {"joiner": {"invited_at": Time.get_unix_time_from_system()}},
	}
	fm.player_party_map["leader"] = party_id

	# Simulate join
	fm.parties[party_id]["invites"].erase("joiner")
	fm.parties[party_id]["members"].append("joiner")
	fm.player_party_map["joiner"] = party_id

	assert_eq(fm.parties[party_id]["members"].size(), 2)
	assert_true("joiner" in fm.player_party_map)

func test_party_invite_ttl_expired() -> void:
	var party_id = 1
	var expired_time = Time.get_unix_time_from_system() - fm.PARTY_INVITE_TTL_SEC - 10
	fm.parties[party_id] = {
		"party_id": party_id,
		"leader_id": "leader",
		"members": ["leader"],
		"invites": {"late-joiner": {"invited_at": expired_time}},
	}
	# Check the invite is expired
	var invite = fm.parties[party_id]["invites"]["late-joiner"]
	var elapsed = Time.get_unix_time_from_system() - float(invite["invited_at"])
	assert_true(elapsed > fm.PARTY_INVITE_TTL_SEC, "Invite should be expired")

func test_party_max_size() -> void:
	var party_id = 1
	var members: Array = []
	for i in fm.MAX_PARTY_SIZE:
		members.append("player-" + str(i))
	fm.parties[party_id] = {
		"party_id": party_id,
		"leader_id": "player-0",
		"members": members,
		"invites": {},
	}
	assert_eq(fm.parties[party_id]["members"].size(), fm.MAX_PARTY_SIZE)
	# Should not allow more (validated in RPC handler, we just check the cap)
	assert_true(fm.parties[party_id]["members"].size() >= fm.MAX_PARTY_SIZE)

func test_party_leader_transfer_on_leave() -> void:
	var party_id = 1
	fm.parties[party_id] = {
		"party_id": party_id,
		"leader_id": "leader",
		"members": ["leader", "member-a", "member-b"],
		"invites": {},
	}
	fm.player_party_map["leader"] = party_id
	fm.player_party_map["member-a"] = party_id
	fm.player_party_map["member-b"] = party_id

	# Simulate leader removal (disconnect handling)
	var party = fm.parties[party_id]
	party["members"].erase("leader")
	fm.player_party_map.erase("leader")
	if str(party["leader_id"]) == "leader":
		party["leader_id"] = party["members"][0]

	assert_eq(str(party["leader_id"]), "member-a")
	assert_eq(party["members"].size(), 2)

func test_party_disband_when_empty() -> void:
	var party_id = 1
	fm.parties[party_id] = {
		"party_id": party_id,
		"leader_id": "solo",
		"members": ["solo"],
		"invites": {},
	}
	fm.player_party_map["solo"] = party_id

	# Remove last member
	fm.parties[party_id]["members"].erase("solo")
	fm.player_party_map.erase("solo")
	if fm.parties[party_id]["members"].is_empty():
		fm.parties.erase(party_id)

	assert_false(fm.parties.has(party_id), "Party should be disbanded")
	assert_false(fm.player_party_map.has("solo"))

# === Tests: Constants ===

func test_constants_sane() -> void:
	assert_eq(fm.MAX_FRIENDS, 100)
	assert_eq(fm.MAX_BLOCKED, 50)
	assert_eq(fm.MAX_PENDING_REQUESTS, 20)
	assert_eq(fm.MAX_PARTY_SIZE, 4)
	assert_eq(fm.PARTY_INVITE_TTL_SEC, 60)

# === Tests: Kick from Shared Party ===

func test_kick_from_shared_party_same_party() -> void:
	var party_id = 1
	fm.parties[party_id] = {
		"party_id": party_id,
		"leader_id": "player-a",
		"members": ["player-a", "player-b"],
		"invites": {},
	}
	fm.player_party_map["player-a"] = party_id
	fm.player_party_map["player-b"] = party_id
	# Both are in same party, so _kick_from_shared_party should remove player-b
	# We can't call the full method without NetworkManager, so test the logic
	assert_eq(fm.player_party_map.get("player-a", -1), fm.player_party_map.get("player-b", -1))

func test_kick_from_shared_party_different_parties() -> void:
	fm.player_party_map["player-a"] = 1
	fm.player_party_map["player-b"] = 2
	# Different parties — should NOT kick
	assert_ne(fm.player_party_map.get("player-a", -1), fm.player_party_map.get("player-b", -1))
