class_name PlayerFX
extends Node3D
## Effects attached to the spirit: drifting aura motes, running dust, landing and
## jump puffs, the dash trail/afterimages, sand brushed up by the hand in a sharp turn,
## a sand slide after hard landings, motes gathering during the idle gesture, the
## substance stream of the hoverboard transformation, and the rest puff.
## All emitters and afterimage ghosts are created once and reused.

@export var particle_intensity := 1.0
@export var aura_color := Color(1.0, 0.55, 0.22, 0.55)
@export var dust_color := Color(0.92, 0.72, 0.52, 0.3)
@export_group("Dash")
@export var afterimage_count := 3
@export var afterimage_interval := 0.055
@export var afterimage_fade := 0.28
@export var afterimage_color := Color(0.55, 0.82, 1.0)

var _aura: GPUParticles3D
var _run_dust: GPUParticles3D
var _land_dust: GPUParticles3D
var _land_motes: GPUParticles3D
var _dash_burst: GPUParticles3D
var _hand_sand: GPUParticles3D
var _slide_spray: GPUParticles3D
var _gather: GPUParticles3D
var _stream_down: GPUParticles3D
var _stream_up: GPUParticles3D
var _dodge_trail: TrailRibbon
var _hand_trail: TrailRibbon
var _hand_anchor: Node3D
var _dodge_trail_timer := 0.0
var _stream_timer := 0.0
var _stream_dir := 1.0
var _slide_timer := 0.0
var _ghosts: Array[Skeleton3D] = []
var _ghost_mats: Array[ShaderMaterial] = []
var _ghost_life: Array[float] = []
var _ghost_queue := 0
var _ghost_timer := 0.0
var _model: SpiritModel


