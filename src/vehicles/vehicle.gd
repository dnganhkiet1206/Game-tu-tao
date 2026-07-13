class_name Vehicle
extends CharacterBody3D
## Arcade car tuned for touch: kinematic body, smooth accel/steer curves,
## ground alignment, working doors with enter/exit animation, engine audio
## with speed pitch, headlights at night. Parked cars sleep (no physics).

const KINDS := {
	"taxi": {"color": Color(0.95, 0.78, 0.1), "top_speed": 17.0, "accel": 9.0, "tank": 35.0},
	"civic": {"color": Color(0.4, 0.55, 0.7), "top_speed": 17.0, "accel": 8.5, "tank": 30.0},
	"pickup": {"color": Color(0.45, 0.5, 0.4), "top_speed": 15.0, "accel": 8.0, "tank": 40.0},
	"minica": {"color": Color(0.85, 0.35, 0.2), "top_speed": 16.0, "accel": 8.5, "tank": 25.0},
	"sedan": {"color": Color(0.15, 0.4, 0.75), "top_speed": 22.0, "accel": 11.0, "tank": 35.0},
}

const CAN_LITERS := 10.0

const STEER_SPEED := 1.9
const BRAKE_DECEL := 14.0
const DRAG := 0.5
const GRAVITY := 16.0

var kind := "civic"
var owner_tag := ""        # "" free | "npc" stealable | "player" bought
var vid := ""
var speed := 0.0
var driver: Node3D = null
var stolen_reported := false

# Ambient AI driving (ping-pong patrol along a road polyline).
const AI_SPEED := 7.5
var ai_route: Array = []
var _ai_index := 0
var _ai_step := 1

# Fuel. AI/display cars never consume.
var fuel := 20.0
var fuel_capacity := 30.0
var _fuel_warned := false
var _engine_dead := false
var _fuel_saved_at := 0.0

# Trunk (not on pickups — they have an open bed).
var is_trunk_open := false
var trunk_has_can := false
var _trunk: Node3D = null

var _door_l: Node3D
var _wheels: Array[Node3D] = []
var _wheel_spin := 0.0
var _steer_visual := 0.0
var _engine: AudioStreamPlayer3D
var _headlights: Array[SpotLight3D] = []
var _passenger_seat: Node3D
var _vy := 0.0
var _skid_cooldown := 0.0


static func make(p_kind: String, p_owner: String, p_id: String) -> Vehicle:
	var v := Vehicle.new()
	v.kind = p_kind
	v.owner_tag = p_owner
	v.vid = p_id
	return v


func _ready() -> void:
	add_to_group("vehicle")
	if kind == "taxi":
		add_to_group("taxi")
	collision_layer = Layers.VEHICLE
	collision_mask = Layers.WORLD | Layers.VEHICLE | Layers.PLAYER | Layers.NPCS
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 1.2, 4.0)
	col.shape = box
	col.position = Vector3(0, 0.8, 0)
	add_child(col)

	_build_visual()

	_engine = AudioStreamPlayer3D.new()
	_engine.stream = Audio.get_loop_stream("car_engine")
	_engine.unit_size = 8.0
	_engine.max_distance = 60.0
	_engine.volume_db = -60.0
	add_child(_engine)

	fuel_capacity = KINDS[kind].tank
	fuel = float(Game.fuel_levels.get(vid, fuel_capacity * 0.65))
	_fuel_saved_at = fuel
	trunk_has_can = owner_tag == "player" or kind == "taxi"

	if owner_tag == "display":
		# Showroom car: not enterable, shows its price tag instead.
		var tag := Label3D.new()
		var spec_name: String = Game.CAR_CATALOG[kind].name if Game.CAR_CATALOG.has(kind) else kind
		var price: int = Game.CAR_CATALOG[kind].price if Game.CAR_CATALOG.has(kind) else 0
		tag.text = "%s\n%s" % [spec_name, Game.format_money(price)]
		tag.font_size = 90
		tag.outline_size = 16
		tag.pixel_size = 0.004
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0, 2.3, 0)
		add_child(tag)
	else:
		var zone := InteractZone.make(Vector3(1.35, 0.8, 0.4), 1.5, _door_prompt(), _on_enter_requested)
		zone.prompt_provider = _door_prompt
		add_child(zone)
		if kind != "pickup":
			_build_trunk()

	set_physics_process(false)
	DayNight.hour_changed.connect(func(_h: int) -> void: _update_lights())
	_update_lights()


