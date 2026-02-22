extends GutTest

# Tests for appearance validation logic (mirrors NetworkManager._validate_appearance)
# We test the same logic inline since NetworkManager is an autoload and its
# methods aren't easily callable in unit tests.

func _validate_appearance(app: Dictionary) -> bool:
	for color_key in ["primary_color", "accent_color"]:
		var color_val = app.get(color_key, null)
		if color_val == null or not color_val is Dictionary:
			return false
		for component in ["r", "g", "b"]:
			var v = color_val.get(component, null)
			if v == null:
				return false
			var fv := float(v)
			if fv < 0.0 or fv > 1.0:
				return false
	return true


func test_valid_appearance():
	var app := {
		"primary_color": {"r": 0.5, "g": 0.3, "b": 0.8},
		"accent_color": {"r": 0.9, "g": 0.9, "b": 0.9},
	}
	assert_true(_validate_appearance(app))


func test_missing_primary_color_fails():
	var app := {
		"accent_color": {"r": 0.9, "g": 0.9, "b": 0.9},
	}
	assert_false(_validate_appearance(app), "Missing primary_color should fail")


func test_missing_accent_color_fails():
	var app := {
		"primary_color": {"r": 0.5, "g": 0.3, "b": 0.8},
	}
	assert_false(_validate_appearance(app), "Missing accent_color should fail")


func test_empty_dict_fails():
	assert_false(_validate_appearance({}), "Empty dict should fail")


func test_missing_color_component_fails():
	var app := {
		"primary_color": {"r": 0.5, "g": 0.3},  # missing b
		"accent_color": {"r": 0.9, "g": 0.9, "b": 0.9},
	}
	assert_false(_validate_appearance(app), "Missing color component should fail")


func test_out_of_range_color_fails():
	var app := {
		"primary_color": {"r": 1.5, "g": 0.3, "b": 0.8},
		"accent_color": {"r": 0.9, "g": 0.9, "b": 0.9},
	}
	assert_false(_validate_appearance(app), "Color > 1.0 should fail")


func test_negative_color_fails():
	var app := {
		"primary_color": {"r": -0.1, "g": 0.3, "b": 0.8},
		"accent_color": {"r": 0.9, "g": 0.9, "b": 0.9},
	}
	assert_false(_validate_appearance(app), "Negative color should fail")


func test_boundary_values_pass():
	var app := {
		"primary_color": {"r": 0.0, "g": 0.0, "b": 0.0},
		"accent_color": {"r": 1.0, "g": 1.0, "b": 1.0},
	}
	assert_true(_validate_appearance(app), "Boundary values 0.0 and 1.0 should pass")


func test_extra_keys_ignored():
	var app := {
		"primary_color": {"r": 0.5, "g": 0.3, "b": 0.8},
		"accent_color": {"r": 0.9, "g": 0.9, "b": 0.9},
		"needs_customization": true,
		"unknown_key": "whatever",
	}
	assert_true(_validate_appearance(app), "Extra keys should be ignored")


func test_non_dict_color_fails():
	var app := {
		"primary_color": "red",
		"accent_color": {"r": 0.9, "g": 0.9, "b": 0.9},
	}
	assert_false(_validate_appearance(app), "Non-dict color should fail")
