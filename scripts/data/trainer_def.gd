class_name TrainerDef
extends Resource

@export var trainer_id: String = ""
@export var display_name: String = ""
@export var dialogue_before: String = ""
@export var dialogue_after: String = ""
@export var party: Array[Dictionary] = [] # [{species_id, level}]
@export var ai_difficulty: String = "easy" # easy, medium, hard
@export var rematch_cooldown_sec: int = 300
@export var reward_money: int = 100
@export var reward_ingredients: Dictionary = {} # {ingredient_id: amount}
@export var reward_recipe_scroll_id: String = "" # one-time recipe scroll on first defeat
