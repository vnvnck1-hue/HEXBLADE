class_name AntRig
extends RefCounted
## 개미 병정(bug_ant.glb) 절차 애니메이션. 판정·이동은 하지 않고 관절 회전만 정한다.
## 적(BugAnt)이나 전시장(BugLab)이 매 프레임 입력 값을 채우고 update(dt) 를 부른다.
##
## 벌레다운 움직임의 요점
##  · 더듬이: 느린 탐색 흔들림 + 불규칙한 "톡" 경련(빠른 스프링이라 끝이 휘청이며 따라온다) · 세 마디가 시간차로 휜다
##  · 머리: 부드럽게 돌지 않고 짧게 끊어 꺾는다 (곤충의 시선 이동)
##  · 걸음: 빠르고 짧은 보폭, 멈췄다 달렸다 · 가운데 다리는 쉬지 않고 허공을 휘젓는다 · 큰턱은 가끔 딸깍거린다
##  · 배: 숨쉬듯 부풀고, 산을 쏠 때는 다리 사이로 말아 앞으로 겨눈다
##
## 관절 회전 방향 (Godot 축, 모든 파츠의 기본 회전은 0):
##  다리·팔: rotation.x + = 앞으로 휘두름 · 정강이 rotation.x - = 무릎 접힘
##  더듬이 밑마디: rotation.x + = 뒤로 젖힘, rotation.z (왼쪽 +) = 바깥으로 벌림
##  배: rotation.x + = 끝이 아래(→ 다리 사이 앞으로) · 큰턱: rotation.y (왼쪽 +) = 벌림

# ── 입력 ───────────────────────────────────────
var speed := 0.0          ## 실제 이동 속도 (m/s)
var turn := 0.0           ## 몸 회전 속도 (rad/s, + = 왼쪽) → 몸 기울임
var look_yaw := 0.0       ## 머리가 볼 방향 (몸 기준, rad)
var acid_k := 0.0         ## 산 발사 준비 0~1: 배를 다리 사이로 말아 앞으로 · 몸을 뒤로 젖힘
var fire_k := 0.0         ## 발사 반동 (1 에서 시작해 줄어든다)
var bite_k := 0.0         ## 물기 준비 0~1: 웅크림 · 큰턱 활짝 · 집게 팔 들기
var lunge_k := 0.0        ## 물기 돌진 0~1: 앞으로 쭉 뻗고 큰턱을 닫는다
var alarm := 0.0          ## 경계·피격: 더듬이·다리 버둥 (1 에서 줄어든다)
var dead_k := 0.0         ## 죽음: 다리를 배 쪽으로 말아 올리고 경련
var emerge_k := 1.0       ## 땅에서 기어 나오는 중 (0 = 땅속) — 다리를 허우적댄다
var kick_power := 1.0
var clicked := false      ## 이번 프레임에 큰턱 딸깍이 시작됐다 (적이 소리를 내고 끈다)     ## 죽은 뒤 다리 경련 세기 (적이 시간에 따라 줄인다)

const RIG_NODES := ["pelvis", "thorax", "head", "gaster_1", "gaster_2", "mandible_l", "mandible_r",
	"antenna_l_1", "antenna_l_2", "antenna_l_3", "antenna_r_1", "antenna_r_2", "antenna_r_3",
	"arm_l_upper", "arm_l_fore", "arm_l_claw", "arm_r_upper", "arm_r_fore", "arm_r_claw",
	"mid_l_upper", "mid_l_lower", "mid_r_upper", "mid_r_lower",
	"leg_l_thigh", "leg_l_shin", "leg_l_foot", "leg_r_thigh", "leg_r_shin", "leg_r_foot"]
const STRIDE := 0.42      ## 한 걸음 길이 (m) — 짧고 잦은 걸음
const SIDES := {"l": -1.0, "r": 1.0}

var n := {}
var rest := {}            ## 파츠 기본 위치
var t := 0.0
var phase := 0.0
var gait := 0.0
var head_yaw := 0.0
var head_goal := 0.0
var head_pitch_goal := 0.0
var head_pitch := 0.0
var jerk_t := 0.0
var chat_t := 1.0         ## 다음 큰턱 딸깍까지
var chat := 0.0
var lean := 0.0
## 더듬이: 쪽마다 [x, vx, y, vy, z, vz] 스프링 + 경련 목표·남은 시간
var ant := {}
var twitch := {}
## 죽음 경련: 다리마다 [값, 속도]
var kick := {}
var rng := RandomNumberGenerator.new()


