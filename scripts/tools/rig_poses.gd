extends SceneTree
## Renders the spirit (with its CharacterRig) in controlled test poses, close up, to
## check the rig itself: neutral, knees bent, elbows bent, a stride. Columns = poses,
## rows = front / side / back.
##   Godot --path . --script res://scripts/tools/rig_poses.gd -- --out=<folder>


var _out := "user://rig_poses"
var _model: SpiritModel
var _cam: Camera3D
var _frame := 0
var _shots: Array = []
var _sheet: Image
var _cell := Vector2i(360, 520)
var _ribbons: Ribbons
var _cloak: Cloak
var _smoke: SmokeBody
var _dark := false
var _no_cloak := false
var _focus := Vector2(0.85, 4.3)   # look-at height, camera distance
var _poses: Array = ["neutral", "knees", "elbows", "stride", "crouch"]


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--poses="):
			_poses = Array(a.substr(8).split(","))
		elif a.begins_with("--focus="):
			var fd := a.substr(8).split(":")
			_focus = Vector2(float(fd[0]), float(fd[1]))
		elif a == "--dark":
			_dark = true
		elif a == "--nocloak":
			_no_cloak = true
		elif a.begins_with("--cell="):
			var wh := a.substr(7).split("x")
			_cell = Vector2i(int(wh[0]), int(wh[1]))
	DirAccess.make_dir_recursive_absolute(_out)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.04, 0.075) if _dark else Color(0.32, 0.27, 0.3)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.85)
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 215, 0)   # lights the front (the model faces -Z)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.04, 0.05, 0.08) if _dark else Color(0.55, 0.42, 0.32)
	floor_mi.material_override = fm
	world.add_child(floor_mi)
	var scene := load("res://scenes/player/player.tscn") as PackedScene
	var player := scene.instantiate()
	# Only the visual model is needed: lift it out of the player.
	var m := player.get_node("Visual/SpiritModel")
	var rib := player.get_node("Visual/Ribbons")
	var clk := player.get_node("Visual/Cloak")
	var smk := player.get_node("Visual/SmokeBody")
	for n in [m, rib, clk, smk]:
		n.get_parent().remove_child(n)
		n.owner = null
		for c in n.get_children():
			c.owner = null
	player.free()
	_model = m as SpiritModel
	world.add_child(_model)
	_ribbons = rib as Ribbons
	world.add_child(_ribbons)
	_ribbons.model = _model
	_cloak = clk as Cloak
	world.add_child(_cloak)
	_cloak.model = _model
	_smoke = smk as SmokeBody
	world.add_child(_smoke)
	_smoke.model = _model
	if _no_cloak:
		_cloak.visible = false
		_ribbons.visible = false
	_cam = Camera3D.new()
	_cam.fov = 30.0
	world.add_child(_cam)
	_cam.current = true
	# The first capture comes out stale: a warm-up shot that the next one overwrites.
	_shots.append([0, 0])
	for p in _poses.size():
		for v in 3:
			_shots.append([p, v])


func _pose(name: String) -> void:
	var sk := _model.skeleton
	sk.reset_bone_poses()
	var r := _model.rest_offsets()
	sk.set_bone_pose_position(SpiritModel.HIPS, r[SpiritModel.HIPS])
	var q := func(b: int, e: Vector3) -> void: sk.set_bone_pose_rotation(b, Quaternion.from_euler(e))
	match name:
		"knees":
			for o in [0, 3]:
				q.call(SpiritModel.TH_L + o, Vector3(0.9, 0, 0))
				q.call(SpiritModel.KN_L + o, Vector3(-1.4, 0, 0))
				q.call(SpiritModel.FT_L + o, Vector3(0.5, 0, 0))
		"elbows":
			q.call(SpiritModel.SH_L, Vector3(0.3, 0, -0.3))
			q.call(SpiritModel.SH_R, Vector3(0.3, 0, 0.3))
			q.call(SpiritModel.EL_L, Vector3(1.5, 0, 0))
			q.call(SpiritModel.EL_R, Vector3(1.5, 0, 0))
		"stride":
			q.call(SpiritModel.TH_L, Vector3(0.7, 0, 0))
			q.call(SpiritModel.KN_L, Vector3(-0.5, 0, 0))
			q.call(SpiritModel.TH_R, Vector3(-0.4, 0, 0))
			q.call(SpiritModel.KN_R, Vector3(-0.9, 0, 0))
			q.call(SpiritModel.SH_L, Vector3(0.6, 0, -0.1))
			q.call(SpiritModel.EL_L, Vector3(0.8, 0, 0))
			q.call(SpiritModel.SH_R, Vector3(-0.6, 0, 0.1))
			q.call(SpiritModel.EL_R, Vector3(0.4, 0, 0))
		"crouch":
			sk.set_bone_pose_position(SpiritModel.HIPS, r[SpiritModel.HIPS] + Vector3(0, -0.3, 0))
			q.call(SpiritModel.SPINE, Vector3(-0.4, 0, 0))
			for o in [0, 3]:
				q.call(SpiritModel.TH_L + o, Vector3(1.2, 0, 0))
				q.call(SpiritModel.KN_L + o, Vector3(-1.9, 0, 0))
				q.call(SpiritModel.FT_L + o, Vector3(0.7, 0, 0))
				q.call(SpiritModel.SH_L + o, Vector3(0.9, 0, 0))
				q.call(SpiritModel.EL_L + o, Vector3(1.0, 0, 0))


func _process(d: float) -> bool:
	_frame += 1
	if _ribbons and _frame > 1:
		_ribbons.step(maxf(d, 0.016))
		_cloak.step(maxf(d, 0.016))
		_smoke.update(maxf(d, 0.016), {})
	if _frame < 3:
		return false
	if _frame % 8 == 0:
		if _shots.is_empty():
			_sheet.save_png(_out + "/poses.png")
			print("[rig_poses] saved ", _out)
			return true
		var s: Array = _shots[0]
		_pose(_poses[s[0]])
		var yaw: float = [0.0, PI * 0.5, PI][s[1]]
		var c := Vector3(0, _focus.x, 0)
		_cam.position = c + Vector3(sin(yaw), 0.05, -cos(yaw)) * _focus.y
		_cam.look_at(c)
		return false
	if _frame % 8 != 7:
		return false
	var s2: Array = _shots.pop_front()
	var img := root.get_texture().get_image()
	var vs := img.get_size()
	var w := int(vs.y * float(_cell.x) / _cell.y)
	img = img.get_region(Rect2i((vs.x - w) / 2, 0, w, vs.y))
	img.resize(_cell.x, _cell.y, Image.INTERPOLATE_LANCZOS)
	if _sheet == null:
		_sheet = Image.create(_cell.x * _poses.size(), _cell.y * 3, false, img.get_format())
	_sheet.blit_rect(img, Rect2i(Vector2i.ZERO, _cell), Vector2i(s2[0] * _cell.x, s2[1] * _cell.y))
	return false
