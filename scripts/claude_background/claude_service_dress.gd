class_name ClaudeServiceDress
## 1번 배관·설비실 합성안 (docs/service-machinery-claude-handoff.md · docs/service-machinery-claude.md).
## 본편 아레나 벽 밖의 검은 비플레이 공간을 '한 층 낮은 설비실'로 채운다. 판정·지형·충돌은 건드리지 않는 정적 장식.
## ClaudeBgDress.apply 끝에서 부른다 (배경 첫 제작이 꺼지면(--bg=old) 같이 꺼짐, 이것만 끄려면 --service=off).
##
##  - 바닥: 벽 칸(바닥에서 1칸) 밖으로 DMAX 칸까지 Y = FLOOR_Y 의 어두운 설비 바닥 (F01 텍스처를 남색으로 · 2m 타일 일부에 배수 격자).
##    바깥으로 갈수록 어두워져 원래의 어둠으로 녹아든다 (바깥 벽체는 만들지 않는다).
##  - 프랍 5종: S01 환기 장치 · S02 냉각 탱크 · S03 직선 배관 · S04 90도 배관 · S05 설비 기둥.
##    · 조립 틀(TEMPLATES): 환기 장치 줄 · 탱크 3개 + 앞 배관 · 펌프(S01 0.8배) · ㄱ자 배관. 벽 가까운 칸(DNEAR 안)부터 겹치지 않게 놓고
##      나머지는 조용한 바닥으로 남긴다. 모든 프랍 정면(상태등)이 카메라(+Z)를 본다.
##    · 벽 옆 기둥: 카메라 쪽(+Z)·옆으로 드러난 벽면을 따라 4칸마다 S05 (상태등 노랑/민트 재질 변형).
##    · 벽면 얇은 라인: 카메라 쪽으로 드러난 벽면(바닥 아래 짙은 부분)에 S03 을 0.25배 균일 축소해 한 줄로 (굵은 배관과 접속하지 않음).
##  - 그리기: 종류 × 16m 구역마다 MultiMesh 하나 (절두체 컬링). 배관 접속(끝단 축·평면)은 GLB 부착점 계약(pt_end_a/b · pt_port)에 맞춘 좌표로 놓는다.

const GLB := {
	"vent": "res://assets/models/bg_claude_service_s01_vent.glb",
	"tank": "res://assets/models/bg_claude_service_s02_tank.glb",
	"pipe": "res://assets/models/bg_claude_service_s03_pipe.glb",
	"elbow": "res://assets/models/bg_claude_service_s04_elbow.glb",
	"column": "res://assets/models/bg_claude_service_s05_column.glb",
}
const FLOOR_Y := -1.0         # 벽 블록 밑동과 같은 높이 (벽이 설비 바닥까지 내려와 닿는다)
const DMIN := 2               # 바닥에서 이 칸 거리부터 설비 공간 (1 = 벽 칸)
const DMAX := 8               # 설비 바닥이 끝나는 거리
const DNEAR := 4              # 조립 틀은 벽에서 이 거리 안에 닿아야 놓는다 (먼 곳은 조용한 바닥)
const LINE_Y := -0.42         # 벽면 얇은 라인 높이 (축 중심, 월드)
const CHUNK := 16.0           # MultiMesh 구역 크기 (m)
const LAMP_YELLOW := Color(1.0, 0.78, 0.32)
const LAMP_MINT := Color(0.35, 1.0, 0.82)
const LAMP_ENERGY := 2.2
const FLOOR_SHADER := preload("res://scripts/claude_background/service_floor.gdshader")

