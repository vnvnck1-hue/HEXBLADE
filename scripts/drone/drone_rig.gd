class_name DroneRig
extends RefCounted
## 파트너 드론(partner_drone.glb) 절차 애니메이션. 판정·이동은 하지 않고 관절만 움직인다 (PartnerDrone 이 입력을 채운다).
##
##  · 다리 4개: 발끝을 월드에 박아 두고(디딘 자리 고정) 2관절 IK 로 지지대·발을 돌린다. 대각선 두 쌍(앞왼+뒤오 / 앞오+뒤왼)이
##    번갈아 딛는 종종걸음. 몸이 숙이거나 내려앉아도 발은 제자리에 남는다. 서 있을 땐 가끔 앞발로 바닥을 톡톡.
##  · 몸통: 발이 디딜 때마다 콩 내려앉는 스프링 · 가속하면 앞으로 숙임 · 도는 쪽으로 기울기 · 숨쉬기 · 기쁨 콩콩 · 피격 덜컹.
##  · 세 모듈(triad): 평소엔 천천히, 청소할 땐 빠르게 고리 안에서 돈다. 모듈은 번갈아 앞으로 튀어나왔다 들어간다(펌프).
##    민트 원판(core)은 발광 — 청소·충전 때 밝게 맥동.
##  · 옆 포드: 걸을 때 바퀴처럼 굴러가고, 기쁘면 귀처럼 파닥, 합체 땐 접힌다.
##  · 접기(fold): 다리를 몸 아래로 바짝 접는다 (합체 · 회수 비행). 공중(air): 다리를 늘어뜨린다.
##
## 관절 방향 (Godot 축, 기본 회전 0, 정면 -Z): triad.rotation.z = 고리 안 회전 · mod.position.z - = 앞으로 튀어나옴 ·
##  pod.rotation.x = 굴러감 · pod.rotation.z × side = 들림 · 다리는 IK 가 basis 를 직접 정한다.

const LEGS := ["fl", "fr", "bl", "br"]
const GROUP := {"fl": 0, "br": 0, "fr": 1, "bl": 1}
const SIDE := {"fl": -1.0, "bl": -1.0, "fr": 1.0, "br": 1.0}
const STEP_DIST := 0.19        ## 발이 제자리(home)에서 이만큼 벗어나면 그 쌍이 한 걸음 딛는다
const STEP_H := 0.12           ## 발 들기 높이
const SNAP_DIST := 1.4         ## 이보다 멀어지면 걷지 않고 바로 제자리로 (순간이동·착지)
const CORE := Color("62ffc4")  ## 민트 발광
const BODY_TINT := Color(0.8, 0.86, 0.95)  ## 외장 밝기·색 보정 (원본 텍스처에 곱한다)

# ── 입력 (PartnerDrone 이 매 틱 채운다) ─────────────────
var vel := Vector3.ZERO      ## 월드 수평 속도
var yaw_rate := 0.0          ## 몸 회전 속도 (rad/s, + = 왼쪽)
var clean := 0.0             ## 청소 세기 0~1: 숙여 노즐을 바닥으로 · 모듈 고속 회전 · 펌프 · 발광 · 부들부들
var pitch_bias := 0.0        ## 추가로 숙이는 각 (rad, + = 앞으로 숙임)
var crouch := 0.0            ## 웅크림 0~1 (도약 준비 · 착지)
var air := 0.0               ## 공중 0~1: 다리를 늘어뜨린다
var fold := 0.0              ## 접기 0~1: 다리를 몸 아래로 접는다 (합체 · 회수 비행)
var charge := 0.0            ## 스킬 충전 0~1: 모듈 초고속 · 강한 발광
var happy := 0.0             ## 기쁨 (1 에서 줄어든다): 콩콩 · 포드 파닥 · 모듈 휘리릭
var hurt := 0.0              ## 피격 (1 에서 줄어든다): 덜컹 · 떨림
var hurt_dir := Vector3.ZERO ## 피격 방향 (월드)
var look := 0.0              ## 몸통만 따로 돌려 두리번 (rad)
var glow := 0.4              ## 기본 발광 세기

# ── 출력 ────────────────────────────────────────────
var stepped := 0             ## 이번 틱에 디딘 발 수 (발소리)
var tapped := false          ## 이번 틱에 앞발 톡

var model: Node3D
var body: Node3D
var triad: Node3D
var mods: Array[Node3D] = []
var cores: Array[MeshInstance3D] = []
var pods := {}
var rest := {}
var legs := {}
var meshes: Array = []
var t := 0.0
var rng := RandomNumberGenerator.new()

var _bob := [0.0, 0.0]
var _tilt := Vector2.ZERO        ## (앞 숙임, 옆 기울기)
var _tilt_v := Vector2.ZERO
var _prev_vel := Vector3.ZERO
var _spin := 0.0
var _roll := 0.0                 ## 포드 굴러간 각
var _fid := {"leg": "", "t": 0.0, "next": 2.0}
var _core_sent := -1.0
var _ground := true


