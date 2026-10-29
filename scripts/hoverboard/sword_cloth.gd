class_name SwordCloth
extends MeshInstance3D
## Torn strips of crimson cloth knotted around the sword's grip (SpiritSword.CLOTH_KNOTS),
## with golden runes painted down them, as on the sword's concept sheet.
##
## Each strip is a light verlet chain: its points keep their momentum, fall, and are
## dragged by the (still) air, so the strips stream out behind the moving sword, swing
## wide through turns and tricks, and droop when it slows, all by themselves. A soft
## turbulence makes them flutter, harder at speed and toward the torn ends; they keep
## their length, never sink into the sand, and a little bending stiffness keeps them
## cloth rather than string. Drawn in world space as smooth ribbons (Catmull-Rom between
## the points, twisting along their length), rebuilt as one surface per frame.

@export var strip_material: Material
## Per strip: x = knot index, y = length (m), z = width (m), w = angle around the grip.
@export var strips: Array[Vector4] = [Vector4(1, 1.1, 0.1, 0.3), Vector4(1, 0.9, 0.085, 2.4),
		Vector4(1, 0.72, 0.075, -1.5), Vector4(0, 0.82, 0.085, 1.0), Vector4(0, 0.58, 0.07, -2.2)]
@export var points_per_strip := 12
@export var subdivisions := 3
@export_group("Physics")
@export var gravity := 5.5
## How fast the cloth matches the air around it (1/s): higher streams back harder.
@export var air_drag := 3.4
## Turbulent flutter (m/s^2), scaled by speed and along the strip.
@export var flutter := 26.0
@export var bend_stiffness := 0.25
@export var iterations := 4
## A light world-space breeze, so the cloth still moves when the sword is still.
@export var breeze := Vector3(0.6, 0.1, 0.35)

## The node whose global transform is the sword's frame (SpiritSword).
var sword: Node3D
## World height of the ground under the sword (Hoverboard sets it).
var ground_height := -INF
## Simulated points of each strip in world space (read by tests).
var points: Array[PackedVector3Array] = []

var _prev: Array[PackedVector3Array] = []
var _mesh := ArrayMesh.new()
var _time := 0.0
var _last_root := Vector3.ZERO
var _primed := false
var _speed := 0.0


func _ready() -> void:
	top_level = true
	mesh = _mesh
	if strip_material:
		var m := strip_material.duplicate() as Material
		if m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter("strip_size", Vector2(0.95, 0.09))
			(m as ShaderMaterial).set_shader_parameter("seed", 11.0)
			# Golden runes painted down the strips, as on the sheet.
			(m as ShaderMaterial).set_shader_parameter("runes", 1.0)
			# A deeper, redder crimson than the faded mantle, as on the sheet.
			(m as ShaderMaterial).set_shader_parameter("cloth", Color(0.18, 0.026, 0.038))
			(m as ShaderMaterial).set_shader_parameter("cloth_faded", Color(0.36, 0.13, 0.14))
		material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	custom_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))


## Hang the strips straight down again (summon, respawn).
func reset() -> void:
	_primed = false


func step(delta: float) -> void:
	if sword == null or delta <= 0.0:
		return
	global_transform = Transform3D.IDENTITY
	var xf := sword.global_transform
	_time += delta
	var dt := clampf(delta, 0.002, 1.0 / 30.0)
	var knot0: Vector3 = xf * SpiritSword.CLOTH_KNOTS[0]
	if not _primed or knot0.distance_to(_last_root) > 5.0:
		_hang(xf)
	_speed = lerpf(_speed, knot0.distance_to(_last_root) / delta, 1.0 - exp(-6.0 * delta))
	_last_root = knot0
	var fast := clampf(_speed / 20.0, 0.0, 1.0)
	var n := points_per_strip
	for r in strips.size():
		var spec := strips[r]
		var root := _root(xf, spec)
		var pts := points[r]
		var prv := _prev[r]
		var seg := spec.y / float(n - 1)
		pts[0] = root
		prv[0] = root
		for i in range(1, n):
			var s := float(i) / float(n - 1)
			var p := pts[i]
			var v := (p - prv[i]) / dt
			var acc := Vector3(0.0, -gravity, 0.0) + (breeze - v) * air_drag
			# Turbulence: smooth pseudo-random gusts, stronger at speed and at the tip.
			var ph := _time * (6.0 + r * 1.3) - s * 5.0 + r * 2.1
			acc += Vector3(sin(ph * 1.3), sin(ph * 0.9 + 1.0) * 0.6, cos(ph * 1.1)) * flutter * (0.15 + fast) * s
			prv[i] = p
			pts[i] = p + v * dt + acc * dt * dt
		for _it in iterations:
			pts[0] = root
			for i in range(1, n):
				var d := pts[i] - pts[i - 1]
				var l := d.length()
				if l > 0.00001:
					var corr := d * (1.0 - seg / l)
					if i == 1:
						pts[i] -= corr
					else:
						pts[i - 1] += corr * 0.5
						pts[i] -= corr * 0.5
			# A little stiffness: each point leans toward the middle of its neighbours'
			# straight line, so the strip curves smoothly instead of kinking.
			for i in range(1, n - 1):
				var mid := (pts[i - 1] + pts[i + 1]) * 0.5
				pts[i] = pts[i].lerp(mid, bend_stiffness * 0.5)
			for i in range(1, n):
				pts[i].y = maxf(pts[i].y, ground_height + 0.03)
		points[r] = pts
		_prev[r] = prv
	_rebuild(xf)


