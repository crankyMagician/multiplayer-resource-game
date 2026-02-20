class_name RegistrySeeder
extends RefCounted

# Populates DataRegistry static dicts directly for testing.
# Sets _loaded = true to prevent filesystem auto-loading.

static func seed_all() -> void:
	DataRegistry._loaded = true
	_seed_moves()
	_seed_abilities()
	_seed_held_items()
	_seed_trainers()
	_seed_battle_items()
	_seed_shops()
	_seed_npcs()
	_seed_locations()
	_seed_quests()
	_seed_tools()
	_seed_fishing_tables()
	_seed_fish_ingredients()
	_seed_fishing_rods()

static func clear_all() -> void:
	DataRegistry.moves.clear()
	DataRegistry.abilities.clear()
	DataRegistry.held_items.clear()
	DataRegistry.trainers.clear()
	DataRegistry.species.clear()
	DataRegistry.ingredients.clear()
	DataRegistry.recipes.clear()
	DataRegistry.foods.clear()
	DataRegistry.tools.clear()
	DataRegistry.recipe_scrolls.clear()
	DataRegistry.encounter_tables.clear()
	DataRegistry.shops.clear()
	DataRegistry.battle_items.clear()
	DataRegistry.npcs.clear()
	DataRegistry.locations.clear()
	DataRegistry.quests.clear()
	DataRegistry.fishing_tables.clear()
	DataRegistry._loaded = false

static func _seed_moves() -> void:
	# A selection of moves used by tests
	_add_move("quick_bite", "Quick Bite", "spicy", "physical", 40, 100, 15, {"is_contact": true})
	_add_move("grain_bash", "Grain Bash", "grain", "physical", 50, 100, 10, {"is_contact": true})
	_add_move("flame_burst", "Flame Burst", "spicy", "special", 70, 95, 10)
	_add_move("sweet_beam", "Sweet Beam", "sweet", "special", 65, 100, 10)
	_add_move("sour_spray", "Sour Spray", "sour", "special", 60, 100, 10)
	_add_move("umami_wave", "Umami Wave", "umami", "special", 55, 100, 10)
	_add_move("herbal_slash", "Herbal Slash", "herbal", "physical", 60, 100, 10, {"is_contact": true})
	_add_move("status_burn", "Heat Wave", "spicy", "status", 0, 100, 10, {"status_effect": "burned", "status_chance": 100})
	_add_move("heal_move", "Taste Test", "grain", "status", 0, 100, 5, {"heal_percent": 0.5})
	_add_move("taunt_move", "Taunt", "spicy", "status", 0, 100, 10, {"taunt": true})
	_add_move("trick_room_move", "Trick Room", "sweet", "status", 0, 100, 5, {"trick_room": true})
	_add_move("weather_move", "Sizzle Sun", "spicy", "status", 0, 100, 5, {"weather_set": "spicy"})
	_add_move("hazard_move", "Caltrops", "grain", "status", 0, 100, 5, {"hazard_type": "caltrops"})
	_add_move("sub_move", "Substitute", "grain", "status", 0, 100, 5, {"substitute": true})
	_add_move("encore_move", "Encore", "sweet", "status", 0, 100, 5, {"encore": true})
	_add_move("priority_move", "Quick Strike", "spicy", "physical", 40, 100, 10, {"priority": 1, "is_contact": true})
	_add_move("knock_off_move", "Knock Off", "sour", "physical", 65, 100, 10, {"knock_off": true, "is_contact": true})
	_add_move("switch_move", "U-Turn", "herbal", "physical", 55, 100, 10, {"switch_after": true, "is_contact": true})
	_add_move("multi_hit", "Multi Hit", "spicy", "physical", 25, 100, 10, {"multi_hit_min": 2, "multi_hit_max": 5, "is_contact": true})
	_add_move("protect_move", "Protect", "grain", "status", 0, 100, 5, {"is_protection": true, "priority": 4})
	_add_move("force_switch_move", "Roar", "grain", "status", 0, 100, 5, {"force_switch": true})
	_add_move("hazard_clear", "Rapid Spin", "grain", "physical", 25, 100, 10, {"clears_hazards": true, "is_contact": true})
	_add_move("crit_boost_move", "Focus Energy", "grain", "status", 0, 100, 10, {"self_crit_stage_change": 2})
	_add_move("stat_boost_move", "Sharpen", "grain", "status", 0, 100, 10, {"stat_changes": {"attack": 1}})

