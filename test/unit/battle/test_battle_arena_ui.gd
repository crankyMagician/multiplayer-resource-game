extends GutTest

# Tests for battle_arena_ui.gd pure logic functions:
# _format_log_entry, _format_stat_stages, _format_status_with_turns,
# _format_types, _hp_tint_color (on battle_arena.gd)

const BattleArenaUIScript = preload("res://scripts/battle/battle_arena_ui.gd")
const BattleArenaScript = preload("res://scripts/battle/battle_arena.gd")

var ui: Node

func before_each() -> void:
	RegistrySeeder.seed_all()
	ui = Node.new()
	ui.set_script(BattleArenaUIScript)
	add_child(ui)

func after_each() -> void:
	ui.queue_free()
	RegistrySeeder.clear_all()

# === _format_log_entry: move type ===

func test_format_move_basic_damage() -> void:
	var entry = {"type": "move", "actor": "player", "move": "Flame Burst", "damage": 45}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "You used Flame Burst!")
	assert_string_contains(result, "Dealt 45 damage.")

func test_format_move_enemy_actor() -> void:
	var entry = {"type": "move", "actor": "enemy", "move": "Quick Bite", "damage": 20}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Enemy used Quick Bite!")

func test_format_move_missed() -> void:
	var entry = {"type": "move", "actor": "player", "move": "Flame Burst", "missed": true}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "But it missed!")

func test_format_move_skipped() -> void:
	var entry = {"type": "move", "actor": "player", "move": "X", "skipped": true, "message": "is paralyzed!"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "You is paralyzed!")

func test_format_move_charging() -> void:
	var entry = {"type": "move", "actor": "enemy", "move": "X", "charging": true, "message": "is charging up!"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Enemy is charging up!")

func test_format_move_protecting() -> void:
	var entry = {"type": "move", "actor": "player", "move": "Protect", "protecting": true, "message": "protected itself!"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "You protected itself!")

func test_format_move_blocked() -> void:
	var entry = {"type": "move", "actor": "player", "move": "X", "blocked": true, "message": "was blocked!"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "was blocked!")

func test_format_move_immune() -> void:
	var entry = {"type": "move", "actor": "player", "move": "X", "immune": true}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "doesn't affect")

