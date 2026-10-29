class_name FollowCamera
extends Node3D
## Third-person orbit camera: the only script that moves the camera.
##
## Stability by design (these were the sources of the old high-speed shake):
##  * no continuous noise shake; only a small, decaying kick on hard landings,
##  * the pivot follows the interpolated body through critically damped springs,
##    softer vertically while riding so hover-spring motion never reaches the view,
##  * collision is a sphere cast against props only; terrain is handled analytically
##    by lifting the camera over dunes with asymmetric smoothing, instead of a ray that
##    pumped the distance whenever it grazed a dune,
##  * speed and travel direction are estimated at render rate from the interpolated
##    position, so auto-alignment and FOV never step at the physics tick rate.
## Riding framing follows the reference surfing games: a wide, high view that shows the
## sand ahead; the camera eases back when the board accelerates (and returns as speed
## settles), backs off a little in big air so tricks stay in frame, widens its field of
## view with speed, and draws speed lines at the screen's edge while boosting.

@export var target_path: NodePath
@export var terrain_path: NodePath
@export_group("Control")
@export var mouse_sensitivity := 0.0022
@export var stick_sensitivity := 2.6
@export var invert_y := false
@export_range(-89.0, 0.0) var pitch_min_deg := -65.0
@export_range(0.0, 89.0) var pitch_max_deg := 35.0
@export_group("Framing")
@export var distance := 5.4
@export var min_distance := 1.8
@export var max_distance := 10.0
@export var zoom_step := 0.5
@export var ride_extra_distance := 0.9
@export var speed_extra_distance := 1.2
## Extra distance per m/s^2 of forward acceleration (the camera lags a boost, then
## catches up), and while airborne (tricks stay in frame).
@export var accel_lag := 0.06
@export var air_extra_distance := 0.3
@export var pivot_height := 1.35
@export var ride_pivot_height := 1.25
@export var default_pitch_deg := -13.0
## Moves the camera up without rotating it, so the character sits a little low in frame.
@export var vertical_offset := 0.25
@export_group("Smoothing")
## Seconds for the pivot to catch up horizontally (critically damped).
@export var horizontal_smooth_time := 0.05
@export var vertical_smooth_time := 0.12
@export var ride_vertical_smooth_time := 0.22
@export var zoom_sharpness := 4.0
@export_group("FOV")
@export var base_fov := 70.0
@export var speed_fov := 7.0
@export var boost_fov := 12.0
@export var fov_sharpness := 2.5
@export_group("Ride auto-align")
@export var recenter_delay := 0.35
@export var recenter_sharpness := 2.4
@export var ride_pitch_deg := -11.0
@export_group("Speed lines")
## Speed (m/s) where the edge streaks begin and where they are full.
@export var speed_lines_range := Vector2(24.0, 32.0)
@export_group("Landing kick")
@export var landing_kick := 0.05
@export_group("Collision")
@export_flags_3d_physics var collision_mask := 4
@export var collision_radius := 0.25
@export var terrain_clearance := 0.5

var yaw := 0.0
var pitch := 0.0

@onready var camera: Camera3D = $Camera3D

var _target: PlayerController
var _terrain: DuneTerrain
var _pivot := Vector3.ZERO
var _sd_vel := [0.0, 0.0, 0.0]
var _distance := 4.2
var _zoom := 4.2
var _idle_look := 0.0
var _lift := 0.0
var _kick := 0.0
var _kick_vel := 0.0
var _last_feet := Vector3.ZERO
var _vel := Vector3.ZERO
var _lag := 0.0
# Combat: a short, restrained shake on heavy impacts and a slight pull-back (with a
# wider view) while a heavy strike winds up.
var _shake := 0.0
var _anticipate := 0.0
var _anticipate_target := 0.0
var _time := 0.0
# Brief, gentle widening of the view after a clean trick landing (no shake).
var _punch := 0.0
var _air_back := 0.0
# Combat framing: drawn in toward the sentinel being fought, a lean into whirling moves,
# a quick push-in on big blows.
var _focus := Vector3.ZERO
var _focus_w := 0.0
var _focus_target := 0.0
var _roll := 0.0
var _roll_target := 0.0
var _zoom_punch := 0.0
var _fov := 70.0
var _lines := ColorRect.new()
var _lines_mat := ShaderMaterial.new()
var _sphere := SphereShape3D.new()
var _shape_query := PhysicsShapeQueryParameters3D.new()


