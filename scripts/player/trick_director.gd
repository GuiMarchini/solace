class_name TrickDirector
extends Node
## The rider's tricks, played the way a skateboarding game plays them (and the way the
## reference's trick showcase does: one jump is one continuous performance). The sword
## physics stay in HoverMotor, the score in ComboTracker.
##
## * Clips: every trick is a short clip of eased keyframes on named channels: pose
##   weights for SpiritModel, offsets of her body and of the sword, her feet, the sword
##   standing on end (slid along under her), taken in hand; plus full turns of her body
##   or of the sword (spins, flips, varials). Clips overlap and add up: full turns sum
##   rather than replace each other, and every channel then goes through a critically
##   damped spring, so nothing ever snaps from one pose to the next.
## * Every real jump plays something by itself, chosen from the airtime; on big air a
##   second move is linked to the first (the sword stood on end, then the rodeo...).
## * Q (`trick_spin`) opens with a rotation, E (`trick_style`) with a flip or a grab;
##   a second press is the follow-up of a combo: QQ the spin carries on into a 720, QE a
##   grab on the way out of the spin, EQ the sword whirled under her, EE the sword taken
##   in hand. A follow-up never cuts the move in progress: it waits for that move's link
##   point and overlaps its ending. A press that does not fit yet stays buffered (held
##   while the jump is charging, for the jump to come; on the sand it becomes a deck trick).
## * Other systems (combat) register clips of their own and play them through the same
##   engine (`register_clips`, `play`): tricks in progress give way to them smoothly.
## * Landing: full turns are timed to finish before touchdown (sped up gently when the
##   ground comes early); in the last moments of the fall every pose eases back into the
##   riding stance; a rotation still unfinished at touchdown is caught over a few frames
##   (a sketchy landing) or, if far off, is a bail. Nothing can leave her stuck in a pose.

signal move_started(move_name: String, title: String, player_made: bool)
## Touchdown after air: clean (nothing left to finish), had tricks this jump.
signal landed(clean: bool, had_tricks: bool)
signal bailed
## A deck trick that throws sand from the inside edge (side: +1 left turn).
signal sand_slash(side: float)
## The deck trick asks the sword for a small pop (m/s up).
signal hop_requested(vy: float)

## What PlayerVisual and SpiritModel read every frame.
class Channels:
	## Rider and sword turning together about her centre of mass (travel frame).
	var body := Quaternion.IDENTITY
	## The sword relative to the deck under her feet: rotation about a point along it
	## (`pivot`, m, + toward the grip), after sliding along its length (`slide`).
	var board := Quaternion.IDENTITY
	var pivot := 0.0
	var slide := 0.0
	## The drawn sword raised toward her feet (m, flips: it pops up to the tucked feet),
	## and moved out to one side (m, + to the right of travel) where the flip shows.
	var rise := 0.0
	var side := 0.0
	## Rider floating above the deck (m): her feet leave the sword.
	var lift := 0.0
	## 1 = the feet follow the drawn sword (nose pressed), 0 = the deck.
	var on_board := 0.0
	## Extra foot offsets (travel frame, m).
	var front := Vector3.ZERO
	var rear := Vector3.ZERO
	## 0..1 the sword held in her right hand, the direction its blade points while held
	## (travel frame: yaw from straight ahead toward her right, pitch up, roll about the
	## blade) and 0..1 her left hand on the grip too.
	var hold := 0.0
	var swing := Vector3.ZERO
	var grip2 := 0.0
	var w := {}

	func _init() -> void:
		for k in TrickDirector.POSE_KEYS:
			w[k] = 0.0

const POSE_KEYS := [&"tuck", &"grab", &"extend", &"kick", &"arm_up", &"crouch", &"tall", &"staff", &"slash", &"press", &"flick"]
const POSE_NAMES := ["tuck", "grab", "extend", "kick", "arm_up", "crouch", "tall", "staff", "slash", "press", "flick"]
## Magnitudes combined by taking the strongest clip (two overlapping clips never double them).
const MAX_SCALARS := ["lift", "on_board", "hold", "grip2", "slide", "b_up"]
const SCALARS := ["lift", "on_board", "hold", "grip2", "swing_yaw", "swing_pitch", "swing_roll", "slide", "b_up", "b_side", "pivot", "yaw", "pitch", "roll", "b_yaw", "b_pitch", "b_roll"]
## Channels mirrored by the move's direction (spins and rolls to either side).
const SIGNED := ["yaw", "roll", "b_yaw", "b_roll", "swing_yaw", "swing_roll"]
const STANCE := 0.28
const V0 := Vector3.ZERO

