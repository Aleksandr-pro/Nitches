class_name NativeMainMenu
extends CanvasLayer

## 0.2.40 front end: the live 3D selected-car/RichTown scene stays
## visible behind clean dark translucent panels.  Navigation is a
## single row of labelled icon tabs, PLAY is the one dominant home
## action, and both the garage and the real-content store expose the
## actual selected car in Main's studio scene.  Four catalogue cars
## have real GLBs, physics, recorded audio and per-car customization;
## no model-less fake cars are listed.

signal play_requested
signal world_map_requested
signal settings_changed(settings: Dictionary)
signal camera_cycle_requested
signal time_cycle_requested
signal panel_changed(panel_index: int)
signal garage_dragged(relative: Vector2)
signal garage_zoomed(factor: float)
signal customization_changed(customization: Dictionary)
signal tuning_purchase_requested(level: int)
signal profile_changed(player_name: String, avatar_id: String)
signal car_selection_requested(car_id: String)
signal world_selected(world_id: String)

const CarSilhouetteScript := preload("res://scripts/car_silhouette_icon.gd")
const AvatarIconScript := preload("res://scripts/avatar_icon.gd")
const WheelPreviewScript := preload("res://scripts/wheel_preview.gd")
const LockIconScript := preload("res://scripts/lock_icon.gd")
const MENU_PLAY_TEXTURE: Texture2D = preload("res://assets/ui/menu_play_gameplay.jpg")
const MENU_SHELBY_TEXTURE: Texture2D = preload("res://assets/ui/menu_shelby_gameplay.jpg")
const MENU_RICHTOWN_TEXTURE: Texture2D = preload("res://assets/ui/menu_richtown_gameplay.jpg")
const MENU_WORLD_TEXTURE: Texture2D = preload("res://assets/ui/menu_world_gameplay.jpg")
const UI_CLICK_STREAM: AudioStream = preload("res://assets/audio/ui_click.wav")
const BACKDROP_BLUR_SHADER: Shader = preload("res://shaders/backdrop_blur.gdshader")

const COL_BG := Color(0.004, 0.008, 0.014, 0.16)
const COL_PANEL := Color(0.008, 0.012, 0.020, 0.68)
const COL_PANEL_LIGHT := Color(0.035, 0.045, 0.060, 0.78)
const COL_TEXT := Color(0.96, 0.98, 1.0)
const COL_MUTED := Color(0.72, 0.78, 0.85)
const COL_ACCENT := Color(1.0, 0.58, 0.08)
const COL_BORDER := Color(1.0, 1.0, 1.0, 0.22)
const COL_LOCKED := Color(0.30, 0.34, 0.38)
const PANEL_HOME := 0
const PANEL_GARAGE := 1
const PANEL_STORE := 2
const PANEL_PROFILE := 3
const PANEL_WORLDS := 4
const PANEL_SETTINGS := 5
const PANEL_TRANSITION_SECONDS := 0.18
const MIN_TOUCH_HEIGHT := 48.0
const MIN_FONT_SIZE := 14
const WORLD_MOUNTAINS_REQUIRED_LEVEL := 5
const WORLD_CANYON_REQUIRED_CREDITS := 50000
# Temporary owner request (0.2.48): every finished world is free for
# all players. Flip this one flag to restore the credit/level gates.
const WORLDS_FREE_FOR_ALL := true
const TUNING_COSTS: Array[int] = [0, 5000, 12000]
const TUNING_MULTIPLIERS: Array[float] = [1.0, 1.08, 1.16]
const TUNING_NAMES: Array[String] = ["СТОК", "SPORT", "TRACK"]
const TUNING_DESCRIPTIONS: Array[String] = [
    "Заводская настройка выбранного автомобиля: исходные мощность и момент.",
    "Уличный пакет: +8% к мощности и моменту выбранного автомобиля.",
    "Трековый пакет: +16% к мощности и моменту выбранного автомобиля.",
]
const WHEEL_FINISH_COLORS := {
    "silver": Color(0.72, 0.75, 0.78),
    "black": Color(0.018, 0.02, 0.024),
    "bronze": Color(0.48, 0.27, 0.09),
    "white": Color(0.88, 0.89, 0.90),
}

var _root: Control
var _built := false
var _panels: Array[Control] = []
var _tab_buttons: Array[Button] = []
var _tab_icon_labels: Array[Label] = []
var _tab_text_labels: Array[Label] = []
var _current_panel := 0
var _panel_tween: Tween
var _body_font: Font
var _heading_font: Font
var _click_player: AudioStreamPlayer
var _hover_player: AudioStreamPlayer
var _last_hover_msec := 0
var _backdrop_blur_material: ShaderMaterial
var _car_name := ""
var _selected_car_id := NativeCarCatalog.DEFAULT_CAR_ID
var _catalog_cars: Array = []
var _catalog_by_id: Dictionary = {}
var _catalog_bound := false
var _car_texture_cache: Dictionary = {}
var _specs: Dictionary = {}
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
    "graphics_quality": "balanced",
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
var _graphics_buttons: Dictionary = {}
var _graphics_note_label: Label
var _camera_setting_button: Button
var _time_setting_button: Button
var _developer_status_label: Label
var _version_button: Button
var _version_taps := 0
var _last_version_tap_msec := 0

var _top_car_label: Label
var _top_car_summary_label: Label
var _top_car_icon: NativeCarSilhouetteIcon
var _top_credits_label: Label
var _top_name_label: Label
var _top_avatar_icon: NativeAvatarIcon
var _top_xp_bar: ProgressBar
var _top_xp_label: Label
var _home_class_label: Label
var _home_goal_label: Label
var _home_world_card: Button
var _home_car_card: Button
var _home_play_button: Button

var _p_name: Label
var _p_level: Label
var _p_credits: Label
var _p_distance: Label
var _p_top: Label
var _p_drift: Label
var _p_time: Label
var _profile_avatar_icon: NativeAvatarIcon
var _profile_scroll: ScrollContainer
var _nickname_edit: LineEdit
var _xp_bar: ProgressBar
var _xp_label: Label
var _achievements_box: VBoxContainer
var _achievement_card_count := 0
var _history_box: VBoxContainer
var _car_stats_label: Label
var _profile_view: Dictionary = {}
var _avatar_id := "wheel"

var _customization: Dictionary = {
    "paint_id": "red",
    "paint_color": Color(0.48, 0.025, 0.035),
    "wheel_finish": "silver",
    "tuning_level": 0,
    "tuning_owned_max": 0,
    "license_plate": "GT500-67",
}
var _customization_bound := false
var _preview_tuning_level := 0
var _paint_buttons: Dictionary = {}
var _wheel_finish_previews: Dictionary = {}
var _tuning_buttons: Array[Button] = []
var _tuning_action_button: Button
var _tuning_now_label: Label
var _tuning_compare_label: Label
var _garage_next_step_label: Label
var _garage_next_step_button: Button
var _garage_class_label: Label
var _garage_power_label: Label
var _garage_torque_label: Label
var _garage_accel_label: Label
var _garage_title_label: Label
var _garage_category_label: Label
var _garage_engine_label: Label
var _garage_top_speed_label: Label
var _garage_gearbox_label: Label
var _garage_drive_label: Label
var _garage_mass_label: Label
var _garage_dimensions_label: Label
var _garage_rating_bars: Dictionary = {}
var _garage_cars_title: Label
var _garage_cars_box: VBoxContainer
var _garage_car_buttons: Dictionary = {}
var _garage_drive_button: Button
var _garage_status_label: Label
var _plate_edit: LineEdit
var _garage_drag_surface: Control
var _store_drag_surface: Control
var _garage_drag_index := -2
var _garage_mouse_dragging := false

var _store_balance_label: Label
var _store_status_label: Label
var _store_detail_title: Label
var _store_detail_label: Label
var _store_action_button: Button
var _store_cards_box: VBoxContainer
var _store_card_buttons: Dictionary = {}
var _store_filter_buttons: Dictionary = {}
var _store_sort_button: Button
var _store_filter := "all"
var _store_sort := "price"
var _store_selected_id := "shelby_gt500"
var _store_hint_label: Label
var _store_drive_button: Button

var _world_progress_label: Label
var _world_detail_label: Label
var _current_world_id := "richtown"
var _richtown_card: Button
var _desert_card: Button
var _desert_card_subtitle: Label
var _desert_lock_icon: Control
var _forest_card: Button
var _forest_card_subtitle: Label
var _world_title_label: Label
var _paint_options: Array[Dictionary] = [
    {"id": "red", "name": "Красный", "color": Color(0.48, 0.025, 0.035)},
    {"id": "blue", "name": "Синий", "color": Color(0.03, 0.16, 0.55)},
    {"id": "green", "name": "Зелёный", "color": Color(0.02, 0.30, 0.17)},
    {"id": "yellow", "name": "Жёлтый", "color": Color(0.92, 0.64, 0.04)},
    {"id": "silver", "name": "Серебристый", "color": Color(0.62, 0.66, 0.70)},
    {"id": "black", "name": "Чёрный", "color": Color(0.012, 0.014, 0.018)},
]


func _ready() -> void:
    layer = 6
    _make_fonts()
    _make_backdrop_material()
    _setup_audio()
    _build_ui()
    _built = true
    hide_menu()


func show_menu() -> void:
    if _root != null:
        _root.visible = true
        if _current_panel >= 0 and _current_panel < _panels.size():
            call_deferred("_animate_panel", _panels[_current_panel])


func show_settings() -> void:
    show_menu()
    _show_panel(PANEL_SETTINGS)


func show_panel_index(index: int) -> void:
    show_menu()
    _show_panel(index)


func hide_menu() -> void:
    if _root != null:
        _root.visible = false


func is_menu_visible() -> bool:
    return _root != null and _root.visible


func get_current_panel() -> int:
    return _current_panel


func get_smoke_state() -> Dictionary:
    return {
        "created": _built,
        "panels": _panels.size(),
        "tabs": _tab_buttons.size(),
        "current_panel": _current_panel,
        "car_name": _car_name,
        "specs_bound": _specs_bound,
        "profile_bound": _profile_bound,
        "visible_now": is_menu_visible(),
        "world_map_button": _world_map_button != null,
        "settings_panel_0233": _sensitivity_slider != null and _dead_zone_slider != null and _wheel_size_slider != null,
        "graphics_quality_0244": _graphics_buttons.size() == 3 and _graphics_note_label != null,
        "control_buttons": _control_buttons.size(),
        "settings_bound": _settings_bound,
        "version_button_created": _version_button != null,
        "developer_mode": bool(_settings.get("developer_mode", false)),
        "control_type": String(_settings.get("control_type", "wheel")),
        "clean_menu_0234": true,
        "multi_car_0240": _catalog_entries().size() == 4 and _garage_car_buttons.size() == 4,
        "catalog_cars": _catalog_entries().size(),
        "catalog_bound": _catalog_bound,
        "selected_car_id": _selected_car_id,
        "garage_cars": _garage_car_buttons.size(),
        "store_cars": _store_car_count(),
        "store_panel_0236": _panels.size() == 6 and _store_cards_box != null and _store_drag_surface != null,
        "store_items": _store_card_buttons.size(),
        "store_filter": _store_filter,
        "store_sort": _store_sort,
        "labeled_tabs_0236": _tab_buttons.size() == 6 and _tab_text_labels.size() == 6 and _tab_icon_labels.size() == 6,
        "top_xp_bar_0236": _top_xp_bar != null and _top_xp_label != null,
        "avatar_icon_0236": _top_avatar_icon != null and _profile_avatar_icon != null,
        "clickable_home_cards_0236": _home_world_card != null and _home_car_card != null,
        "home_goal_0236": _home_goal_label != null and not _home_goal_label.text.is_empty(),
        "wheel_previews_0236": _wheel_finish_previews.size() == 4,
        "profile_single_scroll_0236": _profile_scroll != null,
        "achievement_cards_0236": _achievement_card_count,
        "locked_world_conditions_0236": _world_progress_label != null and _world_detail_label != null,
        "desert_world_0247": _desert_card != null,
        "forest_world_0254": _forest_card != null,
        "current_world_id": _current_world_id,
        "desert_unlocked_0247": _desert_unlocked(),
        "worlds_free_for_all_0248": WORLDS_FREE_FOR_ALL,
        "hover_sound_0236": _hover_player != null,
        "panel_transition_018_0236": is_equal_approx(PANEL_TRANSITION_SECONDS, 0.18),
        "gameplay_card_textures_0236": MENU_PLAY_TEXTURE != null and MENU_SHELBY_TEXTURE != null and MENU_RICHTOWN_TEXTURE != null and MENU_WORLD_TEXTURE != null,
        "readability_min_font_0236": MIN_FONT_SIZE >= 14,
        "touch_min_height_0236": MIN_TOUCH_HEIGHT >= 48.0,
        "car_icon_created": _top_car_icon != null,
        "garage_drag_surface": _garage_drag_surface != null,
        "customization_bound": _customization_bound,
        "paint_options": _paint_buttons.size(),
        "wheel_finish_options": _wheel_finish_previews.size(),
        "tuning_options": _tuning_buttons.size(),
        "profile_xp_created": _xp_bar != null,
        "click_sound_created": _click_player != null and UI_CLICK_STREAM != null,
        "garage_status_created": _garage_status_label != null,
        "backdrop_blur_0234": _backdrop_blur_material != null,
    }


# --------------------------------------------------------------------- #
# construction helpers
# --------------------------------------------------------------------- #
func _make_fonts() -> void:
    var body := FontVariation.new()
    body.base_font = ThemeDB.fallback_font
    body.variation_embolden = 0.08
    _body_font = body
    var heading := FontVariation.new()
    heading.base_font = ThemeDB.fallback_font
    heading.variation_embolden = 0.62
    heading.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(-0.14, 1.0), Vector2.ZERO)
    _heading_font = heading


func _make_backdrop_material() -> void:
    _backdrop_blur_material = ShaderMaterial.new()
    _backdrop_blur_material.shader = BACKDROP_BLUR_SHADER
    _backdrop_blur_material.set_shader_parameter("blur_lod", 2.6)


