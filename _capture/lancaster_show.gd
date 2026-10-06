extends SceneTree
## LANCASTER 보스 확인 캡처 (허수아비 씬 보스방).
## powershell -File tools\godot.ps1 wait --fixed-fps 60 -s res://_capture/lancaster_show.gd -- --bossroom --out=DIR [--game] [--walk]
##  기본: 보스 옆 가까운 카메라(close)로 기동 · 패턴마다 핵심 프레임 · 광폭화 · 경직 · 정지
##  --game  실제 게임 카메라로 같은 장면
##  --walk  옆걸음 · 대시 연속 프레임 (보행 확인)

var out := "res://output/lancaster-boss-20261006/shots"
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
	main = (load("res://scenes/training.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(3)
	main.god = true
	if not game:
		Main.ui_hidden = true
		main.show_help = false
	p = main.player
	room = main.boss_room
	boss = room.boss
	if not game:
		cam = Camera3D.new()
		cam.fov = 40.0
		main.world.add_child(cam)
		cam.make_current()
	await _shot("dormant")
	await _frames(40)
	await _shot("wake_eyes")
	await _frames(50)
	await _shot("wake_rise")
	await _frames(40)
	await _shot("wake_roar")
	while boss.st != LancasterBoss.St.FIGHT:
		await physics_frame
	# 패턴은 하나씩만 (견제 연사 · 대시 · 자동 선택 없이)
	boss.set_i = 5
	await _frames(30)
	_place_player(8.0, 0.4)
	await _frames(40)
	await _shot("neutral_strafe")
	boss.set_i = 0
	# PINNING BURST
	_place_player(9.0, 0.3)
	_cast("burst")
	if await _wait_phase("burst", "brace"):
		await _frames(25)
		await _shot("burst_brace")
	if await _wait_phase("burst", "fire"):
		await _frames(30)
		await _shot("burst_fire")
	if await _wait_phase("burst", "vent"):
		await _frames(12)
		await _shot("burst_vent")
	# SWEEP
	_place_player(9.0, 0.9)
	_cast("sweep")
	if await _wait_phase("sweep", "track"):
		await _frames(20)
		await _shot("sweep_track")
	if await _wait_phase("sweep", "sweep"):
		await _frames(30)
		await _shot("sweep_fire")
	# CLAW
	_place_player(7.5, 0.2)
	_cast("claw")
	if await _wait_phase("claw", "windup"):
		await _frames(30)
		await _shot("claw_windup")
	while boss.pat == "claw" and not (String(boss.ps.get("ph", "")) in ["lunge", "crush"]):
		await physics_frame
	await _frames(3)
	await _shot("claw_lunge")
	if await _wait_phase("claw", "crush", 2.0):
		await _frames(4)
		await _shot("claw_crush")
	# SLUG
	_place_player(9.0, 0.5)
	_cast("slug")
	if await _wait_phase("slug", "windup"):
		await _frames(40)
		await _shot("slug_windup")
	if await _wait_phase("slug", "after"):
		await _frames(6)
		await _shot("slug_fire")
	# SPIKE
	_place_player(8.0, 0.2)
	_cast("spike")
	if await _wait_phase("spike", "windup"):
		await _frames(20)
		await _shot("spike_windup")
	if await _wait_phase("spike", "hop"):
		await _frames(18)
		await _shot("spike_hop")
	if await _wait_phase("spike", "stuck"):
		await _frames(3)
		await _shot("spike_slam")
	# STOMP
	_place_player(4.0, 0.4)
	_cast("stomp")
	if await _wait_phase("stomp", "lift"):
		await _frames(28)
		await _shot("stomp_lift")
	if await _wait_phase("stomp", "wave"):
		await _frames(8)
		await _shot("stomp_wave")
	# PODS
	_place_player(9.0, 0.6)
	_cast("pods")
	await _frames(25)
	await _shot("pods_lock")
	await _frames(40)
	await _shot("pods_barrage")
	await _frames(50)
	await _shot("pods_impact")
	# OVERDRIVE
	boss.force_phase(2)
	await _frames(55)
	await _shot("overdrive_roar")
	while boss.st != LancasterBoss.St.FIGHT:
		await physics_frame
	await _frames(20)
	await _shot("overdrive_fight")
	# STAGGER
	_place_player(6.0, 0.3)
	boss.stagger((boss.global_position - p.global_position).normalized(), 2.0)
	await _frames(20)
	await _shot("stagger")
	while boss.st == LancasterBoss.St.STAGGER:
		await physics_frame
	# SHUTDOWN
	boss.immortal = false
	boss.take_hit(9999, Vector3.FORWARD, boss.global_position + Vector3(0, 2, 0), "slash")
	await _frames(25)
	await _shot("shutdown_spark")
	await _frames(70)
	await _shot("shutdown_kneel")
	await _frames(120)
	await _shot("shutdown_dead")
	quit()
