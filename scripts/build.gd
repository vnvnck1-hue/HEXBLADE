class_name Build
extends RefCounted
## 기본 도형 조합으로 로봇과 적을 만든다. 정면은 -Z.

static var _boxes := {}


static func box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, rot_deg := Vector3.ZERO, emission := 0.0) -> MeshInstance3D:
	var key := str(size)
	if not _boxes.has(key):
		var b := BoxMesh.new()
		b.size = size
		_boxes[key] = b
	var mi := MeshInstance3D.new()
	mi.mesh = _boxes[key]
	mi.material_override = Pal.lit(c, emission)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func glow_box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, energy := 1.4, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := Pal.flat_mesh(b, c, energy)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func pivot(parent: Node3D, pos: Vector3, name: String) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.position = pos
	parent.add_child(n)
	return n


## 플레이어 로봇. 관절 노드를 딕셔너리로 돌려준다.
static func robot(visual: Node3D) -> Dictionary:
	var j := {}
	var legs := pivot(visual, Vector3.ZERO, "Legs")
	j.legs = legs
	for side in [-1, 1]:
		var hip := pivot(legs, Vector3(0.21 * side, 0.74, 0.02), "Hip")
		box(hip, Vector3(0.2, 0.38, 0.26), Vector3(0, -0.17, 0), Pal.P_BODY)
		box(hip, Vector3(0.24, 0.14, 0.3), Vector3(0.02 * side, 0.0, 0), Pal.P_DARK)
		var knee := pivot(hip, Vector3(0, -0.36, 0), "Knee")
		box(knee, Vector3(0.24, 0.32, 0.3), Vector3(0, -0.16, 0.03), Pal.P_LIGHT)
		box(knee, Vector3(0.3, 0.1, 0.44), Vector3(0, -0.34, -0.05), Pal.P_DARK)
		glow_box(knee, Vector3(0.06, 0.06, 0.04), Vector3(0.0, -0.1, -0.13), Pal.CYAN, 1.6)
		if side < 0:
			j.hip_l = hip
			j.knee_l = knee
		else:
			j.hip_r = hip
			j.knee_r = knee

	var upper := pivot(visual, Vector3(0, 0.74, 0), "Upper")
	j.upper = upper
	box(upper, Vector3(0.46, 0.18, 0.3), Vector3(0, 0.04, 0), Pal.P_DARK)
	var torso := pivot(upper, Vector3(0, 0.1, 0), "Torso")
	j.torso = torso
	box(torso, Vector3(0.64, 0.42, 0.46), Vector3(0, 0.24, 0), Pal.P_BODY)
	box(torso, Vector3(0.42, 0.22, 0.08), Vector3(0, 0.28, -0.25), Pal.P_LIGHT)
	box(torso, Vector3(0.46, 0.36, 0.24), Vector3(0, 0.3, 0.3), Pal.P_DARK)
	# 백팩 부스터 노즐 + 불꽃 (부스트 중에만 보임)
	var flame := CylinderMesh.new()
	flame.top_radius = 0.1
	flame.bottom_radius = 0.0
	flame.height = 1.0
	flame.radial_segments = 8
	var core := CylinderMesh.new()
	core.top_radius = 0.05
	core.bottom_radius = 0.0
	core.height = 1.0
	core.radial_segments = 6
	for side in [-1, 1]:
		box(torso, Vector3(0.14, 0.18, 0.14), Vector3(0.15 * side, 0.14, 0.44), Pal.P_GREY)
		var jet := pivot(torso, Vector3(0.15 * side, 0.04, 0.46), "Jet")
		jet.rotation_degrees.x = -40.0
		var f := Pal.flat_mesh(flame, Pal.CYAN, 1.6)
		f.position.y = -0.5
		jet.add_child(f)
		var c := Pal.flat_mesh(core, Color(0.9, 1.0, 1.0), 2.2)
		c.position.y = -0.4
		jet.add_child(c)
		jet.scale = Vector3(1, 0.001, 1)
		jet.visible = false
		if side < 0:
			j.jet_l = jet
		else:
			j.jet_r = jet
	# 등에 멘 포신 (GIF 의 회색 긴 막대)
	box(torso, Vector3(0.13, 0.13, 0.95), Vector3(0.16, 0.66, 0.42), Pal.P_GREY, Vector3(-32, 0, 0))
	box(torso, Vector3(0.2, 0.2, 0.26), Vector3(0.16, 0.5, 0.2), Pal.P_DARK, Vector3(-32, 0, 0))
	# 머리
	var head := pivot(torso, Vector3(0, 0.5, -0.04), "Head")
	box(head, Vector3(0.3, 0.22, 0.32), Vector3(0, 0.06, 0), Pal.P_LIGHT)
	glow_box(head, Vector3(0.24, 0.06, 0.04), Vector3(0, 0.07, -0.17), Pal.CYAN, 1.8)
	box(head, Vector3(0.05, 0.22, 0.05), Vector3(-0.12, 0.26, 0.06), Pal.P_DARK)
	# 어깨
	for side in [-1, 1]:
		box(torso, Vector3(0.3, 0.28, 0.4), Vector3(0.46 * side, 0.38, 0), Pal.P_LIGHT)
		glow_box(torso, Vector3(0.04, 0.12, 0.2), Vector3(0.62 * side, 0.36, 0), Pal.CYAN, 1.3)
	# 왼팔: 사격 팔
	var arm_l := pivot(torso, Vector3(-0.46, 0.3, 0), "ArmL")
	box(arm_l, Vector3(0.17, 0.3, 0.18), Vector3(0, -0.18, 0), Pal.P_BODY)
	box(arm_l, Vector3(0.19, 0.16, 0.42), Vector3(0, -0.34, -0.14), Pal.P_DARK)
	box(arm_l, Vector3(0.11, 0.12, 0.5), Vector3(0, -0.33, -0.5), Pal.P_GREY)
	glow_box(arm_l, Vector3(0.06, 0.06, 0.06), Vector3(0, -0.24, -0.62), Pal.CYAN, 1.8)
	var muzzle := pivot(arm_l, Vector3(0, -0.33, -0.8), "Muzzle")
	j.arm_l = arm_l
	j.muzzle = muzzle
	# 오른팔: 녹색 검
	var arm_r := pivot(torso, Vector3(0.46, 0.3, 0), "ArmR")
	box(arm_r, Vector3(0.17, 0.3, 0.18), Vector3(0, -0.18, 0), Pal.P_BODY)
	box(arm_r, Vector3(0.19, 0.16, 0.36), Vector3(0, -0.34, -0.1), Pal.P_DARK)
	var blade := pivot(arm_r, Vector3(0.02, -0.34, -0.26), "Blade")
	box(blade, Vector3(0.08, 0.08, 0.2), Vector3(0, 0, 0.02), Pal.P_GREY)
	glow_box(blade, Vector3(0.08, 0.035, 1.35), Vector3(0, 0, -0.76), Pal.BLADE, 1.6)
	glow_box(blade, Vector3(0.03, 0.045, 1.2), Vector3(0, 0.01, -0.72), Color("e8ffb0"), 1.8)
	blade.rotation_degrees = Vector3(38, -18, 0)
	j.arm_r = arm_r
	j.blade = blade
	return j