func _add_backdrop_blur(panel: PanelContainer, tint: Color) -> void:
    var blur_panel := Panel.new()
    blur_panel.name = "BackdropBlur0234"
    blur_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    blur_panel.add_theme_stylebox_override("panel", _style(tint, Color.TRANSPARENT, 7, 0))
    blur_panel.material = _backdrop_blur_material
    panel.add_child(blur_panel)


func _setup_audio() -> void:
    _click_player = AudioStreamPlayer.new()
    _click_player.name = "MenuClickPlayer"
    _click_player.stream = UI_CLICK_STREAM
    _click_player.volume_db = -9.0
    add_child(_click_player)
    _hover_player = AudioStreamPlayer.new()
    _hover_player.name = "MenuHoverPlayer"
    _hover_player.stream = UI_CLICK_STREAM
    _hover_player.volume_db = -24.0
    _hover_player.pitch_scale = 1.35
    add_child(_hover_player)


func _play_click() -> void:
    if _click_player != null and bool(_settings.get("sound_enabled", true)):
        _click_player.stop()
        _click_player.play()


func _play_hover() -> void:
    if _hover_player == null or not bool(_settings.get("sound_enabled", true)):
        return
    var now := Time.get_ticks_msec()
    if now - _last_hover_msec < 70:
        return
    _last_hover_msec = now
    _hover_player.stop()
    _hover_player.play()


func _style(bg: Color, border: Color, radius: int = 8, border_w: int = 0) -> StyleBoxFlat:
    var sb := StyleBoxFlat.new()
    sb.bg_color = bg
    sb.corner_detail = 1
    sb.corner_radius_top_left = 4
    sb.corner_radius_top_right = maxi(radius * 2, 14)
    sb.corner_radius_bottom_right = 4
    sb.corner_radius_bottom_left = maxi(radius * 2, 14)
    if border_w > 0:
        sb.set_border_width_all(border_w)
        sb.border_color = border
    sb.content_margin_left = 14.0
    sb.content_margin_right = 14.0
    sb.content_margin_top = 8.0
    sb.content_margin_bottom = 8.0
    return sb


func _label(parent: Node, text: String, size: int, color: Color = COL_TEXT, heading: bool = false) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_override("font", _heading_font if heading else _body_font)
    label.add_theme_font_size_override("font_size", maxi(size, MIN_FONT_SIZE))
    label.add_theme_color_override("font_color", color)
    label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.72))
    label.add_theme_constant_override("shadow_offset_x", 1)
    label.add_theme_constant_override("shadow_offset_y", 1)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(label)
    return label


func _button(text: String, accent: Color, min_size: Vector2, font_size: int = 22) -> Button:
    var button := Button.new()
    button.text = text
    button.custom_minimum_size = Vector2(min_size.x, maxf(min_size.y, MIN_TOUCH_HEIGHT))
    button.focus_mode = Control.FOCUS_NONE
    button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    button.add_theme_font_override("font", _heading_font if font_size >= 17 else _body_font)
    button.add_theme_font_size_override("font_size", maxi(font_size, MIN_FONT_SIZE))
    button.add_theme_color_override("font_color", COL_TEXT)
    button.add_theme_color_override("font_hover_color", Color.WHITE)
    button.add_theme_color_override("font_pressed_color", Color.WHITE)
    button.add_theme_color_override("font_disabled_color", COL_MUTED)
    button.add_theme_stylebox_override("normal", _style(COL_PANEL, COL_BORDER, 7, 1))
    button.add_theme_stylebox_override("hover", _style(COL_PANEL_LIGHT, accent, 7, 2))
    button.add_theme_stylebox_override("pressed", _style(accent.darkened(0.18), accent.lightened(0.25), 7, 2))
    button.add_theme_stylebox_override("disabled", _style(Color(0.01, 0.015, 0.02, 0.52), COL_LOCKED, 7, 1))
    button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
    button.mouse_entered.connect(_play_hover)
    button.focus_entered.connect(_play_hover)
    button.pressed.connect(_play_click)
    button.button_down.connect(func() -> void:
        button.pivot_offset = button.size * 0.5
        button.scale = Vector2.ONE * 0.97
    )
    button.button_up.connect(func() -> void:
        button.scale = Vector2.ONE
    )
    return button


func _add_picture_layers(control: Control, texture: Texture2D, title: String, subtitle: String, title_size: int) -> void:
    control.clip_contents = true
    var image := TextureRect.new()
    image.name = "PictureImage"
    image.texture = texture
    image.set_anchors_preset(Control.PRESET_FULL_RECT)
    image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    image.mouse_filter = Control.MOUSE_FILTER_IGNORE
    control.add_child(image)
    var shade := ColorRect.new()
    shade.color = Color(0.0, 0.0, 0.0, 0.28)
    shade.set_anchors_preset(Control.PRESET_FULL_RECT)
    shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    control.add_child(shade)
    var label_block_height := float(maxi(title_size, MIN_FONT_SIZE) + 42)
    var label_shade := ColorRect.new()
    label_shade.color = Color(0.0, 0.0, 0.0, 0.46)
    label_shade.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    label_shade.offset_left = 0.0
    label_shade.offset_top = -(label_block_height + 18.0)
    label_shade.offset_right = 0.0
    label_shade.offset_bottom = 0.0
    label_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    control.add_child(label_shade)
    var labels := VBoxContainer.new()
    labels.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    labels.offset_left = 16.0
    labels.offset_top = -label_block_height
    labels.offset_right = -16.0
    labels.offset_bottom = -10.0
    labels.alignment = BoxContainer.ALIGNMENT_END
    labels.clip_contents = false
    labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
    control.add_child(labels)
    var title_label := _label(labels, title, title_size, Color.WHITE, true)
    title_label.name = "PictureTitle"
    title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    title_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
    var subtitle_label := _label(labels, subtitle, MIN_FONT_SIZE, Color(0.90, 0.94, 0.99))
    subtitle_label.name = "PictureSubtitle"
    subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM


func _picture_button(texture: Texture2D, title: String, subtitle: String, min_size: Vector2, title_size: int = 34) -> Button:
    var button := _button("", COL_ACCENT, min_size, title_size)
    button.add_theme_stylebox_override("normal", _style(Color(0, 0, 0, 0.18), COL_BORDER, 8, 1))
    button.add_theme_stylebox_override("hover", _style(Color(0, 0, 0, 0.10), COL_ACCENT, 8, 2))
    button.add_theme_stylebox_override("pressed", _style(Color(0, 0, 0, 0.12), Color.WHITE, 8, 2))
    _add_picture_layers(button, texture, title, subtitle, title_size)
    return button


func _picture_card(parent: Node, texture: Texture2D, title: String, subtitle: String, min_size: Vector2) -> Control:
    var card := Control.new()
    card.custom_minimum_size = min_size
    card.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(card)
    _add_picture_layers(card, texture, title, subtitle, 20)
    return card


func _tile(title: String, subtitle: String, accent: Color, min_size: Vector2, font_size: int = 30) -> Button:
    var button := _button(title, accent, min_size, font_size)
    var sub := Label.new()
    sub.text = subtitle
    sub.add_theme_font_override("font", _body_font)
    sub.add_theme_font_size_override("font_size", MIN_FONT_SIZE)
    sub.add_theme_color_override("font_color", COL_MUTED)
    sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
    sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    sub.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    sub.offset_left = 15.0
    sub.offset_top = -38.0
    sub.offset_right = -12.0
    sub.offset_bottom = -9.0
    button.add_child(sub)
    return button


func _panel_box(parent: Node) -> PanelContainer:
    var panel := PanelContainer.new()
    panel.add_theme_stylebox_override("panel", _style(COL_PANEL, COL_BORDER, 7, 1))
    parent.add_child(panel)
    _add_backdrop_blur(panel, COL_PANEL)
    return panel


func _bar(parent: Node, caption: String, value: float, accent: Color) -> ProgressBar:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    parent.add_child(row)
    var cap := _label(row, caption, 14, COL_MUTED)
    cap.custom_minimum_size = Vector2(118.0, 0.0)
    var bar := ProgressBar.new()
    bar.min_value = 0.0
    bar.max_value = 10.0
    bar.value = value
    bar.show_percentage = false
    bar.custom_minimum_size = Vector2(0.0, 12.0)
    bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bar.add_theme_stylebox_override("background", _style(Color(1, 1, 1, 0.10), COL_BORDER, 3, 0))
    bar.add_theme_stylebox_override("fill", _style(accent, accent, 3, 0))
    row.add_child(bar)
    var value_label := _label(row, "%.1f" % value, 14, COL_TEXT)
    value_label.name = "RatingValue"
    return bar


func _spec_row(grid: GridContainer, key_text: String, value_text: String) -> Label:
    _label(grid, key_text, 14, COL_MUTED)
    return _label(grid, value_text, 14, COL_TEXT)


func _line_edit(text: String, placeholder: String) -> LineEdit:
    var edit := LineEdit.new()
    edit.text = text
    edit.placeholder_text = placeholder
    edit.custom_minimum_size = Vector2(0.0, MIN_TOUCH_HEIGHT)
    edit.add_theme_font_override("font", _body_font)
    edit.add_theme_font_size_override("font_size", 16)
    edit.add_theme_color_override("font_color", COL_TEXT)
    edit.add_theme_color_override("font_placeholder_color", COL_MUTED)
    edit.add_theme_color_override("caret_color", COL_ACCENT)
    edit.add_theme_stylebox_override("normal", _style(Color(0.0, 0.0, 0.0, 0.42), COL_BORDER, 6, 1))
    edit.add_theme_stylebox_override("focus", _style(Color(0.02, 0.03, 0.04, 0.58), COL_ACCENT, 6, 2))
    return edit


# --------------------------------------------------------------------- #
# layout
# --------------------------------------------------------------------- #
func _build_ui() -> void:
    _root = Control.new()
    _root.name = "MainMenuRoot"
    _root.set_anchors_preset(Control.PRESET_FULL_RECT)
    _root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_root)

    var bg := ColorRect.new()
    bg.color = COL_BG
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(bg)

    var margin := MarginContainer.new()
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_left", 24)
    margin.add_theme_constant_override("margin_right", 24)
    margin.add_theme_constant_override("margin_top", 16)
    margin.add_theme_constant_override("margin_bottom", 16)
    _root.add_child(margin)

    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 10)
    margin.add_child(column)

    _build_top_bar(column)
    _build_tabs(column)

    var panels_root := Control.new()
    panels_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panels_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(panels_root)

    _panels.append(_build_home_panel(panels_root))
    _panels.append(_build_garage_panel(panels_root))
    _panels.append(_build_store_panel(panels_root))
    _panels.append(_build_profile_panel(panels_root))
    _panels.append(_build_worlds_panel(panels_root))
    _panels.append(_build_settings_panel(panels_root))
    _show_panel(PANEL_HOME)


func _build_top_bar(parent: Node) -> void:
    var bar := HBoxContainer.new()
    bar.add_theme_constant_override("separation", 12)
    parent.add_child(bar)

    var logo := _label(bar, "NITCHES HORIZON", 29, Color.WHITE, true)
    logo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

    var car_chip := _panel_box(bar)
    var car_row := HBoxContainer.new()
    car_row.add_theme_constant_override("separation", 10)
    car_chip.add_child(car_row)
    _top_car_icon = CarSilhouetteScript.new()
    _top_car_icon.custom_minimum_size = Vector2(78.0, 38.0)
    car_row.add_child(_top_car_icon)
    var car_text := VBoxContainer.new()
    car_row.add_child(car_text)
    _top_car_label = _label(car_text, "Shelby GT500 '67", 16, COL_TEXT, true)
    _top_car_summary_label = _label(car_text, "365 л.с. • 569 Нм • 207 км/ч", 12, COL_MUTED)

    var spacer := Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bar.add_child(spacer)

    var profile_chip := _panel_box(bar)
    var profile_row := HBoxContainer.new()
    profile_row.add_theme_constant_override("separation", 10)
    profile_chip.add_child(profile_row)
    _top_avatar_icon = AvatarIconScript.new() as NativeAvatarIcon
    _top_avatar_icon.custom_minimum_size = Vector2(52.0, 52.0)
    profile_row.add_child(_top_avatar_icon)
    var profile_text := VBoxContainer.new()
    profile_text.add_theme_constant_override("separation", 2)
    profile_text.custom_minimum_size = Vector2(176.0, 0.0)
    profile_row.add_child(profile_text)
    _top_name_label = _label(profile_text, "ИГРОК", 15, COL_TEXT, true)
    _top_credits_label = _label(profile_text, "CR 35 000", MIN_FONT_SIZE, Color(1.0, 0.78, 0.42))
    var xp_row := HBoxContainer.new()
    xp_row.add_theme_constant_override("separation", 7)
    profile_text.add_child(xp_row)
    _top_xp_label = _label(xp_row, "ур. 1 • XP 0%", MIN_FONT_SIZE, COL_MUTED)
    _top_xp_bar = ProgressBar.new()
    _top_xp_bar.min_value = 0.0
    _top_xp_bar.max_value = 1.0
    _top_xp_bar.value = 0.0
    _top_xp_bar.show_percentage = false
    _top_xp_bar.custom_minimum_size = Vector2(82.0, 9.0)
    _top_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _top_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _top_xp_bar.add_theme_stylebox_override("background", _style(Color(1, 1, 1, 0.12), COL_BORDER, 3, 0))
    _top_xp_bar.add_theme_stylebox_override("fill", _style(COL_ACCENT, COL_ACCENT, 3, 0))
    xp_row.add_child(_top_xp_bar)


