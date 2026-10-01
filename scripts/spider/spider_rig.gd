extends Node3D
## SHIPWRIGHT 의 몸: 모델 조립 + 절차적 다관절 다리 IK + 살아 있는 움직임. 판정과 AI 는 spider_boss.gd 가 맡는다.
## 3면도 기준: 푸른 장갑 머리(청록 큰 눈 셋 · 작은 통풍구 둘 · 머리 위 카메라와 안테나) · 높은 뒤 몸통(공구 거치대 렌치 ·
## 태블릿 모니터 · 뒤쪽 새끼 해치 · 방적돌기) · 회색 원판 관절의 굵은 보행 다리 넷(검은 고무 발굽) · 앞쪽 공구 팔 넷
## (용접기 · 드릴 · 집게손 · 원형 톱) · 턱 밑 개틀링.
##
## 다리 (한 다리 = 고관절 원판 → 넓적다리 → 무릎 원판 → 정강이 장갑 → 발목 → 발허리 → 발굽):
##  - 발은 땅에 박힌 채 있고, 몸이 움직여 쉬는 자리(rest)와 멀어지면 한 걸음 내딛는다. 대각선 두 다리가 한 조.
##    다른 조가 딛는 중이면 기다리고, 너무 늘어나면 조와 상관없이 급히 딛는다. 빠를수록 짧고 빠른 걸음.
##  - 딛는 자리는 stage.project() 로 가장 가까운 면(바닥·벽·기둥)에 붙이므로, 벽에 다가가면 앞발부터 벽을 짚고 올라간다.
##  - 무릎은 몸보다 높이 솟는다(거미 실루엣). 3관절 IK: 발허리 방향을 면 법선 쪽으로 고정하고 넓적다리·정강이를 2관절로 푼다.
## 몸: 걸음에 맞춰 출렁이고(발이 닿을 때 눌린다) · 가속하면 뒤로 젖혀지고 · 뒤 몸통은 스프링으로 늦게 따라온다.
## 머리: 플레이어 쪽을 보되 거미처럼 툭툭 끊어 돌린다(단속 운동). 머리의 탐조등이 어둠을 훑는다.

signal foot_planted(pos: Vector3, n: Vector3, leg: int, hard: float)

const Stage := preload("res://scripts/spider/spider_stage.gd")

const BLUE := Color("3b70c2")
const BLUE_D := Color("284f8f")
const BLUE_L := Color("5a8fdc")
const GREY := Color("9aa2ac")
const GREY_D := Color("5d646e")
const METAL := Color("2b2f37")
const METAL_L := Color("434955")
const BLACK := Color("17181c")
const EYE := Color(0.55, 1.0, 0.97)
const TEAL := Color(0.15, 0.95, 0.85)
const SCREEN := Color(0.25, 0.75, 1.0)

const L_FEMUR := 3.4
const L_TIBIA := 4.4
const L_META := 1.3
const REACH := L_FEMUR + L_TIBIA - 0.05
const BODY_S := 1.22            # 몸통 배율 (다리 길이는 그대로, 3면도의 묵직한 몸통 비율)
## 몸 좌표 (정면 -Z · 위 +Y). 엉덩이 · 쉬는 발 자리(y 는 -RIDE 로 바뀐다)
const HIPS := [Vector3(-1.5, -0.1, -0.85), Vector3(1.5, -0.1, -0.85), Vector3(-1.55, -0.1, 1.0), Vector3(1.55, -0.1, 1.0)]
const RESTS := [Vector3(-5.6, 0, -4.4), Vector3(5.6, 0, -4.4), Vector3(-5.8, 0, 4.4), Vector3(5.8, 0, 4.4)]
const GROUP := [0, 1, 1, 0]
## 공구 팔: [어깨, 위팔, 아래팔, 쉬는 손끝 자리, 종류]
const ARMS := [
	[Vector3(-1.2, -0.45, -2.35), 1.8, 1.9, Vector3(-2.1, -2.0, -4.6), "welder"],
	[Vector3(-0.55, -0.8, -2.45), 1.35, 1.45, Vector3(-0.75, -2.05, -4.15), "drill"],
	[Vector3(0.55, -0.8, -2.45), 1.35, 1.45, Vector3(0.75, -2.05, -4.15), "claw"],
	[Vector3(1.2, -0.45, -2.35), 1.7, 1.8, Vector3(2.1, -1.9, -4.6), "saw"],
]

var stage: Stage
var root: Node3D               # 몸 중심 (자세)
var head: Node3D
var abdomen: Node3D
var hatch: Node3D
var gatling: Node3D
var saw_disc: Node3D
var searchlight: SpotLight3D
var eye_light: OmniLight3D
var eye_mats: Array[StandardMaterial3D] = []
var vent_mats: Array[StandardMaterial3D] = []
var torch_mat: StandardMaterial3D
var torch_light: OmniLight3D
var hatch_glow: StandardMaterial3D
var mouth_glow: StandardMaterial3D
var meshes: Array = []
var legs: Array = []
var arms: Array = []

# 컨트롤러가 정하는 목표 자세
var c := Vector3(0, Stage.RIDE, 0)
var up := Vector3.UP
var fwd := Vector3.FORWARD
var look_at_p := Vector3.ZERO   # 머리가 볼 곳
var ride := Stage.RIDE          # 몸 높이 (웅크리면 낮아진다)
var crouch := 0.0               # 0~1 도약 준비로 몸을 낮춤
var rear := 0.0                 # 0~1 앞다리를 들고 몸을 세움 (위협 자세)
var abd_raise := 0.0            # 0~1 뒤 몸통을 들어 올림 (새끼 해치 · 거미줄)
var hatch_open := 0.0
var curl := 0.0                 # 0~1 죽음: 다리를 몸 아래로 오므림
var eye_k := 1.0                # 눈빛 세기 (어둠 속에서 꺼 숨는다)
var light_k := 1.0              # 탐조등 세기
var gat_spin := 0.0
var saw_spin := 0.0
var torch_k := 0.0
var mouth_k := 0.0
var stride_k := 1.0             # 걸음 문턱 배율 (작을수록 자주 딛는다)
var twitch := 0.0               # 경련 (죽음 · 피격)

