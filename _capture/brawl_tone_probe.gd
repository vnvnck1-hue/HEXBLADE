extends SceneTree
## 배경·캐릭터 톤 분리 측정: 같은 화면을 캐릭터(플레이어·적) 켜고/끄고 찍어, 달라진 픽셀 = 캐릭터, 나머지 = 배경.
## 각 평균 밝기·채도와 비(캐릭터/배경)를 출력하고 tone_<tag>.png 저장.
## powershell -File tools\godot.ps1 wait --resolution 1280x720 -s res://_capture/brawl_tone_probe.gd -- --seed=4 [--classic] [--tag=이름]
const OUT := "res://output/brawl-look-20261004/"


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _grab() -> Image:
	await _frames(6)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _run() -> void:
	var tag := "brawl"
	for a in OS.get_cmdline_user_args():
		if a == "--classic":
			BrawlLook.on = false
			tag = "classic"
		elif a.begins_with("--tag="):
			tag = a.substr(6)
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(40)
	var main := current_scene as Main
	main.player.invuln = 9999.0
	main.hud.visible = false
	var c := main.player.global_position
	var made: Array[Node3D] = []
	var spots := [Vector3(-3.2, 0, -1.6), Vector3(3.0, 0, -2.2), Vector3(-2.6, 0, 2.2), Vector3(3.2, 0, 1.8)]
	var kinds := [Crawler, Turret, TrainingDummy, Crawler]
	for i in spots.size():
		var e: Enemy = kinds[i].new()
		var pos: Vector3 = main.map.push_out(c + spots[i], 1.0)
		if e is TrainingDummy:
			(e as TrainingDummy).anchor = pos
		main.world.add_child(e)
		e.global_position = pos
		made.append(e)
	await _frames(90)
	for e in made:
		e.process_mode = Node.PROCESS_MODE_DISABLED
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.camera.snap(c)
	main.camera.global_position = main.camera.global_position   # (snap 은 이미 위치를 정함)
	var with := await _grab()
	var actors: Array[Node3D] = [main.player]
	actors.append_array(made)
	for n in actors:
		n.visible = false
	var without := await _grab()
	for n in actors:
		n.visible = true
	with.save_png(OUT + "tone_%s.png" % tag)
	var w := with.get_width()
	var h := with.get_height()
	var cl := 0.0
	var cs := 0.0
	var cn := 0
	var bl := 0.0
	var bs := 0.0
	var bn := 0
	for y in range(0, h, 2):
		for x in range(0, w * 4 / 5, 2):   # 오른쪽 위 미니맵 영역은 뺀다
			var a := with.get_pixel(x, y)
			var b := without.get_pixel(x, y)
			var diff := absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			var lum := a.r * 0.299 + a.g * 0.587 + a.b * 0.114
			var sat := a.s
			if diff > 0.12:
				cl += lum
				cs += sat
				cn += 1
			else:
				bl += lum
				bs += sat
				bn += 1
	cl /= maxf(1, cn)
	cs /= maxf(1, cn)
	bl /= maxf(1, bn)
	bs /= maxf(1, bn)
	print("TONE %s  char lum=%.3f sat=%.3f (%d px)  bg lum=%.3f sat=%.3f  ratio lum=%.2f sat=%.2f" % [tag, cl, cs, cn, bl, bs, cl / bl, cs / maxf(bs, 0.001)])
	quit()
