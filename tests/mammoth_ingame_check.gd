extends SceneTree
## Run with: Godot --headless --path . -s tests/mammoth_ingame_check.gd
## 본선 MAMMOTH 추격전(boss.tscn)에서 확인한다.
##  1. 기본총 착탄 연출 위치(fx_point)가 차체 안에 묻히지 않고 겉면 밖으로 나온다.
##  2. 보스전 총 연출 배율(ToonGunFX.view_k)이 걸린다.
##  3. 왼쪽에서 충전 레이저를 맞으면 왼쪽이 들리고 오른쪽 모서리는 도로에 붙어 있다. 잠시 뒤 다시 내려앉는다.
##  4. 격파하면 죽음 연출(B안 궤도 파손과 전복) 감독이 시작되고, 연출 카메라로 바뀌며 입력이 잠긴다.
##  5. 연출이 끝나면 보스전 카메라로 돌아오고 바로 WIN 이 된다. 포탑이 뜯겨 나가고 잔해는 멀어진다.

const BossEnemy := preload("res://scripts/boss_enemy.gd")

var fails := 0
var main: Main


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		main.player.invuln = 999.0
		await physics_frame


func _run() -> void:
	main = load("res://scenes/boss.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(2)
	_check(is_equal_approx(ToonGunFX.inst.view_k, main.VIEW_K) and main.VIEW_K > 1.0, "보스전 총 연출 배율 view_k = %.2f" % ToonGunFX.inst.view_k)
	# 보스 등장 대기
	var boss: BossEnemy = null
	for i in 900:
		await _frames(1)
		boss = main.get("boss")
		if boss and boss.st == BossEnemy.St.FIGHT:
			break
	_check(boss != null and boss.st == BossEnemy.St.FIGHT, "보스 등장 · 전투 시작")
	if boss == null:
		quit(1)
		return
	boss.rest = 99.0          # 검증 중에는 패턴을 쏘지 않게
	for b in get_nodes_in_group("enemy_bullets"):
		b.queue_free()

	# 1. 착탄 위치: 판정 원기둥(반지름 3.3) 위 낮은 점 → 차체 겉면 밖으로
	var bp := boss.global_position
	var hit := bp + Vector3(0.5, 1.0, 3.35)
	var fxp := boss.fx_point(hit, Vector3(0, 0, -1))
	var lp := boss.to_local(fxp)
	_check(lp.z > 3.75 and fxp.y >= 1.2, "기본총 착탄 연출이 차체 앞면 밖으로 나온다 (로컬 z %.2f, 높이 %.2f)" % [lp.z, fxp.y])
	var side_fx := boss.to_local(boss.fx_point(bp + Vector3(-3.3, 1.0, 0.5), Vector3(1, 0, 0)))
	_check(side_fx.x < -3.55, "옆에서 맞아도 옆면 밖으로 (로컬 x %.2f)" % side_fx.x)

	# 3. 왼쪽(-X)에서 충전 레이저
	var pl := main.player
	pl.global_position = bp + Vector3(-7.0, 0, 6.0)
	var dir := (bp - pl.global_position)
	dir.y = 0
	dir = dir.normalized()
	boss.take_hit(10, dir, bp, "laser")
	var best_l := 0.0
	var right_y := 0.0
	for i in 20:
		await _frames(1)
		var ly := boss.visual.to_global(Vector3(-3.3, 0, 0)).y - boss.global_position.y
		if ly > best_l:
			best_l = ly
			right_y = boss.visual.to_global(Vector3(3.3, 0, 0)).y - boss.global_position.y
	_check(best_l > 0.6, "왼쪽에서 맞으면 왼쪽 모서리가 들린다 (최대 %.2fm)" % best_l)
	_check(right_y < 0.25, "들리는 동안 반대쪽(오른쪽) 모서리는 도로에 남는다 (%.2fm)" % right_y)
	await _frames(150)
	_check(boss.lift.lifted() < 0.03, "잠시 뒤 다시 내려앉는다 (기울기 %.3f rad)" % boss.lift.lifted())
	# 오른쪽(+X)에서 맞으면 반대로
	pl.global_position = bp + Vector3(7.0, 0, 6.0)
	dir = (bp - pl.global_position)
	dir.y = 0
	boss.take_hit(10, dir.normalized(), bp, "laser")
	var best_r := 0.0
	for i in 20:
		await _frames(1)
		best_r = maxf(best_r, boss.visual.to_global(Vector3(3.3, 0, 0)).y - boss.global_position.y)
	_check(best_r > 0.6, "오른쪽에서 맞으면 오른쪽이 들린다 (최대 %.2fm)" % best_r)
	await _frames(150)

	# 4. 격파 → 죽음 연출
	pl.global_position = bp + Vector3(0, 0, 8.0)
	boss.phase = 2
	boss.boss_hp = 1.0
	boss.take_hit(5, Vector3(0, 0, -1), bp + Vector3(0, 1, 3.4), "bullet")
	_check(boss.death_started() and boss.st == BossEnemy.St.DEAD and not boss.alive, "격파 순간 죽음 연출 감독 시작")
	await _frames(3)
	var cam := root.get_viewport().get_camera_3d()
	_check(cam != main.camera, "연출 카메라로 전환")
	_check(pl.bot, "연출 중 플레이어 입력 잠금 (자동 비행)")
	_check(main.state == Main.State.PLAY, "연출이 끝나기 전에는 WIN 이 아니다")
	var t0 := Time.get_ticks_msec()
	var torn := false
	while main.state != Main.State.WIN and Time.get_ticks_msec() - t0 < 12000:
		await process_frame
		pl.invuln = 999.0
		if boss.death_fx._turret_gone:
			torn = true
	var took := (Time.get_ticks_msec() - t0) / 1000.0
	_check(main.state == Main.State.WIN, "연출이 끝나면 WIN (%.2f초)" % took)
	_check(took > 4.8 and took < 7.0, "연출 길이 5.7초 안팎 (%.2f초)" % took)
	_check(torn, "전복 중 포탑이 뜯겨 나간다")
	_check(root.get_viewport().get_camera_3d() == main.camera and main.hud.visible, "보스전 카메라 · HUD 복귀")
	_check(is_equal_approx(Engine.time_scale, 1.0), "시간 배율 원래대로 (%.2f)" % Engine.time_scale)
	# 잔해가 도로와 함께 멀어진다
	t0 = Time.get_ticks_msec()
	while boss.visual.visible and Time.get_ticks_msec() - t0 < 6000:
		await process_frame
	_check(not boss.visual.visible, "잔해가 화면 밖으로 멀어진다")

	print("RESULT mammoth_ingame_check fails=%d" % fails)
	quit(1 if fails > 0 else 0)
