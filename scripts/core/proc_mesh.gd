class_name ProcMesh
extends RefCounted
## Procedural mesh builders. Everything visible in the demo is generated from
## these helpers, so no external modelling tool is needed.
##
## Godot treats clockwise triangles as front-facing. `commit()` fixes the winding
## of every triangle automatically by comparing it with the vertex normals, so the
## builders only need to produce correct normals.


## Surface of revolution around +Y.
## `profile` holds Vector2(radius, height) points ordered from bottom to top.
## `squash` scales the cross-section depth (Z), e.g. 0.7 for a flatter torso.
## `jitter` randomly displaces the radius for weathered stone.
static func lathe(profile: PackedVector2Array, segments: int = 16, squash: float = 1.0,
		jitter: float = 0.0, seed: int = 0) -> ArrayMesh:
	var a := lathe_arrays(profile, segments, squash, jitter, seed)
	return commit(a[0], a[1], a[2], a[3])


## Same as lathe() but returns [verts, normals, uvs, indices] so several parts can
## be merged into one mesh (used for the skinned spirit body).
static func lathe_arrays(profile: PackedVector2Array, segments: int = 16, squash: float = 1.0,
		jitter: float = 0.0, seed: int = 0) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var rings := profile.size()
	for i in rings:
		var p := profile[i]
		var prev := profile[maxi(i - 1, 0)]
		var next := profile[mini(i + 1, rings - 1)]
		var t := next - prev
		var n2 := Vector2(t.y, -t.x).normalized()
		var v := float(i) / float(rings - 1)
		for j in segments + 1:
			var jj := j % segments
			var a := TAU * float(jj) / float(segments)
			var c := cos(a)
			var s := sin(a)
			var r := p.x
			if jitter > 0.0 and r > 0.0:
				r *= 1.0 + (_hash(i * 131 + jj * 17 + seed * 7919) - 0.5) * 2.0 * jitter
			verts.append(Vector3(c * r, p.y, s * r * squash))
			normals.append(Vector3(c * n2.x, n2.y, s * n2.x / squash).normalized())
			uvs.append(Vector2(float(j) / float(segments), v))
	for i in rings - 1:
		for j in segments:
			var a0 := i * (segments + 1) + j
			var a1 := a0 + 1
			var b0 := a0 + segments + 1
			var b1 := b0 + 1
			indices.append_array([a0, a1, b0, a1, b1, b0])
	return [verts, normals, uvs, indices]


## Profile for a limb segment that starts at the joint (y = 0) and extends down to
## y = -length, with rounded caps so neighbouring segments overlap seamlessly.
## `flare` widens the lower end (used for the flowing trousers of the spirit).
static func limb_profile(length: float, r_top: float, r_bottom: float, bulge: float = 0.0,
		flare: float = 0.0, steps: int = 8) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var cap := 4
	var rb := r_bottom + flare
	for i in cap + 1:
		var a := -PI * 0.5 + PI * 0.5 * float(i) / float(cap)
		pts.append(Vector2(cos(a) * rb, -length + sin(a) * rb))
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var r := lerpf(r_bottom, r_top, smoothstep(0.0, 1.0, t)) + sin(t * PI) * bulge
		r += flare * pow(1.0 - t, 2.5)
		pts.append(Vector2(r, -length + length * t))
	for i in cap + 1:
		var a := PI * 0.5 * float(i) / float(cap)
		pts.append(Vector2(cos(a) * r_top, sin(a) * r_top))
	return pts


## Ellipsoid profile centred on y = 0 (radius `rx`, half-height `ry`).
## `egg` > 0 makes the upper half fuller than the lower half.
static func ellipsoid_profile(rx: float, ry: float, steps: int = 12, egg: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		var a := -PI * 0.5 + PI * float(i) / float(steps)
		var s := sin(a)
		var r := cos(a) * rx * (1.0 + egg * s)
		pts.append(Vector2(maxf(r, 0.0), s * ry))
	return pts


## Elongated, tapered board shape lofted along -Z (nose) to +Z (tail).
## The cross-section is a lens; UV.x runs along the length, UV.y around it
## (0 = right rim, 0.25 = top centre, 0.5 = left rim, 0.75 = bottom centre).
static func board(length: float, width: float, thickness: float, kick: float,
		sections: int = 32, ring: int = 20) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in sections + 1:
		var t := float(i) / float(sections)
		var z := lerpf(-length * 0.5, length * 0.5, t)
		# Nose is slightly longer and sharper than the tail.
		var shape_t := pow(t, 0.92)
		var w := width * 0.5 * pow(sin(PI * shape_t), 0.42)
		var h := thickness * 0.5 * (0.35 + 0.65 * pow(sin(PI * shape_t), 0.6))
		var y_off := kick * (pow(smoothstep(0.2, 0.0, t), 2.0) + 0.7 * pow(smoothstep(0.82, 1.0, t), 2.0))
		for k in ring + 1:
			var a := TAU * float(k % ring) / float(ring)
			var c := cos(a)
			var s := sin(a)
			# Flatter top surface, rounder belly.
			var hy := h * (0.55 if s > 0.0 else 1.0)
			verts.append(Vector3(c * w, s * hy + y_off, z))
			var n := Vector3(c / maxf(w, 0.001), s / maxf(hy, 0.001), 0.0).normalized()
			normals.append(n)
			uvs.append(Vector2(t, float(k) / float(ring)))
	for i in sections:
		for k in ring:
			var a0 := i * (ring + 1) + k
			var a1 := a0 + 1
			var b0 := a0 + ring + 1
			var b1 := b0 + 1
			indices.append_array([a0, a1, b0, a1, b1, b0])
	return commit(verts, normals, uvs, indices)


## Assembles an ArrayMesh, flipping any triangle whose winding disagrees with its normals.
static func commit(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array,
		indices: PackedInt32Array, colors: PackedColorArray = PackedColorArray(),
		bones: PackedInt32Array = PackedInt32Array(), weights: PackedFloat32Array = PackedFloat32Array(),
		into: ArrayMesh = null, uv2s: PackedVector2Array = PackedVector2Array()) -> ArrayMesh:
	for t in range(0, indices.size(), 3):
		var i0 := indices[t]
		var i1 := indices[t + 1]
		var i2 := indices[t + 2]
		var face := (verts[i1] - verts[i0]).cross(verts[i2] - verts[i0])
		var n := normals[i0] + normals[i1] + normals[i2]
		if face.dot(n) > 0.0:
			indices[t + 1] = i2
			indices[t + 2] = i1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	if not uvs.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	if not uv2s.is_empty():
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	if not colors.is_empty():
		arrays[Mesh.ARRAY_COLOR] = colors
	if not bones.is_empty():
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := into if into else ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _hash(n: int) -> float:
	var x := (n * 374761393 + 668265263) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	return float(x & 0xffff) / 65535.0