## 조립 틀: w×h 칸, 항목 [종류, u, v, yaw(도), 배율]. u = 오른쪽(+X), v = 카메라 반대쪽(-Z), 원점 = 앞(+Z)·왼쪽 모서리.
## yaw 180 = 정면이 카메라. 배관: 직선 yaw 0 = u 축 · 90 = v 축. 꺾임 yaw → 끝단 방향 {0: -u,-v · 90: -v,+u · 180: +u,+v · 270: +v,-u}.
const TEMPLATES := [
	# 환기 장치 둘을 직선 배관 하나로 잇고 옆에 설비 기둥 (원화 왼쪽)
	{"name": "vents", "w": 6, "h": 3, "weight": 3.0, "items": [
		["vent", 1.0, 1.5, 180.0, 1.0], ["pipe", 2.71, 1.5, 0.0, 1.0], ["vent", 4.42, 1.5, 180.0, 1.0], ["column", 5.62, 0.62, 180.0, 1.0]]},
	# 탱크 3개 + 포트 앞을 지나는 배관, 배관 양끝은 설비 기둥(제어함)으로 들어간다 (원화 오른쪽)
	{"name": "tanks", "w": 5, "h": 3, "weight": 3.0, "items": [
		["tank", 1.0, 2.0, 180.0, 1.0], ["tank", 2.5, 2.0, 180.0, 1.0], ["tank", 4.0, 2.0, 180.0, 1.0],
		["pipe", 1.6, 0.95, 0.0, 1.0], ["pipe", 3.6, 0.95, 0.0, 1.0],
		["column", 0.42, 0.95, 180.0, 1.0], ["column", 4.78, 0.95, 180.0, 1.0]]},
	# 펌프 둘 (S01 0.8배 균일 축소) + 제어함 기둥
	{"name": "pumps", "w": 4, "h": 3, "weight": 2.0, "items": [
		["vent", 0.85, 1.4, 180.0, 0.8], ["vent", 2.3, 1.4, 180.0, 0.8], ["column", 3.5, 1.0, 180.0, 1.0]]},
	# 기둥에서 나온 배관이 ㄱ자로 꺾여 환기 장치 정면으로 들어간다
	{"name": "pipe_l", "w": 5, "h": 4, "weight": 2.0, "items": [
		["column", 0.6, 1.0, 180.0, 1.0], ["pipe", 1.75, 1.0, 0.0, 1.0], ["elbow", 3.5, 1.0, 270.0, 1.0], ["vent", 3.5, 2.46, 180.0, 1.0]]},
	# 기둥 사이를 잇는 긴 배관 두 줄
	{"name": "pipe_run", "w": 6, "h": 3, "weight": 1.5, "items": [
		["column", 0.6, 0.9, 180.0, 1.0], ["pipe", 1.75, 0.9, 0.0, 1.0], ["pipe", 3.75, 0.9, 0.0, 1.0], ["column", 4.9, 0.9, 180.0, 1.0],
		["pipe", 2.75, 2.1, 0.0, 1.0], ["pipe", 4.75, 2.1, 0.0, 1.0], ["vent", 0.95, 2.1, 180.0, 0.8]]},
]

static var enabled := not OS.get_cmdline_user_args().has("--service=off")
static var _meshes := {}      # 종류 → Mesh (GLB 에서 한 번 꺼냄)
static var _lamp_mats := {}   # "종류:노랑/민트" → 상태등 색을 정한 머티리얼 (많아야 6개)
static var _floor_mat: ShaderMaterial
static var _line_mat: StandardMaterial3D


# ── 자원 ───────────────────────────────────────────────

## GLB 의 메시 하나. 메시 노드는 모델 원점에 회전 없이 있어야 한다 (모델 스크립트의 svc.finish) — 아니면 경고하고 그대로 쓴다
static func mesh(kind: String) -> Mesh:
	if not _meshes.has(kind):
		var n := (load(GLB[kind]) as PackedScene).instantiate() as Node3D
		var mi := n.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		var xf := n.global_transform.affine_inverse() * mi.global_transform if n.is_inside_tree() else mi.transform
		if not xf.is_equal_approx(Transform3D.IDENTITY):
			push_warning("ClaudeServiceDress: %s 메시 노드에 변환이 남아 있다 %s" % [kind, xf])
		_meshes[kind] = mi.mesh
		n.free()
	return _meshes[kind]


## 상태등이 있는 모델(S01·S02·S05)의 머티리얼: GLB 의 발광 마스크에 색·세기를 준다
static func lamp_material(kind: String, mint := false) -> Material:
	var key := "%s:%s" % [kind, "mint" if mint else "yellow"]
	if not _lamp_mats.has(key):
		var src := mesh(kind).surface_get_material(0) as StandardMaterial3D
		var m := src.duplicate() as StandardMaterial3D
		if m.emission_texture:
			m.emission_enabled = true
			m.emission = LAMP_MINT if mint else LAMP_YELLOW
			m.emission_energy_multiplier = LAMP_ENERGY
		_lamp_mats[key] = m
	return _lamp_mats[key]


