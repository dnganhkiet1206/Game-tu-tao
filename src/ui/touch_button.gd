class_name TouchButton
extends Control
## Round on-screen button that is multitouch-safe (regular Buttons rely on
## single-touch mouse emulation). Can inject an input action while held
## and/or fire a callback on tap.

signal tapped

var label := "A"
var action := ""            # optional input action pressed while held
var radius := 42.0
var base_color := Color(0.1, 0.12, 0.16, 0.55)
var held := false

var _touch_id := -1
var _font: Font


func _init(p_label: String = "A", p_radius: float = 42.0, p_action: String = "") -> void:
	label = p_label
	radius = p_radius
	action = p_action


func _ready() -> void:
	custom_minimum_size = Vector2(radius * 2.0, radius * 2.0)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = get_theme_default_font()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		# Positions here are local to the control.
		var inside := touch.position.distance_to(size * 0.5) <= radius * 1.25
		if touch.pressed and _touch_id == -1 and inside:
			_touch_id = touch.index
			_press()
			accept_event()
		elif not touch.pressed and touch.index == _touch_id:
			_touch_id = -1
			_unpress(true)
			accept_event()


func _press() -> void:
	held = true
	if action != "":
		Input.action_press(action)
	queue_redraw()


func _unpress(fire: bool) -> void:
	held = false
	if action != "":
		Input.action_release(action)
	if fire:
		tapped.emit()
	queue_redraw()


func force_release() -> void:
	if held:
		_touch_id = -1
		_unpress(false)


func set_label(text: String) -> void:
	if label != text:
		label = text
		queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var color := base_color
	if held:
		color = Color(base_color.r + 0.15, base_color.g + 0.15, base_color.b + 0.15, 0.75)
	draw_circle(center, radius, color)
	draw_arc(center, radius, 0, TAU, 40, Color(1, 1, 1, 0.4), 2.5, true)
	var font_size := int(radius * 0.62)
	var text_size := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string(_font, center - Vector2(text_size.x * 0.5, -text_size.y * 0.28), label,
		HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(1, 1, 1, 0.92))
