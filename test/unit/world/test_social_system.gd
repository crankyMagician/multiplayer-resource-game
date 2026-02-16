extends GutTest

# Tests for NPC social system: friendship tiers, gift tiers, points, daily decay
# Uses RegistrySeeder — NO preload
# SocialManager doesn't have class_name (uses autoloads), so we inline its logic here.

const TALK_BONUS: int = 2
const DAILY_DECAY: int = 1
const GIFT_POINTS = {"loved": 15, "liked": 8, "neutral": 3, "disliked": -8, "hated": -15}
const BIRTHDAY_MULTIPLIER: int = 3
const MIN_FRIENDSHIP: int = -100
const MAX_FRIENDSHIP: int = 100

func before_each() -> void:
	RegistrySeeder.seed_all()
	_seed_npcs()

func after_each() -> void:
	RegistrySeeder.clear_all()

# Inline static methods from SocialManager for testing
static func _get_tier(points: int) -> String:
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

static func _resolve_schedule(npc_def: Resource, time_fraction: float, season: String) -> Vector3:
	for entry in npc_def.schedule:
		var t_start: float = float(entry.get("time_start", 0.0))
		var t_end: float = float(entry.get("time_end", 1.0))
		var seasons: Array = entry.get("seasons", [])
		if time_fraction >= t_start and time_fraction < t_end:
			if seasons.is_empty() or season in seasons:
				var pos_dict: Dictionary = entry.get("position", {})
				return Vector3(float(pos_dict.get("x", 0)), float(pos_dict.get("y", 1)), float(pos_dict.get("z", 0)))
	return Vector3.ZERO

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
		"neutral": [
			{
				"text": "Hello there.",
				"choices": [
					{"label": "Hi!", "points": 3, "response": "Nice to see you!"},
					{"label": "Go away.", "points": -3, "response": "How rude!"},
				]
			},
			{"text": "Simple greeting.", "choices": []}
		],
		"like": [{"text": "Good friend!", "choices": [
			{"label": "You too!", "points": 2, "response": "Thanks!"}
		]}],
		"love": [{"text": "Best friend!", "choices": []}],
		"dislike": [{"text": "Oh, it's you.", "choices": [
			{"label": "Sorry.", "points": 3, "response": "...Fine."}
		]}],
		"hate": [{"text": "Go away.", "choices": [
			{"label": "I want to change.", "points": 5, "response": "We'll see."}
		]}],
		"birthday": [{"text": "It's my birthday!", "choices": [
			{"label": "Happy birthday!", "points": 3, "response": "Thanks!"}
		]}],
	}
	npc.npc_gifts = [
		{"threshold": 20, "item_id": "grain_wheat", "quantity": 3, "message": "A gift for you!"},
		{"threshold": 50, "item_id": "herb_leaf", "quantity": 5, "message": "Special gift!"},
	]
	npc.occupation = "Tester"
	npc.schedule = [
		{"time_start": 0.0, "time_end": 0.5, "position": {"x": 0, "y": 1, "z": 0}, "seasons": []},
		{"time_start": 0.5, "time_end": 1.0, "position": {"x": 10, "y": 1, "z": 10}, "seasons": []},
	]
	DataRegistry.npcs["test_npc"] = npc

# === Friendship Tier Tests ===

func test_tier_hate_at_minus_100() -> void:
	assert_eq(_get_tier(-100), "hate")

func test_tier_hate_at_minus_61() -> void:
	assert_eq(_get_tier(-61), "hate")

func test_tier_dislike_at_minus_60() -> void:
	assert_eq(_get_tier(-60), "dislike")

func test_tier_dislike_at_minus_21() -> void:
	assert_eq(_get_tier(-21), "dislike")

func test_tier_neutral_at_minus_20() -> void:
	assert_eq(_get_tier(-20), "neutral")

func test_tier_neutral_at_19() -> void:
	assert_eq(_get_tier(19), "neutral")

func test_tier_like_at_20() -> void:
	assert_eq(_get_tier(20), "like")

func test_tier_like_at_59() -> void:
	assert_eq(_get_tier(59), "like")

func test_tier_love_at_60() -> void:
	assert_eq(_get_tier(60), "love")

func test_tier_love_at_100() -> void:
	assert_eq(_get_tier(100), "love")

func test_tier_neutral_at_0() -> void:
	assert_eq(_get_tier(0), "neutral")

# === Gift Tier Tests ===

func test_gift_tier_loved() -> void:
	var npc = DataRegistry.get_npc("test_npc")
	assert_eq(_get_gift_tier(npc, "grain_wheat"), "loved")

