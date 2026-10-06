class_name LancasterBoss
extends Enemy
## LANCASTER — 버려진 시설의 광폭화된 보안 로봇. 벌레든 침입자든 무자비하게 지운다.
## 덩치는 플레이어의 두 배(3.6m, size_k 로 조절)지만 플레이어처럼 재빠르게 옆걸음 · 분사 대시로 움직이며 템포 높게 싸운다.
## 하체(이동 방향)와 상체(조준 방향)가 따로 돈다 — 애니메이션은 LancasterRig, 효과 · 투사체는 LancasterFX.
## 설계 · 수치 · 조작은 docs/lancaster-boss.md.
##
## 평소: 옆걸음질로 거리를 재며 짧은 견제 연사(PINNING), 가끔 분사 대시로 자리를 바꾸고 가까이 붙은 검을 피한다.
## 패턴 (컨셉 시트 01~04)
##   burst  PINNING BURST     버팀(조준 레이저 · 총열 가속) → 지속 연사(추적 속도 제한, 대시로 빠져나간다) → 배기(증기 · 약점)
##   sweep  SWEEP SUPPRESSION 부채꼴 예고 → 옆으로 미끄러지며 110° 휩쓸기 사격 → 회복
##   claw   CLAW CRUSH        [근접 패링] 집게를 뒤로 젖혀 하얗게 충전 → 별빛 알림 → 분사 돌진으로 정확히 0.5초 뒤 움켜쥔다
##   slug   HEAVY SLUG        [원거리 패링] 총열을 멈추고 충전 → 금빛 중탄 (되받아치면 크게 경직)
##   spike  PILE-DRIVER SPIKE 붉은 원 예고 → 분사 도약 → 가시를 바닥에 박는다 (박힌 동안 약점)
##   stomp  HEAVY STOMP       가까이 오면 발을 들어 → 내리찍어 퍼지는 충격파 고리 (뛰거나 대시로 넘는다)
##   pods   SECURITY POD BARRAGE  어깨 포드가 돌며 표적 원을 찍고 박격탄을 쏟아붓는다 (그동안에도 움직인다)
## 2페이즈 (체력 50%) OVERDRIVE: 눈이 붉어지고 통풍구가 달아오르며 전류 · 증기. 빨라지고, 포드 포격이 다른 패턴과 겹치며,
##   집게 돌진이 연달아 나오고 중탄은 세 발.
## 패링당하거나 자기 중탄을 맞으면 크게 휘청(STAGGER, 받는 피해 두 배). 쓰러지면 무릎 꿇고 정지(SHUTDOWN).

signal phase_changed(phase: int)
signal defeated
signal pattern_started(id: String)

enum St { DORMANT, WAKE, FIGHT, TRANSITION, STAGGER, DYING, DEAD }

const Rig := preload("res://scripts/lancaster/lancaster_rig.gd")

const MAX_HP := 900.0
const PHASE2_AT := 0.5
const SPEED := 7.4               ## 옆걸음 속도 (플레이어 6.8)
const ACCEL := 44.0
const DASH_SPEED := 19.0
const DASH_TIME := 0.26
const BODY_R := 1.45             ## 판정 반지름 (size_k 1 기준)
const CLAW_REACH := 2.3          ## 돌진 집게가 닿는 거리 (몸 중심에서)
const SPIKE_R := 3.0
const STOMP_R := 5.2
const MORTAR_R := 1.7
const TRACER_SPEED := 28.0
const SIZES := [2.0, 1.5, 2.5]   ## 플레이어 키의 배수
const NAMES := {
	"burst": "PINNING BURST · 제압 연사", "sweep": "SWEEP SUPPRESSION · 휩쓸기", "claw": "CLAW CHAIN · 집게 연타",
	"slug": "HEAVY SLUG · 중탄", "spike": "PILE-DRIVER · 가시 박기", "stomp": "HEAVY STOMP · 짓밟기",
	"pods": "POD BARRAGE · 포드 포격",
}
## 패턴 세트 (허수아비 씬 보스방 2 키)
const SETS := [
	{"id": "auto", "ko": "전체", "list": ["burst", "sweep", "claw", "slug", "spike", "stomp", "pods"]},
	{"id": "suppress", "ko": "제압 사격", "list": ["burst", "sweep", "slug"]},
	{"id": "close", "ko": "근접 제압", "list": ["claw", "spike", "stomp"]},
	{"id": "lockdown", "ko": "구역 봉쇄", "list": ["pods", "stomp", "sweep"]},
	{"id": "parry", "ko": "패링 연습", "list": ["claw", "slug"]},
	{"id": "move", "ko": "이동만", "list": []},
]
const TEMPOS := [{"ko": "보통", "k": 1.0}, {"ko": "빠름", "k": 1.25}, {"ko": "광폭", "k": 1.55}]
## 받는 피해 배율 (원천별)
const DMG := {"bullet": 1.0, "slash": 2.4, "phantom": 2.2, "missile": 1.6, "laser": 1.0, "parry": 2.5, "deflect": 2.5}

var rig: LancasterRig
var bar: Node
var st := St.DORMANT
var st_t := 0.0
var phase := 1
var boss_hp := MAX_HP
var immortal := false
var set_i := 0
var tempo_i := 0
var size_i := 0
var size_k := 1.0
var active := false              ## 플레이어가 방 안에 있다 (밖이면 싸우지 않고 지킨다)
var hold_ai := false             ## 행동 정지 (이동 · 공격 없이 서서 조준만)
var room_rect := Rect2()         ## 몸 중심이 머무를 수 있는 바닥 (xz). 크기 0 이면 제한 없음
var home := Vector3.ZERO
var weak := false

var vel := Vector3.ZERO
var want_vel := Vector3.ZERO
var face_yaw := 0.0
var aim_yaw := 0.0
var strafe_dir := 1.0
var strafe_t := 0.0
var dash_t := 0.0
var dash_dir := Vector3.ZERO
var dash_cd := 1.5
var pin_cd := 1.2
var pin_left := 0
var pin_t := 0.0
var rest := 1.2
var pat := ""
var pt := 0.0
var ps := {}
var last_pat := ""
var force_next := ""
var chain := 0
var sight: MeshInstance3D
var lift_y := 0.0                ## 도약 높이 (보이는 몸만)
var pods := {"st": "", "t": 0.0, "targets": [], "warns": [], "i": 0, "fire_t": 0.0, "auto": 4.0}
var _pod_lines: MeshInstance3D

# 리그 입력 목표 (매 틱 기본값으로 돌아가고 상태가 덮어쓴다. 값은 부드럽게 따라간다)
var _want := {}
var _rate := {}
var _snap := {}
var _cur := {}
const RIG_KEYS := {
	"crouch": 0.0, "lean": 0.0, "air": 0.0, "claw": 0.0, "pods_up": 0.0, "stomp": 0.0, "kneel": 0.0, "gun_aim": 0.0,
	"jet": 0.0, "heat": 0.0, "eye_on": 1.0, "rage": 0.0,
}

var _ghost_t := 0.0
var _fx_t := 0.0
var _snd_t := 0.0
var _hit_snd := 0.0
var _flash_t := 0.0
var _regen_t := 0.0
var _charge_q := -1.0
var _steam_t := 0.0
var _sq := 0.0                   ## 늘임(-) · 찌그러짐(+) 스프링 (임팩트 스윙 · 패링 반동)
var _sq_v := 0.0


func _ready() -> void:
	add_to_group("enemies")
	is_boss = true
	landed = true
	slice_size = Vector3(3.0, 3.4, 2.4)
	slice_color = Color("c9ccd6")
	visual = Node3D.new()
	add_child(visual)
	j = {"body": visual, "core": null}
	shadow = FX.blob_shadow(self, 4.2, 0.55)
	rig = Rig.new().setup(visual)
	sight = LancasterFX.sight()
	add_child(sight)
	sight.top_level = true
	_pod_lines = MeshInstance3D.new()
	_pod_lines.top_level = true
	_pod_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pod_lines)
	for k: String in RIG_KEYS:
		_cur[k] = RIG_KEYS[k]
	set_size(size_i)
	face_yaw = rotation.y
	aim_yaw = face_yaw
	rig.reset_feet()
	if st == St.DORMANT:
		_cur.kneel = 1.0
		_cur.eye_on = 0.0
		_cur.lean = 0.3


func _exit_tree() -> void:
	_end_pattern(true)
	_pods_stop()
	if Parry.inst:
		Parry.inst.unregister(self)


# ── 설정 (보스방 프리셋) ───────────────────────────────

func set_size(i: int) -> void:
	size_i = i
	size_k = float(SIZES[i]) / 2.0
	visual.scale = Vector3.ONE * size_k
	radius = BODY_R * size_k
	hp_bar_y = 3.9 * size_k
	if is_instance_valid(shadow):
		shadow.scale = Vector3.ONE * size_k


func tempo() -> float:
	return float(TEMPOS[tempo_i].k) * (1.22 if phase >= 2 else 1.0)


## 다음 패턴을 바로 시전 (현재 세트에서 차례로)
func cast_next() -> String:
	var list: Array = SETS[set_i].list
	if list.is_empty():
		return ""
	var i := (list.find(last_pat) + 1) % list.size()
	force_next = list[i]
	rest = 0.0
	if pat != "" and pat != "pods":
		_end_pattern(false)
	return force_next


## 페이즈 강제 (1 = 처음 상태로, 2 = 광폭화 연출)
func force_phase(p: int) -> void:
	if not alive:
		return
	if p == 2 and phase == 1:
		boss_hp = minf(boss_hp, MAX_HP * PHASE2_AT)
		_bar_hp()
		_begin_transition()
	elif p == 1 and phase == 2:
		phase = 1
		boss_hp = MAX_HP
		_bar_hp()
		if is_instance_valid(bar):
			bar.call("set_phase", 1)
		phase_changed.emit(1)


func wake() -> void:
	if st == St.DORMANT:
		st = St.WAKE
		st_t = 0.0
		Sfx.play("hrise", 0.03, -4.0)


# ── 매 틱 ───────────────────────────────────────────────

func _physics_process(dt: float) -> void:
	if rig == null:
		return
	t += dt
	st_t += dt
	_hit_snd = maxf(0.0, _hit_snd - dt)
	_reset_wants()
	var p := Main.inst.player
	var playing := Main.inst.state == Main.State.PLAY and p.alive
	match st:
		St.DORMANT:
			_dormant(dt)
		St.WAKE:
			_wake(dt)
		St.FIGHT:
			if active and playing and not hold_ai:
				_fight(dt, p)
			else:
				_guard(dt, p)
		St.TRANSITION:
			_transition(dt)
		St.STAGGER:
			_stagger_tick(dt)
		St.DYING:
			_dying(dt)
		St.DEAD:
			_dead(dt)
	_pods_update(dt)
	_move(dt)
	_apply_rig(dt)
	rig.update(dt)
	_feet()
	_push_player(p)
	_overlay_tick(dt)
	if immortal and alive:
		_regen_t -= dt
		if _regen_t <= 0.0 and boss_hp < MAX_HP * (PHASE2_AT if phase >= 2 else 1.0):
			boss_hp = move_toward(boss_hp, MAX_HP * (PHASE2_AT if phase >= 2 else 1.0), MAX_HP * 0.6 * dt)
			_bar_hp()


