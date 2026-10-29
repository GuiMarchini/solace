class_name CombatDirector
extends Node
## Fighting from the sword. She leaps off it, it flies up into her hand, she strikes, and
## it returns under her feet before she lands, all without leaving the ride: attacks are
## clips played through TrickDirector (same springs, poses and landing as the tricks),
## the sword in hand follows each stroke (PlayerVisual places it in her grip, her arm
## reaching along the blade), and HoverMotor carries the momentum (launch, dash, dive).
##
## * Input: Input Map actions only (ACTIONS, rebindable), read in one place. A press made
##   while an attack plays is buffered and starts at that attack's link point, so attacks
##   chain without cutting each other. Missed attacks just finish; nothing locks her.
## * Attacks: a light string (diagonal cut, rising backhand with a kick, pirouette, and a
##   flipping cleave that cracks the sand), shadow spin (two whirling turns, hits twice),
##   phantom dash (homes on a target ahead, scales with speed, whirls out of it), spirit
##   breaker (launch with a front flip, two-handed overhead, dive, strike, shockwave) and,
##   with full spirit energy, the Last Spirit (the sword dissolves, a spectral blade forms,
##   a strike that shakes the dunes).
## * Control: while an attack plays the ride eases down to a fighting pace (ATTACK_SPEED).
## * Cinema: big blows land in slow motion with a push-in of the camera and a flash of
##   light; the camera draws in on the sentinel being fought and leans into whirls.
## * Hits: judged by distance to the blade (or around her / along the dash / around an
##   impact), once per target per attack. A hit in the air rebounds her (Ghost Rebound)
##   and opens a window where Space is an air jump for a follow-up.
## * Feedback: hit-stop, a restrained camera shake on heavy hits, sparks and smoke where
##   the blade connects, smoke trails along its real path; combos (variety pays) brighten
##   the runes and build spirit energy. No text on screen.

signal attack_started(attack: String)
signal hit_landed(target: Node3D, heavy: bool, combo: int)
signal impact(point: Vector3, strength: float)
signal state_changed(state: int)
signal combo_ended(hits: int, style: float)
signal special_ready
## Space pressed in the Ghost Rebound window (the air jump).
signal air_jumped

enum SwordState { SURFING, ENTERING_ATTACK, HELD_FOR_ATTACK, ATTACKING, RETURNING_TO_SURF, SURFING_RECOVERY }
const STATE_NAMES := ["SURFING", "ENTERING_ATTACK", "HELD_FOR_ATTACK", "ATTACKING", "RETURNING_TO_SURF", "SURFING_RECOVERY"]

## Attack -> Input Map action (bindings live in the Input Map).
const ACTIONS := {"light": &"attack_light", "heavy": &"attack_heavy", "spin": &"attack_spin",
	"dash": &"attack_dash", "special": &"attack_special"}

