extends SceneTree
## E 도약 내려찍기 · 대시 연계 확인 캡처 (전투 테스트장).
## godot --path . -s _capture/leap_slam_show.gd -- --out=DIR
## 0 착지 조준 펼침 · 1 조준 (적 잠금) · 2 사거리 끝(MAX) · 3 도약 정점 · 4 내려찍기 · 5 착지 자국
## 6 대시 중 일격참 · 7 2단 대시 휠윈드

var out := "res://output/leap-slam-20261005"
var main: TrainingMain
var p: Player


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


func _dummy(at: Vector3) -> TrainingDummy:
	var d := main._spawn_dummy(at)
	d.anchor = at
	d.global_position = at
	d.immortal = true
	return d


func _clear() -> void:
	for d in main.dummies:
		if is_instance_valid(d):
			d.queue_free()
	main.dummies.clear()


func _run() -> void:
	main = (load("res://scenes/training.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(40)
	p = main.player
	main.god = true
	_clear()
	p.global_position = main.center + Vector3(-2.0, 0, 3.5)
	await _frames(2)
	var target := p.global_position + Vector3(4.5, 0, -4.0)
	_dummy(target + Vector3(0.7, 0, 0.2))
	_dummy(target + Vector3(-1.4, 0, -1.2))
	_dummy(target + Vector3(1.0, 0, -2.0))
	_dummy(target + Vector3(5.5, 0, 1.0))
	await _frames(70)
	p.aim_override = Vector3(target.x, p.global_position.y + 0.95, target.z)
	main.camera.snap(p.global_position + Vector3(2.0, 0, -2.0)) if main.camera.has_method("snap") else null
	await _frames(4)
	Input.action_press("rush_skill")
	await _frames(4)
	await _shot("0_deploy")
	await _frames(20)
	await _shot("1_aim_lock")
	p.aim_override = p.global_position + Vector3(14.0, 0.95, -6.0)
	await _frames(10)
	await _shot("2_aim_max")
	p.aim_override = Vector3(target.x, p.global_position.y + 0.95, target.z)
	await _frames(6)
	Input.action_release("rush_skill")
	await _frames(14)
	await _shot("3_leap_apex")
	while p.leap.flying():
		await physics_frame
	await _frames(1)
	await _shot("4_slam")
	await _frames(14)
	await _shot("5_marks")
	print("hits=%d stuns=%d cd=%.2f" % [p.leap.last_hits, p.leap.last_stuns, p.leap.cd])
	await _frames(60)
	# 대시 중 일격참
	p.aim_override = p.global_position + Vector3(-5.0, 0.95, 0.5)
	p.dash_cd = 0.0
	Input.action_press("move_down")
	Input.action_press("dash")
	await _frames(2)
	Input.action_release("dash")
	Input.action_release("move_down")
	await _frames(4)
	Input.action_press("slash")
	await _frames(2)
	Input.action_release("slash")
	await _frames(2)
	await _shot("6_dash_strike")
	await _frames(50)
	# 2단 대시 휠윈드
	p.dash_cd = 0.0
	Input.action_press("dash")
	await _frames(2)
	Input.action_release("dash")
	while p.dash_t > Player.CHAIN_WINDOW * 0.6:
		await physics_frame
	Input.action_press("dash")
	await _frames(2)
	Input.action_release("dash")
	await _frames(24)
	await _shot("7_whirl")
	print("whirl=%s" % p.whirl.active())
	p.aim_override = Vector3.INF
	quit()
