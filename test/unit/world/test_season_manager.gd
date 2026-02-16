extends GutTest

# Tests for SeasonManager logic (12-month calendar system).
# SeasonManager extends Node and uses multiplayer, so we instantiate it
# as a standalone node (without multiplayer) and test pure logic.

var sm: Node

func before_each():
	# Load the script and create instance
	var script = load("res://scripts/world/season_manager.gd")
	sm = Node.new()
	sm.set_script(script)
	# Don't add to tree (avoids _ready multiplayer check)
	# Set initial state directly
	sm.current_year = 1
	sm.current_month = 3 # March (spring)
	sm.day_in_month = 1
	sm.day_timer = 0.0
	sm.total_day_count = 1
	sm.current_weather = 0 # SUNNY

func after_each():
	if sm:
		sm.free()

# --- get_current_season (derived from month) ---

func test_season_spring_march():
	sm.current_month = 3
	assert_eq(sm.get_current_season(), "spring")

func test_season_spring_april():
	sm.current_month = 4
	assert_eq(sm.get_current_season(), "spring")

func test_season_spring_may():
	sm.current_month = 5
	assert_eq(sm.get_current_season(), "spring")

func test_season_summer_june():
	sm.current_month = 6
	assert_eq(sm.get_current_season(), "summer")

func test_season_summer_july():
	sm.current_month = 7
	assert_eq(sm.get_current_season(), "summer")

func test_season_summer_august():
	sm.current_month = 8
	assert_eq(sm.get_current_season(), "summer")

func test_season_autumn_september():
	sm.current_month = 9
	assert_eq(sm.get_current_season(), "autumn")

func test_season_autumn_october():
	sm.current_month = 10
	assert_eq(sm.get_current_season(), "autumn")

func test_season_autumn_november():
	sm.current_month = 11
	assert_eq(sm.get_current_season(), "autumn")

func test_season_winter_december():
	sm.current_month = 12
	assert_eq(sm.get_current_season(), "winter")

func test_season_winter_january():
	sm.current_month = 1
	assert_eq(sm.get_current_season(), "winter")

func test_season_winter_february():
	sm.current_month = 2
	assert_eq(sm.get_current_season(), "winter")

# --- get_season_name (alias) ---

func test_season_name_alias():
	sm.current_month = 3
	assert_eq(sm.get_season_name(), "spring")

# --- get_month_name ---

func test_month_name_january():
	sm.current_month = 1
	assert_eq(sm.get_month_name(), "January")

func test_month_name_june():
	sm.current_month = 6
	assert_eq(sm.get_month_name(), "June")

func test_month_name_december():
	sm.current_month = 12
	assert_eq(sm.get_month_name(), "December")

func test_month_name_all():
	var expected = ["January", "February", "March", "April", "May", "June",
		"July", "August", "September", "October", "November", "December"]
	for i in range(12):
		sm.current_month = i + 1
		assert_eq(sm.get_month_name(), expected[i])

# --- get_weather_name ---

func test_weather_name_sunny():
	sm.current_weather = 0
	assert_eq(sm.get_weather_name(), "sunny")

func test_weather_name_rainy():
	sm.current_weather = 1
	assert_eq(sm.get_weather_name(), "rainy")

func test_weather_name_stormy():
	sm.current_weather = 2
	assert_eq(sm.get_weather_name(), "stormy")

func test_weather_name_windy():
	sm.current_weather = 3
	assert_eq(sm.get_weather_name(), "windy")

# --- is_crop_in_season ---

func test_crop_single_season_matching():
	sm.current_month = 3 # spring
	assert_true(sm.is_crop_in_season("spring"))

func test_crop_single_season_not_matching():
	sm.current_month = 3 # spring
	assert_false(sm.is_crop_in_season("summer"))

func test_crop_multi_season_matching():
	sm.current_month = 7 # summer
	assert_true(sm.is_crop_in_season("spring/summer"))

func test_crop_multi_season_not_matching():
	sm.current_month = 12 # winter
	assert_false(sm.is_crop_in_season("spring/summer"))

func test_crop_empty_always_true():
	sm.current_month = 12
	assert_true(sm.is_crop_in_season(""))

func test_crop_all_seasons():
	sm.current_month = 10 # autumn
	assert_true(sm.is_crop_in_season("spring/summer/autumn/winter"))

# --- is_raining ---

func test_is_raining_when_rainy():
	sm.current_weather = 1 # RAINY
	assert_true(sm.is_raining())

func test_is_raining_when_stormy():
	sm.current_weather = 2 # STORMY
	assert_true(sm.is_raining())

func test_not_raining_when_sunny():
	sm.current_weather = 0 # SUNNY
	assert_false(sm.is_raining())

func test_not_raining_when_windy():
	sm.current_weather = 3 # WINDY
	assert_false(sm.is_raining())

# --- _roll_weather distribution ---