const V0 := Vector3.ZERO
## Clips played through TrickDirector (its format; swing_* aim the held blade in the
## travel frame: yaw from straight ahead toward her right (she faces +90 deg), pitch up).
const ATTACK_CLIPS := {
	# The light string: four different blows, each flowing out of the last (wind-up ->
	# fast cut -> held follow-through). The first one kicks the sword up off her feet: it
	# turns over once in the air and lands in her hand; chained blows keep it there.
	"slash_a": {"title": "Corte", "dur": 0.66, "link": 0.48, "pts": 0, "attack": true, "keys": {
		# Coiled away with the blade cocked high over her shoulder, then a diagonal cut
		# down across her front, the body unwinding into it.
		"crouch": [[0.0, 0.0], [0.05, 0.6], [0.16, 0.0]],
		"kick": [[0.03, 0.0], [0.11, 0.6], [0.26, 0.0]],
		"hold": [[0.03, 0.0], [0.3, 1.0], [0.74, 1.0], [0.97, 0.0]],
		"swing_yaw": [[0.0, 1.9], [0.3, 2.45], [0.36, 2.55], [0.5, -0.55], [0.74, -0.55], [0.97, 0.9]],
		"swing_pitch": [[0.0, 0.6], [0.3, 1.15], [0.36, 1.2], [0.5, -0.65], [0.74, -0.6], [0.97, 0.0]],
		"swing_roll": [[0.0, 0.0], [0.3, 0.4], [0.5, 1.1], [0.74, 1.1], [0.97, 0.0]],
		"yaw": [[0.1, 0.0], [0.36, -0.35], [0.5, 0.6], [0.8, 0.2], [1.0, 0.0]],
		"roll": [[0.15, 0.0], [0.36, 0.14], [0.5, -0.26], [0.85, 0.0]],
		"tuck": [[0.1, 0.0], [0.3, 0.4], [0.74, 0.4], [0.95, 0.0]]}},
	"slash_b": {"title": "Corte", "dur": 0.62, "link": 0.48, "pts": 0, "attack": true, "keys": {
		# The backhand: dropped low across, then ripped up and over to the other side,
		# one leg kicking high with it.
		"crouch": [[0.0, 0.0], [0.05, 0.5], [0.16, 0.0]],
		"hold": [[0.03, 0.0], [0.3, 1.0], [0.74, 1.0], [0.97, 0.0]],
		"swing_yaw": [[0.0, -0.2], [0.3, -0.5], [0.36, -0.55], [0.52, 2.4], [0.74, 2.4], [0.97, 0.9]],
		"swing_pitch": [[0.0, -0.3], [0.3, -0.55], [0.36, -0.6], [0.52, 1.1], [0.74, 1.0], [0.97, 0.0]],
		"swing_roll": [[0.0, 0.0], [0.3, -0.4], [0.52, -1.1], [0.74, -1.1], [0.97, 0.0]],
		"yaw": [[0.1, 0.0], [0.36, 0.38], [0.52, -0.55], [0.8, -0.15], [1.0, 0.0]],
		"roll": [[0.15, 0.0], [0.36, -0.16], [0.52, 0.22], [0.85, 0.0]],
		"kick": [[0.3, 0.0], [0.46, 0.85], [0.68, 0.0]],
		"tuck": [[0.1, 0.0], [0.3, 0.3], [0.74, 0.3], [0.95, 0.0]]}},
	"slash_c": {"title": "Corte", "dur": 0.72, "link": 0.56, "pts": 0, "attack": true,
		"rot": [[0, 0, 1.0, 0.22, 0.68]], "keys": {
		# A pirouette: the blade laid flat at arm's length, she whirls once, leaning in.
		"crouch": [[0.0, 0.0], [0.06, 0.4], [0.16, 0.0]],
		"hold": [[0.03, 0.0], [0.26, 1.0], [0.8, 1.0], [0.97, 0.0]],
		"swing_yaw": [[0.0, 1.2], [0.22, 1.45], [1.0, 1.45]],
		"swing_pitch": [[0.0, 0.3], [0.22, 0.05], [0.68, 0.05], [0.95, 0.0]],
		"swing_roll": [[0.0, 0.0], [0.22, 1.4], [0.68, 1.4], [0.95, 0.0]],
		"extend": [[0.15, 0.0], [0.28, 0.7], [0.66, 0.7], [0.86, 0.0]],
		"roll": [[0.15, 0.0], [0.3, -0.22], [0.66, -0.22], [0.9, 0.0]],
		"tuck": [[0.15, 0.0], [0.3, 0.35], [0.66, 0.35], [0.9, 0.0]]}},
	"slash_d": {"title": "Corte", "dur": 0.95, "link": 0.82, "pts": 0, "attack": true,
		"rot": [[0, 1, -1.0, 0.12, 0.55]], "keys": {
		# The finisher: a leap into a front flip, both hands on the hilt over her head,
		# then a cleave straight down that cracks the sand.
		"crouch": [[0.0, 0.0], [0.06, 0.8], [0.14, 0.0], [0.7, 0.0], [0.8, 0.6], [1.0, 0.0]],
		"tuck": [[0.12, 0.0], [0.25, 0.9], [0.5, 0.9], [0.6, 0.2], [0.85, 0.2], [1.0, 0.0]],
		"hold": [[0.03, 0.0], [0.25, 1.0], [0.82, 1.0], [0.98, 0.0]],
		"grip2": [[0.3, 0.0], [0.5, 1.0], [0.8, 1.0], [0.95, 0.0]],
		"swing_yaw": [[0.0, 1.571], [1.0, 1.571]],
		"swing_pitch": [[0.0, 0.6], [0.5, 1.9], [0.58, 1.95], [0.68, -0.95], [0.82, -0.9], [0.98, 0.0]],
		"roll": [[0.5, 0.0], [0.58, 0.25], [0.68, -0.45], [0.85, -0.3], [1.0, 0.0]]}},
	"spin_r": {"title": "Giro", "dur": 0.82, "link": 0.68, "pts": 0, "attack": true,
		"rot": [[0, 0, 2.0, 0.16, 0.76]], "keys": {
		# A hop and two whirling turns, tilted like a top, the blade flat at arm's length:
		# it cuts a double circle around her.
		"crouch": [[0.0, 0.0], [0.06, 0.6], [0.16, 0.0]],
		"kick": [[0.03, 0.0], [0.1, 0.5], [0.2, 0.0]],
		"hold": [[0.02, 0.0], [0.2, 1.0], [0.8, 1.0], [0.97, 0.0]],
		"swing_yaw": [[0.0, 1.35], [1.0, 1.35]],
		"swing_pitch": [[0.0, 0.4], [0.18, -0.12], [0.76, -0.12], [0.95, 0.0]],
		"swing_roll": [[0.15, 0.0], [0.25, 1.4], [0.76, 1.4], [0.95, 0.0]],
		"extend": [[0.1, 0.0], [0.22, 0.75], [0.76, 0.75], [0.92, 0.0]],
		"roll": [[0.12, 0.0], [0.25, -0.3], [0.76, -0.3], [0.92, 0.0]],
		"tuck": [[0.12, 0.0], [0.25, 0.6], [0.76, 0.6], [0.92, 0.0]]}},
	"spin_l": {"title": "Giro", "dur": 0.82, "link": 0.68, "pts": 0, "attack": true,
		"rot": [[0, 0, -2.0, 0.16, 0.76]], "keys": {
		"crouch": [[0.0, 0.0], [0.06, 0.6], [0.16, 0.0]],
		"kick": [[0.03, 0.0], [0.1, 0.5], [0.2, 0.0]],
		"hold": [[0.02, 0.0], [0.2, 1.0], [0.8, 1.0], [0.97, 0.0]],
		"swing_yaw": [[0.0, 1.35], [1.0, 1.35]],
		"swing_pitch": [[0.0, 0.4], [0.18, -0.12], [0.76, -0.12], [0.95, 0.0]],
		"swing_roll": [[0.15, 0.0], [0.25, -1.4], [0.76, -1.4], [0.95, 0.0]],
		"extend": [[0.1, 0.0], [0.22, 0.75], [0.76, 0.75], [0.92, 0.0]],
		"roll": [[0.12, 0.0], [0.25, -0.3], [0.76, -0.3], [0.92, 0.0]],
		"tuck": [[0.12, 0.0], [0.25, 0.6], [0.76, 0.6], [0.92, 0.0]]}},
	"dash": {"title": "Investida", "dur": 0.92, "link": 0.64, "pts": 0, "attack": true,
		"rot": [[0, 0, 1.0, 0.58, 0.88]], "keys": {
		# Coils low, then shoots forward with the sword thrust out in both hands, body
		# stretched flat, one leg trailing; past the target she whirls out of it once.
		"crouch": [[0.0, 0.0], [0.08, 0.85], [0.18, 0.2], [0.26, 0.0]],
		"hold": [[0.03, 0.0], [0.22, 1.0], [0.84, 1.0], [0.98, 0.0]],
		"grip2": [[0.12, 0.0], [0.24, 0.8], [0.55, 0.8], [0.64, 0.0]],
		"yaw": [[0.08, 0.0], [0.22, -1.1], [0.55, -1.1], [0.7, -0.5], [0.95, 0.0]],
		"roll": [[0.08, 0.0], [0.22, -0.42], [0.55, -0.42], [0.7, -0.1], [0.95, 0.0]],
		"swing_yaw": [[0.0, 1.6], [0.22, 1.1], [0.55, 1.1], [0.62, 1.4], [0.88, 1.4], [0.98, 0.9]],
		"swing_pitch": [[0.0, 0.3], [0.22, -0.1], [0.55, -0.1], [0.62, 0.05], [0.98, 0.0]],
		"swing_roll": [[0.55, 0.0], [0.62, 1.3], [0.88, 1.3], [0.98, 0.0]],
		"extend": [[0.12, 0.0], [0.26, 0.45], [0.55, 0.45], [0.62, 0.7], [0.86, 0.7], [0.96, 0.0]],
		"rear": [[0.1, V0], [0.26, Vector3(0.0, 0.2, 0.25)], [0.55, Vector3(0.0, 0.2, 0.25)], [0.66, V0]]}},
	"breaker_up": {"title": "Ruptura", "dur": 0.9, "link": 1.0, "pts": 0, "attack": true,
		"rot": [[0, 1, -1.0, 0.3, 0.9]], "keys": {
		# A deep gather, the leap, the sword pulled up into both hands over her head
		# and a whole front flip around it on the way up.
		"crouch": [[0.0, 0.0], [0.16, 1.0], [0.28, 0.0]],
		"kick": [[0.14, 0.0], [0.22, 0.5], [0.34, 0.0]],
		"hold": [[0.16, 0.0], [0.4, 1.0], [1.0, 1.0]],
		"grip2": [[0.3, 0.0], [0.5, 1.0], [1.0, 1.0]],
		"swing_yaw": [[0.0, 1.571], [1.0, 1.571]],
		"swing_pitch": [[0.0, 0.2], [0.4, 1.1], [0.8, 1.9], [1.0, 1.9]],
		"roll": [[0.25, 0.0], [0.85, 0.22], [1.0, 0.22]],
		"tuck": [[0.25, 0.0], [0.4, 0.85], [0.8, 0.85], [1.0, 0.55]]}},
	"breaker_dive": {"title": "Ruptura", "dur": 3.0, "link": 1.0, "pts": 0, "attack": true, "no_prep": true, "until_landing": true, "keys": {
		"hold": [[0.0, 1.0], [1.0, 1.0]],
		"grip2": [[0.0, 1.0], [1.0, 1.0]],
		"swing_yaw": [[0.0, 1.571], [1.0, 1.571]],
		"swing_pitch": [[0.0, 1.9], [1.0, 1.9]],
		"roll": [[0.0, 0.22], [1.0, 0.22]],
		"tuck": [[0.0, 0.55], [0.06, 0.3], [1.0, 0.3]]}},
	"breaker_strike": {"title": "Ruptura", "dur": 0.3, "link": 1.0, "pts": 0, "attack": true, "no_prep": true, "until_landing": true, "keys": {
		# The overhead blow, folding over it, just before the sand.
		"hold": [[0.0, 1.0], [1.0, 1.0]],
		"grip2": [[0.0, 1.0], [1.0, 1.0]],
		"swing_yaw": [[0.0, 1.571], [1.0, 1.571]],
		"swing_pitch": [[0.0, 1.9], [0.45, -0.95], [1.0, -0.95]],
		"roll": [[0.0, 0.22], [0.45, -0.4], [1.0, -0.4]],
		"crouch": [[0.3, 0.0], [1.0, 0.5]]}},
	"breaker_impact": {"title": "Ruptura", "dur": 0.8, "link": 0.55, "pts": 0, "attack": true, "persist": true, "keys": {
		# The blade buried in the sand, a deep crouch absorbing the blow, a beat held,
		# then the sword flips back under her feet and up she comes.
		"hold": [[0.0, 1.0], [0.4, 1.0], [0.88, 0.0]],
		"grip2": [[0.0, 1.0], [0.4, 1.0], [0.72, 0.0]],
		"swing_yaw": [[0.0, 1.571], [1.0, 1.571]],
		"swing_pitch": [[0.0, -0.95], [0.4, -0.95], [0.88, 0.0]],
		"roll": [[0.0, -0.4], [0.4, -0.3], [0.88, 0.0]],
		"crouch": [[0.0, 1.0], [0.35, 0.9], [0.82, 0.0]]}},
	"spirit_rise": {"title": "Último Espírito", "dur": 1.05, "link": 1.0, "pts": 0, "attack": true, "keys": {
		# The leap; arms flung wide as the sword comes apart into smoke and she hangs in
		# the air; the smoke condensing into a great blade in her hands, raised high.
		"crouch": [[0.0, 0.0], [0.1, 0.9], [0.2, 0.0]],
		"extend": [[0.15, 0.0], [0.3, 1.0], [0.5, 1.0], [0.62, 0.0]],
		"hold": [[0.45, 0.0], [0.65, 1.0], [1.0, 1.0]],
		"grip2": [[0.55, 0.0], [0.75, 1.0], [1.0, 1.0]],
		"swing_yaw": [[0.0, 1.571], [1.0, 1.571]],
		"swing_pitch": [[0.0, 0.3], [0.65, 0.9], [0.95, 1.9], [1.0, 1.9]],
		"roll": [[0.15, 0.0], [0.4, 0.3], [0.6, 0.1], [0.95, 0.25], [1.0, 0.25]],
		"tuck": [[0.6, 0.0], [0.9, 0.5], [1.0, 0.5]]}},
	"spirit_dive": {"title": "Último Espírito", "dur": 3.0, "link": 1.0, "pts": 0, "attack": true, "no_prep": true, "until_landing": true, "keys": {
		"hold": [[0.0, 1.0], [1.0, 1.0]],
		"grip2": [[0.0, 1.0], [1.0, 1.0]],
		"swing_yaw": [[0.0, 1.571], [1.0, 1.571]],
		"swing_pitch": [[0.0, 1.9], [1.0, 1.9]],
		"roll": [[0.0, 0.25], [1.0, 0.25]],
		"tuck": [[0.0, 0.5], [0.06, 0.3], [1.0, 0.3]]}},
	"spirit_strike": {"title": "Último Espírito", "dur": 0.3, "link": 1.0, "pts": 0, "attack": true, "no_prep": true, "until_landing": true, "keys": {
		"hold": [[0.0, 1.0], [1.0, 1.0]],
		"grip2": [[0.0, 1.0], [1.0, 1.0]],
		"swing_yaw": [[0.0, 1.571], [1.0, 1.571]],
		"swing_pitch": [[0.0, 1.9], [0.45, -0.95], [1.0, -0.95]],
		"roll": [[0.0, 0.25], [0.45, -0.45], [1.0, -0.45]],
		"crouch": [[0.3, 0.0], [1.0, 0.6]]}},
	"spirit_impact": {"title": "Último Espírito", "dur": 1.1, "link": 0.7, "pts": 0, "attack": true, "persist": true, "keys": {
		"hold": [[0.0, 1.0], [0.5, 1.0], [0.92, 0.0]],
		"grip2": [[0.0, 1.0], [0.45, 1.0], [0.78, 0.0]],
		"swing_yaw": [[0.0, 1.571], [1.0, 1.571]],
		"swing_pitch": [[0.0, -0.95], [0.5, -0.95], [0.92, 0.0]],
		"roll": [[0.0, -0.45], [0.5, -0.3], [0.92, 0.0]],
		"crouch": [[0.0, 1.0], [0.45, 0.9], [0.92, 0.0]]}},
}

