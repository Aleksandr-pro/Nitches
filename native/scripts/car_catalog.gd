class_name NativeCarCatalog
extends RefCounted

## 0.2.40 multi-car catalogue.
##
## One dictionary per playable car is the single source for the menu spec
## sheet, RigidBody dimensions, raycast suspension layout, drivetrain,
## torque curve, camera/effect anchor points and garage defaults.  The
## Shelby entry reproduces the pre-0.2.40 constants exactly; the three new
## entries use the owner-supplied model/spec files:
##
## * Audo R8 V10 plus: 5.2 V10, 610 hp, 560 Nm, AWD.
## * Chevrole Kamaro SS: 6.2 LT1 V8, 455 hp, 617 Nm, RWD.
## * Mercedez-Bens 560 SEL: 5.5 V8, 300 hp, 455 Nm, RWD.
##
## 0.2.61: display names are lightly fictionalised so the game needs
## no manufacturer licences; ids/model paths stay stable for saves.
##
## All lengths are metres in vehicle-local Godot axes (nose -Z, up +Y,
## origin on the ground midway between the axles), matching the GLB
## contract produced by scripts/blender_convert_supplied_cars.py.

const DEFAULT_CAR_ID := "shelby_gt500"
const COMMON_STEERING_WHEEL_TEXTURE := "res://assets/ui/steering_wheel_common.png"
const COMMON_STEERING_WHEEL_ID := "common_sport"


static func car_ids() -> Array[String]:
	return [
		"shelby_gt500",
		"audi_r8_v10_plus",
		"chevrolet_camaro_ss",
		"mercedes_560_sel",
		"bugatti_chiron_super_sport",
	]


static func has_car(car_id: String) -> bool:
	return car_ids().has(car_id)


static func normalize_id(car_id: String) -> String:
	return car_id if has_car(car_id) else DEFAULT_CAR_ID


static func get_car(car_id: String) -> Dictionary:
	var cars := _build_cars()
	var safe_id := normalize_id(car_id)
	return (cars[safe_id] as Dictionary).duplicate(true)


static func all_cars() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for car_id in car_ids():
		result.append(get_car(car_id))
	return result


static func get_cars() -> Array[Dictionary]:
	return all_cars()


static func car_count() -> int:
	return car_ids().size()


static func get_menu_cars(customizations: Dictionary, stats_by_car: Dictionary, selected_car_id: String) -> Array:
	var result: Array = []
	var selected := normalize_id(selected_car_id)
	var tuning_multipliers: Array[float] = [1.0, 1.08, 1.16]
	for car in all_cars():
		var entry := car.duplicate(true)
		var car_id := String(entry.get("id", ""))
		var customization := default_customization(car_id)
		var saved_customization := customizations.get(car_id, {}) as Dictionary
		for key in saved_customization.keys():
			customization[key] = saved_customization[key]
		var owned := clampi(int(customization.get("owned_tuning_level", customization.get("tuning_owned_max", 0))), 0, tuning_multipliers.size() - 1)
		var tuning_level := clampi(int(customization.get("tuning_level", 0)), 0, owned)
		customization["owned_tuning_level"] = owned
		customization["tuning_owned_max"] = owned
		customization["tuning_level"] = tuning_level
		var base_pi := int(entry.get("performance_index", 612))
		var adds: Array = entry.get("tuning_pi_add", [0, 36, 89])
		var tuning_pis: Array[int] = []
		var tuning_classes: Array[String] = []
		for level in tuning_multipliers.size():
			var level_pi := base_pi + (int(adds[level]) if level < adds.size() else 0)
			tuning_pis.append(level_pi)
			tuning_classes.append(class_label_for_pi(level_pi))
		var multiplier := tuning_multipliers[tuning_level]
		var ratings := (entry.get("ratings", {}) as Dictionary).duplicate(true)
		if ratings.has("accel"):
			ratings["acceleration"] = ratings.get("accel")
		entry["ratings"] = ratings
		entry["car_id"] = car_id
		entry["selected"] = car_id == selected
		entry["customization"] = customization.duplicate(true)
		entry["stats"] = (stats_by_car.get(car_id, {}) as Dictionary).duplicate(true)
		entry["tuning_level"] = tuning_level
		entry["owned_tuning_level"] = owned
		entry["base_performance_index"] = base_pi
		entry["performance_index"] = tuning_pis[tuning_level]
		entry["class_label"] = tuning_classes[tuning_level]
		entry["tuning_performance_index"] = tuning_pis
		entry["tuning_class_labels"] = tuning_classes
		entry["effective_power_hp"] = int(round(float(entry.get("power_hp", 0)) * multiplier))
		entry["effective_torque_nm"] = int(round(float(entry.get("torque_nm", 0)) * multiplier))
		entry["effective_accel_0_100_s"] = float(entry.get("accel_0_100_s", 6.0)) / sqrt(multiplier)
		result.append(entry)
	return result


