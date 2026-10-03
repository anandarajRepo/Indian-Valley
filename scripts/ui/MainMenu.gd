extends Control
## MainMenu.gd — the title screen shown at boot and after quitting to menu.
##
## Built procedurally (no art yet). Pages:
##   main  — Continue (latest save) / New Game / Load Game / Options / Quit
##   slots — pick one of the three save slots (to start a new game or to load)
##   name  — name your farmer, then start in the chosen slot
##   credits — who made the game, plus the Godot Engine licence notice
## Buttons drive the GameManager flow (new_game / load_slot / quit_game).

const COL_TEXT:   Color = Color(0.96, 0.90, 0.74)
const COL_ACCENT: Color = Color(0.85, 0.66, 0.24)
const COL_MUTED:  Color = Color(0.72, 0.64, 0.50)
const COL_BG:     Color = Color(0.094, 0.078, 0.047)

const CREDITS_LINES: Array = [
	["Indian Valley", "a farming & life sim set in Viralpadi Valley"],
	["Design, code & writing", "Indian Valley Project"],
	["Music & sound", "synthesised in-engine — raga Mohanam over a tanpura drone"],
	["Inspired by", "the farms, festivals and people of rural South India"],
	["Built with", "Godot Engine"],
]
const GODOT_NOTICE: String = "This game uses Godot Engine, available under the MIT licence.\n© 2014-present Godot Engine contributors. © 2007-2014 Juan Linietsky, Ariel Manzur."

var _box: VBoxContainer = null
var _pending_slot: int = 0
var _name_edit: LineEdit = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 14)
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(_box)

	var version := _label("v%s%s" % [ProjectSettings.get_setting("application/config/version", ""),
		"  ·  demo" if _is_demo() else ""], 11)
	version.add_theme_color_override("font_color", COL_MUTED)
	version.position = Vector2(12, 694)
	add_child(version)

	show_main()


func _clear() -> void:
	for child in _box.get_children():
		child.queue_free()


func _header() -> void:
	var title := _label("Indian Valley", 48)
	title.add_theme_color_override("font_color", COL_ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(title)

	var tagline := _label("A year in Viralpadi Valley", 16)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(tagline)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	_box.add_child(spacer)

# ---------------------------------------------------------------------------
# Pages
# ---------------------------------------------------------------------------

func show_main() -> void:
	_clear()
	_header()
	var any_save := SaveManager.most_recent_slot() != -1

	var continue_btn := _button("Continue")
	continue_btn.disabled = not any_save
	continue_btn.pressed.connect(_on_continue)
	_box.add_child(continue_btn)

	var new_btn := _button("New Game")
	new_btn.pressed.connect(func(): show_slots(true))
	_box.add_child(new_btn)

	var load_btn := _button("Load Game")
	load_btn.disabled = not any_save
	load_btn.pressed.connect(func(): show_slots(false))
	_box.add_child(load_btn)

	var options_btn := _button("Options")
	options_btn.pressed.connect(func():
		if GameManager.instance:
			GameManager.instance.open_options())
	_box.add_child(options_btn)

	var credits_btn := _button("Credits")
	credits_btn.pressed.connect(show_credits)
	_box.add_child(credits_btn)

	var quit_btn := _button("Quit")
	quit_btn.pressed.connect(_on_quit)
	_box.add_child(quit_btn)

	(continue_btn if any_save else new_btn).grab_focus.call_deferred()


func show_slots(for_new_game: bool) -> void:
	_clear()
	_header()
	var prompt := _label("Choose a slot for your new farm" if for_new_game else "Choose a save to load", 18)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(prompt)

	var first: Button = null
	for slot in range(SaveManager.SLOT_COUNT):
		var exists := SaveManager.slot_exists(slot)
		var b := _button("Slot %d:  %s" % [slot + 1, SaveManager.describe_slot(slot)])
		b.custom_minimum_size = Vector2(520, 46)
		b.disabled = not for_new_game and (not exists or SaveManager.get_slot_info(slot).get("damaged", false))
		var s := slot
		if for_new_game:
			b.pressed.connect(func(): _pick_new_slot(s, exists))
		else:
			b.pressed.connect(func(): _load(s))
		_box.add_child(b)
		if first == null and not b.disabled:
			first = b

	var back := _button("Back")
	back.pressed.connect(show_main)
	_box.add_child(back)
	(first if first else back).grab_focus.call_deferred()


func show_credits() -> void:
	_clear()
	_header()
	for entry in CREDITS_LINES:
		var role := _label(entry[0], 14)
		role.add_theme_color_override("font_color", COL_MUTED)
		role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_box.add_child(role)
		var who := _label(entry[1], 18)
		who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_box.add_child(who)
	var notice := _label(GODOT_NOTICE, 11)
	notice.add_theme_color_override("font_color", COL_MUTED)
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(notice)
	var back := _button("Back")
	back.pressed.connect(show_main)
	_box.add_child(back)
	back.grab_focus.call_deferred()


func _pick_new_slot(slot: int, exists: bool) -> void:
	if not exists:
		show_name_entry(slot)
		return
	_clear()
	_header()
	var warn := _label("Slot %d already holds a farm:\n%s\nStart over and replace it?" % [
		slot + 1, SaveManager.describe_slot(slot)], 16)
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(warn)
	var yes := _button("Replace it")
	yes.pressed.connect(func(): show_name_entry(slot))
	_box.add_child(yes)
	var no := _button("Back")
	no.pressed.connect(func(): show_slots(true))
	_box.add_child(no)
	no.grab_focus.call_deferred()


func show_name_entry(slot: int) -> void:
	_pending_slot = slot
	_clear()
	_header()
	var prompt := _label("What's your name, farmer?", 18)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(prompt)

	_name_edit = LineEdit.new()
	_name_edit.text = "Arya"
	_name_edit.max_length = 16
	_name_edit.custom_minimum_size = Vector2(260, 40)
	_name_edit.add_theme_font_size_override("font_size", 18)
	_name_edit.text_submitted.connect(func(_t): _start_new())
	_box.add_child(_name_edit)

	var start := _button("Begin")
	start.pressed.connect(_start_new)
	_box.add_child(start)
	var back := _button("Back")
	back.pressed.connect(func(): show_slots(true))
	_box.add_child(back)
	_name_edit.grab_focus.call_deferred()
	_name_edit.select_all.call_deferred()

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

func _start_new() -> void:
	if GameManager.instance:
		GameManager.instance.new_game(_pending_slot, _name_edit.text if _name_edit else "")


func _load(slot: int) -> void:
	if GameManager.instance:
		GameManager.instance.load_slot(slot)


func _on_continue() -> void:
	var slot := SaveManager.most_recent_slot()
	if slot != -1:
		_load(slot)


func _on_quit() -> void:
	if GameManager.instance:
		GameManager.instance.quit_game()
	else:
		get_tree().quit()


func _is_demo() -> bool:
	return GameManager.instance != null and GameManager.instance.is_demo()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", COL_TEXT)
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 20)
	b.custom_minimum_size = Vector2(260, 46)
	b.pressed.connect(func(): Audio.play("ui_click"))
	return b
