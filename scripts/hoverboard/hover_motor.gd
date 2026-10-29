class_name HoverMotor
extends Node
## Hoverboard riding physics (kinematic, on the player's CharacterBody3D).
##
## Why kinematic instead of a RigidBody board: the rider and board share one body,
## so there is nothing to couple or keep from colliding, and every parameter maps
## directly to feel. Hovering is a raycast suspension: five probes (centre, nose,
## tail, left, right) measure the ground, and a one-sided spring-damper pushes the
## board toward `hover_height`. The spring can only push (plus a small "magnet"
## pull), so cresting a dune launches the board naturally instead of gluing it down.

signal jumped
signal landed(impact: float)
signal boost_changed(active: bool)
signal drift_changed(active: bool)
## Landed cleanly after spinning `spins` full turns in the air.
signal trick_landed(spins: float)
## Landed badly misaligned with the direction of travel.
signal bailed
## The held jump is fully charged (a big pop is ready).
signal charge_ready

@export_group("Hover")
## Height of the deck (rider's feet) above the ground.
@export var hover_height := 0.22
@export var spring_strength := 260.0
@export var spring_damping := 26.0
## Maximum downward pull of the suspension, as a fraction of gravity.
@export_range(0.0, 1.0) var magnet := 0.35
## Extra distance above hover_height where the suspension still holds the board.
@export var capture_range := 0.32
@export var min_clearance := 0.08
@export var probe_length := 0.9
@export var probe_width := 0.5
@export_flags_3d_physics var ground_mask := 5
@export var normal_smoothing := 9.0
@export_group("Ride")
@export var cruise_speed := 16.0
@export var acceleration := 6.5
@export var coast_deceleration := 1.0
@export var brake_deceleration := 18.0
## Per-second fraction of excess speed bled off above the current target speed.
@export var overspeed_drag := 0.55
@export var max_speed := 46.0
## How quickly sideways slip is removed (higher = more grip, less drift).
@export var grip := 5.5
## Fraction of removed slip converted into forward speed when carving.
@export_range(0.0, 1.0) var carve_transfer := 0.75
@export var turn_rate_slow := 2.8
@export var turn_rate_fast := 1.4
@export var steer_response := 7.0
## How strongly slopes accelerate the board downhill (1 = full gravity component).
@export var slope_gain := 1.3
@export_group("Drift")
## Minimum forward speed for a drift to start.
@export var drift_min_speed := 13.0
## Fraction of the maximum turn rate the player must request to start drifting.
@export_range(0.0, 1.0) var drift_steer_threshold := 0.8
## How long the sharp turn must be held before the board breaks into a drift.
@export var drift_entry_time := 0.18
@export var drift_grip := 1.3
@export var drift_turn_boost := 1.4
@export var drift_friction := 1.5
@export var drift_cooldown := 0.6
@export_group("Boost")
@export var boost_speed := 30.0
@export var boost_acceleration := 12.0
@export var boost_ramp_time := 0.35
@export_group("Air")
@export var gravity := 19.5
## Hold jump to crouch and charge, release to pop: tap = small hop, full charge = big air.
@export var jump_velocity_min := 7.0
@export var jump_velocity_max := 11.5
## Steering in the air also bends the flight path a little (rad/s), so a jump can be
## aimed; the board's own spin stays the trick input.
@export var air_steer := 0.7
## A release made this long before touchdown still jumps on landing (input buffer).
@export var jump_buffer := 0.16
@export var jump_charge_time := 0.6
@export_group("Air tricks")
## Left/right in the air spin the board by hand (rad/s); 0 = spins are tricks (Q).
@export var air_spin_rate := 0.0
## Short hops over ripples keep normal carving; spins start after this much airtime.
@export var air_spin_delay := 0.22
## Landing within this angle of the travel direction is clean; beyond it you bail.
@export var land_align_tolerance_deg := 60.0
## Without spin input, the board eases toward the nearest clean landing angle near the ground.
@export var landing_assist := 6.0
## Speed gained per half turn spun before a clean landing.
@export var spin_bonus := 1.6
## Fraction of speed kept after a bail.
@export_range(0.0, 1.0) var bail_speed_keep := 0.55
@export var jump_forward_bonus := 1.5
@export var coyote_time := 0.15
## Fraction of the into-ground velocity removed on landing (rest is kept by the spring).
@export_range(0.0, 1.0) var landing_absorb := 0.8

