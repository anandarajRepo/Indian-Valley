extends CanvasLayer
## Popup.gd — the single modal overlay for dialogue, shop, inventory, the day
## summary, and the pause menu. Only one modal is ever open at a time.
##
## Lives as a persistent child of Main (layer 20, above the HUD). Opening any
## modal pauses the game clock; closing resumes it (while in a playable world).
## All UI is built procedurally — no art required for the vertical slice.

enum Mode { NONE, DIALOGUE, SHOP, INVENTORY, SUMMARY, PAUSE }

var _mode: int = Mode.NONE

# --- Root layout -----------------------------------------------------------
var _root:    Control   = null    ## Full-rect container for the active modal.
var _dim:     ColorRect = null     ## Dark backdrop behind the panel.
var _content: Control   = null     ## Cleared & rebuilt for each modal.

# --- Dialogue state --------------------------------------------------------
var _dlg_lines:   Array    = []
var _dlg_index:   int      = 0
var _dlg_speaker: String   = ""
var _dlg_on_done: Callable = Callable()
var _dlg_label:   Label    = null
var _input_enabled: bool   = false   ## Guards against the opening keypress advancing.

# --- Theme -----------------------------------------------------------------
const COL_TEXT:   Color = Color(0.95, 0.88, 0.70)
const COL_PANEL:  Color = Color(0.15, 0.10, 0.05, 0.94)
const COL_DIM:    Color = Color(0.0, 0.0, 0.0, 0.45)
const COL_ACCENT: Color = Color(0.8, 0.6, 0.2, 1.0)

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_build_root()
	_hide_root()


func _build_root() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_dim = ColorRect.new()
	_dim.color = COL_DIM
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_dim)

	_content = Control.new()
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_content)


func _hide_root() -> void:
	_root.visible = false
	_mode = Mode.NONE


func _clear_content() -> void:
	for child in _content.get_children():
		child.queue_free()

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	var gm = GameManager.instance

	# Inventory toggle works from gameplay and closes the inventory screen.
	if event.is_action_pressed("inventory_toggle"):
		if _mode == Mode.INVENTORY:
			close_all()
			get_viewport().set_input_as_handled()
			return
		elif _mode == Mode.NONE and gm != null and gm.in_game:
			toggle_inventory_screen()
			get_viewport().set_input_as_handled()
			return

	# Esc closes any open modal, or opens the pause menu from gameplay.
	if event.is_action_pressed("ui_cancel"):
		if _mode != Mode.NONE:
			close_all()
		elif gm != null and gm.in_game:
			open_pause_menu()
		get_viewport().set_input_as_handled()
		return

	if _mode == Mode.NONE or not _input_enabled:
		return

	# Advance / dismiss on interact, use_tool, or accept.
	if event.is_action_pressed("interact") \
			or event.is_action_pressed("use_tool") \
			or event.is_action_pressed("ui_accept"):
		match _mode:
			Mode.DIALOGUE:
				_advance_dialogue()
				get_viewport().set_input_as_handled()
			Mode.SUMMARY:
				close_all()
				get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------
# Open / close
# ---------------------------------------------------------------------------

func _open(mode: int) -> void:
	_mode = mode
	_clear_content()
	_root.visible = true
	GameClock.pause()
	_input_enabled = false
	_enable_input_next_frame()


func _enable_input_next_frame() -> void:
	await get_tree().process_frame
	_input_enabled = true


func close_all() -> void:
	var was_open := _mode != Mode.NONE
	_dlg_on_done = Callable()
	_hide_root()
	_clear_content()
	# Resume the clock only when returning to actual gameplay.
	var gm = GameManager.instance
	if was_open and gm != null and gm.in_game:
		GameClock.resume()

# ---------------------------------------------------------------------------
# Dialogue
# ---------------------------------------------------------------------------

func show_dialogue(speaker: String, lines: Array, on_done: Callable = Callable()) -> void:
	if lines.is_empty():
		if on_done.is_valid():
			on_done.call()
		return

	_dlg_speaker = speaker
	_dlg_lines = lines
	_dlg_index = 0
	_dlg_on_done = on_done
	_open(Mode.DIALOGUE)
	_build_dialogue()


