class_name PlayerController
extends CharacterBody3D
## Owns the player's physics body and mode. Solace travels on her floating sword
## (RIDE, driven by HoverMotor): she summons it and mounts at the start and never walks.
## The on-foot mode (FootMotor) only exists for inspection tools (`foot_enabled`).
## Input is read once per tick, the active motor computes velocity, then the body
## moves. Presentation lives in PlayerVisual and reacts to the signals below.
## The body's origin is at the feet.

enum Mode { FOOT, RIDE }

signal mode_changed(mode: Mode)
signal jumped(on_board: bool)
signal landed(impact: float, on_board: bool)
signal dodged(direction: Vector3)
signal boost_changed(active: bool)
signal respawned

@export var camera_rig_path: NodePath
## Walking / running and the summon toggle. Off in the game: the sword is the only way
## to travel. Tools that inspect the on-foot animation turn it on.
@export var foot_enabled := false
## Seconds after the start (past the fade-in) before she summons the sword and mounts.
@export var mount_delay := 1.1
@export var terrain_path: NodePath
@export_group("Board")
## Minimum time between summon/dismiss presses, so transitions can't stack.
@export var board_toggle_cooldown := 0.45
## Small upward hop when stepping off a hovering board.
@export var dismiss_hop := 2.0
## Horizontal speed is capped to this when leaving the board, so you don't fly off.
@export var dismiss_speed_limit := 10.0
@export_group("Facing")
@export var turn_speed := 14.0
@export_group("Play area")
## Half-size of the region the player is softly kept inside (world units from origin).
@export var play_half_extent := 600.0
@export var soft_boundary_width := 80.0
@export var boundary_strength := 14.0
@export_group("Floor")
@export var foot_snap_length := 0.5
@export_group("Collider")
@export var foot_capsule := Vector2(0.22, 1.42)
## Radius and height while riding; its bottom sits `ride_capsule_lift` above the deck.
@export var ride_capsule := Vector2(0.18, 1.1)
@export var ride_capsule_lift := 0.4
@export_range(0.0, 89.0) var max_slope_deg := 52.0

@onready var foot: FootMotor = $FootMotor
@onready var hover: HoverMotor = $HoverMotor
@onready var _collider: CollisionShape3D = $CollisionShape3D

var mode := Mode.FOOT
var facing_yaw := 0.0
var input := PlayerInput.new()
var input_enabled := true
var grounded := true
var landing_impact := 0.0

var _camera_rig: Node3D
var _terrain: DuneTerrain
var _toggle_cd := 0.0
var _was_on_floor := true
var _prev_vy := 0.0
var _spawn := Vector3.ZERO
var _mount_timer := 0.0


func _ready() -> void:
	_camera_rig = get_node_or_null(camera_rig_path) as Node3D
	_terrain = get_node_or_null(terrain_path) as DuneTerrain
	floor_max_angle = deg_to_rad(max_slope_deg)
	floor_snap_length = foot_snap_length
	floor_constant_speed = true
	floor_block_on_wall = true
	foot.jumped.connect(func() -> void: jumped.emit(false))
	foot.dodged.connect(func(dir: Vector3) -> void: dodged.emit(dir))
	hover.jumped.connect(func() -> void: jumped.emit(true))
	hover.landed.connect(func(impact: float) -> void: landed.emit(impact, true))
	hover.boost_changed.connect(func(active: bool) -> void: boost_changed.emit(active))
	_spawn = global_position
	place_on_ground(global_position)
	if not foot_enabled:
		_mount_timer = mount_delay


## Puts the player on the terrain surface at the given XZ position.
func place_on_ground(at: Vector3) -> void:
	var y := at.y
	if _terrain:
		y = _terrain.height_at(at.x, at.z) + 0.05
	global_position = Vector3(at.x, y, at.z)
	velocity = Vector3.ZERO
	reset_physics_interpolation()


## Turns on walking / running (inspection tools only) and steps off the sword.
func enable_foot() -> void:
	foot_enabled = true
	if mode == Mode.RIDE:
		_toggle_board()
		place_on_ground(global_position)


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func facing_direction() -> Vector3:
	return Vector3(-sin(facing_yaw), 0.0, -cos(facing_yaw))