static func class_label_for_pi(performance_index: int) -> String:
	if performance_index >= 900:
		return "X"
	if performance_index >= 800:
		return "S2"
	if performance_index >= 700:
		return "S1"
	if performance_index >= 600:
		return "A"
	if performance_index >= 500:
		return "B"
	if performance_index >= 400:
		return "C"
	return "D"


static func default_customization(car_id: String) -> Dictionary:
	var car := get_car(car_id)
	return {
		"paint_id": String(car.get("default_paint_id", "red")),
		"paint_color": car.get("default_paint_color", Color(0.48, 0.025, 0.035)),
		"wheel_finish": String(car.get("default_wheel_finish", "silver")),
		"tuning_level": 0,
		"owned_tuning_level": 0,
		"tuning_owned_max": 0,
		"license_plate": String(car.get("default_plate", "NITCHES")),
	}


static func _build_cars() -> Dictionary:
	return {
		"shelby_gt500": _shelby(),
		"audi_r8_v10_plus": _audi_r8(),
		"chevrolet_camaro_ss": _camaro_ss(),
		"mercedes_560_sel": _mercedes_560_sel(),
		"bugatti_chiron_super_sport": _bugatti_chiron(),
	}


static func _common() -> Dictionary:
	return {
		"steering_wheel_texture": COMMON_STEERING_WHEEL_TEXTURE,
		"steering_wheel_id": COMMON_STEERING_WHEEL_ID,
		"price_cr": 0,
		"owned_by_default": true,
		# Shelby keeps the established 0.2.35 paint response.  The
		# supplied cars override this profile below: silver and black
		# factory paints need a much smoother clearcoat and finer,
		# cooler flakes or they read as dusty/matte at gameplay range.
		"paint_metallic": 0.68,
		"paint_roughness": 0.19,
		"paint_clearcoat": 1.0,
		"paint_clearcoat_roughness": 0.075,
		"paint_flake_density": 180.0,
		"paint_flake_strength": 0.5,
		"paint_flake_tint_amount": 0.58,
		"paint_fresnel_strength": 0.24,
		"paint_fresnel_tint_amount": 0.32,
	}


static func _with_common(car: Dictionary) -> Dictionary:
	var result := _common()
	for key in car.keys():
		result[key] = car[key]
	return result


