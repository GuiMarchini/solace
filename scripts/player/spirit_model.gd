class_name SpiritModel
extends Node3D
## The wanderer's animated body: one continuous skinned body (see SpiritBodyBuilder),
## drawn as living smoke, on a Skeleton3D animated from motion capture and layers.
##
## Legs are driven by IK toward planted foot targets: during stance a foot slides back
## exactly at body speed (so it stays fixed on the sand), during swing it travels an arc
## with a high knee and a kick-back heel. Gait parameters blend walk -> run -> sprint by
## real speed. Upper body, pelvis and head are layered procedural rotations. Contextual
## variations (MotionContext), the board stance, air, dash, landing and resting all
## blend into the same targets, so nothing snaps. The model faces -Z, origin at the feet.

@export_group("Proportions")
@export var hip_height := 1.0
@export var thigh_length := 0.485
@export var shin_length := 0.465
@export var upper_arm_length := 0.29
@export var forearm_length := 0.26
@export var head_radius := 0.084
@export_group("Locomotion (motion capture)")
## Looping cycles retargeted from motion capture (scripts/tools/import_mocap.gd).
@export var walk_cycle: MotionCycle = preload("res://assets/mocap/walk.res")
@export var jog_cycle: MotionCycle = preload("res://assets/mocap/jog.res")
@export var run_cycle: MotionCycle = preload("res://assets/mocap/run.res")
## Game speeds (m/s) at which the walk, jog and run cycles are fully used.
@export var gait_speeds := Vector3(1.3, 4.5, 6.5)
## How much the cadence rises above the capture's natural rhythm at speed; the rest of
## the speed goes into longer, floatier strides (feet stay planted while in contact).
@export_range(0.0, 1.0) var cadence_exponent := 0.35
## Extra stylised forward lean on top of the capture (walk, jog, run).
@export var body_lean := Vector3(0.0, 0.05, 0.12)
@export_group("Animation")
@export var joint_sharpness := 20.0
## Legs follow their IK targets almost directly (targets are already continuous);
## heavy smoothing here would make planted feet lag and slide.
@export var leg_sharpness := 60.0
@export var turn_lean_strength := 0.035
@export var ride_crouch_depth := 0.26
## How far the arms open while riding (1 = wide surfer stance; lower keeps them inside the
## cloak). Wide enough that the hands come out of it and stay visible.
@export var ride_arm_spread := 0.6
@export_group("Materials")
@export var body_material: Material
## Build the body mesh (off: only the animated skeleton, for tools).
@export var procedural_body := true

# --- Animation inputs (set by PlayerVisual every frame) ---
var speed := 0.0
var run_blend := 0.0
var grounded := true
var vertical_speed := 0.0
var dodge_weight := 0.0
var dodge_side := 0.0
var ride_weight := 0.0
var boost := 0.0
var carve := 0.0
var accel_lean := 0.0
var turn_rate := 0.0
## 0..1 jump charge on the board (crouch).
var ride_charge := 0.0
## Airborne tuck on the board (m): the board is drawn up toward the body (PlayerVisual).
var ride_tuck := 0.0
## Trick poses from TrickDirector (name -> 0..1, see TrickDirector.POSE_KEYS): tucked,
## grabbing the sword, stretched out, a leg kicked back, an arm thrown up, sunk low,
## standing tall on the upturned sword, holding it like a staff, slashing the sand,
## pressing the nose. The feet themselves are placed by PlayerVisual.
var trick_pose := {}
## Raw steering input (-1 right .. 1 left): head and chest turn into a turn before the
## board does (anticipation).
var steer_lead := 0.0
## Combat: where the held blade points (model space), how much the sword is in her hand
## (her sword hand reaches out along the blade) and 0..1 the other hand on the grip too.
var blade_dir := Vector3.FORWARD
var blade_w := 0.0
var grip2 := 0.0
## Measured travel velocity in this node's space (drives stride and stance direction).
var travel_local := Vector3.ZERO
## Ground normal expressed in this node's space (feet and hands follow the slope).
var ground_normal := Vector3.UP
var ride_feet: Array[Vector3] = [Vector3(-0.2, 0.0, 0.0), Vector3(0.2, 0.0, 0.0)]
var ride_feet_basis := Basis.IDENTITY
var ctx: MotionContext

var chest: Node3D
var skeleton: Skeleton3D
var body_mesh: MeshInstance3D
## World positions of the hands, updated every frame (effects use them).
var hand_world: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
## True for a foot currently in the stance phase of the gait.
var foot_planted: Array[bool] = [false, false]

enum { HIPS, SPINE, CHEST, NECK, HEAD, SH_L, EL_L, HA_L, SH_R, EL_R, HA_R, TH_L, KN_L, FT_L, TH_R, KN_R, FT_R, JOINT_COUNT }
const PARENT := [-1, HIPS, SPINE, CHEST, NECK, CHEST, SH_L, EL_L, CHEST, SH_R, EL_R, HIPS, TH_L, KN_L, HIPS, TH_R, KN_R]
const BONE_NAMES := ["Hips", "Spine", "Chest", "Neck", "Head", "UpperArm.L", "Forearm.L", "Hand.L",
	"UpperArm.R", "Forearm.R", "Hand.R", "Thigh.L", "Shin.L", "Foot.L", "Thigh.R", "Shin.R", "Foot.R"]

var _rest: Array[Vector3] = []
var _cur: Array[Quaternion] = []
var _hips_pos := Vector3.ZERO
var _neck_socket: Node3D
var _cape_xf := Transform3D.IDENTITY
var _phase := 0.0
var _time := 0.0
var _air := 0.0
var _land := 0.0
var _land_vel := 0.0
var _gait_w := 0.0
var _prev_speed := 0.0
var _accel := 0.0
var _psi := 0.0
var _contact_frac: Array[float] = []
var _clip_q: Array[Quaternion] = []
var _blend_q: Array[Quaternion] = []
var _gait_hips := Vector3.ZERO
var _lock_world: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _lock_w: Array[float] = [0.0, 0.0]
var _locked: Array[bool] = [false, false]
var _delta := 0.016
var _bal := Vector2.ZERO
var _bal_v := Vector2.ZERO
var _wob := 0.0
var _wob_t := 0.0


