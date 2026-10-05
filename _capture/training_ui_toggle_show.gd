extends SceneTree
## 허수아비 시험장 F1(설명 숨김) · F2(UI 전체 숨김) 확인 캡처. 결과: <폴더>/normal.png · f1.png · f2.png
## 실행: powershell -File tools\godot.ps1 wait --resolution 1280x800 -s res://_capture/training_ui_toggle_show.gd -- --out=<폴더>

func _initialize() -> void:
	_run.call_deferred()


func _shot(path: String) -> void:
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)


func _run() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var m: TrainingMain = load("res://scenes/training.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	for i in 150:
		await physics_frame
	await _shot(out + "/normal.png")
	m.show_help = false
	await _shot(out + "/f1.png")
	m.show_help = true
	Main.ui_hidden = true
	await _shot(out + "/f2.png")
	quit()
