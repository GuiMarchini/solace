class_name Hoverboard
extends Node3D
## Visual side of the spirit's floating sword while it carries her (see SpiritSword):
## materialize / dissolve, a single point of light trailing behind it (no long beams),
## the cloth strips on the grip (SwordCloth), the groove it cuts (SandTrail) and the
## sand it throws (SandFX), all driven by the real riding state.
## The origin is the top of the blade (where the rider's feet stand), tip toward -Z.
## Riding physics live in HoverMotor; PlayerVisual poses this node each frame and
## feeds it the riding state through update_effects() and the event calls below.

signal fully_dismissed

@export_group("Shape")
## Footprint used to size effects (the sword's blade).
@export var length := 1.72
@export var width := 0.22
@export var thickness := 0.04
@export_group("Look")
@export var board_material: ShaderMaterial
## The rune light (warm ember red-orange, as on the sword's concept sheet).
@export var energy_color := Color(1.0, 0.45, 0.25)
@export var cloth_material: Material = preload("res://materials/cloak_strip.tres")
@export var light_energy := 0.18
@export var materialize_time := 0.55
@export var dismiss_time := 0.45
@export_group("Effects")
@export var particle_intensity := 1.0
## The point of light behind the sword: size (m) and brightness.
@export var tail_light_size := 0.2
@export var tail_light_intensity := 0.9
@export var circle_time := 0.9

var active := false
var materialize := 0.0
## True while the sword is dissolved into smoke (the Last Spirit): it fades out and,
## when set back, reconstructs under her.
var spectral := false

var _mesh: MeshInstance3D
var _cloth: SwordCloth
# The spectral blade (the Last Spirit): the sword's shape grown huge, scaled about the grip.
var _ghost: MeshInstance3D
var _ghost_mat := ShaderMaterial.new()
var _ghost_form := 0.0
var _ghost_target := 0.0
var _tail: MeshInstance3D
var _tail_mat := ShaderMaterial.new()
var _light: OmniLight3D
var _motes: GPUParticles3D
# A short glowing arc from the tip while the sword whirls (spins, varials).
var _arc: TrailRibbon
var _swing := 0.0
var _summon_burst: GPUParticles3D
var _spark_burst: GPUParticles3D
var _circle: MeshInstance3D
var _circle_mat := ShaderMaterial.new()
var _circle_t := 1.0
var _groove: SandTrail
var _sand: SandFX
var _time := 0.0
var _energy := 1.0
var _flare := 0.0
var _was_contact := false
var _last_speed := 0.0
var _ground := Vector3.ZERO


