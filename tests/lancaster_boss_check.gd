extends SceneTree
## Run with: Godot --headless --path . -s tests/lancaster_boss_check.gd
## 허수아비 씬 왼쪽 보스 체험방 · LANCASTER 보스 확인.
##  1. 홀 왼쪽에 보스방이 있고 보스는 정지(무릎 꿇음) 상태로 기다린다. 보스 키는 플레이어 메카의 약 두 배.
##  2. 방에 들어가면 패널이 보스 프리셋으로 바뀌고 보스가 기동해 싸운다. 나오면 허수아비 패널로 돌아간다.
##  3. 하체 · 상체 분리: 상체는 조준 쪽으로 비틀리고 하체(몸 yaw)는 그대로. 걸으면 발이 번갈아 디디고 디딘 발은 바닥에 붙어 있다.
##  4. 근접 패링(집게 돌진)이 패링되면 경직, 원거리 패링(중탄)은 ParryOrb 로 나간다. 예광탄은 플레이어를 맞힌다.
##  5. 체력 50% 에서 광폭화(2페이즈), 쓰러지면 정지 연출 뒤 다시 기동. 프리셋 키(세트 · 크기 · 행동 정지).

var fails := 0
var main: TrainingMain
var room: TrainingBossRoom
var p: Player


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


func _panel_text() -> String:
	var s := ""
	for l in main.panel.find_children("*", "Label", true, false):
		s += (l as Label).text + "\n"
	return s


func _height(n: Node3D) -> float:
	var lo := INF
	var hi := -INF
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if not mi.visible or mi.mesh == null:
			continue
		var ab := mi.global_transform * mi.get_aabb()
		lo = minf(lo, ab.position.y)
		hi = maxf(hi, ab.end.y)
	return hi - lo


func _boss() -> LancasterBoss:
	return room.boss


func _wait(cond: Callable, limit: float) -> bool:
	var tt := 0.0
	while tt < limit:
		if cond.call():
			return true
		await physics_frame
		tt += 1.0 / 60.0
	return false


func _cast(id: String) -> void:
	var b := _boss()
	b._end_pattern(false)
	b.force_next = id
	b.rest = 0.0


func _put_player(dist: float) -> void:
	var b := _boss()
	var r := room.rect.grow(-2.0)
	var q := b.global_position + Vector3(dist, 0, 0)
	if not r.has_point(Vector2(q.x, q.z)):
		q = b.global_position - Vector3(dist, 0, 0)
	p.global_position = q
	p.velocity = Vector3.ZERO


