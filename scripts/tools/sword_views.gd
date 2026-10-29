extends SceneTree
## Renders the spirit's sword (the Hoverboard scene, materialized) in a neutral studio,
## from the views of its concept sheet: front (its flat, the rider's side), a 3/4 hero
## view, side, base (underside) and a close-up of the guard and the rune circle.
##   Godot --path . --script res://scripts/tools/sword_views.gd -- --out=<folder>

var _out := "user://sword_views"
var _board: Hoverboard
var _cam: Camera3D
var _frame := 0
var _sheet: Image
var _cell := Vector2i(420, 760)
# [name, camera position, look-at, up, fov]
var _views := [
	["front", Vector3(0.0, 4.6, -0.08), Vector3(0.0, 0.0, -0.08), Vector3(0, 0, 1), 30.0],
	["hero", Vector3(2.6, 2.5, -2.4), Vector3(0.0, -0.03, -0.1), Vector3.UP, 34.0],
	["side", Vector3(4.6, 0.05, -0.08), Vector3(0.0, -0.03, -0.08), Vector3(0, 0, 1), 30.0],
	["base", Vector3(0.0, -4.6, -0.08), Vector3(0.0, 0.0, -0.08), Vector3(0, 0, 1), 30.0],
	["guard", Vector3(0.55, 0.75, 0.05), Vector3(0.0, -0.02, 0.55), Vector3.UP, 30.0],
]
var _queue: Array = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.36, 0.31, 0.3)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.78, 0.75)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.glow_enabled = true
	e.glow_intensity = 0.6
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.92, 0.84)
	sun.shadow_enabled = true
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(50, -140, 0)
	fill.light_energy = 0.35
	world.add_child(fill)
	_board = (load("res://scenes/hoverboard/hoverboard.tscn") as PackedScene).instantiate() as Hoverboard
	world.add_child(_board)
	_cam = Camera3D.new()
	world.add_child(_cam)
	_cam.current = true
	# The first capture comes out stale: a warm-up shot that the next one overwrites.
	_queue.append(0)
	for i in _views.size():
		_queue.append(i)


func _process(d: float) -> bool:
	_frame += 1
	if _frame == 2:
		_board.active = true
		_board.visible = true
		_board.materialize = 1.0
		_board._set_materialize(1.0)
		_board._motes.visible = false
	if _frame >= 2:
		_board.update_effects(maxf(d, 0.016), 0.0, 0.0, false, Vector3(0, -1.0, 0), 1.0, 0.0)
	if _frame < 20:
		return false
	if _frame % 8 == 0:
		if _queue.is_empty():
			_sheet.save_png(_out + "/sword.png")
			print("[sword_views] saved ", _out)
			return true
		var v: Array = _views[_queue[0]]
		_cam.fov = v[4]
		_cam.position = v[1]
		_cam.look_at(v[2], v[3])
		return false
	if _frame % 8 != 7:
		return false
	var i: int = _queue.pop_front()
	var img := root.get_texture().get_image()
	var vs := img.get_size()
	var w := int(vs.y * float(_cell.x) / _cell.y)
	img = img.get_region(Rect2i((vs.x - w) / 2, 0, w, vs.y))
	img.resize(_cell.x, _cell.y, Image.INTERPOLATE_LANCZOS)
	if _sheet == null:
		_sheet = Image.create(_cell.x * _views.size(), _cell.y, false, img.get_format())
	_sheet.blit_rect(img, Rect2i(Vector2i.ZERO, _cell), Vector2i(i * _cell.x, 0))
	return false
