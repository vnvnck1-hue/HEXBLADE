extends RefCounted
## 보스: 데포르메 중전차 "맘모스". 둥근 모서리 파츠 조합, 정면은 -Z, 원점은 바닥 중심.
## 짧고 뭉뚝한 비율: 전장 약 7.4m · 폭 7m · 높이 5m (플레이어 로봇 약 1.5m).

const STEEL := Color("a4a5b8")
const STEEL_MID := Color("7e7f96")
const STEEL_DARK := Color("595a70")
const STEEL_DEEP := Color("38384a")
const HILITE := Color("8ff6ff")
const TREAD := Color("7a4a38")
const CLEAT := Color("4a3028")
const HUB := Color("c4c6da")
const BORE := Color("1a1a24")

static var _meshes := {}
static var _mats := {}


static func _mesh(key: String, make: Callable) -> Mesh:
	if not _meshes.has(key):
		_meshes[key] = make.call()
	return _meshes[key]


## 살짝 반들거리는 장난감 질감 + 가장자리 림
static func mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		Pal.toon(m, 0.7, 0.35, 0.3)
		m.albedo_color = c
		m.rim_enabled = true
		m.rim = 0.25
		m.rim_tint = 0.3
		_mats[key] = m
	return _mats[key]


## 모서리 반지름 r 인 둥근 박스. 구의 각 정점을 옥탄트별로 밀어내서 만든다.
static func _rounded_mesh(size: Vector3, r: float) -> ArrayMesh:
	var h := size * 0.5
	var rr := minf(r, minf(h.x, minf(h.y, h.z)))
	var inner := h - Vector3.ONE * rr
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 24
	sm.rings = 12
	var arr := sm.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for i in v.size():
		var n := v[i].normalized()
		var s := Vector3(_sgn(n.x), _sgn(n.y), _sgn(n.z))
		v[i] = s * inner + n * rr
		nrm[i] = n
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TANGENT] = null
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func _sgn(x: float) -> float:
	return 0.0 if absf(x) < 1e-4 else signf(x)


