extends SceneTree
## Run with: Godot --headless --path . -s tests/bug_enemies_check.gd
## 벌레형 괴생명체 (개미 병정 bug_ant · 공벌레 bug_pillbug) 확인:
##  1. 모델: 관절 사슬(더듬이 3마디 · 다리 · 등딱지 8장)과 부착점, 모든 파츠 기본 회전 0, 발이 바닥, 정면 = -Z
##  2. 공벌레 말기: curl = 1 이면 등딱지 바깥면이 공 중심에서 거의 같은 거리(틈 없는 공) · 말리는 동안 바닥에 묻히지 않음
##  3. 리그: 몇 초 돌려도 값이 유한하고, 더듬이가 실제로 움직인다 (벌레 움직임)
##  4. 시험장: 땅에서 기어 나온 뒤 전투 · 개미 산 발사로 적 탄이 생긴다 · 공벌레가 굴러 다닌다 · 공 상태는 총알을 튕긴다 · 죽음 연출 후 사라진다

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


func _run() -> void:
	# ── 1. 모델 ──
	var ant := (load(BugAnt.MODEL) as PackedScene).instantiate() as Node3D
	root.add_child(ant)
	for s in ["l", "r"]:
		_check(ant.get_node_or_null("pelvis/thorax/head/antenna_%s_1/antenna_%s_2/antenna_%s_3" % [s, s, s]) != null, "개미 더듬이 3마디 사슬 (%s)" % s)
		_check(ant.get_node_or_null("pelvis/leg_%s_thigh/leg_%s_shin/leg_%s_foot" % [s, s, s]) != null, "개미 뒷다리 사슬 (%s)" % s)
		_check(ant.get_node_or_null("pelvis/thorax/arm_%s_upper/arm_%s_fore/arm_%s_claw" % [s, s, s]) != null, "개미 집게 팔 (%s)" % s)
		_check(ant.get_node_or_null("pelvis/thorax/mid_%s_upper/mid_%s_lower" % [s, s]) != null, "개미 가운데 다리 (%s)" % s)
		_check(ant.get_node_or_null("pelvis/thorax/head/mandible_" + s) != null, "개미 큰턱 (%s)" % s)
		var ft := ant.find_child("pt_foot_" + s) as Node3D
		_check(ft != null and absf(ft.global_position.y) < 0.03, "개미 발 pt_foot_%s 바닥" % s)
	_check(ant.get_node_or_null("pelvis/gaster_1/gaster_2/pt_stinger") != null, "개미 배 두 마디 + 산 발사구")
	var eye := ant.find_child("pt_eye_l") as Node3D
	_check(eye != null and eye.global_position.z < -0.3 and eye.global_position.x < 0.0, "개미 왼눈이 앞(-Z) 왼쪽")
	_check(_rot_zero(ant), "개미 모든 파츠 기본 회전 0")

	var pill := (load(BugPill.MODEL) as PackedScene).instantiate() as Node3D
	root.add_child(pill)
	var chain := "seg_3/seg_2/seg_1/seg_0"
	_check(pill.get_node_or_null(chain) != null, "공벌레 앞 사슬 " + chain)
	_check(pill.get_node_or_null("seg_3/seg_4/seg_5/seg_6/seg_7") != null, "공벌레 뒤 사슬 seg_4~7")
	for s in ["l", "r"]:
		_check(pill.get_node_or_null(chain + "/antenna_%s_1/antenna_%s_2/antenna_%s_3" % [s, s, s]) != null, "공벌레 더듬이 3마디 (%s)" % s)
	var legs := 0
	for i in range(1, 7):
		for s in ["l", "r"]:
			var f := pill.find_child("pt_foot_%d_%s" % [i, s]) as Node3D
			if f and absf(f.global_position.y) < 0.03:
				legs += 1
	_check(legs == 12, "공벌레 다리 6쌍 발이 바닥 (%d/12)" % legs)
	_check((pill.find_child("pt_eye_l") as Node3D).global_position.z < -0.8, "공벌레 머리가 앞(-Z)")
	_check(_rot_zero(pill), "공벌레 모든 파츠 기본 회전 0")
	pill.queue_free()
	ant.queue_free()

	# ── 2. 공벌레 말기 ──
	var pose := Node3D.new()
	root.add_child(pose)
	var roller := Node3D.new()
	pose.add_child(roller)
	var pm := (load(BugPill.MODEL) as PackedScene).instantiate() as Node3D
	roller.add_child(pm)
	var pr := PillRig.new().setup(pm, roller)
	pr.curl = 1.0
	pr.update(0.0)
	await process_frame
	var c := (pm.find_child("pt_ball_center") as Node3D).global_position
	var lo := INF
	var hi := 0.0
	var low_y := INF
	for i in 8:
		var mi := pm.find_child("seg_%d" % i) as MeshInstance3D
		var arr := mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
		for p in arr:
			var w := mi.global_transform * p
			var d := w - c
			d.x /= 0.8                 # 모델은 좌우로 0.8 납작한 타원체
			var r := d.length()
			if r > 0.5:                # 바깥면만
				lo = minf(lo, r)
				hi = maxf(hi, r)
			low_y = minf(low_y, w.y)
	_check(hi - lo < 0.08 and hi < 0.65, "다 말린 등딱지 바깥면 반지름 %.3f~%.3f (공)" % [lo, hi])
	_check(absf(c.y - PillRig.BALL_R) < 0.08, "공 중심 높이 %.2f ≈ 반지름" % c.y)
	_check(low_y > -0.03, "공 상태 바닥에 묻히지 않음 (최저 %.3f)" % low_y)
	var buried := 0.0
	for step in 11:
		pr.curl = step / 10.0
		pr.update(0.0)
		await process_frame
		for i in 8:
			var mi := pm.find_child("seg_%d" % i) as MeshInstance3D
			for p in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
				buried = minf(buried, (mi.global_transform * p).y)
	_check(buried > -0.03, "말리는 도중에도 등딱지가 바닥에 묻히지 않음 (최저 %.3f)" % buried)
	pose.queue_free()

	# ── 3. 리그 ──
	var am := (load(BugAnt.MODEL) as PackedScene).instantiate() as Node3D
	root.add_child(am)
	var ar := AntRig.new().setup(am)
	var a1 := ar.n.antenna_l_1 as Node3D
	var seen := {}
	var finite := true
	for i in 240:
		ar.speed = 5.0 if i % 40 < 25 else 0.0
		ar.acid_k = clampf((i - 120) / 30.0, 0.0, 1.0)
		ar.update(1.0 / 60.0)
		seen[a1.rotation.snapped(Vector3.ONE * 0.05)] = true
		for k in ar.n:
			var r: Vector3 = (ar.n[k] as Node3D).rotation
			if not (is_finite(r.x) and is_finite(r.y) and is_finite(r.z)):
				finite = false
	_check(finite, "개미 리그 4초 — 관절 값 유한")
	_check(seen.size() > 20, "개미 더듬이가 계속 움직인다 (%d가지 자세)" % seen.size())
	_check((ar.n.gaster_1 as Node3D).rotation.x > 1.0, "산 발사 자세: 배를 다리 사이로 말았다 (%.2f rad)" % (ar.n.gaster_1 as Node3D).rotation.x)
	am.queue_free()

	# ── 4. 시험장 ──
	var lab = (load("res://scenes/bugs.tscn") as PackedScene).instantiate()
	root.add_child(lab)
	current_scene = lab
	await _frames(5)
	var bugs: Array = lab._bugs()
	_check(bugs.size() == 4, "시험장에 벌레 4마리 (%d)" % bugs.size())
	await _frames(50)
	var landed := bugs.all(func(e): return is_instance_valid(e) and e.landed)
	_check(landed, "땅에서 기어 나와 전투 시작")
	var bullets := 0
	var rolled := false
	var p_start: Vector3 = lab.player.global_position
	for i in 600:
		await physics_frame
		lab.player.global_position = p_start
		bullets = maxi(bullets, lab.bullets.get_child_count())
		for e in bugs:
			if is_instance_valid(e) and e is BugPill and (e as BugPill).state == BugPill.P.ROLL:
				rolled = true
	_check(bullets > 0, "개미가 산(적 탄)을 쏜다 (최대 %d발)" % bullets)
	_check(rolled, "공벌레가 몸을 말아 굴러 온다")
	# 공 상태 무적 (총알)
	var pb := BugPill.new()
	lab.world.add_child(pb)
	pb.global_position = p_start + Vector3(5, 0, -3)
	await _frames(50)
	pb.rig.curl = 1.0
	var hp0: int = pb.hp
	pb.take_hit(2, Vector3.FORWARD, Vector3.ZERO, "bullet")
	_check(pb.hp == hp0, "공 상태 공벌레는 총알을 튕긴다")
	pb.rig.curl = 0.0
	pb.take_hit(2, Vector3.FORWARD, Vector3.ZERO, "bullet")
	_check(pb.hp < hp0, "펼친 공벌레는 총알에 맞는다")
	# 죽음 연출 3종
	var kinds := ["bullet", "slash", "missile"]
	var dead: Array = []
	for i in 3:
		var e: BugEnemy = lab.spawn_bug("ant" if i != 1 else "pill", p_start + Vector3(-5 + i * 3, 0, -4))
		dead.append(e)
	await _frames(50)
	for i in 3:
		(dead[i] as BugEnemy).take_hit(99, Vector3.FORWARD, Vector3.ZERO, kinds[i])
	_check(dead.all(func(e): return not is_instance_valid(e) or not e.alive), "죽음 처리 (일반 · 광선검 · 미사일)")
	await _frames(100)
	_check(dead.all(func(e): return not is_instance_valid(e)), "죽음 연출 뒤 사라진다")
	print("BUG_ENEMIES_CHECK %s" % ("OK" if fails == 0 else "FAILED %d" % fails))
	quit(1 if fails > 0 else 0)