func _build_tabs(parent: Node) -> void:
    var tabs := HBoxContainer.new()
    tabs.add_theme_constant_override("separation", 7)
    parent.add_child(tabs)
    var group := ButtonGroup.new()
    var specs := [
        ["⌂", "Главная"],
        ["◎", "Гараж"],
        ["▣", "Магазин"],
        ["◉", "Профиль"],
        ["⌖", "Карты"],
        ["⚙", "Настройки"],
    ]
    for i in specs.size():
        var tab := _button("", COL_ACCENT, Vector2(104.0, 60.0), MIN_FONT_SIZE)
        tab.name = "LabeledTab%d" % i
        tab.tooltip_text = String(specs[i][1])
        tab.alignment = HORIZONTAL_ALIGNMENT_CENTER
        tab.toggle_mode = true
        tab.button_group = group
        tab.pressed.connect(_show_panel.bind(i))
        var tab_text := VBoxContainer.new()
        tab_text.set_anchors_preset(Control.PRESET_FULL_RECT)
        tab_text.offset_left = 4.0
        tab_text.offset_top = 5.0
        tab_text.offset_right = -4.0
        tab_text.offset_bottom = -4.0
        tab_text.add_theme_constant_override("separation", 0)
        tab_text.alignment = BoxContainer.ALIGNMENT_CENTER
        tab_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
        tab.add_child(tab_text)
        var icon_label := _label(tab_text, String(specs[i][0]), 23, Color.WHITE, true)
        icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        var text_label := _label(tab_text, String(specs[i][1]), MIN_FONT_SIZE, Color.WHITE, true)
        text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        tabs.add_child(tab)
        _tab_buttons.append(tab)
        _tab_icon_labels.append(icon_label)
        _tab_text_labels.append(text_label)
    var spacer := Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    tabs.add_child(spacer)
    _tab_buttons[0].button_pressed = true
    _refresh_tab_labels()


func _refresh_tab_labels() -> void:
    for i in _tab_text_labels.size():
        var active := i == _current_panel
        _tab_icon_labels[i].add_theme_color_override("font_color", Color.WHITE if active else Color(0.78, 0.84, 0.92))
        _tab_text_labels[i].add_theme_color_override("font_color", Color(1.0, 0.74, 0.38) if active else Color.WHITE)


func _show_panel(index: int) -> void:
    if index < 0 or index >= _panels.size():
        return
    _current_panel = index
    for i in _panels.size():
        _panels[i].visible = i == index
    if index < _tab_buttons.size() and not _tab_buttons[index].button_pressed:
        _tab_buttons[index].button_pressed = true
    _refresh_tab_labels()
    if index == PANEL_STORE:
        _refresh_store()
    panel_changed.emit(index)
    call_deferred("_animate_panel", _panels[index])


