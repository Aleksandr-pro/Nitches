class_name NativeVehicleAudio
extends Node

## 0.2.35 recorded Shelby/Mustang vehicle audio.
##
## The continuous engine voice is not synthesized and is not a single
## stretched sample.  Sixteen phase-aligned Mustang GT500 loops are
## available in separate on-throttle and off-throttle layers.  Two
## neighbouring RPM loops are equal-power crossfaded, then the load
## layers are crossfaded from the effective pedal.  A long recorded
## Mustang idle handles the unstable big-V8 idle below the first
## driving loops; startup/shutdown and tyre squeal are also field
## recordings.  Sources and licenses live in docs/AUDIO_CREDITS.md.

const ENGINE_OFF := 0
const ENGINE_CRANKING := 1
const ENGINE_RUNNING := 2
const ENGINE_STOPPING := 3
const RECORDED_AUDIO_0235 := true
const BANK_RPMS: Array[int] = [900, 1100, 1300, 1500, 1700, 1900, 2100, 2350, 2600, 2850, 3100, 3350, 3600, 3850, 4100, 4400]
const BANK_CYCLES: Array[int] = [6, 7, 8, 9, 11, 12, 13, 15, 16, 18, 19, 21, 22, 24, 26, 28]
const ON_STREAMS: Array[AudioStream] = [
	preload("res://assets/audio/shelby/gt500_on_0900.wav"),
	preload("res://assets/audio/shelby/gt500_on_1100.wav"),
	preload("res://assets/audio/shelby/gt500_on_1300.wav"),
	preload("res://assets/audio/shelby/gt500_on_1500.wav"),
	preload("res://assets/audio/shelby/gt500_on_1700.wav"),
	preload("res://assets/audio/shelby/gt500_on_1900.wav"),
	preload("res://assets/audio/shelby/gt500_on_2100.wav"),
	preload("res://assets/audio/shelby/gt500_on_2350.wav"),
	preload("res://assets/audio/shelby/gt500_on_2600.wav"),
	preload("res://assets/audio/shelby/gt500_on_2850.wav"),
	preload("res://assets/audio/shelby/gt500_on_3100.wav"),
	preload("res://assets/audio/shelby/gt500_on_3350.wav"),
	preload("res://assets/audio/shelby/gt500_on_3600.wav"),
	preload("res://assets/audio/shelby/gt500_on_3850.wav"),
	preload("res://assets/audio/shelby/gt500_on_4100.wav"),
	preload("res://assets/audio/shelby/gt500_on_4400.wav"),
]
const OFF_STREAMS: Array[AudioStream] = [
	preload("res://assets/audio/shelby/gt500_off_0900.wav"),
	preload("res://assets/audio/shelby/gt500_off_1100.wav"),
	preload("res://assets/audio/shelby/gt500_off_1300.wav"),
	preload("res://assets/audio/shelby/gt500_off_1500.wav"),
	preload("res://assets/audio/shelby/gt500_off_1700.wav"),
	preload("res://assets/audio/shelby/gt500_off_1900.wav"),
	preload("res://assets/audio/shelby/gt500_off_2100.wav"),
	preload("res://assets/audio/shelby/gt500_off_2350.wav"),
	preload("res://assets/audio/shelby/gt500_off_2600.wav"),
	preload("res://assets/audio/shelby/gt500_off_2850.wav"),
	preload("res://assets/audio/shelby/gt500_off_3100.wav"),
	preload("res://assets/audio/shelby/gt500_off_3350.wav"),
	preload("res://assets/audio/shelby/gt500_off_3600.wav"),
	preload("res://assets/audio/shelby/gt500_off_3850.wav"),
	preload("res://assets/audio/shelby/gt500_off_4100.wav"),
	preload("res://assets/audio/shelby/gt500_off_4400.wav"),
]
const IDLE_STREAM: AudioStream = preload("res://assets/audio/shelby/mustang_idle.wav")
const START_STREAM: AudioStream = preload("res://assets/audio/shelby/mustang_start.wav")
const STOP_STREAM: AudioStream = preload("res://assets/audio/shelby/mustang_stop.wav")
const TIRE_STREAM: AudioStream = preload("res://assets/audio/shelby/tire_squeal_loop.wav")