# State read by the visuals, camera and audio.
var heading_yaw := 0.0
var yaw_rate := 0.0
var boost_level := 0.0
var boosting := false
var supported := false
var ground_normal := Vector3.UP
var ground_point := Vector3.ZERO
var ground_distance := INF
var air_time := 0.0
var forward_speed := 0.0
var forward_accel := 0.0
var carve := 0.0
var drifting := false
## 0..1, smoothed; visuals and effects read this.
var drift_amount := 0.0
## +1 when sliding toward the board's right, -1 toward its left.
var drift_dir := 0.0
## Signed angle (rad) between where the board points and where it travels.
var slip_angle := 0.0
## 0..1 while holding jump on the ground (the rider crouches).
var jump_charge := 0.0
## Total yaw spun since leaving the ground (rad, signed).
var air_spin := 0.0

var _has_ground := false
var _raw_normal := Vector3.UP
var _jump_lock := 0.0
var _sharp_time := 0.0
var _drift_cd := 0.0
var _prev_jump_held := false
var _coyote := 0.0
var _release_buffer := 0.0
var _buffered_charge := 0.0
var _hop := 0.0
# Combat: a velocity change for the next tick, a dive speed, and lighter gravity for a while.
var _impulse := Vector3.ZERO
var _slam := 0.0
var _grav_scale := 1.0
## Combat: while she attacks, horizontal speed eases down to this (m/s; INF = free).
var speed_cap := INF
## How fast (m/s^2) the speed eases down to speed_cap.
@export var cap_brake := 30.0
var _grav_time := 0.0
var _hang_drag := 0.0
var _charge_announced := false
var _query := PhysicsRayQueryParameters3D.new()
const EARTH_G := 9.8


func enter(yaw: float) -> void:
	heading_yaw = yaw
	yaw_rate = 0.0
	boost_level = 0.0
	boosting = false
	supported = false
	air_time = 0.0
	_jump_lock = 0.0
	_coyote = 0.0
	ground_normal = Vector3.UP


func exit() -> void:
	if drifting:
		drifting = false
		drift_changed.emit(false)
	drift_amount = 0.0
	if boosting:
		boosting = false
		boost_changed.emit(false)
	boost_level = 0.0


func forward() -> Vector3:
	return Vector3(-sin(heading_yaw), 0.0, -cos(heading_yaw))


## A small pop on the next tick if the board is on the sand (deck tricks).
func request_hop(vy: float) -> void:
	_hop = maxf(_hop, vy)


## A velocity change applied on the next tick (combat: leaping off the sword, a dash).
## An upward part lifts her off the sand.
func impulse(dv: Vector3) -> void:
	_impulse += dv


## Dives toward the ground at least this fast (m/s, positive).
func slam(speed: float) -> void:
	_slam = maxf(_slam, speed)


## Gravity scaled by `scale` for `seconds` (a brief hang in the air), the horizontal
## motion slowed by `drag` (1/s) meanwhile.
func suspend(seconds: float, scale: float, drag := 0.0) -> void:
	_grav_time = maxf(_grav_time, seconds)
	_grav_scale = scale
	_hang_drag = drag


## Speed reward along the travel direction (clean trick landings).
func add_speed(dv: float, body: CharacterBody3D) -> void:
	var hv := Vector3(body.velocity.x, 0.0, body.velocity.z)
	if hv.length() < 1.0:
		return
	hv = (hv + hv.normalized() * dv).limit_length(max_speed)
	body.velocity = Vector3(hv.x, body.velocity.y, hv.z)


## A crash that is the rider's fault (a trick landed mid-rotation): lose speed.
func bail_now(body: CharacterBody3D) -> void:
	body.velocity = Vector3(body.velocity.x * bail_speed_keep, body.velocity.y, body.velocity.z * bail_speed_keep)
	bailed.emit()


