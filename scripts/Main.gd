extends Node
class_name GameManager
## Main.gd — the persistent game manager and root of the scene tree.
##
## Responsibilities:
##   - Owns the swappable "world" scenes (MainMenu ↔ Farm ↔ Town) loaded into
##     the CurrentScene container, so autoloads and the persistent UI survive.
##   - High-level flow: new game, continue, quit, scene transitions.
##   - Cross-scene state that must outlive any single scene:
##       * farm_tiles     — authoritative farm plot simulation state
##       * inventory_data — the player's inventory (survives Farm↔Town trips)
##       * spawn_target   — which spawn marker the next world should use
##   - Overnight simulation (crop growth) + save/load orchestration.
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

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal inventory_updated()          ## Inventory contents/selection changed.
signal farm_updated()               ## Farm tile state changed (e.g. overnight growth).
signal game_state_changed(in_game: bool)

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

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _enter_tree() -> void:
	# Set the global reference before any child (HUD/Popup/world) runs _ready.
	instance = self


func _ready() -> void:
	add_to_group("game")
	show_main_menu()


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


func goto_world(path: String, spawn: String = "default") -> void:
	## Transition between playable world scenes (Farm ↔ Town).
	spawn_target = spawn
	call_deferred("_load_scene", path)


func goto_farm(spawn: String = "default") -> void:
	goto_world(FARM_SCENE, spawn)


func goto_town(spawn: String = "default") -> void:
	goto_world(TOWN_SCENE, spawn)

# ---------------------------------------------------------------------------
# Flow: main menu / new game / continue / quit
# ---------------------------------------------------------------------------

func show_main_menu() -> void:
	in_game = false
	GameClock.pause()
	_update_ui_visibility()
	emit_signal("game_state_changed", in_game)
	call_deferred("_load_scene", MAIN_MENU_SCENE)


func new_game() -> void:
	GameClock.reset_to_new_game()
	GameData.reset_to_new_game()
	farm_tiles = {}
	inventory_data = {}
	spawn_target = "default"
	in_game = true
	_update_ui_visibility()
	emit_signal("game_state_changed", in_game)
	GameClock.resume()
	call_deferred("_load_scene", FARM_SCENE)


func continue_game() -> bool:
	if not has_save():
		return false
	if not SaveManager.load_game(current_slot):
		return false

	var data: Dictionary = SaveManager.last_loaded
	var farm: Dictionary = data.get("farm", {})
	farm_tiles = farm.get("tiles", {})
	inventory_data = data.get("inventory", {})
	spawn_target = "default"
	in_game = true
	_update_ui_visibility()
	emit_signal("game_state_changed", in_game)
	GameClock.resume()
	call_deferred("_load_scene", FARM_SCENE)
	return true


func has_save() -> bool:
	return SaveManager.slot_exists(current_slot)


func quit_game() -> void:
	get_tree().quit()

# ---------------------------------------------------------------------------
# Saving
# ---------------------------------------------------------------------------

func save_game() -> bool:
	var extra := {
		"farm":      {"tiles": farm_tiles},
		"inventory": inventory_data,
	}
	return SaveManager.save_game(current_slot, extra)

# ---------------------------------------------------------------------------
# Overnight simulation
# ---------------------------------------------------------------------------

func on_overnight(earnings: int) -> void:
	## Called by GameData after the calendar has advanced to the new morning.
	advance_farm_day()
	save_game()
	if popup and popup.has_method("show_day_summary"):
		popup.show_day_summary(earnings)


func advance_farm_day() -> void:
	## Grow every watered, planted tile by one day. Watering "expires" naturally
	## because a tile only counts as watered on the exact day it was watered.
	for key in farm_tiles:
		var data: Dictionary = farm_tiles[key]
		if data.get("state", "") != "planted":
			continue

		var crop = ItemDB.get_crop(data.get("crop_id", ""))
		if crop.is_empty():
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


func open_shop() -> void:
	if popup and popup.has_method("open_shop"):
		popup.open_shop()


func toggle_inventory_screen() -> void:
	if popup and popup.has_method("toggle_inventory_screen"):
		popup.toggle_inventory_screen()


func open_pause_menu() -> void:
	if popup and popup.has_method("open_pause_menu"):
		popup.open_pause_menu()

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
