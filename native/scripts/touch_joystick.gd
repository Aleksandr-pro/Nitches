class_name NativeTouchJoystick
extends Control

## 0.3.28: virtual analogue stick for on-foot movement.  Drawn
## to match the driving HUD language (dark translucent disc,
## accent ring, soft knob) and polled via `get_value()` — the
## returned vector is in screen space (x right, y down), length
## clamped to 1, so main can merge it with keyboard axes as-is.
## Touch and mouse both drive it; multi-touch tracks one finger.

const _MOUSE_POINTER := 0x3FFFFFFF

var _value := Vector2.ZERO
var _knob_offset := Vector2.ZERO
var _pointer_id := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


func get_value() -> Vector2:
	return _value


func release() -> void:
	_value = Vector2.ZERO
	_knob_offset = Vector2.ZERO
	_pointer_id = -1
	queue_redraw()


func _travel_radius() -> float:
	return minf(size.x, size.y) * 0.36


func _update_from(local_position: Vector2) -> void:
	var centre := size * 0.5
	var offset := local_position - centre
	var radius := maxf(_travel_radius(), 1.0)
	if offset.length() > radius:
		offset = offset.normalized() * radius
	_knob_offset = offset
	_value = offset / radius
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _pointer_id == -1:
			_pointer_id = touch.index
			_update_from(touch.position)
			accept_event()
		elif not touch.pressed and touch.index == _pointer_id:
			release()
			accept_event()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _pointer_id:
			_update_from(drag.position)
			accept_event()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed and _pointer_id == -1:
				_pointer_id = _MOUSE_POINTER
				_update_from(button.position)
				accept_event()
			elif not button.pressed and _pointer_id == _MOUSE_POINTER:
				release()
				accept_event()
	elif event is InputEventMouseMotion:
		if _pointer_id == _MOUSE_POINTER:
			_update_from((event as InputEventMouseMotion).position)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _pointer_id == _MOUSE_POINTER:
		release()


func _draw() -> void:
	var centre := size * 0.5
	var base_radius := minf(size.x, size.y) * 0.47
	if base_radius <= 2.0:
		return
	draw_circle(centre, base_radius, Color(0.006, 0.014, 0.028, 0.44))
	draw_arc(centre, base_radius, 0.0, TAU, 56, Color(1.0, 0.64, 0.16, 0.5), 3.0, true)
	# Cardinal ticks keep the stick readable at a glance.
	for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var tick_at := centre + direction * base_radius * 0.78
		draw_circle(tick_at, 3.0, Color(1.0, 1.0, 1.0, 0.28))
	var knob_radius := base_radius * 0.42
	var knob_centre := centre + _knob_offset
	draw_circle(knob_centre, knob_radius, Color(1.0, 1.0, 1.0, 0.3))
	draw_arc(knob_centre, knob_radius, 0.0, TAU, 40, Color(1.0, 1.0, 1.0, 0.55), 2.5, true)
	draw_circle(knob_centre, knob_radius * 0.36, Color(1.0, 0.64, 0.16, 0.65))
