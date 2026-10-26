class_name NativeDynamicWorld
extends Node

## Drive-база «Для godot»: DynamicWorld, адаптированный к RichTown.
##
## Исходный dynamic_world.gd сам создавал второй WorldEnvironment и второе
## солнце и заменял небо на PhysicalSkyMaterial.  В RichTown уже есть
## пользовательские панорамы день/закат/ночь, ночные emissive-материалы,
## ReflectionProbe и солнце с дальностью теней 520 м, поэтому эта версия
## не плодит дубли.  Она владеет пресетами цветокора/тумана/bloom и
## физическим небом-запасным вариантом, а NativeWorldBuilder применяет её
## к уже существующим Environment и DirectionalLight3D.

enum Preset { GOLDEN_HOUR, CLEAR_DAY, AUTUMN_MORNING, OVERCAST, SUNSET }

const PRESETS := {
	Preset.GOLDEN_HOUR: {
		"time": 17.5, "turbidity": 8.0, "mie": 0.008, "fog": 0.0018,
		"fog_color": Color(1.0, 0.74, 0.52), "sat": 1.18, "contrast": 1.10,
		"glow": 1.0, "exposure": 1.0, "sun_scale": 1.15, "ambient": 0.9,
	},
	Preset.CLEAR_DAY: {
		"time": 12.5, "turbidity": 4.0, "mie": 0.004, "fog": 0.0007,
		"fog_color": Color(0.70, 0.80, 0.95), "sat": 1.08, "contrast": 1.05,
		"glow": 0.5, "exposure": 1.0, "sun_scale": 1.0, "ambient": 1.0,
	},
	Preset.AUTUMN_MORNING: {
		"time": 7.0, "turbidity": 9.0, "mie": 0.010, "fog": 0.0028,
		"fog_color": Color(0.95, 0.80, 0.65), "sat": 1.20, "contrast": 1.08,
		"glow": 0.8, "exposure": 1.0, "sun_scale": 1.0, "ambient": 0.95,
	},
	Preset.OVERCAST: {
		"time": 13.0, "turbidity": 25.0, "mie": 0.02, "fog": 0.0030,
		"fog_color": Color(0.75, 0.78, 0.82), "sat": 0.90, "contrast": 1.0,
		"glow": 0.3, "exposure": 1.1, "sun_scale": 0.35, "ambient": 1.1,
	},
	Preset.SUNSET: {
		"time": 17.9, "turbidity": 10.0, "mie": 0.012, "fog": 0.0022,
		"fog_color": Color(1.0, 0.55, 0.40), "sat": 1.25, "contrast": 1.12,
		"glow": 1.2, "exposure": 1.0, "sun_scale": 1.0, "ambient": 0.8,
	},
}

# Исходные плотности тумана рассчитаны на небольшую сцену. RichTown имеет
# обзор на километр, поэтому fog масштабируется, а не копируется буквально:
# буквально 0.0022 на закате почти полностью съел бы силуэт города.
const FOG_SCALE := 0.42
const NIGHT_GRADE := {
	"sat": 1.02,
	"contrast": 1.06,
	"glow": 1.18,
	"exposure": 0.92,
	"fog": 0.00085,
}

var _physical_sky_material: PhysicalSkyMaterial
var _current_mode := "day"
var _current_preset: Preset = Preset.CLEAR_DAY


func get_physical_sky_material() -> PhysicalSkyMaterial:
	if _physical_sky_material == null:
		_physical_sky_material = PhysicalSkyMaterial.new()
		_physical_sky_material.rayleigh_coefficient = 2.2
		_physical_sky_material.sun_disk_scale = 1.0
		_physical_sky_material.ground_color = Color(0.22, 0.20, 0.17)
		_physical_sky_material.use_debanding = true
	return _physical_sky_material


func get_preset_count() -> int:
	return PRESETS.size()


func get_current_preset_name() -> String:
	if _current_mode == "night":
		return "night"
	match _current_preset:
		Preset.GOLDEN_HOUR:
			return "golden_hour"
		Preset.CLEAR_DAY:
			return "clear_day"
		Preset.AUTUMN_MORNING:
			return "autumn_morning"
		Preset.OVERCAST:
			return "overcast"
		Preset.SUNSET:
			return "sunset"
	return "clear_day"


func apply_mode(mode: String, environment: Environment, sun: DirectionalLight3D) -> void:
	if environment == null:
		return
	_current_mode = mode

	var grade: Dictionary
	match mode:
		"sunset":
			_current_preset = Preset.GOLDEN_HOUR
			grade = PRESETS[_current_preset]
		"night":
			grade = NIGHT_GRADE
		_:
			_current_preset = Preset.CLEAR_DAY
			grade = PRESETS[_current_preset]

	# Физическое небо используется, если пользовательская панорама по какой-то
	# причине не попала в экспорт. Его параметры всё равно следуют пресету.
	var physical_sky := get_physical_sky_material()
	if mode == "night":
		physical_sky.energy_multiplier = 0.12
	else:
		physical_sky.turbidity = float(grade.get("turbidity", 4.0))
		physical_sky.mie_coefficient = float(grade.get("mie", 0.004))
		physical_sky.energy_multiplier = 0.92 if mode == "sunset" else 1.0

	# Кинематографичная тональная компрессия и bloom из DynamicWorld.
	# Исходник ставил tonemap_white=6, но документация Godot 4.7 прямо
	# предупреждает: на Mobile renderer значение выше 2 делает картинку
	# тёмной. Используем мобильно-безопасный предел 1.8.
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_white = 1.8
	environment.tonemap_exposure = float(grade.get("exposure", 1.0)) * (1.04 if mode == "day" else (1.08 if mode == "sunset" else 1.0))
	environment.glow_enabled = true
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	environment.glow_strength = 0.95
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 1.0
	# CLEAR_DAY в исходнике даёт glow=0.5; для дневного RichTown это слишком
	# глушит окна/воду, поэтому дневной floor выше, а закат/ночь — по пресету.
	environment.glow_intensity = maxf(float(grade.get("glow", 0.8)), 0.78 if mode == "day" else 0.0)

	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.02
	environment.adjustment_saturation = float(grade.get("sat", 1.05))
	environment.adjustment_contrast = float(grade.get("contrast", 1.05))

	environment.fog_enabled = true
	environment.fog_sky_affect = 0.25
	environment.fog_density = float(grade.get("fog", 0.0006)) * (FOG_SCALE if mode != "night" else 1.0)
	if sun != null:
		environment.fog_light_color = environment.fog_light_color.lerp(sun.light_color, 0.18)


func get_smoke_state() -> Dictionary:
	return {
		"presets": PRESETS.size(),
		"mode": _current_mode,
		"preset": get_current_preset_name(),
		"physical_sky": get_physical_sky_material() != null,
	}