## The clips. dur: nominal length (s); link: fraction from which a follow-up may start;
## pts: points; title (combo bookkeeping); ground: started on the sand; rot: full turns
## [[0 body / 1 sword, axis 0 yaw / 1 pitch / 2 roll, turns, t0, t1]]; keys: channel ->
## [[t, value], ...], eased between keys, every clip ending at rest.
const CLIPS := {
	# --- Her own moves on every jump ---------------------------------------------------
	"pop_kick": {"title": "Chute", "dur": 0.7, "link": 0.6, "pts": 100, "keys": {
		"kick": [[0.0, 0.0], [0.16, 1.0], [0.62, 1.0], [0.9, 0.0]],
		"arm_up": [[0.0, 0.0], [0.2, 0.45], [0.62, 0.45], [0.9, 0.0]],
		"rear": [[0.0, V0], [0.16, Vector3(0.0, 0.24, 0.3)], [0.62, Vector3(0.0, 0.24, 0.3)], [0.9, V0]],
		"b_pitch": [[0.0, 0.0], [0.16, 0.28], [0.62, 0.28], [0.9, 0.0]]}},
	"tuck_grab": {"title": "Agarrada", "dur": 0.8, "link": 0.55, "pts": 150, "keys": {
		"tuck": [[0.0, 0.0], [0.18, 1.0], [0.72, 1.0], [0.95, 0.0]],
		"grab": [[0.08, 0.0], [0.28, 1.0], [0.68, 1.0], [0.88, 0.0]],
		"b_roll": [[0.08, 0.0], [0.28, 0.3], [0.68, 0.3], [0.88, 0.0]]}},
	"pogo": {"title": "Lâmina em Pé", "dur": 1.05, "link": 0.62, "pts": 300, "keys": {
		# The sword swings up on end under her front foot (slid back so that she stands
		# on its tip, the hilt and its light hanging below), the free leg kicked forward,
		# arms out; then she sinks onto it, knee drawn up, and it swings flat again.
		"b_pitch": [[0.0, 0.0], [0.16, 1.35], [0.66, 1.35], [0.9, 0.0]],
		"slide": [[0.0, 0.0], [0.16, 0.94], [0.66, 0.94], [0.9, 0.0]],
		"pivot": [[0.0, -STANCE], [1.0, -STANCE]],
		"rear": [[0.0, V0], [0.16, Vector3(0.0, 0.4, -0.42)], [0.38, Vector3(0.0, 0.4, -0.42)],
			[0.52, Vector3(0.0, 0.3, -0.12)], [0.66, Vector3(0.0, 0.3, -0.12)], [0.9, V0]],
		"tall": [[0.0, 0.0], [0.16, 1.0], [0.4, 1.0], [0.55, 0.25], [0.66, 0.25], [0.9, 0.0]],
		"crouch": [[0.38, 0.0], [0.52, 0.6], [0.66, 0.6], [0.88, 0.0]],
		"arm_up": [[0.0, 0.0], [0.16, 0.8], [0.4, 0.8], [0.6, 0.25], [0.88, 0.0]]}},
	"rodeo": {"title": "Rodeio", "dur": 1.0, "link": 0.68, "pts": 350, "keys": {
		# She swings round to face the way she flies (the sword turns across under her),
		# sinks onto it and throws one arm up, then swings back to her stance.
		"yaw": [[0.0, 0.0], [0.2, 1.45], [0.7, 1.45], [0.92, 0.0]],
		"crouch": [[0.0, 0.0], [0.2, 1.0], [0.7, 1.0], [0.92, 0.0]],
		"arm_up": [[0.05, 0.0], [0.24, 1.0], [0.7, 1.0], [0.9, 0.0]],
		"lift": [[0.0, 0.0], [0.2, 0.05], [0.7, 0.05], [0.9, 0.0]],
		"b_roll": [[0.0, 0.0], [0.2, 0.25], [0.7, 0.25], [0.9, 0.0]]}},
	"stretch": {"title": "Voo Estendido", "dur": 0.9, "link": 0.6, "pts": 250, "keys": {
		"extend": [[0.0, 0.0], [0.18, 1.0], [0.7, 1.0], [0.9, 0.0]],
		"front": [[0.0, V0], [0.18, Vector3(0.0, 0.14, -0.16)], [0.7, Vector3(0.0, 0.14, -0.16)], [0.9, V0]],
		"rear": [[0.0, V0], [0.18, Vector3(0.0, 0.1, 0.16)], [0.7, Vector3(0.0, 0.1, 0.16)], [0.9, V0]],
		"b_pitch": [[0.0, 0.0], [0.18, 0.32], [0.7, 0.32], [0.9, 0.0]]}},
	# --- Q: the sword spun flat under her (she stays facing ahead) ------------------
	"shuv360": {"title": "Shuv 360", "dur": 0.7, "link": 0.5, "pts": 350,
		"rot": [[1, 0, 1.0, 0.12, 0.8]], "keys": {
		# The back foot scoops the tail round (a sweep back and up), the sword spins flat
		# under her while she rides it out on tucked legs, eyes down, shoulders countering
		# a little; then her feet come down and catch it.
		"front": [[0.0, V0], [0.14, Vector3(0.0, 0.18, 0.0)], [0.3, Vector3(0.0, 0.3, -0.04)],
			[0.76, Vector3(0.0, 0.28, -0.04)], [0.92, V0]],
		"rear": [[0.0, V0], [0.1, Vector3(0.0, 0.08, 0.22)], [0.24, Vector3(0.0, 0.3, 0.12)],
			[0.76, Vector3(0.0, 0.28, 0.04)], [0.92, V0]],
		"yaw": [[0.0, 0.0], [0.2, -0.18], [0.7, -0.1], [0.92, 0.0]],
		"flick": [[0.0, 0.0], [0.1, 0.8], [0.78, 0.8], [0.95, 0.0]],
		"extend": [[0.05, 0.0], [0.2, 0.35], [0.8, 0.35], [0.95, 0.0]],
		"tuck": [[0.1, 0.0], [0.26, 0.65], [0.76, 0.65], [0.92, 0.0]],
		"b_up": [[0.1, 0.0], [0.26, 0.15], [0.74, 0.15], [0.9, 0.0]],
		"crouch": [[0.0, 0.0], [0.07, 0.55], [0.16, 0.0], [0.84, 0.0], [0.93, 0.4], [1.0, 0.0]]}},
	# --- E: flips and grabs --------------------------------------------------------------
	"frontflip": {"title": "Mortal Frontal", "dur": 0.95, "link": 0.68, "pts": 600,
		"rot": [[0, 1, -1.0, 0.04, 0.96]], "keys": {
		"tuck": [[0.0, 0.0], [0.15, 1.0], [0.85, 1.0], [1.0, 0.0]],
		"grab": [[0.15, 0.0], [0.3, 0.5], [0.72, 0.5], [0.88, 0.0]]}},
	"backflip": {"title": "Mortal de Costas", "dur": 0.95, "link": 0.68, "pts": 600,
		"rot": [[0, 1, 1.0, 0.04, 0.96]], "keys": {
		"tuck": [[0.0, 0.0], [0.15, 1.0], [0.85, 1.0], [1.0, 0.0]],
		"grab": [[0.15, 0.0], [0.3, 0.5], [0.72, 0.5], [0.88, 0.0]]}},
	"kickflip": {"title": "Kickflip", "dur": 0.75, "link": 0.55, "pts": 450, "fixed": true,
		"rot": [[1, 2, 1.0, 0.2, 0.78]], "keys": {
		# A quick squat, then she drags the front foot up to the nose (the nose pops up)
		# and kicks it off the side: the sword flies out a little to that side, rises and
		# rolls over there (turned sideways, clear of her cloak, so the flip reads), her
		# shoulders countering the kick and her eyes on it; then it swings back under her
		# feet, they come down, catch it and absorb.
		"b_pitch": [[0.0, 0.0], [0.12, 0.42], [0.26, 0.15], [0.8, 0.06], [0.92, 0.0]],
		"pivot": [[0.0, STANCE], [0.18, STANCE], [0.3, 0.0], [1.0, 0.0]],
		"b_yaw": [[0.14, 0.0], [0.3, 0.45], [0.74, 0.45], [0.9, 0.0]],
		"b_side": [[0.14, 0.0], [0.32, 0.5], [0.7, 0.5], [0.88, 0.0]],
		"b_up": [[0.12, 0.0], [0.3, 0.26], [0.72, 0.26], [0.9, 0.0]],
		"yaw": [[0.1, 0.0], [0.24, -0.15], [0.6, 0.0], [0.9, 0.0]],
		"front": [[0.0, V0], [0.1, Vector3(0.0, 0.04, -0.22)], [0.22, Vector3(0.38, 0.38, -0.46)],
			[0.36, Vector3(0.0, 0.44, -0.06)], [0.74, Vector3(0.0, 0.42, -0.04)], [0.9, V0]],
		"rear": [[0.0, V0], [0.1, Vector3(0.0, 0.0, 0.06)], [0.3, Vector3(0.0, 0.42, 0.04)],
			[0.74, Vector3(0.0, 0.4, 0.04)], [0.9, V0]],
		"crouch": [[0.0, 0.0], [0.07, 0.7], [0.16, 0.0], [0.84, 0.0], [0.93, 0.45], [1.0, 0.0]],
		"flick": [[0.0, 0.0], [0.1, 1.0], [0.78, 1.0], [0.95, 0.0]],
		"extend": [[0.1, 0.0], [0.22, 0.5], [0.4, 0.25], [0.8, 0.25], [0.95, 0.0]],
		"tuck": [[0.2, 0.0], [0.34, 0.8], [0.74, 0.8], [0.9, 0.0]]}},
	"heelflip": {"title": "Heelflip", "dur": 0.75, "link": 0.55, "pts": 450, "fixed": true,
		"rot": [[1, 2, -1.0, 0.2, 0.78]], "keys": {
		# A quick squat, then she drags the front foot up to the nose (the nose pops up)
		# and kicks it off the side: the sword flies out a little to that side, rises and
		# rolls over there (turned sideways, clear of her cloak, so the flip reads), her
		# shoulders countering the kick and her eyes on it; then it swings back under her
		# feet, they come down, catch it and absorb.
		"b_pitch": [[0.0, 0.0], [0.12, 0.42], [0.26, 0.15], [0.8, 0.06], [0.92, 0.0]],
		"pivot": [[0.0, STANCE], [0.18, STANCE], [0.3, 0.0], [1.0, 0.0]],
		"b_yaw": [[0.14, 0.0], [0.3, -0.45], [0.74, -0.45], [0.9, 0.0]],
		"b_side": [[0.14, 0.0], [0.32, -0.5], [0.7, -0.5], [0.88, 0.0]],
		"b_up": [[0.12, 0.0], [0.3, 0.26], [0.72, 0.26], [0.9, 0.0]],
		"yaw": [[0.1, 0.0], [0.24, 0.15], [0.6, 0.0], [0.9, 0.0]],
		"front": [[0.0, V0], [0.1, Vector3(0.0, 0.04, -0.22)], [0.22, Vector3(-0.38, 0.38, -0.46)],
			[0.36, Vector3(0.0, 0.44, -0.06)], [0.74, Vector3(0.0, 0.42, -0.04)], [0.9, V0]],
		"rear": [[0.0, V0], [0.1, Vector3(0.0, 0.0, 0.06)], [0.3, Vector3(0.0, 0.42, 0.04)],
			[0.74, Vector3(0.0, 0.4, 0.04)], [0.9, V0]],
		"crouch": [[0.0, 0.0], [0.07, 0.7], [0.16, 0.0], [0.84, 0.0], [0.93, 0.45], [1.0, 0.0]],
		"flick": [[0.0, 0.0], [0.1, 1.0], [0.78, 1.0], [0.95, 0.0]],
		"extend": [[0.1, 0.0], [0.22, 0.5], [0.4, 0.25], [0.8, 0.25], [0.95, 0.0]],
		"tuck": [[0.2, 0.0], [0.34, 0.8], [0.74, 0.8], [0.9, 0.0]]}},
	"method": {"title": "Method", "dur": 0.7, "link": 0.45, "pts": 250, "keys": {
		"grab": [[0.0, 0.0], [0.2, 1.0], [0.75, 1.0], [0.95, 0.0]],
		"extend": [[0.0, 0.0], [0.2, 0.45], [0.75, 0.45], [0.95, 0.0]],
		"b_pitch": [[0.0, 0.0], [0.2, 0.45], [0.75, 0.45], [0.95, 0.0]],
		"b_roll": [[0.0, 0.0], [0.2, -0.4], [0.75, -0.4], [0.95, 0.0]],
		"rear": [[0.0, V0], [0.2, Vector3(0.0, 0.12, 0.1)], [0.75, Vector3(0.0, 0.12, 0.1)], [0.95, V0]]}},
	# --- Follow-ups (second press) ------------------------------------------------------
	"board_spin": {"title": "Lâmina Giratória", "dur": 0.85, "link": 0.6, "pts": 700,
		"rot": [[1, 0, 2.0, 0.08, 0.9]], "keys": {
		# The sword whirls twice round under her (a glowing arc) while she floats above.
		"lift": [[0.0, 0.0], [0.15, 0.3], [0.8, 0.3], [1.0, 0.0]],
		"front": [[0.0, V0], [0.15, Vector3(0.0, 0.2, 0.0)], [0.8, Vector3(0.0, 0.2, 0.0)], [1.0, V0]],
		"rear": [[0.0, V0], [0.15, Vector3(0.0, 0.2, 0.0)], [0.8, Vector3(0.0, 0.2, 0.0)], [1.0, V0]],
		"tuck": [[0.0, 0.0], [0.15, 0.6], [0.8, 0.6], [1.0, 0.0]],
		"flick": [[0.0, 0.0], [0.15, 0.7], [0.8, 0.7], [1.0, 0.0]]}},
	"varial_flip": {"title": "Varial Flip", "dur": 0.85, "link": 0.55, "pts": 800, "fixed": true,
		"rot": [[1, 0, 1.0, 0.16, 0.8], [1, 2, 1.0, 0.2, 0.8]], "keys": {
		# Scoop and flick at once: the sword spins and rolls together under her.
		"front": [[0.0, V0], [0.12, Vector3(0.0, 0.06, -0.2)], [0.24, Vector3(0.3, 0.3, -0.3)],
			[0.36, Vector3(0.0, 0.32, -0.06)], [0.76, Vector3(0.0, 0.3, -0.04)], [0.92, V0]],
		"rear": [[0.0, V0], [0.12, Vector3(0.0, 0.08, 0.22)], [0.28, Vector3(0.0, 0.3, 0.1)],
			[0.76, Vector3(0.0, 0.28, 0.04)], [0.92, V0]],
		"flick": [[0.0, 0.0], [0.1, 1.0], [0.8, 1.0], [0.95, 0.0]],
		"extend": [[0.1, 0.0], [0.22, 0.45], [0.8, 0.25], [0.95, 0.0]],
		"tuck": [[0.2, 0.0], [0.34, 0.8], [0.76, 0.8], [0.92, 0.0]]}},
	"staff": {"title": "Lâmina na Mão", "dur": 1.05, "link": 0.72, "pts": 800, "keys": {
		# The sword leaves her feet for her hand, held up like a staff while she floats,
		# then goes back underfoot before the landing.
		"hold": [[0.0, 0.0], [0.16, 1.0], [0.74, 1.0], [0.9, 0.0]],
		"swing_yaw": [[0.0, 0.61], [1.0, 0.61]],
		"swing_pitch": [[0.0, 0.92], [1.0, 0.92]],
		"lift": [[0.0, 0.0], [0.16, 0.22], [0.74, 0.22], [0.9, 0.0]],
		"staff": [[0.0, 0.0], [0.16, 1.0], [0.74, 1.0], [0.9, 0.0]],
		"tuck": [[0.0, 0.0], [0.16, 0.5], [0.74, 0.5], [0.9, 0.0]]}},
	# --- On the sand --------------------------------------------------------------------
	"shuv": {"title": "Shuv Pop", "dur": 0.6, "link": 0.6, "pts": 200, "ground": true,
		"rot": [[1, 0, 1.0, 0.12, 0.8]], "keys": {
		# The back foot scoops the tail round (a sweep back and up), the sword spins flat
		# under her while she rides it out on tucked legs, eyes down, shoulders countering
		# a little; then her feet come down and catch it.
		"front": [[0.0, V0], [0.14, Vector3(0.0, 0.18, 0.0)], [0.3, Vector3(0.0, 0.3, -0.04)],
			[0.76, Vector3(0.0, 0.28, -0.04)], [0.92, V0]],
		"rear": [[0.0, V0], [0.1, Vector3(0.0, 0.08, 0.22)], [0.24, Vector3(0.0, 0.3, 0.12)],
			[0.76, Vector3(0.0, 0.28, 0.04)], [0.92, V0]],
		"yaw": [[0.0, 0.0], [0.2, -0.18], [0.7, -0.1], [0.92, 0.0]],
		"flick": [[0.0, 0.0], [0.1, 0.8], [0.78, 0.8], [0.95, 0.0]],
		"extend": [[0.05, 0.0], [0.2, 0.35], [0.8, 0.35], [0.95, 0.0]],
		"tuck": [[0.1, 0.0], [0.26, 0.65], [0.76, 0.65], [0.92, 0.0]],
		"b_up": [[0.1, 0.0], [0.26, 0.15], [0.74, 0.15], [0.9, 0.0]],
		"crouch": [[0.0, 0.0], [0.07, 0.55], [0.16, 0.0], [0.84, 0.0], [0.93, 0.4], [1.0, 0.0]]}},
	"flip_ground": {"title": "Kickflip", "dur": 0.62, "link": 0.6, "pts": 250, "ground": true, "fixed": true,
		"rot": [[1, 2, 1.0, 0.2, 0.78]], "keys": {
		# A quick squat, then she drags the front foot up to the nose (the nose pops up)
		# and kicks it off the side: the sword flies out a little to that side, rises and
		# rolls over there (turned sideways, clear of her cloak, so the flip reads), her
		# shoulders countering the kick and her eyes on it; then it swings back under her
		# feet, they come down, catch it and absorb.
		"b_pitch": [[0.0, 0.0], [0.12, 0.42], [0.26, 0.15], [0.8, 0.06], [0.92, 0.0]],
		"pivot": [[0.0, STANCE], [0.18, STANCE], [0.3, 0.0], [1.0, 0.0]],
		"b_yaw": [[0.14, 0.0], [0.3, 0.45], [0.74, 0.45], [0.9, 0.0]],
		"b_side": [[0.14, 0.0], [0.32, 0.5], [0.7, 0.5], [0.88, 0.0]],
		"b_up": [[0.12, 0.0], [0.3, 0.26], [0.72, 0.26], [0.9, 0.0]],
		"yaw": [[0.1, 0.0], [0.24, -0.15], [0.6, 0.0], [0.9, 0.0]],
		"front": [[0.0, V0], [0.1, Vector3(0.0, 0.04, -0.22)], [0.22, Vector3(0.38, 0.38, -0.46)],
			[0.36, Vector3(0.0, 0.44, -0.06)], [0.74, Vector3(0.0, 0.42, -0.04)], [0.9, V0]],
		"rear": [[0.0, V0], [0.1, Vector3(0.0, 0.0, 0.06)], [0.3, Vector3(0.0, 0.42, 0.04)],
			[0.74, Vector3(0.0, 0.4, 0.04)], [0.9, V0]],
		"crouch": [[0.0, 0.0], [0.07, 0.7], [0.16, 0.0], [0.84, 0.0], [0.93, 0.45], [1.0, 0.0]],
		"flick": [[0.0, 0.0], [0.1, 1.0], [0.78, 1.0], [0.95, 0.0]],
		"extend": [[0.1, 0.0], [0.22, 0.5], [0.4, 0.25], [0.8, 0.25], [0.95, 0.0]],
		"tuck": [[0.2, 0.0], [0.34, 0.8], [0.74, 0.8], [0.9, 0.0]]}},
	"press": {"title": "Nose Press", "dur": 0.9, "link": 0.7, "pts": 150, "ground": true, "keys": {
		# She drops over the front foot, the tail lifts under the back one.
		"b_pitch": [[0.0, 0.0], [0.15, -0.22], [0.8, -0.22], [0.97, 0.0]],
		"pivot": [[0.0, -STANCE], [1.0, -STANCE]],
		"on_board": [[0.0, 0.0], [0.15, 1.0], [0.8, 1.0], [0.97, 0.0]],
		"press": [[0.0, 0.0], [0.15, 1.0], [0.8, 1.0], [0.97, 0.0]]}},
	"slash": {"title": "Corte na Areia", "dur": 0.85, "link": 0.7, "pts": 200, "ground": true, "keys": {
		# Low into the carve, the inside hand cutting the sand.
		"slash": [[0.0, 0.0], [0.12, 1.0], [0.78, 1.0], [0.96, 0.0]],
		"crouch": [[0.0, 0.0], [0.12, 0.8], [0.78, 0.8], [0.96, 0.0]],
		"b_roll": [[0.0, 0.0], [0.12, 0.25], [0.78, 0.25], [0.96, 0.0]]}},
}

