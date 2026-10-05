extends SceneTree
## 파트너 드론 근접 캡처: 실제 시험장(DroneLab)을 적 없이 열고, 각본대로 드론의 모든 행동을 차례로 일으키며 프레임을 저장한다.
## 실행: powershell -File tools\godot.ps1 wait --fixed-fps 30 -s res://_capture/drone_show.gd -- --out=<폴더> [--every=3] [--zoom=1]
## 결과: <폴더>/f_0001.png … · beats.txt (프레임 번호 · 장면 이름 · 드론 상태)

var out := ""
var every := 3
var zoom := 1.0
var lab: DroneLab
var drone: PartnerDrone
var cam: Camera3D
var t := 0.0
var frame := 0
var beat := -1
var log_lines: PackedStringArray = []
var cam_pos := Vector3.ZERO
var cam_look := Vector3.ZERO

## [시작 시각, 이름]
const BEATS := [
	[0.0, "등장 (하늘에서 착지)"],
	[2.2, "따라 걷기"],
	[6.5, "잔해 청소"],
	[11.5, "체액 청소"],
	[16.0, "적탄 회피"],
	[18.0, "피격 휘청"],
	[20.0, "합체 비행 · 합체"],
	[23.0, "합체 보조 사격"],
	[26.0, "트리플 볼텍스"],
	[28.5, "분리 착지"],
	[31.0, "돌파 보호막"],
	[34.0, "플레이어 직접 청소"],
	[38.0, "가만히 서서 자동 청소"],
	[41.5, "Q → 합체 + 휠윈드"],
	[45.0, "응원 · 대기 두리번"],
	[48.0, "끝"],
]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--every="):
			every = int(a.substr(8))
		elif a.begins_with("--zoom="):
			zoom = float(a.substr(7))
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _run() -> void:
	lab = load("res://scenes/drone.tscn").instantiate()
	lab.spawning = false
	root.add_child(lab)
	current_scene = lab
	await physics_frame
	lab.spawning = false
	for m in get_nodes_in_group(DroneMess.GROUP):
		m.queue_free()
	drone = PartnerDrone.inst
	cam = Camera3D.new()
	cam.fov = 32
	lab.add_child(cam)
	cam.current = true
	cam_pos = lab.player.global_position + Vector3(0, 6, 7)
	cam_look = lab.player.global_position
	process_frame.connect(_tick)


func _press(a: String, on: bool) -> void:
	if on:
		Input.action_press(a)
	else:
		Input.action_release(a)


func _tick() -> void:
	var dt := 1.0 / 30.0
	t += dt
	var p := lab.player
	var nb := beat
	for i in BEATS.size():
		if t >= float(BEATS[i][0]):
			nb = i
	if nb != beat:
		beat = nb
		_enter(beat)
	_during(beat, t - float(BEATS[beat][0]))
	# 카메라: 드론과 플레이어 사이를 비스듬히 내려다본다
	var focus := drone.global_position.lerp(p.global_position, 0.35) + Vector3(0, 0.6, 0)
	cam_look = cam_look.lerp(focus, 0.12)
	var want := cam_look + Vector3(-3.2, 4.2, 5.2) / zoom
	cam_pos = cam_pos.lerp(want, 0.1)
	cam.global_position = cam_pos
	cam.look_at(cam_look)
	frame += 1
	if frame % every == 0:
		var img := root.get_viewport().get_texture().get_image()
		var n := frame / every
		img.save_png("%s/f_%04d.png" % [out, n])
		log_lines.append("%d\t%.2f\t%s\t%s" % [n, t, BEATS[beat][1], drone.status_text()])
	if beat == BEATS.size() - 1:
		var f := FileAccess.open(out + "/beats.txt", FileAccess.WRITE)
		f.store_string("\n".join(log_lines))
		f.close()
		print("DRONE_SHOW_OK whirls=%d spent=%.0f frames=%d cleaned=%d dodges=%d hits=%d docks=%d vortex=%d shields=%d blocks=%d player=%d" % [drone.whirls, drone.spent, frame / every, drone.cleaned, drone.dodges, drone.hits_taken, drone.docks, drone.vortex_used, drone.shields_used, drone.blocks, drone.player_cleaned])
		quit()


