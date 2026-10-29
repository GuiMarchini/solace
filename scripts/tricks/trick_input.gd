class_name TrickInput
extends RefCounted
## Trick buttons (Input Map actions `trick_spin`, default Q, and `trick_style`,
## default E) with buffering: a press is kept for `buffer_time` so one made slightly
## early (just before takeoff, or while the previous trick is still playing) is not
## lost; while the jump is charging presses are held for the jump to come.
## TrickDirector polls it once per frame and decides what each press means.

const SPIN := &"trick_spin"
const STYLE := &"trick_style"

## Seconds a press waits to be used.
var buffer_time := 0.45

# Pending presses: [button ("Q" / "E"), age].
var _pending: Array = []


## Reads the buttons (call every frame). `hold`: keep pending presses from expiring.
func update(delta: float, enabled: bool, hold := false) -> void:
	if not hold:
		for p in _pending:
			p[1] += delta
	_pending = _pending.filter(func(p: Array) -> bool: return p[1] <= buffer_time)
	if not enabled:
		_pending.clear()
		return
	if InputMap.has_action(SPIN) and Input.is_action_just_pressed(SPIN):
		_pending.append(["Q", 0.0])
	if InputMap.has_action(STYLE) and Input.is_action_just_pressed(STYLE):
		_pending.append(["E", 0.0])


## Injects a press (tests, tour).
func press(button: String) -> void:
	_pending.append([button, 0.0])


func has_pending() -> bool:
	return not _pending.is_empty()


## The oldest pending press, or "" if none (it stays pending until `consume`).
func peek() -> String:
	return _pending[0][0] if not _pending.is_empty() else ""


## Uses the oldest press; returns it.
func consume() -> String:
	if _pending.is_empty():
		return ""
	return _pending.pop_front()[0]


func clear() -> void:
	_pending.clear()
