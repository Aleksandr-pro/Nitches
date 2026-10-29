class_name NativeWorldMap
extends CanvasLayer

## Full-screen RichTown map (0.2.32).
##
## This is deliberately a navigation screen, not an enlarged minimap:
## it can be panned and zoomed, names every exported district, labels
## the main roads and parks, and exposes the important landmarks both
## as tappable map markers and as a scrollable list.  Selecting a
## point shows its district, real world coordinates and straight-line
## distance from the player.  Main freezes the car while it is open.

signal close_requested
signal destination_changed(world_position: Vector2)
signal fast_travel_requested(world_position: Vector2, cost: int, poi_name: String)
signal minimap_points_changed(points: Array)

const NO_DRAG := -2
const MOUSE_DRAG := -1
const MIN_ZOOM := 0.85
const MAX_ZOOM := 9.0

const DISTRICT_NAMES := {
    "richtown": "ЦЕНТР RICHTOWN",
    "richtown-marina": "МАРИНА",
    "richtown-beach": "ПЛЯЖ RICHTOWN",
    "palm-island": "ОСТРОВ-ПАЛЬМА",
    "south-villa-district": "ЮЖНЫЙ РАЙОН ВИЛЛ",
}
const DISTRICT_COLORS := {
    "richtown": Color(1.0, 0.58, 0.10, 0.10),
    "richtown-marina": Color(0.05, 0.72, 1.0, 0.12),
    "richtown-beach": Color(1.0, 0.78, 0.28, 0.10),
    "palm-island": Color(0.22, 0.95, 0.48, 0.10),
    "south-villa-district": Color(0.72, 0.42, 1.0, 0.12),
}
const LANDMARK_POIS := {
    "rt-tower": ["Главная башня", "Башня", 1],
    "rt-arch": ["Триумфальная арка", "Достопримечательность", 2],
    "rt-fountain": ["Центральный фонтан", "Площадь", 1],
    "rt-sail": ["Башня «Парус»", "Башня", 1],
    "rt-museum": ["Музей", "Культура", 1],
    "rt-opera": ["Опера", "Культура", 1],
    "rt-mosque": ["Мечеть", "Культура", 1],
    "rt-twist": ["Башня Twist", "Башня", 2],
    "rt-lean": ["Наклонная башня", "Башня", 2],
    "rt-hole": ["Башня Hole", "Башня", 2],
    "rt-parking": ["Многоуровневый паркинг", "Инфраструктура", 3],
    "rt-aquapark": ["Аквапарк", "Развлечения", 2],
}
const ROAD_LABELS := [
    {"name": "ГЛАВНЫЙ БУЛЬВАР", "x": 760.0, "z": -135.0, "priority": 1},
    {"name": "ЗАПАДНАЯ УЛИЦА", "x": 560.0, "z": 35.0, "priority": 2},
    {"name": "ПРИБРЕЖНАЯ ДОРОГА", "x": 930.0, "z": -145.0, "priority": 1},
    {"name": "ШОССЕ", "x": 535.0, "z": 225.0, "priority": 2},
    {"name": "ДОРОГА К «ПАРУСУ»", "x": 1050.0, "z": 80.0, "priority": 2},
    {"name": "МОСТ НА ОСТРОВ-ПАЛЬМУ", "x": 1085.0, "z": -250.0, "priority": 1},
]

var _world: NativeWorldBuilder
var _vehicle: NativeVehicle
var _data: Dictionary = {}
var _pois: Array = []
var _selected_poi: Dictionary = {}
var _route_poi: Dictionary = {}
var _route_active := false
var _route_points: Array[Vector2] = []
var _active_filter := "all"
var _hint_visible := false
var _travel_status := ""

var _root: Control
var _canvas: Control
var _side_panel: PanelContainer
var _poi_list: VBoxContainer
var _title_label: Label
var _player_label: Label
var _detail_panel: PanelContainer
var _detail_label: Label
var _route_button: Button
var _travel_button: Button
var _filter_buttons: Dictionary = {}
var _close_button: Button
var _zoom_in_button: Button
var _zoom_out_button: Button
var _centre_button: Button
var _fit_button: Button
var _compass_label: Label
var _scale_label: Label
var _district_labels: Array = []
var _poi_labels: Array = []
var _road_labels: Array = []

var _centre_world := Vector2(1010.0, 0.0)
var _zoom_factor := 1.0
var _fit_pixels_per_meter := 0.5
var _map_initialized := false
var _drag_index := NO_DRAG
var _drag_start := Vector2.ZERO
var _last_drag_position := Vector2.ZERO
var _drag_distance := 0.0
var _hover_world := Vector2.ZERO
var _has_hover_world := false
var _touch_points: Dictionary = {}
var _pinch_active := false
var _pinch_distance := 0.0
var _pinch_centre := Vector2.ZERO


func _ready() -> void:
    name = "WorldMap"
    layer = 30
    visible = false
    _build_ui()
    if get_viewport() != null:
        get_viewport().size_changed.connect(_layout)


func _is_desert() -> bool:
    return _world != null and _world.world_id == "desert"


func bind(world: NativeWorldBuilder, vehicle: NativeVehicle) -> void:
    _world = world
    _vehicle = vehicle
    if _world != null:
        _data = _world.get_world_data().duplicate(true)
    if _title_label != null:
        _title_label.text = "КАРТА: ПУСТЫННЫЙ КАНЬОН" if _is_desert() else "КАРТА RICHTOWN"
    _build_pois()
    _build_labels()
    _rebuild_poi_list()
    _layout()
    _fit_all()
    _update_player_info()
    _update_detail()
    _refresh_map()


func show_map() -> void:
    visible = true
    _layout()
    if not _map_initialized:
        _fit_all()
    _update_player_info()
    _update_detail()
    _refresh_map()


func hide_map() -> void:
    visible = false
    _drag_index = NO_DRAG
    _has_hover_world = false
    _touch_points.clear()
    _pinch_active = false
    _pinch_distance = 0.0


func is_open() -> bool:
    return visible


func get_smoke_state() -> Dictionary:
    return {
        "world_map_0232": true,
        "created": _canvas != null,
        "data_bound": not _data.is_empty(),
        "visible_now": visible,
        "districts": (_data.get("districts", []) as Array).size(),
        "district_labels": _district_labels.size(),
        "roads": (_data.get("roads", []) as Array).size(),
        "road_labels": _road_labels.size(),
        "pois": _pois.size(),
        "poi_labels": _poi_labels.size(),
        "parks": _world.get_park_map_entries().size() if _world != null else 0,
        "zoom_factor": _zoom_factor,
        "pinch_zoom": true,
        "centre_world": _centre_world,
        "selected_poi": String(_selected_poi.get("name", "")),
        "selected_destination": get_selected_destination(),
        "minimap_points": get_minimap_points().size(),
        "world_map_0234": true,
        "route_active": _route_active,
        "route_destination": get_route_destination(),
        "route_points": _route_points.size(),
        "route_button_created": _route_button != null,
        "fast_travel_button_created": _travel_button != null,
        "active_filter": _active_filter,
        "filter_buttons": _filter_buttons.size(),
        "hint_visible": _hint_visible,
        "district_circles_removed": true,
        "zoom_label_tiers_0234": true,
    "world_id": _world.world_id if _world != null else "",
    "desert_map_0247": _is_desert(),
    }


