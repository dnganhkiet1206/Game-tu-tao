class_name Minimap
extends Control
## Zoomed top-down minimap: a window of the baked island texture that
## follows the player, with a heading arrow and the current objective dot.
## North is up (world +Z maps to screen down, matching world axes).

signal tapped

const WINDOW_M := 250.0

var objective_pos := Vector3.ZERO
var objective_active := false

var _tex: ImageTexture = null


func _ready() -> void:
	# STOP so a tap on the minimap opens the big map (this control sits
	# above the joystick capture area).
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(168, 168)
	size = Vector2(168, 168)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		accept_event()
		tapped.emit()


func setup(tex: ImageTexture) -> void:
	_tex = tex


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if _tex == null or not is_instance_valid(Game.player):
		return
	var n := float(Terrain.N)
	var half_px: float = WINDOW_M * 0.5 / Terrain.CELL
	var p: Vector3 = Game.player.global_position
	var center_px: Vector2 = Vector2(p.x, p.z) / Terrain.CELL
	var region := Rect2(center_px - Vector2(half_px, half_px), Vector2(half_px, half_px) * 2.0)
	region.position.x = clampf(region.position.x, 0.0, n - region.size.x)
	region.position.y = clampf(region.position.y, 0.0, n - region.size.y)

	draw_rect(Rect2(Vector2(-3, -3), size + Vector2(6, 6)), Color(0.05, 0.07, 0.1, 0.8))
	draw_texture_rect_region(_tex, Rect2(Vector2.ZERO, size), region)
	var px_scale := size.x / region.size.x  # screen px per map px

	if objective_active:
		var o: Vector2 = (Vector2(objective_pos.x, objective_pos.z) / Terrain.CELL - region.position) * px_scale
		o = o.clamp(Vector2(7, 7), size - Vector2(7, 7))
		draw_circle(o, 6.0, Color(0.08, 0.08, 0.08, 0.9))
		draw_circle(o, 4.5, Color(1.0, 0.85, 0.2))

	# Player heading arrow (facing +Z == screen down).
	var sp: Vector2 = (center_px - region.position) * px_scale
	var yaw: float = Game.player.rotation.y
	var fwd := Vector2(sin(yaw), cos(yaw))
	var perp := Vector2(-fwd.y, fwd.x)
	var tri := PackedVector2Array([sp + fwd * 10.0, sp - fwd * 5.0 + perp * 6.0, sp - fwd * 5.0 - perp * 6.0])
	draw_colored_polygon(tri, Color(0.05, 0.05, 0.05, 0.85))
	var tri_inner := PackedVector2Array([sp + fwd * 8.0, sp - fwd * 3.6 + perp * 4.4, sp - fwd * 3.6 - perp * 4.4])
	draw_colored_polygon(tri_inner, Color(1, 1, 1))

	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.35), false, 2.0)