class Pose:
	var base: Array[Quaternion] = []     # base local rotations (motion capture), identity otherwise
	var e := PackedVector3Array()        # additive bone eulers on top of `base`
	var hips := Vector3.ZERO             # hips offset from rest height
	var feet: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var foot_pitch: Array[float] = [0.0, 0.0]
	var leg_fk := 0.0                    # 0 = IK feet, 1 = FK leg angles
	var hands: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var hand_w: Array[float] = [0.0, 0.0]

	var gait := 0.0                      # weight of the captured locomotion

	func _init() -> void:
		e.resize(17)
		base.resize(17)
		for i in 17:
			base[i] = Quaternion.IDENTITY

	func add(bone: int, v: Vector3) -> void:
		e[bone] = e[bone] + v

	func reach(side: int, target: Vector3, w: float) -> void:
		hands[side] = hands[side].lerp(target, w / maxf(w + hand_w[side], 0.0001)) if hand_w[side] > 0.0 else target
		hand_w[side] = maxf(hand_w[side], w)


func _ready() -> void:
	_build()


## Bone offsets relative to their parents (straight rest pose).
func rest_offsets() -> Array[Vector3]:
	var r: Array[Vector3] = []
	r.resize(JOINT_COUNT)
	r[HIPS] = Vector3(0.0, hip_height, 0.0)
	r[SPINE] = Vector3(0.0, 0.07, 0.0)
	r[CHEST] = Vector3(0.0, 0.22, 0.0)
	r[NECK] = Vector3(0.0, 0.13, 0.0)
	r[HEAD] = Vector3(0.0, 0.05, 0.0)
	for side in 2:
		var s := -1.0 if side == 0 else 1.0
		var o := 0 if side == 0 else 3
		r[SH_L + o] = Vector3(0.105 * s, 0.105, 0.0)
		r[EL_L + o] = Vector3(0.0, -upper_arm_length, 0.0)
		r[HA_L + o] = Vector3(0.0, -forearm_length, 0.0)
		r[TH_L + o] = Vector3(0.06 * s, -0.03, 0.0)
		r[KN_L + o] = Vector3(0.0, -thigh_length, 0.0)
		r[FT_L + o] = Vector3(0.0, -shin_length, 0.0)
	return r


func impulse_landing(strength: float) -> void:
	_land_vel += clampf(strength, 0.0, 1.2) * 3.2


## A shaky landing: the torso sways and the arms swing out to catch the balance,
## dying away in under a second (0..1).
func land_wobble(strength: float) -> void:
	_wob = maxf(_wob, clampf(strength, 0.0, 1.0))
	_wob_t = 0.0


func impulse_takeoff() -> void:
	_land = 0.3
	_land_vel = -7.0


func cape_anchor() -> Transform3D:
	return _cape_xf


## Back of the head, where the long locks of hair start.
func head_anchor() -> Transform3D:
	return skeleton.get_bone_global_pose(HEAD).translated_local(Vector3(0.0, 0.1, 0.07))


## 1 when standing on the ground on foot, 0 in the air or on the board.
func groundedness() -> float:
	return (1.0 - _air) * (1.0 - ride_weight)


# --- Construction ---------------------------------------------------------------------

func _build() -> void:
	_rest = rest_offsets()
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)
	for i in JOINT_COUNT:
		skeleton.add_bone(BONE_NAMES[i])
	for i in JOINT_COUNT:
		if PARENT[i] >= 0:
			skeleton.set_bone_parent(i, PARENT[i])
		skeleton.set_bone_rest(i, Transform3D(Basis.IDENTITY, _rest[i]))
	skeleton.reset_bone_poses()
	_cur.resize(JOINT_COUNT)
	for i in JOINT_COUNT:
		_cur[i] = Quaternion.IDENTITY
	_hips_pos = _rest[HIPS]
	_clip_q.resize(JOINT_COUNT)
	_blend_q.resize(JOINT_COUNT)
	for c in _clips():
		var frac := 0.0
		if c:
			for k in c.samples:
				frac += maxf(c.contacts[k].x, c.contacts[k].y)
			frac /= c.samples
		_contact_frac.append(frac)

	if procedural_body:
		body_mesh = MeshInstance3D.new()
		body_mesh.name = "Body"
		body_mesh.mesh = SpiritBodyBuilder.load_or_build(_rest, PARENT, head_radius)
		body_mesh.skin = SpiritBodyBuilder.make_skin(_rest, PARENT)
		body_mesh.material_override = body_material
		skeleton.add_child(body_mesh)
		body_mesh.skeleton = NodePath("..")

	chest = Node3D.new()
	chest.name = "ChestSocket"
	add_child(chest)
	_neck_socket = Node3D.new()
	_neck_socket.name = "NeckSocket"
	add_child(_neck_socket)
	_update_sockets()


# --- Per-frame ------------------------------------------------------------------------

func tick(delta: float) -> void:
	_time += delta
	_accel = lerpf(_accel, (speed - _prev_speed) / maxf(delta, 0.0001), 1.0 - exp(-6.0 * delta))
	_prev_speed = speed
	_air = move_toward(_air, 0.0 if grounded else 1.0, delta * 6.0)
	var acc := -120.0 * _land - 14.0 * _land_vel
	_land_vel += acc * delta
	_land += _land_vel * delta
	_gait_w = move_toward(_gait_w, clampf(speed / 0.6, 0.0, 1.0), delta * 5.0)
	var cw := _clip_weights(speed)
	_psi = fposmod(_psi + _phase_rate(cw) * delta, 1.0)

	var p := Pose.new()
	_locomotion(p, cw)
	if ctx:
		_context_layers(p)
	_air_and_dash(p)
	_landing(p)
	if ride_weight > 0.001:
		_ride_layer(p, ride_weight)
	_solve_and_apply(p, delta)


func _clips() -> Array[MotionCycle]:
	return [walk_cycle, jog_cycle, run_cycle]


## Blend weights of the walk / jog / run cycles for a speed.
func _clip_weights(v: float) -> Vector3:
	if v <= gait_speeds.x:
		return Vector3(1, 0, 0)
	if v <= gait_speeds.y:
		var t := smoothstep(gait_speeds.x, gait_speeds.y, v)
		return Vector3(1.0 - t, t, 0.0)
	var t2 := smoothstep(gait_speeds.y, gait_speeds.z, v)
	return Vector3(0.0, 1.0 - t2, t2)


## Phase speed (cycles/s). While a foot is in contact the capture plays at exactly the
## ground speed (so the foot stays planted); flight phases absorb the remaining time.
func _phase_rate(cw: Vector3) -> float:
	var clips := _clips()
	var rate := 0.0
	for i in 3:
		var w: float = cw[i]
		if w < 0.001 or clips[i] == null:
			continue
		var c := clips[i]
		var period := c.source_period
		var natural := c.stride * _leg_scale(c) / period
		var r := maxf(speed, 0.05) / natural
		var ri: float
		if r <= 1.0:
			ri = r / period
		else:
			var cyc := clampf(pow(1.0 / r, cadence_exponent), 0.55, 1.0)
			var cf: float = _contact_frac[i]
			var flight := clampf((cyc - cf / r) / maxf(1.0 - cf, 0.05), 0.5, 2.5)
			var ct := c.contact(_psi)
			var contact := maxf(ct.x, ct.y)
			ri = (contact * r + (1.0 - contact) / flight) / period
		rate += w * ri
	return rate


