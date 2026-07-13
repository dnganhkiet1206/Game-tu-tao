class_name PlayerCharacter
extends CharacterBody3D
## Third-person player controller tuned for touch: camera-relative movement
## with acceleration curves, coyote time, jump buffering, step-up assist,
## ledge vaulting, surface swimming, auto-work harvesting and vehicle hand-off.

enum State { GROUND, AIR, SWIM, CLIMB, WORKING, FISHING, DRIVING, LOCKED }

const WALK_SPEED := 2.1
const JOG_SPEED := 4.4
const RUN_SPEED := 6.4
const ACCEL := 26.0
const DECEL := 20.0
const AIR_CONTROL := 0.45
const JUMP_VELOCITY := 5.1
const GRAVITY := 14.0
const SWIM_SPEED := 2.7
const TURN_LERP := 11.0
const COYOTE := 0.12
const JUMP_BUFFER := 0.16
const STEP_HEIGHT := 0.42

var state: int = State.GROUND
var move_input := Vector2.ZERO       # written by HUD joystick, camera-space
var sprint_held := false
var visual: Humanoid
var camera_rig: Node3D = null
var vehicle: Node3D = null

var _coyote := 0.0
var _jump_buffer := 0.0
var _step_distance := 0.0
var _was_in_water := false
var _work_target: ResourceNode = null
var _work_timer := 0.0
var _work_hit_done := false
var _punch_timer := -1.0
var _fishing_ctl: Node = null
var _swim_stroke_timer := 0.0
var _fall_speed_peak := 0.0
var _interactables: Array = []
var _yaw_target := 0.0

@onready var interact_area: Area3D = null


func _ready() -> void:
	add_to_group("player")
	collision_layer = Layers.PLAYER
	collision_mask = Layers.WORLD | Layers.VEHICLE | Layers.NPC
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.7
	col.shape = capsule
	col.position = Vector3(0, 0.85, 0)
	add_child(col)

	visual = Humanoid.make(
		Color(0.85, 0.5, 0.25),   # shirt
		Color(0.25, 0.3, 0.4),    # pants
		Color(0.9, 0.72, 0.58),   # skin
		Color(0.16, 0.12, 0.1))   # hair
	add_child(visual)

	interact_area = Area3D.new()
	interact_area.collision_layer = 0
	interact_area.collision_mask = Layers.INTERACT
	var zone_col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.3
	zone_col.shape = sphere
	zone_col.position = Vector3(0, 1.0, 0)
	interact_area.add_child(zone_col)
	add_child(interact_area)
	interact_area.area_entered.connect(_on_interact_seen)
	interact_area.area_exited.connect(_on_interact_lost)
	interact_area.body_entered.connect(_on_interact_seen)
	interact_area.body_exited.connect(_on_interact_lost)

	Game.player = self
	_yaw_target = rotation.y
	Events.player_spawned.emit(self)


# --- interactables ------------------------------------------------------------

func _on_interact_seen(node: Node3D) -> void:
	if node.has_method("interact") and not _interactables.has(node):
		_interactables.append(node)


func _on_interact_lost(node: Node3D) -> void:
	_interactables.erase(node)


func current_interactable() -> Node3D:
	var best: Node3D = null
	var best_d := 99.0
	var stale: Array = []
	for node in _interactables:
		if not is_instance_valid(node):
			stale.append(node)  # freed nodes never emit body_exited
			continue
		if node.has_method("can_interact") and not node.can_interact(self):
			continue
		var d: float = global_position.distance_to(node.global_position)
		if d < best_d:
			best_d = d
			best = node
	for node in stale:
		_interactables.erase(node)
	return best


func try_interact() -> void:
	if state == State.DRIVING and vehicle != null and vehicle.has_method("eject_driver"):
		vehicle.eject_driver()
		return
	if state == State.FISHING and _fishing_ctl != null:
		_fishing_ctl.call("on_action")
		return
	if state != State.GROUND:
		return
	var target := current_interactable()
	if target != null:
		target.interact(self)


# --- main loop -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	match state:
		State.GROUND, State.AIR:
			_locomotion(delta)
		State.SWIM:
			_swim(delta)
		State.WORKING:
			_working(delta)
		State.FISHING:
			_anim(delta, {"mode": "fish"})
		State.DRIVING:
			_driving(delta)
		State.CLIMB, State.LOCKED:
			_anim(delta, {"mode": "climb" if state == State.CLIMB else "idle"})
	if _punch_timer >= 0.0:
		_punch_timer += delta * 2.6
		if _punch_timer >= 1.0:
			_punch_timer = -1.0


