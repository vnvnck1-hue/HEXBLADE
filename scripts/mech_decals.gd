class_name MechDecals
extends RefCounted
## 배경용 메카닉 데칼: 사선 컷 타일 · 육각 벌집 · 쉐브론 · 경고 사선 · 테크 라인 · 각진 숫자.
## 텍스처는 도형 목록을 스캔라인(짝홀 규칙)으로 칠해 런타임에 한 번 만들고 공유한다.
## Decal 은 RECEIVER 레이어(바닥·벽 메시)에만 찍혀 캐릭터·적·탄에는 묻지 않는다.

const RECEIVER := 1 << 19
const PX := 40        # 단위당 픽셀
const SS := 2         # 초표본 배율 (축소하며 가장자리 안티에일리어싱)
const PAD := 0.3      # 텍스처 가장자리 여백(단위). 클램프 번짐 방지

## 칠 색: [modulate, albedo_mix, emission]
## 바탕 데칼은 아주 옅게: 네온 순차 점등이 눈에 띄도록 도료는 바닥에 거의 묻혀 있어야 한다
const LIGHT := [Color(0.5, 0.5, 0.74), 0.11, 0.0]
const DARK := [Color(0.05, 0.05, 0.1), 0.2, 0.0]
const AMBER := [Color(0.8, 0.6, 0.32), 0.12, 0.0]

## 네온 순차 점등. groups = 차례로 켜질 부품 번호 묶음(도형 정의 순서)
## rate = 초당 단계, rest = 한 바퀴 뒤 꺼져 있는 단계 수, trail = 뒤따르는 잔광 세기
const NEON_CYAN := Color(0.3, 0.9, 1.0)
const NEON_AMBER := Color(1.0, 0.62, 0.22)
const ANIM := {
	"chevron_col": {"groups": [[3], [2], [1], [0]], "rate": 6.0, "rest": 3, "trail": [1.0, 0.3], "col": NEON_AMBER},
	"chev_row": {"groups": [[0], [1], [2]], "rate": 5.0, "rest": 3, "trail": [1.0, 0.3], "col": NEON_CYAN},
	"hazard": {"groups": [[0], [1], [2], [3], [4], [5], [6], [7], [8]], "rate": 12.0, "rest": 6, "trail": [1.0, 0.5, 0.2], "col": NEON_AMBER},
	"bead_rail": {"groups": [[1], [2], [3], [4], [5], [6], [7]], "rate": 8.0, "rest": 5, "trail": [1.0, 0.4, 0.15], "col": NEON_CYAN},
	"dots": {"groups": [[0], [1], [2]], "rate": 2.5, "rest": 2, "trail": [1.0], "col": NEON_CYAN},
	"tri_row": {"groups": [[0], [1], [2], [3], [4], [5]], "rate": 8.0, "rest": 4, "trail": [1.0, 0.4, 0.15], "col": NEON_CYAN},
	"cut_tiles": {"groups": [[0, 1], [2, 3], [4, 5], [6, 7]], "rate": 4.0, "rest": 3, "trail": [1.0, 0.25], "col": NEON_CYAN},
	"hex_cluster": {"groups": [[0], [6], [2], [8], [4], [5], [1], [7], [3]], "rate": 5.0, "rest": 3, "trail": [1.0, 0.35], "col": NEON_CYAN},
	"arrow_bar": {"groups": [[1], [2], [3], [4]], "rate": 6.0, "rest": 3, "trail": [1.0, 0.3], "col": NEON_CYAN},
}
const NEON_ENERGY := 1.6
const NEON_CHANCE := 0.6      # 반복 무늬 중 네온이 달리는 비율 (출입구 쉐브론은 항상)

const FLOOR_BIG := ["cross_bracket", "ring_target", "hex_cluster", "hud_corner", "bent_strip", "slant_pair", "cut_tiles", "tri_row", "vent", "num"]
const FLOOR_LINE := ["tech_bar", "arrow_bar", "bead_rail", "hazard", "dots", "chev_row"]
const WALL_TOP := ["tech_bar", "bead_rail", "hazard", "dots", "chev_row", "arrow_bar"]
const WALL_FACE := ["hazard", "num", "vent", "arrow_bar", "cut_tiles", "chev_row"]
const NUMBERS := ["01", "02", "04", "07", "13", "26", "38", "59", "80"]

