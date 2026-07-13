class_name BigMap
extends Control
## Full-screen island map: tap the minimap (or press M) to open.
## Shows every point of interest with an icon + name, the player's
## position/heading and the active objective. Tap anywhere to close.

signal closed

## kind -> [icon, show name label]
const KIND_ICONS := {
	"shop": ["🏪", false],
	"cafe": ["🍜", false],
	"garage": ["🚗", true],
	"police": ["🚓", true],
	"hospital": ["🏥", true],
	"market": ["🐟", true],
	"sawmill": ["🪵", true],
	"depot": ["⛏", true],
	"player_home": ["🏠", true],
}

var objective_pos := Vector3.ZERO
var objective_active := false

var _tex: ImageTexture = null
var _pois: Array = []  # {icon, name, pos: Vector2}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(tex: ImageTexture) -> void:
	_tex = tex
	_pois.clear()
	for b in MapLayout.BUILDINGS:
		if KIND_ICONS.has(b.kind):
			var entry: Array = KIND_ICONS[b.kind]
			var poi_name: String = b.name if entry[1] else ""
			_pois.append({"icon": entry[0], "name": poi_name, "pos": b.pos})
	_pois.append({"icon": "🚕", "name": "Bến taxi", "pos": Vector2(414, 388)})
	_pois.append({"icon": "⛰", "name": "Mỏ đá", "pos": MapLayout.QUARRY_CENTER})
	_pois.append({"icon": "🏖", "name": "Bãi biển", "pos": Vector2(112, 500)})
	_pois.append({"icon": "🌊", "name": "Hồ Gương", "pos": MapLayout.LAKE_CENTER})
	_pois.append({"icon": "🌲", "name": "Rừng thông", "pos": MapLayout.FOREST_RECT.get_center()})
	if is_instance_valid(Game.world):
		for spot in Game.world.fishing_spots:
			_pois.append({"icon": "🎣", "name": "", "pos": Vector2(spot.x, spot.z)})


func open() -> void:
	visible = true
	queue_redraw()
	Audio.play_ui("click")


func close() -> void:
	if not visible:
		return
	visible = false
	Audio.play_ui("click")
	closed.emit()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		accept_event()
		close()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if _tex == null:
		return
	var vs := size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.04, 0.07, 0.93))
	var side: float = minf(vs.x, vs.y) - 72.0
	var origin: Vector2 = (vs - Vector2(side, side)) * 0.5
	var map_rect := Rect2(origin, Vector2(side, side))
	draw_texture_rect(_tex, map_rect, false)
	draw_rect(map_rect, Color(1, 1, 1, 0.4), false, 2.0)
	var font := get_theme_default_font()
	var map_scale: float = side / MapLayout.WORLD_SIZE

	for poi in _pois:
		var pos2: Vector2 = poi.pos
		var p: Vector2 = origin + pos2 * map_scale
		draw_string(font, p + Vector2(-13, 9), poi.icon,
			HORIZONTAL_ALIGNMENT_CENTER, 26, 22, Color.WHITE)
		var poi_name: String = poi.name
		if poi_name != "":
			var label_w := 180.0
			draw_string_outline(font, p + Vector2(-label_w * 0.5, 26), poi_name,
				HORIZONTAL_ALIGNMENT_CENTER, label_w, 13, 5, Color(0, 0, 0, 0.9))
			draw_string(font, p + Vector2(-label_w * 0.5, 26), poi_name,
				HORIZONTAL_ALIGNMENT_CENTER, label_w, 13, Color(1, 1, 1, 0.92))

	if objective_active:
		var o: Vector2 = origin + Vector2(objective_pos.x, objective_pos.z) * map_scale
		draw_circle(o, 7.5, Color(0, 0, 0, 0.9))
		draw_circle(o, 5.5, Color(1.0, 0.85, 0.2))

	if is_instance_valid(Game.player):
		var pp: Vector3 = Game.player.global_position
		var sp: Vector2 = origin + Vector2(pp.x, pp.z) * map_scale
		var yaw: float = Game.player.rotation.y
		var fwd := Vector2(sin(yaw), cos(yaw))
		var perp := Vector2(-fwd.y, fwd.x)
		draw_colored_polygon(PackedVector2Array([
			sp + fwd * 13.0, sp - fwd * 6.5 + perp * 7.5, sp - fwd * 6.5 - perp * 7.5,
		]), Color(0.05, 0.05, 0.05, 0.9))
		draw_colored_polygon(PackedVector2Array([
			sp + fwd * 10.0, sp - fwd * 4.8 + perp * 5.5, sp - fwd * 4.8 - perp * 5.5,
		]), Color(1, 1, 1))

	draw_string(font, origin + Vector2(2, -16), "🗺 BẢN ĐỒ HÒN GIÓ",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.98, 0.92, 0.75))
	draw_string(font, origin + Vector2(side - 300, -14), "Chạm để đóng  •  phím M",
		HORIZONTAL_ALIGNMENT_RIGHT, 300, 15, Color(1, 1, 1, 0.65))