## Combat data per clip. hits: windows [from, to, shape, reach (m), damage] in clip
## fractions, each window may strike a target again; shape: "blade" (along the sword),
## "around" (a ring around her), "path" (around her as she dashes). heavy: a heavy blow;
## events: [[fraction, name]] fired once.
const MOVES := {
	"slash_a": {"hits": [[0.38, 0.6, "blade", 0.5, 1.0]], "events": [[0.07, "launch"]]},
	"slash_b": {"hits": [[0.38, 0.6, "blade", 0.5, 1.0]], "events": [[0.07, "launch"]]},
	"slash_c": {"hits": [[0.24, 0.7, "around", 2.4, 1.0]], "events": [[0.07, "launch"], [0.24, "ring"]]},
	"slash_d": {"hits": [[0.6, 0.8, "blade", 0.8, 2.0]], "heavy": true, "events": [[0.08, "leap"], [0.66, "cleave"]]},
	"spin_r": {"hits": [[0.18, 0.47, "around", 2.8, 1.0], [0.47, 0.78, "around", 2.8, 1.0]],
		"events": [[0.07, "launch"], [0.2, "ring"], [0.47, "ring"]]},
	"spin_l": {"hits": [[0.18, 0.47, "around", 2.8, 1.0], [0.47, 0.78, "around", 2.8, 1.0]],
		"events": [[0.07, "launch"], [0.2, "ring"], [0.47, "ring"]]},
	"dash": {"hits": [[0.14, 0.58, "path", 1.7, 1.5], [0.6, 0.88, "around", 2.4, 1.0]],
		"events": [[0.12, "dash"], [0.6, "ring"]]},
	"breaker_up": {"events": [[0.18, "launch"]]},
	"breaker_dive": {"events": [[0.04, "slam"]]},
	"spirit_dive": {"events": [[0.04, "slam"]]},
	"breaker_strike": {"hits": [[0.1, 1.0, "blade", 0.7, 2.0]], "heavy": true},
	"spirit_rise": {"events": [[0.1, "launch"], [0.22, "dissolve"], [0.45, "ghost"]]},
	"spirit_strike": {"hits": [[0.1, 1.0, "blade", 1.4, 4.0]], "heavy": true},
	"spirit_impact": {"events": [[0.36, "restore"]]},
}