func _build_dialogue() -> void:
	var panel := _make_panel(Vector2(1000, 150), Vector2(140, 545))
	_content.add_child(panel)

	var box := _make_vbox(panel, 12)

	var name_label := _make_label(_dlg_speaker, 18)
	name_label.add_theme_color_override("font_color", COL_ACCENT)
	box.add_child(name_label)

	_dlg_label = _make_label("", 15)
	_dlg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dlg_label.custom_minimum_size = Vector2(960, 60)
	box.add_child(_dlg_label)

	var hint := _make_label("▶  Z / Enter", 11)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(hint)

	_show_dialogue_line()


func _show_dialogue_line() -> void:
	if _dlg_label:
		_dlg_label.text = str(_dlg_lines[_dlg_index])


func _advance_dialogue() -> void:
	_dlg_index += 1
	if _dlg_index >= _dlg_lines.size():
		var cb := _dlg_on_done
		close_all()
		if cb.is_valid():
			cb.call()
	else:
		_show_dialogue_line()

# ---------------------------------------------------------------------------
# Shop
# ---------------------------------------------------------------------------

func open_shop() -> void:
	_open(Mode.SHOP)
	_build_shop()


func _shop_stock() -> Array:
	## Seeds for the current season, plus staple tools/food, in a stable order.
	var stock: Array = []
	var season_name := GameClock.get_season_name().to_lower()
	for crop in ItemDB.get_all_crops():
		if season_name in crop.get("seasons", []):
			var seed_id: String = crop.get("seed_id", "")
			var seed_item = ItemDB.get_item(seed_id)
			if not seed_item.is_empty() and not stock.has(seed_id):
				stock.append(seed_id)
	# A few always-available staples.
	for staple in ["idli", "dosa"]:
		if not ItemDB.get_item(staple).is_empty():
			stock.append(staple)
	return stock


