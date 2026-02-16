extends Node

signal craft_result(success: bool, result_name: String, message: String)

func _ready() -> void:
	pass

# === Single-phase server-authoritative crafting ===

@rpc("any_peer", "reliable")
func request_craft(recipe_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	DataRegistry.ensure_loaded()
	var recipe = DataRegistry.get_recipe(recipe_id)
	if recipe == null:
		_craft_result_client.rpc_id(sender, false, "", "Recipe not found")
		return

	# Check if recipe is unlockable and player has it unlocked
	if recipe.unlockable and not NetworkManager.server_has_known_recipe(sender, recipe_id):
		_craft_result_client.rpc_id(sender, false, "", "Recipe not yet unlocked")
		return

	# Check ingredients available in server store
	for ingredient_id in recipe.ingredients:
		var needed = int(recipe.ingredients[ingredient_id])
		if not NetworkManager.server_has_inventory(sender, ingredient_id, needed):
			_craft_result_client.rpc_id(sender, false, "", "Missing ingredients")
			return

	# Check tool ingredient (for upgrade recipes)
	if recipe.requires_tool_ingredient != "":
		if not NetworkManager.server_has_inventory(sender, recipe.requires_tool_ingredient):
			_craft_result_client.rpc_id(sender, false, "", "Missing required tool")
			return

	# === All validation passed — deduct and produce ===

	# Deduct ingredients
	for ingredient_id in recipe.ingredients:
		var needed = int(recipe.ingredients[ingredient_id])
		NetworkManager.server_remove_inventory(sender, ingredient_id, needed)

	# Deduct tool ingredient if applicable
	if recipe.requires_tool_ingredient != "":
		NetworkManager.server_remove_inventory(sender, recipe.requires_tool_ingredient, 1)

	# Produce result
	var result_name = ""

	if recipe.result_species_id != "":
		# Creature recipe — use universal server_give_creature (handles party-full)
		var species = DataRegistry.get_species(recipe.result_species_id)
		if species == null:
			_craft_result_client.rpc_id(sender, false, "", "Species not found")
			return
		var creature = CreatureInstance.create_from_species(species, 1)
		var creature_data = creature.to_dict()
		creature_data["creature_id"] = NetworkManager._generate_uuid()
		result_name = species.display_name
		NetworkManager.server_give_creature(sender, creature_data, "craft", recipe_id)
		_craft_result_client.rpc_id(sender, true, result_name, result_name + " has been crafted!")

	elif recipe.result_item_id != "":
		# Held item recipe
		NetworkManager.server_add_inventory(sender, recipe.result_item_id, 1)
		var item = DataRegistry.get_held_item(recipe.result_item_id)
		result_name = item.display_name if item else recipe.result_item_id
		_receive_crafted_item.rpc_id(sender, recipe.result_item_id, result_name)

	elif recipe.result_food_id != "":
		# Food recipe
		NetworkManager.server_add_inventory(sender, recipe.result_food_id, 1)
		var food = DataRegistry.get_food(recipe.result_food_id)
		result_name = food.display_name if food else recipe.result_food_id
		_receive_crafted_item.rpc_id(sender, recipe.result_food_id, result_name)

	elif recipe.result_tool_id != "":
		# Tool recipe (upgrade)
		NetworkManager.server_add_inventory(sender, recipe.result_tool_id, 1)
		var tool_def = DataRegistry.get_tool(recipe.result_tool_id)
		result_name = tool_def.display_name if tool_def else recipe.result_tool_id
		# Auto-equip the new tool
		if tool_def:
			NetworkManager.server_equip_tool(sender, tool_def.tool_type, recipe.result_tool_id)
		_receive_crafted_item.rpc_id(sender, recipe.result_tool_id, result_name)

	# Track crafting stat
	StatTracker.increment(sender, "items_crafted")
	# Sync inventory after crafting
	NetworkManager._sync_inventory_full.rpc_id(sender, NetworkManager.player_data_store[sender].get("inventory", {}))
	# Quest progress: craft objective
	var quest_mgr = get_node_or_null("/root/Main/GameWorld/QuestManager")
	if quest_mgr:
		quest_mgr.notify_progress(sender, "craft", recipe_id)
	print("[Craft] ", sender, " crafted: ", result_name)

@rpc("authority", "reliable")
func _receive_crafted_item(item_id: String, item_name: String) -> void:
	PlayerData.add_to_inventory(item_id, 1)
	craft_result.emit(true, item_name, "Crafted " + item_name + "!")

@rpc("authority", "reliable")
func _craft_result_client(success: bool, result_name: String, message: String) -> void:
	craft_result.emit(success, result_name, message)

# === Recipe listing ===

func get_available_recipes(station: String = "") -> Array:
	DataRegistry.ensure_loaded()
	var available = []
	for recipe_id in DataRegistry.recipes:
		var recipe = DataRegistry.recipes[recipe_id]
		# Station filter
		if station != "" and recipe.station != "" and recipe.station != station:
			continue
		var locked = recipe.unlockable and recipe_id not in PlayerData.known_recipes
		var info = {
			"recipe_id": recipe.recipe_id,
			"display_name": recipe.display_name,
			"result_species_id": recipe.result_species_id,
			"result_item_id": recipe.result_item_id,
			"result_food_id": recipe.result_food_id,
			"result_tool_id": recipe.result_tool_id,
			"description": recipe.description,
			"station": recipe.station,
			"requires_tool_ingredient": recipe.requires_tool_ingredient,
			"can_craft": not locked,
			"locked": locked,
			"ingredients": {}
		}
		for ingredient_id in recipe.ingredients:
			var needed = int(recipe.ingredients[ingredient_id])
			var have = PlayerData.get_item_count(ingredient_id)
			info.ingredients[ingredient_id] = {"needed": needed, "have": have}
			if have < needed:
				info.can_craft = false
		# Check tool ingredient
		if recipe.requires_tool_ingredient != "":
			var have_tool = PlayerData.has_item(recipe.requires_tool_ingredient)
			info["has_tool_ingredient"] = have_tool
			if not have_tool:
				info.can_craft = false
		available.append(info)
	return available
