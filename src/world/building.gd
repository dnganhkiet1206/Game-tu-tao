class_name GameBuilding
extends Node3D
## Enterable building generated from a MapLayout entry.
## All static geometry is merged into ONE vertex-colored mesh (1 draw call),
## windows into one emissive mesh, plus a working hinged door, interior
## furniture with collision, a name sign and marker points for gameplay.

const WALL_T := 0.24
const DOOR_W := 1.4
const DOOR_H := 2.35

var data: Dictionary = {}
var door: Door = null
var markers: Dictionary = {}  # name -> local Vector3
var interior_light: OmniLight3D = null

var _st: SurfaceTool
var _collisions: Array = []  # [center: Vector3, size: Vector3]


static func make(p_data: Dictionary) -> GameBuilding:
	var b := GameBuilding.new()
	b.data = p_data
	b.name = "Building_" + p_data.id
	b.rotation.y = deg_to_rad(p_data.rot)
	b._build()
	return b


func kind() -> String:
	return data.kind


func _build() -> void:
	var size: Vector3 = data.size
	var w: float = size.x
	var h: float = size.y
	var d: float = size.z
	var wall: Color = data.color
	_st = Props.begin()

	var open_w := DOOR_W
	var open_h := DOOR_H
	var kind_id: String = data.kind
	if kind_id == "garage":
		open_w = 5.4
		open_h = 3.2
	elif kind_id == "market" or kind_id == "sawmill":
		open_w = 5.0
		open_h = 2.9

	_floor(w, d, kind_id)
	_front_wall(w, h, d, wall, open_w, open_h)
	_solid_wall(w, h, -d * 0.5, wall)              # back
	_side_walls(w, h, d, wall)
	_roof(w, h, d, wall)
	_furnish(w, h, d)

	# Real door panel only for door-sized openings.
	if open_w <= DOOR_W + 0.01:
		door = Door.make(DOOR_W, DOOR_H, wall.darkened(0.45))
		door.position = Vector3(-DOOR_W * 0.5, 0.15, d * 0.5)
		add_child(door)

	var mesh_node := MeshInstance3D.new()
	mesh_node.mesh = Props.commit(_st)
	mesh_node.name = "BuildingMesh"
	add_child(mesh_node)

	_windows(w, h, d)
	_collision_body()
	_sign(d)
	_light(h)


# --- structure -----------------------------------------------------------------

func _floor(w: float, d: float, kind_id: String) -> void:
	var thick := 0.05 if kind_id == "garage" else 0.15
	var color := Color(0.42, 0.4, 0.38) if kind_id == "garage" else Color(0.68, 0.56, 0.42)
	Props.add_box(_st, Vector3(0, thick * 0.5, 0), Vector3(w, thick, d), color)
	_collisions.append([Vector3(0, thick * 0.5, 0), Vector3(w, thick, d), "wood"])


func _front_wall(w: float, h: float, d: float, color: Color, open_w: float, open_h: float) -> void:
	var z := d * 0.5
	var seg_w := (w - open_w) * 0.5
	# Left / right of the opening.
	Props.add_box(_st, Vector3(-(open_w * 0.5 + seg_w * 0.5), h * 0.5, z), Vector3(seg_w, h, WALL_T), color)
	Props.add_box(_st, Vector3(open_w * 0.5 + seg_w * 0.5, h * 0.5, z), Vector3(seg_w, h, WALL_T), color)
	_collisions.append([Vector3(-(open_w * 0.5 + seg_w * 0.5), h * 0.5, z), Vector3(seg_w, h, WALL_T), ""])
	_collisions.append([Vector3(open_w * 0.5 + seg_w * 0.5, h * 0.5, z), Vector3(seg_w, h, WALL_T), ""])
	# Lintel above the opening.
	var lintel_h := h - open_h - 0.15
	if lintel_h > 0.05:
		Props.add_box(_st, Vector3(0, open_h + 0.15 + lintel_h * 0.5, z), Vector3(open_w, lintel_h, WALL_T), color)
		_collisions.append([Vector3(0, open_h + 0.15 + lintel_h * 0.5, z), Vector3(open_w, lintel_h, WALL_T), ""])


func _solid_wall(w: float, h: float, z: float, color: Color) -> void:
	Props.add_box(_st, Vector3(0, h * 0.5, z), Vector3(w, h, WALL_T), color.darkened(0.06))
	_collisions.append([Vector3(0, h * 0.5, z), Vector3(w, h, WALL_T), ""])


