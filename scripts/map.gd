class_name ArenaMap
extends Node3D
## 격자 기반 방·통로 맵.
## 여러 형태의 방을 트리처럼 이어 붙이고 일부는 고리형 통로로 한 번 더 연결한다.
## 방에 들어서면 출입구 차단막이 닫히고, 정리하면 열린다.
## 몇몇 전투방은 보통 방의 2~3배 크기로 넓게 찍고, 그중 가장 큰 방은 웨이브 방(WAVES 번 웨이브)이 된다.

const CELL := 1.0
const W := 180
const H := 180
const VOID := 0
const FLOOR := 1
const PILLAR := 2      # 방 안의 높은 기둥
const LOW := 3         # 방 안의 낮은 엄폐물
const WALL_H := 0.8
const PILLAR_H := 1.5
const LOW_H := 0.7
const COMBAT_ROOMS := 9
## 넓은 방: 전투방 번호(생성 순서) → 보통 방 대비 크기 배율. 자리가 없으면 배율을 조금씩 줄여 다시 찾는다.
const BIG_ROOMS := {3: 2.0, 6: 2.5, 9: 3.0}
const BIG_MIN_SCALE := 2.0
## 넓은 방에 쓰는 형태 (L자 회랑은 늘리면 긴 복도가 돼서 뺀다)
const BIG_SHAPES := [Shape.RECT, Shape.ROUND, Shape.CROSS, Shape.PILLARS, Shape.RING, Shape.OCTAGON, Shape.BLOB]
## 웨이브 방(가장 큰 방)에 쓰는 형태: 사방이 트인 넓은 홀
const WAVE_SHAPES := [Shape.OCTAGON, Shape.PILLARS, Shape.RECT, Shape.RING]
const WAVES := 5
# ── 바닥 굴곡 (terrain 이 켜진 맵만. 끄면 모든 칸 높이 0) ──
const STEP := 0.5          # 걸어서 넘을 수 있는 높이 차. 굴곡은 모두 이보다 완만하다

enum Shape { RECT, ROUND, L, CROSS, PILLARS, RING, OCTAGON, BLOB }
const SHAPE_NAMES := ["홀", "원형 광장", "L자 회랑", "십자 교차로", "기둥 홀", "고리 광장", "팔각 홀", "동굴"]

var grid := PackedByteArray()
var room_of := PackedInt32Array()
var gate_of := PackedInt32Array()
var discovered := PackedByteArray()
var rooms: Array = []           # Dictionary 목록
var rng := RandomNumberGenerator.new()
var start_room := 0
var wave_room := -1
var minimap_img: Image
var minimap_tex: ImageTexture
var _disc_t := 0.0
var _gate_mat: StandardMaterial3D
var _floor_shader: Shader
var _t := 0.0
var terrain := false
var hgt := PackedFloat32Array()       # 칸 중심 높이 (벽 칸은 이웃 바닥 중 가장 높은 값)
var smooth := PackedInt32Array()      # 곡면 지형 요소 번호. -1 이면 hgt 높이의 평평한 칸
var feats: Array = []                 # 곡면 요소: 둔덕/오목한 자리(mound)


# ── 좌표 ────────────────────────────────────────────────

func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL + W * 0.5), floori(p.z / CELL + H * 0.5))


func world_of(c: Vector2i) -> Vector3:
	var p := Vector3((c.x - W * 0.5 + 0.5) * CELL, 0, (c.y - H * 0.5 + 0.5) * CELL)
	p.y = cell_h(c)
	return p


## 칸 중심의 지면 높이
func cell_h(c: Vector2i) -> float:
	if hgt.is_empty() or not _in(c):
		return 0.0
	var i := _idx(c)
	if smooth[i] >= 0:
		return feat_h(smooth[i], (c.x - W * 0.5 + 0.5) * CELL, (c.y - H * 0.5 + 0.5) * CELL)
	return hgt[i]


## 월드 xz 지점의 지면 높이 (곡면 칸은 연속 함수, 나머지는 칸 높이)
func height_at(p: Vector3) -> float:
	if hgt.is_empty():
		return 0.0
	var c := cell_of(p)
	if not _in(c):
		return 0.0
	var i := _idx(c)
	return feat_h(smooth[i], p.x, p.z) if smooth[i] >= 0 else hgt[i]


## 칸 c 의 지면 높이를 점 p 에 가장 가까운 칸 안 지점에서 잰다 (비탈을 오를 때 칸 이음새에서 막히지 않게)
func _near_h(c: Vector2i, p: Vector3) -> float:
	var i := _idx(c)
	if smooth[i] < 0:
		return hgt[i]
	var mn := Vector3((c.x - W * 0.5) * CELL, 0, (c.y - H * 0.5) * CELL)
	return feat_h(smooth[i], clampf(p.x, mn.x, mn.x + CELL), clampf(p.z, mn.z, mn.z + CELL))


## 곡면 요소 f 의 (x, z) 높이. 둥근 S자(smoothstep) 단면이라 바닥과 이음새 없이 이어진다.
func feat_h(f: int, x: float, z: float) -> float:
	var ft: Dictionary = feats[f]
	var r := Vector2(x, z).distance_to(ft.c)
	return ft.base + ft.h * (1.0 - smoothstep(ft.r0, ft.r1, r))


