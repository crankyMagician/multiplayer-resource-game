extends Node

signal season_changed(new_season: String)
signal month_changed(new_month: String)
signal day_changed()
signal weather_changed(new_weather: String)

enum Weather { SUNNY, RAINY, STORMY, WINDY }

const WEATHER_NAMES = ["sunny", "rainy", "stormy", "windy"]

const DAY_DURATION = 600.0 # 10 real minutes per day
const MONTHS_PER_YEAR = 12
const DAYS_PER_MONTH = 28

const MONTH_NAMES = [
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December"
]

# Northern hemisphere: Dec/Jan/Feb=winter, Mar/Apr/May=spring, Jun/Jul/Aug=summer, Sep/Oct/Nov=autumn
const MONTH_TO_SEASON = {
	1: "winter", 2: "winter", 3: "spring", 4: "spring", 5: "spring", 6: "summer",
	7: "summer", 8: "summer", 9: "autumn", 10: "autumn", 11: "autumn", 12: "winter"
}

# Weighted weather table: sunny 50, rainy 25, stormy 10, windy 15
const WEATHER_WEIGHTS = [50, 25, 10, 15]

# Season ground tint colors
const SEASON_COLORS = {
	"spring": Color(0.35, 0.6, 0.3, 1),
	"summer": Color(0.3, 0.7, 0.25, 1),
	"autumn": Color(0.6, 0.45, 0.2, 1),
	"winter": Color(0.8, 0.85, 0.9, 1)
}

var current_year: int = 1
var current_month: int = 3 # 1-12, start in March (spring)
var day_in_month: int = 1 # 1-28
var day_timer: float = 0.0
var total_day_count: int = 1 # absolute day counter

var current_weather: Weather = Weather.SUNNY

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
	var old_season = get_current_season()
	day_in_month += 1
	total_day_count += 1

	if day_in_month > DAYS_PER_MONTH:
		day_in_month = 1
		current_month += 1
		if current_month > MONTHS_PER_YEAR:
			current_month = 1
			current_year += 1
		month_changed.emit(get_month_name())

	var new_season = get_current_season()
	if new_season != old_season:
		season_changed.emit(new_season)

	# Roll weather
	current_weather = _roll_weather()

	# Rain auto-waters farm plots
	if current_weather == Weather.RAINY or current_weather == Weather.STORMY:
		_rain_water_all_farms()

	# Track days_played for all online players
	for p_id in NetworkManager.player_data_store:
		StatTracker.increment(p_id, "days_played")
	print("Day ", total_day_count, " — Year ", current_year, " ", get_month_name(), " ", day_in_month, " — ", get_weather_name().capitalize())
	_broadcast_time.rpc(current_year, current_month, day_in_month, total_day_count, current_weather)
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
func _broadcast_time(year: int, month: int, day: int, total_days: int, weather: int) -> void:
	current_year = year
	current_month = month
	day_in_month = day
	total_day_count = total_days
	current_weather = weather as Weather
	season_changed.emit(get_current_season())
	day_changed.emit()
	weather_changed.emit(get_weather_name())

func get_current_season() -> String:
	return MONTH_TO_SEASON.get(current_month, "spring")

# Backward-compat alias
func get_season_name() -> String:
	return get_current_season()

func get_month_name() -> String:
	if current_month >= 1 and current_month <= 12:
		return MONTH_NAMES[current_month - 1]
	return "March"

func get_weather_name() -> String:
	return WEATHER_NAMES[current_weather]

func get_season_color() -> Color:
	return SEASON_COLORS[get_current_season()]

func is_crop_in_season(crop_season: String) -> bool:
	if crop_season == "":
		return true
	var current = get_current_season()
	var seasons = crop_season.split("/")
	return current in seasons

func is_raining() -> bool:
	return current_weather == Weather.RAINY or current_weather == Weather.STORMY

@rpc("any_peer", "reliable")
func request_season_sync() -> void:
	var sender = multiplayer.get_remote_sender_id()
	_broadcast_time.rpc_id(sender, current_year, current_month, day_in_month, total_day_count, current_weather)

func get_save_data() -> Dictionary:
	return {
		"current_month": current_month,
		"day_in_month": day_in_month,
		"current_year": current_year,
		"day_timer": day_timer,
		"total_day_count": total_day_count,
		"current_weather": current_weather,
		# Backward compat keys (for old loaders)
		"current_season": _season_to_old_enum(get_current_season()),
		"day_in_season": day_in_month,
		"season_timer": 0.0,
		"day_count": total_day_count,
	}

func load_save_data(data: Dictionary) -> void:
	if data.has("current_month"):
		# New format
		current_month = int(data.get("current_month", 3))
		day_in_month = int(data.get("day_in_month", 1))
	else:
		# Old format: convert season enum + day_in_season to month/day
		var old_season: int = int(data.get("current_season", 0))
		var old_day: int = int(data.get("day_in_season", 1))
		current_month = _old_season_to_month(old_season, old_day)
		day_in_month = _old_day_to_month_day(old_day)

	current_year = int(data.get("current_year", 1))
	day_timer = float(data.get("day_timer", data.get("season_timer", 0.0)))
	total_day_count = int(data.get("total_day_count", data.get("day_count", 1)))
	current_weather = int(data.get("current_weather", 0)) as Weather

	season_changed.emit(get_current_season())
	day_changed.emit()
	weather_changed.emit(get_weather_name())

# Old Season enum: 0=spring, 1=summer, 2=autumn, 3=winter
# Each old season had 14 days; new months have 28 days.
# spring(0) -> Mar/Apr/May, summer(1) -> Jun/Jul/Aug, autumn(2) -> Sep/Oct/Nov, winter(3) -> Dec/Jan/Feb
const _OLD_SEASON_FIRST_MONTH = [3, 6, 9, 12] # spring->Mar, summer->Jun, autumn->Sep, winter->Dec

func _old_season_to_month(old_season: int, old_day: int) -> int:
	# Old: 14 days per season. Map to 3 months (84 days total per "quarter").
	# Approximate: day 1-5 -> first month, 6-10 -> second, 11-14 -> third
	var base = _OLD_SEASON_FIRST_MONTH[clampi(old_season, 0, 3)]
	if old_day <= 5:
		return base
	elif old_day <= 10:
		return base + 1 if base < 12 else ((base + 1 - 1) % 12 + 1)
	else:
		var m = base + 2
		if m > 12:
			m = ((m - 1) % 12) + 1
		return m

func _old_day_to_month_day(old_day: int) -> int:
	# Spread old 14-day season across 28-day month: multiply by 2, clamp
	return clampi(((old_day - 1) % 5) * 5 + 1, 1, 28)

func _season_to_old_enum(season: String) -> int:
	match season:
		"spring": return 0
		"summer": return 1
		"autumn": return 2
		"winter": return 3
	return 0
