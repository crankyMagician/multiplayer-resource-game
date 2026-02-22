extends GutTest

# Tests for debug action handling logic.
# We test the validation and error paths of _handle_debug_action which return
# messages without calling RPCs. For store-mutation actions, we test the
# underlying server_add_* helpers and validate return messages from error paths.
#
# Testing approach: since _handle_debug_action calls RPCs internally for sync,
# and those fail without multiplayer peers, we focus on:
# 1. Error paths that return before any RPC
# 2. Store mutation helpers (server_add_inventory, server_add_money)
# 3. Unknown action handling

const FAKE_PEER := 999

func before_each() -> void:
	RegistrySeeder.seed_all()
	NetworkManager.player_data_store.clear()

func after_each() -> void:
	RegistrySeeder.clear_all()
	NetworkManager.player_data_store.clear()

# === Unknown Action ===

func test_unknown_action_returns_error() -> void:
	NetworkManager.player_data_store[FAKE_PEER] = {"inventory": {}, "money": 0, "party": []}
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "nonexistent_action", {})
	assert_eq(msg, "Unknown action: nonexistent_action")

# === No Player Data ===

func test_give_item_no_player_data() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "give_item", {"item_id": "herb", "qty": 1})
	assert_eq(msg, "No player data")

func test_give_money_no_player_data() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "give_money", {"amount": 100})
	assert_eq(msg, "No player data")

func test_heal_party_no_player_data() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "heal_party", {})
	assert_eq(msg, "No player data")

func test_unlock_all_recipes_no_player_data() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "unlock_all_recipes", {})
	assert_eq(msg, "No player data")

func test_set_creature_level_no_player_data() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "set_creature_level", {"party_idx": 0, "level": 10})
	assert_eq(msg, "No player data")

func test_max_all_creatures_no_player_data() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "max_all_creatures", {})
	assert_eq(msg, "No player data")

func test_force_evolve_no_player_data() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "force_evolve", {"party_idx": 0})
	assert_eq(msg, "No player data")

func test_reset_quests_no_player_data() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "reset_quests", {})
	assert_eq(msg, "No player data")

func test_set_friendship_no_player_data() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "set_friendship", {"npc_id": "npc_01", "points": 50})
	assert_eq(msg, "No player data")

func test_max_all_friendships_no_player_data() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "max_all_friendships", {})
	assert_eq(msg, "No player data")

# === Invalid Party Index ===

func test_set_creature_level_invalid_index() -> void:
	NetworkManager.player_data_store[FAKE_PEER] = {"party": []}
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "set_creature_level", {"party_idx": 5, "level": 10})
	assert_string_contains(msg, "Invalid party index")

func test_force_evolve_invalid_index() -> void:
	NetworkManager.player_data_store[FAKE_PEER] = {"party": []}
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "force_evolve", {"party_idx": 0})
	assert_string_contains(msg, "Invalid party index")

# === Node-Not-Found Errors ===

func test_set_time_no_season_manager() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "set_time", {"year": 1, "month": 3, "day": 1})
	assert_eq(msg, "SeasonManager not found")

func test_advance_day_no_season_manager() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "advance_day", {})
	assert_eq(msg, "SeasonManager not found")

func test_set_time_speed_no_season_manager() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "set_time_speed", {"multiplier": 5})
	assert_eq(msg, "SeasonManager not found")

func test_wild_battle_unknown_species() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "wild_battle", {"species_id": "nonexistent_creature_xyz"})
	assert_string_contains(msg, "Unknown species")

func test_teleport_no_player_node() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "teleport", {"x": 0, "y": 1, "z": 3})
	assert_eq(msg, "Player node not found")

func test_force_grow_no_farm_manager() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "force_grow_plots", {})
	assert_eq(msg, "FarmManager not found")

func test_reset_plots_no_farm_manager() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "reset_plots", {})
	assert_eq(msg, "FarmManager not found")

func test_complete_quest_no_quest_manager() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "complete_quest", {"quest_id": "q1"})
	assert_eq(msg, "QuestManager not found")

func test_end_excursion_no_excursion_manager() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "end_excursion", {})
	assert_eq(msg, "ExcursionManager not found")

