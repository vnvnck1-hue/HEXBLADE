extends SceneTree
## 사체 표시 프리셋(MessLook) 4종을 허수아비 씬에서 같은 샘플로 찍고 검사한다 → output/mess-look-20261011/
## powershell -File tools\godot.ps1 wait --resolution 1280x800 -s res://_capture/mess_look_show.gd -- --drone=off
const OUT := "res://output/mess-look-20261011/"

var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	change_scene_to_file("res://scenes/training.tscn")
	for i in 90:
		await process_frame
	var m: TrainingMain = current_scene as TrainingMain
	m.show_help = false
	m.player.aim_dir = Vector3(0, 0, -1)
	var shots: Array[Image] = []
	for p in MessLook.IDS.size():
		for n in root.get_tree().get_nodes_in_group(DroneMess.GROUP):
			n.remove_from_group(DroneMess.GROUP)
			n.queue_free()
		await process_frame
		MessLook.set_preset(self, p)
		m.scatter_mess()
		for i in 45:
			await process_frame
		var messes := root.get_tree().get_nodes_in_group(DroneMess.GROUP)
		_check(messes.size() == 6, "%s: 샘플 6개 (%d)" % [MessLook.IDS[p], messes.size()])
		var looks := MessLook.count(self)
		_check(looks == (0 if p == MessLook.BASE else 6), "%s: 표시 붙은 사체 %d" % [MessLook.IDS[p], looks])
		if p == MessLook.OUTLINE:
			var l := (messes[0] as Node).get_node("MessLook") as MessLook
			_check(l.hulls.size() >= 4, "outline: 조각마다 외곽선 (%d)" % l.hulls.size())
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.save_png(OUT + "%d_%s.png" % [p, MessLook.IDS[p]])
		shots.append(img)
	# 프리셋을 바꾸면 이미 있는 사체의 표시가 바뀌고, 기본으로 돌리면 외곽선 복사본까지 다 사라진다
	MessLook.set_preset(self, MessLook.OUTLINE)
	await process_frame
	await process_frame
	MessLook.set_preset(self, MessLook.BASE)
	await process_frame
	var left := 0
	for n in root.get_tree().get_nodes_in_group(DroneMess.GROUP):
		for c in (n as Node).find_children("*", "MeshInstance3D", true, false):
			if c.has_meta("mess_look") and not c.is_queued_for_deletion():
				left += 1
	_check(left == 0 and MessLook.count(self) == 0, "BASE 로 되돌리면 표시 · 외곽선 복사본 0 (%d)" % left)
	# 청소: 다 치우면 표시가 숨는다
	MessLook.set_preset(self, MessLook.RING)
	await process_frame
	await process_frame
	var dm := root.get_tree().get_nodes_in_group(DroneMess.GROUP)[0] as DroneMess
	dm.clean(99.0, dm.global_position)
	await process_frame
	var l2 := dm.get_node_or_null("MessLook") as MessLook
	var hidden := l2 == null or l2.geoms.all(func(g): return not is_instance_valid(g) or not g.visible)
	_check(hidden, "다 치우면 표시가 숨음")
	# 2×2 시트 (가운데 부분만 잘라 붙인다)
	var w := shots[0].get_width()
	var h := shots[0].get_height()
	var cw := int(w * 0.62)
	var ch := int(h * 0.62)
	var sheet := Image.create(cw * 2, ch * 2, false, shots[0].get_format())
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i((w - cw) / 2, int(h * 0.12), cw, ch), Vector2i((i % 2) * cw, (i / 2) * ch))
	sheet.save_png(OUT + "sheet.png")
	print("FAILS %d" % fails)
	MessLook.preset = MessLook.BASE
	quit(1 if fails > 0 else 0)
