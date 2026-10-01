extends Node3D
## 거미 보스 전장 · SHAFT 07 (버려진 건조 갱도). 판정·경로·표면 정보는 모두 이 파일이 갖는다.
##  - 54×46m 강철 바닥 홀. 북·동·서쪽은 화면을 채우는 48m 벽, 카메라 쪽(남쪽)은 낮은 난간만 둔다(절개면).
##  - 벽에는 바닥 높이의 큰 굴(TUNNEL)과 높은 곳의 배관 구멍(DUCT)이 뚫려 있고, 보스가 이 구멍으로 숨었다 나타난다.
##  - 홀 안의 기둥 7개는 위로 끝없이 이어져 어둠 속으로 사라진다 (엄폐물 · 공간감 · 보스가 오르내리는 길).
##  - 카메라와 플레이어 사이를 가리는 기둥은 화면에서 플레이어 둘레만 점묘로 비운다 (occlusion 셰이더).
## 표면 투영(project)과 경로(route)는 거미 보스의 다리 IK 와 이동이 쓴다: 바닥·벽·기둥 어디든 붙어 다닌다.

const HX := 27.0                     # 바닥 반폭 (x)
const HZ := 23.0                     # 바닥 반깊이 (z)
const WALL_H := 48.0
const WALL_T := 3.0
const SOUTH_H := 2.6                 # 카메라 쪽 난간 높이
const PILLAR_H := 190.0
const TUNNEL_D := 16.0               # 구멍 안쪽 깊이
const RIDE := 2.3                    # 보스 몸 중심이 붙은 면에서 떠 있는 높이
const PILLAR_CLEAR := 4.2            # 보스가 바닥에서 기둥을 비켜 가는 여유 (몸 + 다리)

## 기둥: [위치(x,z), 반지름]
const PILLARS := [
	[Vector2(-15.0, -10.0), 2.4],
	[Vector2(14.0, -11.0), 2.6],
	[Vector2(-3.0, -2.5), 2.2],
	[Vector2(-17.0, 9.0), 2.3],
	[Vector2(15.5, 7.0), 2.5],
	[Vector2(3.5, 13.0), 2.0],
	[Vector2(2.5, -15.0), 2.0],
]
## 구멍: wall N/E/W · u = 벽을 따라가는 좌표 (N 은 x, E·W 는 z) · y = 아래 끝 높이 · w·h = 너비·높이
## 바닥 굴(y = 0)은 보스가 걸어 들어가고, 배관 구멍은 벽을 기어 올라가 머리부터 들어간다.
const HOLES := [
	{"wall": "N", "u": -14.0, "y": 0.0, "w": 10.0, "h": 7.5},
	{"wall": "N", "u": 15.0, "y": 0.0, "w": 10.0, "h": 7.5},
	{"wall": "W", "u": 6.0, "y": 0.0, "w": 10.0, "h": 7.5},
	{"wall": "E", "u": -8.0, "y": 0.0, "w": 10.0, "h": 7.5},
	{"wall": "N", "u": 0.0, "y": 11.0, "w": 9.0, "h": 6.5},
	{"wall": "W", "u": -12.0, "y": 9.0, "w": 9.0, "h": 6.5},
	{"wall": "E", "u": 12.0, "y": 10.0, "w": 9.0, "h": 6.5},
	{"wall": "N", "u": 9.0, "y": 19.0, "w": 9.0, "h": 6.5},
]

const STEEL := Color(0.16, 0.17, 0.19)
const STEEL_DARK := Color(0.07, 0.075, 0.085)
const HAZARD := Color(0.95, 0.7, 0.12)
const CYAN := Color(0.35, 0.95, 1.0)
const DANGER := Color(1.0, 0.16, 0.12)

var webs: Array = []                 # 바닥 거미줄 판 {mi, pos, r, life, max}
var occl_mat: ShaderMaterial         # 기둥 셰이더 (플레이어 가림 구멍)
var wall_mat: ShaderMaterial
var hole_glows: Array = []           # 구멍마다 안쪽 눈빛 {node, mats, k, target}
var beacons: Array = []              # 기둥 신호등 (2페이즈에 붉게 깜빡인다)
var alarm := 0.0                     # 0~1, 2페이즈 경보 조명
var _dust: Array = []                # [mi, vel, life, max, size]
var _dust_mesh: QuadMesh
var _dust_mat: ShaderMaterial
var _web_mat: ShaderMaterial
var _strands: Array = []             # 위에서 늘어진 거미줄 가닥 (흔들림)
var _t := 0.0


func _ready() -> void:
	_build_floor()
	_build_walls()
	_build_holes()
	_build_pillars()
	_build_decor()
	_dust_mesh = QuadMesh.new()
	_dust_mat = ShaderMaterial.new()
	_dust_mat.shader = _shader(DUST_SHADER)
	_web_mat = ShaderMaterial.new()
	_web_mat.shader = _shader(WEB_FLOOR_SHADER)


## 노이즈 함수를 붙인 spatial 셰이더 (shader_type 줄이 맨 앞에 와야 한다)
static func _shader_n(body: String) -> Shader:
	return _shader("shader_type spatial;" + String.chr(10) + NOISE + body)


static func _shader(code: String) -> Shader:
	var s := Shader.new()
	s.code = code
	return s


# ── 표면 · 판정 ─────────────────────────────────────────

## 벽 이름 → 안쪽을 향한 법선
static func wall_n(w: String) -> Vector3:
	match w:
		"N": return Vector3(0, 0, 1)
		"S": return Vector3(0, 0, -1)
		"W": return Vector3(1, 0, 0)
		_: return Vector3(-1, 0, 0)


## 벽면 위 한 점: u(벽을 따라) · y(높이)
static func wall_point(w: String, u: float, y: float) -> Vector3:
	match w:
		"N": return Vector3(u, y, -HZ)
		"S": return Vector3(u, y, HZ)
		"W": return Vector3(-HX, y, u)
		_: return Vector3(HX, y, u)


## 점의 벽 좌표 (u, 벽면까지 거리 · 안쪽이 +)
static func wall_uv(w: String, p: Vector3) -> Vector2:
	match w:
		"N": return Vector2(p.x, p.z + HZ)
		"S": return Vector2(p.x, HZ - p.z)
		"W": return Vector2(p.z, p.x + HX)
		_: return Vector2(p.z, HX - p.x)


static func wall_half(w: String) -> float:
	return HX if w == "N" or w == "S" else HZ


static func pillar_pos(i: int) -> Vector3:
	var v: Vector2 = PILLARS[i][0]
	return Vector3(v.x, 0, v.y)


static func pillar_r(i: int) -> float:
	return float(PILLARS[i][1])


static func hole_center(i: int) -> Vector3:
	var h: Dictionary = HOLES[i]
	return wall_point(h.wall, h.u, float(h.y) + float(h.h) * 0.5)


static func is_duct(i: int) -> bool:
	return float((HOLES[i] as Dictionary).y) > 0.5


