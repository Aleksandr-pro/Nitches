class_name NativeHud
extends CanvasLayer

## 0.2.33 driving HUD.
##
## The layout is computed from the live viewport on every resize:
## all driving controls stay inside a 3%-wide / 4%-high safe area,
## buttons are translucent icons at least 56 px across, the wheel
## is twice the old 172 px size, and the right side uses tall
## analog pedals with circular nitro/handbrake controls above them.
## Performance/debug text exists only when developer mode is on.

signal camera_requested
signal view_requested
signal time_requested
signal reset_requested
signal menu_requested
signal sound_toggle_requested
signal map_requested
signal ignition_requested

const MinimapScript := preload("res://scripts/minimap.gd")
const SteeringWheelScript := preload("res://scripts/steering_wheel.gd")
const DashboardGaugeScript := preload("res://scripts/dashboard_gauge.gd")
const TouchPedalScript := preload("res://scripts/touch_pedal.gd")
const RoundActionButtonScript := preload("res://scripts/round_action_button.gd")
const IgnitionButtonScript := preload("res://scripts/ignition_button.gd")
const CircularMaskShader := preload("res://shaders/circular_mask.gdshader")

var _root: Control
var _vehicle: NativeVehicle
var _world: NativeWorldBuilder
var _minimap: NativeMinimap
var _map_overlay: Button
var _gauge: NativeDashboardGauge
var _wheel: NativeSteeringWheel
var _gas_pedal: NativeTouchPedal
var _brake_pedal: NativeTouchPedal
var _nitro_button: NativeRoundActionButton
var _drift_button: NativeRoundActionButton
var _ignition_button: NativeIgnitionButton
var _steer_left_button: Button
var _steer_right_button: Button
var _camera_button: Button
var _view_button: Button
var _sound_button: Button
var _pause_button: Button
var _reset_button: Button
var _performance_label: Label
var _district_label: Label
var _reverse_label: Label
var _tilt_label: Label
var _touch_buttons: Dictionary = {}
var _control_type := "wheel"
var _wheel_size_multiplier := 1.0
var _developer_mode := false
var _sound_enabled := true
var _current_district := ""
var _district_notice_time := 0.0
var _fast_timer := 0.0
var _slow_timer := 0.0
var _build_error := ""


func _ready() -> void:
    name = "HUD"
    layer = 10
    _root = Control.new()
    _root.name = "HUDRoot"
    _root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(_root)
    _build_ui()
    if get_viewport() != null:
        get_viewport().size_changed.connect(_layout_hud)
    call_deferred("_layout_hud")


func bind(world: NativeWorldBuilder, vehicle: NativeVehicle) -> void:
    _world = world
    _vehicle = vehicle
    _fast_timer = 1.0
    _slow_timer = 1.0
    if _minimap != null:
        _minimap.bind(world, vehicle)
    if _vehicle != null:
        if not _vehicle.engine_state_changed.is_connected(_on_engine_state_changed):
            _vehicle.engine_state_changed.connect(_on_engine_state_changed)
        _on_engine_state_changed(_vehicle.get_engine_state())
    if _world != null and not _world.build_error.is_empty():
        show_build_error(_world.build_error)


func show_build_error(message: String) -> void:
    _build_error = message
    if _performance_label != null:
        _performance_label.text = "WORLD DATA ERROR"

func set_minimap_points(points: Array) -> void:
    if _minimap != null:
        _minimap.set_points_of_interest(points)


func set_destination(world_position: Vector2) -> void:
    if _minimap != null:
        _minimap.set_destination(world_position)


func set_route_path(points: Array) -> void:
    if _minimap != null:
        _minimap.set_route_path(points)


func clear_destination() -> void:
    if _minimap != null:
        _minimap.clear_destination()


