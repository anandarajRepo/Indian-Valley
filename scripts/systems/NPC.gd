extends StaticBody2D
class_name NPC
## NPC.gd — a talkable villager.
##
## The player faces them and presses Interact; Player._interact() calls
## interact(). Villagers with an `npc_id` pull their name, seasonal dialogue,
## gift tastes and friendship from the Relationships autoload:
##   - chatting once a day raises friendship
##   - holding a giftable item offers a "Give" choice (one gift per day)
##   - a shopkeeper (opens_shop = true) also offers to open the store
## Without an `npc_id`, the exported `dialogue` text is used as-is.

@export var npc_id: String = ""
@export var npc_name: String = "Villager"
@export_multiline var dialogue: String = "Hello, traveller."
@export var opens_shop: bool = false


func _ready() -> void:
	if npc_id != "" and not Relationships.get_npc(npc_id).is_empty():
		npc_name = Relationships.get_name_of(npc_id)


func interact(_player: Node) -> void:
	var gm = GameManager.instance
	if gm == null:
		return

	var held := gm.get_held_item_id()
	var can_gift := npc_id != "" and held != "" and Relationships.is_giftable(held) \
		and Relationships.can_gift(npc_id)

	var options: Array = ["Chat"]
	var actions: Array = [_chat]
	if can_gift:
		options.append("Give %s" % ItemDB.get_item(held).get("name", held))
		actions.append(func(): _give(held))
	if opens_shop:
		options.append("Browse the store")
		actions.append(func(): gm.open_shop())

	if options.size() == 1:
		_chat()
		return
	gm.show_choice(npc_name, "What would you like to do?", options,
		func(i: int): actions[i].call())


func _chat() -> void:
	var gm = GameManager.instance
	if npc_id == "":
		gm.show_dialogue(npc_name, _dialogue_lines(), _after_chat())
		return

	var talk := Relationships.talk(npc_id)
	var lines: Array = talk["lines"]
	var gift: Dictionary = talk["gift"]
	if not gift.is_empty():
		lines.append(gift.get("line", "Here, take this."))
	var on_done := _after_chat()
	if not gift.is_empty():
		var after := on_done
		on_done = func():
			var item_id: String = gift.get("item_id", "")
			if gm.give_item(item_id, 1):
				gm.show_notification("Received %s" % ItemDB.get_item(item_id).get("name", item_id))
			if after.is_valid():
				after.call()
	gm.show_dialogue(npc_name, lines, on_done)


func _after_chat() -> Callable:
	## Shopkeepers without a menu choice (legacy data) open the store after talking.
	if opens_shop and npc_id == "":
		return func(): GameManager.instance.open_shop()
	return Callable()


func _give(item_id: String) -> void:
	var gm = GameManager.instance
	var inv = gm.get_active_inventory()
	if inv == null or not inv.remove_item(item_id, 1):
		return
	var result := Relationships.give_gift(npc_id, item_id)
	gm.show_dialogue(npc_name, result["lines"])


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
