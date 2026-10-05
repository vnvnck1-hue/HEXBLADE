extends SceneTree
## 유체 연기 확인 캡처 + GPU 계산 수치 검사 (헤드리스 아님 — 컴퓨트 셰이더가 있어야 한다).
## 통풍구 · 가득 채움 · 대시 가르기 · 검 · 폭발 바람 · 합체 휠윈드 · 청소 질주를 찍고,
## 그때마다 격자 밀도를 GPU 에서 읽어 와 연기가 실제로 밀렸는지 본다 (CHECK 줄, 마지막 RESULT).
## powershell -File tools\godot.ps1 wait --fixed-fps 60 -s res://_capture/fluid_smoke_show.gd -- [--out=DIR]

var out := "res://output/fluid-smoke-20261005"
var main: FluidLab
var fails := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("CHECK ok   " if ok else "CHECK FAIL ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", name)


func _tap(action: String, frames := 2) -> void:
	Input.action_press(action)
	await _frames(frames)
	Input.action_release(action)


func _run() -> void:
	var inst := (load("res://scenes/fluid_smoke.tscn") as PackedScene).instantiate()
	if not (inst is FluidLab):
		# 스크립트가 컴파일되지 않으면 멈추지 말고 끝낸다 (헤드리스 테스트가 영영 기다리지 않게)
		print("RESULT FAIL (fluid_smoke.tscn 스크립트 로드 실패)")
		quit(1)
		return
	main = inst
	root.add_child(main)
	current_scene = main
	await _frames(30)
	var s := main.smoke
	_check(s.active, "GPU 계산 켜짐 (격자 %d×%d)" % [s.nx, s.ny])
	if not s.active:
		print("RESULT FAIL (no GPU)")
		quit(1)
		return
	main.god = true
	PartnerDrone.cutin_style = "off"
	main.show_help = false
	Main.ui_hidden = true
	main._apply_ui()
	var p := main.player
	for d in main.dummies:
		d.anchor = main.center + Vector3(0, 0, -8)
		d.global_position = d.anchor
	# 1) 통풍구만으로 차오르는지
	var vent: Vector3 = main.center + FluidLab.VENTS[0]
	var before := s.total_density()
	await _frames(240)
	_check(s.total_density() > before + 20.0, "통풍구가 연기를 채움 (합 %.0f → %.0f)" % [before, s.total_density()])
	_check(s.density_at(vent, 0.6) > 0.3, "통풍구 둘레 밀도 %.2f" % s.density_at(vent, 0.6))
	await _shot("01_vents")
	# 2) 가득 채우고 대시로 가르기
	s.vents_on = false
	s.clear()
	s.fill(0.7)
	p.global_position = main.center + Vector3(-7, 0, 1)
	main.camera.snap(p.global_position)
	await _frames(40)
	await _shot("02_filled")
	s.clear()
	s.fill(0.6, false)       # 수치 검사는 고른 연기에서
	await _frames(10)
	var lane := main.center + Vector3(-3.5, 0, 1)
	var side := main.center + Vector3(-3.5, 0, 4.5)
	var d_lane0 := s.density_at(lane, 0.5)
	p.aim_override = p.global_position + Vector3(10, 0.95, 0)
	Input.action_press("move_right")
	await _frames(3)
	await _tap("dash", 3)
	await _frames(12)
	Input.action_release("move_right")
	await _frames(6)
	var d_lane1 := s.density_at(lane, 0.5)
	var d_side := s.density_at(side, 0.5)
	_check(d_lane1 < d_lane0 * 0.75, "대시가 지나간 길이 갈라짐 (%.2f → %.2f, 옆 %.2f)" % [d_lane0, d_lane1, d_side])
	await _shot("03_dash_part")
	# 3) 검 휘두르기
	await _frames(30)
	for i in 6:
		await _tap("slash", 2)
		await _frames(10)
	await _shot("04_slash")
	# 4) 폭발 바람: 가운데가 비고 둘레로 밀려남
	s.clear()
	s.fill(0.6, false)
	await _frames(20)
	var bc := main.center + Vector3(5, 0, -2)
	var ring := bc + Vector3(1.9, 0, 0)
	var c0 := s.density_at(ring, 0.5)
	FluidSmoke.blast(bc, 3.4, 1.3, 0.0)   # 수치 검사는 그을음 없이 바람만
	await _frames(12)
	var c1 := s.density_at(ring, 0.5)
	_check(c1 < c0 * 0.5, "폭발 바람이 둘레 연기를 밀어냄 (%.2f → %.2f)" % [c0, c1])
	s.clear()
	s.fill(0.7)
	await _frames(20)
	FX.fire_explosion(bc, 1.0)          # 화면: 실제 폭발 (Distortion.burst → 바람 + 그을음)
	await _frames(14)
	await _shot("05_blast")
	await _frames(40)
	await _shot("06_blast_after")
	# 5) 드론 합체 휠윈드: 몸 둘레가 휘감김
	s.clear()
	s.fill(0.7)
	p.aim_override = Vector3.INF
	p.global_position = main.center + Vector3(-2, 0, 2)
	main.camera.snap(p.global_position)
	await _frames(30)
	var dr := PartnerDrone.inst
	if is_instance_valid(dr):
		for i in 400:
			if dr.state == PartnerDrone.St.FOLLOW and dr.link_cd <= 0.0 and dr.whirl_t < 0.0:
				break
			await physics_frame
		dr.whirl_link()
		for i in 300:
			if dr.whirl_t >= 0.0:
				break
			await physics_frame
		await _frames(40)
		_check(dr.whirl_t >= 0.0 and s.emitters.any(func(e): return e[0] == FluidSmoke.Kind.SWIRL), "합체 휠윈드 소용돌이 방출기")
		await _shot("07_whirl")
		while dr.whirl_t >= 0.0:
			await physics_frame
		await _frames(20)
		await _shot("08_whirl_after")
	# 6) 청소 질주: 둘레 연기를 빨아들여 먹음
	s.clear()
	s.fill(0.6, false)
	await _frames(30)
	var r0 := s.density_at(p.global_position, 2.5)
	Input.action_press("dash")
	await _frames(70)
	var swept := is_instance_valid(dr) and dr.sweeping
	var r1 := s.density_at(p.global_position, 2.5)
	await _shot("09_sweep")
	Input.action_release("dash")
	_check(swept and r1 < r0 * 0.7, "청소 질주가 연기를 빨아들임 (%.2f → %.2f, 질주 %s)" % [r0, r1, swept])
	# 7) 실제 플레이에 가까운 모습: 통풍구만 켜고 한참 둔 뒤 연기 덩어리 사이를 대시로 지나간다
	s.clear()
	s.vents_on = true
	p.aim_override = Vector3.INF
	p.global_position = main.center + Vector3(-11, 0, -2)
	main.camera.snap(p.global_position)
	await _frames(600)
	await _shot("11_vents_long")
	p.aim_override = p.global_position + Vector3(10, 0.95, -3)
	Input.action_press("move_right")
	Input.action_press("move_up")
	await _frames(3)
	await _tap("dash", 3)
	await _frames(14)
	Input.action_release("move_up")
	Input.action_release("move_right")
	await _frames(4)
	await _shot("12_vents_dash")
	for i in 5:
		await _tap("slash", 2)
		await _frames(9)
	await _shot("13_vents_slash")
	# 8) 스타일 프리셋 4종: 통풍구마다 다른 스타일로 한참 뿜은 뒤 전체 · 통풍구별 가까이
	s.clear()
	s.vents_on = true
	s.force_style = -1
	main._refresh_vents()
	p.aim_override = main.center + Vector3(0, 0.95, -6)
	p.global_position = main.center + Vector3(0, 0, 1)
	main.camera.snap(p.global_position)
	await _frames(720)
	for i in FluidLab.VENTS.size():
		var at: Vector3 = main.center + FluidLab.VENTS[i]
		var own := s.style_at(at, i, 0.8)
		var other := 0.0
		for j in 4:
			if j != i:
				other += s.style_at(at, j, 0.8)
		_check(own > 0.4 and other < own * 0.25, "통풍구 %d 는 %s 연기 (제 몫 %.2f · 다른 몫 %.2f)" % [i, FluidSmoke.STYLES[i].name, own, other])
	await _shot("14_presets_all")
	for i in FluidLab.VENTS.size():
		var at: Vector3 = main.center + FluidLab.VENTS[i]
		p.global_position = at + Vector3(signf(-FluidLab.VENTS[i].x) * 3.0, 0, 2.6)
		main.camera.snap(p.global_position)
		await _frames(30)
		await _shot("15_preset_%d_%s" % [i, FluidSmoke.STYLES[i].id])
	# 통풍구를 끄면 독가스는 오래 고이고 증기는 금방 흩어진다
	var tox_at: Vector3 = main.center + FluidLab.VENTS[2]
	var stm_at: Vector3 = main.center + FluidLab.VENTS[3]
	var tox0 := s.style_at(tox_at, 2, 2.0)
	var stm0 := s.style_at(stm_at, 3, 2.0)
	s.vents_on = false
	main._refresh_vents()
	await _frames(180)
	var tox1 := s.style_at(tox_at, 2, 2.0)
	var stm1 := s.style_at(stm_at, 3, 2.0)
	_check(tox1 / maxf(tox0, 1e-3) > 1.5 * stm1 / maxf(stm0, 1e-3), "독가스는 고이고 증기는 흩어짐 (3초 뒤 독가스 %.0f%% · 증기 %.0f%%)" % [tox1 / maxf(tox0, 1e-3) * 100.0, stm1 / maxf(stm0, 1e-3) * 100.0])
	# 모두 한 스타일로 (F10)
	s.clear()
	s.vents_on = true
	s.force_style = 2
	main._refresh_vents()
	p.global_position = main.center + Vector3(0, 0, 1)
	main.camera.snap(p.global_position)
	await _frames(480)
	_check(s.style_at(main.center + FluidLab.VENTS[1], 2, 0.8) > 0.4, "F10 고정: 모든 통풍구가 독가스")
	await _shot("16_all_toxic")
	s.force_style = -1
	# 9) 밀도 그대로 화면
	s.view_mode = 1
	await _frames(5)
	await _shot("10_debug_density")
	print("RESULT %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