func _mess(at: Vector3, goo: bool) -> void:
	var q := lab.map.push_out(at, 0.8)
	q.y = Main.gy(q)
	DroneMess.spawn(lab.world, q, DroneMess.Kind.GOO if goo else DroneMess.Kind.SCRAP, 1.1, BugEnemy.GOO[0])


func _enter(i: int) -> void:
	var p := lab.player
	var c := lab.center
	match i:
		2:
			_mess(drone.global_position + Vector3(-2.0, 0, -1.5), false)
			_mess(drone.global_position + Vector3(-3.2, 0, 0.5), false)
		3:
			_mess(drone.global_position + Vector3(1.5, 0, -2.2), true)
		4:
			var o := drone.global_position + Vector3(6, 0.6, 0)
			lab.add_bullet(Bullet.make_enemy(o, (drone.global_position + Vector3(0, 0.6, 0) - o).normalized(), 9.0))
		5:
			drone._dodge_cd = 99.0
			var o := drone.global_position + Vector3(-5, 0.6, 1)
			lab.add_bullet(Bullet.make_enemy(o, (drone.global_position + Vector3(0, 0.6, 0) - o).normalized(), 9.0))
		6:
			drone._dodge_cd = 0.0
			drone.toggle_link()
		7:
			var e := Enemy.new()
			e.fire_timer = 99.0
			lab.world.add_child(e)
			e.global_position = lab.map.push_out(p.global_position + Vector3(0, 0, -7), 1.0)
		8:
			drone.gauge = PartnerDrone.GAUGE_MAX
			_mess(p.global_position + Vector3(2.5, 0, 1.5), false)
			_mess(p.global_position + Vector3(-2.0, 0, 2.5), true)
			drone.use_skill()
		9:
			drone.toggle_link()
		10:
			drone.gauge = PartnerDrone.GAUGE_MAX
			drone.use_skill()
			var o := p.global_position + Vector3(5, 0.95, 0)
			get_tree_timer(1.0, func(): lab.add_bullet(Bullet.make_enemy(o, (p.global_position + Vector3(0, 0.95, 0) - o).normalized(), 8.0)))
		11:
			for k in 3:
				_mess(p.global_position + Vector3(-0.8 + k * 0.8, 0, -1.0), k == 1)
			lab.god = true
		12:
			_press("drone_clean", false)
			drone._go(PartnerDrone.St.DOWN)
			for k in 2:
				_mess(p.global_position + Vector3(1.4 - k * 2.8, 0, 0.9), k == 1)
		13:
			drone._go(PartnerDrone.St.FOLLOW)
			drone.gauge = PartnerDrone.GAUGE_MAX
			for k in 3:
				var e := Enemy.new()
				e.fire_timer = 99.0
				lab.world.add_child(e)
				e.global_position = lab.map.push_out(p.global_position + Vector3(cos(k * 2.1), 0, sin(k * 2.1)) * 2.6, 1.0)
		14:
			drone._go(PartnerDrone.St.CHEER)


func get_tree_timer(sec: float, f: Callable) -> void:
	create_timer(sec, false).timeout.connect(f)


func _during(i: int, bt: float) -> void:
	var p := lab.player
	_press("move_up", false)
	_press("move_left", false)
	_press("move_right", false)
	_press("move_down", false)
	match i:
		1:
			# 원을 그리며 걷는다 → 드론이 종종걸음으로 따라온다
			var a := bt * 1.1
			_press("move_up" if cos(a) > 0.3 else ("move_down" if cos(a) < -0.3 else "move_left"), true)
			if sin(a) > 0.3:
				_press("move_right", true)
		7:
			_press("move_left" if fmod(bt, 2.0) < 1.0 else "move_right", true)
		13:
			_press("drone_link", bt < 0.05)
			if bt > 0.45 and bt < 2.4:
				_press("move_right" if bt < 1.4 else "move_up", true)
		11:
			_press("drone_clean", true)
			# 오염 쪽을 바라보게 조준점을 둔다 (마우스 대신)
			p.aim_dir = Vector3(0, 0, -1)
		_:
			pass
	if i == 11:
		p.aim_point = p.global_position + Vector3(0, 0, -3)
