class_name NativeMainMenu
extends CanvasLayer

## 0.2.29 main menu: the game no longer drops the player straight into
## the world.  A tiled festival-style front end (home / garage /
## profile / store / worlds) floats over a slow cinematic orbit of the
## car; Play hands control to the driving HUD.  All layout is built in
## code from the same Control toolkit as the HUD so phone touch and
## desktop mouse behave identically.

signal play_requested
signal world_map_requested
signal settings_changed(settings: Dictionary)
signal camera_cycle_requested
signal time_cycle_requested

const COL_BG := Color(0.008, 0.20, 0.22, 0.90)
const COL_PANEL := Color(0.03, 0.14, 0.15, 0.97)
const COL_PANEL_LIGHT := Color(0.05, 0.22, 0.23, 0.97)
const COL_TEXT := Color(0.94, 0.98, 0.98)
const COL_MUTED := Color(0.62, 0.78, 0.78)
const COL_TEAL := Color(0.10, 0.72, 0.70)
const COL_YELLOW := Color(0.98, 0.78, 0.10)
const COL_MAGENTA := Color(0.88, 0.16, 0.55)
const COL_LOCKED := Color(0.23, 0.30, 0.30)

var _root: Control
var _built := false
var _panels: Array[Control] = []
var _tab_buttons: Array[Button] = []
var _car_name := ""
var _specs_bound := false
var _profile_bound := false
var _world_map_button: Button
var _settings: Dictionary = {
    "control_type": "wheel",
    "steering_sensitivity": 1.0,
    "steering_dead_zone": 0.03,
    "wheel_size_multiplier": 1.0,
    "sound_enabled": true,
    "developer_mode": false,
    "camera_label": "ВИД СЗАДИ",
    "time_label": "ДЕНЬ",
}
var _settings_bound := false
var _updating_settings := false
var _control_buttons: Dictionary = {}
var _sensitivity_slider: HSlider
var _dead_zone_slider: HSlider
var _wheel_size_slider: HSlider
var _setting_value_labels: Dictionary = {}
var _sound_toggle: Button
var _camera_setting_button: Button
var _time_setting_button: Button
var _developer_status_label: Label
var _version_button: Button
var _version_taps := 0
var _last_version_tap_msec := 0

var _top_car_label: Label
var _top_credits_label: Label
var _top_name_label: Label
var _profile_tile_sub: Label
var _p_name: Label
var _p_level: Label
var _p_credits: Label
var _p_distance: Label
var _p_top: Label
var _p_time: Label


func _ready() -> void:
    layer = 6
    _build_ui()
    _built = true
    hide_menu()


func show_menu() -> void:
    if _root != null:
        _root.visible = true


func show_settings() -> void:
    show_menu()
    _show_panel(5)


func hide_menu() -> void:
    if _root != null:
        _root.visible = false


func is_menu_visible() -> bool:
    return _root != null and _root.visible


func get_smoke_state() -> Dictionary:
    return {
        "created": _built,
        "panels": _panels.size(),
        "tabs": _tab_buttons.size(),
        "car_name": _car_name,
        "specs_bound": _specs_bound,
        "profile_bound": _profile_bound,
        "visible_now": is_menu_visible(),
        "world_map_button": _world_map_button != null,
        "settings_panel_0233": _sensitivity_slider != null and _dead_zone_slider != null and _wheel_size_slider != null,
        "control_buttons": _control_buttons.size(),
        "settings_bound": _settings_bound,
        "version_button_created": _version_button != null,
        "developer_mode": bool(_settings.get("developer_mode", false)),
        "control_type": String(_settings.get("control_type", "wheel")),
    }


# --------------------------------------------------------------------- #
# construction helpers
# --------------------------------------------------------------------- #
func _style(bg: Color, border: Color, radius: int = 10, border_w: int = 0) -> StyleBoxFlat:
    var sb := StyleBoxFlat.new()
    sb.bg_color = bg
    sb.set_corner_radius_all(radius)
    if border_w > 0:
        sb.set_border_width_all(border_w)
        sb.border_color = border
    sb.content_margin_left = 16.0
    sb.content_margin_right = 16.0
    sb.content_margin_top = 10.0
    sb.content_margin_bottom = 10.0
    return sb


