extends SceneTree
## Run with: Godot --headless --path . -s tests/gimmicks_check.gd
## 필드 기믹 (scripts/gimmicks/):
##  1. 연기 구역: 들어가면 숨음·공격 불가·홀로그램, 숨은 동안 적이 쏘지 않고 플레이어 탄도 나가지 않는다.
##     빠져나오면 해제되고 연기 꼬리 가닥이 몸을 따라 끌려 나온다
##  2. 레일: 가만히 서 있어도 띠 속도만큼 실려 간다
##  3. 가스통: 다 깎이면 터져 주변 적·플레이어에 피해, 옆 가스통 연쇄, 그을음·불 자국이 남는다. 처치 수에 세지 않는다
##  4. 수리키트 해치: F 를 PRESSES 번 누르면 열리고, 돌리는 동안 묶이며, 키트를 주우면 체력 +2
##  5. 방 탐색 본편: 전투방에 기믹이 자동 배치된다

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


func _load(path: String) -> Main:
	if current_scene:
		current_scene.queue_free()
		await process_frame
	var m: Main = load(path).instantiate()
	root.add_child(m)
	current_scene = m
	await _frames(4)
	return m


func _player_bullets(m: Main) -> int:
	var n := 0
	for b in m.bullets.get_children():
		if b is Bullet and (b as Bullet).from_player:
			n += 1
	return n


