class_name ChomperRig
extends RefCounted
## 촘퍼(bug_chomper.glb) 절차 애니메이션. 판정·이동은 하지 않고 관절만 돌린다 (적 BugChomper · 전시장 BugLab 이 입력을 채운다).
##
## 하찮은 벌레다운 생동감의 요점
##  · 다리 6개: 삼각 지지 걸음(1좌·2우·3좌 / 1우·2좌·3우가 번갈아). 짧고 빠른 보폭 · 발 디딜 때마다 몸이 콩콩 내려앉고 좌우로 뒤뚱.
##    서 있을 때도 다리 하나씩 가끔 꼼지락 들었다 놓는다. 몸이 내려앉거나 기울면 다리를 그만큼 펴서 발이 바닥에 남게 한다.
##  · 갑각 판: 몸의 위아래 가속을 받는 스프링이라 걸을 때 출렁이고, 숨 쉴 때 살짝 들썩, 흥분·준비동작 땐 뒤끝을 쳐든다.
##  · 입: 평소엔 헐떡이듯 반쯤 여닫고, 가끔 이빨을 딱딱 부딪치거나 하품하듯 쩍 벌렸다 닫는다. 혀는 늘 꿈틀.
##  · 머리(차양)는 부드럽게 돌지 않고 짧게 끊어 두리번거린다 (곤충의 시선).
##
## 관절 방향 (Godot 축, 기본 회전 0): head.rotation.x + = 윗턱 들림 · jaw.rotation.x + = 아래턱 닫힘 ·
##  shell_*.rotation.x - = 판 뒤끝이 들림 · pad.rotation.z × side + = 옆 판 벌어짐 ·
##  다리 rotation.y × side + = 앞으로 · 들기는 다리마다 "고관절→발끝 수평 방향 × 위" 축으로 돈다
##  (v2 모델은 앞다리가 앞으로, 뒷다리가 뒤로 뻗어 있어 옆 축(z) 하나로는 발이 안 들린다. 옆으로 뻗은 다리면 예전 z × side 와 같다)

const SIDES := {"l": -1.0, "r": 1.0}
const STRIDE := 0.24          ## 한 걸음 주기에 나아가는 거리 (m) — 짧고 잦은 걸음
const NODES := ["body", "head", "jaw", "tongue", "shell_1", "shell_2", "shell_3", "pad_l", "pad_r"]

# ── 입력 ───────────────────────────────────────
var speed := 0.0          ## 이동 속도 (m/s)
var turn := 0.0           ## 몸 회전 속도 (rad/s, + = 왼쪽)
var look_yaw := 0.0       ## 머리가 볼 방향 (몸 기준 rad)
var windup := 0.0         ## 물기 준비 0~1: 뒤로 웅크림 · 입 쩍 · 판 곤두세움 · 부들부들
var lunge := 0.0          ## 물기 돌진 0~1: 앞으로 쭉 뻗음
var snap := 0.0           ## 입 닫힘 (1 에서 줄어든다 — 적이 "덥석" 순간에 1 로 둔다)
var chew := 0.0           ## 우물우물 (1 에서 줄어든다)
var lick := 0.0           ## 혀로 입가 핥기 (1 에서 줄어든다)
var startle := 0.0        ## 깜짝 (1 에서 줄어든다): 콩 뛰며 다리·판을 쫙 편다
var alarm := 0.0          ## 피격: 판 덜컹 · 다리 버둥 (1 에서 줄어든다)
var dizzy := 0.0          ## 어질어질 0~1: 몸이 빙글빙글 · 혀 축 · 비틀걸음
var air := 0.0            ## 공중 0~1: 다리를 늘어뜨린다
var dead_k := 0.0         ## 죽음: 다리 말아 올리고 따로 움찔 · 혀 늘어짐
var kick_power := 1.0     ## 죽은 뒤 다리 경련 세기
var emerge_k := 1.0       ## 땅에서 기어 나오는 중 (0 = 땅속)

# ── 출력 (적이 소리·체액에 쓰고 끈다) ───────────
var stepped := false      ## 이번 프레임에 발 무리가 디뎠다
var clacked := false      ## 이빨 딱딱 시작
var yawned := false       ## 하품 시작

