extends "res://scripts/stream/stream_main.gd"
## 무한 비행 모드 녹화용: stream_main.gd 그대로 + 실제 시계 기준 기술 각본 봇.
## 녹화 스크립트(stream_play_video.gd)가 clip0 (Time.get_ticks_msec) 를 넣으면 그때부터 PLAN 순서대로 기술을 쓴다.
## 기술마다 실제로 발동했는지는 플레이어 상태 변화로 따로 기록한다 (fired 로그).
## 패링: 패링 공격(포격 드론 금빛 탄 · 요격기 돌진 베기)이 판정 창에 들어오면 언제든 대시로 받아친다.
##   이 공격은 섹터 2·4 부터 나오므로 녹화는 --sector=4 로 시작한다.
## 파트너 드론: 게이지는 게임 규칙대로 청소로 찬다. 각본 틈에 X 보호막(50) · Q 합체 휠윈드(30)를 게이지가 차는 대로 쓴다.

const PLAN := [
	["combo", 2.6],       # 광선검 콤보
	["backstep", 5.0],    # 콤보 중 좌+우 = 회피 레이저
	["laser", 6.5],       # 충전 레이저 1단 (에너지 1칸 → 지속 레이저 때 다시 3칸)
	["sweep", 7.4],       # Space 누른 채 = 청소 질주 (드론 게이지)
	["perfect", 9.3],     # 2단 대시 PERFECT → 휠윈드
	["dashstrike", 11.2], # 대시 중 검 = 일격참 돌진
	["rush", 12.8],       # 좌클릭 길게 = 기 모으기 돌진 (최대 TEMPEST)
	["leap", 15.4],       # E = 도약 내려찍기
	["ult", 17.2],        # R = 미사일 궁극기 (조준은 짧게)
	["qwhirl", 18.6],     # Q = 드론 합체 + 휠윈드 (게이지 30)
	["mega", 21.8],       # 최대 충전 = 지속 레이저
	["zclean", 25.0],     # Z = 직접 청소 (게이지를 채워 보호막으로)
	["xshield", 26.4],    # X = 드론 보호막 (게이지 50)
	["finish", 27.2],
]
const ULT_AIM := 0.55     ## 궁극기 조준(슬로우모션) 최대 실제 시간

var clip0 := 0
var clip_on := false
var log_rows: Array = []
var _step := 0
var _act := ""
var _t0 := 0.0
var _sub := 0
var _ult_t := -1.0
var _prev := {}
var _max_combo := -1
var _parry_n := 0
var _drone_done := {}
var _hold_input := ""     ## Input.action_press 로 누르고 있는 드론 입력


func ct() -> float:
	return (Time.get_ticks_msec() - clip0) / 1000.0 if clip_on else -1.0


func mark(kind: String, extra := {}) -> void:
	var row := {"kind": kind, "ct": snappedf(ct(), 0.001), "unix": Time.get_unix_time_from_system(), "game_t": snappedf(time, 0.001)}
	row.merge(extra)
	log_rows.append(row)
	print("STREAMVID " + JSON.stringify(row))


func _physics_process(dt: float) -> void:
	super._physics_process(dt)
	if clip_on and is_instance_valid(player):
		_watch(player)


## 실제로 발동한 기술을 상태 변화로 기록한다
func _watch(p: Player) -> void:
	var s := {
		"combo": p.combo.posing() or p.combo.committed(),
		"backstep": p.tech.backstepping(),
		"charge_laser": p.charging,
		"dash": p.dash_t > 0.0 and not p.rainbow,
		"perfect_dash": p.dash_t > 0.0 and p.rainbow,
		"whirl": p.whirl.active(),
		"phantom": p.lunge_t > 0.0,
		"rush": p.tech.rushing(),
		"leap": p.leap.flying(),
		"ult_aim": p.ult_aiming,
		"ult_fire": p.ult_queue > 0,
		"mega": p.mega_t > 0.0,
	}
	var d = PartnerDrone.inst
	if is_instance_valid(d):
		s["drone_docked"] = d.state == PartnerDrone.St.DOCKED
		s["drone_whirl"] = d.whirl_t >= 0.0
		s["drone_shield"] = is_instance_valid(d.shield) and not d.shield.broken
		s["sweep_clean"] = d.sweeping
		s["z_clean"] = d.p_cleaning
	if Parry.inst and Parry.inst.count > _parry_n:
		_parry_n = Parry.inst.count
		mark("fired_parry", {"n": _parry_n})
	for k in s:
		if s[k] and not _prev.get(k, false):
			var ex := {}
			if k.begins_with("drone") or k.ends_with("clean"):
				ex = {"gauge": snappedf(d.gauge, 0.1)}
			elif k == "charge_laser":
				ex = {"energy": p.energy}
			elif k == "ult_fire":
				ex = {"missiles_fired": p.ult_count, "locks": p.locks.size()}
			mark("fired_" + k, ex)
		elif not s[k] and _prev.get(k, false) and k in ["charge_laser", "ult_aim", "mega", "whirl"]:
			mark("end_" + k, {"charge": snappedf(p.charge, 0.01)} if k == "charge_laser" else {})
	if p.combo.step > _max_combo and s.combo:
		_max_combo = p.combo.step
		mark("combo_step", {"step": p.combo.step + 1})
	if not s.combo:
		_max_combo = -1
	_prev = s


