extends SceneTree
## Run with: Godot --headless --path . -s tests/enemy_wander_check.gd
## 1. 포탑 체력은 다른 적 배율의 절반 (hp_mul 0.5)
## 2. 플레이어가 연기 속에 숨으면 드론·스트라이커·크롤러·포탑이 놓친 자리 주변을 배회하며 두리번거린다 (Wander):
##    쏘지 않고, 실제로 돌아다니되 놓친 자리에서 멀리 가지 않으며, 바라보는 방향이 바뀐다 (포탑은 머리만)
## 3. 연기에서 나오면 배회가 끝난다

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


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


func _run() -> void:
	var lab: GimmickLab = load("res://scenes/gimmicks.tscn").instantiate()
	root.add_child(lab)
	current_scene = lab
	await _frames(4)
	lab._drone_t = 9999.0
	for d in lab.drones:
		d.queue_free()
	lab.drones.clear()
	var p := lab.player
	# 봇은 끈다: 시험장 봇은 몇 초 뒤 연기 밖으로 나가는 단계로 넘어가 은신이 풀린다
	p.bot = false
	lab.phase = 0
	lab.ph_t = 0.0
	var c := lab.smoke.global_position
	p.global_position = c
	await _frames(30)
	_check(p.hidden, "연기 속: 플레이어가 숨었다")

	# ── 1. 포탑 체력 ──
	var plain := Enemy.new()
	plain.hp = 9
	plain._init_hp()
	var tur := Turret.new()
	tur.face_yaw = 0.0
	lab.world.add_child(tur)
	tur.global_position = lab.push_out(c + _flat(c - lab.belt.global_position).normalized() * 7.0 - Vector3(_flat(c - lab.belt.global_position).normalized().z, 0, -_flat(c - lab.belt.global_position).normalized().x) * 2.5, 0.8)
	await _frames(2)
	_check(tur.max_hp * 2 <= plain.max_hp + 1 and tur.max_hp > 0, "포탑 체력은 같은 기본 체력의 일반 적의 절반 (%d vs %d)" % [tur.max_hp, plain.max_hp])
	plain.free()

	# ── 2. 배회 ──
	var foes: Array[Enemy] = [tur]
	# 레일(적도 실어 나른다)에서 먼 쪽에 세운다
	var away := _flat(c - lab.belt.global_position).normalized()
	var side := Vector3(-away.z, 0, away.x)
	var offs := [away * 5.0 + side * 5.5, away * 5.0 - side * 5.5, away * 7.5 + side * 2.0]
	var kinds := [Enemy, Striker, Crawler]
	for i in 3:
		var e: Enemy = kinds[i].new()
		lab.world.add_child(e)
		e.global_position = lab.push_out(c + offs[i], 0.9)
		foes.append(e)
	# 등장 연출(포탑 해치 약 1.6초)이 끝나고 배회에 들어갈 때까지
	await _frames(150)
	var all_on := true
	for e in foes:
		all_on = all_on and e.landed and e.wander.on
	_check(all_on, "숨은 동안 모든 적이 배회 상태 (wander.on)")
	var anchor := {}
	var yaw_min := {}
	var yaw_max := {}
	var max_from_anchor := {}
	for e in foes:
		anchor[e] = _flat(e.wander.anchor)
		yaw_min[e] = INF
		yaw_max[e] = -INF
		max_from_anchor[e] = 0.0
	var seen := {}
	for b in lab.get_tree().get_nodes_in_group("enemy_bullets"):
		seen[b.get_instance_id()] = true
	var new_shots := 0
	var walked := {}
	for e in foes:
		walked[e] = 0.0
	var prev := {}
	var last_yaw := {}
	var unwrapped := {}
	for e in foes:
		prev[e] = _flat(e.global_position)
	for i in 600:
		await _frames(1)
		p.global_position = c
		p.velocity = Vector3.ZERO
		lab.ph_t = 0.0
		for b in lab.get_tree().get_nodes_in_group("enemy_bullets"):
			if not seen.has(b.get_instance_id()):
				seen[b.get_instance_id()] = true
				new_shots += 1
		for e in foes:
			if not is_instance_valid(e):
				continue
			var pos := _flat(e.global_position)
			walked[e] += pos.distance_to(prev[e])
			prev[e] = pos
			max_from_anchor[e] = maxf(max_from_anchor[e], pos.distance_to(anchor[e]))
			# 감긴 각도를 풀어 누적한다 (±PI 경계에서 튀지 않게)
			var yaw: float = e.rotation.y if not (e is Turret) else e.rotation.y + (e.j.head as Node3D).rotation.y
			if not last_yaw.has(e):
				last_yaw[e] = yaw
				unwrapped[e] = 0.0
			unwrapped[e] += wrapf(yaw - float(last_yaw[e]), -PI, PI)
			last_yaw[e] = yaw
			yaw_min[e] = minf(yaw_min[e], unwrapped[e])
			yaw_max[e] = maxf(yaw_max[e], unwrapped[e])
	_check(new_shots == 0, "배회하는 동안 적이 쏘지 않는다 (새 적탄 %d)" % new_shots)
	for e in foes:
		var nm: String = e.get_script().get_global_name()
		var spread: float = yaw_max[e] - yaw_min[e]
		_check(spread > 0.6, "%s: 두리번거리며 바라보는 방향이 바뀐다 (폭 %.2f rad)" % [nm, spread])
		if e is Turret:
			_check(float(walked[e]) < 0.05, "Turret: 제자리에 고정 (이동 %.2fm)" % walked[e])
		else:
			_check(float(walked[e]) > 1.0, "%s: 실제로 돌아다닌다 (이동 %.1fm)" % [nm, walked[e]])
			_check(float(max_from_anchor[e]) < Wander.RADIUS + 1.5, "%s: 놓친 자리 주변을 벗어나지 않는다 (최대 %.1fm)" % [nm, max_from_anchor[e]])

	# ── 3. 드러나면 끝 ──
	p.global_position = c + Vector3(0, 0, 9.0)
	await _frames(30)
	var any_on := false
	for e in foes:
		if is_instance_valid(e) and e.wander.on:
			any_on = true
	_check(not p.hidden and not any_on, "연기에서 나오면 배회가 끝난다")

	print("RESULT enemy_wander_check fails=%d" % fails)
	quit(1 if fails > 0 else 0)
