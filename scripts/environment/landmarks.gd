class_name Landmarks
extends Node3D
## Ancient silhouettes: a distant cluster of colossal spires (the focal point,
## marked by a faint beam of light), broken arches and obelisks on the horizon,
## plus a handful of weathered stones inside the playable area for scale.
## Distant pieces are pure scenery; near stones get simple collision.

@export var terrain_path: NodePath = ^"../DuneTerrain"
@export var stone_color := Color(0.62, 0.5, 0.42)
@export var far_stone_color := Color(0.36, 0.34, 0.4)
@export var glyph_color := Color(0.55, 0.85, 1.0)
@export var beacon_position := Vector3(-300.0, 0.0, -2400.0)
@export var spire_scale := 1.3

var _terrain: DuneTerrain
var _rng := RandomNumberGenerator.new()
var _near_mat: StandardMaterial3D
var _far_mat: StandardMaterial3D
var _glyph_mat: StandardMaterial3D


func _ready() -> void:
	_rng.seed = 1977
	_terrain = get_node_or_null(terrain_path) as DuneTerrain
	_near_mat = _stone_material(stone_color)
	_far_mat = _stone_material(far_stone_color)
	_glyph_mat = StandardMaterial3D.new()
	_glyph_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glyph_mat.albedo_color = glyph_color * 2.2
	_build_spire_city()
	_build_horizon_ruins()
	_build_near_stones()


func _ground(x: float, z: float) -> float:
	return _terrain.height_at(x, z) if _terrain else 0.0


func _stone_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.92
	m.metallic_specular = 0.2
	return m


# --- Distant spire city (focal point) -------------------------------------------

func _build_spire_city() -> void:
	var root := Node3D.new()
	root.name = "SpireCity"
	add_child(root)
	var c := beacon_position
	var base_y := _ground(c.x, c.z) - 30.0
	# (offset x, offset z, height, radius)
	var spires := [
		[0.0, 0.0, 560.0, 46.0],
		[-120.0, 40.0, 400.0, 34.0],
		[115.0, 30.0, 430.0, 36.0],
		[-230.0, 120.0, 290.0, 28.0],
		[220.0, 140.0, 260.0, 26.0],
		[-60.0, -110.0, 340.0, 30.0],
		[70.0, -150.0, 300.0, 26.0],
		[-330.0, 60.0, 200.0, 22.0],
		[330.0, 20.0, 190.0, 22.0],
		[0.0, 190.0, 230.0, 30.0],
	]
	for i in spires.size():
		var s: Array = spires[i]
		var mi := MeshInstance3D.new()
		var k := spire_scale
		mi.mesh = ProcMesh.lathe(_spire_profile(float(s[2]) * k, float(s[3]) * k), 8, 1.0, 0.04, i)
		mi.material_override = _far_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(c.x + float(s[0]) * k, base_y, c.z + float(s[1]) * k)
		mi.rotation = Vector3(_rng.randf_range(-0.02, 0.02), _rng.randf() * TAU, _rng.randf_range(-0.03, 0.03))
		root.add_child(mi)
	# A broad base mass so the spires grow out of something.
	var base := MeshInstance3D.new()
	base.mesh = ProcMesh.lathe(PackedVector2Array([
		Vector2(0, -40), Vector2(420, -40), Vector2(400, 40), Vector2(330, 60),
		Vector2(300, 110), Vector2(180, 130), Vector2(0, 135)]), 10, 0.7, 0.06, 99)
	base.material_override = _far_mat
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	base.position = Vector3(c.x, base_y, c.z + 40.0)
	root.add_child(base)
	# Faint beam of light rising from the city: the thing you want to walk toward.
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.6
	cyl.bottom_radius = 3.4
	cyl.height = 650.0
	cyl.radial_segments = 16
	cyl.cap_top = false
	cyl.cap_bottom = false
	beam.mesh = cyl
	var bm := ShaderMaterial.new()
	bm.shader = load("res://shaders/soft_glow.gdshader")
	bm.set_shader_parameter("mode", 1)
	bm.set_shader_parameter("color", Color(0.6, 0.85, 1.0))
	bm.set_shader_parameter("intensity", 1.0)
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position = Vector3(c.x, base_y + 325.0, c.z)
	root.add_child(beam)
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 9.0
	sphere.height = 18.0
	core.mesh = sphere
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.albedo_color = Color(0.7, 0.9, 1.0) * 6.0
	core.material_override = cm
	core.position = Vector3(c.x, base_y + 150.0, c.z - 50.0)
	root.add_child(core)


func _spire_profile(h: float, r: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, -60.0), Vector2(r * 1.15, -60.0), Vector2(r * 1.05, 0.0),
		Vector2(r * 0.95, h * 0.22), Vector2(r * 1.12, h * 0.23), Vector2(r * 1.12, h * 0.25),
		Vector2(r * 0.8, h * 0.26), Vector2(r * 0.72, h * 0.46), Vector2(r * 0.9, h * 0.47),
		Vector2(r * 0.9, h * 0.49), Vector2(r * 0.58, h * 0.5), Vector2(r * 0.5, h * 0.66),
		Vector2(r * 0.64, h * 0.67), Vector2(r * 0.34, h * 0.69), Vector2(r * 0.22, h * 0.8),
		Vector2(r * 0.08, h * 0.95), Vector2(0.0, h)])


# --- Horizon ruins ----------------------------------------------------------------

