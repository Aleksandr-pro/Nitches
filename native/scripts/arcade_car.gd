class_name NativeArcadeCarAssist
extends RefCounted

## Адаптация Drive-файла arcade_car.gd для текущего NativeVehicle.
##
## Исходный ArcadeCar — самостоятельный RigidBody3D с raycast-подвеской,
## простым двигателем и кругом трения.  NativeVehicle уже реализует ту же
## базовую схему в расширенном виде (Pacejka, Ackermann, поверхности,
## 6 передач, wheelspin/TC, ABS-подобный приоритет боковой силы, нитро).
## Заменять её упрощённой версией означало бы потерять эти системы, поэтому
## сюда перенесены две действительно полезные идеи исходника:
##
## 1. roll_reduction — силы шин прикладываются ближе к уровню центра масс,
##    отчего кузов меньше раскачивается от боковых/продольных сил;
## 2. квадратичная кривая ограничения руля по скорости и экспоненциально
##    плавный отклик руля вместо линейного цифрового рывка кнопок.

const ROLL_REDUCTION := 0.55
const MAX_STEER_RAD := 0.54
const MIN_STEER_RAD := 0.14
const STEER_SPEED_REF_MS := 48.0
const STEER_RESPONSE := 7.0


static func steering_limit(speed_ms: float) -> float:
	var t := clampf(absf(speed_ms) / STEER_SPEED_REF_MS, 0.0, 1.0)
	return lerpf(MAX_STEER_RAD, MIN_STEER_RAD, t * t)


static func smooth_steering(current: float, target: float, delta: float) -> float:
	var weight := 1.0 - exp(-STEER_RESPONSE * maxf(delta, 0.0))
	return lerpf(current, target, weight)


static func roll_reduced_force_point(contact_from_com: Vector3, surface_up: Vector3) -> Vector3:
	var up := surface_up.normalized()
	if up.length_squared() < 0.0001:
		return contact_from_com
	return contact_from_com - up * up.dot(contact_from_com) * ROLL_REDUCTION


static func get_smoke_state() -> Dictionary:
	return {
		"roll_reduction": ROLL_REDUCTION,
		"max_steer_rad": MAX_STEER_RAD,
		"min_steer_rad": MIN_STEER_RAD,
		"steer_response": STEER_RESPONSE,
	}