## 벽면 얇은 라인 재질 변형: 0.25배라 밴드가 촘촘한 구슬처럼 보이므로 회크림 밴드 없이 남색 단색 (모델은 S03 그대로)
static func line_material() -> StandardMaterial3D:
	if _line_mat == null:
		_line_mat = StandardMaterial3D.new()
		_line_mat.albedo_color = Color("2a3150")
		_line_mat.roughness = 0.85
	return _line_mat


static func floor_material() -> ShaderMaterial:
	if _floor_mat == null:
		_floor_mat = ShaderMaterial.new()
		_floor_mat.shader = FLOOR_SHADER
		_floor_mat.set_shader_parameter("albedo_tex", ClaudeBgDress.floor_material().get_shader_parameter("albedo_tex"))
		BrawlLook.track_pool(_floor_mat)
		if not BrawlLook.moco:      # --bgtone=old: mo.co 무드 이전 톤 (비교용)
			_floor_mat.set_shader_parameter("old_tone", true)
			_floor_mat.set_shader_parameter("base_col", Color(0.165, 0.19, 0.30))
			_floor_mat.set_shader_parameter("grate_rate", 0.32)
	return _floor_mat


# ── 거리장 ─────────────────────────────────────────────

## 칸마다 가장 가까운 바닥·기둥·엄폐물 칸까지의 체비셰프 거리 (DMAX+1 에서 멈춤)
static func distances(map: ArenaMap) -> PackedByteArray:
	var n := ArenaMap.W * ArenaMap.H
	var d := PackedByteArray()
	d.resize(n)
	d.fill(255)
	var q: Array[Vector2i] = []
	for y in ArenaMap.H:
		for x in ArenaMap.W:
			if map.grid[y * ArenaMap.W + x] != ArenaMap.VOID:
				d[y * ArenaMap.W + x] = 0
				q.append(Vector2i(x, y))
	var head := 0
	while head < q.size():
		var c := q[head]
		head += 1
		var dc := d[c.y * ArenaMap.W + c.x]
		if dc > DMAX:
			continue
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nb := c + Vector2i(dx, dy)
				if nb.x < 0 or nb.y < 0 or nb.x >= ArenaMap.W or nb.y >= ArenaMap.H:
					continue
				var i := nb.y * ArenaMap.W + nb.x
				if d[i] > dc + 1:
					d[i] = dc + 1
					q.append(nb)
	return d


# ── 적용 ───────────────────────────────────────────────

