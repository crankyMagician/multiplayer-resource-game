class_name FishingTable
extends Resource

@export var table_id: String = ""
@export var display_name: String = ""
@export var entries: Array = []
# Entry: {fish_id: String, weight: int, difficulty: int (1-5),
#         min_rod_tier: int, movement_type: String, season: String}
# movement_type: "smooth" | "dart" | "sinker" | "mixed"
# season: "" (all), "spring", "summer", "autumn", "winter"
@export var weather_bonus: Dictionary = {}  # {weather: fish_id}
