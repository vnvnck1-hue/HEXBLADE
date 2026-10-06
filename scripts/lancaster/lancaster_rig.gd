class_name LancasterRig
extends RefCounted
## LANCASTER 보스(lancaster.glb) 절차 애니메이션. 판정·이동은 하지 않고 관절만 움직인다 (LancasterBoss 가 입력을 채운다).
## 모델 계약은 models/src/lancaster.py 머리말 (원점 = 관절, 기본 회전 0, 정면 -Z, 왼쪽 = 개틀링 팔 · 오른쪽 = 집게 팔).
##
##  · 하체: 두 발을 월드에 박아 두고(디딘 자리 고정) 2관절 IK 로 허벅지 · 정강이를 돌린다. 발이 제자리에서 벗어나면 한 발씩
##    번갈아 딛는다(빠를수록 보폭이 길고 빠르다). 디딜 때 골반이 쿵 내려앉고 stepped 로 알린다(먼지 · 진동 · 발소리).
##    plant 면 발을 떼지 않는다(사격 버팀 자세). air 면 다리를 몸 아래로 접는다(분사 도약).
##    stomp 는 오른발을 높이 든다(밟기 준비), kneel 은 무릎을 꿇는다(정지 · 기동).
##  · 상체: 골반 위 torso 만 따로 돈다 — 하체는 이동 방향, 상체는 조준 방향(aim_yaw). 비틀림은 스프링으로 따라간다.
##  · 팔 · 몸통 자세: pose 사전(관절 → 기본 자세에서 더할 회전, 라디안)을 목표로 관절마다 스프링이 따라간다.
##    snap() 하면 바로 그 자세(임팩트 프레임). kick() 은 관절에 순간 충격(반동 · 피격).
##  · 개틀링 팔: gun_aim 만큼 상완을 돌려 총열 축이 aim_point 를 향하게 한다(자세 위에 덧씌움). 총열은 spin 속도로 돈다.
##  · 집게(claw 0 닫힘 ~ 1 벌림) · 어깨 위 보안 포드(pods_spin · pods_up) · 등 분사구 불꽃(jet) · 눈 · 표시등 발광(eye_on, rage = 붉게)
##  · 총열 열기(heat) · 가슴 통풍구 열기(rage) 는 덮개 재질로.
##
## 축 (Godot, 기본 회전 0): torso.rotation.x - = 앞으로 숙임, .y + = 왼쪽으로 비틂(오른 어깨가 앞으로)
##  upperarm.rotation.x + = 팔을 앞 · 위로 듦, .z + = 오른팔 바깥 / 왼팔 안쪽, forearm.rotation.x + = 팔꿈치를 굽혀 전완을 듦

const GLB := "res://assets/models/lancaster.glb"
## 골반을 원점 위로 (모델 전체 이동, 변형 없음)
const SHIFT := Vector3(0, 0, -0.48)
## 서 있는 기본 자세: 원본은 다리가 거의 펴져 있어 골반을 낮춰 무릎을 굽힌다
const CROUCH_BASE := 0.16
const JOINTS := ["torso", "shoulder_l", "upperarm_l", "forearm_l", "shoulder_r", "upperarm_r", "forearm_r", "hand_r"]
const SIDES := ["l", "r"]
const EYE := Color(0.35, 1.0, 0.9)
const RAGE := Color(1.0, 0.14, 0.06)
const FLAME_OUT := Color(1.0, 0.45, 0.12)
const FLAME_IN := Color(1.0, 0.92, 0.6)
const STEP_H := 0.34            ## 발 들기 높이 (m, 모델 기준)
const SNAP_DIST := 3.2          ## 이보다 멀어지면 걷지 않고 바로 제자리로