## 적: 흰색 몸체 + 붉은 코어
static func drone(visual: Node3D) -> Dictionary:
	var j := {}
	var body := pivot(visual, Vector3(0, 1.0, 0), "Body")
	j.body = body
	var cube := box(body, Vector3(0.78, 0.74, 0.78), Vector3.ZERO, Pal.E_WHITE)
	box(body, Vector3(0.62, 0.1, 0.62), Vector3(0, 0.41, 0), Color("f6f5fb"))
	box(body, Vector3(0.12, 0.34, 0.46), Vector3(0.45, -0.02, 0.08), Pal.E_GREY)
	box(body, Vector3(0.12, 0.34, 0.46), Vector3(-0.45, -0.02, 0.08), Pal.E_GREY)
	box(body, Vector3(0.36, 0.16, 0.2), Vector3(0, -0.3, 0.36), Pal.E_GREY)
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	var core := MeshInstance3D.new()
	core.mesh = sm
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Pal.E_RED
	cm.emission_enabled = true
	cm.emission = Pal.E_RED
	cm.emission_energy_multiplier = 0.6
	cm.roughness = 0.35
	core.material_override = cm
	core.position = Vector3(0, 0.02, -0.4)
	body.add_child(core)
	j.core = core
	j.core_mat = cm
	j.cube = cube
	return j


