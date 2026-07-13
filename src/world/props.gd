class_name Props
## Factory for all generated low-poly prop meshes (vertex-colored).
## Normals are set explicitly (outward) and the shared material is
## double-sided, so generated geometry can never be culled away or lit
## from the wrong side regardless of triangle winding.

static var _mesh_cache: Dictionary = {}


static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func commit(st: SurfaceTool, foliage: bool = false) -> ArrayMesh:
	var mesh := st.commit()
	var material: Material = Palette.vertex_mat()
	if foliage:
		material = Palette.foliage_mat()
	mesh.surface_set_material(0, material)
	return mesh


## --- geometry helpers --------------------------------------------------------

static func add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color, n: Vector3 = Vector3.ZERO) -> void:
	if n == Vector3.ZERO:
		n = (b - a).cross(c - a)
		if n.length_squared() < 0.000001:
			n = Vector3.UP
		else:
			n = n.normalized()
			if n.y < 0.0:
				n = -n
	st.set_color(color)
	st.set_normal(n)
	st.add_vertex(a)
	st.set_color(color)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_color(color)
	st.set_normal(n)
	st.add_vertex(c)


static func add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, n: Vector3 = Vector3.ZERO) -> void:
	add_tri(st, a, b, c, color, n)
	add_tri(st, a, c, d, color, n)


static func add_box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color, yaw: float = 0.0) -> void:
	var h := size * 0.5
	var basis := Basis(Vector3.UP, yaw)
	var corners: Array[Vector3] = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				corners.append(center + basis * Vector3(h.x * sx, h.y * sy, h.z * sz))
	# corner index = (sx)(sy)(sz) bits with -1 => 0, +1 => 1
	var faces := [
		[[4, 6, 7, 5], Vector3.RIGHT],
		[[0, 1, 3, 2], Vector3.LEFT],
		[[2, 3, 7, 6], Vector3.UP],
		[[0, 4, 5, 1], Vector3.DOWN],
		[[1, 5, 7, 3], Vector3.BACK],
		[[0, 2, 6, 4], Vector3.FORWARD],
	]
	for f in faces:
		var idx: Array = f[0]
		var n: Vector3 = basis * f[1]
		add_quad(st, corners[idx[0]], corners[idx[1]], corners[idx[2]], corners[idx[3]], color, n)


static func add_cylinder(st: SurfaceTool, base: Vector3, r_bottom: float, r_top: float, height: float, segs: int, color: Color, cap_top: bool = true, top_color: Color = Color.BLACK) -> void:
	if top_color == Color.BLACK:
		top_color = color
	var top := base + Vector3(0, height, 0)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var am := (a0 + a1) * 0.5
		var radial := Vector3(cos(am), 0, sin(am))
		var n := (radial * height + Vector3.UP * (r_bottom - r_top)).normalized()
		var b0 := base + Vector3(cos(a0) * r_bottom, 0, sin(a0) * r_bottom)
		var b1 := base + Vector3(cos(a1) * r_bottom, 0, sin(a1) * r_bottom)
		var t0 := top + Vector3(cos(a0) * r_top, 0, sin(a0) * r_top)
		var t1 := top + Vector3(cos(a1) * r_top, 0, sin(a1) * r_top)
		if r_top > 0.001:
			add_quad(st, b0, t0, t1, b1, color, n)
			if cap_top:
				add_tri(st, t0, top, t1, top_color, Vector3.UP)
		else:
			add_tri(st, b0, top, b1, color, n)