func step(body: CharacterBody3D, input: PlayerInput, delta: float) -> void:
	_sense(body, delta)
	var v := body.velocity
	var air_before := air_time

	_jump_lock = maxf(_jump_lock - delta, 0.0)
	var was_supported := supported
	supported = _has_ground and ground_distance < hover_height + capture_range and _jump_lock <= 0.0
	if supported:
		_coyote = coyote_time
		air_time = 0.0
	else:
		_coyote -= delta
		air_time += delta

	# --- Boost ----------------------------------------------------------------
	if input.run_held != boosting:
		boosting = input.run_held
		boost_changed.emit(boosting)
	boost_level = move_toward(boost_level, 1.0 if boosting else 0.0, delta / boost_ramp_time)

	# --- Steering ---------------------------------------------------------------
	var hv := Vector3(v.x, 0.0, v.z)
	var f := hv.dot(forward())
	var max_rate := lerpf(turn_rate_slow, turn_rate_fast, clampf(f / boost_speed, 0.0, 1.0))
	max_rate *= lerpf(1.0, drift_turn_boost, drift_amount)
	# Board-relative carving, like a snowboard: left/right put the board on its edge,
	# forward pumps for speed, back digs the edge in (tighter turn) or brakes.
	var steer := -input.axes.x
	var dig := maxf(input.axes.y, 0.0)
	var target_rate := steer * max_rate * (1.0 + 0.35 * dig)
	var throttle := maxf(-input.axes.y, 0.0)
	var braking := dig > 0.5 and absf(steer) < 0.2
	if boosting:
		throttle = 1.0
		braking = false
	_update_drift(delta, f, target_rate, max_rate)
	if supported or air_time < air_spin_delay:
		# Grounded, or just skipping over a ripple: keep carving.
		yaw_rate = lerpf(yaw_rate, target_rate, 1.0 - exp(-steer_response * delta))
		if supported:
			air_spin = 0.0
	else:
		# In the air the board follows the flight path (steering bends the path, see
		# air_steer); spins are tricks (TrickDirector), drawn without turning the body,
		# so every landing faces the way she travels.
		var spin_target := steer * air_spin_rate
		var hv_now := Vector3(v.x, 0.0, v.z)
		if hv_now.length() > 2.0:
			var travel := atan2(-hv_now.x, -hv_now.z)
			var err := wrapf(travel - heading_yaw, -PI, PI)
			if absf(err) > PI * 0.5:
				err = wrapf(err + PI, -PI, PI)
			spin_target += clampf(err * landing_assist, -4.0, 4.0)
		yaw_rate = lerpf(yaw_rate, spin_target, 1.0 - exp(-10.0 * delta))
		air_spin += yaw_rate * delta
	heading_yaw = wrapf(heading_yaw + yaw_rate * delta, -PI, PI)

	# --- Horizontal motion --------------------------------------------------------
	var hv_air := hv
	var fwd := forward()
	f = hv.dot(fwd)
	var lat := hv - fwd * f
	var g := lerpf(grip, drift_grip, drift_amount)
	var keep := exp(-(g if supported else grip * 0.15) * delta)
	var lat_before := lat.length_squared()
	lat *= keep
	# Carving: part of the slip energy removed by grip is kept as forward speed
	# (energy-conserving, so turning never makes the board faster).
	var regained := (lat_before - lat.length_squared()) * carve_transfer
	f = signf(f) * sqrt(f * f + regained) if f != 0.0 else f

	var prev_f := forward_speed
	var target_speed := lerpf(cruise_speed, boost_speed, boost_level)
	var accel := lerpf(acceleration, boost_acceleration, boost_level)
	if supported:
		if braking:
			f = move_toward(f, 0.0, brake_deceleration * delta)
		elif throttle > 0.01:
			var t := target_speed * throttle
			if f < t:
				f = minf(f + accel * delta, t)
			else:
				f = move_toward(f, t, ((f - t) * overspeed_drag + 0.5) * delta)
		else:
			f = move_toward(f, 0.0, coast_deceleration * delta)
			if f > cruise_speed:
				f = move_toward(f, cruise_speed, (f - cruise_speed) * overspeed_drag * delta)
		if drift_amount > 0.0:
			f = move_toward(f, 0.0, drift_friction * drift_amount * delta)
		hv = fwd * f + lat
		# Gravity along the slope: downhill gains speed, uphill costs speed.
		hv += Vector3(ground_normal.x, 0.0, ground_normal.z) * EARTH_G * slope_gain * delta
	else:
		hv = hv_air * exp(-0.04 * delta)
		hv = hv.rotated(Vector3.UP, steer * air_steer * delta)
	hv = hv.limit_length(max_speed)
	forward_speed = hv.dot(fwd)
	forward_accel = lerpf(forward_accel, (forward_speed - prev_f) / delta, 1.0 - exp(-6.0 * delta))
	carve = clampf(yaw_rate * absf(forward_speed) / 28.0, -1.0, 1.0)
	if hv.length() > 2.0:
		slip_angle = fwd.signed_angle_to(hv.normalized(), Vector3.UP)
	var lateral := hv - fwd * hv.dot(fwd)
	drift_dir = signf(lateral.dot(fwd.cross(Vector3.UP).normalized())) if lateral.length() > 0.5 else drift_dir

	# --- Vertical: suspension, gravity, landing, jump --------------------------------
	var ground_vy := 0.0
	if _has_ground and _raw_normal.y > 0.2:
		# Unsmoothed normal here: the suspension must react to the ground it is about to hit.
		ground_vy = -(_raw_normal.x * hv.x + _raw_normal.z * hv.z) / _raw_normal.y
	var vy := v.y
	if supported:
		var target := hover_height + gravity / spring_strength
		var force := spring_strength * (target - ground_distance) - spring_damping * (vy - ground_vy)
		force = maxf(force, -gravity * magnet)
		vy += (force - gravity) * delta
		if not was_supported and air_before > 0.12:
			# Keep the velocity along the ground, absorb most of the into-ground part.
			var vel := hv + Vector3.UP * vy
			var into := vel.dot(ground_normal)
			if into < 0.0:
				vel -= ground_normal * into * landing_absorb
				hv = Vector3(vel.x, 0.0, vel.z)
				vy = vel.y
				landed.emit(-into)
				if air_before > 0.3:
					hv = _land_tricks(hv)
				else:
					air_spin = 0.0
	else:
		_grav_time = maxf(_grav_time - delta, 0.0)
		vy -= gravity * delta * (_grav_scale if _grav_time > 0.0 else 1.0)
		if _grav_time > 0.0 and _hang_drag > 0.0:
			hv *= exp(-_hang_drag * delta)
	# Combat impulses and dives.
	if _impulse != Vector3.ZERO:
		hv += Vector3(_impulse.x, 0.0, _impulse.z)
		hv = hv.limit_length(max_speed)
		if _impulse.y > 0.0:
			vy = maxf(vy, 0.0) + _impulse.y
			_jump_lock = maxf(_jump_lock, 0.25)
			_coyote = 0.0
			supported = false
		else:
			vy += _impulse.y
		_impulse = Vector3.ZERO
	if speed_cap < INF:
		var hl := hv.length()
		if hl > speed_cap:
			hv *= move_toward(hl, speed_cap, cap_brake * delta) / hl
	if _slam > 0.0:
		vy = minf(vy, -_slam)
		_slam = 0.0
	# Predictive floor: never let the next step bring the deck closer than min_clearance,
	# even when falling fast (one tick at 25 m/s is ~0.4 m).
	if _has_ground and ground_distance < 50.0:
		var next_gap := ground_distance + (vy - ground_vy) * delta
		if next_gap < min_clearance:
			if ground_distance >= min_clearance:
				vy = ground_vy + (min_clearance - ground_distance) / delta
			else:
				# Already low (e.g. just summoned on the sand): stop sinking, let the spring lift.
				vy = maxf(vy, ground_vy)

	var released := _prev_jump_held and not input.jump_held
	_prev_jump_held = input.jump_held
	# Charging also works in the last moments of a fall, so the pop is ready on touchdown.
	var near := _coyote > 0.0 or (ground_distance < hover_height + 1.2 and v.y < 0.0)
	if input.jump_held and near:
		var was := jump_charge
		jump_charge = minf(jump_charge + delta / jump_charge_time, 1.0)
		if jump_charge >= 1.0 and was < 1.0 and not _charge_announced:
			_charge_announced = true
			charge_ready.emit()
	elif not released:
		jump_charge = move_toward(jump_charge, 0.0, delta * 4.0)
	if not input.jump_held and jump_charge <= 0.0:
		_charge_announced = false
	# Input buffer: a release just before touchdown jumps as soon as the board lands.
	_release_buffer = maxf(_release_buffer - delta, 0.0)
	if released and _coyote <= 0.0:
		_release_buffer = jump_buffer
		_buffered_charge = jump_charge
	var buffered := _release_buffer > 0.0 and _coyote > 0.0
	if (released or buffered) and _coyote > 0.0 and _jump_lock <= 0.0:
		var charge := _buffered_charge if buffered and not released else jump_charge
		vy = maxf(vy, 0.0) + lerpf(jump_velocity_min, jump_velocity_max, charge)
		hv += fwd * jump_forward_bonus
		_jump_lock = 0.3
		_coyote = 0.0
		jump_charge = 0.0
		_release_buffer = 0.0
		_charge_announced = false
		supported = false
		air_spin = 0.0
		jumped.emit()
	elif _hop > 0.0 and supported and _jump_lock <= 0.0:
		# Deck-trick pop: a small, uncharged hop.
		vy = maxf(vy, 0.0) + _hop
		_jump_lock = 0.25
		_coyote = 0.0
		supported = false
		air_spin = 0.0
	_hop = 0.0

	body.velocity = Vector3(hv.x, vy, hv.z)