var _bus_name := "VehicleAudio0235"
var _idle_player: AudioStreamPlayer
var _on_low_player: AudioStreamPlayer
var _on_high_player: AudioStreamPlayer
var _off_low_player: AudioStreamPlayer
var _off_high_player: AudioStreamPlayer
var _event_player: AudioStreamPlayer
var _tire_player: AudioStreamPlayer
var _suspended := false
var _state_gain := 0.0
var _load_smooth := 0.0
var _tire_smooth := 0.0
var _sound_rpm := 0.0
var _crank_phase_cycles := 0.0
var _low_index := 0
var _high_index := 0
var _segment_fraction := 0.0


func _ready() -> void:
	name = "VehicleAudio0235"
	_ensure_vehicle_bus()
	for stream in ON_STREAMS:
		_prepare_loop(stream)
	for stream in OFF_STREAMS:
		_prepare_loop(stream)
	_prepare_loop(IDLE_STREAM)
	_prepare_loop(TIRE_STREAM)
	_idle_player = _make_player("RecordedMustangIdle", IDLE_STREAM)
	_on_low_player = _make_player("GT500OnLow", ON_STREAMS[0])
	_on_high_player = _make_player("GT500OnHigh", ON_STREAMS[0])
	_off_low_player = _make_player("GT500OffLow", OFF_STREAMS[0])
	_off_high_player = _make_player("GT500OffHigh", OFF_STREAMS[0])
	_event_player = _make_player("MustangIgnitionEvent", null)
	_tire_player = _make_player("RecordedTireSqueal", TIRE_STREAM)


func _ensure_vehicle_bus() -> void:
	var bus_index := AudioServer.get_bus_index(_bus_name)
	if bus_index >= 0:
		return
	bus_index = AudioServer.bus_count
	AudioServer.add_bus(bus_index)
	AudioServer.set_bus_name(bus_index, _bus_name)
	AudioServer.set_bus_send(bus_index, "Master")
	AudioServer.set_bus_mute(bus_index, false)
	AudioServer.set_bus_volume_db(bus_index, 0.0)
	var limiter := AudioEffectLimiter.new()
	limiter.ceiling_db = -1.0
	limiter.threshold_db = -3.0
	limiter.soft_clip_db = 2.0
	limiter.soft_clip_ratio = 8.0
	AudioServer.add_bus_effect(bus_index, limiter)


func _prepare_loop(stream: AudioStream) -> void:
	var wav := stream as AudioStreamWAV
	if wav == null:
		return
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	var frames := int(round(wav.get_length() * float(wav.mix_rate)))
	if frames > 0:
		wav.loop_end = frames


