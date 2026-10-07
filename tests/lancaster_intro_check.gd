extends SceneTree
## Run with: Godot --headless --path . -s tests/lancaster_intro_check.gd
## LANCASTER 첫 등장 연출 (LancasterIntro + LancasterBoss INTRO):
##  들어오기 전: 등 돌리고 선 채 대기 → 들어오면 조작 잠금 · 연출 카메라 · 레터박스 · UI 가 화면 밖으로
##  → 벌레 학살(사격) → 다가온 한 마리 짓밟기 → 흘깃 → 상체 먼저 · 하체 나중에 돌아섬 → 재장전 → 붉은 눈 · 경보 → 보스전
##  끝나면 카메라 · UI · 조작이 원래대로, 엑스트라 벌레 처치는 점수 · 콤보에 안 들어간다. U = 다시 보기, Enter = 건너뛰기.

var fails := 0
var main: TrainingMain
var room: TrainingBossRoom
var boss: LancasterBoss
var p: Player


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _key(k: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.keycode = k
	ev.pressed = true
	main._unhandled_input(ev)


func _run() -> void:
	main = (load("res://scenes/training.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(20)
	p = main.player
	main.god = false
	room = main.boss_room
	boss = room.boss
	_check(boss.st == LancasterBoss.St.DORMANT and boss.intro_ready, "들어오기 전: 등장 연출 대기")
	var back := boss._dir_of(boss.face_yaw)
	var to_door := room.door - boss.global_position
	to_door.y = 0
	_check(back.dot(to_door.normalized()) < -0.9, "입구(플레이어 쪽)에 등을 돌리고 서 있다")
	await _frames(30)
	_check(boss.rig.kneel < 0.05, "무릎 꿇지 않고 서 있다 (%.2f)" % boss.rig.kneel)

	var calm: Control = main.hud.presets.calm
	var dock: Control = null
	for c in main.hud.presets.get_children():
		if c is RoundSkillDock:
			dock = c
	var calm0 := calm.position
	var dock0 := dock.position
	var panel0 := main.panel.position
	var score0 := main.score
	var kills0 := main.kills
	var hp0 := p.hp

	# 들어간다
	p.global_position = room.door + Vector3(-1.0, 0, 0)
	await _frames(4)
	_check(boss.st == LancasterBoss.St.INTRO, "들어오면 등장 연출 시작")
	_check(is_instance_valid(room.intro), "연출 감독이 생긴다")
	_check(p.cine_lock, "플레이어 조작 잠금")
	_check(boss.ip == "aim", "처음은 총을 들어 겨누기")
	_check(root.get_viewport().get_camera_3d() != main.camera, "연출 카메라로 바뀐다")
	var bugs := 0
	for e in get_nodes_in_group("enemies"):
		if e is BugEnemy and e.cine:
			bugs += 1
	_check(bugs == 5, "엑스트라 벌레 5마리 (사격 4 + 짓밟기 1) — %d" % bugs)
	await _frames(50)
	_check(calm.position.y < calm0.y - 200.0, "위 상태 HUD 는 위로 나간다 (%.0f)" % (calm.position.y - calm0.y))
	_check(dock.position.y > dock0.y + 200.0, "아래 스킬 HUD 는 아래로 나간다 (%.0f)" % (dock.position.y - dock0.y))
	_check(main.panel.position.x < panel0.x - 200.0, "왼쪽 패널은 왼쪽으로 나간다")
	_check(room.intro.bar_k > 0.95 and room.intro.top_bar.position.y > -2.0, "레터박스가 들어와 있다")

	# 타임라인 관찰
	var seen := {}
	var order: Array[String] = []
	var gun_dead_before_stomp := false
	var stomp_alive_at_stomp := false
	var stomp_bug: Node3D = boss.intro_stomp
	var stomp_dead_at := -1.0
	var twist_upper := 0.0
	var face_at_upper_end := 0.0
	var face0 := boss.face_yaw
	var steps := 0
	var rage_max := 0.0
	var shots := 0
	var frames := 0
	while boss.st == LancasterBoss.St.INTRO and frames < 60 * 30:
		var ip := boss.ip
		if not seen.has(ip):
			seen[ip] = frames
			order.append(ip)
			if ip == "stomp":
				gun_dead_before_stomp = boss._intro_left() == 0
				stomp_alive_at_stomp = is_instance_valid(stomp_bug) and stomp_bug.alive
			if ip == "turn_lower":
				face_at_upper_end = boss.face_yaw
		if ip == "slaughter" and boss.rig.spin > 40.0:
			shots += 1
		if ip == "turn_upper":
			twist_upper = maxf(twist_upper, absf(boss.rig.twist))
		if ip == "turn_lower":
			steps += boss.rig.stepped
		if stomp_dead_at < 0.0 and (not is_instance_valid(stomp_bug) or not stomp_bug.alive):
			stomp_dead_at = frames
		rage_max = maxf(rage_max, boss.rig.rage)
		frames += 1
		await physics_frame
	print("  순서 ", order, "  %.1f초" % (frames / 60.0), "  단계 시작 프레임 ", seen)
	_check(order == ["slaughter", "stomp", "crush", "glance", "turn_upper", "turn_lower", "reload", "alarm"], "연출 순서")
	_check(shots > 30, "개틀링으로 쓸어 버린다 (%d 틱)" % shots)
	_check(gun_dead_before_stomp, "사격 표적 4마리를 다 쓰러뜨린 뒤 짓밟기")
	_check(stomp_alive_at_stomp, "짓밟을 벌레는 발을 들 때까지 살아서 기어 온다")
	_check(stomp_dead_at >= float(seen.get("crush", 99999)) - 1 and stomp_dead_at <= float(seen.get("crush", -99)) + 2, "발을 내리찍는 순간 벌레가 터진다")
	_check(absf(wrapf(face_at_upper_end - face0, -PI, PI)) < 0.05, "상체가 도는 동안 하체는 그대로")
	_check(twist_upper > 1.2, "상체가 먼저 크게 돌아선다 (%.2f rad)" % twist_upper)
	_check(steps >= 2, "하체는 쿵쿵 디디며 돈다 (%d 걸음)" % steps)
	var to_p := p.global_position - boss.global_position
	_check(boss._dir_of(boss.face_yaw).dot(Vector3(to_p.x, 0, to_p.z).normalized()) > 0.95, "다 돌면 플레이어를 정면으로 본다")
	_check(rage_max > 0.8, "경보 때 눈이 붉게 (%.2f)" % rage_max)
	var total := (frames + 54) / 60.0
	_check(total > 9.0 and total < 16.0, "연출 길이 %.1f초" % total)
	_check(boss.st == LancasterBoss.St.FIGHT, "연출 끝 → 보스전")
	_check(p.hp == hp0, "연출 중 플레이어는 맞지 않는다")
	main.god = true
	_check(not room.bar.root.visible, "체력바는 레터박스가 걷힐 때까지 기다린다")
	await _frames(150)
	_check(not is_instance_valid(room.intro), "연출 감독 정리")
	_check(room.bar.root.visible, "레터박스가 걷히며 보스 체력바가 나타난다")
	_check(not p.cine_lock, "조작 잠금 풀림")
	_check(root.get_viewport().get_camera_3d() == main.camera, "게임 카메라로 돌아온다")
	_check(calm.position.distance_to(calm0) < 0.5 and dock.position.distance_to(dock0) < 0.5 and main.panel.position.distance_to(panel0) < 0.5, "UI 가 원래 자리로")
	_check(main.score == score0 and main.kills == kills0, "엑스트라 처치는 점수 · 처치 수에 안 들어간다")
	var left := 0
	for e in get_nodes_in_group("enemies"):
		if e is BugEnemy:
			left += 1
	_check(left == 0, "엑스트라 벌레가 남지 않는다")

	# 다시 보기 (U) → Enter 건너뛰기
	main.god = true
	_key(KEY_U)
	await _frames(3)
	_check(is_instance_valid(room.intro) and room.boss.st == LancasterBoss.St.INTRO, "U = 등장 연출 다시 보기")
	boss = room.boss
	await _frames(40)
	var ev := InputEventKey.new()
	ev.keycode = KEY_ENTER
	ev.physical_keycode = KEY_ENTER
	ev.pressed = true
	room.intro._unhandled_input(ev)
	await _frames(3)
	_check(boss.st == LancasterBoss.St.FIGHT, "Enter = 건너뛰고 바로 보스전")
	await _frames(120)
	_check(not is_instance_valid(room.intro) and not p.cine_lock and root.get_viewport().get_camera_3d() == main.camera, "건너뛴 뒤에도 원래대로")
	var left2 := 0
	for e in get_nodes_in_group("enemies"):
		if e is BugEnemy:
			left2 += 1
	_check(left2 == 0, "건너뛰면 엑스트라 벌레도 치운다")

	print("RESULT %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(0 if fails == 0 else 1)
