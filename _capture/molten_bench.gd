extends SceneTree
## 액체 스플래시 CPU 비용 측정 (headless): 최악 수준 동시 발생 상황에서 프레임당 _process 시간.
const MoltenSplash := preload("res://scripts/presentation/molten_splash.gd")
func _initialize() -> void:
	var ms := MoltenSplash.new()
	root.add_child(ms)
	await process_frame
	var worst := 0.0
	var total := 0.0
	var frames := 0
	for f in 240:
		if f % 57 == 0:
			for i in 3:
				ms.burst(Vector3(randf_range(-6, 6), 0, randf_range(-6, 6)), 1.25)
		if f % 90 == 0:
			for i in 13:
				ms.column(Vector3(randf_range(-8, 8), 0, randf_range(-8, 8)), 0.9)
		var t0 := Time.get_ticks_usec()
		ms._process(1.0 / 60.0)
		var us := float(Time.get_ticks_usec() - t0)
		worst = maxf(worst, us)
		total += us
		frames += 1
		if f % 30 == 0:
			print("f=%d drops_hi=%d splats=%d us=%.0f" % [f, ms._hi, ms._sn, us])
	print("avg=%.0fus worst=%.0fus" % [total / frames, worst])
	quit()