func setup(m: Node3D) -> DroneRig:
	model = m
	rng.randomize()
	t = rng.randf() * 10.0
	body = _n("body")
	triad = _n("triad")
	for i in 3:
		mods.append(_n("mod_%d" % (i + 1)))
		var c := _n("core_%d" % (i + 1)) as MeshInstance3D
		c.material_override = Pal.flat()
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.set_instance_shader_parameter("tint", CORE)
		cores.append(c)
	pods = {"l": _n("pod_l"), "r": _n("pod_r")}
	var movable: Array[Node3D] = [body, triad]
	movable.append_array(mods)
	movable.append(pods.l)
	movable.append(pods.r)
	for nd in movable:
		rest[nd] = nd.position
	for s: String in LEGS:
		var hip := _n("leg_%s_1" % s)
		var knee := _n("leg_%s_2" % s)
		var pt := _n("pt_foot_" + s)
		var h0 := hip.position
		var k0 := h0 + knee.position
		var f0 := k0 + pt.position
		var a0 := (k0 - h0).normalized()
		var b0 := (f0 - k0).normalized()
		var s0 := (f0 - h0).cross(k0 - h0).normalized()
		var l1 := (k0 - h0).length()
		var l2 := (f0 - k0).length()
		var mid := (h0 + f0) * 0.5
		# 무릎은 쉬는 자세처럼 바깥 위로 굽는다 (고관절→발 선에서 무릎이 떨어진 방향)
		var pole := (k0 - mid).normalized() + Vector3.UP * 0.3
		# 접은 자세: 발끝을 고관절 아래 몸 쪽으로 바짝 당긴다
		var out := Vector3(f0.x - h0.x, 0, f0.z - h0.z).normalized()
		var fold_t := h0 + out * 0.1 + Vector3.DOWN * 0.16
		legs[s] = {
			"hip": hip, "knee": knee, "h0": h0, "k0": k0, "f0": f0, "l1": l1, "l2": l2,
			"lmin": absf(l1 - l2) + 0.02, "lmax": (l1 + l2) * 0.995,
			"fa": _frame(a0, s0), "fb": _frame(b0, s0), "s0": s0, "pole": pole, "fold": fold_t,
			"plant": Vector3.ZERO, "from": Vector3.ZERO, "stepping": false, "st": 0.0, "dur": 0.2, "lift": 0.0,
		}
	# 원본 외장은 거의 흰색이라 밝은 화면(브롤 룩)에서 하얗게 날아간다 → 옅은 하늘색이 남도록 살짝 눌러 둔 사본 재질
	var tinted: Material = null
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		meshes.append(mi)
		if cores.has(mi) or mi.mesh == null:
			continue
		var src := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if src and tinted == null:
			var tm := src.duplicate() as StandardMaterial3D
			tm.albedo_color = BODY_TINT
			tinted = tm
		if tinted:
			mi.set_surface_override_material(0, tinted)
	return self


func _n(nm: String) -> Node3D:
	var nd := model.find_child(nm, true, false) as Node3D
	assert(nd != null, "partner_drone.glb: no node " + nm)
	return nd


static func _frame(a: Vector3, s: Vector3) -> Basis:
	return Basis(a, s, a.cross(s))


## 발을 모두 지금 제자리에 내려놓는다 (등장 · 순간이동 · 착지 직후)
func reset_feet() -> void:
	for s: String in LEGS:
		var L: Dictionary = legs[s]
		L.plant = _home(s)
		L.stepping = false
		L.lift = 0.0


## 피격 섬광 (파츠 위에 흰색을 덮는다)
func flash(on: bool) -> void:
	var m: Material = Pal.flash() if on else null
	for mi: MeshInstance3D in meshes:
		if is_instance_valid(mi) and not cores.has(mi):
			mi.material_overlay = m


func update(dt: float) -> void:
	if dt <= 0.0:
		return
	t += dt
	stepped = 0
	tapped = false
	happy = move_toward(happy, 0.0, dt * 0.8)
	hurt = move_toward(hurt, 0.0, dt * 2.0)
	var spd := Vector2(vel.x, vel.z).length()
	_body(dt, spd)
	_triad(dt)
	_pods(dt, spd)
	_legs(dt, spd)
	_cores()
	_prev_vel = vel


# ── 몸통 ───────────────────────────────────────────