func test_format_move_super_effective() -> void:
	var entry = {"type": "move", "actor": "player", "move": "X", "damage": 50, "effectiveness": "super_effective"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Super effective!")

func test_format_move_not_very_effective() -> void:
	var entry = {"type": "move", "actor": "player", "move": "X", "damage": 20, "effectiveness": "not_very_effective"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Not very effective")

func test_format_move_immune_effectiveness() -> void:
	var entry = {"type": "move", "actor": "player", "move": "X", "damage": 0, "effectiveness": "immune"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "No effect!")

func test_format_move_critical() -> void:
	var entry = {"type": "move", "actor": "player", "move": "X", "damage": 80, "critical": true}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Critical hit!")

func test_format_move_multi_hit() -> void:
	var entry = {"type": "move", "actor": "player", "move": "Multi Hit", "damage": 75, "hit_count": 3}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Hit 3 times!")

func test_format_move_recoil() -> void:
	var entry = {"type": "move", "actor": "player", "move": "X", "damage": 40, "recoil": 10}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "You took 10 recoil!")

func test_format_move_drain_heal() -> void:
	var entry = {"type": "move", "actor": "player", "move": "X", "damage": 40, "drain_heal": 20}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Drained 20 HP!")

func test_format_move_status_applied() -> void:
	var entry = {"type": "move", "actor": "player", "move": "X", "damage": 30, "status_applied": "burned"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Inflicted")

func test_format_move_heal() -> void:
	var entry = {"type": "move", "actor": "player", "move": "Taste Test", "heal": 40}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Healed 40 HP!")

func test_format_move_stat_changes_up() -> void:
	var entry = {"type": "move", "actor": "player", "move": "X", "stat_changes": {"attack": 1}}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Attack")
	assert_string_contains(result, "rose!")

func test_format_move_stat_changes_down() -> void:
	var entry = {"type": "move", "actor": "player", "move": "X", "stat_changes": {"defense": -1}}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Defense")
	assert_string_contains(result, "fell!")

func test_format_move_stat_changes_sharply() -> void:
	var entry = {"type": "move", "actor": "player", "move": "X", "stat_changes": {"attack": 2}}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "sharply")
	assert_string_contains(result, "rose!")

func test_format_move_target_stat_changes() -> void:
	var entry = {"type": "move", "actor": "player", "move": "X", "target_stat_changes": {"speed": -1}}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Foe's Speed fell!")

func test_format_move_weather_set() -> void:
	var entry = {"type": "move", "actor": "player", "move": "X", "weather_set": "spicy"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Sizzle Sun started!")

func test_format_move_hazard_set() -> void:
	var entry = {"type": "move", "actor": "player", "move": "X", "hazard_set": "caltrops"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Set caltrops!")

func test_format_move_hazards_cleared() -> void:
	var entry = {"type": "move", "actor": "player", "move": "X", "hazards_cleared": true}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Cleared hazards!")

func test_format_move_substitute_created() -> void:
	var entry = {"type": "move", "actor": "player", "move": "X", "substitute_created": true}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Created a substitute!")

func test_format_move_substitute_broke() -> void:
	var entry = {"type": "move", "actor": "player", "move": "X", "damage": 50, "substitute_broke": true}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "The substitute broke!")

func test_format_move_substitute_blocked() -> void:
	var entry = {"type": "move", "actor": "player", "move": "X", "damage": 50, "substitute_blocked": true}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "The substitute took the hit!")

func test_format_move_knocked_off_item() -> void:
	var entry = {"type": "move", "actor": "player", "move": "X", "damage": 50, "knocked_off_item": "Life Orb"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Knocked off Life Orb!")

func test_format_move_focus_sash() -> void:
	var entry = {"type": "move", "actor": "player", "move": "X", "damage": 99, "focus_sash_triggered": true}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Focus Spatula")

func test_format_move_bond_endure() -> void:
	var entry = {"type": "move", "actor": "player", "move": "X", "damage": 99, "bond_endure_triggered": true}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "bond with its trainer")

func test_format_move_life_orb_recoil() -> void:
	var entry = {"type": "move", "actor": "player", "move": "X", "damage": 60, "life_orb_recoil": 8}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Lost 8 HP from Flavor Crystal!")

func test_format_move_switch_after() -> void:
	var entry = {"type": "move", "actor": "player", "move": "U-Turn", "damage": 30, "switch_after": true}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Dashed back!")

func test_format_move_force_switch_failed() -> void:
	var entry = {"type": "move", "actor": "player", "move": "Roar", "force_switch_failed": true}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "But it failed!")

# === _format_log_entry: non-move types ===