## 점 p 가 구멍 i 의 입구(벽면 사각형) 안에 드는가
static func in_opening(i: int, w: String, u: float, y: float, pad := 0.0) -> bool:
	var h: Dictionary = HOLES[i]
	if h.wall != w:
		return false
	return absf(u - float(h.u)) < float(h.w) * 0.5 - pad and y > float(h.y) + pad and y < float(h.y) + float(h.h) - pad


## 점이 어떤 구멍 안(벽 뒤 굴 속)에 있는가. 있으면 구멍 번호, 없으면 -1
static func inside_hole(p: Vector3) -> int:
	for i in HOLES.size():
		var h: Dictionary = HOLES[i]
		var uv := wall_uv(h.wall, p)
		if uv.y < 0.3 and uv.y > -TUNNEL_D - 2.0 and absf(uv.x - float(h.u)) < float(h.w) * 0.5 + 0.5 and p.y > float(h.y) - 1.0 and p.y < float(h.y) + float(h.h) + 2.0:
			return i
	return -1


## 탄을 막는가: 바닥 사각형 밖 · 기둥 안
func is_blocked(p: Vector3) -> bool:
	if absf(p.x) > HX or absf(p.z) > HZ:
		return true
	for i in PILLARS.size():
		var c := pillar_pos(i)
		if Vector2(p.x - c.x, p.z - c.z).length() < pillar_r(i):
			return true
	return false


## 플레이어·잡몹: 바닥 안 · 기둥 밖으로 밀어낸다
func push_out(p: Vector3, radius: float) -> Vector3:
	p.x = clampf(p.x, -HX + radius, HX - radius)
	p.z = clampf(p.z, -HZ + radius, HZ - radius)
	for i in PILLARS.size():
		var c := pillar_pos(i)
		var d := Vector2(p.x - c.x, p.z - c.z)
		var rr := pillar_r(i) + radius
		if d.length() < rr:
			d = d.normalized() * rr if d.length() > 0.001 else Vector2(rr, 0)
			p.x = c.x + d.x
			p.z = c.z + d.y
	return p


## 다리 IK 용: 점 q 에서 가장 가까운 "디딜 수 있는 면"의 점과 법선 {p, n}
## 바닥(굴 바닥 포함) · 북동서 벽(구멍 입구 제외) · 기둥 옆면 · 배관 구멍 바닥 중에서 고른다.
func project(q: Vector3) -> Dictionary:
	var best_p := Vector3(q.x, 0.0, q.z)
	var best_n := Vector3.UP
	var best_d := INF
	# 바닥: 홀 안 또는 바닥 굴 안
	var hi := inside_hole(q)
	var on_floor := (absf(q.x) <= HX + 0.5 and absf(q.z) <= HZ + 0.5) or (hi >= 0 and not is_duct(hi))
	if on_floor:
		best_d = absf(q.y)
	# 배관 구멍 바닥
	if hi >= 0 and is_duct(hi):
		var hy := float((HOLES[hi] as Dictionary).y)
		var d := absf(q.y - hy)
		if d < best_d:
			best_d = d
			best_p = Vector3(q.x, hy, q.z)
			best_n = Vector3.UP
	# 벽
	for w in ["N", "E", "W"]:
		var uv := wall_uv(w, q)
		var u := clampf(uv.x, -wall_half(w), wall_half(w))
		var y := clampf(q.y, 0.0, WALL_H)
		var blocked := false
		for i in HOLES.size():
			if in_opening(i, w, u, y, 0.4):
				blocked = true
				break
		if blocked:
			continue
		var wp := wall_point(w, u, y)
		var d := q.distance_to(wp)
		if d < best_d:
			best_d = d
			best_p = wp
			best_n = wall_n(w)
	# 기둥
	for i in PILLARS.size():
		var c := pillar_pos(i)
		var rad := Vector3(q.x - c.x, 0, q.z - c.z)
		if rad.length() < 0.01:
			rad = Vector3(1, 0, 0)
		var n := rad.normalized()
		var pp := Vector3(c.x, maxf(q.y, 0.0), c.z) + n * pillar_r(i)
		var d := q.distance_to(pp)
		if d < best_d:
			best_d = d
			best_p = pp
			best_n = n
	return {"p": best_p, "n": best_n, "d": best_d}


# ── 경로 ────────────────────────────────────────────────
## 위치(loc) = {s: floor|wall|pillar|duct|tunnel, c: 몸 중심, n: 붙은 면 법선, w: 벽, i: 번호}
## 경로 점 = {c, n}. 몸 중심을 잇는 꺾은선이고, 오목한 모서리(바닥↔벽)는 몸이 두 면에서 RIDE 만큼 떨어진 L 자로 돈다.

static func floor_loc(p: Vector3) -> Dictionary:
	return {"s": "floor", "c": Vector3(p.x, RIDE, p.z), "n": Vector3.UP}


static func wall_loc(w: String, u: float, y: float) -> Dictionary:
	var hw := wall_half(w) - RIDE * 1.6
	return {"s": "wall", "w": w, "c": wall_point(w, clampf(u, -hw, hw), maxf(y, RIDE * 2.0)) + wall_n(w) * RIDE, "n": wall_n(w)}


static func pillar_loc(i: int, y: float, ang: float) -> Dictionary:
	var n := Vector3(cos(ang), 0, sin(ang))
	return {"s": "pillar", "i": i, "c": pillar_pos(i) + n * (pillar_r(i) + RIDE) + Vector3(0, maxf(y, RIDE * 2.0), 0), "n": n}


## 구멍 속 (depth: 벽면에서 안쪽으로 들어간 거리)
static func hole_loc(i: int, depth := TUNNEL_D - 4.0) -> Dictionary:
	var h: Dictionary = HOLES[i]
	var n := wall_n(h.wall)
	var c := wall_point(h.wall, h.u, float(h.y) + RIDE) - n * depth
	return {"s": "duct" if is_duct(i) else "tunnel", "i": i, "w": h.wall, "c": c, "n": Vector3.UP}


## 구멍 앞에서 몸이 나오고 들어가는 자리 (바닥 굴: 입구 앞 바닥 · 배관 구멍: 구멍 바로 아래 벽면)
static func hole_mouth(i: int) -> Dictionary:
	var h: Dictionary = HOLES[i]
	if is_duct(i):
		return wall_loc(h.wall, h.u, float(h.y) - RIDE * 1.2)
	return floor_loc(wall_point(h.wall, h.u, 0.0) + wall_n(h.wall) * (RIDE * 2.6))


static func _pt(c: Vector3, n: Vector3) -> Dictionary:
	return {"c": c, "n": n.normalized()}