## Clean landing (board within tolerance of the travel direction, forwards or fakie)
## realigns the board and rewards spins with speed; a misaligned landing bails.
func _land_tricks(hv: Vector3) -> Vector3:
	var spins := absf(air_spin) / TAU
	air_spin = 0.0
	if hv.length() < 2.0:
		return hv
	var travel_yaw := atan2(-hv.x, -hv.z)
	var mis := absf(wrapf(travel_yaw - heading_yaw, -PI, PI))
	if mis > PI * 0.5:
		mis = PI - mis
	heading_yaw = travel_yaw
	yaw_rate = 0.0
	if mis <= deg_to_rad(land_align_tolerance_deg):
		var half_turns := roundf(spins * 2.0)
		if half_turns >= 1.0:
			hv += hv.normalized() * spin_bonus * half_turns
			trick_landed.emit(half_turns * 0.5)
		return hv
	bailed.emit()
	return hv * bail_speed_keep


## Enters a drift on a sharp, sustained turn at speed; exits when the turn eases.
func _update_drift(delta: float, f: float, target_rate: float, max_rate: float) -> void:
	_drift_cd = maxf(_drift_cd - delta, 0.0)
	# Short hops off ripples and crests don't break a sustained sharp turn.
	var sharp := (supported or air_time < 0.15) and f > drift_min_speed and absf(target_rate) >= max_rate * drift_steer_threshold
	_sharp_time = _sharp_time + delta if sharp else 0.0
	if not drifting and _sharp_time >= drift_entry_time and _drift_cd <= 0.0:
		drifting = true
		drift_changed.emit(true)
	elif drifting and (absf(target_rate) < max_rate * 0.35 or f < drift_min_speed * 0.7 or air_time > 0.3):
		drifting = false
		_drift_cd = drift_cooldown
		drift_changed.emit(false)
	drift_amount = move_toward(drift_amount, 1.0 if drifting else 0.0, delta * (5.0 if drifting else 2.5))


