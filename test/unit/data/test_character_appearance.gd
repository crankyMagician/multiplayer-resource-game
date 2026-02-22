extends GutTest

# Tests for CharacterAppearance resource (two-color palette)

func test_to_dict_from_dict_roundtrip():
	var app := CharacterAppearance.new()
	app.primary_color = Color(0.5, 0.3, 0.8)
	app.accent_color = Color(0.1, 0.9, 0.2)

	var d := app.to_dict()
	var restored := CharacterAppearance.from_dict(d)

	assert_almost_eq(restored.primary_color.r, 0.5, 0.01)
	assert_almost_eq(restored.primary_color.g, 0.3, 0.01)
	assert_almost_eq(restored.primary_color.b, 0.8, 0.01)
	assert_almost_eq(restored.accent_color.r, 0.1, 0.01)
	assert_almost_eq(restored.accent_color.g, 0.9, 0.01)
	assert_almost_eq(restored.accent_color.b, 0.2, 0.01)


func test_from_dict_empty_dict_uses_defaults():
	var app := CharacterAppearance.from_dict({})

	assert_almost_eq(app.primary_color.r, 0.2, 0.01, "Default primary red")
	assert_almost_eq(app.primary_color.g, 0.5, 0.01, "Default primary green")
	assert_almost_eq(app.primary_color.b, 0.9, 0.01, "Default primary blue")
	assert_almost_eq(app.accent_color.r, 0.9, 0.01, "Default accent red")
	assert_almost_eq(app.accent_color.g, 0.9, 0.01, "Default accent green")
	assert_almost_eq(app.accent_color.b, 0.9, 0.01, "Default accent blue")


func test_random_default_has_required_fields():
	seed(42)
	var d := CharacterAppearance.random_default()

	assert_true(d.has("primary_color"), "Must have primary_color")
	assert_true(d["primary_color"] is Dictionary, "primary_color must be a dict")
	assert_true(d["primary_color"].has("r"), "primary_color must have r")
	assert_true(d["primary_color"].has("g"), "primary_color must have g")
	assert_true(d["primary_color"].has("b"), "primary_color must have b")
	assert_true(d.has("accent_color"), "Must have accent_color")
	assert_true(d["accent_color"] is Dictionary, "accent_color must be a dict")
	assert_true(d.has("needs_customization"), "Must have needs_customization flag")
	assert_true(d["needs_customization"], "needs_customization should be true")


func test_to_dict_returns_all_keys():
	var app := CharacterAppearance.new()
	var d := app.to_dict()

	assert_true(d.has("primary_color"), "to_dict must include primary_color")
	assert_true(d.has("accent_color"), "to_dict must include accent_color")
	assert_eq(d.size(), 2, "to_dict should have exactly 2 keys")


func test_color_dict_format():
	var app := CharacterAppearance.new()
	app.primary_color = Color(0.1, 0.2, 0.3)
	var d := app.to_dict()
	var pc: Dictionary = d["primary_color"]
	assert_almost_eq(float(pc["r"]), 0.1, 0.01)
	assert_almost_eq(float(pc["g"]), 0.2, 0.01)
	assert_almost_eq(float(pc["b"]), 0.3, 0.01)
