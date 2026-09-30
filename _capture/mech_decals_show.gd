extends SceneTree
## 실제 게임 아레나에서 메카닉 데칼 배치를 캡처한다.
## --scene=run(기본) | main   --tag=이름
var game: Node

func _initialize() -> void:
	_run.call_deferred()

func _arg(key: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.split("=")[1]
	return def

func _run() -> void:
	var scene := _arg("scene", "run")
	var tag := _arg("tag", scene)
	var t0 := Time.get_ticks_msec()
	game = load("res://scenes/%s.tscn" % scene).instantiate()
	root.add_child(game)
	await process_frame
	print("DECAL_BUILD_MS ", Time.get_ticks_msec() - t0)
	var run := get_root().get_node_or_null("Run")
	if run and run.map_view:
		run.map_view.want = false
	await create_timer(2.0).timeout
	if run and run.map_view:
		run.map_view.visible = false
		run.map_view.process_mode = Node.PROCESS_MODE_DISABLED
	game.process_mode = Node.PROCESS_MODE_DISABLED
	var kit: Node = game.map.get_node("MechDecals")
	var slots := {}
	var neon := 0
	for d in kit.get_children():
		if d is Decal:
			slots[d.get_meta("slot")] = slots.get(d.get_meta("slot"), 0) + 1
			neon += d.get_child_count()
	print("DECAL_COUNT ", slots, " neon=", neon)
	# 게임은 멈춰도 네온 점등은 계속 돌려서 순차 점등 프레임을 찍는다
	kit.get_node("Neon").process_mode = Node.PROCESS_MODE_ALWAYS
	await _save("decals_%s_gameplay" % tag)
	var p: Vector3 = game.player.global_position
	game.hud.visible = false
	var cam := Camera3D.new()
	root.add_child(cam)
	ToonOutline.attach(cam)
	cam.current = true
	cam.fov = 50
	cam.position = p + Vector3(0, 26, 17)
	cam.look_at(p + Vector3(0, 0, -1))
	await _save("decals_%s_overview" % tag)
	cam.fov = 38
	cam.position = p + Vector3(-3, 9, 9)
	cam.look_at(p + Vector3(0, 0, -3))
	await _save("decals_%s_close" % tag)
	DirAccess.make_dir_recursive_absolute("res://_capture/decals_seq")
	for i in 12:
		await create_timer(0.07).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://_capture/decals_seq/%s_%02d.png" % [tag, i])
	print("DECAL_SEQ saved")
	quit()

func _save(title: String) -> void:
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://_capture/%s.png" % title)
	print("DECAL_CAPTURE ", title)
