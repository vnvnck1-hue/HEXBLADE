extends SceneTree
## Run with: Godot --headless --path . -s tests/leap_slam_check.gd
## E 도약 내려찍기 확인. 전투 테스트장(training.tscn)에서 실제 입력 액션(rush_skill = E)으로 누른다.
## 조준은 Player.aim_override 로 정한다 (헤드리스에는 마우스가 없다).
##  1. E 를 누르는 동안 조준점 자리에 원형 착지 인디케이터가 뜬다 (범위 안 적 수 · 그림).
##  2. 떼면 그 자리로 도약한다: 높이 뜨고 무적, 착지점에 내려앉는다.
##  3. 착지하면 범위 안 적만 피해 + 1초 기절, 범위 밖 적은 그대로. 쿨타임이 걸린다.
##  4. 사거리를 넘는 조준은 사거리 끝에 붙는다. 쿨타임 중에는 조준이 뜨지 않는다.

var fails := 0
var main: TrainingMain
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


func _secs(s: float) -> void:
	await _frames(int(ceil(s * 60.0)))


func _dummy(at: Vector3) -> TrainingDummy:
	var d := main._spawn_dummy(at)
	d.anchor = at
	d.global_position = at
	d.immortal = true
	return d


func _run() -> void:
	var scene: PackedScene = load("res://scenes/training.tscn")
	main = scene.instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(30)
	player = main.player
	main.god = true
	main.infinite = true

	_check(InputMap.action_get_events("rush_skill").any(func(e): return e is InputEventKey and e.physical_keycode == KEY_E), "E 는 도약 내려찍기(rush_skill) 키")

	# 무대: 플레이어 앞 6m 착지점, 그 둘레(1.8m)에 하나, 범위 밖(착지점에서 6m)에 하나
	for d in main.dummies:
		if is_instance_valid(d):
			d.queue_free()
	main.dummies.clear()
	player.global_position = main.center + Vector3(0, 0, 4.5)
	player.velocity = Vector3.ZERO
	await _frames(2)
	var target := player.global_position + Vector3(0, 0, -6.0)
	var a := _dummy(target + Vector3(0.6, 0, 0))
	var b := _dummy(target + Vector3(-1.8, 0, 0.3))
	var c := _dummy(target + Vector3(6.0, 0, 0))
	await _secs(0.9)          # 착지 기다림
	player.aim_override = Vector3(target.x, player.global_position.y + 0.95, target.z)
	await _frames(2)

	# ── 1. 누르는 동안 착지 인디케이터 ──
	var start := player.global_position
	Input.action_press("rush_skill")
	await _frames(12)
	var ind: Node3D = player.leap._ind
	_check(player.leap.aiming() and is_instance_valid(ind), "E 를 누르는 동안 착지 인디케이터가 뜬다")
	_check(not player.leap.busy() and start.distance_to(player.global_position) < 0.3, "누르는 동안은 아직 뛰지 않는다")
	var at: Vector3 = player.leap.aim_to
	_check(Vector2(at.x - target.x, at.z - target.z).length() < 0.3, "인디케이터 = 마우스(조준) 자리 (%.2fm 차)" % Vector2(at.x - target.x, at.z - target.z).length())
	_check(player.leap.aim_count == 2, "범위 안 적 2기를 잠금 표시 (%d)" % player.leap.aim_count)
	if is_instance_valid(ind):
		var mi := ind.get_child(0) as MeshInstance3D
		_check(mi.mesh is ImmediateMesh and mi.mesh.get_surface_count() > 0 and (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 2000,
			"메카닉 원형 인디케이터를 그린다 (꼭짓점 %d)" % ((mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() if mi.mesh.get_surface_count() > 0 else 0))

	# ── 2. 떼면 도약 ──
	var hits0 := main.hit_count
	Input.action_release("rush_skill")
	await _frames(2)
	_check(player.leap.busy() and not is_instance_valid(ind), "떼면 도약 시작 · 인디케이터 사라짐")
	_check(absf(player.leap.cd - LeapSlam.CD) < 0.1, "쿨타임 %.0f초 (%.2f)" % [LeapSlam.CD, player.leap.cd])
	var top := 0.0
	var inv_ok := true
	for i in 40:
		await physics_frame
		if player.leap.flying():
			top = maxf(top, player.global_position.y - Main.gy(player.global_position))
			inv_ok = inv_ok and player.invuln > 0.0
	_check(top > 2.0, "높이 뛰어오른다 (정점 %.2fm)" % top)
	_check(inv_ok, "도약 중 무적")
	await _secs(0.3)
	var land := player.global_position
	_check(Vector2(land.x - target.x, land.z - target.z).length() < 0.6, "착지점에 내려앉는다 (%.2fm 차)" % Vector2(land.x - target.x, land.z - target.z).length())
	_check(player.leap.slams == 1 and player.leap.last_hits == 2, "범위 안 적 2기만 맞힌다 (%d)" % player.leap.last_hits)
	_check(main.hit_count - hits0 == 2, "피해 기록 2타 (%d)" % (main.hit_count - hits0))
	_check(a.stagger_t > 0.3 and b.stagger_t > 0.3 and c.stagger_t <= 0.0, "맞은 적은 기절 · 범위 밖은 그대로 (%.2f %.2f %.2f)" % [a.stagger_t, b.stagger_t, c.stagger_t])
	_check(absf(a.stagger_total - LeapSlam.STUN) < 0.01, "기절 시간 %.1f초" % LeapSlam.STUN)
	await _secs(0.9)
	_check(a.stagger_t <= 0.0 and b.stagger_t <= 0.0, "1초 뒤 기절이 풀린다")
	_check(not player.leap.busy(), "착지 후 다시 움직일 수 있다")

	# ── 3. 쿨타임 중에는 조준이 안 뜬다 ──
	Input.action_press("rush_skill")
	await _frames(6)
	_check(not player.leap.aiming(), "쿨타임 중에는 조준이 뜨지 않는다")
	Input.action_release("rush_skill")
	await _frames(4)
	_check(not player.leap.busy(), "쿨타임 중에는 뛰지 않는다")
	await _secs(player.leap.cd + 0.1)
	_check(player.leap.ready(), "쿨타임이 끝나면 다시 준비")

	# ── 4. 사거리 밖 조준은 사거리 끝 ──
	player.global_position = main.center + Vector3(0, 0, 4.5)
	await _frames(2)
	player.aim_override = player.global_position + Vector3(0, 0.95, -30.0)
	Input.action_press("rush_skill")
	await _frames(6)
	var far: Vector3 = player.leap.aim_to
	var fd := Vector2(far.x - player.global_position.x, far.z - player.global_position.z).length()
	_check(player.leap.aim_clamped and fd <= LeapSlam.RANGE + 0.01 and fd > 2.0, "사거리를 넘는 조준은 사거리 안에 붙는다 (%.2fm)" % fd)
	Input.action_release("rush_skill")
	await _secs(1.0)
	_check(player.leap.slams == 2 and not player.leap.busy(), "사거리 끝으로 도약해 내려찍는다")
	player.aim_override = Vector3.INF

	print("RESULT %s (%d fails)" % ["OK" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
