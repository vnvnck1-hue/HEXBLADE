class_name GrubRig
extends RefCounted
## 애벌레(bug_grub.glb) 절차 애니메이션. 판정·이동은 하지 않고 몸 모양만 만든다 (적 BugGrub · 전시장 BugLab 이 입력을 채운다).
##
## 몸통은 통짜 메시라 처음에 몸 길이 방향으로 뼈 NB 개를 박아 스키닝한다 (뼈마다 부모 없음, 이차 B-스플라인 가중치라
## 뼈 사이가 매끈하게 이어진다). 매 프레임 뼈마다 앞뒤 위치 · 들림 · 기울기 · 굵기(폭·높이·길이 배율)를 따로 정한다.
##
## 진짜 애벌레처럼 기는 요점 (연동 운동, peristalsis)
##  · 한 주기 동안 꼬리 고리부터 차례로 앞으로 옮겨 간다. 아직 안 옮긴 앞 고리는 바닥을 붙잡고 있어서
##    그 사이 몸이 쭈욱 줄어들고(수축 물결이 꼬리 → 머리로 번짐), 마지막에 머리가 내밀리며 다시 늘어난다(이완).
##  · 바닥을 붙잡은 고리는 월드에서 미끄러지지 않는다: 몸 중심(적 원점)은 일정 속도로 가고,
##    고리 i 의 상대 위치 = STRIDE · (진행도_i − 주기 진행도) 라서 붙잡은 동안엔 월드 위치가 그대로다.
##  · 옮기는 중인 고리는 살짝 들리고(혹), 줄어든 구간은 부피를 지키듯 높고 굵게 부푼다 · 늘어난 구간은 가늘고 납작해진다.
##  · 돌 때는 몸이 지나온 길을 따라 활처럼 휜다 (머리는 도는 쪽으로, 꼬리는 반대로).
##  · 머리는 매 주기 끝에 앞으로 쑥 내밀어 더듬고, 서 있을 땐 앞몸을 들어 좌우로 두리번거린다.
##  · 더듬이 3마디: 뿌리 → 끝으로 갈수록 무른 스프링이라 채찍처럼 늦게 따라온다. 기는 동안 번갈아 좌우를 쓸고,
##    서 있으면 번갈아 바닥을 톡톡 두드리고, 가끔 혼자 움찔. 공격 준비 땐 활짝 벌려 떨고 덥석 때 집게처럼 오므린다.
##
## 축 (Godot): 앞 = -Z, 왼쪽 = -X. 뼈 0 = 꼬리, NB-1 = 머리. 회전 yaw + = 왼쪽, pitch + = 앞이 들림.

const NB := 9
const SPAN := 1.2              ## 첫 뼈(꼬리) ~ 끝 뼈(머리) 거리. 메시 길이 1.36
const STRIDE := 0.34           ## 한 주기에 나아가는 거리 (m) — 몸 길이의 25% 만큼 줄었다 늘어난다
const WAVE := 0.72             ## 고리 하나가 움직이는 시간 비율 (클수록 몸 전체가 함께 줄고 늘어난다)
const HUMP := 0.07             ## 옮기는 고리가 들리는 높이
const HEAD_REST := Vector3(0.0, 0.12, -0.45)
const FEELER_K := [150.0, 95.0, 60.0]       ## 더듬이 마디별 스프링 세기 (끝으로 갈수록 무름)
const FEELER_D := [16.0, 11.0, 8.0]