func _ready() -> void:
	_target = get_node_or_null(target_path) as PlayerController
	_terrain = get_node_or_null(terrain_path) as DuneTerrain
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	top_level = true
	global_transform = Transform3D.IDENTITY
	pitch = deg_to_rad(default_pitch_deg)
	_zoom = distance
	_distance = distance
	_sphere.radius = collision_radius
	_shape_query.shape = _sphere
	camera.fov = base_fov
	_fov = base_fov
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	_lines_mat.shader = load("res://shaders/speed_lines.gdshader")
	_lines.material = _lines_mat
	_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_lines)
	if _target:
		_target.landed.connect(_on_landed)
		var visual := _target.get_node_or_null("Visual") as PlayerVisual
		if visual:
			visual.tricks.landed.connect(func(clean: bool, had: bool) -> void:
				if clean and had:
					_punch = clampf(0.5 + 0.15 * visual.tricks.combo.multiplier, 0.5, 1.2))
		_target.respawned.connect(snap)
		snap()


## Instantly places the camera behind the target (after teleports).
func snap() -> void:
	if _target == null:
		return
	yaw = _target.facing_yaw
	pitch = deg_to_rad(default_pitch_deg)
	_last_feet = _target.global_position
	_pivot = _last_feet + Vector3.UP * pivot_height
	_sd_vel = [0.0, 0.0, 0.0]
	_vel = Vector3.ZERO
	_lift = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var m := event as InputEventMouseMotion
		yaw -= m.relative.x * mouse_sensitivity
		pitch -= m.relative.y * mouse_sensitivity * (-1.0 if invert_y else 1.0)
		pitch = clampf(pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
		_idle_look = 0.0
	elif event is InputEventMouseButton and event.pressed:
		var b := event as InputEventMouseButton
		if b.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = maxf(_zoom - zoom_step, min_distance)
		elif b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = minf(_zoom + zoom_step, max_distance)


func _process(delta: float) -> void:
	if _target == null or delta <= 0.0:
		return
	_idle_look += delta
	var stick := Input.get_vector(&"camera_left", &"camera_right", &"camera_up", &"camera_down")
	if stick.length() > 0.01:
		yaw -= stick.x * stick_sensitivity * delta
		pitch = clampf(pitch - stick.y * stick_sensitivity * 0.7 * delta * (-1.0 if invert_y else 1.0),
				deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
		_idle_look = 0.0

	var riding := _target.mode == PlayerController.Mode.RIDE
	var feet := _target.get_global_transform_interpolated().origin
	if feet.distance_to(_last_feet) > 20.0:
		snap()
	# Render-rate velocity estimate from the interpolated position.
	var raw_vel := (feet - _last_feet) / delta
	_vel = _vel.lerp(raw_vel, 1.0 - exp(-6.0 * delta))
	_last_feet = feet
	var speed := Vector2(_vel.x, _vel.z).length()
	var speed01 := clampf(speed / _target.hover.cruise_speed, 0.0, 1.5)

	if riding and _idle_look > recenter_delay and speed > 5.0:
		var travel_yaw := atan2(-_vel.x, -_vel.z)
		var k := 1.0 - exp(-recenter_sharpness * clampf(speed / 15.0, 0.3, 1.5) * delta)
		yaw = lerp_angle(yaw, travel_yaw, k)
		pitch = lerpf(pitch, deg_to_rad(ride_pitch_deg), k * 0.5)

	# Pivot: critically damped follow; softer vertically while riding.
	var goal := feet + Vector3.UP * (ride_pivot_height if riding else pivot_height)
	_focus_w = lerpf(_focus_w, _focus_target, 1.0 - exp(-(3.0 if _focus_target > _focus_w else 1.5) * delta))
	if _focus_w > 0.001:
		goal = goal.lerp(goal.lerp(_focus, 0.5), 0.6 * _focus_w)
	var vt := ride_vertical_smooth_time if riding else vertical_smooth_time
	_pivot = Vector3(
			_smooth_damp(_pivot.x, goal.x, 0, horizontal_smooth_time, delta),
			_smooth_damp(_pivot.y, goal.y, 1, vt, delta),
			_smooth_damp(_pivot.z, goal.z, 2, horizontal_smooth_time, delta))

	# Landing kick: small decaying dip, the only "shake".
	var acc := -90.0 * _kick - 13.0 * _kick_vel
	_kick_vel += acc * delta
	_kick += _kick_vel * delta

	# Ease back while the board accelerates and in big air; return as it settles.
	var hm := _target.hover
	var lag_target := clampf(hm.forward_accel * accel_lag, -0.4, 1.2) if riding else 0.0
	_lag = lerpf(_lag, lag_target, 1.0 - exp(-2.0 * delta))
	var air := riding and not hm.supported and hm.air_time > 0.25
	_air_back = lerpf(_air_back, air_extra_distance if air else 0.0, 1.0 - exp(-(2.5 if air else 1.5) * delta))
	_anticipate = lerpf(_anticipate, _anticipate_target, 1.0 - exp(-(5.0 if _anticipate_target > _anticipate else 2.5) * delta))
	var want := _zoom + (ride_extra_distance if riding else 0.0) + speed_extra_distance * clampf(speed01, 0.0, 1.0) + _lag + _air_back + 0.7 * _anticipate - 0.9 * _focus_w
	var rot := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var dir := rot * Vector3(0.0, 0.0, 1.0)

	# Props (stones): sphere cast, pull in fast, ease back out.
	var allowed := want
	_shape_query.transform = Transform3D(Basis.IDENTITY, _pivot)
	_shape_query.motion = dir * want
	_shape_query.collision_mask = collision_mask
	_shape_query.exclude = [_target.get_rid()]
	var frac := get_world_3d().direct_space_state.cast_motion(_shape_query)
	if frac.size() == 2 and frac[0] < 1.0:
		allowed = maxf(want * frac[0], 0.6)
	var zk := 18.0 if allowed < _distance else zoom_sharpness
	_distance = lerpf(_distance, allowed, 1.0 - exp(-zk * delta))
	var pos := _pivot + dir * _distance

	# Terrain: lift the camera so the view line clears any dune between it and the pivot.
	var need := 0.0
	if _terrain:
		for i in range(2, 6):
			var t := float(i) / 5.0
			var sp := _pivot.lerp(pos, t)
			var ground := _terrain.height_at(sp.x, sp.z) + terrain_clearance * t
			if ground > sp.y:
				need = maxf(need, (ground - sp.y) / t)
	_lift = lerpf(_lift, need, 1.0 - exp(-(10.0 if need > _lift else 2.0) * delta))
	pos.y += _lift

	var look := Basis.looking_at(_pivot - pos, Vector3.UP) if pos.distance_to(_pivot) > 0.05 else rot
	_roll = lerpf(_roll, _roll_target, 1.0 - exp(-4.0 * delta))
	look = look * Basis(Vector3.BACK, _roll)
	_time += delta
	_shake = move_toward(_shake, 0.0, delta * 3.5)
	var jolt := Vector3(sin(_time * 61.0), sin(_time * 47.0 + 1.3), sin(_time * 53.0 + 2.1)) * 0.07 * _shake * _shake
	camera.global_transform = Transform3D(look, pos + Vector3.UP * _kick + jolt)
	camera.v_offset = vertical_offset

	var boost := _target.hover.boost_level if riding else 0.0
	_punch = move_toward(_punch, 0.0, delta * 1.8)
	var fov := base_fov + speed_fov * clampf(speed01, 0.0, 1.0) + boost_fov * boost + 3.5 * _punch + 4.0 * _anticipate
	_fov = lerpf(_fov, fov, 1.0 - exp(-fov_sharpness * delta))
	_zoom_punch = move_toward(_zoom_punch, 0.0, delta * 2.5)
	camera.fov = _fov - 9.0 * _zoom_punch * (2.0 - _zoom_punch)
	var lines := smoothstep(speed_lines_range.x, speed_lines_range.y, speed) if riding else 0.0
	_lines_mat.set_shader_parameter("intensity", lines)
	_lines.visible = lines > 0.01


## A brief, small shake (0..1); it dies away in a fraction of a second.
func shake(strength: float) -> void:
	_shake = maxf(_shake, clampf(strength, 0.0, 1.0))


## Combat framing: draws in and shifts the view toward `point` (weight 0..1, 0 lets go).
func focus(point: Vector3, weight: float) -> void:
	if weight > 0.0:
		_focus = point
	_focus_target = clampf(weight, 0.0, 1.0)


## A slight roll of the view (rad) for whirling moves (0 levels it).
func tilt(amount: float) -> void:
	_roll_target = amount


## A quick push-in of the view on a big blow (0..1).
func zoom_punch(amount: float) -> void:
	_zoom_punch = maxf(_zoom_punch, clampf(amount, 0.0, 1.0))


## Holds a slight pull-back while a heavy strike winds up (0 releases it).
func anticipate(amount: float) -> void:
	_anticipate_target = clampf(amount, 0.0, 1.0)


## Critically damped spring toward `target` (the classic "SmoothDamp").
func _smooth_damp(current: float, target: float, axis: int, smooth_time: float, dt: float) -> float:
	var st := maxf(smooth_time, 0.0001)
	var omega := 2.0 / st
	var x := omega * dt
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := current - target
	var v: float = _sd_vel[axis]
	var temp := (v + omega * change) * dt
	v = (v - omega * temp) * e
	_sd_vel[axis] = v
	return target + (change + temp) * e


func _on_landed(impact: float, _on_board: bool) -> void:
	_kick_vel -= clampf(impact / 15.0, 0.0, 1.0) * landing_kick * 12.0