## Upward launch off the sand (m/s), and the boost of an attack begun in the air.
const LAUNCH := {"light": 5.8, "spin": 6.5, "dash": 2.5, "heavy": 9.5, "special": 10.0}
const AIR_BOOST := {"light": 2.6, "spin": 3.0, "dash": 1.5, "heavy": 4.5, "special": 6.0}
## The light string, one blow per press.
const LIGHT_STRING := ["slash_a", "slash_b", "slash_c", "slash_d"]
## Riding speed (m/s) she eases down to while an attack plays, to stay in control.
const ATTACK_SPEED := {"light": 10.0, "spin": 9.0, "dash": 12.0, "heavy": 7.0, "special": 5.0}

@export var buffer_time := 0.45
@export var combo_time := 2.5
@export var rebound_speed := 5.5
@export var air_jump_speed := 7.5
## Spirit energy gained per hit (the Last Spirit needs 1).
@export var energy_per_hit := 0.14

var sword_state: int = SwordState.SURFING
var combo := 0
var style := 1.0
var best_combo := 0
var total_hits := 0
var energy := 0.0
## Attacks started (tests).
var started := {}

var visual: PlayerVisual
var player: PlayerController
var tricks: TrickDirector
var board: Hoverboard
var model: SpiritModel
var smoke: SmokeBody
var camera: FollowCamera

var _kind := ""
var _clip := ""
var _inst := {}
var _fired := {}
var _hitset := {}
var _rebound_used := false
var _rebound_window := 0.0
var _buffer := ""
var _buffer_age := 0.0
var _light_step := 0
var _string_timer := 0.0
var _window := -1
var _last_kind := ""
var _combo_timer := 0.0
var _air_attacks := 0
var _recovery := 0.0
var _hitstop_until := 0
var _slow_start := 0
var _slow_end := 0
var _slow_scale := 1.0
var _time_ctl := false
var _flash_light := OmniLight3D.new()
var _flash_e := 0.0
var _ready_pulse := 0.0
var _trail: BladeTrail
var _sparks: GPUParticles3D
var _puff: GPUParticles3D
var _ring: GPUParticles3D
var _dash_smoke: GPUParticles3D
var _dissolve: GPUParticles3D
var _waves: Array[Shockwave] = []
var _next_wave := 0
var _prev_tip := Vector3.ZERO
var _prev_hold := 0.0


