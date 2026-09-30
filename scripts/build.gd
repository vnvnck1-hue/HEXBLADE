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


static var _bevels := {}
static var _cyls := {}


## 모서리를 깎은 판재 상자. taper 는 윗면(+Y)의 가로·세로 배율이다. 면마다 법선이 따로라 셀 음영에서 모서리가 한 단 끊겨 보인다.
static func bevel_mesh(size: Vector3, b: float, taper := 1.0) -> ArrayMesh:
	var key := "%s_%s_%s" % [size, b, taper]
	if _bevels.has(key):
		return _bevels[key]
	var h := size * 0.5
	b = minf(b, minf(h.x, minf(h.y, h.z)) * 0.9)
	# P(s, ax): 부호 s 의 꼭짓점에서 ax 축만 끝까지, 나머지 두 축은 b 만큼 안쪽
	var pt := func(s: Vector3, ax: int) -> Vector3:
		var q := Vector3()
		for i in 3:
			q[i] = s[i] * (h[i] if i == ax else h[i] - b)
		if q.y > 0.0:
			q.x *= taper
			q.z *= taper
		return q
	var polys := []
	var sg := [-1.0, 1.0]
	for a in 3:
		var u := (a + 1) % 3
		var w := (a + 2) % 3
		for s in sg:
			# 주면
			var f := []
			for su in sg:
				for sw in sg:
					var c := Vector3()
					c[a] = s
					c[u] = su
					c[w] = sw
					f.append(pt.call(c, a))
			polys.append(f)
			# 모서리 경사면 (a 축과 u 축 사이, w 축 방향으로 뻗음)
			for su in sg:
				var e := []
				for sw in sg:
					var c := Vector3()
					c[a] = s
					c[u] = su
					c[w] = sw
					e.append(pt.call(c, a))
					e.append(pt.call(c, u))
				polys.append(e)
	# 꼭짓점 삼각형
	for sx in sg:
		for sy in sg:
			for sz in sg:
				var c := Vector3(sx, sy, sz)
				polys.append([pt.call(c, 0), pt.call(c, 1), pt.call(c, 2)])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for poly in polys:
		var cen := Vector3()
		for q in poly:
			cen += q
		cen /= poly.size()
		# 면 위 점을 중심 기준 각도로 정렬 → 볼록 다각형
		var n0 := ((poly[1] as Vector3) - (poly[0] as Vector3)).cross((poly[2] as Vector3) - (poly[0] as Vector3))
		if n0.length() < 1e-9:
			n0 = ((poly[2] as Vector3) - (poly[0] as Vector3)).cross((poly[3] as Vector3) - (poly[0] as Vector3))
		n0 = n0.normalized()
		if n0.dot(cen) < 0.0:
			n0 = -n0
		var ua := ((poly[0] as Vector3) - cen).normalized()
		var va := n0.cross(ua)
		var ordered: Array = poly.duplicate()
		ordered.sort_custom(func(p1: Vector3, p2: Vector3) -> bool:
			return atan2((p1 - cen).dot(va), (p1 - cen).dot(ua)) < atan2((p2 - cen).dot(va), (p2 - cen).dot(ua)))
		# 정렬 순서는 바깥에서 봐서 반시계 → Godot 앞면(시계)으로 뒤집어 넣는다
		for i in range(1, ordered.size() - 1):
			st.set_normal(n0)
			st.add_vertex(ordered[0])
			st.set_normal(n0)
			st.add_vertex(ordered[i + 1])
			st.set_normal(n0)
			st.add_vertex(ordered[i])
	var m := st.commit()
	_bevels[key] = m
	return m


static func bevel(parent: Node3D, size: Vector3, pos: Vector3, c: Color, b := 0.04, rot_deg := Vector3.ZERO, taper := 1.0) -> MeshInstance3D:
	var mi := _keep(parent, bevel_mesh(size, b, taper), Pal.mech(c), pos)
	mi.rotation_degrees = rot_deg
	return mi