func _ready() -> void:
	if board_material == null:
		board_material = load("res://materials/sword.tres")
	board_material = board_material.duplicate()
	_mesh = MeshInstance3D.new()
	_mesh.name = "BoardMesh"
	_mesh.mesh = SpiritSword.mesh()
	_mesh.material_override = board_material
	add_child(_mesh)
	board_material.set_shader_parameter("energy_color", energy_color)
	board_material.set_shader_parameter("tip_z", SpiritSword.TIP_Z)
	board_material.set_shader_parameter("guard_z", SpiritSword.GUARD_Z)
	board_material.set_shader_parameter("emblem", SpiritSword.EMBLEM)
	board_material.set_shader_parameter("emblem_radius", SpiritSword.EMBLEM_RADIUS)
	_ghost = MeshInstance3D.new()
	_ghost.name = "SpectralBlade"
	_ghost.mesh = SpiritSword.mesh()
	_ghost_mat.shader = load("res://shaders/ghost_blade.gdshader")
	_ghost.material_override = _ghost_mat
	var k := 2.6
	_ghost.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * k), SpiritSword.GRIP - SpiritSword.GRIP * k)
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)
	_cloth = SwordCloth.new()
	_cloth.name = "Cloth"
	_cloth.strip_material = cloth_material
	_cloth.sword = _mesh
	add_child(_cloth)

	# One soft point of light behind the sword (where the spirit's propulsion leaves it).
	_tail = MeshInstance3D.new()
	_tail.name = "TailLight"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * tail_light_size
	_tail.mesh = quad
	_tail_mat.shader = load("res://shaders/tail_light.gdshader")
	_tail_mat.set_shader_parameter("color", energy_color)
	_tail.material_override = _tail_mat
	_tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tail.position = Vector3(0.0, -SpiritSword.THICK, SpiritSword.GRIP.z + 0.38)
	add_child(_tail)

	_light = OmniLight3D.new()
	_light.light_color = energy_color
	# At deck level (below it, carving put it right against the sand: a hot spot).
	_light.omni_range = 2.0
	_light.omni_attenuation = 2.0
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 0.12, 0.3)
	add_child(_light)

	var tip := Node3D.new()
	tip.name = "Tip"
	tip.position = Vector3(0.0, -SpiritSword.THICK, SpiritSword.TIP_Z + 0.06)
	_mesh.add_child(tip)
	_arc = TrailRibbon.new()
	_arc.source = tip
	_arc.color = energy_color
	_arc.width = 0.032
	_arc.lifetime = 0.2
	_arc.min_distance = 0.04
	# Recorded around the rider, so it draws the whirl, not a streak across the desert.
	_arc.space = get_parent() as Node3D
	add_child(_arc)

	_motes = Fx.particles({"amount": 5, "lifetime": 1.2, "size": 0.02, "shape": "box",
		"extents": Vector3(width * 0.4, 0.02, length * 0.4), "direction": Vector3.DOWN,
		"spread": 40.0, "velocity": Vector2(0.1, 0.4), "gravity": Vector3(0, 0.2, 0),
		"color": Color(1.0, 0.72, 0.5, 0.4), "turbulence": true})
	_motes.position = Vector3(0.0, -thickness, 0.0)
	add_child(_motes)

	_summon_burst = Fx.particles({"amount": 40, "lifetime": 0.9, "size": 0.03, "one_shot": true,
		"explosiveness": 0.9, "shape": "ring", "radius": 0.7, "direction": Vector3.UP,
		"spread": 20.0, "velocity": Vector2(0.5, 2.0), "radial": Vector2(-0.6, -0.2),
		"gravity": Vector3(0, 0.6, 0), "color": Color(1.0, 0.7, 0.48, 1.0)})
	add_child(_summon_burst)

	# Sparks off the runes: the charged jump being ready, a clean trick landing.
	_spark_burst = Fx.particles({"amount": 34, "lifetime": 0.7, "size": 0.035, "one_shot": true,
		"explosiveness": 0.95, "shape": "box", "extents": Vector3(width * 0.3, 0.02, length * 0.4),
		"direction": Vector3.UP, "spread": 70.0, "velocity": Vector2(0.8, 2.6), "gravity": Vector3(0, 0.4, 0),
		"damping": 2.0, "color": Color(1.0, 0.68, 0.42, 1.0)})
	add_child(_spark_burst)

	_groove = SandTrail.new()
	add_child(_groove)
	_sand = SandFX.new()
	_sand.name = "Sand"
	add_child(_sand)

	# Summoning circle drawn on the sand.
	_circle = MeshInstance3D.new()
	var cq := QuadMesh.new()
	cq.size = Vector2(2.2, 2.2)
	cq.orientation = PlaneMesh.FACE_Y
	_circle.mesh = cq
	_circle_mat.shader = load("res://shaders/magic_circle.gdshader")
	_circle_mat.set_shader_parameter("color", energy_color)
	_circle.material_override = _circle_mat
	_circle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_circle.top_level = true
	_circle.visible = false
	add_child(_circle)

	_set_materialize(0.0)
	visible = false