func setup(v: PlayerVisual) -> void:
	visual = v
	player = v.player
	tricks = v.tricks
	board = v.board
	model = v.model
	smoke = v.smoke
	camera = player.get_node_or_null(player.camera_rig_path) as FollowCamera


func _ready() -> void:
	tricks.register_clips(ATTACK_CLIPS)
	tricks.landed.connect(_on_landed)
	tricks.bailed.connect(func() -> void: _end_combo())
	player.respawned.connect(_reset)
	_trail = BladeTrail.new()
	_trail.space = visual
	add_child(_trail)
	_sparks = Fx.particles({"amount": 48, "lifetime": 0.55, "size": 0.05, "one_shot": true, "explosiveness": 0.95,
		"direction": Vector3.UP, "spread": 180.0, "velocity": Vector2(2.5, 7.0), "damping": 3.5,
		"color": Color(1.0, 0.6, 0.28, 1.0)})
	add_child(_sparks)
	_puff = Fx.particles({"amount": 20, "lifetime": 0.8, "size": 0.55, "kind": "smoke", "one_shot": true,
		"explosiveness": 0.9, "direction": Vector3.UP, "spread": 180.0, "velocity": Vector2(0.8, 2.4),
		"damping": 2.5, "grow": true, "color": Color(0.04, 0.035, 0.04, 0.6), "turbulence": true})
	add_child(_puff)
	# A brief spiral of smoke thrown out from her as she spins.
	_ring = Fx.particles({"amount": 60, "lifetime": 0.7, "size": 0.45, "kind": "smoke", "one_shot": true,
		"explosiveness": 0.85, "shape": "ring", "radius": 0.9, "direction": Vector3.UP, "spread": 10.0,
		"flatness": 0.9, "velocity": Vector2(0.2, 0.6), "radial": Vector2(3.0, 5.0), "damping": 2.5,
		"grow": true, "color": Color(0.04, 0.035, 0.04, 0.55), "turbulence": true})
	add_child(_ring)
	# The stretched smoke left along the dash (left behind, world space).
	_dash_smoke = Fx.particles({"amount": 120, "lifetime": 0.6, "size": 0.5, "kind": "smoke", "radius": 0.25,
		"direction": Vector3.UP, "spread": 60.0, "velocity": Vector2(0.1, 0.4), "damping": 1.5,
		"grow": true, "color": Color(0.03, 0.028, 0.03, 0.55), "turbulence": true})
	add_child(_dash_smoke)
	_dissolve = Fx.particles({"amount": 70, "lifetime": 1.1, "size": 0.4, "kind": "smoke", "one_shot": true,
		"explosiveness": 0.8, "shape": "box", "extents": Vector3(0.15, 0.1, 1.0), "direction": Vector3.UP,
		"spread": 70.0, "velocity": Vector2(0.5, 2.0), "damping": 1.8, "grow": true,
		"color": Color(0.04, 0.035, 0.04, 0.65), "turbulence": true})
	add_child(_dissolve)
	_flash_light.top_level = true
	_flash_light.light_color = Color(1.0, 0.62, 0.32)
	_flash_light.omni_range = 7.0
	_flash_light.light_energy = 0.0
	_flash_light.shadow_enabled = false
	add_child(_flash_light)
	for i in 2:
		var w := Shockwave.new()
		add_child(w)
		_waves.append(w)


# --- Input ----------------------------------------------------------------------------

## Requests an attack ("light", "heavy", "spin", "dash", "special"): starts now, or is
## buffered until the attack in progress reaches its link point.
func request(kind: String) -> void:
	_buffer = kind
	_buffer_age = 0.0


func _read_input() -> void:
	if not player.input_enabled:
		return
	for kind in ACTIONS:
		var action: StringName = ACTIONS[kind]
		if InputMap.has_action(action) and Input.is_action_just_pressed(action):
			request(kind)
	# Ghost Rebound: after a hit in the air, Space is an air jump for the follow-up.
	if _rebound_window > 0.0 and not player.hover.supported and Input.is_action_just_pressed(&"jump"):
		player.hover.impulse(Vector3.UP * air_jump_speed)
		_rebound_window = 0.0
		smoke.on_jump()
		air_jumped.emit()


# --- Per frame --------------------------------------------------------------------------

func update(delta: float) -> void:
	_time_tick()
	if delta <= 0.0:
		return
	var riding := player.mode == PlayerController.Mode.RIDE and (board.materialize > 0.9 or board.spectral)
	_read_input()
	_buffer_age += delta
	if _buffer != "" and _buffer_age > buffer_time:
		_buffer = ""
	_rebound_window = maxf(_rebound_window - delta, 0.0)
	_recovery = maxf(_recovery - delta, 0.0)
	_string_timer = 0.55 if _attack_on() else maxf(_string_timer - delta, 0.0)
	if player.hover.supported:
		_air_attacks = 0
	if riding and _buffer != "" and _can_start():
		var kind := _buffer
		_buffer = ""
		_begin(kind)
	_progress_chains()
	_fire_events()
	var pts := board.blade_points()
	_detect_hits(pts)
	_effects(delta, pts)
	_update_state()
	_govern(delta)
	if combo > 0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_end_combo()
	if energy >= 1.0:
		_ready_pulse -= delta
		if _ready_pulse <= 0.0:
			_ready_pulse = 1.1
			board.pulse(0.7)


func _progress() -> float:
	if _inst.is_empty():
		return 1.0
	return clampf(float(_inst["t"]) / float(_inst["dur"]), 0.0, 1.0)


func _attack_on() -> bool:
	return _clip != "" and tricks.attack_active() and _progress() < 1.0


## A new attack may begin once the current one reaches its link point (heavy and special
## chains run to their end).
func _can_start() -> bool:
	if not _attack_on():
		return true
	var link := float(tricks.clips[_clip].get("link", 0.6))
	return _progress() >= link and link < 1.0