## Approximate seconds per locomotion cycle at a speed (used by inspection tools).
func _leg_scale(c: MotionCycle) -> float:
	return (thigh_length + shin_length) / c.leg_length


func cycle_period(v: float) -> float:
	var saved := speed
	speed = v
	var r := _phase_rate(_clip_weights(v))
	speed = saved
	return 1.0 / maxf(r, 0.01)


func _g(v: Vector3, cw: Vector3) -> float:
	return v.x * cw.x + v.y * cw.y + v.z * cw.z


## Ground height under a model-space XZ point (plane through the origin with ground_normal).
func _ground_y(x: float, z: float) -> float:
	var n := ground_normal if ground_normal.y > 0.3 else Vector3.UP
	return -(n.x * x + n.z * z) / n.y


func _on_ground(v: Vector3, lift: float = 0.0) -> Vector3:
	return Vector3(v.x, _ground_y(v.x, v.z) + lift, v.z)


func _locomotion(p: Pose, cw: Vector3) -> void:
	var g := _gait_w * (1.0 - ride_weight) * (1.0 - _air) * (1.0 - dodge_weight)
	var idle := 1.0 - _gait_w
	p.gait = g

	# Captured locomotion: blend walk / jog / run at the shared phase.
	foot_planted[0] = false
	foot_planted[1] = false
	if g > 0.001:
		var clips := _clips()
		var acc_w := 0.0
		for i in 3:
			var w: float = cw[i]
			if w < 0.001 or clips[i] == null:
				continue
			var h := clips[i].sample_pose(_psi, _clip_q)
			var k := _leg_scale(clips[i])
			h = Vector3(h.x * k, (h.y - 0.03) * k + 0.03, h.z * k)
			if acc_w <= 0.0:
				for b in JOINT_COUNT:
					_blend_q[b] = _clip_q[b]
				_gait_hips = h
			else:
				var t := w / (acc_w + w)
				for b in JOINT_COUNT:
					_blend_q[b] = _blend_q[b].slerp(_clip_q[b], t)
				_gait_hips = _gait_hips.lerp(h, t)
			acc_w += w
		for b in JOINT_COUNT:
			p.base[b] = Quaternion.IDENTITY.slerp(_blend_q[b], g)
		p.hips = (_gait_hips - _rest[HIPS]) * g
		var contact := Vector2.ZERO
		for i in 3:
			if cw[i] > 0.001 and clips[i]:
				contact += clips[i].contact(_psi) * cw[i]
		foot_planted[0] = contact.x > 0.5 and g > 0.9
		foot_planted[1] = contact.y > 0.5 and g > 0.9

	# Idle feet (IK) where the capture isn't driving the legs.
	for side in 2:
		var s := -1.0 if side == 0 else 1.0
		p.feet[side] = _on_ground(Vector3(_rest[TH_L + (0 if side == 0 else 3)].x + s * 0.018, 0.0, 0.01 * s))

	# A touch of stylised lean with speed and acceleration.
	var lean := _g(body_lean, cw) + clampf(_accel * 0.02, -0.1, 0.12)
	p.add(SPINE, Vector3(-lean, 0.0, 0.0) * g)
	p.add(HEAD, Vector3(lean * 0.6, 0.0, 0.0) * g)

	# Idle: a floating, observing stillness; slow drift of arms and head.
	# Hands hang a little forward, in the cloak's opening, as on the concept.
	p.add(SH_L, Vector3(0.26 + 0.04 * sin(_time * 0.8), 0.0, -0.02 - 0.02 * sin(_time * 0.5)) * idle)
	p.add(SH_R, Vector3(0.26 + 0.04 * sin(_time * 0.8 + 1.0), 0.0, 0.02 + 0.02 * sin(_time * 0.5 + 2.0)) * idle)
	p.add(EL_L, Vector3(0.5, 0.0, 0.0) * idle)
	p.add(EL_R, Vector3(0.5, 0.0, 0.0) * idle)
	p.add(HA_L, Vector3(0.15, 0.0, 0.0) * idle)
	p.add(HA_R, Vector3(0.15, 0.0, 0.0) * idle)
	p.add(CHEST, Vector3(0.02 * sin(_time * 0.35), 0.0, 0.0) * idle)
	p.add(HEAD, Vector3(0.04 * sin(_time * 0.37) - 0.03, 0.12 * sin(_time * 0.19), 0.035 * sin(_time * 0.29)) * idle)
	p.add(HIPS, Vector3(0.0, 0.0, 0.025 * sin(_time * 0.4)) * idle)
	p.hips.y += (0.006 * sin(_time * TAU * 0.3) - 0.004) * idle

	# Lean into turns: gentle turns lean the torso, sharp ones the whole body.
	var tl := clampf(turn_rate * speed * turn_lean_strength, -0.4, 0.4) * g
	p.add(SPINE, Vector3(0.0, 0.0, tl))
	p.add(HIPS, Vector3(0.0, 0.0, tl * 0.6))
	p.add(HEAD, Vector3(0.0, 0.0, -tl * 0.6))


