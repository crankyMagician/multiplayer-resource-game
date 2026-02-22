extends GutTest

# Tests for BattleCalculator pure static methods (no DataRegistry needed)
# Uses class_name directly — NO preload

# --- get_type_effectiveness ---

func test_super_effective_single_type():
	assert_eq(BattleCalculator.get_type_effectiveness("spicy", ["sweet"]), 2.0)

func test_super_effective_spicy_vs_herbal():
	assert_eq(BattleCalculator.get_type_effectiveness("spicy", ["herbal"]), 2.0)

func test_not_very_effective():
	assert_eq(BattleCalculator.get_type_effectiveness("spicy", ["sour"]), 0.5)

func test_immune_sour_vs_grain():
	assert_eq(BattleCalculator.get_type_effectiveness("sour", ["grain"]), 0.0)

func test_immune_herbal_vs_umami():
	assert_eq(BattleCalculator.get_type_effectiveness("herbal", ["umami"]), 0.0)

func test_dual_type_double_super():
	# spicy vs [sweet, herbal] = 2.0 * 2.0 = 4.0
	assert_eq(BattleCalculator.get_type_effectiveness("spicy", ["sweet", "herbal"]), 4.0)

func test_dual_type_mixed():
	# spicy vs [sweet, sour] = 2.0 * 0.5 = 1.0
	assert_eq(BattleCalculator.get_type_effectiveness("spicy", ["sweet", "sour"]), 1.0)

func test_neutral_type():
	# spicy vs grain = 1.0 (not in chart)
	assert_eq(BattleCalculator.get_type_effectiveness("spicy", ["grain"]), 1.0)

func test_empty_attack_type():
	assert_eq(BattleCalculator.get_type_effectiveness("", ["sweet"]), 1.0)

func test_empty_defender_types():
	assert_eq(BattleCalculator.get_type_effectiveness("spicy", []), 1.0)

func test_unknown_attack_type():
	assert_eq(BattleCalculator.get_type_effectiveness("cosmic", ["sweet"]), 1.0)

func test_all_chart_super_effectives():
	# Verify each super-effective pair (all 18 types)
	var supers = {
		"spicy": ["sweet", "herbal", "dairy"],
		"sweet": ["sour", "umami", "bitter"],
		"sour": ["spicy", "mineral", "dairy"],
		"herbal": ["sour", "sweet", "earthy"],
		"umami": ["herbal", "spicy", "aromatic"],
		"grain": ["sweet", "umami", "protein"],
		"mineral": ["grain", "toxic", "smoked"],
		"earthy": ["mineral", "liquid", "fermented"],
		"liquid": ["spicy", "mineral", "smoked"],
		"aromatic": ["herbal", "toxic", "tropical"],
		"toxic": ["herbal", "earthy", "protein", "dairy"],
		"protein": ["aromatic", "bitter", "spoiled"],
		"tropical": ["earthy", "liquid", "dairy"],
		"dairy": ["bitter", "spoiled", "fermented"],
		"bitter": ["aromatic", "spoiled", "fermented"],
		"spoiled": ["sweet", "toxic", "fermented", "smoked"],
		"fermented": ["protein", "tropical", "smoked"],
		"smoked": ["spicy", "protein"],
	}
	for atk_type in supers:
		for def_type in supers[atk_type]:
			assert_eq(
				BattleCalculator.get_type_effectiveness(atk_type, [def_type]),
				2.0,
				"%s vs %s should be 2.0" % [atk_type, def_type]
			)

func test_all_chart_not_very_effectives():
	# Verify a sampling of not-very-effective pairs for new types
	var resists = {
		"mineral": ["sour", "earthy", "liquid"],
		"earthy": ["herbal", "toxic", "tropical"],
		"liquid": ["herbal", "earthy", "tropical"],
		"aromatic": ["umami", "protein", "bitter"],
		"toxic": ["mineral", "spoiled"],
		"protein": ["grain", "toxic", "smoked"],
		"tropical": ["aromatic", "fermented"],
		"dairy": ["spicy", "sour", "toxic", "tropical"],
		"bitter": ["sweet", "protein", "dairy"],
		"spoiled": ["aromatic", "protein", "dairy"],
		"fermented": ["earthy", "dairy", "bitter", "spoiled"],
		"smoked": ["mineral", "liquid", "spoiled", "fermented"],
	}
	for atk_type in resists:
		for def_type in resists[atk_type]:
			assert_eq(
				BattleCalculator.get_type_effectiveness(atk_type, [def_type]),
				0.5,
				"%s vs %s should be 0.5" % [atk_type, def_type]
			)

func test_all_chart_immunities():
	assert_eq(BattleCalculator.get_type_effectiveness("sour", ["grain"]), 0.0)
	assert_eq(BattleCalculator.get_type_effectiveness("herbal", ["umami"]), 0.0)