static func _add_move(id: String, display: String, type: String, category: String, power: int, accuracy: int, pp_val: int, extras: Dictionary = {}) -> void:
	var m = MoveDef.new()
	m.move_id = id
	m.display_name = display
	m.type = type
	m.category = category
	m.power = power
	m.accuracy = accuracy
	m.pp = pp_val
	m.priority = extras.get("priority", 0)
	m.status_effect = extras.get("status_effect", "")
	m.status_chance = extras.get("status_chance", 0)
	m.stat_changes = extras.get("stat_changes", {})
	m.heal_percent = extras.get("heal_percent", 0.0)
	m.drain_percent = extras.get("drain_percent", 0.0)
	m.is_contact = extras.get("is_contact", false)
	m.recoil_percent = extras.get("recoil_percent", 0.0)
	m.multi_hit_min = extras.get("multi_hit_min", 0)
	m.multi_hit_max = extras.get("multi_hit_max", 0)
	m.is_protection = extras.get("is_protection", false)
	m.weather_set = extras.get("weather_set", "")
	m.hazard_type = extras.get("hazard_type", "")
	m.clears_hazards = extras.get("clears_hazards", false)
	m.switch_after = extras.get("switch_after", false)
	m.force_switch = extras.get("force_switch", false)
	m.trick_room = extras.get("trick_room", false)
	m.taunt = extras.get("taunt", false)
	m.encore = extras.get("encore", false)
	m.substitute = extras.get("substitute", false)
	m.knock_off = extras.get("knock_off", false)
	m.self_crit_stage_change = extras.get("self_crit_stage_change", 0)
	DataRegistry.moves[id] = m

static func _seed_abilities() -> void:
	_add_ability("sour_aura", "Sour Aura", "on_enter")
	_add_ability("grain_shield", "Grain Shield", "on_enter")
	_add_ability("scoville_aura", "Scoville Aura", "on_enter")
	_add_ability("ferment_cloud", "Ferment Cloud", "on_enter")
	_add_ability("flash_fry", "Flash Fry", "on_attack")
	_add_ability("deep_umami", "Deep Umami", "on_attack")
	_add_ability("sharp_zest", "Sharp Zest", "on_attack")
	_add_ability("scoville_boost", "Scoville Boost", "on_attack")
	_add_ability("stretchy", "Stretchy", "on_attack")
	_add_ability("brine_body", "Brine Body", "on_defend")
	_add_ability("crusty_armor", "Crusty Armor", "on_defend")
	_add_ability("herbivore", "Herbivore", "on_defend")
	_add_ability("flavor_absorb", "Flavor Absorb", "on_defend")
	_add_ability("flash_freeze", "Flash Freeze", "on_defend")
	_add_ability("sugar_coat", "Sugar Coat", "on_status")
	_add_ability("firm_press", "Firm Press", "on_status")
	_add_ability("starter_culture", "Starter Culture", "end_of_turn")
	_add_ability("mycelium_net", "Mycelium Net", "end_of_turn")
	_add_ability("photosynthesis", "Photosynthesis", "end_of_turn")
	_add_ability("fermentation", "Fermentation", "on_weather")

static func _add_ability(id: String, display: String, trigger: String) -> void:
	var a = AbilityDef.new()
	a.ability_id = id
	a.display_name = display
	a.trigger = trigger
	DataRegistry.abilities[id] = a

static func _seed_held_items() -> void:
	# Type boosters
	_add_held_item("spice_charm", "Spice Charm", "type_boost", {"type": "spicy", "multiplier": 1.2})
	_add_held_item("sugar_charm", "Sugar Charm", "type_boost", {"type": "sweet", "multiplier": 1.2})
	# Choice items
	_add_held_item("choice_fork", "Choice Fork", "choice_lock", {"stat": "attack", "multiplier": 1.5})
	_add_held_item("choice_spoon", "Choice Spoon", "choice_lock", {"stat": "sp_attack", "multiplier": 1.5})
	_add_held_item("choice_whisk", "Choice Whisk", "choice_lock", {"stat": "speed", "multiplier": 1.5})
	# Life orb
	_add_held_item("life_orb", "Life Orb", "life_orb", {"damage_multiplier": 1.3})
	# Damage reduction
	_add_held_item("iron_plate", "Iron Plate", "damage_reduction", {"category": "physical", "multiplier": 0.8})
	_add_held_item("spell_guard", "Spell Guard", "damage_reduction", {"category": "special", "multiplier": 0.8})
	# End of turn heal
	_add_held_item("leftovers", "Leftovers", "end_of_turn", {"heal_percent": 0.0625})
	# Status cure
	_add_held_item("ginger_root", "Ginger Root", "on_status", {"cure_status": true}, true)
	# Focus sash
	_add_held_item("focus_spatula", "Focus Spatula", "focus_sash", {})
	# HP threshold items
	_add_held_item("espresso_shot", "Espresso Shot", "on_hp_threshold", {"hp_threshold": 0.25, "stat": "speed", "multiplier": 1.5}, true)
	_add_held_item("golden_truffle", "Golden Truffle", "on_hp_threshold", {"hp_threshold": 0.25, "heal_percent": 0.25}, true)
	# Crit boost
	_add_held_item("precision_grater", "Precision Grater", "crit_boost", {})

