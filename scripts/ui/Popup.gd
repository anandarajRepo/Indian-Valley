extends CanvasLayer
## Popup.gd — the single modal overlay for dialogue, choices, shop, inventory,
## the journal, fishing, the Panchayat Hall board, the day summary, and the
## pause menu. Only one modal is ever open at a time.
##
## Lives as a persistent child of Main (layer 20, above the HUD). Opening any
## modal pauses the game clock; closing resumes it (while in a playable world).
## All UI is built procedurally — no art required for the vertical slice.

const JournalView    = preload("res://scripts/ui/JournalView.gd")
const HallView       = preload("res://scripts/ui/HallView.gd")
const FishingMinigame = preload("res://scripts/ui/FishingMinigame.gd")

enum Mode { NONE, DIALOGUE, SHOP, INVENTORY, SUMMARY, PAUSE, CHOICE, FISHING, JOURNAL, HALL }

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

# --- Views hosted in _content ---------------------------------------------
var _journal: Control = null
var _fishing: Control = null

# --- Theme (shared with the other views via UIKit) --------------------------
const COL_TEXT:   Color = UIKit.COL_TEXT
const COL_PANEL:  Color = UIKit.COL_PANEL
const COL_DIM:    Color = UIKit.COL_DIM
const COL_ACCENT: Color = UIKit.COL_ACCENT

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
	_journal = null
	_fishing = null


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

	# Journal toggle mirrors the inventory toggle.
	if event.is_action_pressed("journal"):
		if _mode == Mode.JOURNAL:
			close_all()
			get_viewport().set_input_as_handled()
			return
		elif _mode == Mode.NONE and gm != null and gm.in_game:
			open_journal()
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

	# Journal: Q / E flip between tabs.
	if _mode == Mode.JOURNAL and _journal != null:
		if event.is_action_pressed("hotbar_prev") or event.is_action_pressed("hotbar_next"):
			_journal.cycle(-1 if event.is_action_pressed("hotbar_prev") else 1)
			get_viewport().set_input_as_handled()
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
			Mode.FISHING:
				if _fishing:
					_fishing.press()
				get_viewport().set_input_as_handled()
			Mode.CHOICE:
				# Z / X pick the focused option (Enter is handled by the button).
				var focused := get_viewport().gui_get_focus_owner()
				if focused is Button and not event.is_action_pressed("ui_accept"):
					focused.emit_signal("pressed")
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
# Choice (a prompt with a few buttons)
# ---------------------------------------------------------------------------

func show_choice(speaker: String, prompt: String, options: Array, on_choice: Callable) -> void:
	## Ask the player to pick one of `options`. `on_choice` receives the index
	## after the modal has closed (Esc cancels without calling it).
	_open(Mode.CHOICE)
	var panel := _make_panel(Vector2(1000, 170), Vector2(140, 525))
	_content.add_child(panel)
	var box := _make_vbox(panel, 10)

	var name_label := _make_label(speaker, 18)
	name_label.add_theme_color_override("font_color", COL_ACCENT)
	box.add_child(name_label)

	var text := _make_label(prompt, 15)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(960, 0)
	box.add_child(text)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var first: Button = null
	for i in range(options.size()):
		var b := _make_button(str(options[i]))
		b.custom_minimum_size = Vector2(180, 34)
		var idx := i
		b.pressed.connect(func():
			close_all()
			if on_choice.is_valid():
				on_choice.call(idx)
		)
		row.add_child(b)
		if first == null:
			first = b
	if first:
		first.grab_focus()

# ---------------------------------------------------------------------------
# Journal, fishing and the Panchayat Hall (views live in their own scripts)
# ---------------------------------------------------------------------------

func open_journal() -> void:
	if _mode != Mode.NONE:
		return
	_open(Mode.JOURNAL)
	_journal = JournalView.new()
	_content.add_child(_journal)


func open_fishing(location: String) -> void:
	if _mode != Mode.NONE:
		return
	_open(Mode.FISHING)
	_fishing = FishingMinigame.new()
	_fishing.location = location
	_fishing.finished.connect(func(fish_id: String):
		close_all()
		if GameManager.instance:
			GameManager.instance.on_fishing_finished(fish_id)
	)
	_content.add_child(_fishing)


func open_hall() -> void:
	if _mode != Mode.NONE:
		return
	_open(Mode.HALL)
	var view := HallView.new()
	view.close_requested.connect(close_all)
	_content.add_child(view)

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
	for staple in ["idli", "dosa", "banana_leaf_rice"]:
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

