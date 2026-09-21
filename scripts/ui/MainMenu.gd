extends Control
## MainMenu.gd — the title screen shown at boot and after quitting to menu.
##
## Built procedurally (no art yet). Buttons drive the GameManager flow:
##   New Game   → fresh save state, load the Farm in Ugadi (Spring)
##   Continue   → load slot 0 (disabled when no save exists)
##   Quit       → exit

const COL_TEXT:   Color = Color(0.96, 0.90, 0.74)
const COL_ACCENT: Color = Color(0.85, 0.66, 0.24)
const COL_BG:     Color = Color(0.094, 0.078, 0.047)


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

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)

	var title := _label("Indian Valley", 48)
	title.add_theme_color_override("font_color", COL_ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var tagline := _label("A season in Viralpadi Valley", 16)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tagline)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	box.add_child(spacer)

	var new_btn := _button("New Game")
	new_btn.pressed.connect(_on_new_game)
	box.add_child(new_btn)

	var continue_btn := _button("Continue")
	continue_btn.disabled = not _has_save()
	continue_btn.pressed.connect(_on_continue)
	box.add_child(continue_btn)

	var quit_btn := _button("Quit")
	quit_btn.pressed.connect(_on_quit)
	box.add_child(quit_btn)

	new_btn.grab_focus()


func _on_new_game() -> void:
	if GameManager.instance:
		GameManager.instance.new_game()


func _on_continue() -> void:
	if GameManager.instance:
		GameManager.instance.continue_game()


func _on_quit() -> void:
	if GameManager.instance:
		GameManager.instance.quit_game()
	else:
		get_tree().quit()


func _has_save() -> bool:
	return GameManager.instance != null and GameManager.instance.has_save()

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
	return b