static func _add_held_item(id: String, display: String, effect_type: String, params: Dictionary, consumable: bool = false) -> void:
	var h = HeldItemDef.new()
	h.item_id = id
	h.display_name = display
	h.effect_type = effect_type
	h.effect_params = params
	h.consumable = consumable
	DataRegistry.held_items[id] = h

static func _seed_trainers() -> void:
	var t = TrainerDef.new()
	t.trainer_id = "test_easy"
	t.display_name = "Test Easy Trainer"
	t.ai_difficulty = "easy"
	DataRegistry.trainers["test_easy"] = t

	var t2 = TrainerDef.new()
	t2.trainer_id = "test_medium"
	t2.display_name = "Test Medium Trainer"
	t2.ai_difficulty = "medium"
	DataRegistry.trainers["test_medium"] = t2

	var t3 = TrainerDef.new()
	t3.trainer_id = "test_hard"
	t3.display_name = "Test Hard Trainer"
	t3.ai_difficulty = "hard"
	DataRegistry.trainers["test_hard"] = t3

static func _seed_battle_items() -> void:
	_add_battle_item("herb_poultice", "Herb Poultice", "heal_hp", 30)
	_add_battle_item("spicy_tonic", "Spicy Tonic", "heal_hp", 60)
	_add_battle_item("full_feast", "Full Feast", "heal_hp", 9999)
	_add_battle_item("mint_extract", "Mint Extract", "cure_status", 0)
	_add_battle_item("flavor_essence", "Flavor Essence", "restore_pp", 5)
	_add_battle_item("revival_soup", "Revival Soup", "revive", 50)

static func _add_battle_item(id: String, display: String, effect_type: String, effect_value: int) -> void:
	var bi = BattleItemDef.new()
	bi.item_id = id
	bi.display_name = display
	bi.effect_type = effect_type
	bi.effect_value = effect_value
	bi.target = "single"
	DataRegistry.battle_items[id] = bi

static func _seed_shops() -> void:
	var shop = ShopDef.new()
	shop.shop_id = "test_general"
	shop.display_name = "Test General Store"
	shop.items_for_sale.append({"item_id": "herb_poultice", "buy_price": 100})
	shop.items_for_sale.append({"item_id": "spicy_tonic", "buy_price": 200})
	DataRegistry.shops["test_general"] = shop

static func _seed_npcs() -> void:
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
		"neutral": [{"text": "Hello.", "choices": [
			{"label": "Hi!", "points": 3, "response": "Nice!"},
		]}],
		"like": [{"text": "Friend!", "choices": []}],
		"love": [{"text": "Best friend!", "choices": []}],
		"dislike": [{"text": "Oh.", "choices": []}],
		"hate": [{"text": "Leave.", "choices": []}],
		"birthday": [{"text": "My birthday!", "choices": []}],
	}
	npc.npc_gifts = [{"threshold": 20, "item_id": "grain_wheat", "quantity": 3, "message": "A gift!"}]
	npc.occupation = "Tester"
	npc.schedule = [
		{"time_start": 0.0, "time_end": 0.5, "position": {"x": 0, "y": 1, "z": 0}, "seasons": []},
		{"time_start": 0.5, "time_end": 1.0, "position": {"x": 10, "y": 1, "z": 10}, "seasons": []},
	]
	DataRegistry.npcs["test_npc"] = npc

