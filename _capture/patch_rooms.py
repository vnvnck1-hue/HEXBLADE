import io, os
os.chdir(os.path.join(os.path.dirname(__file__), "..", "scripts"))
p = "main.gd"
s = io.open(p, encoding="utf-8").read()


def rep(a, b):
    global s
    assert a in s, a[:80]
    s = s.replace(a, b)


def cut(start, end, b):
    global s
    i = s.index(start)
    j = s.index(end, i)
    s = s[:i] + b + s[j:]


rep('## 경기장 · 카메라 · 웨이브 · 승패 · 타격 정지 · 화면 흔들림.', '## 방·통로 맵 · 카메라 · 방 전투 진행 · 승패 · 타격 정지 · 화면 흔들림.')
cut("const HALF := 13.0", "static var inst: Main", '''## 방 난이도별 적 패턴 풀 (0 조준 3연발, 1 부채꼴, 2 원형탄)
const POOLS := [[0], [0, 0, 1], [0, 1, 1, 2], [0, 1, 2, 2]]
const MAX_ALIVE := 4

''')
rep("var obstacles: Array[Rect2] = []\nvar wave := 0\n", "var map: ArenaMap\nvar map_seed := -1\nvar active_room := -1\nvar room_total := 0\nvar room_kills := 0\nvar rooms_cleared := 0\n")
rep("var wave_delay := -1.0\nvar _wave_kills := 0\n", "var bot_path: Array[Vector3] = []\nvar bot_path_t := 0.0\n")
rep('''	player.global_position = Vector3(0, 0, 2)
''', '''	player.global_position = map.room_center_world(map.start_room)
''')
rep('''	if showcase:
		wave = 1
		return
	FX.victory(player.global_position)
	_next_wave()''', '''	if showcase:
		return
	FX.victory(player.global_position)
	hud.banner("EXPLORE", Color(0.7, 0.95, 1.0), "전투방 %d곳을 모두 정리하세요" % combat_rooms())''')
rep('''		elif a == "--showcase":''', '''		elif a.begins_with("--seed="):
			map_seed = int(a.substr(7))
		elif a == "--showcase":''')

# 경기장 생성 → 맵
cut("func _build_arena() -> void:", "# ── 판정 보조", '''func _build_arena() -> void:
	map = ArenaMap.new()
	world.add_child(map)
	map.generate(map_seed if map_seed >= 0 else randi())
	map.build()


''')
cut("func is_blocked(p: Vector3) -> bool:", "func add_bullet(b: Bullet) -> void:", '''func is_blocked(p: Vector3) -> bool:
	return map.is_blocked(p)


func push_out(p: Vector3, radius: float) -> Vector3:
	return map.push_out(p, radius)


''')
cut("## 현재 웨이브 포함, 남은 적 수", "func _run_showcase() -> void:", '''func combat_rooms() -> int:
	return ArenaMap.COMBAT_ROOMS if map.rooms.size() > ArenaMap.COMBAT_ROOMS else map.rooms.size() - 1


## 현재 전투방에 남은 적 수
func enemies_left() -> int:
	return room_total - room_kills if active_room >= 0 else 0


# ── 방 진행 ─────────────────────────────────────────────

func _activate_room(id: int) -> void:
	var r: Dictionary = map.rooms[id]
	r.state = "active"
	r.visited = true
	active_room = id
	map.close_gates(id)
	var d: int = clampi(r.difficulty, 1, 6)
	room_total = clampi(3 + d, 4, 9)
	room_kills = 0
	spawn_queue.clear()
	var pool: Array = POOLS[mini(d - 1, POOLS.size() - 1)]
	for i in room_total:
		spawn_queue.append(pool[randi() % pool.size()])
	spawn_timer = 0.6
	shake(0.25)
	Sfx.play("spawn", 0.0, 0.0)
	hud.banner(ArenaMap.SHAPE_NAMES[r.shape], Color("ff7a9a"), "차단막이 닫혔습니다 · 적 %d기" % room_total)


func _clear_room() -> void:
	var id := active_room
	map.rooms[id].state = "cleared"
	map.open_gates(id)
	active_room = -1
	rooms_cleared += 1
	if player.hp < Player.MAX_HP:
		player.hp += 1
	if rooms_cleared >= combat_rooms():
		_win()
	else:
		Sfx.play("charged", 0.0, 0.0)
		FX.shockwave(player.global_position, Pal.CYAN, 4.0, 0.5)
		hud.banner("ROOM CLEAR", Color(0.6, 0.95, 1.0), "%d / %d  ·  차단막 해제 · 체력 +1" % [rooms_cleared, combat_rooms()])


''')
cut("func _physics_process(dt: float) -> void:", "func on_enemy_killed(_e: Enemy) -> void:", '''func _physics_process(dt: float) -> void:
	time += dt
	if showcase:
		_run_showcase()
	map.update_discovery(player.global_position, dt)
	if state == State.PLAY and active_room < 0 and not showcase and player.alive:
		var rid := map.room_at(player.global_position)
		if rid >= 0 and map.rooms[rid].combat and map.rooms[rid].state == "idle":
			# 출입구에서 한 칸 이상 안쪽으로 들어왔을 때 닫는다
			var inside := true
			for door in map.rooms[rid].doors:
				if map.world_of(door[0]).distance_to(player.global_position) < 1.8:
					inside = false
					break
			if inside:
				_activate_room(rid)
		elif rid >= 0:
			map.rooms[rid].visited = true
	if state == State.PLAY and active_room >= 0 and spawn_queue.size() > 0:
		spawn_timer -= dt
		var alive := get_tree().get_nodes_in_group("enemies").size() + pending_spawns
		if spawn_timer <= 0.0 and alive < MAX_ALIVE:
			spawn_timer = 0.5
			_spawn(spawn_queue.pop_front())


func _spawn(pattern: int) -> void:
	var pos := map.random_spot(active_room, player.global_position, 5.5)
	pending_spawns += 1
	FX.spawn_marker(pos, 0.7)
	Sfx.play("spawn", 0.1, -6.0)
	get_tree().create_timer(0.7, false).timeout.connect(func():
		pending_spawns -= 1
		if state == State.LOSE:
			return
		var e := Enemy.new()
		e.pattern = pattern
		world.add_child(e)
		e.global_position = pos)


''')
rep('''	kills += 1
	_wave_kills += 1
	hitstop(0.07)
	shake(0.35)
	camera.kill_punch(_e.global_position)
	if _wave_kills >= WAVES[wave - 1].size() and state == State.PLAY:
		if wave >= WAVES.size():
			_win()
		else:
			wave_delay = 1.6
			if player.hp < Player.MAX_HP:
				player.hp += 1''', '''	kills += 1
	hitstop(0.07)
	shake(0.35)
	camera.kill_punch(_e.global_position)
	if active_room >= 0 and state == State.PLAY:
		room_kills += 1
		if room_kills >= room_total:
			_clear_room()''')