func _label(parent: Node, text: String, size: int, color: Color = COL_TEXT) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", size)
    label.add_theme_color_override("font_color", color)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(label)
    return label


func _button(text: String, accent: Color, min_size: Vector2, font_size: int = 22) -> Button:
    var button := Button.new()
    button.text = text
    button.custom_minimum_size = min_size
    button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    button.add_theme_font_size_override("font_size", font_size)
    button.add_theme_color_override("font_color", COL_TEXT)
    button.add_theme_color_override("font_hover_color", COL_TEXT)
    button.add_theme_color_override("font_pressed_color", COL_TEXT)
    button.add_theme_color_override("font_disabled_color", COL_MUTED)
    button.add_theme_stylebox_override("normal", _style(COL_PANEL, accent, 10, 2))
    button.add_theme_stylebox_override("hover", _style(COL_PANEL_LIGHT, accent, 10, 3))
    button.add_theme_stylebox_override("pressed", _style(accent.darkened(0.25), accent, 10, 2))
    button.add_theme_stylebox_override("disabled", _style(COL_PANEL, COL_LOCKED, 10, 2))
    button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
    return button


func _tile(title: String, subtitle: String, accent: Color, min_size: Vector2, font_size: int = 30) -> Button:
    var button := _button(title, accent, min_size, font_size)
    var sub := Label.new()
    sub.text = subtitle
    sub.add_theme_font_size_override("font_size", 15)
    sub.add_theme_color_override("font_color", COL_MUTED)
    sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
    sub.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
    sub.offset_left = 16.0
    sub.offset_top = -34.0
    sub.offset_right = 420.0
    sub.offset_bottom = -10.0
    button.add_child(sub)
    if title == "ПРОФИЛЬ":
        _profile_tile_sub = sub
    return button


func _panel_box(parent: Node) -> PanelContainer:
    var panel := PanelContainer.new()
    panel.add_theme_stylebox_override("panel", _style(COL_PANEL, COL_TEAL.darkened(0.35), 12, 1))
    parent.add_child(panel)
    return panel


func _bar(parent: Node, caption: String, value: float, accent: Color) -> void:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    parent.add_child(row)
    var cap := _label(row, caption, 15, COL_MUTED)
    cap.custom_minimum_size = Vector2(150.0, 0.0)
    var bar := ProgressBar.new()
    bar.min_value = 0.0
    bar.max_value = 10.0
    bar.value = value
    bar.show_percentage = false
    bar.custom_minimum_size = Vector2(0.0, 14.0)
    bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bar.add_theme_stylebox_override("background", _style(Color(0.02, 0.08, 0.09, 0.95), COL_LOCKED, 4, 0))
    bar.add_theme_stylebox_override("fill", _style(accent, accent, 4, 0))
    row.add_child(bar)
    _label(row, "%.1f" % value, 15, COL_TEXT)


func _spec_row(grid: GridContainer, key_text: String, value_text: String) -> void:
    _label(grid, key_text, 16, COL_MUTED)
    _label(grid, value_text, 16, COL_TEXT)


# --------------------------------------------------------------------- #
# layout
# --------------------------------------------------------------------- #
func _build_ui() -> void:
    _root = Control.new()
    _root.name = "MainMenuRoot"
    _root.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(_root)

    var bg := ColorRect.new()
    bg.color = COL_BG
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    _root.add_child(bg)

    var margin := MarginContainer.new()
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_left", 26)
    margin.add_theme_constant_override("margin_right", 26)
    margin.add_theme_constant_override("margin_top", 18)
    margin.add_theme_constant_override("margin_bottom", 16)
    _root.add_child(margin)

    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 12)
    margin.add_child(column)

    _build_top_bar(column)
    _build_tabs(column)

    var panels_root := Control.new()
    panels_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(panels_root)

    _panels.append(_build_home_panel(panels_root))
    _panels.append(_build_garage_panel(panels_root))
    _panels.append(_build_profile_panel(panels_root))
    _panels.append(_build_store_panel(panels_root))
    _panels.append(_build_worlds_panel(panels_root))
    _panels.append(_build_settings_panel(panels_root))
    _show_panel(0)

    _label(column, "ИГРАТЬ — выезд в RichTown   •   Esc или ⏸ в игре — пауза и настройки", 14, COL_MUTED)


