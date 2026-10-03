extends Node
class_name GameManager
## Main.gd — the persistent game manager and root of the scene tree.
##
## Responsibilities:
##   - Owns the swappable "world" scenes (MainMenu ↔ Farm ↔ Town ↔ Trail ↔ Mines) loaded into
##     the CurrentScene container, so autoloads and the persistent UI survive.
##   - High-level flow: new game, continue, quit, scene transitions.
##   - Cross-scene state that must outlive any single scene:
##       * farm_tiles     — authoritative farm plot simulation state
##       * inventory_data — the player's inventory (survives Farm↔Town trips)
##       * forage_data    — today's forageable spawns per location
##       * hall_state     — Panchayat Hall offerings (bundles)
##       * mine_state     — current / deepest Kanagiri Mines floor
##       * spawn_target   — which spawn marker the next world should use
##   - Overnight simulation (crop growth, season withering, rain, forage
##     respawn) + save/load orchestration.
##   - Gameplay services shared by several scenes: fishing, foraging, festival
##     offerings, Hall donations, the mines, shops and Selvam's tool upgrades.
##   - The mornings after: weddings, your spouse's help, waking up at home,
##     and (in demo builds) the end of the demo after Year 1.
##   - Presentation: fade-ins between scenes, music, and level-up fanfares.
##   - Window lifecycle: autosave when the window is closed mid-game, and the
##     pause menu when the window loses focus (see Settings).
##
## Accessed from anywhere via the static `GameManager.instance`.

# ---------------------------------------------------------------------------
# Global access
# ---------------------------------------------------------------------------

static var instance: GameManager = null

# ---------------------------------------------------------------------------
# Scene paths
# ---------------------------------------------------------------------------

const MAIN_MENU_SCENE: String = "res://scenes/UI/MainMenu.tscn"
const FARM_SCENE:      String = "res://scenes/World/Farm.tscn"
const TOWN_SCENE:      String = "res://scenes/World/Town.tscn"
const TRAIL_SCENE:     String = "res://scenes/World/GhatsTrail.tscn"
const MINES_SCENE:     String = "res://scenes/World/Mines.tscn"

## How long the fade from black takes after a scene change.
const FADE_TIME: float = 0.35

## Where forageables can appear each morning, per location (tile rects).
const FORAGE_AREAS: Dictionary = {
	"trail": Rect2i(6, 2, 11, 12),
}
const FORAGE_MIN: int = 4
const FORAGE_MAX: int = 6

## What each shop sells beyond Kavitha's seasonal seeds (see shop_stock()).
const GENERAL_STAPLES: Array = ["idli", "dosa", "banana_leaf_rice", "jasmine_garland"]
const CHAI_MENU: Array = ["masala_chai", "filter_coffee", "medu_vada", "lemon_rice", "veg_biryani"]
const SHOP_TITLES: Dictionary = {
	"general": "Kavitha's General Store",
	"chai":    "Farida's Chai Kadai",
}

const INTRO_LINES: Array = [
	"A letter was waiting on the farmhouse table...",
	"\"My dear one — if you're reading this, the farm is yours now. It has been quiet too long.\"",
	"\"The soil remembers kindness. So do the people of Viralpadi. Go and meet them.\"",
	"\"And if you can, help Meenakshi bring the old Panchayat Hall back to life.\" — Paati Amma",
	"(Till with the hoe, plant seeds, water daily, and ship crops in the chest. Press J for your journal, Esc for help and options.)",
]
const DEMO_END_LINES: Array = [
	"And so your first year in Viralpadi Valley comes to a close.",
	"Thank you for playing the Indian Valley demo!",
	"The full game continues into Year 2 and beyond — with more to discover in the valley.",
]

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal inventory_updated()          ## Inventory contents/selection changed.
signal farm_updated()               ## Farm tile state changed (e.g. overnight growth).
signal game_state_changed(in_game: bool)
signal hall_changed()                ## A Panchayat Hall bundle was offered to.