static var _tex: Dictionary = {}     # 이름 → [알베도, 크기(단위, 여백 포함), 발광]
static var _frames: Dictionary = {}  # 이름 → 순차 점등 발광 프레임 목록


# ── 배치 ────────────────────────────────────────────────

## ArenaMap.build() 에서 호출. skip = 벽 프랍이 차지한 벽 칸
static func dress(map: ArenaMap, skip: Dictionary) -> Node3D:
	var kit := Node3D.new()
	kit.name = "MechDecals"
	map.add_child(kit)
	var anim := MechDecalAnim.new()
	anim.name = "Neon"
	kit.add_child(anim)
	var rng := RandomNumberGenerator.new()
	rng.seed = map.rng.seed ^ 0x5EED
	var used: Dictionary = {}          # 바닥 칸 점유
	var regions: Dictionary = {}
	for y in ArenaMap.H:
		for x in ArenaMap.W:
			var c := Vector2i(x, y)
			if map.grid[map._idx(c)] == ArenaMap.FLOOR:
				var rid: int = map.room_of[map._idx(c)]
				if not regions.has(rid):
					regions[rid] = []
				regions[rid].append(c)
	# 출입구: 방 안쪽을 가리키는 쉐브론
	for r in map.rooms:
		for door in r.doors:
			_door(map, kit, door[0], door[1], used)
	for rid in regions:
		var cells: Array = regions[rid]
		var corridor: bool = rid == -1
		var big := 0 if corridor else clampi(cells.size() / 26, 3, 14)
		var lines := clampi(cells.size() / (20 if corridor else 34), 2, 16)
		var label := "" if corridor else "%02d" % (rid + 1)
		_scatter(map, kit, rng, cells, used, FLOOR_BIG, big, 0.2, 0.34, label)
		_scatter(map, kit, rng, cells, used, FLOOR_LINE, lines, 0.14, 0.22)
	_wall_tops(map, kit, rng, skip)
	_wall_faces(map, kit, rng, skip)
	return kit


static func _scatter(map: ArenaMap, kit: Node3D, rng: RandomNumberGenerator, cells: Array, used: Dictionary,
		kinds: Array, want: int, s0: float, s1: float, label := "") -> void:
	var placed := 0
	for attempt in want * 30:
		if placed >= want:
			return
		var kind: String = kinds[rng.randi() % kinds.size()]
		# 바닥 숫자 = 방 번호, 방마다 하나
		if kind == "num":
			if label == "":
				continue
		var tex := texture("num:" + label) if kind == "num" else _kind_tex(kind, rng)
		var unit := rng.randf_range(s0, s1)
		var sz: Vector2 = tex[1] * unit
		var turn := 0 if kind == "num" else rng.randi() % 4     # 숫자는 카메라 쪽으로 똑바로
		var foot := Vector2(sz.y, sz.x) if turn % 2 == 1 else sz
		var c: Vector2i = cells[rng.randi() % cells.size()]
		var center := map.world_of(c)
		var cover := _cover(map, center, foot, 0.35)
		if cover.is_empty():
			continue
		var ok := true
		var h0 := center.y
		for cc in cover:
			if used.has(cc) or map.grid[map._idx(cc)] != ArenaMap.FLOOR or map.gate_of[map._idx(cc)] >= 0:
				ok = false
				break
			h0 = maxf(h0, map.cell_h(cc))
		if not ok:
			continue
		for cc in cover:
			used[cc] = true
		var paint: Array = AMBER if kind == "hazard" else (DARK if rng.randf() < 0.35 else LIGHT)
		var d := _decal(tex, sz, paint, 1.4)
		d.position = Vector3(center.x, h0, center.z)
		d.rotation.y = turn * PI * 0.5
		d.set_meta("slot", "floor")
		d.set_meta("kind", kind)
		kit.add_child(d)
		if rng.randf() < NEON_CHANCE:
			_neon(kit, d, kind, rng)
		placed += 1
		if kind == "num":
			label = ""


