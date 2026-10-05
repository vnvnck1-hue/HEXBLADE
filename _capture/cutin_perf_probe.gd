extends SceneTree
## 합체 컷인 성능 측정: 씬을 bot 으로 돌리다가 적이 있을 때 Q 합체(whirl_link)를 일으키고, 컷인 동안 실제 프레임 시간 · 물리/처리 시간 · 물리 스텝 수를 잰다.
## 실행: powershell -File tools\godot.ps1 wait -s res://_capture/cutin_perf_probe.gd -- --scene=res://scenes/main.tscn --bot --seed=4 [--wait=14] [--times=3]
var scene_path := "res://scenes/main.tscn"
var wait_s := 14.0
var times := 3
var steps := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			scene_path = a.substr(8)
		elif a.begins_with("--wait="):
			wait_s = float(a.substr(7))
		elif a.begins_with("--times="):
			times = int(a.substr(8))
	physics_frame.connect(func(): steps += 1)
	_run.call_deferred()


func _run() -> void:
	var m: Node = load(scene_path).instantiate()
	root.add_child(m)
	current_scene = m
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(wait_s * 1000.0):
		await process_frame
	# 측정 동안은 봇을 끈다 (봇의 궁극기 슬로우모션이 섞이지 않게) · 플레이어 무적 · 시간 배율 1
	m.set("capture_mode", false)
	for k in times:
		m.call("set_slowmo", 1.0)
		var d := PartnerDrone.inst
		var w := 0
		while d and (d.state != PartnerDrone.St.FOLLOW or d.link_cd > 0.0 or d.whirl_t >= 0.0) and w < 600:
			await process_frame
			w += 1
		var foes := get_nodes_in_group("enemies").size()
		_frames_report("before", 30, foes)
		if d:
			d.gauge = PartnerDrone.GAUGE_MAX
			d.whirl_link()
		await _frames_report("cutin", 0, foes)
		for i in 90:
			await process_frame
	quit()


## n 프레임(0 이면 컷인이 사라질 때까지) 동안의 실제 프레임 시간 통계
func _frames_report(tag: String, n: int, foes: int) -> void:
	var last := Time.get_ticks_usec()
	var worst := 0.0
	var sum := 0.0
	var cnt := 0
	var s0 := steps
	var phys := 0.0
	var proc := 0.0
	var start := Time.get_ticks_usec()
	while true:
		await process_frame
		var pl: Variant = current_scene.get("player")
		if pl is Node and is_instance_valid(pl):
			(pl as Node).set("invuln", 5.0)
		var now := Time.get_ticks_usec()
		var ft := float(now - last) / 1000.0
		last = now
		worst = maxf(worst, ft)
		sum += ft
		cnt += 1
		phys = maxf(phys, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		proc = maxf(proc, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		if n > 0 and cnt >= n:
			break
		if n == 0:
			var d := PartnerDrone.inst
			if cnt > 3 and (d == null or not is_instance_valid(d.cutin)):
				break
			if cnt > 600:
				break
	var real_s := float(Time.get_ticks_usec() - start) / 1e6
	print("PERF %s ticks=%d foes=%d frames=%d avg=%.1fms worst=%.1fms phys_steps/s=%.0f phys_max=%.1fms proc_max=%.1fms" % [tag, Engine.physics_ticks_per_second, foes, cnt, sum / cnt, worst, (steps - s0) / maxf(real_s, 0.001), phys, proc])
