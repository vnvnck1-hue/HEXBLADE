class_name RogueMap
extends ArenaMap
## 아이작식 층 생성: 9×9 슬롯 그리드에 방을 BFS 로 뻗어 붙이고, 이웃한 방은 짧은 통로(문)로 직결한다.
## 벽·바닥·차단막·꾸밈·충돌은 ArenaMap.build() 를 그대로 쓴다 (모든 방을 combat 으로 찍어 문마다 차단막이 생기게 한다).
##
## 방 사전에 더하는 값: kind(방 종류) · slots(차지한 슬롯) · rect(안쪽 칸 범위) · dist(시작에서 슬롯 거리)
##  · nbr(문으로 이어진 방 id) · locked · secret_wall(비밀방으로 가는 금 간 벽 자리, 비밀방 사전에만)
## 비밀방·거래방(악마/천사)은 그리드 아래쪽에 떨어진 섬으로 찍고 포털로만 오간다.

const GW := 9
const GH := 9
const PX := 29                 # 슬롯 간격 (칸)
const PY := 21
const RW := 23                 # 1×1 방 안쪽 크기
const RH := 15
const OX := 9
const OY := 10
const ISLAND_Y := 222          # 떨어진 섬 방의 윗줄
const START := Vector2i(4, 4)

var slot_room := {}            # Vector2i 슬롯 → 방 id
var depth := 1
var island_secret := -1
var island_deal := -1
var boss_room := -1
var gen_tries := 0


static func slot_origin(s: Vector2i) -> Vector2i:
	return Vector2i(OX + s.x * PX, OY + s.y * PY)


func room_count_for(d: int) -> int:
	return 6 + d + rng.randi_range(0, 2)


