class_name NativeLoadingScreen
extends CanvasLayer

## 0.2.52 branded first-frame loading screen.
##
## The engine boot splash uses the same real RichTown gameplay frame
## (with the wordmark baked into the boot image), then this overlay
## takes over for the actual staged world build: live stage names,
## percentage, five checkpoints, rotating gameplay tips and a very
## slow Ken Burns drift so the still frame never feels frozen while
## a heavy build stage is running.

signal error_continue_requested

const BACKGROUND_TEXTURE: Texture2D = preload("res://assets/ui/menu_richtown_gameplay.jpg")
const COL_TEXT := Color(0.96, 0.98, 1.0)
const COL_MUTED := Color(0.72, 0.78, 0.85)
const COL_ACCENT := Color(1.0, 0.58, 0.08)
const COL_BORDER := Color(1.0, 1.0, 1.0, 0.22)
const COL_ERROR := Color(1.0, 0.36, 0.30)
const MIN_FONT_SIZE := 14
const MIN_DISPLAY_SECONDS := 0.65
const CHECKPOINT_LABELS: Array[String] = ["ДАННЫЕ", "МИР", "АВТО", "ИНТЕРФЕЙС", "ГОТОВО"]
const GENERIC_TIPS: Array[String] = [
	"Совет: откройте карту, поставьте точку маршрута и следуйте живой линии на дороге и миникарте.",
	"Совет: в гараже перед покупкой тюнинга видны характеристики автомобиля до и после.",
	"Совет: на грунте, гравии и песке тормозите раньше, чем на сухом асфальте.",
	"Совет: день, закат и ночь меняют не только картинку, но и настроение поездки.",
]
const RICHTOWN_TIPS: Array[String] = [
	"Совет: на закате набережная, стеклянные башни и остров Паруса выглядят особенно красиво.",
	"Совет: бульвар RichTown удобен для длинных разгонов, а районные улицы — для точного дрифта.",
]
const FOREST_TIPS: Array[String] = [
	"Совет: в болоте и на грязных берегах держите скорость ниже — мокрый грунт почти не держит автомобиль.",
	"Совет: на вершине северных холмов есть смотровая площадка, а у водопада — удобная фото-точка.",
]

const DESERT_TIPS: Array[String] = [
	"Совет: на гравийных тропах дозируйте газ — автомобиль начинает скользить раньше, чем на асфальте.",
	"Совет: у оазиса, каменной арки и серпантина есть удобные места для красивых кадров.",
]

var _is_built := false
var _context_initialized := false
var _is_finishing := false
var _has_error := false
var _world_id := "richtown"
var _elapsed := 0.0
var _shown_msec := 0
var _target_progress := 0.0
var _displayed_progress := 0.0
var _last_percent := -1
var _tip_timer := 0.0
var _tip_index := 0
var _tips: Array[String] = []

var _body_font: Font
var _heading_font: Font
var _root: Control
var _background: TextureRect
var _world_label: Label
var _world_subtitle_label: Label
var _version_label: Label
var _stage_label: Label
var _percent_label: Label
var _tip_label: Label
var _error_label: Label
var _continue_button: Button
var _progress_bar: ProgressBar
var _progress_fill: StyleBoxFlat
var _checkpoint_dots: Array[Label] = []
var _checkpoint_captions: Array[Label] = []


func _ready() -> void:
	layer = 1024
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_fonts()
	_build_ui()
	_shown_msec = Time.get_ticks_msec()
	if not _context_initialized:
		restart("richtown")
	get_viewport().size_changed.connect(_on_viewport_size_changed)


func _process(delta: float) -> void:
	if not visible or not _is_built:
		return
	_elapsed += maxf(delta, 0.0)
	_update_background_motion()
	if _displayed_progress < _target_progress:
		var weight := 1.0 - exp(-7.5 * maxf(delta, 0.0))
		_displayed_progress = lerpf(_displayed_progress, _target_progress, weight)
		if _target_progress - _displayed_progress < 0.0015:
			_displayed_progress = _target_progress
		_refresh_progress_widgets()
	if _has_error:
		return
	_tip_timer += maxf(delta, 0.0)
	if _tip_timer >= 3.6 and not _tips.is_empty():
		_tip_timer = 0.0
		_tip_index = (_tip_index + 1) % _tips.size()
		_tip_label.text = _tips[_tip_index]


