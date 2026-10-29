class_name Cloak
extends Node3D
## The wanderer's hooded cloak: one long mantle of heavy cloth flowing out of the hood's
## cowl, a clasp and the single point of light inside the hood.
##
## The mantle is a coarse grid of control points hanging from a ring around the
## shoulders, open at the front below the clasp in an inverted V. It is art-directed rather than simulated: each column follows
## a "flow" (gravity + air from the body's motion + inertia + a faint supernatural
## breeze), and points further down read the flow from further in the past, so the hem
## lags behind turns, streams back at speed and lifts on jumps. Columns are kept outside
## the body (torso, arms, legs as capsules) and coupled to their neighbours so the
## cloth stays one sheet. A steady side breeze keeps it billowing even at rest; at a
## sprint the wind takes the whole mantle, front panels included, and throws it back,
## uncovering the smoke body. Only the control points
## live on the CPU: cloak_cloth.gdshader turns a dense mesh into a smooth surface
## through them and adds the fold geometry. The hood is a deep rounded shell with soft
## folds and a rolled rim, built once as a signed distance field.

const HOOD_PATH := "res://assets/spirit/hood.res"
const HOOD_VERSION := 11
const MAX_CTRL := 400

@export var cloth_material: ShaderMaterial
@export var hood_material: ShaderMaterial
@export var clasp_material: Material
@export_group("Mantle")
@export var columns := 24
@export var rows := 15
@export var mesh_resolution := Vector2i(120, 72)
## Mantle length at the back and at the front edges (metres from the shoulders).
@export var back_length := 1.48
@export var front_length := 1.22
## Half-angle of the shoulder ring from the back (180 = closed at the front).
@export var ring_half_angle := 150.0
@export var ring_radius := Vector2(0.16, 0.16)
## Height of the shoulder ring above the chest joint (just under the hood's cowl).
@export var ring_height := 0.08
## How far the front edges swing apart below the clasp (opening over the smoke body).
@export var front_opening := 0.55
## How much the cloth widens toward the hem (a full, bell-like drape).
@export var hem_flare := 0.3
@export var fold_count := 11.0
@export var fold_depth := 0.08
@export_group("Flow")
@export var tail_delay := 0.3
@export var air_strength := 0.04
@export var air_cap := 10.0
@export var inertia := 0.035
@export var breeze := 0.18
## A steady world-space breeze (direction, strength) that billows the cloak to one side
## even when standing still, as on the concept art.
@export var wind_dir := Vector3(1.0, 0.0, 0.35)
@export var idle_wind := 0.3
## Extra air drag on the cloth at a full sprint (multiplies `air_strength`).
@export var sprint_wind := 4.0
@export var neighbour_coupling := 0.35
## How much less the wind moves the front panels than the back (they hang heavy in
## front of the body, so the cloak wraps the figure instead of flying like a cape).
@export_range(0.0, 1.0) var front_weight := 0.6
## Flutter of the cloth (travelling wave), stronger with speed.
@export var flutter := 0.03
@export var flutter_fast := 0.05
@export_group("Face light")
@export var face_color := Color(1.0, 0.5, 0.15)
@export var face_glow := 1.5
## Size of the hood on the head (the concept's hood is small for the tall body).
@export var hood_scale := 0.86

## Raised by gameplay (boost, dash) for livelier flutter.
var excitement := 0.0
## Sprint wind 0..1 (PlayerVisual: the boost level): blows the mantle back.
var wind := 0.0
## 0..1 while she spins or flips (PlayerVisual): the mantle flares out like a spinning
## skirt, front panels included, so her smoke body and limbs show through the trick.
var spin_flare := 0.0
## Briefly raised by gameplay (focus, impact): the face light flares.
var face_flare := 0.0
var model: SpiritModel
## Mantle control points (read by tests).
var _pts: Array[PackedVector3Array] = []


