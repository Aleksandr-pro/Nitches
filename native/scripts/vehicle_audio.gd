class_name NativeVehicleAudio
extends Node

## Recorded vehicle audio (0.2.35 Shelby bank, 0.2.40 supplied-car
## banks, 0.2.42 realism pass).
##
## The continuous engine voice is never synthesized and is not a
## single stretched sample.  Each car owns a bank of phase-aligned
## field recordings in separate on-throttle and off-throttle layers;
## two neighbouring RPM loops are equal-power crossfaded in the log
## (pitch) domain, then the load layers are crossfaded from the
## effective pedal.  Sparse banks were densified offline with
## pulse-synchronous TD-PSOLA derivations of the same recordings
## (see scripts/generate_supplied_car_audio.py), so runtime pitch
## ratios stay near unity instead of the old 2.3x formant stretch.
##
## Around that recorded core, 0.2.42 adds the detail layers a real
## car produces: a dynamic engine low-pass (brightness follows RPM,
## load and camera), exhaust overrun crackle resequenced from the
## bank's own recorded exhaust pulses, shift clunks with a
## rev-match blip on downshifts, a redline limiter stutter, idle
## lope wander, speed-squared wind, per-surface road beds,
## output-shaft gear whine, directional tyre scrub/squeal with an
## onset chirp, suspension thumps, wall scrapes and impact knocks.
## Wind/road/whine/impact beds are synthesized foley (documented in
## docs/AUDIO_CREDITS.md); the engine and tyre-squeal voices remain
## 100% field recordings.

const ENGINE_OFF := 0
const ENGINE_CRANKING := 1
const ENGINE_RUNNING := 2
const ENGINE_STOPPING := 3
const RECORDED_AUDIO_0235 := true
const AUDIO_REALISM_0242 := true
const BANK_RPMS: Array[int] = [900, 1100, 1300, 1500, 1700, 1900, 2100, 2350, 2600, 2850, 3100, 3350, 3600, 3850, 4100, 4400, 5000, 5600]
const BANK_CYCLES: Array[int] = [6, 7, 8, 9, 11, 12, 13, 15, 16, 18, 19, 21, 22, 24, 26, 28, 28, 28]
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
	preload("res://assets/audio/shelby/gt500_on_5000.wav"),
	preload("res://assets/audio/shelby/gt500_on_5600.wav"),
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
	preload("res://assets/audio/shelby/gt500_off_5000.wav"),
	preload("res://assets/audio/shelby/gt500_off_5600.wav"),
]
const IDLE_STREAM: AudioStream = preload("res://assets/audio/shelby/mustang_idle.wav")
const START_STREAM: AudioStream = preload("res://assets/audio/shelby/mustang_start.wav")
const STOP_STREAM: AudioStream = preload("res://assets/audio/shelby/mustang_stop.wav")
const TIRE_STREAM: AudioStream = preload("res://assets/audio/shelby/tire_squeal_loop.wav")
const WIND_STREAM: AudioStream = preload("res://assets/audio/vehicle_foley/wind_loop.wav")
const ROAD_ASPHALT_STREAM: AudioStream = preload("res://assets/audio/vehicle_foley/road_asphalt.wav")
const ROAD_SIDEWALK_STREAM: AudioStream = preload("res://assets/audio/vehicle_foley/road_sidewalk.wav")
const ROAD_GRASS_STREAM: AudioStream = preload("res://assets/audio/vehicle_foley/road_grass.wav")
const ROAD_SAND_STREAM: AudioStream = preload("res://assets/audio/vehicle_foley/road_sand.wav")
const WHINE_STREAM: AudioStream = preload("res://assets/audio/vehicle_foley/whine_loop.wav")
const SCRAPE_STREAM: AudioStream = preload("res://assets/audio/vehicle_foley/scrape_loop.wav")
const THUMP_STREAM: AudioStream = preload("res://assets/audio/vehicle_foley/suspension_thump.wav")
const CLUNK_STREAM: AudioStream = preload("res://assets/audio/vehicle_foley/shift_clunk.wav")
const IMPACT_SOFT_STREAM: AudioStream = preload("res://assets/audio/vehicle_foley/impact_soft.wav")
const IMPACT_MED_STREAM: AudioStream = preload("res://assets/audio/vehicle_foley/impact_med.wav")
const IMPACT_HARD_STREAM: AudioStream = preload("res://assets/audio/vehicle_foley/impact_hard.wav")
const POP_COUNT := 10
const CAMERA_CHASE := 0
const CAMERA_HOOD := 1
const CAMERA_TOP := 2

var _bus_name := "VehicleAudio0235"
var _engine_bus_name := "VehicleAudio0235Engine"
var _tires_bus_name := "VehicleAudio0235Tires"
var _road_bus_name := "VehicleAudio0235Road"
var _events_bus_name := "VehicleAudio0235Events"
var _car_id := "shelby_gt500"
var _bank_id := "shelby_gt500"
var _bank_rpms: Array[int] = [900, 1100, 1300, 1500, 1700, 1900, 2100, 2350, 2600, 2850, 3100, 3350, 3600, 3850, 4100, 4400, 5000, 5600]
var _bank_cycles: Array[int] = [6, 7, 8, 9, 11, 12, 13, 15, 16, 18, 19, 21, 22, 24, 26, 28, 28, 28]
var _on_streams: Array[AudioStream] = []
var _off_streams: Array[AudioStream] = []
var _pop_streams: Array[AudioStream] = []
var _idle_stream: AudioStream
var _start_stream: AudioStream
var _stop_stream: AudioStream
var _idle_pitch := 1.03
var _pitch_min := 0.55
var _pitch_max := 1.30
var _sound_redline := 6400.0
var _limiter_rpm := 6400.0
var _compression_start := 5600.0
var _compression_factor := 0.80
var _idle_crossfade_low := 1010.0
var _idle_crossfade_high := 1330.0
var _master_db_offset := 0.0
# Per-car audio character (0.2.42).
var _crackle_amount := 0.55
var _crackle_min_rpm := 2200.0
var _crackle_gain_db := 0.0
var _clunk_pitch := 0.9
var _clunk_db := 0.0
var _exhaust_lp_mult := 1.0
var _whine_db := -6.0