func summon() -> void:
	active = true
	visible = true
	_cloth.reset()
	_groove.clear()
	Fx.burst(_summon_burst, global_position, particle_intensity)
	_show_circle()


func dismiss() -> void:
	active = false
	_motes.emitting = false
	Fx.burst(_summon_burst, global_position, 0.6 * particle_intensity)


func on_jump() -> void:
	_flare = maxf(_flare, 0.6)


func on_land(impact: float, ground_point: Vector3) -> void:
	# Small puff for a gentle touchdown, a wide burst for a hard one.
	var k := clampf(impact / 14.0, 0.0, 1.0)
	_sand.burst(ground_point, 0.15 + 0.85 * k, Vector3.UP, 0.35 + 0.6 * k, 55.0 + 25.0 * k)
	_flare = maxf(_flare, 0.4 + 0.6 * k)


func on_boost_start() -> void:
	_flare = maxf(_flare, 1.0)
	if _was_contact:
		# A brief disturbance of the sand under the sword as it surges.
		_sand.burst(_ground - global_basis.z * 0.2, 0.35, global_basis.z + Vector3.UP * 0.8, 0.3, 40.0)


## E in a sharp carve: the inside hand cuts the sand, which sprays up and inward.
func on_slash(side: float) -> void:
	var inside := -global_basis.x * side
	_sand.burst(_ground + inside * 0.35, 0.75, inside + Vector3.UP * 1.1, 0.3, 35.0)


## A flare of the runes (combat hits, spirit energy ready).
func pulse(amount: float) -> void:
	_flare = maxf(_flare, amount)


## A trick of hers begins: the runes flare for its length (it reads from afar).
func on_trick_start() -> void:
	_flare = maxf(_flare, 1.1)


## The held jump is fully charged: the runes flare and spark.
## The spectral blade condensing (1) or fraying away (0).
func set_ghost(amount: float) -> void:
	_ghost_target = clampf(amount, 0.0, 1.0)


## Dissolves the sword into smoke, or reconstructs it (with a burst of light).
func set_spectral(on: bool) -> void:
	if on == spectral:
		return
	spectral = on
	Fx.burst(_summon_burst, global_position, particle_intensity * (0.8 if on else 1.0))


## World positions of the grip and the tip (hit detection, blade trails).
func blade_points() -> Array:
	var xf := global_transform
	return [xf * SpiritSword.GRIP, xf * Vector3(0.0, -SpiritSword.THICK, SpiritSword.TIP_Z)]


## How fast the sword whirls (rad/s, PlayerVisual): fast spins draw a short arc.
func set_swing(rate: float) -> void:
	_swing = lerpf(_swing, rate, 0.5)
	_arc.emitting = active and materialize > 0.6 and _swing > 7.0
	_arc.intensity = clampf((_swing - 7.0) / 7.0, 0.0, 1.0) * 1.1


func on_charge_ready() -> void:
	_flare = maxf(_flare, 1.3)
	Fx.burst(_spark_burst, global_position, particle_intensity)


## A clean landing after tricks: a brighter burst, scaled by the combo.
func on_trick_landed(multiplier: float) -> void:
	_flare = maxf(_flare, 1.0 + 0.2 * multiplier)
	Fx.burst(_spark_burst, global_position, clampf(0.5 + 0.15 * multiplier, 0.5, 1.0))
	_sand.burst(_ground, clampf(0.4 + 0.12 * multiplier, 0.4, 1.0), Vector3.UP, 0.6, 70.0)