func _make_player(player_name: String, stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = stream
	player.bus = _bus_name
	player.volume_db = -60.0
	player.pitch_scale = 1.0
	add_child(player)
	return player


func _all_players() -> Array[AudioStreamPlayer]:
	var result: Array[AudioStreamPlayer] = []
	for player in [_idle_player, _on_low_player, _on_high_player, _off_low_player, _off_high_player, _event_player, _tire_player]:
		if player != null:
			result.append(player)
	return result


func set_suspended(suspended: bool) -> void:
	_suspended = suspended
	for player in _all_players():
		player.stream_paused = suspended


func play_start() -> void:
	if _event_player == null:
		return
	_event_player.stream_paused = _suspended
	_event_player.stream = START_STREAM
	_event_player.volume_db = 1.5
	_event_player.pitch_scale = 1.0
	_event_player.stop()
	_event_player.play()


func play_stop() -> void:
	if _event_player == null:
		return
	_event_player.stream_paused = _suspended
	_event_player.stream = STOP_STREAM
	_event_player.volume_db = 1.0
	_event_player.pitch_scale = 1.0
	_event_player.stop()
	_event_player.play()


func cancel_event() -> void:
	if _event_player != null:
		_event_player.stop()


func stop_engine_loops() -> void:
	_state_gain = 0.0
	for player in [_idle_player, _on_low_player, _on_high_player, _off_low_player, _off_high_player]:
		if player != null:
			player.volume_db = -60.0
			player.stop()


func _set_gain(player: AudioStreamPlayer, linear_gain: float) -> void:
	if player == null:
		return
	if linear_gain <= 0.0001:
		player.volume_db = -60.0
	else:
		player.volume_db = clampf(linear_to_db(linear_gain), -60.0, 6.0)


func _assign_bank_stream(player: AudioStreamPlayer, stream: AudioStream, cycles: int) -> void:
	if player == null or stream == null:
		return
	if player.stream != stream:
		player.stream = stream
		var safe_cycles := float(maxi(cycles, 1))
		var phase := fposmod(_crank_phase_cycles, safe_cycles) / safe_cycles
		player.play(clampf(phase, 0.0, 0.999) * stream.get_length())
	elif not player.playing:
		player.play()


func _sound_rpm_for(engine_rpm: float) -> float:
	var mapped := clampf(engine_rpm, 0.0, 6400.0)
	# The openly licensed GT500 takes top out at 4,400 rpm.  Above
	# that point compress the remaining climb instead of pitching a
	# loop by an unnatural 1.45x all the way to the 6,400 rpm redline.
	if mapped > 4400.0:
		mapped = 4400.0 + (mapped - 4400.0) * 0.72
	return mapped


func update_audio(delta: float, engine_state: int, engine_rpm: float, engine_load: float, boost_active: bool, tire_slip: float, tire_pitch: float) -> void:
	if _idle_player == null:
		return
	var safe_delta := clampf(delta, 0.0, 0.1)
	var running := engine_state == ENGINE_RUNNING
	var gain_rate := 9.0 if running else 15.0
	_state_gain = clampf(move_toward(_state_gain, 1.0 if running else 0.0, gain_rate * safe_delta), 0.0, 1.0)

	var load_rate := 12.0 if engine_load > _load_smooth else 7.0
	_load_smooth = lerpf(_load_smooth, clampf(engine_load, 0.0, 1.0), 1.0 - exp(-load_rate * safe_delta))
	var tire_rate := 11.0 if tire_slip > _tire_smooth else 6.0
	_tire_smooth = lerpf(_tire_smooth, clampf(tire_slip, 0.0, 1.0), 1.0 - exp(-tire_rate * safe_delta))

	if _tire_smooth > 0.008:
		if not _tire_player.playing:
			_tire_player.play()
		_tire_player.pitch_scale = clampf(tire_pitch, 0.60, 1.28)
		_set_gain(_tire_player, pow(_tire_smooth, 1.25) * db_to_linear(-5.0))
	else:
		_set_gain(_tire_player, 0.0)
		if _tire_player.playing:
			_tire_player.stop()

	if _state_gain <= 0.001:
		if not running:
			stop_engine_loops()
		return

	_sound_rpm = _sound_rpm_for(engine_rpm)
	_crank_phase_cycles = fposmod(_crank_phase_cycles + _sound_rpm / 120.0 * safe_delta, 100000.0)

	_low_index = 0
	_high_index = 0
	_segment_fraction = 0.0
	if _sound_rpm >= float(BANK_RPMS[BANK_RPMS.size() - 1]):
		_low_index = BANK_RPMS.size() - 1
		_high_index = _low_index
	elif _sound_rpm > float(BANK_RPMS[0]):
		for i in range(BANK_RPMS.size() - 1):
			var low_rpm := float(BANK_RPMS[i])
			var high_rpm := float(BANK_RPMS[i + 1])
			if _sound_rpm >= low_rpm and _sound_rpm <= high_rpm:
				_low_index = i
				_high_index = i + 1
				_segment_fraction = clampf((_sound_rpm - low_rpm) / maxf(high_rpm - low_rpm, 1.0), 0.0, 1.0)
				break

	_assign_bank_stream(_on_low_player, ON_STREAMS[_low_index], BANK_CYCLES[_low_index])
	_assign_bank_stream(_on_high_player, ON_STREAMS[_high_index], BANK_CYCLES[_high_index])
	_assign_bank_stream(_off_low_player, OFF_STREAMS[_low_index], BANK_CYCLES[_low_index])
	_assign_bank_stream(_off_high_player, OFF_STREAMS[_high_index], BANK_CYCLES[_high_index])
	if not _idle_player.playing:
		_idle_player.play()

	_on_low_player.pitch_scale = clampf(_sound_rpm / float(BANK_RPMS[_low_index]), 0.55, 1.36)
	_on_high_player.pitch_scale = clampf(_sound_rpm / float(BANK_RPMS[_high_index]), 0.55, 1.36)
	_off_low_player.pitch_scale = _on_low_player.pitch_scale
	_off_high_player.pitch_scale = _on_high_player.pitch_scale
	_idle_player.pitch_scale = 1.03

	var segment_angle := _segment_fraction * PI * 0.5
	var low_weight := cos(segment_angle)
	var high_weight := sin(segment_angle)
	var load_angle := _load_smooth * PI * 0.5
	var on_weight := sin(load_angle)
	var off_weight := cos(load_angle)

	var idle_weight := 1.0 - smoothstep(1010.0, 1330.0, _sound_rpm)
	idle_weight *= 1.0 - smoothstep(0.18, 0.46, _load_smooth) * 0.72
	idle_weight = clampf(idle_weight, 0.0, 1.0)
	var bank_weight := sqrt(maxf(1.0 - idle_weight * idle_weight, 0.0))

	var rpm_mix := clampf((_sound_rpm - 850.0) / 5000.0, 0.0, 1.0)
	var master_db := lerpf(-4.5, 1.2, rpm_mix) + _load_smooth * 1.4 + (2.0 if boost_active else 0.0)
	var master_gain := _state_gain * db_to_linear(master_db)

	_set_gain(_idle_player, master_gain * idle_weight * 0.92)
	_set_gain(_on_low_player, master_gain * bank_weight * on_weight * low_weight)
	_set_gain(_on_high_player, master_gain * bank_weight * on_weight * high_weight)
	_set_gain(_off_low_player, master_gain * bank_weight * off_weight * low_weight)
	_set_gain(_off_high_player, master_gain * bank_weight * off_weight * high_weight)


func get_smoke_state() -> Dictionary:
	var streams_ready := ON_STREAMS.size() == 16 and OFF_STREAMS.size() == 16
	for stream in ON_STREAMS:
		streams_ready = streams_ready and stream != null
	for stream in OFF_STREAMS:
		streams_ready = streams_ready and stream != null
	return {
		"recorded_audio_0235": RECORDED_AUDIO_0235,
		"recorded_gt500_bank": true,
		"on_loop_count": ON_STREAMS.size(),
		"off_loop_count": OFF_STREAMS.size(),
		"streams_ready": streams_ready and IDLE_STREAM != null and START_STREAM != null and STOP_STREAM != null and TIRE_STREAM != null,
		"players_created": _all_players().size(),
		"bus_ready": AudioServer.get_bus_index(_bus_name) >= 0,
		"state_gain": _state_gain,
		"load": _load_smooth,
		"sound_rpm": _sound_rpm,
		"low_index": _low_index,
		"high_index": _high_index,
		"tire_level": _tire_smooth,
		"suspended": _suspended,
	}
