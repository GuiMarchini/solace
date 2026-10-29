class_name SpiritSword
extends RefCounted
## The spirit's sword: an ancient blade of weathered stone, forgotten by time. It is her
## locomotion underfoot (she stands on its flat) and, in combat, the weapon in hand.
## Follows the concept sheet (nova-referencia/Prancha Conceitual Solace_ Lâmina
## Espiritual.png): a broad blade framed by stacked stone plates with stepped, chipped
## edges around a darker recessed core; a rune line burns in a channel down the core from
## a rune circle below the guard; an arched collar with two claws grips the blade; a
## wrapped grip ends in an octagonal ring. Underneath, a glowing slot (her propulsion).
## Built from flat-shaded faceted pieces so the stone keeps crisp edges; vertex COLOR
## tags each piece for spirit_sword.gdshader (r = part, g = per-piece tone, b = 1 on the
## underside slot). The cloth strips tied to the grip are SwordCloth.
## Frame: origin on the top face of the blade between the rider's feet, tip toward -Z,
## grip toward +Z.

## The stone pieces are designed broad (as on the sheet) and slimmed into a slender
## blade at the end (`WX` across, `WY` in thickness); round pieces (rune circle, grip,
## ring) are built at their final size so they stay round.
const WX := 0.62
const WY := 0.74
## Blade from the guard (z = GUARD_Z) to the tip (z = TIP_Z); its top face is y = 0.
const TIP_Z := -1.22
const GUARD_Z := 0.5
const HALF_WIDTH := 0.175 * WX
## Half the blade's thickness (the blade's centre line is y = -THICK).
const THICK := _T * WY
## Where the hand holds it (grip centre), in this frame.
const GRIP := Vector3(0.0, -THICK, 0.79)
## Rune circle below the guard (centre, on top of its boss) and its radius.
const EMBLEM := Vector3(0.0, -0.003 * WY, 0.355)
const EMBLEM_RADIUS := 0.046 * WX
## Where the cloth strips are tied (grip, below the collar and below the ring).
const CLOTH_KNOTS: Array[Vector3] = [Vector3(0.0, -THICK, 0.7), Vector3(0.0, -THICK, 0.925)]

# Part tags (vertex COLOR.r), read by spirit_sword.gdshader.
const FRAME := 0.0
const CORE := 0.15
const TIP := 0.3
const GUARD := 0.45
const GRIP_WRAP := 0.6
const CLOTH := 0.75
const BOSS := 0.9
const RUNE := 1.0
## Ring pommel and its neck: stone, but not slimmed.
const RING := 0.46

## Design-space half thickness of the stone pieces (before slimming).
const _T := 0.027

const _CORE_TOP := -0.007
const _CORE_BOTTOM := -0.047
const _GROOVE_HALF := 0.009
const _GROOVE_DEPTH := 0.005

static var _mesh: ArrayMesh


static func mesh() -> ArrayMesh:
	if _mesh == null:
		_mesh = _build()
	return _mesh


## Outer half-width of the blade's frame at a z along it (design space, before the
## per-plate steps and the slimming).
static func outer_half_width(z: float) -> float:
	return 0.175 * (1.0 - 0.06 * _along(z))


static func _core_half_width(z: float) -> float:
	return 0.074 - 0.014 * _along(z)


## 0 at the guard, 1 at the tip.
static func _along(z: float) -> float:
	return clampf((GUARD_Z - z) / (GUARD_Z - TIP_Z), 0.0, 1.0)


# --- Building ------------------------------------------------------------------------------

