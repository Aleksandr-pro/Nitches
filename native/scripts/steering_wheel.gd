class_name NativeSteeringWheel
extends Control

## Direct analog steering wheel for touch and mouse.
##
## The driver grabs and rotates the rim itself.  Pointer rotation is
## accumulated around the hub and mapped 1:1 to a 270 degree
## lock-to-lock range (+/-135 degrees), so there is no second layer
## of button ramping between the hand and NativeVehicle's steering
## rack.  Releasing the wheel starts a fast, visible self-centring
## spring; the source remains "engaged" until it reaches centre so
## keyboard/gamepad input cannot fight the return.

signal steering_changed(value: float, engaged: bool)

const MAX_LOCK_DEGREES := 135.0
const CENTERING_RATE_PER_SEC := 4.2
const NO_DRAG := -2
const MOUSE_DRAG := -1

var _value := 0.0
var _drag_index := NO_DRAG
var _last_pointer_angle := 0.0
var _has_pointer_angle := false
var _centering := false
var _hub_label: Label


func _ready() -> void:
    name = "SteeringWheel"
    custom_minimum_size = Vector2(164.0, 164.0)
    mouse_filter = Control.MOUSE_FILTER_STOP
    focus_mode = Control.FOCUS_NONE
    clip_contents = false

    _hub_label = Label.new()
    _hub_label.name = "SteeringWheelLabel"
    _hub_label.text = "РУЛЬ"
    _hub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _hub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _hub_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _hub_label.add_theme_font_size_override("font_size", 13)
    _hub_label.add_theme_color_override("font_color", Color(0.92, 0.97, 1.0, 0.95))
    _hub_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
    _hub_label.add_theme_constant_override("shadow_offset_x", 1)
    _hub_label.add_theme_constant_override("shadow_offset_y", 1)
    add_child(_hub_label)
    _layout_label()


func get_steering_value() -> float:
    return _value


func is_engaged() -> bool:
    return _drag_index != NO_DRAG or _centering


func force_release() -> void:
    _drag_index = NO_DRAG
    _has_pointer_angle = false
    _centering = false
    _value = 0.0
    _emit_steering()
    queue_redraw()


func set_display_value(value: float) -> void:
    if is_engaged():
        return
    var next_value := clampf(value, -1.0, 1.0)
    if absf(next_value - _value) > 0.0005:
        _value = next_value
        queue_redraw()


func get_smoke_state() -> Dictionary:
    return {
        "touch_steering_wheel_0232": true,
        "created": true,
        "value": _value,
        "engaged": is_engaged(),
        "max_lock_degrees": MAX_LOCK_DEGREES,
        "centering_rate": CENTERING_RATE_PER_SEC,
        "rect": get_global_rect(),
    }


func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        _layout_label()
        queue_redraw()


func _layout_label() -> void:
    if _hub_label == null:
        return
    var centre := size * 0.5
    _hub_label.position = centre - Vector2(34.0, 11.0)
    _hub_label.size = Vector2(68.0, 22.0)


func _centre() -> Vector2:
    return size * 0.5


func _radius() -> float:
    return minf(size.x, size.y) * 0.46


func _pointer_angle(local_position: Vector2) -> Dictionary:
    var offset := local_position - _centre()
    if offset.length() < 16.0:
        return {"valid": false, "angle": 0.0}
    return {"valid": true, "angle": atan2(offset.y, offset.x)}


func _begin_drag(index: int, local_position: Vector2) -> void:
    if local_position.distance_to(_centre()) > _radius() * 1.18:
        return
    _drag_index = index
    _centering = false
    var pointer := _pointer_angle(local_position)
    _has_pointer_angle = bool(pointer.get("valid", false))
    _last_pointer_angle = float(pointer.get("angle", 0.0))
    accept_event()
    _emit_steering()
    queue_redraw()


func _move_drag(local_position: Vector2) -> void:
    var pointer := _pointer_angle(local_position)
    if not bool(pointer.get("valid", false)):
        _has_pointer_angle = false
        accept_event()
        return
    var angle := float(pointer.get("angle", 0.0))
    if not _has_pointer_angle:
        _last_pointer_angle = angle
        _has_pointer_angle = true
        accept_event()
        return
    var delta_degrees := rad_to_deg(wrapf(angle - _last_pointer_angle, -PI, PI))
    _last_pointer_angle = angle
    var next_value := clampf(_value + delta_degrees / MAX_LOCK_DEGREES, -1.0, 1.0)
    if absf(next_value - _value) > 0.00001:
        _value = next_value
        _emit_steering()
        queue_redraw()
    accept_event()