## loc 에서 바닥까지 내려가는 점들 [loc 자신, ..., 바닥 위 점]
static func _chain(loc: Dictionary) -> Array:
	var c: Vector3 = loc.c
	var n: Vector3 = loc.n
	match String(loc.s):
		"floor":
			return [_pt(c, n)]
		"wall", "pillar":
			# 면을 따라 바닥 높이까지 내려와 오목한 모서리를 돌아 바닥으로
			var base := Vector3(c.x, RIDE, c.z)
			var out: Array = [_pt(c, n)]
			if c.y > RIDE * 2.0 + 0.1:
				out.append(_pt(Vector3(c.x, RIDE * 2.0, c.z), n))
			out.append(_pt(base, (n + Vector3.UP).normalized()))
			out.append(_pt(base + n * RIDE, Vector3.UP))
			return out
		"tunnel":
			var i: int = loc.i
			var m := hole_mouth(i)
			var h: Dictionary = HOLES[i]
			var wn := wall_n(h.wall)
			var lip := wall_point(h.wall, h.u, RIDE)
			return [_pt(c, Vector3.UP), _pt(lip - wn * 2.0, Vector3.UP), _pt(lip + wn * 1.0, Vector3.UP), _pt(m.c, Vector3.UP)]
		"duct":
			var i: int = loc.i
			var h: Dictionary = HOLES[i]
			var wn := wall_n(h.wall)
			var hy := float(h.y)
			var lip := wall_point(h.wall, h.u, hy)
			# 구멍 속 → 입구 안쪽 → 볼록한 모서리(바닥 → 벽) → 벽면을 타고 내려간다
			var out: Array = [_pt(c, Vector3.UP), _pt(lip - wn * 2.6 + Vector3(0, RIDE, 0), Vector3.UP)]
			out.append(_pt(lip + (wn + Vector3.UP).normalized() * RIDE * 0.9, (wn + Vector3.UP).normalized()))
			out.append(_pt(lip + wn * RIDE - Vector3(0, RIDE * 0.9, 0), wn))
			var rest := _chain(wall_loc(h.wall, h.u, hy - RIDE * 0.9))
			rest.remove_at(0)
			out.append_array(rest)
			return out
	return [_pt(c, n)]


static func _wall_of(loc: Dictionary) -> String:
	var s := String(loc.s)
	if s == "wall" or s == "duct":
		return String(loc.w)
	return ""


## 벽(또는 그 벽의 배관 구멍)에 붙은 loc 에서 벽면 위 한 점까지 [loc, ..., 벽면 점]
static func _chain_to_wall(loc: Dictionary) -> Array:
	var full := _chain(loc)
	if String(loc.s) == "wall":
		return [full[0]]
	# 배관 구멍: 벽면에 처음 닿는 점까지
	var out: Array = []
	for pt in full:
		out.append(pt)
		if (pt.n as Vector3).is_equal_approx(wall_n(String(loc.w))):
			break
	return out


func route(a: Dictionary, b: Dictionary) -> Array:
	var wa := _wall_of(a)
	var wb := _wall_of(b)
	if wa != "" and wa == wb:
		# 같은 벽: 벽면을 타고 바로 간다
		var A := _chain_to_wall(a)
		var B := _chain_to_wall(b)
		B.reverse()
		var out: Array = A.slice(1)
		out.append_array(B)
		return out
	if String(a.s) == "pillar" and String(b.s) == "pillar" and int(a.i) == int(b.i):
		return [_pt(b.c, b.n)]
	var ca := _chain(a)
	var cb := _chain(b)
	cb.reverse()
	var out: Array = ca.slice(1)
	var fa: Vector3 = (ca[ca.size() - 1] as Dictionary).c
	var fb: Vector3 = (cb[0] as Dictionary).c
	for q in floor_path(fa, fb):
		out.append(_pt(q, Vector3.UP))
	out.append_array(cb.slice(1))
	return out


## 바닥 위 a → b 직선 경로. 기둥이 가로막으면 옆으로 비켜 가는 점을 끼워 넣는다. (a 제외, b 포함)
func floor_path(a: Vector3, b: Vector3) -> Array:
	var pts: Array = [a, b]
	for it in 10:
		var changed := false
		for s in range(pts.size() - 1):
			var p0: Vector3 = pts[s]
			var p1: Vector3 = pts[s + 1]
			for i in PILLARS.size():
				var c := pillar_pos(i)
				c.y = RIDE
				var seg := p1 - p0
				var l2 := seg.length_squared()
				var tt := clampf((c - p0).dot(seg) / maxf(l2, 0.0001), 0.0, 1.0)
				var cl := p0 + seg * tt
				var off := cl - c
				off.y = 0
				var need := pillar_r(i) + PILLAR_CLEAR
				if off.length() < need - 0.05 and tt > 0.02 and tt < 0.98:
					var dir := off.normalized() if off.length() > 0.05 else Vector3(-seg.z, 0, seg.x).normalized()
					var q := c + dir * (need + 0.6)
					q.x = clampf(q.x, -HX + RIDE * 2.0, HX - RIDE * 2.0)
					q.z = clampf(q.z, -HZ + RIDE * 2.0, HZ - RIDE * 2.0)
					q.y = RIDE
					pts.insert(s + 1, q)
					changed = true
					break
			if changed:
				break
		if not changed:
			break
	return pts.slice(1)


## 경로 길이
static func route_len(start: Vector3, r: Array) -> float:
	var l := 0.0
	var p := start
	for q in r:
		l += p.distance_to(q.c)
		p = q.c
	return l


## 바닥 위 무작위 자리 (기둥과 벽에서 떨어진 곳)
func random_floor(min_from: Vector3, min_d: float, max_d := 99.0, margin := 5.0) -> Vector3:
	for it in 60:
		var p := Vector3(randf_range(-HX + margin, HX - margin), 0, randf_range(-HZ + margin, HZ - margin))
		var ok := true
		for i in PILLARS.size():
			if Vector2(p.x - pillar_pos(i).x, p.z - pillar_pos(i).z).length() < pillar_r(i) + margin * 0.8:
				ok = false
		var d := Vector2(p.x - min_from.x, p.z - min_from.z).length()
		if ok and d >= min_d and d <= max_d:
			return p
	return Vector3(0, 0, -6)


# ── 바닥 거미줄 판 ──────────────────────────────────────

func add_web(pos: Vector3, r: float, life := 9.0) -> void:
	if webs.size() > 26:
		var old: Dictionary = webs.pop_front()
		(old.mi as Node).queue_free()
	var q := QuadMesh.new()
	q.orientation = PlaneMesh.FACE_Y
	q.size = Vector2(r * 2.0, r * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _web_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("seed", randf() * 100.0)
	mi.set_instance_shader_parameter("fade", 0.0)
	add_child(mi)
	mi.global_position = Vector3(pos.x, 0.04 + webs.size() * 0.002, pos.z)
	mi.rotation.y = randf() * TAU
	webs.append({"mi": mi, "pos": Vector3(pos.x, 0, pos.z), "r": r, "life": life, "max": life, "age": 0.0})


## 점 p 가 거미줄 판 위인가 (0 = 아님, 1 = 한가운데)
func web_at(p: Vector3) -> float:
	var k := 0.0
	for w in webs:
		var d := Vector2(p.x - (w.pos as Vector3).x, p.z - (w.pos as Vector3).z).length()
		if d < float(w.r) * 0.92:
			k = maxf(k, 1.0 - d / float(w.r) * 0.4)
	return k


## 검으로 거미줄 판을 끊는다
func cut_webs(p: Vector3, r: float) -> int:
	var n := 0
	for w in webs:
		if (w.pos as Vector3).distance_to(Vector3(p.x, 0, p.z)) < r + float(w.r) * 0.6 and float(w.life) > 0.4:
			w.life = 0.35
			n += 1
	return n


func clear_webs() -> void:
	for w in webs:
		w.life = minf(float(w.life), 0.5)


# ── 먼지 · 부스러기 ─────────────────────────────────────

## 부드러운 먼지 구름 (빛을 받지 않는 반투명 판)
func dust(p: Vector3, size: float, c: Color, vel := Vector3(0, 0.5, 0), life := 1.5) -> void:
	if _dust.size() > 260:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _dust_mesh
	mi.material_override = _dust_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("tint", c)
	mi.set_instance_shader_parameter("fade", 1.0)
	add_child(mi)
	mi.global_position = p
	mi.scale = Vector3.ONE * size * 0.4
	_dust.append([mi, vel + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3)), life, life, size])