func _context_layers(p: Pose) -> void:
	var c := ctx

	# Slope balance: arms open a little on steep or uneven sand.
	var bal := c.balance * groundedness()
	p.add(SH_L, Vector3(0.1, 0.0, -0.35) * bal)
	p.add(SH_R, Vector3(0.1, 0.0, 0.35) * bal)

	# Running turn that brushes the sand with the inner hand.
	if c.sand_touch > 0.001:
		var w := c.sand_touch
		var side := c.sand_side   # -1 = left hand (left turn), +1 = right hand
		var inner := 0 if side < 0.0 else 1
		var outer := 1 - inner
		p.add(SPINE, Vector3(-0.12, 0.0, -side * 0.6) * w)
		p.add(HIPS, Vector3(-0.04, 0.0, -side * 0.3) * w)
		p.add(CHEST, Vector3(0.0, side * 0.25, 0.0) * w)
		p.add(HEAD, Vector3(0.25, -side * 0.2, side * 0.35) * w)
		p.hips.y -= 0.15 * w
		p.hips.x += side * 0.07 * w
		p.reach(inner, _on_ground(Vector3(side * 0.34, 0.0, -0.06), 0.035), w)
		var o := 0 if outer == 0 else 3
		# The outer arm opens out as a counterweight (replaces the sprint arm pose).
		p.e[SH_L + o] = p.e[SH_L + o].lerp(Vector3(0.1, 0.0, -side * 1.15), w)
		p.e[EL_L + o] = p.e[EL_L + o].lerp(Vector3(0.35, 0.0, 0.0), w)
		p.feet[outer] = p.feet[outer].lerp(_on_ground(p.feet[outer] + Vector3(-side * 0.16, 0.0, 0.08)), w)

	# Abrupt stop: lean back, brace one foot forward, arms out, then settle.
	if c.stop_recover > 0.001:
		var w := c.stop_recover
		var s := c.stop_side
		var front := 0 if s < 0.0 else 1
		p.add(SPINE, Vector3(0.28, 0.0, s * 0.06) * w)
		p.add(HEAD, Vector3(-0.15, 0.0, 0.0) * w)
		p.add(SH_L, Vector3(0.45, 0.0, -0.55) * w)
		p.add(SH_R, Vector3(0.45, 0.0, 0.55) * w)
		p.hips.y -= 0.07 * w
		p.feet[front] = p.feet[front].lerp(_on_ground(Vector3(s * 0.08, 0.0, -0.22)), w)
		p.foot_pitch[front] = lerpf(p.foot_pitch[front], 0.35, w)
		p.feet[1 - front] = p.feet[1 - front].lerp(_on_ground(Vector3(-s * 0.08, 0.0, 0.12)), w)

	# Hard landing: low crouch, one hand to the sand; slides if still moving fast.
	if c.land_low > 0.001:
		var w := c.land_low
		p.add(SPINE, Vector3(-0.5, 0.0, 0.0) * w)
		p.add(HEAD, Vector3(0.45, 0.0, 0.0) * w)
		p.add(SH_L, Vector3(-0.6, 0.0, -0.9) * w)
		p.add(EL_L, Vector3(0.2, 0.0, 0.0) * w)
		p.hips.y -= 0.27 * w
		p.reach(1, _on_ground(Vector3(0.16, 0.0, -0.2), 0.03), w)
		p.feet[0] = p.feet[0].lerp(_on_ground(Vector3(-0.12, 0.0, -0.12)), w)
		p.feet[1] = p.feet[1].lerp(_on_ground(Vector3(0.11, 0.0, 0.16)), w)
		p.foot_pitch[1] = lerpf(p.foot_pitch[1], -0.5, w)

	# Looking around / toward the horizon (idle, long runs, before sitting).
	if c.look > 0.001:
		var w := c.look
		p.add(CHEST, Vector3(0.0, c.look_yaw * 0.25, 0.0) * w)
		p.add(NECK, Vector3(0.0, c.look_yaw * 0.3, 0.0) * w)
		p.add(HEAD, Vector3(c.look_pitch, c.look_yaw * 0.45, 0.0) * w)

	# Idle weight shift: hips drift over one leg, the other knee relaxes.
	if c.weight_shift > 0.001:
		var w := c.weight_shift
		var s := c.shift_side
		p.hips.x += s * 0.03 * w
		p.hips.y -= 0.012 * w
		p.add(HIPS, Vector3(0.0, 0.0, -s * 0.08) * w)
		p.add(SPINE, Vector3(0.0, 0.0, s * 0.1) * w)
		var relaxed := 0 if s > 0.0 else 1
		p.feet[relaxed] += Vector3(0.0, 0.0, -0.05) * w
		p.foot_pitch[relaxed] = lerpf(p.foot_pitch[relaxed], -0.25, w)

	# Expressive gesture: one hand rises, palm up, as motes gather around it.
	if c.gesture > 0.001:
		var w := c.gesture
		var o := 0 if c.gesture_side < 0.0 else 3
		p.add(SH_L + o, Vector3(1.05, 0.0, c.gesture_side * 0.25) * w)
		p.add(EL_L + o, Vector3(0.8, 0.0, 0.0) * w)
		p.add(HA_L + o, Vector3(-0.5, c.gesture_side * 0.6, 0.0) * w)
		p.add(HEAD, Vector3(0.3, c.gesture_side * 0.35, 0.0) * w)

	# Resting: sit on the sand, knees up, one hand behind, one on a knee.
	if c.sit > 0.001:
		var w := smoothstep(0.0, 1.0, c.sit)
		p.hips = p.hips.lerp(Vector3(0.0, 0.13 + _ground_y(0.0, 0.05) - hip_height, 0.05), w)
		p.add(HIPS, Vector3(0.22, 0.0, 0.0) * w)
		p.add(SPINE, Vector3(-0.32, 0.0, 0.0) * w)
		p.add(HEAD, Vector3(-0.08, 0.0, 0.0) * w)
		for side in 2:
			var s := -1.0 if side == 0 else 1.0
			p.feet[side] = p.feet[side].lerp(_on_ground(Vector3(s * 0.1, 0.0, -0.24 + 0.03 * s)), w)
			p.foot_pitch[side] = lerpf(p.foot_pitch[side], 0.25, w)
		p.reach(0, _on_ground(Vector3(-0.17, 0.0, 0.12), 0.02), w)
		p.reach(1, Vector3(0.1, 0.36 + _ground_y(0.1, -0.16), -0.17), w)