# ---------------------------------------------------------------------------
# Cross-scene state
# ---------------------------------------------------------------------------

## Authoritative farm plot state. Keyed by "x,y" tile string; value:
##   { "state": "tilled"|"planted", "crop_id": String,
##     "planted_day": int, "watered_day": int, "progress": int, "stage": int }
var farm_tiles: Dictionary = {}

## Player inventory snapshot: { "slots": Array, "hotbar_index": int }
## Empty means "new game — hand out starter items".
var inventory_data: Dictionary = {}

## Today's forage spawns: { location: [ { "x": int, "y": int, "item_id": String } ] }
var forage_data: Dictionary = {}

## Panchayat Hall progress:
##   { "donated": { bundle_id: { item_id: qty } }, "completed": { bundle_id: true },
##     "restored": bool, "intro_seen": bool }
var hall_state: Dictionary = {}

## Kanagiri Mines: { "floor": int (0 = entrance), "deepest": int, "seal_found": bool }
var mine_state: Dictionary = {}

## Extra location text for the HUD (e.g. the mine floor), set by the world.
var location_note: String = ""

## Force demo mode on/off in tests (-1 = decide from the build).
var demo_override: int = -1

## Which spawn marker a freshly loaded world should place the player at.
var spawn_target: String = "default"

## Whether we're currently in a playable world (vs. the main menu).
var in_game: bool = false

## Save slot in use this session (single-slot for the vertical slice).
var current_slot: int = 0

# ---------------------------------------------------------------------------
# Nodes
# ---------------------------------------------------------------------------

@onready var current_scene_node: Node = $CurrentScene
@onready var hud:   CanvasLayer = $HUD
@onready var popup: CanvasLayer = $Popup

## Full-screen black overlay used for fade-ins (built in _ready).
var _fade_layer: CanvasLayer = null
var _fade_rect:  ColorRect   = null
var _fade_tween: Tween       = null

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _enter_tree() -> void:
	# Set the global reference before any child (HUD/Popup/world) runs _ready.
	instance = self


func _ready() -> void:
	add_to_group("game")
	_build_fade()
	# We decide what happens on window close (autosave first).
	get_tree().set_auto_accept_quit(false)
	GameData.skill_leveled.connect(_on_skill_leveled)
	Audio.play_music()
	show_main_menu()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			quit_game()
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			if Settings.pause_on_focus_loss:
				pause_for_focus_loss()


func pause_for_focus_loss() -> bool:
	## Open the pause menu if the player is mid-game with nothing else open.
	if not in_game or popup == null or popup._mode != popup.Mode.NONE:
		return false
	open_pause_menu()
	return true


func _exit_tree() -> void:
	if instance == self:
		instance = null

# ---------------------------------------------------------------------------
# Scene management
# ---------------------------------------------------------------------------

func _load_scene(path: String) -> void:
	for child in current_scene_node.get_children():
		child.queue_free()

	var packed: PackedScene = load(path)
	if packed == null:
		push_error("GameManager: failed to load scene: %s" % path)
		return

	var scene_instance = packed.instantiate()
	current_scene_node.add_child(scene_instance)
	fade_in()


func goto_world(path: String, spawn: String = "default") -> void:
	## Transition between playable world scenes (Farm ↔ Town).
	spawn_target = spawn
	Audio.play("warp")
	call_deferred("_load_scene", path)


func goto_farm(spawn: String = "default") -> void:
	goto_world(FARM_SCENE, spawn)


func goto_town(spawn: String = "default") -> void:
	goto_world(TOWN_SCENE, spawn)


func goto_trail(spawn: String = "default") -> void:
	goto_world(TRAIL_SCENE, spawn)


func goto_mines(spawn: String = "from_town") -> void:
	goto_world(MINES_SCENE, spawn)


func get_active_world() -> Node:
	var count := current_scene_node.get_child_count()
	for i in range(count - 1, -1, -1):
		var child := current_scene_node.get_child(i)
		if not child.is_queued_for_deletion():
			return child
	return null

