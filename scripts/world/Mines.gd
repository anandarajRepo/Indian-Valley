extends WorldBase
class_name Mines
## Mines.gd — Kanagiri Mines, east of the town square.
##
## One scene serves every floor. GameManager.mine_state["floor"] says which:
##   Floor 0  — the entrance: the road back to town, a ladder down, and the
##              old lift (unlocked every 5 floors you reach).
##   Floor 1+ — a cave full of rocks. Break them with the pickaxe for stone,
##              ore and gems (richer the deeper you go). One of them hides the
##              ladder down; breaking the last rock always reveals it.
##   Floor 20 — the bottom: an ancient shrine keeps the Tank King's Seal.
##
## Rocks are rolled fresh every time a floor is entered, like the real mines
## of old: nothing on a floor is saved except how deep you've been.

const MAX_FLOOR: int = 20
const LIFT_STEP: int = 5

## Where rocks can appear (tile coords).
const ROCK_AREA: Rect2i = Rect2i(2, 2, 16, 11)
const ROCK_MIN: int = 14
const ROCK_MAX: int = 22
## Chance each broken rock reveals the ladder (the last rock always does).
const LADDER_CHANCE: float = 0.12

## Keep these tiles clear: the arrival point and the exit ladder.
const CLEAR_TILES: Array = [Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3)]

## Rock kinds: hit points, what they drop and their placeholder colour.
const ROCKS: Dictionary = {
	"stone":    {"hp": 1, "drop": "stone",         "qty": [1, 2], "xp": 1, "color": Color(0.45, 0.42, 0.40)},
	"copper":   {"hp": 2, "drop": "copper_ore",    "qty": [1, 2], "xp": 3, "color": Color(0.72, 0.45, 0.25)},
	"iron":     {"hp": 3, "drop": "iron_ore",      "qty": [1, 2], "xp": 5, "color": Color(0.62, 0.58, 0.55)},
	"gold":     {"hp": 4, "drop": "gold_ore",      "qty": [1, 2], "xp": 8, "color": Color(0.90, 0.75, 0.25)},
	"quartz":   {"hp": 2, "drop": "quartz",        "qty": [1, 1], "xp": 4, "color": Color(0.92, 0.92, 0.95)},
	"amethyst": {"hp": 3, "drop": "amethyst",      "qty": [1, 1], "xp": 7, "color": Color(0.60, 0.35, 0.80)},
	"ruby":     {"hp": 4, "drop": "kanagiri_ruby", "qty": [1, 1], "xp": 10, "color": Color(0.85, 0.15, 0.25)},
}

const SEAL_LINES: Array = [
	"Carved into the rock is a shrine, older than anything in the valley.",
	"Behind a veil of roots rests a bronze seal stamped with a water tank and a crown.",
	"This must have belonged to the forgotten king who built Viralpadi's tanks.",
	"(You found the Tank King's Seal! Anjali and Paati would love to see it.)",
]

var floor_num: int = 0
var ladder: Node2D = null

## "x,y" → { "type": String, "hp": int, "node": Node2D }
var rocks: Dictionary = {}

@onready var ground: Polygon2D = $Ground


func _world_ready() -> void:
	var gm = GameManager.instance
	if gm == null:
		return
	if gm.spawn_target == "from_town":
		gm.mine_state["floor"] = 0
	floor_num = int(gm.mine_state.get("floor", 0))

	var depth := float(floor_num) / MAX_FLOOR
	ground.color = Color(0.30, 0.26, 0.22).lerp(Color(0.24, 0.12, 0.10), depth)

	if floor_num == 0:
		_build_entrance()
	else:
		var to_town := get_node_or_null("ToTown")
		if to_town:
			to_town.queue_free()
		_build_floor()

	gm.location_note = "Kanagiri Mines" if floor_num == 0 else "Mines · Floor %d" % floor_num
	gm.refresh_hud()
	if floor_num > 0:
		gm.show_notification("Kanagiri Mines — Floor %d" % floor_num)
	elif not _player_has_pickaxe():
		gm.show_notification("You'll need a pickaxe. Selvam the blacksmith may lend you one.")

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _build_entrance() -> void:
	var down := Interactable.make(Vector2(248, 120), Vector2(16, 16), Color(0.15, 0.10, 0.06),
		func(): descend())
	down.name = "LadderDown"
	add_child(down)
	ladder = down
	var lift := Interactable.make(Vector2(160, 40), Vector2(24, 20), Color(0.5, 0.45, 0.3),
		func(): use_lift())
	lift.name = "Lift"
	add_child(lift)


func _build_floor() -> void:
	var up := Interactable.make(Vector2(40, 40), Vector2(14, 14), Color(0.55, 0.40, 0.22),
		func(): GameManager.instance.enter_mine_floor(0))
	up.name = "LadderUp"
	add_child(up)

	if floor_num % LIFT_STEP == 0:
		var lift := Interactable.make(Vector2(288, 40), Vector2(24, 20), Color(0.5, 0.45, 0.3),
			func(): use_lift())
		lift.name = "Lift"
		add_child(lift)

	if floor_num >= MAX_FLOOR:
		var shrine := Interactable.make(Vector2(168, 120), Vector2(24, 24), Color(0.75, 0.6, 0.3),
			func(): visit_shrine())
		shrine.name = "Shrine"
		add_child(shrine)

	_generate_rocks()