func _air_and_dash(p: Pose) -> void:
	var a := _air * (1.0 - dodge_weight) * (1.0 - ride_weight)
	if a > 0.001:
		var rising := smoothstep(-3.0, 3.0, vertical_speed)
		p.add(TH_L, Vector3(lerpf(0.4, 1.0, rising), 0.0, -0.05))
		p.add(KN_L, Vector3(-lerpf(0.75, 1.45, rising), 0.0, 0.0))
		p.add(FT_L, Vector3(-0.3, 0.0, 0.0))
		p.add(TH_R, Vector3(lerpf(0.15, -0.35, rising), 0.0, 0.05))
		p.add(KN_R, Vector3(-lerpf(0.65, 0.55, rising), 0.0, 0.0))
		p.add(FT_R, Vector3(-0.45, 0.0, 0.0))
		p.add(SH_L, Vector3(lerpf(0.1, -0.55, rising), 0.0, -lerpf(0.95, 0.45, rising)) * a)
		p.add(SH_R, Vector3(lerpf(0.1, -0.55, rising), 0.0, lerpf(0.95, 0.45, rising)) * a)
		p.add(EL_L, Vector3(0.25, 0.0, 0.0) * a)
		p.add(EL_R, Vector3(0.25, 0.0, 0.0) * a)
		p.add(SPINE, Vector3(lerpf(-0.05, 0.12, rising), 0.0, 0.0) * a)
		p.add(HEAD, Vector3(lerpf(-0.12, 0.1, rising), 0.0, 0.0) * a)
		p.leg_fk = a
	if dodge_weight > 0.001 and ride_weight < 0.5:
		var d := dodge_weight
		p.add(HIPS, Vector3(-0.35, 0.0, -0.15 * dodge_side) * d)
		p.add(SPINE, Vector3(-0.45, 0.0, -0.2 * dodge_side) * d)
		p.add(CHEST, Vector3(-0.12, 0.0, 0.0) * d)
		p.add(HEAD, Vector3(0.6, 0.0, 0.0) * d)
		p.add(SH_L, Vector3(-1.25, 0.0, -0.25) * d)
		p.add(SH_R, Vector3(-1.25, 0.0, 0.25) * d)
		var dash_legs := {TH_L: Vector3(0.1, 0, 0), KN_L: Vector3(-0.9, 0, 0), FT_L: Vector3(-0.4, 0, 0),
			TH_R: Vector3(-0.35, 0, 0), KN_R: Vector3(-0.35, 0, 0), FT_R: Vector3(-0.5, 0, 0)}
		for bone in dash_legs:
			p.e[bone] = p.e[bone].lerp(dash_legs[bone], d)
		p.hips.y -= 0.1 * d
		p.leg_fk = maxf(p.leg_fk, d)


func _landing(p: Pose) -> void:
	var l := clampf(_land, -0.3, 1.0)
	p.hips.y -= l * 0.12
	p.add(SPINE, Vector3(-0.3, 0.0, 0.0) * l)
	p.add(SH_L, Vector3(-0.2, 0.0, -0.35) * l)
	p.add(SH_R, Vector3(-0.2, 0.0, 0.35) * l)
	if p.leg_fk > 0.0:
		for o in [0, 3]:
			p.add(TH_L + o, Vector3(0.6, 0.0, 0.0) * l)
			p.add(KN_L + o, Vector3(-1.2, 0.0, 0.0) * l)


