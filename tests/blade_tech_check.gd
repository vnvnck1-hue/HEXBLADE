extends SceneTree
## Run with: Godot --headless --path . -s tests/blade_tech_check.gd
## 광선검 특수기(BladeTech) 확인. 전투 테스트장(training.tscn)에서 실제 입력 액션으로 누른다.
##  1. 좌클릭을 짧게 눌렀다 떼면 평소 콤보 검이 나간다 (기 모으기 아님).
##  2. 길게 누르면 HOLD 뒤 기 모으기 → 최대까지 모아 떼면 드릴 회오리 돌진: 경로 위 허수아비를 여러 번 벤다.
##  3. 반쯤 모아 떼면 일반 돌진: 최대가 아니고 한 번만 벤다. 최대보다 짧다.
##  4. 콤보 도중 좌+우클릭 동시 → 뒤로 물러서며 단타 레이저. 에너지를 쓰지 않고, 이어서 누르면(물러서는 중에 눌러도) 다음 단(2타)이 나간다.

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


## 허수아비 하나를 조준 방향 dist m 앞에 세우고 플레이어를 홀 가운데로 되돌린다
func _setup(dist: float) -> TrainingDummy:
	Input.action_release("slash_mouse")
	Input.action_release("fire_mouse")
	player.global_position = main.center + Vector3(0, 0, 4.5)
	player.velocity = Vector3.ZERO
	player.slash_cd = 0.0
	player.laser_cd = 0.0
	player.combo.cancel(true)
	main.layout = 0
	main._place()
	await _frames(2)
	var d: TrainingDummy = main.dummies[0]
	d.anchor = player.global_position + player.aim_dir * dist
	d.global_position = d.anchor
	await _secs(0.8)            # 착지 기다림
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

	# ── 1. 짧게 누르기 = 콤보 검 ──
	await _setup(2.5)
	Input.action_press("slash_mouse")
	await _frames(4)
	Input.action_release("slash_mouse")
	await _frames(2)
	_check(player.combo.posing() and not player.tech.charging(), "짧게 누르면 콤보 검 (콤보 %s · 기 모으기 %s)" % [player.combo.posing(), player.tech.charging()])
	await _secs(1.2)

	# ── 2. 최대 기 모으기 → 드릴 회오리 돌진 ──
	var d := await _setup(5.0)
	var hits0 := main.hit_count
	var start := player.global_position
	Input.action_press("slash_mouse")
	await _secs(BladeTech.HOLD + 0.1)
	_check(player.tech.charging(), "HOLD(%.2f초) 넘게 누르면 기 모으기 시작" % BladeTech.HOLD)
	_check(player.velocity.length() < 0.5, "기 모으는 동안 제자리에 선다 (속도 %.2f)" % player.velocity.length())
	var jk_lo := player.tech.jet_k()
	# 카메라는 부드럽게 미끄러지지 않고 단계마다 한 칸씩 물러난다
	var levels := {}
	var cam := main.camera
	for f in int((BladeTech.CHARGE_TIME + 0.1) * 60.0):
		levels[snappedf(cam.charge_zoom, 0.001)] = true
		await physics_frame
	levels[snappedf(cam.charge_zoom, 0.001)] = true
	_check(levels.size() == BladeTech.ZOOM_LEVELS.size() and is_equal_approx(cam.charge_zoom, BladeTech.ZOOM_LEVELS[-1]),
		"기 모으는 동안 줌아웃이 %d단계로 계단식 (%s)" % [levels.size(), str(levels.keys())])
	_check(is_equal_approx(player.tech.k, 1.0), "끝까지 모으면 최대 (k=%.2f)" % player.tech.k)
	_check(player.tech.jet_k() > jk_lo + 1.0, "모을수록 부스터가 거세진다 (%.2f → %.2f)" % [jk_lo, player.tech.jet_k()])
	Input.action_release("slash_mouse")
	await _frames(2)
	_check(player.tech.rushing() and player.tech.whirl(), "떼면 최대 돌진(드릴 회오리)")
	_check(is_equal_approx(player.trail.life, BladeTech.SPIRAL_LIFE), "최대 돌진 중 광선검 리본이 오래 남는다 (%.2f초)" % player.trail.life)
	await _secs(BladeTech.MAX_TIME + 0.3)
	var moved := start.distance_to(player.global_position)
	var mh := main.hit_count - hits0
	_check(not player.tech.busy(), "돌진이 끝나면 평소 상태로")
	_check(moved > 6.0, "길게 돌진한다 (%.1fm)" % moved)
	_check(mh >= 3, "경로 위 허수아비를 여러 번 벤다 (%d타)" % mh)
	_check(player.visual.basis.get_euler().length() < 0.05, "드릴 자세가 풀려 똑바로 선다")
	var max_moved := moved
	await _secs(0.6)
	_check(is_equal_approx(main.camera.charge_zoom, 1.0), "돌진이 끝나면 줌이 돌아온다 (%.2f)" % main.camera.charge_zoom)
	_check(is_equal_approx(player.trail.life, Player.SABER_RIBBON_LIFE) and is_equal_approx(player.trail.bright, Player.SABER_RIBBON_BRIGHT), "나선이 사라진 뒤 리본 수명 · 밝기가 평소로 (%.3f초 · %.2f)" % [player.trail.life, player.trail.bright])

	# ── 3. 반쯤 모으기 → 일반 돌진 ──
	d = await _setup(4.0)
	hits0 = main.hit_count
	start = player.global_position
	Input.action_press("slash_mouse")
	await _secs(BladeTech.HOLD + 0.5)
	var hk := player.tech.k
	Input.action_release("slash_mouse")
	if OS.get_cmdline_user_args().has("--trace"):
		for f in 30:
			await physics_frame
			print("TR f=%d st=%d pos=%.2f vel=%.1f t=%.3f dur=%.3f ts=%.2f" % [f, player.tech.st, start.distance_to(player.global_position), player.velocity.length(), player.tech.t, player.tech._dur, Engine.time_scale])
	await _frames(2)
	_check(player.tech.rushing() and not player.tech.whirl(), "반쯤 모아 떼면 일반 돌진 (k=%.2f)" % hk)
	await _secs(0.4)
	moved = start.distance_to(player.global_position)
	_check(main.hit_count - hits0 == 1, "일반 돌진은 한 번 벤다 (%d타)" % (main.hit_count - hits0))
	_check(moved > 3.0 and moved < max_moved, "모은 만큼만 간다 (%.1fm < 최대 %.1fm)" % [moved, max_moved])
	await _secs(0.6)

	# ── 4. 콤보 중 좌+우 동시 → 회피 레이저 ──
	d = await _setup(2.2)
	var e0 := player.energy
	Input.action_press("slash_mouse")
	await _frames(3)
	Input.action_release("slash_mouse")
	await _frames(14)
	_check(player.combo.posing(), "1타 진행 중")
	var near := player.global_position.distance_to(d.global_position)
	main.infinite = false
	e0 = player.energy
	Input.action_press("slash_mouse")
	Input.action_press("fire_mouse")
	await _frames(2)
	_check(player.tech.backstepping(), "콤보 중 좌+우 동시 → 회피 레이저")
	_check(player.invuln > 0.0, "물러서는 동안 무적")
	await _frames(8)
	Input.action_release("slash_mouse")
	Input.action_release("fire_mouse")
	_check(player.laser_cd > 0.0, "단타 레이저 발사")
	await _frames(8)
	var far := player.global_position.distance_to(d.global_position)
	_check(far > near + 1.0, "뒤로 물러선다 (%.1fm → %.1fm)" % [near, far])
	_check(player.energy == e0, "에너지를 쓰지 않는다 (%d → %d)" % [e0, player.energy])
	_check(player.combo.link_t > 0.0 and player.combo.next_step == 1, "링크가 열려 다음 단을 기다린다 (link %.2f · 다음 %d단)" % [player.combo.link_t, player.combo.next_step + 1])
	main.infinite = true
	# 회피 레이저가 끝나기 전에 눌러도 버퍼에 남았다가 끝나자마자 다음 단이 나간다
	Input.action_press("slash_mouse")
	await _frames(2)
	Input.action_release("slash_mouse")
	for f in 60:
		if not player.tech.backstepping():
			break
		await physics_frame
	await _frames(3)
	_check(player.combo.step == 1, "이어서 누르면 2타가 나간다 (%d타)" % (player.combo.step + 1))

	print("RESULT %s (%d fails)" % ["OK" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
