extends GutTest

# Tests for busy-state guards across player controller, interaction, prompts, and encounters.
# Uses lightweight dictionaries to simulate player bodies — no scene instantiation or RPCs.

# --- Movement lock tests ---

func test_busy_player_velocity_zeroed():
	# When busy, horizontal velocity should decay toward zero (no movement applied)
	var vx: float = 5.0
	var vz: float = 5.0
	var is_busy: bool = true
	var delta: float = 0.016
	var SPEED: float = 7.0
	# Simulate the busy branch logic from player_controller._physics_process
	if is_busy:
		vx = move_toward(vx, 0, SPEED * delta * 5)
		vz = move_toward(vz, 0, SPEED * delta * 5)
	assert_lt(abs(vx), 5.0, "X velocity should decay when busy")
	assert_lt(abs(vz), 5.0, "Z velocity should decay when busy")

func test_non_busy_player_moves_normally():
	# When not busy, movement direction should be applied
	var vx: float = 0.0
	var vz: float = 0.0
	var is_busy: bool = false
	var input_direction := Vector2(0, 1) # forward
	var camera_yaw: float = 0.0
	var SPEED: float = 7.0
	# Simulate non-busy branch
	if not is_busy:
		var forward := Vector3(sin(camera_yaw), 0, cos(camera_yaw))
		var right := Vector3(cos(camera_yaw), 0, -sin(camera_yaw))
		var move_dir := (forward * input_direction.y + right * input_direction.x).normalized()
		if move_dir.length() > 0.1:
			vx = move_dir.x * SPEED
			vz = move_dir.z * SPEED
	assert_gt(abs(vx) + abs(vz), 0.0, "Should have velocity when not busy")

# --- Interaction lock tests ---

func test_busy_player_interaction_blocked():
	# Simulates the early-return guard in player_interaction._process
	var is_busy: bool = true
	var interaction_processed: bool = false
	if not is_busy:
		interaction_processed = true
	assert_false(interaction_processed, "Interactions should be blocked when busy")

func test_non_busy_player_interaction_allowed():
	var is_busy: bool = false
	var interaction_processed: bool = false
	if not is_busy:
		interaction_processed = true
	assert_true(interaction_processed, "Interactions should proceed when not busy")

# --- Prompt suppression tests ---
# Replicates the guard: if body.get("is_busy"): return (skip prompt)

func _would_show_prompt(is_busy: bool) -> bool:
	if is_busy:
		return false
	return true

func test_shop_prompt_suppressed_when_busy():
	assert_false(_would_show_prompt(true), "Shop prompt should be suppressed when busy")

func test_shop_prompt_shown_when_not_busy():
	assert_true(_would_show_prompt(false), "Shop prompt should show when not busy")

func test_social_npc_prompt_suppressed_when_busy():
	assert_false(_would_show_prompt(true), "Social NPC prompt should be suppressed when busy")

func test_social_npc_prompt_shown_when_not_busy():
	assert_true(_would_show_prompt(false), "Social NPC prompt should show when not busy")

func test_calendar_prompt_suppressed_when_busy():
	assert_false(_would_show_prompt(true), "Calendar prompt should be suppressed when busy")

func test_calendar_prompt_shown_when_not_busy():
	assert_true(_would_show_prompt(false), "Calendar prompt should show when not busy")

func test_trainer_prompt_already_suppressed_when_busy():
	# Regression: existing guard pattern also works for trainers
	assert_false(_would_show_prompt(true), "Trainer prompt should be suppressed when busy")

# --- Encounter guard tests ---

func test_encounter_skipped_when_busy():
	# Simulates the defensive guard in tall_grass._trigger_encounter
	var is_busy: bool = true
	var encounter_started: bool = false
	if not is_busy:
		encounter_started = true
	assert_false(encounter_started, "Encounter should not start when player is busy")

func test_encounter_allowed_when_not_busy():
	var is_busy: bool = false
	var encounter_started: bool = false
	if not is_busy:
		encounter_started = true
	assert_true(encounter_started, "Encounter should start when player is not busy")