# ── 입력 (LancasterBoss 가 매 틱 채운다) ─────────────────
var vel := Vector3.ZERO          ## 월드 수평 속도
var aim_yaw := 0.0               ## 상체가 바라볼 월드 yaw (0 = -Z)
var aim_point := Vector3.ZERO    ## 개틀링이 겨눌 월드 점
var gun_aim := 0.0               ## 0~1
var crouch := 0.0                ## 0~1 웅크림 (골반을 낮춘다)
var lean := 0.0                  ## 몸통 추가 숙임 (rad, + = 앞으로)
var plant := false               ## 발을 떼지 않는다 (버팀)
var air := 0.0                   ## 0~1 공중: 다리를 접는다
var spin := 0.0                  ## 총열 목표 회전 속도 (rad/s)
var heat := 0.0                  ## 총열 열기 0~1
var claw := 0.0                  ## 0 닫힘 ~ 1 벌림
var pods_spin := 0.0             ## 포드 목표 회전 속도 (rad/s)
var pods_up := 0.0               ## 포드 들어 올림 0~1
var jet := 0.0                   ## 분사 불꽃 0~1
var rage := 0.0                  ## 광폭화 0~1: 눈 · 표시등 붉게 · 통풍구 달아오름 · 떨림
var eye_on := 1.0                ## 눈 밝기 0~1 (정지 0)
var stomp := 0.0                 ## 오른발 들기 0~1
var kneel := 0.0                 ## 0~1 무릎 꿇음 (정지 · 기동 전)
var pose := {}                   ## 관절 → 목표 회전 (Vector3)
var stiff := 190.0               ## 자세 스프링 강도 (클수록 빠르게 따라간다)
var damp := 19.0
var twist_k := 16.0              ## 상체 비틀림 따라가는 빠르기
var twist_max := 1.7

# ── 출력 ────────────────────────────────────────────
var stepped := 0                 ## 이번 틱에 디딘 발 수
var step_at: Array[Vector3] = [] ## 이번 틱에 디딘 발 자리 (월드)
var twist := 0.0                 ## 지금 상체 비틀림 (rad)

var model: Node3D
var pelvis: Node3D
var torso: Node3D
var n := {}                      ## 이름 → 노드
var meshes: Array[MeshInstance3D] = []   ## 외장 메시 (섬광 · 락온 덮개 대상)
var eyes: Array[MeshInstance3D] = []
var lights: MeshInstance3D
var flames := {}                 ## "l"/"r" → [바깥, 안쪽]
var legs := {}
var t := 0.0
var rng := RandomNumberGenerator.new()

var _cur := {}
var _vel := {}
var _drive := {}                 ## swing() 진행 중: {from, to, t, dur}
var _kick := {}
var _kick_v := {}
var _pelvis_rest := Vector3.ZERO
var _bob := 0.0
var _bob_v := 0.0
var _tilt := Vector2.ZERO        ## 골반 (앞 숙임, 옆 기울기)
var _tilt_v := Vector2.ZERO
var _prev_vel := Vector3.ZERO
var _twist_v := 0.0
var _spin := 0.0
var _spin_a := 0.0
var _pod_a := 0.0
var _pod_v := 0.0
var _barrel_axis := Vector3.FORWARD
var _next_foot := "l"
var _heat_mat: StandardMaterial3D
var _rage_mat: StandardMaterial3D
var _heat_sent := -1.0
var _rage_sent := -1.0
var _glow_sent := Color(0, 0, 0, 0)