# ---------------------------------------------------------------------------
# Flow: main menu / new game / continue / quit
# ---------------------------------------------------------------------------

func show_main_menu() -> void:
	in_game = false
	location_note = ""
	GameClock.pause()
	_update_ui_visibility()
	emit_signal("game_state_changed", in_game)
	call_deferred("_load_scene", MAIN_MENU_SCENE)


func new_game(slot: int = -1, player_name: String = "") -> void:
	## Start fresh in `slot` (default: the current slot). The intro letter plays
	## once the farm has loaded.
	if slot >= 0:
		current_slot = slot
	GameClock.reset_to_new_game()
	GameData.reset_to_new_game()
	if player_name.strip_edges() != "":
		GameData.player_name = player_name.strip_edges().left(16)
	Calendar.reset_to_new_game()
	Relationships.reset_to_new_game()
	Weather.reset_to_new_game()
	Quests.reset_to_new_game()
	farm_tiles = {}
	inventory_data = {}
	hall_state = _default_hall_state()
	mine_state = _default_mine_state()
	generate_forage()
	spawn_target = "default"
	in_game = true
	_update_ui_visibility()
	emit_signal("game_state_changed", in_game)
	GameClock.resume()
	call_deferred("_load_scene", FARM_SCENE)
	call_deferred("_play_intro")


func _play_intro() -> void:
	show_dialogue("Grandmother's letter", INTRO_LINES)


func load_slot(slot: int) -> bool:
	current_slot = slot
	return continue_game()


func continue_game() -> bool:
	if not has_save():
		return false
	if not SaveManager.load_game(current_slot):
		return false
	if SaveManager.last_load_recovered:
		call_deferred("show_notification", "Your save was damaged — restored the previous one")

	var data: Dictionary = SaveManager.last_loaded
	var farm: Dictionary = data.get("farm", {})
	farm_tiles = farm.get("tiles", {})
	inventory_data = data.get("inventory", {})
	forage_data = data.get("world", {}).get("forage", {})
	if forage_data.is_empty():
		generate_forage()
	hall_state = _default_hall_state()
	for key in data.get("hall", {}):
		hall_state[key] = data["hall"][key]
	mine_state = _default_mine_state()
	for key in data.get("mines", {}):
		mine_state[key] = data["mines"][key]
	mine_state["floor"] = 0
	mine_state["deepest"] = int(mine_state.get("deepest", 0))
	spawn_target = "default"
	in_game = true
	_update_ui_visibility()
	emit_signal("game_state_changed", in_game)
	GameClock.resume()
	call_deferred("_load_scene", FARM_SCENE)
	return true


func has_save() -> bool:
	return SaveManager.slot_exists(current_slot)


func has_any_save() -> bool:
	return SaveManager.most_recent_slot() != -1


func quit_game() -> void:
	## Quitting mid-game (window close, or a quit button) saves first.
	if in_game:
		save_game()
	Audio.shutdown()
	# Give the audio server a moment to let go of its playbacks.
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()

# ---------------------------------------------------------------------------
# Saving
# ---------------------------------------------------------------------------

func save_game() -> bool:
	# A finished demo never writes Year 2 over the last Year 1 save.
	if is_demo() and GameClock.current_year > 1:
		return false
	var extra := {
		"farm":      {"tiles": farm_tiles},
		"inventory": inventory_data,
		"world":     {"forage": forage_data},
		"hall":      hall_state,
		"mines":     mine_state,
	}
	return SaveManager.save_game(current_slot, extra)

# ---------------------------------------------------------------------------
# Overnight simulation
# ---------------------------------------------------------------------------