static func add_blob(st: SurfaceTool, center: Vector3, radius: float, color: Color, rng: RandomNumberGenerator, deform: float = 0.25, rings: int = 4, segs: int = 7, squash: float = 1.0) -> void:
	# Low-poly deformed sphere; faceted normals point away from center.
	var pts: Array = []
	for ri in rings + 1:
		var row: Array[Vector3] = []
		var phi := PI * ri / rings
		for si in segs:
			var theta := TAU * si / segs
			var p := Vector3(sin(phi) * cos(theta), cos(phi) * squash, sin(phi) * sin(theta))
			var r := radius * (1.0 + rng.randf_range(-deform, deform))
			if ri == 0 or ri == rings:
				r = radius
			row.append(center + p * r)
		pts.append(row)
	for ri in rings:
		for si in segs:
			var sj := (si + 1) % segs
			var a: Vector3 = pts[ri][si]
			var b: Vector3 = pts[ri][sj]
			var c: Vector3 = pts[ri + 1][sj]
			var d: Vector3 = pts[ri + 1][si]
			var shade := color.darkened(rng.randf_range(0.0, 0.12))
			var n := ((a + b + c + d) * 0.25 - center).normalized()
			if ri == 0:
				add_tri(st, a, b, c, shade, n)
			elif ri == rings - 1:
				add_tri(st, a, c, d, shade, n)
			else:
				add_quad(st, a, b, c, d, shade, n)


## --- trees ------------------------------------------------------------------

static func pine_mesh(variant: int = 0) -> ArrayMesh:
	var key := "pine_%d" % variant
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + variant
	var st := begin()
	var trunk := Color(0.42, 0.3, 0.2)
	add_cylinder(st, Vector3.ZERO, 0.26, 0.2, 1.7, 6, trunk, false)
	var green := Color(0.2, 0.42, 0.24).lightened(rng.randf_range(0.0, 0.12))
	var y := 1.2
	var r := 1.75 + rng.randf_range(-0.2, 0.2)
	for i in 3:
		add_cylinder(st, Vector3(rng.randf_range(-0.1, 0.1), y, rng.randf_range(-0.1, 0.1)), r, 0.0, 1.9, 7, green.darkened(0.06 * i))
		y += 1.25
		r *= 0.68
	var mesh := commit(st, true)
	_mesh_cache[key] = mesh
	return mesh


static func broadleaf_mesh(variant: int = 0) -> ArrayMesh:
	var key := "leaf_%d" % variant
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 2000 + variant
	var st := begin()
	add_cylinder(st, Vector3.ZERO, 0.3, 0.22, 2.3, 6, Color(0.45, 0.33, 0.22), false)
	var green := Color(0.3, 0.5, 0.24).lightened(rng.randf_range(0.0, 0.1))
	add_blob(st, Vector3(0, 3.4, 0), 1.9, green, rng, 0.22, 4, 7, 0.85)
	var mesh := commit(st, true)
	_mesh_cache[key] = mesh
	return mesh


static func palm_mesh(variant: int = 0) -> ArrayMesh:
	var key := "palm_%d" % variant
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3000 + variant
	var st := begin()
	var trunk := Color(0.55, 0.44, 0.3)
	var lean := Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35))
	var base := Vector3.ZERO
	for i in 4:
		add_cylinder(st, base, 0.22 - i * 0.03, 0.19 - i * 0.03, 1.15, 5, trunk.darkened(i * 0.04), false)
		base += Vector3(lean.x, 1.1, lean.z)
	var top := base + Vector3(0, 0.2, 0)
	var green := Color(0.25, 0.52, 0.28)
	for i in 6:
		var ang := TAU * i / 6 + rng.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(ang), 0, sin(ang))
		var tip := top + dir * 2.4 + Vector3(0, -0.9, 0)
		var mid := top + dir * 1.2 + Vector3(0, 0.25, 0)
		var side := dir.cross(Vector3.UP) * 0.42
		var shade := green.darkened(0.05 * (i % 3))
		add_tri(st, top + side, mid - side, top - side, shade)
		add_tri(st, top + side, mid + side, mid - side, shade)
		add_tri(st, mid + side, tip, mid - side, green.darkened(0.08))
	var mesh := commit(st, true)
	_mesh_cache[key] = mesh
	return mesh


static func stump_mesh() -> ArrayMesh:
	if _mesh_cache.has("stump"):
		return _mesh_cache["stump"]
	var st := begin()
	add_cylinder(st, Vector3.ZERO, 0.34, 0.3, 0.45, 7, Color(0.42, 0.3, 0.2), true, Color(0.72, 0.58, 0.4))
	var mesh := commit(st)
	_mesh_cache["stump"] = mesh
	return mesh


## --- rocks / ore -------------------------------------------------------------