## foot(월드 m) 사각형이 덮는 칸 목록. 맵 밖이면 빈 배열
static func _cover(map: ArenaMap, center: Vector3, foot: Vector2, margin: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var a := map.cell_of(center - Vector3(foot.x * 0.5 + margin, 0, foot.y * 0.5 + margin))
	var b := map.cell_of(center + Vector3(foot.x * 0.5 + margin, 0, foot.y * 0.5 + margin))
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			var c := Vector2i(x, y)
			if not map._in(c):
				return []
			out.append(c)
	return out


static func _door(map: ArenaMap, kit: Node3D, c: Vector2i, d: Vector2i, used: Dictionary) -> void:
	# 문 칸에서 방 안쪽으로 두 칸 들어간 자리
	var inside := c + d * 2
	if not map._in(inside) or map.grid[map._idx(inside)] != ArenaMap.FLOOR or used.has(inside):
		return
	var tex := _kind_tex("chevron_col", null)
	var sz: Vector2 = tex[1] * 0.2
	var d3 := _decal(tex, sz, AMBER, 1.4)
	var at := map.world_of(inside)
	d3.position = at
	# 쉐브론은 텍스처 위(-Z)를 가리킨다 → 방 안쪽(d)으로 돌린다
	d3.rotation.y = atan2(-float(d.x), -float(d.y))
	d3.set_meta("slot", "door")
	d3.set_meta("kind", "chevron_col")
	kit.add_child(d3)
	_neon(kit, d3, "chevron_col", null)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			used[inside + Vector2i(dx, dy)] = true


static func _is_edge_wall(map: ArenaMap, c: Vector2i, skip: Dictionary) -> bool:
	if not map._in(c) or map.grid[map._idx(c)] != ArenaMap.VOID or skip.has(c):
		return false
	for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var q: Vector2i = c + n
		if map._in(q) and map.grid[map._idx(q)] != ArenaMap.VOID:
			return true
	return false


## 벽 윗면: 곧은 벽 구간을 따라 가늘고 긴 띠
static func _wall_tops(map: ArenaMap, kit: Node3D, rng: RandomNumberGenerator, skip: Dictionary) -> void:
	var taken: Dictionary = {}
	var cands: Array[Vector2i] = []
	for y in ArenaMap.H:
		for x in ArenaMap.W:
			var c := Vector2i(x, y)
			if _is_edge_wall(map, c, skip):
				cands.append(c)
	if cands.is_empty():
		return
	var want := clampi(cands.size() / 16, 2, 40)
	var placed := 0
	for attempt in want * 20:
		if placed >= want:
			break
		var c: Vector2i = cands[rng.randi() % cands.size()]
		var axis := Vector2i(1, 0) if rng.randf() < 0.5 else Vector2i(0, 1)
		var kind: String = WALL_TOP[rng.randi() % WALL_TOP.size()]
		var tex := _kind_tex(kind, rng)
		var unit: float = 0.8 / tex[1].y          # 띠 폭 = 벽 한 칸 안쪽
		var len_m: float = tex[1].x * unit
		var n := int(ceil(len_m)) + 1
		var base := map.hgt[map._idx(c)]
		var ok := true
		for k in n:
			var q := c + axis * k
			if not _is_edge_wall(map, q, skip) or taken.has(q) or absf(map.hgt[map._idx(q)] - base) > 0.01:
				ok = false
				break
		if not ok:
			continue
		for k in range(-1, n + 1):
			taken[c + axis * k] = true
		var a := map.world_of(c)
		var b := map.world_of(c + axis * (n - 1))
		var paint: Array = AMBER if kind == "hazard" else LIGHT
		var d := _decal(tex, tex[1] * unit, paint, 0.5)
		d.position = Vector3((a.x + b.x) * 0.5, base + ArenaMap.WALL_H, (a.z + b.z) * 0.5)
		d.rotation.y = 0.0 if axis.x != 0 else PI * 0.5
		if rng.randf() < 0.5:
			d.rotation.y += PI
		d.set_meta("slot", "wall_top")
		d.set_meta("kind", kind)
		kit.add_child(d)
		if rng.randf() < 0.75:
			_neon(kit, d, kind, rng)
		placed += 1


## 벽 정면: 카메라를 향한 뒷벽(+Z 면)에 표식
static func _wall_faces(map: ArenaMap, kit: Node3D, rng: RandomNumberGenerator, skip: Dictionary) -> void:
	var cands: Array[Vector2i] = []
	for y in ArenaMap.H:
		for x in ArenaMap.W:
			var c := Vector2i(x, y)
			var back := c + Vector2i(0, -1)
			if map.grid[map._idx(c)] == ArenaMap.FLOOR and map._in(back) and map.grid[map._idx(back)] == ArenaMap.VOID and not skip.has(back):
				cands.append(c)
	if cands.is_empty():
		return
	var taken: Dictionary = {}
	var want := clampi(cands.size() / 12, 2, 30)
	var placed := 0
	for attempt in want * 20:
		if placed >= want:
			break
		var c: Vector2i = cands[rng.randi() % cands.size()]
		var kind: String = WALL_FACE[rng.randi() % WALL_FACE.size()]
		var rid: int = map.room_of[map._idx(c)]
		var tex := texture("num:%02d" % (rid + 1)) if kind == "num" and rid >= 0 else _kind_tex(kind, rng)
		var tall := 0.5
		var unit: float = tall / tex[1].y
		var w: float = tex[1].x * unit
		var n := int(ceil(w))
		var x0 := c.x - n / 2
		var h0 := map.cell_h(c)
		var ok := true
		for k in range(-1, n + 1):
			var q := Vector2i(x0 + k, c.y)
			if taken.has(q) or not cands.has(q) or absf(map.cell_h(q) - h0) > 0.01:
				ok = false
				break
		if not ok:
			continue
		for k in range(-2, n + 2):
			taken[Vector2i(x0 + k, c.y)] = true
		var face_z := map.world_of(c).z - ArenaMap.CELL * 0.5
		var paint: Array = AMBER if kind == "hazard" else (DARK if rng.randf() < 0.45 else LIGHT)
		var d := _decal(tex, tex[1] * unit, paint, 0.5)
		d.position = Vector3(map.world_of(Vector2i(x0, c.y)).x + (n - 1) * 0.5 * ArenaMap.CELL, h0 + 0.42, face_z)
		d.rotation.x = PI * 0.5      # 투사 방향 -Y → 벽 안쪽(-Z), 텍스처 위 → 월드 위
		d.set_meta("slot", "wall_face")
		d.set_meta("kind", kind)
		kit.add_child(d)
		placed += 1


## 바탕 데칼 위에 같은 크기의 발광 전용 데칼을 겹치고 MechDecalAnim 이 프레임을 넘긴다
static func _neon(kit: Node3D, base: Decal, kind: String, rng: RandomNumberGenerator) -> void:
	if not ANIM.has(kind):
		return
	var spec: Dictionary = ANIM[kind]
	var o := Decal.new()
	o.size = base.size
	o.albedo_mix = 0.0
	o.modulate = spec.col
	o.cull_mask = RECEIVER
	o.normal_fade = base.normal_fade
	o.upper_fade = base.upper_fade
	o.lower_fade = base.lower_fade
	o.emission_energy = 0.0
	base.add_child(o)
	var fr := frames(kind)
	o.texture_emission = fr[0]
	var off := rng.randf() * 100.0 if rng else randf() * 100.0
	(kit.get_node("Neon") as MechDecalAnim).add(o, fr, spec.rate, spec.rest, off, NEON_ENERGY)


static func _decal(tex: Array, size: Vector2, paint: Array, depth: float) -> Decal:
	var d := Decal.new()
	d.texture_albedo = tex[0]
	d.size = Vector3(size.x, depth, size.y)
	d.modulate = paint[0]
	d.albedo_mix = paint[1]
	if paint[2] > 0.0:
		d.texture_emission = tex[2]
		d.emission_energy = paint[2]
	d.cull_mask = RECEIVER
	d.normal_fade = 0.35
	d.upper_fade = 0.05
	d.lower_fade = 0.05
	return d


# ── 텍스처 ──────────────────────────────────────────────

static func _kind_tex(kind: String, rng: RandomNumberGenerator) -> Array:
	if kind == "num":
		var s: String = NUMBERS[rng.randi() % NUMBERS.size()] if rng else "07"
		return texture("num:" + s)
	return texture(kind)


## [ImageTexture, 크기(단위)] — 크기는 여백 포함. 데칼 크기 = 크기 × (m/단위)
static func texture(name: String) -> Array:
	if not _tex.has(name):
		var sh := _shape(name)
		var img := _raster(sh[0], sh[1])
		# 발광 텍스처는 바탕이 검어야 한다 (알베도는 RGB 가 흰색 그대로라 사각형 전체가 빛난다)
		var glow := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
		glow.fill(Color.BLACK)
		glow.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
		img.generate_mipmaps()
		glow.generate_mipmaps()
		_tex[name] = [ImageTexture.create_from_image(img), sh[0] + Vector2(PAD, PAD) * 2.0, ImageTexture.create_from_image(glow)]
	return _tex[name]


## 순차 점등 프레임: k 번째 프레임은 묶음 k 가 가장 밝고, 지나간 묶음이 trail 만큼 잔광으로 남는다
static func frames(kind: String) -> Array:
	if not _frames.has(kind):
		var sh := _shape(kind)
		var spec: Dictionary = ANIM[kind]
		var groups: Array = spec.groups
		var trail: Array = spec.trail
		var out: Array = []
		# 마지막 묶음 뒤로 잔광이 사그라드는 프레임까지 포함 (되감기지 않는다)
		for k in groups.size() + trail.size() - 1:
			var wts := PackedFloat32Array()
			wts.resize(sh[1].size())
			for g in groups.size():
				var back: int = k - g
				if back >= 0 and back < trail.size():
					for pi in groups[g]:
						wts[pi] = trail[back]
			var img := _raster(sh[0], sh[1], wts)
			img.generate_mipmaps()
			out.append(ImageTexture.create_from_image(img))
		_frames[kind] = out
	return _frames[kind]


## weights 가 비면 흰 도형 · 투명 바탕(알베도). 있으면 부품마다 밝기를 칠한 검은 바탕(발광)
static func _raster(size: Vector2, parts: Array, weights := PackedFloat32Array()) -> Image:
	var s := float(PX * SS)
	var w := int(ceil((size.x + PAD * 2.0) * s / SS)) * SS
	var h := int(ceil((size.y + PAD * 2.0) * s / SS)) * SS
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0) if weights.is_empty() else Color.BLACK)
	var off := Vector2(PAD, PAD)
	for pi in parts.size():
		var part: Array = parts[pi]
		var ink := Color.WHITE
		if not weights.is_empty():
			if weights[pi] <= 0.0:
				continue
			ink = Color(weights[pi], weights[pi], weights[pi])
		# 한 부품의 윤곽선들은 짝홀 규칙: 안쪽 윤곽 = 구멍
		var ax := PackedFloat32Array()
		var ay := PackedFloat32Array()
		var bx := PackedFloat32Array()
		var by := PackedFloat32Array()
		var ymin := INF
		var ymax := -INF
		for contour in part:
			var m: int = contour.size()
			for i in m:
				var a: Vector2 = (contour[i] + off) * s
				var b: Vector2 = (contour[(i + 1) % m] + off) * s
				ax.append(a.x); ay.append(a.y); bx.append(b.x); by.append(b.y)
				ymin = minf(ymin, a.y)
				ymax = maxf(ymax, a.y)
		for y in range(maxi(0, floori(ymin)), mini(h, ceili(ymax) + 1)):
			var yc := y + 0.5
			var xs := PackedFloat32Array()
			for e in ax.size():
				if (ay[e] <= yc) != (by[e] <= yc):
					xs.append(ax[e] + (yc - ay[e]) / (by[e] - ay[e]) * (bx[e] - ax[e]))
			xs.sort()
			for k in range(0, xs.size() - 1, 2):
				var x0 := clampi(roundi(xs[k]), 0, w)
				var x1 := clampi(roundi(xs[k + 1]), 0, w)
				if x1 > x0:
					img.fill_rect(Rect2i(x0, y, x1 - x0, 1), ink)
	img.resize(w / SS, h / SS, Image.INTERPOLATE_BILINEAR)
	return img


