extends SceneTree
## Run with: Godot --headless --path . -s tests/dialogue_check.gd
## 캐릭터 대화 시스템 (scripts/dialogue/) 을 확인한다.
##  1. data/dialogue/*.dlg 가 오류 없이 읽히고, 표정 그림이 모두 있다.
##  2. 꾸밈 문법: 색 · 흔들림 → BBCode, 문장부호 자동 멈춤, {p=} 멈춤, {fast} 속도, '[' 이스케이프.
##  3. 진행기: 선택지 분기 · 변수 · 조건부 선택지 · @if · 요약 · 끝.
##  4. 화면: 타자기 출력이 조금씩 나오고, 진행 입력이 문장을 완성한 뒤 다음 줄로 간다. 화자 강조 · 표정 바뀜 ·
##     선택지 버튼 · 숫자 고르기 · 기록 · 자동 진행 · Tab 건너뛰기 요약 · 끝 신호.

var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## 조건이 맞을 때까지 프레임을 넘긴다 (헤드리스는 프레임 시간이 짧으므로 실제 시간 기준)
func _until(cond: Callable, sec: float) -> bool:
	var end := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _run() -> void:
	# 헤드리스 기본 창 모양과 무관하게 실제 게임의 1280×800 배치를 검증한다.
	root.size = Vector2i(1280, 800)
	root.content_scale_size = Vector2i(1280, 800)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	await _frames(2)
	# ── 1. 파일 ──
	for f in DirAccess.get_files_at("res://data/dialogue"):
		if f.ends_with(".dlg"):
			var s := DialogueScript.load_file("res://data/dialogue/" + f)
			_check(s.errors.is_empty() and s.items.size() > 5, "%s 읽기 (명령 %d, 오류 %s)" % [f, s.items.size(), str(s.errors)])
	var missing := []
	for id in DialogueCast.CAST:
		for e in DialogueCast.CAST[id].expr:
			if DialogueCast.texture(id, e) == null:
				missing.append(id + ":" + e)
	_check(missing.is_empty(), "등록된 포트레이트 그림 모두 있음 %s" % str(missing))
	# 새 오프닝의 두 질문 × 두 응답을 모두 끝까지 실행한다.
	var opening := DialogueScript.load_file("res://data/dialogue/cleaning_opening.dlg")
	for question in 2:
		for attitude in 2:
			var intro := DialogueRunner.new(opening)
			var expressions: Array = []
			intro.said.connect(func(l):
				if l.who == "owner" and not expressions.has(l.expr):
					expressions.append(l.expr))
			intro.start()
			var choices := 0
			for step in 200:
				if intro.done:
					break
				if intro.waiting_choice:
					intro.choose(question if choices == 0 else attitude)
					choices += 1
				else:
					intro.advance()
			_check(intro.done and choices == 2 and intro.flags.get("first_contract_ready", false), "청소업체 오프닝 분기 %d/%d 끝까지, 의뢰 준비" % [question, attitude])
			_check(intro.flags.get("asked_payment" if question == 0 else "asked_safety", false)
				and intro.flags.get("opening_attitude") == ("nervous" if attitude == 0 else "confident")
				and expressions.has("welcome") and expressions.has("briefing") and expressions.has("encouragement"), "질문/응답 분기 보존, 사장 표정 3종 사용")
	var bad := DialogueScript.from_text("ghost: 누구?\n@enter mira nowhere\n-> nolabel\nmira sleepy: 하암")
	_check(bad.errors.size() == 4, "잘못된 화자 · 자리 · 라벨 · 표정을 오류로 잡음 (%d)" % bad.errors.size())

	# ── 2. 꾸밈 ──
	var m := DialogueScript.markup("안녕, 나는 {red}미라{/red}.{p=1.0} {shake}간다{/shake}! {fast}빠르게{/fast} [괄호]")
	_check(m.bb.contains("[color=#ff4a5a]미라[/color]") and m.bb.contains("[shake") and m.bb.contains("[lb]괄호]"), "BBCode 변환 (%s)" % m.bb)
	_check(m.plain == "안녕, 나는 미라. 간다! 빠르게 [괄호]", "글자만 남긴 문장 (%s)" % m.plain)
	_check(is_equal_approx(m.pauses.get(3, 0.0), 0.1), "쉼표 뒤 0.1초 멈춤")
	_check(m.pauses.get(10, 0.0) >= 1.0, "{p=1.0} 멈춤이 마침표 자리에 (%s)" % str(m.pauses))
	_check(m.speeds.size() == 2 and m.speeds[0][1] > 1.0 and m.speeds[1][1] == 1.0, "{fast} 속도 구간 (%s)" % str(m.speeds))
	_check(not m.pauses.has(m.plain.length()), "문장 끝에서는 멈추지 않음")

	# ── 3. 진행기 ──
	var src := "== start\n@summary 시작\nmira: 하나\n* 가 -> a\n* [if flag] 숨김 -> b\n* 나 -> b\n== a\n@set flag = true\n@set n += 2\n@if n >= 2 -> b\nmira: 안 나와야 함\n== b\n* [if flag] 보임 -> c\n* 끝 -> c\n== c\nmira angry: 끝\n@end\nmira: 끝 뒤"
	var r := DialogueRunner.new(DialogueScript.from_text(src))
	var said: Array = []
	var asked: Array = []
	var ended := [false]
	r.said.connect(func(l): said.append(l.plain))
	r.asked.connect(func(o): asked.append(o.size()))
	r.ended.connect(func(): ended[0] = true)
	r.start()
	r.advance()
	_check(said == ["하나"] and asked == [2], "첫 대사 후 선택지 2개 (조건 안 맞는 줄 숨김) %s %s" % [str(said), str(asked)])
	r.choose(0)
	_check(r.flags.get("flag") == true and is_equal_approx(r.flags.get("n", 0.0), 2.0), "@set · += (%s)" % str(r.flags))
	_check(asked == [2, 2] and not said.has("안 나와야 함"), "@if 점프 후 조건부 선택지 보임")
	r.choose(0)
	_check(said.back() == "끝" and not ended[0], "마지막 대사")
	r.advance()
	_check(ended[0] and not said.has("끝 뒤") and r.summaries == PackedStringArray(["시작"]), "@end 에서 끝, 요약 수집")

	# ── 4. 화면 ──
	var sfx := Sfx.new()
	root.add_child(sfx)
	var view := DialogueView.new()
	root.add_child(view)
	var done := [false]
	view.finished.connect(func(): done[0] = true)
	DialogueView.speed_idx = 1
	var runner := DialogueRunner.new(DialogueScript.load_file("res://data/dialogue/hangar_briefing.dlg"))
	view.play(runner)
	await _frames(3)
	# 첫 줄은 @wait 0.4 뒤 해설이다
	_check(view.wait_left > 0.0 and view.title_label.text == "격납고 · 출격 준비", "제목 · 대기 명령")
	await _until(func(): return view.typing and view.text.visible_characters > 2, 5.0)
	_check(view.typing and view.text.visible_characters > 0 and view.text.visible_characters < view.total, "타자기: 글자가 조금씩 나옴 (%d/%d)" % [view.text.visible_characters, view.total])
	_check(not view.plate_name.visible, "해설 줄은 이름표 없음")
	view.next()
	_check(not view.typing and view.text.visible_characters == -1, "출력 중 진행 입력 → 문장 완성")
	view.next()
	await _frames(2)
	_check(view.line.who == "mira" and view.plate_name.text == "미라" and view.portraits.mira.active and not view.portraits.eirin.active, "다음 줄: 미라 강조, 에이린 어둡게")
	# 미라 → 에이린 → 미라 angry! 까지
	for i in 2:
		view.next()
		view.next()
		await _frames(2)
	_check(view.line.who == "mira" and view.portraits.mira.expr == "angry" and view.line.punch, "표정 바꾸기 + 흔들기 (%s)" % view.portraits.mira.expr)
	var logs := view.log_count()
	_check(logs == 4, "기록 4줄 (%d)" % logs)
	# 자동 진행: 손대지 않아도 다음 줄로 간다
	view.auto = true
	var before: int = view.line.line
	await _until(func(): return view.line.line != before, 15.0)
	_check(view.line.line != before, "자동 진행으로 다음 줄")
	view.auto = false
	# Tab: 선택지까지 건너뛰고 요약
	view.jump_to_choice()
	await _frames(2)
	_check(runner.waiting_choice and view.choice_box.get_child_count() == 3, "선택지까지 건너뜀, 버튼 3개")
	_check(view.summary_layer.visible and view.summary_text.text.contains("섹터 7"), "건너뛴 줄거리 요약 표시")
	_check(view.portraits.size() == 4, "4명이 무대에 (%d)" % view.portraits.size())
	view.next()
	_check(not view.summary_layer.visible, "요약은 입력 한 번에 닫힘")
	# 숫자 키 3 → 노아에게 더 묻기
	var key := InputEventKey.new()
	key.physical_keycode = KEY_3
	key.keycode = KEY_3
	key.pressed = true
	root.push_input(key)
	await _frames(2)
	_check(runner.flags.get("asked_noa") == true and view.line.who == "noa", "숫자 키로 선택 → 분기 (%s)" % str(runner.flags))
	# 나머지는 빨리 넘기기 + 첫 번째 선택지로 끝까지
	view.fast_forward = true
	await _until(func():
		if runner.waiting_choice:
			view._pick(0)
		return done[0], 30.0)
	_check(done[0] and runner.flags.get("trust_mira", 0.0) == 1.0, "끝까지 진행, 미라 신뢰 +1 (%s)" % str(runner.flags))
	_check(view.portraits.is_empty(), "@exit all 로 모두 퇴장")
	_check(DialogueRunner.picked.size() >= 2, "고른 선택지 기억 (%d)" % DialogueRunner.picked.size())
	view.queue_free()
	await _frames(2)
	# 실제 테스트씬 기본 대본, 새 표정 전환과 단독 대화의 빈 쪽 선택지 배치.
	var main: DialogueMain = load("res://scenes/dialogue.tscn").instantiate()
	root.add_child(main)
	_check(main.current == "cleaning_opening" and main.view.portraits.has("owner"), "실제 대화 테스트씬 기본값은 사장 오프닝")
	for step in 100:
		if main.runner.waiting_choice or main.runner.done:
			break
		main.view.wait_left = -1.0
		main.view._complete()
		main.runner.advance()
	await _frames(2)
	_check(main.runner.waiting_choice and main.view.choice_box.get_child_count() == 2
		and main.view.choice_box.anchor_left == 0.0 and main.view.choice_box.anchor_right == 1.0
		and main.view.portraits.owner.expr == "briefing", "사장 업무 설명 그림, 선택지 두 개는 하단 창 안에")
	await _until(func(): return absf(main.view.portraits.owner.get_global_rect().get_center().x - 640.0) < 2.0, 2.0)
	var owner_rect: Rect2 = main.view.portraits.owner.get_global_rect()
	var base_overlap := owner_rect.intersection(main.view.box.get_global_rect()).size.y
	_check(base_overlap > 0.0 and base_overlap <= 32.0
		and absf(owner_rect.get_center().x - 640.0) < 2.0
		and main.view.box.anchor_top == 1.0 and main.view.box.anchor_left == 0.0 and main.view.box.anchor_right == 1.0
		# 표정 교체의 12px 점프와 0.4% 호흡 확대 중에도 상단 메뉴 아래에 머문다.
		and owner_rect.position.x >= 0.0 and owner_rect.position.y >= 76.0
		and owner_rect.end.x <= root.get_visible_rect().size.x
		and owner_rect.end.y <= root.get_visible_rect().size.y - 38.0, "단독 대화: 중앙 정렬, 허리 끝만 하단 창에 연결 (%s / %s)" % [owner_rect, main.view.box.get_global_rect()])
	_check(not owner_rect.intersects(main.view.choice_box.get_global_rect()), "하단 선택지는 캐릭터와 겹치지 않음")
	var saved_size := DialogueView.size_idx
	DialogueView.size_idx = 3
	main.view._apply_size()
	var fits := true
	for item in opening.items:
		if item.op != "say":
			continue
		var preview: Dictionary = item.duplicate()
		preview.was_seen = false
		main.view._on_said(preview)
		main.view._complete()
		await _frames(2)
		fits = fits and main.view.text.get_content_height() <= main.view.text.size.y
	_check(fits, "오프닝 모든 대사가 최대 글자 크기 36에서도 대화창 안에 표시")
	DialogueView.size_idx = saved_size
	main.view._apply_size()
	main.view._pick(0)
	for step in 100:
		if main.runner.waiting_choice or main.runner.done:
			break
		main.view.wait_left = -1.0
		main.view._complete()
		main.runner.advance()
	await _frames(2)
	main.view._pick(1)
	_check(main.view.portraits.owner.expr == "encouragement" and main.view.plate_name.text == "사장", "응답 뒤 실제 화면에서 격려 표정과 이름표")
	key.physical_keycode = KEY_F2
	key.keycode = KEY_F2
	root.push_input(key)
	await _frames(2)
	_check(main.current == "hangar_briefing" and main.view.portraits.has("mira"), "F2로 기존 격납고 브리핑 전환")
	_check(main.view.box.anchor_left == 0.0 and main.view.box.anchor_right == 1.0
		and not main.view.portraits.mira.solo, "다인 대화는 기존 하단 전체 너비 배치 유지")
	key.physical_keycode = KEY_F3
	key.keycode = KEY_F3
	root.push_input(key)
	await _frames(2)
	_check(main.current == "feature_demo" and not main.runner.dlg.items.is_empty(), "F3로 기존 기능 시연 전환")
	key.physical_keycode = KEY_F1
	key.keycode = KEY_F1
	root.push_input(key)
	await _frames(2)
	_check(main.current == "cleaning_opening" and main.view.portraits.has("owner"), "F1로 새 오프닝 복귀")
	main.runner.flags["first_contract_ready"] = true
	key.physical_keycode = KEY_R
	key.keycode = KEY_R
	root.push_input(key)
	await _frames(2)
	_check(main.runner.flags.is_empty() and main.current == "cleaning_opening", "R 재시작 시 이번 대화의 선택 상태 초기화")
	main.queue_free()
	await _frames(2)

	print("RESULT dialogue_check: %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
