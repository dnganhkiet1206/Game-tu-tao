class_name PoliceOfficer
extends NPC
## Police NPC: patrols the station block; when the player is wanted they
## give chase on foot and bust the player on contact.

const CHASE_SPEED := 5.9
const CATCH_DISTANCE := 1.8

var _repath_timer := 0.0
var _patrol_points: Array[Vector3] = []
var _patrol_index := 0
var _patrol_wait := 0.0


func _ready() -> void:
	super()
	add_to_group("police")
	var world := Game.world
	if world != null:
		_patrol_points = [
			world.door_global("police") + Vector3(2, 0, 3),
			Vector3(420, world.terrain.height_at(420, 392), 392),
			Vector3(452, world.terrain.height_at(452, 398), 398),
		]


func tick(delta: float) -> void:
	var manager := get_tree().get_first_node_in_group("police_manager")
	var wanted: int = manager.wanted if manager != null else 0
	if wanted > 0 and is_instance_valid(Game.player):
		_chase(delta, manager)
		return
	# Off duty at night: stand inside the station (still visible via window).
	_patrol(delta)


func _patrol(delta: float) -> void:
	if _patrol_points.is_empty():
		visual.tick(delta, {"mode": "idle"})
		return
	if _patrol_wait > 0.0:
		_patrol_wait -= delta
		visual.tick(delta, {"mode": "idle"})
		return
	var target := _patrol_points[_patrol_index]
	var to_target := target - global_position
	to_target.y = 0.0
	if to_target.length() < 1.2:
		_patrol_index = (_patrol_index + 1) % _patrol_points.size()
		_patrol_wait = randf_range(4.0, 9.0)
		return
	var dir := to_target.normalized()
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), minf(8.0 * delta, 1.0))
	velocity = dir * WALK_SPEED + Vector3(0, -4.0, 0)
	move_and_slide()
	visual.tick(delta, {"mode": "walk", "speed": 0.3})


func _chase(delta: float, manager: Node) -> void:
	var player: PlayerCharacter = Game.player
	var to_player := player.global_position - global_position
	var dist := to_player.length()
	if dist < CATCH_DISTANCE and player.state != PlayerCharacter.State.DRIVING:
		if manager != null:
			manager.bust_player()
		return
	# Direct pursuit when close, road path when far.
	if dist < 26.0:
		var dir := to_player.normalized()
		dir.y = 0.0
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), minf(10.0 * delta, 1.0))
		velocity = dir * CHASE_SPEED + Vector3(0, -4.0, 0)
		move_and_slide()
	else:
		_repath_timer -= delta
		if _repath_timer <= 0.0 or _path_index >= _path.size():
			_repath_timer = 1.6
			_path = Game.world.road_graph.path(global_position, player.global_position)
			_path_index = 0
		_follow_path(delta, CHASE_SPEED)
	visual.tick(delta, {"mode": "walk", "speed": 1.0})


func on_punched(_attacker: Node3D) -> void:
	# Officers don't flee — assaulting police escalates the wanted level.
	Events.crime_committed.emit("assault_police", global_position)
	var tween := create_tween()
	tween.tween_property(visual, "rotation:x", -0.2, 0.08)
	tween.tween_property(visual, "rotation:x", 0.0, 0.2)


func get_prompt() -> String:
	return "Nói chuyện"


func can_interact(_player: Node3D) -> bool:
	var manager := get_tree().get_first_node_in_group("police_manager")
	return manager == null or manager.wanted == 0
