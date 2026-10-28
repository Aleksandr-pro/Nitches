class_name NativeWheelPreview
extends Control
## Large touch-friendly wheel-finish preview drawn from the exact PBR albedo
## values used by the 3D Shelby wheels.

signal pressed

var rim_color := Color(0.72, 0.75, 0.78)
var selected := false
var _hovered := false


func _init() -> void:
	custom_minimum_size = Vector2(64.0, 64.0)
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void:
		_hovered = true
		queue_redraw()
	)
	mouse_exited.connect(func() -> void:
		_hovered = false
		queue_redraw()
	)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func set_finish(p_color: Color, p_selected: bool) -> void:
	rim_color = p_color
	selected = p_selected
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			pressed.emit()
			accept_event()
	elif event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			pressed.emit()
			accept_event()
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and (key_event.keycode == KEY_ENTER or key_event.keycode == KEY_SPACE or key_event.keycode == KEY_KP_ENTER):
			pressed.emit()
			accept_event()


func _draw() -> void:
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * 0.44
	var rim_radius := radius * 0.66
	var ring_color := Color(1.0, 0.62, 0.10, 1.0) if selected else (Color(0.85, 0.92, 1.0, 0.75) if (_hovered or has_focus()) else Color(0.45, 0.54, 0.65, 0.55))
	draw_circle(centre, radius + 3.0, Color(0.015, 0.018, 0.022, 0.55))
	draw_circle(centre, radius, Color(0.025, 0.028, 0.033, 1.0))
	draw_arc(centre, radius - 1.5, 0.0, TAU, 56, Color(0.16, 0.17, 0.19, 1.0), 3.0, true)
	draw_circle(centre, rim_radius, rim_color)
	draw_arc(centre, rim_radius - 1.0, 0.0, TAU, 48, rim_color.lightened(0.22), 2.0, true)
	# Five broad spokes and a hub make each finish recognisable without text.
	for index in range(5):
		var angle := -PI * 0.5 + float(index) * TAU / 5.0
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(centre, centre + direction * (rim_radius - 3.0), rim_color.darkened(0.22), 6.0, true)
	draw_circle(centre, rim_radius * 0.24, rim_color.lightened(0.22))
	draw_circle(centre, rim_radius * 0.11, Color(0.04, 0.05, 0.06, 0.9))
	# Painted brake calliper glimpse.
	draw_arc(centre, rim_radius * 0.72, -0.45, 0.42, 14, Color(0.75, 0.08, 0.06, 0.95), 4.0, true)
	draw_arc(centre, radius + 1.5, 0.0, TAU, 56, ring_color, 3.0 if selected else 1.6, true)
	if selected:
		draw_circle(centre + Vector2(0.0, radius + 5.0), 3.0, Color(1.0, 0.62, 0.10, 1.0))
