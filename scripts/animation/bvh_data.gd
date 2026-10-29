class_name BvhData
extends RefCounted
## Minimal BVH (motion capture) reader with forward kinematics.
## Only used offline by scripts/tools/import_mocap.gd; nothing loads BVH at runtime.

var names: PackedStringArray = []
var parents: PackedInt32Array = []
var offsets: PackedVector3Array = []
var channels: Array = []          # per joint: Array of channel names
var channel_start: PackedInt32Array = []
var is_end: Array[bool] = []
var frames: Array[PackedFloat32Array] = []
var frame_time := 1.0 / 120.0


static func load_file(path: String) -> BvhData:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("BvhData: cannot open " + path)
		return null
	var d := BvhData.new()
	d._parse(f.get_as_text())
	return d


func _parse(text: String) -> void:
	var tokens := text.replace("\r", " ").replace("\n", " ").replace("\t", " ").split(" ", false)
	var i := 0
	var stack: Array[int] = []
	var n_channels := 0
	while i < tokens.size():
		var t := tokens[i]
		if t == "ROOT" or t == "JOINT" or t == "End":
			var jname := tokens[i + 1] if t != "End" else (names[stack.back()] + "_End")
			names.append(jname)
			parents.append(stack.back() if not stack.is_empty() else -1)
			offsets.append(Vector3.ZERO)
			channels.append([])
			channel_start.append(n_channels)
			is_end.append(t == "End")
			i += 2
		elif t == "{":
			stack.append(names.size() - 1)
			i += 1
		elif t == "}":
			stack.pop_back()
			i += 1
		elif t == "OFFSET":
			offsets[names.size() - 1] = Vector3(tokens[i + 1].to_float(), tokens[i + 2].to_float(), tokens[i + 3].to_float())
			i += 4
		elif t == "CHANNELS":
			var c := tokens[i + 1].to_int()
			var arr: Array = []
			for k in c:
				arr.append(tokens[i + 2 + k])
			channels[names.size() - 1] = arr
			channel_start[names.size() - 1] = n_channels
			n_channels += c
			i += 2 + c
		elif t == "MOTION":
			var count := tokens[i + 2].to_int()
			frame_time = tokens[i + 5].to_float()
			i += 6
			for fr in count:
				var row := PackedFloat32Array()
				row.resize(n_channels)
				for k in n_channels:
					row[k] = tokens[i + k].to_float()
				frames.append(row)
				i += n_channels
			break
		else:
			i += 1


func index_of(joint: String) -> int:
	return names.find(joint)


## Global joint positions for one frame (BVH space: Y up).
func positions(frame: int) -> PackedVector3Array:
	var row := frames[frame]
	var g: Array[Transform3D] = []
	g.resize(names.size())
	var out := PackedVector3Array()
	out.resize(names.size())
	for j in names.size():
		var pos := offsets[j]
		var rot := Basis.IDENTITY
		var chans: Array = channels[j]
		var base := channel_start[j]
		for k in chans.size():
			var v := row[base + k]
			match String(chans[k]):
				"Xposition": pos.x += v
				"Yposition": pos.y += v
				"Zposition": pos.z += v
				"Xrotation": rot = rot * Basis(Vector3.RIGHT, deg_to_rad(v))
				"Yrotation": rot = rot * Basis(Vector3.UP, deg_to_rad(v))
				"Zrotation": rot = rot * Basis(Vector3.BACK, deg_to_rad(v))
		var local := Transform3D(rot, pos)
		g[j] = (g[parents[j]] * local) if parents[j] >= 0 else local
		out[j] = g[j].origin
	return out
