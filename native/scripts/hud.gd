class_name NativeHud
extends CanvasLayer

## Native Godot HUD: speed, district, nitro, performance data and
## phone-friendly driving controls.  It talks to the vehicle through its
## public GDScript API only.

signal camera_requested
signal time_requested
signal reset_requested

const MinimapScript := preload("res://scripts/minimap.gd")

var _world: NativeWorldBuilder
var _vehicle: NativeVehicle
var _minimap: NativeMinimap
var _district_label: Label
var _objective_label: Label
var _performance_label: Label
var _speed_label: Label
var _gear_label: Label
var _state_label: Label
var _nitro_bar: ProgressBar
var _refresh_timer := 0.0


func _ready() -> void:
	layer = 10
	_build_ui()


func bind(world: NativeWorldBuilder, vehicle: NativeVehicle) -> void:
	_world = world
	_vehicle = vehicle
	if _minimap != null:
		_minimap.bind(world, vehicle)
	_update_static_labels()


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.008, 0.018, 0.032, 0.66)
	style.border_color = Color(1.0, 0.58, 0.10, 0.66)
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	return style


func _make_panel(parent: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style())
	parent.add_child(panel)
	return panel


func _make_label(parent: Control, text: String, size: int, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.72))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(label)
	return label


func _button_style(pressed: bool, accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent, 0.58 if pressed else 0.30)
	style.border_color = Color(1.0, 0.68, 0.18, 0.88 if pressed else 0.62)
	style.set_border_width_all(2)
	style.set_corner_radius_all(17)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style


func _make_touch_button(parent: Control, text: String, action_name: String, minimum_size: Vector2, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = minimum_size
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 21)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _button_style(false, accent))
	button.add_theme_stylebox_override("pressed", _button_style(true, accent))
	button.add_theme_stylebox_override("hover", _button_style(true, accent))
	button.button_down.connect(_on_touch_button_down.bind(action_name))
	button.button_up.connect(_on_touch_button_up.bind(action_name))
	parent.add_child(button)
	return button


func _make_action_button(parent: Control, text: String, minimum_size: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = minimum_size
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _button_style(false, Color(0.02, 0.20, 0.34)))
	button.add_theme_stylebox_override("pressed", _button_style(true, Color(0.75, 0.28, 0.03)))
	button.add_theme_stylebox_override("hover", _button_style(true, Color(0.05, 0.30, 0.45)))
	parent.add_child(button)
	return button