# ── 입력 ───────────────────────────────────────
var speed := 0.0          ## 이동 속도 (m/s, 몸 중심)
var turn := 0.0           ## 몸 회전 속도 (rad/s, + = 왼쪽)
var look_yaw := 0.0       ## 머리가 볼 방향 (몸 기준 rad)
var windup := 0.0         ## 공격 준비 0~1: 몸을 꼬리 쪽으로 바짝 움츠려 앞몸을 쳐들고 · 더듬이 활짝 · 부들부들
var lunge := 0.0          ## 공격 돌진 0~1: 몸을 앞으로 확 늘이며 앞몸을 내리찍는다
var bite := 0.0           ## 덥석 (1 에서 줄어든다): 더듬이가 집게처럼 오므라든다 · 머리 끄덕
var alarm := 0.0          ## 피격 (1 에서 줄어든다): 몸이 움찔 줄어들며 S 자로 몸부림 · 더듬이 뒤로 젖힘
var startle := 0.0        ## 알아챔 (1 에서 줄어든다): 앞몸 번쩍 · 더듬이 쭉
var dizzy := 0.0          ## 어질어질 0~1: 앞몸이 느리게 휘청 · 더듬이 축
var dead_k := 0.0         ## 죽음: 몸을 C 자로 말며 꿈틀 (뒤집힌 상태 기준)
var kick_power := 1.0     ## 죽은 뒤 꿈틀 세기
var emerge_k := 1.0       ## 땅에서 기어 나오는 중 (0 = 땅속)

# ── 출력 (적이 소리·체액에 쓰고 끈다) ───────────
var pulsed := false       ## 이번 프레임에 새 수축 물결이 시작됐다 (꼬리가 떨어짐)
var gait := 0.0           ## 기는 정도 0~1

var model: Node3D
var skel: Skeleton3D
var head: Node3D
var feelers: Array = []   ## [[seg1, seg2, seg3], side, 스프링 [[값x, 속x, 값y, 속y] × 3], 움찔 [값, 다음]]
var rest_z: Array[float] = []
var t := 0.0
var phase := 0.0
var _cycle := 0
var bend := 0.0           ## 몸 휨 곡률 (1/m, + = 왼쪽)
var sway := 0.0
var sway_goal := 0.0
var sway_t := 0.0
var search := 0.0         ## 앞몸 들고 두리번 정도
var ripple := 0.0         ## 서 있을 때 가끔 제자리에서 지나가는 작은 수축 물결 (0~1 진행, <0 이면 없음)
var ripple_t := 3.0
var head_ext := 0.0
var off: Array[float] = []      ## 지난 프레임 뼈 앞뒤 위치 (확인용)
var lift: Array[float] = []
var rng := RandomNumberGenerator.new()

static var _skin_mesh: ArrayMesh
static var _skin: Skin
static var _rest_z: Array[float] = []


func setup(m: Node3D) -> GrubRig:
	model = m
	rng.randomize()
	t = rng.randf() * 10.0
	phase = rng.randf()
	ripple_t = rng.randf_range(1.5, 4.0)
	ripple = -1.0
	var body := m.find_child("body", true, false) as MeshInstance3D
	head = m.find_child("head", true, false) as Node3D
	_skin_body(body)
	for s in ["l", "r"]:
		var segs := []
		for i in range(1, 4):
			segs.append(m.find_child("feeler_%s_%d" % [s, i], true, false))
		var spr := []
		for i in 3:
			spr.append([0.0, 0.0, 0.0, 0.0])
		feelers.append([segs, -1.0 if s == "l" else 1.0, spr, [0.0, rng.randf_range(0.5, 2.0)]])
	for i in NB:
		off.append(0.0)
		lift.append(0.0)
	update(0.0001)
	return self


