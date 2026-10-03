extends Node
## Audio.gd — Autoload for sound effects, music and ambience.
##
## There are no audio assets yet, so every sound is synthesised at runtime
## into an AudioStreamWAV:
##   - SFX     — short tones / noise bursts from the RECIPES table, built on
##               first use and cached. Played through a small voice pool.
##   - Music   — a gentle looping tune in raga Mohanam (a pentatonic scale)
##               over a tanpura-style drone, rendered on a worker thread at
##               boot so it never stalls the first frame.
##   - Ambience — a soft rain loop the Atmosphere layer turns on when it rains.
##
## Three buses (Master → Music, SFX) carry the player's volume settings.

const MIX_RATE: int = 22050
const VOICES:   int = 8
const MUSIC_BUS: String = "Music"
const SFX_BUS:   String = "SFX"

## Each recipe is a list of notes played one after another:
##   [frequency Hz (0 = noise), duration s, wave, volume, slide Hz (optional)]
## wave: "sine", "square", "tri", "pluck" (decaying sine + overtones), "noise".
const RECIPES: Dictionary = {
	"ui_click":  [[880.0, 0.035, "square", 0.18]],
	"ui_open":   [[587.3, 0.05, "tri", 0.30], [880.0, 0.07, "tri", 0.30]],
	"ui_close":  [[880.0, 0.05, "tri", 0.25], [587.3, 0.07, "tri", 0.25]],
	"blip":      [[1174.7, 0.025, "tri", 0.12]],
	"till":      [[0.0, 0.10, "noise", 0.35, 0.0], [110.0, 0.06, "tri", 0.30]],
	"water":     [[0.0, 0.28, "noise", 0.22, 0.0]],
	"plant":     [[392.0, 0.12, "pluck", 0.40]],
	"harvest":   [[587.3, 0.07, "pluck", 0.40], [740.0, 0.07, "pluck", 0.40], [880.0, 0.14, "pluck", 0.45]],
	"coin":      [[987.8, 0.06, "square", 0.20], [1318.5, 0.16, "square", 0.20]],
	"pickup":    [[659.3, 0.05, "tri", 0.35], [987.8, 0.08, "tri", 0.35]],
	"eat":       [[330.0, 0.06, "tri", 0.35], [262.0, 0.06, "tri", 0.30], [392.0, 0.10, "tri", 0.30]],
	"rock_hit":  [[0.0, 0.07, "noise", 0.40, 0.0], [196.0, 0.04, "square", 0.15]],
	"rock_break":[[0.0, 0.20, "noise", 0.50, 0.0], [98.0, 0.12, "tri", 0.40, -40.0]],
	"discover":  [[523.3, 0.08, "pluck", 0.40], [784.0, 0.08, "pluck", 0.40], [1046.5, 0.20, "pluck", 0.45]],
	"bite":      [[1318.5, 0.05, "square", 0.25], [0.0, 0.04, "noise", 0.0, 0.0], [1318.5, 0.05, "square", 0.25]],
	"catch":     [[587.3, 0.06, "pluck", 0.40], [880.0, 0.06, "pluck", 0.40], [1174.7, 0.22, "pluck", 0.45]],
	"miss":      [[392.0, 0.10, "tri", 0.30, -120.0], [262.0, 0.16, "tri", 0.25, -80.0]],
	"error":     [[146.8, 0.12, "square", 0.18]],
	"warp":      [[0.0, 0.22, "noise", 0.12, 0.0]],
	"sleep":     [[880.0, 0.18, "sine", 0.25], [740.0, 0.18, "sine", 0.22], [587.3, 0.36, "sine", 0.20]],
	"level_up":  [[587.3, 0.07, "pluck", 0.40], [740.0, 0.07, "pluck", 0.40], [880.0, 0.07, "pluck", 0.40], [1174.7, 0.30, "pluck", 0.50]],
	"fanfare":   [[440.0, 0.10, "pluck", 0.40], [587.3, 0.10, "pluck", 0.40], [740.0, 0.10, "pluck", 0.40], [880.0, 0.12, "pluck", 0.45], [1174.7, 0.40, "pluck", 0.50]],
	"gift":      [[740.0, 0.07, "tri", 0.30], [987.8, 0.12, "tri", 0.30]],
}

