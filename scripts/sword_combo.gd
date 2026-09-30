class_name SwordCombo
extends RefCounted
## 광선검 5단 콤보. Player 가 소유하고 매 물리 틱 update() → pose() 순으로 부른다.
##
##  1타 섬광 베기      파고들며 오른쪽 → 왼쪽 가로 일섬
##  2타 반동 역베기    맞힌 반동으로 뒤로 살짝 튕겨 떴다가, 그 탄력으로 되받아 왼쪽 → 오른쪽
##  3타 삼연섬         X자 대각 두 번 + 찌르기 (한 동작에 3타)
##  4타 도약 올려베기  웅크렸다 뛰어오르며 아래 → 위로 올려 벤다 (공중으로 떠오른다)
##  5타 낙월           정점에서 앞으로 한 바퀴 돌며 내리꽂아 착지 충격파 (마무리)
##
## 연결 규칙: 각 타격이 실제로 적중(장갑에 막히지 않은 피해)했을 때만 다음 단으로 부드럽게 이어진다.
##  - 적중 → 짧은 캔슬 지점부터 선입력이 곧바로 다음 단을 낸다. 입력이 없으면 LINK_TIME 동안 기다린다.
##  - 헛침 → 휘두른 기세에 몸이 끌려가는 오버스윙 자세로 늘어지고 WHIFF_LOCK 동안 검을 못 쓴다. 콤보는 1타로.
##  - 막힘(장갑) → 칼이 튕겨 뒤로 밀리며 같은 경직.
## 자세는 준비(WINDUP: 빠르게 감기고 멈칫) → 스윙(SWING 2~4프레임, 폭발적으로 뻗는다) →
## 여운(FOLLOW: 살짝 넘쳤다 돌아온다) → 복귀(RETURN) 로 보간한다. 스윙 동안에는 프레임 사이 자세를
## 여러 번 계산해 광선검 잔상에 넘겨, 한 프레임에 크게 도는 칼도 매끈한 초승달을 남긴다.

enum Ph { IDLE, LUNGE, WINDUP, SWING, FOLLOW, WHIFF, RETURN }

const F := 1.0 / 60.0
const LINK_TIME := 0.36         # 적중한 단이 끝난 뒤 다음 입력을 기다리는 시간
const WHIFF_LOCK := 0.46        # 헛치거나 막히면 이만큼 검을 다시 못 휘두른다
const WHIFF_POSE := 0.3         # 오버스윙 자세가 늘어지는 시간
const FINISH_REST := 0.24       # 5타 뒤 숨 고르기
const BOSS_REST := 0.7          # 보스(no_slash_reset)에게 5타를 넣은 뒤 숨 고르기
const STOP := 1.45              # 대상과 유지하는 거리
const LUNGE_SPEED := 62.0
const RANGE := 8.0

const NEUTRAL := {
	"ax": 0.0, "ay": 0.0, "az": 0.0, "bl": Vector3(38, -18, 0), "bs": 1.0,
	"tx": 0.0, "ty": 0.0, "tz": 0.0, "uy": 0.0, "lift": 0.0, "pitch": 0.0,
	"hl": 0.0, "hr": 0.0, "kl": 0.0, "kr": 0.0, "al": 0.0,
}

## 단 정의. 시간은 프레임(60fps) 단위. 각 cut: wind(준비) · swing(2~4) · ready/impact 자세 ·
## back(준비 중 뒤로 m) · fwd(스윙 중 앞으로 m) · reach/cone/dmg · stop(히트스탑 초) · kb(넉백 배율) ·
## sq(찌그러짐 충격: 준비·스윙·임팩트) · ease(키별 스윙 이징 덮어쓰기) · pitch_s(스윙음 높이)
static var STEPS: Array = []

var p: Player
var trail: SaberTrail
var step := -1
var cut := 0
var ph := Ph.IDLE
var t := 0.0
var dur := 0.0
var hit_ok := false
var blocked := false
var buffered := false
var link_t := 0.0
var next_step := 0
var dir := Vector3.FORWARD
var vel := Vector3.ZERO
var target: Enemy
var cur: Dictionary = NEUTRAL.duplicate()
var from: Dictionary = NEUTRAL.duplicate()
var to: Dictionary = NEUTRAL.duplicate()
var ease_over: Dictionary = {}
var k_prev := 0.0
var move_d := 0.0
var move_prev := 0.0
var approach := 0.0
var lunged := false
var land_pending := false
var chain := 0                  # 연속 적중 단 수 (HUD·확인용)