func _build_top_bar(parent: Node) -> void:
    var bar := HBoxContainer.new()
    bar.add_theme_constant_override("separation", 14)
    parent.add_child(bar)

    var logo := _label(bar, "NITCHES HORIZON", 30, COL_YELLOW)
    logo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

    var car_chip := _panel_box(bar)
    var car_row := HBoxContainer.new()
    car_row.add_theme_constant_override("separation", 10)
    car_chip.add_child(car_row)
    var swatch := ColorRect.new()
    swatch.color = Color(0.62, 0.05, 0.08)
    swatch.custom_minimum_size = Vector2(44.0, 44.0)
    car_row.add_child(swatch)
    var car_text := VBoxContainer.new()
    car_row.add_child(car_text)
    _top_car_label = _label(car_text, "Shelby GT500 '67", 17, COL_TEXT)
    _label(car_text, "365 л.с. • 569 Нм • ~207 км/ч", 13, COL_MUTED)

    var spacer := Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bar.add_child(spacer)

    var profile_chip := _panel_box(bar)
    var profile_row := HBoxContainer.new()
    profile_row.add_theme_constant_override("separation", 10)
    profile_chip.add_child(profile_row)
    var avatar := PanelContainer.new()
    avatar.custom_minimum_size = Vector2(44.0, 44.0)
    avatar.add_theme_stylebox_override("panel", _style(COL_MAGENTA, COL_MAGENTA, 8, 0))
    profile_row.add_child(avatar)
    var initial := _label(avatar, "N", 22, COL_TEXT)
    initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    var profile_text := VBoxContainer.new()
    profile_row.add_child(profile_text)
    _top_name_label = _label(profile_text, "ИГРОК • ур. 1", 16, COL_TEXT)
    _top_credits_label = _label(profile_text, "CR 35 000", 14, COL_YELLOW)


func _build_tabs(parent: Node) -> void:
    var tabs := HBoxContainer.new()
    tabs.add_theme_constant_override("separation", 8)
    parent.add_child(tabs)
    var group := ButtonGroup.new()
    var names := ["ГЛАВНАЯ", "ГАРАЖ", "ПРОФИЛЬ", "МАГАЗИН", "КАРТЫ И МИРЫ", "НАСТРОЙКИ"]
    for i in names.size():
        var tab := _button(names[i], COL_TEAL, Vector2(0.0, 46.0), 17)
        tab.alignment = HORIZONTAL_ALIGNMENT_CENTER
        tab.toggle_mode = true
        tab.button_group = group
        tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        tab.pressed.connect(_show_panel.bind(i))
        tabs.add_child(tab)
        _tab_buttons.append(tab)
    _tab_buttons[0].button_pressed = true


func _show_panel(index: int) -> void:
    for i in _panels.size():
        _panels[i].visible = i == index
    if index >= 0 and index < _tab_buttons.size() and not _tab_buttons[index].button_pressed:
        _tab_buttons[index].button_pressed = true


func _new_panel(parent: Node) -> VBoxContainer:
    var panel := PanelContainer.new()
    panel.set_anchors_preset(Control.PRESET_FULL_RECT)
    panel.add_theme_stylebox_override("panel", _style(Color(0.02, 0.11, 0.12, 0.65), COL_TEAL.darkened(0.45), 12, 1))
    parent.add_child(panel)
    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 18)
    margin.add_theme_constant_override("margin_right", 18)
    margin.add_theme_constant_override("margin_top", 14)
    margin.add_theme_constant_override("margin_bottom", 14)
    panel.add_child(margin)
    var vbox := VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 12)
    margin.add_child(vbox)
    return vbox


