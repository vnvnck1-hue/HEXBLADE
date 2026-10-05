extends SceneTree
## 바닥 파괴 스타일 확인 캡처 (전투 테스트장).
## godot --path . -s _capture/ground_break_show.gd -- --out=DIR [--only=slab]
## 스타일마다 플레이어 앞에 세기 1.0 연출을 내고 0.05 / 0.18 / 0.6 / 1.6 초에 찍는다 → <스타일>_<n>.png
## 끝에 실제 E 도약 내려찍기 착지 → leap_0/1.png, sheet.png 는 tools 없이 PIL 로 따로 묶음

var out := "res://output/ground-break-20261005"
var only := ""
var main: TrainingMain
var p: Player


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--only="):
			only = a.substr(7)
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


func _run() -> void:
	main = (load("res://scenes/training.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(40)
	p = main.player
	main.god = true
	main.show_help = false
	Main.ui_hidden = true
	for d in main.dummies:
		if is_instance_valid(d):
			d.queue_free()
	main.dummies.clear()
	p.global_position = main.center + Vector3(-2.2, 0, 2.0)
	await _frames(30)
	var at := main.center + Vector3(1.2, 0, -0.8)
	var times := [0.05, 0.18, 0.6, 1.6]
	for s in GroundBreak.STYLES:
		var id: String = s.id
		if id == "off" or (only != "" and id != only):
			continue
		await _frames(150)        # 이전 연출이 사라질 때까지
		GroundBreak.burst(at, 1.0, Vector3(1, 0, -0.4), id)
		var t0 := 0.0
		for i in times.size():
			var wait := float(times[i]) - t0
			await _frames(maxi(1, int(round(wait * 60.0))))
			t0 = float(times[i])
			await _shot("%s_%d" % [id, i])
	# 실제 E 도약 내려찍기 (기본 스타일 SLAB)
	if only == "":
		await _frames(170)
		GroundBreak.style = 0
		p.leap.cd = 0.0
		p.aim_override = Vector3(at.x, p.global_position.y + 0.95, at.z)
		await _frames(2)
		Input.action_press("rush_skill")
		await _frames(10)
		Input.action_release("rush_skill")
		while is_instance_valid(GroundBreak.inst) == false or GroundBreak.inst.bursts.is_empty():
			await physics_frame
		await _frames(8)
		await _shot("leap_0")
		await _frames(20)
		await _shot("leap_1")
		# 지나간 자리 흔적: 대시 중 일격참 → Q 합체 휠윈드
		await _frames(200)
		p.global_position = main.center + Vector3(-7, 0, 2.5)
		p.velocity = Vector3.ZERO
		p.aim_override = p.global_position + Vector3(12, 0.95, -1.5)
		await _frames(4)
		Input.action_press("move_right")
		Input.action_press("dash")
		await _frames(2)
		Input.action_release("dash")
		Input.action_release("move_right")
		await _frames(3)
		Input.action_press("slash")
		await _frames(2)
		Input.action_release("slash")
		await _frames(16)
		await _shot("trail_rush_0")
		await _frames(24)
		await _shot("trail_rush_1")
		p.aim_override = Vector3.INF
		await _frames(150)
		var dr := PartnerDrone.inst
		if is_instance_valid(dr):
			main.infinite = true
			p.global_position = main.center + Vector3(4, 0, 2.5)
			for i in 600:
				if dr.state == PartnerDrone.St.FOLLOW and dr.link_cd <= 0.0 and dr.whirl_t < 0.0:
					break
				await physics_frame
			dr.whirl_link()
			while dr.whirl_t < 0.0:
				await physics_frame
			Input.action_press("move_left")
			await _frames(60)              # 합체 컷인이 지나가고
			for i in 3:
				await _frames(22)
				await _shot("trail_whirl_%d" % i)
			Input.action_release("move_left")
	print("pieces left ", GroundBreak.piece_count())
	quit()