## 특수방 목록 (보스 제외). 깊을수록 늘어난다.
func _special_list(d: int) -> Array:
	var out := ["treasure", "shop"]
	var extra := ["sacrifice", "curse", "challenge", "library"]
	for i in range(extra.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = extra[i]
		extra[i] = extra[j]
		extra[j] = t
	var n := 1 if d <= 2 else 2
	for i in n:
		out.append(extra[i])
	return out


func generate_floor(seed_value: int, d: int) -> void:
	depth = d
	rng.seed = seed_value
	var layout := {}
	var dist := {}
	var specials := _special_list(d)
	for attempt in 200:
		gen_tries = attempt + 1
		layout = _bfs(room_count_for(d))
		if layout.is_empty():
			continue
		dist = _slot_dist(layout)
		var ends := _dead_ends(layout)
		if ends.size() >= specials.size() + 1:
			break
		layout = {}
	assert(not layout.is_empty())
	# 막다른 방: 가장 먼 곳이 보스, 나머지에 특수방
	var ends := _dead_ends(layout)
	ends.sort_custom(func(a, b): return dist[a] > dist[b])
	var kinds := {}
	kinds[ends[0]] = "boss"
	var rest: Array = ends.slice(1)
	for i in rest.size():
		var j := rng.randi_range(0, rest.size() - 1)
		var t = rest[i]
		rest[i] = rest[j]
		rest[j] = t
	for i in mini(specials.size(), rest.size()):
		kinds[rest[i]] = specials[i]
	# 큰 방: 특수방이 아닌 이웃 두 슬롯을 하나로 (최대 2개)
	var merged := {}       # 슬롯 → 대표 슬롯
	var merges := 0
	var keys_ := layout.keys()
	keys_.shuffle()
	for s in keys_:
		if merges >= 2 or merged.has(s) or kinds.has(s) or s == START:
			continue
		for dv in [Vector2i(1, 0), Vector2i(0, 1)]:
			var n: Vector2i = s + dv
			if layout.has(n) and not merged.has(n) and not kinds.has(n) and n != START and rng.randf() < 0.45:
				merged[s] = s
				merged[n] = s
				merges += 1
				break
	_reset_grid()
	slot_room.clear()
	# 방 찍기 (시작 방이 0번)
	var order: Array = [START]
	for s in layout:
		if s != START:
			order.append(s)
	for s in order:
		if slot_room.has(s):
			continue
		var slots: Array = [s]
		if merged.has(s):
			for o in merged:
				if merged[o] == merged[s] and o != s:
					slots.append(o)
		var kind: String = "start" if s == START else kinds.get(s, "normal")
		var id := _stamp_slots(slots, kind)
		rooms[id].dist = dist[s]
		for q in slots:
			slot_room[q] = id
	start_room = 0
	# 문: 이웃한 슬롯이 다른 방이면 통로를 판다
	for s in layout:
		for dv in [Vector2i(1, 0), Vector2i(0, 1)]:
			var n: Vector2i = s + dv
			if not layout.has(n):
				continue
			var a: int = slot_room[s]
			var b: int = slot_room[n]
			if a == b:
				continue
			_carve_door(s, n)
			if not rooms[a].nbr.has(b):
				rooms[a].nbr.append(b)
				rooms[b].nbr.append(a)
				rooms[a].links.append(b)
				rooms[b].links.append(a)
	_place_secret(layout, kinds)
	# 떨어진 섬: 거래방
	island_deal = _stamp_rect(Rect2i(OX + 2 * PX, ISLAND_Y, RW, RH), "deal", [])
	for r in rooms:
		if r.kind == "boss":
			boss_room = r.id
		if (r.kind == "treasure" or r.kind == "shop") and d >= 2:
			r.locked = true
		if r.kind == "challenge":
			r.locked = true
	for r in rooms:
		if r.kind in ["normal", "challenge", "boss"]:
			_obstacles(r)
	update_scan()
	_find_doors()
	Terrain.shape(self)
	_compute_anchors()


func _reset_grid() -> void:
	var n := W * H
	grid.resize(n)
	grid.fill(VOID)
	room_of.resize(n)
	room_of.fill(-1)
	gate_of.resize(n)
	gate_of.fill(-1)
	discovered.resize(n)
	discovered.fill(0)
	rooms.clear()


## 아이작식 BFS: 이웃이 이미 2개 이상인 칸은 건너뛰어 고리가 생기지 않게 한다
func _bfs(target: int) -> Dictionary:
	var filled := {START: true}
	var q: Array = [START]
	var count := 1
	var guard := 0
	while count < target and guard < 400:
		guard += 1
		if q.is_empty():
			# 막혔으면 아무 칸에서나 다시 뻗는다
			q = filled.keys()
			q.shuffle()
		var cur: Vector2i = q.pop_front()
		var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		dirs.shuffle()
		for dv in dirs:
			if count >= target:
				break
			var nb: Vector2i = cur + dv
			if nb.x < 0 or nb.y < 0 or nb.x >= GW or nb.y >= GH or filled.has(nb):
				continue
			if _filled_nbrs(filled, nb) > 1:
				continue
			if cur != START and rng.randf() < 0.5:
				continue
			filled[nb] = true
			q.append(nb)
			count += 1
	return filled if count >= target else {}


func _filled_nbrs(filled: Dictionary, s: Vector2i) -> int:
	var n := 0
	for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if filled.has(s + dv):
			n += 1
	return n


func _dead_ends(layout: Dictionary) -> Array:
	var out: Array = []
	for s in layout:
		if s != START and _filled_nbrs(layout, s) == 1:
			out.append(s)
	return out


func _slot_dist(layout: Dictionary) -> Dictionary:
	var d := {START: 0}
	var q: Array = [START]
	while q.size() > 0:
		var c: Vector2i = q.pop_front()
		for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + dv
			if layout.has(n) and not d.has(n):
				d[n] = d[c] + 1
				q.append(n)
	return d


func _slots_rect(slots: Array) -> Rect2i:
	var lo := Vector2i(999, 999)
	var hi := Vector2i(-1, -1)
	for s in slots:
		lo = Vector2i(mini(lo.x, s.x), mini(lo.y, s.y))
		hi = Vector2i(maxi(hi.x, s.x), maxi(hi.y, s.y))
	var o := slot_origin(lo)
	return Rect2i(o, Vector2i(RW + (hi.x - lo.x) * PX, RH + (hi.y - lo.y) * PY))


func _stamp_slots(slots: Array, kind: String) -> int:
	return _stamp_rect(_slots_rect(slots), kind, slots)


func _stamp_rect(rect: Rect2i, kind: String, slots: Array) -> int:
	var c := rect.position + rect.size / 2
	var cells: Array[Vector2i] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			cells.append(Vector2i(x, y) - c)
	var shp := {"cells": cells, "pillars": [], "lows": [], "r": Vector2(rect.size).length() * 0.5}
	var id := _stamp(c, shp, Shape.RECT, true)
	var r: Dictionary = rooms[id]
	r.kind = kind
	r.slots = slots
	r.rect = rect
	r.dist = 0
	r.nbr = []
	r.locked = false
	r.visited = false
	r.seen = false
	return id


## 이웃 슬롯 a·b 사이 통로 (폭 3칸)
func _carve_door(a: Vector2i, b: Vector2i) -> void:
	var oa := slot_origin(a)
	if b.x != a.x:
		var lo := a if a.x < b.x else b
		var o := slot_origin(lo)
		var y := o.y + RH / 2
		for x in range(o.x + RW, o.x + PX):
			for dy in range(-1, 2):
				grid[_idx(Vector2i(x, y + dy))] = FLOOR
	else:
		var lo := a if a.y < b.y else b
		var o := slot_origin(lo)
		var x := o.x + RW / 2
		for y in range(o.y + RH, o.y + PY):
			for dx in range(-1, 2):
				grid[_idx(Vector2i(x + dx, y))] = FLOOR
	oa = oa


## 비밀방: 일반 방 2개 이상과 이웃한 빈 슬롯 → 섬에 찍고, 이웃 방 벽 하나를 금 간 벽으로
func _place_secret(layout: Dictionary, kinds: Dictionary) -> void:
	var best := Vector2i(-1, -1)
	var best_n := 0
	for y in GH:
		for x in GW:
			var s := Vector2i(x, y)
			if layout.has(s):
				continue
			var n := 0
			var near_boss := false
			for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if layout.has(s + dv):
					if kinds.get(s + dv, "") == "boss":
						near_boss = true
					else:
						n += 1
			if near_boss or n < 1:
				continue
			var score := n * 10 + rng.randi_range(0, 5)
			if score > best_n:
				best_n = score
				best = s
	if best.x < 0:
		return
	island_secret = _stamp_rect(Rect2i(OX, ISLAND_Y, RW, RH), "secret", [])
	var r: Dictionary = rooms[island_secret]
	r.ghost_slot = best
	# 이웃 일반 방 하나를 골라 그 방 벽(비밀 슬롯 쪽) 가운데에 금 간 벽
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	dirs.shuffle()
	for dv in dirs:
		var n: Vector2i = best + dv
		if layout.has(n) and kinds.get(n, "") != "boss":
			var o := slot_origin(n)
			var cell: Vector2i
			var face := Vector2i(-dv.x, -dv.y)     # 이웃 방에서 비밀 슬롯 쪽
			if face.x > 0:
				cell = Vector2i(o.x + RW - 1, o.y + RH / 2)
			elif face.x < 0:
				cell = Vector2i(o.x, o.y + RH / 2)
			elif face.y > 0:
				cell = Vector2i(o.x + RW / 2, o.y + RH - 1)
			else:
				cell = Vector2i(o.x + RW / 2, o.y)
			r.secret_wall = {"room": slot_room[n], "cell": cell, "face": face}
			break


## 방 안 장애물: 문 쪽 십자 통로는 비워 두고, 좌우·상하 대칭으로 놓는다
func _obstacles(r: Dictionary) -> void:
	var rect: Rect2i = r.rect
	var pat := rng.randi_range(0, 6)
	if r.kind == "boss":
		pat = [0, 1, 6][rng.randi_range(0, 2)]
	var slots: Array = r.slots
	if slots.is_empty():
		return
	for s in slots:
		var o := slot_origin(s)
		_pattern(Rect2i(o, Vector2i(RW, RH)), pat, r.id)


func _pattern(rc: Rect2i, pat: int, rid: int) -> void:
	var cx := rc.position.x + RW / 2
	var cy := rc.position.y + RH / 2
	var marks: Array = []          # [오프셋 Vector2i (오른쪽 아래 사분면), 종류]
	match pat:
		1:    # 기둥 넷
			for o in [Vector2i(6, 3), Vector2i(7, 3), Vector2i(6, 4), Vector2i(7, 4)]:
				marks.append([o, PILLAR])
		2:    # 모서리 엄폐물
			for o in [Vector2i(7, 4), Vector2i(8, 4), Vector2i(9, 4), Vector2i(9, 3)]:
				marks.append([o, LOW])
		3:    # 가로 차선
			for x in range(4, 9):
				marks.append([Vector2i(x, 4), LOW])
		4:    # 흩어진 바위
			for i in rng.randi_range(2, 4):
				marks.append([Vector2i(rng.randi_range(3, 9), rng.randi_range(3, 5)), LOW])
		5:    # 고리
			for x in range(3, 8):
				marks.append([Vector2i(x, 3), LOW])
			marks.append([Vector2i(7, 3), LOW])
		6:    # 기둥 점점이
			for o in [Vector2i(4, 3), Vector2i(8, 3), Vector2i(6, 5)]:
				marks.append([o, PILLAR])
	for m in marks:
		var o: Vector2i = m[0]
		for sx in [-1, 1]:
			for sy in [-1, 1]:
				var c := Vector2i(cx + o.x * sx, cy + o.y * sy)
				if absi(c.x - cx) <= 2 or absi(c.y - cy) <= 2:
					continue
				if not rc.grow(-2).has_point(c):
					continue
				var i := _idx(c)
				if grid[i] == FLOOR and room_of[i] == rid:
					grid[i] = m[1]


# ── 조회 ────────────────────────────────────────────────

func room_kind(id: int) -> String:
	return rooms[id].kind if id >= 0 and id < rooms.size() else ""


func rooms_of_kind(kind: String) -> Array:
	var out: Array = []
	for r in rooms:
		if r.kind == kind:
			out.append(r.id)
	return out


## 방 바닥의 무작위 빈자리 (둘레 3×3 이 비어 있어야 함)
func free_spot(id: int, avoid: Vector3, min_dist: float) -> Vector3:
	return random_spot(id, avoid, min_dist)


func room_center(id: int) -> Vector3:
	var rect: Rect2i = rooms[id].rect
	return world_of(rect.position + rect.size / 2)
