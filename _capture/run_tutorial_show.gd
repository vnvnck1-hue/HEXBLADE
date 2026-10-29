extends SceneTree
## 섹터 런 사장 대화형 튜토리얼 화면 확인 캡처 → output/run-tutorial-20261016/
## powershell -File tools\godot.ps1 wait --resolution 1280x800 -s res://_capture/run_tutorial_show.gd
const OUT := "res://output/run-tutorial-20261016/"


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")
	print("SHOT " + name)


func _enter(tut: RunTutorial) -> void:
	tut.skip_step()
	await _frames(2)


## 대사를 넘겨 k단계 해 보기까지
func _to_action(tut: RunTutorial, k: int) -> void:
	for i in 1500:
		if tut.st == RunTutorial.St.ACTION and tut.idx == k:
			return
		if tut.st == RunTutorial.St.SAY:
			if tut.line_done():
				await _enter(tut)
			else:
				await process_frame
			continue
		await process_frame


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	RunTutorial.force = true
	RunTutorial.persist = false
	PlayerEntrance.force = true
	var rs = root.get_node("Run")
	rs.active = false
	change_scene_to_file("res://scenes/run.tscn")
	await _frames(10)
	var m: RunMain = current_scene
	var tut: RunTutorial = m.tutorial
	while tut.st != RunTutorial.St.SAY:
		await process_frame
	await _frames(25)
	await _shot("01_owner_typing")
	while not tut.line_done():
		await process_frame
	await _frames(5)
	await _shot("02_owner_line_done")
	await _to_action(tut, 0)
	await _frames(5)
	await _shot("03_move_action")
	Input.action_press("move_up")
	while not (tut.st == RunTutorial.St.OK and tut.idx == 0):
		await process_frame
	Input.action_release("move_up")
	await _frames(40)
	await _shot("04_move_ok")
	await _to_action(tut, 1)
	await _frames(10)
	var d0: TrainingDummy = tut.dummies[0]
	for i in 5:
		d0.take_hit(1, Vector3.FORWARD, d0.global_position + Vector3(0, 1, 0), "bullet")
		await _frames(4)
	await _shot("05_shoot_progress")
	for i in 3:
		d0.take_hit(1, Vector3.FORWARD, d0.global_position + Vector3(0, 1, 0), "bullet")
		await _frames(2)
	await _to_action(tut, 2)
	await _frames(3)
	await _shot("06_sword_action")
	# 나머지는 건너뛰어 설명 대사까지
	for k in range(2, 8):
		await _to_action(tut, k)
		await _enter(tut)
	while not (tut.st == RunTutorial.St.SAY and tut.idx == 8 and tut.line_done()):
		await process_frame
	await _frames(5)
	await _shot("07_rules_line1")
	# 설명 대사는 3줄: 마지막 줄까지 넘긴다
	while not tut._lines.is_empty():
		await _enter(tut)
		while not tut.line_done():
			await process_frame
	await _frames(5)
	await _shot("08_rules_last")
	await _enter(tut)
	await _frames(70)
	await _shot("09_portals")
	quit()