func _build_home_panel(parent: Node) -> Control:
    var vbox := _new_panel(parent)

    var row1 := HBoxContainer.new()
    row1.add_theme_constant_override("separation", 12)
    row1.size_flags_vertical = Control.SIZE_EXPAND_FILL
    vbox.add_child(row1)
    var play := _tile("ИГРАТЬ", "RichTown • свободная езда • день/закат/ночь", COL_YELLOW, Vector2(0.0, 170.0), 44)
    play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    play.size_flags_stretch_ratio = 2.0
    play.pressed.connect(func() -> void: play_requested.emit())
    row1.add_child(play)
    var garage := _tile("ГАРАЖ", "1 автомобиль • Shelby GT500", COL_MAGENTA, Vector2(0.0, 170.0), 30)
    garage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    garage.pressed.connect(_show_panel.bind(1))
    row1.add_child(garage)

    var row2 := HBoxContainer.new()
    row2.add_theme_constant_override("separation", 12)
    row2.size_flags_vertical = Control.SIZE_EXPAND_FILL
    vbox.add_child(row2)
    var profile := _tile("ПРОФИЛЬ", "ур. 1 • CR 35 000", COL_TEAL, Vector2(0.0, 130.0), 26)
    profile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    profile.pressed.connect(_show_panel.bind(2))
    row2.add_child(profile)
    var store := _tile("МАГАЗИН", "скоро открытие", COL_TEAL.darkened(0.2), Vector2(0.0, 130.0), 26)
    store.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    store.pressed.connect(_show_panel.bind(3))
    row2.add_child(store)
    var worlds := _tile("КАРТЫ И МИРЫ", "RichTown доступен", COL_TEAL, Vector2(0.0, 130.0), 26)
    worlds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    worlds.pressed.connect(_show_panel.bind(4))
    row2.add_child(worlds)
    return vbox.get_parent().get_parent() as Control


func _build_garage_panel(parent: Node) -> Control:
    var vbox := _new_panel(parent)
    _label(vbox, "ГАРАЖ", 28, COL_TEXT)
    var columns := HBoxContainer.new()
    columns.add_theme_constant_override("separation", 18)
    columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
    vbox.add_child(columns)

    var left := VBoxContainer.new()
    left.add_theme_constant_override("separation", 8)
    left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    left.size_flags_stretch_ratio = 1.55
    columns.add_child(left)
    _label(left, "Shelby GT500 (1967)", 30, COL_YELLOW)
    _label(left, "КЛАСС A • ИНДЕКС 612 • МАСЛКАР", 15, COL_MAGENTA)
    var grid := GridContainer.new()
    grid.columns = 2
    grid.add_theme_constant_override("h_separation", 18)
    grid.add_theme_constant_override("v_separation", 4)
    left.add_child(grid)
    _spec_row(grid, "Двигатель", "V8, 7.0 л (428 cid)")
    _spec_row(grid, "Мощность", "365 л.с. (SAE gross)")
    _spec_row(grid, "Крутящий момент", "569 Нм при 3200 об/мин")
    _spec_row(grid, "Разгон 0–100 км/ч", "6.0 с")
    _spec_row(grid, "Макс. скорость", "~207 км/ч")
    _spec_row(grid, "Коробка передач", "4-ступенчатая механика")
    _spec_row(grid, "Привод", "задний")
    _label(left, "", 8)
    _bar(left, "Скорость", 6.4, COL_TEAL)
    _bar(left, "Разгон", 6.8, COL_YELLOW)
    _bar(left, "Управление", 5.2, COL_MAGENTA)
    _bar(left, "Дрифт", 7.5, Color(0.95, 0.45, 0.15))

    var right := VBoxContainer.new()
    right.add_theme_constant_override("separation", 10)
    right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    columns.add_child(right)
    _label(right, "МОИ АВТОМОБИЛИ (1)", 18, COL_TEXT)
    var owned := _button("Shelby GT500 '67 — выбран", COL_YELLOW, Vector2(0.0, 64.0), 18)
    owned.disabled = true
    right.add_child(owned)
    var change := _button("СМЕНИТЬ АВТО", COL_LOCKED, Vector2(0.0, 54.0), 17)
    change.disabled = true
    right.add_child(change)
    _label(right, "Новые автомобили появятся в магазине.", 14, COL_MUTED)
    var spacer := Control.new()
    spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
    right.add_child(spacer)
    var drive := _button("ИГРАТЬ НА ЭТОМ АВТО", COL_MAGENTA, Vector2(0.0, 62.0), 20)
    drive.alignment = HORIZONTAL_ALIGNMENT_CENTER
    drive.pressed.connect(func() -> void: play_requested.emit())
    right.add_child(drive)
    return vbox.get_parent().get_parent() as Control


