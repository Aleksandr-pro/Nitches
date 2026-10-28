class_name NativeDashboardGauge
extends Control

## Circular speedometer/tachometer for the 0.2.33 HUD.
## The large centre number is speed, the outer arc is engine RPM with
## a permanent red zone, and gear is a separate bold readout.  The R
## readout flashes, while the small lower arc mirrors nitro charge.

var _speed_kmh := 0.0
var _rpm_ratio := 0.08
var _nitro_ratio := 0.72
var _gear := "N"
var _speed_label: Label
var _unit_label: Label
var _gear_label: Label
var _nitro_label: Label
var _abs_label: Label


func _ready() -> void:
    name = "DashboardGauge"
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    clip_contents = false
    _speed_label = _make_label("0", 48, Color.WHITE)
    _unit_label = _make_label("км/ч", 14, Color(0.72, 0.86, 1.0))
    _gear_label = _make_label("N", 30, Color(1.0, 0.68, 0.18))
    _nitro_label = _make_label("N₂O 72%", 11, Color(0.45, 0.86, 1.0))
    _abs_label = _make_label("ABS", 10, Color(0.55, 0.95, 0.68, 0.9))
    _layout_labels()


func _make_label(text: String, font_size: int, color: Color) -> Label:
    var label := Label.new()
    label.text = text
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.78))
    label.add_theme_constant_override("shadow_offset_x", 1)
    label.add_theme_constant_override("shadow_offset_y", 1)
    add_child(label)
    return label


func set_values(speed_kmh: float, gear: String, rpm_ratio: float, nitro_ratio: float) -> void:
    _speed_kmh = maxf(speed_kmh, 0.0)
    _gear = gear
    _rpm_ratio = clampf(rpm_ratio, 0.0, 1.0)
    _nitro_ratio = clampf(nitro_ratio, 0.0, 1.0)
    if _speed_label != null:
        _speed_label.text = str(int(round(_speed_kmh)))
    if _gear_label != null:
        _gear_label.text = _gear
        _gear_label.add_theme_color_override("font_color", Color(1.0, 0.22, 0.12) if _gear == "R" else Color(1.0, 0.68, 0.18))
        _gear_label.modulate.a = 1.0
    if _nitro_label != null:
        _nitro_label.text = "N₂O %d%%" % int(round(_nitro_ratio * 100.0))
        _nitro_label.add_theme_color_override("font_color", Color(0.45, 0.86, 1.0) if _nitro_ratio > 0.03 else Color(0.62, 0.66, 0.70))
    queue_redraw()


func get_speed_text() -> String:
    return _speed_label.text if _speed_label != null else ""


func get_gear_text() -> String:
    return _gear


func get_smoke_state() -> Dictionary:
    return {
        "circular_gauge_0233": true,
        "speed_text": get_speed_text(),
        "gear": _gear,
        "rpm_ratio": _rpm_ratio,
        "nitro_ratio": _nitro_ratio,
        "rect": get_global_rect(),
    }


func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        _layout_labels()
        queue_redraw()


func _layout_labels() -> void:
    if _speed_label == null or size.x < 20.0 or size.y < 20.0:
        return
    var centre := size * 0.5
    var speed_font := int(clampf(size.x * 0.28, 28.0, 64.0))
    var gear_font := int(clampf(size.x * 0.18, 20.0, 42.0))
    _speed_label.add_theme_font_size_override("font_size", speed_font)
    _gear_label.add_theme_font_size_override("font_size", gear_font)
    _unit_label.add_theme_font_size_override("font_size", int(clampf(size.x * 0.085, 10.0, 17.0)))
    _nitro_label.add_theme_font_size_override("font_size", int(clampf(size.x * 0.07, 9.0, 14.0)))
    _abs_label.add_theme_font_size_override("font_size", int(clampf(size.x * 0.062, 8.0, 12.0)))

    _speed_label.position = centre + Vector2(-size.x * 0.36, -size.y * 0.27)
    _speed_label.size = Vector2(size.x * 0.58, size.y * 0.34)
    _gear_label.position = centre + Vector2(size.x * 0.20, -size.y * 0.25)
    _gear_label.size = Vector2(size.x * 0.20, size.y * 0.30)
    _unit_label.position = centre + Vector2(-size.x * 0.27, size.y * 0.035)
    _unit_label.size = Vector2(size.x * 0.40, size.y * 0.14)
    _nitro_label.position = centre + Vector2(-size.x * 0.28, size.y * 0.20)
    _nitro_label.size = Vector2(size.x * 0.56, size.y * 0.13)
    _abs_label.position = centre + Vector2(-size.x * 0.36, size.y * 0.20)
    _abs_label.size = Vector2(size.x * 0.18, size.y * 0.13)


func _process(_delta: float) -> void:
    if _gear_label == null:
        return
    if _gear == "R":
        _gear_label.modulate.a = 1.0 if int(Time.get_ticks_msec() / 260) % 2 == 0 else 0.22
    elif _gear_label.modulate.a != 1.0:
        _gear_label.modulate.a = 1.0


func _direction(angle: float) -> Vector2:
    return Vector2(cos(angle), sin(angle))


func _draw() -> void:
    if size.x < 20.0 or size.y < 20.0:
        return
    var centre := size * 0.5
    var radius := minf(size.x, size.y) * 0.485
    var start := PI * 0.75
    var sweep := PI * 1.5
    var end := start + sweep

    draw_circle(centre, radius, Color(0.006, 0.014, 0.028, 0.52))
    draw_arc(centre, radius, 0.0, TAU, 96, Color(1.0, 0.64, 0.16, 0.72), 1.6, true)
    draw_arc(centre, radius * 0.91, start, end, 96, Color(0.72, 0.80, 0.88, 0.34), maxf(radius * 0.09, 5.0), true)
    draw_arc(centre, radius * 0.91, start + sweep * 0.82, end, 32, Color(1.0, 0.10, 0.08, 0.88), maxf(radius * 0.095, 5.0), true)

    for i in 11:
        var t := float(i) / 10.0
        var angle := start + sweep * t
        var outer := centre + _direction(angle) * radius * 0.98
        var inner := centre + _direction(angle) * radius * (0.84 if i % 5 == 0 else 0.88)
        draw_line(inner, outer, Color(1.0, 0.18, 0.10, 0.95) if t >= 0.82 else Color(0.88, 0.94, 1.0, 0.72), 1.5, true)

    if _rpm_ratio > 0.001:
        var rpm_color := Color(1.0, 0.58, 0.10, 0.96)
        if _rpm_ratio >= 0.82:
            rpm_color = Color(1.0, 0.12, 0.08, 0.98)
        draw_arc(centre, radius * 0.91, start, start + sweep * _rpm_ratio, 96, rpm_color, maxf(radius * 0.095, 5.0), true)

    var nitro_start := PI * 0.18
    var nitro_sweep := PI * 0.64
    draw_arc(centre, radius * 0.68, nitro_start, nitro_start + nitro_sweep, 48, Color(0.42, 0.58, 0.68, 0.30), 3.0, true)
    if _nitro_ratio > 0.001:
        draw_arc(centre, radius * 0.68, nitro_start, nitro_start + nitro_sweep * _nitro_ratio, 48, Color(0.12, 0.78, 1.0, 0.95), 3.2, true)