func _build_shop() -> void:
	var panel := _make_panel(Vector2(620, 600), Vector2(330, 60))
	_content.add_child(panel)

	var box := _make_vbox(panel, 8)

	var title := _make_label("Kavitha's General Store", 20)
	title.add_theme_color_override("font_color", COL_ACCENT)
	box.add_child(title)

	var subtitle := _make_label("Fresh %s stock" % GameClock.get_season_name(), 12)
	box.add_child(subtitle)

	var gold_label := _make_label("Your gold: %d" % GameData.gold, 14)
	box.add_child(gold_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(580, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for item_id in _shop_stock():
		list.add_child(_build_shop_row(item_id, gold_label))

	var close_btn := _make_button("Close  (Esc)")
	close_btn.pressed.connect(close_all)
	box.add_child(close_btn)


func _build_shop_row(item_id: String, gold_label: Label) -> Control:
	var item = ItemDB.get_item(item_id)
	var price: int = item.get("buy_price", 0)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.custom_minimum_size = Vector2(560, 34)

	var name_label := _make_label(item.get("name", item_id), 14)
	name_label.custom_minimum_size = Vector2(300, 0)
	row.add_child(name_label)

	var price_label := _make_label("₹%d" % price, 14)
	price_label.custom_minimum_size = Vector2(90, 0)
	row.add_child(price_label)

	var buy_btn := _make_button("Buy")
	buy_btn.custom_minimum_size = Vector2(90, 30)
	buy_btn.pressed.connect(func(): _try_buy(item_id, price, gold_label))
	row.add_child(buy_btn)

	return row


func _try_buy(item_id: String, price: int, gold_label: Label) -> void:
	var inv := _active_inventory()
	if inv == null:
		return
	if inv.is_full():
		GameManager.instance.show_notification("Inventory full")
		return
	if not GameData.spend_gold(price):
		GameManager.instance.show_notification("Not enough gold")
		return
	inv.add_item(item_id, 1)
	gold_label.text = "Your gold: %d" % GameData.gold
	GameManager.instance.show_notification("Bought %s" % ItemDB.get_item(item_id).get("name", item_id))

# ---------------------------------------------------------------------------
# Inventory screen
# ---------------------------------------------------------------------------

func toggle_inventory_screen() -> void:
	if _mode == Mode.INVENTORY:
		close_all()
		return
	if _mode != Mode.NONE:
		return
	_open(Mode.INVENTORY)
	_build_inventory()


func _build_inventory() -> void:
	var panel := _make_panel(Vector2(560, 540), Vector2(360, 90))
	_content.add_child(panel)

	var box := _make_vbox(panel, 10)

	var title := _make_label("Inventory", 20)
	title.add_theme_color_override("font_color", COL_ACCENT)
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)

	var slots: Array = []
	var gm = GameManager.instance
	if gm:
		slots = gm.inventory_data.get("slots", [])

	for i in range(30):
		grid.add_child(_build_inv_slot(slots[i] if i < slots.size() else null))

	var hint := _make_label("Press I / T or Esc to close", 11)
	box.add_child(hint)


func _build_inv_slot(slot_data) -> Control:
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(96, 64)
	slot.add_theme_stylebox_override("panel", _slot_style())

	var label := _make_label("", 11)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	if slot_data != null:
		var item = ItemDB.get_item(slot_data.get("item_id", ""))
		label.text = "%s\n×%d" % [item.get("name", "?"), int(slot_data.get("quantity", 0))]
	slot.add_child(label)
	return slot

# ---------------------------------------------------------------------------
# Day summary
# ---------------------------------------------------------------------------

func show_day_summary(earnings: int) -> void:
	_open(Mode.SUMMARY)
	# on_overnight resumed the clock via end_day(); keep it paused for the summary.
	GameClock.pause()

	var panel := _make_panel(Vector2(560, 300), Vector2(360, 210))
	_content.add_child(panel)

	var box := _make_vbox(panel, 14)

	var title := _make_label("You slept until morning", 20)
	title.add_theme_color_override("font_color", COL_ACCENT)
	box.add_child(title)

	box.add_child(_make_label(GameClock.get_date_string(), 15))

	if earnings > 0:
		box.add_child(_make_label("Overnight sales:  +₹%d" % earnings, 15))
	else:
		box.add_child(_make_label("Nothing was shipped last night.", 13))

	box.add_child(_make_label("Gold:  ₹%d" % GameData.gold, 15))

	var cont := _make_button("Start the day  (Z / Enter)")
	cont.pressed.connect(close_all)
	box.add_child(cont)

# ---------------------------------------------------------------------------
# Pause menu
# ---------------------------------------------------------------------------

func open_pause_menu() -> void:
	_open(Mode.PAUSE)

	var panel := _make_panel(Vector2(360, 320), Vector2(460, 200))
	_content.add_child(panel)

	var box := _make_vbox(panel, 14)

	var title := _make_label("Paused", 22)
	title.add_theme_color_override("font_color", COL_ACCENT)
	box.add_child(title)

	var resume_btn := _make_button("Resume")
	resume_btn.pressed.connect(close_all)
	box.add_child(resume_btn)

	var save_btn := _make_button("Save Game")
	save_btn.pressed.connect(func():
		if GameManager.instance and GameManager.instance.save_game():
			GameManager.instance.show_notification("Game saved")
	)
	box.add_child(save_btn)

	var menu_btn := _make_button("Save & Quit to Menu")
	menu_btn.pressed.connect(func():
		if GameManager.instance:
			GameManager.instance.save_game()
			close_all()
			GameManager.instance.show_main_menu()
	)
	box.add_child(menu_btn)

# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------

func _active_inventory() -> Node:
	if GameManager.instance:
		return GameManager.instance.get_active_inventory()
	return null


func _make_panel(size: Vector2, pos: Vector2) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = size
	p.size = size
	p.position = pos
	var style := StyleBoxFlat.new()
	style.bg_color = COL_PANEL
	style.border_color = COL_ACCENT
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	p.add_theme_stylebox_override("panel", style)
	return p


func _make_vbox(parent: Control, separation: int) -> VBoxContainer:
	## A VBox filling the parent panel with a comfortable margin.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	parent.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	margin.add_child(box)
	return box


func _make_label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", COL_TEXT)
	return l


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 14)
	b.custom_minimum_size = Vector2(0, 34)
	return b


func _slot_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.20, 0.15, 0.10, 0.9)
	s.border_color = Color(0.4, 0.3, 0.15, 1.0)
	s.border_width_left = 1
	s.border_width_right = 1
	s.border_width_top = 1
	s.border_width_bottom = 1
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 4
	s.corner_radius_bottom_left = 4
	s.corner_radius_bottom_right = 4
	return s
