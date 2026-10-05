extends SceneTree
## 땅굴크루식 데미지 로그 확인 캡처 (docs/damage-log.md). 허수아비 둘에 연사·강타를 넣고 몇 장 찍는다.
## powershell -File tools\godot.ps1 wait --resolution 1280x800 -s res://_capture/damage_log_show.gd -- --seed=4 [--dmglog=bounce]
## (BOUNCE 는 파일 이름 앞에 bounce_)
const OUT := "res://output/damage-log-20261004/"

var main: Main


func _initialize() -> void:
	_run.call_deferred()


var pins: Array = []


func _frames(n: int) -> void:
	for i in n:
		await process_frame
		for d: TrainingDummy in pins:      # 넉백으로 밀려나지 않게 제자리
			d.global_position = d.anchor


func _shot(name: String) -> void:
	print(name, " numbers=", MocoFX.get_inst().live_numbers())
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	img.save_png(OUT + ("" if DamageLog.preset == "stack" else DamageLog.preset + "_") + name + ".png")


func _dummy(at: Vector3) -> Enemy:
	var e := TrainingDummy.new()
	e.anchor = main.map.push_out(at, 1.0)
	e.immortal = true
	main.world.add_child(e)
	e.global_position = e.anchor
	pins.append(e)
	return e


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(40)
	main = current_scene as Main
	main.player.invuln = 9999.0
	main.hud.visible = false
	var c := main.player.global_position
	var d1 := _dummy(c + Vector3(3.2, 0, -0.6))
	var d2 := _dummy(c + Vector3(-3.0, 0, -0.4))
	await _frames(90)
	main.camera.snap(c)
	var dir := Vector3(1, 0, -0.2).normalized()
	# 1) 기관총 연사 — 0.1초마다 1~3 피해
	var shot_i := 0
	for i in 40:
		if i % 6 == 0:
			d1.take_hit(randi_range(1, 3), dir, d1.global_position + Vector3(-0.3, 1.0, 0.2), "bullet")
		if i == 30 or i == 34 or i == 38:
			await _shot("gun_%d" % shot_i)
			await _frames(1)
			shot_i += 1
		else:
			await _frames(1)
	# 2) 검 강타
	d2.take_hit(4, -dir, d2.global_position + Vector3(0.3, 1.0, 0.2), "slash")
	await _shot("heavy_0")
	await _frames(4)
	await _shot("heavy_1")
	await _frames(6)
	await _shot("heavy_2")
	# 3) 섞어서
	for i in 30:
		if i % 4 == 0:
			d1.take_hit(randi_range(1, 3), dir, d1.global_position + Vector3(-0.3, 1.0, 0.2), "bullet")
		if i % 12 == 0:
			d2.take_hit(randi_range(4, 9), -dir, d2.global_position + Vector3(0.3, 1.0, 0.2), "slash")
		await _frames(1)
	await _shot("mix")
	d2.stagger(Vector3(1, 0, 0), 1.1)
	await _frames(8)
	await _shot("stun")
	# 4) 연속 타격 열기: 한 대상을 0.12초마다 20번 (끊김 없이)
	await _frames(90)
	for i in 20:
		d1.take_hit(randi_range(1, 3) if i % 5 != 4 else randi_range(4, 6), dir, d1.global_position + Vector3(-0.3, 1.0, 0.2), "bullet" if i % 5 != 4 else "slash")
		if i in [2, 6, 10, 14, 19]:
			await _frames(4)            # 팝이 가라앉은 뒤 (생긴 직후 한 프레임은 크게 튐)
			await _shot("chain_%02d" % (i + 1))
			await _frames(2)
		else:
			await _frames(7)
	quit()
