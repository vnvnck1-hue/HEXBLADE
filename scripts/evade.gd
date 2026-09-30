class_name Evade
extends RefCounted
## 적의 거리 벌리기. 플레이어가 가까이 붙으면 일정 확률로 셋 중 하나를 한다.
##  BACK   뒷걸음질: 플레이어를 바라본 채 반대쪽으로 물러선다 (기본형 적이 주로 한다)
##  DASH   이탈 대시: 반대쪽으로 순간 대시해 거리를 벌린 뒤, 기체가 가진 공격 중 하나를 무작위로 쏜다
##  BLINK  회피 반격: 붙어서 휘두른 광선검이 닿는 순간 플레이어 등 뒤로 순간이동해 피하고 곧바로 반격한다.
##         피한 순간 아주 잠깐 슬로모션이 걸린다.
## Enemy 가 하나씩 갖고, 기체 AI(_ai) 위에 이동을 덧붙여 적용한다. 확률은 기체마다 _ready 에서 정한다.
## 기체는 아래를 덮어써 동작을 정한다:
##   _can_evade() -> bool   지금 거리 벌리기를 해도 되는 상태인가 (공격 준비 중이면 false)
##   _evade_attack()        이탈 대시 뒤의 무작위 공격
##   _counter_attack()      순간이동 뒤의 반격

enum K { NONE, BACK, DASH, DASH_REST, BLINK }

const RANGE := 3.6              # 이 거리 안으로 붙으면 거리 벌리기를 고려한다
const ROLL_GAP := 0.45          # 붙어 있는 동안 이 간격마다 확률을 굴린다
const BACK_T := 0.65
const BACK_SPEED := 4.8
const DASH_T := 0.2
const DASH_SPEED := 19.0
const DASH_REST := 0.14         # 대시 뒤 공격까지 멈칫
const BLINK_BEHIND := 1.9       # 플레이어 등 뒤로 떨어지는 거리
const BLINK_DELAY := 0.2        # 순간이동 뒤 반격까지 (게임 초)
const SLOW := 0.25              # 회피 슬로모션 배율
const SLOW_REAL := 0.16         # 슬로모션 유지 (실제 초)
const COOLDOWN := Vector2(2.4, 4.0)
const GHOST := Color(0.75, 0.9, 1.0, 0.4)

var e: Enemy
var chance := 0.0               # 붙어 있을 때 굴릴 때마다 뒷걸음질/대시를 할 확률
var back_w := 0.7               # 그중 뒷걸음질 비율 (나머지는 이탈 대시)
var dodge := 0.0                # 광선검을 순간이동으로 피할 확률
var kind := K.NONE
var t := 0.0
var dir := Vector3.ZERO
var cd := 1.0
var roll_t := 0.0
var ghost_t := 0.0


func active() -> bool:
	return kind != K.NONE


## 조건 공통: 플레이 중이고, 확인 모드면 거리 벌리기 확인 모드에서만
static func _allowed() -> bool:
	var main := Main.inst
	if main == null or main.state != Main.State.PLAY or not main.player.alive:
		return false
	return not main.showcase or main.evade_show


## 매 물리 틱 (기체 AI 뒤에) 부른다
func update(dt: float) -> void:
	cd -= dt
	if kind == K.NONE:
		_consider(dt)
		return
	t -= dt
	var p := Main.inst.player
	match kind:
		K.BACK:
			if not e._can_evade():
				_end()
				return
			var k := clampf(t / BACK_T, 0.0, 1.0)
			_move(_away(p) * BACK_SPEED * (0.35 + 0.65 * k), dt)
			if t <= 0.0:
				_end()
		K.DASH:
			if not _move(dir * DASH_SPEED, dt):
				t = 0.0
			ghost_t -= dt
			if ghost_t <= 0.0:
				ghost_t = 0.03
				FX.afterimage(e.visual, GHOST)
			if t <= 0.0:
				kind = K.DASH_REST
				t = DASH_REST
		K.DASH_REST:
			if t <= 0.0:
				_end()
				if _allowed():
					e._evade_attack()
		K.BLINK:
			_face(p)
			if t <= 0.0:
				_end()
				if _allowed():
					e._counter_attack()


func _consider(dt: float) -> void:
	if cd > 0.0 or chance <= 0.0 or not _allowed() or not e._can_evade():
		return
	var p := Main.inst.player
	var d := e.global_position - p.global_position
	d.y = 0
	if d.length() > RANGE:
		roll_t = 0.0
		return
	roll_t -= dt
	if roll_t > 0.0:
		return
	roll_t = ROLL_GAP
	if randf() >= chance:
		return
	if randf() < back_w:
		_begin_back()
	else:
		_begin_dash(p)


func _end() -> void:
	kind = K.NONE
	cd = randf_range(COOLDOWN.x, COOLDOWN.y)
	roll_t = ROLL_GAP