## Sideways (regular) stance on the board: the nose is on the model's left (-X).
func _ride_layer(p: Pose, rw: float) -> void:
	var c := ctx
	var tuck := c.board_tuck if c else 0.0
	var tp := trick_pose
	var grab := maxf(c.board_grab if c else 0.0, tp.get(&"grab", 0.0))
	var t_crouch: float = tp.get(&"crouch", 0.0)
	var t_tall: float = tp.get(&"tall", 0.0)
	var t_slash: float = tp.get(&"slash", 0.0)
	var t_press: float = tp.get(&"press", 0.0)
	var drift := c.board_drift if c else 0.0
	var drift_dir := c.board_drift_dir if c else 0.0
	var relaxed := c.board_relaxed if c else 0.0
	var dt := _delta
	# Balance: a springy response to carving and acceleration. The arms and torso
	# overshoot and settle, so the rider reacts to the ride instead of holding a pose.
	var bal_target := Vector2(carve, clampf(accel_lean * 0.05, -1.0, 1.0))
	_bal_v += ((bal_target - _bal) * 60.0 - _bal_v * 8.0) * dt
	_bal += _bal_v * dt
	var sway := sin(_time * 1.7)
	var deep := absf(carve)
	# Pumping: rhythmic knee work while driving forward at low speed.
	var pump := clampf(accel_lean / 6.0, 0.0, 1.0) * (1.0 - boost) * sin(_time * 6.5) * 0.045
	var low := (c.board_style_w if c and c.board_style == 0 else 0.0) * 0.1
	var crouch := (ride_crouch_depth + low + 0.06 * boost + clampf(_land, 0.0, 1.0) * 0.12 + 0.05 * deep
			+ 0.08 * tuck + 0.12 * grab + 0.06 * drift - 0.05 * relaxed + 0.16 * ride_charge + ride_tuck + pump
			+ 0.18 * t_crouch + 0.12 * t_press + 0.2 * t_slash - 0.14 * t_tall)
	var r := PackedVector3Array()
	r.resize(JOINT_COUNT)
	r[HIPS] = Vector3(0.0, 0.28, 0.0)
	r[SPINE] = Vector3(-0.14 + _bal.x * 0.38 - _air * 0.12 - 0.2 * tuck - 0.3 * grab + drift_dir * 0.3 * drift + 0.08 * relaxed,
		0.0, 0.12 + 0.3 * boost + _bal.y * 0.12 - 0.05 * relaxed)
	r[CHEST] = Vector3(-0.06 - 0.1 * ride_tuck, 0.32 + 0.22 * boost, 0.05 * boost - _bal.x * 0.08)
	r[NECK] = Vector3(0.0, 0.2, 0.0)
	r[HEAD] = Vector3(0.12 - 0.08 * boost + 0.2 * grab - _bal.x * 0.15, 0.45, -0.1 + _bal.x * 0.1)
	# Arms out for balance, the leading one forward and the trailing one back. Carving
	# lifts the outside arm and lowers the inside one; the air opens them wide; a
	# landing drops them, then they spring back.
	var spread := (1.0 + 0.3 * drift - 0.45 * relaxed + 0.6 * _air) * ride_arm_spread
	var lift := clampf(_land_vel * 0.025, -0.3, 0.3)
	# Cruising like the reference rider: compact, elbows bent, hands at the hips a little
	# out to the sides (they show past the cloak); the air opens the arms up.
	r[SH_L] = Vector3(lerpf(0.38, 0.45, boost) + 0.05 * sway + _bal.y * 0.2 + 0.1 * _air, 0.0,
		(-lerpf(0.95, 0.55, boost) + _bal.x * 0.45 - lift) * spread)
	r[EL_L] = Vector3(lerpf(1.15, 0.35, boost) + 0.15 * relaxed - 0.6 * _air, 0.0, 0.0)
	r[HA_L] = Vector3(0.2, 0.0, -0.1)
	r[SH_R] = Vector3(lerpf(0.2, -0.6, boost) - 0.05 * sway - _bal.y * 0.2 - 0.05 * _air, 0.0,
		(lerpf(0.9, 0.45, boost) + _bal.x * 0.45 + lift) * spread)
	r[EL_R] = Vector3(lerpf(1.1, 0.3, boost) + 0.15 * relaxed - 0.55 * _air, 0.0, 0.0)
	r[HA_R] = Vector3(0.2, 0.0, 0.1)
	# Trick poses, each its own shape: tucked (arms hug the knees), stretched out
	# (arched, arms wide), a leg kicked back (over the front foot, arms out), an arm
	# thrown up (rodeo), sunk low, standing tall on the upturned sword (arms up),
	# holding the sword out like a staff, slashing the sand, pressing the nose.
	var tk: float = tp.get(&"tuck", 0.0)
	var ex: float = tp.get(&"extend", 0.0)
	var kk: float = tp.get(&"kick", 0.0)
	var au: float = tp.get(&"arm_up", 0.0)
	var st: float = tp.get(&"staff", 0.0)
	if tk + ex + kk + au + st + t_crouch + t_tall + t_press + t_slash > 0.001:
		r[SPINE] += Vector3(-0.38 * tk + 0.24 * ex - 0.22 * kk - 0.3 * t_crouch + 0.1 * t_tall - 0.45 * t_press - 0.35 * t_slash, 0.12 * st, 0.0)
		r[HEAD] += Vector3(0.28 * tk - 0.22 * ex + 0.1 * kk - 0.15 * t_tall + 0.3 * t_press + 0.2 * t_slash, 0.0, 0.0)
		r[CHEST] += Vector3(-0.1 * t_crouch, -0.2 * st, 0.0)
		r[SH_L] = r[SH_L].lerp(Vector3(0.95, 0.0, -0.25), tk).lerp(Vector3(0.15, 0.0, -1.35), ex).lerp(Vector3(0.55, 0.0, -1.0), kk)
		r[SH_R] = r[SH_R].lerp(Vector3(0.95, 0.0, 0.25), tk).lerp(Vector3(-0.1, 0.0, 1.35), ex).lerp(Vector3(-0.45, 0.0, 1.05), kk)
		r[EL_L] = r[EL_L].lerp(Vector3(1.2, 0.0, 0.0), tk).lerp(Vector3(0.15, 0.0, 0.0), ex).lerp(Vector3(0.3, 0.0, 0.0), kk)
		r[EL_R] = r[EL_R].lerp(Vector3(1.2, 0.0, 0.0), tk).lerp(Vector3(0.15, 0.0, 0.0), ex).lerp(Vector3(0.35, 0.0, 0.0), kk)
		# One arm high overhead, the other out to the side.
		r[SH_L] = r[SH_L].lerp(Vector3(2.65, 0.0, -0.3), au)
		r[EL_L] = r[EL_L].lerp(Vector3(0.15, 0.0, 0.0), au)
		r[SH_R] = r[SH_R].lerp(Vector3(0.35, 0.0, 1.15), au * (1.0 - t_tall))
		# Both arms up and wide on the upturned sword.
		r[SH_R] = r[SH_R].lerp(Vector3(2.3, 0.0, 0.5), t_tall)
		r[EL_R] = r[EL_R].lerp(Vector3(0.2, 0.0, 0.0), t_tall)
		# The sword held out in the right hand, the left arm out for balance.
		r[SH_R] = r[SH_R].lerp(Vector3(1.0, 0.0, 0.8), st)
		r[EL_R] = r[EL_R].lerp(Vector3(0.25, 0.0, 0.0), st)
		r[SH_L] = r[SH_L].lerp(Vector3(0.45, 0.0, -1.25), st)
		r[EL_L] = r[EL_L].lerp(Vector3(0.3, 0.0, 0.0), st)
		# Low over the front foot, the leading arm pointing ahead, the other back.
		r[SH_L] = r[SH_L].lerp(Vector3(1.35, 0.0, -0.2), t_press)
		r[SH_R] = r[SH_R].lerp(Vector3(-0.7, 0.0, 0.45), t_press)
		# Sunk low (rodeo): arms forward, elbows bent, unless one is thrown up.
		r[SH_R] = r[SH_R].lerp(Vector3(0.6, 0.0, 0.7), t_crouch * (1.0 - au))
		r[EL_R] = r[EL_R].lerp(Vector3(0.9, 0.0, 0.0), t_crouch * (1.0 - au))
	# Flicking the sword (kickflip, shove-it): she watches it turn under her feet, the
	# torso a little back over the kick, the arms out to balance.
	var fl: float = tp.get(&"flick", 0.0)
	if fl > 0.001:
		r[SPINE] += Vector3(0.1, 0.0, 0.0) * fl
		r[HEAD] += Vector3(0.38, -0.25, 0.0) * fl
		r[SH_L] = r[SH_L].lerp(Vector3(0.55, 0.0, -1.15), fl)
		r[EL_L] = r[EL_L].lerp(Vector3(0.45, 0.0, 0.0), fl)
		r[SH_R] = r[SH_R].lerp(Vector3(0.0, 0.0, 1.2), fl)
		r[EL_R] = r[EL_R].lerp(Vector3(0.4, 0.0, 0.0), fl)
	# Anticipation: the head and chest turn into the turn as soon as it is asked for.
	r[HEAD] += Vector3(0.0, steer_lead * 0.3, -steer_lead * 0.08)
	r[CHEST] += Vector3(0.0, steer_lead * 0.12, 0.0)
	# Cruising styles (MotionContext): crouch low like a skier, point the way ahead,
	# glance back over the shoulder, open the arms wide.
	var sw := c.board_style_w if c else 0.0
	if sw > 0.001:
		match c.board_style:
			0:
				r[SPINE] += Vector3(-0.22, 0.0, 0.0) * sw
				r[SH_L] = r[SH_L].lerp(Vector3(-0.5, 0.0, -0.35), sw)
				r[SH_R] = r[SH_R].lerp(Vector3(-0.55, 0.0, 0.35), sw)
			1:
				r[SH_L] = r[SH_L].lerp(Vector3(1.25, 0.0, -0.3), sw)
				r[EL_L] = r[EL_L].lerp(Vector3(0.12, 0.0, 0.0), sw)
				r[HEAD] += Vector3(0.0, 0.25, 0.0) * sw
			2:
				r[HEAD] += Vector3(0.05, -0.9, 0.0) * sw
				r[CHEST] += Vector3(0.0, -0.3, 0.0) * sw
			3:
				r[SH_L] = r[SH_L].lerp(Vector3(0.1, 0.0, -1.35), sw)
				r[SH_R] = r[SH_R].lerp(Vector3(-0.05, 0.0, 1.35), sw)
				r[EL_L] = r[EL_L].lerp(Vector3(0.2, 0.0, 0.0), sw)
				r[EL_R] = r[EL_R].lerp(Vector3(0.2, 0.0, 0.0), sw)
	# Swinging the sword: the chest turns into the blade's direction, the spine folds over
	# a downward strike and arches under an overhead one, and the free arm balances out
	# (unless it joins on the grip).
	if blade_w > 0.001:
		var d := blade_dir.normalized()
		var twist := clampf(-atan2(d.x, -d.z), -1.2, 1.2)
		r[CHEST] += Vector3(0.0, twist * 0.45, 0.0) * blade_w
		r[SPINE] += Vector3(-0.42 * maxf(-d.y, 0.0) + 0.22 * maxf(d.y, 0.0), twist * 0.2, 0.0) * blade_w
		r[HEAD] += Vector3(0.25 * maxf(-d.y, 0.0), twist * 0.25, 0.0) * blade_w
		var free := blade_w * (1.0 - grip2)
		r[SH_L] = r[SH_L].lerp(Vector3(0.35, 0.0, -1.2), free)
		r[EL_L] = r[EL_L].lerp(Vector3(0.35, 0.0, 0.0), free)
	# Shaky landing: sway and counter-swinging arms, dying away.
	if _wob > 0.001:
		_wob_t += dt
		_wob = move_toward(_wob, 0.0, dt * 1.4)
		var osc := sin(_wob_t * 10.5) * _wob * _wob
		r[SPINE] += Vector3(0.05 * osc, 0.0, 0.24 * osc)
		r[HEAD] += Vector3(0.0, 0.0, -0.18 * osc)
		r[SH_L] += Vector3(0.25 * osc, 0.0, -0.55 * absf(osc) + 0.3 * osc)
		r[SH_R] += Vector3(-0.25 * osc, 0.0, 0.55 * absf(osc) + 0.3 * osc)
	for i in TH_L:
		p.e[i] = p.e[i].lerp(r[i], rw)
	# The hips drop toward the inside of a carve (+Z = heel side).
	p.hips = p.hips.lerp(Vector3(-0.1 * t_press, -crouch + 0.008 * sway, carve * 0.07), rw)
	p.feet[0] = p.feet[0].lerp(ride_feet[0], rw)
	p.feet[1] = p.feet[1].lerp(ride_feet[1], rw)
	p.leg_fk *= 1.0 - rw
	for side in 2:
		p.hand_w[side] *= 1.0 - rw
	if grab > 0.001:
		p.reach(0, (ride_feet[0] + ride_feet[1]) * 0.5 + Vector3(-0.05, 0.03, -0.17), grab * rw)
	# Hard carves: the inside hand trails toward the sand (leading hand on the toe side,
	# trailing hand on the heel side).
	# A sand slash (E in a carve) reaches right down and drags through the sand.
	var touch := maxf(smoothstep(0.55, 0.95, deep) * (1.0 - _air), t_slash) * rw
	if touch > 0.001:
		var mid := (ride_feet[0] + ride_feet[1]) * 0.5
		var cs := signf(carve) if absf(carve) > 0.02 else 1.0
		var side := 1 if cs > 0.0 else 0
		p.reach(side, mid + Vector3(0.12 if side == 1 else -0.12, 0.02 - 0.03 * t_slash, (0.34 + 0.08 * t_slash) * cs), touch * 0.9)
	# The sword hand out along the blade from the shoulder (the sword itself is placed in
	# that hand by PlayerVisual); the other hand just below it on a two-handed grip.
	if blade_w > 0.001:
		var d := blade_dir.normalized()
		var sh := _rest[HIPS] + p.hips + Vector3(0.105, _rest[SPINE].y + _rest[CHEST].y + 0.105, 0.0)
		var hand := sh + d * 0.46 + Vector3(0.0, -0.05, 0.0)
		p.reach(1, hand, blade_w * rw)
		if grip2 > 0.001:
			p.reach(0, hand - d * 0.14, blade_w * grip2 * rw)