func _panel_style() -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.006, 0.018, 0.034, 0.92)
    style.border_color = Color(1.0, 0.62, 0.12, 0.72)
    style.set_border_width_all(1)
    style.set_corner_radius_all(12)
    style.content_margin_left = 12.0
    style.content_margin_right = 12.0
    style.content_margin_top = 9.0
    style.content_margin_bottom = 9.0
    return style


func _button_style(pressed: bool) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.02, 0.34, 0.48, 0.88 if pressed else 0.62)
    style.border_color = Color(1.0, 0.68, 0.18, 0.92 if pressed else 0.58)
    style.set_border_width_all(1)
    style.set_corner_radius_all(9)
    style.content_margin_left = 8.0
    style.content_margin_right = 8.0
    style.content_margin_top = 6.0
    style.content_margin_bottom = 6.0
    return style


func _make_button(parent: Control, text: String) -> Button:
    var button := Button.new()
    button.text = text
    button.focus_mode = Control.FOCUS_NONE
    button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    button.add_theme_font_size_override("font_size", 14)
    button.add_theme_color_override("font_color", Color.WHITE)
    button.add_theme_color_override("font_hover_color", Color(1.0, 0.86, 0.48))
    button.add_theme_stylebox_override("normal", _button_style(false))
    button.add_theme_stylebox_override("hover", _button_style(true))
    button.add_theme_stylebox_override("pressed", _button_style(true))
    parent.add_child(button)
    return button


func _make_label(parent: Control, text: String, size: int, color: Color) -> Label:
    var label := Label.new()
    label.text = text
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.add_theme_font_size_override("font_size", size)
    label.add_theme_color_override("font_color", color)
    label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.82))
    label.add_theme_constant_override("shadow_offset_x", 1)
    label.add_theme_constant_override("shadow_offset_y", 1)
    parent.add_child(label)
    return label


func _build_ui() -> void:
    _root = Control.new()
    _root.name = "WorldMapRoot"
    _root.set_anchors_preset(Control.PRESET_FULL_RECT)
    _root.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(_root)

    var backdrop := ColorRect.new()
    backdrop.name = "WorldMapBackdrop"
    backdrop.color = Color(0.003, 0.008, 0.018, 0.97)
    backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
    backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
    _root.add_child(backdrop)

    _title_label = _make_label(_root, "КАРТА RICHTOWN", 25, Color(1.0, 0.70, 0.18))
    _player_label = _make_label(_root, "ИГРОК: —", 14, Color(0.68, 0.92, 1.0))
    _close_button = _make_button(_root, "✕  ЗАКРЫТЬ")
    _close_button.pressed.connect(func() -> void: close_requested.emit())

    _canvas = Control.new()
    _canvas.name = "WorldMapCanvas"
    _canvas.clip_contents = true
    _canvas.mouse_filter = Control.MOUSE_FILTER_STOP
    _canvas.draw.connect(_draw_map)
    _canvas.gui_input.connect(_on_canvas_gui_input)
    _canvas.resized.connect(_on_canvas_resized)
    _root.add_child(_canvas)

    _compass_label = _make_label(_root, "↑ С", 18, Color.WHITE)
    _scale_label = _make_label(_canvas, "100 м", 11, Color(0.86, 0.94, 1.0))

    _side_panel = PanelContainer.new()
    _side_panel.name = "WorldMapPoiPanel"
    _side_panel.add_theme_stylebox_override("panel", _panel_style())
    _root.add_child(_side_panel)
    var side_box := VBoxContainer.new()
    side_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    side_box.add_theme_constant_override("separation", 7)
    _side_panel.add_child(side_box)
    var side_title := _make_label(side_box, "ОСНОВНЫЕ ТОЧКИ", 16, Color(1.0, 0.72, 0.22))
    side_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    var filter_grid := GridContainer.new()
    filter_grid.columns = 2
    filter_grid.add_theme_constant_override("h_separation", 5)
    filter_grid.add_theme_constant_override("v_separation", 5)
    side_box.add_child(filter_grid)
    for spec in [["all", "ВСЕ"], ["races", "ГОНКИ"], ["shops", "МАГАЗИНЫ"], ["landmarks", "МЕСТА"], ["homes", "ДОМА"]]:
        var filter_id := String(spec[0])
        var filter_button := _make_button(filter_grid, String(spec[1]))
        filter_button.custom_minimum_size = Vector2(0.0, 34.0)
        filter_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
        filter_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        filter_button.pressed.connect(func() -> void: _set_filter(filter_id))
        if filter_id == _active_filter:
            filter_button.modulate = Color(1.0, 0.76, 0.42)
        _filter_buttons[filter_id] = filter_button
    var scroll := ScrollContainer.new()
    scroll.name = "WorldMapPoiScroll"
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    side_box.add_child(scroll)
    _poi_list = VBoxContainer.new()
    _poi_list.name = "WorldMapPoiList"
    _poi_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _poi_list.add_theme_constant_override("separation", 5)
    scroll.add_child(_poi_list)

    _detail_panel = PanelContainer.new()
    _detail_panel.name = "WorldMapDetailPanel"
    _detail_panel.add_theme_stylebox_override("panel", _panel_style())
    _root.add_child(_detail_panel)
    var detail_box := HBoxContainer.new()
    detail_box.add_theme_constant_override("separation", 8)
    _detail_panel.add_child(detail_box)
    _detail_label = _make_label(detail_box, "Выберите точку на карте или в списке", 13, Color(0.88, 0.96, 1.0))
    _detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _detail_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _route_button = _make_button(detail_box, "МАРШРУТ")
    _route_button.custom_minimum_size = Vector2(118.0, 36.0)
    _route_button.pressed.connect(_on_route_button_pressed)
    _travel_button = _make_button(detail_box, "ПЕРЕЙТИ")
    _travel_button.custom_minimum_size = Vector2(132.0, 36.0)
    _travel_button.pressed.connect(_on_travel_button_pressed)

    _zoom_in_button = _make_button(_root, "+")
    _zoom_in_button.pressed.connect(func() -> void: _set_zoom_factor(_zoom_factor * 1.45, _canvas.size * 0.5))
    _zoom_out_button = _make_button(_root, "−")
    _zoom_out_button.pressed.connect(func() -> void: _set_zoom_factor(_zoom_factor / 1.45, _canvas.size * 0.5))
    _centre_button = _make_button(_root, "◎ Я")
    _centre_button.pressed.connect(_centre_on_player)
    _fit_button = _make_button(_root, "ВЕСЬ ГОРОД")
    _fit_button.pressed.connect(_fit_all)


func _place(control: Control, rect: Rect2) -> void:
    if control == null:
        return
    control.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
    control.position = rect.position
    control.size = rect.size


