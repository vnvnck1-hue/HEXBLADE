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
	var dock: RoundSkillDock
	for child in hud.presets.get_children():
		if child is RoundSkillDock:
			dock = child
	_check(dock != null and dock.icons.size() == 6, "원형 장비 HUD 아이콘 6종 로드")
	for name_ in ["sword", "gun", "dash", "boost", "energy", "missile"]:
		var image := Image.load_from_file(ProjectSettings.globalize_path(RoundSkillDock.ICON_DIR + name_ + ".png"))
		_check(image != null and image.detect_alpha() != Image.ALPHA_NONE and image.get_pixel(0, 0).a == 0.0, "%s: 투명 장비 그림" % name_)
	# 실제 화면 크기별 장비/키 배지와 드론 패널 공간 확보.
	for view in [Vector2(1280, 720), Vector2(1280, 800), Vector2(1920, 1080), Vector2(1920, 800)]:
		var rect := RoundSkillDock.dock_rect(view)
		var support := DroneHud.panel_rect(view)
		var screen := Rect2(Vector2.ZERO, view)
		_check(screen.encloses(rect) and screen.encloses(support) and not support.intersects(rect), "%s: 장비/드론 패널 화면 안 · 서로 비겹침" % view)
	p.missiles = 0
	p.ult_queue = 4
	_check(RoundSkillDock.missile_count(p) == 4, "발사 예약 미사일은 실제 발사될 때까지 수량 유지")
	p.ult_queue = 0
	p.missiles = Player.MISSILE_START
	# 실제 레이아웃과 기존 HUD 복귀를 검증한다.
	var calm := hud.presets.calm
	_check(calm != null and calm.portrait != null and calm.portrait.get_width() <= 512, "차분한 HUD 초상 로드 · 임포트 최대 512px")
	var portrait_image := Image.load_from_file(ProjectSettings.globalize_path("res://assets/ui/calm_hud/mecha_bust.png"))
	_check(portrait_image.detect_alpha() != Image.ALPHA_NONE, "메카 초상 투명 알파 유지")
	var drone_panel := PartnerDrone.inst.hud_panel
	_check(drone_panel.portrait != null and drone_panel.portrait.get_width() <= 512, "TRIAD 카드 초상 로드 · 임포트 최대 512px")
	var drone_image := Image.load_from_file(ProjectSettings.globalize_path(DroneHud.PORTRAIT))
	_check(drone_image.detect_alpha() != Image.ALPHA_NONE and drone_image.get_pixel(0, 0).a == 0, "TRIAD 초상 투명 알파")
	var original_size := root.size
	for window_size in [Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(1920, 1080), Vector2i(1920, 800)]:
		root.size = window_size
		await _frames(3)
		var screen := Rect2(Vector2.ZERO, hud.root.size)
		var hero := calm.hero_rect()
		var status := calm.status_rect()
		var map_frame := calm.minimap_rect()
		_check(screen.encloses(hero) and screen.encloses(status) and screen.encloses(map_frame) and not hero.intersects(status) and not status.intersects(map_frame), "%s: 실제 창에서 상단 카드 화면 안 · 비겹침" % window_size)
		var support := drone_panel.get_global_rect()
		var skills := RoundSkillDock.dock_rect(hud.root.size)
		_check(screen.encloses(support) and support.position.x < hud.root.size.x * 0.1 and not support.intersects(skills) and not support.intersects(hero), "%s: 실제 TRIAD 카드 좌하단 · 스킬/상단 비겹침" % window_size)
	root.size = original_size
	await _frames(3)
	var foe := Enemy.new()
	main.world.add_child(foe)
	foe.global_position = p.global_position + Vector3(3, 0, -3)
	foe._init_hp()
	foe.landed = true
	foe.hp = maxi(1, int(foe.max_hp * 0.5))
	foe._update_hp_bar(0.01)
	_check(not foe.hp_bar.visible and calm.enemy_rect(foe).size.x > 0, "화면 공간 적 HP바 · 기존 3D바 중복 숨김")
	HudPresets.current = HudPresets.CORNERS
	hud._apply_preset()
	foe._update_hp_bar(0.01)
	await _frames(2)
	_check(foe.hp_bar.visible and hud.minimap.visible and hud.count_label.visible and not calm.visible, "다른 프리셋에서 기존 미니맵 · 수치 · 적 HP바 복귀")
	_check(drone_panel.get_global_rect().size == Vector2(DroneHud.W, DroneHud.H), "다른 프리셋에서 기존 드론 패널 크기 복귀")
	HudPresets.current = HudPresets.STRIKER
	hud._apply_preset()
	await _frames(2)
	_check(calm.visible and not hud.minimap.visible and not hud.count_label.visible and not hud.wave_label.visible and not hud.combo_box.visible, "새 상단 HUD에서 중복 수치 숨김")
	foe.queue_free()
	await _frames(2)

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
		_check(dock.visible == (i == HudPresets.STRIKER), "%s: 장비 원형 버튼은 STRIKER에서 표시" % HudPresets.NAMES[i])
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
