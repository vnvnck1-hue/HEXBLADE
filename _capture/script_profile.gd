extends SceneTree
## 스크립트별 처리 시간 측정: 스크립트 종류마다 처리 순서(process_priority / process_physics_priority)를 따로 주고
## 묶음 사이에 표시 노드를 넣어, 한 프레임 안에서 각 스크립트 종류가 _process · _physics_process 에 쓴 시간을 잰다.
## 순서를 바꾸므로 측정용으로만 쓴다 (게임 동작이 아주 조금 달라질 수 있다).
## 실행: powershell -File tools\godot.ps1 wait -s res://_capture/script_profile.gd -- --scene=res://scenes/main.tscn --bot --dronebot --seed=4 --seconds=9999 --probe-seconds=40 [--top=25]
var scene_path := "res://scenes/main.tscn"
var seconds := 40.0
var warm := 5.0
var top := 25
var spike := 6.0

class Mark extends Node:
	var stamp := 0
	var phys := false
	func _physics_process(_dt: float) -> void:
		if phys:
			stamp = Time.get_ticks_usec()
	func _process(_dt: float) -> void:
		if not phys:
			stamp = Time.get_ticks_usec()

var _keys: Array[String] = []          # 묶음 이름 (스크립트 파일 이름)
var _idx := {}
var _pm: Array[Mark] = []               # 물리 묶음 시작 표시
var _qm: Array[Mark] = []               # 처리 묶음 시작 표시
var _pend: Mark
var _qend: Mark
var _psum := {}
var _qsum := {}
var _pmax := {}
var _qmax := {}
var _last_phys := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			scene_path = a.substr(8)
		elif a.begins_with("--probe-seconds="):
			seconds = float(a.substr(16))
		elif a.begins_with("--spike="):
			spike = float(a.substr(8))
		elif a.begins_with("--top="):
			top = int(a.substr(6))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_pend = _mark(true, 100000000)
	_qend = _mark(false, 100000000)
	node_added.connect(_on_added)
	_run.call_deferred()


func _mark(phys: bool, pri: int) -> Mark:
	var m := Mark.new()
	m.phys = phys
	if phys:
		m.process_physics_priority = pri
	else:
		m.process_priority = pri
	root.add_child.call_deferred(m)
	return m


func _on_added(n: Node) -> void:
	if n is Mark:
		return
	var s: Variant = n.get_script()
	if not (s is Script) or (s as Script).resource_path == "":
		return
	var k := (s as Script).resource_path.get_file()
	if not _idx.has(k):
		_idx[k] = _keys.size()
		_keys.append(k)
		var base := (_keys.size()) * 10
		_pm.append(_mark(true, base))
		_qm.append(_mark(false, base))
	var b: int = (int(_idx[k]) + 1) * 10 + 5
	n.process_priority = b
	n.process_physics_priority = b


func _run() -> void:
	var m: Node = load(scene_path).instantiate()
	root.add_child(m)
	current_scene = m
	var t0 := Time.get_ticks_usec()
	var frames := 0
	var ticks := 0
	var start := 0
	while true:
		await process_frame
		var now := Time.get_ticks_usec()
		var pl: Variant = current_scene.get("player")
		if pl is Node and is_instance_valid(pl):
			(pl as Node).set("hp", 5)
		if now - t0 < int(warm * 1e6):
			continue
		if start == 0:
			start = now
			continue
		if now - start > int(seconds * 1e6):
			break
		# 이번 프레임의 처리 묶음 (지난 _process 들) · 물리 묶음 (이번 프레임의 물리 틱, 여러 번이면 마지막만)
		frames += 1
		_collect(_qm, _qend, _qsum, _qmax)
		if _pend.stamp != _last_phys:
			_last_phys = _pend.stamp
			ticks += 1
			_collect(_pm, _pend, _psum, _pmax)
	_print("PROC", _qsum, _qmax, frames)
	_print("PHYS", _psum, _pmax, ticks)
	quit()


func _collect(marks: Array[Mark], end: Mark, sums: Dictionary, maxs: Dictionary) -> void:
	for i in marks.size():
		var a := marks[i].stamp
		var b := end.stamp
		if i + 1 < marks.size():
			b = marks[i + 1].stamp
		if a == 0 or b < a:
			continue
		var d := float(b - a) / 1000.0
		if d > 200.0:
			continue
		var k := _keys[i]
		if d >= spike:
			print("SPIKE t=%.1fs %s %s %.1fms" % [float(Time.get_ticks_usec()) / 1e6, "phys" if marks == _pm else "proc", k, d])
		sums[k] = float(sums.get(k, 0.0)) + d
		maxs[k] = maxf(float(maxs.get(k, 0.0)), d)


func _print(tag: String, sums: Dictionary, maxs: Dictionary, n: int) -> void:
	var arr := []
	var total := 0.0
	for k in sums:
		arr.append([float(sums[k]) / maxi(n, 1), k])
		total += float(sums[k]) / maxi(n, 1)
	arr.sort_custom(func(a, b): return a[0] > b[0])
	print("%s total_avg=%.2fms n=%d" % [tag, total, n])
	for i in mini(top, arr.size()):
		print("  %s %-34s avg=%.3fms max=%.1fms" % [tag, arr[i][1], arr[i][0], float(maxs[arr[i][1]])])
