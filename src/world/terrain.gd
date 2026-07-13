class_name Terrain
extends StaticBody3D
## Procedural island terrain: heightfield mesh (chunked for culling),
## exact-matching HeightMapShape3D collision, sea + lake water, and
## surface-type lookups used for footstep sounds and prop placement.

const CELL := 4.0
const N := 201  # samples per side -> 800 m

enum Surf { GRASS, SAND, ROAD, PAVEMENT, ROCK, DIRT, FOREST_FLOOR }

var heights := PackedFloat32Array()
var surf_ids := PackedByteArray()
var _colors := PackedColorArray()
var _normals := PackedVector3Array()

var _n_base := FastNoiseLite.new()
var _n_hills := FastNoiseLite.new()
var _n_detail := FastNoiseLite.new()

const SURF_COLORS := {
	Surf.GRASS: Color(0.45, 0.58, 0.32),
	Surf.SAND: Color(0.88, 0.8, 0.6),
	Surf.ROAD: Color(0.27, 0.28, 0.3),
	Surf.PAVEMENT: Color(0.56, 0.56, 0.57),
	Surf.ROCK: Color(0.52, 0.5, 0.47),
	Surf.DIRT: Color(0.55, 0.44, 0.3),
	Surf.FOREST_FLOOR: Color(0.36, 0.47, 0.27),
}

const SURF_STEP_SOUND := {
	Surf.GRASS: "step_grass",
	Surf.SAND: "step_sand",
	Surf.ROAD: "step_road",
	Surf.PAVEMENT: "step_road",
	Surf.ROCK: "step_road",
	Surf.DIRT: "step_grass",
	Surf.FOREST_FLOOR: "step_grass",
}


func _init() -> void:
	name = "Terrain"
	_n_base.seed = 71
	_n_base.frequency = 1.0 / 95.0
	_n_hills.seed = 72
	_n_hills.frequency = 1.0 / 240.0
	_n_detail.seed = 73
	_n_detail.frequency = 1.0 / 11.0
	set_meta("surface", "terrain")


func build() -> void:
	_fill_grids()
	_build_chunks()
	_build_water()


# --- height model -------------------------------------------------------------

## Terrain height before roads are ironed in.
func _height_raw(x: float, z: float) -> float:
	var h := 3.2 + _n_base.get_noise_2d(x, z) * 2.4
	h += maxf(_n_hills.get_noise_2d(x, z), 0.0) * 11.0
	# Northern ridge behind the forest.
	h += smoothstep(150.0, 40.0, z) * 7.0
	# Quarry: raised rocky rim with a flat working pit.
	var qd := Vector2(x, z).distance_to(MapLayout.QUARRY_CENTER)
	h += smoothstep(95.0, 58.0, qd) * 6.5
	h = lerpf(h, 5.6, smoothstep(46.0, 30.0, qd))
	# Lake bowl.
	var ld := Vector2(x, z).distance_to(MapLayout.LAKE_CENTER)
	h = lerpf(h, -4.0, smoothstep(MapLayout.LAKE_RADIUS + 16.0, MapLayout.LAKE_RADIUS - 12.0, ld))
	# West coast: flatten to beach, then drop into the sea.
	h = lerpf(h, 0.9, smoothstep(165.0, 122.0, x))
	h = lerpf(h, -7.5, smoothstep(118.0, 58.0, x))
	# South and east edges slope into water so the island feels finite.
	h = lerpf(h, -6.0, smoothstep(740.0, 795.0, maxf(x, z)))
	h = lerpf(h, -6.0, smoothstep(60.0, 8.0, z) * smoothstep(500.0, 700.0, x))
	# Flatten pads (town, residential, yards...).
	for pad in MapLayout.FLATTEN_PADS:
		var m: float = smoothstep(pad[1], pad[1] * 0.5, Vector2(x, z).distance_to(pad[0]))
		h = lerpf(h, pad[2], m)
	return h


## Distance to nearest road centerline; also returns interpolation point.
func _road_info(x: float, z: float) -> Array:
	var best_d := 99999.0
	var best_pt := Vector2.ZERO
	var best_w := 0.0
	var p := Vector2(x, z)
	for road in MapLayout.ROADS:
		var pts: Array = road.points
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var proj := Geometry2D.get_closest_point_to_segment(p, a, b)
			var d := p.distance_to(proj)
			if d < best_d:
				best_d = d
				best_pt = proj
				best_w = road.width
	return [best_d, best_pt, best_w]


func height_full(x: float, z: float) -> float:
	var h := _height_raw(x, z)
	var info := _road_info(x, z)
	var d: float = info[0]
	var w: float = info[2]
	if d < w * 0.5 + 7.0:
		var pt: Vector2 = info[1]
		var road_h := _height_raw(pt.x, pt.y)
		var m: float = smoothstep(w * 0.5 + 7.0, w * 0.5 + 1.0, d)
		h = lerpf(h, road_h, m)
	return h