func _layout() -> void:
    if _root == null or get_viewport() == null:
        return
    var viewport_size := get_viewport().get_visible_rect().size
    if viewport_size.x < 100.0 or viewport_size.y < 100.0:
        return
    var side_width := 300.0 if viewport_size.x >= 1000.0 else clampf(viewport_size.x * 0.34, 190.0, 270.0)
    var map_rect := Rect2(14.0, 74.0, maxf(viewport_size.x - side_width - 42.0, 240.0), maxf(viewport_size.y - 146.0, 200.0))
    _place(_title_label, Rect2(16.0, 7.0, 430.0, 34.0))
    _place(_player_label, Rect2(17.0, 40.0, maxf(viewport_size.x - 190.0, 240.0), 24.0))
    _place(_close_button, Rect2(viewport_size.x - 154.0, 12.0, 140.0, 42.0))
    _place(_canvas, map_rect)
    _place(_side_panel, Rect2(map_rect.end.x + 10.0, map_rect.position.y, side_width, map_rect.size.y))
    _place(_detail_panel, Rect2(map_rect.position.x, viewport_size.y - 64.0, map_rect.size.x, 52.0))
    _place(_compass_label, Rect2(map_rect.position.x + 12.0, map_rect.position.y + 8.0, 54.0, 28.0))
    _place(_zoom_in_button, Rect2(map_rect.end.x - 58.0, map_rect.end.y - 158.0, 44.0, 40.0))
    _place(_zoom_out_button, Rect2(map_rect.end.x - 58.0, map_rect.end.y - 112.0, 44.0, 40.0))
    _place(_centre_button, Rect2(map_rect.end.x - 92.0, map_rect.end.y - 66.0, 78.0, 40.0))
    _place(_fit_button, Rect2(map_rect.end.x - 214.0, map_rect.end.y - 66.0, 116.0, 40.0))
    _compute_fit()
    _refresh_map()


func _on_canvas_resized() -> void:
    _compute_fit()
    _refresh_map()


func _bounds() -> Dictionary:
    return _data.get("bounds", {"minX": 520.0, "maxX": 1500.0, "minZ": -500.0, "maxZ": 500.0})


func _compute_fit() -> void:
    if _canvas == null or _canvas.size.x < 20.0 or _canvas.size.y < 20.0:
        return
    var bounds := _bounds()
    var world_width := maxf(float(bounds.get("maxX", 1500.0)) - float(bounds.get("minX", 520.0)), 1.0)
    var world_height := maxf(float(bounds.get("maxZ", 500.0)) - float(bounds.get("minZ", -500.0)), 1.0)
    _fit_pixels_per_meter = minf(_canvas.size.x / world_width, _canvas.size.y / world_height) * 0.985
    if not _map_initialized:
        _centre_world = Vector2(
            (float(bounds.get("minX", 520.0)) + float(bounds.get("maxX", 1500.0))) * 0.5,
            (float(bounds.get("minZ", -500.0)) + float(bounds.get("maxZ", 500.0))) * 0.5
        )
        _zoom_factor = 1.0
        _map_initialized = true


func _pixels_per_meter() -> float:
    return maxf(_fit_pixels_per_meter * _zoom_factor, 0.001)


func _world_to_map(x: float, z: float) -> Vector2:
    if _canvas == null:
        return Vector2.ZERO
    var ppm := _pixels_per_meter()
    return _canvas.size * 0.5 + Vector2((x - _centre_world.x) * ppm, -(z - _centre_world.y) * ppm)


func _map_to_world(point: Vector2) -> Vector2:
    if _canvas == null:
        return _centre_world
    var ppm := _pixels_per_meter()
    var relative := point - _canvas.size * 0.5
    return _centre_world + Vector2(relative.x / ppm, -relative.y / ppm)


func _clamp_centre() -> void:
    var bounds := _bounds()
    _centre_world.x = clampf(_centre_world.x, float(bounds.get("minX", 520.0)) - 220.0, float(bounds.get("maxX", 1500.0)) + 220.0)
    _centre_world.y = clampf(_centre_world.y, float(bounds.get("minZ", -500.0)) - 220.0, float(bounds.get("maxZ", 500.0)) + 220.0)


func _fit_all() -> void:
    var bounds := _bounds()
    _centre_world = Vector2(
        (float(bounds.get("minX", 520.0)) + float(bounds.get("maxX", 1500.0))) * 0.5,
        (float(bounds.get("minZ", -500.0)) + float(bounds.get("maxZ", 500.0))) * 0.5
    )
    _zoom_factor = 1.0
    _map_initialized = true
    _refresh_map()


func _centre_on_player() -> void:
    if _vehicle == null:
        return
    _centre_world = Vector2(_vehicle.global_position.x, _vehicle.global_position.z)
    _zoom_factor = maxf(_zoom_factor, 3.0)
    _clamp_centre()
    _update_player_info()
    _refresh_map()


func _set_zoom_factor(next_zoom: float, anchor: Vector2) -> void:
    if _canvas == null:
        return
    var anchored_world := _map_to_world(anchor)
    _zoom_factor = clampf(next_zoom, MIN_ZOOM, MAX_ZOOM)
    var ppm := _pixels_per_meter()
    var relative := anchor - _canvas.size * 0.5
    _centre_world = anchored_world - Vector2(relative.x / ppm, -relative.y / ppm)
    _clamp_centre()
    _refresh_map()


func _filter_for_category(category: String, id: String) -> String:
    if category == "Гонка" or category == "Старт" or id.begins_with("race_"):
        return "races"
    if category in ["Кафе", "Отель", "Инфраструктура"]:
        return "shops"
    if category == "Дом":
        return "homes"
    return "landmarks"


func _poi_passes_filter(poi: Dictionary) -> bool:
    return _active_filter == "all" or String(poi.get("filter", "landmarks")) == _active_filter


func _set_filter(filter_id: String) -> void:
    _active_filter = filter_id
    for key in _filter_buttons.keys():
        (_filter_buttons[key] as Button).modulate = Color(1.0, 0.76, 0.42) if String(key) == filter_id else Color.WHITE
    _rebuild_poi_list()
    _refresh_map()
    minimap_points_changed.emit(get_minimap_points())


func _add_poi(id: String, name: String, category: String, x: float, z: float, priority: int, label_offset := Vector2(10.0, -10.0)) -> void:
    _pois.append({
        "id": id,
        "name": name,
        "category": category,
        "x": x,
        "z": z,
        "priority": priority,
        "filter": _filter_for_category(category, id),
        "label_offset": label_offset,
    })


func _poi_sort(a: Dictionary, b: Dictionary) -> bool:
    var priority_a := int(a.get("priority", 3))
    var priority_b := int(b.get("priority", 3))
    if priority_a != priority_b:
        return priority_a < priority_b
    return String(a.get("name", "")) < String(b.get("name", ""))


