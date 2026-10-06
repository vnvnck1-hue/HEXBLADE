extends SceneTree
## 민트 메이드 컷인 포즈 5종을 체류 시점에 한 장씩 → output/mint-maid-poses-20261007/pose_<n>.png · sheet.png
## Run: tools\godot.ps1 wait -s res://_capture/mint_pose_show.gd

const OUT := "res://output/mint-maid-poses-20261007/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 800)
	var m: TrainingMain = load("res://scenes/training.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	for i in 30:
		await process_frame
	var n: int = (DiagonalDockingCutin.CHARACTERS[2].poses as Array).size()
	for k in n:
		DiagonalDockingCutin.pose_mode = k
		var c := DiagonalDockingCutin.begin(m, null, true)
		while is_instance_valid(c) and c.t < 0.5:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT + "pose_%d.png" % k)
		print("pose ", k, " ", c.pose_i)
		c.queue_free()
		for i in 10:
			await process_frame
	DiagonalDockingCutin.pose_mode = -1
	quit()
