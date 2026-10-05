extends SceneTree
## Run with: Godot --headless --path . -s tests/input_buffer_check.gd
## 선입력 버퍼 확인. 전투 테스트장(training.tscn)에서 실제 입력 액션(slash = F, dash = Space, rush_skill = E)으로 누른다. (대시 도중 검은 이제 곧바로 일격참, E 는 도약 내려찍기)
##  1. InputBuffer: WINDOW 초 뒤 사라지고, 마지막 입력이 이기고, hold 동안은 줄지 않는다.
##  2. 대시 쿨타임이 끝나기 직전에 누른 대시는 쿨타임이 끝나는 순간 나간다. 너무 일찍 누르면 사라진다.
##  3. 대시 도중 누른 검은 대시가 끝나자마자 나간다.
##  4. 헛친 경직이 풀리기 직전에 누른 검은 풀리자마자 나간다. 너무 일찍 누르면 사라진다.
##  5. 돌진 스킬 도중 누른 대시는 돌진이 끝나자마자 나간다. 대시 도중 톡 누른 E 는 대시가 끝나자마자 돌진한다.
##  6. 검을 누르고 있으면 적중하는 동안 콤보가 다음 단으로 저절로 이어진다.
##  7. 2단 대시는 타이밍 판정이라 일찍 누른 입력으로 성공하지 않는다.

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


## 짧게 누른다 (테스트 코루틴은 플레이어 틱 뒤에 깨어나므로 누른 입력은 다음 틱에 읽힌다)
func _tap(action: String) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)


## cond 가 참이 될 때까지 (최대 n 틱). 참이 되었으면 true
func _until(cond: Callable, n := 240) -> bool:
	for i in n:
		if cond.call():
			return true
		await physics_frame
	return cond.call()


## 평소 상태로 되돌린다. dummy_dist > 0 이면 허수아비를 조준 방향 그 거리에, 아니면 멀리 치운다
func _reset(dummy_dist := 0.0) -> void:
	for a in ["slash", "dash", "rush_skill"]:
		Input.action_release(a)
	player.combo.cancel(true)
	player.tech.abort()
	await _until(func(): return player.dash_t <= 0.0 and player.lunge_t <= 0.0)
	player.global_position = main.center + Vector3(0, 0, 4.5)
	player.velocity = Vector3.ZERO
	main.layout = 0
	main._place()
	await _frames(2)
	var d: TrainingDummy = main.dummies[0]
	var dir := player.aim_dir
	d.anchor = player.global_position + (dir * dummy_dist if dummy_dist > 0.0 else Vector3(25, 0, 0))
	d.global_position = d.anchor
	d.immortal = true
	await _secs(0.9)
	player.dash_cd = 0.0
	player.slash_cd = 0.0
	player.leap.cd = 0.0
	player.phantom_ready = false
	player.inbuf.clear()


