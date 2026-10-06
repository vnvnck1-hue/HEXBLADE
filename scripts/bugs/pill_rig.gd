class_name PillRig
extends RefCounted
## 공벌레(bug_pillbug.glb) 절차 애니메이션. 관절 회전과 굴림 피벗만 정한다 (판정·이동은 BugPill).
##
##  · 말기 curl 0~1: 이웃 판 사이 관절을 CURL(45°) × curl 만큼 굽힌다. 1 이면 틈 없는 공 (모델이 그렇게 설계됨).
##    다리는 배 쪽으로 접히고 더듬이·꼬리 돌기는 공 안으로 감춘다. 말리는 동안 바닥에 묻히지 않게 몸을 들어 올린다
##    (말림 정도별 최저점을 처음 한 번 메시 정점으로 재 둔다 — _LIFT).
##  · 걷기 speed: 다리 6쌍이 뒤에서 앞으로 번지는 물결(메타크로날 파동)로 움직이고, 몸판이 좌우로 살짝 꿈틀댄다.
##  · 더듬이: 번갈아 바닥을 톡톡 두드리며 좌우를 훑는다 (sniff 중엔 빠르고 낮게).
##  · roll: 공 상태에서 굴러간 각도. 공 중심(pt_ball_center)을 축으로 돈다.
##
## 관절 방향 (Godot 축, 기본 회전 0): 앞쪽 사슬(seg_2→0) rotation.x - = 머리가 아래로 말림 · 뒤쪽 사슬(seg_4→7) + = 꼬리가 아래로
##  다리(옆으로 뻗음): rotation.y × side = 앞으로 · rotation.z × side = 들기 (side: 왼쪽 -1, 오른쪽 +1)

const CURL := TAU / 8.0         ## 다 말렸을 때 관절 하나의 각도 (판 8장 → 45°)
const ARCH := 0.1               ## 평소 등을 굽힌 정도 (관절당 rad) — 원화처럼 둥근 등
const BALL_R := 0.6             ## 공 반지름 (모델 R0)
const LEGS := 6
const SIDES := {"l": -1.0, "r": 1.0}

# ── 입력 ───────────────────────────────────────
var speed := 0.0          ## 기어가는 속도 (m/s)
var turn := 0.0           ## 몸 회전 속도 (rad/s)
var curl := 0.0           ## 0 = 펼침, 1 = 공
var stretch := 0.0        ## 음수 = 등을 뒤로 젖힘(말기 전 반동 · 펼친 직후 기지개), 양수 = 더 웅크림
var roll := 0.0           ## 굴러간 각도 (rad, 공 상태에서만 쓰인다)
var sniff := 0.0          ## 냄새 맡기 0~1: 멈춰서 더듬이로 바닥을 빠르게 두드림
var alarm := 0.0          ## 경계·피격 (1 에서 줄어든다): 다리·더듬이 버둥
var dead_k := 0.0         ## 죽음: 뒤집혀 다리 허우적 → 서서히 반쯤 말림
var emerge_k := 1.0       ## 땅에서 기어 나오는 중 (0 = 땅속)

var model: Node3D
var roller: Node3D
var n := {}
var center := Vector3.ZERO      ## 공 중심 (모델 좌표)
var t := 0.0
var phase := 0.0
var gait := 0.0
var wig := 0.0
var tap := {}                   ## 더듬이마다 두드리기 위상
var tw := {}                    ## 더듬이 경련 [x, y, 남은 시간, 다음]
var rng := RandomNumberGenerator.new()

static var _LIFT: PackedFloat32Array     ## 말림 정도(0, 0.1 … 1)별로 몸을 들어야 하는 높이


func setup(m: Node3D, r: Node3D) -> PillRig:
	model = m
	roller = r
	for i in 8:
		n["seg_%d" % i] = m.find_child("seg_%d" % i, true, false)
	for s: String in SIDES:
		for k in 3:
			n["antenna_%s_%d" % [s, k + 1]] = m.find_child("antenna_%s_%d" % [s, k + 1], true, false)
		for k in 2:
			n["tail_%s_%d" % [s, k + 1]] = m.find_child("tail_%s_%d" % [s, k + 1], true, false)
		for i in range(1, LEGS + 1):
			for k in 2:
				n["leg_%d_%s_%d" % [i, s, k + 1]] = m.find_child("leg_%d_%s_%d" % [i, s, k + 1], true, false)
		tap[s] = rng.randf() * TAU
		tw[s] = [0.0, 0.0, 0.0, rng.randf_range(0.3, 1.2)]
	var bc := m.find_child("pt_ball_center", true, false) as Node3D
	center = _to_model(bc)
	rng.randomize()
	t = rng.randf() * 10.0
	if _LIFT.is_empty():
		_measure_lift()
	roller.position = center
	model.position = -center
	return self


