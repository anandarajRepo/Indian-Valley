extends WorldBase
## GhatsTrail.gd — the forest trail west of the farm.
##
## Seasonal forageables appear here every morning (rolled by the GameManager),
## and the river along the west edge is the valley's best fishing spot.

const LOCATION: String = "trail"

## River tiles (tile coords) — cast the fishing rod into these.
const RIVER: Rect2i = Rect2i(2, 0, 3, 15)

const ForageSpotScript = preload("res://scripts/systems/ForageSpot.gd")


func _world_ready() -> void:
	_spawn_forage()


func _spawn_forage() -> void:
	if GameManager.instance == null:
		return
	for spot in GameManager.instance.get_forage_spots(LOCATION):
		var node = ForageSpotScript.new()
		node.setup(LOCATION, Vector2i(int(spot["x"]), int(spot["y"])), spot["item_id"])
		add_child(node)


func _water_location(tile_pos: Vector2i) -> String:
	return "river" if RIVER.has_point(tile_pos) else ""
