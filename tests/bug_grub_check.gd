extends SceneTree
## Run with: Godot --headless --path . -s tests/bug_grub_check.gd
## 애벌레 (bug_grub.glb · GrubRig · BugGrub · SlimeTrail) 확인:
##  1. 모델: 몸통 · 머리 · 더듬이 3마디 사슬 · 부착점 · 기본 회전 0 · 정면 = -Z · 바닥 위 · 몸통 재질 2개(크림 · 띠)
##  2. 리그: 몸통이 뼈 9개 스켈레톤으로 스키닝됨 · 기는 동안 몸 길이가 줄었다 늘었다(연동 수축) ·
##     수축이 꼬리에서 먼저 시작해 머리로 번짐 · 바닥을 붙잡은 고리는 월드에서 멈춰 있음(미끄러지지 않음) ·
##     줄어든 구간이 높게 부풂 · 더듬이가 움직이고 끝 마디가 늦게 따라옴 · 공격 준비 = 움츠림 / 돌진 = 늘어남 ·
##     왼쪽으로 돌면 몸이 휜다 · 모든 값 유한
##  3. 시험장: 기어 나와 알아채고 다가와 움츠렸다 덮친다 · 지나간 자리에 점액 흔적 · 죽은 뒤에도 흔적이 남았다 마르면 사라짐

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


func _bone_w(r: GrubRig, i: int) -> Vector3:
	return r.skel.global_transform * r.skel.get_bone_global_pose(i).origin


