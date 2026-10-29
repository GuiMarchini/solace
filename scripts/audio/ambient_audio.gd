class_name AmbientAudio
extends Node
## A soft, cozy procedural soundscape (no audio files). Nothing tonal follows the speed
## (that read as an engine); the world is made of air and sand, and the magic of
## small, warm kalimba-like notes:
##   * wind: gentle filtered noise with slow gusts, a soft air rush in flight and at speed,
##   * sand: the hush of the sword sliding over the dunes, louder and grainier in carves,
##     silent in the air,
##   * one-shots synthesized once at startup: soft pentatonic notes for summoning, a fully
##     charged jump, clean trick landings and a finished combo; muffled sand puffs for
##     landings; airy swishes for jumps, tricks and boosts,
##   * combat, kept just as soft: airy swishes and a turning whirl for the attacks, a muffled
##     wooden knock with a warm note for each hit (one pentatonic step higher per hit of a
##     combo), a deep muffled boom for the heavy blows and a slow arpeggio for the Last Spirit.
## Effects play on an "SFX" bus with a gentle low-pass and a warm reverb; wind and sand
## on an "Ambience" bus with a low-pass, so nothing is ever sharp.
## To use recorded assets later, replace the streams on the players created here.

@export var player_path: NodePath
@export_range(0.0, 1.0) var master_volume := 0.7
@export_range(0.0, 1.0) var wind_volume := 0.32
@export_range(0.0, 1.0) var sand_volume := 0.26
@export_range(0.0, 1.0) var sfx_volume := 0.5

const RATE := 22050.0
## C major pentatonic, a warm register (Hz).
const C5 := 523.25
const D5 := 587.33
const E5 := 659.25
const G5 := 783.99
const A5 := 880.0
const C6 := 1046.5
const G4 := 392.0
## Each attack's sound and gain.
const ATTACK_SOUNDS := {"light": ["slash", 0.5], "spin": ["spin", 0.5], "dash": ["dash", 0.55],
	"heavy": ["heavy_rise", 0.5], "special": ["spirit", 0.7]}
## Pentatonic steps up from C: each hit of a combo rings one step higher.
const STEPS := [1.0, 1.122, 1.26, 1.498, 1.682, 2.0]

var _player: PlayerController
var _wind: AudioStreamPlayer
var _sand: AudioStreamPlayer
var _wind_pb: AudioStreamGeneratorPlayback
var _sand_pb: AudioStreamGeneratorPlayback
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _sounds := {}

# DSP state
var _w_lo := 0.0
var _w_mid := 0.0
var _w_mid2 := 0.0
var _a_lp := 0.0
var _s_hp_in := 0.0
var _s_hp := 0.0
var _s_lp := 0.0
var _s_lp2 := 0.0
var _grain := 0.0
var _grain_target := 0.0
var _grain_count := 0
var _gust := 0.5
var _gust_target := 0.5
var _speed01 := 0.0
var _contact := 0.0
var _carve := 0.0
var _air := 0.0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		# No audio device in automated runs; skip synthesis entirely.
		set_process(false)
		return
	var lp_amb := AudioEffectLowPassFilter.new()
	lp_amb.cutoff_hz = 4200.0
	_bus("Ambience", [lp_amb])
	var lp_sfx := AudioEffectLowPassFilter.new()
	lp_sfx.cutoff_hz = 6500.0
	var verb := AudioEffectReverb.new()
	verb.room_size = 0.55
	verb.damping = 0.6
	verb.spread = 0.7
	verb.hipass = 0.15
	verb.dry = 0.9
	verb.wet = 0.2
	verb.predelay_msec = 40.0
	_bus("SFX", [lp_sfx, verb])
	_player = get_node_or_null(player_path) as PlayerController
	_wind = _make_generator("Wind", "Ambience")
	_sand = _make_generator("Sand", "Ambience")
	_wind_pb = _wind.get_stream_playback() as AudioStreamGeneratorPlayback
	_sand_pb = _sand.get_stream_playback() as AudioStreamGeneratorPlayback
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_sfx_pool.append(p)
	_sounds = make_sounds()
	if _player:
		_player.mode_changed.connect(_on_mode_changed)
		_player.jumped.connect(_on_jumped)
		_player.landed.connect(_on_landed)
		_player.dodged.connect(_on_dodged)
		_player.boost_changed.connect(_on_boost_changed)
		(_player.get_node("HoverMotor") as HoverMotor).charge_ready.connect(func() -> void: play("charge_ready", 0.9))
		var visual := _player.get_node_or_null("Visual") as PlayerVisual
		if visual:
			var td := visual.tricks
			td.move_started.connect(_on_trick_move)
			td.landed.connect(_on_trick_landed)
			td.combo.banked.connect(_on_combo_banked)
			var cd := visual.combat
			cd.attack_started.connect(_on_attack)
			cd.hit_landed.connect(_on_hit)
			cd.impact.connect(_on_impact)
			cd.special_ready.connect(func() -> void: play("spirit_ready", 0.55))
			cd.air_jumped.connect(func() -> void: play("rebound", 0.5))


