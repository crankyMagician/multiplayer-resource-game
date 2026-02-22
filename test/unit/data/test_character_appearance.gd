extends GutTest

# Tests for CharacterAppearance resource

func test_to_dict_from_dict_roundtrip():
	var app := CharacterAppearance.new()
	app.gender = "male"
	app.head_id = "HEAD_02_1"
	app.hair_id = "HAIR_03_1"
	app.torso_id = "TORSO_05_1"
	app.pants_id = "PANTS_02_1"
	app.shoes_id = "SHOES_03_1"
	app.arms_id = "HANDS_01_1"
	app.hat_id = "HAT_01_1"
	app.glasses_id = "GLASSES_02_1"
	app.beard_id = "BEARD_01_1"

	var d := app.to_dict()
	var restored := CharacterAppearance.from_dict(d)

	assert_eq(restored.gender, "male")
	assert_eq(restored.head_id, "HEAD_02_1")
	assert_eq(restored.hair_id, "HAIR_03_1")
	assert_eq(restored.torso_id, "TORSO_05_1")
	assert_eq(restored.pants_id, "PANTS_02_1")
	assert_eq(restored.shoes_id, "SHOES_03_1")
	assert_eq(restored.arms_id, "HANDS_01_1")
	assert_eq(restored.hat_id, "HAT_01_1")
	assert_eq(restored.glasses_id, "GLASSES_02_1")
	assert_eq(restored.beard_id, "BEARD_01_1")


func test_from_dict_missing_keys_uses_defaults():
	var d := {"gender": "male"}
	var app := CharacterAppearance.from_dict(d)

	assert_eq(app.gender, "male")
	assert_eq(app.head_id, "HEAD_01_1", "Missing head_id should use default")
	assert_eq(app.torso_id, "TORSO_02_1", "Missing torso_id should use default")
	assert_eq(app.pants_id, "PANTS_01_1", "Missing pants_id should use default")
	assert_eq(app.shoes_id, "SHOES_01_1", "Missing shoes_id should use default")
	assert_eq(app.hair_id, "", "Missing hair_id should be empty")
	assert_eq(app.arms_id, "HANDS_01_1", "Missing arms_id should default to HANDS_01_1")
	assert_eq(app.hat_id, "", "Missing hat_id should be empty")
	assert_eq(app.glasses_id, "", "Missing glasses_id should be empty")
	assert_eq(app.beard_id, "", "Missing beard_id should be empty")


func test_from_dict_empty_dict_uses_all_defaults():
	var app := CharacterAppearance.from_dict({})

	assert_eq(app.gender, "female", "Default gender should be female")
	assert_eq(app.head_id, "HEAD_01_1")
	assert_eq(app.torso_id, "TORSO_02_1")


func test_random_default_has_required_fields():
	seed(42)
	var d := CharacterAppearance.random_default()

	assert_true(d.has("gender"), "Must have gender")
	assert_true(d["gender"] == "female" or d["gender"] == "male", "Gender must be female or male")
	assert_true(d.has("head_id"), "Must have head_id")
	assert_ne(d["head_id"], "", "head_id must not be empty")
	assert_true(d.has("torso_id"), "Must have torso_id")
	assert_ne(d["torso_id"], "", "torso_id must not be empty")
	assert_true(d.has("pants_id"), "Must have pants_id")
	assert_ne(d["pants_id"], "", "pants_id must not be empty")
	assert_true(d.has("shoes_id"), "Must have shoes_id")
	assert_ne(d["shoes_id"], "", "shoes_id must not be empty")
	assert_true(d.has("needs_customization"), "Must have needs_customization flag")
	assert_true(d["needs_customization"], "needs_customization should be true")


func test_from_dict_armless_torso_backfills():
	var d := {"gender": "female", "torso_id": "TORSO_01_1"}
	var app := CharacterAppearance.from_dict(d)
	assert_eq(app.torso_id, "TORSO_02_1", "TORSO_01_1 should migrate to TORSO_02_1")


func test_from_dict_empty_arms_id_backfills():
	var d := {"gender": "female", "arms_id": ""}
	var app := CharacterAppearance.from_dict(d)
	assert_eq(app.arms_id, "HANDS_01_1", "Empty arms_id should backfill to HANDS_01_1")


func test_gender_preserved_female():
	var app := CharacterAppearance.new()
	app.gender = "female"
	var d := app.to_dict()
	var restored := CharacterAppearance.from_dict(d)
	assert_eq(restored.gender, "female")


func test_gender_preserved_male():
	var app := CharacterAppearance.new()
	app.gender = "male"
	var d := app.to_dict()
	var restored := CharacterAppearance.from_dict(d)
	assert_eq(restored.gender, "male")


func test_to_dict_returns_all_keys():
	var app := CharacterAppearance.new()
	var d := app.to_dict()

	var expected_keys := ["gender", "head_id", "hair_id", "torso_id", "pants_id",
		"shoes_id", "arms_id", "hat_id", "glasses_id", "beard_id"]
	for key in expected_keys:
		assert_true(d.has(key), "to_dict must include key: " + key)