func _door_prompt() -> String:
	if fuel <= 2.0 and Game.count_item("fuel_can") > 0 and driver == null:
		return "Đổ can xăng (+%dL)" % int(CAN_LITERS)
	if owner_tag == "npc":
		return "Cướp xe ⚠"
	return "Lái xe"


func _build_trunk() -> void:
	_trunk = Node3D.new()
	_trunk.position = Vector3(0, 0.88, -1.16)
	var lid := MeshInstance3D.new()
	lid.mesh = Humanoid._box(Vector3(1.6, 0.07, 0.82))
	lid.material_override = Palette.mat(KINDS[kind].color.darkened(0.08))
	lid.position = Vector3(0, 0, -0.41)
	_trunk.add_child(lid)
	add_child(_trunk)
	var zone := InteractZone.make(Vector3(0, 0.8, -2.3), 1.35, "Mở cốp", _on_trunk_interact)
	zone.prompt_provider = _trunk_prompt
	add_child(zone)


func _trunk_prompt() -> String:
	if driver != null:
		return ""
	if not is_trunk_open:
		return "Mở cốp"
	if trunk_has_can:
		return "Lấy can xăng"
	return "Đóng cốp"


func _on_trunk_interact(_player: Node3D) -> void:
	if driver != null:
		return
	if not is_trunk_open:
		_set_trunk(true)
	elif trunk_has_can:
		trunk_has_can = false
		Game.add_item("fuel_can", 1)
		Audio.play_at("pickup", global_position, -2.0)
		Events.toast.emit("Lấy can xăng dự phòng từ cốp xe")
	else:
		_set_trunk(false)


func _set_trunk(open: bool) -> void:
	is_trunk_open = open
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_trunk, "rotation:x", deg_to_rad(-72.0) if open else 0.0, 0.4)
	Audio.play_at("trunk_open" if open else "trunk_close", to_global(Vector3(0, 0.9, -1.9)), -2.0)


# --- fuel -----------------------------------------------------------------------

func refuel(liters: float) -> void:
	fuel = minf(fuel + liters, fuel_capacity)
	_save_fuel()
	if fuel > 0.5:
		_fuel_warned = false
		if _engine_dead:
			_engine_dead = false
			if driver != null:
				Audio.play_at("car_start", global_position, 0.0)


func _save_fuel() -> void:
	Game.fuel_levels[vid] = fuel
	_fuel_saved_at = fuel


func _consume_fuel(delta: float, throttle: float, top: float) -> void:
	if fuel <= 0.0:
		return
	var burn := 0.012 + absf(throttle) * 0.05 + absf(speed) / top * 0.02
	fuel = maxf(fuel - burn * delta, 0.0)
	if absf(_fuel_saved_at - fuel) > 0.5:
		_save_fuel()
	if not _fuel_warned and fuel < fuel_capacity * 0.15:
		_fuel_warned = true
		Audio.play_ui("beep_low")
		Events.toast.emit("⛽ Sắp hết xăng! Ghé Trạm Xăng Hòn Gió.")
	if fuel <= 0.0 and not _engine_dead:
		_engine_dead = true
		_save_fuel()
		Audio.play_at("engine_die", global_position, 2.0)
		Events.toast.emit("Hết xăng! Dùng can xăng hoặc gọi trợ giúp ở trạm xăng.")


