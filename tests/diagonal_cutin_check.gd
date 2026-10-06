extends SceneTree
## Run with: Godot --headless --path . -s tests/diagonal_cutin_check.gd
## 사선 DOCKING 합체 컷인 (scripts/drone/diagonal_docking_cutin.gd · docs/diagonal-docking-cutin.md):
##  1. 기본 종류가 사선 · 허수아비 시험장 Q 합체에 컷인 1개 · layer 11(HUD 위) · 실제 합체 순간 잠금 · GattaiFX 는 집중선만
##  2. 기준점이 진입·체류·퇴장 내내 하단선 위(법선 거리 0.5px 이내) · 왼쪽 밖에서 시작 · 오른쪽 밖으로 퇴장(왼쪽 복귀 없음)
##  3. 체류 중에도 DOCKING 글자가 흐른다 · 마스크 셰이더가 같은 하단선을 받는다
##  4. 가슴 스프링이 과하게 출렁인다 (20~72px) · 컷인 동안 슬로우모션(0.1), 끝나면 1 · 임팩트 때 글자 거의 정지 · 실제 시간으로 1.6초 안에 정리 · 반복 Q 로 쌓이지 않음
##  6. 보이스: 실제 합체 순간 1회 · prewarm 무음 · 직전 반복 없음 · 음소거 · 긴 음성 끝까지 · 조종석 모드는 없음
##  5. 합체 비행이 끊기면 성공 연출 없이 퇴장 · 미리보기(F3)는 드론 없이 스스로 잠금 · 0 키로 조종석/끔 전환

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
		await process_frame
	return cond.call()


func _of(type: Variant) -> Array:
	var r := []
	for c in current_scene.get_children():
		if is_instance_of(c, type) and not c.is_queued_for_deletion():
			r.append(c)
	return r


func _ready_drone(d: PartnerDrone) -> void:
	if d.docked():
		d._detach()
	await _until(func(): return d.state == PartnerDrone.St.FOLLOW and d.link_cd <= 0.0 and d.whirl_t < 0.0, 900)
	await _until(func(): return _of(DiagonalDockingCutin).is_empty() and _of(CockpitCutin).is_empty(), 300)


func _key(lab: Node, k: Key, shift := false) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.pressed = true
	ev.shift_pressed = shift
	lab._unhandled_input(ev)