## Every one-shot, synthesized (also used by tools/render_sounds.gd to preview them).
func make_sounds() -> Dictionary:
	return {
		"summon": _kalimba([G4, C5, E5, G5], 0.08, 1.8, 0.5),
		"dismiss": _kalimba([G5, E5, C5], 0.09, 1.5, 0.4),
		"charge_ready": _twinkle(),
		"land_clean": _kalimba([C5, G5], 0.035, 1.4, 0.38),
		"banked": _kalimba([E5, G5, A5, C6], 0.1, 2.0, 0.34),
		"board_jump": _swish(0.3, 500.0, 900.0, 0.22),
		"jump": _swish(0.28, 500.0, 900.0, 0.2),
		"trick": _swish(0.34, 450.0, 1050.0, 0.22),
		"boost": _swish(0.8, 400.0, 1000.0, 0.3),
		"dodge": _swish(0.3, 500.0, 1100.0, 0.22),
		"land": _sand_puff(0.45, 0.55),
		"slash": _swish(0.24, 650.0, 1500.0, 0.2),
		"spin": _whirl(0.62, 500.0, 1250.0, 0.2, 6.5),
		"dash": _swish(0.42, 380.0, 1400.0, 0.24),
		"heavy_rise": _swish(0.6, 320.0, 950.0, 0.22),
		"spirit": _spirit_rise(),
		"hit": _hit_knock(),
		"boom": _soft_boom(1.6, 0.6),
		"rebound": _kalimba([G5, C6], 0.05, 0.9, 0.28),
		"spirit_ready": _kalimba([C5, G5, C6], 0.09, 1.6, 0.3),
	}


static func _bus(bus_name: String, effects: Array) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, &"Master")
	for e in effects:
		AudioServer.add_bus_effect(idx, e)


func _on_mode_changed(m: PlayerController.Mode) -> void:
	play("summon" if m == PlayerController.Mode.RIDE else "dismiss", 0.8)


func _on_jumped(on_board: bool) -> void:
	play("board_jump" if on_board else "jump", 0.7)


func _on_landed(impact: float, _on_board: bool) -> void:
	if impact > 2.5:
		play("land", clampf(impact / 16.0, 0.2, 0.9), randf_range(0.85, 1.05))


func _on_dodged(_dir: Vector3) -> void:
	play("dodge", 0.6)


func _on_boost_changed(on: bool) -> void:
	if on:
		play("boost", 0.7)


func _on_trick_move(_move: String, _title: String, by_player: bool) -> void:
	play("trick", 0.55 if by_player else 0.3, randf_range(0.9, 1.1))


func _on_trick_landed(clean: bool, had_tricks: bool) -> void:
	if had_tricks and clean:
		play("land_clean", 0.7, [1.0, 1.122, 0.891][randi() % 3])


func _on_combo_banked(_total: int, multiplier: float) -> void:
	if multiplier >= 2.0:
		play("banked", 0.65)


