class_name TaxiJob
extends Node3D
## Taxi work: drive the town taxi, passengers appear at pickup points,
## deliver them across the island for distance-based fares (+ speed tips).

enum Phase { OFF, TO_PICKUP, TO_DROPOFF, COOLDOWN }

const BASE_FARE := 15.0
const FARE_PER_M := 0.12

var phase: int = Phase.OFF
var _passenger: Node3D = null
var _pickup: Vector3
var _dropoff: Vector3
var _dropoff_name := ""
var _fare := 0
var _trip_timer := 0.0
var _expected_time := 0.0
var _cooldown := 0.0


func _ready() -> void:
	add_to_group("taxi_job")
	Events.player_entered_vehicle.connect(_on_entered_vehicle)
	Events.player_exited_vehicle.connect(_on_exited_vehicle)


func _on_entered_vehicle(vehicle: Node3D) -> void:
	if phase != Phase.OFF or not vehicle.is_in_group("taxi"):
		return
	# One objective arrow at a time: finish the delivery round first.
	var delivery := get_tree().get_first_node_in_group("delivery_job")
	if delivery != null and delivery.active:
		Events.toast.emit("Giao nốt kiện hàng đã rồi hãy chạy taxi nhé!")
		return
	Events.job_started.emit("taxi")
	Events.toast.emit("🚕 Chế độ taxi: đón khách theo mũi tên!")
	_next_fare()


func _on_exited_vehicle(vehicle: Node3D) -> void:
	if not vehicle.is_in_group("taxi") or phase == Phase.OFF:
		return
	if phase == Phase.TO_DROPOFF:
		Events.toast.emit("Khách bực mình bỏ đi… chuyến bị huỷ.")
	_cancel()


func _cancel() -> void:
	phase = Phase.OFF
	_clear_passenger()
	Events.clear_objective()
	Events.job_ended.emit("taxi", false)


func _next_fare() -> void:
	var player_pos: Vector3 = Game.player.global_position
	var spots: Array = MapLayout.TAXI_SPOTS.duplicate()
	spots.shuffle()
	var pickup_spot: Dictionary = spots[0]
	for spot in spots:
		var p: Vector2 = spot.pos
		var d := Vector2(player_pos.x, player_pos.z).distance_to(p)
		if d > 60.0 and d < 400.0:
			pickup_spot = spot
			break
	var terrain: Terrain = Game.world.terrain
	_pickup = Vector3(pickup_spot.pos.x, terrain.height_at(pickup_spot.pos.x, pickup_spot.pos.y), pickup_spot.pos.y)
	_spawn_passenger(_pickup)
	phase = Phase.TO_PICKUP
	Events.objective_changed.emit("Đón khách: %s" % pickup_spot.name, _pickup, true)


func _spawn_passenger(pos: Vector3) -> void:
	_clear_passenger()
	_passenger = Node3D.new()
	var ids := ["hanh_khach_1", "hanh_khach_2", "hanh_khach_3"]
	var palette := NpcData.palette_for(ids[randi() % ids.size()] + str(randi() % 97))
	var body := Humanoid.make(palette[0], palette[1], palette[2], palette[3])
	_passenger.add_child(body)
	_passenger.set_meta("body", body)
	add_child(_passenger)
	_passenger.global_position = pos


func _clear_passenger() -> void:
	if _passenger != null and is_instance_valid(_passenger):
		_passenger.queue_free()
	_passenger = null


