extends SceneTree
## Run with: Godot --headless --path . -s tests/whirl_props_check.gd
## Q 합체 휠윈드 + 민트 메이드: 컷인의 메이드 소품이 회오리 둘레로 흩뿌려진다 (WhirlProps)
##  1. 사선 컷인(민트 메이드)으로 합체해 휠윈드가 시작되면 소품 연출이 붙는다
##  2. 소품이 계속 튀어나와 회오리를 돌다 내팽개쳐지고(멀리 2m 넘게), 바닥에 튄다
##  3. 금빛 가산 별이 함께 생긴다
##  4. 휠윈드가 끝나면 남은 소품도 사라지고 노드가 정리된다
##  5. 컷인이 꺼져 있으면(--cutin=off) 소품 연출 없음

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
	PartnerDrone.cutin_style = "diagonal"
	var m: TrainingMain = load("res://scenes/training.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	for i in 4:
		await physics_frame
	var d := PartnerDrone.inst
	_check(d != null and await _until(func(): return d.state == PartnerDrone.St.FOLLOW, 600), "드론 동행 시작")
	d.whirl_link()
	_check(await _until(func(): return d.whirl_t >= 0.0, 600), "Q 합체 → 휠윈드 시작")
	var w := d.maid_props
	_check(is_instance_valid(w), "민트 메이드 컷인으로 합체하면 휠윈드에 메이드 소품 연출이 붙는다")
	if not is_instance_valid(w):
		_finish()
		return
	var star_peak := 0
	var item_peak := 0
	var emitted := 0
	var flung := 0
	var bounced := 0
	var far := 0.0
	var life_max := 0.0
	var shadow_ok := true
	var side_max := 0.0
	for i in 6000:
		if not is_instance_valid(w):
			break
		star_peak = maxi(star_peak, w.stars.size())
		item_peak = maxi(item_peak, w.items.size())
		emitted = w.emitted
		flung = w.flung
		bounced = w.bounced
		far = w.max_dist
		for it: Dictionary in w.items:
			life_max = maxf(life_max, float(it.age) if int(it.phase) < 2 else 0.0)
			side_max = maxf(side_max, float(it.side))
			var sh: MeshInstance3D = it.shadow
			if not is_instance_valid(sh) or (sh.visible and absf(sh.global_position.y - Main.gy(Vector3(it.pos)) - 0.03) > 0.01):
				shadow_ok = false
		await process_frame
	print("  emitted %d · peak %d · flung %d · bounced %d · far %.1fm · stars %d" % [emitted, item_peak, flung, bounced, far, star_peak])
	_check(emitted >= 10 and emitted <= 22 and item_peak >= 3, "소품이 계속 튀어나와 회오리를 돈다 (%d개 · 동시 %d개)" % [emitted, item_peak])
	_check(flung >= 8 and far > 2.0, "소품이 사방으로 내팽개쳐짐 (%d개 · 최대 %.1fm)" % [flung, far])
	_check(bounced >= 4, "바닥에 통통 튐 (%d번)" % bounced)
	_check(star_peak >= 3, "금빛 가산 별이 함께 흩날림 (동시 %d개)" % star_peak)
	_check(shadow_ok, "소품마다 바닥에 붙은 그림자")
	_check(life_max <= WhirlProps.LIFE_MAX + 0.05, "소품 비행 수명 짧게 (최대 %.2f초)" % life_max)
	_check(WhirlProps.SHADER.contains("depth_draw_never") and not WhirlProps.SHADER.contains("depth_draw_always"), "소품 판은 깊이를 쓰지 않음 (기체가 네모로 뚫려 보이지 않게)")
	_check(side_max < 1.35, "소품 크기 절반 (판 최대 %.2fm)" % side_max)
	_check(not is_instance_valid(w), "휠윈드가 끝나면 소품이 모두 사라지고 노드 정리")
	# 컷인 없음 → 소품 없음
	PartnerDrone.cutin_style = "off"
	_check(await _until(func(): return d.whirl_t < 0.0 and d.state == PartnerDrone.St.FOLLOW and d.link_cd <= 0.0, 1500), "분리 뒤 다시 동행")
	d.gauge = PartnerDrone.GAUGE_MAX
	d.maid_props = null
	d.whirl_link()
	_check(await _until(func(): return d.whirl_t >= 0.0, 600), "컷인 꺼도 휠윈드 시작")
	_check(d.maid_props == null, "컷인이 꺼져 있으면 소품 연출 없음")
	PartnerDrone.cutin_style = "diagonal"
	_finish()


func _finish() -> void:
	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