static func _pose(over: Dictionary) -> Dictionary:
	var d := NEUTRAL.duplicate()
	d.merge(over, true)
	return d


static func _build() -> void:
	if not STEPS.is_empty():
		return
	STEPS = [
		{   # 1타 섬광 베기
			"name": "FLASH", "lunge": true, "approach": 1.2, "follow": 9, "cancel": 4,
			"cuts": [{
				"wind": 4, "swing": 3, "back": 0.0, "fwd": 0.5,
				"ready": _pose({"ay": -1.55, "ax": -0.45, "bl": Vector3(8, -72, 0), "ty": -0.95, "tz": 0.08, "pitch": 0.22,
					"hl": -0.55, "hr": 0.6, "kl": -0.25, "kr": -0.85, "al": 0.35}),
				"impact": _pose({"ay": 2.0, "ax": -0.4, "bl": Vector3(8, -72, 0), "ty": 0.95, "tz": -0.06, "pitch": 0.1, "bs": 1.35,
					"hl": 0.5, "hr": -0.45, "kl": -0.5, "kr": -0.2, "al": -0.3}),
				"reach": 2.9, "cone": 80.0, "dmg": 8, "stop": 0.06, "kb": 0.7, "sq": [-5.0, 7.0, -6.0], "pitch_s": 1.0,
			}],
			"rest": _pose({"ay": 1.8, "ax": -0.3, "bl": Vector3(10, -60, 0), "ty": 0.75, "pitch": 0.06, "hl": 0.35, "hr": -0.3, "kl": -0.4, "kr": -0.15}),
		},
		{   # 2타 반동 역베기: 뒤로 튕겨 살짝 떴다가 그 탄력으로 되받아 친다
			"name": "RECOIL", "lunge": true, "approach": 1.4, "follow": 9, "cancel": 4,
			"cuts": [{
				"wind": 4, "swing": 2, "back": 0.75, "fwd": 1.25,
				"ready": _pose({"ay": 2.15, "ax": -0.3, "bl": Vector3(8, -30, 0), "ty": 1.05, "tz": -0.1, "uy": 0.25, "lift": 0.3, "pitch": -0.28,
					"hl": 0.55, "hr": 0.35, "kl": -1.1, "kr": -0.9, "al": -0.5}),
				"impact": _pose({"ay": -1.65, "ax": -0.35, "bl": Vector3(8, -30, 0), "ty": -1.0, "tz": 0.08, "uy": -0.3, "lift": 0.0, "pitch": 0.18, "bs": 1.4,
					"hl": -0.5, "hr": 0.55, "kl": -0.2, "kr": -0.6, "al": 0.4}),
				"reach": 3.0, "cone": 85.0, "dmg": 8, "stop": 0.06, "kb": 0.6, "sq": [-7.0, 9.0, -6.0], "pitch_s": 1.12,
				"ease": {"lift": "in"},
			}],
			"rest": _pose({"ay": -1.4, "ax": -0.25, "bl": Vector3(10, -40, 0), "ty": -0.8, "uy": -0.15, "pitch": 0.08, "hl": -0.35, "hr": 0.4, "kl": -0.2, "kr": -0.45}),
		},
		{   # 3타 삼연섬: 대각 X 두 번 + 찌르기
			"name": "FLURRY", "lunge": true, "approach": 1.0, "follow": 9, "cancel": 5,
			"cuts": [
				{
					"wind": 3, "swing": 2, "back": 0.0, "fwd": 0.3,
					"ready": _pose({"ax": 2.4, "ay": 0.95, "bl": Vector3(-90, 0, 0), "ty": 0.7, "tx": 0.18, "pitch": -0.05,
						"hl": 0.3, "hr": -0.2, "kl": -0.4, "kr": -0.3}),
					"impact": _pose({"ax": 0.45, "ay": -1.25, "bl": Vector3(-90, 0, 0), "ty": -0.7, "tx": -0.25, "pitch": 0.2, "bs": 1.3,
						"hl": -0.3, "hr": 0.45, "kl": -0.3, "kr": -0.6}),
					"reach": 2.8, "cone": 70.0, "dmg": 4, "stop": 0.03, "kb": 0.35, "sq": [-3.0, 5.0, -4.0], "pitch_s": 1.25,
				},
				{
					"wind": 2, "swing": 2, "back": 0.0, "fwd": 0.3,
					"ready": _pose({"ax": 2.35, "ay": -1.05, "bl": Vector3(-90, 0, 0), "ty": -0.75, "tx": 0.15, "pitch": -0.05,
						"hl": -0.2, "hr": 0.3, "kl": -0.3, "kr": -0.4}),
					"impact": _pose({"ax": 0.4, "ay": 1.3, "bl": Vector3(-90, 0, 0), "ty": 0.75, "tx": -0.25, "pitch": 0.2, "bs": 1.3,
						"hl": 0.45, "hr": -0.3, "kl": -0.6, "kr": -0.3}),
					"reach": 2.8, "cone": 70.0, "dmg": 4, "stop": 0.03, "kb": 0.35, "sq": [-3.0, 5.0, -4.0], "pitch_s": 1.35,
				},
				{   # 찌르기: 몸을 비틀어 당겼다가 칼을 길게 늘여 꿰뚫는다
					"wind": 3, "swing": 2, "back": 0.2, "fwd": 1.1,
					"ready": _pose({"ax": 1.25, "ay": -0.45, "bl": Vector3(-90, 0, 0), "ty": -0.85, "tz": 0.1, "pitch": -0.12, "bs": 0.8,
						"hl": 0.5, "hr": 0.2, "kl": -0.9, "kr": -0.7, "al": 0.5}),
					"impact": _pose({"ax": 1.62, "ay": 0.1, "bl": Vector3(-90, 0, 0), "ty": 0.55, "tz": -0.05, "pitch": 0.32, "bs": 1.75,
						"hl": -0.75, "hr": 0.65, "kl": -0.1, "kr": -0.5, "al": -0.6}),
					"reach": 3.7, "cone": 32.0, "dmg": 5, "stop": 0.06, "kb": 0.9, "sq": [-6.0, 10.0, -5.0], "pitch_s": 0.9,
				},
			],
			"rest": _pose({"ax": 1.45, "ay": 0.05, "bl": Vector3(-90, 0, 0), "ty": 0.4, "pitch": 0.2, "bs": 1.1, "hl": -0.5, "hr": 0.5, "kl": -0.15, "kr": -0.45}),
		},
		{   # 4타 도약 올려베기
			"name": "RISE", "lunge": true, "approach": 1.2, "follow": 10, "cancel": 4,
			"cuts": [{
				"wind": 4, "swing": 3, "back": 0.0, "fwd": 0.9,
				"ready": _pose({"ax": -0.7, "ay": -1.0, "bl": Vector3(-90, 0, 0), "ty": -0.6, "tx": -0.15, "lift": -0.2, "pitch": 0.3,
					"hl": 0.85, "hr": 0.75, "kl": -1.5, "kr": -1.35, "al": 0.4}),
				"impact": _pose({"ax": 2.95, "ay": 0.75, "bl": Vector3(-90, 0, 0), "ty": 0.45, "tx": 0.3, "lift": 0.85, "pitch": -0.22, "bs": 1.4,
					"hl": -0.3, "hr": 0.9, "kl": -0.2, "kr": -1.4, "al": -0.5}),
				"reach": 3.0, "cone": 65.0, "dmg": 8, "stop": 0.07, "kb": 0.25, "sq": [-9.0, 13.0, -2.0], "pitch_s": 1.18,
				"ease": {"lift": "out"}, "arc": "rise",
			}],
			# 여운 동안 계속 떠오르며 정점에서 멈칫한다 (5타의 발판)
			"rest": _pose({"ax": 2.8, "ay": 0.2, "bl": Vector3(-90, 0, 0), "ty": 0.25, "tx": 0.25, "lift": 1.5, "pitch": -0.32,
				"hl": 0.8, "hr": 1.0, "kl": -1.4, "kr": -1.6, "al": -0.6}),
		},
		{   # 5타 낙월: 정점에서 앞으로 한 바퀴 돌며 내리꽂는다
			"name": "CRESCENT", "lunge": true, "approach": 2.6, "follow": 16, "cancel": 99,
			"cuts": [{
				"wind": 4, "swing": 4, "back": 0.0, "fwd": 0.6,
				"ready": _pose({"ax": 3.3, "ay": 0.0, "bl": Vector3(-90, 0, 0), "ty": 0.1, "tx": 0.35, "lift": 1.6, "pitch": -0.55,
					"hl": 1.0, "hr": 1.05, "kl": -1.6, "kr": -1.7, "al": -0.7}),
				"impact": _pose({"ax": 1.05, "ay": 0.0, "bl": Vector3(-90, 0, 0), "ty": 0.0, "tx": -0.35, "lift": -0.12, "pitch": TAU + 0.42, "bs": 1.5,
					"hl": 0.75, "hr": -0.2, "kl": -1.3, "kr": -0.5, "al": 0.5}),
				"reach": 3.5, "cone": 115.0, "dmg": 14, "stop": 0.13, "kb": 1.5, "sq": [-4.0, 8.0, -16.0], "pitch_s": 0.72,
				"ease": {"pitch": "inout", "lift": "in2"}, "slam": true,
			}],
			"rest": _pose({"ax": 0.9, "ay": 0.0, "bl": Vector3(-90, 0, 0), "tx": -0.2, "lift": -0.05, "pitch": 0.3, "bs": 1.0,
				"hl": 0.6, "hr": -0.15, "kl": -1.1, "kr": -0.45}),
		},
	]