## Her own moves on a jump, by airtime: single moves, and linked pairs on big air.
const AUTO_SMALL := ["pop_kick", "tuck_grab"]
const AUTO_MEDIUM := ["pogo", "rodeo", "stretch", "tuck_grab", "staff"]
const AUTO_BIG := [["pogo", "rodeo"], ["rodeo", "stretch"], ["pogo", "staff"], ["stretch", "tuck_grab"], ["rodeo", "staff"]]

@export var enabled := true
@export_group("Timing")
## Full turns may play this much faster than nominal to fit the airtime.
@export var min_speedup := 0.7
## Full turns finish this long before touchdown.
@export var land_margin := 0.12
## In the last part of the fall (s before touchdown) every pose eases back into the
## riding stance.
@export var land_window := 0.38
## How fast a clip may be sped up when the ground comes early (speed per second).
@export var retime_rate := 3.5
## Pause after takeoff before her own move starts (a press right at takeoff wins).
@export var auto_delay := 0.22
## How long her own move takes to give way to a player's trick.
@export var fade_time := 0.18
## Spring time of the channels (s): small = crisp, large = soft.
@export var smooth_time := 0.07
## Time to catch a rotation left unfinished at touchdown.
@export var catch_time := 0.22
## Leftover body rotation (rad) at touchdown for a sketchy landing, and for a bail.
@export var sketchy_angle := 0.35
@export var bail_angle := 1.6
@export_group("Deck tricks")
@export var shuv_pop := 6.5
## |carve| above which E on the deck is a sand slash instead of a nose press.
@export var slash_carve := 0.35