func _build_visual() -> void:
	var spec: Dictionary = KINDS[kind]
	var body_color: Color = spec.color
	var st := Props.begin()
	# Chassis + hood/trunk step.
	Props.add_box(st, Vector3(0, 0.62, 0), Vector3(1.8, 0.5, 3.9), body_color)
	Props.add_box(st, Vector3(0, 0.6, 0), Vector3(1.86, 0.18, 3.94), body_color.darkened(0.25))
	# Cabin.
	Props.add_box(st, Vector3(0, 1.12, -0.15), Vector3(1.6, 0.55, 2.0), body_color.darkened(0.06))
	# Windows (tinted, part of the merged mesh; cheap and readable).
	var glass := Color(0.2, 0.3, 0.38)
	Props.add_box(st, Vector3(0, 1.16, 0.88), Vector3(1.42, 0.4, 0.06), glass)
	Props.add_box(st, Vector3(0, 1.16, -1.18), Vector3(1.42, 0.4, 0.06), glass)
	Props.add_box(st, Vector3(0.78, 1.16, -0.15), Vector3(0.06, 0.38, 1.7), glass)
	Props.add_box(st, Vector3(-0.78, 1.16, -0.15), Vector3(0.06, 0.38, 1.7), glass)
	# Bumpers, lights.
	Props.add_box(st, Vector3(0, 0.45, 1.98), Vector3(1.7, 0.25, 0.12), Color(0.25, 0.26, 0.28))
	Props.add_box(st, Vector3(0, 0.45, -1.98), Vector3(1.7, 0.25, 0.12), Color(0.25, 0.26, 0.28))
	Props.add_box(st, Vector3(0.6, 0.68, 1.96), Vector3(0.3, 0.14, 0.08), Color(1.0, 0.95, 0.75))
	Props.add_box(st, Vector3(-0.6, 0.68, 1.96), Vector3(0.3, 0.14, 0.08), Color(1.0, 0.95, 0.75))
	Props.add_box(st, Vector3(0.6, 0.68, -1.96), Vector3(0.3, 0.14, 0.08), Color(0.8, 0.15, 0.1))
	Props.add_box(st, Vector3(-0.6, 0.68, -1.96), Vector3(0.3, 0.14, 0.08), Color(0.8, 0.15, 0.1))
	if kind == "taxi":
		Props.add_box(st, Vector3(0, 1.48, -0.15), Vector3(0.5, 0.18, 0.3), Color(1.0, 1.0, 1.0))
	if kind == "pickup":
		Props.add_box(st, Vector3(0, 0.95, -1.2), Vector3(1.7, 0.35, 1.4), body_color.darkened(0.2))
	var mesh_node := MeshInstance3D.new()
	mesh_node.mesh = Props.commit(st)
	add_child(mesh_node)

	# Driver door (visual, animates open). Facing +Z, the driver's
	# (left/VN) side is +X.
	_door_l = Node3D.new()
	_door_l.position = Vector3(0.92, 0.62, 0.75)
	var door_mesh := MeshInstance3D.new()
	door_mesh.mesh = Humanoid._box(Vector3(0.07, 0.5, 1.0))
	door_mesh.material_override = Palette.mat(KINDS[kind].color.darkened(0.12))
	door_mesh.position = Vector3(0, 0, -0.5)
	_door_l.add_child(door_mesh)
	add_child(_door_l)

	# Wheels.
	for offset in [Vector3(-0.82, 0.34, 1.3), Vector3(0.82, 0.34, 1.3), Vector3(-0.82, 0.34, -1.3), Vector3(0.82, 0.34, -1.3)]:
		var wheel_pivot := Node3D.new()
		wheel_pivot.position = offset
		var wheel_mesh := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.34
		cyl.bottom_radius = 0.34
		cyl.height = 0.24
		cyl.radial_segments = 10
		cyl.material = Palette.mat(Color(0.12, 0.12, 0.13), 0.9)
		wheel_mesh.mesh = cyl
		wheel_mesh.rotation_degrees = Vector3(0, 0, 90)
		wheel_pivot.add_child(wheel_mesh)
		add_child(wheel_pivot)
		_wheels.append(wheel_pivot)

	# Seats sit low so the driver's head stays under the cabin roof
	# (legs clip into the chassis — hidden by the body panels).
	_passenger_seat = Node3D.new()
	_passenger_seat.position = Vector3(-0.45, -0.05, 0.1)
	add_child(_passenger_seat)

	for x in [-0.55, 0.55]:
		var light := SpotLight3D.new()
		light.position = Vector3(x, 0.7, 1.95)
		light.rotation_degrees = Vector3(-8, 180, 0)
		light.spot_range = 22.0
		light.spot_angle = 32.0
		light.light_energy = 0.0
		light.light_color = Color(1.0, 0.93, 0.75)
		light.shadow_enabled = false
		add_child(light)
		_headlights.append(light)


func _update_lights() -> void:
	var driven := driver != null or not ai_route.is_empty()
	var on := DayNight.is_night() and driven and Game.quality >= 1
	for light in _headlights:
		light.light_energy = 2.4 if on else 0.0


# --- enter / exit -----------------------------------------------------------------

func get_prompt() -> String:
	return _door_prompt()


func can_interact(_player: Node3D) -> bool:
	return driver == null


