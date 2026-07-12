class_name DeliveryJob
extends Node
## Delivery work: take a stack of packages at the shop, drop one at each
## marked house door. Finish the whole round fast for a bonus.

const PAY_PER_DROP := 22
const ROUND_BONUS := 45
const ROUND_TIME := 240.0

var active := false
var _targets: Array = []       # [{id, pos}]
var _timer := 0.0


func _ready() -> void:
	add_to_group("delivery_job")


func start() -> void:
	if active:
		Events.toast.emit("Bạn đang giao dở một chuyến rồi!")
		return
	var homes := []
	for b in MapLayout.BUILDINGS:
		if b.kind == "home":
			homes.append(b)
	homes.shuffle()
	_targets.clear()
	for i in 3:
		var entry: Dictionary = homes[i]
		_targets.append({"id": entry.id, "pos": Game.world.door_global(entry.id)})
	active = true
	_timer = 0.0
	Game.add_item("package", 3)
	Audio.play_ui("pickup")
	Events.job_started.emit("delivery")
	Events.toast.emit("📦 Nhận 3 kiện hàng. Giao theo mũi tên!")
	_point_to_next()


func _point_to_next() -> void:
	if _targets.is_empty():
		return
	var target: Dictionary = _nearest_target()
	Events.objective_changed.emit("Giao hàng (còn %d kiện)" % _targets.size(), target.pos, true)


func _nearest_target() -> Dictionary:
	var best: Dictionary = _targets[0]
	var best_d := 999999.0
	var player_pos: Vector3 = Game.player.global_position
	for t in _targets:
		var d: float = player_pos.distance_to(t.pos)
		if d < best_d:
			best_d = d
			best = t
	return best


func _process(delta: float) -> void:
	if not active or not is_instance_valid(Game.player):
		return
	_timer += delta
	var target: Dictionary = _nearest_target()
	var dist: float = Game.player.global_position.distance_to(target.pos)
	if dist < 2.6 and Game.player.state == PlayerCharacter.State.GROUND:
		_deliver(target)


func _deliver(target: Dictionary) -> void:
	_targets.erase(target)
	Game.remove_item("package", 1)
	Game.add_money(PAY_PER_DROP, true)
	Audio.play_ui("cash")
	# Knock on the door for flavor.
	var b: GameBuilding = Game.world.get_building(target.id)
	if b != null and b.door != null:
		b.door.open_for(1.8)
	if _targets.is_empty():
		active = false
		Game.stats.deliveries += 1
		Events.clear_objective()
		Events.job_ended.emit("delivery", true)
		if _timer < ROUND_TIME:
			Game.add_money(ROUND_BONUS, true)
			Events.toast.emit("🎉 Giao đủ 3 kiện + thưởng nhanh %s!" % Game.format_money(ROUND_BONUS))
		else:
			Events.toast.emit("Đã giao đủ 3 kiện hàng!")
	else:
		Events.toast.emit("Đã giao 1 kiện (+%s)" % Game.format_money(PAY_PER_DROP))
		_point_to_next()
