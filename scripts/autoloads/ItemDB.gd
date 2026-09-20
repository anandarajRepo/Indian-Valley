extends Node
## ItemDB.gd — Autoload that loads items.json and crops.json at startup.
## Provides fast lookup by item ID.
##
## Usage:
##   var item = ItemDB.get_item("paddy_grain")   # → Dictionary or null
##   var crop = ItemDB.get_crop("paddy")         # → Dictionary or null

const ITEMS_PATH: String = "res://data/items.json"
const CROPS_PATH: String = "res://data/crops.json"

var _items: Dictionary = {}   ## item_id → item dict
var _crops: Dictionary = {}   ## crop_id → crop dict


func _ready() -> void:
	_load_items()
	_load_crops()


func _load_items() -> void:
	var text = FileAccess.get_file_as_string(ITEMS_PATH)
	if text.is_empty():
		push_error("ItemDB: could not read %s" % ITEMS_PATH)
		return
	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed.has("items"):
		push_error("ItemDB: invalid JSON in %s" % ITEMS_PATH)
		return
	for item in parsed["items"]:
		_items[item["id"]] = item
	print("[ItemDB] Loaded %d items." % _items.size())


func _load_crops() -> void:
	var text = FileAccess.get_file_as_string(CROPS_PATH)
	if text.is_empty():
		push_error("ItemDB: could not read %s" % CROPS_PATH)
		return
	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed.has("crops"):
		push_error("ItemDB: invalid JSON in %s" % CROPS_PATH)
		return
	for crop in parsed["crops"]:
		_crops[crop["id"]] = crop
	print("[ItemDB] Loaded %d crops." % _crops.size())


func get_item(item_id: String) -> Dictionary:
	return _items.get(item_id, {})


func get_crop(crop_id: String) -> Dictionary:
	return _crops.get(crop_id, {})


func get_crop_for_seed(seed_id: String) -> Dictionary:
	## Given a seed item_id, find the crop that uses it.
	for crop_id in _crops:
		if _crops[crop_id].get("seed_id") == seed_id:
			return _crops[crop_id]
	return {}


func get_all_items() -> Array:
	return _items.values()


func get_all_crops() -> Array:
	return _crops.values()


func get_crops_for_season(season: int) -> Array:
	## Return crops available in the given GameClock.Season value.
	var season_name = GameClock.SEASON_NAMES.get(season, "").to_lower()
	var result: Array = []
	for crop in _crops.values():
		if season_name in crop.get("seasons", []):
			result.append(crop)
	return result