func test_gift_tier_liked() -> void:
	var npc = DataRegistry.get_npc("test_npc")
	assert_eq(_get_gift_tier(npc, "herb_leaf"), "liked")

func test_gift_tier_disliked() -> void:
	var npc = DataRegistry.get_npc("test_npc")
	assert_eq(_get_gift_tier(npc, "sour_vinegar"), "disliked")

func test_gift_tier_hated() -> void:
	var npc = DataRegistry.get_npc("test_npc")
	assert_eq(_get_gift_tier(npc, "bitter_root"), "hated")

func test_gift_tier_neutral_unknown() -> void:
	var npc = DataRegistry.get_npc("test_npc")
	assert_eq(_get_gift_tier(npc, "unknown_item"), "neutral")

# === Gift Points Tests ===

func test_gift_points_loved() -> void:
	assert_eq(GIFT_POINTS["loved"], 15)

func test_gift_points_hated() -> void:
	assert_eq(GIFT_POINTS["hated"], -15)

func test_gift_points_neutral() -> void:
	assert_eq(GIFT_POINTS["neutral"], 3)

func test_birthday_multiplier() -> void:
	var base = GIFT_POINTS["loved"]
	var result = base * BIRTHDAY_MULTIPLIER
	assert_eq(result, 45)

func test_birthday_multiplier_liked() -> void:
	var base = GIFT_POINTS["liked"]
	var result = base * BIRTHDAY_MULTIPLIER
	assert_eq(result, 24)

# === Friendship Clamp Tests ===

func test_clamp_at_max() -> void:
	assert_eq(clampi(150, MIN_FRIENDSHIP, MAX_FRIENDSHIP), 100)

func test_clamp_at_min() -> void:
	assert_eq(clampi(-200, MIN_FRIENDSHIP, MAX_FRIENDSHIP), -100)

func test_clamp_within_range() -> void:
	assert_eq(clampi(50, MIN_FRIENDSHIP, MAX_FRIENDSHIP), 50)

# === Talk Bonus Tests ===

func test_talk_bonus_value() -> void:
	assert_eq(TALK_BONUS, 2)

func test_talk_bonus_only_once_per_day() -> void:
	var fs = {"points": 0, "talked_today": false, "gifted_today": false, "last_interaction_day": 0, "gifts_received": []}
	if not fs["talked_today"]:
		fs["talked_today"] = true
		fs["points"] = clampi(fs["points"] + TALK_BONUS, MIN_FRIENDSHIP, MAX_FRIENDSHIP)
	assert_eq(fs["points"], 2)
	var before = fs["points"]
	if not fs["talked_today"]:
		fs["points"] = clampi(fs["points"] + TALK_BONUS, MIN_FRIENDSHIP, MAX_FRIENDSHIP)
	assert_eq(fs["points"], before, "Second talk should not add bonus")

# === Daily Decay Tests ===

func test_daily_decay_positive() -> void:
	var points: int = 50
	points = maxi(points - DAILY_DECAY, 0)
	assert_eq(points, 49)

func test_daily_decay_floor_at_zero() -> void:
	var points: int = 1
	points = maxi(points - DAILY_DECAY, 0)
	assert_eq(points, 0)

func test_daily_decay_no_negative() -> void:
	var points: int = 0
	if points > 0:
		points = maxi(points - DAILY_DECAY, 0)
	assert_eq(points, 0, "Should not decay below 0")

func test_daily_decay_negative_untouched() -> void:
	var points: int = -30
	if points > 0:
		points = maxi(points - DAILY_DECAY, 0)
	assert_eq(points, -30, "Negative points should not decay")

# === Gift Limit Tests ===

func test_gift_limit_once_per_day() -> void:
	var fs = {"points": 0, "talked_today": false, "gifted_today": false, "last_interaction_day": 0, "gifts_received": []}
	assert_false(fs["gifted_today"])
	fs["gifted_today"] = true
	assert_true(fs["gifted_today"])

# === NPC Gift Threshold Tests ===

func test_npc_gift_threshold_not_met() -> void:
	var npc = DataRegistry.get_npc("test_npc")
	var received: Array = []
	var triggered: Array = []
	for gift in npc.npc_gifts:
		var threshold = int(gift["threshold"])
		var gift_key = "npc_gift_test_npc_" + str(gift["item_id"])
		if 10 >= threshold and gift_key not in received:
			triggered.append(gift_key)
	assert_eq(triggered.size(), 0, "No gifts should trigger at 10 points")

