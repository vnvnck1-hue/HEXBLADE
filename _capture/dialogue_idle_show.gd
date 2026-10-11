extends SceneTree
## Forward+ 실제 셰이더 픽셀 변화/정지 검증과 전체 캐스트 및 대화 씬 움직임 캡처.
const OUT := "res://output/portrait-blink-20261011/idle/"
const IDS := ["owner", "worker", "partner"]
var gallery: Control
var portraits: Array[DialoguePortrait] = []
var starts: Array[Vector2] = []
var fails := 0
var checks: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	checks.append({"pass": ok, "message": message})
	fails += int(not ok)

func _label(parent: Node, text: String, pos: Vector2, font_size := 20) -> void:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)

func _step_gallery(dt: float, lock_body := false) -> void:
	for i in portraits.size():
		var p := portraits[i]
		p._process(dt)
		p.size = Vector2(274, 274)
		p.pivot_offset = p.size * Vector2(0.5, 1.0)
		p.position = starts[i] + (Vector2.ZERO if lock_body else p.idle_motion.body_offset)
		p.scale = Vector2.ONE if lock_body else p.idle_motion.body_scale
		p.rotation = 0.0 if lock_body else p.idle_motion.body_roll
		p.modulate = Color.WHITE
		p._update_idle_images()

func _render() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _diff(a: Image, b: Image, rect: Rect2i) -> int:
	var changes := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			changes += int(absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.035)
	return changes

func _seek(main: DialogueMain, cond: Callable) -> bool:
	for step in 160:
		if cond.call():
			return true
		if main.runner.done or main.runner.waiting_choice:
			return false
		main.view.wait_left = -1.0
		main.view._complete()
		main.runner.advance()
	return false

func _capture_scene(script: String, prefix: String, speaker: String) -> void:
	var main: DialogueMain = load("res://scenes/dialogue.tscn").instantiate()
	main.initial_script = script
	root.add_child(main)
	_check(_seek(main, func(): return main.view.line.get("who") == speaker), prefix + " 원하는 실제 대사 표시")
	main.view._complete()
	main.set_process(false)
	main.view.set_process(false)
	for p in main.view.people.get_children():
		p.set_process(false)
	for i in 90:
		for p in main.view.people.get_children():
			p._process(1.0 / 60.0)
	for frame in 64:
		for step in 4:
			for p in main.view.people.get_children():
				p._process(1.0 / 60.0)
		var image := await _render()
		image.save_png(OUT + "frames/%s_%03d.png" % [prefix, frame])
		if frame == 20:
			image.save_png(OUT + prefix + ".png")
	main.queue_free()
	await process_frame

func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.content_scale_size = Vector2i(1280, 800)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "frames"))
	gallery = Control.new()
	root.add_child(gallery)
	var bg := ColorRect.new()
	bg.color = Color("22232e")
	bg.size = Vector2(1280, 800)
	gallery.add_child(bg)
	_label(gallery, "대화 포트레이트 · 아이들링 모션", Vector2(32, 18), 26)
	_label(gallery, "합체 컷인 머리/옷가지 셰이더 · 인물별 숨쉬기와 지연 움직임 · 남주 제외", Vector2(32, 59), 16)
	for i in IDS.size():
		var p := DialoguePortrait.new()
		var pos := Vector2(83 + i * 420, 240)
		starts.append(pos)
		p.setup(IDS[i], "left", "", Vector2(1280, 800))
		p.active = true
		p._alpha = 1.0
		p._light = 1.0
		gallery.add_child(p)
		p.set_process(false)
		portraits.append(p)
		_label(gallery, DialogueCast.info(IDS[i]).name, pos + Vector2(10, -27), 20)
	_step_gallery(0.0, true)
	var before := await _render()
	before.save_png(OUT + "shader_before.png")
	for step in 90:
		_step_gallery(1.0 / 60.0, true)
	var after := await _render()
	after.save_png(OUT + "shader_after.png")
	for i in IDS.size():
		var pixels := _diff(before, after, Rect2i(starts[i], Vector2i(274, 274)))
		_check(pixels > 80, IDS[i] + " 몸을 고정해도 셰이더 머리/옷이 실제로 움직임: %d pixels" % pixels)
	DialogueView.reduce_motion = true
	for step in 30:
		_step_gallery(1.0 / 60.0, true)
	before = await _render()
	for step in 90:
		_step_gallery(1.0 / 60.0, true)
	after = await _render()
	_check(_diff(before, after, Rect2i(0, 100, 1280, 680)) == 0, "움직임 줄이기: 실제 렌더 픽셀도 정지")
	DialogueView.reduce_motion = false
	for step in 60:
		_step_gallery(1.0 / 60.0)
	for frame in 80:
		for step in 4:
			_step_gallery(1.0 / 60.0)
		var image := await _render()
		image.save_png(OUT + "frames/gallery_%03d.png" % frame)
		if frame == 20:
			image.save_png(OUT + "gallery.png")
	for variant in 3:
		for i in IDS.size():
			var expressions: Array = DialogueCast.CAST[IDS[i]].expr.keys()
			portraits[i].set_expr(expressions[mini(variant, expressions.size() - 1)], false)
		_step_gallery(1.0 / 60.0)
		var image := await _render()
		image.save_png(OUT + "expressions_%02d.png" % variant)
	for i in IDS.size():
		var tex := portraits[i].current_image.texture
		DialogueIdleMotion.mask_for(IDS[i], tex).get_image().save_png(OUT + IDS[i] + "_mask.png")
	gallery.queue_free()
	await process_frame
	await _capture_scene("coworker_introduction", "mechanic", "worker")
	await _capture_scene("field_partner_introduction", "partner", "me")
	var file := FileAccess.open(OUT + "render_checks.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "fails": fails}, "\t"))
	file.close()
	print("RESULT dialogue_idle_render: %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
