extends SceneTree
## 참조 HUD 캡처와 우하단 보존 비교. --before는 변경 전 기준 이미지를 저장한다.
const OUT := "res://output/calm-ingame-ui-20261004/"
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

func _region_hash(img: Image, rect: Rect2) -> String:
	var region := img.get_region(Rect2i(rect.position.floor(), rect.size.ceil()))
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(region.get_data())
	return hash.finish().hex_encode()

func _run() -> void:
	HudPresets.current = HudPresets.STRIKER
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(100)
	var main := current_scene as Main
	var p := main.player
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.invuln = 9999.0
	p.mag = 26
	p.energy = 3
	p.boost = 0.65
	p.dash_cd = 0.0
	p.missiles = 4
	p.aim_point = p.global_position + Vector3(3, 0, -2)
	main.combo = 0
	main.hud.hint.visible = false
	main.hud.center.visible = false
	main.hud.sub.visible = false
	main.hud.gain_label.modulate.a = 0
	if PartnerDrone.inst:
		PartnerDrone.inst.process_mode = Node.PROCESS_MODE_DISABLED
		PartnerDrone.inst.gauge = 0
		PartnerDrone.inst.cleaned = 0
		PartnerDrone.inst.player_cleaned = 0
	for e in get_nodes_in_group("enemies"):
		e.process_mode = Node.PROCESS_MODE_DISABLED
	# 화면의 배경만 고정해 보호 영역을 픽셀 단위로 비교한다.
	var layer := CanvasLayer.new()
	layer.layer = 9
	root.add_child(layer)
	var flat := ColorRect.new()
	flat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flat.color = Color(0.12, 0.11, 0.2)
	layer.add_child(flat)
	var suffix := "_before" if before else "_after"
	var ready := await _shot("protected_ready" + suffix)
	p.mag = 0
	p.reload_t = Player.RELOAD_TIME * 0.5
	p.dash_cd = Player.DASH_CD * 0.65
	p.boost = 0.18
	p.overheated = true
	p.energy = 0
	p.missiles = 0
	var blocked := await _shot("protected_blocked" + suffix)
	if not before:
		var protected := [RoundSkillDock.dock_rect(main.hud.root.size), RoundSkillDock.support_rect(main.hud.root.size, Vector2(DroneHud.W, DroneHud.H))]
		var result := {}
		for state in ["ready", "blocked"]:
			var baseline := Image.load_from_file(ProjectSettings.globalize_path(OUT + "protected_" + state + "_before.png"))
			var actual := ready if state == "ready" else blocked
			for i in protected.size():
				var same := _region_hash(baseline, protected[i]) == _region_hash(actual, protected[i])
				result[state + ("_skills" if i == 0 else "_triad")] = same
				print("PROTECTED_%s_%d %s" % [state, i, "PASS" if same else "FAIL"])
		var file := FileAccess.open(OUT + "protected-pixels.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(result, "\t"))
	# 개발 배경에 일반 적을 세워 실제 바와 HUD를 확인한다.
	layer.queue_free()
	p.mag = 26
	p.reload_t = 0
	p.dash_cd = 0
	p.boost = 0.65
	p.overheated = false
	p.energy = 3
	p.missiles = 4
	var center := p.global_position
	for delta in [Vector3(-3, 0, -2), Vector3(3, 0, -3), Vector3(-2, 0, 3)]:
		var foe := Enemy.new()
		main.world.add_child(foe)
		foe.global_position = main.map.push_out(center + delta, 0.9)
		await _frames(50)
		foe.process_mode = Node.PROCESS_MODE_DISABLED
		foe.hp = maxi(1, int(foe.max_hp * 0.6))
		foe._bar_chip = 0.75
	await _shot("applied" + suffix)
	if not before:
		p.hp = 1
		p.boost = 0.1
		p.overheated = true
		p.energy = 1
		await _frames(90)
		await _shot("low_health")
		p.overheated = false
		main.combo = 12
		main.best_combo = 20
		main.combo_t = Main.COMBO_TIME * 0.75
		main.score = 3200
		main.hud.ult_on = true
		p.ult_aiming = true
		p.locks.assign(get_nodes_in_group("enemies").slice(0, 3))
		p.ult_ptr = main.camera.screen_pos(p.global_position + Vector3(3, 0, -3))
		p.ult_raw = p.ult_ptr
		await _shot("lock_combo")
	print("CALM_HUD_CAPTURE_OK")
	quit()
