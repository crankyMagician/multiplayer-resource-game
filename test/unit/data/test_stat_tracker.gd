extends GutTest

# Tests for StatTracker static utility class

const PEER_ID = 99
var _test_store: Dictionary = {}

func before_each():
	_test_store = {}
	_test_store[PEER_ID] = {
		"stats": {},
		"compendium": {"items": [], "creatures_seen": [], "creatures_owned": []}
	}
	StatTracker._store = _test_store

func after_each():
	StatTracker._store = {}

# --- increment ---

func test_increment_basic():
	StatTracker.increment(PEER_ID, "battles_fought")
	assert_eq(_test_store[PEER_ID]["stats"]["battles_fought"], 1)

func test_increment_accumulates():
	StatTracker.increment(PEER_ID, "battles_fought", 3)
	StatTracker.increment(PEER_ID, "battles_fought", 2)
	assert_eq(_test_store[PEER_ID]["stats"]["battles_fought"], 5)

func test_increment_custom_amount():
	StatTracker.increment(PEER_ID, "total_xp_gained", 500)
	assert_eq(_test_store[PEER_ID]["stats"]["total_xp_gained"], 500)

func test_increment_missing_peer():
	StatTracker.increment(12345, "battles_fought")
	assert_true(true, "No crash on missing peer")

func test_increment_creates_stats_dict_if_missing():
	_test_store[PEER_ID].erase("stats")
	StatTracker.increment(PEER_ID, "battles_fought")
	assert_eq(_test_store[PEER_ID]["stats"]["battles_fought"], 1)

# --- increment_species ---

func test_increment_species_basic():
	StatTracker.increment_species(PEER_ID, "species_encounters", "rice_ball")
	assert_eq(_test_store[PEER_ID]["stats"]["species_encounters"]["rice_ball"], 1)

func test_increment_species_accumulates():
	StatTracker.increment_species(PEER_ID, "species_encounters", "rice_ball", 3)
	StatTracker.increment_species(PEER_ID, "species_encounters", "rice_ball", 2)
	assert_eq(_test_store[PEER_ID]["stats"]["species_encounters"]["rice_ball"], 5)

func test_increment_species_multiple():
	StatTracker.increment_species(PEER_ID, "species_encounters", "rice_ball")
	StatTracker.increment_species(PEER_ID, "species_encounters", "flame_pepper")
	var encounters = _test_store[PEER_ID]["stats"]["species_encounters"]
	assert_eq(encounters["rice_ball"], 1)
	assert_eq(encounters["flame_pepper"], 1)

# --- unlock_compendium_item ---

func test_unlock_compendium_item():
	StatTracker.unlock_compendium_item(PEER_ID, "wheat")
	assert_has(_test_store[PEER_ID]["compendium"]["items"], "wheat")

func test_unlock_compendium_item_no_duplicates():
	StatTracker.unlock_compendium_item(PEER_ID, "wheat")
	StatTracker.unlock_compendium_item(PEER_ID, "wheat")
	var items = _test_store[PEER_ID]["compendium"]["items"]
	assert_eq(items.size(), 1)

func test_unlock_compendium_item_multiple():
	StatTracker.unlock_compendium_item(PEER_ID, "wheat")
	StatTracker.unlock_compendium_item(PEER_ID, "sugar")
	var items = _test_store[PEER_ID]["compendium"]["items"]
	assert_eq(items.size(), 2)

# --- unlock_creature_seen ---

func test_unlock_creature_seen():
	StatTracker.unlock_creature_seen(PEER_ID, "rice_ball")
	assert_has(_test_store[PEER_ID]["compendium"]["creatures_seen"], "rice_ball")

func test_unlock_creature_seen_no_duplicates():
	StatTracker.unlock_creature_seen(PEER_ID, "rice_ball")
	StatTracker.unlock_creature_seen(PEER_ID, "rice_ball")
	assert_eq(_test_store[PEER_ID]["compendium"]["creatures_seen"].size(), 1)

# --- unlock_creature_owned ---

func test_unlock_creature_owned():
	StatTracker.unlock_creature_owned(PEER_ID, "rice_ball")
	assert_has(_test_store[PEER_ID]["compendium"]["creatures_owned"], "rice_ball")

func test_unlock_creature_owned_also_marks_seen():
	StatTracker.unlock_creature_owned(PEER_ID, "rice_ball")
	assert_has(_test_store[PEER_ID]["compendium"]["creatures_seen"], "rice_ball")
	assert_has(_test_store[PEER_ID]["compendium"]["creatures_owned"], "rice_ball")

func test_unlock_creature_owned_no_duplicates():
	StatTracker.unlock_creature_owned(PEER_ID, "rice_ball")
	StatTracker.unlock_creature_owned(PEER_ID, "rice_ball")
	assert_eq(_test_store[PEER_ID]["compendium"]["creatures_owned"].size(), 1)
	assert_eq(_test_store[PEER_ID]["compendium"]["creatures_seen"].size(), 1)

func test_unlock_creature_owned_after_seen():
	StatTracker.unlock_creature_seen(PEER_ID, "rice_ball")
	StatTracker.unlock_creature_owned(PEER_ID, "rice_ball")
	assert_eq(_test_store[PEER_ID]["compendium"]["creatures_seen"].size(), 1)
	assert_eq(_test_store[PEER_ID]["compendium"]["creatures_owned"].size(), 1)

# --- missing peer safety ---

func test_compendium_item_missing_peer():
	StatTracker.unlock_compendium_item(12345, "wheat")
	assert_true(true, "No crash on missing peer")

func test_creature_seen_missing_peer():
	StatTracker.unlock_creature_seen(12345, "rice_ball")
	assert_true(true, "No crash on missing peer")

func test_creature_owned_missing_peer():
	StatTracker.unlock_creature_owned(12345, "rice_ball")
	assert_true(true, "No crash on missing peer")

func test_species_increment_missing_peer():
	StatTracker.increment_species(12345, "species_encounters", "rice_ball")
	assert_true(true, "No crash on missing peer")
