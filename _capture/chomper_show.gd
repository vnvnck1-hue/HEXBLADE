extends SceneTree
## 촘퍼 애니메이션 근접 캡처: BugLab.CHOMP_CLIPS 를 차례로 재생하며 프레임을 저장한다 (체액 방울·웅덩이 포함).
## 실행: powershell -File tools\godot.ps1 wait --fixed-fps 30 -s res://_capture/chomper_show.gd -- --out=<폴더> [--every=3] [--view=side|front|three|back] [--clip=N]
## 결과: <폴더>/f_0001.png … · clips.txt (프레임 번호 · 클립 이름 · 시각)

var out := ""
var every := 3
var view := "three"
var only_clip := -1
var rig: ChomperRig
var pose: Node3D
var model: Node3D
var cam: Camera3D
var t := 0.0
var clip := 0
var frame := 0
var log_lines: PackedStringArray = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--every="):
			every = int(a.substr(8))
		elif a.begins_with("--view="):
			view = a.substr(7)
		elif a.begins_with("--clip="):
			only_clip = int(a.substr(7))
	DirAccess.make_dir_recursive_absolute(out)
	var world := Node3D.new()
	root.add_child(world)
	FX.setup(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("595d66")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.78, 0.78, 0.82)
	env.environment.ambient_light_energy = 0.75
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.35
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
	var root3 := Node3D.new()
	world.add_child(root3)
	FX.blob_shadow(root3, 1.3, 0.6)
	pose = Node3D.new()
	root3.add_child(pose)
	model = (load(BugChomper.MODEL) as PackedScene).instantiate() as Node3D
	pose.add_child(model)
	rig = ChomperRig.new().setup(model)
	cam = Camera3D.new()
	cam.fov = 30
	world.add_child(cam)
	var target := Vector3(0, 0.32, 0)
	var zoom := 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--zoom="):
			zoom = float(a.substr(7))
	match view:
		"side":
			cam.position = Vector3(-3.4, 0.9, 0.0)
		"front":
			cam.position = Vector3(0.0, 0.9, -3.4)
		"back":
			cam.position = Vector3(0.4, 1.1, 3.3)
		_:
			cam.position = Vector3(-2.3, 1.35, -2.5)
	cam.position = target + (cam.position - target) / zoom
	cam.look_at_from_position(cam.position, target)
	if only_clip >= 0:
		clip = only_clip


func _process(dt: float) -> bool:
	t += dt
	var clips: Array = BugLab.CHOMP_CLIPS
	var dur: float = clips[clip][1]
	if t >= dur:
		t = 0.0
		clip += 1
		if clip >= clips.size() or only_clip >= 0:
			FileAccess.open(out + "/clips.txt", FileAccess.WRITE).store_string("\n".join(log_lines))
			quit()
			return true
		dur = clips[clip][1]
	BugLab.chomp_clip(rig, pose, model, clip, t, t / dur, dt, 0.0)
	rig.update(dt)
	frame += 1
	if frame % every == 0:
		var img := root.get_texture().get_image()
		var n := frame / every
		img.save_png("%s/f_%04d.png" % [out, n])
		log_lines.append("%d %d %s %.2f" % [n, clip, clips[clip][0], t])
	return false
