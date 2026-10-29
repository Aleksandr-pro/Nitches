class_name NativeLockIcon
extends Control
## Small vector lock used beside explicit world-unlock conditions.

func _init() -> void:
	custom_minimum_size = Vector2(28.0, 28.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var scale_factor := minf(size.x, size.y) / 28.0
	var centre_x := size.x * 0.5
	var shackle_centre := Vector2(centre_x, 11.0 * scale_factor)
	draw_arc(shackle_centre, 6.5 * scale_factor, PI, TAU, 24, Color(0.88, 0.93, 1.0, 0.95), 3.0 * scale_factor, true)
	var body := Rect2(Vector2(centre_x - 9.0 * scale_factor, 11.0 * scale_factor), Vector2(18.0, 13.0) * scale_factor)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.62, 0.10, 0.96)
	style.set_corner_radius_all(maxi(2, int(round(3.0 * scale_factor))))
	draw_style_box(style, body)
	draw_circle(Vector2(centre_x, 16.5 * scale_factor), 2.2 * scale_factor, Color(0.05, 0.06, 0.08, 1.0))
	draw_line(Vector2(centre_x, 17.5 * scale_factor), Vector2(centre_x, 21.0 * scale_factor), Color(0.05, 0.06, 0.08, 1.0), 2.2 * scale_factor, true)