func _process(delta: float) -> void:
	if phase == Phase.OFF or not is_instance_valid(Game.player):
		return
	var player: PlayerCharacter = Game.player
	# Passenger idle anim.
	if _passenger != null and is_instance_valid(_passenger):
		var body: Humanoid = _passenger.get_meta("body")
		body.tick(delta, {"mode": "idle"})
	match phase:
		Phase.TO_PICKUP:
			if player.state != PlayerCharacter.State.DRIVING:
				return
			var dist: float = player.vehicle.global_position.distance_to(_pickup)
			if dist < 7.0 and absf(player.vehicle.speed) < 0.8:
				_board_passenger()
		Phase.TO_DROPOFF:
			_trip_timer += delta
			if player.state != PlayerCharacter.State.DRIVING:
				return
			var dist: float = player.vehicle.global_position.distance_to(_dropoff)
			if dist < 8.0 and absf(player.vehicle.speed) < 0.8:
				_complete_fare()
		Phase.COOLDOWN:
			_cooldown -= delta
			if _cooldown <= 0.0:
				if player.state == PlayerCharacter.State.DRIVING and player.vehicle != null and player.vehicle.is_in_group("taxi"):
					_next_fare()
				else:
					_cancel()


func _board_passenger() -> void:
	var vehicle: Vehicle = Game.player.vehicle
	# Walk to the car, then hop in.
	var body: Humanoid = _passenger.get_meta("body")
	var seat: Vector3 = vehicle.passenger_seat_global()
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
		if _passenger != null and is_instance_valid(_passenger) and is_instance_valid(vehicle):
			_passenger.global_position = _passenger.global_position.lerp(vehicle.passenger_seat_global() + Vector3(1.4, -0.5, 0), t)
			body.tick(0.016, {"mode": "walk", "speed": 0.4})
	, 0.0, 1.0, 1.1)
	tween.tween_callback(func() -> void:
		_clear_passenger()
		Audio.play_at("car_door_close", seat, -4.0)
		var spots: Array = MapLayout.TAXI_SPOTS.duplicate()
		spots.shuffle()
		# Fall back to the farthest spot if none clears the distance bar.
		var chosen: Dictionary = spots[0]
		var chosen_d := 0.0
		for spot in spots:
			var p: Vector2 = spot.pos
			var d := Vector2(_pickup.x, _pickup.z).distance_to(p)
			if d > chosen_d:
				chosen_d = d
				chosen = spot
			if d > 120.0:
				chosen = spot
				break
		var terrain: Terrain = Game.world.terrain
		var dest: Vector2 = chosen.pos
		_dropoff = Vector3(dest.x, terrain.height_at(dest.x, dest.y), dest.y)
		_dropoff_name = chosen.name
		var trip_m := _pickup.distance_to(_dropoff)
		_fare = int(BASE_FARE + trip_m * FARE_PER_M)
		_expected_time = trip_m / 9.0 + 12.0
		_trip_timer = 0.0
		phase = Phase.TO_DROPOFF
		Events.objective_changed.emit("Chở khách tới: %s (%s)" % [_dropoff_name, Game.format_money(_fare)], _dropoff, true)
	)


func _complete_fare() -> void:
	var tip := 0
	if _trip_timer < _expected_time:
		tip = int(_fare * 0.3)
	Game.add_money(_fare + tip, true)
	Game.stats.taxi_fares += 1
	Audio.play_ui("cash")
	if tip > 0:
		Events.toast.emit("💵 %s + tip %s (chạy nhanh!)" % [Game.format_money(_fare), Game.format_money(tip)])
	else:
		Events.toast.emit("💵 Nhận %s tiền cuốc xe" % Game.format_money(_fare))
	# Passenger hops out and wanders off.
	var out_pos: Vector3 = Game.player.vehicle.to_global(Vector3(1.7, 0.1, 0.3))
	_spawn_passenger(out_pos)
	var body: Humanoid = _passenger.get_meta("body")
	var walk_target := out_pos + Vector3(randf_range(-4, 4), 0, randf_range(2, 5))
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
		if _passenger != null and is_instance_valid(_passenger):
			_passenger.global_position = out_pos.lerp(walk_target, t)
			body.tick(0.016, {"mode": "walk", "speed": 0.3})
	, 0.0, 1.0, 2.2)
	tween.tween_callback(_clear_passenger)
	phase = Phase.COOLDOWN
	_cooldown = 3.0
	Events.clear_objective()
	Events.job_ended.emit("taxi", true)
