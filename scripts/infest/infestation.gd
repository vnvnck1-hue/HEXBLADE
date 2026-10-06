class_name Infestation
extends Node3D
## 감염 오염물 배치 관리자 (docs/infestation.md). 방마다 안쪽 구석(두 벽이 만나는 자리)에 감염 포낭 무더기(InfestNest)를
## 종양처럼 국소적으로 키워 놓고, 곧은 벽에도 가끔 작은 혹 무리를 붙인다.
##  · 무더기: 구석에 가장 큰 포낭 하나 → 둘레에 중간 크기 → 바깥으로 갈수록 작은 혹. 서로 겹치며 한 덩어리처럼 붙고,
##    작은 것일수록 벽을 따라 멀리 번진다. 벽면에도 포낭이 붙고, 바닥·벽에 연결막이 깔린다.
##  · 크기 등급 (큰·중간·작은) 을 섞어 방마다 생김새가 다르다. 같은 시드면 같은 배치.
##  · 살아 있는 큰 포낭은 플레이어가 파고들지 못하게 밀어낸다 (작은 혹은 밟고 지나감).
## 끄기: 실행 인자 --infest=off (또는 Infestation.enabled = false). Main 하위 씬이 infest_layout(i) 를 가지면 자동 배치 대신 그것을 부른다.

const PER_ROOM := Vector2i(1, 4)      ## 방마다 구석 무더기 수 (큰 방은 위쪽)
const WALL_GROWTH := 0.55             ## 방마다 곧은 벽 작은 혹 무리 확률
const MIN_GAP := 3.6                  ## 무더기 사이 최소 거리
const DOOR_GAP := 2.6
const START_GAP := 3.5
const WALL_TOP := 0.66                ## 벽에 붙는 것의 최고 높이 (낮은 벽 0.8 · 엄폐물 0.7 아래)
const SIZE_K := 1.25                  ## 포낭 크기 전체 배율 (전투 카메라에서 형태가 읽히게)

static var enabled := not OS.get_cmdline_user_args().has("--infest=off")
static var inst: Infestation

var main: Main
var map: ArenaMap
var rng := RandomNumberGenerator.new()
var nests: Array[InfestNest] = []
var used: Array = []                  ## [Vector3, 반지름]


static func attach(m: Main) -> Infestation:
	if not enabled or m.map == null:
		return null
	var i := Infestation.new()
	i.name = "Infestation"
	i.main = m
	m.world.add_child(i)
	return i


func _exit_tree() -> void:
	if inst == self:
		inst = null


func _ready() -> void:
	inst = self
	map = main.map
	# 첫 포낭이 터질 때의 준비 비용(셰이더 · 액체 시트 텍스처 · 효과음 합성, 약 30ms)을 씬을 불러오는 동안 치른다
	InfestMesh.goo_mat()
	InfestSound.ensure()
	for k in LiquidFX.KIND_FILES.size():
		LiquidFX.material(k, "wine")
	rng.seed = hash([main.map_seed, map.rooms.size(), "infest"]) if main.map_seed >= 0 else randi()
	# Gimmicks 배치(같은 프레임 deferred)가 끝난 뒤에 — 가스통·연기·레일 자리를 피한다
	_layout.call_deferred()


func _layout() -> void:
	if main.has_method("infest_layout"):
		main.call("infest_layout", self)
		return
	if main.showcase:
		return
	_reserve()
	for r in map.rooms:
		_populate(r.id)


func _reserve() -> void:
	if is_instance_valid(main.player):
		used.append([main.player.global_position, START_GAP])
	var ps = main.get("portals")
	if ps is Array:
		for p in ps:
			if is_instance_valid(p):
				used.append([(p as Node3D).global_position, 2.6])
	var pad = main.get("rest_pad")
	if pad is Node3D and is_instance_valid(pad):
		used.append([pad.global_position, 3.0])
	if Gimmicks.inst:
		for u in Gimmicks.inst.used:
			used.append(u)


func _populate(id: int) -> void:
	var r: Dictionary = map.rooms[id]
	var big: float = r.get("scale", 1.0)
	var corners := find_corners(id)
	corners.shuffle()
	# 카메라를 향한 뒤쪽 구석(벽이 -Z)이 잘 보이니 먼저
	corners.sort_custom(func(a, b): return float(a.iz.z) > float(b.iz.z))
	var want := clampi(int(round(corners.size() * 0.35)), PER_ROOM.x, PER_ROOM.x + int(big * 1.3) + (1 if r.combat else 0))
	want = mini(want, PER_ROOM.y)
	var made := 0
	for c in corners:
		if made >= want:
			break
		if not _free(c.k, 1.9):
			continue
		var roll := rng.randf()
		var tier := 2 if roll < 0.32 else (1 if roll < 0.8 else 0)
		if made == 0 and big >= 1.5:
			tier = 2
		var n := add_corner(c.k, c.ix, c.iz, tier)
		if n:
			made += 1
	if rng.randf() < WALL_GROWTH:
		var walls := find_walls(id)
		walls.shuffle()
		for w in walls:
			if _free(w.k, 1.5):
				add_wall(w.k, w.n, w.t)
				break


