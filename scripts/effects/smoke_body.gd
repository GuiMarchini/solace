class_name SmokeBody
extends Node3D
## The wanderer's living smoke.
##
## The body itself is SpiritModel's continuous skinned silhouette drawn with
## smoke_body.gdshader (billows boiling up the body, feet coming apart into smoke) and
## its translucent outer layer smoke_shell.gdshader (the outline blurs into curling
## smoke). This node adds what that surface can't do:
##  * the hands, with long fingers, built once as signed distance fields at a finer
##    resolution than the body and carried by the hand bones;
##  * physical smoke: thin grey wisps rising off the whole body (torso, arms, legs)
##    and ink-like GPU puffs pouring from the shins and feet. Each keeps part of the
##    body's velocity (momentum), rises by buoyancy, is
##    slowed by air drag and curls with turbulence, so at speed the smoke streams back
##    along the actual path, bends through turns and lags on jumps; landings and
##    impacts throw out a short, flattened burst;
##  * state: speed, airborne, boost, rest, jumps, landings and combat (gather /
##    follow_arc / on_impact) scale emission, flow speed and the embers' glow smoothly.
## PlayerVisual calls update() each frame.

const HAND_PATH := "res://assets/spirit/hand_%s.res"
const HAND_VERSION := 3

@export var body_material: ShaderMaterial
@export_group("Smoke")
@export var smoke_color := Color(0.03, 0.028, 0.03, 0.7)
## Thin smoke coming off the body.
@export var wisp_color := Color(0.06, 0.058, 0.06, 0.22)
## Fraction of the body's velocity a new wisp keeps (momentum).
@export_range(0.0, 1.0) var inherit_velocity := 0.75
## Upward acceleration of the smoke (buoyancy) and its air drag.
@export var buoyancy := 0.45
@export var drag := 1.4
@export var turbulence := 1.1
## Hands are drawn larger than the bone chain suggests (the concept's long hands).
@export var hand_scale := 1.45
@export_group("Response")
@export var emission_idle := 0.35
@export var emission_fast := 1.0
@export var fast_speed := 16.0
@export var flow_idle := 0.45
@export var flow_fast := 1.2
@export var rest_emission := 0.12
@export var rest_flow := 0.2

var model: SpiritModel

var _hands: Array[MeshInstance3D] = []
# The hands share the body's smoke but swell less and have no outer layer (it would
# blur the fingers).
var _hand_mat: ShaderMaterial
# The smoke layers rising off the body (smoke_shell.gdshader), chained after it.
var _shells: Array[ShaderMaterial] = []
var _legs: Array[GPUParticles3D] = []
var _feet: Array[GPUParticles3D] = []
var _puff: GPUParticles3D
var _plume: Array[GPUParticles3D] = []
var _wisps: Array[GPUParticles3D] = []
# Where the body wisps rise from: [bone a, bone b, fraction along a -> b].
var _wisp_at := [
	[SpiritModel.HIPS, SpiritModel.CHEST, 0.6],
	[SpiritModel.SH_L, SpiritModel.EL_L, 0.5], [SpiritModel.SH_R, SpiritModel.EL_R, 0.5],
	[SpiritModel.EL_L, SpiritModel.HA_L, 0.5], [SpiritModel.EL_R, SpiritModel.HA_R, 0.5],
	[SpiritModel.TH_L, SpiritModel.KN_L, 0.5], [SpiritModel.TH_R, SpiritModel.KN_R, 0.5],
	[SpiritModel.KN_L, SpiritModel.FT_L, 0.45], [SpiritModel.KN_R, SpiritModel.FT_R, 0.45],
]
var _emit := 0.4
var _flow := 0.45
var _energy := 0.0
var _gather := 0.0
var _arc := Vector3.ZERO
var _void_set := false


