class_name Ribbons
extends MeshInstance3D
## Long, flowing strips of torn cloak fabric trailing from the shoulders (`ribbons`),
## plus optional strands from the back of the head (`head_locks`).
##
## Art-directed rather than simulated: each ribbon is a smooth curve whose direction
## comes from a "flow" (gravity + airflow from the body's motion + inertia + a steady
## side wind with gusts, the same breeze that billows the cloak, so even at rest the
## strips stream far out to one side as on the concept art). Points further down the
## ribbon read the flow from further in the
## past, so the tail follows through and swings out naturally in turns, then settles.
## A travelling wave adds the flowing motion. The curve is smoothed with Catmull-Rom,
## framed by parallel transport (it never flips or twists abruptly), given a leaf-like
## taper and a slightly cupped cross-section so it has volume and catches light.

@export var ribbon_material: Material
@export_group("Shape")
## Per ribbon: x = lateral offset at the back, y = length, z = widest width, w = tint (0..1).
@export var ribbons: Array[Vector4] = [Vector4(-0.15, 1.45, 0.12, 0.0), Vector4(0.16, 1.25, 0.11, 1.0),
		Vector4(-0.07, 1.1, 0.095, 0.5), Vector4(0.08, 0.92, 0.085, 0.3)]
## Locks of hair from the back of the head, same layout as `ribbons`.
@export var head_locks: Array[Vector4] = []
@export var control_points := 14
@export var subdivisions := 3
@export var cup := 0.22
@export_group("Flow")
## Seconds of delay between the root and the tip (follow-through).
@export var tail_delay := 0.38
@export var air_strength := 0.18
@export var air_cap := 14.0
@export var inertia := 0.04
@export var current_strength := 0.35
## Steady world-space wind (direction, strength at rest) with gusts: light strips
## stream almost level in it. Keep the direction in step with Cloak.wind_dir.
@export var wind_dir := Vector3(1.0, 0.0, 0.35)
@export var idle_wind := 1.25
@export var gusts := 0.35
@export var spread := 0.32
## Minimum distance kept between the two ribbons (grows toward the tips).
@export var min_gap := 0.09
@export_group("Wave")
@export var wave_amplitude := 0.12
@export var wave_speed_gain := 0.012
@export var wave_frequency := 1.6
@export var wave_length := 0.65
@export var twist := 0.8

## Raised by gameplay (sprint, boost, dash) for livelier motion.
var excitement := 0.0
var model: SpiritModel
## Control points of each ribbon in this node's space (read by tests).
var points: Array[PackedVector3Array] = []

var _imesh := ImmediateMesh.new()
var _time := 0.0
var _hist_t: Array[float] = []
var _hist_flow: Array[Vector3] = []
var _v := Vector3.ZERO
var _a := Vector3.ZERO
var _last_pos := Vector3.ZERO
var _initialized := false


func _ready() -> void:
	mesh = _imesh
	material_override = ribbon_material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func reset() -> void:
	_hist_t.clear()
	_hist_flow.clear()
	_v = Vector3.ZERO
	_a = Vector3.ZERO
	if model:
		_last_pos = model.global_position
	_initialized = true


## Called by PlayerVisual after the model has been posed this frame.
func step(delta: float) -> void:
	if model == null or delta <= 0.0:
		return
	transform = model.transform
	if not _initialized:
		reset()
	_time += delta
	var pos := model.global_position
	if pos.distance_to(_last_pos) > 6.0:
		reset()
	var v_raw := (pos - _last_pos) / delta
	_last_pos = pos
	var v_new := _v.lerp(v_raw, 1.0 - exp(-10.0 * delta))
	_a = _a.lerp(((v_new - _v) / delta).limit_length(25.0), 1.0 - exp(-6.0 * delta))
	_v = v_new

	# World-space flow direction for this instant.
	var speed := minf(_v.length(), air_cap)
	var air := -_v.normalized() * speed * air_strength if _v.length() > 0.05 else Vector3.ZERO
	var calm := 1.0 - clampf(speed / 3.0, 0.0, 1.0)
	var current := Vector3(sin(_time * 0.6) * 0.5, 0.35 + 0.25 * sin(_time * 0.43), 0.0) * current_strength * calm
	var gust := 1.0 + gusts * (sin(_time * 0.9) * 0.6 + sin(_time * 2.3 + 1.0) * 0.4)
	var side_wind := wind_dir.normalized() * idle_wind * gust * (0.35 + 0.65 * calm)
	var flow := Vector3.DOWN + air + side_wind - _a * inertia + model.global_basis * (Vector3(0.0, 0.0, 0.25) + current)
	_hist_t.append(_time)
	_hist_flow.append(flow)
	while _hist_t.size() > 2 and _time - _hist_t[1] > tail_delay + 0.1:
		_hist_t.pop_front()
		_hist_flow.pop_front()
	_build_curves()
	_rebuild()