var _idle_player: AudioStreamPlayer
var _on_low_player: AudioStreamPlayer
var _on_high_player: AudioStreamPlayer
var _off_low_player: AudioStreamPlayer
var _off_high_player: AudioStreamPlayer
var _event_player: AudioStreamPlayer
var _tire_player: AudioStreamPlayer
var _road_players: Array[AudioStreamPlayer] = []
var _wind_player: AudioStreamPlayer
var _whine_player: AudioStreamPlayer
var _scrape_player: AudioStreamPlayer
var _clunk_player: AudioStreamPlayer
var _impact_player: AudioStreamPlayer
var _thump_player: AudioStreamPlayer
var _pop_players: Array[AudioStreamPlayer] = []
var _engine_lowpass: AudioEffectLowPassFilter
var _tire_lowpass: AudioEffectLowPassFilter
var _tire_panner: AudioEffectPanner

var _suspended := false
var _state_gain := 0.0
var _load_smooth := 0.0
var _prev_load_smooth := 0.0
var _tire_smooth := 0.0
var _prev_tire_input := 0.0
var _chirp := 0.0
var _tire_pan := 0.0
var _sound_rpm := 0.0
var _prev_sound_rpm := 0.0
var _crank_phase_cycles := 0.0
var _low_index := 0
var _high_index := 0
var _segment_fraction := 0.0
var _idle_time := 0.0
var _blip_timer := 0.0
var _limiter_phase := 0.0
var _limiter_active := false
var _engine_lp_hz := 2400.0
var _crackle_timer := 0.0
var _crackle_window := 1.0
var _crackle_energy := 0.0
var _pop_cooldown := 0.0
var _pop_round_robin := 0
var _pops_fired := 0
var _road_kind := ""
var _road_front := 0
var _road_blend := 1.0
var _road_level := 0.0
var _wind_level := 0.0
var _whine_level := 0.0
var _scrape_smooth := 0.0
var _camera_mode := CAMERA_CHASE
var _listener_engine_db := 0.0
var _listener_lp_mult := 1.0
var _listener_wind_db := 0.0
var _listener_tire_db := 0.0
var _listener_events_db := 0.0
var _road_streams: Dictionary = {}


func configure_for_car(car_id: String) -> void:
	# Called by NativeVehicle before this node enters the tree, both for
	# the initial spawn and for a garage car switch (which rebuilds the
	# audio node together with the rest of the vehicle).
	_car_id = car_id
	match car_id:
		"audi_r8_v10_plus":
			_apply_recorded_bank(
				"audi_r8", "res://assets/audio/audi_r8",
				[1231, 1602, 2400, 3735, 5200, 6800], [15, 33, 33, 11, 26, 34],
				0.56, 0.62, 1.38, 8500.0, 1250.0, 1650.0, 0.5
			)
			# Dual-clutch V10: ferocious lift-off crackle, sharp quiet
			# shifts, the brightest exhaust of the four.
			_apply_character(1.0, 2800.0, 1.5, 1.28, -7.0, 1.18, -7.0, 8500.0)
		"chevrolet_camaro_ss":
			_apply_recorded_bank(
				"camaro_ss", "res://assets/audio/camaro_ss",
				[635, 1050, 1444, 2265, 2900, 3747, 5000, 6478], [16, 16, 24, 11, 62, 62, 62, 65],
				1.18, 0.60, 1.40, 6500.0, 850.0, 1150.0, 0.0
			)
			_apply_character(0.8, 2400.0, 0.5, 1.05, -3.0, 1.06, -6.0, 6500.0)
		"mercedes_560_sel":
			_apply_recorded_bank(
				"mercedes_560_sel", "res://assets/audio/mercedes_560_sel",
				[805, 999, 1444, 2265, 2900, 3747, 5000], [23, 25, 24, 11, 62, 62, 62],
				0.87, 0.60, 1.35, 6000.0, 900.0, 1200.0, -2.0
			)
			# W126 luxury brief: muffled note, soft slushbox shifts and
			# only the rarest, deepest burble on a hard lift.
			_apply_character(0.18, 2600.0, -6.0, 0.8, -6.0, 0.78, -9.0, 6000.0)
		_:
			_apply_shelby_bank()


func _apply_character(
	crackle_amount: float,
	crackle_min_rpm: float,
	crackle_gain_db: float,
	clunk_pitch: float,
	clunk_db: float,
	exhaust_lp_mult: float,
	whine_db: float,
	limiter_rpm: float
) -> void:
	_crackle_amount = crackle_amount
	_crackle_min_rpm = crackle_min_rpm
	_crackle_gain_db = crackle_gain_db
	_clunk_pitch = clunk_pitch
	_clunk_db = clunk_db
	_exhaust_lp_mult = exhaust_lp_mult
	_whine_db = whine_db
	_limiter_rpm = limiter_rpm


