extends StaticBody2D
## ShippingChest.gd — The wooden chest on the farm edge.
##
## Player walks up and presses Interact to deposit items.
## Items sell overnight; gold is credited in GameData.process_shipping().
## Only crops, minerals, and forageable items can be shipped — not tools/food.

signal chest_opened()
signal item_deposited(item_id: String, quantity: int)

const SHIPPABLE_CATEGORIES: Array = ["crop", "mineral", "forage", "fish"]

## Reference set by Farm.gd
var player_inventory: Node = null


func _ready() -> void:
	## Connect to the area for interaction detection
	pass


func interact(player: Node) -> void:
	## Called by Player._interact() when the player presses Interact near this chest.
	if player_inventory == null:
		## Try to find inventory on the player
		player_inventory = player.get_node_or_null("Inventory")
	if player_inventory == null:
		push_warning("ShippingChest: no player inventory found")
		return

	emit_signal("chest_opened")
	_ship_all(player_inventory)


func _ship_all(inventory: Node) -> void:
	## Deposits all shippable items from the player's inventory into the shipping chest.
	var shipped_count = 0
	for i in range(inventory.INVENTORY_SIZE):
		var slot = inventory.get_slot(i)
		if slot == null:
			continue
		var item = ItemDB.get_item(slot["item_id"])
		if item.is_empty():
			continue
		if not item.get("category", "") in SHIPPABLE_CATEGORIES:
			continue

		var qty = slot["quantity"]
		GameData.add_to_shipping(slot["item_id"], qty)
		inventory.remove_item(slot["item_id"], qty)
		emit_signal("item_deposited", slot["item_id"], qty)
		shipped_count += qty

	if shipped_count > 0:
		print("[ShippingChest] Deposited %d items for overnight sale." % shipped_count)
	else:
		print("[ShippingChest] Nothing to ship.")


func ship_item(item_id: String, quantity: int) -> void:
	## Call this to deposit a specific item programmatically.
	GameData.add_to_shipping(item_id, quantity)
	emit_signal("item_deposited", item_id, quantity)