func restart(world_id: String) -> void:
	if not _is_built:
		_make_fonts()
		_build_ui()
	_world_id = world_id
	_context_initialized = true
	_is_finishing = false
	_elapsed = 0.0
	_shown_msec = Time.get_ticks_msec()
	_target_progress = 0.0
	_displayed_progress = 0.0
	_last_percent = -1
	visible = true
	set_process(true)
	_root.modulate = Color.WHITE
	clear_error()
	_world_label.text = "ПУСТЫННЫЙ КАНЬОН" if world_id == "desert" else ("ЗЕЛЁНЫЙ ЛЕС" if world_id == "greenforest" else "RICHTOWN")
	_world_subtitle_label.text = "дюны • соляное плато • оазис" if world_id == "desert" else ("озеро • холмы • фермерская долина" if world_id == "greenforest" else "город • набережная • остров Паруса")
	_tips.clear()
	if world_id == "desert":
		_tips.append_array(DESERT_TIPS)
	elif world_id == "greenforest":
		_tips.append_array(FOREST_TIPS)
	else:
		_tips.append_array(RICHTOWN_TIPS)
	_tips.append_array(GENERIC_TIPS)
	_tip_index = int(Time.get_ticks_msec() / 1000) % maxi(_tips.size(), 1)
	_tip_timer = 0.0
	if not _tips.is_empty():
		_tip_label.text = _tips[_tip_index]
	set_progress(0.0, "Подготавливаем игру")
	_update_background_pivot()


func set_progress(fraction: float, stage: String) -> void:
	if not _is_built:
		return
	_target_progress = maxf(_target_progress, clampf(fraction, 0.0, 1.0))
	if not _has_error:
		_stage_label.text = stage
	_refresh_progress_widgets()


func set_error(message: String) -> void:
	if not _is_built:
		return
	_has_error = true
	_stage_label.text = "Мир загружен с ошибкой"
	_error_label.text = message
	_error_label.visible = true
	_continue_button.visible = true
	_progress_fill.bg_color = COL_ERROR
	_percent_label.text = "!"


func clear_error() -> void:
	if not _is_built:
		return
	_has_error = false
	_error_label.visible = false
	_continue_button.visible = false
	_progress_fill.bg_color = COL_ACCENT
	_refresh_progress_widgets()


func hide_immediately() -> void:
	visible = false
	set_process(false)


func finish() -> void:
	if not _is_built or not visible or _is_finishing or _has_error:
		return
	_is_finishing = true
	set_progress(1.0, "Готово")
	var elapsed_seconds := float(Time.get_ticks_msec() - _shown_msec) / 1000.0
	if elapsed_seconds < MIN_DISPLAY_SECONDS:
		await get_tree().create_timer(MIN_DISPLAY_SECONDS - elapsed_seconds).timeout
	var waited_frames := 0
	while _displayed_progress < 0.999 and waited_frames < 28:
		await get_tree().process_frame
		waited_frames += 1
	_displayed_progress = 1.0
	_refresh_progress_widgets()
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, 0.30)
	await tween.finished
	visible = false
	set_process(false)
	_is_finishing = false


func get_visual_state() -> Dictionary:
	return {
		"custom_loading_screen_0252": _is_built,
		"real_gameplay_background": BACKGROUND_TEXTURE != null,
		"checkpoints": _checkpoint_captions.size(),
		"tips": _tips.size(),
		"displayed_progress": _displayed_progress,
		"error_visible": _has_error,
	}


func _on_viewport_size_changed() -> void:
	_update_background_pivot()


func _on_continue_pressed() -> void:
	if _has_error:
		error_continue_requested.emit()


func _update_background_pivot() -> void:
	if _background != null and _background.size.x > 1.0 and _background.size.y > 1.0:
		_background.pivot_offset = _background.size * 0.5


func _update_background_motion() -> void:
	if _background == null:
		return
	_update_background_pivot()
	var zoom_t := clampf(_elapsed / 22.0, 0.0, 1.0)
	_background.scale = Vector2.ONE * lerpf(1.035, 1.085, zoom_t)


