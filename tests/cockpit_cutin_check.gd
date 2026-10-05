extends SceneTree
## Run with: Godot --headless --path . -s tests/cockpit_cutin_check.gd
## 드론 조종석 합체 컷인 (scripts/drone/cockpit_cutin.gd · docs/drone-cockpit-cutin-claude-handoff.md):
##  1. Q 즉시 합체(게이지 30 이상, 미만이면 거절)에 컷인 1개 · layer 9 · 입력 통과 · 실제 합체 순간에 잠금(dock)
##  2. 컷인과 함께면 GattaiFX 는 집중선만(compact, 컷인 아래 층) · 휠윈드는 그대로 시작
##  3. 가슴 스프링이 진입·합체 충격의 관성으로 흔들리고(셰이더 변위) 끝에는 잦아든다
##  4. 실제 시간으로 흘러 히트스탑에도 제때 사라진다 · 반복 Q 로 쌓이지 않는다
##  5. 분리 Q · 자동 복귀(fast=false)에는 컷인 없음 · 합체 비행이 끊기면 접힌다 · --cutin=off 없이도 드론 제거 시 정리

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


func _cutins() -> Array:
	var r := []
	for c in current_scene.get_children():
		if c is CockpitCutin and not c.is_queued_for_deletion():
			r.append(c)
	return r


func _gattai_fx() -> Array:
	var r := []
	for c in current_scene.get_children():
		if c is GattaiFX and not c.is_queued_for_deletion():
			r.append(c)
	return r


func _ready_drone(d: PartnerDrone) -> void:
	if d.docked():
		d._detach()
	await _until(func(): return d.state == PartnerDrone.St.FOLLOW and d.link_cd <= 0.0 and d.whirl_t < 0.0, 600)
	await _until(func(): return _cutins().is_empty(), 300)