func setup(model: Node3D) -> AntRig:
	for k: String in RIG_NODES:
		var node := model.find_child(k, true, false) as Node3D
		n[k] = node
		rest[k] = node.position if node else Vector3.ZERO
	rng.randomize()
	t = rng.randf() * 10.0
	for s: String in SIDES:
		ant[s] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		twitch[s] = {"x": 0.0, "y": 0.0, "z": 0.0, "hold": 0.0, "next": rng.randf_range(0.2, 1.0)}
	for k in ["leg_l", "leg_r", "mid_l", "mid_r", "arm_l", "arm_r"]:
		kick[k] = [0.0, 0.0, rng.randf_range(0.0, 0.3)]
	return self


func update(dt: float) -> void:
	t += dt
	fire_k = move_toward(fire_k, 0.0, dt * 3.0)
	alarm = move_toward(alarm, 0.0, dt * 1.6)
	# 걸음: 보폭만큼 갈 때마다 한 주기. 느리면 섞기를 줄여 제자리 자세로.
	gait = move_toward(gait, clampf(speed / 2.5, 0.0, 1.0), dt * 8.0)
	phase = fmod(phase + speed / STRIDE * PI * dt, TAU)
	lean = lerpf(lean, clampf(turn * 0.08, -0.25, 0.25), 1.0 - exp(-8.0 * dt))
	var ease_acid := _smooth(acid_k)
	var ease_bite := _smooth(bite_k)
	var alive_k := 1.0 - dead_k

	_body(dt, ease_acid, ease_bite)
	_head(dt, ease_acid, ease_bite)
	_antennae(dt, ease_acid, ease_bite)
	_mandibles(dt, ease_bite)
	_legs(dt, ease_acid, ease_bite, alive_k)
	_arms(dt, ease_bite, alive_k)


# ── 몸통 · 배 ─────────────────────────────────

func _body(dt: float, acid: float, bite: float) -> void:
	var pelvis: Node3D = n.pelvis
	var thorax: Node3D = n.thorax
	var g1: Node3D = n.gaster_1
	var g2: Node3D = n.gaster_2
	# 걸음마다 두 번 통통 튀고 (발 디딜 때 내려앉음) 좌우로 비튼다
	var bob := -absf(sin(phase)) * 0.045 * gait + 0.012 * sin(t * 2.2)
	var crouch := bite * 0.16 - lunge_k * 0.06 + acid * 0.04
	pelvis.position = rest.pelvis + Vector3(0, bob - crouch, 0)
	pelvis.rotation = Vector3(-0.08 * gait + bite * 0.12 - lunge_k * 0.3, sin(phase) * 0.12 * gait, lean)
	# 가슴: 달릴수록 앞으로 숙이고, 산을 쏠 땐 뒤로 젖혀 배를 앞으로 내민다
	var kick_back := fire_k * 0.25
	thorax.rotation = Vector3(-0.18 * gait + acid * 0.38 + kick_back - bite * 0.2 - lunge_k * 0.35,
		-sin(phase) * 0.1 * gait, -lean * 0.5)
	# 배: 숨쉬기 (부풀고 꺼짐) + 걸음 반동 + 산 발사 자세
	var breathe := sin(t * 3.1)
	g1.rotation = Vector3(-0.1 + sin(phase * 2.0) * 0.05 * gait + acid * 1.35 - fire_k * 0.3 + sin(t * 1.3) * 0.04,
		sin(t * 0.9) * 0.06 + sin(phase) * 0.08 * gait, 0)
	g2.rotation = Vector3(acid * 0.55 - fire_k * 0.25 + sin(t * 1.3 - 0.5) * 0.05, sin(t * 0.9 - 0.4) * 0.05, 0)
	g2.scale = Vector3.ONE * (1.0 + breathe * 0.035 + acid * 0.06 + fire_k * 0.1)
	if acid > 0.6:
		# 발사 직전: 배 끝이 떨린다
		g2.rotation.y += sin(t * 70.0) * 0.04 * (acid - 0.6) * 2.5


# ── 머리 ───────────────────────────────────────

func _head(dt: float, acid: float, bite: float) -> void:
	var head: Node3D = n.head
	# 곤충의 시선: 목표 방향으로 짧게 끊어 꺾는다 (가끔 엉뚱한 쪽을 한 번 보고 돌아온다)
	jerk_t -= dt
	if jerk_t <= 0.0:
		jerk_t = rng.randf_range(0.18, 0.7) * (0.5 if alarm > 0.2 else 1.0)
		var wander := rng.randf_range(-0.35, 0.35) if rng.randf() < 0.55 else 0.0
		head_goal = clampf(look_yaw * 0.7 + wander, -0.7, 0.7)
		head_pitch_goal = rng.randf_range(-0.12, 0.15)
	head_yaw = lerpf(head_yaw, head_goal, 1.0 - exp(-30.0 * dt))
	head_pitch = lerpf(head_pitch, head_pitch_goal, 1.0 - exp(-24.0 * dt))
	var tremble := sin(t * 47.0) * 0.02 * alarm
	head.rotation = Vector3(head_pitch * (1.0 - bite) - bite * 0.3 + acid * 0.2 + lunge_k * 0.25 - dead_k * 0.4 + tremble,
		head_yaw * (1.0 - bite * 0.7) + tremble, -lean * 0.4 + sin(t * 1.7) * 0.03)


