extends SceneTree
## LANCASTER 패링 공격 임팩트 스윙 프레임 단위 캡처: 찌르기 · 내려찍기 · 휘둘러 베기가 닿는 순간 앞뒤 프레임 + 패링 튕김.
## (lancaster_show.gd 와 같은 카메라 · 인자)
## powershell -File tools\godot.ps1 wait --fixed-fps 60 -s res://_capture/lancaster_show.gd -- --bossroom --out=DIR [--game] [--walk]
##  기본: 보스 옆 가까운 카메라(close)로 기동 · 패턴마다 핵심 프레임 · 광폭화 · 경직 · 정지
##  --game  실제 게임 카메라로 같은 장면
##  --walk  옆걸음 · 대시 연속 프레임 (보행 확인)

var out := "res://output/lancaster-boss-20261006/swing"
var main: TrainingMain
var room: TrainingBossRoom
var boss: LancasterBoss
var p: Player
var cam: Camera3D
var game := false
var n := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--game":
			game = true
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _frames(k: int) -> void:
	for i in k:
		await physics_frame


func _shot(name: String) -> void:
	_aim_cam()
	await process_frame
	await RenderingServer.frame_post_draw
	n += 1
	root.get_texture().get_image().save_png(out.path_join("%02d_%s.png" % [n, name]))
	print("saved ", name)


## 가까운 카메라: 보스 앞 왼쪽 위에서 보스와 플레이어를 함께
func _aim_cam() -> void:
	if game or cam == null or not is_instance_valid(boss):
		return
	var b := boss.global_position
	var to := p.global_position - b
	to.y = 0
	var mid := b.lerp(p.global_position, 0.3) + Vector3(0, 1.6, 0)
	var side := Vector3(-to.z, 0, to.x).normalized() if to.length() > 0.1 else Vector3.RIGHT
	if side.z < 0.0:
		side = -side          # 늘 화면 앞(+Z) 쪽에서 본다
	cam.global_position = mid + side * 13.0 + Vector3(0, 6.5, 0)
	cam.look_at(mid, Vector3.UP)
	cam.look_at(mid, Vector3.UP)


func _wait_phase(id: String, ph: String, limit := 6.0) -> bool:
	var tt := 0.0
	while tt < limit:
		if boss.pat == id and String(boss.ps.get("ph", "")) == ph:
			return true
		await physics_frame
		tt += 1.0 / 60.0
	print("timeout ", id, " ", ph)
	return false


func _cast(id: String) -> void:
	boss.force_next = id
	boss.rest = 0.0
	if boss.pat != "" and boss.pat != id:
		boss._end_pattern(false)
		boss.force_next = id
		boss.rest = 0.0


func _place_player(dist: float, ang := 0.6) -> void:
	var b := boss.global_position
	var d := Vector3(cos(ang), 0, sin(ang))
	var q := b + d * dist
	var r := room.rect.grow(-1.5)
	q.x = clampf(q.x, r.position.x, r.end.x)
	q.z = clampf(q.z, r.position.y, r.end.y)
	p.global_position = main.map.push_out(q, 0.6)
	p.velocity = Vector3.ZERO


func _run() -> void:
	LancasterIntro.enabled = false
	main = (load("res://scenes/training.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(3)
	main.god = true
	Main.ui_hidden = true
	main.show_help = false
	p = main.player
	room = main.boss_room
	boss = room.boss
	cam = Camera3D.new()
	cam.fov = 34.0
	main.world.add_child(cam)
	cam.make_current()
	while boss.st != LancasterBoss.St.FIGHT:
		await physics_frame
	boss.set_i = 4
	for kind in ["thrust", "smash", "swipe", "parry"]:
		await _frames(30)
		while boss.pat != "":
			await physics_frame
		_place_player(7.0, 0.35)
		_cast("claw")
		await _wait_phase("claw", "windup")
		boss.ps.kinds = ["thrust" if kind == "parry" else kind, "smash"]
		boss.ps.total = 2
		while not (boss.pat == "claw" and String(boss.ps.get("ph", "")) == "strike"):
			await physics_frame
		# 닿기 몇 프레임 전부터 프레임마다
		while boss.pat == "claw" and String(boss.ps.get("ph", "")) == "strike" and boss.parry_eta() > 0.1:
			await physics_frame
		for f in 10:
			if kind == "parry" and Parry.inst.best_threat() == boss and f >= 1:
				Parry.inst.try_parry(p)
			await _shot("%s_f%02d" % [kind, f])
			await physics_frame
	quit()