func on_overnight(earnings: int) -> void:
	## Called by GameData after the calendar has advanced to the new morning.
	var report := {
		"earnings":   earnings,
		"new_season": GameClock.is_new_season_morning(),
		"new_year":   GameClock.is_new_year_morning(),
	}
	report["withered"] = advance_farm_day()
	report["rain_watered"] = apply_weather_to_farm()
	generate_forage()
	report["weather"]   = Weather.today
	report["forecast"]  = Weather.tomorrow
	report["festival"]  = Calendar.festival_today()
	report["birthdays"] = Relationships.birthdays_today()
	report["wedding"]   = Relationships.check_wedding()
	if report["wedding"] == "":
		report["spouse_help"] = apply_spouse_help()
	report["request"]   = Quests.describe()
	report["passed_out"] = _wake_at_home()
	Audio.play("sleep")
	if report["new_year"]:
		report["year_review"] = build_year_review(GameClock.current_year - 1)
		report["demo_end"] = is_demo()
	# The demo ends after Year 1; keep the last save on Winter 28 instead.
	if not report.get("demo_end", false):
		save_game()
	if popup and popup.has_method("show_day_summary"):
		popup.show_day_summary(report)


func _wake_at_home() -> bool:
	## Everyone wakes up at home. Returns true if the player passed out away
	## from the farm (they wake with only half their energy).
	mine_state["floor"] = 0
	var world := get_active_world()
	if world == null or world.name == "Farm" or not in_game:
		return false
	GameData.energy_current = GameData.energy_max / 2
	GameData.emit_signal("energy_changed", GameData.energy_current, GameData.energy_max)
	goto_farm("default")
	return true


func apply_spouse_help() -> String:
	## Your spouse sometimes waters the crops or leaves you breakfast.
	## Returns a line for the day summary ("" when nothing happened).
	var spouse := Relationships.spouse
	if spouse == "":
		return ""
	var spouse_name := Relationships.get_name_of(spouse)
	var roll := randf()
	if roll < 0.35 and not Weather.is_raining():
		var watered := 0
		for key in farm_tiles:
			var data: Dictionary = farm_tiles[key]
			if data.get("state", "") == "planted":
				data["watered_day"] = GameClock.days_elapsed
				watered += 1
		if watered > 0:
			emit_signal("farm_updated")
			return "%s watered all the crops this morning." % spouse_name
	if roll < 0.65:
		var meal: String = ["idli", "dosa", "masala_chai", "lemon_rice"][randi() % 4]
		if give_item(meal, 1):
			return "%s made you %s for breakfast." % [spouse_name, ItemDB.get_item(meal).get("name", meal)]
	return ""


func is_demo() -> bool:
	if demo_override != -1:
		return demo_override == 1
	return OS.has_feature("demo") or bool(ProjectSettings.get_setting("indian_valley/demo_build", false))


func finish_demo() -> void:
	## Called when the Year 1 summary closes in a demo build.
	show_dialogue("Indian Valley", DEMO_END_LINES, func(): show_main_menu())


func advance_farm_day() -> int:
	## Grow every watered, planted tile by one day. Watering "expires" naturally
	## because a tile only counts as watered on the exact day it was watered.
	## On the first morning of a season, crops that can't grow in the new season
	## wither. Returns how many crops withered.
	var new_season := GameClock.is_new_season_morning()
	var season_key := GameClock.season_key()
	var withered := 0

	for key in farm_tiles:
		var data: Dictionary = farm_tiles[key]
		if data.get("state", "") != "planted":
			continue

		var crop = ItemDB.get_crop(data.get("crop_id", ""))
		if crop.is_empty():
			continue

		if new_season and not season_key in crop.get("seasons", []):
			data["state"] = "dead"
			withered += 1
			continue

		# A tile advances only if it was watered on the day that just ended.
		var watered_yesterday := int(data.get("watered_day", -1)) == GameClock.days_elapsed - 1
		if not watered_yesterday:
			continue

		var growth_days: int = crop.get("growth_days", 1)
		if int(data.get("progress", 0)) < growth_days:
			data["progress"] = int(data.get("progress", 0)) + 1
			var stages: int = max(1, crop.get("stages", 4))
			data["stage"] = int(float(data["progress"]) / growth_days * (stages - 1))

	emit_signal("farm_updated")
	return withered