# ── 더듬이 ─────────────────────────────────────

func _antennae(dt: float, acid: float, bite: float) -> void:
	for s: String in SIDES:
		var side: float = SIDES[s]
		var tw: Dictionary = twitch[s]
		# 경련: 이따금 한쪽 더듬이를 톡 튕겨 잠깐 그 자리에 멈춘다 (경계 중엔 더 잦고 크다)
		tw.next -= dt
		if tw.next <= 0.0:
			var big := 1.0 + alarm * 1.5
			tw.x = rng.randf_range(-0.55, 0.35) * big
			tw.y = rng.randf_range(-0.5, 0.5) * big
			tw.z = rng.randf_range(-0.2, 0.35) * big
			tw.hold = rng.randf_range(0.08, 0.3)
			tw.next = rng.randf_range(0.25, 1.4) * (0.35 if alarm > 0.2 else 1.0)
		if tw.hold > 0.0:
			tw.hold -= dt
		else:
			var dec := exp(-5.0 * dt)
			tw.x *= dec
			tw.y *= dec
			tw.z *= dec
		# 기본 자세: 앞을 더듬는 느린 흔들림 · 달리면 뒤로 눕힘 · 공격 준비 땐 바짝 젖힘
		var ph := t * 1.9 + side * 1.3
		var gx := sin(ph) * 0.18 + sin(ph * 2.7) * 0.06 + gait * 0.35 + acid * 0.55 + bite * 0.65 - lunge_k * 0.3
		var gy := sin(ph * 0.8 + 0.7) * 0.22 * side
		var gz := (0.08 + bite * 0.2 + dead_k * 0.4) * -side
		var flail := alarm * sin(t * 31.0 + side) * 0.35
		var a: Array = ant[s]
		_spring(a, 0, gx + tw.x + flail, 260.0, 16.0, dt)
		_spring(a, 2, gy + tw.y * side, 260.0, 16.0, dt)
		_spring(a, 4, -gz + tw.z * -side, 200.0, 14.0, dt)
		var a1: Node3D = n["antenna_%s_1" % s]
		var a2: Node3D = n["antenna_%s_2" % s]
		var a3: Node3D = n["antenna_%s_3" % s]
		a1.rotation = Vector3(a[0], a[2], a[4])
		# 바깥 마디는 밑마디 속도의 반대로 휘었다 따라온다 (채찍처럼)
		var whip := Vector3(-a[1], -a[3], -a[5]) * 0.022
		var sway := sin(t * 3.3 + side * 2.0) * 0.12
		a2.rotation = Vector3(-0.1 + whip.x + sway * 0.5 - dead_k * 0.5, whip.y + sway * side, whip.z) + Vector3(0, 0, -side * 0.05)
		a3.rotation = Vector3(whip.x * 1.4 + sin(t * 4.1 + side) * 0.14 - dead_k * 0.4, whip.y * 1.3, whip.z * 1.2)


# ── 큰턱 ───────────────────────────────────────

func _mandibles(dt: float, bite: float) -> void:
	chat_t -= dt
	if chat_t <= 0.0:
		chat_t = rng.randf_range(0.6, 2.4)
		chat = 1.0
		clicked = true
	chat = move_toward(chat, 0.0, dt * 2.5)
	# 딸깍딸깍 두세 번 (빠른 사인 × 감쇠) · 물기 준비는 활짝 · 돌진하면 꽉 닫는다
	var click := maxf(0.0, sin(chat * 18.0)) * chat * 0.35
	var open := click + bite * 0.75 + sin(t * 2.0) * 0.03 + alarm * 0.2 * maxf(0.0, sin(t * 25.0)) - lunge_k * 0.25
	(n.mandible_l as Node3D).rotation = Vector3(0, open, 0)
	(n.mandible_r as Node3D).rotation = Vector3(0, -open, 0)


# ── 다리 ───────────────────────────────────────