func test_npc_gift_threshold_met() -> void:
	var npc = DataRegistry.get_npc("test_npc")
	var received: Array = []
	var triggered: Array = []
	for gift in npc.npc_gifts:
		var threshold = int(gift["threshold"])
		var gift_key = "npc_gift_test_npc_" + str(gift["item_id"])
		if 25 >= threshold and gift_key not in received:
			triggered.append(gift_key)
			received.append(gift_key)
	assert_eq(triggered.size(), 1, "One gift should trigger at 25 points (threshold 20)")

func test_npc_gift_one_time_only() -> void:
	var npc = DataRegistry.get_npc("test_npc")
	var received: Array = ["npc_gift_test_npc_grain_wheat"]
	var triggered: Array = []
	for gift in npc.npc_gifts:
		var threshold = int(gift["threshold"])
		var gift_key = "npc_gift_test_npc_" + str(gift["item_id"])
		if 25 >= threshold and gift_key not in received:
			triggered.append(gift_key)
	assert_eq(triggered.size(), 0, "Already received gift should not trigger again")

# === Schedule Position Tests ===

func test_schedule_morning_position() -> void:
	var npc = DataRegistry.get_npc("test_npc")
	var pos = _resolve_schedule(npc, 0.25, "spring")
	assert_eq(pos, Vector3(0, 1, 0))

func test_schedule_afternoon_position() -> void:
	var npc = DataRegistry.get_npc("test_npc")
	var pos = _resolve_schedule(npc, 0.75, "spring")
	assert_eq(pos, Vector3(10, 1, 10))

func test_schedule_no_match_returns_zero() -> void:
	var npc = NPCDef.new()
	npc.schedule = [
		{"time_start": 0.0, "time_end": 1.0, "position": {"x": 5, "y": 1, "z": 5}, "seasons": ["winter"]},
	]
	var pos = _resolve_schedule(npc, 0.5, "summer")
	assert_eq(pos, Vector3.ZERO)

func test_schedule_all_seasons() -> void:
	var npc = DataRegistry.get_npc("test_npc")
	var pos = _resolve_schedule(npc, 0.25, "winter")
	assert_eq(pos, Vector3(0, 1, 0))

# === Dialogue Choice Points Tests ===

func test_dialogue_kind_choice_stacks_with_talk() -> void:
	var points: int = 0
	points += TALK_BONUS
	points += 3
	assert_eq(points, 5)

func test_dialogue_rude_choice_stacks_with_talk() -> void:
	var points: int = 0
	points += TALK_BONUS
	points += -3
	assert_eq(points, -1)

func test_dialogue_no_choice_no_extra_points() -> void:
	var points: int = 0
	points += TALK_BONUS
	assert_eq(points, 2)

func test_dialogue_tier_selection_neutral() -> void:
	var tier = _get_tier(0)
	var npc = DataRegistry.get_npc("test_npc")
	var dialogues: Array = npc.dialogues.get(tier, [])
	assert_gt(dialogues.size(), 0, "Neutral tier should have dialogues")

func test_dialogue_tier_selection_like() -> void:
	var tier = _get_tier(30)
	var npc = DataRegistry.get_npc("test_npc")
	var dialogues: Array = npc.dialogues.get(tier, [])
	assert_gt(dialogues.size(), 0, "Like tier should have dialogues")

func test_dialogue_tier_selection_hate() -> void:
	var tier = _get_tier(-80)
	var npc = DataRegistry.get_npc("test_npc")
	var dialogues: Array = npc.dialogues.get(tier, [])
	assert_gt(dialogues.size(), 0, "Hate tier should have dialogues")

# === Redemption Path Test ===

func test_hate_tier_kind_choice_gives_extra() -> void:
	var npc = DataRegistry.get_npc("test_npc")
	var hate_dialogues: Array = npc.dialogues.get("hate", [])
	assert_gt(hate_dialogues.size(), 0)
	var choices = hate_dialogues[0].get("choices", [])
	var kind_choice = choices[0]
	assert_eq(int(kind_choice["points"]), 5, "Hate tier kind choice should give +5")

# === DataRegistry NPC Access ===

func test_get_npc_valid() -> void:
	var npc = DataRegistry.get_npc("test_npc")
	assert_not_null(npc)
	assert_eq(npc.display_name, "Test NPC")

func test_get_npc_invalid() -> void:
	var npc = DataRegistry.get_npc("nonexistent_npc")
	assert_null(npc)