func _flow_at(t: float) -> Vector3:
	var n := _hist_t.size()
	if n == 0:
		return Vector3.DOWN
	if t <= _hist_t[0]:
		return _hist_flow[0]
	for i in range(n - 1, 0, -1):
		if _hist_t[i - 1] <= t:
			var k := inverse_lerp(_hist_t[i - 1], _hist_t[i], t)
			return _hist_flow[i - 1].lerp(_hist_flow[i], clampf(k, 0.0, 1.0))
	return _hist_flow[n - 1]


func _build_curves() -> void:
	var to_local := model.global_basis.inverse()
	var speed01 := clampf(_v.length() / 10.0, 0.0, 1.0)
	var all := _all_specs()
	points.resize(all.size())
	var sk := model.skeleton
	var hips := sk.get_bone_global_pose(SpiritModel.HIPS).origin
	var neck := sk.get_bone_global_pose(SpiritModel.NECK).origin
	for r in all.size():
		var spec: Vector4 = all[r]
		var side := signf(spec.x)
		var n := control_points
		var seg := spec.y / float(n - 1)
		var pts := PackedVector3Array()
		pts.resize(n)
		var anchor := model.cape_anchor() if r < ribbons.size() else model.head_anchor()
		var root := anchor * Vector3(spec.x, 0.0, 0.0)
		# Leaves the back (or the nape) pointing down and slightly out and back.
		var root_dir := (anchor.basis * (Vector3(side * 0.4, -1.0, 0.3) if r < ribbons.size() else Vector3(side * 0.15, -1.0, 0.55))).normalized()
		pts[0] = root
		var p := root
		for i in range(1, n):
			var s := float(i) / float(n - 1)
			var f := to_local * _flow_at(_time - s * tail_delay * (0.7 + 0.3 * r))
			f += Vector3(side * spread * s, 0.0, 0.0)
			var d := root_dir.slerp(f.normalized(), smoothstep(0.0, 0.3, s)).normalized()
			var prev := p
			p += d * seg
			# Never pass through the torso: nudge the curve out behind the body,
			# then restore the segment length so the ribbon never stretches.
			p = _clear_body(p, hips, neck)
			p = prev + (p - prev).normalized() * seg
			pts[i] = p
		# Travelling wave, growing toward the tip.
		# Faster = straighter streaming with a quicker, small flutter.
		var amp := wave_amplitude * (1.0 + excitement) + minf(wave_speed_gain * _v.length(), 0.1)
		for i in range(1, n):
			var s := float(i) / float(n - 1)
			var t0 := (pts[i] - pts[i - 1]).normalized()
			var lateral := t0.cross(Vector3.UP)
			if lateral.length_squared() < 0.01:
				lateral = Vector3.RIGHT
			lateral = lateral.normalized()
			var normal := lateral.cross(t0).normalized()
			var ph := TAU * (wave_frequency * _time * (1.0 + speed01) - s / wave_length) + r * 1.7
			pts[i] += (lateral * sin(ph) + normal * 0.8 * sin(ph * 0.6 + 1.0 + r)) * amp * pow(s, 1.25)
		points[r] = pts
	_separate()
	# The wave and the separation move points sideways: restore every segment's length
	# so the strips undulate instead of stretching.
	for r in points.size():
		var pts := points[r]
		var seg: float = all[r].y / float(pts.size() - 1)
		for i in range(1, pts.size()):
			var d := pts[i] - pts[i - 1]
			if d.length_squared() > 0.000001:
				pts[i] = pts[i - 1] + d.normalized() * seg
		points[r] = pts


func _all_specs() -> Array[Vector4]:
	var all: Array[Vector4] = ribbons.duplicate()
	all.append_array(head_locks)
	return all