func setup(parent: Node3D) -> LancasterRig:
	rng.randomize()
	t = rng.randf() * 10.0
	model = (load(GLB) as PackedScene).instantiate() as Node3D
	model.position = SHIFT
	parent.add_child(model)
	for nd in model.find_children("*", "Node3D", true, false):
		n[String(nd.name)] = nd
	pelvis = n.pelvis
	torso = n.torso
	_pelvis_rest = pelvis.position
	for j: String in JOINTS:
		_cur[j] = Vector3.ZERO
		_vel[j] = Vector3.ZERO
		_kick[j] = Vector3.ZERO
		_kick_v[j] = Vector3.ZERO
	_barrel_axis = (n.pt_muzzle as Node3D).position.normalized()
	# 다리: 고관절 · 무릎 · 발목 · 발바닥의 쉬는 자리 (골반 기준)
	for s: String in SIDES:
		var thigh: Node3D = n["thigh_" + s]
		var shin: Node3D = n["shin_" + s]
		var foot: Node3D = n["foot_" + s]
		var sole: Node3D = n["pt_foot_" + s]
		var h0 := thigh.position
		var k0 := h0 + shin.position
		var a0 := k0 + foot.position
		var f0 := a0 + sole.position
		legs[s] = {
			"thigh": thigh, "shin": shin, "foot": foot, "h0": h0, "k0": k0, "a0": a0,
			"l1": (k0 - h0).length(), "l2": (a0 - k0).length(),
			"da": (k0 - h0).normalized(), "db": (a0 - k0).normalized(),
			# 모델 기준 발바닥 제자리 (바닥 높이 0) 와 발목까지의 차
			"home": Vector3(_pelvis_rest.x + f0.x, 0.0, _pelvis_rest.z + f0.z),
			"ankle_up": a0 - f0,
			"plant": Vector3.ZERO, "from": Vector3.ZERO, "to": Vector3.ZERO, "stepping": false, "st": 0.0, "dur": 0.2,
			"lift": 0.0, "side": -1.0 if s == "l" else 1.0,
		}
	# 외장 메시 · 발광부
	lights = n.lights as MeshInstance3D
	lights.material_override = Pal.flat()
	lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi != lights:
			meshes.append(mi)
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 12
	sm.rings = 6
	for i in 3:
		var e := Pal.flat_mesh(sm, EYE, 2.2)
		e.scale = Vector3.ONE * 0.13
		torso.add_child(e)
		e.position = (n["pt_eye_%d" % (i + 1)] as Node3D).position + Vector3(0, 0, -0.03)
		eyes.append(e)
	# 분사 불꽃: 등 탱크 뒤에서 뒤 · 아래로
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.5
	cone.height = 1.0
	cone.radial_segments = 10
	cone.rings = 1
	for s: String in SIDES:
		var pivot := Node3D.new()
		(n["pt_jet_" + s] as Node3D).add_child(pivot)
		pivot.rotation = Vector3(deg_to_rad(-105.0), 0, 0)     # 원뿔 +Y 를 뒤(+Z) · 살짝 아래로
		var outer := Pal.flat_mesh(cone, FLAME_OUT, 2.4)
		var inner := Pal.flat_mesh(cone, FLAME_IN, 3.4)
		for f in [outer, inner]:
			pivot.add_child(f)
			f.visible = false
		flames[s] = [outer, inner]
	_heat_mat = _glow_mat()
	_rage_mat = _glow_mat()
	set_overlay(null)
	return self


static func _glow_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.albedo_color = Color(0, 0, 0, 1)
	return m


## 노드 (부착점 포함)
func node(nm: String) -> Node3D:
	return n[nm]


## 부착점 월드 위치
func at(nm: String) -> Vector3:
	return (n[nm] as Node3D).global_position


## 개틀링 총열 축 (월드, 총구 쪽)
func barrel_dir() -> Vector3:
	return ((n.barrel_l as Node3D).global_basis * _barrel_axis).normalized()


## 발을 모두 지금 제자리에 내려놓는다 (등장 · 순간이동)
func reset_feet() -> void:
	for s: String in SIDES:
		var L: Dictionary = legs[s]
		L.plant = _home_world(s)
		L.stepping = false
		L.lift = 0.0


## 지금 자세를 목표 자세로 바로 맞춘다 (임팩트 프레임)
func snap() -> void:
	_drive.clear()
	for j: String in JOINTS:
		_cur[j] = pose.get(j, Vector3.ZERO)
		_vel[j] = Vector3.ZERO


## 임팩트 스윙: 지금 자세에서 to 자세로 dur 초(몇 프레임) 만에 폭발적으로 뻗는다 (스프링을 건너뛴 expo 이징).
## 끝나면 남은 속도(carry 배)가 스프링에 넘어가 목표를 살짝 지나쳤다 돌아온다 (광선검 콤보의 스윙 → 여운과 같은 느낌)
func swing(to: Dictionary, dur: float, carry := 0.35) -> void:
	var from := {}
	for j: String in JOINTS:
		from[j] = _cur[j]
	_drive = {"from": from, "to": to, "t": 0.0, "dur": maxf(dur, 0.001), "carry": carry}
	pose = to


func swinging() -> bool:
	return not _drive.is_empty()


