extends SceneTree
## 프레임 시간 측정: 씬을 자동 플레이로 돌리며 실제 프레임 시간 분포 · 끊김(hitch) · 처리/물리 시간 · 그리기 호출 · 노드 수를 잰다.
## 기능을 끈 실행(--drone=off, --fluid=off, --infest=off …)과 비교하면 기능별 비용이 나온다.
## 실행: powershell -File tools\godot.ps1 wait --fixed-fps 0 -s res://_capture/frame_probe.gd -- --scene=res://scenes/main.tscn --bot --dronebot --seed=4 --seconds=9999 --probe-seconds=40 [--warm=5] [--tag=base]
## Main 은 --bot 이면 --seconds=(기본 20초) 뒤 스스로 끝낸다 → 측정보다 길게 --seconds=9999 를 같이 준다.
## 측정 길이는 --probe-seconds= 로 따로 준다
## 끊김 프레임은 HITCH 줄로 그때의 노드 수 · 그 프레임에 새로 생긴 노드 수를 같이 찍는다.
var scene_path := "res://scenes/main.tscn"
var seconds := 40.0
var warm := 5.0
var tag := "run"
var hitch_ms := 25.0

var _added := 0
var _added_names := {}
## 스크립트 단계 시간: 물리 틱(모든 _physics_process 합) · 처리(_process 합). 가장 먼저/나중에 도는 표시 노드로 잰다
class Mark extends Node:
	static var phys_us := 0
	static var proc_us := 0
	static var steps := 0
	var first := true
	var _t := 0
	func _init(f: bool) -> void:
		first = f
		process_priority = -1000000 if f else 1000000
		process_physics_priority = -1000000 if f else 1000000
	func _physics_process(_dt: float) -> void:
		if first:
			_t = Time.get_ticks_usec()
			get_parent().get_node("MarkB").set("_t", _t)
		else:
			_frame_add(true, Time.get_ticks_usec() - _t)
	func _process(_dt: float) -> void:
		if first:
			get_parent().get_node("MarkB").set("_t", Time.get_ticks_usec())
		else:
			_frame_add(false, Time.get_ticks_usec() - _t)
	static func _frame_add(phys: bool, us: int) -> void:
		if phys:
			phys_us += us
			steps += 1
		else:
			proc_us += us


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			scene_path = a.substr(8)
		elif a.begins_with("--probe-seconds="):
			seconds = float(a.substr(16))
		elif a.begins_with("--warm="):
			warm = float(a.substr(7))
		elif a.begins_with("--tag="):
			tag = a.substr(6)
		elif a.begins_with("--hitch="):
			hitch_ms = float(a.substr(8))
	# vsync 를 끄고 상한을 없애야 실제 비용이 보인다
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	node_added.connect(_on_added)
	_run.call_deferred()


func _on_added(n: Node) -> void:
	_added += 1
	var k := n.get_class()
	var s: Variant = n.get_script()
	if s is Script and (s as Script).resource_path != "":
		k = (s as Script).resource_path.get_file()
	_added_names[k] = int(_added_names.get(k, 0)) + 1


func _run() -> void:
	var m: Node = load(scene_path).instantiate()
	root.add_child(m)
	current_scene = m
	var a := Mark.new(true)
	a.name = "MarkA"
	var b := Mark.new(false)
	b.name = "MarkB"
	root.add_child(a)
	root.add_child(b)
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < int(warm * 1e6):
		await process_frame
		_keep_alive()
	var times: PackedFloat32Array = []
	var procs: PackedFloat32Array = []
	var physs: PackedFloat32Array = []
	var draws := 0.0
	var prims := 0.0
	var nodes_max := 0
	var hitches := 0
	var hitch_spawn := {}
	var last := Time.get_ticks_usec()
	var start := last
	var total_added := 0
	while Time.get_ticks_usec() - start < int(seconds * 1e6):
		_added = 0
		_added_names.clear()
		Mark.phys_us = 0
		Mark.proc_us = 0
		Mark.steps = 0
		await process_frame
		_keep_alive()
		var now := Time.get_ticks_usec()
		var ft := float(now - last) / 1000.0
		last = now
		times.append(ft)
		procs.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		physs.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var nn := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		nodes_max = maxi(nodes_max, nn)
		total_added += _added
		if ft > hitch_ms:
			hitches += 1
			var top := _top(_added_names, 4)
			print("HITCH %s t=%.1fs ft=%.1fms phys_scripts=%.1fms(%d steps) proc_scripts=%.1fms other=%.1fms nodes=%d added=%d %s" % [tag, float(now - start) / 1e6, ft, Mark.phys_us / 1000.0, Mark.steps, Mark.proc_us / 1000.0, ft - (Mark.phys_us + Mark.proc_us) / 1000.0, nn, _added, top])
			for k in _added_names:
				hitch_spawn[k] = int(hitch_spawn.get(k, 0)) + int(_added_names[k])
	var n := times.size()
	var sorted := times.duplicate()
	sorted.sort()
	var ps := procs.duplicate()
	ps.sort()
	var ph := physs.duplicate()
	ph.sort()
	var avg := 0.0
	for v in times:
		avg += v
	avg /= maxf(n, 1)
	print("FRAME %s frames=%d avg=%.2fms p50=%.2f p95=%.2f p99=%.2f max=%.1f hitches(>%.0fms)=%d proc_p50=%.2f proc_p99=%.2f phys_p50=%.2f phys_p99=%.2f draws=%.0f prims=%.0fk nodes_max=%d added/s=%.0f" % [
		tag, n, avg, sorted[n / 2], sorted[int(n * 0.95)], sorted[int(n * 0.99)], sorted[n - 1], hitch_ms, hitches,
		ps[n / 2], ps[int(n * 0.99)], ph[n / 2], ph[int(n * 0.99)], draws / maxf(n, 1), prims / maxf(n, 1) / 1000.0, nodes_max, total_added / seconds])
	if not hitch_spawn.is_empty():
		print("HITCH_SPAWN %s %s" % [tag, _top(hitch_spawn, 10)])
	quit()


func _keep_alive() -> void:
	var pl: Variant = current_scene.get("player") if current_scene else null
	if pl is Node and is_instance_valid(pl):
		(pl as Node).set("hp", 5)


func _top(d: Dictionary, k: int) -> String:
	var arr := []
	for key in d:
		arr.append([int(d[key]), key])
	arr.sort_custom(func(a, b): return a[0] > b[0])
	var s := ""
	for i in mini(k, arr.size()):
		s += "%s:%d " % [arr[i][1], arr[i][0]]
	return s
