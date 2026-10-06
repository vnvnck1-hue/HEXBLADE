extends SceneTree
## 감염 체액 터짐 비용: 본편 씬에서 InfestSplash.burst 를 n 개 한꺼번에 내고 호출·다음 프레임 시간을 잰다.
## 실행: powershell -File tools\godot.ps1 wait -s res://_capture/burst_probe.gd -- --capture= --seconds=9999
func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_run.call_deferred()

func _run() -> void:
	var m: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	for i in 60:
		await process_frame
	var p: Vector3 = (m.get("player") as Node3D).global_position + Vector3(2, 0.5, 2)
	for n in [1, 4, 10, 1, 4, 10]:
		var t0 := Time.get_ticks_usec()
		for k in n:
			InfestSplash.burst(p + Vector3(k * 0.3, 0, 0), Vector3.UP, 1.0)
		var t1 := Time.get_ticks_usec()
		await process_frame
		var t2 := Time.get_ticks_usec()
		var worst := 0.0
		var last := t2
		for f in 120:
			await process_frame
			var now := Time.get_ticks_usec()
			worst = maxf(worst, (now - last) / 1000.0)
			last = now
		print("BURST n=%d call=%.1fms frame1=%.1fms worst_after=%.1fms" % [n, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, worst])
	quit()