func test_new_type_dual_type_defender():
	# sour vs mineral+liquid: mineral SE 2.0, liquid neutral 1.0 = 2.0
	assert_eq(BattleCalculator.get_type_effectiveness("sour", ["mineral", "liquid"]), 2.0)
	# toxic vs earthy+protein = 2.0 * 2.0 = 4.0
	assert_eq(BattleCalculator.get_type_effectiveness("toxic", ["earthy", "protein"]), 4.0)
	# smoked vs mineral+liquid = 0.5 * 0.5 = 0.25
	assert_eq(BattleCalculator.get_type_effectiveness("smoked", ["mineral", "liquid"]), 0.25)
	# dairy vs bitter+spoiled = 2.0 * 2.0 = 4.0
	assert_eq(BattleCalculator.get_type_effectiveness("dairy", ["bitter", "spoiled"]), 4.0)

func test_original_6_types_backward_compat():
	# Ensure original matchups are untouched
	assert_eq(BattleCalculator.get_type_effectiveness("spicy", ["sweet"]), 2.0)
	assert_eq(BattleCalculator.get_type_effectiveness("spicy", ["sour"]), 0.5)
	assert_eq(BattleCalculator.get_type_effectiveness("sweet", ["sour"]), 2.0)
	assert_eq(BattleCalculator.get_type_effectiveness("sweet", ["spicy"]), 0.5)
	assert_eq(BattleCalculator.get_type_effectiveness("sour", ["spicy"]), 2.0)
	assert_eq(BattleCalculator.get_type_effectiveness("sour", ["grain"]), 0.0)
	assert_eq(BattleCalculator.get_type_effectiveness("herbal", ["sour"]), 2.0)
	assert_eq(BattleCalculator.get_type_effectiveness("herbal", ["umami"]), 0.0)
	assert_eq(BattleCalculator.get_type_effectiveness("umami", ["herbal"]), 2.0)
	assert_eq(BattleCalculator.get_type_effectiveness("umami", ["grain"]), 0.5)
	assert_eq(BattleCalculator.get_type_effectiveness("grain", ["sweet"]), 2.0)
	assert_eq(BattleCalculator.get_type_effectiveness("grain", ["sour"]), 0.5)

# --- _stage_multiplier ---

func test_stage_zero():
	assert_eq(BattleCalculator._stage_multiplier(0), 1.0)

func test_stage_plus_one():
	assert_eq(BattleCalculator._stage_multiplier(1), 1.5)

func test_stage_plus_six():
	assert_eq(BattleCalculator._stage_multiplier(6), 4.0)

func test_stage_minus_one():
	assert_almost_eq(BattleCalculator._stage_multiplier(-1), 2.0 / 3.0, 0.001)

func test_stage_minus_six():
	assert_eq(BattleCalculator._stage_multiplier(-6), 0.25)

func test_stage_clamp_above_six():
	assert_eq(BattleCalculator._stage_multiplier(10), BattleCalculator._stage_multiplier(6))

func test_stage_clamp_below_minus_six():
	assert_eq(BattleCalculator._stage_multiplier(-10), BattleCalculator._stage_multiplier(-6))

# --- _accuracy_stage_multiplier ---

func test_accuracy_stage_zero():
	assert_eq(BattleCalculator._accuracy_stage_multiplier(0), 1.0)

func test_accuracy_stage_plus_one():
	assert_almost_eq(BattleCalculator._accuracy_stage_multiplier(1), 4.0 / 3.0, 0.001)

func test_accuracy_stage_minus_one():
	assert_almost_eq(BattleCalculator._accuracy_stage_multiplier(-1), 3.0 / 4.0, 0.001)

func test_accuracy_stage_plus_six():
	assert_eq(BattleCalculator._accuracy_stage_multiplier(6), 3.0)

func test_accuracy_stage_minus_six():
	assert_almost_eq(BattleCalculator._accuracy_stage_multiplier(-6), 3.0 / 9.0, 0.001)

# --- apply_status_damage ---

func test_burn_damage():
	var creature = {"max_hp": 80, "hp": 80}
	var dmg = BattleCalculator.apply_status_damage(creature, "burned")
	assert_eq(dmg, 10) # 80/8

func test_poison_damage():
	var creature = {"max_hp": 80, "hp": 80}
	var dmg = BattleCalculator.apply_status_damage(creature, "poisoned")
	assert_eq(dmg, 10)

func test_burn_damage_min_one():
	var creature = {"max_hp": 4, "hp": 4}
	var dmg = BattleCalculator.apply_status_damage(creature, "burned")
	assert_eq(dmg, 1) # 4/8 = 0 -> max(1, 0) = 1

func test_no_damage_for_unknown_status():
	var creature = {"max_hp": 80}
	assert_eq(BattleCalculator.apply_status_damage(creature, "drowsy"), 0)

