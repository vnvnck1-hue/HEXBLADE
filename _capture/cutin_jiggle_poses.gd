extends SceneTree
## 가슴 흔들림 셰이더 단독 확인: 원화 한 장에 변위 몇 가지를 넣어 나란히 저장한다 (게임 화면 아님).
## 실행: powershell -File tools\godot.ps1 wait --resolution 1024x1024 -s res://_capture/cutin_jiggle_poses.gd -- --out=<폴더> [--debug]
## --debug 면 영향 타원을 색으로 칠한다.

const POSES := [
	["neutral", Vector2.ZERO, Vector2.ZERO, 0.0],
	["up", Vector2(0, -22), Vector2(0, -18), -0.09],
	["down", Vector2(0, 22), Vector2(0, 18), 0.09],
	["left", Vector2(-24, 0), Vector2(-20, 2), 0.0],
	["right", Vector2(24, 0), Vector2(20, -2), 0.0],
	["split", Vector2(-10, -20), Vector2(12, 16), 0.0],
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := ""
	var debug := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--debug":
			debug = true
	DirAccess.make_dir_recursive_absolute(out)
	var r := TextureRect.new()
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture = CockpitCutin.PLATE
	r.size = Vector2(1024, 1024)
	var m := ShaderMaterial.new()
	m.shader = CockpitCutin.JIGGLE
	r.material = m
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.15)
	bg.size = Vector2(1024, 1024)
	root.add_child(bg)
	root.add_child(r)
	for p: Array in POSES:
		var l: Vector2 = p[1]
		var rr: Vector2 = p[2]
		m.set_shader_parameter("off_l", l / 1024.0)
		m.set_shader_parameter("off_r", rr / 1024.0)
		m.set_shader_parameter("sq_l", p[3])
		m.set_shader_parameter("sq_r", p[3])
		await process_frame
		await process_frame
		RenderingServer.force_draw()
		await process_frame
		root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, p[0]])
	quit()
