class_name FuelPump
extends StaticBody3D
## A petrol pump: interact to start/stop filling the nearest car.
## Charges per liter while pouring; stops on full tank, empty wallet,
## or when the car / player walks away.

const PRICE_PER_LITER := 2
const FILL_RATE := 3.0     # liters per second
const CAR_RANGE := 7.0

var _active_vehicle: Vehicle = null
var _player: Node3D = null
var _liter_accum := 0.0
var _pump_audio: AudioStreamPlayer3D


func _ready() -> void:
	collision_layer = Layers.WORLD
	collision_mask = 0
	var st := Props.begin()
	var red := Color(0.85, 0.28, 0.24)
	Props.add_box(st, Vector3(0, 0.09, 0), Vector3(1.1, 0.18, 0.7), Color(0.45, 0.45, 0.46))
	Props.add_box(st, Vector3(0, 0.7, 0), Vector3(0.55, 1.1, 0.4), red)
	Props.add_box(st, Vector3(0, 1.02, 0.21), Vector3(0.4, 0.3, 0.03), Color(0.92, 0.93, 0.95))
	Props.add_box(st, Vector3(0, 1.3, 0), Vector3(0.6, 0.12, 0.45), red.darkened(0.15))
	Props.add_box(st, Vector3(0.31, 0.75, 0), Vector3(0.08, 0.3, 0.14), Color(0.15, 0.15, 0.17))
	var mesh := MeshInstance3D.new()
	mesh.mesh = Props.commit(st)
	add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.8, 1.5, 0.6)
	col.shape = shape
	col.position = Vector3(0, 0.75, 0)
	add_child(col)

	var zone := InteractZone.make(Vector3(0, 0.8, 0), 2.0, "", _on_interact)
	zone.prompt_provider = _prompt
	add_child(zone)

	_pump_audio = AudioStreamPlayer3D.new()
	_pump_audio.stream = Audio.get_loop_stream("fuel_pump")
	_pump_audio.unit_size = 4.0
	_pump_audio.max_distance = 25.0
	add_child(_pump_audio)
	set_process(false)


func _prompt() -> String:
	if _active_vehicle != null:
		return "Ngừng bơm"
	return "Đổ xăng (%d₫/L)" % PRICE_PER_LITER


func _on_interact(player: Node3D) -> void:
	if _active_vehicle != null:
		_stop()
		return
	var best: Vehicle = null
	var best_d := CAR_RANGE
	for car in get_tree().get_nodes_in_group("vehicle"):
		if not car is Vehicle or (car as Vehicle).owner_tag == "display":
			continue
		var d: float = car.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = car
	if best == null:
		Events.toast.emit("Đưa xe lại gần trụ xăng đã nhé.")
		Audio.play_ui("denied")
		return
	if best.fuel >= best.fuel_capacity - 0.1:
		Events.toast.emit("Bình xăng xe này đầy rồi.")
		return
	_active_vehicle = best
	_player = player
	_liter_accum = 0.0
	_pump_audio.play()
	set_process(true)


func _stop() -> void:
	if _active_vehicle != null and _liter_accum > 0.0:
		Events.toast.emit("⛽ Đã đổ xăng — bình còn %d%%" % int(_active_vehicle.fuel / _active_vehicle.fuel_capacity * 100.0))
	_active_vehicle = null
	_player = null
	_pump_audio.stop()
	set_process(false)


func _process(delta: float) -> void:
	if _active_vehicle == null or not is_instance_valid(_active_vehicle):
		_stop()
		return
	# Walked or drove away? Shut the pump off.
	if _active_vehicle.global_position.distance_to(global_position) > CAR_RANGE + 1.0 \
			or absf(_active_vehicle.speed) > 0.5 \
			or (_player != null and is_instance_valid(_player)
				and _player.global_position.distance_to(global_position) > 5.0):
		_stop()
		return
	_liter_accum += FILL_RATE * delta
	while _liter_accum >= 1.0:
		_liter_accum -= 1.0
		if _active_vehicle.fuel >= _active_vehicle.fuel_capacity - 0.05:
			Events.toast.emit("⛽ Bình đầy!")
			Audio.play_ui("cash")
			_stop()
			return
		if not Game.try_spend(PRICE_PER_LITER):
			_stop()
			return
		_active_vehicle.refuel(1.0)