rep('''	hud.message("ARENA CLEAR", "적 %d기 격파 · %.1f초 · R 키로 다시 시작" % [kills, time], Color("7cf5ff"))''',
    '''	hud.message("ALL ROOMS CLEAR", "방 %d곳 · 적 %d기 격파 · %.1f초 · R 키로 다시 시작" % [rooms_cleared, kills, time], Color("7cf5ff"))''')

# 자동 플레이: 적이 없으면 경로를 따라 다음 전투방으로
rep('''	# 가장자리 회피
	move += -p.global_position * 0.02
	out.move = move.limit_length(1.0)
	return out''', '''	if best == null:
		move += _bot_explore(p, out)
	out.move = move.limit_length(1.0)
	return out


func _bot_explore(p: Player, out: Dictionary) -> Vector3:
	bot_path_t -= get_physics_process_delta_time()
	if bot_path_t <= 0.0 or bot_path.is_empty():
		bot_path_t = 0.6
		var target := -1
		var bd := 1e9
		for r in map.rooms:
			if r.combat and r.state == "idle":
				var d: float = map.room_center_world(r.id).distance_to(p.global_position)
				if d < bd:
					bd = d
					target = r.id
		bot_path.clear()
		if target >= 0:
			bot_path = map.find_path(p.global_position, map.room_center_world(target))
	# 가까운 경유점은 건너뛴다
	while bot_path.size() > 1 and bot_path[0].distance_to(p.global_position) < 2.2:
		bot_path.pop_front()
	if bot_path.is_empty():
		return Vector3.ZERO
	var wp: Vector3 = bot_path[mini(2, bot_path.size() - 1)]
	var d := wp - p.global_position
	d.y = 0
	out.aim = p.global_position + d.normalized() * 4.0 + Vector3(0, 0.95, 0)
	out.boost = bot_path.size() > 12 and p.boost > 0.5
	return d.normalized()''')
io.open(p, "w", encoding="utf-8", newline="\n").write(s)

# HUD: 웨이브 → 방
p = "hud.gd"
h = io.open(p, encoding="utf-8").read()
a = '''	wave_label.text = "WAVE %d / %d" % [m.wave, m.WAVES.size()]
	count_label.text = "ENEMIES  %d" % m.enemies_left()'''
assert a in h
h = h.replace(a, '''	wave_label.text = "ROOMS  %d / %d" % [m.rooms_cleared, m.combat_rooms()]
	count_label.text = ("ENEMIES  %d" % m.enemies_left()) if m.active_room >= 0 else "탐색 중"''')
io.open(p, "w", encoding="utf-8", newline="\n").write(h)

# 파편: 경기장 경계 → 맵 벽
p = "debris.gd"
d = io.open(p, encoding="utf-8").read()
a = '''		if absf(pos.x) > lim:
			pos.x = signf(pos.x) * lim
			v.x = -v.x * 0.4
		if absf(pos.z) > lim:
			pos.z = signf(pos.z) * lim
			v.z = -v.z * 0.4'''
assert a in d
d = d.replace(a, '''		var old := mi.global_position
		if pos.y < 1.2 and Main.inst.map.is_blocked(Vector3(pos.x, 0, old.z)):
			pos.x = old.x
			v.x = -v.x * 0.4
		if pos.y < 1.2 and Main.inst.map.is_blocked(Vector3(pos.x, 0, pos.z)):
			pos.z = old.z
			v.z = -v.z * 0.4''')
d = d.replace("	var lim := Main.HALF + 0.3\n", "")
io.open(p, "w", encoding="utf-8", newline="\n").write(d)
print("ok")