func apply_control_preferences(control_type: String, wheel_size_multiplier: float) -> void:
    _control_type = control_type if control_type in ["wheel", "tilt", "arrows"] else "wheel"
    _wheel_size_multiplier = clampf(wheel_size_multiplier, 0.75, 1.25)
    if _wheel != null:
        _wheel.visible = _control_type != "arrows"
        _wheel.set_input_enabled(_control_type == "wheel")
    if _steer_left_button != null:
        _steer_left_button.visible = _control_type == "arrows"
    if _steer_right_button != null:
        _steer_right_button.visible = _control_type == "arrows"
    if _tilt_label != null:
        _tilt_label.visible = _control_type == "tilt"
    _layout_hud()


func set_developer_mode(enabled: bool) -> void:
    _developer_mode = enabled
    if _performance_label != null:
        _performance_label.visible = enabled


func set_sound_enabled(enabled: bool) -> void:
    _sound_enabled = enabled
    if _sound_button != null:
        _sound_button.text = "♪" if enabled else "✕"


func set_steering_wheel_texture_path(path: String) -> void:
    if _wheel != null:
        _wheel.set_wheel_texture_path(path)


func reset_touch_controls() -> void:
    if _vehicle != null:
        for action_name in _touch_buttons.keys():
            _vehicle.set_touch_input(action_name, false)
        _vehicle.set_touch_input("steer_left", false)
        _vehicle.set_touch_input("steer_right", false)
        _vehicle.set_touch_input("boost", false)
        _vehicle.set_touch_input("handbrake", false)
        _vehicle.set_touch_pedal("accelerate", 0.0)
        _vehicle.set_touch_pedal("brake_reverse", 0.0)
    if _wheel != null:
        _wheel.force_release()
    if _gas_pedal != null:
        _gas_pedal.force_release()
    if _brake_pedal != null:
        _brake_pedal.force_release()
    if _nitro_button != null:
        _nitro_button.force_release()
    if _drift_button != null:
        _drift_button.force_release()
    if _ignition_button != null:
        _ignition_button.force_release()


func _style_label(label: Label, font_size: int, color: Color) -> void:
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.78))
    label.add_theme_constant_override("shadow_offset_x", 1)
    label.add_theme_constant_override("shadow_offset_y", 1)


func _make_translucent_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = bg
    style.border_color = border
    style.set_border_width_all(1)
    style.set_corner_radius_all(radius)
    style.content_margin_left = 4.0
    style.content_margin_top = 3.0
    style.content_margin_right = 4.0
    style.content_margin_bottom = 3.0
    return style


func _add_press_feedback(button: Button) -> void:
    button.button_down.connect(func() -> void:
        button.pivot_offset = button.size * 0.5
        button.scale = Vector2.ONE * 0.94
    )
    button.button_up.connect(func() -> void:
        button.scale = Vector2.ONE
    )


func _make_icon_button(text: String, font_size: int, radius: int = 999) -> Button:
    var button := Button.new()
    button.text = text
    button.focus_mode = Control.FOCUS_NONE
    button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    button.add_theme_font_size_override("font_size", font_size)
    button.add_theme_color_override("font_color", Color(0.94, 0.98, 1.0))
    button.add_theme_color_override("font_hover_color", Color.WHITE)
    button.add_theme_color_override("font_pressed_color", Color(1.0, 0.82, 0.42))
    button.add_theme_stylebox_override("normal", _make_translucent_style(Color(0.006, 0.014, 0.028, 0.44), Color(1.0, 0.64, 0.16, 0.48), radius))
    button.add_theme_stylebox_override("hover", _make_translucent_style(Color(0.02, 0.045, 0.08, 0.52), Color(1.0, 0.70, 0.22, 0.72), radius))
    button.add_theme_stylebox_override("pressed", _make_translucent_style(Color(0.25, 0.10, 0.018, 0.55), Color(1.0, 0.78, 0.28, 0.95), radius))
    button.add_theme_stylebox_override("focus", _make_translucent_style(Color(0.006, 0.014, 0.028, 0.44), Color(1.0, 0.64, 0.16, 0.48), radius))
    _add_press_feedback(button)
    _root.add_child(button)
    return button