func _init(owner: Player) -> void:
	p = owner
	_build()


# ── 상태 질의 ───────────────────────────────────────────

## 이동·조준을 콤보가 잡고 있는가 (일반 이동 입력 무시)
func committed() -> bool:
	return ph == Ph.LUNGE or ph == Ph.WINDUP or ph == Ph.SWING or ph == Ph.FOLLOW or ph == Ph.WHIFF


func posing() -> bool:
	return ph != Ph.IDLE


func swinging() -> bool:
	return ph == Ph.LUNGE or ph == Ph.SWING or (ph == Ph.FOLLOW and t < 3.0 * F) or ph == Ph.WINDUP and step == 2 and cut > 0


func lift() -> float:
	return float(cur.lift) if ph != Ph.IDLE else 0.0


# ── 입력 ────────────────────────────────────────────────

## 검 버튼. 콤보가 처리하면 true.
func press() -> bool:
	if ph == Ph.WHIFF:
		return true                      # 헛친 뒤 경직 중: 무시
	if ph == Ph.LUNGE or ph == Ph.WINDUP or ph == Ph.SWING or ph == Ph.FOLLOW:
		buffered = true
		return true
	if link_t > 0.0:
		_start(next_step)
		return true
	if p.slash_cd > 0.0:
		return true
	_start(0)
	return true