func _animate_panel(panel: Control) -> void:
    if panel == null or not is_inside_tree():
        return
    if _panel_tween != null and _panel_tween.is_valid():
        _panel_tween.kill()
    panel.pivot_offset = panel.size * 0.5
    panel.modulate.a = 0.0
    panel.scale = Vector2.ONE * 0.985
    _panel_tween = create_tween()
    _panel_tween.set_parallel(true)
    _panel_tween.tween_property(panel, "modulate:a", 1.0, PANEL_TRANSITION_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    _panel_tween.tween_property(panel, "scale", Vector2.ONE, PANEL_TRANSITION_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _new_panel(parent: Node, background_alpha: float = 0.46, use_backdrop_blur: bool = true) -> VBoxContainer:
    var panel := PanelContainer.new()
    panel.set_anchors_preset(Control.PRESET_FULL_RECT)
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.add_theme_stylebox_override("panel", _style(Color(0.004, 0.008, 0.014, background_alpha), Color(1, 1, 1, 0.10), 8, 1))
    parent.add_child(panel)
    if use_backdrop_blur:
        _add_backdrop_blur(panel, Color(0.004, 0.008, 0.014, background_alpha))
    var margin := MarginContainer.new()
    margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
    margin.add_theme_constant_override("margin_left", 16)
    margin.add_theme_constant_override("margin_right", 16)
    margin.add_theme_constant_override("margin_top", 12)
    margin.add_theme_constant_override("margin_bottom", 12)
    panel.add_child(margin)
    var vbox := VBoxContainer.new()
    vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
    vbox.add_theme_constant_override("separation", 10)
    margin.add_child(vbox)
    return vbox


func _catalog_entries() -> Array:
    if not _catalog_cars.is_empty():
        return _catalog_cars.duplicate(true)
    var result: Array = []
    for car_variant in NativeCarCatalog.get_cars():
        var car: Dictionary = car_variant
        var entry := car.duplicate(true)
        entry["effective_power_hp"] = int(entry.get("power_hp", 0))
        entry["effective_torque_nm"] = int(entry.get("torque_nm", 0))
        entry["effective_accel_0_100_s"] = float(entry.get("accel_0_100_s", 6.0))
        entry["base_performance_index"] = int(entry.get("performance_index", 612))
        result.append(entry)
    return result


func _catalog_car(car_id: String) -> Dictionary:
    var normalized := NativeCarCatalog.normalize_id(car_id)
    if _catalog_by_id.has(normalized):
        return (_catalog_by_id[normalized] as Dictionary).duplicate(true)
    for entry_variant in _catalog_entries():
        var entry: Dictionary = entry_variant
        if String(entry.get("id", "")) == normalized:
            return entry.duplicate(true)
    return NativeCarCatalog.get_car(normalized)


func _texture_for_car(car_id: String) -> Texture2D:
    var normalized := NativeCarCatalog.normalize_id(car_id)
    if _car_texture_cache.has(normalized):
        return _car_texture_cache[normalized] as Texture2D
    var path := ""
    match normalized:
        "audi_r8_v10_plus":
            path = "res://assets/ui/menu_audi_r8_gameplay.jpg"
        "chevrolet_camaro_ss":
            path = "res://assets/ui/menu_camaro_ss_gameplay.jpg"
        "mercedes_560_sel":
            path = "res://assets/ui/menu_mercedes_560_sel_gameplay.jpg"
        _:
            path = "res://assets/ui/menu_shelby_gameplay.jpg"
    var texture: Texture2D = MENU_SHELBY_TEXTURE
    if ResourceLoader.exists(path):
        var loaded := load(path) as Texture2D
        if loaded != null:
            texture = loaded
    _car_texture_cache[normalized] = texture
    return texture


func _set_picture_card(button: Button, texture: Texture2D, title: String, subtitle: String) -> void:
    if button == null:
        return
    var image := button.get_node_or_null("PictureImage") as TextureRect
    if image != null:
        image.texture = texture
    var title_label := button.find_child("PictureTitle", true, false) as Label
    if title_label != null:
        title_label.text = title
    var subtitle_label := button.find_child("PictureSubtitle", true, false) as Label
    if subtitle_label != null:
        subtitle_label.text = subtitle


func _car_display_name(specs: Dictionary) -> String:
    var base_name := String(specs.get("short_name", specs.get("name", "Автомобиль")))
    var year_label := String(specs.get("year_label", ""))
    if year_label.is_empty() and int(specs.get("year", 0)) > 0:
        year_label = "'%02d" % (int(specs.get("year", 0)) % 100)
    return ("%s %s" % [base_name, year_label]).strip_edges()


func _specs_for_car(car_id: String) -> Dictionary:
    var normalized := NativeCarCatalog.normalize_id(car_id)
    if String(_specs.get("car_id", "")) == normalized:
        return _specs.duplicate(true)
    return _catalog_car(normalized)


func _tuning_values_for(specs: Dictionary, level: int) -> Dictionary:
    var safe := clampi(level, 0, TUNING_MULTIPLIERS.size() - 1)
    var base_power := float(specs.get("power_hp", 365))
    var base_torque := float(specs.get("torque_nm", 569))
    var base_accel := float(specs.get("accel_0_100_s", 6.0))
    var multiplier := TUNING_MULTIPLIERS[safe]
    var pi := 612
    var class_label := "A"
    var tuning_pis: Array = specs.get("tuning_performance_index", [])
    var tuning_classes: Array = specs.get("tuning_class_labels", [])
    if tuning_pis.size() > safe:
        pi = int(tuning_pis[safe])
    else:
        var adds: Array = specs.get("tuning_pi_add", [0, 36, 89])
        pi = int(specs.get("base_performance_index", specs.get("performance_index", 612))) + (int(adds[safe]) if adds.size() > safe else 0)
    if tuning_classes.size() > safe:
        class_label = String(tuning_classes[safe])
    else:
        class_label = NativeCarCatalog.class_label_for_pi(pi)
    return {
        "power": int(round(base_power * multiplier)),
        "torque": int(round(base_torque * multiplier)),
        "accel": base_accel / sqrt(multiplier),
        "pi": pi,
        "class": class_label,
    }


func _store_car_count() -> int:
    var count := 0
    for entry_variant in _catalog_entries():
        var entry: Dictionary = entry_variant
        if not String(entry.get("id", "")).is_empty():
            count += 1
    return count


func bind_car_catalog(cars: Array) -> void:
    _catalog_cars = cars.duplicate(true)
    _catalog_by_id.clear()
    var selected_found := false
    for entry_variant in _catalog_cars:
        var entry: Dictionary = entry_variant
        var car_id := String(entry.get("id", entry.get("car_id", "")))
        if car_id.is_empty():
            continue
        _catalog_by_id[car_id] = entry.duplicate(true)
        if bool(entry.get("selected", false)):
            _selected_car_id = car_id
            selected_found = true
    if not selected_found and not String(_specs.get("car_id", "")).is_empty():
        _selected_car_id = String(_specs.get("car_id", _selected_car_id))
    _catalog_bound = _catalog_by_id.size() == NativeCarCatalog.car_count()
    _refresh_car_presentation()


func _request_car_selection(car_id: String) -> void:
    var next_id := NativeCarCatalog.normalize_id(car_id)
    if next_id == _selected_car_id:
        return
    var entry := _catalog_car(next_id)
    set_garage_status("Загружаю %s: модель, физику и звук…" % _car_display_name(entry))
    car_selection_requested.emit(next_id)


func _refresh_car_presentation() -> void:
    var specs := _specs_for_car(_selected_car_id)
    if specs.is_empty():
        return
    # Keep the store detail pane on the live studio car after a garage
    # switch.  A tuning item for this same car stays selected; a car
    # card or another car's tuning item follows the new selection.
    if _catalog_by_id.has(_store_selected_id):
        _store_selected_id = _selected_car_id
    elif _store_selected_id.begins_with("tuning_") and not _store_selected_id.begins_with("tuning_%s_" % _selected_car_id):
        _store_selected_id = _selected_car_id
    var display_name := _car_display_name(specs)
    var tuning := _tuning_values_for(specs, int(_customization.get("tuning_level", 0)))
    if _top_car_label != null:
        _top_car_label.text = display_name
    if _top_car_summary_label != null:
        _top_car_summary_label.text = "%d л.с. • %d Нм • %d км/ч" % [
            int(specs.get("power_hp", tuning.get("power", 0))), int(specs.get("torque_nm", tuning.get("torque", 0))), int(specs.get("top_speed_kmh", 0)),
        ]
    if _home_play_button != null:
        _set_picture_card(_home_play_button, MENU_PLAY_TEXTURE, "▶  ИГРАТЬ", "%s • %s • свободная езда" % [_world_display_name(), display_name])
    if _home_car_card != null:
        _set_picture_card(_home_car_card, _texture_for_car(_selected_car_id), display_name.to_upper(), "открыть гараж →")
    if _garage_title_label != null:
        _garage_title_label.text = "%s (%d)" % [String(specs.get("name", display_name)), int(specs.get("year", 1967))]
    if _garage_category_label != null:
        _garage_category_label.text = String(specs.get("category", "АВТОМОБИЛЬ"))
    if _garage_engine_label != null:
        _garage_engine_label.text = String(specs.get("engine", "—"))
    if _garage_top_speed_label != null:
        _garage_top_speed_label.text = "%d км/ч" % int(specs.get("top_speed_kmh", 0))
    if _garage_gearbox_label != null:
        _garage_gearbox_label.text = String(specs.get("gearbox", "—"))
    if _garage_drive_label != null:
        _garage_drive_label.text = String(specs.get("drive", "—"))
    if _garage_mass_label != null:
        _garage_mass_label.text = "%s кг" % _fmt_int(int(round(float(specs.get("mass_kg", 0.0)))))
    if _garage_dimensions_label != null:
        _garage_dimensions_label.text = "%.2f × %.2f × %.2f м" % [float(specs.get("length_m", 0.0)), float(specs.get("width_m", 0.0)), float(specs.get("height_m", 0.0))]
    var ratings := specs.get("ratings", {}) as Dictionary
    for rating_key in _garage_rating_bars.keys():
        var bar := _garage_rating_bars[rating_key] as ProgressBar
        if bar == null:
            continue
        var rating_value := clampf(float(ratings.get(String(rating_key), bar.value)), 0.0, 10.0)
        bar.value = rating_value
        var row := bar.get_parent() as HBoxContainer
        if row != null:
            var value_label := row.get_node_or_null("RatingValue") as Label
            if value_label != null:
                value_label.text = "%.1f" % rating_value
    if _garage_drive_button != null:
        _garage_drive_button.text = "▶  ИГРАТЬ НА %s" % display_name.to_upper()
    if _store_hint_label != null:
        _store_hint_label.text = "3D %s • ВРАЩАЙТЕ И МАСШТАБИРУЙТЕ" % display_name.to_upper()
    if _store_drive_button != null:
        _store_drive_button.text = "▶  ИГРАТЬ НА %s" % display_name.to_upper()
    _refresh_garage_car_list()
    _refresh_garage_specs()
    _refresh_store()


func _refresh_garage_car_list() -> void:
    if _garage_cars_box == null:
        return
    for child in _garage_cars_box.get_children():
        _garage_cars_box.remove_child(child)
        child.queue_free()
    _garage_car_buttons.clear()
    var entries := _catalog_entries()
    if _garage_cars_title != null:
        _garage_cars_title.text = "МОИ АВТОМОБИЛИ (%d)" % entries.size()
    for entry_variant in entries:
        var entry: Dictionary = entry_variant
        var car_id := String(entry.get("id", entry.get("car_id", "")))
        var customization := entry.get("customization", {}) as Dictionary
        var level := int(customization.get("tuning_level", int(entry.get("tuning_level", 0))))
        var values := _tuning_values_for(entry, level)
        var selected := car_id == _selected_car_id
        var status := "выбран • живой 3D" if selected else "игровой кадр • выбрать авто"
        var button := _picture_button(
            _texture_for_car(car_id),
            _car_display_name(entry),
            "%s %d • %d л.с. • %s" % [String(values.get("class", "A")), int(values.get("pi", 612)), int(values.get("power", 0)), status],
            Vector2(0.0, 88.0),
            18
        )
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        button.modulate = Color(1.0, 0.84, 0.58) if selected else Color.WHITE
        button.pressed.connect(func() -> void:
            if car_id == _selected_car_id:
                set_garage_status("%s уже выбран." % _car_display_name(entry))
            else:
                _request_car_selection(car_id)
        )
        _garage_cars_box.add_child(button)
        _garage_car_buttons[car_id] = button


func _build_home_panel(parent: Node) -> Control:
    var vbox := _new_panel(parent, 0.10, false)
    var spacer := Control.new()
    spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
    spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    vbox.add_child(spacer)

    var bottom := HBoxContainer.new()
    bottom.add_theme_constant_override("separation", 14)
    vbox.add_child(bottom)

    var left := VBoxContainer.new()
    left.add_theme_constant_override("separation", 8)
    left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    left.size_flags_stretch_ratio = 1.55
    bottom.add_child(left)
    _label(left, "СВОБОДНЫЕ ДОРОГИ RICHTOWN", 16, Color(1.0, 0.78, 0.48), true)
    _home_goal_label = _label(left, "БЛИЖАЙШАЯ ЦЕЛЬ: до уровня 2 осталось 50.0 км", MIN_FONT_SIZE, Color(0.92, 0.96, 1.0))
    _home_goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _home_play_button = _picture_button(MENU_PLAY_TEXTURE, "▶  ИГРАТЬ", "RichTown • Shelby GT500 • свободная езда", Vector2(0.0, 172.0), 46)
    _home_play_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _home_play_button.pressed.connect(func() -> void: play_requested.emit())
    left.add_child(_home_play_button)

    var right := VBoxContainer.new()
    right.add_theme_constant_override("separation", 10)
    right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bottom.add_child(right)
    _home_world_card = _picture_button(MENU_RICHTOWN_TEXTURE, "RICHTOWN", "открыть карты и миры →", Vector2(0.0, 104.0), 22)
    _home_world_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _home_world_card.pressed.connect(func() -> void: _show_panel(PANEL_WORLDS))
    right.add_child(_home_world_card)
    _home_car_card = _picture_button(MENU_SHELBY_TEXTURE, "SHELBY GT500", "открыть гараж →", Vector2(0.0, 104.0), 22)
    _home_car_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _home_car_card.pressed.connect(func() -> void: _show_panel(PANEL_GARAGE))
    right.add_child(_home_car_card)
    _home_class_label = _label(_home_car_card, "A 612", 18, Color.WHITE, true)
    _home_class_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    _home_class_label.offset_left = -86.0
    _home_class_label.offset_top = 10.0
    _home_class_label.offset_right = -12.0
    _home_class_label.offset_bottom = 38.0
    _home_class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    return vbox.get_parent().get_parent() as Control


func _build_garage_panel(parent: Node) -> Control:
    var vbox := _new_panel(parent, 0.16, false)
    var header := HBoxContainer.new()
    header.add_theme_constant_override("separation", 14)
    vbox.add_child(header)
    _label(header, "ГАРАЖ", 27, Color.WHITE, true)
    _garage_class_label = _label(header, "КЛАСС A • ИНДЕКС 612", 15, Color(1.0, 0.76, 0.44), true)
    _garage_class_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _garage_status_label = _label(header, "", MIN_FONT_SIZE, Color(1.0, 0.78, 0.48))
    _garage_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _garage_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _garage_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

    var columns := HBoxContainer.new()
    columns.add_theme_constant_override("separation", 12)
    columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
    vbox.add_child(columns)

    var left_panel := _panel_box(columns)
    left_panel.custom_minimum_size = Vector2(300.0, 0.0)
    left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    left_panel.size_flags_stretch_ratio = 0.88
    var left := VBoxContainer.new()
    left.add_theme_constant_override("separation", 7)
    left_panel.add_child(left)
    _garage_title_label = _label(left, "Shelby GT500 (1967)", 25, Color.WHITE, true)
    _garage_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _garage_category_label = _label(left, "МАСЛКАР • ЗАДНИЙ ПРИВОД", MIN_FONT_SIZE, COL_MUTED, true)
    _garage_category_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var grid := GridContainer.new()
    grid.columns = 2
    grid.add_theme_constant_override("h_separation", 14)
    grid.add_theme_constant_override("v_separation", 3)
    left.add_child(grid)
    _garage_engine_label = _spec_row(grid, "Двигатель", "V8, 7.0 л (428 cid)")
    _garage_power_label = _spec_row(grid, "Мощность", "365 л.с. (SAE gross)")
    _garage_torque_label = _spec_row(grid, "Момент", "569 Нм при 3200")
    _garage_accel_label = _spec_row(grid, "0–100 км/ч", "6.0 с")
    _garage_top_speed_label = _spec_row(grid, "Макс. скорость", "207 км/ч")
    _garage_gearbox_label = _spec_row(grid, "Коробка", "4-ступенчатая механика")
    _garage_drive_label = _spec_row(grid, "Привод", "задний")
    _garage_mass_label = _spec_row(grid, "Масса", "1 450 кг")
    _garage_dimensions_label = _spec_row(grid, "Габариты", "4.64 × 1.84 × 1.32 м")
    for value_label in [_garage_engine_label, _garage_power_label, _garage_torque_label, _garage_accel_label, _garage_top_speed_label, _garage_gearbox_label, _garage_drive_label, _garage_mass_label, _garage_dimensions_label]:
        value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _garage_rating_bars["speed"] = _bar(left, "Скорость", 6.4, COL_ACCENT)
    _garage_rating_bars["accel"] = _bar(left, "Разгон", 6.8, COL_ACCENT)
    _garage_rating_bars["handling"] = _bar(left, "Управление", 5.2, COL_ACCENT)
    _garage_rating_bars["drift"] = _bar(left, "Дрифт", 7.5, COL_ACCENT)
    var left_spacer := Control.new()
    left_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
    left_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    left.add_child(left_spacer)
    var next_panel := _panel_box(left)
    var next_box := VBoxContainer.new()
    next_box.add_theme_constant_override("separation", 6)
    next_panel.add_child(next_box)
    _label(next_box, "СЛЕДУЮЩИЙ ШАГ ТЮНИНГА", MIN_FONT_SIZE, Color(1.0, 0.76, 0.44), true)
    _garage_next_step_label = _label(next_box, "SPORT: 394 л.с. • CR 5 000", MIN_FONT_SIZE, COL_TEXT)
    _garage_next_step_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _garage_next_step_button = _button("ОТКРЫТЬ В МАГАЗИНЕ", COL_ACCENT, Vector2(0.0, MIN_TOUCH_HEIGHT), MIN_FONT_SIZE)
    _garage_next_step_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
    _garage_next_step_button.pressed.connect(_open_next_tuning_in_store)
    next_box.add_child(_garage_next_step_button)

    _garage_drag_surface = Control.new()
    _garage_drag_surface.name = "GarageDragSurface"
    _garage_drag_surface.mouse_filter = Control.MOUSE_FILTER_STOP
    _garage_drag_surface.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _garage_drag_surface.size_flags_stretch_ratio = 1.85
    _garage_drag_surface.gui_input.connect(_on_garage_drag_input.bind(_garage_drag_surface))
    columns.add_child(_garage_drag_surface)
    var drag_hint := _label(_garage_drag_surface, "↔  ВРАЩАЙТЕ МАШИНУ • КОЛЕСО — МАСШТАБ", MIN_FONT_SIZE, Color(1, 1, 1, 0.82), true)
    drag_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
    drag_hint.offset_left = -190.0
    drag_hint.offset_top = -42.0
    drag_hint.offset_right = 190.0
    drag_hint.offset_bottom = -8.0
    drag_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

    var right_panel := _panel_box(columns)
    right_panel.custom_minimum_size = Vector2(300.0, 0.0)
    right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right_panel.size_flags_stretch_ratio = 0.92
    var scroll := ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    right_panel.add_child(scroll)
    var right := VBoxContainer.new()
    right.add_theme_constant_override("separation", 8)
    right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(right)

    _garage_cars_title = _label(right, "МОИ АВТОМОБИЛИ (4)", 15, Color.WHITE, true)
    _garage_cars_box = VBoxContainer.new()
    _garage_cars_box.add_theme_constant_override("separation", 8)
    _garage_cars_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right.add_child(_garage_cars_box)
    _refresh_garage_car_list()
    _build_garage_tuning_section(right)

    _label(right, "ЦВЕТ КУЗОВА", MIN_FONT_SIZE, COL_MUTED, true)
    var paint_row := GridContainer.new()
    paint_row.columns = 3
    paint_row.add_theme_constant_override("h_separation", 8)
    paint_row.add_theme_constant_override("v_separation", 8)
    right.add_child(paint_row)
    for option in _paint_options:
        var paint_id := String(option.get("id", "red"))
        var paint_color: Color = option.get("color", Color.RED)
        var swatch := _button("", COL_ACCENT, Vector2(MIN_TOUCH_HEIGHT, MIN_TOUCH_HEIGHT), 15)
        swatch.tooltip_text = String(option.get("name", paint_id))
        swatch.add_theme_stylebox_override("normal", _style(paint_color, COL_BORDER, 6, 1))
        swatch.add_theme_stylebox_override("hover", _style(paint_color.lightened(0.12), Color.WHITE, 6, 2))
        swatch.add_theme_stylebox_override("pressed", _style(paint_color.lightened(0.20), COL_ACCENT, 6, 2))
        swatch.pressed.connect(func() -> void:
            _customization["paint_id"] = paint_id
            _customization["paint_color"] = paint_color
            _refresh_customization_controls()
            customization_changed.emit(_customization.duplicate(true))
        )
        paint_row.add_child(swatch)
        _paint_buttons[paint_id] = swatch

    _label(right, "КОЛЁСА • ПРЕВЬЮ ДИСКОВ", MIN_FONT_SIZE, COL_MUTED, true)
    var wheel_row := GridContainer.new()
    wheel_row.columns = 2
    wheel_row.add_theme_constant_override("h_separation", 10)
    wheel_row.add_theme_constant_override("v_separation", 8)
    right.add_child(wheel_row)
    for spec in [["silver", "Серебро"], ["black", "Чёрные"], ["bronze", "Бронза"], ["white", "Белые"]]:
        var finish_id := String(spec[0])
        var cell := VBoxContainer.new()
        cell.add_theme_constant_override("separation", 3)
        cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        wheel_row.add_child(cell)
        var preview := WheelPreviewScript.new() as NativeWheelPreview
        preview.name = "WheelPreview_%s" % finish_id
        preview.custom_minimum_size = Vector2(68.0, 68.0)
        preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        preview.tooltip_text = String(spec[1])
        preview.set_finish(WHEEL_FINISH_COLORS.get(finish_id, Color(0.72, 0.75, 0.78)), false)
        preview.mouse_entered.connect(_play_hover)
        preview.focus_entered.connect(_play_hover)
        preview.pressed.connect(func() -> void:
            _play_click()
            _customization["wheel_finish"] = finish_id
            _refresh_customization_controls()
            customization_changed.emit(_customization.duplicate(true))
        )
        cell.add_child(preview)
        var finish_label := _label(cell, String(spec[1]), MIN_FONT_SIZE, COL_TEXT)
        finish_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _wheel_finish_previews[finish_id] = preview

    _label(right, "НОМЕР", MIN_FONT_SIZE, COL_MUTED, true)
    var plate_row := HBoxContainer.new()
    plate_row.add_theme_constant_override("separation", 6)
    right.add_child(plate_row)
    _plate_edit = _line_edit(String(_customization.get("license_plate", "GT500-67")), "НОМЕР")
    _plate_edit.max_length = 9
    _plate_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _plate_edit.text_submitted.connect(func(_value: String) -> void: _apply_plate_edit())
    plate_row.add_child(_plate_edit)
    var plate_apply := _button("OK", COL_ACCENT, Vector2(54.0, 42.0), 14)
    plate_apply.alignment = HORIZONTAL_ALIGNMENT_CENTER
    plate_apply.pressed.connect(_apply_plate_edit)
    plate_row.add_child(plate_apply)

    _garage_drive_button = _button("▶  ИГРАТЬ НА ЭТОМ АВТО", COL_ACCENT, Vector2(0.0, 58.0), 19)
    _garage_drive_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
    _garage_drive_button.pressed.connect(func() -> void: play_requested.emit())
    vbox.add_child(_garage_drive_button)
    _refresh_customization_controls()
    return vbox.get_parent().get_parent() as Control


func _build_garage_tuning_section(right: VBoxContainer) -> void:
    _label(right, "ТЮНИНГ • СЕЙЧАС / ВЫБРАНО", MIN_FONT_SIZE, COL_MUTED, true)
    _tuning_now_label = _label(right, "", MIN_FONT_SIZE, Color(1.0, 0.82, 0.56))
    _tuning_now_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    for level in 3:
        var tuning_button := _button("", COL_ACCENT, Vector2(0.0, MIN_TOUCH_HEIGHT), MIN_FONT_SIZE)
        tuning_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
        tuning_button.pressed.connect(func() -> void:
            _preview_tuning_level = level
            _refresh_customization_controls()
        )
        right.add_child(tuning_button)
        _tuning_buttons.append(tuning_button)
    _tuning_compare_label = _label(right, "", MIN_FONT_SIZE, COL_TEXT)
    _tuning_compare_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _tuning_action_button = _button("УСТАНОВИТЬ", COL_ACCENT, Vector2(0.0, MIN_TOUCH_HEIGHT), MIN_FONT_SIZE)
    _tuning_action_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
    _tuning_action_button.pressed.connect(_on_tuning_action_pressed)
    right.add_child(_tuning_action_button)


func _open_next_tuning_in_store() -> void:
    var owned_max := int(_customization.get("tuning_owned_max", 0))
    var next_level := clampi(owned_max + 1, 0, 2)
    _store_selected_id = "tuning_%s_%d" % [_selected_car_id, next_level]
    _store_filter = "tuning"
    _show_panel(PANEL_STORE)


func _on_garage_drag_input(event: InputEvent, surface: Control) -> void:
    if surface == null:
        return
    if event is InputEventScreenTouch:
        var touch := event as InputEventScreenTouch
        if touch.pressed:
            _garage_drag_index = touch.index
        elif touch.index == _garage_drag_index:
            _garage_drag_index = -2
        surface.accept_event()
    elif event is InputEventScreenDrag:
        var drag := event as InputEventScreenDrag
        if drag.index == _garage_drag_index:
            garage_dragged.emit(drag.relative)
            surface.accept_event()
    elif event is InputEventMouseButton:
        var button := event as InputEventMouseButton
        if button.button_index == MOUSE_BUTTON_LEFT:
            _garage_mouse_dragging = button.pressed
            surface.accept_event()
        elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
            garage_zoomed.emit(0.90)
            surface.accept_event()
        elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            garage_zoomed.emit(1.10)
            surface.accept_event()
    elif event is InputEventMouseMotion and _garage_mouse_dragging:
        garage_dragged.emit((event as InputEventMouseMotion).relative)
        surface.accept_event()


func _apply_plate_edit() -> void:
    if _plate_edit == null:
        return
    _customization["license_plate"] = _plate_edit.text.strip_edges().to_upper()
    _refresh_customization_controls()
    customization_changed.emit(_customization.duplicate(true))


func _on_tuning_action_pressed() -> void:
    var owned_max := int(_customization.get("tuning_owned_max", 0))
    if _preview_tuning_level <= owned_max:
        _customization["tuning_level"] = _preview_tuning_level
        _refresh_customization_controls()
        customization_changed.emit(_customization.duplicate(true))
    else:
        tuning_purchase_requested.emit(_preview_tuning_level)


func _tuning_values(level: int) -> Dictionary:
    return _tuning_values_for(_specs_for_car(_selected_car_id), level)


func _refresh_customization_controls() -> void:
    var paint_id := String(_customization.get("paint_id", "red"))
    for key in _paint_buttons.keys():
        var swatch := _paint_buttons[key] as Button
        swatch.text = "✓" if String(key) == paint_id else ""
    var finish_id := String(_customization.get("wheel_finish", "silver"))
    for key in _wheel_finish_previews.keys():
        var preview := _wheel_finish_previews[key] as NativeWheelPreview
        if preview != null:
            preview.set_finish(WHEEL_FINISH_COLORS.get(String(key), Color(0.72, 0.75, 0.78)), String(key) == finish_id)
    if _plate_edit != null and not _plate_edit.has_focus():
        _plate_edit.text = String(_customization.get("license_plate", String(_catalog_car(_selected_car_id).get("default_plate", "NITCHES"))))
    if _top_car_icon != null:
        _top_car_icon.set_paint_color(_customization.get("paint_color", Color(0.48, 0.025, 0.035)))

    var current_level := int(_customization.get("tuning_level", 0))
    var owned_max := int(_customization.get("tuning_owned_max", 0))
    var current := _tuning_values(current_level)
    var preview := _tuning_values(_preview_tuning_level)
    for level in _tuning_buttons.size():
        var values := _tuning_values(level)
        var suffix := " • выбран" if level == current_level else (" • открыт" if level <= owned_max else " • CR %s" % _fmt_int(TUNING_COSTS[level]))
        _tuning_buttons[level].text = "%s • %s %d • %d л.с.%s" % [TUNING_NAMES[level], String(values.get("class", "A")), int(values.get("pi", 612)), int(values.get("power", 365)), suffix]
        _tuning_buttons[level].modulate = Color(1.0, 0.80, 0.52) if level == _preview_tuning_level else Color.WHITE
    if _tuning_now_label != null:
        _tuning_now_label.text = "СЕЙЧАС: %s • %s %d • %d л.с. • %d Нм" % [
            TUNING_NAMES[current_level], String(current.get("class", "A")), int(current.get("pi", 612)),
            int(current.get("power", 365)), int(current.get("torque", 569)),
        ]
    if _tuning_compare_label != null:
        var power_delta := int(preview.get("power", 365)) - int(current.get("power", 365))
        var torque_delta := int(preview.get("torque", 569)) - int(current.get("torque", 569))
        var accel_delta := float(preview.get("accel", 6.0)) - float(current.get("accel", 6.0))
        _tuning_compare_label.text = "ВЫБРАНО: %s • %s %d\n%d л.с. (%+d) • %d Нм (%+d)\n0–100: %.1f с (%+.1f с)\n%s" % [
            TUNING_NAMES[_preview_tuning_level], String(preview.get("class", "A")), int(preview.get("pi", 612)),
            int(preview.get("power", 365)), power_delta,
            int(preview.get("torque", 569)), torque_delta,
            float(preview.get("accel", 6.0)), accel_delta,
            TUNING_DESCRIPTIONS[_preview_tuning_level],
        ]
    if _garage_next_step_label != null:
        if owned_max >= 2:
            _garage_next_step_label.text = "TRACK уже открыт. Выберите пакет справа или сравните варианты в магазине."
            if _garage_next_step_button != null:
                _garage_next_step_button.text = "СРАВНИТЬ В МАГАЗИНЕ"
        else:
            var next_level := owned_max + 1
            var next_values := _tuning_values(next_level)
            var credits := int(_profile_view.get("credits", 35000))
            var missing := maxi(TUNING_COSTS[next_level] - credits, 0)
            _garage_next_step_label.text = "%s: %d л.с. • %d Нм • CR %s%s" % [
                TUNING_NAMES[next_level], int(next_values.get("power", 365)), int(next_values.get("torque", 569)),
                _fmt_int(TUNING_COSTS[next_level]), " • хватает кредитов" if missing == 0 else " • не хватает CR %s" % _fmt_int(missing),
            ]
            if _garage_next_step_button != null:
                _garage_next_step_button.text = "ОТКРЫТЬ %s В МАГАЗИНЕ" % TUNING_NAMES[next_level]
    if _tuning_action_button != null:
        if _preview_tuning_level == current_level:
            _tuning_action_button.text = "%s УЖЕ ВЫБРАН" % TUNING_NAMES[_preview_tuning_level]
            _tuning_action_button.disabled = true
        elif _preview_tuning_level <= owned_max:
            _tuning_action_button.text = "ВЫБРАТЬ %s" % TUNING_NAMES[_preview_tuning_level]
            _tuning_action_button.disabled = false
        else:
            _tuning_action_button.text = "КУПИТЬ %s • CR %s" % [TUNING_NAMES[_preview_tuning_level], _fmt_int(TUNING_COSTS[_preview_tuning_level])]
            _tuning_action_button.disabled = false
    _refresh_garage_specs()
    _refresh_store()


func _refresh_garage_specs() -> void:
    var specs := _specs_for_car(_selected_car_id)
    var values := _tuning_values(int(_customization.get("tuning_level", 0)))
    var class_text := "КЛАСС %s • ИНДЕКС %d" % [String(values.get("class", "A")), int(values.get("pi", 612))]
    if _garage_class_label != null:
        _garage_class_label.text = class_text
    if _home_class_label != null:
        _home_class_label.text = "%s %d" % [String(values.get("class", "A")), int(values.get("pi", 612))]
    if _garage_power_label != null:
        var power_note := String(specs.get("power_note", ""))
        _garage_power_label.text = "%d л.с.%s" % [int(values.get("power", 365)), (" (%s)" % power_note) if int(_customization.get("tuning_level", 0)) == 0 and not power_note.is_empty() else (" (тюнинг)" if int(_customization.get("tuning_level", 0)) > 0 else "")]
    if _garage_torque_label != null:
        _garage_torque_label.text = "%d Нм при %d" % [int(values.get("torque", 569)), int(specs.get("torque_rpm", 3200))]
    if _garage_accel_label != null:
        _garage_accel_label.text = "%.1f с" % float(values.get("accel", float(specs.get("accel_0_100_s", 6.0))))


func set_garage_status(text: String) -> void:
    if _garage_status_label != null:
        _garage_status_label.text = text
    if _store_status_label != null:
        _store_status_label.text = text


func bind_customization(customization: Dictionary) -> void:
    for key in customization.keys():
        _customization[key] = customization[key]
    if customization.has("car_id"):
        _selected_car_id = NativeCarCatalog.normalize_id(String(customization.get("car_id", _selected_car_id)))
    _preview_tuning_level = int(_customization.get("tuning_level", 0))
    _customization_bound = true
    set_garage_status("")
    _refresh_customization_controls()


func _build_store_panel(parent: Node) -> Control:
    var vbox := _new_panel(parent, 0.16, false)
    var header := HBoxContainer.new()
    header.add_theme_constant_override("separation", 14)
    vbox.add_child(header)
    _label(header, "МАГАЗИН", 27, Color.WHITE, true)
    _store_status_label = _label(header, "", MIN_FONT_SIZE, Color(1.0, 0.78, 0.48))
    _store_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _store_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _store_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _store_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _store_balance_label = _label(header, "CR 35 000", 17, Color(1.0, 0.78, 0.42), true)
    _store_balance_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

    var columns := HBoxContainer.new()
    columns.add_theme_constant_override("separation", 12)
    columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
    vbox.add_child(columns)

    var catalog_panel := _panel_box(columns)
    catalog_panel.custom_minimum_size = Vector2(300.0, 0.0)
    catalog_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    catalog_panel.size_flags_stretch_ratio = 0.92
    var catalog := VBoxContainer.new()
    catalog.add_theme_constant_override("separation", 8)
    catalog_panel.add_child(catalog)
    _label(catalog, "КАТАЛОГ • ТОЛЬКО РЕАЛЬНЫЙ КОНТЕНТ", MIN_FONT_SIZE, Color.WHITE, true)
    var filter_row := HBoxContainer.new()
    filter_row.add_theme_constant_override("separation", 6)
    catalog.add_child(filter_row)
    var filter_group := ButtonGroup.new()
    for spec in [["all", "ВСЁ"], ["cars", "МАШИНЫ"], ["tuning", "ТЮНИНГ"]]:
        var filter_id := String(spec[0])
        var filter_button := _button(String(spec[1]), COL_ACCENT, Vector2(0.0, MIN_TOUCH_HEIGHT), MIN_FONT_SIZE)
        filter_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
        filter_button.toggle_mode = true
        filter_button.button_group = filter_group
        filter_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        filter_button.pressed.connect(func() -> void:
            _store_filter = filter_id
            _refresh_store()
        )
        filter_row.add_child(filter_button)
        _store_filter_buttons[filter_id] = filter_button
    _store_sort_button = _button("СОРТИРОВКА: ЦЕНА ↑", COL_ACCENT, Vector2(0.0, MIN_TOUCH_HEIGHT), MIN_FONT_SIZE)
    _store_sort_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
    _store_sort_button.pressed.connect(_cycle_store_sort)
    catalog.add_child(_store_sort_button)
    var cards_scroll := ScrollContainer.new()
    cards_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    cards_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    catalog.add_child(cards_scroll)
    _store_cards_box = VBoxContainer.new()
    _store_cards_box.add_theme_constant_override("separation", 8)
    _store_cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    cards_scroll.add_child(_store_cards_box)

    _store_drag_surface = Control.new()
    _store_drag_surface.name = "StoreDragSurface0236"
    _store_drag_surface.mouse_filter = Control.MOUSE_FILTER_STOP
    _store_drag_surface.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _store_drag_surface.size_flags_stretch_ratio = 1.70
    _store_drag_surface.gui_input.connect(_on_garage_drag_input.bind(_store_drag_surface))
    columns.add_child(_store_drag_surface)
    _store_hint_label = _label(_store_drag_surface, "3D АВТО • ВРАЩАЙТЕ И МАСШТАБИРУЙТЕ", MIN_FONT_SIZE, Color(1, 1, 1, 0.84), true)
    var store_hint := _store_hint_label
    store_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
    store_hint.offset_left = -205.0
    store_hint.offset_top = -42.0
    store_hint.offset_right = 205.0
    store_hint.offset_bottom = -8.0
    store_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

    var detail_panel := _panel_box(columns)
    detail_panel.custom_minimum_size = Vector2(300.0, 0.0)
    detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    detail_panel.size_flags_stretch_ratio = 0.92
    var details := VBoxContainer.new()
    details.add_theme_constant_override("separation", 8)
    detail_panel.add_child(details)
    _label(details, "ВЫБРАННЫЙ ТОВАР", MIN_FONT_SIZE, COL_MUTED, true)
    _store_detail_title = _label(details, "Shelby GT500 '67", 24, Color.WHITE, true)
    _store_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _store_detail_label = _label(details, "", MIN_FONT_SIZE, COL_TEXT)
    _store_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _store_detail_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _store_action_button = _button("ОТКРЫТЬ В ГАРАЖЕ", COL_ACCENT, Vector2(0.0, 54.0), 16)
    _store_action_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
    _store_action_button.pressed.connect(_on_store_action_pressed)
    details.add_child(_store_action_button)
    var honesty_note := _label(details, "Магазин показывает только четыре машины с реальными 3D-моделями, физикой и звуком, а также тюнинг выбранного авто. Фейковых машин без моделей здесь нет.", MIN_FONT_SIZE, COL_MUTED)
    honesty_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

    _store_drive_button = _button("▶  ИГРАТЬ НА ВЫБРАННОМ АВТО", COL_ACCENT, Vector2(0.0, 56.0), 18)
    _store_drive_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
    _store_drive_button.pressed.connect(func() -> void: play_requested.emit())
    vbox.add_child(_store_drive_button)
    _refresh_store()
    return vbox.get_parent().get_parent() as Control


func _store_items() -> Array[Dictionary]:
    var items: Array[Dictionary] = []
    for entry_variant in _catalog_entries():
        var entry: Dictionary = entry_variant
        var car_id := String(entry.get("id", entry.get("car_id", "")))
        var car_customization := entry.get("customization", {}) as Dictionary
        var level := int(car_customization.get("tuning_level", int(entry.get("tuning_level", 0))))
        if car_id == _selected_car_id:
            level = int(_customization.get("tuning_level", level))
        var values := _tuning_values_for(entry, level)
        items.append({
            "id": car_id,
            "car_id": car_id,
            "type": "cars",
            "name": _car_display_name(entry),
            "price": 0,
            "power": int(values.get("power", entry.get("power_hp", 0))),
            "torque": int(values.get("torque", entry.get("torque_nm", 0))),
            "accel": float(values.get("accel", entry.get("accel_0_100_s", 6.0))),
            "pi": int(values.get("pi", entry.get("performance_index", 612))),
            "class": String(values.get("class", entry.get("class_label", "A"))),
            "level": -1,
            "specs": entry.duplicate(true),
        })
    var selected_specs := _specs_for_car(_selected_car_id)
    for level in TUNING_NAMES.size():
        var values := _tuning_values(level)
        items.append({
            "id": "tuning_%s_%d" % [_selected_car_id, level],
            "car_id": _selected_car_id,
            "type": "tuning",
            "name": "Тюнинг %s • %s" % [TUNING_NAMES[level], _car_display_name(selected_specs)],
            "price": TUNING_COSTS[level],
            "power": int(values.get("power", selected_specs.get("power_hp", 365))),
            "torque": int(values.get("torque", selected_specs.get("torque_nm", 569))),
            "accel": float(values.get("accel", selected_specs.get("accel_0_100_s", 6.0))),
            "pi": int(values.get("pi", selected_specs.get("performance_index", 612))),
            "class": String(values.get("class", selected_specs.get("class_label", "A"))),
            "level": level,
            "specs": selected_specs.duplicate(true),
        })
    return items


func _store_sort_less(a: Dictionary, b: Dictionary) -> bool:
    match _store_sort:
        "power":
            if int(a.get("power", 0)) != int(b.get("power", 0)):
                return int(a.get("power", 0)) > int(b.get("power", 0))
        "name":
            return String(a.get("name", "")) < String(b.get("name", ""))
        _:
            if int(a.get("price", 0)) != int(b.get("price", 0)):
                return int(a.get("price", 0)) < int(b.get("price", 0))
            if int(a.get("power", 0)) != int(b.get("power", 0)):
                return int(a.get("power", 0)) > int(b.get("power", 0))
    return String(a.get("name", "")) < String(b.get("name", ""))


func _cycle_store_sort() -> void:
    match _store_sort:
        "price":
            _store_sort = "power"
        "power":
            _store_sort = "name"
        _:
            _store_sort = "price"
    _refresh_store()


func _store_item_status(item: Dictionary) -> String:
    if String(item.get("type", "")) == "cars":
        return "ВЫБРАН" if String(item.get("car_id", item.get("id", ""))) == _selected_car_id else "В ГАРАЖЕ"
    var level := int(item.get("level", 0))
    var current_level := int(_customization.get("tuning_level", 0))
    var owned_max := int(_customization.get("tuning_owned_max", 0))
    if level == current_level:
        return "УСТАНОВЛЕН"
    if level <= owned_max:
        return "ОТКРЫТ"
    return "CR %s" % _fmt_int(int(item.get("price", 0)))


func _refresh_store() -> void:
    if _store_cards_box == null:
        return
    for key in _store_filter_buttons.keys():
        (_store_filter_buttons[key] as Button).button_pressed = String(key) == _store_filter
    if _store_sort_button != null:
        _store_sort_button.text = "СОРТИРОВКА: ЦЕНА ↑" if _store_sort == "price" else ("СОРТИРОВКА: МОЩНОСТЬ ↓" if _store_sort == "power" else "СОРТИРОВКА: ИМЯ А–Я")
    for child in _store_cards_box.get_children():
        _store_cards_box.remove_child(child)
        child.queue_free()
    _store_card_buttons.clear()
    var items := _store_items()
    items.sort_custom(_store_sort_less)
    var visible_items: Array[Dictionary] = []
    for item in items:
        if _store_filter == "all" or String(item.get("type", "")) == _store_filter:
            visible_items.append(item)
    var selected_visible := false
    for item in visible_items:
        if String(item.get("id", "")) == _store_selected_id:
            selected_visible = true
    if not selected_visible and not visible_items.is_empty():
        _store_selected_id = String(visible_items[0].get("id", "shelby_gt500"))
    for item in visible_items:
        var item_id := String(item.get("id", ""))
        var status := _store_item_status(item)
        var button: Button
        var item_car_id := String(item.get("car_id", item_id))
        if String(item.get("type", "")) == "cars":
            button = _picture_button(_texture_for_car(item_car_id), String(item.get("name", "Автомобиль")), "%s %d • %d л.с. • %s" % [String(item.get("class", "A")), int(item.get("pi", 612)), int(item.get("power", 0)), status], Vector2(0.0, 98.0), 19)
        else:
            button = _tile(String(item.get("name", "Тюнинг")), "%s %d • %d л.с. • %.1f с • %s" % [String(item.get("class", "A")), int(item.get("pi", 612)), int(item.get("power", 0)), float(item.get("accel", 6.0)), status], COL_ACCENT, Vector2(0.0, 84.0), 20)
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        button.modulate = Color(1.0, 0.82, 0.56) if item_id == _store_selected_id else Color.WHITE
        button.pressed.connect(func() -> void:
            _store_selected_id = item_id
            if String(item.get("type", "")) == "cars":
                _request_car_selection(item_car_id)
            elif item_id.begins_with("tuning_"):
                _preview_tuning_level = int(item.get("level", 0))
            _refresh_store()
        )
        _store_cards_box.add_child(button)
        _store_card_buttons[item_id] = button
    _refresh_store_details()


func _refresh_store_details() -> void:
    if _store_detail_title == null or _store_detail_label == null or _store_action_button == null:
        return
    var credits := int(_profile_view.get("credits", 35000))
    if _store_balance_label != null:
        _store_balance_label.text = "CR %s" % _fmt_int(credits)
    var selected: Dictionary = {}
    for item in _store_items():
        if String(item.get("id", "")) == _store_selected_id:
            selected = item
            break
    if selected.is_empty():
        return
    _store_detail_title.text = String(selected.get("name", "Автомобиль"))
    if String(selected.get("type", "")) == "cars":
        var car_specs := selected.get("specs", {}) as Dictionary
        var car_id := String(selected.get("car_id", selected.get("id", "")))
        var is_selected_car := car_id == _selected_car_id
        var ratings := car_specs.get("ratings", {}) as Dictionary
        _store_detail_label.text = "СТАТУС: %s\n\n%s\nДвигатель: %s\nКласс %s • индекс %d\nМощность: %d л.с.\nМомент: %d Нм при %d\n0–100 км/ч: %.1f с\nМакс. скорость: %d км/ч\nКоробка: %s\nПривод: %s\nМасса: %s кг\nГабариты: %.2f × %.2f × %.2f м\n\nСкорость %.1f • Разгон %.1f\nУправление %.1f • Дрифт %.1f\n\nРеальная 3D-модель уже показана в студии по центру. Выбор меняет модель, физику, звук, камеру и отдельную кастомизацию этой машины." % [
            "выбран сейчас" if is_selected_car else "уже в вашем гараже",
            String(car_specs.get("category", "АВТОМОБИЛЬ")),
            String(car_specs.get("engine", "—")),
            String(selected.get("class", "A")), int(selected.get("pi", 612)), int(selected.get("power", 0)), int(selected.get("torque", 0)), int(car_specs.get("torque_rpm", 0)), float(selected.get("accel", 6.0)),
            int(car_specs.get("top_speed_kmh", 0)), String(car_specs.get("gearbox", "—")), String(car_specs.get("drive", "—")),
            _fmt_int(int(round(float(car_specs.get("mass_kg", 0.0))))), float(car_specs.get("length_m", 0.0)), float(car_specs.get("width_m", 0.0)), float(car_specs.get("height_m", 0.0)),
            float(ratings.get("speed", 0.0)), float(ratings.get("accel", 0.0)), float(ratings.get("handling", 0.0)), float(ratings.get("drift", 0.0)),
        ]
        _store_action_button.text = "ОТКРЫТЬ В ГАРАЖЕ" if is_selected_car else "ВЫБРАТЬ АВТО"
        _store_action_button.disabled = false
        return
    var level := int(selected.get("level", 0))
    var current_level := int(_customization.get("tuning_level", 0))
    var owned_max := int(_customization.get("tuning_owned_max", 0))
    var current := _tuning_values(current_level)
    var price := int(selected.get("price", 0))
    var missing := maxi(price - credits, 0)
    var status_line := "Установлен сейчас" if level == current_level else ("Открыт и готов к установке" if level <= owned_max else "Цена: CR %s" % _fmt_int(price))
    if level > owned_max and missing > 0:
        status_line += "\nНе хватает: CR %s" % _fmt_int(missing)
    _store_detail_label.text = "%s\n\nСЕЙЧАС: %s • %d л.с. • %d Нм • %.1f с\nВЫБРАНО: %s • %d л.с. (%+d) • %d Нм (%+d) • %.1f с (%+.1f с)\nКласс/индекс: %s %d → %s %d\n\n%s" % [
        TUNING_DESCRIPTIONS[level],
        TUNING_NAMES[current_level], int(current.get("power", 365)), int(current.get("torque", 569)), float(current.get("accel", 6.0)),
        TUNING_NAMES[level], int(selected.get("power", 365)), int(selected.get("power", 365)) - int(current.get("power", 365)),
        int(selected.get("torque", 569)), int(selected.get("torque", 569)) - int(current.get("torque", 569)),
        float(selected.get("accel", 6.0)), float(selected.get("accel", 6.0)) - float(current.get("accel", 6.0)),
        String(current.get("class", "A")), int(current.get("pi", 612)), String(selected.get("class", "A")), int(selected.get("pi", 612)),
        status_line,
    ]
    if level == current_level:
        _store_action_button.text = "%s УЖЕ УСТАНОВЛЕН" % TUNING_NAMES[level]
        _store_action_button.disabled = true
    elif level <= owned_max:
        _store_action_button.text = "УСТАНОВИТЬ %s" % TUNING_NAMES[level]
        _store_action_button.disabled = false
    else:
        _store_action_button.text = "КУПИТЬ И УСТАНОВИТЬ • CR %s" % _fmt_int(price)
        _store_action_button.disabled = false


func _on_store_action_pressed() -> void:
    for item in _store_items():
        if String(item.get("id", "")) != _store_selected_id:
            continue
        if String(item.get("type", "")) == "cars":
            var car_id := String(item.get("car_id", item.get("id", "")))
            if car_id == _selected_car_id:
                _show_panel(PANEL_GARAGE)
            else:
                _request_car_selection(car_id)
            return
        _preview_tuning_level = int(item.get("level", 0))
        _refresh_customization_controls()
        _on_tuning_action_pressed()
        _refresh_store()
        return


func _avatar_glyph(avatar_id: String) -> String:
    match avatar_id:
        "star":
            return "★"
        "flag":
            return "⚑"
        "helmet":
            return "♞"
        _:
            return "◎"


func _build_profile_panel(parent: Node) -> Control:
    var vbox := _new_panel(parent, 0.52)
    _label(vbox, "ПРОФИЛЬ ВОДИТЕЛЯ", 27, Color.WHITE, true)
    _profile_scroll = ScrollContainer.new()
    _profile_scroll.name = "ProfileSingleScroll0236"
    _profile_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    _profile_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    vbox.add_child(_profile_scroll)
    var columns := HBoxContainer.new()
    columns.add_theme_constant_override("separation", 14)
    columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _profile_scroll.add_child(columns)

    var left_panel := _panel_box(columns)
    left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var left := VBoxContainer.new()
    left.add_theme_constant_override("separation", 8)
    left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    left_panel.add_child(left)
    _profile_avatar_icon = AvatarIconScript.new() as NativeAvatarIcon
    _profile_avatar_icon.custom_minimum_size = Vector2(118.0, 118.0)
    _profile_avatar_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    left.add_child(_profile_avatar_icon)
    var avatar_row := HBoxContainer.new()
    avatar_row.add_theme_constant_override("separation", 6)
    avatar_row.alignment = BoxContainer.ALIGNMENT_CENTER
    left.add_child(avatar_row)
    for spec in [["wheel", "◎"], ["star", "★"], ["flag", "⚑"], ["helmet", "♞"]]:
        var avatar_id := String(spec[0])
        var avatar_button := _button(String(spec[1]), COL_ACCENT, Vector2(48.0, 42.0), 20)
        avatar_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
        avatar_button.pressed.connect(func() -> void:
            _avatar_id = avatar_id
            profile_changed.emit(_nickname_edit.text.strip_edges(), _avatar_id)
        )
        avatar_row.add_child(avatar_button)
    _nickname_edit = _line_edit("ИГРОК", "НИК")
    _nickname_edit.max_length = 18
    left.add_child(_nickname_edit)
    var save_name := _button("СОХРАНИТЬ НИК И АВАТАР", COL_ACCENT, Vector2(0.0, 42.0), 13)
    save_name.alignment = HORIZONTAL_ALIGNMENT_CENTER
    save_name.pressed.connect(func() -> void: profile_changed.emit(_nickname_edit.text.strip_edges(), _avatar_id))
    left.add_child(save_name)
    _p_name = _label(left, "ИГРОК", 24, Color.WHITE, true)
    _p_level = _label(left, "Уровень: 1", 16, COL_TEXT)
    _xp_bar = ProgressBar.new()
    _xp_bar.min_value = 0.0
    _xp_bar.max_value = 1.0
    _xp_bar.value = 0.0
    _xp_bar.show_percentage = false
    _xp_bar.custom_minimum_size = Vector2(0.0, 14.0)
    _xp_bar.add_theme_stylebox_override("background", _style(Color(1, 1, 1, 0.10), COL_BORDER, 3, 0))
    _xp_bar.add_theme_stylebox_override("fill", _style(COL_ACCENT, COL_ACCENT, 3, 0))
    left.add_child(_xp_bar)
    _xp_label = _label(left, "XP: 0% до следующего уровня", 12, COL_MUTED)
    _p_credits = _label(left, "Кредиты: CR 35 000", 16, COL_TEXT)
    _p_distance = _label(left, "Пробег: 0.0 км", 16, COL_TEXT)
    _p_top = _label(left, "Рекорд скорости: 0 км/ч", 16, COL_TEXT)
    _p_drift = _label(left, "Рекорд дрифта: 0°", 16, COL_TEXT)
    _p_time = _label(left, "Время за рулём: 0 мин", 16, COL_TEXT)

    var right := VBoxContainer.new()
    right.add_theme_constant_override("separation", 12)
    right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right.size_flags_stretch_ratio = 1.35
    columns.add_child(right)
    var achievements_panel := _panel_box(right)
    var achievements_box := VBoxContainer.new()
    achievements_panel.add_child(achievements_box)
    _label(achievements_box, "ДОСТИЖЕНИЯ И НАГРАДЫ", 15, Color.WHITE, true)
    _achievements_box = VBoxContainer.new()
    _achievements_box.add_theme_constant_override("separation", 8)
    achievements_box.add_child(_achievements_box)
    var history_panel := _panel_box(right)
    var history_box := VBoxContainer.new()
    history_panel.add_child(history_box)
    _label(history_box, "ИСТОРИЯ ЗАЕЗДОВ", 15, Color.WHITE, true)
    _history_box = VBoxContainer.new()
    _history_box.add_theme_constant_override("separation", 7)
    history_box.add_child(_history_box)
    var car_panel := _panel_box(right)
    var car_box := VBoxContainer.new()
    car_panel.add_child(car_box)
    _label(car_box, "СТАТИСТИКА ПО МАШИНАМ", 15, Color.WHITE, true)
    _car_stats_label = _label(car_box, "Автомобили — 0.0 км", MIN_FONT_SIZE, COL_TEXT)
    _car_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    return vbox.get_parent().get_parent() as Control


func _build_worlds_panel(parent: Node) -> Control:
    var vbox := _new_panel(parent, 0.30)
    _label(vbox, "КАРТЫ И МИРЫ", 27, Color.WHITE, true)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    vbox.add_child(row)
    _richtown_card = _picture_button(MENU_WORLD_TEXTURE, "RICHTOWN", "игровой обзор города • побережье • Остров-Пальма", Vector2(0.0, 224.0), 34)
    _richtown_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _richtown_card.size_flags_stretch_ratio = 1.7
    _richtown_card.pressed.connect(func() -> void: _on_world_card_pressed("richtown"))
    row.add_child(_richtown_card)
    var locked_column := VBoxContainer.new()
    locked_column.add_theme_constant_override("separation", 12)
    locked_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(locked_column)
    var mountains_subtitle := "открывается на уровне %d • мир в разработке" % WORLD_MOUNTAINS_REQUIRED_LEVEL
    if WORLDS_FREE_FOR_ALL:
        mountains_subtitle = "бесплатно • мир в разработке"
    var locked_specs := [
        ["СЕВЕРНЫЕ ГОРЫ", mountains_subtitle],
    ]
    for spec in locked_specs:
        var locked := _tile(String(spec[0]), String(spec[1]), COL_LOCKED, Vector2(0.0, 106.0), 21)
        locked.disabled = true # This world is not built yet; free mode removes only its level gate.
        locked.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        if not WORLDS_FREE_FOR_ALL:
            var lock_icon := LockIconScript.new() as NativeLockIcon
            lock_icon.set_anchors_preset(Control.PRESET_TOP_RIGHT)
            lock_icon.offset_left = -46.0
            lock_icon.offset_top = 12.0
            lock_icon.offset_right = -12.0
            lock_icon.offset_bottom = 46.0
            locked.add_child(lock_icon)
        locked_column.add_child(locked)
    var desert_card_subtitle_text := "нужно накопить CR %s" % _fmt_int(WORLD_CANYON_REQUIRED_CREDITS)
    if WORLDS_FREE_FOR_ALL:
        desert_card_subtitle_text = "бесплатно • открыт для всех игроков"
    _desert_card = _tile("ПУСТЫННЫЙ КАНЬОН", desert_card_subtitle_text, Color(0.78, 0.50, 0.24), Vector2(0.0, 106.0), 21)
    _desert_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    for child in _desert_card.get_children():
        if child is Label:
            _desert_card_subtitle = child as Label
    _desert_lock_icon = LockIconScript.new() as NativeLockIcon
    _desert_lock_icon.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    _desert_lock_icon.offset_left = -46.0
    _desert_lock_icon.offset_top = 12.0
    _desert_lock_icon.offset_right = -12.0
    _desert_lock_icon.offset_bottom = 46.0
    _desert_card.add_child(_desert_lock_icon)
    _desert_card.pressed.connect(func() -> void: _on_world_card_pressed("desert"))
    locked_column.add_child(_desert_card)
    _forest_card = _tile("ЗЕЛЁНЫЙ ЛЕС", "бесплатно • открыт • 4×4 км • озеро • холмы • ферма", Color(0.30, 0.55, 0.28), Vector2(0.0, 106.0), 21)
    _forest_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    for child in _forest_card.get_children():
        if child is Label:
            _forest_card_subtitle = child as Label
    _forest_card.pressed.connect(func() -> void: _on_world_card_pressed("greenforest"))
    locked_column.add_child(_forest_card)

    var detail_panel := _panel_box(vbox)
    detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    var detail_row := HBoxContainer.new()
    detail_row.add_theme_constant_override("separation", 20)
    detail_panel.add_child(detail_row)
    var description_box := VBoxContainer.new()
    description_box.add_theme_constant_override("separation", 6)
    description_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    description_box.size_flags_stretch_ratio = 1.35
    detail_row.add_child(description_box)
    _world_title_label = _label(description_box, "RICHTOWN — ТЕКУЩИЙ МИР", 18, Color.WHITE, true)
    _world_detail_label = _label(description_box, "Открытый прибрежный город: центральный деловой район и главная башня, мечеть, опера и бульвары с кафе, центральный парк, набережная, порт и Остров-Пальма. Полноэкранная карта строит маршрут по настоящим дорогам, показывает районы и точки интереса, а быстрый переход переносит выбранный автомобиль к выбранному месту.", MIN_FONT_SIZE, COL_TEXT)
    _world_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var progress_box := VBoxContainer.new()
    progress_box.add_theme_constant_override("separation", 6)
    progress_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    detail_row.add_child(progress_box)
    _label(progress_box, "ПРОГРЕСС К НОВЫМ МИРАМ", 18, Color(1.0, 0.76, 0.44), true)
    _world_progress_label = _label(progress_box, "", MIN_FONT_SIZE, COL_TEXT)
    _world_progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _update_world_progress()

    _world_map_button = _button("⌖  ОТКРЫТЬ КАРТУ RICHTOWN", COL_ACCENT, Vector2(0.0, 56.0), 18)
    _world_map_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
    _world_map_button.pressed.connect(func() -> void: world_map_requested.emit())
    vbox.add_child(_world_map_button)
    _refresh_world_cards()
    return vbox.get_parent().get_parent() as Control


func _slider_row(parent: Node, key: String, caption: String, minimum: float, maximum: float, step: float) -> HSlider:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    parent.add_child(row)
    var cap := _label(row, caption, 14, COL_MUTED)
    cap.custom_minimum_size = Vector2(190.0, 0.0)
    cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    var slider := HSlider.new()
    slider.min_value = minimum
    slider.max_value = maximum
    slider.step = step
    slider.custom_minimum_size = Vector2(0.0, MIN_TOUCH_HEIGHT)
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(slider)
    var value_label := _label(row, "", 14, COL_TEXT)
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
    var vbox := _new_panel(parent, 0.58)
    _label(vbox, "НАСТРОЙКИ", 27, Color.WHITE, true)
    var columns := HBoxContainer.new()
    columns.add_theme_constant_override("separation", 20)
    columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
    vbox.add_child(columns)

    var left := VBoxContainer.new()
    left.add_theme_constant_override("separation", 9)
    left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    left.size_flags_stretch_ratio = 1.25
    columns.add_child(left)
    _label(left, "УПРАВЛЕНИЕ", 18, Color.WHITE, true)
    _label(left, "Тип управления", 14, COL_MUTED)
    var type_row := HBoxContainer.new()
    type_row.add_theme_constant_override("separation", 8)
    left.add_child(type_row)
    var group := ButtonGroup.new()
    for spec in [["wheel", "РУЛЬ"], ["tilt", "НАКЛОН"], ["arrows", "СТРЕЛКИ"]]:
        var control_type := String(spec[0])
        var button := _button(String(spec[1]), COL_ACCENT, Vector2(0.0, 50.0), 15)
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
    var tilt_note := _label(left, "НАКЛОН автоматически запоминает текущее положение телефона как центр при включении.", MIN_FONT_SIZE, COL_MUTED)
    tilt_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

    var right := VBoxContainer.new()
    right.add_theme_constant_override("separation", 9)
    right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    columns.add_child(right)
    _label(right, "ИГРА И ПАУЗА", 18, Color.WHITE, true)
    _camera_setting_button = _button("КАМЕРА: ВИД СЗАДИ", COL_ACCENT, Vector2(0.0, 52.0), 16)
    _camera_setting_button.pressed.connect(func() -> void: camera_cycle_requested.emit())
    right.add_child(_camera_setting_button)
    _time_setting_button = _button("ВРЕМЯ СУТОК: ДЕНЬ", COL_ACCENT, Vector2(0.0, 52.0), 16)
    _time_setting_button.pressed.connect(func() -> void: time_cycle_requested.emit())
    right.add_child(_time_setting_button)
    _sound_toggle = _button("ЗВУК: ВКЛ", COL_ACCENT, Vector2(0.0, 52.0), 16)
    _sound_toggle.pressed.connect(func() -> void:
        _settings["sound_enabled"] = not bool(_settings.get("sound_enabled", true))
        _refresh_settings_controls()
        _emit_settings()
    )
    right.add_child(_sound_toggle)
    _label(right, "Качество графики", 14, COL_MUTED)
    var graphics_row := HBoxContainer.new()
    graphics_row.add_theme_constant_override("separation", 8)
    right.add_child(graphics_row)
    var graphics_group := ButtonGroup.new()
    for spec in [["performance", "СКОРОСТЬ"], ["balanced", "БАЛАНС"], ["beauty", "КРАСОТА"]]:
        var quality_id := String(spec[0])
        var quality_button := _button(String(spec[1]), COL_ACCENT, Vector2(0.0, 50.0), 15)
        quality_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
        quality_button.toggle_mode = true
        quality_button.button_group = graphics_group
        quality_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        quality_button.pressed.connect(func() -> void:
            _settings["graphics_quality"] = quality_id
            _refresh_settings_controls()
            _emit_settings()
        )
        graphics_row.add_child(quality_button)
        _graphics_buttons[quality_id] = quality_button
    _graphics_note_label = _label(right, "", MIN_FONT_SIZE, COL_MUTED)
    _graphics_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var continue_button := _button("▶  ПРОДОЛЖИТЬ", COL_ACCENT, Vector2(0.0, 56.0), 18)
    continue_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
    continue_button.pressed.connect(func() -> void: play_requested.emit())
    right.add_child(continue_button)
    var spacer := Control.new()
    spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
    right.add_child(spacer)
    _developer_status_label = _label(right, "режим разработчика выключен", MIN_FONT_SIZE, COL_MUTED)
    _developer_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _version_button = _button("Nitches 0.2.59-native-alpha", COL_LOCKED, Vector2(0.0, MIN_TOUCH_HEIGHT), MIN_FONT_SIZE)
    _version_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
    _version_button.pressed.connect(_on_version_pressed)
    right.add_child(_version_button)
    var audio_credit := _label(right, "Звук: Altair78 (CC BY-SA 4.0) • шины: Tom Haigh (CC BY 3.0) • остальные записи: CC0, список — docs/AUDIO_CREDITS.md", MIN_FONT_SIZE, COL_MUTED)
    audio_credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    audio_credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
    var graphics_quality := String(_settings.get("graphics_quality", "balanced"))
    for key in _graphics_buttons.keys():
        (_graphics_buttons[key] as Button).button_pressed = String(key) == graphics_quality
    if _graphics_note_label != null:
        match graphics_quality:
            "performance":
                _graphics_note_label.text = "СКОРОСТЬ: короче дальность детализации и теней, меньше частиц, масштаб рендера 80% — для слабых телефонов."
            "beauty":
                _graphics_note_label.text = "КРАСОТА: максимальная дальность детализации листвы и теней, полные атмосферные эффекты."
            _:
                _graphics_note_label.text = "БАЛАНС: стандартные дальность детализации, тени и атмосферные эффекты."
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
    _specs = specs.duplicate(true)
    _car_name = String(specs.get("name", ""))
    if not String(specs.get("car_id", "")).is_empty():
        _selected_car_id = NativeCarCatalog.normalize_id(String(specs.get("car_id", _selected_car_id)))
    _specs_bound = not _selected_car_id.is_empty() and int(specs.get("power_hp", 0)) > 0 and int(specs.get("torque_nm", 0)) > 0 and int(specs.get("top_speed_kmh", 0)) > 0 and int(specs.get("gears", 0)) > 0
    _refresh_customization_controls()
    _refresh_car_presentation()


func _format_progress_value(value: float, unit: String) -> String:
    if unit == "км":
        return "%.1f" % value
    if unit == "мин":
        return "%.0f" % value
    return "%d" % int(round(value))


func _refresh_achievement_cards(items: Array) -> void:
    if _achievements_box == null:
        return
    for child in _achievements_box.get_children():
        _achievements_box.remove_child(child)
        child.queue_free()
    _achievement_card_count = 0
    for item_variant in items:
        var item: Dictionary = item_variant
        var card := PanelContainer.new()
        card.add_theme_stylebox_override("panel", _style(Color(1, 1, 1, 0.055), Color(1, 1, 1, 0.10), 6, 1))
        _achievements_box.add_child(card)
        var box := VBoxContainer.new()
        box.add_theme_constant_override("separation", 4)
        card.add_child(box)
        var header := HBoxContainer.new()
        header.add_theme_constant_override("separation", 8)
        box.add_child(header)
        var unlocked := bool(item.get("unlocked", false))
        _label(header, "★" if unlocked else "☆", 18, Color(1.0, 0.78, 0.42) if unlocked else COL_MUTED, true)
        var title := _label(header, String(item.get("title", "Достижение")), 16, Color.WHITE, true)
        title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _label(header, "ОТКРЫТО" if unlocked else "CR %s" % _fmt_int(int(item.get("reward", 0))), MIN_FONT_SIZE, Color(0.55, 0.95, 0.65) if unlocked else Color(1.0, 0.78, 0.42), true)
        var detail := _label(box, String(item.get("detail", "")), MIN_FONT_SIZE, COL_MUTED)
        detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        var progress_row := HBoxContainer.new()
        progress_row.add_theme_constant_override("separation", 9)
        box.add_child(progress_row)
        var bar := ProgressBar.new()
        bar.min_value = 0.0
        bar.max_value = 1.0
        bar.value = clampf(float(item.get("progress", 1.0 if unlocked else 0.0)), 0.0, 1.0)
        bar.show_percentage = false
        bar.custom_minimum_size = Vector2(0.0, 11.0)
        bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        bar.add_theme_stylebox_override("background", _style(Color(1, 1, 1, 0.10), COL_BORDER, 3, 0))
        bar.add_theme_stylebox_override("fill", _style(Color(0.25, 0.82, 0.42) if unlocked else COL_ACCENT, COL_ACCENT, 3, 0))
        progress_row.add_child(bar)
        var unit := String(item.get("unit", ""))
        var progress_text := "%s / %s %s" % [
            _format_progress_value(float(item.get("current", 0.0)), unit),
            _format_progress_value(float(item.get("target", 0.0)), unit),
            unit,
        ]
        var value_label := _label(progress_row, progress_text.strip_edges(), MIN_FONT_SIZE, COL_TEXT)
        value_label.custom_minimum_size = Vector2(126.0, 0.0)
        value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        _achievement_card_count += 1
    if _achievement_card_count == 0:
        var empty_label := _label(_achievements_box, "Достижения появятся после первых заездов.", MIN_FONT_SIZE, COL_MUTED)
        empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _refresh_history(items: Array) -> void:
    if _history_box == null:
        return
    for child in _history_box.get_children():
        _history_box.remove_child(child)
        child.queue_free()
    if items.is_empty():
        var empty_label := _label(_history_box, "Пока нет завершённых заездов. Первый заезд появится здесь после поездки и возвращения в меню.", MIN_FONT_SIZE, COL_MUTED)
        empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        var drive_button := _button("▶  ПОЕХАТЬ", COL_ACCENT, Vector2(0.0, MIN_TOUCH_HEIGHT), 16)
        drive_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
        drive_button.pressed.connect(func() -> void: play_requested.emit())
        _history_box.add_child(drive_button)
        return
    for item_variant in items:
        var item: Dictionary = item_variant
        var history_prefix := String(item.get("date", "заезд"))
        var history_car := String(item.get("car_name", ""))
        if not history_car.is_empty():
            history_prefix += " • " + history_car
        var line := _label(_history_box, "%s • %.1f км • %d км/ч • дрифт %d° • %d мин" % [
            history_prefix,
            float(item.get("distance_km", 0.0)),
            int(round(float(item.get("top_speed_kmh", 0.0)))),
            int(round(float(item.get("drift_deg", 0.0)))),
            int(round(float(item.get("duration_sec", 0.0)) / 60.0)),
        ], MIN_FONT_SIZE, COL_TEXT)
        line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _update_world_progress() -> void:
    if _world_progress_label == null:
        return
    if WORLDS_FREE_FOR_ALL:
        _world_progress_label.text = "ВСЕ ГОТОВЫЕ КАРТЫ БЕСПЛАТНЫ: RichTown и Пустынный каньон открыты сразу. Северные горы тоже будут бесплатны, но этот мир ещё в разработке."
        _refresh_world_cards()
        return
    var level := int(_profile_view.get("level", 1))
    var credits := int(_profile_view.get("credits", 35000))
    var mountains_left := maxi(WORLD_MOUNTAINS_REQUIRED_LEVEL - level, 0)
    var canyon_left := maxi(WORLD_CANYON_REQUIRED_CREDITS - credits, 0)
    var canyon_line := ""
    if canyon_left == 0:
        canyon_line = "ПУСТЫННЫЙ КАНЬОН: ОТКРЫТ • выберите карточку мира выше, чтобы поехать в пустыню"
    else:
        canyon_line = "ПУСТЫННЫЙ КАНЬОН: CR %s / %s • не хватает CR %s" % [_fmt_int(credits), _fmt_int(WORLD_CANYON_REQUIRED_CREDITS), _fmt_int(canyon_left)]
    _world_progress_label.text = "СЕВЕРНЫЕ ГОРЫ: уровень %d / %d%s • мир в разработке\n%s" % [
        level, WORLD_MOUNTAINS_REQUIRED_LEVEL, " • условие выполнено" if mountains_left == 0 else " • осталось уровней: %d" % mountains_left,
        canyon_line,
    ]
    _refresh_world_cards()


## World selection: RichTown is always available.  While
## WORLDS_FREE_FOR_ALL is on (0.2.48), the desert canyon is free too;
## otherwise it unlocks at WORLD_CANYON_REQUIRED_CREDITS.  Selecting a
## card asks main to rebuild the world and then starts driving there.
func _world_display_name(world_id: String = "") -> String:
    var id := world_id if not world_id.is_empty() else _current_world_id
    return "ПУСТЫННЫЙ КАНЬОН" if id == "desert" else ("ЗЕЛЁНЫЙ ЛЕС" if id == "greenforest" else "RICHTOWN")


func _desert_unlocked() -> bool:
    if WORLDS_FREE_FOR_ALL:
        return true
    return int(_profile_view.get("credits", 35000)) >= WORLD_CANYON_REQUIRED_CREDITS


func _on_world_card_pressed(world_id: String) -> void:
    if world_id == "desert" and not _desert_unlocked():
        return
    if world_id != _current_world_id:
        world_selected.emit(world_id)
    play_requested.emit()


func set_current_world(world_id: String) -> void:
    if world_id != "richtown" and world_id != "desert" and world_id != "greenforest":
        return
    _current_world_id = world_id
    _refresh_world_cards()
    _refresh_car_presentation()


func _richtown_detail_text() -> String:
    return "Открытый прибрежный город: центральный деловой район и главная башня, мечеть, опера и бульвары с кафе, центральный парк, набережная, порт и Остров-Пальма. Полноэкранная карта строит маршрут по настоящим дорогам, показывает районы и точки интереса, а быстрый переход переносит выбранный автомобиль к выбранному месту."


func _forest_detail_text() -> String:
    return "Открытый лесной мир 4×4 км: густой тёмный лес и хвойные холмы с серпантином и смотровой площадкой, центральные луга со скоростной прямой, большое озеро с дамбой, островом и посёлком на восточном берегу, река с водопадом, болото с гатью, фермерская долина с полями, мельницей и теплицами, лесопилка и скалистый утёс с тоннелем и мостом над ущельем. Около 55 км дорог: асфальтовое кольцо, грунтовки и лесные тропы. Трава, подстилка, грязь и полевая земля держат машину по-разному — после дождя у воды особенно скользко."


func _desert_detail_text() -> String:
    return "Открытая пустынная котловина 4×4 км: городок Дюны со стартом на главной улице, 55 км дорог кольцом и тропами, каньоны и серпантин у северных мез, карьер с техникой, нефтяное поле с качалками, солончак для рекордов скорости, море дюн, ветроферма и оазис с озером и пальмами. Асфальт, гравий, утрамбованный песок, соль и дюны держат машину по-разному — следите за сцеплением и пылью из-под колёс."


func _refresh_world_cards() -> void:
    var desert := _current_world_id == "desert"
    var forest := _current_world_id == "greenforest"
    if _richtown_card != null:
        _set_picture_card(_richtown_card, MENU_WORLD_TEXTURE, "RICHTOWN" + ("" if (desert or forest) else " • ТЕКУЩИЙ МИР"), "игровой обзор города • побережье • Остров-Пальма")
    if _desert_card != null:
        var unlocked := _desert_unlocked()
        _desert_card.disabled = not unlocked
        _desert_card.modulate = Color.WHITE if unlocked else Color(0.52, 0.54, 0.58)
        _desert_card.text = "ПУСТЫННЫЙ КАНЬОН" + ("" if not desert else " • ТЕКУЩИЙ")
        if _desert_lock_icon != null:
            _desert_lock_icon.visible = not unlocked
        if _desert_card_subtitle != null:
            if not unlocked:
                _desert_card_subtitle.text = "нужно накопить CR %s" % _fmt_int(WORLD_CANYON_REQUIRED_CREDITS)
            elif desert:
                _desert_card_subtitle.text = "ТЕКУЩИЙ МИР • 4×4 км • каньоны • солончак • оазис"
            else:
                _desert_card_subtitle.text = "бесплатно • открыт • 4×4 км • каньоны • солончак • оазис" if WORLDS_FREE_FOR_ALL else "открыт • 4×4 км • каньоны • солончак • оазис"
    if _world_title_label != null:
        _world_title_label.text = "%s — ТЕКУЩИЙ МИР" % _world_display_name()
    if _forest_card != null:
        _forest_card.text = "ЗЕЛЁНЫЙ ЛЕС" + (" • ТЕКУЩИЙ" if forest else "")
        if _forest_card_subtitle != null:
            _forest_card_subtitle.text = "ТЕКУЩИЙ МИР • 4×4 км • озеро • холмы • ферма" if forest else "бесплатно • открыт • 4×4 км • озеро • холмы • ферма"
    if _world_detail_label != null:
        _world_detail_label.text = _forest_detail_text() if forest else (_desert_detail_text() if desert else _richtown_detail_text())
    if _world_map_button != null:
        _world_map_button.text = "⌖  ОТКРЫТЬ КАРТУ: %s" % _world_display_name()


func refresh_profile(view: Dictionary) -> void:
    _profile_view = view.duplicate(true)
    _profile_bound = true
    var player_name := String(view.get("name", "ИГРОК"))
    var level := int(view.get("level", 1))
    var credits := int(view.get("credits", 35000))
    _avatar_id = String(view.get("avatar_id", _avatar_id))
    var xp_progress := clampf(float(view.get("xp_progress", 0.0)), 0.0, 1.0)
    if _top_name_label != null:
        _top_name_label.text = player_name
    if _top_credits_label != null:
        _top_credits_label.text = "CR %s" % _fmt_int(credits)
    if _top_xp_bar != null:
        _top_xp_bar.value = xp_progress
    if _top_xp_label != null:
        _top_xp_label.text = "ур. %d • XP %d%%" % [level, int(round(xp_progress * 100.0))]
    if _home_goal_label != null:
        _home_goal_label.text = "БЛИЖАЙШАЯ ЦЕЛЬ: до уровня %d осталось %.1f км • баланс CR %s" % [level + 1, float(view.get("xp_to_next_km", 50.0)), _fmt_int(credits)]
    if _top_avatar_icon != null:
        _top_avatar_icon.queue_redraw()
    if _profile_avatar_icon != null:
        _profile_avatar_icon.queue_redraw()
    if _nickname_edit != null and not _nickname_edit.has_focus():
        _nickname_edit.text = player_name
    if _p_name != null:
        _p_name.text = player_name
        _p_level.text = "Уровень: %d" % level
        _p_credits.text = "Кредиты: CR %s" % _fmt_int(credits)
        _p_distance.text = "Пробег: %.1f км" % float(view.get("distance_km", 0.0))
        _p_top.text = "Рекорд скорости: %d км/ч" % int(round(float(view.get("top_speed_kmh", 0.0))))
        _p_drift.text = "Рекорд дрифта: %d°" % int(round(float(view.get("drift_record_deg", 0.0))))
        _p_time.text = "Время за рулём: %d мин" % int(float(view.get("play_seconds", 0.0)) / 60.0)
    if _xp_bar != null:
        var progress := clampf(float(view.get("xp_progress", 0.0)), 0.0, 1.0)
        _xp_bar.value = progress
        _xp_label.text = "XP: %d%% • до уровня %d осталось %.1f км" % [int(round(progress * 100.0)), level + 1, float(view.get("xp_to_next_km", 50.0))]
    _refresh_achievement_cards(view.get("achievements", []))
    _refresh_history(view.get("history", []))
    _update_world_progress()
    _refresh_store()
    if _car_stats_label != null:
        var car_lines: Array[String] = []
        for item_variant in view.get("car_stats", []):
            var item: Dictionary = item_variant
            car_lines.append("%s • %.1f км • рекорд %d км/ч • дрифт %d°" % [
                String(item.get("name", "Автомобиль")),
                float(item.get("distance_km", 0.0)),
                int(round(float(item.get("top_speed_kmh", 0.0)))),
                int(round(float(item.get("drift_deg", 0.0)))),
            ])
        _car_stats_label.text = "\n".join(car_lines) if not car_lines.is_empty() else "Автомобили — 0.0 км"


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