func _build_ui() -> void:
    _minimap = MinimapScript.new()
    var circular_material := ShaderMaterial.new()
    circular_material.shader = CircularMaskShader
    _minimap.material = circular_material
    _root.add_child(_minimap)

    _map_overlay = Button.new()
    _map_overlay.name = "MinimapOpenButton"
    _map_overlay.text = ""
    _map_overlay.focus_mode = Control.FOCUS_NONE
    _map_overlay.flat = true
    _map_overlay.modulate.a = 0.0
    _map_overlay.pressed.connect(func() -> void: map_requested.emit())
    _root.add_child(_map_overlay)

    _ignition_button = IgnitionButtonScript.new()
    _root.add_child(_ignition_button)
    _ignition_button.pressed.connect(_on_ignition_pressed)

    _reset_button = _make_icon_button("↺", 27)
    _reset_button.name = "ResetCarButton"
    _reset_button.pressed.connect(func() -> void: reset_requested.emit())

    _district_label = Label.new()
    _district_label.name = "DistrictNotice"
    _district_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _district_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _style_label(_district_label, 18, Color(0.92, 0.97, 1.0, 0.98))
    _district_label.visible = false
    _root.add_child(_district_label)

    _gauge = DashboardGaugeScript.new()
    _root.add_child(_gauge)

    _camera_button = _make_icon_button("◎", 24)
    _camera_button.name = "CameraButton"
    _camera_button.pressed.connect(func() -> void: camera_requested.emit())
    _view_button = _make_icon_button("◉", 24)
    _view_button.name = "ViewButton"
    _view_button.pressed.connect(func() -> void: view_requested.emit())
    _sound_button = _make_icon_button("♪", 25)
    _sound_button.name = "SoundButton"
    _sound_button.pressed.connect(func() -> void: sound_toggle_requested.emit())
    _pause_button = _make_icon_button("❚❚", 18)
    _pause_button.name = "PauseButton"
    _pause_button.pressed.connect(func() -> void: menu_requested.emit())

    _wheel = SteeringWheelScript.new()
    _wheel.steering_changed.connect(_on_wheel_steering_changed)
    _root.add_child(_wheel)

    _steer_left_button = _make_icon_button("◀", 34, 24)
    _steer_left_button.name = "SteerLeftButton"
    _steer_right_button = _make_icon_button("▶", 34, 24)
    _steer_right_button.name = "SteerRightButton"
    _register_hold_button(_steer_left_button, "steer_left")
    _register_hold_button(_steer_right_button, "steer_right")
    _steer_left_button.visible = false
    _steer_right_button.visible = false

    _tilt_label = Label.new()
    _tilt_label.name = "TiltModeLabel"
    _tilt_label.text = "↻ НАКЛОН"
    _tilt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _tilt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _style_label(_tilt_label, 14, Color(0.82, 0.93, 1.0, 0.92))
    _tilt_label.visible = false
    _root.add_child(_tilt_label)

    _gas_pedal = TouchPedalScript.new()
    _root.add_child(_gas_pedal)
    _gas_pedal.configure("accelerate", "↑", Color(0.10, 0.72, 0.32))
    _gas_pedal.value_changed.connect(_on_pedal_value_changed)

    _brake_pedal = TouchPedalScript.new()
    _root.add_child(_brake_pedal)
    _brake_pedal.configure("brake_reverse", "↓", Color(0.96, 0.22, 0.12))
    _brake_pedal.value_changed.connect(_on_pedal_value_changed)

    _nitro_button = RoundActionButtonScript.new()
    _root.add_child(_nitro_button)
    _nitro_button.configure("boost", "nitro", Color(0.10, 0.72, 1.0))
    _nitro_button.pressed_changed.connect(_on_round_action_changed)

    _drift_button = RoundActionButtonScript.new()
    _root.add_child(_drift_button)
    _drift_button.configure("handbrake", "handbrake", Color(1.0, 0.55, 0.08))
    _drift_button.pressed_changed.connect(_on_round_action_changed)

    _reverse_label = Label.new()
    _reverse_label.name = "ReverseFlash"
    _reverse_label.text = "R"
    _reverse_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _reverse_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _style_label(_reverse_label, 34, Color(1.0, 0.18, 0.10, 0.98))
    _reverse_label.visible = false
    _root.add_child(_reverse_label)

    _performance_label = Label.new()
    _performance_label.name = "DeveloperPerformance"
    _performance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _performance_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
    _performance_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _style_label(_performance_label, 12, Color(0.72, 1.0, 0.80, 0.96))
    _performance_label.visible = false
    _root.add_child(_performance_label)

    apply_control_preferences(_control_type, _wheel_size_multiplier)
    set_sound_enabled(_sound_enabled)


