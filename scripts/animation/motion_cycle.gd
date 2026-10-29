class_name MotionCycle
extends Resource
## One looping locomotion cycle retargeted onto the spirit's skeleton.
## Phase 0 = left foot contact, so cycles of different gaits blend in sync.

@export var clip_name := ""
## Distance travelled per cycle (metres, at the spirit's scale).
@export var stride := 1.0
## Duration of one cycle in the original capture (seconds).
@export var source_period := 1.0
@export var samples := 48
## samples * bone_count quaternions as x, y, z, w.
@export var rotations := PackedFloat32Array()
## Absolute hips position per sample (model space).
@export var hips := PackedVector3Array()
## Per sample: x = left foot contact (0..1), y = right foot contact.
@export var contacts := PackedVector2Array()
@export var bone_count := 17
## Thigh + shin length the capture was scaled to (stride and hips scale with it).
@export var leg_length := 0.78


func rotation(sample: int, bone: int) -> Quaternion:
	var i := (sample * bone_count + bone) * 4
	return Quaternion(rotations[i], rotations[i + 1], rotations[i + 2], rotations[i + 3])


## Interpolated pose at `phase` (0..1): fills `out` with local bone rotations and
## returns the hips position.
func sample_pose(phase: float, out: Array[Quaternion]) -> Vector3:
	var f := fposmod(phase, 1.0) * samples
	var a := int(floorf(f)) % samples
	var b := (a + 1) % samples
	var t := f - floorf(f)
	for bone in bone_count:
		out[bone] = rotation(a, bone).slerp(rotation(b, bone), t)
	return hips[a].lerp(hips[b], t)


func contact(phase: float) -> Vector2:
	var f := fposmod(phase, 1.0) * samples
	var a := int(floorf(f)) % samples
	var b := (a + 1) % samples
	return contacts[a].lerp(contacts[b], f - floorf(f))