func _reset_wants() -> void:
	for k: String in RIG_KEYS:
		_want[k] = RIG_KEYS[k]
		_rate[k] = 10.0
	_snap.clear()
	if phase >= 2 and alive:
		_want.rage = 1.0
	rig.pose = {}
	rig.stiff = 190.0
	rig.damp = 19.0
	rig.plant = false
	rig.spin = 2.0
	rig.pods_spin = 0.0
	want_vel = Vector3.ZERO
	windup_k = 0.0


func _w(key: String, v: float, rate := -1.0) -> void:
	_want[key] = v
	if rate > 0.0:
		_rate[key] = rate


func _snapv(key: String, v: float) -> void:
	_want[key] = v
	_snap[key] = true


func _apply_rig(dt: float) -> void:
	for k: String in RIG_KEYS:
		if _snap.has(k):
			_cur[k] = _want[k]
		else:
			_cur[k] = lerpf(_cur[k], _want[k], 1.0 - exp(-float(_rate[k]) * dt))
	rig.crouch = _cur.crouch
	rig.lean = _cur.lean
	rig.air = _cur.air
	rig.claw = _cur.claw
	rig.pods_up = _cur.pods_up
	rig.stomp = _cur.stomp
	rig.kneel = _cur.kneel
	rig.gun_aim = _cur.gun_aim
	rig.jet = _cur.jet
	rig.heat = _cur.heat
	rig.eye_on = _cur.eye_on
	rig.rage = _cur.rage
	rig.vel = vel
	rig.aim_yaw = aim_yaw
	visual.position.y = lift_y
	_sq_v += (-_sq * 900.0 - _sq_v * 20.0) * dt
	_sq += _sq_v * dt
	var q := clampf(_sq, -1.2, 1.2)
	visual.scale = Vector3(1.0 + 0.07 * q, 1.0 - 0.09 * q, 1.0 + 0.07 * q) * size_k


func _yaw_of(d: Vector3) -> float:
	return atan2(-d.x, -d.z)


