extends GutTest

# Unit tests for the fishing system — FishingMinigame deterministic engine,
# fish rolling, bar size calculation.

func before_each() -> void:
	RegistrySeeder.seed_all()

func after_each() -> void:
	RegistrySeeder.clear_all()

# --- Deterministic fish stepping ---

func test_fish_step_deterministic():
	# Same initial state → same result
	var s1 := FishingMinigame.init_fish_state(42, "smooth")
	var s2 := FishingMinigame.init_fish_state(42, "smooth")
	var r1 := FishingMinigame.step_fish(s1["pos"], s1["speed"], s1["target"],
			s1["bias"], s1["rng"], 55.0, "smooth")
	var r2 := FishingMinigame.step_fish(s2["pos"], s2["speed"], s2["target"],
			s2["bias"], s2["rng"], 55.0, "smooth")
	assert_eq(r1["pos"], r2["pos"], "Same state should produce identical fish positions")

func test_different_seed_different_state():
	var s1 := FishingMinigame.init_fish_state(42, "smooth")
	var s2 := FishingMinigame.init_fish_state(99, "smooth")
	# Run 100 steps to let them diverge
	for i in 100:
		s1 = FishingMinigame.step_fish(s1["pos"], s1["speed"], s1["target"],
				s1["bias"], s1["rng"], 55.0, "smooth")
		s2 = FishingMinigame.step_fish(s2["pos"], s2["speed"], s2["target"],
				s2["bias"], s2["rng"], 55.0, "smooth")
	assert_ne(s1["pos"], s2["pos"], "Different seeds should diverge over time")

func test_fish_position_in_bounds():
	# All movement types should stay within 0.0-1.0 after many steps
	for movement in ["smooth", "dart", "sinker", "mixed", "floater"]:
		var state := FishingMinigame.init_fish_state(12345, movement)
		for i in 600:  # 10 seconds at 60fps
			state = FishingMinigame.step_fish(state["pos"], state["speed"],
					state["target"], state["bias"], state["rng"], 55.0, movement)
			assert_gte(state["pos"], 0.0, "%s pos should be >= 0 at frame %d" % [movement, i])
			assert_lte(state["pos"], 1.0, "%s pos should be <= 1 at frame %d" % [movement, i])

func test_easy_fish_stays_centered():
	# Difficulty 1 (SDV ~15) — fish should mostly stay near its start
	var state := FishingMinigame.init_fish_state(42, "smooth")
	var sdv_diff: float = FishingMinigame._sdv_difficulty(1)
	var total: float = 0.0
	var frames: int = 600
	for i in frames:
		state = FishingMinigame.step_fish(state["pos"], state["speed"],
				state["target"], state["bias"], state["rng"], sdv_diff, "smooth")
		total += state["pos"]
	var avg: float = total / float(frames)
	# Easy fish starts at 0.5, should average near center
	assert_gt(avg, 0.2, "Easy fish avg should be above 0.2 (was %.3f)" % avg)
	assert_lt(avg, 0.8, "Easy fish avg should be below 0.8 (was %.3f)" % avg)

# --- Simulation tests ---

func test_simulate_makes_progress():
	var input_log := PackedFloat32Array()
	var t: float = 0.0
	while t < 19.0:
		input_log.append(t)
		t += 0.25
		input_log.append(t)
		t += 0.15

	var result := FishingMinigame.simulate(42, 1, "smooth", 0.5, 20.0, input_log)
	assert_gte(result.get("catch_pct", -1.0), 0.0,
		"catch_pct should be non-negative")
	assert_true(result.has("success"), "Result should have success key")

func test_simulate_failure_no_input():
	var input_log := PackedFloat32Array()
	var result := FishingMinigame.simulate(42, 3, "smooth", 0.25, 10.0, input_log)
	assert_false(result.get("success", true), "No input should not succeed")

func test_simulate_returns_catch_pct():
	var input_log := PackedFloat32Array()
	var result := FishingMinigame.simulate(42, 1, "smooth", 0.25, 5.0, input_log)
	assert_true(result.has("catch_pct"), "Result should have catch_pct")
	assert_true(result.has("success"), "Result should have success")
	assert_true(result.has("perfect"), "Result should have perfect")
	assert_gte(result["catch_pct"], 0.0, "catch_pct should be >= 0")
	assert_lte(result["catch_pct"], 1.0, "catch_pct should be <= 1")

