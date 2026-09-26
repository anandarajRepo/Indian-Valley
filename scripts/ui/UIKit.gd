extends RefCounted
class_name UIKit
## UIKit.gd — shared builders for the procedural (art-free) UI.
##
## Every modal view uses the same warm palette and panel style; keeping the
## builders here lets Popup, the journal, the fishing minigame and the Hall
## board look identical without copying helpers around.

const COL_TEXT:   Color = Color(0.95, 0.88, 0.70)
const COL_MUTED:  Color = Color(0.72, 0.64, 0.50)
const COL_PANEL:  Color = Color(0.15, 0.10, 0.05, 0.94)
const COL_DIM:    Color = Color(0.0, 0.0, 0.0, 0.45)
const COL_ACCENT: Color = Color(0.8, 0.6, 0.2, 1.0)
const COL_GOOD:   Color = Color(0.55, 0.80, 0.40)
const COL_BAD:    Color = Color(0.85, 0.40, 0.30)


static func panel(size: Vector2, pos: Vector2) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = size
	p.size = size
	p.position = pos
	var style := StyleBoxFlat.new()
	style.bg_color = COL_PANEL
	style.border_color = COL_ACCENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	p.add_theme_stylebox_override("panel", style)
	return p


static func vbox(parent: Control, separation: int) -> VBoxContainer:
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


static func label(text: String, font_size: int, color: Color = COL_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


static func title(text: String, font_size: int = 20) -> Label:
	return label(text, font_size, COL_ACCENT)


static func button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 14)
	b.custom_minimum_size = Vector2(0, 34)
	return b


static func slot_style(highlight: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.32, 0.24, 0.12, 0.95) if highlight else Color(0.20, 0.15, 0.10, 0.9)
	s.border_color = COL_ACCENT if highlight else Color(0.4, 0.3, 0.15, 1.0)
	s.set_border_width_all(2 if highlight else 1)
	s.set_corner_radius_all(4)
	return s


static func bar(value: float, max_value: float, width: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.min_value = 0
	b.max_value = max_value
	b.value = value
	b.show_percentage = false
	b.custom_minimum_size = Vector2(width, 12)
	return b
