extends SceneTree
const OUT := "res://output/opening-dialogue-applied-20261011"
var main: DialogueMain

func _initialize() -> void:
	_run.call_deferred()

func _seek(cond: Callable) -> bool:
	for step in 160:
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
	await create_timer(0.9).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "/" + name + ".png")
	print("OPENING_CAST_CAPTURE ", name)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = load("res://scenes/dialogue.tscn").instantiate()
	root.add_child(main)
	if not _seek(func(): return main.view.line.get("who") == "owner"):
		quit(1)
		return
	await _shot("01_owner_welcome")
	_seek(func(): return main.view.line.get("who") == "me")
	await _shot("02_pilot_reply")
	_seek(func(): return main.view.line.get("expr") == "briefing")
	await _shot("03_owner_briefing")
	main.start("coworker_introduction")
	_seek(func(): return main.view.portraits.size() == 2 and main.view.line.get("who") == "worker")
	await _shot("04_mechanic_introduction")
	_seek(func(): return main.view.line.get("expr") == "cheerful")
	await _shot("05_mechanic_cheerful")
	main.start("field_partner_introduction")
	_seek(func(): return main.view.line.get("who") == "partner")
	await _shot("06_partner_greeting")
	_seek(func(): return main.view.line.get("who") == "me")
	await _shot("07_partner_pilot_reply")
	_seek(func(): return main.runner.waiting_choice)
	await _shot("08_partner_choices")
	main.view._pick(0)
	_seek(func(): return main.view.line.get("expr") == "encouragement")
	await _shot("09_owner_encouragement")
	quit()
