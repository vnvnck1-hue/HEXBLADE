class_name MechPlayer
extends RefCounted
## 새 메카 플레이어 모델(assets/models/mech_volume_preserved.glb)을 기존 Build.robot 관절 계약(j)에 맞춰 붙이는 어댑터.
## 설계 근거는 docs/mech-player-integration-handoff.md.
##
## 원칙: 메시는 줄이거나 늘리지 않는다. 원본 외피를 관절 피벗 아래로 옮기기만 하고(부위 배율 1),
## 맞지 않는 부분은 피벗 위치 · 기본 자세 회전으로 맞춘다.
##
## 좌우: 기존 동작은 "왼손 총 · 오른손 검" 기준인데 새 메카는 총이 오른쪽(+X), 손이 왼쪽(-X)이다.
## 상체와 하체를 각각 거울(X 반전) 공간에 넣어, 기존 코드는 예전 배치(총 -X · 검 +X)에 값을 쓰고
## 화면에는 좌우가 바뀐 동작으로 보이게 한다. 메시는 거울 공간 안에서 다시 X 반전하므로 원형 그대로 보인다.
## 회전 값(조준 yaw)은 거울 밖의 Legs/Upper 에 쓰이므로 방향은 바뀌지 않는다.
##
## 선택: 기본은 새 메카. 실행 인자 --player=robot 이면 예전 Build.robot.

const GLB := "res://assets/models/mech_volume_preserved.glb"
## 모델 전체 이동 (변형 없음): 몸 중심을 플레이어 원점 위로
const SHIFT := Vector3(0, 0, -0.25)
## Player._animate 가 Upper.position.y 에 직접 쓰는 기준 높이
const UPPER_Y := 0.74
const MIRROR := Vector3(-1, 1, 1)
## 원본 GLB(중립 자세)의 총신 축 (총 메시 주성분, 총구 쪽). 모델을 다시 만들면 다시 잰다.
const GUN_AXIS := Vector3(0.358, -0.651, -0.669)
## 총 팔 기본 자세: 어깨를 들고(라디안), 팔꿈치는 총신을 정면 수평으로 돌린 뒤 총신 축 둘레로 GUN_ROLL 만큼 돌린다
const GUN_LIFT := 0.52
const GUN_ROLL := 0.0
const FWD := Vector3(0, 0, -1)

static var _choice := ""


static func active() -> bool:
	if _choice == "":
		_choice = "mech"
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--player="):
				_choice = a.substr(9)
	return _choice != "robot"