## 고정 포탑: 십자 받침 위에서 도는 파란 포탑 머리 + 위아래 두 포신, 옆에 탄약 상자.
## body 는 다른 적과 같이 높이 1.0 에 두고, 받침(base)은 바닥 기준 좌표로 붙인다.
static func turret(visual: Node3D) -> Dictionary:
	var j := {}
	var body := pivot(visual, Vector3(0, 1.0, 0), "Body")
	j.body = body
	# 받침: 팔각 판 + 네 방향 다리 + 기둥 (돌지 않는다)
	var base := pivot(body, Vector3(0, -1.0, 0), "Base")
	j.base = base
	box(base, Vector3(0.9, 0.16, 0.9), Vector3(0, 0.08, 0), Pal.T_METAL)
	box(base, Vector3(0.9, 0.16, 0.9), Vector3(0, 0.08, 0), Pal.T_METAL, Vector3(0, 45, 0))
	for i in 4:
		var a := TAU * i / 4.0
		var d := Vector3(sin(a), 0, cos(a))
		box(base, Vector3(0.32, 0.14, 0.44), d * 0.56 + Vector3(0, 0.07, 0), Pal.T_METAL, Vector3(0, rad_to_deg(a), 0))
		box(base, Vector3(0.36, 0.07, 0.1), d * 0.8 + Vector3(0, 0.035, 0), Pal.T_DARK, Vector3(0, rad_to_deg(a), 0))
	box(base, Vector3(0.62, 0.1, 0.62), Vector3(0, 0.21, 0), Pal.T_DARK, Vector3(0, 45, 0))
	box(base, Vector3(0.36, 0.36, 0.36), Vector3(0, 0.42, 0), Pal.T_METAL_LIGHT)
	# 탄약 상자와 주변에 흩어진 탄피
	var crate := pivot(base, Vector3(0.8, 0, 0.45), "Crate")
	crate.rotation_degrees.y = 18.0
	box(crate, Vector3(0.52, 0.34, 0.42), Vector3(0, 0.17, 0), Pal.T_CRATE)
	box(crate, Vector3(0.56, 0.08, 0.46), Vector3(0, 0.38, 0), Pal.T_CRATE_LIGHT, Vector3(0, 0, -5))
	box(crate, Vector3(0.05, 0.3, 0.44), Vector3(-0.16, 0.16, 0), Pal.T_CRATE_LIGHT)
	box(crate, Vector3(0.05, 0.3, 0.44), Vector3(0.16, 0.16, 0), Pal.T_CRATE_LIGHT)
	var shell := CylinderMesh.new()
	shell.top_radius = 0.06
	shell.bottom_radius = 0.06
	shell.height = 0.2
	shell.radial_segments = 8
	shell.rings = 1
	j.shell_mesh = shell
	j.shell_mat = Pal.lit(Pal.T_SHELL, 0.35)
	for s in [[Vector3(0.02, 0.48, 0.02), Vector3(0, 20, 90)], [Vector3(0.48, 0.06, 0.12), Vector3(90, 30, 0)],
			[Vector3(0.4, 0.06, -0.3), Vector3(90, -50, 0)], [Vector3(0.55, 0.1, -0.08), Vector3.ZERO]]:
		var mi := MeshInstance3D.new()
		mi.mesh = shell
		mi.material_override = j.shell_mat
		mi.position = s[0]
		mi.rotation_degrees = s[1]
		crate.add_child(mi)

	# 포탑 머리: 받침 위에서 좌우로만 돈다. 정면(-Z)이 포구 방향.
	var head := pivot(body, Vector3(0, -0.38, 0), "Head")
	j.head = head
	box(head, Vector3(0.46, 0.1, 0.46), Vector3(0, 0.05, 0), Pal.T_DARK)
	box(head, Vector3(0.6, 0.58, 0.54), Vector3(0.04, 0.4, 0.06), Pal.T_BLUE)
	box(head, Vector3(0.52, 0.06, 0.46), Vector3(0.04, 0.72, 0.06), Pal.T_BLUE_LIGHT)
	box(head, Vector3(0.3, 0.08, 0.5), Vector3(0.2, 0.8, 0.04), Pal.T_METAL_LIGHT, Vector3(0, 0, -28))
	# 뒤쪽에 꺾여 솟은 파란 장갑판
	box(head, Vector3(0.1, 0.7, 0.34), Vector3(-0.3, 0.78, 0.22), Pal.T_BLUE, Vector3(0, 0, 6))
	box(head, Vector3(0.1, 0.24, 0.34), Vector3(-0.21, 1.18, 0.22), Pal.T_BLUE_LIGHT, Vector3(0, 0, -48))
	# 정면 패널과 붉은 센서(코어)
	box(head, Vector3(0.3, 0.26, 0.05), Vector3(0.14, 0.42, -0.22), Pal.T_METAL_LIGHT)
	box(head, Vector3(0.2, 0.03, 0.03), Vector3(0.14, 0.33, -0.25), Pal.T_DARK)
	var core_box := BoxMesh.new()
	core_box.size = Vector3(0.11, 0.08, 0.04)
	var core := MeshInstance3D.new()
	core.mesh = core_box
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Pal.E_RED
	cm.emission_enabled = true
	cm.emission = Pal.E_RED
	cm.emission_energy_multiplier = 0.6
	cm.roughness = 0.35
	core.material_override = cm
	core.position = Vector3(0.14, 0.45, -0.26)
	head.add_child(core)
	j.core = core
	j.core_mat = cm
	j.cube = core
	# 포신 받침과 위아래 두 포신 (각 포신은 z 축으로 돌고, 쏠 때 뒤로 밀린다)
	box(head, Vector3(0.22, 0.46, 0.3), Vector3(-0.24, 0.4, -0.14), Pal.T_DARK)
	var barrels: Array = []
	var bores: Array = []
	var muzzles: Array = []
	for b in [[0.28, 1.0], [0.53, 0.8]]:
		var y: float = b[0]
		var bl: float = b[1]
		var bp := pivot(head, Vector3(-0.26, y, -0.28), "Barrel")
		box(bp, Vector3(0.2, 0.2, 0.18), Vector3(0, 0, -0.02), Pal.T_METAL)
		box(bp, Vector3(0.12, 0.12, 0.72 * bl), Vector3(0, 0, -0.08 - 0.36 * bl), Pal.T_METAL_LIGHT)
		box(bp, Vector3(0.22, 0.22, 0.14), Vector3(0, 0, -0.08 - 0.72 * bl), Pal.T_METAL)
		bores.append(glow_box(bp, Vector3(0.11, 0.11, 0.02), Vector3(0, 0, -0.16 - 0.72 * bl), Color("5a1418"), 1.0))
		muzzles.append(pivot(bp, Vector3(0, 0, -0.24 - 0.72 * bl), "Muzzle"))
		barrels.append(bp)
	j.barrels = barrels
	j.bores = bores
	j.muzzles = muzzles
	# 조준선: 발사 준비 중에만 보인다 (길이는 매 프레임 z 축 스케일로)
	var sight_box := BoxMesh.new()
	sight_box.size = Vector3(0.03, 0.03, 1.0)
	var sight := Pal.flat_mesh(sight_box, Pal.E_RED, 1.6)
	sight.visible = false
	head.add_child(sight)
	j.sight = sight
	return j


