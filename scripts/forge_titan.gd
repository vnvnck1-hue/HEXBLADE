extends RefCounted
## 보스 모델: 용광로 거신 "VULCAN". 정면은 +Z(플레이어 쪽), 원점은 몸통 바닥 중심(용암 수면 부근).
## 하반신은 용암에 잠겨 있고, 둥근 모서리 파츠(boss_tank.gd 도우미)에 주황 발광 이음새를 두른다.
## 몸통 폭 약 11m, 머리 꼭대기 약 13m (플레이어 로봇 약 1.5m).
## 팔은 forge_boss.gd 가 IK 로 매 프레임 자세를 잡는다. 위팔·아래팔 노드는 각각 원점(관절)에서 -Z 로 ARM_LEN 만큼 뻗는다.

const BT := preload("res://scripts/boss_tank.gd")

const IRON := Color("5b5566")
const IRON_MID := Color("46414f")
const IRON_DARK := Color("312d38")
const IRON_LIGHT := Color("766f80")
const BORE := Color("140f14")
const MOLTEN := Color("ff7a1a")
const HOT := Color("ffc24a")

const ARM_LEN := 9.0
const SHOULDERS := [Vector3(-6.9, 7.6, 2.2), Vector3(6.9, 7.6, 2.2)]   # 몸(Body) 기준


## root: 몸통을 붙일 노드, arm_root: 팔을 붙일 노드(전역 변환으로 움직이므로 흔들리지 않는 부모)
static func build(root: Node3D, arm_root: Node3D) -> Dictionary:
	var j := {}
	var body := BT.pivot(root, Vector3.ZERO, "Body")
	j.body = body
	_torso(body, j)
	var head := BT.pivot(body, Vector3(0, 9.6, 1.9), "Head")
	j.head = head
	_head(head, j)
	for i in 2:
		_shoulder(body, SHOULDERS[i], -1 if i == 0 else 1)
	var arms: Array = []
	for i in 2:
		var side := -1 if i == 0 else 1
		var upper := Node3D.new()
		upper.name = "UpperArm"
		arm_root.add_child(upper)
		_upper(upper, side)
		var fore := Node3D.new()
		fore.name = "ForeArm"
		arm_root.add_child(fore)
		var parts := _fore(fore, side)
		arms.append({"upper": upper, "fore": fore, "glow": parts.glow, "rings": parts.rings})
	j.arms = arms
	return j


static func _torso(b: Node3D, j: Dictionary) -> void:
	# 용암에 잠긴 하체 덩어리 + 수면선의 달아오른 띠
	BT.rbox(b, Vector3(11.6, 5.6, 8.6), 1.2, Vector3(0, 0.2, 0), IRON_DARK)
	BT.glow(b, Vector3(11.9, 0.3, 8.9), Vector3(0, -0.75, 0), MOLTEN, 2.2)
	# 복부 장갑
	BT.rbox(b, Vector3(9.8, 2.2, 7.6), 0.7, Vector3(0, 3.6, 0.2), IRON_MID)
	for x in [-3.2, 0.0, 3.2]:
		BT.rbox(b, Vector3(2.8, 1.5, 0.5), 0.2, Vector3(x, 3.5, 4.1), IRON)
	BT.glow(b, Vector3(9.2, 0.16, 0.16), Vector3(0, 2.75, 4.35), MOLTEN, 2.4)
	# 가슴
	BT.rbox(b, Vector3(10.6, 4.4, 7.2), 1.1, Vector3(0, 6.3, 0.4), IRON)
	BT.rbox(b, Vector3(8.6, 0.8, 5.8), 0.35, Vector3(0, 8.55, 0.0), IRON_LIGHT)
	# 가슴 용광로: 둘레 고리 + 안쪽 검은 판 + 노심(발광 구)
	for i in 16:
		var a := TAU * i / 16.0
		BT.rbox(b, Vector3(0.95, 0.55, 0.9), 0.2, Vector3(cos(a) * 2.05, 5.5 + sin(a) * 2.05, 4.05), IRON_DARK, Vector3(0, 0, rad_to_deg(a) + 90.0))
	BT.cyl(b, 2.0, 2.0, 0.4, Vector3(0, 5.5, 3.3), BORE, Vector3(90, 0, 0), 28)
	j.core = BT.glow_ball(b, 1.35, Vector3(0, 5.5, 3.7), MOLTEN, 2.0)
	# 1페이즈: 노심 앞 창살과 좌우 장갑판 (2페이즈 전환 때 떨어져 나간다)
	var grille: Array = []
	for i in 5:
		grille.append(BT.rbox(b, Vector3(0.3, 3.6, 0.32), 0.12, Vector3(-1.4 + i * 0.7, 5.5, 4.6), IRON_MID))
	j.grille = grille
	var plates: Array = []
	for side in [-1, 1]:
		var pl := BT.pivot(b, Vector3(side * 3.55, 5.9, 4.0), "ChestPlate")
		pl.rotation_degrees = Vector3(0, side * 14.0, side * 3.0)
		BT.rbox(pl, Vector3(3.4, 3.6, 0.9), 0.4, Vector3.ZERO, IRON_LIGHT)
		BT.rbox(pl, Vector3(2.6, 0.3, 0.3), 0.1, Vector3(0, 1.2, 0.45), IRON_DARK)
		BT.glow(pl, Vector3(0.14, 2.2, 0.1), Vector3(side * -1.1, -0.2, 0.47), MOLTEN, 2.0)
		for k in 3:
			BT.ball(pl, 0.12, Vector3(side * 1.1, -1.0 + k * 0.9, 0.46), IRON_DARK)
		plates.append(pl)
	j.plates = plates
	# 옆구리 배기 틈
	for side in [-1, 1]:
		for k in 3:
			BT.glow(b, Vector3(0.12, 0.16, 2.2), Vector3(side * 5.32, 4.4 + k * 0.7, 0.8), MOLTEN, 1.8)
	# 등: 큰 탱크 + 굴뚝 두 개 (끝에서 연기·불꽃)
	BT.rbox(b, Vector3(7.4, 4.2, 3.2), 0.9, Vector3(0, 8.2, -3.6), IRON_MID)
	var stacks: Array = []
	for side in [-1, 1]:
		BT.cyl(b, 0.75, 0.9, 6.0, Vector3(side * 2.9, 10.6, -3.4), IRON_DARK, Vector3.ZERO, 16)
		BT.cyl(b, 1.0, 1.0, 0.6, Vector3(side * 2.9, 13.7, -3.4), IRON_MID, Vector3.ZERO, 16)
		BT.glow_ball(b, 0.6, Vector3(side * 2.9, 13.9, -3.4), MOLTEN, 2.2)
		stacks.append(BT.pivot(b, Vector3(side * 2.9, 14.2, -3.4), "Stack"))
	j.stacks = stacks
	# 가슴 옆 굵은 배선
	for side in [-1, 1]:
		for k in 2:
			BT.cyl(b, 0.28, 0.28, 3.6, Vector3(side * (4.6 + k * 0.6), 5.0 - k * 0.6, 3.3 - k * 0.5), IRON_DARK, Vector3(18, 0, side * 24), 10)


