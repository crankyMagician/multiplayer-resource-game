class_name CharacterPartRegistry
extends RefCounted

## Registry of available character customization parts.
## Scans assets/characters/{gender}/parts/{category}/ for GLB files.
## Handles .glb, .glb.remap, .glb.import for export builds.

const CHARACTERS_DIR := "res://assets/characters/"

const FEMALE_CATEGORIES: Array[String] = [
	"head", "hair", "torso", "pants", "shoes", "arms", "hats", "glasses",
]

const MALE_CATEGORIES: Array[String] = [
	"head", "hair", "torso", "pants", "shoes", "arms", "hats", "glasses", "beard",
]

# Category → appearance dict key mapping
const CATEGORY_KEYS: Dictionary = {
	"head": "head_id",
	"hair": "hair_id",
	"torso": "torso_id",
	"pants": "pants_id",
	"shoes": "shoes_id",
	"arms": "arms_id",
	"hats": "hat_id",
	"glasses": "glasses_id",
	"beard": "beard_id",
}

# Categories where empty string means "none" (optional parts)
const OPTIONAL_CATEGORIES: Array[String] = [
	"hair", "hats", "glasses", "beard",
]

# Torsos that lack arm geometry and should not be selectable
const TORSO_BLOCKLIST: Array[String] = ["TORSO_01_1"]

# Cache: gender → category → Array[String] of part IDs
static var _cache: Dictionary = {}


static func get_categories(gender: String) -> Array[String]:
	if gender == "male":
		return MALE_CATEGORIES
	return FEMALE_CATEGORIES


static func get_parts(gender: String, category: String) -> Array[String]:
	var cache_key := gender + "/" + category
	if _cache.has(cache_key):
		return _cache[cache_key]

	var parts: Array[String] = []
	var dir_path := CHARACTERS_DIR + gender + "/parts/" + category + "/"
	var dir := DirAccess.open(dir_path)
	if not dir:
		_cache[cache_key] = parts
		return parts

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var part_id := _extract_part_id(file_name)
			if part_id != "" and not parts.has(part_id):
				parts.append(part_id)
		file_name = dir.get_next()
	dir.list_dir_end()

	# Filter out blocklisted torsos (no arm geometry)
	if category == "torso":
		parts = parts.filter(func(p: String) -> bool: return not TORSO_BLOCKLIST.has(p))
	parts.sort()
	_cache[cache_key] = parts
	return parts


static func get_part_path(gender: String, category: String, part_id: String) -> String:
	if part_id == "":
		return ""
	return CHARACTERS_DIR + gender + "/parts/" + category + "/" + part_id + ".glb"


static func get_base_model_path(gender: String) -> String:
	return CHARACTERS_DIR + gender + "/base/modular_" + gender + ".glb"


static func get_icon_path(gender: String, part_id: String) -> String:
	return CHARACTERS_DIR + "icons/" + gender + "/" + part_id + ".png"


static func get_texture_atlas_path() -> String:
	return CHARACTERS_DIR + "texture/Texture_Modular_Characters.png"


## Validates that all part IDs in an appearance dict exist in the registry.
static func validate_appearance(appearance: Dictionary) -> bool:
	var gender: String = appearance.get("gender", "female")
	if gender != "female" and gender != "male":
		return false

	for category in get_categories(gender):
		var key: String = CATEGORY_KEYS.get(category, "")
		if key == "":
			continue
		var part_id: String = appearance.get(key, "")
		if part_id == "":
			# Empty is OK for optional categories
			if category in OPTIONAL_CATEGORIES:
				continue
			# Required categories must have a value
			return false
		# Check part exists
		var parts := get_parts(gender, category)
		if parts.size() > 0 and not parts.has(part_id):
			return false

	return true


## Clear cached data (e.g. after asset reimport).
static func clear_cache() -> void:
	_cache.clear()


## Extract a part ID from a filename, handling .glb, .glb.remap, .glb.import
static func _extract_part_id(file_name: String) -> String:
	if file_name.ends_with(".glb"):
		return file_name.replace(".glb", "")
	elif file_name.ends_with(".glb.remap"):
		return file_name.replace(".glb.remap", "")
	elif file_name.ends_with(".glb.import"):
		return file_name.replace(".glb.import", "")
	return ""
