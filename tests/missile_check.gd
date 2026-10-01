extends SceneTree
## Run with: Godot --headless --path . -s tests/missile_check.gd
## 궁극기 미사일 분배·비행 규칙을 확인한다.
##  1. 일반 적은 락온한 적 하나에 미사일 한 발씩만 간다. 남는 미사일은 쏘지 않고 남긴다.
##  2. 보스를 락온하면 일반 적에게 한 발씩 나눈 뒤 남은 미사일을 전부 보스에게 쏜다.
##  3. 락온 없이 쏘면 예전처럼 가진 미사일을 모두 주변 바닥에 흩뿌린다.
##  4. 7m 떨어진 정지한 적까지 명중 시간: 처음(평균 0.611초) → 1차(0.386초) → 지금 평균 0.32초 이하.
##  5. R 을 떼면 준비동작(ULT_WINDUP)이 먼저 나오고 그동안은 슬로우모션이 이어지며 미사일이 안 나간다.
##     준비동작이 끝나는 순간 슬로우모션이 풀리고 미사일이 나간다.

const FLIGHT_AVG := 0.32
const FLIGHT_MAX := 0.34

var fails := 0
var main: Main
var player: Player


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


## 움직이지 않는 과녁 적
func _dummy(off: Vector3, boss := false) -> Enemy:
	var e := Enemy.new()
	main.world.add_child(e)
	e.global_position = player.global_position + off
	e.global_position.y = Main.gy(e.global_position)
	e.hp = 99999
	e.landed = true
	e.is_boss = boss
	e.set_physics_process(false)
	e.set_process(false)
	return e


func _clear_enemies() -> void:
	for e in get_nodes_in_group("enemies"):
		e.queue_free()
	for c in FX.root.get_children():
		if c is Missile:
			c.queue_free()
	await _frames(2)


## ult_targets 를 직접 정해 발사하고, 발사된 미사일마다의 목표(null = 바닥)를 돌려준다.
## 미사일이 빨리 터지므로 발사하는 동안 매 프레임 새로 생긴 미사일을 모은다.
func _fire(targets: Array, missiles: int) -> Array:
	player.missiles = missiles
	player.ult_targets = targets.duplicate()
	player._fire_ult()
	var seen := {}
	for f in int(0.05 * 60.0 * missiles) + 8:
		for c in FX.root.get_children():
			if c is Missile and not seen.has(c.get_instance_id()):
				seen[c.get_instance_id()] = (c as Missile).target
		await physics_frame
	return seen.values()


func _count_for(ms: Array, en: Enemy) -> int:
	return ms.count(en)


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(30)
	player = main.player
	player.invuln = 999.0
	await _clear_enemies()

	# ── 1. 일반 적 3, 미사일 8 → 3발만 ──
	var a := _dummy(Vector3(5, 0, 0))
	var b := _dummy(Vector3(-5, 0, 0))
	var c := _dummy(Vector3(0, 0, -5))
	var ms := await _fire([a, b, c], 8)
	_check(ms.size() == 3, "일반 적 3기 락온 · 미사일 8 → 3발 발사 (%d발)" % ms.size())
	_check(_count_for(ms, a) == 1 and _count_for(ms, b) == 1 and _count_for(ms, c) == 1, "적마다 정확히 1발씩")
	_check(player.missiles == 5, "남은 5발은 보유량에 남는다 (%d)" % player.missiles)
	await _frames(90)

	# ── 1-2. 적 1기에 미사일 4 → 1발 ──
	ms = await _fire([a], 4)
	_check(ms.size() == 1 and _count_for(ms, a) == 1, "적 1기 락온 · 미사일 4 → 1발만 (%d발)" % ms.size())
	_check(player.missiles == 3, "남은 3발 보유 (%d)" % player.missiles)
	await _frames(90)

	# ── 1-3. 적 3기, 미사일 2 → 앞의 2기에 1발씩 ──
	ms = await _fire([a, b, c], 2)
	_check(ms.size() == 2 and _count_for(ms, a) == 1 and _count_for(ms, b) == 1, "미사일이 모자라면 락온 순서대로 1발씩 (%d발)" % ms.size())
	_check(player.missiles == 0, "보유 0")
	await _frames(90)

	# ── 2. 보스 + 일반 2, 미사일 8 → 일반 1·1, 보스 6 ──
	var boss := _dummy(Vector3(0, 0, 6), true)
	ms = await _fire([a, boss, b], 8)
	_check(ms.size() == 8, "보스 포함 락온 → 미사일 8발 모두 발사 (%d발)" % ms.size())
	_check(_count_for(ms, a) == 1 and _count_for(ms, b) == 1, "일반 적은 여전히 1발씩")
	_check(_count_for(ms, boss) == 6, "남은 6발은 보스에게 (%d)" % _count_for(ms, boss))
	_check(player.missiles == 0, "보유 0")
	await _frames(90)

	# ── 3. 락온 없음 → 전부 흩뿌림 ──
	ms = await _fire([], 4)
	var stray := 0
	for m in ms:
		if m == null:
			stray += 1
	_check(ms.size() == 4 and stray == 4, "락온 없이 쏘면 4발 모두 바닥으로 (%d/%d)" % [stray, ms.size()])
	await _frames(120)

	# ── 4. 명중 시간 ──
	await _clear_enemies()
	var targets := []
	for i in 6:
		var ang := TAU * i / 6.0
		targets.append(_dummy(Vector3(cos(ang), 0, sin(ang)) * 7.0))
	player.missiles = 6
	player.ult_targets = targets.duplicate()
	player._fire_ult()
	var ages := {}
	var done := {}
	for f in 240:
		await physics_frame
		for ch in FX.root.get_children():
			if ch is Missile:
				ages[ch.get_instance_id()] = (ch as Missile).age
	var total := 0.0
	var worst := 0.0
	for k in ages:
		total += ages[k]
		worst = maxf(worst, ages[k])
	var avg := total / maxf(ages.size(), 1)
	print("flight avg %.3f  max %.3f  (n=%d)" % [avg, worst, ages.size()])
	_check(ages.size() == 6 and avg <= FLIGHT_AVG and worst <= FLIGHT_MAX, "7m 거리 명중 시간 평균 %.3f초 ≤ %.3f · 최대 %.3f초 ≤ %.3f" % [avg, FLIGHT_AVG, worst, FLIGHT_MAX])

	# ── 5. 준비동작 · 슬로우모션 ──
	await _clear_enemies()
	await _frames(30)
	var tgt := _dummy(Vector3(0, 0, -6))
	player.missiles = 3
	player._begin_ult_aim()
	await process_frame
	player.locks.append(tgt)
	player._end_ult_aim(true)
	await create_timer(Player.ULT_WINDUP * 0.4, true, false, true).timeout
	var flying := 0
	for ch in FX.root.get_children():
		if ch is Missile:
			flying += 1
	_check(player.ult_winding() and Engine.time_scale < 0.2 and flying == 0 and player.ult_queue == 0,
		"준비동작 중: 슬로우모션 유지 (%.2f) · 아직 발사 안 함 (%d발)" % [Engine.time_scale, flying])
	await create_timer(Player.ULT_WINDUP * 0.75, true, false, true).timeout
	await _frames(3)
	_check(not player.ult_winding() and is_equal_approx(Engine.time_scale, 1.0) and player.ult_count == 1,
		"준비동작이 끝나면 슬로우모션 해제 (%.2f) · 락온 1기에 1발 발사 (%d)" % [Engine.time_scale, player.ult_count])

	print("RESULT %s (%d fails)" % ["OK" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
