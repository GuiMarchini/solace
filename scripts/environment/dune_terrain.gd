class_name DuneTerrain
extends Node3D
## Deterministic procedural dune field.
##
## One analytic height function drives three things so they always agree:
##   * the detailed playable mesh (and its HeightMapShape3D collision),
##   * a coarse far-field mesh that carries the dunes to the horizon,
##   * fast height queries (`height_at`) for the camera, spawning and safety checks.
##
## Dunes are asymmetric transverse ridges (gentle windward slope, steeper slip face)
## bent by domain warping, crossed by a weaker second set, on top of broad undulation.
## In patches, smaller sharp-crested ridges ride on the dunes: natural kickers that
## launch the sword at speed (never walls: their slopes stay gentle).
## Some areas are deep, loose sand (`softness_at`): the sand there looks fresher and
## throws up far more grains and dust (SandFX); the same field is baked into a texture
## for the sand shader.

@export var seed := 7
@export_group("Playable area")
## Number of cells per side of the detailed mesh (power of two keeps Jolt's heightfield fast).
@export var cells := 512
@export var cell_size := 2.5
@export_group("Far field")
@export var far_cells := 224
@export var far_cell_size := 40.0
@export_group("Dune shape")
@export var wind_angle_deg := 24.0
@export var dune_wavelength := 200.0
@export var dune_height := 26.0
## Fraction of each dune period used by the windward slope (rest is the slip face).
@export_range(0.5, 0.9) var windward_fraction := 0.72
@export var cross_dune_strength := 0.32
@export var warp_strength := 75.0
@export var base_height := 28.0
@export var spawn_calm_radius := 45.0
## Small launch ridges: height (m), spacing (m) and how much of the desert has them.
@export var ridge_height := 2.4
@export var ridge_wavelength := 42.0
@export_range(0.0, 1.0) var ridge_coverage := 0.45
@export_group("Loose sand")
## Size (m) of the patches of deep, loose sand and how much of the desert they cover.
@export var soft_patch_size := 240.0
@export_range(0.0, 1.0) var soft_coverage := 0.35
@export_group("Rendering")
@export var sand_material: Material
@export var cast_shadows := true

var half_extent: float:
	get:
		return cells * cell_size * 0.5

var _warp := FastNoiseLite.new()
var _amp := FastNoiseLite.new()
var _base := FastNoiseLite.new()
var _wind := Vector2.ZERO
var _wind2 := Vector2.ZERO
var _heights := PackedFloat32Array()
var _ridge_mask := FastNoiseLite.new()
var _soft := FastNoiseLite.new()

## The terrain in play (effects and tools query it).
static var instance: DuneTerrain


func _ready() -> void:
	instance = self
	_setup_noise()
	var t0 := Time.get_ticks_msec()
	_build_playable()
	_build_far_field()
	_build_boundary()
	print("[DuneTerrain] generated in %d ms" % (Time.get_ticks_msec() - t0))


func _setup_noise() -> void:
	_warp.seed = seed
	_warp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_warp.frequency = 1.0 / 900.0
	_warp.fractal_type = FastNoiseLite.FRACTAL_NONE
	_amp.seed = seed + 101
	_amp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_amp.frequency = 1.0 / 420.0
	_amp.fractal_type = FastNoiseLite.FRACTAL_NONE
	_base.seed = seed + 202
	_base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_base.frequency = 1.0 / 1500.0
	_base.fractal_type = FastNoiseLite.FRACTAL_FBM
	_base.fractal_octaves = 3
	_ridge_mask.seed = seed + 303
	_ridge_mask.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridge_mask.frequency = 1.0 / 300.0
	_soft.seed = seed + 404
	_soft.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_soft.frequency = 1.0 / soft_patch_size
	_soft.fractal_type = FastNoiseLite.FRACTAL_FBM
	_soft.fractal_octaves = 2
	var a := deg_to_rad(wind_angle_deg)
	_wind = Vector2(sin(a), cos(a))
	var a2 := a + deg_to_rad(68.0)
	_wind2 = Vector2(sin(a2), cos(a2))


