extends SceneTree
## Run with: Godot --headless --path . -s tests/bug_chomper_check.gd
## 촘퍼 (bug_chomper.glb · ChomperRig · BugChomper) 확인:
##  1. 모델(v2 = Tripo 원본을 관절로 나눔): 관절 사슬(머리·턱·혀·판 3장·옆 판·다리 6개 두 마디)과 부착점, 기본 회전 0, 발이 바닥, 정면 = -Z, 텍스처가 들어 있음
##  2. 리그: 걷기·준비동작·덥석·어질·죽음을 몇 초 돌려도 값이 유한 · 걷는 동안·웅크린 동안 발이 바닥에 묻히지 않음 ·
##     다리가 번갈아 든다 · 판이 출렁인다 · 덥석이면 입이 닫힌다
##  3. 시험장: 땅에서 기어 나와 플레이어를 알아채고(깜짝) 다가와 덥석 뛰어든다 · 돌아다니며 노란 체액 웅덩이를 남긴다 · 죽음 연출 뒤 사라진다

var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _rot_zero(n: Node) -> bool:
	for c in n.find_children("*", "Node3D", true, false):
		if not (c as Node3D).rotation.is_zero_approx():
			print("  rotated: ", c.name, " ", (c as Node3D).rotation)
			return false
	return true


func _feet(m: Node3D) -> Array:
	var out: Array = []
	for i in range(1, 4):
		for s in ["l", "r"]:
			out.append(m.find_child("pt_foot_%d_%s" % [i, s]) as Node3D)
	return out


