class_name GameUI
extends CanvasLayer
## Nearly invisible interface: a fade-in from black, a small control hint that
## fades out on its own (F1 brings it back), a minimal pause overlay, and an optional
## debug readout (F3). No trick names or scores on screen: tricks speak through the
## rider, the sand and soft sounds.

@export var player_path: NodePath
@export var hint_delay := 1.5
@export var hint_duration := 10.0

signal resume_requested
signal quit_requested

var _player: PlayerController
var _fade: ColorRect
var _hint: Label
var _pause: Control
var _debug: Label
var _hint_t := 0.0
var _hint_visible := true



func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = get_node_or_null(player_path) as PlayerController

	_hint = Label.new()
	_hint.text = "W glide   A/D carve   Shift boost   Space jump   Mouse L slash   Mouse R breaker   Q spin   E dash   F spirit   C/X tricks"
	var ls := LabelSettings.new()
	ls.font_size = 15
	ls.font_color = Color(1.0, 0.97, 0.92, 0.85)
	ls.shadow_color = Color(0.1, 0.07, 0.12, 0.5)
	ls.shadow_size = 6
	ls.shadow_offset = Vector2.ZERO
	_hint.label_settings = ls
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_top = -64.0
	_hint.offset_bottom = -36.0
	_hint.offset_left = -600.0
	_hint.offset_right = 600.0
	_hint.modulate.a = 0.0
	add_child(_hint)

	_debug = Label.new()
	_debug.position = Vector2(16, 12)
	var dls := LabelSettings.new()
	dls.font_size = 13
	dls.font_color = Color(1, 1, 1, 0.9)
	dls.outline_size = 4
	dls.outline_color = Color(0, 0, 0, 0.6)
	_debug.label_settings = dls
	_debug.visible = false
	add_child(_debug)

	_pause = _build_pause()
	_pause.visible = false
	add_child(_pause)

	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.02, 0.04, 1.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 2.2).set_trans(Tween.TRANS_SINE).set_delay(0.2)


func _build_pause() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.08, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -160.0
	box.offset_right = 160.0
	box.offset_top = -90.0
	box.offset_bottom = 90.0
	box.add_theme_constant_override("separation", 14)
	root.add_child(box)
	var title := Label.new()
	title.text = "S O L A C E"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tls := LabelSettings.new()
	tls.font_size = 34
	tls.font_color = Color(0.95, 0.96, 1.0)
	tls.shadow_color = Color(0.4, 0.7, 1.0, 0.5)
	tls.shadow_size = 12
	tls.shadow_offset = Vector2.ZERO
	title.label_settings = tls
	box.add_child(title)
	var resume := Button.new()
	resume.text = "Resume"
	resume.flat = true
	resume.pressed.connect(func() -> void: resume_requested.emit())
	box.add_child(resume)
	var quit := Button.new()
	quit.text = "Quit"
	quit.flat = true
	quit.pressed.connect(func() -> void: quit_requested.emit())
	box.add_child(quit)
	return root


func set_paused(paused: bool) -> void:
	_pause.visible = paused


func show_hint() -> void:
	_hint_t = hint_delay
	_hint_visible = true


func _process(delta: float) -> void:
	if Input.is_action_just_pressed(&"toggle_hint"):
		if _hint.modulate.a > 0.1:
			_hint_t = hint_delay + hint_duration
		else:
			show_hint()
	if Input.is_action_just_pressed(&"toggle_debug"):
		_debug.visible = not _debug.visible

	_hint_t += delta
	var a := 0.0
	if _hint_visible:
		a = smoothstep(hint_delay, hint_delay + 1.0, _hint_t) * (1.0 - smoothstep(hint_delay + hint_duration - 1.5, hint_delay + hint_duration, _hint_t))
	_hint.modulate.a = a


	if _debug.visible and _player:
		var hm := _player.hover
		_debug.text = "FPS %d\nmode %s\nspeed %.1f m/s\nvy %.1f\nboost %.2f\nsupported %s  hover %.2f m\npos %s" % [
			Engine.get_frames_per_second(), PlayerController.Mode.keys()[_player.mode],
			_player.horizontal_speed(), _player.velocity.y, hm.boost_level,
			str(hm.supported), hm.ground_distance if hm.ground_distance < 100.0 else -1.0,
			str(_player.global_position.snapped(Vector3.ONE * 0.1))]
