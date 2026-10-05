extends SceneTree
## Run with: Godot --headless --path . -s tests/space_sweep_check.gd
## 청소 질주(Space 누른 채) 확인. 전투 테스트장(training.tscn)에 오염(DroneMess)을 직접 뿌리고 실제 입력 액션으로 누른다.
##  1. Space 를 짧게 누르면 평소처럼 대시만 하고 청소기는 나오지 않는다.
##  2. 누른 채로 있으면 대시가 끝난 뒤 청소기를 꺼낸다: 손이 등 뒤로 → 등에 탱크가 나타나고 → 막대를 앞바닥으로 (칼은 숨김).
##     쓸기 루프: 노즐이 앞바닥에 닿아 좌우로 쓸고, 둘레 SWEEP_R 안 오염을 한꺼번에 치운다 (흡입 기류 · 발밑 고리, 범위 밖은 그대로).
##     대시는 한 번만, 질주 중 공격 불가 · 조금 느려짐. 떼면 막대를 등 뒤로 넘기고 탱크가 사라지며 칼이 돌아온다.
##  3. 누른 채 걸어 다니면 앞쪽으로 지나가는 길의 오염이 모두 치워지고 게이지가 찬다.

var fails := 0
var main: TrainingMain
var player: Player
var drone: PartnerDrone
var gear: SweepGear


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _secs(s: float) -> void:
	await _frames(int(ceil(s * 60.0)))


func _clear_mess() -> void:
	for m in root.get_tree().get_nodes_in_group(DroneMess.GROUP):
		(m as DroneMess).dissolve()
	await _frames(30)


func _mess(p: Vector3, i: int) -> DroneMess:
	p.y = Main.gy(p)
	return DroneMess.spawn(main.world, p, DroneMess.Kind.SCRAP if i % 2 == 0 else DroneMess.Kind.GOO, 1.0)