func _free(p: Vector3, r: float) -> bool:
	for u in used:
		var q: Vector3 = u[0]
		if Vector2(p.x - q.x, p.z - q.z).length() < r + float(u[1]):
			return false
	var rid := map.room_at(p + Vector3(0, 0, 0))
	if rid >= 0:
		for door in map.rooms[rid].doors:
			if map.world_of(door[0]).distance_to(p) < DOOR_GAP:
				return false
	return true


# ── 자리 찾기 ─────────────────────────────────────────────

func _floor_ok(c: Vector2i, h0: float) -> bool:
	return map.cell_type(c) == ArenaMap.FLOOR and map.gate_of[map._idx(c)] < 0 and absf(map.cell_h(c) - h0) < 0.06


func _solid(c: Vector2i) -> bool:
	if map.cell_type(c) == ArenaMap.FLOOR:
		return false
	var occ = map.get_meta("claude_occupied") if map.has_meta("claude_occupied") else {}
	return not (occ as Dictionary).has(c)       # 벽감 작업대·수납장·벽 장식 칸은 피한다


## 안쪽 구석: 두 직교 이웃과 대각 칸이 벽이고, 방 안쪽 3×3 이 평평한 바닥. {k 구석점, ix/iz 두 벽의 안쪽 법선}
func find_corners(id: int) -> Array:
	var out: Array = []
	for c: Vector2i in map.rooms[id].cells:
		var h0 := map.cell_h(c)
		for s: Vector2i in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			if not (_solid(c + Vector2i(s.x, 0)) and _solid(c + Vector2i(0, s.y)) and _solid(c + s)):
				continue
			var ok := true
			for a in 3:
				for b in 3:
					if not _floor_ok(c - Vector2i(s.x * a, s.y * b), h0):
						ok = false
			if not ok:
				continue
			var k := map.world_of(c) + Vector3(s.x, 0, s.y) * ArenaMap.CELL * 0.5
			k.y = h0
			out.append({"k": k, "ix": Vector3(-s.x, 0, 0), "iz": Vector3(0, 0, -s.y)})
	return out


## 곧은 벽: 한쪽만 벽이고 양옆으로 2칸씩 같은 벽이 이어지는 자리. {k 벽면 점, n 안쪽 법선, t 벽 방향}
func find_walls(id: int) -> Array:
	var out: Array = []
	for c: Vector2i in map.rooms[id].cells:
		var h0 := map.cell_h(c)
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var side := Vector2i(d.y, d.x)
			var ok := true
			for i in range(-2, 3):
				if not _solid(c + d + side * i) or not _floor_ok(c + side * i, h0) or not _floor_ok(c + side * i - d, h0) or not _floor_ok(c + side * i - d * 2, h0):
					ok = false
			if not ok:
				continue
			var k := map.world_of(c) + Vector3(d.x, 0, d.y) * ArenaMap.CELL * 0.5
			k.y = h0
			out.append({"k": k, "n": Vector3(-d.x, 0, -d.y), "t": Vector3(side.x, 0, side.y)})
	return out


# ── 무더기 설계 ───────────────────────────────────────────

## 등급별 포낭 크기 (s = 0.5m 원본 배율). 큰 것부터 놓는다. 전체에 SIZE_K 를 곱한다
func _sizes(tier: int) -> Array:
	var out := _sizes_raw(tier)
	for i in out.size():
		out[i] = float(out[i]) * SIZE_K
	return out


func _sizes_raw(tier: int) -> Array:
	var out: Array = []
	match tier:
		2:
			out.append(rng.randf_range(1.9, 2.35))
			for i in 3: out.append(rng.randf_range(1.1, 1.5))
			for i in 5: out.append(rng.randf_range(0.6, 0.95))
			for i in 6: out.append(rng.randf_range(0.28, 0.48))
		1:
			out.append(rng.randf_range(1.4, 1.75))
			for i in 2: out.append(rng.randf_range(0.85, 1.2))
			for i in 4: out.append(rng.randf_range(0.55, 0.85))
			for i in 4: out.append(rng.randf_range(0.28, 0.45))
		_:
			out.append(rng.randf_range(0.95, 1.25))
			for i in 2: out.append(rng.randf_range(0.6, 0.85))
			for i in 3: out.append(rng.randf_range(0.28, 0.45))
	return out