## 관절에 순간 충격 (반동 · 피격). v = 회전 속도 (rad/s)
func kick(j: String, v: Vector3) -> void:
	_kick_v[j] += v


## 피격: 맞은 쪽(월드 방향)으로 상체가 젖혀진다
func hit(dir: Vector3, k: float) -> void:
	var l := (model.global_basis.orthonormalized().inverse() * Vector3(dir.x, 0, dir.z)).normalized()
	kick("torso", Vector3(l.z, 0, -l.x) * 3.5 * k + Vector3(0, rng.randf_range(-1, 1) * 1.5 * k, 0))
	_bob_v -= 1.2 * k


## 외장 덮개 재질 (섬광 · 락온 빗금 · 패링 예고)
func set_overlay(m: Material) -> void:
	for mi in meshes:
		if is_instance_valid(mi) and mi != (n.barrel_l as MeshInstance3D) and mi != (n.vent_l as MeshInstance3D) and mi != (n.vent_r as MeshInstance3D):
			mi.material_overlay = m
	var hm: Material = m if m else _heat_mat
	(n.barrel_l as MeshInstance3D).material_overlay = hm
	var rm: Material = m if m else _rage_mat
	(n.vent_l as MeshInstance3D).material_overlay = rm
	(n.vent_r as MeshInstance3D).material_overlay = rm


func set_overlay_param(key: String, v: float) -> void:
	for mi in meshes:
		if is_instance_valid(mi):
			mi.set_instance_shader_parameter(key, v)


func update(dt: float) -> void:
	if dt <= 0.0:
		return
	t += dt
	stepped = 0
	step_at.clear()
	var spd := Vector2(vel.x, vel.z).length()
	_pose(dt)
	_body(dt, spd)
	_legs(dt, spd)
	_gun(dt)
	_extras(dt)
	_prev_vel = vel


# ── 자세 스프링 ────────────────────────────────────────

func _pose(dt: float) -> void:
	if not _drive.is_empty():
		_drive.t = float(_drive.t) + dt
		var k := clampf(float(_drive.t) / float(_drive.dur), 0.0, 1.0)
		var e := 1.0 - pow(2.0, -10.0 * k) if k < 1.0 else 1.0
		for j: String in JOINTS:
			var a: Vector3 = _drive.from[j]
			var b: Vector3 = (_drive.to as Dictionary).get(j, Vector3.ZERO)
			_cur[j] = a.lerp(b, e)
			_vel[j] = (b - a) / float(_drive.dur) * float(_drive.carry) if k >= 1.0 else Vector3.ZERO
		if k >= 1.0:
			_drive.clear()
		_kicks(dt)
		_apply_joints()
		return
	for j: String in JOINTS:
		var goal: Vector3 = pose.get(j, Vector3.ZERO)
		var c: Vector3 = _cur[j]
		var v: Vector3 = _vel[j]
		v += ((goal - c) * stiff - v * damp) * dt
		c += v * dt
		_cur[j] = c
		_vel[j] = v
	_kicks(dt)
	_apply_joints()


func _kicks(dt: float) -> void:
	for j: String in JOINTS:
		var kv: Vector3 = _kick_v[j]
		var kp: Vector3 = _kick[j]
		kv += (-kp * 260.0 - kv * 16.0) * dt
		kp += kv * dt
		_kick[j] = kp
		_kick_v[j] = kv


func _apply_joints() -> void:
	for j: String in JOINTS:
		if j == "torso":
			continue
		(n[j] as Node3D).rotation = _cur[j] + _kick[j]


# ── 골반 · 몸통 ────────────────────────────────────────

