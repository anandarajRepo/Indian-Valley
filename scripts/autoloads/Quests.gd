extends Node
## Quests.gd — Autoload for villager requests pinned to the town notice board.
##
## Most mornings (when no request is open) a villager asks for something they
## like that can be found this season — a few crops, a forage find, a fish or
## some ore once you've been down the mines. Deliver it at the notice board
## before the deadline for gold and a big friendship boost.

signal request_changed()

const POST_CHANCE:   float = 0.6
const DAYS_TO_DO:    int   = 3     ## Posted today → due at the end of day 3
const REWARD_MULT:   int   = 3     ## Gold = sell price × quantity × this
const REWARD_BONUS:  int   = 50
const FRIENDSHIP:    int   = 150

## The open request, or {} when the board is empty:
## { "npc_id", "item_id", "quantity", "reward", "due_day" (days_elapsed) }
var active: Dictionary = {}
## The last request that expired unfinished (shown once on the board).
var last_expired: Dictionary = {}

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	GameClock.day_started.connect(_on_day_started)


func _on_day_started(_day: int, _season) -> void:
	if not active.is_empty() and GameClock.days_elapsed > int(active.get("due_day", 0)):
		last_expired = active
		active = {}
	if active.is_empty() and _rng.randf() < POST_CHANCE:
		post_new()
	emit_signal("request_changed")

# ---------------------------------------------------------------------------
# Posting
# ---------------------------------------------------------------------------

func post_new() -> bool:
	## Roll a new request from a random villager. Returns false if nobody
	## has a wish that can be met this season.
	var npcs: Array = Relationships.get_all_npcs().duplicate()
	npcs.shuffle()
	for npc in npcs:
		var wishes: Array = []
		for item_id in npc.get("loves", []) + npc.get("likes", []):
			if is_obtainable(item_id):
				wishes.append(item_id)
		if wishes.is_empty():
			continue
		var item_id: String = wishes[_rng.randi() % wishes.size()]
		var item := ItemDB.get_item(item_id)
		var qty := _rng.randi_range(3, 5) if item.get("category", "") == "crop" else _rng.randi_range(1, 2)
		active = {
			"npc_id":   npc["id"],
			"item_id":  item_id,
			"quantity": qty,
			"reward":   int(item.get("sell_price", 10)) * qty * REWARD_MULT + REWARD_BONUS,
			"due_day":  GameClock.days_elapsed + DAYS_TO_DO - 1,
		}
		return true
	return false


func is_obtainable(item_id: String) -> bool:
	## Can the player reasonably get this item right now?
	var item := ItemDB.get_item(item_id)
	var season := GameClock.season_key()
	match item.get("category", ""):
		"crop":
			for crop in ItemDB.get_crops_for_season(GameClock.current_season):
				if crop.get("product_id", "") == item_id and int(crop.get("growth_days", 99)) <= 10:
					return true
			return false
		"forage":
			return season in item.get("seasons", [])
		"fish":
			return season in item.get("seasons", []) and item.get("weather", "") == "" \
				and int(item.get("difficulty", 1)) <= 3
		"mineral":
			var gm = get_tree().get_first_node_in_group("game")
			var deepest: int = int(gm.mine_state.get("deepest", 0)) if gm else 0
			return item_id in ["stone", "copper_ore"] and deepest >= 1
	return false

# ---------------------------------------------------------------------------
# Queries / delivery
# ---------------------------------------------------------------------------

func has_active() -> bool:
	return not active.is_empty()


func days_left() -> int:
	return int(active.get("due_day", 0)) - GameClock.days_elapsed + 1


func describe() -> String:
	if active.is_empty():
		return ""
	var item_name: String = ItemDB.get_item(active["item_id"]).get("name", active["item_id"])
	return "%s would like %d × %s. Reward: ₹%d. (%d day%s left)" % [
		Relationships.get_name_of(active["npc_id"]), int(active["quantity"]), item_name,
		int(active["reward"]), days_left(), "" if days_left() == 1 else "s"]


func can_deliver(inventory: Node) -> bool:
	return not active.is_empty() and inventory != null \
		and inventory.count_item(active["item_id"]) >= int(active["quantity"])


func deliver(inventory: Node) -> Dictionary:
	## Hand over the requested items. Returns { "ok", "lines" }.
	if not can_deliver(inventory):
		return {"ok": false, "lines": ["You don't have everything yet."]}
	inventory.remove_item(active["item_id"], int(active["quantity"]))
	var npc_id: String = active["npc_id"]
	var reward := int(active["reward"])
	GameData.add_gold(reward)
	Relationships.add_points(npc_id, FRIENDSHIP)
	Relationships.met[npc_id] = true
	GameData.record_stat("requests_completed")
	active = {}
	emit_signal("request_changed")
	return {"ok": true, "lines": [
		"%s: \"You're a lifesaver! Thank you so much.\"" % Relationships.get_name_of(npc_id),
		"(You received ₹%d. %s's friendship rose.)" % [reward, Relationships.get_name_of(npc_id)]]}

# ---------------------------------------------------------------------------
# Lifecycle / serialisation
# ---------------------------------------------------------------------------

func reset_to_new_game() -> void:
	active = {}
	last_expired = {}


func to_dict() -> Dictionary:
	return {"active": active, "last_expired": last_expired}


func from_dict(d: Dictionary) -> void:
	active = d.get("active", {}).duplicate()
	for key in ["quantity", "reward", "due_day"]:
		if active.has(key):
			active[key] = int(active[key])   # JSON numbers load as floats
	last_expired = d.get("last_expired", {})
