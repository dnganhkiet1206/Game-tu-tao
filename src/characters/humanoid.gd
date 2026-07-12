class_name Humanoid
extends Node3D
## Shared low-poly humanoid rig for the player and every NPC.
## No skeleton: box limbs hang off pivot nodes and a pose function drives
## them each frame, blended smoothly (procedural animation keeps APK small
## and runs the same everywhere).
##
## Box meshes are cached per size and materials come from the shared
## palette cache, so 25 humanoids cost almost nothing extra in state changes.

static var _box_cache: Dictionary = {}

var joints: Dictionary = {}         # name -> Node3D pivot
var _pose: Dictionary = {}          # name -> Vector3 current euler
var _pelvis: Node3D
var _pelvis_base := 0.94
var _pelvis_offset := 0.0
var _phase := 0.0
var _tool_holder: Node3D
var _tool_id := ""

const BLEND := 13.0


static func make(shirt: Color, pants: Color, skin: Color, hair: Color) -> Humanoid:
	var h := Humanoid.new()
	h._build(shirt, pants, skin, hair)
	return h


static func _box(size: Vector3) -> BoxMesh:
	var key := "%v" % size
	if _box_cache.has(key):
		return _box_cache[key]
	var mesh := BoxMesh.new()
	mesh.size = size
	_box_cache[key] = mesh
	return mesh


