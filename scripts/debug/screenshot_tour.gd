extends Node
## Visual check: plays a scripted sword-riding sequence in a real window and saves
## screenshots (mount, cruise, carves, boost, drift, charged jump, air, landing).
## Steering is board-relative like the player's: forward pumps, left/right carve.
## Run:  Godot --path . -- --tour --out=<folder>

var _player: PlayerController
var _cam: FollowCamera
var _ctx: MotionContext
var _out := "user://shots"
var _t := 0.0
var _next := 0
## Multiplies every shot's camera distance (e.g. --zoom=0.5 for close-ups).
var _zoom_mul := 1.0
## Optional burst capture: frames every `_burst.z` seconds between `_burst.x` and `_burst.y`
## (--burst=start:end:interval), seen from `_burst_yaw` (rad from travel), for contact
## sheets of the animation. Regular shots are skipped while a burst is set.
var _burst := Vector3.ZERO
var _burst_yaw := PI * 0.5
## Height of the burst camera above her feet (m), --burst_up=.
var _burst_up := 1.3
## --burst_cam=game: capture through the gameplay camera itself.
var _burst_game_cam := false
var _burst_next := 0.0
var _burst_i := 0
## Nodes under Player/Visual to hide (--hide=Cloak,Ribbons), for diagnosis.
var _hide := PackedStringArray()
## --jumps: a jump-heavy run (taps, charged jumps, back-to-back, boosted) to check the
## air moves; --combos also presses Q / E on a schedule (deck tricks, QE, EQ, EE, QQ,
## queued tricks) and prints what was played and scored.
var _jumps := false
var _combos := false
## --combat: sentinels appear ahead and attacks are pressed on a schedule (slash chains,
## spin, dash, breaker, the Last Spirit); logs attacks, hits, sword states and checks
## that the sword never stays stuck in her hand.
var _combat := false
# [time, what, arg]: "spawn" (metres ahead, metres to the right), an attack, "energy", "jump".
var _combat_plan := [[4.9, "spawn", Vector2(17, 0)], [5.55, "light", null], [5.9, "light", null],
	[6.25, "light", null], [6.75, "light", null],
	[7.7, "spawn", Vector2(9, -2.2)], [7.7, "spawn", Vector2(9.5, 2.2)], [8.2, "spin", null],
	[8.8, "spawn", Vector2(16, 0)], [9.1, "dash", null],
	[10.3, "spawn", Vector2(12, 0)], [10.45, "heavy", null],
	[13.1, "spawn", Vector2(9, 0)], [13.6, "light", null], [13.85, "spin", null],
	[15.3, "spawn", Vector2(12, 0)], [15.6, "dash", null], [16.05, "light", null],
	[17.4, "energy", null], [17.4, "spawn", Vector2(13, -3)], [17.4, "spawn", Vector2(14, 3)], [17.5, "special", null]]
var _combat_next := 0
var _stuck_time := 0.0
var _max_stuck := 0.0
## --start=x,z,yaw: begin the run there (e.g. inside a patch of loose sand).
var _start := Vector3.INF
## --sandtest: before setting off, a hard-landing burst of sand at her feet (to watch
## the grains fall and settle); the ride starts at 5 s.
var _sandtest := false
# [time, button]
var _press_plan := [[5.6, "Q"], [8.2, "Q"], [8.3, "E"], [9.15, "E"], [10.7, "E"], [10.8, "Q"],
	[12.95, "Q"], [14.85, "E"], [14.95, "E"], [17.25, "Q"], [17.55, "E"], [19.65, "Q"], [19.75, "Q"]]
var _press_next := 0
# [press time, hold seconds]
var _jump_plan := [[5.0, 0.05], [7.5, 0.6], [10.0, 0.6], [12.6, 0.3], [14.2, 0.6], [16.6, 0.6], [19.0, 0.6]]

