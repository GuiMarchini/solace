class_name MotionContext
extends Node
## Contextual movement variations: decides WHEN the spirit does something special,
## SpiritModel decides HOW it looks.
##
## Every variation has eligibility rules (speed, turn sharpness, slope, grounded state,
## landing intensity, idle time, board state), a cooldown and a controlled chance, so
## details like brushing the sand in a turn stay rare and always fit the situation.
## Outputs are smooth 0..1 weights read by SpiritModel and PlayerFX. Player input always
## wins: any input fades idle/rest behaviours out in a fraction of a second.

signal sand_touch_started(side: float)
signal landing_slide_started
signal gesture_started(side: float)
signal sat_down

@export var enabled := true
## For screenshots/tests: makes every eligible variation trigger (ignores chance).
@export var force_variations := false
@export_group("Sand-touch turn")
@export var sand_touch_min_speed := 4.0
## Lateral acceleration (m/s^2) the turn must reach.
@export var sand_touch_min_lateral := 6.5
@export var sand_touch_hold_time := 0.06
@export var sand_touch_max_slope_deg := 24.0
@export var sand_touch_cooldown := 7.0
@export_range(0.0, 1.0) var sand_touch_chance := 0.45
@export var sand_touch_duration := 0.75
@export_group("Sprint")
@export var sprint_settle_speed := 6.0
@export var sprint_settle_delay := 1.2
@export_group("Landing")
@export var hard_landing_impact := 11.0
@export var slide_min_speed := 4.0
@export_group("Stops and balance")
@export var stop_from_speed := 3.5
@export var balance_slope_deg := 18.0
@export_group("Long runs")
@export var long_run_time := 6.0
@export var long_run_look_cooldown := 14.0
@export_range(0.0, 1.0) var long_run_look_chance := 0.5
@export_group("Idle")
@export var idle_fidget_delay := 2.5
@export var idle_fidget_interval := Vector2(4.0, 8.0)
@export var rest_after := Vector2(20.0, 35.0)
@export_range(0.0, 1.0) var rest_chance := 0.65
@export var seated_time := Vector2(8.0, 16.0)
@export_group("Hoverboard")
@export var grab_min_air_time := 0.5
@export var grab_cooldown := 4.0
@export_range(0.0, 1.0) var grab_chance := 0.5
@export var relaxed_glide_delay := 2.0
## While cruising steadily, now and then shift the riding style for a moment (seconds
## between changes): crouch low, point ahead, glance back, open the arms.
@export var board_style_interval := Vector2(5.0, 9.0)

# --- Outputs (0..1 weights unless noted) ---
var sand_touch := 0.0
var sand_side := 0.0
var sprint_settle := 0.0
var land_low := 0.0
var stop_recover := 0.0
var stop_side := 1.0
var look := 0.0
var look_yaw := 0.0
var look_pitch := 0.0
var weight_shift := 0.0
var shift_side := 1.0
var gesture := 0.0
var gesture_side := 1.0
var sit := 0.0
var balance := 0.0
var board_tuck := 0.0
var board_grab := 0.0
var board_drift := 0.0
var board_drift_dir := 0.0
var board_relaxed := 0.0
## Current cruising style (0 low crouch, 1 point ahead, 2 glance back, 3 arms wide) and
## its weight.
var board_style := 0
var board_style_w := 0.0
## Name of the active full-body variation (for debugging / tests).
var active := ""

var _rng := RandomNumberGenerator.new()
var _env := {}            # name -> [time, duration, attack, release]
var _cool := {}           # name -> remaining seconds
var _turn_time := 0.0
var _turn_rolled := false
var _sprint_time := 0.0
var _run_time := 0.0
var _speed_hist: Array[float] = []
var _idle_time := 0.0
var _rest_threshold := 25.0
var _rest_rolled := false
var _next_fidget := 5.0
var _last_fidget := ""
var _rest_stage := 0      # 0 none, 1 look, 2 sitting down, 3 seated, 4 standing
var _rest_t := 0.0
var _seated_for := 10.0
var _air_was := false
var _air_time := 0.0
var _relax_time := 0.0
var _style_timer := 6.0
var _style_left := 0.0