func _classify(x: float, z: float, h: float, road_d: float, road_w: float) -> int:
	if road_d < road_w * 0.5:
		return Surf.ROAD
	if road_d < road_w * 0.5 + 2.2 and _in_paved_zone(x, z):
		return Surf.PAVEMENT
	# Town plaza around the crossing.
	if x > 404.0 and x < 444.0 and z > 376.0 and z < 397.0:
		return Surf.PAVEMENT
	# Gas-station forecourt (cars roll off the road onto the pumps).
	if x > 552.0 and x < 580.0 and z > 387.0 and z < 397.0:
		return Surf.PAVEMENT
	var qd := Vector2(x, z).distance_to(MapLayout.QUARRY_CENTER)
	if qd < 58.0:
		return Surf.ROCK
	if x < 158.0 and h < 2.4:
		return Surf.SAND
	var ld := Vector2(x, z).distance_to(MapLayout.LAKE_CENTER)
	if ld < MapLayout.LAKE_RADIUS + 14.0 and h < 1.6:
		return Surf.SAND
	if MapLayout.FOREST_RECT.has_point(Vector2(x, z)):
		if _n_detail.get_noise_2d(x * 0.4, z * 0.4) > 0.25:
			return Surf.DIRT
		return Surf.FOREST_FLOOR
	return Surf.GRASS


func _in_paved_zone(x: float, z: float) -> bool:
	# Sidewalks only inside town / residential areas.
	return Vector2(x, z).distance_to(MapLayout.TOWN_CENTER) < 140.0 \
		or (x > 470.0 and x < 670.0 and z > 270.0 and z < 330.0)


func _fill_grids() -> void:
	heights.resize(N * N)
	surf_ids.resize(N * N)
	for iz in N:
		for ix in N:
			var x := ix * CELL
			var z := iz * CELL
			var info := _road_info(x, z)
			var d: float = info[0]
			var w: float = info[2]
			var h := _height_raw(x, z)
			if d < w * 0.5 + 7.0:
				var pt: Vector2 = info[1]
				h = lerpf(h, _height_raw(pt.x, pt.y), smoothstep(w * 0.5 + 7.0, w * 0.5 + 1.0, d))
			heights[iz * N + ix] = h
			surf_ids[iz * N + ix] = _classify(x, z, h, d, w)
	# Second pass: bake per-vertex normals and colors once (needs neighbors).
	_normals.resize(N * N)
	_colors.resize(N * N)
	for iz in N:
		for ix in N:
			_normals[iz * N + ix] = _grid_normal(ix, iz)
			_colors[iz * N + ix] = _vertex_color(ix, iz)


# --- queries -------------------------------------------------------------------

