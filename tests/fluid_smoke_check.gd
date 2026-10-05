extends SceneTree
## Run with: Godot --headless --path . -s tests/fluid_smoke_check.gd
## 유체 연기 시험장(fluid_smoke.tscn)의 CPU 쪽 확인. 헤드리스에는 RenderingDevice 가 없어 격자 계산은 꺼지고
## (오류 없이 건너뛰는지), 방출기 수집만 돈다. 실제 GPU 계산은 _capture/fluid_smoke_show.gd 가 수치로 검사한다.
##  1. GPU 가 없으면 active = false · 화면 상자 없음 · 오류 없음. 격자는 8 의 배수로 방을 덮는다.
##  2. 셀 좌표: 격자 가운데 = 방 가운데.
##  3. 방출기: 통풍구(퍼짐+소용돌이) · 외풍 · 서 있는 몸(PUSH) · 움직이는 몸(PART, 진행 방향) ·
##     폭발 바람(Distortion.burst → RADIAL, BLAST_LIFE 뒤 사라짐) · 2단 대시 휠윈드/합체 휠윈드(SWIRL) · 청소 질주(빨아들임).
##  4. 씬이 사라지면 inst 가 비고, blast 는 아무것도 하지 않는다.

var fails := 0
var main: FluidLab
var smoke: FluidSmoke


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _kinds(kind: int) -> Array:
	return smoke.emitters.filter(func(e): return e[0] == kind)


