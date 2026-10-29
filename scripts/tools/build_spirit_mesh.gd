extends SceneTree
## Offline step: builds the spirit's organic body mesh and caches it as a resource.
## Run after changing proportions in SpiritModel or SpiritBodyBuilder:
##   Godot --headless --path . --script res://scripts/tools/build_spirit_mesh.gd


func _init() -> void:
	var model := SpiritModel.new()
	var rest := model.rest_offsets()
	var mesh := SpiritBodyBuilder.new().build(rest, SpiritModel.PARENT, model.head_radius)
	DirAccess.make_dir_recursive_absolute(SpiritBodyBuilder.CACHE_PATH.get_base_dir())
	var err := ResourceSaver.save(mesh, SpiritBodyBuilder.CACHE_PATH)
	print("[build_spirit_mesh] saved %s (error %d)" % [SpiritBodyBuilder.CACHE_PATH, err])
	model.free()
	quit(0 if err == OK else 1)
