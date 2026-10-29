class_name PlayerVisual
extends Node3D
## Presentation layer of the player. This node is top-level with physics
## interpolation off: every frame it moves to the body's *interpolated* transform,
## so the model, ribbons, board and effects stay smooth at any refresh rate while
## gameplay physics runs at a fixed tick.
##
## Update order each frame (one owner per transform, nothing fights):
##   context -> air moves (TrickDirector) -> board pose -> model root -> model.tick()
##   (skeleton) -> ribbons -> effects.
## Tricks (TrickDirector channels) turn the sword and the rider together about her
## centre of mass (visual only: the physics body never rotates), move the sword relative
## to her feet (spun under her, stood on its nose, taken in hand), float her off it and
## place her feet and pose; landing rewards and bails come back from its signals.

@export_group("Transitions")
@export var ride_blend_time := 0.45
@export var visual_turn_sharpness := 16.0
@export_group("Board pose")
@export var board_bank := 0.72
@export var board_air_pitch := 0.38
@export var board_align_sharpness := 10.0
@export var hover_bob := 0.025
@export var air_tilt := 0.12
## 0 = rider stays perpendicular to the board, 1 = rider always upright.
@export_range(0.0, 1.0) var rider_upright := 0.42
@export var stance_half_width := 0.28
## Airborne tuck: how far the board is drawn up toward the body (m), how long into a
## jump it takes, and the ground distance at which the legs reach down for the landing.
@export var tuck_height := 0.24
@export var tuck_delay := 0.18
@export var landing_reach := 1.3
## Height of the rider's centre of mass above the deck: tricks rotate about it.
@export var trick_pivot := 0.8

@onready var player: PlayerController = get_parent()
@onready var model: SpiritModel = $SpiritModel
@onready var ribbons: Ribbons = $Ribbons
@onready var cloak: Cloak = $Cloak
@onready var smoke: SmokeBody = $SmokeBody
@onready var board: Hoverboard = $Hoverboard
@onready var fx: PlayerFX = $PlayerFX
@onready var ctx: MotionContext = $MotionContext

var ride_blend := 0.0
var tricks := TrickDirector.new()
var combat := CombatDirector.new()

var _yaw := 0.0
var _turn_rate := 0.0
var _board_up := Vector3.UP
var _bank := 0.0
var _pitch := 0.0
var _roll_air := 0.0
var _time := 0.0
var _glow := 0.0
var _dodge_w := 0.0
var _landed_impact := 0.0
var _last_origin := Vector3.ZERO
var _travel := Vector3.ZERO
var _still_time := 0.0
var _tuck := 0.0
var _prev_body := Quaternion.IDENTITY
var _prev_board_q := Quaternion.IDENTITY
var _flare := 0.0


func _ready() -> void:
	tricks.name = "TrickDirector"
	add_child(tricks)
	combat.name = "Combat"
	combat.setup(self)
	add_child(combat)
	tricks.hop_requested.connect(func(vy: float) -> void: player.hover.request_hop(vy))
	tricks.sand_slash.connect(func(side: float) -> void: board.on_slash(side))
	tricks.landed.connect(_on_trick_landing)
	tricks.bailed.connect(func() -> void: player.hover.bail_now(player))
	tricks.move_started.connect(_on_move_started)
	(player.get_node("HoverMotor") as HoverMotor).charge_ready.connect(func() -> void: board.on_charge_ready())
	# TrickDirector owns the air poses now (including grabs).
	ctx.grab_chance = 0.0
	ribbons.model = model
	cloak.model = model
	smoke.model = model
	model.ctx = ctx
	fx.setup(model)
	player.mode_changed.connect(_on_mode_changed)
	player.landed.connect(_on_landed)
	player.jumped.connect(_on_jumped)
	player.dodged.connect(_on_dodged)
	player.boost_changed.connect(_on_boost_changed)
	player.respawned.connect(_on_respawned)
	var motor: HoverMotor = player.get_node("HoverMotor")
	motor.trick_landed.connect(_on_trick_landed)
	motor.bailed.connect(_on_bailed)
	ctx.sand_touch_started.connect(func(_side: float) -> void: fx.on_sand_touch())
	ctx.landing_slide_started.connect(func() -> void: fx.on_landing_slide())
	ctx.gesture_started.connect(func(side: float) -> void: fx.on_gesture(side))
	ctx.sat_down.connect(func() -> void: fx.on_sat_down())
	_yaw = player.facing_yaw


