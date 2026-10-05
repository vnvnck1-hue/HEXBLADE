extends SceneTree
## Observe the real game using its default camera, lighting and combat bot.
const OUT := "res://output/soft-handpaint-applied-20261005/"
var scene: Main

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	seed(4)
	scene = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	scene.map_seed = 4
	root.add_child(scene)
	current_scene = scene
	for frame in 1800:
		await physics_frame
		if frame in [180, 480, 900, 1380, 1770]:
			await process_frame
			await RenderingServer.frame_post_draw
			var file := OUT + "game_%04d.png" % frame
			var err := root.get_texture().get_image().save_png(file)
			print("APPROVED_PAINT_GAME frame=%d save=%d player=%s" % [frame, err, scene.player.global_position])
	print("APPROVED_PAINT_GAME_COMPLETE")
	quit()