func _part(parent: Node3D, offset: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _box(size)
	mi.material_override = Palette.mat(color)
	mi.position = offset
	parent.add_child(mi)
	return mi


func _pivot(parent: Node3D, joint_name: String, pos: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = joint_name
	node.position = pos
	parent.add_child(node)
	joints[joint_name] = node
	_pose[joint_name] = Vector3.ZERO
	return node


func _build(shirt: Color, pants: Color, skin: Color, hair: Color) -> void:
	_pelvis = _pivot(self, "pelvis", Vector3(0, _pelvis_base, 0))
	_part(_pelvis, Vector3(0, 0.06, 0), Vector3(0.34, 0.18, 0.22), pants)
	var torso := _pivot(_pelvis, "torso", Vector3(0, 0.12, 0))
	_part(torso, Vector3(0, 0.22, 0), Vector3(0.36, 0.4, 0.22), shirt)
	var head := _pivot(torso, "head", Vector3(0, 0.46, 0))
	_part(head, Vector3(0, 0.13, 0), Vector3(0.23, 0.24, 0.23), skin)
	_part(head, Vector3(0, 0.245, -0.015), Vector3(0.25, 0.09, 0.26), hair)

	for side in [-1.0, 1.0]:
		var suffix := "l" if side < 0 else "r"
		var shoulder := _pivot(torso, "arm_" + suffix, Vector3(side * 0.235, 0.38, 0))
		_part(shoulder, Vector3(0, -0.14, 0), Vector3(0.1, 0.3, 0.11), shirt.darkened(0.06))
		var elbow := _pivot(shoulder, "elbow_" + suffix, Vector3(0, -0.29, 0))
		_part(elbow, Vector3(0, -0.12, 0), Vector3(0.09, 0.26, 0.1), skin)
		_part(elbow, Vector3(0, -0.28, 0), Vector3(0.09, 0.08, 0.1), skin.darkened(0.05))
		var hip := _pivot(_pelvis, "leg_" + suffix, Vector3(side * 0.1, -0.02, 0))
		_part(hip, Vector3(0, -0.2, 0), Vector3(0.13, 0.4, 0.14), pants.darkened(0.04))
		var knee := _pivot(hip, "knee_" + suffix, Vector3(0, -0.4, 0))
		_part(knee, Vector3(0, -0.19, 0), Vector3(0.115, 0.36, 0.125), pants.darkened(0.1))
		_part(knee, Vector3(0, -0.4, 0.05), Vector3(0.115, 0.08, 0.25), Color(0.2, 0.18, 0.16))

	_tool_holder = Node3D.new()
	_tool_holder.name = "ToolHolder"
	_tool_holder.position = Vector3(0, -0.26, 0.04)
	joints["elbow_r"].add_child(_tool_holder)


func set_tool(tool_id: String) -> void:
	if _tool_id == tool_id:
		return
	_tool_id = tool_id
	for child in _tool_holder.get_children():
		child.queue_free()
	if tool_id == "":
		return
	var mi := MeshInstance3D.new()
	mi.mesh = Props.tool_mesh(tool_id)
	mi.rotation_degrees = Vector3(-95, 0, 0)
	_tool_holder.add_child(mi)


## Advance the animation. params:
##   mode: idle|walk|air|swim|sit|work|punch|climb|fish|talk
##   speed: 0..1 (walk->run), work_phase / punch_t: 0..1, work_kind: chop|mine
func tick(delta: float, params: Dictionary) -> void:
	var mode: String = params.get("mode", "idle")
	var speed: float = params.get("speed", 0.0)
	var target := {}
	var bob := 0.0
	match mode:
		"walk":
			_phase += delta * lerpf(5.5, 11.5, speed)
			var swing := lerpf(0.45, 1.0, speed)
			var s := sin(_phase)
			target = {
				"arm_l": Vector3(s * swing, 0, 0.06),
				"arm_r": Vector3(-s * swing, 0, -0.06),
				"elbow_l": Vector3(lerpf(-0.15, -0.9, speed) * maxf(-s, 0.2), 0, 0),
				"elbow_r": Vector3(lerpf(-0.15, -0.9, speed) * maxf(s, 0.2), 0, 0),
				"leg_l": Vector3(-s * swing * 0.9, 0, 0),
				"leg_r": Vector3(s * swing * 0.9, 0, 0),
				"knee_l": Vector3(maxf(s, 0.0) * swing * 1.1, 0, 0),
				"knee_r": Vector3(maxf(-s, 0.0) * swing * 1.1, 0, 0),
				"torso": Vector3(lerpf(0.03, 0.22, speed), 0, 0),
				"head": Vector3(lerpf(-0.02, -0.14, speed), 0, 0),
				"pelvis": Vector3.ZERO,
			}
			bob = absf(cos(_phase)) * lerpf(0.02, 0.06, speed)
		"air":
			target = {
				"arm_l": Vector3(-0.5, 0, 0.5), "arm_r": Vector3(-0.5, 0, -0.5),
				"elbow_l": Vector3(-0.4, 0, 0), "elbow_r": Vector3(-0.4, 0, 0),
				"leg_l": Vector3(-0.35, 0, 0), "leg_r": Vector3(0.2, 0, 0),
				"knee_l": Vector3(0.7, 0, 0), "knee_r": Vector3(0.45, 0, 0),
				"torso": Vector3(0.1, 0, 0),
			}
		"swim":
			_phase += delta * 6.0
			var stroke := _phase
			target = {
				"pelvis": Vector3(1.25, 0, 0),
				"torso": Vector3(0.15, 0, 0),
				"head": Vector3(-1.05, 0, 0),
				"arm_l": Vector3(-1.6 - sin(stroke) * 1.3, 0, 0.25),
				"arm_r": Vector3(-1.6 - sin(stroke + PI) * 1.3, 0, -0.25),
				"elbow_l": Vector3(-0.3, 0, 0), "elbow_r": Vector3(-0.3, 0, 0),
				"leg_l": Vector3(sin(stroke * 2.0) * 0.3, 0, 0),
				"leg_r": Vector3(-sin(stroke * 2.0) * 0.3, 0, 0),
				"knee_l": Vector3(0.25, 0, 0), "knee_r": Vector3(0.25, 0, 0),
			}
			bob = sin(_phase * 0.7) * 0.05
		"sit":
			target = {
				"leg_l": Vector3(-1.45, 0, 0.06), "leg_r": Vector3(-1.45, 0, -0.06),
				"knee_l": Vector3(1.35, 0, 0), "knee_r": Vector3(1.35, 0, 0),
				"arm_l": Vector3(-0.75, 0, 0.12), "arm_r": Vector3(-0.75, 0, -0.12),
				"elbow_l": Vector3(-0.55, 0, 0), "elbow_r": Vector3(-0.55, 0, 0),
				"torso": Vector3(0.06, 0, 0),
			}
		"work":
			var wp: float = params.get("work_phase", 0.0)
			var kind: String = params.get("work_kind", "chop")
			var lift := sin(clampf(wp / 0.55, 0.0, 1.0) * PI * 0.5)   # raise 0..0.55
			var slam := clampf((wp - 0.55) / 0.2, 0.0, 1.0)           # strike 0.55..0.75
			var raise_angle := -2.4 if kind == "chop" else -2.1
			var arm_x := lerpf(0.0, raise_angle, lift) + slam * (2.6 if kind == "chop" else 2.3)
			target = {
				"arm_r": Vector3(arm_x, 0, -0.2),
				"arm_l": Vector3(arm_x * 0.9, 0, 0.3),
				"elbow_r": Vector3(-0.35 + slam * 0.2, 0, 0),
				"elbow_l": Vector3(-0.45, 0, 0),
				"torso": Vector3(0.12 + slam * 0.35, 0, 0),
				"leg_l": Vector3(-0.15, 0, 0.08), "leg_r": Vector3(0.1, 0, -0.08),
				"knee_l": Vector3(0.2, 0, 0), "knee_r": Vector3(0.15, 0, 0),
			}
		"punch":
			var t: float = params.get("punch_t", 0.0)
			var jab := sin(clampf(t, 0.0, 1.0) * PI)
			target = {
				"arm_r": Vector3(-1.5 * jab, -0.25 * jab, 0),
				"elbow_r": Vector3(-1.2 * (1.0 - jab), 0, 0),
				"arm_l": Vector3(-0.6, 0, 0.3),
				"elbow_l": Vector3(-1.5, 0, 0),
				"torso": Vector3(0.08, -0.35 * jab, 0),
			}
		"climb":
			target = {
				"arm_l": Vector3(-2.6, 0, 0.2), "arm_r": Vector3(-2.6, 0, -0.2),
				"elbow_l": Vector3(-0.4, 0, 0), "elbow_r": Vector3(-0.4, 0, 0),
				"leg_l": Vector3(-0.9, 0, 0), "knee_l": Vector3(1.2, 0, 0),
				"leg_r": Vector3(-0.3, 0, 0), "knee_r": Vector3(0.6, 0, 0),
				"torso": Vector3(0.25, 0, 0),
			}
		"fish":
			_phase += delta * 1.4
			target = {
				"arm_r": Vector3(-0.95 + sin(_phase) * 0.03, 0, -0.12),
				"arm_l": Vector3(-0.7, 0, 0.35),
				"elbow_r": Vector3(-0.5, 0, 0), "elbow_l": Vector3(-0.9, 0, 0),
				"torso": Vector3(0.05, 0, 0),
				"head": Vector3(0.1, 0, 0),
			}
		"talk":
			_phase += delta * 2.2
			target = {
				"arm_l": Vector3(-0.25 + sin(_phase) * 0.08, 0, 0.15),
				"arm_r": Vector3(-0.3 - sin(_phase * 1.3) * 0.1, 0, -0.15),
				"elbow_l": Vector3(-0.7, 0, 0), "elbow_r": Vector3(-0.8, 0, 0),
				"head": Vector3(sin(_phase * 0.7) * 0.05, 0, 0),
			}
		_:  # idle
			_phase += delta * 1.8
			var breathe := sin(_phase) * 0.03
			target = {
				"arm_l": Vector3(breathe * 0.5, 0, 0.07),
				"arm_r": Vector3(breathe * 0.5, 0, -0.07),
				"elbow_l": Vector3(-0.12, 0, 0), "elbow_r": Vector3(-0.12, 0, 0),
				"torso": Vector3(0.02 + breathe, 0, 0),
				"head": Vector3(-0.02, 0, 0),
				"leg_l": Vector3.ZERO, "leg_r": Vector3.ZERO,
				"knee_l": Vector3(0.03, 0, 0), "knee_r": Vector3(0.03, 0, 0),
			}
	var blend := minf(delta * BLEND, 1.0)
	for joint_name in joints:
		var goal: Vector3 = target.get(joint_name, Vector3.ZERO)
		var cur: Vector3 = _pose[joint_name]
		cur = cur.lerp(goal, blend)
		_pose[joint_name] = cur
		if joint_name == "pelvis":
			continue
		joints[joint_name].rotation = cur
	# Pelvis: pitch for swim + bob.
	_pelvis_offset = lerpf(_pelvis_offset, bob, blend)
	var pelvis_goal: Vector3 = target.get("pelvis", Vector3.ZERO)
	var pelvis_cur: Vector3 = _pose["pelvis"]
	_pelvis.rotation = pelvis_cur
	var base := _pelvis_base
	if mode == "sit":
		base = 0.62
	elif mode == "swim":
		base = 0.55
	_pelvis.position.y = lerpf(_pelvis.position.y, base + _pelvis_offset, blend)
	_pose["pelvis"] = pelvis_cur.lerp(pelvis_goal, blend)