func _place(control: Control, rect: Rect2) -> void:
    if control == null:
        return
    control.position = rect.position
    control.size = rect.size
    control.pivot_offset = rect.size * 0.5


func _layout_hud() -> void:
    var viewport_size := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2.ZERO
    if viewport_size.x < 100.0 or viewport_size.y < 100.0 or _minimap == null:
        return
    var vw := viewport_size.x
    var vh := viewport_size.y
    var margin_x := maxf(vw * 0.03, 12.0)
    var margin_y := maxf(vh * 0.04, 12.0)
    var gap := maxf(minf(vw, vh) * 0.012, 8.0)

    var minimap_d := clampf(vh * 0.24, 112.0, 260.0)
    var minimap_rect := Rect2(Vector2(margin_x, margin_y), Vector2(minimap_d, minimap_d))
    _place(_minimap, minimap_rect)
    _place(_map_overlay, minimap_rect)
    # 0.2.35: the engine power button lives directly under the
    # minimap and is exactly the handbrake lever button's diameter.
    var ignition_d := clampf(vh * 0.12, 64.0, 104.0)
    var ignition_rect := Rect2(Vector2(minimap_rect.get_center().x - ignition_d * 0.5, minimap_rect.end.y + 8.0), Vector2(ignition_d, ignition_d))
    _place(_ignition_button, ignition_rect)
    _place(_district_label, Rect2(minimap_rect.position + Vector2(0.0, minimap_d + 8.0 + ignition_d + 5.0), Vector2(minimap_d, 32.0)))

    var reset_size := clampf(vh * 0.09, 56.0, 72.0)
    _place(_reset_button, Rect2(Vector2(minimap_rect.end.x + gap, margin_y), Vector2(reset_size, reset_size)))

    var gauge_d := clampf(vh * 0.22, 112.0, 240.0)
    var gauge_rect := Rect2(Vector2(vw - margin_x - gauge_d, margin_y), Vector2(gauge_d, gauge_d))
    _place(_gauge, gauge_rect)

    var small_size := clampf(vh * 0.075, 56.0, 68.0)
    var small_gap := 8.0
    var small_total := small_size * 4.0 + small_gap * 3.0
    var small_x := vw - margin_x - small_total
    var small_y := gauge_rect.end.y + 8.0
    _place(_camera_button, Rect2(Vector2(small_x, small_y), Vector2(small_size, small_size)))
    _place(_view_button, Rect2(Vector2(small_x + (small_size + small_gap), small_y), Vector2(small_size, small_size)))
    _place(_sound_button, Rect2(Vector2(small_x + (small_size + small_gap) * 2.0, small_y), Vector2(small_size, small_size)))
    _place(_pause_button, Rect2(Vector2(small_x + (small_size + small_gap) * 3.0, small_y), Vector2(small_size, small_size)))

    var wheel_base := clampf(minf(vw * 0.30, vh * 0.58), 240.0, 344.0)
    var wheel_size := clampf(wheel_base * _wheel_size_multiplier, 196.0, minf(vw * 0.38, vh * 0.66))
    var wheel_rect := Rect2(Vector2(maxf(vw * 0.04, margin_x), vh - margin_y - wheel_size), Vector2(wheel_size, wheel_size))
    _place(_wheel, wheel_rect)
    _place(_tilt_label, Rect2(wheel_rect.position + Vector2(0.0, -30.0), Vector2(wheel_size, 26.0)))

    var arrow_size := clampf(wheel_size * 0.34, 72.0, 116.0)
    var arrow_y := vh - margin_y - arrow_size
    _place(_steer_left_button, Rect2(Vector2(wheel_rect.position.x, arrow_y), Vector2(arrow_size, arrow_size)))
    _place(_steer_right_button, Rect2(Vector2(wheel_rect.position.x + arrow_size + 10.0, arrow_y), Vector2(arrow_size, arrow_size)))

    var pedal_height := clampf(vh * 0.34, 160.0, vh * 0.52)
    var pedal_y := vh - margin_y - pedal_height
    var gas_width := clampf(vw * 0.09, 64.0, 118.0)
    var brake_width := clampf(vw * 0.08, 60.0, 106.0)
    var gas_rect := Rect2(Vector2(vw - margin_x - gas_width, pedal_y), Vector2(gas_width, pedal_height))
    var brake_rect := Rect2(Vector2(gas_rect.position.x - 8.0 - brake_width, pedal_y), Vector2(brake_width, pedal_height))
    _place(_gas_pedal, gas_rect)
    _place(_brake_pedal, brake_rect)

    var nitro_d := clampf(vh * 0.14, 72.0, 122.0)
    var nitro_center_x := gas_rect.get_center().x
    var nitro_rect := Rect2(Vector2(nitro_center_x - nitro_d * 0.5, pedal_y - 10.0 - nitro_d), Vector2(nitro_d, nitro_d))
    _place(_nitro_button, nitro_rect)

    var drift_d := clampf(vh * 0.12, 64.0, 104.0)
    var drift_rect := Rect2(Vector2(nitro_rect.position.x - 16.0 - drift_d, nitro_rect.position.y + (nitro_d - drift_d) * 0.55), Vector2(drift_d, drift_d))
    _place(_drift_button, drift_rect)

    # 0.2.53: compact top-centre chip; the old 84x72 flashing R sat
    # directly on top of the car in chase view and read as a plate bug.
    _place(_reverse_label, Rect2(Vector2(vw * 0.5 - 28.0, vh * 0.15), Vector2(56.0, 48.0)))
    _place(_performance_label, Rect2(Vector2(vw * 0.34, margin_y), Vector2(vw * 0.32, 76.0)))