func _on_enter_requested(player: Node3D) -> void:
	if driver != null or not player is PlayerCharacter:
		return
	# Empty tank + a jerry can in hand: pour instead of entering.
	if fuel <= 2.0 and Game.count_item("fuel_can") > 0:
		if Game.remove_item("fuel_can", 1):
			Audio.play_at("fuel_pour", global_position, 0.0)
			refuel(CAN_LITERS)
			Events.toast.emit("Đã đổ %dL xăng từ can" % int(CAN_LITERS))
		return
	# A patrolling AI car pulls over immediately — the seat must hold still
	# while the enter animation plays.
	if not ai_route.is_empty():
		ai_route = []
		speed = 0.0
		velocity = Vector3.ZERO
	if owner_tag == "npc" and not stolen_reported:
		stolen_reported = true
		Events.crime_committed.emit("car_theft", global_position)
		Events.toast.emit("Bạn đã cướp xe! Cảnh sát sẽ để ý đấy…")
	open_door()
	Audio.play_at("car_door_open", global_position, -2.0)
	(player as PlayerCharacter).enter_vehicle(self)


func open_door() -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_door_l, "rotation:y", deg_to_rad(-65.0), 0.35)


func close_door() -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(_door_l, "rotation:y", 0.0, 0.3)
	tween.tween_callback(func() -> void: Audio.play_at("car_door_close", global_position, -2.0))


func seat_global_position() -> Vector3:
	return to_global(Vector3(0.45, -0.05, 0.1))


func passenger_seat_global() -> Vector3:
	return _passenger_seat.global_position


## Puts this car on autopilot along a road polyline (ping-pong patrol).
func start_ai_route(points: Array) -> void:
	ai_route = points.duplicate()
	if ai_route.is_empty():
		return
	var best := 0
	var best_d := 1.0e12
	for i in ai_route.size():
		var d: float = global_position.distance_to(ai_route[i])
		if d < best_d:
			best_d = d
			best = i
	_ai_index = best
	_ai_step = 1
	set_physics_process(true)
	if not _engine.playing:
		_engine.play()
	_update_lights()


func _ai_drive(delta: float) -> void:
	var target: Vector3 = ai_route[_ai_index]
	var to_t := target - global_position
	to_t.y = 0.0
	if to_t.length() < 5.0:
		_ai_index += _ai_step
		if _ai_index >= ai_route.size() or _ai_index < 0:
			_ai_step = -_ai_step
			_ai_index += _ai_step * 2
		return
	var desired := atan2(to_t.x, to_t.z)
	var err := wrapf(desired - rotation.y, -PI, PI)
	rotation.y += clampf(err, -1.5 * delta, 1.5 * delta)
	# Brake for anything on the road ahead (player, NPCs, other cars).
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 0.7, 0) + global_transform.basis.z * 2.2
	var query := PhysicsRayQueryParameters3D.create(from, from + global_transform.basis.z * 7.5,
		Layers.PLAYER | Layers.NPCS | Layers.VEHICLE)
	query.exclude = [get_rid()]
	var blocked := not space.intersect_ray(query).is_empty()
	var target_speed := 0.0 if blocked else AI_SPEED * clampf(1.5 - absf(err), 0.25, 1.0)
	speed = move_toward(speed, target_speed, 7.0 * delta)
	if is_on_floor():
		_vy = -1.0
	else:
		_vy -= GRAVITY * delta
	velocity = global_transform.basis.z * speed + Vector3(0, _vy, 0)
	move_and_slide()
	_wheel_spin += speed * delta / 0.34
	for i in _wheels.size():
		_wheels[i].rotation.x = _wheel_spin
		if i < 2:
			_wheels[i].rotation.y = clampf(err, -0.4, 0.4)
	_engine.pitch_scale = 0.75 + clampf(absf(speed) / AI_SPEED, 0.0, 1.0) * 0.5
	_engine.volume_db = -12.0


func set_driver(p_driver: Node3D) -> void:
	driver = p_driver
	ai_route = []  # a stolen patrol car stays stolen
	close_door()
	if is_trunk_open:
		_set_trunk(false)
	set_physics_process(true)
	if fuel > 0.0:
		Audio.play_at("car_start", global_position, 0.0)
	else:
		Audio.play_at("engine_die", global_position, 0.0)
		Events.toast.emit("Xe này hết xăng — cần can xăng hoặc trạm xăng.")
	_engine.play()
	_update_lights()


