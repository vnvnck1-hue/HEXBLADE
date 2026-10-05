extends SceneTree
## Run with: Godot --headless --path . -s tests/dash_moves_check.gd
## 대시 연계 확인. 전투 테스트장(training.tscn)에서 실제 입력 액션(dash = Space, slash = F)으로 누른다.
##  1. 대시 도중 검을 누르면 대시가 끊기고 곧바로 조준 방향으로 일격참(관통 일격) 돌진 → 앞의 적을 꿰뚫어 벤다.
##  2. 2단 대시를 제때 누르면 휠윈드가 장전되고(칼날 불꽃 3초), 그 안에 검을 누르면 드론 합체 휠윈드 빠르기로
##     5바퀴 돌며 천천히 움직이고, 둘레 적을 바퀴마다 벤다.
##  3. 2단 대시 도중 검도 휠윈드. 장전은 3초 뒤 꺼진다. 너무 일찍 누른 두 번째 대시는 장전되지 않는다. 휠윈드는 대시로 끊는다.

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


## 2틱 눌렀다 뗀다 (테스트 코루틴은 플레이어 틱 뒤에 깨어나 다음 틱에 읽힌다)
func _tap(a: String) -> void:
	Input.action_press(a)
	await _frames(2)
	Input.action_release(a)


func _reset(at: Vector3) -> void:
	for d in main.dummies:
		if is_instance_valid(d):
			d.queue_free()
	main.dummies.clear()
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.dash_cd = 0.0
	player.combo.cancel(true)
	await _frames(2)


## 대시 → 끝나기 직전 다시 대시 (2단 대시 성공)
func _chain() -> void:
	player.dash_cd = 0.0
	await _tap("dash")
	var n := 0
	while player.dash_t > Player.CHAIN_WINDOW * 0.6 and n < 60:
		await physics_frame
		n += 1
	await _tap("dash")


