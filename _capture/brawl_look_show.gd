extends SceneTree
## 브롤스타즈 식 화면(BrawlLook) 비교 캡처: 같은 장면을 켜고/끄고 찍는다.
##  - 방 탐색 시작 방에 드론·포탑·크롤러·허수아비를 세워 멈춘 채 (적은 정지, 플레이어 무적)
##  - brawl_on.png / brawl_off.png / brawl_pair.png(좌 끔 · 우 켬) + 가까이 본 brawl_close.png
## powershell -File tools\godot.ps1 wait --resolution 1280x720 -s res://_capture/brawl_look_show.gd
const OUT := "res://output/brawl-look-20261004/"


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> Image:
	await _frames(4)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(OUT + name)
	return img


func _run() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(20)
	var main := current_scene as Main
	main.player.invuln = 9999.0
	var c := main.player.global_position
	var spots := [Vector3(-3.2, 0, -2.4), Vector3(3.0, 0, -2.8), Vector3(-2.6, 0, 2.2), Vector3(3.4, 0, 1.8)]
	var kinds := [Enemy, Turret, Crawler, TrainingDummy]
	var made: Array[Node3D] = []
	for i in spots.size():
		var e: Enemy = kinds[i].new()
		if e is TrainingDummy:
			(e as TrainingDummy).anchor = main.map.push_out(c + spots[i], 1.0)
		main.world.add_child(e)
		e.global_position = main.map.push_out(c + spots[i], 1.0)
		made.append(e)
	await _frames(30)
	for e in made:
		e.process_mode = Node.PROCESS_MODE_DISABLED
	main.player.aim_point = c + Vector3(3, 0, -2)
	# 같은 구도로 끔 → 켬
	BrawlLook.set_on(false, true)
	main.camera.snap(c)
	await _frames(40)
	var off := await _shot("brawl_off.png")
	BrawlLook.set_on(true, true)
	main.camera.snap(c)
	await _frames(40)
	var on := await _shot("brawl_on.png")
	var w := off.get_width()
	var h := off.get_height()
	var pair := Image.create(w, h / 2, false, Image.FORMAT_RGBA8)
	var a := off.duplicate() as Image
	var b := on.duplicate() as Image
	a.resize(w / 2, h / 2)
	b.resize(w / 2, h / 2)
	a.convert(Image.FORMAT_RGBA8)
	b.convert(Image.FORMAT_RGBA8)
	pair.blit_rect(a, Rect2i(0, 0, w / 2, h / 2), Vector2i.ZERO)
	pair.blit_rect(b, Rect2i(0, 0, w / 2, h / 2), Vector2i(w / 2, 0))
	pair.save_png(OUT + "brawl_pair.png")
	# 가까이 (줌인)
	var cp: Dictionary = main.camera.p.duplicate()
	cp.offset = (cp.offset as Vector3) * 0.5
	main.camera.p = cp
	main.camera.cur_offset = cp.offset
	await _frames(10)
	await _shot("brawl_close.png")
	print("BRAWL SHOW saved")
	quit()