func _run() -> void:
	PartnerDrone.cutin_style = "cockpit"   # 예전 조종석 컷인 (보관본) 검사 — 새 사선 컷인은 diagonal_cutin_check
	var lab: DroneLab = load("res://scenes/drone.tscn").instantiate()
	lab.spawning = false
	root.add_child(lab)
	current_scene = lab
	await _frames(4)
	lab.spawning = false
	var d := PartnerDrone.inst
	_check(await _until(func(): return d.state == PartnerDrone.St.FOLLOW, 400), "드론 동행 시작")

	# 1. 게이지 넉넉: 컷인 + 휠윈드
	d.gauge = PartnerDrone.GAUGE_MAX
	d.whirl_link()
	var cs := _cutins()
	_check(cs.size() == 1 and d.state == PartnerDrone.St.RECALL, "Q 합체 시작 → 컷인 1개")
	var c: CockpitCutin = cs[0] if cs.size() > 0 else null
	if c == null:
		quit(1)
		return
	_check(c.layer == CockpitCutin.LAYER and c.layer < 10, "컷인 layer 9 (HUD 10 아래)")
	_check(c.root.mouse_filter == Control.MOUSE_FILTER_IGNORE and c.panel.mouse_filter == Control.MOUSE_FILTER_IGNORE \
		and c.plate.mouse_filter == Control.MOUSE_FILTER_IGNORE, "컷인 Control 은 입력을 가로채지 않는다")
	_check(c.dock_t < 0.0, "합체 전에는 잠금 전")
	d.whirl_link()
	_check(_cutins().size() == 1, "합체 비행 중 Q 를 또 눌러도 쌓이지 않는다")
	var t0 := Time.get_ticks_msec()
	_check(await _until(func(): return d.state == PartnerDrone.St.DOCKED, 300), "합체 완료")
	_check(is_instance_valid(c) and c.dock_t >= 0.0, "실제 합체 순간에 잠금 알림(notify_dock)")
	var gf := _gattai_fx()
	_check(gf.size() == 1 and (gf[0] as GattaiFX).compact and (gf[0] as GattaiFX).layer < CockpitCutin.LAYER,
		"GattaiFX 는 컷인 아래 층 집중선만 (말풍선·글자 중복 없음)")
	_check(d.whirl_t >= 0.0, "휠윈드는 그대로 시작")
	await _until(func(): return c.ph == CockpitCutin.Ph.EXIT, 600)
	var peak := c.jig_peak if is_instance_valid(c) else 0.0
	print("  jig_peak=%.1f px" % peak)
	_check(peak > 8.0 and peak <= CockpitCutin.JIG_MAX + 0.01, "가슴이 관성으로 흔들린다 (최대 변위 8~30px)")
	if is_instance_valid(c):
		var off: Vector2 = c.mat.get_shader_parameter("off_l")
		_check(off == (c.jig[0] as Vector2) / CockpitCutin.ART, "흔들림이 셰이더 변위로 들어간다")
	var wc: WeakRef = weakref(c)
	_check(await _until(func(): return wc.get_ref() == null, 600), "컷인이 끝나면 사라진다")
	var life := (Time.get_ticks_msec() - t0) / 1000.0
	print("  life=%.2fs (real)" % life)
	_check(life < 1.6, "실제 시간으로 흐른다 (히트스탑 중에도 1.6초 안에 끝)")

	# 2. 게이지 휠윈드 미만: Q 합체 거절 → 컷인 없음
	await _ready_drone(d)
	d.gauge = PartnerDrone.WHIRL_COST - 5.0
	d.whirl_link()
	await _frames(2)
	_check(_cutins().is_empty() and d.state != PartnerDrone.St.RECALL, "게이지 30 미만이면 Q 합체 거절 · 컷인 없음")

	# 3. 휠윈드 끝 자동 분리 때도 컷인 없음
	await _ready_drone(d)
	d.gauge = PartnerDrone.GAUGE_MAX
	d.whirl_link()
	await _until(func(): return d.state == PartnerDrone.St.DOCKED, 300)
	await _until(func(): return _cutins().is_empty(), 600)
	await _until(func(): return d.whirl_t < 0.0, 900)
	await _frames(2)
	_check(d.state != PartnerDrone.St.DOCKED and _cutins().is_empty(), "휠윈드 끝 자동 분리 · 분리에는 컷인 없음")

	# 4. 자동 복귀(fast=false): 컷인 없음
	await _ready_drone(d)
	d.gauge = PartnerDrone.GAUGE_MAX
	d.toggle_link()
	await _frames(2)
	_check(d.state == PartnerDrone.St.RECALL and _cutins().is_empty(), "보통 합체(fast=false)는 큰 컷인 없음")
	await _until(func(): return d.state == PartnerDrone.St.DOCKED, 300)
	_check(_gattai_fx().is_empty(), "보통 합체는 만화 연출도 없음 (기존 그대로)")

	# 5. 합체 비행이 끊기면 접힌다
	await _ready_drone(d)
	d.gauge = PartnerDrone.GAUGE_MAX
	d.whirl_link()
	var c2: CockpitCutin = _cutins()[0]
	await _frames(2)
	d._go(PartnerDrone.St.FOLLOW)
	d._whirl_pending = false
	await process_frame
	await process_frame
	_check(is_instance_valid(c2) and c2.ph == CockpitCutin.Ph.EXIT, "합체 비행이 끊기면 퇴장")
	var wc2: WeakRef = weakref(c2)
	_check(await _until(func(): return wc2.get_ref() == null, 120), "끊긴 컷인도 정리된다")

	# 6. 드론이 사라지면 같이 정리
	await _ready_drone(d)
	d.gauge = PartnerDrone.GAUGE_MAX
	d.whirl_link()
	var c3: CockpitCutin = _cutins()[0]
	d.queue_free()
	await process_frame
	await process_frame
	_check(not is_instance_valid(c3), "드론이 제거되면 컷인도 제거")

	Engine.time_scale = 1.0
	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