## 원통 (기본 축 Y). top_r < 0 이면 위아래 반지름이 같다.
static func cyl(parent: Node3D, r: float, height: float, pos: Vector3, c: Color, rot_deg := Vector3.ZERO, top_r := -1.0, segs := 14) -> MeshInstance3D:
	var tr := r if top_r < 0.0 else top_r
	var key := "%s_%s_%s_%s" % [r, tr, height, segs]
	if not _cyls.has(key):
		var cm := CylinderMesh.new()
		cm.bottom_radius = r
		cm.top_radius = tr
		cm.height = height
		cm.radial_segments = segs
		cm.rings = 1
		_cyls[key] = cm
	var mi := _keep(parent, _cyls[key], Pal.mech(c), pos)
	mi.rotation_degrees = rot_deg
	return mi


static func ball(parent: Node3D, r: float, pos: Vector3, c: Color, squash := Vector3.ONE) -> MeshInstance3D:
	var key := "ball_%s" % r
	if not _cyls.has(key):
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 16
		sm.rings = 8
		_cyls[key] = sm
	var mi := _keep(parent, _cyls[key], Pal.mech(c), pos)
	mi.scale = squash
	return mi


## 집게 손: 손목 구슬 + 손바닥 + 바깥 손가락 둘(앞·뒤) + 안쪽 엄지. 손가락은 -Y 로 뻗고 끝마디가 안쪽으로 굽는다.
## grip 0 이면 벌리고 1 이면 쥔다. side 는 팔 방향(바깥 = side).
static func claw(parent: Node3D, at: Vector3, k: float, grip: float, side: float) -> Node3D:
	var hand := pivot(parent, at, "Hand")
	ball(hand, 0.047 * k, Vector3.ZERO, Pal.M_CREAM)
	bevel(hand, Vector3(0.12, 0.08, 0.12) * k, Vector3(0, -0.05 * k, 0), Pal.M_DARK, 0.02 * k)
	for f in [Vector2(side * 0.04, -0.035), Vector2(side * 0.04, 0.035), Vector2(-side * 0.045, 0.0)]:
		var d := Vector3(f.x, 0, f.y).normalized()
		var axis := Vector3.DOWN.cross(d).normalized()
		var base := pivot(hand, Vector3(f.x, -0.08, f.y) * k, "Finger")
		base.basis = Basis(axis, deg_to_rad(lerpf(30.0, 8.0, grip)))
		ball(base, 0.025 * k, Vector3.ZERO, Pal.M_PANEL)
		bevel(base, Vector3(0.038, 0.1, 0.038) * k, Vector3(0, -0.05 * k, 0), Pal.M_MID, 0.01 * k)
		var tip := pivot(base, Vector3(0, -0.1 * k, 0), "Tip")
		tip.basis = Basis(axis, -deg_to_rad(lerpf(42.0, 78.0, grip)))
		ball(tip, 0.021 * k, Vector3.ZERO, Pal.M_DARK)
		bevel(tip, Vector3(0.033, 0.085, 0.03) * k, Vector3(0, -0.04 * k, 0), Pal.M_DARK, 0.01 * k)
	return hand