func _solve_and_apply(p: Pose, delta: float) -> void:
	_delta = delta
	var targets: Array[Quaternion] = []
	targets.resize(JOINT_COUNT)
	for i in JOINT_COUNT:
		targets[i] = p.base[i] * Quaternion.from_euler(p.e[i])
	# Smooth the pelvis first and solve the legs against the pelvis actually applied,
	# so planted feet don't drift when the hips sway or bounce.
	var k := 1.0 - exp(-joint_sharpness * delta)
	_hips_pos = _hips_pos.lerp(_rest[HIPS] + p.hips, k)
	_cur[HIPS] = _cur[HIPS].slerp(targets[HIPS], k)
	targets[HIPS] = _cur[HIPS]
	var hips_xf := Transform3D(Basis(_cur[HIPS]), _hips_pos)
	var up := ground_normal if ground_normal.y > 0.3 else Vector3.UP
	var slope := Basis(Quaternion(Vector3.UP, up))
	for side in 2:
		var s := -1.0 if side == 0 else 1.0
		var o := 0 if side == 0 else 3
		var foot_basis := (slope * Basis(Vector3.RIGHT, p.foot_pitch[side])).slerp(ride_feet_basis, ride_weight)
		var ik := _two_bone(hips_xf, _rest[TH_L + o], p.feet[side] + Vector3(0.0, 0.025, 0.0),
				thigh_length, shin_length, Vector3(s * 0.25, 0.0, -1.0), false)
		var thigh_q: Quaternion = ik[0]
		var knee_q: Quaternion = ik[1]
		var foot_q := ((hips_xf.basis * Basis(thigh_q) * Basis(knee_q)).inverse() * foot_basis).orthonormalized().get_rotation_quaternion()
		var fk := maxf(p.leg_fk, p.gait)
		targets[TH_L + o] = thigh_q.slerp(targets[TH_L + o], fk)
		targets[KN_L + o] = knee_q.slerp(targets[KN_L + o], fk)
		targets[FT_L + o] = foot_q.slerp(targets[FT_L + o], fk)
		if p.gait > 0.001:
			_fit_to_slope(hips_xf, side, targets, p.gait)
			_lock_foot(hips_xf, side, targets, p.gait)
		else:
			_locked[side] = false
			_lock_w[side] = 0.0
	# Hands reaching for a point (sand, knee, board edge).
	var chest_xf := hips_xf * Transform3D(Basis(targets[SPINE]), _rest[SPINE]) * Transform3D(Basis(targets[CHEST]), _rest[CHEST])
	for side in 2:
		var w: float = p.hand_w[side]
		if w <= 0.001:
			continue
		var s := -1.0 if side == 0 else 1.0
		var o := 0 if side == 0 else 3
		var ik := _two_bone(chest_xf, _rest[SH_L + o], p.hands[side],
				upper_arm_length, forearm_length + 0.04, Vector3(s * 0.6, 0.0, 1.0), true)
		targets[SH_L + o] = targets[SH_L + o].slerp(ik[0], w)
		targets[EL_L + o] = targets[EL_L + o].slerp(ik[1], w)
		targets[HA_L + o] = targets[HA_L + o].slerp(Quaternion.from_euler(Vector3(0.3, 0.0, s * 0.2)), w)

	skeleton.set_bone_pose_position(HIPS, _hips_pos)
	var kl := 1.0 - exp(-leg_sharpness * delta)
	for i in JOINT_COUNT:
		_cur[i] = _cur[i].slerp(targets[i], kl if i >= TH_L and p.leg_fk < 0.5 else k)
		skeleton.set_bone_pose_rotation(i, _cur[i])
	_update_sockets()