## 고속 요격기:납작한 흰 동체 + 뒤로 젖힌 날개 + 붉은 발광선. 코어는 기수 끝(레이저 포구).
static func striker(visual: Node3D) -> Dictionary:
	var j := {}
	var body := pivot(visual, Vector3(0, 1.0, 0), "Body")
	j.body = body
	var hull := box(body, Vector3(0.62, 0.32, 1.0), Vector3.ZERO, Pal.E_WHITE)
	box(body, Vector3(0.36, 0.14, 0.46), Vector3(0, 0.22, -0.06), Color("3a3848"))
	glow_box(body, Vector3(0.3, 0.04, 0.04), Vector3(0, 0.25, -0.3), Pal.E_RED, 1.8)
	box(body, Vector3(0.36, 0.22, 0.34), Vector3(0, -0.03, -0.62), Color("f6f5fb"), Vector3(10, 0, 0))
	for side in [-1, 1]:
		box(body, Vector3(0.95, 0.06, 0.42), Vector3(0.68 * side, 0.0, 0.16), Pal.E_WHITE, Vector3(0, 24 * side, 0))
		glow_box(body, Vector3(0.72, 0.03, 0.05), Vector3(0.64 * side, 0.045, 0.0), Pal.E_RED, 1.6, Vector3(0, 24 * side, 0))
		box(body, Vector3(0.06, 0.32, 0.34), Vector3(1.1 * side, 0.1, 0.4), Pal.E_GREY, Vector3(0, 24 * side, 0))
		box(body, Vector3(0.08, 0.08, 0.5), Vector3(0.2 * side, -0.19, -0.52), Pal.E_GREY)
		box(body, Vector3(0.22, 0.22, 0.32), Vector3(0.2 * side, -0.02, 0.6), Pal.E_GREY)
	# 엔진 불꽃: +Z 로 뻗는다. 대시 중에 길어진다.
	var flame := CylinderMesh.new()
	flame.top_radius = 0.1
	flame.bottom_radius = 0.0
	flame.height = 1.0
	flame.radial_segments = 8
	var jets: Array = []
	for side in [-1, 1]:
		var jet := pivot(body, Vector3(0.2 * side, -0.02, 0.76), "Jet")
		jet.rotation_degrees.x = -90.0
		var f := Pal.flat_mesh(flame, Color("ff5a30"), 1.8)
		f.position.y = -0.5
		jet.add_child(f)
		jet.scale = Vector3(1, 0.35, 1)
		jets.append(jet)
	j.jets = jets
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.3
	var core := MeshInstance3D.new()
	core.mesh = sm
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Pal.E_RED
	cm.emission_enabled = true
	cm.emission = Pal.E_RED
	cm.emission_energy_multiplier = 0.8
	cm.roughness = 0.35
	core.material_override = cm
	core.position = Vector3(0, -0.02, -0.82)
	body.add_child(core)
	j.core = core
	j.core_mat = cm
	j.cube = hull
	return j


