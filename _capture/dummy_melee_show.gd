extends SceneTree
## 허수아비 근접 반격(후려치기) 확인 캡처: 준비동작 · 별빛 · 한 박자 · 후려치기 · 패링.
## powershell -File tools\godot.ps1 wait --fixed-fps 60 -s res://_capture/dummy_melee_show.gd -- --out=DIR

var out := "res://output/parry-timing-20261007"
var main: TrainingMain
var p: Player
var cam: Camera3D
var n := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _frames(k: int) -> void:
	for i in k:
		await physics_frame


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	n += 1
	root.get_texture().get_image().save_png(out.path_join("%02d_%s.png" % [n, name]))


func _run() -> void:
	main = (load("res://scenes/training.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(30)
	main.god = true
	Main.ui_hidden = true
	main.show_help = false
	p = main.player
	for d in main.dummies:
		if is_instance_valid(d):
			d.queue_free()
	main.dummies.clear()
	main.counter_melee = true
	var at := main.center + Vector3(0, 0, -1.0)
	var d := main._spawn_dummy(at)
	await _frames(70)
	cam = Camera3D.new()
	cam.fov = 34.0
	main.world.add_child(cam)
	cam.make_current()
	cam.global_position = at + Vector3(4.5, 3.2, 4.0)
	cam.look_at(at + Vector3(0, 1.0, 1.0), Vector3.UP)
	p.global_position = at + Vector3(0, 0, 2.2)
	p.aim_override = at + Vector3(0, 0.95, 0)
	while d.m_state != "wind":
		await physics_frame
	await _frames(20)
	await _shot("wind_mid")
	while d.m_state != "beat":
		await physics_frame
	await _frames(2)
	await _shot("beat_star")
	while Parry.inst.best_threat() != d:
		await physics_frame
	await _shot("window_open")
	while d.m_state != "swing":
		await physics_frame
	await _frames(2)
	await _shot("swing")
	await _frames(3)
	await _shot("after_swing")
	# 두 번째: 패링
	while Parry.inst.best_threat() != d:
		await physics_frame
	Parry.inst.try_parry(p)
	await _frames(2)
	await _shot("parried")
	await _frames(20)
	await _shot("parried_stagger")
	quit()
