class_name SpiritBodyBuilder
extends RefCounted
## Builds the spirit's body as ONE continuous organic mesh.
##
## The shape is a signed distance field made of round cones and ellipsoids joined with
## smooth unions, so shoulders, hips and neck melt into each other like a single
## substance. It is polygonised with surface nets, every vertex is projected back onto
## the exact surface, normals come from the field gradient (perfectly smooth shading),
## and each vertex is skinned to the bones whose shapes it is closest to.
##
## The mesh is built in an A-pose (arms out, legs slightly apart) so limbs don't fuse
## with the torso; the Skin binds it to the skeleton's straight rest pose.
## Building takes a few seconds in GDScript, so the result is cached in CACHE_PATH.
## After changing proportions run:  Godot --headless --path . --script res://scripts/tools/build_spirit_mesh.gd

const CACHE_PATH := "res://assets/spirit/spirit_body.res"
const VERSION := 11

## A-pose used for binding: shoulder and thigh roll (radians).
const ARM_SPREAD := 0.62
const LEG_SPREAD := 0.09

enum { CONE, ELLIPSOID }

var voxel := 0.0085

var _prims: Array = []     # [type, bone, a, b, ra, rb]  (ellipsoid: a = centre, b = radii)
var _chains: Array = []    # [[prim indices], chain_k, attach_k]


## Hash of everything that shapes the mesh, stored on the cached resource.
static func shape_hash(rest: Array[Vector3]) -> int:
	return hash(str(rest) + str(VERSION) + str(ARM_SPREAD) + str(LEG_SPREAD))


## Bone transforms (model space) of the bind A-pose.
static func bind_globals(rest: Array[Vector3], parents: Array) -> Array[Transform3D]:
	var g: Array[Transform3D] = []
	g.resize(rest.size())
	for i in rest.size():
		var rot := Basis.IDENTITY
		match i:
			SpiritModel.SH_L: rot = Basis(Vector3.BACK, -ARM_SPREAD)
			SpiritModel.SH_R: rot = Basis(Vector3.BACK, ARM_SPREAD)
			SpiritModel.TH_L: rot = Basis(Vector3.BACK, -LEG_SPREAD)
			SpiritModel.TH_R: rot = Basis(Vector3.BACK, LEG_SPREAD)
		var local := Transform3D(rot, rest[i])
		g[i] = (g[parents[i]] * local) if parents[i] >= 0 else local
	return g


static func make_skin(rest: Array[Vector3], parents: Array) -> Skin:
	var skin := Skin.new()
	var g := bind_globals(rest, parents)
	for i in g.size():
		skin.add_bind(i, g[i].affine_inverse())
	return skin


## Loads the cached mesh if it matches the proportions, otherwise builds it.
static func load_or_build(rest: Array[Vector3], parents: Array, head_radius: float) -> ArrayMesh:
	var want := shape_hash(rest)
	if ResourceLoader.exists(CACHE_PATH):
		var m := load(CACHE_PATH) as ArrayMesh
		if m and m.has_meta("shape_hash") and int(m.get_meta("shape_hash")) == want:
			return m
	push_warning("SpiritBodyBuilder: cached body missing or outdated; building at runtime (run scripts/tools/build_spirit_mesh.gd to cache it).")
	return SpiritBodyBuilder.new().build(rest, parents, head_radius)


# --- Shape --------------------------------------------------------------------------------