# ── 도형 (단위 좌표, y 아래로) ─────────────────────────
## 반환: [크기, 부품 목록]. 부품 = 윤곽선 배열(짝홀)

static func _shape(name: String) -> Array:
	var P: Array = []
	match name:
		"cut_tiles":      # 모서리를 사선으로 떼어 낸 정사각 타일 줄
			for i in 4:
				var x := i * 3.6
				P.append([_pl([x + 1.25, 0, x + 3, 0, x + 3, 3, x, 3, x, 1.25])])
				P.append([_pl([x, 0, x + 0.75, 0, x, 0.75])])
			return [Vector2(13.8, 3), P]
		"tri_row":        # 꼭짓점을 자른 삼각형 줄
			for i in 6:
				var x := i * 2.6
				P.append([_pl([x, 2.2, x + 2.4, 2.2, x + 1.5, 0.45, x + 0.9, 0.45])])
			return [Vector2(15.4, 2.2), P]
		"hex_cluster":    # 5 + 4 벌집
			var r := 1.2
			var dx := r * sqrt(3.0) + 0.25
			for i in 5:
				P.append([_hex(r * 0.87 + i * dx, r, r)])
			for i in 4:
				P.append([_hex(r * 0.87 + dx * 0.5 + i * dx, r + dx * 0.87, r)])
			return [Vector2(r * 1.74 + dx * 4, r * 2 + dx * 0.87), P]
		"chevron_col":    # 위를 가리키는 쉐브론 4단
			for i in 4:
				var y := i * 2.2
				P.append([_pl([0, y + 1.8, 2, y, 4, y + 1.8, 4, y + 3, 2, y + 1.2, 0, y + 3])])
			return [Vector2(4, 9.6), P]
		"hazard":         # 경고 사선
			for i in 9:
				var x := i * 1.0
				P.append([_pl([x + 0.9, 0, x + 1.4, 0, x + 0.5, 2, x, 2])])
			return [Vector2(9.4, 2), P]
		"tech_bar":       # 단차가 있는 긴 판
			P.append([_pl([0, 0.7, 3.5, 0.7, 4.2, 0, 7.5, 0, 8.2, 0.7, 16, 0.7, 16, 1.5, 11.8, 1.5, 11.1, 2.2, 2.2, 2.2, 1.5, 1.5, 0, 1.5])])
			P.append([_pl([13, 1.85, 16, 1.85, 16, 2.2, 13.35, 2.2])])
			return [Vector2(16, 2.2), P]
		"arrow_bar":      # 판 · 사선 두 줄 · 블록 · 화살표
			P.append([_pl([0, 0.4, 5.6, 0.4, 5.0, 1.6, 0, 1.6])])
			P.append([_pl([6.2, 0.4, 6.8, 0.4, 6.2, 1.6, 5.6, 1.6])])
			P.append([_pl([7.4, 0.4, 8.0, 0.4, 7.4, 1.6, 6.8, 1.6])])
			P.append([_rect(8.6, 0.4, 0.7, 1.2)])
			P.append([_pl([9.8, 0.4, 12.4, 0.4, 12.4, 0, 14, 1, 12.4, 2, 12.4, 1.6, 9.8, 1.6])])
			return [Vector2(14, 2), P]
		"cross_bracket":  # 십자 틈으로 나뉜 네 조각 프레임
			var q := [0.4, 0, 2.7, 0, 2.7, 2, 2, 2, 2, 2.7, 0, 2.7, 0, 0.4]
			for fx in [false, true]:
				for fy in [false, true]:
					var pts: Array = []
					for k in range(0, q.size(), 2):
						pts.append(6.0 - q[k] if fx else q[k])
						pts.append(6.0 - q[k + 1] if fy else q[k + 1])
					P.append([_pl(pts)])
			return [Vector2(6, 6), P]
		"bead_rail":      # 육각 구슬을 꿴 가는 선
			P.append([_rect(1.0, 0.65, 12.2, 0.3)])
			P.append([_pl([0, 0.2, 0.9, 0.2, 1.5, 0.8, 0.9, 1.4, 0, 1.4])])
			for i in 5:
				P.append([_hex(3.0 + i * 2.0, 0.8, 0.62, false)])
			P.append([_hex(13.2, 0.8, 0.78, false)])
			return [Vector2(14, 1.6), P]
		"hud_corner":     # 각진 L 프레임 + 눈금
			P.append([_pl([1, 0, 8, 0, 8, 0.9, 1.6, 0.9, 0.9, 1.6, 0.9, 8, 0, 8, 0, 1])])
			for i in 3:
				var x := 2.3 + i * 0.8
				P.append([_pl([x + 0.4, 1.4, x + 0.8, 1.4, x + 0.4, 2.0, x, 2.0])])
			P.append([_rect(1.5, 3.2, 0.28, 3.6)])
			P.append([_rect(6.0, 1.35, 2.0, 0.45)])
			return [Vector2(8, 8), P]
		"ring_target":    # 끊긴 원 · 눈금 · 안쪽 호 · 가운데 대시
			var c := Vector2(3.3, 3.3)
			for k in 4:
				var a0 := k * PI * 0.5 + 0.12
				P.append([_arc(c, 2.7, 3.0, a0, a0 + PI * 0.5 - 0.24)])
				var dir := Vector2.from_angle(k * PI * 0.5)
				P.append([_quad_at(c + dir * 3.15, dir, 0.3, 0.5)])
			P.append([_arc(c, 1.85, 2.0, deg_to_rad(200), deg_to_rad(340))])
			P.append([_arc(c, 1.85, 2.0, deg_to_rad(20), deg_to_rad(160))])
			for i in 3:
				var x := c.x - 1.0 + i * 0.75
				P.append([_pl([x + 0.2, c.y - 0.15, x + 0.65, c.y - 0.15, x + 0.45, c.y + 0.15, x, c.y + 0.15])])
			return [Vector2(6.6, 6.6), P]
		"dots":
			for i in 3:
				P.append([_circ(1 + i * 2.5, 1, 1)])
			return [Vector2(7, 2), P]
		"slant_pair":     # 사선으로 맞물린 두 판
			P.append([_pl([0.6, 0, 3.4, 0, 1.4, 3.6, 0.6, 3.6, 0, 3.0, 0, 0.6])])
			P.append([_pl([4.0, 0, 6.4, 0, 7.0, 0.6, 7.0, 3.0, 6.4, 3.6, 2.0, 3.6])])
			return [Vector2(7, 3.6), P]
		"bent_strip":     # 꺾인 굵은 띠 + 가는 보조선
			P.append([_stroke([Vector2(0.6, 8), Vector2(0.6, 3.2), Vector2(3.2, 0.6), Vector2(9.5, 0.6)], 1.2)])
			P.append([_stroke([Vector2(2.1, 7), Vector2(2.1, 3.9), Vector2(3.9, 2.1), Vector2(7.5, 2.1)], 0.3)])
			P.append([_pl([7.9, 1.8, 9.5, 1.8, 9.5, 2.4, 8.3, 2.4])])
			return [Vector2(9.5, 8), P]
		"chev_row":       # >>>
			for i in 3:
				var x := i * 1.4
				P.append([_pl([x, 0, x + 0.9, 0, x + 2, 1, x + 0.9, 2, x, 2, x + 1.1, 1])])
			return [Vector2(4.8, 2), P]
		"vent":           # 슬롯이 뚫린 통풍판
			var parts: Array = [_chamfer(0, 0, 6, 3, 0.5)]
			for i in 4:
				parts.append(_rect(0.7, 0.45 + i * 0.58, 4.6, 0.3))
			P.append(parts)
			return [Vector2(6, 3), P]
	if name.begins_with("num:"):
		var s := name.substr(4)
		for i in s.length():
			for part in _digit(s.unicode_at(i) - 48, i * 5.0):
				P.append(part)
		return [Vector2(s.length() * 5.0 - 1.0, 6), P]
	push_error("MechDecals: unknown shape " + name)
	return [Vector2(1, 1), [[_rect(0, 0, 1, 1)]]]


