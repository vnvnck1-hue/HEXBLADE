extends SceneTree
## GunSound 합성 시간 측정 + wav 저장 (검증용)
func _init() -> void:
	var t0 := Time.get_ticks_usec()
	var xs := GunSound.build()
	print("GUNSOUND build ms ", (Time.get_ticks_usec() - t0) / 1000.0, " variants ", xs.size(), " samples ", xs[0].size())
	var dir := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
	for i in xs.size():
		var data := PackedByteArray()
		data.resize(xs[i].size() * 2)
		for k in xs[i].size():
			data.encode_s16(k * 2, int(clamp(xs[i][k], -1.0, 1.0) * 32000.0))
		var w := AudioStreamWAV.new()
		w.format = AudioStreamWAV.FORMAT_16_BITS
		w.mix_rate = GunSound.RATE
		w.data = data
		if dir != "":
			w.save_to_wav(dir + "/godot_%02d.wav" % i)
	quit()
