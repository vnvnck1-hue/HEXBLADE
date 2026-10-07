extends SceneTree
## LANCASTER 첫 등장 연출 캡처: 보스방 입구에서 들어가 연출 전체를 일정 간격으로 찍고 시트로 묶는다.
## powershell -File tools\godot.ps1 wait --fixed-fps 60 -s res://_capture/lancaster_intro_show.gd -- --out=DIR [--every=12]

var out := "res://output/lancaster-intro-20261007"
var every := 12
var main: TrainingMain
var room: TrainingBossRoom
var shots: Array[Image] = []
var labels: Array[String] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--every="):
			every = int(a.substr(8))
	DirAccess.make_dir_recursive_absolute(out.path_join("frames"))
	for f in DirAccess.get_files_at(out.path_join("frames")):
		DirAccess.remove_absolute(out.path_join("frames").path_join(f))
	_run.call_deferred()


func _frames(k: int) -> void:
	for i in k:
		await physics_frame


func _grab(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var n := shots.size()
	img.save_png(out.path_join("frames/%03d_%s.png" % [n, tag]))
	var s := img.duplicate() as Image
	s.resize(img.get_width() / 4, img.get_height() / 4, Image.INTERPOLATE_BILINEAR)
	shots.append(s)
	labels.append(tag)


func _run() -> void:
	main = (load("res://scenes/training.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(20)
	main.god = true
	room = main.boss_room
	var p := main.player
	p.global_position = room.door + Vector3(4.0, 0, 0)
	main.camera.snap(p.global_position)
	await _frames(30)
	await _grab("before")
	p.global_position = room.door + Vector3(-1.0, 0, 0)
	var boss := room.boss
	var f := 0
	while (boss.st == LancasterBoss.St.INTRO or is_instance_valid(room.intro) or f < 10) and f < 60 * 25:
		await physics_frame
		f += 1
		if f % every == 0:
			await _grab("%s_%d" % [boss.ip if boss.st == LancasterBoss.St.INTRO else "end", f])
	await _frames(30)
	await _grab("fight")
	_sheet()
	quit()


func _sheet() -> void:
	if shots.is_empty():
		return
	var w := shots[0].get_width()
	var h := shots[0].get_height()
	var cols := 6
	var rows := ceili(shots.size() / float(cols))
	var sheet := Image.create(w * cols, h * rows, false, shots[0].get_format())
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	sheet.save_png(out.path_join("sheet.png"))
	print("sheet ", shots.size(), " ", labels)