class Layer:
	var cols := 24
	var rows := 15
	var half_angle := 142.0
	var radius := Vector2(0.16, 0.16)
	var height := 0.08
	var len_back := 1.45
	var len_front := 1.2
	var opening := 0.7
	var lift := 0.0
	var lens: Array[float] = []
	var pts: Array[PackedVector3Array] = []
	var flat := PackedVector3Array()
	var mat: ShaderMaterial


var _layers: Array[Layer] = []
var _hood: MeshInstance3D
var _clasp: MeshInstance3D
var _star: MeshInstance3D
var _star_mat := ShaderMaterial.new()
var _time := 0.0
var _hist_t: Array[float] = []
var _hist_flow: Array[Vector3] = []
var _v := Vector3.ZERO
var _a := Vector3.ZERO
var _last_pos := Vector3.ZERO
var _initialized := false
var _front_w := 0.6


func _ready() -> void:
	var mantle := _add_layer(columns, rows, mesh_resolution, 0.0, fold_count, fold_depth, Vector2(2.2, back_length), 0.82, 12.0)
	mantle.half_angle = ring_half_angle
	mantle.radius = ring_radius
	mantle.height = ring_height
	mantle.len_back = back_length
	mantle.len_front = front_length
	mantle.opening = front_opening
	_hood = MeshInstance3D.new()
	_hood.name = "Hood"
	_hood.mesh = _hood_mesh()
	_hood.material_override = hood_material
	add_child(_hood)
	_clasp = MeshInstance3D.new()
	_clasp.name = "Clasp"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.016
	torus.outer_radius = 0.029
	torus.rings = 24
	torus.ring_segments = 8
	_clasp.mesh = torus
	_clasp.material_override = clasp_material
	add_child(_clasp)
	_star = MeshInstance3D.new()
	_star.name = "FaceLight"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.18, 0.18)
	_star.mesh = quad
	_star_mat.shader = load("res://shaders/face_star.gdshader")
	_star.material_override = _star_mat
	_star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_star)


func _add_layer(c: int, r: int, res: Vector2i, seed: float, folds: float, depth: float, size: Vector2,
		hem: float, strips: float) -> Layer:
	assert(c * r <= MAX_CTRL, "cloth layer has more control points than cloak_cloth.gdshader holds")
	var L := Layer.new()
	L.cols = c
	L.rows = r
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + int(seed)
	for i in c:
		L.lens.append(rng.randf_range(0.93, 1.05))
	L.mat = cloth_material.duplicate() as ShaderMaterial
	L.mat.set_shader_parameter("cols", c)
	L.mat.set_shader_parameter("rows", r)
	L.mat.set_shader_parameter("seed", seed)
	L.mat.set_shader_parameter("fold_count", folds)
	L.mat.set_shader_parameter("fold_depth", depth)
	L.mat.set_shader_parameter("cloth_size", size)
	L.mat.set_shader_parameter("hem_start", hem)
	L.mat.set_shader_parameter("strip_count", strips)
	var mi := MeshInstance3D.new()
	mi.name = "Mantle"
	mi.mesh = _grid(res.x, res.y)
	mi.material_override = L.mat
	# The real shape comes from the shader: never cull it.
	mi.custom_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	add_child(mi)
	_layers.append(L)
	return L