func _apply_shelby_bank() -> void:
	_bank_id = "shelby_gt500"
	_bank_rpms.assign(BANK_RPMS)
	_bank_cycles.assign(BANK_CYCLES)
	_on_streams.assign(ON_STREAMS)
	_off_streams.assign(OFF_STREAMS)
	_idle_stream = IDLE_STREAM
	_start_stream = START_STREAM
	_stop_stream = STOP_STREAM
	_idle_pitch = 1.03
	_pitch_min = 0.55
	_pitch_max = 1.30
	_sound_redline = 6400.0
	# The openly licensed GT500 recordings top out at 4,400 rpm; the
	# 5000/5600 anchors are PSOLA derivations of that same recorded
	# loop, so only the last 800 rpm still needs mild compression.
	_compression_start = 5600.0
	_compression_factor = 0.80
	_idle_crossfade_low = 1010.0
	_idle_crossfade_high = 1330.0
	_master_db_offset = 0.0
	# Carburetted big-block through a 4-speed: honest manual thunk,
	# moderate burble, unfiltered period exhaust.
	_apply_character(0.55, 2200.0, 0.0, 0.9, 0.0, 1.0, -6.0, 6400.0)
	_load_pops("res://assets/audio/shelby")


func _apply_recorded_bank(
	bank_id: String,
	folder: String,
	rpms: Array,
	cycles: Array,
	idle_pitch: float,
	pitch_min: float,
	pitch_max: float,
	sound_redline: float,
	idle_crossfade_low: float,
	idle_crossfade_high: float,
	master_db_offset: float
) -> void:
	_bank_id = bank_id
	_bank_rpms.clear()
	_bank_cycles.clear()
	_on_streams.clear()
	_off_streams.clear()
	for i in rpms.size():
		var rpm := int(rpms[i])
		_bank_rpms.append(rpm)
		_bank_cycles.append(int(cycles[i]) if i < cycles.size() else 12)
		_on_streams.append(_load_stream("%s/engine_on_%04d.wav" % [folder, rpm]))
		_off_streams.append(_load_stream("%s/engine_off_%04d.wav" % [folder, rpm]))
	_idle_stream = _load_stream("%s/engine_idle.wav" % folder)
	_start_stream = _load_stream("%s/engine_start.wav" % folder)
	_stop_stream = _load_stream("%s/engine_stop.wav" % folder)
	_idle_pitch = idle_pitch
	_pitch_min = pitch_min
	_pitch_max = pitch_max
	_sound_redline = sound_redline
	_compression_start = sound_redline
	_compression_factor = 1.0
	_idle_crossfade_low = idle_crossfade_low
	_idle_crossfade_high = idle_crossfade_high
	_master_db_offset = master_db_offset
	_load_pops(folder)


func _load_pops(folder: String) -> void:
	_pop_streams.clear()
	for i in range(1, POP_COUNT + 1):
		var stream := _load_stream("%s/pop_%02d.wav" % [folder, i])
		if stream != null:
			_pop_streams.append(stream)


