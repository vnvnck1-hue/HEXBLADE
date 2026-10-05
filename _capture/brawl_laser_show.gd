extends SceneTree
## 강력 레이저(최대 충전 지속 레이저) 순간 비교: 발사 0.7초 뒤를 찍는다. 주변은 어둡고 빔 광원만 강조되어야 한다.
##  - 화면 평균 밝기 · 빔에서 먼 곳의 밝기를 출력, laser_<brawl|classic>.png 저장
## powershell -File tools\godot.ps1 wait --resolution 1280x720 -s res://_capture/brawl_laser_show.gd -- --seed=4 [--classic]
const OUT := "res://output/brawl-look-20261004/"


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _lum_rect(img: Image, r: Rect2i) -> float:
	var s := 0.0
	var n := 0
	for y in range(r.position.y, r.end.y, 4):
		for x in range(r.position.x, r.end.x, 4):
			var c := img.get_pixel(x, y)
			s += c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			n += 1
	return s / maxf(1, n)


func _run() -> void:
	var classic := OS.get_cmdline_user_args().has("--classic")
	if classic:
		BrawlLook.on = false
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(40)
	var main := current_scene as Main
	main.player.invuln = 9999.0
	main.hud.visible = false
	var c := main.player.global_position
	var e := Enemy.new()
	main.world.add_child(e)
	e.global_position = main.map.push_out(c + Vector3(-3.0, 0, 2.0), 1.0)
	await _frames(60)
	e.process_mode = Node.PROCESS_MODE_DISABLED
	var img0: Image
	await RenderingServer.frame_post_draw
	img0 = root.get_texture().get_image()
	var p := main.player
	p.aim_dir = Vector3(1, 0, -0.35).normalized()
	p.aim_point = c + p.aim_dir * 8.0
	p._start_mega()
	# 임팩트 프레임 · 히트스탑이 지나고 빔이 이어지는 중간
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 700:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var tag := "classic" if classic else "brawl"
	img.save_png(OUT + "laser_%s.png" % tag)
	img0.save_png(OUT + "laser_%s_before.png" % tag)
	var w := img.get_width()
	var h := img.get_height()
	# 빔은 화면 오른쪽 위로 나간다 → 왼쪽 아래 사분면 = 빔에서 먼 곳
	var far := Rect2i(0, h / 2, w / 3, h / 2)
	print("LASER %s  before: all=%.3f far=%.3f   during: all=%.3f far=%.3f" % [tag,
		_lum_rect(img0, Rect2i(0, 0, w, h)), _lum_rect(img0, far),
		_lum_rect(img, Rect2i(0, 0, w, h)), _lum_rect(img, far)])
	quit()