func _dir_of(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func _to_player() -> Vector3:
	var d := Main.inst.player.global_position - global_position
	d.y = 0
	return d


func _chest() -> Vector3:
	return Main.inst.player.global_position + Vector3(0, 0.95, 0)


## 몸 중심을 방 안 · 벽 밖으로
func _clamp(p: Vector3) -> Vector3:
	if room_rect.size != Vector2.ZERO:
		p.x = clampf(p.x, room_rect.position.x, room_rect.end.x)
		p.z = clampf(p.z, room_rect.position.y, room_rect.end.y)
	return Main.inst.push_out(p, radius)


func _move(dt: float) -> void:
	if dash_t > 0.0:
		dash_t -= dt
		var k := clampf(dash_t / DASH_TIME, 0.0, 1.0)
		vel = dash_dir * DASH_SPEED * (0.35 + 0.65 * k) * sqrt(size_k)
		_w("jet", 1.0, 30.0)
		_w("air", 0.65, 30.0)          # 분사 대시: 다리를 살짝 접고 미끄러진다
		_ghost_t -= dt
		if _ghost_t <= 0.0:
			_ghost_t = 0.035
			FX.afterimage(visual, Color(1.0, 0.62, 0.3, 0.32), 0.2)
		if dash_t <= 0.0:
			vel *= 0.4
	else:
		vel = vel.move_toward(want_vel, ACCEL * dt * maxf(1.0, tempo()))
	var np := _clamp(global_position + vel * dt)
	var moved := np - global_position
	if moved.length() < vel.length() * dt * 0.5 and dash_t > 0.0:
		dash_t = minf(dash_t, 0.05)
	global_position = np
	# 하체: 이동 방향을 본다 (뒷걸음질이면 조준 쪽을 보고 뒤로 걷는다). 서 있으면 조준이 크게 벗어날 때만 돈다
	var spd := Vector2(vel.x, vel.z).length()
	var target := face_yaw
	if spd > 1.2:
		target = _yaw_of(vel)
		if absf(wrapf(target - aim_yaw, -PI, PI)) > 1.9:
			target = wrapf(target + PI, -PI, PI)
	elif absf(wrapf(aim_yaw - face_yaw, -PI, PI)) > 0.9:
		target = aim_yaw
	face_yaw = lerp_angle(face_yaw, target, 1.0 - exp(-9.0 * tempo() * dt))
	rotation.y = face_yaw


## 디딘 발: 먼지 · 진동 · 발소리
func _feet() -> void:
	if rig.stepped <= 0:
		return
	var spd := Vector2(vel.x, vel.z).length()
	for at in rig.step_at:
		if spd > 3.0 or st != St.FIGHT:
			LancasterFX.dust_ring(at, 0.35 * size_k, 4)
		var thud := Sfx.play("land", 0.08, -14.0 + minf(spd, 8.0) * 0.6)
		if thud:
			thud.pitch_scale = 0.55 + randf() * 0.1
	Main.inst.shake(0.05 * size_k + spd * 0.006)


func _push_player(p: Player) -> void:
	if not alive or not is_instance_valid(p) or not p.alive:
		return
	var d := p.global_position - global_position
	d.y = 0
	var r := radius + p.hit_radius + 0.05
	if d.length() < r:
		var n := d.normalized() if d.length() > 0.01 else _dir_of(face_yaw + PI)
		p.global_position += n * (r - d.length())


# ── 대기 · 기동 ─────────────────────────────────────────

func _dormant(_dt: float) -> void:
	_snapv("kneel", 1.0)
	_snapv("lean", 0.3)
	_w("eye_on", 0.04 + (0.25 if fmod(t, 3.1) < 0.08 else 0.0), 30.0)
	rig.pose = {"upperarm_l": Vector3(-0.25, 0, 0.1), "upperarm_r": Vector3(-0.2, 0, -0.1), "forearm_r": Vector3(-0.2, 0, 0)}
	if active:
		wake()


func _wake(dt: float) -> void:
	var e := st_t
	_fx_t -= dt
	# 0~0.6 눈이 깜빡이며 켜진다
	var on := 0.0
	if e < 0.6:
		on = 1.0 if fmod(e * 13.0, 1.0) < 0.35 + e else 0.1
	else:
		on = 1.0
	_w("eye_on", on, 40.0)
	var rise := smoothstep(0.55, 1.6, e)
	_w("kneel", 1.0 - rise, 30.0)
	_w("lean", lerpf(0.3, -0.22, rise) if e < 1.8 else 0.0, 12.0)
	rig.pods_spin = 10.0 if e > 0.7 else 0.0
	_w("pods_up", 1.0 if e > 0.9 and e < 2.1 else 0.0, 8.0)
	aim_yaw = _yaw_of(_to_player())
	if e > 1.6 and e < 2.3:
		rig.pose = {"upperarm_l": Vector3(0.35, 0, -0.6), "upperarm_r": Vector3(0.7, 0, 0.7), "forearm_r": Vector3(0.9, 0, 0), "torso": Vector3(0.25, 0, 0)}
		if not ps.has("roar"):
			ps.roar = true
			_roar(0.6)
		if _fx_t <= 0.0:
			_fx_t = 0.05
			LancasterFX.steam(rig.at("pt_vent_l"), 1.0)
			LancasterFX.steam(rig.at("pt_vent_r"), 1.0)
	if e >= 2.5:
		ps.clear()
		st = St.FIGHT
		st_t = 0.0
		rest = 0.6
		if is_instance_valid(bar):
			bar.call("appear")
		_bar_hp()


## 포효: 증기 · 충격파 · 가까운 플레이어를 밀어낸다 (피해 없음)
func _roar(k: float) -> void:
	var c := global_position + Vector3(0, 2.4 * size_k, 0)
	FX.shockwave(global_position + Vector3(0, 0.1, 0), Color(1.0, 0.7, 0.4), 8.0 * size_k * k + 3.0, 0.45, 0.14)
	Distortion.burst(c, 6.0 * size_k, 0.5, 1.2 * k, 0.4)
	LancasterFX.dust_ring(global_position, 2.0 * size_k, 14)
	Main.inst.shake(0.5 * k + 0.2)
	var s := Sfx.play("overload", 0.03, -2.0)
	if s:
		s.pitch_scale = 0.62
	var p := Main.inst.player
	var d := _to_player()
	if p.alive and d.length() < 7.0 * size_k:
		p.velocity += d.normalized() * 9.0 * k


# ── 지키기 (플레이어가 방 밖 · 행동 정지) ─────────────────

func _guard(_dt: float, _p: Player) -> void:
	_end_pattern(false)
	if pods.st != "":
		_pods_stop()
	var d := _to_player()
	aim_yaw = _yaw_of(d) if d.length() > 0.5 else aim_yaw
	if hold_ai:
		_w("gun_aim", 0.8)
		rig.aim_point = _chest()
		return
	var back := home - global_position
	back.y = 0
	if back.length() > 1.0:
		want_vel = back.normalized() * SPEED * 0.6
	rig.pods_spin = 1.4
	_w("gun_aim", 0.3)
	rig.aim_point = _chest()


# ── 전투 ────────────────────────────────────────────────

func _fight(dt: float, p: Player) -> void:
	var to := _to_player()
	var dist := to.length()
	aim_yaw = _yaw_of(to) if dist > 0.3 else aim_yaw
	rig.aim_point = _chest()
	if pat != "":
		pt += dt
		call("_p_" + pat, dt, p, to, dist)
		return
	_neutral(dt, p, to, dist)
	rest -= dt * tempo()
	if rest <= 0.0 and dash_t <= 0.0:
		_pick(dist)
	# 2페이즈: 포드 포격이 다른 패턴과 겹쳐 나온다
	if phase >= 2 and pods.st == "" and SETS[set_i].list.has("pods"):
		pods.auto = float(pods.auto) - dt * tempo()
		if pods.auto <= 0.0:
			pods.auto = randf_range(5.5, 7.5)
			_pods_start()


## 평소 움직임: 옆걸음 · 거리 맞추기 · 견제 연사 · 분사 대시 · 회피
func _neutral(dt: float, p: Player, to: Vector3, dist: float) -> void:
	var k := tempo()
	strafe_t -= dt
	if strafe_t <= 0.0:
		strafe_t = randf_range(0.9, 2.2) / k
		strafe_dir = -strafe_dir if randf() < 0.65 else strafe_dir
	var n := to / maxf(dist, 0.01)
	var side := Vector3(-n.z, 0, n.x) * strafe_dir
	var want := 7.5
	var radial := clampf((dist - want) * 0.6, -1.0, 1.0)
	want_vel = (side * 0.9 + n * radial).normalized() * SPEED * minf(k, 1.3) * sqrt(size_k)
	# 벽에 막히면 반대로
	if Main.inst.is_blocked(global_position + side * (radius + 1.2)) or (room_rect.size != Vector2.ZERO and not room_rect.grow(-0.5).has_point(Vector2(global_position.x, global_position.z) + Vector2(side.x, side.z) * 1.5)):
		strafe_dir = -strafe_dir
	_w("gun_aim", 0.75, 8.0)
	rig.spin = 6.0
	# 견제 연사
	pin_cd -= dt * k
	if pin_left > 0:
		_w("gun_aim", 1.0, 20.0)
		rig.spin = 34.0
		pin_t -= dt
		if pin_t <= 0.0:
			pin_t = 0.075
			pin_left -= 1
			_fire_round(_lead_dir(0.55), 0.05)
	elif pin_cd <= 0.0 and dist > 3.5 and dash_t <= 0.0:
		pin_cd = randf_range(1.3, 2.4)
		pin_left = randi_range(4, 6) + (2 if phase >= 2 else 0)
		pin_t = 0.12
	# 분사 대시: 자리 바꾸기 · 가까운 검 피하기
	dash_cd -= dt * k
	if dash_cd <= 0.0 and dash_t <= 0.0:
		var close := dist < 3.4
		if close and randf() < 0.55 or (not close and randf() < 0.35):
			var d := side
			if close:
				d = (-n * 0.75 + side * 0.65).normalized()
			elif dist > 11.0:
				d = (n * 0.8 + side * 0.4).normalized()
			_dash(d)
		dash_cd = randf_range(1.4, 2.6)


func _dash(d: Vector3) -> void:
	dash_dir = Vector3(d.x, 0, d.z).normalized()
	dash_t = DASH_TIME
	_ghost_t = 0.0
	Sfx.play("dash", 0.06, -4.0)
	LancasterFX.jet_burst(-6.0, 0.7, 0.3)
	LancasterFX.dust_ring(global_position, 0.8 * size_k, 6)
	FX.flash(rig.at("pt_jet_l"), Color(1.0, 0.6, 0.25), 0.9, 0.08)
	FX.flash(rig.at("pt_jet_r"), Color(1.0, 0.6, 0.25), 0.9, 0.08)


## 플레이어 이동을 내다본 조준 방향 (수평)
func _lead_dir(lead_k: float) -> Vector3:
	var p := Main.inst.player
	var m := rig.at("pt_muzzle")
	var tgt := p.global_position
	var dist := Vector2(tgt.x - m.x, tgt.z - m.z).length()
	tgt += Vector3(p.velocity.x, 0, p.velocity.z) * (dist / TRACER_SPEED) * lead_k
	var d := tgt - m
	d.y = 0
	return d.normalized() if d.length() > 0.01 else _dir_of(aim_yaw)


## 예광탄 한 발 (수평 방향 d, 퍼짐 spread rad)
func _fire_round(d: Vector3, spread: float) -> void:
	var m := rig.at("pt_muzzle")
	var dir := d.rotated(Vector3.UP, randf_range(-spread, spread))
	var y := (Main.inst.player.global_position.y + 0.95) - m.y
	var flat := Vector2(dir.x, dir.z).length()
	var fd := Vector3(dir.x, clampf(y / 12.0, -0.25, 0.25) * flat, dir.z).normalized()
	LancasterFX.tracer(m + fd * 0.3, fd, TRACER_SPEED)
	GunFX.muzzle(m, fd, 1.6 * size_k, randf() < 0.4)
	var side := -(visual.global_basis.x.normalized())
	GunFX.eject(rig.at("pt_eject"), (side + Vector3.UP * 0.6).normalized(), fd, 1.6)
	rig.kick("upperarm_l", Vector3(-2.2, randf_range(-1, 1) * 0.6, 0))
	rig.kick("torso", Vector3(0.5, 0, 0))
	_cur.heat = minf(1.0, float(_cur.heat) + 0.016)
	_snd_t -= 1.0
	if _snd_t <= 0.0:
		_snd_t = 2.0
		var s := Sfx.play("shoot", 0.06, -9.0)
		if s:
			s.pitch_scale = 0.72 + randf() * 0.06


func _pick(dist: float) -> void:
	var list: Array = SETS[set_i].list
	if list.is_empty():
		rest = 1.0
		return
	var id := force_next
	force_next = ""
	if id == "" or not list.has(id):
		var best := ""
		var total := 0.0
		var w := {}
		for c: String in list:
			var x := 1.0
			match c:
				"burst", "sweep":
					x = 1.4 if dist > 4.5 else 0.3
				"slug":
					x = 1.2 if dist > 5.0 else 0.3
				"claw":
					x = 1.9 if dist > 2.5 and dist < 12.0 else 0.7
				"spike":
					x = 1.0 if dist > 3.5 and dist < 13.0 else 0.35
				"stomp":
					x = 2.2 if dist < 5.0 * size_k else 0.05
				"pods":
					x = 0.9 if pods.st == "" else 0.0
			if c == last_pat and list.size() > 1:
				x *= 0.1
			w[c] = x
			total += x
		var r := randf() * total
		for c: String in w:
			r -= float(w[c])
			if r <= 0.0:
				best = c
				break
		id = best if best != "" else list[0]
	_start(id)


func _start(id: String) -> void:
	pat = id
	pt = 0.0
	ps = {"ph": ""}
	last_pat = id
	pin_left = 0
	pattern_started.emit(id)
	if is_instance_valid(bar):
		bar.call("set_pattern", NAMES.get(id, id))
	print("LANCASTER_PATTERN %s t=%.1f hp=%.0f phase=%d" % [id, Main.inst.time, boss_hp, phase])


func _end_pattern(_aborted: bool) -> void:
	if ps.has("warn"):
		LancasterFX.clear_warn(ps.warn, false)
	if ps.has("fan"):
		LancasterFX.clear_warn(ps.fan, false)
	if ps.has("ring"):
		LancasterFX.clear_warn(ps.ring, false)
	if is_instance_valid(sight):
		sight.visible = false
	if pat == "claw" or pat == "slug":
		_end_warn()
		if Parry.inst:
			Parry.inst.unregister(self)
	weak = false
	lift_y = 0.0
	pat = ""
	ps = {}
	pt = 0.0
	rest = randf_range(0.45, 1.05)
	if is_instance_valid(bar):
		bar.call("set_pattern", "")


## 다음 단계로
func _ph(name: String) -> void:
	ps.ph = name
	pt = 0.0


# ── 패턴: PINNING BURST ─────────────────────────────────

func _p_burst(dt: float, _p: Player, to: Vector3, dist: float) -> void:
	var k := tempo()
	var brace := 0.6 / k
	match ps.ph:
		"":
			ps.aim = to / maxf(dist, 0.01)
			Sfx.play("twind", 0.03, -4.0)
			_ph("brace")
		"brace":
			rig.plant = true
			_w("crouch", 0.45, 14.0)
			_w("gun_aim", 1.0, 16.0)
			rig.spin = lerpf(4.0, 40.0, pt / brace)
			rig.pose = {"torso": Vector3(-0.12, 0, 0), "upperarm_r": Vector3(0.35, 0, 0.25), "forearm_r": Vector3(0.7, 0, 0)}
			ps.aim = _lead_dir(0.3)
			aim_yaw = _yaw_of(ps.aim)
			rig.aim_point = _muzzle_ray(ps.aim)
			LancasterFX.aim_sight(sight, rig.at("pt_muzzle"), rig.at("pt_muzzle") + rig.barrel_dir() * 22.0, pt / brace)
			if pt >= brace:
				sight.visible = false
				ps.shot_t = 0.0
				ps.dur = 1.75 if phase == 1 else 2.2
				_ph("fire")
		"fire":
			rig.plant = true
			_w("crouch", 0.5, 14.0)
			_w("gun_aim", 1.0, 30.0)
			rig.spin = 46.0
			# 추적: 돌리는 속도에 한계가 있어 옆으로 달리거나 대시로 벗어날 수 있다
			var want := _lead_dir(0.6)
			var cur: Vector3 = ps.aim
			var ang := cur.signed_angle_to(want, Vector3.UP)
			var turn := (1.05 if phase == 1 else 1.45) * k
			cur = cur.rotated(Vector3.UP, clampf(ang, -turn * dt, turn * dt))
			ps.aim = cur
			aim_yaw = _yaw_of(cur)
			rig.aim_point = _muzzle_ray(cur)
			want_vel = -cur * 0.7
			rig.pose = {"torso": Vector3(-0.16, 0, sin(t * 47.0) * 0.02), "upperarm_r": Vector3(0.35, 0, 0.3), "forearm_r": Vector3(0.75, 0, 0)}
			ps.shot_t = float(ps.shot_t) - dt
			var rate := (16.0 if phase == 1 else 21.0) * sqrt(k)
			while ps.shot_t <= 0.0:
				ps.shot_t = float(ps.shot_t) + 1.0 / rate
				_fire_round(cur, 0.035)
			if pt >= float(ps.dur):
				_w("heat", 1.0)
				Sfx.play("hatch", 0.04, -4.0)
				_ph("vent")
		"vent":
			_vent(dt, 0.85 / k)


## 배기: 총열 증기 · 위 탱크 증기 · 웅크린 약점 자세
func _vent(dt: float, dur: float) -> void:
	weak = true
	rig.spin = 0.0
	_w("heat", 0.0, 1.2)
	_w("crouch", 0.4, 8.0)
	_w("gun_aim", 0.2, 6.0)
	rig.pose = {"torso": Vector3(-0.3, 0, 0.05), "upperarm_l": Vector3(-0.3, 0, 0), "upperarm_r": Vector3(-0.15, 0, 0.1), "forearm_r": Vector3(0.3, 0, 0)}
	_fx_t -= dt
	if _fx_t <= 0.0:
		_fx_t = 0.06
		LancasterFX.steam(rig.at("pt_muzzle"), 0.6)
		LancasterFX.steam(rig.at("pt_vent_l") + Vector3(0, 0.2, 0), 0.9)
		LancasterFX.steam(rig.at("pt_vent_r") + Vector3(0, 0.2, 0), 0.9)
	if pt >= dur:
		_end_pattern(false)


func _muzzle_ray(d: Vector3) -> Vector3:
	var m := rig.at("pt_muzzle")
	var tgt := m + Vector3(d.x, 0, d.z).normalized() * 16.0
	tgt.y = Main.inst.player.global_position.y + 0.95
	return tgt


# ── 패턴: SWEEP SUPPRESSION ─────────────────────────────

func _p_sweep(dt: float, _p: Player, to: Vector3, dist: float) -> void:
	var k := tempo()
	var track := 0.5 / k
	var half := 0.95
	match ps.ph:
		"":
			var base := to / maxf(dist, 0.01)
			ps.side = 1.0 if randf() < 0.5 else -1.0
			ps.a0 = _yaw_of(base) - float(ps.side) * half
			ps.a1 = _yaw_of(base) + float(ps.side) * half
			ps.fan = LancasterFX.warn_fan(global_position, _yaw_of(base), half + 0.05, 15.0)
			Sfx.play("twind", 0.03, -5.0)
			_ph("track")
		"track":
			rig.plant = true
			_w("crouch", 0.35, 14.0)
			_w("gun_aim", 1.0, 16.0)
			rig.spin = lerpf(6.0, 44.0, pt / track)
			aim_yaw = float(ps.a0)
			rig.aim_point = _muzzle_ray(_dir_of(aim_yaw))
			rig.pose = {"torso": Vector3(-0.1, 0, 0), "upperarm_r": Vector3(0.3, 0, 0.4), "forearm_r": Vector3(0.6, 0, 0)}
			LancasterFX.aim_sight(sight, rig.at("pt_muzzle"), rig.at("pt_muzzle") + rig.barrel_dir() * 16.0, pt / track)
			if is_instance_valid(ps.fan):
				(ps.fan as MeshInstance3D).global_position = Vector3(global_position.x, 0.07, global_position.z)
			if pt >= track:
				sight.visible = false
				ps.shot_t = 0.0
				_ph("sweep")
		"sweep":
			var dur := 1.05 / sqrt(k)
			var e := clampf(pt / dur, 0.0, 1.0)
			var s := e * e * (3.0 - 2.0 * e)
			aim_yaw = lerp_angle(float(ps.a0), float(ps.a1), s)
			var d := _dir_of(aim_yaw)
			rig.aim_point = _muzzle_ray(d)
			_w("gun_aim", 1.0, 40.0)
			rig.spin = 48.0
			# 휩쓰는 방향으로 미끄러진다
			var side := Vector3(-d.z, 0, d.x) * float(ps.side)
			want_vel = side * 4.2 * sqrt(size_k)
			rig.pose = {"torso": Vector3(-0.14, 0, -0.08 * float(ps.side)), "upperarm_r": Vector3(0.3, 0, 0.45), "forearm_r": Vector3(0.6, 0, 0)}
			LancasterFX.set_warn(ps.fan, e)
			if is_instance_valid(ps.fan):
				(ps.fan as MeshInstance3D).global_position = Vector3(global_position.x, 0.07, global_position.z)
			ps.shot_t = float(ps.shot_t) - dt
			while ps.shot_t <= 0.0:
				ps.shot_t = float(ps.shot_t) + 1.0 / 24.0
				_fire_round(d, 0.06)
			if pt >= dur:
				LancasterFX.clear_warn(ps.fan)
				ps.erase("fan")
				_ph("recover")
		"recover":
			rig.spin = 0.0
			_w("gun_aim", 0.5, 6.0)
			_fx_t -= dt
			if _fx_t <= 0.0:
				_fx_t = 0.08
				LancasterFX.smoke(rig.at("pt_muzzle"), 0.4)
			if pt >= 0.45 / k:
				_end_pattern(false)


# ── 패턴: CLAW CHAIN (근접 연속 패링) ───────────────────
## 젠레스 존 제로 보스 식 (docs/lancaster-parry-research.md): 크게 젖히는 준비동작 → 멈칫 → 금빛 섬광 → 아주 빠른 일격.
## 패링해도 튕겨 났다가 짧은 재장전 뒤 바로 다음 타. 마지막 타까지 받아 내야 크게 무너진다. 맞으면 2 피해 + 날아감.
const STRIKE_DMG := 2
const STRIKE_MAX_SPEED := 80.0
const REACH := {"thrust": 2.3, "smash": 2.5, "swipe": 2.8}
const SLUG_T := 0.3              ## 섬광 → 중탄이 닿기까지 (보스 전용, 공통 Parry.TRAVEL 0.5 보다 빠르다)


## 섬광 → 집게가 닿기까지 (공통 Parry.TRAVEL 0.5 보다 빠르다)
func _strike_t() -> float:
	return 0.26 if phase >= 2 else 0.3


func _windup_t() -> float:
	return maxf(0.7, (0.85 if phase >= 2 else 1.0) / sqrt(tempo()))


func _rewind_t() -> float:
	return maxf(0.26, (0.34 if phase >= 2 else 0.42) / sqrt(tempo()))


func _p_claw(dt: float, p: Player, to: Vector3, dist: float) -> void:
	var k := tempo()
	var dir: Vector3 = ps.get("dir", to / maxf(dist, 0.01))
	match ps.ph:
		"":
			ps.n = 0
			ps.total = 2 if phase == 1 else randi_range(3, 4)
			var kinds := ["thrust"]
			var pool := ["smash", "swipe", "thrust"]
			for i in int(ps.total) - 1:
				var c: String = pool[randi() % pool.size()]
				while c == kinds[-1]:
					c = pool[randi() % pool.size()]
				kinds.append(c)
			ps.kinds = kinds
			ps.slug_finish = phase >= 2 and SETS[set_i].list.has("slug") and randf() < 0.55
			ps.dir = to / maxf(dist, 0.01)
			ps.ring = LancasterFX.warn_disc(global_position, 4.2 * size_k, ParryFX.GOLD)
			Sfx.play("echarge", 0.03, -1.0)
			_snd_cue("rev", 0.8, -2.0)
			_ph("windup")
		"windup", "rewind":
			var big: bool = ps.ph == "windup"
			var dur := _windup_t() if big else _rewind_t()
			var e := clampf(pt / dur, 0.0, 1.0)
			if e < 0.8:
				ps.dir = (dir.slerp(to / maxf(dist, 0.01), 1.0 - exp(-12.0 * dt))).normalized()
			aim_yaw = _yaw_of(ps.dir)
			_charge_anim(dt, e, big, String(ps.kinds[int(ps.n)]))
			if pt >= dur:
				_alert_strike(p)
		"hold":
			ps.hold = float(ps.hold) - dt
			_strike_pose(String(ps.kind))
			aim_yaw = _yaw_of(dir)
			if ps.hold <= 0.0:
				_launch_strike()
		"strike":
			_strike(dt, p, dir, dist)
		"after":
			ps.after = float(ps.after) - dt
			if ps.has("recoil"):
				# 패링된 스윙이 다 뻗은 다음 프레임에 튕겨 난다
				ps.recoil = float(ps.recoil) - dt
				if ps.recoil <= 0.0:
					var rd: Vector3 = ps.recoil_dir
					ps.erase("recoil")
					vel = rd * 9.0
					rig.kick("torso", Vector3(4.0, randf_range(-2, 2), 0))
					rig.kick("upperarm_r", Vector3(-7.0, 0, 3.0))
					_sq = 0.8
			elif not rig.swinging():
				_w("claw", 0.5, 10.0)
				_w("crouch", 0.5, 12.0)
			if ps.after <= 0.0:
				if int(ps.n) < int(ps.total):
					_ph("rewind")
					rig.stiff = 420.0
					LancasterFX.impact_star(rig.at("pt_claw"), 0.6)
					_snd_cue("rev", 1.1, -3.0)
				elif bool(ps.get("slug_finish", false)):
					# 2페이즈 콤보: 집게 연타 끝을 중탄으로 마무리
					pat = "slug"
					ps = {"ph": "", "combo": true}
					pt = 0.0
				else:
					_ph("recover")
		"recover":
			_w("claw", 0.3, 6.0)
			_w("crouch", 0.3, 6.0)
			rig.pose = {"torso": Vector3(-0.1, 0.15, 0), "upperarm_r": Vector3(0.3, 0, 0.25), "forearm_r": Vector3(0.4, 0, 0)}
			if pt >= 0.6 / k:
				_end_pattern(false)


## 준비동작: 눈이 번쩍 → 몸을 크게 비틀어 집게를 치켜듦 · 깊게 웅크림 · 분사구 푸푸 · 금빛 입자가 집게로 · 금빛 원이 조여듦 → 끝에 멈칫
func _charge_anim(dt: float, e: float, big: bool, kind: String) -> void:
	# 흰 발광은 자세가 읽힌 뒤 마지막 구간에만 (처음부터 덮으면 몸이 하얀 덩어리로 보여 자세가 안 읽힌다)
	windup_k = smoothstep(0.6 if big else 0.4, 0.92, e)
	var ramp := smoothstep(0.0, 0.55 if big else 0.35, e)
	var pose := _cock_pose(kind)
	var out := {}
	for key: String in pose:
		out[key] = (pose[key] as Vector3) * ramp
	# 마지막 구간: 그 자세로 멈칫하며 부들부들
	var freeze := smoothstep(0.84, 0.9, e)
	if freeze > 0.0:
		out.torso = (out.get("torso", Vector3.ZERO) as Vector3) + Vector3(sin(t * 83.0), sin(t * 71.0), sin(t * 97.0)) * 0.035 * freeze
	rig.pose = out
	rig.stiff = 260.0 if big else 520.0
	_w("crouch", 0.85 * ramp, 16.0)
	_w("lean", -0.22 * ramp, 10.0)
	_w("claw", 1.0, 14.0)
	_w("gun_aim", 0.0, 8.0)
	_w("jet", 0.3 + 0.5 * e, 14.0)
	want_vel = -(ps.dir as Vector3) * 2.5 * (1.0 - e) if big else Vector3.ZERO
	# 눈 번쩍 (시작)
	if big and e < 0.12:
		_w("eye_on", 1.0, 60.0)
		_w("rage", 1.0 if fmod(t * 18.0, 1.0) < 0.5 else float(_cur.rage), 60.0)
	_fx_t -= dt
	if _fx_t <= 0.0:
		_fx_t = lerpf(0.06, 0.018, e)
		var c := rig.at("pt_claw")
		var r := (1.8 * (1.0 - e) + 0.25) * size_k
		var d := Vector3(randf_range(-1, 1), randf_range(-0.6, 1), randf_range(-1, 1)).normalized()
		FX.flash(c + d * r, ParryFX.GOLD if randf() < 0.7 else Color.WHITE, 0.22 + 0.2 * e, 0.09)
		if randf() < 0.35:
			FX.puffs(rig.at("pt_jet_l" if randf() < 0.5 else "pt_jet_r"), 1, LancasterFX.SMOKE_C, 0.1, 0.35, 0.45)
	if ps.has("ring") and is_instance_valid(ps.ring):
		var ring: MeshInstance3D = ps.ring
		var rr := lerpf(4.2, 1.6, e) * size_k
		ring.global_position = Vector3(global_position.x, Main.gy(global_position) + 0.06, global_position.z)
		ring.scale = Vector3(rr * 2.0, 1, rr * 2.0)
		LancasterFX.set_warn(ring, e)


## 치켜든 자세 (타격 종류별). 관절 → 회전
func _cock_pose(kind: String) -> Dictionary:
	match kind:
		"smash":
			return {"torso": Vector3(0.38, 0.25, 0), "shoulder_r": Vector3(0.4, 0, 0.2), "upperarm_r": Vector3(2.9, 0, 0.3), "forearm_r": Vector3(1.6, 0, 0), "hand_r": Vector3(0.5, 0, 0), "upperarm_l": Vector3(-0.5, 0, -0.6)}
		"swipe":
			return {"torso": Vector3(0.1, -1.25, 0.08), "shoulder_r": Vector3(-0.2, 0, 0.35), "upperarm_r": Vector3(0.7, 0, 1.45), "forearm_r": Vector3(0.5, 0, 0), "hand_r": Vector3(0.2, 0, 0), "upperarm_l": Vector3(0.6, 0, -0.4)}
	return {"torso": Vector3(0.22, -1.0, 0.1), "shoulder_r": Vector3(-0.3, 0, 0.3), "upperarm_r": Vector3(-0.95, 0, 0.9), "forearm_r": Vector3(1.6, 0, 0), "hand_r": Vector3(0.6, 0, 0), "upperarm_l": Vector3(0.55, 0, -0.5)}


## 돌진 중 자세: 감긴 그대로 몸만 앞으로 기울여 날아든다 (스윙은 닿기 직전 몇 프레임에 몰아서)
func _strike_pose(kind: String) -> void:
	if rig.swinging() or ps.has("swung"):
		return
	rig.stiff = 600.0
	rig.damp = 26.0
	_w("claw", 1.0, 40.0)
	var pose := _cock_pose(kind)
	var torso: Vector3 = pose.get("torso", Vector3.ZERO)
	pose.torso = torso + Vector3(-0.35, 0, 0)
	rig.pose = pose
	_w("crouch", 0.45 if kind != "smash" else 0.25, 30.0)


## 임팩트 자세 (스윙이 끝나는 자세). 컨셉 시트: 찌르기 = 쭉 뻗음, 내려찍기 = 바닥까지, 휘둘러 베기 = 반대편까지 돌아감
func _impact_pose(kind: String) -> Dictionary:
	match kind:
		"smash":
			return {"torso": Vector3(-0.85, 0.15, 0), "shoulder_r": Vector3(0.35, 0, 0.1), "upperarm_r": Vector3(0.4, 0, 0.15), "forearm_r": Vector3(-0.2, 0, 0), "hand_r": Vector3(-0.35, 0, 0), "upperarm_l": Vector3(-0.6, 0, -0.7)}
		"swipe":
			return {"torso": Vector3(-0.25, 1.35, -0.12), "shoulder_r": Vector3(0.3, 0, 0.1), "upperarm_r": Vector3(1.0, 0, 0.2), "forearm_r": Vector3(0.15, 0, 0), "hand_r": Vector3(-0.2, 0, 0), "upperarm_l": Vector3(0.1, 0, -0.75)}
	return {"torso": Vector3(-0.55, 0.9, 0), "shoulder_r": Vector3(0.4, 0, 0), "upperarm_r": Vector3(1.7, 0, 0.05), "forearm_r": Vector3(-0.05, 0, 0), "hand_r": Vector3(-0.25, 0, 0), "upperarm_l": Vector3(-0.55, 0, -0.35)}


const SWING_FRAMES := 3          ## 임팩트 스윙 길이 (60fps 프레임) — 광선검 콤보 스윙(1~4프레임)과 같은 결
const SWING_LEAD := 0.05         ## 닿기 이만큼 전에 스윙을 시작해 정확히 닿는 순간 다 뻗는다


## 몇 프레임 만에 폭발적으로 휘두른다: 관절 expo 구동 · 금빛 잔상 호 · 늘였다 찌그러뜨리기 · 바람 소리
func _swing_now() -> void:
	if ps.has("swung"):
		return
	ps.swung = true
	_end_warn()                  # 금빛 전신 덮개는 섬광 순간만 — 스윙 자세가 읽히게 걷는다 (판정 창은 그대로)
	var kind := String(ps.kind)
	rig.swing(_impact_pose(kind), SWING_FRAMES / 60.0, 0.4)
	_snapv("claw", 0.0 if kind != "swipe" else 0.2)
	if kind == "smash":
		_snapv("crouch", 1.0)
	_sq = -1.0
	_sq_v = 0.0
	var dir: Vector3 = ps.dir
	var sh := rig.node("shoulder_r").global_position
	var face := Basis.looking_at(dir, Vector3.UP)
	# 호 메시는 반지름 0.45~2.7 의 띠 → 크기 0.6~0.75 면 팔 길이(약 1.6~2m) 둘레를 긋는다
	match kind:
		"smash":
			LancasterFX.smear(sh, face * Basis(Vector3.FORWARD, PI * 0.5), 0.62 * size_k, 0.05, 0.14)
		"swipe":
			LancasterFX.smear(global_position + Vector3(0, 1.3 * size_k, 0), face * Basis(Vector3.FORWARD, -0.15), 0.78 * size_k, 0.05, 0.14)
		_:
			LancasterFX.smear(sh, face * Basis(Vector3.FORWARD, 1.25), 0.55 * size_k, 0.04, 0.12)
			LancasterFX.thrust_line(global_position + Vector3(0, 1.4 * size_k, 0) + dir * 1.4 * size_k, dir, 2.6 * size_k)
	var whoosh := Sfx.play("slash", 0.05, 2.0)
	if whoosh:
		whoosh.pitch_scale = 0.55
	Main.inst.kick(dir * 0.35)


func _gap(p: Player, reach := CLAW_REACH) -> float:
	return maxf(0.0, _to_player().length() - reach * size_k - p.hit_radius)


## 준비 끝: 금빛 섬광 → 정확히 _strike_t() 초 뒤에 닿도록 돌진 속도(또는 버티는 시간)를 정한다
func _alert_strike(p: Player) -> void:
	var kind := String(ps.kinds[int(ps.n)])
	ps.kind = kind
	var to := _to_player()
	if to.length() > 0.1:
		ps.dir = to.normalized()
	var reach := float(REACH[kind])
	ps.reach = reach
	var gap := _gap(p, reach)
	var tt := _strike_t()
	var speed := clampf(gap / tt, 6.0, STRIKE_MAX_SPEED * sqrt(size_k))
	ps.speed = speed
	ps.hold = maxf(0.0, tt - gap / speed)
	ps.max = (gap + 2.5) / speed + float(ps.hold) + 0.06
	ps.erase("hit")
	ps.erase("swung")
	windup_k = 0.0
	_warn(rig.at("pt_claw"), "melee")
	Sfx.play("pcue", 0.02, 2.0)
	if Parry.inst:
		Parry.inst.register(self)
	if ps.has("ring"):
		LancasterFX.clear_warn(ps.ring)
		ps.erase("ring")
	if float(ps.hold) > 0.0:
		_ph("hold")
	else:
		_launch_strike()


func _launch_strike() -> void:
	_ph("strike")
	_strike_pose(String(ps.kind))
	rig.snap()
	_ghost_t = 0.0
	Sfx.play("launch", 0.05, 0.0)
	LancasterFX.jet_burst(-3.0, 0.85, 0.3)
	FX.shockwave(global_position + Vector3(0, 0.1, 0), ParryFX.GOLD, 3.5 * size_k, 0.2, 0.06)
	LancasterFX.dust_ring(global_position, 1.0 * size_k, 8)


func _strike(dt: float, p: Player, dir: Vector3, dist: float) -> void:
	var kind := String(ps.kind)
	var span := maxf(float(ps.max) - float(ps.get("hold", 0.0)), 0.05)
	var k := clampf(pt / span, 0.0, 1.0)
	_strike_pose(kind)
	aim_yaw = _yaw_of(dir)
	vel = dir * float(ps.speed)
	want_vel = vel
	_w("jet", 1.0, 60.0)
	_w("air", 0.6, 40.0)
	if kind == "smash":
		lift_y = sin(PI * minf(k * 1.4, 1.0)) * 0.9 * size_k
	_ghost_t -= dt
	if _ghost_t <= 0.0 and not ps.has("swung"):
		_ghost_t = 0.045
		FX.afterimage(visual, Color(1.0, 0.75, 0.35, 0.2), 0.12)
	var reach := float(ps.reach) * size_k
	if not ps.has("swung") and (dist - reach - p.hit_radius) / maxf(float(ps.speed), 0.1) <= SWING_LEAD:
		_swing_now()
	if not ps.has("hit") and p.alive and dist < reach + p.hit_radius:
		_strike_contact(p, dir)
		return
	if pt >= float(ps.max) or Main.inst.is_blocked(global_position + dir * (radius + 0.4)):
		_swing_now()
		_strike_end()


## 닿음: 패링되지 않았다 → 크게 맞는다 (2 피해 · 날아감 · 짧은 경직)
func _strike_contact(p: Player, dir: Vector3) -> void:
	ps.hit = true
	_swing_now()
	var c := rig.at("pt_claw") if String(ps.kind) != "smash" else rig.at("pt_spike")
	if p.take_hit(c):
		for i in STRIKE_DMG - 1:
			if p.hp > 0:
				p.hp -= 1
		p.velocity += dir * 15.0 + Vector3.UP * 2.0
		if p.hp <= 0:
			p.die(dir)
		else:
			p.stagger(0.32)
		LancasterFX.impact_star(c, 1.8)
		Main.inst.shake(0.85)
		Main.inst.hitstop(0.09)
		Sfx.play("boom", 0.05, -2.0)
	else:
		FX.sparks(c, 10, [Color.WHITE, Color(1.0, 0.7, 0.3)], 6.0, 0.3, -12.0, 0.06)
	Sfx.play("clank", 0.05, 2.0)
	if String(ps.kind) == "smash":
		GroundBreak.burst(Vector3(c.x, 0, c.z), 0.7, dir)
		FX.shockwave(Vector3(c.x, Main.gy(c) + 0.08, c.z), Color(1.0, 0.7, 0.35), 4.0 * size_k, 0.25, 0.1)
	_strike_end()


func _strike_end() -> void:
	_end_warn()
	if Parry.inst:
		Parry.inst.unregister(self)
	lift_y = 0.0
	vel = (ps.dir as Vector3) * 3.0
	ps.n = int(ps.n) + 1
	ps.after = (0.16 if int(ps.n) < int(ps.total) else 0.3) + SWING_FRAMES / 60.0
	_ph("after")


func parry_eta() -> float:
	var p := Main.inst.player
	if not p.alive or not alive or st != St.FIGHT or pat != "claw":
		return INF
	var gap := _gap(p, float(ps.get("reach", CLAW_REACH)))
	match ps.get("ph", ""):
		"hold":
			return float(ps.hold) + gap / float(ps.speed)
		"strike":
			if ps.has("hit") or _to_player().dot(ps.dir) < -0.3:
				return INF
			return gap / float(ps.speed)
	return INF


func parry_committed() -> bool:
	if pat == "claw":
		return ps.get("ph", "") in ["windup", "rewind", "hold", "strike", "after"]
	if pat == "slug":
		return ps.get("ph", "") in ["windup", "after"]
	return false


func parry_kind() -> String:
	return "melee"


func parry_point() -> Vector3:
	return _chest().lerp(rig.at("pt_claw"), 0.5)


func parry_source() -> Node3D:
	return self


func parry_window_open() -> void:
	ParryFX.cue(rig.at("pt_claw"))


## 패링당함: 중간 타면 튕겨 났다 곧바로 다음 타, 마지막 타면 크게 무너진다
func parry_hit(p: Player) -> void:
	var d := global_position - p.global_position
	d.y = 0
	d = d.normalized()
	if pat == "claw" and int(ps.get("n", 0)) + 1 < int(ps.get("total", 1)):
		_swing_now()
		_end_warn()
		if Parry.inst:
			Parry.inst.unregister(self)
		lift_y = 0.0
		ps.n = int(ps.n) + 1
		ps.after = 0.2 + SWING_FRAMES / 60.0
		ps.recoil = SWING_FRAMES / 60.0
		ps.recoil_dir = d
		_ph("after")
		vel = Vector3.ZERO
		LancasterFX.impact_star(rig.at("pt_claw"), 1.2)
		Sfx.play("clank", 0.05, 2.0)
		take_hit(3, d, rig.at("pt_claw"), "deflect")
		return
	_swing_now()
	_end_pattern(true)
	stagger(d, 2.4)
	take_hit(6, d, rig.at("pt_claw"), "parry")


# ── 패턴: HEAVY SLUG (원거리 연속 패링) ─────────────────

func _p_slug(dt: float, _p: Player, to: Vector3, dist: float) -> void:
	var k := tempo()
	match ps.ph:
		"":
			ps.n = 0
			ps.total = (2 if phase == 1 else 4) if not bool(ps.get("combo", false)) else 2
			Sfx.play("echarge", 0.03, -2.0)
			_ph("windup")
		"windup":
			var first: bool = int(ps.n) == 0 and not bool(ps.get("combo", false))
			var dur := maxf(0.6, 0.9 / sqrt(k)) if first else maxf(0.28, 0.38 / sqrt(k))
			var e := clampf(pt / dur, 0.0, 1.0)
			windup_k = smoothstep(0.6 if first else 0.35, 0.92, e)
			rig.plant = true
			rig.spin = 0.0
			aim_yaw = _yaw_of(to)
			rig.aim_point = _chest()
			# 총을 높이 치켜들었다(달아오름 · 증기) 끝에 플레이어 쪽으로 내려 겨눈다
			var lower := smoothstep(0.55, 0.85, e) if first else smoothstep(0.2, 0.7, e)
			_w("gun_aim", lower, 30.0)
			_w("heat", 0.4 + 0.6 * e, 12.0)
			_w("crouch", 0.55, 14.0)
			_w("lean", -0.2 * (1.0 - lower), 10.0)
			var up := 1.0 - lower
			var pose := {"torso": Vector3(0.3 * up, 0.35 * up, 0), "shoulder_l": Vector3(0.3 * up, 0, 0), "upperarm_l": Vector3(1.5 * up, 0, -0.2 * up), "upperarm_r": Vector3(0.3, 0, 0.5), "forearm_r": Vector3(0.9, 0, 0)}
			if e > 0.86:
				pose.torso += Vector3(sin(t * 83.0), sin(t * 71.0), 0) * 0.03
			rig.pose = pose
			rig.stiff = 280.0 if first else 520.0
			_fx_t -= dt
			if _fx_t <= 0.0:
				_fx_t = lerpf(0.06, 0.02, e)
				var m := rig.at("pt_muzzle")
				FX.flash(m + Vector3(randf_range(-0.5, 0.5), randf_range(-0.3, 0.5), randf_range(-0.5, 0.5)) * (1.0 - e + 0.3), ParryFX.GOLD, 0.25 + 0.2 * e, 0.1)
				if first and randf() < 0.4:
					LancasterFX.steam(rig.at("pt_vent_l" if randf() < 0.5 else "pt_vent_r") + Vector3(0, 0.2, 0), 0.5)
			if pt >= dur:
				_fire_slug(to, dist)
				ps.n = int(ps.n) + 1
				_ph("after")
		"after":
			rig.plant = true
			_w("gun_aim", 1.0, 10.0)
			_w("crouch", 0.35, 10.0)
			rig.pose = {"torso": Vector3(0.3, 0, 0), "upperarm_l": Vector3(0.35, 0, 0), "upperarm_r": Vector3(0.25, 0, 0.35), "forearm_r": Vector3(0.8, 0, 0)}
			if pt >= 0.12:
				if int(ps.n) < int(ps.total):
					_ph("windup")
				elif pt >= 0.5 / k:
					_end_pattern(false)


func _fire_slug(to: Vector3, dist: float) -> void:
	windup_k = 0.0
	var m := rig.at("pt_muzzle")
	var d := to / maxf(dist, 0.01)
	var p := Main.inst.player
	var from := Vector3(m.x, p.global_position.y + 0.95, m.z) + d * 0.3
	var orb := ParryOrb.make(from, d, self)
	var gap := Vector2(p.global_position.x - from.x, p.global_position.z - from.z).length() - (p.hit_radius + ParryOrb.RADIUS)
	orb.speed = maxf(gap / (SLUG_T if phase == 1 else 0.26), 14.0)
	orb.vel = d * orb.speed
	Main.inst.bullets.add_child(orb)
	ParryFX.warn(m, "ranged")
	Sfx.play("pcue", 0.02, 2.0)
	parry_flash()
	GunFX.muzzle(m, d, 3.2 * size_k, true)
	rig.kick("upperarm_l", Vector3(-7.0, 0, 0))
	rig.kick("torso", Vector3(2.4, 0, 0))
	_cur.heat = 1.0
	Main.inst.shake(0.35)
	Sfx.play("launch", 0.04, 0.0)
	var s := Sfx.play("boom", 0.05, -8.0)
	if s:
		s.pitch_scale = 1.4


func _snd_cue(id: String, pitch: float, vol: float) -> void:
	var s := Sfx.play(id, 0.03, vol)
	if s:
		s.pitch_scale = pitch


# ── 패턴: PILE-DRIVER SPIKE ─────────────────────────────

func _p_spike(dt: float, p: Player, _to: Vector3, _dist: float) -> void:
	var k := tempo()
	var windup := 0.5 / k
	var hop := 0.58
	match ps.ph:
		"":
			var tgt := p.global_position + Vector3(p.velocity.x, 0, p.velocity.z) * 0.35
			var from := global_position
			var span := tgt - from
			span.y = 0
			# 가시는 몸 앞 1.3m 에 박힌다 → 착지 자리는 그만큼 앞에서 멈춘다
			var fwd := span.normalized() if span.length() > 0.1 else _dir_of(face_yaw)
			var land := from + fwd * clampf(span.length() - 1.3 * size_k, 0.0, 10.0)
			land = _clamp(land)
			ps.from = from
			ps.land = land
			ps.dir = fwd
			ps.hit_at = land + fwd * 1.3 * size_k
			ps.warn = LancasterFX.warn_disc(ps.hit_at, SPIKE_R * size_k, LancasterFX.DANGER)
			Sfx.play("rev", 0.05, -2.0)
			_ph("windup")
		"windup":
			var e := pt / windup
			aim_yaw = _yaw_of(ps.dir)
			_w("crouch", 0.75, 12.0)
			_w("jet", 0.5 * e, 10.0)
			_w("lean", -0.15, 8.0)
			rig.pose = {"torso": Vector3(0.25, 0.25, 0), "shoulder_r": Vector3(0.3, 0, 0.1), "upperarm_r": Vector3(2.5, 0, 0.35), "forearm_r": Vector3(1.4, 0, 0), "upperarm_l": Vector3(-0.3, 0, -0.35)}
			LancasterFX.set_warn(ps.warn, e * 0.45)
			if pt >= windup:
				LancasterFX.jet_burst(-2.0, 0.8, 0.5)
				LancasterFX.dust_ring(global_position, 1.2 * size_k, 10)
				_ph("hop")
		"hop":
			var e := clampf(pt / hop, 0.0, 1.0)
			var pos := (ps.from as Vector3).lerp(ps.land, e * e * (3.0 - 2.0 * e))
			global_position = _clamp(pos)
			vel = Vector3.ZERO
			lift_y = sin(PI * e) * 2.6 * size_k
			aim_yaw = _yaw_of(ps.dir)
			face_yaw = aim_yaw
			_w("air", 1.0 if e < 0.85 else 0.0, 14.0)
			_w("jet", 1.0, 30.0)
			_w("crouch", 0.1, 10.0)
			var down := smoothstep(0.55, 1.0, e)
			rig.stiff = 260.0
			rig.pose = {
				"torso": Vector3(lerpf(0.3, -0.55, down), 0.25 * (1.0 - down), 0), "shoulder_r": Vector3(0.3, 0, 0.1),
				"upperarm_r": Vector3(lerpf(2.7, 0.8, down), 0, 0.2), "forearm_r": Vector3(lerpf(1.4, -0.1, down), 0, 0),
				"upperarm_l": Vector3(-0.5, 0, -0.5),
			}
			LancasterFX.set_warn(ps.warn, 0.45 + 0.55 * e)
			_ghost_t -= dt
			if _ghost_t <= 0.0:
				_ghost_t = 0.04
				FX.afterimage(visual, Color(1.0, 0.6, 0.3, 0.25), 0.16)
			if e >= 1.0:
				_slam()
		"stuck":
			weak = true
			_w("crouch", 1.0, 30.0)
			_w("lean", 0.0, 6.0)
			rig.pose = {"torso": Vector3(-0.55, 0, 0), "upperarm_r": Vector3(0.8, 0, 0.2), "forearm_r": Vector3(-0.1, 0, 0), "upperarm_l": Vector3(-0.4, 0, -0.5)}
			_fx_t -= dt
			if _fx_t <= 0.0:
				_fx_t = 0.1
				FX.sparks(rig.at("pt_spike"), 4, [Color.WHITE, Color(1.0, 0.7, 0.3)], 4.0, 0.25, -10.0, 0.05)
			if pt >= 0.8 / k:
				FX.sparks(rig.at("pt_spike"), 14, [Color(0.45, 0.43, 0.5), Color(0.3, 0.28, 0.34), Color(1.0, 0.7, 0.3)], 7.0, 0.6, -18.0, 0.12)
				LancasterFX.dust_ring(rig.at("pt_spike"), 0.6, 6)
				Sfx.play("clank", 0.06, -4.0)
				_ph("pull")
		"pull":
			_w("crouch", 0.3, 8.0)
			rig.pose = {"torso": Vector3(0.1, 0, 0), "upperarm_r": Vector3(1.4, 0, 0.3), "forearm_r": Vector3(0.8, 0, 0)}
			if pt >= 0.42 / k:
				_end_pattern(false)


func _slam() -> void:
	lift_y = 0.0
	_snapv("air", 0.0)
	_snapv("crouch", 1.0)
	rig.pose = {"torso": Vector3(-0.6, 0, 0), "upperarm_r": Vector3(0.7, 0, 0.2), "forearm_r": Vector3(-0.15, 0, 0), "upperarm_l": Vector3(-0.4, 0, -0.5)}
	rig.snap()
	rig.reset_feet()
	var at: Vector3 = ps.hit_at
	at = Vector3(at.x, Main.gy(at), at.z)
	LancasterFX.clear_warn(ps.warn)
	ps.erase("warn")
	LancasterFX.impact_star(rig.at("pt_spike"), 1.6)
	GroundBreak.burst(at, 1.25, ps.dir)
	FX.shockwave(at + Vector3(0, 0.08, 0), Color(1.0, 0.65, 0.3), SPIKE_R * 2.4 * size_k, 0.35, 0.14)
	FX.shockwave(at + Vector3(0, 0.08, 0), Color(1.0, 0.95, 0.85), SPIKE_R * 1.4 * size_k, 0.2, 0.08)
	LancasterFX.dust_ring(at, 1.6 * size_k, 14)
	Distortion.burst(at + Vector3(0, 0.6, 0), 5.0 * size_k, 0.45, 1.3, 0.3)
	Main.inst.shake(0.95)
	Main.inst.hitstop(0.05)
	Main.inst.kick((ps.dir as Vector3) * 0.6)
	Sfx.play("boom", 0.05, 1.0)
	var thud := Sfx.play("land", 0.05, 0.0)
	if thud:
		thud.pitch_scale = 0.5
	var p := Main.inst.player
	if p.alive:
		var d := Vector2(p.global_position.x - at.x, p.global_position.z - at.z).length()
		if d < SPIKE_R * size_k + p.hit_radius * 0.5:
			p.take_hit(at)
	_ph("stuck")


# ── 패턴: HEAVY STOMP ───────────────────────────────────

func _p_stomp(dt: float, p: Player, to: Vector3, _dist: float) -> void:
	var k := tempo()
	var lift := 0.55 / k
	match ps.ph:
		"":
			ps.warn = LancasterFX.warn_disc(global_position, STOMP_R * size_k, LancasterFX.DANGER)
			Sfx.play("hrise", 0.05, -6.0)
			_ph("lift")
		"lift":
			var e := pt / lift
			rig.plant = true
			_w("stomp", 1.0, 9.0)
			_w("crouch", 0.15, 8.0)
			rig.pose = {"torso": Vector3(0.18, 0, 0.12), "upperarm_l": Vector3(0.25, 0, -0.55), "upperarm_r": Vector3(0.25, 0, 0.65), "forearm_r": Vector3(0.6, 0, 0)}
			aim_yaw = _yaw_of(to)
			LancasterFX.set_warn(ps.warn, e)
			if is_instance_valid(ps.warn):
				(ps.warn as MeshInstance3D).global_position = Vector3(global_position.x, 0.06, global_position.z)
			if pt >= lift:
				_stomp_impact()
		"wave":
			rig.plant = true
			_w("crouch", 0.8, 30.0)
			rig.pose = {"torso": Vector3(-0.35, 0, 0), "upperarm_l": Vector3(-0.2, 0, -0.35), "upperarm_r": Vector3(-0.2, 0, 0.4)}
			var e := clampf(pt / 0.34, 0.0, 1.0)
			var r := lerpf(0.8, STOMP_R * size_k, e)
			var c: Vector3 = ps.c
			if p.alive and not ps.has("hit"):
				var d := Vector2(p.global_position.x - c.x, p.global_position.z - c.z).length()
				var grounded := p.global_position.y - Main.gy(p.global_position) < 0.35
				if grounded and d > r - 0.9 and d < r + 0.35:
					if p.take_hit(c):
						ps.hit = true
						p.velocity += (p.global_position - c).normalized() * 8.0
			_fx_t -= dt
			if _fx_t <= 0.0:
				_fx_t = 0.07
				LancasterFX.dust_ring(c, r, int(6 + r))
			if e >= 1.0:
				_ph("settle")
		"settle":
			_w("crouch", 0.25, 6.0)
			if pt >= 0.5 / k:
				_end_pattern(false)


func _stomp_impact() -> void:
	_snapv("stomp", 0.0)
	_snapv("crouch", 0.9)
	rig.snap()
	var c := global_position
	ps.c = c
	LancasterFX.clear_warn(ps.warn)
	ps.erase("warn")
	var foot := rig.at("pt_foot_r")
	FX.shockwave(c + Vector3(0, 0.1, 0), Color(1.0, 0.92, 0.8), STOMP_R * 2.0 * size_k, 0.34, 0.2)
	FX.shockwave(c + Vector3(0, 0.1, 0), Color(1.0, 0.6, 0.3), STOMP_R * 1.2 * size_k, 0.25, 0.1)
	GroundBreak.burst(Vector3(foot.x, 0, foot.z), 1.0, Vector3.ZERO)
	Distortion.burst(c + Vector3(0, 0.4, 0), 6.0 * size_k, 0.4, 1.2, 0.2)
	Main.inst.shake(0.85)
	Main.inst.hitstop(0.04)
	Sfx.play("boom", 0.05, 0.0)
	var thud := Sfx.play("land", 0.05, 2.0)
	if thud:
		thud.pitch_scale = 0.45
	_ph("wave")


# ── 패턴: SECURITY POD BARRAGE ──────────────────────────

func _p_pods(dt: float, p: Player, to: Vector3, dist: float) -> void:
	if ps.ph == "":
		_pods_start()
		_ph("cover")
	_neutral(dt, p, to, dist)
	pin_left = 0
	if pt >= 1.9 / tempo():
		_end_pattern(false)


func _pods_start() -> void:
	if pods.st != "":
		return
	var p := Main.inst.player
	var n := 3 if phase == 1 else 5
	var base := p.global_position + Vector3(p.velocity.x, 0, p.velocity.z) * 0.6
	var targets: Array = [base]
	for i in n - 1:
		var a := randf() * TAU
		var q := base + Vector3(cos(a), 0, sin(a)) * randf_range(2.0, 3.8)
		targets.append(Main.inst.push_out(q, 0.5))
	var warns: Array = []
	for q: Vector3 in targets:
		warns.append(LancasterFX.warn_disc(q, MORTAR_R, LancasterFX.DANGER))
	pods = {"st": "lock", "t": 0.0, "targets": targets, "warns": warns, "i": 0, "fire_t": 0.0, "auto": pods.get("auto", 6.0)}
	Sfx.play("lock", 0.03, -2.0)


func _pods_stop() -> void:
	for w in pods.get("warns", []):
		if is_instance_valid(w):
			(w as Node).queue_free()
	pods.st = ""
	pods.warns = []
	if is_instance_valid(_pod_lines):
		_pod_lines.mesh = null


func _pods_update(dt: float) -> void:
	if pods.st == "":
		return
	if not alive:
		_pods_stop()
		return
	pods.t = float(pods.t) + dt
	rig.pods_spin = 14.0
	_w("pods_up", 1.0, 10.0)
	match pods.st:
		"lock":
			var lock := 0.7 / sqrt(tempo())
			for w in pods.warns:
				LancasterFX.set_warn(w, 0.15 * float(pods.t) / lock)
			_draw_pod_lines(1.0 - float(pods.t) / lock)
			if pods.t >= lock:
				pods.st = "fire"
				pods.t = 0.0
				_pod_lines.mesh = null
		"fire":
			pods.fire_t = float(pods.fire_t) - dt
			if pods.fire_t <= 0.0 and int(pods.i) < (pods.targets as Array).size():
				pods.fire_t = 0.13
				var i := int(pods.i)
				var s := "l" if i % 2 == 0 else "r"
				var from := rig.at("pt_lens_" + s)
				LancasterFX.mortar(from, pods.targets[i], 1.0, MORTAR_R, pods.warns[i])
				FX.flash(from, Color(1.0, 0.7, 0.3), 0.7, 0.07)
				FX.puffs(from, 2, LancasterFX.SMOKE_C, 0.15, 0.35, 0.6)
				var snd := Sfx.play("tshot", 0.05, -4.0)
				if snd:
					snd.pitch_scale = 0.6
				pods.i = i + 1
			if int(pods.i) >= (pods.targets as Array).size():
				pods.st = "reset"
				pods.t = 0.0
				pods.warns = []      # 박격탄이 넘겨받아 지운다
		"reset":
			rig.pods_spin = 4.0
			_w("pods_up", 0.0, 4.0)
			if pods.t >= 0.6:
				pods.st = ""


## 포드 렌즈에서 표적 원까지 붉은 점선
func _draw_pod_lines(k: float) -> void:
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var a := clampf(k, 0.0, 1.0)
	for i in (pods.targets as Array).size():
		var from := rig.at("pt_lens_" + ("l" if i % 2 == 0 else "r"))
		var to: Vector3 = pods.targets[i]
		to.y = Main.gy(to) + 0.08
		var segs := 14
		for s in segs:
			if s % 2 == 1:
				continue
			var off := fmod(t * 3.0, 2.0) / segs
			im.surface_set_color(Color(1.0, 0.2, 0.12) * 2.0 * a)
			im.surface_add_vertex(from.lerp(to, clampf(float(s) / segs + off, 0.0, 1.0)))
			im.surface_add_vertex(from.lerp(to, clampf(float(s + 1) / segs + off, 0.0, 1.0)))
	im.surface_end()
	_pod_lines.mesh = im


# ── 광폭화 (2페이즈) ────────────────────────────────────

func _begin_transition() -> void:
	_end_pattern(true)
	_pods_stop()
	dash_t = 0.0
	st = St.TRANSITION
	st_t = 0.0
	if is_instance_valid(stun_halo):
		stun_halo.queue_free()
	Sfx.play("powerdown", 0.03, -2.0)


func _transition(dt: float) -> void:
	var e := st_t
	rig.plant = true
	aim_yaw = _yaw_of(_to_player())
	_w("rage", smoothstep(0.2, 0.9, e), 30.0)
	_w("eye_on", 1.0 if e > 0.25 or fmod(e * 20.0, 1.0) < 0.5 else 0.2, 40.0)
	if e < 0.6:
		_w("crouch", 0.6, 10.0)
		rig.pose = {"torso": Vector3(-0.45, 0, 0), "upperarm_l": Vector3(-0.2, 0, -0.2), "upperarm_r": Vector3(-0.2, 0, 0.2)}
	else:
		_w("crouch", 0.1, 10.0)
		rig.pose = {"torso": Vector3(0.5, 0, 0), "upperarm_l": Vector3(0.45, 0, -0.7), "upperarm_r": Vector3(1.0, 0, 0.85), "forearm_r": Vector3(0.9, 0, 0)}
		rig.pods_spin = 18.0
		_w("pods_up", 1.0, 8.0)
		if not ps.has("roar"):
			ps.roar = true
			phase = 2
			_roar(1.0)
			if is_instance_valid(bar):
				bar.call("set_phase", 2)
			phase_changed.emit(2)
	_fx_t -= dt
	if _fx_t <= 0.0:
		_fx_t = 0.045
		LancasterFX.arc_lines(global_position + Vector3(0, 2.2 * size_k, 0), 1.3 * size_k, 3)
		LancasterFX.steam(rig.at("pt_vent_l") + Vector3(0, 0.2, 0), 1.2)
		LancasterFX.steam(rig.at("pt_vent_r") + Vector3(0, 0.2, 0), 1.2)
	if e >= 2.0:
		ps.clear()
		st = St.FIGHT
		st_t = 0.0
		rest = 0.3
		pods.auto = 2.5


# ── 경직 (패링 · 자기 중탄) ─────────────────────────────

func stagger(dir: Vector3, dur: float) -> void:
	if not alive or st != St.FIGHT and st != St.STAGGER:
		return
	_end_pattern(true)
	dash_t = 0.0
	st = St.STAGGER
	st_t = 0.0
	stagger_t = dur
	stagger_total = dur
	knock = Vector3(dir.x, 0, dir.z).normalized() * 7.0
	rig.hit(dir, 2.5)
	rig.kick("upperarm_r", Vector3(-6.0, 0, 3.0))
	rig.kick("upperarm_l", Vector3(-3.0, 0, -2.0))
	weak = true
	if not is_instance_valid(stun_halo):
		stun_halo = ParryFX.stun_halo(visual)
		stun_halo.position = Vector3(0, 4.1, 0)
		stun_halo.scale = Vector3.ONE * 1.6
	if MocoFX.on:
		var mf := MocoFX.get_inst()
		if mf:
			mf.status(self, "STUN!")
	LancasterFX.impact_star(rig.at("pt_chest"), 1.2)
	FX.sparks(rig.at("pt_chest"), 30, [Color.WHITE, ParryFX.HOT, ParryFX.GOLD], 10.0, 0.5, -12.0, 0.08)
	Sfx.play("clank", 0.05, 2.0)
	if is_instance_valid(bar):
		bar.set("weak", true)


func _stagger_tick(dt: float) -> void:
	stagger_t -= dt
	var k := clampf(stagger_t / stagger_total, 0.0, 1.0)
	vel = knock
	want_vel = knock
	knock = knock.move_toward(Vector3.ZERO, 14.0 * dt)
	_w("crouch", 0.45 + 0.2 * sin(t * 6.0), 10.0)
	_w("eye_on", 0.4 + 0.6 * float(fmod(t * 9.0, 1.0) < 0.6), 40.0)
	_w("claw", 0.6, 4.0)
	rig.stiff = 120.0
	rig.damp = 9.0
	rig.pose = {
		"torso": Vector3(0.35 * k + sin(t * 7.0) * 0.12, sin(t * 4.3) * 0.35 * k, sin(t * 8.6) * 0.18 * k),
		"upperarm_l": Vector3(-0.4, 0, -0.35 + sin(t * 5.0) * 0.2), "upperarm_r": Vector3(-0.3, 0, 0.45 + sin(t * 6.0) * 0.2),
		"forearm_r": Vector3(0.2, 0, 0),
	}
	if is_instance_valid(stun_halo):
		stun_halo.rotation.y += dt * 9.0
	_fx_t -= dt
	if _fx_t <= 0.0:
		_fx_t = randf_range(0.08, 0.15)
		var c := global_position + Vector3(randf_range(-1, 1) * size_k, randf_range(1.6, 3.2) * size_k, randf_range(-1, 1) * size_k)
		FX.sparks(c, 4, [Color.WHITE, ParryFX.GOLD], 5.0, 0.25, -10.0, 0.05)
		if randf() < 0.3:
			LancasterFX.arc_lines(c, 0.4, 2, Color(0.6, 0.9, 1.0))
	if stagger_t <= 0.0:
		stagger_t = 0.0
		if is_instance_valid(stun_halo):
			stun_halo.queue_free()
		stun_halo = null
		weak = false
		if is_instance_valid(bar):
			bar.set("weak", false)
		st = St.FIGHT
		st_t = 0.0
		rest = 0.25
		# 일어나며 뒤로 대시
		var d := -_to_player()
		if d.length() > 0.1:
			_dash(d.normalized())


# ── 피격 ────────────────────────────────────────────────

func take_hit(dmg: int, dir: Vector3, pos: Vector3, source := "bullet") -> void:
	if not alive:
		return
	var at := fx_point(pos, dir)
	if st == St.DORMANT or st == St.WAKE or st == St.TRANSITION:
		# 기동 · 광폭화 중에는 튕겨 낸다
		FX.sparks(at, 4, [Color.WHITE, Color(0.7, 0.9, 1.0)], 6.0, 0.2, -10.0, 0.05)
		if _hit_snd <= 0.0:
			_hit_snd = 0.1
			Sfx.play("ricochet", 0.1, -10.0)
		return
	var amount := float(dmg) * float(DMG.get(source, 1.0))
	if weak:
		amount *= 1.6
	if st == St.STAGGER:
		amount *= 2.0
	boss_hp -= amount
	if immortal:
		boss_hp = maxf(boss_hp, 1.0)
		_regen_t = 2.5
	_bar_hp(amount >= 6.0)
	kill_source = source
	var heavy := source in ["slash", "phantom", "missile", "parry", "deflect"] or amount >= 6.0
	HitSpark.spawn(at, dir, clampf(1.0 + amount * 0.05, 1.0, 2.6), self, 1 if heavy else 0)
	MocoFX.report(self, roundi(amount), heavy, at)
	if Main.inst.has_method("record_hit"):
		Main.inst.call("record_hit", self, roundi(amount), source)
	rig.hit(dir, clampf(amount * 0.07, 0.15, 1.2))
	if heavy:
		_flash_t = 0.06
		_set_flash(true)
	if _hit_snd <= 0.0:
		_hit_snd = 0.07
		Sfx.play("hit", 0.15, -8.0)
	if weak and randf() < 0.15:
		Main.inst.hud.popup("WEAK ×1.6", Color("ffe060"), at + Vector3(0, 1.2, 0))
	if source == "parry" and st == St.FIGHT:
		var d := global_position - Main.inst.player.global_position
		d.y = 0
		stagger(d.normalized(), 1.7)
	if phase == 1 and boss_hp <= MAX_HP * PHASE2_AT and st == St.FIGHT:
		boss_hp = MAX_HP * PHASE2_AT
		_bar_hp(true)
		_begin_transition()
	elif boss_hp <= 0.0:
		die(dir, source)


## 큰 몸이라 판정점이 몸 속에 묻힌다 → 연출 위치만 겉면으로
func fx_point(pos: Vector3, _dir := Vector3.ZERO) -> Vector3:
	var c := global_position + Vector3(0, 2.0 * size_k + lift_y, 0)
	var flat := Vector3(pos.x - c.x, 0, pos.z - c.z)
	if flat.length() < 0.01:
		return c
	var at := c + flat.normalized() * radius * 0.85
	at.y = clampf(pos.y, global_position.y + 0.9 * size_k, global_position.y + 3.2 * size_k) + lift_y
	return at


func _bar_hp(big := false) -> void:
	if is_instance_valid(bar):
		bar.call("set_hp", boss_hp / MAX_HP, big)
		bar.set("weak", weak or st == St.STAGGER)


# ── 덮개 재질 (섬광 · 락온 · 패링 예고) ────────────────

func _overlay_tick(dt: float) -> void:
	if _flash_t > 0.0:
		_flash_t -= dt
		if _flash_t <= 0.0:
			_set_flash(false)
	if glow_t > 0.0:
		glow_t -= dt
		if glow_t <= 0.0:
			_set_flash(_flash_t > 0.0)
	var on := windup_k > 0.0 and alive
	if on != charge_on:
		charge_on = on
		_charge_q = -1.0
		_set_flash(_flash_t > 0.0)
	if on:
		var q := snappedf(clampf(windup_k, 0.0, 1.0), 0.05)
		if q != _charge_q:
			_charge_q = q
			rig.set_overlay_param("charge", q)


func _set_flash(on: bool) -> void:
	if rig == null:
		return
	var rest_m: Material = null
	if locked:
		rest_m = Pal.lock_hatch()
	elif charge_on:
		rest_m = Pal.parry_charge()
	elif warn_glow:
		rest_m = Pal.parry_glow()
	if glow_t > 0.0:
		rest_m = Pal.parry_flash()
	rig.set_overlay(Pal.flash() if on else rest_m)


func set_locked(on: bool) -> void:
	if locked == on:
		return
	locked = on
	_set_flash(_flash_t > 0.0)
	if is_instance_valid(lock_marker):
		lock_marker.queue_free()
	lock_marker = null
	if on and alive:
		lock_marker = LockMarker.attach(self, radius, hp_bar_y)


# ── 정지 (처치) ─────────────────────────────────────────

func die(dir := Vector3.ZERO, source := "bullet") -> void:
	if not alive:
		return
	alive = false
	dying = true
	_end_pattern(true)
	_pods_stop()
	remove_from_group("enemies")
	kill_source = source
	death_dir = Vector3(dir.x, 0, dir.z).normalized()
	locked = false
	warn_glow = false
	charge_on = false
	windup_k = 0.0
	dash_t = 0.0
	if is_instance_valid(lock_marker):
		lock_marker.queue_free()
	if is_instance_valid(stun_halo):
		stun_halo.queue_free()
	_set_flash(false)
	st = St.DYING
	st_t = 0.0
	if is_instance_valid(bar):
		bar.call("set_hp", 0.0, true)
		bar.call("set_pattern", "SHUTDOWN")
	Main.inst.on_enemy_killed(self)
	Main.inst.hitstop(0.12)
	Sfx.play("overload", 0.03, 0.0)
	defeated.emit()


func _dying(dt: float) -> void:
	var e := st_t
	vel = vel.move_toward(Vector3.ZERO, 20.0 * dt)
	_w("rage", 0.0, 3.0)
	rig.spin = 0.0
	_w("claw", 0.5, 3.0)
	if e < 0.7:
		# 부들부들 떨며 불꽃
		_w("eye_on", 1.0 if fmod(e * 23.0, 1.0) < 0.5 else 0.1, 60.0)
		rig.pose = {"torso": Vector3(0.3 + sin(t * 40.0) * 0.06, sin(t * 33.0) * 0.08, sin(t * 29.0) * 0.06), "upperarm_l": Vector3(0.3, 0, -0.5), "upperarm_r": Vector3(0.3, 0, 0.6)}
	else:
		var c := smoothstep(0.7, 1.6, e)
		_w("kneel", c, 30.0)
		_w("lean", 0.35 * c, 8.0)
		_w("eye_on", 0.0 if e > 1.9 else (1.0 if fmod(e * 9.0, 1.0) < 0.5 else 0.2), 60.0)
		_w("gun_aim", 0.0, 4.0)
		rig.pose = {"upperarm_l": Vector3(-0.15, 0, 0.15), "upperarm_r": Vector3(-0.1, 0, -0.15), "forearm_r": Vector3(-0.2, 0, 0), "forearm_l": Vector3(-0.2, 0, 0)}
		if e >= 1.5 and not ps.has("thud"):
			ps.thud = true
			LancasterFX.dust_ring(global_position, 1.8 * size_k, 16)
			Main.inst.shake(0.6)
			var thud := Sfx.play("land", 0.05, 2.0)
			if thud:
				thud.pitch_scale = 0.4
			Sfx.play("powerdown", 0.03, 0.0)
	_fx_t -= dt
	if _fx_t <= 0.0:
		_fx_t = randf_range(0.12, 0.28) if e < 1.6 else 0.2
		var c := global_position + Vector3(randf_range(-1, 1) * size_k, randf_range(1.0, 3.0) * size_k * (1.0 - 0.4 * smoothstep(0.7, 1.6, e)), randf_range(-1, 1) * size_k)
		if e < 1.6:
			FX.fire_explosion(c, 0.45)
			Sfx.play("boom", 0.1, -10.0)
			Main.inst.shake(0.2)
		LancasterFX.smoke(rig.at("pt_vent_l") + Vector3(0, 0.3, 0), 1.2)
		LancasterFX.smoke(rig.at("pt_vent_r") + Vector3(0, 0.3, 0), 1.2)
		if randf() < 0.4:
			FX.sparks(c, 6, [Color.WHITE, Color(1.0, 0.75, 0.3)], 6.0, 0.3, -12.0, 0.06)
	if e >= 3.4:
		st = St.DEAD
		st_t = 0.0
		if is_instance_valid(bar):
			bar.call("hide_bar")


func _dead(dt: float) -> void:
	_snapv("kneel", 1.0)
	_snapv("lean", 0.35)
	_snapv("eye_on", 0.0)
	rig.pose = {"upperarm_l": Vector3(-0.15, 0, 0.15), "upperarm_r": Vector3(-0.1, 0, -0.15), "forearm_r": Vector3(-0.2, 0, 0), "forearm_l": Vector3(-0.2, 0, 0)}
	_fx_t -= dt
	if _fx_t <= 0.0 and st_t < 8.0:
		_fx_t = 0.3
		LancasterFX.smoke(rig.at("pt_vent_l") + Vector3(0, 0.3, 0), 0.8)
		LancasterFX.smoke(rig.at("pt_vent_r") + Vector3(0, 0.3, 0), 0.8)