## 0.2.47: desert POIs come straight from the generated data —
## named landmarks, fast-travel points, race starts (circuits,
## sprints, drags), photo spots and jump ramps.  Treasures stay
## unmarked on purpose: they are physical chests to discover.
func _build_desert_pois() -> void:
    var spawn: Dictionary = _data.get("spawn", {"x": 612.0, "z": 2052.0})
    _add_poi("spawn", "Старт • городок Дюны", "Старт", float(spawn.get("x", 612.0)), float(spawn.get("z", 2052.0)), 1, Vector2(10.0, 8.0))
    var index := 0
    for landmark_variant in _data.get("landmarks", []):
        var landmark: Dictionary = landmark_variant
        var lname := String(landmark.get("name", ""))
        if lname.is_empty():
            continue
        index += 1
        _add_poi("lm_%d" % index, lname, "Достопримечательность", float(landmark.get("x", 0.0)), float(landmark.get("z", 0.0)), 2)
    var dz: Dictionary = _data.get("desert", {})
    var game: Dictionary = dz.get("game", {})
    index = 0
    for ft_variant in game.get("fastTravel", []):
        var ft: Dictionary = ft_variant
        index += 1
        _add_poi("travel_%d" % index, String(ft.get("name", "Быстрый переход")), "Инфраструктура", float(ft.get("x", 0.0)), float(ft.get("z", 0.0)), 1)
    for list_key in ["circuits", "sprints"]:
        for route_variant in game.get(list_key, []):
            var route: Dictionary = route_variant
            var pts: Array = route.get("points", [])
            if pts.is_empty():
                continue
            var first: Array = pts[0]
            _add_poi("race_" + String(route.get("id", "route")), "Гонка: " + String(route.get("name", "Трасса")), "Гонка", float(first[0]), float(first[1]), 2)
    for drag_variant in game.get("drags", []):
        var drag: Dictionary = drag_variant
        var start: Array = drag.get("start", [])
        if start.size() < 2:
            continue
        _add_poi("race_" + String(drag.get("id", "drag")), String(drag.get("name", "Драг")), "Гонка", float(start[0]), float(start[1]), 2)
    index = 0
    for photo_variant in game.get("photoSpots", []):
        var photo: Dictionary = photo_variant
        index += 1
        _add_poi("photo_%d" % index, String(photo.get("name", "Фототочка")), "Фототочка", float(photo.get("x", 0.0)), float(photo.get("z", 0.0)), 3)
    index = 0
    for jump_variant in game.get("jumps", []):
        var jump: Dictionary = jump_variant
        index += 1
        _add_poi("jump_%d" % index, String(jump.get("name", "Трамплин")), "Трамплин", float(jump.get("x", 0.0)), float(jump.get("z", 0.0)), 3)
    if _world != null:
        for park_variant in _world.get_park_map_entries():
            var park: Dictionary = park_variant
            var rect: Rect2 = park.get("rect", Rect2())
            _add_poi("oasis", "Оазис • озеро и пальмы", "Парк", rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y * 0.5, 1)


func _road_labels_data() -> Array:
    if not _is_desert():
        return ROAD_LABELS
    var labels: Array = []
    for road_variant in _data.get("roads", []):
        var road: Dictionary = road_variant
        var rname := String(road.get("name", ""))
        var samples: Array = road.get("samples", [])
        if rname.is_empty() or samples.size() < 6:
            continue
        var prio := 1 if String(road.get("surface", "asphalt")) == "asphalt" else 3
        var spots: Array = [samples.size() / 2]
        if String(road.get("id", "")) == "dz-ring":
            spots = [samples.size() / 5, samples.size() * 2 / 5, samples.size() * 3 / 5, samples.size() * 4 / 5]
        for si in spots:
            var s: Array = samples[int(si)]
            labels.append({"name": rname.to_upper(), "x": float(s[0]), "z": float(s[2]), "priority": prio})
    return labels


func _build_pois() -> void:
    _pois.clear()
    if _is_desert():
        _build_desert_pois()
        _pois.sort_custom(_poi_sort)
        if not _pois.is_empty():
            _selected_poi = _pois[0]
        return
    var seen_lifeguard := false
    for landmark_variant in _data.get("landmarks", []):
        var landmark: Dictionary = landmark_variant
        var kind := String(landmark.get("kind", ""))
        if kind == "rt-lifeguard":
            if seen_lifeguard:
                continue
            seen_lifeguard = true
            _add_poi("lifeguard", "Пляжная вышка", "Пляж", float(landmark.get("x", 985.0)), float(landmark.get("z", -20.0)), 3)
            continue
        var spec: Array = LANDMARK_POIS.get(kind, [])
        if spec.size() >= 3:
            _add_poi(kind, String(spec[0]), String(spec[1]), float(landmark.get("x", 0.0)), float(landmark.get("z", 0.0)), int(spec[2]))

    for building_variant in _data.get("buildings", []):
        var building: Dictionary = building_variant
        var kind := String(building.get("kind", ""))
        var x := float(building.get("x", 0.0))
        var z := float(building.get("z", 0.0))
        if kind == "rt-mall":
            _add_poi("mall", "Торговый центр", "Инфраструктура", x, z, 2)
        elif kind == "rt-hotel" and x > 880.0:
            # Only the three X892 plots use the integrated Grand Hotel
            # model.  The other exported rt-hotel entries are generic
            # tower archetypes, so labelling all of them as hotels
            # would make the navigation map actively misleading.
            if absf(z + 385.0) <= 1.0:
                _add_poi("grand_hotel", "Гранд-отель", "Отель", x, z, 1)
            elif absf(z + 185.0) <= 1.0:
                _add_poi("coast_hotel_north", "Отель побережья — север", "Отель", x, z, 2)
            elif absf(z - 105.0) <= 1.0:
                _add_poi("coast_hotel_south", "Отель побережья — юг", "Отель", x, z, 2)

    var spawn: Dictionary = _data.get("spawn", {"x": 760.0, "z": 330.0})
    _add_poi("spawn", "Старт • Shelby GT500", "Старт", float(spawn.get("x", 760.0)), float(spawn.get("z", 330.0)), 1, Vector2(10.0, 8.0))
    _add_poi("boulevard_cafe", "Бульварные кафе", "Кафе", 738.0, 23.0, 2, Vector2(-112.0, -10.0))

    if _world != null:
        for park_variant in _world.get_park_map_entries():
            var park: Dictionary = park_variant
            var rect: Rect2 = park.get("rect", Rect2())
            var park_id := String(park.get("id", "park"))
            var park_name := String(park.get("label", "Парк"))
            if park_id == "central":
                park_name = "Центральный парк"
            elif park_id == "museum":
                park_name = "Сад музея"
            elif park_id == "beach":
                park_name = "Пальметум Корниш"
            _add_poi("park_" + park_id, park_name, "Парк", rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y * 0.5, 2)

    _add_poi("race_boulevard", "Старт гонки: Бульвар", "Гонка", 760.0, 318.0, 2)
    _add_poi("race_corniche", "Старт гонки: Корниш", "Гонка", 930.0, -318.0, 2)
    _add_poi("race_palm_bridge", "Старт гонки: Мост Пальмы", "Гонка", 1085.0, -250.0, 2)
    var home_targets := [Vector2(710.0, -344.0), Vector2(662.0, 306.0), Vector2(1348.0, -352.0)]
    var home_names := ["Дом у музея", "Дом в Южном районе вилл", "Дом на Острове-Пальме"]
    for home_index in home_targets.size():
        var target: Vector2 = home_targets[home_index]
        var best: Dictionary = {}
        var best_distance := 40.0
        for building_variant in _data.get("buildings", []):
            var building: Dictionary = building_variant
            if String(building.get("kind", "")) != "rt-villa" or String(building.get("model", "")) != "villa":
                continue
            var candidate := Vector2(float(building.get("x", 0.0)), float(building.get("z", 0.0)))
            var distance := candidate.distance_to(target)
            if distance < best_distance:
                best_distance = distance
                best = building
        if not best.is_empty():
            _add_poi("home_%d" % home_index, home_names[home_index], "Дом", float(best.get("x", target.x)), float(best.get("z", target.y)), 2)

    _pois.sort_custom(_poi_sort)
    if not _pois.is_empty():
        _selected_poi = _pois[0]


