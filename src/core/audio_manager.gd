extends Node
## Central audio: pooled positional SFX, UI sounds and the layered ambience
## (wind / waves / birds / crickets / rain / music pads) that keeps the world
## from ever being silent. All sounds are small generated WAVs in assets/audio.

const AUDIO_DIR := "res://assets/audio/"
const POOL_SIZE := 14

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_index: int = 0
var _ui_players: Array[AudioStreamPlayer] = []
var _ui_index: int = 0

# Ambient layer players, keyed by name.
var _ambient: Dictionary = {}
var _ambient_targets: Dictionary = {}
var _music_is_night := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 6.0
		p.max_distance = 70.0
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	for i in 4:
		var up := AudioStreamPlayer.new()
		add_child(up)
		_ui_players.append(up)
	_setup_ambient_layer("wind", "ambient_wind", -18.0)
	_setup_ambient_layer("waves", "ambient_waves", -60.0)
	_setup_ambient_layer("birds", "ambient_birds", -60.0)
	_setup_ambient_layer("crickets", "ambient_crickets", -60.0)
	_setup_ambient_layer("rain", "ambient_rain", -60.0)
	_setup_ambient_layer("music", "music_day", -26.0)


func _setup_ambient_layer(layer: String, stream_name: String, start_db: float) -> void:
	var p := AudioStreamPlayer.new()
	var stream := get_loop_stream(stream_name)
	if stream != null:
		p.stream = stream
	p.volume_db = start_db
	p.autoplay = false
	add_child(p)
	_ambient[layer] = p
	_ambient_targets[layer] = start_db
	if stream != null:
		p.play()


func _get_stream(sfx_name: String) -> AudioStreamWAV:
	if _streams.has(sfx_name):
		return _streams[sfx_name]
	var path := AUDIO_DIR + sfx_name + ".wav"
	if not ResourceLoader.exists(path):
		push_warning("Missing audio: " + path)
		_streams[sfx_name] = null
		return null
	var stream: AudioStreamWAV = load(path)
	_streams[sfx_name] = stream
	return stream


## Returns a private looping copy of a stream (safe to share the data).
func get_loop_stream(sfx_name: String) -> AudioStreamWAV:
	var base := _get_stream(sfx_name)
	if base == null:
		return null
	var stream: AudioStreamWAV = base.duplicate()
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	var bytes_per_frame := 2
	if stream.stereo:
		bytes_per_frame *= 2
	stream.loop_end = stream.data.size() / bytes_per_frame
	return stream


## Fire-and-forget positional sound.
func play_at(sfx_name: String, pos: Vector3, volume_db: float = 0.0, pitch_jitter: float = 0.08) -> void:
	var stream := _get_stream(sfx_name)
	if stream == null:
		return
	var p := _pool[_pool_index]
	_pool_index = (_pool_index + 1) % POOL_SIZE
	p.stop()
	p.stream = stream
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


## Non-positional UI / feedback sound.
func play_ui(sfx_name: String, volume_db: float = 0.0) -> void:
	var stream := _get_stream(sfx_name)
	if stream == null:
		return
	var p := _ui_players[_ui_index]
	_ui_index = (_ui_index + 1) % _ui_players.size()
	p.stop()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-0.03, 0.03)
	p.play()


func _process(delta: float) -> void:
	_update_ambient_targets()
	for layer in _ambient:
		var p: AudioStreamPlayer = _ambient[layer]
		var target: float = _ambient_targets[layer]
		p.volume_db = lerpf(p.volume_db, target, minf(delta * 2.0, 1.0))
		# Keep fully-quiet layers cheap.
		if p.volume_db < -55.0 and p.playing and layer != "wind" and layer != "music":
			p.stop()
		elif p.volume_db >= -55.0 and not p.playing and p.stream != null:
			p.play()


func _update_ambient_targets() -> void:
	var probe := {"waves": 0.0, "forest": 0.0, "indoor": 0.0}
	if is_instance_valid(Game.player) and is_instance_valid(Game.world) and Game.world.has_method("ambience_at"):
		probe = Game.world.ambience_at(Game.player.global_position)
	var daylight: float = DayNight.daylight()
	var night := 1.0 if DayNight.is_night() else 0.0
	var rain: float = DayNight.rain_amount
	var indoor: float = probe.get("indoor", 0.0)
	var outdoor := 1.0 - indoor * 0.8

	_ambient_targets["wind"] = _mix_db(-20.0, (0.55 + 0.45 * rain) * outdoor)
	_ambient_targets["waves"] = _mix_db(-8.0, probe.get("waves", 0.0) * outdoor)
	_ambient_targets["birds"] = _mix_db(-14.0, probe.get("forest", 0.0) * daylight * (1.0 - rain) * outdoor)
	_ambient_targets["crickets"] = _mix_db(-16.0, night * (1.0 - rain) * outdoor)
	_ambient_targets["rain"] = _mix_db(-8.0, rain * (1.0 - indoor * 0.5))
	_update_music()


## Crossfade between the day and night pads: duck to silence, swap, rise.
func _update_music() -> void:
	var want_night := DayNight.is_night()
	var music: AudioStreamPlayer = _ambient["music"]
	if want_night == _music_is_night:
		_ambient_targets["music"] = -26.0
		return
	_ambient_targets["music"] = -60.0
	if music.volume_db <= -50.0:
		_music_is_night = want_night
		var stream := get_loop_stream("music_night" if want_night else "music_day")
		if stream != null:
			music.stream = stream
			music.play()


static func _mix_db(full_db: float, amount: float) -> float:
	if amount <= 0.01:
		return -60.0
	return full_db + linear_to_db(clampf(amount, 0.0, 1.0))
