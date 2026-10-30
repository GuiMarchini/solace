extends Node
## Photographs the world from fixed viewpoints, for before/after comparisons of the
## environment art (`-- --views --out=<folder>`, optional `--only=name,name`).
## The player stays at the spawn (for scale in the near views); the UI is hidden and the
## follow camera is frozen while the shots are taken.

## [name, eye (x, height above the sand, z), target (x, height above the sand, z)]
const VIEWS := [
	["01_spawn_ahead", Vector3(0, 3, 9), Vector3(0, 6, -260)],
	["02_spawn_high", Vector3(45, 28, 70), Vector3(-60, 0, -520)],
	["03_colonnade", Vector3(22, 4, -175), Vector3(-10, 8, -430)],
	["04_oasis", Vector3(150, 10, -150), Vector3(255, 0, -255)],
	["05_east", Vector3(0, 6, 0), Vector3(600, 30, 40)],
	["06_west", Vector3(0, 6, 0), Vector3(-600, 30, -60)],
	["07_into_sun", Vector3(-30, 5, 40), Vector3(220, 25, -480)],
	["08_aerial", Vector3(60, 170, 260), Vector3(0, 0, -420)],
	["09_back", Vector3(0, 6, -40), Vector3(80, 20, 600)],
	["10_blade", Vector3(-120, 10, -300), Vector3(-560, 60, -1250)],
	["11_warden", Vector3(200, 12, -420), Vector3(760, 25, -1450)],
	["12_aqueduct", Vector3(-300, 10, -200), Vector3(-1450, 60, -1200)],
	["13_blade_close", Vector3(-420, 30, -950), Vector3(-560, 50, -1250)],
	["14_warden_close", Vector3(600, 30, -1100), Vector3(760, 25, -1450)],
	["15_banners", Vector3(30, 3, -260), Vector3(10, 6, -330)],
	["16_sandfall", Vector3(-385, 9, -185), Vector3(-450, 22, -232)],
]

var _out := "user://views"
var _only: PackedStringArray = []
var _cam: Camera3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--only="):
			_only = a.substr(7).split(",")
	DirAccess.make_dir_recursive_absolute(_out)
	# Real frame times, not the monitor's refresh rate.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_run.call_deferred()


func _ground(x: float, z: float) -> float:
	return DuneTerrain.instance.height_at(x, z) if DuneTerrain.instance else 0.0


func _run() -> void:
	var main := get_parent()
	var ui := main.get_node_or_null("UI") as CanvasLayer
	if ui:
		ui.visible = false
	var rig := main.get_node("CameraRig")
	rig.set_process(false)
	_cam = rig.get_node("Camera3D") as Camera3D
	_cam.fov = 70.0
	# Let the world build and the effects settle.
	for i in 90:
		await get_tree().process_frame
	var times := []
	for v in VIEWS:
		if not _only.is_empty() and not (String(v[0]) in _only):
			continue
		var e: Vector3 = v[1]
		var t: Vector3 = v[2]
		var eye := Vector3(e.x, _ground(e.x, e.z) + e.y, e.z)
		var at := Vector3(t.x, _ground(t.x, t.z) + t.y, t.z)
		_cam.global_transform = Transform3D(Basis.looking_at(at - eye, Vector3.UP), eye)
		# Temporal effects (volumetric fog, SSAO) need a few frames to converge.
		var t0 := Time.get_ticks_usec()
		for i in 40:
			await get_tree().process_frame
		times.append(float(Time.get_ticks_usec() - t0) / 40.0 / 1000.0)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, v[0]])
		print("[views] %s  %.1f ms/frame" % [v[0], times[-1]])
	print("[views] done")
	get_tree().quit()
