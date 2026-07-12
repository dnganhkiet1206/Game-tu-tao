class_name NPC
extends CharacterBody3D
## A resident with a simple daily life: sleep at home, walk to work along
## the roads, lunch at the cafe, evening stroll, back to bed. Far from the
## player they glide cheaply on the road graph; nearby they get real physics.

enum Mode { HIDDEN, IDLE, WALKING, TALKING, FLEEING }

const WALK_SPEED := 1.7
const FLEE_SPEED := 4.6
const PHYSICS_RANGE := 32.0

var data: Dictionary = {}
var mode: int = Mode.IDLE
var visual: Humanoid
var anchor_anim := "idle"

var _path: PackedVector3Array = PackedVector3Array()
var _path_index := 0
var _goal_key := ""       # schedule slot currently satisfied
var _talk_timer := 0.0
var _flee_timer := 0.0
var _lane_offset := 0.0
var _label: Label3D


static func make(p_data: Dictionary) -> NPC:
	var npc := NPC.new()
	npc.data = p_data
	npc.name = "NPC_" + p_data.id
	return npc


func _ready() -> void:
	add_to_group("npc")
	collision_layer = Layers.NPC | Layers.INTERACT
	collision_mask = Layers.WORLD
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.33
	capsule.height = 1.68
	col.shape = capsule
	col.position = Vector3(0, 0.84, 0)
	add_child(col)

	var palette := NpcData.palette_for(data.id)
	if data.role == "police":
		palette = [Color(0.2, 0.35, 0.55), Color(0.16, 0.22, 0.3), palette[2], Color(0.1, 0.09, 0.08)]
	visual = Humanoid.make(palette[0], palette[1], palette[2], palette[3])
	add_child(visual)

	_label = Label3D.new()
	_label.text = data.name
	_label.font_size = 60
	_label.outline_size = 12
	_label.pixel_size = 0.004
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 2.05, 0)
	_label.modulate = Color(1, 1, 1, 0.85)
	_label.visibility_range_end = 16.0
	add_child(_label)

	_lane_offset = fmod(float(hash(data.id) % 100), 5.0) - 2.5


# --- schedule ---------------------------------------------------------------------

## Where this NPC should be for the current hour. Returns
## [key, world_target, hidden, anim]
func _current_slot() -> Array:
	var h := DayNight.time_hours
	var role: String = data.role
	var world := Game.world
	if h < 6.25 or h >= 21.0:
		return ["sleep", _home_pos(), true, "idle"]
	if h < 7.75:
		return ["morning", _home_pos() + Vector3(1.5, 0, 1.5), false, "idle"]
	if h < 11.5 or (h >= 13.0 and h < 17.5):
		var slot_key := "work_am" if h < 11.5 else "work_pm"
		if data.work is String:
			var marker: Vector3 = world.marker_global(data.work, "vendor")
			return [slot_key, marker, false, anchor_anim]
		var spot: Vector2 = data.work
		return [slot_key, Vector3(spot.x, world.terrain.height_at(spot.x, spot.y), spot.y), false, data.anim]
	if h < 13.0:
		# Lunch: half go to the cafe, half eat at their spot.
		if hash(data.id) % 2 == 0:
			var eat_marker := "eat_1" if hash(data.id) % 4 < 2 else "eat_2"
			return ["lunch", world.marker_global("cafe", eat_marker), false, "idle"]
		return ["lunch", _work_pos(), false, "idle"]
	# Evening leisure.
	var leisure := [Vector2(420, 384), Vector2(126, 460), Vector2(634, 246), Vector2(360, 392)]
	var p: Vector2 = leisure[hash(data.id) % leisure.size()]
	return ["evening", Vector3(p.x, world.terrain.height_at(p.x, p.y), p.y), false, "talk" if hash(data.id) % 3 == 0 else "idle"]


func _home_pos() -> Vector3:
	var world := Game.world
	if data.home != "":
		return world.door_global(data.home)
	if data.work is String:
		return world.door_global(data.work)
	return global_position


func _work_pos() -> Vector3:
	var world := Game.world
	if data.work is String:
		return world.marker_global(data.work, "vendor")
	var spot: Vector2 = data.work
	return Vector3(spot.x, world.terrain.height_at(spot.x, spot.y), spot.y)


## Jump straight to wherever the schedule says (used at spawn/load).
func snap_to_schedule() -> void:
	var slot := _current_slot()
	_goal_key = slot[0]
	global_position = slot[1]
	if slot[2]:
		mode = Mode.HIDDEN
		visible = false
		collision_layer = 0
	else:
		mode = Mode.IDLE
		anchor_anim = slot[3]