func _body(dt: float, spd: float) -> void:
	var gb := model.global_basis.orthonormalized()
	var lv := gb.inverse() * vel
	var acc := gb.inverse() * ((vel - _prev_vel) / dt)
	_bob_v += (-_bob * 150.0 - _bob_v * 11.0) * dt
	_bob += _bob_v * dt
	var ground := 1.0 - air
	var y := _pelvis_rest.y - CROUCH_BASE * ground - crouch * 0.55 * ground - kneel * 0.6 + _bob
	y += sin(t * 2.1) * 0.02 * ground * (1.0 - kneel)                  # 숨쉬기 (모터 웅웅)
	y -= 0.07 * minf(spd / 7.0, 1.0) * ground                           # 달릴 땐 낮게
	y += air * 0.12
	var goal := Vector2.ZERO
	goal.x = clampf(-lv.z * 0.028, -0.18, 0.26) + clampf(-acc.z * 0.006, -0.16, 0.16)
	goal.y = clampf(lv.x * 0.02, -0.14, 0.14) + clampf(acc.x * 0.004, -0.1, 0.1)
	_tilt_v += ((goal - _tilt) * 120.0 - _tilt_v * 13.0) * dt
	_tilt += _tilt_v * dt
	var shake := Vector3.ZERO
	if rage > 0.0:
		shake = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.012 * rage
	pelvis.position = Vector3(_pelvis_rest.x, y, _pelvis_rest.z) + shake
	pelvis.rotation = Vector3(-_tilt.x, 0, -_tilt.y)
	# 상체: 조준 방향으로 비틀림 (하체 yaw 와의 차)
	var rel := wrapf(aim_yaw - model.global_rotation.y, -PI, PI)
	rel = clampf(rel, -twist_max, twist_max)
	_twist_v += ((rel - twist) * twist_k * twist_k - _twist_v * twist_k * 1.6) * dt
	twist += _twist_v * dt
	var tp: Vector3 = _cur.torso + _kick.torso
	torso.rotation = Vector3(tp.x - lean - kneel * 0.3, tp.y + twist, tp.z) + shake * 2.0


# ── 다리 (발 고정 + 2관절 IK) ──────────────────────────

func _home_world(s: String) -> Vector3:
	var L: Dictionary = legs[s]
	var w := model.global_transform * (L.home as Vector3)
	w.y = Main.gy(w) if Main.inst else 0.0
	return w


func _legs(dt: float, spd: float) -> void:
	var lead := clampf(spd * 0.11, 0.0, 1.0)
	var flat := Vector3(vel.x, 0, vel.z)
	var reach := 0.42 + spd * 0.055
	var dur := clampf(0.3 - spd * 0.018, 0.13, 0.3)
	var sk := model.global_basis.get_scale().x
	for s: String in SIDES:
		var L: Dictionary = legs[s]
		var home := _home_world(s) + flat * 0.11
		# 공중(분사 대시 · 도약)에서는 발이 몸을 따라온다 → 내려앉을 때 몸 아래에 딛는다
		if air > 0.3:
			L.plant = home
			L.stepping = false
			L.lift = 0.0
		if (L.plant as Vector3) == Vector3.ZERO or (L.plant as Vector3).distance_to(home) > SNAP_DIST * sk:
			L.plant = home
			L.stepping = false
		var other: Dictionary = legs["r" if s == "l" else "l"]
		var stomping := s == "r" and stomp > 0.01
		if not L.stepping and not stomping and air < 0.5 and kneel < 0.5:
			var off := (L.plant as Vector3).distance_to(home)
			var turn := absf(wrapf(model.global_rotation.y - float(L.get("yaw", model.global_rotation.y)), -PI, PI))
			if ((off > reach * sk and not plant) or turn > 0.7) and (not other.stepping or spd > 5.5) and (_next_foot == s or off > reach * sk * 1.6):
				L.stepping = true
				L.st = 0.0
				L.dur = dur
				L.from = L.plant
				L.to = home + flat * dur * (0.5 + lead * 0.3)
				_next_foot = "r" if s == "l" else "l"
		if L.stepping:
			L.st = float(L.st) + dt / float(L.dur)
			var k := clampf(L.st, 0.0, 1.0)
			L.to = (L.to as Vector3).lerp(home + flat * float(L.dur) * (1.0 - k) * 0.6, 0.15)
			var e := k * k * (3.0 - 2.0 * k)
			L.plant = (L.from as Vector3).lerp(L.to, e)
			L.lift = sin(PI * k) * STEP_H * sk * clampf(0.6 + spd * 0.06, 0.6, 1.25)
			if k >= 1.0:
				L.stepping = false
				L.lift = 0.0
				L.yaw = model.global_rotation.y
				stepped += 1
				step_at.append(L.plant)
				_bob_v -= 0.9 + spd * 0.12
		elif plant:
			L.lift = move_toward(L.lift, 0.0, dt * 4.0)
	# 디딘 발이 다리 길이 밖이면 골반을 그만큼 낮춘다 (발이 바닥에서 뜨지 않게)
	var drop := 0.0
	for s: String in SIDES:
		var L: Dictionary = legs[s]
		var tg := _target(s, L)
		var tp: Vector3 = tg[0]
		var h := pelvis.transform * (L.h0 as Vector3)
		var d := tp - h
		var lmax := (float(L.l1) + float(L.l2)) * 0.985
		var hz := Vector2(d.x, d.z).length()
		if d.length() > lmax and hz < lmax:
			drop = maxf(drop, -d.y - sqrt(lmax * lmax - hz * hz))
	pelvis.position.y -= minf(drop, 0.6)
	for s: String in SIDES:
		var L: Dictionary = legs[s]
		var tg := _target(s, L)
		_solve(L, tg[0], tg[1])