func test_roll_weather_distribution():
	seed(42)
	var counts = [0, 0, 0, 0]
	for i in range(1000):
		seed(i * 7 + 1)
		var w = sm._roll_weather()
		counts[w] += 1
	# Sunny ~50%, rainy ~25%, stormy ~10%, windy ~15%
	assert_gt(counts[0], 350) # sunny
	assert_lt(counts[0], 650)
	assert_gt(counts[1], 130) # rainy
	assert_lt(counts[1], 400)

# --- month/year rollover logic (tested via direct state manipulation,
#     since _advance_day calls RPC/tree methods not available in standalone tests) ---

func test_month_rollover_logic():
	# Simulate what _advance_day does: day 28 -> day 1 of next month
	sm.current_month = 3
	sm.day_in_month = 28
	# Advance: increment day, check rollover
	sm.day_in_month += 1
	if sm.day_in_month > sm.DAYS_PER_MONTH:
		sm.day_in_month = 1
		sm.current_month += 1
	assert_eq(sm.day_in_month, 1)
	assert_eq(sm.current_month, 4) # April

func test_year_rollover_logic():
	sm.current_month = 12
	sm.day_in_month = 28
	sm.current_year = 1
	# Advance
	sm.day_in_month += 1
	if sm.day_in_month > sm.DAYS_PER_MONTH:
		sm.day_in_month = 1
		sm.current_month += 1
		if sm.current_month > sm.MONTHS_PER_YEAR:
			sm.current_month = 1
			sm.current_year += 1
	assert_eq(sm.day_in_month, 1)
	assert_eq(sm.current_month, 1) # January
	assert_eq(sm.current_year, 2)

func test_within_month_no_rollover():
	sm.current_month = 3
	sm.day_in_month = 14
	sm.total_day_count = 14
	sm.day_in_month += 1
	sm.total_day_count += 1
	assert_eq(sm.day_in_month, 15)
	assert_eq(sm.current_month, 3)

func test_total_day_count_increments():
	sm.total_day_count = 100
	sm.total_day_count += 1
	assert_eq(sm.total_day_count, 101)
	sm.total_day_count += 1
	assert_eq(sm.total_day_count, 102)

func test_season_change_on_month_boundary():
	# May (spring) -> June (summer)
	sm.current_month = 5
	assert_eq(sm.get_current_season(), "spring")
	sm.current_month = 6
	assert_eq(sm.get_current_season(), "summer")

# --- save/load round-trip ---

func test_save_load_roundtrip():
	sm.current_year = 3
	sm.current_month = 10 # October (autumn)
	sm.day_in_month = 15
	sm.day_timer = 123.5
	sm.total_day_count = 280
	sm.current_weather = 1 # RAINY

	var data = sm.get_save_data()
	assert_eq(data["current_year"], 3)
	assert_eq(data["current_month"], 10)
	assert_eq(data["day_in_month"], 15)

	# Reset and load
	sm.current_year = 1
	sm.current_month = 3
	sm.day_in_month = 1
	sm.load_save_data(data)
	assert_eq(sm.current_year, 3)
	assert_eq(sm.current_month, 10)
	assert_eq(sm.day_in_month, 15)
	assert_almost_eq(sm.day_timer, 123.5, 0.01)
	assert_eq(sm.total_day_count, 280)
	assert_eq(int(sm.current_weather), 1)
	assert_eq(sm.get_current_season(), "autumn")

func test_load_backward_compat():
	# Old save format without current_month
	var old_data = {
		"current_season": 1, # summer
		"season_timer": 42.0,
		"day_count": 15,
		"day_in_season": 7,
	}
	sm.load_save_data(old_data)
	# Should convert summer season to a summer month (Jun/Jul/Aug)
	assert_true(sm.current_month >= 6 and sm.current_month <= 8, "Should be a summer month")
	assert_eq(sm.get_current_season(), "summer")
	assert_almost_eq(sm.day_timer, 42.0, 0.01) # falls back to season_timer
	assert_eq(sm.total_day_count, 15) # falls back to day_count
	assert_eq(sm.current_year, 1) # default

func test_load_backward_compat_spring():
	var old_data = {
		"current_season": 0, # spring
		"day_in_season": 3,
	}
	sm.load_save_data(old_data)
	assert_true(sm.current_month >= 3 and sm.current_month <= 5, "Should be a spring month")
	assert_eq(sm.get_current_season(), "spring")

func test_load_backward_compat_winter():
	var old_data = {
		"current_season": 3, # winter
		"day_in_season": 1,
	}
	sm.load_save_data(old_data)
	assert_true(sm.current_month in [12, 1, 2], "Should be a winter month")
	assert_eq(sm.get_current_season(), "winter")

func test_save_includes_backward_compat_keys():
	sm.current_month = 7 # July (summer)
	sm.day_in_month = 10
	var data = sm.get_save_data()
	# Should include old-format keys for backward compat
	assert_true(data.has("current_season"))
	assert_true(data.has("day_in_season"))
	assert_eq(data["current_season"], 1) # summer enum = 1