## 구석 무더기. k = 구석점(바닥 높이), ix/iz = 두 벽 면의 안쪽 법선
func add_corner(k: Vector3, ix: Vector3, iz: Vector3, tier: int) -> InfestNest:
	var placed: Array = []        # [Vector2(u, v), r, s]
	var sizes := _sizes(tier)
	for s: float in sizes:
		var r := 0.25 * s
		for tries in 30:
			var uv: Vector2
			if placed.is_empty():
				uv = Vector2(r * 0.8, r * 0.8) + Vector2(rng.randf_range(0, 0.08), rng.randf_range(0, 0.08))
			else:
				# 작은 것일수록 멀리, 벽을 따라 번지는 쪽을 자주
				var reach := rng.randf_range(0.25, 0.55 + (1.0 - clampf(s / 2.0, 0.0, 1.0)) * 1.5)
				var th := rng.randf() * PI * 0.5
				if rng.randf() < 0.5:
					th = (rng.randf_range(0.0, 0.25) if rng.randf() < 0.5 else rng.randf_range(PI * 0.5 - 0.25, PI * 0.5))
				var hero: Vector2 = placed[0][0]
				uv = hero + Vector2(cos(th), sin(th)) * (float(placed[0][1]) * 0.6 + reach)
				uv.x = maxf(uv.x, r * 0.72)
				uv.y = maxf(uv.y, r * 0.72)
			if _fits(placed, uv, r):
				placed.append([uv, r, s])
				break
	var to_world := func(uv: Vector2) -> Vector3:
		return k + ix * uv.x + iz * uv.y
	var walls := [{"n": ix, "t": iz}, {"n": iz, "t": ix}]
	var wall_n := 3 if tier == 2 else (2 if tier == 1 else 1)
	var mems: Array = []
	var ms: float = [rng.randf_range(1.4, 1.8), rng.randf_range(2.0, 2.4), rng.randf_range(2.5, 3.0)][tier]
	mems.append(["floor", to_world.call(Vector2(rng.randf_range(0.5, 0.75), rng.randf_range(0.5, 0.75))), ms])
	for i in tier:
		var along := rng.randf_range(1.3, 2.1)
		var off := rng.randf_range(0.3, 0.6)
		mems.append(["floor", to_world.call(Vector2(along, off) if i % 2 == 0 else Vector2(off, along)), rng.randf_range(1.1, 1.6)])
	return _make(k, placed, to_world, walls, wall_n, tier, mems, true)


## 곧은 벽 작은 혹 무리. k = 벽면 점, n = 안쪽 법선, t = 벽 방향
func add_wall(k: Vector3, n: Vector3, t: Vector3) -> InfestNest:
	var placed: Array = []
	var sizes: Array = [rng.randf_range(0.7, 0.95)]
	for i in rng.randi_range(2, 4):
		sizes.append(rng.randf_range(0.28, 0.6))
	for s: float in sizes:
		var r := 0.25 * s
		for tries in 30:
			var uv := Vector2(r * 0.75 + rng.randf_range(0.0, 0.25), rng.randf_range(-0.9, 0.9) if not placed.is_empty() else 0.0)
			if _fits(placed, uv, r):
				placed.append([uv, r, s])
				break
	var to_world := func(uv: Vector2) -> Vector3:
		return k + n * uv.x + t * uv.y
	var mems: Array = [["floor", to_world.call(Vector2(0.35, rng.randf_range(-0.2, 0.2))), rng.randf_range(1.0, 1.4)]]
	return _make(k, placed, to_world, [{"n": n, "t": t, "sym": true}], 1, 0, mems, false)


## 겹침은 조금 허용 (한 덩어리로 붙어 보이게), 너무 파묻히거나 떨어져 있으면 안 된다
func _fits(placed: Array, uv: Vector2, r: float) -> bool:
	if placed.is_empty():
		return true
	var touch := false
	for q: Array in placed:
		var d := uv.distance_to(q[0])
		var rr := r + float(q[1])
		if d < rr * 0.6:
			return false
		if d < rr + 0.06:
			touch = true
	return touch