static func _shelby() -> Dictionary:
	return _with_common({
		"id": "shelby_gt500",
		"name": "Shelbie GT500",
		"price_cr": 0,
		"owned_by_default": true,
		"short_name": "GT500",
		"year": 1967,
		"year_label": "'67",
		"category": "МАСЛКАР • ЗАДНИЙ ПРИВОД",
		"engine": "V8, 7.0 л (428 cid)",
		"power_hp": 365,
		"power_note": "SAE gross",
		"torque_nm": 569,
		"torque_rpm": 3200,
		"accel_0_100_s": 6.0,
		"top_speed_kmh": 207,
		"gearbox": "4-ступенчатая механика",
		"drive": "задний",
		"drivetrain": "rwd",
		"model_path": "res://assets/vehicles/mustang.glb",
		"mass_kg": 1450.0,
		"center_of_mass": Vector3(0.0, 0.38, 0.02),
		"angular_damp": 0.38,
		"length_m": 4.64,
		"width_m": 1.84,
		"height_m": 1.32,
		"wheelbase_m": 2.86,
		"front_track_m": 1.64,
		"rear_track_m": 1.64,
		"wheel_radius_m": 0.3378,
		"wheel_ray_y": 0.58,
		"body_collision_size": Vector3(1.84, 0.68, 4.64),
		"body_collision_position": Vector3(0.0, 0.62, 0.0),
		"cabin_collision_size": Vector3(1.58, 0.54, 2.05),
		"cabin_collision_position": Vector3(0.0, 1.03, 0.18),
		"spring_stiffness": 28000.0,
		"spring_damping_compression": 3600.0,
		"spring_damping_rebound": 2150.0,
		"anti_roll_front": 8000.0,
		"anti_roll_rear": 6400.0,
		"spring_force_limit": 26500.0,
		"gear_ratios": [2.32, 1.69, 1.29, 1.00],
		"reverse_ratio": 2.78,
		"final_drive": 3.91,
		"idle_rpm": 850.0,
		"redline_rpm": 6400.0,
		"shift_up_rpm": 5950.0,
		"shift_down_rpm": 2050.0,
		"torque_curve": [
			Vector2(850.0, 0.62), Vector2(1800.0, 0.80), Vector2(3200.0, 1.00),
			Vector2(4400.0, 0.97), Vector2(5400.0, 0.88), Vector2(6000.0, 0.78),
			Vector2(6400.0, 0.66),
		],
		"drag_area": 0.72,
		"downforce_area": 0.52,
		"tyre_grip_multiplier": 1.0,
		"brake_force": 21500.0,
		"performance_index": 612,
		"tuning_pi_add": [0, 36, 89],
		"ratings": {"speed": 6.4, "accel": 6.8, "handling": 5.2, "drift": 7.5},
		"default_paint_id": "red",
		"default_paint_color": Color(0.48, 0.025, 0.035),
		"secondary_paint_color": Color(0.92, 0.88, 0.80),
		"default_wheel_finish": "silver",
		"default_plate": "GT500-67",
		"audio_bank_id": "shelby_gt500",
		"headlight_position": Vector3(0.62, 0.74, -2.22),
		"plate_front_position": Vector3(0.0, 0.58, -2.335),
		"plate_rear_position": Vector3(0.0, 0.58, 2.335),
		"exhaust_position": Vector3(0.56, 0.36, 2.34),
		"smoke_x": 0.82,
		"smoke_z": 1.50,
		"contact_shadow_size": Vector2(2.28, 5.08),
		"hood_camera_position": Vector3(0.0, 1.12, -0.32),
		"garage_camera_scale": 1.0,
		"camera_distance_scale": 1.0,
		"silhouette": "muscle",
	})