var vel := Vector3.ZERO
var speed := 0.0
var _q := Quaternion.IDENTITY
var _prev_c := Vector3.ZERO
var _prev_vel := Vector3.ZERO
var _bob := 0.0
var _bob_v := 0.0
var _lean := Vector3.ZERO       # 몸 좌표 회전 (x 앞뒤 · z 좌우)
var _lean_v := Vector3.ZERO
var _abd := Vector2.ZERO        # 뒤 몸통 스프링 (pitch, roll)
var _abd_v := Vector2.ZERO
var _head_yaw := 0.0
var _head_pitch := 0.0
var _head_goal := Vector2.ZERO
var _sacc_t := 0.0
var _sacc_off := Vector2.ZERO
var _t := 0.0
var _first := true
var _xf := Transform3D.IDENTITY


func _ready() -> void:
	root = Node3D.new()
	root.name = "Body"
	add_child(root)
	_build_body()
	for i in 4:
		legs.append(_build_leg(i))
	for i in ARMS.size():
		arms.append(_build_arm(i))
	meshes = find_children("*", "MeshInstance3D", true, false)
	for m in meshes:
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


# ── 조립 도우미 ─────────────────────────────────────────

func _glow(c0: Color, e: float, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c0
	m.emission_enabled = true
	m.emission = c0
	m.emission_energy_multiplier = e
	m.roughness = 0.2
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _bv(p: Node3D, size: Vector3, pos: Vector3, col: Color, b := 0.08, rot := Vector3.ZERO, taper := 1.0) -> MeshInstance3D:
	return Build.bevel(p, size, pos, col, b, rot, taper)


func _cy(p: Node3D, r: float, h: float, pos: Vector3, col: Color, rot := Vector3.ZERO, top_r := -1.0, segs := 16) -> MeshInstance3D:
	return Build.cyl(p, r, h, pos, col, rot, top_r, segs)


func _ball(p: Node3D, r: float, pos: Vector3, mat: Material, sq := Vector3.ONE) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 20
	sm.rings = 10
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	mi.scale = sq
	p.add_child(mi)
	return mi


func _build_body() -> void:
	# ── 가슴 (다리가 붙는 가운데 마디) ──
	var th := Build.pivot(root, Vector3.ZERO, "Thorax")
	_bv(th, Vector3(2.7, 1.25, 2.9), Vector3(0, -0.1, 0), METAL, 0.12)
	_bv(th, Vector3(2.9, 0.55, 2.5), Vector3(0, 0.62, 0), BLUE, 0.14, Vector3.ZERO, 0.88)
	_bv(th, Vector3(1.1, 0.22, 2.2), Vector3(0, 0.95, 0), GREY, 0.06)
	_bv(th, Vector3(2.2, 0.35, 2.4), Vector3(0, -0.8, 0), METAL_L, 0.1)
	for s in [-1.0, 1.0]:
		# 고관절 위 덮개 장갑
		_bv(th, Vector3(0.55, 1.0, 2.9), Vector3(s * 1.45, 0.25, 0.08), BLUE_D, 0.12)
		_bv(th, Vector3(0.2, 0.5, 1.2), Vector3(s * 1.74, 0.35, 0.1), GREY_D, 0.05)
	# ── 머리 ──
	head = Build.pivot(root, Vector3(0, 0.2, -1.35), "Head")
	_bv(head, Vector3(2.75, 1.7, 2.3), Vector3(0, 0.05, -1.0), BLUE, 0.26, Vector3.ZERO, 0.82)
	_bv(head, Vector3(1.7, 0.28, 1.5), Vector3(0, 0.95, -0.85), GREY, 0.08, Vector3.ZERO, 0.9)
	_bv(head, Vector3(0.4, 0.32, 1.9), Vector3(0, 1.08, -0.95), METAL, 0.06)
	_bv(head, Vector3(2.35, 1.05, 0.34), Vector3(0, -0.12, -2.08), METAL, 0.1)
	_bv(head, Vector3(1.7, 0.55, 0.9), Vector3(0, -0.78, -1.75), METAL_L, 0.1)
	_bv(head, Vector3(0.8, 0.2, 0.5), Vector3(0, 0.62, -2.05), GREY_D, 0.05)
	for s in [-1.0, 1.0]:
		_bv(head, Vector3(0.3, 1.2, 1.7), Vector3(s * 1.36, 0.05, -1.0), BLUE_D, 0.1)
		# 옆면 청록 표시등
		var lm := _glow(TEAL, 2.0)
		vent_mats.append(lm)
		var lmi := Build.box(head, Vector3(0.08, 0.36, 0.22), Vector3(s * 1.52, 0.3, -0.7), TEAL)
		lmi.material_override = lm
	# 눈 셋: 회색 테두리 안의 청록 유리 돔
	var glass := _glow(EYE, 3.2)
	glass.roughness = 0.05
	glass.metallic_specular = 1.0
	eye_mats.append(glass)
	for e in [[-0.84, 0.12], [0.0, -0.02], [0.84, 0.12]]:
		var ex: float = e[0]
		var ey: float = e[1]
		_cy(head, 0.56, 0.24, Vector3(ex, ey, -2.2), GREY, Vector3(90, 0, 0), 0.5)
		_cy(head, 0.47, 0.1, Vector3(ex, ey, -2.33), BLACK, Vector3(90, 0, 0))
		_ball(head, 0.44, Vector3(ex, ey, -2.33), glass, Vector3(1, 1, 0.62))
		# 동공 점 셋 (3면도의 눈 속 점)
		for k in 3:
			var a := TAU * k / 3.0 + PI * 0.5
			Build.box(head, Vector3(0.05, 0.05, 0.03), Vector3(ex + cos(a) * 0.1, ey + sin(a) * 0.1 - 0.05, -2.62), METAL)
	# 아래 작은 통풍구 둘 (청록 격자)
	for s in [-1.0, 1.0]:
		_cy(head, 0.26, 0.2, Vector3(s * 1.1, -0.5, -2.12), GREY_D, Vector3(90, 0, 0))
		var vm := _glow(TEAL, 2.6)
		vent_mats.append(vm)
		var v := _cy(head, 0.2, 0.08, Vector3(s * 1.1, -0.5, -2.24), TEAL, Vector3(90, 0, 0))
		v.material_override = vm
		for k in 3:
			Build.box(head, Vector3(0.36, 0.035, 0.04), Vector3(s * 1.1, -0.5 + (k - 1) * 0.1, -2.29), METAL)
	# 머리 위 카메라 · 안테나 · 노란 경고 삼각
	_bv(head, Vector3(0.5, 0.38, 0.55), Vector3(0.0, 1.32, -1.55), METAL_L, 0.05)
	_cy(head, 0.12, 0.12, Vector3(0.0, 1.32, -1.86), BLACK, Vector3(90, 0, 0))
	_cy(head, 0.05, 1.3, Vector3(-0.35, 1.7, -0.45), GREY_D)
	_ball(head, 0.09, Vector3(-0.35, 2.36, -0.45), _glow(Color(1.0, 0.3, 0.2), 3.0))
	# 이름 (머리 윗면)
	var lbl := Label3D.new()
	lbl.text = "SHIPWRIGHT"
	lbl.font_size = 64
	lbl.pixel_size = 0.0045
	lbl.modulate = Color(0.85, 0.92, 1.0, 0.9)
	lbl.outline_size = 0
	lbl.double_sided = false
	head.add_child(lbl)
	lbl.position = Vector3(0.95, 0.72, -1.05)
	lbl.rotation_degrees = Vector3(-90, 90, 0)
	lbl.rotate_object_local(Vector3.RIGHT, deg_to_rad(-22.0))
	# 입 (거미줄을 뱉는 곳): 평소 어둡고 쏘기 직전 하얗게 달아오른다
	mouth_glow = _glow(Color(0.9, 1.0, 1.0), 0.0)
	var mo := _cy(head, 0.24, 0.3, Vector3(0, -0.72, -2.25), BLACK, Vector3(90, 0, 0))
	mo.material_override = mouth_glow
	# 턱 밑 개틀링
	var gm := Build.pivot(head, Vector3(0, -1.05, -2.0), "GatMount")
	_cy(gm, 0.36, 0.9, Vector3(0, 0, 0.1), METAL_L, Vector3(90, 0, 0))
	gatling = Build.pivot(gm, Vector3(0, 0, -0.4), "Gatling")
	for k in 6:
		var a := TAU * k / 6.0
		_cy(gatling, 0.075, 1.5, Vector3(cos(a) * 0.19, sin(a) * 0.19, -0.75), METAL, Vector3(90, 0, 0), -1.0, 8)
	_cy(gatling, 0.3, 0.16, Vector3(0, 0, -1.42), GREY_D, Vector3(90, 0, 0))
	_cy(gatling, 0.3, 0.16, Vector3(0, 0, -0.4), GREY_D, Vector3(90, 0, 0))
	# ── 뒤 몸통 ──
	abdomen = Build.pivot(root, Vector3(0, 0.3, 1.25), "Abdomen")
	_bv(abdomen, Vector3(3.1, 2.7, 3.3), Vector3(0, 1.05, 1.75), BLUE, 0.3, Vector3.ZERO, 0.9)
	_bv(abdomen, Vector3(1.3, 0.3, 2.9), Vector3(0, 2.45, 1.75), GREY, 0.08)
	_bv(abdomen, Vector3(0.3, 0.2, 0.3), Vector3(0, 2.62, 1.2), Color(0.95, 0.2, 0.15), 0.04)
	_bv(abdomen, Vector3(2.7, 1.1, 2.8), Vector3(0, -0.25, 1.85), METAL, 0.12)
	_bv(abdomen, Vector3(2.2, 0.7, 1.0), Vector3(0, 0.15, 0.2), METAL_L, 0.1)
	for s in [-1.0, 1.0]:
		_bv(abdomen, Vector3(0.16, 1.35, 1.8), Vector3(s * 1.58, 1.05, 1.75), GREY, 0.05)
		_bv(abdomen, Vector3(0.12, 0.7, 0.5), Vector3(s * 1.64, 1.5, 2.2), GREY_D, 0.03)
		var tl := _glow(TEAL, 2.2)
		vent_mats.append(tl)
		var tmi := Build.box(abdomen, Vector3(0.1, 0.55, 0.3), Vector3(s * 1.66, 1.15, 0.85), TEAL)
		tmi.material_override = tl
		# 공구 거치대 (렌치 · 드라이버가 꽂힌 상자)
		var holder := Build.pivot(abdomen, Vector3(s * 1.05, 2.55, 2.75), "Holder")
		_bv(holder, Vector3(0.8, 0.75, 0.85), Vector3(0, 0.1, 0), METAL_L, 0.06)
		for k in 3:
			var x := (k - 1) * 0.22
			var hgt := randf_range(0.7, 1.0)
			Build.box(holder, Vector3(0.08, hgt, 0.05), Vector3(x, 0.45 + hgt * 0.5, 0.1 * (k % 2)), GREY, Vector3(0, 0, (k - 1) * 8.0))
			if k != 1:
				_bv(holder, Vector3(0.22, 0.14, 0.06), Vector3(x + (k - 1) * 0.03, 0.5 + hgt, 0.1 * (k % 2)), GREY, 0.02)
			else:
				_cy(holder, 0.05, 0.25, Vector3(x, 0.55 + hgt, 0.0), Color(0.85, 0.75, 0.2))
	# 태블릿 모니터 (청사진이 떠 있는 화면)
	var tab := Build.pivot(abdomen, Vector3(0.25, 3.1, 3.05), "Tablet")
	_cy(tab, 0.07, 0.9, Vector3(0, -0.3, 0), GREY_D)
	var scr := Build.pivot(tab, Vector3(0, 0.45, 0.05), "Screen")
	scr.rotation_degrees = Vector3(18, 0, 0)
	_bv(scr, Vector3(1.25, 0.85, 0.12), Vector3.ZERO, METAL, 0.05)
	var sm := _glow(SCREEN, 1.8)
	var sq := Build.box(scr, Vector3(1.05, 0.66, 0.02), Vector3(0, 0, -0.07), SCREEN)
	sq.material_override = sm
	for k in 4:
		Build.box(scr, Vector3(randf_range(0.3, 0.8), 0.03, 0.01), Vector3(randf_range(-0.2, 0.2), -0.2 + k * 0.13, -0.085), Color(0.8, 1.0, 1.0), Vector3.ZERO, 2.4)
	# 뒤쪽 새끼 해치 (위쪽 경첩) · 안쪽은 붉게 달아오른 산란실
	var inner := Build.box(abdomen, Vector3(1.8, 1.3, 0.3), Vector3(0, 0.25, 3.25), Color(1.0, 0.35, 0.15))
	hatch_glow = _glow(Color(1.0, 0.35, 0.15), 0.4)
	inner.material_override = hatch_glow
	hatch = Build.pivot(abdomen, Vector3(0, 1.0, 3.45), "Hatch")
	_bv(hatch, Vector3(2.1, 1.6, 0.25), Vector3(0, -0.8, 0), GREY_D, 0.06)
	for k in 5:
		Build.box(hatch, Vector3(0.22, 1.3, 0.04), Vector3(-0.8 + k * 0.4, -0.8, 0.14), Color(0.9, 0.68, 0.12), Vector3(0, 0, 30))
	# 방적돌기 (거미줄 꽁무니)
	for s in [-1.0, 1.0]:
		_cy(abdomen, 0.22, 0.6, Vector3(s * 0.45, -0.75, 3.3), METAL_L, Vector3(90, 0, 0), 0.14)
	# 등 가운데 배선 (가슴 → 뒤 몸통)
	for s in [-1.0, 1.0]:
		_cy(root, 0.11, 2.0, Vector3(s * 0.55, 1.05, 0.65), BLACK, Vector3(75, 0, 0))
	# 머리 탐조등 · 눈빛
	searchlight = SpotLight3D.new()
	searchlight.light_color = Color(0.72, 0.95, 1.0)
	searchlight.light_energy = 7.0
	searchlight.spot_range = 46.0
	searchlight.spot_angle = 17.0
	searchlight.spot_angle_attenuation = 1.3
	searchlight.spot_attenuation = 0.7
	searchlight.light_volumetric_fog_energy = 3.0
	searchlight.shadow_enabled = true
	searchlight.shadow_bias = 0.1
	head.add_child(searchlight)
	searchlight.position = Vector3(0, 0.1, -2.7)
	searchlight.rotation_degrees = Vector3(-22, 0, 0)
	eye_light = OmniLight3D.new()
	eye_light.light_color = EYE
	eye_light.light_energy = 2.2
	eye_light.omni_range = 7.0
	eye_light.omni_attenuation = 1.5
	head.add_child(eye_light)
	eye_light.position = Vector3(0, 0, -3.2)


func _build_leg(i: int) -> Dictionary:
	var side := -1.0 if i % 2 == 0 else 1.0
	var hip_l: Vector3 = HIPS[i]
	# 고관절 원판 (몸에 붙어 있다)
	var hp := Build.pivot(root, hip_l, "Hip%d" % i)
	_cy(hp, 0.82, 0.55, Vector3(side * 0.1, 0, 0), GREY, Vector3(0, 0, 90))
	_cy(hp, 0.5, 0.65, Vector3(side * 0.12, 0, 0), METAL, Vector3(0, 0, 90))
	_cy(hp, 0.2, 0.75, Vector3(side * 0.14, 0, 0), GREY_D, Vector3(0, 0, 90))
	var lg := Node3D.new()
	lg.name = "Leg%d" % i
	add_child(lg)
	# 넓적다리: 짙은 축 + 푸른 덮개 장갑 + 회색 띠
	var fem := Build.pivot(lg, Vector3.ZERO, "Femur")
	_cy(fem, 0.3, L_FEMUR, Vector3(0, 0, -L_FEMUR * 0.5), METAL, Vector3(90, 0, 0))
	_bv(fem, Vector3(0.95, L_FEMUR * 0.82, 0.62), Vector3(0, 0.2, -L_FEMUR * 0.52), BLUE, 0.14, Vector3(-90, 0, 0), 0.82)
	_bv(fem, Vector3(0.4, 0.16, L_FEMUR * 0.5), Vector3(0, 0.55, -L_FEMUR * 0.5), GREY, 0.04)
	_cy(fem, 0.13, L_FEMUR * 0.7, Vector3(side * 0.35, -0.2, -L_FEMUR * 0.5), BLACK, Vector3(90, 0, 0), -1.0, 8)
	# 무릎 원판
	var knee := Build.pivot(lg, Vector3.ZERO, "Knee")
	_cy(knee, 0.68, 0.8, Vector3.ZERO, GREY)
	_cy(knee, 0.42, 0.92, Vector3.ZERO, METAL)
	_cy(knee, 0.16, 1.0, Vector3.ZERO, GREY_D)
	# 정강이: 무릎에서 넓고 발끝으로 좁아지는 큰 장갑판
	var tib := Build.pivot(lg, Vector3.ZERO, "Tibia")
	_cy(tib, 0.28, L_TIBIA, Vector3(0, 0, -L_TIBIA * 0.5), METAL, Vector3(90, 0, 0))
	_bv(tib, Vector3(1.25, L_TIBIA * 0.9, 0.9), Vector3(0, 0.12, -L_TIBIA * 0.48), BLUE, 0.18, Vector3(-90, 0, 0), 0.62)
	_bv(tib, Vector3(0.62, L_TIBIA * 0.5, 0.2), Vector3(0, 0.55, -L_TIBIA * 0.36), BLUE_D, 0.06, Vector3(-90, 0, 0), 0.7)
	_bv(tib, Vector3(0.18, L_TIBIA * 0.3, 0.1), Vector3(0, 0.66, -L_TIBIA * 0.32), GREY, 0.03, Vector3(-90, 0, 0))
	var lamp := Build.box(tib, Vector3(0.1, 0.1, 0.4), Vector3(0, 0.6, -L_TIBIA * 0.7), Color(1.0, 0.25, 0.2), Vector3.ZERO, 2.5)
	lamp.name = "Lamp"
	# 발목 · 발허리 · 검은 고무 발굽
	var ank := Build.pivot(lg, Vector3.ZERO, "Ankle")
	_cy(ank, 0.36, 0.6, Vector3.ZERO, GREY_D)
	var meta := Build.pivot(lg, Vector3.ZERO, "Meta")
	_cy(meta, 0.26, L_META, Vector3(0, 0, -L_META * 0.5), METAL_L, Vector3(90, 0, 0), 0.22)
	var pad := Build.pivot(lg, Vector3.ZERO, "Pad")
	_bv(pad, Vector3(1.05, 0.6, 1.35), Vector3(0, 0.3, 0), BLACK, 0.2, Vector3.ZERO, 0.85)
	_bv(pad, Vector3(0.7, 0.18, 0.9), Vector3(0, 0.66, 0), METAL_L, 0.05)
	var rest: Vector3 = RESTS[i]
	return {"i": i, "side": side, "hip": hip_l, "rest": rest, "node": lg, "fem": fem, "knee": knee, "tib": tib, "ank": ank, "meta": meta, "pad": pad,
		"foot": Vector3.ZERO, "n": Vector3.UP, "from": Vector3.ZERO, "to": Vector3.ZERO, "from_n": Vector3.UP, "to_n": Vector3.UP,
		"t": -1.0, "dur": 0.3, "lift": 1.0, "group": GROUP[i], "goal": Vector3.ZERO, "gw": 0.0, "gn": Vector3.UP, "hard": 0.0}


func _build_arm(i: int) -> Dictionary:
	var spec: Array = ARMS[i]
	var kind: String = spec[4]
	var an := Node3D.new()
	an.name = "Arm_" + kind
	add_child(an)
	var l1: float = spec[1]
	var l2: float = spec[2]
	var sh := Build.pivot(an, Vector3.ZERO, "Shoulder")
	_cy(sh, 0.3, 0.4, Vector3.ZERO, GREY, Vector3(0, 0, 90))
	var up_n := Build.pivot(an, Vector3.ZERO, "Upper")
	_cy(up_n, 0.17, l1, Vector3(0, 0, -l1 * 0.5), METAL, Vector3(90, 0, 0))
	_bv(up_n, Vector3(0.42, l1 * 0.75, 0.36), Vector3(0, 0.12, -l1 * 0.5), BLUE if kind != "drill" else GREY, 0.08, Vector3(-90, 0, 0), 0.8)
	var el := Build.pivot(an, Vector3.ZERO, "Elbow")
	_cy(el, 0.26, 0.42, Vector3.ZERO, GREY_D)
	var fo := Build.pivot(an, Vector3.ZERO, "Fore")
	_cy(fo, 0.14, l2, Vector3(0, 0, -l2 * 0.5), METAL_L, Vector3(90, 0, 0), 0.11)
	_bv(fo, Vector3(0.32, l2 * 0.5, 0.28), Vector3(0, 0.08, -l2 * 0.35), GREY if kind != "saw" else BLUE, 0.06, Vector3(-90, 0, 0), 0.8)
	var tool := Build.pivot(an, Vector3.ZERO, "Tool")
	match kind:
		"welder":
			_cy(tool, 0.16, 0.5, Vector3(0, 0, -0.1), GREY, Vector3(90, 0, 0))
			_cy(tool, 0.09, 0.7, Vector3(0, 0, -0.6), METAL, Vector3(90, 0, 0), 0.04)
			_cy(tool, 0.05, 0.25, Vector3(0, 0, -1.0), Color(0.8, 0.65, 0.3), Vector3(90, 0, 0), 0.02)
			Build.box(tool, Vector3(0.6, 0.5, 0.06), Vector3(0, 0.3, -0.3), METAL_L, Vector3(-30, 0, 0))
			torch_mat = _glow(Color(0.45, 0.75, 1.0), 0.0, true)
			var fl := _cy(tool, 0.06, 0.4, Vector3(0, 0, -1.3), Color.WHITE, Vector3(90, 0, 0), 0.0, 8)
			fl.material_override = torch_mat
			fl.name = "Flame"
			torch_light = OmniLight3D.new()
			torch_light.light_color = Color(0.5, 0.8, 1.0)
			torch_light.light_energy = 0.0
			torch_light.omni_range = 5.0
			tool.add_child(torch_light)
			torch_light.position = Vector3(0, 0, -1.3)
		"drill":
			_cy(tool, 0.15, 0.45, Vector3(0, 0, -0.1), GREY_D, Vector3(90, 0, 0))
			_cy(tool, 0.1, 0.8, Vector3(0, 0, -0.65), GREY, Vector3(90, 0, 0), 0.0, 10)
		"claw":
			_bv(tool, Vector3(0.42, 0.3, 0.45), Vector3(0, 0, -0.2), METAL_L, 0.06)
			for k in 3:
				var a := -0.5 + k * 0.5
				var fing := Build.pivot(tool, Vector3(sin(a) * 0.15, -0.05, -0.4), "F%d" % k)
				fing.rotation = Vector3(-0.5, a * 0.6, 0)
				_bv(fing, Vector3(0.1, 0.1, 0.42), Vector3(0, 0, -0.2), BLACK, 0.03)
				_bv(fing, Vector3(0.08, 0.08, 0.3), Vector3(0, -0.1, -0.45), METAL, 0.02, Vector3(-45, 0, 0))
		"saw":
			_bv(tool, Vector3(0.3, 0.35, 0.6), Vector3(0, 0, -0.2), GREY_D, 0.05)
			saw_disc = Build.pivot(tool, Vector3(0, -0.15, -0.65), "Disc")
			_cy(saw_disc, 0.72, 0.06, Vector3.ZERO, Color(0.78, 0.8, 0.84), Vector3(0, 0, 90), -1.0, 24)
			_cy(saw_disc, 0.2, 0.12, Vector3.ZERO, GREY_D, Vector3(0, 0, 90))
			for k in 16:
				var a := TAU * k / 16.0
				Build.box(saw_disc, Vector3(0.05, 0.14, 0.1), Vector3(0, cos(a) * 0.76, sin(a) * 0.76), Color(0.9, 0.9, 0.92), Vector3(rad_to_deg(-a), 0, 0))
			_bv(tool, Vector3(0.12, 0.6, 1.0), Vector3(0.2, 0.25, -0.6), BLUE, 0.04)
	var rest: Vector3 = spec[3]
	return {"kind": kind, "sh": spec[0], "l1": l1, "l2": l2, "rest": rest, "node": an, "shn": sh, "up": up_n, "el": el, "fo": fo, "tool": tool,
		"hand": Vector3.ZERO, "goal": Vector3.ZERO, "gw": 0.0, "ph": randf() * TAU, "tap": 0.0}


# ── 외부 조작 ───────────────────────────────────────────

## 다리 i 를 월드 점 p 로 가져간다 (w 0 이면 걸음에 맡긴다). 찌르기 · 앞발 들기 · 죽음 오므림.
func set_leg_goal(i: int, p: Vector3, w: float, n := Vector3.UP) -> void:
	var l: Dictionary = legs[i]
	l.goal = p
	l.gw = clampf(w, 0.0, 1.0)
	l.gn = n.normalized() if n.length() > 0.001 else Vector3.UP


func set_arm_goal(i: int, p: Vector3, w: float) -> void:
	var a: Dictionary = arms[i]
	a.goal = p
	a.gw = clampf(w, 0.0, 1.0)


func arm_index(kind: String) -> int:
	for i in arms.size():
		if arms[i].kind == kind:
			return i
	return 0


## 지금 몸 좌표 → 월드
func to_world(local: Vector3) -> Vector3:
	return _xf * local


func body_xf() -> Transform3D:
	return _xf


func mouth_pos() -> Vector3:
	return head.global_transform * Vector3(0, -0.72, -2.5)


func gun_muzzle() -> Vector3:
	return gatling.global_transform * Vector3(0, 0, -1.6)


func gun_dir() -> Vector3:
	return -gatling.global_basis.z


func head_pos() -> Vector3:
	return head.global_transform * Vector3(0, 0.1, -1.6)


func hatch_pos() -> Vector3:
	return abdomen.global_transform * Vector3(0, 0.2, 3.7)


func tool_pos(kind: String) -> Vector3:
	var a: Dictionary = arms[arm_index(kind)]
	return (a.tool as Node3D).global_transform * Vector3(0, 0, -1.0)


## 모든 발을 지금 쉬는 자리에 바로 내려놓는다 (순간 이동 뒤)
func snap_feet() -> void:
	_update_xf(1.0)
	for l in legs:
		var pr := stage.project(_rest_world(l))
		l.foot = pr.p
		l.n = pr.n
		l.t = -1.0
	for a in arms:
		a.hand = _xf * (a.rest as Vector3)
	_prev_c = c
	_first = false


func set_flash(mat: Material) -> void:
	for m in meshes:
		if is_instance_valid(m):
			(m as MeshInstance3D).material_overlay = mat


# ── 매 프레임 ───────────────────────────────────────────

func update(dt: float) -> void:
	if dt <= 0.0:
		return
	_t += dt
	if _first:
		snap_feet()
	vel = vel.lerp((c - _prev_c) / dt, 1.0 - exp(-12.0 * dt))
	_prev_c = c
	speed = vel.length()
	var accel := (vel - _prev_vel) / dt
	_prev_vel = vel
	# 몸 기울기 스프링: 가속하면 반대로 젖혀진다 (몸 좌표)
	var la := Basis(_q).inverse() * accel
	_lean_v += (Vector3(clampf(la.z, -30, 30) * 0.004, 0, clampf(-la.x, -30, 30) * 0.004) - _lean) * 60.0 * dt - _lean_v * 9.0 * dt
	_lean += _lean_v * dt
	# 출렁임 스프링 (발이 닿으면 아래로 눌린다)
	_bob_v += (-_bob * 90.0 - _bob_v * 10.0) * dt
	_bob += _bob_v * dt
	_update_xf(1.0 - exp(-7.0 * dt))
	_update_legs(dt)
	_update_arms(dt)
	_update_head(dt)
	_update_parts(dt)


func _ortho_basis(u: Vector3, f: Vector3) -> Basis:
	u = u.normalized()
	var ff := f - u * f.dot(u)
	if ff.length() < 0.05:
		ff = (Basis(_q) * Vector3.FORWARD)
		ff -= u * ff.dot(u)
		if ff.length() < 0.05:
			ff = Vector3.FORWARD if absf(u.z) < 0.9 else Vector3.UP
			ff -= u * ff.dot(u)
	ff = ff.normalized()
	var z := -ff
	var x := u.cross(z).normalized()
	return Basis(x, u, z)


func _update_xf(k: float) -> void:
	var target := _ortho_basis(up, fwd).get_rotation_quaternion()
	if _first:
		_q = target
	else:
		_q = _q.slerp(target, k)
	var b := Basis(_q)
	# 자세 보정: 위협(앞을 들어 세움) · 웅크림 · 기울기 · 경련 · 숨
	var pitch := rear * 0.55 - _lean.x - crouch * 0.06
	var roll := _lean.z
	var breathe := sin(_t * 1.7) * 0.012
	var jit := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * twitch * 0.08
	var lb := Basis(Vector3.RIGHT, pitch + breathe + jit.x) * Basis(Vector3.FORWARD, roll + jit.z) * Basis(Vector3.UP, jit.y)
	var h := ride * (1.0 - crouch * 0.45) * (1.0 - curl * 0.62) + rear * 0.8 + _bob - Stage.RIDE
	_xf = Transform3D(b * lb * Basis.from_scale(Vector3.ONE * BODY_S), c + b.y * h)
	root.global_transform = _xf


func _rest_world(l: Dictionary) -> Vector3:
	var r: Vector3 = l.rest
	var sp := clampf(speed / 10.0, 0.0, 1.0)
	# 빠를수록 다리를 조금 더 넓게 벌린다
	var local := Vector3(r.x * (1.0 + sp * 0.06), -ride * (1.0 - crouch * 0.45) - rear * 0.0, r.z * (1.0 + sp * 0.1))
	var b := Basis(_q)
	return c + b * local


func _update_legs(dt: float) -> void:
	var stepping := [0, 0]
	for l in legs:
		if float(l.t) >= 0.0:
			stepping[int(l.group)] += 1
	var predict := vel.limit_length(16.0)
	var base_thr := lerpf(1.25, 2.2, clampf(speed / 8.0, 0.0, 1.0)) * stride_k
	var dur := clampf(0.4 - speed * 0.016, 0.15, 0.4)
	var bxf := _xf
	for l in legs:
		var hip: Vector3 = bxf * (l.hip as Vector3)
		var desired := _rest_world(l)
		var pr := stage.project(desired + predict * dur * 0.55)
		var tgt: Vector3 = pr.p
		var tn: Vector3 = pr.n
		var gw: float = l.gw
		if float(l.t) < 0.0:
			var err := (l.foot as Vector3).distance_to(tgt)
			var stretch := hip.distance_to(l.foot) > REACH * 0.97
			var other := 1 - int(l.group)
			var may: bool = int(stepping[other]) == 0
			# 거의 서 있을 때는 오차가 조금만 쌓여도 한 다리씩 고쳐 딛는다
			var thr := base_thr if speed > 0.6 else 0.7 * stride_k
			if gw < 0.5 and ((err > thr and may) or stretch or (err > thr * 2.4)):
				l.from = l.foot
				l.from_n = l.n
				l.to = tgt
				l.to_n = tn
				l.t = 0.0
				l.dur = dur * randf_range(0.92, 1.08)
				l.lift = clampf(0.7 + speed * 0.08, 0.7, 1.7) + (0.5 if err > 4.0 else 0.0)
				stepping[int(l.group)] += 1
		if float(l.t) >= 0.0:
			l.t = float(l.t) + dt / float(l.dur)
			# 걷는 중에 목표가 움직이면 착지점도 따라간다
			l.to = (l.to as Vector3).lerp(tgt, 1.0 - exp(-6.0 * dt))
			l.to_n = tn
			var k := clampf(float(l.t), 0.0, 1.0)
			var e := k * k * (3.0 - 2.0 * k)
			var n := (l.from_n as Vector3).slerp(l.to_n, e).normalized() if not (l.from_n as Vector3).is_equal_approx(l.to_n) else (l.to_n as Vector3)
			var arc := sin(k * PI)
			# 발을 몸 쪽으로 살짝 끌어 올렸다가 내뻗는다 (거미의 갈고리 같은 궤적)
			var inward := (c - (l.from as Vector3).lerp(l.to, e))
			inward -= n * inward.dot(n)
			var p := (l.from as Vector3).lerp(l.to, e) + n * arc * float(l.lift) + inward.normalized() * arc * 0.35 * float(l.lift)
			l.foot = p
			l.n = n
			if float(l.t) >= 1.0:
				l.t = -1.0
				# 착지점은 걷는 중에 두 면 사이로 끌렸을 수 있으니 다시 면에 붙인다
				var land := stage.project(l.to)
				l.foot = land.p
				l.n = land.n
				_bob_v -= 0.6 + speed * 0.05
				foot_planted.emit(l.foot, l.n, int(l.i), clampf(speed / 12.0, 0.15, 1.0))
		# 외부 목표 (찌르기 · 들기 · 오므림)
		var foot: Vector3 = l.foot
		var fn: Vector3 = l.n
		if gw > 0.0:
			foot = foot.lerp(l.goal, gw)
			fn = fn.slerp(l.gn, gw).normalized()
		if curl > 0.0:
			# 죽은 거미처럼 다리를 몸 아래로 접는다
			var under := bxf * Vector3((l.hip as Vector3).x * 0.6, -0.6, (l.hip as Vector3).z * 0.4 - 0.4)
			foot = foot.lerp(under, curl)
			fn = fn.slerp(bxf.basis.y.normalized(), curl).normalized()
		_pose_leg(l, hip, foot, fn)


## 3관절 IK: 발허리를 면 법선 쪽으로 세우고, 고관절 → 발목을 넓적다리 · 정강이 2관절로 푼다 (무릎은 위로)
func _pose_leg(l: Dictionary, hip: Vector3, foot: Vector3, n: Vector3) -> void:
	var b := _xf.basis.orthonormalized()
	var bup := b.y
	var out := foot - hip
	out -= bup * out.dot(bup)
	out = out.normalized() if out.length() > 0.01 else b.x * float(l.side)
	var meta_dir := (n * 0.82 - out * 0.32 + bup * 0.15).normalized()
	var ank := foot + meta_dir * L_META
	var d := ank - hip
	var dl := d.length()
	if dl > REACH:
		ank = hip + d / dl * REACH
		d = ank - hip
		dl = REACH
	dl = maxf(dl, absf(L_FEMUR - L_TIBIA) + 0.05)
	var axis := d / dl
	var pole := (bup * 1.0 + out * 0.35).normalized()
	var perp := pole - axis * pole.dot(axis)
	perp = perp.normalized() if perp.length() > 0.01 else bup
	var a := (dl * dl + L_FEMUR * L_FEMUR - L_TIBIA * L_TIBIA) / (2.0 * dl)
	var hgt := sqrt(maxf(0.0, L_FEMUR * L_FEMUR - a * a))
	var knee := hip + axis * a + perp * hgt
	var bulge := perp
	(l.fem as Node3D).global_transform = Transform3D(_look(knee - hip, bulge), hip)
	(l.tib as Node3D).global_transform = Transform3D(_look(ank - knee, bulge), knee)
	(l.meta as Node3D).global_transform = Transform3D(_look(foot - ank, bulge), ank)
	var pn := (knee - hip).cross(ank - knee)
	pn = pn.normalized() if pn.length() > 0.001 else b.z
	(l.knee as Node3D).global_transform = Transform3D(_axis_y(pn), knee)
	(l.ank as Node3D).global_transform = Transform3D(_axis_y(pn), ank)
	(l.pad as Node3D).global_transform = Transform3D(_ortho_up(n, out), foot)
	l.knee_p = knee


static func _look(v: Vector3, up_hint: Vector3) -> Basis:
	var nv := v.normalized()
	var u := up_hint - nv * up_hint.dot(nv)
	if u.length() < 0.01:
		u = Vector3.UP if absf(nv.y) < 0.95 else Vector3.FORWARD
	return Basis.looking_at(nv, u.normalized())


## Y 축이 a 를 향하는 기저 (원판 관절)
static func _axis_y(a: Vector3) -> Basis:
	var y := a.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	return Basis(x, y, z)


static func _ortho_up(n: Vector3, f: Vector3) -> Basis:
	var y := n.normalized()
	var z := -(f - y * f.dot(y))
	z = z.normalized() if z.length() > 0.01 else y.cross(Vector3.RIGHT).normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, x.cross(y))