## 대시·피격·패링 등으로 끊는다. hard 면 자세도 즉시 놓는다 (다른 모션이 바로 잇는다).
func cancel(hard := false) -> void:
	if ph == Ph.IDLE and link_t <= 0.0:
		return
	link_t = 0.0
	next_step = 0
	buffered = false
	chain = 0
	vel = Vector3.ZERO
	if hard or ph == Ph.IDLE:
		ph = Ph.IDLE
		cur = NEUTRAL.duplicate()
		(p.j.blade as Node3D).scale = Vector3.ONE
		return
	_enter_return(0.08)


# ── 진행 ────────────────────────────────────────────────

func _start(i: int) -> void:
	step = i
	cut = 0
	hit_ok = false
	blocked = false
	buffered = false
	link_t = 0.0
	lunged = false
	var s: Dictionary = STEPS[step]
	# 대상: 사거리 안 가장 가까운 적 (처치 후엔 다음 적에게로 이어 파고든다)
	target = _find_target() if step == 0 or not is_instance_valid(target) or not target.alive else target
	dir = p.aim_dir
	var gap := 0.0
	if target:
		var d := target.global_position - p.global_position
		d.y = 0
		if d.length() > 0.05:
			dir = d.normalized()
		gap = d.length() - STOP
	p.aim_dir = dir
	# 이 단의 동작 자체가 내딛는 거리(반동·찌르기 등)를 빼고 남은 만큼만 다가간다
	var net := 0.0
	for c in s.cuts:
		net += float(c.fwd) - float(c.back)
	approach = clampf(gap - net, -1.2, float(s.approach)) if target else 0.0
	# 가까이 붙기에 너무 멀면 먼저 번개처럼 파고든다 (준비 동작을 겸한다)
	var far := gap - net - float(s.approach)
	if s.lunge and target and far > 0.25:
		_enter_lunge(far)
	else:
		_enter_windup()


