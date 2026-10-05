extends SceneTree
## Run with: Godot --headless --path . -s tests/whirl_pull_check.gd
## 회오리(드론 합체 휠윈드)가 주변 몬스터를 조금씩 플레이어 쪽으로 끌어들이는지 확인. 전투 테스트장(training.tscn).
## 적 자체 이동이 섞이지 않게 시험용 적은 착지 뒤 물리(AI)를 멈춘다 (끌림은 드론이 위치를 옮긴다).
##  1. 반경 WHIRL_PULL_R 안 적은 휠윈드 동안 플레이어 쪽으로 끌려온다 (가까울수록 세게, 한 번에 순간이동하지 않고 조금씩).
##  2. 몸에 겹치기 직전(WHIRL_PULL_MIN)에서 멈춘다.
##  3. 반경 밖 적 · 보스는 끌리지 않는다. 휠윈드가 끝나면 더 끌리지 않는다.

var fails := 0
var main: TrainingMain
var player: Player
var drone: PartnerDrone


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _foe(at: Vector3, boss := false) -> Enemy:
	var e := Enemy.new()
	e.fire_timer = 999.0
	e.hp = 9999
	e.is_boss = boss
	main.world.add_child(e)
	e.global_position = main.push_out(at, 1.0)
	return e


func _run() -> void:
	var scene: PackedScene = load("res://scenes/training.tscn")
	main = scene.instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(60)
	player = main.player
	drone = PartnerDrone.inst
	main.god = true
	_check(is_instance_valid(drone), "전투 테스트장에 파트너 드론이 있다")
	for d in main.dummies:
		d.anchor = main.center + Vector3(0, 0, -9)
		d.global_position = d.anchor
	player.global_position = main.center
	await _frames(30)
	var c := player.global_position
	var near := _foe(c + Vector3(3.6, 0, 0))
	var mid := _foe(c + Vector3(-2.0, 0, 5.2))
	var far := _foe(c + Vector3(0, 0, PartnerDrone.WHIRL_PULL_R + 3.0))
	var boss := _foe(c + Vector3(-4.5, 0, -1.0), true)
	# 착지할 때까지 기다린 뒤 AI 를 멈춘다
	for i in 120:
		if near.landed and mid.landed and far.landed and boss.landed:
			break
		await physics_frame
	for e in [near, mid, far, boss]:
		(e as Enemy).set_physics_process(false)
		(e as Enemy).knock = Vector3.ZERO
	var d0 := {}
	for e in [near, mid, far, boss]:
		d0[e] = _flat((e as Node3D).global_position, player.global_position)
	PartnerDrone.cutin_style = "off"   # 사선 컷인의 슬로우모션 없이 게임 시간 그대로 끌림을 잰다
	drone.gauge = PartnerDrone.GAUGE_MAX
	drone.whirl_link()
	for i in 180:
		if drone.whirl_t >= 0.0:
			break
		await physics_frame
	_check(drone.whirl_t >= 0.0, "휠윈드 시작")
	var pp := player.global_position
	# 조금씩: 0.3초 동안 얼마나 끌려오나
	await _frames(18)
	var step_near := float(d0[near]) - _flat(near.global_position, player.global_position)
	var max_jump := 0.0
	var prev := mid.global_position
	for i in 1500:
		await process_frame
		max_jump = maxf(max_jump, _flat(mid.global_position, prev))
		prev = mid.global_position
		if drone.whirl_t < 0.0:
			break
	_check(drone.whirl_t < 0.0, "휠윈드가 끝났다")
	var dn := _flat(near.global_position, player.global_position)
	var dm := _flat(mid.global_position, player.global_position)
	var df := _flat(far.global_position, player.global_position)
	var db := _flat(boss.global_position, player.global_position)
	_check(step_near > 0.1 and step_near < 1.2, "조금씩 끌려온다: 처음 0.3초 동안 %.2fm" % step_near)
	_check(float(d0[mid]) - dm > 1.0, "반경 안 적이 플레이어 쪽으로 끌려왔다 (%.1f → %.1fm)" % [float(d0[mid]), dm])
	_check(max_jump < 0.3, "순간이동하지 않는다 (한 틱 최대 %.2fm)" % max_jump)
	var stop := PartnerDrone.WHIRL_PULL_MIN + near.radius
	_check(dn >= stop - 0.05 and dn < float(d0[near]) - 0.5, "몸에 겹치기 직전에서 멈춘다 (%.1f → %.2fm, 멈춤 %.2fm)" % [float(d0[near]), dn, stop])
	_check(absf(df - float(d0[far])) < 0.05, "반경 밖 적은 끌리지 않는다 (%.2f → %.2fm)" % [float(d0[far]), df])
	_check(absf(db - float(d0[boss])) < 0.05, "보스는 끌리지 않는다 (%.2f → %.2fm)" % [float(d0[boss]), db])
	_check(_flat(player.global_position, pp) < 0.5, "(확인) 플레이어는 제자리")
	var after := mid.global_position
	await _frames(40)
	_check(_flat(mid.global_position, after) < 0.01, "휠윈드가 끝나면 더 끌리지 않는다")

	print("RESULT %s (%d fails)" % ["OK" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
