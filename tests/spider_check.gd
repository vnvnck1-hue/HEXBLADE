extends SceneTree
## Run with: Godot --headless --path . -s tests/spider_check.gd
## 거미 보스 SHAFT 07 · SHIPWRIGHT 확인:
##  1. 전장: push_out 은 바닥 안 · 기둥 밖으로, project 는 바닥 / 벽 / 기둥 면을 고른다, 바닥 경로는 기둥을 비켜 간다
##  2. 구멍 속 → 바닥 경로가 바닥에서 끝나고, 같은 벽끼리는 벽면으로만 간다
##  3. 장면: 등장 연출 뒤 전투 시작 · 걸으면 발이 면에 붙어 있다 · 거미줄 직격/판이 플레이어를 느리게 한다 · 새끼 거미가 나온다
##  4. 체력 50% 에서 2페이즈, 0 이면 격파 연출 뒤 WIN

const Stage := preload("res://scripts/spider/spider_stage.gd")
const Boss := preload("res://scripts/spider/spider_boss.gd")

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


func _run() -> void:
	var scene: PackedScene = load("res://scenes/spider.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(5)
	var stage: Stage = main.stage
	var player: Player = main.player
	# ── 1. 전장 ──
	var ok_push := true
	for i in 200:
		var p := Vector3(randf_range(-40, 40), 0, randf_range(-35, 35))
		var q := stage.push_out(p, 0.4)
		if stage.is_blocked(q):
			ok_push = false
	_check(ok_push, "push_out: 어떤 점이든 막히지 않은 바닥으로 돌아온다")
	var pf: Dictionary = stage.project(Vector3(0, 0.6, 5))
	var pw: Dictionary = stage.project(Vector3(-2, 6, -Stage.HZ + 0.8))
	var c0 := Stage.pillar_pos(0)
	var pp: Dictionary = stage.project(c0 + Vector3(Stage.pillar_r(0) + 0.5, 8, 0))
	_check((pf.n as Vector3).is_equal_approx(Vector3.UP) and (pw.n as Vector3).is_equal_approx(Vector3(0, 0, 1)) and (pp.n as Vector3).dot(Vector3.RIGHT) > 0.99, "project: 바닥 · 북쪽 벽 · 기둥 옆면 법선")
	var path: Array = stage.floor_path(Vector3(-24, Stage.RIDE, -10), Vector3(0, Stage.RIDE, -10))
	var clear := true
	var prev := Vector3(-24, Stage.RIDE, -10)
	for q in path:
		for k in 20:
			var s: Vector3 = prev.lerp(q, k / 19.0)
			var d := Vector2(s.x - c0.x, s.z - c0.z).length()
			if d < Stage.pillar_r(0) + Stage.PILLAR_CLEAR - 0.6:
				clear = false
		prev = q
	_check(clear and path.size() >= 2, "바닥 경로가 기둥을 비켜 간다 (점 %d개)" % path.size())
	# ── 2. 구멍 경로 ──
	var r1: Array = stage.route(Stage.hole_loc(4), Stage.floor_loc(Vector3(0, 0, 0)))
	var last: Dictionary = r1[r1.size() - 1]
	_check((last.n as Vector3).is_equal_approx(Vector3.UP) and absf((last.c as Vector3).y - Stage.RIDE) < 0.01, "배관 구멍 → 바닥 경로가 바닥에서 끝난다")
	var r2: Array = stage.route(Stage.wall_loc("N", -10, 6), Stage.wall_loc("N", 10, 8))
	var on_wall := true
	for q in r2:
		if not (q.n as Vector3).is_equal_approx(Vector3(0, 0, 1)):
			on_wall = false
	_check(on_wall, "같은 벽끼리는 벽면을 타고 간다")

	# ── 3. 장면 ──
	var boss: Boss = main.boss
	var t := 0
	while boss.st == Boss.St.ENTER and t < 1200:
		player.invuln = 99.0
		await physics_frame
		t += 1
	_check(boss.st == Boss.St.FIGHT, "등장 연출 뒤 전투 시작 (%.1f초)" % (t / 60.0))
	# 걸을 때 발이 면에 붙어 있는가 (딛는 중이 아닌 발)
	var worst := 0.0
	for k in 240:
		player.invuln = 99.0
		await physics_frame
		for l in boss.rig.legs:
			if float(l.t) < 0.0 and float(l.gw) <= 0.0:
				worst = maxf(worst, float((stage.project(l.foot) as Dictionary).d))
	_check(worst < 0.3, "디딘 발이 바닥 · 벽 · 기둥 면에 붙어 있다 (최대 %.2fm)" % worst)
	main.web_player(1.0)
	await _frames(3)
	_check(player.slow_mul < 0.5, "거미줄 직격: 느려진다 (배율 %.2f)" % player.slow_mul)
	main.web_t = 0.0
	stage.add_web(player.global_position, 2.5)
	await _frames(3)
	_check(player.slow_mul < 0.85 and player.slow_mul > 0.3, "거미줄 판 위: 느려진다 (배율 %.2f)" % player.slow_mul)
	stage.clear_webs()
	var before: int = main.enemies_left()
	boss._throw_brood()
	boss._throw_brood()
	await _frames(70)
	_check(main.enemies_left() >= before + 2, "새끼 거미가 날아와 착지한다 (%d → %d)" % [before, main.enemies_left()])
	for e in main.get_tree().get_nodes_in_group("enemies"):
		if not (e as Enemy).is_boss and (e as Enemy).landed:
			(e as Enemy).take_hit(99, Vector3.FORWARD, (e as Node3D).global_position)

	# ── 4. 페이즈 · 격파 ──
	var hit := func() -> void:
		player.invuln = 99.0
		if boss.st == Boss.St.FIGHT and not boss.hidden:
			boss.take_hit(20, Vector3.FORWARD, boss.global_position)
	t = 0
	while boss.phase == 1 and t < 6000:
		hit.call()
		await physics_frame
		t += 1
	_check(boss.phase == 2, "체력 50%%: 2페이즈 (%.1f초)" % (t / 60.0))
	t = 0
	while main.state != Main.State.WIN and t < 9000:
		hit.call()
		await physics_frame
		t += 1
	_check(main.state == Main.State.WIN and boss.st == Boss.St.DEAD, "격파 연출 뒤 WIN (%.1f초)" % (t / 60.0))
	print("SPIDER_CHECK %s" % ("OK" if fails == 0 else "FAILED %d" % fails))
	quit(1 if fails > 0 else 0)
