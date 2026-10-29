class_name Shockwave
extends MeshInstance3D
## A shockwave rolling out over the sand from an impact (shockwave.gdshader on a quad
## laid on the ground). Reusable: play() restarts it.

var _mat := ShaderMaterial.new()
var _t := 1.0
var _dur := 0.7


func _ready() -> void:
	top_level = true
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	q.orientation = PlaneMesh.FACE_Y
	mesh = q
	_mat.shader = load("res://shaders/shockwave.gdshader")
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


## Starts a wave at `at` on ground with normal `n`, spreading to `radius` (m).
func play(at: Vector3, n: Vector3, radius: float, duration: float, strength := 1.0) -> void:
	var x := n.cross(Vector3.FORWARD)
	if x.length_squared() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var b := Basis(x, n, x.cross(n)).orthonormalized().scaled(Vector3(radius, 1.0, radius))
	global_transform = Transform3D(b, at + n * 0.06)
	_dur = duration
	_t = 0.0
	_mat.set_shader_parameter("strength", strength)
	visible = true


func _process(delta: float) -> void:
	if _t >= 1.0:
		return
	_t = minf(_t + delta / _dur, 1.0)
	_mat.set_shader_parameter("progress", _t)
	if _t >= 1.0:
		visible = false
