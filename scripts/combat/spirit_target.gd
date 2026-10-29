class_name SpiritTarget
extends Node3D
## A training sentinel to fight: a weathered stone shard floating above the sand, a ring
## of amber runes turning around its waist. Hits are judged by CombatDirector (distance
## to the blade or the strike), so it has no physics body and never blocks the ride.
## Light hits flash it, knock it back and set it wobbling; heavy ones throw it and spin
## it; a hit in the air can launch it upward. It always drifts back to its post. When
## its strength runs out it bursts into smoke and stone dust and forms again later.

signal broken

@export var hover_height := 1.4
@export var max_health := 5.0
@export var respawn_time := 4.0
## Radius (m) the blade has to reach.
@export var hurt_radius := 0.8

var alive := true
var health := 5.0

var _anchor := Vector3.ZERO
var _pos := Vector3.ZERO
var _vel := Vector3.ZERO
var _tilt := Vector3.ZERO
var _tilt_v := Vector3.ZERO
var _yaw := 0.0
var _spin := 0.0
var _flash := 0.0
var _time := 0.0
var _respawn := 0.0
var _grow := 1.0
var _body: Node3D
var _ring: MeshInstance3D
var _stone_mat := StandardMaterial3D.new()
var _rune_mat := StandardMaterial3D.new()
var _sparks: GPUParticles3D
var _puff: GPUParticles3D
var _dust: GPUParticles3D
var _wisps: GPUParticles3D


## A sentinel standing guard at `at` (XZ on the terrain).
static func spawn(parent: Node, at: Vector3) -> SpiritTarget:
	var t := SpiritTarget.new()
	parent.add_child(t)
	var y := at.y
	if DuneTerrain.instance:
		y = DuneTerrain.instance.height_at(at.x, at.z)
	t.post(Vector3(at.x, y, at.z))
	return t


func _ready() -> void:
	add_to_group(&"spirit_targets")
	top_level = true
	health = max_health
	_time = randf() * 10.0
	_body = Node3D.new()
	add_child(_body)
	_stone_mat.albedo_color = Color(0.62, 0.46, 0.38)
	_stone_mat.roughness = 0.92
	_rune_mat.albedo_color = Color(0.25, 0.1, 0.05)
	_rune_mat.emission_enabled = true
	_rune_mat.emission = Color(1.0, 0.5, 0.2)
	_rune_mat.emission_energy_multiplier = 1.6
	# A tall six-sided shard, pointed at both ends.
	for part in [[0.0, 0.36, 0.24, 1.3], [0.82, 0.24, 0.03, 0.34], [-0.86, 0.02, 0.36, 0.42]]:
		var c := CylinderMesh.new()
		c.radial_segments = 6
		c.rings = 1
		c.top_radius = part[2]
		c.bottom_radius = part[1]
		c.height = part[3]
		var mi := MeshInstance3D.new()
		mi.mesh = c
		mi.material_override = _stone_mat
		mi.position = Vector3(0.0, part[0], 0.0)
		_body.add_child(mi)
	_ring = MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.42
	tor.outer_radius = 0.5
	tor.rings = 24
	tor.ring_segments = 6
	_ring.mesh = tor
	_ring.material_override = _rune_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(_ring)
	_sparks = Fx.particles({"amount": 40, "lifetime": 0.6, "size": 0.05, "one_shot": true, "explosiveness": 0.95,
		"direction": Vector3.UP, "spread": 180.0, "velocity": Vector2(2.0, 6.0), "damping": 3.0,
		"color": Color(1.0, 0.62, 0.3, 1.0)})
	add_child(_sparks)
	_puff = Fx.particles({"amount": 24, "lifetime": 1.0, "size": 0.6, "kind": "smoke", "one_shot": true,
		"explosiveness": 0.9, "direction": Vector3.UP, "spread": 180.0, "velocity": Vector2(0.8, 2.6),
		"damping": 2.5, "grow": true, "color": Color(0.05, 0.045, 0.05, 0.7), "turbulence": true})
	add_child(_puff)
	_dust = Fx.particles({"amount": 30, "lifetime": 1.4, "size": 0.5, "kind": "sand", "one_shot": true,
		"explosiveness": 0.95, "direction": Vector3.UP, "spread": 120.0, "velocity": Vector2(1.5, 5.0),
		"gravity": Vector3(0, -3.0, 0), "damping": 1.5, "grow": true, "color": Color(0.85, 0.6, 0.42, 0.8)})
	add_child(_dust)
	_wisps = Fx.particles({"amount": 10, "lifetime": 1.2, "size": 0.25, "kind": "smoke", "radius": 0.08,
		"direction": Vector3.DOWN, "spread": 25.0, "velocity": Vector2(0.2, 0.6), "gravity": Vector3(0, -0.3, 0),
		"grow": true, "color": Color(0.05, 0.045, 0.05, 0.45), "turbulence": true})
	_wisps.emitting = true
	add_child(_wisps)