var n := {}
var rest := {}
var legs: Array = []      ## [upper, lower, side, group, hip(body 좌표), 꼼지락 [값, 남은 시간, 다음], 번호, 들기 축, 고관절→발 수평 거리]
var t := 0.0
var phase := 0.0
var gait := 0.0
var _step_i := 0
var lean := 0.0
var pitch_acc := 0.0
var _prev_speed := 0.0
var _prev_y := 0.0
var _prev_vy := 0.0
var squash := [0.0, 0.0]               ## 눌림 스프링 [값, 속도]
var jig := {}                          ## 판마다 출렁임 스프링 [값, 속도]
var head_yaw := 0.0
var head_goal := 0.0
var head_tilt := 0.0
var tilt_goal := 0.0
var jerk_t := 0.0
var clack_t := 2.0
var clack := 0.0
var yawn_t := 5.0
var yawn := 0.0
var mouth := 0.4                       ## 0 = 모델 그대로(활짝) · 1 = 꽉 닫힘 · 음수 = 더 크게 벌림
var kick := {}
var rng := RandomNumberGenerator.new()


func setup(model: Node3D) -> ChomperRig:
	for k: String in NODES:
		var node := model.find_child(k, true, false) as Node3D
		n[k] = node
		rest[k] = node.position
	rng.randomize()
	t = rng.randf() * 10.0
	clack_t = rng.randf_range(0.8, 2.5)
	yawn_t = rng.randf_range(3.0, 7.0)
	for i in range(1, 4):
		for s: String in SIDES:
			var up := model.find_child("leg_%d_%s_1" % [i, s], true, false) as Node3D
			var lo := model.find_child("leg_%d_%s_2" % [i, s], true, false) as Node3D
			var group := (i + (1 if s == "r" else 0)) % 2
			# 들기 축: 고관절에서 발끝으로 가는 수평 방향 × 위 (+ 회전 = 발끝이 올라감)
			var hip_m: Vector3 = (n.body as Node3D).position + up.position
			var out := foot(model, i, s) - hip_m
			out.y = 0.0
			var axis := out.normalized().cross(Vector3.UP)
			legs.append([up, lo, SIDES[s], group, up.position, [0.0, 0.0, rng.randf_range(0.3, 2.5)], i, axis, maxf(out.length(), 0.08)])
			kick["%d%s" % [i, s]] = [0.0, 0.0, rng.randf_range(0.0, 0.3)]
	for k in ["shell_1", "shell_2", "shell_3", "pad_l", "pad_r"]:
		jig[k] = [0.0, 0.0]
	_prev_y = rest.body.y
	return self


func update(dt: float) -> void:
	if dt <= 0.0:
		return
	t += dt
	stepped = false
	clacked = false
	yawned = false
	snap = move_toward(snap, 0.0, dt * 2.2)
	chew = move_toward(chew, 0.0, dt * 1.4)
	lick = move_toward(lick, 0.0, dt * 1.3)
	startle = move_toward(startle, 0.0, dt * 2.0)
	alarm = move_toward(alarm, 0.0, dt * 1.8)
	var alive_k := 1.0 - dead_k
	gait = move_toward(gait, clampf(absf(speed) / 1.1, 0.0, 1.0) * (1.0 - air) * alive_k, dt * 7.0)
	phase += speed / STRIDE * TAU * dt
	var si := int(floor(phase / PI))
	if si != _step_i:
		_step_i = si
		if gait > 0.3:
			stepped = true
			_kick_squash(0.35 * gait)
	# 가속하면 뒤로 젖혀졌다, 멈추면 앞으로 쏠린다 (관성)
	var acc := (speed - _prev_speed) / dt
	_prev_speed = speed
	pitch_acc = lerpf(pitch_acc, clampf(acc * 0.012, -0.12, 0.12), 1.0 - exp(-10.0 * dt))
	lean = lerpf(lean, clampf(turn * 0.05, -0.18, 0.18), 1.0 - exp(-8.0 * dt))
	_body(dt)
	_plates(dt)
	_mouth(dt)
	_head(dt)
	_legs(dt, alive_k)


func _kick_squash(v: float) -> void:
	squash[1] += v * 9.0


# ── 몸통 ───────────────────────────────────────

