class_name TrainingMain
extends Main
## 전투 테스트장 (Main 상속). 엄폐물 없는 넓은 홀에 허수아비를 세워 두고 모든 무기·콤보·연출을 자유롭게 시험한다.
## 전투방·차단막·승패가 없고, 맞힌 피해는 허수아비 위 숫자와 오른쪽 위 DPS 표시로 보인다.
##
## 숫자 키로 바꾼다 (왼쪽 위 설정 패널 TrainingPanel 에 현재 상태가 보인다):
##  1 허수아비 다시 세우기 + 기록 초기화   2 배치: 1기 / 3기 / 무리 6기 / 멀리 1기
##  3 무적 ↔ 처치 가능(쓰러지면 2초 뒤 다시 선다)   4 반격(패링 탄)   5 좌우 이동
##  6 재화 무한(에너지·미사일·부스터·드론 합체 게이지 = Q 합체 휠윈드 무제한, 탄창은 그대로라 재장전도 볼 수 있다)   7 플레이어 무적
##  0 합체 컷인 · [ 컷인 캐릭터 · - 컷인 트위닝 · F3 컷인 미리보기 · J 피해 숫자 프리셋 · H HUD 프리셋 (Main)
##  = / Shift+= 바닥 파괴 스타일 (CRUMBLE 깨짐 튐 기본 · SLAB 판 들림 · SPIKE 암석 솟음 · BUCKLE 찌그러짐 · SCATTER 파편 튐 · MIX 대파괴 · OFF)   F4 / Shift+F4 조준점에 바닥 파괴 크게 / 작게
##  F1 왼쪽 설명(설정 패널·하단 조작 안내) 잠시 숨기기 ↔ 보이기   F2 모든 UI 숨기기 ↔ 보이기 (HUD·드론 패널·피해 숫자·말풍선·적 체력바)
## 왼쪽 통로 끝에는 보스 체험방(TrainingBossRoom)이 있다: 들어가면 LANCASTER 가 기동하고 패널 · 숫자 키가 보스 프리셋으로 바뀐다.
## 확인용 실행 인자: --layout=0~3 --killable --counter --moving (봇: --bot) · --bossroom (보스방 입구에서 시작) · --bossroom=off

const ROOM_SIZE := Vector2i(30, 22)
const RESPAWN := 2.0
const DPS_WINDOW := 3.0
const CHAIN_GAP := 1.2          # 이 시간 넘게 안 맞으면 연속 피해 묶음이 끝난다
const LAYOUTS := ["1기", "3기", "무리 6기", "멀리 1기"]
const SRC_COLORS := {
	"slash": Color("ff7ad0"), "phantom": Color("ff6a4a"), "bullet": Color("ffe070"), "laser": Color("7cf5ff"),
	"missile": Color("ffa040"), "parry": Color("ffd166"),
}

var center := Vector3.ZERO
var dummies: Array[TrainingDummy] = []
var layout := 1
var immortal := true
var counter := false
var moving := false
var infinite := true
var god := true
var hits: Array = []            # [게임 시간, 피해]
var total := 0
var hit_count := 0
var last_hit := 0
var chain_dmg := 0
var best_chain := 0
var last_hit_t := -99.0
var panel: TrainingPanel
var panel_rows := true          # false 면 패널에 설정 행 없이 _panel_text() 글자만 (자체 설명을 쓰는 상속 씬)
var _respawns: Array = []       # [남은 시간, 자리]
var _bot_t := 0.0
var show_help := true           # F1: 왼쪽 설명
var _numbers: CanvasLayer       # MocoFX 의 피해 숫자 층 (F2 로 같이 숨김)
var boss_room: TrainingBossRoom # 왼쪽 보스 체험방 (이 씬 자체일 때만. 상속 씬은 없음)
var _boss_room_id := -1