## 벽면에서 부스러기가 흘러내린다 (보스가 벽 속을 지나갈 때의 단서)
func wall_trickle(w: String, u: float, y: float) -> void:
	var n := wall_n(w)
	var p := wall_point(w, u, y) + n * 0.4
	for i in 4:
		dust(p + Vector3(randf_range(-1.5, 1.5), randf_range(-1, 1), randf_range(-1.5, 1.5)) * Vector3(absf(n.z) + 0.2, 1, absf(n.x) + 0.2), randf_range(1.0, 2.2), Color(0.28, 0.27, 0.27, 0.32), Vector3(0, -2.5, 0) + n * 0.5, 1.6)
	FX.sparks(p, 6, [Color(0.35, 0.33, 0.32), Color(0.2, 0.2, 0.21)], 2.0, 1.2, -14.0, 0.08)


# ── 매 프레임 ───────────────────────────────────────────

func update(dt: float, cam: Camera3D, player_pos: Vector3) -> void:
	_t += dt
	# 기둥 가림 구멍: 플레이어 화면 위치 · 깊이
	if cam:
		var sp := cam.unproject_position(player_pos + Vector3(0, 0.9, 0))
		var vs := cam.get_viewport().get_visible_rect().size
		occl_mat.set_shader_parameter("occl_uv", sp / vs)
		var vd := -(cam.global_transform.affine_inverse() * (player_pos + Vector3(0, 0.9, 0))).z
		occl_mat.set_shader_parameter("occl_depth", vd)
		occl_mat.set_shader_parameter("occl_on", 1.0 if not cam.is_position_behind(player_pos) else 0.0)
	occl_mat.set_shader_parameter("alarm", alarm)
	wall_mat.set_shader_parameter("alarm", alarm)
	# 거미줄 판 수명
	var i := webs.size() - 1
	while i >= 0:
		var w: Dictionary = webs[i]
		w.age = float(w.age) + dt
		w.life = float(w.life) - dt
		var mi := w.mi as MeshInstance3D
		var f := clampf(float(w.age) / 0.25, 0.0, 1.0) * clampf(float(w.life) / 0.5, 0.0, 1.0)
		mi.set_instance_shader_parameter("fade", f)
		if float(w.life) <= 0.0:
			mi.queue_free()
			webs.remove_at(i)
		i -= 1
	# 먼지
	i = _dust.size() - 1
	while i >= 0:
		var d: Array = _dust[i]
		var mi := d[0] as MeshInstance3D
		d[2] = float(d[2]) - dt
		var v: Vector3 = d[1]
		v *= 1.0 - dt * 0.9
		d[1] = v
		mi.global_position += v * dt
		var k := 1.0 - float(d[2]) / float(d[3])
		mi.scale = Vector3.ONE * float(d[4]) * lerpf(0.4, 1.0, sqrt(k))
		mi.set_instance_shader_parameter("fade", (1.0 - k) * minf(1.0, k * 6.0))
		if cam:
			mi.look_at(cam.global_position, Vector3.UP, true)
		if float(d[2]) <= 0.0:
			mi.queue_free()
			_dust.remove_at(i)
		i -= 1
	# 구멍 속 눈빛
	for g in hole_glows:
		g.k = move_toward(float(g.k), float(g.target), dt * (6.0 if float(g.target) > float(g.k) else 2.5))
		var flick := 0.85 + 0.15 * sin(_t * 23.0 + float(g.ph))
		for m in g.mats:
			(m as StandardMaterial3D).emission_energy_multiplier = float(g.k) * 5.0 * flick
		(g.node as Node3D).visible = float(g.k) > 0.01
		(g.light as OmniLight3D).light_energy = float(g.k) * 2.5
	# 늘어진 가닥 흔들림
	for s in _strands:
		var n := s[0] as Node3D
		n.rotation = Vector3(sin(_t * 0.4 + float(s[1])) * 0.012, 0, cos(_t * 0.33 + float(s[1])) * 0.012)
	for b in beacons:
		var mat := b[0] as StandardMaterial3D
		var on := 0.5 + 0.5 * sin(_t * 2.2 + float(b[1]))
		var c := CYAN.lerp(DANGER, alarm)
		mat.emission = c
		mat.albedo_color = c
		mat.emission_energy_multiplier = lerpf(2.2, 3.5 * (1.0 if fmod(_t * 1.6 + float(b[1]), 1.0) < 0.5 else 0.2), alarm) * (0.7 + 0.3 * on)


## 구멍 i 의 어둠 속에서 눈빛을 켠다 (k 0~1)
func hole_eyes(i: int, k: float) -> void:
	if i >= 0 and i < hole_glows.size():
		hole_glows[i].target = k


func hole_eyes_off() -> void:
	for g in hole_glows:
		g.target = 0.0


# ── 조립 ────────────────────────────────────────────────