var input := TrickInput.new()
var combo := ComboTracker.new()
## Current output.
var out := Channels.new()
## The newest move ("" = none) and its progress 0..1 (debug / tests).
var move := ""
var progress := 0.0
## Every move played this session (tests check the variety).
var played := {}
## Last move started (debug / tests).
var last := ""
## Fluidity measures (tests): fastest turning of her body (rad/s) and fastest change of
## any pose weight (1/s) seen so far.
var max_body_rate := 0.0
var max_pose_rate := 0.0

## Every clip this engine can play: CLIPS plus those registered by other systems.
var clips := {}

var _rng := RandomNumberGenerator.new()
# Active clips: {c, t, dur, speed, dir, player, w, fade, air, link}.
var _active: Array = []
# Moves waiting for the current one's link point: {c, dir, player}.
var _queue: Array = []
var _air := false
var _last_t_rem := 1.0
var _tricks_this_air := 0
var _last_button := ""
var _auto_wait := 0.0
var _recent_auto: Array[String] = []
var _spin_alt := 1.0
var _e_cycle := 0
var _last_flip := "kickflip"
var _side := 1.0
# Channel springs: name -> value, velocity.
var _cv := {}
var _cvel := {}
# Rotation caught after touchdown: body (yaw, pitch, roll) and sword, and its progress.
var _catch := Vector3.ZERO
var _catch_board := Vector3.ZERO
var _catch_k := 1.0
var _prev_body := Quaternion.IDENTITY


