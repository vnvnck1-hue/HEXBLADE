class_name ClaudeBgDress
## 본편 아레나(ArenaMap)에 Claude 배경 첫 제작(docs/background-first-pass-claude.md)을 입힌다 — 시험 씬과 같은 모델·텍스처.
## ArenaMap.build() 가 두 번 부른다. 판정(칸 막힘·충돌 상자)·지형·방 구성은 그대로, 보이는 것만 바뀐다.
##
##  1. plan(map, occupied)  (벽 상자를 만들기 전)
##     뒤쪽(-Z) 벽 줄의 직선 구간에 실제 W01(3m, 2m 모듈 · 남는 한 칸은 1m 반쪽 모듈)을 세운다.
##     그 뒤 3칸에 바닥이 없는 곳만 — 3m 벽이 다른 방·통로를 가리지 않게.
##     방마다 그 벽에 벽감을 내어 작업대 A01 · 수납장 A02 를 넣는다 (벽 칸 자리라 전투 바닥은 줄지 않음).
##     벽감: 안쪽 W01 을 뒤로 물리고 양옆을 옆판(bg_claude_jamb)으로 막고 바닥을 깐다.
##  2. apply(map)  (build 끝)
##     방·통로 바닥 → F01 4m 텍스처 월드 셰이더 (시험 씬과 같은 재질).
##     나머지 벽(0.8) · 낮은 엄폐물(0.7) · 기둥(1.5) → 칸마다 '낮은 W01' 블록 모델 (MultiMesh). 예전 단색 벽 상자는 숨긴다.
## 예전 모습: 실행 인자 --bg=old (또는 ClaudeBgDress.enabled = false).

const GLB := {
	"f01": "res://assets/models/bg_claude_f01.glb",
	"w01": "res://assets/models/bg_claude_w01.glb",
	"half": "res://assets/models/bg_claude_w01_half.glb",
	"jamb": "res://assets/models/bg_claude_jamb.glb",
	"bench": "res://assets/models/bg_claude_a01.glb",
	"locker": "res://assets/models/bg_claude_a02.glb",
	"wall": "res://assets/models/bg_claude_block_wall.glb",
	"cover": "res://assets/models/bg_claude_block_cover.glb",
	"pillar": "res://assets/models/bg_claude_block_pillar.glb",
}
const FLOOR_SHADER := preload("res://scripts/claude_background/bg_floor.gdshader")
const BLUE_PAINT := preload("res://scripts/claude_background/blue_handpaint.gd")
const BEHIND := 3            # 3m 벽 뒤로 이만큼 칸에 바닥이 없어야 세운다
const MIN_RUN := 3           # 3m 벽을 세우는 직선 구간의 최소 칸 수
const DEPTH := {"bench": 0.75, "locker": 0.5}
const GAP := 0.05            # 프랍 뒷면과 벽감 벽 사이

static var enabled := not OS.get_cmdline_user_args().has("--bg=old")
static var _floor_mats := {}  # 줄눈 위상(0/1m, 0/1m) → 재질. 많아야 4개
static var _meshes := {}     # 블록 종류 → Mesh (GLB 에서 한 번 꺼냄)


# ── 재질 · 메시 ─────────────────────────────────────────

## 바닥 재질. offset = 2m 줄눈이 시작되는 위치(월드 X, Z 를 2 로 나눈 나머지 — 0 또는 1).
static func floor_material(offset := Vector2.ZERO) -> ShaderMaterial:
	var key := Vector2i(posmod(roundi(offset.x), 2), posmod(roundi(offset.y), 2))
	if not _floor_mats.has(key):
		var tex: Texture2D = null
		var n := (load(GLB.f01) as PackedScene).instantiate()
		for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			var m := mi.mesh.surface_get_material(0) as BaseMaterial3D
			if m and m.albedo_texture:
				tex = m.albedo_texture
				break
		n.free()
		var mat := ShaderMaterial.new()
		mat.shader = FLOOR_SHADER
		mat.set_shader_parameter("albedo_tex", tex)
		mat.set_shader_parameter("offset", Vector2(key))
		BLUE_PAINT.configure(mat, false)
		_floor_mats[key] = mat
	return _floor_mats[key]


## 방 바닥 메시의 줄눈 위상: 방의 왼쪽(-X)·뒤(-Z) 벽에서 2m 줄눈이 시작되게
static func _room_offset(mi: MeshInstance3D) -> Vector2:
	var b := mi.global_transform * mi.get_aabb()
	return Vector2(roundi(b.position.x), roundi(b.position.z))


