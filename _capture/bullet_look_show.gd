extends SceneTree
## 허수아비 씬: G 기본 적 자동 소환 + 적 투사체 표시 프리셋(BulletLook) 4종 캡처·검사 → output/bullet-look-20261011/
## powershell -File tools\godot.ps1 wait --resolution 1280x800 -s res://_capture/bullet_look_show.gd -- --drone=off
const OUT := "res://output/bullet-look-20261011/"

var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _bullets() -> Array:
	return root.get_tree().get_nodes_in_group(BulletLook.GROUP).filter(func(b): return is_instance_valid(b) and not b.is_queued_for_deletion())


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	change_scene_to_file("res://scenes/training.tscn")
	for i in 60:
		await process_frame
	var m: TrainingMain = current_scene as TrainingMain
	m.show_help = false
	m._set_auto(true)
	var t0 := Time.get_ticks_msec()
	while m._auto_alive() < 3 and Time.get_ticks_msec() - t0 < 12000:
		await process_frame
	_check(m._auto_alive() >= 3, "자동 소환: 적 %d기 (상한 %d)" % [m._auto_alive(), TrainingMain.AUTO_MAX])
	for i in 240:
		await process_frame
	_check(m._auto_alive() <= TrainingMain.AUTO_MAX, "자동 소환 상한 지킴 (%d)" % m._auto_alive())
	var shots: Array[Image] = []
	for p in BulletLook.IDS.size():
		BulletLook.set_preset(self, p)
		# 탄이 여럿 날고 있는 순간을 기다린다
		t0 = Time.get_ticks_msec()
		for i in 30:
			await process_frame
		while _bullets().size() < 4 and Time.get_ticks_msec() - t0 < 8000:
			await process_frame
		var bs := _bullets()
		var looks := BulletLook.count(self)
		_check(bs.size() > 0, "%s: 적 탄 %d개" % [BulletLook.IDS[p], bs.size()])
		_check(looks == (0 if p == BulletLook.BASE else bs.size()), "%s: 표시 붙은 탄 %d/%d" % [BulletLook.IDS[p], looks, bs.size()])
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.save_png(OUT + "%d_%s.png" % [p, BulletLook.IDS[p]])
		shots.append(img)
	BulletLook.set_preset(self, BulletLook.BASE)
	m._set_auto(false)
	await process_frame
	await process_frame
	var left := 0
	for e in root.get_tree().get_nodes_in_group("enemies"):
		if e is Enemy and not (e is TrainingDummy) and not e.get("prop") and not e.is_boss and not e.is_queued_for_deletion():
			print("  남은 적: ", e.get_script().resource_path, " alive=", e.alive, " auto=", m.auto_foes.has(e))
			left += 1
	_check(left == 0, "G 끄면 자동 소환 적 물러남 (남은 %d)" % left)
	var w := shots[0].get_width()
	var h := shots[0].get_height()
	var sheet := Image.create(w, h, false, shots[0].get_format())
	for i in shots.size():
		var half := shots[i].duplicate() as Image
		half.resize(w / 2, h / 2, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(half, Rect2i(0, 0, w / 2, h / 2), Vector2i((i % 2) * (w / 2), (i / 2) * (h / 2)))
	sheet.save_png(OUT + "sheet.png")
	print("FAILS %d" % fails)
	quit(1 if fails > 0 else 0)
