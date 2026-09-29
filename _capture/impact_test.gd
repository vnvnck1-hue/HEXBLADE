extends SceneTree
## 피격 연출 크기 비교: 왼쪽 보스 크기(1.0), 오른쪽 작은 적(드론 반지름 기준). godot --path . -s _capture/impact_test.gd -- --out=DIR

const BeamImpact := preload("res://scripts/beam_impact.gd")
const BossTank := preload("res://scripts/boss_tank.gd")

var out := "res://_capture/impact_test"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var world := Node3D.new()
	root.add_child(world)
	FX.setup(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.85)
	env.ambient_light_energy = 0.4
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.1
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

	# 왼쪽: 보스, 오른쪽: 드론
	var boss := Node3D.new()
	boss.position = Vector3(-5.5, 0, -3.3)
	boss.rotation.y = PI
	world.add_child(boss)
	BossTank.build(boss)
	var drone := Node3D.new()
	drone.position = Vector3(5.0, 0, -0.62)
	world.add_child(drone)
	Build.drone(drone)

	# 빔 (시각용): 아래에서 위(-Z)로
	for x in [-5.5, 5.0]:
		var bm := CylinderMesh.new()
		bm.top_radius = 0.5
		bm.bottom_radius = 0.5
		bm.height = 1.0
		var b := Pal.flat_mesh(bm, Pal.CYAN, 1.8)
		b.rotation_degrees.x = 90
		b.position = Vector3(x, 0.95, 5.0)
		b.scale = Vector3(1.1, 10.0, 1.1)
		world.add_child(b)

	var big := BeamImpact.new()
	world.add_child(big)
	var small := BeamImpact.new()
	world.add_child(small)

	var cam := Camera3D.new()
	cam.fov = 44
	world.add_child(cam)
	cam.look_at_from_position(Vector3(0, 13, 9), Vector3(0, 0.5, -0.5))
	_run.call_deferred(big, small)


func _run(big: Node3D, small: Node3D) -> void:
	var size_small := clampf(0.62 / BeamImpact.BIG_RADIUS, BeamImpact.MIN_SIZE, 1.0)
	for f in 40:
		big.touch(Vector3(-5.5, 0.95, 0.0), Vector3.FORWARD, 1.0)
		small.touch(Vector3(5.0, 0.95, 0.0), Vector3.FORWARD, size_small)
		await process_frame
		if f in [24, 30, 36]:
			root.get_texture().get_image().save_png(out.path_join("f_%02d.png" % f))
	quit()
