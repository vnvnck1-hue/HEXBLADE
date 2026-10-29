extends SceneTree
## Run with: Godot --headless --path . -s tests/run_tutorial_check.gd
## 섹터 런 첫 출발 방의 사장 대화형 기본 튜토리얼:
##  1. 켜면 포탈이 안 열리고, 등장 연출 뒤 사장 대사(타자기 → Space · 대화창 클릭 · Enter 로 다음 줄, 필드 클릭은 안 넘김) → 1단계(이동) 해 보기
##     대사 중엔 공격 잠금, Space 대시는 회피 단계 해 보기 전까지 잠금
##  2. 8단계가 실제 입력·명중으로 차례로 완료된다 (이동 · 사격 · 검 · 대시 · 부스터 · 도약 · 궁극기 · 지도), 사격 단계부터 허수아비 둘
##  3. 게임 방식 대사를 Enter 로 넘기면 끝: 허수아비 제거 · 포탈 열림 · 연습에 쓴 미사일·탄창·점수 복구 · 기록
##  4. Backspace 로 전체 건너뛰기 → 바로 포탈
##  5. 꺼져 있거나(enabled=false) 캡처 모드면 뜨지 않는다 (포탈이 바로 열린다)

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
		await physics_frame
	return cond.call()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	await physics_frame
	var up := InputEventKey.new()
	up.physical_keycode = code
	up.keycode = code
	up.pressed = false
	Input.parse_input_event(up)
	await physics_frame


## 사장 대사를 Enter 로 넘겨 k번째 단계의 해 보기까지 간다
func _to_action(tut: RunTutorial, k: int, max_frames := 1500) -> bool:
	for i in max_frames:
		if tut.st == RunTutorial.St.ACTION and tut.idx == k:
			return true
		if tut.st == RunTutorial.St.DONE:
			return false
		if tut.st == RunTutorial.St.SAY:
			await _key(KEY_ENTER)
			continue
		await physics_frame
	return tut.st == RunTutorial.St.ACTION and tut.idx == k


## 캔버스 좌표 pos 를 클릭한다 (헤드리스 창과 캔버스 배율이 달라 창 좌표로 바꿔 보낸다)
func _click(canvas_pos: Vector2) -> void:
	var pos := root.get_final_transform() * canvas_pos
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)
	await physics_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	up.global_position = pos
	Input.parse_input_event(up)
	await physics_frame


func _open_run() -> RunMain:
	var run_state = root.get_node("Run")
	run_state.active = false
	var m: RunMain = (load("res://scenes/run.tscn") as PackedScene).instantiate()
	root.add_child(m)
	current_scene = m
	await _frames(6)
	return m


func _close(m: Node) -> void:
	m.queue_free()
	await _frames(5)


