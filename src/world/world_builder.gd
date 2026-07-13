class_name WorldRoot
extends Node3D
## Assembles the whole island: sky/sun, terrain, buildings, piers, props,
## harvestable resources, street furniture, interact zones and the road graph.

var terrain: Terrain
var road_graph: RoadGraph
var buildings: Dictionary = {}          # id -> GameBuilding
var fishing_spots: Array[Vector3] = []
var sun: DirectionalLight3D
var world_env: WorldEnvironment

var _indoor_rects: Array[Rect2] = []
var _rng := RandomNumberGenerator.new()


func build() -> void:
	name = "World"
	add_to_group("world")
	_rng.seed = 8686
	_build_sky()
	terrain = Terrain.new()
	add_child(terrain)
	terrain.build()
	_build_buildings()
	_build_piers()
	_build_forest_and_props()
	_build_quarry_resources()
	_build_street_furniture()
	_build_interact_zones()
	road_graph = RoadGraph.new()
	road_graph.build(terrain)
	add_child(Weather.new())
	Game.world = self
	Events.hour_changed.connect(_on_hour_changed)
	Events.weather_changed.connect(func(_w: String) -> void: _on_hour_changed(int(DayNight.time_hours)))
	_on_hour_changed(int(DayNight.time_hours))
	apply_quality()


# --- sky / lighting ---------------------------------------------------------------

func _build_sky() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_fade_start = 0.85
	add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 8.0     # tight, realistic sun disc + halo
	sky_mat.sun_curve = 0.12
	sky_mat.use_debanding = true
	sky_mat.sky_cover = _make_cloud_texture()
	sky_mat.sky_cover_modulate = Color(1, 1, 1, 0.5)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	# Day/night tints the sky every frame; incremental radiance updates keep
	# the ambient/reflection probe refresh affordable on mobile GPUs.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.85, 0.95)
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.fog_enabled = true
	env.fog_light_color = Color(0.65, 0.75, 0.85)
	env.fog_density = 0.004
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.2
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.glow_enabled = false  # apply_quality() enables it on medium/high
	env.glow_intensity = 0.55
	env.glow_hdr_threshold = 1.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.07
	env.adjustment_contrast = 1.03
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	DayNight.register_sky(sun, env)


## Seamless noise clouds for the procedural sky; the day/night cycle tints
## them (white noon, amber dusk, storm gray in rain) via sky_cover_modulate.
func _make_cloud_texture() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = 4
	noise.frequency = 0.008
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 1))
	ramp.set_offset(0, 0.45)
	ramp.set_offset(1, 0.85)
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp
	return tex


func apply_quality() -> void:
	var q: int = Game.quality
	sun.directional_shadow_max_distance = [40.0, 70.0, 110.0][q]
	sun.directional_shadow_blend_splits = q == 2
	RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096][q], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][q])
	var vp := get_viewport()
	vp.scaling_3d_scale = [0.8, 1.0, 1.0][q]
	# MSAA is close to free on mobile tiled GPUs and is the best AA fit here.
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][q]
	world_env.environment.glow_enabled = q >= 1
	var cam := vp.get_camera_3d()
	if cam != null:
		cam.far = [420.0, 600.0, 800.0][q]
	# Re-evaluate everything that gates on quality (interior lights, headlights).
	_on_hour_changed(int(DayNight.time_hours))
	get_tree().call_group("vehicle", "_update_lights")


# --- buildings -----------------------------------------------------------------------

func _build_buildings() -> void:
	for entry in MapLayout.BUILDINGS:
		var b := GameBuilding.make(entry)
		var pos: Vector2 = entry.pos
		var h := terrain.height_at(pos.x, pos.y)
		b.position = Vector3(pos.x, h - 0.04, pos.y)
		add_child(b)
		buildings[entry.id] = b
		# Footprint (rot is always a multiple of 90 in the layout).
		var size: Vector3 = entry.size
		var half := Vector2(size.x, size.z) * 0.5
		if int(roundf(entry.rot)) % 180 != 0:
			half = Vector2(half.y, half.x)
		_indoor_rects.append(Rect2(pos - half, half * 2.0))


