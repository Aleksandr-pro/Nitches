class_name NativeAvatarIcon
extends Control
## Drawn driver avatar used instead of a coloured placeholder square.

func _init() -> void:
	custom_minimum_size = Vector2(72.0, 72.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.08, 0.13, 0.19, 1.0)
	background.border_color = Color(1.0, 0.62, 0.10, 0.95)
	background.set_border_width_all(2)
	background.set_corner_radius_all(18)
	draw_style_box(background, rect)

	var centre := size * 0.5
	var scale_factor := minf(size.x, size.y) / 72.0
	# Back glow and a small horizon line keep the mark readable at phone size.
	draw_circle(centre + Vector2(0.0, 2.0 * scale_factor), 27.0 * scale_factor, Color(0.12, 0.33, 0.52, 0.55))
	draw_line(Vector2(10.0 * scale_factor, size.y - 13.0 * scale_factor), Vector2(size.x - 10.0 * scale_factor, size.y - 13.0 * scale_factor), Color(1.0, 0.62, 0.10, 0.75), 2.0 * scale_factor, true)
	# Head and shoulders.
	draw_circle(centre + Vector2(0.0, -10.0 * scale_factor), 11.0 * scale_factor, Color(0.94, 0.97, 1.0, 0.96))
	draw_circle(centre + Vector2(0.0, 25.0 * scale_factor), 19.0 * scale_factor, Color(0.94, 0.97, 1.0, 0.96))
	# Steering-wheel hint in front of the driver.
	var wheel_centre := centre + Vector2(0.0, 15.0 * scale_factor)
	draw_arc(wheel_centre, 15.0 * scale_factor, 0.0, TAU, 40, Color(0.04, 0.07, 0.10, 0.95), 3.0 * scale_factor, true)
	draw_line(wheel_centre + Vector2(-11.0, 4.0) * scale_factor, wheel_centre + Vector2(11.0, 4.0) * scale_factor, Color(0.04, 0.07, 0.10, 0.95), 2.4 * scale_factor, true)
	draw_line(wheel_centre, wheel_centre + Vector2(0.0, 12.0) * scale_factor, Color(0.04, 0.07, 0.10, 0.95), 2.4 * scale_factor, true)
	draw_circle(wheel_centre, 3.2 * scale_factor, Color(1.0, 0.62, 0.10, 1.0))
