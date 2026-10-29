class_name SandFX
extends Node3D
## The sand answering the sword. Everything here is driven by the board's real contact
## and motion (Hoverboard.update_effects feeds it every frame), never emitted blindly:
##  * carving / drifting: grains and dust thrown off the OUTSIDE edge, up and outward,
##    stronger with speed and turn sharpness;
##  * speed: a narrow rooster tail of grains kicked up behind the sword, longer and
##    denser the faster she goes, with low dust drifting near the surface;
##  * takeoff, landing (scaled by the impact, wider when hard), a sand slash (E in a
##    carve, thrown from the inside edge), boost and clean trick landings: bursts.
## Grains are thousands of tiny sunlit specks (sand_grain.gdshader) that fall under
## gravity and settle on the dunes (collision against a height field of the terrain
## that follows the camera), then shrink away; dust is soft sand-coloured puffs. In the
## patches of deep, loose sand (DuneTerrain.softness_at) everything is far denser.

## Visual layer the terrain also renders into, so only it shapes the height field.
const TERRAIN_LAYER := 1 << 19

@export var grain_light := Color(1.0, 0.56, 0.24)
@export var grain_dark := Color(0.8, 0.4, 0.15)
@export var dust_color := Color(0.9, 0.58, 0.33, 0.42)
@export_range(0.0, 2.0) var intensity := 1.0

var _spray: GPUParticles3D
var _trail: GPUParticles3D
var _dust: GPUParticles3D
var _bursts: Array[GPUParticles3D] = []
var _burst_dust: Array[GPUParticles3D] = []
var _next_burst := 0
var _height: GPUParticlesCollisionHeightField3D
var _grain_mat := ShaderMaterial.new()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_grain_mat.shader = load("res://shaders/sand_grain.gdshader")
	_spray = _grains(3200, 1.15, 0.02)
	_trail = _grains(1600, 0.9, 0.018)
	for i in 2:
		var b := _grains(1200, 1.35, 0.022)
		b.one_shot = true
		b.explosiveness = 0.92
		var pm := b.process_material as ParticleProcessMaterial
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3.UP
		pm.emission_ring_height = 0.05
		_bursts.append(b)
		var d := Fx.particles({"amount": 40, "lifetime": 1.6, "size": 0.8, "kind": "sand", "one_shot": true,
			"explosiveness": 0.9, "shape": "ring", "radius": 0.5, "direction": Vector3.UP, "spread": 80.0,
			"flatness": 0.6, "velocity": Vector2(1.0, 3.5), "gravity": Vector3(0, -0.6, 0), "damping": 2.2,
			"scale": Vector2(0.6, 1.5), "grow": true, "color": dust_color, "turbulence": true})
		add_child(d)
		_burst_dust.append(d)
	_dust = Fx.particles({"amount": 150, "lifetime": 1.5, "size": 0.75, "kind": "sand", "shape": "box",
		"extents": Vector3(0.15, 0.05, 0.4), "direction": Vector3(0, 1, 0.5), "spread": 35.0,
		"velocity": Vector2(0.4, 1.6), "gravity": Vector3(0, 0.15, 0), "damping": 1.8,
		"scale": Vector2(0.5, 1.4), "grow": true, "color": dust_color, "turbulence": true})
	(_dust.process_material as ParticleProcessMaterial).inherit_velocity_ratio = 0.35
	add_child(_dust)
	_height = GPUParticlesCollisionHeightField3D.new()
	_height.size = Vector3(56.0, 40.0, 56.0)
	_height.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_256
	_height.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	_height.follow_camera_enabled = true
	# Only the terrain shapes the height field (heightfield_mask); every particle system
	# collides with it (cull_mask is about which particles are affected).
	_height.heightfield_mask = TERRAIN_LAYER
	add_child(_height)


func _grains(amount: int, lifetime: float, size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.randomness = 0.5
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-30, -15, -30), Vector3(60, 30, 60))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.collision_base_size = 0.02
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.05, 0.03, 0.45)
	pm.direction = Vector3(1.0, 1.0, 0.4)
	pm.spread = 25.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(0.0, -9.8, 0.0)
	pm.damping_min = 0.2
	pm.damping_max = 0.8
	pm.scale_min = 0.45
	pm.scale_max = 1.25
	# Full size most of their life, then shrinking away (no fade: they are opaque).
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(0.7, 0.9))
	c.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = c
	pm.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, grain_dark)
	g.set_color(1, grain_light)
	g.add_point(0.6, grain_light.lerp(grain_dark, 0.35))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_initial_ramp = gt
	pm.inherit_velocity_ratio = 0.35
	pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	pm.collision_friction = 0.85
	pm.collision_bounce = 0.08
	pm.collision_use_scale = true
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	quad.material = _grain_mat
	p.draw_pass_1 = quad
	add_child(p)
	return p


