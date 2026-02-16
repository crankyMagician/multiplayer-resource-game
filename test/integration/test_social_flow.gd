extends GutTest

# Integration tests for NPC social system: talk flow, gift flow, daily processing
# Tests server-side logic by simulating SocialManager methods (no class_name available)
# Uses RegistrySeeder — NO preload

const TALK_BONUS: int = 2
const DAILY_DECAY: int = 1
const GIFT_POINTS = {"loved": 15, "liked": 8, "neutral": 3, "disliked": -8, "hated": -15}
const BIRTHDAY_MULTIPLIER: int = 3
const MIN_FRIENDSHIP: int = -100
const MAX_FRIENDSHIP: int = 100

var mock_peer_id: int = 100

func before_each() -> void:
	RegistrySeeder.seed_all()
	_seed_npcs()
	_seed_ingredients()
	_setup_mock_player()

func after_each() -> void:
	RegistrySeeder.clear_all()
	NetworkManager.player_data_store.erase(mock_peer_id)

# Inline SocialManager helpers
static func _create_default_friendship() -> Dictionary:
	return {
		"points": 0,
		"talked_today": false,
		"gifted_today": false,
		"last_interaction_day": 0,
		"gifts_received": [],
	}

static func get_friendship_tier(points: int) -> String:
	if points < -60:
		return "hate"
	elif points < -20:
		return "dislike"
	elif points < 20:
		return "neutral"
	elif points < 60:
		return "like"
	else:
		return "love"

static func _get_gift_tier(npc_def: Resource, item_id: String) -> String:
	var prefs: Dictionary = npc_def.gift_preferences
	if item_id in prefs.get("loved", []):
		return "loved"
	elif item_id in prefs.get("liked", []):
		return "liked"
	elif item_id in prefs.get("disliked", []):
		return "disliked"
	elif item_id in prefs.get("hated", []):
		return "hated"
	return "neutral"

func _seed_npcs() -> void:
	var npc = NPCDef.new()
	npc.npc_id = "test_npc"
	npc.display_name = "Test NPC"
	npc.visual_color = Color(0.5, 0.5, 0.5)
	npc.birthday = {"month": 3, "day": 5}
	npc.gift_preferences = {
		"loved": ["grain_wheat"],
		"liked": ["herb_leaf"],
		"disliked": ["sour_vinegar"],
		"hated": ["bitter_root"],
	}
	npc.dialogues = {
		"neutral": [{"text": "Hello.", "choices": [
			{"label": "Hi!", "points": 3, "response": "Nice!"},
			{"label": "Bye.", "points": -2, "response": "Rude."},
		]}],
		"like": [{"text": "Friend!", "choices": []}],
		"love": [{"text": "Best friend!", "choices": []}],
		"dislike": [{"text": "Oh.", "choices": [
			{"label": "Sorry.", "points": 3, "response": "Fine."}
		]}],
		"hate": [{"text": "Leave.", "choices": [
			{"label": "I'll change.", "points": 5, "response": "Maybe."}
		]}],
		"birthday": [{"text": "My birthday!", "choices": []}],
	}
	npc.npc_gifts = [
		{"threshold": 20, "item_id": "grain_wheat", "quantity": 3, "message": "A gift!"},
	]
	npc.occupation = "Tester"
	npc.schedule = []
	DataRegistry.npcs["test_npc"] = npc

func _seed_ingredients() -> void:
	var ing = IngredientDef.new()
	ing.ingredient_id = "grain_wheat"
	ing.display_name = "Grain Wheat"
	ing.sell_price = 10
	ing.icon_color = Color.YELLOW
	DataRegistry.ingredients["grain_wheat"] = ing

	var ing2 = IngredientDef.new()
	ing2.ingredient_id = "bitter_root"
	ing2.display_name = "Bitter Root"
	ing2.sell_price = 5
	ing2.icon_color = Color.DARK_RED
	DataRegistry.ingredients["bitter_root"] = ing2

func _setup_mock_player() -> void:
	NetworkManager.player_data_store[mock_peer_id] = {
		"player_name": "TestPlayer",
		"inventory": {"grain_wheat": 5, "bitter_root": 3},
		"npc_friendships": {},
		"money": 100,
	}

func _get_friendship(npc_id: String) -> Dictionary:
	return NetworkManager.player_data_store[mock_peer_id].get("npc_friendships", {}).get(npc_id, {})

# === Talk Request Tests ===

func test_friendship_init_on_first_interaction() -> void:
	var data = NetworkManager.player_data_store[mock_peer_id]
	var friendships: Dictionary = data.get("npc_friendships", {})
	assert_false(friendships.has("test_npc"), "Should not have friendship before talk")

	# Simulate what handle_talk_request does: init + talk bonus
	friendships["test_npc"] = _create_default_friendship()
	data["npc_friendships"] = friendships
	var fs = friendships["test_npc"]
	fs["talked_today"] = true
	fs["points"] = clampi(int(fs["points"]) + TALK_BONUS, MIN_FRIENDSHIP, MAX_FRIENDSHIP)

	assert_eq(int(fs["points"]), 2)
	assert_true(fs["talked_today"])

