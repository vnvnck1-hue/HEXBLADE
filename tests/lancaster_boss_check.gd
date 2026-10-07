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
	LancasterIntro.enabled = false      # 첫 등장 연출은 lancaster_intro_check 가 따로 본다 (여기선 예전 기동 → 전투)
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
	var since_dash := 1.0
	for i in 150:
		await physics_frame
		steps += b.rig.stepped
		# 분사 대시 직후는 발이 따라 내려앉는 중이라 뺀다
		since_dash = 0.0 if b.dash_t > 0.0 else since_dash + 1.0 / 60.0
		for s in ["l", "r"]:
			var L: Dictionary = b.rig.legs[s]
			if not L.stepping and since_dash > 0.3 and b.rig.air < 0.05:
				var fy: float = b.rig.at("pt_foot_" + s).y
				max_foot = maxf(max_foot, fy)
	_check(steps >= 4, "옆걸음 2.5초에 %d 걸음" % steps)
	_check(max_foot < 0.2, "디딘 발은 바닥에 붙어 있다 (분사 대시 밖, 발바닥 최고 %.2fm)" % max_foot)

	# 4. 패링 · 예광탄
	b.set_i = 0
	_put_player(7.0)
	_cast("claw")
	var t0 := Main.inst.time
	# 섬광이 떠도 파고드는 동안(멀리 있는 동안)은 패링 판정이 없다
	var far_open := false
	var opened := false
	for i in 240:
		if Parry.inst.best_threat() == b:
			opened = true
			break
		if String(b.ps.get("ph", "")) == "close" and Parry.inst.best_threat() == b:
			far_open = true
		await physics_frame
	_check(opened, "집게 연타 첫 타에 근접 패링 판정 창이 열린다")
	_check(not far_open and String(b.ps.get("ph", "")) == "strike", "판정 창은 파고들기가 끝나고 바로 앞에서 휘두를 때만 (지금 %s)" % b.ps.get("ph", ""))
	var near_d := (b.global_position - p.global_position) * Vector3(1, 0, 1)
	_check(near_d.length() <= b._stand_d(p) + 0.3, "판정 창이 열릴 때 보스가 바로 앞 (%.2fm, 휘두르는 거리 %.2fm)" % [near_d.length(), b._stand_d(p)])
	_check(b.parry_eta() <= Parry.EARLY + 0.001, "판정 창은 실제로 닿기 직전 (남은 %.2f초)" % b.parry_eta())
	_check(Main.inst.time - t0 > 0.75, "첫 타 전 준비동작이 길다 (%.2f초)" % (Main.inst.time - t0))
	var total := int(b.ps.get("total", 0))
	_check(total >= 2, "연속 %d타" % total)
	if opened:
		var away := b.global_position - p.global_position
		away.y = 0
		away = away.normalized()
		var pos0 := b.global_position
		_check(b.parry_feel() == "light", "중간 타 패링은 가벼운 연출(히트스탑만)")
		_check(Parry.stop_preset().id == "heavy", "기본 패링 히트스톱 프리셋은 HEAVY (묵직하게 길게)")
		_check(Parry.inst.try_parry(p), "첫 타 패링 성공")
		_check(Engine.time_scale < 0.01, "패링 순간 히트스톱: 시간이 사실상 멈춘다 (배율 %.3f)" % Engine.time_scale)
		await _frames(2)
		_check(b.st == LancasterBoss.St.FIGHT and b.pat == "claw" and b.ps.get("ph", "") == "link", "중간 타를 패링해도 멈추지 않고 연결 동작(link)으로 이어진다")
		_check(p.stun_t > 0.0 and p.stun_t <= Player.PARRY_RECOIL and p.stun_soft, "패링 성공 뒤 플레이어가 살짝 경직 (%.2f초)" % p.stun_t)
		var t1 := Main.inst.time
		var back := 0.0
		var again := false
		for i in 120:
			back = maxf(back, (b.global_position - pos0).dot(away))
			if Parry.inst.best_threat() == b:
				again = true
				break
			await physics_frame
		_check(back < 0.35, "패링당해도 뒤로 밀려나지 않는다 (최대 %.2fm)" % back)
		_check(again and Main.inst.time - t1 > 0.75 and Main.inst.time - t1 < 1.5, "다음 타는 한 세트로 이어서 온다 (%.2f초 뒤 판정 창)" % (Main.inst.time - t1))
		var near2 := (b.global_position - p.global_position) * Vector3(1, 0, 1)
		_check(again and near2.length() <= b._stand_d(p) + 0.3 and b.parry_eta() <= Parry.EARLY + 0.001, "다음 타도 바로 앞에서 닿기 직전에만 (%.2fm · 남은 %.2f초)" % [near2.length(), b.parry_eta()])
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
	_check(orb.speed >= LancasterBoss.SLUG_SPEED - 0.01, "중탄이 빠르다 (%.0fm/s, 일반 패링 탄 %.0f)" % [orb.speed, ParryOrb.SPEED])
	var orb_open := await _wait(func(): return is_instance_valid(orb) and Parry.inst.best_threat() == orb, 2.0)
	if orb_open:
		var od := Vector2(p.global_position.x - orb.position.x, p.global_position.z - orb.position.z).length() - p.hit_radius - ParryOrb.RADIUS
		_check(od / orb.speed <= Parry.EARLY + 0.02, "중탄 판정 창도 실제로 닿기 직전 (%.2fm · %.2f초)" % [od, od / orb.speed])
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

	# 패링 히트스톱 프리셋 (보스방 P 키)
	var ids := []
	for i in Parry.STOP_PRESETS.size():
		room.handle_key(KEY_P, false)
		ids.append(Parry.stop_preset().id)
	_check(ids.size() == 5 and ids[-1] == "heavy" and ids.has("crunch") and ids.has("soft"), "P 키로 히트스톱 프리셋 %d종을 돌아 다시 HEAVY (%s)" % [ids.size(), ", ".join(ids)])
	room.handle_key(KEY_P, true)
	_check(Parry.stop_preset().id == "crunch", "Shift+P 는 거꾸로")
	Parry.use_stop("heavy")

	# 소강: 한동안 때리지 않으면 거리를 벌리고 견제만 한다. 다시 때리면 곧 끝난다
	_check(is_equal_approx(LancasterBoss.MAX_HP, 2700.0), "보스 체력 2700 (예전 900 의 세 배)")
	_put_player(5.0)
	b._pressure = Main.inst.time - 10.0
	b.rest = 0.3
	var lulled := await _wait(func(): return b.lull_t > 0.0, 2.0)
	_check(lulled, "공격을 멈추면 보스가 소강 상태에 들어간다")
	var d0 := b._to_player().length()
	var quiet := true
	for i in 120:
		if b.pat != "" and b.pat != "pods":
			quiet = false
		await physics_frame
	_check(quiet and b._to_player().length() > d0 + 2.0, "소강 동안 패턴 없이 거리를 벌린다 (%.1fm → %.1fm)" % [d0, b._to_player().length()])
	b.take_hit(1, Vector3.FORWARD, b.global_position + Vector3(0, 2, 0), "bullet")
	_check(b.lull_t <= 0.6, "다시 때리면 소강이 곧 끝난다 (남은 %.2f초)" % b.lull_t)
	await _wait(func(): return b.pat != "", 3.0)
	b._end_pattern(true)

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