## 통짜 몸통 메시에 뼈 NB 개짜리 스켈레톤을 붙인다. 스키닝한 메시와 Skin 은 모든 애벌레가 같이 쓴다 (정적 캐시 1개).
func _skin_body(body: MeshInstance3D) -> void:
	skel = Skeleton3D.new()
	skel.name = "spine"
	var parent := body.get_parent()
	parent.add_child(skel)
	skel.transform = body.transform
	if _skin_mesh == null:
		_build_skin(body.mesh as ArrayMesh)
	for i in NB:
		skel.add_bone("seg_%d" % i)
		skel.set_bone_rest(i, Transform3D(Basis(), Vector3(0, 0, _rest_z[i])))
	skel.reset_bone_poses()
	rest_z = _rest_z
	var mats := []
	for s in body.mesh.get_surface_count():
		var ov := body.get_surface_override_material(s)
		mats.append(ov if ov else body.mesh.surface_get_material(s))
	body.owner = null
	parent.remove_child(body)
	skel.add_child(body)
	body.transform = Transform3D.IDENTITY
	body.mesh = _skin_mesh
	for s in mats.size():
		if mats[s] != _skin_mesh.surface_get_material(s):
			body.set_surface_override_material(s, mats[s])
	body.skin = _skin
	body.skeleton = NodePath("..")


static func _build_skin(src: ArrayMesh) -> void:
	_rest_z.clear()
	for i in NB:
		_rest_z.append(SPAN * 0.5 - SPAN * float(i) / (NB - 1))
	var h := SPAN / (NB - 1)
	_skin_mesh = ArrayMesh.new()
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		bones.resize(verts.size() * 4)
		weights.resize(verts.size() * 4)
		for vi in verts.size():
			# 꼬리 뼈에서부터 잰 뼈 번호(실수). 이차 B-스플라인 가중치 → 가까운 뼈 셋에 나눠 준다
			var f := (SPAN * 0.5 - verts[vi].z) / h
			var picks := []
			var total := 0.0
			for k in NB:
				var w := _b2(f - k)
				if w > 0.0001:
					picks.append([k, w])
					total += w
			if picks.is_empty():
				picks.append([clampi(roundi(f), 0, NB - 1), 1.0])
				total = 1.0
			for q in 4:
				if q < picks.size():
					bones[vi * 4 + q] = picks[q][0]
					weights[vi * 4 + q] = picks[q][1] / total
				else:
					bones[vi * 4 + q] = 0
					weights[vi * 4 + q] = 0.0
		arr[Mesh.ARRAY_BONES] = bones
		arr[Mesh.ARRAY_WEIGHTS] = weights
		_skin_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		_skin_mesh.surface_set_material(s, src.surface_get_material(s))
	_skin = Skin.new()
	for i in NB:
		_skin.add_bind(i, Transform3D(Basis(), Vector3(0, 0, _rest_z[i])).affine_inverse())


static func _b2(x: float) -> float:
	var a := absf(x)
	if a < 0.5:
		return 0.75 - a * a
	if a < 1.5:
		return 0.5 * (1.5 - a) * (1.5 - a)
	return 0.0


