extends Node2D
## Farm.gd — The player's home base scene.
##
## Manages:
##   - TileMap layers (ground, crops, objects, decorations)
##   - Spawning and connecting the Player
##   - Farming system (till → plant → water → harvest)
##   - Shipping chest interaction
##   - Day-start crop growth tick
##   - Saving/loading farm-specific data (tile states)

signal farm_saved(data: Dictionary)

# ---------------------------------------------------------------------------
# Tile layer indices
# ---------------------------------------------------------------------------

const LAYER_GROUND:  int = 0
const LAYER_CROPS:   int = 1
const LAYER_OBJECTS: int = 2

# ---------------------------------------------------------------------------
# Tile IDs in the TileSet (placeholder IDs — update to match your TileSet)
# ---------------------------------------------------------------------------

## Source ID in the TileSet resource
const TILESET_SOURCE: int = 0

## Atlas coords for each tile type (row, col in the atlas)
const TILE_GRASS:        Vector2i = Vector2i(0, 0)
const TILE_SOIL_DRY:     Vector2i = Vector2i(1, 0)
const TILE_SOIL_TILLED:  Vector2i = Vector2i(2, 0)
const TILE_SOIL_WATERED: Vector2i = Vector2i(3, 0)
const TILE_PATH:         Vector2i = Vector2i(4, 0)
const TILE_WATER:        Vector2i = Vector2i(5, 0)

# ---------------------------------------------------------------------------
# Nodes
# ---------------------------------------------------------------------------

@onready var tilemap:        TileMap = $TileMap
@onready var player_spawn:   Marker2D = $PlayerSpawn
@onready var shipping_chest: Node2D   = $ShippingChest
@onready var hud:            CanvasLayer = $HUD

## Dynamically instantiated
var player_instance: CharacterBody2D = null

const PLAYER_SCENE = preload("res://scenes/Player/Player.tscn")

# ---------------------------------------------------------------------------
# Farm tile state (persisted in save)
# ---------------------------------------------------------------------------

## Keyed by "x,y" tile coordinate string
## Value: { "state": "tilled"|"watered"|"planted", "crop_id": String,
##           "growth_day": int, "days_watered": int }
var _tile_data: Dictionary = {}

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_spawn_player()
	_connect_signals()
	_setup_farm_tiles()
	GameClock.day_started.connect(_on_day_started)
	GameClock.sleep_triggered.connect(_on_sleep_triggered)


func _spawn_player() -> void:
	player_instance = PLAYER_SCENE.instantiate()
	add_child(player_instance)
	player_instance.global_position = player_spawn.global_position if player_spawn else Vector2(80, 80)
	player_instance.tool_used.connect(_on_tool_used)


func _connect_signals() -> void:
	## Connect player inventory once it's available (Feature 6)
	pass


func _setup_farm_tiles() -> void:
	## Draws a basic farm layout if no save data exists.
	## This is a placeholder — proper tile art will replace the atlas coords.
	if _tile_data.is_empty():
		_draw_default_farm()


func _draw_default_farm() -> void:
	## A small 20×15 farm: grass surround, 10×8 farmable plot in the centre.
	if tilemap == null:
		return

	var map_width  = 20
	var map_height = 15
	var plot_x     = 5
	var plot_y     = 3
	var plot_w     = 10
	var plot_h     = 8

	for y in range(map_height):
		for x in range(map_width):
			tilemap.set_cell(LAYER_GROUND, Vector2i(x, y), TILESET_SOURCE, TILE_GRASS)

	## Farm plot — tilled soil
	for y in range(plot_y, plot_y + plot_h):
		for x in range(plot_x, plot_x + plot_w):
			tilemap.set_cell(LAYER_GROUND, Vector2i(x, y), TILESET_SOURCE, TILE_SOIL_DRY)

# ---------------------------------------------------------------------------
# Tool use handler (connected to Player.tool_used)
# ---------------------------------------------------------------------------

func _on_tool_used(tool_id: String, tile_pos: Vector2i) -> void:
	var item = ItemDB.get_item(tool_id)
	if item.is_empty():
		return

	var tool_type = item.get("tool_type", "")
	var category  = item.get("category",  "")

	match tool_type:
		"hoe":     _till_soil(tile_pos)
		"water":   _water_tile(tile_pos)
		"harvest": _harvest_tile(tile_pos)
		"mine":    pass   ## handled by Mines scene

	if category == "seed":
		_plant_seed(tile_pos, tool_id)


# ---------------------------------------------------------------------------
# Farming actions
# ---------------------------------------------------------------------------

func _till_soil(tile_pos: Vector2i) -> void:
	var ground_tile = tilemap.get_cell_atlas_coords(LAYER_GROUND, tile_pos)
	if ground_tile == TILE_SOIL_DRY or ground_tile == TILE_GRASS:
		tilemap.set_cell(LAYER_GROUND, tile_pos, TILESET_SOURCE, TILE_SOIL_TILLED)
		var key = _key(tile_pos)
		if not _tile_data.has(key):
			_tile_data[key] = {"state": "tilled", "crop_id": "", "growth_day": 0, "days_watered": 0}
		GameData.add_skill_xp("farming", 1)
		print("[Farm] Tilled tile at %s" % str(tile_pos))