func apply_weather_to_farm() -> bool:
	## Rain and storms water every tilled or planted tile for today.
	if not Weather.is_raining():
		return false
	for key in farm_tiles:
		var data: Dictionary = farm_tiles[key]
		if data.get("state", "") in ["tilled", "planted"]:
			data["watered_day"] = GameClock.days_elapsed
	emit_signal("farm_updated")
	return true


func build_year_review(year: int) -> Dictionary:
	return {
		"year":         year,
		"earned":       GameData.get_stat("total_earned"),
		"harvested":    GameData.get_stat("crops_harvested"),
		"fish":         GameData.get_stat("fish_caught"),
		"foraged":      GameData.get_stat("items_foraged"),
		"festivals":    GameData.get_stat("festivals_attended"),
		"friends":      Relationships.count_friends(4),
		"bundles_done": hall_state.get("completed", {}).size(),
		"bundles_total":ItemDB.get_bundles().size(),
		"restored":     hall_state.get("restored", false),
		"deepest":      int(mine_state.get("deepest", 0)),
		"requests":     GameData.get_stat("requests_completed"),
		"spouse":       Relationships.get_name_of(Relationships.spouse) if Relationships.spouse != "" else "",
	}

# ---------------------------------------------------------------------------
# Foraging
# ---------------------------------------------------------------------------

func generate_forage() -> void:
	## Scatter today's seasonal forageables across each forage area.
	forage_data = {}
	var pool := ItemDB.get_items_for_season("forage", GameClock.current_season)
	for location in FORAGE_AREAS:
		var spots: Array = []
		if not pool.is_empty():
			var area: Rect2i = FORAGE_AREAS[location]
			var count := randi_range(FORAGE_MIN, FORAGE_MAX)
			var used := {}
			var tries := 0
			while spots.size() < count and tries < 100:
				tries += 1
				var x := area.position.x + randi() % area.size.x
				var y := area.position.y + randi() % area.size.y
				var k := "%d,%d" % [x, y]
				if used.has(k):
					continue
				used[k] = true
				spots.append({"x": x, "y": y, "item_id": pool[randi() % pool.size()]["id"]})
		forage_data[location] = spots


func get_forage_spots(location: String) -> Array:
	return forage_data.get(location, [])


func pick_forage(location: String, tile: Vector2i) -> bool:
	## Collect the forageable at `tile`. Returns true if it was picked up.
	var spots: Array = forage_data.get(location, [])
	for i in range(spots.size()):
		var spot: Dictionary = spots[i]
		if int(spot["x"]) != tile.x or int(spot["y"]) != tile.y:
			continue
		var item_id: String = spot["item_id"]
		if not give_item(item_id, 1):
			show_notification("Inventory full")
			return false
		spots.remove_at(i)
		GameData.add_skill_xp("foraging", 3)
		GameData.record_stat("items_foraged")
		Audio.play("pickup")
		show_notification("Found %s" % ItemDB.get_item(item_id).get("name", item_id))
		return true
	return false

# ---------------------------------------------------------------------------
# Fishing
# ---------------------------------------------------------------------------

func start_fishing(location: String) -> void:
	if popup and popup.has_method("open_fishing"):
		popup.open_fishing(location)


func choose_fish(location: String) -> Dictionary:
	## Pick a fish that can bite here, now. Easier fish are more common.
	var candidates: Array = []
	var total_weight := 0.0
	for fish in ItemDB.get_items_for_season("fish", GameClock.current_season):
		if not location in fish.get("locations", []):
			continue
		if fish.get("weather", "") == "rain" and not Weather.is_raining():
			continue
		var weight := 1.0 / float(max(1, int(fish.get("difficulty", 1))))
		candidates.append([fish, weight])
		total_weight += weight
	if candidates.is_empty():
		return {}
	var r := randf() * total_weight
	for c in candidates:
		r -= c[1]
		if r <= 0.0:
			return c[0]
	return candidates[-1][0]


