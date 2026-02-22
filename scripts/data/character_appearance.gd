class_name CharacterAppearance
extends Resource

## Defines a character's visual customization. Used for both player avatars and NPC presets.

@export var gender: String = "female" # "female" or "male"
@export var head_id: String = "HEAD_01_1"
@export var hair_id: String = "" # empty = bald
@export var torso_id: String = "TORSO_02_1"
@export var pants_id: String = "PANTS_01_1"
@export var shoes_id: String = "SHOES_01_1"
@export var arms_id: String = "HANDS_01_1"
@export var hat_id: String = "" # empty = none
@export var glasses_id: String = "" # empty = none
@export var beard_id: String = "" # male only, empty = none


func to_dict() -> Dictionary:
	return {
		"gender": gender,
		"head_id": head_id,
		"hair_id": hair_id,
		"torso_id": torso_id,
		"pants_id": pants_id,
		"shoes_id": shoes_id,
		"arms_id": arms_id,
		"hat_id": hat_id,
		"glasses_id": glasses_id,
		"beard_id": beard_id,
	}


static func from_dict(d: Dictionary) -> CharacterAppearance:
	var app := CharacterAppearance.new()
	app.gender = d.get("gender", "female")
	app.head_id = d.get("head_id", "HEAD_01_1")
	app.hair_id = d.get("hair_id", "")
	app.torso_id = d.get("torso_id", "TORSO_02_1")
	if app.torso_id == "TORSO_01_1":
		app.torso_id = "TORSO_02_1"
	app.pants_id = d.get("pants_id", "PANTS_01_1")
	app.shoes_id = d.get("shoes_id", "SHOES_01_1")
	app.arms_id = d.get("arms_id", "HANDS_01_1")
	if app.arms_id == "":
		app.arms_id = "HANDS_01_1"
	app.hat_id = d.get("hat_id", "")
	app.glasses_id = d.get("glasses_id", "")
	app.beard_id = d.get("beard_id", "")
	return app


## Returns a randomized appearance for first-time players.
static func random_default() -> Dictionary:
	var genders := ["female", "male"]
	var g: String = genders[randi() % genders.size()]
	return {
		"gender": g,
		"head_id": "HEAD_01_1",
		"hair_id": "HAIR_01_1",
		"torso_id": "TORSO_02_1",
		"pants_id": "PANTS_01_1",
		"shoes_id": "SHOES_01_1",
		"arms_id": "HANDS_01_1",
		"hat_id": "",
		"glasses_id": "",
		"beard_id": "",
		"needs_customization": true,
	}
