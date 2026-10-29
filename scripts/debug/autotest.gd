extends Node
## Automated gameplay test. Drives the real Input Map actions through a scripted
## sequence (walk, run, jump, dodge, summon, ride, boost, carve, board jump,
## dismiss, rapid summon/dismiss, long ride) and checks invariants every tick:
## no NaNs, never below the terrain, board hovers near its target height.
## Run:  Godot --headless --path . --fixed-fps 60 -- --autotest

var _player: PlayerController
var _terrain: DuneTerrain
var _t := 0.0
var _step := 0
var _step_t := 0.0
var _fail: Array[String] = []
var _log: Array[String] = []
var _min_clearance := INF
var _max_speed := 0.0
var _ride_ticks := 0
var _supported_ticks := 0
var _hover_err_sum := 0.0
var _hover_samples := 0
var _landings := 0
var _jumps := 0
var _dodges := 0
var _summons := 0
var _dismisses := 0
var _mark := {}
var _taps := {}
var _ride_since := 0.0
var _rng := RandomNumberGenerator.new()
var _cam: Camera3D
var _cam_prev_fwd := Vector3.ZERO
var _cam_prev_rate := 0.0
var _cam_prev_y := 0.0
var _cam_prev_vy := 0.0
var _cam_jerk_sum := 0.0
var _cam_vjerk_sum := 0.0
var _cam_samples := 0
var _cam_max_jerk := 0.0
var _cape_max_reach := 0.0
var _ribbon_min_gap := INF
var _cloak_max_reach := 0.0
var _max_seen := {}
var _slide_sum := 0.0
var _slide_n := 0
var _slide_prev := Vector3.ZERO
var _slide_foot := -1


func _ready() -> void:
	process_physics_priority = -100
	_player = get_parent().get_node("Player")
	_terrain = get_parent().get_node("Desert/DuneTerrain")
	_rng.seed = 42
	# The game itself starts mounted on the sword with no walking; the legacy part of
	# this suite still exercises the on-foot rig and the summon/dismiss transitions.
	_expect(not _player.foot_enabled and _player.mount_delay >= 0.0, "game is sword-only (no walking)")
	_player.enable_foot()
	_player.landed.connect(func(_i: float, _b: bool) -> void: _landings += 1)
	_player.jumped.connect(func(_b: bool) -> void: _jumps += 1)
	_player.dodged.connect(func(_d: Vector3) -> void: _dodges += 1)
	_player.mode_changed.connect(_on_mode_changed)
	print("[autotest] start")
	_check_collision_alignment()


func _on_mode_changed(m: PlayerController.Mode) -> void:
	if m == PlayerController.Mode.RIDE:
		_summons += 1
		_ride_since = _t
	else:
		_dismisses += 1


func _process(delta: float) -> void:
	if is_physics_processing():
		_camera_metric(delta)


func _check_collision_alignment() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := _player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = 1
	var max_err := 0.0
	var misses := 0
	for i in 300:
		var x := _rng.randf_range(-550.0, 550.0)
		var z := _rng.randf_range(-550.0, 550.0)
		q.from = Vector3(x, 500.0, z)
		q.to = Vector3(x, -500.0, z)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			misses += 1
			continue
		var p: Vector3 = hit["position"]
		max_err = maxf(max_err, absf(p.y - _terrain.height_at(x, z)))
	_log.append("collision vs analytic height: max error %.3f m, misses %d/300" % [max_err, misses])
	if misses > 0 or max_err > 0.25:
		_fail.append("terrain collision does not match rendered height (err %.3f, misses %d)" % [max_err, misses])


func _release_all() -> void:
	for a in [&"move_forward", &"move_back", &"move_left", &"move_right", &"run", &"jump", &"dodge", &"hoverboard", &"walk"]:
		Input.action_release(a)


func _tap(action: StringName) -> void:
	Input.action_press(action)
	_taps[action] = 2


func _next(label: String) -> void:
	_log.append("%6.2fs  %-28s pos %s speed %.1f mode %s" % [_t, label,
		str(_player.global_position.snapped(Vector3.ONE * 0.1)), _player.horizontal_speed(),
		PlayerController.Mode.keys()[_player.mode]])
	_step += 1
	_step_t = 0.0


