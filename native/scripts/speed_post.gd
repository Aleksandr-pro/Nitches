class_name NativeSpeedPost
extends MeshInstance3D

## Drive-база «Для godot»: полноэкранный speed post-эффект.
##
## Исходный speed_post.gd зависел от класса ArcadeCar. Эта версия получает
## нормализованную скорость NativeVehicle: лёгкий цветовой grade/vignette/grain
## работает постоянно, а blur/chromatic aberration включаются только в движении.

const SPEED_SHADER: Shader = preload("res://shaders/speed_post.gdshader")
const SMOOTHING := 4.0

var _material: ShaderMaterial
var _target_ratio := 0.0
var _amount := 0.0


func _ready() -> void:
	name = "SpeedPost"

	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.flip_faces = true
	mesh = quad

	# Официальный fullscreen-quad приём Godot: вершинный шейдер пишет POSITION
	# напрямую в clip space, а огромный cull margin не даёт CPU отсечь квад.
	extra_cull_margin = 16384.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Отдельный визуальный слой 20: игровая камера видит все слои, а
	# ReflectionProbe в WorldBuilder этот слой из захвата исключает. Иначе
	# clip-space квад мог бы перекрыть кубические карты отражений.
	layers = 1 << 19

	_material = ShaderMaterial.new()
	_material.shader = SPEED_SHADER
	# В 3D screen texture снимается после opaque и до transparent. Самый
	# низкий приоритет рисует пост первым среди transparent-объектов: стёкла,
	# вода и частицы затем нормально дорисуются поверх, а не исчезнут под
	# полноэкранным квадом.
	_material.render_priority = -128
	_material.set_shader_parameter("speed", 0.0)
	_material.set_shader_parameter("saturation", 1.0)
	_material.set_shader_parameter("contrast", 1.06)
	_material.set_shader_parameter("shadow_tint", Vector3(0.95, 0.97, 1.0))
	_material.set_shader_parameter("highlight_tint", Vector3(1.02, 1.0, 0.96))
	_material.set_shader_parameter("split_strength", 0.28)
	_material.set_shader_parameter("vignette_strength", 0.22)
	_material.set_shader_parameter("grain", 0.005)
	material_override = _material
	# Always-on subtle color grade/vignette/grain; only the extra speed samples
	# in the fragment shader scale with _amount.
	visible = true


func set_speed_ratio(value: float) -> void:
	_target_ratio = clampf(value, 0.0, 1.0)


func _process(delta: float) -> void:
	# Preserve the inexpensive one-sample grade at all speeds. On Android the
	# additional radial blur/CA/line treatment starts only above ~75 km/h.
	var effective_target := _target_ratio
	if OS.has_feature("android") and _target_ratio < 0.35:
		effective_target = 0.0
	var weight := 1.0 - exp(-SMOOTHING * maxf(delta, 0.0))
	_amount = lerpf(_amount, effective_target, weight)
	visible = true
	if _material != null:
		_material.set_shader_parameter("speed", _amount)


func get_smoke_state() -> Dictionary:
	return {
		"ready": _material != null and _material.shader != null and mesh != null,
		"amount": _amount,
		"target": _target_ratio,
		"visible": visible,
		"cinematic_grade": _material != null and _material.shader != null,
		"always_on_vignette": _material != null and float(_material.get_shader_parameter("vignette_strength")) > 0.0,
		"film_grain": _material != null and float(_material.get_shader_parameter("grain")) > 0.0,
	}
