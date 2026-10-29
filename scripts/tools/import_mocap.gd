extends SceneTree
## Offline step: turns CMU motion-capture clips (BVH) into looping MotionCycle
## resources retargeted onto the spirit's skeleton.
##   Godot --headless --path . --script res://scripts/tools/import_mocap.gd
##
## Retargeting is direction-based: every spirit bone is oriented so it points where the
## matching human bone points, with the knee/elbow bend axis taken from the limb's
## plane. This is independent of the capture's rest pose and of bone lengths; the hips
## trajectory is scaled by the leg-length ratio. One clean cycle is found by
## autocorrelation of the left ankle height, phase 0 is set at left-foot contact, the
## loop is closed seamlessly and resampled to a fixed number of samples.

const SRC := "res://assets/mocap/raw/"
const DST := "res://assets/mocap/"
# name, file, min period (s), max period (s)
const CLIPS := [
	["walk", "35_01.bvh", 0.8, 1.5],
	["jog", "35_17.bvh", 0.5, 0.95],
	["run", "09_01.bvh", 0.45, 0.85],
	["run_b", "09_06.bvh", 0.45, 0.85],
]
const SAMPLES := 48

var M := SpiritModel


func _init() -> void:
	var model := SpiritModel.new()
	var leg_len := model.thigh_length + model.shin_length
	for c in CLIPS:
		var bvh := BvhData.load_file(SRC + String(c[1]))
		if bvh == null:
			continue
		var cycle := _build(bvh, String(c[0]), float(c[2]), float(c[3]), leg_len)
		if cycle:
			var err := ResourceSaver.save(cycle, DST + String(c[0]) + ".res")
			print("[import_mocap] %-6s period %.3fs  stride %.2fm  speed@scale %.2f m/s  (err %d)" % [
				c[0], cycle.source_period, cycle.stride, cycle.stride / cycle.source_period, err])
	model.free()
	quit()


func _j(bvh: BvhData, n: String) -> int:
	var i := bvh.index_of(n)
	assert(i >= 0, "missing joint " + n)
	return i


func _build(bvh: BvhData, clip: String, pmin: float, pmax: float, leg_len: float) -> MotionCycle:
	# The first frames of these files hold the T-pose reference: skip them.
	var skip := 8
	var count := bvh.frames.size() - skip
	var P: Array[PackedVector3Array] = []
	for f in count:
		P.append(bvh.positions(f + skip))
	var hips := _j(bvh, "Hips")
	var lup := _j(bvh, "LeftUpLeg")
	var lleg := _j(bvh, "LeftLeg")
	var lfoot := _j(bvh, "LeftFoot")
	var rfoot := _j(bvh, "RightFoot")

	# Period by autocorrelation of the left ankle height.
	var fps := 1.0 / bvh.frame_time
	var lo := int(pmin * fps)
	var hi := mini(int(pmax * fps), count - 2)
	var best_lag := lo
	var best := -INF
	for lag in range(lo, hi + 1):
		var s := 0.0
		var n := 0
		for f in range(0, count - lag):
			var d := P[f][lfoot].y - P[f + lag][lfoot].y
			s -= d * d
			n += 1
		if n > 0 and s / n > best:
			best = s / n
			best_lag = lag
	var period := best_lag
	if count < period + 2:
		push_error("clip %s too short for one cycle" % clip)
		return null
	# Start at a left-foot contact (ankle lowest) inside the window that still fits a cycle.
	var f0 := 0
	var lowest := INF
	for f in range(0, count - period - 1):
		if P[f][lfoot].y < lowest:
			lowest = P[f][lfoot].y
			f0 = f
	if f0 + period >= count:
		f0 = count - period - 1

	# Character frame: travel direction -> -Z, origin at the start hips XZ.
	var travel := P[f0 + period][hips] - P[f0][hips]
	travel.y = 0.0
	var yaw := atan2(-travel.x, -travel.z)
	var to_char := Basis(Vector3.UP, -yaw)
	var origin := Vector3(P[f0][hips].x, 0.0, P[f0][hips].z)
	var scale := leg_len / (bvh.offsets[lleg].length() + bvh.offsets[lfoot].length())
	var floor_y := INF
	for f in range(f0, f0 + period + 1):
		floor_y = minf(floor_y, minf(P[f][lfoot].y, P[f][rfoot].y))

	var cycle := MotionCycle.new()
	cycle.clip_name = clip
	cycle.samples = SAMPLES
	cycle.source_period = period / fps
	cycle.stride = travel.length() * scale
	cycle.leg_length = leg_len
	cycle.rotations.resize(SAMPLES * 17 * 4)
	cycle.hips.resize(SAMPLES)
	cycle.contacts.resize(SAMPLES)

	var first: Array[Quaternion] = []
	var last: Array[Quaternion] = []
	var first_hips := Vector3.ZERO
	var last_hips := Vector3.ZERO
	var all_q: Array = []
	var all_h: Array[Vector3] = []
	for s in SAMPLES + 1:
		var t := f0 + float(period) * s / SAMPLES
		var fa := int(floorf(t))
		var fb := mini(fa + 1, count - 1)
		var w := t - fa
		var pos := PackedVector3Array()
		pos.resize(P[fa].size())
		var lin := float(s) / SAMPLES
		for j in pos.size():
			var p := P[fa][j].lerp(P[fb][j], w)
			# Remove the steady forward travel; keep the oscillation around it.
			p -= origin + travel * lin
			pos[j] = to_char * p
		var q := _retarget(bvh, pos)
		var hp := pos[hips] * scale
		hp.y = (pos[hips].y + origin.y - floor_y) * scale + 0.03
		all_q.append(q)
		all_h.append(hp)
	first = all_q[0]
	last = all_q[SAMPLES]
	first_hips = all_h[0]
	last_hips = all_h[SAMPLES]
	# Seamless loop: spread the end-to-start mismatch across the cycle.
	for s in SAMPLES:
		var k := float(s) / SAMPLES
		var q: Array[Quaternion] = all_q[s]
		for b in 17:
			var delta: Quaternion = last[b].inverse() * first[b]
			var fixed: Quaternion = q[b] * Quaternion.IDENTITY.slerp(delta, k)
			var i := (s * 17 + b) * 4
			cycle.rotations[i] = fixed.x
			cycle.rotations[i + 1] = fixed.y
			cycle.rotations[i + 2] = fixed.z
			cycle.rotations[i + 3] = fixed.w
		cycle.hips[s] = all_h[s] + (first_hips - last_hips) * k
	# Foot contacts: foot low and nearly still relative to the ground.
	for s in SAMPLES:
		var t := f0 + float(period) * s / SAMPLES
		var fa := int(floorf(t))
		var c := Vector2.ZERO
		for side in 2:
			var foot := lfoot if side == 0 else rfoot
			var h := (P[fa][foot].y - floor_y) * scale
			var v := (P[mini(fa + 1, count - 1)][foot] - P[fa][foot]) * scale * fps
			v.y = 0.0
			var low := 1.0 - smoothstep(0.02, 0.06, h)
			var still := 1.0 - smoothstep(0.6, 1.6, v.length())
			c[side] = low * still
		cycle.contacts[s] = c
	return cycle