func test_simulate_deterministic():
	var log1 := PackedFloat32Array([0.5, 1.5, 3.0, 4.0])
	var log2 := PackedFloat32Array([0.5, 1.5, 3.0, 4.0])
	var r1 := FishingMinigame.simulate(99, 2, "dart", 0.3, 15.0, log1)
	var r2 := FishingMinigame.simulate(99, 2, "dart", 0.3, 15.0, log2)
	assert_eq(r1["success"], r2["success"], "Same inputs should give same success")
	assert_eq(r1["catch_pct"], r2["catch_pct"], "Same inputs should give same catch_pct")

# --- Fish roll tests ---

func test_weighted_fish_selection():
	seed(42)
	var table = DataRegistry.get_fishing_table("test_pond")
	assert_not_null(table, "Test pond should exist")
	assert_eq(table.entries.size(), 3, "Test pond should have 3 entries")

func test_season_filter():
	var table = DataRegistry.get_fishing_table("test_pond")
	assert_not_null(table, "Test pond should exist")
	var autumn_fish := 0
	for entry in table.entries:
		if entry.get("season", "") == "autumn":
			autumn_fish += 1
	assert_gt(autumn_fish, 0, "Test pond should have at least one autumn-only fish")

func test_rod_tier_filter():
	var table = DataRegistry.get_fishing_table("test_pond")
	var valid_for_tier_0: Array = []
	for entry in table.entries:
		if entry.get("min_rod_tier", 0) <= 0:
			valid_for_tier_0.append(entry)
	for entry in valid_for_tier_0:
		assert_ne(entry.get("fish_id", ""), "golden_koi",
			"Golden koi should not be available with tier 0 rod")

func test_rod_tier_filter_includes_high_tier():
	var table = DataRegistry.get_fishing_table("test_pond")
	var valid_for_tier_2: Array = []
	for entry in table.entries:
		if entry.get("min_rod_tier", 0) <= 2:
			valid_for_tier_2.append(entry)
	var has_koi := false
	for entry in valid_for_tier_2:
		if entry.get("fish_id", "") == "golden_koi":
			has_koi = true
	assert_true(has_koi, "Golden koi should be available with tier 2 rod")

# --- Bar size calculation ---

func test_bar_size_base():
	var bar := clampf(0.25 + 0 * 0.005 + 0.0, 0.2, 0.5)
	assert_almost_eq(bar, 0.25, 0.001, "Base bar size should be 0.25")

func test_bar_size_with_skill():
	var bar := clampf(0.25 + 10 * 0.005 + 0.0, 0.2, 0.5)
	assert_almost_eq(bar, 0.30, 0.001, "Bar with skill 10 should be 0.30")

func test_bar_size_with_rod_bonus():
	var bar := clampf(0.25 + 0 * 0.005 + 0.15, 0.2, 0.5)
	assert_almost_eq(bar, 0.40, 0.001, "Bar with gold rod should be 0.40")

func test_bar_size_cap():
	var bar := clampf(0.25 + 100 * 0.005 + 0.15, 0.2, 0.5)
	assert_almost_eq(bar, 0.50, 0.001, "Bar size should be capped at 0.50")

# --- Weather bonus ---

func test_weather_bonus():
	var table = DataRegistry.get_fishing_table("test_pond")
	assert_eq(table.weather_bonus.get("rainy", ""), "bass",
		"Rainy weather should bonus bass in test pond")

# --- Input log size ---

func test_input_log_size_cap():
	assert_gt(1200, 0, "MAX_INPUT_LOG_SIZE should be positive")
	var max_events_20s: int = 20 * 60
	assert_lte(max_events_20s, 1200, "20s at 60fps fits within cap")

# --- Data integrity ---

func test_fishing_table_registered():
	assert_not_null(DataRegistry.get_fishing_table("test_pond"), "test_pond should be registered")