func _run() -> void:
	# ── 1. 버퍼 단위 동작 ──
	var b := InputBuffer.new()
	b.push("slash")
	b.tick(InputBuffer.WINDOW * 0.5)
	_check(b.has("slash"), "창 안에서는 남아 있다")
	b.tick(InputBuffer.WINDOW * 0.6)
	_check(not b.has("slash"), "%.2f초가 지나면 사라진다" % InputBuffer.WINDOW)
	b.push("slash")
	b.push("dash")
	_check(b.has("dash") and not b.has("slash"), "마지막에 누른 행동이 이긴다")
	b.tick(10.0, true)
	_check(b.has("dash"), "hold 동안은 줄지 않는다")
	_check(b.take("dash") and not b.has("dash"), "꺼내면 비워진다")

	var scene: PackedScene = load("res://scenes/training.tscn")
	main = scene.instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(30)
	player = main.player
	main.god = true
	main.infinite = true

	# ── 2. 대시 쿨타임 선입력 ──
	await _reset()
	await _tap("dash")
	_check(player.dash_t > 0.0, "대시가 나간다")
	await _until(func(): return player.dash_t <= 0.0 and player.dash_cd <= 0.1)
	_check(player.dash_cd > 0.0, "쿨타임이 %.2f초 남았을 때" % player.dash_cd)
	await _tap("dash")
	_check(player.dash_t <= 0.0, "쿨타임 중에는 바로 나가지 않는다")
	var fired := await _until(func(): return player.dash_t > 0.0, 12)
	_check(fired, "쿨타임이 끝나는 순간 미리 누른 대시가 나간다")

	await _reset()
	await _tap("dash")
	await _until(func(): return player.dash_t <= 0.0)
	await _frames(2)
	_check(player.dash_cd > InputBuffer.WINDOW + 0.1, "쿨타임이 많이 남았을 때 (%.2f초)" % player.dash_cd)
	await _tap("dash")
	await _until(func(): return player.dash_cd <= 0.0)
	await _frames(3)
	_check(player.dash_t <= 0.0, "너무 일찍 누른 대시는 사라진다")

	# ── 3. 대시 → 검: 대시 도중 누른 검은 곧바로 일격참 (대시를 끊는다) ──
	await _reset()
	await _tap("dash")
	await _frames(2)
	await _tap("slash")
	_check(player.dash_t <= 0.0 and not player.combo.posing(), "대시 도중 검 → 대시가 끊기고 콤보가 아닌 일격참")
	var slashed := await _until(func(): return player.slash_anim > 0.0, 12)
	_check(slashed, "일격참이 끝나며 베어 낸다")

	# ── 4. 헛친 경직 ──
	await _reset()
	await _tap("slash")
	var whiffed := await _until(func(): return player.combo.ph == SwordCombo.Ph.WHIFF, 90)
	_check(whiffed, "허공을 베면 헛친 경직")
	# slash_cd 는 광선검 속도 배율(Player.blade_k)로 줄어든다 → 남은 실제 시간 = slash_cd / blade_k
	await _until(func(): return player.slash_cd / player.blade_k() <= 0.1 and not player.combo.committed())
	_check(player.slash_cd > 0.0, "경직이 %.2f초 남았을 때" % (player.slash_cd / player.blade_k()))
	await _tap("slash")
	slashed = await _until(func(): return player.combo.committed(), 12)
	_check(slashed, "경직이 풀리자마자 미리 누른 검이 나간다")

	await _reset()
	await _tap("slash")
	await _until(func(): return player.combo.ph == SwordCombo.Ph.WHIFF, 90)
	await _frames(1)
	_check(player.slash_cd > InputBuffer.WINDOW + 0.1, "경직이 많이 남았을 때 (%.2f초)" % player.slash_cd)
	await _tap("slash")
	await _until(func(): return player.slash_cd <= 0.0 and not player.combo.committed())
	await _frames(3)
	_check(not player.combo.committed(), "너무 일찍 누른 검은 사라진다")

	# ── 5. 도약 내려찍기 ↔ 대시 ──
	await _reset()
	Input.action_press("rush_skill")
	await _frames(4)
	Input.action_release("rush_skill")
	await _frames(2)
	_check(player.leap.busy(), "도약 내려찍기가 나간다")
	await _tap("dash")
	_check(player.dash_t <= 0.0, "도약 도중에는 대시가 나가지 않는다")
	await _until(func(): return not player.leap.busy())
	var dashed := await _until(func(): return player.dash_t > 0.0, 4)
	_check(dashed, "착지가 끝나자마자 도약 도중 누른 대시가 나간다")

	await _reset()
	await _tap("dash")
	await _frames(2)
	await _tap("rush_skill")
	_check(not player.leap.busy() and not player.leap.aiming(), "대시 도중에는 도약하지 않는다")
	await _until(func(): return player.dash_t <= 0.0)
	var leapt := await _until(func(): return player.leap.busy(), 4)
	_check(leapt, "대시가 끝나자마자 대시 도중 톡 누른 E 로 도약한다")
	await _until(func(): return not player.leap.busy())

	# ── 6. 누르고 있으면 콤보가 이어진다 ──
	await _reset(2.0)
	Input.action_press("slash")
	var deep := await _until(func(): return player.combo.step >= 2, 240)
	Input.action_release("slash")
	_check(deep, "검을 누르고만 있어도 적중하는 동안 3단까지 이어진다 (단 %d)" % (player.combo.step + 1))

	# ── 7. 2단 대시는 미리 눌러 둔 입력으로 성공하지 않는다 ──
	await _reset()
	await _tap("dash")
	await _frames(2)
	await _tap("dash")               # 너무 이르다
	await _until(func(): return player.dash_t <= 0.0)
	await _frames(6)
	_check(not player.whirl.armed(), "일찍 누른 2단 대시는 버퍼로 성공하지 않는다")

	await _reset()
	await _tap("dash")
	await _until(func(): return player.dash_t <= Player.CHAIN_WINDOW * 0.7)
	await _tap("dash")
	_check(player.rainbow and player.whirl.armed(), "제때 누른 2단 대시는 그대로 성공한다 (휠윈드 장전)")

	print("RESULT %s (%d fails)" % ["OK" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