func _physics_process(delta: float) -> void:
	_t += delta
	_step_t += delta
	for a in _taps.keys():
		_taps[a] -= 1
		if _taps[a] <= 0:
			Input.action_release(a)
			_taps.erase(a)
	_monitor()
	_foot_slide_metric(delta)
	var p := _player
	var riding := p.mode == PlayerController.Mode.RIDE
	match _step:
		0:
			if _step_t > 0.6:
				_next("settled")
		1:
			Input.action_press(&"move_forward")
			if _step_t > 2.0:
				_mark_value("run_speed", p.horizontal_speed())
				_expect(absf(p.horizontal_speed() - p.foot.run_speed) < 0.3, "default movement runs")
				_next("walked")
		2:
			Input.action_press(&"run")
			if _step_t > 2.5:
				_mark_value("sprint_speed", p.horizontal_speed())
				_expect(absf(p.horizontal_speed() - p.foot.sprint_speed) < 0.3, "shift sprints")
				_next("sprinted")
		3:
			if _step_t < delta * 1.5:
				_mark_value("jumps_before", _jumps)
				_tap(&"jump")
			if _step_t > 1.5:
				_expect(_jumps > int(_mark["jumps_before"]), "foot jump triggered")
				_expect(p.grounded, "landed after foot jump")
				_next("jumped")
		4:
			if _step_t < delta * 1.5:
				_tap(&"dodge")
			if _step_t > 0.05 and _step_t < 0.12:
				_mark_value("dodge_speed", p.horizontal_speed())
			if _step_t > 1.0:
				_expect(_dodges >= 1, "dodge triggered")
				_expect(float(_mark.get("dodge_speed", 0.0)) > 12.0, "dodge burst speed (%.1f)" % float(_mark.get("dodge_speed", 0.0)))
				_next("dodged")
		5:
			_release_all()
			if _step_t > 1.0:
				_tap(&"hoverboard")
				_next("summon pressed")
		6:
			if _step_t > 1.0:
				_expect(riding, "riding after summon")
				_expect(p.hover.supported, "board supported after summon")
				_expect(absf(p.hover.ground_distance - p.hover.hover_height) < 0.15,
						"hover height near target (%.2f)" % p.hover.ground_distance)
				_next("hovering")
		7:
			Input.action_press(&"move_forward")
			if _step_t > 5.0:
				_mark_value("cruise", p.horizontal_speed())
				_next("cruising")
		8:
			Input.action_press(&"run")
			if _step_t > 4.0:
				_mark_value("boost", p.horizontal_speed())
				var rib: Ribbons = p.get_node("Visual/Ribbons")
				var tip: Vector3 = rib.points[0][rib.points[0].size() - 1]
				_mark_value("ribbon tip - anchor at boost", (tip - rib.model.cape_anchor().origin).snapped(Vector3.ONE * 0.01))
				_expect(float(_mark["boost"]) > float(_mark["cruise"]) + 4.0, "boost faster than cruise")
				_next("boosted")
		9:
			Input.action_release(&"run")
			Input.action_press(&"move_left")
			if _step_t > 2.0:
				_next("carved left")
		10:
			Input.action_release(&"move_left")
			if _step_t < delta * 1.5:
				_mark_value("board_jumps_before", _jumps)
				_tap(&"jump")
			if _step_t > 0.25 and _step_t < 0.3:
				_expect(not p.hover.supported, "airborne after board jump")
			if _step_t > 2.5:
				_expect(_jumps > int(_mark["board_jumps_before"]), "board jump triggered")
				_expect(p.hover.supported, "board recovered hover after jump")
				_next("board jumped")
		11:
			if _step_t < delta * 1.5:
				_tap(&"hoverboard")
			if _step_t > 2.0:
				_expect(p.mode == PlayerController.Mode.FOOT, "dismissed to foot")
				_expect(p.grounded, "grounded after dismiss")
				_expect(p.horizontal_speed() < 11.0, "no launch on dismiss (%.1f)" % p.horizontal_speed())
				_next("dismissed")
		12:
			# Rapid summon / dismiss while moving.
			if fmod(_step_t, 0.55) < delta * 1.01:
				_tap(&"hoverboard")
			if _step_t > 0.55 * 12.0:
				_release_all()
				_next("rapid toggles")
		13:
			if _step_t > 1.5:
				if p.mode == PlayerController.Mode.FOOT:
					_tap(&"hoverboard")
				_next("long ride start")
		14:
			# Long ride with wandering steering, boosts and jumps.
			Input.action_press(&"move_forward")
			var s := sin(_step_t * 0.37) + 0.6 * sin(_step_t * 1.1)
			if s > 0.6:
				Input.action_press(&"move_left")
				Input.action_release(&"move_right")
			elif s < -0.6:
				Input.action_press(&"move_right")
				Input.action_release(&"move_left")
			else:
				Input.action_release(&"move_left")
				Input.action_release(&"move_right")
			if fmod(_step_t, 7.0) < 3.0:
				Input.action_press(&"run")
			else:
				Input.action_release(&"run")
			if fmod(_step_t, 4.3) < delta * 1.01:
				_tap(&"jump")
			if _step_t > 40.0:
				_release_all()
				_next("long ride end")
		15:
			# Board drift: get fast, then hold a sharp turn.
			Input.action_press(&"move_forward")
			Input.action_press(&"run")
			if _step_t > 3.0:
				_next("fast for drift")
		16:
			Input.action_release(&"run")
			Input.action_press(&"move_forward")
			Input.action_press(&"move_left")
			_track("drift", p.hover.drift_amount)
			if _step_t > 1.6:
				_expect(_max_seen.get("drift", 0.0) > 0.5, "sharp fast turn drifts (%.2f)" % _max_seen.get("drift", 0.0))
				_next("drifted")
		17:
			Input.action_release(&"move_left")
			if _step_t > 1.5:
				_expect(not p.hover.drifting, "drift ends when the turn eases")
				_release_all()
				_tap(&"hoverboard")
				_next("dismiss for foot tests")
		18:
			if _step_t > 1.5:
				_ctx().force_variations = true
				_place_on_flat()
				_next("sprint for sand touch")
		19:
			Input.action_press(&"move_forward")
			Input.action_press(&"run")
			if _step_t > 2.5:
				_next("sprinting")
		20:
			Input.action_release(&"move_forward")
			Input.action_press(&"move_left")
			_track("sand", _ctx().sand_touch)
			if _step_t > 1.2:
				_expect(_max_seen.get("sand", 0.0) > 0.3, "sharp sprint turn brushes the sand (%.2f)" % _max_seen.get("sand", 0.0))
				_release_all()
				_next("sand touch")
		21:
			# A walking turn must never trigger it.
			Input.action_press(&"walk")
			Input.action_press(&"move_right" if fmod(_step_t, 1.0) < 0.5 else &"move_back")
			Input.action_release(&"move_back" if fmod(_step_t, 1.0) < 0.5 else &"move_right")
			if _step_t > 0.6:
				_track("sand_walk", _ctx().sand_touch)
			if _step_t > 4.0:
				_expect(_max_seen.get("sand_walk", 0.0) == 0.0, "walking turns never brush the sand")
				_release_all()
				_ctx().force_variations = false
				_next("walk turns")
		22:
			if _step_t < delta * 1.5:
				p.global_position += Vector3.UP * 4.5
				p.velocity = Vector3.ZERO
				p.reset_physics_interpolation()
			_track("land_low", _ctx().land_low)
			if _step_t > 2.0:
				_expect(_max_seen.get("land_low", 0.0) > 0.3, "big drop gives a low landing")
				var c := _ctx()
				c.rest_chance = 1.0
				c.rest_after = Vector2(1.0, 1.0)
				c._rest_threshold = 1.0
				_next("hard landing")
		23:
			if _ctx().sit >= 0.99:
				_mark_value("seated after idle (s)", snappedf(_step_t, 0.1))
				_next("seated")
			elif _step_t > 9.0:
				_expect(false, "rests (sits) after idling")
				_next("seated")
		24:
			Input.action_press(&"move_forward")
			if _step_t > 0.35:
				_expect(_ctx().sit < 0.2, "input interrupts resting promptly (sit %.2f)" % _ctx().sit)
				_expect(p.horizontal_speed() > 1.5, "control returns immediately (%.1f m/s)" % p.horizontal_speed())
				_release_all()
				_next("stood up")
		25:
			_finish()


