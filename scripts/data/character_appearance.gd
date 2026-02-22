class_name CharacterAppearance
extends Resource

## Defines a character's visual customization using a two-color palette.
## Primary color tints the body, accent color tints secondary surfaces.

@export var primary_color: Color = Color(0.2, 0.5, 0.9)
@export var accent_color: Color = Color(0.9, 0.9, 0.9)


func to_dict() -> Dictionary:
	return {
		"primary_color": {"r": primary_color.r, "g": primary_color.g, "b": primary_color.b},
		"accent_color": {"r": accent_color.r, "g": accent_color.g, "b": accent_color.b},
	}


static func from_dict(d: Dictionary) -> CharacterAppearance:
	var app := CharacterAppearance.new()
	var pc: Dictionary = d.get("primary_color", {})
	if not pc.is_empty():
		app.primary_color = Color(float(pc.get("r", 0.2)), float(pc.get("g", 0.5)), float(pc.get("b", 0.9)))
	var ac: Dictionary = d.get("accent_color", {})
	if not ac.is_empty():
		app.accent_color = Color(float(ac.get("r", 0.9)), float(ac.get("g", 0.9)), float(ac.get("b", 0.9)))
	return app


## Returns a randomized appearance for first-time players.
static func random_default() -> Dictionary:
	var palette := [
		Color(0.2, 0.5, 0.9), Color(0.9, 0.3, 0.3), Color(0.3, 0.8, 0.4),
		Color(0.9, 0.7, 0.2), Color(0.7, 0.3, 0.8), Color(0.2, 0.8, 0.8),
		Color(0.9, 0.5, 0.2), Color(0.6, 0.4, 0.3), Color(0.8, 0.6, 0.7),
	]
	var pc: Color = palette[randi() % palette.size()]
	var ac: Color = palette[randi() % palette.size()]
	return {
		"primary_color": {"r": pc.r, "g": pc.g, "b": pc.b},
		"accent_color": {"r": ac.r, "g": ac.g, "b": ac.b},
		"needs_customization": true,
	}
