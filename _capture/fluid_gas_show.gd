extends SceneTree
## 기체 청소 기믹 확인 캡처 + 수치 검사 (화면 있음 — GPU 계산 필요).
##  1. 허수아비 시험장: 안개 둑 + 독가스 세트(구름 3개)가 생긴다. 가만히 두면 독가스는 줄지 않는다.
##  2. 독가스 곁에서 Space 를 누른 채(청소 질주) → 도트로 게이지가 여러 번 나눠 차오르고, 다 빨아들이면 정화 완료.
##  3. 안개 곁에서 빨아들여도 게이지는 오르지 않는다 (청소 대상 아님).
##  4. 방 탐색(main.tscn, --gas=always 상당): 전투방에 들어가면 독가스 세트 · 안개가 생긴다.
## powershell -File tools\godot.ps1 wait --fixed-fps 60 -s res://_capture/fluid_gas_show.gd

var out := "res://output/fluid-smoke-20261005"
var fails := 0


func _initialize() -> void:
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


func _load(path: String) -> Main:
	if current_scene:
		current_scene.queue_free()
		await process_frame
	var m: Main = (load(path) as PackedScene).instantiate()
	root.add_child(m)
	current_scene = m
	await _frames(20)
	Main.ui_hidden = false
	return m


func _run() -> void:
	PartnerDrone.cutin_style = "off"
	# ── 1) 허수아비 시험장 ──
	var tm := await _load("res://scenes/training.tscn") as TrainingMain
	tm.god = true
	tm.infinite = false
	var ff := FluidField.inst
	_check(ff != null and ff.mode == "training", "허수아비 시험장에 유체 연기 (training)")
	await _frames(150)
	_check(ff.banks.size() == 1, "안개 둑 하나")
	_check(ff.sets.size() == 1 and ff.sets[0].state == FluidField.St.ACTIVE and ff.sets[0].m0 > 1.0, "독가스 세트 활성 (구름 %d · 양 %.0f)" % [ff.sets[0].clouds.size(), ff.sets[0].m0])
	var s: Dictionary = ff.sets[0]
	var tox0 := ff.smoke.stat_toxic
	await _frames(600)
	var tox1 := ff.smoke.stat_toxic
	_check(tox1 > tox0 * 0.92 and tox1 < tox0 * 1.08, "가만히 두면 독가스가 거의 그대로 (10초 %.0f → %.0f)" % [tox0, tox1])
	var p := tm.player
	for d in tm.dummies:
		d.anchor = tm.center + Vector3(-6, 0, -7)
		d.global_position = d.anchor
	p.global_position = (s.clouds[0].pos as Vector3) + Vector3(-1.5, 0, 1.0)
	tm.camera.snap(p.global_position)
	await _frames(20)
	await _shot("20_training_gas")
	# ── 2) 청소 질주로 빨아들이기 ──
	var dr := PartnerDrone.inst
	dr.gauge = 0.0
	var t0 := ff.ticks
	var g0 := dr.gauge
	Input.action_press("dash")
	var mid_shot := false
	for i in 600:
		await physics_frame
		# 구름 사이를 천천히 옮겨 다니며 빨아들인다
		var tgt: Vector3 = s.clouds[(i / 120) % s.clouds.size()].pos
		var to := tgt - p.global_position
		to.y = 0
		if to.length() > 1.0:
			p.global_position += to.normalized() * 0.03
		if i == 50 and not mid_shot:
			mid_shot = true
			await _shot("21_sweep_gas")
		if s.state == FluidField.St.CLEARED:
			break
	Input.action_release("dash")
	# 정화 뒤: 남은 독가스가 한 번에 사라지지 않고 몇 초에 걸쳐 걷힘
	var tox_c := ff.smoke.stat_toxic
	_check(ff.fading(), "정화 뒤 걷어 내기 시작")
	await _frames(18)
	var tox_a := ff.smoke.stat_toxic
	await _shot("22a_gas_fading")
	await _frames(72)
	var tox_b := ff.smoke.stat_toxic
	await _frames(180)
	var tox_d := ff.smoke.stat_toxic
	print("FADE toxic %.2f → 0.3s %.2f → 1.5s %.2f → 4.5s %.2f" % [tox_c, tox_a, tox_b, tox_d])
	_check(tox_a > tox_c * 0.5, "0.3초 뒤에도 절반 넘게 남음 = 뿅 사라지지 않음 (%.2f → %.2f)" % [tox_c, tox_a])
	_check(tox_b < tox_a * 0.8 and tox_b > tox_c * 0.1, "1.5초: 서서히 줄어드는 중 (%.2f)" % tox_b)
	_check(tox_d < maxf(tox_c * 0.03, 0.05), "4.5초 뒤 격자 어디에도 거의 안 남음 (%.3f)" % tox_d)
	_check(not ff.fading(), "걷어 내기 끝")
	await _frames(60)
	for i in 60:
		await physics_frame
		if ff._acc < 1.0 and ff._chain_t > 0.3:
			break
	var dt_ticks := ff.ticks - t0
	_check(s.state == FluidField.St.CLEARED, "다 빨아들이면 정화 완료")
	_check(dt_ticks >= 15, "게이지가 도트로 여러 번 나눠 들어옴 (%d번)" % dt_ticks)
	_check(absf((dr.gauge - g0) - s.value) <= 1.5, "정화 한 세트 = 게이지 %.0f (받은 %.0f)" % [s.value, dr.gauge - g0])
	await _shot("22_gas_cleared")
	# ── 3) 안개는 청소 대상 아님 ──
	var b: Dictionary = ff.banks[0]
	p.global_position = b.pos
	tm.camera.snap(p.global_position)
	await _frames(30)
	var t1 := ff.ticks
	var g1 := dr.gauge
	Input.action_press("dash")
	await _frames(150)
	Input.action_release("dash")
	await _frames(30)
	_check(ff.ticks == t1 and absf(dr.gauge - g1) < 0.01, "안개를 빨아들여도 게이지 없음")
	await _shot("23_training_mist")
	# 정화 뒤 시험장은 다시 생긴다
	await _frames(int(FluidField.RESPAWN_T * 60) + 120)
	_check(ff.sets.size() == 2 and ff.sets[1].state == FluidField.St.ACTIVE, "시험장: 정화 뒤 독가스 세트 다시 생김")
	# ── 4) 방 탐색 필드 ──
	var mm := await _load("res://scenes/main.tscn")
	ff = FluidField.inst
	_check(ff != null and ff.mode == "field", "방 탐색에 유체 연기 (field)")
	ff.gas = "always"
	ff.smoke.measure_gpu = true
	var room := -1
	for r in mm.map.rooms:
		if r.combat:
			room = r.id
			break
	_check(room >= 0, "전투방")
	if room >= 0:
		var c := mm.map.room_center_world(room)
		mm.player.global_position = mm.push_out(c, 1.0)
		mm.camera.snap(mm.player.global_position)
		for i in 240:
			await physics_frame
			if ff.sets.size() > 0 and ff.sets[0].state == FluidField.St.ACTIVE:
				break
		_check(ff.sets.size() == 1 and ff.sets[0].clouds.size() >= 2 and ff.sets[0].clouds.size() <= 3, "전투방에 독가스 세트 (구름 %d)" % (ff.sets[0].clouds.size() if ff.sets.size() > 0 else 0))
		_check(ff.banks.size() == 1, "전투방에 안개 둑")
		_check(ff.smoke.nx <= 400 and ff.smoke.ny <= 400, "맵 전체 격자 %d×%d · 칸 %.2fm · %.1fMB" % [ff.smoke.nx, ff.smoke.ny, ff.smoke.cell, ff.smoke.gpu_bytes() / 1048576.0])
		if ff.sets.size() > 0:
			mm.player.global_position = (ff.sets[0].clouds[0].pos as Vector3) + Vector3(-2, 0, 2)
			mm.camera.snap(mm.player.global_position)
		await _frames(60)
		await _shot("24_field_gas")
		print("PERF field compute %.3fms draw %.3fms cpu %.2fms" % [ff.smoke.compute_gpu_ms(), ff.smoke.draw_gpu_ms(), ff.smoke.cpu_usec / 1000.0])
	print("RESULT %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
