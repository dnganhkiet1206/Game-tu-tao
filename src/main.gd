extends Node3D
## Game bootstrap: builds the island, spawns systems, NPCs, vehicles and the
## player, then hands control to the title screen.

var world: WorldRoot
var player: PlayerCharacter
var camera_rig: CameraRig
var hud: Hud
var npc_manager: NpcManager


func _ready() -> void:
	add_to_group("main")
	world = WorldRoot.new()
	add_child(world)
	world.build()

	add_child(PoliceManager.new())
	var fishing := FishingController.new()
	add_child(fishing)
	add_child(TaxiJob.new())
	add_child(DeliveryJob.new())

	npc_manager = NpcManager.new()
	add_child(npc_manager)

	_spawn_world_vehicles()

	player = PlayerCharacter.new()
	add_child(player)
	player.global_position = _spawn_point()

	camera_rig = CameraRig.new()
	add_child(camera_rig)
	camera_rig.target = player
	player.camera_rig = camera_rig

	hud = Hud.new()
	add_child(hud)
	hud.player = player

	npc_manager.spawn_all()

	hud.menus.start_requested.connect(_on_start)
	hud.menus.open_main(Game.has_save())


func _spawn_point() -> Vector3:
	var p: Vector3 = MapLayout.PLAYER_SPAWN
	return Vector3(p.x, world.terrain.height_at(p.x, p.z) + 0.3, p.z)


func _on_start(load_save: bool) -> void:
	if load_save and Game.load_game():
		if Game.pending_spawn.has("pos"):
			player.teleport_to(Game.pending_spawn.pos + Vector3(0, 0.2, 0))
			player.rotation.y = Game.pending_spawn.yaw
		_spawn_saved_cars()
		world.rebuild_player_home()
		Events.money_changed.emit(Game.money)
		Events.toast.emit("Chào mừng trở lại Hòn Gió!")
	else:
		Game.new_game()
		player.teleport_to(_spawn_point())
		Events.money_changed.emit(Game.money)
		_show_intro()
	world.apply_quality()
	# Refresh NPCs against the (possibly loaded) clock.
	for npc in npc_manager.npcs:
		npc.snap_to_schedule()


func _show_intro() -> void:
	Events.toast.emit("🏝 Chào mừng đến Hòn Gió!")
	var tips := [
		"Bạn có một cần câu trong túi — ra cầu tàu thử vận may!",
		"Kiếm tiền: câu cá, chặt gỗ, đào quặng, chạy taxi, giao hàng.",
		"Rìu và cuốc chim bán ở Tạp hoá Cô Ba.",
		"Về nhà ngủ sau 19:00 để lưu game và sang ngày mới.",
	]
	var delay := 3.0
	for tip in tips:
		# process_always=false so tips don't tick away behind the pause menu.
		var timer := get_tree().create_timer(delay, false)
		timer.timeout.connect(func() -> void: Events.toast.emit("💡 " + tip))
		delay += 3.4


# --- vehicles ---------------------------------------------------------------------

func _spawn_world_vehicles() -> void:
	for entry in MapLayout.VEHICLES:
		var pos: Vector2 = entry.pos
		_spawn_vehicle(entry.kind, entry.owner, entry.id,
			Vector3(pos.x, world.terrain.height_at(pos.x, pos.y) + 0.15, pos.y), entry.rot)
	# Showroom cars inside the garage.
	var slot_1: Vector3 = world.marker_global("garage", "car_slot_1")
	var slot_2: Vector3 = world.marker_global("garage", "car_slot_2")
	_spawn_vehicle("minica", "display", "display_minica", slot_1 + Vector3(0, 0.1, 0), 0.0)
	_spawn_vehicle("sedan", "display", "display_sedan", slot_2 + Vector3(0, 0.1, 0), 0.0)
	_spawn_traffic()


## Two ambient cars patrolling the main roads (the road net is a tree, so
## they ping-pong end to end and U-turn — enough life without traffic AI).
func _spawn_traffic() -> void:
	var main_street := [
		Vector2(170, 402), Vector2(300, 402), Vector2(430, 402),
		Vector2(560, 402), Vector2(688, 402),
	]
	var north_south := [
		Vector2(401.5, 190), Vector2(401.5, 300), Vector2(401.5, 430),
		Vector2(401.5, 560), Vector2(401.5, 630),
	]
	var routes := [main_street, north_south]
	var kinds := ["civic", "pickup"]
	for i in routes.size():
		var route: Array = []
		for p in routes[i]:
			route.append(Vector3(p.x, world.terrain.height_at(p.x, p.y), p.y))
		var start: Vector3 = route[0] if i == 0 else route[route.size() - 1]
		var car := _spawn_vehicle(kinds[i], "npc", "traffic_%d" % i, start + Vector3(0, 0.15, 0), 90.0)
		car.start_ai_route(route)


func _spawn_vehicle(kind: String, owner_tag: String, id: String, pos: Vector3, rot_deg: float) -> Vehicle:
	var v := Vehicle.make(kind, owner_tag, id)
	add_child(v)
	v.global_position = pos
	v.rotation.y = deg_to_rad(rot_deg)
	return v


func _spawn_saved_cars() -> void:
	var offset := 0.0
	for car_id in Game.owned_cars:
		_spawn_owned_at_home(car_id, offset)
		offset += 5.0


func _spawn_owned_at_home(car_id: String, offset: float) -> void:
	var home_door: Vector3 = world.door_global("player_home")
	var pos := home_door + Vector3(5.0 + offset, 0.3, 3.0)
	pos.y = world.terrain.height_at(pos.x, pos.z) + 0.15
	_spawn_vehicle(car_id, "player", "owned_" + car_id, pos, 90.0)


## Called by the garage shop right after a purchase.
func spawn_owned_car(car_id: String, at_garage: bool) -> void:
	if at_garage:
		var door: Vector3 = world.door_global("garage")
		var pos := door + Vector3(6.0, 0.3, 4.0)
		pos.y = world.terrain.height_at(pos.x, pos.z) + 0.15
		_spawn_vehicle(car_id, "player", "owned_" + car_id, pos, 0.0)
	else:
		_spawn_owned_at_home(car_id, 0.0)