func _refresh_progress_widgets() -> void:
	if not _is_built:
		return
	_progress_bar.value = _displayed_progress * 100.0
	var percent := int(round(_displayed_progress * 100.0))
	if percent != _last_percent:
		_last_percent = percent
		if not _has_error:
			_percent_label.text = "%d%%" % percent
	var active_checkpoint := 0
	if _displayed_progress >= 0.97:
		active_checkpoint = 4
	elif _displayed_progress >= 0.86:
		active_checkpoint = 3
	elif _displayed_progress >= 0.74:
		active_checkpoint = 2
	elif _displayed_progress >= 0.12:
		active_checkpoint = 1
	for i in range(_checkpoint_dots.size()):
		var dot := _checkpoint_dots[i]
		var caption := _checkpoint_captions[i]
		dot.text = "●" if i <= active_checkpoint else "○"
		if i == active_checkpoint:
			dot.add_theme_color_override("font_color", COL_ACCENT)
			caption.add_theme_color_override("font_color", COL_TEXT)
		elif i < active_checkpoint:
			dot.add_theme_color_override("font_color", COL_TEXT)
			caption.add_theme_color_override("font_color", COL_MUTED)
		else:
			dot.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.38))
			caption.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.46))


func _make_fonts() -> void:
	if _body_font != null and _heading_font != null:
		return
	var body := FontVariation.new()
	body.base_font = ThemeDB.fallback_font
	body.variation_embolden = 0.08
	_body_font = body
	var heading := FontVariation.new()
	heading.base_font = ThemeDB.fallback_font
	heading.variation_embolden = 0.62
	heading.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(-0.14, 1.0), Vector2.ZERO)
	_heading_font = heading


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


