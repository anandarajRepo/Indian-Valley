extends WorldBase
## Town.gd — Viralpadi village hub.
##
## The social/economic counterpart to the farm: villagers to talk to,
## Kavitha's General Store, the Panchayat Hall offering baskets, and the town
## square where each season's festival is held. Reached through the road warp
## from the farm. Player spawning and HUD wiring are handled by WorldBase.

@onready var festival_node: Node2D = $Festival


func _world_ready() -> void:
	_setup_festival()


func _setup_festival() -> void:
	## Decorations and the offering stall only exist on festival days.
	if festival_node == null:
		return
	var festival := Calendar.festival_today()
	if festival.is_empty():
		festival_node.queue_free()
		festival_node = null
		return

	var c: Array = festival.get("banner_color", [0.95, 0.75, 0.2])
	var color := Color(c[0], c[1], c[2])
	for child in festival_node.get_children():
		if child is Polygon2D and child.name.begins_with("Bunting"):
			child.color = color
	var stall_sign := festival_node.get_node_or_null("StallSign") as Label
	if stall_sign:
		stall_sign.text = festival.get("name", "Festival")
	if GameManager.instance:
		GameManager.instance.show_notification("%s — %s" % [festival.get("name", ""), festival.get("description", "")])
