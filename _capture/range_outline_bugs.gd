extends SceneTree
## 벌레 시험장에서 E 조준: 스키닝 몸(애벌레) · GLB 몸(개미·공벌레·촘퍼)에도 외곽선이 몸을 따라가는지
var out := "res://output/range-outline-20261007"

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _run() -> void:
	var main: Main = (load("res://scenes/bugs.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(240)
	var p := main.player
	main.set("god", true)
	var es := Enemy.live(self)
	print("enemies ", es.size())
	var best: Enemy = null
	for e in es:
		if e is BugGrub:
			best = e
	if best == null and es.size() > 0:
		best = es[0]
	var types := {}
	for e in es:
		types[(e as Node).get_script().get_global_name()] = true
	print("types ", types.keys())
	p.global_position = best.global_position + Vector3(-4.0, 0, 3.0)
	for i in 50:
		p.aim_override = Vector3(best.global_position.x, p.global_position.y + 0.95, best.global_position.z)
		if i == 2:
			Input.action_press("rush_skill")
		await physics_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("6_bugs.png"))
	print("marked grub ", RangeOutline.is_marked(best), " count ", RangeOutline.count())
	Input.action_release("rush_skill")
	await _frames(10)
	quit()