func test_format_ability_trigger() -> void:
	var entry = {"type": "ability_trigger", "actor": "player", "message": "Scoville Aura raised attack!"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Your creature's Scoville Aura raised attack!")

func test_format_ability_trigger_enemy() -> void:
	var entry = {"type": "ability_trigger", "actor": "enemy", "message": "Grain Shield raised defense!"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Enemy's Grain Shield raised defense!")

func test_format_status_damage() -> void:
	var entry = {"type": "status_damage", "actor": "player", "message": "is hurt by burn!", "damage": 10}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Your creature is hurt by burn!")
	assert_string_contains(result, "10 damage")

func test_format_ability_heal() -> void:
	var entry = {"type": "ability_heal", "actor": "player", "message": "healed with ability!", "heal": 15}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "+15 HP")

func test_format_item_heal() -> void:
	var entry = {"type": "item_heal", "actor": "enemy", "message": "ate leftovers!", "heal": 5}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Enemy ate leftovers!")
	assert_string_contains(result, "+5 HP")

func test_format_weather_cleared() -> void:
	var entry = {"type": "weather_cleared", "weather": "spicy"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Sizzle Sun subsided")

func test_format_hazard_damage() -> void:
	var entry = {"type": "hazard_damage", "actor": "player", "hazard": "caltrops", "damage": 12}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Your creature was hurt by caltrops!")
	assert_string_contains(result, "12 damage")

func test_format_hazard_effect() -> void:
	var entry = {"type": "hazard_effect", "actor": "enemy", "hazard": "sticky web"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Enemy was affected by sticky web!")

func test_format_trick_room_set() -> void:
	var entry = {"type": "trick_room_set"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Trick Room")

func test_format_trick_room_ended() -> void:
	var entry = {"type": "trick_room_ended"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Trick Room wore off")

func test_format_taunt_applied() -> void:
	var entry = {"type": "taunt_applied", "actor": "enemy"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Your creature was taunted!")

func test_format_taunt_ended() -> void:
	var entry = {"type": "taunt_ended", "actor": "player"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Your creature's taunt wore off")

func test_format_encore_applied() -> void:
	var entry = {"type": "encore_applied", "actor": "enemy"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Your creature got an encore!")

func test_format_encore_ended() -> void:
	var entry = {"type": "encore_ended", "actor": "enemy"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Enemy's encore ended")

func test_format_substitute_created() -> void:
	var entry = {"type": "substitute_created", "actor": "player"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Your creature put up a substitute!")

func test_format_substitute_broken() -> void:
	var entry = {"type": "substitute_broken", "actor": "enemy"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Enemy's substitute broke!")

func test_format_forced_switch() -> void:
	var entry = {"type": "forced_switch", "actor": "player"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Your creature was forced out!")

func test_format_force_switch_failed_type() -> void:
	var entry = {"type": "force_switch_failed"}
	var result = ui._format_log_entry(entry)
	assert_eq(result, "But it failed!")

func test_format_bond_cured() -> void:
	var entry = {"type": "bond_cured", "actor": "player", "status": "burned"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "bond cured its burned")

func test_format_sleep_talk_move() -> void:
	var entry = {"type": "sleep_talk_move", "actor": "enemy"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Enemy used a move in its sleep!")

func test_format_item_use() -> void:
	var entry = {"type": "item_use", "item_name": "Herb Poultice", "creature_name": "Chili Drake", "message": "Healed 30 HP!"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Used Herb Poultice on Chili Drake!")

func test_format_trainer_switch() -> void:
	var entry = {"type": "trainer_switch"}
	var result = ui._format_log_entry(entry)
	assert_eq(result, "Trainer sent out the next creature!")

func test_format_victory() -> void:
	var entry = {"type": "victory"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "Victory!")

func test_format_defeat() -> void:
	var entry = {"type": "defeat"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "creatures fainted")

func test_format_fled() -> void:
	var entry = {"type": "fled"}
	var result = ui._format_log_entry(entry)
	assert_eq(result, "Got away safely!")

func test_format_flee_failed() -> void:
	var entry = {"type": "flee_failed"}
	var result = ui._format_log_entry(entry)
	assert_eq(result, "Couldn't escape!")

func test_format_fainted() -> void:
	var entry = {"type": "fainted"}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "creature fainted")
	assert_string_contains(result, "Switch to another!")

func test_format_switch() -> void:
	var entry = {"type": "switch"}
	var result = ui._format_log_entry(entry)
	assert_eq(result, "Switched creature!")

func test_format_unknown_type_returns_empty() -> void:
	var entry = {"type": "nonexistent_type"}
	var result = ui._format_log_entry(entry)
	assert_eq(result, "")

# === _format_stat_stages ===

func test_format_stat_stages_empty() -> void:
	var result = ui._format_stat_stages({})
	assert_eq(result, "")

func test_format_stat_stages_zero_values_ignored() -> void:
	var result = ui._format_stat_stages({"attack": 0, "defense": 0})
	assert_eq(result, "")

func test_format_stat_stages_positive() -> void:
	var result = ui._format_stat_stages({"attack": 2})
	assert_string_contains(result, "ATK")
	assert_string_contains(result, "+2")

func test_format_stat_stages_negative() -> void:
	var result = ui._format_stat_stages({"speed": -1})
	assert_string_contains(result, "SPE")
	assert_string_contains(result, "-1")

func test_format_stat_stages_multiple() -> void:
	var result = ui._format_stat_stages({"attack": 1, "sp_defense": -2})
	assert_string_contains(result, "ATK")
	assert_string_contains(result, "SPD")

# === _format_status_with_turns ===

func test_format_status_empty() -> void:
	var result = ui._format_status_with_turns("", 0)
	assert_eq(result, "")

func test_format_status_poisoned_escalating() -> void:
	var result = ui._format_status_with_turns("poisoned", 3)
	assert_string_contains(result, "escalating")

func test_format_status_burned_with_turns() -> void:
	var result = ui._format_status_with_turns("burned", 2)
	assert_string_contains(result, "2/5 turns")

func test_format_status_frozen_with_turns() -> void:
	var result = ui._format_status_with_turns("frozen", 1)
	assert_string_contains(result, "1/5 turns")

func test_format_status_wilted_with_turns() -> void:
	var result = ui._format_status_with_turns("wilted", 2)
	assert_string_contains(result, "2/3 turns")

# === _format_types ===

func test_format_types_single() -> void:
	var result = ui._format_types(["spicy"])
	assert_eq(result, "Spicy")

func test_format_types_dual() -> void:
	var result = ui._format_types(["spicy", "sweet"])
	assert_eq(result, "Spicy, Sweet")

func test_format_types_empty() -> void:
	var result = ui._format_types([])
	assert_eq(result, "")

# === _hp_tint_color (on battle_arena.gd) ===

func test_hp_tint_color_high() -> void:
	var arena = Node3D.new()
	arena.set_script(BattleArenaScript)
	add_child(arena)
	var color = arena._hp_tint_color(0.8)
	# Should be green (STAMP_GREEN)
	assert_eq(color, preload("res://scripts/ui/ui_tokens.gd").STAMP_GREEN)
	arena.queue_free()

func test_hp_tint_color_medium() -> void:
	var arena = Node3D.new()
	arena.set_script(BattleArenaScript)
	add_child(arena)
	var color = arena._hp_tint_color(0.4)
	# Should be gold (STAMP_GOLD)
	assert_eq(color, preload("res://scripts/ui/ui_tokens.gd").STAMP_GOLD)
	arena.queue_free()

func test_hp_tint_color_low() -> void:
	var arena = Node3D.new()
	arena.set_script(BattleArenaScript)
	add_child(arena)
	var color = arena._hp_tint_color(0.1)
	# Should be red (STAMP_RED)
	assert_eq(color, preload("res://scripts/ui/ui_tokens.gd").STAMP_RED)
	arena.queue_free()

func test_hp_tint_color_boundary_50() -> void:
	var arena = Node3D.new()
	arena.set_script(BattleArenaScript)
	add_child(arena)
	# Exactly 0.5 should be gold (not green, since > 0.5 is the threshold)
	var color = arena._hp_tint_color(0.5)
	assert_eq(color, preload("res://scripts/ui/ui_tokens.gd").STAMP_GOLD)
	arena.queue_free()

func test_hp_tint_color_boundary_25() -> void:
	var arena = Node3D.new()
	arena.set_script(BattleArenaScript)
	add_child(arena)
	# Exactly 0.25 should be red (not gold, since > 0.25 is the threshold)
	var color = arena._hp_tint_color(0.25)
	assert_eq(color, preload("res://scripts/ui/ui_tokens.gd").STAMP_RED)
	arena.queue_free()

# === _hp_tint_color (on battle_arena_ui.gd — duplicated from arena for 2D cards) ===

func test_ui_hp_tint_color_high() -> void:
	var color = ui._hp_tint_color(0.8)
	assert_eq(color, Color(0.3, 0.8, 0.3))

func test_ui_hp_tint_color_medium() -> void:
	var color = ui._hp_tint_color(0.4)
	assert_eq(color, Color(0.95, 0.75, 0.1))

func test_ui_hp_tint_color_low() -> void:
	var color = ui._hp_tint_color(0.1)
	assert_eq(color, Color(0.9, 0.2, 0.2))

func test_ui_hp_tint_color_boundary_50() -> void:
	var color = ui._hp_tint_color(0.5)
	assert_eq(color, Color(0.95, 0.75, 0.1))

func test_ui_hp_tint_color_boundary_25() -> void:
	var color = ui._hp_tint_color(0.25)
	assert_eq(color, Color(0.9, 0.2, 0.2))

# === _has_any_positive ===

func test_has_any_positive_true() -> void:
	assert_true(ui._has_any_positive({"attack": 1, "defense": -1}))

func test_has_any_positive_false_all_negative() -> void:
	assert_false(ui._has_any_positive({"attack": -1, "defense": -2}))

func test_has_any_positive_false_empty() -> void:
	assert_false(ui._has_any_positive({}))

func test_has_any_positive_false_all_zero() -> void:
	assert_false(ui._has_any_positive({"attack": 0}))

# === BattleEffects preload ===

func test_battle_effects_preload() -> void:
	var BattleEffects = preload("res://scripts/battle/battle_effects.gd")
	assert_not_null(BattleEffects)

# === Compound log entry ===

func test_format_move_compound_entry() -> void:
	var entry = {
		"type": "move",
		"actor": "player",
		"move": "Flame Burst",
		"damage": 90,
		"effectiveness": "super_effective",
		"critical": true,
		"stat_changes": {"sp_attack": 1},
		"status_applied": "burned",
	}
	var result = ui._format_log_entry(entry)
	assert_string_contains(result, "You used Flame Burst!")
	assert_string_contains(result, "Dealt 90 damage.")
	assert_string_contains(result, "Super effective!")
	assert_string_contains(result, "Critical hit!")
	assert_string_contains(result, "rose!")
	assert_string_contains(result, "Inflicted")
