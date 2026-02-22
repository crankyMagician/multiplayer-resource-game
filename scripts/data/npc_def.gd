class_name NPCDef
extends Resource

@export var npc_id: String = ""
@export var display_name: String = ""
@export var visual_color: Color = Color(0.7, 0.5, 0.8)
@export var birthday: Dictionary = {} # {month: 3, day: 5}

# Schedule: array of {time_start: float, time_end: float, position: {x,y,z}, seasons: []}
# time_start/time_end are 0.0-1.0 fraction of day; seasons=[] means all seasons
@export var schedule: Array = []

# Gift preferences (arrays of item_ids)
@export var gift_preferences: Dictionary = {
	"loved": [], "liked": [], "disliked": [], "hated": []
}

# Branching dialogue trees, keyed by friendship tier
# Each entry is an array of dialogue nodes:
# {text: String, choices: [{label, points, response}]}
@export var dialogues: Dictionary = {
	"neutral": [], "like": [], "love": [],
	"dislike": [], "hate": [], "birthday": []
}

# NPC gifts at friendship thresholds: [{threshold: int, item_id: String, quantity: int, message: String}]
# OR creature gifts: [{threshold: int, creature_species_id: String, creature_level: int, creature_nickname: String, message: String}]
@export var npc_gifts: Array = []

# Creature trades: NPCs offer creatures to players for items/money, gated by conditions
# [{creature_species_id, creature_level, creature_nickname, cost_items: {item_id: qty}, cost_money: int,
#   required_friendship: String, required_season: String, required_quest_id: String,
#   dialogue_text: String, dialogue_accept_label: String, dialogue_decline_label: String, one_time: bool}]
@export var creature_trades: Array = []

@export var occupation: String = ""

# Character appearance for modular AR Kit model (optional — falls back to color-tinted mannequin)
@export var appearance: CharacterAppearance = null
