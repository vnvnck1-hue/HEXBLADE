extends SceneTree
## 전투 테스트장 왼쪽 설정 패널 확인 캡처 → output/training-panel-20261005/
## powershell -File tools\godot.ps1 wait --resolution 1280x800 -s res://_capture/training_panel_show.gd
const OUT := "res://output/training-panel-20261005/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for sc in ["training", "drone", "claude_background_first_pass"]:
		if not ResourceLoader.exists("res://scenes/%s.tscn" % sc):
			continue
		change_scene_to_file("res://scenes/%s.tscn" % sc)
		for i in 150:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT + sc + ".png")
	quit()