func _load_stream(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var stream := load(path) as AudioStream
		if stream != null:
			return stream
	push_warning("Recorded vehicle audio stream is missing: %s" % path)
	return null


func _ready() -> void:
	name = "VehicleAudio0235"
	if _on_streams.is_empty():
		_apply_shelby_bank()
	_ensure_buses()
	for stream in _on_streams:
		_prepare_loop(stream)
	for stream in _off_streams:
		_prepare_loop(stream)
	_prepare_loop(_idle_stream)
	_prepare_loop(TIRE_STREAM)
	_prepare_loop(WIND_STREAM)
	_prepare_loop(WHINE_STREAM)
	_prepare_loop(SCRAPE_STREAM)
	_road_streams = {
		"asphalt": ROAD_ASPHALT_STREAM,
		"sidewalk": ROAD_SIDEWALK_STREAM,
		"grass": ROAD_GRASS_STREAM,
		"sand": ROAD_SAND_STREAM,
	}
	for stream_value in _road_streams.values():
		_prepare_loop(stream_value as AudioStream)
	_idle_player = _make_player("RecordedEngineIdle", _idle_stream, _engine_bus_name)
	_on_low_player = _make_player("RecordedEngineOnLow", _on_streams[0] if not _on_streams.is_empty() else null, _engine_bus_name)
	_on_high_player = _make_player("RecordedEngineOnHigh", _on_streams[0] if not _on_streams.is_empty() else null, _engine_bus_name)
	_off_low_player = _make_player("RecordedEngineOffLow", _off_streams[0] if not _off_streams.is_empty() else null, _engine_bus_name)
	_off_high_player = _make_player("RecordedEngineOffHigh", _off_streams[0] if not _off_streams.is_empty() else null, _engine_bus_name)
	_event_player = _make_player("RecordedIgnitionEvent", null, _events_bus_name)
	_tire_player = _make_player("RecordedTireSqueal", TIRE_STREAM, _tires_bus_name)
	_road_players = [
		_make_player("RoadBedA", ROAD_ASPHALT_STREAM, _road_bus_name),
		_make_player("RoadBedB", ROAD_ASPHALT_STREAM, _road_bus_name),
	]
	_wind_player = _make_player("WindBed", WIND_STREAM, _road_bus_name)
	_whine_player = _make_player("GearWhine", WHINE_STREAM, _road_bus_name)
	_scrape_player = _make_player("WallScrape", SCRAPE_STREAM, _events_bus_name)
	_clunk_player = _make_player("ShiftClunk", CLUNK_STREAM, _events_bus_name)
	_impact_player = _make_player("BodyImpact", IMPACT_MED_STREAM, _events_bus_name)
	_thump_player = _make_player("SuspensionThump", THUMP_STREAM, _events_bus_name)
	_pop_players = [
		_make_player("ExhaustPopA", null, _events_bus_name),
		_make_player("ExhaustPopB", null, _events_bus_name),
		_make_player("ExhaustPopC", null, _events_bus_name),
	]


func _get_or_add_bus(bus_name: String, send_to: String) -> int:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index >= 0:
		return bus_index
	bus_index = AudioServer.bus_count
	AudioServer.add_bus(bus_index)
	AudioServer.set_bus_name(bus_index, bus_name)
	AudioServer.set_bus_send(bus_index, send_to)
	AudioServer.set_bus_mute(bus_index, false)
	AudioServer.set_bus_volume_db(bus_index, 0.0)
	return bus_index


func _ensure_buses() -> void:
	var master_index := _get_or_add_bus(_bus_name, "Master")
	if AudioServer.get_bus_effect_count(master_index) == 0:
		var compressor := AudioEffectCompressor.new()
		compressor.threshold = -14.0
		compressor.ratio = 3.0
		compressor.gain = 1.0
		compressor.attack_us = 4000.0
		compressor.release_ms = 180.0
		AudioServer.add_bus_effect(master_index, compressor)
		var limiter := AudioEffectLimiter.new()
		limiter.ceiling_db = -1.0
		limiter.threshold_db = -3.0
		limiter.soft_clip_db = 2.0
		limiter.soft_clip_ratio = 8.0
		AudioServer.add_bus_effect(master_index, limiter)

	var engine_index := _get_or_add_bus(_engine_bus_name, _bus_name)
	if AudioServer.get_bus_effect_count(engine_index) == 0:
		var lowpass := AudioEffectLowPassFilter.new()
		lowpass.cutoff_hz = _engine_lp_hz
		lowpass.resonance = 0.35
		lowpass.db = AudioEffectFilter.FILTER_18DB
		AudioServer.add_bus_effect(engine_index, lowpass)
		var enhance := AudioEffectStereoEnhance.new()
		enhance.pan_strength = 0.35
		enhance.surround = 0.0
		AudioServer.add_bus_effect(engine_index, enhance)
	for i in AudioServer.get_bus_effect_count(engine_index):
		var effect := AudioServer.get_bus_effect(engine_index, i)
		if effect is AudioEffectLowPassFilter:
			_engine_lowpass = effect as AudioEffectLowPassFilter

	var tires_index := _get_or_add_bus(_tires_bus_name, _bus_name)
	if AudioServer.get_bus_effect_count(tires_index) == 0:
		var tire_lp := AudioEffectLowPassFilter.new()
		tire_lp.cutoff_hz = 4200.0
		tire_lp.resonance = 0.3
		tire_lp.db = AudioEffectFilter.FILTER_12DB
		AudioServer.add_bus_effect(tires_index, tire_lp)
		var panner := AudioEffectPanner.new()
		panner.pan = 0.0
		AudioServer.add_bus_effect(tires_index, panner)
	for i in AudioServer.get_bus_effect_count(tires_index):
		var effect := AudioServer.get_bus_effect(tires_index, i)
		if effect is AudioEffectLowPassFilter:
			_tire_lowpass = effect as AudioEffectLowPassFilter
		elif effect is AudioEffectPanner:
			_tire_panner = effect as AudioEffectPanner

	_get_or_add_bus(_road_bus_name, _bus_name)
	_get_or_add_bus(_events_bus_name, _bus_name)


func _prepare_loop(stream: AudioStream) -> void:
	var wav := stream as AudioStreamWAV
	if wav == null:
		return
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	var frames := int(round(wav.get_length() * float(wav.mix_rate)))
	if frames > 0:
		wav.loop_end = frames


func _make_player(player_name: String, stream: AudioStream, bus_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = stream
	player.bus = bus_name
	player.volume_db = -60.0
	player.pitch_scale = 1.0
	add_child(player)
	return player


func _all_players() -> Array[AudioStreamPlayer]:
	var result: Array[AudioStreamPlayer] = []
	for player in [
		_idle_player, _on_low_player, _on_high_player, _off_low_player,
		_off_high_player, _event_player, _tire_player, _wind_player,
		_whine_player, _scrape_player, _clunk_player, _impact_player,
		_thump_player,
	]:
		if player != null:
			result.append(player)
	for player in _road_players:
		if player != null:
			result.append(player)
	for player in _pop_players:
		if player != null:
			result.append(player)
	return result


func set_suspended(suspended: bool) -> void:
	_suspended = suspended
	for player in _all_players():
		player.stream_paused = suspended


func play_start() -> void:
	if _event_player == null or _suspended:
		return
	_event_player.stream_paused = false
	_event_player.stream = _start_stream
	_event_player.volume_db = 1.5
	# No two real cranks are identical: battery/starter variation.
	_event_player.pitch_scale = randf_range(0.965, 1.035)
	_event_player.stop()
	_event_player.play()


func play_stop(from_rpm_ratio: float = 0.0) -> void:
	if _event_player == null or _suspended:
		return
	_event_player.stream_paused = false
	_event_player.stream = _stop_stream
	_event_player.volume_db = 1.0
	# Killing the engine at speed starts the run-down higher.
	_event_player.pitch_scale = clampf(0.9 + 0.35 * clampf(from_rpm_ratio, 0.0, 1.0), 0.9, 1.25)
	_event_player.stop()
	_event_player.play()


func play_shift(downshift: bool, intensity: float) -> void:
	if _suspended:
		return
	if downshift:
		# Rev-match blip: briefly swell the on-throttle layer while
		# the drivetrain resynchronises RPM into the lower gear.
		_blip_timer = 0.22
		if _sound_rpm > _crackle_min_rpm * 0.85:
			_crackle_energy = maxf(_crackle_energy, 0.45 * _crackle_amount)
			_crackle_window = 0.7
			_crackle_timer = maxf(_crackle_timer, 0.45)
	if _clunk_player == null:
		return
	var gain_db := _clunk_db + lerpf(-9.0, -2.5, clampf(intensity, 0.0, 1.0)) + _listener_events_db
	_clunk_player.stream_paused = false
	_clunk_player.pitch_scale = _clunk_pitch * randf_range(0.94, 1.06) * (0.92 if downshift else 1.0)
	_clunk_player.volume_db = gain_db
	_clunk_player.stop()
	_clunk_player.play()


func play_impact(strength: float) -> void:
	if _impact_player == null or _suspended:
		return
	var s := clampf(strength, 0.0, 1.0)
	_impact_player.stream = IMPACT_SOFT_STREAM if s < 0.34 else (IMPACT_MED_STREAM if s < 0.67 else IMPACT_HARD_STREAM)
	_impact_player.stream_paused = false
	_impact_player.pitch_scale = randf_range(0.94, 1.04) * (1.06 - 0.22 * s)
	_impact_player.volume_db = lerpf(-13.0, -1.0, s) + _listener_events_db
	_impact_player.stop()
	_impact_player.play()


func play_thump(strength: float) -> void:
	if _thump_player == null or _suspended:
		return
	var s := clampf(strength, 0.0, 1.0)
	_thump_player.stream_paused = false
	_thump_player.pitch_scale = randf_range(0.94, 1.05) * (1.08 - 0.18 * s)
	_thump_player.volume_db = lerpf(-15.0, -3.0, s) + _listener_events_db
	_thump_player.stop()
	_thump_player.play()


func cancel_event() -> void:
	if _event_player != null:
		_event_player.stop()


func stop_engine_loops() -> void:
	_state_gain = 0.0
	_blip_timer = 0.0
	_crackle_timer = 0.0
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
	var mapped := clampf(engine_rpm, 0.0, _sound_redline)
	# Only the Shelby bank still needs top-end compression; the
	# 0.2.40/0.2.42 banks carry anchors at each car's own redline.
	if mapped > _compression_start:
		mapped = _compression_start + (mapped - _compression_start) * _compression_factor
	return mapped


func _road_audio_kind(surface_kind: String) -> String:
	match surface_kind:
		"asphalt":
			return "asphalt"
		"grass":
			return "grass"
		"sand", "water":
			return "sand"
		_:
			return "sidewalk"


func _fire_pop(gain_db: float) -> void:
	if _pop_streams.is_empty() or _pop_players.is_empty() or _suspended:
		return
	var player := _pop_players[_pop_round_robin % _pop_players.size()]
	_pop_round_robin += 1
	player.stream = _pop_streams[randi() % _pop_streams.size()]
	player.stream_paused = false
	player.pitch_scale = randf_range(0.87, 1.17)
	player.volume_db = gain_db + _listener_events_db + randf_range(-1.5, 1.0)
	player.stop()
	player.play()
	_pops_fired += 1


func update_audio(delta: float, s: Dictionary) -> void:
	if _idle_player == null:
		return
	var safe_delta := clampf(delta, 0.0, 0.1)
	var engine_state := int(s.get("engine_state", ENGINE_OFF))
	var engine_rpm := float(s.get("engine_rpm", 0.0))
	var engine_load := clampf(float(s.get("engine_load", 0.0)), 0.0, 1.0)
	var boost_active := bool(s.get("boost", false))
	var speed_ms := float(s.get("speed_ms", 0.0))
	var abs_speed := absf(speed_ms)
	var gear_index := int(s.get("gear_index", 0))
	var reverse := bool(s.get("reverse", false))
	var tire_input := clampf(float(s.get("tire_squeal", 0.0)), 0.0, 1.0)
	var tire_pitch := float(s.get("tire_pitch", 0.9))
	var drift_pan := clampf(float(s.get("drift_pan", 0.0)), -1.0, 1.0)
	var surface_kind := String(s.get("surface_kind", "asphalt"))
	var grounded := bool(s.get("grounded", false))
	_camera_mode = clampi(int(s.get("camera_mode", CAMERA_CHASE)), CAMERA_CHASE, CAMERA_TOP)
	var scrape_input := clampf(float(s.get("scrape", 0.0)), 0.0, 1.0)

	# Listener (camera) mix, smoothed so a camera cut is not a sonic cut.
	var listener_targets := [0.0, 1.0, 0.0, 0.0, 0.0]
	match _camera_mode:
		CAMERA_HOOD:
			listener_targets = [1.6, 1.38, 3.2, -2.5, -3.5]
		CAMERA_TOP:
			listener_targets = [-6.5, 0.42, -5.0, -4.0, -4.0]
	var listener_alpha := 1.0 - exp(-5.5 * safe_delta)
	_listener_engine_db = lerpf(_listener_engine_db, float(listener_targets[0]), listener_alpha)
	_listener_lp_mult = lerpf(_listener_lp_mult, float(listener_targets[1]), listener_alpha)
	_listener_wind_db = lerpf(_listener_wind_db, float(listener_targets[2]), listener_alpha)
	_listener_tire_db = lerpf(_listener_tire_db, float(listener_targets[3]), listener_alpha)
	_listener_events_db = lerpf(_listener_events_db, float(listener_targets[4]), listener_alpha)

	var running := engine_state == ENGINE_RUNNING
	var gain_rate := 9.0 if running else 15.0
	_state_gain = clampf(move_toward(_state_gain, 1.0 if running else 0.0, gain_rate * safe_delta), 0.0, 1.0)

	_prev_load_smooth = _load_smooth
	var load_rate := 12.0 if engine_load > _load_smooth else 7.0
	_load_smooth = lerpf(_load_smooth, engine_load, 1.0 - exp(-load_rate * safe_delta))
	_blip_timer = maxf(_blip_timer - safe_delta, 0.0)
	var blip_env := 0.0
	if _blip_timer > 0.0:
		blip_env = sin(PI * clampf(1.0 - _blip_timer / 0.22, 0.0, 1.0)) * 0.78
	var load_eff := clampf(maxf(_load_smooth, blip_env), 0.0, 1.0)

	# --- Tyre squeal/scrub -------------------------------------------------
	var tire_deriv := (tire_input - _prev_tire_input) / maxf(safe_delta, 0.001)
	_prev_tire_input = tire_input
	if tire_input > 0.22 and tire_deriv > 3.0:
		_chirp = 1.0
	_chirp = move_toward(_chirp, 0.0, 7.5 * safe_delta)
	var tire_rate := 11.0 if tire_input > _tire_smooth else 6.0
	_tire_smooth = lerpf(_tire_smooth, tire_input, 1.0 - exp(-tire_rate * safe_delta))
	if _tire_smooth > 0.008:
		if not _tire_player.playing:
			_tire_player.play()
		_tire_player.pitch_scale = clampf(tire_pitch, 0.60, 1.28) * (1.0 + 0.13 * _chirp)
		_set_gain(_tire_player, pow(_tire_smooth, 1.25) * db_to_linear(-5.0 + _listener_tire_db))
	else:
		_set_gain(_tire_player, 0.0)
		if _tire_player.playing:
			_tire_player.stop()
	if _tire_lowpass != null:
		_tire_lowpass.cutoff_hz = lerpf(_tire_lowpass.cutoff_hz, 2300.0 + 4700.0 * _tire_smooth, 1.0 - exp(-8.0 * safe_delta))
	_tire_pan = lerpf(_tire_pan, drift_pan * 0.38, 1.0 - exp(-8.0 * safe_delta))
	if _tire_panner != null:
		_tire_panner.pan = _tire_pan

	# --- Road beds ----------------------------------------------------------
	var road_kind := _road_audio_kind(surface_kind)
	var surface_gain := 0.8
	match road_kind:
		"sidewalk":
			surface_gain = 0.9
		"grass":
			surface_gain = 1.18
		"sand":
			surface_gain = 1.08
	_road_level = 0.0
	if grounded:
		_road_level = pow(clampf(abs_speed / 38.0, 0.0, 1.0), 1.55) * surface_gain
		_road_level *= 1.0 + 0.35 * _tire_smooth
		_road_level = clampf(_road_level, 0.0, 1.25)
	var road_pitch := 0.8 + 0.55 * clampf(abs_speed / 46.0, 0.0, 1.0)
	if road_kind != _road_kind:
		_road_kind = road_kind
		_road_front = 1 - _road_front
		var front_player := _road_players[_road_front]
		front_player.stream = _road_streams.get(road_kind, ROAD_ASPHALT_STREAM) as AudioStream
		_road_blend = 0.0
	_road_blend = minf(_road_blend + safe_delta / 0.18, 1.0)
	var road_gain := _road_level * db_to_linear(-9.0 + _listener_tire_db * 0.5)
	for i in _road_players.size():
		var road_player := _road_players[i]
		var is_front := i == _road_front
		var weight := sin(_road_blend * PI * 0.5) if is_front else cos(_road_blend * PI * 0.5)
		if _road_kind == "":
			weight = 0.0
		road_player.pitch_scale = road_pitch
		if road_gain * weight > 0.004:
			if not road_player.playing:
				road_player.play()
			_set_gain(road_player, road_gain * weight)
		else:
			_set_gain(road_player, 0.0)
			if road_player.playing and (not is_front or _road_level <= 0.004):
				road_player.stop()

	# --- Wind ---------------------------------------------------------------
	_wind_level = pow(clampf(abs_speed / 52.0, 0.0, 1.0), 2.05)
	var wind_gain := _wind_level * db_to_linear(-7.0 + _listener_wind_db + (2.0 if boost_active else 0.0))
	if wind_gain > 0.004:
		if not _wind_player.playing:
			_wind_player.play()
		_wind_player.pitch_scale = 0.9 + 0.28 * clampf(abs_speed / 55.0, 0.0, 1.0)
		_set_gain(_wind_player, wind_gain)
	else:
		_set_gain(_wind_player, 0.0)
		if _wind_player.playing:
			_wind_player.stop()

	# --- Gear whine ----------------------------------------------------------
	_whine_level = 0.0
	var whine_pitch := 1.0
	if reverse and running:
		_whine_level = clampf(abs_speed / 8.5, 0.0, 1.0) * 0.55
		whine_pitch = clampf(0.55 + abs_speed * 0.30, 0.55, 3.3)
	elif running and gear_index <= 1 and load_eff > 0.2:
		_whine_level = 0.13 * load_eff * clampf(abs_speed / 14.0, 0.0, 1.0)
		whine_pitch = clampf(0.5 + abs_speed * 0.20, 0.5, 3.0)
	var whine_gain := _whine_level * db_to_linear(_whine_db)
	if whine_gain > 0.003:
		if not _whine_player.playing:
			_whine_player.play()
		_whine_player.pitch_scale = whine_pitch
		_set_gain(_whine_player, whine_gain)
	else:
		_set_gain(_whine_player, 0.0)
		if _whine_player.playing:
			_whine_player.stop()

	# --- Wall scrape -----------------------------------------------------------
	var scrape_rate := 10.0 if scrape_input > _scrape_smooth else 6.0
	_scrape_smooth = lerpf(_scrape_smooth, scrape_input, 1.0 - exp(-scrape_rate * safe_delta))
	if _scrape_smooth > 0.01:
		if not _scrape_player.playing:
			_scrape_player.play()
		_scrape_player.pitch_scale = 0.92 + 0.15 * _scrape_smooth
		_set_gain(_scrape_player, _scrape_smooth * db_to_linear(-8.0 + _listener_events_db))
	else:
		_set_gain(_scrape_player, 0.0)
		if _scrape_player.playing:
			_scrape_player.stop()

	# --- Exhaust crackle -------------------------------------------------------
	_prev_sound_rpm = _sound_rpm
	if running:
		_sound_rpm = _sound_rpm_for(engine_rpm)
		# Hard lift from real load: unburnt fuel lights off downstream.
		if _prev_load_smooth >= 0.5 and _load_smooth < 0.32 and _sound_rpm > _crackle_min_rpm:
			var rpm_ratio := clampf((_sound_rpm - _crackle_min_rpm) / maxf(_sound_redline - _crackle_min_rpm, 1.0), 0.0, 1.0)
			_crackle_energy = clampf(0.35 + 0.65 * rpm_ratio, 0.0, 1.0) * _crackle_amount
			_crackle_window = 0.5 + 0.9 * _crackle_energy
			_crackle_timer = _crackle_window
			_pop_cooldown = 0.0
		_crackle_timer = maxf(_crackle_timer - safe_delta, 0.0)
		_pop_cooldown = maxf(_pop_cooldown - safe_delta, 0.0)
		var pop_rate := 0.0
		var pop_gain_db := -7.0
		if _crackle_timer > 0.0 and _crackle_energy > 0.02:
			var decay := _crackle_timer / maxf(_crackle_window, 0.01)
			pop_rate = 15.0 * _crackle_energy * decay
			pop_gain_db = -8.0 + 6.0 * _crackle_energy * decay
		elif _load_smooth < 0.10 and _sound_rpm > _crackle_min_rpm * 0.8 and _sound_rpm < _prev_sound_rpm - 1.0:
			# Closed-throttle overrun burble while revs fall.
			pop_rate = 2.4 * _crackle_amount
			pop_gain_db = -13.0
		if pop_rate > 0.1 and _pop_cooldown <= 0.0 and randf() < pop_rate * safe_delta * 3.0:
			_fire_pop(pop_gain_db + _crackle_gain_db)
			_pop_cooldown = randf_range(0.45, 1.4) / pop_rate

	# --- Engine (recorded bank) ------------------------------------------------
	if _state_gain <= 0.001:
		if not running:
			stop_engine_loops()
		return
	if not running:
		_sound_rpm = _sound_rpm_for(engine_rpm)
	_crank_phase_cycles = fposmod(_crank_phase_cycles + _sound_rpm / 120.0 * safe_delta, 100000.0)
	_idle_time += safe_delta

	_low_index = 0
	_high_index = 0
	_segment_fraction = 0.0
	if _sound_rpm >= float(_bank_rpms[_bank_rpms.size() - 1]):
		_low_index = _bank_rpms.size() - 1
		_high_index = _low_index
	elif _sound_rpm > float(_bank_rpms[0]):
		for i in range(_bank_rpms.size() - 1):
			var low_rpm := float(_bank_rpms[i])
			var high_rpm := float(_bank_rpms[i + 1])
			if _sound_rpm >= low_rpm and _sound_rpm <= high_rpm:
				_low_index = i
				_high_index = i + 1
				# Pitch is logarithmic: crossfade on log-RPM so the
				# blend midpoint sits at the geometric mean.
				_segment_fraction = clampf(log(_sound_rpm / low_rpm) / log(high_rpm / low_rpm), 0.0, 1.0)
				break

	_assign_bank_stream(_on_low_player, _on_streams[_low_index], _bank_cycles[_low_index])
	_assign_bank_stream(_on_high_player, _on_streams[_high_index], _bank_cycles[_high_index])
	_assign_bank_stream(_off_low_player, _off_streams[_low_index], _bank_cycles[_low_index])
	_assign_bank_stream(_off_high_player, _off_streams[_high_index], _bank_cycles[_high_index])
	if not _idle_player.playing:
		_idle_player.play()

	# Rev-limiter stutter at the hard clamp.
	_limiter_active = running and engine_rpm >= _limiter_rpm * 0.994 and load_eff > 0.45
	var limiter_gain := 1.0
	var limiter_pitch := 1.0
	if _limiter_active:
		_limiter_phase += safe_delta * TAU * 19.0
		var gate := smoothstep(-0.25, 0.25, sin(_limiter_phase))
		limiter_gain = 0.42 + 0.58 * gate
		limiter_pitch = 0.982 + 0.018 * gate
	else:
		_limiter_phase = 0.0

	_on_low_player.pitch_scale = clampf(_sound_rpm / float(_bank_rpms[_low_index]), _pitch_min, _pitch_max) * limiter_pitch
	_on_high_player.pitch_scale = clampf(_sound_rpm / float(_bank_rpms[_high_index]), _pitch_min, _pitch_max) * limiter_pitch
	_off_low_player.pitch_scale = _on_low_player.pitch_scale
	_off_high_player.pitch_scale = _on_high_player.pitch_scale
	# A real idling V8 hunts: slow pitch/gain wander around the mark.
	var idle_wander := 1.0 + 0.010 * sin(_idle_time * 0.83) + 0.007 * sin(_idle_time * 2.11 + 1.7)
	_idle_player.pitch_scale = _idle_pitch * idle_wander
	var idle_gain_wander := 1.0 + 0.05 * sin(_idle_time * 1.27 + 0.4)

	var segment_angle := _segment_fraction * PI * 0.5
	var low_weight := cos(segment_angle)
	var high_weight := sin(segment_angle)
	var load_angle := load_eff * PI * 0.5
	var on_weight := sin(load_angle)
	var off_weight := cos(load_angle)

	var idle_weight := 1.0 - smoothstep(_idle_crossfade_low, _idle_crossfade_high, _sound_rpm)
	idle_weight *= 1.0 - smoothstep(0.18, 0.46, load_eff) * 0.72
	idle_weight = clampf(idle_weight, 0.0, 1.0)
	var bank_weight := sqrt(maxf(1.0 - idle_weight * idle_weight, 0.0))

	var rpm_mix := clampf((_sound_rpm - 850.0) / maxf(_sound_redline - 850.0, 1000.0), 0.0, 1.0)
	var master_db := lerpf(-4.5, 1.2, rpm_mix) + load_eff * 1.4 + (2.0 if boost_active else 0.0) + _master_db_offset + _listener_engine_db
	var master_gain := _state_gain * db_to_linear(master_db) * limiter_gain

	if _engine_lowpass != null:
		var lp_target := (620.0 + 5600.0 * pow(rpm_mix, 1.35) + 1900.0 * load_eff) * _exhaust_lp_mult * _listener_lp_mult
		_engine_lp_hz = lerpf(_engine_lp_hz, clampf(lp_target, 480.0, 11800.0), 1.0 - exp(-9.0 * safe_delta))
		_engine_lowpass.cutoff_hz = _engine_lp_hz

	_set_gain(_idle_player, master_gain * idle_weight * 0.92 * idle_gain_wander)
	_set_gain(_on_low_player, master_gain * bank_weight * on_weight * low_weight)
	_set_gain(_on_high_player, master_gain * bank_weight * on_weight * high_weight)
	_set_gain(_off_low_player, master_gain * bank_weight * off_weight * low_weight)
	_set_gain(_off_high_player, master_gain * bank_weight * off_weight * high_weight)


func _foley_ready() -> bool:
	return (
		WIND_STREAM != null and WHINE_STREAM != null and SCRAPE_STREAM != null
		and THUMP_STREAM != null and CLUNK_STREAM != null
		and IMPACT_SOFT_STREAM != null and IMPACT_MED_STREAM != null
		and IMPACT_HARD_STREAM != null
		and ROAD_ASPHALT_STREAM != null and ROAD_SIDEWALK_STREAM != null
		and ROAD_GRASS_STREAM != null and ROAD_SAND_STREAM != null
	)


func get_smoke_state() -> Dictionary:
	var streams_ready := not _on_streams.is_empty() and _on_streams.size() == _off_streams.size() and _on_streams.size() == _bank_rpms.size()
	for stream in _on_streams:
		streams_ready = streams_ready and stream != null
	for stream in _off_streams:
		streams_ready = streams_ready and stream != null
	return {
		"recorded_audio_0235": RECORDED_AUDIO_0235,
		"audio_realism_0242": AUDIO_REALISM_0242,
		"recorded_gt500_bank": _bank_id == "shelby_gt500",
		"multi_car_audio_0240": true,
		"car_id": _car_id,
		"bank_id": _bank_id,
		"anchor_rpms": _bank_rpms.duplicate(),
		"pitch_min": _pitch_min,
		"pitch_max": _pitch_max,
		"sound_redline": _sound_redline,
		"limiter_rpm": _limiter_rpm,
		"on_loop_count": _on_streams.size(),
		"off_loop_count": _off_streams.size(),
		"pops_count": _pop_streams.size(),
		"pops_fired": _pops_fired,
		"crackle_amount": _crackle_amount,
		"foley_ready": _foley_ready(),
		"engine_lowpass_ready": _engine_lowpass != null,
		"tire_panner_ready": _tire_panner != null,
		"engine_lp_hz": _engine_lp_hz,
		"camera_mode": _camera_mode,
		"road_kind": _road_kind,
		"streams_ready": streams_ready and _idle_stream != null and _start_stream != null and _stop_stream != null and TIRE_STREAM != null,
		"players_created": _all_players().size(),
		"bus_ready": AudioServer.get_bus_index(_bus_name) >= 0 and AudioServer.get_bus_index(_engine_bus_name) >= 0 and AudioServer.get_bus_index(_events_bus_name) >= 0,
		"state_gain": _state_gain,
		"load": _load_smooth,
		"sound_rpm": _sound_rpm,
		"low_index": _low_index,
		"high_index": _high_index,
		"tire_level": _tire_smooth,
		"road_level": _road_level,
		"wind_level": _wind_level,
		"suspended": _suspended,
	}