func on_fishing_finished(fish_id: String) -> void:
	## Called by the fishing minigame. An empty id means the fish got away.
	if fish_id == "":
		Audio.play("miss")
		show_notification("The fish got away...")
		return
	var fish := ItemDB.get_item(fish_id)
	if not give_item(fish_id, 1):
		show_notification("Inventory full — you let the %s go" % fish.get("name", "fish"))
		return
	GameData.add_skill_xp("fishing", 5 + 2 * int(fish.get("difficulty", 1)))
	GameData.record_stat("fish_caught")
	Audio.play("catch")
	show_notification("Caught a %s!" % fish.get("name", fish_id))

# ---------------------------------------------------------------------------
# Panchayat Hall
# ---------------------------------------------------------------------------

func _default_hall_state() -> Dictionary:
	return {"donated": {}, "completed": {}, "restored": false, "intro_seen": false}

# ---------------------------------------------------------------------------
# Kanagiri Mines
# ---------------------------------------------------------------------------

func _default_mine_state() -> Dictionary:
	return {"floor": 0, "deepest": 0, "seal_found": false}


func enter_mine_floor(floor_num: int) -> void:
	## Travel to a mine floor (0 = the entrance) by ladder or lift.
	floor_num = clampi(floor_num, 0, 20)
	mine_state["floor"] = floor_num
	mine_state["deepest"] = maxi(int(mine_state.get("deepest", 0)), floor_num)
	goto_world(MINES_SCENE, "from_above" if floor_num > 0 else "from_below")


func lift_floors() -> Array:
	## Floors the old lift can reach (every 5th floor you've been to).
	var floors: Array = []
	var f := 5
	while f <= int(mine_state.get("deepest", 0)):
		floors.append(f)
		f += 5
	return floors

# ---------------------------------------------------------------------------
# Shops and the forge
# ---------------------------------------------------------------------------

func shop_stock(shop_id: String) -> Array:
	## Item ids for sale, in display order.
	if shop_id == "chai":
		return CHAI_MENU.duplicate()
	var stock: Array = []
	var season_name := GameClock.season_key()
	for crop in ItemDB.get_all_crops():
		if season_name in crop.get("seasons", []):
			var seed_id: String = crop.get("seed_id", "")
			if not ItemDB.get_item(seed_id).is_empty() and not stock.has(seed_id):
				stock.append(seed_id)
	for staple in GENERAL_STAPLES:
		if not ItemDB.get_item(staple).is_empty():
			stock.append(staple)
	if not Relationships.dating.is_empty() and Relationships.spouse == "":
		stock.append(Relationships.PROPOSAL_ITEM)
	return stock


func upgrade_tool(tool_id: String) -> Dictionary:
	## Selvam upgrades a tool on the spot. Returns { "ok": bool, "message": String }.
	var inv := get_active_inventory()
	var cost := GameData.next_tool_upgrade(tool_id)
	if cost.is_empty():
		return {"ok": false, "message": "That tool can't be improved any further."}
	if inv == null or inv.count_item(tool_id) == 0:
		return {"ok": false, "message": "Bring the tool with you first."}
	if inv.count_item(cost["ore"]) < int(cost["ore_qty"]):
		return {"ok": false, "message": "You need %d %s." % [cost["ore_qty"], ItemDB.get_item(cost["ore"]).get("name", cost["ore"])]}
	if GameData.gold < int(cost["gold"]):
		return {"ok": false, "message": "You need ₹%d." % cost["gold"]}
	inv.remove_item(cost["ore"], int(cost["ore_qty"]))
	GameData.spend_gold(int(cost["gold"]))
	GameData.set_tool_level(tool_id, GameData.get_tool_level(tool_id) + 1)
	Audio.play("level_up")
	emit_signal("inventory_updated")
	return {"ok": true, "message": "Selvam hands back your %s!" % GameData.tool_display_name(tool_id)}


func is_bundle_complete(bundle_id: String) -> bool:
	return hall_state.get("completed", {}).has(bundle_id)