func _begin(kind: String) -> void:
	if kind == "special" and energy < 1.0:
		return
	var name := ""
	match kind:
		"light":
			# Presses in quick succession walk the string; a pause starts it over.
			var chained := _last_kind == "light" and _string_timer > 0.0
			_light_step = (_light_step + 1) % LIGHT_STRING.size() if chained else 0
			name = LIGHT_STRING[_light_step]
		"spin":
			var steer := -player.input.axes.x
			name = "spin_l" if steer < -0.3 else "spin_r"
		"dash":
			name = "dash"
		"heavy":
			name = "breaker_up"
		"special":
			name = "spirit_rise"
			energy = 0.0
	_last_kind = kind
	_kind = kind
	_play(name)
	started[kind] = started.get(kind, 0) + 1
	attack_started.emit(kind)
	if kind == "heavy" or kind == "special" or name == "slash_d":
		if camera:
			camera.anticipate(1.0 if kind != "light" else 0.5)
		smoke.gather(0.8)
	# Launch at once from the sand for the quick ones (no waiting on a click).
	if not player.hover.supported:
		var boost: float = AIR_BOOST[kind] * pow(0.6, _air_attacks)
		_air_attacks += 1
		if kind != "heavy" and kind != "special" and name != "slash_d":
			player.hover.impulse(Vector3.UP * boost)


func _play(name: String) -> void:
	_clip = name
	_inst = tricks.play(name, 1.0, not player.hover.supported, _t_rem())
	_fired = {}
	_hitset = {}
	_window = -1
	_rebound_used = false


func _t_rem() -> float:
	var hm := player.hover
	return TrickDirector.time_to_ground(player.velocity.y, hm.ground_distance - hm.hover_height, hm.gravity)


## The heavy chains: rise -> dive -> strike (-> impact on touchdown, see _on_landed).
func _progress_chains() -> void:
	if _clip == "":
		return
	var hm := player.hover
	match _clip:
		"breaker_up", "spirit_rise":
			if _progress() >= 0.98 or (_progress() > 0.75 and player.velocity.y < 0.5):
				if hm.supported:
					_play("breaker_strike" if _clip == "breaker_up" else "spirit_strike")
				else:
					# A breath at the top, sword raised, then the dive (the "slam" event).
					_play("breaker_dive" if _clip == "breaker_up" else "spirit_dive")
					hm.suspend(0.12, 0.05)
		"breaker_dive", "spirit_dive":
			if (_fired.has("%s@0.04" % _clip) and _t_rem() < 0.17) or hm.supported:
				_play("breaker_strike" if _clip == "breaker_dive" else "spirit_strike")
		"breaker_strike", "spirit_strike":
			# Struck from the sand itself (no touchdown to wait for): it lands now.
			if hm.supported and _progress() > 0.45:
				_on_landed(true, false)


func _fire_events() -> void:
	if _clip == "" or not MOVES.has(_clip):
		return
	var f := _progress()
	for e in MOVES[_clip].get("events", []):
		var key := "%s@%s" % [_clip, e[0]]
		if f >= float(e[0]) and not _fired.has(key):
			_fired[key] = true
			_event(String(e[1]))


func _event(name: String) -> void:
	var hm := player.hover
	match name:
		"launch":
			if hm.supported:
				hm.impulse(Vector3.UP * float(LAUNCH[_kind]))
				board.on_jump()
			elif _kind == "heavy" or _kind == "special":
				hm.impulse(Vector3.UP * float(AIR_BOOST[_kind]))
			if _kind == "special":
				hm.suspend(1.0, 0.12, 1.6)
		"leap":
			# The finisher's leap: high enough for the flip before the cleave.
			if hm.supported:
				hm.impulse(Vector3.UP * 6.8)
				board.on_jump()
			else:
				hm.impulse(Vector3.UP * 3.4)
		"cleave":
			# The finisher comes down: near the sand it cracks it open.
			if camera:
				camera.anticipate(0.0)
			if hm.ground_distance < 3.0:
				_impact(1.2, 3.2, 1.5)
		"slam":
			hm.slam(13.0 if _kind == "heavy" else 17.0)
		"ring":
			Fx.burst(_ring, model.chest.global_position + Vector3.DOWN * 0.3, 1.0)
		"dash":
			var dir := _dash_direction()
			var speed := player.horizontal_speed()
			# Toward a target below or above too (cancelling the fall or the rise).
			var dv := dir * (9.0 + 0.25 * speed)
			if absf(dir.y) > 0.05:
				dv.y -= player.velocity.y
			hm.impulse(dv + Vector3.UP * (2.0 if absf(dir.y) <= 0.05 else 0.0))
			hm.suspend(0.35, 0.25)
			board.on_boost_start()
			if camera:
				camera.zoom_punch(0.5)
		"dissolve":
			board.set_spectral(true)
			Fx.burst(_dissolve, board.global_position, 1.0)
		"ghost":
			board.set_ghost(1.0)
			# The great blade forms: time holds its breath.
			_slowmo(0.4, 0.55)
			_flash(model.chest.global_position + Vector3.UP, 0.8)
		"restore":
			board.set_ghost(0.0)
			board.set_spectral(false)


## Toward a sentinel ahead (within ~16 m and 40 deg, up or down at most 35 deg), else
## straight along the travel.
func _dash_direction() -> Vector3:
	var hv := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var fwd := hv.normalized() if hv.length() > 1.0 else player.facing_direction()
	var me := model.chest.global_position
	var best := fwd
	var best_d := 16.0
	for t in get_tree().get_nodes_in_group(&"spirit_targets"):
		var st := t as SpiritTarget
		if st == null or not st.alive:
			continue
		var to := st.hurt_center() - me
		var flat := Vector3(to.x, 0.0, to.z)
		var d := flat.length()
		if d < best_d and d > 0.5 and fwd.dot(flat / d) > cos(deg_to_rad(40.0)):
			best_d = d
			var pitch := clampf(atan2(to.y, d), deg_to_rad(-35.0), deg_to_rad(35.0))
			best = (flat / d) * cos(pitch) + Vector3.UP * sin(pitch)
	return best


