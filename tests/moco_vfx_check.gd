extends SceneTree
## Run with: Godot --headless --path . -s tests/moco_vfx_check.gd
## mo.co 무드 VFX (scripts/presentation/moco_fx.gd, docs/moco-vfx-claude.md):
##  1. 피격 섬광이 MocoFX 버스트로 그려지고(예전 HitSpark 노드 없음), 동시 묶음 상한 24
##  2. 피해 숫자: 실제 피해 한 번에 한 번 · 짧은 창 합산 · 대상당 최대 2 · 화면 전체 최대 16 · 강타는 노란 숫자 · 가스통(소품)은 숫자 없음
##  3. STUN! 은 실제 경직 진입 때만 (이미 경직 중이면 다시 안 뜸) · 패링 공격 중 피격 규칙(경직·넉백 없음)은 그대로
##  4. 드론 연결선·볼텍스는 수명이 끝나면 사라지고, 보호막은 blend_mix 옅은 면 재질
##  5. 검 궤적 재질이 mo.co 분기 · 일반 120ms / 강타 180ms 안에 사라짐

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


func _run() -> void:
	_check(MocoFX.on, "기본 켜짐 (--vfx=old 아님)")
	var m: Main = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	await _frames(20)
	m.player.invuln = 9999.0
	var c := m.player.global_position
	var e := TrainingDummy.new()
	e.anchor = m.push_out(c + Vector3(4, 0, 0), 1.0)
	e.immortal = true
	m.world.add_child(e)
	e.global_position = e.anchor
	await _frames(100)
	var fx := MocoFX.get_inst()
	_check(fx != null and fx.get_parent() == ToonGunFX.inst, "씬마다 ToonGunFX 아래 MocoFX 하나")

	# ── 1. 버스트 ──
	var before := ToonGunFX.inst.get_child_count()
	e.take_hit(1, Vector3(1, 0, 0), e.global_position + Vector3(-0.3, 1, 0), "bullet")
	await _frames(1)
	_check(fx.burst_count() == 1, "총알 한 발 = 버스트 1")
	_check(ToonGunFX.inst.get_child_count() == before, "예전 방추 노드를 만들지 않음")
	for i in 40:
		fx.hit(c + Vector3(i * 0.1, 1, 0), Vector3.RIGHT, 1.2, i % 2 == 0)
	_check(fx.burst_count() <= MocoFX.MAX_BURSTS, "동시 버스트 상한 %d (%d)" % [MocoFX.MAX_BURSTS, fx.burst_count()])
	await create_timer(0.4).timeout
	_check(fx.burst_count() == 0, "강타도 0.3초 안에 모두 사라짐")

	# ── 2. 숫자 ──
	await _frames(60)
	var e2 := TrainingDummy.new()
	e2.anchor = m.push_out(c + Vector3(-4, 0, 0), 1.0)
	e2.immortal = true
	m.world.add_child(e2)
	e2.global_position = e2.anchor
	await _frames(100)
	for i in 5:
		e2.take_hit(1, Vector3(-1, 0, 0), Vector3.ZERO, "bullet")      # 같은 프레임 연사 → 합산
	await _frames(1)
	var nums := fx.live_numbers()
	_check(nums.size() == 1 and nums[0].text == "5", "같은 순간 연사 5발 → 숫자 하나 '5' %s" % str(nums))
	e2.take_hit(4, Vector3(-1, 0, 0), Vector3.ZERO, "slash")
	await _frames(1)
	var heavy_found := false
	for n in fx.live_numbers():
		if n.kind == "heavy":
			heavy_found = true
	_check(heavy_found, "검 피해는 강타(노란) 숫자")
	for i in 30:
		e2.take_hit(1, Vector3(-1, 0, 0), Vector3.ZERO, "bullet")
		await _frames(6)
	var per := 0
	for n in fx.live_numbers():
		if n.kind != "status":
			per += 1
	_check(per >= 2 and per <= MocoFX.NUM_MAX, "연사는 맞을 때마다 숫자가 따로 튐 (땅굴크루식, 상한 %d) (%d)" % [MocoFX.NUM_MAX, per])
	var log: DamageLog = fx.get_node("MocoNumbers/DamageLog")
	_check(DamageLog.preset == "bounce", "피해 숫자 기본 프리셋은 BOUNCE (%s)" % DamageLog.preset)
	var sp := log.spawn(Vector3.ZERO, 7, false)
	var vy0: float = sp.vy
	await create_timer(0.08, true, false, true).timeout      # 숫자는 실제 시간으로 움직인다
	_check(float(sp.vy) > vy0, "숫자는 위로 튄 뒤 감속 (vy %.0f → %.0f)" % [vy0, float(sp.vy)])
	await create_timer(0.5, true, false, true).timeout
	_check(log.entries.has(sp), "숫자는 0.5초 뒤에도 남아 읽힘")
	await create_timer(0.8, true, false, true).timeout
	_check(not log.entries.has(sp), "숫자 수명 %.2f초 (1.3초 뒤 사라짐)" % DamageLog.LIFE)
	# 연속 타격 열기: 같은 대상을 끊김 없이 때릴수록 달아오름
	var hot := Node3D.new()
	m.world.add_child(hot)
	var first := log.spawn(Vector3.ZERO, 1, false, hot)
	var last := first
	for i in DamageLog.CHAIN_FULL - 1:
		last = log.spawn(Vector3.ZERO, 1, false, hot)
	_check(float(first.heat) == 0.0 and float(last.heat) == 1.0, "연속 %d타에서 열기 0 → 1 (%.2f → %.2f)" % [DamageLog.CHAIN_FULL, float(first.heat), float(last.heat)])
	var c0: Color = first.col
	var c1: Color = last.col
	_check(c0.g > 0.9 and c1.g < 0.4 and c1.r > 0.9, "색이 크림 → 붉은 분홍으로 (%s → %s)" % [c0.to_html(false), c1.to_html(false)])
	_check(float(last.pop) > float(first.pop) and float(last.life) > float(first.life), "달아오를수록 팝·수명이 커짐")
	await create_timer(DamageLog.CHAIN_GAP + 0.1, true, false, true).timeout
	_check(log.chain_of(hot) == 0 and float(log.spawn(Vector3.ZERO, 1, false, hot).heat) == 0.0, "%.2f초 끊기면 연속이 처음부터" % DamageLog.CHAIN_GAP)
	# BOUNCE 프리셋: 튀어 올랐다가 중력으로 떨어짐 · 쌓지 않음
	DamageLog.use("bounce")
	var b1 := log.spawn(Vector3.ZERO, 3, false, hot)
	var b2 := log.spawn(Vector3.ZERO, 3, false, hot)
	await create_timer(0.15, true, false, true).timeout
	var up_y: float = b1.off.y
	_check(up_y < -30.0, "BOUNCE: 먼저 위로 튐 (%.0fpx)" % up_y)
	await create_timer(0.55, true, false, true).timeout
	_check(float(b1.vy) > 0.0 and float(b1.off.y) > up_y, "BOUNCE: 정점 뒤 중력으로 떨어짐 (vy %.0f, y %.0f → %.0f)" % [float(b1.vy), up_y, float(b1.off.y)])
	_check(float(b1.lift_to) == 0.0 and float(b2.lift_to) == 0.0, "BOUNCE: 이전 숫자를 위로 쌓지 않음")
	await create_timer(0.4, true, false, true).timeout
	_check(not log.entries.has(b1), "BOUNCE: %.2f초 안에 사라짐" % DamageLog.B_LIFE)
	DamageLog.use("stack")
	_check(DamageLog.use() == "bounce" and DamageLog.use() == "stack", "프리셋 순환 STACK ↔ BOUNCE")
	hot.queue_free()
	var many: Array[Enemy] = []
	for i in 20:
		var d := TrainingDummy.new()
		d.anchor = m.push_out(c + Vector3(-6 + (i % 5) * 3, 0, 4 + (i / 5) * 2), 1.0)
		d.immortal = true
		m.world.add_child(d)
		d.global_position = d.anchor
		many.append(d)
	await _frames(100)
	for d in many:
		d.take_hit(1, Vector3(0, 0, 1), Vector3.ZERO, "bullet")
	await _frames(1)
	_check(fx.live_numbers().size() <= MocoFX.NUM_MAX, "화면 전체 숫자 최대 %d (%d)" % [MocoFX.NUM_MAX, fx.live_numbers().size()])
	for d in many:
		d.queue_free()
	await _frames(60)
	var gas := GasCanister.new()
	m.world.add_child(gas)
	gas.global_position = m.push_out(c + Vector3(0, 0, -4), 1.0)
	await _frames(60)
	var n0 := fx.live_numbers().size()
	gas.take_hit(1, Vector3(0, 0, -1), Vector3.ZERO, "bullet")
	await _frames(1)
	_check(fx.live_numbers().size() == n0, "가스통(소품)은 피해 숫자 없음")

	# ── 3. STUN ──
	await _frames(60)
	e.stagger(Vector3(1, 0, 0), 1.1)
	e.stagger(Vector3(1, 0, 0), 1.1)
	await _frames(1)
	var stun := 0
	for n in fx.live_numbers():
		if n.kind == "status" and n.text == "STUN!":
			stun += 1
	_check(stun == 1, "경직 진입 STUN! 한 번 (이미 경직 중 재진입은 안 뜸) (%d)" % stun)
	_check(fx.live_numbers().size() <= MocoFX.NUM_MAX, "상태 글자도 상한 안")

	# ── 4. 드론 연출 ──
	var noz := Node3D.new()
	m.world.add_child(noz)
	noz.global_position = c + Vector3(-1, 1.5, 1)
	var links_before := FX.root.find_children("*", "Link", false, false).size()
	DroneFX.tether(noz, m.player, 0.35)
	DroneFX.vortex_disc(m.player, 8.0, 0.75)
	await _frames(2)
	var lk := 0
	var vx := 0
	for ch in FX.root.get_children():
		if ch is DroneFX.Link:
			lk += 1
		elif ch is DroneFX.Vortex:
			vx += 1
	_check(lk == 1 and vx == 1, "연결선·볼텍스 노드 생김 (%d, %d)" % [lk, vx])
	await create_timer(1.2).timeout
	lk = 0
	vx = 0
	for ch in FX.root.get_children():
		if ch is DroneFX.Link:
			lk += 1
		elif ch is DroneFX.Vortex:
			vx += 1
	_check(lk == 0 and vx == 0, "수명이 끝나면 연결선·볼텍스 사라짐")
	var sh := DroneFX.Shield.new()
	m.player.add_child(sh)
	await _frames(2)
	var code: String = (sh.mat.shader as Shader).code
	_check(code.contains("blend_mix") and code.contains("hex_edge"), "보호막: blend_mix 옅은 면 + 육각 셀")
	sh.pop(Vector3(1, 0, 0))
	await create_timer(0.6).timeout
	_check(not is_instance_valid(sh), "보호막 깨지면 사라짐")

	# ── 5. 검 궤적 ──
	_check(FX._slash_mat.get_shader_parameter("moco") == true, "검 궤적 재질 mo.co 분기")
	var n_before := FX.root.get_child_count()
	FX.slash(m.player, 0.0, 0)
	await _frames(1)
	var made := FX.root.get_child_count() - n_before
	await create_timer(0.25).timeout
	var left := FX.root.get_child_count() - n_before
	_check(made >= 1 and left <= 0, "일반 베기 궤적은 0.25초 안에 사라짐 (생김 %d, 남음 %d)" % [made, left])

	print("RESULT moco_vfx_check fails=%d" % fails)
	quit(1 if fails > 0 else 0)