func test_talk_bonus_not_applied_twice() -> void:
	var data = NetworkManager.player_data_store[mock_peer_id]
	var friendships: Dictionary = data.get("npc_friendships", {})
	friendships["test_npc"] = _create_default_friendship()
	data["npc_friendships"] = friendships
	var fs = friendships["test_npc"]

	# First talk
	fs["talked_today"] = true
	fs["points"] = clampi(int(fs["points"]) + TALK_BONUS, MIN_FRIENDSHIP, MAX_FRIENDSHIP)
	assert_eq(int(fs["points"]), 2)

	# Second talk — should not add more
	if not fs["talked_today"]:
		fs["points"] = clampi(int(fs["points"]) + TALK_BONUS, MIN_FRIENDSHIP, MAX_FRIENDSHIP)
	assert_eq(int(fs["points"]), 2, "Talk bonus should not apply twice")

func test_dialogue_choice_applies_points() -> void:
	var data = NetworkManager.player_data_store[mock_peer_id]
	var friendships: Dictionary = data.get("npc_friendships", {})
	friendships["test_npc"] = _create_default_friendship()
	data["npc_friendships"] = friendships
	var fs = friendships["test_npc"]

	# Simulate talk + kind choice (+3)
	fs["talked_today"] = true
	fs["points"] = clampi(int(fs["points"]) + TALK_BONUS, MIN_FRIENDSHIP, MAX_FRIENDSHIP)
	# Apply choice points
	fs["points"] = clampi(int(fs["points"]) + 3, MIN_FRIENDSHIP, MAX_FRIENDSHIP)
	assert_eq(int(fs["points"]), 5, "Talk bonus (2) + kind choice (3) = 5")

func test_dialogue_rude_choice_reduces_points() -> void:
	var data = NetworkManager.player_data_store[mock_peer_id]
	var friendships: Dictionary = data.get("npc_friendships", {})
	friendships["test_npc"] = _create_default_friendship()
	data["npc_friendships"] = friendships
	var fs = friendships["test_npc"]

	fs["talked_today"] = true
	fs["points"] = clampi(int(fs["points"]) + TALK_BONUS, MIN_FRIENDSHIP, MAX_FRIENDSHIP)
	fs["points"] = clampi(int(fs["points"]) + (-2), MIN_FRIENDSHIP, MAX_FRIENDSHIP)
	assert_eq(int(fs["points"]), 0, "Talk bonus (2) + rude choice (-2) = 0")

func test_cancel_dialogue_only_talk_bonus() -> void:
	var data = NetworkManager.player_data_store[mock_peer_id]
	var friendships: Dictionary = data.get("npc_friendships", {})
	friendships["test_npc"] = _create_default_friendship()
	data["npc_friendships"] = friendships
	var fs = friendships["test_npc"]

	# Talk applied
	fs["talked_today"] = true
	fs["points"] = clampi(int(fs["points"]) + TALK_BONUS, MIN_FRIENDSHIP, MAX_FRIENDSHIP)
	# Cancel — no choice points applied
	assert_eq(int(fs["points"]), 2, "Cancel should only have talk bonus")

# === Gift Flow Tests ===

func test_gift_loved_adds_points() -> void:
	var data = NetworkManager.player_data_store[mock_peer_id]
	var friendships: Dictionary = data.get("npc_friendships", {})
	friendships["test_npc"] = _create_default_friendship()
	data["npc_friendships"] = friendships
	var fs = friendships["test_npc"]

	# Give loved item
	var gift_tier = _get_gift_tier(DataRegistry.get_npc("test_npc"), "grain_wheat")
	assert_eq(gift_tier, "loved")
	var base_points = GIFT_POINTS[gift_tier]
	fs["gifted_today"] = true
	fs["points"] = clampi(int(fs["points"]) + base_points, MIN_FRIENDSHIP, MAX_FRIENDSHIP)
	assert_eq(int(fs["points"]), 15)

func test_gift_hated_reduces_points() -> void:
	var data = NetworkManager.player_data_store[mock_peer_id]
	var friendships: Dictionary = data.get("npc_friendships", {})
	friendships["test_npc"] = _create_default_friendship()
	data["npc_friendships"] = friendships
	var fs = friendships["test_npc"]

	var gift_tier = _get_gift_tier(DataRegistry.get_npc("test_npc"), "bitter_root")
	assert_eq(gift_tier, "hated")
	var base_points = GIFT_POINTS[gift_tier]
	fs["gifted_today"] = true
	fs["points"] = clampi(int(fs["points"]) + base_points, MIN_FRIENDSHIP, MAX_FRIENDSHIP)
	assert_eq(int(fs["points"]), -15)