static func _seed_locations() -> void:
	var loc1 = LocationDef.new()
	loc1.location_id = "test_hub"
	loc1.display_name = "Test Hub"
	loc1.world_position = Vector3(0, 0, 0)
	loc1.discovery_radius = 10.0
	loc1.category = "zone"
	loc1.icon_color = Color.WHITE
	DataRegistry.locations["test_hub"] = loc1

	var loc2 = LocationDef.new()
	loc2.location_id = "test_shop"
	loc2.display_name = "Test Shop"
	loc2.world_position = Vector3(20, 0, 0)
	loc2.discovery_radius = 5.0
	loc2.category = "shop"
	loc2.icon_color = Color.TEAL
	DataRegistry.locations["test_shop"] = loc2

	var loc3 = LocationDef.new()
	loc3.location_id = "test_wild"
	loc3.display_name = "Test Wild Zone"
	loc3.world_position = Vector3(0, 0, -30)
	loc3.discovery_radius = 8.0
	loc3.category = "wild_zone"
	loc3.icon_color = Color.GREEN
	DataRegistry.locations["test_wild"] = loc3

	var loc4 = LocationDef.new()
	loc4.location_id = "test_crafting"
	loc4.display_name = "Test Workbench"
	loc4.world_position = Vector3(10, 0, 10)
	loc4.discovery_radius = 5.0
	loc4.category = "crafting"
	loc4.icon_color = Color.ORANGE
	DataRegistry.locations["test_crafting"] = loc4

	var loc5 = LocationDef.new()
	loc5.location_id = "test_trainer"
	loc5.display_name = "Test Trainer Spot"
	loc5.world_position = Vector3(-15, 0, 5)
	loc5.discovery_radius = 6.0
	loc5.category = "trainer"
	loc5.icon_color = Color.RED
	DataRegistry.locations["test_trainer"] = loc5

	var loc6 = LocationDef.new()
	loc6.location_id = "test_social_npc"
	loc6.display_name = "Test NPC House"
	loc6.world_position = Vector3(5, 0, -10)
	loc6.discovery_radius = 5.0
	loc6.category = "social_npc"
	loc6.icon_color = Color.PINK
	DataRegistry.locations["test_social_npc"] = loc6

	var loc7 = LocationDef.new()
	loc7.location_id = "test_landmark"
	loc7.display_name = "Test Landmark"
	loc7.world_position = Vector3(-20, 0, -20)
	loc7.discovery_radius = 10.0
	loc7.category = "landmark"
	loc7.icon_color = Color.YELLOW
	DataRegistry.locations["test_landmark"] = loc7

