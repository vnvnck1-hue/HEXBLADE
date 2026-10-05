extends SceneTree
## 적 피격 반응 5종 확인 시트: 시험장에 드론 다섯(또는 --kind=striker|crawler)을 한 줄로 세우고
## 왼쪽부터 젖힘 · 비틀림 · 숙임 · 회전 · 띄움을 동시에 걸어 몇 프레임 간격으로 찍어 한 장으로 붙인다.
## godot --path . -s _capture/hit_react_show.gd -- --out=output/hit-react-20261004 [--kind=striker]

var out := "res://output/hit-react-20261004"
var kind := "drone"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--kind="):
			kind = a.substr(7)
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	var m: GimmickLab = load("res://scenes/gimmicks.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	await _frames(4)
	m._drone_t = 9999.0
	for d in m.drones:
		d.queue_free()
	var p := m.player
	p.bot = false
	var c := p.global_position
	var foes: Array[Enemy] = []
	for i in 5:
		var e: Enemy
		match kind:
			"striker": e = Striker.new()
			"crawler": e = Crawler.new()
			_: e = Enemy.new()
		e.hp = 999
		e.orb_chance = 0.0
		m.world.add_child(e)
		e.global_position = m.push_out(c + Vector3(-5.0 + i * 2.5, 0, -1.2), 0.8)
		foes.append(e)
	await _frames(90)
	if kind == "crawler":
		# 거미 자세(약점 노출)에서만 맞으므로 변신을 기다린다
		for i in 600:
			await _frames(1)
			var ok := true
			for e in foes:
				ok = ok and not (e as Crawler).armored
			if ok:
				break
	# HUD 를 모두 숨긴다 (기체가 가리지 않게)
	for n in m.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	var sheet_frames := [0, 3, 6, 10, 15, 21, 28]
	var shots: Array[Image] = []
	for e in foes:
		e.fire_timer = 9.0
	for f in 30:
		if f == 0:
			for i in 5:
				foes[i].force_react = i
				var d := foes[i].global_position - p.global_position
				d.y = 0
				foes[i].take_hit(1, d.normalized(), foes[i].global_position + Vector3(0.3, 1.0, 0.2), "slash")
		await process_frame
		await physics_frame
		if f in sheet_frames:
			# 다섯 기체 둘레만 잘라 낸다
			var cam := root.get_viewport().get_camera_3d()
			var r := Rect2()
			for i in 5:
				var sp := cam.unproject_position(foes[i].global_position + Vector3(0, 0.9, 0))
				r = Rect2(sp, Vector2.ZERO) if i == 0 else r.expand(sp)
			r = r.grow_individual(90, 130, 90, 70)
			var img := root.get_texture().get_image()
			r = r.intersection(Rect2(Vector2.ZERO, Vector2(img.get_size())))
			shots.append(img.get_region(Rect2i(r)))
	var w := shots[0].get_width()
	var h := shots[0].get_height()
	for i in shots.size():
		if shots[i].get_size() != Vector2i(w, h):
			shots[i].resize(w, h)
	var sheet := Image.create(w, h * shots.size(), false, shots[0].get_format())
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(0, 0, w, h), Vector2i(0, h * i))
	sheet.save_png(out.path_join("sheet_%s.png" % kind))
	print("SAVED ", out.path_join("sheet_%s.png" % kind))
	quit()
