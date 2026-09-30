extends SceneTree
## Godot --path . --resolution 1280x800 -s docs/mammoth-death/tools/capture_lobby.gd
const LobbyScene := preload("res://scenes/lobby.tscn")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var lobby := LobbyScene.instantiate()
	root.add_child(lobby)
	current_scene = lobby
	for i in 6:
		await process_frame
	await _save("engine-lobby.png")
	lobby._toggle_tests()
	for i in 6:
		await process_frame
	await _save("engine-lobby-expanded.png")
	var scroll: ScrollContainer = lobby.find_children("*", "ScrollContainer", true, false)[0]
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	for i in 3:
		await process_frame
	await _save("engine-lobby-scrolled.png")
	print("MAMMOTH_LAB_LOBBY_CAPTURE_OK")
	quit()

func _save(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://output/mammoth-death-b/".path_join(filename)
	var result := root.get_texture().get_image().save_png(path)
	assert(result == OK)
