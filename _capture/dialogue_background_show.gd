extends SceneTree
## 실제 대화 씬을 조작해 이미지 배경과 포트레이트를 Forward+로 확인한다.
const OUT := "res://output/dialogue-backgrounds-applied-20261013/"
var main: DialogueMain
var checks: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var fails := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	checks.append({"pass": ok, "message": message})
	fails += int(not ok)

func _seek(cond: Callable) -> bool:
	for step in 200:
		if cond.call():
			return true
		if main.runner.done or main.runner.waiting_choice:
			return false
		main.view.wait_left = -1.0
		main.view._complete()
		main.runner.advance()
	return false

func _key(code: Key, expected: String) -> void:
	var key := InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.pressed = true
	root.push_input(key)
	await process_frame
	await process_frame
	_check(main.current == expected, "실제 키 입력으로 대본 전환: " + expected)

func _shot(name: String, location: String) -> void:
	main.view._complete()
	await create_timer(0.9).timeout
	# 정지 캡처에서 눈 감는 순간을 피한다. 실제 포트레이트/모션/배치는 유지.
	for portrait: DialoguePortrait in main.view.people.get_children():
		portrait.blink.closed = false
		portrait.blink.remaining = 10.0
		portrait._update_idle_images()
	await process_frame
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	_check(shot.save_png(OUT + name + ".png") == OK, "실제 렌더 캡처 저장: " + name)
	var bg := main.view.backdrop
	_check(bg.location_id == location and bg.image.texture == (HangarBackdrop.HANGAR if location == "hangar" else HangarBackdrop.BRIEFING), name + " 선택된 실제 배경 리소스")
	_check(bg.image.get_global_rect().is_equal_approx(main.view.stage.get_global_rect()), name + " 배경이 무대를 빈 틈 없이 채움")
	_check(bg.image.modulate == Color.WHITE and bg.modulate == Color.WHITE, name + " 배경에 추가 색 배수 없음")
	shots.append({"file": name + ".png", "script": main.current, "location": location, "width": shot.get_width(), "height": shot.get_height(), "portraits": main.view.portraits.keys(), "speaker": main.view.line.get("who", "")})
	print("DIALOGUE_BACKGROUND_CAPTURE ", name)

func _size(resolution: Vector2i) -> void:
	root.size = resolution
	root.content_scale_size = resolution
	await process_frame
	await process_frame

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await _size(Vector2i(1280, 800))
	main = load("res://scenes/dialogue.tscn").instantiate()
	root.add_child(main)
	_check(_seek(func(): return main.view.line.get("who") == "owner"), "첫 출근 사장 대사")
	await _shot("01_blue_owner_solo", "hangar")
	_check(_seek(func(): return main.view.line.get("who") == "me"), "주인공 대사")
	await _shot("02_blue_pilot_reply", "hangar")
	await _key(KEY_F2, "hangar_briefing")
	_check(_seek(func(): return main.view.line.get("who") == "worker"), "브리핑 두 인물 대사")
	await _shot("03_red_briefing_pair", "briefing")
	_check(_seek(func(): return main.view.line.get("who") == "partner"), "브리핑 세 인물 대사")
	await _shot("04_red_briefing_three", "briefing")
	_check(_seek(func(): return main.runner.waiting_choice), "브리핑 선택지")
	await _shot("05_red_briefing_choices", "briefing")
	await _key(KEY_F4, "coworker_introduction")
	_check(_seek(func(): return main.view.line.get("who") == "worker"), "정비사 소개 대사")
	await _shot("06_blue_mechanic_pair", "hangar")
	await _key(KEY_F5, "field_partner_introduction")
	_check(_seek(func(): return main.view.line.get("who") == "partner"), "파트너 소개 대사")
	await _shot("07_blue_partner_pair", "hangar")
	await _key(KEY_F3, "feature_demo")
	_check(_seek(func(): return main.view.line.get("who") == "partner"), "기능 시연 단독 대사")
	await _shot("08_red_partner_solo", "briefing")
	await _size(Vector2i(1280, 720))
	await _shot("09_red_solo_16x9", "briefing")
	await _key(KEY_F1, "cleaning_opening")
	_check(_seek(func(): return main.view.line.get("who") == "owner"), "F1 재진입")
	await _size(Vector2i(1024, 768))
	await _shot("10_blue_solo_4x3", "hangar")
	await _key(KEY_R, "cleaning_opening")
	_check(_seek(func(): return main.view.line.get("who") == "owner"), "R 재시작")
	_check(main.view.backdrop.location_id == "hangar", "재시작 시 배경 유지")
	main.queue_free()
	await process_frame
	await process_frame
	var report := FileAccess.open(OUT + "render_validation.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"renderer": "Forward+", "checks": checks, "shots": shots, "fails": fails}, "\t"))
	report.close()
	print("RESULT dialogue_background_capture: %s (%d checks, %d shots, %d fails)" % ["PASS" if fails == 0 else "FAIL", checks.size(), shots.size(), fails])
	quit(1 if fails > 0 else 0)