func update(dt: float) -> void:
	t += dt
	alarm = move_toward(alarm, 0.0, dt * 1.5)
	gait = move_toward(gait, clampf(speed / 1.2, 0.0, 1.0) * (1.0 - curl), dt * 5.0)
	phase = fmod(phase + speed * 9.0 * dt, TAU)
	wig = lerpf(wig, clampf(turn * 0.05, -0.12, 0.12), 1.0 - exp(-6.0 * dt))
	var c := clampf(curl, 0.0, 1.0)
	_spine(c)
	_legs(dt, c)
	_antennae(dt, c)
	_tail(c)
	# 굴림 피벗: 공 중심을 축으로, 말린 만큼 바닥에서 들어 올린다
	roller.position = center + Vector3(0, lift_at(c + maxf(0.0, stretch) * 0.3), 0)
	roller.rotation = Vector3(roll * smoothstep(0.75, 1.0, c), 0, 0)


## 등뼈: 판마다 말림 + 평소 굽음 + 걸을 때 뒤에서 앞으로 번지는 꿈틀거림 + 좌우 비틀기
func _spine(c: float) -> void:
	var open := 1.0 - c
	for i in 8:
		if i == 3:
			continue
		var node: Node3D = n["seg_%d" % i]
		var front := i < 3
		var d := (3 - i) if front else (i - 3)          # 루트에서 몇 번째 관절인가 (1~4)
		var wave := sin(phase * 0.5 - i * 0.8) * 0.035 * gait
		var breathe := sin(t * 2.2 - i * 0.5) * 0.012
		var bend := CURL * c + (ARCH + stretch * 0.25 + wave + breathe) * open + dead_k * 0.25 * open
		node.rotation = Vector3(-bend if front else bend, (wig * d * 0.6 + sin(phase * 0.5 - i * 0.9) * 0.03 * gait) * open, 0)
	(n.seg_0 as Node3D).rotation.y += sin(t * 1.3) * 0.06 * open * (1.0 - sniff) + sin(t * 9.0) * 0.04 * sniff * open


func _legs(dt: float, c: float) -> void:
	var open := 1.0 - c
	var flail := maxf(alarm, dead_k) + (1.0 - emerge_k)
	for i in range(1, LEGS + 1):
		for s: String in SIDES:
			var side: float = SIDES[s]
			# 물결: 뒷다리부터 앞다리로 번진다 · 좌우는 반 박자 어긋남
			var ph := phase - (LEGS - i) * 0.85 + (0.0 if s == "l" else PI * 0.5)
			var sw := sin(ph) * 0.38 * gait
			var lift := maxf(0.0, cos(ph)) * 0.35 * gait
			var fl := sin(t * 26.0 + i * 1.7 + side) * 0.45 * flail
			var idle := sin(t * 2.0 + i * 0.9 + side) * 0.05
			var u: Node3D = n["leg_%d_%s_1" % [i, s]]
			var l: Node3D = n["leg_%d_%s_2" % [i, s]]
			# 말리면 배 쪽으로 접어 넣는다 (공 안으로)
			u.rotation = Vector3(0, side * (sw + fl * 0.5 + idle) * open, side * (lift + fl * 0.4) * open - side * c * 1.35)
			l.rotation = Vector3(0, side * fl * 0.3 * open, side * (-lift * 0.6 + fl * 0.5) * open - side * c * 1.2)


