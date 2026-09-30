class_name Terrain
extends RefCounted
## 방 탐색 아레나의 바닥 굴곡.
## 방마다 작고 완만한 둔덕·오목한 자리를 몇 군데 얹어 평지의 단조로움만 덜어 낸다.
## 모두 걸어서 부드럽게 지나갈 수 있는 곡면이며 (칸 사이 높이 차 < ArenaMap.STEP), 따로 표시하지 않는다.
## 높이는 ArenaMap 의 칸 배열(hgt · smooth · feats)에 쓰고, 여기서 바닥 메시를 만든다.

const SUB := 3                 # 곡면 칸을 SUB×SUB 로 나눠 곡률을 살린다


# ── 생성 ────────────────────────────────────────────────

static func shape(m: ArenaMap) -> void:
	var n := ArenaMap.W * ArenaMap.H
	m.hgt.resize(n)
	m.hgt.fill(0.0)
	m.smooth.resize(n)
	m.smooth.fill(-1)
	m.feats.clear()
	if not m.terrain:
		return
	for r in m.rooms:
		_room(m, r)
	# 벽 칸 높이 = 이웃 바닥 중 가장 높은 곳 (둔덕 옆 벽이 바닥에 묻히지 않게)
	for y in ArenaMap.H:
		for x in ArenaMap.W:
			var c := Vector2i(x, y)
			if m.grid[m._idx(c)] != ArenaMap.VOID:
				continue
			var top := 0.0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nb := c + Vector2i(dx, dy)
					if m._in(nb) and m.grid[m._idx(nb)] != ArenaMap.VOID:
						top = maxf(top, _cell_max(m, nb))
			m.hgt[m._idx(c)] = top


## 방 넓이에 따라 굴곡 2~5개. 대부분 볼록한 둔덕, 가끔 얕게 오목한 자리.
static func _room(m: ArenaMap, r: Dictionary) -> void:
	var info := _room_info(m, r)
	var want := clampi(info.floor.size() / 60, 2, 5)
	var placed := 0
	var tries := want * 50
	for attempt in tries:
		if placed >= want:
			break
		# 뒤쪽 시도일수록 작게 (기둥·엄폐물 사이 좁은 틈에도 들어가게)
		if _bump(m, r, info, lerpf(1.0, 0.55, float(attempt) / tries)):
			placed += 1
	if OS.get_cmdline_user_args().has("--terrainlog"):
		print("TERRAIN room=%d shape=%d cells=%d bumps=%d/%d" % [r.id, r.shape, info.floor.size(), placed, want])


## 방 바닥 칸 · 통로 입구 칸
static func _room_info(m: ArenaMap, r: Dictionary) -> Dictionary:
	var flo: Array[Vector2i] = []
	var entries: Array[Vector2i] = []
	var R := int(ceil(r.r)) + 2
	var c0: Vector2i = r.center
	for dy in range(-R, R + 1):
		for dx in range(-R, R + 1):
			var c := c0 + Vector2i(dx, dy)
			if not m._in(c) or m.room_of[m._idx(c)] != r.id or m.grid[m._idx(c)] != ArenaMap.FLOOR:
				continue
			flo.append(c)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nb: Vector2i = c + d
				if m._in(nb) and m.room_of[m._idx(nb)] == -1 and m.grid[m._idx(nb)] == ArenaMap.FLOOR and not entries.has(nb):
					entries.append(nb)
	return {"floor": flo, "entries": entries}


## 둥근 굴곡 하나: 가운데 반경 r0 은 거의 평평하고, r1 까지 S자 단면으로 바닥에 스며든다
static func _bump(m: ArenaMap, r: Dictionary, info: Dictionary, k := 1.0) -> bool:
	var rng := m.rng
	var P: Vector2i = info.floor[rng.randi_range(0, info.floor.size() - 1)]
	var h := rng.randf_range(0.2, 0.38) * k
	if rng.randf() < 0.3:
		h = -rng.randf_range(0.15, 0.26) * k
	var r0 := rng.randf_range(0.1, 0.6) * k
	var r1 := r0 + rng.randf_range(1.9, 2.6) * k
	var cw := Vector2((P.x - ArenaMap.W * 0.5 + 0.5) * ArenaMap.CELL, (P.y - ArenaMap.H * 0.5 + 0.5) * ArenaMap.CELL)
	var cells: Array[Vector2i] = []
	var R := int(ceil(r1)) + 1
	for dy in range(-R, R + 1):
		for dx in range(-R, R + 1):
			var c := P + Vector2i(dx, dy)
			var near := Vector2(maxf(absf(dx) - 0.5, 0.0), maxf(absf(dy) - 0.5, 0.0)).length() * ArenaMap.CELL
			if near >= r1:
				continue
			# 방 바닥 안, 엄폐물·기둥·출입구·다른 굴곡과 떨어진 곳에만
			if not _free(m, r, c) or not _clear(m, c) or _door_d(info, c) < 2.0:
				return false
			cells.append(c)
	m.feats.append({"k": "mound", "c": cw, "r0": r0, "r1": r1, "h": h, "base": 0.0})
	var fi := m.feats.size() - 1
	for c in cells:
		m.smooth[m._idx(c)] = fi
	return true


