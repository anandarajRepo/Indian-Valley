extends Node
## Settings.gd — Autoload for player preferences (not part of any save slot).
##
## Stored in user://settings.cfg:
##   fullscreen     — windowed vs. fullscreen
##   relaxed_clock  — days pass 50% slower, for a gentler pace
##   master/music/sfx_volume — 0..1 per audio bus
##   text_speed     — how fast dialogue types out (see TEXT_SPEEDS)
##   pause_on_focus_loss — open the pause menu when the window loses focus

const PATH: String = "user://settings.cfg"
const RELAXED_SCALE: float = 1.5
## Smallest window the UI (built for 1280×720) still reads well in.
const MIN_WINDOW: Vector2i = Vector2i(960, 540)

## Characters per second for each text speed; 0 shows the whole line at once.
const TEXT_SPEEDS: Dictionary = {"slow": 30.0, "normal": 60.0, "fast": 120.0, "instant": 0.0}
const TEXT_SPEED_ORDER: Array = ["slow", "normal", "fast", "instant"]

const DEFAULTS: Dictionary = {
	"fullscreen": false,
	"relaxed_clock": false,
	"master_volume": 0.8,
	"music_volume": 0.6,
	"sfx_volume": 0.8,
	"text_speed": "normal",
	"pause_on_focus_loss": true,
}

var fullscreen: bool = false
var relaxed_clock: bool = false
var master_volume: float = 0.8
var music_volume: float = 0.6
var sfx_volume: float = 0.8
var text_speed: String = "normal"
var pause_on_focus_loss: bool = true


func _ready() -> void:
	load_settings()
	apply()


func load_settings() -> void:
	reset_to_defaults(false)
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	fullscreen = bool(cfg.get_value("display", "fullscreen", fullscreen))
	relaxed_clock = bool(cfg.get_value("gameplay", "relaxed_clock", relaxed_clock))
	pause_on_focus_loss = bool(cfg.get_value("gameplay", "pause_on_focus_loss", pause_on_focus_loss))
	master_volume = clampf(float(cfg.get_value("audio", "master_volume", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music_volume", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 1.0)
	var speed := String(cfg.get_value("gameplay", "text_speed", text_speed))
	text_speed = speed if TEXT_SPEEDS.has(speed) else DEFAULTS["text_speed"]


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("gameplay", "relaxed_clock", relaxed_clock)
	cfg.set_value("gameplay", "text_speed", text_speed)
	cfg.set_value("gameplay", "pause_on_focus_loss", pause_on_focus_loss)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.save(PATH)


func reset_to_defaults(persist: bool = true) -> void:
	fullscreen = DEFAULTS["fullscreen"]
	relaxed_clock = DEFAULTS["relaxed_clock"]
	master_volume = DEFAULTS["master_volume"]
	music_volume = DEFAULTS["music_volume"]
	sfx_volume = DEFAULTS["sfx_volume"]
	text_speed = DEFAULTS["text_speed"]
	pause_on_focus_loss = DEFAULTS["pause_on_focus_loss"]
	if persist:
		apply()
		save_settings()


func apply() -> void:
	GameClock.time_scale = RELAXED_SCALE if relaxed_clock else 1.0
	Audio.set_bus_volume("Master", master_volume)
	Audio.set_bus_volume(Audio.MUSIC_BUS, music_volume)
	Audio.set_bus_volume(Audio.SFX_BUS, sfx_volume)
	# Headless runs (tests, CI) have no real window to resize.
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_min_size(MIN_WINDOW)
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


func chars_per_second() -> float:
	return float(TEXT_SPEEDS.get(text_speed, TEXT_SPEEDS["normal"]))


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	apply()
	save_settings()


func set_relaxed_clock(on: bool) -> void:
	relaxed_clock = on
	apply()
	save_settings()


func set_volume(bus: String, linear: float) -> void:
	## bus: "master", "music" or "sfx".
	linear = clampf(linear, 0.0, 1.0)
	match bus:
		"master": master_volume = linear
		"music":  music_volume = linear
		"sfx":    sfx_volume = linear
		_: return
	apply()
	save_settings()


func set_text_speed(speed: String) -> void:
	if not TEXT_SPEEDS.has(speed):
		return
	text_speed = speed
	save_settings()


func set_pause_on_focus_loss(on: bool) -> void:
	pause_on_focus_loss = on
	save_settings()
