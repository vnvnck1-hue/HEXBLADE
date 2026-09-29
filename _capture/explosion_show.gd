extends SceneTree
## 스타일라이즈드 폭발 시연 영상.
## godot --path . --fixed-fps 60 --resolution 1280x720 --write-movie DIR/f.png -s _capture/explosion_show.gd
## 컷 1: 근접 시점 정상 속도 · 컷 2: 같은 폭발 0.35배 슬로모션 · 컷 3: 게임 쿼터뷰에서 크기별 연쇄 폭발

var cam: Camera3D
var world: Node3D
var label: Label


func _initialize() -> void:
	world = Node3D.new()
	root.add_child(world)
	FX.setup(world)

	# 게임(main.gd)과 같은 환경 · 글로우 설정
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.85)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_strength = 0.9
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, 28, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	world.add_child(sun)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	ground.material_override = Pal.lit(Pal.FLOOR)
	world.add_child(ground)
	# 바닥 이음선 몇 줄 (게임 바닥 느낌)
	for i in range(-6, 7):
		for axis in 2:
			var line := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.04, 0.005, 40) if axis == 0 else Vector3(40, 0.005, 0.04)
			line.mesh = bm
			line.material_override = Pal.lit(Pal.FLOOR_LINE)
			line.position = Vector3(i * 3.0, 0.003, 0) if axis == 0 else Vector3(0, 0.003, i * 3.0)
			world.add_child(line)

	cam = Camera3D.new()
	world.add_child(cam)

	var ui := CanvasLayer.new()
	root.add_child(ui)
	label = Label.new()
	label.position = Vector2(28, 22)
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color(1, 0.85, 0.6))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 6)
	ui.add_child(label)
	_run.call_deferred()


func _wait(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout


func _run() -> void:
	# 컷 1: 근접 · 정상 속도
	cam.fov = 38
	cam.position = Vector3(0, 4.2, 7.4)
	cam.look_at(Vector3(0, 1.1, 0))
	label.text = "STYLIZED FIRE EXPLOSION  ·  1.0x"
	await _wait(0.4)
	StylizedExplosion.spawn(world, Vector3(0, 1.0, 0), 1.0, 0.0, 7)
	await _wait(3.0)

	# 컷 2: 같은 폭발(같은 시드) 슬로모션
	label.text = "SLOW MOTION  ·  0.35x"
	await _wait(0.3)
	Engine.time_scale = 0.35
	StylizedExplosion.spawn(world, Vector3(0, 1.0, 0), 1.0, 0.0, 7)
	await _wait(3.0 / 0.35 * 0.95)
	Engine.time_scale = 1.0

	# 컷 3: 게임 쿼터뷰 (ACTION 프리셋 오프셋) · 로봇 옆에서 크기별 연쇄
	label.text = "IN-GAME VIEW  ·  k 0.5 / 1.0 / 1.7"
	cam.fov = 42
	cam.position = Vector3(0, 9.0, 6.6) + Vector3(0, 0, 1.0)
	cam.look_at(Vector3(0, 0.6, -0.5))
	var bot := Node3D.new()
	bot.position = Vector3(-0.5, 0, 2.2)
	bot.rotation_degrees.y = 200
	world.add_child(bot)
	Build.robot(bot)
	await _wait(0.5)
	var shots := [[Vector3(2.8, 1.0, -1.0), 0.5], [Vector3(-3.2, 1.0, -1.8), 0.5], [Vector3(0.6, 1.0, -2.6), 1.0],
		[Vector3(3.4, 1.0, -3.4), 0.5], [Vector3(-2.2, 1.0, -4.0), 1.0]]
	for s in shots:
		StylizedExplosion.spawn(world, s[0], s[1])
		await _wait(0.32)
	await _wait(1.2)
	StylizedExplosion.spawn(world, Vector3(0.4, 1.2, -2.0), 1.7)
	await _wait(3.2)
	quit()