static func _audi_r8() -> Dictionary:
	return _with_common({
		"id": "audi_r8_v10_plus",
		"name": "Audo R8 V10 plus",
		"price_cr": 50000,
		"owned_by_default": false,
		"short_name": "R8 V10 plus",
		"year": 2016,
		"year_label": "'16",
		"category": "СУПЕРКАР • ПОЛНЫЙ ПРИВОД",
		"engine": "V10 FSI, 5.2 л",
		"power_hp": 610,
		"power_note": "DIN",
		"torque_nm": 560,
		"torque_rpm": 6500,
		"accel_0_100_s": 3.2,
		"top_speed_kmh": 330,
		"gearbox": "7-ступенчатый S tronic",
		"drive": "полный quattro",
		"drivetrain": "awd",
		"model_path": "res://assets/vehicles/audi_r8_v10_plus.glb",
		"mass_kg": 1555.0,
		"center_of_mass": Vector3(0.0, 0.34, 0.22),
		"angular_damp": 0.46,
		"length_m": 4.426,
		"width_m": 1.967,
		"height_m": 1.201,
		"wheelbase_m": 2.644,
		"front_track_m": 1.639,
		"rear_track_m": 1.637,
		"wheel_radius_m": 0.3134,
		"wheel_ray_y": 0.53,
		"body_collision_size": Vector3(1.90, 0.58, 4.30),
		"body_collision_position": Vector3(0.0, 0.49, -0.10),
		"cabin_collision_size": Vector3(1.50, 0.48, 2.05),
		"cabin_collision_position": Vector3(0.0, 0.88, -0.25),
		"spring_stiffness": 39000.0,
		"spring_damping_compression": 4700.0,
		"spring_damping_rebound": 2800.0,
		"anti_roll_front": 12500.0,
		"anti_roll_rear": 10500.0,
		"spring_force_limit": 34000.0,
		"gear_ratios": [3.40, 2.35, 1.78, 1.40, 1.13, 0.96, 0.845],
		"reverse_ratio": 3.05,
		"final_drive": 3.60,
		"idle_rpm": 900.0,
		"redline_rpm": 8500.0,
		"shift_up_rpm": 8000.0,
		"shift_down_rpm": 2650.0,
		"torque_curve": [
			Vector2(900.0, 0.48), Vector2(2000.0, 0.68), Vector2(3500.0, 0.82),
			Vector2(5000.0, 0.92), Vector2(6500.0, 1.00), Vector2(7500.0, 0.96),
			Vector2(8000.0, 0.94), Vector2(8500.0, 0.90),
		],
		"drag_area": 0.64,
		"downforce_area": 0.95,
		"tyre_grip_multiplier": 1.10,
		"brake_force": 26500.0,
		"performance_index": 862,
		"tuning_pi_add": [0, 24, 55],
		"ratings": {"speed": 10.0, "accel": 9.8, "handling": 9.3, "drift": 6.4},
		"default_paint_id": "silver",
		"default_paint_color": Color(0.56, 0.60, 0.65),
		"secondary_paint_color": Color(0.025, 0.028, 0.032),
		"paint_metallic": 0.86,
		"paint_roughness": 0.075,
		"paint_clearcoat_roughness": 0.025,
		"paint_flake_density": 300.0,
		"paint_flake_strength": 0.16,
		"paint_flake_tint_amount": 0.20,
		"paint_fresnel_strength": 0.14,
		"paint_fresnel_tint_amount": 0.18,
		"default_wheel_finish": "silver",
		"default_plate": "R8-V10",
		"audio_bank_id": "audi_r8",
		"headlight_position": Vector3(0.68, 0.55, -2.28),
		"plate_front_position": Vector3(0.0, 0.48, -2.333),
		"plate_rear_position": Vector3(0.0, 0.62, 2.125),
		"exhaust_position": Vector3(0.58, 0.38, 2.12),
		"smoke_x": 0.82,
		"smoke_z": 1.39,
		"contact_shadow_size": Vector2(2.30, 4.82),
		"hood_camera_position": Vector3(0.0, 1.02, -0.55),
		"garage_camera_scale": 0.95,
		"camera_distance_scale": 0.96,
		"silhouette": "supercar",
	})