func _away(p: Player) -> Vector3:
	var d := e.global_position - p.global_position
	d.y = 0
	return d.normalized() if d.length() > 0.05 else -e.global_basis.z


func _face(p: Player) -> void:
	var d := p.global_position - e.global_position
	d.y = 0
	if d.length() > 0.05:
		e.rotation.y = atan2(-d.x, -d.z)


## 벽에 막히지 않으면 움직이고 true, 막히면 제자리 false
func _move(v: Vector3, dt: float) -> bool:
	if v.length() < 0.001:
		return true
	var np := e.global_position + v * dt
	if Main.inst.is_blocked(np + v.normalized() * e.radius):
		return false
	e.global_position = Main.inst.push_out(np, e.radius)
	return true


func _begin_back() -> void:
	kind = K.BACK
	t = BACK_T
	print("EVADE back t=%.2f %s" % [Main.inst.time, e.get_script().get_global_name()])
	e.punch = maxf(e.punch, 0.4)
	FX.puffs(e.global_position, 3, [Color("8a88a0"), Color("6a6680"), Color("403c50"), Color("2c2a3a")], 0.5, 0.3, 0.3)


## 반대쪽(조금 비스듬히)으로 순간 대시. 앞이 벽이면 옆으로 틀어 본다.
func _begin_dash(p: Player) -> void:
	var away := _away(p)
	var side := 1.0 if randf() < 0.5 else -1.0
	for a in [0.35, -0.35, 0.9, -0.9, 1.4, -1.4]:
		var d: Vector3 = away.rotated(Vector3.UP, a * side)
		if not Main.inst.is_blocked(e.global_position + d * (DASH_SPEED * DASH_T * 0.6 + e.radius)):
			dir = d
			kind = K.DASH
			t = DASH_T
			ghost_t = 0.0
			e.punch = 1.0
			FX.shockwave(e.global_position, Color(0.75, 0.9, 1.0), 1.8, 0.2, 0.05)
			FX.afterimage(e.visual, GHOST)
			Sfx.play("dash", 0.08, -4.0)
			print("EVADE dash t=%.2f %s" % [Main.inst.time, e.get_script().get_global_name()])
			return


## 광선검 판정 직전에 Player 가 부른다. 피했으면 true (이 적은 이번 타격을 맞지 않는다).
## slash_dir: 검을 휘두르는 방향. 그 반대쪽 = 플레이어 등 뒤로 순간이동한다.
func try_dodge(p: Player, slash_dir: Vector3) -> bool:
	if dodge <= 0.0 or cd > 0.0 or kind == K.DASH or kind == K.BLINK or not _allowed():
		return false
	if e.stagger_t > 0.0 or not e._can_evade() or randf() >= dodge:
		return false
	var back := -Vector3(slash_dir.x, 0, slash_dir.z).normalized()
	var to := Vector3.ZERO
	var found := false
	for a in [0.0, 0.6, -0.6, 1.2, -1.2, 1.8, -1.8]:
		var d: Vector3 = back.rotated(Vector3.UP, a)
		var c := p.global_position + d * BLINK_BEHIND
		if not Main.inst.is_blocked(c) and not Main.inst.is_blocked(p.global_position + d * BLINK_BEHIND * 0.5):
			to = c
			found = true
			break
	if not found:
		return false
	var from := e.global_position + Vector3(0, 1.0, 0)
	FX.afterimage(e.visual, GHOST, 0.3)
	FX.flash(from, Color(0.8, 0.95, 1.0), 0.9, 0.06)
	e.global_position = Main.inst.push_out(to, e.radius)
	_face(p)
	var at := e.global_position + Vector3(0, 1.0, 0)
	FX.flash(at, Color.WHITE, 1.0, 0.06)
	FX.shockwave(e.global_position, Color(0.75, 0.9, 1.0), 2.2, 0.22, 0.05)
	FX.sparks(at, 14, [Color.WHITE, Color(0.7, 0.9, 1.0)], 7.0, 0.3, -6.0, 0.05)
	Sfx.play("dash", 0.05, -1.0)
	e.punch = 1.0
	kind = K.BLINK
	t = BLINK_DELAY
	cd = randf_range(COOLDOWN.x, COOLDOWN.y)
	_slowmo()
	print("EVADE blink t=%.2f %s" % [Main.inst.time, e.get_script().get_global_name()])
	return true


## 회피 순간 아주 잠깐 슬로모션 (실제 시간으로 풀린다). 패링 연출·궁극기 락온이 시간을 쥐고 있으면 건드리지 않는다.
static func _slowmo() -> void:
	var main := Main.inst
	if main.player.ult_aiming or (Parry.inst and Parry.inst.sequence_active()) or main.slowmo < 0.99:
		return
	main.set_slowmo(SLOW)
	main.get_tree().create_timer(SLOW_REAL, true, false, true).timeout.connect(func() -> void:
		if is_instance_valid(main) and is_equal_approx(main.slowmo, SLOW) and not main.player.ult_aiming:
			main.set_slowmo(1.0))
