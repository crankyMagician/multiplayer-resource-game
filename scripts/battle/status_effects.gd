class_name StatusEffects
extends RefCounted

# Status effect definitions
# burned (Seared): -1/8 HP per turn, -50% Attack
# frozen (Brain Freeze): can't act, 25% thaw per turn
# poisoned (Food Poisoning): -1/8 HP per turn, escalating
# drowsy (Food Coma): 50% skip turn
# wilted: -50% Sp.Attack, -25% Speed for 3 turns
# soured: -50% Defense for 3 turns
# brined: -50% Speed, 25% skip turn for 4 turns
# fermented (Tipsy): 33% self-hit for 1/8 max HP, 3 turns
# stuffed (Stuffed): blocks all healing, 3 turns
# spiced (Spiced Up): +25% damage dealt AND received, 3 turns
# chilled (Chilled): always moves last, 4 turns

static func apply_end_of_turn(creature: Dictionary) -> Dictionary:
	var result = {"damage": 0, "message": "", "cured": false}
	var status = creature.get("status", "")
	if status == "":
		return result

	var turns = creature.get("status_turns", 0)
	turns += 1
	creature["status_turns"] = turns

	match status:
		"burned":
			var dmg = max(1, creature.get("max_hp", 40) / 8)
			creature["hp"] = max(0, creature.get("hp", 0) - dmg)
			result.damage = dmg
			result.message = "is hurt by its burn!"
			if turns >= 5:
				creature["status"] = ""
				creature["status_turns"] = 0
				result.cured = true
		"poisoned":
			# Escalating: 1/8, 2/8, 3/8...
			var fraction = min(turns, 4)
			var dmg = max(1, creature.get("max_hp", 40) * fraction / 8)
			creature["hp"] = max(0, creature.get("hp", 0) - dmg)
			result.damage = dmg
			result.message = "is hurt by food poisoning!"
		"frozen":
			result.message = "is frozen solid!"
			if turns >= 5:
				creature["status"] = ""
				creature["status_turns"] = 0
				result.cured = true
				result.message = "thawed out!"
		"drowsy":
			result.message = "is in a food coma..."
			if turns >= 4:
				creature["status"] = ""
				creature["status_turns"] = 0
				result.cured = true
				result.message = "woke up!"
		"wilted":
			result.message = "is wilted..."
			if turns >= 3:
				creature["status"] = ""
				creature["status_turns"] = 0
				result.cured = true
				result.message = "recovered from wilting!"
		"soured":
			result.message = "is feeling sour..."
			if turns >= 3:
				creature["status"] = ""
				creature["status_turns"] = 0
				result.cured = true
				result.message = "recovered from sourness!"
		"brined":
			result.message = "is stiff from brine!"
			if turns >= 4:
				creature["status"] = ""
				creature["status_turns"] = 0
				result.cured = true
				result.message = "shook off the brine!"
		"fermented":
			result.message = "is tipsy and confused..."
			if turns >= 3:
				creature["status"] = ""
				creature["status_turns"] = 0
				result.cured = true
				result.message = "sobered up!"
		"stuffed":
			result.message = "is too stuffed to eat..."
			if turns >= 3:
				creature["status"] = ""
				creature["status_turns"] = 0
				result.cured = true
				result.message = "digested its meal!"
		"spiced":
			result.message = "is burning with spice!"
			if turns >= 3:
				creature["status"] = ""
				creature["status_turns"] = 0
				result.cured = true
				result.message = "cooled down!"
		"chilled":
			result.message = "is chilled and sluggish..."
			if turns >= 4:
				creature["status"] = ""
				creature["status_turns"] = 0
				result.cured = true
				result.message = "warmed back up!"
	return result

static func get_stat_modifier(creature: Dictionary, stat: String) -> float:
	var status = creature.get("status", "")
	match status:
		"burned":
			if stat == "attack":
				return 0.5
		"wilted":
			if stat == "sp_attack":
				return 0.5
			if stat == "speed":
				return 0.75
		"soured":
			if stat == "defense":
				return 0.5
		"brined":
			if stat == "speed":
				return 0.5
	return 1.0

static func try_apply_status(creature: Dictionary, status: String, chance: int) -> bool:
	if creature.get("status", "") != "":
		return false # Already has a status
	if status == "":
		return false
	if randi() % 100 >= chance:
		return false
	creature["status"] = status
	creature["status_turns"] = 0
	return true

static func get_status_display_name(status: String) -> String:
	match status:
		"burned": return "Seared"
		"frozen": return "Brain Freeze"
		"poisoned": return "Food Poisoning"
		"drowsy": return "Food Coma"
		"wilted": return "Wilted"
		"soured": return "Soured"
		"brined": return "Brined"
		"fermented": return "Tipsy"
		"stuffed": return "Stuffed"
		"spiced": return "Spiced Up"
		"chilled": return "Chilled"
		_: return ""

static func is_heal_blocked(creature: Dictionary) -> bool:
	return creature.get("status", "") == "stuffed"

static func get_damage_multiplier(creature: Dictionary) -> float:
	if creature.get("status", "") == "spiced":
		return 1.25
	return 1.0
