extends SceneTree
## Run with: Godot --headless --path . -s tests/lancaster_claw_hit_check.gd
## LANCASTER 근접 패링 공격(CLAW CHAIN)은 시도하면 확실히 닿는다:
##  1. 섬광 뒤 플레이어가 뒤로 걸어서(7m/s) 빠져도 → 보스가 끝까지 따라붙어 맞힌다 (예전엔 헛스윙하고 천천히 따라옴).
##  2. 더 빠르게(12m/s) 달아나도 맞는다. 맞는 순간 보스는 플레이어 바로 앞.
##  3. 휘두를 때 집게 팔 리본이 보이고, 휘두르기가 크다(몸 비틀림).
##  4. 패링 판정 창은 그대로 닿기 직전에만 열린다.

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


func _wait(cond: Callable, limit: float) -> bool:
	var tt := 0.0
	while tt < limit:
		if cond.call():
			return true
		await physics_frame
		tt += 1.0 / 60.0
	return false


func _far_dir(b: LancasterBoss) -> Vector3:
	# 보스에서 방 안 가장 먼 모서리 쪽 (달아날 공간이 가장 넓은 방향)
	var r := room.rect.grow(-1.5)
	var best := Vector3.RIGHT
	var bd := -1.0
	for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var d := Vector3(c.x, 0, c.y) - b.global_position
		d.y = 0
		if d.length() > bd:
			bd = d.length()
			best = d.normalized()
	return best


## 한 번 시도: 섬광(close 진입) 순간부터 speed m/s 로 보스 반대쪽으로 계속 걸어간다 → 첫 타에 맞았나
func _try(speed: float) -> Dictionary:
	var b := room.boss
	b._end_pattern(false)
	b.rest = 99.0
	b.pin_cd = 99.0
	await _frames(20)
	var away := _far_dir(b)
	p.global_position = main.map.push_out(b.global_position + away * 6.5, 0.6)
	p.velocity = Vector3.ZERO
	p.hp = Player.MAX_HP
	p.invuln = 0.0
	p.stun_t = 0.0
	main.god = false
	await _frames(2)
	b.force_next = "claw"
	b.rest = 0.0
	var started := await _wait(func(): return b.pat == "claw" and String(b.ps.get("ph", "")) == "close", 4.0)
	var hp0 := p.hp
	var hit := false
	var contact_d := INF
	var ribbon := false
	var twist := 0.0
	var early := false
	for i in 120:
		# 계속 보스 반대쪽으로 걷는다 (방 밖으로는 못 나감)
		var a := p.global_position - b.global_position
		a.y = 0
		a = a.normalized() if a.length() > 0.1 else away
		var np := p.global_position + a * speed / 60.0
		var r := room.rect.grow(-1.0)
		np.x = clampf(np.x, r.position.x, r.end.x)
		np.z = clampf(np.z, r.position.y, r.end.y)
		p.global_position = main.map.push_out(np, 0.6)
		if String(b.ps.get("ph", "")) == "close" and Parry.inst.best_threat() == b:
			early = true
		if b.ps.has("swung"):
			twist = maxf(twist, absf(b.rig.twist) + absf(float((b.rig._cur.torso as Vector3).y)))
			var mi := b.claw_trail
			if mi and mi.active and (mi.mesh as ImmediateMesh).get_surface_count() > 0:
				ribbon = true
		await physics_frame
		if p.hp < hp0 and not hit:
			hit = true
			var d := p.global_position - b.global_position
			d.y = 0
			contact_d = d.length()
		if hit or int(b.ps.get("n", 0)) >= 1 or b.pat != "claw":
			break
	main.god = true
	p.hp = Player.MAX_HP
	return {"started": started, "hit": hit, "d": contact_d, "ribbon": ribbon, "twist": twist, "early": early}


func _run() -> void:
	LancasterIntro.enabled = false
	main = (load("res://scenes/training.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(20)
	p = main.player
	main.god = true
	room = main.boss_room
	p.global_position = room.door + Vector3(-1.0, 0, 0)
	await _frames(4)
	_check(await _wait(func(): return room.boss.st == LancasterBoss.St.FIGHT, 5.0), "보스전 시작")
	room.boss.set_i = 0

	var walk_hits := 0
	for i in 3:
		var r: Dictionary = await _try(7.0)
		print("  걸어서 달아남 %d: 시작 %s · 맞음 %s · 거리 %.2fm · 리본 %s · 비틀림 %.2f" % [i, r.started, r.hit, r.d, r.ribbon, r.twist])
		if r.hit:
			walk_hits += 1
		if i == 0:
			_check(r.ribbon, "휘두를 때 집게 팔 리본이 보인다")
			_check(r.twist > 1.0, "크게 휘두른다 (몸 비틀림 %.2f rad)" % r.twist)
			_check(not r.early, "파고드는 동안은 여전히 패링 판정 창 밖")
	_check(walk_hits == 3, "뒤로 걸어서(7m/s) 빠져도 첫 타에 맞는다 (%d/3)" % walk_hits)
	var run_hits := 0
	var far_d := 0.0
	for i in 3:
		var r: Dictionary = await _try(12.0)
		print("  뛰어서 달아남 %d: 맞음 %s · 거리 %.2fm" % [i, r.hit, r.d])
		if r.hit:
			run_hits += 1
			far_d = maxf(far_d, r.d)
	_check(run_hits == 3, "더 빠르게(12m/s) 달아나도 맞는다 (%d/3)" % run_hits)
	_check(far_d < LancasterBoss.REACH["swipe"] * room.boss.size_k + p.hit_radius + 1.2, "맞는 순간 보스는 플레이어 바로 앞 (최대 %.2fm)" % far_d)

	print("RESULT %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(0 if fails == 0 else 1)