func _label_style() -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.0, 0.02, 0.04, 0.62)
    style.set_corner_radius_all(5)
    style.content_margin_left = 5.0
    style.content_margin_right = 5.0
    style.content_margin_top = 2.0
    style.content_margin_bottom = 2.0
    return style


func _make_map_label(text: String, font_size: int, color: Color, world_x: float, world_z: float, offset: Vector2) -> Label:
    var label := _make_label(_canvas, text, font_size, color)
    label.add_theme_stylebox_override("normal", _label_style())
    label.set_meta("world_x", world_x)
    label.set_meta("world_z", world_z)
    label.set_meta("offset", offset)
    label.reset_size()
    return label


func _district_display_name(district: Dictionary) -> String:
    var id := String(district.get("id", ""))
    return String(DISTRICT_NAMES.get(id, String(district.get("name", "RichTown")).to_upper()))


func _build_labels() -> void:
    for label in _district_labels + _poi_labels + _road_labels:
        (label as Label).queue_free()
    _district_labels.clear()
    _poi_labels.clear()
    _road_labels.clear()
    if _canvas == null:
        return

    for district_variant in _data.get("districts", []):
        var district: Dictionary = district_variant
        var label := _make_map_label(
            _district_display_name(district),
            17,
            Color(1.0, 1.0, 1.0, 0.94),
            float(district.get("x", 0.0)),
            float(district.get("z", 0.0)),
            Vector2.ZERO
        )
        label.set_meta("centre_label", true)
        _district_labels.append(label)

    for poi in _pois:
        var poi_dict: Dictionary = poi
        var label := _make_map_label(
            String(poi_dict.get("name", "Точка")),
            12,
            Color(0.94, 0.98, 1.0, 0.96),
            float(poi_dict.get("x", 0.0)),
            float(poi_dict.get("z", 0.0)),
            poi_dict.get("label_offset", Vector2(10.0, -10.0))
        )
        label.set_meta("poi_id", String(poi_dict.get("id", "")))
        label.set_meta("filter", String(poi_dict.get("filter", "landmarks")))
        label.set_meta("priority", int(poi_dict.get("priority", 3)))
        _poi_labels.append(label)

    for road_variant in _road_labels_data():
        var road: Dictionary = road_variant
        var label := _make_map_label(
            String(road.get("name", "")),
            10,
            Color(0.68, 0.84, 0.98, 0.88),
            float(road.get("x", 0.0)),
            float(road.get("z", 0.0)),
            Vector2(8.0, -8.0)
        )
        label.set_meta("priority", int(road.get("priority", 2)))
        _road_labels.append(label)


func _rebuild_poi_list() -> void:
    if _poi_list == null:
        return
    for child in _poi_list.get_children():
        child.queue_free()
    for poi in _pois:
        var poi_dict: Dictionary = poi
        if not _poi_passes_filter(poi_dict):
            continue
        var button := _make_button(_poi_list, "◆  %s\n%s • X %.0f • Z %.0f" % [
            String(poi_dict.get("name", "Точка")),
            String(poi_dict.get("category", "Точка")),
            float(poi_dict.get("x", 0.0)),
            float(poi_dict.get("z", 0.0)),
        ])
        button.custom_minimum_size = Vector2(0.0, 50.0)
        button.alignment = HORIZONTAL_ALIGNMENT_LEFT
        var poi_id := String(poi_dict.get("id", ""))
        button.pressed.connect(func() -> void: _select_poi_by_id(poi_id, true))


func _find_poi(id: String) -> Dictionary:
    for poi in _pois:
        var poi_dict: Dictionary = poi
        if String(poi_dict.get("id", "")) == id:
            return poi_dict
    return {}


func _select_poi_by_id(id: String, focus: bool) -> void:
    var poi := _find_poi(id)
    if poi.is_empty():
        return
    _selected_poi = poi
    _travel_status = ""
    if focus:
        _centre_world = Vector2(float(poi.get("x", _centre_world.x)), float(poi.get("z", _centre_world.y)))
        _zoom_factor = maxf(_zoom_factor, 2.7)
        _clamp_centre()
    _update_detail()
    _refresh_map()


func set_first_open_hint(visible_hint: bool) -> void:
    _hint_visible = visible_hint
    _update_player_info()


func set_travel_status(text: String) -> void:
    _travel_status = text
    _update_detail()
    _refresh_map()


func set_route_path(points: Array) -> void:
    _route_points.clear()
    for point_variant in points:
        _route_points.append(point_variant as Vector2)
    _refresh_map()


func get_route_destination() -> Vector2:
    if not _route_active or _route_poi.is_empty():
        return Vector2.INF
    return Vector2(float(_route_poi.get("x", 0.0)), float(_route_poi.get("z", 0.0)))


func clear_route() -> void:
    _route_active = false
    _route_poi = {}
    _route_points.clear()
    destination_changed.emit(Vector2.INF)
    _update_detail()
    _refresh_map()


func _travel_cost_for_selected() -> int:
    if _selected_poi.is_empty():
        return 0
    var destination := Vector2(float(_selected_poi.get("x", 0.0)), float(_selected_poi.get("z", 0.0)))
    var spawn: Dictionary = _data.get("spawn", {"x": 760.0, "z": 330.0})
    var home := Vector2(float(spawn.get("x", 760.0)), float(spawn.get("z", 330.0)))
    if String(_selected_poi.get("id", "")) == "spawn" or destination.distance_to(home) <= 100.0:
        return 0
    var distance := 0.0
    if _vehicle != null:
        distance = Vector2(_vehicle.global_position.x, _vehicle.global_position.z).distance_to(destination)
    return mini(250 + int(round(distance / 100.0)) * 10, 900)


func _on_route_button_pressed() -> void:
    if _selected_poi.is_empty():
        return
    if _route_active and String(_route_poi.get("id", "")) == String(_selected_poi.get("id", "")):
        clear_route()
        return
    _route_poi = _selected_poi.duplicate(true)
    _route_active = true
    _route_points.clear()
    destination_changed.emit(get_route_destination())
    _update_detail()
    _refresh_map()


func _on_travel_button_pressed() -> void:
    if _selected_poi.is_empty():
        return
    fast_travel_requested.emit(get_selected_destination(), _travel_cost_for_selected(), String(_selected_poi.get("name", "Точка")))


func get_minimap_points() -> Array:
    var result: Array = []
    for poi in _pois:
        var poi_dict: Dictionary = poi
        if not _poi_passes_filter(poi_dict) and String(poi_dict.get("id", "")) != String(_route_poi.get("id", "")):
            continue
        result.append({
            "name": String(poi_dict.get("name", "")),
            "category": String(poi_dict.get("category", "")),
            "position": Vector2(float(poi_dict.get("x", 0.0)), float(poi_dict.get("z", 0.0))),
        })
    return result


func get_selected_destination() -> Vector2:
    if _selected_poi.is_empty():
        return Vector2.INF
    return Vector2(float(_selected_poi.get("x", 0.0)), float(_selected_poi.get("z", 0.0)))


func _emit_destination_changed() -> void:
    # Kept as a compatibility helper: only an explicitly created
    # route is a navigation destination, mere inspection is not.
    destination_changed.emit(get_route_destination())


