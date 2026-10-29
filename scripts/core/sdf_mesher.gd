class_name SdfMesher
extends RefCounted
## Polygonises a signed distance field (a Callable p -> float) with surface nets inside
## a box: one vertex per crossed cell, projected back onto the exact surface, normals
## from the field gradient. Small shapes only (dense grid, GDScript): cache the result.


static func build(sdf: Callable, lo: Vector3, hi: Vector3, h: float) -> ArrayMesh:
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
				coarse[(ck * cny + cj) * cnx + ci] = sdf.call(lo + Vector3(ci, cj, ck) * h * c)
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
							field[(k * ny + j) * nx + i] = -1.0 if inside else sdf.call(lo + Vector3(i, j, k) * h)

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
						acc += Vector3(corner_off[a]).lerp(Vector3(corner_off[b]), vals[a] / (vals[a] - vals[b]))
						cnt += 1
				cell_vert[(k * (ny - 1) + j) * (nx - 1) + i] = verts.size()
				verts.append(lo + (Vector3(i, j, k) + acc / cnt) * h)

	var indices := PackedInt32Array()
	for k in range(1, nz - 1):
		for j in range(1, ny - 1):
			for i in range(1, nx - 1):
				var v0 := field[(k * ny + j) * nx + i] < 0.0
				if (field[(k * ny + j) * nx + i + 1] < 0.0) != v0:
					_quad(indices, cell_vert, nx, ny, Vector3i(i, j - 1, k - 1), Vector3i(i, j, k - 1), Vector3i(i, j, k), Vector3i(i, j - 1, k))
				if (field[(k * ny + j + 1) * nx + i] < 0.0) != v0:
					_quad(indices, cell_vert, nx, ny, Vector3i(i - 1, j, k - 1), Vector3i(i, j, k - 1), Vector3i(i, j, k), Vector3i(i - 1, j, k))
				if (field[((k + 1) * ny + j) * nx + i] < 0.0) != v0:
					_quad(indices, cell_vert, nx, ny, Vector3i(i - 1, j - 1, k), Vector3i(i, j - 1, k), Vector3i(i, j, k), Vector3i(i - 1, j, k))

	var normals := PackedVector3Array()
	normals.resize(verts.size())
	var e := h * 0.5
	for vi in verts.size():
		var p := verts[vi]
		for _step in 2:
			var g := _grad(sdf, p, e)
			p -= g * float(sdf.call(p))
		verts[vi] = p
		normals[vi] = _grad(sdf, p, e)
	return ProcMesh.commit(verts, normals, PackedVector2Array(), indices)


static func _grad(sdf: Callable, p: Vector3, e: float) -> Vector3:
	var g := Vector3(
		float(sdf.call(p + Vector3(e, 0, 0))) - float(sdf.call(p - Vector3(e, 0, 0))),
		float(sdf.call(p + Vector3(0, e, 0))) - float(sdf.call(p - Vector3(0, e, 0))),
		float(sdf.call(p + Vector3(0, 0, e))) - float(sdf.call(p - Vector3(0, 0, e))))
	return g.normalized() if g.length_squared() > 0.0 else Vector3.UP


static func _quad(out: PackedInt32Array, cell_vert: PackedInt32Array, nx: int, ny: int,
		a: Vector3i, b: Vector3i, c: Vector3i, d: Vector3i) -> void:
	var ia := cell_vert[(a.z * (ny - 1) + a.y) * (nx - 1) + a.x]
	var ib := cell_vert[(b.z * (ny - 1) + b.y) * (nx - 1) + b.x]
	var ic := cell_vert[(c.z * (ny - 1) + c.y) * (nx - 1) + c.x]
	var id := cell_vert[(d.z * (ny - 1) + d.y) * (nx - 1) + d.x]
	if ia < 0 or ib < 0 or ic < 0 or id < 0:
		return
	out.append_array([ia, ib, ic, ia, ic, id])


# --- Primitives --------------------------------------------------------------------------

static func ellipsoid(p: Vector3, r: Vector3) -> float:
	var k0 := (p / r).length()
	var k1 := (p / (r * r)).length()
	return k0 * (k0 - 1.0) / maxf(k1, 0.000001)


static func round_cone(p: Vector3, a: Vector3, b: Vector3, r1: float, r2: float) -> float:
	var ba := b - a
	var l2 := ba.length_squared()
	var t := clampf((p - a).dot(ba) / l2, 0.0, 1.0)
	return (p - (a + ba * t)).length() - lerpf(r1, r2, t)


static func smin(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


static func smax(a: float, b: float, k: float) -> float:
	return -smin(-a, -b, k)