func _body(dt: float, spd: float) -> void:
	var gb := model.global_basis.orthonormalized()
	var lv := gb.inverse() * vel
	var acc := gb.inverse() * ((vel - _prev_vel) / dt)
	# 디딤 스프링 (발이 땅에 닿을 때 _legs 가 속도를 꺾는다)
	_bob[1] += (-float(_bob[0]) * 170.0 - float(_bob[1]) * 12.0) * dt
	_bob[0] = float(_bob[0]) + float(_bob[1]) * dt
	var ground := (1.0 - air) * (1.0 - fold)
	var b: Vector3 = rest[body]
	var y := b.y + float(_bob[0])
	y += sin(t * 2.3) * 0.012 * ground                             # 숨쉬기
	y -= crouch * 0.17 * ground + clean * 0.06 * ground
	y += absf(sin(t * 12.5)) * 0.08 * happy * ground                # 기쁨 콩콩
	y -= 0.05 * minf(spd / 6.0, 1.0) * ground                       # 달릴 땐 낮게
	# 기울기 목표 (x = 앞으로 숙임 +, y = 오른쪽으로 기울기 +)
	var goal := Vector2.ZERO
	goal.x = clampf(-lv.z * 0.03, -0.12, 0.2) + clampf(-acc.z * 0.012, -0.15, 0.15) + clean * 0.34 + pitch_bias + crouch * 0.12
	goal.y = clampf(yaw_rate * -0.06, -0.2, 0.2) + clampf(lv.x * 0.025, -0.12, 0.12)
	goal.x += sin(t * 31.0) * 0.025 * clean                          # 흡입 진동
	if air > 0.0:
		goal.x += -0.15 * air                                       # 공중: 살짝 젖힘
	_tilt_v += ((goal - _tilt) * 140.0 - _tilt_v * 14.0) * dt
	_tilt += _tilt_v * dt
	var shake := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.035 * hurt
	var hd := gb.inverse() * hurt_dir
	var recoil := Vector2(-hd.z, hd.x) * 0.45 * hurt * hurt
	body.position = Vector3(b.x, y, b.z) + shake + Vector3(hd.x, 0, hd.z) * 0.08 * hurt
	body.rotation = Vector3(-(_tilt.x + recoil.x), look + sin(t * 9.0) * 0.12 * happy, -(_tilt.y + recoil.y) + sin(t * 17.0) * 0.12 * happy)


# ── 세 모듈 · 포드 · 발광 ──────────────────────────

func _triad(dt: float) -> void:
	var w := 0.5 + clean * 11.0 + charge * 18.0 + happy * 9.0 + hurt * 6.0
	_spin += w * dt
	triad.rotation.z = _spin
	for i in 3:
		var m := mods[i]
		var pump := clean * 0.045 * (0.5 + 0.5 * sin(t * 19.0 + i * 2.1)) + charge * 0.06 + happy * 0.03 * maxf(0.0, sin(t * 10.0 + i * 2.1))
		m.position = rest[m] + Vector3(0, 0, -pump)


func _pods(dt: float, spd: float) -> void:
	_roll += (spd * 2.4 + clean * 4.0 + charge * 6.0) * dt
	for k: String in pods:
		var side := -1.0 if k == "l" else 1.0
		var p: Node3D = pods[k]
		var flap := sin(t * 21.0 + side) * 0.45 * happy + sin(t * 3.1 + side) * 0.05
		p.rotation = Vector3(_roll * side, 0.0, side * (flap - fold * 0.5 + air * 0.25 + hurt * 0.4))


func _cores() -> void:
	var e := glow + clean * (1.3 + 0.6 * sin(t * 22.0)) + charge * (2.0 + 0.8 * sin(t * 40.0)) + happy * 0.8
	e = snappedf(e, 0.05)
	if absf(e - _core_sent) < 0.01:
		return
	_core_sent = e
	for c in cores:
		c.set_instance_shader_parameter("energy", e)


# ── 다리 ───────────────────────────────────────────

## 이 다리의 발이 쉬는 자리 (월드, 지면 높이)
func _home(s: String) -> Vector3:
	var L: Dictionary = legs[s]
	var p := model.global_transform * (Vector3(rest[body].x, 0.0, rest[body].z) + Vector3(L.f0.x, 0.0, L.f0.z))
	p.y = Main.gy(p)
	return p


func _group_stepping(g: int) -> bool:
	for s: String in LEGS:
		if GROUP[s] == g and legs[s].stepping:
			return true
	return false


