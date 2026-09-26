extends Node2D
class_name WorldBase
## WorldBase.gd — shared behaviour for playable world scenes (Farm, Town, Trail).
##
## Handles the things every world needs:
##   - spawning the player at the correct marker (based on where they came from)
##   - forwarding the player's tool-use signal to a subclass hook
##   - casting the fishing rod into any water the subclass reports
##   - refreshing the persistent HUD once the player exists
##
## Subclasses override `_world_ready()` for their own setup and, if they support
## farming, `_on_tool_used()`. Worlds with water override `_water_location()`.

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player/Player.tscn")

var player_instance: CharacterBody2D = null


func _ready() -> void:
	add_to_group("world")
	_spawn_player()
	if GameManager.instance:
		GameManager.instance.refresh_hud()
	_world_ready()


func _spawn_player() -> void:
	player_instance = PLAYER_SCENE.instantiate()
	# Place the player before it enters the tree so it never overlaps a warp
	# (or anything else) at the origin on its first physics frame.
	player_instance.position = _get_spawn_position()
	add_child(player_instance)
	player_instance.global_position = _get_spawn_position()
	if player_instance.has_signal("tool_used"):
		player_instance.tool_used.connect(_on_player_tool_used)


func _get_spawn_position() -> Vector2:
	var target := "default"
	if GameManager.instance:
		target = GameManager.instance.spawn_target

	var spawns := get_node_or_null("Spawns")
	if spawns:
		var marker = spawns.get_node_or_null(target)
		if marker:
			return marker.global_position
		var default_marker = spawns.get_node_or_null("default")
		if default_marker:
			return default_marker.global_position

	var legacy = get_node_or_null("PlayerSpawn")
	if legacy:
		return legacy.global_position

	return Vector2(96, 88)

func _on_player_tool_used(tool_id: String, tile_pos: Vector2i) -> void:
	## Fishing works the same everywhere; everything else is world-specific.
	if ItemDB.get_item(tool_id).get("tool_type", "") == "fish":
		var location := _water_location(tile_pos)
		if location == "":
			if GameManager.instance:
				GameManager.instance.show_notification("Face the water to cast your line")
		elif GameManager.instance:
			GameManager.instance.start_fishing(location)
		return
	_on_tool_used(tool_id, tile_pos)

# ---------------------------------------------------------------------------
# Virtual hooks (override in subclasses)
# ---------------------------------------------------------------------------

func _world_ready() -> void:
	pass


func _on_tool_used(_tool_id: String, _tile_pos: Vector2i) -> void:
	pass


func _water_location(_tile_pos: Vector2i) -> String:
	## Return the fishing location id ("pond", "river") for a water tile, or "".
	return ""