func _target(p: Player, max_d := INF) -> Enemy:
	var best: Enemy = null
	var bd := max_d
	for e in Enemy.live(get_tree()):
		var en := e as Enemy
		if en == null or not en.alive or not en.landed or en.prop:
			continue
		var gp := en.global_position
		if gp.z < -28.0 or gp.z > 9.0 or absf(gp.x) > 11.0:
			continue
		var d := gp.distance_to(p.global_position)
		if d < bd:
			bd = d
			best = en
	return best


func _enemy_count() -> int:
	var n := 0
	for e in Enemy.live(get_tree()):
		var en := e as Enemy
		if en and en.alive and en.landed and not en.prop and en.global_position.z > -28.0 and en.global_position.z < 9.0:
			n += 1
	return n


func _done() -> void:
	mark("act_end_" + _act)
	_act = ""


func bot_input(p: Player) -> Dictionary:
	var out := {"move": Vector3.ZERO, "aim": p.global_position - Vector3(0, 0, 8), "fire": false, "slash": false, "dash": false,
		"charge": false, "boost": true, "hold": false, "dual": false, "skill": false, "ult": false}
	if not p.alive:
		return out
	var now := ct()
	# 패링: 판정 창이 열린 공격이 있으면 무엇을 하던 대시로 받아친다 (궁극기 · 지속 레이저 중 제외)
	if now >= 0.0 and Parry.inst and Parry.inst.best_threat() != null and not p.ult_busy() and p.mega_t <= 0.0 and p.lunge_t <= 0.0:
		out.dash = true
		var th: Node3D = Parry.inst.best_threat() as Node3D
		if th:
			out.aim = th.global_position + Vector3(0, 0.95, 0)
		return out
	_drone_acts(p, now)
	if now >= 0.0 and _act == "" and _step < PLAN.size() and now >= PLAN[_step][1]:
		_act = PLAN[_step][0]
		_step += 1
		_t0 = now
		_sub = 0
		mark("act_start_" + _act, {"energy": p.energy, "missiles": p.missiles, "enemies": _enemy_count()})
	var e := _target(p)
	var near := _target(p, 8.0)
	var at := now - _t0
	# 기본: 앞쪽 적을 노려 사격하며 좌우로 비킨다
	if fmod(time, 6.0) < 0.02:
		bot_side = -bot_side
	var want := Vector3(bot_side * 4.0, 0, 3.0)
	if e:
		out.aim = e.global_position + Vector3(0, 0.95, 0)
		out.fire = true
		want.x = clampf(e.global_position.x * 0.7 + bot_side * 1.5, -8.5, 8.5)
	var melee := _act in ["combo", "backstep", "dashstrike", "rush", "leap", "finish", "perfect"]
	if melee and e:
		# 근접 기술: 적 바로 앞(화면 아래쪽)으로 붙는다
		want = e.global_position + Vector3(0, 0, 2.4)
		want.z = clampf(want.z, PLAYER_Z_MIN, PLAYER_Z_MAX)
	match _act:
		"combo":
			out.fire = false
			out.slash = near != null
			if at > 2.9:
				_done()
		"backstep":
			out.fire = false
			if p.combo.posing() or p.combo.link_t > 0.0:
				if p.laser_cd <= 0.0:
					out.dual = true
			else:
				out.slash = near != null
			if p.tech.backstepping() or at > 2.2:
				_done()
		"laser":
			out.fire = false
			if _sub == 0:
				out.charge = true
				if p.charging:
					_sub = 1
				elif at > 1.0:
					_done()
			elif _sub == 1:
				out.charge = p.charge < 0.4
				if not p.charging:
					_done()
		"perfect":
			out.fire = false
			var to := (e.global_position - p.global_position) if e else Vector3(bot_side, 0, -1)
			to.y = 0
			out.move = to.normalized()
			if _sub == 0:
				if p.dash_t <= 0.0 and p.dash_cd <= 0.0 and not p.combo.committed():
					out.dash = true
					_sub = 1
			elif _sub == 1:
				if p.dash_t > 0.0 and p.dash_t <= Player.CHAIN_WINDOW and not p.rainbow:
					out.dash = true
					_sub = 2
				elif p.dash_t <= 0.0 and at > 0.6:
					_sub = 0          # 놓쳤다: 다시
			elif _sub == 2:
				if p.whirl.armed() or p.rainbow:
					out.slash = true
				if p.whirl.active():
					_sub = 3
			elif _sub == 3 and not p.whirl.active():
				_done()
			if at > 3.5:
				_done()
			return _finish(p, out, want, true)
		"dashstrike":
			out.fire = false
			var to2 := (e.global_position - p.global_position) if e else Vector3(0, 0, -1)
			to2.y = 0
			if _sub == 0:
				if p.dash_t <= 0.0 and p.dash_cd <= 0.0 and not p.combo.committed() and e and to2.length() < 9.0:
					out.move = to2.normalized()
					out.dash = true
					_sub = 1
			elif _sub == 1:
				out.move = to2.normalized()
				if p.dash_t > 0.0:
					out.slash = true
				if p.lunge_t > 0.0:
					_sub = 2
				elif p.dash_t <= 0.0 and at > 1.2:
					_sub = 0
			elif _sub == 2 and p.lunge_t <= 0.0:
				_done()
			if at > 2.0:
				_done()
			if _sub <= 1:
				return _finish(p, out, want, _sub == 1)
		"rush":
			out.fire = false
			if _sub == 0:
				if not p.combo.committed() and p.slash_cd <= 0.0 and p.dash_t <= 0.0:
					out.hold = true
					_sub = 1
			elif _sub == 1:
				out.hold = true
				if p.tech.charging() and at > 1.45:
					out.hold = false
					_sub = 2
				elif not p.tech.charging() and not p.tech.busy() and at > 0.5:
					_sub = 0          # 검으로 나갔다: 다시 길게
					_t0 = now
			elif _sub == 2 and not p.tech.busy():
				_done()
			if at > 3.5:
				_done()
		"leap":
			out.fire = false
			var land := e.global_position if e else p.global_position + Vector3(0, 0, -6)
			var d3 := land - p.global_position
			d3.y = 0
			if d3.length() > 8.5:
				land = p.global_position + d3.normalized() * 8.5
			out.aim = land + Vector3(0, 0.95, 0)
			if _sub == 0:
				out.skill = true
				if at > 0.55:
					_sub = 1
			elif _sub == 1:
				if not p.leap.busy() and at > 1.4:
					_done()
			if at > 3.0:
				_done()
		"ult":
			if _sub == 0:
				if p.missiles > 0 and (_enemy_count() >= 3 or at > 1.5) and not p.ult_busy():
					out.ult = true
					_ult_t = now
					_sub = 1
			elif _sub == 1:
				if not p.ult_busy() and p.ult_queue == 0 and now - _ult_t > 1.0:
					_done()
			if at > 4.0:
				_done()
		"mega":
			if _sub == 0:
				out.fire = false
				if (p.energy >= Player.ENERGY_MAX and _enemy_count() >= 2) or at > 2.0:
					out.charge = true
					if p.charging:
						_sub = 1
			elif _sub == 1:
				out.fire = false
				out.charge = p.charge < 1.0
				if not p.charging:
					_sub = 2
			elif _sub == 2:
				if p.mega_t <= 0.0:
					_done()
			if at > 5.0:
				_done()
		"sweep":
			# Space: 누르는 순간 대시, 누른 채로 대시가 끝나면 청소 질주 (드론 쪽이 Input 의 dash 를 읽는다)
			out.fire = false
			if _sub == 0 and p.dash_cd <= 0.0 and p.dash_t <= 0.0:
				out.dash = true
				_press("dash")
				_sub = 1
			elif _sub == 1 and at > 1.6:
				_release()
				_done()
			if at > 2.2:
				_release()
				_done()
		"qwhirl":
			var dq = PartnerDrone.inst
			if not is_instance_valid(dq) or (_drone_done.has("whirl") and _sub == 0):
				_done()
			elif _sub == 0:
				if dq.gauge >= PartnerDrone.WHIRL_COST and dq.whirl_t < 0.0 and dq.state != PartnerDrone.St.RECALL:
					dq.whirl_link()
					if dq.state == PartnerDrone.St.RECALL or dq.whirl_t >= 0.0:
						_drone_done["whirl"] = true
						_sub = 1
				if at > 1.5:
					_done()
			elif _sub == 1:
				if dq.whirl_t < 0.0 and dq.state != PartnerDrone.St.RECALL and at > 0.6:
					_done()
				if at > 3.4:
					_done()
		"xshield":
			var dx = PartnerDrone.inst
			if not is_instance_valid(dx) or _drone_done.has("shield"):
				_done()
			elif dx.gauge >= PartnerDrone.SKILL_COST and dx.state in [PartnerDrone.St.FOLLOW, PartnerDrone.St.SEEK, PartnerDrone.St.CLEAN, PartnerDrone.St.CHEER, PartnerDrone.St.HOP]:
				_drone_done["shield"] = true
				dx.use_skill()
				_done()
			elif at > 1.5:
				_done()
		"zclean":
			out.fire = false
			if _sub == 0:
				_press("drone_clean")
				_sub = 1
			elif at > 1.3:
				_release()
				_done()
		"finish":
			out.slash = near != null and fmod(now, 1.6) < 0.8
	return _finish(p, out, want, false)