func _until_dash_end() -> void:
	var n := 0
	while player.dash_t > 0.0 and n < 60:
		await physics_frame
		n += 1


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

	# ── 1. 대시 도중 검 = 일격참 ──
	var home := main.center + Vector3(0, 0, 4.5)
	await _reset(home)
	var foe := _dummy(home + Vector3(0, 0, -5.0))
	await _secs(0.9)
	player.aim_override = Vector3(foe.global_position.x, player.global_position.y + 0.95, foe.global_position.z)
	player.dash_cd = 0.0
	await _frames(2)
	var hits0 := main.hit_count
	Input.action_press("move_right")          # 옆으로 대시하다가
	await _tap("dash")
	Input.action_release("move_right")
	await _frames(3)
	_check(player.dash_t > 0.0, "대시 중")
	await _tap("slash")                        # 대시 도중 검
	_check(player.dash_t <= 0.0 and (player.lunge_t > 0.0 or player.lunge_phantom or player.slash_anim > 0.0), "대시가 끊기고 일격참 돌진")
	await _secs(0.4)
	_check(main.hit_count > hits0, "앞의 적을 꿰뚫어 벤다 (%d타)" % (main.hit_count - hits0))
	var past := (player.global_position - home).dot(Vector3.FORWARD)
	_check(past > 5.0, "적을 지나 뒤로 빠져나간다 (앞으로 %.1fm)" % past)
	_check(not player.whirl.active(), "일격참은 휠윈드가 아니다")

	# ── 2. 2단 대시 성공 = 휠윈드 ──
	await _reset(home)
	var near := _dummy(home + Vector3(1.6, 0, -0.6))
	await _secs(0.9)
	player.aim_override = home + Vector3(0, 0.95, -5.0)
	player.dash_cd = 0.0
	await _frames(2)
	hits0 = main.hit_count
	await _tap("dash")
	var waited := 0
	while player.dash_t > Player.CHAIN_WINDOW * 0.6 and waited < 60:
		await physics_frame
		waited += 1
	await _tap("dash")
	_check(player.rainbow and player.dash_t > 0.0 and player.whirl.armed() and not player.whirl.active(),
		"제때 누른 2단 대시 → 무지개 대시 + 휠윈드 장전 (바로 돌지 않는다)")
	_check(not player.phantom_ready and player.blade_fx.lit, "칼날이 불타오른다 (관통 일격이 아니라 휠윈드 장전)")
	await _until_dash_end()
	await _frames(10)
	_check(player.whirl.armed() and not player.whirl.active(), "검을 누르기 전까지 장전 상태로 기다린다")
	var whirl_pos := player.global_position
	near.anchor = whirl_pos + Vector3(-1.4, 0, 0)
	near.global_position = near.anchor
	Input.action_press("move_left")
	await _tap("slash")
	_check(player.whirl.active() and not player.whirl.armed(), "장전 중 검 → 휠윈드")
	var t := 2.0 / 60.0
	var max_v := 0.0
	while player.whirl.active() and t < 3.0:
		await physics_frame
		t += 1.0 / 60.0
		if t > 0.04:
			max_v = maxf(max_v, Vector2(player.velocity.x, player.velocity.z).length())
	Input.action_release("move_left")
	_check(absf(DashWhirl.TURN_RATE - PartnerDrone.WHIRL_TURNS) < 0.01, "회전 빠르기 = 드론 합체 휠윈드 (초당 %.0f바퀴)" % DashWhirl.TURN_RATE)
	_check(t >= DashWhirl.TIME - 0.05 and t < DashWhirl.TIME + 0.16, "휠윈드 %.2f초 (%.2f, 적중 멈춤 포함)" % [DashWhirl.TIME, t])
	_check(player.whirl.turns_done == DashWhirl.TURNS, "%d바퀴 (%d)" % [DashWhirl.TURNS, player.whirl.turns_done])
	var moved := whirl_pos.distance_to(player.global_position)
	_check(absf(moved - DashWhirl.TRAVEL) < 1.0, "대시 거리만큼 이동하며 돈다 (%.2fm, 대시 %.2fm)" % [moved, DashWhirl.TRAVEL])
	_check(player.global_position.x < whirl_pos.x - 3.0, "이동키 쪽(왼쪽)으로 나간다")
	_check(max_v > Player.SPEED, "평소 걸음보다 빠르게 미끄러진다 (최고 %.1f m/s)" % max_v)
	_check(player.whirl.hits >= 3, "둘레 적을 바퀴마다 벤다 (%d타)" % player.whirl.hits)
	_check(is_equal_approx(player.trail.life, Player.SABER_RIBBON_LIFE), "끝나면 광선검 리본이 원래대로")

	# ── 3. 2단 대시 도중 검 · 장전 만료 · 이른 2단 대시 · 대시로 끊기 ──
	await _reset(home)
	await _secs(0.3)
	await _chain()
	await _frames(3)
	await _tap("slash")
	_check(player.whirl.active() and player.dash_t <= 0.0, "2단 대시 도중 검 → 대시를 끊고 휠윈드 (일격참 아님)")
	await _secs(0.6)
	await _reset(home)
	await _secs(1.0)
	await _chain()
	await _secs(DashWhirl.ARM_WINDOW + 0.2)
	_check(not player.whirl.armed() and not player.blade_fx.lit, "%.0f초 안에 쓰지 않으면 장전이 꺼진다" % DashWhirl.ARM_WINDOW)
	await _reset(home)
	await _secs(1.0)
	await _tap("dash")
	await _frames(3)
	await _tap("dash")
	await _secs(0.4)
	_check(not player.whirl.armed() and not player.whirl.active(), "너무 일찍 누른 2단 대시는 장전되지 않는다")
	await _secs(1.0)
	player.dash_cd = 0.0
	await _chain()
	await _until_dash_end()
	await _tap("slash")
	_check(player.whirl.active(), "다시 휠윈드")
	await _frames(4)
	await _tap("dash")
	await _frames(2)
	_check(not player.whirl.active() and player.dash_t > 0.0, "휠윈드는 대시로 끊는다")
	player.aim_override = Vector3.INF

	print("RESULT %s (%d fails)" % ["OK" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