func _make(k: Vector3, placed: Array, to_world: Callable, walls: Array, wall_n: int, tier: int, floor_mems: Array, corner: bool) -> InfestNest:
	if placed.is_empty():
		return null
	var cysts: Array = []
	var origin := Vector3.ZERO
	var wsum := 0.0
	for q: Array in placed:
		var w := float(q[2])
		var p: Vector3 = to_world.call(q[0])
		origin += p * w
		wsum += w
	origin /= wsum
	origin.y = k.y
	var seed_v := rng.randi()
	for q: Array in placed:
		var p: Vector3 = to_world.call(q[0])
		p.y = map.height_at(p)
		var out := Vector3(p.x - k.x, 0, p.z - k.z)
		out = out.normalized() if out.length() > 0.05 else (walls[0].n as Vector3)
		# 바깥쪽으로 살짝 기울어 자란다 + 아무렇게나 돈 방향
		var tilt := Basis(out.cross(Vector3.UP).normalized(), -rng.randf_range(0.0, 0.22)) if out.length() > 0.5 else Basis.IDENTITY
		var b := tilt * Basis(Vector3.UP, rng.randf() * TAU)
		cysts.append({"pos": p - origin, "basis": b.orthonormalized(), "s": q[2], "v": rng.randi_range(0, InfestMesh.CYST_VARIANTS - 1), "wall": false})
	# 벽면 포낭
	for i in wall_n:
		var w: Dictionary = walls[rng.randi_range(0, walls.size() - 1)]
		var s := rng.randf_range(0.55, 1.05) if i == 0 else rng.randf_range(0.35, 0.75)
		var r := 0.25 * s
		var along := rng.randf_range(-0.9, 0.9) if w.get("sym", false) else rng.randf_range(0.15, 1.3 if tier > 0 else 0.8)
		var h := clampf(rng.randf_range(0.12, 0.5), r * 0.75, WALL_TOP - r * 0.9)
		var nrm: Vector3 = w.n
		var tan: Vector3 = w.t
		var p := k + tan * along + Vector3.UP * h + nrm * 0.0
		var y := nrm
		var x := tan
		var z := x.cross(y).normalized()
		var b := Basis(x, y, z) * Basis(Vector3.UP, rng.randf() * TAU)
		cysts.append({"pos": p - origin, "basis": b.orthonormalized(), "s": s, "v": rng.randi_range(0, InfestMesh.CYST_VARIANTS - 1), "wall": true})
	var mems: Array = []
	for fm: Array in floor_mems:
		var p: Vector3 = fm[1]
		p.y = map.height_at(p) + 0.004
		var s: float = fm[2]
		mems.append({"pos": p - origin, "basis": Basis(Vector3.UP, rng.randf() * TAU), "scale": Vector3(s, 1.0, s * rng.randf_range(0.8, 1.1)), "v": rng.randi_range(0, InfestMesh.MEMBRANE_VARIANTS - 1)})
	# 벽면 연결막 (아래 가장자리가 바닥에 닿게)
	var wm := 2 if tier == 2 else (1 if tier == 1 or rng.randf() < 0.5 else 0)
	for i in wm:
		var w: Dictionary = walls[i % walls.size()]
		var ww := rng.randf_range(1.1, 1.7)
		var hh := rng.randf_range(0.5, WALL_TOP + 0.04)
		var along: float = rng.randf_range(-0.3, 0.3) if w.get("sym", false) else ww * 0.4 + rng.randf_range(0.0, 0.3)
		var nrm: Vector3 = w.n
		var tan: Vector3 = w.t
		var p := k + tan * along + Vector3.UP * (hh * 0.5 - 0.03) + nrm * 0.004
		var z := tan.cross(nrm).normalized()
		mems.append({"pos": p - origin, "basis": Basis(tan, nrm, z), "scale": Vector3(ww, 1.0, hh), "v": rng.randi_range(0, InfestMesh.MEMBRANE_VARIANTS - 1)})
	var nest := InfestNest.new()
	nest.plan = {"cysts": cysts, "mems": mems, "seed": seed_v}
	main.world.add_child(nest)
	nest.global_position = origin
	nests.append(nest)
	var rad := nest.radius + 0.5
	used.append([origin, rad])
	if Gimmicks.inst:
		Gimmicks.inst.used.append([origin, rad])
	return nest


# ── 매 틱: 큰 포낭은 몸으로 밀고 들어갈 수 없다 ─────────────

func _physics_process(_dt: float) -> void:
	var p := main.player
	if not is_instance_valid(p) or not p.alive or p.airborne:
		return
	var pos := p.global_position
	var moved := false
	for n in nests:
		if not is_instance_valid(n) or not n.alive:
			continue
		var d := Vector2(pos.x - n.global_position.x, pos.z - n.global_position.z).length()
		if d > n.radius + 1.5:
			continue
		var q := n.push_out(pos, p.hit_radius * 0.75)
		if q != pos:
			pos = q
			moved = true
	if moved:
		p.global_position = main.push_out(pos, p.hit_radius * 0.75)
	nests = nests.filter(func(x): return is_instance_valid(x))


## 지금 살아 있는 무더기 수 (시험·HUD 조회용)
func alive_count() -> int:
	var c := 0
	for n in nests:
		if is_instance_valid(n) and n.alive:
			c += 1
	return c
