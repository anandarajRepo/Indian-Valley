extends StaticBody2D
class_name NPC
## NPC.gd — a talkable villager.
##
## The player faces them and presses Interact; Player._interact() calls
## interact(), which plays out the dialogue lines through the Popup layer.
## A shopkeeper (opens_shop = true) opens the store when the dialogue ends.

@export var npc_name: String = "Villager"
@export_multiline var dialogue: String = "Hello, traveller."
@export var opens_shop: bool = false


func interact(_player: Node) -> void:
	var lines := _dialogue_lines()

	if opens_shop:
		var on_done := func():
			if GameManager.instance:
				GameManager.instance.open_shop()
		if GameManager.instance:
			GameManager.instance.show_dialogue(npc_name, lines, on_done)
	else:
		if GameManager.instance:
			GameManager.instance.show_dialogue(npc_name, lines)


func _dialogue_lines() -> Array:
	## Each non-empty line of the exported text becomes one dialogue page.
	var lines: Array = []
	for raw in dialogue.split("\n"):
		var line := raw.strip_edges()
		if line != "":
			lines.append(line)
	if lines.is_empty():
		lines.append("...")
	return lines