func _side_walls(w: float, h: float, d: float, color: Color) -> void:
	for sx in [-1.0, 1.0]:
		Props.add_box(_st, Vector3(sx * w * 0.5, h * 0.5, 0), Vector3(WALL_T, h, d), color.darkened(0.03))
		_collisions.append([Vector3(sx * w * 0.5, h * 0.5, 0), Vector3(WALL_T, h, d), ""])


func _roof(w: float, h: float, d: float, _wall: Color) -> void:
	var kind_id: String = data.kind
	var flat := kind_id in ["garage", "police", "hospital", "market", "depot", "shop", "fuel"]
	if flat:
		var roof_c := Color(0.45, 0.44, 0.42)
		Props.add_box(_st, Vector3(0, h + 0.12, 0), Vector3(w + 0.5, 0.24, d + 0.5), roof_c)
		_collisions.append([Vector3(0, h + 0.12, 0), Vector3(w + 0.5, 0.24, d + 0.5), ""])
	else:
		var roof_c := Color(0.62, 0.3, 0.24) if (hash(data.id) % 2 == 0) else Color(0.35, 0.38, 0.45)
		var ridge_h: float = h + w * 0.24
		var ov := 0.45  # overhang
		var y0 := h - 0.02
		var a := Vector3(-w * 0.5 - ov, y0, d * 0.5 + ov)
		var b := Vector3(w * 0.5 + ov, y0, d * 0.5 + ov)
		var c := Vector3(w * 0.5 + ov, y0, -d * 0.5 - ov)
		var e := Vector3(-w * 0.5 - ov, y0, -d * 0.5 - ov)
		var r_front := Vector3(0, ridge_h, d * 0.5 + ov)
		var r_back := Vector3(0, ridge_h, -d * 0.5 - ov)
		# Slopes.
		var n_left := Vector3(-(ridge_h - y0), w * 0.5 + ov, 0).normalized()
		var n_right := Vector3(ridge_h - y0, w * 0.5 + ov, 0).normalized()
		Props.add_quad(_st, a, r_front, r_back, e, roof_c, n_left)
		Props.add_quad(_st, b, r_front, r_back, c, roof_c, n_right)
		# Gable ends.
		Props.add_tri(_st, a, b, r_front, data.color.darkened(0.12), Vector3.BACK)
		Props.add_tri(_st, e, c, r_back, data.color.darkened(0.12), Vector3.FORWARD)
		# Underside so looking up isn't hollow (double-sided mat handles it).


