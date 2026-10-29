class_name SandTrail
extends MeshInstance3D
## The groove the board carves into the sand: a flat strip laid on the ground along the
## board's path that darkens the sand (multiply blend, so it works on any lighting) with
## slightly bright raised rims, and fades over a few seconds.

@export var width := 0.34
@export var lifetime := 5.0
@export var spacing := 0.3
@export var max_points := 160

var _pts: Array[Vector3] = []
var _nrm: Array[Vector3] = []
var _t: Array[float] = []
var _time := 0.0
var _imesh := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	global_transform = Transform3D.IDENTITY
	mesh = _imesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/sand_trail.gdshader")
	material_override = m


## Call every frame; `on_sand` false breaks the trail (airborne or far from the ground).
func feed(delta: float, ground_point: Vector3, ground_normal: Vector3, on_sand: bool) -> void:
	_time += delta
	while not _t.is_empty() and _time - _t[0] > lifetime:
		_pts.pop_front()
		_nrm.pop_front()
		_t.pop_front()
	if on_sand:
		if _pts.is_empty() or _pts.back().distance_to(ground_point) > spacing:
			if not _pts.is_empty() and _pts.back().distance_to(ground_point) > spacing * 6.0:
				# Gap (landing after a jump): start a fresh segment.
				_pts.append(Vector3.INF)
				_nrm.append(Vector3.UP)
				_t.append(_time)
			_pts.append(ground_point)
			_nrm.append(ground_normal)
			_t.append(_time)
			if _pts.size() > max_points:
				_pts.pop_front()
				_nrm.pop_front()
				_t.pop_front()
	elif not _pts.is_empty() and _pts.back() != Vector3.INF:
		_pts.append(Vector3.INF)
		_nrm.append(Vector3.UP)
		_t.append(_time)
	_rebuild()


func clear() -> void:
	_pts.clear()
	_nrm.clear()
	_t.clear()
	_imesh.clear_surfaces()


func _rebuild() -> void:
	_imesh.clear_surfaces()
	var n := _pts.size()
	if n < 2:
		return
	var open := false
	for i in n:
		var p := _pts[i]
		if p == Vector3.INF:
			if open:
				_imesh.surface_end()
				open = false
			continue
		var prev := _pts[i - 1] if i > 0 and _pts[i - 1] != Vector3.INF else p
		var next := _pts[i + 1] if i < n - 1 and _pts[i + 1] != Vector3.INF else p
		var dir := next - prev
		if dir.length_squared() < 0.000001:
			continue
		var side := dir.cross(_nrm[i]).normalized()
		var age := clampf((_time - _t[i]) / lifetime, 0.0, 1.0)
		var a := (1.0 - age) * (1.0 - age)
		var w := width * (0.6 + 0.4 * (1.0 - age))
		var lift := _nrm[i] * 0.02
		if not open:
			_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
			open = true
		_imesh.surface_set_color(Color(1, 1, 1, a))
		_imesh.surface_set_uv(Vector2(age, 0.0))
		_imesh.surface_add_vertex(p - side * w + lift)
		_imesh.surface_set_color(Color(1, 1, 1, a))
		_imesh.surface_set_uv(Vector2(age, 1.0))
		_imesh.surface_add_vertex(p + side * w + lift)
	if open:
		_imesh.surface_end()
