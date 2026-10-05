extends SceneTree
## 유체 연기 부하 분석: 설정마다 GPU 시간(뷰포트 전체 · 유체 계산 · 연기 그리기), CPU 시간, GPU 메모리를 잰다.
## 뷰포트 GPU = 장면 그리기 전체(컴포지터 연기 포함), 계산/그리기 = 그 구간 GPU 타임스탬프.
## powershell -File tools\godot.ps1 wait -s res://_capture/fluid_perf_probe.gd [-- --res=1920x1080]
## 결과는 PERF 줄 + output/fluid-smoke-20261005/perf_<해상도>.json

const WARM := 60
const N := 180

var main: Main
var rows: Array = []
var res_tag := ""


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await process_frame


func _measure(s: FluidSmoke) -> Dictionary:
	await _wait(WARM)
	var vp := root.get_viewport_rid()
	var g := 0.0
	var c := 0.0
	var cn := 0
	var d := 0.0
	var dn := 0
	var cpu := 0.0
	for i in N:
		await process_frame
		g += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		cpu += s.cpu_usec / 1000.0
		if i % 6 == 0:
			var ms := s.compute_gpu_ms()
			if ms >= 0.0:
				c += ms
				cn += 1
			var dm := s.draw_gpu_ms()
			if dm >= 0.0:
				d += dm
				dn += 1
	return {"view_gpu": g / N, "compute_gpu": c / cn if cn > 0 else 0.0, "draw_gpu": d / dn if dn > 0 else 0.0, "cpu": cpu / N}


func _row(s: FluidSmoke, name: String) -> void:
	var r := await _measure(s)
	r.name = name
	r.grid = "%dx%d" % [s.nx, s.ny]
	r.mem_mb = s.gpu_bytes() / 1048576.0
	r.res = res_tag
	r.idle = s.idle
	rows.append(r)
	print("PERF %-24s 뷰포트 %5.2f · 계산 %5.3f · 그리기 %5.3f · CPU %4.2f ms · 격자 %s %.1fMB%s" % [name, r.view_gpu, r.compute_gpu, r.draw_gpu, r.cpu, r.grid, r.mem_mb, " · 쉼" if s.idle else ""])


func _cfg(s: FluidSmoke, q: int, compute := true, draw := true) -> void:
	FluidSmoke.quality = q as FluidSmoke.Quality
	s.gpu_compute = compute
	s.draw = draw
	s.steps_override = -1


func _load(path: String) -> FluidSmoke:
	if current_scene:
		current_scene.queue_free()
		await _wait(3)
	main = (load(path) as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _wait(10)
	Main.ui_hidden = true
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var s := FluidField.inst.smoke
	s.measure_gpu = true
	return s


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--res="):
			var wh := a.substr(6).split("x")
			DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
	await _wait(5)
	PartnerDrone.cutin_style = "off"
	res_tag = "%dx%d" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]
	# ── 유체 연기 시험장: 통풍구 넷 ──
	var s := await _load("res://scenes/fluid_smoke.tscn")
	main.player.global_position = (main as FluidLab).center + Vector3(0, 0, 1)
	main.camera.snap(main.player.global_position)
	await _wait(600)
	_cfg(s, FluidSmoke.Quality.HIGH, false, false)
	await _row(s, "기준 (연기 끔)")
	_cfg(s, FluidSmoke.Quality.HIGH, true, false)
	await _row(s, "계산만")
	_cfg(s, FluidSmoke.Quality.FULL)
	await _row(s, "FULL 원 해상도 40")
	_cfg(s, FluidSmoke.Quality.HIGH)
	await _row(s, "HIGH 절반 40")
	_cfg(s, FluidSmoke.Quality.LOW)
	await _row(s, "LOW 절반 24")
	s.fill(1.2)
	await _wait(10)
	_cfg(s, FluidSmoke.Quality.FULL)
	await _row(s, "최악 FULL")
	_cfg(s, FluidSmoke.Quality.HIGH)
	await _row(s, "최악 HIGH")
	_cfg(s, FluidSmoke.Quality.LOW)
	await _row(s, "최악 LOW")
	# ── 방 탐색 필드: 맵 전체 격자 ──
	FluidSmoke.quality = FluidSmoke.Quality.HIGH
	s = await _load("res://scenes/main.tscn")
	await _wait(60)
	await _row(s, "필드 · 연기 없음")
	var ff := FluidField.inst
	var room := -1
	for r in main.map.rooms:
		if r.combat:
			room = r.id
			break
	if room >= 0:
		var c := main.map.room_center_world(room)
		ff.add_toxic([c + Vector3(3, 0, 0), c + Vector3(6, 0, 2), c + Vector3(5, 0, -2.5)])
		ff.add_mist(c + Vector3(-4, 0, 1))
		main.player.global_position = main.push_out(c, 1.0)
		main.camera.snap(main.player.global_position)
		await _wait(120)
		await _row(s, "필드 · 독가스+안개")
	var f := FileAccess.open("res://output/fluid-smoke-20261005/perf_%s.json" % res_tag, FileAccess.WRITE)
	f.store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(), "rows": rows}, "\t"))
	f.close()
	FluidSmoke.quality = FluidSmoke.Quality.FULL
	print("RESULT done")
	quit()
