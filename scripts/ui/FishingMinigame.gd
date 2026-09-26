extends Control
## FishingMinigame.gd — a simple timing minigame shown inside the Popup layer.
##
##   1. Cast: wait a moment for a bite (reeling in now scares the fish off).
##   2. Bite: a marker sweeps across a track; press Z / X / Enter while it is
##      inside the green zone to land the fish. Harder fish have a smaller
##      zone and a faster marker.
##
## Emits `finished(fish_id)` — an empty id means nothing was caught.

signal finished(fish_id: String)

enum Phase { WAITING, BITE, DONE }

const TRACK_W: float = 440.0
const TRACK_H: float = 26.0

var location: String = "pond"

var _phase: int = Phase.WAITING
var _fish: Dictionary = {}
var _wait_left: float = 0.0
var _marker_pos: float = 0.0     ## 0..1 along the track
var _marker_dir: float = 1.0
var _speed: float = 0.6          ## track widths per second
var _zone_start: float = 0.4
var _zone_size: float = 0.25

var _status: Label = null
var _track: ColorRect = null
var _zone: ColorRect = null
var _marker: ColorRect = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_wait_left = randf_range(0.8, 2.2)
	_fish = GameManager.instance.choose_fish(location) if GameManager.instance else {}
	if _fish.is_empty():
		_status.text = "Nothing seems to be biting here right now."
		_phase = Phase.DONE
		get_tree().create_timer(1.2).timeout.connect(func(): _finish(""))


func _build() -> void:
	var panel := UIKit.panel(Vector2(520, 200), Vector2(380, 420))
	add_child(panel)
	var box := UIKit.vbox(panel, 12)

	var where := "the farm pond" if location == "pond" else "the Ghats river"
	box.add_child(UIKit.title("Fishing at %s" % where, 18))

	_status = UIKit.label("Waiting for a bite...", 14)
	box.add_child(_status)

	_track = ColorRect.new()
	_track.color = Color(0.12, 0.22, 0.32)
	_track.custom_minimum_size = Vector2(TRACK_W, TRACK_H)
	_track.visible = false
	box.add_child(_track)

	_zone = ColorRect.new()
	_zone.color = UIKit.COL_GOOD
	_track.add_child(_zone)

	_marker = ColorRect.new()
	_marker.color = Color(0.98, 0.95, 0.85)
	_marker.size = Vector2(6, TRACK_H + 8)
	_track.add_child(_marker)

	box.add_child(UIKit.label("Z / X / Enter to reel in   ·   Esc to stop", 11, UIKit.COL_MUTED))


func _process(delta: float) -> void:
	match _phase:
		Phase.WAITING:
			_wait_left -= delta
			if _wait_left <= 0.0:
				_start_bite()
		Phase.BITE:
			_marker_pos += _marker_dir * _speed * delta
			if _marker_pos >= 1.0:
				_marker_pos = 1.0
				_marker_dir = -1.0
			elif _marker_pos <= 0.0:
				_marker_pos = 0.0
				_marker_dir = 1.0
			_layout_marker()


func _start_bite() -> void:
	_phase = Phase.BITE
	var difficulty: int = clampi(int(_fish.get("difficulty", 1)), 1, 5)
	_zone_size = 0.34 - 0.05 * difficulty       # 0.29 (easy) → 0.09 (legendary)
	_speed = 0.55 + 0.2 * difficulty
	_zone_start = randf_range(0.05, 0.95 - _zone_size)
	_marker_pos = 0.0 if randf() < 0.5 else 1.0
	_marker_dir = 1.0 if _marker_pos == 0.0 else -1.0
	_status.text = "Something's biting! Reel in when the marker is in the green."
	_track.visible = true
	_zone.position = Vector2(_zone_start * TRACK_W, 0)
	_zone.size = Vector2(_zone_size * TRACK_W, TRACK_H)
	_layout_marker()


func _layout_marker() -> void:
	_marker.position = Vector2(_marker_pos * TRACK_W - _marker.size.x / 2.0, -4)


func press() -> void:
	## Called by the Popup when the player presses reel-in.
	match _phase:
		Phase.WAITING:
			_phase = Phase.DONE
			_status.text = "Too early — you scared it off."
			get_tree().create_timer(0.9).timeout.connect(func(): _finish(""))
		Phase.BITE:
			_phase = Phase.DONE
			var hit := _marker_pos >= _zone_start and _marker_pos <= _zone_start + _zone_size
			if hit:
				_status.text = "You caught a %s!" % _fish.get("name", "fish")
				get_tree().create_timer(0.7).timeout.connect(func(): _finish(_fish.get("id", "")))
			else:
				_status.text = "It slipped the hook..."
				get_tree().create_timer(0.9).timeout.connect(func(): _finish(""))


func _finish(fish_id: String) -> void:
	if not is_inside_tree():
		return
	emit_signal("finished", fish_id)