func tick(delta: float) -> void:
	match mode:
		Mode.TALKING:
			_talk_timer -= delta
			if _talk_timer <= 0.0:
				mode = Mode.IDLE
			visual.tick(delta, {"mode": "talk"})
			return
		Mode.FLEEING:
			_flee_timer -= delta
			if _flee_timer <= 0.0:
				mode = Mode.IDLE
				_goal_key = ""  # re-plan
			else:
				_follow_path(delta, FLEE_SPEED)
				visual.tick(delta, {"mode": "walk", "speed": 1.0})
				return
	var slot := _current_slot()
	var key: String = slot[0]
	var target: Vector3 = slot[1]
	var hidden: bool = slot[2]
	var anim: String = slot[3]
	if key != _goal_key:
		_goal_key = key
		_start_moving_to(target, hidden)
	match mode:
		Mode.HIDDEN:
			pass
		Mode.WALKING:
			_follow_path(delta, WALK_SPEED)
			visual.tick(delta, {"mode": "walk", "speed": 0.35})
		Mode.IDLE:
			visual.tick(delta, {"mode": anim})


func _start_moving_to(target: Vector3, hide_at_end: bool) -> void:
	var player_pos := Vector3.ZERO
	var player_far := true
	if is_instance_valid(Game.player):
		player_pos = Game.player.global_position
		player_far = global_position.distance_to(player_pos) > 55.0 and target.distance_to(player_pos) > 55.0
	if mode == Mode.HIDDEN and not hide_at_end:
		# Step out of the building.
		visible = true
		collision_layer = Layers.NPC | Layers.INTERACT
		var b := _building_node()
		if b != null and b.door != null:
			b.door.open_for(1.4)
	if player_far:
		# Teleport when far away: nobody sees it and it saves the pathing.
		global_position = target
		_arrive(hide_at_end)
		return
	_path = Game.world.road_graph.path(global_position, target)
	_path_index = 0
	mode = Mode.WALKING
	_hide_at_end = hide_at_end


var _hide_at_end := false


func _follow_path(delta: float, speed: float) -> void:
	if _path_index >= _path.size():
		_arrive(_hide_at_end)
		return
	var next := _path[_path_index]
	# Walk beside the road center, not on it.
	if _path_index < _path.size() - 1:
		var dir2 := Vector3(next.x - global_position.x, 0, next.z - global_position.z)
		if dir2.length() > 0.1:
			var perp := dir2.normalized().cross(Vector3.UP)
			next += perp * _lane_offset * 0.6
	var to_next := next - global_position
	to_next.y = 0.0
	if to_next.length() < 0.8:
		_path_index += 1
		return
	var dir := to_next.normalized()
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), minf(8.0 * delta, 1.0))
	var use_physics := false
	if is_instance_valid(Game.player):
		use_physics = global_position.distance_to(Game.player.global_position) < PHYSICS_RANGE
	if use_physics:
		velocity = dir * speed + Vector3(0, -4.0, 0)
		move_and_slide()
		# Politely open doors we bump into.
		for i in get_slide_collision_count():
			var collider := get_slide_collision(i).get_collider()
			if collider is Door and not (collider as Door).is_open:
				(collider as Door).open_for(2.0)
	else:
		global_position += dir * speed * delta
		global_position.y = Game.world.terrain.height_at(global_position.x, global_position.z)


func _arrive(hide_now: bool) -> void:
	_path = PackedVector3Array()
	if hide_now:
		mode = Mode.HIDDEN
		visible = false
		collision_layer = 0
		var b := _building_node()
		if b != null and b.door != null and is_instance_valid(Game.player) \
				and global_position.distance_to(Game.player.global_position) < 40.0:
			b.door.open_for(1.4)
	else:
		mode = Mode.IDLE


func _building_node() -> GameBuilding:
	var target_id: String = data.home
	if target_id == "" and data.work is String:
		target_id = data.work
	if target_id == "":
		return null
	return Game.world.get_building(target_id)


# --- interaction -------------------------------------------------------------------

func get_prompt() -> String:
	return "Nói chuyện"


func can_interact(_player: Node3D) -> bool:
	return mode == Mode.IDLE or mode == Mode.WALKING or mode == Mode.TALKING


func interact(player: Node3D) -> void:
	mode = Mode.TALKING
	_talk_timer = 5.0
	var to_player: Vector3 = player.global_position - global_position
	rotation.y = atan2(to_player.x, to_player.z)
	Audio.play_at("npc_talk", global_position, -4.0)
	Events.dialogue_opened.emit(data.name, get_line())


func get_line() -> String:
	return NpcData.line_for(data.role)


func on_punched(attacker: Node3D) -> void:
	if mode == Mode.HIDDEN:
		return
	Events.crime_committed.emit("assault", global_position)
	mode = Mode.FLEEING
	_flee_timer = 14.0
	# Run somewhere far from the attacker.
	var away := (global_position - attacker.global_position)
	away.y = 0.0
	var flee_target := global_position + away.normalized() * 40.0
	flee_target.x = clampf(flee_target.x, 100.0, 760.0)
	flee_target.z = clampf(flee_target.z, 60.0, 760.0)
	flee_target.y = Game.world.terrain.height_at(flee_target.x, flee_target.z)
	_path = Game.world.road_graph.path(global_position, flee_target)
	_path_index = 0
	# Stagger visual.
	var tween := create_tween()
	tween.tween_property(visual, "rotation:x", -0.25, 0.08)
	tween.tween_property(visual, "rotation:x", 0.0, 0.2)
