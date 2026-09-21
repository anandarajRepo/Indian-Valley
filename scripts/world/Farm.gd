extends WorldBase
## Farm.gd — the player's home base.
##
## Renders and drives the farm plot (till → plant → water → harvest). The
## authoritative tile state lives in GameManager.farm_tiles so it survives
## trips to town and overnight growth (simulated by the manager). This scene
## reads that state and paints the TileMap accordingly.

# ---------------------------------------------------------------------------
# Tile layers
# ---------------------------------------------------------------------------

const LAYER_GROUND: int = 0
const LAYER_CROPS:  int = 1
const LAYER_OBJECTS: int = 2

const TILESET_SOURCE: int = 0

## Ground atlas coords
const TILE_GRASS:        Vector2i = Vector2i(0, 0)
const TILE_SOIL_DRY:     Vector2i = Vector2i(1, 0)
const TILE_SOIL_TILLED:  Vector2i = Vector2i(2, 0)
const TILE_SOIL_WATERED: Vector2i = Vector2i(3, 0)
const TILE_PATH:         Vector2i = Vector2i(4, 0)
const TILE_WATER:        Vector2i = Vector2i(5, 0)

## Crop stage atlas coords (placeholder colours)
const TILE_CROP_YOUNG:   Vector2i = Vector2i(6, 0)
const TILE_CROP_MID:     Vector2i = Vector2i(7, 0)
const TILE_CROP_MATURE:  Vector2i = Vector2i(8, 0)
const TILE_CROP_READY:   Vector2i = Vector2i(9, 0)

## Placeholder tile colours (no art yet — a solid-colour atlas is generated).
const PLACEHOLDER_COLORS: Array = [
	Color(0.35, 0.55, 0.25),   # 0 grass
	Color(0.55, 0.42, 0.28),   # 1 dry soil
	Color(0.40, 0.28, 0.16),   # 2 tilled soil
	Color(0.28, 0.20, 0.12),   # 3 watered soil
	Color(0.62, 0.58, 0.45),   # 4 path
	Color(0.25, 0.45, 0.65),   # 5 water
	Color(0.55, 0.80, 0.40),   # 6 crop young
	Color(0.35, 0.68, 0.28),   # 7 crop mid
	Color(0.22, 0.52, 0.20),   # 8 crop mature
	Color(0.90, 0.78, 0.28),   # 9 crop ready
]
const TILE_PX: int = 16

# ---------------------------------------------------------------------------
# Farm plot bounds (tile coords)
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

@onready var tilemap:        TileMap = $TileMap
@onready var shipping_chest: Node2D  = $ShippingChest

## Authoritative tile state — a live reference to GameManager.farm_tiles.
var _tile_data: Dictionary = {}

# ---------------------------------------------------------------------------
# WorldBase hooks
# ---------------------------------------------------------------------------

func _world_ready() -> void:
	if GameManager.instance:
		_tile_data = GameManager.instance.farm_tiles
		GameManager.instance.farm_updated.connect(_render_all)

	_setup_tilemap()
	_render_all()

	# Wire the shipping chest to the freshly spawned player's inventory.
	if shipping_chest and player_instance:
		shipping_chest.player_inventory = player_instance.inventory


func _on_tool_used(tool_id: String, tile_pos: Vector2i) -> void:
	var item = ItemDB.get_item(tool_id)
	if item.is_empty():
		return

	var tool_type = item.get("tool_type", "")
	var category  = item.get("category", "")

	match tool_type:
		"hoe":     _till_soil(tile_pos)
		"water":   _water_tile(tile_pos)
		"harvest": _harvest_tile(tile_pos)

	if category == "seed":
		_plant_seed(tile_pos, tool_id)

# ---------------------------------------------------------------------------
# TileMap setup & rendering
# ---------------------------------------------------------------------------

func _setup_tilemap() -> void:
	if tilemap == null:
		return
	if tilemap.tile_set == null:
		tilemap.tile_set = _build_placeholder_tileset()
	while tilemap.get_layers_count() < 3:
		tilemap.add_layer(-1)


func _build_placeholder_tileset() -> TileSet:
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


func _render_all() -> void:
	## Repaint the whole farm from scratch: base layout then per-tile state.
	if tilemap == null:
		return

	tilemap.clear_layer(LAYER_CROPS)

	for y in range(MAP_H):
		for x in range(MAP_W):
			tilemap.set_cell(LAYER_GROUND, Vector2i(x, y), TILESET_SOURCE, TILE_GRASS)

	for y in range(PLOT_Y, PLOT_Y + PLOT_H):
		for x in range(PLOT_X, PLOT_X + PLOT_W):
			tilemap.set_cell(LAYER_GROUND, Vector2i(x, y), TILESET_SOURCE, TILE_SOIL_DRY)

	for key in _tile_data:
		_render_tile(_pos_from_key(key))


