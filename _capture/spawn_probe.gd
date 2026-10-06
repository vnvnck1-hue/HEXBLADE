extends SceneTree
## 적 등장 비용 측정: 본편 씬을 띄운 뒤 벌레 4종을 차례로 여러 번 만들어 new / add_child(_ready) / 첫 프레임 시간을 잰다.
## 실행: powershell -File tools\godot.ps1 wait -s res://_capture/spawn_probe.gd -- --capture= --seconds=9999 [--times=3]
var times := 3


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--times="):
			times = int(a.substr(8))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_run.call_deferred()


func _run() -> void:
	var m: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	for i in 60:
		await process_frame
	var kinds := {"grub": BugGrub, "chomp": BugChomper, "ant": BugAnt, "pill": BugPill}
	for k in times:
		for name: String in kinds:
			var t0 := Time.get_ticks_usec()
			var e: Node3D = kinds[name].new()
			var t1 := Time.get_ticks_usec()
			e.position = Vector3(3, 0, 3)
			m.add_child(e)
			var t2 := Time.get_ticks_usec()
			var l0 := Time.get_ticks_usec()
			await process_frame
			var f1 := Time.get_ticks_usec()
			await process_frame
			var f2 := Time.get_ticks_usec()
			print("SPAWN %s #%d new=%.1fms ready=%.1fms frame1=%.1fms frame2=%.1fms" % [name, k, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (f1 - l0) / 1000.0, (f2 - f1) / 1000.0])
			e.queue_free()
			for i in 10:
				await process_frame
	quit()