# Battle actions with no BattleManager
func test_battle_force_win_no_battle_manager() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "battle_force_win", {})
	assert_eq(msg, "BattleManager not found")

func test_battle_force_lose_no_battle_manager() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "battle_force_lose", {})
	assert_eq(msg, "BattleManager not found")

func test_battle_set_hp_no_battle_manager() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "battle_set_hp", {"side": "player", "hp": 50})
	assert_eq(msg, "BattleManager not found")

func test_battle_set_status_no_battle_manager() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "battle_set_status", {"side": "player", "status": "burn"})
	assert_eq(msg, "BattleManager not found")

func test_battle_heal_no_battle_manager() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "battle_heal", {})
	assert_eq(msg, "BattleManager not found")

func test_battle_set_weather_no_battle_manager() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "battle_set_weather", {"weather": "rain", "turns": 5})
	assert_eq(msg, "BattleManager not found")

func test_battle_clear_hazards_no_battle_manager() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "battle_clear_hazards", {})
	assert_eq(msg, "BattleManager not found")

func test_battle_max_pp_no_battle_manager() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "battle_max_pp", {})
	assert_eq(msg, "BattleManager not found")

func test_battle_set_stat_stage_no_battle_manager() -> void:
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "battle_set_stat_stage", {"side": "player", "stat": "attack", "value": 6})
	assert_eq(msg, "BattleManager not found")

# === Store Mutation Helpers ===

func test_server_add_inventory_creates_entry() -> void:
	NetworkManager.player_data_store[FAKE_PEER] = {"inventory": {}}
	NetworkManager.server_add_inventory(FAKE_PEER, "herb_poultice", 5)
	var inv = NetworkManager.player_data_store[FAKE_PEER]["inventory"]
	assert_eq(inv.get("herb_poultice", 0), 5)

func test_server_add_inventory_stacks() -> void:
	NetworkManager.player_data_store[FAKE_PEER] = {"inventory": {"herb_poultice": 3}}
	NetworkManager.server_add_inventory(FAKE_PEER, "herb_poultice", 7)
	var inv = NetworkManager.player_data_store[FAKE_PEER]["inventory"]
	assert_eq(inv["herb_poultice"], 10)

func test_server_add_money_adds() -> void:
	NetworkManager.player_data_store[FAKE_PEER] = {"money": 100}
	NetworkManager.server_add_money(FAKE_PEER, 500)
	assert_eq(int(NetworkManager.player_data_store[FAKE_PEER]["money"]), 600)

func test_server_add_money_no_player() -> void:
	# Should not crash
	NetworkManager.server_add_money(FAKE_PEER, 500)
	assert_false(FAKE_PEER in NetworkManager.player_data_store)

func test_server_add_inventory_no_player() -> void:
	# Should not crash
	NetworkManager.server_add_inventory(FAKE_PEER, "herb", 1)
	assert_false(FAKE_PEER in NetworkManager.player_data_store)

# === Reset Quests Store Mutation ===
# reset_quests modifies store then calls RPC. We can verify store change
# since it errors on the RPC but the store is already mutated.

func test_reset_quests_clears_quest_data() -> void:
	NetworkManager.player_data_store[FAKE_PEER] = {
		"quests": {
			"active": {"q1": {"objectives": []}},
			"completed": {"q0": true},
			"daily_reset_day": 5,
			"weekly_reset_day": 2,
			"unlock_flags": ["flag1"]
		}
	}
	# This will call _sync_quest_state RPC which will error, but store is mutated first
	# Use _handle_debug_action which returns the message
	var msg := NetworkManager._handle_debug_action(FAKE_PEER, "reset_quests", {})
	assert_eq(msg, "All quests reset")
	var quests = NetworkManager.player_data_store[FAKE_PEER]["quests"]
	assert_eq(quests["active"].size(), 0)
	assert_eq(quests["completed"].size(), 0)
	assert_eq(quests["daily_reset_day"], 0)
	assert_eq(quests["weekly_reset_day"], 0)
	assert_eq(quests["unlock_flags"].size(), 0)