func _district_name_at(x: float, z: float) -> String:
    var best_name := "Пустынный каньон" if _is_desert() else "RichTown"
    var best_score := INF
    var point := Vector2(x, z)
    for district_variant in _data.get("districts", []):
        var district: Dictionary = district_variant
        var centre := Vector2(float(district.get("x", 0.0)), float(district.get("z", 0.0)))
        var radius := maxf(float(district.get("radiusM", 200.0)), 1.0)
        var score := centre.distance_to(point) / radius
        if score < best_score:
            best_score = score
            best_name = _district_display_name(district)
    return best_name


func _update_player_info() -> void:
    if _player_label == null:
        return
    if _vehicle == null:
        _player_label.text = "ИГРОК: нет данных"
        return
    var p := _vehicle.global_position
    _player_label.text = "ИГРОК: %s  •  X %.1f  •  Z %.1f  •  ↑ север −Z%s" % [
        _district_name_at(p.x, p.z),
        p.x,
        p.z,
        "  •  перетаскивайте карту, масштаб — колесо/пинч" if _hint_visible else "",
    ]


func _format_distance(distance_m: float) -> String:
    if distance_m >= 1000.0:
        return "%.2f км" % (distance_m / 1000.0)
    return "%d м" % int(round(distance_m))


func _update_detail() -> void:
    if _detail_label == null:
        return
    if not _selected_poi.is_empty():
        var x := float(_selected_poi.get("x", 0.0))
        var z := float(_selected_poi.get("z", 0.0))
        var distance_text := "расстояние: —"
        if _vehicle != null:
            var p := _vehicle.global_position
            distance_text = "расстояние от игрока: %s" % _format_distance(Vector2(p.x, p.z).distance_to(Vector2(x, z)))
        _detail_label.text = "%s  •  %s  •  район: %s  •  X %.0f • Z %.0f  •  %s" % [
            String(_selected_poi.get("name", "Точка")),
            String(_selected_poi.get("category", "Точка")),
            _district_name_at(x, z),
            x,
            z,
            distance_text,
        ]
    elif _has_hover_world:
        _detail_label.text = "Координаты под указателем: X %.1f • Z %.1f  •  район: %s" % [_hover_world.x, _hover_world.y, _district_name_at(_hover_world.x, _hover_world.y)]
    else:
        _detail_label.text = "Выберите точку на карте или в списке справа"
    if not _travel_status.is_empty():
        _detail_label.text += "  •  " + _travel_status
    if _route_button != null and _travel_button != null:
        var has_selected := not _selected_poi.is_empty()
        var is_route := has_selected and _route_active and String(_route_poi.get("id", "")) == String(_selected_poi.get("id", ""))
        _route_button.disabled = not has_selected
        _route_button.text = "УБРАТЬ МАРШРУТ" if is_route else "МАРШРУТ"
        var cost := _travel_cost_for_selected()
        _travel_button.disabled = not has_selected
        _travel_button.text = "ПЕРЕЙТИ • БЕСПЛАТНО" if cost == 0 else "ПЕРЕЙТИ • CR %d" % cost


func _refresh_map() -> void:
    if _canvas == null:
        return
    _canvas.queue_redraw()
    _refresh_labels()


func _try_position_label(label: Label, can_show: bool, accepted: Array) -> void:
    if label == null or _canvas == null:
        return
    var point := _world_to_map(float(label.get_meta("world_x", 0.0)), float(label.get_meta("world_z", 0.0)))
    var expanded := Rect2(Vector2(-260.0, -80.0), _canvas.size + Vector2(520.0, 160.0))
    if not can_show or not expanded.has_point(point):
        label.visible = false
        return
    if label.size.x < 2.0 or label.size.y < 2.0:
        label.reset_size()
    var offset: Vector2 = label.get_meta("offset", Vector2.ZERO)
    var target := point + offset
    if bool(label.get_meta("centre_label", false)):
        target -= label.size * 0.5
    target.x = clampf(target.x, 4.0, maxf(_canvas.size.x - label.size.x - 4.0, 4.0))
    target.y = clampf(target.y, 4.0, maxf(_canvas.size.y - label.size.y - 4.0, 4.0))
    var rect := Rect2(target, label.size)
    for accepted_variant in accepted:
        var accepted_rect: Rect2 = accepted_variant
        if rect.intersects(accepted_rect.grow(4.0)):
            label.visible = false
            return
    label.position = target
    label.visible = true
    accepted.append(rect)


func _refresh_labels() -> void:
    if _canvas == null:
        return
    var accepted: Array = []
    var selected_id := String(_selected_poi.get("id", ""))
    var route_id := String(_route_poi.get("id", "")) if _route_active else ""
    var show_districts := _zoom_factor < 1.55
    # Reserve space for the inspected/routed POI first: its label
    # must never be the one sacrificed to a district or road name.
    for label_variant in _poi_labels:
        var priority_label := label_variant as Label
        var priority_id := String(priority_label.get_meta("poi_id", ""))
        if priority_id == selected_id or priority_id == route_id:
            _try_position_label(priority_label, true, accepted)
    for label_variant in _district_labels:
        _try_position_label(label_variant as Label, show_districts, accepted)
    for label_variant in _poi_labels:
        var label := label_variant as Label
        var poi_id := String(label.get_meta("poi_id", ""))
        if poi_id == selected_id or poi_id == route_id:
            continue
        var priority := int(label.get_meta("priority", 3))
        var passes_filter := _active_filter == "all" or String(label.get_meta("filter", "landmarks")) == _active_filter
        var zoom_show := (priority <= 1 and _zoom_factor >= 1.55) or (priority == 2 and _zoom_factor >= 2.20) or (priority >= 3 and _zoom_factor >= 3.0)
        _try_position_label(label, passes_filter and zoom_show, accepted)
    for label_variant in _road_labels:
        var label := label_variant as Label
        var priority := int(label.get_meta("priority", 2))
        var show := (priority <= 1 and _zoom_factor >= 1.20) or (priority >= 2 and _zoom_factor >= 1.75)
        _try_position_label(label, show, accepted)
    if _scale_label != null:
        var scale_length := 100.0 * _pixels_per_meter()
        _scale_label.position = Vector2(18.0 + scale_length * 0.5 - 20.0, _canvas.size.y - 42.0)
        _scale_label.size = Vector2(48.0, 18.0)
        _scale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _draw_world_rect(min_x: float, max_x: float, min_z: float, max_z: float, color: Color) -> void:
    var top_left := _world_to_map(min_x, max_z)
    var bottom_right := _world_to_map(max_x, min_z)
    _canvas.draw_rect(Rect2(top_left, bottom_right - top_left), color, true)


func _draw_zone(name: String, color: Color) -> void:
    var zones: Dictionary = _data.get("zones", {})
    var zone: Dictionary = zones.get(name, {})
    if zone.is_empty():
        return
    _draw_world_rect(
        float(zone.get("minX", 0.0)),
        float(zone.get("maxX", 0.0)),
        float(zone.get("minZ", 0.0)),
        float(zone.get("maxZ", 0.0)),
        color
    )


