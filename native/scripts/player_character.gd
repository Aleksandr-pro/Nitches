class_name NativePlayerCharacter
extends Node3D

## 0.3.28: procedural locomotion for the jointed player avatar.
## The GLB ships a translation-only limb hierarchy (Torso, Head,
## Thigh/Shin/Foot, UpperArm/Forearm per side) with zero bind
## rotations, so this script poses it directly — no Skeleton3D,
## no skinning, no animation player.  Movement physics lives in
## main.gd (`_step_on_foot`); this node only turns the resulting
## ground speed into a readable gait: leg swing with knee flex,
## counter-swinging arms, torso lean and a gentle vertical bob.
## All poses are written as absolute rotations each call, so the
## bind pose is always recovered by zero speed.

var _model: Node3D
var _torso: Node3D
var _head: Node3D
var _thigh_l: Node3D
var _shin_l: Node3D
var _foot_l: Node3D
var _thigh_r: Node3D
var _shin_r: Node3D
var _foot_r: Node3D
var _upper_arm_l: Node3D
var _forearm_l: Node3D
var _upper_arm_r: Node3D
var _forearm_r: Node3D

var _phase := 0.0
var _move_weight := 0.0
var _speed_blend := 0.0
var _idle_timer := 0.0


func _find_limb(limb_name: String) -> Node3D:
	if _model == null:
		return null
	var found := _model.find_child(limb_name, true, false)
	return found as Node3D


func bind_model(model: Node3D) -> void:
	_model = model
	add_child(model)
	_torso = _find_limb("Torso")
	_head = _find_limb("Head")
	_thigh_l = _find_limb("ThighL")
	_shin_l = _find_limb("ShinL")
	_foot_l = _find_limb("FootL")
	_thigh_r = _find_limb("ThighR")
	_shin_r = _find_limb("ShinR")
	_foot_r = _find_limb("FootR")
	_upper_arm_l = _find_limb("UpperArmL")
	_forearm_l = _find_limb("ForearmL")
	_upper_arm_r = _find_limb("UpperArmR")
	_forearm_r = _find_limb("ForearmR")


func has_limb_hierarchy() -> bool:
	return (
		_torso != null
		and _head != null
		and _thigh_l != null
		and _shin_l != null
		and _foot_l != null
		and _thigh_r != null
		and _shin_r != null
		and _foot_r != null
		and _upper_arm_l != null
		and _forearm_l != null
		and _upper_arm_r != null
		and _forearm_r != null
	)


func get_locomotion_state() -> Dictionary:
	return {
		"phase": _phase,
		"move_weight": _move_weight,
		"speed_blend": _speed_blend,
		"has_limbs": has_limb_hierarchy(),
	}


func _set_limb_x(limb: Node3D, angle: float) -> void:
	if limb != null:
		limb.rotation.x = angle


