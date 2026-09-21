extends Area2D
class_name Warp
## Warp.gd — a doorway/edge trigger that moves the player to another world scene.
##
## Drop one into a world scene, give it a CollisionShape2D, and set:
##   target_scene — the .tscn path to load (Farm or Town)
##   target_spawn — the spawn marker name to place the player at on arrival
##
## Fires once when the player body enters, then hands off to the GameManager.

@export_file("*.tscn") var target_scene: String = ""
@export var target_spawn: String = "default"

var _armed: bool = true


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if not _armed:
		return
	if not body.is_in_group("player"):
		return
	if target_scene.is_empty():
		push_warning("Warp: no target_scene set on %s" % name)
		return
	_armed = false
	if GameManager.instance:
		GameManager.instance.goto_world(target_scene, target_spawn)