func _define(rest: Array[Vector3], parents: Array, head_r: float) -> void:
	var g := bind_globals(rest, parents)
	var M := SpiritModel
	var hips := g[M.HIPS].origin
	var chest := g[M.CHEST].origin
	_prims.clear()
	_chains.clear()
	# Torso: pelvis, waist, ribcage and a soft shoulder line.
	var pelvis := _ellipsoid(M.HIPS, hips + Vector3(0, -0.015, 0.0), Vector3(0.098, 0.085, 0.07))
	var waist := _ellipsoid(M.SPINE, hips + Vector3(0, 0.12, 0.0), Vector3(0.062, 0.1, 0.05))
	var ribs := _ellipsoid(M.CHEST, chest + Vector3(0, 0.01, -0.004), Vector3(0.088, 0.1, 0.064))
	var yoke := _ellipsoid(M.CHEST, chest + Vector3(0, 0.09, 0.006), Vector3(0.09, 0.03, 0.048))
	_chains.append([[pelvis, waist, ribs, yoke], 0.07, 0.0])
	# Slender neck and a smaller, slightly egg-shaped head.
	var neck_base := g[M.NECK].origin + Vector3(0, -0.05, 0)
	var neck := _cone(M.NECK, neck_base, g[M.HEAD].origin + Vector3(0, 0.03, 0), 0.022, 0.015)
	_chains.append([[neck], 0.0, 0.03])
	# Small oval head, slightly taller than wide.
	var head := _ellipsoid(M.HEAD, g[M.HEAD].origin + Vector3(0, head_r * 1.1, -0.004), Vector3(head_r * 0.92, head_r * 1.18, head_r))
	_chains.append([[head], 0.0, 0.014])
	for side in 2:
		var o := 0 if side == 0 else 3
		var s := g[M.SH_L + o].origin
		var e := g[M.EL_L + o].origin
		var w := g[M.HA_L + o].origin
		# Wrist stub only: the hands (with fingers) are separate fine meshes (SmokeBody).
		var tip := g[M.HA_L + o] * Vector3(0, -0.028, 0.002)
		# Lean but not thin: a full shoulder, a tapering upper arm, a forearm that swells
		# below the elbow and narrows to a slim wrist.
		var fm := e.lerp(w, 0.3)
		var dl := _cone(M.SH_L + o, s, s.lerp(e, 0.25), 0.05, 0.047)
		var ua := _cone(M.SH_L + o, s.lerp(e, 0.25), e, 0.047, 0.034)
		var fa := _cone(M.EL_L + o, e, fm, 0.034, 0.037)
		var fb := _cone(M.EL_L + o, fm, w, 0.037, 0.021)
		var hand := _cone(M.HA_L + o, w, tip, 0.02, 0.017)
		_chains.append([[dl, ua, fa, fb, hand], 0.025, 0.04])
		var h := g[M.TH_L + o].origin
		var k := g[M.KN_L + o].origin
		var a := g[M.FT_L + o].origin
		# Long tapering legs ending in pointed, elegant feet.
		var toe := g[M.FT_L + o] * Vector3(0, -0.028, -0.125)
		# A shaped leg: full upper thigh, narrower knee, a calf that swells at the back
		# (+Z) below it, then a long taper to a slim ankle.
		var tm := h.lerp(k, 0.45)
		var cm := k.lerp(a, 0.3) + Vector3(0, 0, 0.014)
		var th := _cone(M.TH_L + o, h, tm, 0.08, 0.066)
		var tk := _cone(M.TH_L + o, tm, k, 0.066, 0.044)
		var ca := _cone(M.KN_L + o, k, cm, 0.043, 0.052)
		var sh := _cone(M.KN_L + o, cm, a + Vector3(0, 0.01, 0), 0.052, 0.026)
		var ft := _cone(M.FT_L + o, a + Vector3(0, -0.004, 0.01), toe, 0.024, 0.008)
		_chains.append([[th, tk, ca, sh, ft], 0.03, 0.05])


func _cone(bone: int, a: Vector3, b: Vector3, ra: float, rb: float) -> int:
	_prims.append([CONE, bone, a, b, ra, rb])
	return _prims.size() - 1


func _ellipsoid(bone: int, c: Vector3, r: Vector3) -> int:
	_prims.append([ELLIPSOID, bone, c, r, 0.0, 0.0])
	return _prims.size() - 1


func _prim_dist(i: int, p: Vector3) -> float:
	var pr: Array = _prims[i]
	if pr[0] == ELLIPSOID:
		var q: Vector3 = p - pr[2]
		var r: Vector3 = pr[3]
		var k0 := (q / r).length()
		var k1 := (q / (r * r)).length()
		return k0 * (k0 - 1.0) / maxf(k1, 0.000001)
	return _round_cone(p, pr[2], pr[3], pr[4], pr[5])


## Exact round-cone distance (Inigo Quilez).
static func _round_cone(p: Vector3, a: Vector3, b: Vector3, r1: float, r2: float) -> float:
	var ba := b - a
	var l2 := ba.dot(ba)
	var rr := r1 - r2
	var a2 := l2 - rr * rr
	var il2 := 1.0 / l2
	var pa := p - a
	var y := pa.dot(ba)
	var z := y - l2
	var xv := pa * l2 - ba * y
	var x2 := xv.dot(xv)
	var y2 := y * y * l2
	var z2 := z * z * l2
	var k := signf(rr) * rr * rr * x2
	if signf(z) * a2 * z2 > k:
		return sqrt(x2 + z2) * il2 - r2
	if signf(y) * a2 * y2 < k:
		return sqrt(x2 + y2) * il2 - r1
	return (sqrt(x2 * a2 * il2) + y * rr) * il2 - r1


static func _smin(a: float, b: float, k: float) -> float:
	if k <= 0.0:
		return minf(a, b)
	var h := maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - h * h * k * 0.25


func sdf(p: Vector3) -> float:
	var body := INF
	for c in _chains:
		var idx: Array = c[0]
		var d := _prim_dist(idx[0], p)
		for j in range(1, idx.size()):
			d = _smin(d, _prim_dist(idx[j], p), c[1])
		body = d if body == INF else _smin(body, d, c[2])
	return body


