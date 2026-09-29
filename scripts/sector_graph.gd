class_name SectorGraph
extends RefCounted
## 섹터 지도 생성: 출발 → 단계 1~LEVELS (단계마다 방 2~3개) → 보스.
## 방은 다음 단계의 방 1~2개로 이어지고, 연결선끼리 교차하지 않는다.
## 노드는 헥스 격자(열 = 단계, 홀수 열은 반 칸 내려감) 위에 놓인다.

enum Kind { START, COMBAT, ELITE, REST, BOSS }
const KIND_NAMES := ["출발", "전투", "정예", "정비", "보스"]
const KIND_COLORS := [Color("8ab8ff"), Color("ff5a7a"), Color("ffb040"), Color("5cf0a0"), Color("ff3ad0")]
const LEVELS := 6
const ROW_MIN := -2
const ROW_MAX := 2


## 노드 딕셔너리: id, level, row, kind, links(다음 단계 id 목록), seed, shape, difficulty, coins
static func build(seed_value: int, sector: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var nodes: Array = []
	var by_level: Array = []
	# 출발
	by_level.append([_add(nodes, 0, 0, Kind.START, rng)])
	# 일반 단계
	for lv in range(1, LEVELS + 1):
		var n := rng.randi_range(2, 3)
		# 가운데 쪽 줄을 조금 더 자주 고른다
		var keyed: Array = []
		for r in range(ROW_MIN, ROW_MAX + 1):
			keyed.append([absi(r) + rng.randf() * 2.5, r])
		keyed.sort_custom(func(a, b): return a[0] < b[0])
		var rows: Array = []
		for k in n:
			rows.append(keyed[k][1])
		rows.sort()
		var ids: Array = []
		for r in rows:
			ids.append(_add(nodes, lv, r, Kind.COMBAT, rng))
		by_level.append(ids)
	# 보스
	by_level.append([_add(nodes, LEVELS + 1, 0, Kind.BOSS, rng)])
	for lv in by_level.size() - 1:
		_link(nodes, by_level[lv], by_level[lv + 1], rng)
	_assign_kinds(nodes, by_level, rng)
	for nd in nodes:
		var d := 1 + int((nd.level - 1) * 0.75) + sector * 2
		if nd.kind == Kind.ELITE:
			d += 2
		nd.difficulty = clampi(d, 1, 6)
		nd.coins = 0
		if nd.kind == Kind.COMBAT:
			nd.coins = 20 + nd.level * 5
		elif nd.kind == Kind.ELITE:
			nd.coins = 50 + nd.level * 10
	return nodes


static func _add(nodes: Array, level: int, row: int, kind: int, rng: RandomNumberGenerator) -> int:
	var id := nodes.size()
	nodes.append({
		"id": id, "level": level, "row": row, "kind": kind, "links": [],
		"seed": rng.randi(), "shape": rng.randi_range(0, ArenaMap.Shape.size() - 1),
		"difficulty": 1, "coins": 0,
	})
	return id


## 두 단계 사이 연결. 위아래 순서를 지키는 비례 매핑에 가끔 이웃 한 칸을 더 잇는다.
static func _link(nodes: Array, a: Array, b: Array, rng: RandomNumberGenerator) -> void:
	var n := a.size()
	var m := b.size()
	var edges: Array = []   # [i, j] (a·b 안의 순번)
	for i in n:
		var j := roundi(float(i) * (m - 1) / maxf(n - 1, 1)) if n > 1 else m / 2
		_try_edge(edges, i, j)
		if rng.randf() < 0.5:
			var k := j + (1 if rng.randf() < 0.5 else -1)
			if k >= 0 and k < m:
				_try_edge(edges, i, k)
	# 들어오는 길이 없는 칸은 가장 가까운 순번에서 잇는다
	for j in m:
		var has := false
		for e in edges:
			if e[1] == j:
				has = true
		if not has:
			var i := roundi(float(j) * (n - 1) / maxf(m - 1, 1)) if m > 1 else n / 2
			if not _try_edge(edges, i, j):
				# 교차를 피할 수 없으면 양 끝 규칙: 맨 위는 맨 위, 맨 아래는 맨 아래와 잇는다
				edges.append([0 if j == 0 else n - 1, j])
	for e in edges:
		var from: Dictionary = nodes[a[e[0]]]
		var to_id: int = b[e[1]]
		if not from.links.has(to_id):
			from.links.append(to_id)


static func _try_edge(edges: Array, i: int, j: int) -> bool:
	for e in edges:
		if e[0] == i and e[1] == j:
			return true
		if (e[0] < i and e[1] > j) or (e[0] > i and e[1] < j):
			return false
	edges.append([i, j])
	return true


## 1단계는 전투만, 중간 단계는 정예·정비가 섞이고, 보스 앞 단계에는 정비가 적어도 하나 있다.
static func _assign_kinds(nodes: Array, by_level: Array, rng: RandomNumberGenerator) -> void:
	var elites := 0
	for lv in range(2, LEVELS + 1):
		var ids: Array = by_level[lv]
		for id in ids:
			var roll := rng.randf()
			var k := Kind.COMBAT
			if lv == LEVELS:
				k = Kind.REST if roll < 0.5 else Kind.COMBAT
			elif lv >= 3 and roll < 0.22:
				k = Kind.ELITE
			elif roll < 0.38:
				k = Kind.REST
			nodes[id].kind = k
			if k == Kind.ELITE:
				elites += 1
		# 한 단계가 모두 정비면 하나는 전투로 (보스 앞 단계 제외)
		if lv < LEVELS:
			var all_rest := true
			for id in ids:
				if nodes[id].kind != Kind.REST:
					all_rest = false
			if all_rest:
				nodes[ids[rng.randi_range(0, ids.size() - 1)]].kind = Kind.COMBAT
	var last: Array = by_level[LEVELS]
	var has_rest := false
	for id in last:
		if nodes[id].kind == Kind.REST:
			has_rest = true
	if not has_rest:
		nodes[last[rng.randi_range(0, last.size() - 1)]].kind = Kind.REST
	# 정예가 하나도 없으면 3~5단계 중 한 칸을 정예로
	if elites == 0:
		var pool: Array = []
		for lv in range(3, LEVELS):
			for id in by_level[lv]:
				if nodes[id].kind == Kind.COMBAT:
					pool.append(id)
		if pool.size() > 0:
			nodes[pool[rng.randi_range(0, pool.size() - 1)]].kind = Kind.ELITE


## 헥스 격자 위 노드 중심 (반지름 R, 평평한 윗변 헥스). 열 = 단계, 홀수 열은 반 칸 내려간다.
static func hex_center(level: int, row: int, R: float) -> Vector2:
	return Vector2(level * 1.5 * R, (row + (level % 2) * 0.5) * sqrt(3.0) * R)


static func hex_points(c: Vector2, R: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i)
		pts.append(c + Vector2(cos(a), sin(a)) * R)
	return pts
