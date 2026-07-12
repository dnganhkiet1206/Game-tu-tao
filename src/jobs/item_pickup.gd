class_name ItemPickup
extends Area3D
## Bobbing world item; walks into the player's inventory on contact.

var item_id := "log"
var count := 1
var _mesh: MeshInstance3D
var _time := 0.0
var _base_y := 0.0
var _collected := false


static func make(p_item_id: String, p_count: int = 1) -> ItemPickup:
	var pickup := ItemPickup.new()
	pickup.item_id = p_item_id
	pickup.count = p_count
	return pickup


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.PLAYER
	monitoring = true
	_mesh = MeshInstance3D.new()
	_mesh.mesh = Props.item_mesh(item_id)
	add_child(_mesh)
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 1.0
	col.shape = shape
	col.position = Vector3(0, 0.4, 0)
	add_child(col)
	body_entered.connect(_on_body_entered)
	_time = randf() * TAU


func _process(delta: float) -> void:
	_time += delta
	if _base_y == 0.0:
		_base_y = position.y
	_mesh.position.y = 0.12 + sin(_time * 2.2) * 0.08
	_mesh.rotation.y += delta * 1.2


func _on_body_entered(body: Node3D) -> void:
	if _collected or not body.is_in_group("player"):
		return
	_collected = true
	Game.add_item(item_id, count)
	Audio.play_at("pickup", global_position, -2.0)
	Events.toast.emit("+%d %s" % [count, Game.item_name(item_id)])
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_mesh, "scale", Vector3.ONE * 0.05, 0.18)
	tween.tween_property(_mesh, "position:y", 1.2, 0.18)
	tween.chain().tween_callback(queue_free)
