class_name BattleCalculator
extends RefCounted

# Type effectiveness chart
# super effective = 2.0, not very effective = 0.5, neutral = 1.0
const TYPE_CHART: Dictionary = {
	# Original 6 types (unchanged)
	"spicy": {"sweet": 2.0, "herbal": 2.0, "sour": 0.5, "umami": 0.5, "liquid": 0.5, "dairy": 2.0, "smoked": 0.5},
	"sweet": {"sour": 2.0, "umami": 2.0, "spicy": 0.5, "grain": 0.5, "bitter": 2.0, "spoiled": 0.5},
	"sour": {"spicy": 2.0, "grain": 0.0, "sweet": 0.5, "herbal": 0.5, "mineral": 2.0, "dairy": 2.0},
	"herbal": {"sour": 2.0, "sweet": 2.0, "spicy": 0.5, "umami": 0.0, "earthy": 2.0, "aromatic": 0.5, "toxic": 0.5},
	"umami": {"herbal": 2.0, "spicy": 2.0, "sweet": 0.5, "grain": 0.5, "aromatic": 2.0},
	"grain": {"sweet": 2.0, "umami": 2.0, "sour": 0.5, "herbal": 0.5, "mineral": 0.5, "protein": 2.0},
	# New 12 types
	"mineral": {"grain": 2.0, "toxic": 2.0, "smoked": 2.0, "sour": 0.5, "earthy": 0.5, "liquid": 0.5},
	"earthy": {"mineral": 2.0, "liquid": 2.0, "fermented": 2.0, "herbal": 0.5, "toxic": 0.5, "tropical": 0.5},
	"liquid": {"spicy": 2.0, "mineral": 2.0, "smoked": 2.0, "herbal": 0.5, "earthy": 0.5, "tropical": 0.5},
	"aromatic": {"herbal": 2.0, "toxic": 2.0, "tropical": 2.0, "umami": 0.5, "protein": 0.5, "bitter": 0.5},
	"toxic": {"herbal": 2.0, "earthy": 2.0, "protein": 2.0, "dairy": 2.0, "mineral": 0.5, "spoiled": 0.5},
	"protein": {"aromatic": 2.0, "bitter": 2.0, "spoiled": 2.0, "grain": 0.5, "toxic": 0.5, "smoked": 0.5},
	"tropical": {"earthy": 2.0, "liquid": 2.0, "dairy": 2.0, "aromatic": 0.5, "fermented": 0.5},
	"dairy": {"bitter": 2.0, "spoiled": 2.0, "fermented": 2.0, "spicy": 0.5, "sour": 0.5, "toxic": 0.5, "tropical": 0.5},
	"bitter": {"aromatic": 2.0, "spoiled": 2.0, "fermented": 2.0, "sweet": 0.5, "protein": 0.5, "dairy": 0.5},
	"spoiled": {"sweet": 2.0, "toxic": 2.0, "fermented": 2.0, "smoked": 2.0, "aromatic": 0.5, "protein": 0.5, "dairy": 0.5},
	"fermented": {"protein": 2.0, "tropical": 2.0, "smoked": 2.0, "earthy": 0.5, "dairy": 0.5, "bitter": 0.5, "spoiled": 0.5},
	"smoked": {"spicy": 2.0, "protein": 2.0, "mineral": 0.5, "liquid": 0.5, "spoiled": 0.5, "fermented": 0.5},
}

# Crit stage thresholds: stage -> denominator (1/N chance)
const CRIT_THRESHOLDS: Array = [16, 8, 4, 2]

static func get_type_effectiveness(attack_type: String, defender_types: Array) -> float:
	if attack_type == "":
		return 1.0
	var multiplier = 1.0
	var chart = TYPE_CHART.get(attack_type, {})
	for def_type in defender_types:
		multiplier *= chart.get(def_type, 1.0)
	return multiplier

static func calculate_damage(attacker: Dictionary, defender: Dictionary, move, level: int, weather: String = "") -> Dictionary:
	if move.category == "status":
		return {"damage": 0, "effectiveness": 1.0, "critical": false}

	# Get attacking and defending stats
	var atk: float
	var def_stat: float
	if move.category == "physical":
		atk = float(attacker.get("attack", 10))
		def_stat = float(defender.get("defense", 10))
	else: # special
		atk = float(attacker.get("sp_attack", 10))
		def_stat = float(defender.get("sp_defense", 10))

	# Apply stat stages
	atk *= _stage_multiplier(attacker.get("attack_stage", 0) if move.category == "physical" else attacker.get("sp_attack_stage", 0))
	def_stat *= _stage_multiplier(defender.get("defense_stage", 0) if move.category == "physical" else defender.get("sp_defense_stage", 0))

	# Base damage formula (Pokemon-style)
	var base = ((2.0 * level / 5.0 + 2.0) * move.power * atk / def_stat) / 50.0 + 2.0

	# Type effectiveness
	var defender_types = defender.get("types", [])
	if defender_types is PackedStringArray:
		defender_types = Array(defender_types)
	var effectiveness = get_type_effectiveness(move.type, defender_types)
	base *= effectiveness

	# Weather modifier
	var weather_mod = FieldEffects.get_weather_modifier(weather, move.type)
	base *= weather_mod

	# Random factor (0.85 - 1.0)
	var random_factor = randf_range(0.85, 1.0)
	base *= random_factor

	# Critical hit (staged system)
	var critical = check_critical(attacker, move)
	if critical:
		base *= 1.5

	# Bond stat modifiers (dynamic nature from affinities)
	var bond_boost = attacker.get("bond_boost_stat", "")
	var bond_nerf = attacker.get("bond_nerf_stat", "")
	if bond_boost != "" or bond_nerf != "":
		var atk_stat_name = "attack" if move.category == "physical" else "sp_attack"
		if bond_boost == atk_stat_name:
			base *= 1.1
		elif bond_nerf == atk_stat_name:
			base *= 0.9
		var def_stat_name = "defense" if move.category == "physical" else "sp_defense"
		if bond_boost == def_stat_name:
			# Defender's boost — attacker takes less? No — this is attacker's bond.
			pass
		if bond_nerf == def_stat_name:
			pass

	# STAB (Same Type Attack Bonus)
	var attacker_types = attacker.get("types", [])
	if attacker_types is PackedStringArray:
		attacker_types = Array(attacker_types)
	if move.type in attacker_types:
		base *= 1.5

	var final_damage = max(1, int(base))
	return {"damage": final_damage, "effectiveness": effectiveness, "critical": critical}

