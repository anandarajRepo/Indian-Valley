extends CharacterBody2D
## Player.gd — Player controller.
##
## Handles:
##   - 4-directional movement (WASD / arrow keys)
##   - Animation state machine (idle / walk, 4 directions)
##   - Tool use (hoe, watering can, sickle, pickaxe, fishing rod)
##   - Facing direction for tool placement
##   - Interaction with world objects (chests, NPCs, signs)

signal tool_used(tool_id: String, tile_pos: Vector2i)
signal interacted(target: Node)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const MOVE_SPEED: float     = 80.0   ## pixels per second
const TILE_SIZE:  int       = 16     ## matches the 16×16 tilemap

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

enum Direction { DOWN = 0, UP = 1, LEFT = 2, RIGHT = 3 }

var facing: Direction = Direction.DOWN
var is_moving: bool   = false

## Reference to the Inventory node (set by Farm scene after instantiation)
var inventory: Node = null

# ---------------------------------------------------------------------------
# Nodes (resolved in _ready)
# ---------------------------------------------------------------------------

@onready var sprite:          AnimatedSprite2D = $AnimatedSprite2D
@onready var tool_area:       Area2D           = $ToolArea
@onready var interact_area:   Area2D           = $InteractArea
@onready var collision:       CollisionShape2D = $CollisionShape2D

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# The Inventory lives as a child node on the Player scene.
	inventory = get_node_or_null("Inventory")
	# Connect clock pause so player freezes during menus
	GameClock.sleep_triggered.connect(_on_sleep)


func _physics_process(delta: float) -> void:
	if GameClock.is_paused():
		velocity = Vector2.ZERO
		_update_animation()
		return

	_handle_movement(delta)
	_update_animation()
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if GameClock.is_paused():
		return

	if event.is_action_pressed("use_tool"):
		_use_tool()
	elif event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("sleep"):
		_try_sleep()

# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------

func _handle_movement(_delta: float) -> void:
	var dir = Vector2.ZERO

	if Input.is_action_pressed("move_up"):
		dir.y = -1
		facing = Direction.UP
	elif Input.is_action_pressed("move_down"):
		dir.y = 1
		facing = Direction.DOWN

	if Input.is_action_pressed("move_left"):
		dir.x = -1
		facing = Direction.LEFT
	elif Input.is_action_pressed("move_right"):
		dir.x = 1
		facing = Direction.RIGHT

	is_moving = dir != Vector2.ZERO
	velocity  = dir.normalized() * MOVE_SPEED

	# Reposition the tool area based on facing
	_update_tool_area()


func _update_tool_area() -> void:
	## Move the tool-hit Area2D one tile in front of the player
	if tool_area == null:
		return
	match facing:
		Direction.UP:    tool_area.position = Vector2(0, -TILE_SIZE)
		Direction.DOWN:  tool_area.position = Vector2(0,  TILE_SIZE)
		Direction.LEFT:  tool_area.position = Vector2(-TILE_SIZE, 0)
		Direction.RIGHT: tool_area.position = Vector2( TILE_SIZE, 0)

# ---------------------------------------------------------------------------
# Animation
# ---------------------------------------------------------------------------

func _update_animation() -> void:
	# No SpriteFrames assigned yet (Phase 0 has no art) — skip to avoid errors.
	if sprite == null or sprite.sprite_frames == null:
		return

	var dir_name: String
	match facing:
		Direction.UP:    dir_name = "up"
		Direction.DOWN:  dir_name = "down"
		Direction.LEFT:  dir_name = "left"
		Direction.RIGHT: dir_name = "right"

	var anim_prefix = "walk" if is_moving else "idle"
	var anim_name   = "%s_%s" % [anim_prefix, dir_name]

	if sprite.animation != anim_name:
		sprite.play(anim_name)

# ---------------------------------------------------------------------------
# Tool use
# ---------------------------------------------------------------------------

func _use_tool() -> void:
	if inventory == null:
		return

	var held_item = inventory.get_hotbar_item()
	if held_item.is_empty():
		return

	var item_data = ItemDB.get_item(held_item["item_id"])
	if item_data.is_empty():
		return

	var category = item_data.get("category", "")
	if category != "tool" and category != "seed":
		return

	# Check energy
	var energy_cost = item_data.get("energy_cost", 1)
	if not GameData.spend_energy(energy_cost):
		# TODO: show "too tired" popup
		return

	# Get the tile in front of the player
	var tile_pos = _get_facing_tile()
	emit_signal("tool_used", held_item["item_id"], tile_pos)

	# Play use animation (swing / water)
	_play_tool_animation(item_data.get("tool_type", ""))


func _get_facing_tile() -> Vector2i:
	## Returns the tilemap coordinates of the tile in front of the player.
	var world_pos: Vector2 = global_position
	match facing:
		Direction.UP:    world_pos.y -= TILE_SIZE
		Direction.DOWN:  world_pos.y += TILE_SIZE
		Direction.LEFT:  world_pos.x -= TILE_SIZE
		Direction.RIGHT: world_pos.x += TILE_SIZE
	# Convert to tile coordinates (integer division by tile size)
	return Vector2i(int(world_pos.x) / TILE_SIZE, int(world_pos.y) / TILE_SIZE)


func _play_tool_animation(tool_type: String) -> void:
	## TODO: hook into AnimatedSprite2D tool swing animations.
	## For Phase 0 we just print.
	print("[Player] Used tool: %s facing %s" % [tool_type, Direction.keys()[facing]])

# ---------------------------------------------------------------------------
# Interaction
# ---------------------------------------------------------------------------

func _interact() -> void:
	## Check for interactive objects in the interact area
	if interact_area == null:
		return
	var bodies = interact_area.get_overlapping_bodies()
	var areas  = interact_area.get_overlapping_areas()

	for body in bodies:
		if body.has_method("interact"):
			body.interact(self)
			emit_signal("interacted", body)
			return

	for area in areas:
		if area.get_parent().has_method("interact"):
			area.get_parent().interact(self)
			emit_signal("interacted", area.get_parent())
			return

# ---------------------------------------------------------------------------
# Sleep
# ---------------------------------------------------------------------------

func _try_sleep() -> void:
	## Player presses F near their bed — only allowed at home
	## For now we trigger sleep directly (bed detection comes later)
	GameClock._trigger_sleep()


func _on_sleep() -> void:
	velocity = Vector2.ZERO
	## Show sleep animation / fade — handled by Farm scene
	pass

# ---------------------------------------------------------------------------
# Public helpers
# ---------------------------------------------------------------------------

func get_facing_direction() -> Direction:
	return facing


func get_tile_position(tilemap: TileMap) -> Vector2i:
	return tilemap.local_to_map(tilemap.to_local(global_position))