func _ready() -> void:
	if body_material:
		var pass_mat := body_material.next_pass as ShaderMaterial
		while pass_mat:
			_shells.append(pass_mat)
			pass_mat = pass_mat.next_pass as ShaderMaterial
		_hand_mat = body_material.duplicate() as ShaderMaterial
		_hand_mat.next_pass = null
		_hand_mat.set_shader_parameter("billow_depth", 0.003)
		_hand_mat.set_shader_parameter("billow_scale", 26.0)
		_hand_mat.set_shader_parameter("dissolve_height", -1.0)
		# The hands read against the cloak and the sand: lighter smoke over the knuckles,
		# a soft rim and a little light of their own (still dark, still smoke).
		_hand_mat.set_shader_parameter("billow_color", Color(0.12, 0.115, 0.12))
		_hand_mat.set_shader_parameter("highlight", Color(0.42, 0.4, 0.42))
		_hand_mat.set_shader_parameter("filaments", 1.2)
		_hand_mat.set_shader_parameter("self_light", 0.35)
		_hand_mat.set_shader_parameter("fray", 0.3)
	for side in ["l", "r"]:
		var h := MeshInstance3D.new()
		h.name = "Hand_" + side
		h.mesh = _hand_mesh(side)
		h.material_override = _hand_mat
		add_child(h)
		_hands.append(h)
	for i in 2:
		# Many small, faint puffs blend into continuous smoke instead of reading as
		# separate blobs, even when they are strung out behind at speed.
		_legs.append(_smoke({"amount": 110, "lifetime": 0.6, "size": 0.2, "radius": 0.05, "soft": true,
			"velocity": Vector2(0.1, 0.35), "gravity": Vector3(0, buoyancy * 2.0, 0),
			"color": Color(smoke_color, smoke_color.a * 0.35)}))
		# The feet pour the most: dense smoke spilling around them (over the blade
		# when riding) and streaming back with the motion.
		_feet.append(_smoke({"amount": 170, "lifetime": 0.6, "size": 0.26, "radius": 0.07, "soft": true,
			"spread": 80.0, "velocity": Vector2(0.15, 0.5), "gravity": Vector3(0, buoyancy * 2.0, 0),
			"color": Color(smoke_color, smoke_color.a * 0.45)}))
		var pl := _smoke({"amount": 140, "lifetime": 0.4, "size": 0.42, "radius": 0.07, "soft": true,
			"color": Color(smoke_color, smoke_color.a * 0.26)})
		pl.emitting = false
		_plume.append(pl)
	for w in _wisp_at:
		_wisps.append(_smoke({"amount": 18 if w[0] == SpiritModel.HIPS else 14, "lifetime": 0.6, "size": 0.13, "soft": true,
			"radius": 0.07 if w[0] == SpiritModel.HIPS else 0.04, "spread": 70.0, "velocity": Vector2(0.04, 0.18),
			"gravity": Vector3(0, buoyancy * 1.3, 0), "color": wisp_color}))
	# The burst emitter rides along with the body (update() keeps it at the feet), so a
	# landing's puff is carried with her and spreads out instead of being dropped on the
	# sand as a cluster of separate clumps.
	_puff = Fx.particles({"amount": 40, "lifetime": 0.9, "size": 0.36, "kind": "smoke", "soft": true, "one_shot": true,
		"explosiveness": 0.95, "shape": "ring", "radius": 0.25, "direction": Vector3.UP, "spread": 85.0,
		"flatness": 0.85, "velocity": Vector2(1.0, 2.6), "gravity": Vector3(0, buoyancy, 0), "damping": 2.5,
		"scale": Vector2(0.6, 1.4), "grow": true, "color": Color(smoke_color, smoke_color.a * 0.6), "turbulence": true})
	_physical(_puff)
	add_child(_puff)


func _smoke(cfg: Dictionary) -> GPUParticles3D:
	var c := {"kind": "smoke", "direction": Vector3.UP, "spread": 60.0, "velocity": Vector2(0.05, 0.3),
		"gravity": Vector3(0, buoyancy, 0), "damping": drag, "scale": Vector2(0.5, 1.3), "grow": true,
		"color": smoke_color, "turbulence": true}
	c.merge(cfg, true)
	var p := Fx.particles(c)
	_physical(p)
	p.preprocess = p.lifetime   # already smoking on the first frame
	add_child(p)
	p.emitting = true
	return p