func _generate_rocks() -> void:
	var table := rock_table(floor_num)
	var count := randi_range(ROCK_MIN, ROCK_MAX)
	var tries := 0
	while rocks.size() < count and tries < 300:
		tries += 1
		var tile := Vector2i(ROCK_AREA.position.x + randi() % ROCK_AREA.size.x,
			ROCK_AREA.position.y + randi() % ROCK_AREA.size.y)
		if tile in CLEAR_TILES or rocks.has(_key(tile)):
			continue
		if floor_num >= MAX_FLOOR and absi(tile.x - 10) <= 1 and absi(tile.y - 7) <= 1:
			continue   # leave room around the shrine
		add_rock(tile, _roll(table))


func add_rock(tile: Vector2i, type: String) -> void:
	var info: Dictionary = ROCKS[type]
	var node := StaticBody2D.new()
	node.position = Vector2(tile * 16) + Vector2(8, 8)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(14, 14)
	shape.shape = rect
	node.add_child(shape)
	var body := Polygon2D.new()
	body.color = info["color"]
	body.polygon = PackedVector2Array([Vector2(-6, -4), Vector2(-2, -7), Vector2(5, -6),
		Vector2(7, 1), Vector2(4, 7), Vector2(-5, 6), Vector2(-7, 1)])
	node.add_child(body)
	add_child(node)
	rocks[_key(tile)] = {"type": type, "hp": int(info["hp"]), "node": node}


static func rock_table(f: int) -> Array:
	## [type, weight] pairs — ore and gems get richer with depth.
	if f <= 5:
		return [["stone", 70], ["copper", 25], ["quartz", 5 if f >= 3 else 0]]
	if f <= 10:
		return [["stone", 55], ["copper", 20], ["iron", 20], ["quartz", 5]]
	if f <= 15:
		return [["stone", 45], ["iron", 25], ["gold", 15], ["quartz", 8], ["amethyst", 7]]
	return [["stone", 40], ["iron", 15], ["gold", 25], ["amethyst", 12], ["ruby", 8]]


func _roll(table: Array) -> String:
	var total := 0
	for entry in table:
		total += int(entry[1])
	var r := randi() % maxi(1, total)
	for entry in table:
		r -= int(entry[1])
		if r < 0:
			return entry[0]
	return "stone"

# ---------------------------------------------------------------------------
# Mining
# ---------------------------------------------------------------------------

func _on_tool_used(tool_id: String, tile_pos: Vector2i) -> void:
	if ItemDB.get_item(tool_id).get("tool_type", "") == "mine":
		hit_rock(tile_pos)


func hit_rock(tile: Vector2i) -> bool:
	## Swing the pickaxe at `tile`. Returns true if a rock broke.
	var key := _key(tile)
	if not rocks.has(key):
		return false
	var rock: Dictionary = rocks[key]
	rock["hp"] = int(rock["hp"]) - (1 + GameData.get_tool_level("pickaxe"))
	if rock["hp"] > 0:
		var body := rock["node"].get_child(1) as Polygon2D
		if body:
			body.color = body.color.darkened(0.2)
		return false

	var info: Dictionary = ROCKS[rock["type"]]
	var qty := randi_range(int(info["qty"][0]), int(info["qty"][1]))
	var gm = GameManager.instance
	if gm:
		if gm.give_item(info["drop"], qty):
			gm.show_notification("+%d %s" % [qty, ItemDB.get_item(info["drop"]).get("name", info["drop"])])
		else:
			gm.show_notification("Inventory full")
	GameData.add_skill_xp("mining", int(info["xp"]))
	GameData.record_stat("rocks_broken")
	rock["node"].queue_free()
	rocks.erase(key)

	if ladder == null and floor_num < MAX_FLOOR and (rocks.is_empty() or randf() < LADDER_CHANCE):
		reveal_ladder(tile)
	return true


func reveal_ladder(tile: Vector2i) -> void:
	ladder = Interactable.make(Vector2(tile * 16) + Vector2(8, 8), Vector2(12, 12),
		Color(0.12, 0.08, 0.05), func(): descend())
	ladder.name = "LadderDown"
	add_child(ladder)
	if GameManager.instance:
		GameManager.instance.show_notification("You found a ladder leading down!")

# ---------------------------------------------------------------------------
# Travel
# ---------------------------------------------------------------------------

func descend() -> void:
	if GameManager.instance:
		GameManager.instance.enter_mine_floor(floor_num + 1)


func use_lift() -> void:
	var gm = GameManager.instance
	if gm == null:
		return
	var stops: Array = gm.lift_floors()
	if floor_num != 0:
		stops.push_front(0)
	stops.erase(floor_num)
	if stops.is_empty():
		gm.show_dialogue("Old lift", ["The old mine lift creaks but won't move.",
			"(Reach floor %d and the lift will remember it.)" % LIFT_STEP])
		return
	var options: Array = []
	for f in stops:
		options.append("Entrance" if f == 0 else "Floor %d" % f)
	options.append("Stay here")
	gm.show_choice("Old lift", "Where to?", options, func(i: int):
		if i < stops.size():
			gm.enter_mine_floor(stops[i]))


func visit_shrine() -> void:
	var gm = GameManager.instance
	if gm == null:
		return
	if gm.mine_state.get("seal_found", false):
		gm.show_dialogue("Ancient shrine", ["The shrine is quiet. Water drips somewhere far below."])
		return
	if not gm.give_item("tank_kings_seal", 1):
		gm.show_dialogue("Ancient shrine", ["Something glints behind the roots, but your bag is full."])
		return
	gm.mine_state["seal_found"] = true
	GameData.add_skill_xp("mining", 25)
	gm.show_dialogue("Ancient shrine", SEAL_LINES)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _player_has_pickaxe() -> bool:
	var inv = GameManager.instance.get_active_inventory() if GameManager.instance else null
	return inv != null and inv.count_item("pickaxe") > 0


func _key(tile: Vector2i) -> String:
	return "%d,%d" % [tile.x, tile.y]