func _sense(body: CharacterBody3D, delta: float) -> void:
	var space := body.get_world_3d().direct_space_state
	var feet := body.global_position
	var yaw_basis := Basis(Vector3.UP, heading_yaw)
	var f := yaw_basis * Vector3(0.0, 0.0, -probe_length)
	var r := yaw_basis * Vector3(probe_width, 0.0, 0.0)
	var up := 1.0
	var reach := up + hover_height + capture_range + 2.5
	_query.collision_mask = ground_mask
	_query.exclude = [body.get_rid()]

	var offsets: Array[Vector3] = [Vector3.ZERO, f, -f, r, -r]
	var hit_y: Array[float] = []
	var ok: Array[bool] = []
	var center_normal := Vector3.UP
	for i in offsets.size():
		_query.from = feet + offsets[i] + Vector3.UP * up
		_query.to = _query.from + Vector3.DOWN * reach
		var hit := space.intersect_ray(_query)
		if hit.is_empty():
			ok.append(false)
			hit_y.append(0.0)
		else:
			var p: Vector3 = hit["position"]
			ok.append(true)
			hit_y.append(p.y)
			if i == 0:
				center_normal = hit["normal"]
	var count := 0
	var sum := 0.0
	for i in ok.size():
		if ok[i]:
			count += 1
			sum += hit_y[i]
	_has_ground = count > 0
	if not _has_ground:
		ground_distance = INF
		return
	# Use the higher of centre and average so the nose/tail never dig in at troughs.
	var ground_y := sum / count
	if ok[0]:
		ground_y = maxf(ground_y, hit_y[0])
	ground_distance = feet.y - ground_y
	ground_point = Vector3(feet.x, ground_y, feet.z)

	var n := center_normal
	if ok[1] and ok[2] and ok[3] and ok[4]:
		var nose := feet + f
		nose.y = hit_y[1]
		var tail := feet - f
		tail.y = hit_y[2]
		var right := feet + r
		right.y = hit_y[3]
		var left := feet - r
		left.y = hit_y[4]
		n = (right - left).cross(nose - tail).normalized()
	if n.y < 0.3:
		n = Vector3.UP
	_raw_normal = n
	ground_normal = ground_normal.slerp(n, 1.0 - exp(-normal_smoothing * delta)).normalized()