func _grad(p: Vector3) -> Vector3:
	var e := 0.0012
	return Vector3(
		sdf(p + Vector3(e, 0, 0)) - sdf(p - Vector3(e, 0, 0)),
		sdf(p + Vector3(0, e, 0)) - sdf(p - Vector3(0, e, 0)),
		sdf(p + Vector3(0, 0, e)) - sdf(p - Vector3(0, 0, e))).normalized()


# --- Build --------------------------------------------------------------------------------

func build(rest: Array[Vector3], parents: Array, head_r: float) -> ArrayMesh:
	var t0 := Time.get_ticks_msec()
	_define(rest, parents, head_r)
	var lo := Vector3(-0.55, -0.03, -0.22)
	var hi := Vector3(0.55, rest[0].y + 0.75, 0.16)
	var h := voxel
	var nx := int(ceil((hi.x - lo.x) / h)) + 1
	var ny := int(ceil((hi.y - lo.y) / h)) + 1
	var nz := int(ceil((hi.z - lo.z) / h)) + 1
	var field := PackedFloat32Array()
	field.resize(nx * ny * nz)
	field.fill(1.0)
	# Coarse pass, then exact values only in a narrow band around the surface.
	var c := 3
	var cnx := (nx - 1) / c + 2
	var cny := (ny - 1) / c + 2
	var cnz := (nz - 1) / c + 2
	var coarse := PackedFloat32Array()
	coarse.resize(cnx * cny * cnz)
	for ck in cnz:
		for cj in cny:
			for ci in cnx:
				coarse[(ck * cny + cj) * cnx + ci] = sdf(lo + Vector3(ci, cj, ck) * h * c)
	var band := h * c * 1.8
	for ck in cnz - 1:
		for cj in cny - 1:
			for ci in cnx - 1:
				var near := false
				var inside := true
				for corner in 8:
					var v := coarse[((ck + (corner >> 2)) * cny + cj + ((corner >> 1) & 1)) * cnx + ci + (corner & 1)]
					if absf(v) < band:
						near = true
					if v > -band:
						inside = false
				if not near and not inside:
					continue
				for k in range(ck * c, mini(ck * c + c + 1, nz)):
					for j in range(cj * c, mini(cj * c + c + 1, ny)):
						for i in range(ci * c, mini(ci * c + c + 1, nx)):
							field[(k * ny + j) * nx + i] = -1.0 if inside else sdf(lo + Vector3(i, j, k) * h)

	# Surface nets: one vertex per cell that the surface crosses.
	var corner_off: Array[Vector3i] = []
	for corner in 8:
		corner_off.append(Vector3i(corner & 1, (corner >> 1) & 1, corner >> 2))
	var edges := [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]
	var cell_vert := PackedInt32Array()
	cell_vert.resize((nx - 1) * (ny - 1) * (nz - 1))
	cell_vert.fill(-1)
	var verts := PackedVector3Array()
	var vals := PackedFloat32Array()
	vals.resize(8)
	for k in nz - 1:
		for j in ny - 1:
			for i in nx - 1:
				var mask := 0
				for corner in 8:
					var o := corner_off[corner]
					var v := field[((k + o.z) * ny + j + o.y) * nx + i + o.x]
					vals[corner] = v
					if v < 0.0:
						mask |= 1 << corner
				if mask == 0 or mask == 255:
					continue
				var acc := Vector3.ZERO
				var cnt := 0
				for e in edges:
					var a: int = e[0]
					var b: int = e[1]
					if (vals[a] < 0.0) != (vals[b] < 0.0):
						var t := vals[a] / (vals[a] - vals[b])
						acc += Vector3(corner_off[a]).lerp(Vector3(corner_off[b]), t)
						cnt += 1
				cell_vert[(k * (ny - 1) + j) * (nx - 1) + i] = verts.size()
				verts.append(lo + (Vector3(i, j, k) + acc / cnt) * h)

	var indices := PackedInt32Array()
	for k in range(1, nz - 1):
		for j in range(1, ny - 1):
			for i in range(1, nx - 1):
				var v0 := field[(k * ny + j) * nx + i] < 0.0
				# x edge
				if (field[(k * ny + j) * nx + i + 1] < 0.0) != v0:
					_quad(indices, cell_vert, nx, ny, Vector3i(i, j - 1, k - 1), Vector3i(i, j, k - 1), Vector3i(i, j, k), Vector3i(i, j - 1, k))
				if (field[(k * ny + j + 1) * nx + i] < 0.0) != v0:
					_quad(indices, cell_vert, nx, ny, Vector3i(i - 1, j, k - 1), Vector3i(i, j, k - 1), Vector3i(i, j, k), Vector3i(i - 1, j, k))
				if (field[((k + 1) * ny + j) * nx + i] < 0.0) != v0:
					_quad(indices, cell_vert, nx, ny, Vector3i(i - 1, j - 1, k), Vector3i(i, j - 1, k), Vector3i(i, j, k), Vector3i(i - 1, j, k))

	# Project onto the exact surface, smooth normals, skin weights.
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	var colors := PackedColorArray()
	colors.resize(verts.size())
	# Rest-pose position (UV.xy + COLOR.r - 0.5): surface-anchored detail in the shader.
	var uvs := PackedVector2Array()
	uvs.resize(verts.size())
	# Limb-cylindrical coordinates (UV2: turns around the nearest limb's axis, metres
	# along it): lets the shader wind rope-like strands around each limb.
	var uv2s := PackedVector2Array()
	uv2s.resize(verts.size())
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for vi in verts.size():
		var p := verts[vi]
		for _step in 2:
			p -= _grad(p) * sdf(p)
		verts[vi] = p
		normals[vi] = _grad(p)
		var w := _skin_weights(p)
		bones.append_array([w[0], w[2], w[4], w[6]])
		weights.append_array([w[1], w[3], w[5], w[7]])
		var head_w := 0.0
		for q in 4:
			if int(w[q * 2]) == SpiritModel.HEAD:
				head_w += float(w[q * 2 + 1])
		colors[vi] = Color(p.z + 0.5, clampf((p.y) / (rest[0].y + 0.6), 0.0, 1.0), head_w, 1.0)
		uvs[vi] = Vector2(p.x, p.y)
		uv2s[vi] = _limb_coords(p)

	var mesh := ProcMesh.commit(verts, normals, uvs, indices, colors, bones, weights, null, uv2s)
	mesh.set_meta("shape_hash", shape_hash(rest))
	print("[SpiritBodyBuilder] %d vertices, %d triangles in %d ms" % [verts.size(), indices.size() / 3, Time.get_ticks_msec() - t0])
	return mesh