static func _camaro_ss() -> Dictionary:
	return _with_common({
		"id": "chevrolet_camaro_ss",
		"name": "Chevrole Kamaro SS",
		"price_cr": 95000,
		"owned_by_default": false,
		"short_name": "Camaro SS",
		"year": 2017,
		"year_label": "'17",
		"category": "МАСЛКАР • ЗАДНИЙ ПРИВОД",
		"engine": "V8 LT1, 6.2 л",
		"power_hp": 455,
		"power_note": "SAE net",
		"torque_nm": 617,
		"torque_rpm": 4400,
		"accel_0_100_s": 4.2,
		"top_speed_kmh": 290,
		"gearbox": "8-ступенчатый автомат",
		"drive": "задний",
		"drivetrain": "rwd",
		"model_path": "res://assets/vehicles/chevrolet_camaro_ss.glb",
		"mass_kg": 1671.0,
		"center_of_mass": Vector3(0.0, 0.44, -0.06),
		"angular_damp": 0.42,
		"length_m": 4.783,
		"width_m": 2.038,
		"height_m": 1.347,
		"wheelbase_m": 2.792,
		"front_track_m": 1.574,
		"rear_track_m": 1.574,
		"wheel_radius_m": 0.3377,
		"wheel_ray_y": 0.57,
		"body_collision_size": Vector3(1.92, 0.62, 4.62),
		"body_collision_position": Vector3(0.0, 0.56, 0.04),
		"cabin_collision_size": Vector3(1.55, 0.48, 2.00),
		"cabin_collision_position": Vector3(0.0, 0.95, 0.25),
		"spring_stiffness": 34000.0,
		"spring_damping_compression": 4200.0,
		"spring_damping_rebound": 2500.0,
		"anti_roll_front": 10500.0,
		"anti_roll_rear": 9000.0,
		"spring_force_limit": 31500.0,
		"gear_ratios": [4.56, 2.97, 2.08, 1.69, 1.27, 1.00, 0.85, 0.65],
		"reverse_ratio": 3.82,
		"final_drive": 2.77,
		"idle_rpm": 750.0,
		"redline_rpm": 6500.0,
		"shift_up_rpm": 6100.0,
		"shift_down_rpm": 2100.0,
		"torque_curve": [
			Vector2(750.0, 0.55), Vector2(1800.0, 0.78), Vector2(3000.0, 0.92),
			Vector2(4400.0, 1.00), Vector2(5200.0, 0.96), Vector2(6000.0, 0.86),
			Vector2(6500.0, 0.78),
		],
		"drag_area": 0.62,
		"downforce_area": 0.48,
		"tyre_grip_multiplier": 1.04,
		"brake_force": 24500.0,
		"performance_index": 724,
		"tuning_pi_add": [0, 34, 82],
		"ratings": {"speed": 8.8, "accel": 8.4, "handling": 7.8, "drift": 8.8},
		"default_paint_id": "blue",
		"default_paint_color": Color(0.0, 0.62, 0.95),
		"secondary_paint_color": Color(0.03, 0.032, 0.038),
		"paint_metallic": 0.74,
		"paint_roughness": 0.12,
		"paint_clearcoat_roughness": 0.045,
		"paint_flake_density": 240.0,
		"paint_flake_strength": 0.28,
		"paint_flake_tint_amount": 0.38,
		"paint_fresnel_strength": 0.20,
		"paint_fresnel_tint_amount": 0.26,
		"default_wheel_finish": "black",
		"default_plate": "CAMARO-SS",
		"audio_bank_id": "camaro_ss",
		"headlight_position": Vector3(0.68, 0.66, -2.32),
		"plate_front_position": Vector3(0.0, 0.52, -2.372),
		"plate_rear_position": Vector3(0.0, 0.60, 2.45),
		"exhaust_position": Vector3(0.62, 0.38, 2.43),
		"smoke_x": 0.79,
		"smoke_z": 1.47,
		"contact_shadow_size": Vector2(2.36, 5.18),
		"hood_camera_position": Vector3(0.0, 1.08, -0.45),
		"garage_camera_scale": 1.03,
		"camera_distance_scale": 1.02,
		"silhouette": "muscle_modern",
	})