## 메카를 body 아래에 만들고 Build.robot 과 같은 키의 관절 사전을 돌려준다.
static func build(body: Node3D) -> Dictionary:
	var glb := (load(GLB) as PackedScene).instantiate() as Node3D
	var g := {}                       # GLB 노드 이름 → 노드
	for n in glb.find_children("*", "Node3D", true, false):
		g[n.name] = n
	var at := func(name: String) -> Vector3:        # 모델 좌표 (이동 반영)
		return _model_pos(g[name], glb) + SHIFT
	var rel := func(a: String, b: String) -> Vector3:   # 거울 공간에서 b 기준 a 의 위치
		return _m(at.call(a) - at.call(b))
	var j := {"mech": true}

	# ── 하체: Legs(이동 방향 yaw) → 거울 → 골반 · 양다리 ──
	var legs := Build.pivot(body, Vector3.ZERO, "Legs")
	j.legs = legs
	var legs_m := _mirror(legs, "LegsMirror")
	var pelvis := Build.pivot(legs_m, _m(at.call("pelvis")), "Pelvis")
	_take(g.pelvis, pelvis)
	# 거울 공간의 왼쪽(-X) = 화면 오른쪽(+X) 의 총 쪽 다리
	for s in [["l", "gun"], ["r", "hand"]]:
		var k: String = s[1]
		var hip := Build.pivot(legs_m, _m(at.call("hip_" + k)), "Hip")
		_take(g["hip_" + k], hip)
		var knee := Build.pivot(hip, rel.call("knee_" + k, "hip_" + k), "Knee")
		_take(g["knee_" + k], knee)
		var ankle := Build.pivot(knee, rel.call("ankle_" + k, "knee_" + k), "Ankle")
		_take(g["ankle_" + k], ankle)
		# 기존 계약의 발 기준점은 발바닥 0.12 위 · 0.05 뒤 (Player._update_rush 가 그만큼 빼서 발밑을 잡는다)
		var foot := Build.pivot(ankle, rel.call("pt_foot_" + k, "ankle_" + k) + Vector3(0, 0.12, 0.05), "Foot")
		j["hip_" + s[0]] = hip
		j["knee_" + s[0]] = knee
		j["ankle_" + s[0]] = ankle
		j["foot_" + s[0]] = foot
	var knee_y: float = at.call("knee_gun").y
	j.leg_trail = [Vector3(0, at.call("hip_gun").y - knee_y - 0.05, 0), Vector3(0, -knee_y + 0.06, -0.3)]

	# ── 상체: Upper(조준 yaw) → 거울 → 몸통 ──
	var upper := Build.pivot(body, Vector3(0, UPPER_Y, 0), "Upper")
	j.upper = upper
	var upper_m := _mirror(upper, "UpperMirror")
	var torso := Build.pivot(upper_m, _m(at.call("body")) - Vector3(0, UPPER_Y, 0), "Torso")
	_take(g.body, torso)
	j.torso = torso
	var head := Build.pivot(torso, rel.call("head", "body"), "Head")
	_take(g.head, head)

	# 총 팔 (기존 arm_l): 어깨 → 상완(기본 자세) → 팔꿈치(기본 자세) → 총
	var sh_l := Build.pivot(torso, rel.call("shoulder_gun", "body"), "ShoulderL")
	_take(g.shoulder_gun, sh_l)
	var arm_l := Build.pivot(sh_l, rel.call("arm_gun_upper", "shoulder_gun"), "ArmL")
	var rest := _gun_rest(at.call("arm_gun_upper"), at.call("arm_gun_fore"))
	var arm_l_rest := Build.pivot(arm_l, Vector3.ZERO, "ArmLRest")
	arm_l_rest.basis = _mb(rest[0])
	_take(g.arm_gun_upper, arm_l_rest)
	var elbow_l := Build.pivot(arm_l_rest, rel.call("arm_gun_fore", "arm_gun_upper"), "ElbowL")
	elbow_l.basis = _mb(rest[1])
	_take(g.arm_gun_fore, elbow_l)
	var gun := Build.pivot(elbow_l, rel.call("gun_mount", "arm_gun_fore"), "Gun")
	_take(g.gun_mount, gun)
	var muzzle := Build.pivot(gun, rel.call("pt_muzzle", "gun_mount"), "Muzzle")
	muzzle.basis = Basis.looking_at(_m(GUN_AXIS.normalized()), Vector3.UP)
	j.shoulder_l = sh_l
	j.arm_l = arm_l
	j.gun = gun
	j.muzzle = muzzle

	# 손 팔 (기존 arm_r): 어깨 → 상완 → 팔꿈치 → 손 → 광선검. 중립 자세 그대로가 기본 자세라 손 축 = 팔 축
	var sh_r := Build.pivot(torso, rel.call("shoulder_hand", "body"), "ShoulderR")
	_take(g.shoulder_hand, sh_r)
	var arm_r := Build.pivot(sh_r, rel.call("arm_hand_upper", "shoulder_hand"), "ArmR")
	_take(g.arm_hand_upper, arm_r)
	var elbow_r := Build.pivot(arm_r, rel.call("arm_hand_fore", "arm_hand_upper"), "ElbowR")
	_take(g.arm_hand_fore, elbow_r)
	var hand := Build.pivot(elbow_r, rel.call("hand", "arm_hand_fore"), "Hand")
	_take(g.hand, hand)
	var blade := Build.pivot(hand, rel.call("pt_grip", "hand"), "Blade")
	Build.box(blade, Vector3(0.08, 0.08, 0.24), Vector3(0, 0, 0.04), Pal.P_GREY)
	Build.glow_box(blade, Vector3(0.08, 0.035, 1.35), Vector3(0, 0, -0.76), Pal.BLADE, 1.6)
	Build.glow_box(blade, Vector3(0.03, 0.045, 1.2), Vector3(0, 0.01, -0.72), Pal.BLADE_CORE, 1.8)
	blade.rotation_degrees = Vector3(38, -18, 0)
	j.shoulder_r = sh_r
	j.arm_r = arm_r
	j.blade = blade

	# 부스터 불꽃: 원본 배낭 아래 부착점에 불꽃만 붙인다 (장갑은 늘이거나 숨기지 않는다)
	for s in [["l", "gun"], ["r", "hand"]]:
		var jet := Build.pivot(torso, rel.call("pt_booster_" + s[1], "body"), "Jet")
		jet.rotation_degrees.x = -40.0
		_flame(jet)
		j["jet_" + s[0]] = jet

	# 몸 리본: 팔 기준 어깨 → 총구 / 손
	j.arm_base = Vector3(0, -0.1, 0)
	j.arm_tip_l = (arm_l_rest.transform * elbow_l.transform * gun.transform * muzzle.transform).origin
	j.arm_tip_r = (elbow_r.transform * hand.transform * blade.transform).origin
	glb.free()
	return j