func _gather_move_dir() -> Vector3:
	if Game.ui_blocked:
		return Vector3.ZERO
	var raw := move_input
	var kb := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if kb.length_squared() > raw.length_squared():
		raw = kb
	if raw.length() > 1.0:
		raw = raw.normalized()
	if raw.length_squared() < 0.004:
		return Vector3.ZERO
	var cam_yaw := camera_rig.yaw if camera_rig != null else 0.0
	var basis := Basis(Vector3.UP, cam_yaw)
	return basis * Vector3(raw.x, 0, raw.y)


func _locomotion(delta: float) -> void:
	var dir := _gather_move_dir()
	var input_mag := clampf(dir.length(), 0.0, 1.0)
	var sprinting := sprint_held or Input.is_action_pressed("sprint")
	var target_speed := 0.0
	if input_mag > 0.01:
		if sprinting:
			target_speed = RUN_SPEED
		else:
			target_speed = lerpf(WALK_SPEED, JOG_SPEED, smoothstep(0.35, 1.0, input_mag))
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	var accel := ACCEL if target_speed > horizontal.length() else DECEL
	if state == State.AIR:
		accel *= AIR_CONTROL
	var desired := dir.normalized() * target_speed if input_mag > 0.01 else Vector3.ZERO
	horizontal = horizontal.move_toward(desired, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	# Rotate the body toward travel direction.
	if horizontal.length() > 0.4:
		_yaw_target = atan2(horizontal.x, horizontal.z)
	rotation.y = lerp_angle(rotation.y, _yaw_target, minf(TURN_LERP * delta, 1.0))

	# Jumping with coyote time + buffering.
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER
	if is_on_floor():
		_coyote = COYOTE
		if _fall_speed_peak > 7.0:
			Audio.play_at("step_road", global_position, 2.0, 0.05)
			if camera_rig != null:
				camera_rig.kick(0.25)
		_fall_speed_peak = 0.0
	else:
		_coyote -= delta
		_fall_speed_peak = maxf(_fall_speed_peak, -velocity.y)
	if _jump_buffer > 0.0:
		_jump_buffer -= delta
		if _try_vault():
			_jump_buffer = 0.0
			return  # state is CLIMB now; don't let the code below overwrite it
		if _coyote > 0.0:
			velocity.y = JUMP_VELOCITY
			_coyote = 0.0
			_jump_buffer = 0.0
			Audio.play_at("whoosh", global_position, -12.0)

	velocity.y -= GRAVITY * delta
	move_and_slide()
	_step_up_assist(dir)

	# Water check.
	var water_y := _water_level()
	var depth := water_y - global_position.y
	if depth > 1.05:
		_enter_swim(depth)
		return
	state = State.AIR if not is_on_floor() else State.GROUND

	# Footsteps.
	if state == State.GROUND:
		var speed := Vector3(velocity.x, 0, velocity.z).length()
		if speed > 0.5:
			_step_distance += speed * delta
			var stride := 0.85 if speed < 5.0 else 1.05
			if _step_distance >= stride:
				_step_distance = 0.0
				_play_footstep(speed)

	# Animation.
	var speed_norm := clampf(Vector3(velocity.x, 0, velocity.z).length() / RUN_SPEED, 0.0, 1.0)
	if _punch_timer >= 0.0:
		_anim(delta, {"mode": "punch", "punch_t": _punch_timer})
	elif state == State.AIR:
		_anim(delta, {"mode": "air"})
	elif speed_norm > 0.03:
		_anim(delta, {"mode": "walk", "speed": smoothstep(0.15, 1.0, speed_norm)})
	else:
		_anim(delta, {"mode": "idle"})


func _play_footstep(speed: float) -> void:
	var sound := "step_grass"
	if is_instance_valid(Game.world):
		var collider: Object = null
		var col := get_last_slide_collision()
		if col != null:
			collider = col.get_collider()
		sound = Game.world.step_sound_for(collider, global_position)
	var vol := -8.0 + clampf(speed / RUN_SPEED, 0.0, 1.0) * 6.0
	Audio.play_at(sound, global_position, vol)


## Silent step-up for kerbs / thresholds up to STEP_HEIGHT.
func _step_up_assist(dir: Vector3) -> void:
	if dir.length_squared() < 0.01 or not is_on_wall() or not is_on_floor():
		return
	var space := get_world_3d().direct_space_state
	var forward := dir.normalized()
	var origin := global_position + Vector3(0, STEP_HEIGHT + 0.35, 0) + forward * 0.5
	var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3(0, -(STEP_HEIGHT + 0.3), 0), Layers.WORLD)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var rise: float = hit.position.y - global_position.y
	if rise > 0.04 and rise <= STEP_HEIGHT and hit.normal.y > 0.75:
		# Make sure there is headroom.
		var head_query := PhysicsRayQueryParameters3D.create(hit.position + Vector3(0, 0.1, 0), hit.position + Vector3(0, 1.7, 0), Layers.WORLD)
		if space.intersect_ray(head_query).is_empty():
			global_position = hit.position + Vector3(0, 0.02, 0)