func _ready() -> void:
	_rng.randomize()
	_rest_threshold = _rng.randf_range(rest_after.x, rest_after.y)


## `inputs`: a snapshot from PlayerVisual (see keys used below).
func update(delta: float, s: Dictionary) -> void:
	if not enabled:
		_clear()
		return
	for k in _cool.keys():
		_cool[k] = maxf(0.0, _cool[k] - delta)
	var speed: float = s["speed"]
	var grounded: bool = s["grounded"]
	var riding: bool = s["riding"]
	var has_input: bool = s["has_input"]
	var turn_rate: float = s["turn_rate"]
	var slope_deg: float = s["slope_deg"]

	_speed_hist.append(speed)
	if _speed_hist.size() > 20:
		_speed_hist.pop_front()

	if riding:
		_update_board(delta, s)
		_reset_foot_state()
	else:
		board_tuck = move_toward(board_tuck, 0.0, delta * 4.0)
		board_grab = move_toward(board_grab, 0.0, delta * 4.0)
		board_drift = move_toward(board_drift, 0.0, delta * 4.0)
		board_relaxed = move_toward(board_relaxed, 0.0, delta * 4.0)
		_update_foot(delta, speed, grounded, has_input, turn_rate, slope_deg, s)

	sand_touch = _env_value("sand_touch", delta)
	land_low = _env_value("land_low", delta)
	stop_recover = _env_value("stop", delta)
	weight_shift = _env_value("shift", delta)
	gesture = _env_value("gesture", delta)
	var run_look := _env_value("run_look", delta)
	var idle_look := _env_value("idle_look", delta)
	look = maxf(run_look, idle_look)
	active = ""
	for n in _env:
		active = n
		break
	if sit > 0.0 or _rest_stage > 0:
		active = "rest"


func _update_foot(delta: float, speed: float, grounded: bool, has_input: bool, turn_rate: float,
		slope_deg: float, s: Dictionary) -> void:
	var lateral := absf(turn_rate) * speed
	var busy := _env.has("sand_touch") or _env.has("land_low") or _env.has("stop")

	# Sharp running turn -> occasionally brush the sand with the inner hand.
	if grounded and speed >= sand_touch_min_speed and lateral >= sand_touch_min_lateral and slope_deg <= sand_touch_max_slope_deg:
		_turn_time += delta
		if _turn_time >= sand_touch_hold_time and not _turn_rolled:
			_turn_rolled = true
			if not busy and _ready_for("sand_touch") and _roll(sand_touch_chance):
				sand_side = -1.0 if turn_rate > 0.0 else 1.0
				_start("sand_touch", sand_touch_duration, 0.18, 0.3)
				_cool["sand_touch"] = sand_touch_cooldown
				sand_touch_started.emit(sand_side)
	elif lateral < sand_touch_min_lateral * 0.5:
		_turn_time = 0.0
		_turn_rolled = false

	# Settling into a sprint after holding top speed for a moment.
	if grounded and speed >= sprint_settle_speed:
		_sprint_time += delta
	else:
		_sprint_time = maxf(0.0, _sprint_time - delta * 3.0)
	var settle_target := 1.0 if _sprint_time > sprint_settle_delay and speed >= sprint_settle_speed - 0.8 else 0.0
	sprint_settle = move_toward(sprint_settle, settle_target, delta * (1.0 if settle_target > 0.0 else 2.5))

	# Hard landing (low pose; a short slide if still moving fast).
	if s["landed_impact"] > 0.0:
		var impact: float = s["landed_impact"]
		if (impact >= hard_landing_impact or _air_time > 0.9) and not _env.has("land_low"):
			var slide := speed >= slide_min_speed
			_start("land_low", 0.7 if slide else 0.5, 0.06, 0.3)
			if slide:
				landing_slide_started.emit()
	_air_time = 0.0 if grounded else _air_time + delta

	# Abrupt stop from a run.
	if _speed_hist.size() >= 15 and _speed_hist[0] >= stop_from_speed and speed < 1.2 and not has_input \
			and grounded and not busy and _ready_for("stop"):
		stop_side = -1.0 if _rng.randf() < 0.5 else 1.0
		_start("stop", 0.55, 0.08, 0.3)
		_cool["stop"] = 1.5

	# Balance on steep or uneven sand.
	var steep := smoothstep(balance_slope_deg, balance_slope_deg + 12.0, slope_deg) if speed > 0.5 else 0.0
	balance = move_toward(balance, steep, delta * 2.0)

	# Long runs: now and then glance toward the horizon.
	_run_time = _run_time + delta if speed > 4.0 and grounded else 0.0
	if _run_time > long_run_time and _ready_for("run_look") and not busy:
		_cool["run_look"] = 3.0
		if _roll(long_run_look_chance):
			look_yaw = (-1.0 if _rng.randf() < 0.5 else 1.0) * _rng.randf_range(0.5, 0.8)
			look_pitch = -0.05
			_start("run_look", 1.6, 0.4, 0.5)
			_cool["run_look"] = long_run_look_cooldown

	_update_idle(delta, speed, grounded, has_input)