func get_building(id: String) -> GameBuilding:
	return buildings.get(id)


## Global position of a named marker inside a building.
func marker_global(building_id: String, marker: String) -> Vector3:
	var b: GameBuilding = buildings.get(building_id)
	if b == null or not b.markers.has(marker):
		return Vector3.ZERO
	return b.to_global(b.markers[marker])


func door_global(building_id: String) -> Vector3:
	var b: GameBuilding = buildings.get(building_id)
	if b == null:
		return Vector3.ZERO
	var p := MapLayout.door_pos(b.data)
	return Vector3(p.x, terrain.height_at(p.x, p.y), p.y)


# --- piers ---------------------------------------------------------------------------

func _build_piers() -> void:
	_build_pier(MapLayout.SEA_PIER, 1.25)
	_build_pier(MapLayout.LAKE_PIER, 1.55)


func _build_pier(spec: Dictionary, deck_y: float) -> void:
	var start: Vector2 = spec.start
	var dir: Vector2 = spec.dir
	var length: float = spec.length
	var width: float = spec.width
	var st := Props.begin()
	var wood := Color(0.55, 0.42, 0.28)
	var dir3 := Vector3(dir.x, 0, dir.y)
	var side3 := Vector3(-dir.y, 0, dir.x)
	var plank_step := 0.55
	var count := int(length / plank_step)
	for i in count:
		var center := Vector3(start.x, deck_y, start.y) + dir3 * (i + 0.5) * plank_step
		var shade := wood.darkened(fmod(i * 0.618, 1.0) * 0.1)
		Props.add_box(st, center, side3.abs() * width + dir3.abs() * (plank_step - 0.06) + Vector3(0, 0.09, 0), shade)
	# Posts every 4 m, both sides, down into the ground/water.
	var post_count := int(length / 4.0)
	for i in post_count + 1:
		for s in [-1.0, 1.0]:
			var base: Vector3 = Vector3(start.x, deck_y - 3.4, start.y) + dir3 * i * 4.0 + side3 * s * (width * 0.5 - 0.12)
			Props.add_cylinder(st, base, 0.11, 0.1, 3.5, 5, wood.darkened(0.25), false)
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.set_meta("surface", "wood")
	var mesh_node := MeshInstance3D.new()
	mesh_node.mesh = Props.commit(st)
	body.add_child(mesh_node)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var horiz := dir3.abs() * length + side3.abs() * width
	shape.size = Vector3(horiz.x, 0.22, horiz.z)
	col.shape = shape
	col.position = Vector3(start.x, deck_y, start.y) + dir3 * length * 0.5
	body.add_child(col)
	add_child(body)
	# Fishing spot at the far end.
	var end := Vector3(start.x, deck_y + 0.05, start.y) + dir3 * (length - 1.2)
	fishing_spots.append(end)


# --- vegetation / rocks ------------------------------------------------------------