## How far a planted foot slides on the sand per step while running/sprinting.
func _foot_slide_metric(delta: float) -> void:
	if not (_step == 1 or _step == 2) or _step_t < 1.0 or not _player.is_on_floor():
		_slide_foot = -1
		return
	var m: SpiritModel = _player.get_node("Visual/SpiritModel")
	var sk := m.skeleton
	var feet := [sk.global_transform * sk.get_bone_global_pose(SpiritModel.FT_L).origin,
		sk.global_transform * sk.get_bone_global_pose(SpiritModel.FT_R).origin]
	var low := 0 if m.foot_planted[0] else (1 if m.foot_planted[1] else -1)
	if low < 0:
		_slide_foot = -1
		return
	var f: Vector3 = feet[low]
	if low == _slide_foot:
		var d := f - _slide_prev
		_slide_sum += Vector2(d.x, d.z).length()
	else:
		_slide_n += 1   # a new stance begins
	_slide_foot = low
	_slide_prev = f


## Moves the player to a nearby flat stretch (foot variation tests shouldn't depend
## on whatever dune face the previous step ended on).
func _place_on_flat() -> void:
	var best := _player.global_position
	var best_score := INF
	for i in 400:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(0.0, 120.0)
		var c := _player.global_position + Vector3(cos(a), 0.0, sin(a)) * r
		var score := 0.0
		for k in 8:
			var q := c + Vector3(cos(k * TAU / 8.0), 0.0, sin(k * TAU / 8.0)) * 10.0
			score += 1.0 - _terrain.normal_at(q.x, q.z).y
		score += 1.0 - _terrain.normal_at(c.x, c.z).y
		if score < best_score and _terrain.is_inside(c.x, c.z, 60.0):
			best_score = score
			best = c
	_player.place_on_ground(best)


