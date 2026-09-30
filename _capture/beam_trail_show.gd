extends SceneTree
## 메가 빔 끝점 궤적 잔상 시연. 쿼터뷰에서 빔을 좌우로 흔들며 쏜다.
## godot --path . --fixed-fps 60 --resolution 1280x720 --write-movie DIR/f.png -s _capture/beam_trail_show.gd

var world: Node3D
var beam: MegaBeam
var t := 0.0
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
	pm.size = Vector2(60, 60)
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


func _run() -> void:
	cam.fov = 40
	cam.position = Vector3(0, 0, -5.0) + Vector3(0, 40.0, 33.6) * 0.62
	cam.look_at(Vector3(0, 0, -5.0))
	await create_timer(0.1).timeout
	beam = MegaBeam.new()
	FX.root.add_child(beam)
	_aim(0.0)
	while t < 2.4:
		await process_frame
		t += 1.0 / 60.0
		_aim(t)
	beam.finish()
	await create_timer(2.0).timeout
	quit()


func _aim(tt: float) -> void:
	var yaw := sin(tt * 2.6) * 0.55 + sin(tt * 6.1) * 0.12
	var d := Vector3(sin(yaw), 0, -cos(yaw))
	var len := 13.0 + sin(tt * 4.3) * 1.5
	beam.set_beam(Vector3(0, 0.95, 4.0), d, len)
