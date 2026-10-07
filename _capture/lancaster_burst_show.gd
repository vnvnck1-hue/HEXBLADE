extends SceneTree
## LANCASTER 개틀링 연사(PINNING BURST · 휩쓸기) 캡처 — UI 전부 끔 (HUD · 패널 · 보스 체력바 · 피해 숫자).
## powershell -File tools\godot.ps1 wait --fixed-fps 60 -s res://_capture/lancaster_burst_show.gd -- --bossroom --out=DIR
## 게임 카메라 그대로 + 가까운 카메라 몇 장.

var out := "res://output/lancaster-burst-20261007"
var main: TrainingMain
var room: TrainingBossRoom
var boss: LancasterBoss
var p: Player
var n := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _frames(k: int) -> void:
	for i in k:
		await physics_frame


func _hide_ui() -> void:
	Main.ui_hidden = true
	main.show_help = false
	main._apply_ui()
	if is_instance_valid(room.bar):
		room.bar.visible = false


func _shot(name: String) -> void:
	_hide_ui()
	await process_frame
	await RenderingServer.frame_post_draw
	n += 1
	root.get_texture().get_image().save_png(out.path_join("%02d_%s.png" % [n, name]))
	print("saved ", name)


func _place_player(dist: float, ang: float) -> void:
	var q := boss.global_position + Vector3(cos(ang), 0, sin(ang)) * dist
	var r := room.rect.grow(-1.5)
	q.x = clampf(q.x, r.position.x, r.end.x)
	q.z = clampf(q.z, r.position.y, r.end.y)
	p.global_position = main.map.push_out(q, 0.6)
	p.velocity = Vector3.ZERO


func _cast(id: String) -> void:
	boss._end_pattern(false)
	boss.force_next = id
	boss.rest = 0.0


func _wait_phase(id: String, ph: String) -> void:
	for i in 600:
		if boss.pat == id and String(boss.ps.get("ph", "")) == ph:
			return
		await physics_frame
	print("TIMEOUT ", id, " ", ph)


func _idle() -> void:
	while boss.pat != "":
		await physics_frame
	boss.rest = 99.0
	boss.pin_cd = 99.0


func _run() -> void:
	main = (load("res://scenes/training.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(3)
	main.god = true
	p = main.player
	room = main.boss_room
	boss = room.boss
	_hide_ui()
	while boss.st != LancasterBoss.St.FIGHT:
		await physics_frame
	boss.set_i = 1          # 제압 사격 세트 (burst · sweep 이 들어 있어야 강제 시전이 먹는다)
	boss.rest = 99.0
	await _frames(30)
	# 제압 연사 — 게임 카메라
	boss.pin_cd = 99.0
	_place_player(8.5, 0.5)
	await _frames(40)
	_cast("burst")
	await _wait_phase("burst", "fire")
	for i in 6:
		await _frames(9)
		await _shot("burst_game_%d" % i)
	await _wait_phase("burst", "vent")
	await _frames(10)
	await _shot("burst_vent_game")
	# 휩쓸기 — 게임 카메라
	await _idle()
	_place_player(9.0, 1.2)
	await _frames(30)
	_cast("sweep")
	await _wait_phase("sweep", "sweep")
	for i in 3:
		await _frames(14)
		await _shot("sweep_game_%d" % i)
	# 제압 연사 — 가까운 카메라 (보스 옆 앞에서)
	await _idle()
	_place_player(8.5, 0.2)
	await _frames(40)
	var cam := Camera3D.new()
	cam.fov = 38.0
	main.world.add_child(cam)
	_cast("burst")
	await _wait_phase("burst", "fire")
	cam.make_current()
	for i in 6:
		await _frames(7)
		var b := boss.global_position
		var to := p.global_position - b
		to.y = 0
		var side := Vector3(-to.z, 0, to.x).normalized()
		if side.z < 0.0:
			side = -side
		# 보스 앞 비스듬히: 보스를 화면 왼쪽 1/3, 총구 불꽃과 날아가는 예광탄이 오른쪽으로
		var fwd := to.normalized()
		var look := b + Vector3(0, 1.7, 0) + fwd * 2.6
		cam.global_position = b + fwd * 5.0 + side * 7.5 + Vector3(0, 3.6, 0)
		cam.look_at(look, Vector3.UP)
		await _shot("burst_close_%d" % i)
	quit()
