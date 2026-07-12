class_name CameraRig
extends Node3D
## Smooth chase camera with touch-drag orbit, spring-arm wall clipping,
## speed FOV and a tiny impact kick. Drag anywhere that isn't a control.

var yaw := 0.0
var pitch := -0.32
var target: Node3D = null
var follow_distance := 4.6
var _kick := 0.0
var _touch_id := -1
var _spring: SpringArm3D
var _camera: Camera3D


func _ready() -> void:
	top_level = true
	_spring = SpringArm3D.new()
	_spring.spring_length = follow_distance
	_spring.collision_mask = Layers.WORLD
	_spring.margin = 0.25
	add_child(_spring)
	_camera = Camera3D.new()
	_camera.fov = 66.0
	_camera.near = 0.1
	_camera.far = 480.0
	_camera.current = true
	_spring.add_child(_camera)


func kick(strength: float) -> void:
	_kick = maxf(_kick, strength)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			# Only orbit with touches on the right 55% of the screen.
			var size := get_viewport().get_visible_rect().size
			if _touch_id == -1 and touch.position.x > size.x * 0.45:
				_touch_id = touch.index
		elif touch.index == _touch_id:
			_touch_id = -1
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_id:
			yaw -= drag.relative.x * 0.0042
			pitch = clampf(pitch - drag.relative.y * 0.0038, -1.1, 0.35)


func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var focus: Vector3 = target.global_position + Vector3(0, 1.55, 0)
	var driving := false
	if target is PlayerCharacter:
		var p := target as PlayerCharacter
		driving = p.state == PlayerCharacter.State.DRIVING
		if driving and is_instance_valid(p.vehicle):
			focus = p.vehicle.global_position + Vector3(0, 1.8, 0)
	var wanted_dist := 7.2 if driving else 4.6
	follow_distance = lerpf(follow_distance, wanted_dist, minf(delta * 3.0, 1.0))
	_spring.spring_length = follow_distance

	global_position = global_position.lerp(focus, minf(delta * 10.0, 1.0))
	rotation = Vector3(pitch, yaw, 0)

	# Speed-based FOV + kick decay.
	var speed := 0.0
	if target is CharacterBody3D:
		speed = (target as CharacterBody3D).velocity.length()
	if driving and target is PlayerCharacter:
		var veh := (target as PlayerCharacter).vehicle
		if veh != null and "speed" in veh:
			speed = absf(veh.speed)
	var target_fov := 66.0 + clampf(speed / 22.0, 0.0, 1.0) * 12.0 + _kick * 30.0
	_camera.fov = lerpf(_camera.fov, target_fov, minf(delta * 5.0, 1.0))
	_kick = maxf(_kick - delta * 1.6, 0.0)
