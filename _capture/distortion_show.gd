extends SceneTree
## 공간 왜곡(Distortion) 시연: 격자 바닥·기둥 뒤에서 굴절 충격파와 폭발.
## godot --path . --fixed-fps 60 --resolution 1280x720 --write-movie _capture/distort/f.png -s _capture/distortion_show.gd

var cam: Camera3D
var world: Node3D


func _initialize() -> void:
	world = Node3D.new()
	root.add_child(world)
	FX.setup(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.85)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, 28, 0)
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	ground.material_override = Pal.lit(Pal.FLOOR)
	world.add_child(ground)
	for i in range(-12, 13):
		for axis in 2:
			var line := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.06, 0.005, 40) if axis == 0 else Vector3(40, 0.005, 0.06)
			line.mesh = bm
			line.material_override = Pal.lit(Color(0.7, 0.75, 1.0))
			line.position = Vector3(i * 1.0, 0.003, 0) if axis == 0 else Vector3(0, 0.003, i * 1.0)
			world.add_child(line)
	for x in [-3, -1.5, 1.5, 3]:
		var col := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.4, 2.5, 0.4)
		col.mesh = b
		col.material_override = Pal.lit(Color(0.9, 0.5, 0.3))
		col.position = Vector3(x, 1.25, -2.5)
		world.add_child(col)
	cam = Camera3D.new()
	cam.fov = 42
	world.add_child(cam)
	_run.call_deferred()


func _wait(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout


func _run() -> void:
	cam.position = Vector3(0, 7.5, 7.0)
	cam.look_at(Vector3(0, 0.6, -1.0))
	await _wait(0.3)
	Engine.time_scale = 0.3
	Distortion.burst(Vector3(0, 0.6, -1.0), 4.0, 0.4, 1.4)
	await _wait(0.5)
	Engine.time_scale = 1.0
	await _wait(0.3)
	Engine.time_scale = 0.3
	FX.fire_explosion(Vector3(0, 1.0, -1.0), 1.0)
	await _wait(0.8)
	Engine.time_scale = 1.0
	await _wait(1.0)
	quit()