func _on_landed(_clean: bool, _had: bool) -> void:
	# Touching the sand before the launch lifts her: the rise just goes on.
	if (_clip == "breaker_up" or _clip == "spirit_rise") and not _fired.has("%s@%s" % [_clip, MOVES[_clip]["events"][0][0]]):
		return
	# The heavy blows land: shockwave on the sand, everything around struck.
	match _clip:
		"breaker_up", "breaker_dive", "breaker_strike":
			_play("breaker_impact")
			_impact(2.0, 4.5, 2.0)
		"spirit_rise", "spirit_dive", "spirit_strike":
			_play("spirit_impact")
			_impact(3.0, 9.0, 4.0)
	if camera:
		camera.anticipate(0.0)
	if _attack_on() or _clip != "":
		_recovery = 0.3


func _impact(strength: float, radius: float, damage: float) -> void:
	var hm := player.hover
	var pts := board.blade_points()
	var at: Vector3 = pts[1]
	at.y = hm.ground_point.y
	var n := hm.ground_normal
	var w := _waves[_next_wave]
	_next_wave = (_next_wave + 1) % _waves.size()
	w.play(at, n, radius, 0.55 + 0.15 * strength, clampf(0.6 + 0.2 * strength, 0.0, 1.0))
	board._sand.burst(at, clampf(0.45 * strength, 0.4, 1.0), Vector3.UP, 0.6 + 0.3 * strength, 75.0)
	Fx.burst(_ring, at + Vector3.UP * 0.25, 1.0)
	Fx.burst(_puff, at + Vector3.UP * 0.3, 1.0)
	smoke.on_impact(clampf(strength * 0.5, 0.3, 1.0))
	_flash(at + Vector3.UP * 0.6, clampf(0.4 + 0.25 * strength, 0.5, 1.2))
	if camera:
		camera.shake(clampf(0.35 * strength, 0.3, 1.0))
		camera.zoom_punch(clampf(0.35 * strength, 0.4, 1.0))
	_hitstop(0.06 + 0.02 * strength)
	# The big blows land in slow motion.
	if strength >= 2.0:
		_slowmo(0.3 if strength < 3.0 else 0.2, 0.3 + 0.15 * strength)
	impact.emit(at, strength)
	for t in get_tree().get_nodes_in_group(&"spirit_targets"):
		var st := t as SpiritTarget
		if st == null or not st.alive or _hitset.has(st.get_instance_id()):
			continue
		if st.hurt_center().distance_to(at) <= radius + st.hurt_radius:
			_hit(st, st.hurt_center(), damage, true, false)


func _detect_hits(pts: Array) -> void:
	if not _attack_on() or not MOVES.has(_clip):
		return
	var mv: Dictionary = MOVES[_clip]
	var hits: Array = mv.get("hits", [])
	var f := _progress()
	var win := -1
	for i in hits.size():
		if f >= float(hits[i][0]) and f <= float(hits[i][1]):
			win = i
	if win < 0:
		return
	if win != _window:
		# A new window: every target may be struck again (multi-hit moves).
		_window = win
		_hitset = {}
	var h: Array = hits[win]
	var shape: String = h[2]
	var reach: float = h[3]
	var grip: Vector3 = pts[0]
	var tip: Vector3 = pts[1]
	var chest := model.chest.global_position
	for t in get_tree().get_nodes_in_group(&"spirit_targets"):
		var st := t as SpiritTarget
		if st == null or not st.alive or _hitset.has(st.get_instance_id()):
			continue
		var c := st.hurt_center()
		var point := Vector3.ZERO
		var touched := false
		match shape:
			"blade":
				point = Geometry3D.get_closest_point_to_segment(c, grip, tip)
				touched = point.distance_to(c) <= reach + st.hurt_radius
			"around":
				point = chest + (c - chest).limit_length(reach)
				touched = Vector2(c.x - chest.x, c.z - chest.z).length() <= reach + st.hurt_radius and absf(c.y - chest.y) < 1.8
			"path":
				var on_blade := Geometry3D.get_closest_point_to_segment(c, grip, tip)
				point = on_blade if on_blade.distance_to(c) < chest.distance_to(c) else chest
				touched = point.distance_to(c) <= reach + st.hurt_radius
		if touched:
			_hit(st, point, float(h[4]), mv.get("heavy", false), not player.hover.supported)


func _hit(st: SpiritTarget, point: Vector3, damage: float, heavy: bool, airborne: bool) -> void:
	_hitset[st.get_instance_id()] = true
	var away := st.hurt_center() - player.global_position
	var hv := Vector3(player.velocity.x, 0.0, player.velocity.z)
	st.take_hit({"damage": damage, "heavy": heavy, "dir": away.normalized() + hv.normalized() * 0.5,
		"launch": (airborne and not heavy) or _clip == "slash_b", "point": point})
	# Combo: every hit counts; a different attack from the last raises the style.
	combo += 1
	total_hits += 1
	best_combo = maxi(best_combo, combo)
	if _kind != str(get_meta("last_hit_kind", "")):
		style = minf(style + 0.25, 3.0)
	set_meta("last_hit_kind", _kind)
	_combo_timer = combo_time
	var was_ready := energy >= 1.0
	energy = minf(energy + energy_per_hit * style, 1.0)
	if energy >= 1.0 and not was_ready:
		special_ready.emit()
	# Feedback.
	Fx.burst(_sparks, point, 1.0 if heavy else 0.6)
	Fx.burst(_puff, point, 0.7 if heavy else 0.35)
	_flash(point, 0.7 if heavy else 0.35)
	board.pulse(0.6 + 0.12 * minf(combo, 6))
	smoke.on_impact(0.8 if heavy else 0.45)
	_hitstop(0.09 if heavy else 0.05)
	if camera:
		camera.shake(0.55 if heavy else 0.15)
		camera.zoom_punch(0.6 if heavy else 0.2)
	# A finishing blow (the string's last, or a sentinel shattering) slows time a moment.
	if not st.alive:
		_slowmo(0.3, 0.45)
	elif _clip == "slash_d":
		_slowmo(0.35, 0.3)
	# Ghost Rebound: a hit in the air lifts her a little and opens an air jump.
	if airborne and not _rebound_used and not _clip.ends_with("strike"):
		_rebound_used = true
		player.hover.impulse(Vector3.UP * rebound_speed)
		_rebound_window = 0.8
	hit_landed.emit(st, heavy, combo)


