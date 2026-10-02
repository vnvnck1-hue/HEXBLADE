extends SceneTree
## 벌레 모델 애니메이션 근접 캡처: 개미 병정 · 공벌레를 BugLab 전시 모드와 같은 클립으로 움직이며 프레임을 저장한다.
## 실행: powershell -File tools\godot.ps1 wait --fixed-fps 30 -s res://_capture/bug_show.gd -- --out=<폴더> [--kind=ant|pill] [--every=6] [--view=side|top|front]
## 결과: <폴더>/f_0001.png … (BugLab 의 클립 순서 · 클립 이름은 out 폴더의 clips.txt)

var out := ""
var kind := "ant"
var every := 6
var view := "side"
var rig_a: AntRig
var rig_p: PillRig
var pose: Node3D
var cam: Camera3D
var t := 0.0
var clip := 0
var frame := 0
var log_lines: PackedStringArray = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--kind="):
			kind = a.substr(7)
		elif a.begins_with("--every="):
			every = int(a.substr(8))
		elif a.begins_with("--view="):
			view = a.substr(7)
	DirAccess.make_dir_recursive_absolute(out)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("595d66")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.environment.ambient_light_energy = 0.7
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("3a3d45")
	floor_mi.material_override = fm
	world.add_child(floor_mi)
	pose = Node3D.new()
	world.add_child(pose)
	if kind == "ant":
		var m := (load(BugAnt.MODEL) as PackedScene).instantiate() as Node3D
		pose.add_child(m)
		rig_a = AntRig.new().setup(m)
	else:
		var roller := Node3D.new()
		pose.add_child(roller)
		var m := (load(BugPill.MODEL) as PackedScene).instantiate() as Node3D
		roller.add_child(m)
		rig_p = PillRig.new().setup(m, roller)
	cam = Camera3D.new()
	cam.fov = 34
	world.add_child(cam)
	var target := Vector3(0, 0.75 if kind == "ant" else 0.4, 0)
	match view:
		"side":
			cam.position = Vector3(-4.6, 1.5, -1.6)
		"front":
			cam.position = Vector3(-1.2, 1.4, -4.8)
		"top":
			cam.position = Vector3(-2.6, 5.5, 2.8)
	if kind == "pill":
		cam.position *= 0.95
	cam.look_at_from_position(cam.position, target)


func _process(dt: float) -> bool:
	t += dt
	var clips: Array = BugLab.ANT_CLIPS if kind == "ant" else BugLab.PILL_CLIPS
	var dur: float = clips[clip][1]
	if t >= dur:
		t = 0.0
		clip += 1
		if clip >= clips.size():
			FileAccess.open(out + "/clips.txt", FileAccess.WRITE).store_string("\n".join(log_lines))
			quit()
			return true
		dur = clips[clip][1]
	var k := t / dur
	if kind == "ant":
		BugLab.ant_clip(rig_a, pose, clip, t, k, dur)
		rig_a.update(dt)
	else:
		BugLab.pill_clip(rig_p, pose, clip, t, k, dt)
		rig_p.update(dt)
	frame += 1
	if frame % every == 0:
		var img := root.get_texture().get_image()
		var n := frame / every
		img.save_png("%s/f_%04d.png" % [out, n])
		log_lines.append("%d %s %.2f" % [n, clips[clip][0], t])
	return false