## Mohanam on Sa = D: Sa Ri Ga Pa Dha (D E F# A B), two octaves.
const SCALE_HZ: Array = [293.66, 329.63, 369.99, 440.0, 493.88, 587.33, 659.26, 739.99, 880.0, 987.77]
const MUSIC_BEAT: float = 0.75   ## 80 bpm
## Melody as [scale index, beats]; -1 is a rest. 32 beats ≈ 24 s.
const MELODY: Array = [
	[5, 1], [4, 0.5], [3, 0.5], [2, 1], [3, 1],
	[4, 1.5], [3, 0.5], [2, 2],
	[0, 1], [1, 1], [2, 1], [3, 1],
	[2, 1.5], [1, 0.5], [0, 2],
	[3, 1], [4, 1], [5, 1], [6, 1],
	[7, 1.5], [6, 0.5], [5, 2],
	[4, 1], [3, 0.5], [2, 0.5], [1, 1], [2, 1],
	[0, 3], [-1, 1],
]
## Tanpura-style drone pattern, plucked once a beat: Pa, Sa', Sa', Sa.
const DRONE_HZ: Array = [110.0, 146.83, 146.83, 73.42]

var _voices: Array = []
var _cache: Dictionary = {}
var _music_player: AudioStreamPlayer = null
var _ambience_player: AudioStreamPlayer = null
var _ambience: String = ""
var _music_thread: Thread = null
var _music_wanted: bool = false

## Headless runs (tests, CI) use a dummy driver that never mixes, so its
## playbacks are never released. There we build streams but don't play them.
var _silent: bool = false

## Seconds since each sound last played, so rapid repeats (dialogue blips,
## a row of watered tiles) don't stack into noise.
var _last_played: Dictionary = {}
const MIN_REPEAT: float = 0.04


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_silent = DisplayServer.get_name() == "headless"
	_ensure_buses()
	for i in range(VOICES):
		var p := AudioStreamPlayer.new()
		p.bus = SFX_BUS
		add_child(p)
		_voices.append(p)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = MUSIC_BUS
	add_child(_music_player)
	_ambience_player = AudioStreamPlayer.new()
	_ambience_player.bus = SFX_BUS
	_ambience_player.volume_db = -10.0
	add_child(_ambience_player)
	# Render the music in the background; headless runs skip it.
	if not _silent:
		_music_thread = Thread.new()
		_music_thread.start(_render_music_threaded)


func _exit_tree() -> void:
	shutdown()


func shutdown() -> void:
	## Stop and drop every stream. Call a few frames before quitting so the
	## audio server releases its playbacks (otherwise they leak at exit).
	if _music_thread and _music_thread.is_started():
		_music_thread.wait_to_finish()
	_music_wanted = false
	_ambience = ""
	for p in _voices + [_music_player, _ambience_player]:
		p.stop()
		p.stream = null
	_cache.clear()

# ---------------------------------------------------------------------------
# Buses & volume
# ---------------------------------------------------------------------------

func _ensure_buses() -> void:
	for bus_name in [MUSIC_BUS, SFX_BUS]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func set_bus_volume(bus_name: String, linear: float) -> void:
	## `linear` is 0..1; 0 mutes the bus.
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	linear = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))


func get_bus_volume(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1 or AudioServer.is_bus_mute(idx):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))

# ---------------------------------------------------------------------------
# Sound effects
# ---------------------------------------------------------------------------

func play(sfx: String, pitch: float = 1.0) -> bool:
	## Play a named sound effect. Returns false for unknown names.
	if not RECIPES.has(sfx):
		push_warning("Audio: unknown sound '%s'" % sfx)
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(sfx, -1.0)) < MIN_REPEAT:
		return true
	_last_played[sfx] = now
	var player := _free_voice()
	player.stream = get_stream(sfx)
	player.pitch_scale = pitch
	if not _silent:
		player.play()
	return true


func get_stream(sfx: String) -> AudioStreamWAV:
	if not _cache.has(sfx):
		_cache[sfx] = _render_recipe(RECIPES[sfx])
	return _cache[sfx]


func _free_voice() -> AudioStreamPlayer:
	for p in _voices:
		if not p.playing:
			return p
	# Every voice is busy — steal the first one.
	return _voices[0]

# ---------------------------------------------------------------------------
# Music & ambience
# ---------------------------------------------------------------------------

func play_music() -> void:
	## Start the background tune (it starts as soon as it has rendered).
	_music_wanted = true
	if _music_player.stream != null and not _music_player.playing:
		_music_player.play()


func stop_music() -> void:
	_music_wanted = false
	_music_player.stop()


func is_music_ready() -> bool:
	return _music_player.stream != null