static func _inst(parent: Node3D, mesh: Mesh, pos: Vector3, c: Color, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(c)
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func rbox(parent: Node3D, size: Vector3, r: float, pos: Vector3, c: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := _mesh("r%s_%s" % [size, r], func(): return _rounded_mesh(size, r))
	return _inst(parent, m, pos, c, rot)


## 축은 기본 Y. rot 으로 눕힌다 (X 90 → Z 축, Z 90 → X 축).
static func cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, c: Color, rot := Vector3.ZERO, seg := 20) -> MeshInstance3D:
	var m := _mesh("c%s_%s_%s_%s" % [r_top, r_bot, h, seg], func():
		var cm := CylinderMesh.new()
		cm.top_radius = r_top
		cm.bottom_radius = r_bot
		cm.height = h
		cm.radial_segments = seg
		cm.rings = 1
		return cm)
	return _inst(parent, m, pos, c, rot)


static func ball(parent: Node3D, r: float, pos: Vector3, c: Color, scl := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := _mesh("s%s" % r, func():
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = 28
		s.rings = 14
		return s)
	return _inst(parent, m, pos, c, rot, scl)


static func glow(parent: Node3D, size: Vector3, pos: Vector3, c: Color, energy := 1.6, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := Pal.flat_mesh(_mesh("g%s" % size, func(): return _rounded_mesh(size, minf(size.x, minf(size.y, size.z)) * 0.5)), c, energy)
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi


static func glow_ball(parent: Node3D, r: float, pos: Vector3, c: Color, energy := 1.8) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	var mi := Pal.flat_mesh(s, c, energy)
	mi.position = pos
	parent.add_child(mi)
	return mi


static func pivot(parent: Node3D, pos: Vector3, name: String) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.position = pos
	parent.add_child(n)
	return n


## 보스 전체. 움직일 관절 노드를 딕셔너리로 돌려준다.
static func build(visual: Node3D) -> Dictionary:
	var j := {}
	var treads: Array = []
	for side in [-1, 1]:
		var pod := pivot(visual, Vector3(2.6 * side, 0.0, 0.0), "Tread")
		_tread(pod, side)
		treads.append(pod)
	j.treads = treads

	var hull := pivot(visual, Vector3.ZERO, "Hull")
	j.hull = hull
	_hull(hull)

	var turret := pivot(hull, Vector3(0, 2.85, 0.25), "Turret")
	j.turret = turret
	j.merge(_turret(turret))

	var spons: Array = []
	for side in [-1, 1]:
		var sp := pivot(hull, Vector3(1.75 * side, 2.8, -2.25), "Sponson")
		_sponson(sp)
		spons.append(sp)
	j.sponsons = spons

	var pods: Array = []
	for side in [-1, 1]:
		var mp := pivot(hull, Vector3(1.8 * side, 2.75, 2.3), "MissilePod")
		_missile_pod(mp)
		pods.append(mp)
	j.missile_pods = pods
	return j


## 궤도: 통통한 캡슐 벨트 + 큰 바퀴 3개 + 둘레 돌기 + 위 흙받이
static func _tread(p: Node3D, side: int) -> void:
	var W := 1.8
	var H := 2.0
	var L := 6.6
	var r := H * 0.5
	var ez := L * 0.5 - r
	rbox(p, Vector3(W, H, L), r, Vector3(0, r, 0), TREAD)
	# 윗면 돌기
	for i in 5:
		var z := lerpf(-ez, ez, float(i) / 4.0)
		rbox(p, Vector3(W + 0.12, 0.24, 0.46), 0.1, Vector3(0, H + 0.02, z), CLEAT)
	# 앞뒤 곡면 돌기
	for e in [-1, 1]:
		for k in 3:
			var a := deg_to_rad(45.0 - 45.0 * k)
			var off := Vector3(0, r + sin(a) * (r + 0.02), e * (ez + cos(a) * (r + 0.02)))
			rbox(p, Vector3(W + 0.12, 0.24, 0.46), 0.1, off, CLEAT, Vector3(e * (90.0 - rad_to_deg(a)), 0, 0))
	# 바깥 면 큰 바퀴
	var ox := side * (W * 0.5)
	for i in 3:
		var z := lerpf(-1.9, 1.9, float(i) / 2.0)
		cyl(p, 0.78, 0.78, 0.2, Vector3(ox, r, z), STEEL_DEEP, Vector3(0, 0, 90))
		ball(p, 0.56, Vector3(ox + side * 0.08, r, z), HUB, Vector3(0.35, 1, 1))
		ball(p, 0.18, Vector3(ox + side * 0.26, r, z), STEEL_DARK, Vector3(0.6, 1, 1))
	# 흙받이: 두툼한 둥근 판, 앞뒤는 아래로 숙인다
	var fx := -side * 0.3
	rbox(p, Vector3(W - 0.2, 0.62, L - 2.0), 0.28, Vector3(fx, H + 0.28, 0), STEEL)
	for e in [-1, 1]:
		rbox(p, Vector3(W - 0.2, 0.58, 1.5), 0.26, Vector3(fx, H - 0.02, e * (L * 0.5 - 0.95)), STEEL_MID, Vector3(e * 30, 0, 0))
	glow(p, Vector3(0.08, 0.08, L - 2.4), Vector3(fx + side * (W * 0.5 - 0.1), H + 0.36, 0), HILITE, 1.1)


static func _hull(h: Node3D) -> void:
	rbox(h, Vector3(3.8, 1.6, 6.0), 0.55, Vector3(0, 1.75, 0), STEEL_DARK)
	rbox(h, Vector3(3.9, 0.7, 5.6), 0.32, Vector3(0, 2.55, 0.1), STEEL_MID)
	# 앞 범퍼와 뭉툭한 뿔
	rbox(h, Vector3(3.9, 1.1, 1.1), 0.5, Vector3(0, 1.25, -3.05), STEEL)
	rbox(h, Vector3(3.4, 0.45, 1.5), 0.22, Vector3(0, 2.3, -2.85), STEEL, Vector3(-28, 0, 0))
	for x in [-1.1, 0.0, 1.1]:
		cyl(h, 0.08, 0.28, 0.45, Vector3(x, 1.2, -3.72), STEEL_MID, Vector3(-90, 0, 0), 12)
		ball(h, 0.08, Vector3(x, 1.2, -3.95), STEEL_MID)
	for side in [-1, 1]:
		glow(h, Vector3(0.42, 0.2, 0.08), Vector3(1.45 * side, 1.62, -3.58), Pal.E_RED, 1.9)
	# 후방 엔진: 둥근 덩어리 + 환풍 줄 + 짧은 배기통
	rbox(h, Vector3(3.2, 1.4, 1.0), 0.42, Vector3(0, 2.0, 3.0), STEEL_MID)
	for i in 5:
		rbox(h, Vector3(2.2, 0.1, 0.1), 0.05, Vector3(0, 1.62 + i * 0.19, 3.5), STEEL_DEEP)
	for side in [-1, 1]:
		cyl(h, 0.32, 0.36, 0.9, Vector3(0.7 * side, 3.1, 2.95), STEEL_DARK, Vector3.ZERO, 16)
		cyl(h, 0.4, 0.4, 0.2, Vector3(0.7 * side, 3.6, 2.95), STEEL_DEEP, Vector3.ZERO, 16)
		cyl(h, 0.24, 0.24, 0.04, Vector3(0.7 * side, 3.71, 2.95), BORE, Vector3.ZERO, 16)
	# 짧은 안테나
	cyl(h, 0.04, 0.06, 1.2, Vector3(-1.2, 3.45, 3.05), STEEL_DEEP, Vector3(0, 0, 10), 6)
	glow_ball(h, 0.13, Vector3(-1.3, 4.07, 3.05), Pal.E_RED, 2.0)


## 주포탑: 크고 납작한 구 몸통 + 해치 + 짧고 굵은 쌍포 + 양옆 둥근 귀 포드
static func _turret(t: Node3D) -> Dictionary:
	var j := {}
	cyl(t, 2.05, 2.15, 0.4, Vector3(0, 0.1, 0), STEEL_DEEP, Vector3.ZERO, 28)
	ball(t, 2.2, Vector3(0, 0.35, 0), STEEL, Vector3(1, 0.75, 1))
	# 허리 띠와 리벳
	cyl(t, 2.22, 2.22, 0.2, Vector3(0, 0.55, 0), STEEL_MID, Vector3.ZERO, 28)
	for i in 14:
		var a := TAU * i / 14.0
		ball(t, 0.09, Vector3(sin(a) * 2.24, 0.55, cos(a) * 2.24), STEEL_DEEP)
	glow(t, Vector3(0.1, 0.1, 1.6), Vector3(-1.35, 1.55, 0.3), HILITE, 1.0, Vector3(0, 0, 38))
	# 상부 해치
	cyl(t, 0.72, 0.78, 0.3, Vector3(0.25, 1.93, 0.45), STEEL_MID, Vector3.ZERO, 20)
	ball(t, 0.72, Vector3(0.25, 2.08, 0.45), STEEL, Vector3(1, 0.5, 1))
	rbox(t, Vector3(0.5, 0.14, 0.14), 0.07, Vector3(0.25, 2.45, 0.45), STEEL_DEEP)
	# 잠망경 눈
	rbox(t, Vector3(0.8, 0.55, 0.65), 0.22, Vector3(-0.95, 1.72, -0.95), STEEL_MID)
	glow(t, Vector3(0.52, 0.16, 0.08), Vector3(-0.95, 1.76, -1.28), Pal.E_RED, 2.0)
	# 포방패 + 약점 코어
	rbox(t, Vector3(2.8, 1.4, 1.2), 0.55, Vector3(0, 0.75, -1.75), STEEL_MID)
	cyl(t, 0.55, 0.55, 0.3, Vector3(0, 0.8, -2.35), STEEL_DEEP, Vector3(90, 0, 0), 24)
	j.core = glow_ball(t, 0.4, Vector3(0, 0.8, -2.45), Pal.E_RED, 1.8)
	# 짧고 굵은 쌍포, 끝은 둥근 포구 덩어리
	var guns: Array = []
	for side in [-1, 1]:
		var g := pivot(t, Vector3(0.95 * side, 0.8, -2.25), "Cannon")
		cyl(g, 0.46, 0.46, 0.5, Vector3(0, 0, -0.1), STEEL_DARK, Vector3(90, 0, 0))
		cyl(g, 0.32, 0.36, 1.4, Vector3(0, 0, -0.95), STEEL, Vector3(90, 0, 0))
		cyl(g, 0.4, 0.4, 0.18, Vector3(0, 0, -0.85), STEEL_DARK, Vector3(90, 0, 0))
		rbox(g, Vector3(0.95, 0.9, 0.8), 0.36, Vector3(0, 0, -1.95), STEEL_MID)
		cyl(g, 0.26, 0.26, 0.06, Vector3(0, 0, -2.34), BORE, Vector3(90, 0, 0))
		guns.append({"pivot": g, "muzzle": pivot(g, Vector3(0, 0, -2.45), "Muzzle")})
	j.cannons = guns
	# 양옆 귀 포드
	for side in [-1, 1]:
		var pod := pivot(t, Vector3(2.1 * side, 0.95, -0.2), "EarPod")
		ball(pod, 0.85, Vector3.ZERO, STEEL_MID, Vector3(0.85, 1, 1))
		ball(pod, 0.55, Vector3(side * 0.55, 0, 0), STEEL, Vector3(0.45, 1, 1))
		glow(pod, Vector3(0.08, 0.36, 0.08), Vector3(side * 0.8, 0.12, 0), HILITE, 1.0)
		for k in [-1, 1]:
			cyl(pod, 0.13, 0.13, 0.8, Vector3(k * 0.2, -0.1, -1.05), STEEL, Vector3(90, 0, 0), 12)
			cyl(pod, 0.18, 0.18, 0.16, Vector3(k * 0.2, -0.1, -1.42), STEEL_DARK, Vector3(90, 0, 0), 12)
	# 뒤 탄약 상자
	rbox(t, Vector3(2.2, 0.9, 1.0), 0.36, Vector3(0, 0.85, 1.95), STEEL_DARK)
	return j


## 앞 모서리 보조 포탑: 동글한 돔 + 뭉툭한 3열 개틀링
static func _sponson(s: Node3D) -> void:
	cyl(s, 0.78, 0.84, 0.28, Vector3(0, 0.12, 0), STEEL_DEEP, Vector3.ZERO, 20)
	ball(s, 0.78, Vector3(0, 0.3, 0), STEEL, Vector3(1, 0.85, 1))
	glow(s, Vector3(0.38, 0.12, 0.08), Vector3(0, 0.62, -0.66), Pal.E_RED, 1.9)
	cyl(s, 0.3, 0.3, 0.4, Vector3(0, 0.3, -0.8), STEEL_DARK, Vector3(90, 0, 0), 16)
	for k in 3:
		var a := TAU * k / 3.0 + PI * 0.5
		cyl(s, 0.08, 0.08, 0.6, Vector3(cos(a) * 0.14, 0.3 + sin(a) * 0.14, -1.25), STEEL, Vector3(90, 0, 0), 8)
	cyl(s, 0.28, 0.28, 0.14, Vector3(0, 0.3, -1.5), STEEL_DARK, Vector3(90, 0, 0), 16)


## 뒤 모서리 미사일 포드: 둥근 상자 + 위로 향한 굵은 발사관 4개
static func _missile_pod(m: Node3D) -> void:
	rbox(m, Vector3(1.4, 1.1, 1.5), 0.4, Vector3(0, 0.45, 0), STEEL_MID)
	for ix in 2:
		for iz in 2:
			var p := Vector3(lerpf(-0.3, 0.3, float(ix)), 1.0, lerpf(-0.33, 0.33, float(iz)))
			cyl(m, 0.22, 0.22, 0.1, p, STEEL_DEEP, Vector3.ZERO, 16)
			cyl(m, 0.16, 0.16, 0.02, p + Vector3(0, 0.05, 0), BORE, Vector3.ZERO, 16)
			glow_ball(m, 0.1, p + Vector3(0, 0.02, 0), Pal.E_RED, 1.5)
