extends SceneTree
## 실제 엔진 입력/반응형 배치/긴 목록의 스크롤과 포커스 복구 검사.
var fails := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1

func _key(code: Key, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.shift_pressed = shift
	e.pressed = true
	root.push_input(e)
	await process_frame
	e = e.duplicate()
	e.pressed = false
	root.push_input(e)
	await process_frame
	await process_frame

func _settle() -> void:
	for i in 8:
		await process_frame

func _run() -> void:
	root.size = Vector2i(1280, 800)
	var lobby: Lobby = load(Lobby.SCENE).instantiate()
	root.add_child(lobby)
	current_scene = lobby
	await _settle()
	var art := lobby.art
	_check(root.gui_get_focus_owner() == lobby.main_btn, "최초 섹터 런 포커스")
	_check(art.menus.size() == 4 and art.rows.size() == Lobby.TEST_SCENES.size(), "네 메뉴와 현행 전체 테스트 목록")
	await _key(KEY_DOWN)
	_check(root.gui_get_focus_owner() == art.menus[1], "아래키 연출 테스트")
	await _key(KEY_TAB)
	_check(root.gui_get_focus_owner() == art.menus[2], "Tab 테스트 씬")
	await _key(KEY_ENTER)
	await _settle()
	_check(art.drawer.visible and root.gui_get_focus_owner() == art.rows[0], "Enter 패널 열기 / 첫 행")
	_check(art.menus.all(func(b: Button): return b.disabled and b.focus_mode == Control.FOCUS_NONE), "패널 뒤 메뉴 입력/포커스 차단")
	for i in art.rows.size() - 1:
		await _key(KEY_DOWN)
	await _settle()
	var row := art.rows[-1]
	_check(root.gui_get_focus_owner() == row and art.scroll.scroll_vertical > 0, "마지막 항목까지 키보드 스크롤")
	_check(art.scroll.get_global_rect().encloses(row.get_global_rect()), "선택한 마지막 항목 전체 노출")
	for b in art.rows:
		var content := b.get_child(0) as VBoxContainer
		_check(content.get_combined_minimum_size().y <= b.size.y - 27, "긴 제목/설명 잘림 없음 " + b.name)
	await _key(KEY_ESCAPE)
	_check(not art.drawer.visible and root.gui_get_focus_owner() == art.menus[2], "Esc 패널만 닫기 / 테스트 버튼 복귀")
	await _key(KEY_ENTER)
	await _settle()
	_check(root.gui_get_focus_owner() == row and art.scroll.scroll_vertical > 0, "재개방 선택/스크롤 보존")
	await _key(KEY_TAB)
	_check(root.gui_get_focus_owner() == art.close_button, "Tab으로 닫기 접근")
	await _key(KEY_ENTER)
	_check(not art.drawer.visible, "닫기 버튼 Enter")
	for viewport_size in [Vector2(1280, 800), Vector2(1280, 720), Vector2(1920, 1080), Vector2(1920, 800)]:
		art.size = viewport_size
		art.fit()
		var rect := Rect2(art.canvas.position, LobbyArt.DESIGN * art.canvas.scale)
		_check(Rect2(Vector2.ZERO, viewport_size).encloses(rect) and is_equal_approx(art.canvas.scale.x, art.canvas.scale.y), "원화/검/드론/메뉴 비율 유지 " + str(viewport_size))
		_check(rect.get_center().distance_to(viewport_size * 0.5) < 0.01, "캔버스 중앙 정렬 " + str(viewport_size))
	art.size = root.size
	art.fit()
	await _settle()
	# 실제 포인터 이벤트: 장식 위에서도 버튼이 입력을 받는지 확인한다.
	var mouse := InputEventMouseMotion.new()
	art.menus[0].grab_focus()
	mouse.position = art.menus[2].get_global_rect().get_center()
	root.push_input(mouse, true)
	await _settle()
	_check(root.gui_get_focus_owner() == art.menus[2], "마우스 호버 포커스")
	for down in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = mouse.position
		click.button_index = MOUSE_BUTTON_LEFT
		click.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		click.pressed = down
		root.push_input(click, true)
		await process_frame
	await _settle()
	_check(art.drawer.visible, "마우스 실제 클릭 패널 열기")
	art.set_drawer(false)
	# 마우스 휠로도 긴 목록에 접근하고 닫기 버튼을 직접 누른다.
	art.last_row = 0
	art.set_drawer(true)
	await _settle()
	var wheel := InputEventMouseButton.new()
	wheel.position = art.scroll.get_global_rect().get_center()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	root.push_input(wheel, true)
	wheel = wheel.duplicate()
	wheel.pressed = false
	root.push_input(wheel, true)
	await _settle()
	_check(art.scroll.scroll_vertical > 0, "마우스 휠 목록 스크롤")
	var close_motion := InputEventMouseMotion.new()
	close_motion.position = art.close_button.get_global_rect().get_center()
	root.push_input(close_motion, true)
	await _settle()
	for down in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = art.close_button.get_global_rect().get_center()
		click.button_index = MOUSE_BUTTON_LEFT
		click.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		click.pressed = down
		root.push_input(click, true)
		await process_frame
	_check(not art.drawer.visible and root.gui_get_focus_owner() == art.menus[2], "닫기 버튼 마우스 클릭과 포커스 복구")
	var children := lobby.get_child_count()
	for i in 10:
		art.set_drawer(true)
		art.set_drawer(false)
	_check(children == lobby.get_child_count() and art.rows.size() == Lobby.TEST_SCENES.size(), "10회 열기/닫기 노드와 목록 중복 없음")
	for i in Lobby.TEST_SCENES.size():
		var entry: Dictionary = Lobby.TEST_SCENES[i]
		_check(ResourceLoader.exists(entry.scene), "실제 씬 존재 " + entry.title)
		var connections := art.rows[i].get_signal_connection_list("pressed")
		_check(connections.size() == 1 and connections[0].callable.get_bound_arguments() == [entry.scene], "현행 씬 경로 연결 " + entry.title)
	lobby.queue_free()
	await _settle()
	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails else 0)