func update(dt: float) -> void:
	if dt <= 0.0:
		return
	t += dt
	pulsed = false
	bite = move_toward(bite, 0.0, dt * 3.0)
	alarm = move_toward(alarm, 0.0, dt * 2.2)
	startle = move_toward(startle, 0.0, dt * 1.8)
	var alive_k := 1.0 - dead_k
	var busy := maxf(windup, lunge)
	# 기는 정도: 멈춰도 바로 0 이 되지 않고 하던 수축 주기를 마저 끝낸다
	var want_g := clampf(absf(speed) / 0.35, 0.0, 1.0) * alive_k * (1.0 - busy)
	gait = move_toward(gait, want_g, dt * (4.0 if want_g > gait else 1.6))
	var rate := speed / STRIDE
	if gait > 0.05 and absf(rate) < 1.1:
		rate = 1.1 * (signf(rate) if rate != 0.0 else 1.0)      # 멈추는 중: 남은 수축을 이어서 끝낸다
	phase += rate * dt
	var cyc := int(floor(phase))
	if cyc != _cycle:
		_cycle = cyc
		if gait > 0.3:
			pulsed = true
	var frac := fposmod(phase, 1.0)
	# 몸 휨: 지나온 길의 곡률 = 회전 속도 / 속도 (제자리 회전은 살짝만)
	var k_goal := turn / maxf(absf(speed), 0.6) * 0.9
	bend = lerpf(bend, clampf(k_goal, -1.3, 1.3) * alive_k, 1.0 - exp(-6.0 * dt))
	# 서 있을 때: 앞몸을 들고 짧게 끊어 두리번거리다 가끔 제자리 물결
	var idle := (1.0 - gait) * alive_k * (1.0 - busy)
	search = move_toward(search, idle * (0.6 + 0.4 * absf(sin(t * 0.37))), dt * 1.5)
	sway_t -= dt
	if sway_t <= 0.0:
		sway_t = rng.randf_range(0.5, 1.4)
		sway_goal = clampf(look_yaw * 0.6, -0.5, 0.5) + rng.randf_range(-0.45, 0.45)
	sway = lerpf(sway, sway_goal * (0.35 + 0.65 * idle), 1.0 - exp(-5.0 * dt))
	ripple_t -= dt * idle
	if ripple < 0.0 and ripple_t <= 0.0:
		ripple = 0.0
		ripple_t = rng.randf_range(2.5, 5.0)
	if ripple >= 0.0:
		ripple += dt / 1.1
		if ripple >= 1.0:
			ripple = -1.0

	var d0 := SPAN / (NB - 1)
	var pos: Array[Vector3] = []
	var sc: Array[Vector3] = []
	var ofs: Array[float] = []
	var lf: Array[float] = []
	# ① 앞뒤 위치(몸 중심 기준 상대 이동)와 들림
	for i in NB:
		var u := float(i) / (NB - 1)
		var a := u * (1.0 - WAVE)
		var p := smoothstep(0.0, 1.0, (frac - a) / WAVE)
		var o := STRIDE * (p - frac) * gait
		var l := HUMP * sin(PI * p) * gait
		# 제자리 물결 (서 있을 때 숨 쉬듯 한 번 쭉 지나감)
		if ripple >= 0.0:
			var rp := smoothstep(0.0, 1.0, (ripple - a) / WAVE)
			o += 0.07 * (rp - ripple) * idle
			l += 0.022 * sin(PI * rp) * idle
		# 숨쉬기: 아주 작게 늘었다 줄었다
		o += 0.012 * sin(t * 2.1) * (u - 0.5) * alive_k
		# 머리 내밀기: 주기 끝에 머리 고리가 쑥 나갔다 돌아옴
		# 공격 준비: 꼬리 쪽으로 바짝 움츠림 · 돌진: 앞으로 확 늘어남
		o -= 0.34 * windup * u
		o += 0.42 * lunge * (u - 0.35)
		# 피격 움찔: 몸 전체가 가운데로 줄어든다
		o -= 0.16 * alarm * (u - 0.5)
		# 앞몸 들기 (두리번 · 공격 준비 · 알아챔), 돌진 땐 앞몸을 내리찍는다
		var front := pow(smoothstep(0.45, 1.0, u), 1.6)
		l += front * (0.07 * search + 0.18 * windup + 0.16 * startle - 0.05 * lunge)
		# 땅에서 기어 나올 때·죽을 때
		ofs.append(o)
		lf.append(l)
	# ② 고리 사이 늘어남 비율 → 굵기 (줄면 높고 굵게, 늘면 가늘고 납작하게)
	for i in NB:
		var lam_a := (d0 + ofs[mini(i + 1, NB - 1)] - ofs[i]) / d0 if i < NB - 1 else 1.0
		var lam_b := (d0 + ofs[i] - ofs[maxi(i - 1, 0)]) / d0 if i > 0 else 1.0
		var lam := clampf((lam_a + lam_b) * 0.5 if i > 0 and i < NB - 1 else (lam_a if i == 0 else lam_b), 0.62, 1.45)
		var breathe := 1.0 + 0.02 * sin(t * 2.1 + i * 0.3) * alive_k
		sc.append(Vector3(pow(lam, -0.22) * breathe, pow(lam, -0.5) * breathe, lam))
	# ③ 몸 휨 · 두리번 · 몸부림 · 죽음
	var tremble := windup * 0.012
	for i in NB:
		var u := float(i) / (NB - 1)
		var s := rest_z[i] * -1.0 + ofs[i]          # 몸 중심에서 앞쪽 거리
		var x := -bend * s * s * 0.5
		var front := pow(smoothstep(0.4, 1.0, u), 1.5)
		x += -sway * 0.16 * front
		# 피격 · 어질 · 땅속 · 죽음: 옆으로 S 자 몸부림 (뒤에서 앞으로 흐르는 물결)
		var writhe := alarm * 0.09 + dizzy * 0.05 * front + (1.0 - emerge_k) * 0.1 + dead_k * kick_power * 0.11
		var wf := 9.0 if dizzy < 0.5 else 2.5
		x += sin(t * wf - u * 5.5) * writhe
		x += sin(t * 61.0 + i * 1.7) * tremble
		var y := lf[i] + sin(t * 57.0 + i) * tremble * 0.6
		# 죽음: 뒤집힌 채 양 끝을 배 쪽(로컬 -Y)으로 C 자로 만다
		var curl := absf(u - 0.5) * 2.0
		y -= dead_k * (0.16 * curl * curl + 0.05 * sin(t * 6.0 + u * 4.0) * kick_power)
		pos.append(Vector3(x, y, -s))
	# ④ 기울기: 이웃 고리로 접선 방향을 구해 yaw · pitch 로
	for i in NB:
		var a: Vector3 = pos[maxi(i - 1, 0)]
		var b: Vector3 = pos[mini(i + 1, NB - 1)]
		var d := b - a
		var yaw := atan2(-d.x, -d.z)
		var pitch := atan2(d.y, Vector2(d.x, d.z).length())
		var q := Quaternion.from_euler(Vector3(pitch, yaw, 0.0))
		skel.set_bone_pose_position(i, pos[i])
		skel.set_bone_pose_rotation(i, q)
		skel.set_bone_pose_scale(i, sc[i])
	off = ofs
	lift = lf
	_head(dt, pos[NB - 1], skel.get_bone_pose_rotation(NB - 1), sc[NB - 1], frac)
	_feelers(dt, frac, idle)


