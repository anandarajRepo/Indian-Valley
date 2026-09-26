extends StaticBody2D
class_name ForageSpot
## ForageSpot.gd — a seasonal forageable lying on the ground.
##
## Spawned by the world each time it loads, from GameManager.forage_data (which
## is re-rolled every morning). Interact to pick it up; the manager adds it to
## the inventory, awards foraging XP and removes it from today's spawns.

var location: String = ""
var tile: Vector2i = Vector2i.ZERO
var item_id: String = ""


func setup(p_location: String, p_tile: Vector2i, p_item_id: String) -> void:
	location = p_location
	tile = p_tile
	item_id = p_item_id
	position = Vector2(tile * 16) + Vector2(8, 8)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10, 10)
	shape.shape = rect
	add_child(shape)

	# Placeholder art: a small coloured diamond, hue derived from the item id.
	var gem := Polygon2D.new()
	gem.color = Color.from_hsv(float(absi(item_id.hash()) % 360) / 360.0, 0.55, 0.95)
	gem.polygon = PackedVector2Array([Vector2(0, -6), Vector2(5, 0), Vector2(0, 6), Vector2(-5, 0)])
	add_child(gem)


func interact(_player: Node) -> void:
	if GameManager.instance and GameManager.instance.pick_forage(location, tile):
		queue_free()
