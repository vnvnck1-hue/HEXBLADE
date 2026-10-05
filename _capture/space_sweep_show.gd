extends SceneTree
## 청소 질주(Space 누른 채) 확인 캡처: 전투 테스트장에 오염을 뿌리고 Space 를 누른 채 찍는다.
## 꺼내기(등 뒤로 손 뻗기 → 탱크 등장 → 막대 내려 꽂기) · 쓸기 루프 · 걸으며 쓸기 · 집어넣기를 전체 화면과
## 플레이어 주변 확대본(zoom_*)으로 저장한다.
## godot --path . -s _capture/space_sweep_show.gd -- [--out=DIR]

const CROP := Vector2i(520, 440)

var out := "res://output/space-sweep-20261004"
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


func _shot(name: String, zoom := true) -> void:
	paused = true
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	if zoom:
		var p := main.player
		var c := main.camera.unproject_position(p.global_position + Vector3(0, 0.9, 0) + PartnerDrone.inst.gear.aim * 0.6)
		var r := Rect2i(Vector2i(c) - CROP / 2, CROP)
		r.position = r.position.clamp(Vector2i.ZERO, img.get_size() - CROP)
		img.get_region(r).save_png(out.path_join("zoom_" + name + ".png"))
	paused = false
	var g := PartnerDrone.inst.gear
	print("saved %s  st=%s t=%.2f sweeping=%s" % [name, SweepGear.St.keys()[g.st], g.t, PartnerDrone.inst.sweeping])


## 꺼내기 시작 뒤 x 초가 될 때까지
func _until_t(x: float) -> void:
	var g := PartnerDrone.inst.gear
	for i in 60:
		if g.st != SweepGear.St.DRAW or g.t >= x:
			return
		await physics_frame


func _run() -> void:
	main = (load("res://scenes/training.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(60)
	main.god = true
	var p := main.player
	var gear := PartnerDrone.inst.gear
	for d in main.dummies:
		d.anchor = main.center + Vector3(12, 0, -8)
		d.global_position = d.anchor
	p.global_position = main.center + Vector3(-9, 0, 2)
	await _frames(60)
	# 오른쪽으로 이어진 오염 들판
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 18:
		var pos := p.global_position + Vector3(rng.randf_range(3.5, 15.0), 0, rng.randf_range(-2.6, 2.6))
		pos.y = Main.gy(pos)
		DroneMess.spawn(main.world, pos, DroneMess.Kind.GOO if i % 3 == 0 else DroneMess.Kind.SCRAP, rng.randf_range(0.9, 1.3))
	# 잡조각: 탄피 · 벽 파편 · 체액 얼룩 (청소 질주 때 함께 빨려 든다, 게이지 없음)
	for i in 50:
		var pos := p.global_position + Vector3(rng.randf_range(1.0, 15.0), 0, rng.randf_range(-3.0, 3.0))
		pos.y = Main.gy(pos)
		var out_d := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
		GunFX.eject(pos + Vector3(0, 0.4, 0), out_d, Vector3.FORWARD)
		if i % 3 == 0:
			GunFX.impact_wall(pos + Vector3(0, 0.4, 0), out_d, -out_d)
		if i % 5 == 0:
			BugEnemy.splat(pos, rng.randf_range(0.8, 1.4), i % 3)
	await _frames(40)
	var aim_at := func(): Input.warp_mouse(main.camera.unproject_position(p.global_position + Vector3(6, 0, 0)))
	aim_at.call()
	await _frames(6)
	await _shot("0_before", false)
	Input.action_press("dash")
	for i in 90:
		aim_at.call()
		await physics_frame
		if p.dash_t <= 0.0 and gear.st == SweepGear.St.DRAW:
			break
	await _until_t(0.05)
	await _shot("1_draw_reach")
	await _until_t(0.11)
	await _shot("2_draw_tank")
	await _until_t(0.17)
	await _shot("3_draw_plant")
	for i in 30:
		aim_at.call()
		await physics_frame
	await _shot("4_loop_a")
	await _frames(15)
	await _shot("5_loop_b")
	Input.action_press("move_right")
	for i in 40:
		aim_at.call()
		await physics_frame
	await _shot("6_walk_sweep")
	for i in 40:
		aim_at.call()
		await physics_frame
	await _shot("7_walk_sweep_on")
	Input.action_release("move_right")
	Input.action_release("dash")
	await _frames(6)
	await _shot("8_stow")
	await _frames(30)
	await _shot("9_after", false)
	quit()
