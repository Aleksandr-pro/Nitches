class_name NativeCarSilhouetteIcon
extends Control

## Small vector Shelby/fastback pictogram used instead of the old
## red square in the 0.2.34 menu.  It is drawn entirely with
## CanvasItem primitives, so it stays crisp at phone and desktop
## resolutions and can follow the player's chosen paint colour.

var _paint_color := Color(0.48, 0.025, 0.035)
var _wheel_color := Color(0.72, 0.75, 0.78)


func _ready() -> void:
    name = "CarSilhouetteIcon"
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    custom_minimum_size = Vector2(56.0, 32.0)


func set_paint_color(color: Color) -> void:
    _paint_color = color
    queue_redraw()


func set_wheel_color(color: Color) -> void:
    _wheel_color = color
    queue_redraw()


func get_smoke_state() -> Dictionary:
    return {
        "car_silhouette_icon_0234": true,
        "paint_color": _paint_color,
        "rect": get_global_rect(),
    }


func _point(x: float, y: float) -> Vector2:
    return Vector2(size.x * x, size.y * y)


func _draw() -> void:
    if size.x < 16.0 or size.y < 10.0:
        return
    var body := PackedVector2Array([
        _point(0.025, 0.64), _point(0.055, 0.52), _point(0.18, 0.48),
        _point(0.30, 0.45), _point(0.38, 0.30), _point(0.48, 0.22),
        _point(0.63, 0.24), _point(0.72, 0.42), _point(0.80, 0.48),
        _point(0.94, 0.53), _point(0.985, 0.62), _point(0.97, 0.72),
        _point(0.87, 0.72), _point(0.83, 0.61), _point(0.75, 0.60),
        _point(0.70, 0.72), _point(0.34, 0.72), _point(0.29, 0.61),
        _point(0.20, 0.60), _point(0.16, 0.72), _point(0.045, 0.72),
    ])
    draw_colored_polygon(body, _paint_color)
    var glass := PackedVector2Array([
        _point(0.41, 0.34), _point(0.49, 0.27), _point(0.61, 0.28),
        _point(0.68, 0.42), _point(0.55, 0.43), _point(0.53, 0.34),
        _point(0.50, 0.43), _point(0.39, 0.43),
    ])
    draw_colored_polygon(glass, Color(0.05, 0.10, 0.14, 0.96))
    draw_line(_point(0.10, 0.57), _point(0.94, 0.57), Color(1.0, 1.0, 1.0, 0.58), maxf(size.y * 0.045, 1.0), true)
    draw_line(_point(0.045, 0.68), _point(0.96, 0.68), Color(0.0, 0.0, 0.0, 0.28), maxf(size.y * 0.05, 1.0), true)
    for centre_x in [0.245, 0.79]:
        var centre := _point(centre_x, 0.70)
        var radius := size.y * 0.17
        draw_circle(centre, radius, Color(0.012, 0.012, 0.014, 1.0))
        draw_circle(centre, radius * 0.56, _wheel_color)
        draw_circle(centre, radius * 0.18, Color(0.03, 0.04, 0.05, 1.0))
