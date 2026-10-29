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
const COMMON_WHEEL_TEXTURE: Texture2D = preload("res://assets/ui/steering_wheel_common.png")
const COMMON_WHEEL_TEXTURE_ID := "common_sport"

var _value := 0.0
var _drag_index := NO_DRAG
var _last_pointer_angle := 0.0
var _has_pointer_angle := false
var _centering := false
var _input_enabled := true
var _wheel_texture: Texture2D = COMMON_WHEEL_TEXTURE
var _wheel_texture_id := COMMON_WHEEL_TEXTURE_ID


func _ready() -> void:
    name = "SteeringWheel"
    custom_minimum_size = Vector2(164.0, 164.0)
    mouse_filter = Control.MOUSE_FILTER_STOP
    focus_mode = Control.FOCUS_NONE
    clip_contents = false


## 0.2.40: the HUD wheel is the owner's processed steering-wheel photo.
## Every car currently uses the common sport wheel; the catalogue can
## later point individual cars at their own transparent wheel PNG and
## this one call swaps it without touching the analog input code.
func set_wheel_texture(texture: Texture2D, texture_id: String = COMMON_WHEEL_TEXTURE_ID) -> void:
    if texture == null:
        return
    _wheel_texture = texture
    _wheel_texture_id = texture_id if not texture_id.is_empty() else COMMON_WHEEL_TEXTURE_ID
    queue_redraw()


func set_wheel_texture_path(path: String, texture_id: String = COMMON_WHEEL_TEXTURE_ID) -> void:
    if path.is_empty() or not ResourceLoader.exists(path):
        return
    var texture := load(path) as Texture2D
    if texture != null:
        set_wheel_texture(texture, texture_id)


func get_wheel_texture_id() -> String:
    return _wheel_texture_id


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


func set_input_enabled(enabled: bool) -> void:
    _input_enabled = enabled
    mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
    if not enabled:
        force_release()
    queue_redraw()


func is_input_enabled() -> bool:
    return _input_enabled


func get_smoke_state() -> Dictionary:
    return {
        "touch_steering_wheel_0232": true,
        "created": true,
        "value": _value,
        "engaged": is_engaged(),
        "input_enabled": _input_enabled,
        "configurable_size_0233": true,
        "photo_steering_wheel_0240": _wheel_texture != null,
        "replaceable_per_car_0240": true,
        "wheel_texture_id": _wheel_texture_id,
        "wheel_texture_size": _wheel_texture.get_size() if _wheel_texture != null else Vector2.ZERO,
        "max_lock_degrees": MAX_LOCK_DEGREES,
        "centering_rate": CENTERING_RATE_PER_SEC,
        "rect": get_global_rect(),
    }


func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        queue_redraw()


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


func _input(event: InputEvent) -> void:
    if not _input_enabled:
        return
    if event is InputEventScreenTouch:
        var touch := event as InputEventScreenTouch
        if not touch.pressed:
            _end_drag(touch.index)
    elif event is InputEventMouseButton:
        var button := event as InputEventMouseButton
        if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
            _end_drag(MOUSE_DRAG)


func _gui_input(event: InputEvent) -> void:
    if not _input_enabled:
        return
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

    # A soft dark disc behind the cut-out keeps the black leather readable
    # over bright roads; the photograph itself stays transparent through
    # the rim openings.
    draw_circle(centre, radius * 1.08, Color(0.004, 0.012, 0.024, 0.42))
    draw_arc(centre, radius * 1.08, 0.0, TAU, 72, Color(0.35, 0.85, 1.0, 0.16), 1.5, true)

    if _wheel_texture != null:
        var half := radius * 1.075
        draw_set_transform(centre, rotation, Vector2.ONE)
        draw_texture_rect(
            _wheel_texture,
            Rect2(Vector2(-half, -half), Vector2(half * 2.0, half * 2.0)),
            false,
            Color(1.0, 1.0, 1.0, 0.98 if engaged else 0.94)
        )
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    else:
        # Defensive fallback only; the shipped build always stages the
        # processed common-wheel PNG.
        draw_arc(centre, radius, 0.0, TAU, 96, Color(0.78, 0.86, 0.94, 0.96), 10.0, true)
        draw_circle(centre, radius * 0.34, Color(0.025, 0.05, 0.09, 0.98))

    # Fixed centre tick and the swept lock arc show exactly where the
    # wheel is relative to straight-ahead before the rim is read.
    var top_angle := -PI * 0.5
    draw_line(centre + _direction(top_angle) * radius * 1.03, centre + _direction(top_angle) * radius * 1.15, Color(1.0, 0.72, 0.16, 0.95), 3.0, true)
    if absf(rotation) > 0.001:
        var start_angle := minf(top_angle, top_angle + rotation)
        var end_angle := maxf(top_angle, top_angle + rotation)
        draw_arc(centre, radius * 1.08, start_angle, end_angle, 48, Color(1.0, 0.58, 0.08, 0.95), 5.0, true)
