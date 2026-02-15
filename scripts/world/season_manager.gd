extends Node

signal season_changed(new_season: String)
signal day_changed()
signal weather_changed(new_weather: String)

enum Season { SPRING, SUMMER, AUTUMN, WINTER }
enum Weather { SUNNY, RAINY, STORMY, WINDY }

const SEASON_NAMES = ["spring", "summer", "autumn", "winter"]
const WEATHER_NAMES = ["sunny", "rainy", "stormy", "windy"]

const DAY_DURATION = 600.0 # 10 real minutes per day
const DAYS_PER_SEASON = 14
const SEASONS_PER_YEAR = 4

# Weighted weather table: sunny 50, rainy 25, stormy 10, windy 15
const WEATHER_WEIGHTS = [50, 25, 10, 15]

var current_year: int = 1
var current_season: Season = Season.SPRING
var day_in_season: int = 1 # 1–14
var day_timer: float = 0.0
var total_day_count: int = 1 # absolute day counter

var current_weather: Weather = Weather.SUNNY

# Season ground tint colors
const SEASON_COLORS = {
	"spring": Color(0.35, 0.6, 0.3, 1),
	"summer": Color(0.3, 0.7, 0.25, 1),
	"autumn": Color(0.6, 0.45, 0.2, 1),
	"winter": Color(0.8, 0.85, 0.9, 1)
}

func _ready() -> void:
	if not multiplayer.is_server():
		return

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	day_timer += delta
	if day_timer >= DAY_DURATION:
		day_timer -= DAY_DURATION
		_advance_day()

func _advance_day() -> void:
	day_in_season += 1
	total_day_count += 1

	if day_in_season > DAYS_PER_SEASON:
		day_in_season = 1
		current_season = ((current_season as int + 1) % SEASONS_PER_YEAR) as Season
		if current_season == Season.SPRING:
			current_year += 1
		season_changed.emit(get_season_name())

	# Roll weather
	current_weather = _roll_weather()

	# Rain auto-waters farm plots
	if current_weather == Weather.RAINY or current_weather == Weather.STORMY:
		_rain_water_all_farms()

	print("Day ", total_day_count, " — Year ", current_year, " ", get_season_name().capitalize(), " Day ", day_in_season, " — ", get_weather_name().capitalize())
	_broadcast_time.rpc(current_year, current_season, day_in_season, total_day_count, current_weather)
	day_changed.emit()
	weather_changed.emit(get_weather_name())

func _roll_weather() -> Weather:
	var total_weight = 0
	for w in WEATHER_WEIGHTS:
		total_weight += w
	var roll = randi() % total_weight
	var cumulative = 0
	for i in range(WEATHER_WEIGHTS.size()):
		cumulative += WEATHER_WEIGHTS[i]
		if roll < cumulative:
			return i as Weather
	return Weather.SUNNY

func _rain_water_all_farms() -> void:
	# Water all farm plots in all FarmManagers
	for fm in get_tree().get_nodes_in_group("farm_manager"):
		if fm.has_method("rain_water_all"):
			fm.rain_water_all()
		else:
			# Fallback: water each plot individually
			for plot in fm.plots:
				if plot.has_method("rain_water"):
					plot.rain_water()

@rpc("authority", "call_local", "reliable")
func _broadcast_time(year: int, season: int, day: int, total_days: int, weather: int) -> void:
	current_year = year
	current_season = season as Season
	day_in_season = day
	total_day_count = total_days
	current_weather = weather as Weather
	season_changed.emit(get_season_name())
	day_changed.emit()
	weather_changed.emit(get_weather_name())

func get_season_name() -> String:
	return SEASON_NAMES[current_season]

func get_weather_name() -> String:
	return WEATHER_NAMES[current_weather]

func get_season_color() -> Color:
	return SEASON_COLORS[get_season_name()]

func is_crop_in_season(crop_season: String) -> bool:
	if crop_season == "":
		return true
	var current = get_season_name()
	var seasons = crop_season.split("/")
	return current in seasons

func is_raining() -> bool:
	return current_weather == Weather.RAINY or current_weather == Weather.STORMY

@rpc("any_peer", "reliable")
func request_season_sync() -> void:
	var sender = multiplayer.get_remote_sender_id()
	_broadcast_time.rpc_id(sender, current_year, current_season, day_in_season, total_day_count, current_weather)

func get_save_data() -> Dictionary:
	return {
		"current_season": current_season,
		"season_timer": 0.0, # kept for backward compat
		"day_count": total_day_count, # kept for backward compat
		"current_year": current_year,
		"day_in_season": day_in_season,
		"day_timer": day_timer,
		"total_day_count": total_day_count,
		"current_weather": current_weather,
	}

func load_save_data(data: Dictionary) -> void:
	current_season = data.get("current_season", 0) as Season
	# New fields (with backward-compat fallbacks)
	current_year = data.get("current_year", 1)
	day_in_season = data.get("day_in_season", 1)
	day_timer = data.get("day_timer", data.get("season_timer", 0.0))
	total_day_count = data.get("total_day_count", data.get("day_count", 1))
	current_weather = data.get("current_weather", 0) as Weather
	season_changed.emit(get_season_name())
	day_changed.emit()
	weather_changed.emit(get_weather_name())
