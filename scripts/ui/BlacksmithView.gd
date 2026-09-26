extends Control
## BlacksmithView.gd — Selvam's forge, shown inside the Popup.
##
## Lists each upgradable tool with its current level and the ore + rupees the
## next level costs. "Upgrade" hands the work to GameManager.upgrade_tool().

signal close_requested()

var _list: VBoxContainer = null
var _gold: Label = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := UIKit.panel(Vector2(680, 390), Vector2(300, 150))
	add_child(panel)
	var box := UIKit.vbox(panel, 10)
	box.add_child(UIKit.title("Selvam's Forge", 20))
	box.add_child(UIKit.label("Upgraded tools reach further and cost less energy.", 12, UIKit.COL_MUTED))
	_gold = UIKit.label("", 14)
	box.add_child(_gold)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	box.add_child(_list)

	var close_btn := UIKit.button("Close  (Esc)")
	close_btn.pressed.connect(func(): emit_signal("close_requested"))
	box.add_child(close_btn)
	_rebuild()


func _rebuild() -> void:
	_gold.text = "Your gold: ₹%d" % GameData.gold
	for child in _list.get_children():
		child.queue_free()
	for tool_id in GameData.UPGRADABLE_TOOLS:
		_list.add_child(_build_row(tool_id))


func _build_row(tool_id: String) -> Control:
	var gm = GameManager.instance
	var inv = gm.get_active_inventory() if gm else null
	var cost := GameData.next_tool_upgrade(tool_id)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.slot_style(cost.is_empty()))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	info.add_child(UIKit.label(GameData.tool_display_name(tool_id), 15, UIKit.COL_ACCENT))

	var detail := ""
	var can_upgrade := false
	if cost.is_empty():
		detail = "Fully upgraded."
	elif inv == null or inv.count_item(tool_id) == 0:
		detail = "Bring your %s to upgrade it." % ItemDB.get_item(tool_id).get("name", tool_id)
	else:
		var ore_name: String = ItemDB.get_item(cost["ore"]).get("name", cost["ore"])
		var have: int = inv.count_item(cost["ore"])
		detail = "Next: %s — %d %s (you have %d) + ₹%d" % [cost["name"], cost["ore_qty"], ore_name, have, cost["gold"]]
		can_upgrade = have >= int(cost["ore_qty"]) and GameData.gold >= int(cost["gold"])
	info.add_child(UIKit.label(detail, 12))

	var btn := UIKit.button("Upgrade")
	btn.custom_minimum_size = Vector2(110, 34)
	btn.disabled = not can_upgrade
	btn.pressed.connect(func():
		if gm:
			gm.show_notification(gm.upgrade_tool(tool_id)["message"])
		_rebuild()
	)
	row.add_child(btn)
	return card