## 머리 캡슐: 맨 앞 뼈를 따라가되 늘임은 받지 않는다. 주기 끝에 쑥 내밀고, 두리번·공격 때 끄덕인다.
func _head(dt: float, p: Vector3, q: Quaternion, s: Vector3, frac: float) -> void:
	if head.get_parent() != model:
		return          # 광선검에 잘려 날아간 머리
	var a := (1.0 - WAVE)
	var hp := clampf((frac - a) / WAVE, 0.0, 1.0)
	head_ext = lerpf(head_ext, sin(PI * hp) * gait * 0.05 + windup * -0.06 + lunge * 0.08, 1.0 - exp(-14.0 * dt))
	var rel := HEAD_REST - Vector3(0, 0, rest_z[NB - 1])
	rel = Vector3(rel.x * s.x, rel.y * s.y, rel.z * s.z - head_ext)
	var nod := sin(t * 3.1) * 0.05 * search - bite * 0.35 + windup * 0.25 - lunge * 0.2 + alarm * 0.3 \
		- dizzy * 0.25 + sin(t * 18.0) * 0.03 * (1.0 - emerge_k)
	var turn_h := clampf(look_yaw, -0.6, 0.6) * 0.35 * (1.0 - dead_k) + sway * 0.25
	var hq := q * Quaternion.from_euler(Vector3(nod, turn_h, sin(t * 1.3) * 0.12 * dizzy))
	head.position = p + q * rel
	head.quaternion = hq
	head.scale = Vector3.ONE * (1.0 + bite * 0.08)


