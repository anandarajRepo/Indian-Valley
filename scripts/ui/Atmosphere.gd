extends CanvasLayer
## Atmosphere.gd — screen-space weather and time-of-day overlay.
##
## Sits between the world and the HUD (layer 5):
##   - evenings darken gradually from 6 pm and are darkest after 10 pm
##   - rainy days get a grey wash and falling rain streaks (heavier in storms)
## Purely visual; hidden on the main menu.

const RAIN_DROPS:  int = 90
const STORM_DROPS: int = 180

var _tint: ColorRect = null
var _rain: Control = null
var _drops: Array = []     ## Array of Vector2 in normalised screen space


func _ready() -> void:
	_tint = ColorRect.new()
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.color = Color(0, 0, 0, 0)
	add_child(_tint)

	_rain = Control.new()
	_rain.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rain.draw.connect(_draw_rain)
	add_child(_rain)

	for i in range(STORM_DROPS):
		_drops.append(Vector2(randf(), randf()))

	var gm = GameManager.instance
	visible = gm != null and gm.in_game
	if gm:
		gm.game_state_changed.connect(func(in_game: bool): visible = in_game)


func _process(delta: float) -> void:
	if not visible:
		return
	_tint.color = _compute_tint()
	if Weather.is_raining():
		if not GameClock.is_paused():
			var speed := 1.6 if Weather.today == Weather.STORM else 1.1
			for i in range(_drops.size()):
				var d: Vector2 = _drops[i]
				d.y += speed * delta
				d.x -= 0.15 * delta
				if d.y > 1.0:
					d = Vector2(randf() + 0.1, 0.0)
				elif d.x < 0.0:
					d.x += 1.0
				_drops[i] = d
		_rain.queue_redraw()
	elif _rain.visible:
		_rain.queue_redraw()
	_rain.visible = Weather.is_raining()


func _compute_tint() -> Color:
	## Evening darkening blended with a grey wash for bad weather.
	var hour := float(GameClock.current_hour) + GameClock.current_minute / 60.0
	var night := clampf((hour - 18.0) / 4.0, 0.0, 1.0) * 0.45
	var gloom := 0.0
	match Weather.today:
		Weather.STORM:  gloom = 0.28
		Weather.RAIN:   gloom = 0.18
		Weather.CLOUDY: gloom = 0.08
	var night_col := Color(0.05, 0.06, 0.20, night)
	if gloom <= 0.0:
		return night_col
	var gloom_col := Color(0.25, 0.28, 0.32, gloom)
	var a := 1.0 - (1.0 - night) * (1.0 - gloom)
	var mix := night_col.lerp(gloom_col, gloom / (night + gloom))
	return Color(mix.r, mix.g, mix.b, a)


func _draw_rain() -> void:
	if not Weather.is_raining():
		return
	var count := STORM_DROPS if Weather.today == Weather.STORM else RAIN_DROPS
	var size := _rain.size
	var col := Color(0.75, 0.82, 0.95, 0.55)
	for i in range(min(count, _drops.size())):
		var p: Vector2 = _drops[i] * size
		_rain.draw_line(p, p + Vector2(-4, 14), col, 1.5)