func _enter_lunge(dist: float) -> void:
	ph = Ph.LUNGE
	t = 0.0
	dur = maxf(dist / LUNGE_SPEED, 2.0 * F)
	vel = dir * (dist / dur)
	lunged = true
	from = cur.duplicate()
	to = (STEPS[step].cuts[0] as Dictionary).ready
	p.invuln = maxf(p.invuln, dur + 0.05)
	p.tilt_v += dir * 8.0
	FX.shockwave(p.global_position, Pal.BLADE, 1.8, 0.22, 0.05)
	Sfx.play("dash", 0.08, -5.0)
	Main.inst.camera.fov_punch(3.0)


func _cutd() -> Dictionary:
	return (STEPS[step].cuts as Array)[cut]


func _enter_windup() -> void:
	var c := _cutd()
	ph = Ph.WINDUP
	t = 0.0
	# 파고들며 이미 자세를 잡았으면 준비는 짧게
	dur = float(c.wind) * F * (0.5 if lunged and cut == 0 else 1.0)
	from = cur.duplicate()
	to = c.ready
	ease_over = {}
	k_prev = 0.0
	move_d = -float(c.back) + approach * 0.3 * (1.0 if cut == 0 else 0.0)
	move_prev = 0.0
	p.squash_v += float(c.sq[0])
	p.tilt_v += -dir * 2.5
	if cut > 0 and is_instance_valid(target) and target.alive:
		# 연타 사이에도 대상을 살짝 따라간다
		var d := target.global_position - p.global_position
		d.y = 0
		if d.length() > 0.3:
			dir = dir.slerp(d.normalized(), 0.6).normalized()
			p.aim_dir = dir


func _enter_swing() -> void:
	var c := _cutd()
	ph = Ph.SWING
	t = 0.0
	dur = float(c.swing) * F
	from = cur.duplicate()
	to = c.impact
	ease_over = c.get("ease", {})
	k_prev = 0.0
	move_d = float(c.fwd) + (approach * 0.7 if cut == 0 else 0.0)
	move_prev = 0.0
	p.squash_v += float(c.sq[1])
	p.tilt_v += dir * 6.0
	var snd := Sfx.play("slash", 0.04, -1.0 if cut == 0 else -3.0)
	if snd:
		snd.pitch_scale = float(c.pitch_s) * randf_range(0.96, 1.04)
	if c.get("slam", false):
		p.invuln = maxf(p.invuln, dur + 0.15)
		Sfx.play("dash", 0.05, -3.0)
	var yaw := atan2(-dir.x, -dir.z)
	var up := Basis(Vector3.UP, yaw)
	match c.get("arc", "slam" if c.get("slam", false) else ""):
		"rise":
			# 아래 → 위 대각 호: 앞쪽으로 55° 세워 기울인다
			FX.crescent(p.global_position + Vector3(0, 1.1, 0) + dir * 0.3, up * Basis(Vector3.FORWARD, deg_to_rad(-60)) * Basis(Vector3.RIGHT, deg_to_rad(35)) * Basis.from_scale(Vector3(-0.85, 1, 0.85)), dur, 0.1)
		"slam":
			# 공중 회전 내려찍기: 몸 둘레를 크게 도는 세로 호 + 착지 순간 앞바닥을 가르는 호
			FX.crescent(p.global_position + Vector3(0, 1.5, 0), up * Basis(Vector3.FORWARD, deg_to_rad(90)) * Basis(Vector3.UP, deg_to_rad(-25)) * Basis.from_scale(Vector3(1.1, 1, 1.1)), dur, 0.12)
	trail.boost = 1.0


func _enter_follow() -> void:
	var s: Dictionary = STEPS[step]
	ph = Ph.FOLLOW
	t = 0.0
	dur = float(s.follow) * F
	from = cur.duplicate()
	to = s.rest
	ease_over = {}
	trail.boost = 0.0