func _update_idle(delta: float, speed: float, grounded: bool, has_input: bool) -> void:
	var idle := grounded and speed < 0.2 and not has_input
	if not idle:
		_idle_time = 0.0
		_rest_rolled = false
		_next_fidget = _rng.randf_range(idle_fidget_interval.x, idle_fidget_interval.y)
		# Input always wins: fade idle behaviours out quickly.
		for n in ["shift", "gesture", "idle_look"]:
			_interrupt(n)
		if _rest_stage > 0:
			_rest_stage = 0
			_rest_threshold = _rng.randf_range(rest_after.x, rest_after.y)
		sit = move_toward(sit, 0.0, delta * 4.0)
		return
	_idle_time += delta

	if _rest_stage == 0:
		sit = move_toward(sit, 0.0, delta * 4.0)
		if _idle_time > _rest_threshold and not _rest_rolled:
			_rest_rolled = true
			if _roll(rest_chance):
				_rest_stage = 1
				_rest_t = 0.0
				_seated_for = _rng.randf_range(seated_time.x, seated_time.y)
				look_yaw = (-1.0 if _rng.randf() < 0.5 else 1.0) * 0.7
				look_pitch = -0.08
				_start("idle_look", 2.2, 0.6, 0.6)
		elif _idle_time > idle_fidget_delay and _idle_time > _next_fidget and _env.is_empty():
			_fidget()
			_next_fidget = _idle_time + _rng.randf_range(idle_fidget_interval.x, idle_fidget_interval.y)
		return

	_rest_t += delta
	match _rest_stage:
		1:
			if _rest_t > 2.0:
				_rest_stage = 2
				_rest_t = 0.0
		2:
			sit = move_toward(sit, 1.0, delta / 1.3)
			if sit >= 1.0:
				_rest_stage = 3
				_rest_t = 0.0
				sat_down.emit()
		3:
			if _rest_t > _seated_for:
				_rest_stage = 4
				_rest_t = 0.0
		4:
			sit = move_toward(sit, 0.0, delta / 1.0)
			if sit <= 0.0:
				_rest_stage = 0
				_idle_time = 0.0
				_rest_rolled = false
				_rest_threshold = _rng.randf_range(rest_after.x, rest_after.y)


func _fidget() -> void:
	var options := ["look", "shift", "gesture"]
	options.erase(_last_fidget)
	var pick: String = options[_rng.randi() % options.size()]
	_last_fidget = pick
	match pick:
		"look":
			look_yaw = _rng.randf_range(-0.9, 0.9)
			look_pitch = _rng.randf_range(-0.12, 0.05)
			_start("idle_look", 2.6, 0.7, 0.8)
		"shift":
			shift_side = -shift_side
			_start("shift", 3.0, 0.8, 0.9)
		"gesture":
			gesture_side = -1.0 if _rng.randf() < 0.5 else 1.0
			_start("gesture", 2.4, 0.6, 0.7)
			gesture_started.emit(gesture_side)


