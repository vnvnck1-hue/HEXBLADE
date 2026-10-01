extends SceneTree
## Run with: Godot --headless --path . -s tests/hud_preset_check.gd
## HUD 프리셋 (scripts/presentation/hud_presets.gd) 을 확인한다.
##  1. H 키로 프리셋이 차례로 바뀌고 한 바퀴 돌면 처음으로, Shift+H 는 거꾸로 돈다.
##  2. 기존 세로 나열(LEGACY)은 LEGACY 에서만 보이고, 에너지·미사일 아이콘 줄은 그 줄을 쓰는 프리셋에서만 보인다.
##  3. 프리셋마다 피격 · 재장전 · 충전 · 부스터 과열 · 대시 쿨다운 상태로 몇 프레임씩 그려도 멈추지 않는다.
##  4. 고른 프리셋은 씬을 다시 불러도 유지된다.

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
		await process_frame


func _press_h(shift := false) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_H
	ev.keycode = KEY_H
	ev.shift_pressed = shift
	ev.pressed = true
	root.push_input(ev)
	await _frames(1)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	root.push_input(up)
	await _frames(1)


func _run() -> void:
	HudPresets.current = HudPresets.STRIKER
	var scene: PackedScene = load("res://scenes/main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(30)
	var hud := main.hud
	var p := main.player
	p.invuln = 999.0
	var n := HudPresets.NAMES.size()

	# ── 1. H 순환 ──
	var seen: Array[int] = [HudPresets.current]
	for i in n:
		await _press_h()
		seen.append(HudPresets.current)
	_check(seen == [0, 1, 2, 3, 4, 0], "H 로 STRIKER → CORNERS → COCKPIT → TACTICAL → LEGACY → STRIKER (%s)" % str(seen))
	await _press_h(true)
	_check(HudPresets.current == HudPresets.LEGACY, "Shift+H 는 이전 프리셋 (%s)" % HudPresets.NAMES[HudPresets.current])

	# ── 2·3. 프리셋마다 표시 규칙과 여러 상태 그리기 ──
	for i in n:
		HudPresets.current = i
		hud._apply_preset()
		var legacy := i == HudPresets.LEGACY
		var want_icons := legacy or i in [HudPresets.CORNERS, HudPresets.TACTICAL]
		_check((hud.legacy_left.modulate.a > 0.5) == legacy, "%s: 기존 세로 나열 %s" % [HudPresets.NAMES[i], "보임" if legacy else "숨김"])
		_check(hud.energy_icons.visible == want_icons and hud.missile_icons.visible == want_icons, "%s: 아이콘 줄 %s" % [HudPresets.NAMES[i], "보임" if want_icons else "숨김"])
		p.hp = 1
		p.mag = 3
		p.reload_t = Player.RELOAD_TIME * 0.5
		p.charging = true
		p.charge = 0.7
		p.overheated = true
		p.boost = 0.2
		p.dash_cd = Player.DASH_CD * 0.5
		p.energy = 1
		p.missiles = 0
		p.phantom_t = 0.5
		await _frames(6)
		p.hp = Player.MAX_HP
		p.mag = Player.MAG_SIZE
		p.reload_t = 0.0
		p.charging = false
		p.charge = 0.0
		p.overheated = false
		p.boost = 1.0
		p.dash_cd = 0.0
		p.energy = Player.ENERGY_MAX
		p.missiles = Player.MISSILE_MAX
		p.phantom_t = 0.0
		await _frames(6)
		_check(is_instance_valid(hud.presets), "%s: 극단 상태를 그려도 멈추지 않음" % HudPresets.NAMES[i])
		if i in [HudPresets.CORNERS, HudPresets.TACTICAL]:
			var vs := hud.root.size
			var r1 := Rect2(hud.energy_icons.position, hud.energy_icons.size * hud.energy_icons.scale)
			var r2 := Rect2(hud.missile_icons.position, hud.missile_icons.size * hud.missile_icons.scale)
			var screen := Rect2(Vector2.ZERO, vs)
			_check(screen.encloses(r1) and screen.encloses(r2) and not r1.intersects(r2), "%s: 아이콘 줄이 화면 안 · 서로 겹치지 않음" % HudPresets.NAMES[i])

	# ── 4. 다시 불러도 유지 ──
	HudPresets.current = HudPresets.COCKPIT
	main.queue_free()
	await _frames(2)
	main = scene.instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(10)
	_check(HudPresets.current == HudPresets.COCKPIT and main.hud.energy_icons.visible == false, "씬을 다시 불러도 COCKPIT 유지")

	print("RESULT  %s  (%d fail)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
