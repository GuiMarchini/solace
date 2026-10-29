class_name ComboTracker
extends Node
## Flow combos: every trick (air or ground) joins the current chain, which stays alive
## while she is airborne and for `link_window` seconds after a trick or a landing, so
## a landing straight into the next jump, deck trick or carve keeps it going. Points
## grow with a multiplier: +0.5 for each different trick in the chain and for each
## clean landing; repeating a trick in the same chain is worth less and less, so a
## long, varied sequence pays far more than one trick done over and over. The chain
## banks when the window runs out on the ground; a bail loses it. Automatic air moves
## score a little but never raise the multiplier: that comes from the player's tricks.
## Signals drive the HUD, sounds and effects.

signal chain_changed(names: PackedStringArray, multiplier: float, points: int)
signal trick_added(trick_name: String, points: int, multiplier: float)
signal landed_clean(multiplier: float)
signal banked(total: int, multiplier: float)
signal lost

## Seconds on the ground a chain survives without a new trick or jump.
@export var link_window := 1.8

var multiplier := 1.0
var points := 0
var total_score := 0
var names: PackedStringArray = []
var active := false

var _counts := {}
var _timer := 0.0
var _airborne := false
var _air_tricks := 0


func add_trick(trick_name: String, base_points: int, player_made: bool) -> void:
	# Her automatic moves only add to a chain the player has started.
	if not player_made and not active:
		return
	var n: int = _counts.get(trick_name, 0)
	if player_made and n == 0:
		multiplier += 0.5 if active else 0.0
	_counts[trick_name] = n + 1
	var value := int(base_points * pow(0.5, n))
	points += value
	names.append(trick_name)
	active = true
	# Only the player's own tricks keep the chain open.
	if player_made:
		_timer = link_window
		_air_tricks += 1
	trick_added.emit(trick_name, value, multiplier)
	chain_changed.emit(names, multiplier, int(points * multiplier))


## Board state each frame (supported = on the sand).
func update(delta: float, supported: bool) -> void:
	_airborne = not supported
	if not active or _airborne:
		return
	_timer -= delta
	if _timer <= 0.0:
		_bank()


## Touchdown. `clean`: no rotation left over; false = a sketchy landing (kept, no bonus).
## Only a landing out of tricks renews the window (bumps and crests don't).
func on_landed(clean: bool) -> void:
	if not active or _air_tricks == 0:
		_air_tricks = 0
		return
	if clean:
		multiplier += 0.5
		landed_clean.emit(multiplier)
		chain_changed.emit(names, multiplier, int(points * multiplier))
	_air_tricks = 0
	_timer = link_window


## Keeps the chain alive (a jump, a sharp carve linking two tricks).
func touch() -> void:
	if active:
		_timer = maxf(_timer, link_window * 0.6)


func bail() -> void:
	if not active:
		return
	_reset()
	lost.emit()
	chain_changed.emit(names, multiplier, 0)


func _bank() -> void:
	var value := int(points * multiplier)
	total_score += value
	var m := multiplier
	_reset()
	banked.emit(value, m)
	chain_changed.emit(names, multiplier, 0)


func _reset() -> void:
	active = false
	multiplier = 1.0
	points = 0
	names = PackedStringArray()
	_counts.clear()
	_air_tricks = 0
