extends SceneTree
## Run with: Godot --headless --path . -s tests/stream_mode_check.gd
## 무한 비행 모드 (StreamMain, scenes/stream.tscn)
##  1. 흐르는 공간이 켜지고, 도로가 흐르는 만큼 비행 거리가 쌓인다
##  2. 편대가 화면 위(-Z)에서 날아 들어와 아래(+Z)로 내려온다
##  3. 격추하지 못한 전투기는 화면 아래로 빠져나가 사라지고 "놓침" 으로 센다 (처치 수에는 안 들어간다)
##  4. 한 편대를 모두 격추하면 편대 보너스 점수와 재화가 나온다
##  5. 시간이 지나면 섹터가 올라 도로가 빨라지고 적이 단단해진다, 정예 섹터에는 크롤러가 나온다
##  6. 포격 드론은 앞쪽에 버티다가 정해진 시간이 지나면 위로 빠져나간다
##  7. 모든 편대 종류가 오류 없이 뜬다, 플레이어는 차선 안에 묶인다
##  8. 격추되면 끝나고 비행 거리 기록이 남는다

var fails := 0
var main: StreamMain


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		if is_instance_valid(main) and is_instance_valid(main.player) and main.state == Main.State.PLAY:
			main.player.invuln = 999.0
		await physics_frame


func _fighters() -> Array:
	var out := []
	for e in get_nodes_in_group("enemies"):
		if e is StreamFighter:
			out.append(e)
	return out


func _clear_enemies() -> void:
	for e in get_nodes_in_group("enemies"):
		e.remove_from_group("enemies")
		e.queue_free()
	for b in get_nodes_in_group("enemy_bullets"):
		b.queue_free()
	main.schedule.clear()
	main.waves.clear()
	await _frames(2)


