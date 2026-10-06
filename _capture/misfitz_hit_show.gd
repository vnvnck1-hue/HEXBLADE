extends SceneTree
## MISFITZ 타격 VFX 프레임별 확인 (docs/misfitz-hit-vfx.md). 허수아비 씬에서 일반/강타를 한 번씩 때리고
## 매 프레임(1/60초) 맞은 자리를 잘라 시트로 묶는다. 레퍼런스 정점 A · 소멸 B 잘라 낸 것도 옆에 붙인다.
## powershell -File tools\godot.ps1 wait --fixed-fps 60 --resolution 1280x800 -s res://_capture/misfitz_hit_show.gd -- [--hitfx=moco] [--ref=<레퍼런스 경로>]
const OUT := "res://output/misfitz-hit-20261006/"
const CROP := 160
const FRAMES := 20

var main: Main
var ref_path := ""


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _crop(img: Image, at: Vector2) -> Image:
	var x := clampi(int(at.x) - CROP / 2, 0, img.get_width() - CROP)
	var y := clampi(int(at.y) - CROP / 2, 0, img.get_height() - CROP)
	return img.get_region(Rect2i(x, y, CROP, CROP))


func _row(d: TrainingDummy, dmg: int, src: String, tag: String) -> Array:
	var hp := d.global_position + Vector3(-0.3, 1.0, 0.2)
	var cam := root.get_camera_3d()
	var out: Array = []
	d.take_hit(dmg, Vector3(1, 0, -0.2).normalized(), hp, src)
	for f in FRAMES:
		var img := await _grab()
		var scr := cam.unproject_position(hp)
		if f == 3:
			img.save_png(OUT + tag + "_full_f03.png")
		var c := _crop(img, scr)
		c.save_png(OUT + "frames/%s_f%02d.png" % [tag, f])
		out.append(c)
		await _frames(1)
	return out


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ref="):
			ref_path = a.substr(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "frames"))
	change_scene_to_file("res://scenes/training.tscn")
	await _frames(40)
	main = current_scene as Main
	main.player.invuln = 9999.0
	Main.ui_hidden = true
	if main.has_method("_apply_ui"):
		main.call("_apply_ui")
	var dummies: Array = get_nodes_in_group("enemies").filter(func(e): return e is TrainingDummy)
	dummies.sort_custom(func(a, b): return a.global_position.distance_to(main.player.global_position) < b.global_position.distance_to(main.player.global_position))
	var d: TrainingDummy = dummies[0]
	main.player.global_position = d.global_position + Vector3(-3.4, 0, 0.6)
	main.camera.snap(main.player.global_position)
	await _frames(60)
	var tag := MocoFX.style
	var rows_img: Array = []
	for spec: Array in [[1, "bullet", "bullet"], [3, "missile", "missile"], [3, "slash", "slash"]]:
		rows_img.append(await _row(d, spec[0], spec[1], tag + "_" + spec[2]))
		await _frames(40)
	# 시트: 레퍼런스(있으면) + 총(노랑) · 미사일(노랑 강타) · 검(보라 강타) 각 20프레임, 한 줄 10칸
	var cols := 10
	var refs: Array = []
	if ref_path != "":
		var r := Image.load_from_file(ref_path)
		if r:
			r.convert(Image.FORMAT_RGBA8)
			for box: Rect2i in [Rect2i(970, 55, 165, 150), Rect2i(1128, 55, 150, 150)]:
				var q := r.get_region(box)
				q.resize(CROP, CROP, Image.INTERPOLATE_NEAREST)
				refs.append(q)
	var y0 := CROP if refs.size() > 0 else 0
	var sheet := Image.create(cols * CROP, y0 + rows_img.size() * 2 * CROP, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.1, 0.1, 0.12))
	for i in refs.size():
		sheet.blit_rect(refs[i], Rect2i(0, 0, CROP, CROP), Vector2i(i * CROP, 0))
	for ri in rows_img.size():
		var fr: Array = rows_img[ri]
		for i in fr.size():
			sheet.blit_rect(fr[i], Rect2i(0, 0, CROP, CROP), Vector2i((i % cols) * CROP, y0 + ri * 2 * CROP + (i / cols) * CROP))
	sheet.save_png(OUT + "sheet_%s.png" % tag)
	print("MISFITZ_SHOW done style=", tag, " bursts_left=", MocoFX.get_inst().burst_count())
	quit(0)
