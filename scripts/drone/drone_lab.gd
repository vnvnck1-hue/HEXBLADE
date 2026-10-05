class_name DroneLab
extends TrainingMain
## 파트너 드론 시험장 (TrainingMain 상속: 같은 넓은 홀 · 플레이어 무적 · 재화 무한).
## 허수아비 대신 실제 적(사격 드론 · 개미 병정)이 계속 나와 잔해·체액을 남기고, 드론이 따라다니며 치운다.
##
##  1 적 소환 켜기/끄기     2 오염 뿌리기 (잔해·체액 8개)     3 지원 게이지 가득
##  7 플레이어 무적          Q 합체+휠윈드 → 자동 분리 · X 지원 스킬 · Z 직접 청소 (본편과 같음)
## 확인용 실행 인자: --bot (봇이 싸우고 드론 조작도 자동) · --nofoes (적 없이 시작)

const FOES := 3
const SPAWN_GAP := 1.6

var spawning := true
var _spawn_t := 1.0
var _wander := Vector3.ZERO
var _wander_t := 0.0


func drone_lab() -> bool:
	return true


func _ready() -> void:
	panel_rows = false          # 설정 패널에 허수아비 설정 대신 드론 시험장 설명만
	super._ready()
	if Main.cmd_args.has("--nofoes"):
		spawning = false
	_scatter(10, center + Vector3(0, 0, -1.5), 6.0)
	hud.banner("PARTNER DRONE", DroneFX.MINT, "드론이 잔해·체액을 치웁니다 · Q 합체 + 휠윈드 · X 지원 · Z 직접 청소 · 숫자 키로 설정")


func _place() -> void:
	for d in dummies:
		if is_instance_valid(d):
			d.queue_free()
	dummies.clear()
	_reset_stats()


func _scatter(n: int, at: Vector3, r: float) -> void:
	for i in n:
		var a := randf() * TAU
		var p := map.push_out(at + Vector3(cos(a), 0, sin(a)) * randf_range(1.0, r), 0.8)
		p.y = Main.gy(p)
		if i % 3 == 2:
			DroneMess.spawn(world, p, DroneMess.Kind.GOO, randf_range(0.9, 1.3), BugEnemy.GOO[0])
		else:
			DroneMess.spawn(world, p, DroneMess.Kind.SCRAP, randf_range(0.85, 1.3))


func _physics_process(dt: float) -> void:
	# 무적은 맞지 않는 대신 체력을 매 틱 채우는 방식으로 바꾼다 (맞아야 드론 보호막이 막는 것을 볼 수 있다)
	var keep := god
	god = false
	super._physics_process(dt)
	god = keep
	if god and player.alive:
		player.hp = Player.MAX_HP
	if not spawning or state != State.PLAY:
		return
	_spawn_t -= dt
	var alive := pending_spawns
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.get("prop"):
			alive += 1
	if _spawn_t <= 0.0 and alive < FOES:
		_spawn_t = SPAWN_GAP
		_spawn_foe()


func _spawn_foe() -> void:
	var a := randf() * TAU
	var pos := map.push_out(player.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(6.5, 9.5), 1.0)
	pending_spawns += 1
	FX.spawn_marker(pos, 0.6)
	var ant := randf() < 0.4
	get_tree().create_timer(0.6, false).timeout.connect(func():
		pending_spawns -= 1
		var e: Enemy = BugAnt.new() if ant else Enemy.new()
		world.add_child(e)
		e.global_position = pos)


func _panel_text() -> String:
	var dr := PartnerDrone.inst
	var lines := [
		"[ 파트너 드론 시험장 ]",
		"1  적 소환          %s" % _onoff(spawning),
		"2  오염 뿌리기 (잔해·체액 8개)",
		"3  지원 게이지 가득",
		"7  플레이어 무적    %s (맞아도 체력 회복)" % _onoff(god),
		"",
		"Q  즉시 합체 + 회오리 휠윈드 2초 (게이지 30, 1.5배 이동 · 무적) → 끝나면 저절로 분리",
		"   합체 중: 광선검 속도 2배 · 총 연사 2배 · 보조 사격 (쓸 때마다 게이지 소모, 0 이면 자동 분리)",
		"X  지원 스킬 50: 분리 = 돌파 보호막 · 합체 = 트리플 볼텍스",
		"Z  누르는 동안 직접 청소 (공격 불가) · 오염 곁에 가만히 서 있으면 자동 청소",
	]
	if dr:
		lines.append("")
		lines.append("드론 청소 %d · 직접 %d · 회피 %d · 피격 %d · 막음 %d · 휠윈드 %d · 강화 소모 %d" % [dr.cleaned, dr.player_cleaned, dr.dodges, dr.hits_taken, dr.blocks, dr.whirls, int(dr.spent)])
	return "\n".join(lines)


func _process(dt: float) -> void:
	super._process(dt)
	hud.wave_label.text = "PARTNER DRONE"
	hud.count_label.text = "남은 오염 %d" % get_tree().get_nodes_in_group(DroneMess.GROUP).size()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var k := (event as InputEventKey).physical_keycode
		var handled := true
		match k:
			KEY_1:
				spawning = not spawning
				hud.banner("적 소환  %s" % _onoff(spawning), Color(0.8, 0.9, 1.0), "")
			KEY_2:
				_scatter(8, player.global_position, 5.5)
				hud.banner("오염 뿌리기", DroneFX.MINT, "잔해 · 체액 8개")
			KEY_3:
				if PartnerDrone.inst:
					PartnerDrone.inst.gauge = PartnerDrone.GAUGE_MAX
				hud.banner("지원 게이지 가득", DroneFX.MINT, "X 로 보호막 / 합체 중엔 볼텍스")
			KEY_4, KEY_5, KEY_8:
				pass
			_:
				handled = false
		if handled:
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)


## 봇: 가까운 적을 쫓아 쏘고 베다가, 가끔 다른 자리로 크게 걸어가 드론이 따라오는지 보인다
func bot_input(p: Player) -> Dictionary:
	var out := {"move": Vector3.ZERO, "aim": p.global_position - Vector3(0, 0, 3), "fire": false, "slash": false, "dash": false, "charge": false, "boost": false, "jump": false}
	_wander_t -= get_physics_process_delta_time()
	if _wander_t <= 0.0:
		_wander_t = 16.0
		var a := randf() * TAU
		_wander = map.push_out(center + Vector3(cos(a), 0, sin(a)) * 8.0, 1.5)
	if _wander_t > 13.0:
		var to := _wander - p.global_position
		to.y = 0
		out.move = to.normalized() if to.length() > 0.8 else Vector3.ZERO
		out.aim = p.global_position + out.move * 4.0
		return out
	var best: Enemy = null
	var bd := 1e9
	for e in Enemy.live(get_tree()):
		var en := e as Enemy
		if is_instance_valid(en) and en.alive and en.landed and not en.get("prop"):
			var l := en.global_position.distance_to(p.global_position)
			if l < bd:
				bd = l
				best = en
	if best == null:
		return out
	out.aim = best.global_position + Vector3(0, 0.95, 0)
	var to := best.global_position - p.global_position
	to.y = 0
	if bd > 5.0:
		out.move = to.normalized()
	out.fire = bd > 2.5
	out.slash = bd <= 2.5 and fmod(time, 0.12) < 0.017
	return out