func _flat_d(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _all_done(arr: Array) -> bool:
	return arr.all(func(m): return not is_instance_valid(m) or (m as DroneMess).done)


func _untouched(arr: Array) -> bool:
	return arr.all(func(m): return is_instance_valid(m) and ((m as DroneMess).claim != null or (m as DroneMess).progress() == 0.0))


func _run() -> void:
	var scene: PackedScene = load("res://scenes/training.tscn")
	main = scene.instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(60)
	player = main.player
	drone = PartnerDrone.inst
	main.god = true
	main.infinite = false   # 재화 무한이면 드론 게이지가 늘 가득이라 차오르는 것을 볼 수 없다
	_check(is_instance_valid(drone) and is_instance_valid(drone.gear), "전투 테스트장에 파트너 드론과 청소 장비가 있다")
	if not is_instance_valid(drone):
		quit(1)
		return
	gear = drone.gear
	drone.gauge = 0.0
	for d in main.dummies:
		d.anchor = main.center + Vector3(12, 0, -8)
		d.global_position = d.anchor
	player.global_position = main.center + Vector3(-4, 0, 3)
	await _secs(1.0)

	# ── 1. 짧게 누르면 대시만 ──
	var swept0 := drone.swept
	Input.action_press("dash")
	await _frames(2)
	Input.action_release("dash")
	_check(player.dash_t > 0.0, "짧게 누르면 대시")
	await _secs(0.6)
	_check(not gear.active() and not gear.tank.visible, "짧게 누르면 청소기는 나오지 않는다")

	# ── 2. 누른 채로: 꺼내기 → 쓸기 → 집어넣기 ──
	player.velocity = Vector3.ZERO
	await _secs(0.9)
	var gauge0 := drone.gauge
	Input.action_press("dash")
	await _frames(3)
	_check(player.dash_t > 0.0 and not gear.active(), "누르는 순간은 대시 (대시 중에는 청소기 없음)")
	for i in 60:
		if gear.active():
			break
		await physics_frame
	_check(gear.st == SweepGear.St.DRAW and player.gear_pose.is_valid(), "대시가 끝나면 청소기를 꺼내기 시작한다")
	_check(player.no_attack and player.slow_mul < 1.0, "청소 질주 중 공격 불가 · 조금 느려짐 (%.2f)" % player.slow_mul)
	await _frames(4)
	var ax := (player.j.arm_r as Node3D).rotation.x
	_check(ax > 1.8, "꺼내기: 칼 팔을 어깨 너머 등 뒤로 뻗는다 (팔 %.2f rad)" % ax)
	await _secs(SweepGear.GRAB_T + 0.05)
	var aim := gear.aim
	var back := (gear.tank.global_position - player.global_position)
	back.y = 0
	_check(gear.tank.visible and back.dot(aim) < -0.15, "손이 등에 닿으면 등 뒤에 청소 탱크가 나타난다 (뒤로 %.2fm)" % -back.dot(aim))
	_check(not (player.j.blade as Node3D).visible and gear.wand.visible, "칼은 숨기고 흡입 막대를 쥔다")
	await _secs(SweepGear.DRAW_T)
	_check(gear.st == SweepGear.St.LOOP and gear.sucking(), "꺼내기가 끝나면 쓸기 루프")
	# 둘레 원 안(앞 · 옆 · 뒤 고르게)과 원 밖에 뿌린다
	aim = gear.aim
	var side := aim.cross(Vector3.UP).normalized()
	var g := player.global_position
	var front := []
	for i in 6:
		var a := TAU * i / 6.0 + 0.3
		front.append(_mess(g + (aim * cos(a) + side * sin(a)) * (2.2 if i % 2 == 0 else 3.6), i))
	var outside := []
	for i in 3:
		var a := TAU * i / 3.0 + 1.0
		outside.append(_mess(g + (aim * cos(a) + side * sin(a)) * (PartnerDrone.SWEEP_R + 2.5), i))
	await _frames(6)
	var tip_rel := gear.tip - player.global_position
	_check(gear.tip.y - Main.gy(gear.tip) < 0.3 and tip_rel.dot(aim) > 0.8, "노즐이 앞바닥에 닿는다 (앞 %.2fm · 높이 %.2fm)" % [tip_rel.dot(aim), gear.tip.y - Main.gy(gear.tip)])
	var lo := 99.0
	var hi := -99.0
	var streams_on := 0
	swept0 = drone.swept
	var t := 0
	while not _all_done(front) and t < 150:
		await physics_frame
		t += 1
		var lat := (gear.tip - player.global_position).dot(side)
		lo = minf(lo, lat)
		hi = maxf(hi, lat)
		streams_on = maxi(streams_on, drone.sweep_streams.filter(func(s): return (s as DroneFX.Suction).on > 0.3).size())
	_check(_all_done(front), "둘레 %.1fm 안 오염 %d개(앞 · 옆 · 뒤)를 한꺼번에 치운다 (%.2f초)" % [PartnerDrone.SWEEP_R, front.size(), t / 60.0])
	_check(drone.swept - swept0 >= front.size() - 1, "청소 질주로 치운 수 %d" % (drone.swept - swept0))
	_check(_untouched(outside), "범위 밖 오염은 건드리지 않는다")
	_check(streams_on >= 4, "오염마다 몸으로 빨려 드는 흡입 기류 (%d줄)" % streams_on)
	await _secs(0.7)
	for i in 40:
		await physics_frame
		var lat := (gear.tip - player.global_position).dot(side)
		lo = minf(lo, lat)
		hi = maxf(hi, lat)
	_check(hi - lo > 0.5, "쓸기 루프: 노즐이 좌우로 쓴다 (폭 %.2fm)" % (hi - lo))
	_check(drone.gauge > gauge0, "치운 만큼 지원 게이지가 찬다 (%.0f → %.0f)" % [gauge0, drone.gauge])
	_check(player.dash_t <= 0.0, "누르고 있어도 대시는 한 번만")
	Input.action_release("dash")
	await _frames(3)
	_check(gear.st == SweepGear.St.STOW and not player.no_attack, "떼면 집어넣기 · 다시 공격 가능")
	await _secs(SweepGear.STOW_T + 0.1)
	_check(not gear.active() and not gear.tank.visible and (player.j.blade as Node3D).visible and not player.gear_pose.is_valid(), "집어넣으면 탱크가 사라지고 칼이 돌아온다")
	await _clear_mess()

	# ── 2-2. 바닥 잡조각: 탄피 · 벽/몸체 파편 · 몸체 조각 · 체액 얼룩 · 웅덩이도 전부 빨려 든다 (게이지 없음) ──
	await _secs(0.9)
	Input.action_press("dash")
	for i in 90:
		if drone.sweeping:
			break
		await physics_frame
	await _secs(0.5)                  # 대시 뒤 미끄러짐이 멈춘 자리에서
	g = player.global_position
	var gauge1 := drone.gauge
	var swallowed0 := drone.junk.swallowed
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.2
	for i in 8:
		var a := TAU * i / 8.0
		var inward := -Vector3(cos(a), 0, sin(a))      # 플레이어 쪽으로 튀게 (범위 밖으로 날아가지 않게)
		var p := g + Vector3(cos(a), 0, sin(a)) * (2.0 + (i % 3) * 0.6)
		p.y = Main.gy(p)
		GunFX.eject(p + Vector3(0, 0.6, 0), inward, Vector3.FORWARD)
		if i % 2 == 0:
			GunFX.impact_wall(p + Vector3(0, 0.5, 0), inward, -inward)
		if i % 3 == 0:
			GunFX.impact_body(p + Vector3(0, 0.8, 0), Vector3.FORWARD, Color(0.6, 0.3, 0.8))
		Debris.toss(box, Pal.lit(Color(0.4, 0.4, 0.5)), Transform3D(Basis.IDENTITY, p + Vector3(0, 0.3, 0)), Vector3(0, 1.0, 0), 6.0)
		if i % 2 == 1:
			BugEnemy.splat(p, 1.0, i % 3)
		if i % 4 == 1:
			BugChomper.puddle(p, 0.5)
	var far_p := g + Vector3(PartnerDrone.SWEEP_R + 3.0, 0, 0)
	far_p.y = Main.gy(far_p)
	BugEnemy.splat(far_p, 1.0)
	var near_junk := func() -> int:
		var n := 0
		var lists := [GunFX.inst.casings, GunFX.inst.chips, Debris.inst.pieces]
		for l: Array in lists:
			for pc: Dictionary in l:
				if is_instance_valid(pc.node) and _flat_d((pc.node as Node3D).global_position, player.global_position) < PartnerDrone.SWEEP_R - 0.3:
					n += 1
		for s in root.get_tree().get_nodes_in_group(BugEnemy.SPLAT_GROUP):
			if _flat_d((s as Node3D).global_position, player.global_position) < PartnerDrone.SWEEP_R - 0.3:
				n += 1
		for pd in BugChomper._puddles:
			if is_instance_valid(pd) and _flat_d((pd as Node3D).global_position, player.global_position) < PartnerDrone.SWEEP_R - 0.3:
				n += 1
		return n
	var spawned := GunFX.inst.casings.size() + GunFX.inst.chips.size() + Debris.inst.pieces.size() \
		+ root.get_tree().get_nodes_in_group(BugEnemy.SPLAT_GROUP).size() - 1 + BugChomper._puddles.size()
	var flying := 0
	t = 0
	while (near_junk.call() > 0 or drone.junk.fly.size() > 0) and t < 120:
		await physics_frame
		t += 1
		flying = maxi(flying, drone.junk.fly.size())
	var got := drone.junk.swallowed - swallowed0
	_check(got >= spawned - 3 and got >= 25, "탄피 · 벽/몸체 파편 · 몸체 조각 · 체액 얼룩 · 웅덩이를 빨아들인다 (%d/%d개 · 동시에 %d개가 날아감)" % [got, spawned, flying])
	_check(near_junk.call() == 0 and drone.junk.fly.is_empty(), "둘레 잡조각이 하나도 남지 않는다 (%.2f초)" % (t / 60.0))
	_check(is_equal_approx(drone.gauge, gauge1), "잡조각은 지원 게이지에 들어가지 않는다 (%.0f → %.0f)" % [gauge1, drone.gauge])
	_check(root.get_tree().get_nodes_in_group(BugEnemy.SPLAT_GROUP).size() >= 1, "범위 밖 체액 얼룩은 남는다")
	Input.action_release("dash")
	await _secs(5.5)
	_check(root.get_tree().get_nodes_in_group(BugEnemy.SPLAT_GROUP).is_empty(), "빨아들이지 않은 잡조각은 원래 수명대로 저절로 사라진다")

	# ── 3. 누른 채 걸어 다니며 앞쪽 길 위의 오염을 치운다 ──
	await _secs(0.9)
	# 조준 방향 뒤쪽으로 물려 세워 앞으로 걸어갈 자리를 만든다 (헤드리스에서는 마우스가 고정이라 조준 방향도 거의 고정)
	player.global_position = main.center - gear.aim * 7.0
	player.velocity = Vector3.ZERO
	await _frames(20)
	Input.action_press("dash")
	for i in 90:
		if gear.sucking():
			break
		await physics_frame
	aim = gear.aim
	side = aim.cross(Vector3.UP).normalized()
	g = player.global_position
	var path := []
	for i in 7:
		path.append(_mess(g + aim * (2.0 + i * 1.3) + side * (0.7 if i % 2 == 0 else -0.7), i))
	await _frames(6)
	var start := player.global_position
	swept0 = drone.swept
	# 조준 방향으로 걷는다 (방향키 세기를 나눠 준다)
	Input.action_press("move_right", maxf(aim.x, 0.0))
	Input.action_press("move_left", maxf(-aim.x, 0.0))
	Input.action_press("move_down", maxf(aim.z, 0.0))
	Input.action_press("move_up", maxf(-aim.z, 0.0))
	t = 0
	while not _all_done(path) and t < 60 * 6:
		await physics_frame
		t += 1
	for a in ["move_right", "move_left", "move_down", "move_up", "dash"]:
		Input.action_release(a)
	var moved := player.global_position.distance_to(start)
	_check(_all_done(path), "누른 채 앞으로 걸어가며 길 위 오염 %d개를 모두 치운다 (%.1f초 · %.1fm)" % [path.size(), t / 60.0, moved])
	_check(moved > 3.0, "청소 질주 중에도 걸어 다닐 수 있다 (%.1fm)" % moved)

	print("RESULT %s (%d fails)" % ["OK" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
