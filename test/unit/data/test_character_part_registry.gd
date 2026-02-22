extends GutTest

# Tests for CharacterPartRegistry static methods

func before_each():
	CharacterPartRegistry.clear_cache()


func after_each():
	CharacterPartRegistry.clear_cache()


func test_get_categories_female():
	var cats := CharacterPartRegistry.get_categories("female")
	assert_eq(cats.size(), 8, "Female should have 8 categories")
	assert_false(cats.has("beard"), "Female should not have beard")
	assert_true(cats.has("head"))
	assert_true(cats.has("hair"))
	assert_true(cats.has("torso"))
	assert_true(cats.has("pants"))
	assert_true(cats.has("shoes"))
	assert_true(cats.has("arms"))
	assert_true(cats.has("hats"))
	assert_true(cats.has("glasses"))


func test_get_categories_male():
	var cats := CharacterPartRegistry.get_categories("male")
	assert_eq(cats.size(), 9, "Male should have 9 categories")
	assert_true(cats.has("beard"), "Male should have beard")


func test_get_parts_returns_array():
	var parts := CharacterPartRegistry.get_parts("female", "head")
	assert_true(parts is Array, "get_parts should return an Array")


func test_get_part_path_format():
	var path := CharacterPartRegistry.get_part_path("female", "head", "HEAD_01_1")
	assert_eq(path, "res://assets/characters/female/parts/head/HEAD_01_1.glb")


func test_get_part_path_empty_id_returns_empty():
	var path := CharacterPartRegistry.get_part_path("female", "head", "")
	assert_eq(path, "")


func test_get_base_model_path_female():
	var path := CharacterPartRegistry.get_base_model_path("female")
	assert_eq(path, "res://assets/characters/female/base/modular_female.glb")


func test_get_base_model_path_male():
	var path := CharacterPartRegistry.get_base_model_path("male")
	assert_eq(path, "res://assets/characters/male/base/modular_male.glb")


func test_get_icon_path():
	var path := CharacterPartRegistry.get_icon_path("female", "HEAD_01_1")
	assert_eq(path, "res://assets/characters/icons/female/HEAD_01_1.png")


func test_get_texture_atlas_path():
	var path := CharacterPartRegistry.get_texture_atlas_path()
	assert_eq(path, "res://assets/characters/texture/Texture_Modular_Characters.png")


func test_optional_categories_list():
	var optional := CharacterPartRegistry.OPTIONAL_CATEGORIES
	assert_true(optional.has("hair"), "hair should be optional")
	assert_true(optional.has("hats"), "hats should be optional")
	assert_true(optional.has("glasses"), "glasses should be optional")
	assert_true(optional.has("beard"), "beard should be optional")
	assert_false(optional.has("head"), "head should not be optional")
	assert_false(optional.has("torso"), "torso should not be optional")
	assert_false(optional.has("pants"), "pants should not be optional")
	assert_false(optional.has("shoes"), "shoes should not be optional")
	assert_false(optional.has("arms"), "arms should not be optional")


func test_validate_appearance_valid():
	# With no parts dirs, all part_id lookups return empty arrays, so any ID is accepted
	var appearance := {
		"gender": "female",
		"head_id": "HEAD_01_1",
		"torso_id": "TORSO_02_1",
		"pants_id": "PANTS_01_1",
		"shoes_id": "SHOES_01_1",
		"arms_id": "HANDS_01_1",
	}
	assert_true(CharacterPartRegistry.validate_appearance(appearance))


func test_validate_appearance_invalid_gender():
	var appearance := {
		"gender": "robot",
		"head_id": "HEAD_01_1",
		"torso_id": "TORSO_02_1",
		"pants_id": "PANTS_01_1",
		"shoes_id": "SHOES_01_1",
		"arms_id": "HANDS_01_1",
	}
	assert_false(CharacterPartRegistry.validate_appearance(appearance))


func test_validate_appearance_missing_required():
	# Missing head_id (required)
	var appearance := {
		"gender": "female",
		"head_id": "",
		"torso_id": "TORSO_02_1",
		"pants_id": "PANTS_01_1",
		"shoes_id": "SHOES_01_1",
		"arms_id": "HANDS_01_1",
	}
	assert_false(CharacterPartRegistry.validate_appearance(appearance))


func test_validate_appearance_missing_gender():
	# Empty gender should fail
	var appearance := {
		"gender": "",
		"head_id": "HEAD_01_1",
		"torso_id": "TORSO_02_1",
		"pants_id": "PANTS_01_1",
		"shoes_id": "SHOES_01_1",
		"arms_id": "HANDS_01_1",
	}
	assert_false(CharacterPartRegistry.validate_appearance(appearance))


func test_validate_appearance_optional_empty_ok():
	# Optional parts can be empty, but arms_id is now required
	var appearance := {
		"gender": "male",
		"head_id": "HEAD_01_1",
		"torso_id": "TORSO_02_1",
		"pants_id": "PANTS_01_1",
		"shoes_id": "SHOES_01_1",
		"arms_id": "HANDS_01_1",
		"hair_id": "",
		"hat_id": "",
		"glasses_id": "",
		"beard_id": "",
	}
	assert_true(CharacterPartRegistry.validate_appearance(appearance))


func test_validate_appearance_empty_arms_rejected():
	# arms_id is required — empty should fail
	var appearance := {
		"gender": "female",
		"head_id": "HEAD_01_1",
		"torso_id": "TORSO_02_1",
		"pants_id": "PANTS_01_1",
		"shoes_id": "SHOES_01_1",
		"arms_id": "",
	}
	assert_false(CharacterPartRegistry.validate_appearance(appearance))


func test_category_keys_mapping():
	assert_eq(CharacterPartRegistry.CATEGORY_KEYS["head"], "head_id")
	assert_eq(CharacterPartRegistry.CATEGORY_KEYS["hats"], "hat_id")
	assert_eq(CharacterPartRegistry.CATEGORY_KEYS["beard"], "beard_id")


func test_extract_part_id_glb():
	var result := CharacterPartRegistry._extract_part_id("HEAD_01_1.glb")
	assert_eq(result, "HEAD_01_1")


func test_extract_part_id_remap():
	var result := CharacterPartRegistry._extract_part_id("HEAD_01_1.glb.remap")
	assert_eq(result, "HEAD_01_1")


func test_extract_part_id_import():
	var result := CharacterPartRegistry._extract_part_id("HEAD_01_1.glb.import")
	assert_eq(result, "HEAD_01_1")


func test_extract_part_id_invalid():
	var result := CharacterPartRegistry._extract_part_id("HEAD_01_1.png")
	assert_eq(result, "")


func test_extract_part_id_no_extension():
	var result := CharacterPartRegistry._extract_part_id("readme.txt")
	assert_eq(result, "")


func test_cache_cleared():
	# After clearing, subsequent calls should work fresh
	CharacterPartRegistry.get_parts("female", "head")
	CharacterPartRegistry.clear_cache()
	# No crash, no stale data
	var parts := CharacterPartRegistry.get_parts("female", "head")
	assert_true(parts is Array)
