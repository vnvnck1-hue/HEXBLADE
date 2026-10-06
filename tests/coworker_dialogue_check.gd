extends SceneTree
## 동료 소개의 실제 씬/네 분기/원화 방향/하단 선택지와 최대 글자 크기를 검사한다.
var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _seek(main: DialogueMain, cond: Callable) -> bool:
	for step in 200:
		if cond.call():
			return true
		if main.runner.done or main.runner.waiting_choice:
			return false
		main.view.wait_left = -1.0
		main.view._complete()
		main.runner.advance()
	return false


func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.content_scale_size = Vector2i(1280, 800)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	await _frames(2)
	var script := DialogueScript.load_file("res://data/dialogue/coworker_introduction.dlg")
	_check(script.errors.is_empty(), "소개 대본 오류 없음: %s" % script.errors)
	for question in 2:
		for attitude in 2:
			var runner := DialogueRunner.new(script)
			var whos: Array = []
			var poses: Array = []
			runner.said.connect(func(l):
				if not whos.has(l.who):
					whos.append(l.who)
				if l.who == "worker" and not poses.has(l.expr):
					poses.append(l.expr))
			runner.start()
			var choices := 0
			for step in 200:
				if runner.done:
					break
				if runner.waiting_choice:
					runner.choose(question if choices == 0 else attitude)
					choices += 1
				else:
					runner.advance()
			_check(runner.done and choices == 2 and runner.flags.get("worker_introduced", false)
				and runner.flags.get("team_check_ready", false)
				and runner.flags.get("asked_worker_role" if question == 0 else "asked_worker_repair", false)
				and runner.flags.get("coworker_attitude") == ("nervous" if attitude == 0 else "confident"), "역할/고장 질문 × 긴장/자신감 분기 %d/%d 종료" % [question, attitude])
			_check(whos.has("owner") and whos.has("worker") and whos.has("me")
				and poses.has("introduction") and poses.has("cheerful"), "세 사람 발언과 동료 감정 포즈 두 개 사용")
	for path in ["res://assets/portraits/cleaning_owner/owner-introduction-player.png", "res://assets/portraits/purple_worker/purple-worker-introduction-player.png", "res://assets/portraits/purple_worker/purple-worker-cheerful-player.png"]:
		var texture := load(path) as Texture2D
		var image := texture.get_image()
		if image.is_compressed():
			image.decompress()
		_check(not image.is_empty() and image.get_width() == image.get_height() and image.detect_alpha() != Image.ALPHA_NONE, "프로젝트에 저장된 정사각 투명 원화: " + path)
	var main: DialogueMain = load("res://scenes/coworker_dialogue.tscn").instantiate()
	root.add_child(main)
	_check(main.current == "coworker_introduction", "별도 소개 씬의 기본 대본")
	_check(_seek(main, func(): return main.view.portraits.size() == 2 and main.view.line.get("who") == "owner"), "사장의 소개 뒤 동료 등장")
	await create_timer(0.8).timeout
	var owner: DialoguePortrait = main.view.portraits.owner
	var worker: DialoguePortrait = main.view.portraits.worker
	_check(owner.slot == "left" and worker.slot == "right" and owner.body_direction() == 1 and worker.body_direction() == -1,
		"시선은 원화대로 플레이어, 좌우 몸 방향은 서로 반대")
	var owner_rect := owner.get_global_rect()
	var worker_rect := worker.get_global_rect()
	var box_rect := main.view.box.get_global_rect()
	_check(owner.paired and worker.paired and owner_rect.get_center().x < 400.0 and worker_rect.get_center().x > 880.0
		and not owner_rect.intersects(worker_rect) and owner_rect.position.y >= 76.0 and worker_rect.position.y >= 76.0,
		"좌우 인물: 상단 메뉴 아래, 몸/손 겹침 없음 (%s / %s)" % [owner_rect, worker_rect])
	_check(box_rect.position.y > 550.0 and main.view.box.anchor_left == 0.0 and main.view.box.anchor_right == 1.0
		and owner_rect.end.y - box_rect.position.y <= 32.0 and worker_rect.end.y - box_rect.position.y <= 32.0, "항상 하단 전체 너비 창, 인물의 밑단만 창에 연결")
	owner.place("right")
	worker.place("left")
	worker.set_expr("cheerful", false)
	_check(owner.body_direction() == -1 and worker.body_direction() == 1 and owner._flip and worker._flip, "자리 이동/표정 변경에도 원화의 몸 방향 갱신")
	owner.place("left")
	worker.place("right")
	_check(owner.body_direction() == 1 and worker.body_direction() == -1 and not owner._flip and not worker._flip, "본래 자리로 돌아오면 원화 반전 해제")
	_check(_seek(main, func(): return main.runner.waiting_choice), "질문 선택지 표시")
	await _frames(3)
	var choices := main.view.choice_box.get_global_rect()
	_check(main.view.choice_box.get_child_count() == 2 and not main.view.text.visible and choices.position.y > main.view.box.get_global_rect().position.y
		and not choices.intersects(owner.get_global_rect()) and not choices.intersects(worker.get_global_rect()), "선택지 하단 창 안, 두 인물과 비겹침")
	main.view._pick(1)
	await _frames(3)
	_check(main.view.text.visible and main.view.line.who == "worker" and worker.active and not owner.active, "응답 뒤 대사 복원 및 화자 강조")
	var old_size := DialogueView.size_idx
	DialogueView.size_idx = 3
	main.view._apply_size()
	var fits := true
	for item in script.items:
		if item.op != "say":
			continue
		main.view._on_said(item)
		main.view._complete()
		await _frames(2)
		fits = fits and main.view.text.get_content_height() <= main.view.text.size.y
	_check(fits, "소개 대사 모두 글자36에서도 하단 창 안에 표시")
	DialogueView.size_idx = old_size
	main.view._apply_size()
	main.start("cleaning_opening")
	await _frames(2)
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_F4
	key.keycode = KEY_F4
	root.push_input(key)
	await _frames(2)
	_check(main.current == "coworker_introduction", "F4로 소개 장면 전환")
	main.runner.flags["team_check_ready"] = true
	key.physical_keycode = KEY_R
	key.keycode = KEY_R
	root.push_input(key)
	await _frames(2)
	_check(main.current == "coworker_introduction" and main.runner.flags.is_empty(), "R로 소개 장면 상태 초기화")
	main.queue_free()
	await _frames(2)
	var in_lobby := false
	for entry in Lobby.TEST_SCENES:
		in_lobby = in_lobby or entry.scene == "res://scenes/coworker_dialogue.tscn"
	_check(in_lobby and FileAccess.file_exists("res://launchers/scenes/coworker_dialogue.cmd"), "로비 항목과 직접 실행기 있음")
	print("RESULT coworker_dialogue_check: %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