func _mesh(m: Mesh, mat: Material, pos: Vector3, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _box(size: Vector3, pos: Vector3, mat: Material, shadow := true) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mesh(b, mat, pos, shadow)


func _build_floor() -> void:
	var fm := ShaderMaterial.new()
	fm.shader = _shader_n(FLOOR_SHADER)
	var pm := PlaneMesh.new()
	pm.size = Vector2(HX * 2.0, HZ * 2.0)
	pm.subdivide_width = 1
	pm.subdivide_depth = 1
	var mi := _mesh(pm, fm, Vector3.ZERO, false)
	mi.name = "Floor"
	# 바닥 아래 받침 (가장자리 틈으로 어둠이 보이지 않게)
	var under := StandardMaterial3D.new()
	under.albedo_color = Color(0.01, 0.01, 0.012)
	_box(Vector3(HX * 2.0 + 40.0, 1.0, HZ * 2.0 + 40.0), Vector3(0, -0.52, 0), under, false)


func _build_walls() -> void:
	wall_mat = ShaderMaterial.new()
	wall_mat.shader = _shader_n(WALL_SHADER)
	for w in ["N", "E", "W"]:
		var n := wall_n(w)
		var half := wall_half(w) + WALL_T
		# 구멍들을 피해 벽을 세로 띠로 자른 뒤, 구멍 위아래를 채운다
		var cuts: Array = []
		for i in HOLES.size():
			var h: Dictionary = HOLES[i]
			if h.wall == w:
				cuts.append([float(h.u) - float(h.w) * 0.5, float(h.u) + float(h.w) * 0.5, float(h.y), float(h.y) + float(h.h)])
		cuts.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
		var xs: Array = [-half]
		for c in cuts:
			xs.append(c[0])
			xs.append(c[1])
		xs.append(half)
		for k in range(0, xs.size(), 2):
			var u0: float = xs[k]
			var u1: float = xs[k + 1]
			if u1 - u0 > 0.01:
				_wall_block(w, u0, u1, 0.0, WALL_H)
		for c in cuts:
			if float(c[2]) > 0.01:
				_wall_block(w, c[0], c[1], 0.0, c[2])
			_wall_block(w, c[0], c[1], c[3], WALL_H)
		# 벽 밑동 (두꺼운 띠 · 경고 줄)
		var base_c := wall_point(w, 0.0, 0.6) + n * 0.25
		var bm := Pal.lit(Color(0.09, 0.09, 0.1))
		var seg := _box(Vector3(half * 2.0, 1.2, 0.5) if absf(n.z) > 0.5 else Vector3(0.5, 1.2, half * 2.0), base_c, bm)
		seg.name = "Skirt" + w
	# 카메라 쪽 남쪽 난간 (낮다)
	var rail := Pal.lit(Color(0.12, 0.125, 0.14))
	_box(Vector3(HX * 2.0 + WALL_T * 2.0, SOUTH_H, WALL_T), Vector3(0, SOUTH_H * 0.5, HZ + WALL_T * 0.5), rail)
	var stripe := Pal.lit(HAZARD, 0.0)
	for k in 28:
		var x := -HX + 1.0 + k * 2.0
		_box(Vector3(0.9, 0.28, 0.06), Vector3(x, SOUTH_H - 0.4, HZ - 0.03), stripe, false).rotation_degrees = Vector3(0, 0, 35)
	# 남쪽 너머: 한 단 낮은 정비 통로 (격자 바닥 · 난간 기둥) 뒤로 어둠
	var deck := Pal.lit(Color(0.06, 0.065, 0.075))
	_box(Vector3(HX * 2.0 + WALL_T * 2.0, 0.4, 14.0), Vector3(0, -1.4, HZ + WALL_T + 7.0), deck, false)
	var grate := Pal.lit(Color(0.1, 0.105, 0.12))
	for k in 14:
		_box(Vector3(HX * 2.0 + WALL_T * 2.0, 0.08, 0.12), Vector3(0, -1.16, HZ + WALL_T + 0.6 + k * 1.0), grate, false)
	for k in 12:
		_box(Vector3(0.25, 3.0, 0.25), Vector3(-HX + k * 5.0, 0.3, HZ + WALL_T + 13.5), rail, false)
	var void_m := StandardMaterial3D.new()
	void_m.albedo_color = Color(0.0, 0.0, 0.0)
	void_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_box(Vector3(HX * 2.0 + 60.0, 1.0, 40.0), Vector3(0, -8.0, HZ + 30.0), void_m, false)


## 벽 한 토막: 벽 좌표 u0~u1 · 높이 y0~y1
func _wall_block(w: String, u0: float, u1: float, y0: float, y1: float) -> void:
	var n := wall_n(w)
	var uc := (u0 + u1) * 0.5
	var size_u := u1 - u0
	var c := wall_point(w, uc, (y0 + y1) * 0.5) - n * WALL_T * 0.5
	var size := Vector3(size_u, y1 - y0, WALL_T) if absf(n.z) > 0.5 else Vector3(WALL_T, y1 - y0, size_u)
	var mi := _box(size, c, wall_mat)
	mi.name = "Wall" + w


func _build_holes() -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.035, 0.037, 0.042)
	dark.roughness = 0.9
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0, 0, 0)
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var frame := Pal.lit(Color(0.2, 0.21, 0.23))
	var stripe := Pal.lit(HAZARD)
	var curtain := StandardMaterial3D.new()
	curtain.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	curtain.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	curtain.albedo_color = Color(0, 0, 0, 0.42)
	curtain.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in HOLES.size():
		var h: Dictionary = HOLES[i]
		var w: String = h.wall
		var n := wall_n(w)
		var side := Vector3(n.z, 0, -n.x) if absf(n.z) > 0.5 else Vector3(0, 0, n.x)
		side = side.normalized()
		var hw := float(h.w)
		var hh := float(h.h)
		var y0 := float(h.y)
		var mouth := wall_point(w, h.u, y0)
		var root := Node3D.new()
		root.name = "Hole%d" % i
		add_child(root)
		# 굴 안쪽: 바닥 · 천장 · 양옆 · 끝 (어둡다)
		var depth := TUNNEL_D
		var ctr := mouth - n * (depth * 0.5 + WALL_T * 0.0)
		var axis_size := func(along_u: float, y: float, along_n: float) -> Vector3:
			return Vector3(along_u, y, along_n) if absf(n.z) > 0.5 else Vector3(along_n, y, along_u)
		_box(axis_size.call(hw + 2.0, 0.6, depth), ctr + Vector3(0, -0.3, 0), dark, false)
		_box(axis_size.call(hw + 2.0, 0.6, depth), ctr + Vector3(0, hh + 0.3, 0), dark, false)
		for s in [-1.0, 1.0]:
			_box(axis_size.call(0.6, hh, depth), ctr + side * s * (hw * 0.5 + 0.3) + Vector3(0, hh * 0.5, 0), dark, false)
		_box(axis_size.call(hw, hh, 0.4), mouth - n * depth + Vector3(0, hh * 0.5, 0), black, false)
		# 어둠 막: 안으로 들어갈수록 겹겹이 어두워진다 (보스가 이 속으로 사라진다)
		for k in 4:
			var q := QuadMesh.new()
			q.size = Vector2(hw, hh)
			var cm := _mesh(q, curtain, mouth - n * (2.2 + k * 2.6) + Vector3(0, hh * 0.5, 0), false)
			cm.look_at(cm.global_position + n, Vector3.UP)
		# 입구 테두리: 두꺼운 철골 + 경고 줄
		var fr := 0.7
		_box(axis_size.call(hw + fr * 2.0, fr, fr), mouth + n * 0.2 + Vector3(0, hh + fr * 0.5, 0), frame)
		if y0 > 0.5:
			_box(axis_size.call(hw + fr * 2.0, fr, fr * 1.6), mouth + n * 0.4 + Vector3(0, -fr * 0.5, 0), frame)
		for s in [-1.0, 1.0]:
			_box(axis_size.call(fr, hh, fr), mouth + n * 0.2 + side * s * (hw * 0.5 + fr * 0.5) + Vector3(0, hh * 0.5, 0), frame)
			for k in 4:
				var st := _box(axis_size.call(0.12, 0.7, 0.08), mouth + n * 0.58 + side * s * (hw * 0.5 + fr * 0.5) + Vector3(0, 0.8 + k * 1.3, 0), stripe, false)
				st.rotation_degrees = Vector3(0, 0, 0)
		# 뜯겨 나간 창살 몇 개 (보스가 찢고 나온 자국)
		for k in 3:
			var bar := _box(axis_size.call(0.18, hh * randf_range(0.3, 0.6), 0.18), mouth + n * 0.1 + side * randf_range(-hw * 0.45, hw * 0.45) + Vector3(0, hh - 0.8, 0), frame)
			bar.rotate(n.cross(Vector3.UP).normalized() if absf(n.y) < 0.9 else Vector3.RIGHT, randf_range(-0.6, 0.6))
		# 어둠 속 눈빛 (평소 꺼짐): 청록 눈 셋
		var eyes := Node3D.new()
		root.add_child(eyes)
		eyes.global_position = mouth - n * 6.0 + Vector3(0, RIDE + 0.6, 0)
		var mats: Array = []
		for e in 3:
			var em := StandardMaterial3D.new()
			em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			em.albedo_color = CYAN
			em.emission_enabled = true
			em.emission = CYAN
			em.emission_energy_multiplier = 0.0
			var sm := SphereMesh.new()
			sm.radius = 0.32
			sm.height = 0.64
			var emi := MeshInstance3D.new()
			emi.mesh = sm
			emi.material_override = em
			emi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			eyes.add_child(emi)
			emi.position = side * (float(e) - 1.0) * 0.8 + Vector3(0, absf(float(e) - 1.0) * 0.12, 0)
			mats.append(em)
		var gl := OmniLight3D.new()
		gl.light_color = CYAN
		gl.light_energy = 0.0
		gl.omni_range = 7.0
		eyes.add_child(gl)
		gl.position = n * 1.5
		eyes.visible = false
		hole_glows.append({"node": eyes, "mats": mats, "k": 0.0, "target": 0.0, "ph": randf() * 10.0, "light": gl})