static func _mercedes_560_sel() -> Dictionary:
	return _with_common({
		"id": "mercedes_560_sel",
		"name": "Mercedez-Bens 560 SEL",
		"price_cr": 160000,
		"owned_by_default": false,
		"short_name": "560 SEL",
		"year": 1990,
		"year_label": "'90",
		"category": "ПРЕМИУМ-СЕДАН • ЗАДНИЙ ПРИВОД",
		"engine": "V8 M117, 5.5 л",
		"power_hp": 300,
		"power_note": "ECE",
		"torque_nm": 455,
		"torque_rpm": 3750,
		"accel_0_100_s": 6.8,
		"top_speed_kmh": 250,
		"gearbox": "4-ступенчатый автомат",
		"drive": "задний",
		"drivetrain": "rwd",
		"model_path": "res://assets/vehicles/mercedes_benz_560_sel.glb",
		"mass_kg": 1830.0,
		"center_of_mass": Vector3(0.0, 0.50, -0.15),
		"angular_damp": 0.34,
		"length_m": 5.160,
		"width_m": 1.955,
		"height_m": 1.446,
		"wheelbase_m": 3.006,
		"front_track_m": 1.514,
		"rear_track_m": 1.531,
		"wheel_radius_m": 0.3257,
		"wheel_ray_y": 0.56,
		"body_collision_size": Vector3(1.80, 0.68, 5.02),
		"body_collision_position": Vector3(0.0, 0.60, 0.14),
		"cabin_collision_size": Vector3(1.56, 0.58, 2.45),
		"cabin_collision_position": Vector3(0.0, 1.02, 0.15),
		"spring_stiffness": 30000.0,
		"spring_damping_compression": 3400.0,
		"spring_damping_rebound": 2100.0,
		"anti_roll_front": 6500.0,
		"anti_roll_rear": 5200.0,
		"spring_force_limit": 30500.0,
		"gear_ratios": [3.87, 2.25, 1.44, 1.00],
		"reverse_ratio": 3.30,
		"final_drive": 2.65,
		"idle_rpm": 700.0,
		"redline_rpm": 6000.0,
		"shift_up_rpm": 5400.0,
		"shift_down_rpm": 1800.0,
		"torque_curve": [
			Vector2(700.0, 0.58), Vector2(1500.0, 0.76), Vector2(2500.0, 0.90),
			Vector2(3750.0, 1.00), Vector2(5000.0, 0.925), Vector2(5600.0, 0.82),
			Vector2(6000.0, 0.72),
		],
		"drag_area": 0.78,
		"downforce_area": 0.20,
		"tyre_grip_multiplier": 0.94,
		"brake_force": 23500.0,
		"performance_index": 536,
		"tuning_pi_add": [0, 32, 78],
		"ratings": {"speed": 7.4, "accel": 6.2, "handling": 5.4, "drift": 5.8},
		"default_paint_id": "black",
		"default_paint_color": Color(0.018, 0.020, 0.024),
		"secondary_paint_color": Color(0.16, 0.17, 0.18),
		"paint_metallic": 0.82,
		"paint_roughness": 0.065,
		"paint_clearcoat_roughness": 0.022,
		"paint_flake_density": 300.0,
		"paint_flake_strength": 0.12,
		"paint_flake_tint_amount": 0.16,
		"paint_fresnel_strength": 0.12,
		"paint_fresnel_tint_amount": 0.16,
		"default_wheel_finish": "silver",
		"default_plate": "560-SEL",
		"audio_bank_id": "mercedes_560_sel",
		"headlight_position": Vector3(0.68, 0.78, -2.40),
		"plate_front_position": Vector3(0.0, 0.58, -2.452),
		"plate_rear_position": Vector3(0.0, 0.72, 2.74),
		"exhaust_position": Vector3(0.48, 0.36, 2.72),
		"smoke_x": 0.76,
		"smoke_z": 1.58,
		"contact_shadow_size": Vector2(2.28, 5.55),
		"hood_camera_position": Vector3(0.0, 1.25, -0.55),
		"garage_camera_scale": 1.11,
		"camera_distance_scale": 1.10,
		"silhouette": "sedan",
	})


