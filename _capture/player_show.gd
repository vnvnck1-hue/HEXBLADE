extends SceneTree
## 플레이어 기체 모델 확인용 캡처: 실제 런 아레나에서 여러 각도 + 게임 카메라.
## godot --path . -s res://_capture/player_show.gd
var game: RunMain
var shot_cam: Camera3D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = load("res://scenes/run.tscn").instantiate()
	root.add_child(game)
	await process_frame
	get_root().get_node("Run").map_view.want = false
	await create_timer(2.2).timeout
	game.hud.visible = false
	get_root().get_node("Run").map_view.visible = false
	for portal in game.portals:
		portal.visible = false
	var p: Node3D = game.player
	await create_timer(0.3).timeout
	game.process_mode = Node.PROCESS_MODE_DISABLED
	p.rotation.y = 0.0
	for k in ["upper", "legs", "torso"]:
		(p.j[k] as Node3D).rotation = Vector3.ZERO
	p.lean.basis = Basis.IDENTITY
	p.visual.basis = Basis.IDENTITY
	var c := p.global_position + Vector3(0, 1.0, 0)
	shot_cam = Camera3D.new()
	root.add_child(shot_cam)
	for child in game.camera.get_children():
		if child is ToonOutline:
			child.visible = false
	ToonOutline.attach(shot_cam)
	shot_cam.current = true
	shot_cam.fov = 32
	var views := {
		"front": Vector3(0.0, 0.9, -4.6),
		"front34": Vector3(-2.6, 1.8, -3.6),
		"high": Vector3(-1.6, 3.2, -3.0),
		"side": Vector3(4.6, 0.8, 0.0),
		"back34": Vector3(2.8, 2.2, 3.4),
		"top_close": Vector3(-0.9, 1.6, -1.6),
	}
	for k in views:
		shot_cam.position = c + views[k]
		shot_cam.look_at(c + Vector3(0, 0.1, 0))
		await _save("player_" + k)
	shot_cam.current = false
	game.process_mode = Node.PROCESS_MODE_INHERIT
	for child in game.camera.get_children():
		if child is ToonOutline:
			child.visible = true
	game.camera.current = true
	game.hud.visible = true
	await create_timer(0.4).timeout
	await _save("player_ingame")
	quit()

func _save(title: String) -> void:
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png("res://_capture/%s.png" % title)
	print("PLAYER_CAPTURE ", title, " ", err)