func _build_ui() -> void:
	var root := Control.new()
	root.name = "HudRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# District and objective, top-left.
	var info_panel := _make_panel(root)
	info_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	info_panel.position = Vector2(14.0, 12.0)
	info_panel.custom_minimum_size = Vector2(292.0, 0.0)
	var info_box := VBoxContainer.new()
	info_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_box.add_theme_constant_override("separation", 2)
	info_panel.add_child(info_box)
	var title := _make_label(info_box, "NITCHES HORIZON • NATIVE", 19, Color(1.0, 0.69, 0.18))
	title.add_theme_font_size_override("font_size", 19)
	_district_label = _make_label(info_box, "RICHTOWN", 23)
	_objective_label = _make_label(info_box, "СВОБОДНАЯ ПОЕЗДКА • ТЕСТ ФИЗИКИ", 14, Color(0.78, 0.90, 1.0))

	# Minimap, performance and small actions, top-right.
	var right_column := VBoxContainer.new()
	right_column.name = "RightColumn"
	right_column.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right_column.position = Vector2(-222.0, 12.0)
	right_column.custom_minimum_size = Vector2(208.0, 0.0)
	right_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_column.add_theme_constant_override("separation", 7)
	root.add_child(right_column)

	var minimap_panel := _make_panel(right_column)
	_minimap = MinimapScript.new() as NativeMinimap
	minimap_panel.add_child(_minimap)

	var performance_panel := _make_panel(right_column)
	_performance_label = _make_label(performance_panel, "FPS —", 13, Color(0.78, 0.96, 0.84))
	_performance_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var action_row := HBoxContainer.new()
	action_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_row.add_theme_constant_override("separation", 6)
	right_column.add_child(action_row)
	var camera_button := _make_action_button(action_row, "CAM", Vector2(62.0, 44.0))
	camera_button.pressed.connect(func() -> void: camera_requested.emit())
	var time_button := _make_action_button(action_row, "TIME", Vector2(62.0, 44.0))
	time_button.pressed.connect(func() -> void: time_requested.emit())
	var reset_button := _make_action_button(action_row, "RESET", Vector2(72.0, 44.0))
	reset_button.pressed.connect(func() -> void: reset_requested.emit())

	# Steering, bottom-left.
	var steering_row := HBoxContainer.new()
	steering_row.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	steering_row.position = Vector2(16.0, -104.0)
	steering_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	steering_row.add_theme_constant_override("separation", 10)
	root.add_child(steering_row)
	_make_touch_button(steering_row, "◀", "steer_left", Vector2(92.0, 82.0), Color(0.02, 0.22, 0.40))
	_make_touch_button(steering_row, "▶", "steer_right", Vector2(92.0, 82.0), Color(0.02, 0.22, 0.40))

	# Speed and nitro above the pedals.
	var speed_panel := _make_panel(root)
	speed_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	speed_panel.position = Vector2(-356.0, -218.0)
	speed_panel.custom_minimum_size = Vector2(340.0, 96.0)
	var speed_box := VBoxContainer.new()
	speed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speed_box.add_theme_constant_override("separation", 1)
	speed_panel.add_child(speed_box)
	var speed_row := HBoxContainer.new()
	speed_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speed_row.add_theme_constant_override("separation", 10)
	speed_box.add_child(speed_row)
	_speed_label = _make_label(speed_row, "0", 48)
	_make_label(speed_row, "км/ч", 17, Color(0.78, 0.88, 1.0))
	_gear_label = _make_label(speed_row, "N", 34, Color(1.0, 0.68, 0.18))
	_state_label = _make_label(speed_row, "", 15, Color(0.55, 0.96, 1.0))
	_nitro_bar = ProgressBar.new()
	_nitro_bar.custom_minimum_size = Vector2(310.0, 11.0)
	_nitro_bar.min_value = 0.0
	_nitro_bar.max_value = 100.0
	_nitro_bar.value = 72.0
	_nitro_bar.show_percentage = false
	_nitro_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nitro_background := StyleBoxFlat.new()
	nitro_background.bg_color = Color(0.02, 0.05, 0.08, 0.78)
	nitro_background.set_corner_radius_all(6)
	var nitro_fill := StyleBoxFlat.new()
	nitro_fill.bg_color = Color(0.10, 0.78, 1.0, 0.94)
	nitro_fill.set_corner_radius_all(6)
	_nitro_bar.add_theme_stylebox_override("background", nitro_background)
	_nitro_bar.add_theme_stylebox_override("fill", nitro_fill)
	speed_box.add_child(_nitro_bar)

	# Pedals, bottom-right.
	var pedal_row := HBoxContainer.new()
	pedal_row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	pedal_row.position = Vector2(-356.0, -104.0)
	pedal_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pedal_row.add_theme_constant_override("separation", 8)
	root.add_child(pedal_row)
	_make_touch_button(pedal_row, "ТОРМОЗ", "brake_reverse", Vector2(88.0, 82.0), Color(0.55, 0.06, 0.05))
	_make_touch_button(pedal_row, "ДРИФТ", "handbrake", Vector2(76.0, 82.0), Color(0.48, 0.22, 0.03))
	_make_touch_button(pedal_row, "N₂O", "boost", Vector2(70.0, 82.0), Color(0.02, 0.45, 0.68))
	_make_touch_button(pedal_row, "ГАЗ", "accelerate", Vector2(92.0, 82.0), Color(0.04, 0.48, 0.18))


func _update_static_labels() -> void:
	if _objective_label != null:
		_objective_label.text = "СВОБОДНАЯ ПОЕЗДКА • ТЕСТ ФИЗИКИ"


func _on_touch_button_down(action_name: String) -> void:
	if _vehicle != null:
		_vehicle.set_touch_input(action_name, true)


func _on_touch_button_up(action_name: String) -> void:
	if _vehicle != null:
		_vehicle.set_touch_input(action_name, false)


func _process(delta: float) -> void:
	if _vehicle == null:
		return

	_speed_label.text = str(int(round(_vehicle.get_absolute_speed_kmh())))
	_gear_label.text = _vehicle.get_gear_label()
	_nitro_bar.value = _vehicle.get_nitro_ratio() * 100.0
	if _vehicle.is_boosting():
		_state_label.text = "НИТРО"
	elif _vehicle.is_drifting():
		_state_label.text = "ДРИФТ %d°" % int(round(_vehicle.get_drift_angle_degrees()))
	else:
		_state_label.text = ""

	_refresh_timer += delta
	if _refresh_timer < 0.14:
		return
	_refresh_timer = 0.0

	if _world != null:
		_district_label.text = _world.get_district_name(_vehicle.global_position).to_upper()
	if _minimap != null:
		_minimap.refresh()

	var draw_calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var primitives := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var process_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_performance_label.text = "FPS %d  •  DRAW %d\nTRIS %s  •  CPU %.1f ms\nPHYS %.1f ms  •  %s" % [
		Engine.get_frames_per_second(),
		draw_calls,
		_format_count(primitives),
		process_ms,
		physics_ms,
		_current_time_label(),
	]


func _format_count(value: int) -> String:
	if value >= 1_000_000:
		return "%.2fM" % (float(value) / 1_000_000.0)
	if value >= 1_000:
		return "%.1fK" % (float(value) / 1_000.0)
	return str(value)


func _current_time_label() -> String:
	if _world == null:
		return "ДЕНЬ"
	match _world.time_of_day:
		"sunset":
			return "ЗАКАТ"
		"night":
			return "НОЧЬ"
		_:
			return "ДЕНЬ"
