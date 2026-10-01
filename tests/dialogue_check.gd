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
	_check(missing.is_empty(), "포트레이트 그림 12장 모두 있음 %s" % str(missing))
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

	print("RESULT dialogue_check: %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
