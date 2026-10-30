class_name AmbienceFX
extends Node3D
## What keeps the world alive when she stands still:
##   * sand blowing off the dune crests around the camera (crests found by scanning the
##     terrain along the wind, one row of samples per frame, fed to the particles as
##     emission points),
##   * motes of dust drifting and catching the sun near the camera,
##   * banners rippling on bronze poles along the Pilgrim's Colonnade,
##   * sand pouring off the ledges of the near mesas,
##   * flocks of birds wheeling over the Watchers, the oasis and the gateway.

const GRID := 22
const SPACING := 7.0
const MAX_POINTS := 160

var _terrain: DuneTerrain
var _wind := Vector2(0.42, 0.91).normalized()
var _streamers: GPUParticles3D
var _motes: GPUParticles3D
var _img := Image.create(MAX_POINTS, 1, false, Image.FORMAT_RGBF)
var _tex: ImageTexture
var _row := 0
var _origin := Vector3.ZERO
var _found: Array[Vector3] = []
var _birds := MultiMesh.new()
var _flocks: Array = []
var _time := 0.0


func build(builder: WorldBuilder, terrain: DuneTerrain) -> void:
	_terrain = terrain
	_build_banners(builder.banner_spots)
	_build_streamers()
	_build_motes()
	_build_birds()
	# Sandfalls need the mesas' collision to find their cliff faces.
	_build_sandfalls.call_deferred(builder)


func _process(delta: float) -> void:
	_time += delta
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	_motes.global_position = cp + Vector3(_wind.x, 0.0, _wind.y) * 6.0
	_scan_crests(cp)
	_update_birds()


# --- Sand blowing off the crests ----------------------------------------------------------

func _build_streamers() -> void:
	_streamers = Fx.particles({"amount": 220, "lifetime": 2.4, "size": 1.1, "kind": "sand",
		"direction": Vector3(_wind.x, 0.12, _wind.y), "spread": 10.0, "velocity": Vector2(3.0, 7.5),
		"gravity": Vector3(0.0, -0.4, 0.0), "damping": 0.6, "scale": Vector2(0.5, 1.6), "grow": true,
		"color": Color(1.0, 0.82, 0.62, 0.22), "turbulence": true})
	var pm := _streamers.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	_tex = ImageTexture.create_from_image(_img)
	pm.emission_point_texture = _tex
	pm.emission_point_count = 0
	_streamers.emitting = false
	_streamers.visibility_aabb = AABB(Vector3(-200, -60, -200), Vector3(400, 160, 400))
	add_child(_streamers)


## One row of the grid around the camera per frame: a crest is higher than the sand a few
## metres upwind and downwind of it. When the grid is done, the crests become the
## emission points.
func _scan_crests(cp: Vector3) -> void:
	if _row == 0:
		_origin = Vector3(snappedf(cp.x, SPACING), 0.0, snappedf(cp.z, SPACING))
		_found.clear()
	var w := Vector2(_wind.x, _wind.y) * 4.0
	var z := _origin.z + (_row - GRID * 0.5) * SPACING
	for i in GRID:
		var x := _origin.x + (i - GRID * 0.5) * SPACING
		var h := _terrain.height_at(x, z)
		var up := _terrain.height_at(x - w.x, z - w.y)
		var down := _terrain.height_at(x + w.x, z + w.y)
		if h - 0.5 * (up + down) > 0.3 and h > down and not WorldLayout.on_water(x, z):
			_found.append(Vector3(x, h + 0.2, z))
	_row += 1
	if _row < GRID:
		return
	_row = 0
	var n := mini(_found.size(), MAX_POINTS)
	for i in n:
		var p := _found[i]
		_img.set_pixel(i, 0, Color(p.x, p.y, p.z))
	_tex.update(_img)
	var pm := _streamers.process_material as ParticleProcessMaterial
	pm.emission_point_count = n
	_streamers.emitting = n > 0