static func apply(map: ArenaMap, kit: Node3D) -> void:
	if not enabled:
		return
	var root := Node3D.new()
	root.name = "ServiceRoom"
	kit.add_child(root)
	var d := distances(map)
	root.add_child(_floor(map, d))
	var spots := {}            # 묶음 이름 → [Transform3D]
	var used := {}             # 칸 → true (프랍이 차지)
	# 3m 벽(벽감 포함)은 뒤 칸으로 조금 물러나 있다 → 그 뒤 한 줄은 비운다
	for c: Vector2i in (map.get_meta("claude_tall", {}) as Dictionary).keys() + (map.get_meta("claude_occupied", {}) as Dictionary).keys():
		used[c - Vector2i(0, 1)] = true
	var rng := RandomNumberGenerator.new()
	var s := 17
	for r in map.rooms:
		s = hash([s, r.center])
	rng.seed = s
	_templates(map, d, used, spots, rng)
	_wall_columns(map, d, used, spots)
	_wall_lines(map, d, spots)
	root.set_meta("placed", spots.get("_placed", []))     # [틀 이름, 중심] — 캡처·검사용
	spots.erase("_placed")
	# 종류 × 구역(CHUNK m)마다 MultiMesh 하나 — 맵 전체를 한 덩어리로 두면 화면 밖까지 매 프레임 그린다 (구역 단위로 절두체 컬링)
	var groups := {}
	for key: String in spots:
		for xf: Transform3D in spots[key]:
			var ck := "%s@%d,%d" % [key, floori(xf.origin.x / CHUNK), floori(xf.origin.z / CHUNK)]
			if not groups.has(ck):
				groups[ck] = []
			groups[ck].append(xf)
	for ck: String in groups:
		var list: Array = groups[ck]
		var key := ck.get_slice("@", 0)
		var kind := key.get_slice(":", 0)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh(kind)
		mm.instance_count = list.size()
		for k in list.size():
			mm.set_instance_transform(k, list[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Service_" + ck.replace(":", "_").replace("@", "_").replace(",", "_")
		mmi.multimesh = mm
		if kind in ["vent", "tank", "column"]:
			mmi.material_override = lamp_material(kind, key.ends_with(":mint"))
		elif key == "pipe:line":
			mmi.material_override = line_material()
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF     # 벽에 붙은 가는 줄: 그림자 패스 삼각형 절약
		mmi.layers = 1 | MechDecals.RECEIVER
		mmi.set_meta("claude_service", key)
		mmi.set_meta("claude_spots", list)      # 검사용 (헤드리스 렌더러는 MultiMesh 변환을 돌려주지 않는다)
		root.add_child(mmi)
	root.set_meta("service_used", used)


## 설비 바닥: DMIN-1 ~ DMAX 칸 (벽 칸 밑도 덮어 벽 밑동과 이음매가 없게). 꼭짓점 색 = 바깥으로 갈수록 어두워지는 정도
static func _floor(map: ArenaMap, d: PackedByteArray) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var cells := 0
	for y in ArenaMap.H:
		for x in ArenaMap.W:
			var dc := d[y * ArenaMap.W + x]
			if dc < DMIN - 1 or dc > DMAX:
				continue
			cells += 1
			var p := map.world_of(Vector2i(x, y))
			var h := ArenaMap.CELL * 0.5
			var corners := [Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)]
			var v: Array[Vector3] = []
			var k: Array[float] = []
			for c: Vector2 in corners:
				v.append(Vector3(p.x + c.x, FLOOR_Y, p.z + c.y))
				k.append(_fade(d, x, y, int(signf(c.x)), int(signf(c.y))))
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_color(Color(k[idx], k[idx], k[idx]))
				st.add_vertex(v[idx])
	var mi := MeshInstance3D.new()
	mi.name = "ServiceFloor"
	mi.mesh = st.commit() if cells > 0 else null
	mi.material_override = floor_material()
	mi.layers = 1 | MechDecals.RECEIVER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("claude_service", "floor")
	mi.set_meta("cells", cells)
	return mi


## 칸 모서리의 밝기: 모서리를 공유하는 네 칸 중 가장 가까운 거리로 정한다 (칸 사이가 부드럽게 이어짐)
static func _fade(d: PackedByteArray, x: int, y: int, sx: int, sy: int) -> float:
	var best := 255
	for dy in [0, sy]:
		for dx in [0, sx]:
			var cx: int = x + dx
			var cy: int = y + dy
			if cx >= 0 and cy >= 0 and cx < ArenaMap.W and cy < ArenaMap.H:
				best = mini(best, d[cy * ArenaMap.W + cx])
	return clampf(1.0 - smoothstep(4.0, float(DMAX) + 0.5, float(best)), 0.0, 1.0)


static func _band(d: PackedByteArray, c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= ArenaMap.W or c.y >= ArenaMap.H:
		return false
	var v := d[c.y * ArenaMap.W + c.x]
	return v >= DMIN and v <= DMAX - 1


## 조립 틀 놓기: 칸을 섞은 순서로 돌며, 벽 가까운(DNEAR) 자리에 겹치지 않게 놓는다. 틀 둘레 한 칸은 비워 숨 쉴 자리를 둔다.
static func _templates(map: ArenaMap, d: PackedByteArray, used: Dictionary, spots: Dictionary, rng: RandomNumberGenerator) -> void:
	var cand: Array[Vector2i] = []
	for y in ArenaMap.H:
		for x in ArenaMap.W:
			var v := d[y * ArenaMap.W + x]
			if v >= DMIN and v <= DNEAR:
				cand.append(Vector2i(x, y))
	# 섞기 (같은 맵이면 같은 배치)
	for i in range(cand.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := cand[i]
		cand[i] = cand[j]
		cand[j] = t
	var total := 0.0
	for t in TEMPLATES:
		total += t.weight
	for a in cand:
		if used.has(a):
			continue
		# 틀 고르기 (가중치) → 안 맞으면 다른 틀도 차례로
		var pick := rng.randf() * total
		var first := 0
		for i in TEMPLATES.size():
			pick -= TEMPLATES[i].weight
			if pick <= 0.0:
				first = i
				break
		var mirror := rng.randf() < 0.5
		for k in TEMPLATES.size():
			var t: Dictionary = TEMPLATES[(first + k) % TEMPLATES.size()]
			# a = 틀의 앞(+Z)·왼쪽 칸
			if _fits(d, used, a, t.w, t.h):
				_place(map, a, t, mirror, used, spots)
				break


static func _fits(d: PackedByteArray, used: Dictionary, a: Vector2i, w: int, h: int) -> bool:
	var near := false
	for dv in h:
		for du in w:
			var c := Vector2i(a.x + du, a.y - dv)
			if used.has(c) or not _band(d, c):
				return false
			near = near or d[c.y * ArenaMap.W + c.x] <= DNEAR
	return near


static func _place(map: ArenaMap, a: Vector2i, t: Dictionary, mirror: bool, used: Dictionary, spots: Dictionary) -> void:
	var w: int = t.w
	var h: int = t.h
	var corner := map.world_of(a) + Vector3(-ArenaMap.CELL * 0.5, 0.0, ArenaMap.CELL * 0.5)   # 앞·왼쪽 모서리
	for it: Array in t.items:
		var kind: String = it[0]
		var u: float = it[1]
		var yaw: float = it[3]
		if mirror:
			u = w - u
			if kind == "elbow":
				yaw = {0.0: 90.0, 90.0: 0.0, 180.0: 270.0, 270.0: 180.0}[yaw]
		var p := Vector3(corner.x + u, FLOOR_Y, corner.z - float(it[2]))
		var key := kind
		if kind == "column" and (hash(Vector2i(roundi(p.x * 4.0), roundi(p.z * 4.0))) % 3 == 0):
			key = "column:mint"
		_add(spots, key, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)).scaled(Vector3.ONE * float(it[4])), p))
	for dv in range(-1, h + 1):
		for du in range(-1, w + 1):
			used[Vector2i(a.x + du, a.y - dv)] = true
	if not spots.has("_placed"):
		spots["_placed"] = []
	spots["_placed"].append([t.name, corner + Vector3(w * 0.5, 0.0, -h * 0.5)])


