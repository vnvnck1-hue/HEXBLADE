extends SceneTree
## 카툰 액체 시트 확인 캡처: 빈 바닥 위에서 LiquidFX.burst 를 터뜨려 연속으로 찍는다 (HUD·적 없음).
## 게임 카메라와 같은 62° 부감 · 화각 36°, 거리만 가깝게. 팔레트 wine · yellow.
## godot --path . -s _capture/liquid_show.gd -- [--out=DIR]

var out := "res://output/liquid-sheets-20261005"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	var w := Node3D.new()
	root.add_child(w)
	current_scene = w
	FX.setup(w)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.1, 0.1, 0.16)
	env.environment.ambient_light_color = Color(0.7, 0.72, 0.9)
	env.environment.ambient_light_energy = 0.7
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-56, -104, 0)
	w.add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.32, 0.34, 0.5)
	fl.material_override = fm
	w.add_child(fl)
	var cam := Camera3D.new()
	cam.fov = 36.0
	w.add_child(cam)
	cam.global_position = Vector3(0, 4.6, 2.45)
	cam.look_at(Vector3(0, 0.3, 0), Vector3.UP)
	cam.make_current()
	await _frames(5)
	for pal in ["wine", "yellow"]:
		seed(7)
		LiquidFX.burst(Vector3(0, 0.15, 0), Vector3.UP, 1.0, pal)
		for f in 12:
			await _frames(3)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join("burst_%s_%02d.png" % [pal, f]))
		await _frames(60)
	print("done")
	quit()
