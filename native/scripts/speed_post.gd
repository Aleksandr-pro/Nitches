class_name NativeSpeedPost
extends MeshInstance3D

## Drive-база «Для godot»: полноэкранный speed post-эффект.
##
## Исходный speed_post.gd зависел от класса ArcadeCar и всегда держал
## полноэкранный проход включённым.  Эта версия получает только нормализованную
## скорость из NativeVehicle через main.gd, поэтому её можно безопасно
## использовать с текущей физикой, а на малой скорости квад полностью
## выключается ради мобильного FPS.

const SPEED_SHADER: Shader = preload("res://shaders/speed_post.gdshader")
const SMOOTHING := 4.0
const VISIBLE_EPSILON := 0.015

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
	material_override = _material
	visible = false


func set_speed_ratio(value: float) -> void:
	_target_ratio = clampf(value, 0.0, 1.0)


func _process(delta: float) -> void:
	var weight := 1.0 - exp(-SMOOTHING * maxf(delta, 0.0))
	_amount = lerpf(_amount, _target_ratio, weight)
	visible = _amount > VISIBLE_EPSILON or _target_ratio > VISIBLE_EPSILON
	if _material != null:
		_material.set_shader_parameter("speed", _amount)


func get_smoke_state() -> Dictionary:
	return {
		"ready": _material != null and _material.shader != null and mesh != null,
		"amount": _amount,
		"target": _target_ratio,
		"visible": visible,
	}