func _on_attack(kind: String) -> void:
	var s: Array = ATTACK_SOUNDS.get(kind, ["slash", 0.5])
	play(s[0], s[1], randf_range(0.93, 1.07) if kind == "light" or kind == "spin" else 0.0)


func _on_hit(_target: Node3D, heavy: bool, combo: int) -> void:
	var step: float = STEPS[clampi(combo - 1, 0, STEPS.size() - 1)]
	play("hit", 0.7 if heavy else 0.5, step * (0.75 if heavy else 1.0))


func _on_impact(_point: Vector3, strength: float) -> void:
	play("boom", clampf(0.35 + 0.18 * strength, 0.4, 0.9), 1.08 - 0.06 * strength)


func _exit_tree() -> void:
	if _wind == null:
		return
	for p in _sfx_pool:
		p.stop()
		p.stream = null
	_wind.stop()
	_sand.stop()
	_wind_pb = null
	_sand_pb = null
	_sounds.clear()


func play(sound: String, gain: float = 1.0, pitch: float = 0.0) -> void:
	if not _sounds.has(sound):
		return
	var p := _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	p.stream = _sounds[sound]
	p.volume_db = linear_to_db(maxf(sfx_volume * master_volume * gain, 0.0001))
	p.pitch_scale = pitch if pitch > 0.0 else randf_range(0.97, 1.03)
	p.play()


func _make_generator(n: String, bus: String) -> AudioStreamPlayer:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.2
	var p := AudioStreamPlayer.new()
	p.name = n
	p.stream = gen
	p.bus = bus
	p.volume_db = linear_to_db(master_volume)
	add_child(p)
	p.play()
	return p


func _process(delta: float) -> void:
	var riding := false
	var speed := 0.0
	var contact := false
	var carve := 0.0
	if _player:
		riding = _player.mode == PlayerController.Mode.RIDE
		speed = _player.horizontal_speed()
		var hm := _player.hover
		contact = riding and hm.supported and hm.ground_distance < 0.6
		carve = absf(hm.carve) + hm.drift_amount * 0.5
	var k := 1.0 - exp(-4.0 * delta)
	_speed01 = lerpf(_speed01, clampf(speed / 30.0, 0.0, 1.2), k)
	_contact = lerpf(_contact, 1.0 if contact else 0.0, 1.0 - exp(-12.0 * delta))
	_carve = lerpf(_carve, clampf(carve, 0.0, 1.0), k)
	_air = lerpf(_air, 1.0 if riding and not contact else 0.0, 1.0 - exp(-5.0 * delta))
	if randf() < delta * 0.2:
		_gust_target = randf_range(0.2, 1.0)
	_gust = lerpf(_gust, _gust_target, 1.0 - exp(-0.5 * delta))
	_fill_wind()
	_fill_sand()


## Desert air: a low, soft bed with slow gusts, and a gentle rush of air in flight and
## at speed (low-passed, never hissy).
func _fill_wind() -> void:
	if _wind_pb == null:
		return
	var n := _wind_pb.get_frames_available()
	if n <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		var s := wind_frame()
		buf[i] = Vector2(s, s * 0.94)
	_wind_pb.push_buffer(buf)


## One sample of the wind (state: _gust, _speed01, _air).
func wind_frame() -> float:
	var bed := wind_volume * (0.25 + 0.35 * _gust)
	var rush := wind_volume * _speed01 * (0.25 + 0.55 * _air)
	var mid_c := 0.025 + 0.03 * _speed01
	var w := randf() * 2.0 - 1.0
	_w_lo += (w - _w_lo) * 0.008
	_w_mid += (w - _w_mid) * mid_c
	_w_mid2 += (_w_mid - _w_mid2) * mid_c
	_a_lp += (_w_mid2 - _a_lp) * 0.5
	return _w_lo * 7.0 * bed + _a_lp * 3.2 * rush