func _build_forest_and_props() -> void:
	var choppable_parent := Node3D.new()
	choppable_parent.name = "Trees"
	add_child(choppable_parent)
	var rect: Rect2 = MapLayout.FOREST_RECT
	var variant := 0
	var step := 15.0
	var x := rect.position.x
	while x < rect.end.x:
		var z := rect.position.y
		while z < rect.end.y:
			var px := x + _rng.randf_range(-5.0, 5.0)
			var pz := z + _rng.randf_range(-5.0, 5.0)
			z += step
			if not _spot_ok_for_tree(px, pz):
				continue
			var tree := ResourceNode.make_tree(variant % 5)
			variant += 1
			tree.position = Vector3(px, terrain.height_at(px, pz) - 0.05, pz)
			tree.rotation.y = _rng.randf_range(0.0, TAU)
			choppable_parent.add_child(tree)
		x += step

	# Decorative pines on the northern hills (outside the choppable rect).
	var deco: Array[Transform3D] = []
	for i in 500:
		var px := _rng.randf_range(140.0, 700.0)
		var pz := _rng.randf_range(20.0, 120.0)
		if deco.size() >= 130:
			break
		if rect.has_point(Vector2(px, pz)):
			continue
		if not _spot_ok_for_tree(px, pz):
			continue
		var h := terrain.height_at(px, pz)
		var t := Transform3D(Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * _rng.randf_range(0.85, 1.3)), Vector3(px, h - 0.05, pz))
		deco.append(t)
	_add_multimesh(Props.pine_mesh(7), deco, "DecoPines")

	# Palms along the beach.
	var palms: Array[Transform3D] = []
	var z_palm := 255.0
	while z_palm < 565.0:
		var px := _rng.randf_range(120.0, 148.0)
		var h := terrain.height_at(px, z_palm)
		if h > 0.5 and terrain.surface_at(px, z_palm) == Terrain.Surf.SAND:
			palms.append(Transform3D(Basis(Vector3.UP, _rng.randf_range(0.0, TAU)), Vector3(px, h - 0.05, z_palm)))
		z_palm += _rng.randf_range(14.0, 24.0)
	_add_multimesh(Props.palm_mesh(2), palms, "Palms")

	# Broadleaf trees around the lake and residential edges.
	var leafs: Array[Transform3D] = []
	for i in 40:
		var ang := _rng.randf_range(0.0, TAU)
		var r: float = MapLayout.LAKE_RADIUS + _rng.randf_range(10.0, 30.0)
		var p: Vector2 = MapLayout.LAKE_CENTER + Vector2(cos(ang), sin(ang)) * r
		if not _spot_ok_for_tree(p.x, p.y):
			continue
		var h := terrain.height_at(p.x, p.y)
		if h < 1.0:
			continue
		leafs.append(Transform3D(Basis(Vector3.UP, _rng.randf_range(0.0, TAU)), Vector3(p.x, h - 0.05, p.y)))
	_add_multimesh(Props.broadleaf_mesh(1), leafs, "LakeTrees")

	# Scattered rocks: shoreline + quarry rim.
	var rocks: Array[Transform3D] = []
	for i in 60:
		var ang := _rng.randf_range(0.0, TAU)
		var r: float = MapLayout.QUARRY_RADIUS + _rng.randf_range(4.0, 26.0)
		var p: Vector2 = MapLayout.QUARRY_CENTER + Vector2(cos(ang), sin(ang)) * r
		if p.x > 795.0 or p.y > 795.0:
			continue
		if terrain.road_distance(p.x, p.y) < 6.0:
			continue
		var h := terrain.height_at(p.x, p.y)
		if h < 0.5:
			continue
		var s := _rng.randf_range(0.6, 1.6)
		rocks.append(Transform3D(Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * s), Vector3(p.x, h - 0.1, p.y)))
	_add_multimesh(Props.rock_mesh(3), rocks, "Rocks")


func _spot_ok_for_tree(px: float, pz: float) -> bool:
	if px < 8.0 or pz < 8.0 or px > 792.0 or pz > 792.0:
		return false
	var surf := terrain.surface_at(px, pz)
	if surf != Terrain.Surf.GRASS and surf != Terrain.Surf.FOREST_FLOOR and surf != Terrain.Surf.DIRT:
		return false
	if terrain.height_at(px, pz) < 1.2:
		return false
	if terrain.road_distance(px, pz) < 7.0:
		return false
	# Keep clear of building yards.
	for rect in _indoor_rects:
		if rect.grow(4.0).has_point(Vector2(px, pz)):
			return false
	return true


func _add_multimesh(mesh: Mesh, transforms: Array[Transform3D], node_name: String) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.name = node_name
	# Foliage sway displaces vertices beyond the static AABB.
	mmi.extra_cull_margin = 1.0
	add_child(mmi)


