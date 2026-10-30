class_name StoneKit
extends RefCounted
## The pieces the ruins and rock formations are made of, added into a MeshKit at a
## transform: fluted columns (whole or broken off), fallen drums, arches of voussoirs on
## stacked piers, stairs, broken walls, tapered monoliths and layered sandstone mesas.
## All dimensions in metres; everything stands on its local origin, +Y up.


## A fluted column on a plinth. `broken` (0..1) breaks the shaft off at that fraction of
## its height with a jagged, slanted top (0 = whole, with its capital).
static func column(k: MeshKit, xf: Transform3D, height: float, r: float, seed: int, broken := 0.0,
		flutes := 14) -> void:
	var nz := MeshKit.noise()
	k.block(xf * Transform3D(Basis(), Vector3(0.0, r * 0.35, 0.0)), Vector3(r * 2.7, r * 0.7, r * 2.7), r * 0.08, r * 0.05, seed)
	# Moulded base ring.
	k.tube(xf * Transform3D(Basis(), Vector3(0.0, r * 0.7, 0.0)), r * 0.4, 24, 3,
		func(_a: float, t: float) -> float: return r * lerpf(1.28, 1.04, t),
		func(_a: float) -> float: return r * 0.4,
		func(_a: float) -> float: return 0.85, false)
	var y0 := r * 1.1
	var shaft := height - y0 - (0.0 if broken > 0.0 else r * 0.95)
	var top := shaft
	var slant := float(seed % 7) / 7.0 * TAU
	var jag := func(a: float) -> float:
		if broken <= 0.0:
			return shaft
		var j := nz.get_noise_2d(cos(a) * 2.3 + seed, sin(a) * 2.3) * r * 0.9
		return maxf(shaft * broken + j + cos(a - slant) * r * 0.55, r * 0.5)
	k.tube(xf * Transform3D(Basis(), Vector3(0.0, y0, 0.0)), shaft, 28, maxi(int(shaft / 1.1), 4),
		func(a: float, t: float) -> float:
			var wear := nz.get_noise_3d(cos(a) * 1.5 + seed, t * 5.0, sin(a) * 1.5) * 0.05
			return r * (1.0 - 0.1 * t) * (1.0 + 0.035 * cos(flutes * a) + wear),
		jag,
		func(a: float) -> float: return 0.72 + 0.28 * cos(flutes * a),
		true)
	if broken > 0.0:
		return
	# Capital: a flaring echinus and a square abacus.
	var cy := y0 + top
	k.tube(xf * Transform3D(Basis(), Vector3(0.0, cy, 0.0)), r * 0.5, 24, 3,
		func(_a: float, t: float) -> float: return r * lerpf(0.9, 1.32, t * t),
		func(_a: float) -> float: return r * 0.5,
		func(_a: float) -> float: return 0.8, false)
	k.block(xf * Transform3D(Basis(), Vector3(0.0, cy + r * 0.72, 0.0)), Vector3(r * 2.9, r * 0.45, r * 2.9), r * 0.06, r * 0.05, seed + 1)


## A column drum lying on its side (fallen), axis along local X.
static func drum(k: MeshKit, xf: Transform3D, length: float, r: float, seed: int) -> void:
	var nz := MeshKit.noise()
	var lay := xf * Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3(-length * 0.5, r * 0.85, 0.0))
	k.tube(lay, length, 24, 3,
		func(a: float, t: float) -> float:
			return r * (1.0 + 0.035 * cos(14.0 * a) + nz.get_noise_3d(cos(a) + seed, t * 3.0, sin(a)) * 0.06),
		func(a: float) -> float: return length + nz.get_noise_2d(cos(a) * 2.0 + seed, sin(a) * 2.0) * r * 0.5,
		func(a: float) -> float: return 0.72 + 0.28 * cos(14.0 * a), true, true)


## An arch: two piers of stacked blocks and a half ring of voussoirs. `span` is the clear
## opening; `missing` lists voussoir indices that have fallen.
static func arch(k: MeshKit, xf: Transform3D, span: float, pier_h: float, depth: float, thick: float,
		seed: int, missing: Array = []) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for side: float in [-1.0, 1.0]:
		var x := side * (span * 0.5 + thick * 0.5)
		var y := 0.0
		k.block(xf * Transform3D(Basis(), Vector3(x, 0.4, 0.0)), Vector3(thick * 1.3, 0.8, depth * 1.2), 0.1, 0.06, seed)
		y = 0.8
		while y < pier_h - 0.2:
			var bh := minf(rng.randf_range(1.2, 1.8), pier_h - y)
			var off := Vector3(rng.randf_range(-0.06, 0.06), y + bh * 0.5, rng.randf_range(-0.06, 0.06))
			k.block(xf * Transform3D(Basis(Vector3.UP, rng.randf_range(-0.03, 0.03)), Vector3(x, 0.0, 0.0) + off),
				Vector3(thick, bh * 0.97, depth), 0.08, 0.06, seed + int(y * 10.0))
			y += bh
		# Impost block.
		k.block(xf * Transform3D(Basis(), Vector3(x, pier_h + 0.25, 0.0)), Vector3(thick * 1.25, 0.5, depth * 1.1), 0.06, 0.04, seed + 3)
	var rad := span * 0.5 + thick * 0.5
	var n := maxi(int(PI * rad / 1.6), 7)
	for i in n:
		if missing.has(i):
			continue
		var a := PI * (float(i) + 0.5) / n
		var key := 1.25 if i == n / 2 else 1.0
		var b := Basis(Vector3.BACK, a)
		k.block(xf * Transform3D(b, Vector3(cos(a) * rad, pier_h + 0.5 + sin(a) * rad, 0.0)),
			Vector3(thick * key, PI * rad / n * 0.96, depth), 0.07, 0.05, seed + 20 + i)