## Sand under the sword: a soft "shhh" (noise band-passed around the hiss of sliding
## sand, rounded off on top), its level following contact and speed, louder and
## grainier while carving (slow random swells, like sand piling and spilling).
func _fill_sand() -> void:
	if _sand_pb == null:
		return
	var n := _sand_pb.get_frames_available()
	if n <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		var s := sand_frame()
		buf[i] = Vector2(s * 0.95, s)
	_sand_pb.push_buffer(buf)


## One sample of the sand under the sword (state: _contact, _speed01, _carve).
func sand_frame() -> float:
	var level := sand_volume * _contact * clampf(_speed01 * 1.6, 0.0, 1.0) * (0.55 + 0.75 * _carve)
	_grain_count += 1
	if _grain_count >= 220:
		_grain_count = 0
		_grain_target = randf_range(0.55, 1.0)
	_grain += (_grain_target - _grain) * 0.004
	var w := randf() * 2.0 - 1.0
	# High-pass (~700 Hz), then two soft low-passes (~2.5 kHz).
	_s_hp = 0.82 * (_s_hp + w - _s_hp_in)
	_s_hp_in = w
	_s_lp += (_s_hp - _s_lp) * 0.45
	_s_lp2 += (_s_lp - _s_lp2) * 0.45
	return _s_lp2 * level * _grain * 0.9


## Sets the state the ambience follows (offline rendering and tests).
func set_ambience(speed01: float, contact: float, carve: float, air: float, gust: float) -> void:
	_speed01 = speed01
	_contact = contact
	_carve = carve
	_air = air
	_gust = gust


# --- One-shot synthesis -------------------------------------------------------------------

func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(RATE)
	wav.stereo = false
	wav.data = bytes
	return wav