## A flat UV grid; the vertex shader places every vertex.
static func _grid(nu: int, nv: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	for j in nv:
		for i in nu:
			var uv := Vector2(float(i) / (nu - 1), float(j) / (nv - 1))
			verts.append(Vector3(uv.x, -uv.y, 0.0))
			uvs.append(uv)
			normals.append(Vector3.BACK)
	var idx := PackedInt32Array()
	for j in nv - 1:
		for i in nu - 1:
			var a := j * nu + i
			idx.append_array([a, a + 1, a + nu, a + 1, a + nu + 1, a + nu])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


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
	var v_new := _v.lerp((pos - _last_pos) / delta, 1.0 - exp(-10.0 * delta))
	_last_pos = pos
	_a = _a.lerp(((v_new - _v) / delta).limit_length(25.0), 1.0 - exp(-6.0 * delta))
	_v = v_new
	var speed := minf(_v.length(), air_cap)
	var drag := air_strength * (1.0 + sprint_wind * wind)
	var air := -_v.normalized() * speed * drag if _v.length() > 0.05 else Vector3.ZERO
	var calm := 1.0 - clampf(speed / 3.0, 0.0, 1.0)
	var gust := Vector3(sin(_time * 0.7) * 0.6, 0.25 + 0.2 * sin(_time * 0.53), cos(_time * 0.41) * 0.4) * breeze * (calm + 0.3)
	var side_wind := wind_dir.normalized() * idle_wind * (0.75 + 0.25 * sin(_time * 0.45)) * (0.4 + 0.6 * calm)
	# At a sprint the front panels lose their weight and go back with the rest.
	_front_w = front_weight * (1.0 - 0.9 * wind) * (1.0 - 0.85 * spin_flare)
	_hist_t.append(_time)
	_hist_flow.append(Vector3.DOWN + air + side_wind - _a * inertia + model.global_basis * gust)
	while _hist_t.size() > 2 and _time - _hist_t[1] > tail_delay + 0.1:
		_hist_t.pop_front()
		_hist_flow.pop_front()

	var sk := model.skeleton
	var head := sk.get_bone_global_pose(SpiritModel.HEAD)
	var chest := sk.get_bone_global_pose(SpiritModel.CHEST)
	_hood.transform = head.scaled_local(Vector3.ONE * hood_scale)
	_clasp.transform = chest * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, ring_height + 0.035, -ring_radius.y - 0.015))
	face_flare = move_toward(face_flare, 0.0, delta * 1.2)
	var glow := face_glow * (0.92 + 0.08 * sin(_time * 3.1) * sin(_time * 1.7)) * (1.0 + 1.5 * face_flare)
	var star_local := Vector3(0.0, 0.06, -0.12)
	_star.position = head * (star_local * hood_scale)
	_star.scale = Vector3.ONE * (1.0 + 0.6 * face_flare)
	_star_mat.set_shader_parameter("intensity", glow)
	_star_mat.set_shader_parameter("color", face_color)
	if hood_material:
		hood_material.set_shader_parameter("star_pos", star_local)
		hood_material.set_shader_parameter("star_glow", glow)
		hood_material.set_shader_parameter("star_color", face_color)

	_body_capsules()
	for L in _layers:
		_build_layer(L, chest)
	_pts = _layers[0].pts


func _flow_at(t: float) -> Vector3:
	var n := _hist_t.size()
	if n == 0:
		return Vector3.DOWN
	if t <= _hist_t[0]:
		return _hist_flow[0]
	for i in range(n - 1, 0, -1):
		if _hist_t[i - 1] <= t:
			return _hist_flow[i - 1].lerp(_hist_flow[i], clampf(inverse_lerp(_hist_t[i - 1], _hist_t[i], t), 0.0, 1.0))
	return _hist_flow[n - 1]


## Body volume the cloth must stay outside of, as capsules in model space (torso first,
## then arms and legs), kept in flat packed arrays: this runs for every control point
## twice a frame, so it avoids Variant lookups. `drape` capsules (the arms) are always
## covered: the cloth is pushed away from the torso over them, never tucked behind.
var _cap_a := PackedVector3Array()
var _cap_ab := PackedVector3Array()
var _cap_inv := PackedFloat32Array()
var _cap_r := PackedFloat32Array()
var _cap_mid := PackedVector3Array()
var _cap_reach := PackedFloat32Array()
var _cap_drape: Array[bool] = []


