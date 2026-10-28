class_name NativeRoundActionButton
extends Control

## Circular hold button used for nitro and handbrake.  Nitro uses
## its full circumference as the charge gauge and turns grey when
## empty; the handbrake draws a simple lever pictogram and glows
## orange while held.

signal pressed_changed(action_name: String, pressed: bool)

const NO_DRAG := -2
const MOUSE_DRAG := -1

var _action_name := ""
var _kind := "nitro"
var _accent := Color(0.1, 0.7, 1.0)
var _charge_ratio := 1.0
var _drag_index := NO_DRAG
var _label: Label


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    focus_mode = Control.FOCUS_NONE
    clip_contents = false
    _label = Label.new()
    _label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _label.add_theme_color_override("font_color", Color.WHITE)
    _label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
    _label.add_theme_constant_override("shadow_offset_x", 1)
    _label.add_theme_constant_override("shadow_offset_y", 1)
    add_child(_label)
    _layout_label()


func configure(action_name: String, kind: String, accent: Color) -> void:
    _action_name = action_name
    _kind = kind
    _accent = accent
    name = "NitroButton" if kind == "nitro" else "DriftButton"
    if _label != null:
        _label.text = "N₂O" if kind == "nitro" else ""
    _layout_label()
    queue_redraw()


func set_charge_ratio(value: float) -> void:
    var next := clampf(value, 0.0, 1.0)
    if absf(next - _charge_ratio) > 0.004:
        _charge_ratio = next
        if _label != null and _kind == "nitro":
            _label.add_theme_color_override("font_color", Color.WHITE if _charge_ratio > 0.03 else Color(0.62, 0.66, 0.70))
        queue_redraw()


func is_held() -> bool:
    return _drag_index != NO_DRAG


func force_release() -> void:
    if _drag_index != NO_DRAG:
        _drag_index = NO_DRAG
        pressed_changed.emit(_action_name, false)
    queue_redraw()


func get_smoke_state() -> Dictionary:
    return {
        "round_action_0233": true,
        "action": _action_name,
        "kind": _kind,
        "held": is_held(),
        "charge_ratio": _charge_ratio,
        "rect": get_global_rect(),
    }


func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        _layout_label()
        queue_redraw()


func _layout_label() -> void:
    if _label == null:
        return
    _label.position = Vector2.ZERO
    _label.size = size
    _label.add_theme_font_size_override("font_size", int(clampf(minf(size.x, size.y) * 0.24, 16.0, 30.0)))


func _begin(index: int) -> void:
    _drag_index = index
    pressed_changed.emit(_action_name, true)
    accept_event()
    queue_redraw()


func _end(index: int) -> void:
    if index != _drag_index:
        return
    _drag_index = NO_DRAG
    pressed_changed.emit(_action_name, false)
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


func _draw() -> void:
    if size.x < 20.0 or size.y < 20.0:
        return
    var centre := size * 0.5
    var radius := minf(size.x, size.y) * (0.455 if is_held() else 0.485)
    var empty := _kind == "nitro" and _charge_ratio <= 0.03
    var fill := Color(0.16, 0.17, 0.18, 0.48) if empty else Color(0.008, 0.018, 0.034, 0.55 if is_held() else 0.48)
    draw_circle(centre, radius, fill)
    draw_arc(centre, radius, 0.0, TAU, 80, Color(0.55, 0.58, 0.62, 0.72) if empty else Color(_accent, 0.72), 2.0, true)

    if _kind == "nitro":
        draw_arc(centre, radius * 0.90, -PI * 0.5, PI * 1.5, 80, Color(0.45, 0.58, 0.68, 0.34), maxf(radius * 0.10, 4.0), true)
        if _charge_ratio > 0.001:
            var ring_color := Color(0.10, 0.72, 1.0, 0.98 if is_held() else 0.78)
            draw_arc(centre, radius * 0.90, -PI * 0.5, -PI * 0.5 + TAU * _charge_ratio, 80, ring_color, maxf(radius * 0.11, 4.0), true)
        if is_held() and not empty:
            draw_arc(centre, radius * 0.76, 0.0, TAU, 64, Color(0.35, 0.88, 1.0, 0.65), 2.0, true)
    else:
        if is_held():
            draw_arc(centre, radius * 0.84, 0.0, TAU, 72, Color(1.0, 0.52, 0.06, 0.95), maxf(radius * 0.10, 4.0), true)
        var icon_color := Color(1.0, 0.62, 0.12, 1.0) if is_held() else Color(0.94, 0.97, 1.0, 0.96)
        var base_y := centre.y + radius * 0.34
        draw_line(centre + Vector2(-radius * 0.38, radius * 0.34), centre + Vector2(radius * 0.38, radius * 0.34), icon_color, 4.0, true)
        draw_line(Vector2(centre.x - radius * 0.08, base_y), centre + Vector2(radius * 0.28, -radius * 0.30), icon_color, 6.0, true)
        draw_circle(centre + Vector2(radius * 0.31, -radius * 0.34), radius * 0.11, icon_color)
        draw_arc(centre + Vector2(-radius * 0.08, radius * 0.34), radius * 0.18, -PI * 0.45, PI * 0.55, 24, icon_color, 2.4, true)