func _ready() -> void:
	process_priority = 100     # HUD 뒤에 돌아 오른쪽 위 문구를 덮어쓴다
	super._ready()
	center = map.room_center_world(map.start_room)
	player.global_position = center + Vector3(0, 0, 4.5)
	camera.snap(player.global_position)
	panel = TrainingPanel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 16
	panel.offset_top = 152          # 왼쪽 위 상태 HUD 아래
	hud.root.add_child(panel)
	_build_panel()
	# 시작 설정 (확인용 실행 인자): --layout=0~3 --killable --counter --moving
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--layout="):
			layout = clampi(int(a.substr(9)), 0, LAYOUTS.size() - 1)
		elif a == "--killable":
			immortal = false
		elif a == "--counter":
			counter = true
		elif a == "--moving":
			moving = true
	_place()
	if _boss_room_id >= 0:
		boss_room = TrainingBossRoom.new()
		boss_room.name = "BossRoom"
		boss_room.main = self
		add_child(boss_room)
		boss_room.setup(_boss_room_id)
	FX.victory(player.global_position)
	hud.banner("TRAINING", Color(0.7, 0.95, 1.0), "허수아비를 마음껏 때려 보세요 · 숫자 키로 설정 · Esc 로비")


## 엄폐물 없는 평평한 넓은 홀 하나
func _build_arena() -> void:
	map = ArenaMap.new()
	world.add_child(map)
	map.terrain = false
	map.generate_single(map_seed if map_seed >= 0 else 7, ArenaMap.Shape.RECT, false, ROOM_SIZE)
	if _wants_boss_room():
		_boss_room_id = TrainingBossRoom.carve(map)
	map.build()


## 보스 체험방은 허수아비 씬 자체에만 (드론 · 유체 · 배경 시험장 같은 상속 씬은 그대로)
func _wants_boss_room() -> bool:
	if Main.cmd_args.has("--bossroom=off"):
		return false
	var sc := get_script() as Script
	return sc != null and sc.resource_path == "res://scripts/training/training_main.gd"


## 감염 오염물은 허수아비 홀에만 (보스방은 비워 둔다)
func infest_layout(inf: Node) -> void:
	if _boss_room_id < 0:
		inf.call("_reserve")
		for r in map.rooms:
			inf.call("_populate", r.id)
		return
	inf.call("_reserve")
	inf.call("_populate", map.start_room)


func combat_rooms() -> int:
	return 0


# ── 허수아비 배치 ───────────────────────────────────────

func _spots() -> Array[Vector3]:
	var out: Array[Vector3] = []
	match layout:
		0:
			out.append(center + Vector3(0, 0, -0.5))
		1:
			out.append_array([center + Vector3(-4.0, 0, -1.0), center + Vector3(0, 0, -2.0), center + Vector3(4.0, 0, -1.0)])
		2:
			for i in 6:
				var a := TAU * i / 6.0
				out.append(center + Vector3(0, 0, -1.5) + Vector3(cos(a), 0, sin(a)) * 3.2)
		3:
			out.append(center + Vector3(0, 0, -7.5))
	return out


func _place() -> void:
	for d in dummies:
		if is_instance_valid(d):
			d.queue_free()
	dummies.clear()
	_respawns.clear()
	for p in _spots():
		_spawn_dummy(p)
	_reset_stats()


func _spawn_dummy(p: Vector3) -> TrainingDummy:
	var d := TrainingDummy.new()
	d.anchor = map.push_out(p, 1.0)
	d.immortal = immortal
	d.attack = counter
	d.mover = moving
	world.add_child(d)
	d.global_position = d.anchor
	d.rotation.y = atan2(-(player.global_position.x - p.x), -(player.global_position.z - p.z))
	dummies.append(d)
	return d


func _apply_flags() -> void:
	for d in dummies:
		if is_instance_valid(d) and d.alive:
			d.immortal = immortal
			d.attack = counter
			d.mover = moving
			if not counter:
				d.orb_next = false


func _reset_stats() -> void:
	hits.clear()
	total = 0
	hit_count = 0
	last_hit = 0
	chain_dmg = 0
	best_chain = 0
	last_hit_t = -99.0


# ── 피해 기록 ───────────────────────────────────────────

## TrainingDummy.take_hit 이 부른다: 숫자를 띄우고 DPS·연속 피해를 센다
func record_hit(d: Node3D, dmg: int, source: String) -> void:
	if time - last_hit_t > CHAIN_GAP:
		chain_dmg = 0
	last_hit_t = time
	hits.append([time, dmg])
	total += dmg
	hit_count += 1
	last_hit = dmg
	chain_dmg += dmg
	best_chain = maxi(best_chain, chain_dmg)
	# mo.co 무드 연출이면 일반 전투와 같은 피해 숫자(MocoFX, Enemy.take_hit 에서 한 번)를 쓴다 — 두 번 뜨지 않게
	if not MocoFX.on and not ui_hidden:
		_damage_number(d, dmg, source)


