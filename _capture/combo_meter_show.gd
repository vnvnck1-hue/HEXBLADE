extends SceneTree
## 타격 콤보 점수(ComboMeter) 확인 캡처. 허수아비에 연타를 넣으며 타격 직후·랭크 상승·정산·끊김을 찍는다.
## powershell -File tools\godot.ps1 wait --resolution 1280x800 -s res://_capture/combo_meter_show.gd
const OUT := "res://output/combo-meter-20261005/"

var main: Main
var dummy: TrainingDummy


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame
		if dummy:
			dummy.global_position = dummy.anchor


func _wait(sec: float) -> void:
	var until := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < until:
		await _frames(1)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	img.save_png(OUT + name + ".png")
	print("shot ", name, " hits=", ComboMeter.inst.hits, " score=", ComboMeter.inst.combo_score)


func _hit(dmg: int, src := "bullet") -> void:
	dummy.take_hit(dmg, Vector3(1, 0, 0), dummy.global_position + Vector3(-0.3, 1.0, 0.2), src)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(40)
	main = current_scene as Main
	main.player.invuln = 9999.0
	var c := main.player.global_position
	dummy = TrainingDummy.new()
	dummy.anchor = main.map.push_out(c + Vector3(3.2, 0, -0.6), 1.0)
	dummy.immortal = true
	main.world.add_child(dummy)
	dummy.global_position = dummy.anchor
	await _frames(90)
	# 1) 연사 → 4타 직후, 1프레임 뒤, 6프레임 뒤 (팝 → 찌그러짐 → 자리)
	for i in 4:
		_hit(1)
		await _frames(6)
	_hit(2)
	await _shot("01_hit_f0")
	await _frames(2)
	await _shot("02_hit_f2")
	await _frames(5)
	await _shot("03_hit_f7")
	await _frames(14)
	await _shot("04_settled")
	# 2) 랭크 NICE → GOOD 직후
	for i in 9:
		_hit(1)
		await _frames(4)
	_hit(5, "slash")
	await _frames(1)
	await _shot("05_rank_good_f1")
	await _frames(5)
	await _shot("06_rank_good_f6")
	# 3) 길게 이어서 GREAT · AWESOME
	for i in 40:
		_hit(randi_range(1, 4), "slash" if i % 7 == 0 else "bullet")
		await _frames(3)
	await _frames(10)
	await _shot("07_awesome")
	# 4) 창이 지나 정산
	while ComboMeter.inst.phase == ComboMeter.Phase.LIVE:
		await _frames(1)
	await _frames(2)
	await _shot("08_finish")
	await _wait(0.35)
	await _shot("09_finish_late")
	await _wait(1.0)
	# 5) 끊김
	for i in 18:
		_hit(1)
		await _frames(3)
	main.on_player_hurt()
	await _frames(3)
	await _shot("10_break")
	await _wait(0.3)
	await _shot("11_break_late")
	quit()