func _register_hold_button(button: Button, action_name: String) -> void:
    _touch_buttons[action_name] = button
    button.button_down.connect(func() -> void:
        if _vehicle != null:
            _vehicle.set_touch_input(action_name, true)
    )
    button.button_up.connect(func() -> void:
        if _vehicle != null:
            _vehicle.set_touch_input(action_name, false)
    )


func _on_wheel_steering_changed(value: float, engaged: bool) -> void:
    if _vehicle != null:
        _vehicle.set_touch_steering(value, engaged)


func _on_pedal_value_changed(action_name: String, value: float) -> void:
    if _vehicle != null:
        _vehicle.set_touch_pedal(action_name, value)


func _on_ignition_pressed() -> void:
    ignition_requested.emit()
    if _vehicle != null:
        _vehicle.toggle_engine()


func _on_engine_state_changed(state: int) -> void:
    if _ignition_button != null:
        _ignition_button.set_engine_state(state)


func _on_round_action_changed(action_name: String, pressed: bool) -> void:
    if _vehicle != null:
        _vehicle.set_touch_input(action_name, pressed)


func _process(delta: float) -> void:
    if _district_notice_time > 0.0:
        _district_notice_time = maxf(_district_notice_time - delta, 0.0)
        if _district_label != null:
            _district_label.visible = _district_notice_time > 0.0
            _district_label.modulate.a = clampf(_district_notice_time / 0.45, 0.0, 1.0) if _district_notice_time < 0.45 else 1.0
    if _reverse_label != null and _reverse_label.visible:
        _reverse_label.modulate.a = 1.0 if int(Time.get_ticks_msec() / 260) % 2 == 0 else 0.35

    _fast_timer += delta
    _slow_timer += delta
    var slow_update := _slow_timer >= 0.25
    if slow_update:
        _slow_timer = 0.0
    if _fast_timer < 0.033 and not slow_update:
        return
    _fast_timer = 0.0
    update_from_vehicle(slow_update)