func _legs(dt: float, acid: float, bite: float, alive_k: float) -> void:
	for s: String in SIDES:
		var side: float = SIDES[s]
		var ph := phase + (0.0 if s == "l" else PI)
		var sw := sin(ph)
		var lift := maxf(0.0, cos(ph))            # 다리를 앞으로 가져가는 동안 든다
		var thigh: Node3D = n["leg_%s_thigh" % s]
		var shin: Node3D = n["leg_%s_shin" % s]
		var foot: Node3D = n["leg_%s_foot" % s]
		var squat := bite * 0.55 + acid * 0.2 - lunge_k * 0.3
		var em := (1.0 - emerge_k) * sin(t * 22.0 + side * 1.5) * 0.6       # 땅에서 빠져나오며 허우적
		var k: Array = kick["leg_" + s]
		var dead_x: float = dead_k * (1.1 + k[0])
		thigh.rotation = Vector3((sw * 0.55 * gait + squat * 0.6 + em) * alive_k + dead_x, 0, side * (0.04 + dead_k * 0.25) - lean * 0.3)
		shin.rotation = Vector3((-lift * 0.85 * gait - squat * 1.0 - absf(em) * 0.6) * alive_k - dead_k * (1.5 + k[0] * 0.6), 0, 0)
		foot.rotation = Vector3((lift * 0.55 * gait + squat * 0.45 - sw * 0.15 * gait) * alive_k + dead_k * 0.9, 0, 0)
		# 가운데 다리: 쉬지 않고 허공을 짧게 휘젓는다 (걸을 땐 노 젓듯 크게)
		var mu: Node3D = n["mid_%s_upper" % s]
		var ml: Node3D = n["mid_%s_lower" % s]
		var mk: Array = kick["mid_" + s]
		var paddle := sin(phase * 1.0 + side * 0.8 + PI * 0.5) * 0.5 * gait + sin(t * 9.0 + side * 2.0) * 0.08 + alarm * sin(t * 28.0 + side) * 0.4
		mu.rotation = Vector3((paddle + em * 0.7) * alive_k + dead_k * (0.6 + mk[0]), side * 0.1, side * (0.15 + bite * 0.3) * alive_k + side * dead_k * 0.5)
		ml.rotation = Vector3((-0.2 + sin(t * 9.0 + side * 2.0 - 0.6) * 0.1 - paddle * 0.4) * alive_k - dead_k * (1.0 + mk[0] * 0.7), 0, 0)
	if dead_k > 0.0:
		_kicks(dt)


## 죽은 벌레: 다리마다 따로 불규칙하게 움찔 차올린다 (점점 약해진다)
func _kicks(dt: float) -> void:
	var weak := kick_power
	for k: String in kick:
		var v: Array = kick[k]
		v[2] -= dt
		if v[2] <= 0.0:
			v[2] = rng.randf_range(0.08, 0.35)
			v[1] += rng.randf_range(-9.0, 9.0) * weak
		v[1] += (-v[0] * 180.0 - v[1] * 9.0) * dt
		v[0] += v[1] * dt


# ── 팔 (앞다리 집게) ───────────────────────────

func _arms(dt: float, bite: float, alive_k: float) -> void:
	for s: String in SIDES:
		var side: float = SIDES[s]
		var up: Node3D = n["arm_%s_upper" % s]
		var fo: Node3D = n["arm_%s_fore" % s]
		var cl: Node3D = n["arm_%s_claw" % s]
		var ph := phase + (PI if s == "l" else 0.0)
		var k: Array = kick["arm_" + s]
		var idle := sin(t * 1.4 + side) * 0.06 + sin(t * 11.0 + side * 3.0) * 0.025
		var swing := sin(ph) * 0.3 * gait
		var raise := bite * 1.1 - lunge_k * 0.6 + fire_k * 0.2
		up.rotation = Vector3((swing + raise + idle + alarm * sin(t * 26.0 + side) * 0.3) * alive_k + dead_k * (0.4 + k[0]),
			side * (0.1 + bite * 0.35 - lunge_k * 0.25) * alive_k, side * (0.1 + bite * 0.25) * alive_k + side * dead_k * 0.6)
		fo.rotation = Vector3((-0.15 + bite * 0.6 - lunge_k * 0.5 + idle * 0.5) * alive_k - dead_k * (1.2 + k[0] * 0.5), 0, 0)
		cl.rotation = Vector3((0.2 * bite + lunge_k * 0.6 + sin(t * 7.0 + side) * 0.05) * alive_k - dead_k * 0.8, 0, 0)


# ── 도우미 ─────────────────────────────────────

static func _smooth(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


## 2차 스프링 한 자유도: a[i] = 값, a[i+1] = 속도
static func _spring(a: Array, i: int, goal: float, stiff: float, damp: float, dt: float) -> void:
	a[i + 1] += ((goal - a[i]) * stiff - a[i + 1] * damp) * dt
	a[i] += a[i + 1] * dt
