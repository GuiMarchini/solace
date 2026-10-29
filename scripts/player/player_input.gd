class_name PlayerInput
extends RefCounted
## Snapshot of the player's intent for one physics tick, read from the Input Map.
## Movement is converted to a camera-relative world direction here so the motors
## never touch raw input.

var move := Vector2.ZERO
var move_world := Vector3.ZERO
## Independent, un-normalised axes (x = left/right, y = forward(-)/back(+)) for board carving.
var axes := Vector2.ZERO
var jump_pressed := false
var jump_held := false
var run_held := false
var dodge_pressed := false
var board_pressed := false


func read(camera_yaw: float, enabled: bool) -> void:
	if not enabled:
		clear()
		return
	move = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	move_world = Basis(Vector3.UP, camera_yaw) * Vector3(move.x, 0.0, move.y)
	axes = Vector2(Input.get_axis(&"move_left", &"move_right"), Input.get_axis(&"move_forward", &"move_back"))
	jump_pressed = Input.is_action_just_pressed(&"jump")
	jump_held = Input.is_action_pressed(&"jump")
	run_held = Input.is_action_pressed(&"run")
	dodge_pressed = Input.is_action_just_pressed(&"dodge")
	board_pressed = Input.is_action_just_pressed(&"hoverboard")


func clear() -> void:
	move = Vector2.ZERO
	move_world = Vector3.ZERO
	axes = Vector2.ZERO
	jump_pressed = false
	jump_held = false
	run_held = false
	dodge_pressed = false
	board_pressed = false