static func block_mesh(kind: String) -> Mesh:
	if not _meshes.has(kind):
		var n := (load(GLB[kind]) as PackedScene).instantiate()
		var mi := n.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		_meshes[kind] = mi.mesh
		n.free()
	return _meshes[kind]


static func _inst(parent: Node3D, kind: String, pos: Vector3, yaw_deg: float) -> Node3D:
	var n := (load(GLB[kind]) as PackedScene).instantiate() as Node3D
	n.rotation_degrees.y = yaw_deg
	n.position = pos
	n.set_meta("claude_bg", kind)
	parent.add_child(n)
	return n


# ── 1. 뒤 벽 3m 구간 · 벽감 프랍 ─────────────────────────

## 벽 칸 b 에 3m 벽을 세울 수 있는가: 바로 앞(+Z)이 평평한 바닥, 출입구 아님, 뒤 BEHIND 칸에 바닥·기둥 없음, WallProps 자리 아님
static func _tall_ok(map: ArenaMap, b: Vector2i, occupied: Dictionary) -> bool:
	if map.cell_type(b) != ArenaMap.VOID or occupied.has(b):
		return false
	var f := b + Vector2i(0, 1)
	if map.cell_type(f) != ArenaMap.FLOOR or map.gate_of[map._idx(f)] >= 0 or absf(map.cell_h(f)) > 0.01:
		return false
	for k in range(1, BEHIND + 1):
		if map.cell_type(b - Vector2i(0, k)) != ArenaMap.VOID:
			return false
	return true


## 벽 칸의 바닥 쪽 경계(+Z 끝) · 왼쪽(-X) 끝 월드 좌표
static func _front_z(map: ArenaMap, b: Vector2i) -> float:
	return map.world_of(b).z + ArenaMap.CELL * 0.5


static func _left_x(map: ArenaMap, b: Vector2i) -> float:
	return map.world_of(b).x - ArenaMap.CELL * 0.5


static func plan(map: ArenaMap, occupied: Dictionary) -> void:
	if not enabled:
		return
	var kit := Node3D.new()
	kit.name = "ClaudeBg"
	map.add_child(kit)
	var tall := {}
	# 줄마다 연속 구간 [x0, x1)
	var runs: Array = []
	for y in ArenaMap.H:
		var x := 0
		while x < ArenaMap.W:
			if not _tall_ok(map, Vector2i(x, y), occupied):
				x += 1
				continue
			var x0 := x
			while x < ArenaMap.W and _tall_ok(map, Vector2i(x, y), occupied):
				x += 1
			if x - x0 >= MIN_RUN:        # 짧은 구간에 3m 판 하나만 서면 외딴 기둥처럼 보인다 → 낮은 블록으로
				runs.append([y, x0, x])
	# 방마다 벽감 몫: 작업대 1 · 수납장 1 (큰 방 2씩)
	var want := {}
	for r in map.rooms:
		want[r.id] = {"bench": 2 if r.scale > 1.0 else 1, "locker": 2 if r.scale > 1.0 else 1}
	for run in runs:
		var y: int = run[0]
		var x0: int = run[1]
		var x1: int = run[2]
		var alcoves: Array = []          # [시작 x, 종류]
		var taken := {}
		for kind in ["bench", "locker"]:
			var w := 2 if kind == "bench" else 1
			# 구간 가운데에 가까운 자리부터, 양옆 한 칸씩은 3m 벽으로 남긴다
			var cands: Array = range(x0 + 1, x1 - w)
			var mid := (x0 + x1 - w) * 0.5
			cands.sort_custom(func(a, b): return absf(a - mid) < absf(b - mid))
			for cx: int in cands:
				var rid := map.room_of[map._idx(Vector2i(cx, y + 1))]
				if rid < 0 or want[rid][kind] <= 0:
					continue
				var free := true
				for dx in range(-1, w + 1):
					if taken.has(cx + dx):
						free = false
				if not free:
					continue
				alcoves.append([cx, kind])
				for dx in w:
					taken[cx + dx] = true
				want[rid][kind] -= 1
				break
		# 벽감 만들기
		for a in alcoves:
			_alcove(map, kit, Vector2i(a[0], y), a[1])
			for dx in (2 if a[1] == "bench" else 1):
				occupied[Vector2i(a[0] + dx, y)] = true
		# 나머지는 3m 벽: 2m 모듈로 채우고 남는 한 칸은 반쪽 모듈
		var x := x0
		while x < x1:
			if taken.has(x):
				x += 1
				continue
			var two := x + 1 < x1 and not taken.has(x + 1)
			var b := Vector2i(x, y)
			var w := 2 if two else 1
			_inst(kit, "w01" if two else "half", Vector3(_left_x(map, b) + w, 0.0, _front_z(map, b)), 180.0)
			for dx in w:
				tall[Vector2i(x + dx, y)] = true
			x += w
	map.set_meta("claude_tall", tall)
	map.set_meta("claude_occupied", occupied)


