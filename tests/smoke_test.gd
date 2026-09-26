extends Node
## Headless smoke test for the Phase 2 (Alpha) year loop.
##
## Run from the project root:
##   godot --headless res://tests/SmokeTest.tscn
## Exits with code 0 when every check passes, 1 otherwise. Uses save slot 2
## and restores whatever was there before.

const MAIN_SCENE := "res://scenes/Main.tscn"
const TEST_SLOT := 2

var gm: GameManager = null
var _passed := 0
var _failed := 0
var _slot_backup := ""


func _ready() -> void:
	# Watchdog: a script error aborts _run mid-way, so never hang forever.
	get_tree().create_timer(90.0).timeout.connect(func():
		print("\nSmoke test TIMED OUT after %d passed, %d failed" % [_passed, _failed])
		_restore_slot()
		get_tree().quit(2))
	_run.call_deferred()


func check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  PASS  ", label)
	else:
		_failed += 1
		print("  FAIL  ", label)


func frames(n: int = 2) -> void:
	for i in range(n):
		await get_tree().process_frame


func world() -> Node:
	return gm.current_scene_node.get_child(gm.current_scene_node.get_child_count() - 1)


func inv() -> Node:
	return gm.get_active_inventory()


func sleep_overnight() -> Dictionary:
	## Trigger the overnight pipeline and return the summary report shown.
	GameClock.resume()
	GameClock._trigger_sleep()
	await frames(2)
	var popup = gm.popup
	check(popup._mode == popup.Mode.SUMMARY, "day summary is shown after sleeping")
	popup.close_all()
	await frames(1)
	return {}


func set_date(season: int, day: int) -> void:
	GameClock.current_season = season
	GameClock.current_day = day


func _backup_slot() -> void:
	var path := SaveManager._slot_path(TEST_SLOT)
	if FileAccess.file_exists(path):
		_slot_backup = FileAccess.get_file_as_string(path)


func _restore_slot() -> void:
	var path := SaveManager._slot_path(TEST_SLOT)
	if _slot_backup != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(_slot_backup)
		f.close()
	else:
		SaveManager.delete_slot(TEST_SLOT)


