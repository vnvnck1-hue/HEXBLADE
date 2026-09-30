extends SceneTree
## 용광로 액체 스플래시 시연.
## godot --path . --fixed-fps 60 --resolution 1280x720 --write-movie DIR/f.png -s _capture/molten_show.gd
## 컷 1: 근접 · 내려찍기(burst) · 컷 2: 0.3배 슬로모션 · 컷 3: 게임 쿼터뷰에서 burst / impact / column

const Stage := preload("res://scripts/forge_stage.gd")
const MoltenSplash := preload("res://scripts/presentation/molten_splash.gd")

var cam: Camera3D
var world: Node3D
var stage: Stage
var ms: MoltenSplash


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
	sun.light_energy = 1.0
	world.add_child(sun)
	stage = Stage.new()
	world.add_child(stage)
	ms = MoltenSplash.new()
	ms.ground_fn = func(p: Vector3) -> float: return 0.0 if Stage.oct_dist(p) <= stage.radius else Stage.LAVA_Y
	stage.add_child(ms)
	cam = Camera3D.new()
	world.add_child(cam)
	cam.current = true
	_run.call_deferred()


func _wait(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout


func _run() -> void:
	seed(7)
	cam.fov = 40
	cam.position = Vector3(0, 5.5, 13.0)
	cam.look_at(Vector3(0, 2.2, 0))
	await _wait(0.3)
	ms.burst(Vector3(0, 0, 0), 1.0, Vector3(0, 0, 1))
	await _wait(2.6)
	seed(7)
	Engine.time_scale = 0.3
	ms.burst(Vector3(0, 0, 0), 1.0, Vector3(0, 0, 1))
	await _wait(2.4 / 0.3)
	Engine.time_scale = 1.0
	# 게임 쿼터뷰
	cam.fov = 40
	cam.position = Vector3(0, 0, -5.0) + Vector3(0, 40.0, 33.6) * 0.62
	cam.look_at(Vector3(0, 0, -2.0))
	await _wait(0.3)
	ms.burst(Vector3(-3, 0, 1), 1.0, Vector3(-1, 0, 1))
	await _wait(0.5)
	ms.impact(Vector3(4, 0, 3), 0.85)
	await _wait(0.4)
	for p in [Vector3(0, 0, -3), Vector3(3, 0, -5), Vector3(-5, 0, -4)]:
		ms.column(p, 0.9)
	await _wait(2.5)
	quit()
