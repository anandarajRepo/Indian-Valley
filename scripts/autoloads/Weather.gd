extends Node
## Weather.gd — Autoload for daily weather and the next-day forecast.
##
## Each morning "tomorrow" becomes "today" and a new forecast is rolled from
## the season's odds. Rain (and storms) water every tilled tile on the farm,
## so the Kharif monsoon does a lot of the work for you. Festival days and the
## very first morning of a new game are always sunny.

signal weather_changed(today: String)

const SUNNY:  String = "sunny"
const CLOUDY: String = "cloudy"
const RAIN:   String = "rain"
const STORM:  String = "storm"

const DISPLAY_NAMES: Dictionary = {
	SUNNY:  "Sunny",
	CLOUDY: "Cloudy",
	RAIN:   "Rain",
	STORM:  "Monsoon storm",
}

## Per-season odds, keyed by GameClock season key. Remaining probability = sunny.
const SEASON_ODDS: Dictionary = {
	"ugadi":  {"rain": 0.15, "storm": 0.02, "cloudy": 0.20},
	"kharif": {"rain": 0.45, "storm": 0.15, "cloudy": 0.20},
	"rabi":   {"rain": 0.15, "storm": 0.00, "cloudy": 0.25},
	"winter": {"rain": 0.05, "storm": 0.00, "cloudy": 0.35},
}

var today:    String = SUNNY
var tomorrow: String = SUNNY

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	GameClock.day_started.connect(_on_day_started)


func _on_day_started(_day: int, _season) -> void:
	today = tomorrow
	tomorrow = roll_for_date(GameClock.get_date_offset(1))
	emit_signal("weather_changed", today)

# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func is_raining() -> bool:
	return today == RAIN or today == STORM


func get_display_name(w: String = "") -> String:
	if w == "":
		w = today
	return DISPLAY_NAMES.get(w, "Sunny")


func roll_for_date(date: Dictionary) -> String:
	## Roll the weather for a given { day, season } date.
	var season: int = date.get("season", GameClock.current_season)
	if not Calendar.festival_on(season, int(date.get("day", 1))).is_empty():
		return SUNNY
	var odds: Dictionary = SEASON_ODDS.get(GameClock.season_key(season), {})
	var r := _rng.randf()
	var storm: float = odds.get("storm", 0.0)
	var rain: float  = odds.get("rain", 0.0)
	var cloudy: float = odds.get("cloudy", 0.0)
	if r < storm:
		return STORM
	if r < storm + rain:
		return RAIN
	if r < storm + rain + cloudy:
		return CLOUDY
	return SUNNY

# ---------------------------------------------------------------------------
# Lifecycle / serialisation
# ---------------------------------------------------------------------------

func reset_to_new_game() -> void:
	today = SUNNY
	tomorrow = roll_for_date(GameClock.get_date_offset(1))
	emit_signal("weather_changed", today)


func to_dict() -> Dictionary:
	return {"today": today, "tomorrow": tomorrow}


func from_dict(d: Dictionary) -> void:
	today = d.get("today", SUNNY)
	tomorrow = d.get("tomorrow", "")
	if tomorrow == "":
		tomorrow = roll_for_date(GameClock.get_date_offset(1))
	emit_signal("weather_changed", today)