func setup(model: SpiritModel) -> void:
	_model = model
	_aura = Fx.particles({"amount": 20, "lifetime": 2.4, "size": 0.028, "shape": "box",
		"extents": Vector3(0.11, 0.32, 0.08), "direction": Vector3.UP, "spread": 60.0,
		"velocity": Vector2(0.05, 0.2), "gravity": Vector3(0, 0.16, 0), "damping": 0.3,
		"color": aura_color, "turbulence": true})
	model.chest.add_child(_aura)
	_aura.position = Vector3(0.0, -0.12, 0.0)
	# The smoke body carries its own faint embers; the old floating aura stays off.
	_aura.emitting = false

	_run_dust = Fx.particles({"amount": 30, "lifetime": 0.9, "size": 0.26, "kind": "dust",
		"shape": "box", "extents": Vector3(0.12, 0.02, 0.12), "direction": Vector3(0, 1, 0.5),
		"spread": 40.0, "velocity": Vector2(0.4, 1.2), "gravity": Vector3(0, -0.4, 0),
		"damping": 1.2, "scale": Vector2(0.5, 1.1), "grow": true, "color": dust_color})
	add_child(_run_dust)

	_land_dust = Fx.particles({"amount": 26, "lifetime": 1.1, "size": 0.4, "kind": "dust",
		"one_shot": true, "explosiveness": 0.95, "shape": "ring", "radius": 0.25,
		"direction": Vector3.UP, "spread": 85.0, "flatness": 0.7, "velocity": Vector2(0.8, 2.4),
		"gravity": Vector3(0, -0.8, 0), "damping": 2.0, "scale": Vector2(0.6, 1.2), "grow": true,
		"color": dust_color})
	add_child(_land_dust)

	_land_motes = Fx.particles({"amount": 14, "lifetime": 0.9, "size": 0.025, "one_shot": true,
		"explosiveness": 0.9, "shape": "ring", "radius": 0.2, "direction": Vector3.UP,
		"spread": 50.0, "velocity": Vector2(0.6, 1.6), "gravity": Vector3(0, 0.3, 0),
		"color": aura_color})
	add_child(_land_motes)

	_dash_burst = Fx.particles({"amount": 28, "lifetime": 0.5, "size": 0.03, "one_shot": true,
		"explosiveness": 0.9, "shape": "sphere", "radius": 0.22, "direction": Vector3.UP,
		"spread": 180.0, "velocity": Vector2(0.8, 2.2), "damping": 3.0, "color": aura_color})
	add_child(_dash_burst)

	# Sand flicked up by the hand brushing the dune in a sharp turn.
	_hand_sand = Fx.particles({"amount": 40, "lifetime": 0.8, "size": 0.16, "kind": "dust",
		"shape": "sphere", "radius": 0.05, "direction": Vector3(0, 1, 0.3), "spread": 55.0,
		"velocity": Vector2(0.6, 2.0), "gravity": Vector3(0, -2.5, 0), "damping": 1.0,
		"scale": Vector2(0.4, 1.0), "grow": true, "color": Color(0.94, 0.75, 0.55, 0.45)})
	add_child(_hand_sand)
	_hand_anchor = Node3D.new()
	add_child(_hand_anchor)
	_hand_anchor.top_level = true
	_hand_trail = TrailRibbon.new()
	_hand_trail.source = _hand_anchor
	_hand_trail.width = 0.04
	_hand_trail.lifetime = 0.45
	_hand_trail.intensity = 0.7
	add_child(_hand_trail)

	# Low slide after a hard landing at speed.
	_slide_spray = Fx.particles({"amount": 50, "lifetime": 0.9, "size": 0.3, "kind": "dust",
		"shape": "box", "extents": Vector3(0.18, 0.02, 0.1), "direction": Vector3(0, 1, 0.8),
		"spread": 40.0, "velocity": Vector2(1.0, 2.6), "gravity": Vector3(0, -1.5, 0),
		"damping": 1.5, "scale": Vector2(0.5, 1.2), "grow": true, "color": Color(0.93, 0.74, 0.55, 0.4)})
	add_child(_slide_spray)

	# Motes drawn toward the raised hand during the idle gesture.
	_gather = Fx.particles({"amount": 26, "lifetime": 1.2, "size": 0.025, "shape": "sphere",
		"radius": 0.3, "direction": Vector3.UP, "spread": 180.0, "velocity": Vector2(0.0, 0.05),
		"radial": Vector2(-0.35, -0.2), "damping": 0.2, "color": Color(1.0, 0.6, 0.28, 0.85)})
	add_child(_gather)

	# Substance flowing down into the board (summon) and back up into the body (dismiss).
	_stream_down = Fx.particles({"amount": 60, "lifetime": 0.35, "size": 0.03, "shape": "box",
		"extents": Vector3(0.1, 0.3, 0.07), "direction": Vector3.DOWN, "spread": 12.0,
		"velocity": Vector2(1.6, 3.0), "damping": 0.5, "color": Color(1.0, 0.6, 0.28, 0.85)})
	_stream_down.position = Vector3(0.0, 0.45, 0.0)
	add_child(_stream_down)
	_stream_up = Fx.particles({"amount": 60, "lifetime": 0.4, "size": 0.03, "shape": "box",
		"extents": Vector3(0.3, 0.03, 0.1), "direction": Vector3.UP, "spread": 12.0,
		"velocity": Vector2(1.6, 2.8), "damping": 0.5, "color": Color(1.0, 0.6, 0.28, 0.85)})
	add_child(_stream_up)

	var trail_anchor := Node3D.new()
	model.chest.add_child(trail_anchor)
	_dodge_trail = TrailRibbon.new()
	_dodge_trail.source = trail_anchor
	_dodge_trail.width = 0.18
	_dodge_trail.lifetime = 0.3
	_dodge_trail.intensity = 0.9
	add_child(_dodge_trail)

	_build_ghosts(model)


## Afterimages are duplicates of the skinned body that receive a copy of the pose.
func _build_ghosts(model: SpiritModel) -> void:
	var shader := load("res://shaders/afterimage.gdshader")
	for i in afterimage_count:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("color", afterimage_color)
		var ghost := model.skeleton.duplicate() as Skeleton3D
		for child in ghost.get_children():
			var mi := child as MeshInstance3D
			if mi:
				mi.material_override = mat
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost.top_level = true
		ghost.visible = false
		add_child(ghost)
		_ghosts.append(ghost)
		_ghost_mats.append(mat)
		_ghost_life.append(0.0)


