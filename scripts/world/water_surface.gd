class_name WaterSurface
extends Node3D
## A still body of water (the Drowned Court): a gently waving disc drawn with
## water.gdshader, and a flat collision body on the ground layer at the water line, so
## the sword surfs over it exactly as over the sand (HoverMotor rays hit it).

const GROUND_LAYER := 1

var level := 0.0
var _mat := ShaderMaterial.new()


func setup(center: Vector3, radius: float) -> void:
	level = center.y
	position = center
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.0, radius * 2.0)
	plane.subdivide_width = 96
	plane.subdivide_depth = 96
	var mi := MeshInstance3D.new()
	mi.name = "Surface"
	mi.mesh = plane
	_mat.shader = load("res://shaders/water.gdshader")
	_mat.set_shader_parameter("normal_a", _ripples(5, 0.02))
	_mat.set_shader_parameter("normal_b", _ripples(9, 0.05))
	# Round: only the basin holds water (a square would fill troughs of the dunes around).
	_mat.set_shader_parameter("center", Vector2(center.x, center.z))
	_mat.set_shader_parameter("radius", radius)
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var body := StaticBody3D.new()
	body.name = "WaterBody"
	body.collision_layer = GROUND_LAYER
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var disc := CylinderShape3D.new()
	disc.radius = radius
	disc.height = 2.0
	cs.shape = disc
	cs.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(cs)
	add_child(body)


static func _ripples(seed: int, freq: float) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = 3
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.as_normal_map = true
	t.bump_strength = 6.0
	t.noise = n
	return t
