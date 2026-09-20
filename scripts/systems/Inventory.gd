extends Node
## Inventory.gd — Player inventory with hotbar.
##
## Inventory: 30 slots (6 rows × 5 cols)
## Hotbar:     5 slots (first row of inventory, always visible)
##
## Each slot is either:
##   null  — empty
##   { "item_id": String, "quantity": int }

signal inventory_changed()
signal hotbar_selection_changed(slot_index: int)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const HOTBAR_SIZE:    int = 5
const INVENTORY_SIZE: int = 30

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _slots: Array = []           ## Array of INVENTORY_SIZE dicts or nulls
var _hotbar_index: int = 0       ## Currently selected hotbar slot (0–4)

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_slots.resize(INVENTORY_SIZE)
	_slots.fill(null)
	## Give player starter tools
	_give_starter_items()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("hotbar_next"):
		set_hotbar_index((_hotbar_index + 1) % HOTBAR_SIZE)
	elif event.is_action_pressed("hotbar_prev"):
		set_hotbar_index((_hotbar_index - 1 + HOTBAR_SIZE) % HOTBAR_SIZE)
	else:
		## Number keys 1–5 for direct hotbar selection
		for i in range(1, HOTBAR_SIZE + 1):
			if event.is_action_pressed("ui_text_select_all") or \
			   (event is InputEventKey and event.pressed and event.keycode == KEY_0 + i):
				set_hotbar_index(i - 1)
				break


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func add_item(item_id: String, quantity: int = 1) -> bool:
	## Try to add quantity of item_id. Returns false if inventory is full.
	var item = ItemDB.get_item(item_id)
	if item.is_empty():
		push_error("Inventory: unknown item_id '%s'" % item_id)
		return false

	var stack_max = item.get("stack_max", 99)

	## First, try to stack into existing slots
	for i in range(INVENTORY_SIZE):
		if _slots[i] == null:
			continue
		if _slots[i]["item_id"] == item_id:
			var space = stack_max - _slots[i]["quantity"]
			if space > 0:
				var to_add = min(quantity, space)
				_slots[i]["quantity"] += to_add
				quantity -= to_add
				if quantity == 0:
					emit_signal("inventory_changed")
					return true

	## Then fill empty slots
	for i in range(INVENTORY_SIZE):
		if _slots[i] != null:
			continue
		if quantity == 0:
			break
		var to_add = min(quantity, stack_max)
		_slots[i] = {"item_id": item_id, "quantity": to_add}
		quantity -= to_add

	emit_signal("inventory_changed")
	return quantity == 0


func remove_item(item_id: String, quantity: int = 1) -> bool:
	## Remove quantity items. Returns false if not enough.
	if count_item(item_id) < quantity:
		return false
	var remaining = quantity
	for i in range(INVENTORY_SIZE):
		if _slots[i] == null or _slots[i]["item_id"] != item_id:
			continue
		var take = min(remaining, _slots[i]["quantity"])
		_slots[i]["quantity"] -= take
		remaining -= take
		if _slots[i]["quantity"] == 0:
			_slots[i] = null
		if remaining == 0:
			break
	emit_signal("inventory_changed")
	return true


func count_item(item_id: String) -> int:
	var total = 0
	for slot in _slots:
		if slot != null and slot["item_id"] == item_id:
			total += slot["quantity"]
	return total


func get_slot(index: int) -> Variant:
	## Returns null or { item_id, quantity }
	if index < 0 or index >= INVENTORY_SIZE:
		return null
	return _slots[index]


func get_hotbar_item() -> Dictionary:
	## Returns the item dict in the currently selected hotbar slot, or {}.
	var slot = _slots[_hotbar_index]
	return slot if slot != null else {}


func set_hotbar_index(index: int) -> void:
	_hotbar_index = clamp(index, 0, HOTBAR_SIZE - 1)
	emit_signal("hotbar_selection_changed", _hotbar_index)


func get_hotbar_index() -> int:
	return _hotbar_index


func get_all_hotbar_slots() -> Array:
	return _slots.slice(0, HOTBAR_SIZE)


func is_full() -> bool:
	for slot in _slots:
		if slot == null:
			return false
	return true


# ---------------------------------------------------------------------------
# Starter items
# ---------------------------------------------------------------------------

func _give_starter_items() -> void:
	add_item("hoe")
	add_item("watering_can")
	add_item("sickle")
	add_item("paddy_seed", 15)
	add_item("chilli_seed", 10)


# ---------------------------------------------------------------------------
# Serialisation
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"slots":         _slots,
		"hotbar_index":  _hotbar_index,
	}


func from_dict(d: Dictionary) -> void:
	var saved = d.get("slots", [])
	_slots.fill(null)
	for i in range(min(saved.size(), INVENTORY_SIZE)):
		_slots[i] = saved[i]
	_hotbar_index = d.get("hotbar_index", 0)
	emit_signal("inventory_changed")
	emit_signal("hotbar_selection_changed", _hotbar_index)