func _windows(w: float, _h: float, d: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var positions: Array = []
	var quarter := w * 0.27
	positions.append([Vector3(-quarter, 1.45, d * 0.5 + WALL_T * 0.5 + 0.02), 0.0])
	positions.append([Vector3(quarter, 1.45, d * 0.5 + WALL_T * 0.5 + 0.02), 0.0])
	positions.append([Vector3(-quarter, 1.45, -d * 0.5 - WALL_T * 0.5 - 0.02), PI])
	positions.append([Vector3(quarter, 1.45, -d * 0.5 - WALL_T * 0.5 - 0.02), PI])
	for entry in positions:
		var center: Vector3 = entry[0]
		var yaw: float = entry[1]
		var rot_basis := Basis(Vector3.UP, yaw)
		var right := rot_basis * Vector3(0.62, 0, 0)
		var up := Vector3(0, 0.55, 0)
		var n := rot_basis * Vector3.BACK
		for tri in [[center - right - up, center + right - up, center + right + up], [center - right - up, center + right + up, center - right + up]]:
			for v in tri:
				st.set_normal(n)
				st.add_vertex(v)
	var mesh := st.commit()
	mesh.surface_set_material(0, Palette.window_mat())
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "Windows"
	add_child(mi)


func _collision_body() -> void:
	var body := StaticBody3D.new()
	body.name = "Structure"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	for entry in _collisions:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = entry[1]
		col.shape = shape
		col.position = entry[0]
		body.add_child(col)
	body.set_meta("surface", "wood")
	add_child(body)


func _sign(d: float) -> void:
	var title: String = data.get("name", "")
	if title == "":
		return
	var label := Label3D.new()
	label.text = title
	label.font_size = 140
	label.outline_size = 20
	label.modulate = Color(0.98, 0.95, 0.85)
	label.outline_modulate = Color(0.12, 0.1, 0.08)
	label.position = Vector3(0, DOOR_H + 0.75, d * 0.5 + 0.16)
	label.pixel_size = 0.004
	add_child(label)


func _light(h: float) -> void:
	interior_light = OmniLight3D.new()
	interior_light.light_color = Color(1.0, 0.87, 0.65)
	interior_light.light_energy = 1.1
	interior_light.omni_range = maxf(data.size.x, data.size.z) * 0.75
	interior_light.position = Vector3(0, h - 0.4, 0)
	interior_light.shadow_enabled = false
	interior_light.distance_fade_enabled = true
	interior_light.distance_fade_begin = 30.0
	interior_light.distance_fade_length = 12.0
	interior_light.visible = false
	add_child(interior_light)


# --- furniture ------------------------------------------------------------------

func _furnish(w: float, h: float, d: float) -> void:
	match data.kind:
		"shop":
			_counter(Vector3(0, 0, -d * 0.5 + 1.4), w * 0.55)
			_shelf(Vector3(-w * 0.5 + 0.5, 0, 0.6), PI * 0.5)
			_shelf(Vector3(w * 0.5 - 0.5, 0, 0.6), -PI * 0.5)
			_shelf(Vector3(w * 0.5 - 0.5, 0, -1.6), -PI * 0.5)
			markers["vendor"] = Vector3(0, 0.15, -d * 0.5 + 0.7)
			markers["counter"] = Vector3(0, 0.15, -d * 0.5 + 2.4)
		"cafe":
			_counter(Vector3(-w * 0.5 + 1.5, 0, -d * 0.5 + 1.2), 2.4)
			for i in 2:
				_table(Vector3(-w * 0.25 + i * w * 0.5, 0, 0.8))
			markers["vendor"] = Vector3(-w * 0.5 + 1.5, 0.15, -d * 0.5 + 0.6)
			markers["counter"] = Vector3(-w * 0.5 + 1.5, 0.15, -d * 0.5 + 2.2)
			markers["eat_1"] = Vector3(-w * 0.25, 0.15, 1.7)
			markers["eat_2"] = Vector3(w * 0.25, 0.15, 1.7)
		"garage":
			_counter(Vector3(-w * 0.5 + 1.3, 0, -d * 0.5 + 1.1), 2.2)
			_shelf(Vector3(w * 0.5 - 0.5, 0, -d * 0.5 + 1.2), -PI * 0.5)
			markers["vendor"] = Vector3(-w * 0.5 + 1.3, 0.05, -d * 0.5 + 0.6)
			markers["counter"] = Vector3(-w * 0.5 + 1.3, 0.05, -d * 0.5 + 2.1)
			markers["car_slot_1"] = Vector3(1.6, 0.05, 0.8)
			markers["car_slot_2"] = Vector3(-2.4, 0.05, 0.8)
		"police":
			_desk(Vector3(0, 0, -d * 0.5 + 1.6))
			_cell(Vector3(w * 0.5 - 1.9, 0, -d * 0.5 + 1.9))
			markers["vendor"] = Vector3(0, 0.15, -d * 0.5 + 0.8)
			markers["counter"] = Vector3(0, 0.15, -d * 0.5 + 2.6)
		"hospital":
			for i in 3:
				_bed(Vector3(-w * 0.5 + 1.3 + i * 2.2, 0, -d * 0.5 + 1.5), Color(0.92, 0.95, 0.97))
			_counter(Vector3(w * 0.5 - 1.6, 0, d * 0.5 - 2.2), 2.2)
			markers["vendor"] = Vector3(w * 0.5 - 1.6, 0.15, d * 0.5 - 2.9)
			markers["counter"] = Vector3(w * 0.5 - 1.6, 0.15, d * 0.5 - 1.4)
		"market":
			for i in 3:
				_stall(Vector3(-w * 0.5 + 2.2 + i * 3.4, 0, -0.4))
			markers["vendor"] = Vector3(0, 0.15, -1.6)
			markers["counter"] = Vector3(0, 0.15, 0.9)
		"sawmill":
			_saw_table(Vector3(-w * 0.25, 0, -0.5))
			_counter(Vector3(w * 0.5 - 1.4, 0, -d * 0.5 + 1.2), 2.2)
			markers["vendor"] = Vector3(w * 0.5 - 1.4, 0.15, -d * 0.5 + 0.7)
			markers["counter"] = Vector3(w * 0.5 - 1.4, 0.15, -d * 0.5 + 2.2)
		"fuel":
			_counter(Vector3(0, 0, -d * 0.5 + 1.2), w * 0.5)
			_shelf(Vector3(-w * 0.5 + 0.5, 0, 0.6), PI * 0.5)
			_crate(Vector3(w * 0.5 - 0.9, 0, 0.9), Color(0.85, 0.28, 0.24))
			markers["vendor"] = Vector3(0, 0.15, -d * 0.5 + 0.6)
			markers["counter"] = Vector3(0, 0.15, -d * 0.5 + 2.2)
		"depot":
			_counter(Vector3(0, 0, -d * 0.5 + 1.2), w * 0.5)
			_crate(Vector3(-w * 0.5 + 0.8, 0, 1.2), Color(0.78, 0.47, 0.26))
			_crate(Vector3(-w * 0.5 + 1.9, 0, 1.4), Color(0.62, 0.65, 0.7))
			markers["vendor"] = Vector3(0, 0.15, -d * 0.5 + 0.6)
			markers["counter"] = Vector3(0, 0.15, -d * 0.5 + 2.2)
		"home", "player_home":
			_furnish_home(w, h, d)


func _furnish_home(w: float, _h: float, d: float) -> void:
	var tier: int = Game.house_tier if data.kind == "player_home" else 2
	_bed(Vector3(-w * 0.5 + 1.2, 0, -d * 0.5 + 1.3), Color(0.5, 0.6, 0.8))
	markers["bed"] = Vector3(-w * 0.5 + 1.2, 0.15, -d * 0.5 + 2.3)
	markers["sleep"] = Vector3(-w * 0.5 + 1.2, 0.15, -d * 0.5 + 1.3)
	if tier >= 1:
		_table(Vector3(w * 0.25, 0, 0))
		_counter(Vector3(w * 0.5 - 1.1, 0, -d * 0.5 + 1.0), 1.8)
	if tier >= 2:
		_shelf(Vector3(-w * 0.5 + 0.5, 0, 0.8), PI * 0.5)
		_rug(Vector3(0.3, 0, 0.4))
	if tier >= 3:
		_rug(Vector3(-w * 0.25, 0, -0.8))
		_plant(Vector3(w * 0.5 - 0.6, 0, d * 0.5 - 1.0))
		_plant(Vector3(-w * 0.5 + 0.6, 0, d * 0.5 - 1.0))
	markers["upgrade"] = Vector3(w * 0.25, 0.15, 0)


func _counter(pos: Vector3, width: float) -> void:
	Props.add_box(_st, pos + Vector3(0, 0.55, 0), Vector3(width, 0.8, 0.6), Color(0.55, 0.4, 0.28))
	Props.add_box(_st, pos + Vector3(0, 0.97, 0), Vector3(width + 0.12, 0.06, 0.72), Color(0.72, 0.58, 0.4))
	_collisions.append([pos + Vector3(0, 0.55, 0), Vector3(width, 1.0, 0.7), ""])


func _shelf(pos: Vector3, yaw: float) -> void:
	var rot_basis := Basis(Vector3.UP, yaw)
	Props.add_box(_st, pos + Vector3(0, 1.0, 0), Vector3(0.4, 2.0, 1.8), Color(0.5, 0.38, 0.26), yaw)
	for level in 3:
		var shelf_y := 0.5 + level * 0.55
		for i in 3:
			var offset := rot_basis * Vector3(0.0, 0, -0.6 + i * 0.6)
			var c := Color(0.8, 0.6, 0.3).lerp(Color(0.4, 0.6, 0.75), float((level * 3 + i) % 4) / 3.0)
			Props.add_box(_st, pos + offset + Vector3(0, shelf_y + 0.12, 0) + rot_basis * Vector3(0.05, 0, 0), Vector3(0.22, 0.24, 0.3), c, yaw)
	var col_size := Vector3(1.8, 2.0, 0.45) if absf(sin(yaw)) > 0.5 else Vector3(0.45, 2.0, 1.8)
	_collisions.append([pos + Vector3(0, 1.0, 0), col_size, ""])


func _table(pos: Vector3) -> void:
	Props.add_box(_st, pos + Vector3(0, 0.72, 0), Vector3(1.1, 0.06, 1.1), Color(0.62, 0.46, 0.3))
	Props.add_box(_st, pos + Vector3(0, 0.36, 0), Vector3(0.12, 0.72, 0.12), Color(0.45, 0.34, 0.24))
	for offset in [Vector3(0.85, 0, 0), Vector3(-0.85, 0, 0)]:
		Props.add_box(_st, pos + offset + Vector3(0, 0.24, 0), Vector3(0.42, 0.48, 0.42), Color(0.5, 0.38, 0.28))
	_collisions.append([pos + Vector3(0, 0.4, 0), Vector3(1.2, 0.8, 1.2), ""])


func _desk(pos: Vector3) -> void:
	Props.add_box(_st, pos + Vector3(0, 0.72, 0), Vector3(2.4, 0.08, 0.9), Color(0.4, 0.32, 0.26))
	Props.add_box(_st, pos + Vector3(-1.0, 0.36, 0), Vector3(0.3, 0.7, 0.8), Color(0.35, 0.29, 0.24))
	Props.add_box(_st, pos + Vector3(1.0, 0.36, 0), Vector3(0.3, 0.7, 0.8), Color(0.35, 0.29, 0.24))
	_collisions.append([pos + Vector3(0, 0.4, 0), Vector3(2.4, 0.8, 0.9), ""])


func _cell(pos: Vector3) -> void:
	# Small holding cell: three walls of bars.
	var bar := Color(0.3, 0.32, 0.36)
	for i in 6:
		Props.add_cylinder(_st, pos + Vector3(-1.2 + i * 0.5, 0.15, 1.2), 0.04, 0.04, 2.2, 4, bar)
	for i in 4:
		Props.add_cylinder(_st, pos + Vector3(1.4, 0.15, -0.4 + i * 0.5), 0.04, 0.04, 2.2, 4, bar)
	Props.add_box(_st, pos + Vector3(0, 2.4, 0.4), Vector3(2.9, 0.1, 1.9), bar)
	_bed(pos + Vector3(-0.5, 0, -0.4), Color(0.6, 0.62, 0.66))
	_collisions.append([pos + Vector3(-0.2, 1.1, 1.2), Vector3(2.6, 2.2, 0.12), ""])
	_collisions.append([pos + Vector3(1.4, 1.1, 0.35), Vector3(0.12, 2.2, 1.9), ""])


func _bed(pos: Vector3, blanket: Color) -> void:
	Props.add_box(_st, pos + Vector3(0, 0.25, 0), Vector3(1.0, 0.3, 2.0), Color(0.48, 0.36, 0.26))
	Props.add_box(_st, pos + Vector3(0, 0.44, -0.15), Vector3(0.94, 0.14, 1.6), blanket)
	Props.add_box(_st, pos + Vector3(0, 0.47, 0.75), Vector3(0.7, 0.14, 0.4), Color(0.95, 0.95, 0.9))
	_collisions.append([pos + Vector3(0, 0.3, 0), Vector3(1.0, 0.6, 2.0), ""])


func _stall(pos: Vector3) -> void:
	Props.add_box(_st, pos + Vector3(0, 0.5, 0), Vector3(2.6, 0.75, 1.2), Color(0.45, 0.5, 0.55))
	for i in 3:
		Props.add_box(_st, pos + Vector3(-0.8 + i * 0.8, 0.95, 0), Vector3(0.7, 0.18, 0.9), Color(0.75, 0.85, 0.9))
		Props.add_box(_st, pos + Vector3(-0.8 + i * 0.8, 1.05, 0), Vector3(0.5, 0.1, 0.25), Color(0.55, 0.65, 0.72))
	_collisions.append([pos + Vector3(0, 0.5, 0), Vector3(2.6, 1.0, 1.2), ""])


func _saw_table(pos: Vector3) -> void:
	Props.add_box(_st, pos + Vector3(0, 0.45, 0), Vector3(2.6, 0.7, 1.3), Color(0.45, 0.4, 0.36))
	# Circular saw blade.
	Props.add_cylinder(_st, pos + Vector3(0, 0.8, 0), 0.42, 0.42, 0.04, 10, Color(0.75, 0.78, 0.8))
	_collisions.append([pos + Vector3(0, 0.5, 0), Vector3(2.6, 1.0, 1.3), ""])


func _crate(pos: Vector3, color: Color) -> void:
	Props.add_box(_st, pos + Vector3(0, 0.35, 0), Vector3(0.9, 0.7, 0.9), Color(0.5, 0.4, 0.28))
	Props.add_box(_st, pos + Vector3(0, 0.75, 0), Vector3(0.7, 0.16, 0.7), color)
	_collisions.append([pos + Vector3(0, 0.4, 0), Vector3(0.9, 0.8, 0.9), ""])


func _rug(pos: Vector3) -> void:
	Props.add_box(_st, pos + Vector3(0, 0.17, 0), Vector3(1.8, 0.03, 1.2), Color(0.7, 0.35, 0.3))


func _plant(pos: Vector3) -> void:
	Props.add_cylinder(_st, pos + Vector3(0, 0.15, 0), 0.22, 0.28, 0.4, 6, Color(0.65, 0.4, 0.3))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pos)
	Props.add_blob(_st, pos + Vector3(0, 0.95, 0), 0.4, Color(0.3, 0.55, 0.3), rng, 0.25, 3, 6)