func _make_label(text: String, size: int, color: Color = COL_TEXT, heading: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _heading_font if heading else _body_font)
	label.add_theme_font_size_override("font_size", maxi(size, MIN_FONT_SIZE))
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.72))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _build_ui() -> void:
	if _is_built:
		return
	_root = Control.new()
	_root.name = "LoadingRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_background = TextureRect.new()
	_background.name = "RichTownGameplayBackground"
	_background.texture = BACKGROUND_TEXTURE
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_background)

	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.004, 0.008, 0.014, 0.42))
	gradient.set_color(1, Color(0.004, 0.008, 0.014, 0.90))
	gradient.add_point(0.44, Color(0.004, 0.008, 0.014, 0.08))
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.fill = GradientTexture2D.FILL_LINEAR
	gradient_texture.fill_from = Vector2(0.5, 0.0)
	gradient_texture.fill_to = Vector2(0.5, 1.0)
	gradient_texture.width = 16
	gradient_texture.height = 256
	var shade := TextureRect.new()
	shade.name = "CinematicShade"
	shade.texture = gradient_texture
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)

	var margin := MarginContainer.new()
	margin.name = "SafeMargin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 34)
	margin.add_theme_constant_override("margin_bottom", 34)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	margin.add_child(content)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 24)
	content.add_child(top_row)

	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", 2)
	top_row.add_child(brand)
	var accent_line := ColorRect.new()
	accent_line.name = "BrandAccent"
	accent_line.color = COL_ACCENT
	accent_line.custom_minimum_size = Vector2(64.0, 5.0)
	accent_line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	brand.add_child(accent_line)
	var title := _make_label("NITCHES", 58, COL_TEXT, true)
	brand.add_child(title)
	var subtitle := _make_label("H  O  R  I  Z  O  N", 22, COL_ACCENT, true)
	brand.add_child(subtitle)
	var tagline := _make_label("ОТКРЫТЫЙ МИР • ФЕСТИВАЛЬ СКОРОСТИ", 14, Color(1.0, 1.0, 1.0, 0.82), false)
	brand.add_child(tagline)

	var top_spacer := Control.new()
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(top_spacer)

	var world_chip := PanelContainer.new()
	world_chip.custom_minimum_size = Vector2(252.0, 0.0)
	world_chip.add_theme_stylebox_override("panel", _style(Color(0.004, 0.008, 0.014, 0.62), COL_BORDER, 8, 1))
	top_row.add_child(world_chip)
	var chip_box := VBoxContainer.new()
	chip_box.add_theme_constant_override("separation", 2)
	world_chip.add_child(chip_box)
	var chip_caption := _make_label("МИР", 14, COL_ACCENT, true)
	chip_box.add_child(chip_caption)
	_world_label = _make_label("RICHTOWN", 22, COL_TEXT, true)
	chip_box.add_child(_world_label)
	_world_subtitle_label = _make_label("город • набережная • остров Паруса", 14, COL_MUTED, false)
	chip_box.add_child(_world_subtitle_label)
	var version_text := String(ProjectSettings.get_setting("application/config/version", "0.2.53-native-alpha"))
	_version_label = _make_label("v" + version_text.split("-")[0], 14, COL_MUTED, false)
	chip_box.add_child(_version_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)

	var panel := PanelContainer.new()
	panel.name = "LoadingPanel"
	panel.custom_minimum_size = Vector2(0.0, 208.0)
	panel.add_theme_stylebox_override("panel", _style(Color(0.004, 0.008, 0.014, 0.70), COL_BORDER, 8, 1))
	content.add_child(panel)

	var panel_box := VBoxContainer.new()
	panel_box.add_theme_constant_override("separation", 10)
	panel.add_child(panel_box)

	var stage_row := HBoxContainer.new()
	stage_row.add_theme_constant_override("separation", 18)
	panel_box.add_child(stage_row)
	_stage_label = _make_label("Подготавливаем игру", 24, COL_TEXT, true)
	_stage_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_row.add_child(_stage_label)
	_percent_label = _make_label("0%", 34, COL_ACCENT, true)
	_percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stage_row.add_child(_percent_label)

	var checkpoints := HBoxContainer.new()
	checkpoints.add_theme_constant_override("separation", 8)
	panel_box.add_child(checkpoints)
	for caption_text in CHECKPOINT_LABELS:
		var checkpoint_box := VBoxContainer.new()
		checkpoint_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		checkpoint_box.add_theme_constant_override("separation", 0)
		checkpoints.add_child(checkpoint_box)
		var dot := _make_label("○", 16, Color(1.0, 1.0, 1.0, 0.38), true)
		dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		checkpoint_box.add_child(dot)
		_checkpoint_dots.append(dot)
		var caption := _make_label(caption_text, 14, Color(1.0, 1.0, 1.0, 0.46), true)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		checkpoint_box.add_child(caption)
		_checkpoint_captions.append(caption)

	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(0.0, 14.0)
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.step = 0.1
	_progress_bar.value = 0.0
	_progress_bar.show_percentage = false
	_progress_bar.add_theme_stylebox_override("background", _style(Color(1.0, 1.0, 1.0, 0.13), COL_BORDER, 3, 0))
	_progress_fill = _style(COL_ACCENT, Color.TRANSPARENT, 3, 0)
	_progress_bar.add_theme_stylebox_override("fill", _progress_fill)
	panel_box.add_child(_progress_bar)

	_tip_label = _make_label("", 15, COL_MUTED, false)
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.custom_minimum_size = Vector2(0.0, 42.0)
	panel_box.add_child(_tip_label)

	_error_label = _make_label("", 15, COL_ERROR, false)
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.visible = false
	panel_box.add_child(_error_label)

	_continue_button = Button.new()
	_continue_button.text = "ПРОДОЛЖИТЬ"
	_continue_button.custom_minimum_size = Vector2(230.0, 52.0)
	_continue_button.focus_mode = Control.FOCUS_NONE
	_continue_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_continue_button.add_theme_font_override("font", _heading_font)
	_continue_button.add_theme_font_size_override("font_size", 18)
	_continue_button.add_theme_color_override("font_color", COL_TEXT)
	_continue_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_continue_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	_continue_button.add_theme_stylebox_override("normal", _style(Color(0.55, 0.16, 0.08, 0.92), COL_BORDER, 7, 1))
	_continue_button.add_theme_stylebox_override("hover", _style(Color(0.72, 0.22, 0.10, 0.96), Color.WHITE, 7, 1))
	_continue_button.add_theme_stylebox_override("pressed", _style(Color(0.42, 0.11, 0.06, 0.96), COL_ACCENT, 7, 1))
	_continue_button.visible = false
	_continue_button.pressed.connect(_on_continue_pressed)
	panel_box.add_child(_continue_button)

	_is_built = true
	_update_background_pivot()
	_refresh_progress_widgets()