static func _bugatti_chiron() -> Dictionary:
	return _with_common({
		"id": "bugatti_chiron_super_sport",
		"name": "Bygatti Shiron Super Sport",
		"price_cr": 350000,
		"owned_by_default": false,
		"short_name": "Shiron Super Sport",
		"year": 2021,
		"year_label": "'21",
		"category": "ГИПЕРКАР • ПОЛНЫЙ ПРИВОД",
		"engine": "W16, 8.0 л, 4 турбины",
		"power_hp": 1600,
		"power_note": "DIN",
		"torque_nm": 1600,
		"torque_rpm": 2000,
		"accel_0_100_s": 2.4,
		"top_speed_kmh": 440,
		"gearbox": "7-ступенчатый робот DCT",
		"drive": "полный",
		"drivetrain": "awd",
		"model_path": "res://assets/vehicles/bugatti_chiron_super_sport.glb",
		"mass_kg": 1975.0,
		"center_of_mass": Vector3(0.0, 0.32, 0.28),
		"angular_damp": 0.44,
		"length_m": 4.794,
		"width_m": 2.038,
		"height_m": 1.212,
		"wheelbase_m": 2.724,
		"front_track_m": 1.754,
		"rear_track_m": 1.679,
		"wheel_radius_m": 0.352,
		"wheel_ray_y": 0.56,
		"body_collision_size": Vector3(1.98, 0.55, 4.55),
		"body_collision_position": Vector3(0.0, 0.47, 0.04),
		"cabin_collision_size": Vector3(1.55, 0.42, 1.90),
		"cabin_collision_position": Vector3(0.0, 0.85, -0.15),
		"spring_stiffness": 47000.0,
		"spring_damping_compression": 5600.0,
		"spring_damping_rebound": 3400.0,
		"anti_roll_front": 15000.0,
		"anti_roll_rear": 13000.0,
		"spring_force_limit": 42000.0,
		"gear_ratios": [3.20, 2.188, 1.583, 1.167, 0.881, 0.690, 0.542],
		"reverse_ratio": 3.00,
		"final_drive": 2.671,
		"idle_rpm": 950.0,
		"redline_rpm": 7100.0,
		"shift_up_rpm": 6800.0,
		"shift_down_rpm": 2400.0,
		"torque_curve": [
			Vector2(950.0, 0.62), Vector2(1500.0, 0.85), Vector2(2000.0, 1.00),
			Vector2(4000.0, 1.00), Vector2(6000.0, 1.00), Vector2(7000.0, 1.00),
			Vector2(7100.0, 0.97),
		],
		"drag_area": 0.69,
		"downforce_area": 0.80,
		"tyre_grip_multiplier": 1.16,
		"brake_force": 34000.0,
		"performance_index": 968,
		"tuning_pi_add": [0, 18, 40],
		"ratings": {"speed": 10.0, "accel": 10.0, "handling": 8.6, "drift": 5.2},
		"default_paint_id": "black",
		"default_paint_color": Color(0.020, 0.020, 0.022),
		"secondary_paint_color": Color(0.965, 0.054, 0.008),
		"paint_metallic": 0.86,
		"paint_roughness": 0.075,
		"paint_clearcoat_roughness": 0.025,
		"paint_flake_density": 300.0,
		"paint_flake_strength": 0.10,
		"paint_flake_tint_amount": 0.20,
		"paint_fresnel_strength": 0.14,
		"paint_fresnel_tint_amount": 0.18,
		"default_wheel_finish": "black",
		"default_plate": "W16-SS",
		"audio_bank_id": "bugatti_chiron",
		"headlight_position": Vector3(0.72, 0.58, -2.32),
		"plate_front_position": Vector3(0.0, 0.42, -2.40),
		"plate_rear_position": Vector3(0.0, 0.72, 2.42),
		"exhaust_position": Vector3(0.18, 0.45, 2.42),
		"smoke_x": 0.84,
		"smoke_z": 1.36,
		"contact_shadow_size": Vector2(2.40, 5.20),
		"hood_camera_position": Vector3(0.0, 1.00, -0.35),
		"garage_camera_scale": 0.98,
		"camera_distance_scale": 1.00,
		"silhouette": "supercar",
	})