## 둥근 얼굴판에 다섯 눈 (주사위 5 배열), 아래로 흘러내리는 쇳물
static func _head(h: Node3D, j: Dictionary) -> void:
	BT.rbox(h, Vector3(3.8, 1.8, 3.2), 0.5, Vector3(0, -1.4, -0.7), IRON_DARK)
	BT.rbox(h, Vector3(5.2, 4.6, 3.6), 1.2, Vector3(0, 0.6, -1.1), IRON_MID)
	BT.cyl(h, 3.05, 3.05, 0.7, Vector3(0, 0.55, 0.55), IRON_DARK, Vector3(90, 0, 0), 32)
	BT.cyl(h, 2.8, 2.8, 1.0, Vector3(0, 0.55, 0.95), IRON, Vector3(90, 0, 0), 32)
	# 발광 테: 주황 원판 위에 한 단 작은 판을 덮어 띠만 보이게 한다
	var ring := CylinderMesh.new()
	ring.top_radius = 2.5
	ring.bottom_radius = 2.5
	ring.height = 0.08
	ring.radial_segments = 32
	var rg := Pal.flat_mesh(ring, MOLTEN, 2.0)
	rg.rotation_degrees.x = 90.0
	rg.position = Vector3(0, 0.55, 1.47)
	h.add_child(rg)
	j.face_ring = rg
	BT.cyl(h, 2.25, 2.25, 0.14, Vector3(0, 0.55, 1.5), IRON_MID, Vector3(90, 0, 0), 32)
	var eyes: Array = []
	for off in [Vector2(0, 0), Vector2(-1.2, 1.15), Vector2(1.2, 1.15), Vector2(-1.2, -1.05), Vector2(1.2, -1.05)]:
		var r := 0.62 if off == Vector2.ZERO else 0.5
		BT.cyl(h, r + 0.14, r + 0.14, 0.2, Vector3(off.x, 0.55 + off.y, 1.58), BORE, Vector3(90, 0, 0), 20)
		var e := BT.glow_ball(h, r, Vector3(off.x, 0.55 + off.y, 1.6), HOT, 2.6)
		e.scale = Vector3(1, 1, 0.5)
		eyes.append(e)
	j.eyes = eyes
	# 이마 볏 · 뿔
	BT.rbox(h, Vector3(4.6, 0.9, 2.4), 0.3, Vector3(0, 3.3, -0.4), IRON_LIGHT)
	for side in [-1, 1]:
		BT.cyl(h, 0.12, 0.42, 1.8, Vector3(side * 2.3, 3.6, -0.6), IRON_DARK, Vector3(-20, 0, side * -28), 10)
	# 턱과 흘러내리는 쇳물
	BT.rbox(h, Vector3(3.4, 1.0, 1.7), 0.4, Vector3(0, -1.95, 1.0), IRON_DARK)
	var drips: Array = []
	for d in [[-1.1, 1.6], [-0.4, 2.8], [0.2, 3.6], [0.8, 2.2], [1.3, 1.3]]:
		var ln: float = d[1]
		var g := BT.glow(h, Vector3(0.16, ln, 0.16), Vector3(d[0], -2.4 - ln * 0.5, 1.55), MOLTEN, 2.2)
		BT.glow_ball(g, 0.16, Vector3(0, -ln * 0.5, 0), HOT, 2.4)
		drips.append(g)
	j.drips = drips