## 중력 크롤러: 황토색 장갑 구체 + 짙은 금속 뚜껑·허리띠 + 정면 삼안(파란 발광) + 접이식 다리 4개.
## Body(높이) → Squash(찌그러짐) → Shell(굴러가며 회전하는 구체). 다리와 약점 코어는 Squash 에 붙어
## 구르지 않고, 구체 안에 접혀 있다가 펼쳐진다. 정면은 -Z.
const CR_R := 0.6
const CR_L1 := 0.5
const CR_L2 := 0.86

static func crawler(visual: Node3D) -> Dictionary:
	var j := {}
	var R := CR_R
	var body := pivot(visual, Vector3(0, R, 0), "Body")
	var squash := pivot(body, Vector3.ZERO, "Squash")
	var shell := pivot(squash, Vector3.ZERO, "Shell")
	j.body = body
	j.squash = squash
	j.shell = shell
	# 장갑 구체
	var sph := SphereMesh.new()
	sph.radius = R
	sph.height = R * 2.0
	sph.radial_segments = 24
	sph.rings = 12
	_keep(shell, sph, Pal.lit(Pal.CR_YELLOW), Vector3.ZERO)
	# 윗뚜껑: 납작한 금속 돔 (가장자리가 턱처럼 살짝 튀어나온다). 뒤쪽 경첩(Cap)으로 열려 약점 코어를 드러낸다.
	var hinge := pivot(shell, Vector3(0, R * 0.3, R * 0.92), "Cap")
	j.cap = hinge
	var cap := SphereMesh.new()
	cap.radius = R * 1.03
	cap.height = R * 1.03
	cap.is_hemisphere = true
	cap.radial_segments = 24
	cap.rings = 6
	var cap_mi := _keep(hinge, cap, Pal.lit(Pal.CR_METAL), Vector3(0, 0, -R * 0.92))
	cap_mi.scale = Vector3(1, 0.72, 1)
	box(hinge, Vector3(0.22, 0.05, 0.1), Vector3(0, R * 0.73, 0.1 - R * 0.92), Pal.CR_METAL_DARK)
	box(hinge, Vector3(0.08, 0.04, 0.06), Vector3(0, R * 0.68, -0.3 - R * 0.92), Pal.CR_METAL_DARK)
	box(hinge, Vector3(0.3, 0.07, 0.08), Vector3(0, 0.02, 0), Pal.CR_METAL_DARK)
	# 뚜껑 이음새에서 새어 나오는 붉은 빛 (뚜껑이 들리기 시작할 때만 보인다)
	var seam_m := TorusMesh.new()
	seam_m.inner_radius = R * 0.9
	seam_m.outer_radius = R * 1.0
	seam_m.rings = 28
	seam_m.ring_segments = 4
	var seam_glow := Pal.flat_mesh(seam_m, Pal.E_RED, 0.0)
	seam_glow.position = Vector3(0, R * 0.32, 0)
	seam_glow.scale = Vector3(1, 0.4, 1)
	shell.add_child(seam_glow)
	j.seam = seam_glow
	# 허리띠 (정면 삼안 아래를 두른다)
	var band := CylinderMesh.new()
	band.top_radius = R * 1.02
	band.bottom_radius = R * 1.0
	band.height = 0.13
	band.radial_segments = 24
	_keep(shell, band, Pal.lit(Pal.CR_METAL_DARK), Vector3(0, -R * 0.24, 0))
	# 장갑 이음새
	for a in [0.55, -0.55, 2.3, -2.3]:
		var n := Vector3(sin(a), 0.1, -cos(a)).normalized()
		var seam := box(shell, Vector3(0.025, 0.36, 0.03), n * R * 0.985 + Vector3(0, 0.06, 0), Pal.CR_YELLOW_DARK)
		seam.basis = Basis.looking_at(n, Vector3.UP)
	# 옆 포트
	var port := CylinderMesh.new()
	port.top_radius = 0.12
	port.bottom_radius = 0.13
	port.height = 0.08
	port.radial_segments = 14
	var port_in := CylinderMesh.new()
	port_in.top_radius = 0.065
	port_in.bottom_radius = 0.065
	port_in.height = 0.1
	port_in.radial_segments = 12
	for side in [-1, 1]:
		var n := Vector3(side, 0.05, 0).normalized()
		var q := Basis(Quaternion(Vector3.UP, n))
		var pm := _keep(shell, port, Pal.lit(Pal.CR_METAL_DARK), n * R * 0.99)
		pm.basis = q
		var pi := _keep(shell, port_in, Pal.lit(Pal.CR_METAL), n * R * 1.01)
		pi.basis = q
	# 정면 삼안: 어두운 하우징 + 소켓 + 파란 발광 눈 + 흰 하이라이트
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Pal.CR_EYE
	eye_mat.emission_enabled = true
	eye_mat.emission = Pal.CR_EYE
	eye_mat.emission_energy_multiplier = 1.5
	eye_mat.roughness = 0.25
	j.eye_mat = eye_mat
	var hous := SphereMesh.new()
	hous.radius = 0.15
	hous.height = 0.3
	hous.radial_segments = 14
	hous.rings = 7
	var sock := CylinderMesh.new()
	sock.top_radius = 0.1
	sock.bottom_radius = 0.115
	sock.height = 0.1
	sock.radial_segments = 16
	var eye := SphereMesh.new()
	eye.radius = 0.078
	eye.height = 0.156
	eye.radial_segments = 14
	eye.rings = 7
	var glint := SphereMesh.new()
	glint.radius = 0.024
	glint.height = 0.048
	glint.radial_segments = 8
	glint.rings = 4
	var eyes: Array = []
	for o in [Vector2(0, 0.21), Vector2(-0.18, -0.07), Vector2(0.18, -0.07)]:
		var n := Vector3(o.x, 0.12 + o.y, -1.0).normalized()
		var q := Basis(Quaternion(Vector3.UP, n))
		_keep(shell, hous, Pal.lit(Pal.CR_METAL_DARK), n * R * 0.93)
		var sm := _keep(shell, sock, Pal.lit(Pal.CR_METAL), n * R * 1.02)
		sm.basis = q
		var em := MeshInstance3D.new()
		em.mesh = eye
		em.material_override = eye_mat
		em.position = n * (R + 0.055)
		shell.add_child(em)
		eyes.append(em)
		var g := Pal.flat_mesh(glint, Color(0.85, 0.95, 1.0), 2.2)
		g.position = n * (R + 0.11) + Vector3(-0.025, 0.03, 0)
		shell.add_child(g)
	j.eyes = eyes
	# 약점 코어: 뚜껑 밑에 숨어 있다가 다리를 펴고 뚜껑이 열리면 드러난다 (구체일 때는 크기 0)
	var csm := SphereMesh.new()
	csm.radius = 0.22
	csm.height = 0.44
	var core := MeshInstance3D.new()
	core.mesh = csm
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Pal.E_RED
	cm.emission_enabled = true
	cm.emission = Pal.E_RED
	cm.emission_energy_multiplier = 0.8
	cm.roughness = 0.35
	core.material_override = cm
	core.position = Vector3(0, R * 0.84, 0)
	shell.add_child(core)
	j.core = core
	j.core_mat = cm
	var ring := TorusMesh.new()
	ring.inner_radius = 0.2
	ring.outer_radius = 0.28
	ring.rings = 16
	ring.ring_segments = 6
	var cr := _keep(core, ring, Pal.lit(Pal.CR_METAL_DARK), Vector3(0, -0.06, 0))
	cr.scale = Vector3(1, 0.6, 1)
	# 다리 4개: 대각선 방향. Hip(바깥 = 로컬 +X) → Thigh(회전 z) → Knee(회전 z) → 노란 정강이 판 + 바퀴 발
	var jm := CylinderMesh.new()
	jm.top_radius = 0.085
	jm.bottom_radius = 0.085
	jm.height = 0.2
	jm.radial_segments = 12
	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.085
	wheel.bottom_radius = 0.085
	wheel.height = 0.2
	wheel.radial_segments = 12
	var legs: Array = []
	for i in 4:
		var a := PI * 0.25 + PI * 0.5 * i
		var out := Vector3(cos(a), 0, -sin(a))
		var hip := pivot(squash, out * 0.42 + Vector3(0, -0.2, 0), "Hip")
		hip.rotation.y = a
		var hj := _keep(hip, jm, Pal.lit(Pal.CR_METAL_DARK), Vector3.ZERO)
		hj.rotation_degrees.x = 90.0
		var thigh := pivot(hip, Vector3.ZERO, "Thigh")
		box(thigh, Vector3(CR_L1, 0.1, 0.12), Vector3(CR_L1 * 0.5, 0, 0), Pal.CR_METAL)
		box(thigh, Vector3(CR_L1 * 0.7, 0.04, 0.05), Vector3(CR_L1 * 0.5, 0.08, 0), Pal.CR_METAL_DARK)
		var knee := pivot(thigh, Vector3(CR_L1, 0, 0), "Knee")
		var kj := _keep(knee, jm, Pal.lit(Pal.CR_METAL_DARK), Vector3.ZERO)
		kj.rotation_degrees.x = 90.0
		kj.scale = Vector3(1.15, 1.2, 1.15)
		box(knee, Vector3(CR_L2 * 0.82, 0.07, 0.26), Vector3(CR_L2 * 0.46, -0.02, 0), Pal.CR_METAL_DARK)
		box(knee, Vector3(CR_L2 * 0.78, 0.2, 0.2), Vector3(CR_L2 * 0.5, 0.05, 0), Pal.CR_YELLOW)
		box(knee, Vector3(CR_L2 * 0.3, 0.06, 0.21), Vector3(CR_L2 * 0.62, 0.16, 0), Pal.CR_YELLOW_DARK)
		var wm := _keep(knee, wheel, Pal.lit(Pal.CR_METAL_DARK), Vector3(CR_L2, 0, 0))
		wm.rotation_degrees.x = 90.0
		legs.append({"hip": hip, "thigh": thigh, "knee": knee, "out": out, "a": a})
	j.legs = legs
	j.cube = shell
	return j


## 파편이 되어도 원래 색을 유지하는 메시 (Debris 는 기본적으로 박스가 아닌 메시를 꺼진 코어 색으로 칠한다)
static func _keep(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.set_meta("keep_mat", true)
	parent.add_child(mi)
	return mi
