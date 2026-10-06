extends SceneTree
## 부스터 연소가스 확인 캡처 + 수치 검사 (화면 있음 — GPU 계산 필요).
## 허수아비 시험장에서 Shift 부스터로 달리면 등 뒤 분사구 쪽에 배기가 꼬리처럼 남고, 끄면 몇 초 안에 흩어진다.
## powershell -File tools\godot.ps1 wait --fixed-fps 60 -s res://_capture/boost_exhaust_show.gd
## → output/boost-exhaust-20261006/

var out := "res://output/boost-exhaust-20261006"
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


func _steam(sm: FluidSmoke, p: Vector3) -> float:
	return sm.exhaust_at(p, 0.8)


## 화면에서 플레이어 둘레(반경 px) 의 선명한 배기 색(주황 · 분홍 · 보라 · 노랑, 초록 계열 제외) 화소 수
func _vivid(tm: TrainingMain, at: Vector3, px := 260.0) -> int:
	var img := root.get_texture().get_image()
	var c := tm.camera.unproject_position(at)
	var n := 0
	for y in range(maxi(0, int(c.y - px)), mini(img.get_height(), int(c.y + px)), 2):
		for x in range(maxi(0, int(c.x - px)), mini(img.get_width(), int(c.x + px)), 2):
			var col := img.get_pixel(x, y)
			if col.s > 0.45 and col.v > 0.55 and (col.h < 0.14 or col.h > 0.72):
				n += 1
	return n


## 그 쪽(side = -1 뒤 · +1 앞, X 축) 영역에서 가장 짙은 증기 채널 밀도
func _zone(sm: FluidSmoke, c: Vector3, side: float) -> float:
	var m := 0.0
	for dx in [1.5, 2.5, 3.5]:
		for dz in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			m = maxf(m, sm.exhaust_at(c + Vector3(dx * side, 0, dz), 0.3))
	return m


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	PartnerDrone.cutin_style = "off"
	var tm: TrainingMain = (load("res://scenes/training.tscn") as PackedScene).instantiate()
	root.add_child(tm)
	current_scene = tm
	await _frames(30)
	Main.ui_hidden = true
	tm.god = true
	var ff := FluidField.inst
	if ff:
		ff.gas = "off"
		ff.banks.clear()
		ff._respawn = -1.0
		ff.sets.clear()
		ff._fades.clear()
	var sm := FluidSmoke.inst
	_check(sm != null and sm.active, "유체 연기 GPU 계산")
	var p := tm.player
	p.infinite_boost = false
	var start := tm.center + Vector3(-8, 0, 2)
	p.global_position = start
	tm.camera.snap(p.global_position)
	await _frames(60)
	sm.clear()
	await _frames(10)
	# 부스터 없이 걷기: 배기 없음
	Input.action_press("move_right")
	await _frames(40)
	var walk_k := _steam(sm, p.global_position - Vector3(1.2, 0, 0))
	Input.action_release("move_right")
	_check(walk_k < 0.02, "부스터 없이 걸으면 배기 없음 (%.3f)" % walk_k)
	await _frames(60)
	# 부스터로 오른쪽 → 위로 꺾어 달리기
	p.global_position = start
	sm.clear()
	await _frames(5)
	Input.action_press("boost")
	Input.action_press("move_right")
	await _frames(12)
	await _shot("01_boost_start")
	await _frames(30)
	var behind := _zone(sm, p.global_position, -1.0)
	var ahead := _zone(sm, p.global_position, 1.0)
	_check(behind > 0.08 and behind > ahead * 3.0, "달리는 등 뒤에 배기 꼬리 (뒤 %.3f · 앞 %.3f)" % [behind, ahead])
	await _shot("02_boost_run")
	var vivid := _vivid(tm, p.global_position)
	_check(vivid > 150, "배기 색(주황·분홍·보라)이 화면에 보임 (화소 %d)" % vivid)
	var run_amount := sm.total_exhaust()
	Input.action_release("move_right")
	Input.action_press("move_up")
	await _frames(40)
	await _shot("03_boost_turn")
	Input.action_release("move_up")
	Input.action_release("boost")
	var tail := p.global_position
	await _frames(20)
	await _shot("04_boost_off")
	var k0 := sm.total_exhaust()
	await _frames(70)
	var k1 := sm.total_exhaust()
	_check(k1 < k0 * 0.12, "끄면 1.5초 안에 거의 사라짐 (%.1f → %.1f)" % [k0, k1])
	_check(run_amount < 260.0, "달리는 동안 격자 위 배기 양이 적음 (%.0f)" % run_amount)
	await _shot("05_after")
	# 방향키 없이 부스터(조준 방향으로 날아감)도 뿜음
	sm.clear()
	await _frames(5)
	Input.action_press("boost")
	await _frames(45)
	var still := sm.total_exhaust()
	Input.action_release("boost")
	_check(still > 1.0, "방향키 없이 부스터도 배기 (%.1f)" % still)
	# 끄기
	sm.exhaust_on = false
	sm.clear()
	await _frames(5)
	Input.action_press("boost")
	await _frames(45)
	Input.action_release("boost")
	_check(sm.total_exhaust() < 0.5, "--exhaust=off 면 배기 없음 (%.2f)" % sm.total_exhaust())
	print("RESULT %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