func _run() -> void:
	main = (load("res://scenes/training.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(20)
	p = main.player
	main.god = true
	room = main.boss_room

	# 1. 방 · 정지 상태 · 크기
	_check(room != null and room.room_id >= 0, "허수아비 씬에 보스방이 있다")
	if room == null:
		quit(1)
		return
	_check(room.rect.end.x < main.center.x - 10.0, "보스방은 홀 왼쪽 (방 오른쪽 끝 %.1f < 홀 가운데 %.1f)" % [room.rect.end.x, main.center.x])
	var corridor := main.map.is_blocked(Vector3(room.rect.end.x + 3.0, 0, room.center.z))
	_check(not corridor, "홀과 보스방 사이 통로가 뚫려 있다")
	var b := _boss()
	_check(b.st == LancasterBoss.St.DORMANT and b.is_boss, "들어가기 전엔 정지(DORMANT) · is_boss")
	_check(_panel_text().contains("TRAINING") and not _panel_text().contains("BOSS ROOM"), "방 밖에서는 허수아비 패널")
	var bh := _height(b.rig.model)
	b.rig.kneel = 0.0
	b.st = LancasterBoss.St.FIGHT
	b.hold_ai = true
	b._cur.kneel = 0.0
	b._cur.lean = 0.0
	await _frames(40)
	bh = _height(b.rig.model)
	var ph := _height(p.visual)
	_check(ph > 1.3 and bh / ph > 1.75 and bh / ph < 2.25, "보스 키 %.2fm = 플레이어 %.2fm × %.2f (두 배)" % [bh, ph, bh / ph])
	room._spawn()
	b = _boss()
	await _frames(5)

	# 2. 입장 → 패널 · 기동
	p.global_position = room.door + Vector3(-1.0, 0, 0)
	await _frames(4)
	_check(room.inside, "입구에 서면 보스방 안")
	_check(_panel_text().contains("BOSS ROOM") and _panel_text().contains("패턴 세트"), "패널이 보스 프리셋으로 바뀐다")
	_check(await _wait(func(): return b.st == LancasterBoss.St.FIGHT, 4.0), "기동 연출 뒤 전투 시작")

	# 3. 상체 · 하체 분리
	b.hold_ai = true
	b.set_i = 5
	await _frames(30)
	var legs_yaw := b.rotation.y
	b.aim_yaw = legs_yaw + 0.9
	for i in 30:
		b.aim_yaw = legs_yaw + 0.9
		b.rig.aim_yaw = b.aim_yaw
		b.rig.update(1.0 / 60.0)
	_check(absf(wrapf(b.rig.twist - 0.9, -PI, PI)) < 0.15 and absf(wrapf(b.rotation.y - legs_yaw, -PI, PI)) < 0.05, "상체만 0.9rad 비틀림 (twist %.2f, 하체 그대로)" % b.rig.twist)
	_check(b.rig.torso.get_parent() == b.rig.pelvis and b.rig.node("thigh_l").get_parent() == b.rig.pelvis, "torso 와 다리는 골반 아래 따로")
	# 걷기: 행동 정지를 풀고 이동만 → 발이 디딘다
	b.hold_ai = false
	_put_player(8.0)
	var steps := 0
	var max_foot := 0.0
	for i in 150:
		await physics_frame
		steps += b.rig.stepped
		for s in ["l", "r"]:
			var L: Dictionary = b.rig.legs[s]
			if not L.stepping and b.dash_t <= 0.0 and b.rig.air < 0.05:
				var fy: float = b.rig.at("pt_foot_" + s).y
				max_foot = maxf(max_foot, fy)
	_check(steps >= 4, "옆걸음 2.5초에 %d 걸음" % steps)
	_check(max_foot < 0.2, "디딘 발은 바닥에 붙어 있다 (분사 대시 밖, 발바닥 최고 %.2fm)" % max_foot)

	# 4. 패링 · 예광탄
	b.set_i = 0
	_put_player(7.0)
	_cast("claw")
	var t0 := Main.inst.time
	var opened := await _wait(func(): return Parry.inst.best_threat() == b, 4.0)
	_check(opened, "집게 연타 첫 타에 근접 패링 판정 창이 열린다")
	_check(Main.inst.time - t0 > 0.75, "첫 타 전 준비동작이 길다 (%.2f초)" % (Main.inst.time - t0))
	var total := int(b.ps.get("total", 0))
	_check(total >= 2, "연속 %d타" % total)
	if opened:
		_check(Parry.inst.try_parry(p), "첫 타 패링 성공")
		await _frames(2)
		_check(b.st == LancasterBoss.St.FIGHT and b.pat == "claw", "중간 타를 패링하면 튕겨 났다가 연타를 이어 간다")
		var t1 := Main.inst.time
		var again := await _wait(func(): return Parry.inst.best_threat() == b, 2.0)
		_check(again and Main.inst.time - t1 < 0.9, "다음 타가 곧바로 온다 (%.2f초 뒤 판정 창)" % (Main.inst.time - t1))
		# 섬광 → 타격이 빠르다: 판정 창이 열린 뒤 닿기까지
		_check(b.parry_eta() < 0.3, "섬광 뒤 0.3초 안에 닿는다 (남은 %.2f초)" % b.parry_eta())
		for i in total - 1:
			if Parry.inst.best_threat() == b or await _wait(func(): return Parry.inst.best_threat() == b, 2.0):
				Parry.inst.try_parry(p)
				await _frames(2)
		_check(b.st == LancasterBoss.St.STAGGER, "마지막 타까지 패링하면 크게 무너진다(STAGGER)")
	# 맞으면 2 피해
	await _wait(func(): return b.st == LancasterBoss.St.FIGHT, 4.0)
	await _wait(func(): return b.pat == "", 3.0)
	main.god = false
	p.invuln = 0.0
	p.hp = Player.MAX_HP
	_put_player(7.0)
	_cast("claw")
	var hit := await _wait(func(): return p.hp < Player.MAX_HP, 4.0)
	_check(hit and p.hp <= Player.MAX_HP - 2, "패링 못 하면 한 타에 2 피해 (체력 %d)" % p.hp)
	main.god = true
	p.hp = Player.MAX_HP
	b._end_pattern(true)
	await _wait(func(): return b.st == LancasterBoss.St.FIGHT, 4.0)
	_put_player(9.0)
	_cast("slug")
	_check(await _wait(func(): return not get_nodes_in_group("parry_orbs").is_empty(), 4.0), "중탄은 패링 탄(ParryOrb)으로 나간다")
	var orb := get_nodes_in_group("parry_orbs")[0] as ParryOrb
	var gap := Vector2(p.global_position.x - orb.position.x, p.global_position.z - orb.position.z).length() - p.hit_radius - ParryOrb.RADIUS
	_check(gap / orb.speed < 0.34, "중탄이 빠르다 (%.0fm/s · %.2f초 만에 닿음, 예전 0.5초)" % [orb.speed, gap / orb.speed])
	_check(await _wait(func(): return int(b.ps.get("n", 0)) >= 2, 3.0), "중탄 연속 2발")
	await _wait(func(): return b.pat == "", 4.0)
	main.god = false
	p.invuln = 0.0
	p.hp = Player.MAX_HP
	_put_player(8.0)
	_cast("burst")
	var hurt := await _wait(func(): return p.hp < Player.MAX_HP, 5.0)
	_check(hurt, "제압 연사 예광탄이 플레이어를 맞힌다 (체력 %d)" % p.hp)
	main.god = true
	p.hp = Player.MAX_HP
	await _wait(func(): return b.pat == "", 4.0)

	# 분사 소리가 멈춘다 (예전: 반복 소리를 그냥 틀어 끝없이 울림)
	b._dash(Vector3.RIGHT)
	await _secs(1.2)
	var looping := 0
	for pl in Sfx.inst.players:
		if pl.playing and pl.stream == Sfx.inst.streams.get("boost"):
			looping += 1
	_check(looping == 0, "분사 대시 1.2초 뒤 부스터 소리가 남아 있지 않다 (%d개)" % looping)

	# 5. 광폭화 · 처치 · 재기동 · 프리셋 키
	b.take_hit(int(LancasterBoss.MAX_HP * 0.6), Vector3.FORWARD, b.global_position + Vector3(0, 2, 0), "bullet")
	_check(b.st == LancasterBoss.St.TRANSITION and is_equal_approx(b.boss_hp, LancasterBoss.MAX_HP * 0.5), "체력 50% 에서 광폭화 연출 (체력이 50% 에서 멈춘다)")
	_check(await _wait(func(): return b.phase == 2 and b.st == LancasterBoss.St.FIGHT, 4.0), "2페이즈 OVERDRIVE 로 전투 재개")
	room.handle_key(KEY_8, false)
	_check(is_equal_approx(b.visual.scale.x, 0.75), "8 키: 크기 플레이어 × 1.5")
	room.handle_key(KEY_8, false)
	room.handle_key(KEY_8, false)
	_check(is_equal_approx(b.visual.scale.x, 1.0), "8 키 세 번: 다시 × 2.0")
	room.handle_key(KEY_2, false)
	_check(b.set_i == 1 and room.set_i == 1, "2 키: 패턴 세트 바꿈")
	room.handle_key(KEY_2, false)
	room.handle_key(KEY_2, false)
	room.handle_key(KEY_2, false)
	room.handle_key(KEY_2, false)
	room.handle_key(KEY_2, false)
	b.immortal = false
	b.take_hit(99999, Vector3.FORWARD, b.global_position + Vector3(0, 2, 0), "slash")
	_check(not b.alive and b.st == LancasterBoss.St.DYING, "쓰러지면 정지(SHUTDOWN) 연출")
	var old_id := b.get_instance_id()
	_check(await _wait(func(): return is_instance_valid(room.boss) and room.boss.get_instance_id() != old_id, TrainingBossRoom.RESPAWN + 1.0), "처치 가능이면 %.0f초 뒤 다시 소환" % TrainingBossRoom.RESPAWN)
	b = _boss()
	_check(await _wait(func(): return b.st == LancasterBoss.St.FIGHT, 4.0), "다시 기동해 싸운다")

	# 나가면 허수아비 패널
	p.global_position = main.center
	await _frames(4)
	_check(not room.inside and _panel_text().contains("TRAINING"), "방을 나가면 허수아비 패널로 돌아온다")
	await _frames(30)
	_check(b.pat == "" and b.st == LancasterBoss.St.FIGHT and not b.active, "방 밖이면 보스는 공격하지 않고 지킨다")

	print("RESULT %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(0 if fails == 0 else 1)