func _run() -> void:
	_check(PartnerDrone.cutin_style == "diagonal", "기본 합체 컷인 = 사선 DOCKING")
	var lab: TrainingMain = load("res://scenes/training.tscn").instantiate()
	root.add_child(lab)
	current_scene = lab
	await _frames(4)
	var d := PartnerDrone.inst
	_check(d != null and await _until(func(): return d.state == PartnerDrone.St.FOLLOW, 600), "허수아비 시험장에 드론 동행")
	_check(DockingVoice.plays == 0, "씬 시작 prewarm 에서는 보이스 없음")
	_check(DockingVoice.VOICES.size() == 9 and DockingVoice.VOICES.all(func(v): return v is AudioStream), "선택 보이스 9개 로드")

	# 1. Q 합체
	d.gauge = PartnerDrone.GAUGE_MAX
	var plays0 := DockingVoice.plays
	d.whirl_link()
	_check(DockingVoice.plays == plays0, "Q 를 누른 순간엔 보이스 없음 (실제 합체 순간에)")
	var cs := _of(DiagonalDockingCutin)
	_check(cs.size() == 1 and d.state == PartnerDrone.St.RECALL, "Q 합체 → 사선 컷인 1개")
	var c: DiagonalDockingCutin = cs[0] if cs.size() > 0 else null
	if c == null:
		quit(1)
		return
	_check(c.layer == DiagonalDockingCutin.LAYER and c.layer > 10, "layer 11 (HUD 10 위, 원본 GIF 겹침 순서)")
	var vw: float = c.vs.x
	var right0 := c.anchor.position.x + c.side * (1.0 - c.anchor_uv.x)
	_check(right0 < 0.0, "왼쪽 화면 밖에서 시작 (오른쪽 끝 x=%.0f)" % right0)
	d.whirl_link()
	_check(_of(DiagonalDockingCutin).size() == 1, "합체 비행 중 Q 를 또 눌러도 쌓이지 않는다")
	_check(is_equal_approx(lab.slowmo, DiagonalDockingCutin.SLOW), "합체 연출 시작과 함께 슬로우모션 (x%.2f)" % lab.slowmo)
	var t0 := Time.get_ticks_msec()
	_check(await _until(func(): return d.state == PartnerDrone.St.DOCKED, 300), "합체 완료")
	_check(is_instance_valid(c) and c.dock_t >= 0.0, "실제 합체 순간에 잠금(notify_dock)")
	_check(DockingVoice.plays == plays0 + 1 and DockingVoice.is_playing(), "실제 합체 순간 보이스 1회 (%s)" % DockingVoice.last_name)
	var vp: AudioStreamPlayer = DockingVoice.inst.player if is_instance_valid(DockingVoice.inst) else null
	_check(vp != null and is_equal_approx(vp.pitch_scale, 1.0) and vp.get_parent().get_parent() == lab and vp.process_mode == Node.PROCESS_MODE_PAUSABLE,
		"보이스: 피치 1.0 · 씬 노드 아래(컷인 자식 아님) · 일시정지에 같이 멈춤")
	var pop_y := 0.0
	while is_instance_valid(c) and c.t < c.dock_t + DiagonalDockingCutin.POP_T + 0.03:
		pop_y = maxf(pop_y, c.anchor.scale.y)
		await process_frame
	_check(pop_y > 1.02 and pop_y < 1.15 and absf(c.pop_at()) < 0.0001, "합체 순간 세로로 쭉 늘었다 짧게(0.16초) 돌아온다 (최대 x%.3f)" % pop_y)
	_check(absf(c.dock_t - PartnerDrone.GATTAI_TIME) < 0.05, "슬로우모션 중에도 합체 비행은 컷인 시계로 0.22초에 붙는다 (dock=%.3f)" % c.dock_t)
	await _until(func(): return c.t > c.dock_t + 0.1, 120)
	print("  text_k at dock+%.2f = %.3f" % [c.t - c.dock_t, c.text_k()])
	_check(c.text_k() <= DiagonalDockingCutin.TEXT_MIN + 0.001, "임팩트 순간 DOCKING 글자가 거의 멈춘다")
	_check(is_equal_approx(lab.slowmo, DiagonalDockingCutin.SLOW), "합체 뒤 체류 중에도 슬로우모션 유지")
	var gf := _of(GattaiFX)
	_check(gf.size() == 1 and (gf[0] as GattaiFX).compact, "GattaiFX 는 집중선만 (말풍선·글자 중복 없음)")
	await _until(func(): return c.ph == DiagonalDockingCutin.Ph.HOLD and c.t > 0.4, 300)
	var hold_x := c.anchor.position.x
	_check(absf(hold_x - vw * DiagonalDockingCutin.X_HOLD) < vw * 0.06, "중앙 체류 (x=%.0f / W=%.0f)" % [hold_x, vw])
	await _until(func(): return c.t > c.dock_t + DiagonalDockingCutin.TEXT_RESUME + 0.02, 300)
	var off0 := c._text_off
	await process_frame
	await process_frame
	_check(c.ph == DiagonalDockingCutin.Ph.HOLD and not is_equal_approx(c._text_off, off0) and c.text_k() > 0.9, "체류 중에도 DOCKING 글자가 흐른다 (임팩트 뒤 다시 흐름)")
	_check(c.mat.get_shader_parameter("clip_origin") == c.origin and c.mat.get_shader_parameter("clip_normal") == c.normal \
		and c.text_mat.get_shader_parameter("bottom_normal") == c.normal, "포트레이트 마스크 · 글자 띠가 같은 하단선을 쓴다")
	var max_x := 0.0
	var max_tilt := 0.0
	while is_instance_valid(c) and c.ph != DiagonalDockingCutin.Ph.DONE and c.done_t < 0.0:
		max_x = maxf(max_x, c.anchor.position.x)
		max_tilt = maxf(max_tilt, absf(c.anchor.rotation))
		await process_frame

	print("  max_tilt=%.3f rad" % max_tilt)
	_check(max_tilt <= maxf(float(DiagonalDockingCutin.tween().amp), float(DiagonalDockingCutin.tween().out)) + 0.001, "체류~퇴장 기울기는 한계 안 (최대 %.1f°)" % rad_to_deg(max_tilt))
	if is_instance_valid(c):
		var left_end := c.anchor.position.x - c.side * c.anchor_uv.x
		_check(left_end > vw, "오른쪽 화면 밖으로 퇴장 (왼쪽 끝 x=%.0f)" % left_end)
		_check(c.max_clip_err < 0.5, "기준점이 내내 하단선 위 (최대 %.3fpx)" % c.max_clip_err)
		print("  jig_peak=%.1f px" % c.jig_peak)
		_check(c.jig_peak > 20.0 and c.jig_peak <= DiagonalDockingCutin.JIG_MAX * 1.42, "가슴이 관성·합체 충격으로 크게 출렁인다 (축마다 72px 한계)")
		var off: Vector2 = c.mat.get_shader_parameter("off_l")
		_check(off.is_equal_approx((c.jig[0] as Vector2) * c.jig_scale / c.art), "흔들림이 셰이더 변위로 들어간다")
	var wc: WeakRef = weakref(c)
	_check(await _until(func(): return wc.get_ref() == null, 600), "끝나면 사라진다")
	var life := (Time.get_ticks_msec() - t0) / 1000.0
	print("  life=%.2fs (real)" % life)
	_check(life < 1.6, "실제 시간으로 흐른다 (슬로우모션 · 히트스탑 중에도 1.6초 안에 끝)")
	_check(DockingVoice.plays == plays0 + 1, "한 합체에 보이스는 한 번만 (휠윈드·분리에 추가 없음)")
	_check(is_equal_approx(lab.slowmo, 1.0), "컷인이 끝나면 정상 속도로 복귀")

	# 2. 합체 비행이 끊기면 성공 연출 없이 퇴장
	await _ready_drone(d)
	d.gauge = PartnerDrone.GAUGE_MAX
	d.whirl_link()
	var c2: DiagonalDockingCutin = _of(DiagonalDockingCutin)[0]
	var cancel_plays := DockingVoice.plays
	await _frames(2)
	d._go(PartnerDrone.St.FOLLOW)
	d._whirl_pending = false
	await process_frame
	await process_frame
	_check(is_instance_valid(c2) and c2.ph == DiagonalDockingCutin.Ph.EXIT and c2.dock_t < 0.0, "합체 비행이 끊기면 잠금 없이 퇴장")
	_check(DockingVoice.plays == cancel_plays, "합체 전에 끊기면 보이스 없음")
	var wc2: WeakRef = weakref(c2)
	_check(await _until(func(): return wc2.get_ref() == null, 200), "끊긴 컷인도 정리된다")
	_check(is_equal_approx(lab.slowmo, 1.0), "끊긴 컷인도 슬로우모션을 풀고 간다")

	# 3. 미리보기 (F3): 드론 없이 스스로 잠금
	await _ready_drone(d)
	_key(lab, KEY_F3)
	var pv := _of(DiagonalDockingCutin)
	_check(pv.size() == 1 and (pv[0] as DiagonalDockingCutin).preview, "F3 미리보기 컷인")
	if pv.size() == 1:
		var c3: DiagonalDockingCutin = pv[0]
		# 진입 관성: 기울기는 멈추는 순간(ENTER) 최대 · 가슴은 오른쪽으로 쏠림 · 첫 프레임 왼쪽 튐 없음 · 기울기는 짧게 끝
		var tilt_peak := 0.0
		var tilt_peak_t := 0.0
		var jig_right := 0.0
		var jig_first := 0.0
		var tilt_late := 0.0
		var hold_jx := 0.0
		var hold_jy := 0.0
		while is_instance_valid(c3) and c3.t < 0.5:
			if c3.anchor.rotation > tilt_peak:
				tilt_peak = c3.anchor.rotation
				tilt_peak_t = c3.t
			var jx: float = (c3.jig[0] as Vector2).x
			if c3.t < 0.06 and absf(jx) > absf(jig_first):
				jig_first = jx
			if c3.t < 0.25:
				jig_right = maxf(jig_right, jx)
			if c3.t > DiagonalDockingCutin.SETTLE:
				hold_jx = maxf(hold_jx, absf(jx))
				hold_jy = maxf(hold_jy, absf((c3.jig[0] as Vector2).y))
			if c3.t > float(DiagonalDockingCutin.tween().peak_t) + float(DiagonalDockingCutin.tween().settle) + 0.02:
				tilt_late = maxf(tilt_late, absf(c3.anchor.rotation))
			await process_frame
		print("  tilt_peak=%.3f at t=%.3f  jig first=%.1f right=%.1f  tilt_late=%.4f" % [tilt_peak, tilt_peak_t, jig_first, jig_right, tilt_late])
		var peak_want: float = DiagonalDockingCutin.tween().peak_t
		_check(DiagonalDockingCutin.tween().id == "late", "기본 트위닝 = LATE (멈출 때 쏠림)")
		_check(tilt_peak > 0.04 and absf(tilt_peak_t - peak_want) < 0.03, "프리셋 시각(t=%.2f)에 위쪽이 진행 방향으로 가장 크게 쏠린다" % tilt_peak_t)
		_check(jig_first >= -1.0, "등장 첫 프레임에 가슴이 왼쪽으로 튀지 않는다 (%.1f)" % jig_first)
		_check(jig_right > 30.0, "가슴이 등장 방향(오른쪽)으로 관성 쏠림 (%.1fpx)" % jig_right)
		print("  hold jig |x|=%.1f |y|=%.1f" % [hold_jx, hold_jy])
		_check(hold_jx > 25.0 and hold_jx > hold_jy * 1.4, "멈춘 뒤에도 가슴은 위아래보다 좌우로 크게 출렁인다 (|x| %.0f · |y| %.0f)" % [hold_jx, hold_jy])
		_check(tilt_late < 0.003, "기울기는 짧게 끝나고 흔들리지 않는다 (%.4f rad)" % tilt_late)
		_check(await _until(func(): return not is_instance_valid(c3) or c3.dock_t >= 0.0, 200) and is_instance_valid(c3), "미리보기는 스스로 잠금")
		var wc3: WeakRef = weakref(c3)
		_check(await _until(func(): return wc3.get_ref() == null, 300), "미리보기도 정리된다")

	# 3b. - 키: 트위닝 프리셋 바꾸기 → 바로 미리보기, 프리셋마다 기울기 곡선이 다르다
	var t0p := DiagonalDockingCutin.tween_preset
	_key(lab, KEY_MINUS)
	_check(DiagonalDockingCutin.tween_preset == (t0p + 1) % DiagonalDockingCutin.TWEEN_PRESETS.size(), "- 키로 트위닝 프리셋이 바뀐다 (%s)" % DiagonalDockingCutin.tween().name)
	var pv2 := _of(DiagonalDockingCutin)
	_check(pv2.size() >= 1, "프리셋을 바꾸면 바로 미리보기")
	var peaks := {}
	for i in DiagonalDockingCutin.TWEEN_PRESETS.size():
		DiagonalDockingCutin.tween_preset = i
		var probe := DiagonalDockingCutin.new()
		probe.t = float(DiagonalDockingCutin.tween().peak_t)
		peaks[DiagonalDockingCutin.tween().id] = probe.tilt_at()
		probe.free()
	print("  preset tilt at peak: %s" % str(peaks))
	_check(peaks.size() == DiagonalDockingCutin.TWEEN_PRESETS.size() and absf(float(peaks["none"])) < 0.0001 and float(peaks["lunge"]) > float(peaks["snap"]), "프리셋마다 다른 기울기 (NONE 은 0)")
	DiagonalDockingCutin.tween_preset = t0p
	for x in _of(DiagonalDockingCutin):
		x.queue_free()
	await process_frame

	# 3e. 민트 메이드 (기본): 보라 · 초록은 숨김이라 번갈아도 민트만 · 전용 테마 · 가슴 모핑 없음 · 치마/리본 흔들림 · 오른쪽 그림자 ·
	#     소품이 띠 안을 왼쪽 → 오른쪽으로 튀며 날아감 · 금빛 반짝이는 띠 안에서만 오른쪽으로 · 소품은 캐릭터 뒤 층
	_check(DiagonalDockingCutin.char_mode == "alt" and DiagonalDockingCutin.hidden_chars == ["purple", "green"], "기본: 번갈아 · 보라/초록 숨김")
	var m1 := DiagonalDockingCutin.begin(lab, null, true)
	var m2 := DiagonalDockingCutin.begin(lab, null, true)
	await process_frame
	_check(m1.cfg.id == "mint" and m2.cfg.id == "mint" and m1.anchor.visible, "숨긴 캐릭터는 건너뛰어 민트 메이드만 (%s, %s)" % [m1.cfg.id, m2.cfg.id])
	m2.queue_free()
	var hair := Color8(182, 213, 191)
	_check(m1.text_col.g > m1.text_col.r and m1.text_col.g > m1.text_col.b and absf(m1.band_top_edge.h - hair.h) < 0.03
		and m1.band_fill.g > m1.band_fill.r and absf(m1.band_fill.h - hair.h) < 0.06 and m1.band_fill.v < 0.35,
		"민트 전용 테마 = 머리색 기준 (민트 글자 · 머리색 위 테두리 · 짙은 청록 띠)")
	_check(float(m1.mat.get_shader_parameter("bust")) == 0.0 and float(m1.mat.get_shader_parameter("motion")) == 1.0, "가슴 모핑 끔 · 치마/옷 움직임 켬")
	var ri_back := m1.root.get_children().find(m1.scatter.back)
	var ri_anchor := m1.root.get_children().find(m1.anchor)
	_check(m1.scatter != null and ri_back >= 0 and ri_back < ri_anchor and m1.shadow.get_index() < m1.portrait.get_index(), "소품 · 그림자는 캐릭터 뒤 층")
	var sh_right := 0.0
	var sh_a := 0.0
	var flutter_max := 0.0
	var sp_vx := 0.0
	var sp_n := 0
	var live_props := 0
	var sp_outside := 0
	var near_min := 1.0
	var near_far := 0.0
	while is_instance_valid(m1) and m1.t < 0.85:
		for q: Dictionary in m1.scatter.props:
			if q.alive and q.near:
				var qp: Vector2 = q.pos
				if qp.x > 0.0 and qp.x < m1.vs.x:
					var top := m1.scatter.band_top(qp.x)
					near_min = minf(near_min, (qp.y - top) / (m1.scatter.band_bottom(qp.x) - top))
				near_far = maxf(near_far, qp.x / m1.vs.x)
		for sp: Dictionary in m1.scatter.sparks:
			if not m1.scatter.in_band(sp.pos, 1.0):
				sp_outside += 1
		if m1.shadow_k >= 1.0:
			sh_right = maxf(sh_right, (m1.shadow.position.x - m1.portrait.position.x) / m1.side)
			sh_a = maxf(sh_a, m1.shadow.modulate.a)
		flutter_max = maxf(flutter_max, float(m1.mat.get_shader_parameter("flutter")))
		for sp: Dictionary in m1.scatter.sparks:
			sp_vx += (sp.vel as Vector2).x
			sp_n += 1
		live_props = m1.scatter.props.filter(func(q): return q.alive).size()
		await process_frame
	var left_start := m1.scatter.min_x.all(func(x): return float(x) < 0.0)
	var far := 0.0
	for x in m1.scatter.max_x:
		far += float(x) / m1.vs.x / m1.scatter.max_x.size()
	print("  mint skirt %.1f · cloth %.1f px · shadow +%.3f side a %.2f · props %d far %.2fW bounces %d · sparks %d (vx %.0f, out %d/%d)" % [m1.skirt_peak, m1.cloth_peak, sh_right, sh_a, live_props, far, m1.scatter.bounces, m1.scatter.spark_total, sp_vx / maxf(sp_n, 1), sp_outside, m1.scatter.spark_out])
	_check(m1.skirt_peak > 6.0 and m1.cloth_peak > 8.0 and flutter_max > DiagonalDockingCutin.FLUTTER.x, "치마 · 리본 꼬리가 관성으로 흔들림 (%.0f / %.0f px)" % [m1.skirt_peak, m1.cloth_peak])
	_check(sh_right > 0.01 and sh_right < 0.045 and sh_a > 0.4, "그림자가 캐릭터 바로 오른쪽에 자라남 (+%.3f side)" % sh_right)
	_check(live_props == 10 and left_start and far > 0.5 and m1.scatter.bounces >= 10,
		"소품 10개가 왼쪽 밖에서 오른쪽으로 튀며 날아감 (평균 %.2f W까지 · 튐 %d)" % [far, m1.scatter.bounces])
	var near_n := m1.scatter.props.filter(func(q): return q.near).size()
	var ri_front := m1.root.get_children().find(m1.scatter.front)
	print("  near props %d · lowest band pos %.2f · far %.2fW" % [near_n, near_min, near_far])
	_check(near_n == 3 and ri_front > ri_anchor and near_min >= CutinScatter.NEAR_TOP - 0.01 and near_far > 0.5,
		"소품 셋은 캐릭터 앞을 지나감 (앞 층 · 띠 아래쪽 절반에서만 · 오른쪽까지)")
	_check(m1.scatter.spark_total > 15 and sp_vx / maxf(sp_n, 1) > 0.0 and sp_outside == 0 and m1.scatter.spark_out == 0,
		"금빛 반짝이는 띠 안에서만 오른쪽으로 (%d개)" % m1.scatter.spark_total)
	for x in _of(DiagonalDockingCutin):
		x.queue_free()
	await process_frame
	var mh := DiagonalDockingCutin.hidden_chars
	DiagonalDockingCutin.hidden_chars = ["purple"]
	var hp := DiagonalDockingCutin.begin(lab, null, true)
	DiagonalDockingCutin.char_mode = "purple"
	var hq := DiagonalDockingCutin.begin(lab, null, true)
	DiagonalDockingCutin.char_mode = "alt"
	await process_frame
	_check(hq.cfg.id == "purple" and not hq.anchor.visible and not hq.paper_front.visible and hq.front.visible, "숨긴 캐릭터를 고정하면 원화 · 종이 안 그림 (집중선은 그림)")
	hp.queue_free()
	hq.queue_free()
	await process_frame

	# 3d. 캐릭터: 합체마다 번갈아 · 캐릭터마다 테마 색 · 머리카락이 흔들림 · [ 키로 고정 (예전 두 캐릭터 — 숨김을 풀고 검사)
	DiagonalDockingCutin.hidden_chars = ["mint"]
	DiagonalDockingCutin._next_char = 0
	var ca := DiagonalDockingCutin.begin(lab, null, true)
	var cb := DiagonalDockingCutin.begin(lab, null, true)
	await process_frame
	print("  chars: %s → %s" % [ca.cfg.id, cb.cfg.id])
	_check(ca.cfg.id != cb.cfg.id, "연속 두 합체는 서로 다른 캐릭터 (%s → %s)" % [ca.cfg.id, cb.cfg.id])
	var green_c: DiagonalDockingCutin = ca if ca.cfg.id == "green" else cb
	var purple_c: DiagonalDockingCutin = cb if green_c == ca else ca
	_check(green_c.text_col.g > green_c.text_col.r + 0.4 and purple_c.text_col.b > purple_c.text_col.g + 0.2 and purple_c.band_fill != green_c.band_fill,
		"테마: 초록 메이드 = 그린 · 보라 정비사 = 퍼플 (글자 · 띠 색)")
	_check(green_c.portrait.texture.get_width() == 1226 and green_c.mat.get_shader_parameter("hair_mask") != null and purple_c.mat.get_shader_parameter("hair_mask") != null,
		"초록 메이드 원화 1226² · 두 캐릭터 모두 머리카락 마스크")
	var hmax := 0.0
	var gjig := 0.0
	var first_seen := {}
	var paper_x0 := -1.0
	var paper_dx := 0.0
	while is_instance_valid(green_c) and green_c.t < 0.5:
		for pp: Dictionary in green_c.pops:
			if (pp.node as Sprite2D).scale.x > 0.01 and not first_seen.has(pp.cfg.kind + str(pp.cfg.at)):
				first_seen[pp.cfg.kind + str(pp.cfg.at)] = green_c.t
		var alive := green_c.papers.filter(func(q): return q.alive)
		if not alive.is_empty():
			var mx := 0.0
			for q in alive:
				mx += (q.pos as Vector2).x
			mx /= alive.size()
			if paper_x0 < 0.0:
				paper_x0 = mx
			paper_dx = mx - paper_x0
		hmax = maxf(hmax, absf((green_c.mat.get_shader_parameter("hair_off") as Vector2).x) * green_c.art)
		gjig = maxf(gjig, absf((green_c.jig[0] as Vector2).x))
		await process_frame
	print("  green hair max %.1f px · jig x %.1f" % [hmax, gjig])
	_check(hmax > 10.0 and hmax <= DiagonalDockingCutin.HAIR_MAX + 0.01, "머리카락이 관성으로 흔들린다 (최대 %.0f px)" % hmax)
	_check(gjig > 20.0, "초록 메이드도 가슴 모핑 (%.0f px)" % gjig)
	print("  pops first seen: %s · papers moved %+.0f px" % [str(first_seen), paper_dx])
	var order: Array = first_seen.values()
	_check(first_seen.size() == 4 and order == order.duplicate() and float(first_seen.values()[0]) < float(first_seen.values()[1]),
		"하트 말풍선 · 하트 · 반짝이가 순서대로 튀어나온다")
	_check(green_c.papers.size() > 8 and paper_dx > green_c.vs.x * 0.15, "서류 종이가 등장 방향(오른쪽)으로 휘날린다")
	_check(purple_c.pops.is_empty() and purple_c.papers.is_empty(), "보라 정비사에는 말풍선 팝업 · 종이 없음")
	for x in _of(DiagonalDockingCutin):
		x.queue_free()
	await process_frame
	var ek := InputEventKey.new()
	ek.physical_keycode = KEY_BRACKETLEFT
	ek.pressed = true
	lab._unhandled_input(ek)
	var fixed_id := DiagonalDockingCutin.char_mode
	var f1 := DiagonalDockingCutin.begin(lab, null, true)
	var f2 := DiagonalDockingCutin.begin(lab, null, true)
	await process_frame
	_check(fixed_id != "alt" and f1.cfg.id == fixed_id and f2.cfg.id == fixed_id, "[ 키로 캐릭터 고정 (%s)" % fixed_id)
	DiagonalDockingCutin.char_mode = "alt"
	DiagonalDockingCutin.hidden_chars = mh
	for x in _of(DiagonalDockingCutin):
		x.queue_free()
	await process_frame

	# 3c. 보이스: Shift+F3 순서대로 강제 · 무작위는 직전과 겹치지 않음 · 음소거면 재생 안 함 · 긴 음성은 컷인이 끝나도 계속
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F3
	ev.pressed = true
	ev.shift_pressed = true
	var before := DockingVoice.plays
	lab._unhandled_input(ev)
	await _until(func(): return DockingVoice.plays > before, 200)
	_check(DockingVoice.last_name == DockingVoice.NAMES[0], "Shift+F3: 첫 번째 보이스부터 순서대로 (%s)" % DockingVoice.last_name)
	for x in _of(DiagonalDockingCutin):
		x.queue_free()
	var repeats := 0
	var seen := {}
	var prev := ""
	for i in 40:
		DockingVoice.inst._play()
		if DockingVoice.last_name == prev:
			repeats += 1
		prev = DockingVoice.last_name
		seen[prev] = true
	_check(repeats == 0 and seen.size() >= 7, "무작위 보이스: 직전 파일 연속 없음 · 여러 파일이 고루 (40번에 %d종)" % seen.size())
	await _until(func(): return not DockingVoice.is_playing() and DockingVoice.inst.duck <= 0.0, 600)
	var mi := AudioServer.get_bus_index("Master")
	var vb := AudioServer.get_bus_index(DockingVoice.BUS)
	var master0 := AudioServer.get_bus_volume_db(mi)
	_check(vb >= 0 and AudioServer.get_bus_effect_count(vb) == 3 and DockingVoice.inst.player.bus == DockingVoice.BUS,
		"보이스 전용 버스 (EQ · 컴프레서 · 리미터)")
	DockingVoice.force = 6                                   ## shozyo1-atattekudasai (약 1.32초)
	DockingVoice.inst._play()
	var long_t0 := Time.get_ticks_msec()
	await _until(func(): return Time.get_ticks_msec() - long_t0 > 200, 120)
	var ducked := AudioServer.get_bus_volume_db(mi) - master0
	var comp := AudioServer.get_bus_volume_db(vb)
	print("  duck master %.1f dB · voice bus %+.1f dB" % [ducked, comp])
	_check(ducked < -9.0 and absf(comp + ducked) < 0.01, "보이스 동안 다른 소리는 -10dB (보이스 버스는 상쇄해 그대로)")
	_check(DockingVoice.inst.player.volume_db > 0.0, "보이스 음량을 올림 (%.1f dB)" % DockingVoice.inst.player.volume_db)
	await _until(func(): return not DockingVoice.is_playing(), 400)
	var long_len := (Time.get_ticks_msec() - long_t0) / 1000.0
	print("  long voice played %.2fs" % long_len)
	_check(long_len > 1.0, "긴 보이스는 끝까지 재생 (%.2f초)" % long_len)
	await _until(func(): return DockingVoice.inst.duck <= 0.0, 300)
	_check(is_equal_approx(AudioServer.get_bus_volume_db(mi), master0) and is_zero_approx(AudioServer.get_bus_volume_db(vb)), "보이스가 끝나면 덕킹이 풀려 원래 음량")
	Sfx.inst.muted = true
	var mp := DockingVoice.plays
	DockingVoice.inst._play()
	_check(DockingVoice.plays == mp and not DockingVoice.is_playing(), "M 음소거면 보이스 재생 안 함")
	Sfx.inst.muted = false
	await process_frame

	# 4. 0 키: 조종석(예전) → 끔 → 사선
	_key(lab, KEY_0)
	_check(PartnerDrone.cutin_style == "cockpit", "0 키 → 조종석 컷인 (예전 보관본)")
	await _ready_drone(d)
	d.gauge = PartnerDrone.GAUGE_MAX
	d.whirl_link()
	_check(_of(CockpitCutin).size() == 1 and _of(DiagonalDockingCutin).is_empty(), "조종석을 고르면 예전 컷인이 나온다")
	var cp0 := DockingVoice.plays
	await _until(func(): return d.state == PartnerDrone.St.DOCKED, 300)
	_check(DockingVoice.plays == cp0, "예전 조종석 컷인에는 보이스 없음 (범위 밖)")
	_key(lab, KEY_0)
	_check(PartnerDrone.cutin_style == "off", "0 키 → 끔")
	await _ready_drone(d)
	d.gauge = PartnerDrone.GAUGE_MAX
	d.whirl_link()
	_check(_of(CockpitCutin).is_empty() and _of(DiagonalDockingCutin).is_empty(), "끔이면 컷인 없음")
	_key(lab, KEY_0)
	_check(PartnerDrone.cutin_style == "diagonal", "0 키 → 다시 사선")

	# 5. 드론이 사라지면 같이 정리
	await _ready_drone(d)
	d.gauge = PartnerDrone.GAUGE_MAX
	d.whirl_link()
	var c4: DiagonalDockingCutin = _of(DiagonalDockingCutin)[0]
	d.queue_free()
	await process_frame
	await process_frame
	_check(not is_instance_valid(c4), "드론이 제거되면 컷인도 제거")
	_check(is_equal_approx(lab.slowmo, 1.0), "제거될 때도 슬로우모션 해제")

	Engine.time_scale = 1.0
	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
