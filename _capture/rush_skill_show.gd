extends SceneTree
## 돌진 스킬(E) 확인 캡처: 전투 테스트장에서 E 를 눌러 인디케이터를 띄운 화면 → 떼서 돌진하는 화면을 저장한다.
## godot --path . -s _capture/rush_skill_show.gd -- --out=DIR

var out := "res://output/rush-skill-20261002"
var main: TrainingMain


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", name)


func _run() -> void:
	main = (load("res://scenes/training.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(40)
	var p := main.player
	main.god = true
	# 조준: 화면 오른쪽 위 방향으로 마우스를 둔다
	var vp := root.get_visible_rect().size
	Input.warp_mouse(vp * Vector2(0.72, 0.3))
	await _frames(10)
	Input.action_press("rush_skill")
	await _frames(4)
	await _shot("0_deploy")
	await _frames(16)
	await _shot("1_aim")
	Input.warp_mouse(vp * Vector2(0.3, 0.62))
	await _frames(10)
	await _shot("2_aim_other_dir")
	Input.action_release("rush_skill")
	await _frames(4)
	await _shot("3_rush")
	await _frames(20)
	await _shot("4_cooldown")
	print("skill_cd=%.2f" % p.tech.skill_cd)
	quit()