## 사선 컷이 들어간 각진 숫자 (4 × 6)
static func _digit(n: int, x: float) -> Array:
	var g: Array = []
	match n:
		0:
			g = [[_pl([1.4, 0, 4, 0, 4, 4.6, 2.6, 6, 0, 6, 0, 1.4]), _pl([1.9, 1.2, 2.8, 1.2, 2.8, 4.1, 2.1, 4.8, 1.2, 4.8, 1.2, 1.9])]]
		1:
			g = [[_pl([1.2, 0, 2.6, 0, 2.6, 6, 1.4, 6, 1.4, 1.7, 0.6, 2.5, 0.6, 0.6])]]
		2:
			g = [[_pl([0, 0, 3, 0, 4, 1, 4, 2.6, 1.8, 4.8, 4, 4.8, 4, 6, 0, 6, 0, 4.7, 2.8, 2.1, 2.8, 1.2, 0, 1.2])]]
		3:
			g = [[_pl([0, 0, 3.2, 0, 4, 0.8, 4, 2.4, 3.4, 3, 4, 3.6, 4, 5.2, 3.2, 6, 0, 6, 0, 4.8, 2.8, 4.8, 2.8, 3.6, 1, 3.6, 1, 2.4, 2.8, 2.4, 2.8, 1.2, 0, 1.2])]]
		4:
			g = [[_pl([2, 0, 3.4, 0, 1.6, 3.6, 2.6, 3.6, 2.6, 2.4, 3.8, 2.4, 3.8, 3.6, 4, 3.6, 4, 4.8, 3.8, 4.8, 3.8, 6, 2.6, 6, 2.6, 4.8, 0, 4.8, 0, 3.6])]]
		5:
			g = [[_pl([0, 0, 4, 0, 4, 1.2, 1.2, 1.2, 1.2, 2.4, 3.2, 2.4, 4, 3.2, 4, 5.2, 3.2, 6, 0, 6, 0, 4.8, 2.8, 4.8, 2.8, 3.6, 0, 3.6])]]
		6, 9:
			var o := [1.6, 0, 4, 0, 4, 1.2, 2.2, 1.2, 1.5, 2.4, 3.2, 2.4, 4, 3.2, 4, 6, 0, 6, 0, 2.4]
			var hole := [1.2, 3.6, 2.8, 3.6, 2.8, 4.8, 1.2, 4.8]
			if n == 9:
				o = _flip(o)
				hole = _flip(hole)
			g = [[_pl(o), _pl(hole)]]
		7:
			g = [[_pl([0, 0, 4, 0, 4, 1.2, 2, 6, 0.7, 6, 2.6, 1.2, 0, 1.2])]]
		8:
			g = [[_chamfer(0, 0, 4, 6, 0.8), _rect(1.2, 1.2, 1.6, 1.2), _pl([1.2, 3.6, 2.8, 3.6, 2.8, 4.8, 1.2, 4.8])]]
	for part in g:
		for i in part.size():
			var c: PackedVector2Array = part[i]
			for k in c.size():
				c[k].x += x
			part[i] = c
	return g