func _root(xf: Transform3D, spec: Vector4) -> Vector3:
	var knot: Vector3 = SpiritSword.CLOTH_KNOTS[int(spec.x)]
	return xf * (knot + Vector3(cos(spec.w), sin(spec.w), 0.0) * 0.03)


func _hang(xf: Transform3D) -> void:
	_primed = true
	points.clear()
	_prev.clear()
	var n := points_per_strip
	for spec in strips:
		var root := _root(xf, spec)
		var seg := spec.y / float(n - 1)
		var pts := PackedVector3Array()
		pts.resize(n)
		for i in n:
			# Trailing back along the grip and down.
			pts[i] = root + (xf.basis.z.normalized() * 0.7 + Vector3.DOWN * 0.7).normalized() * seg * i
		points.append(pts)
		_prev.append(pts.duplicate())
	_last_root = xf * SpiritSword.CLOTH_KNOTS[0]


func _rebuild(xf: Transform3D) -> void:
	_mesh.clear_surfaces()
	if points.is_empty():
		return
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var n := points_per_strip
	var m := (n - 1) * subdivisions + 1
	verts.resize(strips.size() * m * 2)
	norms.resize(verts.size())
	uvs.resize(verts.size())
	var up := xf.basis.y.normalized()
	var vi := 0
	for r in strips.size():
		var ctrl := points[r]
		var side := xf.basis.x.normalized()
		var prev_t := Vector3.ZERO
		var base := vi
		for k in m:
			var seg_i := mini(k / subdivisions, n - 2)
			var f := float(k - seg_i * subdivisions) / subdivisions
			if k == m - 1:
				seg_i = n - 2
				f = 1.0
			var c := Ribbons._catmull(ctrl[maxi(seg_i - 1, 0)], ctrl[seg_i], ctrl[seg_i + 1], ctrl[mini(seg_i + 2, n - 1)], f)
			var nxt := Ribbons._catmull(ctrl[maxi(seg_i - 1, 0)], ctrl[seg_i], ctrl[seg_i + 1], ctrl[mini(seg_i + 2, n - 1)], minf(f + 0.05, 1.0))
			var t := nxt - c if f < 1.0 else c - Ribbons._catmull(ctrl[maxi(seg_i - 1, 0)], ctrl[seg_i], ctrl[seg_i + 1], ctrl[mini(seg_i + 2, n - 1)], 0.95)
			if t.length_squared() < 1e-10:
				t = prev_t if prev_t != Vector3.ZERO else Vector3.DOWN
			t = t.normalized()
			prev_t = t
			# Side vector carried along the strip (parallel transport), twisting slowly.
			side = side - t * side.dot(t)
			if side.length_squared() < 0.0001:
				side = up.cross(t)
			side = side.normalized()
			var s := float(k) / float(m - 1)
			var sd := side.rotated(t, 0.9 * s * sin(_time * 1.7 + r * 1.9))
			var nrm := t.cross(sd).normalized()
			var w: float = strips[r].z * (0.65 + 0.35 * smoothstep(0.0, 0.15, s)) * (1.0 - 0.3 * s) * 0.5
			verts[vi] = c - sd * w
			verts[vi + 1] = c + sd * w
			norms[vi] = nrm
			norms[vi + 1] = nrm
			uvs[vi] = Vector2(s, 0.0)
			uvs[vi + 1] = Vector2(s, 1.0)
			vi += 2
		for k in m - 1:
			var a := base + k * 2
			idx.append_array(PackedInt32Array([a, a + 2, a + 1, a + 1, a + 2, a + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh.surface_set_material(0, material_override)