func _process(delta: float) -> void:
	_time += delta
	var origin := player.get_global_transform_interpolated().origin
	global_transform = Transform3D(Basis.IDENTITY, origin)
	# Measured (interpolated) travel velocity: what the eye sees, used for the stride.
	if delta > 0.0 and origin.distance_to(_last_origin) < 3.0:
		var v := (origin - _last_origin) / delta
		_travel = _travel.lerp(Vector3(v.x, 0.0, v.z), 1.0 - exp(-25.0 * delta))
	_last_origin = origin

	var riding := player.mode == PlayerController.Mode.RIDE
	ride_blend = move_toward(ride_blend, 1.0 if riding else 0.0, delta / ride_blend_time)
	var rb := smoothstep(0.0, 1.0, ride_blend)
	var prev_yaw := _yaw
	_yaw = lerp_angle(_yaw, player.facing_yaw, 1.0 - exp(-visual_turn_sharpness * delta))
	_turn_rate = lerpf(_turn_rate, wrapf(_yaw - prev_yaw, -PI, PI) / maxf(delta, 0.0001), 1.0 - exp(-10.0 * delta))

	var hm := player.hover
	var speed := player.horizontal_speed()
	var speed01 := clampf(speed / hm.cruise_speed, 0.0, 1.6)
	var floor_n := player.get_floor_normal() if player.is_on_floor() else Vector3.UP
	var world_n := hm.ground_normal if riding else floor_n

	# --- Contextual variations ---------------------------------------------------------
	var inp := player.input
	ctx.update(delta, {
		"speed": speed,
		"grounded": player.grounded and not riding,
		"riding": riding,
		"has_input": inp.move.length() > 0.1 or inp.jump_pressed or inp.dodge_pressed or inp.board_pressed,
		"turn_rate": _turn_rate,
		"slope_deg": rad_to_deg(acos(clampf(world_n.y, -1.0, 1.0))),
		"landed_impact": _landed_impact,
		"board_supported": hm.supported,
		"board_air_time": hm.air_time,
		"board_drift": hm.drift_amount,
		"board_drift_dir": hm.drift_dir,
		"board_carve": hm.carve,
		"boost": hm.boost_level if riding else 0.0,
	})
	_landed_impact = 0.0

	# --- Tricks -----------------------------------------------------------------------
	tricks.update(delta, {
		"riding": riding,
		"supported": hm.supported,
		"vy": player.velocity.y,
		"speed": speed,
		"gravity": hm.gravity,
		"height": hm.ground_distance - hm.hover_height,
		"carve": hm.carve,
		"steer": -inp.axes.x,
		"pitch_input": inp.axes.y,
		"charging": riding and inp.jump_held,
	})
	var tc: TrickDirector.Channels = tricks.out
	var tw: Dictionary = tc.w

	# --- Board pose (local to this node, whose origin is the feet) -------------------
	var target_up := hm.ground_normal if hm.supported else Vector3.UP.lerp(hm.ground_normal, 0.3).normalized()
	_board_up = _board_up.slerp(target_up, 1.0 - exp(-board_align_sharpness * delta)).normalized()
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var back := -(fwd - _board_up * fwd.dot(_board_up)).normalized()
	var right := _board_up.cross(back).normalized()
	var b := Basis(right, _board_up, back).orthonormalized()
	var bank_target := (-hm.carve * board_bank - hm.drift_dir * hm.drift_amount * 0.15) if riding else 0.0
	_bank = lerpf(_bank, bank_target, 1.0 - exp(-6.0 * delta))
	var air_pitch := 0.0
	var air_roll := 0.0
	if riding and not hm.supported:
		air_pitch = clampf(player.velocity.y * 0.045, -board_air_pitch, board_air_pitch)
		air_roll = 0.5 * ctx.board_tuck * air_tilt
	_pitch = lerpf(_pitch, air_pitch, 1.0 - exp(-4.0 * delta))
	_roll_air = lerpf(_roll_air, air_roll, 1.0 - exp(-5.0 * delta))
	b = Basis(-b.z, _bank + _roll_air) * Basis(b.x, _pitch) * b
	var bob := 0.0
	if hm.supported:
		bob = sin(_time * 2.3) * hover_bob * (1.0 - clampf(speed01, 0.0, 1.0) * 0.7)
	# Tuck: in a real jump the board comes up to the body (knees to chest); falling
	# toward the ground the legs reach down again to meet the landing.
	var tuck_target := 0.0
	if riding and not hm.supported:
		tuck_target = smoothstep(tuck_delay, tuck_delay + 0.25, hm.air_time)
		# A tucked pose draws the sword right up; stretched or kicking legs keep it low.
		tuck_target = clampf(tuck_target * (1.0 - 0.75 * maxf(tw[&"extend"], tw[&"kick"])) + 0.5 * tw[&"tuck"], 0.0, 1.5)
		if player.velocity.y < 0.0:
			tuck_target *= smoothstep(0.35, landing_reach, hm.ground_distance)
	_tuck = move_toward(_tuck, tuck_target, delta * (3.0 if tuck_target > _tuck else 6.0))
	var tuck_m := smoothstep(0.0, 1.0, minf(_tuck, 1.0)) * tuck_height + maxf(_tuck - 1.0, 0.0) * tuck_height * 0.6
	# The deck: where the rider's feet expect the sword. The drawn sword may slide along
	# its length and turn about a point along it (spun under her, stood on end under her
	# front foot, nose pressed down).
	var deck := Transform3D(b, Vector3(0.0, bob + tuck_m, 0.0))
	var rel := Basis(tc.board)
	var piv := Vector3(0.0, 0.0, tc.pivot)
	var board_xf := deck * Transform3D(rel, piv - rel * piv) * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, tc.slide))
	board_xf.origin += deck.basis.y * tc.rise + deck.basis.x * tc.side

	# --- Rider: blend between upright on foot and sideways stance on the board ---------
	var foot_xf := Transform3D(Basis(Vector3.UP, _yaw), Vector3.ZERO)
	var stance := b * Basis(Vector3.UP, -PI * 0.5)
	var upright := Basis(Vector3.UP, _yaw - PI * 0.5)
	var rider_basis := Basis(stance.get_rotation_quaternion().slerp(upright.get_rotation_quaternion(), rider_upright))
	var model_xf := foot_xf.interpolate_with(Transform3D(rider_basis, deck.origin + Vector3.UP * tc.lift), rb)

	# Tricks: sword and rider turn together about her centre of mass.
	var travel := Basis(Vector3.UP, _yaw)
	var spin := Basis.IDENTITY
	if not tc.body.is_equal_approx(Quaternion.IDENTITY):
		spin = travel * Basis(tc.body) * travel.inverse()
		var pivot := deck.origin + Vector3.UP * trick_pivot
		var about := Transform3D(spin, pivot - spin * pivot)
		board_xf = about * board_xf
		deck = about * deck
		model_xf = about * model_xf
	board.transform = board_xf
	model.transform = model_xf

	# Feet on the deck, or on the drawn sword (stood on end, nose pressed); off it while
	# she floats (spun or flipped under her, taken in hand); moved by the move itself
	# (a leg kicked out, both stretched apart).
	var lift_up := spin * Vector3.UP * tc.lift * 1.25
	var f0 := (deck * Vector3(0.0, 0.0, -stance_half_width)).lerp(board_xf * Vector3(0.0, 0.0, -stance_half_width), tc.on_board) + lift_up
	var f1 := (deck * Vector3(0.0, 0.0, stance_half_width)).lerp(board_xf * Vector3(0.0, 0.0, stance_half_width), tc.on_board) + lift_up
	f0 += spin * (travel * tc.front)
	f1 += spin * (travel * tc.rear)
	var to_model := model.transform.affine_inverse()
	model.ride_feet[0] = to_model * f0
	model.ride_feet[1] = to_model * f1
	model.ride_feet_basis = model.basis.inverse() * (spin * stance)
	model.ground_normal = (model.basis.inverse() * world_n).normalized()

	# --- Animation inputs --------------------------------------------------------------
	var foot := player.foot
	var dashing := foot.dodge_timer > 0.0
	_dodge_w = move_toward(_dodge_w, 1.0 if dashing else 0.0, delta * (14.0 if dashing else 6.0))
	model.speed = _travel.length() if not riding else 0.0
	model.travel_local = model.basis.inverse() * _travel
	model.run_blend = foot.run_blend
	model.grounded = player.grounded or riding
	model.vertical_speed = player.velocity.y
	model.dodge_weight = _dodge_w
	model.ride_weight = rb
	model.boost = hm.boost_level if riding else 0.0
	model.carve = hm.carve if riding else 0.0
	model.accel_lean = hm.forward_accel if riding else 0.0
	model.turn_rate = _turn_rate if not riding else 0.0
	model.ride_charge = hm.jump_charge if riding else 0.0
	model.ride_tuck = tuck_m
	model.trick_pose = tw
	model.steer_lead = lerpf(model.steer_lead, -inp.axes.x if riding else 0.0, 1.0 - exp(-12.0 * delta))
	# Where the held blade points (travel frame, turning with her): her sword hand
	# reaches out along it.
	var sw := tc.swing
	var blade := (spin * (travel * Vector3(sin(sw.x) * cos(sw.y), sin(sw.y), -cos(sw.x) * cos(sw.y)))).normalized()
	model.blade_dir = model.basis.inverse() * blade
	model.blade_w = tc.hold
	model.grip2 = tc.grip2
	model.tick(delta)
	# The sword taken in hand: kicked up from under her feet it arcs up into her grip,
	# turning over once on the way, and lands pointing where the move aims it (blade
	# edge leading); it goes back down the same way.
	if tc.hold > 0.001:
		var hand := model.transform * model.skeleton.get_bone_global_pose(SpiritModel.HA_R)
		var zb := -blade
		var xb := Vector3.UP.cross(zb)
		if xb.length_squared() < 0.001:
			xb = travel * Vector3.RIGHT
		xb = xb.normalized()
		var held_basis := Basis(zb, sw.z) * Basis(xb, zb.cross(xb).normalized(), zb)
		var grip := hand.origin + hand.basis * Vector3(0.0, -0.06, 0.0)
		var k := smoothstep(0.0, 1.0, tc.hold)
		var from := board.transform
		var a := from * SpiritSword.GRIP
		var c := (a + grip) * 0.5 + Vector3.UP * (0.35 + 0.45 * a.distance_to(grip))
		var at := a * (1.0 - k) * (1.0 - k) + c * 2.0 * (1.0 - k) * k + grip * k * k
		var q := from.basis.orthonormalized().get_rotation_quaternion().slerp(held_basis.get_rotation_quaternion(), k)
		var fb := Basis(q) * Basis(Vector3.RIGHT, -TAU * (1.0 - k))
		board.transform = Transform3D(fb, at - fb * SpiritSword.GRIP)

	# Combat reads the blade where it really is this frame (hits, trails, impacts).
	combat.update(delta)

	ribbons.excitement = clampf(speed / 10.0, 0.0, 1.0) * 0.6 + model.boost * 0.6 + _dodge_w * 0.6 + ctx.sand_touch * 0.5
	ribbons.step(delta)
	cloak.excitement = ribbons.excitement
	cloak.wind = model.boost
	# Spins and flips flare the mantle open (how fast she is turning).
	var turn_speed := TrickDirector.turn_angle(_prev_body, tc.body) / maxf(delta, 0.001)
	_prev_body = tc.body
	# Flips and shove-its open it too, so her legs show as she kicks and tucks.
	var flare_target := maxf(clampf(turn_speed / 9.0, 0.0, 1.0), 0.35 * float(tw[&"flick"]))
	_flare = lerpf(_flare, flare_target, 1.0 - exp(-(10.0 if flare_target > _flare else 3.0) * delta))
	cloak.spin_flare = _flare
	cloak.step(delta)
	var still := speed < 0.6 and player.grounded
	_still_time = _still_time + delta if still else 0.0
	smoke.update(delta, {
		"velocity": Vector3(_travel.x, player.velocity.y if not player.grounded else 0.0, _travel.z),
		"airborne": not player.grounded,
		"boost": model.boost,
		"rest": maxf(ctx.sit, smoothstep(4.0, 8.0, _still_time)),
	})

	# --- Board and effects ---------------------------------------------------------------
	# How fast the sword whirls (relative to the way she travels): fast spins leave a
	# short glowing arc from its tip.
	var bq := (travel.inverse() * board.transform.basis).get_rotation_quaternion()
	board.set_swing(TrickDirector.turn_angle(_prev_board_q, bq) / maxf(delta, 0.001))
	_prev_board_q = bq
	board.update_effects(delta, speed01 if riding else 0.0, model.boost, hm.supported and riding,
			hm.ground_point, hm.ground_distance, hm.carve, hm.drift_amount if riding else 0.0)
	var running := clampf((speed - 4.5) / 3.0, 0.0, 1.0) if player.grounded else 0.0
	fx.update(delta, running, not player.grounded, riding, ctx, model)

	_glow = move_toward(_glow, 0.0, delta * 2.0)
	cloak.face_flare = maxf(cloak.face_flare, _glow * 0.5)


