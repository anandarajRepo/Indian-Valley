extends Node
## Settings.gd — Autoload for player preferences (not part of any save slot).
##
## Stored in user://settings.cfg:
##   fullscreen    — windowed vs. fullscreen
##   relaxed_clock — days pass 50% slower, for a gentler pace

const PATH: String = "user://settings.cfg"
const RELAXED_SCALE: float = 1.5

var fullscreen: bool = false
var relaxed_clock: bool = false


func _ready() -> void:
	load_settings()
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	fullscreen = bool(cfg.get_value("display", "fullscreen", false))
	relaxed_clock = bool(cfg.get_value("gameplay", "relaxed_clock", false))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("gameplay", "relaxed_clock", relaxed_clock)
	cfg.save(PATH)


func apply() -> void:
	GameClock.time_scale = RELAXED_SCALE if relaxed_clock else 1.0
	# Headless runs (tests, CI) have no real window to resize.
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	apply()
	save_settings()


func set_relaxed_clock(on: bool) -> void:
	relaxed_clock = on
	apply()
	save_settings()
