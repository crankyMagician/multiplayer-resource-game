class_name FishingMinigame
extends RefCounted

# Stardew Valley-style deterministic fishing simulation.
# Fish picks random targets, glides toward them, pauses, picks new targets.
# Both server (validation) and client (display) step through frames identically.

const SIM_FPS: int = 60
const SIM_DT: float = 1.0 / 60.0

const BAR_GRAVITY: float = -2.0
const BAR_LIFT: float = 5.0
const BAR_DAMPING: float = 0.85
const BAR_BOUNCE: float = 0.3

const CATCH_FILL_RATE: float = 0.55
const CATCH_DRAIN_RATE: float = 0.18
const INITIAL_CATCH_METER: float = 0.45


# --- Seeded PRNG (linear congruential) ---

static func _next_rng(state: int) -> int:
	# Advance PRNG state. Returns new state.
	return (state * 1103515245 + 12345) & 0x7FFFFFFF


static func _rng_float(state: int) -> float:
	# Convert state to float in [0.0, 1.0).
	return float(state) / float(0x7FFFFFFF)


# --- Difficulty mapping ---

static func _sdv_difficulty(difficulty: int) -> float:
	# Our 1-5 difficulty → Stardew 0-100 range.
	# 1→15, 2→35, 3→55, 4→75, 5→95
	return 10.0 + (difficulty - 1) * 20.0


# --- Fish state stepping (Stardew Valley algorithm) ---

static func step_fish(fish_pos: float, fish_speed: float, fish_target: float,
		fish_bias: float, rng_state: int, sdv_diff: float,
		movement_type: String) -> Dictionary:
	# Advances fish state by one frame. Returns updated state dict.
	# All values in 0.0-1.0 space.

	rng_state = _next_rng(rng_state)
	var r1: float = _rng_float(rng_state)
	rng_state = _next_rng(rng_state)
	var r2: float = _rng_float(rng_state)
	rng_state = _next_rng(rng_state)
	var r3: float = _rng_float(rng_state)
	rng_state = _next_rng(rng_state)
	var r4: float = _rng_float(rng_state)

	# Smooth fish picks targets less often
	var target_chance_divisor: float = 4000.0
	if movement_type == "smooth":
		target_chance_divisor = 10000.0

	# Random chance to pick a new target
	if r1 < sdv_diff / target_chance_divisor:
		var percent: float = sdv_diff / 100.0
		var offset: float = (r2 * 2.0 - 1.0) * percent
		fish_target = clampf(fish_pos + offset, 0.0, 1.0)

	# Dart: extra chance for big random jumps
	if movement_type == "dart":
		rng_state = _next_rng(rng_state)
		var r_dart: float = _rng_float(rng_state)
		if r_dart < sdv_diff / 3000.0:
			fish_target = clampf(r2, 0.05, 0.95)

	# Move toward target (target < 0 means idle — just dampen speed)
	if fish_target < 0.0:
		fish_speed *= 0.8
	elif absf(fish_pos - fish_target) > 0.005:
		var divisor: float = r3 * 20.0 + 10.0 + (100.0 - sdv_diff)
		var accel: float = (fish_target - fish_pos) / divisor
		fish_speed += (accel - fish_speed) / 5.0  # dampening
	else:
		# Near target — chance to pick a nearby one, otherwise idle
		if r4 < sdv_diff / 2000.0:
			var small_offset: float = (r2 * 2.0 - 1.0) * 0.1
			fish_target = clampf(fish_pos + small_offset, 0.0, 1.0)
		else:
			fish_target = -1.0  # idle
			fish_speed *= 0.8

	# Behavior biases (sinker = toward 0/bottom, floater = toward 1/top)
	match movement_type:
		"sinker":
			fish_bias = clampf(fish_bias - 0.002, -0.03, 0.03)
		"floater":
			fish_bias = clampf(fish_bias + 0.002, -0.03, 0.03)
		_:
			fish_bias *= 0.95

	fish_pos += fish_speed + fish_bias
	fish_pos = clampf(fish_pos, 0.0, 1.0)

	# Stop at edges
	if fish_pos <= 0.0 or fish_pos >= 1.0:
		fish_speed = 0.0

	return {
		"pos": fish_pos,
		"speed": fish_speed,
		"target": fish_target,
		"bias": fish_bias,
		"rng": rng_state,
	}


# --- Initial fish state ---

static func init_fish_state(seed_val: int, movement_type: String) -> Dictionary:
	var start_pos: float = 0.5
	if movement_type == "sinker":
		start_pos = 0.3
	elif movement_type == "floater":
		start_pos = 0.7
	return {
		"pos": start_pos,
		"speed": 0.0,
		"target": start_pos,
		"bias": 0.0,
		"rng": seed_val & 0x7FFFFFFF,
	}


# --- Server simulation (replay) ---

static func simulate(seed_val: int, difficulty: int, movement_type: String,
		bar_size: float, time_limit: float,
		input_log: PackedFloat32Array) -> Dictionary:
	var catch_meter: float = INITIAL_CATCH_METER
	var bar_pos: float = 0.5
	var bar_velocity: float = 0.0
	var holding: bool = false
	var input_idx: int = 0
	var perfect: bool = true
	var ever_increased: bool = false

	var total_frames: int = int(time_limit * SIM_FPS)
	var sdv_diff: float = _sdv_difficulty(difficulty)

	# Initialize fish state
	var fish: Dictionary = init_fish_state(seed_val, movement_type)

	for frame in total_frames:
		var t: float = frame * SIM_DT

		# Process input events
		while input_idx < input_log.size():
			var event_time: float = input_log[input_idx]
			if event_time > t:
				break
			if input_idx % 2 == 0:
				holding = true
			else:
				holding = false
			input_idx += 1

		# Step fish
		fish = step_fish(fish["pos"], fish["speed"], fish["target"],
				fish["bias"], fish["rng"], sdv_diff, movement_type)

		# Physics-based bar movement
		if holding:
			bar_velocity += BAR_LIFT * SIM_DT
		else:
			bar_velocity += BAR_GRAVITY * SIM_DT
		bar_velocity *= BAR_DAMPING
		bar_pos += bar_velocity * SIM_DT

		if bar_pos < 0.0:
			bar_pos = 0.0
			bar_velocity = absf(bar_velocity) * BAR_BOUNCE
		if bar_pos > 1.0:
			bar_pos = 1.0
			bar_velocity = 0.0

		# Check overlap
		var half_bar: float = bar_size / 2.0
		var overlaps: bool = absf(fish["pos"] - bar_pos) <= half_bar

		# Update catch meter
		if overlaps:
			var prev_meter: float = catch_meter
			catch_meter += CATCH_FILL_RATE * SIM_DT
			if catch_meter > prev_meter and catch_meter > 0.001:
				ever_increased = true
		else:
			var prev_meter: float = catch_meter
			catch_meter -= CATCH_DRAIN_RATE * SIM_DT
			if ever_increased and catch_meter < prev_meter:
				perfect = false
		catch_meter = clampf(catch_meter, 0.0, 1.0)

		if catch_meter >= 1.0:
			return {"success": true, "catch_pct": 1.0, "perfect": perfect}

	return {"success": false, "catch_pct": catch_meter, "perfect": false}