## Spirit-skeleton local rotations for one frame of character-space joint positions.
func _retarget(bvh: BvhData, p: PackedVector3Array) -> Array[Quaternion]:
	var J := func(n: String) -> Vector3: return p[_j(bvh, n)]
	var right_hips: Vector3 = (J.call("RightUpLeg") - J.call("LeftUpLeg")).normalized()
	var right_chest: Vector3 = (J.call("RightArm") - J.call("LeftArm")).normalized()
	var g: Array[Basis] = []
	g.resize(17)
	g[M.HIPS] = _frame(right_hips, J.call("Spine") - J.call("Hips"))
	g[M.SPINE] = _frame((right_hips + right_chest).normalized(), J.call("Spine1") - J.call("Hips"))
	g[M.CHEST] = _frame(right_chest, J.call("Neck1") - J.call("Spine1"))
	g[M.NECK] = _frame(right_chest, J.call("Head") - J.call("Neck1"))
	g[M.HEAD] = _frame(right_chest, J.call("Head_End") - J.call("Head"))
	for side in 2:
		var L := "Left" if side == 0 else "Right"
		var o := 0 if side == 0 else 3
		var arm := _limb(J.call(L + "Arm"), J.call(L + "ForeArm"), J.call(L + "Hand"), right_chest, 1.0)
		g[M.SH_L + o] = arm[0]
		g[M.EL_L + o] = arm[1]
		var hand_dir: Vector3 = J.call(L + "HandIndex1") - J.call(L + "Hand")
		g[M.HA_L + o] = _limb_basis(hand_dir, arm[1].x)
		var leg := _limb(J.call(L + "UpLeg"), J.call(L + "Leg"), J.call(L + "Foot"), right_hips, -1.0)
		g[M.TH_L + o] = leg[0]
		g[M.KN_L + o] = leg[1]
		var toe: Vector3 = (J.call(L + "ToeBase") - J.call(L + "Foot")).normalized()
		var z := -toe
		var x: Vector3 = (leg[1].x - z * leg[1].x.dot(z)).normalized()
		g[M.FT_L + o] = Basis(x, z.cross(x), z).orthonormalized()
	var out: Array[Quaternion] = []
	out.resize(17)
	for i in 17:
		var parent: int = SpiritModel.PARENT[i]
		var local := g[i] if parent < 0 else g[parent].inverse() * g[i]
		out[i] = local.orthonormalized().get_rotation_quaternion()
	return out


## Basis with +Y along `up` and +X as close as possible to `right` (+Z = back).
func _frame(right: Vector3, up: Vector3) -> Basis:
	var y := up.normalized()
	var x := (right - y * right.dot(y)).normalized()
	return Basis(x, y, x.cross(y)).orthonormalized()


## Bone pointing along `dir` (local -Y), bend axis (local +X) close to `x_ref`.
func _limb_basis(dir: Vector3, x_ref: Vector3) -> Basis:
	var y := -dir.normalized()
	var x := (x_ref - y * x_ref.dot(y))
	if x.length_squared() < 0.0001:
		x = Vector3.RIGHT - y * y.x
	x = x.normalized()
	return Basis(x, y, x.cross(y)).orthonormalized()


## Upper and lower limb bases; the bend axis comes from the limb plane (sign: arms +1,
## legs -1, matching the spirit's elbow-forward / knee-forward convention), falling
## back to `fallback` when the limb is straight.
func _limb(a: Vector3, b: Vector3, c: Vector3, fallback: Vector3, sign: float) -> Array:
	var d1 := (b - a).normalized()
	var d2 := (c - b).normalized()
	var n := d1.cross(d2) * sign
	var bendiness := clampf(n.length() / 0.25, 0.0, 1.0)
	var axis := fallback.lerp(n.normalized() if n.length() > 0.0001 else fallback, bendiness)
	# Keep the axis on the same side as the fallback (no flips when nearly straight).
	if axis.dot(fallback) < 0.0 and bendiness < 0.5:
		axis = fallback
	return [_limb_basis(d1, axis), _limb_basis(d2, axis)]