## 발목 목표 (모델 기준) 와 발 앞꿈치 기울기
func _target(s: String, L: Dictionary) -> Array:
	var inv := model.global_transform.affine_inverse()
	var tgt := inv * ((L.plant as Vector3) + Vector3.UP * float(L.lift))
	tgt += L.ankle_up as Vector3
	var toe_pitch := 0.0
	if L.stepping:
		toe_pitch = sin(PI * clampf(L.st, 0.0, 1.0)) * 0.35
	# 오른발 들기 (밟기 준비)
	if s == "r" and stomp > 0.0:
		var up := Vector3(0, 1.15, -0.35) * stomp
		tgt += up
		toe_pitch += 0.25 * stomp
	# 공중: 다리를 몸 아래로 접는다 (골반을 따라가며)
	if air > 0.0:
		var tuck := (L.home as Vector3) + (L.ankle_up as Vector3) + Vector3(0, pelvis.position.y - _pelvis_rest.y + 0.55, 0.3)
		tgt = tgt.lerp(tuck, air)
		toe_pitch = lerpf(toe_pitch, -0.4, air)
	return [tgt, toe_pitch]


func _solve(L: Dictionary, tgt: Vector3, toe_pitch: float) -> void:
	# 골반 기준으로
	var p := pelvis.transform.affine_inverse() * tgt
	var h0: Vector3 = L.h0
	var l1: float = L.l1
	var l2: float = L.l2
	var d := p - h0
	var dl := clampf(d.length(), absf(l1 - l2) + 0.02, (l1 + l2) * 0.999)
	var dir := d.normalized()
	p = h0 + dir * dl
	# 무릎은 앞 · 살짝 바깥으로 (무릎 꿇을 땐 더 앞으로)
	var pole := (pelvis.basis.inverse() * Vector3(float(L.side) * 0.18, -0.1, -1.0)).normalized()
	var pp := (pole - dir * dir.dot(pole)).normalized()
	var a := (l1 * l1 - l2 * l2 + dl * dl) / (2.0 * dl)
	var hh := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var knee := h0 + dir * a + pp * hh
	var a1 := (knee - h0).normalized()
	var b1 := (p - knee).normalized()
	var nrm := dir.cross(pp).normalized()
	var r1 := _frame(a1, nrm) * _frame(L.da, Vector3.RIGHT).inverse()
	var r2 := _frame(b1, nrm) * _frame(L.db, Vector3.RIGHT).inverse()
	(L.thigh as Node3D).basis = r1
	(L.shin as Node3D).basis = r1.inverse() * r2
	# 발: 모델 기준 수평 (+ 디딜 때 앞꿈치 들기)
	var want := pelvis.basis.inverse() * Basis(Vector3.RIGHT, toe_pitch)
	(L.foot as Node3D).basis = r2.inverse() * want


## 뼈 방향 a 와 (a 에 수직으로 맞춘) 평면 법선 n 으로 정한 직교 기저
static func _frame(a: Vector3, nrm: Vector3) -> Basis:
	var nn := (nrm - a * a.dot(nrm))
	if nn.length() < 0.001:
		nn = Vector3.FORWARD.cross(a)
	nn = nn.normalized()
	return Basis(nn, a, nn.cross(a))


