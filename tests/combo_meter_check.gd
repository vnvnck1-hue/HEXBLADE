extends SceneTree
## Run with: Godot --headless --path . -s tests/combo_meter_check.gd
## 타격 콤보 점수 (ComboMeter, 화면 왼쪽):
##  피해마다 타수 +1 · 콤보 점수 = 피해 × 10 × 배율(10타마다 +0.5, 최대 4) · 랭크 문턱
##  창(1.2초 게임 시간) 안에 다음 피해가 없으면 끝 → 콤보 점수가 Main.score 로
##  플레이어 피격 → BREAK, 절반만 들어감 · 처치 보너스 · 화면 왼쪽 절반에 그려짐

var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _wait(sec: float) -> void:
	var until := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


func _run() -> void:
	_check(is_equal_approx(ComboMeter.mult_for(0), 1.0) and is_equal_approx(ComboMeter.mult_for(10), 1.5) and is_equal_approx(ComboMeter.mult_for(999), ComboMeter.MULT_MAX), "배율: 0타 ×1 · 10타 ×1.5 · 상한 ×4")
	_check(ComboMeter.rank_for(4) == -1 and ComboMeter.rank_for(5) == 0 and ComboMeter.rank_for(30) == 2, "랭크 문턱: 5타 NICE · 30타 GREAT")
	_check(ComboMeter._commas(1234567) == "1,234,567" and ComboMeter._commas(12) == "12", "점수 자리 쉼표")

	var m: TrainingMain = load("res://scenes/training.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	for i in 30:
		await physics_frame
	var cm := ComboMeter.inst
	_check(cm != null and cm.get_parent() == m.hud.root, "HUD 에 콤보 미터가 붙음")
	var dm: TrainingDummy = m.dummies[0]
	var hit_at := dm.global_position + Vector3(0, 1, 0)

	# ── 연속 타격
	var score0 := m.score
	for i in 12:
		dm.take_hit(1, Vector3.ZERO, hit_at, "slash")
		await physics_frame
	_check(cm.hits == 12, "실제 적 피해 12번 → 12타 (%d)" % cm.hits)
	_check(cm.phase == ComboMeter.Phase.LIVE and cm.rank == 0, "진행 중 · 랭크 NICE")
	# 1~9타 ×1 = 10점씩, 10~12타 ×1.5 = 15점씩
	_check(cm.combo_score == 9 * 10 + 3 * 15, "콤보 점수에 배율 반영 (%d)" % cm.combo_score)
	_check(m.score == score0, "진행 중에는 전체 점수에 아직 안 들어감")
	_check(m.best_combo >= 12, "최대 콤보 기록 = 타수")
	_check(cm.anchor().x < cm.size.x * 0.25, "화면 왼쪽에 그려짐 (x %.0f / %.0f)" % [cm.anchor().x, cm.size.x])
	var pending := cm.combo_score

	# 강타는 더 크게 튄다
	cm._pop[0] = 0.0
	ComboMeter.hit(5, true)
	_check(cm._pop[0] >= 0.8 and cm._shake >= 15.0, "강타: 큰 팝 · 센 흔들림")
	pending = cm.combo_score

	# ── 창이 지나면 끝 → 정산
	await _wait(ComboMeter.WINDOW + 0.4)
	_check(cm.phase == ComboMeter.Phase.FINISH or cm.phase == ComboMeter.Phase.IDLE, "창이 지나면 콤보 끝")
	_check(m.score == score0 + pending, "끝나면 콤보 점수 전체가 점수로 (%d → %d)" % [score0, m.score])
	await _wait(ComboMeter.FINISH_T + 0.1)
	_check(cm.phase == ComboMeter.Phase.IDLE and cm.hits == 0, "정산 연출 뒤 초기화")

	# ── 처치 보너스
	for i in 3:
		ComboMeter.hit(1, false)
	var before_kill := cm.combo_score
	ComboMeter.kill()
	_check(cm.combo_score == before_kill + ComboMeter.KILL_PTS, "콤보 중 처치 보너스")

	# ── 피격 → BREAK, 절반
	var s1 := m.score
	var half := int(cm.combo_score * ComboMeter.BREAK_KEEP)
	m.on_player_hurt()
	_check(cm.phase == ComboMeter.Phase.BREAK, "맞으면 BREAK")
	_check(m.score == s1 + half, "BREAK: 절반만 들어감 (+%d)" % (m.score - s1))
	_check(cm._shards.size() > 0, "BREAK: 숫자 조각이 흩어짐")

	# ── 1타만 치고 끝나면 표시 없이 조용히 정산
	await _wait(ComboMeter.BREAK_T + 0.1)
	var s2 := m.score
	ComboMeter.hit(2, false)
	await _wait(ComboMeter.WINDOW + 0.3)
	_check(cm.phase == ComboMeter.Phase.IDLE and m.score == s2 + 20, "1타는 연출 없이 점수만")

	# ── 히트스탑(시간 배율 ~0) 동안은 창이 거의 줄지 않음
	ComboMeter.hit(1, false)
	ComboMeter.hit(1, false)
	m.hitstop(0.5)
	await _wait(0.45)
	_check(cm.window > ComboMeter.WINDOW - 0.1, "히트스탑 동안 창이 거의 그대로 (%.2f)" % cm.window)

	print("combo_meter_check: %d fails" % fails)
	quit(1 if fails > 0 else 0)
