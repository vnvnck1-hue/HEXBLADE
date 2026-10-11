extends SceneTree
const OUT := "res://output/portrait-blink-20261011/"
var people: Array[DialoguePortrait] = []
var origins: Array[Vector2] = []
func _initialize() -> void:
	_run.call_deferred()
func _render() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func _gallery_step(dt: float) -> void:
	for i in people.size():
		var p := people[i]
		p._process(dt)
		p.size = Vector2(320, 320)
		p.pivot_offset = Vector2(160, 320)
		p.position = origins[i] + p.idle_motion.body_offset
		p.scale = p.idle_motion.body_scale
		p.modulate = Color.WHITE
		p._update_idle_images()
func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.content_scale_size = Vector2i(1280, 800)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "frames"))
	var gallery := Control.new()
	root.add_child(gallery)
	var bg := ColorRect.new()
	bg.size = Vector2(1280, 800)
	bg.color = Color("232631")
	gallery.add_child(bg)
	var title := Label.new()
	title.text = "대화 포트레이트 · 눈 깜빡임 6개 포즈"
	title.position = Vector2(36, 15)
	title.add_theme_font_size_override("font_size", 26)
	gallery.add_child(title)
	var ids := ["owner", "owner", "owner", "worker", "worker", "partner"]
	var poses := ["welcome", "briefing", "encouragement", "introduction", "cheerful", "greeting"]
	for i in ids.size():
		var p := DialoguePortrait.new()
		p.setup(ids[i], "left", poses[i], Vector2(1280, 800))
		gallery.add_child(p)
		p.set_process(false)
		people.append(p)
		origins.append(Vector2(52 + (i % 3) * 420, 95 + floori(float(i) / 3.0) * 355))
		p.blink.remaining = 1.0 + i * 0.25
		var label := Label.new()
		label.text = DialogueCast.info(ids[i]).name + " · " + poses[i]
		label.position = origins[i] + Vector2(0, -25)
		gallery.add_child(label)
	_gallery_step(0.0)
	(await _render()).save_png(OUT + "all_open.png")
	for p in people:
		p.blink.closed = true
		p.blink.remaining = 1.0
	_gallery_step(0.0)
	(await _render()).save_png(OUT + "all_closed.png")
	for i in people.size():
		people[i].blink.closed = false
		people[i].blink.remaining = 1.0 + i * 0.25
	for frame in 140:
		_gallery_step(0.05)
		(await _render()).save_png(OUT + "frames/blink_%03d.png" % frame)
	gallery.queue_free()
	await process_frame
	var main: DialogueMain = load("res://scenes/partner_dialogue.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	main.view.set_process(false)
	for step in 80:
		if main.view.line.get("who") == "partner":
			break
		main.view.wait_left = -1.0
		main.view._complete()
		main.runner.advance()
	main.view._complete()
	for p in main.view.people.get_children():
		p.set_process(false)
		for frame in 120:
			p._process(1.0 / 60.0)
		p.blink.closed = false
		p.blink.remaining = 10.0
		p._update_idle_images()
	(await _render()).save_png(OUT + "scene_open.png")
	for p in main.view.people.get_children():
		p.blink.closed = true
		p._update_idle_images()
	(await _render()).save_png(OUT + "scene_closed.png")
	print("RESULT dialogue_blink_capture PASS: 6 poses and actual dialogue open/closed")
	quit()
