extends SceneTree
## Run with: Godot --headless --path . -s tests/ammo_check.gd
## 한정 재화(에너지 · 미사일) 규칙을 실제 입력으로 확인한다.
##  1. 레이저: 에너지가 없으면 충전되지 않고, 최소 발사 1칸 · 2단 2칸 · 최대 3칸을 쓴다.
##     가진 에너지로 쏠 수 있는 단계까지만 모인다.
##  2. 미사일: 1발 이상 있어야 궁극기가 발동하고, 가진 개수만큼만 발사된다.
##     적이 죽으면 가끔 그 자리에 떨어지고, 플레이어가 직접 닿아야 먹힌다. 가득 차면 먹지 않는다.
##  3. HUD: 최대치만큼 칸이 늘 있고, 가진 개수만큼 채워진다.

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


func _ready_laser() -> void:
	player.laser_cd = 0.0
	player.energy_regen_t = 0.0
	player.stun_t = 0.0
	await _frames(2)


## 좌+우클릭을 sec 초 동안 눌렀다 뗀다
func _charge(sec: float) -> float:
	Input.action_press("slash_mouse")
	Input.action_press("fire_mouse")
	await _frames(int(sec * 60.0))
	var k := player.charge
	Input.action_release("slash_mouse")
	Input.action_release("fire_mouse")
	await _frames(2)
	return k


func _missiles_in_world() -> int:
	var n := 0
	for c in FX.root.get_children():
		if c is Missile:
			n += 1
	return n


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(30)
	player = main.player
	player.invuln = 999.0

	# ── 1. 레이저 에너지 ──
	_check(player.energy == Player.ENERGY_MAX and Player.ENERGY_MAX == 3, "시작 에너지 3/3")
	player.energy = 0
	await _ready_laser()
	Input.action_press("slash_mouse")
	Input.action_press("fire_mouse")
	await _frames(40)
	_check(not player.charging and player.charge == 0.0, "에너지 0: 충전되지 않는다")
	Input.action_release("slash_mouse")
	Input.action_release("fire_mouse")
	await _frames(5)

	player.energy = 1
	await _ready_laser()
	var k := await _charge(1.5)
	_check(k < Player.CHARGE_STAGES[1] and k >= Player.CHARGE_STAGES[0], "에너지 1: 1단까지만 모인다 (%.2f)" % k)
	_check(player.energy == 0, "에너지 1: 1단 발사로 1칸 소모 → %d" % player.energy)

	player.energy = 2
	await _ready_laser()
	k = await _charge(1.5)
	_check(k < 1.0 and k >= Player.CHARGE_STAGES[1], "에너지 2: 2단까지만 모인다 (%.2f)" % k)
	_check(player.energy == 0, "에너지 2: 2단 발사로 2칸 소모 → %d" % player.energy)

	player.energy = 3
	await _ready_laser()
	k = await _charge(0.3)
	_check(k >= Player.CHARGE_MIN and k < Player.CHARGE_STAGES[0], "짧은 충전 (%.2f)" % k)
	_check(player.energy == 2, "최소 발사 단계도 1칸 소모 → %d" % player.energy)

	player.energy = 3
	await _ready_laser()
	k = await _charge(1.2)
	_check(k >= 1.0 and player.mega_t > 0.0, "에너지 3: 최대 레이저 발동")
	_check(player.energy == 0, "최대 레이저는 3칸 소모 → %d" % player.energy)
	await _frames(240)

	# 자연 재충전
	player.energy = 0
	player.energy_regen_t = Player.ENERGY_REGEN - 0.05
	await _frames(6)
	_check(player.energy == 1, "시간이 지나면 에너지 1칸이 찬다")

	# ── 2. 미사일 ──
	player.missiles = 0
	await _frames(2)
	Input.action_press("ult")
	await _frames(3)
	_check(not player.ult_aiming, "미사일 0: 궁극기가 발동하지 않는다")
	Input.action_release("ult")
	await _frames(40)

	player.missiles = 3
	var before := _missiles_in_world()
	Input.action_press("ult")
	await _frames(3)
	_check(player.ult_aiming, "미사일 3: 궁극기 조준 시작")
	Input.action_release("ult")
	await process_frame
	await _frames(2)
	_check(player.missiles == 0 and player.ult_count == 3, "발사: 가진 미사일 3발을 모두 장전하고 보유량은 0 (m=%d c=%d aim=%s)" % [player.missiles, player.ult_count, player.ult_aiming])
	await _frames(20)
	var fired := _missiles_in_world() - before
	_check(player.ult_queue == 0 and fired == 3, "가진 개수(3)만큼만 발사 → %d발" % fired)
	await _frames(120)

	# 픽업: 떨어진 자리에 직접 가야 먹힌다
	var p0 := player.global_position
	var spot := p0 + Vector3(4.0, 0, 0)
	if main.is_blocked(spot):
		spot = p0 + Vector3(-4.0, 0, 0)
	var pk := main.drop_pickup("missile", spot)
	await _frames(120)
	_check(is_instance_valid(pk) and player.missiles == 0, "멀리 있는 미사일 아이템은 저절로 먹히지 않는다")
	player.global_position = Vector3(pk.global_position.x, player.global_position.y, pk.global_position.z)
	await _frames(6)
	_check(player.missiles == 1, "아이템에 닿으면 미사일 +1 → %d" % player.missiles)
	await _frames(2)
	_check(not is_instance_valid(pk) or pk.is_queued_for_deletion(), "먹은 아이템은 사라진다")

	player.missiles = Player.MISSILE_MAX
	var pk2 := main.drop_pickup("missile", player.global_position)
	await _frames(90)
	_check(is_instance_valid(pk2) and player.missiles == Player.MISSILE_MAX, "가득 차 있으면 먹지 않고 남는다")
	pk2.queue_free()

	player.energy = 1
	var pk3 := main.drop_pickup("energy", player.global_position)
	await _frames(90)
	_check(player.energy == 2 and not is_instance_valid(pk3), "에너지 아이템도 주우면 +1")

	# 적 처치 드롭: 가끔 나온다 (항상은 아니다)
	var dummy := Enemy.new()
	main.world.add_child(dummy)
	dummy.global_position = spot
	var drops := 0
	var n_miss := 0
	for i in 200:
		var had := get_nodes_in_group("pickups").size()
		main._drop_loot(dummy)
		var now := get_nodes_in_group("pickups")
		if now.size() > had:
			drops += 1
		for q in now:
			if (q as Pickup).kind == "missile" and not q.is_queued_for_deletion():
				n_miss += 1
			q.queue_free()
		await process_frame
	_check(drops > 20 and drops < 180, "적 처치 드롭은 가끔 나온다 (200회 중 %d회)" % drops)
	_check(n_miss > 0, "미사일이 드롭된다")
	dummy.queue_free()

	# ── 3. HUD 아이콘 ──
	player.energy = 2
	player.missiles = 5
	await _frames(3)
	var hud := main.hud
	_check(hud.energy_icons.max_count == Player.ENERGY_MAX and hud.energy_icons.count == 2, "에너지 칸 3개 중 2개 채움")
	_check(hud.missile_icons.max_count == Player.MISSILE_MAX and hud.missile_icons.count == 5, "미사일 칸 %d개 중 5개 채움" % Player.MISSILE_MAX)
	_check(hud.missile_icons.visible and hud.energy_icons.visible, "아이콘 줄은 항상 보인다")

	print("RESULT %s (%d fails)" % ["OK" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
