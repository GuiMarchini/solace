extends SceneTree
## Finds patches of deep, loose sand (DuneTerrain.softness_at) near the spawn, for
## screenshots and tests:  Godot --headless --path . --script res://scripts/tools/find_soft_sand.gd

var _frame := 0


func _init() -> void:
	var desert := (load("res://scenes/environment/desert.tscn") as PackedScene).instantiate()
	root.add_child(desert)


func _process(_d: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	var t := DuneTerrain.instance
	var best := []
	for r in range(20, 320, 10):
		for a in 36:
			var ang := TAU * a / 36.0
			var x := cos(ang) * r
			var z := sin(ang) * r
			# Soft here and for 40 m on (along the angle's tangent), so a ride stays in it.
			var ok := true
			for k in 5:
				if t.softness_at(x + cos(ang) * k * 10.0, z + sin(ang) * k * 10.0) < 0.85:
					ok = false
			if ok:
				best.append([r, x, z, ang])
		if best.size() >= 6:
			break
	for b in best.slice(0, 6):
		print("[soft] r %d  x %.0f  z %.0f  heading out %.2f rad" % b)
	return true
