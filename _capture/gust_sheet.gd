extends SceneTree
## GustFX 부채꼴 모양 변화표: 위에서 내려다본 가시형(윗줄) · 구름형(아랫줄)을 진행도별로 늘어놓는다.
## godot --path . --resolution 1600x500 -s res://_capture/gust_sheet.gd

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	FX.setup(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.1, 0.14)
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	await process_frame
	var g := GustFX._host()
	await process_frame
	g.process_mode = Node.PROCESS_MODE_DISABLED
	var steps := 9
	for row in 2:
		for i in steps:
			var k := (i + 0.5) / steps
			var pos := Vector3((i - (steps - 1) * 0.5) * 1.3, 0, row * 1.5 - 0.75 + 0.5)
			g._fan(pos, Vector3.FORWARD, Vector3.UP, 1.9, 1.0, 1.0, 1.0, float(row))
			g._seed[g._n - 1] = 0.37 + i * 0.001
			g._age[g._n - 1] = k
	g._write()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 3.3
	world.add_child(cam)
	cam.position = Vector3(0, 10, 0)
	cam.look_at(Vector3.ZERO, Vector3.FORWARD)
	cam.current = true
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://_capture/gust/fan_sheet.png")
	# 비스듬히 본 모습 (부피감 확인)
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 60
	cam.position = Vector3(0, 1.6, 3.2)
	cam.look_at(Vector3(0, 0, 0.5))
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://_capture/gust/fan_sheet_3d.png")
	quit()
