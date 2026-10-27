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
const STEER_RESPONSE := 24.0
const STEER_ACTUATOR_RATE_LOW := 6.4
const STEER_ACTUATOR_RATE_HIGH := 3.4
const STEER_RETURN_RATE_LOW := 8.0
const STEER_RETURN_RATE_HIGH := 4.8
const DIGITAL_STEER_ATTACK_LOW := 5.8
const DIGITAL_STEER_ATTACK_HIGH := 4.0
const DIGITAL_STEER_RETURN_LOW := 7.5
const DIGITAL_STEER_RETURN_HIGH := 6.0
const DIGITAL_STEER_REVERSE_LOW := 9.0
const DIGITAL_STEER_REVERSE_HIGH := 7.5
const STEERING_INPUT_CURVE := 1.18
const STEERING_DEADBAND := 0.02
const DIGITAL_STEER_INITIAL_BITE := 0.18


static func steering_limit(speed_ms: float) -> float:
	var t := clampf(absf(speed_ms) / STEER_SPEED_REF_MS, 0.0, 1.0)
	return lerpf(MAX_STEER_RAD, MIN_STEER_RAD, t * t)


static func shape_steering_input(raw_input: float) -> float:
	var magnitude := absf(clampf(raw_input, -1.0, 1.0))
	if magnitude <= STEERING_DEADBAND:
		return 0.0
	# Remove the deadband before the precision curve so a centred stick
	# is truly centred but the first usable travel starts near zero.
	magnitude = (magnitude - STEERING_DEADBAND) / (1.0 - STEERING_DEADBAND)
	return signf(raw_input) * pow(magnitude, STEERING_INPUT_CURVE)


static func ramp_digital_steering(current: float, target: float, delta: float, speed_ms: float) -> float:
	if delta <= 0.0:
		return target
	# Initial bite: the first usable command appears on the first
	# physics tick, instead of waiting for a purely linear ramp to
	# become perceptible.  Duration after that still encodes lock, so
	# a 30-50 ms tap remains a small, precise correction.
	if absf(target) > 0.01 and absf(current) <= STEERING_DEADBAND:
		current = signf(target) * DIGITAL_STEER_INITIAL_BITE
	var speed_t := clampf(absf(speed_ms) / STEER_SPEED_REF_MS, 0.0, 1.0)
	var rate := lerpf(DIGITAL_STEER_ATTACK_LOW, DIGITAL_STEER_ATTACK_HIGH, speed_t)
	if absf(target) < 0.01:
		rate = lerpf(DIGITAL_STEER_RETURN_LOW, DIGITAL_STEER_RETURN_HIGH, speed_t)
	elif absf(current) > 0.01 and signf(target) != signf(current):
		rate = lerpf(DIGITAL_STEER_REVERSE_LOW, DIGITAL_STEER_REVERSE_HIGH, speed_t)
	return clampf(move_toward(current, target, rate * delta), -1.0, 1.0)


static func responsive_steering(current: float, target: float, delta: float, speed_ms: float) -> float:
	if delta <= 0.0:
		return target
	var error := target - current
	if absf(error) <= 0.0004:
		return target
	var speed_t := clampf(absf(speed_ms) / STEER_SPEED_REF_MS, 0.0, 1.0)
	var returning := absf(target) < absf(current) or (absf(current) > 0.001 and absf(target) > 0.001 and signf(target) != signf(current))
	var max_rate := lerpf(
		STEER_RETURN_RATE_LOW if returning else STEER_ACTUATOR_RATE_LOW,
		STEER_RETURN_RATE_HIGH if returning else STEER_ACTUATOR_RATE_HIGH,
		speed_t
	)
	# A rate-limited rack with a fast small-error response: large inputs
	# start immediately without the old 7/s exponential lag, while tiny
	# corrections land precisely and never overshoot the requested lock.
	var precision_step := error * (1.0 - exp(-STEER_RESPONSE * delta))
	var step := clampf(precision_step, -max_rate * delta, max_rate * delta)
	return current + step


static func smooth_steering(current: float, target: float, delta: float) -> float:
	return responsive_steering(current, target, delta, 0.0)


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
		"steering_precision_0231": true,
		"steer_actuator_rate_low": STEER_ACTUATOR_RATE_LOW,
		"steer_return_rate_low": STEER_RETURN_RATE_LOW,
		"digital_steer_attack": DIGITAL_STEER_ATTACK_LOW,
		"digital_steer_reverse": DIGITAL_STEER_REVERSE_LOW,
		"steering_input_curve": STEERING_INPUT_CURVE,
		"steering_deadband": STEERING_DEADBAND,
		"digital_steer_initial_bite": DIGITAL_STEER_INITIAL_BITE,
	}
