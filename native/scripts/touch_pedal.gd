class_name NativeTouchPedal
extends Control

## Tall analog touch pedal.  While held, its value and visible
## bottom-up fill rise together; while released, both fall.  This
## gives real progressive throttle/brake command on hardware without
## pressure-sensitive touch.

signal value_changed(action_name: String, value: float)

const NO_DRAG := -2
const MOUSE_DRAG := -1
const PRESS_RATE := 5.2
const RELEASE_RATE := 7.0

var _action_name := ""
var _accent := Color(0.1, 0.7, 0.3)
var _value := 0.0
var _drag_index := NO_DRAG
var _arrow_label: Label
var _background_style: StyleBoxFlat
var _fill_style: StyleBoxFlat
var _pressed_background_style: StyleBoxFlat


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    focus_mode = Control.FOCUS_NONE
    clip_contents = true
    _arrow_label = Label.new()
    _arrow_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _arrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _arrow_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _arrow_label.add_theme_color_override("font_color", Color.WHITE)
    _arrow_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
    _arrow_label.add_theme_constant_override("shadow_offset_x", 1)
    _arrow_label.add_theme_constant_override("shadow_offset_y", 1)
    add_child(_arrow_label)
    _rebuild_styles()
    _layout_arrow()


func configure(action_name: String, arrow: String, accent: Color) -> void:
    _action_name = action_name
    _accent = accent
    name = "GasPedal" if action_name == "accelerate" else "BrakePedal"
    if _arrow_label != null:
        _arrow_label.text = arrow
    _rebuild_styles()
    queue_redraw()


func get_value() -> float:
    return _value


func is_held() -> bool:
    return _drag_index != NO_DRAG


func force_release() -> void:
    _drag_index = NO_DRAG
    if _value != 0.0:
        _value = 0.0
        value_changed.emit(_action_name, _value)
    queue_redraw()


func get_smoke_state() -> Dictionary:
    return {
        "analog_pedal_0233": true,
        "action": _action_name,
        "value": _value,
        "held": is_held(),
        "rect": get_global_rect(),
    }


func _rebuild_styles() -> void:
    _background_style = StyleBoxFlat.new()
    _background_style.bg_color = Color(0.01, 0.02, 0.035, 0.48)
    _background_style.border_color = Color(_accent, 0.58)
    _background_style.set_border_width_all(2)
    _background_style.set_corner_radius_all(18)

    _pressed_background_style = StyleBoxFlat.new()
    _pressed_background_style.bg_color = Color(0.015, 0.03, 0.05, 0.55)
    _pressed_background_style.border_color = Color(1.0, 0.78, 0.28, 0.92)
    _pressed_background_style.set_border_width_all(2)
    _pressed_background_style.set_corner_radius_all(16)

    _fill_style = StyleBoxFlat.new()
    _fill_style.bg_color = Color(_accent, 0.52)
    _fill_style.set_corner_radius_all(16)


func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        _layout_arrow()
        queue_redraw()


func _layout_arrow() -> void:
    if _arrow_label == null:
        return
    _arrow_label.position = Vector2.ZERO
    _arrow_label.size = size
    _arrow_label.add_theme_font_size_override("font_size", int(clampf(minf(size.x, size.y) * 0.48, 30.0, 58.0)))


func _begin(index: int) -> void:
    _drag_index = index
    accept_event()
    queue_redraw()


func _end(index: int) -> void:
    if index == _drag_index:
        _drag_index = NO_DRAG
        accept_event()
        queue_redraw()


func _input(event: InputEvent) -> void:
    # A finger can be lifted just outside the visual pedal/button.
    # Release is therefore also observed globally for our own drag
    # index, so a custom touch control can never remain stuck on.
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
            if _drag_index == NO_DRAG:
                _begin(touch.index)
        else:
            _end(touch.index)
    elif event is InputEventMouseButton:
        var button := event as InputEventMouseButton
        if button.button_index == MOUSE_BUTTON_LEFT:
            if button.pressed:
                if _drag_index == NO_DRAG:
                    _begin(MOUSE_DRAG)
            else:
                _end(MOUSE_DRAG)


func _process(delta: float) -> void:
    var target := 1.0 if is_held() else 0.0
    var rate := PRESS_RATE if is_held() else RELEASE_RATE
    var next_value := move_toward(_value, target, rate * maxf(delta, 0.0))
    if absf(next_value - _value) > 0.0005:
        _value = next_value
        value_changed.emit(_action_name, _value)
        queue_redraw()


func _draw() -> void:
    if size.x < 20.0 or size.y < 20.0 or _background_style == null:
        return
    var inset := 3.0 if is_held() else 0.0
    var rect := Rect2(Vector2(inset, inset), size - Vector2(inset * 2.0, inset * 2.0))
    draw_stylebox(_pressed_background_style if is_held() else _background_style, rect)
    if _value > 0.001:
        var fill_height := maxf((rect.size.y - 6.0) * _value, 3.0)
        var fill_rect := Rect2(rect.position + Vector2(3.0, rect.size.y - 3.0 - fill_height), Vector2(rect.size.x - 6.0, fill_height))
        draw_stylebox(_fill_style, fill_rect)
    var line_color := Color(1.0, 1.0, 1.0, 0.20 if not is_held() else 0.34)
    for i in 3:
        var y := rect.position.y + 18.0 + float(i) * 12.0
        draw_line(Vector2(rect.position.x + 14.0, y), Vector2(rect.end.x - 14.0, y), line_color, 2.0, true)
