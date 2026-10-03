extends Node
## SaveManager.gd — Autoload handling JSON save/load across 3 slots.
##
## Save file path: user://saves/slot_{n}.json
## Writes are crash-safe: the new save goes to slot_{n}.json.tmp first, the
## previous save is kept as slot_{n}.json.bak, then the temp file is moved into
## place. A damaged save file falls back to the backup when loading.
## Each save contains: clock state, player data, weather, friendships, calendar
## progress, plus scene data from the GameManager (farm tiles, inventory,
## forage spawns, Panchayat Hall offerings).

const SAVE_DIR:   String = "user://saves/"
const SLOT_COUNT: int    = 3
const VERSION:    int    = 3   ## Increment on breaking save format changes
## v2 (Phase 2 — Alpha): adds "weather", "social", "calendar", "world", "hall"
##     sections and player "stats". v1 saves load with fresh defaults for these.
## v3 (Phase 3 — Beta): adds "quests" and "mines" sections, player
##     "tool_levels" / "collected", and romance fields in "social".

signal save_completed(slot: int)
signal load_completed(slot: int)
signal load_failed(slot: int, reason: String)

## The full parsed contents of the most recently loaded save. Lets the game
## manager pull scene-specific sections (farm tiles, inventory) after a load.
var last_loaded: Dictionary = {}

## True when the most recent load had to fall back to the .bak file.
var last_load_recovered: bool = false


func _ready() -> void:
	_ensure_save_dir()


func _ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)


# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------

func save_game(slot: int, extra_data: Dictionary = {}) -> bool:
	## Collect state from all autoloads, merge extra_data (e.g. farm tile data
	## from the Farm scene), and write to the slot file.
	if slot < 0 or slot >= SLOT_COUNT:
		push_error("SaveManager: invalid slot %d" % slot)
		return false

	var data: Dictionary = {
		"version":  VERSION,
		"slot":     slot,
		"saved_at": Time.get_datetime_string_from_system(),
		"clock":    GameClock.to_dict(),
		"player":   GameData.to_dict(),
		"weather":  Weather.to_dict(),
		"social":   Relationships.to_dict(),
		"calendar": Calendar.to_dict(),
		"quests":   Quests.to_dict(),
	}

	# Merge any extra scene-specific data (e.g. farm tiles, NPC states)
	for key in extra_data:
		data[key] = extra_data[key]

	var path = _slot_path(slot)
	if not _write_atomic(path, JSON.stringify(data, "\t")):
		return false

	emit_signal("save_completed", slot)
	print("[SaveManager] Game saved to slot %d (%s)" % [slot, path])
	return true


# ---------------------------------------------------------------------------
# Load
# ---------------------------------------------------------------------------

func load_game(slot: int) -> bool:
	if slot < 0 or slot >= SLOT_COUNT:
		push_error("SaveManager: invalid slot %d" % slot)
		return false

	var path = _slot_path(slot)
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(_backup_path(slot)):
		emit_signal("load_failed", slot, "File not found")
		return false

	last_load_recovered = false
	var data := _read_save(path)
	if data.is_empty():
		data = _read_save(_backup_path(slot))
		if data.is_empty():
			emit_signal("load_failed", slot, "Save file is damaged")
			return false
		push_warning("SaveManager: slot %d was damaged — loaded the backup" % slot)
		last_load_recovered = true

	# Version migration hook (extend as needed)
	var file_version = data.get("version", 0)
	if file_version < VERSION:
		print("[SaveManager] Migrating save from v%d → v%d" % [file_version, VERSION])
		data = _migrate(data, file_version)

	# Restore autoload state
	if data.has("clock"):
		GameClock.from_dict(data["clock"])
	if data.has("player"):
		GameData.from_dict(data["player"])
	# Sections added in v2 — an absent section restores clean defaults.
	Relationships.from_dict(data.get("social", {}))
	Calendar.from_dict(data.get("calendar", {}))
	Weather.from_dict(data.get("weather", {}))
	Quests.from_dict(data.get("quests", {}))

	# Stash the full payload so the manager can restore farm tiles / inventory.
	last_loaded = data

	emit_signal("load_completed", slot)
	print("[SaveManager] Game loaded from slot %d" % slot)
	return true