## 맞은 자리 위로 튀어 오르며 사라지는 피해 숫자 (큰 피해일수록 크다)
func _damage_number(d: Node3D, dmg: int, source: String) -> void:
	var l := Label3D.new()
	l.text = str(dmg)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.font_size = int(clampf(34.0 + dmg * 2.2, 34.0, 80.0))
	l.outline_size = 10
	l.modulate = SRC_COLORS.get(source, Color.WHITE)
	l.outline_modulate = Color(0.05, 0.03, 0.12)
	l.render_priority = 20
	l.outline_render_priority = 19
	world.add_child(l)
	var base := d.global_position + Vector3(randf_range(-0.45, 0.45), 1.5 + randf_range(0.0, 0.35), randf_range(-0.2, 0.2))
	l.global_position = base
	l.scale = Vector3.ONE * 1.7
	var tw := l.create_tween().set_ignore_time_scale(true)
	tw.tween_property(l, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "global_position", base + Vector3(0, 0.7, 0), 0.6).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.2)
	tw.parallel().tween_property(l, "outline_modulate:a", 0.0, 0.2)
	tw.tween_callback(l.queue_free)


func dps() -> float:
	var sum := 0
	var first := time
	for h in hits:
		if time - float(h[0]) <= DPS_WINDOW:
			sum += int(h[1])
			first = minf(first, float(h[0]))
	if sum == 0:
		return 0.0
	return sum / maxf(time - first, 0.5)


# ── 진행 ────────────────────────────────────────────────

func _physics_process(dt: float) -> void:
	super._physics_process(dt)
	while not hits.is_empty() and time - float(hits[0][0]) > DPS_WINDOW:
		hits.pop_front()
	if infinite and player.alive:
		player.energy = Player.ENERGY_MAX
		player.missiles = Player.MISSILE_MAX
		player.boost = 1.0
		player.overheated = false
		# 드론 합체(Q 휠윈드)도 무제한 (드론 시험장은 게이지가 차는 과정을 봐야 해서 제외)
		if PartnerDrone.inst and not has_method("drone_lab"):
			PartnerDrone.inst.gauge = PartnerDrone.GAUGE_MAX
	if god and player.alive:
		player.invuln = maxf(player.invuln, 0.2)
		player.hp = Player.MAX_HP
	# 쓰러진 허수아비는 잠시 뒤 다시 선다
	for i in range(dummies.size() - 1, -1, -1):
		var d := dummies[i]
		if not is_instance_valid(d) or not d.alive:
			_respawns.append([RESPAWN, d.anchor if is_instance_valid(d) else center])
			dummies.remove_at(i)
	for r in _respawns:
		r[0] = float(r[0]) - dt
	while not _respawns.is_empty() and float(_respawns[0][0]) <= 0.0:
		_spawn_dummy(_respawns.pop_front()[1])


func on_player_died() -> void:
	super.on_player_died()
	hud.message("DESTROYED", "F5 로 다시 시작 · 7 키로 플레이어 무적", Color("ff4a8a"))


func _process(dt: float) -> void:
	super._process(dt)
	hud.wave_label.text = "TRAINING"
	hud.count_label.text = "DPS %d  ·  최근 %d  ·  연속 %d (최고 %d)  ·  합계 %d / %d타" % [roundi(dps()), last_hit, chain_dmg if time - last_hit_t <= CHAIN_GAP else 0, best_chain, total, hit_count]
	if panel:
		panel.refresh(_panel_text())
		panel.visible = show_help
	hud.hint.visible = show_help
	_apply_ui()


## F2: 모든 UI 숨김. HUD 층(상태·지도·스킬·드론 패널·팝업·배너) · 피해 숫자 층 · 드론 말풍선 (적 체력바는 Enemy 가 Main.ui_hidden 을 본다)
func _apply_ui() -> void:
	hud.visible = not ui_hidden
	if not is_instance_valid(_numbers) and is_instance_valid(ToonGunFX.inst):
		_numbers = ToonGunFX.inst.get_node_or_null("MocoFX/MocoNumbers") as CanvasLayer
	if is_instance_valid(_numbers):
		_numbers.visible = not ui_hidden
	# 말풍선(SpeechBubble)은 HUD 층 아래라 hud.visible 을 따른다


func _onoff(v: bool) -> String:
	return "ON" if v else "OFF"


## 보스방 출입 때 패널을 그 자리에 맞게 다시 채운다
func rebuild_panel() -> void:
	if panel == null:
		return
	panel.clear()
	_build_panel()


