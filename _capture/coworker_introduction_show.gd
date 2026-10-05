extends SceneTree
## 실제 동료 소개 씬의 사장/정비사/플레이어 발언과 선택지를 캡처한다.
const OUT := "res://output/coworker-introduction-20261004"
var main: DialogueMain


func _initialize() -> void:
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


func _require(ok: bool, what: String) -> bool:
	if not ok:
		push_error("동료 소개 캡처 실패: " + what)
		quit(1)
	return ok


func _shot(name: String) -> void:
	main.view._complete()
	await create_timer(1.0).timeout
	await process_frame
	await process_frame
	for id in main.view.portraits:
		var p: DialoguePortrait = main.view.portraits[id]
		print("COWORKER_LAYOUT %s expr=%s body=%d flip=%s rect=%s paired=%s" % [id, p.expr, p.body_direction(), p._flip, p.get_global_rect(), p.paired])
	root.get_texture().get_image().save_png(OUT + "/" + name + ".png")
	print("COWORKER_CAPTURE ", name)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = load("res://scenes/coworker_dialogue.tscn").instantiate()
	root.add_child(main)
	if not _require(main.current == "coworker_introduction", "new scene default"):
		return
	if not _require(_seek(func(): return main.view.portraits.size() == 2 and main.view.line.get("who") == "owner"), "owner introduces colleague"):
		return
	await _shot("01_owner_introduces")
	if not _require(_seek(func(): return main.view.line.get("who") == "worker"), "mechanic introduction"):
		return
	await _shot("02_worker_greeting")
	if not _require(_seek(func(): return main.view.line.get("who") == "me"), "player reply"):
		return
	await _shot("03_player_reply")
	if not _require(_seek(func(): return main.view.line.get("who") == "worker" and main.view.line.get("expr") == "cheerful"), "cheerful pose"):
		return
	await _shot("04_worker_cheerful")
	if not _require(_seek(func(): return main.runner.waiting_choice), "question choices"):
		return
	await _shot("05_question_choices")
	main.view._pick(1)
	if not _require(_seek(func(): return main.runner.waiting_choice), "attitude choices"):
		return
	main.view._pick(0)
	await _shot("06_reassurance")
	if not _require(_seek(func(): return main.runner.done), "dialogue finished"):
		return
	await _shot("07_together")
	print("COWORKER_CAPTURE_DONE flags=", main.runner.flags)
	quit()