## 3면도 크림 기체 (캐릭터 선택용으로 보관, 현재 플레이어는 robot()). 키 약 1.85m, 정면 -Z. 관절 노드를 딕셔너리로 돌려준다.
## 치수는 3면도(390px/m)에서 잰 값이다. stance 0 = 3면도 차렷 자세, 1 = 게임 기본 전투 자세
## (무릎을 굽혀 낮추고 상체를 숙이며, 사격 팔은 앞으로 뻗고 검 팔은 반쯤 든다).
## 전투 자세의 굽힘은 애니메이션 관절 아래의 고정 노드(허벅지·정강이·발·가슴·윗팔·아래팔)에 들어 있어
## 걷기·대시·검술 애니메이션은 그대로 그 위에 얹힌다.
static func robot_mech(visual: Node3D, stance := 1.0) -> Dictionary:
	var j := {}
	var s := stance
	# ── 다리 ── 고관절(0.2) → 무릎(0.4) → 발목, 발목 높이 0.141
	var thigh_a := 30.0 * s              # 허벅지를 앞으로
	var knee_b := 45.0 * s               # 무릎 굽힘
	var hip_h := 0.2 * cos(deg_to_rad(thigh_a)) + 0.4 * cos(deg_to_rad(thigh_a - knee_b)) + 0.141
	var drop := 0.741 - hip_h
	var legs := pivot(visual, Vector3.ZERO, "Legs")
	j.legs = legs
	bevel(legs, Vector3(0.44, 0.16, 0.3), Vector3(0, hip_h + 0.04, 0.03), Pal.M_DEEP, 0.04)
	cyl(legs, 0.07, 0.7, Vector3(0, hip_h, 0.03), Pal.M_DARK, Vector3(0, 0, 90))
	for side in [-1, 1]:
		var hip := pivot(legs, Vector3(0.39 * side, hip_h, 0.03), "Hip")
		cyl(hip, 0.09, 0.22, Vector3.ZERO, Pal.M_DARK, Vector3(0, 0, 90))
		cyl(hip, 0.105, 0.05, Vector3(0.2 * side, 0, 0), Pal.M_CREAM, Vector3(0, 0, 90), -1.0, 18)
		cyl(hip, 0.05, 0.06, Vector3(0.2 * side, 0, 0), Pal.M_MID, Vector3(0, 0, 90))
		var thigh := pivot(hip, Vector3.ZERO, "Thigh")
		thigh.rotation_degrees.x = thigh_a
		bevel(thigh, Vector3(0.33, 0.25, 0.3), Vector3(0, -0.08, -0.01), Pal.M_CREAM, 0.04)
		bevel(thigh, Vector3(0.26, 0.18, 0.03), Vector3(0, -0.08, -0.165), Pal.M_PANEL, 0.015, Vector3(0, 0, 6 * side))
		bevel(thigh, Vector3(0.2, 0.08, 0.2), Vector3(0, -0.19, 0.02), Pal.M_DARK, 0.02)
		var knee := pivot(thigh, Vector3(0, -0.2, 0), "Knee")
		cyl(knee, 0.075, 0.26, Vector3.ZERO, Pal.M_DARK, Vector3(0, 0, 90))
		# 무릎 안쪽 큰 원반
		cyl(knee, 0.1, 0.05, Vector3(-0.165 * side, -0.05, 0), Pal.M_CREAM, Vector3(0, 0, 90), -1.0, 18)
		cyl(knee, 0.055, 0.06, Vector3(-0.17 * side, -0.05, 0), Pal.M_MID, Vector3(0, 0, 90))
		var shin := pivot(knee, Vector3.ZERO, "Shin")
		shin.rotation_degrees.x = -knee_b
		bevel(shin, Vector3(0.37, 0.33, 0.36), Vector3(0, -0.18, 0), Pal.M_CREAM, 0.05)
		bevel(shin, Vector3(0.23, 0.27, 0.03), Vector3(0.05 * side, -0.18, -0.185), Pal.M_PANEL, 0.015)
		bevel(shin, Vector3(0.2, 0.24, 0.03), Vector3(0, -0.19, 0.185), Pal.M_PANEL, 0.015)
		bevel(shin, Vector3(0.03, 0.2, 0.1), Vector3(0.19 * side, -0.2, 0.1), Pal.M_PANEL, 0.008)
		# 발목 띠 (바깥쪽이 살짝 처진다)
		bevel(shin, Vector3(0.38, 0.1, 0.34), Vector3(0, -0.36, -0.005), Pal.M_CREAM, 0.03, Vector3(0, 0, 4 * side))
		box(shin, Vector3(0.1, 0.012, 0.01), Vector3(0, -0.36, -0.177), Pal.M_DEEP)
		var foot := pivot(shin, Vector3(0, -0.4, 0), "Foot")
		foot.rotation_degrees.x = knee_b - thigh_a
		# 발: 땅은 발 기준 y -0.141
		bevel(foot, Vector3(0.27, 0.1, 0.26), Vector3(0, -0.02, 0), Pal.M_CREAM, 0.03)
		bevel(foot, Vector3(0.36, 0.05, 0.5), Vector3(0, -0.116, -0.01), Pal.M_DARK, 0.015)
		bevel(foot, Vector3(0.2, 0.08, 0.16), Vector3(0.075 * side, -0.1, -0.17), Pal.M_DARK, 0.025, Vector3(-14, 0, 0))
		bevel(foot, Vector3(0.13, 0.07, 0.14), Vector3(-0.1 * side, -0.105, -0.16), Pal.M_DARK, 0.022, Vector3(-14, 0, 0))
		bevel(foot, Vector3(0.3, 0.12, 0.17), Vector3(0, -0.08, 0.15), Pal.M_DARK, 0.03)
		cyl(foot, 0.028, 0.02, Vector3(0.152 * side, -0.075, 0.16), Pal.M_MID, Vector3(0, 0, 90))
		if side < 0:
			j.hip_l = hip
			j.knee_l = knee
			j.foot_l = foot
		else:
			j.hip_r = hip
			j.knee_r = knee
			j.foot_r = foot
		# 몸 리본용: 무릎 기준 허벅지 위 → 발끝
		j.leg_trail = [Vector3(0, 0.12, 0), shin.transform * foot.transform * Vector3(0, -0.1, -0.22)]

	# ── 상체 ── Rig 아래 좌표는 3면도 차렷 기준 절대 높이(땅 = 0). 가슴 노드가 허리(0.8)를 축으로 숙인다.
	var upper := pivot(visual, Vector3(0, 0.74, 0), "Upper")
	j.upper = upper
	var torso := pivot(upper, Vector3(0, 0.1, 0), "Torso")
	j.torso = torso
	var chest := pivot(torso, Vector3(0, -0.04 - drop, 0), "Chest")
	chest.rotation_degrees.x = -8.0 * s
	var rig := pivot(chest, Vector3(0, -0.8, 0), "Rig")
	bevel(rig, Vector3(0.46, 0.16, 0.36), Vector3(0, 0.8, 0.0), Pal.M_DEEP, 0.04)
	# 몸통 심 · 목 뒤 덩어리
	bevel(rig, Vector3(0.62, 0.42, 0.56), Vector3(0, 1.02, -0.06), Pal.M_CREAM, 0.06)
	bevel(rig, Vector3(0.38, 0.22, 0.42), Vector3(0, 1.25, 0.02), Pal.M_CREAM, 0.05)
	# 얼굴: 세운 바이저 면 + 뒤로 38° 누운 덮개 + 뒤로 빠지는 턱
	bevel(rig, Vector3(0.56, 0.2, 0.24), Vector3(0, 1.05, -0.43), Pal.M_CREAM, 0.04)
	bevel(rig, Vector3(0.46, 0.32, 0.2), Vector3(0, 1.193, -0.381), Pal.M_CREAM, 0.05, Vector3(38, 0, 0))
	box(rig, Vector3(0.28, 0.012, 0.01), Vector3(0, 1.23, -0.475), Pal.M_DEEP, Vector3(38, 0, 0))
	bevel(rig, Vector3(0.58, 0.13, 0.2), Vector3(0, 0.93, -0.41), Pal.M_CREAM, 0.04, Vector3(-35, 0, 0))
	for side in [-1, 1]:
		bevel(rig, Vector3(0.035, 0.022, 0.03), Vector3(0.155 * side, 1.16, -0.54), Pal.M_CREAM, 0.006)
	bevel(rig, Vector3(0.34, 0.11, 0.02), Vector3(0, 1.04, -0.553), Pal.M_MID, 0.012, Vector3.ZERO, 1.18)
	bevel(rig, Vector3(0.29, 0.075, 0.02), Vector3(0, 1.042, -0.562), Pal.M_DEEP, 0.01, Vector3.ZERO, 1.18)
	for side in [-1, 1]:
		# 노란 눈: ( ) 모양 두 토막
		for up in [-1, 1]:
			glow_box(rig, Vector3(0.017, 0.022, 0.01), Vector3(0.06 * side + 0.004 * side, 1.045 + 0.01 * up, -0.574), Pal.M_EYE, 1.7, Vector3(0, 0, 22 * side * up))
		# 턱의 작은 포트 · 얼굴과 어깨 사이 큰 포트
		cyl(rig, 0.034, 0.02, Vector3(0.17 * side, 0.945, -0.49), Pal.M_PANEL, Vector3(55, 0, 0))
		cyl(rig, 0.022, 0.03, Vector3(0.17 * side, 0.945, -0.492), Pal.M_DEEP, Vector3(55, 0, 0))
		cyl(rig, 0.062, 0.03, Vector3(0.28 * side, 0.95, -0.4), Pal.M_CREAM, Vector3(90, -45 * side, 0), -1.0, 16)
		cyl(rig, 0.045, 0.04, Vector3(0.283 * side, 0.95, -0.403), Pal.M_DEEP, Vector3(90, -45 * side, 0), -1.0, 16)
		# 얼굴 옆 어깨 안쪽 크림 판
		bevel(rig, Vector3(0.08, 0.4, 0.3), Vector3(0.3 * side, 1.02, -0.3), Pal.M_CREAM, 0.03)
	# 가슴 판: 폭 0.42, 높이 0.33~0.92, 위가 살짝 앞으로, 아래가 두껍다
	var tab := pivot(rig, Vector3(0, 0.92, -0.45), "Tabard")
	tab.rotation_degrees.x = -7.0
	bevel(tab, Vector3(0.42, 0.6, 0.12), Vector3(0, -0.3, 0.01), Pal.M_CREAM, 0.05)
	bevel(tab, Vector3(0.38, 0.3, 0.08), Vector3(0, -0.42, 0.09), Pal.M_CREAM, 0.03)
	bevel(tab, Vector3(0.33, 0.46, 0.03), Vector3(0, -0.24, -0.06), Pal.M_PANEL, 0.035)
	box(tab, Vector3(0.08, 0.014, 0.01), Vector3(0, -0.51, -0.062), Pal.M_DEEP)
	# 등: 윗등 판 · 나사 박힌 큰 회색 판 · 엉덩이 상자
	bevel(rig, Vector3(0.27, 0.14, 0.04), Vector3(0, 1.1, 0.22), Pal.M_CREAM, 0.02)
	box(rig, Vector3(0.2, 0.01, 0.01), Vector3(0, 1.1, 0.242), Pal.M_DEEP)
	bevel(rig, Vector3(0.48, 0.22, 0.04), Vector3(0, 0.94, 0.225), Pal.M_PANEL, 0.03)
	for side in [-1, 1]:
		cyl(rig, 0.022, 0.02, Vector3(0.17 * side, 0.93, 0.25), Pal.M_MID, Vector3(90, 0, 0))
	box(rig, Vector3(0.46, 0.03, 0.02), Vector3(0, 0.815, 0.22), Pal.M_DEEP)
	bevel(rig, Vector3(0.36, 0.26, 0.28), Vector3(0, 0.65, 0.12), Pal.M_CREAM, 0.05)
	box(rig, Vector3(0.075, 0.014, 0.01), Vector3(0, 0.64, 0.262), Pal.M_DEEP)
	# 어깨 장갑: 앞면이 바깥으로 돌아간 큰 덩어리, 앞·바깥 회색 판. 바깥 뒤쪽에 둥근 팔 소켓
	for side in [-1, 1]:
		var sh := pivot(rig, Vector3(0.445 * side, 1.0, -0.16), "Shoulder")
		sh.rotation_degrees = Vector3(0, -12 * side, -8 * side)
		bevel(sh, Vector3(0.35, 0.46, 0.42), Vector3.ZERO, Pal.M_CREAM, 0.06)
		bevel(sh, Vector3(0.27, 0.34, 0.03), Vector3(0.01 * side, -0.03, -0.215), Pal.M_PANEL, 0.02)
		bevel(sh, Vector3(0.03, 0.32, 0.3), Vector3(0.18 * side, -0.03, 0.0), Pal.M_PANEL, 0.015)
		cyl(sh, 0.02, 0.02, Vector3(0.198 * side, -0.14, -0.02), Pal.M_MID, Vector3(0, 0, 90))
		for k in 2:
			box(sh, Vector3(0.1, 0.012, 0.03), Vector3(0.0, 0.232, -0.08 + k * 0.07), Pal.M_DEEP)
		cyl(rig, 0.09, 0.06, Vector3(0.64 * side, 1.056, -0.03), Pal.M_CREAM, Vector3(0, 0, 90), -1.0, 18)
		cyl(rig, 0.062, 0.07, Vector3(0.645 * side, 1.056, -0.03), Pal.M_PANEL, Vector3(0, 0, 90), -1.0, 16)
		cyl(rig, 0.035, 0.08, Vector3(0.65 * side, 1.056, -0.03), Pal.M_DARK, Vector3(0, 0, 90))
	# 백팩: 회색 경첩 원통 → 뒤로 48° 누운 원통 포드(열린 아랫면이 앞아래를 본다) · 가운데 팩
	var flame := CylinderMesh.new()
	flame.top_radius = 0.14
	flame.bottom_radius = 0.0
	flame.height = 1.0
	flame.radial_segments = 8
	var core := CylinderMesh.new()
	core.top_radius = 0.07
	core.bottom_radius = 0.0
	core.height = 1.0
	core.radial_segments = 6
	for side in [-1, 1]:
		cyl(rig, 0.1, 0.28, Vector3(0.33 * side, 1.28, -0.2), Pal.M_PANEL, Vector3(0, 0, 90), -1.0, 18)
		cyl(rig, 0.106, 0.03, Vector3(0.46 * side, 1.28, -0.2), Pal.M_DARK, Vector3(0, 0, 90), -1.0, 18)
		cyl(rig, 0.085, 0.05, Vector3(0.2 * side, 1.28, -0.2), Pal.M_MID, Vector3(0, 0, 90), -1.0, 16)
		var pod := pivot(rig, Vector3(0.4 * side, 1.35, -0.07), "Pod")
		pod.rotation_degrees = Vector3(48, 0, -3 * side)
		cyl(pod, 0.12, 0.06, Vector3(0, -0.02, 0), Pal.M_PANEL, Vector3.ZERO, -1.0, 16)
		cyl(pod, 0.172, 0.01, Vector3(0, -0.002, 0), Pal.M_DEEP, Vector3.ZERO, -1.0, 20)
		cyl(pod, 0.21, 0.04, Vector3(0, 0.02, 0), Pal.M_CREAM, Vector3.ZERO, -1.0, 22)
		cyl(pod, 0.21, 0.4, Vector3(0, 0.24, 0), Pal.M_CREAM, Vector3.ZERO, -1.0, 22)
		cyl(pod, 0.212, 0.008, Vector3(0, 0.1, 0), Pal.M_MID, Vector3.ZERO, -1.0, 22)
		cyl(pod, 0.212, 0.008, Vector3(0, 0.42, 0), Pal.M_MID, Vector3.ZERO, -1.0, 22)
		cyl(pod, 0.21, 0.07, Vector3(0, 0.475, 0), Pal.M_CREAM, Vector3.ZERO, 0.16, 22)
		bevel(pod, Vector3(0.008, 0.055, 0.055), Vector3(0.21 * side, 0.32, 0), Pal.M_MID, 0.003, Vector3(45, 0, 0))
		# 부스터 불꽃: 포드 뒤쪽 아래에서 뒤아래로 분사 (부스트 중에만 보임)
		var jet := pivot(rig, Vector3(0.4 * side + 0.01 * side, 1.32, 0.27), "Jet")
		jet.rotation_degrees.x = -35.0
		var f := Pal.flat_mesh(flame, Pal.JET, 1.7)
		f.position.y = -0.5
		jet.add_child(f)
		var c := Pal.flat_mesh(core, Pal.JET_CORE, 2.2)
		c.position.y = -0.4
		jet.add_child(c)
		jet.scale = Vector3(1, 0.001, 1)
		jet.visible = false
		if side < 0:
			j.jet_l = jet
		else:
			j.jet_r = jet
	var pack := pivot(rig, Vector3(0, 1.495, -0.103), "Pack")
	pack.rotation_degrees.x = 41.0
	bevel(pack, Vector3(0.4, 0.45, 0.22), Vector3.ZERO, Pal.M_CREAM, 0.07)
	for k in 3:
		box(pack, Vector3(0.075, 0.01, 0.01), Vector3(-0.08, 0.17 - k * 0.022, -0.112), Pal.M_DEEP)
		box(pack, Vector3(0.075, 0.01, 0.01), Vector3(0, 0.17 - k * 0.022, 0.112), Pal.M_DEEP)
	box(pack, Vector3(0.016, 0.016, 0.01), Vector3(0.05, 0.172, -0.112), Pal.M_DEEP)
	box(pack, Vector3(0.016, 0.016, 0.01), Vector3(0.078, 0.162, -0.112), Pal.M_DEEP)
	box(pack, Vector3(0.008, 0.28, 0.008), Vector3(0.03, 0.0, -0.112), Pal.M_DEEP, Vector3(0, 0, 8))
	box(pack, Vector3(0.3, 0.008, 0.008), Vector3(0, -0.16, -0.112), Pal.M_DEEP)
	box(pack, Vector3(0.24, 0.008, 0.008), Vector3(0, -0.16, 0.112), Pal.M_DEEP)

	# ── 팔 ── 소켓 → 짧은 윗팔(0.23) → 팔꿈치 → 굵은 아래팔(0.3) → 아래로 뻗은 집게 손
	# 전투 자세: 사격 팔은 앞으로 거의 수평, 검 팔은 반쯤 든다. 차렷(3면도)은 바깥으로 벌려 늘어뜨린다.
	for side in [-1, 1]:
		var gun: bool = side < 0
		var arm := pivot(rig, Vector3(0.66 * side, 1.056, -0.03), "ArmL" if gun else "ArmR")
		ball(arm, 0.075, Vector3.ZERO, Pal.M_DARK)
		var ua := pivot(arm, Vector3.ZERO, "UpperArm")
		ua.rotation_degrees = Vector3(lerpf(0.0, 30.0 if gun else 15.0, s), 0, lerpf(6.0, 10.0, s) * side)
		cyl(ua, 0.05, 0.24, Vector3(0, -0.12, 0), Pal.M_DARK)
		bevel(ua, Vector3(0.16, 0.2, 0.17), Vector3(0.015 * side, -0.12, 0), Pal.M_CREAM, 0.035)
		bevel(ua, Vector3(0.02, 0.14, 0.08), Vector3(-0.08 * side, -0.12, 0), Pal.M_DARK, 0.006)
		cyl(ua, 0.06, 0.17, Vector3(0, -0.23, 0), Pal.M_DARK, Vector3(0, 0, 90))
		var fa := pivot(ua, Vector3(0, -0.23, 0), "Forearm")
		fa.rotation_degrees = Vector3(lerpf(10.0, 58.0 if gun else 38.0, s), 0, lerpf(8.0, 5.0, s) * side)
		bevel(fa, Vector3(0.19, 0.27, 0.2), Vector3(0, -0.145, 0), Pal.M_CREAM, 0.045, Vector3.ZERO, 1.12)
		bevel(fa, Vector3(0.02, 0.18, 0.1), Vector3(0.1 * side, -0.155, 0.02), Pal.M_DARK, 0.006)
		bevel(fa, Vector3(0.07, 0.16, 0.02), Vector3(-0.03 * side, -0.155, -0.1), Pal.M_DARK, 0.006)
		bevel(fa, Vector3(0.21, 0.035, 0.21), Vector3(0, -0.035, 0), Pal.M_PANEL, 0.01)
		cyl(fa, 0.045, 0.06, Vector3(0, -0.3, 0), Pal.M_DARK)
		var to_arm := ua.transform * fa.transform
		if gun:
			# 왼팔: 사격 팔. 집게가 짧은 포신을 문다. 총구는 포신 방향을 -Z 로 본다.
			claw(fa, Vector3(0, -0.34, 0), 1.25, 0.5, side)
			cyl(fa, 0.032, 0.26, Vector3(0, -0.47, 0), Pal.M_MID)
			cyl(fa, 0.042, 0.04, Vector3(0, -0.6, 0), Pal.M_DARK)
			var dir := (to_arm.basis * Vector3.DOWN).normalized()
			var mz := pivot(arm, to_arm * Vector3(0, -0.63, 0), "Muzzle")
			mz.basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.BACK)
			j.arm_l = arm
			j.muzzle = mz
			j.arm_tip_l = to_arm * Vector3(0, -0.59, 0)
		else:
			# 오른팔: 집게 손으로 붉은 광선검 손잡이를 쥔다. 검 피벗은 팔 기준 축이라 검술 자세 각도가 그대로 통한다.
			claw(fa, Vector3(0, -0.34, 0), 1.25, 0.75, side)
			var blade := pivot(arm, to_arm * Vector3(0, -0.42, 0), "Blade")
			cyl(blade, 0.035, 0.24, Vector3(0, 0, 0.03), Pal.M_DARK, Vector3(90, 0, 0))
			box(blade, Vector3(0.1, 0.05, 0.04), Vector3(0, 0, -0.09), Pal.M_MID)
			glow_box(blade, Vector3(0.08, 0.035, 1.35), Vector3(0, 0, -0.78), Pal.BLADE, 1.6)
			glow_box(blade, Vector3(0.03, 0.045, 1.2), Vector3(0, 0.01, -0.74), Pal.BLADE_CORE, 1.8)
			blade.rotation_degrees = Vector3(38, -18, 0)
			j.arm_r = arm
			j.blade = blade
			j.arm_tip_r = to_arm * Vector3(0, -0.57, 0)
	j.arm_base = Vector3(0, -0.1, 0)
	return j