func _water_tile(tile_pos: Vector2i) -> void:
	var key = _key(tile_pos)
	if not _tile_data.has(key):
		return
	var data = _tile_data[key]
	if data["state"] in ["tilled", "planted"]:
		data["days_watered"] = GameClock.current_day
		tilemap.set_cell(LAYER_GROUND, tile_pos, TILESET_SOURCE, TILE_SOIL_WATERED)
		GameData.add_skill_xp("farming", 1)
		print("[Farm] Watered tile at %s" % str(tile_pos))


func _plant_seed(tile_pos: Vector2i, seed_id: String) -> void:
	var key = _key(tile_pos)
	if not _tile_data.has(key):
		return
	var data = _tile_data[key]
	if data["state"] != "tilled":
		return

	var crop = ItemDB.get_crop_for_seed(seed_id)
	if crop.is_empty():
		return

	## Check season
	var season_name = GameClock.get_season_name().to_lower()
	if not season_name in crop.get("seasons", []):
		print("[Farm] %s can't grow in %s!" % [crop["name"], season_name])
		return

	data["state"]      = "planted"
	data["crop_id"]    = crop["id"]
	data["growth_day"] = GameClock.current_day   ## day it was planted
	data["stage"]      = 0

	## TODO: place crop sprite on LAYER_CROPS
	print("[Farm] Planted %s at %s (day %d)" % [crop["name"], str(tile_pos), GameClock.current_day])


func _harvest_tile(tile_pos: Vector2i) -> void:
	var key = _key(tile_pos)
	if not _tile_data.has(key):
		return
	var data = _tile_data[key]
	if data["state"] != "planted":
		return

	var crop = ItemDB.get_crop(data["crop_id"])
	if crop.is_empty():
		return

	var days_grown = GameClock.current_day - data["growth_day"]
	if days_grown < crop.get("growth_days", 999):
		print("[Farm] %s not ready yet (%d/%d days)" % [crop["name"], days_grown, crop["growth_days"]])
		return

	## Give product to inventory
	## (inventory reference not set until Feature 6 — print for now)
	print("[Farm] Harvested %s → %s" % [crop["name"], crop["product_id"]])
	GameData.add_skill_xp("farming", 5)

	## Reset tile
	if crop.get("regrows", false):
		data["growth_day"] = GameClock.current_day
		data["stage"] = 0
	else:
		_tile_data.erase(key)
		tilemap.set_cell(LAYER_GROUND, tile_pos, TILESET_SOURCE, TILE_SOIL_TILLED)
		tilemap.erase_cell(LAYER_CROPS, tile_pos)

# ---------------------------------------------------------------------------
# Day tick (grow crops overnight)
# ---------------------------------------------------------------------------

func _on_day_started(_day: int, _season) -> void:
	_grow_crops()
	_reset_watered_tiles()


func _grow_crops() -> void:
	for key in _tile_data:
		var data = _tile_data[key]
		if data["state"] != "planted":
			continue

		var crop = ItemDB.get_crop(data.get("crop_id", ""))
		if crop.is_empty():
			continue

		## Only grow if watered yesterday
		var watered_yesterday = data.get("days_watered", -1) == GameClock.current_day - 1
		if not watered_yesterday:
			continue

		var max_stage = crop.get("stages", 4) - 1
		if data.get("stage", 0) < max_stage:
			data["stage"] += 1
			## TODO: update sprite frame on LAYER_CROPS
			print("[Farm] %s grew to stage %d" % [crop.get("name", "?"), data["stage"]])


func _reset_watered_tiles() -> void:
	## Dry out watered tiles each morning (player must re-water)
	for key in _tile_data:
		var data = _tile_data[key]
		if data["state"] in ["tilled", "planted"]:
			var tile_pos = _pos_from_key(key)
			var tile = tilemap.get_cell_atlas_coords(LAYER_GROUND, tile_pos)
			if tile == TILE_SOIL_WATERED:
				tilemap.set_cell(LAYER_GROUND, tile_pos, TILESET_SOURCE, TILE_SOIL_TILLED)

# ---------------------------------------------------------------------------
# Sleep handler
# ---------------------------------------------------------------------------

func _on_sleep_triggered() -> void:
	## Trigger save before clock advances
	_save_farm()


func _save_farm() -> void:
	var extra = {"farm": {"tiles": _tile_data}}
	SaveManager.save_game(0, extra)   ## Always save to slot 0 for now

# ---------------------------------------------------------------------------
# Save/Load farm-specific state
# ---------------------------------------------------------------------------

func load_farm_data(data: Dictionary) -> void:
	_tile_data = data.get("tiles", {})
	_redraw_farm_from_save()


func _redraw_farm_from_save() -> void:
	## Re-draw tiles from saved state
	for key in _tile_data:
		var tile_pos = _pos_from_key(key)
		var data = _tile_data[key]
		match data.get("state", ""):
			"tilled":
				tilemap.set_cell(LAYER_GROUND, tile_pos, TILESET_SOURCE, TILE_SOIL_TILLED)
			"planted":
				tilemap.set_cell(LAYER_GROUND, tile_pos, TILESET_SOURCE, TILE_SOIL_TILLED)
				## TODO: set crop sprite stage

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

func _key(tile_pos: Vector2i) -> String:
	return "%d,%d" % [tile_pos.x, tile_pos.y]


func _pos_from_key(key: String) -> Vector2i:
	var parts = key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))
