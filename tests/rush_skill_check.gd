extends SceneTree
## Run with: Godot --headless --path . -s tests/rush_skill_check.gd
## 돌진 스킬(E) 확인. 전투 테스트장(training.tscn)에서 실제 입력 액션(rush_skill = E)으로 누른다.
##  1. E 는 이제 검이 아니다: 누르는 동안 콤보가 나가지 않고 푸른 민트 인디케이터가 조준 방향·돌진 길이로 뜬다.
##  2. 떼면 그 방향으로 기 모으기의 1단계 짧은 돌진이 나간다 (최대 아님, 약 4m). 쿨타임 3초가 걸린다.
##  3. 쿨타임 중에는 눌러도 조준·돌진이 안 된다. 쿨타임이 끝나면 다시 된다.
##  4. 이 스킬로 적을 처치하면 남은 쿨타임이 1.5초로 줄어 1.5초 안에 다시 쓸 수 있다.

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


## 허수아비 하나를 스킬 조준 방향 dist m 앞에 세운다
func _setup(dist: float, killable: bool) -> TrainingDummy:
	Input.action_release("rush_skill")
	player.global_position = main.center + Vector3(0, 0, 4.5)
	player.velocity = Vector3.ZERO
	player.combo.cancel(true)
	main.layout = 0
	main._place()
	await _frames(2)
	var d: TrainingDummy = main.dummies[0]
	var dir := player.tech._skill_aim_dir()
	d.anchor = player.global_position + dir * dist
	d.global_position = d.anchor
	d.immortal = not killable
	await _secs(0.8)            # 착지 기다림
	if killable:
		d.hp = 1
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

	_check(not InputMap.action_get_events("slash").any(func(e): return e is InputEventKey and e.physical_keycode == KEY_E), "E 는 더 이상 검(slash) 키가 아니다")
	_check(InputMap.action_get_events("rush_skill").any(func(e): return e is InputEventKey and e.physical_keycode == KEY_E), "E 는 돌진 스킬(rush_skill) 키")

	# ── 1. 누르는 동안 조준 인디케이터 ──
	await _setup(3.0, false)
	var start := player.global_position
	Input.action_press("rush_skill")
	await _frames(6)
	var ind: Node3D = player.tech._skill_ind
	_check(player.tech.skill_aiming() and is_instance_valid(ind), "E 를 누르는 동안 스킬 인디케이터가 뜬다")
	_check(not player.combo.posing() and not player.tech.busy(), "E 를 눌러도 검이 나가지 않고 아직 돌진하지 않는다")
	if is_instance_valid(ind):
		var dir := player.tech._skill_aim_dir()
		var fwd := -ind.global_basis.z.normalized()
		_check(fwd.dot(dir) > 0.99, "인디케이터가 조준 방향을 가리킨다 (dot %.3f)" % fwd.dot(dir))
		var want := lerpf(BladeTech.DIST.x, BladeTech.DIST.y, BladeTech.SKILL_K) * BladeTech.SKILL_REACH
		var wid := lerpf(BladeTech.WIDTH.x, BladeTech.WIDTH.y, BladeTech.SKILL_K)
		_check(absf(BladeTech.SKILL_REACH - 1.3) < 0.001 and absf(want - lerpf(BladeTech.DIST.x, BladeTech.DIST.y, BladeTech.SKILL_K) * 1.3) < 0.01, "사거리 1단계의 130%% (%.1fm)" % want)
		_check(absf(player.tech.ind_len - want) < 0.6 and absf(player.tech.ind_width - wid) < 0.01, "인디케이터 크기 = 돌진 길이 %.1fm × 폭 %.2fm (%.2f × %.2f)" % [want, wid, player.tech.ind_len, player.tech.ind_width])
		var mi := ind.get_child(0) as MeshInstance3D
		_check(mi.mesh is ImmediateMesh and mi.mesh.get_surface_count() > 0, "메카닉 인디케이터를 그린다 (면 %d)" % mi.mesh.get_surface_count())
		var c := BladeTech.SKILL_COL
		_check(c.g > 0.8 and c.b > 0.7 and c.r < 0.5, "푸른 민트색 (%s)" % str(c))

	# ── 2. 떼면 1단계 짧은 돌진 + 쿨타임 3초 ──
	var hits0 := main.hit_count
	Input.action_release("rush_skill")
	await _frames(2)
	_check(player.tech.rushing() and not player.tech.whirl(), "떼면 돌진 (최대 회오리 아님)")
	_check(is_equal_approx(player.tech.k, BladeTech.SKILL_K), "기 모으기 1단계 세기 (k=%.2f)" % player.tech.k)
	_check(not is_instance_valid(ind), "돌진하면 인디케이터가 사라진다")
	_check(absf(player.tech.skill_cd - BladeTech.SKILL_CD) < 0.1, "쿨타임 %.0f초 (%.2f)" % [BladeTech.SKILL_CD, player.tech.skill_cd])
	await _secs(0.4)
	var moved := start.distance_to(player.global_position)
	_check(not player.tech.busy(), "돌진이 끝나면 평소 상태로")
	_check(moved > 4.2 and moved < 7.0, "1단계 x1.3 돌진 거리 (%.1fm)" % moved)
	_check(main.hit_count - hits0 == 1, "경로 위 허수아비를 한 번 벤다 (%d타)" % (main.hit_count - hits0))

	# ── 3. 쿨타임 중에는 안 나간다 ──
	start = player.global_position
	Input.action_press("rush_skill")
	await _frames(6)
	_check(not player.tech.skill_aiming(), "쿨타임 중에는 조준이 뜨지 않는다")
	Input.action_release("rush_skill")
	await _frames(4)
	_check(not player.tech.rushing() and start.distance_to(player.global_position) < 0.5, "쿨타임 중에는 돌진하지 않는다")
	await _secs(player.tech.skill_cd + 0.1)
	_check(player.tech.skill_ready(), "쿨타임이 끝나면 다시 준비")

	# ── 4. 처치하면 1.5초 안에 다시 쓸 수 있다 ──
	var d := await _setup(3.0, true)
	var kills0 := player.tech.skill_kills
	Input.action_press("rush_skill")
	await _frames(4)
	Input.action_release("rush_skill")
	await _secs(0.3)
	_check(not d.alive, "돌진 스킬로 허수아비를 처치")
	_check(player.tech.skill_kills == kills0 + 1, "스킬 처치로 집계")
	_check(player.tech.skill_cd <= BladeTech.SKILL_KILL_CD and player.tech.skill_cd > 0.0, "처치하면 남은 쿨타임이 %.1f초 이하로 줄어든다 (%.2f)" % [BladeTech.SKILL_KILL_CD, player.tech.skill_cd])
	await _secs(player.tech.skill_cd + 0.05)
	start = player.global_position
	Input.action_press("rush_skill")
	await _frames(4)
	Input.action_release("rush_skill")
	await _frames(2)
	_check(player.tech.rushing(), "처치 뒤 %.1f초 안에 다시 돌진" % BladeTech.SKILL_KILL_CD)
	await _secs(0.4)

	# ── 5. 처치하지 못하면 쿨타임 그대로 ──
	await _secs(BladeTech.SKILL_CD)
	await _setup(3.0, false)
	Input.action_press("rush_skill")
	await _frames(4)
	Input.action_release("rush_skill")
	await _secs(0.3)
	_check(player.tech.skill_cd > BladeTech.SKILL_KILL_CD + 0.5, "처치하지 못하면 쿨타임이 줄지 않는다 (%.2f)" % player.tech.skill_cd)

	print("RESULT %s (%d fails)" % ["OK" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
