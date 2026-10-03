extends Node
## Headless smoke test for the Phase 4 (Polish) build: the full year loop, the
## mines, forge, romance, requests, collection, save slots and demo ending,
## plus the release polish — audio, options, typewriter dialogue, fades,
## gamepad bindings, crash-safe saves and the credits.
##
## Run from the project root:
##   godot --headless res://tests/SmokeTest.tscn
## Exits with code 0 when every check passes, 1 otherwise. Uses save slot 2
## and restores whatever was there before (settings.cfg too).

const MAIN_SCENE := "res://scenes/Main.tscn"
const TEST_SLOT := 2

var gm: GameManager = null
var _passed := 0
var _failed := 0
var _slot_backup := ""
var _bak_backup := ""
var _settings_backup := ""


func _ready() -> void:
	# Watchdog: a script error aborts _run mid-way, so never hang forever.
	get_tree().create_timer(180.0).timeout.connect(func():
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
	if FileAccess.file_exists(SaveManager._backup_path(TEST_SLOT)):
		_bak_backup = FileAccess.get_file_as_string(SaveManager._backup_path(TEST_SLOT))
	if FileAccess.file_exists(Settings.PATH):
		_settings_backup = FileAccess.get_file_as_string(Settings.PATH)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _restore_slot() -> void:
	SaveManager.delete_slot(TEST_SLOT)
	if _slot_backup != "":
		_write(SaveManager._slot_path(TEST_SLOT), _slot_backup)
	if _bak_backup != "":
		_write(SaveManager._backup_path(TEST_SLOT), _bak_backup)
	if _settings_backup != "":
		_write(Settings.PATH, _settings_backup)
	elif FileAccess.file_exists(Settings.PATH):
		DirAccess.remove_absolute(Settings.PATH)
	Settings.load_settings()


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
	check(gm.popup._mode == gm.popup.Mode.DIALOGUE and gm.popup._dlg_speaker == "Grandmother's letter", "intro letter plays")
	gm.popup.close_all()
	check(GameClock.current_season == GameClock.Season.UGADI and GameClock.current_day == 1, "starts Ugadi 1")
	check(Weather.today == Weather.SUNNY, "first morning is sunny")
	check(gm.get_forage_spots("trail").size() >= GameManager.FORAGE_MIN, "trail forage generated")
	check(ItemDB.get_crops_for_season(GameClock.Season.WINTER).size() >= 5, "winter has crops")
	check(ItemDB.get_bundles().size() == 7, "seven Hall bundles loaded")
	check(Relationships.get_all_npcs().size() == 12, "twelve villagers loaded")
	check(Relationships.get_candidates().size() == 6, "six marriage candidates")

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
	var emax := GameData.energy_max
	for b in ItemDB.get_bundles():
		for req in b["items"]:
			inv().add_item(req["item_id"], int(req["quantity"]))
		gm.donate_to_bundle(b["id"])
	check(gm.hall_state["completed"].size() == 7, "all bundles complete")
	check(gm.hall_state["restored"], "hall restored")
	check(GameData.energy_max == emax + 20 + 30, "energy rewards applied")
	await get_tree().create_timer(0.3).timeout
	check(gm.popup._mode == gm.popup.Mode.DIALOGUE, "restoration scene plays")
	gm.popup.close_all()

	print("[10] UI views")
	gm.open_journal()
	await frames(2)
	check(gm.popup._mode == gm.popup.Mode.JOURNAL, "journal opens")
	for i in range(5):
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

	print("[14] Kanagiri Mines")
	gm.goto_town("from_farm")
	await frames(3)
	check(world().get_node_or_null("Selvam") != null and world().get_node_or_null("ToMines") != null, "town has the forge and mine road")
	var selvam_talk := Relationships.talk("selvam")
	check(selvam_talk["gift"].get("item_id", "") == "pickaxe", "Selvam gives a pickaxe on first meeting")
	gm.give_item("pickaxe", 1)
	gm.goto_mines("from_town")
	await frames(3)
	var mines := world()
	check(mines.name == "Mines" and mines.floor_num == 0, "mines entrance loads")
	check(mines.get_node_or_null("LadderDown") != null and mines.get_node_or_null("Lift") != null, "entrance has ladder and lift")
	check(gm.lift_floors().is_empty(), "lift locked before floor 5")
	gm.enter_mine_floor(1)
	await frames(3)
	mines = world()
	check(mines.floor_num == 1 and not mines.rocks.is_empty(), "floor 1 has rocks")
	check(gm.location_note == "Mines · Floor 1", "HUD shows the mine floor")
	var stone_before: int = inv().count_item("stone")
	for key in mines.rocks.keys():
		var parts: PackedStringArray = key.split(",")
		var t := Vector2i(int(parts[0]), int(parts[1]))
		for n in range(6):
			if mines.hit_rock(t):
				break
	check(mines.rocks.is_empty(), "every rock breaks")
	check(mines.ladder != null, "breaking the last rock reveals the ladder")
	check(GameData.get_stat("rocks_broken") > 0 and GameData.get_skill_xp("mining") > 0, "mining stats and xp")
	check(inv().count_item("stone") > stone_before or GameData.has_collected("copper_ore"), "rocks drop stone or ore")
	mines.descend()
	await frames(3)
	check(world().floor_num == 2 and int(gm.mine_state["deepest"]) == 2, "ladder leads down a floor")
	gm.enter_mine_floor(5)
	await frames(3)
	check(gm.lift_floors() == [5] and world().get_node_or_null("Lift") != null, "floor 5 unlocks the lift")
	check(Mines_rock_table_ok(), "deeper floors hold richer rocks")
	gm.enter_mine_floor(20)
	await frames(3)
	check(world().get_node_or_null("Shrine") != null and world().ladder == null, "floor 20 has the shrine and no ladder")
	world().visit_shrine()
	check(inv().count_item("tank_kings_seal") == 1 and gm.mine_state["seal_found"], "shrine gives the Tank King's Seal")
	gm.popup.close_all()
	check(Relationships.get_taste("anjali", "tank_kings_seal") == "loved", "Anjali loves the seal")

	print("[15] Forge & tool upgrades")
	GameData.gold = 600
	inv().remove_item("copper_ore", inv().count_item("copper_ore"))   # floor 1 may have dropped some
	check(not gm.upgrade_tool("hoe")["ok"], "upgrade needs ore")
	inv().add_item("copper_ore", 5)
	var up := gm.upgrade_tool("hoe")
	check(up["ok"] and GameData.get_tool_level("hoe") == 1 and GameData.gold == 100, "copper hoe upgrade")
	check(inv().count_item("copper_ore") == 0, "upgrade consumes ore")
	check(GameData.tool_reach("hoe") == 3 and GameData.tool_energy_cost("hoe", 2) == 1, "upgraded hoe reaches 3 tiles for less energy")
	check(GameData.tool_display_name("hoe") == "Copper Hoe", "upgraded tool name")
	gm.open_shop("blacksmith")
	await frames(2)
	check(gm.popup._mode == gm.popup.Mode.BLACKSMITH, "forge view opens")
	gm.popup.close_all()
	gm.open_shop("chai")
	await frames(2)
	check(gm.popup._mode == gm.popup.Mode.SHOP and "veg_biryani" in gm.shop_stock("chai"), "chai stall opens")
	gm.popup.close_all()
	check("jasmine_garland" in gm.shop_stock("general") and not "wedding_garland" in gm.shop_stock("general"), "general store stocks garlands")

	print("[16] Waking up at home")
	gm.goto_mines("from_town")
	await frames(3)
	var player_now = gm.get_active_player()
	player_now._try_sleep()
	check(not GameClock.is_paused(), "can't sleep with F away from home")
	await sleep_overnight()
	await frames(3)
	check(world().name == "Farm", "passing out in the mines wakes you at home")
	check(GameData.energy_current == GameData.energy_max / 2, "passing out away from home costs energy")
	var farm2 := world()
	farm2.player_instance.facing = 3   # right
	farm2._on_tool_used("hoe", Vector2i(5, 9))
	check(gm.farm_tiles.has("5,9") and gm.farm_tiles.has("6,9") and gm.farm_tiles.has("7,9"), "copper hoe tills a row of 3")

	print("[17] Romance")
	Relationships.points["arjun"] = 0
	Relationships.add_points("arjun", 3000)
	check(Relationships.get_hearts("arjun") == 8, "candidates cap at 8 hearts before dating")
	Relationships.gifted_today.clear()
	check(not Relationships.give_gift("arjun", "wedding_garland")["consumed"], "can't propose before dating")
	check(not Relationships.give_gift("kavitha", "jasmine_garland")["consumed"], "non-candidates decline garlands")
	var date := Relationships.give_gift("arjun", "jasmine_garland")
	check(date["consumed"] and Relationships.is_dating("arjun"), "jasmine garland starts dating")
	check("wedding_garland" in gm.shop_stock("general"), "wedding garland on sale once dating")
	Relationships.add_points("arjun", 1000)
	check(Relationships.get_hearts("arjun") == 10, "dating lifts the heart cap")
	Relationships.gifted_today.clear()
	var proposal := Relationships.give_gift("arjun", "wedding_garland")
	check(proposal["consumed"] and Relationships.engaged_to == "arjun", "wedding garland is a proposal")
	check(Relationships.relationship_status("arjun") == "Engaged", "engaged status")
	Relationships.wedding_day = GameClock.days_elapsed + 1
	GameClock.resume()
	GameClock._trigger_sleep()
	await frames(2)
	check(gm.popup._mode == gm.popup.Mode.SUMMARY, "wedding morning summary")
	gm.popup.close_all()
	check(Relationships.spouse == "arjun" and Relationships.engaged_to == "", "the wedding happens")
	gm.goto_farm("default")
	await frames(3)
	check(world().get_node_or_null("Spouse") != null, "spouse lives on the farm")
	check(Relationships.talk("arjun")["lines"][-1] in Relationships.get_npc("arjun")["dialogue"]["spouse"], "spouse dialogue")
	gm.goto_town("from_farm")
	await frames(3)
	check(world().get_node_or_null("Arjun") == null, "spouse no longer in the square")
	for i in range(8):
		if gm.apply_spouse_help() != "":
			break
	check(true, "spouse morning help runs")

	print("[18] Villager requests")
	set_date(GameClock.Season.UGADI, 3)
	Quests.reset_to_new_game()
	check(Quests.post_new() and Quests.has_active(), "a request is posted")
	var req: Dictionary = Quests.active.duplicate()
	check(Quests.is_obtainable(req["item_id"]), "requested item is obtainable")
	inv().add_item(req["item_id"], int(req["quantity"]))
	var gold_q := GameData.gold
	var pts_q := Relationships.get_points(req["npc_id"])
	var board = world().get_node("NoticeBoard")
	board.interact(gm.get_active_player())
	await frames(2)
	check(gm.popup._mode == gm.popup.Mode.CHOICE, "notice board offers delivery")
	gm.popup.close_all()
	var delivered := Quests.deliver(inv())
	check(delivered["ok"] and GameData.gold == gold_q + int(req["reward"]), "delivery pays the reward")
	check(Relationships.get_points(req["npc_id"]) > pts_q or Relationships.get_hearts(req["npc_id"]) >= 8, "delivery raises friendship")
	check(GameData.get_stat("requests_completed") == 1 and not Quests.has_active(), "request completed")
	Quests.post_new()
	Quests.active["due_day"] = GameClock.days_elapsed - 1
	Quests._on_day_started(1, GameClock.current_season)
	check(not Quests.last_expired.is_empty(), "overdue requests expire")

	print("[19] Collection & journal")
	# (The v1 load in [12] started a fresh collection, so check post-load finds.)
	check(GameData.has_collected("copper_ore") and GameData.has_collected("tank_kings_seal"), "finds are collected")
	check(not GameData.has_collected("hoe"), "tools aren't collectibles")
	gm.open_journal()
	await frames(2)
	for i in range(5):
		gm.popup._journal.show_tab(i)
		await frames(1)
	check(gm.popup._journal._body.get_child_count() > 0, "journal tabs build")
	gm.popup.close_all()

	print("[20] Settings")
	var relaxed_before := Settings.relaxed_clock
	Settings.relaxed_clock = true
	Settings.apply()
	check(is_equal_approx(GameClock.time_scale, Settings.RELAXED_SCALE), "relaxed clock slows time")
	Settings.relaxed_clock = relaxed_before
	Settings.apply()
	gm.open_options()
	await frames(2)
	check(gm.popup._mode == gm.popup.Mode.OPTIONS, "options open")
	gm.popup.close_all()

	print("[21] Save v3 round trip")
	gm.save_game()
	var deepest := int(gm.mine_state["deepest"])
	GameData.reset_to_new_game()
	Relationships.reset_to_new_game()
	Quests.reset_to_new_game()
	gm.mine_state = {}
	check(gm.continue_game(), "v3 save loads")
	await frames(3)
	check(GameData.get_tool_level("hoe") == 1, "tool levels persisted")
	check(int(gm.mine_state["deepest"]) == deepest and gm.mine_state["seal_found"], "mine progress persisted")
	check(Relationships.spouse == "arjun", "marriage persisted")
	check(GameData.has_collected("tank_kings_seal"), "collection persisted")
	check(gm.get_active_player() != null and world().get_node_or_null("Spouse") != null, "spouse on farm after load")
	var v2 := {"version": 2, "clock": {"hour": 6, "minute": 0, "day": 9, "season": 0, "year": 1, "days_elapsed": 36},
		"player": {"gold": 1234}, "farm": {"tiles": {}}, "inventory": {}, "social": {"points": {"ravi": 300}},
		"hall": {"completed": {}}, "weather": {}, "calendar": {}, "world": {}}
	var f2 := FileAccess.open(SaveManager._slot_path(TEST_SLOT), FileAccess.WRITE)
	f2.store_string(JSON.stringify(v2))
	f2.close()
	check(gm.continue_game(), "v2 save loads")
	await frames(3)
	check(GameData.gold == 1234 and Relationships.get_points("ravi") == 300, "v2 data kept")
	check(GameData.get_tool_level("hoe") == 0 and int(gm.mine_state["deepest"]) == 0 and Relationships.spouse == "", "v3 defaults for v2 save")

	print("[22] Title screen & save slots")
	gm.show_main_menu()
	await frames(3)
	var menu := world()
	check(menu.name == "MainMenu", "main menu shows")
	menu.show_slots(true)
	await frames(2)
	menu._pick_new_slot(TEST_SLOT, false)
	await frames(2)
	menu._name_edit.text = "Tester"
	menu._start_new()
	await frames(3)
	check(gm.current_slot == TEST_SLOT and GameData.player_name == "Tester", "new game in chosen slot with name")
	check(world().name == "Farm" and gm.popup._mode == gm.popup.Mode.DIALOGUE, "farm loads with intro letter")
	gm.popup.close_all()
	gm.save_game()
	check(SaveManager.describe_slot(TEST_SLOT).begins_with("Tester"), "slot summary shows the farmer")

	print("[23] Demo ending")
	gm.demo_override = 1
	set_date(GameClock.Season.WINTER, 28)
	var saved_before := FileAccess.get_file_as_string(SaveManager._slot_path(TEST_SLOT))
	GameClock.resume()
	GameClock._trigger_sleep()
	await frames(2)
	check(gm.popup._mode == gm.popup.Mode.SUMMARY and gm.popup._summary_on_close.is_valid(), "demo ends after Year 1")
	check(FileAccess.get_file_as_string(SaveManager._slot_path(TEST_SLOT)) == saved_before, "demo end doesn't overwrite the save")
	gm.popup._close_summary()
	await frames(2)
	check(gm.popup._mode == gm.popup.Mode.DIALOGUE, "thank-you message plays")
	for i in range(10):
		if gm.popup._mode != gm.popup.Mode.DIALOGUE:
			break
		gm.popup._advance_dialogue()
		await frames(1)
	await frames(3)
	check(not gm.in_game and world().name == "MainMenu", "demo returns to the title screen")
	gm.demo_override = -1

	await _polish_checks()

	_restore_slot()
	Audio.shutdown()
	await frames(3)
	print("\nSmoke test: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func Mines_rock_table_ok() -> bool:
	## Floor 1 never has gold; floor 18 can.
	var shallow := Mines.rock_table(1).map(func(e): return e[0])
	var deep := Mines.rock_table(18).map(func(e): return e[0])
	return not "gold" in shallow and "gold" in deep and "ruby" in deep


func _polish_checks() -> void:
	print("[24] Audio")
	var all_render := true
	for sfx in Audio.RECIPES:
		var stream: AudioStreamWAV = Audio.get_stream(sfx)
		if stream == null or stream.data.size() < 100:
			all_render = false
	check(all_render, "every sound effect synthesises")
	check(Audio.play("coin") and not Audio.play("no_such_sound"), "play() knows its sounds")
	var tune := Audio.render_music(Audio.MUSIC_BEAT * 4.0)
	check(tune.loop_mode == AudioStreamWAV.LOOP_FORWARD and tune.loop_end == int(Audio.MUSIC_BEAT * 4.0 * Audio.MIX_RATE), "music loops seamlessly")
	check(AudioServer.get_bus_index(Audio.MUSIC_BUS) != -1 and AudioServer.get_bus_index(Audio.SFX_BUS) != -1, "music and SFX buses exist")
	gm.new_game(TEST_SLOT, "Polish")
	await frames(3)
	gm.popup.close_all()
	Weather.today = Weather.RAIN
	await frames(2)
	check(Audio.get_ambience() == "rain", "rain ambience on rainy days")
	gm.enter_mine_floor(1)
	await frames(3)
	check(Audio.get_ambience() == "", "no rain heard in the mines")
	Weather.today = Weather.SUNNY
	gm.goto_farm("default")
	await frames(3)

	print("[25] Options")
	Settings.set_volume("music", 0.5)
	check(absf(Audio.get_bus_volume(Audio.MUSIC_BUS) - 0.5) < 0.01, "music volume reaches the bus")
	Settings.set_volume("sfx", 0.0)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index(Audio.SFX_BUS)), "zero volume mutes")
	Settings.set_text_speed("fast")
	Settings.set_pause_on_focus_loss(false)
	Settings.load_settings()
	check(Settings.text_speed == "fast" and not Settings.pause_on_focus_loss and is_equal_approx(Settings.music_volume, 0.5), "options persist to settings.cfg")
	Settings.reset_to_defaults()
	check(Settings.text_speed == "normal" and Settings.pause_on_focus_loss and is_equal_approx(Settings.sfx_volume, 0.8), "reset to defaults")
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(Audio.SFX_BUS)), "reset unmutes")
	gm.open_options()
	await frames(2)
	check(gm.popup._mode == gm.popup.Mode.OPTIONS, "options open with audio controls")
	gm.popup.close_all()

	print("[26] Typewriter dialogue")
	gm.show_dialogue("Test", ["A fairly long line of dialogue to type out.", "Second line."])
	await frames(2)
	check(not gm.popup.is_line_revealed(), "lines type out")
	var press := InputEventAction.new()
	press.action = "interact"
	press.pressed = true
	gm.popup._unhandled_input(press)
	check(gm.popup.is_line_revealed() and gm.popup._dlg_index == 0, "first press finishes the line")
	gm.popup._unhandled_input(press)
	check(gm.popup._dlg_index == 1, "next press moves on")
	await get_tree().create_timer(0.5).timeout
	check(gm.popup.is_line_revealed(), "a short line finishes typing on its own")
	gm.popup.close_all()
	Settings.set_text_speed("instant")
	gm.show_dialogue("Test", ["Instant."])
	await frames(1)
	check(gm.popup.is_line_revealed(), "instant text speed")
	gm.popup.close_all()
	Settings.set_text_speed("normal")

	print("[27] Fades, focus and level-ups")
	gm.goto_town("from_farm")
	await frames(2)
	check(gm.get_fade_alpha() > 0.5, "scene change fades from black")
	await get_tree().create_timer(GameManager.FADE_TIME + 0.2).timeout
	check(gm.get_fade_alpha() == 0.0, "fade clears")
	check(gm.pause_for_focus_loss() and gm.popup._mode == gm.popup.Mode.PAUSE, "losing focus pauses the game")
	await frames(2)
	var focused := get_viewport().gui_get_focus_owner()
	check(focused is Button and focused.text == "Resume", "menus take focus for gamepads")
	check(not gm.pause_for_focus_loss(), "focus loss doesn't stack menus")
	gm.popup.close_all()
	var level_before := GameData.get_skill_level("fishing")
	GameData.add_skill_xp("fishing", 100000)
	check(GameData.get_skill_level("fishing") == level_before + 1 and gm.hud.notif_label.text.begins_with("Fishing level"), "level-ups are announced")
	GameData.energy_current = 5
	GameData.emit_signal("energy_changed", 5, GameData.energy_max)
	check(gm.hud.is_energy_low(), "low energy warning")
	GameData.restore_energy()

	print("[28] Gamepad")
	var pad_ok := true
	for action in ["move_up", "move_down", "move_left", "move_right", "interact", "use_tool",
			"hotbar_prev", "hotbar_next", "inventory_toggle", "journal", "ui_cancel"]:
		var has_pad := false
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton:
				has_pad = true
		pad_ok = pad_ok and has_pad
	check(pad_ok, "every action has a gamepad button")
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = 1.0
	check(InputMap.event_is_action(stick, "move_right"), "left stick moves")
	var start := InputEventJoypadButton.new()
	start.button_index = JOY_BUTTON_START
	start.pressed = true
	check(InputMap.event_is_action(start, "ui_cancel"), "Start opens the pause menu")

	print("[29] Crash-safe saves")
	var path := SaveManager._slot_path(TEST_SLOT)
	GameData.gold = 4242
	gm.save_game()
	GameData.gold = 99
	gm.save_game()
	check(FileAccess.file_exists(SaveManager._backup_path(TEST_SLOT)) and not FileAccess.file_exists(path + ".tmp"), "previous save kept as a backup")
	_write(path, "{ this is not json")
	check(SaveManager.describe_slot(TEST_SLOT).begins_with("Polish"), "damaged slot still lists its backup")
	check(gm.continue_game(), "damaged save falls back to the backup")
	await frames(3)
	check(SaveManager.last_load_recovered and GameData.gold == 4242, "backup restores the earlier save")
	gm.save_game()
	check(int(SaveManager._read_save(path).get("player", {}).get("gold", 0)) == 4242, "next save repairs the slot")
	_write(path, "garbage")
	_write(SaveManager._backup_path(TEST_SLOT), "garbage")
	check(SaveManager.describe_slot(TEST_SLOT) == "Damaged save", "unreadable slot is flagged")
	check(not gm.continue_game(), "an unreadable slot doesn't load")
	SaveManager.delete_slot(TEST_SLOT)
	check(not SaveManager.slot_exists(TEST_SLOT), "deleting a slot removes its backup too")
	gm.demo_override = 1
	GameClock.current_year = 2
	check(not gm.save_game() and not SaveManager.slot_exists(TEST_SLOT), "a finished demo never saves Year 2")
	gm.demo_override = -1
	GameClock.current_year = 1

	print("[30] Credits & version")
	gm.show_main_menu()
	await frames(3)
	var menu := world()
	menu.show_credits()
	await frames(2)
	var credit_text := ""
	for child in menu._box.get_children():
		if child is Label:
			credit_text += child.text
	check("Godot Engine" in credit_text and "MIT" in credit_text, "credits carry the Godot licence notice")
	check(String(ProjectSettings.get_setting("application/config/version")).begins_with("0.9"), "release-candidate version")
	menu.show_main()
	await frames(2)
