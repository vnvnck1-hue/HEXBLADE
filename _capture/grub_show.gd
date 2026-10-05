extends SceneTree
## 애벌레 애니메이션 근접 캡처: BugLab.GRUB_CLIPS 를 차례로 재생하며 프레임을 저장한다 (점액 흔적 포함).
## 기는 클립은 실제로 앞(+X 쪽)으로 나아가고 카메라가 따라간다 — 바닥을 붙잡은 고리가 미끄러지지 않는지 보인다.
## 실행: powershell -File tools\godot.ps1 wait --fixed-fps 30 -s res://_capture/grub_show.gd -- --out=<폴더> [--every=3] [--view=side|three|top|front] [--clip=N] [--zoom=1.0]
## 결과: <폴더>/f_0001.png … · clips.txt (프레임 번호 · 클립 이름 · 시각)

var out := ""
var every := 3
var view := "three"
var only_clip := -1
var zoom := 1.0
var rig: GrubRig
var root3: Node3D
var pose: Node3D
var model: Node3D
var cam: Camera3D
var trail: SlimeTrail
var cam_off := Vector3.ZERO
var follow := Vector3.ZERO
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
		elif a.begins_with("--zoom="):
			zoom = float(a.substr(7))
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
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("3a3d45")
	fm.roughness = 0.8
	floor_mi.material_override = fm
	world.add_child(floor_mi)
	# 바닥 눈금 (미끄러짐 확인용 0.5m 간격 점)
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color("4c505a")
	var dot := BoxMesh.new()
	dot.size = Vector3(0.04, 0.004, 0.04)
	for ix in range(-12, 13):
		for iz in range(-6, 7):
			var d := MeshInstance3D.new()
			d.mesh = dot
			d.material_override = dm
			d.position = Vector3(ix * 0.5, 0.002, iz * 0.5)
			world.add_child(d)
	root3 = Node3D.new()
	world.add_child(root3)
	root3.rotation.y = -PI * 0.5            # 앞 = +X
	FX.blob_shadow(root3, 1.5, 0.55)
	pose = Node3D.new()
	root3.add_child(pose)
	model = (load(BugGrub.MODEL) as PackedScene).instantiate() as Node3D
	pose.add_child(model)
	rig = GrubRig.new().setup(model)
	trail = SlimeTrail.make(0.6)
	cam = Camera3D.new()
	cam.fov = 30
	world.add_child(cam)
	match view:
		"side":
			cam_off = Vector3(0.0, 0.9, 3.6)
		"front":
			cam_off = Vector3(3.6, 0.9, 0.0)
		"top":
			cam_off = Vector3(0.0, 5.2, 0.6)
		_:
			cam_off = Vector3(2.1, 1.6, 2.7)
	cam_off /= zoom
	if only_clip >= 0:
		clip = only_clip
	_reset_clip()


func _reset_clip() -> void:
	root3.position = Vector3(-1.2, 0, 0)
	root3.rotation.y = -PI * 0.5
	follow = root3.position


func _process(dt: float) -> bool:
	t += dt
	var clips: Array = BugLab.GRUB_CLIPS
	var dur: float = clips[clip][1]
	if t >= dur:
		t = 0.0
		clip += 1
		if clip >= clips.size() or only_clip >= 0:
			FileAccess.open(out + "/clips.txt", FileAccess.WRITE).store_string("\n".join(log_lines))
			quit()
			return true
		dur = clips[clip][1]
		_reset_clip()
	var go := BugLab.grub_clip(rig, pose, clip, t, t / dur, dt)
	root3.rotation.y += rig.turn * dt
	root3.position += -root3.global_basis.z * go * dt
	rig.update(dt)
	if clip <= 4:
		trail.feed(model.global_transform * rig.tail_local(), -root3.global_basis.z)
	follow = follow.lerp(root3.position, 1.0 - exp(-3.0 * dt))
	var target := follow + Vector3(0, 0.25, 0)
	cam.look_at_from_position(target + cam_off, target)
	frame += 1
	if frame % every == 0:
		var img := root.get_texture().get_image()
		var n := frame / every
		img.save_png("%s/f_%04d.png" % [out, n])
		log_lines.append("%d %d %s %.2f" % [n, clip, clips[clip][0], t])
	return false