func _run() -> void:
	main = load("res://scenes/stream.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	main.save_records = false     # 기록 파일(user://)을 건드리지 않게
	main.wave_timer = 9999.0      # 자동 편대는 끄고 직접 띄운다
	await _frames(5)

	# 1. 흐르는 공간 · 거리
	_check(WorldFlow.active() and is_equal_approx(WorldFlow.road_v(), StreamMain.SPEED_START), "흐르는 공간 켜짐 (도로 %.0f m/s)" % WorldFlow.road_v())
	var d0 := main.distance
	await _frames(60)
	var gained := main.distance - d0
	_check(absf(gained - StreamMain.SPEED_START) < 2.0, "1초에 도로 속도만큼 비행 거리 (%.1f m)" % gained)

	# 2. 편대 진입
	var id := main.launch("line")
	await _frames(3)
	var fs := _fighters()
	var n := fs.size()
	_check(n >= 4, "가로 편대 %d기 등장" % n)
	var z_start := 0.0
	for f in fs:
		z_start += (f as Node3D).global_position.z
	z_start /= maxf(n, 1)
	_check(z_start < -20.0, "편대는 화면 위 바깥에서 나온다 (평균 z %.1f)" % z_start)
	await _frames(60)
	var z_now := 0.0
	for f in fs:
		if is_instance_valid(f):
			z_now += (f as Node3D).global_position.z
	z_now /= maxf(n, 1)
	_check(z_now - z_start > 5.0, "편대가 아래(+Z)로 내려온다 (%.1f → %.1f)" % [z_start, z_now])

	# 3. 놓침: 그대로 두면 화면 아래로 빠져나간다 (플레이어는 쏘지 않는다)
	var kills0 := main.kills
	var esc0 := main.escaped
	for i in 600:
		await _frames(1)
		if _fighters().is_empty():
			break
	_check(_fighters().is_empty(), "격추하지 않은 전투기는 모두 화면 밖으로 사라진다")
	_check(main.escaped - esc0 == n and main.kills == kills0, "놓침 %d · 처치 수 그대로 (%d)" % [main.escaped - esc0, main.kills - kills0])
	_check(not main.waves.has(id), "놓친 편대는 정리된다 (보너스 없음)")
	await _clear_enemies()

	# 4. 편대 전멸 보너스
	id = main.launch("vee")
	await _frames(60)
	var score0 := main.score
	var picks0 := get_nodes_in_group("pickups").size()
	var killed := 0
	for i in 120:
		for f in _fighters():
			var e := f as StreamFighter
			if e.alive and e.landed:
				e.take_hit(99, Vector3.FORWARD, e.global_position, "bullet")
				killed += 1
		await _frames(1)
		if not main.waves.has(id):
			break
	_check(killed == 5, "V 편대 5기 격추 (%d)" % killed)
	_check(not main.waves.has(id), "편대 전멸 처리")
	_check(main.score - score0 >= StreamMain.WAVE_BONUS, "편대 보너스 점수 (+%d)" % (main.score - score0))
	_check(get_nodes_in_group("pickups").size() > picks0, "편대 보너스 재화가 떨어진다")
	# 떨어진 재화는 화면 아래로 흘러간다
	var pk: Node3D = get_nodes_in_group("pickups").back()
	var pz := pk.position.z
	await _frames(30)
	_check(is_instance_valid(pk) and pk.position.z > pz + 1.0, "재화가 공간과 함께 아래로 흘러간다")
	await _clear_enemies()

	# 5. 섹터 상승
	var hp1 := main.hp_scale()
	main.time = StreamMain.SECTOR_TIME + 0.1
	await _frames(120)
	_check(main.sector == 2, "%d초 뒤 섹터 2" % int(StreamMain.SECTOR_TIME))
	_check(main.stage.speed > StreamMain.SPEED_START + 1.0, "섹터가 오르면 도로가 빨라진다 (%.1f m/s)" % main.stage.speed)
	_check(main.hp_scale() > hp1 and main.max_alive() > 7, "적 체력 배율 %.2f · 동시 %d" % [main.hp_scale(), main.max_alive()])
	main.time = StreamMain.SECTOR_TIME * (StreamMain.ELITE_EVERY - 1) + 0.1
	await _frames(200)
	var elite := false
	for e in get_nodes_in_group("enemies"):
		if e is Crawler and e.has_meta("stream_elite"):
			elite = true
	_check(main.sector == StreamMain.ELITE_EVERY and elite and main.elite_alive, "섹터 %d 정예 크롤러 출현" % main.sector)
	await _clear_enemies()
	main.elite_alive = false

	# 6. 포격 드론 이탈
	main.launch("gunship")
	await _frames(90)
	var drones := []
	for e in get_nodes_in_group("enemies"):
		if e is StreamDrone:
			drones.append(e)
	_check(drones.size() >= 2, "포격 드론 %d기" % drones.size())
	var ahead := true
	for d in drones:
		if (d as Node3D).global_position.z > main.player.global_position.z - 3.0:
			ahead = false
	_check(ahead, "드론은 플레이어 앞쪽에 머문다")
	for d in drones:
		(d as StreamDrone).stay = 0.5
	var esc1 := main.escaped
	for i in 400:
		await _frames(1)
		var any := false
		for d in drones:
			if is_instance_valid(d) and (d as StreamDrone).alive:
				any = true
		if not any:
			break
	_check(main.escaped - esc1 == drones.size(), "시간이 지난 드론은 위로 빠져나간다 (놓침 %d)" % (main.escaped - esc1))
	await _clear_enemies()

	# 7. 모든 편대 종류
	main.sector = 8
	for k in ["line", "vee", "snake", "swoop", "hook", "dive", "pincer", "bomber", "gunship", "striker", "storm"]:
		main.launch(k)
		await _frames(50)
		await _clear_enemies()
	_check(true, "편대 11종 모두 띄움 (오류는 로그 확인)")
	main.player.global_position = Vector3(40, 0, -40)
	await _frames(2)
	var pp := main.player.global_position
	_check(absf(pp.x) <= 10.0 and pp.z >= StreamMain.PLAYER_Z_MIN - 0.01, "플레이어는 차선 안에 묶인다 (%.1f, %.1f)" % [pp.x, pp.z])

	# 8. 격추 → 끝 · 기록
	main.best.distance = 0.0
	main.player.invuln = 0.0
	main.player.hp = 1
	main.player.take_hit(main.player.global_position + Vector3(0, 0, -2))
	await _frames(30)
	_check(main.state == Main.State.LOSE, "격추되면 끝")
	_check(main.new_best and float(main.best.distance) > 0.0, "비행 거리 기록 %.0f m" % float(main.best.distance))
	var d_end := main.distance
	await _frames(30)
	_check(main.distance == d_end, "끝난 뒤에는 거리가 늘지 않는다")

	print("RESULT %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
