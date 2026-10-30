class_name WorldBuilder
extends Node3D
## Builds the places of the first environment on the dunes (see WorldLayout): the
## Pilgrim's Colonnade with its gateway, the Watchers' ring, the Drowned Court (flooded
## ruins), sandstone mesas (solid ones framing the playable sea, a far wall of them on the
## horizon), rock clusters, half-buried fragments near the start, and two colossal far
## landmarks: the Fallen Blade and the Sleeping Warden.
##
## Each site is merged into one mesh per material (one draw call); collisions are simple
## shapes on layer 4 ("props": solid to her, avoided by the camera). The oasis water is a
## WaterSurface whose flat body (layer 1) she rides on like the sand.

@export var terrain_path: NodePath = ^"../DuneTerrain"

const PROPS_LAYER := 4

var ruin_material := ShaderMaterial.new()
var sandstone_material := ShaderMaterial.new()
var glyph_material := StandardMaterial3D.new()
## Where banners stand (effects add them): [position, facing yaw].
var banner_spots: Array = []

var _terrain: DuneTerrain
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_terrain = get_node(terrain_path) as DuneTerrain
	_rng.seed = 2026
	var t0 := Time.get_ticks_msec()
	_make_materials()
	_build_colonnade()
	_build_watchers()
	_build_oasis()
	_build_mesas()
	_build_rocks()
	_build_far_landmarks()
	_build_far_ruins()
	var amb := AmbienceFX.new()
	amb.name = "Ambience"
	add_child(amb)
	amb.build(self, _terrain)
	print("[WorldBuilder] built in %d ms" % (Time.get_ticks_msec() - t0))


func _ground(x: float, z: float) -> float:
	return _terrain.height_at(x, z)


func _make_materials() -> void:
	var shader := load("res://shaders/stone.gdshader") as Shader
	ruin_material.shader = shader
	ruin_material.set_shader_parameter("strata", 0.0)
	# Weathered ochre limestone, darker than the sand so the ruins read against it.
	ruin_material.set_shader_parameter("stone_light", Color(0.82, 0.66, 0.5))
	ruin_material.set_shader_parameter("stone_mid", Color(0.69, 0.52, 0.39))
	ruin_material.set_shader_parameter("stone_dark", Color(0.47, 0.33, 0.26))
	ruin_material.set_shader_parameter("seam_color", Color(0.34, 0.23, 0.19))
	sandstone_material.shader = shader
	sandstone_material.set_shader_parameter("strata", 1.0)
	sandstone_material.set_shader_parameter("strata_scale", 0.11)
	# Rose-orange sandstone with cream bands and deep rust seams.
	sandstone_material.set_shader_parameter("stone_light", Color(0.88, 0.6, 0.44))
	sandstone_material.set_shader_parameter("stone_mid", Color(0.74, 0.44, 0.31))
	sandstone_material.set_shader_parameter("stone_dark", Color(0.5, 0.27, 0.21))
	sandstone_material.set_shader_parameter("seam_color", Color(0.36, 0.19, 0.16))
	sandstone_material.set_shader_parameter("detail_distance", 160.0)
	glyph_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glyph_material.albedo_color = Color(0.55, 0.88, 1.0) * 2.2


