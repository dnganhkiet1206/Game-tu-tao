class_name PoliceManager
extends Node
## Simple wanted system: crimes raise stars, officers chase, getting caught
## costs a fine and a trip to the station, staying out of sight clears stars.

const MAX_WANTED := 3
const FINE_PER_STAR := 90
const EVADE_SECONDS := 22.0

var wanted := 0
var _evade_timer := 0.0


func _ready() -> void:
	add_to_group("police_manager")
	Events.crime_committed.connect(_on_crime)


func _on_crime(kind: String, _pos: Vector3) -> void:
	var add := 1
	match kind:
		"assault":
			add = 1
		"car_theft":
			add = 1
		"assault_police":
			add = 2
		"vandalism":
			add = 1
	set_wanted(wanted + add)
	Audio.play_ui("denied", -6.0)


func set_wanted(level: int) -> void:
	var new_level: int = clampi(level, 0, MAX_WANTED)
	if new_level == wanted:
		return
	wanted = new_level
	_evade_timer = 0.0
	Events.wanted_changed.emit(wanted)
	if wanted > 0:
		Events.toast.emit("⭐ Cảnh sát đang truy đuổi bạn!")


func _process(delta: float) -> void:
	if wanted <= 0 or not is_instance_valid(Game.player):
		return
	# Evade: stay far from every officer long enough and the heat dies down.
	var nearest := 9999.0
	for officer in get_tree().get_nodes_in_group("police"):
		nearest = minf(nearest, officer.global_position.distance_to(Game.player.global_position))
	if nearest > 42.0:
		_evade_timer += delta
		if _evade_timer >= EVADE_SECONDS:
			set_wanted(0)
			Events.toast.emit("Bạn đã thoát khỏi cảnh sát.")
	else:
		_evade_timer = maxf(_evade_timer - delta * 2.0, 0.0)


func bust_player() -> void:
	if wanted <= 0:
		return
	var fine: int = mini(FINE_PER_STAR * wanted, Game.money)
	Game.player.busted(fine)
	Game.add_money(-fine, true)
	Game.stats.fines_paid += fine
	set_wanted(0)
	Events.toast.emit("Bạn bị bắt! Nộp phạt %s" % Game.format_money(fine))


## Paying at the police counter clears the stars without the trip.
func pay_off() -> void:
	if wanted <= 0:
		Events.toast.emit("Bạn không bị truy nã.")
		return
	var fine := FINE_PER_STAR * wanted
	if Game.try_spend(fine):
		set_wanted(0)
		Audio.play_ui("cash")
		Events.toast.emit("Đã nộp phạt. Hồ sơ trong sạch!")
