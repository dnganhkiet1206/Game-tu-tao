class_name InteractZone
extends Area3D
## Generic "walk up and press the action button" volume.
## World / buildings wire a prompt + callback into these.

var prompt: String = "Tương tác"
var callback: Callable = Callable()
var enabled: bool = true


static func make(pos: Vector3, radius: float, p_prompt: String, p_callback: Callable) -> InteractZone:
	var zone := InteractZone.new()
	zone.prompt = p_prompt
	zone.callback = p_callback
	zone.collision_layer = Layers.INTERACT
	zone.collision_mask = 0
	zone.monitoring = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	zone.add_child(shape)
	zone.position = pos
	return zone


func get_prompt() -> String:
	return prompt


func can_interact(_player: Node3D) -> bool:
	return enabled


func interact(player: Node3D) -> void:
	if enabled and callback.is_valid():
		callback.call(player)