static func _add(spots: Dictionary, key: String, xf: Transform3D) -> void:
	if not spots.has(key):
		spots[key] = []
	spots[key].append(xf)


## 벽 옆 기둥: 바닥에서 2칸(벽 바로 바깥) 칸 중, 벽면이 카메라 쪽(+Z)이나 옆(±X)으로 드러난 곳에 4칸마다
static func _wall_columns(map: ArenaMap, d: PackedByteArray, used: Dictionary, spots: Dictionary) -> void:
	for y in ArenaMap.H:
		for x in ArenaMap.W:
			var c := Vector2i(x, y)
			if d[y * ArenaMap.W + x] != DMIN or used.has(c):
				continue
			var north := _is_wall(d, c + Vector2i(0, -1))
			var side := _is_wall(d, c + Vector2i(1, 0)) or _is_wall(d, c + Vector2i(-1, 0))
			if not ((north and posmod(x, 4) == 1) or (side and not north and posmod(y, 4) == 2)):
				continue
			var p := map.world_of(c)
			var off := Vector3.ZERO     # 칸 가운데: 뒷면이 벽면에서 0.25 떨어져 벽면 얇은 라인과 겹치지 않는다
			var key := "column:mint" if posmod(x * 7 + y * 13, 3) == 0 else "column"
			_add(spots, key, Transform3D(Basis(Vector3.UP, PI), Vector3(p.x + off.x, FLOOR_Y, p.z + off.z)))
			used[c] = true


static func _is_wall(d: PackedByteArray, c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= ArenaMap.W or c.y >= ArenaMap.H:
		return false
	return d[c.y * ArenaMap.W + c.x] == 1


## 벽면 얇은 라인: S03 0.25배 (길이 0.5 · 지름 0.125). 카메라 쪽(+Z)으로 드러난 벽면에서 0.08 띄워 칸마다 두 토막 한 줄.
## 옆(±X) 벽면은 카메라에서 거의 안 보여 두지 않는다 (삼각형 수 절약)
static func _wall_lines(map: ArenaMap, d: PackedByteArray, spots: Dictionary) -> void:
	var k := 0.25
	var axis_h := 0.3 * k                       # 피벗(바닥)에서 축까지
	for y in ArenaMap.H:
		for x in ArenaMap.W:
			var c := Vector2i(x, y)
			if d[y * ArenaMap.W + x] < DMIN or not _is_wall(d, c + Vector2i(0, -1)):
				continue
			var p := map.world_of(c)
			for sx in [-0.25, 0.25]:
				_add(spots, "pipe:line", Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * k),
						Vector3(p.x + sx, LINE_Y - axis_h, p.z - 0.5 + 0.08 + 0.0625)))
