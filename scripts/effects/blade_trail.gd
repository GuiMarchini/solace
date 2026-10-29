class_name BladeTrail
extends MeshInstance3D
## The swept trail of a sword stroke: every frame the blade's grip and tip positions are
## recorded (in a moving frame, `space`: the rider, so the stroke's arc reads instead of
## a streak across the desert) and drawn as a strip between them that fades with age
## (blade_trail.gdshader: black smoke with an amber edge).

@export var lifetime := 0.3
@export var max_pairs := 48

var space: Node3D
var intensity := 1.0

var _base: Array[Vector3] = []
var _tip: Array[Vector3] = []
var _t: Array[float] = []
var _time := 0.0
var _imesh := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mesh = _imesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/blade_trail.gdshader")
	material_override = m
	custom_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))


## Call every frame with the blade's world points; `on` false lets the trail fade out.
func feed(delta: float, base: Vector3, tip: Vector3, on: bool) -> void:
	_time += delta
	while not _t.is_empty() and _time - _t[0] > lifetime:
		_base.pop_front()
		_tip.pop_front()
		_t.pop_front()
	var to_local := space.global_transform.affine_inverse() if space else Transform3D.IDENTITY
	if on:
		_base.append(to_local * base)
		_tip.append(to_local * tip)
		_t.append(_time)
		if _t.size() > max_pairs:
			_base.pop_front()
			_tip.pop_front()
			_t.pop_front()
	_rebuild()


func _rebuild() -> void:
	_imesh.clear_surfaces()
	var n := _t.size()
	global_transform = space.global_transform if space else Transform3D.IDENTITY
	if n < 2:
		return
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(n - 1, -1, -1):
		var age := clampf((_time - _t[i]) / lifetime, 0.0, 1.0)
		_imesh.surface_set_color(Color(1, 1, 1, intensity))
		_imesh.surface_set_uv(Vector2(age, 0.0))
		_imesh.surface_add_vertex(_base[i])
		_imesh.surface_set_color(Color(1, 1, 1, intensity))
		_imesh.surface_set_uv(Vector2(age, 1.0))
		_imesh.surface_add_vertex(_tip[i])
	_imesh.surface_end()
