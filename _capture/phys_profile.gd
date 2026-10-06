extends SceneTree
## 물리 틱 구간 측정: 노드들의 물리 처리 순서(process_physics_priority)를 묶음별로 나누고 사이에 표시 노드를 넣어
## 한 물리 틱 안에서 [그 밖 / Main / 플레이어 / 드론 / 적(둥지·가스통 포함)] 이 각각 쓴 시간을 잰다.
## 오래 걸린 틱(--spike=ms 이상)만 찍는다. 순서를 바꾸므로 측정용으로만 쓴다.
## 실행: powershell -File tools\godot.ps1 wait -s res://_capture/phys_profile.gd -- --bot --dronebot --seed=4 --seconds=9999 --probe-seconds=40
var seconds := 40.0
var spike := 12.0
const SEGS := ["misc", "main", "player", "drone", "enemies", "tail"]
const PRI := [-1000000, 5, 15, 25, 35, 45, 1000000]   # 표시 노드 (구간 경계)
const GROUP_PRI := {"main": 10, "player": 20, "drone": 30, "enemies": 40}

class Mark extends Node:
	static var stamps: Array[int] = [0, 0, 0, 0, 0, 0, 0]
	var idx := 0
	func _physics_process(_dt: float) -> void:
		stamps[idx] = Time.get_ticks_usec()


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--probe-seconds="):
			seconds = float(a.substr(16))
		elif a.begins_with("--spike="):
			spike = float(a.substr(8))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	node_added.connect(_on_added)
	_run.call_deferred()


func _on_added(n: Node) -> void:
	if n is Enemy:
		n.process_physics_priority = GROUP_PRI.enemies
	elif n is PartnerDrone:
		n.process_physics_priority = GROUP_PRI.drone
	elif n is Player:
		n.process_physics_priority = GROUP_PRI.player


func _run() -> void:
	var m: Main = load("res://scenes/main.tscn").instantiate()
	m.process_physics_priority = GROUP_PRI.main
	root.add_child(m)
	current_scene = m
	for i in PRI.size():
		var k := Mark.new()
		k.idx = i
		k.process_physics_priority = PRI[i]
		root.add_child(k)
	var t0 := Time.get_ticks_usec()
	var worst := {}
	var sums := {}
	var ticks := 0
	while Time.get_ticks_usec() - t0 < int(seconds * 1e6):
		await physics_frame
		# physics_frame 은 이번 틱 노드 처리 직전에 온다 → stamps 는 지난 틱의 완성된 값
		var now := Time.get_ticks_usec()
		var stamps := Mark.stamps
		if stamps[0] == 0:
			continue
		var parts := []
		var total := 0.0
		for i in SEGS.size():
			var d := float(stamps[i + 1] - stamps[i]) / 1000.0
			parts.append(d)
			total += d
			sums[SEGS[i]] = float(sums.get(SEGS[i], 0.0)) + d
			worst[SEGS[i]] = maxf(float(worst.get(SEGS[i], 0.0)), d)
		ticks += 1
		if total >= spike and Time.get_ticks_usec() - t0 > 3e6:
			var s := ""
			for i in SEGS.size():
				s += "%s=%.1f " % [SEGS[i], parts[i]]
			print("SPIKE t=%.1fs total=%.1fms %s enemies_n=%d" % [float(now - t0) / 1e6, total, s, Enemy.live(self).size()])
	var avg := ""
	for k in SEGS:
		avg += "%s=%.2f/%.1f " % [k, float(sums[k]) / ticks, float(worst[k])]
	print("PHYS avg/worst ms: %s ticks=%d" % [avg, ticks])
	quit()