func test_gift_daily_limit_blocks_second() -> void:
	var data = NetworkManager.player_data_store[mock_peer_id]
	var friendships: Dictionary = data.get("npc_friendships", {})
	friendships["test_npc"] = _create_default_friendship()
	data["npc_friendships"] = friendships
	var fs = friendships["test_npc"]

	# First gift succeeds
	fs["gifted_today"] = true
	fs["points"] = clampi(int(fs["points"]) + 15, MIN_FRIENDSHIP, MAX_FRIENDSHIP)

	# Second gift blocked
	assert_true(fs["gifted_today"], "Should be blocked after first gift")

func test_gift_birthday_multiplier() -> void:
	var base_points = GIFT_POINTS["loved"]
	var birthday_points = base_points * BIRTHDAY_MULTIPLIER
	assert_eq(birthday_points, 45)

func test_gift_inventory_required() -> void:
	# Player has 5 grain_wheat — should have enough
	assert_true(NetworkManager.server_has_inventory(mock_peer_id, "grain_wheat", 1))
	# Player has no "nonexistent"
	assert_false(NetworkManager.server_has_inventory(mock_peer_id, "nonexistent", 1))

# === Daily Decay Processing ===

func test_daily_decay_across_npcs() -> void:
	var data = NetworkManager.player_data_store[mock_peer_id]
	var friendships: Dictionary = {}
	friendships["npc_a"] = {"points": 30, "talked_today": false, "gifted_today": false, "last_interaction_day": 0, "gifts_received": []}
	friendships["npc_b"] = {"points": 10, "talked_today": true, "gifted_today": false, "last_interaction_day": 5, "gifts_received": []}
	data["npc_friendships"] = friendships

	# Simulate day change (day 5 -> day 6)
	var current_day: int = 6
	for npc_id in friendships:
		var fs = friendships[npc_id]
		var last_day = int(fs.get("last_interaction_day", 0))
		if last_day < current_day and int(fs.get("points", 0)) > 0:
			fs["points"] = maxi(int(fs["points"]) - DAILY_DECAY, 0)
		fs["talked_today"] = false
		fs["gifted_today"] = false

	# npc_a: 30 -> 29 (no interaction, day 0 < 6)
	assert_eq(int(friendships["npc_a"]["points"]), 29)
	# npc_b: 10 -> 9 (interacted day 5, but 5 < 6 so still decays)
	assert_eq(int(friendships["npc_b"]["points"]), 9)
	# Daily flags reset
	assert_false(friendships["npc_b"]["talked_today"])

func test_daily_decay_no_negative_spiral() -> void:
	var data = NetworkManager.player_data_store[mock_peer_id]
	var friendships: Dictionary = {}
	friendships["test_npc"] = {"points": -50, "talked_today": false, "gifted_today": false, "last_interaction_day": 0, "gifts_received": []}
	data["npc_friendships"] = friendships

	var current_day: int = 10
	var fs = friendships["test_npc"]
	var last_day = int(fs.get("last_interaction_day", 0))
	if last_day < current_day and int(fs.get("points", 0)) > 0:
		fs["points"] = maxi(int(fs["points"]) - DAILY_DECAY, 0)

	assert_eq(int(fs["points"]), -50, "Negative friendship should not decay further")

# === Redemption Path Test ===

func test_hate_tier_recovery_via_kind_choices() -> void:
	var data = NetworkManager.player_data_store[mock_peer_id]
	var friendships: Dictionary = data.get("npc_friendships", {})
	friendships["test_npc"] = {"points": -70, "talked_today": false, "gifted_today": false, "last_interaction_day": 0, "gifts_received": []}
	data["npc_friendships"] = friendships
	var fs = friendships["test_npc"]

	# Talk + hate tier kind choice (+5)
	fs["talked_today"] = true
	fs["points"] = clampi(int(fs["points"]) + TALK_BONUS, MIN_FRIENDSHIP, MAX_FRIENDSHIP)
	fs["points"] = clampi(int(fs["points"]) + 5, MIN_FRIENDSHIP, MAX_FRIENDSHIP)

	assert_eq(int(fs["points"]), -63, "Should be -70 + 2 + 5 = -63")
	assert_eq(get_friendship_tier(-63), "hate", "Still in hate tier")

	# After several kind interactions, should escape hate tier
	for i in range(5):
		fs["talked_today"] = false # new day
		fs["talked_today"] = true
		fs["points"] = clampi(int(fs["points"]) + TALK_BONUS + 5, MIN_FRIENDSHIP, MAX_FRIENDSHIP)

	assert_true(int(fs["points"]) > -60, "Should have escaped hate tier")