func _build_profile_panel(parent: Node) -> Control:
    var vbox := _new_panel(parent)
    _label(vbox, "ПРОФИЛЬ ВОДИТЕЛЯ", 28, COL_TEXT)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 20)
    vbox.add_child(row)
    var avatar := PanelContainer.new()
    avatar.custom_minimum_size = Vector2(150.0, 150.0)
    avatar.add_theme_stylebox_override("panel", _style(COL_MAGENTA, COL_MAGENTA, 14, 0))
    row.add_child(avatar)
    var initial := _label(avatar, "N", 64, COL_TEXT)
    initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    var stats := VBoxContainer.new()
    stats.add_theme_constant_override("separation", 6)
    row.add_child(stats)
    _p_name = _label(stats, "ИГРОК", 26, COL_YELLOW)
    _p_level = _label(stats, "Уровень: 1", 18, COL_TEXT)
    _p_credits = _label(stats, "Кредиты: CR 35 000", 18, COL_TEXT)
    _p_distance = _label(stats, "Пробег: 0.0 км", 18, COL_TEXT)
    _p_top = _label(stats, "Рекорд скорости: 0 км/ч", 18, COL_TEXT)
    _p_time = _label(stats, "Время за рулём: 0 мин", 18, COL_TEXT)
    _label(stats, "Автомобилей в гараже: 1", 18, COL_TEXT)
    _label(vbox, "Прогресс сохраняется автоматически: пробег, рекорды и кредиты переживут перезапуск.", 14, COL_MUTED)
    return vbox.get_parent().get_parent() as Control


func _build_store_panel(parent: Node) -> Control:
    var vbox := _new_panel(parent)
    _label(vbox, "МАГАЗИН", 28, COL_TEXT)
    _label(vbox, "Скоро открытие. Автомобили, тюнинг и винилы уже в пути в RichTown.", 17, COL_MUTED)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    vbox.add_child(row)
    for caption in ["АВТОМОБИЛИ", "ТЮНИНГ", "ВИНИЛЫ"]:
        var locked := _tile(caption, "закрыто • скоро", COL_LOCKED, Vector2(0.0, 130.0), 24)
        locked.disabled = true
        locked.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(locked)
    return vbox.get_parent().get_parent() as Control


func _build_worlds_panel(parent: Node) -> Control:
    var vbox := _new_panel(parent)
    _label(vbox, "КАРТЫ И МИРЫ", 28, COL_TEXT)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    row.size_flags_vertical = Control.SIZE_EXPAND_FILL
    vbox.add_child(row)
    var richtown := _tile("RICHTOWN", "открытый город • побережье • остров-Пальма", COL_YELLOW, Vector2(0.0, 160.0), 30)
    richtown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    richtown.size_flags_stretch_ratio = 1.4
    richtown.pressed.connect(func() -> void: play_requested.emit())
    row.add_child(richtown)
    for caption in ["СЕВЕРНЫЕ ГОРЫ", "ПУСТЫННЫЙ КАНЬОН"]:
        var locked := _tile(caption, "закрыто • скоро", COL_LOCKED, Vector2(0.0, 160.0), 24)
        locked.disabled = true
        locked.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(locked)
    _world_map_button = _button("ОТКРЫТЬ КАРТУ RICHTOWN", COL_TEAL, Vector2(0.0, 58.0), 20)
    _world_map_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
    _world_map_button.pressed.connect(func() -> void: world_map_requested.emit())
    vbox.add_child(_world_map_button)
    return vbox.get_parent().get_parent() as Control


func _slider_row(parent: Node, key: String, caption: String, minimum: float, maximum: float, step: float) -> HSlider:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    parent.add_child(row)
    var cap := _label(row, caption, 15, COL_MUTED)
    cap.custom_minimum_size = Vector2(190.0, 0.0)
    cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    var slider := HSlider.new()
    slider.min_value = minimum
    slider.max_value = maximum
    slider.step = step
    slider.custom_minimum_size = Vector2(0.0, 36.0)
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(slider)
    var value_label := _label(row, "", 15, COL_TEXT)
    value_label.custom_minimum_size = Vector2(72.0, 0.0)
    value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _setting_value_labels[key] = value_label
    slider.value_changed.connect(func(value: float) -> void:
        _settings[key] = value
        _refresh_setting_value_labels()
        _emit_settings()
    )
    return slider