func _idx(c: Vector2i) -> int:
	return c.y * W + c.x


func _in(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H


func cell_type(c: Vector2i) -> int:
	return grid[_idx(c)] if _in(c) else VOID


# ── 판정 ────────────────────────────────────────────────

func is_blocked_cell(c: Vector2i) -> bool:
	if not _in(c):
		return true
	var i := _idx(c)
	if grid[i] != FLOOR:
		return true
	var g := gate_of[i]
	return g >= 0 and rooms[g].gates_closed


## 벽·기둥·닫힌 차단막, 그리고 p.y 보다 STEP 넘게 높은 지면이면 막힘 (굴곡은 모두 이보다 완만하다)
func is_blocked(p: Vector3) -> bool:
	if is_blocked_cell(cell_of(p)):
		return true
	return terrain and height_at(p) > p.y + STEP


## 원(반지름 r)을 막힌 칸 밖으로 밀어낸다. 지형이 있으면 p.y 를 발 높이로 보고,
## 끝나면 지면 높이로 붙인다 (내리막·낭떠러지는 몇 프레임에 걸쳐 내려앉는다).
func push_out(p: Vector3, r: float) -> Vector3:
	p = push_out_feet(p, r, p.y, STEP)
	if terrain:
		var h := height_at(p)
		p.y = h if h >= p.y else lerpf(p.y, h, 0.35)
	return p


## push_out 과 같되 높이를 바꾸지 않는다. feet 보다 climb 넘게 높은 칸을 벽으로 본다 (플레이어 점프용).
func push_out_feet(p: Vector3, r: float, feet: float, climb := STEP) -> Vector3:
	for iter in 2:
		var c := cell_of(p)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n := c + Vector2i(dx, dy)
				if not is_blocked_cell(n) and not (terrain and _near_h(n, p) > feet + climb):
					continue
				var mn := world_of(n) - Vector3(CELL, 0, CELL) * 0.5
				var q := Vector2(clampf(p.x, mn.x, mn.x + CELL), clampf(p.z, mn.z, mn.z + CELL))
				var d := Vector2(p.x, p.z) - q
				var l := d.length()
				if l < r:
					if l < 0.0001:
						var cc := world_of(n)
						d = Vector2(p.x - cc.x, p.z - cc.z)
						l = maxf(d.length(), 0.0001)
						d = d / l * 0.001
						l = 0.001
					var push := d / l * (r - l)
					p.x += push.x
					p.z += push.y
	return p


func room_at(p: Vector3) -> int:
	var c := cell_of(p)
	return room_of[_idx(c)] if _in(c) else -1


# ── 생성 ────────────────────────────────────────────────

func generate(seed_value: int) -> void:
	rng.seed = seed_value
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

	start_room = _stamp(Vector2i(W / 2, H / 2), _shape(Shape.RECT, Vector2i(22, 16)), Shape.RECT, false)
	var tries := 0
	# 형태 주머니: 모든 형태가 한 번씩 나온 뒤에 반복
	var bag: Array = []
	# 넓은 방: 이번 번호의 배율 · 형태 · 실패 횟수
	var big_scale := 0.0
	var big_shape := -1
	var big_fail := 0
	while rooms.size() < COMBAT_ROOMS + 1 and tries < 3000:
		tries += 1
		var want_big: float = BIG_ROOMS.get(rooms.size(), 0.0)
		if want_big > 0.0:
			if big_shape < 0:
				var last: bool = rooms.size() == BIG_ROOMS.keys().max()
				var pick: Array = WAVE_SHAPES if last else BIG_SHAPES
				big_shape = pick[rng.randi_range(0, pick.size() - 1)]
				if big_scale <= 0.0:
					big_scale = want_big
			# 넓은 방은 오래 못 찾으면 아무 방에서나 뻗어 나간다 (자리가 넉넉한 쪽을 찾게)
			var bparent: Dictionary = rooms[rng.randi_range(0 if big_fail > 30 else maxi(0, rooms.size() - 3), rooms.size() - 1)]
			var bshp := _big_shape(big_shape, big_scale)
			var bang := rng.randf() * TAU
			var bdist: float = bparent.r + bshp.r + rng.randf_range(6.0, 11.0)
			var bc: Vector2i = bparent.center + Vector2i(roundi(cos(bang) * bdist), roundi(sin(bang) * bdist))
			if not _fits(bc, bshp.r):
				big_fail += 1
				if big_fail % 60 == 0:
					big_scale = maxf(BIG_MIN_SCALE, big_scale - 0.1)
					big_shape = -1           # 형태도 다시 골라 본다
				continue
			var bid := _stamp(bc, bshp, big_shape, true)
			rooms[bid].scale = big_scale
			_carve_corridor(bparent.center, bc)
			bparent.links.append(bid)
			rooms[bid].links.append(bparent.id)
			print("BIG_ROOM id=%d shape=%d scale=%.1f r=%.1f cells=%d" % [bid, big_shape, big_scale, bshp.r, rooms[bid].cells.size()])
			big_shape = -1
			big_scale = 0.0
			big_fail = 0
			continue
		if bag.is_empty():
			for k in Shape.size():
				bag.append(k)
			for k in range(bag.size() - 1, 0, -1):
				var j := rng.randi_range(0, k)
				var tmp = bag[k]
				bag[k] = bag[j]
				bag[j] = tmp
		# 최근 방에서 뻗어 나가는 경향 → 길게 이어지면서도 가지가 생긴다
		var lo := maxi(0, rooms.size() - 3)
		var parent: Dictionary = rooms[rng.randi_range(lo, rooms.size() - 1)]
		if tries % 30 == 0:
			bag.push_back(bag.pop_front())   # 계속 안 들어가는 형태는 뒤로
		var shape_id: int = bag[0]
		var shp := _shape(shape_id)
		var ang := rng.randf() * TAU
		var dist: float = parent.r + shp.r + rng.randf_range(6.0, 11.0)
		var c: Vector2i = parent.center + Vector2i(roundi(cos(ang) * dist), roundi(sin(ang) * dist))
		if not _fits(c, shp.r):
			continue
		var id := _stamp(c, shp, shape_id, true)
		_carve_corridor(parent.center, c)
		parent.links.append(id)
		rooms[id].links.append(parent.id)
		bag.pop_front()
	# 고리형 연결: 가깝지만 이어지지 않은 방끼리 추가 통로
	for a in rooms:
		for b in rooms:
			if a.id < b.id and not a.links.has(b.id):
				var d: float = Vector2(a.center - b.center).length()
				if d < a.r + b.r + 14.0 and rng.randf() < 0.45:
					_carve_corridor(a.center, b.center)
					a.links.append(b.id)
					b.links.append(a.id)
	_find_doors()
	_assign_difficulty()
	_pick_wave_room()
	Terrain.shape(self)
	_compute_anchors()


## 바닥이 가장 넓은 전투방을 웨이브 방으로 삼는다
func _pick_wave_room() -> void:
	wave_room = -1
	var most := 0
	for r in rooms:
		if r.combat and r.scale > 1.0 and r.cells.size() > most:
			most = r.cells.size()
			wave_room = r.id
	if wave_room >= 0:
		rooms[wave_room].wave = true


## 섹터 런용: 방 하나만 맵 가운데 찍는다 (통로·차단막 없음). combat 이 거짓이면 안전 구역.
## size 를 주면 그 크기의 엄폐물 없는 홀(RECT)이 된다.
func generate_single(seed_value: int, shape_id: int, combat: bool, size := Vector2i.ZERO) -> void:
	rng.seed = seed_value
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
	start_room = _stamp(Vector2i(W / 2, H / 2), _shape(shape_id, size), shape_id, combat)
	Terrain.shape(self)
	_compute_anchors()


## 방 안에서 둘레 3×3 칸이 모두 비어 있는 바닥 칸의 월드 위치 목록
func open_spots(id: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for c in rooms[id].cells:
		var ok := true
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if is_blocked_cell(c + Vector2i(dx, dy)) or not _flat_near(c, c + Vector2i(dx, dy)):
					ok = false
		if ok:
			out.append(world_of(c))
	return out


func _fits(c: Vector2i, r: float) -> bool:
	var m := int(ceil(r)) + 4
	if c.x < m or c.y < m or c.x >= W - m or c.y >= H - m:
		return false
	for o in rooms:
		if Vector2(c - o.center).length() < r + o.r + 4.0:
			return false
	return true


## 모양별 칸 목록. cells=바닥, pillars=높은 기둥, lows=낮은 엄폐물
func _shape(s: int, size := Vector2i.ZERO) -> Dictionary:
	var cells: Array[Vector2i] = []
	var pillars: Array[Vector2i] = []
	var lows: Array[Vector2i] = []
	match s:
		Shape.RECT:
			var w := size.x if size.x > 0 else rng.randi_range(13, 19)
			var h := size.y if size.y > 0 else rng.randi_range(11, 15)
			for y in range(-h / 2, h - h / 2):
				for x in range(-w / 2, w - w / 2):
					cells.append(Vector2i(x, y))
			if size.x == 0:
				for i in rng.randi_range(2, 3):
					var bx := rng.randi_range(-w / 2 + 3, w / 2 - 5)
					var by := rng.randi_range(-h / 2 + 3, h / 2 - 4)
					var horiz := rng.randf() < 0.5
					for k in 3:
						lows.append(Vector2i(bx + (k if horiz else 0), by + (0 if horiz else k)))
		Shape.ROUND:
			var R := rng.randf_range(6.5, 8.5)
			_disc(cells, Vector2.ZERO, R)
		Shape.L:
			var a := rng.randi_range(15, 19)
			var t := rng.randi_range(6, 8)
			var fx := 1 if rng.randf() < 0.5 else -1
			var fy := 1 if rng.randf() < 0.5 else -1
			for y in range(-a / 2, a - a / 2):
				for x in range(-a / 2, a - a / 2):
					var lx := x * fx + a / 2
					var ly := y * fy + a / 2
					if lx < t or ly < t:
						cells.append(Vector2i(x, y))
		Shape.CROSS:
			var arm := rng.randi_range(8, 10)
			var hw := rng.randi_range(3, 4)
			for y in range(-arm, arm + 1):
				for x in range(-arm, arm + 1):
					if absi(x) <= hw or absi(y) <= hw:
						cells.append(Vector2i(x, y))
		Shape.PILLARS:
			for y in range(-7, 7):
				for x in range(-9, 9):
					var px := posmod(x + 9, 5)
					var py := posmod(y + 7, 5)
					var inner := absi(x) < 8 and absi(y) < 6
					if inner and px >= 3 and py >= 3 and x > -8 and y > -6:
						pillars.append(Vector2i(x, y))
					else:
						cells.append(Vector2i(x, y))
		Shape.RING:
			var R := rng.randf_range(8.0, 9.5)
			var ri := rng.randf_range(2.6, 3.4)
			for y in range(-10, 11):
				for x in range(-10, 11):
					var d := Vector2(x, y).length()
					if d <= ri:
						pillars.append(Vector2i(x, y))
					elif d <= R:
						cells.append(Vector2i(x, y))
		Shape.OCTAGON:
			var k := rng.randi_range(7, 8)
			for y in range(-k, k + 1):
				for x in range(-k, k + 1):
					if absi(x) + absi(y) <= int(k * 1.4):
						cells.append(Vector2i(x, y))
			for q in [Vector2i(-3, -3), Vector2i(3, 3), Vector2i(-3, 3), Vector2i(3, -3)]:
				if rng.randf() < 0.6:
					lows.append(q)
					lows.append(q + Vector2i(1, 0))
		Shape.BLOB:
			var m := {}
			for i in rng.randi_range(3, 4):
				var off := Vector2(rng.randf_range(-5, 5), rng.randf_range(-5, 5)) if i > 0 else Vector2.ZERO
				var tmp: Array[Vector2i] = []
				_disc(tmp, off, rng.randf_range(4.0, 6.0))
				for c in tmp:
					m[c] = true
			for c in m:
				cells.append(c)
	var r := 0.0
	for c in cells:
		r = maxf(r, Vector2(c).length())
	for c in pillars:
		r = maxf(r, Vector2(c).length())
	return {"cells": cells, "pillars": pillars, "lows": lows, "r": r}


## 보통 형태를 scale 배로 넓힌다. 넓힌 칸마다 원래 형태의 가장 가까운 칸 종류를 따른다.
## 기둥·엄폐물도 같이 커지고, 넓은 바닥에 엄폐물을 몇 무더기 더 흩어 놓는다.
func _big_shape(s: int, scale: float) -> Dictionary:
	var base := _shape(s)
	var kind := {}
	for c in base.cells:
		kind[c] = FLOOR
	for c in base.lows:
		kind[c] = LOW
	for c in base.pillars:
		kind[c] = PILLAR
	var cells: Array[Vector2i] = []
	var pillars: Array[Vector2i] = []
	var lows: Array[Vector2i] = []
	var R := ceili(base.r * scale) + 2
	for y in range(-R, R + 1):
		for x in range(-R, R + 1):
			var src := Vector2i(roundi(x / scale), roundi(y / scale))
			match kind.get(src, VOID):
				FLOOR:
					cells.append(Vector2i(x, y))
				LOW:
					cells.append(Vector2i(x, y))
					lows.append(Vector2i(x, y))
				PILLAR:
					pillars.append(Vector2i(x, y))
	# 추가 엄폐물: 넓은 바닥 곳곳에 3칸짜리 낮은 벽 (한가운데는 비워 둔다)
	var floor_set := {}
	for c in cells:
		floor_set[c] = true
	for c in lows:
		floor_set.erase(c)
	for i in int(cells.size() / 160):
		var at: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		if Vector2(at).length() < 5.0:
			continue
		var horiz := rng.randf() < 0.5
		var ok := true
		for k in range(-2, 5):
			for w in range(-2, 3):
				if not floor_set.has(at + (Vector2i(k, w) if horiz else Vector2i(w, k))):
					ok = false
		if not ok:
			continue
		for k in 3:
			var q := at + (Vector2i(k, 0) if horiz else Vector2i(0, k))
			lows.append(q)
			floor_set.erase(q)
	var r := 0.0
	for c in cells:
		r = maxf(r, Vector2(c).length())
	for c in pillars:
		r = maxf(r, Vector2(c).length())
	return {"cells": cells, "pillars": pillars, "lows": lows, "r": r}


func _disc(out: Array[Vector2i], o: Vector2, R: float) -> void:
	for y in range(floori(o.y - R), ceili(o.y + R) + 1):
		for x in range(floori(o.x - R), ceili(o.x + R) + 1):
			if Vector2(x, y).distance_to(o) <= R:
				out.append(Vector2i(x, y))


func _stamp(c: Vector2i, shp: Dictionary, shape_id: int, combat: bool) -> int:
	var id := rooms.size()
	var cells: Array[Vector2i] = []
	for o in shp.cells:
		var p: Vector2i = c + o
		if _in(p):
			grid[_idx(p)] = FLOOR
			room_of[_idx(p)] = id
			cells.append(p)
	for o in shp.pillars:
		var p: Vector2i = c + o
		if _in(p):
			grid[_idx(p)] = PILLAR
			room_of[_idx(p)] = id
	for o in shp.lows:
		var p: Vector2i = c + o
		if _in(p) and grid[_idx(p)] == FLOOR:
			grid[_idx(p)] = LOW
	rooms.append({
		"id": id, "center": c, "r": shp.r, "shape": shape_id, "cells": cells, "links": [],
		"combat": combat, "state": "idle", "gates_closed": false, "doors": [],
		"gate_nodes": [], "gate_shapes": [], "gate_body": null, "anchor": c, "difficulty": 0, "visited": not combat,
		"scale": 1.0, "wave": false,
	})
	return id


## 통로: 중간점 두 개를 흔들어 꺾이는 길을 만든다 (폭 3칸)
func _carve_corridor(a: Vector2i, b: Vector2i) -> void:
	var pts: Array[Vector2i] = [a]
	var d := b - a
	for k in [0.35, 0.7]:
		var m := a + Vector2i(roundi(d.x * k), roundi(d.y * k))
		m += Vector2i(rng.randi_range(-4, 4), rng.randi_range(-4, 4))
		pts.append(m)
	pts.append(b)
	for i in pts.size() - 1:
		var p := pts[i]
		var q := pts[i + 1]
		var horiz_first := rng.randf() < 0.5
		var corner := Vector2i(q.x, p.y) if horiz_first else Vector2i(p.x, q.y)
		_carve_line(p, corner)
		_carve_line(corner, q)


func _carve_line(p: Vector2i, q: Vector2i) -> void:
	var step := Vector2i(signi(q.x - p.x), signi(q.y - p.y))
	var c := p
	while true:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n := c + Vector2i(dx, dy)
				if _in(n) and grid[_idx(n)] == VOID:
					grid[_idx(n)] = FLOOR
		if c == q:
			break
		c += step


func _find_doors() -> void:
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			var i := _idx(c)
			if grid[i] != FLOOR or room_of[i] != -1:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if not _in(n):
					continue
				var r := room_of[_idx(n)]
				if r >= 0 and rooms[r].combat:
					gate_of[i] = r
					rooms[r].doors.append([c, d])
					break


## 시작 방에서의 연결 거리 = 난이도
func _assign_difficulty() -> void:
	var depth := {start_room: 0}
	var q := [start_room]
	while q.size() > 0:
		var cur: int = q.pop_front()
		for nb in rooms[cur].links:
			if not depth.has(nb):
				depth[nb] = depth[cur] + 1
				q.append(nb)
	for r in rooms:
		r.difficulty = depth.get(r.id, 3)


# ── 메시 · 충돌 ─────────────────────────────────────────

func build() -> void:
	_floor_shader = Shader.new()
	_floor_shader.code = FLOOR_SHADER
	# 바닥: 방마다 살짝 다른 색
	var tints := [Color(0.175, 0.175, 0.29), Color(0.19, 0.17, 0.3), Color(0.16, 0.18, 0.3), Color(0.185, 0.165, 0.27), Color(0.17, 0.19, 0.31)]
	var regions := {}
	for y in H:
		for x in W:
			var i := y * W + x
			if grid[i] == VOID:
				continue
			var rid := room_of[i]
			if not regions.has(rid):
				regions[rid] = []
			regions[rid].append(Vector2i(x, y))
	for rid in regions:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		Terrain.floor_cells(self, st, regions[rid])
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		var m := ShaderMaterial.new()
		m.shader = _floor_shader
		var tint: Color = Color(0.14, 0.14, 0.24) if rid == -1 else (Color(0.2, 0.2, 0.33) if rid == start_room else tints[rid % tints.size()])
		m.set_shader_parameter("base", tint)
		m.set_shader_parameter("line_col", Pal.FLOOR_LINE)
		mi.material_override = m
		mi.layers = 1 | MechDecals.RECEIVER
		add_child(mi)

	# 벽·기둥·엄폐물: 같은 종류·같은 높이 칸을 가로로 이어 상자 하나로
	var wall_prop_cells := WallProps.dress(self)
	ClaudeBgDress.plan(self, wall_prop_cells)          # 배경 첫 제작: 뒤 벽 3m W01 · 벽감 작업대·수납장 (--bg=old 면 없음)
	var solid := PackedByteArray()
	solid.resize(W * H)
	var base := PackedFloat32Array()
	base.resize(W * H)
	for y in H:
		for x in W:
			var i := y * W + x
			var g := grid[i]
			if g == PILLAR or g == LOW:
				solid[i] = g
				base[i] = cell_h(Vector2i(x, y))
			elif g == VOID and _near_floor(Vector2i(x, y)):
				solid[i] = 10 if wall_prop_cells.has(Vector2i(x, y)) else 9
				base[i] = hgt[i] if not hgt.is_empty() else 0.0
	var side_st := SurfaceTool.new()
	side_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top_st := SurfaceTool.new()
	top_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new()
	add_child(body)
	for y in H:
		var x := 0
		while x < W:
			var t := solid[y * W + x]
			var b0 := base[y * W + x]
			if t == 0:
				x += 1
				continue
			var x0 := x
			while x < W and solid[y * W + x] == t and absf(base[y * W + x] - b0) < 0.001:
				x += 1
			var h := WALL_H if t >= 9 else (PILLAR_H if t == PILLAR else LOW_H)
			var mn := Vector3((x0 - W * 0.5) * CELL, 0, (y - H * 0.5) * CELL)
			var mx := Vector3((x - W * 0.5) * CELL, b0 + h, (y - H * 0.5 + 1) * CELL)
			# 벽은 이웃 바닥(가장 높은 층) 위로 WALL_H 만큼 솟고, 아래는 분지 바닥까지 내려간다
			mn.y = -1.0 if t >= 9 else b0 - 0.4     # 기둥·엄폐물 밑동은 굴곡 비탈 아래까지 묻는다
			if t != 10:
				_box(side_st, top_st, mn, mx)
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			var top := mx.y + 3.0
			bs.size = Vector3(mx.x - mn.x, top - mn.y, CELL)
			cs.shape = bs
			cs.position = Vector3((mn.x + mx.x) * 0.5, (mn.y + top) * 0.5, (mn.z + mx.z) * 0.5)
			body.add_child(cs)
	var wm := ArrayMesh.new()
	side_st.commit(wm)
	top_st.commit(wm)
	wm.surface_set_material(0, Pal.lit(Color(0.1, 0.1, 0.19)))
	wm.surface_set_material(1, Pal.lit(Color(0.17, 0.16, 0.29)))
	var wall_mi := MeshInstance3D.new()
	wall_mi.mesh = wm
	wall_mi.layers = 1 | MechDecals.RECEIVER
	add_child(wall_mi)
	MechDecals.dress(self, wall_prop_cells)

	_build_gates()
	_build_minimap()
	ClaudeBgDress.apply(self)                          # 배경 첫 제작: F01 바닥 재질 · 낮은 W01 블록 벽


func _near_floor(c: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n := c + Vector2i(dx, dy)
			if _in(n) and grid[_idx(n)] != VOID:
				return true
	return false


func _box(side: SurfaceTool, top: SurfaceTool, mn: Vector3, mx: Vector3) -> void:
	var v := [
		Vector3(mn.x, mn.y, mn.z), Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mn.y, mx.z), Vector3(mn.x, mn.y, mx.z),
		Vector3(mn.x, mx.y, mn.z), Vector3(mx.x, mx.y, mn.z), Vector3(mx.x, mx.y, mx.z), Vector3(mn.x, mx.y, mx.z),
	]
	_quad(top, v[4], v[5], v[6], v[7], Vector3.UP)
	_quad(side, v[3], v[2], v[6], v[7], Vector3.BACK)     # +Z
	_quad(side, v[1], v[0], v[4], v[5], Vector3.FORWARD)  # -Z
	_quad(side, v[2], v[1], v[5], v[6], Vector3.RIGHT)
	_quad(side, v[0], v[3], v[7], v[4], Vector3.LEFT)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	st.set_normal(n)
	# Godot 는 시계 방향이 앞면: cross(b-a, c-a) 가 법선 반대쪽이어야 한다
	if (b - a).cross(c - a).dot(n) < 0.0:
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)
	else:
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
		st.add_vertex(a); st.add_vertex(d); st.add_vertex(c)


# ── 출입구 차단막 ───────────────────────────────────────

func _build_gates() -> void:
	_gate_mat = StandardMaterial3D.new()
	_gate_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_gate_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_gate_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_gate_mat.albedo_color = Color(1.0, 0.18, 0.35, 0.5)
	_gate_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for r in rooms:
		if not r.combat:
			continue
		var body := StaticBody3D.new()
		add_child(body)
		r.gate_body = body
		for door in r.doors:
			var c: Vector2i = door[0]
			var d: Vector2i = door[1]
			var edge := world_of(c) + Vector3(d.x, 0, d.y) * CELL * 0.5
			var size := Vector3(0.12, 1.4, CELL) if d.x != 0 else Vector3(CELL, 1.4, 0.12)
			var bm := BoxMesh.new()
			bm.size = size
			var mi := MeshInstance3D.new()
			mi.mesh = bm
			mi.material_override = _gate_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = edge + Vector3(0, 0.7, 0)
			mi.scale = Vector3(1, 0.001, 1)
			mi.visible = false
			add_child(mi)
			r.gate_nodes.append(mi)
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(size.x + 0.1, 3.0, size.z + 0.1)
			cs.shape = bs
			cs.position = edge + Vector3(0, 1.5, 0)
			cs.disabled = true
			body.add_child(cs)
			r.gate_shapes.append(cs)


func close_gates(id: int) -> void:
	var r: Dictionary = rooms[id]
	r.gates_closed = true
	for cs in r.gate_shapes:
		(cs as CollisionShape3D).set_deferred("disabled", false)
	for mi in r.gate_nodes:
		var m := mi as MeshInstance3D
		m.visible = true
		var tw := m.create_tween()
		tw.tween_property(m, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for door in r.doors:
		if randf() < 0.3:
			FX.sparks(world_of(door[0]) + Vector3(0, 0.5, 0), 4, [Color("ff3a6a"), Color.WHITE], 4.0, 0.3, -8.0, 0.06)
	_repaint_room(id)


func open_gates(id: int) -> void:
	var r: Dictionary = rooms[id]
	r.gates_closed = false
	for cs in r.gate_shapes:
		(cs as CollisionShape3D).set_deferred("disabled", true)
	for mi in r.gate_nodes:
		var m := mi as MeshInstance3D
		var tw := m.create_tween()
		tw.tween_property(m, "scale", Vector3(1, 0.001, 1), 0.3).set_ease(Tween.EASE_IN)
		tw.tween_callback(func(): m.visible = false)
		FX.flash(m.global_position, Color("ff6a8a"), 0.5, 0.1)
	_repaint_room(id)


func _process(dt: float) -> void:
	_t += dt
	if _gate_mat:
		_gate_mat.albedo_color.a = 0.38 + sin(_t * 9.0) * 0.12 + randf() * 0.06


## 전투방 안의 무작위 바닥 위치 (벽·플레이어와 떨어진 곳)
## max_dist 를 주면 avoid 에서 그 안쪽 자리를 고른다 (넓은 방에서 적이 너무 멀리 나오지 않게)
func random_spot(id: int, avoid: Vector3, min_dist: float, max_dist := INF) -> Vector3:
	var cells: Array = rooms[id].cells
	var best := world_of(rooms[id].center)
	for tries in (120 if max_dist < INF else 60):
		var c: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		var ok := true
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if is_blocked_cell(c + Vector2i(dx, dy)) or not _flat_near(c, c + Vector2i(dx, dy)):
					ok = false
		if not ok:
			continue
		var p := world_of(c)
		var dd := Vector2(p.x - avoid.x, p.z - avoid.z).length()
		if dd >= min_dist and dd <= max_dist:
			return p
		best = p
	return best


## 벽에 붙은 바닥 자리를 고른다 (구석을 우선). 가운데 칸 둘레 3×3 칸이 모두 비어 있어야 한다 (포탑 해치 크기).
## 출입구 근처, 이미 쓴 자리(taken) 근처, avoid 에서 min_dist 안쪽은 뺀다.
## 돌려주는 yaw 는 벽 반대쪽(방 안쪽)을 정면(-Z)으로 보는 방향 [0, TAU). 자리가 없으면 빈 딕셔너리.
func wall_spot(id: int, avoid: Vector3, min_dist: float, taken: Array) -> Dictionary:
	var corners: Array = []
	var walls: Array = []
	var doors: Array = rooms[id].doors
	for c in rooms[id].cells:
		var cell: Vector2i = c
		var ok := true
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n := cell + Vector2i(dx, dy)
				if cell_type(n) != FLOOR or gate_of[_idx(n)] >= 0 or not _flat_near(cell, n, 0.05):
					ok = false
		if not ok:
			continue
		var p := world_of(cell)
		if Vector2(p.x - avoid.x, p.z - avoid.z).length() < min_dist:
			continue
		for d in doors:
			if world_of(d[0]).distance_to(p) < 3.5:
				ok = false
		for q in taken:
			if (q as Vector3).distance_to(p) < 3.2:
				ok = false
		if not ok:
			continue
		# 3×3 바로 바깥이 막힌 쪽이 벽. 그 반대쪽이 정면.
		var away := Vector3.ZERO
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if cell_type(cell + d * 2) != FLOOR:
				away -= Vector3(d.x, 0, d.y)
		if away.length() < 0.5:
			continue   # 벽이 없거나 양쪽이 막힌 좁은 곳
		var spot := {"pos": p, "yaw": fposmod(atan2(away.x, away.z) + PI, TAU)}
		if away.length() > 1.2:
			corners.append(spot)
		else:
			walls.append(spot)
	if corners.size() > 0 and (walls.is_empty() or rng.randf() < 0.6):
		return corners[rng.randi_range(0, corners.size() - 1)]
	if walls.size() > 0:
		return walls[rng.randi_range(0, walls.size() - 1)]
	return {}


## 두 칸의 높이 차가 tol 이하인가 (소환·해치 자리가 비탈에 걸치지 않게)
func _flat_near(a: Vector2i, b: Vector2i, tol := 0.3) -> bool:
	return absf(cell_h(a) - cell_h(b)) <= tol


func room_center_world(id: int) -> Vector3:
	return world_of(rooms[id].anchor)


## 방마다 벽·출입구에서 가장 먼 안쪽 칸 (방의 기준점)
func _compute_anchors() -> void:
	for r in rooms:
		var best: Vector2i = r.cells[0]
		var bs := -1e9
		for c in r.cells:
			if is_blocked_cell(c):
				continue
			var clear := 5.0
			for dy in range(-4, 5):
				for dx in range(-4, 5):
					var n: Vector2i = c + Vector2i(dx, dy)
					if not _in(n) or grid[_idx(n)] != FLOOR or room_of[_idx(n)] != r.id:
						clear = minf(clear, Vector2(dx, dy).length())
			var door_d := 20.0
			for door in r.doors:
				door_d = minf(door_d, Vector2(c - door[0]).length())
			var score: float = clear * 2.0 + minf(door_d, 8.0) * 0.5 - Vector2(c - r.center).length() * 0.15
			# 기준점(출발·귀환 지점)은 바닥층의 평평한 곳에 둔다
			if absf(cell_h(c)) > 0.05 or (not hgt.is_empty() and smooth[_idx(c)] >= 0):
				score -= 6.0
			if score > bs:
				bs = score
				best = c
		r.anchor = best


# ── 경로 (자동 플레이용) ────────────────────────────────

func find_path(from: Vector3, to: Vector3) -> Array[Vector3]:
	var s := cell_of(from)
	var g := cell_of(to)
	var out: Array[Vector3] = []
	if not _in(s) or not _in(g):
		return out
	var prev := PackedInt32Array()
	prev.resize(W * H)
	prev.fill(-2)
	var q := PackedInt32Array([_idx(s)])
	prev[_idx(s)] = -1
	var head := 0
	var gi := _idx(g)
	while head < q.size():
		var i := q[head]
		head += 1
		if i == gi:
			break
		var cx := i % W
		var cy := i / W
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = Vector2i(cx, cy) + d
			if not _in(n):
				continue
			var ni := _idx(n)
			if prev[ni] != -2 or is_blocked_cell(n):
				continue
			prev[ni] = i
			q.append(ni)
	if prev[gi] == -2:
		return out
	var cur := gi
	while cur != -1:
		out.push_front(world_of(Vector2i(cur % W, cur / W)))
		cur = prev[cur]
	return out


# ── 미니맵 ──────────────────────────────────────────────

func _build_minimap() -> void:
	minimap_img = Image.create(W, H, false, Image.FORMAT_RGBA8)
	minimap_img.fill(Color(0, 0, 0, 0))
	minimap_tex = ImageTexture.create_from_image(minimap_img)


func _cell_color(i: int) -> Color:
	var g := grid[i]
	if g == VOID:
		return Color(0, 0, 0, 0)
	if g != FLOOR:
		return Color(0.12, 0.12, 0.2, 0.9)
	var r := room_of[i]
	if gate_of[i] >= 0 and rooms[gate_of[i]].gates_closed:
		return Color(1.0, 0.25, 0.4, 1.0)
	return _cell_color_flat(i, r)


func _cell_color_flat(i: int, r: int) -> Color:
	if r < 0:
		return Color(0.32, 0.32, 0.5, 0.9)
	var room: Dictionary = rooms[r]
	if not room.combat:
		return Color(0.35, 0.6, 0.75, 0.95)
	match room.state:
		"active": return Color(0.85, 0.25, 0.4, 0.95)
		"cleared": return Color(0.3, 0.5, 0.8, 0.95)
	return Color(0.5, 0.36, 0.52, 0.95)


func update_discovery(p: Vector3, dt: float) -> void:
	_disc_t -= dt
	if _disc_t > 0.0:
		return
	_disc_t = 0.2
	var c := cell_of(p)
	var R := 13
	var changed := false
	for dy in range(-R, R + 1):
		for dx in range(-R, R + 1):
			if dx * dx + dy * dy > R * R:
				continue
			var n := c + Vector2i(dx, dy)
			if not _in(n):
				continue
			var i := _idx(n)
			if discovered[i] == 0:
				discovered[i] = 1
				minimap_img.set_pixel(n.x, n.y, _cell_color(i))
				changed = true
	if changed:
		minimap_tex.update(minimap_img)


func _repaint_room(id: int) -> void:
	if minimap_img == null:
		return
	for c in rooms[id].cells:
		var i := _idx(c)
		if discovered[i]:
			minimap_img.set_pixel(c.x, c.y, _cell_color(i))
	for door in rooms[id].doors:
		var c: Vector2i = door[0]
		if discovered[_idx(c)]:
			minimap_img.set_pixel(c.x, c.y, _cell_color(_idx(c)))
	minimap_tex.update(minimap_img)


const FLOOR_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 base : source_color;
uniform vec3 line_col : source_color;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float grid(vec2 p, float period, float w, out vec2 cell) {
	vec2 q = p / period;
	cell = floor(q);
	vec2 g = abs(fract(q) - 0.5);
	float d = (0.5 - max(g.x, g.y)) * period;
	return 1.0 - smoothstep(w, w + 0.035, d);
}
mat2 rot(float a) { return mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))); }
void fragment() {
	vec2 p = wpos.xz;
	vec2 ca; vec2 cb;
	float la = grid(rot(0.21) * p + vec2(3.0, 1.0), 9.0, 0.022, ca);
	float lb = grid(rot(0.86) * p + vec2(1.3, 5.2), 12.5, 0.018, cb);
	float mb = step(0.62, hash(ca + 7.0));
	float lines = max(la, lb * mb);
	float n = noise(p * 0.12) * 0.6 + noise(p * 0.5) * 0.25 + noise(p * 2.3) * 0.15;
	float plate = hash(ca) * 0.06;
	vec3 col = base * (0.86 + n * 0.28 + plate);
	col = mix(col, line_col, lines * 0.85);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.15;
}
"""
