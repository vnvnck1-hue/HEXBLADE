extends SceneTree
## 보스 모델 턴테이블 캡처. godot --path . -s _capture/boss_shots.gd -- --out=DIR

const BossTank = preload("res://scripts/boss_tank.gd")
const TARGET := Vector3(0, 2.3, -0.2)

var cam: Camera3D
var out := "res://_capture/boss"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var world := Node3D.new()
	root.add_child(world)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.23, 0.23, 0.25)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.78)
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 1.45
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 2.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	world.add_child(sun)
	# 레퍼런스의 청록 반사광을 흉내 낸 역광
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_color = Color(0.55, 0.95, 1.0)
	rim.light_energy = 0.3
	world.add_child(rim)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	ground.material_override = Pal.lit(Color(0.3, 0.3, 0.33))
	world.add_child(ground)

	var boss := Node3D.new()
	world.add_child(boss)
	BossTank.build(boss)

	# 크기 비교용 플레이어 로봇 (마지막 컷에서만 보임)
	var bot := Node3D.new()
	bot.position = Vector3(-4.9, 0, -5.2)
	bot.rotation_degrees.y = 200
	bot.visible = false
	world.add_child(bot)
	Build.robot(bot)

	cam = Camera3D.new()
	cam.fov = 34
	world.add_child(cam)
	_run.call_deferred(bot)


func _aim(yaw: float, pitch: float, dist: float, target := TARGET, fov := 34.0) -> void:
	var y := deg_to_rad(yaw)
	var p := deg_to_rad(pitch)
	cam.fov = fov
	cam.position = target + Vector3(sin(y) * cos(p), sin(p), -cos(y) * cos(p)) * dist
	cam.look_at(target)


func _run(bot: Node3D) -> void:
	var shots := [
		["01_quarter_front", 35, 40, 18.5],
		["02_front", 0, 10, 20.0],
		["03_side", 90, 6, 21.0],
		["04_rear_quarter", 145, 30, 21.0],
		["05_rear", 180, 14, 20.0],
		["06_top", 0, 88, 24.0],
		["07_low_hero", -28, 2, 14.0, Vector3(0, 2.2, -1.5), 46.0],
		["08_turret_close", -40, 28, 9.5, Vector3(0, 3.6, -1.2), 40.0],
	]
	for s in shots:
		if s.size() > 4:
			_aim(s[1], s[2], s[3], s[4], s[5])
		else:
			_aim(s[1], s[2], s[3])
		await _save(s[0])
	bot.visible = true
	_aim(-20, 34, 22.0, Vector3(-1.5, 1.6, -1.5))
	await _save("09_scale_vs_player")
	quit()


func _save(name: String) -> void:
	for i in 4:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("saved ", name)