static func _stage_multiplier(stage: int) -> float:
	stage = clampi(stage, -6, 6)
	if stage >= 0:
		return (2.0 + stage) / 2.0
	else:
		return 2.0 / (2.0 - stage)

static func check_accuracy(move, attacker: Dictionary, defender: Dictionary) -> bool:
	if move.accuracy <= 0 or move.accuracy >= 100:
		return true
	var acc = float(move.accuracy)
	# Apply accuracy/evasion stages
	var acc_stage = attacker.get("accuracy_stage", 0)
	var eva_stage = defender.get("evasion_stage", 0)
	var net_stage = clampi(acc_stage - eva_stage, -6, 6)
	acc *= _accuracy_stage_multiplier(net_stage)
	return randf() * 100.0 < acc

static func _accuracy_stage_multiplier(stage: int) -> float:
	# Accuracy/evasion uses 3/3, 3/4, 3/5... for negative and 3/3, 4/3, 5/3... for positive
	stage = clampi(stage, -6, 6)
	if stage >= 0:
		return (3.0 + stage) / 3.0
	else:
		return 3.0 / (3.0 - stage)

static func check_critical(attacker: Dictionary, move) -> bool:
	var stage = attacker.get("crit_stage", 0)
	# Move-specific crit boost
	if move and move.self_crit_stage_change > 0:
		stage += move.self_crit_stage_change
	# Held item crit boost (Precision Grater)
	var item_id = attacker.get("held_item_id", "")
	if item_id != "":
		var item = DataRegistry.get_held_item(item_id)
		if item and item.effect_type == "crit_boost":
			stage += 1
	# Bond level 1+ gives +1 crit stage
	if attacker.get("bond_level", 0) >= 1:
		stage += 1
	stage = clampi(stage, 0, 3)
	var threshold = CRIT_THRESHOLDS[stage]
	return randi() % threshold == 0

static func check_confusion(creature: Dictionary) -> Dictionary:
	if creature.get("status", "") != "fermented":
		return {"confused": false, "damage": 0}
	if randf() < 0.33:
		var dmg = max(1, creature.get("max_hp", 40) / 8)
		creature["hp"] = max(0, creature.get("hp", 0) - dmg)
		return {"confused": true, "damage": dmg}
	return {"confused": false, "damage": 0}

static func get_speed(creature: Dictionary) -> int:
	# Chilled: always moves last
	if creature.get("status", "") == "chilled":
		return 1
	var base_speed = creature.get("speed", 10)
	var stage = creature.get("speed_stage", 0)
	var spd = float(base_speed) * _stage_multiplier(stage)
	# Status speed modifier (brined = 0.5x, wilted = 0.75x)
	spd *= StatusEffects.get_stat_modifier(creature, "speed")
	# Bond boost/nerf on speed
	if creature.get("bond_boost_stat", "") == "speed":
		spd *= 1.1
	elif creature.get("bond_nerf_stat", "") == "speed":
		spd *= 0.9
	# Choice Whisk: +50% speed
	var item_id = creature.get("held_item_id", "")
	if item_id != "":
		var item = DataRegistry.get_held_item(item_id)
		if item and item.effect_type == "choice_lock" and item.effect_params.get("stat", "") == "speed":
			spd *= 1.5
	return int(spd)

static func apply_status_damage(creature: Dictionary, status: String) -> int:
	var max_hp = creature.get("max_hp", 40)
	match status:
		"burned", "poisoned":
			return max(1, max_hp / 8)
		_:
			return 0

static func can_act(creature: Dictionary) -> bool:
	var status = creature.get("status", "")
	match status:
		"frozen":
			# 25% chance to thaw each turn
			if randf() < 0.25:
				creature["status"] = ""
				creature["status_turns"] = 0
				return true
			return false
		"drowsy":
			# 50% chance to skip turn
			return randf() > 0.5
		"brined":
			# 25% chance to skip turn
			return randf() > 0.25
		_:
			return true

static func apply_stat_changes(creature: Dictionary, changes: Dictionary) -> Dictionary:
	var results = {}
	for stat in changes:
		var stage_key = stat + "_stage"
		var current = creature.get(stage_key, 0)
		var change = changes[stat]
		var new_val = clampi(current + change, -6, 6)
		creature[stage_key] = new_val
		results[stat] = change
	return results

static func get_effectiveness_text(effectiveness: float) -> String:
	if effectiveness == 0.0:
		return "immune"
	elif effectiveness >= 2.0:
		return "super_effective"
	elif effectiveness <= 0.5:
		return "not_very_effective"
	else:
		return "neutral"
