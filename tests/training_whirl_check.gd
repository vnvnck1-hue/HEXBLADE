extends SceneTree
## Run with: Godot --headless --path . -s tests/training_whirl_check.gd
## 허수아비 시험장의 드론 Q 합체 휠윈드:
##  1. 재화 무한(기본)이면 드론 게이지가 늘 가득 → Q 합체 휠윈드를 연달아 몇 번이고 쓸 수 있다
##  2. 휠윈드가 끝나면 저절로 분리 (합체 유지 없음)
##  3. 휠윈드 시작부터 끝까지 메카 무적 (시험장 플레이어 무적을 꺼도)
##  4. 재화 무한을 끄면 게이지가 줄어든다

var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _run() -> void:
	var m: TrainingMain = load("res://scenes/training.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	for i in 4:
		await physics_frame
	var d := PartnerDrone.inst
	var p := m.player
	_check(d != null, "허수아비 시험장에 드론이 붙는다")
	_check(await _until(func(): return d.state == PartnerDrone.St.FOLLOW, 600), "드론 동행 시작")
	m.god = false
	d.gauge = 0.0
	await physics_frame
	await physics_frame
	_check(is_equal_approx(d.gauge, PartnerDrone.GAUGE_MAX), "재화 무한: 드론 게이지가 늘 가득")
	for n in 3:
		await _until(func(): return d.state == PartnerDrone.St.FOLLOW and d.link_cd <= 0.0 and d.whirl_t < 0.0, 900)
		p.invuln = 0.0
		d.whirl_link()
		_check(d.state == PartnerDrone.St.RECALL, "Q 합체 %d번째 시작" % (n + 1))
		_check(await _until(func(): return d.whirl_t >= 0.0, 300), "붙자마자 휠윈드 %d" % (n + 1))
		var guard := true
		var hp0 := p.hp
		while d.whirl_t >= 0.0:
			if p.invuln <= 0.0 or p.take_hit(p.global_position + Vector3(1, 0, 0)):
				guard = false
			await process_frame
		_check(guard and p.hp == hp0, "휠윈드 %d 내내 무적" % (n + 1))
		await process_frame
		_check(d.state != PartnerDrone.St.DOCKED, "휠윈드 %d 끝 → 저절로 분리" % (n + 1))
		_check(p.invuln < 0.1, "휠윈드 %d 끝나면 무적도 끝 (%.2f)" % [n + 1, p.invuln])
		_check(is_equal_approx(d.gauge, PartnerDrone.GAUGE_MAX), "휠윈드 %d 뒤에도 게이지 가득" % (n + 1))
	m.infinite = false
	await _until(func(): return d.state == PartnerDrone.St.FOLLOW and d.link_cd <= 0.0, 900)
	d.gauge = PartnerDrone.GAUGE_MAX
	d.whirl_link()
	await _until(func(): return d.whirl_t >= 0.0, 300)
	_check(d.gauge <= PartnerDrone.GAUGE_MAX - PartnerDrone.WHIRL_COST + 0.01, "재화 무한을 끄면 게이지를 쓴다")
	await _until(func(): return d.whirl_t < 0.0, 1500)
	m.god = true
	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