func _body_capsules() -> void:
	var sk := model.skeleton
	var g := func(b: int) -> Vector3: return sk.get_bone_global_pose(b).origin
	var raw := [[g.call(SpiritModel.HIPS), g.call(SpiritModel.NECK), 0.14, false]]
	for o in [0, 3]:
		raw.append([g.call(SpiritModel.SH_L + o), g.call(SpiritModel.EL_L + o), 0.095, true])
		# The forearm is not tented over: the hands come out of the cloak.
		raw.append([g.call(SpiritModel.EL_L + o), g.call(SpiritModel.HA_L + o), 0.07, false])
		raw.append([g.call(SpiritModel.TH_L + o), g.call(SpiritModel.KN_L + o), 0.105, false])
		raw.append([g.call(SpiritModel.KN_L + o), g.call(SpiritModel.FT_L + o), 0.085, false])
	var n := raw.size()
	_cap_a.resize(n)
	_cap_ab.resize(n)
	_cap_inv.resize(n)
	_cap_r.resize(n)
	_cap_mid.resize(n)
	_cap_reach.resize(n)
	_cap_drape.resize(n)
	for i in n:
		var c: Array = raw[i]
		var a: Vector3 = c[0]
		var ab: Vector3 = c[1] - a
		_cap_a[i] = a
		_cap_ab[i] = ab
		_cap_inv[i] = 1.0 / maxf(ab.length_squared(), 0.000001)
		_cap_r[i] = c[2]
		_cap_mid[i] = a + ab * 0.5
		# Bounding sphere (plus the tent's reach): points beyond it skip the capsule.
		_cap_reach[i] = ab.length() * 0.5 + float(c[2]) * 1.6 + 0.05
		_cap_drape[i] = c[3]


func _push_out(p: Vector3, lift: float) -> Vector3:
	var ta := _cap_a[0]
	var tab := _cap_ab[0]
	var tinv := _cap_inv[0]
	var n := _cap_a.size()
	for i in n:
		var reach := _cap_reach[i] + lift
		if p.distance_squared_to(_cap_mid[i]) > reach * reach:
			continue
		var a := _cap_a[i]
		var ab := _cap_ab[i]
		var r := _cap_r[i] + lift
		var q := a + ab * clampf((p - a).dot(ab) * _cap_inv[i], 0.0, 1.0)
		var d := p - q
		var l2 := d.length_squared()
		if l2 >= r * r:
			continue
		var l := sqrt(l2)
		var dir := d / l if l > 0.0001 else Vector3.BACK
		if _cap_drape[i]:
			var tq := ta + tab * clampf((q - ta).dot(tab) * tinv, 0.0, 1.0)
			var out := Vector3(q.x - tq.x, 0.0, q.z - tq.z)
			if out.length_squared() > 0.000001:
				dir = dir.lerp(out.normalized(), 0.75).normalized()
		p = q + dir * r
	# Cloth that hangs between the torso and an arm is lifted over the arm (a tent),
	# so the arms always stay under the cloak.
	for i in n:
		if not _cap_drape[i]:
			continue
		var reach := _cap_reach[i] + lift
		if p.distance_squared_to(_cap_mid[i]) > reach * reach:
			continue
		var a := _cap_a[i]
		var ab := _cap_ab[i]
		var r := _cap_r[i] + lift
		var q := a + ab * clampf((p - a).dot(ab) * _cap_inv[i], 0.0, 1.0)
		if absf(p.y - q.y) > r * 1.5:
			continue
		var tq := ta + tab * clampf((q - ta).dot(tab) * tinv, 0.0, 1.0)
		var va := Vector3(q.x - tq.x, 0.0, q.z - tq.z)
		var vp := Vector3(p.x - tq.x, 0.0, p.z - tq.z)
		var la := va.length()
		var lp := vp.length()
		if la < 0.001 or lp < 0.001 or lp >= la + r:
			continue
		if va.dot(vp) / (la * lp) > cos(atan2(r * 1.3, la)):
			p += vp / lp * (la + r - lp)
	return p