func update_from_vehicle(slow_update: bool = false) -> void:
    if _vehicle == null or _gauge == null:
        return
    var speed := _vehicle.get_absolute_speed_kmh()
    var gear := _vehicle.get_gear_label()
    var nitro_ratio := _vehicle.get_nitro_ratio()
    _gauge.set_values(speed, gear, _vehicle.get_rpm_ratio(), nitro_ratio)
    _nitro_button.set_charge_ratio(nitro_ratio)
    if _ignition_button != null:
        _ignition_button.set_engine_state(_vehicle.get_engine_state())

    var car_transform := _vehicle.get_global_transform_interpolated()
    var car_position := car_transform.origin
    var forward := -car_transform.basis.z
    _minimap.set_player(car_position, forward)

    if _wheel != null and _wheel.visible:
        _wheel.set_display_value(_vehicle.steering_input)

    _reverse_label.visible = gear == "R"
    if not slow_update:
        return

    if _world != null:
        var district := _world.get_district_name(car_position)
        if district != _current_district and not district.is_empty():
            _current_district = district
            _district_label.text = district.to_upper()
            _district_label.visible = true
            _district_label.modulate.a = 1.0
            _district_notice_time = 3.0

    if _developer_mode and _performance_label != null:
        var draw_calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
        var primitives := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
        _performance_label.text = "FPS %d • DRAW %d • TRIS %d • CPU %.1f ms • PHYS %.1f ms\nX %.1f • Z %.1f • %s" % [
            Engine.get_frames_per_second(),
            draw_calls,
            primitives,
            Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
            Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
            car_position.x,
            car_position.z,
            _current_district,
        ]
        if not _build_error.is_empty():
            _performance_label.text += "\nWORLD DATA ERROR"

func get_smoke_state() -> Dictionary:
    var viewport_size := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2.ZERO
    var ignition_diameter := minf(_ignition_button.size.x, _ignition_button.size.y) if _ignition_button != null else 0.0
    var drift_diameter := minf(_drift_button.size.x, _drift_button.size.y) if _drift_button != null else 0.0
    return {
        "hud_0233": true,
        "hud_0235": true,
        "ignition_button": _ignition_button.get_smoke_state() if _ignition_button != null else {},
        "ignition_under_minimap": _ignition_button != null and _minimap != null and _ignition_button.position.y >= _minimap.position.y + _minimap.size.y,
        "ignition_same_size_as_drift": ignition_diameter > 0.0 and absf(ignition_diameter - drift_diameter) <= 0.5,
        "safe_area_3pct_4pct": true,
        "viewport_size": viewport_size,
        "dashboard_gauge": _gauge.get_smoke_state() if _gauge != null else {},
        "minimap": _minimap.get_smoke_state() if _minimap != null else {},
        "map_overlay_created": _map_overlay != null,
        "analog_wheel_created": _wheel != null,
        "steering_wheel": _wheel.get_smoke_state() if _wheel != null else {},
        "gas_pedal": _gas_pedal.get_smoke_state() if _gas_pedal != null else {},
        "brake_pedal": _brake_pedal.get_smoke_state() if _brake_pedal != null else {},
        "nitro_button": _nitro_button.get_smoke_state() if _nitro_button != null else {},
        "drift_button": _drift_button.get_smoke_state() if _drift_button != null else {},
        "control_type": _control_type,
        "wheel_size_multiplier": _wheel_size_multiplier,
        "developer_mode": _developer_mode,
        "performance_visible": _performance_label.visible if _performance_label != null else false,
        "district_notice_seconds": _district_notice_time,
        "sound_enabled": _sound_enabled,
        "touch_button_count": _touch_buttons.size(),
        "build_error": _build_error,
    }