# --- quarry --------------------------------------------------------------------------

func _build_quarry_resources() -> void:
	var parent := Node3D.new()
	parent.name = "OreNodes"
	add_child(parent)
	var kinds := ["ore_copper", "ore_copper", "ore_copper", "ore_copper",
		"ore_iron", "ore_iron", "ore_iron", "ore_iron", "ore_gold"]
	for i in kinds.size():
		var ang := TAU * i / kinds.size() + _rng.randf_range(-0.2, 0.2)
		var r := _rng.randf_range(10.0, 26.0)
		var p: Vector2 = MapLayout.QUARRY_CENTER + Vector2(cos(ang), sin(ang)) * r
		var ore := ResourceNode.make_ore(kinds[i])
		ore.position = Vector3(p.x, terrain.height_at(p.x, p.y) - 0.05, p.y)
		ore.rotation.y = _rng.randf_range(0.0, TAU)
		parent.add_child(ore)


# --- street furniture ------------------------------------------------------------------

func _build_street_furniture() -> void:
	var poles: Array[Transform3D] = []
	var lamp_specs := [
		{"a": Vector2(160, 400), "b": Vector2(690, 400), "offset": 6.2, "step": 42.0},
		{"a": Vector2(400, 180), "b": Vector2(400, 630), "offset": 5.6, "step": 46.0},
		{"a": Vector2(410, 300), "b": Vector2(655, 300), "offset": 5.0, "step": 44.0},
	]
	for spec in lamp_specs:
		var a: Vector2 = spec.a
		var b: Vector2 = spec.b
		var dir := (b - a).normalized()
		var perp := Vector2(-dir.y, dir.x)
		var length := a.distance_to(b)
		var t := 0.0
		var side := 1.0
		while t < length:
			var p: Vector2 = a + dir * t + perp * spec.offset * side
			var h := terrain.height_at(p.x, p.y)
			var face := atan2(dir.x, dir.y)
			poles.append(Transform3D(Basis(Vector3.UP, face), Vector3(p.x, h, p.y)))
			t += spec.step
			side = -side
	var heads: Array[Transform3D] = []
	for t in poles:
		heads.append(Transform3D(t.basis, t.origin + t.basis * Vector3(0.6, 4.12, 0)))
	_add_multimesh(Props.lamp_pole_mesh(), poles, "LampPoles")
	_add_multimesh(Props.lamp_head_mesh(), heads, "LampHeads")

	var bench_spots := [
		[Vector2(412, 380), PI], [Vector2(430, 380), PI],
		[Vector2(630, 242), 0.4], [Vector2(652, 250), 1.2],
		[Vector2(130, 430), PI * 0.5], [Vector2(132, 500), PI * 0.5],
	]
	for spot in bench_spots:
		var p: Vector2 = spot[0]
		var bench := StaticBody3D.new()
		bench.collision_layer = Layers.WORLD
		bench.collision_mask = 0
		var mi := MeshInstance3D.new()
		mi.mesh = Props.bench_mesh()
		bench.add_child(mi)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.8, 1.0, 0.6)
		col.shape = shape
		col.position = Vector3(0, 0.5, 0)
		bench.add_child(col)
		bench.position = Vector3(p.x, terrain.height_at(p.x, p.y), p.y)
		bench.rotation.y = spot[1]
		add_child(bench)

	_build_fuel_forecourt()

	# Log pile beside the sawmill.
	var pile := StaticBody3D.new()
	pile.collision_layer = Layers.WORLD
	pile.collision_mask = 0
	var pile_mesh := MeshInstance3D.new()
	pile_mesh.mesh = Props.log_pile_mesh()
	pile.add_child(pile_mesh)
	var pile_col := CollisionShape3D.new()
	var pile_shape := BoxShape3D.new()
	pile_shape.size = Vector3(3.0, 1.4, 2.2)
	pile_col.shape = pile_shape
	pile_col.position = Vector3(0, 0.7, 0)
	pile.add_child(pile_col)
	pile.position = Vector3(290, terrain.height_at(290, 214), 214)
	add_child(pile)


