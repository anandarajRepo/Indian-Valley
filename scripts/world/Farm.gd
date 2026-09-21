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

## Atlas coords for each tile type (column, row in the atlas)
const TILE_GRASS:        Vector2i = Vector2i(0, 0)
const TILE_SOIL_DRY:     Vector2i = Vector2i(1, 0)
const TILE_SOIL_TILLED:  Vector2i = Vector2i(2, 0)
const TILE_SOIL_WATERED: Vector2i = Vector2i(3, 0)
const TILE_PATH:         Vector2i = Vector2i(4, 0)
const TILE_WATER:        Vector2i = Vector2i(5, 0)

## Placeholder tile colours (Phase 0 has no art — a solid-colour atlas is
## generated at runtime so the farm is visible and tile logic works).
const PLACEHOLDER_COLORS: Array = [
	Color(0.35, 0.55, 0.25),   # grass
	Color(0.55, 0.42, 0.28),   # dry soil
	Color(0.40, 0.28, 0.16),   # tilled soil
	Color(0.28, 0.20, 0.12),   # watered soil
	Color(0.62, 0.58, 0.45),   # path
	Color(0.25, 0.45, 0.65),   # water
]
const TILE_PX: int = 16

# ---------------------------------------------------------------------------
# Farm plot bounds (tile coords) — the region the player is allowed to farm.
# ---------------------------------------------------------------------------

const PLOT_X: int = 5
const PLOT_Y: int = 3
const PLOT_W: int = 10
const PLOT_H: int = 8
const MAP_W:  int = 20
const MAP_H:  int = 15

# ---------------------------------------------------------------------------
# Nodes
# ---------------------------------------------------------------------------

@onready var tilemap:        TileMap     = $TileMap
@onready var player_spawn:   Marker2D    = $PlayerSpawn
@onready var shipping_chest: Node2D      = $ShippingChest
@onready var hud:            CanvasLayer = $HUD

## Dynamically instantiated
var player_instance: CharacterBody2D = null

const PLAYER_SCENE = preload("res://scenes/Player/Player.tscn")

# ---------------------------------------------------------------------------
# Farm tile state (persisted in save)
# ---------------------------------------------------------------------------

## Keyed by "x,y" tile coordinate string
## Value: { "state": "tilled"|"planted", "crop_id": String,
##           "planted_day": int, "watered_day": int, "progress": int, "stage": int }
##   planted_day / watered_day are absolute GameClock.days_elapsed values.
##   progress counts the number of watered days accrued toward growth_days.
var _tile_data: Dictionary = {}

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_setup_tilemap()
	_spawn_player()
	_connect_signals()
	_setup_farm_tiles()
	GameClock.day_started.connect(_on_day_started)
	GameClock.sleep_triggered.connect(_on_sleep_triggered)


func _setup_tilemap() -> void:
	## Give the TileMap a placeholder TileSet and the three layers we rely on.
	if tilemap == null:
		return
	if tilemap.tile_set == null:
		tilemap.tile_set = _build_placeholder_tileset()
	while tilemap.get_layers_count() < 3:
		tilemap.add_layer(-1)


func _build_placeholder_tileset() -> TileSet:
	## Builds a solid-colour atlas (one 16×16 tile per PLACEHOLDER_COLORS entry)
	## so the ground layer renders and get_cell_atlas_coords works in Phase 0.
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_PX, TILE_PX)

	var count := PLACEHOLDER_COLORS.size()
	var img := Image.create(TILE_PX * count, TILE_PX, false, Image.FORMAT_RGBA8)
	for i in range(count):
		img.fill_rect(Rect2i(i * TILE_PX, 0, TILE_PX, TILE_PX), PLACEHOLDER_COLORS[i])

	var tex := ImageTexture.create_from_image(img)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(TILE_PX, TILE_PX)
	ts.add_source(src, TILESET_SOURCE)
	for i in range(count):
		src.create_tile(Vector2i(i, 0))
	return ts


func _spawn_player() -> void:
	player_instance = PLAYER_SCENE.instantiate()
	add_child(player_instance)
	player_instance.global_position = player_spawn.global_position if player_spawn else Vector2(96, 88)
	player_instance.tool_used.connect(_on_tool_used)


func _connect_signals() -> void:
	## The inventory lives on the player. Wire it to the HUD and shipping chest.
	var inventory = player_instance.inventory if player_instance else null
	if inventory:
		inventory.inventory_changed.connect(_on_inventory_changed)
		inventory.hotbar_selection_changed.connect(_on_hotbar_selection_changed)
	if shipping_chest:
		shipping_chest.player_inventory = inventory
	if hud:
		hud.hotbar_slot_clicked.connect(_on_hud_hotbar_clicked)
	_refresh_hud_hotbar()


func _setup_farm_tiles() -> void:
	## Draws a basic farm layout if no save data exists.
	if _tile_data.is_empty():
		_draw_default_farm()
	else:
		_redraw_farm_from_save()


func _draw_default_farm() -> void:
	## Grass surround with a farmable plot of dry soil in the centre.
	if tilemap == null:
		return

	for y in range(MAP_H):
		for x in range(MAP_W):
			tilemap.set_cell(LAYER_GROUND, Vector2i(x, y), TILESET_SOURCE, TILE_GRASS)

	for y in range(PLOT_Y, PLOT_Y + PLOT_H):
		for x in range(PLOT_X, PLOT_X + PLOT_W):
			tilemap.set_cell(LAYER_GROUND, Vector2i(x, y), TILESET_SOURCE, TILE_SOIL_DRY)