class _Builder:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	## Flat triangle given counter-clockwise as seen from outside (Godot's front faces are
	## clockwise, so it is stored reversed).
	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-14:
			return
		n = n.normalized()
		verts.append_array(PackedVector3Array([a, c, b]))
		normals.append_array(PackedVector3Array([n, n, n]))
		colors.append_array(PackedColorArray([col, col, col]))

	## Faceted loft: consecutive sections (closed polygons with the same vertex count,
	## counter-clockwise in their own XY plane) placed by `xfs`, ordered along each
	## transform's +Z, joined by flat quads. `caps` closes both ends; `smooth` gives the
	## sides radial normals instead (round pieces such as the grip).
	func loft(polys: Array, xfs: Array, col: Color, caps := true, smooth := false) -> void:
		var rings := []
		for s in polys.size():
			var ring := PackedVector3Array()
			for q: Vector2 in polys[s]:
				ring.append(xfs[s] * Vector3(q.x, q.y, 0.0))
			rings.append(ring)
		var n: int = rings[0].size()
		for s in rings.size() - 1:
			var A: PackedVector3Array = rings[s]
			var B: PackedVector3Array = rings[s + 1]
			for i in n:
				var j := (i + 1) % n
				if smooth:
					var ca: Vector3 = xfs[s].origin
					var cb: Vector3 = xfs[s + 1].origin
					var na := [(A[i] - ca).normalized(), (A[j] - ca).normalized()]
					var nb := [(B[i] - cb).normalized(), (B[j] - cb).normalized()]
					verts.append_array(PackedVector3Array([A[i], B[j], A[j], A[i], B[i], B[j]]))
					normals.append_array(PackedVector3Array([na[0], nb[1], na[1], na[0], nb[0], nb[1]]))
					for _k in 6:
						colors.append(col)
				else:
					tri(A[i], A[j], B[j], col)
					tri(A[i], B[j], B[i], col)
		if caps:
			cap(rings[0], polys[0], col, true)
			cap(rings[rings.size() - 1], polys[polys.size() - 1], col, false)

	## Closes a section (facing backward along the loft for the first one).
	func cap(ring: PackedVector3Array, poly: PackedVector2Array, col: Color, first: bool) -> void:
		var idx := Geometry2D.triangulate_polygon(poly)
		for t in range(0, idx.size(), 3):
			var i0 := idx[t]
			var i1 := idx[t + 1]
			var i2 := idx[t + 2]
			var ccw := (poly[i1] - poly[i0]).cross(poly[i2] - poly[i0]) > 0.0
			if ccw != first:
				tri(ring[i0], ring[i1], ring[i2], col)
			else:
				tri(ring[i0], ring[i2], ring[i1], col)

	func commit() -> ArrayMesh:
		# Slim the stone pieces into the final blade (normals by the inverse scale).
		for i in verts.size():
			var tag := colors[i].r
			if tag < 0.455 or tag > 0.95:
				var v := verts[i]
				verts[i] = Vector3(v.x * WX, v.y * WY, v.z)
				var n := normals[i]
				normals[i] = Vector3(n.x / WX, n.y / WY, n.z).normalized()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m


static func _at(z: float, y := 0.0, x := 0.0) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(x, y, z))