func _run() -> void:
	RunTutorial.force = true
	RunTutorial.persist = false
	var m := await _open_run()
	var tut: RunTutorial = m.tutorial
	var run_state = root.get_node("Run")
	var p := m.player
	_check(tut != null and tut.active(), "첫 출발 방에 튜토리얼이 붙는다")
	_check(not m.portals_open, "튜토리얼 동안 포탈이 닫혀 있다")
	_check(tut.dummies.is_empty(), "이동 단계에는 허수아비가 아직 없다")
	var miss0: int = run_state.missiles
	_check(await _until(func(): return tut.st == RunTutorial.St.SAY and tut.idx == 0, 300), "등장 뒤 사장 대사부터 시작")
	_check(await _until(func(): return tut.line_done(), 400), "대사가 타자기로 다 찍힌다")
	_check(tut.st == RunTutorial.St.SAY and tut.idx == 0, "다 찍혀도 넘기기 전엔 다음으로 안 넘어간다")
	_check(p.attack_lock and p.dash_lock, "대사 중엔 공격·대시 잠금")
	await _click(tut.rect().end + Vector2(10, 200))
	_check(tut.st == RunTutorial.St.SAY and tut.idx == 0, "필드(대화창 밖) 클릭은 대사를 넘기지 않는다")
	await _click(tut.rect().get_center())
	_check(tut.st == RunTutorial.St.ACTION and tut.idx == 0, "대화창 클릭으로 대사를 넘겨 1단계 이동 해 보기")
	_check(not p.attack_lock and p.dash_lock, "해 보기 중엔 공격은 풀리고, 대시는 아직 잠김")
	Input.action_press("dash")
	await _frames(3)
	Input.action_release("dash")
	await _frames(3)
	_check(p.dash_t <= 0.0 and tut._dashes == 0, "회피 단계 전엔 Space 로 대시가 안 된다")

	# 1. 이동
	Input.action_press("move_up")
	_check(await _until(func(): return tut.idx == 0 and tut.st == RunTutorial.St.OK, 900), "이동 6m → 완료 대사")
	Input.action_release("move_up")
	_check(await _to_action(tut, 1), "완료 대사는 저절로 넘어가고 → 2단계 사격 해 보기")
	_check(tut.dummies.size() == 2 and tut.dummies.all(func(d): return is_instance_valid(d) and d.immortal), "사격 단계에 무적 허수아비 둘이 나타난다")
	_check(tut.dummies.all(func(d): var v: Vector3 = d.global_position - p.global_position; v.y = 0; return v.length() < 6.0), "허수아비는 플레이어 곁 6m 안")

	# 2. 사격 (허수아비 명중 8)
	var d0: TrainingDummy = tut.dummies[0]
	for i in 8:
		d0.take_hit(1, Vector3.FORWARD, d0.global_position + Vector3(0, 1, 0), "bullet")
		await physics_frame
	_check(await _until(func(): return tut.st == RunTutorial.St.OK, 300), "사격 명중 → 완료 대사")
	await _until(func(): return tut.line_done(), 400)
	await _key(KEY_SPACE)
	_check(await _until(func(): return tut.st == RunTutorial.St.SAY and tut.idx == 2, 60), "완료 대사는 Space 로도 바로 넘긴다")
	_check(p.dash_t <= 0.0, "그 Space 로 대시는 나가지 않는다")
	_check(await _to_action(tut, 2), "→ 3단계 검")

	# 3. 검 (명중 6)
	for i in 6:
		d0.take_hit(2, Vector3.FORWARD, d0.global_position + Vector3(0, 1, 0), "slash")
		await physics_frame
	_check(await _to_action(tut, 3), "검 명중 6 → 4단계 대시")

	# 4. 대시 (해 보기부터 Space 가 풀린다)
	_check(not p.dash_lock, "회피 단계 해 보기부터 Space 대시가 풀린다")
	for n in 3:
		await _until(func(): return p.dash_t <= 0.0 and p.dash_cd <= 0.0, 600)
		p.aim_override = p.global_position + Vector3(0, 0.95, 3.0)
		Input.action_press("dash")
		await physics_frame
		await physics_frame
		Input.action_release("dash")
		await _until(func(): return p.dash_t > 0.0, 60)
		await _frames(20)
	_check(await _to_action(tut, 4), "대시 → 5단계 부스터")

	# 5. 부스터 1초
	await _until(func(): return p.dash_t <= 0.0, 300)
	Input.action_press("boost")
	_check(await _to_action(tut, 5), "부스터 → 6단계 도약")
	Input.action_release("boost")

	# 6. E 도약
	await _until(func(): return p.leap.cd <= 0.0, 600)
	p.aim_override = p.global_position + Vector3(0, 0.95, -3.0)
	Input.action_press("rush_skill")
	await _frames(3)
	Input.action_release("rush_skill")
	_check(await _to_action(tut, 6), "도약 내려찍기 → 7단계 궁극기")
	p.aim_override = Vector3.INF

	# 7. 궁극기 (미사일 발사)
	await _until(func(): return not p.leap.busy(), 600)
	_check(p.missiles >= 1, "궁극기 단계에는 연습용 미사일이 있다 (%d)" % p.missiles)
	Input.action_press("ult")
	await _until(func(): return p.ult_aiming, 60)
	await _frames(6)
	Input.action_release("ult")
	_check(await _to_action(tut, 7), "미사일 발사 → 8단계 섹터 지도")

	# 8. Tab 지도 열고 닫기
	await _until(func(): return not p.ult_busy(), 600)
	await _key(KEY_TAB)
	_check(run_state.map_view.want, "Tab → 섹터 지도 열림")
	await _frames(3)
	await _key(KEY_TAB)
	_check(await _until(func(): return tut.idx == 8 and tut.st == RunTutorial.St.SAY, 400), "지도 닫기 → 게임 방식 설명 대사")
	_check(not m.portals_open, "설명 대사까지 포탈은 아직 닫힘")

	# 설명 대사를 Enter 로 넘기면 출격
	var n_enter := 0
	while tut.st != RunTutorial.St.DONE and n_enter < 20:
		await _key(KEY_ENTER)
		n_enter += 1
	_check(tut.st == RunTutorial.St.DONE and n_enter >= 3, "설명 대사 3줄을 넘기면 끝 (%d번)" % n_enter)
	_check(not p.attack_lock and not p.dash_lock, "끝나면 잠금 해제")
	_check(await _until(func(): return m.portals_open, 120), "끝나면 포탈이 열린다")
	await _frames(3)
	_check(tut.dummies.is_empty() and get_nodes_in_group("enemies").all(func(e): return not (e is TrainingDummy)), "허수아비 제거")
	_check(p.missiles == miss0 and p.mag == Player.MAG_SIZE and p.reload_t == 0.0, "연습에 쓴 미사일·탄창 복구 (%d/%d)" % [p.missiles, miss0])
	_check(await _until(func(): return m.score == 0, 200), "연습 점수 0")
	await _close(m)

	# Backspace 전체 건너뛰기
	m = await _open_run()
	tut = m.tutorial
	await _until(func(): return tut.st == RunTutorial.St.SAY, 300)
	await _key(KEY_BACKSPACE)
	_check(tut.st == RunTutorial.St.DONE, "Backspace → 전체 건너뛰기")
	_check(await _until(func(): return m.portals_open, 120), "건너뛰면 바로 포탈")
	await _close(m)

	# 꺼짐
	RunTutorial.force = false
	RunTutorial.enabled = false
	m = await _open_run()
	_check(m.tutorial == null, "꺼져 있으면 튜토리얼이 안 붙는다")
	_check(await _until(func(): return m.portals_open, 120), "꺼져 있으면 포탈이 바로 열린다")
	await _close(m)
	RunTutorial.enabled = true

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