func _update_board(delta: float, s: Dictionary) -> void:
	var supported: bool = s["board_supported"]
	var air_time: float = s["board_air_time"]
	board_tuck = move_toward(board_tuck, 1.0 if (not supported and air_time > 0.25) else 0.0, delta * 5.0)
	if not supported and air_time > grab_min_air_time and board_grab <= 0.0 and _ready_for("grab"):
		_cool["grab"] = grab_cooldown
		if _roll(grab_chance):
			board_grab = 0.001
	if board_grab > 0.0:
		board_grab = move_toward(board_grab, 0.0 if supported else 1.0, delta * (6.0 if supported else 3.0))
	board_drift = move_toward(board_drift, s["board_drift"], delta * 6.0)
	board_drift_dir = s["board_drift_dir"]
	var steady: bool = supported and absf(s["board_carve"]) < 0.15 and s["boost"] < 0.05 and s["speed"] > 10.0
	_relax_time = _relax_time + delta if steady else 0.0
	board_relaxed = move_toward(board_relaxed, 1.0 if _relax_time > relaxed_glide_delay else 0.0, delta * 1.2)
	# Cruising styles: only on calm, straight stretches; anything else fades them out.
	var cruising: bool = supported and absf(s["board_carve"]) < 0.3 and s["speed"] > 7.0
	if cruising:
		_style_timer -= delta
		if _style_timer <= 0.0 and _style_left <= 0.0:
			var pick := _rng.randi() % 4
			if pick == board_style:
				pick = (pick + 1 + _rng.randi() % 3) % 4
			board_style = pick
			_style_left = _rng.randf_range(1.6, 2.6)
			_style_timer = _rng.randf_range(board_style_interval.x, board_style_interval.y)
	else:
		_style_left = 0.0
	_style_left = maxf(_style_left - delta, 0.0)
	board_style_w = move_toward(board_style_w, 1.0 if _style_left > 0.3 else 0.0, delta * 2.2)


func _reset_foot_state() -> void:
	sprint_settle = move_toward(sprint_settle, 0.0, 0.1)
	balance = 0.0
	_idle_time = 0.0
	sit = 0.0
	_rest_stage = 0
	for n in ["sand_touch", "stop", "shift", "gesture", "idle_look", "run_look", "land_low"]:
		_interrupt(n)


func _clear() -> void:
	_env.clear()
	sand_touch = 0.0
	land_low = 0.0
	stop_recover = 0.0
	look = 0.0
	weight_shift = 0.0
	gesture = 0.0
	sit = 0.0
	balance = 0.0
	sprint_settle = 0.0


# --- Envelopes ------------------------------------------------------------------------

func _start(n: String, duration: float, attack: float, release: float) -> void:
	_env[n] = [0.0, duration, attack, release]


## Fades a running variation out quickly instead of cutting it.
func _interrupt(n: String) -> void:
	if _env.has(n):
		var e: Array = _env[n]
		var remaining: float = e[1] - e[0]
		if remaining > 0.2:
			e[0] = e[1] - 0.2
			e[3] = 0.2


func _env_value(n: String, delta: float) -> float:
	if not _env.has(n):
		return 0.0
	var e: Array = _env[n]
	e[0] += delta
	var t: float = e[0]
	var dur: float = e[1]
	if t >= dur:
		_env.erase(n)
		return 0.0
	var v := minf(smoothstep(0.0, e[2], t), 1.0 - smoothstep(dur - e[3], dur, t))
	return clampf(v, 0.0, 1.0)


func _ready_for(n: String) -> bool:
	return _cool.get(n, 0.0) <= 0.0


func _roll(chance: float) -> bool:
	return force_variations or _rng.randf() < chance
