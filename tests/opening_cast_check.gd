extends SceneTree
## 실제 새 포트레이트의 임포트/투명도, 주인공 대사창, 파트너 분기와 씬 전환.
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
	for step in 150:
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
	await _frames(2)
	for id in ["owner", "worker", "partner", "me"]:
		for expr in DialogueCast.CAST[id].expr:
			var texture := DialogueCast.texture(id, expr)
			_check(texture != null and texture.resource_path.begins_with("res://assets/portraits/opening_cast/"), id + "/" + expr + " 새 원화 경로")
			if texture == null:
				continue
			var img := texture.get_image()
			if img.is_compressed():
				img.decompress()
			_check(img.get_width() == img.get_height() and img.detect_alpha() != Image.ALPHA_NONE
				and img.get_pixel(0, 0).a == 0.0 and img.get_pixel(img.get_width() - 1, 0).a == 0.0,
				id + "/" + expr + " 정사각 투명 상체")
	_check(DialogueCast.CAST.me.speaker_only, "주인공은 무대 추가 대신 대사창 원화")
	var s := DialogueScript.load_file("res://data/dialogue/field_partner_introduction.dlg")
	_check(s.errors.is_empty(), "파트너 대본 오류 없음: %s" % s.errors)
	for pick in 2:
		var r := DialogueRunner.new(s)
		r.start()
		for step in 100:
			if r.done:
				break
			if r.waiting_choice:
				r.choose(pick)
			else:
				r.advance()
		_check(r.done and r.flags.get("partner_introduced", false), "파트너 분기 %d 완료" % pick)
	var main: DialogueMain = load("res://scenes/partner_dialogue.tscn").instantiate()
	root.add_child(main)
	_check(main.current == "field_partner_introduction", "파트너 씬 기본 대본")
	_check(_seek(main, func(): return main.view.line.get("who") == "me"), "주인공 발언까지 진행")
	await create_timer(0.8).timeout
	_check(main.view.portraits.size() == 2 and not main.view.portraits.has("me") and main.view.speaker_portrait.visible
		and main.view.speaker_portrait.texture == DialogueCast.texture("me", "neutral"), "사장/파트너 무대 두 명 유지 + 주인공 실제 원화 표시")
	var inset := main.view.speaker_portrait.get_global_rect()
	var box := main.view.box.get_global_rect()
	_check(box.encloses(inset) and inset.end.x < main.view.text.get_global_rect().position.x,
		"주인공 원화 대사창 내부, 본문과 비겹침")
	_check(_seek(main, func(): return main.runner.waiting_choice), "파트너 질문 선택지")
	await _frames(3)
	_check(not main.view.speaker_portrait.visible and main.view.choice_box.get_child_count() == 2
		and not main.view.choice_box.get_global_rect().intersects(main.view.portraits.partner.get_global_rect()), "선택지에서는 주인공 원화 숨김, 파트너와 비겹침")
	main.view._pick(0)
	_check(not main.view.speaker_portrait.visible and main.view.line.who == "partner", "동료 응답에서 대사창 원화 해제")
	main.start("cleaning_opening")
	_check(_seek(main, func(): return main.view.line.get("who") == "me"), "기존 첫 출근에도 주인공 포트레이트")
	_check(main.view.speaker_portrait.visible and main.view.portraits.size() == 1, "첫 출근은 사장 단독 무대 유지")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F5
	key.keycode = KEY_F5
	key.pressed = true
	root.push_input(key)
	await _frames(3)
	_check(main.current == "field_partner_introduction" and main.view.portraits.has("partner"), "F5 파트너 소개 전환")
	main.queue_free()
	await _frames(2)
	print("RESULT opening_cast_check: %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