# [time, name, camera yaw offset from travel (rad, 0 = gameplay view from behind), pitch deg, zoom]
var _shots := [
	[1.45, "01_summon", PI * 0.7, -10.0, 2.6],
	[2.5, "02_mounted", PI * 0.8, -6.0, 2.4],
	[5.5, "03_cruise_behind", 0.0, -8.0, 1.0],
	[7.0, "04_cruise_side", PI * 0.5, -5.0, 3.0],
	[9.2, "05_carve_left", PI * 0.3, -8.0, 2.8],
	[11.4, "06_carve_right", -PI * 0.3, -8.0, 2.8],
	[13.6, "07_boost_behind", 0.0, -8.0, 1.0],
	[15.6, "08_drift", PI * 0.75, -12.0, 3.6],
	[17.7, "09_charge", PI * 0.6, -6.0, 3.0],
	[18.5, "10_air", PI * 0.55, -4.0, 4.0],
	[20.4, "11_landed", 0.0, -8.0, 1.0],
	[23.0, "12_vista", 0.0, -4.0, 6.0],
]


func _ready() -> void:
	process_physics_priority = -100
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--zoom="):
			_zoom_mul = float(a.substr(7))
		elif a.begins_with("--burst="):
			var b := a.substr(8).split(":")
			_burst = Vector3(float(b[0]), float(b[1]), float(b[2]))
			_burst_next = _burst.x
		elif a == "--burst_cam=game":
			_burst_game_cam = true
		elif a.begins_with("--burst_up="):
			_burst_up = float(a.substr(11))
		elif a.begins_with("--burst_yaw="):
			_burst_yaw = deg_to_rad(float(a.substr(12)))
		elif a.begins_with("--hide="):
			_hide = a.substr(7).split(",")
		elif a == "--jumps":
			_jumps = true
		elif a.begins_with("--start="):
			var v := a.substr(8).split(",")
			_start = Vector3(float(v[0]), float(v[1]), float(v[2]))
		elif a == "--sandtest":
			_sandtest = true
		elif a == "--combat":
			_combat = true
		elif a == "--combos":
			_jumps = true
			_combos = true
	DirAccess.make_dir_recursive_absolute(_out)
	_player = get_parent().get_node("Player")
	_cam = get_parent().get_node("CameraRig")
	_ctx = _player.get_node("Visual/MotionContext")
	_ctx.force_variations = true
	if _start != Vector3.INF:
		_player.place_on_ground(Vector3(_start.x, 0.0, _start.y))
		_player.facing_yaw = _start.z
		_cam.snap()
	for n in _hide:
		var node := _player.get_node_or_null("Visual/" + n) as Node3D
		if node:
			node.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _combat:
		var cd: CombatDirector = _player.get_node("Visual").combat
		cd.attack_started.connect(func(k: String) -> void: print("[tour] %.2f  attack %s" % [_t, k]))
		cd.hit_landed.connect(func(_t2: Node3D, heavy: bool, n: int) -> void:
			print("[tour] %.2f  HIT %s combo %d" % [_t, "heavy" if heavy else "light", n]))
		cd.impact.connect(func(p: Vector3, st: float) -> void:
			var best := 999.0
			for t in get_tree().get_nodes_in_group(&"spirit_targets"):
				best = minf(best, (t as SpiritTarget).hurt_center().distance_to(p))
			print("[tour] %.2f  impact %.1f nearest sentinel %.1f m  player %s" % [_t, st, best, _player.global_position.snapped(Vector3.ONE)]))
		cd.attack_started.connect(func(_k: String) -> void:
			var best := 999.0
			for t in get_tree().get_nodes_in_group(&"spirit_targets"):
				if (t as SpiritTarget).alive:
					best = minf(best, (t as SpiritTarget).hurt_center().distance_to(_player.global_position))
			print("[tour]        nearest live sentinel %.1f m" % best))
		cd.state_changed.connect(func(st: int) -> void: print("[tour] %.2f    sword %s" % [_t, CombatDirector.STATE_NAMES[st]]))
		cd.combo_ended.connect(func(n: int, sty: float) -> void: print("[tour] %.2f  combo ended %d hits x%.2f" % [_t, n, sty]))
	if _jumps:
		var td: TrickDirector = _player.get_node("Visual").tricks
		td.move_started.connect(func(m: String, _title: String, by_player: bool) -> void:
			print("[tour] %.2f  %s %s" % [_t, m, "(player)" if by_player else "(auto)"]))
		td.landed.connect(func(clean: bool, had: bool) -> void:
			if had:
				print("[tour] %.2f  landed %s" % [_t, "clean" if clean else "sketchy"]))
		_player.hover.charge_ready.connect(func() -> void: print("[tour] %.2f  jump charged (magic chime)" % _t))
		td.combo.lost.connect(func() -> void: print("[tour] %.2f  combo lost" % _t))
		td.bailed.connect(func() -> void: print("[tour] %.2f  BAIL" % _t))
		td.combo.banked.connect(func(total: int, m: float) -> void:
			print("[tour] %.2f  combo banked %d (x%.1f)" % [_t, total, m]))
	# Measure the real frame cost, not the monitor's refresh rate.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func _exit_tree() -> void:
	var td: TrickDirector = get_parent().get_node("Player/Visual").tricks
	print("[tour] moves played: ", td.played)
	if _combat:
		var cd: CombatDirector = get_parent().get_node("Player/Visual").combat
		print("[tour] combat: attacks %s, hits %d, best combo %d, longest time with the sword in hand outside an attack %.2f s" % [
			cd.started, cd.total_hits, cd.best_combo, _max_stuck])
	print("[tour] combo score banked: ", td.combo.total_score)
	print("[tour] fluidity: fastest body turn %.1f rad/s, fastest pose change %.1f /s" % [td.max_body_rate, td.max_pose_rate])