func _update_arms(dt: float) -> void:
	var b := _xf.basis.orthonormalized()
	var walk := clampf(speed / 6.0, 0.0, 1.0)
	for i in arms.size():
		var a: Dictionary = arms[i]
		a.ph = float(a.ph) + dt * (1.4 + speed * 0.5)
		var s: Vector3 = _xf * (a.sh as Vector3)
		var rest: Vector3 = a.rest
		# 더듬이처럼: 서 있으면 천천히 꿈틀대고, 걸으면 번갈아 바닥을 톡톡 짚는다
		var tap := maxf(0.0, sin(float(a.ph) * 2.0 + i * 1.6)) * walk
		var idle := Vector3(sin(_t * 1.3 + i * 2.1) * 0.18, sin(_t * 0.9 + i) * 0.22 + 0.25 * (1.0 - walk), cos(_t * 1.1 + i * 1.3) * 0.15)
		var local := rest + idle * (1.0 - walk * 0.6) + Vector3(0, 0.55 * tap, 0.35 * tap) + Vector3(0, rear * 1.8, rear * 0.6)
		var want := _xf * local
		want = want.lerp(a.goal, float(a.gw))
		a.hand = (a.hand as Vector3).lerp(want, 1.0 - exp(-(10.0 + float(a.gw) * 14.0) * dt))
		_pose_arm(a, s, a.hand, b)


