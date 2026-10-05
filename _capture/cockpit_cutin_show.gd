extends SceneTree
## 조종석 합체 컷인 캡처: 드론 시험장에서 Q 합체(whirl_link)를 일으키고 매 프레임 저장한다.
## 실행: powershell -File tools\godot.ps1 wait --fixed-fps 60 --resolution 1280x800 -s res://_capture/cockpit_cutin_show.gd -- --out=<폴더> [--gauge=100]
## 결과: <폴더>/f_0001.png … · log.txt (프레임 · 컷인 단계 · 가슴 변위)

var out := ""
var gauge := 100.0
var lines: PackedStringArray = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--gauge="):
			gauge = float(a.substr(8))
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _run() -> void:
	var lab: DroneLab = load("res://scenes/drone.tscn").instantiate()
	lab.spawning = false
	root.add_child(lab)
	current_scene = lab
	await physics_frame
	lab.spawning = false
	var d := PartnerDrone.inst
	for i in 200:
		await physics_frame
		if d.state == PartnerDrone.St.FOLLOW and i > 120:
			break
	d.gauge = gauge
	PartnerDrone.cutin_style = "cockpit"
	CockpitCutin.fixed_dt = 1.0 / 60.0
	d.whirl_link()
	var n := 0
	for i in 70:
		await process_frame
		n += 1
		var c = d.cutin
		var info := "none"
		if is_instance_valid(c):
			info = "ph=%d t=%.3f dock=%.3f jigL=%s jigR=%s" % [c.ph, c.t, c.dock_t, c.jig[0], c.jig[1]]
		lines.append("%04d state=%d %s" % [n, d.state, info])
		root.get_viewport().get_texture().get_image().save_png("%s/f_%04d.png" % [out, n])
	var f := FileAccess.open(out + "/log.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	quit()