func _category_color(category: String) -> Color:
    match category:
        "Башня":
            return Color(1.0, 0.58, 0.10, 1.0)
        "Культура":
            return Color(0.86, 0.42, 1.0, 1.0)
        "Парк":
            return Color(0.22, 0.95, 0.42, 1.0)
        "Отель":
            return Color(1.0, 0.78, 0.28, 1.0)
        "Кафе":
            return Color(1.0, 0.38, 0.52, 1.0)
        "Старт":
            return Color(0.15, 0.92, 1.0, 1.0)
        "Гонка":
            return Color(1.0, 0.20, 0.12, 1.0)
        "Дом":
            return Color(0.55, 0.92, 1.0, 1.0)
        "Пляж":
            return Color(1.0, 0.86, 0.34, 1.0)
        _:
            return Color(0.55, 0.82, 1.0, 1.0)


func _draw_map() -> void:
    if _canvas == null:
        return
    var rect := Rect2(Vector2.ZERO, _canvas.size)
    _canvas.draw_rect(rect, Color(0.13, 0.10, 0.06, 1.0) if _is_desert() else Color(0.055, 0.11, 0.13, 1.0), true)
    if _data.is_empty():
        _canvas.draw_line(Vector2(12.0, 12.0), _canvas.size - Vector2(12.0, 12.0), Color(1.0, 0.2, 0.1), 3.0, true)
        return

    if _is_desert():
        _draw_zone("salt", Color(0.92, 0.90, 0.82, 0.80))
        _draw_zone("dunes", Color(0.85, 0.66, 0.38, 0.50))
        _draw_zone("plateau", Color(0.62, 0.44, 0.32, 0.42))
        _draw_zone("quarry", Color(0.55, 0.50, 0.44, 0.46))
        _draw_zone("oilField", Color(0.45, 0.40, 0.34, 0.42))
        _draw_zone("town", Color(0.80, 0.62, 0.42, 0.36))
        _draw_zone("oasisLake", Color(0.10, 0.55, 0.62, 0.88))
    else:
        _draw_zone("sea", Color(0.035, 0.36, 0.62, 0.95))
        _draw_zone("marina", Color(0.05, 0.46, 0.70, 0.88))
        _draw_zone("beach", Color(0.72, 0.58, 0.32, 0.48))
        _draw_zone("palmIsland", Color(0.20, 0.50, 0.28, 0.48))
        _draw_zone("sailIsland", Color(0.20, 0.50, 0.28, 0.48))
        _draw_zone("rtPlaza", Color(0.68, 0.68, 0.62, 0.36))

    var bounds := _bounds()
    var grid_color := Color(1.0, 1.0, 1.0, 0.055)
    var grid_x := ceilf(float(bounds.get("minX", 520.0)) / 100.0) * 100.0
    while grid_x <= float(bounds.get("maxX", 1500.0)):
        _canvas.draw_line(_world_to_map(grid_x, float(bounds.get("minZ", -500.0))), _world_to_map(grid_x, float(bounds.get("maxZ", 500.0))), grid_color, 1.0)
        grid_x += 100.0
    var grid_z := ceilf(float(bounds.get("minZ", -500.0)) / 100.0) * 100.0
    while grid_z <= float(bounds.get("maxZ", 500.0)):
        _canvas.draw_line(_world_to_map(float(bounds.get("minX", 520.0)), grid_z), _world_to_map(float(bounds.get("maxX", 1500.0)), grid_z), grid_color, 1.0)
        grid_z += 100.0

    if _world != null:
        for park_variant in _world.get_park_map_entries():
            var park: Dictionary = park_variant
            var park_rect: Rect2 = park.get("rect", Rect2())
            var top_left := _world_to_map(park_rect.position.x, park_rect.position.y + park_rect.size.y)
            var bottom_right := _world_to_map(park_rect.position.x + park_rect.size.x, park_rect.position.y)
            var draw_rect := Rect2(top_left, bottom_right - top_left)
            _canvas.draw_rect(draw_rect, Color(0.12, 0.58, 0.22, 0.62), true)
            _canvas.draw_rect(draw_rect, Color(0.45, 1.0, 0.55, 0.45), false, 1.0)

    if _zoom_factor >= 1.7:
        for building_variant in _data.get("buildings", []):
            var building: Dictionary = building_variant
            var centre := _world_to_map(float(building.get("x", 0.0)), float(building.get("z", 0.0)))
            if not Rect2(Vector2(-60.0, -60.0), _canvas.size + Vector2(120.0, 120.0)).has_point(centre):
                continue
            var width_m := float(building.get("w", 10.0))
            var depth_m := float(building.get("d", 10.0))
            if absf(absf(float(building.get("rotY", 0.0))) - PI * 0.5) < 0.2:
                var swap := width_m
                width_m = depth_m
                depth_m = swap
            var pixel_size := Vector2(maxf(width_m * _pixels_per_meter(), 2.0), maxf(depth_m * _pixels_per_meter(), 2.0))
            var color := Color(0.72, 0.78, 0.86, 0.50)
            if String(building.get("model", "generic")) != "generic":
                color = Color(1.0, 0.68, 0.20, 0.72)
            _canvas.draw_rect(Rect2(centre - pixel_size * 0.5, pixel_size), color, true)

    var casing_width := clampf(5.2 * _pixels_per_meter(), 2.4, 11.0)
    var centre_width := clampf(2.2 * _pixels_per_meter(), 1.1, 5.0)
    for road_variant in _data.get("roads", []):
        var road: Dictionary = road_variant
        var points := PackedVector2Array()
        for sample_variant in road.get("samples", []):
            var sample: Array = sample_variant
            if sample.size() >= 3:
                points.append(_world_to_map(float(sample[0]), float(sample[2])))
        if points.size() >= 2:
            _canvas.draw_polyline(points, Color(0.025, 0.04, 0.055, 0.92), casing_width, true)
            _canvas.draw_polyline(points, Color(0.90, 0.94, 0.98, 0.88), centre_width, true)

    var selected_id := String(_selected_poi.get("id", ""))
    var player_point := Vector2.ZERO
    var has_player := false
    if _vehicle != null:
        player_point = _world_to_map(_vehicle.global_position.x, _vehicle.global_position.z)
        has_player = true

    if has_player and _route_active and not _route_poi.is_empty():
        if _route_points.size() >= 2:
            var route_map_points := PackedVector2Array()
            for route_point in _route_points:
                route_map_points.append(_world_to_map(route_point.x, route_point.y))
            _canvas.draw_polyline(route_map_points, Color(1.0, 0.52, 0.05, 0.34), 7.0, true)
            _canvas.draw_polyline(route_map_points, Color(1.0, 0.62, 0.08, 0.96), 3.0, true)
        else:
            var target_point := _world_to_map(float(_route_poi.get("x", 0.0)), float(_route_poi.get("z", 0.0)))
            var total := player_point.distance_to(target_point)
            var direction := (target_point - player_point).normalized() if total > 0.01 else Vector2.ZERO
            var travelled := 0.0
            while travelled < total:
                var segment_end := minf(travelled + 9.0, total)
                _canvas.draw_line(player_point + direction * travelled, player_point + direction * segment_end, Color(1.0, 0.66, 0.10, 0.82), 2.2, true)
                travelled += 17.0

    for poi in _pois:
        var poi_dict: Dictionary = poi
        var poi_id := String(poi_dict.get("id", ""))
        if not _poi_passes_filter(poi_dict) and poi_id != selected_id and not (_route_active and poi_id == String(_route_poi.get("id", ""))):
            continue
        var point := _world_to_map(float(poi_dict.get("x", 0.0)), float(poi_dict.get("z", 0.0)))
        if not Rect2(Vector2(-30.0, -30.0), _canvas.size + Vector2(60.0, 60.0)).has_point(point):
            continue
        var selected := poi_id == selected_id
        var color := _category_color(String(poi_dict.get("category", "")))
        if selected:
            _canvas.draw_arc(point, 15.0, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.95), 2.2, true)
        _canvas.draw_circle(point, 8.0 if selected else 6.2, color)
        _canvas.draw_arc(point, 8.0 if selected else 6.2, 0.0, TAU, 32, Color(0.0, 0.03, 0.06, 0.95), 1.4, true)
        _canvas.draw_circle(point, 2.0, Color.WHITE)

    if has_player:
        var forward := -_vehicle.global_transform.basis.z
        var direction := Vector2(forward.x, -forward.z)
        direction = direction.normalized() if direction.length_squared() > 0.001 else Vector2.UP
        var right := Vector2(-direction.y, direction.x)
        var triangle := PackedVector2Array([
            player_point + direction * 13.0,
            player_point - direction * 8.0 + right * 6.0,
            player_point - direction * 8.0 - right * 6.0,
        ])
        _canvas.draw_colored_polygon(triangle, Color(1.0, 0.48, 0.08, 1.0))
        _canvas.draw_arc(player_point, 10.0, 0.0, TAU, 40, Color.WHITE, 1.5, true)
        _canvas.draw_circle(player_point, 2.2, Color.WHITE)

    var scale_start := Vector2(18.0, _canvas.size.y - 18.0)
    var scale_end := scale_start + Vector2(100.0 * _pixels_per_meter(), 0.0)
    _canvas.draw_line(scale_start, scale_end, Color.WHITE, 3.0, true)
    _canvas.draw_line(scale_start + Vector2(0.0, -5.0), scale_start + Vector2(0.0, 5.0), Color.WHITE, 2.0, true)
    _canvas.draw_line(scale_end + Vector2(0.0, -5.0), scale_end + Vector2(0.0, 5.0), Color.WHITE, 2.0, true)
    _canvas.draw_rect(rect, Color(1.0, 0.62, 0.12, 0.85), false, 1.6)


