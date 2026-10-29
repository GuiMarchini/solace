@tool
extends DirectionalLight3D
## Orients the sun from two intuitive angles. Azimuth is measured from -Z
## (the spawn's view direction) toward +X; elevation is above the horizon.

@export_range(-180.0, 180.0) var azimuth_deg := 24.0:
	set(v):
		azimuth_deg = v
		_apply()
@export_range(0.0, 90.0) var elevation_deg := 9.0:
	set(v):
		elevation_deg = v
		_apply()


func _ready() -> void:
	_apply()


## Unit vector pointing from the world toward the sun.
func direction_to_sun() -> Vector3:
	var az := deg_to_rad(azimuth_deg)
	var el := deg_to_rad(elevation_deg)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))


func _apply() -> void:
	if not is_inside_tree():
		return
	basis = Basis.looking_at(-direction_to_sun(), Vector3.UP)
	# Shared with shaders (e.g. the sand tints slopes facing away from the sun).
	RenderingServer.global_shader_parameter_set(&"sun_direction", direction_to_sun())