func show_day_summary(report: Dictionary) -> void:
	## `report` comes from GameManager.on_overnight(): earnings, weather,
	## season / year changes, withered crops, festival and birthdays.
	_open(Mode.SUMMARY)
	# on_overnight resumed the clock via end_day(); keep it paused for the summary.
	GameClock.pause()

	var review: Dictionary = report.get("year_review", {})
	var height := 470 if review.is_empty() else 640
	var panel := _make_panel(Vector2(620, height), Vector2(330, (720 - height) / 2))
	_content.add_child(panel)

	var box := _make_vbox(panel, 8)

	var title_text := "You slept until morning"
	if report.get("new_year", false):
		title_text = "Happy Ugadi — a new year begins!"
	elif report.get("new_season", false):
		title_text = "%s has arrived" % GameClock.get_season_name()
	var title := _make_label(title_text, 20)
	title.add_theme_color_override("font_color", COL_ACCENT)
	box.add_child(title)

	box.add_child(_make_label(GameClock.get_date_string(), 15))
	box.add_child(_make_label("Weather: %s   ·   Tomorrow: %s" % [
		Weather.get_display_name(report.get("weather", Weather.today)),
		Weather.get_display_name(report.get("forecast", Weather.tomorrow))], 13))

	var earnings := int(report.get("earnings", 0))
	if earnings > 0:
		box.add_child(_make_label("Overnight sales:  +₹%d" % earnings, 15))
	else:
		box.add_child(_make_label("Nothing was shipped last night.", 13))
	box.add_child(_make_label("Gold:  ₹%d" % GameData.gold, 15))

	var notes: Array = []
	if report.get("rain_watered", false):
		notes.append("The rain watered your crops.")
	var withered := int(report.get("withered", 0))
	if withered > 0:
		notes.append("%d out-of-season crop%s withered. Clear them with the hoe or sickle." % [withered, "" if withered == 1 else "s"])
	if report.get("new_season", false):
		notes.append("Kavitha has new %s seeds in stock." % GameClock.get_season_name())
	var festival: Dictionary = report.get("festival", {})
	if not festival.is_empty():
		notes.append("Today is %s! Head to the town square." % festival.get("name", "a festival"))
	for bday in report.get("birthdays", []):
		notes.append("It's %s's birthday today." % bday)
	for note in notes:
		var l := _make_label("•  " + note, 13)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(570, 0)
		box.add_child(l)

	if not review.is_empty():
		box.add_child(_build_year_review(review))

	var cont := _make_button("Start the day  (Z / Enter)")
	cont.pressed.connect(close_all)
	box.add_child(cont)


func _build_year_review(review: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	var head := _make_label("Year %d complete — your story so far" % int(review.get("year", 1)), 16)
	head.add_theme_color_override("font_color", COL_ACCENT)
	col.add_child(head)
	var hall_line := "Panchayat Hall restored!" if review.get("restored", false) \
		else "Hall offerings: %d / %d" % [int(review.get("bundles_done", 0)), int(review.get("bundles_total", 0))]
	for line in [
		"Earned ₹%d from shipping" % int(review.get("earned", 0)),
		"Harvested %d crops · caught %d fish · foraged %d finds" % [
			int(review.get("harvested", 0)), int(review.get("fish", 0)), int(review.get("foraged", 0))],
		"Entered %d festivals · %d close friends (4+ hearts)" % [
			int(review.get("festivals", 0)), int(review.get("friends", 0))],
		hall_line,
	]:
		col.add_child(_make_label(line, 13))
	return col

# ---------------------------------------------------------------------------
# Pause menu
# ---------------------------------------------------------------------------

func open_pause_menu() -> void:
	_open(Mode.PAUSE)

	var panel := _make_panel(Vector2(360, 370), Vector2(460, 175))
	_content.add_child(panel)

	var box := _make_vbox(panel, 14)

	var title := _make_label("Paused", 22)
	title.add_theme_color_override("font_color", COL_ACCENT)
	box.add_child(title)

	var resume_btn := _make_button("Resume")
	resume_btn.pressed.connect(close_all)
	box.add_child(resume_btn)

	var journal_btn := _make_button("Journal  (J)")
	journal_btn.pressed.connect(func():
		close_all()
		open_journal()
	)
	box.add_child(journal_btn)

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
	return UIKit.panel(size, pos)


func _make_vbox(parent: Control, separation: int) -> VBoxContainer:
	return UIKit.vbox(parent, separation)


func _make_label(text: String, font_size: int) -> Label:
	return UIKit.label(text, font_size)


func _make_button(text: String) -> Button:
	return UIKit.button(text)


func _slot_style() -> StyleBoxFlat:
	return UIKit.slot_style()