func _hold(action: StringName, on: bool, strength: float = 1.0) -> void:
	if on:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _physics_process(delta: float) -> void:
	var t0 := _t
	_t += delta
	var moving := _t > (5.0 if _sandtest else 3.0) and _t < 22.0
	if _sandtest and t0 < 2.6 and _t >= 2.6:
		var board: Hoverboard = _player.get_node("Visual/Hoverboard")
		# Grains live longer in this test so their resting on the sand can be seen.
		for b in board._sand._bursts:
			b.lifetime = 4.0
		board.on_land(14.0, _player.hover.ground_point)
	_hold(&"move_forward", moving)
	_hold(&"move_left", ((_t > 8.0 and _t < 9.6) or (_t > 14.6 and _t < 15.8)) and not _combat)
	_hold(&"move_right", _t > 10.2 and _t < 11.8 and not _combat)
	_hold(&"move_back", false)
	_hold(&"run", _t > 12.4 and _t < 15.0)
	if _combat:
		_combat_tick(delta)
	if _combos and _press_next < _press_plan.size() and _t >= float(_press_plan[_press_next][0]):
		var td: TrickDirector = get_parent().get_node("Player/Visual").tricks
		td.input.press(_press_plan[_press_next][1])
		_press_next += 1
	if _jumps:
		var held := false
		for j in _jump_plan:
			if _t > j[0] and _t < j[0] + j[1]:
				held = true
		_hold(&"jump", held)
	else:
		# Charged jump: hold, then release.
		_hold(&"jump", _t > 17.0 and _t < 17.8 and not _combat)
		if t0 < 17.8 and _t >= 17.8:
			Input.action_release(&"jump")

	if _burst != Vector3.ZERO:
		_burst_capture()
		return
	if _next < _shots.size():
		var shot: Array = _shots[_next]
		var hv := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
		var dir := hv.normalized() if hv.length() > 1.0 else _player.facing_direction()
		if _t >= float(shot[0]) - 0.5:
			_cam.yaw = atan2(-dir.x, -dir.z) + float(shot[2])
			_cam.pitch = deg_to_rad(shot[3])
			_cam._zoom = float(shot[4]) * _zoom_mul
			_cam._idle_look = -10.0
		if _t >= float(shot[0]):
			var img := get_viewport().get_texture().get_image()
			img.save_png("%s/%s.png" % [_out, shot[1]])
			print("[tour] %s  fps %d  frame %.1f ms  mode %s  speed %.1f  air %.2f  drift %.2f" % [
				shot[1], Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				PlayerController.Mode.keys()[_player.mode],
				_player.horizontal_speed(), _player.hover.air_time, _player.hover.drift_amount])
			_next += 1
			if _next >= _shots.size():
				get_tree().quit()