func _build_pillars() -> void:
	occl_mat = ShaderMaterial.new()
	occl_mat.shader = _shader_n(PILLAR_SHADER)
	var shadow_mat := StandardMaterial3D.new()
	var base_mat := Pal.lit(Color(0.13, 0.135, 0.15))
	var stripe := Pal.lit(HAZARD)
	for i in PILLARS.size():
		var c := pillar_pos(i)
		var r := pillar_r(i)
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = PILLAR_H
		cm.radial_segments = 28
		cm.rings = 1
		var mi := _mesh(cm, occl_mat, c + Vector3(0, PILLAR_H * 0.5, 0), false)
		mi.name = "Pillar%d" % i
		mi.set_instance_shader_parameter("seed", float(i) * 7.3)
		mi.set_instance_shader_parameter("radius", r)
		# 그림자는 따로 (가림 구멍이 그림자에 구멍을 내지 않게)
		var sh := MeshInstance3D.new()
		sh.mesh = cm
		sh.material_override = shadow_mat
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		add_child(sh)
		sh.position = c + Vector3(0, PILLAR_H * 0.5, 0)
		# 밑동 받침 (팔각) + 경고 띠
		var pb := CylinderMesh.new()
		pb.top_radius = r + 0.45
		pb.bottom_radius = r + 0.75
		pb.height = 1.1
		pb.radial_segments = 8
		pb.rings = 1
		var base := _mesh(pb, base_mat, c + Vector3(0, 0.55, 0))
		base.rotation.y = PI / 8.0
		for k in 8:
			var a := TAU * k / 8.0 + PI / 8.0
			var d := Vector3(cos(a), 0, sin(a))
			var st := _box(Vector3(0.5, 0.18, 0.08), c + d * (r + 0.66) + Vector3(0, 0.75, 0), stripe, false)
			st.look_at(st.global_position + d, Vector3.UP)
			st.rotate_object_local(Vector3.FORWARD, 0.6)
		# 위로 이어지는 신호등: 몇 m 마다 하나씩, 높을수록 안개에 묻힌다 (끝이 보이지 않는 높이감)
		for k in 9:
			var y := 7.0 + k * 9.0 + float(i % 3) * 2.0
			var a := float(i) * 1.7 + k * 2.1
			var d := Vector3(cos(a), 0, sin(a))
			var lm := StandardMaterial3D.new()
			lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			lm.albedo_color = CYAN
			lm.emission_enabled = true
			lm.emission = CYAN
			lm.emission_energy_multiplier = 2.2
			var lb := BoxMesh.new()
			lb.size = Vector3(0.28, 0.5, 0.12)
			var lmi := _mesh(lb, lm, c + d * (r + 0.06) + Vector3(0, y, 0), false)
			lmi.look_at(lmi.global_position + d, Vector3.UP)
			beacons.append([lm, randf() * 6.0])


## 장식: 구석의 오래된 거미줄 · 위에서 늘어진 가닥 · 바닥 잔해
func _build_decor() -> void:
	var silk := StandardMaterial3D.new()
	silk.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	silk.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	silk.albedo_color = Color(0.78, 0.84, 0.88, 0.22)
	silk.cull_mode = BaseMaterial3D.CULL_DISABLED
	silk.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	# 북쪽 두 구석 · 구멍 위쪽 모서리에 큰 방사형 거미줄
	var corners := [
		[Vector3(-HX, 7.0, -HZ), Vector3(1, 0, 1), 7.0],
		[Vector3(HX, 6.0, -HZ), Vector3(-1, 0, 1), 6.0],
		[Vector3(-HX, 4.0, HZ - 4.0), Vector3(1, 0, 0), 4.0],
		[Vector3(HX, 5.0, HZ - 6.0), Vector3(-1, 0, 0), 4.5],
	]
	for c in corners:
		var mi := MeshInstance3D.new()
		mi.mesh = _web_mesh(float(c[2]), 14, 9, randi())
		mi.material_override = silk
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = c[0]
		mi.look_at(mi.global_position + (c[1] as Vector3), Vector3.UP)
	# 기둥과 벽 사이 · 구멍 입구에 걸친 찢어진 거미줄
	for i in HOLES.size():
		if randf() < 0.6:
			var h: Dictionary = HOLES[i]
			var mi := MeshInstance3D.new()
			mi.mesh = _web_mesh(float(h.w) * 0.45, 10, 6, randi())
			mi.material_override = silk
			add_child(mi)
			var n := wall_n(h.wall)
			mi.global_position = hole_center(i) + n * 0.5 + Vector3(0, float(h.h) * 0.3, 0)
			mi.look_at(mi.global_position + n, Vector3.UP)
			mi.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	# 위에서 늘어진 가닥: 어둠에서 내려와 바닥 근처에서 끊긴다
	for k in 22:
		var p := Vector3(randf_range(-HX + 2, HX - 2), 0, randf_range(-HZ + 2, HZ - 6))
		var len := randf_range(14.0, 40.0)
		var root := Node3D.new()
		add_child(root)
		root.position = Vector3(p.x, randf_range(3.0, 9.0) + len, p.z)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.012
		cm.bottom_radius = 0.008
		cm.height = len
		cm.radial_segments = 3
		cm.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = silk
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		mi.position = Vector3(0, -len * 0.5, 0)
		_strands.append([root, randf() * 10.0])
	# 바닥 잔해: 낡은 판재 · 케이블 다발 (벽가에만, 전장 한가운데는 비운다)
	var junk := Pal.lit(Color(0.11, 0.115, 0.13))
	var cable := Pal.lit(Color(0.04, 0.04, 0.045))
	for k in 18:
		var w: String = ["N", "E", "W"][k % 3]
		var u := randf_range(-wall_half(w) + 3.0, wall_half(w) - 3.0)
		var skip := false
		for i in HOLES.size():
			if in_opening(i, w, u, 0.5, -2.0):
				skip = true
		if skip:
			continue
		var p := wall_point(w, u, 0.0) + wall_n(w) * randf_range(0.8, 2.2)
		var b := _box(Vector3(randf_range(0.8, 2.2), randf_range(0.2, 0.6), randf_range(0.6, 1.4)), p + Vector3(0, 0.2, 0), junk)
		b.rotation.y = randf() * TAU
		if randf() < 0.5:
			var cy := CylinderMesh.new()
			cy.top_radius = 0.12
			cy.bottom_radius = 0.12
			cy.height = randf_range(2.0, 5.0)
			var c2 := _mesh(cy, cable, p + Vector3(randf_range(-1, 1), 0.12, randf_range(-1, 1)))
			c2.rotation = Vector3(PI * 0.5, randf() * TAU, 0)


