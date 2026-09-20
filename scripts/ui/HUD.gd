extends CanvasLayer
## HUD.gd — In-game heads-up display.
##
## Displays:
##   - Clock (top-right): time + day + season + year
##   - Energy bar (top-left): coloured progress bar
##   - Gold display (bottom-left): ₹ amount
##   - Hotbar (bottom-centre): 5 item slots with item icon/count
##   - Notifications (top-centre): short timed messages

signal hotbar_slot_clicked(index: int)

# ---------------------------------------------------------------------------
# Nodes (resolved in _ready — created procedurally since we have no art yet)
# ---------------------------------------------------------------------------

var clock_label:    Label         = null
var date_label:     Label         = null
var energy_bar:     ProgressBar   = null
var energy_label:   Label         = null
var gold_label:     Label         = null
var hotbar_slots:   Array         = []    ## Array of Panel nodes
var notif_label:    Label         = null

var _notif_timer:   float         = 0.0
const NOTIF_DURATION: float       = 3.0

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_build_hud()
	_connect_signals()
	_update_clock()
	_update_energy(GameData.energy_current, GameData.energy_max)
	_update_gold(GameData.gold)


func _process(delta: float) -> void:
	## Update clock every frame (it changes every in-game minute)
	_update_clock()

	## Hide notification after duration
	if _notif_timer > 0.0:
		_notif_timer -= delta
		if _notif_timer <= 0.0 and notif_label != null:
			notif_label.visible = false


# ---------------------------------------------------------------------------
# Build HUD nodes procedurally (no art needed for Phase 0)
# ---------------------------------------------------------------------------

func _build_hud() -> void:
	## ---- CLOCK (top-right) ----
	var clock_panel = _panel(Vector2(200, 56), Vector2(1080, 8))
	add_child(clock_panel)

	clock_label = _label("6:00 AM", 14)
	clock_label.position = Vector2(8, 4)
	clock_panel.add_child(clock_label)

	date_label = _label("Day 1, Kharif — Year 1", 10)
	date_label.position = Vector2(8, 24)
	clock_panel.add_child(date_label)

	## ---- ENERGY (top-left) ----
	var energy_panel = _panel(Vector2(160, 36), Vector2(8, 8))
	add_child(energy_panel)

	var energy_title = _label("Energy", 10)
	energy_title.position = Vector2(8, 4)
	energy_panel.add_child(energy_title)

	energy_bar = ProgressBar.new()
	energy_bar.position = Vector2(8, 20)
	energy_bar.size = Vector2(120, 10)
	energy_bar.min_value = 0
	energy_bar.max_value = 100
	energy_bar.value = 100
	energy_bar.show_percentage = false
	energy_panel.add_child(energy_bar)

	energy_label = _label("100 / 100", 9)
	energy_label.position = Vector2(132, 20)
	energy_panel.add_child(energy_label)

	## ---- GOLD (bottom-left) ----
	var gold_panel = _panel(Vector2(120, 32), Vector2(8, 680))
	add_child(gold_panel)

	var gold_icon = _label("₹", 16)
	gold_icon.position = Vector2(6, 4)
	gold_panel.add_child(gold_icon)

	gold_label = _label("500", 14)
	gold_label.position = Vector2(28, 6)
	gold_panel.add_child(gold_label)

	## ---- HOTBAR (bottom-centre) ----
	var hotbar_panel = _panel(Vector2(250, 52), Vector2(515, 660))
	add_child(hotbar_panel)

	for i in range(5):
		var slot = _panel(Vector2(44, 44), Vector2(4 + i * 49, 4))
		slot.add_child(_label(str(i + 1), 8))
		hotbar_panel.add_child(slot)
		hotbar_slots.append(slot)
		## Click to select hotbar slot
		var btn = Button.new()
		btn.position = Vector2(0, 0)
		btn.size = Vector2(44, 44)
		btn.flat = true
		var slot_index = i
		btn.pressed.connect(func(): emit_signal("hotbar_slot_clicked", slot_index))
		slot.add_child(btn)

	_highlight_hotbar(0)

	## ---- NOTIFICATION (top-centre) ----
	notif_label = _label("", 12)
	notif_label.position = Vector2(440, 12)
	notif_label.size = Vector2(400, 32)
	notif_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notif_label.visible = false
	add_child(notif_label)


# ---------------------------------------------------------------------------
# Signal connections
# ---------------------------------------------------------------------------

func _connect_signals() -> void:
	GameClock.time_changed.connect(_on_time_changed)
	GameData.energy_changed.connect(_update_energy)
	GameData.gold_changed.connect(_update_gold)


# ---------------------------------------------------------------------------
# Update methods
# ---------------------------------------------------------------------------

func _update_clock() -> void:
	if clock_label:
		clock_label.text = GameClock.get_time_string()
	if date_label:
		date_label.text  = GameClock.get_date_string()


func _on_time_changed(_hour: int, _minute: int) -> void:
	_update_clock()


func _update_energy(current: int, maximum: int) -> void:
	if energy_bar:
		energy_bar.max_value = maximum
		energy_bar.value     = current
	if energy_label:
		energy_label.text = "%d" % current


func _update_gold(amount: int) -> void:
	if gold_label:
		gold_label.text = "%d" % amount


func update_hotbar(slots: Array, selected: int) -> void:
	## Call this from Inventory when inventory changes.
	for i in range(min(slots.size(), hotbar_slots.size())):
		var slot_node = hotbar_slots[i]
		var label = slot_node.get_child(0) as Label
		var slot_data = slots[i]
		if slot_data == null:
			label.text = str(i + 1)
		else:
			var item = ItemDB.get_item(slot_data["item_id"])
			label.text = item.get("name", "?").left(6) + "\n×%d" % slot_data["quantity"]
	_highlight_hotbar(selected)


func _highlight_hotbar(index: int) -> void:
	for i in range(hotbar_slots.size()):
		var panel = hotbar_slots[i] as Panel
		if panel == null:
			continue
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.35, 0.25, 0.15, 0.85) if i == index else Color(0.2, 0.15, 0.1, 0.7)
		style.border_width_left   = 2
		style.border_width_right  = 2
		style.border_width_top    = 2
		style.border_width_bottom = 2
		style.border_color = Color(0.8, 0.6, 0.2, 1.0) if i == index else Color(0.4, 0.3, 0.15, 1.0)
		style.corner_radius_top_left     = 4
		style.corner_radius_top_right    = 4
		style.corner_radius_bottom_left  = 4
		style.corner_radius_bottom_right = 4
		panel.add_theme_stylebox_override("panel", style)


func show_notification(message: String) -> void:
	if notif_label == null:
		return
	notif_label.text    = message
	notif_label.visible = true
	_notif_timer = NOTIF_DURATION


# ---------------------------------------------------------------------------
# Helpers for procedural node creation
# ---------------------------------------------------------------------------

func _panel(size: Vector2, pos: Vector2) -> Panel:
	var p = Panel.new()
	p.size     = size
	p.position = pos
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.10, 0.05, 0.80)
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	p.add_theme_stylebox_override("panel", style)
	return p


func _label(text: String, font_size: int) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.95, 0.88, 0.70))
	return l