func _ready() -> void:
	clips = CLIPS.duplicate()
	_rng.randomize()
	combo.name = "Combo"
	add_child(combo)
	for k in POSE_NAMES + SCALARS:
		_cv[k] = 0.0
		_cvel[k] = 0.0


## Seconds until the sword reaches the ground below (flat-ground ballistic estimate).
static func time_to_ground(vy: float, height: float, g: float) -> float:
	return (vy + sqrt(maxf(vy * vy + 2.0 * g * maxf(height, 0.0), 0.0))) / g


## `s`: riding, supported, vy, speed, gravity, height (deck above hover height),
## carve (-1..1), steer (-1 right .. 1 left), pitch_input (-1 forward .. 1 back),
## charging (the jump is being held).
func update(delta: float, s: Dictionary) -> void:
	if delta <= 0.0:
		return
	var riding: bool = s["riding"]
	var airborne: bool = riding and not s["supported"]
	var charging: bool = s.get("charging", false)
	input.update(delta, enabled and riding, charging and not airborne)
	var vy: float = s["vy"]
	var t_rem := time_to_ground(vy, s["height"], s["gravity"]) if airborne else 0.0
	_last_t_rem = t_rem
	combo.update(delta, not airborne)
	if airborne and not _air:
		_takeoff(t_rem, vy)
	elif not airborne and _air:
		_touchdown()
	_air = airborne
	if not riding:
		_active.clear()
		_queue.clear()
	_auto_tick(delta, airborne, t_rem, s)
	_read_buttons(s, airborne, t_rem, charging)
	_run_queue(airborne, t_rem, s)
	_advance(delta, airborne, t_rem)
	_evaluate(delta, airborne, t_rem, vy)


# --- Choosing ---------------------------------------------------------------------------

func _takeoff(t_rem: float, vy: float) -> void:
	_tricks_this_air = 0
	_last_button = ""
	_queue.clear()
	if vy >= 1.0 and t_rem >= 0.42:
		# A real jump links tricks; bumps and crests don't.
		combo.touch()
	# A move already playing from the sand (a shuv popping her up) carries on.
	if _lead().is_empty() and enabled and vy >= 1.0 and t_rem >= 0.42:
		_auto_wait = auto_delay


## Her own move on a jump, once the moment for a player's press has passed.
func _auto_tick(delta: float, airborne: bool, t_rem: float, s: Dictionary) -> void:
	if _auto_wait <= 0.0:
		return
	_auto_wait -= delta
	if _auto_wait > 0.0:
		return
	if not airborne or not _lead().is_empty() or t_rem < 0.35:
		return
	if t_rem >= 1.45:
		var pairs := AUTO_BIG.filter(func(p: Array) -> bool: return not _recent_auto.has(p[0]))
		var pair: Array = pairs[_rng.randi() % pairs.size()] if not pairs.is_empty() else AUTO_BIG[0]
		_remember_auto(pair[0])
		_start(pair[0], t_rem, false, _dir_for(s, pair[0]), true)
		_queue.append({"c": pair[1], "dir": _dir_for(s, pair[1]), "player": false})
		return
	var pool: Array = AUTO_MEDIUM if t_rem >= 0.8 else AUTO_SMALL
	pool = pool.filter(func(m: String) -> bool: return not _recent_auto.has(m) and _fits(m, t_rem))
	if pool.is_empty():
		return
	var m: String = pool[_rng.randi() % pool.size()]
	_remember_auto(m)
	_start(m, t_rem, false, _dir_for(s, m), true)