func _quad(out: PackedInt32Array, cell_vert: PackedInt32Array, nx: int, ny: int,
		a: Vector3i, b: Vector3i, c: Vector3i, d: Vector3i) -> void:
	var ia := cell_vert[(a.z * (ny - 1) + a.y) * (nx - 1) + a.x]
	var ib := cell_vert[(b.z * (ny - 1) + b.y) * (nx - 1) + b.x]
	var ic := cell_vert[(c.z * (ny - 1) + c.y) * (nx - 1) + c.x]
	var id := cell_vert[(d.z * (ny - 1) + d.y) * (nx - 1) + d.x]
	if ia < 0 or ib < 0 or ic < 0 or id < 0:
		return
	out.append_array([ia, ib, ic, ia, ic, id])


## (turns around the nearest primitive's axis in -0.5..0.5, metres along the axis).
## Axes: cones along their length, torso ellipsoids vertical. The angle is measured
## from the axis-perpendicular part of +Z, so neighbouring primitives of a limb agree.
func _limb_coords(p: Vector3) -> Vector2:
	var best := 0
	var bd := INF
	for i in _prims.size():
		var d := _prim_dist(i, p)
		if d < bd:
			bd = d
			best = i
	var pr: Array = _prims[best]
	var a: Vector3 = pr[2]
	var axis := Vector3.UP
	if pr[0] == CONE:
		axis = (pr[3] - pr[2]).normalized()
	var radial := (p - a) - axis * (p - a).dot(axis)
	var e1 := Vector3.BACK - axis * Vector3.BACK.dot(axis)
	if e1.length_squared() < 0.0001:
		e1 = Vector3.RIGHT
	e1 = e1.normalized()
	var e2 := axis.cross(e1)
	return Vector2(atan2(radial.dot(e2), radial.dot(e1)) / TAU, p.dot(axis))


## Up to four bones, weighted by how close the vertex is to each bone's shapes.
func _skin_weights(p: Vector3) -> Array:
	var best := {}
	for i in _prims.size():
		var bone: int = _prims[i][1]
		var d := _prim_dist(i, p)
		if not best.has(bone) or d < best[bone]:
			best[bone] = d
	var dmin := INF
	for b in best:
		dmin = minf(dmin, best[b])
	var pairs: Array = []
	for b in best:
		var w := exp(-maxf(float(best[b]) - dmin, 0.0) / 0.011)
		if w > 0.02:
			pairs.append([w, b])
	pairs.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
	var out := [0, 0.0, 0, 0.0, 0, 0.0, 0, 0.0]
	var total := 0.0
	for q in mini(4, pairs.size()):
		total += pairs[q][0]
	for q in mini(4, pairs.size()):
		out[q * 2] = pairs[q][1]
		out[q * 2 + 1] = pairs[q][0] / total
	return out
