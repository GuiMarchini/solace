class_name Flora
extends Node3D
## Life around the Drowned Court: date palms in small groves along the shore (curved
## ringed trunks, drooping fronds that sway) and reed tufts in the shallows and on the wet
## sand. Everything is built once, merged (palms) or instanced (reeds), and moved only by
## foliage.gdshader's wind.

const PROPS_LAYER := 4

var _terrain: DuneTerrain
var _rng := RandomNumberGenerator.new()
var _bark := ShaderMaterial.new()
var _frond := ShaderMaterial.new()
var _reed := ShaderMaterial.new()


func build(terrain: DuneTerrain) -> void:
	_terrain = terrain
	_rng.seed = 4242
	var shader := load("res://shaders/foliage.gdshader") as Shader
	for m in [_bark, _frond, _reed]:
		m.shader = shader
	_bark.set_shader_parameter("mode", 0)
	_frond.set_shader_parameter("mode", 1)
	_reed.set_shader_parameter("mode", 2)
	_build_palms()
	_build_reeds()


## A point on the shore at angle `a`: where the sand rises `above` m over the water.
func _shore(a: float, above: float) -> Vector2:
	var c := WorldLayout.OASIS
	var lvl := WorldLayout.water_level
	var dir := Vector2(cos(a), sin(a))
	var r := 20.0
	while r < WorldLayout.OASIS_RIM_RADIUS:
		var p := c + dir * r
		if _terrain.height_at(p.x, p.y) > lvl + above:
			return p
		r += 1.0
	return c + dir * WorldLayout.OASIS_RIM_RADIUS


func _build_palms() -> void:
	var trunks := MeshKit.new()
	var fronds := MeshKit.new()
	var body := StaticBody3D.new()
	body.name = "PalmsBody"
	body.collision_layer = PROPS_LAYER
	body.collision_mask = 0
	add_child(body)
	# Groves on the north-east and south shores (away from the stair and the aqueduct).
	for grove in [[-0.9, 4], [-0.2, 3], [0.9, 5], [1.7, 3], [2.6, 4], [3.6, 3], [4.6, 4], [5.5, 3]]:
		var base_a: float = grove[0]
		for i in int(grove[1]):
			var p := _shore(base_a + _rng.randf_range(-0.12, 0.12), _rng.randf_range(0.3, 2.2))
			p += Vector2(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-4.0, 4.0))
			var g := _terrain.height_at(p.x, p.y)
			if g < WorldLayout.water_level + 0.15:
				continue
			var h := _rng.randf_range(7.0, 12.5)
			# Palms lean out over the water.
			var to_water := (WorldLayout.OASIS - p).normalized()
			var lean := Vector3(to_water.x, 0.0, to_water.y) * _rng.randf_range(0.15, 0.4) + Vector3(_rng.randf_range(-0.1, 0.1), 0.0, _rng.randf_range(-0.1, 0.1))
			var top := _trunk(trunks, Vector3(p.x, g - 0.3, p.y), h, lean)
			_crown(fronds, top)
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.45
			cyl.height = 3.0
			cs.shape = cyl
			cs.position = Vector3(p.x, g + 1.5, p.y)
			body.add_child(cs)
	for pair in [[trunks, _bark, "PalmTrunks"], [fronds, _frond, "PalmFronds"]]:
		var mi := MeshInstance3D.new()
		mi.name = pair[2]
		mi.mesh = (pair[0] as MeshKit).commit()
		mi.material_override = pair[1]
		add_child(mi)


## A curved, tapering trunk; returns its top.
func _trunk(k: MeshKit, base: Vector3, h: float, lean: Vector3) -> Vector3:
	var rings := 14
	var segs := 8
	var pts := PackedVector3Array()
	var cols := PackedColorArray()
	var top := base
	for r in rings + 1:
		var t := float(r) / rings
		# Bowed: leaning more toward the top.
		var c := base + Vector3.UP * h * t + lean * h * t * t
		var tangent := (Vector3.UP + lean * 2.0 * t).normalized()
		var side := tangent.cross(Vector3.FORWARD).normalized()
		var fwd := side.cross(tangent).normalized()
		var rad := lerpf(0.38, 0.22, t) * (1.0 + 0.25 * pow(1.0 - t, 6.0))
		for s in segs:
			var a := TAU * s / segs
			pts.append(c + (side * cos(a) + fwd * sin(a)) * rad)
			cols.append(Color(t, 0.5, 1.0, t * t * 0.5))
		top = c
	k.grid(pts, rings + 1, segs, true, cols)
	return top


## A crown of drooping fronds.
func _crown(k: MeshKit, top: Vector3) -> void:
	var n := _rng.randi_range(9, 13)
	for i in n:
		var a := TAU * i / n + _rng.randf_range(-0.2, 0.2)
		var out := Vector3(cos(a), 0.0, sin(a))
		var rise := _rng.randf_range(0.2, 1.0)
		var length := _rng.randf_range(3.2, 5.0)
		var rows := 12
		var cols := 5
		var pts := PackedVector3Array()
		var cc := PackedColorArray()
		var side := out.cross(Vector3.UP).normalized()
		for r in rows:
			var t := float(r) / (rows - 1)
			# The midrib arcs up and out, then droops under its own weight.
			var spine := top + out * length * t + Vector3.UP * (rise * length * 0.45 * t - length * 0.75 * t * t)
			var w := 0.75 * pow(sin(PI * clampf(t * 0.95 + 0.05, 0.0, 1.0)), 0.6)
			for c in cols:
				var u := float(c) / (cols - 1) * 2.0 - 1.0
				# Folded a little along the midrib (a shallow V).
				pts.append(spine + side * u * w + Vector3.UP * absf(u) * w * 0.25)
				cc.append(Color(t, (u + 1.0) * 0.5, 1.0, 0.25 + 0.75 * t))
		k.grid(pts, rows, cols, false, cc)


func _build_reeds() -> void:
	var tuft := MeshKit.new()
	for b in 9:
		var a := TAU * b / 9.0 + _rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0.0, sin(a))
		var h := _rng.randf_range(0.9, 1.7)
		var pts := PackedVector3Array()
		var cc := PackedColorArray()
		var side := out.cross(Vector3.UP).normalized()
		var root := out * _rng.randf_range(0.0, 0.15)
		for r in 6:
			var t := r / 5.0
			var c := root + Vector3.UP * h * t + out * h * 0.35 * t * t
			for s in 2:
				var u := float(s) * 2.0 - 1.0
				pts.append(c + side * u * 0.035)
				cc.append(Color(t, (u + 1.0) * 0.5, 1.0, t))
		tuft.grid(pts, 6, 2, false, cc)
	var mesh := tuft.commit()
	var xfs: Array[Transform3D] = []
	var lvl := WorldLayout.water_level
	for i in 420:
		var a := _rng.randf() * TAU
		var p := _shore(a, _rng.randf_range(-0.4, 0.9)) + Vector2(_rng.randf_range(-2.5, 2.5), _rng.randf_range(-2.5, 2.5))
		var g := _terrain.height_at(p.x, p.y)
		if g < lvl - 0.6 or g > lvl + 1.2:
			continue
		var s := _rng.randf_range(0.7, 1.4)
		xfs.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, maxf(g, lvl - 0.6) - 0.05, p.y)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Reeds"
	mmi.multimesh = mm
	mmi.material_override = _reed
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