func _run() -> void:
	PartnerDrone.cutin_style = "off"
	var inst := (load("res://scenes/fluid_smoke.tscn") as PackedScene).instantiate()
	if not (inst is FluidLab):
		# 스크립트가 컴파일되지 않으면 멈추지 말고 끝낸다 (헤드리스 테스트가 영영 기다리지 않게)
		print("RESULT FLUID_SMOKE_FAILED (fluid_smoke.tscn 스크립트 로드 실패)")
		quit(1)
		return
	main = inst
	root.add_child(main)
	current_scene = main
	await _frames(30)
	smoke = main.smoke
	_check(is_instance_valid(smoke) and FluidSmoke.inst == smoke, "유체 연기 노드 · inst")
	_check(not smoke.active, "헤드리스: GPU 계산 꺼짐 (오류 없이)")
	_check(smoke.get_child_count() == 0, "헤드리스: 화면 상자 없음")
	_check(smoke.nx % 8 == 0 and smoke.ny % 8 == 0, "격자 %d×%d 는 8 의 배수" % [smoke.nx, smoke.ny])
	_check(smoke.size_m().x >= FluidLab.ROOM_SIZE.x and smoke.size_m().y >= FluidLab.ROOM_SIZE.y, "격자가 방을 덮음 %.1f×%.1fm" % [smoke.size_m().x, smoke.size_m().y])
	var half := Vector3(FluidLab.ROOM_SIZE.x, 0, FluidLab.ROOM_SIZE.y) * 0.5
	_check(smoke.covers(main.center) and smoke.covers(main.center + half * 0.95) and smoke.covers(main.center - half * 0.95), "격자가 방 전체를 덮음")
	# 통풍구 · 외풍
	var radial := _kinds(FluidSmoke.Kind.RADIAL).filter(func(e): return e[6] > 0.0)
	_check(radial.size() == FluidLab.VENTS.size(), "통풍구 %d개가 연기를 냄" % radial.size())
	_check(_kinds(FluidSmoke.Kind.SWIRL).size() == FluidLab.VENTS.size(), "통풍구마다 느린 소용돌이")
	# 스타일 프리셋: 통풍구마다 제 스타일 채널로, 분출량 · 바람은 스타일 값
	_check(FluidSmoke.STYLES.size() == 4 and FluidSmoke.STYLES.any(func(st): return st.id == "toxic"), "스타일 프리셋 4종 (독가스 포함)")
	var chans := radial.map(func(e): return e[7])
	_check(chans == FluidLab.VENT_STYLE, "통풍구마다 다른 스타일 채널 %s" % str(chans))
	var steam_e: Array = radial.filter(func(e): return e[7] == 3)
	var toxic_e: Array = radial.filter(func(e): return e[7] == 2)
	if steam_e.size() == 1 and toxic_e.size() == 1:
		_check(steam_e[0][3] > toxic_e[0][3] * 2.0, "증기는 세게 뿜고 독가스는 낮게 고임 (바람 %.2f / %.2f)" % [steam_e[0][3], toxic_e[0][3]])
	smoke.force_style = 2
	await _frames(2)
	var forced := _kinds(FluidSmoke.Kind.RADIAL).filter(func(e): return e[6] > 0.0).map(func(e): return e[7])
	_check(forced == [2, 2, 2, 2], "F10 고정: 모든 통풍구가 독가스 채널")
	smoke.force_style = -1
	_check(smoke.gpu_bytes() > 0 and smoke.gpu_bytes() < 4 * 1024 * 1024, "GPU 메모리 %.0fKB" % (smoke.gpu_bytes() / 1024.0))
	var big := _kinds(FluidSmoke.Kind.PUSH).filter(func(e): return e[2] > 50.0)
	_check(big.size() == 1, "방 전체 외풍 하나")
	smoke.vents_on = false
	await _frames(2)
	_check(_kinds(FluidSmoke.Kind.SWIRL).is_empty() and _kinds(FluidSmoke.Kind.PUSH).size() == 1, "통풍구 끄면 몸 하나만 남음")
	# 움직이는 몸: 진행 방향으로 가르기
	var p := main.player
	p.rooted = true
	var parts := []
	for i in 6:
		p.global_position += Vector3(0.25, 0, 0)
		await process_frame
		parts = _kinds(FluidSmoke.Kind.PART)
	p.rooted = false
	_check(parts.size() == 1, "움직이면 몸이 연기를 가름 (PART)")
	if parts.size() == 1:
		_check(parts[0][3] > 0.9 and absf(parts[0][4]) < 0.2, "가르기 방향 = 진행 방향 +X (%.2f, %.2f)" % [parts[0][3], parts[0][4]])
		_check(parts[0][5] > 5.0, "빠를수록 세게 옆으로 (%.1f m/s)" % parts[0][5])
	p.global_position += Vector3(30, 0, 0)
	await process_frame
	_check(_kinds(FluidSmoke.Kind.PART).is_empty(), "순간이동은 가르기로 치지 않음")
	p.global_position = main.center
	await _frames(3)
	# 폭발 바람
	Distortion.burst(main.center + Vector3(4, 0.5, 0), 3.0, 0.4, 1.2, 1.0)
	await _frames(2)
	var bl := _kinds(FluidSmoke.Kind.RADIAL)
	_check(bl.size() == 1 and bl[0][3] > 5.0 and bl[0][4] > 0.0, "Distortion.burst → 바깥 바람 + 그을음")
	await create_timer(FluidSmoke.BLAST_LIFE + 0.15).timeout
	_check(_kinds(FluidSmoke.Kind.RADIAL).is_empty(), "폭발 바람은 %.2f초 뒤 사라짐" % FluidSmoke.BLAST_LIFE)
	# 합체 휠윈드
	var dr := PartnerDrone.inst
	_check(is_instance_valid(dr), "파트너 드론 동행")
	if is_instance_valid(dr):
		for i in 900:
			if dr.state == PartnerDrone.St.FOLLOW and dr.link_cd <= 0.0 and dr.whirl_t < 0.0:
				break
			await physics_frame
		dr.whirl_link()
		for i in 300:
			if dr.whirl_t >= 0.0:
				break
			await physics_frame
		await _frames(3)
		var sw := _kinds(FluidSmoke.Kind.SWIRL)
		_check(sw.size() >= 1 and sw.any(func(e): return e[4] < 0.0), "합체 휠윈드: 안쪽으로 감기는 소용돌이")
		while dr.whirl_t >= 0.0:
			await physics_frame
		await _frames(3)
		_check(_kinds(FluidSmoke.Kind.SWIRL).is_empty(), "휠윈드가 끝나면 소용돌이도 끝")
		# 청소 질주
		for i in 120:
			if dr.state == PartnerDrone.St.FOLLOW:
				break
			await physics_frame
		Input.action_press("dash")
		var sucked := false
		for i in 90:
			await physics_frame
			if dr.sweeping and _kinds(FluidSmoke.Kind.RADIAL).any(func(e): return e[3] < 0.0 and e[5] > 0.0):
				sucked = true
				break
		Input.action_release("dash")
		_check(sucked, "청소 질주: 둘레 연기를 빨아들여 먹음")
	# 2단 대시 휠윈드
	await _frames(30)
	p.whirl.start()
	await _frames(2)
	_check(p.whirl.active() and _kinds(FluidSmoke.Kind.SWIRL).any(func(e): return e[4] > 0.0), "2단 대시 휠윈드: 바깥으로 흩뿌리는 소용돌이")
	# 정리
	main.queue_free()
	await _frames(3)
	_check(FluidSmoke.inst == null, "씬이 사라지면 inst 비움")
	FluidSmoke.blast(Vector3.ZERO, 3.0)
	_check(FluidSmoke._blasts.is_empty(), "연기 없는 씬의 blast 는 아무것도 안 함")
	_check(FluidField.inst == null, "씬이 사라지면 FluidField 도 비움")
	# 허수아비 시험장: 안개 둑 + 독가스 세트 (GPU 없이도 세트는 만들어지고 활성으로 넘어간다)
	var tm: TrainingMain = (load("res://scenes/training.tscn") as PackedScene).instantiate()
	root.add_child(tm)
	current_scene = tm
	await create_timer(2.0).timeout
	var ff := FluidField.inst
	_check(ff != null and ff.mode == "training", "허수아비 시험장: FluidField (training)")
	if ff:
		_check(ff.banks.size() == 1 and ff.sets.size() == 1, "안개 둑 1 · 독가스 세트 1")
		_check(ff.sets.size() == 1 and ff.sets[0].clouds.size() == 3 and ff.sets[0].state == FluidField.St.ACTIVE, "독가스 구름 3개 · 활성")
		_check(ff.sets.size() == 1 and absf(ff.sets[0].value - FluidField.VALUE_PER_CLOUD * 3) < 0.01, "세트 값 = 구름 × %.0f" % FluidField.VALUE_PER_CLOUD)
		await _frames(2)
		var mist := ff.smoke.emitters.filter(func(e): return e[0] == FluidSmoke.Kind.RADIAL and e[7] == FluidSmoke.Ch.MIST and e[6] > 0.0)
		_check(mist.size() == 1, "안개 둑은 안개 채널로 뿜음")
		_check(not ff.smoke.emitters.any(func(e): return e[7] == FluidSmoke.Ch.TOXIC and e[6] > 0.0), "독가스는 한 번 만든 뒤 더 뿜지 않음")
		# 빨아 먹은 양이 들어오면 도트로 나눠 게이지에
		var dr2 := PartnerDrone.inst
		tm.infinite = false
		dr2.gauge = 0.0
		var s: Dictionary = ff.sets[0]
		ff.smoke.stat_eaten = s.m0 * 0.5
		var t0 := ff.ticks
		await create_timer(0.12).timeout
		_check(ff.ticks - t0 >= 1 and ff.ticks - t0 <= 8, "도트: 한 번에 다 들어오지 않고 나눠서 (0.12초에 %d번)" % (ff.ticks - t0))
		await create_timer(2.5).timeout
		_check(absf(dr2.gauge - s.value * 0.5) <= 1.5, "절반 빨아들임 = 게이지 %.0f (받은 %.1f)" % [s.value * 0.5, dr2.gauge])
		_check(s.state == FluidField.St.ACTIVE, "절반이면 아직 정화 아님")
		ff.smoke.stat_eaten = s.m0 * 0.5
		await create_timer(3.0).timeout
		_check(s.state == FluidField.St.CLEARED and absf(dr2.gauge - s.value) <= 1.5, "다 빨아들이면 정화 · 게이지 합 %.0f (받은 %.1f)" % [s.value, dr2.gauge])
	tm.queue_free()
	await _frames(3)
	# 방 탐색: 전투방이 열리면 (always) 독가스 세트 2~3개 · 안개
	var mm: Main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(mm)
	current_scene = mm
	await _frames(5)
	ff = FluidField.inst
	_check(ff != null and ff.mode == "field", "방 탐색: FluidField (field)")
	if ff:
		_check(ff.smoke.nx <= 400 and ff.smoke.ny <= 400 and ff.smoke.cell >= 0.2, "맵 전체 격자 %d×%d · 칸 %.2fm" % [ff.smoke.nx, ff.smoke.ny, ff.smoke.cell])
		ff.gas = "always"
		var room := -1
		for r in mm.map.rooms:
			if r.combat:
				room = r.id
				break
		ff._on_room(room)
		_check(ff.sets.size() == 1 and ff.sets[0].clouds.size() >= 2 and ff.sets[0].clouds.size() <= 3, "독가스 세트 구름 2~3개 (%d)" % (ff.sets[0].clouds.size() if ff.sets.size() > 0 else 0))
		_check(ff.banks.size() == 1, "안개 둑 하나")
		var inside: bool = ff.sets.size() == 1 and ff.sets[0].clouds.all(func(c): return mm.map.room_at(c.pos) == room and not mm.map.is_blocked(c.pos))
		_check(inside, "구름은 그 전투방 빈 바닥에")
		ff.gas = "off"
		var n := ff.sets.size()
		ff._on_room(room)
		_check(ff.sets.size() == n, "--gas=off 면 만들지 않음")
	mm.queue_free()
	await _frames(3)
	print("RESULT %s (%d fails)" % ["FLUID_SMOKE_OK" if fails == 0 else "FLUID_SMOKE_FAILED", fails])
	quit(0 if fails == 0 else 1)
