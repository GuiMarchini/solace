class_name MeshKit
extends RefCounted
## Accumulates procedural stone geometry (tubes, rounded blocks, displaced rocks) in world
## or site space and commits it as ONE mesh, so a whole ruin is a single draw call.
## Vertex colours carry what the stone shader needs: R = cavity (0 dark .. 1 open),
## G = worn edge, B = height above the sand / 8 m (sand drifts against the foot).
## Normals are averaged from the faces around each vertex at commit.

var verts := PackedVector3Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()

static var _noise: FastNoiseLite


static func noise() -> FastNoiseLite:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.frequency = 1.0
		_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		_noise.fractal_octaves = 3
		_noise.seed = 31
	return _noise


## Adds a grid of rows x cols points (row-major); wraps around the columns if `wrap`.
## `cols_c` gives each point's colour (same layout), or white.
func grid(pts: PackedVector3Array, rows: int, cols: int, wrap: bool, cols_c := PackedColorArray(), flip := false) -> int:
	var base := verts.size()
	verts.append_array(pts)
	if cols_c.size() == pts.size():
		colors.append_array(cols_c)
	else:
		for i in pts.size():
			colors.append(Color.WHITE)
	var cmax := cols if wrap else cols - 1
	for r in rows - 1:
		for c in cmax:
			var c1 := (c + 1) % cols
			var a := base + r * cols + c
			var b := base + r * cols + c1
			var d := base + (r + 1) * cols + c
			var e := base + (r + 1) * cols + c1
			if flip:
				indices.append_array([a, d, b, b, d, e])
			else:
				indices.append_array([a, b, d, b, e, d])
	return base


## Closes a ring of `n` points starting at index `first` with a fan around `center`.
func cap(first: int, n: int, center: Vector3, color := Color.WHITE, flip := false) -> void:
	var ci := verts.size()
	verts.append(center)
	colors.append(color)
	for i in n:
		var a := first + i
		var b := first + (i + 1) % n
		if flip:
			indices.append_array([ci, b, a])
		else:
			indices.append_array([ci, a, b])


## A block with rounded edges (`bevel` m) and chipped, uneven faces (`chip` m).
func block(xf: Transform3D, size: Vector3, bevel := 0.08, chip := 0.04, seed := 0) -> void:
	var h := size * 0.5
	var inner := (h - Vector3.ONE * bevel).max(Vector3.ONE * 0.001)
	var n := 5
	var nz := noise()
	var faces := [[Vector3.RIGHT, Vector3.BACK, Vector3.UP], [Vector3.LEFT, Vector3.FORWARD, Vector3.UP],
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK], [Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
		[Vector3.BACK, Vector3.LEFT, Vector3.UP], [Vector3.FORWARD, Vector3.RIGHT, Vector3.UP]]
	for f in faces:
		var fn: Vector3 = f[0]
		var fu: Vector3 = f[1]
		var fv: Vector3 = f[2]
		var pts := PackedVector3Array()
		var cc := PackedColorArray()
		for j in n + 1:
			for i in n + 1:
				var u := float(i) / n * 2.0 - 1.0
				var v := float(j) / n * 2.0 - 1.0
				var p := (fn + fu * u + fv * v) * h
				var q := p.clamp(-inner, inner)
				var dir := (p - q).normalized()
				var s := q + dir * bevel
				var edge := clampf((maxf(absf(u), absf(v)) - 0.6) / 0.4, 0.0, 1.0)
				var wp := xf * s
				s += dir * (nz.get_noise_3d(wp.x * 1.7 + seed, wp.y * 1.7, wp.z * 1.7) * chip * (0.6 + edge))
				pts.append(xf * s)
				cc.append(Color(1.0, edge * 0.8, 1.0))
		grid(pts, n + 1, n + 1, false, cc)


