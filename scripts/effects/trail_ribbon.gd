class_name TrailRibbon
extends MeshInstance3D
## Camera-facing ribbon that records the path of `source` in world space and
## fades with age. Used for the dodge trail and the board's energy trails.
## `jitter` adds a crackling, lightning-like wobble (boost).

@export var source: Node3D
@export var lifetime := 0.4
@export var width := 0.06
@export var color := Color(0.55, 0.86, 1.0)
@export var intensity := 1.0
@export var jitter := 0.0
@export var min_distance := 0.1
@export var max_points := 64
@export var shader: Shader = preload("res://shaders/energy_trail.gdshader")
## Optional moving frame the trail is recorded in (e.g. the rider): the trail then
## travels with it and only draws the motion relative to it (an arc around her, not a
## long streak across the desert).
@export var space: Node3D

var emitting := false

var _points: Array[Vector3] = []
var _times: Array[float] = []
var _offsets: Array[Vector3] = []
var _time := 0.0
var _imesh := ImmediateMesh.new()
var _material := ShaderMaterial.new()


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	global_transform = Transform3D.IDENTITY
	mesh = _imesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material.shader = shader
	_material.set_shader_parameter("color", color)
	material_override = _material


func clear() -> void:
	_points.clear()
	_times.clear()
	_offsets.clear()
	_imesh.clear_surfaces()


func _process(delta: float) -> void:
	_time += delta
	while not _times.is_empty() and _time - _times[0] > lifetime:
		_points.pop_front()
		_times.pop_front()
		_offsets.pop_front()
	if emitting and source:
		var p := source.global_position
		if space:
			p = space.global_transform.affine_inverse() * p
		if _points.is_empty() or p.distance_to(_points.back()) > min_distance:
			_points.append(p)
			_times.append(_time)
			_offsets.append(Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 2.0)
			if _points.size() > max_points:
				_points.pop_front()
				_times.pop_front()
				_offsets.pop_front()
		else:
			_points[_points.size() - 1] = p
	_rebuild()


func _rebuild() -> void:
	_imesh.clear_surfaces()
	var n := _points.size()
	if n < 2 or intensity <= 0.001:
		return
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam else Vector3.ZERO
	var to_world := space.global_transform if space else Transform3D.IDENTITY
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in n:
		var p := to_world * _points[i]
		var age := clampf((_time - _times[i]) / lifetime, 0.0, 1.0)
		var fade := 1.0 - age
		if jitter > 0.0 and i < n - 1:
			p += _offsets[i] * jitter * (0.3 + age)
		var prev := to_world * _points[maxi(i - 1, 0)]
		var next := to_world * _points[mini(i + 1, n - 1)]
		var dir := (next - prev).normalized()
		var side := dir.cross((cam_pos - p).normalized())
		if side.length_squared() < 0.0001:
			side = Vector3.UP
		side = side.normalized()
		var w := width * (0.3 + 0.7 * fade)
		var head := clampf(float(n - 1 - i) / 2.0, 0.0, 1.0) if n > 3 else 1.0
		var a := fade * fade * intensity * lerpf(0.4, 1.0, head)
		_imesh.surface_set_color(Color(1, 1, 1, a))
		_imesh.surface_set_uv(Vector2(age, 0.0))
		_imesh.surface_add_vertex(p - side * w)
		_imesh.surface_set_color(Color(1, 1, 1, a))
		_imesh.surface_set_uv(Vector2(age, 1.0))
		_imesh.surface_add_vertex(p + side * w)
	_imesh.surface_end()
