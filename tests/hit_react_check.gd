extends SceneTree
## Run with: Godot --headless --path . -s tests/hit_react_check.gd
## 적 피격 반응 (Enemy.HitReact):
##  1. 5종 반응이 각자 뚜렷하게 몸을 움직인다 — 젖힘(크게 기울어짐) · 비틀림(몸 방향이 돌아감) · 숙임(가라앉음)
##     · 회전(한 바퀴) · 띄움(떠오름). 끝나면 몸체가 제자리·정면으로 돌아온다
##  2. 연달아 맞으면 같은 반응이 바로 반복되지 않고 여러 종류가 섞인다. 가벼운 공격에는 회전·띄움이 없다
##  3. 바닥에 박힌 포탑은 회전·띄움을 하지 않는다

var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _tilt(b: Basis) -> float:
	return b.y.angle_to(Vector3.UP)


func _yaw(b: Basis) -> float:
	var f := -b.z
	return atan2(-f.x, -f.z)


func _run() -> void:
	var m: Main = load("res://scenes/gimmicks.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	await _frames(4)
	(m as GimmickLab)._drone_t = 9999.0
	for d in (m as GimmickLab).drones:
		d.queue_free()
	var p := m.player
	p.bot = false
	var c := p.global_position
	var e := Enemy.new()
	e.hp = 999
	e.orb_chance = 0.0
	m.world.add_child(e)
	e.global_position = m.push_out(c + Vector3(0, 0, -6.0), 0.8)
	await _frames(60)
	_check(e.landed, "드론 착지")
	var body: Node3D = e.j.body
	var names := ["RECOIL", "TWIST", "CRUMPLE", "SPIN", "LAUNCH"]
	for kind in 5:
		e.force_react = kind
		e.fire_timer = 5.0
		var y0 := body.position.y
		var hit_dir := (e.global_position - p.global_position)
		hit_dir.y = 0
		hit_dir = hit_dir.normalized()
		e.take_hit(1, hit_dir, e.global_position + Vector3(0.3, 1.0, 0.3), "bullet")
		_check(e.hurt_t > 0.0 and e.hurt_kind == kind, "%s: 피격 반응 시작" % names[kind])
		var max_tilt := 0.0
		var max_yaw := 0.0
		var spun := 0.0
		var last_yaw := _yaw(body.basis)
		var min_dy := 0.0
		var max_dy := 0.0
		var max_push := 0.0
		for i in 45:
			await _frames(1)
			if e.hurt_t <= 0.0:
				break
			var b := body.basis.orthonormalized()
			max_tilt = maxf(max_tilt, _tilt(b))
			var yw := _yaw(b)
			max_yaw = maxf(max_yaw, absf(yw))
			spun += wrapf(yw - last_yaw, -PI, PI)
			last_yaw = yw
			min_dy = minf(min_dy, body.position.y - e.hurt_base_y)
			max_dy = maxf(max_dy, body.position.y - e.hurt_base_y)
			max_push = maxf(max_push, Vector2(body.position.x, body.position.z).length())
		print("  %s tilt=%.2f yaw=%.2f spun=%.2f dy=[%.2f,%.2f] push=%.2f" % [names[kind], max_tilt, max_yaw, spun, min_dy, max_dy, max_push])
		match kind:
			0: _check(max_tilt > 0.55 and max_push > 0.15, "RECOIL: 크게 뒤로 젖혀지며 밀려난다 (기울기 %.2f rad · 밀림 %.2fm)" % [max_tilt, max_push])
			1: _check(max_yaw > 0.8, "TWIST: 몸 방향이 홱 돌아간다 (%.2f rad)" % max_yaw)
			2: _check(min_dy < -0.15 and max_tilt > 0.35, "CRUMPLE: 숙이며 가라앉는다 (%.2fm · %.2f rad)" % [min_dy, max_tilt])
			3: _check(absf(spun) > PI * 1.5, "SPIN: 한 바퀴 가까이 돈다 (누적 %.2f rad)" % spun)
			4: _check(max_dy > 0.5 and max_tilt > 0.6, "LAUNCH: 떠올라 젖혀진다 (+%.2fm · %.2f rad)" % [max_dy, max_tilt])
		await _frames(3)
		var settled := _tilt(body.basis.orthonormalized()) < 0.12 and absf(_yaw(body.basis.orthonormalized())) < 0.12
		_check(e.hurt_t <= 0.0 and settled, "%s: 끝나면 정면·똑바로 돌아온다" % names[kind])
		await _frames(20)
	e.force_react = -1

	# ── 2. 연타 다양성 ──
	var seq: Array[int] = []
	var repeats := 0
	for i in 14:
		e.take_hit(1, Vector3(randf_range(-1, 1), 0, 1).normalized(), Vector3.ZERO, "bullet")
		if not seq.is_empty() and seq[-1] == e.hurt_kind:
			repeats += 1
		seq.append(e.hurt_kind)
		await _frames(12)
	var kinds := {}
	for k in seq:
		kinds[k] = true
	_check(repeats == 0 and kinds.size() >= 3, "연타: 같은 반응이 바로 반복되지 않고 %d종이 섞인다 %s" % [kinds.size(), str(seq)])
	_check(not kinds.has(Enemy.HitReact.SPIN) and not kinds.has(Enemy.HitReact.LAUNCH), "가벼운 총알에는 회전·띄움이 없다")
	await _frames(40)
	var heavy := {}
	for i in 16:
		e.take_hit(1, Vector3(0, 0, 1), Vector3.ZERO, "slash")
		heavy[e.hurt_kind] = true
		await _frames(40)
	_check(heavy.has(Enemy.HitReact.SPIN) or heavy.has(Enemy.HitReact.LAUNCH), "검 같은 무거운 공격에는 회전·띄움이 섞인다 %s" % str(heavy.keys()))

	# ── 3. 포탑 ──
	var tur := Turret.new()
	m.world.add_child(tur)
	tur.global_position = m.push_out(c + Vector3(5, 0, -5), 0.8)
	await _frames(130)
	var tk := {}
	for i in 16:
		tur.hp = 999
		tur.take_hit(2, Vector3(1, 0, 0), Vector3.ZERO, "slash")
		tk[tur.hurt_kind] = true
		await _frames(30)
	_check(tur.landed and not tk.has(Enemy.HitReact.SPIN) and not tk.has(Enemy.HitReact.LAUNCH) and tk.has(Enemy.HitReact.TWIST), "포탑: 비틀림은 있고 회전·띄움은 없다 %s" % str(tk.keys()))

	print("RESULT hit_react_check fails=%d" % fails)
	quit(1 if fails > 0 else 0)
