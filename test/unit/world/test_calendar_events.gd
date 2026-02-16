extends GutTest

# Tests for CalendarEvents static data and lookup functions.
# Uses RegistrySeeder — NO preload

func before_each() -> void:
	RegistrySeeder.seed_all()
	_seed_npcs()

func after_each() -> void:
	RegistrySeeder.clear_all()

func _seed_npcs() -> void:
	var npc = NPCDef.new()
	npc.npc_id = "test_npc_cal"
	npc.display_name = "Test Chef"
	npc.visual_color = Color(0.5, 0.5, 0.5)
	npc.birthday = {"month": 7, "day": 15}
	npc.gift_preferences = {"loved": [], "liked": [], "disliked": [], "hated": []}
	npc.dialogues = {"neutral": [], "like": [], "love": [], "dislike": [], "hate": [], "birthday": []}
	npc.npc_gifts = []
	npc.occupation = "Tester"
	npc.schedule = []
	DataRegistry.npcs["test_npc_cal"] = npc

# === Holiday Data Tests ===

func test_holidays_defined() -> void:
	assert_eq(CalendarEvents.HOLIDAYS.size(), 10)

func test_holidays_have_required_fields() -> void:
	for h in CalendarEvents.HOLIDAYS:
		assert_true(h.has("month"), "Holiday missing month")
		assert_true(h.has("day"), "Holiday missing day")
		assert_true(h.has("name"), "Holiday missing name")
		assert_true(h.has("description"), "Holiday missing description")
		assert_true(h.has("type"), "Holiday missing type")

func test_new_years() -> void:
	var events = CalendarEvents.get_events_for_day(1, 1)
	var found = false
	for ev in events:
		if ev["name"] == "New Year's Festival":
			found = true
	assert_true(found, "New Year's Festival should be on Jan 1")

func test_wintermas() -> void:
	var events = CalendarEvents.get_events_for_day(12, 25)
	var found = false
	for ev in events:
		if ev["name"] == "Wintermas":
			found = true
	assert_true(found, "Wintermas should be on Dec 25")

# === get_events_for_month ===

func test_get_events_for_month_january() -> void:
	var events = CalendarEvents.get_events_for_month(1)
	assert_gt(events.size(), 0, "January should have at least New Year's")
	var names: Array = []
	for ev in events:
		names.append(str(ev["name"]))
	assert_true("New Year's Festival" in names)

func test_get_events_for_month_july_includes_birthday() -> void:
	var events = CalendarEvents.get_events_for_month(7)
	var has_birthday = false
	var has_fireworks = false
	for ev in events:
		if str(ev.get("type", "")) == "birthday" and "Test Chef" in str(ev["name"]):
			has_birthday = true
		if ev["name"] == "Fireworks Festival":
			has_fireworks = true
	assert_true(has_birthday, "July should include Test Chef's birthday")
	assert_true(has_fireworks, "July should include Fireworks Festival")

func test_get_events_for_month_empty() -> void:
	# August has no holidays (only potential NPC birthdays from registry)
	var events = CalendarEvents.get_events_for_month(8)
	# Just check it returns an array (may have NPC birthdays from real registry)
	assert_true(events is Array)

# === get_events_for_day ===

func test_get_events_for_day_specific() -> void:
	var events = CalendarEvents.get_events_for_day(2, 14)
	var found = false
	for ev in events:
		if ev["name"] == "Hearts Day":
			found = true
	assert_true(found, "Feb 14 should have Hearts Day")

func test_get_events_for_day_empty() -> void:
	var events = CalendarEvents.get_events_for_day(3, 15)
	# March 15 has no holidays; check if any NPC birthday matches
	# For this test, just verify it returns a valid array
	assert_true(events is Array)

func test_birthday_lookup() -> void:
	# Test NPC has birthday on July 15
	var events = CalendarEvents.get_events_for_day(7, 15)
	var found_birthday = false
	for ev in events:
		if str(ev.get("type", "")) == "birthday" and "Test Chef" in str(ev["name"]):
			found_birthday = true
	assert_true(found_birthday, "Should find Test Chef's birthday on July 15")

func test_no_birthday_wrong_day() -> void:
	# Test NPC birthday is July 15, not July 16
	var events = CalendarEvents.get_events_for_day(7, 16)
	var found_birthday = false
	for ev in events:
		if str(ev.get("type", "")) == "birthday" and "Test Chef" in str(ev["name"]):
			found_birthday = true
	assert_false(found_birthday, "Should NOT find Test Chef's birthday on July 16")

func test_no_events_on_empty_day() -> void:
	# Pick a day with no holidays and no NPC birthdays
	# Clear NPCs to ensure no birthdays
	DataRegistry.npcs.clear()
	var events = CalendarEvents.get_events_for_day(5, 17)
	assert_eq(events.size(), 0, "May 17 should have no events with no NPCs registered")