# ---------------------------------------------------------------------------
# Slot info (for the save-slot selection UI)
# ---------------------------------------------------------------------------

func get_slot_info(slot: int) -> Dictionary:
	## Returns metadata for a slot without fully loading it, or {} if empty.
	if not slot_exists(slot):
		return {}

	var data := _read_save(_slot_path(slot))
	if data.is_empty():
		data = _read_save(_backup_path(slot))
	if data.is_empty():
		return {"slot": slot, "damaged": true, "saved_at": ""}

	var clock = data.get("clock", {})
	var player = data.get("player", {})
	return {
		"slot":       slot,
		"saved_at":   data.get("saved_at", ""),
		"player_name":player.get("player_name", ""),
		"day":        int(clock.get("day", 1)),
		"season":     int(clock.get("season", 0)),
		"year":       int(clock.get("year", 1)),
		"gold":       int(player.get("gold", 0)),
	}


func describe_slot(slot: int) -> String:
	## One-line summary for the slot picker, e.g. "Arya — Day 3, Kharif, Year 1 · ₹1200".
	var info := get_slot_info(slot)
	if info.is_empty():
		return "Empty"
	if info.get("damaged", false):
		return "Damaged save"
	return "%s — Day %d, %s, Year %d · ₹%d" % [info["player_name"], info["day"],
		GameClock.SEASON_NAMES.get(info["season"], "?"), info["year"], info["gold"]]


func most_recent_slot() -> int:
	## The slot saved most recently, or -1 when there are no saves.
	var best := -1
	var best_time := ""
	for slot in range(SLOT_COUNT):
		var info := get_slot_info(slot)
		if info.is_empty() or info.get("damaged", false):
			continue
		if best == -1 or String(info["saved_at"]) > best_time:
			best = slot
			best_time = info["saved_at"]
	return best


func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot)) or FileAccess.file_exists(_backup_path(slot))


func delete_slot(slot: int) -> void:
	for path in [_slot_path(slot), _backup_path(slot), _slot_path(slot) + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _slot_path(slot: int) -> String:
	return SAVE_DIR + "slot_%d.json" % slot


func _backup_path(slot: int) -> String:
	return _slot_path(slot) + ".bak"


func _write_atomic(path: String, text: String) -> bool:
	## Write `text` to a temp file, keep the old file as .bak, then swap the
	## temp file in. A crash at any point leaves a loadable save behind.
	_ensure_save_dir()
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: could not open %s for writing" % tmp)
		return false
	file.store_string(text)
	file.close()
	if _read_save(tmp).is_empty():
		push_error("SaveManager: %s failed verification" % tmp)
		DirAccess.remove_absolute(tmp)
		return false
	var bak := path + ".bak"
	if FileAccess.file_exists(path):
		# Only a good save becomes the backup — never overwrite it with junk.
		if not _read_save(path).is_empty():
			if FileAccess.file_exists(bak):
				DirAccess.remove_absolute(bak)
			DirAccess.rename_absolute(path, bak)
		else:
			DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(tmp, path) != OK:
		push_error("SaveManager: could not move %s into place" % tmp)
		return false
	return true


func _read_save(path: String) -> Dictionary:
	## Parse a save file; {} when it is missing, empty or not a save.
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	# JSON.parse (unlike parse_string) reports bad files quietly.
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var data = json.data
	if not data is Dictionary or not data.has("clock"):
		return {}
	return data


func _migrate(data: Dictionary, from_version: int) -> Dictionary:
	## Upgrade older save payloads step by step to the current format.
	if from_version < 2:
		# v1 → v2: new sections simply start empty; loaders fill in defaults.
		for key in ["weather", "social", "calendar", "world", "hall"]:
			if not data.has(key):
				data[key] = {}
	if from_version < 3:
		# v2 → v3: quests and mines start empty; tools unupgraded; romance fresh.
		for key in ["quests", "mines"]:
			if not data.has(key):
				data[key] = {}
	data["version"] = VERSION
	return data
