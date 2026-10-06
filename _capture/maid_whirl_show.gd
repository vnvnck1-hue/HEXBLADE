extends SceneTree
## 민트 메이드 Q 합체: 컷인(산뜻한 테마 · 느린 소품/별빛 · 얼굴 반짝이) → 휠윈드 소품 흩뿌리기 캡처
## Run: tools\godot.ps1 wait -s res://_capture/maid_whirl_show.gd
## 결과 output/maid-whirl-20261006/frames/ (git 제외) · 고른 장면은 같은 폴더

const OUT := "res://output/maid-whirl-20261006/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "frames"))
	root.size = Vector2i(1920, 800)
	PartnerDrone.cutin_style = "diagonal"
	var m: TrainingMain = load("res://scenes/training.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	for i in 30:
		await process_frame
	var d := PartnerDrone.inst
	while d.state != PartnerDrone.St.FOLLOW:
		await process_frame
	for i in 20:
		await process_frame
	var t0 := Time.get_ticks_msec()
	d.whirl_link()
	var n := 0
	var last := -1000
	while Time.get_ticks_msec() - t0 < 4200:
		await process_frame
		var ms := Time.get_ticks_msec() - t0
		if ms - last >= 70:
			last = ms
			var img := root.get_texture().get_image()
			img.save_png(OUT + "frames/f_%03d_%04dms.png" % [n, ms])
			n += 1
	print("frames ", n)
	quit()
