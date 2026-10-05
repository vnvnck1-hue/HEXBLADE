extends SceneTree
## 사선 DOCKING 합체 컷인 캡처: 허수아비 시험장에서 Q 합체(whirl_link)를 일으키고 매 프레임 저장한다.
## 실행: powershell -File tools\godot.ps1 wait --fixed-fps 60 --resolution 1280x800 -s res://_capture/diagonal_cutin_show.gd -- --out=<폴더> [--style=diagonal|cockpit] [--preview]
## 결과: <폴더>/f_0001.png … · log.txt (프레임 · 단계 · s · 기준점-하단선 거리 · 가슴 변위)

var out := ""
var style := "diagonal"
var preview := false
var lines: PackedStringArray = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--style="):
			style = a.substr(8)
		elif a == "--preview":
			preview = true
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _run() -> void:
	var lab: TrainingMain = load("res://scenes/training.tscn").instantiate()
	root.add_child(lab)
	current_scene = lab
	await physics_frame
	var d := PartnerDrone.inst
	for i in 240:
		await physics_frame
		if d.state == PartnerDrone.St.FOLLOW and i > 150:
			break
	PartnerDrone.cutin_style = style
	DiagonalDockingCutin.fixed_dt = 1.0 / 60.0
	CockpitCutin.fixed_dt = 1.0 / 60.0
	var c = null
	if preview:
		c = PartnerDrone.begin_cutin(lab, null, true)
	else:
		d.gauge = PartnerDrone.GAUGE_MAX
		d.whirl_link()
	var n := 0
	for i in 80:
		await process_frame
		n += 1
		if not preview:
			c = d.cutin
		var info := "none"
		if is_instance_valid(c) and c is DiagonalDockingCutin:
			info = "ph=%d t=%.3f dock=%.3f s=%.1f clip_err=%.3f rot=%.3f scale=(%.3f,%.3f) slow=%.2f text_k=%.2f jigL=%s jigR=%s" % [c.ph, c.t, c.dock_t, c.s, c.max_clip_err, c.anchor.rotation, c.anchor.scale.x, c.anchor.scale.y, Engine.time_scale, c.text_k(), c.jig[0], c.jig[1]]
		lines.append("%04d state=%d %s" % [n, d.state, info])
		root.get_viewport().get_texture().get_image().save_png("%s/f_%04d.png" % [out, n])
	var f := FileAccess.open(out + "/log.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	quit()