func _build_settings_panel(parent: Node) -> Control:
    var vbox := _new_panel(parent)
    _label(vbox, "НАСТРОЙКИ", 28, COL_TEXT)
    var columns := HBoxContainer.new()
    columns.add_theme_constant_override("separation", 22)
    columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
    vbox.add_child(columns)

    var left := VBoxContainer.new()
    left.add_theme_constant_override("separation", 9)
    left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    left.size_flags_stretch_ratio = 1.25
    columns.add_child(left)
    _label(left, "УПРАВЛЕНИЕ", 19, COL_YELLOW)
    _label(left, "Тип управления", 15, COL_MUTED)
    var type_row := HBoxContainer.new()
    type_row.add_theme_constant_override("separation", 8)
    left.add_child(type_row)
    var group := ButtonGroup.new()
    for spec in [["wheel", "РУЛЬ"], ["tilt", "НАКЛОН"], ["arrows", "СТРЕЛКИ"]]:
        var control_type := String(spec[0])
        var button := _button(String(spec[1]), COL_TEAL, Vector2(0.0, 52.0), 16)
        button.alignment = HORIZONTAL_ALIGNMENT_CENTER
        button.toggle_mode = true
        button.button_group = group
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        button.pressed.connect(func() -> void:
            _settings["control_type"] = control_type
            _emit_settings()
        )
        type_row.add_child(button)
        _control_buttons[control_type] = button
    _sensitivity_slider = _slider_row(left, "steering_sensitivity", "Чувствительность руля", 0.5, 1.8, 0.05)
    _dead_zone_slider = _slider_row(left, "steering_dead_zone", "Мёртвая зона", 0.0, 0.25, 0.01)
    _wheel_size_slider = _slider_row(left, "wheel_size_multiplier", "Размер руля", 0.75, 1.25, 0.05)
    _label(left, "НАКЛОН автоматически запоминает текущее положение телефона как центр при включении.", 13, COL_MUTED)

    var right := VBoxContainer.new()
    right.add_theme_constant_override("separation", 10)
    right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    columns.add_child(right)
    _label(right, "ИГРА И ПАУЗА", 19, COL_YELLOW)
    _camera_setting_button = _button("КАМЕРА: ВИД СЗАДИ", COL_TEAL, Vector2(0.0, 54.0), 17)
    _camera_setting_button.pressed.connect(func() -> void: camera_cycle_requested.emit())
    right.add_child(_camera_setting_button)
    _time_setting_button = _button("ВРЕМЯ СУТОК: ДЕНЬ", COL_TEAL, Vector2(0.0, 54.0), 17)
    _time_setting_button.pressed.connect(func() -> void: time_cycle_requested.emit())
    right.add_child(_time_setting_button)
    _sound_toggle = _button("ЗВУК: ВКЛ", COL_MAGENTA, Vector2(0.0, 54.0), 17)
    _sound_toggle.pressed.connect(func() -> void:
        _settings["sound_enabled"] = not bool(_settings.get("sound_enabled", true))
        _refresh_settings_controls()
        _emit_settings()
    )
    right.add_child(_sound_toggle)
    var continue_button := _button("ПРОДОЛЖИТЬ", COL_YELLOW, Vector2(0.0, 58.0), 19)
    continue_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
    continue_button.pressed.connect(func() -> void: play_requested.emit())
    right.add_child(continue_button)
    var spacer := Control.new()
    spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
    right.add_child(spacer)
    _developer_status_label = _label(right, "режим разработчика выключен", 13, COL_MUTED)
    _version_button = _button("Nitches 0.2.33-native-alpha", COL_LOCKED, Vector2(0.0, 42.0), 13)
    _version_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
    _version_button.pressed.connect(_on_version_pressed)
    right.add_child(_version_button)
    _refresh_settings_controls()
    return vbox.get_parent().get_parent() as Control


func _on_version_pressed() -> void:
    var now := Time.get_ticks_msec()
    if now - _last_version_tap_msec > 1600:
        _version_taps = 0
    _last_version_tap_msec = now
    _version_taps += 1
    if _version_taps >= 5:
        _version_taps = 0
        _settings["developer_mode"] = not bool(_settings.get("developer_mode", false))
        _refresh_settings_controls()
        _emit_settings()


func _emit_settings() -> void:
    if not _updating_settings:
        settings_changed.emit(_settings.duplicate(true))


