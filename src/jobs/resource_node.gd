class_name ResourceNode
extends StaticBody3D
## A harvestable world resource: choppable tree or mineable ore rock.
## Interacting starts the player's auto-work loop; each swing calls hit().

var kind := "tree"  # "tree" | "ore"
var ore_id := "ore_copper"
var hp := 4
var max_hp := 4
var alive := true
var respawn_seconds := 150.0

var _mesh: MeshInstance3D
var _stump: MeshInstance3D = null


static func make_tree(variant: int) -> ResourceNode:
	var node := ResourceNode.new()
	node.kind = "tree"
	node.max_hp = 4
	node.hp = 4
	node._setup(Props.pine_mesh(variant), 0.35, 5.0)
	return node


static func make_ore(p_ore_id: String) -> ResourceNode:
	var node := ResourceNode.new()
	node.kind = "ore"
	node.ore_id = p_ore_id
	node.max_hp = 5
	node.hp = 5
	node.respawn_seconds = 200.0
	node._setup(Props.ore_mesh(p_ore_id), 0.9, 1.4)
	return node


func _setup(mesh: ArrayMesh, radius: float, height: float) -> void:
	collision_layer = Layers.WORLD | Layers.INTERACT
	collision_mask = 0
	_mesh = MeshInstance3D.new()
	_mesh.mesh = mesh
	if kind == "tree":
		# Wind sway displaces vertices beyond the static AABB.
		_mesh.extra_cull_margin = 1.0
	add_child(_mesh)
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	col.shape = shape
	col.position = Vector3(0, height * 0.5, 0)
	add_child(col)
	if kind == "tree":
		_stump = MeshInstance3D.new()
		_stump.mesh = Props.stump_mesh()
		_stump.visible = false
		add_child(_stump)


func required_tool() -> String:
	return "axe" if kind == "tree" else "pickaxe"


func get_prompt() -> String:
	if not alive:
		return ""
	if kind == "tree":
		return "Chặt cây" if Game.has_tool("axe") else "Cần rìu để chặt"
	return "Đào quặng" if Game.has_tool("pickaxe") else "Cần cuốc chim"


func can_interact(_player: Node3D) -> bool:
	return alive


func interact(player: Node3D) -> void:
	if not alive:
		return
	if not Game.has_tool(required_tool()):
		var tool_name: String = Game.item_name(required_tool())
		Events.toast.emit("Bạn cần %s — mua ở Tạp hoá Cô Ba" % tool_name)
		Audio.play_ui("denied")
		return
	if player.has_method("start_working"):
		player.start_working(self)


## Returns true while the node still stands.
func take_hit(from_pos: Vector3) -> bool:
	if not alive:
		return false
	hp -= 1
	if kind == "tree":
		Audio.play_at("chop", global_position, 0.0)
		_shake()
	else:
		Audio.play_at("pickaxe", global_position, 0.0)
		_shake()
	if hp <= 0:
		_deplete(from_pos)
		return false
	return true


func _shake() -> void:
	var tween := create_tween()
	var original := _mesh.rotation
	tween.tween_property(_mesh, "rotation:z", original.z + 0.05, 0.05)
	tween.tween_property(_mesh, "rotation:z", original.z, 0.12)


func _deplete(from_pos: Vector3) -> void:
	alive = false
	collision_layer = 0
	if kind == "tree":
		Game.stats.trees_felled += 1
		_fall_tree(from_pos)
	else:
		Game.stats.ore_mined += 1
		Audio.play_at("rock_break", global_position, 2.0)
		_mesh.visible = false
		_spawn_yield()
	# process_always=false: the respawn clock respects game pause.
	var timer := get_tree().create_timer(respawn_seconds, false)
	timer.timeout.connect(_respawn)


func _fall_tree(from_pos: Vector3) -> void:
	Audio.play_at("tree_fall", global_position, 3.0)
	var away := (global_position - from_pos)
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3.FORWARD
	away = away.normalized()
	var axis := away.cross(Vector3.UP).normalized()
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_method(_apply_fall.bind(axis), 0.0, -1.45, 1.1)
	tween.tween_callback(func() -> void:
		_mesh.visible = false
		_mesh.transform = Transform3D.IDENTITY
		if _stump != null:
			_stump.visible = true
		_spawn_yield()
	)


func _apply_fall(angle: float, axis: Vector3) -> void:
	_mesh.transform = Transform3D(Basis(axis, angle), Vector3.ZERO)


func _spawn_yield() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var drops: Array = []
	if kind == "tree":
		for i in rng.randi_range(2, 3):
			drops.append("log")
	else:
		var count := rng.randi_range(1, 2)
		for i in count:
			drops.append(ore_id)
		if ore_id != "ore_gold" and rng.randf() < 0.08:
			drops.append("ore_gold")
	for i in drops.size():
		var ang := TAU * i / drops.size() + rng.randf_range(0.0, 1.0)
		var offset := Vector3(cos(ang) * 1.1, 0.1, sin(ang) * 1.1)
		var pickup := ItemPickup.make(drops[i], 1)
		get_parent().add_child(pickup)
		pickup.global_position = global_position + offset


func _respawn() -> void:
	if not is_instance_valid(self):
		return
	alive = true
	hp = max_hp
	collision_layer = Layers.WORLD | Layers.INTERACT
	_mesh.visible = true
	if _stump != null:
		_stump.visible = false
	# Pop-in scale so respawns aren't jarring.
	_mesh.scale = Vector3.ONE * 0.1
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_mesh, "scale", Vector3.ONE, 0.5)
