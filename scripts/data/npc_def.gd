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
@export var npc_gifts: Array = []

@export var occupation: String = ""