## Keeps a captured leg pose but moves its foot onto the sloped ground plane (same knee
## direction), so feet neither sink into nor float above the dunes.
func _fit_to_slope(hips_xf: Transform3D, side: int, targets: Array[Quaternion], w: float) -> void:
	var o := 0 if side == 0 else 3
	var th := hips_xf * Transform3D(Basis(targets[TH_L + o]), _rest[TH_L + o])
	var kn := th * Transform3D(Basis(targets[KN_L + o]), _rest[KN_L + o])
	var ankle := kn * _rest[FT_L + o]
	var lift := _ground_y(ankle.x, ankle.z)
	if absf(lift) < 0.004:
		return
	var foot_global := kn.basis * Basis(targets[FT_L + o])
	var mid := (th.origin + ankle) * 0.5
	var pole := kn.origin - mid
	if pole.length_squared() < 0.000001:
		pole = Vector3.FORWARD
	var ik := _two_bone(hips_xf, _rest[TH_L + o], ankle + Vector3(0.0, lift, 0.0),
			thigh_length, shin_length, pole.normalized(), false)
	var thigh_q: Quaternion = ik[0]
	var knee_q: Quaternion = ik[1]
	var foot_q := ((hips_xf.basis * Basis(thigh_q) * Basis(knee_q)).inverse() * foot_global).orthonormalized().get_rotation_quaternion()
	targets[TH_L + o] = targets[TH_L + o].slerp(thigh_q, w)
	targets[KN_L + o] = targets[KN_L + o].slerp(knee_q, w)
	targets[FT_L + o] = targets[FT_L + o].slerp(foot_q, w)


## Foot locking: when a captured foot touches down, its world position is pinned and
## the leg is solved toward it until the foot lifts, so it can't slide on the sand.
func _lock_foot(hips_xf: Transform3D, side: int, targets: Array[Quaternion], g: float) -> void:
	var o := 0 if side == 0 else 3
	var th := hips_xf * Transform3D(Basis(targets[TH_L + o]), _rest[TH_L + o])
	var kn := th * Transform3D(Basis(targets[KN_L + o]), _rest[KN_L + o])
	var ankle := kn * _rest[FT_L + o]
	var gx := global_transform
	var planted := foot_planted[side] and is_inside_tree()
	if planted and not _locked[side]:
		_locked[side] = true
		_lock_world[side] = gx * ankle
	var target := gx.affine_inverse() * _lock_world[side] if _locked[side] else ankle
	# Release when the foot lifts, or if the pin would overstretch the leg.
	if _locked[side] and (not planted or target.distance_to(ankle) > 0.22):
		_locked[side] = false
	_lock_w[side] = move_toward(_lock_w[side], 1.0 if _locked[side] else 0.0, _delta / 0.06)
	var w := _lock_w[side] * g
	if w < 0.001 or not _locked[side] and _lock_w[side] <= 0.0:
		return
	if not _locked[side]:
		return
	var foot_global := kn.basis * Basis(targets[FT_L + o])
	var mid := (th.origin + ankle) * 0.5
	var pole := kn.origin - mid
	if pole.length_squared() < 0.000001:
		pole = Vector3.FORWARD
	var ik := _two_bone(hips_xf, _rest[TH_L + o], target, thigh_length, shin_length, pole.normalized(), false)
	var thigh_q: Quaternion = ik[0]
	var knee_q: Quaternion = ik[1]
	var foot_q := ((hips_xf.basis * Basis(thigh_q) * Basis(knee_q)).inverse() * foot_global).orthonormalized().get_rotation_quaternion()
	targets[TH_L + o] = targets[TH_L + o].slerp(thigh_q, w)
	targets[KN_L + o] = targets[KN_L + o].slerp(knee_q, w)
	targets[FT_L + o] = targets[FT_L + o].slerp(foot_q, w)


## Two-bone IK. `root` is the joint position in the space described by `parent_xf`;
## returns [root rotation, middle-joint rotation]. Legs bend the knee toward `pole`
## (forward); arms (`arm` = true) bend the elbow toward a backward pole.
func _two_bone(parent_xf: Transform3D, root: Vector3, target_model: Vector3, l1: float, l2: float,
		pole_model: Vector3, arm: bool) -> Array:
	var target := parent_xf.affine_inverse() * target_model
	var d := target - root
	var dist := clampf(d.length(), 0.05, (l1 + l2) * 0.995)
	var dn := d.normalized()
	var pole := (parent_xf.basis.inverse() * pole_model).normalized()
	var perp := pole - dn * pole.dot(dn)
	if perp.length_squared() < 0.0001:
		perp = Vector3.FORWARD
	perp = perp.normalized()
	var a := acos(clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0))
	var dir := dn * cos(a) + perp * sin(a)
	var y_axis := -dir
	var po := (perp - dir * perp.dot(dir)).normalized()
	var z_axis := po if arm else -po
	var x_axis := y_axis.cross(z_axis)
	var basis := Basis(x_axis, y_axis, z_axis).orthonormalized()
	var bend := PI - acos(clampf((l1 * l1 + l2 * l2 - dist * dist) / (2.0 * l1 * l2), -1.0, 1.0))
	return [basis.get_rotation_quaternion(), Quaternion(Vector3.RIGHT, bend if arm else -bend)]


func _update_sockets() -> void:
	var chest_pose := skeleton.get_bone_global_pose(CHEST)
	chest.transform = chest_pose.translated_local(Vector3(0.0, 0.04, 0.0))
	_neck_socket.transform = skeleton.get_bone_global_pose(NECK)
	_cape_xf = chest_pose.translated_local(Vector3(0.0, 0.1, 0.055))
	if is_inside_tree():
		var gx := global_transform
		hand_world[0] = gx * (skeleton.get_bone_global_pose(HA_L) * Vector3(0.0, -0.05, 0.0))
		hand_world[1] = gx * (skeleton.get_bone_global_pose(HA_R) * Vector3(0.0, -0.05, 0.0))