static func rock_mesh(variant: int = 0, radius: float = 0.9) -> ArrayMesh:
	var key := "rock_%d_%.1f" % [variant, radius]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4000 + variant
	var st := begin()
	add_blob(st, Vector3(0, radius * 0.5, 0), radius, Color(0.5, 0.48, 0.46), rng, 0.3, 3, 6, 0.7)
	var mesh := commit(st)
	_mesh_cache[key] = mesh
	return mesh


const ORE_COLORS := {
	"ore_copper": Color(0.78, 0.47, 0.26),
	"ore_iron": Color(0.62, 0.65, 0.7),
	"ore_gold": Color(0.93, 0.78, 0.25),
}


static func ore_mesh(ore_id: String) -> ArrayMesh:
	var key := "ore_" + ore_id
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(ore_id)
	var st := begin()
	add_blob(st, Vector3(0, 0.55, 0), 1.0, Color(0.45, 0.43, 0.42), rng, 0.28, 3, 6, 0.65)
	var crystal: Color = ORE_COLORS.get(ore_id, Color.GRAY)
	for i in 4:
		var ang := TAU * i / 4 + rng.randf_range(-0.4, 0.4)
		var pos := Vector3(cos(ang) * 0.55, 0.55 + rng.randf_range(-0.15, 0.3), sin(ang) * 0.55)
		add_box(st, pos, Vector3(0.28, 0.4, 0.28), crystal, rng.randf_range(0.0, TAU))
	var mesh := commit(st)
	_mesh_cache[key] = mesh
	return mesh


## --- street furniture ----------------------------------------------------------

static func lamp_pole_mesh() -> ArrayMesh:
	if _mesh_cache.has("lamp_pole"):
		return _mesh_cache["lamp_pole"]
	var st := begin()
	var dark := Color(0.2, 0.22, 0.25)
	add_cylinder(st, Vector3.ZERO, 0.09, 0.06, 4.1, 6, dark, false)
	add_box(st, Vector3(0.35, 4.15, 0), Vector3(0.85, 0.09, 0.09), dark)
	var mesh := commit(st)
	_mesh_cache["lamp_pole"] = mesh
	return mesh


static func lamp_head_mesh() -> BoxMesh:
	if _mesh_cache.has("lamp_head"):
		return _mesh_cache["lamp_head"]
	var box := BoxMesh.new()
	box.size = Vector3(0.42, 0.16, 0.24)
	box.material = Palette.lamp_mat()
	_mesh_cache["lamp_head"] = box
	return box


static func bench_mesh() -> ArrayMesh:
	if _mesh_cache.has("bench"):
		return _mesh_cache["bench"]
	var st := begin()
	var wood := Color(0.55, 0.4, 0.26)
	var iron := Color(0.25, 0.26, 0.28)
	add_box(st, Vector3(0, 0.42, 0), Vector3(1.7, 0.07, 0.45), wood)
	add_box(st, Vector3(0, 0.75, -0.24), Vector3(1.7, 0.4, 0.06), wood.darkened(0.05))
	add_box(st, Vector3(-0.7, 0.2, 0), Vector3(0.08, 0.42, 0.4), iron)
	add_box(st, Vector3(0.7, 0.2, 0), Vector3(0.08, 0.42, 0.4), iron)
	var mesh := commit(st)
	_mesh_cache["bench"] = mesh
	return mesh


static func log_pile_mesh() -> ArrayMesh:
	if _mesh_cache.has("log_pile"):
		return _mesh_cache["log_pile"]
	var st := begin()
	var wood := Color(0.5, 0.36, 0.24)
	for row in 3:
		var count := 4 - row
		for i in count:
			var pos := Vector3(0, 0.22 + row * 0.4, (i - count * 0.5 + 0.5) * 0.48)
			_add_hlog(st, pos, 2.8, 0.22, wood.darkened(0.04 * row))
	var mesh := commit(st)
	_mesh_cache["log_pile"] = mesh
	return mesh