## Terrain height in world units at world XZ. Safe to call anywhere, any time after _ready.
func height_at(x: float, z: float) -> float:
	var wx := _warp.get_noise_2d(x, z) * warp_strength
	var wz := _warp.get_noise_2d(x + 913.0, z - 377.0) * warp_strength
	var qx := x + wx
	var qz := z + wz
	var amp_n := _amp.get_noise_2d(x, z)
	var phase := (qx * _wind.x + qz * _wind.y) / dune_wavelength + amp_n * 0.25
	var phase2 := (qx * _wind2.x + qz * _wind2.y) / (dune_wavelength * 0.61)
	var dunes := _profile(phase - floorf(phase)) + cross_dune_strength * _profile(phase2 - floorf(phase2))
	var amp := lerpf(0.35, 1.0, clampf(amp_n * 0.9 + 0.55, 0.0, 1.0))
	var calm := smoothstep(spawn_calm_radius * 0.3, spawn_calm_radius, sqrt(x * x + z * z))
	# Launch ridges in patches, along the wind like small dunes on the big ones.
	var mask := smoothstep(1.0 - ridge_coverage * 2.0, 1.0 - ridge_coverage * 2.0 + 0.35, _ridge_mask.get_noise_2d(x, z) + 0.5)
	var rph := (qx * _wind.x + qz * _wind.y) / ridge_wavelength + amp_n * 0.6
	var ridges := _profile(rph - floorf(rph)) * ridge_height * mask
	return (dunes * dune_height * amp + ridges) * lerpf(0.3, 1.0, calm) + _base.get_noise_2d(x, z) * base_height


## 0..1: how deep and loose the sand is at world XZ (patches of fresh, soft sand).
func softness_at(x: float, z: float) -> float:
	var n := _soft.get_noise_2d(x, z) * 0.5 + 0.5
	var t := 1.0 - soft_coverage
	return smoothstep(t - 0.06, t + 0.08, n)


## Normal from the analytic height function (central differences).
func normal_at(x: float, z: float, e: float = 1.0) -> Vector3:
	var hx := height_at(x + e, z) - height_at(x - e, z)
	var hz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


## True when (x, z) lies on the detailed, walkable terrain.
func is_inside(x: float, z: float, margin: float = 0.0) -> bool:
	var h := half_extent - margin
	return absf(x) < h and absf(z) < h


## Sharp-crested dune: a concave windward ramp that is still rising at the top, then a
## steep slip face easing into a smooth trough. The knife-edge crest gives the clean
## light/shadow line of real dunes and a natural launch lip for the board.
@export_range(0.0, 1.0) var crest_sharpness := 0.75

func _profile(t: float) -> float:
	if t < windward_fraction:
		var s := t / windward_fraction
		var sharp := 1.0 - cos(s * PI * 0.5)
		return lerpf(smoothstep(0.0, 1.0, s), sharp, crest_sharpness)
	var s2 := (t - windward_fraction) / (1.0 - windward_fraction)
	var lee := 1.0 - sin(s2 * PI * 0.5)
	return lerpf(1.0 - smoothstep(0.0, 1.0, s2), lee, crest_sharpness)


func _build_playable() -> void:
	var n := cells + 1
	var half := half_extent
	_heights.resize(n * n)
	for iz in n:
		var z := -half + iz * cell_size
		var row := iz * n
		for ix in n:
			_heights[row + ix] = height_at(-half + ix * cell_size, z)

	var mesh := _grid_mesh(_heights, n, cell_size, -half)
	var mi := MeshInstance3D.new()
	mi.name = "DunesMesh"
	mi.mesh = mesh
	mi.material_override = sand_material
	# Also drawn into the particles' height field (sand grains settle on it).
	mi.layers = 1 | SandFX.TERRAIN_LAYER
	_bake_softness()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	# Collision: same samples, scaled uniformly so one heightmap texel = one render vertex.
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	var scaled := PackedFloat32Array()
	scaled.resize(n * n)
	var inv := 1.0 / cell_size
	for i in n * n:
		scaled[i] = _heights[i] * inv
	shape.map_data = scaled
	var body := StaticBody3D.new()
	body.name = "DunesBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3.ONE * cell_size
	body.add_child(cs)
	add_child(body)


