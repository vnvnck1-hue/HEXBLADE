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
