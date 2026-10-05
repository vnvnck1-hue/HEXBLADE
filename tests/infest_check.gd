extends SceneTree
## Run with: Godot --headless --path . -s tests/infest_check.gd
## 감염 오염물 (scripts/infest/, docs/infestation.md):
##  1. 방 탐색 본편에 구석 무더기가 자동 배치된다 (방 안 · 두 벽 구석 근처 · 크기 다양 · 벽 포낭/벽 막 포함 · prop)
##  2. 꿀렁임은 셰이더 TIME 애니메이션 (알주머니마다 위상)
##  3. 실제 플레이어 탄이 무더기에 맞으면 포낭 체력이 깎이고, 다 깎이면 부풀었다 터지며 체액 방울 · 얼룩이 생긴다
##  4. 다 터지면 무더기는 적 판정에서 빠지고 청소 대상 잔해(InfestRemains)가 남는다 → clean 으로 치워진다
##  5. 드론이 잔해를 스스로 치운다 · 큰 포낭은 플레이어를 밀어낸다 · 처치 수에는 세지 않는다

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


func _run() -> void:
	var m: Main = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	await _frames(20)
	m.player.invuln = 9999.0
	var inf := Infestation.inst
	_check(inf != null and inf.nests.size() >= m.map.rooms.size(), "본편: 방마다 무더기 배치 (%d곳)" % (inf.nests.size() if inf else 0))

	# ── 1. 배치 ──
	var in_room := true
	var near_wall := true
	var smin := INF
	var smax := 0.0
	var wall_cysts := 0
	var wall_mems := 0
	var props := true
	for n in inf.nests:
		props = props and n.prop and n.is_in_group("enemies")
		if m.map.room_at(n.global_position) < 0:
			in_room = false
		# 무더기 원점 1.6m 안에 막힌 칸이 있어야 (벽에 붙어 자람)
		var c := m.map.cell_of(n.global_position)
		var wall := false
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if m.map.cell_type(c + Vector2i(dx, dy)) != ArenaMap.FLOOR:
					wall = true
		near_wall = near_wall and wall
		for cy in n.cysts:
			smin = minf(smin, cy.s)
			smax = maxf(smax, cy.s)
			if cy.wall:
				wall_cysts += 1
		for mi in n.mems:
			if absf(mi.global_basis.y.normalized().y) < 0.2:
				wall_mems += 1
	_check(in_room and near_wall, "무더기는 방 안 · 벽 붙은 자리")
	_check(smax / smin > 4.0, "포낭 크기 다양 (%.2f ~ %.2f)" % [smin, smax])
	_check(wall_cysts > 0 and wall_mems > 0, "벽에 붙은 포낭 %d · 벽 연결막 %d" % [wall_cysts, wall_mems])
	_check(props, "무더기는 prop (판정은 받고 처치 수·방 진행에선 빠짐)")
	var sh := InfestMesh.cyst_mat().shader.code
	_check(sh.contains("TIME") and sh.contains("pulse") and InfestMesh.membrane_mat(0).shader.code.contains("TIME"), "꿀렁임: 포낭·막 셰이더 TIME 맥동")

	# ── 3. 실제 탄 ──
	var list := inf.nests.duplicate()
	list.sort_custom(func(a, b): return a.cysts.size() > b.cysts.size())
	var n: InfestNest = list[0]
	var kills0 := m.kills if "kills" in m else 0
	var p := m.player
	# 무더기까지 막힘 없는 자리에서 쏜다
	var from := Vector3.INF
	for a in 32:
		var dd := Vector3(sin(TAU * a / 32.0), 0, cos(TAU * a / 32.0))
		var q := n.global_position + dd * (n.radius + 3.0)
		q.y = n.global_position.y + 1.0
		var clear := true
		for k in 20:
			var s2 := q.lerp(n.global_position + Vector3(0, 1.0, 0), k / 20.0)
			if m.map.is_blocked(s2) and s2.distance_to(n.global_position) > n.radius + 0.3:
				clear = false
		if clear:
			from = q
			break
	var hp0 := 0
	for cy in n.cysts:
		hp0 += cy.hp
	for i in 6:
		var dir := (n.global_position + Vector3(0, 1.0, 0) - from)
		dir.y = 0
		m.add_bullet(Bullet.make_player(from, dir.normalized(), 40.0))
		await _frames(4)
	await _frames(20)
	var hp1 := 0
	var popped := 0
	for cy in n.cysts:
		hp1 += maxi(cy.hp, 0)
		if cy.popped:
			popped += 1
	_check(hp1 < hp0, "플레이어 탄이 포낭에 맞음 (체력 %d → %d)" % [hp0, hp1])
	var splats0 := get_nodes_in_group(BugEnemy.SPLAT_GROUP).size()
	# 남은 것을 모두 터뜨린다 (실제 판정 경로: 검)
	var guard := 0
	var splash_seen := false
	while is_instance_valid(n) and n.alive and guard < 300:
		n.take_hit(3, Vector3.FORWARD, n.global_position, "slash")
		await _frames(3)
		for c in FX.root.get_children():
			if c is InfestSplash:
				splash_seen = true
		guard += 1
	_check(splash_seen, "터질 때 체액 방울 (InfestSplash)")
	await _frames(60)
	_check(get_nodes_in_group(BugEnemy.SPLAT_GROUP).size() > splats0 + 10, "체액 얼룩이 바닥·벽에 남음 (%d개)" % get_nodes_in_group(BugEnemy.SPLAT_GROUP).size())
	_check(not is_instance_valid(n) or not n.is_in_group("enemies"), "다 터진 무더기는 적 판정에서 빠짐")
	if "kills" in m:
		_check(m.kills == kills0, "처치 수에 세지 않음")
	var rem: InfestRemains = null
	for x in get_nodes_in_group(DroneMess.GROUP):
		if x is InfestRemains:
			rem = x
	_check(rem != null and rem.chunks.size() >= 8 and rem.kind == DroneMess.Kind.GOO, "잔해(청소 대상) · 껍질/막 조각 %d개" % (rem.chunks.size() if rem else 0))

	# ── 4. 청소 ──
	if rem:
		var half := rem.clean(rem.work_max * 0.5, rem.global_position + Vector3(0, 1, 0))
		var flown := 0
		for c in rem.chunks:
			if c[2]:
				flown += 1
		_check(not half and flown > 0, "청소 절반: 조각 %d개 빨려 감" % flown)
		_check(rem.clean(rem.work_max, rem.global_position + Vector3(0, 1, 0)), "청소 완료")
		await _frames(40)
		_check(not is_instance_valid(rem), "치운 잔해는 사라짐")

	# ── 5. 드론이 스스로 치운다 ──
	var n2: InfestNest = list[1]
	n2.die()
	await _frames(150)
	var rem2: InfestRemains = null
	for x in get_nodes_in_group(DroneMess.GROUP):
		if x is InfestRemains:
			rem2 = x
	if rem2 and PartnerDrone.inst:
		p.global_position = m.push_out(rem2.global_position + Vector3(1.6, 0, 1.6), 0.5)
		var t := 0
		while is_instance_valid(rem2) and not rem2.done and t < 900:
			p.global_position = m.push_out(rem2.global_position + Vector3(1.6, 0, 1.6), 0.5)
			await _frames(1)
			t += 1
		_check(not is_instance_valid(rem2) or rem2.done, "드론이 잔해를 스스로 청소 (%.1f초)" % (t / 60.0))
	else:
		_check(false, "드론 청소 확인용 잔해")

	# 밀어내기
	var n3: InfestNest = list[2]
	var big: InfestNest.Cyst = null
	for cy in n3.cysts:
		if not cy.wall and (big == null or cy.s > big.s):
			big = cy
	p.global_position = big.pivot.global_position + Vector3(0.05, 0, 0.05)
	await _frames(3)
	var d := Vector2(p.global_position.x - big.pivot.global_position.x, p.global_position.z - big.pivot.global_position.z).length()
	_check(d > big.radius() * 0.7, "큰 포낭은 플레이어를 밀어냄 (%.2fm)" % d)

	print("RESULT %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