static func _flip(a: Array) -> Array:
	var out: Array = []
	for k in range(0, a.size(), 2):
		out.append(4.0 - a[k])
		out.append(6.0 - a[k + 1])
	return out


static func _pl(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in range(0, a.size(), 2):
		out.append(Vector2(a[k], a[k + 1]))
	return out


static func _rect(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return _pl([x, y, x + w, y, x + w, y + h, x, y + h])


static func _chamfer(x: float, y: float, w: float, h: float, c: float) -> PackedVector2Array:
	return _pl([x + c, y, x + w - c, y, x + w, y + c, x + w, y + h - c, x + w - c, y + h, x + c, y + h, x, y + h - c, x, y + c])


static func _hex(cx: float, cy: float, r: float, pointy := true) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in 6:
		var a := PI / 3.0 * k + (PI / 6.0 if pointy else 0.0)
		out.append(Vector2(cx, cy) + Vector2.from_angle(a) * r)
	return out


static func _circ(cx: float, cy: float, r: float, n := 40) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in n:
		out.append(Vector2(cx, cy) + Vector2.from_angle(TAU * k / n) * r)
	return out


static func _arc(c: Vector2, r0: float, r1: float, a0: float, a1: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := maxi(4, int((a1 - a0) / 0.08))
	for k in n + 1:
		out.append(c + Vector2.from_angle(lerpf(a0, a1, float(k) / n)) * r1)
	for k in n + 1:
		out.append(c + Vector2.from_angle(lerpf(a1, a0, float(k) / n)) * r0)
	return out


## 중심 at, 방향 dir 로 길이 len · 폭 wid 인 사각형
static func _quad_at(at: Vector2, dir: Vector2, len: float, wid: float) -> PackedVector2Array:
	var u := dir * len * 0.5
	var v := dir.orthogonal() * wid * 0.5
	return PackedVector2Array([at - u - v, at + u - v, at + u + v, at - u + v])


## 열린 꺾은선을 두께 t 의 띠로 (마이터 이음)
static func _stroke(pts: Array, t: float) -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var p: Vector2 = pts[i]
		var d0: Vector2 = (p - pts[i - 1]).normalized() if i > 0 else (pts[1] - p).normalized()
		var d1: Vector2 = (pts[i + 1] - p).normalized() if i < n - 1 else d0
		var n0 := d0.orthogonal()
		var miter := (n0 + d1.orthogonal()).normalized()
		var k := t * 0.5 / maxf(0.2, miter.dot(n0))
		left.append(p + miter * k)
		right.append(p - miter * k)
	right.reverse()
	return left + right