func _ctx() -> MotionContext:
	return _player.get_node("Visual/MotionContext")


func _track(k: String, v: float) -> void:
	_max_seen[k] = maxf(_max_seen.get(k, 0.0), v)


func _mark_value(k: String, v: Variant) -> void:
	_mark[k] = v
	_log.append("        %s = %s" % [k, str(v)])


func _expect(cond: bool, what: String) -> void:
	if cond:
		_log.append("        ok   %s" % what)
	else:
		_log.append("        FAIL %s" % what)
		_fail.append(what)


func _monitor() -> void:
	var p := _player.global_position
	var v := _player.velocity
	if is_nan(p.x) or is_nan(p.y) or is_nan(v.x) or is_nan(v.y):
		_fail.append("NaN at t=%.2f" % _t)
		_finish()
		return
	var rib: Ribbons = _player.get_node("Visual/Ribbons")
	if rib.model and rib.points.size() >= 2:
		# Stretch: each strip's actual length along its points over its specified length.
		for r in rib.points.size():
			var fin := r < rib.ribbons.size()
			var length: float = rib.ribbons[r].y if fin else rib.head_locks[r - rib.ribbons.size()].y
			var pts: PackedVector3Array = rib.points[r]
			var along := 0.0
			for j in pts.size():
				var q := pts[j]
				if is_nan(q.x) or is_nan(q.y) or is_nan(q.z):
					_fail.append("ribbon NaN at t=%.2f" % _t)
					break
				if j > 0:
					along += q.distance_to(pts[j - 1])
			_cape_max_reach = maxf(_cape_max_reach, along / length)
		for i in range(4, mini(rib.points[0].size(), rib.points[1].size())):
			_ribbon_min_gap = minf(_ribbon_min_gap, rib.points[0][i].distance_to(rib.points[1][i]))
	var cloak: Cloak = _player.get_node("Visual/Cloak")
	for col in cloak._pts:
		if col.is_empty():
			continue
		var reach := col[0].distance_to(col[col.size() - 1])
		_cloak_max_reach = maxf(_cloak_max_reach, reach)
		if is_nan(reach):
			_fail.append("cloak NaN at t=%.2f" % _t)
			break
	var clear := p.y - _terrain.height_at(p.x, p.z)
	_min_clearance = minf(_min_clearance, clear)
	_max_speed = maxf(_max_speed, Vector2(v.x, v.z).length())
	if _player.mode == PlayerController.Mode.RIDE:
		_ride_ticks += 1
		if _player.hover.supported:
			_supported_ticks += 1
			if _player.hover.air_time == 0.0 and _player.hover.ground_distance < 2.0:
				_hover_err_sum += absf(_player.hover.ground_distance - _player.hover.hover_height)
				_hover_samples += 1
		if clear < -0.01 and _t - _ride_since > 0.35:
			_fail.append("board deck touched/clipped the ground at t=%.2f (clearance %.2f, probe %.2f, v %s)" % [
				_t, clear, _player.hover.ground_distance, str(v.snapped(Vector3.ONE * 0.1))])