## Per frame. `s`: active, contact (on the sand), ground (point), basis (the sword's
## global basis), speed (m/s), speed01, carve (-1..1, + = left), drift, boost.
func update(_delta: float, s: Dictionary) -> void:
	var active: bool = s["active"]
	var contact: bool = active and s["contact"]
	var ground: Vector3 = s["ground"]
	var basis: Basis = s["basis"]
	var speed: float = s["speed"]
	var speed01: float = s["speed01"]
	var carve: float = s["carve"]
	var soft := softness(ground)
	var dense := (1.0 + 1.6 * soft) * intensity
	var bx := basis.x.normalized()
	var bz := basis.z.normalized()
	var flat_z := Vector3(bz.x, 0.0, bz.z).normalized() if Vector2(bz.x, bz.z).length() > 0.1 else Vector3.BACK

	# Carving: off the outside edge (a left turn throws sand to the right).
	var carve_i := clampf(absf(carve) * 1.25 + float(s["drift"]), 0.0, 1.0) * clampf(speed / 8.0, 0.0, 1.0)
	_set_rate(_spray, contact and carve_i > 0.06, carve_i * 0.55 * dense)
	if _spray.emitting:
		var out := signf(carve) if absf(carve) > 0.03 else 1.0
		var ox := bx * out
		var sb := Basis(ox, Vector3.UP, flat_z)
		_spray.global_transform = Transform3D(sb, ground + Vector3.UP * 0.06 + ox * 0.08 + flat_z * 0.2)
		var pm := _spray.process_material as ParticleProcessMaterial
		pm.initial_velocity_min = 1.2 + speed * 0.06
		pm.initial_velocity_max = 2.8 + speed * 0.2 * (0.5 + 0.5 * carve_i)
	# Speed: a narrow rooster tail kicked up behind the sword.
	var tail_i := clampf((speed01 - 0.45) * 1.3, 0.0, 1.0)
	_set_rate(_trail, contact and tail_i > 0.04, tail_i * 0.5 * dense)
	if _trail.emitting:
		var tb := Basis(bx, Vector3.UP, flat_z)
		_trail.global_transform = Transform3D(tb, ground + Vector3.UP * 0.05 + flat_z * 0.65)
		var pm := _trail.process_material as ParticleProcessMaterial
		pm.direction = Vector3(0.0, 1.0, 0.9)
		pm.spread = 10.0
		pm.emission_box_extents = Vector3(0.05, 0.02, 0.12)
		pm.initial_velocity_min = 1.0 + speed * 0.05
		pm.initial_velocity_max = 2.0 + speed * 0.13
	# Dust drifting low near the surface, with the carve and at speed.
	var dust_i := maxf(carve_i * 0.8, tail_i * 0.35) * (0.6 + 0.8 * soft)
	_set_rate(_dust, contact and dust_i > 0.05, dust_i * intensity)
	if _dust.emitting:
		_dust.global_position = ground + Vector3.UP * 0.1 + flat_z * 0.3


func _set_rate(p: GPUParticles3D, on: bool, ratio: float) -> void:
	p.emitting = on
	if on:
		p.amount_ratio = clampf(ratio, 0.03, 1.0)


## 0..1: how deep and loose the sand is here.
func softness(at: Vector3) -> float:
	return DuneTerrain.instance.softness_at(at.x, at.z) if DuneTerrain.instance else 0.0


## A burst of grains and dust at `at`. strength 0..1; `dir` the main throw direction
## (world), `radius` the ring it leaves from.
func burst(at: Vector3, strength: float, dir := Vector3.UP, radius := 0.4, spread := 65.0) -> void:
	var soft := softness(at)
	var k := clampf(strength * (1.0 + 0.8 * soft) * intensity, 0.08, 1.0)
	var b := _bursts[_next_burst]
	var d := _burst_dust[_next_burst]
	_next_burst = (_next_burst + 1) % _bursts.size()
	var pm := b.process_material as ParticleProcessMaterial
	pm.direction = dir.normalized()
	pm.spread = spread
	pm.emission_ring_radius = radius
	pm.emission_ring_inner_radius = radius * 0.4
	pm.initial_velocity_min = 1.2 + 2.0 * k
	pm.initial_velocity_max = 2.5 + 5.5 * k
	b.global_position = at + Vector3.UP * 0.05
	b.amount_ratio = k
	b.restart()
	b.emitting = true
	var dpm := d.process_material as ParticleProcessMaterial
	dpm.emission_ring_radius = radius * 1.1
	dpm.emission_ring_inner_radius = radius * 0.6
	d.global_position = at + Vector3.UP * 0.1
	d.amount_ratio = clampf(k * 1.1, 0.1, 1.0)
	d.restart()
	d.emitting = true