func _body(dt: float) -> void:
	var body: Node3D = n.body
	var breath := sin(t * 2.6)
	# 걸음: 반 주기마다 한 번씩 콩 내려앉는다 · 좌우 뒤뚱
	var bob := (absf(cos(phase)) - 0.7) * 0.028 * gait
	var crouch := windup * 0.075 + alarm * 0.02 + dead_k * 0.0
	var hop_k := 1.0 - startle
	var hop := sin(clampf(hop_k / 0.55, 0.0, 1.0) * PI) * 0.17 if startle > 0.0 else 0.0
	var dz := sin(t * 5.2) * 0.04 * dizzy
	var tremble := sin(t * 63.0) * 0.008 * smoothstep(0.5, 1.0, windup)
	body.position = rest.body + Vector3(tremble + sin(t * 4.0) * 0.03 * dizzy,
		bob - crouch + hop + breath * 0.006, windup * 0.07 - lunge * 0.09 + dz)
	body.rotation = Vector3(
		windup * 0.2 - lunge * 0.26 - pitch_acc + breath * 0.012 + startle * 0.15 + cos(t * 5.2) * 0.12 * dizzy,
		sin(phase) * 0.07 * gait + sin(t * 3.3) * 0.12 * dizzy,
		sin(phase) * 0.075 * gait + lean + sin(t * 5.2) * 0.14 * dizzy + sin(t * 41.0) * 0.05 * alarm)
	# 눌림: 숨쉬기 · 걸음 착지 · 덥석 충격을 스프링으로 받는다
	squash[1] += (-squash[0] * 260.0 - squash[1] * 12.0) * dt
	squash[0] += squash[1] * dt
	var q := clampf(squash[0], -0.2, 0.2) + breath * 0.018 + windup * 0.06
	body.scale = Vector3(1.0 + q * 0.6, 1.0 - q, 1.0 + q * 0.4)


# ── 갑각 판: 숨쉬기 + 흥분 + 출렁임 스프링 ─────

func _plates(dt: float) -> void:
	var body: Node3D = n.body
	var vy := (body.position.y - _prev_y) / dt
	var ay := clampf((vy - _prev_vy) / dt, -60.0, 60.0)
	_prev_y = body.position.y
	_prev_vy = vy
	var breath := sin(t * 2.6)
	var flare := windup * 0.24 + startle * 0.3 + breath * 0.02 + dead_k * 0.15 + 0.05 * dizzy
	var i := 0
	for k: String in jig:
		var s: Array = jig[k]
		# 몸이 아래로 꺼지면(가속 -) 판은 관성으로 들린다 · 뒤 판일수록 늦고 크게
		s[1] += (-s[0] * (320.0 - i * 40.0) - s[1] * 9.0 - ay * 0.012) * dt
		s[0] += s[1] * dt
		i += 1
	var rattle := func(seed: float) -> float: return sin(t * 57.0 + seed) * 0.05 * alarm + sin(t * 37.0 + seed) * 0.015 * smoothstep(0.6, 1.0, windup)
	(n.shell_1 as Node3D).rotation = Vector3(-(flare * 0.45 + jig.shell_1[0] * 0.6 + rattle.call(0.0)), 0, 0)
	(n.shell_2 as Node3D).rotation = Vector3(-(flare * 0.55 + jig.shell_2[0] * 0.8 + sin(t * 2.6 - 0.6) * 0.012 + rattle.call(1.7)), 0, 0)
	(n.shell_3 as Node3D).rotation = Vector3(-(flare * 0.6 + jig.shell_3[0] + sin(t * 2.6 - 1.2) * 0.015 + rattle.call(3.1)), 0, 0)
	for k: String in ["pad_l", "pad_r"]:
		var side := -1.0 if k == "pad_l" else 1.0
		var swing := sin(phase + side * 0.8) * 0.05 * gait
		(n[k] as Node3D).rotation = Vector3(0, 0, side * (flare * 0.7 + jig[k][0] * 0.9 + swing + rattle.call(side * 2.3)))


# ── 입 · 혀 ────────────────────────────────────