## Vault onto ledges up to ~2.2 m when jumping at a wall.
func _try_vault() -> bool:
	if state != State.GROUND and state != State.AIR:
		return false
	# The rig is modeled facing +Z, so +basis.z is our forward.
	var forward := global_transform.basis.z.slide(Vector3.UP)
	if forward.length_squared() < 0.3:
		return false
	forward = forward.normalized()
	var space := get_world_3d().direct_space_state
	var chest_from := global_position + Vector3(0, 1.0, 0)
	var chest_query := PhysicsRayQueryParameters3D.create(chest_from, chest_from + forward * 0.9, Layers.WORLD)
	var wall := space.intersect_ray(chest_query)
	if wall.is_empty():
		return false
	var top_from: Vector3 = wall.position + forward * 0.35 + Vector3(0, 2.0, 0)
	var top_query := PhysicsRayQueryParameters3D.create(top_from, top_from + Vector3(0, -2.4, 0), Layers.WORLD)
	var top := space.intersect_ray(top_query)
	if top.is_empty() or top.normal.y < 0.7:
		return false
	var rise: float = top.position.y - global_position.y
	if rise < STEP_HEIGHT or rise > 2.2:
		return false
	_start_climb(top.position + forward * 0.15)
	return true


func _start_climb(target: Vector3) -> void:
	state = State.CLIMB
	velocity = Vector3.ZERO
	set_collision_mask_value(1, false)
	Audio.play_at("whoosh", global_position, -8.0)
	var up_point := Vector3(global_position.x, target.y + 0.05, global_position.z)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "global_position", up_point, 0.38)
	tween.tween_property(self, "global_position", target + Vector3(0, 0.02, 0), 0.22)
	tween.tween_callback(func() -> void:
		set_collision_mask_value(1, true)
		state = State.GROUND
	)


# --- swim ------------------------------------------------------------------------

func _water_level() -> float:
	if not is_instance_valid(Game.world):
		return -1000.0
	return Game.world.terrain.water_level_at(global_position.x, global_position.z)


func _enter_swim(_depth: float) -> void:
	if state != State.SWIM:
		state = State.SWIM
		Audio.play_at("splash", global_position, 0.0)