## Bilinear height matching the collision shape exactly.
func height_at(x: float, z: float) -> float:
	var fx := clampf(x / CELL, 0.0, N - 1.001)
	var fz := clampf(z / CELL, 0.0, N - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var h00 := heights[iz * N + ix]
	var h10 := heights[iz * N + ix + 1]
	var h01 := heights[(iz + 1) * N + ix]
	var h11 := heights[(iz + 1) * N + ix + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func surface_at(x: float, z: float) -> int:
	var ix := clampi(roundi(x / CELL), 0, N - 1)
	var iz := clampi(roundi(z / CELL), 0, N - 1)
	return surf_ids[iz * N + ix]


func road_distance(x: float, z: float) -> float:
	var info := _road_info(x, z)
	return info[0]


func step_sound_at(x: float, z: float) -> String:
	return SURF_STEP_SOUND.get(surface_at(x, z), "step_grass")


## Water surface height at a position, or -1000 if there is no water there.
func water_level_at(x: float, z: float) -> float:
	if x < 128.0 or maxf(x, z) > 745.0 or (z < 55.0 and x > 500.0):
		return MapLayout.SEA_LEVEL
	if Vector2(x, z).distance_to(MapLayout.LAKE_CENTER) < MapLayout.LAKE_RADIUS + 6.0:
		return MapLayout.LAKE_LEVEL
	return -1000.0


## Top-down island image for the minimap (terrain colors + water tint).
func map_base_image() -> Image:
	var img := Image.create_empty(N, N, false, Image.FORMAT_RGB8)
	for iz in N:
		for ix in N:
			var idx := iz * N + ix
			var h := heights[idx]
			var c := _colors[idx]
			var wl := water_level_at(ix * CELL, iz * CELL)
			if wl > -100.0 and h < wl - 0.1:
				var depth := clampf((wl - h) / 7.0, 0.0, 1.0)
				c = Color(0.42, 0.63, 0.7).lerp(Color(0.1, 0.28, 0.46), depth)
			img.set_pixel(ix, iz, c)
	return img


func ambience_at(pos: Vector3) -> Dictionary:
	var waves := clampf(1.0 - (pos.x - 150.0) / 240.0, 0.0, 1.0)
	var forest_rect: Rect2 = MapLayout.FOREST_RECT.grow(40.0)
	var forest := 0.0
	if forest_rect.has_point(Vector2(pos.x, pos.z)):
		forest = 1.0
	else:
		var d := _rect_distance(Vector2(pos.x, pos.z), forest_rect)
		forest = clampf(1.0 - d / 80.0, 0.0, 1.0)
	return {"waves": waves, "forest": forest, "indoor": 0.0}


static func _rect_distance(p: Vector2, r: Rect2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dy := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return Vector2(dx, dy).length()


# --- mesh / collision ------------------------------------------------------------

func _grid_normal(ix: int, iz: int) -> Vector3:
	var xl := heights[iz * N + maxi(ix - 1, 0)]
	var xr := heights[iz * N + mini(ix + 1, N - 1)]
	var zu := heights[maxi(iz - 1, 0) * N + ix]
	var zd := heights[mini(iz + 1, N - 1) * N + ix]
	return Vector3(xl - xr, 2.0 * CELL, zu - zd).normalized()


func _vertex_color(ix: int, iz: int) -> Color:
	var s := surf_ids[iz * N + ix]
	var c: Color = SURF_COLORS[s]
	var x := ix * CELL
	var z := iz * CELL
	var vari := _n_detail.get_noise_2d(x, z) * 0.07
	c = Color(c.r + vari, c.g + vari, c.b + vari)
	var h := heights[iz * N + ix]
	# Tint underwater ground toward teal so shallows read well.
	if h < 0.4:
		c = c.lerp(Color(0.25, 0.42, 0.42), clampf((0.4 - h) / 4.0, 0.0, 0.75))
	# Rock out steep slopes.
	var n := _grid_normal(ix, iz)
	if n.y < 0.82 and (s == Surf.GRASS or s == Surf.FOREST_FLOOR):
		c = c.lerp(SURF_COLORS[Surf.ROCK], clampf((0.82 - n.y) * 5.0, 0.0, 0.85))
	return c


func _build_chunks() -> void:
	const CHUNKS := 5
	var cells_per := (N - 1) / CHUNKS  # 40 cells = 160 m per chunk
	var faces := PackedVector3Array()
	for cz in CHUNKS:
		for cx in CHUNKS:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var x0 := cx * cells_per
			var z0 := cz * cells_per
			for iz in range(z0, z0 + cells_per):
				for ix in range(x0, x0 + cells_per):
					_emit_cell(st, ix, iz, faces)
			st.index()
			var mesh := st.commit()
			mesh.surface_set_material(0, Palette.vertex_mat())
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.name = "Chunk_%d_%d" % [cx, cz]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
	# Collision uses the exact render triangles, so what you see is what
	# you stand on (no heightmap-scale corner cases).
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)


func _emit_cell(st: SurfaceTool, ix: int, iz: int, faces: PackedVector3Array) -> void:
	var corners := [
		Vector2i(ix, iz), Vector2i(ix + 1, iz),
		Vector2i(ix + 1, iz + 1), Vector2i(ix, iz + 1),
	]
	var verts: Array[Vector3] = []
	var cols: Array[Color] = []
	var norms: Array[Vector3] = []
	for c in corners:
		verts.append(Vector3(c.x * CELL, heights[c.y * N + c.x], c.y * CELL))
		cols.append(_colors[c.y * N + c.x])
		norms.append(_normals[c.y * N + c.x])
	for tri in [[0, 1, 2], [0, 2, 3]]:
		for vi in tri:
			st.set_color(cols[vi])
			st.set_normal(norms[vi])
			st.add_vertex(verts[vi])
			faces.append(verts[vi])


func _build_water() -> void:
	var sea := PlaneMesh.new()
	sea.size = Vector2(190, 820)
	sea.subdivide_width = 24
	sea.subdivide_depth = 90
	sea.material = Palette.water_mat()
	var sea_mi := MeshInstance3D.new()
	sea_mi.mesh = sea
	sea_mi.position = Vector3(70, MapLayout.SEA_LEVEL, 400)
	sea_mi.name = "Sea"
	add_child(sea_mi)
	# Thin strips wrap the south/east island edges so distant water exists there.
	var east := PlaneMesh.new()
	east.size = Vector2(120, 820)
	east.subdivide_width = 8
	east.subdivide_depth = 30
	east.material = Palette.water_mat()
	var east_mi := MeshInstance3D.new()
	east_mi.mesh = east
	east_mi.position = Vector3(810, MapLayout.SEA_LEVEL, 400)
	east_mi.name = "SeaEast"
	add_child(east_mi)
	var south := PlaneMesh.new()
	south.size = Vector2(700, 120)
	south.subdivide_width = 24
	south.subdivide_depth = 6
	south.material = Palette.water_mat()
	var south_mi := MeshInstance3D.new()
	south_mi.mesh = south
	south_mi.position = Vector3(450, MapLayout.SEA_LEVEL, 810)
	south_mi.name = "SeaSouth"
	add_child(south_mi)

	var lake := PlaneMesh.new()
	lake.size = Vector2(150, 150)
	lake.subdivide_width = 18
	lake.subdivide_depth = 18
	lake.material = Palette.water_mat()
	var lake_mi := MeshInstance3D.new()
	lake_mi.mesh = lake
	lake_mi.position = Vector3(MapLayout.LAKE_CENTER.x, MapLayout.LAKE_LEVEL, MapLayout.LAKE_CENTER.y)
	lake_mi.name = "Lake"
	add_child(lake_mi)
