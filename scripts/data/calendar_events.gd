class_name CalendarEvents
extends RefCounted

const HOLIDAYS: Array = [
	{"month": 1, "day": 1, "name": "New Year's Festival", "description": "Ring in the new year!", "type": "festival"},
	{"month": 2, "day": 14, "name": "Hearts Day", "description": "A day to celebrate love and friendship.", "type": "holiday"},
	{"month": 3, "day": 1, "name": "Spring Blossom Festival", "description": "Celebrate the arrival of spring.", "type": "festival"},
	{"month": 4, "day": 20, "name": "Egg Hunt", "description": "Hidden eggs appear throughout the world.", "type": "festival"},
	{"month": 6, "day": 21, "name": "Summer Solstice", "description": "The longest day of the year.", "type": "holiday"},
	{"month": 7, "day": 15, "name": "Fireworks Festival", "description": "A night of spectacular fireworks.", "type": "festival"},
	{"month": 9, "day": 22, "name": "Harvest Moon", "description": "Celebrate the autumn harvest.", "type": "festival"},
	{"month": 10, "day": 28, "name": "Spooky Night", "description": "Creatures roam in costumes.", "type": "festival"},
	{"month": 11, "day": 14, "name": "Feast of Thanks", "description": "A day of gratitude and feasting.", "type": "holiday"},
	{"month": 12, "day": 25, "name": "Wintermas", "description": "Exchange gifts and enjoy the frost.", "type": "festival"},
]

static func get_events_for_month(month: int) -> Array:
	var events: Array = []
	for h in HOLIDAYS:
		if int(h["month"]) == month:
			events.append(h)
	# Add NPC birthdays
	DataRegistry.ensure_loaded()
	for npc_id in DataRegistry.npcs:
		var npc = DataRegistry.npcs[npc_id]
		var bday: Dictionary = npc.birthday
		if bday.has("month") and int(bday["month"]) == month:
			events.append({
				"month": month,
				"day": int(bday["day"]),
				"name": npc.display_name + "'s Birthday",
				"description": "It's " + npc.display_name + "'s birthday!",
				"type": "birthday",
			})
	return events

static func get_events_for_day(month: int, day: int) -> Array:
	var events: Array = []
	for h in HOLIDAYS:
		if int(h["month"]) == month and int(h["day"]) == day:
			events.append(h)
	# Add NPC birthdays
	DataRegistry.ensure_loaded()
	for npc_id in DataRegistry.npcs:
		var npc = DataRegistry.npcs[npc_id]
		var bday: Dictionary = npc.birthday
		if bday.has("month") and int(bday["month"]) == month and int(bday["day"]) == day:
			events.append({
				"month": month,
				"day": day,
				"name": npc.display_name + "'s Birthday",
				"description": "It's " + npc.display_name + "'s birthday!",
				"type": "birthday",
			})
	return events