func _build_horizon_ruins() -> void:
	_arch(Vector3(950.0, 0.0, -2350.0), 150.0, 0.25, 0.8, [3, 4])
	_arch(Vector3(1400.0, 0.0, -2600.0), 110.0, -0.4, 0.75, [])
	_arch(Vector3(-2300.0, 0.0, -1500.0), 180.0, 1.1, 0.8, [5, 6, 7])
	for i in 4:
		var p := Vector3(-2600.0 + i * 140.0, 0.0, 900.0 + (i % 2) * 120.0)
		_column(p, 160.0 + i * 35.0, 16.0, Vector3(_rng.randf_range(-0.08, 0.08), 0.0, _rng.randf_range(-0.1, 0.1)), _far_mat, false)
	for i in 6:
		var p := Vector3(300.0 + i * 70.0, 0.0, 2700.0 + sin(i * 1.7) * 40.0)
		_column(p, 70.0 + fmod(i * 37.0, 60.0), 9.0, Vector3(0.0, 0.0, _rng.randf_range(-0.05, 0.05)), _far_mat, false)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 210.0
	torus.outer_radius = 245.0
	torus.rings = 48
	torus.ring_segments = 8
	ring.mesh = torus
	ring.material_override = _far_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(2700.0, _ground(2700.0, 700.0) + 40.0, 700.0)
	ring.rotation = Vector3(deg_to_rad(80.0), deg_to_rad(30.0), deg_to_rad(8.0))
	add_child(ring)


## Arch built from blocks along a semicircle; `missing` lists block indices that have fallen.
func _arch(center: Vector3, radius: float, yaw: float, pillar_ratio: float, missing: Array) -> void:
	var root := Node3D.new()
	root.position = Vector3(center.x, _ground(center.x, center.z) - 10.0, center.z)
	root.rotation.y = yaw
	add_child(root)
	var pillar_h := radius * pillar_ratio
	var thick := radius * 0.16
	for side in [-1.0, 1.0]:
		_column(Vector3(side * radius, 0.0, 0.0), pillar_h, thick * 0.6, Vector3.ZERO, _far_mat, false, root)
	var blocks := 10
	for i in blocks:
		if missing.has(i):
			continue
		var a := PI * (float(i) + 0.5) / float(blocks)
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(thick, radius * PI / blocks * 1.04, thick * 0.9)
		mi.mesh = box
		mi.material_override = _far_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(cos(a) * radius, pillar_h + sin(a) * radius, 0.0)
		mi.rotation.z = a
		root.add_child(mi)


func _column(pos: Vector3, height: float, radius: float, tilt: Vector3, mat: Material,
		collide: bool, parent: Node3D = self) -> MeshInstance3D:
	var y := pos.y
	if parent == self:
		y = _ground(pos.x, pos.z) - height * 0.08
	var prof := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(radius * 1.25, 0.0), Vector2(radius * 1.25, height * 0.05),
		Vector2(radius, height * 0.07), Vector2(radius * 0.92, height * 0.85),
		Vector2(radius * 0.98, height * 0.9), Vector2(radius * 0.7, height * 0.97), Vector2(0.0, height)])
	var mi := MeshInstance3D.new()
	mi.mesh = ProcMesh.lathe(prof, 7, 1.0, 0.07, int(pos.x * 13.0 + pos.z))
	mi.material_override = mat
	mi.position = Vector3(pos.x, y, pos.z)
	mi.rotation = tilt
	if not collide:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = 4  # "props": the camera avoids these; terrain is handled analytically
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = radius * 1.05
		cyl.height = height
		cs.shape = cyl
		cs.position = Vector3(0.0, height * 0.5, 0.0)
		body.add_child(cs)
		mi.add_child(body)
	return mi


# --- Near stones (inside the playable area) ----------------------------------------

func _build_near_stones() -> void:
	# A leaning waystone near spawn, framing the view toward the spire city.
	_waystone(Vector3(16.0, 0.0, -62.0), 9.5, 0.75, Vector3(0.06, 0.0, -0.1))
	_waystone(Vector3(-24.0, 0.0, -150.0), 6.0, 0.6, Vector3(-0.15, 0.0, 0.2))
	# The Watchers: a ring of tall stones on the way to the spires.
	var c := Vector3(60.0, 0.0, -430.0)
	for i in 7:
		var a := TAU * i / 7.0 + 0.3
		var p := c + Vector3(cos(a), 0.0, sin(a)) * 22.0
		var h := 8.0 + fmod(i * 2.7, 4.0)
		if i == 4:
			h = 3.5  # one has broken off
		_waystone(p, h, 0.9, Vector3(_rng.randf_range(-0.06, 0.06), 0.0, _rng.randf_range(-0.06, 0.06)))
	# Scattered fragments.
	_waystone(Vector3(240.0, 0.0, 130.0), 4.0, 1.3, Vector3(0.5, 0.0, 0.2))
	_waystone(Vector3(-160.0, 0.0, 360.0), 12.0, 1.0, Vector3(0.0, 0.0, 0.18))
	_waystone(Vector3(-300.0, 0.0, -260.0), 7.0, 1.1, Vector3(0.2, 0.0, -0.3))
	_waystone(Vector3(420.0, 0.0, -380.0), 10.0, 0.9, Vector3(-0.1, 0.0, 0.05))
	_waystone(Vector3(330.0, 0.0, 420.0), 5.0, 1.4, Vector3(1.2, 0.3, 0.0))


func _waystone(pos: Vector3, height: float, radius: float, tilt: Vector3) -> void:
	var mi := _column(pos, height, radius, tilt, _near_mat, true)
	# A thin band of faint light, as if something still sleeps inside.
	var band := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius * 0.95
	cyl.bottom_radius = radius * 0.95
	cyl.height = 0.12
	cyl.radial_segments = 7
	band.mesh = cyl
	band.material_override = _glyph_mat
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	band.position = Vector3(0.0, height * 0.62, 0.0)
	mi.add_child(band)
