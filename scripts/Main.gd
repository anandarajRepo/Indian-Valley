extends Node
## Main.gd — Root scene manager
## Handles scene transitions (Farm ↔ Town ↔ Mines etc.)

const FARM_SCENE = "res://scenes/World/Farm.tscn"

@onready var current_scene_node: Node = $CurrentScene


func _ready() -> void:
	# Load the starting scene (the Farm)
	call_deferred("_load_scene", FARM_SCENE)


func _load_scene(path: String) -> void:
	# Clear current scene
	for child in current_scene_node.get_children():
		child.queue_free()

	var packed: PackedScene = load(path)
	if packed == null:
		push_error("Main: failed to load scene: %s" % path)
		return

	var scene_instance = packed.instantiate()
	current_scene_node.add_child(scene_instance)


func goto_scene(path: String) -> void:
	## Call this from anywhere to transition to a new scene.
	## Example: Main.goto_scene("res://scenes/World/Town.tscn")
	call_deferred("_load_scene", path)