## 설정 패널: 묶음별 [키] 이름 ··· 값 (값은 매 프레임 갱신)
func _build_panel() -> void:
	if boss_room and boss_room.inside:
		boss_room.build_panel(panel)
		return
	panel.title("TRAINING")
	if panel_rows:
		panel.section("허수아비")
		panel.row("1", "다시 세우기", func(): return "기록 초기화")
		panel.row("2", "배치", func(): return LAYOUTS[layout])
		panel.row("3", "허수아비", func(): return "무적" if immortal else "처치 가능")
		panel.row("4", "반격 (패링 탄)", func(): return _onoff(counter))
		panel.row("5", "좌우 이동", func(): return _onoff(moving))
		panel.section("플레이어")
		panel.row("6", "재화 무한", func(): return _onoff(infinite))
		panel.row("7", "무적", func(): return _onoff(god))
		panel.section("연출 프리셋")
		panel.row("8", "타격 VFX", func(): return MocoFX.STYLE_NAMES[MocoFX.style] + ("  ×0.2" if MocoFX.slow < 1.0 else ""))
		panel.row("J", "피해 숫자", func(): return DamageLog.preset.to_upper())
		panel.row("H", "HUD", func(): return HudPresets.NAMES[HudPresets.current])
		panel.row("=", "바닥 파괴", func(): return String(GroundBreak.current().name))
		panel.row("0", "합체 컷인", _cutin_title)
		panel.row("[", "컷인 캐릭터", func(): return DiagonalDockingCutin.character_title(DiagonalDockingCutin.char_mode))
		panel.row("-", "컷인 트위닝", func(): return String(DiagonalDockingCutin.tween().name))
	panel.footer("F3 컷인 · F4 바닥 파괴 미리보기\nF1 패널 숨기기 · F2 모든 UI 숨기기")


## 상속 씬이 패널 아래에 덧붙이는 글자 (기본 없음)
func _panel_text() -> String:
	return ""


## 8 = 타격 VFX 프리셋 전환 · Shift+8 = 버스트만 0.2 배속으로 느리게 보기 (프레임 확인용)
func _set_hitfx(slow_toggle: bool) -> void:
	if slow_toggle:
		MocoFX.slow = 1.0 if MocoFX.slow < 1.0 else 0.2
		hud.banner("타격 VFX 느리게  %s" % _onoff(MocoFX.slow < 1.0), Color(1.0, 0.45, 0.95), "버스트만 0.2 배속 (게임 시간은 그대로)")
		return
	var i := (MocoFX.STYLES.find(MocoFX.style) + 1) % MocoFX.STYLES.size()
	MocoFX.style = MocoFX.STYLES[i]
	hud.banner("타격 VFX  %s" % MocoFX.STYLE_NAMES[MocoFX.style], Color(1.0, 0.45, 0.95), "허수아비를 때려 보세요 · Shift+8 느리게 보기")


func _ground_title() -> String:
	var s := GroundBreak.current()
	return "%s · %s" % [s.name, s.ko]


## 바닥 파괴 스타일 바꾸기 → 플레이어 앞에 바로 미리보기
func _set_ground(step: int) -> void:
	GroundBreak.cycle(step)
	hud.banner("바닥 파괴  %s" % _ground_title(), Color(0.8, 0.85, 1.0), GroundBreak.current().desc)
	_preview_ground(1.0)


## 조준점(없으면 플레이어 앞 3m) 바닥에 연출만 낸다 (판정 없음)
func _preview_ground(power: float) -> void:
	var at := player.aim_point
	var to := at - player.global_position
	to.y = 0
	if to.length() < 1.0 or to.length() > 12.0:
		at = player.global_position + player.aim_dir * 3.0
	GroundBreak.burst(at, power, to.normalized() if to.length() > 0.1 else player.aim_dir)
	FX.shockwave(Vector3(at.x, Main.gy(at) + 0.05, at.z), Color(0.85, 0.9, 1.0), 2.0 + 2.0 * power, 0.28, 0.08)
	shake(0.25 + 0.4 * power)
	var thud := Sfx.play("land", 0.05, -2.0)
	if thud:
		thud.pitch_scale = 0.7


func _cutin_title() -> String:
	match PartnerDrone.cutin_style:
		"diagonal":
			return "사선 DOCKING"
		"cockpit":
			return "조종석 (예전)"
	return "끔"