## Steps rising along -Z: `count` steps of `rise` x `run`, `width` wide.
static func stairs(k: MeshKit, xf: Transform3D, width: float, count: int, rise: float, run: float, seed: int) -> void:
	for i in count:
		var h := rise * (i + 1)
		k.block(xf * Transform3D(Basis(), Vector3(0.0, h * 0.5, -run * (i + 0.5))),
			Vector3(width, h, run), 0.05, 0.05, seed + i)


## A broken wall of coursed blocks along local X, ragged on top.
static func wall(k: MeshKit, xf: Transform3D, length: float, height: float, thick: float, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var nz := MeshKit.noise()
	var course := 0
	var y := 0.0
	while y < height:
		var bh := rng.randf_range(0.8, 1.1)
		var x := -length * 0.5 + (0.6 if course % 2 == 1 else 0.0)
		while x < length * 0.5:
			var bl := minf(rng.randf_range(1.4, 2.2), length * 0.5 - x)
			var limit := height * (0.55 + 0.45 * (nz.get_noise_2d(x * 0.15 + seed, 0.0) * 0.5 + 0.5))
			if y + bh <= limit and bl > 0.4:
				k.block(xf * Transform3D(Basis(Vector3.UP, rng.randf_range(-0.02, 0.02)), Vector3(x + bl * 0.5, y + bh * 0.5, rng.randf_range(-0.05, 0.05))),
					Vector3(bl * 0.97, bh * 0.96, thick), 0.07, 0.06, seed + course * 31 + int(x * 7.0))
			x += bl
		y += bh
		course += 1


## A tall standing stone, tapering, its top cut at a slant.
static func monolith(k: MeshKit, xf: Transform3D, height: float, width: float, seed: int) -> void:
	var nz := MeshKit.noise()
	k.tube(xf, height, 6, maxi(int(height / 1.5), 3),
		func(a: float, t: float) -> float:
			return width * (1.0 - 0.28 * t) * (1.0 + nz.get_noise_3d(cos(a) + seed, t * 3.0, sin(a)) * 0.1),
		func(a: float) -> float: return height * (1.0 + 0.08 * cos(a + seed)),
		func(_a: float) -> float: return 0.85, true)


## A sandstone butte: a talus skirt at the foot, cliffs leaning slightly inward and broken
## into ledges by the strata, deep gullies down the sides, a cap-rock lip and a ragged
## crown. Built down to `bury` below its base. Several overlapping ones make a mesa
## (see `mesa_cluster`).
static func mesa(k: MeshKit, xf: Transform3D, radius: float, height: float, seed: int, segs := 72,
		bury := 25.0) -> void:
	var nz := MeshKit.noise()
	var ledge := clampf(height / 6.0, 4.0, 30.0)
	var total := height + bury
	var shape := func(a: float) -> float:
		return 1.0 + nz.get_noise_2d(cos(a) * 1.2 + seed, sin(a) * 1.2) * 0.38 				+ nz.get_noise_2d(cos(a) * 4.0 - seed, sin(a) * 4.0) * 0.09
	k.tube(xf * Transform3D(Basis(), Vector3(0.0, -bury, 0.0)), total, segs, maxi(int(total / (ledge * 0.2)), 16),
		func(a: float, t: float) -> float:
			var y := t * total - bury
			var hn := clampf(y / height, 0.0, 1.0)
			var f := fposmod(y / ledge + nz.get_noise_2d(cos(a) * 2.0, sin(a) * 2.0) * 0.5, 1.0)
			# Each stratum juts out at its top, then steps back at the seam below it.
			var step := smoothstep(0.0, 0.12, f) * 0.05 - 0.05
			var g := nz.get_noise_2d(a * 7.0 + seed, y * 0.004)
			var gully := pow(maxf(g, 0.0), 1.5) * 0.32
			var talus := pow(maxf(0.0, 1.0 - hn / 0.3), 1.7) * 0.75
			var lean := -0.16 * hn
			var lip := smoothstep(0.86, 0.9, hn) * 0.05 - smoothstep(0.97, 1.0, hn) * 0.08
			return radius * float(shape.call(a)) * (1.0 + step + lean + talus + lip - gully * (1.0 - talus)),
		func(a: float) -> float:
			return total + nz.get_noise_2d(cos(a) * 2.5 + seed, sin(a) * 2.5) * height * 0.07,
		func(a: float) -> float: return 0.55 + 0.45 * (1.0 - pow(maxf(nz.get_noise_2d(a * 7.0 + seed, 0.0), 0.0), 1.2)),
		true)


## A mesa as a cluster: a main butte with lower ones leaning against it, so the
## silhouette steps and breaks instead of reading as one drum.
static func mesa_cluster(k: MeshKit, xf: Transform3D, radius: float, height: float, seed: int, segs := 72,
		bury := 25.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	mesa(k, xf, radius, height, seed, segs, bury)
	var n := 2 + seed % 2
	for i in n:
		var a := rng.randf() * TAU
		var off := Vector3(cos(a), 0.0, sin(a)) * radius * rng.randf_range(0.55, 0.85)
		var r := radius * rng.randf_range(0.4, 0.62)
		var h := height * rng.randf_range(0.45, 0.85)
		mesa(k, xf * Transform3D(Basis(), off), r, h, seed * 13 + i, maxi(segs / 2, 32), bury)
	# Sometimes a lone spire standing off it.
	if seed % 3 == 0:
		var a2 := rng.randf() * TAU
		var off2 := Vector3(cos(a2), 0.0, sin(a2)) * radius * 1.6
		mesa(k, xf * Transform3D(Basis(), off2), radius * 0.18, height * 0.75, seed * 7 + 5, 24, bury)
