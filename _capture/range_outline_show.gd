extends SceneTree
## 범위 공격 시전 전 범위 안 적 붉은 외곽선 확인 캡처 (전투 테스트장).
## godot --path . -s _capture/range_outline_show.gd -- --out=DIR
## 0 E 조준: 범위 안 셋 · 1 조준 이동: 하나만 · 3 조준 끝(외곽선 사라짐)
## 4 기 모으기 돌진 경로 안 · 5 최대(끝 원형 참격 포함)

var out := "res://output/range-outline-20261007"
var main: TrainingMain
var p: Player
var fails := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", name)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _dummy(at: Vector3) -> TrainingDummy:
	var d := main._spawn_dummy(at)
	d.anchor = at
	d.global_position = at
	d.immortal = true
	return d


func _run() -> void:
	main = (load("res://scenes/training.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(40)
	p = main.player
	main.god = true
	for d in main.dummies:
		if is_instance_valid(d):
			d.queue_free()
	main.dummies.clear()
	p.global_position = main.center + Vector3(-2.0, 0, 3.5)
	await _frames(2)
	var target := p.global_position + Vector3(4.5, 0, -4.0)
	var a := _dummy(target + Vector3(0.7, 0, 0.2))
	var b := _dummy(target + Vector3(-1.4, 0, -1.2))
	var c := _dummy(target + Vector3(1.0, 0, -2.0))
	var far := _dummy(target + Vector3(5.5, 0, 1.0))
	await _frames(70)
	p.aim_override = Vector3(target.x, p.global_position.y + 0.95, target.z)
	Input.action_press("rush_skill")
	await _frames(24)
	await _shot("0_leap_aim")
	_check(RangeOutline.is_marked(a) and RangeOutline.is_marked(b) and RangeOutline.is_marked(c), "E 조준: 범위 안 셋 외곽선")
	_check(not RangeOutline.is_marked(far), "E 조준: 범위 밖은 없음")
	_check(RangeOutline.count() == p.leap.aim_count, "외곽선 수 = LOCK 수 (%d/%d)" % [RangeOutline.count(), p.leap.aim_count])
	var t2 := far.global_position
	p.aim_override = Vector3(t2.x, p.global_position.y + 0.95, t2.z)
	await _frames(16)
	await _shot("1_leap_aim_moved")
	_check(RangeOutline.is_marked(far) and not RangeOutline.is_marked(a), "조준 옮김: 새 범위만")
	Input.action_release("rush_skill")
	p.aim_override = p.global_position + Vector3(0, 0.95, 6.0)   # 빈 곳으로 도약
	await _frames(30)
	_check(RangeOutline.count() == 0, "조준 끝: 외곽선 없음")
	await _shot("3_after")
	while p.leap.busy():
		await physics_frame
	await _frames(int(LeapSlam.CD * 60) + 10)
	# 기 모으기 돌진: 경로 안
	p.global_position = main.center + Vector3(-5.0, 0, 3.0)
	await _frames(2)
	var line := p.global_position + Vector3(1, 0, 0)
	for d in [a, b, c, far]:
		d.queue_free()
	await _frames(2)
	var r1 := _dummy(p.global_position + Vector3(3.0, 0, 0.3))
	var r2 := _dummy(p.global_position + Vector3(6.0, 0, -0.4))
	var r3 := _dummy(p.global_position + Vector3(4.0, 0, 3.0))    # 경로 밖
	var r4 := _dummy(p.global_position + Vector3(14.5, 0, 1.0))   # 최대 끝 원형 참격 안
	await _frames(60)
	p.aim_override = Vector3(line.x + 10, p.global_position.y + 0.95, line.z)
	Input.action_press("slash_mouse")
	await _frames(40)
	await _shot("4_rush_charge")
	_check(RangeOutline.is_marked(r1) and not RangeOutline.is_marked(r3), "돌진 모으기: 경로 안만")
	await _frames(60)
	await _shot("5_rush_max")
	_check(RangeOutline.is_marked(r2) and RangeOutline.is_marked(r4) and not RangeOutline.is_marked(r3), "최대: 경로 + 끝 원 안")
	Input.action_release("slash_mouse")
	await _frames(20)
	_check(RangeOutline.count() == 0, "돌진 뒤 외곽선 없음")
	print("RESULT fails=%d" % fails)
	quit(1 if fails else 0)