## 플레이어 로봇(현재 기체): 보라색 저폴리 로봇 · 청록 발광부 · 등의 회색 포신. 관절 노드를 딕셔너리로 돌려준다.
## 3면도 크림 기체는 robot_mech() 에 따로 둔다 (캐릭터 선택용).
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
		# 발 기준점 (발바닥 = y -0.12)
		var foot := pivot(knee, Vector3(0, -0.24, 0), "Foot")
		if side < 0:
			j.hip_l = hip
			j.knee_l = knee
			j.foot_l = foot
		else:
			j.hip_r = hip
			j.knee_r = knee
			j.foot_r = foot
	# 몸 리본용: 무릎 기준 허벅지 위 → 발끝
	j.leg_trail = [Vector3(0, 0.28, 0), Vector3(0, -0.38, -0.12)]

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
		var f := Pal.flat_mesh(flame, Pal.JET, 1.7)
		f.position.y = -0.5
		jet.add_child(f)
		var c := Pal.flat_mesh(core, Pal.JET_CORE, 2.2)
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
	# 오른팔: 붉은 광선검
	var arm_r := pivot(torso, Vector3(0.46, 0.3, 0), "ArmR")
	box(arm_r, Vector3(0.17, 0.3, 0.18), Vector3(0, -0.18, 0), Pal.P_BODY)
	box(arm_r, Vector3(0.19, 0.16, 0.36), Vector3(0, -0.34, -0.1), Pal.P_DARK)
	var blade := pivot(arm_r, Vector3(0.02, -0.34, -0.26), "Blade")
	box(blade, Vector3(0.08, 0.08, 0.2), Vector3(0, 0, 0.02), Pal.P_GREY)
	glow_box(blade, Vector3(0.08, 0.035, 1.35), Vector3(0, 0, -0.76), Pal.BLADE, 1.6)
	glow_box(blade, Vector3(0.03, 0.045, 1.2), Vector3(0, 0.01, -0.72), Pal.BLADE_CORE, 1.8)
	blade.rotation_degrees = Vector3(38, -18, 0)
	j.arm_r = arm_r
	j.blade = blade
	# 몸 리본용: 팔 기준 어깨 → 손끝
	j.arm_base = Vector3(0, -0.12, 0)
	j.arm_tip_l = Vector3(0, -0.33, -0.78)
	j.arm_tip_r = Vector3(0, -0.36, -0.3)
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