## 벽감: c = 왼쪽 벽 칸. 안쪽 벽을 (프랍 깊이 + 0.05) 뒤로 물리고, 양옆 옆판 · 바닥 · 프랍.
static func _alcove(map: ArenaMap, kit: Node3D, c: Vector2i, kind: String) -> void:
	var w := 2.0 if kind == "bench" else 1.0
	var d: float = DEPTH[kind]
	var zf := _front_z(map, c)
	var xl := _left_x(map, c)
	_inst(kit, "w01" if kind == "bench" else "half", Vector3(xl + w, 0.0, zf - d - GAP), 180.0)
	_inst(kit, "jamb", Vector3(xl, 0.0, zf - 0.25), 180.0)              # 왼쪽 옆판: x xl-0.12 ~ xl
	_inst(kit, "jamb", Vector3(xl + w + 0.12, 0.0, zf - 0.25), 180.0)   # 오른쪽 옆판: x xl+w ~ xl+w+0.12
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, d + GAP)
	fl.mesh = pm
	var rid := map.room_of[map._idx(c + Vector2i(0, 1))]
	var lo := Vector2i(1 << 20, 1 << 20)
	for rc: Vector2i in map.rooms[rid].cells:
		lo = Vector2i(mini(lo.x, rc.x), mini(lo.y, rc.y))
	var corner := map.world_of(lo) - Vector3(ArenaMap.CELL, 0, ArenaMap.CELL) * 0.5
	fl.material_override = floor_material(Vector2(roundi(corner.x), roundi(corner.z)))   # 그 방 바닥과 같은 줄눈
	fl.position = Vector3(xl + w * 0.5, 0.0, zf - (d + GAP) * 0.5)
	fl.layers = 1 | MechDecals.RECEIVER
	kit.add_child(fl)
	_inst(kit, kind, Vector3(xl + w * 0.5, 0.0, zf - d * 0.5), 180.0)   # 정면(-Z)이 방 안(+Z)


# ── 2. 바닥 재질 · 낮은 블록 ────────────────────────────

static func apply(map: ArenaMap) -> void:
	if not enabled:
		return
	for ch in map.get_children():
		var mi := ch as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var cur := mi.material_override as ShaderMaterial
		if cur and cur.shader == map._floor_shader:
			mi.material_override = floor_material(_room_offset(mi))
		elif mi.material_override == null and mi.mesh is ArrayMesh and mi.mesh.get_surface_count() == 2:
			mi.visible = false                              # 예전 벽 상자 (충돌은 StaticBody 라 그대로)
			mi.set_meta("claude_hidden", true)
	var tall: Dictionary = map.get_meta("claude_tall", {})
	var occupied: Dictionary = map.get_meta("claude_occupied", {})
	var spots := {"wall": [], "cover": [], "pillar": []}
	for y in ArenaMap.H:
		for x in ArenaMap.W:
			var c := Vector2i(x, y)
			var i := map._idx(c)
			var g := map.grid[i]
			if g == ArenaMap.PILLAR:
				spots.pillar.append(Vector3(map.world_of(c).x, map.cell_h(c), map.world_of(c).z))
			elif g == ArenaMap.LOW:
				spots.cover.append(Vector3(map.world_of(c).x, map.cell_h(c), map.world_of(c).z))
			elif g == ArenaMap.VOID and map._near_floor(c) and not occupied.has(c) and not tall.has(c):
				var base := map.hgt[i] if not map.hgt.is_empty() else 0.0
				var p := map.world_of(c)
				spots.wall.append(Vector3(p.x, base, p.z))
	var kit := map.get_node_or_null("ClaudeBg") as Node3D
	for kind in spots:
		if spots[kind].is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = block_mesh(kind)
		mm.instance_count = spots[kind].size()
		for k in spots[kind].size():
			mm.set_instance_transform(k, Transform3D(Basis.IDENTITY, spots[kind][k]))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Blocks_" + kind
		mmi.multimesh = mm
		mmi.layers = 1 | MechDecals.RECEIVER
		mmi.set_meta("claude_bg", "blocks_" + kind)
		mmi.set_meta("claude_spots", spots[kind])      # 검사용 (헤드리스 렌더러는 MultiMesh 변환을 돌려주지 않는다)
		kit.add_child(mmi)
	ClaudeServiceDress.apply(map, kit)                  # 1번 설비실: 벽 밖 어둠을 낮은 설비 바닥 + 프랍 5종으로 (--service=off 면 없음)