func set_ambience(kind: String) -> void:
	## "rain" or "" (silence).
	if kind == _ambience:
		return
	_ambience = kind
	if kind == "rain":
		if not _cache.has("_rain"):
			_cache["_rain"] = _render_rain(2.0)
		_ambience_player.stream = _cache["_rain"]
		if not _silent:
			_ambience_player.play()
	else:
		_ambience_player.stop()


func get_ambience() -> String:
	return _ambience


func _render_music_threaded() -> void:
	var stream := render_music(MUSIC_BEAT * 32.0)
	_on_music_rendered.call_deferred(stream)


func _on_music_rendered(stream: AudioStreamWAV) -> void:
	_music_player.stream = stream
	if _music_wanted:
		_music_player.play()

# ---------------------------------------------------------------------------
# Synthesis
# ---------------------------------------------------------------------------

func render_music(seconds: float) -> AudioStreamWAV:
	## Render the looping tune. Notes that ring past the end wrap around to the
	## start, so the loop point is seamless.
	var n := int(seconds * MIX_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var beats := int(seconds / MUSIC_BEAT)
	for b in range(beats):
		_add_pluck(buf, int(b * MUSIC_BEAT * MIX_RATE), DRONE_HZ[b % DRONE_HZ.size()], 2.4, 0.16, true)
	var t := 0.0
	while t < seconds:
		for note in MELODY:
			if t >= seconds:
				break
			var dur: float = float(note[1]) * MUSIC_BEAT
			if int(note[0]) >= 0:
				_add_pluck(buf, int(t * MIX_RATE), SCALE_HZ[int(note[0])], dur + 0.8, 0.22, true)
			t += dur
	return _to_wav(buf, true)


func _render_recipe(notes: Array) -> AudioStreamWAV:
	var total := 0.0
	for note in notes:
		total += float(note[1])
	var buf := PackedFloat32Array()
	buf.resize(int(total * MIX_RATE) + 1)
	var start := 0
	for note in notes:
		var freq: float = note[0]
		var dur: float = note[1]
		var wave: String = note[2]
		var vol: float = note[3]
		var slide: float = note[4] if note.size() > 4 else 0.0
		var count := int(dur * MIX_RATE)
		if wave == "pluck":
			_add_pluck(buf, start, freq, dur, vol, false)
		else:
			var phase := 0.0
			var lp := 0.0
			for i in range(count):
				var k := float(i) / float(maxi(count, 1))
				# Short attack, smooth release — no clicks at the edges.
				var env := minf(1.0, k * 40.0) * (1.0 - k) * (1.0 - k)
				var f := freq + slide * k
				phase += f / MIX_RATE
				var s := 0.0
				match wave:
					"sine":   s = sin(TAU * phase)
					"square": s = 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
					"tri":    s = 4.0 * absf(fmod(phase, 1.0) - 0.5) - 1.0
					"noise":
						lp += 0.35 * (randf_range(-1.0, 1.0) - lp)   # soften the hiss
						s = lp * 2.0
				buf[start + i] += s * env * vol
		start += count
	return _to_wav(buf, false)


func _add_pluck(buf: PackedFloat32Array, start: int, freq: float, dur: float, vol: float, wrap: bool) -> void:
	## A plucked string: a decaying sine with a couple of overtones.
	var count := int(dur * MIX_RATE)
	var n := buf.size()
	var decay := 4.5 / maxf(dur, 0.01)
	var w := TAU * freq / MIX_RATE
	for i in range(count):
		var idx := start + i
		if idx >= n:
			if not wrap:
				break
			idx %= n
		var env := exp(-decay * float(i) / MIX_RATE) * minf(1.0, float(i) / 60.0)
		var x := w * i
		buf[idx] += (sin(x) + 0.35 * sin(2.0 * x) + 0.12 * sin(3.0 * x)) * env * vol


func _render_rain(seconds: float) -> AudioStreamWAV:
	var n := int(seconds * MIX_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	for i in range(n):
		lp += 0.12 * (randf_range(-1.0, 1.0) - lp)
		buf[i] = lp * 0.9
	# Cross-fade the last 1000 samples into the start for a seamless loop.
	var fade := 1000
	for i in range(fade):
		var k := float(i) / fade
		buf[n - fade + i] = buf[n - fade + i] * (1.0 - k) + buf[i] * k
	return _to_wav(buf, true)


func _to_wav(buf: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in range(buf.size()):
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = buf.size()
	return wav