func _mouth(dt: float) -> void:
	# 평소: 헐떡임 (서 있을 땐 숨에 맞춰, 걸을 땐 걸음에 맞춰 덜렁덜렁)
	var pant := 0.42 + sin(t * 2.6 + 0.6) * 0.2
	var flap := 0.5 + sin(phase * 2.0) * 0.28
	var goal := lerpf(pant, flap, gait)
	# 이빨 딱딱: 가끔 빠르게 서너 번
	clack_t -= dt
	if clack_t <= 0.0 and windup < 0.1 and dead_k == 0.0:
		clack_t = rng.randf_range(1.4, 4.0)
		clack = 1.0
		clacked = true
	clack = move_toward(clack, 0.0, dt * 2.6)
	goal += maxf(0.0, sin(clack * 26.0)) * clack * 0.9
	# 하품: 쩍 벌렸다가 딱 닫는다 (서 있을 때만)
	yawn_t -= dt * (1.0 - gait)
	if yawn_t <= 0.0 and windup < 0.1 and dead_k == 0.0:
		yawn_t = rng.randf_range(5.0, 10.0)
		yawn = 1.0
		yawned = true
	yawn = move_toward(yawn, 0.0, dt * 0.9)
	if yawn > 0.0:
		var yk := 1.0 - yawn
		goal = lerpf(goal, -0.9, sin(clampf(yk / 0.8, 0.0, 1.0) * PI)) + (0.6 if yk > 0.85 else 0.0)
	goal = lerpf(goal, -1.0, smoothstep(0.0, 0.6, windup))               # 준비: 최대로 쩍
	goal = lerpf(goal, 0.2 + sin(t * 3.0) * 0.25, dizzy)                 # 어질: 헤벌레
	goal += maxf(0.0, sin(chew * 20.0)) * chew * 0.7                      # 우물우물
	goal = lerpf(goal, 1.15, clampf(snap * 1.6, 0.0, 1.0))                # 덥석: 꽉
	goal = lerpf(goal, -0.35, dead_k)
	# 닫힐 땐 빠르게, 열릴 땐 조금 느리게
	var rate := 40.0 if goal > mouth else 16.0
	mouth = lerpf(mouth, goal, 1.0 - exp(-rate * dt))
	var head: Node3D = n.head
	var jaw: Node3D = n.jaw
	head.rotation.x = -0.17 * mouth
	jaw.rotation.x = 0.3 * mouth if mouth > 0.0 else 0.06 * mouth
	jaw.rotation.z = sin(chew * 20.0) * 0.05 * chew
	# 혀: 늘 꿈틀 · 핥기 · 어질/죽음엔 축 늘어져 밖으로 · 입이 닫히면 안으로
	var tongue: Node3D = n.tongue
	var lk := 1.0 - lick
	var lick_on := lick > 0.0
	var out := (sin(clampf(lk, 0.0, 1.0) * PI) * 0.11 if lick_on else 0.0) + dizzy * 0.06 + dead_k * 0.08
	out *= 1.0 - smoothstep(0.6, 1.0, mouth)
	tongue.position = rest.tongue + Vector3(0, 0, -out)
	tongue.rotation = Vector3(
		sin(t * 4.3) * 0.08 + (sin(lk * TAU * 2.0) * 0.35 if lick_on else 0.0) - dizzy * 0.3 - dead_k * 0.35 + windup * 0.15,
		sin(t * 2.9) * 0.12 + (sin(lk * TAU) * 0.45 if lick_on else 0.0) + sin(t * 2.0) * 0.3 * dizzy,
		sin(t * 3.7) * 0.06)


# ── 머리: 짧게 끊어 두리번 ─────────────────────

func _head(dt: float) -> void:
	jerk_t -= dt
	if jerk_t <= 0.0:
		jerk_t = rng.randf_range(0.25, 0.9) * (0.5 if alarm > 0.2 or startle > 0.2 else 1.0)
		var wander := rng.randf_range(-0.22, 0.22) if rng.randf() < 0.6 else 0.0
		head_goal = clampf(look_yaw * 0.45 + wander, -0.28, 0.28)
		tilt_goal = rng.randf_range(-0.08, 0.08)
	head_yaw = lerpf(head_yaw, head_goal * (1.0 - windup * 0.8), 1.0 - exp(-28.0 * dt))
	head_tilt = lerpf(head_tilt, tilt_goal, 1.0 - exp(-20.0 * dt))
	var head: Node3D = n.head
	head.rotation.y = head_yaw + sin(t * 3.0) * 0.1 * dizzy
	head.rotation.z = head_tilt - lean * 0.5 + sin(t * 47.0) * 0.03 * alarm