func _swim(delta: float) -> void:
	var water_y := _water_level()
	var dir := _gather_move_dir()
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	horizontal = horizontal.move_toward(dir.normalized() * SWIM_SPEED if dir.length() > 0.05 else Vector3.ZERO, 10.0 * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	# Bob to the surface (head above water).
	var target_y := water_y - 1.25
	velocity.y = clampf((target_y - global_position.y) * 4.0, -3.0, 3.0)
	if horizontal.length() > 0.4:
		_yaw_target = atan2(horizontal.x, horizontal.z)
	rotation.y = lerp_angle(rotation.y, _yaw_target, minf(8.0 * delta, 1.0))
	move_and_slide()
	# Stroke sounds.
	if horizontal.length() > 0.6:
		_swim_stroke_timer -= delta
		if _swim_stroke_timer <= 0.0:
			_swim_stroke_timer = 0.9
			Audio.play_at("swim_stroke", global_position, -6.0)
	# Exit when ground is shallow.
	var ground_y: float = Game.world.terrain.height_at(global_position.x, global_position.z)
	if water_y - ground_y < 1.0 and is_on_floor():
		state = State.GROUND
	elif water_y < -100.0:
		state = State.AIR
	_anim(delta, {"mode": "swim"})


# --- work (chop / mine) ------------------------------------------------------------

func start_working(target: ResourceNode) -> void:
	if state != State.GROUND:
		return
	state = State.WORKING
	_work_target = target
	_work_timer = 0.0
	_work_hit_done = false
	velocity = Vector3.ZERO
	visual.set_tool(target.required_tool())
	var to_target := target.global_position - global_position
	_yaw_target = atan2(to_target.x, to_target.z)


func _working(delta: float) -> void:
	if _work_target == null or not is_instance_valid(_work_target) or not _work_target.alive:
		_stop_working()
		return
	if _gather_move_dir().length() > 0.45 or Input.is_action_just_pressed("jump"):
		_stop_working()
		return
	rotation.y = lerp_angle(rotation.y, _yaw_target, minf(10.0 * delta, 1.0))
	var cycle := 1.0 if _work_target.kind == "tree" else 0.9
	_work_timer += delta / cycle
	if _work_timer >= 1.0:
		_work_timer -= 1.0
		_work_hit_done = false
	if not _work_hit_done and _work_timer >= 0.72:
		_work_hit_done = true
		var standing := _work_target.take_hit(global_position)
		if camera_rig != null:
			camera_rig.kick(0.1)
		if not standing:
			_stop_working()
			return
	_anim(delta, {
		"mode": "work",
		"work_phase": _work_timer,
		"work_kind": "chop" if _work_target.kind == "tree" else "mine",
	})


func _stop_working() -> void:
	_work_target = null
	visual.set_tool("")
	if state == State.WORKING:
		state = State.GROUND


# --- fishing ---------------------------------------------------------------------

func start_fishing() -> void:
	if state != State.GROUND:
		return
	var ctl := get_tree().get_first_node_in_group("fishing")
	if ctl != null:
		state = State.FISHING
		_fishing_ctl = ctl
		velocity = Vector3.ZERO
		visual.set_tool("rod")
		ctl.call("begin", self)


func end_fishing() -> void:
	_fishing_ctl = null
	visual.set_tool("")
	if state == State.FISHING:
		state = State.GROUND


func face_towards(point: Vector3) -> void:
	var to_point := point - global_position
	_yaw_target = atan2(to_point.x, to_point.z)
	rotation.y = _yaw_target


# --- punch / crime ------------------------------------------------------------------

func try_punch() -> void:
	if state != State.GROUND or _punch_timer >= 0.0:
		return
	_punch_timer = 0.0
	Audio.play_at("whoosh", global_position, -4.0)
	var hit_something := false
	var origin := global_position + Vector3(0, 1.0, 0)
	var forward := global_transform.basis.z
	for npc in get_tree().get_nodes_in_group("npc"):
		var to_npc: Vector3 = npc.global_position - global_position
		if to_npc.length() < 1.7 and forward.dot(to_npc.normalized()) > 0.35:
			if npc.has_method("on_punched"):
				npc.on_punched(self)
				hit_something = true
				break
	# Smashing parked cars counts as vandalism (with a per-car cooldown so
	# one flurry of punches doesn't stack stars instantly).
	if not hit_something:
		for car in get_tree().get_nodes_in_group("vehicle"):
			var to_car: Vector3 = car.global_position - global_position
			if to_car.length() < 2.6 and forward.dot(to_car.normalized()) > 0.3:
				hit_something = true
				var now := Time.get_ticks_msec()
				var last: int = car.get_meta("last_vandal_ms", -100000)
				if now - last > 8000:
					car.set_meta("last_vandal_ms", now)
					Events.crime_committed.emit("vandalism", car.global_position)
					Events.toast.emit("Bạn vừa đập phá xe của người khác!")
				break
	if hit_something:
		Audio.play_at("punch", origin + forward, 2.0)
		if camera_rig != null:
			camera_rig.kick(0.18)


# --- driving ---------------------------------------------------------------------

func enter_vehicle(v: Node3D) -> void:
	if state != State.GROUND:
		return
	state = State.LOCKED
	vehicle = v
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	var seat: Vector3 = v.call("seat_global_position")
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "global_position", seat, 0.42)
	tween.parallel().tween_property(self, "rotation:y", v.global_rotation.y, 0.42)
	tween.tween_callback(func() -> void:
		state = State.DRIVING
		v.call("set_driver", self)
		Events.player_entered_vehicle.emit(v)
	)


func _driving(delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		exit_vehicle_at(global_position)
		return
	var seat: Vector3 = vehicle.call("seat_global_position")
	global_position = seat
	rotation.y = lerp_angle(rotation.y, vehicle.global_rotation.y, minf(14.0 * delta, 1.0))
	_anim(delta, {"mode": "sit"})


func exit_vehicle_at(spot: Vector3) -> void:
	var old_vehicle := vehicle
	vehicle = null
	state = State.LOCKED
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "global_position", spot, 0.4)
	tween.tween_callback(func() -> void:
		collision_layer = Layers.PLAYER
		collision_mask = Layers.WORLD | Layers.VEHICLE | Layers.NPC
		state = State.GROUND
		velocity = Vector3.ZERO
		if old_vehicle != null:
			Events.player_exited_vehicle.emit(old_vehicle)
	)


# --- busted / respawn ----------------------------------------------------------------

func busted(fine: int) -> void:
	if state == State.DRIVING and vehicle != null and vehicle.has_method("eject_driver"):
		vehicle.eject_driver()
	state = State.LOCKED
	velocity = Vector3.ZERO
	Events.player_busted.emit(fine)


func teleport_to(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	state = State.GROUND


func _anim(delta: float, params: Dictionary) -> void:
	visual.tick(delta, params)