## 방사형 거미줄 메시 (평면 XY, 반지름 r): 방사선 spokes 개 + 나선 rings 바퀴. 가는 띠로 만든다.
static func _web_mesh(r: float, spokes: int, rings: int, sd: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.025 * r / 5.0 + 0.012
	var angs: Array = []
	for s in spokes:
		angs.append(TAU * s / spokes + rng.randf_range(-0.12, 0.12))
	var lens: Array = []
	for s in spokes:
		lens.append(r * rng.randf_range(0.7, 1.0))
	var ribbon := func(a: Vector3, b: Vector3) -> void:
		var d := (b - a).normalized()
		var side := Vector3(-d.y, d.x, 0) * w
		st.add_vertex(a - side)
		st.add_vertex(b - side)
		st.add_vertex(b + side)
		st.add_vertex(a - side)
		st.add_vertex(b + side)
		st.add_vertex(a + side)
	for s in spokes:
		var a: float = angs[s]
		ribbon.call(Vector3.ZERO, Vector3(cos(a), sin(a), 0) * float(lens[s]))
	for k in rings:
		var rr := r * (0.12 + 0.86 * float(k) / rings)
		for s in spokes:
			var a0: float = angs[s]
			var a1: float = angs[(s + 1) % spokes]
			var r0 := minf(rr * rng.randf_range(0.94, 1.04), float(lens[s]))
			var r1 := minf(rr * rng.randf_range(0.94, 1.04), float(lens[(s + 1) % spokes]))
			if rng.randf() < 0.12:
				continue                 # 군데군데 끊긴 실
			# 실은 살짝 처진다 (가운데를 바깥쪽으로 덜 당긴 곡선)
			var p0 := Vector3(cos(a0), sin(a0), 0) * r0
			var p1 := Vector3(cos(a1), sin(a1), 0) * r1
			var mid := (p0 + p1) * 0.5 * 0.93
			ribbon.call(p0, mid)
			ribbon.call(mid, p1)
	return st.commit()


# ── 셰이더 ──────────────────────────────────────────────

const NOISE := """
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 grad2(vec2 p) { float a = hash2(p) * 6.2831853; return vec2(cos(a), sin(a)); }
float gnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = dot(grad2(i), f);
	float b = dot(grad2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(grad2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(grad2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return 0.5 + 0.5 * mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 1.4;
}
float gfbm(vec2 p) {
	float s = 0.0; float a = 0.5;
	mat2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 4; i++) { s += gnoise(p) * a; p = r * p * 2.03 + vec2(3.1, 1.7); a *= 0.5; }
	return s / 0.94;
}
"""

## 바닥: 4m 강철 갑판(이음매 · 볼트 · 미끄럼 방지 무늬) · 녹과 기름 얼룩(젖어 번들거린다) · 벽가 경고 줄 · 오래된 발자국 긁힘
const FLOOR_SHADER := """
varying vec3 wp;
uniform float hx = 27.0;
uniform float hz = 23.0;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float line(float d, float w) { return 1.0 - smoothstep(0.0, w, abs(d)); }
void fragment() {
	vec2 p = wp.xz;
	vec2 cell = floor(p / 4.0);
	vec2 f = fract(p / 4.0);
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)) * 4.0;
	float n = gfbm(p * 0.18);
	float n2 = gnoise(p * 2.3);
	vec3 base = mix(vec3(0.075, 0.08, 0.09), vec3(0.12, 0.125, 0.135), n);
	base *= 0.92 + 0.12 * hash2(cell);
	// 미끄럼 방지 무늬 (다이아몬드 돌기)
	vec2 dp = fract(vec2(p.x + p.y, p.x - p.y) * 2.2) - 0.5;
	float dia = smoothstep(0.32, 0.22, length(dp * vec2(1.0, 3.2)));
	base *= 1.0 + dia * 0.08 * step(0.5, hash2(cell + 7.0));
	// 이음매 · 볼트
	base *= mix(0.45, 1.0, smoothstep(0.02, 0.09, edge));
	vec2 bf = abs(f - 0.5) * 4.0;
	float bolt = smoothstep(0.13, 0.08, length(vec2(bf.x, bf.y) - vec2(1.72)));
	base = mix(base, vec3(0.2, 0.2, 0.21), bolt);
	// 녹 · 기름 얼룩
	float rust = smoothstep(0.58, 0.78, gfbm(p * 0.09 + vec2(4.0, 9.0)));
	base = mix(base, vec3(0.13, 0.07, 0.04), rust * 0.55);
	float oil = smoothstep(0.62, 0.75, gfbm(p * 0.14 + vec2(-3.0, 2.0)));
	base = mix(base, base * 0.35, oil);
	// 긁힌 자국 (보스가 다니며 남긴 긴 상처)
	float scr = line(fract(p.x * 0.31 + gnoise(p * 0.2) * 2.0) - 0.5, 0.012) * smoothstep(0.55, 0.7, gnoise(p * 0.25 + 11.0));
	base += scr * 0.05;
	// 벽가 경고 줄 (노랑·검정 사선)
	float wd = min(hx - abs(p.x), hz - abs(p.y));
	float band = step(wd, 1.6) * step(0.6, wd);
	float diag = step(0.5, fract((p.x + p.y) * 0.6));
	vec3 haz = mix(vec3(0.03), vec3(0.62, 0.45, 0.07), diag) * (0.75 + 0.25 * n);
	base = mix(base, haz, band * (1.0 - rust * 0.6));
	ALBEDO = base;
	ROUGHNESS = mix(0.72, 0.16, oil) - dia * 0.05;
	METALLIC = 0.45;
	SPECULAR = mix(0.4, 0.8, oil);
}
"""

## 벽: 세로 장갑판 · 가로 보강 늑재 · 녹물 줄기 · 높이 올라갈수록 어둠 · 2페이즈 경보등 반사
const WALL_SHADER := """
uniform float alarm = 0.0;
uniform float near_a = 8.0;
uniform float near_b = 15.0;
varying vec3 wp;
varying vec3 wn;
float bayer4w(vec2 p) {
	int x = int(mod(p.x, 4.0)); int y = int(mod(p.y, 4.0));
	float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[x + y * 4] + 0.5) / 16.0;
}
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	if (1.0 - smoothstep(near_a, near_b, length(VERTEX)) > bayer4w(FRAGCOORD.xy)) discard;
	float u = abs(wn.z) > 0.5 ? wp.x : wp.z;
	float y = wp.y;
	vec2 q = vec2(u, y);
	float pu = fract(u / 3.0);
	float py = fract(y / 6.0);
	float seam = min(pu, 1.0 - pu) * 3.0;
	float rib = min(py, 1.0 - py) * 6.0;
	float n = gfbm(q * 0.12 + vec2(wn.x * 5.0, wn.z * 3.0));
	vec3 base = mix(vec3(0.07, 0.075, 0.085), vec3(0.13, 0.135, 0.15), n);
	base *= 0.9 + 0.15 * hash2(floor(q / vec2(3.0, 6.0)));
	base *= mix(0.4, 1.0, smoothstep(0.02, 0.1, seam));
	float ribm = 1.0 - smoothstep(0.15, 0.35, rib);
	base = mix(base, vec3(0.16, 0.165, 0.18), ribm * 0.7);
	base *= mix(1.0, 0.55, smoothstep(0.35, 0.5, rib) * (1.0 - smoothstep(0.5, 0.65, rib)) * 0.4);
	// 녹물 줄기
	float streak = smoothstep(0.6, 0.85, gnoise(vec2(u * 1.3, y * 0.05) + 3.0)) * (1.0 - py);
	base = mix(base, vec3(0.12, 0.06, 0.035), streak * 0.5);
	// 높이에 따른 어둠 (끝이 보이지 않게)
	float dark = exp(-max(y - 6.0, 0.0) / 16.0);
	base *= dark;
	// 바닥 근처 그을음
	base *= mix(0.6, 1.0, smoothstep(0.0, 2.5, y));
	ALBEDO = base;
	ROUGHNESS = 0.7;
	METALLIC = 0.35;
	// 경보등: 붉은 빛이 위아래로 훑고 지나간다
	float sweep = pow(0.5 + 0.5 * sin(TIME * 3.0 - y * 0.25 + u * 0.05), 6.0);
	EMISSION = vec3(0.9, 0.05, 0.03) * alarm * sweep * 0.25 * dark;
}
"""

## 기둥: 둘레를 감는 보강 띠 · 세로 리브 · 높이에 따라 어둠으로 사라짐.
## 카메라와 플레이어 사이에 있으면 플레이어 둘레만 점묘로 비운다 (occl_*).
const PILLAR_SHADER := """
instance uniform float seed = 0.0;
instance uniform float radius = 2.0;
uniform vec2 occl_uv = vec2(0.5);
uniform float occl_depth = 0.0;
uniform float occl_on = 0.0;
uniform float occl_r = 0.13;
uniform float alarm = 0.0;
uniform float near_a = 9.0;
uniform float near_b = 17.0;
varying vec3 wp;
varying vec3 lp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lp = VERTEX;
}
float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0)); int y = int(mod(p.y, 4.0));
	int i = x + y * 4;
	float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}
void fragment() {
	// 카메라 곁을 지나 위로 솟는 부분은 점묘로 지운다 (화면을 덮지 않게)
	float near_k = 1.0 - smoothstep(near_a, near_b, length(VERTEX));
	if (near_k > bayer4(FRAGCOORD.xy)) discard;
	// 가림 구멍
	if (occl_on > 0.5 && -VERTEX.z < occl_depth - 1.2) {
		vec2 d = (SCREEN_UV - occl_uv) * vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0);
		float k = 1.0 - smoothstep(occl_r * 0.55, occl_r, length(d));
		if (k * 0.92 > bayer4(FRAGCOORD.xy)) discard;
	}
	float ang = atan(lp.z, lp.x);
	float y = wp.y;
	float ring = fract((y + seed) / 7.0);
	float band = smoothstep(0.0, 0.03, ring) * (1.0 - smoothstep(0.08, 0.11, ring));
	float rib = abs(fract(ang / 6.2831853 * 16.0) - 0.5);
	float n = gfbm(vec2(ang * radius, y) * 0.25 + seed);
	vec3 base = mix(vec3(0.085, 0.09, 0.1), vec3(0.15, 0.155, 0.17), n);
	base *= mix(0.75, 1.0, smoothstep(0.02, 0.08, rib));
	base = mix(base, vec3(0.2, 0.205, 0.22), band);
	float rust = smoothstep(0.6, 0.8, gnoise(vec2(ang * 3.0, y * 0.08) + seed));
	base = mix(base, vec3(0.13, 0.065, 0.04), rust * 0.5);
	float dark = exp(-max(y - 8.0, 0.0) / 22.0);
	base *= dark;
	ALBEDO = base;
	ROUGHNESS = 0.62 - band * 0.2;
	METALLIC = 0.5;
	EMISSION = vec3(0.9, 0.05, 0.03) * alarm * pow(0.5 + 0.5 * sin(TIME * 3.0 - y * 0.25), 6.0) * 0.18 * dark;
}
"""

## 바닥 거미줄 판: 방사선 + 나선 실, 가운데가 촘촘하고 끈적하게 번들거린다
const WEB_FLOOR_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
instance uniform float seed = 0.0;
instance uniform float fade = 1.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float spokes = 11.0 + floor(fract(seed) * 4.0);
	float sa = abs(fract(a / 6.2831853 * spokes + seed) - 0.5) * 2.0;
	float spoke = 1.0 - smoothstep(0.0, 0.05 / max(r, 0.08), sa);
	float sp = abs(fract(r * 9.0 - a / 6.2831853 + seed * 0.37) - 0.5);
	float spiral = 1.0 - smoothstep(0.03, 0.08, sp);
	float silk = max(spoke * 0.9, spiral * 0.75) * (1.0 - smoothstep(0.82, 1.0, r));
	float glue = (1.0 - smoothstep(0.0, 0.45, r)) * 0.18;
	ALBEDO = vec3(0.86, 0.92, 0.95) * (1.0 + spiral * 0.3);
	ALPHA = clamp(silk * 0.65 + glue, 0.0, 1.0) * fade;
}
"""

const DUST_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
instance uniform vec4 tint : source_color = vec4(0.3, 0.3, 0.3, 0.3);
instance uniform float fade = 1.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float soft = 1.0 - smoothstep(0.2, 1.0, r);
	ALBEDO = tint.rgb;
	ALPHA = soft * soft * tint.a * fade;
}
"""
