class_name QuestDef
extends Resource

@export var quest_id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var category: String = "side" # "side", "daily", "weekly", "main_story"
@export var quest_giver_npc_id: String = "" # NPC who offers/completes

# Prerequisites (all must be met)
@export var prereq_quest_ids: Array = []
@export var prereq_friendship: Dictionary = {} # {npc_id: min_points}
@export var prereq_locations: Array = []
@export var prereq_season: String = "" # "" = any
@export var prereq_weather: String = "" # "" = any
@export var prereq_main_story_quest_id: String = ""

# Objectives: [{type, target_id, target_count, description, deliver_to_npc, consumes_items}]
# Types: "collect", "defeat_trainer", "defeat_creature", "defeat_pvp",
#        "deliver", "craft", "talk_to", "discover_location"
@export var objectives: Array = []

# Rewards
@export var reward_money: int = 0
@export var reward_items: Dictionary = {} # item_id -> count
@export var reward_friendship: Dictionary = {} # npc_id -> points
@export var reward_recipe_scroll_id: String = ""
@export var reward_unlock_flag: String = ""

# Chain/story
@export var next_quest_id: String = ""
@export var chapter: int = 0 # main story grouping (0 = not main story)
@export var sort_order: int = 0

# NPC dialogue for quest flow
@export var offer_dialogue: String = ""
@export var in_progress_dialogue: String = ""
@export var completion_dialogue: String = ""