func _refresh_setting_value_labels() -> void:
    if _setting_value_labels.has("steering_sensitivity"):
        (_setting_value_labels["steering_sensitivity"] as Label).text = "x%.2f" % float(_settings.get("steering_sensitivity", 1.0))
    if _setting_value_labels.has("steering_dead_zone"):
        (_setting_value_labels["steering_dead_zone"] as Label).text = "%d%%" % int(round(float(_settings.get("steering_dead_zone", 0.03)) * 100.0))
    if _setting_value_labels.has("wheel_size_multiplier"):
        (_setting_value_labels["wheel_size_multiplier"] as Label).text = "%d%%" % int(round(float(_settings.get("wheel_size_multiplier", 1.0)) * 100.0))


func _refresh_settings_controls() -> void:
    _updating_settings = true
    var control_type := String(_settings.get("control_type", "wheel"))
    for key in _control_buttons.keys():
        (_control_buttons[key] as Button).button_pressed = String(key) == control_type
    if _sensitivity_slider != null:
        _sensitivity_slider.value = float(_settings.get("steering_sensitivity", 1.0))
    if _dead_zone_slider != null:
        _dead_zone_slider.value = float(_settings.get("steering_dead_zone", 0.03))
    if _wheel_size_slider != null:
        _wheel_size_slider.value = float(_settings.get("wheel_size_multiplier", 1.0))
    if _sound_toggle != null:
        _sound_toggle.text = "ЗВУК: ВКЛ" if bool(_settings.get("sound_enabled", true)) else "ЗВУК: ВЫКЛ"
    if _camera_setting_button != null:
        _camera_setting_button.text = "КАМЕРА: %s" % String(_settings.get("camera_label", "ВИД СЗАДИ"))
    if _time_setting_button != null:
        _time_setting_button.text = "ВРЕМЯ СУТОК: %s" % String(_settings.get("time_label", "ДЕНЬ"))
    if _developer_status_label != null:
        _developer_status_label.text = "режим разработчика включён: FPS/DRAW/TRIS/CPU/PHYS видны в HUD" if bool(_settings.get("developer_mode", false)) else "режим разработчика выключен • 5 касаний по версии"
    _refresh_setting_value_labels()
    _updating_settings = false


func bind_settings(settings: Dictionary) -> void:
    for key in settings.keys():
        _settings[key] = settings[key]
    _settings_bound = true
    _refresh_settings_controls()


# --------------------------------------------------------------------- #
# data binding
# --------------------------------------------------------------------- #
func bind_specs(specs: Dictionary) -> void:
    _car_name = String(specs.get("name", ""))
    if _top_car_label != null and not _car_name.is_empty():
        _top_car_label.text = "%s '%d" % [_car_name, int(specs.get("year", 1967)) % 100]
    _specs_bound = int(specs.get("power_hp", 0)) == 365 and int(specs.get("torque_nm", 0)) == 569


func refresh_profile(view: Dictionary) -> void:
    _profile_bound = true
    var player_name := String(view.get("name", "ИГРОК"))
    var level := int(view.get("level", 1))
    var credits := int(view.get("credits", 35000))
    if _top_name_label != null:
        _top_name_label.text = "%s • ур. %d" % [player_name, level]
    if _top_credits_label != null:
        _top_credits_label.text = "CR %s" % _fmt_int(credits)
    if _profile_tile_sub != null:
        _profile_tile_sub.text = "ур. %d • CR %s" % [level, _fmt_int(credits)]
    if _p_name != null:
        _p_name.text = player_name
        _p_level.text = "Уровень: %d" % level
        _p_credits.text = "Кредиты: CR %s" % _fmt_int(credits)
        _p_distance.text = "Пробег: %.1f км" % float(view.get("distance_km", 0.0))
        _p_top.text = "Рекорд скорости: %d км/ч" % int(round(float(view.get("top_speed_kmh", 0.0))))
        _p_time.text = "Время за рулём: %d мин" % int(float(view.get("play_seconds", 0.0)) / 60.0)


func _fmt_int(value: int) -> String:
    var digits := str(absi(value))
    var out := ""
    var count := 0
    for i in range(digits.length() - 1, -1, -1):
        out = digits[i] + out
        count += 1
        if count % 3 == 0 and i > 0:
            out = " " + out
    return ("-" if value < 0 else "") + out