func _run() -> void:
	var lab: GimmickLab = await _load("res://scenes/gimmicks.tscn")
	var p := lab.player
	var g := Gimmicks.inst
	_check(g != null and lab.smoke != null and lab.belt != null, "시험장: 기믹 관리자와 연기·레일 배치")
	# 드론은 따로 세운다 (시험장 자동 소환은 끈다)
	lab._drone_t = 9999.0
	for d in lab.drones:
		d.queue_free()
	lab.drones.clear()

	# ── 1. 연기 ──
	p.bot = true
	lab.phase = 0
	lab.ph_t = 0.0
	p.global_position = lab.smoke.global_position
	var foe := Enemy.new()
	lab.world.add_child(foe)
	foe.global_position = lab.smoke.global_position + Vector3(0, 0, -6.5)
	await _frames(70)
	_check(p.hidden and p.no_attack and GimmickHolo.active(p), "연기 속: 숨음 · 공격 불가 · 홀로그램")
	var eb0 := lab.get_tree().get_nodes_in_group("enemy_bullets").size()
	var pb_max := 0
	var eb_new := 0
	var seen := {}
	var ft0 := foe.fire_timer
	for i in 180:
		await _frames(1)
		p.global_position = lab.smoke.global_position
		pb_max = maxi(pb_max, _player_bullets(lab))
		for b in lab.get_tree().get_nodes_in_group("enemy_bullets"):
			if not seen.has(b.get_instance_id()):
				seen[b.get_instance_id()] = true
				eb_new += 1
	_check(eb_new <= eb0, "숨은 동안 적이 새로 쏘지 않는다 (새 적탄 %d)" % eb_new)
	_check(absf(foe.fire_timer - ft0) < 0.01, "숨은 동안 적의 사격 준비가 멈춘다 (%.2f → %.2f)" % [ft0, foe.fire_timer])
	_check(pb_max == 0, "연기 속에서는 사격 입력이 막힌다 (플레이어 탄 %d)" % pb_max)
	# 빠져나오기: 봇이 오른쪽으로 달려 나간다
	lab.phase = 1
	lab.ph_t = 0.0
	var wisp_max := 0
	for i in 60:
		await _frames(1)
		var w := 0
		for pf in lab.smoke._puffs:
			if pf.wisp:
				w += 1
		wisp_max = maxi(wisp_max, w)
	_check(not lab.smoke.contains(p.global_position) and not p.hidden and not GimmickHolo.active(p), "빠져나오면 은신·홀로그램 해제")
	_check(wisp_max >= 8, "빠져나올 때 연기 가닥이 끌려 나온다 (최대 %d 가닥)" % wisp_max)
	var ft1 := foe.fire_timer
	await _frames(20)
	_check(foe.fire_timer < ft1 - 0.2 or foe.burst_left > 0 or foe.fire_timer > ft1 + 1.0, "드러나면 적이 다시 공격을 준비한다 (%.2f → %.2f)" % [ft1, foe.fire_timer])
	foe.queue_free()

	# ── 2. 레일 ──
	p.bot = false
	var start := lab.belt.global_position - lab.belt.dir * (lab.belt.length * 0.5 - 1.0)
	p.global_position = start
	p.velocity = Vector3.ZERO
	await _frames(2)
	var x0 := p.global_position
	await _frames(60)
	var moved := (p.global_position - x0).dot(lab.belt.dir)
	_check(moved > 3.5 and moved < 6.5, "레일 위에 가만히 서 있어도 실려 간다 (1초 %.1fm)" % moved)
	p.global_position = lab.center + Vector3(0, 0, 3)

	# ── 3. 가스통 ──
	for e in lab.get_tree().get_nodes_in_group("gas_canisters"):
		e.queue_free()
	await _frames(2)
	var at := lab.center + Vector3(-2, 0, -4)
	var b1 := g.add_barrel(at)
	var b2 := g.add_barrel(at + Vector3(2.4, 0, 0))
	var drone := Enemy.new()
	lab.world.add_child(drone)
	drone.global_position = at + Vector3(-1.8, 0, 0)
	p.global_position = at + Vector3(0, 0, 2.2)
	p.invuln = 0.0
	var hp0 := p.hp
	var kills0 := lab.kills
	await _frames(40)            # 드론 착지
	var dhp := drone.hp
	_check(b1.prop and b1.is_in_group("enemies"), "가스통은 판정용 그룹에 들지만 소품이다")
	b1.take_hit(GasCanister.HP, Vector3.FORWARD, b1.global_position + Vector3(0, 0.9, 0))
	await _frames(60)
	_check(not is_instance_valid(b1), "다 깎인 가스통이 터진다")
	_check(not is_instance_valid(b2), "옆 가스통이 연쇄로 터진다")
	_check(not drone.alive or drone.hp < dhp, "주변 적이 폭발 피해를 입는다 (%d → %d)" % [dhp, drone.hp])
	_check(p.hp < hp0, "주변 플레이어도 폭발 피해를 입는다 (%d → %d)" % [hp0, p.hp])
	_check(lab.get_tree().get_nodes_in_group("blast_scorches").size() >= 1, "터진 자리에 그을음과 불이 남는다")
	_check(lab.kills - kills0 <= 1, "가스통 자체는 처치 수에 세지 않는다 (증가 %d)" % (lab.kills - kills0))
	if is_instance_valid(drone):
		drone.queue_free()

	# ── 4. 수리키트 해치 ──
	var h: RepairHatch = null
	for hh in g.hatches:
		if is_instance_valid(hh):
			h = hh
	await _frames(50)            # 솟아오르기 끝
	p.hp = 2
	p.invuln = 999.0
	p.global_position = h.stand_spot()
	await _frames(3)
	_check(h.can_crank(p.global_position), "레버 옆이면 돌릴 수 있다")
	h.crank(p)
	await _frames(2)
	_check(p.rooted and p.no_attack, "돌리는 동안 제자리에 묶이고 공격할 수 없다")
	var mid := 0.0
	for i in RepairHatch.PRESSES - 1:
		h.crank(p)
		await _frames(6)
		if i == RepairHatch.PRESSES / 2:
			mid = h.progress
	_check(mid > 0.3 and mid < 0.8, "누를수록 조금씩 열린다 (중간 %.2f)" % mid)
	_check(h.done, "%d 번 누르면 활짝 열린다" % RepairHatch.PRESSES)
	await _frames(30)
	_check(not p.rooted, "다 열리면 손을 놓는다")
	p.global_position = h.global_position
	await _frames(40)
	_check(p.hp == 2 + RepairHatch.HEAL and h.collected, "키트를 주우면 체력 +%d (%d)" % [RepairHatch.HEAL, p.hp])

	# ── 5. 본편 자동 배치 ──
	var main := await _load("res://scenes/main.tscn")
	await _frames(3)
	var gm := Gimmicks.inst
	var barrels := main.get_tree().get_nodes_in_group("gas_canisters").size()
	var plans := 0
	for k in gm.room_plan:
		if gm.room_plan[k].hatch:
			plans += 1
	_check(gm.smokes.size() + gm.belts.size() + barrels > 0, "방 탐색: 전투방에 기믹 배치 (연기 %d · 레일 %d · 가스통 %d · 해치 예정 %d)" % [gm.smokes.size(), gm.belts.size(), barrels, plans])
	var start_ok := true
	for s in gm.smokes:
		if s.contains(main.player.global_position, 1.0):
			start_ok = false
	_check(start_ok, "시작 자리에는 연기를 두지 않는다")

	print("RESULT gimmicks_check fails=%d" % fails)
	quit(1 if fails > 0 else 0)
