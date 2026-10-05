extends SceneTree
const OUT := "res://output/drone-support-ui-20261004/"
var before := false

func _initialize() -> void:
	before = OS.get_cmdline_user_args().has("--before")
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _shot(name_: String) -> Image:
	await _frames(4)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(OUT + name_ + ".png")
	return img

func _hash(img: Image, rect: Rect2) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(img.get_region(Rect2i(rect.position.floor(), rect.size.ceil())).get_data())
	return context.finish().hex_encode()

func _run() -> void:
	HudPresets.current = HudPresets.STRIKER
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(100)
	var m := current_scene as Main
	var p := m.player
	var d := PartnerDrone.inst
	p.process_mode = Node.PROCESS_MODE_DISABLED
	d.process_mode = Node.PROCESS_MODE_DISABLED
	d.state = PartnerDrone.St.FOLLOW
	d.gauge = 0
	d.cleaned = 0
	d.player_cleaned = 0
	d.p_cleaning = false
	d.auto_cleaning = false
	d.sweeping = false
	p.mag = 26
	p.missiles = 4
	p.energy = 3
	p.boost = 0.65
	p.dash_cd = 0
	m.combo = 0
	m.hud.hint.visible = false
	m.hud.center.visible = false
	m.hud.sub.visible = false
	m.hud.gain_label.modulate.a = 0
	for e in get_nodes_in_group("enemies"):
		e.process_mode = Node.PROCESS_MODE_DISABLED
	var layer := CanvasLayer.new()
	layer.layer = 9
	root.add_child(layer)
	var flat := ColorRect.new()
	flat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flat.color = Color(0.12, 0.11, 0.2)
	layer.add_child(flat)
	var suffix := "_before" if before else "_after"
	var ready := await _shot("skills_ready" + suffix)
	p.mag = 0
	p.reload_t = Player.RELOAD_TIME * 0.5
	p.energy = 0
	p.missiles = 0
	p.boost = 0.18
	p.overheated = true
	p.dash_cd = Player.DASH_CD * 0.65
	var blocked := await _shot("skills_blocked" + suffix)
	if not before:
		var results := {}
		var region := RoundSkillDock.dock_rect(m.hud.root.size)
		for state in ["ready", "blocked"]:
			var base := Image.load_from_file(ProjectSettings.globalize_path(OUT + "skills_" + state + "_before.png"))
			results[state] = _hash(base, region) == _hash(ready if state == "ready" else blocked, region)
			print("SKILL_PIXELS_%s %s" % [state, "PASS" if results[state] else "FAIL"])
		var file := FileAccess.open(OUT + "protected-pixels.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(results, "\t"))
	layer.queue_free()
	p.mag = 26
	p.reload_t = 0
	p.energy = 3
	p.missiles = 4
	p.boost = 0.65
	p.overheated = false
	p.dash_cd = 0
	await _shot("applied" + suffix)
	if not before:
		d.gauge = 100
		d.cleaned = 7
		d.player_cleaned = 3
		await _shot("support_ready")
		d.state = PartnerDrone.St.DOCKED
		d.gauge = 65
		await _shot("docked")
		d.state = PartnerDrone.St.FOLLOW
		d.gauge = 21
		d.sweeping = true
		d.p_cleaning = true
		await _shot("sweeping")
	print("DRONE_SUPPORT_UI_CAPTURE_OK")
	quit()