## Sets its post (ground point below it).
func post(ground: Vector3) -> void:
	_anchor = ground + Vector3.UP * hover_height
	_pos = _anchor
	global_position = _pos


## Centre of the part the blade has to reach.
func hurt_center() -> Vector3:
	return _body.global_position


## A hit: damage, heavy, dir (push direction), launch (thrown up), point.
func take_hit(info: Dictionary) -> void:
	if not alive:
		return
	var heavy: bool = info.get("heavy", false)
	var dir: Vector3 = info.get("dir", Vector3.FORWARD)
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	health -= float(info.get("damage", 1.0))
	_vel += dir * (8.0 if heavy else 3.5) + Vector3.UP * (7.0 if info.get("launch", false) else (4.0 if heavy else 1.0))
	_tilt_v += Vector3(dir.z, 0.0, -dir.x) * (10.0 if heavy else 5.0)
	_spin += 7.0 if heavy else 2.5
	_flash = 1.0
	var point: Vector3 = info.get("point", hurt_center())
	Fx.burst(_sparks, point, 1.0 if heavy else 0.5)
	Fx.burst(_puff, hurt_center(), 0.8 if heavy else 0.35)
	if health <= 0.0:
		_break()


func _break() -> void:
	alive = false
	_body.visible = false
	_wisps.emitting = false
	Fx.burst(_puff, hurt_center(), 1.0)
	Fx.burst(_dust, hurt_center(), 1.0)
	Fx.burst(_sparks, hurt_center(), 1.0)
	_respawn = respawn_time
	broken.emit()


func _process(delta: float) -> void:
	_time += delta
	if not alive:
		_respawn -= delta
		if _respawn <= 0.0:
			alive = true
			health = max_health
			_pos = _anchor
			_vel = Vector3.ZERO
			_tilt = Vector3.ZERO
			_tilt_v = Vector3.ZERO
			_grow = 0.0
			_body.visible = true
			_wisps.emitting = true
			Fx.burst(_puff, _anchor, 0.6)
		return
	# Drifts back to its post (a soft spring), bobbing; knocks and launches play out.
	var target := _anchor + Vector3(0.0, 0.12 * sin(_time * 1.3), 0.0)
	_vel += ((target - _pos) * 9.0 - _vel * 3.2) * delta
	_pos += _vel * delta
	if DuneTerrain.instance:
		_pos.y = maxf(_pos.y, DuneTerrain.instance.height_at(_pos.x, _pos.z) + 0.7)
	global_position = _pos
	_tilt_v += (-_tilt * 40.0 - _tilt_v * 5.0) * delta
	_tilt += _tilt_v * delta
	_spin = move_toward(_spin, 0.0, delta * 3.0)
	_yaw += (0.35 + _spin) * delta
	_grow = move_toward(_grow, 1.0, delta * 2.0)
	_body.transform = Transform3D(Basis.from_euler(Vector3(_tilt.x, _yaw, _tilt.z)).scaled(Vector3.ONE * smoothstep(0.0, 1.0, _grow)), Vector3.ZERO)
	_ring.rotation.y = -_time * 1.4 - _yaw * 2.0
	_flash = move_toward(_flash, 0.0, delta * 4.0)
	_rune_mat.emission_energy_multiplier = 1.6 + 7.0 * _flash
	_stone_mat.albedo_color = Color(0.62, 0.46, 0.38).lerp(Color(1.0, 0.85, 0.7), _flash * 0.6)
