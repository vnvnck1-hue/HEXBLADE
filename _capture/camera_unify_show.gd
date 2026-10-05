extends SceneTree
## 카메라 시야 통일 확인: 전투 씬마다 시작 2초 뒤 화면과 카메라 각도 · 화각 · 거리를 남긴다.
## godot --path . -s _capture/camera_unify_show.gd -- [--out=DIR]

const SCENES := [
	["main", "res://scenes/main.tscn"], ["training", "res://scenes/training.tscn"], ["boss", "res://scenes/boss.tscn"],
	["forge", "res://scenes/forge.tscn"], ["abyss", "res://scenes/abyss.tscn"], ["spider", "res://scenes/spider.tscn"],
]

var out := "res://output/camera-unify-20261004"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	for s in SCENES:
		var main: Node = (load(s[1]) as PackedScene).instantiate()
		root.add_child(main)
		current_scene = main
		await _frames(120)
		var cam := root.get_viewport().get_camera_3d()
		if cam:
			var fwd := -cam.global_basis.z
			var pitch := rad_to_deg(asin(clampf(-fwd.y, -1.0, 1.0)))
			var p: Node = main.get("player")
			var dist := cam.global_position.distance_to((p as Node3D).global_position) if p else 0.0
			print("CAM %-8s pitch=%.1f fov=%.1f dist=%.1f" % [s[0], pitch, cam.fov, dist])
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join(String(s[0]) + ".png"))
		main.queue_free()
		await _frames(5)
	quit()
