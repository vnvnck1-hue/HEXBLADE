extends SceneTree
## 적 피격 연출 근접 캡처: 드론 셋에 총알·검·미사일 세기로 피격 연출을 띄워 프레임마다 저장한다.
## 환경(글로우 포함)은 main.gd 와 같은 값. godot --path . -s _capture/hit_spark_show.gd -- --out=DIR

var out := "res://_capture/hit_spark"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var world := Node3D.new()
	root.add_child(world)
	FX.setup(world)
	world.add_child(GunFX.new())
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.85)
	env.ambient_light_energy = 0.4
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
	sun.light_energy = 0.8
	world.add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	fl.mesh = pm
	fl.material_override = Pal.lit(Pal.FLOOR)
	world.add_child(fl)
	var drones: Array[Node3D] = []
	for x in [-3.2, 0.0, 3.2]:
		var d := Node3D.new()
		d.position = Vector3(x, 0, 0)
		world.add_child(d)
		Build.drone(d)
		drones.append(d)
	var cam := Camera3D.new()
	cam.fov = 40
	world.add_child(cam)
	cam.look_at_from_position(Vector3(0, 8.5, 6.5), Vector3(0, 0.8, 0))
	_run.call_deferred(drones)


func _run(drones: Array[Node3D]) -> void:
	for f in 30:
		if f == 2:
			var fwd := Vector3(0.4, 0, -1).normalized()
			# 왼쪽: 총알 · 가운데: 검 · 오른쪽: 미사일 세기
			var p0 := drones[0].global_position + Vector3(0, 1.0, 0.5)
			HitSpark.spawn(p0, fwd, 1.0)
			GunFX.impact_body(p0, fwd, Pal.E_RED)
			HitSpark.spawn(drones[1].global_position + Vector3(0, 1.0, 0.3), Vector3(1, 0, -0.3), 1.8)
			HitSpark.spawn(drones[2].global_position + Vector3(0, 1.0, 0.3), Vector3(-1, 0, -0.5), 1.5)
		await process_frame
		if f >= 2 and f <= 22:
			root.get_texture().get_image().save_png(out.path_join("f_%02d.png" % f))
	quit()
