extends StaticBody2D
class_name Interactable
## Interactable.gd — a generic "press Interact here" object built in code.
##
## Used for procedurally placed things with no scene of their own (mine
## ladders, the old lift, the shrine, the notice board). `make()` builds the
## collision shape and a placeholder polygon; `on_interact` runs on Interact.

var on_interact: Callable = Callable()


static func make(pos: Vector2, size: Vector2, color: Color, action: Callable) -> Interactable:
	var node := Interactable.new()
	node.position = pos
	node.on_interact = action

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	node.add_child(shape)

	var body := Polygon2D.new()
	body.name = "Sprite"
	body.color = color
	var h := size / 2.0
	body.polygon = PackedVector2Array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)])
	node.add_child(body)
	return node


func interact(_player: Node) -> void:
	if on_interact.is_valid():
		on_interact.call()