# ── 개틀링 팔 ──────────────────────────────────────────

func _gun(dt: float) -> void:
	# 총열 회전
	_spin = move_toward(_spin, spin, dt * (40.0 if spin > _spin else 18.0))
	_spin_a = wrapf(_spin_a + _spin * dt, 0.0, TAU)
	(n.barrel_l as Node3D).basis = Basis(_barrel_axis, _spin_a)
	if gun_aim <= 0.001:
		return
	var ua: Node3D = n.upperarm_l
	var muzzle: Node3D = n.pt_muzzle
	var want := aim_point - muzzle.global_position
	if want.length() < 0.5:
		return
	var axis := barrel_dir()
	var q := Quaternion(axis, want.normalized())
	var ang := q.get_angle()
	if ang > 1.5:
		q = Quaternion(q.get_axis().normalized(), 1.5)
	q = Quaternion.IDENTITY.slerp(q, clampf(gun_aim, 0.0, 1.0))
	var par := (ua.get_parent() as Node3D).global_basis.orthonormalized()
	var g := ua.global_basis.orthonormalized()
	ua.basis = par.inverse() * Basis(q) * g


# ── 집게 · 포드 · 불꽃 · 발광 ───────────────────────────

func _extras(dt: float) -> void:
	(n.claw_a as Node3D).rotation = Vector3(-0.95 * claw, 0, 0)
	(n.claw_b as Node3D).rotation = Vector3(0.85 * claw, 0, -0.25 * claw)
	_pod_v = move_toward(_pod_v, pods_spin, dt * 30.0)
	_pod_a = wrapf(_pod_a + _pod_v * dt, -PI, PI)
	if absf(pods_spin) <= 0.1:
		_pod_a = lerp_angle(_pod_a, 0.0, 1.0 - exp(-4.0 * dt))
	for s: String in SIDES:
		var pod: Node3D = n["pod_" + s]
		var sgn := 1.0 if s == "l" else -1.0
		pod.rotation = Vector3(pods_up * 0.55, _pod_a * sgn, 0)
	# 분사 불꽃
	for s: String in SIDES:
		var fl: Array = flames[s]
		var on := jet > 0.02
		for i in 2:
			var f: MeshInstance3D = fl[i]
			f.visible = on
			if on:
				var flick := 0.85 + 0.3 * rng.randf()
				var len := (1.3 if i == 0 else 0.8) * jet * flick
				var w := (0.42 if i == 0 else 0.24) * (0.6 + 0.4 * jet)
				f.scale = Vector3(w, len, w)
				f.position = Vector3(0, len * 0.5, 0)
	# 눈 · 표시등
	var c := EYE.lerp(RAGE, clampf(rage, 0.0, 1.0))
	var flick := 1.0
	if rage > 0.5:
		flick = 0.85 + 0.15 * sin(t * 37.0)
	var key := Color(c.r, c.g, c.b, snappedf(eye_on * flick, 0.05))
	if key != _glow_sent:
		_glow_sent = key
		for e in eyes:
			e.set_instance_shader_parameter("tint", c)
			e.set_instance_shader_parameter("energy", 0.15 + 2.6 * key.a)
			e.visible = key.a > 0.01
		lights.set_instance_shader_parameter("tint", c)
		lights.set_instance_shader_parameter("energy", 0.2 + 1.6 * key.a)
	# 총열 열기 · 통풍구 열기 (덮개 재질 밝기)
	var hq := snappedf(clampf(heat, 0.0, 1.0), 0.05)
	if hq != _heat_sent:
		_heat_sent = hq
		_heat_mat.albedo_color = Color(1.0, 0.42, 0.1) * (hq * 1.6)
	var rq := snappedf(clampf(rage * (0.75 + 0.25 * sin(t * 9.0)), 0.0, 1.0), 0.05)
	if rq != _rage_sent:
		_rage_sent = rq
		_rage_mat.albedo_color = Color(1.0, 0.18, 0.06) * (rq * 1.4)