func _enter_whiff() -> void:
	ph = Ph.WHIFF
	t = 0.0
	dur = WHIFF_POSE
	from = cur.duplicate()
	# 오버스윙: 휘두른 쪽으로 몸이 더 돌아가고 앞으로 쏠리며, 떠 있었으면 떨어진다
	var imp: Dictionary = _cutd().impact
	to = imp.duplicate()
	var side := signf(float(imp.ty)) if absf(float(imp.ty)) > 0.1 else 1.0
	if blocked:
		# 튕김: 칼이 위로 튀고 몸이 뒤로 젖혀진다
		to.ax = 2.3
		to.ay = -float(imp.ay) * 0.4
		to.ty = -float(imp.ty) * 0.5
		to.pitch = -0.35
		to.bs = 0.9
		vel = -dir * 6.5
		p.tilt_v += -dir * 12.0
	else:
		to.uy = float(imp.uy) + side * 0.55
		to.ty = float(imp.ty) * 1.25
		to.pitch = 0.42
		to.bs = 1.0
		to.hl = -0.6
		to.hr = 0.7
		to.kl = -0.2
		to.kr = -0.9
		vel = dir * 3.5
		p.tilt_v += dir * 7.0
	to.lift = 0.0
	ease_over = {"lift": "in2"}
	trail.boost = 0.0
	p.slash_cd = WHIFF_LOCK
	land_pending = float(cur.lift) > 0.3
	link_t = 0.0
	next_step = 0
	buffered = false
	chain = 0


func _enter_return(d := -1.0) -> void:
	ph = Ph.RETURN
	t = 0.0
	var lf := float(cur.lift)
	dur = d if d > 0.0 else 0.12 + maxf(lf, 0.0) * 0.14
	land_pending = land_pending or lf > 0.3
	from = cur.duplicate()
	to = NEUTRAL.duplicate()
	ease_over = {"lift": "in2"}
	vel = Vector3.ZERO


func update(dt: float) -> void:
	if link_t > 0.0 and (ph == Ph.IDLE or ph == Ph.RETURN):
		link_t -= dt
		if link_t <= 0.0:
			next_step = 0
			chain = 0
	t += dt
	match ph:
		Ph.LUNGE:
			if t >= dur:
				_finish_phase()
				vel = dir * 2.0
				_enter_windup()
		Ph.WINDUP:
			var k := clampf(t / dur, 0.0, 1.0)
			_move(1.0 - pow(1.0 - k, 3.0), dt)
			if t >= dur:
				_finish_phase()
				_enter_swing()
		Ph.SWING:
			var k := clampf(t / dur, 0.0, 1.0)
			_move(_ease(k, "expo"), dt)
			if t >= dur:
				_finish_phase()
				_impact()
		Ph.FOLLOW:
			vel = vel.move_toward(Vector3.ZERO, 60.0 * dt)
			var last := step >= STEPS.size() - 1
			if not last and buffered and t >= float(STEPS[step].cancel) * F:
				_start(step + 1)
				return
			if t >= dur:
				if last:
					var boss: bool = is_instance_valid(target) and target.get("no_slash_reset") == true
					p.slash_cd = BOSS_REST if boss else FINISH_REST
					next_step = 0
					chain = 0
				else:
					link_t = LINK_TIME
					next_step = step + 1
				_enter_return()
		Ph.WHIFF:
			vel = vel.move_toward(Vector3.ZERO, 22.0 * dt)
			if t >= dur:
				_enter_return(0.16)
		Ph.RETURN:
			if t >= dur:
				ph = Ph.IDLE
				cur = NEUTRAL.duplicate()
				_land()
				# 기다리는 동안 링크가 열려 있으면 다음 입력을 받는다


func _move(frac: float, dt: float) -> void:
	if dt <= 0.0:
		return
	vel = dir * (move_d * (frac - move_prev) / dt)
	move_prev = frac
	# 대상 몸 속으로 파고들지 않는다
	if is_instance_valid(target) and target.alive and vel.dot(dir) > 0.0:
		var d := target.global_position - p.global_position
		d.y = 0
		if d.length() < target.radius + 0.8 and d.dot(dir) > 0.0:
			vel -= dir * vel.dot(dir)