func _press(action: String) -> void:
	_release()
	Input.action_press(action)
	_hold_input = action


func _release() -> void:
	if _hold_input != "":
		Input.action_release(_hold_input)
		_hold_input = ""


## 드론 기술: 각본 기술 사이 틈(다음 기술까지 1초 넘게 남음)에 게이지가 차 있으면 쓴다
func _drone_acts(p: Player, now: float) -> void:
	var d = PartnerDrone.inst
	if now < 0.0 or not is_instance_valid(d) or _act != "" or p.ult_busy() or p.mega_t > 0.0 or p.charging:
		return
	var next_at: float = PLAN[_step][1] if _step < PLAN.size() else 99.0
	if next_at - now < 1.0:
		return
	var free: bool = d.state in [PartnerDrone.St.FOLLOW, PartnerDrone.St.SEEK, PartnerDrone.St.CLEAN, PartnerDrone.St.CHEER, PartnerDrone.St.HOP]
	# X 보호막: Q 휠윈드 몫(30)을 남겨 둘 수 있을 때, 휠윈드를 쓴 뒤면 50 만 있으면
	var need: float = PartnerDrone.SKILL_COST + (0.0 if _drone_done.has("whirl") else PartnerDrone.WHIRL_COST)
	if not _drone_done.has("shield") and free and d.gauge >= need:
		_drone_done["shield"] = true
		mark("act_start_drone_shield", {"gauge": snappedf(d.gauge, 0.1)})
		d.use_skill()