# ── 다리 ───────────────────────────────────────

func _legs(dt: float, alive_k: float) -> void:
	var body: Node3D = n.body
	var bxf := body.transform
	var rest_xf := Transform3D(Basis.IDENTITY, rest.body)
	for L: Array in legs:
		var up: Node3D = L[0]
		var lo: Node3D = L[1]
		var side: float = L[2]
		var hip: Vector3 = L[4]
		var fid: Array = L[5]
		var idx: int = L[6]
		var ph := phase + float(L[3]) * PI
		# 삼각 지지 걸음: 들고 앞으로 · 디디고 뒤로 민다
		var sw := sin(ph) * 0.42 * gait
		var lift := maxf(0.0, cos(ph)) * 0.6 * gait
		# 꼼지락: 서 있을 때 다리 하나씩 가끔 들었다 톡 놓는다
		fid[2] -= dt * (1.0 - gait)
		if fid[2] <= 0.0:
			fid[2] = rng.randf_range(0.8, 3.0)
			fid[1] = 0.22
		if fid[1] > 0.0:
			fid[1] -= dt
			fid[0] = sin((1.0 - fid[1] / 0.22) * PI) * 0.45
		else:
			fid[0] = 0.0
		lift += fid[0] * (1.0 - gait)
		# 몸이 내려앉거나 기울어 고관절이 내려간 만큼 다리를 들어 발을 바닥에 둔다 (펴짐 보정)
		var dy := (bxf * hip).y - (rest_xf * hip).y
		var comp := clampf(-dy / float(L[8]), -0.6, 0.6) * (1.0 - air) * alive_k
		# 깜짝·준비동작: 다리를 쫙 벌려 버틴다 · 앞다리는 땅을 판다
		var brace := startle * 0.35 + windup * 0.12
		var dig := windup * (0.25 if idx == 1 else -0.1) + sin(t * 50.0 + idx) * 0.06 * smoothstep(0.5, 1.0, windup)
		var scramble := sin(t * 31.0 + idx * 2.1 + side) * 0.35 * alarm + sin(t * 23.0 + idx + side * 2.0) * 0.6 * (1.0 - emerge_k)
		var stumble := sin(t * 7.0 + idx * 1.9 + side) * 0.3 * dizzy
		var dangle := air * (-0.35 + sin(t * 18.0 + idx + side) * 0.1)
		var k: Array = kick["%d%s" % [idx, "l" if side < 0 else "r"]]
		var dead_up: float = dead_k * (1.2 + float(k[0]))
		var axis: Vector3 = L[7]
		up.basis = Basis(Vector3.UP, side * ((sw + dig + stumble + scramble * 0.5) * alive_k + dead_k * k[0] * 0.5)) 			* Basis(axis, (lift + comp - brace + dangle + scramble * 0.4) * alive_k + dead_up)
		lo.basis = Basis(Vector3.UP, side * scramble * 0.2 * alive_k) 			* Basis(axis, (-lift * 0.55 + brace * 0.6 - air * 0.4 + scramble * 0.3) * alive_k - dead_k * (1.1 + k[0] * 0.6))
	if dead_k > 0.0:
		_kicks(dt)


## 죽은 벌레: 다리마다 따로 불규칙하게 움찔 차올린다 (kick_power 로 잦아든다)
func _kicks(dt: float) -> void:
	for key: String in kick:
		var v: Array = kick[key]
		v[2] -= dt
		if v[2] <= 0.0:
			v[2] = rng.randf_range(0.07, 0.3)
			v[1] += rng.randf_range(-10.0, 10.0) * kick_power
		v[1] += (-v[0] * 200.0 - v[1] * 9.0) * dt
		v[0] += v[1] * dt


## 발 끝 (모델 좌표) — 테스트·체액 위치용
func foot(model: Node3D, i: int, s: String) -> Vector3:
	var pt := model.find_child("pt_foot_%d_%s" % [i, s], true, false) as Node3D
	var xf := Transform3D.IDENTITY
	var cur: Node = pt
	while cur != null and cur != model:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf.origin