func _legs(dt: float, spd: float) -> void:
	var grounded := air < 0.5 and fold < 0.5
	if grounded and not _ground:
		reset_feet()                              # 착지: 발을 새로 딛는다
	_ground = grounded
	var dur := clampf(0.25 - spd * 0.017, 0.12, 0.25)
	var lead := vel * dur * 0.55
	if grounded:
		# 어느 쌍이 더 많이 벗어났나 → 다른 쌍이 딛고 있지 않으면 그 쌍이 한 걸음
		var err: Array[float] = [0.0, 0.0]
		for s: String in LEGS:
			var L: Dictionary = legs[s]
			if L.stepping:
				continue
			var d := _flat(L.plant - (_home(s) + lead))
			if d > SNAP_DIST:
				L.plant = _home(s)
				continue
			err[GROUP[s]] = maxf(err[GROUP[s]], d)
		var g := 0 if err[0] >= err[1] else 1
		var settle: bool = spd < 0.15 and err[g] > 0.05
		if (err[g] > STEP_DIST or (settle and fmod(t, 0.5) < dt)) and not _group_stepping(1 - g) and not _group_stepping(g):
			for s: String in LEGS:
				if GROUP[s] == g:
					var L: Dictionary = legs[s]
					L.stepping = true
					L.st = 0.0
					L.dur = dur if not settle else 0.16
					L.from = L.plant
		_fidget(dt, spd)
	var landed := false
	var bxf := body.global_transform.affine_inverse()
	for s: String in LEGS:
		var L: Dictionary = legs[s]
		var target: Vector3
		if grounded:
			if L.stepping:
				L.st = float(L.st) + dt
				var k := clampf(float(L.st) / float(L.dur), 0.0, 1.0)
				var to := _home(s) + lead
				to.y = Main.gy(to)
				var e := k * k * (3.0 - 2.0 * k)
				target = (L.from as Vector3).lerp(to, e) + Vector3.UP * sin(PI * k) * STEP_H * (0.7 + minf(spd, 7.0) * 0.07)
				if k >= 1.0:
					L.stepping = false
					L.plant = to
					stepped += 1
					landed = true
			else:
				target = L.plant
			if _fid.leg == s:
				target += Vector3.UP * float(L.lift)
		else:
			target = model.global_transform * (Vector3(rest[body].x, 0.0, rest[body].z) + L.f0)
		var tl: Vector3 = bxf * target
		# 공중: 다리를 아래로 늘어뜨리고 살랑 · 접기: 몸 아래로 바짝
		var dangle: Vector3 = L.f0 + Vector3(0, -0.05 + sin(t * 9.0 + SIDE[s]) * 0.03, 0)
		tl = tl.lerp(dangle, clampf(air * 2.0 - 1.0, 0.0, 1.0) * (1.0 - fold))
		tl = tl.lerp(L.fold, fold)
		_solve(L, tl)
	if landed:
		_bob[1] = float(_bob[1]) - 0.55 * clampf(spd / 4.0, 0.25, 1.0)


## 서 있을 때 앞발 하나로 바닥을 톡톡 (심심할 때)
func _fidget(dt: float, spd: float) -> void:
	if spd > 0.2 or clean > 0.3:
		if _fid.leg != "":
			legs[_fid.leg].lift = 0.0
			_fid.leg = ""
		return
	if _fid.leg == "":
		_fid.next = float(_fid.next) - dt
		if _fid.next <= 0.0:
			_fid.leg = "fl" if rng.randf() < 0.5 else "fr"
			_fid.t = 0.0
		return
	_fid.t = float(_fid.t) + dt
	var k := float(_fid.t) / 0.5
	# 두 번 톡톡
	legs[_fid.leg].lift = maxf(0.0, sin(k * TAU)) * 0.1
	if absf(k - 0.5) < dt / 0.5 * 0.5 or absf(k - 1.0) < dt / 0.5 * 0.5:
		tapped = true
	if k >= 1.0:
		legs[_fid.leg].lift = 0.0
		_fid.leg = ""
		_fid.next = rng.randf_range(2.0, 5.0)


## 2관절 IK (몸통 좌표): 고관절 h0 에서 tl 까지 지지대(l1) · 발(l2). 무릎은 pole 쪽으로 굽는다.
func _solve(L: Dictionary, tl: Vector3) -> void:
	var H: Vector3 = L.h0
	var dv := tl - H
	var dl := dv.length()
	var u := dv / dl if dl > 1e-4 else ((L.f0 as Vector3) - H).normalized()
	var d := clampf(dl, L.lmin, L.lmax)
	var l1: float = L.l1
	var l2: float = L.l2
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var pole: Vector3 = L.pole
	var v := pole - u * pole.dot(u)
	if v.length() < 1e-4:
		v = (L.s0 as Vector3).cross(u)
	v = v.normalized()
	var T := H + u * d
	var K := H + u * a + v * h
	var s1 := (T - H).cross(K - H)
	s1 = s1.normalized() if s1.length() > 1e-6 else L.s0
	var hb := _frame((K - H).normalized(), s1) * (L.fa as Basis).transposed()
	(L.hip as Node3D).basis = hb
	(L.knee as Node3D).basis = hb.transposed() * (_frame((T - K).normalized(), s1) * (L.fb as Basis).transposed())


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


## 발끝 (월드) — 테스트 · 발자국 효과용
func foot_world(s: String) -> Vector3:
	return (model.find_child("pt_foot_" + s, true, false) as Node3D).global_position