## 매 틱 마지막: 발목이 허벅지·무릎 회전을 되받아 발바닥을 지면과 나란하게 둔다 (예전 로봇은 발이 정강이와 한 덩어리)
static func settle(j: Dictionary) -> void:
	for s in ["l", "r"]:
		var a: Node3D = j["ankle_" + s]
		a.rotation.x = -((j["hip_" + s] as Node3D).rotation.x + (j["knee_" + s] as Node3D).rotation.x) * 0.85


## 총 팔 기본 자세 [상완 회전, 팔꿈치 회전] (모델 좌표). 총신 축이 정면 수평을 향하게 한다.
static func _gun_rest(_upper: Vector3, _fore: Vector3) -> Array:
	var rs := Basis(Vector3.RIGHT, GUN_LIFT)
	var a := rs * GUN_AXIS.normalized()
	var c := a.cross(FWD)
	var re := Basis(c.normalized(), a.angle_to(FWD)) if c.length() > 0.00001 else Basis()
	re = Basis(FWD, GUN_ROLL) * re
	return [rs, rs.inverse() * re * rs]


## GLB 노드의 메시 자식을 새 피벗 아래로 옮긴다 (전역 모습 유지: 피벗이 같은 관절 위치에 있고 거울 안이므로 X 반전만 더한다)
static func _take(src: Node, dst: Node3D) -> void:
	for c in src.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var xf := mi.transform
			mi.owner = null
			src.remove_child(mi)
			dst.add_child(mi)
			mi.transform = Transform3D(Basis.from_scale(MIRROR), Vector3.ZERO) * xf


static func _mirror(parent: Node3D, name: String) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.scale = MIRROR
	parent.add_child(n)
	return n


static func _m(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, v.z)


## 모델 좌표의 회전을 거울 공간의 회전으로
static func _mb(b: Basis) -> Basis:
	var f := Basis.from_scale(MIRROR)
	return f * b * f


static func _model_pos(n: Node3D, top: Node3D) -> Vector3:
	var xf := n.transform
	var p := n.get_parent()
	while p and p != top:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf.origin


static var _flame_mesh: CylinderMesh
static var _core_mesh: CylinderMesh


static func _flame(jet: Node3D) -> void:
	if _flame_mesh == null:
		_flame_mesh = CylinderMesh.new()
		_flame_mesh.top_radius = 0.1
		_flame_mesh.bottom_radius = 0.0
		_flame_mesh.height = 1.0
		_flame_mesh.radial_segments = 8
		_core_mesh = CylinderMesh.new()
		_core_mesh.top_radius = 0.05
		_core_mesh.bottom_radius = 0.0
		_core_mesh.height = 1.0
		_core_mesh.radial_segments = 6
	var f := Pal.flat_mesh(_flame_mesh, Pal.JET, 1.7)
	f.position.y = -0.5
	jet.add_child(f)
	var c := Pal.flat_mesh(_core_mesh, Pal.JET_CORE, 2.2)
	c.position.y = -0.4
	jet.add_child(c)
	jet.scale = Vector3(1, 0.001, 1)
	jet.visible = false