func test_no_damage_for_empty_status():
	var creature = {"max_hp": 80}
	assert_eq(BattleCalculator.apply_status_damage(creature, ""), 0)

# --- get_effectiveness_text ---

func test_effectiveness_text_immune():
	assert_eq(BattleCalculator.get_effectiveness_text(0.0), "immune")

func test_effectiveness_text_super_effective():
	assert_eq(BattleCalculator.get_effectiveness_text(2.0), "super_effective")

func test_effectiveness_text_double_super():
	assert_eq(BattleCalculator.get_effectiveness_text(4.0), "super_effective")

func test_effectiveness_text_not_very():
	assert_eq(BattleCalculator.get_effectiveness_text(0.5), "not_very_effective")

func test_effectiveness_text_quarter():
	assert_eq(BattleCalculator.get_effectiveness_text(0.25), "not_very_effective")

func test_effectiveness_text_neutral():
	assert_eq(BattleCalculator.get_effectiveness_text(1.0), "neutral")

# --- apply_stat_changes ---

func test_apply_single_stat_change():
	var creature = {"attack_stage": 0}
	var result = BattleCalculator.apply_stat_changes(creature, {"attack": 1})
	assert_eq(creature["attack_stage"], 1)
	assert_eq(result["attack"], 1)

func test_apply_multiple_stat_changes():
	var creature = {"attack_stage": 0, "speed_stage": 0}
	BattleCalculator.apply_stat_changes(creature, {"attack": 2, "speed": -1})
	assert_eq(creature["attack_stage"], 2)
	assert_eq(creature["speed_stage"], -1)

func test_stat_change_clamp_at_plus_six():
	var creature = {"attack_stage": 5}
	BattleCalculator.apply_stat_changes(creature, {"attack": 3})
	assert_eq(creature["attack_stage"], 6)

func test_stat_change_clamp_at_minus_six():
	var creature = {"defense_stage": -5}
	BattleCalculator.apply_stat_changes(creature, {"defense": -3})
	assert_eq(creature["defense_stage"], -6)

func test_stat_change_cumulative():
	var creature = {"attack_stage": 0}
	BattleCalculator.apply_stat_changes(creature, {"attack": 2})
	BattleCalculator.apply_stat_changes(creature, {"attack": 2})
	assert_eq(creature["attack_stage"], 4)

# --- chilled speed ---

func test_chilled_speed_returns_one():
	var creature = {"status": "chilled", "speed": 100, "speed_stage": 0}
	assert_eq(BattleCalculator.get_speed(creature), 1)

func test_chilled_speed_ignores_stages():
	var creature = {"status": "chilled", "speed": 50, "speed_stage": 6}
	assert_eq(BattleCalculator.get_speed(creature), 1)

func test_normal_speed_not_affected_by_chilled_check():
	var creature = {"status": "", "speed": 50, "speed_stage": 0}
	assert_eq(BattleCalculator.get_speed(creature), 50)

# --- check_confusion (fermented) ---

func test_confusion_no_effect_without_fermented():
	var creature = {"status": "", "hp": 80, "max_hp": 80}
	var result = BattleCalculator.check_confusion(creature)
	assert_false(result.confused)
	assert_eq(result.damage, 0)
	assert_eq(creature["hp"], 80)

func test_confusion_no_effect_with_other_status():
	var creature = {"status": "burned", "hp": 80, "max_hp": 80}
	var result = BattleCalculator.check_confusion(creature)
	assert_false(result.confused)
	assert_eq(result.damage, 0)

func test_confusion_deals_self_damage():
	# Seed RNG so randf() < 0.33 (confusion triggers)
	seed(1) # Find a seed that triggers confusion
	var triggered = false
	for s in range(100):
		seed(s)
		if randf() < 0.33:
			seed(s) # Reset to same seed
			var creature = {"status": "fermented", "hp": 80, "max_hp": 80}
			var result = BattleCalculator.check_confusion(creature)
			assert_true(result.confused)
			assert_eq(result.damage, 10) # 80/8
			assert_eq(creature["hp"], 70)
			triggered = true
			break
	assert_true(triggered, "Should find a seed that triggers confusion")

func test_confusion_sometimes_allows_action():
	# Find a seed where randf() >= 0.33 (confusion doesn't trigger)
	var passed = false
	for s in range(100):
		seed(s)
		if randf() >= 0.33:
			seed(s)
			var creature = {"status": "fermented", "hp": 80, "max_hp": 80}
			var result = BattleCalculator.check_confusion(creature)
			assert_false(result.confused)
			assert_eq(result.damage, 0)
			assert_eq(creature["hp"], 80)
			passed = true
			break
	assert_true(passed, "Should find a seed where confusion doesn't trigger")
