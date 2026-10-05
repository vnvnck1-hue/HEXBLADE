extends SceneTree
## Run with: Godot --headless --path . -s tests/speech_bubble_check.gd
## 필드 만화 말풍선 (SpeechBubble):
##  - 대사 · 감정 · 의성어 세 종류가 HUD 층 아래 화면 층에 뜬다
##  - 띠용 등장: 꼬리 끝을 축으로 0 에서 튀어 1 을 크게 넘었다(오버슈트) 1 로 자리 잡는다
##  - 같은 대상의 새 대사가 오면 이전 것은 비키고, 수명이 끝나면 뿅 줄어 사라진다
##  - 연결: 드론 대사 · 연기 속 적의 ? / !! · 돌리는 메카 기합 (끼릭 · 싹싹 같은 의성어는 예전처럼 떠오르는 글자)

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


func _texts(k: int) -> Array:
	var out := []
	for b in SpeechBubble.live():
		if (b as SpeechBubble).kind == k:
			out.append((b as SpeechBubble).text)
	return out


func _run() -> void:
	SpeechBubble.fixed_dt = 1.0 / 60.0
	var m: TrainingMain = load("res://scenes/training.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	for i in 40:
		await physics_frame
	var p := m.player

	# ── 1. 띠용 등장 ──
	var b := SpeechBubble.say(p, "영차!", SpeechBubble.SAY)
	_check(b != null and b.get_parent() != null and b.get_parent().get_parent() == m.hud.root, "말풍선은 HUD 화면 층 아래에 뜬다")
	var peak := 0.0
	var peak_f := 0
	var min_after := 9.0
	for i in 15:
		await process_frame
		var mx := maxf(b.sx, b.sy)
		if mx > peak:
			peak = mx
			peak_f = i + 1
		if i >= 4:
			min_after = minf(min_after, minf(b.sx, b.sy))
	_check(peak > 1.15, "띠용: 1 을 넘었다 돌아온다 (최대 %.2f)" % peak)
	_check(peak_f <= 5, "짧고 세게: 최대 크기가 80ms 안에 온다 (%d프레임)" % peak_f)
	_check(min_after < 0.99, "넘친 뒤 한 번 눌린다 (최소 %.2f)" % min_after)
	_check(absf(b.sx - 1.0) < 0.04 and absf(b.sy - 1.0) < 0.04, "0.25초 안에 크기 1 로 자리 잡는다 (%.2f, %.2f)" % [b.sx, b.sy])
	_check(b.pivot_offset.is_equal_approx(b.tail_tip), "꼬리 끝을 축으로 커진다")
	var sp: Vector2 = m.camera.screen_pos(p.global_position + b.offset)
	var tip := b.position + b.tail_tip
	_check(tip.distance_to(sp) < 2.0 or b.position.y > sp.y - b.tail_tip.y - 1.0, "꼬리 끝이 말하는 쪽 머리 위를 가리킨다")
	_check(b.col == SpeechBubble.INK, "대사 글자는 남색")

	# ── 2. 같은 대상의 새 대사 → 이전 것은 비킨다 · 수명 끝 → 사라짐 ──
	var b2 := SpeechBubble.say(p, "조금만 더!", SpeechBubble.SAY)
	_check(b.leaving >= 0.0 and b2.leaving < 0.0, "같은 대상에 새 대사가 오면 이전 말풍선은 퇴장")
	await _frames(15)
	_check(not is_instance_valid(b), "퇴장한 말풍선은 금방 지워진다")
	var e := SpeechBubble.say(p, "!!", SpeechBubble.EMOTE)
	_check(is_instance_valid(b2) and b2.leaving < 0.0, "대사와 감정 기호는 따로 뜬다")
	_check(e.col == SpeechBubble.RED, "감정 기호는 빨간 글자")
	await _frames(int(SpeechBubble.LIFE[SpeechBubble.EMOTE] * 60.0) + 15)
	_check(not is_instance_valid(e), "감정 말풍선은 수명이 끝나면 사라진다")

	# ── 3. 드론 대사 ──
	var d := PartnerDrone.inst
	if d:
		d.bark("다녀올게요!")
		await process_frame
		_check(is_instance_valid(d.bubble) and d.bubble.text == "다녀올게요!" and d.bubble.kind == SpeechBubble.SAY, "드론 대사는 말풍선으로")
		_check(d.find_children("*", "Label3D", true, false).is_empty(), "드론 머리 위 예전 글자(Label3D)는 없다")
	m.queue_free()
	await _frames(3)

	# ── 4. 연기 속 적 ? / !! · 수리 레버 끼릭 ──
	var lab: GimmickLab = load("res://scenes/gimmicks.tscn").instantiate()
	root.add_child(lab)
	current_scene = lab
	for i in 90:
		await physics_frame
	var g := Gimmicks.inst
	var lp := lab.player
	lp.invuln = 999.0
	lp.bot = true
	lab.phase = 0
	lab.ph_t = 0.0
	lab._drone_t = 9999.0
	var foe := Enemy.new()
	lab.world.add_child(foe)
	foe.global_position = lab.smoke.global_position + Vector3(0, 0, -6.5)
	for i in 60:
		lp.global_position = lab.smoke.global_position
		await process_frame
	var q := _texts(SpeechBubble.EMOTE)
	_check(lp.hidden and q.has("?") and not q.has("!!"), "연기에 숨으면 적 머리 위 ? 말풍선 (%s)" % str(q))
	lp.global_position = lab.smoke.global_position + Vector3(9, 0, 0)
	for i in 12:
		await process_frame
	var ex := _texts(SpeechBubble.EMOTE)
	_check(not lp.hidden and ex.has("!!") and not ex.has("?"), "들키면 ? 가 !! 로 바뀐다 (%s)" % str(ex))
	var h: RepairHatch = null
	for hh in g.hatches:
		if is_instance_valid(hh):
			h = hh
	if h:
		await _frames(50)
		lp.global_position = h.stand_spot()
		for i in 6:
			h.crank(lp)
			await _frames(3)
		var sfx := _texts(SpeechBubble.SFX)
		var pops := 0
		for c in lab.hud.root.get_children():
			if c is Label and RepairHatch.CREAKS.has((c as Label).text):
				pops += 1
		_check(sfx.is_empty() and pops >= 2, "끼릭 의성어는 말풍선이 아니라 떠오르는 글자 (글자 %d · 말풍선 %d)" % [pops, sfx.size()])
		var says := _texts(SpeechBubble.SAY)
		_check(says.any(func(t): return RepairHatch.SHOUTS.has(t)), "돌리는 메카의 기합 대사 말풍선 (%s)" % str(says))
	else:
		_check(false, "시험장에 수리 해치가 있다")
	SpeechBubble.fixed_dt = 0.0
	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
