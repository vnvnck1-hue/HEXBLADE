extends SceneTree
## 충전 레이저 몸통 잔상 시연.
## godot --path . --fixed-fps 60 --resolution 1280x720 --write-movie DIR/f.png -s _capture/beam_afterimage_show.gd
## 컷 1: 옆에서 본 0.25배 슬로모션 · 컷 2: 게임 쿼터뷰 정속 (충전 0.5 / 1.0)

var world: Node3D
var cam: Camera3D


func _initialize() -> void:
	world = Node3D.new()
	root.add_child(world)
	FX.setup(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.28, 0.28, 0.3)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.7)
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, 28, 0)
	world.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.3, 0.32)
	floor.material_override = fm
	world.add_child(floor)
	var sfx := Sfx.new()
	world.add_child(sfx)
	sfx.muted = true
	cam = Camera3D.new()
	world.add_child(cam)
	cam.current = true
	_run.call_deferred()


func _wait(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout


func _run() -> void:
	seed(3)
	# 컷 1: 옆모습 슬로모션
	cam.fov = 40
	cam.position = Vector3(0, 1.6, 14.0)
	cam.look_at(Vector3(0, 0.95, 0))
	await _wait(0.2)
	Engine.time_scale = 0.25
	FX.laser(Vector3(-9, 0.95, 0), Vector3.RIGHT, 18.0, 1.25, 1.0)
	await _wait(1.3 / 0.25)
	Engine.time_scale = 1.0
	# 컷 2: 쿼터뷰 정속
	cam.position = Vector3(0, 0, -5.0) + Vector3(0, 40.0, 33.6) * 0.62
	cam.look_at(Vector3(0, 0, -5.0))
	await _wait(0.3)
	FX.laser(Vector3(-6, 0.95, 2), Vector3(0.6, 0, -0.8).normalized(), 16.0, 0.85, 0.5)
	await _wait(1.2)
	FX.laser(Vector3(6, 0.95, 2), Vector3(-0.5, 0, -0.85).normalized(), 18.0, 1.25, 1.0)
	await _wait(1.4)
	quit()