func _render_tile(tile_pos: Vector2i) -> void:
	var key = _key(tile_pos)
	if not _tile_data.has(key):
		# Nothing here — revert to plain soil/grass.
		var base = TILE_SOIL_DRY if _is_farmable(tile_pos) else TILE_GRASS
		tilemap.set_cell(LAYER_GROUND, tile_pos, TILESET_SOURCE, base)
		tilemap.erase_cell(LAYER_CROPS, tile_pos)
		return

	var data = _tile_data[key]
	var state = data.get("state", "")

	# Ground: watered today shows as watered soil, otherwise tilled soil.
	var watered_today := int(data.get("watered_day", -1)) == GameClock.days_elapsed
	var ground = TILE_SOIL_WATERED if watered_today else TILE_SOIL_TILLED
	tilemap.set_cell(LAYER_GROUND, tile_pos, TILESET_SOURCE, ground)

	# Crop layer.
	if state == "planted":
		tilemap.set_cell(LAYER_CROPS, tile_pos, TILESET_SOURCE, _crop_stage_tile(data))
	else:
		tilemap.erase_cell(LAYER_CROPS, tile_pos)


func _crop_stage_tile(data: Dictionary) -> Vector2i:
	var crop = ItemDB.get_crop(data.get("crop_id", ""))
	var growth_days: int = max(1, crop.get("growth_days", 1))
	var progress: int = int(data.get("progress", 0))
	if progress >= growth_days:
		return TILE_CROP_READY
	var ratio := float(progress) / float(growth_days)
	if ratio < 0.34:
		return TILE_CROP_YOUNG
	elif ratio < 0.67:
		return TILE_CROP_MID
	return TILE_CROP_MATURE

# ---------------------------------------------------------------------------
# Farming actions
# ---------------------------------------------------------------------------

func _is_farmable(tile_pos: Vector2i) -> bool:
	return tile_pos.x >= PLOT_X and tile_pos.x < PLOT_X + PLOT_W \
		and tile_pos.y >= PLOT_Y and tile_pos.y < PLOT_Y + PLOT_H


func _till_soil(tile_pos: Vector2i) -> void:
	if not _is_farmable(tile_pos):
		_notify("You can only till the farm plot")
		return
	var key = _key(tile_pos)
	if _tile_data.has(key):
		return   ## Already tilled / planted.
	_tile_data[key] = {
		"state": "tilled", "crop_id": "",
		"planted_day": -1, "watered_day": -1, "progress": 0, "stage": 0,
	}
	GameData.add_skill_xp("farming", 1)
	_render_tile(tile_pos)
	_notify("Tilled soil")


func _water_tile(tile_pos: Vector2i) -> void:
	var key = _key(tile_pos)
	if not _tile_data.has(key):
		return
	var data = _tile_data[key]
	if data.get("state", "") in ["tilled", "planted"]:
		data["watered_day"] = GameClock.days_elapsed
		GameData.add_skill_xp("farming", 1)
		_render_tile(tile_pos)


func _plant_seed(tile_pos: Vector2i, seed_id: String) -> void:
	var key = _key(tile_pos)
	if not _tile_data.has(key):
		_notify("Till the soil first")
		return
	var data = _tile_data[key]
	if data.get("state", "") != "tilled":
		return

	var crop = ItemDB.get_crop_for_seed(seed_id)
	if crop.is_empty():
		return

	var season_name = GameClock.get_season_name().to_lower()
	if not season_name in crop.get("seasons", []):
		_notify("%s can't grow in %s" % [crop.get("name", "That"), GameClock.get_season_name()])
		return

	# Consume one seed from the inventory.
	if player_instance and player_instance.inventory:
		if not player_instance.inventory.remove_item(seed_id, 1):
			_notify("Out of %s" % ItemDB.get_item(seed_id).get("name", seed_id))
			return

	data["state"]       = "planted"
	data["crop_id"]     = crop["id"]
	data["planted_day"] = GameClock.days_elapsed
	data["progress"]    = 0
	data["stage"]       = 0
	_render_tile(tile_pos)
	_notify("Planted %s" % crop.get("name", "crop"))


func _harvest_tile(tile_pos: Vector2i) -> void:
	var key = _key(tile_pos)
	if not _tile_data.has(key):
		return
	var data = _tile_data[key]
	if data.get("state", "") != "planted":
		return

	var crop = ItemDB.get_crop(data.get("crop_id", ""))
	if crop.is_empty():
		return

	if int(data.get("progress", 0)) < int(crop.get("growth_days", 999)):
		_notify("%s isn't ready yet" % crop.get("name", "It"))
		return

	var product_id = crop.get("product_id", "")
	if product_id != "" and player_instance and player_instance.inventory:
		player_instance.inventory.add_item(product_id, 1)
	GameData.add_skill_xp("farming", 5)
	_notify("Harvested %s" % crop.get("name", "crop"))

	if crop.get("regrows", false):
		var regrow_days = int(crop.get("regrow_days", crop.get("growth_days", 1)))
		data["progress"] = max(0, int(crop.get("growth_days", 1)) - regrow_days)
		data["stage"]    = 0
	else:
		_tile_data.erase(key)

	_render_tile(tile_pos)

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

func _notify(message: String) -> void:
	if GameManager.instance:
		GameManager.instance.show_notification(message)


func _key(tile_pos: Vector2i) -> String:
	return "%d,%d" % [tile_pos.x, tile_pos.y]


func _pos_from_key(key: String) -> Vector2i:
	var parts = key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))