func _remember_auto(m: String) -> void:
	_recent_auto.append(m)
	while _recent_auto.size() > 2:
		_recent_auto.pop_front()


func _read_buttons(s: Dictionary, airborne: bool, t_rem: float, charging: bool) -> void:
	if not input.has_pending():
		return
	if attack_active():
		input.clear()
		return
	var b := input.peek()
	if airborne:
		var lead := _lead_player()
		if lead.is_empty() and not _queue.any(func(q: Dictionary) -> bool: return q["player"]):
			# The opening: her own move gives way to it.
			var m := _opening(b, t_rem, s)
			if m == "":
				return
			input.consume()
			_fade_auto()
			_start(m, t_rem, true, _dir_for(s, m), true)
			_last_button = b
			return
		if _queue.is_empty():
			# The follow-up, waiting for the move in progress to reach its link point.
			var wait := _time_to_link(lead) if not lead.is_empty() else 0.0
			var m := _follow_up(_last_button, b, maxf(t_rem - wait, 0.0))
			if m == "":
				return
			input.consume()
			_queue.append({"c": m, "dir": _dir_for(s, m), "player": true})
			_last_button = b
		return
	if charging:
		return
	# On the sand: deck tricks, chained the same way.
	var m := _deck_trick(b, s)
	if _lead().is_empty() and _queue.is_empty():
		input.consume()
		_start_deck(m, s)
	elif _queue.is_empty():
		input.consume()
		_queue.append({"c": m, "dir": _dir_for(s, m), "player": true})


## The opening move a button means in the air.
func _opening(b: String, t_rem: float, s: Dictionary) -> String:
	if b == "Q":
		return "shuv360" if _fits("shuv360", t_rem) else ""
	# E: the sword flipped by her kick (kickflip and heelflip in turn); S + E: a backflip.
	if float(s["pitch_input"]) > 0.3 and _fits("backflip", t_rem):
		return "backflip"
	var flip := "kickflip" if _e_cycle % 2 == 0 else "heelflip"
	if _fits(flip, t_rem):
		_e_cycle += 1
		_last_flip = flip
		return flip
	return "method" if _fits("method", t_rem) else ""


## The follow-up of a combo (the previous press and this one), fitting the air left.
func _follow_up(prev: String, b: String, t_avail: float) -> String:
	var options: Array = []
	match prev + b:
		"QQ":
			options = ["shuv360"]
		"QE":
			options = ["varial_flip", _last_flip]
		"EQ":
			options = ["board_spin", "shuv360"]
		"EE":
			# The same flip again: the rolls add up into a double flip.
			options = [_last_flip, "method"]
	for m in options:
		if _fits(m, t_avail):
			return m
	return ""


func _deck_trick(b: String, s: Dictionary) -> String:
	if b == "Q":
		return "shuv"
	return "slash" if absf(float(s["carve"])) > slash_carve else "flip_ground"


func _start_deck(m: String, s: Dictionary) -> void:
	_side = signf(float(s["carve"])) if absf(float(s["carve"])) > 0.05 else 1.0
	if m == "shuv" or m == "flip_ground":
		hop_requested.emit(shuv_pop)
	elif m == "slash":
		sand_slash.emit(_side)
	_start(m, 2.0, true, _dir_for(s, m), false)


func _dir_for(s: Dictionary, m: String) -> float:
	if m == "slash":
		return -_side
	var steer: float = s["steer"]
	if absf(steer) > 0.3:
		return signf(steer)
	_spin_alt = -_spin_alt
	return _spin_alt


static func _rot_end(clip: Dictionary) -> float:
	var end := 0.0
	for r in clip.get("rot", []):
		end = maxf(end, float(r[4]))
	return end


## Whether a clip fits the airtime left: its full turns at the fastest allowed pace, or
## a good part of its poses (they ease out by themselves before the landing).
func _fits(m: String, t_rem: float) -> bool:
	var clip: Dictionary = clips[m]
	var end := _rot_end(clip)
	var need := end * float(clip["dur"]) * min_speedup if end > 0.0 else float(clip["dur"]) * 0.55
	return need + land_margin <= t_rem


func _start(m: String, t_rem: float, by_player: bool, dir: float, airborne: bool) -> Dictionary:
	var clip: Dictionary = clips[m]
	var dur: float = clip["dur"]
	if clip.get("fixed", false):
		dir = 1.0
	var speed := 1.0
	var end := _rot_end(clip)
	if airborne and end > 0.0 and not clip.get("attack", false):
		speed = clampf(end * dur / maxf(t_rem - land_margin, 0.05), 1.0, 1.0 / min_speedup)
	var inst := {"c": m, "t": 0.0, "dur": dur, "speed": speed, "dir": dir, "player": by_player,
		"w": 1.0, "fade": false, "air": airborne, "link": float(clip.get("link", 0.6)),
		"attack": clip.get("attack", false),
		"persist": clip.get("persist", clip.get("attack", false) and not clip.get("until_landing", false))}
	_active.append(inst)
	move = m
	last = m
	played[m] = played.get(m, 0) + 1
	if inst["attack"]:
		return inst
	if airborne:
		_tricks_this_air += 1
	var title: String = clip["title"]
	combo.add_trick(title, clip["pts"], by_player)
	move_started.emit(m, title, by_player)
	return inst


## Adds clips another system plays through this engine (see CLIPS for the format;
## "attack": true keeps them out of the trick combo and out of the landing prep, and
## keeps them going through a touchdown unless "until_landing": true; "persist": true
## keeps any clip going through a touchdown, "no_prep": true keeps its pose down to the
## sand).
func register_clips(extra: Dictionary) -> void:
	clips.merge(extra, true)


## Plays a registered clip now: everything in progress gives way to it, attacks too
## (poses ease away, turns are caught smoothly). If the sword is already in her hand it
## stays there until this clip has it in hand too (no dip toward her feet between two
## blows). Returns the clip instance (its "t" / "dur" give progress).
func play(m: String, dir: float, airborne: bool, t_rem := 2.0) -> Dictionary:
	var held: bool = _cv["hold"] > 0.5
	interrupt(false)
	_auto_wait = 0.0
	var inst := _start(m, t_rem if airborne else 2.0, true, dir, airborne)
	inst["held_until"] = _hold_peak(clips[m]) if held else -1.0
	return inst


