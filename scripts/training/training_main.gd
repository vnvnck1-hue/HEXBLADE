class_name TrainingMain
extends Main
## 전투 테스트장 (Main 상속). 엄폐물 없는 넓은 홀에 허수아비를 세워 두고 모든 무기·콤보·연출을 자유롭게 시험한다.
## 전투방·차단막·승패가 없고, 맞힌 피해는 허수아비 위 숫자와 오른쪽 위 DPS 표시로 보인다.
##
## 숫자 키로 바꾼다 (왼쪽 아래 패널에 현재 상태가 보인다):
##  1 허수아비 다시 세우기 + 기록 초기화   2 배치: 1기 / 3기 / 무리 6기 / 멀리 1기
##  3 무적 ↔ 처치 가능(쓰러지면 2초 뒤 다시 선다)   4 반격(패링 탄)   5 좌우 이동
##  6 재화 무한(에너지·미사일·부스터, 탄창은 그대로라 재장전도 볼 수 있다)   7 플레이어 무적   8 관통 일격 장전
## 확인용 실행 인자: --layout=0~3 --killable --counter --moving (봇: --bot)

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
var panel: Label
var _respawns: Array = []       # [남은 시간, 자리]
var _bot_t := 0.0


func _ready() -> void:
	process_priority = 100     # HUD 뒤에 돌아 오른쪽 위 문구를 덮어쓴다
	super._ready()
	center = map.room_center_world(map.start_room)
	player.global_position = center + Vector3(0, 0, 4.5)
	camera.snap(player.global_position)
	panel = Label.new()
	panel.add_theme_font_size_override("font_size", 14)
	panel.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	panel.add_theme_constant_override("outline_size", 5)
	panel.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.1))
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(22, -250)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hud.root.add_child(panel)
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
	FX.victory(player.global_position)
	hud.banner("TRAINING", Color(0.7, 0.95, 1.0), "허수아비를 마음껏 때려 보세요 · 숫자 키로 설정 · Esc 로비")


## 엄폐물 없는 평평한 넓은 홀 하나
func _build_arena() -> void:
	map = ArenaMap.new()
	world.add_child(map)
	map.terrain = false
	map.generate_single(map_seed if map_seed >= 0 else 7, ArenaMap.Shape.RECT, false, ROOM_SIZE)
	map.build()


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
func record_hit(d: TrainingDummy, dmg: int, source: String) -> void:
	if time - last_hit_t > CHAIN_GAP:
		chain_dmg = 0
	last_hit_t = time
	hits.append([time, dmg])
	total += dmg
	hit_count += 1
	last_hit = dmg
	chain_dmg += dmg
	best_chain = maxi(best_chain, chain_dmg)
	_damage_number(d, dmg, source)


## 맞은 자리 위로 튀어 오르며 사라지는 피해 숫자 (큰 피해일수록 크다)
func _damage_number(d: TrainingDummy, dmg: int, source: String) -> void:
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
		panel.text = _panel_text()


func _onoff(v: bool) -> String:
	return "ON " if v else "OFF"


func _panel_text() -> String:
	var lines := [
		"[ 전투 테스트 ]",
		"1  다시 세우기 · 기록 초기화",
		"2  배치            %s" % LAYOUTS[layout],
		"3  허수아비        %s" % ("무적 (1.6초 뒤 회복)" if immortal else "처치 가능 (2초 뒤 다시 섬)"),
		"4  반격 · 패링 탄  %s" % _onoff(counter),
		"5  좌우 이동       %s" % _onoff(moving),
		"6  재화 무한       %s" % _onoff(infinite),
		"7  플레이어 무적   %s" % _onoff(god),
		"8  관통 일격 장전",
		"",
		"좌클릭 길게 → 기 모으기 돌진 (최대: TEMPEST)",
		"E 누르고 조준 → 떼면 돌진 스킬 (쿨 3초 · 처치 시 1.5초)",
		"콤보 중 좌+우클릭 → 회피 레이저",
	]
	return "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var k := (event as InputEventKey).physical_keycode
		var handled := true
		match k:
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
				hud.banner("재화 무한  %s" % _onoff(infinite), Color(0.8, 0.9, 1.0), "에너지 · 미사일 · 부스터 (탄창은 그대로)")
			KEY_7:
				god = not god
				if not god:
					player.invuln = 0.0
				hud.banner("플레이어 무적  %s" % _onoff(god), Color(0.8, 0.9, 1.0), "")
			KEY_8:
				player._arm_phantom()
				hud.banner("관통 일격 장전", Color(1.0, 0.6, 0.45), "3초 안에 검을 휘두르세요")
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