## Gas-station forecourt: canopy on four posts + two pumps facing the road.
func _build_fuel_forecourt() -> void:
	var center := Vector2(566.0, 392.0)
	var ground := terrain.height_at(center.x, center.y)
	var st := Props.begin()
	var post := Color(0.75, 0.76, 0.78)
	for sx in [-4.6, 4.6]:
		for sz in [-2.2, 2.2]:
			Props.add_cylinder(st, Vector3(sx, 0, sz), 0.14, 0.12, 3.4, 6, post, false)
	Props.add_box(st, Vector3(0, 3.55, 0), Vector3(11.5, 0.3, 6.0), Color(0.92, 0.4, 0.32))
	Props.add_box(st, Vector3(0, 3.42, 0), Vector3(11.7, 0.06, 6.2), Color(0.95, 0.95, 0.9))
	var canopy := StaticBody3D.new()
	canopy.collision_layer = Layers.WORLD
	canopy.collision_mask = 0
	var mesh := MeshInstance3D.new()
	mesh.mesh = Props.commit(st)
	canopy.add_child(mesh)
	var roof_col := CollisionShape3D.new()
	var roof_shape := BoxShape3D.new()
	roof_shape.size = Vector3(11.5, 0.4, 6.0)
	roof_col.shape = roof_shape
	roof_col.position = Vector3(0, 3.55, 0)
	canopy.add_child(roof_col)
	for sx in [-4.6, 4.6]:
		for sz in [-2.2, 2.2]:
			var post_col := CollisionShape3D.new()
			var post_shape := CylinderShape3D.new()
			post_shape.radius = 0.15
			post_shape.height = 3.4
			post_col.shape = post_shape
			post_col.position = Vector3(sx, 1.7, sz)
			canopy.add_child(post_col)
	canopy.position = Vector3(center.x, ground, center.y)
	add_child(canopy)

	for sx in [-2.6, 2.6]:
		var pump := FuelPump.new()
		pump.position = Vector3(center.x + sx, ground, center.y)
		pump.rotation.y = PI * 0.5
		add_child(pump)


# --- interact zones ---------------------------------------------------------------------

func _build_interact_zones() -> void:
	_counter_zone("shop", "Mua sắm", func(_p: Node3D) -> void: Events.shop_requested.emit("shop"))
	_counter_zone("cafe", "Gọi món", func(_p: Node3D) -> void: Events.shop_requested.emit("cafe"))
	_counter_zone("garage", "Mua xe", func(_p: Node3D) -> void: Events.shop_requested.emit("garage"))
	_counter_zone("market", "Bán cá", func(_p: Node3D) -> void: Events.shop_requested.emit("sell_fish"))
	_counter_zone("sawmill", "Bán gỗ", func(_p: Node3D) -> void: Events.shop_requested.emit("sell_wood"))
	_counter_zone("depot", "Bán quặng", func(_p: Node3D) -> void: Events.shop_requested.emit("sell_ore"))
	_counter_zone("police", "Nộp phạt", func(_p: Node3D) -> void: Events.shop_requested.emit("police"))
	_counter_zone("fuel", "Mua đồ", func(_p: Node3D) -> void: Events.shop_requested.emit("fuel_shop"))
	_counter_zone("hospital", "Khám bệnh", func(_p: Node3D) -> void: Events.shop_requested.emit("hospital"))

	_add_home_zones()

	# Fishing spots: pier ends plus two shorelines.
	fishing_spots.append(Vector3(112, 1.0, 520))
	fishing_spots.append(Vector3(608, 1.4, 214))
	for spot in fishing_spots:
		var zone := InteractZone.make(Vector3.ZERO, 2.4, "Câu cá", func(p: Node3D) -> void:
			if p.has_method("start_fishing"):
				p.start_fishing()
		)
		add_child(zone)
		zone.global_position = spot

	# Delivery job pickup outside the shop.
	var shop: GameBuilding = buildings.get("shop")
	if shop != null:
		var pickup_pos := door_global("shop") + Vector3(2.0, 0.3, 1.0)
		var zone := InteractZone.make(Vector3.ZERO, 2.0, "Nhận giao hàng", func(_p: Node3D) -> void: Events.shop_requested.emit("delivery"))
		add_child(zone)
		zone.global_position = pickup_pos