func _begin_drag(index: int, local_position: Vector2) -> void:
    _drag_index = index
    _drag_start = local_position
    _last_drag_position = local_position
    _drag_distance = 0.0
    _hover_world = _map_to_world(local_position)
    _has_hover_world = true
    _update_detail()
    _canvas.accept_event()


func _move_drag(local_position: Vector2) -> void:
    var delta := local_position - _last_drag_position
    _last_drag_position = local_position
    _drag_distance = maxf(_drag_distance, _drag_start.distance_to(local_position))
    var ppm := _pixels_per_meter()
    _centre_world.x -= delta.x / ppm
    _centre_world.y += delta.y / ppm
    _clamp_centre()
    _hover_world = _map_to_world(local_position)
    _has_hover_world = true
    _update_detail()
    _refresh_map()
    _canvas.accept_event()


func _end_drag(index: int, local_position: Vector2) -> void:
    if index != _drag_index:
        return
    var was_click := _drag_distance < 8.0
    _drag_index = NO_DRAG
    if was_click:
        _select_poi_at(local_position)
    _canvas.accept_event()


func _select_poi_at(local_position: Vector2) -> void:
    var best_id := ""
    var best_distance := 30.0
    for poi in _pois:
        var poi_dict: Dictionary = poi
        if not _poi_passes_filter(poi_dict):
            continue
        var point := _world_to_map(float(poi_dict.get("x", 0.0)), float(poi_dict.get("z", 0.0)))
        var distance := local_position.distance_to(point)
        if distance < best_distance:
            best_distance = distance
            best_id = String(poi_dict.get("id", ""))
    if not best_id.is_empty():
        _select_poi_by_id(best_id, false)


func _on_canvas_gui_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        var touch := event as InputEventScreenTouch
        if touch.pressed:
            if touch.double_tap:
                _set_zoom_factor(_zoom_factor * 1.65, touch.position)
                _canvas.accept_event()
            else:
                _touch_points[touch.index] = touch.position
                if _touch_points.size() == 2:
                    _drag_index = NO_DRAG
                    _pinch_active = true
                    var points := _touch_points.values()
                    _pinch_centre = (points[0] + points[1]) * 0.5
                    _pinch_distance = (points[0] as Vector2).distance_to(points[1])
                    _canvas.accept_event()
                elif _drag_index == NO_DRAG:
                    _begin_drag(touch.index, touch.position)
        else:
            var was_pinching := _pinch_active
            _touch_points.erase(touch.index)
            if was_pinching:
                _pinch_active = false
                _pinch_distance = 0.0
                _drag_index = NO_DRAG
                if _touch_points.size() == 1:
                    var remaining_index := int(_touch_points.keys()[0])
                    _begin_drag(remaining_index, _touch_points[remaining_index])
                    _drag_distance = 99.0
                _canvas.accept_event()
            else:
                _end_drag(touch.index, touch.position)
    elif event is InputEventScreenDrag:
        var drag := event as InputEventScreenDrag
        if _touch_points.has(drag.index):
            _touch_points[drag.index] = drag.position
        if _pinch_active and _touch_points.size() >= 2:
            var points := _touch_points.values()
            var new_centre: Vector2 = (points[0] + points[1]) * 0.5
            var new_distance := (points[0] as Vector2).distance_to(points[1])
            if _pinch_distance > 0.5 and new_distance > 0.5:
                var midpoint_delta := new_centre - _pinch_centre
                var ppm := _pixels_per_meter()
                _centre_world.x -= midpoint_delta.x / ppm
                _centre_world.y += midpoint_delta.y / ppm
                _set_zoom_factor(_zoom_factor * new_distance / _pinch_distance, new_centre)
            _pinch_centre = new_centre
            _pinch_distance = new_distance
            _canvas.accept_event()
        elif drag.index == _drag_index:
            _move_drag(drag.position)
    elif event is InputEventMouseButton:
        var button := event as InputEventMouseButton
        match button.button_index:
            MOUSE_BUTTON_WHEEL_UP:
                if button.pressed:
                    _set_zoom_factor(_zoom_factor * 1.16, button.position)
                _canvas.accept_event()
            MOUSE_BUTTON_WHEEL_DOWN:
                if button.pressed:
                    _set_zoom_factor(_zoom_factor / 1.16, button.position)
                _canvas.accept_event()
            MOUSE_BUTTON_LEFT:
                if button.pressed:
                    if button.double_click:
                        _set_zoom_factor(_zoom_factor * 1.65, button.position)
                        _canvas.accept_event()
                    elif _drag_index == NO_DRAG:
                        _begin_drag(MOUSE_DRAG, button.position)
                else:
                    _end_drag(MOUSE_DRAG, button.position)
    elif event is InputEventMouseMotion:
        var motion := event as InputEventMouseMotion
        if _drag_index == MOUSE_DRAG:
            _move_drag(motion.position)
        else:
            _hover_world = _map_to_world(motion.position)
            _has_hover_world = true
            if _selected_poi.is_empty():
                _update_detail()
    elif event is InputEventMagnifyGesture:
        if not _pinch_active:
            var gesture := event as InputEventMagnifyGesture
            _set_zoom_factor(_zoom_factor * maxf(gesture.factor, 0.01), gesture.position)
        _canvas.accept_event()