func _run() -> void:
	# ── 1. 모델 ──
	var m := (load(BugChomper.MODEL) as PackedScene).instantiate() as Node3D
	root.add_child(m)
	_check(m.get_node_or_null("body/head") != null, "머리(윗턱·차양) body/head")
	_check(m.get_node_or_null("body/jaw/tongue") != null, "아래턱 > 혀 body/jaw/tongue")
	_check(m.get_node_or_null("body/shell_1/shell_2") != null and m.get_node_or_null("body/shell_1/shell_3") != null,
		"갑각 판: 위 갑각 shell_1 > 볏 shell_2 · 꼬리 판 shell_3")
	_check(m.get_node_or_null("body/pad_l") != null and m.get_node_or_null("body/pad_r") != null, "옆 판 좌우")
	var chains := 0
	for i in range(1, 4):
		for s in ["l", "r"]:
			if m.get_node_or_null("body/leg_%d_%s_1/leg_%d_%s_2" % [i, s, i, s]) != null:
				chains += 1
	_check(chains == 6, "다리 6개 두 마디 사슬 (%d/6)" % chains)
	var ground := 0
	for f: Node3D in _feet(m):
		if f and absf(f.global_position.y) < 0.03:
			ground += 1
	_check(ground == 6, "발 6개가 바닥 (%d/6)" % ground)
	var eye := m.find_child("pt_eye_l") as Node3D
	_check(eye != null and eye.global_position.x < 0.0, "왼쪽 구슬(눈 역할) 왼쪽")
	var mouth := m.find_child("pt_mouth") as Node3D
	_check(mouth != null and mouth.global_position.z < -0.25, "입이 앞(-Z)")
	_check(m.find_children("pt_drip_*", "", true, false).size() == 5, "체액 떨어지는 점 5곳")
	_check(_rot_zero(m), "모든 파츠 기본 회전 0")
	var mi := m.find_child("shell_1") as MeshInstance3D
	var mat := mi.mesh.surface_get_material(0) as StandardMaterial3D
	_check(mat != null and mat.albedo_texture != null, "갑각 판에 반점 텍스처")
	var bm := (m.find_child("body") as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D
	_check(bm != null and bm.albedo_texture != null, "몸통에 청록 피부 텍스처")
	m.queue_free()

	# ── 2. 리그 ──
	var pose := Node3D.new()
	root.add_child(pose)
	var cm := (load(BugChomper.MODEL) as PackedScene).instantiate() as Node3D
	pose.add_child(cm)
	var r := ChomperRig.new().setup(cm)
	var feet := _feet(cm)
	var finite := true
	var buried := 0.0
	var lifted := {}
	var plate_seen := {}
	var dt := 1.0 / 60.0
	for i in 240:
		r.speed = 1.7
		r.turn = sin(i * 0.05) * 1.5
		r.update(dt)
		await process_frame
		for k in r.n:
			var rr: Vector3 = (r.n[k] as Node3D).rotation
			if not (is_finite(rr.x) and is_finite(rr.y) and is_finite(rr.z)):
				finite = false
		for fi in feet.size():
			var y: float = (feet[fi] as Node3D).global_position.y
			buried = minf(buried, y)
			if y > 0.04:
				lifted[fi] = true
		plate_seen[snappedf((r.n.shell_3 as Node3D).rotation.x, 0.005)] = true
	_check(finite, "걷기 4초 — 관절 값 유한")
	_check(buried > -0.05, "걷는 동안 발이 바닥에 묻히지 않음 (최저 %.3f)" % buried)
	_check(lifted.size() == 6, "다리 6개가 모두 번갈아 든다 (%d/6)" % lifted.size())
	_check(plate_seen.size() > 6, "걸을 때 갑각 판이 출렁인다 (%d가지)" % plate_seen.size())
	# 준비동작: 웅크려도 발이 바닥에 남고 입이 최대로 벌어진다
	r.speed = 0.0
	r.turn = 0.0
	buried = 0.0
	for i in 60:
		r.windup = minf(1.0, i / 30.0)
		r.update(dt)
		await process_frame
		for f: Node3D in feet:
			buried = minf(buried, f.global_position.y)
	_check(buried > -0.06, "웅크린 동안 발이 바닥에 묻히지 않음 (최저 %.3f)" % buried)
	_check((r.n.head as Node3D).rotation.x > 0.1, "준비동작: 윗턱을 쩍 들었다 (%.2f)" % (r.n.head as Node3D).rotation.x)
	_check((r.n.shell_3 as Node3D).rotation.x < -0.08, "준비동작: 뒤 판을 곤두세웠다 (%.2f)" % (r.n.shell_3 as Node3D).rotation.x)
	r.windup = 0.0
	r.snap = 1.0
	for i in 6:
		r.update(dt)
	_check((r.n.head as Node3D).rotation.x < -0.1 and (r.n.jaw as Node3D).rotation.x > 0.15, "덥석: 입이 꽉 닫힌다")
	var drift := false
	for i in 120:
		r.dizzy = 1.0
		r.dead_k = clampf((i - 60) / 20.0, 0.0, 1.0)
		r.update(dt)
		for k in r.n:
			var rr: Vector3 = (r.n[k] as Node3D).rotation
			if not (is_finite(rr.x) and is_finite(rr.y) and is_finite(rr.z)) or rr.length() > 8.0:
				drift = true
	_check(not drift, "어질·죽음 — 관절 값 유한")
	pose.queue_free()

	# ── 3. 시험장 ──
	var lab = (load("res://scenes/bugs.tscn") as PackedScene).instantiate()
	root.add_child(lab)
	current_scene = lab
	await _frames(3)
	for e in lab._bugs():
		e.queue_free()
	await _frames(2)
	var p_start: Vector3 = lab.player.global_position
	var c: BugChomper = lab.spawn_bug("chomp", p_start + Vector3(0, 0, -7.0))
	var pud0: int = BugChomper._puddles.size()
	await _frames(50)
	_check(is_instance_valid(c) and c.landed, "땅에서 기어 나왔다")
	var noticed := false
	var lunged := false
	var crawled := false
	for i in 600:
		await physics_frame
		lab.player.global_position = p_start
		if not is_instance_valid(c):
			break
		noticed = noticed or c.state == BugChomper.C.NOTICE
		crawled = crawled or (c.state == BugChomper.C.CHASE and c.cur_speed > 1.0)
		lunged = lunged or c.state == BugChomper.C.LUNGE
		if lunged and crawled:
			break
	_check(noticed, "플레이어를 보고 깜짝 놀란다")
	_check(crawled, "종종걸음으로 다가온다")
	_check(lunged, "콩 뛰어 덥석 문다")
	_check(BugChomper._puddles.size() > pud0, "돌아다니며 노란 체액 웅덩이를 남긴다 (%d개)" % (BugChomper._puddles.size() - pud0))
	_check(c.goo == BugChomper.GOO_Y, "피격 체액 색 = 노랑")
	var dead: Array = []
	var kinds := ["bullet", "slash", "missile"]
	for i in 3:
		var e: BugChomper = lab.spawn_bug("chomp", p_start + Vector3(-4 + i * 4, 0, -5))
		dead.append(e)
	await _frames(50)
	for i in 3:
		(dead[i] as BugEnemy).take_hit(99, Vector3.FORWARD, Vector3.ZERO, kinds[i])
	_check(dead.all(func(e): return not is_instance_valid(e) or not e.alive), "죽음 처리 (일반 · 광선검 · 미사일)")
	await _frames(100)
	_check(dead.all(func(e): return not is_instance_valid(e)), "죽음 연출 뒤 사라진다")
	print("BUG_CHOMPER_CHECK %s" % ("OK" if fails == 0 else "FAILED %d" % fails))
	quit(1 if fails > 0 else 0)