static func _add_hlog(st: SurfaceTool, center: Vector3, length: float, radius: float, color: Color) -> void:
	# Horizontal hexagonal log along X.
	var segs := 6
	var cut := Color(0.74, 0.6, 0.42)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var am := (a0 + a1) * 0.5
		var n := Vector3(0, cos(am), sin(am))
		var p0 := center + Vector3(-length * 0.5, cos(a0) * radius, sin(a0) * radius)
		var p1 := center + Vector3(-length * 0.5, cos(a1) * radius, sin(a1) * radius)
		var q0 := center + Vector3(length * 0.5, cos(a0) * radius, sin(a0) * radius)
		var q1 := center + Vector3(length * 0.5, cos(a1) * radius, sin(a1) * radius)
		add_quad(st, p0, p1, q1, q0, color, n)
		add_tri(st, center + Vector3(length * 0.5, 0, 0), q0, q1, cut, Vector3.RIGHT)
		add_tri(st, center + Vector3(-length * 0.5, 0, 0), p1, p0, cut, Vector3.LEFT)


## --- hand tools -----------------------------------------------------------------

static func tool_mesh(tool_id: String) -> ArrayMesh:
	var key := "tool_" + tool_id
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var st := begin()
	var handle := Color(0.5, 0.38, 0.26)
	match tool_id:
		"axe":
			add_box(st, Vector3(0, 0.3, 0), Vector3(0.05, 0.7, 0.05), handle)
			add_box(st, Vector3(0.09, 0.6, 0), Vector3(0.22, 0.16, 0.05), Color(0.7, 0.72, 0.75))
		"pickaxe":
			add_box(st, Vector3(0, 0.3, 0), Vector3(0.05, 0.7, 0.05), handle)
			add_box(st, Vector3(0, 0.62, 0), Vector3(0.5, 0.07, 0.06), Color(0.6, 0.62, 0.66))
		"rod":
			add_cylinder(st, Vector3(0, 0.0, 0), 0.022, 0.008, 1.7, 4, Color(0.45, 0.35, 0.25), false)
			add_box(st, Vector3(0.03, 0.25, 0), Vector3(0.07, 0.1, 0.05), Color(0.3, 0.3, 0.32))
		_:
			add_box(st, Vector3(0, 0.2, 0), Vector3(0.08, 0.4, 0.08), handle)
	var mesh := commit(st)
	_mesh_cache[key] = mesh
	return mesh


## --- pickup item visual ---------------------------------------------------------

const ITEM_COLORS := {
	"fish_common": Color(0.6, 0.7, 0.75),
	"fish_fine": Color(0.45, 0.62, 0.8),
	"fish_rare": Color(0.85, 0.4, 0.35),
	"log": Color(0.5, 0.36, 0.24),
	"ore_copper": Color(0.78, 0.47, 0.26),
	"ore_iron": Color(0.62, 0.65, 0.7),
	"ore_gold": Color(0.93, 0.78, 0.25),
	"package": Color(0.75, 0.6, 0.4),
	"banh_mi": Color(0.85, 0.68, 0.4),
}


static func item_mesh(item_id: String) -> ArrayMesh:
	var key := "item_" + item_id
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var st := begin()
	var color: Color = ITEM_COLORS.get(item_id, Color(0.8, 0.8, 0.5))
	if item_id == "log":
		_add_hlog(st, Vector3(0, 0.2, 0), 1.0, 0.16, color)
	elif item_id == "package":
		add_box(st, Vector3(0, 0.25, 0), Vector3(0.5, 0.4, 0.42), color)
		add_box(st, Vector3(0, 0.26, 0), Vector3(0.52, 0.08, 0.44), Color(0.9, 0.85, 0.7))
	elif item_id.begins_with("fish"):
		add_box(st, Vector3(0, 0.16, 0), Vector3(0.55, 0.16, 0.1), color)
		add_tri(st, Vector3(0.28, 0.16, 0), Vector3(0.45, 0.28, 0), Vector3(0.45, 0.05, 0), color.darkened(0.15), Vector3.BACK)
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(item_id)
		add_blob(st, Vector3(0, 0.22, 0), 0.24, color, rng, 0.2, 3, 6)
	var mesh := commit(st)
	_mesh_cache[key] = mesh
	return mesh
