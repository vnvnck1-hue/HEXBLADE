extends SceneTree
## 실제 대화 테스트씬에서 새 오프닝의 표정/선택지/종료를 캡처한다.
const OUT := "res://output/cleaning-opening-20261004"
var out := OUT
var main: DialogueMain


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	_run.call_deferred()


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


func _shot(name: String) -> void:
	main.view._complete()
	await create_timer(0.8).timeout
	await process_frame
	await process_frame
	if main.view.portraits.has("owner"):
		print("PORTRAIT_LAYOUT ", main.view.portraits.owner.get_global_rect(), " solo=", main.view.portraits.owner.solo)
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("OPENING_CAPTURE ", name)


func _require(ok: bool, what: String) -> bool:
	if not ok:
		push_error("청소업체 오프닝 캡처 실패: " + what)
		quit(1)
	return ok


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	main = load("res://scenes/dialogue.tscn").instantiate()
	root.add_child(main)
	if not _require(main.current == "cleaning_opening", "default script"):
		return
	if not _require(_seek(func(): return main.view.line.get("who") == "owner"), "welcome"):
		return
	await _shot("01_welcome")
	if not _require(_seek(func(): return main.view.line.get("expr") == "briefing"), "briefing"):
		return
	await _shot("02_briefing")
	if not _require(_seek(func(): return main.runner.waiting_choice), "question choices"):
		return
	await _shot("03_questions")
	main.view._pick(1)
	if not _require(_seek(func(): return main.runner.waiting_choice), "departure choices"):
		return
	main.view._pick(0)
	if not _require(main.view.portraits.owner.expr == "encouragement", "encouragement texture"):
		return
	await _shot("04_encouragement")
	if not _require(_seek(func(): return main.runner.done), "finished"):
		return
	await _shot("05_finished")
	print("OPENING_CAPTURE_DONE flags=", main.runner.flags)
	quit()