## 이동 마무리: 원하는 자리로 · 적 탄 옆으로 비키기 (각본 밖의 대시는 쓰지 않는다)
func _finish(p: Player, out: Dictionary, want: Vector3, keep_move: bool) -> Dictionary:
	if not keep_move:
		var move := want - p.global_position
		move.y = 0
		move = move.limit_length(1.0) * (1.0 if _act != "" else 0.8)
		for b in get_tree().get_nodes_in_group("enemy_bullets"):
			var bl := b as Bullet
			if bl == null:
				continue
			var rel := p.global_position - bl.position
			rel.y = 0
			var l := rel.length()
			if l < 2.6 and bl.vel.dot(rel) > 0:
				var side := Vector3(-bl.vel.z, 0, bl.vel.x).normalized()
				if side.dot(rel) < 0:
					side = -side
				move += side * (2.6 - l) * 1.3
		out.move = move.limit_length(1.0)
	return out


## 궁극기 조준은 짧게: ULT_AIM 초가 지났거나 화면의 적을 다 잠갔으면 뗀다
func bot_ult_release(p: Player) -> bool:
	var left := 0
	for e in Enemy.live(get_tree()):
		if (e as Enemy).landed and not p.locks.has(e):
			left += 1
	var held := (Time.get_ticks_msec() - p.ult_aim_start) / 1000.0
	return held >= ULT_AIM or (left == 0 and held > 0.25)