func update(delta: float, running_on_sand: float, airborne: bool, riding: bool, ctx: MotionContext, model: SpiritModel) -> void:
	_run_dust.emitting = running_on_sand > 0.05 and not airborne and not riding and ctx.land_low < 0.1
	_run_dust.amount_ratio = clampf(running_on_sand * particle_intensity, 0.05, 1.0)
	_run_dust.global_position = global_position + Vector3.UP * 0.04
	_dodge_trail_timer -= delta
	_dodge_trail.emitting = _dodge_trail_timer > 0.0
	_aura.amount_ratio = clampf(particle_intensity * (1.0 + ctx.gesture), 0.05, 1.0)

	# Hand brushing the sand.
	var hand := model.hand_world[0 if ctx.sand_side < 0.0 else 1]
	_hand_anchor.global_position = hand
	var brushing := ctx.sand_touch > 0.45
	_hand_sand.global_position = hand
	_hand_sand.emitting = brushing
	_hand_trail.emitting = brushing

	_slide_timer -= delta
	_slide_spray.emitting = _slide_timer > 0.0 and ctx.land_low > 0.2
	_slide_spray.global_position = global_position + Vector3.UP * 0.04

	_gather.emitting = ctx.gesture > 0.4
	_gather.global_position = model.hand_world[0 if ctx.gesture_side < 0.0 else 1]

	_stream_timer -= delta
	_stream_down.emitting = _stream_timer > 0.0 and _stream_dir > 0.0
	_stream_up.emitting = _stream_timer > 0.0 and _stream_dir < 0.0

	if _ghost_queue > 0:
		_ghost_timer -= delta
		if _ghost_timer <= 0.0:
			_spawn_ghost()
			_ghost_queue -= 1
			_ghost_timer = afterimage_interval
	for i in _ghosts.size():
		if _ghost_life[i] > 0.0:
			_ghost_life[i] -= delta
			var a := clampf(_ghost_life[i] / afterimage_fade, 0.0, 1.0)
			_ghost_mats[i].set_shader_parameter("alpha", a * a * 0.8)
			if _ghost_life[i] <= 0.0:
				_ghosts[i].visible = false


func _spawn_ghost() -> void:
	var idx := 0
	for i in _ghosts.size():
		if _ghost_life[i] < _ghost_life[idx]:
			idx = i
	var ghost := _ghosts[idx]
	var src := _model.skeleton
	ghost.global_transform = src.global_transform
	for b in src.get_bone_count():
		ghost.set_bone_pose_position(b, src.get_bone_pose_position(b))
		ghost.set_bone_pose_rotation(b, src.get_bone_pose_rotation(b))
	ghost.visible = true
	_ghost_life[idx] = afterimage_fade


func on_landed(impact: float) -> void:
	if impact < 2.5:
		return
	var r := clampf(impact / 14.0, 0.2, 1.0) * particle_intensity
	Fx.burst(_land_dust, global_position + Vector3.UP * 0.04, r)
	Fx.burst(_land_motes, global_position + Vector3.UP * 0.08, r)


func on_jump() -> void:
	Fx.burst(_land_dust, global_position + Vector3.UP * 0.04, 0.3 * particle_intensity)


func on_dodge(model: SpiritModel) -> void:
	_dodge_trail.clear()
	_dodge_trail_timer = 0.24
	Fx.burst(_dash_burst, model.chest.global_position, particle_intensity)
	_ghost_queue = afterimage_count
	_ghost_timer = 0.02


func on_sand_touch() -> void:
	_hand_trail.clear()


func on_landing_slide() -> void:
	_slide_timer = 0.55


func on_gesture(_side: float) -> void:
	pass


func on_sat_down() -> void:
	Fx.burst(_land_dust, global_position + Vector3.UP * 0.03, 0.25 * particle_intensity)


## The hoverboard transformation: substance streams down into the board, or back up.
func on_transform(to_board: bool) -> void:
	_stream_dir = 1.0 if to_board else -1.0
	_stream_timer = 0.4
	_stream_up.global_position = global_position + Vector3.UP * 0.05
	Fx.burst(_land_motes, global_position + Vector3.UP * 0.1, 0.6 * particle_intensity)