## 더듬이 3마디. goal = (pitch + 위, yaw 바깥 +). 마디마다 스프링, 끝으로 갈수록 더 크게 휘고 늦게 따라온다.
func _feelers(dt: float, frac: float, idle: float) -> void:
	for f in feelers:
		var segs: Array = f[0]
		var side: float = f[1]
		var spr: Array = f[2]
		var tw: Array = f[3]
		var ph := 0.0 if side < 0.0 else PI
		# 혼자 움찔 (불규칙한 경련)
		tw[1] -= dt
		if tw[1] <= 0.0:
			tw[1] = rng.randf_range(0.4, 2.2)
			tw[0] = rng.randf_range(0.6, 1.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		tw[0] = move_toward(tw[0], 0.0, dt * 4.0)
		var gp := 0.0
		var gy := 0.0
		# 기는 동안: 주기에 맞춰 번갈아 좌우를 쓸고 살짝 든다
		gy += sin(frac * TAU + ph) * 0.45 * gait
		gp += (0.12 + 0.12 * sin(frac * TAU * 2.0 + ph)) * gait
		# 서 있을 때: 번갈아 바닥을 톡톡 (끝이 바닥에 닿았다 들림) + 느린 탐색
		var tap := pow(maxf(0.0, sin(t * 5.2 + ph)), 6.0)
		gp += (0.22 - tap * 0.34 + sin(t * 1.1 + ph) * 0.1) * idle
		gy += sin(t * 0.9 + ph * 0.7) * 0.3 * idle
		# 두리번 쪽으로 쏠림
		gy += -sway * side * 0.4
		# 공격 준비: 활짝 벌리고 쳐들어 떨기 → 덥석: 안쪽으로 오므림
		gy += windup * 0.75 + sin(t * 47.0 + ph) * 0.08 * windup
		gp += windup * 0.55
		gy -= bite * 1.25
		gp -= bite * 0.25 - lunge * 0.3
		# 피격: 뒤로 젖힘 · 알아챔: 쭉 세움
		gp += alarm * 0.7 + startle * 0.6
		gy += alarm * 0.4 * sin(t * 30.0 + ph)
		# 어질: 축 늘어짐 · 죽음: 안으로 말림 + 경련
		gp -= dizzy * 0.35
		gp += dead_k * (0.6 + sin(t * 9.0 + ph) * 0.4 * kick_power)
		gy -= dead_k * 0.5
		gp += tw[0] * 0.35
		gy += tw[0] * 0.25
		for i in 3:
			var s: Array = spr[i]
			var k: float = FEELER_K[i]
			var d: float = FEELER_D[i]
			# 바깥 마디: 같은 목표의 일부 + 끝 말림(curl)
			var share := 1.0 if i == 0 else 0.55
			var curl := 0.0 if i == 0 else (0.18 + 0.2 * idle * tap) * float(i) * 0.5
			var tp := gp * share - curl * (1.0 - windup)
			var ty := gy * share
			s[1] += (k * (tp - s[0]) - d * s[1]) * dt
			s[0] += s[1] * dt
			s[3] += (k * (ty - s[2]) - d * s[3]) * dt
			s[2] += s[3] * dt
			var seg := segs[i] as Node3D
			# yaw 바깥 = 왼쪽 더듬이는 +, 오른쪽은 - (Godot yaw + = 왼쪽)
			seg.rotation = Vector3(clampf(s[0], -1.4, 1.4), clampf(s[2], -1.6, 1.6) * -side, 0.0)


## 꼬리 끝(체액 흔적을 남기는 자리)의 모델 기준 위치
func tail_local() -> Vector3:
	var p := skel.get_bone_pose_position(0)
	return skel.transform * (p + Vector3(0, 0, 0.06))


## 바닥을 붙잡고 있는 고리 수 (확인용): 들림이 거의 없는 고리
func anchored() -> int:
	var c := 0
	for l in lift:
		if l < 0.01:
			c += 1
	return c