static func _seed_quests() -> void:
	# Side quest: collect (cumulative)
	var QDef = load("res://scripts/data/quest_def.gd")
	var q1 = QDef.new()
	q1.quest_id = "test_collect"
	q1.display_name = "Test Collect Quest"
	q1.description = "Collect 5 items."
	q1.category = "side"
	q1.quest_giver_npc_id = "test_npc"
	q1.objectives = [{"type": "collect", "target_id": "", "target_count": 5, "description": "Collect 5 items"}]
	q1.reward_money = 100
	DataRegistry.quests["test_collect"] = q1

	# Daily quest: defeat creatures
	var q2 = QDef.new()
	q2.quest_id = "test_daily"
	q2.display_name = "Test Daily Quest"
	q2.description = "Defeat 2 creatures."
	q2.category = "daily"
	q2.quest_giver_npc_id = "test_npc"
	q2.objectives = [{"type": "defeat_creature", "target_id": "", "target_count": 2, "description": "Defeat 2 creatures"}]
	q2.reward_money = 25
	DataRegistry.quests["test_daily"] = q2

	# Weekly quest
	var q2w = QDef.new()
	q2w.quest_id = "test_weekly"
	q2w.display_name = "Test Weekly Quest"
	q2w.description = "Weekly gathering."
	q2w.category = "weekly"
	q2w.quest_giver_npc_id = "test_npc"
	q2w.objectives = [{"type": "collect", "target_id": "", "target_count": 10, "description": "Collect 10 items"}]
	q2w.reward_money = 100
	DataRegistry.quests["test_weekly"] = q2w

	# Delivery quest
	var q3 = QDef.new()
	q3.quest_id = "test_delivery"
	q3.display_name = "Test Delivery Quest"
	q3.description = "Deliver 3 wheat."
	q3.category = "side"
	q3.quest_giver_npc_id = "test_npc"
	q3.objectives = [{"type": "deliver", "target_id": "wheat", "target_count": 3, "description": "Deliver 3 Wheat", "deliver_to_npc": "test_npc", "consumes_items": true}]
	q3.reward_money = 200
	q3.reward_items = {"herb_basil": 5}
	DataRegistry.quests["test_delivery"] = q3

	# Main story chain: quest 1
	var q4 = QDef.new()
	q4.quest_id = "test_ms_01"
	q4.display_name = "Main Story 1"
	q4.description = "First main story quest."
	q4.category = "main_story"
	q4.quest_giver_npc_id = "test_npc"
	q4.objectives = [{"type": "talk_to", "target_id": "test_npc", "target_count": 1, "description": "Talk to Test NPC"}]
	q4.reward_money = 50
	q4.reward_unlock_flag = "ms_01_done"
	q4.next_quest_id = "test_ms_02"
	q4.chapter = 1
	q4.sort_order = 1
	DataRegistry.quests["test_ms_01"] = q4

	# Main story chain: quest 2
	var q5 = QDef.new()
	q5.quest_id = "test_ms_02"
	q5.display_name = "Main Story 2"
	q5.description = "Second main story quest."
	q5.category = "main_story"
	q5.quest_giver_npc_id = "test_npc"
	q5.prereq_quest_ids = ["test_ms_01"]
	q5.objectives = [{"type": "defeat_trainer", "target_id": "test_easy", "target_count": 1, "description": "Defeat Test Easy Trainer"}]
	q5.reward_money = 150
	q5.chapter = 1
	q5.sort_order = 2
	DataRegistry.quests["test_ms_02"] = q5

	# Quest with friendship prereq
	var q6 = QDef.new()
	q6.quest_id = "test_prereq_friendship"
	q6.display_name = "Friendship Quest"
	q6.description = "Requires friendship."
	q6.category = "side"
	q6.quest_giver_npc_id = "test_npc"
	q6.prereq_friendship = {"test_npc": 20}
	q6.objectives = [{"type": "collect", "target_id": "", "target_count": 1, "description": "Collect 1 item"}]
	q6.reward_money = 50
	DataRegistry.quests["test_prereq_friendship"] = q6

	# Quest with location prereq
	var q7 = QDef.new()
	q7.quest_id = "test_prereq_location"
	q7.display_name = "Location Quest"
	q7.description = "Requires location discovery."
	q7.category = "side"
	q7.quest_giver_npc_id = "test_npc"
	q7.prereq_locations = ["test_wild"]
	q7.objectives = [{"type": "collect", "target_id": "", "target_count": 1, "description": "Collect 1 item"}]
	q7.reward_money = 50
	DataRegistry.quests["test_prereq_location"] = q7

	# Quest with main story prereq
	var q8 = QDef.new()
	q8.quest_id = "test_prereq_ms"
	q8.display_name = "Post-Story Quest"
	q8.description = "Requires main story completion."
	q8.category = "side"
	q8.quest_giver_npc_id = "test_npc"
	q8.prereq_main_story_quest_id = "test_ms_01"
	q8.objectives = [{"type": "collect", "target_id": "", "target_count": 1, "description": "Collect 1 item"}]
	q8.reward_money = 50
	DataRegistry.quests["test_prereq_ms"] = q8

	# Quest from different NPC
	var q9 = QDef.new()
	q9.quest_id = "test_other_npc"
	q9.display_name = "Other NPC Quest"
	q9.description = "From another NPC."
	q9.category = "side"
	q9.quest_giver_npc_id = "other_npc"
	q9.objectives = [{"type": "collect", "target_id": "", "target_count": 1, "description": "Collect 1 item"}]
	q9.reward_money = 50
	DataRegistry.quests["test_other_npc"] = q9

	# Multi-objective quest
	var q10 = QDef.new()
	q10.quest_id = "test_multi_obj"
	q10.display_name = "Multi Objective Quest"
	q10.description = "Multiple objectives."
	q10.category = "side"
	q10.quest_giver_npc_id = "test_npc"
	q10.objectives = [
		{"type": "defeat_creature", "target_id": "", "target_count": 2, "description": "Defeat 2 creatures"},
		{"type": "discover_location", "target_id": "test_wild", "target_count": 1, "description": "Discover Test Wild Zone"},
	]
	q10.reward_money = 300
	DataRegistry.quests["test_multi_obj"] = q10

