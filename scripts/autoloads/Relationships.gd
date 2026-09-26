extends Node
## Relationships.gd — Autoload for villager friendships.
##
## Loads data/npcs.json (names, birthdays, gift tastes, seasonal dialogue) and
## tracks friendship with each villager:
##   - 250 points per heart, 10 hearts max
##   - first chat of the day: +20
##   - one gift per villager per day: loved +80, liked +45, neutral +20,
##     disliked -20 — multiplied ×8 on their birthday
##
## NPC nodes in the world only carry an `npc_id`; everything else lives here.

signal friendship_changed(npc_id: String, points: int)

const NPCS_PATH: String = "res://data/npcs.json"

const POINTS_PER_HEART: int = 250
const MAX_HEARTS:       int = 10
const MAX_POINTS:       int = POINTS_PER_HEART * MAX_HEARTS

const TALK_POINTS:     int = 20
const GIFT_LOVED:      int = 80
const GIFT_LIKED:      int = 45
const GIFT_NEUTRAL:    int = 20
const GIFT_DISLIKED:   int = -20
const BIRTHDAY_MULT:   int = 8

## Item categories a villager will accept as a gift.
const GIFTABLE_CATEGORIES: Array = ["crop", "forage", "fish", "food", "mineral"]

var _npcs: Dictionary = {}      ## npc_id → npc data dict (from JSON)
var _order: Array     = []      ## npc ids in file order (stable UI ordering)

var points:        Dictionary = {}   ## npc_id → int
var met:           Dictionary = {}   ## npc_id → true once introduced
var talked_today:  Dictionary = {}   ## npc_id → true
var gifted_today:  Dictionary = {}   ## npc_id → true


func _ready() -> void:
	_load_npcs()
	GameClock.day_started.connect(_on_day_started)


func _load_npcs() -> void:
	var text := FileAccess.get_file_as_string(NPCS_PATH)
	var parsed = JSON.parse_string(text) if not text.is_empty() else null
	if parsed == null or not parsed.has("npcs"):
		push_error("Relationships: could not load %s" % NPCS_PATH)
		return
	for npc in parsed["npcs"]:
		_npcs[npc["id"]] = npc
		_order.append(npc["id"])
	print("[Relationships] Loaded %d villagers." % _npcs.size())


func _on_day_started(_day: int, _season) -> void:
	talked_today.clear()
	gifted_today.clear()

# ---------------------------------------------------------------------------
# Lookup
# ---------------------------------------------------------------------------

func get_npc(npc_id: String) -> Dictionary:
	return _npcs.get(npc_id, {})


func get_all_npcs() -> Array:
	var result: Array = []
	for id in _order:
		result.append(_npcs[id])
	return result


func get_name_of(npc_id: String) -> String:
	return get_npc(npc_id).get("name", npc_id)


func get_points(npc_id: String) -> int:
	return int(points.get(npc_id, 0))


func get_hearts(npc_id: String) -> int:
	return get_points(npc_id) / POINTS_PER_HEART


func has_met(npc_id: String) -> bool:
	return met.has(npc_id)


func is_birthday(npc_id: String, season: int = -1, day: int = -1) -> bool:
	if season == -1:
		season = GameClock.current_season
	if day == -1:
		day = GameClock.current_day
	var bday: Dictionary = get_npc(npc_id).get("birthday", {})
	return bday.get("season", "") == GameClock.season_key(season) and int(bday.get("day", 0)) == day


func birthdays_today() -> Array:
	## Names of villagers celebrating today.
	var names: Array = []
	for id in _order:
		if is_birthday(id):
			names.append(get_name_of(id))
	return names


func count_friends(min_hearts: int) -> int:
	var n := 0
	for id in _order:
		if get_hearts(id) >= min_hearts:
			n += 1
	return n

# ---------------------------------------------------------------------------
# Friendship changes
# ---------------------------------------------------------------------------

func add_points(npc_id: String, amount: int) -> void:
	if not _npcs.has(npc_id):
		return
	points[npc_id] = clampi(get_points(npc_id) + amount, 0, MAX_POINTS)
	emit_signal("friendship_changed", npc_id, points[npc_id])


func add_points_all(amount: int) -> void:
	for id in _order:
		add_points(id, amount)


