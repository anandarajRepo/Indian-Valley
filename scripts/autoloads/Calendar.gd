extends Node
## Calendar.gd — Autoload for the valley's yearly events.
##
## Loads data/festivals.json and answers "what's happening on this date?":
##   - one festival per season, held in the town square
##   - villager birthdays (read from Relationships)
## Also remembers which festivals the player has already taken part in.
##
## Usage:
##   Calendar.festival_today()           # → Dictionary ({} when none)
##   Calendar.events_for_season(season)  # → Array of { day, kind, name, id }

const FESTIVALS_PATH: String = "res://data/festivals.json"

var _festivals: Array = []

## Festivals the player already entered, keyed "<year>:<festival_id>".
var festivals_done: Dictionary = {}


func _ready() -> void:
	var text := FileAccess.get_file_as_string(FESTIVALS_PATH)
	var parsed = JSON.parse_string(text) if not text.is_empty() else null
	if parsed == null or not parsed.has("festivals"):
		push_error("Calendar: could not load %s" % FESTIVALS_PATH)
		return
	_festivals = parsed["festivals"]
	print("[Calendar] Loaded %d festivals." % _festivals.size())

# ---------------------------------------------------------------------------
# Festivals
# ---------------------------------------------------------------------------

func get_all_festivals() -> Array:
	return _festivals


func festival_on(season: int, day: int) -> Dictionary:
	var key := GameClock.season_key(season)
	for f in _festivals:
		if f.get("season", "") == key and int(f.get("day", 0)) == day:
			return f
	return {}


func festival_today() -> Dictionary:
	return festival_on(GameClock.current_season, GameClock.current_day)


func is_festival_today() -> bool:
	return not festival_today().is_empty()


func has_entered_festival(festival_id: String, year: int = -1) -> bool:
	if year == -1:
		year = GameClock.current_year
	return festivals_done.has("%d:%s" % [year, festival_id])


func mark_festival_entered(festival_id: String) -> void:
	festivals_done["%d:%s" % [GameClock.current_year, festival_id]] = true

# ---------------------------------------------------------------------------
# Season overview (festivals + birthdays) for the journal calendar
# ---------------------------------------------------------------------------

func events_for_season(season: int) -> Array:
	## Sorted by day: [{ "day": int, "kind": "festival"|"birthday", "name": String, "id": String }]
	var events: Array = []
	var key := GameClock.season_key(season)
	for f in _festivals:
		if f.get("season", "") == key:
			events.append({"day": int(f["day"]), "kind": "festival", "name": f["name"], "id": f["id"]})
	for npc in Relationships.get_all_npcs():
		var bday: Dictionary = npc.get("birthday", {})
		if bday.get("season", "") == key:
			events.append({"day": int(bday["day"]), "kind": "birthday",
				"name": "%s's birthday" % npc["name"], "id": npc["id"]})
	events.sort_custom(func(a, b): return a["day"] < b["day"])
	return events


func events_on(season: int, day: int) -> Array:
	return events_for_season(season).filter(func(e): return e["day"] == day)

# ---------------------------------------------------------------------------
# Lifecycle / serialisation
# ---------------------------------------------------------------------------

func reset_to_new_game() -> void:
	festivals_done = {}


func to_dict() -> Dictionary:
	return {"festivals_done": festivals_done}


func from_dict(d: Dictionary) -> void:
	festivals_done = d.get("festivals_done", {})
