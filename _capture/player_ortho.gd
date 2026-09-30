extends SceneTree
## 플레이어 기체 3면도 캡처. 3면도 원본과 같은 축척(390px/m, 땅 = 이미지 y 800, 이미지 높이 887)으로
## 정면 · 오른쪽 옆(얼굴이 왼쪽) · 뒤를 찍어 _capture/ortho_{front,side,back}.png 로 저장한다.
## 인자 --stance=0 (3면도 차렷, 기본) / --stance=1 (게임 전투 자세)
## godot --path . --resolution 740x887 -s res://_capture/player_ortho.gd
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var stance := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stance="):
			stance = float(a.split("=")[1])
	var w := Node3D.new()
	root.add_child(w)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.95, 0.95, 0.93)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.82)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	w.add_child(we)
	var sun := DirectionalLight3D.new()
	w.add_child(sun)
	sun.light_energy = 0.75
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 887.0 / 390.0
	w.add_child(cam)
	ToonOutline.attach(cam)
	cam.current = true
	var cy := (800.0 - 887.0 * 0.5) / 390.0
	var views := {"front": Vector3(0, cy, -6), "side": Vector3(-6, cy, 0), "back": Vector3(0, cy, 6)}
	for k in views:
		var bot := Node3D.new()
		w.add_child(bot)
		Build.robot_mech(bot, stance)
		cam.position = views[k]
		cam.look_at(Vector3(0, cy, 0))
		sun.global_transform = Transform3D(Basis.looking_at(Vector3(0, cy, 0) - views[k] + Vector3(0, -4, 0) + Vector3(2, 0, 0).rotated(Vector3.UP, cam.rotation.y)), Vector3.ZERO)
		for i in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://_capture/ortho_%s.png" % k)
		bot.free()
	print("ORTHO saved")
	quit()