func _on_mode_changed(mode: PlayerController.Mode) -> void:
	_glow = 1.2
	if mode == PlayerController.Mode.RIDE:
		_board_up = Vector3.UP
		model.impulse_landing(0.45)   # gather the body as the substance flows down
		board.summon()
		fx.on_transform(true)
	else:
		board.dismiss()
		fx.on_transform(false)


func _on_landed(impact: float, on_board: bool) -> void:
	_landed_impact = impact
	model.impulse_landing(clampf(impact / 12.0, 0.0, 1.0))
	# Big landings end in a short balance check; small hops land clean.
	var shaky := clampf((impact - 6.0) / 8.0, 0.0, 0.8)
	if shaky > 0.05:
		model.land_wobble(shaky)
	smoke.on_land(impact)
	if on_board:
		board.on_land(impact, player.hover.ground_point)
	else:
		fx.on_landed(impact)


## Landing judged by the tricks: clean landings after tricks pay out speed (flow), a
## sketchy one wobbles, a bail costs speed and the combo.
func _on_trick_landing(clean: bool, had_tricks: bool) -> void:
	if not had_tricks:
		return
	if clean:
		player.hover.add_speed(1.2 + 0.4 * minf(tricks.combo.multiplier, 4.0), player)
		model.land_wobble(0.18)
		board.on_trick_landed(tricks.combo.multiplier)
	else:
		model.land_wobble(0.6)


