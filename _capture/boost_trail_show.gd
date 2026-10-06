extends SceneTree
## 부스터 리본 꼬리(BoostRibbon) 확인 캡처 + 수치 검사 (화면 있음).
## powershell -File tools\godot.ps1 wait --fixed-fps 60 -s res://_capture/boost_trail_show.gd [-- --exhaust=off]
## → output/boost-trail-20261006/

var out := "res://output/boost-trail-20261006"
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


func _shot(name: String, tm: TrainingMain = null, zoom := false) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	if zoom and tm:
		var c := tm.camera.unproject_position(tm.player.global_position)
		var r := Rect2i(int(c.x) - 330, int(c.y) - 230, 660, 460).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		var z := img.get_region(r)
		z.resize(r.size.x * 2, r.size.y * 2, Image.INTERPOLATE_NEAREST)
		z.save_png(out.path_join(name + "_zoom.png"))
	print("saved ", name)


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
		ff.sets.clear()
	var p := tm.player
	p.infinite_boost = false
	var start := tm.center + Vector3(-8, 0, 2)
	p.global_position = start
	tm.camera.snap(p.global_position)
	await _frames(60)
	Input.action_press("move_right")
	await _frames(40)
	_check(p.ribbons.is_empty() or p.ribbons[0].count() == 0, "부스터 없이 걸으면 리본 없음")
	Input.action_release("move_right")
	await _frames(30)
	p.global_position = start
	Input.action_press("boost")
	Input.action_press("move_right")
	await _frames(14)
	await _shot("01_boost_start", tm, true)
	await _frames(24)
	var rb: BoostRibbon = p.ribbons[0]
	_check(p.ribbons.size() == 2 and p.ribbons[1].count() >= 4, "분사구 두 개 = 연기 두 줄")
	var jet: Node3D = p.j.jet_l
	_check(rb._pts[0][0].distance_to(jet.global_position) < 0.12, "머리가 분사구에 붙어 있음 (%.3f m)" % rb._pts[0][0].distance_to(jet.global_position))
	_check(rb != null and rb.count() >= 4, "부스터로 달리면 리본이 이어짐 (점 %d)" % (rb.count() if rb else 0))
	var behind := 0
	for it in rb._pts:
		if (it[0] as Vector3).x < p.global_position.x - 0.2:
			behind += 1
	_check(behind >= rb.count() - 2, "리본은 등 뒤로 끌림 (%d/%d)" % [behind, rb.count()])
	await _shot("02_boost_run", tm, true)
	Input.action_release("move_right")
	Input.action_press("move_up")
	await _frames(20)
	await _shot("03_boost_turn", tm, true)
	Input.action_press("move_left")
	await _frames(16)
	await _shot("04_boost_curve", tm, true)
	Input.action_release("move_left")
	Input.action_release("move_up")
	Input.action_release("boost")
	await _frames(12)
	await _shot("05_boost_off", tm, true)
	await _frames(40)
	_check(rb.count() == 0, "끄면 꼬리부터 끊겨 0.3초 안에 사라짐 (%d)" % rb.count())
	print("FAILS ", fails)
	quit(1 if fails > 0 else 0)
