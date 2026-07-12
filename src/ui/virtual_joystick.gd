class_name VirtualJoystick
extends Control
## Floating virtual joystick: the stick appears where the thumb lands
## (anywhere on the left part of the screen) — the standard feel in
## commercial mobile games. Multitouch-safe: tracks its own finger index.
## NOTE: positions in _gui_input are local to this control.

signal vector_changed(v: Vector2)

const RADIUS := 92.0
const KNOB_RADIUS := 36.0
const DEAD_ZONE := 0.08

var output := Vector2.ZERO
var _touch_id := -1
var _anchor := Vector2.ZERO
var _knob := Vector2.ZERO
var _blocked := false  # true while a modal panel is open


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_blocked(value: bool) -> void:
	_blocked = value
	if _blocked:
		_release()


func _gui_input(event: InputEvent) -> void:
	if _blocked:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _touch_id == -1:
			_touch_id = touch.index
			_anchor = touch.position
			_knob = touch.position
			accept_event()
			queue_redraw()
		elif not touch.pressed and touch.index == _touch_id:
			_release()
			accept_event()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_id:
			_knob = drag.position
			var v := (_knob - _anchor) / RADIUS
			if v.length() > 1.0:
				v = v.normalized()
				# Let the anchor follow long drags (feels better on phones).
				_anchor = _knob - v * RADIUS
			output = Vector2.ZERO if v.length() < DEAD_ZONE else v
			vector_changed.emit(output)
			accept_event()
			queue_redraw()


func _release() -> void:
	_touch_id = -1
	output = Vector2.ZERO
	vector_changed.emit(output)
	queue_redraw()


func _draw() -> void:
	if _touch_id == -1:
		return
	var knob := _knob
	if (knob - _anchor).length() > RADIUS:
		knob = _anchor + (knob - _anchor).normalized() * RADIUS
	draw_circle(_anchor, RADIUS, Color(1, 1, 1, 0.08))
	draw_arc(_anchor, RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.25), 3.0, true)
	draw_circle(knob, KNOB_RADIUS, Color(1, 1, 1, 0.30))
	draw_arc(knob, KNOB_RADIUS, 0, TAU, 24, Color(1, 1, 1, 0.5), 2.0, true)