func _antennae(dt: float, c: float) -> void:
	var open := 1.0 - c
	for s: String in SIDES:
		var side: float = SIDES[s]
		var a := tw[s] as Array
		a[3] -= dt
		if a[3] <= 0.0:
			a[0] = rng.randf_range(-0.35, 0.3)
			a[1] = rng.randf_range(-0.45, 0.45)
			a[2] = rng.randf_range(0.1, 0.3)
			a[3] = rng.randf_range(0.4, 1.6) * (0.4 if alarm > 0.2 else 1.0)
		if a[2] > 0.0:
			a[2] -= dt
		else:
			a[0] *= exp(-6.0 * dt)
			a[1] *= exp(-6.0 * dt)
		# 두드리기: 끝이 바닥을 톡 치고 튀어 오른다 (|sin| 이라 아래에서 꺾인다). 걷기·냄새 맡기 중 빨라진다
		tap[s] += dt * (3.0 + gait * 4.0 + sniff * 9.0)
		var hit := absf(sin(tap[s] + (0.0 if s == "l" else 1.6)))
		var down := (0.18 + sniff * 0.25) - hit * (0.22 + sniff * 0.2)
		var sweep := sin(t * 1.1 + side) * 0.3 * side + sin(t * 3.7 + side * 2.0) * 0.08
		var fl := sin(t * 29.0 + side) * 0.3 * maxf(alarm, dead_k)
		var a1: Node3D = n["antenna_%s_1" % s]
		var a2: Node3D = n["antenna_%s_2" % s]
		var a3: Node3D = n["antenna_%s_3" % s]
		# 말리면 뒤로 접어 머리 아래(공 안)로 넣는다
		a1.rotation = Vector3((-down + a[0] + fl) * open + c * 0.9, ((sweep + a[1] * side) * open) + side * c * 2.1, side * c * 0.6)
		a2.rotation = Vector3((-hit * 0.18 + sin(t * 4.0 + side) * 0.1 + fl) * open + c * 0.4, side * c * 0.9, 0)
		a3.rotation = Vector3((-hit * 0.25 + sin(t * 5.2 + side) * 0.14) * open + c * 0.6, side * c * 0.6, 0)


func _tail(c: float) -> void:
	var open := 1.0 - c
	for s: String in SIDES:
		var side: float = SIDES[s]
		var t1: Node3D = n["tail_%s_1" % s]
		var t2: Node3D = n["tail_%s_2" % s]
		var flick := sin(t * 2.6 + side * 1.4) * 0.12 + sin(t * 17.0 + side) * 0.06 * alarm
		t1.rotation = Vector3((0.1 + flick) * open + c * 1.4, (side * 0.1 + sin(t * 1.3 + side) * 0.15) * open - side * c * 0.4, 0)
		t2.rotation = Vector3(flick * 0.8 * open + c * 0.6, 0, 0)


## 말림 c 일 때 공 중심을 들어 올릴 높이 (표에서 보간)
func lift_at(c: float) -> float:
	if _LIFT.size() < 2:
		return 0.0          # 표를 아직 못 만들었으면 (메시 정점을 못 읽은 경우) 들지 않는다
	var x := clampf(c, 0.0, 1.0) * (_LIFT.size() - 1)
	var i := mini(int(x), _LIFT.size() - 2)
	return lerpf(_LIFT[i], _LIFT[i + 1], x - i)


## 처음 한 번: 말림 0~1 을 11단계로 놓아 보며 등딱지 정점의 최저 높이를 재고, 바닥 위로 올리는 높이를 표로 만든다
func _measure_lift() -> void:
	var keep := [speed, curl, stretch, gait]
	speed = 0.0
	gait = 0.0
	stretch = 0.0
	var pts: Array = []
	for i in 8:
		var mi := n["seg_%d" % i] as MeshInstance3D
		var picked := PackedVector3Array()
		for sf in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(sf)[Mesh.ARRAY_VERTEX] as PackedVector3Array
			for k in range(0, arr.size(), 3):
				picked.append(arr[k])
		pts.append(picked)
	_LIFT = PackedFloat32Array()
	for step in 11:
		var c := step / 10.0
		_spine(c)
		var low := INF
		for i in 8:
			var xf := _xf_to_model(n["seg_%d" % i] as Node3D)
			for p: Vector3 in pts[i]:
				low = minf(low, (xf * p).y)
		_LIFT.append(maxf(0.0, -low + 0.005))
	speed = keep[0]
	curl = keep[1]
	stretch = keep[2]
	gait = keep[3]


func _xf_to_model(node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != model:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _to_model(node: Node3D) -> Vector3:
	return _xf_to_model(node).origin
