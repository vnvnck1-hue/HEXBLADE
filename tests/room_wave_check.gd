extends SceneTree
## Run with: Godot --headless --path . -s tests/room_wave_check.gd
## 방 탐색 아레나 확인:
##  1. 넓은 방(보통 방의 2~3배)이 생기고, 가장 큰 방이 웨이브 방이 된다 (여러 시드)
##  2. 웨이브 방에 들어가면 5번의 웨이브가 차례로 진행된 뒤에야 방이 정리된다
##  3. 기본 총기는 30발을 쏘면 재장전하고, 재장전이 끝나면 다시 30발이 찬다. T 로 수동 재장전
##  4. 적의 등 뒤 회피(광선검 순간이동 회피)가 없다

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


func _avg_normal_cells(m: ArenaMap) -> float:
	var n := 0
	var sum := 0
	for r in m.rooms:
		if r.combat and r.scale <= 1.0:
			n += 1
			sum += r.cells.size()
	return float(sum) / maxf(n, 1)


func _run() -> void:
	# ── 1. 맵 생성 (여러 시드) ──
	for seed_value in [1, 7, 42, 1234, 99999]:
		var m := ArenaMap.new()
		m.generate(seed_value)
		var big := 0
		var biggest := 0
		for r in m.rooms:
			if r.combat and r.scale > 1.0:
				big += 1
				biggest = maxi(biggest, r.cells.size())
		var avg := _avg_normal_cells(m)
		var combat := 0
		for r in m.rooms:
			if r.combat:
				combat += 1
		_check(combat == ArenaMap.COMBAT_ROOMS, "seed %d: 전투방 %d곳" % [seed_value, combat])
		_check(big >= 2, "seed %d: 넓은 방 %d곳" % [seed_value, big])
		_check(m.wave_room >= 0 and m.rooms[m.wave_room].cells.size() == biggest, "seed %d: 가장 큰 방(%d칸, 보통 평균 %.0f칸)이 웨이브 방" % [seed_value, biggest, avg])
		m.free()

	# ── 2. 웨이브 방 ──
	var scene: PackedScene = load("res://scenes/main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(30)
	player = main.player
	player.invuln = 9999.0
	var wid := main.map.wave_room
	_check(wid >= 0, "웨이브 방이 있다 (id %d, 배율 %.1f)" % [wid, main.map.rooms[wid].scale if wid >= 0 else 0.0])
	player.global_position = main.map.room_center_world(wid)
	await _frames(3)
	_check(main.active_room == wid and main.wave == 1, "웨이브 방에 들어가면 WAVE 1 시작")
	var seen_waves := {}
	var guard := 0
	while main.active_room == wid and guard < 60 * 120:
		guard += 1
		player.hp = Player.MAX_HP
		player.invuln = 9999.0
		seen_waves[main.wave] = true
		for e in main.get_tree().get_nodes_in_group("enemies"):
			var en := e as Enemy
			if en.alive and en.landed and en.is_inside_tree():
				en.hp = 0
				en.die(Vector3.FORWARD, "bullet")
		await physics_frame
	_check(seen_waves.size() == ArenaMap.WAVES and seen_waves.has(ArenaMap.WAVES), "웨이브 %s 모두 진행" % [seen_waves.keys()])
	_check(main.map.rooms[wid].state == "cleared" and main.wave == 0, "5웨이브를 모두 정리해야 방이 정리된다")

	# ── 3. 탄창 · 재장전 ──
	await _frames(10)
	_check(player.mag == Player.MAG_SIZE and Player.MAG_SIZE == 30, "탄창 30발")
	Input.action_press("fire_mouse")
	await _frames(int(Player.FIRE_INTERVAL * 60.0 * 10.0) + 10)
	_check(player.mag < Player.MAG_SIZE and player.mag > 0, "사격하면 탄이 준다 → %d" % player.mag)
	var g2 := 0
	while player.reload_t <= 0.0 and g2 < 600:
		g2 += 1
		await physics_frame
	_check(player.mag == 0 and player.reload_t > 0.0, "30발을 다 쏘면 자동 재장전")
	await _frames(20)
	_check(player.mag == 0, "재장전 중에는 쏘지 않는다")
	await _frames(int(Player.RELOAD_TIME * 60.0) + 5)
	_check(player.mag > Player.MAG_SIZE - 10, "재장전 뒤 탄창이 다시 찬다 → %d" % player.mag)
	Input.action_release("fire_mouse")
	await _frames(5)
	var m0 := player.mag
	Input.action_press("reload")
	await _frames(2)
	Input.action_release("reload")
	_check(player.reload_t > 0.0 or m0 == Player.MAG_SIZE, "T 로 수동 재장전")
	await _frames(int(Player.RELOAD_TIME * 60.0) + 5)
	_check(player.mag == Player.MAG_SIZE, "수동 재장전 완료 → %d" % player.mag)
	_check(player.j.has("shoulder_l") and (player.j.arm_l as Node3D).get_parent() == player.j.shoulder_l, "사격 팔이 어깨 피벗에 달려 있다")

	# ── 4. 등 뒤 회피 없음 ──
	_check(not Evade.new().has_method("try_dodge"), "광선검 순간이동 회피 기능이 없다")

	print("RESULT %s (%d fail)" % ["OK" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