# --- Dust motes ---------------------------------------------------------------------------

func _build_motes() -> void:
	_motes = Fx.particles({"amount": 160, "lifetime": 6.0, "size": 0.03, "shape": "box",
		"extents": Vector3(16.0, 5.0, 16.0), "direction": Vector3(_wind.x, 0.05, _wind.y), "spread": 40.0,
		"velocity": Vector2(0.3, 1.2), "gravity": Vector3.ZERO, "damping": 0.0,
		"scale": Vector2(0.5, 1.4), "color": Color(1.0, 0.86, 0.6, 0.55), "turbulence": true})
	_motes.local_coords = false
	_motes.emitting = true
	add_child(_motes)


# --- Banners --------------------------------------------------------------------------------

func _build_banners(spots: Array) -> void:
	var poles := MeshKit.new()
	var cloth_shader := load("res://shaders/banner.gdshader") as Shader
	var cloth := ShaderMaterial.new()
	cloth.shader = cloth_shader
	var bronze := StandardMaterial3D.new()
	bronze.albedo_color = Color(0.5, 0.36, 0.2)
	bronze.metallic = 0.65
	bronze.roughness = 0.45
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.5, 5.2)
	plane.orientation = PlaneMesh.FACE_Z
	plane.subdivide_width = 4
	plane.subdivide_depth = 16
	var i := 0
	for s in spots:
		var p: Vector2 = s[0]
		var yaw: float = s[1]
		var g := _terrain.height_at(p.x, p.y)
		var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, g - 0.4, p.y))
		var h := 8.0
		poles.tube(xf, h, 8, 3, func(_a: float, t: float) -> float: return lerpf(0.11, 0.08, t),
			func(_a: float) -> float: return h, func(_a: float) -> float: return 1.0, true)
		poles.block(xf * Transform3D(Basis(), Vector3(0.0, h - 0.5, 0.0)), Vector3(1.8, 0.1, 0.1), 0.03, 0.0, i)
		# A ring finial, like the pilgrims' standards.
		poles.tube(xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, h + 0.35, 0.0)), 0.08, 16, 1,
			func(_a: float, _t: float) -> float: return 0.32, func(_a: float) -> float: return 0.08,
			func(_a: float) -> float: return 1.0, false)
		var mi := MeshInstance3D.new()
		mi.mesh = plane
		mi.material_override = cloth
		mi.transform = xf * Transform3D(Basis(), Vector3(0.0, h - 0.55 - 2.6, 0.06))
		mi.set_instance_shader_parameter("seed", float(i) * 1.37)
		add_child(mi)
		i += 1
	var pm := MeshInstance3D.new()
	pm.name = "BannerPoles"
	pm.mesh = poles.commit()
	pm.material_override = bronze
	add_child(pm)


# --- Sand pouring off the mesas -----------------------------------------------------------