func _pose_arm(a: Dictionary, s: Vector3, hand: Vector3, b: Basis) -> void:
	var l1: float = a.l1
	var l2: float = a.l2
	var d := hand - s
	var dl := clampf(d.length(), 0.2, l1 + l2 - 0.02)
	var axis := d.normalized() if d.length() > 0.01 else -b.z
	hand = s + axis * dl
	var pole := (b.y * 1.0 + b.z * 0.4 + b.x * signf((a.sh as Vector3).x) * 0.3).normalized()
	var perp := pole - axis * pole.dot(axis)
	perp = perp.normalized() if perp.length() > 0.01 else b.y
	var aa := (dl * dl + l1 * l1 - l2 * l2) / (2.0 * dl)
	var hgt := sqrt(maxf(0.0, l1 * l1 - aa * aa))
	var el := s + axis * aa + perp * hgt
	(a.shn as Node3D).global_transform = Transform3D(b, s)
	(a.up as Node3D).global_transform = Transform3D(_look(el - s, perp), s)
	(a.el as Node3D).global_transform = Transform3D(_axis_y(b.x), el)
	(a.fo as Node3D).global_transform = Transform3D(_look(hand - el, perp), el)
	(a.tool as Node3D).global_transform = Transform3D(_look(hand - el, perp), hand)