## Per-frame visual update driven by PlayerVisual.
## speed01: 0..1 of cruise speed; boost: 0..1; ground_dist: deck height above sand.
func update_effects(delta: float, speed01: float, boost: float, supported: bool,
		ground_point: Vector3, ground_dist: float, carve: float, drift: float = 0.0) -> void:
	_time += delta
	_update_circle(delta, ground_point)
	var target := 1.0 if active and not spectral else 0.0
	var rate := 1.0 / (materialize_time if active else dismiss_time)
	if materialize != target:
		materialize = move_toward(materialize, target, delta * rate)
		_set_materialize(materialize)
		if materialize <= 0.0 and not active:
			visible = false
			fully_dismissed.emit()
	var contact := active and supported and ground_dist < 0.6
	var speed := speed01 * 16.0
	_ground = ground_point
	if _groove:
		_groove.feed(delta, ground_point, global_basis.y, contact and speed01 > 0.08)
	if not visible:
		_was_contact = contact
		return
	_cloth.ground_height = ground_point.y if ground_dist < 3.0 else -INF
	_cloth.visible = materialize > 0.5
	_cloth.step(delta)
	_ghost_form = move_toward(_ghost_form, _ghost_target, delta * (2.2 if _ghost_target > _ghost_form else 1.6))
	_ghost.visible = _ghost_form > 0.01
	_ghost_mat.set_shader_parameter("form", _ghost_form)
	# Leaving the sand at speed (a jump or a crest): a short burst at takeoff.
	if _was_contact and not contact and active and speed01 > 0.3:
		_sand.burst(ground_point, clampf(speed01 * 0.5, 0.2, 0.7), Vector3.UP + global_basis.z * 0.6, 0.3, 50.0)
	_was_contact = contact
	_sand.update(delta, {"active": active and materialize > 0.6, "contact": contact, "ground": ground_point,
		"basis": global_basis, "speed": speed, "speed01": speed01, "carve": carve, "drift": drift, "boost": boost})

	var on := active and materialize > 0.6
	_flare = move_toward(_flare, 0.0, delta * 1.6)
	_energy = lerpf(_energy, 1.0 + boost * 1.2 + speed01 * 0.3 + _flare, 1.0 - exp(-8.0 * delta))
	board_material.set_shader_parameter("energy", _energy)
	board_material.set_shader_parameter("flow_speed", 1.2 + speed01 * 2.0 + boost * 3.0)
	var pulse := 0.85 + 0.15 * sin(_time * 3.0)
	_light.light_energy = light_energy * materialize * _energy * pulse * (1.0 if supported else 0.6)
	_tail_mat.set_shader_parameter("intensity", tail_light_intensity * materialize * (0.8 + 0.25 * boost + 0.3 * _flare) * pulse)
	_tail.scale = Vector3.ONE * (1.0 + 0.35 * boost + 0.25 * _flare)
	_motes.emitting = on
	_motes.amount_ratio = clampf((0.5 + speed01 * 0.5) * particle_intensity, 0.05, 1.0)


func _show_circle() -> void:
	# Lay the circle flat on the ground under the feet (origin = deck = feet on summon).
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, global_position + Vector3.DOWN * 3.0, 1)
	var hit := space.intersect_ray(q)
	var pos := global_position
	var n := Vector3.UP
	if not hit.is_empty():
		pos = hit["position"]
		n = hit["normal"]
	var x := n.cross(Vector3.FORWARD).normalized()
	if x.length_squared() < 0.01:
		x = Vector3.RIGHT
	_circle.global_transform = Transform3D(Basis(x, n, x.cross(n)).orthonormalized(), pos + n * 0.04)
	_circle.visible = true
	_circle_t = 0.0


func _update_circle(delta: float, ground_point: Vector3) -> void:
	if _circle_t >= 1.0:
		return
	# Follow the rider while it plays.
	var xf := _circle.global_transform
	xf.origin = xf.origin.lerp(ground_point + xf.basis.y * 0.04, 1.0 - exp(-12.0 * delta))
	_circle.global_transform = xf
	_circle_t = minf(_circle_t + delta / circle_time, 1.0)
	_circle_mat.set_shader_parameter("progress", _circle_t)
	if _circle_t >= 1.0:
		_circle.visible = false


func _set_materialize(v: float) -> void:
	board_material.set_shader_parameter("materialize", v)
