class_name NativeIgnitionButton
extends Control

## 0.2.35 round engine start/stop button.
##
## It intentionally uses the same visual language and diameter as
## the round handbrake lever button: translucent dark glass, a thin
## state ring and one white pictogram.  Red means the engine is off,
## amber means it is cranking/stopping, green means it is running.

signal pressed

const ENGINE_OFF := 0
const ENGINE_CRANKING := 1
const ENGINE_RUNNING := 2
const ENGINE_STOPPING := 3
const NO_DRAG := -2
const MOUSE_DRAG := -1

var _engine_state := ENGINE_OFF
var _drag_index := NO_DRAG
var _pulse_time := 0.0


func _ready() -> void:
	name = "IgnitionButton"
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	clip_contents = false
	set_process(true)


func set_engine_state(state: int) -> void:
	var next := clampi(state, ENGINE_OFF, ENGINE_STOPPING)
	if next != _engine_state:
		_engine_state = next
		queue_redraw()


func get_engine_state() -> int:
	return _engine_state


func is_held() -> bool:
	return _drag_index != NO_DRAG


func force_release() -> void:
	_drag_index = NO_DRAG
	queue_redraw()


func _process(delta: float) -> void:
	_pulse_time += maxf(delta, 0.0)
	if _engine_state == ENGINE_OFF or _engine_state == ENGINE_CRANKING or _engine_state == ENGINE_STOPPING:
		queue_redraw()


func _begin(index: int) -> void:
	_drag_index = index
	accept_event()
	pressed.emit()
	queue_redraw()


func _end(index: int) -> void:
	if index != _drag_index:
		return
	_drag_index = NO_DRAG
	accept_event()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if not touch.pressed:
			_end(touch.index)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
			_end(MOUSE_DRAG)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _drag_index == NO_DRAG and touch.position.distance_to(size * 0.5) <= minf(size.x, size.y) * 0.56:
				_begin(touch.index)
		else:
			_end(touch.index)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				if _drag_index == NO_DRAG and button.position.distance_to(size * 0.5) <= minf(size.x, size.y) * 0.56:
					_begin(MOUSE_DRAG)
			else:
				_end(MOUSE_DRAG)


func _state_color() -> Color:
	match _engine_state:
		ENGINE_RUNNING:
			return Color(0.18, 0.92, 0.48)
		ENGINE_CRANKING, ENGINE_STOPPING:
			return Color(1.0, 0.68, 0.12)
		_:
			return Color(1.0, 0.22, 0.16)


func _draw() -> void:
	if size.x < 20.0 or size.y < 20.0:
		return
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * (0.455 if is_held() else 0.485)
	var state_color := _state_color()

	if _engine_state == ENGINE_OFF:
		var pulse := 0.5 + 0.5 * sin(_pulse_time * 4.2)
		draw_arc(centre, radius * (1.03 + pulse * 0.035), 0.0, TAU, 80, Color(state_color, 0.16 + pulse * 0.20), maxf(radius * 0.055, 2.0), true)

	draw_circle(centre, radius, Color(0.008, 0.018, 0.034, 0.55 if is_held() else 0.48))
	draw_arc(centre, radius, 0.0, TAU, 80, Color(state_color, 0.90 if is_held() else 0.74), maxf(radius * 0.045, 2.0), true)

	if _engine_state == ENGINE_CRANKING:
		var start := _pulse_time * 5.2
		draw_arc(centre, radius * 0.84, start, start + PI * 1.35, 64, Color(state_color, 0.95), maxf(radius * 0.09, 3.0), true)
	elif _engine_state == ENGINE_RUNNING:
		draw_arc(centre, radius * 0.84, 0.0, TAU, 72, Color(state_color, 0.42), maxf(radius * 0.07, 3.0), true)

	var icon_color := Color(0.94, 0.97, 1.0, 0.97) if _engine_state == ENGINE_OFF else Color(state_color, 0.98)
	var icon_radius := radius * 0.43
	var line_width := maxf(radius * 0.10, 3.5)
	# Universal power symbol: an almost-closed ring with the stem at 12 o'clock.
	draw_arc(centre, icon_radius, -PI * 0.5 + 0.62, PI * 1.5 - 0.62, 64, icon_color, line_width, true)
	draw_line(
		centre + Vector2(0.0, -icon_radius * 1.22),
		centre + Vector2(0.0, -icon_radius * 0.18),
		icon_color,
		line_width,
		true
	)
	draw_circle(centre + Vector2(0.0, -icon_radius * 1.22), line_width * 0.52, icon_color)


func get_smoke_state() -> Dictionary:
	return {
		"ignition_button_0235": true,
		"engine_state": _engine_state,
		"held": is_held(),
		"rect": get_global_rect(),
		"diameter": minf(size.x, size.y),
	}
