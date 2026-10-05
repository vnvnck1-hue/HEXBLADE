extends SceneTree
## 보이스·합체 효과음의 실제 최대 음량(버스 피크, dBFS)을 잰다 — 믹싱 기준값 확인용.
## 실행: powershell -File tools\godot.ps1 wait --headless -s res://_capture/voice_level_probe.gd

const SFX_IDS := ["drone_dock", "boom", "drone_burst", "launch", "drone_hop", "shoot", "slash"]


func _initialize() -> void:
	_run.call_deferred()


func _peak_of(stream: AudioStream, vol_db: float, via_voice_bus := false) -> Array:
	var bus := AudioServer.bus_count
	AudioServer.add_bus(bus)
	AudioServer.set_bus_name(bus, "Probe")
	if via_voice_bus:
		# DockVoice 의 효과(EQ·컴프·리미터)를 그대로 복사해 이 버스에서 잰다
		var vb := DockingVoice.ensure_bus()
		for e in AudioServer.get_bus_effect_count(vb):
			AudioServer.add_bus_effect(bus, AudioServer.get_bus_effect(vb, e))
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = vol_db
	p.bus = "Probe"
	root.add_child(p)
	p.play()
	var peak := -200.0
	var sum := 0.0
	var n := 0
	var t0 := Time.get_ticks_msec()
	while p.playing and Time.get_ticks_msec() - t0 < 4000:
		await process_frame
		var l := maxf(AudioServer.get_bus_peak_volume_left_db(bus, 0), AudioServer.get_bus_peak_volume_right_db(bus, 0))
		peak = maxf(peak, l)
		if l > -60.0:
			sum += db_to_linear(l) * db_to_linear(l)
			n += 1
	p.queue_free()
	AudioServer.remove_bus(bus)
	await process_frame
	var rms := linear_to_db(sqrt(sum / maxf(n, 1))) if n > 0 else -200.0
	return [peak, rms]


func _run() -> void:
	var sfx := Sfx.new()
	root.add_child(sfx)
	await process_frame
	for i in DockingVoice.VOICES.size():
		var r: Array = await _peak_of(DockingVoice.VOICES[i], 0.0)
		var m: Array = await _peak_of(DockingVoice.VOICES[i], DockingVoice.VOLUME_DB + float(DockingVoice.GAIN_DB[i]), true)
		print("VOICE %-24s raw peak=%6.1f loud=%6.1f  |  mixed peak=%6.1f loud=%6.1f" % [DockingVoice.NAMES[i], r[0], r[1], m[0], m[1]])
	for id in SFX_IDS:
		if not sfx.streams.has(id):
			continue
		var st: Variant = sfx.streams[id]
		if st is Array:
			st = (st as Array)[0]
		var r: Array = await _peak_of(st, 0.0)
		print("SFX   %-24s peak=%6.1f dBFS  loud=%6.1f" % [id, r[0], r[1]])
	quit()
