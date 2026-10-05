extends SceneTree
## Run with: Godot --headless --path . -s tests/bug_arena_check.gd
## 방 탐색 아레나(main.tscn) = 벌레 아레나 확인:
##  1. 위험도 표: 레벨(정리한 방 수)이 오를수록 적 수 · 동시 수 · 체력 · 공격 빈도는 늘고 소환 간격은 줄며, 구성이 개미 → 공벌레 쪽으로 옮겨 간다
##  2. 실제 진행: 방에 들어가면 벌레만 나온다(기계 드론·요격기·포탑·크롤러 없음) · 방을 정리할 때마다 다음 방의 위험도 · 적 수 · 체력이 오른다
##  3. 섹터 런(run.tscn) 은 벌레 아레나가 아니다 (상속한 씬은 예전 규칙 그대로)

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


func _share(w: Array, i: int) -> float:
	var s := 0.0
	for v: float in w:
		s += v
	return w[i] / s


func _run() -> void:
	# ── 1. 위험도 표 ──
	var mono := true
	var strict := true
	for l in 8:
		var a := Main.bug_count(l, 1.0)
		var b := Main.bug_count(l + 1, 1.0)
		if b < a or Main.bug_alive(l + 1, 1.0) < Main.bug_alive(l, 1.0) or Main.bug_interval(l + 1) > Main.bug_interval(l):
			mono = false
		if Main.bug_hp(l + 1) <= Main.bug_hp(l) or Main.bug_aggro(l + 1) <= Main.bug_aggro(l):
			strict = false
	_check(mono, "레벨이 오를수록 적 수 · 동시 수는 줄지 않고 소환 간격은 늘지 않는다")
	_check(strict, "레벨마다 체력 · 공격 빈도가 오른다")
	print("  표  L: 수/동시/간격/체력/빈도")
	for l in 9:
		print("  L%d: %d / %d / %.2f / x%.2f / x%.2f" % [l, Main.bug_count(l, 1.0), Main.bug_alive(l, 1.0), Main.bug_interval(l), Main.bug_hp(l), Main.bug_aggro(l)])
	_check(Main.bug_count(8, 1.0) >= Main.bug_count(0, 1.0) * 3, "마지막 방 적 수가 첫 방의 3배 이상 (%d → %d)" % [Main.bug_count(0, 1.0), Main.bug_count(8, 1.0)])
	var w0 := Main.bug_weights(0)
	var w2 := Main.bug_weights(2)
	var w8 := Main.bug_weights(8)
	_check(w0[2] == 0.0 and w0[3] == 0.0, "첫 방은 애벌레 · 촘퍼만")
	_check(w2[2] > 0.0 and w2[3] > 0.0, "레벨 2부터 개미 · 공벌레가 섞인다")
	_check(_share(w8, 0) < _share(w0, 0) and _share(w8, 2) + _share(w8, 3) > 0.5,
		"뒤 방일수록 애벌레 비율이 줄고 개미 · 공벌레가 절반 넘게 (L8 애벌레 %.0f%% · 개미+공벌레 %.0f%%)" % [_share(w8, 0) * 100, (_share(w8, 2) + _share(w8, 3)) * 100])

	# ── 2. 실제 진행 ──
	var main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(30)
	_check(main.bug_arena, "방 탐색 아레나는 벌레 아레나")
	var player: Player = main.player
	var rooms: Array = []
	for r in main.map.rooms:
		if r.combat and not r.wave and r.scale <= 1.0:
			rooms.append(r.id)
	_check(rooms.size() >= 2, "보통 크기 전투방 %d곳" % rooms.size())
	var totals: Array = []
	var hps: Array = []
	var only_bugs := true
	var kinds := {}
	for n in mini(3, rooms.size()):
		var id: int = rooms[n]
		player.global_position = main.map.room_center_world(id)
		await _frames(3)
		if main.active_room != id:
			_check(false, "방 %d 진입" % id)
			break
		_check(main.threat == n, "%d번째 방 위험도 레벨 %d (정리한 방 %d)" % [n + 1, main.threat, main.rooms_cleared])
		totals.append(main.room_total)
		var hp_seen := 0.0
		var guard := 0
		while main.active_room == id and guard < 60 * 90:
			guard += 1
			player.hp = Player.MAX_HP
			player.invuln = 9999.0
			for e in main.get_tree().get_nodes_in_group("enemies"):
				var en := e as Enemy
				if en.prop:
					continue
				if not (en is BugEnemy):
					only_bugs = false
					print("  기계 적: ", en.get_class(), " ", en.get_script().resource_path)
				else:
					kinds[(en.get_script() as Script).resource_path.get_file()] = true
					hp_seen = maxf(hp_seen, en.hp_mul)
				if en.alive and en.landed and en.is_inside_tree():
					en.hp = 0
					en.die(Vector3.FORWARD, "bullet")
			await physics_frame
		hps.append(hp_seen)
		_check(main.map.rooms[id].state == "cleared", "%d번째 방 정리 (벌레 %d마리)" % [n + 1, totals[-1]])
		await _frames(20)
	_check(only_bugs, "벌레만 나온다 (기계 드론 · 요격기 · 포탑 · 크롤러 없음) — 나온 종류 %s" % [kinds.keys()])
	_check(totals.size() >= 2 and totals[1] > totals[0], "방을 정리할수록 다음 방 적 수가 는다 %s" % [totals])
	_check(hps.size() >= 2 and hps[1] > hps[0], "방을 정리할수록 다음 방 벌레 체력 배율이 오른다 %s" % [hps])
	main.queue_free()
	await _frames(5)

	# ── 3. 섹터 런 ──
	var run = (load("res://scenes/run.tscn") as PackedScene).instantiate()
	root.add_child(run)
	current_scene = run
	await _frames(10)
	_check(not run.bug_arena, "섹터 런은 벌레 아레나가 아니다 (예전 적 그대로)")
	run.queue_free()
	await _frames(5)
	print("BUG_ARENA_CHECK %s" % ("OK" if fails == 0 else "FAILED %d" % fails))
	quit(1 if fails > 0 else 0)
