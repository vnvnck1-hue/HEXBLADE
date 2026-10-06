extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	root.add_child(scene)
	current_scene = scene
	for i in 180:
		await physics_frame
	print("RUNTIME_PROBE time=", scene.time, " dt=", scene.get_physics_process_delta_time(), " scale=", Engine.time_scale, " paused=", paused, " physics=", scene.is_physics_processing(), " bot=", scene.player.bot, " pos=", scene.player.global_position)
	quit()