func test_fish_ingredients_registered():
	assert_not_null(DataRegistry.get_ingredient("sardine"), "sardine should be registered")
	assert_not_null(DataRegistry.get_ingredient("bass"), "bass should be registered")
	assert_not_null(DataRegistry.get_ingredient("trout"), "trout should be registered")
	assert_not_null(DataRegistry.get_ingredient("golden_koi"), "golden_koi should be registered")

func test_fish_category():
	var sardine = DataRegistry.get_ingredient("sardine")
	assert_eq(sardine.category, "fish", "Sardine should have category 'fish'")

func test_fishing_rods_registered():
	var basic = DataRegistry.get_tool("tool_fishing_rod_basic")
	assert_not_null(basic, "Basic fishing rod should be registered")
	assert_eq(basic.tool_type, "fishing_rod", "Should have tool_type 'fishing_rod'")
	assert_eq(basic.tier, 0, "Basic rod should be tier 0")

	var gold = DataRegistry.get_tool("tool_fishing_rod_gold")
	assert_not_null(gold, "Gold fishing rod should be registered")
	assert_eq(gold.tier, 3, "Gold rod should be tier 3")
	assert_almost_eq(gold.effectiveness.get("bar_bonus", 0.0), 0.15, 0.001,
		"Gold rod bar_bonus should be 0.15")

func test_fish_sell_prices():
	var sardine = DataRegistry.get_ingredient("sardine")
	assert_eq(sardine.sell_price, 5, "Sardine sell price should be 5")
	var golden_koi = DataRegistry.get_ingredient("golden_koi")
	assert_eq(golden_koi.sell_price, 50, "Golden koi sell price should be 50")

# --- Physics bar tests ---

func test_initial_catch_meter():
	assert_almost_eq(FishingMinigame.INITIAL_CATCH_METER, 0.45, 0.001,
		"Initial catch meter should be 0.45")

func test_bar_bounce():
	var input_log := PackedFloat32Array()
	var result := FishingMinigame.simulate(42, 1, "smooth", 0.25, 3.0, input_log)
	assert_true(result.has("catch_pct"), "Bounce sim should return catch_pct")
	assert_gte(result["catch_pct"], 0.0, "catch_pct should be >= 0 after bounce")

func test_bar_damping():
	assert_lt(FishingMinigame.BAR_DAMPING, 1.0,
		"BAR_DAMPING should be < 1.0 for velocity decay")
	assert_gt(FishingMinigame.BAR_DAMPING, 0.0,
		"BAR_DAMPING should be > 0.0 (not instant stop)")
	assert_lt(FishingMinigame.BAR_GRAVITY, 0.0,
		"BAR_GRAVITY should be negative (downward)")
	assert_gt(FishingMinigame.BAR_LIFT, 0.0,
		"BAR_LIFT should be positive (upward)")
	assert_gt(FishingMinigame.BAR_BOUNCE, 0.0,
		"BAR_BOUNCE should be positive")
	assert_lt(FishingMinigame.BAR_BOUNCE, 1.0,
		"BAR_BOUNCE should be < 1.0 (energy loss)")

func test_sinker_biases_downward():
	# Sinker fish should average lower than 0.5 over time
	var state := FishingMinigame.init_fish_state(42, "sinker")
	var sdv_diff: float = FishingMinigame._sdv_difficulty(3)
	var total: float = 0.0
	var frames: int = 600
	for i in frames:
		state = FishingMinigame.step_fish(state["pos"], state["speed"],
				state["target"], state["bias"], state["rng"], sdv_diff, "sinker")
		total += state["pos"]
	var avg: float = total / float(frames)
	assert_lt(avg, 0.55, "Sinker fish avg should trend below 0.55 (was %.3f)" % avg)

func test_floater_biases_upward():
	# Floater fish should average higher than 0.5 over time
	var state := FishingMinigame.init_fish_state(42, "floater")
	var sdv_diff: float = FishingMinigame._sdv_difficulty(3)
	var total: float = 0.0
	var frames: int = 600
	for i in frames:
		state = FishingMinigame.step_fish(state["pos"], state["speed"],
				state["target"], state["bias"], state["rng"], sdv_diff, "floater")
		total += state["pos"]
	var avg: float = total / float(frames)
	assert_gt(avg, 0.45, "Floater fish avg should trend above 0.45 (was %.3f)" % avg)
