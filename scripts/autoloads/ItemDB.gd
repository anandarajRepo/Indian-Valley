extends Node
## ItemDB.gd — Autoload that loads items.json and crops.json at startup.
## Provides fast lookup by item ID.
##
## Also loads the Panchayat Hall offering bundles (bundles.json).
##
## Usage:
##   var item = ItemDB.get_item("paddy_grain")   # → Dictionary or {}
##   var crop = ItemDB.get_crop("paddy")         # → Dictionary or {}

const ITEMS_PATH:   String = "res://data/items.json"
const CROPS_PATH:   String = "res://data/crops.json"
const BUNDLES_PATH: String = "res://data/bundles.json"

var _items: Dictionary = {}   ## item_id → item dict
var _crops: Dictionary = {}   ## crop_id → crop dict
var _bundles: Array = []      ## Panchayat Hall bundles, in display order
var _bundle_completion: Dictionary = {}


func _ready() -> void:
	_load_items()
	_load_crops()
	_load_bundles()


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


func _load_bundles() -> void:
	var text = FileAccess.get_file_as_string(BUNDLES_PATH)
	var parsed = JSON.parse_string(text) if not text.is_empty() else null
	if parsed == null or not parsed.has("bundles"):
		push_error("ItemDB: invalid JSON in %s" % BUNDLES_PATH)
		return
	_bundles = parsed["bundles"]
	_bundle_completion = parsed.get("completion", {})
	print("[ItemDB] Loaded %d Hall bundles." % _bundles.size())


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


func get_items_for_season(category: String, season: int) -> Array:
	## Items of a category (e.g. "forage", "fish") whose "seasons" include season.
	var key = GameClock.season_key(season)
	var result: Array = []
	for item in _items.values():
		if item.get("category", "") == category and key in item.get("seasons", []):
			result.append(item)
	return result


func get_bundles() -> Array:
	return _bundles


func get_bundle(bundle_id: String) -> Dictionary:
	for b in _bundles:
		if b.get("id", "") == bundle_id:
			return b
	return {}


func get_bundle_completion() -> Dictionary:
	return _bundle_completion