## Soft plucked notes like a kalimba: a rounded sine with a quick, gentle attack and a
## long decay, a faint octave that fades first, a tiny wooden "tine" at the onset, and
## two quiet echoes. `gap` seconds between notes.
func _kalimba(notes: Array, gap: float, length: float, gain: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := i / RATE
		var v := 0.0
		for k in notes.size():
			var start := k * gap
			if t < start:
				continue
			var tt := t - start
			var f: float = notes[k]
			var attack := 1.0 - exp(-tt * 260.0)
			v += (sin(TAU * f * tt) * exp(-tt * 2.6)
					+ 0.22 * sin(TAU * f * 2.01 * tt) * exp(-tt * 7.0)
					+ 0.06 * sin(TAU * f * 4.3 * tt) * exp(-tt * 28.0)) * attack
		s[i] = v * gain / maxf(sqrt(notes.size()), 1.0) * 0.55
	return _to_wav(_echo(s, [[0.11, 0.25], [0.24, 0.12]]))


## The charged jump being ready: three quick soft notes rising, with a faint, slowly
## trembling shimmer above them.
func _twinkle() -> AudioStreamWAV:
	var notes := _kalimba([E5, G5, C6], 0.06, 1.4, 0.5)
	var n := int(1.4 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var src := notes.data
	for i in n:
		var t := i / RATE
		var base := float(src.decode_s16(i * 2)) / 32767.0 if i * 2 + 1 < src.size() else 0.0
		var shimmer := sin(TAU * 2093.0 * t) * (0.5 + 0.5 * sin(TAU * 7.0 * t)) * exp(-t * 3.0) * smoothstep(0.0, 0.12, t) * 0.035
		s[i] = base + shimmer
	return _to_wav(s)


## A soft airy swish: noise through a gentle band that sweeps from `f0` to `f1` Hz,
## with a smooth rise and fall.
func _swish(length: float, f0: float, f1: float, gain: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var hp_in := 0.0
	var hp := 0.0
	for i in n:
		var t := float(i) / n
		var env := pow(sin(PI * pow(t, 0.7)), 2.0)
		var c := clampf(lerpf(f0, f1, sin(PI * t * 0.5)) / RATE * TAU, 0.0, 1.0)
		var w := randf() * 2.0 - 1.0
		hp = 0.9 * (hp + w - hp_in)
		hp_in = w
		lp += (hp - lp) * c
		lp2 += (lp - lp2) * c
		s[i] = lp2 * env * gain * 2.2
	return _to_wav(s)


## A muffled puff of sand: low-passed noise with a soft attack and a quick settle, a
## faint lower body under it (no thump).
func _sand_puff(length: float, gain: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var lo := 0.0
	for i in n:
		var t := i / RATE
		var env := (1.0 - exp(-t * 90.0)) * exp(-t * 9.0)
		var w := randf() * 2.0 - 1.0
		lp += (w - lp) * 0.22
		lp2 += (lp - lp2) * 0.22
		lo += (w - lo) * 0.03
		s[i] = (lp2 * 1.4 + lo * 2.5) * env * gain
	return _to_wav(s)


## A soft whirl for the spin: a swish whose loudness swells `turns` times a second.
func _whirl(length: float, f0: float, f1: float, gain: float, turns: float) -> AudioStreamWAV:
	var s := _samples(_swish(length, f0, f1, gain))
	for i in s.size():
		s[i] *= 0.6 + 0.4 * sin(TAU * turns * i / RATE - PI * 0.5)
	return _to_wav(s)


## A hit: a muffled wooden knock with a warm note ringing out of it.
func _hit_knock() -> AudioStreamWAV:
	var n := int(1.1 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := i / RATE
		lp += (randf() * 2.0 - 1.0 - lp) * 0.18
		var knock := (lp * 1.6 + sin(TAU * 210.0 * t) * 0.8) * (1.0 - exp(-t * 600.0)) * exp(-t * 38.0)
		var note := (sin(TAU * C5 * t) + 0.18 * sin(TAU * C5 * 3.0 * t) * exp(-t * 9.0)) * (1.0 - exp(-t * 300.0)) * exp(-t * 3.4)
		s[i] = (knock * 0.5 + note * 0.42) * 0.6
	return _to_wav(_echo(s, [[0.09, 0.2], [0.2, 0.1]]))


## A soft, muffled boom for the heavy blows: a low swell sinking in pitch under a rumble,
## then the hush of thrown sand (no hard thump).
func _soft_boom(length: float, gain: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var hs := 0.0
	var ph := 0.0
	for i in n:
		var t := i / RATE
		ph += TAU * (48.0 + 52.0 * exp(-t * 6.0)) / RATE
		var body := sin(ph) * (1.0 - exp(-t * 70.0)) * exp(-t * 4.2)
		var w := randf() * 2.0 - 1.0
		lp += (w - lp) * 0.06
		lp2 += (lp - lp2) * 0.06
		hs += (w - hs) * 0.35
		var rumble := lp2 * 4.0 * (1.0 - exp(-t * 25.0)) * exp(-t * 3.0)
		var hush := (hs - lp) * 0.12 * smoothstep(0.03, 0.18, t) * exp(-maxf(t - 0.18, 0.0) * 4.5)
		s[i] = (body * 0.8 + rumble + hush) * gain
	return _to_wav(_echo(s, [[0.13, 0.22], [0.3, 0.1]]))


## The Last Spirit gathering: a slow arpeggio rising over a breath of air.
func _spirit_rise() -> AudioStreamWAV:
	var s := _samples(_kalimba([G4, C5, E5, G5, C6], 0.13, 2.4, 0.42))
	var air := _samples(_swish(1.1, 300.0, 900.0, 0.18))
	for i in mini(s.size(), air.size()):
		s[i] += air[i]
	return _to_wav(s)


func _samples(w: AudioStreamWAV) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(w.data.size() / 2)
	for i in s.size():
		s[i] = float(w.data.decode_s16(i * 2)) / 32767.0
	return s


## Adds quiet echoes ([delay s, gain] taps) for a little space.
func _echo(s: PackedFloat32Array, taps: Array) -> PackedFloat32Array:
	var out := s.duplicate()
	for tap in taps:
		var d := int(float(tap[0]) * RATE)
		var g: float = tap[1]
		for i in range(d, out.size()):
			out[i] += s[i - d] * g
	return out