## 머리: 볼 곳 쪽으로 툭툭 끊어 돌린다
func _update_head(dt: float) -> void:
	_sacc_t -= dt
	if _sacc_t <= 0.0:
		_sacc_t = randf_range(0.25, 1.1)
		_sacc_off = Vector2(randf_range(-0.25, 0.25), randf_range(-0.12, 0.12)) * (1.0 if randf() < 0.6 else 0.2)
	var hb := root.global_basis
	var hp := root.global_position + hb * Vector3(0, 0.2, -1.4)
	var lp := hb.inverse() * (look_at_p - hp)
	var yaw := clampf(atan2(-lp.x, -lp.z), -0.7, 0.7)
	var pitch := clampf(atan2(lp.y, Vector2(lp.x, lp.z).length()), -0.6, 0.45)
	_head_goal = Vector2(yaw, pitch) + _sacc_off
	# 단속 운동: 목표가 바뀌면 빠르게 붙고, 그 사이엔 거의 멈춰 있다
	var k := 1.0 - exp(-16.0 * dt)
	_head_yaw = lerpf(_head_yaw, _head_goal.x, k)
	_head_pitch = lerpf(_head_pitch, _head_goal.y, k)
	head.rotation = Vector3(_head_pitch + rear * -0.3, _head_yaw, sin(_t * 0.6) * 0.02)