func _run() -> void:
	_backup_slot()
	var main: Node = load(MAIN_SCENE).instantiate()
	add_child(main)
	gm = GameManager.instance
	gm.current_slot = TEST_SLOT
	await frames(3)

	print("[1] New game")
	gm.new_game()
	await frames(3)
	check(world().name == "Farm", "new game loads the farm")
	check(GameClock.current_season == GameClock.Season.UGADI and GameClock.current_day == 1, "starts Ugadi 1")
	check(Weather.today == Weather.SUNNY, "first morning is sunny")
	check(gm.get_forage_spots("trail").size() >= GameManager.FORAGE_MIN, "trail forage generated")
	check(ItemDB.get_crops_for_season(GameClock.Season.WINTER).size() >= 5, "winter has crops")
	check(ItemDB.get_bundles().size() == 6, "six Hall bundles loaded")
	check(Relationships.get_all_npcs().size() == 6, "six villagers loaded")

	print("[2] Farming + rain")
	var farm := world()
	var tile := Vector2i(6, 4)
	farm._till_soil(tile)
	inv().add_item("okra_seed", 1)
	farm._plant_seed(tile, "okra_seed")
	farm._water_tile(tile)
	Weather.tomorrow = Weather.RAIN
	await sleep_overnight()
	var data: Dictionary = gm.farm_tiles["6,4"]
	check(int(data["progress"]) == 1, "watered crop grew overnight")
	check(Weather.today == Weather.RAIN, "forecast became today's weather")
	check(int(data["watered_day"]) == GameClock.days_elapsed, "rain watered the crop")
	check(farm._water_location(Vector2i(2, 11)) == "pond", "farm pond is fishable")
	check(farm._water_location(tile) == "", "plot is not water")

	print("[3] Season change withers out-of-season crops")
	var mel := Vector2i(7, 4)
	farm._till_soil(mel)
	inv().add_item("watermelon_seed", 1)
	farm._plant_seed(mel, "watermelon_seed")
	set_date(GameClock.Season.UGADI, 28)
	await sleep_overnight()
	check(GameClock.current_season == GameClock.Season.KHARIF, "rolled into Kharif")
	check(gm.farm_tiles["7,4"]["state"] == "dead", "watermelon withered at Kharif")
	check(gm.farm_tiles["6,4"]["state"] == "planted", "okra survives into Kharif")
	farm._till_soil(mel)
	check(gm.farm_tiles["7,4"]["state"] == "tilled", "hoe clears withered crop")

	print("[4] Eating")
	GameData.energy_current = 10
	inv().add_item("idli", 1)
	var before := GameData.energy_current
	var player = gm.get_active_player()
	player._eat("idli", ItemDB.get_item("idli"))
	check(GameData.energy_current == before + 50, "eating idli restores 50 energy")

	print("[5] Fishing")
	check(not gm.choose_fish("pond").is_empty(), "something bites in the pond")
	check(not gm.choose_fish("river").is_empty(), "something bites in the river")
	gm.on_fishing_finished("rohu")
	check(inv().count_item("rohu") == 1 and GameData.get_stat("fish_caught") == 1, "caught fish goes to inventory")
	gm.start_fishing("pond")
	await frames(2)
	check(gm.popup._mode == gm.popup.Mode.FISHING, "fishing minigame opens")
	gm.popup._fishing.press()   # too early
	await get_tree().create_timer(1.2).timeout
	check(gm.popup._mode == gm.popup.Mode.NONE, "reeling too early ends the minigame")

	print("[6] Ghats Trail foraging")
	gm.goto_trail("from_farm")
	await frames(3)
	var trail := world()
	check(trail.name == "GhatsTrail", "trail loads")
	var spots := trail.get_children().filter(func(n): return n is ForageSpot)
	check(spots.size() == gm.get_forage_spots("trail").size(), "forage nodes spawned")
	var spot: ForageSpot = spots[0]
	var fid := spot.item_id
	spot.interact(gm.get_active_player())
	check(inv().count_item(fid) >= 1 and GameData.get_stat("items_foraged") == 1, "forage picked up")
	check(trail._water_location(Vector2i(3, 5)) == "river", "trail river is fishable")

	print("[7] Villagers")
	gm.goto_town("from_farm")
	await frames(3)
	var town := world()
	check(town.name == "Town", "town loads")
	check(town.get_node_or_null("Festival") == null, "no festival decorations on a normal day")
	var ravi = town.get_node("Ravi")
	check(ravi.npc_name == "Ravi", "NPC name comes from data")
	# Full interaction: hoe held → straight to chat; finishing gives the rod.
	inv().set_hotbar_index(0)
	ravi.interact(gm.get_active_player())
	await frames(2)
	check(gm.popup._mode == gm.popup.Mode.DIALOGUE, "chatting opens dialogue")
	for i in range(10):
		if gm.popup._mode != gm.popup.Mode.DIALOGUE:
			break
		gm.popup._advance_dialogue()
		await frames(1)
	check(inv().count_item("fishing_rod") == 1, "Ravi hands over the fishing rod")
	# Holding a giftable item at the shopkeeper offers Chat / Give / Store.
	inv().add_item("jasmine_flower", 1)
	var slot := -1
	for i in range(inv().INVENTORY_SIZE):
		var sl = inv().get_slot(i)
		if sl != null and sl["item_id"] == "jasmine_flower":
			slot = i
	var tmp = inv()._slots[0]
	inv()._slots[0] = inv()._slots[slot]
	inv()._slots[slot] = tmp
	inv().set_hotbar_index(0)
	town.get_node("Kavitha").interact(gm.get_active_player())
	await frames(2)
	check(gm.popup._mode == gm.popup.Mode.CHOICE, "shopkeeper offers a choice")
	gm.popup.close_all()
	town.get_node("Kavitha")._give("jasmine_flower")
	check(Relationships.get_points("kavitha") == Relationships.GIFT_LOVED, "Kavitha loves jasmine")
	gm.popup.close_all()
	Relationships.met.erase("ravi")
	Relationships.points.erase("ravi")
	Relationships.talked_today.erase("ravi")
	var talk := Relationships.talk("ravi")
	check(talk["first_meeting"] and talk["gift"].get("item_id", "") == "fishing_rod", "Ravi gives a fishing rod on first meeting")
	check(Relationships.get_points("ravi") == Relationships.TALK_POINTS, "first chat adds friendship")
	Relationships.talk("ravi")
	check(Relationships.get_points("ravi") == Relationships.TALK_POINTS, "second chat same day adds nothing")
	var gift := Relationships.give_gift("ravi", "karimeen")
	check(gift["taste"] == "loved" and Relationships.get_points("ravi") == 20 + 80, "loved gift adds 80")
	check(not Relationships.can_gift("ravi"), "one gift per day")
	set_date(GameClock.Season.WINTER, 18)
	var bday := Relationships.give_gift("anjali", "sunflower")
	check(bday["delta"] == 80, "non-birthday gift unmultiplied")
	Relationships.gifted_today.erase("ravi")
	var bday2 := Relationships.give_gift("ravi", "rohu")
	check(bday2["delta"] == Relationships.GIFT_LIKED * Relationships.BIRTHDAY_MULT, "birthday gift ×8")
	set_date(GameClock.Season.KHARIF, 2)

	print("[8] Festival")
	set_date(GameClock.Season.UGADI, 14)
	check(Calendar.festival_today().get("id", "") == "ugadi_mela", "Ugadi Mela on Ugadi 14")
	check(Weather.roll_for_date({"season": GameClock.Season.UGADI, "day": 14}) == Weather.SUNNY, "festival days are sunny")
	gm.goto_town("from_farm")
	await frames(3)
	check(world().get_node_or_null("Festival") != null, "festival decorations appear")
	inv().add_item("okra", 1)
	var gold0 := GameData.gold
	var res := gm.enter_festival_offering("okra")
	check(res["ok"] and GameData.gold == gold0 + 40 * 3, "offering pays 3× value")
	check(inv().count_item("bevu_bella") == 3, "festival prize received")
	check(Calendar.has_entered_festival("ugadi_mela"), "festival marked entered")
	check(Calendar.events_for_season(GameClock.Season.UGADI).size() >= 2, "calendar lists festival + birthdays")

	print("[9] Panchayat Hall")
	for b in ItemDB.get_bundles():
		for req in b["items"]:
			inv().add_item(req["item_id"], int(req["quantity"]))
	var emax := GameData.energy_max
	for b in ItemDB.get_bundles():
		gm.donate_to_bundle(b["id"])
	check(gm.hall_state["completed"].size() == 6, "all bundles complete")
	check(gm.hall_state["restored"], "hall restored")
	check(GameData.energy_max == emax + 20 + 30, "energy rewards applied")
	await get_tree().create_timer(0.3).timeout
	check(gm.popup._mode == gm.popup.Mode.DIALOGUE, "restoration scene plays")
	gm.popup.close_all()

	print("[10] UI views")
	gm.open_journal()
	await frames(2)
	check(gm.popup._mode == gm.popup.Mode.JOURNAL, "journal opens")
	for i in range(3):
		gm.popup._journal.cycle(1)
		await frames(1)
	gm.popup.close_all()
	gm.open_hall()
	await frames(2)
	check(gm.popup._mode == gm.popup.Mode.HALL, "hall board opens")
	gm.popup.close_all()
	var picked := [-1]
	gm.show_choice("Test", "Pick", ["A", "B"], func(i): picked[0] = i)
	await frames(2)
	check(gm.popup._mode == gm.popup.Mode.CHOICE, "choice opens")
	gm.popup.close_all()

	print("[11] Save / load round trip")
	set_date(GameClock.Season.RABI, 5)
	Weather.today = Weather.CLOUDY
	gm.save_game()
	var ravi_pts := Relationships.get_points("ravi")
	var stats_fish := GameData.get_stat("fish_caught")
	Relationships.reset_to_new_game()
	Calendar.reset_to_new_game()
	gm.hall_state = {}
	check(gm.continue_game(), "continue loads the save")
	await frames(3)
	check(Relationships.get_points("ravi") == ravi_pts, "friendship persisted")
	check(Calendar.has_entered_festival("ugadi_mela"), "festival progress persisted")
	check(gm.hall_state.get("restored", false), "hall progress persisted")
	check(Weather.today == Weather.CLOUDY, "weather persisted")
	check(GameData.get_stat("fish_caught") == stats_fish, "stats persisted")
	check(GameClock.current_season == GameClock.Season.RABI and GameClock.current_day == 5, "date persisted")

	print("[12] v1 save migration")
	var v1 := {"version": 1, "clock": {"hour": 6, "minute": 0, "day": 3, "season": 3, "year": 1, "days_elapsed": 2},
		"player": {"gold": 777}, "farm": {"tiles": {}}, "inventory": {}}
	var f := FileAccess.open(SaveManager._slot_path(TEST_SLOT), FileAccess.WRITE)
	f.store_string(JSON.stringify(v1))
	f.close()
	check(gm.continue_game(), "v1 save loads")
	await frames(3)
	check(GameData.gold == 777 and Relationships.get_points("ravi") == 0, "v1 defaults applied")
	check(not gm.get_forage_spots("trail").is_empty(), "forage generated for v1 save")
	check(not gm.hall_state.get("restored", true), "fresh hall state for v1 save")

	print("[13] Year rollover")
	set_date(GameClock.Season.WINTER, 28)
	GameClock.days_elapsed = 111
	GameClock.current_year = 1
	await sleep_overnight()
	check(GameClock.current_year == 2 and GameClock.current_season == GameClock.Season.UGADI, "Year 2 begins at Ugadi")

	_restore_slot()
	print("\nSmoke test: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