func _build_sandfalls(builder: WorldBuilder) -> void:
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = WorldBuilder.PROPS_LAYER
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	var tex := NoiseTexture2D.new()
	tex.seamless = true
	tex.width = 256
	tex.height = 256
	tex.noise = noise
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/sandfall.gdshader")
	mat.set_shader_parameter("noise_tex", tex)
	for i in WorldLayout.NEAR_MESAS.size():
		var m: Array = WorldLayout.NEAR_MESAS[i]
		var c: Vector2 = m[0]
		var r: float = m[1]
		var hgt: float = m[2]
		# One or two falls on the side facing the middle of the desert.
		var toward := (-c).normalized()
		for j in (2 if r > 30.0 else 1):
			var a := atan2(toward.y, toward.x) + j * 0.45
			var dir := Vector2(cos(a), sin(a))
			var base_y := _terrain.height_at(c.x, c.y)
			var lip_y := base_y + hgt * 0.72
			q.from = Vector3(c.x + dir.x * r * 3.0, lip_y, c.y + dir.y * r * 3.0)
			q.to = Vector3(c.x, lip_y, c.y)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			var at: Vector3 = hit["position"] + Vector3(dir.x, 0.0, dir.y) * 2.6
			var ground := _terrain.height_at(at.x, at.z)
			var fall := at.y - ground
			var ribbon := PlaneMesh.new()
			ribbon.orientation = PlaneMesh.FACE_Z
			ribbon.size = Vector2(6.0 + r * 0.12, fall)
			ribbon.subdivide_depth = 8
			var mi := MeshInstance3D.new()
			mi.name = "Sandfall%d_%d" % [i, j]
			mi.mesh = ribbon
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.transform = Transform3D(Basis.looking_at(Vector3(-dir.x, 0.0, -dir.y), Vector3.UP), Vector3(at.x, ground + fall * 0.5, at.z))
			add_child(mi)
			var dust := Fx.particles({"amount": 40, "lifetime": 2.5, "size": 2.4, "kind": "sand", "shape": "sphere",
				"radius": 1.5, "direction": Vector3(dir.x, 0.6, dir.y), "spread": 60.0, "velocity": Vector2(0.4, 1.6),
				"damping": 0.8, "scale": Vector2(0.6, 1.5), "grow": true, "color": Color(1.0, 0.8, 0.6, 0.35), "turbulence": true})
			add_child(dust)
			dust.global_position = Vector3(at.x, ground + 0.8, at.z)
			dust.emitting = true


# --- Birds -------------------------------------------------------------------------------------

func _build_birds() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [-1.0, 1.0]:
		st.add_vertex(Vector3(0.0, 0.0, -0.35))
		st.add_vertex(Vector3(side * 1.6, 0.12, 0.15))
		st.add_vertex(Vector3(0.0, 0.0, 0.3))
	_birds.transform_format = MultiMesh.TRANSFORM_3D
	_birds.use_custom_data = true
	_birds.mesh = st.commit()
	var c := WorldLayout.WATCHERS
	var o := WorldLayout.OASIS
	var g := WorldLayout.AVENUE_A
	# [centre, radius, height, angular speed, count]
	_flocks = [[Vector3(c.x, 48.0, c.y), 38.0, 48.0, 0.18, 7], [Vector3(o.x, 34.0, o.y), 55.0, 34.0, -0.14, 8],
		[Vector3(g.x, 62.0, g.y), 30.0, 62.0, 0.22, 5]]
	var n := 0
	for f in _flocks:
		n += int(f[4])
	_birds.instance_count = n
	var k := 0
	for f in _flocks:
		for b in int(f[4]):
			_birds.set_instance_custom_data(k, Color(randf(), 0.0, 0.0, 0.0))
			k += 1
	var mi := MultiMeshInstance3D.new()
	mi.name = "Birds"
	mi.multimesh = _birds
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/bird.gdshader")
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-1000, -100, -1000), Vector3(2000, 400, 2000))
	add_child(mi)


func _update_birds() -> void:
	var k := 0
	for f in _flocks:
		var centre: Vector3 = f[0]
		var r: float = f[1]
		var h: float = f[2]
		var w: float = f[3]
		var ground := _terrain.height_at(centre.x, centre.z)
		for b in int(f[4]):
			var a := _time * w + b * 0.55 + sin(_time * 0.3 + b) * 0.1
			var rr := r * (0.8 + 0.35 * sin(b * 2.3 + _time * 0.2))
			var p := Vector3(centre.x + cos(a) * rr, ground + h + sin(_time * 0.7 + b * 1.7) * 3.0 + b * 1.5, centre.z + sin(a) * rr)
			var tangent := Vector3(-sin(a), 0.0, cos(a)) * signf(w)
			var basis := Basis.looking_at(tangent, Vector3.UP) * Basis(Vector3.BACK, sin(_time + b) * 0.2 - signf(w) * 0.25)
			_birds.set_instance_transform(k, Transform3D(basis.scaled(Vector3.ONE * 1.8), p))
			k += 1
