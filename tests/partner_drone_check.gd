extends SceneTree
## Run with: Godot --headless --path . -s tests/partner_drone_check.gd
## 파트너 청소 드론 (scripts/drone/):
##  1. 모델 계약: 관절·부착점 노드, IK 가 디딘 발끝을 바닥 목표에 둔다
##  2. 등장 → 동행, 처치하면 오염이 생기고 드론이 찾아가 치워 게이지가 찬다
##  3. 멀어지면 도약해 따라붙는다 · 적탄을 피한다 · 맞으면 휘청 (파괴 없음)
##  4. G 합체/분리, 합체 중 보조 사격, X 볼텍스(끌어당겨 피해) · X 보호막(피격 1회 막음)
##  5. Z 직접 청소 (공격 불가 → 놓으면 해제) · 체액 웅덩이 감속
##  6. 방 탐색 본편에도 붙는다 · 체액 색 캐시가 늘지 않는다
##  7. 광선검 기본 속도 절반 · 합체하면 검 2배 · 총 연사 2배, 강화를 쓸 때마다 게이지가 줄고 0 이면 저절로 분리
##  8. Q 누르면 즉시 합체(만화 연출) + 휠윈드 2초(움직이며 다단 피해, 게이지 모자라면 합체만) · 합체 중 Q = 분리 · 가만히 서 있으면 자동 청소 · 게이지 효율 1.5배

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


func _until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await physics_frame
	return cond.call()