# ---------------------------------------------------------------------------
# HUD / inventory glue
# ---------------------------------------------------------------------------

func _on_inventory_changed() -> void:
	_refresh_hud_hotbar()


func _on_hotbar_selection_changed(_slot_index: int) -> void:
	_refresh_hud_hotbar()


func _on_hud_hotbar_clicked(index: int) -> void:
	if player_instance and player_instance.inventory:
		player_instance.inventory.set_hotbar_index(index)


func _refresh_hud_hotbar() -> void:
	if hud == null or player_instance == null or player_instance.inventory == null:
		return
	var inventory = player_instance.inventory
	hud.update_hotbar(inventory.get_all_hotbar_slots(), inventory.get_hotbar_index())


func _notify(message: String) -> void:
	if hud and hud.has_method("show_notification"):
		hud.show_notification(message)

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

func _is_farmable(tile_pos: Vector2i) -> bool:
	return tile_pos.x >= PLOT_X and tile_pos.x < PLOT_X + PLOT_W \
		and tile_pos.y >= PLOT_Y and tile_pos.y < PLOT_Y + PLOT_H


func _till_soil(tile_pos: Vector2i) -> void:
	if not _is_farmable(tile_pos):
		return
	var key = _key(tile_pos)
	if _tile_data.has(key):
		return   ## Already tilled / planted.
	tilemap.set_cell(LAYER_GROUND, tile_pos, TILESET_SOURCE, TILE_SOIL_TILLED)
	_tile_data[key] = {
		"state": "tilled", "crop_id": "",
		"planted_day": -1, "watered_day": -1, "progress": 0, "stage": 0,
	}
	GameData.add_skill_xp("farming", 1)
	_notify("Tilled soil")


func _water_tile(tile_pos: Vector2i) -> void:
	var key = _key(tile_pos)
	if not _tile_data.has(key):
		return
	var data = _tile_data[key]
	if data["state"] in ["tilled", "planted"]:
		data["watered_day"] = GameClock.days_elapsed
		tilemap.set_cell(LAYER_GROUND, tile_pos, TILESET_SOURCE, TILE_SOIL_WATERED)
		GameData.add_skill_xp("farming", 1)


func _plant_seed(tile_pos: Vector2i, seed_id: String) -> void:
	var key = _key(tile_pos)
	if not _tile_data.has(key):
		_notify("Till the soil first")
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
		_notify("%s can't grow in %s" % [crop["name"], GameClock.get_season_name()])
		return

	data["state"]       = "planted"
	data["crop_id"]     = crop["id"]
	data["planted_day"] = GameClock.days_elapsed
	data["progress"]    = 0
	data["stage"]       = 0
	_notify("Planted %s" % crop["name"])


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

	if data.get("progress", 0) < crop.get("growth_days", 999):
		_notify("%s isn't ready yet" % crop["name"])
		return

	## Give the product to the player's inventory.
	var product_id = crop.get("product_id", "")
	if product_id != "" and player_instance and player_instance.inventory:
		player_instance.inventory.add_item(product_id, 1)
	GameData.add_skill_xp("farming", 5)
	_notify("Harvested %s" % crop["name"])

	## Regrowing crops restart partway; others clear back to tilled soil.
	if crop.get("regrows", false):
		var regrow_days = crop.get("regrow_days", crop.get("growth_days", 1))
		data["progress"]    = max(0, crop.get("growth_days", 1) - regrow_days)
		data["stage"]       = 0
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
	_refresh_hud_hotbar()


func _grow_crops() -> void:
	for key in _tile_data:
		var data = _tile_data[key]
		if data["state"] != "planted":
			continue

		var crop = ItemDB.get_crop(data.get("crop_id", ""))
		if crop.is_empty():
			continue

		## Advance one day of growth only if the tile was watered yesterday.
		var watered_yesterday = data.get("watered_day", -1) == GameClock.days_elapsed - 1
		if not watered_yesterday:
			continue

		var growth_days = crop.get("growth_days", 1)
		if data.get("progress", 0) < growth_days:
			data["progress"] += 1
			## Derive a visual stage from progress (for when crop art lands).
			var stages = max(1, crop.get("stages", 4))
			data["stage"] = int(float(data["progress"]) / growth_days * (stages - 1))


func _reset_watered_tiles() -> void:
	## Dry out watered tiles each morning (player must re-water).
	for key in _tile_data:
		var data = _tile_data[key]
		if data["state"] in ["tilled", "planted"]:
			var tile_pos = _pos_from_key(key)
			if tilemap.get_cell_atlas_coords(LAYER_GROUND, tile_pos) == TILE_SOIL_WATERED:
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
	emit_signal("farm_saved", extra)

# ---------------------------------------------------------------------------
# Save/Load farm-specific state
# ---------------------------------------------------------------------------

func load_farm_data(data: Dictionary) -> void:
	_tile_data = data.get("tiles", {})
	_redraw_farm_from_save()


func _redraw_farm_from_save() -> void:
	## Draw the base layout, then re-apply saved tile states on top.
	_draw_default_farm()
	for key in _tile_data:
		var tile_pos = _pos_from_key(key)
		var data = _tile_data[key]
		match data.get("state", ""):
			"tilled", "planted":
				tilemap.set_cell(LAYER_GROUND, tile_pos, TILESET_SOURCE, TILE_SOIL_TILLED)

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

func _key(tile_pos: Vector2i) -> String:
	return "%d,%d" % [tile_pos.x, tile_pos.y]


func _pos_from_key(key: String) -> Vector2i:
	var parts = key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))