## Adds a merged mesh to the scene.
func _add_mesh(n: String, k: MeshKit, mat: Material, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = k.commit(_ground)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _body(n: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = n
	body.collision_layer = PROPS_LAYER
	body.collision_mask = 0
	add_child(body)
	return body


func _solid(body: StaticBody3D, shape: Shape3D, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	body.add_child(cs)


func _cylinder(body: StaticBody3D, at: Vector3, r: float, h: float) -> void:
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	_solid(body, c, Transform3D(Basis(), at + Vector3.UP * h * 0.5))


func _box(body: StaticBody3D, xf: Transform3D, size: Vector3) -> void:
	var b := BoxShape3D.new()
	b.size = size
	_solid(body, b, xf)


## A frame standing on the sand at XZ, local X along `right` (Y up), sunk `sink` m.
func _frame(p: Vector2, right: Vector2, sink: float) -> Transform3D:
	var x := Vector3(right.x, 0.0, right.y).normalized()
	var z := x.cross(Vector3.UP)
	return Transform3D(Basis(x, Vector3.UP, z), Vector3(p.x, _ground(p.x, p.y) - sink, p.y))


# --- The Pilgrim's Colonnade ---------------------------------------------------------

func _build_colonnade() -> void:
	var k := MeshKit.new()
	var body := _body("ColonnadeBody")
	var a := WorldLayout.AVENUE_A
	var b := WorldLayout.AVENUE_B
	var d := (b - a).normalized()
	var perp := Vector2(-d.y, d.x)
	var length := a.distance_to(b)
	var hw := WorldLayout.AVENUE_HALF_WIDTH
	# The gateway: a great arch over the road where the avenue begins.
	var gate := a + d * 4.0
	var gy := minf(_ground(gate.x + perp.x * 14.0, gate.y + perp.y * 14.0), _ground(gate.x - perp.x * 14.0, gate.y - perp.y * 14.0))
	var gxf := _frame(gate, perp, 0.0)
	gxf.origin.y = gy - 1.2
	StoneKit.arch(k, gxf, 22.0, 13.0, 3.4, 2.8, 11, [])
	for side: float in [-1.0, 1.0]:
		_box(body, gxf * Transform3D(Basis(), Vector3(side * 12.4, 7.0, 0.0)), Vector3(2.9, 14.0, 3.6))
	# Two rows of columns, many broken, some fallen.
	var count := 12
	for side: float in [-1.0, 1.0]:
		for i in count:
			var t := (float(i) + 1.0) / (count + 0.6)
			var p := a + d * (t * length) + perp * side * hw
			var seed := i * 7 + (3 if side > 0.0 else 0)
			_rng.seed = 900 + seed
			if _rng.randf() < 0.17:
				# Fallen: its drums lie across the sand beside the gap.
				for j in 2:
					var q := p + perp * side * _rng.randf_range(2.0, 6.0) + d * _rng.randf_range(-4.0, 4.0)
					StoneKit.drum(k, _frame(q, Vector2(cos(_rng.randf() * TAU), sin(_rng.randf() * TAU)), 0.5),
						_rng.randf_range(2.2, 3.6), 1.15, seed + j)
				continue
			var h := _rng.randf_range(10.0, 15.0)
			var r := _rng.randf_range(1.05, 1.25)
			var broken := _rng.randf_range(0.25, 0.85) if _rng.randf() < 0.55 else 0.0
			var sink := _rng.randf_range(0.6, 2.4)
			var xf := _frame(p, perp, sink)
			xf.basis = xf.basis * Basis(Vector3.RIGHT, _rng.randf_range(-0.03, 0.03)) * Basis(Vector3.BACK, _rng.randf_range(-0.04, 0.04))
			StoneKit.column(k, xf, h, r, seed, broken)
			_cylinder(body, xf.origin, r * 1.2, h)
			if i % 3 == 1:
				banner_spots.append([p - perp * side * 3.2, atan2(-perp.x, -perp.y)])
	# A stepped platform where the road meets the Watchers.
	var sxf := _frame(b + d * 2.0, perp, 0.6)
	sxf.basis = Basis.looking_at(Vector3(d.x, 0.0, d.y), Vector3.UP)
	StoneKit.stairs(k, sxf, 20.0, 3, 0.45, 2.4, 77)
	_add_mesh("Colonnade", k, ruin_material)


# --- The Watchers ---------------------------------------------------------------------

func _build_watchers() -> void:
	var k := MeshKit.new()
	var glyphs := MeshKit.new()
	var body := _body("WatchersBody")
	var c := WorldLayout.WATCHERS
	for i in 7:
		var ang := TAU * i / 7.0 + 0.3
		var p := c + Vector2(cos(ang), sin(ang)) * 22.0
		var h := 9.0 + fmod(i * 2.7, 4.5)
		if i == 4:
			h = 4.0
		var w := 1.25 + fmod(i * 0.37, 0.3)
		var xf := _frame(p, Vector2(cos(ang + PI * 0.5), sin(ang + PI * 0.5)), 1.0)
		xf.basis = xf.basis * Basis(Vector3.RIGHT, sin(i * 1.9) * 0.05)
		StoneKit.monolith(k, xf, h, w, i)
		_cylinder(body, xf.origin, w, h)
		if i != 4:
			# A band of faint light, as if something still sleeps inside.
			glyphs.tube(xf * Transform3D(Basis(), Vector3(0.0, h * 0.6, 0.0)), 0.16, 6, 1,
				func(_a: float, _t: float) -> float: return w * (1.0 - 0.28 * 0.6) * 1.06,
				func(_a: float) -> float: return 0.16,
				func(_a: float) -> float: return 1.0, false)
	# The low altar at the centre.
	var axf := _frame(c, Vector2.RIGHT, 0.3)
	k.block(axf * Transform3D(Basis(), Vector3(0.0, 0.6, 0.0)), Vector3(4.0, 1.2, 2.6), 0.12, 0.08, 5)
	k.block(axf * Transform3D(Basis(Vector3.UP, 0.2), Vector3(0.0, 1.5, 0.0)), Vector3(2.6, 0.6, 1.6), 0.1, 0.06, 6)
	_box(body, axf * Transform3D(Basis(), Vector3(0.0, 0.9, 0.0)), Vector3(4.0, 1.8, 2.6))
	_add_mesh("Watchers", k, sandstone_material)
	var gm := _add_mesh("WatcherGlyphs", glyphs, glyph_material, false)
	gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# --- The Drowned Court -----------------------------------------------------------------

func _build_oasis() -> void:
	var k := MeshKit.new()
	var body := _body("OasisBody")
	var c := WorldLayout.OASIS
	var lvl := WorldLayout.water_level
	# An aqueduct striding through the water: four arches, one fallen in.
	var ad := Vector2(cos(0.35), sin(0.35))
	var adp := Vector2(-ad.y, ad.x)
	var span := 12.0
	var thick := 2.4
	for i in 4:
		var p := c + ad * ((i - 1.5) * (span + thick)) + adp * 12.0
		var floor_y := minf(_ground(p.x, p.y), lvl - 3.0)
		var xf := _frame(p, ad, 0.0)
		xf.origin.y = floor_y - 0.5
		var missing: Array = [] if i != 2 else [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
		if i == 1:
			missing = [5, 6]
		StoneKit.arch(k, xf, span, 9.5, 2.8, thick, 300 + i, missing)
		for side: float in [-1.0, 1.0]:
			_box(body, xf * Transform3D(Basis(), Vector3(side * (span * 0.5 + thick * 0.5), 5.0, 0.0)), Vector3(thick, 10.0, 2.8))
	# Its fallen blocks, half under water.
	var fall := c + ad * (0.5 * (span + thick)) + adp * 12.0
	for j in 5:
		var q := fall + Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-6.0, 6.0))
		var xf := _frame(q, Vector2(cos(j * 1.3), sin(j * 1.3)), 0.4)
		k.block(xf * Transform3D(Basis(Vector3(0.3, 1.0, 0.2).normalized(), j * 0.7), Vector3(0.0, 0.6, 0.0)),
			Vector3(2.4, 1.6, 2.8), 0.1, 0.08, 400 + j)
	# A grand stair descending into the water from the west shore.
	var sp := c + Vector2(-WorldLayout.OASIS_WATER_RADIUS * 0.82, 6.0)
	var sxf := _frame(sp, Vector2(0.0, 1.0), 0.0)
	sxf.origin.y = lvl - 2.6
	sxf.basis = Basis.looking_at(Vector3(-1.0, 0.0, 0.0), Vector3.UP)
	StoneKit.stairs(k, sxf, 18.0, 8, 0.5, 2.2, 500)
	for side: float in [-1.0, 1.0]:
		var pp := sp + Vector2(-6.0, side * 10.5)
		StoneKit.column(k, _frame(pp, Vector2.RIGHT, 1.0), 11.0, 1.1, 510 + int(side), 0.0)
		_cylinder(body, Vector3(pp.x, _ground(pp.x, pp.y) - 1.0, pp.y), 1.3, 11.0)
	# Columns standing in the shallows, most broken.
	for i in 7:
		var ang := 0.9 + i * 0.62
		var p := c + Vector2(cos(ang), sin(ang)) * _rng.randf_range(48.0, 66.0)
		var xf := _frame(p, Vector2(cos(ang), sin(ang)), 0.8)
		xf.basis = xf.basis * Basis(Vector3.RIGHT, _rng.randf_range(-0.08, 0.08))
		var h := _rng.randf_range(8.0, 13.0)
		StoneKit.column(k, xf, h, 1.05, 520 + i, _rng.randf_range(0.3, 0.8) if i % 3 != 0 else 0.0)
		_cylinder(body, xf.origin, 1.25, h)
	# A broken wall along the north shore.
	var wp := c + Vector2(10.0, -WorldLayout.OASIS_WATER_RADIUS - 8.0)
	var wxf := _frame(wp, Vector2(1.0, 0.15), 0.8)
	StoneKit.wall(k, wxf, 26.0, 6.0, 1.6, 540)
	_box(body, wxf * Transform3D(Basis(), Vector3(0.0, 2.5, 0.0)), Vector3(26.0, 5.0, 1.8))
	_add_mesh("DrownedCourt", k, ruin_material)
	var water := WaterSurface.new()
	water.name = "Water"
	add_child(water)
	water.setup(Vector3(c.x, lvl, c.y), WorldLayout.OASIS_RIM_RADIUS)
	if _terrain.sand_material is ShaderMaterial:
		(_terrain.sand_material as ShaderMaterial).set_shader_parameter("water_zone",
			Vector4(c.x, c.y, WorldLayout.OASIS_RIM_RADIUS, lvl))
	var flora := Flora.new()
	flora.name = "Flora"
	add_child(flora)
	flora.build(_terrain)


# --- Mesas ----------------------------------------------------------------------------

func _build_mesas() -> void:
	var body := _body("MesasBody")
	for i in WorldLayout.NEAR_MESAS.size():
		var m: Array = WorldLayout.NEAR_MESAS[i]
		var c: Vector2 = m[0]
		var k := MeshKit.new()
		var xf := Transform3D(Basis(Vector3.UP, i * 1.3), Vector3(c.x, _min_ground(c, float(m[1])) - 2.0, c.y))
		StoneKit.mesa_cluster(k, xf, float(m[1]), float(m[2]), 60 + i, 64, 20.0)
		var mi := _add_mesh("Mesa%d" % i, k, sandstone_material)
		_solid(body, mi.mesh.create_trimesh_shape(), Transform3D.IDENTITY)
	var far := MeshKit.new()
	for i in WorldLayout.FAR_MESAS.size():
		var m: Array = WorldLayout.FAR_MESAS[i]
		var c: Vector2 = m[0]
		var xf := Transform3D(Basis(Vector3.UP, i * 2.1), Vector3(c.x, _ground(c.x, c.y) - 15.0, c.y))
		StoneKit.mesa_cluster(far, xf, float(m[1]), float(m[2]), 80 + i, 96, 40.0)
	_add_mesh("FarMesas", far, sandstone_material, false)


func _min_ground(c: Vector2, r: float) -> float:
	var low := _ground(c.x, c.y)
	for i in 12:
		var a := TAU * i / 12.0
		low = minf(low, _ground(c.x + cos(a) * r, c.y + sin(a) * r))
	return low


# --- Rocks and fragments ------------------------------------------------------------------

func _build_rocks() -> void:
	var k := MeshKit.new()
	var ruin := MeshKit.new()
	var body := _body("RocksBody")
	# Boulders at the feet of the near mesas.
	for i in WorldLayout.NEAR_MESAS.size():
		var m: Array = WorldLayout.NEAR_MESAS[i]
		var c: Vector2 = m[0]
		var r: float = m[1]
		for j in 9:
			var ang := _rng.randf() * TAU
			var p := c + Vector2(cos(ang), sin(ang)) * r * _rng.randf_range(1.25, 1.9)
			var size := _rng.randf_range(1.5, 6.0)
			_rock(k, body, p, size, i * 20 + j)
	# Stones scattered around the oasis rim.
	for j in 12:
		var ang := _rng.randf() * TAU
		var p := WorldLayout.OASIS + Vector2(cos(ang), sin(ang)) * _rng.randf_range(95.0, 135.0)
		_rock(k, body, p, _rng.randf_range(1.2, 4.0), 300 + j)
	# Half-buried fragments near the start, framing the first view.
	var f1 := Vector2(-17.0, 9.0)
	StoneKit.drum(ruin, _frame(f1, Vector2(0.8, 0.6), 0.6), 3.4, 1.15, 701)
	_box(body, Transform3D(Basis(), Vector3(f1.x, _ground(f1.x, f1.y) + 0.6, f1.y)), Vector3(3.0, 1.4, 2.4))
	var f2 := Vector2(15.0, -14.0)
	var cap := _frame(f2, Vector2(1.0, 0.3), 0.9)
	cap.basis = cap.basis * Basis(Vector3(1.0, 0.0, 0.4).normalized(), 0.35)
	ruin.block(cap * Transform3D(Basis(), Vector3(0.0, 0.8, 0.0)), Vector3(3.2, 1.3, 3.2), 0.12, 0.08, 702)
	StoneKit.column(ruin, _frame(Vector2(21.0, -11.0), Vector2.RIGHT, 1.2), 7.0, 1.1, 703, 0.6)
	_cylinder(body, Vector3(21.0, _ground(21.0, -11.0) - 1.2, -11.0), 1.3, 5.0)
	_box(body, cap * Transform3D(Basis(), Vector3(0.0, 0.8, 0.0)), Vector3(3.2, 1.3, 3.2))
	_add_mesh("Rocks", k, sandstone_material)
	_add_mesh("Fragments", ruin, ruin_material)


func _rock(k: MeshKit, body: StaticBody3D, p: Vector2, size: float, seed: int) -> void:
	var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(p.x, _ground(p.x, p.y) - size * 0.2, p.y))
	k.rock(xf, size, seed, size * 0.3 if size > 2.0 else 0.0)
	if size > 1.4:
		var s := SphereShape3D.new()
		s.radius = size * 0.8
		_solid(body, s, Transform3D(Basis(), xf.origin + Vector3.UP * size * 0.1))


# --- Far ruins: a colossal aqueduct and giant columns on the horizon ----------------------

func _build_far_ruins() -> void:
	var k := MeshKit.new()
	var a: Vector2 = WorldLayout.FAR_AQUEDUCT[0]
	var b: Vector2 = WorldLayout.FAR_AQUEDUCT[1]
	var d := (b - a).normalized()
	var span := 46.0
	var thick := 11.0
	var n := int(a.distance_to(b) / (span + thick))
	for i in n:
		var p := a + d * (i + 0.5) * (span + thick)
		var xf := _frame(p, d, 6.0)
		# A few have fallen, others lost part of their arch.
		if i % 7 == 3 or i % 11 == 6:
			k.block(xf * Transform3D(Basis(), Vector3(-span * 0.5 - thick * 0.5, 10.0, 0.0)), Vector3(thick, 20.0, 12.0), 1.2, 0.8, i)
			continue
		var missing: Array = [] if i % 4 != 1 else [4, 5, 6, 7, 8, 9, 10, 11]
		StoneKit.arch(k, xf, span, 62.0, 12.0, thick, 600 + i, missing)
	var c := WorldLayout.FAR_COLUMNS
	for i in 7:
		var p := c + Vector2((i - 3) * 75.0, sin(i * 1.7) * 60.0)
		var h := 70.0 + fmod(i * 23.0, 50.0)
		StoneKit.column(k, _frame(p, Vector2.RIGHT, 8.0), h, 7.5, 650 + i, 0.0 if i % 3 == 0 else 0.55 + fmod(i * 0.13, 0.35))
	_add_mesh("FarRuins", k, ruin_material, false)


# --- Far landmarks --------------------------------------------------------------------------

func _build_far_landmarks() -> void:
	# The Fallen Blade: a colossal stone sword of her own blade's design, driven slantwise
	# into a dune.
	var sword := load("res://assets/spirit/sword.res") as Mesh
	if sword:
		var aabb := sword.get_aabb()
		# Its tip points along -Z.
		var length := aabb.size.z
		var s := 260.0 / length
		var mi := MeshInstance3D.new()
		mi.name = "FallenBlade"
		mi.mesh = sword
		# Its own copy of the sword's stone (the player's sword animates the shared one).
		var sm := (load("res://materials/sword.tres") as ShaderMaterial).duplicate() as ShaderMaterial
		sm.set_shader_parameter("materialize", 1.0)
		sm.set_shader_parameter("energy", 0.35)
		sm.set_shader_parameter("under_glow", 0.0)
		mi.material_override = sm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Point the blade's long axis down into the sand, leaning back and to the side.
		var axis := Vector3.FORWARD
		var down := Basis(Vector3.RIGHT, deg_to_rad(34.0)) * Basis(Vector3.BACK, deg_to_rad(-22.0)) * Vector3.DOWN
		var b := Basis(Quaternion(axis, down)).scaled(Vector3.ONE * s)
		var p := WorldLayout.FALLEN_BLADE
		# Its middle sits a fifth of the way out of the sand.
		var centre := aabb.get_center()
		var origin := Vector3(p.x, _ground(p.x, p.y) + length * s * 0.2, p.y) - b * centre
		mi.transform = Transform3D(b, origin)
		add_child(mi)
	# The Sleeping Warden: the head of a colossal hooded statue, half sunk in the dunes,
	# a faint amber star where its face should be.
	var hood := load("res://assets/spirit/hood.res") as Mesh
	if hood:
		var aabb := hood.get_aabb()
		var s := 150.0 / aabb.size.x
		var p := WorldLayout.WARDEN
		var face := Vector3(-p.x, 0.0, -p.y).normalized()
		var b := Basis.looking_at(face, Vector3.UP) * Basis(Vector3.RIGHT, 0.18) * Basis(Vector3.BACK, 0.12)
		var mi := MeshInstance3D.new()
		mi.name = "SleepingWarden"
		mi.mesh = hood
		mi.material_override = sandstone_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var g := _ground(p.x, p.y)
		mi.transform = Transform3D(b.scaled(Vector3.ONE * s), Vector3(p.x, g - aabb.size.y * s * 0.35, p.y) - b.scaled(Vector3.ONE * s) * aabb.get_center() + Vector3.UP * aabb.size.y * s * 0.5)
		add_child(mi)
		var star := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 4.5
		sm.height = 9.0
		star.mesh = sm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.55, 0.2) * 4.0
		star.material_override = m
		star.position = mi.transform * (aabb.get_center() + Vector3(0.0, aabb.size.y * 0.08, -aabb.size.z * 0.32))
		add_child(star)
