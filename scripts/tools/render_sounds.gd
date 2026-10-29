extends SceneTree
## Renders every synthesized sound of AmbientAudio to .wav files to listen to them
## outside the game, plus a 12 s "ride" of the ambience (cruise, carve, jump, boost):
##   Godot --headless --path . --script res://scripts/tools/render_sounds.gd -- --out=<folder>

var _out := "user://sounds"


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	var audio := AmbientAudio.new()
	var sounds: Dictionary = audio.make_sounds()
	for k in sounds:
		(sounds[k] as AudioStreamWAV).save_to_wav("%s/%s.wav" % [_out, k])
	# Ambience over a little ride: [seconds, speed01, contact, carve, air, gust].
	var plan := [[2.0, 0.1, 1.0, 0.0, 0.0, 0.4], [3.0, 0.55, 1.0, 0.0, 0.0, 0.5], [2.0, 0.6, 1.0, 0.9, 0.0, 0.6],
		[1.2, 0.6, 0.0, 0.0, 1.0, 0.6], [1.8, 0.65, 1.0, 0.2, 0.0, 0.5], [2.0, 1.0, 1.0, 0.1, 0.0, 0.8]]
	var data := PackedByteArray()
	var cur := [0.1, 1.0, 0.0, 0.0, 0.4]
	for seg in plan:
		var n := int(float(seg[0]) * AmbientAudio.RATE)
		for i in n:
			for j in 5:
				cur[j] = lerpf(cur[j], float(seg[j + 1]), 0.00025)
			audio.set_ambience(cur[0], cur[1], cur[2], cur[3], cur[4])
			var s := (audio.wind_frame() + audio.sand_frame()) * audio.master_volume
			var v := int(clampf(s, -1.0, 1.0) * 32767.0)
			data.append(v & 0xff)
			data.append((v >> 8) & 0xff)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(AmbientAudio.RATE)
	wav.data = data
	wav.save_to_wav(_out + "/ambience_ride.wav")
	audio.free()
	print("[render_sounds] saved ", _out)
	quit()
