extends Node
## SaveManager.gd — Autoload handling JSON save/load across 3 slots.
##
## Save file path: user://saves/slot_{n}.json
## Each save contains: clock state, player data, weather, friendships, calendar
## progress, plus scene data from the GameManager (farm tiles, inventory,
## forage spawns, Panchayat Hall offerings).

const SAVE_DIR:   String = "user://saves/"
const SLOT_COUNT: int    = 3
const VERSION:    int    = 2   ## Increment on breaking save format changes
## v2 (Phase 2 — Alpha): adds "weather", "social", "calendar", "world", "hall"
##     sections and player "stats". v1 saves load with fresh defaults for these.

signal save_completed(slot: int)
signal load_completed(slot: int)
signal load_failed(slot: int, reason: String)

## The full parsed contents of the most recently loaded save. Lets the game
## manager pull scene-specific sections (farm tiles, inventory) after a load.
var last_loaded: Dictionary = {}


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
	}

	# Merge any extra scene-specific data (e.g. farm tiles, NPC states)
	for key in extra_data:
		data[key] = extra_data[key]

	var path = _slot_path(slot)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: could not open %s for writing" % path)
		return false

	file.store_string(JSON.stringify(data, "\t"))
	file.close()

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
	if not FileAccess.file_exists(path):
		emit_signal("load_failed", slot, "File not found")
		return false

	var text = FileAccess.get_file_as_string(path)
	if text.is_empty():
		emit_signal("load_failed", slot, "Empty file")
		return false

	var data = JSON.parse_string(text)
	if data == null:
		emit_signal("load_failed", slot, "JSON parse error")
		return false

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
	var path = _slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}

	var text = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}

	var data = JSON.parse_string(text)
	if data == null:
		return {}

	var clock = data.get("clock", {})
	var player = data.get("player", {})
	return {
		"slot":       slot,
		"saved_at":   data.get("saved_at", ""),
		"player_name":player.get("player_name", ""),
		"day":        clock.get("day", 1),
		"season":     clock.get("season", 0),
		"year":       clock.get("year", 1),
		"gold":       player.get("gold", 0),
	}


func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


func delete_slot(slot: int) -> void:
	var path = _slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _slot_path(slot: int) -> String:
	return SAVE_DIR + "slot_%d.json" % slot


func _migrate(data: Dictionary, from_version: int) -> Dictionary:
	## Upgrade older save payloads step by step to the current format.
	if from_version < 2:
		# v1 → v2: new sections simply start empty; loaders fill in defaults.
		for key in ["weather", "social", "calendar", "world", "hall"]:
			if not data.has(key):
				data[key] = {}
	data["version"] = VERSION
	return data