static func _build() -> ArrayMesh:
	var b := _Builder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1931

	# Recessed core: the rune channel on top, the propulsion slot underneath.
	var polys := []
	var xfs := []
	for z in [-1.0, -0.45, 0.1, GUARD_Z + 0.03]:
		polys.append(_core_section(_core_half_width(z)))
		xfs.append(_at(z))
	b.loft(polys, xfs, Color(CORE, 0.5, 0.0))

	# Frame: stacked stone plates of uneven lengths down both edges, joined at slightly
	# skewed seams; each is a little narrower at its tip end (the outline steps out again
	# at the next plate), some are chipped, the first ones flare into shoulders under
	# the guard.
	var lens := [[0.26, 0.33, 0.24, 0.35, 0.28], [0.31, 0.27, 0.33, 0.25, 0.3]]
	for si in 2:
		var side := -1.0 if si == 0 else 1.0
		var z_hi := GUARD_Z
		var slope_hi := 0.0
		for k in lens[si].size():
			var z_lo: float = z_hi - lens[si][k]
			var slope_lo := rng.randf_range(-0.15, 0.15) if k < lens[si].size() - 1 else 0.0
			_plate(b, rng, side, z_lo, z_hi, slope_lo, slope_hi, 0.014 if k == 0 else 0.0)
			z_hi = z_lo
			slope_hi = slope_lo

	# Angular tip piece with a faint ridge, where the frame converges.
	polys = []
	xfs = []
	for s in [[TIP_Z, 0.004, 0.25], [-1.035, 0.148, 0.95], [-0.962, 0.168, 1.0]]:
		polys.append(_tip_section(s[1], s[2]))
		xfs.append(_at(s[0]))
	b.loft(polys, xfs, Color(TIP, rng.randf(), 0.0))

	# Raised boss carrying the rune circle (the symbol itself is drawn by the shader).
	var disc := _ngon(0.066 * WX, 16)
	polys = [disc, disc, _ngon(0.061 * WX, 16)]
	xfs = []
	for y in [-0.012 * WY, -0.0065 * WY, EMBLEM.y]:
		xfs.append(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(EMBLEM.x, y, EMBLEM.z)))
	b.loft(polys, xfs, Color(BOSS, 0.5, 0.0))

	# Rune line in the channel (from the circle down to the tip piece, plus a short
	# tick above the circle) and the slot underneath.
	var line_y := _CORE_TOP - _GROOVE_DEPTH + 0.0015
	_bar(b, Vector3(0.0, line_y, -0.93), Vector3(0.0, line_y, EMBLEM.z - EMBLEM_RADIUS - 0.003), 0.0045, 0.0015, Color(RUNE, 0.5, 0.0))
	_bar(b, Vector3(0.0, line_y, EMBLEM.z + EMBLEM_RADIUS + 0.003), Vector3(0.0, line_y, EMBLEM.z + EMBLEM_RADIUS + 0.025), 0.0045, 0.0015, Color(RUNE, 0.5, 0.0))
	var slot_y := _CORE_BOTTOM + _GROOVE_DEPTH - 0.0015
	_bar(b, Vector3(0.0, slot_y, -0.9), Vector3(0.0, slot_y, 0.2), 0.0045, 0.0015, Color(RUNE, 0.5, 1.0))

	# The guard: a chunky, faceted stone collar like a cut gem, rising above the blade
	# and narrowing toward the grip, flanked by two tall shoulder plates.
	polys = []
	xfs = []
	for c in [[0.43, 0.06, 0.02], [0.46, 0.115, 0.05], [0.52, 0.125, 0.058], [0.58, 0.11, 0.055],
			[0.63, 0.075, 0.045], [0.665, 0.044, 0.036], [0.682, 0.032, 0.03]]:
		polys.append(_gem_section(c[1], c[2]))
		xfs.append(_at(c[0], -_T + 0.006))
	b.loft(polys, xfs, Color(GUARD, rng.randf(), 0.0))
	for side in [-1.0, 1.0]:
		polys = []
		xfs = []
		for c in [[0.24, 0.161, 0.01, 0.018], [0.31, 0.164, 0.025, 0.037], [0.47, 0.167, 0.031, 0.047], [0.56, 0.158, 0.02, 0.04]]:
			polys.append(_gem_section(c[2], c[3]))
			xfs.append(_at(c[0], -_T + 0.014, side * c[1]))
		b.loft(polys, xfs, Color(GUARD, rng.randf(), 0.0))

	# Thick wrapped grip, with cloth knotted at the guard and below the ring.
	var round14 := _ngon(1.0, 14)
	polys = []
	xfs = []
	for c in [[0.66, 0.025], [0.95, 0.023]]:
		polys.append(_scaled(round14, c[1]))
		xfs.append(_at(c[0], -THICK))
	b.loft(polys, xfs, Color(GRIP_WRAP, 0.5, 0.0), true, true)
	for knot in [[0.684, [0.025, 0.029, 0.0275, 0.0295, 0.026], 0.012], [0.9, [0.024, 0.028, 0.027, 0.029, 0.0275, 0.024], 0.01]]:
		polys = []
		xfs = []
		var radii: Array = knot[1]
		for i in radii.size():
			polys.append(_scaled(round14, radii[i]))
			xfs.append(_at(knot[0] + i * knot[2], -THICK))
		b.loft(polys, xfs, Color(CLOTH, rng.randf(), 0.0), true, true)

	# Neck and a big octagonal ring pommel (lying in the blade's plane, as on the sheet).
	polys = []
	xfs = []
	for c in [[0.94, 0.024, 0.024], [0.958, 0.03, 0.027], [0.972, 0.027, 0.025]]:
		polys.append(_box_section(c[1], c[2], 0.007))
		xfs.append(_at(c[0], -THICK))
	b.loft(polys, xfs, Color(RING, rng.randf(), 0.0))
	var ring_r := 0.06
	var tube := _box_section(0.017, 0.02, 0.007)
	var ring_c := Vector3(0.0, -THICK, 0.962 + ring_r + 0.017)
	polys = []
	xfs = []
	for i in 9:
		var phi := TAU * i / 8.0 - PI * 0.5
		var radial := Vector3(cos(phi), 0.0, sin(phi))
		var tangent := Vector3(-sin(phi), 0.0, cos(phi))
		polys.append(tube)
		xfs.append(Transform3D(Basis(radial, Vector3.UP, tangent), ring_c + radial * ring_r))
	b.loft(polys, xfs, Color(RING, rng.randf(), 0.0), false)
	return b.commit()


## One stone plate of the frame between z_lo (tip side) and z_hi. Its end seams are
## skewed by `slope_*` (z shift per metre of x), `flare` widens it (shoulders).
static func _plate(b: _Builder, rng: RandomNumberGenerator, side: float, z_lo: float, z_hi: float,
		slope_lo: float, slope_hi: float, flare: float) -> void:
	var gap := 0.003
	var jitter := rng.randf_range(-0.009, 0.009)
	var w_lo := outer_half_width(z_lo) * 0.95 + jitter + flare * 0.4
	var w_hi := outer_half_width(z_hi) + jitter + flare
	# Hand-cut stone: each plate sits a hair higher or lower than its neighbours.
	var lift := rng.randf_range(-0.0015, 0.0015)
	var zs := [z_lo + gap, z_lo + gap + 0.014]
	var chips := [0.0, 0.0]
	if rng.randf() < 0.7:
		var zc := rng.randf_range(z_lo + 0.07, z_hi - 0.07)
		var depth := rng.randf_range(0.012, 0.028)
		zs.append_array([zc - 0.03, zc, zc + 0.014])
		chips.append_array([0.0, depth, 0.0])
	zs.append_array([z_hi - gap - 0.014, z_hi - gap])
	chips.append_array([0.0, 0.0])
	var polys := []
	var xfs := []
	var last := zs.size() - 1
	for i in zs.size():
		var w := lerpf(w_lo, w_hi, inverse_lerp(z_lo + gap, z_hi - gap, zs[i]))
		var poly := _plate_section(w, _core_half_width(zs[i]) - 0.012, chips[i], i == 0 or i == last)
		polys.append(_mirrored(poly) if side < 0.0 else poly)
		var slope := slope_lo if i < 2 else (slope_hi if i > last - 2 else (slope_lo + slope_hi) * 0.5)
		xfs.append(Transform3D(Basis(Vector3(1.0, 0.0, slope), Vector3.UP, Vector3.BACK), Vector3(0.0, lift, zs[i])))
	b.loft(polys, xfs, Color(FRAME, rng.randf(), 0.0))