## A tube around +Y (in `xf`): `radius_at(angle, t)` gives the radius at height fraction
## t of `height`, `top_at(angle)` the top height for each angle (a broken shaft); capped.
func tube(xf: Transform3D, height: float, segs: int, rings: int, radius_at: Callable, top_at: Callable,
		cavity_at: Callable, cap_top := true, cap_bottom := false) -> void:
	var pts := PackedVector3Array()
	var cc := PackedColorArray()
	var tops := PackedFloat32Array()
	for s in segs:
		tops.append(float(top_at.call(TAU * s / segs)))
	for r in rings + 1:
		var t := float(r) / rings
		for s in segs:
			var a := TAU * s / segs
			var y := tops[s] * t
			var rad: float = radius_at.call(a, y / height)
			pts.append(xf * Vector3(cos(a) * rad, y, sin(a) * rad))
			cc.append(Color(float(cavity_at.call(a)), 0.15 if r < rings else 0.7, 1.0))
	var first := grid(pts, rings + 1, segs, true, cc)
	if cap_top:
		var avg := 0.0
		for v in tops:
			avg += v
		avg /= segs
		cap(first + rings * segs, segs, xf * Vector3(0.0, avg - 0.001 * height, 0.0), Color(1.0, 0.5, 1.0))
	if cap_bottom:
		cap(first, segs, xf * Vector3.ZERO, Color(0.6, 0.0, 1.0), true)


## A rough boulder: a sphere pushed out by noise, layered into ledges (sandstone),
## flattened below. `strata` (m) is the ledge spacing, 0 for none.
func rock(xf: Transform3D, radius: float, seed: int, strata := 0.0, squash := 0.75) -> void:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 28
	sm.rings = 16
	var arr := sm.get_mesh_arrays()
	var sv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var si: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var nz := noise()
	var base := verts.size()
	# The sphere mesh duplicates its seam vertices: weld them by position so the noise and
	# the normals agree across the seam.
	var welded := {}
	var remap := PackedInt32Array()
	remap.resize(sv.size())
	for i in sv.size():
		var key := Vector3i((sv[i] * 1000.0).round())
		if welded.has(key):
			remap[i] = welded[key]
			continue
		var d := sv[i].normalized()
		var big := nz.get_noise_3d(d.x * 1.3 + seed * 7.1, d.y * 1.3, d.z * 1.3)
		var small := nz.get_noise_3d(d.x * 4.0 - seed, d.y * 4.0, d.z * 4.0)
		var r := radius * (1.0 + big * 0.42 + small * 0.1)
		var p := Vector3(d.x * r, d.y * r * squash, d.z * r)
		if strata > 0.0:
			var ledge := floorf(p.y / strata) * strata + smoothstep(0.55, 1.0, fposmod(p.y / strata, 1.0)) * strata
			p.y = lerpf(p.y, ledge, 0.65)
			# Each ledge juts out a little more or less.
			p *= Vector3(1.0, 0.0, 1.0) * (1.0 + 0.08 * sin(floorf(p.y / strata) * 2.7 + seed)) + Vector3(0.0, 1.0, 0.0)
		p.y = maxf(p.y, -radius * 0.35)
		welded[key] = verts.size()
		remap[i] = verts.size()
		verts.append(xf * p)
		var cav := clampf(0.75 + big * 0.6, 0.35, 1.0)
		colors.append(Color(cav, clampf(small * 2.0, 0.0, 1.0), 1.0))
	for k in range(0, si.size(), 3):
		var a := remap[si[k]]
		var b := remap[si[k + 1]]
		var c := remap[si[k + 2]]
		if a != b and b != c and a != c:
			indices.append_array([a, b, c])


## Builds the mesh. `ground` (Callable x, z -> height) fills the height above the sand.
func commit(ground: Callable = Callable()) -> ArrayMesh:
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for k in range(0, indices.size(), 3):
		var a := indices[k]
		var b := indices[k + 1]
		var c := indices[k + 2]
		var fn := (verts[c] - verts[a]).cross(verts[b] - verts[a])
		normals[a] += fn
		normals[b] += fn
		normals[c] += fn
	for i in normals.size():
		normals[i] = normals[i].normalized() if normals[i].length_squared() > 1e-12 else Vector3.UP
	if ground.is_valid():
		for i in verts.size():
			var v := verts[i]
			colors[i].b = clampf((v.y - float(ground.call(v.x, v.z))) / 8.0, 0.0, 1.0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	if verts.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
