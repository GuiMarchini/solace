class_name Fx
extends RefCounted
## Shared factory for the demo's particle systems. Materials and textures are
## cached so every emitter of the same kind shares one resource.

static var _cache := {}


## Drops cached resources (called on exit so nothing is reported as leaked).
static func clear_cache() -> void:
	_cache.clear()


static func soft_dot() -> Texture2D:
	if _cache.has("dot"):
		return _cache["dot"]
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.3, Color(1, 1, 1, 0.6))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_cache["dot"] = t
	return t


## Very soft falloff for dust so puffs never read as discs.
static func soft_puff() -> Texture2D:
	if _cache.has("puff"):
		return _cache["puff"]
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.55))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.3))
	g.add_point(0.7, Color(1, 1, 1, 0.07))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_cache["puff"] = t
	return t


## Additive glowing mote (magic energy).
static func energy_material() -> StandardMaterial3D:
	if _cache.has("energy"):
		return _cache["energy"]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_dot()
	m.albedo_color = Color(1.5, 1.5, 1.5)
	m.disable_receive_shadows = true
	m.disable_fog = true   # fog added over an additive quad shows its square outline
	_cache["energy"] = m
	return m


## Dark churning smoke wisps (no proximity fade: they are born inside the smoke body).
## `soft`: a looser, more transparent variant for smoke left trailing behind, so a
## stream of puffs reads as one veil instead of separate clumps.
static func smoke_material(soft := false) -> ShaderMaterial:
	var key := "smoke_soft" if soft else "smoke"
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/smoke_particle.gdshader")
	if soft:
		m.set_shader_parameter("softness", 0.85)
		m.set_shader_parameter("lumpiness", 0.55)
		m.set_shader_parameter("sheets", 0.35)
	_cache[key] = m
	return m


## Billowing puffs of sand thrown up by the board: lumpy, sunlit, bright cream.
static func sand_material() -> ShaderMaterial:
	if _cache.has("sand"):
		return _cache["sand"]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/smoke_particle.gdshader")
	m.set_shader_parameter("absorb", 0.2)
	m.set_shader_parameter("ground_lit", 0.8)
	m.set_shader_parameter("softness", 0.55)
	m.set_shader_parameter("lumpiness", 1.0)
	m.set_shader_parameter("sheets", 0.0)
	m.set_shader_parameter("curl", 0.7)
	m.set_shader_parameter("churn", 0.35)
	_cache["sand"] = m
	return m


## Soft sand dust (alpha blended, fades near geometry to avoid hard intersections).
static func dust_material() -> StandardMaterial3D:
	if _cache.has("dust"):
		return _cache["dust"]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_puff()
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.6
	m.disable_receive_shadows = true
	_cache["dust"] = m
	return m


static func fade_ramp(color: Color, peak: float = 0.15) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(color, 0.0))
	g.set_color(1, Color(color, 0.0))
	g.add_point(peak, color)
	g.add_point(0.6, Color(color, color.a * 0.6))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func scale_curve(start: float, peak_t: float, end: float) -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, start))
	c.add_point(Vector2(peak_t, 1.0))
	c.add_point(Vector2(1.0, end))
	var t := CurveTexture.new()
	t.curve = c
	return t


## Creates a world-space GPUParticles3D from a small config dictionary.
## Keys: amount, lifetime, size, one_shot, explosiveness, kind ("energy"/"dust"/"smoke"/"sand"),
## color, shape ("sphere"/"box"/"ring"/"point"), radius, extents, direction,
## spread, velocity (Vector2 min/max), gravity, damping, scale (Vector2 min/max),
## grow (bool), flatness, radial (Vector2), turbulence, soft (smoke: looser variant).
static func particles(cfg: Dictionary) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = cfg.get("amount", 16)
	p.lifetime = cfg.get("lifetime", 1.0)
	p.one_shot = cfg.get("one_shot", false)
	p.explosiveness = cfg.get("explosiveness", 0.0)
	p.randomness = 0.4
	p.local_coords = false
	p.fixed_fps = 0
	p.interpolate = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-20, -10, -20), Vector3(40, 20, 40))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var pm := ParticleProcessMaterial.new()
	match String(cfg.get("shape", "sphere")):
		"box":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			pm.emission_box_extents = cfg.get("extents", Vector3.ONE * 0.2)
		"ring":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			pm.emission_ring_axis = Vector3.UP
			pm.emission_ring_radius = cfg.get("radius", 0.5)
			pm.emission_ring_inner_radius = float(cfg.get("radius", 0.5)) * 0.7
			pm.emission_ring_height = 0.05
		"point":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
		_:
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = cfg.get("radius", 0.2)
	pm.direction = cfg.get("direction", Vector3.UP)
	pm.spread = cfg.get("spread", 30.0)
	pm.flatness = cfg.get("flatness", 0.0)
	var vel: Vector2 = cfg.get("velocity", Vector2(0.2, 0.6))
	pm.initial_velocity_min = vel.x
	pm.initial_velocity_max = vel.y
	var radial: Vector2 = cfg.get("radial", Vector2.ZERO)
	pm.radial_velocity_min = radial.x
	pm.radial_velocity_max = radial.y
	pm.gravity = cfg.get("gravity", Vector3.ZERO)
	var damp: float = cfg.get("damping", 0.5)
	pm.damping_min = damp
	pm.damping_max = damp * 1.5
	var sc: Vector2 = cfg.get("scale", Vector2(0.6, 1.0))
	pm.scale_min = sc.x
	pm.scale_max = sc.y
	if cfg.get("grow", false):
		pm.scale_curve = scale_curve(0.3, 0.35, 1.0)
	else:
		pm.scale_curve = scale_curve(0.4, 0.2, 0.0)
	var color: Color = cfg.get("color", Color(0.6, 0.86, 1.0, 1.0))
	pm.color_ramp = fade_ramp(color)
	if cfg.get("turbulence", false):
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 0.6
		pm.turbulence_noise_scale = 3.0
		pm.turbulence_influence_min = 0.05
		pm.turbulence_influence_max = 0.15
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * float(cfg.get("size", 0.06))
	match String(cfg.get("kind", "energy")):
		"dust": quad.material = dust_material()
		"smoke": quad.material = smoke_material(cfg.get("soft", false))
		"sand": quad.material = sand_material()
		_: quad.material = energy_material()
	p.draw_pass_1 = quad
	return p


## Restarts a one-shot burst at a world position, optionally scaled down.
static func burst(p: GPUParticles3D, at: Vector3, ratio: float = 1.0) -> void:
	p.global_position = at
	p.amount_ratio = clampf(ratio, 0.05, 1.0)
	p.restart()
	p.emitting = true