## Momentum and stronger curl on a smoke emitter.
func _physical(p: GPUParticles3D) -> void:
	var pm := p.process_material as ParticleProcessMaterial
	pm.inherit_velocity_ratio = inherit_velocity
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = turbulence
	pm.turbulence_noise_scale = 1.6
	pm.turbulence_noise_speed = Vector3(0.0, 0.4, 0.0)
	pm.turbulence_influence_min = 0.08
	pm.turbulence_influence_max = 0.3


# --- Hands ---------------------------------------------------------------------------------

## Long-fingered hand in the hand bone's frame (wrist at the origin, fingers along -Y,
## thumb forward, curling toward the body).
static func _hand_mesh(side: String) -> ArrayMesh:
	var path := HAND_PATH % side
	if ResourceLoader.exists(path):
		var m := load(path) as ArrayMesh
		if m and m.get_meta("version", -1) == HAND_VERSION:
			return m
	var curl := 1.0 if side == "l" else -1.0
	var sdf := func(p: Vector3) -> float: return SmokeBody.hand_sdf(p, curl)
	var raw := SdfMesher.build(sdf, Vector3(-0.045, -0.15, -0.055), Vector3(0.045, 0.012, 0.05), 0.0024)
	var mesh := _with_rest_uv(raw, Vector3(curl * 0.4, 0.9, 0.0))
	mesh.set_meta("version", HAND_VERSION)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	ResourceSaver.save(mesh, path)
	return mesh


static func hand_sdf(p: Vector3, curl: float) -> float:
	var flat := Vector3(p.x * 1.7, p.y, p.z)
	var d := SdfMesher.round_cone(flat, Vector3(0.0, 0.006, 0.0), Vector3(0.0, -0.05, 0.0), 0.016, 0.02)
	var zs := [-0.021, -0.007, 0.007, 0.021]
	var lens := [0.058, 0.07, 0.066, 0.052]
	for i in 4:
		var z: float = zs[i]
		var l: float = lens[i]
		var k := Vector3(0.0, -0.048, z)
		var m := Vector3(curl * 0.006, -0.048 - l * 0.55, z * 1.15)
		var t := Vector3(curl * 0.017, -0.048 - l, z * 1.3)
		var f := minf(SdfMesher.round_cone(p, k, m, 0.0062, 0.005), SdfMesher.round_cone(p, m, t, 0.005, 0.0028))
		d = SdfMesher.smin(d, f, 0.006)
	var th := minf(SdfMesher.round_cone(p, Vector3(0.0, -0.012, -0.015), Vector3(curl * 0.012, -0.042, -0.03), 0.0078, 0.0062),
		SdfMesher.round_cone(p, Vector3(curl * 0.012, -0.042, -0.03), Vector3(curl * 0.022, -0.066, -0.034), 0.0062, 0.0036))
	return SdfMesher.smin(d, th, 0.01)


## Copies a mesh, storing each vertex's position (+ offset) as the rest position the
## smoke shader reads from UV.xy and COLOR.r, and cylindrical coordinates around the
## hand's axis in UV2 (the shader winds its strands with them).
static func _with_rest_uv(src: ArrayMesh, offset: Vector3) -> ArrayMesh:
	var a := src.surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var cols := PackedColorArray()
	for v in verts:
		var r := v + offset
		uvs.append(Vector2(r.x, r.y))
		uv2s.append(Vector2(atan2(v.x, v.z) / TAU, -v.y))
		cols.append(Color(r.z + 0.5, 0.0, 0.0, 1.0))
	a[Mesh.ARRAY_TEX_UV] = uvs
	a[Mesh.ARRAY_TEX_UV2] = uv2s
	a[Mesh.ARRAY_COLOR] = cols
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return out


# --- Events ---------------------------------------------------------------------------------

## Smoke gathers toward the body (0..1) while an attack winds up; call with 0 after.
func gather(amount: float) -> void:
	_gather = clampf(amount, 0.0, 1.0)


## A weapon arc's current world direction of travel: the plume follows it.
func follow_arc(dir: Vector3) -> void:
	_arc = dir


func on_jump() -> void:
	# No burst on takeoff: in the air (and through tricks) it scattered as dark flecks.
	pass


func on_land(impact: float) -> void:
	_burst(clampf(impact / 10.0, 0.25, 1.0))