func _load(path: String) -> Main:
	if current_scene:
		current_scene.queue_free()
		await process_frame
	var m: Main = load(path).instantiate()
	if m is DroneLab:
		(m as DroneLab).spawning = false
	root.add_child(m)
	current_scene = m
	await _frames(4)
	return m


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _run() -> void:
	PartnerDrone.cutin_style = "off"   # 드론 게임플레이(물리 프레임 기준 시간) 검사 — 사선 컷인의 슬로우모션은 diagonal_cutin_check 에서
	var lab: DroneLab = await _load("res://scenes/drone.tscn")
	lab.spawning = false
	for m in get_nodes_in_group(DroneMess.GROUP):
		(m as DroneMess).dissolve()
	await _frames(30)
	var d := PartnerDrone.inst
	var p := lab.player
	_check(d != null and d.rig != null, "시험장에 드론이 붙는다")
	for nm in ["body", "triad", "mod_1", "core_3", "pod_l", "pod_r", "leg_fl_1", "leg_br_2", "pt_foot_bl", "pt_nozzle", "pt_dock"]:
		if d.model.find_child(nm, true, false) == null:
			_check(false, "모델 노드 " + nm)
	_check(await _until(func(): return d.state == PartnerDrone.St.FOLLOW, 90), "등장(낙하·착지) → 동행")
	await _frames(40)
	# IK: 서 있을 때(걸음·톡톡 없음) 발끝이 바닥에 닿아 있다
	await _until(func():
		for s in DroneRig.LEGS:
			if d.rig.legs[s].stepping:
				return false
		return d.rig._fid.leg == "" and d.vel.length() < 0.05, 240)
	var worst := 0.0
	for s in DroneRig.LEGS:
		var f: Vector3 = d.rig.foot_world(s)
		worst = maxf(worst, absf(f.y - Main.gy(f)))
		print("  foot %s y=%.3f ground=%.3f stepping=%s" % [s, f.y, Main.gy(f), d.rig.legs[s].stepping])
	_check(worst < 0.06, "IK: 네 발끝이 바닥에 닿음 (최대 %.3fm)" % worst)

	# ── 처치 → 오염 → 청소 → 게이지 ──
	var e := Enemy.new()
	e.fire_timer = 99.0
	lab.world.add_child(e)
	e.global_position = lab.map.push_out(p.global_position + Vector3(3.0, 0, -2.0), 1.0)
	await _frames(40)
	e.take_hit(999, Vector3.FORWARD, e.global_position, "slash")
	await _frames(2)
	var messes := get_nodes_in_group(DroneMess.GROUP)
	_check(messes.size() == 1, "처치한 자리에 잔해가 남는다 (%d)" % messes.size())
	var g0 := d.gauge
	var val: float = (messes[0] as DroneMess).value
	p.global_position += Vector3(0, 0, 6.0)   # 플레이어가 곁에 서 있으면 자동 청소가 먼저 치우므로 비켜 선다
	var cleaned := await _until(func(): return d.cleaned >= 1, 60 * 8)
	_check(cleaned and d.gauge > g0, "드론이 찾아가 치우고 게이지가 찬다 (%.0f → %.0f)" % [g0, d.gauge])
	_check(is_equal_approx(d.gauge - g0, val * PartnerDrone.GAIN_MUL), "게이지 효율 1.5배 (값 %.1f → +%.1f)" % [val, d.gauge - g0])
	_check(get_nodes_in_group(DroneMess.GROUP).is_empty(), "치운 오염은 사라진다")

	# ── 멀어지면 따라붙기 ──
	p.global_position = lab.map.push_out(lab.center + Vector3(9.0, 0, 6.0), 1.0)
	d.global_position = lab.map.push_out(lab.center + Vector3(-9.0, 0, -6.0), 1.0)
	var caught := await _until(func(): return _flat(d.global_position - p.global_position) < 4.0 and d.state == PartnerDrone.St.FOLLOW, 60 * 5)
	_check(caught, "멀어진 플레이어를 따라붙는다 (거리 %.1fm)" % _flat(d.global_position - p.global_position))

	# ── 적탄 회피 · 피격 ──
	var dodged := false
	for k in 4:
		await _frames(70)
		var o := d.global_position + Vector3(5.0, 0.6, 0.5)
		lab.add_bullet(Bullet.make_enemy(o, (d.global_position + Vector3(0, 0.6, 0) - o).normalized(), 9.0))
		if await _until(func(): return d.dodges > 0, 50):
			dodged = true
			break
	_check(dodged, "날아오는 적탄을 옆으로 뛰어 피한다")
	await _frames(60)
	d._dodge_cd = 99.0
	var o2 := d.global_position + Vector3(-4.0, 0.6, 0.0)
	lab.add_bullet(Bullet.make_enemy(o2, (d.global_position + Vector3(0, 0.6, 0) - o2).normalized(), 9.0))
	_check(await _until(func(): return d.hits_taken > 0, 60), "못 피한 탄은 드론에 맞는다")
	# 맞으면 HURT 로 들어간다 (_hurt). 헤드리스 히트스탑 때문에 이미 풀렸을 수 있어 상태 대신 남아 있는지·멈췄는지 본다
	_check(is_instance_valid(d) and d.state in [PartnerDrone.St.HURT, PartnerDrone.St.FOLLOW, PartnerDrone.St.SEEK], "맞으면 휘청 (파괴되지 않음)")
	d._dodge_cd = 0.0
	_check(await _until(func(): return d.state == PartnerDrone.St.FOLLOW, 90), "휘청 뒤 다시 동행")

	# ── 합체 · 보조 사격 · 볼텍스 · 분리 ──
	_check(is_equal_approx(p.blade_k(), 0.5) and is_equal_approx(p.fire_boost, 1.0), "분리 중: 광선검 속도 0.5배 · 총 기본 연사")
	d.gauge = 0.0
	d.toggle_link()
	await _frames(5)
	_check(d.state != PartnerDrone.St.RECALL and d.state != PartnerDrone.St.DOCKED, "게이지가 없으면 합체하지 않는다")
	d.gauge = PartnerDrone.WHIRL_COST - 5.0
	# Q (휠윈드 게이지 모자람) → 거절 (Q 합체는 휠윈드 한 번으로 끝나므로 합체만 하지 않는다)
	Input.action_press("drone_link")
	await _frames(4)
	Input.action_release("drone_link")
	await _frames(10)
	_check(d.state != PartnerDrone.St.RECALL and d.state != PartnerDrone.St.DOCKED and d.whirls == 0, "Q: 휠윈드 게이지가 모자라면 합체하지 않는다")
	d.toggle_link()
	_check(await _until(func(): return d.state == PartnerDrone.St.DOCKED, 60), "보통 합체(toggle_link): 날아와 합체 · 유지")
	_check(d.whirls == 0, "보통 합체는 휠윈드 없음")
	d.gauge = PartnerDrone.GAUGE_MAX
	await _frames(2)
	_check(is_equal_approx(p.blade_k(), 1.0) and is_equal_approx(p.fire_boost, 2.0), "합체 중: 광선검 속도 2배(=예전 속도) · 총 연사 2배")
	var gs := d.gauge
	p.on_attack.call("shot")
	p.on_attack.call("slash")
	_check(is_equal_approx(gs - d.gauge, PartnerDrone.SHOT_COST + PartnerDrone.SLASH_COST), "합체 강화 공격은 게이지를 깎는다 (%.2f)" % (gs - d.gauge))
	var back := d.global_position - p.global_position
	_check(back.y > 0.6 and _flat(back) < 1.2, "합체 위치: 메카 등 뒤 위 (높이 %.2f · 수평 %.2f)" % [back.y, _flat(back)])
	var foe := Enemy.new()
	foe.fire_timer = 99.0
	lab.world.add_child(foe)
	foe.global_position = lab.map.push_out(p.global_position + Vector3(0, 0, -6.0), 1.0)
	var hp0 := 0
	await _frames(40)
	hp0 = foe.hp
	_check(await _until(func(): return foe.hp < hp0 or not foe.alive, 60 * 3), "합체 중 세 모듈이 가까운 적을 쏜다")
	var foe2 := Enemy.new()
	foe2.fire_timer = 99.0
	lab.world.add_child(foe2)
	foe2.global_position = lab.map.push_out(p.global_position + Vector3(5.5, 0, 1.0), 1.0)
	await _frames(40)
	var dist0 := _flat(foe2.global_position - p.global_position)
	var hp2 := foe2.hp
	d.gauge = PartnerDrone.GAUGE_MAX
	d.use_skill()
	_check(d.vortex_t >= 0.0 and d.gauge == PartnerDrone.GAUGE_MAX - PartnerDrone.SKILL_COST, "X(합체): 볼텍스 시작 · 게이지 50 소모")
	await _frames(30)
	var dist1 := _flat(foe2.global_position - p.global_position)
	await _frames(30)
	_check(dist1 < dist0 - 0.5, "볼텍스가 적을 끌어당긴다 (%.1f → %.1fm)" % [dist0, dist1])
	_check(not foe2.alive or foe2.hp < hp2, "볼텍스가 터지며 피해")
	d.toggle_link()
	_check(await _until(func(): return d.state == PartnerDrone.St.FOLLOW, 60), "Q: 분리해 뒤로 뛰어내림")
	_check(absf(d.global_position.y - Main.gy(d.global_position)) < 0.05 and d.scale_k > 0.99, "분리 뒤 바닥에 원래 크기")

	_check(is_equal_approx(p.blade_k(), 0.5) and is_equal_approx(p.fire_boost, 1.0), "분리하면 강화가 풀린다")

	# ── Q = 합체 + 휠윈드 ──
	await _frames(40)
	d.gauge = PartnerDrone.GAUGE_MAX
	var w1 := Enemy.new()
	w1.fire_timer = 99.0
	w1.hp = 300
	lab.world.add_child(w1)
	w1.global_position = lab.map.push_out(p.global_position + Vector3(1.8, 0, 0.0), 1.0)
	await _frames(45)
	var whp := w1.hp
	Input.action_press("drone_link")
	await _frames(2)
	Input.action_release("drone_link")
	_check(d.state == PartnerDrone.St.RECALL, "Q 를 누르는 즉시 합체 비행 시작")
	lab.god = false
	p.invuln = 0.0
	var gattai_seen := false
	for i in 120:
		await physics_frame
		for ch in lab.get_children():
			if ch is GattaiFX:
				gattai_seen = true
		if d.whirl_t >= 0.0:
			break
	_check(d.whirl_t >= 0.0, "붙자마자 휠윈드 시작")
	_check(gattai_seen, "합체 순간 만화식 합체 연출 (집중선 · 합체!! 말풍선)")
	_check(d.state == PartnerDrone.St.DOCKED and is_equal_approx(d.gauge, PartnerDrone.GAUGE_MAX - PartnerDrone.WHIRL_COST), "휠윈드: 합체 · 게이지 %d 소모" % int(PartnerDrone.WHIRL_COST))
	_check(p.invuln > 0.0, "휠윈드 시작 순간부터 무적")
	var px := p.global_position
	await _frames(2)
	_check(p.spin_pose.is_valid() and is_equal_approx(p.trail.life, PartnerDrone.WHIRL_LIFE) and is_equal_approx(p.trail.bright, 1.0) and p.body_trails[0].active, "휠윈드: 회오리 자세 · 광선검 리본 길게(원래 밝기) · 팔다리 리본 켜짐")
	_check(is_equal_approx(p.slow_mul, PartnerDrone.WHIRL_SPEED), "휠윈드 중 이동 속도 %.1f배" % p.slow_mul)
	Input.action_press("move_right")   # 적(오른쪽 1.8m)을 지나 밀고 간다
	var spun := 0.0
	var a0 := p.visual.rotation.y
	# 히트스탑(실제 시간)이 걸리면 헤드리스에선 물리 틱이 아주 느리게 흐르므로 끝날 때까지 지켜본다
	var guard_ok := true
	var hp_w := p.hp
	for i in 1500:
		await process_frame
		spun = maxf(spun, absf(angle_difference(a0, p.visual.rotation.y)))
		if d.whirl_t < 0.0:
			break
		if p.invuln <= 0.0 or p.take_hit(p.global_position + Vector3(2, 0, 0)):
			guard_ok = false
	_check(guard_ok and p.hp == hp_w, "휠윈드 내내 무적 (맞아도 체력 %d → %d)" % [hp_w, p.hp])
	_check(p.invuln < 0.1, "휠윈드가 끝나면 무적도 바로 끝 (남은 %.2f초)" % p.invuln)
	lab.god = true
	Input.action_release("move_right")
	_check(_flat(p.global_position - px) > 1.0, "휠윈드 중 방향키로 움직인다 (%.1fm)" % _flat(p.global_position - px))
	_check(spun > 1.0 and d.whirl_t < 0.0, "휠윈드 중 몸이 돈다")
	_check(not p.spin_pose.is_valid() and is_equal_approx(p.trail.life, Player.SABER_RIBBON_LIFE) and is_equal_approx(p.trail.bright, Player.SABER_RIBBON_BRIGHT) and is_equal_approx(p.slow_mul, 1.0), "휠윈드가 끝나면 자세 · 리본(기본 수명 · 밝기) · 속도가 돌아온다")
	_check(whp - w1.hp >= 6 or not w1.alive, "휠윈드 다단 피해 (%d)" % (whp - w1.hp))
	_check(await _until(func(): return d.whirl_t < 0.0, 60), "2초 뒤 휠윈드 끝")
	_check(d.state != PartnerDrone.St.DOCKED and d.state != PartnerDrone.St.RECALL, "휠윈드가 끝나면 저절로 분리 (합체 유지 안 함)")
	_check(not p.no_attack, "휠윈드 뒤 다시 공격 가능")
	_check(await _until(func(): return d.state == PartnerDrone.St.FOLLOW, 120), "분리 착지 뒤 동행")
	# 게이지를 다 쓰면 저절로 분리 (보통 합체로 붙인 뒤)
	d.gauge = PartnerDrone.GAUGE_MAX
	await _frames(40)
	d.toggle_link()
	await _until(func(): return d.state == PartnerDrone.St.DOCKED, 120)
	d.gauge = 1.0
	p.on_attack.call("slash")
	_check(await _until(func(): return d.state == PartnerDrone.St.FOLLOW, 90), "게이지가 바닥나면 저절로 분리")
	w1.queue_free()

	# ── 보호막 ──
	for n in get_nodes_in_group("enemies"):
		n.queue_free()
	p.global_position = lab.center   # 벽 곁에서 벗어나 탄이 벽에 막히지 않게
	await _frames(70)
	d.gauge = PartnerDrone.GAUGE_MAX
	d.use_skill()
	_check(is_instance_valid(d.shield) and p.hit_guard.is_valid(), "X(분리): 돌파 보호막")
	lab.god = false
	p.invuln = 0.0
	var php := p.hp
	var away := p.global_position - d.global_position
	away.y = 0
	var o3 := p.global_position + away.normalized() * 4.0 + Vector3(0, 0.95, 0)
	var h0 := d.hits_taken
	lab.add_bullet(Bullet.make_enemy(o3, (p.global_position + Vector3(0, 0.95, 0) - o3).normalized(), 10.0))
	await _until(func(): return d.blocks > 0 or p.hp < php, 120)
	_check(d.blocks == 1 and p.hp == php, "보호막이 피격 1회를 막는다 (체력 %d → %d · 막음 %d · 드론 피격 %d)" % [php, p.hp, d.blocks, d.hits_taken - h0])
	await _frames(20)
	_check(not is_instance_valid(d.shield) and not p.hit_guard.is_valid(), "막은 보호막은 사라지고 훅도 풀린다")
	lab.god = true

	# ── 직접 청소 · 체액 감속 ──
	for m in get_nodes_in_group(DroneMess.GROUP):
		(m as DroneMess).dissolve()
	d._go(PartnerDrone.St.DOWN)
	var goo := DroneMess.spawn(lab.world, p.global_position + Vector3(0, 0, -0.4), DroneMess.Kind.GOO, 1.2, Color(0.61, 0.93, 0.21))
	await _frames(5)
	_check(p.slow_mul < 1.0, "체액 웅덩이를 밟으면 느려진다 (%.2f)" % p.slow_mul)
	Input.action_press("drone_clean")
	await _frames(3)
	_check(p.no_attack, "Z 누르는 동안: 공격 불가")
	var done := await _until(func(): return not is_instance_valid(goo) or goo.done, 60 * 3)
	Input.action_release("drone_clean")
	await _frames(3)
	_check(done and d.player_cleaned >= 1, "Z 직접 청소로 웅덩이를 치운다")
	_check(not p.no_attack and is_equal_approx(p.slow_mul, 1.0), "Z 를 놓으면 공격 가능 · 감속 해제")
	# 가만히 서 있으면 자동 청소 (Z 없이)
	var pc := d.player_cleaned
	var near := DroneMess.spawn(lab.world, p.global_position + Vector3(1.6, 0, 0.8), DroneMess.Kind.SCRAP, 1.0)
	_check(await _until(func(): return not is_instance_valid(near) or near.done, 60 * 4), "오염 곁에 가만히 서 있으면 저절로 청소")
	_check(d.player_cleaned > pc and not p.no_attack, "자동 청소는 공격을 막지 않는다")
	d._go(PartnerDrone.St.FOLLOW)

	# ── 체액 색 캐시 ──
	var before := DroneMess._goo_mats.size()
	for i in 30:
		DroneMess.spawn(lab.world, lab.center, DroneMess.Kind.GOO, 1.0, Color(0.6 + randf() * 0.04, 0.9 + randf() * 0.04, 0.2)).dissolve()
	_check(DroneMess._goo_mats.size() <= before + 2, "무작위에 가까운 체액 색도 캐시를 키우지 않는다 (%d → %d)" % [before, DroneMess._goo_mats.size()])

	# ── 방 탐색 본편 ──
	var m2: Main = await _load("res://scenes/main.tscn")
	await _frames(60)
	_check(PartnerDrone.inst != null and PartnerDrone.inst.main == m2, "방 탐색 본편에도 드론이 붙는다")

	print("RESULT partner_drone_check fails=%d" % fails)
	quit(1 if fails > 0 else 0)