func _combat_tick(delta: float) -> void:
	var cd: CombatDirector = _player.get_node("Visual").combat
	while _combat_next < _combat_plan.size() and _t >= float(_combat_plan[_combat_next][0]):
		var e: Array = _combat_plan[_combat_next]
		_combat_next += 1
		match String(e[1]):
			"spawn":
				var hv := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
				var fwd := hv.normalized() if hv.length() > 1.0 else _player.facing_direction()
				var right := fwd.cross(Vector3.UP)
				var off: Vector2 = e[2]
				var st := SpiritTarget.spawn(get_parent(), _player.global_position + fwd * off.x + right * off.y)
				print("[tour] %.2f  spawn at %s (player %s)" % [_t, st.hurt_center().snapped(Vector3.ONE), _player.global_position.snapped(Vector3.ONE)])
			"energy":
				cd.energy = 1.0
			_:
				cd.request(String(e[1]))
	# The sword must never linger in her hand once no attack is playing.
	var td: TrickDirector = _player.get_node("Visual").tricks
	if td.out.hold > 0.5 and not cd._attack_on():
		_stuck_time += delta
		_max_stuck = maxf(_max_stuck, _stuck_time)
	else:
		_stuck_time = 0.0


func _burst_capture() -> void:
	var hv := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	var dir := hv.normalized() if hv.length() > 1.0 else _player.facing_direction()
	# A steady tracking shot (the gameplay camera's springs would drift in jumps):
	# fixed distance and angle from the travel direction, level with the rider.
	if _burst_game_cam:
		_cam._idle_look = 0.0
		Engine.time_scale = 0.25 if _t >= _burst.x - 0.3 and _t <= _burst.y else 1.0
		if _t >= _burst_next and _t <= _burst.y:
			get_viewport().get_texture().get_image().save_png("%s/burst_%03d.png" % [_out, _burst_i])
			_burst_i += 1
			_burst_next += _burst.z
		elif _t > _burst.y:
			print("[tour] burst saved %d frames" % _burst_i)
			get_tree().quit()
		return
	_cam.set_process(false)
	var feet := _player.get_global_transform_interpolated().origin
	var side := Basis(Vector3.UP, atan2(-dir.x, -dir.z) + _burst_yaw) * Vector3.BACK
	var cam: Camera3D = _cam.camera
	var eye := feet + side * 4.2 * _zoom_mul + Vector3.UP * _burst_up
	cam.global_transform = Transform3D(Basis.looking_at(feet + Vector3.UP * 0.9 - eye, Vector3.UP), eye)
	cam.fov = 60.0
	# Slow motion while capturing: every saved frame is a different moment (saving a PNG
	# stalls the game, and the physics would otherwise catch up several ticks unseen).
	Engine.time_scale = 0.25 if _t >= _burst.x - 0.3 and _t <= _burst.y else 1.0
	if _t >= _burst_next and _t <= _burst.y:
		get_viewport().get_texture().get_image().save_png("%s/burst_%03d.png" % [_out, _burst_i])
		_burst_i += 1
		_burst_next += _burst.z
	elif _t > _burst.y:
		print("[tour] burst saved %d frames" % _burst_i)
		get_tree().quit()