## Strong impact (combat): the embers flare and smoke bursts out.
func on_impact(strength: float = 1.0) -> void:
	_energy = maxf(_energy, strength)
	_burst(clampf(strength, 0.3, 1.0))


func on_boost(active: bool) -> void:
	if active:
		_burst(0.35)


func _burst(ratio: float) -> void:
	if model:
		_puff.amount_ratio = clampf(ratio, 0.05, 1.0)
		_puff.restart()
		_puff.emitting = true


# --- Per frame -------------------------------------------------------------------------------

## state: velocity (world), airborne, boost (0..1), rest (0..1).
func update(delta: float, state: Dictionary) -> void:
	if model == null or delta <= 0.0:
		return
	var vel: Vector3 = state.get("velocity", Vector3.ZERO)
	var boost: float = state.get("boost", 0.0)
	var rest: float = state.get("rest", 0.0)
	var airborne: bool = state.get("airborne", false)
	var fast := clampf(vel.length() / fast_speed, 0.0, 1.0)
	var k := 1.0 - exp(-3.0 * delta)
	_emit = lerpf(_emit, lerpf(lerpf(emission_idle, emission_fast, fast), rest_emission, rest) * (1.0 - 0.6 * _gather), k)
	_flow = lerpf(_flow, lerpf(lerpf(flow_idle, flow_fast, fast), rest_flow, rest), k)
	_energy = move_toward(_energy, 0.0, delta * 1.5)
	_arc = _arc.lerp(Vector3.ZERO, 1.0 - exp(-6.0 * delta))
	if body_material:
		if not _void_set:
			_void_set = true
			var r := model.rest_offsets()
			var void_h := r[SpiritModel.HIPS].y + r[SpiritModel.SPINE].y + r[SpiritModel.CHEST].y + 0.07
			for m in [body_material, _hand_mat] + _shells:
				if m:
					m.set_shader_parameter("void_height", void_h)
			for m in _shells:
				m.set_shader_parameter("torso_height", r[SpiritModel.HIPS].y - 0.05)
		for m in [body_material, _hand_mat] + _shells:
			if m:
				m.set_shader_parameter("flow_speed", _flow)
		body_material.set_shader_parameter("energy", maxf(_energy, _gather * 0.5))
		if _hand_mat:
			_hand_mat.set_shader_parameter("energy", maxf(_energy, _gather * 0.5))

	var sk := model.skeleton
	var gx := model.global_transform
	_puff.global_position = model.global_position + Vector3.UP * 0.08
	for j in _wisps.size():
		var w: Array = _wisp_at[j]
		var a := sk.get_bone_global_pose(w[0]).origin
		var b := sk.get_bone_global_pose(w[1]).origin
		_wisps[j].global_position = gx * a.lerp(b, w[2])
		# Smoke is shed on the sand; in the air (spinning, flipping) it would scatter as
		# dark flecks across the sky, so the body keeps it close.
		_wisps[j].emitting = not airborne
		_wisps[j].amount_ratio = clampf(0.35 + _emit * 0.65 + _gather, 0.05, 1.0)
	for i in 2:
		var o := 0 if i == 0 else 3
		var hand := gx * sk.get_bone_global_pose(SpiritModel.HA_L + o)
		_hands[i].global_transform = hand.scaled_local(Vector3.ONE * hand_scale)
		var knee := gx * sk.get_bone_global_pose(SpiritModel.KN_L + o).origin
		var ankle := gx * sk.get_bone_global_pose(SpiritModel.FT_L + o).origin
		_legs[i].global_position = knee.lerp(ankle, 0.8)
		_feet[i].global_position = ankle
		_legs[i].emitting = not airborne
		_legs[i].amount_ratio = clampf(_emit, 0.05, 1.0)
		_feet[i].emitting = not airborne
		_feet[i].amount_ratio = clampf(_emit, 0.05, 1.0)
		_plume[i].global_position = ankle.lerp(knee, 0.3)
		_plume[i].emitting = boost > 0.2 or _arc.length() > 0.3
		# Wisps stream back harder while boosting or following an attack arc.
		(_plume[i].process_material as ParticleProcessMaterial).gravity = Vector3(0, buoyancy, 0) - vel * 0.3 + _arc * 4.0