func _add_home_zones() -> void:
	var home: GameBuilding = buildings.get("player_home")
	if home == null:
		return
	var sleep_zone := InteractZone.make(home.markers["bed"], 1.6, "Ngủ (lưu game)", func(_p: Node3D) -> void: Events.sleep_requested.emit())
	home.add_child(sleep_zone)
	var upgrade_zone := InteractZone.make(home.markers["upgrade"], 1.7, "Nâng cấp nhà", func(_p: Node3D) -> void: Events.upgrade_requested.emit())
	home.add_child(upgrade_zone)


## Rebuilds the player's house after an upgrade (new furniture tier).
func rebuild_player_home() -> void:
	var old: GameBuilding = buildings.get("player_home")
	var entry := MapLayout.building_by_id("player_home")
	if old != null:
		old.queue_free()
	var b := GameBuilding.make(entry)
	var pos: Vector2 = entry.pos
	b.position = Vector3(pos.x, terrain.height_at(pos.x, pos.y) - 0.04, pos.y)
	add_child(b)
	buildings["player_home"] = b
	_add_home_zones()
	_on_hour_changed(int(DayNight.time_hours))


func _counter_zone(building_id: String, prompt: String, callback: Callable) -> void:
	var b: GameBuilding = buildings.get(building_id)
	if b == null or not b.markers.has("counter"):
		return
	var zone := InteractZone.make(b.markers["counter"], 1.9, prompt, callback)
	b.add_child(zone)


# --- runtime ------------------------------------------------------------------------------

func _on_hour_changed(_hour: int) -> void:
	# Lights come on at night — and during storms, like in any real town.
	var lights_on := DayNight.is_night() or DayNight.weather == "rain"
	Palette.set_night_lights(lights_on)
	for id in buildings:
		var b: GameBuilding = buildings[id]
		if b.interior_light != null:
			b.interior_light.visible = lights_on and Game.quality >= 1


## Minimap texture: terrain base + building footprints stamped on top.
func make_map_texture() -> ImageTexture:
	var img := terrain.map_base_image()
	var n: int = Terrain.N
	for rect in _indoor_rects:
		var x0 := clampi(int(rect.position.x / Terrain.CELL), 0, n - 1)
		var x1 := clampi(int(ceilf(rect.end.x / Terrain.CELL)), 0, n - 1)
		var z0 := clampi(int(rect.position.y / Terrain.CELL), 0, n - 1)
		var z1 := clampi(int(ceilf(rect.end.y / Terrain.CELL)), 0, n - 1)
		for iz in range(z0, z1 + 1):
			for ix in range(x0, x1 + 1):
				img.set_pixel(ix, iz, Color(0.88, 0.85, 0.78))
	return ImageTexture.create_from_image(img)


func ambience_at(pos: Vector3) -> Dictionary:
	var result := terrain.ambience_at(pos)
	var p2 := Vector2(pos.x, pos.z)
	for rect in _indoor_rects:
		if rect.has_point(p2):
			result.indoor = 1.0
			break
	return result


## Footstep sound for whatever the ray under the feet hit.
func step_sound_for(collider: Object, pos: Vector3) -> String:
	if collider != null and collider is Node and (collider as Node).has_meta("surface"):
		var surf: String = (collider as Node).get_meta("surface")
		if surf == "terrain":
			return terrain.step_sound_at(pos.x, pos.z)
		return "step_wood"
	return terrain.step_sound_at(pos.x, pos.z)