static func _shoulder(b: Node3D, pos: Vector3, side: int) -> void:
	BT.ball(b, 1.9, pos, IRON_MID)
	BT.rbox(b, Vector3(4.8, 2.3, 5.4), 0.9, pos + Vector3(side * 0.6, 2.0, -0.3), IRON, Vector3(0, 0, -side * 12))
	BT.rbox(b, Vector3(3.8, 0.7, 4.4), 0.3, pos + Vector3(side * 0.9, 3.3, -0.3), IRON_LIGHT, Vector3(0, 0, -side * 12))
	BT.glow(b, Vector3(0.14, 0.14, 4.4), pos + Vector3(side * 2.95, 1.5, -0.3), MOLTEN, 2.2, Vector3(0, 0, -side * 12))
	for k in 3:
		BT.glow(b, Vector3(0.12, 0.7, 0.12), pos + Vector3(side * 2.6, 0.9, -1.4 + k * 1.2), MOLTEN, 1.8)


## 위팔: 관절(원점)에서 -Z 로 ARM_LEN
static func _upper(u: Node3D, side: int) -> void:
	BT.ball(u, 1.55, Vector3.ZERO, IRON_DARK)
	BT.rbox(u, Vector3(2.3, 2.3, ARM_LEN - 2.0), 0.7, Vector3(0, 0, -ARM_LEN * 0.5), IRON)
	BT.rbox(u, Vector3(2.6, 0.6, ARM_LEN - 3.6), 0.25, Vector3(0, 1.25, -ARM_LEN * 0.5), IRON_LIGHT)
	BT.cyl(u, 0.3, 0.3, ARM_LEN - 3.0, Vector3(side * 1.35, -0.8, -ARM_LEN * 0.5), IRON_LIGHT, Vector3(90, 0, 0), 10)
	BT.glow(u, Vector3(0.12, 0.12, ARM_LEN - 3.2), Vector3(side * 1.18, 0.35, -ARM_LEN * 0.5), MOLTEN, 2.0)
	BT.ball(u, 1.5, Vector3(0, 0, -ARM_LEN), IRON_MID)


## 아래팔 = 도가니 포신. 끝(-ARM_LEN)이 포구이자 내려찍는 주먹 면.
static func _fore(f: Node3D, _side: int) -> Dictionary:
	BT.rbox(f, Vector3(2.7, 2.7, 3.6), 0.8, Vector3(0, 0, -2.0), IRON_MID)
	BT.cyl(f, 1.55, 1.55, 5.8, Vector3(0, 0, -ARM_LEN + 3.0), IRON, Vector3(90, 0, 0), 28)
	var rings: Array = []
	for z in [-4.0, -6.0, -7.9]:
		BT.cyl(f, 1.7, 1.7, 0.36, Vector3(0, 0, z), IRON_DARK, Vector3(90, 0, 0), 28)
	for z in [-5.0, -6.95]:
		var rc := CylinderMesh.new()
		rc.top_radius = 1.62
		rc.bottom_radius = 1.62
		rc.height = 0.14
		rc.radial_segments = 28
		var g := Pal.flat_mesh(rc, MOLTEN, 1.8)
		g.rotation_degrees.x = 90.0
		g.position = Vector3(0, 0, z)
		f.add_child(g)
		rings.append(g)
	BT.cyl(f, 1.78, 1.78, 0.55, Vector3(0, 0, -ARM_LEN + 0.28), IRON_DARK, Vector3(90, 0, 0), 28)
	BT.cyl(f, 1.05, 1.05, 0.06, Vector3(0, 0, -ARM_LEN - 0.02), BORE, Vector3(90, 0, 0), 24)
	var glow := BT.glow_ball(f, 0.85, Vector3(0, 0, -ARM_LEN + 0.15), MOLTEN, 1.6)
	glow.scale = Vector3(1, 1, 0.35)
	# 포신 윗면 냉각핀
	for k in 4:
		BT.rbox(f, Vector3(0.25, 0.5, 0.9), 0.08, Vector3(0, 1.6, -4.4 - k * 1.0), IRON_LIGHT)
	return {"glow": glow, "rings": rings}
