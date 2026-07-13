class_name Door
extends StaticBody3D
## Hinged door. The body origin sits on the hinge; interacting swings it
## open/closed with a smooth tween. NPCs may call open_for() to pass through.

var is_open := false
var _panel_width := 1.3
var _closed_yaw := 0.0
var _tween: Tween = null


static func make(width: float, height: float, color: Color) -> Door:
	var door := Door.new()
	door._panel_width = width
	door.collision_layer = Layers.WORLD | Layers.INTERACT
	door.collision_mask = 0
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, height, 0.08)
	box.material = Palette.mat(color, 0.7)
	mesh.mesh = box
	mesh.position = Vector3(width * 0.5, height * 0.5, 0)
	door.add_child(mesh)
	var knob := MeshInstance3D.new()
	var knob_mesh := SphereMesh.new()
	knob_mesh.radius = 0.045
	knob_mesh.height = 0.09
	knob_mesh.material = Palette.mat(Color(0.85, 0.75, 0.4), 0.3, 0.8)
	knob.mesh = knob_mesh
	knob.position = Vector3(width - 0.12, height * 0.48, 0.06)
	door.add_child(knob)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height, 0.08)
	col.shape = shape
	col.position = Vector3(width * 0.5, height * 0.5, 0)
	door.add_child(col)
	return door


func _ready() -> void:
	_closed_yaw = rotation.y


func get_prompt() -> String:
	return "Đóng cửa" if is_open else "Mở cửa"


func can_interact(_player: Node3D) -> bool:
	return true


func interact(_player: Node3D) -> void:
	toggle()


func toggle() -> void:
	set_open(not is_open)


func set_open(value: bool) -> void:
	if is_open == value:
		return
	is_open = value
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.set_ease(Tween.EASE_OUT)
	var target := _closed_yaw + (deg_to_rad(-105.0) if is_open else 0.0)
	_tween.tween_property(self, "rotation:y", target, 0.45)
	Audio.play_at("door_open" if is_open else "door_close", global_position, -4.0)


## Opens, then closes again after a beat (used by NPCs walking through).
func open_for(seconds: float = 1.6) -> void:
	set_open(true)
	var timer := get_tree().create_timer(seconds, false)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(self):
			set_open(false)
	)