func _build_layer(L: Layer, chest: Transform3D) -> void:
	var to_local := model.global_basis.inverse()
	var down := Vector3.DOWN
	var max_th := deg_to_rad(L.half_angle)
	L.pts.resize(L.cols)
	var seg_len := PackedFloat32Array()
	seg_len.resize(L.cols)
	for i in L.cols:
		var u := float(i) / float(L.cols - 1)
		var th := lerpf(-max_th, max_th, u)
		var radial := (chest.basis * Vector3(sin(th), 0.0, cos(th))).normalized()
		# The front edges gather at the clasp, then fall apart to open over the smoke body.
		var root_l := Vector3(sin(th) * L.radius.x, L.height, cos(th) * L.radius.y + 0.01)
		var edge := smoothstep(0.7, 1.0, absf(th) / max_th)
		var front := smoothstep(0.45, 1.0, absf(th) / max_th)
		root_l = root_l.lerp(Vector3(signf(th) * 0.025, L.height + 0.03, -L.radius.y - 0.005), edge * 0.85)
		var root := chest * root_l
		var side := chest.basis.x.normalized() * signf(th)
		var length := lerpf(L.len_front, L.len_back, 0.5 + 0.5 * cos(th)) * L.lens[i]
		var seg := length / float(L.rows - 1)
		seg_len[i] = seg
		var root_dir := (radial * 0.5 + down * 0.85).normalized()
		var col := PackedVector3Array()
		col.resize(L.rows)
		col[0] = root
		var p := root
		for k in range(1, L.rows):
			var s := float(k) / float(L.rows - 1)
			var f := to_local * _flow_at(_time - s * tail_delay * (0.8 + 0.4 * absf(sin(th * 0.5))))
			f = f.lerp(down * f.length(), _front_w * front)
			f += side * L.opening * edge * s + radial * (hem_flare + 1.8 * spin_flare) * s
			var d := root_dir.slerp(f.normalized(), smoothstep(0.0, 0.35, s)).normalized()
			var prev := p
			p = _push_out(p + d * seg, L.lift)
			p = prev + (p - prev).normalized() * seg
			col[k] = p
		L.pts[i] = col
	# Neighbour coupling keeps the columns one sheet; then restore the segment lengths
	# and add a travelling flutter.
	for _pass in 2:
		for i in range(1, L.cols - 1):
			var a := L.pts[i - 1]
			var c := L.pts[i]
			var b := L.pts[i + 1]
			for k in range(1, L.rows):
				c[k] = c[k].lerp((a[k] + b[k]) * 0.5, neighbour_coupling)
			L.pts[i] = c
	var fast := clampf(_v.length() / air_cap, 0.0, 1.0)
	var amp := lerpf(flutter, flutter_fast, fast) * (1.0 + excitement)
	L.flat.resize(L.cols * L.rows)
	for i in L.cols:
		var col := L.pts[i]
		var u := float(i) / float(L.cols - 1)
		var th := lerpf(-max_th, max_th, u)
		var radial := (chest.basis * Vector3(sin(th), 0.0, cos(th))).normalized()
		for k in range(1, L.rows):
			var q := _push_out(col[k], L.lift)
			col[k] = col[k - 1] + (q - col[k - 1]).normalized() * seg_len[i]
		for k in range(1, L.rows):
			var s := float(k) / float(L.rows - 1)
			col[k] += radial * sin(TAU * ((0.6 + 1.6 * fast) * _time - s * 1.3) + u * 5.0) * amp * s * s
		L.pts[i] = col
		for k in L.rows:
			L.flat[k * L.cols + i] = col[k]
	L.mat.set_shader_parameter("ctrl", L.flat)


# --- Hood ----------------------------------------------------------------------------------

