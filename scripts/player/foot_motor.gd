class_name FootMotor
extends Node
## On-foot locomotion: walk, run, sprint, jump and a magical dash.
## Only computes the body's velocity; PlayerController calls move_and_slide().
##
## Movement keys run by default; Shift sprints; Alt (or a half-tilted stick) walks.
## Direction changes rotate the velocity vector instead of braking through zero, so
## turns keep their momentum. The dash is instant, eases out into a run/sprint, and
## can be cancelled into a jump, so actions chain naturally.

signal jumped
signal dodged(direction: Vector3)

@export_group("Speed")
@export var walk_speed := 1.3
@export var run_speed := 4.5
@export var sprint_speed := 6.5
@export var acceleration := 28.0
@export var sprint_acceleration := 14.0
@export var deceleration := 30.0
## How fast the velocity direction follows the input (rad/s) while keeping speed.
@export var turn_rate := 11.0
## Above this angle (degrees) between velocity and input, brake and pivot instead of arcing.
@export var pivot_angle := 120.0
@export var air_acceleration := 10.0
@export var gait_blend_time := 0.25
@export_group("Jump")
@export var jump_velocity := 6.8
@export var gravity := 21.0
@export var fall_gravity_multiplier := 1.4
## Vertical speed is multiplied by this when Space is released early (variable jump).
@export var jump_cut := 0.5
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.14
@export var max_fall_speed := 35.0
@export_group("Dash")
@export var dodge_speed := 15.0
@export var dodge_duration := 0.22
## Fraction of the dash spent at full burst speed before easing out.
@export_range(0.0, 0.9) var dodge_hold := 0.35
## Time from one dash start until the next is allowed (no long animation lock).
@export var dodge_cooldown := 0.38
@export var air_dodge_lift := 1.5
@export_range(0.0, 1.0) var dodge_air_gravity := 0.15

var run_blend := 0.0
var dodge_timer := 0.0
var dodge_direction := Vector3.FORWARD

var _cooldown := 0.0
var _coyote := 0.0
var _buffer := 0.0
var _air_dodge_used := false
var _jump_rising := false
var _speed_target := 0.0


## Fraction of the dash already played (0 at start, 1 when finished or idle).
var dodge_progress: float:
	get:
		return 1.0 - clampf(dodge_timer / dodge_duration, 0.0, 1.0)


func reset() -> void:
	dodge_timer = 0.0
	_cooldown = 0.0
	_buffer = 0.0
	_coyote = 0.0
	_jump_rising = false


func step(body: CharacterBody3D, input: PlayerInput, facing: Vector3, delta: float) -> void:
	var v := body.velocity
	var on_floor := body.is_on_floor()
	_cooldown -= delta
	if on_floor:
		_coyote = coyote_time
		_air_dodge_used = false
	else:
		_coyote -= delta
	_buffer = jump_buffer_time if input.jump_pressed else _buffer - delta

	var stick := minf(input.move.length(), 1.0)
	var walking := Input.is_action_pressed(&"walk") or (stick > 0.1 and stick < 0.55)
	var gait_speed := walk_speed if walking else run_speed
	if input.run_held and stick > 0.1:
		gait_speed = sprint_speed
	_speed_target = move_toward(_speed_target, gait_speed if stick > 0.1 else 0.0,
			(sprint_speed - walk_speed) / gait_blend_time * delta)
	run_blend = clampf((_speed_target - run_speed) / (sprint_speed - run_speed), 0.0, 1.0)

	var hv := Vector3(v.x, 0.0, v.z)
	var wish := input.move_world.normalized() if stick > 0.1 else Vector3.ZERO

	if input.dodge_pressed and _cooldown <= 0.0 and (on_floor or not _air_dodge_used):
		dodge_direction = wish if stick > 0.1 else facing
		dodge_timer = dodge_duration
		_cooldown = dodge_cooldown
		if not on_floor:
			_air_dodge_used = true
			v.y = maxf(v.y, air_dodge_lift)
		dodged.emit(dodge_direction)

	if dodge_timer > 0.0:
		dodge_timer -= delta
		# Ease out of the burst straight into the current gait speed (or keep sprinting).
		var t := dodge_progress
		var exit_speed := maxf(_speed_target, run_speed * 0.8)
		# Hold the burst briefly, then ease smoothly into the exit speed.
		var eased := smoothstep(dodge_hold, 1.0, t)
		hv = dodge_direction * lerpf(dodge_speed, exit_speed, eased)
		if stick > 0.1:
			# Slight steering during the dash.
			dodge_direction = dodge_direction.slerp(wish, 1.0 - exp(-3.0 * delta)).normalized()
	elif not on_floor:
		hv = hv.move_toward(wish * maxf(_speed_target, hv.length() * 0.98), air_acceleration * delta)
	elif stick > 0.1:
		hv = _ground_steer(hv, wish, _speed_target, delta)
	else:
		hv = hv.move_toward(Vector3.ZERO, deceleration * delta)

	if not on_floor:
		var g := gravity
		if v.y < 0.0:
			g *= fall_gravity_multiplier
		if dodge_timer > 0.0:
			g *= dodge_air_gravity
		v.y = maxf(v.y - g * delta, -max_fall_speed)

	if _buffer > 0.0 and _coyote > 0.0:
		v.y = jump_velocity
		_buffer = 0.0
		_coyote = 0.0
		_jump_rising = true
		if dodge_timer > 0.0:
			# Dash-jump: keep the dash momentum, end the dash.
			dodge_timer = 0.0
		jumped.emit()
	if _jump_rising and not input.jump_held and v.y > 0.0:
		v.y *= jump_cut
		_jump_rising = false
	if v.y <= 0.0:
		_jump_rising = false

	body.velocity = Vector3(hv.x, v.y, hv.z)


## Rotates the velocity toward the wished direction while easing its magnitude, so
## turns arc with momentum; very sharp reversals brake and pivot instead.
func _ground_steer(hv: Vector3, wish: Vector3, target_speed: float, delta: float) -> Vector3:
	var spd := hv.length()
	if spd < 0.5:
		return wish * move_toward(spd, target_speed, acceleration * delta)
	var dir := hv / spd
	var angle := dir.angle_to(wish)
	if angle > deg_to_rad(pivot_angle):
		return hv.move_toward(wish * target_speed, (deceleration + acceleration) * delta)
	var turn_step := minf(angle, turn_rate * delta)
	var axis := dir.cross(wish)
	if axis.length_squared() > 0.000001:
		dir = dir.rotated(axis.normalized(), turn_step)
	var accel := acceleration if target_speed <= run_speed or spd < run_speed else sprint_acceleration
	if spd > target_speed:
		accel = deceleration
	# Sharper turns bleed a little speed, like planting a foot.
	var turn_loss := 1.0 - clampf(angle / PI, 0.0, 1.0) * 0.25
	return dir * move_toward(spd, target_speed * turn_loss, accel * delta)