## Poses the avatar for this frame.  `speed_mps` is the actual
## horizontal ground speed (post-collision), so pushing against a
## wall idles instead of moonwalking.  Positive rotation.x swings
## a limb forward (the avatar faces -Z): the lower end moves -Z.
func set_locomotion(speed_mps: float, grounded: bool, delta: float) -> void:
	if _model == null:
		return
	_idle_timer += maxf(delta, 0.0)
	var target_move := 1.0 if (grounded and speed_mps > 0.12) else 0.0
	_move_weight = lerpf(_move_weight, target_move, clampf(delta * 7.0, 0.0, 1.0))
	_speed_blend = lerpf(_speed_blend, clampf(speed_mps / 5.5, 0.0, 1.0), clampf(delta * 5.0, 0.0, 1.0))

	# Stride frequency: ~1.8 Hz walk to ~2.55 Hz run.  Phase only
	# advances while actually covering ground.
	if grounded and speed_mps > 0.05:
		_phase = wrapf(_phase + delta * TAU * lerpf(1.8, 2.55, _speed_blend), 0.0, TAU)

	var swing := lerpf(0.52, 0.88, _speed_blend) * _move_weight
	var stride := sin(_phase)
	var thigh_l_angle := swing * stride
	var thigh_r_angle := -swing * stride
	# Knees flex most while the leg swings through (just after
	# toe-off), so the shin peak trails the thigh peak slightly.
	var knee_amp := lerpf(0.55, 1.05, _speed_blend) * _move_weight
	var shin_l_angle := -knee_amp * maxf(0.0, sin(_phase - 0.85)) - 0.04 * _move_weight
	var shin_r_angle := -knee_amp * maxf(0.0, sin(_phase + PI - 0.85)) - 0.04 * _move_weight
	# Feet counter-rotate to stay flatter against the ground.
	var foot_l_angle := -(thigh_l_angle + shin_l_angle) * 0.6
	var foot_r_angle := -(thigh_r_angle + shin_r_angle) * 0.6
	# Arms counter-swing against the same-side leg; elbows keep a
	# natural bend that pumps a little harder while running.
	var arm_swing := swing * 0.72
	var upper_l_angle := -arm_swing * stride
	var upper_r_angle := arm_swing * stride
	var elbow_base := lerpf(0.16, 0.5, _speed_blend) * _move_weight + 0.06
	var forearm_l_angle := elbow_base - arm_swing * 0.35 * stride
	var forearm_r_angle := elbow_base + arm_swing * 0.35 * stride
	# Torso leans into the motion and counter-rotates a touch;
	# the head stabilises against the lean.  At rest a slow
	# breathing sway replaces the lean.
	var breathe := sin(_idle_timer * 1.7) * 0.014 * (1.0 - _move_weight)
	var torso_pitch := -(0.05 + 0.09 * _speed_blend) * _move_weight + breathe
	var torso_yaw := 0.075 * stride * _move_weight

	if not grounded:
		# Airborne tuck: split legs, bent knees, arms lifted.
		thigh_l_angle = lerpf(thigh_l_angle, 0.38, 0.75)
		thigh_r_angle = lerpf(thigh_r_angle, -0.3, 0.75)
		shin_l_angle = lerpf(shin_l_angle, -0.55, 0.75)
		shin_r_angle = lerpf(shin_r_angle, -0.4, 0.75)
		foot_l_angle = lerpf(foot_l_angle, 0.25, 0.75)
		foot_r_angle = lerpf(foot_r_angle, 0.25, 0.75)
		upper_l_angle = lerpf(upper_l_angle, 0.5, 0.6)
		upper_r_angle = lerpf(upper_r_angle, 0.5, 0.6)
		forearm_l_angle = lerpf(forearm_l_angle, 0.45, 0.6)
		forearm_r_angle = lerpf(forearm_r_angle, 0.45, 0.6)
		torso_pitch = lerpf(torso_pitch, -0.06, 0.6)

	_set_limb_x(_thigh_l, thigh_l_angle)
	_set_limb_x(_shin_l, shin_l_angle)
	_set_limb_x(_foot_l, foot_l_angle)
	_set_limb_x(_thigh_r, thigh_r_angle)
	_set_limb_x(_shin_r, shin_r_angle)
	_set_limb_x(_foot_r, foot_r_angle)
	_set_limb_x(_upper_arm_l, upper_l_angle)
	_set_limb_x(_forearm_l, forearm_l_angle)
	_set_limb_x(_upper_arm_r, upper_r_angle)
	_set_limb_x(_forearm_r, forearm_r_angle)
	if _torso != null:
		_torso.rotation.x = torso_pitch
		_torso.rotation.y = torso_yaw
	if _head != null:
		_head.rotation.x = -torso_pitch * 0.72
		_head.rotation.y = -torso_yaw * 0.5
	# Two soft bounces per stride cycle; the model root bobs so
	# the feet never sink below the authored ground plane.
	_model.position.y = absf(sin(_phase)) * lerpf(0.035, 0.055, _speed_blend) * _move_weight