static func _door_d(info: Dictionary, c: Vector2i) -> float:
	var d := 1e9
	for e in info.entries:
		d = minf(d, Vector2(c - (e as Vector2i)).length())
	return d


## 아직 굴곡이 없는 이 방의 칸인가 (기둥·엄폐물 칸도 된다: 밑동이 바닥 아래까지 묻혀 있어 비탈에서도 뜨지 않는다)
static func _free(m: ArenaMap, r: Dictionary, c: Vector2i) -> bool:
	if not m._in(c):
		return false
	var i := m._idx(c)
	return m.room_of[i] == r.id and m.grid[i] != ArenaMap.VOID and m.smooth[i] < 0


## 둘레 한 칸 안에 다른 굴곡이 없는가 (굴곡끼리 붙어 뭉개지지 않게)
static func _clear(m: ArenaMap, c: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n := c + Vector2i(dx, dy)
			if m._in(n) and m.smooth[m._idx(n)] >= 0:
				return false
	return true


# ── 높이 보조 ───────────────────────────────────────────

static func _cell_max(m: ArenaMap, c: Vector2i) -> float:
	var i := m._idx(c)
	if m.smooth[i] < 0:
		return m.hgt[i]
	var mn := _min_corner(c)
	var top := -INF
	for k in 4:
		top = maxf(top, m.feat_h(m.smooth[i], mn.x + (k % 2) * ArenaMap.CELL, mn.y + (k / 2) * ArenaMap.CELL))
	return top


static func _min_corner(c: Vector2i) -> Vector2:
	return Vector2((c.x - ArenaMap.W * 0.5) * ArenaMap.CELL, (c.y - ArenaMap.H * 0.5) * ArenaMap.CELL)


# ── 메시 ────────────────────────────────────────────────

## 바닥 윗면. 평평한 칸은 사각형 하나, 굴곡 칸은 SUB×SUB 로 나눠 법선까지 부드럽게.
static func floor_cells(m: ArenaMap, st: SurfaceTool, cells: Array) -> void:
	var C := ArenaMap.CELL
	for c in cells:
		var cc: Vector2i = c
		var mn := _min_corner(cc)
		var i := m._idx(cc)
		var f: int = m.smooth[i] if not m.smooth.is_empty() else -1
		if f < 0:
			var h: float = m.hgt[i] if not m.hgt.is_empty() else 0.0
			st.set_normal(Vector3.UP)
			var a := Vector3(mn.x, h, mn.y)
			var b := Vector3(mn.x + C, h, mn.y)
			var e := Vector3(mn.x + C, h, mn.y + C)
			var d := Vector3(mn.x, h, mn.y + C)
			st.add_vertex(a); st.add_vertex(b); st.add_vertex(e)
			st.add_vertex(a); st.add_vertex(e); st.add_vertex(d)
			continue
		var s := C / SUB
		for v in SUB:
			for u in SUB:
				var x0 := mn.x + u * s
				var z0 := mn.y + v * s
				var pts := [Vector2(x0, z0), Vector2(x0 + s, z0), Vector2(x0 + s, z0 + s), Vector2(x0, z0 + s)]
				for k in [0, 1, 2, 0, 2, 3]:
					var q: Vector2 = pts[k]
					st.set_normal(_normal(m, f, q.x, q.y))
					st.add_vertex(Vector3(q.x, m.feat_h(f, q.x, q.y), q.y))


static func _normal(m: ArenaMap, f: int, x: float, z: float) -> Vector3:
	var e := 0.05
	var gx := (m.feat_h(f, x + e, z) - m.feat_h(f, x - e, z)) / (2.0 * e)
	var gz := (m.feat_h(f, x, z + e) - m.feat_h(f, x, z - e)) / (2.0 * e)
	return Vector3(-gx, 1.0, -gz).normalized()