func eject_driver() -> void:
	if driver == null:
		return
	var p := driver
	driver = null
	speed = 0.0
	velocity = Vector3.ZERO
	open_door()
	Audio.play_at("car_door_open", global_position, -2.0)
	var exit_spot := to_global(Vector3(1.7, 0.1, 0.4))
	if is_instance_valid(Game.world):
		var ground: float = Game.world.terrain.height_at(exit_spot.x, exit_spot.z)
		exit_spot.y = maxf(exit_spot.y, ground + 0.05)
	if p is PlayerCharacter:
		(p as PlayerCharacter).exit_vehicle_at(exit_spot)
	_engine.stop()
	set_physics_process(false)
	_update_lights()
	var timer := get_tree().create_timer(0.9)
	timer.timeout.connect(close_door)


# --- driving -----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if driver == null:
		if not ai_route.is_empty():
			_ai_drive(delta)
		return
	var spec: Dictionary = KINDS[kind]
	var top: float = spec.top_speed
	var accel: float = spec.accel

	var throttle := 0.0
	var steer := 0.0
	if not Game.ui_blocked:
		if Input.is_action_pressed("move_forward"):
			throttle += 1.0
		if Input.is_action_pressed("move_back"):
			throttle -= 1.0
		steer = Input.get_axis("move_right", "move_left")
		var hud := get_tree().get_first_node_in_group("hud")
		if hud != null and "joystick_vector" in hud:
			var jv: Vector2 = hud.joystick_vector
			if absf(jv.x) > absf(steer):
				steer = -jv.x
			if absf(jv.y) > 0.5 and absf(throttle) < 0.1:
				throttle = -signf(jv.y)

	# Fuel: burn while the engine runs; a dead engine gives no drive.
	_consume_fuel(delta, throttle, top)
	if fuel <= 0.0:
		throttle = 0.0

	# Speed integration.
	if throttle > 0.0:
		speed = move_toward(speed, top, accel * delta)
	elif throttle < 0.0:
		if speed > 0.5:
			speed = move_toward(speed, 0.0, BRAKE_DECEL * delta)
		else:
			speed = move_toward(speed, -top * 0.4, accel * 0.7 * delta)
	else:
		speed = move_toward(speed, 0.0, (DRAG + absf(speed) * 0.45) * delta)

	if Input.is_action_just_pressed("jump") and absf(speed) > 8.0:
		speed = move_toward(speed, 0.0, 26.0 * delta)
		if _skid_cooldown <= 0.0:
			_skid_cooldown = 0.7
			Audio.play_at("car_skid", global_position, -2.0)
	_skid_cooldown -= delta

	# Steering scales with speed so the car doesn't spin in place.
	var steer_amount := steer * STEER_SPEED * clampf(absf(speed) / 6.0, 0.0, 1.0)
	if speed < 0.0:
		steer_amount = -steer_amount
	rotation.y += steer_amount * delta
	_steer_visual = lerpf(_steer_visual, steer * 0.45, minf(delta * 8.0, 1.0))

	# Gravity + slope handling.
	if is_on_floor():
		_vy = -1.0
	else:
		_vy -= GRAVITY * delta
	# Car is modeled with its nose toward +Z.
	var forward := global_transform.basis.z
	velocity = forward * speed + Vector3(0, _vy, 0)
	var pre := velocity
	move_and_slide()
	# Hitting things scrubs speed.
	if get_slide_collision_count() > 0:
		var actual := velocity.slide(Vector3.UP).length()
		var expected := pre.slide(Vector3.UP).length()
		if expected > 4.0 and actual < expected * 0.4:
			if absf(speed) > 6.0:
				Audio.play_at("car_skid", global_position, 0.0)
			speed *= 0.25

	# Wheels: spin + front steer.
	_wheel_spin += speed * delta / 0.34
	for i in _wheels.size():
		var wheel := _wheels[i]
		wheel.rotation.x = _wheel_spin
		if i < 2:
			wheel.rotation.y = _steer_visual

	# Horn.
	if Input.is_action_just_pressed("horn"):
		Audio.play_at("car_horn", global_position, 2.0)

	# Engine sound follows speed; a dead engine is silent.
	if fuel <= 0.0:
		_engine.volume_db = lerpf(_engine.volume_db, -60.0, minf(delta * 4.0, 1.0))
	else:
		_engine.pitch_scale = 0.75 + clampf(absf(speed) / top, 0.0, 1.0) * 0.85
		_engine.volume_db = lerpf(-14.0, -4.0, clampf(absf(speed) / top, 0.0, 1.0) + absf(throttle) * 0.25)