func _end_drag(index: int) -> void:
    if index != _drag_index:
        return
    _drag_index = NO_DRAG
    _has_pointer_angle = false
    _centering = absf(_value) > 0.001
    if not _centering:
        _value = 0.0
        _emit_steering()
    accept_event()
    queue_redraw()


func _gui_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        var touch := event as InputEventScreenTouch
        if touch.pressed:
            if _drag_index == NO_DRAG:
                _begin_drag(touch.index, touch.position)
        else:
            _end_drag(touch.index)
    elif event is InputEventScreenDrag:
        var drag := event as InputEventScreenDrag
        if drag.index == _drag_index:
            _move_drag(drag.position)
    elif event is InputEventMouseButton:
        var button := event as InputEventMouseButton
        if button.button_index == MOUSE_BUTTON_LEFT:
            if button.pressed:
                if _drag_index == NO_DRAG:
                    _begin_drag(MOUSE_DRAG, button.position)
            else:
                _end_drag(MOUSE_DRAG)
    elif event is InputEventMouseMotion:
        if _drag_index == MOUSE_DRAG:
            var motion := event as InputEventMouseMotion
            _move_drag(motion.position)


func _process(delta: float) -> void:
    if not _centering or _drag_index != NO_DRAG:
        return
    _value = move_toward(_value, 0.0, CENTERING_RATE_PER_SEC * maxf(delta, 0.0))
    if absf(_value) <= 0.001:
        _value = 0.0
        _centering = false
        _emit_steering()
    else:
        _emit_steering()
    queue_redraw()


func _emit_steering() -> void:
    steering_changed.emit(_value, is_engaged())


func _direction(angle: float) -> Vector2:
    return Vector2(cos(angle), sin(angle))


func _draw() -> void:
    var centre := _centre()
    var radius := _radius()
    var rotation := deg_to_rad(_value * MAX_LOCK_DEGREES)
    var engaged := is_engaged()

    draw_circle(centre, radius * 1.08, Color(0.004, 0.012, 0.024, 0.52))
    draw_arc(centre, radius * 1.08, 0.0, TAU, 72, Color(0.35, 0.85, 1.0, 0.20), 1.5, true)

    # Fixed centre tick and the swept lock arc show exactly where the
    # wheel is relative to straight-ahead before the rim is read.
    var top_angle := -PI * 0.5
    draw_line(centre + _direction(top_angle) * radius * 1.03, centre + _direction(top_angle) * radius * 1.15, Color(1.0, 0.72, 0.16, 0.95), 3.0, true)
    if absf(rotation) > 0.001:
        var start_angle := minf(top_angle, top_angle + rotation)
        var end_angle := maxf(top_angle, top_angle + rotation)
        draw_arc(centre, radius * 1.08, start_angle, end_angle, 48, Color(1.0, 0.58, 0.08, 0.95), 5.0, true)

    draw_arc(centre, radius, 0.0, TAU, 96, Color(0.02, 0.025, 0.035, 0.94), 17.0, true)
    draw_arc(centre, radius, 0.0, TAU, 96, Color(0.78, 0.86, 0.94, 0.96), 10.0, true)
    draw_arc(centre, radius - 8.0, 0.0, TAU, 96, Color(0.05, 0.16, 0.28, 0.75), 2.0, true)

    var spoke_angles: Array[float] = [
        top_angle + rotation,
        top_angle + rotation + PI * 0.72,
        top_angle + rotation - PI * 0.72,
    ]
    for angle in spoke_angles:
        draw_line(centre, centre + _direction(angle) * (radius - 8.0), Color(0.66, 0.74, 0.84, 0.98), 10.0, true)
        draw_line(centre, centre + _direction(angle) * (radius - 8.0), Color(0.08, 0.14, 0.22, 0.95), 4.0, true)

    # Rotating top-centre marker on the rim.
    draw_line(
        centre + _direction(top_angle + rotation) * radius * 0.84,
        centre + _direction(top_angle + rotation) * radius * 1.02,
        Color(1.0, 0.62, 0.08, 1.0),
        6.0,
        true
    )

    draw_circle(centre, radius * 0.34, Color(0.025, 0.05, 0.09, 0.98))
    draw_arc(centre, radius * 0.34, 0.0, TAU, 64, Color(1.0, 0.66, 0.14, 0.95 if engaged else 0.62), 3.0, true)
    draw_circle(centre, 4.0, Color(1.0, 0.72, 0.16, 1.0))