static func _seed_tools() -> void:
	_add_tool("tool_hoe_basic", "Basic Hoe", "hoe", 0, {"speed_mult": 1.0})
	_add_tool("tool_hoe_bronze", "Bronze Hoe", "hoe", 1, {"speed_mult": 1.3})
	_add_tool("tool_hoe_iron", "Iron Hoe", "hoe", 2, {"speed_mult": 1.6})
	_add_tool("tool_hoe_gold", "Gold Hoe", "hoe", 3, {"speed_mult": 2.0})
	_add_tool("tool_axe_basic", "Basic Axe", "axe", 0, {"speed_mult": 1.0})
	_add_tool("tool_axe_bronze", "Bronze Axe", "axe", 1, {"speed_mult": 1.3})
	_add_tool("tool_axe_iron", "Iron Axe", "axe", 2, {"speed_mult": 1.6})
	_add_tool("tool_axe_gold", "Gold Axe", "axe", 3, {"speed_mult": 2.0})
	_add_tool("tool_watering_can_basic", "Basic Watering Can", "watering_can", 0, {"speed_mult": 1.0, "capacity": 10})
	_add_tool("tool_watering_can_bronze", "Bronze Watering Can", "watering_can", 1, {"speed_mult": 1.3, "capacity": 15})
	_add_tool("tool_watering_can_iron", "Iron Watering Can", "watering_can", 2, {"speed_mult": 1.6, "capacity": 20})
	_add_tool("tool_watering_can_gold", "Gold Watering Can", "watering_can", 3, {"speed_mult": 2.0, "capacity": 30})
	_add_tool("tool_shovel_basic", "Basic Shovel", "shovel", 0, {"speed_mult": 1.0})
	_add_tool("tool_shovel_bronze", "Bronze Shovel", "shovel", 1, {"speed_mult": 1.3})
	_add_tool("tool_shovel_iron", "Iron Shovel", "shovel", 2, {"speed_mult": 1.6})
	_add_tool("tool_shovel_gold", "Gold Shovel", "shovel", 3, {"speed_mult": 2.0})

static func _add_tool(id: String, display: String, tool_type: String, tier: int, effectiveness: Dictionary) -> void:
	var t = ToolDef.new()
	t.tool_id = id
	t.display_name = display
	t.tool_type = tool_type
	t.tier = tier
	t.effectiveness = effectiveness
	DataRegistry.tools[id] = t

static func _seed_fishing_tables() -> void:
	# Use a plain Dictionary to avoid class_name resolution issues in headless tests.
	# FishingManager accesses these via dict-like property access (.entries, .table_id, etc.)
	# which works for both Resource instances and Dictionaries via DataRegistry.get().
	# For test purposes, we store a Resource with manually set properties.
	var script = load("res://scripts/data/fishing_table.gd")
	if script == null:
		push_warning("[RegistrySeeder] Could not load fishing_table.gd, skipping fishing table seeding")
		return
	var table = script.new()
	table.table_id = "test_pond"
	table.display_name = "Test Pond"
	table.entries = [
		{"fish_id": "sardine", "weight": 40, "difficulty": 1, "min_rod_tier": 0, "movement_type": "smooth", "season": ""},
		{"fish_id": "bass", "weight": 30, "difficulty": 2, "min_rod_tier": 0, "movement_type": "smooth", "season": ""},
		{"fish_id": "golden_koi", "weight": 2, "difficulty": 5, "min_rod_tier": 2, "movement_type": "mixed", "season": "autumn"},
	]
	table.weather_bonus = {"rainy": "bass"}
	DataRegistry.fishing_tables["test_pond"] = table

static func _seed_fish_ingredients() -> void:
	_add_fish("sardine", "Sardine", 5, "")
	_add_fish("bass", "Bass", 10, "")
	_add_fish("trout", "Trout", 12, "spring")
	_add_fish("golden_koi", "Golden Koi", 50, "autumn")

static func _add_fish(id: String, display: String, price: int, season: String) -> void:
	var ing = IngredientDef.new()
	ing.ingredient_id = id
	ing.display_name = display
	ing.category = "fish"
	ing.sell_price = price
	ing.season = season
	ing.grow_time = 0.0
	ing.harvest_min = 1
	ing.harvest_max = 1
	DataRegistry.ingredients[id] = ing

static func _seed_fishing_rods() -> void:
	_add_tool("tool_fishing_rod_basic", "Basic Fishing Rod", "fishing_rod", 0, {"bar_bonus": 0.0})
	_add_tool("tool_fishing_rod_bronze", "Bronze Fishing Rod", "fishing_rod", 1, {"bar_bonus": 0.05})
	_add_tool("tool_fishing_rod_iron", "Iron Fishing Rod", "fishing_rod", 2, {"bar_bonus": 0.10})
	_add_tool("tool_fishing_rod_gold", "Gold Fishing Rod", "fishing_rod", 3, {"bar_bonus": 0.15})