func get_bundle_donated(bundle_id: String, item_id: String) -> int:
	return int(hall_state.get("donated", {}).get(bundle_id, {}).get(item_id, 0))


func donate_to_bundle(bundle_id: String) -> int:
	## Move every matching item the player carries into a bundle.
	## Returns the number of items donated.
	var bundle := ItemDB.get_bundle(bundle_id)
	var inv := get_active_inventory()
	if bundle.is_empty() or inv == null or is_bundle_complete(bundle_id):
		return 0

	var donated: Dictionary = hall_state["donated"].get(bundle_id, {})
	var moved := 0
	for req in bundle.get("items", []):
		var item_id: String = req["item_id"]
		var need := int(req["quantity"]) - int(donated.get(item_id, 0))
		var take := mini(need, inv.count_item(item_id))
		if take > 0 and inv.remove_item(item_id, take):
			donated[item_id] = int(donated.get(item_id, 0)) + take
			moved += take
	hall_state["donated"][bundle_id] = donated

	var complete := true
	for req in bundle.get("items", []):
		if int(donated.get(req["item_id"], 0)) < int(req["quantity"]):
			complete = false
			break
	if complete:
		hall_state["completed"][bundle_id] = true
		_grant_reward(bundle.get("reward", {}))
		Audio.play("fanfare")
		show_notification("%s complete! Reward: %s" % [bundle.get("name", ""), bundle.get("reward", {}).get("text", "")])
		_check_hall_restored()
	emit_signal("hall_changed")
	return moved


func _grant_reward(reward: Dictionary) -> void:
	if reward.has("gold"):
		GameData.add_gold(int(reward["gold"]))
	if reward.has("energy_max"):
		GameData.energy_max += int(reward["energy_max"])
		GameData.restore_energy()
	for entry in reward.get("items", []):
		if not give_item(entry["item_id"], int(entry["quantity"])):
			# No room — pay out the value instead of losing the reward.
			var value := int(ItemDB.get_item(entry["item_id"]).get("buy_price", 0)) * int(entry["quantity"])
			GameData.add_gold(value)


func _check_hall_restored() -> void:
	if hall_state.get("restored", false):
		return
	for bundle in ItemDB.get_bundles():
		if not is_bundle_complete(bundle["id"]):
			return
	hall_state["restored"] = true
	var completion := ItemDB.get_bundle_completion()
	_grant_reward(completion)
	# Let the bundle popup close first, then play the restoration scene.
	var lines: Array = completion.get("lines", ["The Panchayat Hall is restored!"])
	get_tree().create_timer(0.1).timeout.connect(func(): show_dialogue("Panchayat Hall", lines))

# ---------------------------------------------------------------------------
# Festivals
# ---------------------------------------------------------------------------

func enter_festival_offering(item_id: String) -> Dictionary:
	## Offer a held item at today's festival stall. Returns the result
	## { "ok": bool, "lines": Array }.
	var festival := Calendar.festival_today()
	if festival.is_empty():
		return {"ok": false, "lines": ["The stall is empty today."]}
	var inv := get_active_inventory()
	if inv == null or not inv.remove_item(item_id, 1):
		return {"ok": false, "lines": ["You don't have that anymore."]}

	var item := ItemDB.get_item(item_id)
	var value := int(item.get("sell_price", 0))
	var prize_gold := value * 3
	var tier := "a heartfelt"
	if value >= 100:
		tier = "a magnificent"
	elif value >= 50:
		tier = "a fine"

	Calendar.mark_festival_entered(festival["id"])
	GameData.record_stat("festivals_attended")
	GameData.add_gold(prize_gold)
	Relationships.add_points_all(40)
	Audio.play("fanfare")
	var prize_id: String = festival.get("prize_item", "")
	var prize_qty := int(festival.get("prize_qty", 1))
	var lines: Array = ["What %s offering — %s!" % [tier, item.get("name", item_id)]]
	if prize_id != "" and give_item(prize_id, prize_qty):
		lines.append("You receive ₹%d and %d × %s." % [prize_gold, prize_qty, ItemDB.get_item(prize_id).get("name", prize_id)])
	else:
		lines.append("You receive ₹%d." % prize_gold)
	lines.append("The whole village cheers. (Everyone's friendship rose.)")
	return {"ok": true, "lines": lines}

