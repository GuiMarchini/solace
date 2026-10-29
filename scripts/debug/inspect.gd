extends Node
## Character inspection: renders contact sheets of the idle pose from four angles and
## of one walk / run / sprint cycle (8 evenly spaced frames, close side view).
## Run:  Godot --path . -- --inspect --out=<folder>

var _player: PlayerController
var _cam: FollowCamera
var _out := "user://inspect"
var _t := 0.0
var _travel := Vector3.FORWARD
var _sheet: Image
var _cell := Vector2i(400, 450)
var _queue: Array = []   # [time, sheet name, cell index, yaw offset, pitch, zoom, gait]
var _sheets := {}


func _ready() -> void:
	process_physics_priority = -100
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	_player = get_parent().get_node("Player")
	_cam = get_parent().get_node("CameraRig")
	_player.enable_foot()
	(_player.get_node("Visual/MotionContext") as MotionContext).enabled = false
	get_parent().get_node("UI").visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_travel = _player.facing_direction()
	var angles := [0.0, PI * 0.5, PI, PI * 1.5]
	for i in 4:
		_queue.append([2.0 + i * 0.25, "idle", i, angles[i] + PI, -2.0, 1.7, ""])
	for gait in ["walk", "run", "sprint"]:
		var start: float = {"walk": 5.0, "run": 8.0, "sprint": 11.5}[gait]
		var speed: float = {"walk": 1.3, "run": 4.5, "sprint": 6.5}[gait]
		var m: SpiritModel = _player.get_node("Visual/SpiritModel")
		var period := m.cycle_period(speed)
		for i in 8:
			_queue.append([start + period * i / 8.0, gait, i, PI * 0.5, -2.0, 2.2, gait])
		for i in 4:
			_queue.append([start + 0.6 + period * i / 4.0, gait + "_front", i, PI, -2.0, 2.2, gait])


func _gait_at(t: float) -> String:
	if t > 4.0 and t < 6.6:
		return "walk"
	if t >= 6.6 and t < 9.6:
		return "run"
	if t >= 9.6 and t < 13.2:
		return "sprint"
	return ""


func _physics_process(delta: float) -> void:
	_t += delta
	var gait := _gait_at(_t)
	if gait != "":
		_steer(_travel)
	else:
		for a in [&"move_right", &"move_left", &"move_back", &"move_forward"]:
			Input.action_release(a)
	if gait == "walk":
		Input.action_press(&"walk")
	else:
		Input.action_release(&"walk")
	if gait == "sprint":
		Input.action_press(&"run")
	else:
		Input.action_release(&"run")
	if _queue.is_empty():
		for k in _sheets:
			var img: Image = _sheets[k]
			img.save_png("%s/%s.png" % [_out, k])
			print("[inspect] saved ", k)
		get_tree().quit()
		return
	var q: Array = _queue[0]
	var hv := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	var dir := hv.normalized() if hv.length() > 1.0 else _player.facing_direction()
	if _t >= float(q[0]) - 0.35:
		_cam.yaw = atan2(-dir.x, -dir.z) + float(q[3])
		_cam.pitch = deg_to_rad(q[4])
		_cam._zoom = q[5]
		_cam._idle_look = -10.0
	if _t >= float(q[0]):
		_queue.pop_front()
		var shot := get_viewport().get_texture().get_image()
		var sz := shot.get_size()
		var crop := shot.get_region(Rect2i(sz.x / 2 - 320, sz.y / 2 - 360, 640, 720))
		crop.resize(_cell.x, _cell.y, Image.INTERPOLATE_LANCZOS)
		var name: String = q[1]
		var cols := 4 if (name == "idle" or name.ends_with("_front")) else 8
		if not _sheets.has(name):
			var sheet := Image.create(_cell.x * cols, _cell.y, false, crop.get_format())
			_sheets[name] = sheet
		(_sheets[name] as Image).blit_rect(crop, Rect2i(Vector2i.ZERO, _cell), Vector2i(_cell.x * int(q[2]), 0))


func _steer(dir: Vector3) -> void:
	var local := Basis(Vector3.UP, _cam.yaw).inverse() * dir
	_axis(&"move_right", local.x)
	_axis(&"move_left", -local.x)
	_axis(&"move_back", local.z)
	_axis(&"move_forward", -local.z)


func _axis(action: StringName, v: float) -> void:
	if v > 0.01:
		Input.action_press(action, v)
	else:
		Input.action_release(action)