func _set_cutin(step: int) -> void:
	var list := PartnerDrone.CUTIN_STYLES
	var i := (list.find(PartnerDrone.cutin_style) + step + list.size()) % list.size()
	PartnerDrone.cutin_style = list[i]
	hud.banner("합체 컷인  %s" % _cutin_title(), Color(0.45, 1.0, 0.78), "Q 로 합체하면 이 컷인이 나옵니다 (재화 무한이면 게이지 무제한)")


## 드론 없이 컷인만 다시 보기 (사선 컷인. 조종석 컷인은 실제 합체 비행에 묶여 있어 Q 로 볼 것)
func _preview_cutin() -> void:
	if PartnerDrone.cutin_style != "diagonal":
		hud.banner("미리보기는 사선 컷인만", Color(0.8, 0.9, 1.0), "0 키로 사선 DOCKING 을 고르거나 Q 로 실제 합체를 보세요")
		return
	PartnerDrone.begin_cutin(self, null, true)


var _voice_i := -1


## 사선 컷인 캐릭터: 번갈아 → 보라 정비사 고정 → 초록 메이드 고정 → … (바꾸면 바로 미리보기)
func _set_char() -> void:
	var modes := ["alt"]
	for ch in DiagonalDockingCutin.CHARACTERS:
		modes.append(ch.id)
	var i := (modes.find(DiagonalDockingCutin.char_mode) + 1) % modes.size()
	DiagonalDockingCutin.char_mode = modes[i]
	hud.banner("컷인 캐릭터  %s" % DiagonalDockingCutin.character_title(modes[i]), Color(0.45, 1.0, 0.78), "Q 합체 · F3 미리보기에 나올 캐릭터")
	if PartnerDrone.cutin_style == "diagonal":
		PartnerDrone.begin_cutin(self, null, true)


func _tween_title() -> String:
	var p := DiagonalDockingCutin.tween()
	return "%s · %s" % [p.name, p.ko]


## 사선 컷인 트위닝 프리셋 바꾸기 → 바로 미리보기
func _set_tween(step: int) -> void:
	var n := DiagonalDockingCutin.TWEEN_PRESETS.size()
	DiagonalDockingCutin.tween_preset = (DiagonalDockingCutin.tween_preset + step + n) % n
	var p := DiagonalDockingCutin.tween()
	hud.banner("컷인 트위닝  %s" % _tween_title(), Color(0.45, 1.0, 0.78), p.desc)
	if PartnerDrone.cutin_style == "diagonal":
		PartnerDrone.begin_cutin(self, null, true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var k := (event as InputEventKey).physical_keycode
		if boss_room and boss_room.inside and boss_room.handle_key(k, (event as InputEventKey).shift_pressed):
			get_viewport().set_input_as_handled()
			return
		var handled := true
		match k:
			KEY_F1:
				show_help = not show_help
				if not show_help:
					hud.banner("설명 숨김", Color(0.8, 0.9, 1.0), "F1 로 다시 보기")
			KEY_F2:
				ui_hidden = not ui_hidden
				_apply_ui()
			KEY_1:
				_place()
				hud.banner("RESET", Color(0.8, 0.9, 1.0), "허수아비를 다시 세우고 기록을 지웠습니다")
			KEY_2:
				layout = (layout + 1) % LAYOUTS.size()
				_place()
				hud.banner("배치  %s" % LAYOUTS[layout], Color(0.8, 0.9, 1.0), "")
			KEY_3:
				immortal = not immortal
				_apply_flags()
				hud.banner("허수아비  %s" % ("무적" if immortal else "처치 가능"), Color(0.8, 0.9, 1.0), "처치하면 죽음 연출 뒤 2초 만에 다시 섭니다" if not immortal else "")
			KEY_4:
				counter = not counter
				_apply_flags()
				hud.banner("반격  %s" % _onoff(counter), ParryFX.GOLD, "금빛 예고 탄이 닿기 직전에 Space 로 패링" if counter else "")
			KEY_5:
				moving = not moving
				_apply_flags()
				hud.banner("좌우 이동  %s" % _onoff(moving), Color(0.8, 0.9, 1.0), "")
			KEY_6:
				infinite = not infinite
				hud.banner("재화 무한  %s" % _onoff(infinite), Color(0.8, 0.9, 1.0), "에너지 · 미사일 · 부스터 · 드론 합체 게이지 (탄창은 그대로)")
			KEY_7:
				god = not god
				if not god:
					player.invuln = 0.0
				hud.banner("플레이어 무적  %s" % _onoff(god), Color(0.8, 0.9, 1.0), "")
			KEY_8:
				_set_hitfx((event as InputEventKey).shift_pressed)
			KEY_0:
				_set_cutin(-1 if (event as InputEventKey).shift_pressed else 1)
			KEY_F3:
				if (event as InputEventKey).shift_pressed:
					_voice_i = (_voice_i + 1) % DockingVoice.VOICES.size()
					DockingVoice.force = _voice_i
					hud.banner("보이스 %d/%d  %s" % [_voice_i + 1, DockingVoice.VOICES.size(), DockingVoice.NAMES[_voice_i]], Color(0.45, 1.0, 0.78), "합체 순간에 이 보이스로 재생")
				_preview_cutin()
			KEY_EQUAL:
				_set_ground(-1 if (event as InputEventKey).shift_pressed else 1)
			KEY_F4:
				_preview_ground(0.45 if (event as InputEventKey).shift_pressed else 1.0)
			KEY_MINUS:
				_set_tween(-1 if (event as InputEventKey).shift_pressed else 1)
			KEY_BRACKETLEFT:
				_set_char()
			_:
				handled = false
		if handled:
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)


