extends Control
## HallView.gd — the Panchayat Hall offering board, shown inside the Popup.
##
## Lists each bundle with its required items and progress. "Offer" moves every
## matching item the player carries into that bundle (GameManager does the
## bookkeeping and hands out rewards).

signal close_requested()

var _list: VBoxContainer = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := UIKit.panel(Vector2(760, 620), Vector2(260, 50))
	add_child(panel)
	var box := UIKit.vbox(panel, 8)

	box.add_child(UIKit.title("Panchayat Hall — Offering Baskets", 20))
	var gm = GameManager.instance
	var restored: bool = gm != null and gm.hall_state.get("restored", false)
	var subtitle := "The Hall is restored. The valley thanks you." if restored \
		else "Fill every basket to call the Vanam Thay home."
	box.add_child(UIKit.label(subtitle, 12, UIKit.COL_MUTED))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(720, 480)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	var close_btn := UIKit.button("Close  (Esc)")
	close_btn.pressed.connect(func(): emit_signal("close_requested"))
	box.add_child(close_btn)
	_rebuild()


func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()
	for bundle in ItemDB.get_bundles():
		_list.add_child(_build_bundle(bundle))


func _build_bundle(bundle: Dictionary) -> Control:
	var gm = GameManager.instance
	var id: String = bundle["id"]
	var complete: bool = gm != null and gm.is_bundle_complete(id)
	var inv = gm.get_active_inventory() if gm else null

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.slot_style(complete))
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
	info.add_child(UIKit.label(bundle.get("name", id) + ("  (complete)" if complete else ""), 15,
		UIKit.COL_GOOD if complete else UIKit.COL_ACCENT))
	info.add_child(UIKit.label(bundle.get("hint", ""), 11, UIKit.COL_MUTED))

	var can_offer := false
	var parts: Array = []
	for req in bundle.get("items", []):
		var item_id: String = req["item_id"]
		var need := int(req["quantity"])
		var have := gm.get_bundle_donated(id, item_id) if gm else 0
		var carried: int = inv.count_item(item_id) if inv else 0
		if have < need and carried > 0:
			can_offer = true
		var entry := "%s %d/%d" % [ItemDB.get_item(item_id).get("name", item_id), have, need]
		if have < need and carried > 0:
			entry += " (+%d)" % mini(carried, need - have)
		parts.append(entry)
	var req_label := UIKit.label(",  ".join(parts), 12)
	req_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	req_label.custom_minimum_size = Vector2(520, 0)
	info.add_child(req_label)
	info.add_child(UIKit.label("Reward: " + str(bundle.get("reward", {}).get("text", "")), 11, UIKit.COL_MUTED))

	var offer := UIKit.button("Offer")
	offer.custom_minimum_size = Vector2(110, 34)
	offer.disabled = complete or not can_offer
	offer.pressed.connect(func():
		if gm and gm.donate_to_bundle(id) > 0:
			if not gm.is_bundle_complete(id):
				gm.show_notification("Offered to %s" % bundle.get("name", id))
			_rebuild()
	)
	row.add_child(offer)
	return card