func _on_move_started(_move: String, _title: String, by_player: bool) -> void:
	_glow = maxf(_glow, 0.6)
	# The runes flare while she works the sword, so the trick reads from afar.
	if by_player:
		board.on_trick_start()


func _on_jumped(on_board: bool) -> void:
	smoke.on_jump()
	if on_board:
		board.on_jump()
		_glow = maxf(_glow, 0.5)
	else:
		model.impulse_takeoff()
		fx.on_jump()


func _on_dodged(dir: Vector3) -> void:
	_glow = maxf(_glow, 0.9)
	var local := Basis(Vector3.UP, player.facing_yaw).inverse() * dir
	model.dodge_side = clampf(local.x, -1.0, 1.0)
	fx.on_dodge(model)
	smoke.on_boost(true)


func _on_boost_changed(active: bool) -> void:
	smoke.on_boost(active)
	if active:
		board.on_boost_start()


func _on_trick_landed(_spins: float) -> void:
	_glow = maxf(_glow, 1.4)
	board.on_boost_start()


func _on_bailed() -> void:
	model.impulse_landing(1.0)
	fx.on_landed(14.0)


func _on_respawned() -> void:
	global_transform = Transform3D(Basis.IDENTITY, player.global_position)
	_yaw = player.facing_yaw
	ribbons.reset()