func _end_combo() -> void:
	if combo > 0:
		combo_ended.emit(combo, style)
	combo = 0
	style = 1.0
	set_meta("last_hit_kind", "")


func _reset() -> void:
	_end_combo()
	_buffer = ""
	_clip = ""
	_inst = {}
	board.set_ghost(0.0)
	board.set_spectral(false)
	_light_step = 0
	player.hover.speed_cap = INF
	if camera:
		camera.anticipate(0.0)


## A short pause on impact: time slows to a near stop for a few hundredths of a second.
func _hitstop(seconds: float) -> void:
	_hitstop_until = maxi(_hitstop_until, Time.get_ticks_usec() + int(seconds * 1e6))
	_time_tick()


func _effects(delta: float, pts: Array) -> void:
	var grip: Vector3 = pts[0]
	var tip: Vector3 = pts[1]
	var tc := tricks.out
	# The smoke trail follows the real blade from the moment it leaves her feet (its
	# flight up into her hand draws an arc too) until it is back under them.
	var local_tip := visual.global_transform.affine_inverse() * tip
	var tip_speed := local_tip.distance_to(_prev_tip) / delta
	_prev_tip = local_tip
	var swinging := tc.hold > 0.08 and _attack_on() and tip_speed > 3.5
	_trail.intensity = clampf(tip_speed / 12.0, 0.4, 1.0) * (0.55 + 0.45 * tc.hold)
	# In flight only the tip draws a thin streak; in her hand the whole stroke sweeps.
	_trail.feed(delta, grip.lerp(tip, lerpf(0.85, 0.25, smoothstep(0.6, 0.95, tc.hold))), tip, swinging)
	if swinging and tc.hold > 0.6:
		smoke.follow_arc((tip - grip).normalized())
	# The dash leaves stretched smoke along its path.
	var dashing := _clip == "dash" and _progress() > 0.12 and _progress() < 0.6
	_dash_smoke.emitting = dashing
	if dashing:
		_dash_smoke.global_position = model.chest.global_position


func _update_state() -> void:
	var tc := tricks.out
	var s: int = SwordState.SURFING
	var rising := tc.hold > _prev_hold + 0.0005
	var falling := tc.hold < _prev_hold - 0.0005
	_prev_hold = tc.hold
	if _attack_on():
		var mv: Dictionary = MOVES.get(_clip, {})
		var f := _progress()
		var hit_on := mv.has("hit") and f >= float(mv["hit"][0]) and f <= float(mv["hit"][1])
		if hit_on and tc.hold > 0.5:
			s = SwordState.ATTACKING
		elif tc.hold >= 0.9 and not falling:
			s = SwordState.HELD_FOR_ATTACK
		elif falling:
			s = SwordState.RETURNING_TO_SURF
		else:
			s = SwordState.ENTERING_ATTACK if rising or tc.hold < 0.9 else SwordState.HELD_FOR_ATTACK
	elif tc.hold > 0.05:
		s = SwordState.RETURNING_TO_SURF
	elif _recovery > 0.0:
		s = SwordState.SURFING_RECOVERY
	if s != sword_state:
		sword_state = s
		state_changed.emit(s)


## Slow motion at `scale` for `seconds` (real time), easing back over its second half.
func _slowmo(scale: float, seconds: float) -> void:
	var now := Time.get_ticks_usec()
	if now < _slow_end and scale > _slow_scale:
		return
	_slow_start = now
	_slow_end = now + int(seconds * 1e6)
	_slow_scale = scale
	_time_tick()


## Engine time from the hit-stop and slow motion (left alone when neither is running).
func _time_tick() -> void:
	var now := Time.get_ticks_usec()
	var ts := 1.0
	if now < _slow_end:
		var k := float(now - _slow_start) / float(maxi(_slow_end - _slow_start, 1))
		ts = lerpf(_slow_scale, 1.0, smoothstep(0.5, 1.0, k))
	if now < _hitstop_until:
		ts = minf(ts, 0.05)
	if ts < 1.0:
		_time_ctl = true
		Engine.time_scale = ts
	elif _time_ctl:
		_time_ctl = false
		Engine.time_scale = 1.0


## A warm flash of light where a blow lands.
func _flash(at: Vector3, amount: float) -> void:
	_flash_light.global_position = at
	_flash_e = maxf(_flash_e, amount)


## While she fights, the ride eases down to a pace she can control (the dash may burst
## past it), and the camera draws in on the sentinel she is fighting.
func _govern(delta: float) -> void:
	var on := _attack_on()
	var cap := INF
	if on:
		cap = float(ATTACK_SPEED.get(_kind, 11.0))
		if _clip == "dash" and _progress() < 0.6:
			cap = 26.0
	player.hover.speed_cap = cap
	_flash_e = move_toward(_flash_e, 0.0, delta * 5.0)
	_flash_light.light_energy = 5.0 * _flash_e * _flash_e
	if camera == null:
		return
	var target := _nearest_target(16.0) if on or combo > 0 else null
	camera.focus(target.hurt_center() if target else Vector3.ZERO, 1.0 if target and on else (0.5 if target else 0.0))
	var roll := 0.0
	if on:
		match _clip:
			"spin_r", "slash_c":
				roll = 0.06
			"spin_l":
				roll = -0.06
			"dash":
				roll = -0.05 if _progress() < 0.6 else 0.05
	camera.tilt(roll)


## The nearest live sentinel within `max_dist` that is not behind her.
func _nearest_target(max_dist: float) -> SpiritTarget:
	var me := model.chest.global_position
	var hv := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var fwd := hv.normalized() if hv.length() > 1.0 else player.facing_direction()
	var best: SpiritTarget = null
	var best_d := max_dist
	for t in get_tree().get_nodes_in_group(&"spirit_targets"):
		var st := t as SpiritTarget
		if st == null or not st.alive:
			continue
		var to := st.hurt_center() - me
		var d := to.length()
		if d < best_d and (d < 4.0 or fwd.dot(to / d) > -0.2):
			best_d = d
			best = st
	return best