# ── 자동 플레이 (--bot 확인용) ───────────────────────────

## 가장 가까운 허수아비 앞에 붙어 검 연타 → 사격 → 충전 레이저 → 미사일을 돌아가며 쓴다
func bot_input(p: Player) -> Dictionary:
	var out := {"move": Vector3.ZERO, "aim": p.global_position - Vector3(0, 0, 3), "fire": false, "slash": false, "dash": false, "charge": false, "boost": false, "jump": false}
	if boss_room and (boss_room.inside or Main.cmd_args.has("--bossroom")):
		return boss_room.bot_input(p, out)
	var best: TrainingDummy = null
	var bd := 1e9
	for d in dummies:
		if is_instance_valid(d) and d.alive and d.landed:
			var l := d.global_position.distance_to(p.global_position)
			if l < bd:
				bd = l
				best = d
	if best == null:
		return out
	out.aim = best.global_position + Vector3(0, 0.95, 0)
	var to := best.global_position - p.global_position
	to.y = 0
	if Main.cmd_args.has("--techshow"):
		return _tech_bot(p, best, to, bd, out)
	var cyc := fmod(time, 12.0)
	if cyc < 5.0:
		out.move = to.normalized() if bd > 2.6 else Vector3.ZERO
		out.slash = fmod(time, 0.1) < 0.017
	elif cyc < 8.0:
		out.move = (-to.normalized() if bd < 5.0 else Vector3.ZERO)
		out.fire = true
	elif cyc < 9.4:
		out.charge = true
	elif cyc > 10.0 and cyc < 10.05:
		out.ult = true
	return out


## --techshow: 반쯤 모은 돌진 → 최대 돌진(드릴 회오리) → 콤보 중 회피 레이저 를 차례로 보인다
func _tech_bot(p: Player, best: TrainingDummy, to: Vector3, bd: float, out: Dictionary) -> Dictionary:
	var cyc := fmod(time, 9.0)
	# 허수아비 왼쪽 옆에 서서 오른쪽으로 돌진한다 (옆모습이라 등 부스터가 잘 보인다)
	var spot := best.anchor + Vector3(-7.5, 0, 0.3)
	var go := spot - p.global_position
	go.y = 0
	if cyc < 0.8:
		out.move = go.limit_length(1.0) if go.length() > 0.3 else Vector3.ZERO
	elif cyc < 1.55:
		out.hold = true                                                   # 반쯤 모으기 (0.55초)
	elif cyc < 2.4:
		out.move = go.limit_length(1.0) if go.length() > 0.3 else Vector3.ZERO
	elif cyc < 3.9:
		out.hold = true                                                   # 최대까지 모으기
	elif cyc < 4.6:
		pass
	elif cyc < 7.5:
		out.move = to.normalized() if bd > 2.6 else Vector3.ZERO
		out.slash = fmod(time, 0.12) < 0.017
		# 콤보가 이어지는 도중 두 번 회피 레이저
		out.dual = (cyc > 5.3 and cyc < 5.32) or (cyc > 6.5 and cyc < 6.52)
	return out