## Camera stability: frame-to-frame change of angular speed (rad/s^2) and of vertical
## speed (m/s^2), sampled while moving fast. Lower is steadier.
func _camera_metric(delta: float) -> void:
	if _cam == null:
		_cam = get_viewport().get_camera_3d()
		return
	var f := -_cam.global_transform.basis.z
	var rel_y := _cam.global_position.y
	if _cam_prev_fwd != Vector3.ZERO:
		var rate := acos(clampf(f.dot(_cam_prev_fwd), -1.0, 1.0)) / delta
		var vy := (rel_y - _cam_prev_y) / delta
		if _player.horizontal_speed() > 15.0:
			var j := absf(rate - _cam_prev_rate) / delta
			_cam_jerk_sum += j
			_cam_vjerk_sum += absf(vy - _cam_prev_vy) / delta
			_cam_max_jerk = maxf(_cam_max_jerk, j)
			_cam_samples += 1
		_cam_prev_rate = rate
		_cam_prev_vy = vy
	_cam_prev_fwd = f
	_cam_prev_y = rel_y


func _finish() -> void:
	set_physics_process(false)
	_release_all()
	_log.append("min clearance feet-terrain: %.3f m" % _min_clearance)
	_log.append("max horizontal speed: %.1f m/s" % _max_speed)
	_log.append("ride ticks %d, supported %.0f%%, mean |hover error| %.3f m" % [_ride_ticks,
		100.0 * _supported_ticks / maxf(_ride_ticks, 1), _hover_err_sum / maxf(_hover_samples, 1)])
	_log.append("camera at speed: mean angular jerk %.2f rad/s^2 (max %.1f), mean vertical jerk %.2f m/s^2, %d samples" % [
		_cam_jerk_sum / maxf(_cam_samples, 1), _cam_max_jerk, _cam_vjerk_sum / maxf(_cam_samples, 1), _cam_samples])
	# The travelling wave and the strand separation add a little length on top.
	var reach_limit := 1.15
	_log.append("ribbon max stretch: %.2f x its length (limit %.2f), min gap between fins %.3f m" % [_cape_max_reach, reach_limit, _ribbon_min_gap])
	var cloak_node: Cloak = _player.get_node("Visual/Cloak")
	var cloak_limit := cloak_node.back_length * 1.12 + 0.05
	_log.append("cloak max hem distance from shoulders: %.2f m (limit %.2f)" % [_cloak_max_reach, cloak_limit])
	if _cloak_max_reach > cloak_limit:
		_fail.append("cloak over-stretched (%.2f m)" % _cloak_max_reach)
	if _cape_max_reach > reach_limit:
		_fail.append("ribbons over-stretched (%.2f x length)" % _cape_max_reach)
	if _ribbon_min_gap < 0.015:
		_fail.append("ribbons merged (gap %.3f m)" % _ribbon_min_gap)
	var slide := _slide_sum / maxf(_slide_n, 1) * 100.0
	_log.append("planted foot slide while running/sprinting: %.1f cm per step over %d steps" % [slide, _slide_n])
	if slide > 8.0:
		_fail.append("feet slide too much (%.1f cm per step)" % slide)
	_log.append("events: jumps %d, landings %d, dodges %d, summons %d, dismisses %d" % [_jumps, _landings, _dodges, _summons, _dismisses])
	if _min_clearance < -0.2:
		_fail.append("player went below terrain (%.2f)" % _min_clearance)
	if _summons != _dismisses and _summons != _dismisses + 1:
		_fail.append("summon/dismiss count mismatch")
	var boards := 0
	for n in get_tree().root.find_children("*", "Hoverboard", true, false):
		boards += 1
	_log.append("hoverboard instances in tree: %d" % boards)
	if boards != 1:
		_fail.append("expected exactly one hoverboard, found %d" % boards)
	for l in _log:
		print(l)
	if _fail.is_empty():
		print("[autotest] PASS")
	else:
		print("[autotest] FAIL (%d)" % _fail.size())
		# Deduplicate repeated per-tick failures.
		var seen := {}
		for f in _fail:
			var key := f.split(" at t=")[0]
			if not seen.has(key):
				seen[key] = true
				print("  - " + f)
	get_tree().quit(0 if _fail.is_empty() else 1)
