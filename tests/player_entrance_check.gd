extends SceneTree
## Run with: Godot --headless --path . -s tests/player_entrance_check.gd
## 플레이어 등장 연출 (PlayerEntrance): 화면 아래 밖에서 날아와 브레이크 턴 후 착지, 끝나면 조작을 돌려준다.
## 판정 위치는 움직이지 않고 몸(visual)만 날아야 한다.

var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _run() -> void:
	PlayerEntrance.force = true
	var m: TrainingMain = load("res://scenes/training.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	var p := m.player
	_check(p.entrance != null and p.cine_lock, "등장 시작: 조작 잠금")
	var home := p.global_position
	await physics_frame
	await physics_frame
	var cam := m.get_viewport().get_camera_3d()
	var vp := m.get_viewport().get_visible_rect().size
	var w := p.visual.global_position
	var sy := cam.unproject_position(w).y if not cam.is_position_behind(w) else INF
	_check(sy > vp.y, "첫 틱 몸이 화면 아래 밖 (y=%.0f / %.0f)" % [sy, vp.y])
	_check(p.invuln > 0.0, "등장 중 무적")
	var max_turn := 0.0
	var h0 := p.entrance.heading
	var landed_y := INF
	for i in 80:
		await physics_frame
		if p.entrance.active():
			max_turn = maxf(max_turn, absf(angle_difference(h0, p.entrance.heading)))
			if p.entrance.t >= PlayerEntrance.ARRIVE and landed_y == INF:
				landed_y = p.visual.position.y
	_check(p.global_position.distance_to(home) < 0.05, "판정 위치는 그대로 (%.3f m)" % p.global_position.distance_to(home))
	_check(max_turn > PI * 0.9, "브레이크 턴: 몸이 반 바퀴 돎 (%.0f°)" % rad_to_deg(max_turn))
	_check(landed_y < Player.PIVOT_Y + 0.3, "착지 높이")
	_check(not p.entrance.active() and not p.cine_lock, "끝나면 조작을 돌려줌")
	_check(absf(p.visual.position.x) < 0.001 and absf(p.visual.position.z) < 0.001, "몸이 제자리로")
	PlayerEntrance.force = false
	print("FAILS %d" % fails)
	quit(1 if fails > 0 else 0)
