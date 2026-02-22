extends GutTest

# Tests for the character creation gate logic in NetworkManager._receive_player_data.
# We mirror the routing logic inline since NetworkManager is an autoload.


## Returns true if the player needs to go through the character creator,
## false if they can skip straight to the game world.
func _needs_character_creator(appearance: Dictionary) -> bool:
	return appearance.get("needs_customization", false)


func test_new_player_needs_customization_true():
	var app := {"needs_customization": true}
	assert_true(_needs_character_creator(app),
		"New player with needs_customization should trigger creator")


func test_returning_player_skips_creator():
	var app := {
		"gender": "female",
		"head_id": "HEAD_01_1",
		"torso_id": "TORSO_01_1",
		"pants_id": "PANTS_01_1",
		"shoes_id": "SHOES_01_1",
	}
	assert_false(_needs_character_creator(app),
		"Returning player without needs_customization should skip creator")


func test_empty_appearance_skips_creator():
	# Empty dict has no needs_customization key — defaults to false
	assert_false(_needs_character_creator({}),
		"Empty appearance should not trigger creator (default false)")


func test_needs_customization_false_skips_creator():
	var app := {"needs_customization": false, "gender": "male"}
	assert_false(_needs_character_creator(app),
		"Explicit needs_customization=false should skip creator")


func test_old_save_no_appearance_key_backfill():
	# Simulates the server backfill: old saves with no appearance get
	# {"needs_customization": true} added server-side before sending to client.
	# This test validates the client-side gate responds correctly.
	var data_from_server := {"needs_customization": true}
	assert_true(_needs_character_creator(data_from_server),
		"Backfilled old save should trigger creator")


func test_appearance_with_extra_keys_and_needs_customization():
	var app := {
		"needs_customization": true,
		"gender": "female",
		"head_id": "HEAD_01_1",
	}
	assert_true(_needs_character_creator(app),
		"Even with some parts, needs_customization=true should trigger creator")


func test_confirmed_appearance_clears_needs_customization():
	# After the creator confirms, the appearance dict should have
	# needs_customization erased before being sent to the server.
	var app := {
		"needs_customization": true,
		"gender": "female",
		"head_id": "HEAD_01_1",
		"torso_id": "TORSO_01_1",
		"pants_id": "PANTS_01_1",
		"shoes_id": "SHOES_01_1",
	}
	# Simulate what _on_creator_confirmed receives (creator erases the flag)
	app.erase("needs_customization")
	assert_false(_needs_character_creator(app),
		"After confirming, needs_customization should be gone")


## Mirrors the timeout logic from NetworkManager._process() to test that
## "in_creator" state uses the longer CREATOR_TIMEOUT_MS instead of JOIN_READY_TIMEOUT_MS.
func _should_timeout(state: String, elapsed_ms: int) -> bool:
	if state == "active":
		return false
	var timeout := NetworkManager.CREATOR_TIMEOUT_MS if state == "in_creator" else NetworkManager.JOIN_READY_TIMEOUT_MS
	return elapsed_ms >= timeout


func test_in_creator_state_not_timed_out_by_join_timeout():
	# A peer in "in_creator" state should NOT be timed out at 15s
	assert_false(_should_timeout("in_creator", 15000),
		"in_creator state should not timeout at JOIN_READY_TIMEOUT_MS (15s)")
	assert_false(_should_timeout("in_creator", 60000),
		"in_creator state should not timeout at 60s")
	assert_false(_should_timeout("in_creator", 299999),
		"in_creator state should not timeout just before 5 min")
	assert_true(_should_timeout("in_creator", 300000),
		"in_creator state should timeout at CREATOR_TIMEOUT_MS (5 min)")


func test_pending_state_times_out_at_join_timeout():
	assert_false(_should_timeout("pending", 14999),
		"pending state should not timeout before 15s")
	assert_true(_should_timeout("pending", 15000),
		"pending state should timeout at JOIN_READY_TIMEOUT_MS")


func test_active_state_never_times_out():
	assert_false(_should_timeout("active", 999999),
		"active state should never timeout")
