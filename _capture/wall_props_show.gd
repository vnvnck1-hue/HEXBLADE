extends SceneTree
## Captures the actual RunMain arena with its generated wall dressing.
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
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.hud.visible = false
	get_root().get_node("Run").map_view.visible = false
	get_root().get_node("Run").map_view.process_mode = Node.PROCESS_MODE_DISABLED
	# Inspection shots hide portal VFX only; gameplay shot restores them below.
	for portal in game.portals:
		portal.visible = false
	var props := game.map.get_node("WallProps").get_children()
	print("WALL_KIT_INSTANCE_COUNT ", props.size())
	for prop in props:
		print("WALL_KIT_PLACED ", prop.name, " ", prop.position)
	DirAccess.make_dir_recursive_absolute("res://scenes/props")
	for kind in 3:
		var model := WallProps.create(kind)
		for child in model.get_children():
			child.owner = model
		var packed := PackedScene.new()
		packed.pack(model)
		ResourceSaver.save(packed, "res://scenes/props/%s.tscn" % model.name.to_snake_case())
		model.free()
	if props.size() < 3:
		push_error("Expected all three wall variants in the starting arena")
		quit(1)
		return
	var center: Vector3 = props[1].global_position
	game.player.global_position = center + Vector3(-2,0,2.8)
	game.player.rotation.y = PI
	shot_cam = Camera3D.new()
	root.add_child(shot_cam)
	shot_cam.current = true
	for child in game.camera.get_children():
		if child is ToonOutline:
			child.visible = false
	ToonOutline.attach(shot_cam)
	shot_cam.fov = 40
	shot_cam.position = center + Vector3(2.8,5.1,12.7)
	shot_cam.look_at(center+Vector3(0,1.2,0))
	await _save("wall_props_detail")
	shot_cam.position = center + Vector3(0,10.8,9.2)
	shot_cam.fov = 49
	shot_cam.look_at(center+Vector3(0,0.3,3.1))
	await _save("wall_props_ingame")
	for i in 3:
		var at: Vector3 = props[i].global_position
		shot_cam.position = at+Vector3(3.6,3.1,6.5)
		shot_cam.fov = 35
		shot_cam.look_at(at+Vector3(0,1.52,0))
		await _save("wall_prop_%d" % i)
	shot_cam.current = false
	shot_cam.get_child(0).visible = false
	for portal in game.portals:
		portal.visible = true
	game.player.global_position = center + Vector3(0,0,4.4)
	game.camera.current = true
	game.camera.set_preset(3)
	game.camera.snap(game.player.global_position)
	for child in game.camera.get_children():
		if child is ToonOutline:
			child.visible = true
	game.hud.visible = true
	await _save("wall_props_gameplay")
	quit()

func _save(title: String) -> void:
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png("res://_capture/%s.png" % title)
	print("WALL_KIT_CAPTURE ", title, " result=", result)
