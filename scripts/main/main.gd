extends Node3D
## Bootstraps the demo: mouse capture, pause, fullscreen toggle, the training ground
## (sentinels to fight near the start), and the optional automated test / screenshot
## tour (launched with `-- --autotest` or `-- --tour`).

@onready var ui: GameUI = $UI
@onready var player: PlayerController = $Player

var _paused := false


func _ready() -> void:
	_ensure_action(&"walk", KEY_ALT)
	# Trick and attack buttons (also in project.godot; registered here if an older one is
	# saved over). Tricks moved from Q / E to C / X when Q / E became attacks.
	_ensure_action(&"trick_spin", KEY_C, JOY_BUTTON_DPAD_LEFT)
	_ensure_action(&"trick_style", KEY_X, JOY_BUTTON_DPAD_RIGHT)
	_migrate_key(&"trick_spin", KEY_Q, KEY_C)
	_migrate_key(&"trick_style", KEY_E, KEY_X)
	_ensure_action(&"attack_light", KEY_NONE, JOY_BUTTON_X, MOUSE_BUTTON_LEFT)
	_ensure_action(&"attack_heavy", KEY_NONE, JOY_BUTTON_Y, MOUSE_BUTTON_RIGHT)
	_ensure_action(&"attack_spin", KEY_Q, JOY_BUTTON_LEFT_SHOULDER)
	_ensure_action(&"attack_dash", KEY_E, JOY_BUTTON_B)
	_ensure_action(&"attack_special", KEY_F, JOY_BUTTON_DPAD_UP, MOUSE_BUTTON_MIDDLE)
	_training_ground()
	ui.resume_requested.connect(func() -> void: _set_paused(false))
	ui.quit_requested.connect(func() -> void: get_tree().quit())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ui.show_hint()
	var args := OS.get_cmdline_user_args()
	if "--autotest" in args:
		add_child(load("res://scripts/debug/autotest.gd").new())
	elif "--inspect" in args:
		add_child(load("res://scripts/debug/inspect.gd").new())
	elif "--tour" in args:
		add_child(load("res://scripts/debug/screenshot_tour.gd").new())


## Registers an input action at runtime if project.godot doesn't define it
## (keeps the game playable even if an older project.godot is saved over).
func _ensure_action(action: StringName, key: Key, joy := JOY_BUTTON_INVALID, mouse := MOUSE_BUTTON_NONE) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	if key != KEY_NONE:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
	if joy != JOY_BUTTON_INVALID:
		var jb := InputEventJoypadButton.new()
		jb.button_index = joy
		InputMap.action_add_event(action, jb)
	if mouse != MOUSE_BUTTON_NONE:
		var mb := InputEventMouseButton.new()
		mb.button_index = mouse
		InputMap.action_add_event(action, mb)


## Moves an action off an old default key (only if it still has it).
func _migrate_key(action: StringName, old: Key, new: Key) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == old:
			InputMap.action_erase_event(action, ev)
			var k := InputEventKey.new()
			k.physical_keycode = new
			InputMap.action_add_event(action, k)


## Stone sentinels to practise on, posted along the way out from the start.
func _training_ground() -> void:
	var ground := Node3D.new()
	ground.name = "TrainingGround"
	add_child(ground)
	for p in [Vector2(-5, -32), Vector2(6, -50), Vector2(-3, -72), Vector2(9, -96), Vector2(-11, -122),
			Vector2(24, -44), Vector2(-26, -64), Vector2(18, -140), Vector2(-20, -165)]:
		SpiritTarget.spawn(ground, Vector3(p.x, 0.0, p.y))


func _exit_tree() -> void:
	Fx.clear_cache()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		_set_paused(not _paused)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"toggle_fullscreen"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif event is InputEventMouseButton and event.pressed and not _paused \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not _paused and is_inside_tree():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _set_paused(p: bool) -> void:
	_paused = p
	get_tree().paused = p
	ui.set_paused(p)
	player.input_enabled = not p
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if p else Input.MOUSE_MODE_CAPTURED