## 스윙 끝: 판정
func _impact() -> void:
	var c := _cutd()
	var r: Dictionary = p.combo_strike(dir, float(c.reach), float(c.cone), int(c.dmg), float(c.kb), c.get("slam", false))
	var main := Main.inst
	if main.capture_mode:
		print("COMBO step=%d cut=%d %s hit=%d blocked=%d t=%.3f f=%d" % [step + 1, cut, STEPS[step].name, int(r.hit), int(r.blocked), main.time, main.capture_frame])
	p.squash_v += float(c.sq[2])
	cur.pitch = wrapf(float(cur.pitch), -PI, PI)
	cur.uy = wrapf(float(cur.uy), -PI, PI)
	if int(r.hit) > 0:
		hit_ok = true
		main.hitstop(float(c.stop))
		main.shake(0.3 + float(c.stop) * 3.0)
		main.camera.fov_punch(-3.0 - float(c.stop) * 30.0)
		main.kick(dir * 0.45)
	elif int(r.blocked) > 0:
		blocked = true
		main.shake(0.25)
	else:
		main.shake(0.12)
	if c.get("slam", false):
		_slam_fx(int(r.hit) > 0)
	elif int(r.hit) > 0:
		var tip: Vector3 = (p.j.blade as Node3D).to_global(Vector3(0, 0, -1.3))
		FX.flash(tip, Color(1.0, 0.8, 0.92), 0.4, 0.035)
		Distortion.burst(tip, 1.3, 0.22, 0.8)
	var cuts: Array = STEPS[step].cuts
	if cut < cuts.size() - 1:
		cut += 1
		_enter_windup()
		return
	if hit_ok:
		chain += 1
		_enter_follow()
		if step == STEPS.size() - 1:
			main.hud.popup("CRESCENT", Color(1.0, 0.6, 0.85), p.global_position + Vector3(0, 2.4, 0))
	else:
		if blocked:
			FX.sparks((p.j.blade as Node3D).to_global(Vector3(0, 0, -1.0)), 10, [Color.WHITE, Color("ffd080")], 6.0, 0.25, -8.0, 0.05)
			Sfx.play("clank", 0.05, -4.0)
		_enter_whiff()


func _slam_fx(hit: bool) -> void:
	var g := Vector3(p.global_position.x, Main.gy(p.global_position) + 0.05, p.global_position.z) + dir * 1.4
	FX.crescent(Vector3(p.global_position.x, Main.gy(p.global_position) + 0.25, p.global_position.z), Basis(Vector3.UP, atan2(-dir.x, -dir.z)) * Basis.from_scale(Vector3(1.35, 1, 1.35)), 0.03, 0.14)
	FX.shockwave(g, Color(1.0, 0.4, 0.75), 4.2, 0.3, 0.1)
	FX.shockwave(g, Color(0.55, 0.3, 1.0), 2.8, 0.22, 0.06)
	FX.sparks(g + Vector3(0, 0.15, 0), 26, [Color.WHITE, Color(1.0, 0.45, 0.75), Color(0.6, 0.35, 1.0)], 9.0, 0.35, -14.0, 0.08)
	FX.land_dust(g)
	FX.flash(g + Vector3(0, 0.4, 0), Color(1.0, 0.7, 0.9), 1.6, 0.06)
	Distortion.burst(g + Vector3(0, 0.4, 0), 4.6, 0.38, 1.4 if hit else 1.0)
	Sfx.play("land", 0.05, 2.0)
	Sfx.play("boom", 0.1, -8.0 if hit else -12.0)
	Main.inst.shake(0.5)


func _land() -> void:
	if not land_pending:
		return
	land_pending = false
	p.squash_v -= 9.0
	FX.shockwave(p.global_position, Color("8a7ae0"), 1.6, 0.22, 0.05)
	Sfx.play("land", 0.1, -8.0)


func _find_target() -> Enemy:
	var best: Enemy = null
	var bd := RANGE
	for e in p.get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if not en.alive or not en.landed:
			continue
		var d := en.global_position - p.global_position
		d.y = 0
		var l := d.length()
		# 1타: 조준 방향 70° 안, 또는 아주 가까운 적. 이어지는 단: 사방에서 찾되 정면일수록 우선
		# (벤 적이 쓰러지면 다음 적에게 몸을 돌려 파고든다). 방금 벤 대상은 계속 우선.
		var ang := p.aim_dir.angle_to(d / maxf(l, 0.001))
		var score := l - (0.6 if en == target else 0.0) + (ang * 0.8 if step > 0 else 0.0)
		if score < bd and (l < 2.2 or step > 0 or ang < deg_to_rad(70)):
			bd = score
			best = en
	return best


# ── 자세 ────────────────────────────────────────────────

func _ease(k: float, kind: String) -> float:
	match kind:
		"expo":
			return 1.0 if k >= 1.0 else (1.0 - pow(2.0, -10.0 * k)) / (1.0 - pow(2.0, -10.0))
		"out":
			return 1.0 - pow(1.0 - k, 3.0)
		"in":
			return k * k
		"in2":
			return k * k * k
		"inout":
			return k * k * (3.0 - 2.0 * k)
		"back":
			var s := 1.9
			var q := k - 1.0
			return 1.0 + q * q * ((s + 1.0) * q + s)
		"lin":
			return k
	return k


