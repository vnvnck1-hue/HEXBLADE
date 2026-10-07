extends SceneTree
## Run with: Godot --headless --path . -s tests/parry_timing_check.gd
## 패링 타이밍 규칙 (2026-10-07): 별빛 뒤 정해진 시간에 닿는 규칙은 없다. 모든 패링은 실제로 플레이어에게 닿기 직전에만 판정 창이 열린다.
##  1. 패링 히트스톱 기본 프리셋 = HEAVY, 허수아비 홀에서도 P / Shift+P 로 바꾸고 패널에 보인다.
##  2. 허수아비 근접 반격(4 키): 준비동작 · 별빛 동안은 패링이 안 되고, 후려치기가 닿기 직전에만 열린다. 패링하면 허수아비가 휘청, 못 하면 맞는다.
##  3. 패링 탄(원거리): 속도는 일정하고, 판정 창이 열릴 때 탄은 실제로 Parry.EARLY 초 안에 닿을 거리에 있다.
##  4. 요격기(Striker) 돌진 베기: 멀리서 별빛이 떠도 파고드는 동안은 안 되고, 바로 앞에서 벨 때만 열린다.

var fails := 0
var main: TrainingMain
var p: Player


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _panel_text() -> String:
	var s := ""
	for l in main.panel.find_children("*", "Label", true, false):
		s += (l as Label).text + "\n"
	return s


func _key(k: int, shift := false) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.keycode = k
	ev.pressed = true
	ev.shift_pressed = shift
	main._unhandled_input(ev)


func _clear() -> void:
	for d in main.dummies:
		if is_instance_valid(d):
			d.queue_free()
	main.dummies.clear()


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _run() -> void:
	main = (load("res://scenes/training.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(30)
	p = main.player
	main.god = true

	# 1. 히트스톱 프리셋
	_check(Parry.stop_preset().id == "heavy", "패링 히트스톱 기본 = HEAVY 묵직하게 길게")
	_check(_panel_text().contains("패링 히트스톱") and _panel_text().contains("HEAVY"), "허수아비 홀 패널에 패링 히트스톱 줄")
	_key(KEY_P)
	_check(Parry.stop_preset().id == "soft", "홀에서 P = 다음 프리셋 (%s)" % Parry.stop_preset().id)
	_key(KEY_P, true)
	_check(Parry.stop_preset().id == "heavy", "홀에서 Shift+P = 이전 프리셋")

	# 2. 허수아비 근접 반격
	_clear()
	_key(KEY_4)
	_key(KEY_4)
	_check(main.counter_melee and not main.counter, "4 키 두 번 = 근접 반격 (%s)" % main._counter_title())
	_check(_panel_text().contains("근접"), "패널에 반격 모드 표시")
	var at := main.center + Vector3(0, 0, -1.0)
	var d := main._spawn_dummy(at)
	await _frames(70)
	p.global_position = at + Vector3(0, 0, 2.2)
	p.velocity = Vector3.ZERO
	var early_open := false
	var wind_seen := false
	var opened := false
	for i in 240:
		if d.m_state == "wind":
			wind_seen = true
			if Parry.inst.best_threat() == d:
				early_open = true
		if Parry.inst.best_threat() == d:
			opened = true
			break
		await physics_frame
	_check(wind_seen and not early_open, "준비동작 동안은 패링 판정 없음")
	_check(opened and d.parry_eta() <= Parry.EARLY + 0.001, "후려치기가 닿기 직전에만 판정 창 (남은 %.2f초)" % d.parry_eta())
	if opened:
		_check(Parry.inst.try_parry(p), "그때 대시 = 패링 성공")
		await _frames(3)
		_check(d.stagger_t > 0.0, "패링당한 허수아비가 휘청")
	# 패링 안 하면 맞는다
	await _frames(240)
	main.god = false
	p.invuln = 0.0
	p.hp = Player.MAX_HP
	p.global_position = at + Vector3(0, 0, 2.2)
	var hit := false
	for i in 300:
		if p.hp < Player.MAX_HP:
			hit = true
			break
		await physics_frame
	_check(hit, "패링하지 않으면 후려치기에 맞는다")
	main.god = true
	p.hp = Player.MAX_HP

	# 3. 패링 탄
	_clear()
	_key(KEY_4)       # 원거리 + 근접
	_key(KEY_4)       # 끔
	_key(KEY_4)       # 원거리
	_check(main.counter and not main.counter_melee, "4 키 = 원거리 반격")
	var d2 := main._spawn_dummy(main.center + Vector3(0, 0, -6.0))
	d2.fire_timer = 0.9
	p.global_position = main.center + Vector3(0, 0, 4.0)
	await _frames(60)
	var orb: ParryOrb = null
	for i in 400:
		var orbs := get_nodes_in_group("parry_orbs")
		if not orbs.is_empty():
			orb = orbs[0]
			break
		await physics_frame
	_check(orb != null and is_equal_approx(orb.speed, ParryOrb.SPEED), "패링 탄 속도는 일정 (%.1fm/s)" % (orb.speed if orb else 0.0))
	var orb_open := false
	var od := 0.0
	for i in 200:
		if not is_instance_valid(orb):
			break
		if Parry.inst.best_threat() == orb:
			orb_open = true
			od = _flat(orb.position, p.global_position) - p.hit_radius - ParryOrb.RADIUS
			break
		await physics_frame
	_check(orb_open and od / ParryOrb.SPEED <= Parry.EARLY + 0.02, "탄 판정 창은 실제로 닿기 직전 (%.2fm 남음 · %.2f초)" % [od, od / ParryOrb.SPEED])
	_clear()

	# 4. 요격기 돌진 베기
	main.counter = false
	var s := Striker.new()
	s.lunge_only = true
	main.world.add_child(s)
	s.global_position = main.center + Vector3(0, 0, -5.0)
	p.global_position = main.center + Vector3(0, 0, 2.0)
	var s_far := false
	var s_open := false
	var s_d := 0.0
	for i in 900:
		if s.state == Striker.S.LUNGE and not s.lunge_slash and Parry.inst.best_threat() == s:
			s_far = true
		if Parry.inst.best_threat() == s:
			s_open = true
			s_d = _flat(s.global_position, p.global_position)
			break
		await physics_frame
	_check(s_open, "요격기 돌진 베기에 판정 창이 열린다")
	_check(not s_far and s.lunge_slash, "파고드는 동안은 안 되고 바로 앞에서 벨 때만")
	_check(s_d <= Striker.LUNGE_REACH + p.hit_radius + Striker.SLASH_GAP + 0.3, "판정 창이 열릴 때 요격기가 바로 앞 (%.2fm)" % s_d)
	_check(s.parry_eta() <= Parry.EARLY + 0.001, "요격기 베기도 닿기 직전 (남은 %.2f초)" % s.parry_eta())

	print("RESULT %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(0 if fails == 0 else 1)
