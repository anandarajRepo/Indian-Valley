extends Node
## GameClock.gd — Autoload singleton managing all in-game time.
##
## In-game time breakdown:
##   1 real second  = 1.4 in-game minutes   (so 1 in-game hour ≈ 43 real seconds)
##   1 in-game day  = ~14 real minutes       (6am → 2am next = 20 in-game hours)
##   1 season       = 28 in-game days
##   1 year         = 4 seasons = 112 days
##
## Day runs 6:00 am → 2:00 am (next day).  Passing 2:00 am triggers auto-sleep.
## Signals allow UI, world, and systems to react to time changes.

signal time_changed(hour: int, minute: int)
signal hour_changed(hour: int)
signal day_started(day: int, season: Season)
signal day_ended(day: int, season: Season)
signal season_changed(new_season: Season)
signal year_changed(year: int)
signal sleep_triggered()         ## Emitted at 2am or when player sleeps manually

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

enum Season {
	KHARIF  = 0,   ## Monsoon / Summer  (crop-rich, rain)
	RABI    = 1,   ## Post-monsoon / Autumn
	WINTER  = 2,   ## Bittersweet still; no field crops
	UGADI   = 3,   ## New Year / Spring (festivals, flowers)
}

const SEASON_NAMES: Dictionary = {
	Season.KHARIF:  "Kharif",
	Season.RABI:    "Rabi",
	Season.WINTER:  "Winter",
	Season.UGADI:   "Ugadi",
}

const DAYS_PER_SEASON: int = 28
const SEASONS_PER_YEAR: int = 4

## Day starts at this in-game hour (6 am)
const DAY_START_HOUR: int = 6
## Player must sleep before this hour or they pass out (2 am = hour 26 in 24h+)
const SLEEP_HOUR: int = 26  ## 2am next calendar day (we use 0–27 range for simplicity)

## Real-time seconds per in-game minute.
## 14 real mins/day ÷ (20 in-game hours × 60 min) = 0.7 seconds per in-game minute
## We use a slightly generous 0.714 so a full day = exactly 840 real seconds.
const SECONDS_PER_INGAME_MINUTE: float = 0.714

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var current_hour: int   = DAY_START_HOUR
var current_minute: int = 0
var current_day: int    = 1
var current_season: Season = Season.KHARIF
var current_year: int   = 1

## Absolute count of days that have fully elapsed since a new game began.
## Day 1 == 0 elapsed. Used by farming systems to track crop growth without
## worrying about season/year wrap-around.
var days_elapsed: int   = 0

var _elapsed: float = 0.0
var _paused:  bool  = false

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if _paused:
		return

	_elapsed += delta
	if _elapsed >= SECONDS_PER_INGAME_MINUTE:
		_elapsed -= SECONDS_PER_INGAME_MINUTE
		_advance_minute()

# ---------------------------------------------------------------------------
# Internal time advancement
# ---------------------------------------------------------------------------

func _advance_minute() -> void:
	current_minute += 1
	if current_minute >= 60:
		current_minute = 0
		_advance_hour()
	emit_signal("time_changed", current_hour, current_minute)


func _advance_hour() -> void:
	current_hour += 1
	emit_signal("hour_changed", current_hour)

	# Check for 2am auto-sleep
	if current_hour >= SLEEP_HOUR:
		_trigger_sleep()


func _trigger_sleep() -> void:
	if _paused:
		return   ## Already sleeping / mid-transition — ignore duplicate triggers.
	pause()
	emit_signal("sleep_triggered")
	# GameData / Player will call end_day() after handling the sleep sequence


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func end_day() -> void:
	## Called by the sleep system after all overnight processing is done.
	emit_signal("day_ended", current_day, current_season)
	_advance_day()
	emit_signal("day_started", current_day, current_season)
	resume()


func _advance_day() -> void:
	current_day += 1
	days_elapsed += 1
	if current_day > DAYS_PER_SEASON:
		current_day = 1
		_advance_season()

	# Reset time to morning
	current_hour   = DAY_START_HOUR
	current_minute = 0
	_elapsed       = 0.0


func _advance_season() -> void:
	var next_season_index = (int(current_season) + 1) % SEASONS_PER_YEAR
	current_season = next_season_index as Season
	emit_signal("season_changed", current_season)

	if current_season == Season.KHARIF:
		current_year += 1
		emit_signal("year_changed", current_year)


func pause() -> void:
	## Pause the clock (e.g. during dialogue, menus, cutscenes).
	_paused = true


func resume() -> void:
	_paused = false


func is_paused() -> bool:
	return _paused


## Returns the in-game time as a display string, e.g. "6:30 AM"
func get_time_string() -> String:
	var display_hour = current_hour % 24
	var suffix = "AM" if display_hour < 12 else "PM"
	var h = display_hour % 12
	if h == 0:
		h = 12
	var m = str(current_minute).pad_zeros(2)
	return "%d:%s %s" % [h, m, suffix]


## Returns the season display name
func get_season_name() -> String:
	return SEASON_NAMES.get(current_season, "Unknown")


## Returns the full date string, e.g. "Day 3, Kharif — Year 1"
func get_date_string() -> String:
	return "Day %d, %s — Year %d" % [current_day, get_season_name(), current_year]


## Serialise clock state into a dictionary for saving
func to_dict() -> Dictionary:
	return {
		"hour":    current_hour,
		"minute":  current_minute,
		"day":     current_day,
		"season":  int(current_season),
		"year":    current_year,
		"days_elapsed": days_elapsed,
	}


## Restore clock state from a saved dictionary
func from_dict(d: Dictionary) -> void:
	current_hour   = d.get("hour",   DAY_START_HOUR)
	current_minute = d.get("minute", 0)
	current_day    = d.get("day",    1)
	current_season = d.get("season", 0) as Season
	current_year   = d.get("year",   1)
	days_elapsed   = d.get("days_elapsed", 0)
	_elapsed       = 0.0