func _phase_k(k: float) -> Dictionary:
	# 구간별 기본 이징: 준비는 빠르게 감기고 멈칫(ease-out), 스윙은 폭발(expo), 여운은 넘쳤다 돌아옴(back)
	var base := "lin"
	match ph:
		Ph.WINDUP:
			base = "out"
		Ph.SWING:
			base = "expo"
		Ph.FOLLOW:
			base = "back"
		Ph.WHIFF:
			base = "out"
		Ph.RETURN:
			base = "out"
		Ph.LUNGE:
			base = "out"
	var out := {}
	for key in NEUTRAL:
		out[key] = _ease(k, ease_over.get(key, base))
	return out


func _blend(ks: Dictionary) -> void:
	for key in NEUTRAL:
		var k: float = ks[key]
		if key == "bl":
			cur[key] = (from[key] as Vector3).lerp(to[key], k)
		else:
			cur[key] = lerpf(float(from[key]), float(to[key]), k)


## Player._animate 끝에서 부른다: 현재 구간 진행도에 맞춰 자세를 만들고 관절에 적용한다.
## 스윙 중에는 지난 틱과 이번 틱 사이 자세를 여러 번 적용해 잔상에 칼 위치를 넘긴다.
func pose(dt: float) -> void:
	if ph == Ph.IDLE:
		trail.feed(dt, [])
		return
	var k := clampf(t / maxf(dur, 0.0001), 0.0, 1.0)
	if ph == Ph.SWING or ph == Ph.LUNGE:
		_substeps(k_prev, k)
	k_prev = k
	_blend(_phase_k(k))
	_apply()
	var samples := pending
	pending = []
	trail.feed(dt, samples)


var pending: Array = []


## 지난 틱 진행도 kp → k 사이 자세를 잘게 적용해 칼 위치를 잔상용으로 모은다
func _substeps(kp: float, k: float) -> void:
	var n := clampi(int(ceil(absf(k - kp) * 14.0)), 1, 12)
	for i in range(1, n):
		var ki := lerpf(kp, k, float(i) / n)
		_blend(_phase_k(ki))
		_apply()
		pending.append(trail.sample_now())


## 구간이 이번 틱에 끝났다: 마지막 자세(k=1)까지 채워 적용한다 (임팩트 자세를 건너뛰지 않게)
func _finish_phase() -> void:
	if ph == Ph.SWING or ph == Ph.LUNGE:
		_substeps(k_prev, 1.0)
	_blend(_phase_k(1.0))
	_apply()
	if ph == Ph.SWING or ph == Ph.LUNGE:
		pending.append(trail.sample_now())
	k_prev = 0.0


func _apply() -> void:
	var j := p.j
	var yaw := atan2(-dir.x, -dir.z)
	var uy := float(cur.uy)
	(j.upper as Node3D).rotation.y = yaw + uy
	(j.legs as Node3D).rotation.y = yaw + uy * 0.4
	var arm: Node3D = j.arm_r
	arm.rotation = Vector3(float(cur.ax), float(cur.ay), float(cur.az))
	var blade: Node3D = j.blade
	blade.rotation_degrees = cur.bl
	# 스윙 순간 칼이 길게 늘어나는 만화적 스미어 (굵기는 살짝 얇아진다)
	var bs := float(cur.bs)
	blade.scale = Vector3(1.0 / sqrt(bs), 1.0 / sqrt(bs), bs)
	var torso: Node3D = j.torso
	torso.rotation = Vector3(float(cur.tx), float(cur.ty), float(cur.tz))
	(j.hip_l as Node3D).rotation.x = float(cur.hl)
	(j.hip_r as Node3D).rotation.x = float(cur.hr)
	(j.knee_l as Node3D).rotation.x = float(cur.kl)
	(j.knee_r as Node3D).rotation.x = float(cur.kr)
	var arm_l: Node3D = j.arm_l
	arm_l.rotation.y = float(cur.al)
	arm_l.rotation.z = -0.2 - maxf(float(cur.lift), 0.0) * 0.35
	p.visual.position.y = Player.PIVOT_Y + p.hover + float(cur.lift)
	var pitch := float(cur.pitch)
	if absf(pitch) > 0.0001:
		var right := dir.cross(Vector3.UP).normalized()
		p.visual.basis = Basis(right, -pitch)
	else:
		p.visual.basis = Basis.IDENTITY
