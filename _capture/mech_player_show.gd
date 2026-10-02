extends SceneTree
## 새 메카 플레이어 어댑터 확인: 왼쪽 = 원본 GLB 중립, 오른쪽 = MechPlayer.build(기본 자세) 를 4방향에서 찍는다.
## --pose=이름 으로 관절 값을 넣어 본다. 저장 output/mech-player-20261002/show_<뷰>.png
## powershell -File tools\godot.ps1 wait --resolution 1200x700 -s res://_capture/mech_player_show.gd
const OUT := "res://output/mech-player-20261002/"
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var pose := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pose="):
			pose = a.substr(7)
	var w := Node3D.new()
	root.add_child(w)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.32, 0.36, 0.42)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	w.add_child(we)
	var sun := DirectionalLight3D.new()
	w.add_child(sun)
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 1.1
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 4)
	ground.mesh = pm
	w.add_child(ground)
	var ref := (load(MechPlayer.GLB) as PackedScene).instantiate() as Node3D
	w.add_child(ref)
	ref.position = Vector3(-1.6, 0, 0) + MechPlayer.SHIFT
	var body := Node3D.new()
	w.add_child(body)
	body.position = Vector3(1.6, 0, 0)
	var j := MechPlayer.build(body)
	_pose(j, pose)
	MechPlayer.settle(j)
	await process_frame
	print("muzzle=", (j.muzzle as Node3D).global_position - body.position, " fwd=", -(j.muzzle as Node3D).global_basis.z.normalized())
	print("blade_tip=", (j.blade as Node3D).to_global(Vector3(0, 0, -1.3)) - body.position)
	print("foot_l=", (j.foot_l as Node3D).to_global(Vector3(0, -0.12, -0.05)) - body.position, " foot_r=", (j.foot_r as Node3D).to_global(Vector3(0, -0.12, -0.05)) - body.position)
	print("jet_l=", (j.jet_l as Node3D).global_position - body.position, " jet_r=", (j.jet_r as Node3D).global_position - body.position)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 3.2
	w.add_child(cam)
	cam.current = true
	var c := Vector3(0, 0.9, 0)
	var views := {"front": Vector3(0, 0.9, -8), "side": Vector3(8, 0.9, 0), "top": Vector3(0, 9, -0.01), "quarter": Vector3(-5, 7, -6)}
	for k in views:
		cam.position = views[k]
		cam.look_at(c, Vector3.UP if k != "top" else Vector3.FORWARD)
		if k == "top":
			cam.look_at(c, Vector3(0, 0, -1))
		for i in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT + "show_%s%s.png" % [k, ("_" + pose) if pose else ""])
	print("SHOW saved")
	quit()

func _pose(j: Dictionary, pose: String) -> void:
	match pose:
		"walk":
			(j.hip_l as Node3D).rotation.x = 0.7
			(j.hip_r as Node3D).rotation.x = -0.7
			(j.knee_r as Node3D).rotation.x = -0.8
		"slash":
			(j.arm_r as Node3D).rotation.y = 1.2
			(j.arm_r as Node3D).rotation.x = -0.4
			(j.blade as Node3D).rotation_degrees = Vector3(8, -70, 0)
			(j.torso as Node3D).rotation.y = 0.5
		"spin":
			(j.arm_r as Node3D).rotation = Vector3(-0.15, 0, 1.35)
			(j.blade as Node3D).rotation_degrees = Vector3(-90, 0, 0)
		"overhead":
			(j.arm_r as Node3D).rotation.x = 2.8
			(j.blade as Node3D).rotation_degrees = Vector3(-90, 0, 0)
		"crouch":
			(j.hip_l as Node3D).rotation.x = -0.6
			(j.hip_r as Node3D).rotation.x = 0.4
			(j.knee_l as Node3D).rotation.x = -0.7
			(j.knee_r as Node3D).rotation.x = -0.9