func _update_parts(dt: float) -> void:
	# 뒤 몸통: 몸의 움직임에 늦게 따라오는 스프링 + 숨 + 들어 올림
	var lb := Basis(_q).inverse() * vel
	_abd_v += (Vector2(-lb.z * 0.012, lb.x * 0.01) - _abd) * 40.0 * dt - _abd_v * 6.0 * dt
	_abd += _abd_v * dt
	abdomen.rotation = Vector3(_abd.x - abd_raise * 0.55 + sin(_t * 1.7) * 0.02 - rear * 0.2, 0, _abd.y)
	abdomen.scale = Vector3(1.0, 1.0 + sin(_t * 1.7) * 0.012, 1.0)
	hatch.rotation.x = -hatch_open * 1.9
	hatch_glow.emission_energy_multiplier = 0.4 + hatch_open * 5.0
	gatling.rotate_z(gat_spin * dt)
	if saw_disc:
		saw_disc.rotate_x(saw_spin * dt)
	var e := eye_k * (0.9 + 0.1 * sin(_t * 17.0))
	for m in eye_mats:
		m.emission_energy_multiplier = 2.0 * e
	for m in vent_mats:
		m.emission_energy_multiplier = 2.2 * e
	eye_light.light_energy = 2.2 * e
	searchlight.light_energy = 7.0 * light_k * eye_k
	searchlight.visible = light_k * eye_k > 0.02
	torch_mat.emission_energy_multiplier = torch_k * 8.0 * (0.8 + 0.2 * sin(_t * 60.0))
	torch_light.light_energy = torch_k * 4.0
	(torch_mat as StandardMaterial3D).albedo_color.a = 1.0
	(arms[0].tool as Node3D).get_node("Flame").visible = torch_k > 0.02
	mouth_glow.emission_energy_multiplier = mouth_k * 6.0
