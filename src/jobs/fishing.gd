class_name FishingController
extends Node3D
## Fishing flow: cast -> bobber waits -> bite window -> timing bar.
## HUD polls `phase` / `cursor` to draw the minigame; the player's action
## button routes here through PlayerCharacter.try_interact().

enum Phase { OFF, WAITING, BITE, REELING, DONE }

var phase: int = Phase.OFF
var cursor := 0.0          # 0..1 position on the timing bar
var _cursor_speed := 1.6
var _player: PlayerCharacter = null
var _bobber: MeshInstance3D = null
var _cast_point := Vector3.ZERO
var _bobber_floating := false  # true once the drop-in tween has landed
var _timer := 0.0
var _elapsed := 0.0
var _bite_window := 0.0
var _reel_time := 0.0
var _reel_player: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group("fishing")
	_reel_player = AudioStreamPlayer3D.new()
	_reel_player.stream = Audio.get_loop_stream("fishing_reel")
	_reel_player.unit_size = 5.0
	add_child(_reel_player)


func begin(player: PlayerCharacter) -> void:
	_player = player
	# Face the deepest water among known spots (nearest fishing spot).
	var best := Vector3.ZERO
	var best_d := 999.0
	for spot in Game.world.fishing_spots:
		var d: float = player.global_position.distance_to(spot)
		if d < best_d:
			best_d = d
			best = spot
	var water_dir := player.global_transform.basis.z
	var cast_from := player.global_position
	var cast_point := cast_from + water_dir * 5.0
	if best_d < 30.0:
		# Cast outward from the spot toward open water.
		var out_dir := Vector3(-1, 0, 0)
		if best.x > 500.0:
			out_dir = (Vector3(MapLayout.LAKE_CENTER.x, 0, MapLayout.LAKE_CENTER.y) - Vector3(best.x, 0, best.z))
			out_dir.y = 0.0
			out_dir = out_dir.normalized()
		cast_point = best + out_dir * 6.0
	var water_y: float = Game.world.terrain.water_level_at(cast_point.x, cast_point.z)
	if water_y < -100.0:
		water_y = MapLayout.SEA_LEVEL
	cast_point.y = water_y + 0.05
	player.face_towards(cast_point)

	phase = Phase.WAITING
	_timer = randf_range(2.5, 6.0)
	_elapsed = 0.0
	Audio.play_at("fishing_cast", player.global_position, -4.0)
	_spawn_bobber(cast_point)
	Events.toast.emit("Chờ cá cắn câu…")


func _spawn_bobber(point: Vector3) -> void:
	_clear_bobber()
	_bobber = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.18
	sphere.material = Palette.mat(Color(0.9, 0.25, 0.2), 0.4)
	_bobber.mesh = sphere
	add_child(_bobber)
	_cast_point = point
	_bobber_floating = false
	_bobber.global_position = point + Vector3(0, 2.0, 0)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BOUNCE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_bobber, "global_position", point, 0.5)
	tween.tween_callback(func() -> void:
		_bobber_floating = true
		Audio.play_at("bobber_plop", point, -6.0)
	)


func _clear_bobber() -> void:
	if _bobber != null and is_instance_valid(_bobber):
		_bobber.queue_free()
	_bobber = null


## Called when the player presses the action button mid-fishing.
func on_action() -> void:
	match phase:
		Phase.WAITING:
			# Grace period so the tap that started fishing can't cancel it.
			if _elapsed < 0.7:
				return
			_finish(false, "Bạn thu cần sớm quá.")
		Phase.BITE:
			phase = Phase.REELING
			cursor = 0.0
			_cursor_speed = randf_range(1.3, 1.9)
			_reel_time = 0.0
			_reel_player.global_position = _player.global_position
			_reel_player.play()
		Phase.REELING:
			_resolve_catch()
		_:
			pass


func _process(delta: float) -> void:
	if phase == Phase.OFF or _player == null:
		return
	if _player.state != PlayerCharacter.State.FISHING:
		_abort()
		return
	_elapsed += delta
	match phase:
		Phase.WAITING:
			_timer -= delta
			if _bobber != null and _bobber_floating:
				# Ride the same waves the water shader renders.
				_bobber.global_position.y = _cast_point.y + Palette.wave_height_at(
					Vector2(_cast_point.x, _cast_point.z), Time.get_ticks_msec() / 1000.0)
			if _timer <= 0.0:
				phase = Phase.BITE
				_bite_window = 1.25
				Audio.play_at("bite", _bobber.global_position if _bobber != null else _player.global_position, 2.0)
				if _bobber != null:
					var tween := create_tween()
					tween.tween_property(_bobber, "position:y", _bobber.position.y - 0.22, 0.12)
					tween.tween_property(_bobber, "position:y", _bobber.position.y, 0.3)
		Phase.BITE:
			_bite_window -= delta
			if _bite_window <= 0.0:
				_finish(false, "Cá chạy mất rồi!")
		Phase.REELING:
			_reel_time += delta
			cursor = (sin(_reel_time * _cursor_speed * TAU - PI * 0.5) + 1.0) * 0.5
			if _reel_time > 4.0:
				_finish(false, "Cá vùng thoát mất!")
		_:
			pass


func _resolve_catch() -> void:
	_reel_player.stop()
	# Accuracy = distance from bar center.
	var accuracy := 1.0 - absf(cursor - 0.5) * 2.0
	if accuracy < 0.35:
		_finish(false, "Hụt rồi! Canh giữa vạch xanh nhé.")
		return
	var fish := "fish_common"
	if accuracy > 0.93:
		fish = "fish_rare"
	elif accuracy > 0.72:
		fish = "fish_fine"
	Game.add_item(fish, 1)
	Game.stats.fish_caught += 1
	Audio.play_ui("catch_jingle")
	_finish(true, "Bắt được %s!" % Game.item_name(fish))


func _finish(_success: bool, message: String) -> void:
	Events.toast.emit(message)
	phase = Phase.OFF
	_clear_bobber()
	_reel_player.stop()
	if _player != null:
		_player.end_fishing()
	_player = null


func _abort() -> void:
	phase = Phase.OFF
	_clear_bobber()
	_reel_player.stop()
	_player = null