## Right-side plate profile: flat top (y = 0), a worn bevel down to the outer edge, a
## chamfer into the core. `chip` bites into the outer edge from the top corner;
## `inset` shrinks it (the chamfered ends of the plate).
static func _plate_section(w: float, xi: float, chip: float, inset: bool) -> PackedVector2Array:
	var bot := -2.0 * _T
	var pts := PackedVector2Array([Vector2(w - chip, -0.036), Vector2(w - chip, -0.018), Vector2(w - 0.032 - chip * 0.6, 0.0),
		Vector2(xi + 0.016, 0.0), Vector2(xi, -0.012), Vector2(xi, bot + 0.012), Vector2(xi + 0.016, bot),
		Vector2(w - 0.032, bot)])
	if inset:
		var c := Vector2((w + xi) * 0.5, -_T)
		for i in pts.size():
			pts[i] = c + (pts[i] - c) * Vector2(0.94, 0.78)
	return pts


static func _core_section(wc: float) -> PackedVector2Array:
	var t := _CORE_TOP
	var bt := _CORE_BOTTOM
	var g := _GROOVE_HALF
	var d := _GROOVE_DEPTH
	var ch := 0.006
	return PackedVector2Array([Vector2(wc, bt + ch), Vector2(wc, t - ch), Vector2(wc - ch, t), Vector2(g, t), Vector2(g, t - d),
		Vector2(-g, t - d), Vector2(-g, t), Vector2(-wc + ch, t), Vector2(-wc, t - ch), Vector2(-wc, bt + ch),
		Vector2(-wc + ch, bt), Vector2(-g, bt), Vector2(-g, bt + d), Vector2(g, bt + d), Vector2(g, bt), Vector2(wc - ch, bt)])


static func _tip_section(a: float, s: float) -> PackedVector2Array:
	var yc := -_T
	var h := _T * s
	return PackedVector2Array([Vector2(a, yc), Vector2(a * 0.55, yc + h), Vector2(0.0, yc + h + 0.004 * s), Vector2(-a * 0.55, yc + h),
		Vector2(-a, yc), Vector2(-a * 0.55, yc - h), Vector2(0.0, yc - h - 0.004 * s), Vector2(a * 0.55, yc - h)])


## Faceted gem-like profile centred on the origin: a ridge on top, bevelled flanks.
static func _gem_section(hw: float, hh: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(hw, -hh * 0.35), Vector2(hw * 0.78, hh * 0.55), Vector2(hw * 0.3, hh * 0.95),
		Vector2(0.0, hh * 1.05), Vector2(-hw * 0.3, hh * 0.95), Vector2(-hw * 0.78, hh * 0.55), Vector2(-hw, -hh * 0.35),
		Vector2(-hw * 0.7, -hh), Vector2(hw * 0.7, -hh)])


## Chamfered rectangle centred on the origin.
static func _box_section(hw: float, hh: float, ch: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(hw, -hh + ch), Vector2(hw, hh - ch), Vector2(hw - ch, hh), Vector2(-hw + ch, hh),
		Vector2(-hw, hh - ch), Vector2(-hw, -hh + ch), Vector2(-hw + ch, -hh), Vector2(hw - ch, -hh)])


static func _ngon(r: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts


static func _scaled(poly: PackedVector2Array, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in poly:
		out.append(q * s)
	return out


## Mirrors a profile to the other side of the blade, keeping it counter-clockwise.
static func _mirrored(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(poly.size() - 1, -1, -1):
		out.append(Vector2(-poly[i].x, poly[i].y))
	return out


## A thin bar from a to b (along z), half-width hw, half-height hh.
static func _bar(b: _Builder, a: Vector3, c: Vector3, hw: float, hh: float, col: Color) -> void:
	var sec := _box_section(hw, hh, hh * 0.5)
	b.loft([sec, sec], [_at(a.z, a.y, a.x), _at(c.z, c.y, c.x)], col)
