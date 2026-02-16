class_name DataRegistry
extends Node

# Registries
static var ingredients: Dictionary = {} # id -> IngredientDef
static var species: Dictionary = {} # id -> CreatureSpecies
static var moves: Dictionary = {} # id -> MoveDef
static var encounter_tables: Dictionary = {} # id -> EncounterTable
static var recipes: Dictionary = {} # id -> RecipeDef
static var abilities: Dictionary = {} # id -> AbilityDef
static var held_items: Dictionary = {} # id -> HeldItemDef
static var trainers: Dictionary = {} # id -> TrainerDef
static var foods: Dictionary = {} # id -> FoodDef
static var tools: Dictionary = {} # id -> ToolDef
static var recipe_scrolls: Dictionary = {} # id -> RecipeScrollDef
static var shops: Dictionary = {} # id -> ShopDef
static var battle_items: Dictionary = {} # id -> BattleItemDef
static var npcs: Dictionary = {} # id -> NPCDef
static var locations: Dictionary = {} # id -> LocationDef
static var quests: Dictionary = {} # id -> QuestDef

static var _loaded: bool = false

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load_all("res://resources/ingredients/", ingredients, "ingredient_id")
	_load_all("res://resources/creatures/", species, "species_id")
	_load_all("res://resources/moves/", moves, "move_id")
	_load_all("res://resources/encounters/", encounter_tables, "table_id")
	_load_all("res://resources/recipes/", recipes, "recipe_id")
	_load_all("res://resources/abilities/", abilities, "ability_id")
	_load_all("res://resources/held_items/", held_items, "item_id")
	_load_all("res://resources/trainers/", trainers, "trainer_id")
	_load_all("res://resources/foods/", foods, "food_id")
	_load_all("res://resources/tools/", tools, "tool_id")
	_load_all("res://resources/recipe_scrolls/", recipe_scrolls, "scroll_id")
	_load_all("res://resources/shops/", shops, "shop_id")
	_load_all("res://resources/battle_items/", battle_items, "item_id")
	_load_all("res://resources/npcs/", npcs, "npc_id")
	_load_all("res://resources/locations/", locations, "location_id")
	_load_all("res://resources/quests/", quests, "quest_id")
	print("DataRegistry loaded: ", ingredients.size(), " ingredients, ", species.size(), " species, ", moves.size(), " moves, ", encounter_tables.size(), " encounter tables, ", recipes.size(), " recipes, ", abilities.size(), " abilities, ", held_items.size(), " held items, ", trainers.size(), " trainers, ", foods.size(), " foods, ", tools.size(), " tools, ", recipe_scrolls.size(), " recipe scrolls, ", shops.size(), " shops, ", battle_items.size(), " battle items, ", npcs.size(), " npcs, ", locations.size(), " locations, ", quests.size(), " quests")

static func _load_all(path: String, registry: Dictionary, id_field: String) -> void:
	var dir = DirAccess.open(path)
	if dir == null:
		print("DataRegistry: Could not open ", path)
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		# In exported builds, .tres may become .res or .tres.remap
		var load_path := ""
		if file_name.ends_with(".tres") or file_name.ends_with(".res"):
			load_path = path + file_name
		elif file_name.ends_with(".remap"):
			# .tres.remap -> load the original .tres path (Godot resolves it)
			load_path = path + file_name.replace(".remap", "")
		if load_path != "":
			var res = load(load_path)
			if res and id_field in res:
				registry[res.get(id_field)] = res
			elif res:
				print("DataRegistry: loaded ", load_path, " but missing field '", id_field, "'")
		file_name = dir.get_next()

static func get_ingredient(id: String):
	ensure_loaded()
	return ingredients.get(id)

static func get_species(id: String):
	ensure_loaded()
	return species.get(id)

static func get_move(id: String):
	ensure_loaded()
	return moves.get(id)

static func get_encounter_table(id: String):
	ensure_loaded()
	return encounter_tables.get(id)

static func get_recipe(id: String):
	ensure_loaded()
	return recipes.get(id)

static func get_ability(id: String):
	ensure_loaded()
	return abilities.get(id)

static func get_held_item(id: String):
	ensure_loaded()
	return held_items.get(id)

static func get_trainer(id: String):
	ensure_loaded()
	return trainers.get(id)

static func get_food(id: String):
	ensure_loaded()
	return foods.get(id)

static func get_tool(id: String):
	ensure_loaded()
	return tools.get(id)

static func get_recipe_scroll(id: String):
	ensure_loaded()
	return recipe_scrolls.get(id)

static func get_shop(id: String):
	ensure_loaded()
	return shops.get(id)

static func get_battle_item(id: String):
	ensure_loaded()
	return battle_items.get(id)

static func get_npc(id: String):
	ensure_loaded()
	return npcs.get(id)

static func get_location(id: String):
	ensure_loaded()
	return locations.get(id)

static func get_quest(id: String):
	ensure_loaded()
	return quests.get(id)

static func get_sell_price(item_id: String) -> int:
	ensure_loaded()
	if item_id in foods:
		return int(foods[item_id].sell_price)
	if item_id in ingredients:
		return int(ingredients[item_id].sell_price)
	if item_id in held_items:
		var hi = held_items[item_id]
		return int(hi.get("sell_price")) if "sell_price" in hi else 0
	return 0

static func get_item_display_info(item_id: String) -> Dictionary:
	ensure_loaded()
	# Check ingredients
	if item_id in ingredients:
		var ing = ingredients[item_id]
		return {"display_name": ing.display_name, "category": "ingredient", "icon_color": ing.icon_color}
	# Check held items
	if item_id in held_items:
		var hi = held_items[item_id]
		return {"display_name": hi.display_name, "category": "held_item", "icon_color": Color.MEDIUM_PURPLE}
	# Check foods
	if item_id in foods:
		var f = foods[item_id]
		return {"display_name": f.display_name, "category": "food", "icon_color": f.icon_color}
	# Check tools
	if item_id in tools:
		var t = tools[item_id]
		return {"display_name": t.display_name, "category": "tool", "icon_color": t.icon_color}
	# Check recipe scrolls
	if item_id in recipe_scrolls:
		var rs = recipe_scrolls[item_id]
		return {"display_name": rs.display_name, "category": "recipe_scroll", "icon_color": rs.icon_color}
	# Check battle items
	if item_id in battle_items:
		var bi = battle_items[item_id]
		return {"display_name": bi.display_name, "category": "battle_item", "icon_color": bi.icon_color}
	# Check for fragment pattern (fragment_<scroll_id>)
	if item_id.begins_with("fragment_"):
		var scroll_id = item_id.substr(9) # Remove "fragment_" prefix
		if scroll_id in recipe_scrolls:
			var rs = recipe_scrolls[scroll_id]
			return {"display_name": rs.display_name + " Fragment", "category": "fragment", "icon_color": Color(0.7, 0.6, 0.2)}
		return {"display_name": item_id.replace("_", " ").capitalize(), "category": "fragment", "icon_color": Color(0.7, 0.6, 0.2)}
	# Unknown item
	return {"display_name": item_id.replace("_", " ").capitalize(), "category": "unknown", "icon_color": Color.GRAY}