func _physics_process(delta: float) -> void:
	var cam_yaw := facing_yaw
	if _camera_rig and "yaw" in _camera_rig:
		cam_yaw = _camera_rig.get("yaw")
	input.read(cam_yaw, input_enabled and _mount_timer <= 0.0)
	if _mount_timer > 0.0:
		_mount_timer -= delta
		if _mount_timer <= 0.0 and not foot_enabled and mode == Mode.FOOT:
			_toggle_board()

	if input_enabled and Input.is_action_just_pressed(&"respawn"):
		respawn()
		return

	_toggle_cd -= delta
	if foot_enabled and input.board_pressed and _toggle_cd <= 0.0 and foot.dodge_timer <= 0.0:
		_toggle_board()

	_was_on_floor = is_on_floor()
	match mode:
		Mode.FOOT:
			foot.step(self, input, facing_direction(), delta)
		Mode.RIDE:
			hover.step(self, input, delta)
	_apply_boundary(delta)
	_prev_vy = velocity.y
	move_and_slide()

	if mode == Mode.FOOT:
		grounded = is_on_floor()
		if grounded and not _was_on_floor:
			landing_impact = maxf(0.0, -_prev_vy)
			landed.emit(landing_impact, false)
	else:
		grounded = hover.supported

	_update_facing(delta)
	_check_fell_out()


func _update_facing(delta: float) -> void:
	if mode == Mode.RIDE:
		facing_yaw = hover.heading_yaw
		return
	var dir := Vector3.ZERO
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	if foot.dodge_timer > 0.0:
		dir = foot.dodge_direction
	elif input.move_world.length() > 0.1:
		# Face mostly where we are actually going, nudged toward the input so turns read early.
		dir = input.move_world.normalized()
		if hv.length() > 1.0:
			dir = hv.normalized().lerp(dir, 0.35)
	if dir.length_squared() > 0.0001:
		var target := atan2(-dir.x, -dir.z)
		var rate := turn_speed * (2.0 if foot.dodge_timer > 0.0 else 1.0)
		facing_yaw = lerp_angle(facing_yaw, target, 1.0 - exp(-rate * delta))


func _toggle_board() -> void:
	_toggle_cd = board_toggle_cooldown
	if mode == Mode.FOOT:
		mode = Mode.RIDE
		floor_snap_length = 0.0
		_set_capsule(ride_capsule, ride_capsule_lift)
		hover.enter(facing_yaw)
		mode_changed.emit(mode)
	else:
		hover.exit()
		mode = Mode.FOOT
		floor_snap_length = foot_snap_length
		_set_capsule(foot_capsule, 0.0)
		foot.reset()
		var hv := Vector3(velocity.x, 0.0, velocity.z).limit_length(dismiss_speed_limit)
		var vy := velocity.y
		if hover.supported:
			vy = maxf(vy, 0.0) + dismiss_hop
		velocity = Vector3(hv.x, vy, hv.z)
		mode_changed.emit(mode)


func _set_capsule(size: Vector2, lift: float) -> void:
	var cap := _collider.shape as CapsuleShape3D
	cap.radius = size.x
	cap.height = size.y
	_collider.position = Vector3(0.0, lift + size.y * 0.5, 0.0)


func _apply_boundary(delta: float) -> void:
	var p := global_position
	var inner := play_half_extent - soft_boundary_width
	var push := Vector3.ZERO
	if absf(p.x) > inner:
		push.x = -signf(p.x) * (absf(p.x) - inner) / soft_boundary_width
	if absf(p.z) > inner:
		push.z = -signf(p.z) * (absf(p.z) - inner) / soft_boundary_width
	if push == Vector3.ZERO:
		return
	var out_dir := -push.normalized()
	var outward := velocity.dot(out_dir)
	if outward > 0.0:
		# Bleed off outward speed progressively, like wading into a headwind.
		velocity -= out_dir * outward * (1.0 - exp(-push.length() * 3.0 * delta))
	velocity += push * boundary_strength * delta


func _check_fell_out() -> void:
	if _terrain == null:
		return
	var p := global_position
	if p.y < _terrain.height_at(p.x, p.z) - 4.0 or not _terrain.is_inside(p.x, p.z, 2.0):
		push_warning("Player left the terrain at %s; recovering." % p)
		var safe := p.clamp(Vector3(-play_half_extent, -INF, -play_half_extent),
				Vector3(play_half_extent, INF, play_half_extent))
		place_on_ground(safe + Vector3.UP)
		respawned.emit()


func respawn() -> void:
	if mode == Mode.RIDE and foot_enabled:
		_toggle_board()
	place_on_ground(_spawn)
	foot.reset()
	if mode == Mode.RIDE:
		hover.enter(facing_yaw)
	respawned.emit()