## Clip fraction where its sword hold first reaches the hand (0 if it never holds it).
static func _hold_peak(clip: Dictionary) -> float:
	for k in clip["keys"].get("hold", []):
		if float(k[1]) >= 0.99:
			return float(k[0])
	return 0.0


## Everything playing gives way (attacks included unless `keep_attacks`).
func interrupt(keep_attacks := true) -> void:
	_queue.clear()
	_catch_rotations(func(i: Dictionary) -> bool: return not (keep_attacks and i["attack"]))


## True while an attack clip (not giving way) is playing.
func attack_active() -> bool:
	for inst in _active:
		if inst["attack"] and not inst["fade"]:
			return true
	return false


## Removes the clips `pred` selects; whatever they were still turning is caught over
## a few frames (shortest way round) instead of snapping back.
func _catch_rotations(pred: Callable) -> void:
	var gone := _active.filter(pred)
	if gone.is_empty():
		return
	var rot := _rotations(false, false, gone)
	var body: Vector3 = rot[0]
	var sword: Vector3 = rot[1]
	_catch = _catch * _catch_weight() + Vector3(wrapf(body.x, -PI, PI), wrapf(body.y, -PI, PI), wrapf(body.z, -PI, PI))
	_catch_board = _catch_board * _catch_weight() + Vector3(wrapf(sword.x, -PI, PI), wrapf(sword.y, -PI, PI), wrapf(sword.z, -PI, PI))
	_catch_k = 0.0
	_active = _active.filter(func(i: Dictionary) -> bool: return not pred.call(i))


## The newest active clip that is not giving way ({} if none).
func _lead() -> Dictionary:
	for i in range(_active.size() - 1, -1, -1):
		if not _active[i]["fade"]:
			return _active[i]
	return {}


func _lead_player() -> Dictionary:
	for i in range(_active.size() - 1, -1, -1):
		if _active[i]["player"] and not _active[i]["fade"]:
			return _active[i]
	return {}


## Seconds until a clip reaches its link point.
func _time_to_link(inst: Dictionary) -> float:
	return maxf(float(inst["link"]) * float(inst["dur"]) - float(inst["t"]), 0.0) / maxf(float(inst["speed"]), 0.01)


## Her own moves give way to a player's trick: faded out, or, if it has barely begun,
## let go at once (the channel springs still ease it away, without mixing its pose into
## the player's trick).
func _fade_auto() -> void:
	_auto_wait = 0.0
	_active = _active.filter(func(i: Dictionary) -> bool: return i["player"] or float(i["t"]) >= 0.3)
	for inst in _active:
		if not inst["player"]:
			inst["fade"] = true
	_queue = _queue.filter(func(q: Dictionary) -> bool: return q["player"])


## Starts the next queued move once the one in progress reaches its link point.
func _run_queue(airborne: bool, t_rem: float, s: Dictionary) -> void:
	if _queue.is_empty():
		return
	var lead := _lead()
	if not lead.is_empty() and float(lead["t"]) < float(lead["link"]) * float(lead["dur"]):
		return
	var q: Dictionary = _queue.pop_front()
	var m: String = q["c"]
	var ground: bool = clips[m].get("ground", false)
	if airborne != (not ground):
		return
	if airborne:
		if _fits(m, t_rem):
			_start(m, t_rem, q["player"], q["dir"], true)
		return
	_start_deck(m, s)


func _touchdown() -> void:
	_auto_wait = 0.0
	_queue.clear()
	var had := _tricks_this_air > 0
	# Whatever is still turning is caught over a few frames (shortest way round).
	var tricks_rot := _rotations(true, true)
	var t_body: Vector3 = tricks_rot[0]
	var leftover := maxf(absf(wrapf(t_body.x, -PI, PI)), maxf(absf(wrapf(t_body.y, -PI, PI)), absf(wrapf(t_body.z, -PI, PI))))
	_catch_rotations(func(i: Dictionary) -> bool: return i["air"] and not i["persist"])
	if leftover > bail_angle:
		combo.bail()
		bailed.emit()
		landed.emit(false, had)
		return
	var clean := leftover <= sketchy_angle
	combo.on_landed(clean)
	landed.emit(clean, had)


# --- Playing ---------------------------------------------------------------------------

func _advance(delta: float, airborne: bool, t_rem: float) -> void:
	for inst in _active:
		if inst["fade"]:
			inst["w"] = move_toward(inst["w"], 0.0, delta / fade_time)
		var clip: Dictionary = clips[inst["c"]]
		var end := _rot_end(clip)
		var f: float = inst["t"] / inst["dur"]
		# (Attacks keep their own pace: they go on through the landing.)
		if airborne and inst["air"] and end > f and not inst["attack"]:
			# Timed against the ground: the turn is done before touchdown, sped up gently.
			var want := (end - f) * float(inst["dur"]) / maxf(t_rem - land_margin, 0.04)
			if want > inst["speed"]:
				inst["speed"] = minf(move_toward(inst["speed"], want, retime_rate * delta), 2.4)
		inst["t"] += delta * float(inst["speed"])
	_active = _active.filter(func(i: Dictionary) -> bool: return i["t"] < i["dur"] and not (i["fade"] and i["w"] <= 0.0))
	var lead := _lead()
	move = lead["c"] if not lead.is_empty() else ""
	progress = clampf(float(lead["t"]) / float(lead["dur"]), 0.0, 1.0) if not lead.is_empty() else 0.0
	_catch_k = minf(_catch_k + delta / catch_time, 1.0)


func _catch_weight() -> float:
	return 1.0 - smoothstep(0.0, 1.0, _catch_k)


## Sum of the full turns in progress: [body (yaw, pitch, roll), sword (yaw, pitch, roll)].
func _rotations(air_only: bool, tricks_only := false, only: Array = []) -> Array:
	var body := Vector3.ZERO
	var sword := Vector3.ZERO
	for inst in (only if not only.is_empty() else _active):
		if air_only and not inst["air"]:
			continue
		if tricks_only and inst["attack"]:
			continue
		var clip: Dictionary = clips[inst["c"]]
		var f := clampf(float(inst["t"]) / float(inst["dur"]), 0.0, 1.0)
		for r in clip.get("rot", []):
			var k := clampf((f - float(r[3])) / maxf(float(r[4]) - float(r[3]), 0.001), 0.0, 1.0)
			var axis := int(r[1])
			var a := TAU * float(r[2]) * _turn(k) * (1.0 if axis == 1 else float(inst["dir"]))
			var v := Vector3(a if axis == 0 else 0.0, a if axis == 1 else 0.0, a if axis == 2 else 0.0)
			if int(r[0]) == 0:
				body += v
			else:
				sword += v
	return [body, sword]