func _run() -> void:
	# ── 1. 모델 ──
	var m := (load(BugGrub.MODEL) as PackedScene).instantiate() as Node3D
	root.add_child(m)
	var body := m.get_node_or_null("body") as MeshInstance3D
	_check(body != null, "통짜 몸통 body")
	_check(m.get_node_or_null("head/feeler_l_1/feeler_l_2/feeler_l_3") != null
		and m.get_node_or_null("head/feeler_r_1/feeler_r_2/feeler_r_3") != null, "머리 > 더듬이 3마디 사슬 좌우")
	_check(_rot_zero(m), "모든 파츠 기본 회전 0")
	var aabb := body.get_aabb()
	_check(aabb.size.z > 1.25 and aabb.size.z < 1.5 and aabb.size.x > 0.85 and aabb.size.y > 0.45 and aabb.size.y < 0.56,
		"몸통 크기 길이 %.2f · 폭 %.2f · 높이 %.2f (3면도 비율: 낮고 넓은 돔)" % [aabb.size.z, aabb.size.x, aabb.size.y])
	_check(absf(aabb.position.y) < 0.01, "몸통 바닥이 y=0")
	_check(body.mesh.get_surface_count() == 2, "몸통 재질 2개 (크림 · 띠)")
	var tip := m.find_child("pt_feeler_tip_l") as Node3D
	_check(tip != null and tip.global_position.z < -0.8 and tip.global_position.x < 0.0 and tip.global_position.y > -0.01,
		"왼쪽 더듬이 끝이 앞(-Z) · 왼쪽 · 바닥 위 %s" % (tip.global_position if tip else Vector3.ZERO))
	_check(m.find_child("pt_eye_l") != null and m.find_child("pt_tail") != null, "부착점 pt_eye_l · pt_tail")
	m.queue_free()

	# ── 2. 리그 ──
	var holder := Node3D.new()
	root.add_child(holder)
	var gm := (load(BugGrub.MODEL) as PackedScene).instantiate() as Node3D
	holder.add_child(gm)
	var r := GrubRig.new().setup(gm)
	_check(r.skel != null and r.skel.get_bone_count() == GrubRig.NB, "몸통 스켈레톤 뼈 %d개" % GrubRig.NB)
	var bmi := r.skel.get_node_or_null("body") as MeshInstance3D
	_check(bmi != null and bmi.skin != null and bmi.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_BONES != 0, "몸통이 스킨 가중치를 가진 메시")
	# 기기: 몸 중심을 일정 속도로 옮기며 한 주기를 넘게 돌린다
	var dt := 1.0 / 60.0
	var spd := BugGrub.CRAWL_SPEED
	r.speed = spd
	for i in 120:
		holder.position += Vector3(0, 0, -spd * dt)
		r.update(dt)
	var min_len := 99.0
	var max_len := 0.0
	var max_sy := 0.0
	var tail_stop := 99.0
	var head_stop := 99.0
	var tail_move_t := -1.0
	var head_move_t := -1.0
	var finite := true
	var low := 0.0
	var prev_t := _bone_w(r, 0)
	var prev_h := _bone_w(r, GrubRig.NB - 1)
	var cyc := 0
	var f_min := 9.0
	var f_max := -9.0
	var tip_lag := false
	var start_phase := floorf(r.phase)
	for i in 150:
		holder.position += Vector3(0, 0, -spd * dt)
		r.update(dt)
		var pt := _bone_w(r, 0)
		var ph := _bone_w(r, GrubRig.NB - 1)
		var l := pt.distance_to(ph)
		min_len = minf(min_len, l)
		max_len = maxf(max_len, l)
		for b in GrubRig.NB:
			var s := r.skel.get_bone_pose_scale(b)
			max_sy = maxf(max_sy, s.y)
			var p := r.skel.get_bone_pose_position(b)
			if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z) and is_finite(s.y)):
				finite = false
			low = minf(low, p.y)
		var vt := (pt - prev_t).length() / dt
		var vh := (ph - prev_h).length() / dt
		tail_stop = minf(tail_stop, vt)
		head_stop = minf(head_stop, vh)
		# 한 주기 안에서 꼬리·머리가 처음으로 빨리(몸 중심보다) 움직인 시각
		var fr := r.phase - start_phase
		if fr >= 1.0 and fr < 2.0:
			if tail_move_t < 0.0 and vt > spd * 1.3:
				tail_move_t = fr
			if head_move_t < 0.0 and vh > spd * 1.3:
				head_move_t = fr
		prev_t = pt
		prev_h = ph
		var fs := r.feelers[0][0] as Array
		var a1: float = (fs[0] as Node3D).rotation.y
		f_min = minf(f_min, a1)
		f_max = maxf(f_max, a1)
		if absf((fs[2] as Node3D).rotation.y - (fs[1] as Node3D).rotation.y) > 0.01:
			tip_lag = true
	var rest_len := GrubRig.SPAN
	_check(max_len - min_len > rest_len * 0.12, "기는 동안 몸 길이가 줄었다 늘었다 %.2f ~ %.2f m (연동 수축·이완)" % [min_len, max_len])
	_check(tail_move_t >= 0.0 and head_move_t >= 0.0 and tail_move_t < head_move_t,
		"수축이 꼬리에서 먼저 시작해 머리로 번진다 (꼬리 %.2f → 머리 %.2f 주기)" % [tail_move_t, head_move_t])
	_check(tail_stop < spd * 0.1 and head_stop < spd * 0.1,
		"바닥을 붙잡은 꼬리·머리는 월드에서 멈춘다 (최소 속도 꼬리 %.3f · 머리 %.3f m/s, 몸 중심 %.2f)" % [tail_stop, head_stop, spd])
	_check(max_sy > 1.06, "줄어든 구간이 높게 부푼다 (높이 배율 최대 %.2f)" % max_sy)
	_check(low > -0.01, "고리가 바닥 밑으로 내려가지 않는다 (최저 %.3f)" % low)
	_check(finite, "기는 동안 뼈 값 유한")
	_check(f_max - f_min > 0.25, "기는 동안 더듬이가 좌우를 쓴다 (yaw 폭 %.2f rad)" % (f_max - f_min))
	_check(tip_lag, "더듬이 끝 마디가 뿌리보다 늦게 따라온다 (채찍)")
	# 공격 준비 · 돌진
	r.speed = 0.0
	for i in 90:
		r.update(dt)
	var len0 := _bone_w(r, 0).distance_to(_bone_w(r, GrubRig.NB - 1))
	r.windup = 1.0
	for i in 20:
		r.update(dt)
	var len_w := _bone_w(r, 0).distance_to(_bone_w(r, GrubRig.NB - 1))
	var head_up := r.head.position.y
	r.windup = 0.0
	r.lunge = 1.0
	for i in 10:
		r.update(dt)
	var len_l := _bone_w(r, 0).distance_to(_bone_w(r, GrubRig.NB - 1))
	_check(len_w < len0 * 0.85, "공격 준비: 몸을 움츠린다 (%.2f → %.2f m)" % [len0, len_w])
	_check(head_up > 0.2, "공격 준비: 앞몸을 쳐든다 (머리 높이 %.2f)" % head_up)
	_check(len_l > len0 * 1.15, "덮치기: 몸을 앞으로 늘인다 (%.2f → %.2f m)" % [len0, len_l])
	r.lunge = 0.0
	# 왼쪽으로 돌며 기기 → 머리 쪽 뼈가 왼쪽(+yaw)으로
	r.speed = 0.5
	r.turn = 1.0
	for i in 60:
		r.update(dt)
	var hq := r.skel.get_bone_pose_rotation(GrubRig.NB - 1).get_euler()
	var tq := r.skel.get_bone_pose_rotation(0).get_euler()
	_check(hq.y > 0.1 and tq.y < -0.1, "왼쪽으로 돌면 몸이 활처럼 휜다 (머리 yaw %.2f · 꼬리 %.2f)" % [hq.y, tq.y])
	# 죽음 · 어질 · 땅속 몇 초
	r.turn = 0.0
	r.speed = 0.0
	r.dizzy = 1.0
	r.alarm = 1.0
	for i in 60:
		r.update(dt)
	r.dizzy = 0.0
	r.dead_k = 1.0
	r.emerge_k = 0.2
	var drift := false
	for i in 120:
		r.update(dt)
		for b in GrubRig.NB:
			var p := r.skel.get_bone_pose_position(b)
			if not (is_finite(p.x) and is_finite(p.y)) or p.length() > 3.0:
				drift = true
	_check(not drift, "어질·피격·죽음·땅속 — 뼈 값 유한")
	holder.queue_free()

	# ── 3. 시험장 ──
	var lab = (load("res://scenes/bugs.tscn") as PackedScene).instantiate()
	root.add_child(lab)
	current_scene = lab
	await _frames(3)
	for e in lab._bugs():
		e.queue_free()
	await _frames(2)
	var p_start: Vector3 = lab.player.global_position
	var g: BugGrub = lab.spawn_bug("grub", p_start + Vector3(0, 0, -7.0))
	await _frames(50)
	_check(is_instance_valid(g) and g.landed, "땅에서 기어 나왔다")
	var noticed := false
	var crawled := false
	var wound := false
	var lunged := false
	for i in 900:
		await physics_frame
		lab.player.global_position = p_start
		if not is_instance_valid(g):
			break
		noticed = noticed or g.state == BugGrub.G.NOTICE
		crawled = crawled or (g.state == BugGrub.G.CHASE and g.cur_speed > 0.5)
		wound = wound or g.state == BugGrub.G.WINDUP
		lunged = lunged or g.state == BugGrub.G.LUNGE
		if lunged and crawled:
			break
	_check(noticed, "플레이어를 알아채고 앞몸을 든다")
	_check(crawled, "기어서 다가온다")
	_check(wound, "몸을 움츠려 공격을 준비한다 (패링 가능 예고)")
	_check(lunged, "몸을 늘이며 덮친다")
	var tr: SlimeTrail = g.trail
	_check(is_instance_valid(tr) and tr.pts.size() > 8, "지나간 자리에 점액 흔적 (점 %d개)" % (tr.pts.size() if is_instance_valid(tr) else 0))
	_check(is_instance_valid(tr) and (tr.mesh as ArrayMesh).get_surface_count() == 1, "흔적 띠 메시가 만들어짐")
	var sh := (tr.material_override as ShaderMaterial).shader.code if is_instance_valid(tr) else ""
	_check(sh.contains("blend_mix") and sh.contains("ALPHA"), "흔적은 반투명 재질")
	_check(g.goo == BugGrub.GOO_W, "피격 체액 색 = 크림")
	var dead: Array = []
	var kinds := ["bullet", "slash", "missile"]
	for i in 3:
		dead.append(lab.spawn_bug("grub", p_start + Vector3(-4 + i * 4, 0, -5)))
	await _frames(50)
	for i in 3:
		(dead[i] as BugEnemy).take_hit(99, Vector3.FORWARD, Vector3.ZERO, kinds[i])
	_check(dead.all(func(e): return not is_instance_valid(e) or not e.alive), "죽음 처리 (일반 · 광선검 · 미사일)")
	g.take_hit(99, Vector3.FORWARD, Vector3.ZERO, "bullet")
	await _frames(100)
	_check(dead.all(func(e): return not is_instance_valid(e)), "죽음 연출 뒤 사라진다")
	_check(is_instance_valid(tr) and not tr.owner_alive and tr.pts.size() > 0, "주인이 죽어도 흔적은 남아 있다")
	if is_instance_valid(tr):
		tr.clock += SlimeTrail.LIFE + 1.0      # 시간을 건너뛰어 마르게
	await process_frame
	await process_frame
	await process_frame
	_check(not is_instance_valid(tr), "흔적이 다 마르면 스스로 사라진다")
	print("BUG_GRUB_CHECK %s" % ("OK" if fails == 0 else "FAILED %d" % fails))
	quit(1 if fails > 0 else 0)
