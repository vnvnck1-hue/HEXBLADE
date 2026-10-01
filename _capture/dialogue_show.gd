extends SceneTree
## 대화 시스템 캡처: 대표 장면을 output/dialogue-20261001/ 에 PNG 로 남긴다.
##   powershell -File tools\godot.ps1 wait -s res://_capture/dialogue_show.gd

const OUT := "res://output/dialogue-20261001"
var view: DialogueView
var runner: DialogueRunner


func _initialize() -> void:
	_run.call_deferred()


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, name])
	print("saved ", name)


## 화자가 who 인 대사(또는 선택지)가 나올 때까지 빨리 넘긴다
func _skip_to(cond: Callable) -> void:
	for i in 400:
		if cond.call():
			return
		view._complete()
		runner.advance()
		view.wait_left = -1.0


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.add_child(Sfx.new())
	view = DialogueView.new()
	root.add_child(view)
	runner = DialogueRunner.new(DialogueScript.load_file("res://data/dialogue/hangar_briefing.dlg"))
	view.play(runner)
	await _wait(0.6)
	_skip_to(func(): return view.line.get("who") == "mira")
	await _wait(1.2)
	await _shot("01_typing_mira")
	_skip_to(func(): return view.line.get("punch", false))
	await _wait(2.5)
	await _shot("02_mira_angry_punch")
	_skip_to(func(): return view.line.get("who") == "noa" and view.line.get("expr") == "skeptical")
	await _wait(3.5)
	await _shot("03_four_people_noa")
	view.jump_to_choice()
	await _wait(0.8)
	await _shot("04_skip_summary")
	view.next()
	await _wait(0.6)
	await _shot("05_choices")
	view._open_log()
	await _wait(0.4)
	await _shot("06_log")
	view.log_layer.visible = false
	view._pick(0)
	_skip_to(func(): return view.line.get("who") == "eirin" and view.line.get("expr") == "vulnerable")
	await _wait(3.0)
	await _shot("07_eirin_vulnerable")
	quit()