## Slow wind-up, fast middle, soft finish.
static func _turn(t: float) -> float:
	return (0.5 - 0.5 * cos(PI * t)) * 0.65 + t * t * (3.0 - 2.0 * t) * 0.35


## A keyframed channel at clip fraction `f` (eased between keys).
static func _key(keys: Array, f: float) -> Variant:
	var n := keys.size()
	if f <= float(keys[0][0]):
		return keys[0][1]
	for i in range(1, n):
		if f <= float(keys[i][0]):
			var a: Array = keys[i - 1]
			var b: Array = keys[i]
			var span := maxf(float(b[0]) - float(a[0]), 0.0001)
			var k := (f - float(a[0])) / span
			k = k * k * (3.0 - 2.0 * k)
			return lerp(a[1], b[1], k)
	return keys[n - 1][1]


func _evaluate(delta: float, airborne: bool, t_rem: float, vy: float) -> void:
	var tgt := {}
	var front := Vector3.ZERO
	var rear := Vector3.ZERO
	var piv_sum := 0.0
	var piv_w := 0.0
	# The last moments of the fall: back into the riding stance for the landing (but
	# a strike aimed at the sand keeps its pose down to it).
	var keep := 1.0
	if airborne and vy < 0.0:
		keep = smoothstep(land_margin, land_window, t_rem)
	for inst in _active:
		var clip: Dictionary = clips[inst["c"]]
		var f := clampf(float(inst["t"]) / float(inst["dur"]), 0.0, 1.0)
		var w: float = inst["w"] * (1.0 if clip.get("no_prep", false) or inst["attack"] else keep)
		var dir: float = inst["dir"]
		var keys: Dictionary = clip["keys"]
		for key in keys:
			var v: Variant = _key(keys[key], f)
			match key:
				"front":
					var fv := (v as Vector3) * w
					if fv.length_squared() > front.length_squared():
						front = fv
				"rear":
					var rv := (v as Vector3) * w
					if rv.length_squared() > rear.length_squared():
						rear = rv
				"pivot":
					var bp := absf(float(_key(keys.get("b_pitch", [[0.0, 0.0]]), f))) + 0.001
					piv_sum += float(v) * bp
					piv_w += bp
				_:
					var x := float(v)
					if key in SIGNED:
						x *= dir
					elif key == "hold" and f <= float(inst.get("held_until", -1.0)):
						x = 1.0
					if key in POSE_NAMES or key in MAX_SCALARS:
						tgt[key] = maxf(tgt.get(key, 0.0), x * w)
					else:
						tgt[key] = tgt.get(key, 0.0) + x * w
	tgt["pivot"] = piv_sum / piv_w if piv_w > 0.0 else 0.0
	var prev_w := {}
	for k in POSE_NAMES:
		prev_w[k] = _cv[k]
	for k in POSE_NAMES + SCALARS:
		var target: float = tgt.get(k, 0.0)
		_spring(k, target, smooth_time * (1.3 if k == "hold" else 1.0), delta)
	front = _spring_v("front", front, delta)
	rear = _spring_v("rear", rear, delta)
	var rot := _rotations(false)
	var body: Vector3 = rot[0] + _catch * _catch_weight()
	var sword: Vector3 = rot[1] + _catch_board * _catch_weight()
	var c := Channels.new()
	c.body = Quaternion(Vector3.UP, body.x + _cv["yaw"]) * Quaternion(Vector3.RIGHT, body.y + _cv["pitch"]) \
			* Quaternion(Vector3.BACK, body.z + _cv["roll"])
	c.board = Quaternion(Vector3.UP, sword.x + _cv["b_yaw"]) * Quaternion(Vector3.RIGHT, sword.y + _cv["b_pitch"]) \
			* Quaternion(Vector3.BACK, sword.z + _cv["b_roll"])
	c.pivot = _cv["pivot"]
	c.slide = _cv["slide"]
	c.rise = _cv["b_up"]
	c.side = _cv["b_side"]
	c.lift = _cv["lift"]
	c.on_board = clampf(_cv["on_board"], 0.0, 1.0)
	c.hold = clampf(_cv["hold"], 0.0, 1.0)
	c.grip2 = clampf(_cv["grip2"], 0.0, 1.0)
	c.swing = Vector3(_cv["swing_yaw"], _cv["swing_pitch"], _cv["swing_roll"])
	c.front = front
	c.rear = rear
	for i in POSE_KEYS.size():
		c.w[POSE_KEYS[i]] = clampf(_cv[POSE_NAMES[i]], 0.0, 1.0)
	# Fluidity measures.
	max_body_rate = maxf(max_body_rate, turn_angle(_prev_body, c.body) / delta)
	_prev_body = c.body
	for k in POSE_NAMES:
		max_pose_rate = maxf(max_pose_rate, absf(float(_cv[k]) - float(prev_w[k])) / delta)
	out = c


## Angle (rad, 0..PI) between two orientations (q and -q are the same orientation).
static func turn_angle(a: Quaternion, b: Quaternion) -> float:
	var ang := (a.inverse() * b).get_angle()
	return TAU - ang if ang > PI else ang


## Critically damped spring ("smooth damp") of a named channel toward `target`.
func _spring(k: String, target: float, st: float, dt: float) -> float:
	var cur: float = _cv.get(k, 0.0)
	var vel: float = _cvel.get(k, 0.0)
	var omega := 2.0 / maxf(st, 0.0001)
	var x := omega * dt
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := cur - target
	var temp := (vel + omega * change) * dt
	vel = (vel - omega * temp) * e
	cur = target + (change + temp) * e
	_cv[k] = cur
	_cvel[k] = vel
	return cur


func _spring_v(k: String, target: Vector3, dt: float) -> Vector3:
	return Vector3(_spring(k + "_x", target.x, smooth_time, dt), _spring(k + "_y", target.y, smooth_time, dt),
			_spring(k + "_z", target.z, smooth_time, dt))
