extends SceneTree
const OUT := "res://output/lobby-applied-20261011"
var lobby: Lobby
var fails := 0
var checks: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "/" + name + ".png")
	print("LOBBY_CAPTURE ", name, " viewport=", root.size)

func _check(ok: bool, name: String) -> void:
	checks.append({"name": name, "pass": ok})
	print("PASS " if ok else "FAIL ", name)
	if not ok:
		fails += 1

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
	for i in 3:
		await process_frame

func _wait_scene(path: String) -> bool:
	for i in 600:
		await process_frame
		if current_scene and current_scene.scene_file_path == path:
			for settle in 20:
				await process_frame
			return true
	return false

func _run() -> void:
	lobby = load(Lobby.SCENE).instantiate()
	root.add_child(lobby)
	current_scene = lobby
	for dims in [Vector2i(1280, 800), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1920, 800)]:
		DisplayServer.window_set_size(dims)
		await _shot("lobby_%dx%d" % [dims.x, dims.y])
	DisplayServer.window_set_size(Vector2i(1280, 800))
	lobby.art.menus[1].grab_focus()
	await _shot("focus_death_test")
	lobby._toggle_tests()
	await _shot("drawer_top")
	lobby.art.rows[7].grab_focus()
	await _shot("drawer_long_title")
	lobby.art.rows[-1].grab_focus()
	await _shot("drawer_bottom")
	lobby.art.set_drawer(false)
	await _shot("drawer_closed")
	if OS.get_environment("HEX_LOBBY_VISUAL") == "1":
		quit()
		return
	# 실제 전역 F11 입력. 창 모드로 되돌린 후 진입/복귀를 검증한다.
	await _key(KEY_F11)
	_check(DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN], "F11 전체 화면")
	await _key(KEY_F11)
	_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "F11 창 모드 복귀")
	DisplayServer.window_set_size(Vector2i(1280, 800))
	var initial_nodes := get_node_count()
	var training_index := 0
	for i in Lobby.TEST_SCENES.size():
		if Lobby.TEST_SCENES[i].scene == "res://scenes/training.tscn":
			training_index = i
	for repeat in 3:
		lobby.art.menus[2].grab_focus()
		await _key(KEY_ENTER)
		lobby.art.rows[training_index].grab_focus()
		await _key(KEY_ENTER)
		_check(await _wait_scene("res://scenes/training.tscn"), "목록 Enter 허수아비 진입 " + str(repeat))
		if repeat == 0:
			await _shot("training_entry")
		await _key(KEY_ESCAPE)
		_check(await _wait_scene(Lobby.SCENE), "실제 Esc 로비 복귀 " + str(repeat))
		lobby = current_scene as Lobby
		_check(lobby.art.rows.size() == Lobby.TEST_SCENES.size() and root.gui_get_focus_owner() == lobby.main_btn, "재진입 전체 목록/최초 포커스 " + str(repeat))
		_check(get_node_count() == initial_nodes, "재진입 노드 수 일정 " + str(repeat))
	lobby.art.menus[1].grab_focus()
	await _key(KEY_ENTER)
	_check(await _wait_scene(Lobby.DEATH_TEST_SCENE), "연출 테스트 전용 경로 진입")
	await _shot("death_test_entry")
	await _key(KEY_ESCAPE)
	_check(await _wait_scene(Lobby.SCENE), "연출 테스트 Esc 복귀")
	lobby = current_scene as Lobby
	var run := root.get_node("Run")
	run.score = 1234
	lobby.main_btn.grab_focus()
	await _key(KEY_ENTER)
	_check(await _wait_scene(Lobby.RUN_SCENE), "섹터 런 실제 진입")
	_check(run.active and run.score == 0, "new_run 새 런 초기화")
	await _shot("sector_run_entry")
	await _key(KEY_ESCAPE)
	_check(await _wait_scene(Lobby.SCENE), "섹터 런 Esc 복귀")
	lobby = current_scene as Lobby
	_check(is_equal_approx(Engine.time_scale, 1.0) and Engine.physics_ticks_per_second == 60, "복귀 시간/물리 복구")
	await _shot("final_lobby")
	var file := FileAccess.open(OUT + "/interaction-validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "fails": fails}, "\t"))
	file.close()
	print("LOBBY_INTERACTION_RESULT fails=", fails)
	if fails:
		quit(1)
	else:
		print("LOBBY_QUIT_BUTTON Enter")
		lobby.art.menus[3].grab_focus()
		await _key(KEY_ENTER)