## Ribbons always read as separate strands: matching points keep a minimum lateral gap.
func _separate() -> void:
	for ia in points.size():
		for ib in range(ia + 1, points.size()):
			var a := points[ia]
			var b := points[ib]
			var n := mini(a.size(), b.size())
			for i in range(2, n):
				var s := float(i) / float(n - 1)
				var want := min_gap * (0.6 + 0.8 * s)
				var d := b[i] - a[i]
				d.y = 0.0
				var l := d.length()
				if l < want:
					var dir := d / l if l > 0.0001 else Vector3.RIGHT
					var push := dir * (want - l) * 0.5
					a[i] -= push
					b[i] += push
			points[ia] = a
			points[ib] = b


func _clear_body(p: Vector3, hips: Vector3, chest: Vector3) -> Vector3:
	var ab := chest - hips
	var t := clampf((p - hips).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var c := hips + ab * t
	var d := p - c
	var r := 0.12
	if d.length() < r:
		d.y = 0.0
		if d.length_squared() < 0.0001:
			d = Vector3.BACK
		return c + d.normalized() * r + Vector3(0.0, p.y - c.y, 0.0)
	return p


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


func _width(r: int, s: float) -> float:
	var w: float = ribbons[r].z if r < ribbons.size() else head_locks[r - ribbons.size()].z
	return w * (0.45 + 0.55 * smoothstep(0.0, 0.22, s)) * pow(1.0 - s, 0.75) + 0.005


func _rebuild() -> void:
	_imesh.clear_surfaces()
	if points.is_empty():
		return
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in points.size():
		var ctrl := points[r]
		var n := ctrl.size()
		# Dense smooth curve.
		var curve := PackedVector3Array()
		for i in n - 1:
			var p0 := ctrl[maxi(i - 1, 0)]
			var p1 := ctrl[i]
			var p2 := ctrl[i + 1]
			var p3 := ctrl[mini(i + 2, n - 1)]
			for k in subdivisions:
				curve.append(_catmull(p0, p1, p2, p3, float(k) / subdivisions))
		curve.append(ctrl[n - 1])
		var m := curve.size()
		# Parallel-transported side vector, starting along the body's right.
		var side := Vector3.RIGHT
		var tint := Color(1, 1, 1, ribbons[r].w if r < ribbons.size() else head_locks[r - ribbons.size()].w)
		var prev_row: Array[Vector3] = []
		var prev_n: Array[Vector3] = []
		var prev_s := 0.0
		for i in m:
			var t := (curve[mini(i + 1, m - 1)] - curve[maxi(i - 1, 0)]).normalized()
			side = (side - t * side.dot(t))
			if side.length_squared() < 0.0001:
				side = Vector3.RIGHT
			side = side.normalized()
			var s := float(i) / float(m - 1)
			var tw := twist * s * sin(_time * 1.1 + r * 2.0) * (0.4 + excitement)
			var sd := side.rotated(t, tw)
			var nrm := t.cross(sd).normalized()
			var w := _width(r, s)
			var row: Array[Vector3] = [curve[i] - sd * w, curve[i] + nrm * w * cup, curve[i] + sd * w]
			var rn: Array[Vector3] = [(nrm - sd * cup).normalized(), nrm, (nrm + sd * cup).normalized()]
			if i > 0:
				for c in 2:
					_quad(prev_row[c], prev_row[c + 1], row[c], row[c + 1],
						prev_n[c], prev_n[c + 1], rn[c], rn[c + 1], prev_s, s, c, tint)
			prev_row = row
			prev_n = rn
			prev_s = s
	_imesh.surface_end()


func _quad(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3, na0: Vector3, na1: Vector3,
		nb0: Vector3, nb1: Vector3, s0: float, s1: float, col: int, tint: Color) -> void:
	var u0 := col * 0.5
	var u1 := u0 + 0.5
	_v3(a0, na0, Vector2(s0, u0), tint)
	_v3(a1, na1, Vector2(s0, u1), tint)
	_v3(b0, nb0, Vector2(s1, u0), tint)
	_v3(a1, na1, Vector2(s0, u1), tint)
	_v3(b1, nb1, Vector2(s1, u1), tint)
	_v3(b0, nb0, Vector2(s1, u0), tint)


func _v3(p: Vector3, n: Vector3, uv: Vector2, tint: Color) -> void:
	_imesh.surface_set_normal(n)
	_imesh.surface_set_color(tint)
	_imesh.surface_set_uv(uv)
	_imesh.surface_add_vertex(p)