# ---------------------------------------------------------------------------
# Inventory bridge (Inventory node ↔ persistent state ↔ HUD)
# ---------------------------------------------------------------------------

func set_inventory_data(data: Dictionary) -> void:
	inventory_data = data
	refresh_hud()
	emit_signal("inventory_updated")


func get_active_player() -> Node:
	return get_tree().get_first_node_in_group("player")


func get_active_inventory() -> Node:
	var player := get_active_player()
	if player:
		return player.get_node_or_null("Inventory")
	return null


func give_item(item_id: String, quantity: int = 1) -> bool:
	## Add items to the player's inventory. Returns false when it doesn't fit.
	var inv := get_active_inventory()
	if inv == null:
		return false
	if inv.count_item(item_id) == 0 and inv.is_full():
		return false
	return inv.add_item(item_id, quantity)


func get_held_item_id() -> String:
	var inv := get_active_inventory()
	if inv == null:
		return ""
	return inv.get_hotbar_item().get("item_id", "")


func set_hotbar_index(index: int) -> void:
	var inv := get_active_inventory()
	if inv:
		inv.set_hotbar_index(index)

# ---------------------------------------------------------------------------
# UI proxies
# ---------------------------------------------------------------------------

func refresh_hud() -> void:
	if hud and hud.has_method("refresh_from_state"):
		hud.refresh_from_state()


func show_notification(message: String) -> void:
	if hud and hud.has_method("show_notification"):
		hud.show_notification(message)


func show_dialogue(speaker: String, lines: Array, on_done: Callable = Callable()) -> void:
	if popup and popup.has_method("show_dialogue"):
		popup.show_dialogue(speaker, lines, on_done)


func open_shop(shop_id: String = "general") -> void:
	if shop_id == "blacksmith":
		if popup and popup.has_method("open_blacksmith"):
			popup.open_blacksmith()
		return
	if popup and popup.has_method("open_shop"):
		popup.open_shop(shop_id)


func open_options() -> void:
	if popup and popup.has_method("open_options"):
		popup.open_options()


func toggle_inventory_screen() -> void:
	if popup and popup.has_method("toggle_inventory_screen"):
		popup.toggle_inventory_screen()


func show_choice(speaker: String, prompt: String, options: Array, on_choice: Callable) -> void:
	if popup and popup.has_method("show_choice"):
		popup.show_choice(speaker, prompt, options, on_choice)


func open_journal() -> void:
	if popup and popup.has_method("open_journal"):
		popup.open_journal()


func open_hall() -> void:
	if popup and popup.has_method("open_hall"):
		popup.open_hall()


func open_pause_menu() -> void:
	if popup and popup.has_method("open_pause_menu"):
		popup.open_pause_menu()

# ---------------------------------------------------------------------------
# Presentation
# ---------------------------------------------------------------------------

func _build_fade() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 30   # above the HUD and popups
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_rect)


func fade_in() -> void:
	## Snap to black and fade the freshly loaded scene in. Purely visual:
	## the scene is already live, so nothing waits on the fade.
	if _fade_rect == null:
		return
	if _fade_tween:
		_fade_tween.kill()
	_fade_rect.color.a = 1.0
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade_rect, "color:a", 0.0, FADE_TIME)


func get_fade_alpha() -> float:
	return _fade_rect.color.a if _fade_rect else 0.0


func _on_skill_leveled(skill: String, level: int) -> void:
	Audio.play("level_up")
	show_notification("%s level %d!" % [skill.capitalize(), level])

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _update_ui_visibility() -> void:
	if hud:
		hud.visible = in_game
	if popup and not in_game:
		# Leaving gameplay — make sure no modal is left hanging.
		if popup.has_method("close_all"):
			popup.close_all()
