extends Control
## JournalView.gd — the player's journal (J), shown inside the Popup layer.
##
## Three tabs:
##   Calendar  — this season's 28 days, festivals, birthdays, weather forecast
##   Villagers — friendship hearts, birthdays and gift progress for each villager
##   Skills    — skill levels plus lifetime stats and Hall progress

const TABS: Array = ["Calendar", "Villagers", "Skills"]

var tab: int = 0

var _body: Control = null
var _tab_buttons: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := UIKit.panel(Vector2(760, 600), Vector2(260, 60))
	add_child(panel)
	var box := UIKit.vbox(panel, 10)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)
	header.add_child(UIKit.title("Journal", 20))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	for i in range(TABS.size()):
		var b := UIKit.button(TABS[i])
		b.custom_minimum_size = Vector2(110, 32)
		b.toggle_mode = true
		var idx := i
		b.pressed.connect(func(): show_tab(idx))
		header.add_child(b)
		_tab_buttons.append(b)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	_body.custom_minimum_size = Vector2(720, 480)
	box.add_child(_body)

	box.add_child(UIKit.label("Q / E or click to switch tabs   ·   J or Esc to close", 11, UIKit.COL_MUTED))
	show_tab(tab)


func cycle(step: int) -> void:
	show_tab((tab + step + TABS.size()) % TABS.size())


func show_tab(index: int) -> void:
	tab = index
	for i in range(_tab_buttons.size()):
		_tab_buttons[i].button_pressed = i == tab
	for child in _body.get_children():
		child.queue_free()
	match tab:
		0: _build_calendar()
		1: _build_villagers()
		2: _build_skills()

# ---------------------------------------------------------------------------
# Calendar
# ---------------------------------------------------------------------------

func _build_calendar() -> void:
	var season: int = GameClock.current_season
	_body.add_child(UIKit.label("%s — Year %d" % [GameClock.get_season_name(), GameClock.current_year], 16))
	_body.add_child(UIKit.label("Today: %s   ·   Tomorrow: %s" % [
		Weather.get_display_name(Weather.today), Weather.get_display_name(Weather.tomorrow)], 13, UIKit.COL_MUTED))

	var events := Calendar.events_for_season(season)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	_body.add_child(grid)

	for day in range(1, GameClock.DAYS_PER_SEASON + 1):
		var cell := Panel.new()
		cell.custom_minimum_size = Vector2(98, 54)
		cell.add_theme_stylebox_override("panel", UIKit.slot_style(day == GameClock.current_day))
		var text := str(day)
		var color := UIKit.COL_TEXT
		for e in events:
			if e["day"] == day:
				if e["kind"] == "festival":
					text += "\n" + e["name"]
					color = UIKit.COL_ACCENT
				else:
					text += "\n" + Relationships.get_name_of(e["id"]).split(" ")[0] + " bday"
		var l := UIKit.label(text, 10, color)
		l.position = Vector2(6, 3)
		l.size = Vector2(88, 48)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cell.add_child(l)
		grid.add_child(cell)

	var upcoming: Array = []
	for e in events:
		if e["day"] >= GameClock.current_day:
			upcoming.append("Day %d — %s" % [e["day"], e["name"]])
	var note := "Coming up: " + (", ".join(upcoming) if not upcoming.is_empty() else "nothing else this season")
	var nl := UIKit.label(note, 12)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.custom_minimum_size = Vector2(700, 0)
	_body.add_child(nl)

# ---------------------------------------------------------------------------
# Villagers
# ---------------------------------------------------------------------------

func _build_villagers() -> void:
	_body.add_child(UIKit.label("Chat daily and bring gifts they love. Birthday gifts count ×8.", 12, UIKit.COL_MUTED))
	for npc in Relationships.get_all_npcs():
		var id: String = npc["id"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.custom_minimum_size = Vector2(700, 52)

		var info := VBoxContainer.new()
		info.custom_minimum_size = Vector2(250, 0)
		var met := Relationships.has_met(id)
		info.add_child(UIKit.label(npc["name"] if met else "???", 15, UIKit.COL_ACCENT if met else UIKit.COL_MUTED))
		var bday: Dictionary = npc.get("birthday", {})
		info.add_child(UIKit.label("%s · Birthday: %s %d" % [npc.get("role", ""),
			String(bday.get("season", "")).capitalize(), int(bday.get("day", 0))], 11, UIKit.COL_MUTED))
		row.add_child(info)

		var hearts := VBoxContainer.new()
		hearts.custom_minimum_size = Vector2(240, 0)
		hearts.add_child(UIKit.label("%d / %d hearts" % [Relationships.get_hearts(id), Relationships.MAX_HEARTS], 12))
		hearts.add_child(UIKit.bar(Relationships.get_points(id), Relationships.MAX_POINTS, 220))
		row.add_child(hearts)

		var status := []
		if Relationships.talked_today.has(id):
			status.append("Chatted")
		if Relationships.gifted_today.has(id):
			status.append("Gifted")
		if Relationships.is_birthday(id):
			status.append("Birthday!")
		row.add_child(UIKit.label(", ".join(status) if not status.is_empty() else "—", 12,
			UIKit.COL_GOOD if not status.is_empty() else UIKit.COL_MUTED))
		_body.add_child(row)

# ---------------------------------------------------------------------------
# Skills & stats
# ---------------------------------------------------------------------------

func _build_skills() -> void:
	_body.add_child(UIKit.label("Skills", 16, UIKit.COL_ACCENT))
	for skill in ["farming", "foraging", "fishing", "mining"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var level := GameData.get_skill_level(skill)
		var name_label := UIKit.label("%s  Lv %d" % [skill.capitalize(), level], 14)
		name_label.custom_minimum_size = Vector2(180, 0)
		row.add_child(name_label)
		var xp := GameData.get_skill_xp(skill)
		var needed := GameData.XP_PER_LEVEL * (level + 1)
		row.add_child(UIKit.bar(xp, needed, 300))
		row.add_child(UIKit.label("%d / %d xp" % [xp, needed], 12, UIKit.COL_MUTED))
		_body.add_child(row)

	_body.add_child(UIKit.label("This save", 16, UIKit.COL_ACCENT))
	var gm = GameManager.instance
	var bundles_done: int = gm.hall_state.get("completed", {}).size() if gm else 0
	var lines := [
		"Days played: %d" % GameData.get_stat("days_played"),
		"Gold earned from shipping: ₹%d" % GameData.get_stat("total_earned"),
		"Crops harvested: %d" % GameData.get_stat("crops_harvested"),
		"Fish caught: %d" % GameData.get_stat("fish_caught"),
		"Items foraged: %d" % GameData.get_stat("items_foraged"),
		"Gifts given: %d" % GameData.get_stat("gifts_given"),
		"Festivals entered: %d" % GameData.get_stat("festivals_attended"),
		"Panchayat Hall offerings: %d / %d" % [bundles_done, ItemDB.get_bundles().size()],
	]
	for line in lines:
		_body.add_child(UIKit.label(line, 13))