## Bakes the loose-sand field over the playable area into a texture for the shader.
func _bake_softness() -> void:
	var res := 256
	var img := Image.create(res, res, false, Image.FORMAT_R8)
	var size := half_extent * 2.0
	for j in res:
		for i in res:
			var x := -half_extent + (i + 0.5) / res * size
			var z := -half_extent + (j + 0.5) / res * size
			img.set_pixel(i, j, Color(softness_at(x, z), 0.0, 0.0))
	var tex := ImageTexture.create_from_image(img)
	if sand_material is ShaderMaterial:
		var m := sand_material as ShaderMaterial
		m.set_shader_parameter("soft_map", tex)
		m.set_shader_parameter("soft_map_origin", Vector2(-half_extent, -half_extent))
		m.set_shader_parameter("soft_map_size", size)


func _build_far_field() -> void:
	var n := far_cells + 1
	var half := far_cells * far_cell_size * 0.5
	var inner := half_extent
	var h := PackedFloat32Array()
	h.resize(n * n)
	for iz in n:
		var z := -half + iz * far_cell_size
		for ix in n:
			var x := -half + ix * far_cell_size
			var y := height_at(x, z)
			# Vertices strictly inside the playable square sink below the detailed mesh.
			if absf(x) < inner - 0.01 and absf(z) < inner - 0.01:
				y -= 40.0
			h[iz * n + ix] = y
	var mesh := _grid_mesh(h, n, far_cell_size, -half)
	var mi := MeshInstance3D.new()
	mi.name = "FarDunes"
	mi.mesh = mesh
	mi.material_override = sand_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_boundary() -> void:
	# Hard backstop just inside the edge of the collision heightmap. The player
	# controller pushes softly before this, so these walls are rarely touched.
	var body := StaticBody3D.new()
	body.name = "Boundary"
	body.collision_layer = 1
	body.collision_mask = 0
	var limit := half_extent - 18.0
	for i in 4:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(limit * 2.0 + 20.0, 800.0, 10.0)
		cs.shape = box
		var dir := Vector3.FORWARD.rotated(Vector3.UP, i * PI * 0.5)
		cs.position = dir * (limit + 5.0)
		cs.rotation.y = i * PI * 0.5
		body.add_child(cs)
	add_child(body)


## Builds a grid mesh from a square heightfield. COLOR.r stores convexity
## (0.5 = flat, >0.5 crest, <0.5 trough), used by the sand shader.
func _grid_mesh(h: PackedFloat32Array, n: int, step: float, origin: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	var curv_scale := 1.6 / maxf(step, 1.0)
	for iz in n:
		var z := origin + iz * step
		var zu := maxi(iz - 1, 0) * n
		var zd := mini(iz + 1, n - 1) * n
		var row := iz * n
		for ix in n:
			var i := row + ix
			var y := h[i]
			var xl := h[row + maxi(ix - 1, 0)]
			var xr := h[row + mini(ix + 1, n - 1)]
			var yu := h[zu + ix]
			var yd := h[zd + ix]
			verts[i] = Vector3(origin + ix * step, y, z)
			normals[i] = Vector3(xl - xr, 2.0 * step, yu - yd).normalized()
			var lap := (xl + xr + yu + yd - 4.0 * y) / step
			var c := clampf(0.5 - lap * curv_scale, 0.0, 1.0)
			colors[i] = Color(c, 0.0, 0.0, 1.0)
	var indices := PackedInt32Array()
	indices.resize((n - 1) * (n - 1) * 6)
	var k := 0
	for iz in n - 1:
		for ix in n - 1:
			var v00 := iz * n + ix
			var v10 := v00 + 1
			var v01 := v00 + n
			var v11 := v01 + 1
			# Clockwise seen from above (Godot front face).
			indices[k] = v00
			indices[k + 1] = v10
			indices[k + 2] = v01
			indices[k + 3] = v10
			indices[k + 4] = v11
			indices[k + 5] = v01
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