static func _hood_mesh() -> ArrayMesh:
	if ResourceLoader.exists(HOOD_PATH):
		var m := load(HOOD_PATH) as ArrayMesh
		if m and m.get_meta("version", -1) == HOOD_VERSION:
			return m
	var t0 := Time.get_ticks_msec()
	var mesh := SdfMesher.build(hood_sdf, Vector3(-0.2, -0.24, -0.25), Vector3(0.2, 0.3, 0.24), 0.0042)
	mesh.set_meta("version", HOOD_VERSION)
	DirAccess.make_dir_recursive_absolute(HOOD_PATH.get_base_dir())
	ResourceSaver.save(mesh, HOOD_PATH)
	print("[Cloak] hood built in %d ms" % (Time.get_ticks_msec() - t0))
	return mesh


## A deep, rounded hood whose soft crown tips forward over the face, with heavy-cloth
## folds sweeping from the crown down the sides, a seam running over the crown from the
## face to the nape, cloth gathered in soft creases around a large arched face opening
## framed by a thick rolled rim, and a cowl that drapes over the shoulders.
## Head-joint space: +Y up, -Z forward.
static func hood_sdf(p: Vector3) -> float:
	var d := SdfMesher.ellipsoid(p - Vector3(0.0, 0.07, 0.02), Vector3(0.128, 0.138, 0.15))
	d = SdfMesher.smin(d, SdfMesher.round_cone(p, Vector3(0.0, 0.13, 0.02), Vector3(0.0, 0.17, -0.04), 0.075, 0.05), 0.06)
	d = SdfMesher.smin(d, SdfMesher.round_cone(p, Vector3(0.0, 0.0, 0.03), Vector3(0.0, -0.2, 0.03), 0.13, 0.2), 0.07)
	# Heavy-cloth folds sweeping from the crown down and back, fading near the face
	# (smooth, wider than the mesh's resolution: creases would facet).
	d += hood_folds(p) * 0.0105 * smoothstep(-0.06, 0.06, p.z + 0.02 - absf(p.x) * 0.2)
	# The seam over the crown, from the top of the face opening to the nape.
	d -= 0.0035 * exp(-pow(p.x / 0.008, 2.0)) * smoothstep(0.0, 0.1, p.y)
	var face := SdfMesher.ellipsoid(p - Vector3(0.0, 0.035, -0.175), Vector3(0.105, 0.155, 0.15))
	# Gothic arch: the opening narrows to a soft point at the top.
	face = SdfMesher.smin(face, SdfMesher.round_cone(p, Vector3(0.0, 0.1, -0.17), Vector3(0.0, 0.19, -0.13), 0.06, 0.012), 0.04)
	# Cloth gathered around the opening: soft creases radiating from the rim.
	var fq := (p - Vector3(0.0, 0.035, -0.175)) / Vector3(0.105, 0.155, 0.15)
	var gather := sin(atan2(fq.y, fq.x) * 9.0 + 0.8) * (1.0 - smoothstep(0.02, 0.09, absf(face)))
	d += gather * 0.0035
	var rim := 1.0 - smoothstep(0.0, 0.045, absf(face))
	var shell := absf(d) - (0.008 + 0.015 * rim)
	shell = SdfMesher.smax(shell, -face, 0.014)
	var slit := SdfMesher.round_cone(p, Vector3(0.0, -0.03, -0.16), Vector3(0.0, -0.23, -0.19), 0.045, 0.075)
	shell = SdfMesher.smax(shell, -slit, 0.012)
	return SdfMesher.smax(shell, -(p.y + 0.21), 0.012)


## The hood's fold field (-1..1, crests positive), shared with hood_cloth.gdshader.
static func hood_folds(p: Vector3) -> float:
	var ang := atan2(p.x, p.z + 0.02)
	return (sin(ang * 4.0 + p.y * 7.0 + 0.6) * 0.55 + sin(ang * 7.0 - p.y * 10.0 + 1.3) * 0.3
			+ sin(ang * 11.0 + p.y * 14.0 + 2.1) * 0.15)