func talk(npc_id: String) -> Dictionary:
	## Chat with a villager. Returns:
	##   { "lines": Array, "first_meeting": bool, "gift": { item_id, line } or {} }
	var npc := get_npc(npc_id)
	var result := {"lines": [], "first_meeting": false, "gift": {}}
	if npc.is_empty():
		result["lines"] = ["..."]
		return result

	var dlg: Dictionary = npc.get("dialogue", {})
	if not has_met(npc_id):
		met[npc_id] = true
		result["first_meeting"] = true
		result["lines"].append_array(dlg.get("first_meet", []))
		result["gift"] = npc.get("first_meet_gift", {})

	result["lines"].append(_pick_line(npc_id, dlg))

	if not talked_today.has(npc_id):
		talked_today[npc_id] = true
		add_points(npc_id, TALK_POINTS)
	return result


func _pick_line(npc_id: String, dlg: Dictionary) -> String:
	## Pick today's line. Stable within a day so re-talking doesn't reroll.
	var roll := GameClock.days_elapsed + npc_id.hash()
	var hearts := get_hearts(npc_id)

	if is_birthday(npc_id):
		return "It's my birthday today! Thank you for stopping by."
	if Calendar.is_festival_today() and dlg.has("festival"):
		return _pick(dlg["festival"], roll)
	if Weather.is_raining() and dlg.has("rain") and roll % 2 == 0:
		return _pick(dlg["rain"], roll)
	if hearts >= 8 and dlg.has("hearts_8") and roll % 3 == 0:
		return _pick(dlg["hearts_8"], roll)
	if hearts >= 4 and dlg.has("hearts_4") and roll % 3 == 1:
		return _pick(dlg["hearts_4"], roll)

	var pool: Array = []
	pool.append_array(dlg.get(GameClock.season_key(), []))
	pool.append_array(dlg.get("default", []))
	if pool.is_empty():
		return "..."
	return _pick(pool, roll)


func _pick(lines: Array, roll: int) -> String:
	if lines.is_empty():
		return "..."
	return str(lines[absi(roll) % lines.size()])

# ---------------------------------------------------------------------------
# Gifts
# ---------------------------------------------------------------------------

func is_giftable(item_id: String) -> bool:
	var item := ItemDB.get_item(item_id)
	return not item.is_empty() and item.get("category", "") in GIFTABLE_CATEGORIES


func can_gift(npc_id: String) -> bool:
	return _npcs.has(npc_id) and not gifted_today.has(npc_id)


func get_taste(npc_id: String, item_id: String) -> String:
	## "loved" | "liked" | "disliked" | "neutral"
	var npc := get_npc(npc_id)
	if item_id in npc.get("loves", []):
		return "loved"
	if item_id in npc.get("likes", []):
		return "liked"
	if item_id in npc.get("dislikes", []):
		return "disliked"
	return "neutral"


func give_gift(npc_id: String, item_id: String) -> Dictionary:
	## Apply a gift's friendship effect. The caller removes the item.
	## Returns { "taste": String, "delta": int, "lines": Array }.
	var npc := get_npc(npc_id)
	var taste := get_taste(npc_id, item_id)
	var delta: int
	match taste:
		"loved":    delta = GIFT_LOVED
		"liked":    delta = GIFT_LIKED
		"disliked": delta = GIFT_DISLIKED
		_:          delta = GIFT_NEUTRAL

	var birthday := is_birthday(npc_id)
	if birthday:
		delta *= BIRTHDAY_MULT

	gifted_today[npc_id] = true
	met[npc_id] = true
	add_points(npc_id, delta)
	GameData.record_stat("gifts_given")

	var item_name: String = ItemDB.get_item(item_id).get("name", item_id)
	var dlg: Dictionary = npc.get("dialogue", {})
	var lines: Array = []
	if birthday:
		lines.append_array(dlg.get("birthday", []))
	match taste:
		"loved":
			lines.append(_pick(dlg.get("gift_loved", ["I love {item}! Thank you!"]), 0).format({"item": item_name}))
		"liked":
			lines.append("%s? Thank you, that's lovely." % item_name)
		"disliked":
			lines.append(_pick(dlg.get("gift_disliked", ["{item}... I don't really like this."]), 0).format({"item": item_name}))
		_:
			lines.append("Oh, %s. Thank you." % item_name)
	return {"taste": taste, "delta": delta, "lines": lines}

# ---------------------------------------------------------------------------
# Lifecycle / serialisation
# ---------------------------------------------------------------------------

func reset_to_new_game() -> void:
	points = {}
	met = {}
	talked_today = {}
	gifted_today = {}


func to_dict() -> Dictionary:
	return {
		"points":       points,
		"met":          met,
		"talked_today": talked_today,
		"gifted_today": gifted_today,
	}


func from_dict(d: Dictionary) -> void:
	points = {}
	for id in d.get("points", {}):
		points[id] = int(d["points"][id])   # JSON numbers load as floats
	met          = d.get("met", {})
	talked_today = d.get("talked_today", {})
	gifted_today = d.get("gifted_today", {})
