class_name GroundBreak
extends Node3D
## 바닥 파괴 연출: 스킬·강타가 바닥을 깨뜨려 판이 들리고, 암석이 솟고, 바닥이 찌그러지고, 파편이 튄다.
## 판정 없음 (연출 전용). 조각은 그 자리 바닥 재질을 그대로 써서 무늬·줄눈·조명 풀까지 바닥과 똑같이 보인다.
##
## 부르는 곳: GroundBreak.burst(지면 위치, 세기 0~1, 방향)
##   E 도약 내려찍기 1.0 · 검 콤보 무거운 일격(heavy) 0.55 · 미사일 착탄 0.3 · 허수아비 씬 F4 미리보기
## 스타일은 static (씬을 다시 불러도 유지): 허수아비 씬 = / Shift+= , 실행 인자 --ground=slab|spike|buckle|scatter|mix|off
##
## 스타일
##  CRUMBLE 깨짐 튐 (기본) — 깨진 구멍 + 가장자리 작게 들린 판 + 파편 튐 (암석 솟음에서 솟는 기둥만 뺀 것)
##  SLAB    판 들림   — 충격 지점을 중심으로 바닥이 방사형 판으로 갈라지고, 안쪽 판일수록 바깥 모서리를 축으로 높이 들린다 (틈은 어두운 금)
##  SPIKE   암석 솟음 — 각진 기둥 조각들이 바깥으로 기울어 바닥을 뚫고 솟았다가 다시 들어간다 (가장자리 작은 판)
##  BUCKLE  찌그러짐 — 바닥 면 자체가 물결처럼 튀어 오르며 퍼지고, 주름진 둔덕 고리와 가운데 금으로 굳었다가 펴진다
##  SCATTER 파편 튐   — 바닥 조각 덩어리들이 공격 방향으로 쏟아져 튀고 구르다 멈춘다 (가운데 깨진 구멍)
##  MIX     대파괴    — 판 들림 + 가운데 암석 + 파편 튐을 한꺼번에
##
## 지나간 자리 흔적 (trail): 돌진(일격참 · 관통 일격 · 기 모으기 돌진) · 2단 대시 휠윈드 · Q 합체 휠윈드 동안
## 일정 거리마다 작은 찌그러짐 + 작은 파편 몇 개 + 짧은 금을 남긴다. Player 가 매 틱 GroundBreak.follow 를 부른다. OFF 면 없음

const STYLES := [
	{"id": "crumble", "name": "CRUMBLE", "ko": "깨짐 튐", "desc": "깨진 구멍 · 가장자리 작게 들린 판 · 파편이 튀고 구른다 (솟는 암석 없음)"},
	{"id": "slab", "name": "SLAB", "ko": "판 들림", "desc": "방사형으로 갈라진 바닥 판이 바깥 모서리를 축으로 들린다 · 틈은 어두운 금"},
	{"id": "spike", "name": "SPIKE", "ko": "암석 솟음", "desc": "각진 기둥 조각이 바깥으로 기울어 바닥을 뚫고 솟았다 들어간다"},
	{"id": "buckle", "name": "BUCKLE", "ko": "찌그러짐", "desc": "바닥 면이 물결처럼 튀어 퍼지고 주름진 둔덕 고리로 굳었다 펴진다"},
	{"id": "scatter", "name": "SCATTER", "ko": "파편 튐", "desc": "바닥 덩어리가 공격 방향으로 쏟아져 튀고 구르다 멈춘다"},
	{"id": "mix", "name": "MIX", "ko": "대파괴", "desc": "판 들림 + 가운데 암석 + 파편 튐 한꺼번에"},
	{"id": "off", "name": "OFF", "ko": "끔", "desc": "바닥 파괴 연출 없음 (예전 그대로)"},
]

const MAX_PIECES := 460          # 넘으면 가장 오래된 연출부터 지운다
const MAX_BURSTS := 30          # 흔적은 가벼워 큰 연출과 같이 세도 넉넉하게
const BUDGET := 5.0              # 초당 새 연출 수 상한 (미사일 일제 사격이 한 프레임에 조각을 수백 개 만들지 않게)
const POP := 0.09                # 판이 들리는 시간
const SINK := 0.55               # 끝에 바닥 속으로 가라앉는 시간
const WAVE_V := 26.0             # 균열이 퍼지는 속도 (m/s): 바깥 판일수록 늦게 들린다
const GRAV := 24.0
const HOLE_COL := Color(0.045, 0.035, 0.1, 0.92)
const CRACK_COL := Color(0.05, 0.04, 0.12, 0.8)
const TRAIL_BUDGET := 14.0       # 흔적: 초당 상한 (큰 연출 예산과 따로)
const TRAIL_LIFE := 1.7
const TRAIL_AMP := 0.38          # 흔적 찌그러짐 높이 배율 (살짝)
const TRAIL_RINGS := 6           # 흔적 찌그러짐은 가벼운 격자
const TRAIL_SEGS := 18
const DUST: Array[Color] = [Color(0.75, 0.8, 0.95), Color(0.6, 0.65, 0.85), Color(0.32, 0.34, 0.5), Color(0.22, 0.24, 0.36)]

static var style := _arg_style()
static var inst: GroundBreak
static var _decal_mat: ShaderMaterial
static var _fallback: StandardMaterial3D

enum { SLAB, SPIKE, CHUNK }


class Piece:
	var node: MeshInstance3D
	var kind := 0
	var delay := 0.0
	var base := Vector3.ZERO      # 판: 경첩(바깥 모서리) · 기둥: 밑동 · 덩어리: 현재 위치
	var axis := Vector3.RIGHT     # 판: 들리는 회전축
	var ang := 0.0                # 판: 최대 기울기 · 기둥: (쓰지 않음)
	var lift := 0.0               # 판: 들리는 높이 · 기둥: 길이
	var basis := Basis.IDENTITY   # 기둥: 기울기 · 덩어리: 현재 회전
	var vel := Vector3.ZERO
	var spin_axis := Vector3.UP
	var spin := 0.0
	var size := 0.1
	var rest := false


class Burst:
	var t := 0.0
	var life := 2.4
	var pieces: Array[Piece] = []
	var decal: MeshInstance3D
	var center := Vector3.ZERO
	var power := 1.0
	var fmat: Material             # 그 자리 바닥 재질 (안 들린 판은 이것 그대로라 경계가 보이지 않는다)
	# 찌그러짐
	var buckle: MeshInstance3D
	var im: ImmediateMesh
	var R := 2.0
	var noise := PackedFloat32Array()
	var creases := 6
	var phase := 0.0
	var built_final := false
	var rings := 14
	var segs := 40
	var trail := false
	var light := Vector3.UP         # 해 쪽 방향 (주름 명암 계산)


var bursts: Array[Burst] = []
var _budget := BUDGET
var _trail_budget := TRAIL_BUDGET
var _trail_last := {}           # 흔적 출처 → 마지막 자리 (Vector3), 없으면 지금 안 지나가는 중
var _trail_tick := {}           # 흔적 출처 → 제자리에서 도는 동안의 시간 누적
var _floors: Array[MeshInstance3D] = []
var _floors_ok := false
var _piece_mats := {}           # 바닥 재질 id → 조각 재질 (씬마다 이 노드와 함께 사라진다)

const PIECE_VALUE := 1.32       # 조각은 바닥보다 밝게 (들린 판·파편이 바닥 위에서 읽히게. 원화의 흰 조각)
const PIECE_SHADE := 0.62       # 그림자 쪽에 남는 해의 몫 (바닥 0.36 이면 기운 면이 짙은 남색으로 죽는다)


static func _arg_style() -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ground="):
			var id := a.substr(9)
			for i in STYLES.size():
				if STYLES[i].id == id:
					return i
	return 0


static func current() -> Dictionary:
	return STYLES[style]


static func use_id(id: String) -> void:
	for i in STYLES.size():
		if STYLES[i].id == id:
			style = i


static func cycle(step: int) -> void:
	style = (style + step + STYLES.size()) % STYLES.size()


static func piece_count() -> int:
	if not is_instance_valid(inst):
		return 0
	var n := 0
	for b in inst.bursts:
		n += b.pieces.size()
	return n


## 연출 하나. pos 는 지면 위치(높이는 다시 잰다), power 0~1, dir 은 공격 방향(수평, 없으면 사방). id 를 주면 그 스타일
static func burst(pos: Vector3, power := 1.0, dir := Vector3.ZERO, id := "") -> void:
	var s: String = id if id != "" else str(STYLES[style].id)
	if s == "off" or not is_instance_valid(Main.inst) or not Main.inst.is_inside_tree():
		return
	if not is_instance_valid(inst):
		inst = GroundBreak.new()
		inst.name = "GroundBreak"
		Main.inst.add_child(inst)
	inst._spawn(pos, clampf(power, 0.05, 1.5), dir, s)


func _exit_tree() -> void:
	if inst == self:
		inst = null


func _spawn(pos: Vector3, power: float, dir: Vector3, s: String) -> void:
	if _budget < 1.0:
		return
	_budget -= 1.0
	if WorldFlow.active():
		return        # 흐르는 씬(추격 보스전)은 도로가 움직여 바닥에 붙은 조각이 어긋난다
	var g := Vector3(pos.x, Main.gy(pos), pos.z)
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.ZERO
	var b := Burst.new()
	b.center = g
	b.power = power
	var fmat := _floor_mat(g)
	var mat := _piece_mat(fmat)
	b.fmat = fmat
	var decal := ImmediateMesh.new()
	decal.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	match s:
		"crumble":
			b.life = 2.7
			_hole(decal, g, 0.35 + 0.5 * power, 13, 0.0)
			_slabs(b, mat, decal, g, power * 0.55, 0.35)
			_chunks(b, mat, g, power, dir, 1.0)
			_dust(g, power * 0.8)
		"slab":
			b.life = 2.4
			_slabs(b, mat, decal, g, power, 1.0)
			_chunks(b, mat, g, power * 0.35, dir, 0.6)
			_dust(g, power)
		"spike":
			b.life = 1.7
			_spikes(b, mat, decal, g, power, dir, 1.0)
			_slabs(b, mat, decal, g, power * 0.55, 0.35)
			_dust(g, power * 0.8)
		"buckle":
			b.life = 2.6
			_buckle(b, fmat, decal, g, power)
		"scatter":
			b.life = 2.9
			_hole(decal, g, (0.3 + 0.35 * power), 13, 0.0)
			_cracks(decal, g, 1.0 + 1.6 * power, 6 + randi() % 3, 0.04)
			_chunks(b, mat, g, power, dir, 1.0)
			_dust(g, power * 0.7)
		"mix":
			b.life = 2.6
			_slabs(b, mat, decal, g, power, 1.0)
			_spikes(b, mat, decal, g, power * 0.7, dir, 0.55)
			_chunks(b, mat, g, power * 0.8, dir, 0.9)
			_dust(g, power * 1.2)
	decal.surface_end()
	if decal.get_surface_count() > 0:
		var mi := MeshInstance3D.new()
		mi.mesh = decal
		mi.material_override = _decal_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		b.decal = mi
	bursts.append(b)
	var crack := Sfx.play("clank", 0.08, -9.0 + 4.0 * minf(power, 1.0))
	if crack:
		crack.pitch_scale = randf_range(0.42, 0.55)
	_trim()


## 너무 많으면 가장 오래된 연출부터 지운다
func _trim() -> void:
	while bursts.size() > MAX_BURSTS or (bursts.size() > 1 and piece_count() > MAX_PIECES):
		_free_burst(bursts.pop_front())


func _free_burst(b: Burst) -> void:
	for pc in b.pieces:
		if is_instance_valid(pc.node):
			pc.node.queue_free()
	b.pieces.clear()
	if is_instance_valid(b.decal):
		b.decal.queue_free()
	if is_instance_valid(b.buckle):
		b.buckle.queue_free()


# ── 바닥 재질 ───────────────────────────────────────────

## 그 자리 바닥 재질 (방마다 줄눈 위상·색이 다르다). 바닥 메시를 못 찾으면 비슷한 단색
func _floor_mat(p: Vector3) -> Material:
	var map: ArenaMap = Main.inst.map if is_instance_valid(Main.inst) else null
	if map and (not _floors_ok or _floors.any(func(m): return not is_instance_valid(m))):
		_floors.clear()
		for c in map.get_children():
			var mi := c as MeshInstance3D
			if mi and mi.material_override is ShaderMaterial and (mi.layers & MechDecals.RECEIVER) != 0 and mi.get_aabb().size.y < 1.2:
				_floors.append(mi)
		_floors_ok = true
	for mi in _floors:
		var bb := mi.global_transform * mi.get_aabb()
		if p.x >= bb.position.x and p.x <= bb.end.x and p.z >= bb.position.z and p.z <= bb.end.z:
			return mi.material_override
	if _fallback == null:
		_fallback = StandardMaterial3D.new()
		_fallback.albedo_color = Color(0.27, 0.29, 0.42)
		_fallback.roughness = 0.5
	return _fallback


## 바닥 재질을 복제해 밝기만 올린 조각 재질
func _piece_mat(src: Material) -> Material:
	var id := src.get_instance_id()
	if not _piece_mats.has(id):
		var m := src.duplicate() as Material
		var sm := m as ShaderMaterial
		if sm:
			for key in ["floor_value", "lift"]:
				var v: Variant = sm.get_shader_parameter(key)
				if v != null:
					sm.set_shader_parameter(key, float(v) * PIECE_VALUE)
			sm.set_shader_parameter("shade_floor", PIECE_SHADE)
			BrawlLook.track_pool(sm)
		elif m is StandardMaterial3D:
			(m as StandardMaterial3D).albedo_color = (m as StandardMaterial3D).albedo_color * PIECE_VALUE
		_piece_mats[id] = m
	return _piece_mats[id]


## 찌그러짐 재질: 바닥 셰이더에 정점 색(주름 명암)을 곱한 것. 셀 셰이딩은 완만한 경사의 명암을 지워 둔덕이 안 보이므로
## 해를 향한 면은 밝게, 등진 면·골은 어둡게 정점 색으로 과장한다. 바닥 셰이더가 아니면 조각 재질
static var _bk_shaders := {}     # 바닥 셰이더 id → 정점 색 셰이더 (바닥 셰이더 종류만큼, 많아야 3)

func _buckle_mat(src: Material) -> Material:
	var sm := src as ShaderMaterial
	const LINE := "ALBEDO = clamp(col, 0.0, 1.0);"
	if sm == null or sm.shader == null or not sm.shader.code.contains(LINE):
		return _piece_mat(src)
	var key := "bk%d" % sm.get_instance_id()
	if not _piece_mats.has(key):
		var sid := sm.shader.get_instance_id()
		if not _bk_shaders.has(sid):
			var sh := Shader.new()
			sh.code = sm.shader.code.replace(LINE, "ALBEDO = clamp(col * COLOR.rgb, 0.0, 1.0);")
			_bk_shaders[sid] = sh
		var m := ShaderMaterial.new()
		m.shader = _bk_shaders[sid]
		for u in sm.shader.get_shader_uniform_list():
			var n: String = u.name
			m.set_shader_parameter(n, sm.get_shader_parameter(n))
		BrawlLook.track_pool(m)
		_piece_mats[key] = m
	return _piece_mats[key]


## 해 쪽 방향 (빛이 오는 쪽). BrawlLook 해가 없으면 그 기본 각도
static func _sun_dir() -> Vector3:
	if is_instance_valid(BrawlLook._sun):
		return BrawlLook._sun.global_basis.z.normalized()
	return Basis.from_euler(Vector3(deg_to_rad(BrawlLook.SUN_ROT.x), deg_to_rad(BrawlLook.SUN_ROT.y), 0)).z.normalized()


static func _decal_material() -> ShaderMaterial:
	if _decal_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;
instance uniform float fade = 1.0;
void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * fade;
	ROUGHNESS = 0.0;   // ToonOutline 제외
}
"""
		_decal_mat = ShaderMaterial.new()
		_decal_mat.shader = sh
	return _decal_mat


# ── 메시 도우미 ─────────────────────────────────────────

## 원하는 바깥 법선 n 쪽이 앞면이 되게 감아 넣는다 (Godot 앞면 = 시계 방향. cull_disabled 재질은 뒷면 법선을 뒤집기 때문)
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	var fn := (b - a).cross(c - a)
	if fn.length_squared() < 1e-12:
		return
	fn = fn.normalized()
	if fn.dot(n) < 0.0:
		fn = -fn
	st.set_normal(fn)
	if (c - a).cross(b - a).dot(fn) > 0.0:
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	else:
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)


static func _im_tri(im: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	im.surface_set_color(col)
	im.surface_add_vertex(a); im.surface_add_vertex(b); im.surface_add_vertex(c)


static func _quad(im: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_im_tri(im, a, b, c, col)
	_im_tri(im, a, c, d, col)


## 볼록 다각형 판 (경첩 기준 상대 좌표, 위 = +0.012, 아래 = -th)
static func _slab_mesh(pts: PackedVector3Array, th: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := pts.size()
	var mid := Vector3.ZERO
	for q in pts:
		mid += q
	mid /= n
	var top := 0.012
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		_tri(st, Vector3(mid.x, top, mid.z), Vector3(a.x, top, a.z), Vector3(b.x, top, b.z), Vector3.UP)
		_tri(st, Vector3(mid.x, -th, mid.z), Vector3(b.x, -th, b.z), Vector3(a.x, -th, a.z), Vector3.DOWN)
		var out := ((a + b) * 0.5 - mid)
		out.y = 0
		_tri(st, Vector3(a.x, top, a.z), Vector3(a.x, -th, a.z), Vector3(b.x, -th, b.z), out)
		_tri(st, Vector3(a.x, top, a.z), Vector3(b.x, -th, b.z), Vector3(b.x, top, b.z), out)
	return st.commit()


func _piece_node(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	return mi


# ── SLAB 판 들림 ────────────────────────────────────────

## 방사형 판. 고리 3개 × 조각 n 개 + 가운데 부채꼴. 꼭짓점은 이웃과 공유해 빈틈없이 갈라진다.
## lift_k: 들리는 정도 배율 (SPIKE 가장자리 판은 작게)
func _slabs(b: Burst, mat: Material, decal: ImmediateMesh, g: Vector3, power: float, lift_k: float) -> void:
	var R := lerpf(1.25, 3.4, clampf(power, 0.0, 1.2))
	var n := 7 + randi() % 3
	var rings := [0.0, 0.26 + randf() * 0.06, 0.58 + randf() * 0.08, 1.0]
	var ph := randf() * TAU
	# 꼭짓점 격자 [고리][조각]
	var P: Array = []
	for ri in rings.size():
		var row: Array = []
		for j in n:
			var a := ph + TAU * (j + randf_range(-0.28, 0.28)) / n
			var r := float(rings[ri]) * R * randf_range(0.88, 1.1)
			if ri == 0:
				r = randf() * 0.12 * R
			row.append(g + Vector3(cos(a) * r, 0, sin(a) * r))
		P.append(row)
	var center: Vector3 = g + Vector3(randf_range(-0.1, 0.1), 0, randf_range(-0.1, 0.1)) * R
	for ri in range(1, rings.size()):
		for j in n:
			var j2 := (j + 1) % n
			var poly: Array = []
			if ri == 1:
				poly = [center, P[1][j], P[1][j2]]
			else:
				poly = [P[ri - 1][j], P[ri - 1][j2], P[ri][j2], P[ri][j]]
			# 바깥 고리는 가끔 둘로 쪼갠다 (긴 판이 너무 규칙적이지 않게)
			if ri == 3 and randf() < 0.45:
				var m0: Vector3 = (P[2][j] as Vector3).lerp(P[3][j], randf_range(0.4, 0.6))
				var m1: Vector3 = (P[2][j2] as Vector3).lerp(P[3][j2], randf_range(0.4, 0.6))
				_slab_piece(b, mat, decal, g, [P[2][j], P[2][j2], m1, m0], 2, R, lift_k)
				_slab_piece(b, mat, decal, g, [m0, m1, P[3][j2], P[3][j]], 3, R, lift_k)
			else:
				_slab_piece(b, mat, decal, g, poly, ri, R, lift_k)
	_cracks(decal, g, R * 1.35, n, 0.035 + 0.02 * power, R * 0.9)


func _slab_piece(b: Burst, mat: Material, decal: ImmediateMesh, g: Vector3, poly: Array, ring: int, R: float, lift_k: float) -> void:
	var cnt := poly.size()
	# 경첩 = 중심에서 가장 먼 변의 가운데 (그 변을 축으로 안쪽이 들린다)
	var best := 0
	var bd := -1.0
	for i in cnt:
		var m: Vector3 = ((poly[i] as Vector3) + (poly[(i + 1) % cnt] as Vector3)) * 0.5
		var d := Vector2(m.x - g.x, m.z - g.z).length()
		if d > bd:
			bd = d
			best = i
	var e0: Vector3 = poly[best]
	var e1: Vector3 = poly[(best + 1) % cnt]
	var hinge := (e0 + e1) * 0.5
	var mid := Vector3.ZERO
	for q in poly:
		mid += q
	mid /= cnt
	# 구멍(어두운 바닥) = 원래 자리 전체, 판은 살짝 줄여 틈이 금으로 보인다
	var hy := g.y + 0.005
	for i in range(1, cnt - 1):
		_im_tri(decal, Vector3((poly[0] as Vector3).x, hy, (poly[0] as Vector3).z), Vector3((poly[i] as Vector3).x, hy, (poly[i] as Vector3).z), Vector3((poly[i + 1] as Vector3).x, hy, (poly[i + 1] as Vector3).z), HOLE_COL)
	var shrink := 0.035 + 0.01 * ring
	var local := PackedVector3Array()
	for q in poly:
		var v: Vector3 = q
		var to := mid - v
		to.y = 0
		v += to.normalized() * minf(shrink, to.length() * 0.3)
		local.append(Vector3(v.x - hinge.x, 0, v.z - hinge.z))
	var pc := Piece.new()
	pc.kind = SLAB
	pc.base = hinge
	var inward := mid - hinge
	inward.y = 0
	inward = inward.normalized() if inward.length() > 0.001 else Vector3.FORWARD
	pc.axis = inward.cross(Vector3.UP).normalized()
	var deg := 0.0
	match ring:
		1: deg = randf_range(52.0, 80.0)
		2: deg = randf_range(22.0, 42.0)
		_: deg = randf_range(0.0, 11.0) if randf() < 0.75 else 0.0
	pc.ang = deg_to_rad(deg) * lift_k
	pc.lift = [0.0, 0.26, 0.12, 0.03][ring] * lift_k * (0.6 + 0.4 * R / 3.0)
	pc.delay = Vector2(mid.x - g.x, mid.z - g.z).length() / WAVE_V
	pc.node = _piece_node(_slab_mesh(local, randf_range(0.1, 0.16)), mat if pc.ang > 0.05 else b.fmat)
	pc.node.global_transform = Transform3D(Basis.IDENTITY, hinge)
	b.pieces.append(pc)


## 중심에서 뻗는 들쭉날쭉한 금 (from 부터 to 까지)
func _cracks(decal: ImmediateMesh, g: Vector3, to: float, n: int, w: float, from := 0.0) -> void:
	var y := g.y + 0.006
	for i in n:
		var a := TAU * (i + randf()) / n
		var r := from
		var p := g + Vector3(cos(a), 0, sin(a)) * r
		var ww := w
		while r < to:
			a += randf_range(-0.45, 0.45)
			var step := randf_range(0.18, 0.38)
			r += step
			var q := p + Vector3(cos(a), 0, sin(a)) * step
			var side := Vector3(-sin(a), 0, cos(a))
			var w2 := ww * 0.82
			_quad(decal, Vector3(p.x, y, p.z) + side * ww, Vector3(q.x, y, q.z) + side * w2, Vector3(q.x, y, q.z) - side * w2, Vector3(p.x, y, p.z) - side * ww, CRACK_COL)
			p = q
			ww = w2
			if ww < 0.008:
				break


## 깨진 구멍 (어두운 들쭉날쭉한 원)
func _hole(decal: ImmediateMesh, g: Vector3, r: float, n: int, lift: float) -> void:
	var y := g.y + 0.006 + lift
	var pts: Array[Vector3] = []
	for i in n:
		var a := TAU * (i + randf_range(-0.3, 0.3)) / n
		var rr := r * (randf_range(0.55, 1.15) if i % 2 == 0 else randf_range(0.35, 0.7))   # 별 모양으로 들쭉날쭉
		pts.append(Vector3(g.x + cos(a) * rr, y, g.z + sin(a) * rr))
	var c := Vector3(g.x, y, g.z)
	for i in n:
		_im_tri(decal, c, pts[i], pts[(i + 1) % n], HOLE_COL)


func _dust(g: Vector3, power: float) -> void:
	FX.puffs(g + Vector3(0, 0.1, 0), int(2 + 4 * power), DUST, 0.6 + 1.0 * power, 0.22 + 0.2 * power, 0.5)


# ── SPIKE 암석 솟음 ─────────────────────────────────────

## 각진 기둥 (밑동 = 원점, +Y 로 길이 h). 윗면은 비스듬히 깨진 끌 모양
static func _spike_mesh(rb: float, h: float, sides: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bot: Array[Vector3] = []
	var top: Array[Vector3] = []
	var taper := randf_range(0.35, 0.65)
	var shift := Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3)) * rb
	var tilt := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	for i in sides:
		var a := TAU * (i + randf_range(-0.2, 0.2)) / sides
		var r := rb * randf_range(0.8, 1.15)
		var v := Vector3(cos(a) * r, 0, sin(a) * r)
		bot.append(v)
		var tv := v * taper + shift
		tv.y = h * (1.0 - 0.22 * maxf(0.0, (v / maxf(r, 0.001)).dot(tilt))) * randf_range(0.94, 1.0)
		top.append(tv)
	var tmid := Vector3.ZERO
	for q in top:
		tmid += q
	tmid /= sides
	for i in sides:
		var j := (i + 1) % sides
		var out := (bot[i] + bot[j]) * 0.5
		out.y = 0
		_tri(st, bot[i], bot[j], top[j], out)
		_tri(st, bot[i], top[j], top[i], out)
		_tri(st, tmid, top[i], top[j], Vector3.UP)
	return st.commit()


func _spikes(b: Burst, mat: Material, decal: ImmediateMesh, g: Vector3, power: float, dir: Vector3, k: float) -> void:
	var count := int(round((4.0 + 7.0 * power) * k))
	var spread := 0.35 + 1.0 * power
	_hole(decal, g, spread * 0.9 + 0.3, 11, 0.0)
	for i in maxi(count, 2):
		var a := TAU * (i + randf_range(-0.3, 0.3)) / maxi(count, 2)
		var r := spread * sqrt(randf_range(0.05, 1.0))
		var out := Vector3(cos(a), 0, sin(a))
		if dir != Vector3.ZERO and randf() < 0.5:
			out = (out + dir * 1.2).normalized()      # 공격 방향 쪽으로 더 쏠린다
		var at := g + out * r
		at.y = Main.gy(at)
		var size := (0.55 + 0.45 * (1.0 - r / maxf(spread, 0.01))) * (0.8 + 0.65 * power)   # 가운데가 크다
		var h := randf_range(0.6, 1.25) * size * 1.5
		var rb := randf_range(0.3, 0.5) * size
		var pc := Piece.new()
		pc.kind = SPIKE
		pc.node = _piece_node(_spike_mesh(rb, h, 4 + randi() % 2), mat)
		var lean := deg_to_rad(randf_range(8.0, 26.0)) * (0.35 + 0.65 * r / maxf(spread, 0.01))
		var ax := Vector3.UP.cross(out).normalized()
		pc.basis = Basis(ax, lean) * Basis(Vector3.UP, randf() * TAU)
		pc.base = at
		pc.lift = h
		pc.delay = r / (WAVE_V * 0.7) + randf() * 0.03
		pc.node.global_transform = Transform3D(pc.basis, at - pc.basis.y * (h + 0.1))
		b.pieces.append(pc)


# ── SCATTER 파편 튐 ─────────────────────────────────────

## 울퉁불퉁한 덩어리 (찌그러진 상자, 원점 = 가운데)
static func _chunk_mesh(s: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sx := s * randf_range(0.8, 1.4)
	var sy := s * randf_range(0.35, 0.7)          # 바닥 판 조각이라 납작하다
	var sz := s * randf_range(0.8, 1.3)
	var c: Array[Vector3] = []
	for i in 8:
		var v := Vector3(sx if i & 1 else -sx, sy if i & 2 else -sy, sz if i & 4 else -sz)
		c.append(v * randf_range(0.7, 1.2))
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	for f in faces:
		var a: Vector3 = c[f[0]]
		var b2: Vector3 = c[f[1]]
		var cc: Vector3 = c[f[2]]
		var d: Vector3 = c[f[3]]
		var out := (a + b2 + cc + d) * 0.25
		_tri(st, a, b2, cc, out)
		_tri(st, a, cc, d, out)
	return st.commit()


func _chunks(b: Burst, mat: Material, g: Vector3, power: float, dir: Vector3, k: float) -> void:
	var count := int((10.0 + 26.0 * power) * k)
	for i in count:
		var out := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		if dir != Vector3.ZERO and randf() < 0.6:
			out = dir.rotated(Vector3.UP, randf_range(-0.9, 0.9))
		var s := randf_range(0.05, 0.17) * (0.7 + 0.5 * power)
		if randf() < 0.15:
			s *= 1.8                                   # 가끔 큰 덩어리
		var pc := Piece.new()
		pc.kind = CHUNK
		pc.size = s
		pc.node = _piece_node(_chunk_mesh(s), mat)
		pc.base = g + out * randf_range(0.1, 0.6) * (0.5 + power) + Vector3(0, s, 0)
		var sp := randf_range(2.5, 7.5) * (0.55 + 0.6 * sqrt(power)) * (0.25 / (s + 0.12))
		pc.vel = out * sp + Vector3.UP * randf_range(3.0, 7.5) * (0.6 + 0.5 * power)
		pc.spin_axis = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		pc.spin = randf_range(8.0, 22.0)
		pc.basis = Basis(pc.spin_axis, randf() * TAU)
		pc.delay = randf() * 0.04
		pc.node.global_transform = Transform3D(pc.basis, pc.base)
		pc.node.visible = false
		b.pieces.append(pc)


# ── BUCKLE 찌그러짐 ────────────────────────────────────

const BK_RINGS := 14
const BK_SEGS := 40

func _buckle(b: Burst, mat: Material, decal: ImmediateMesh, g: Vector3, power: float) -> void:
	b.R = lerpf(1.5, 3.8, clampf(power, 0.0, 1.2)) if not b.trail else (0.55 + 1.1 * power) * randf_range(0.75, 1.2)
	b.creases = 5 + randi() % 4
	b.phase = randf() * TAU
	b.noise.resize((b.rings + 1) * b.segs)
	for i in b.noise.size():
		b.noise[i] = randf_range(-1.0, 1.0)
	b.im = ImmediateMesh.new()
	b.buckle = MeshInstance3D.new()
	b.buckle.mesh = b.im
	b.buckle.material_override = _buckle_mat(mat)
	b.light = _sun_dir()
	add_child(b.buckle)
	b.buckle.global_position = Vector3(g.x, g.y, g.z)
	if b.trail:
		_cracks(decal, g, b.R * 0.75, 3, 0.022, 0.0)
	else:
		_hole(decal, g, b.R * 0.16, 9, 0.012)
		_cracks(decal, g, b.R * 0.34, b.creases, 0.03 + 0.015 * power, 0.0)
		_dust(g, power * 0.6)
	_buckle_mesh(b)


## 높이 = 퍼지는 물결 + 주름진 둔덕 고리 (가운데는 평평하게 두어 금 데칼이 보이게) · 끝에 서서히 펴진다
func _buckle_h(b: Burst, r: float, a: float, ni: int) -> float:
	var R := b.R
	var t := b.t
	var p := b.power
	var front := R * 0.95 * minf(t / 0.3, 1.0)
	var wave := 0.75 * p * exp(-pow((r - front) / (0.22 * R), 2.0)) * maxf(0.0, 1.0 - t / 0.55)
	var settle := smoothstep(0.0, 0.25, t)
	var crease := 0.45 + 0.55 * absf(sin(b.creases * 0.5 * a + b.phase + r * 0.9))
	var rim := 0.5 * p * exp(-pow((r - 0.68 * R) / (0.2 * R), 2.0)) * crease * settle
	var crumple := 0.07 * p * b.noise[ni] * smoothstep(0.25 * R, 0.5 * R, r) * (1.0 - smoothstep(0.85 * R, R, r))
	var end := 1.0 - smoothstep(b.life - SINK - 0.35, b.life, t)
	var h := (wave + rim + crumple * settle) * end
	if b.trail:
		h *= TRAIL_AMP
	h *= 1.0 - smoothstep(0.88 * R, R, r)           # 바깥 끝은 바닥과 이어진다
	return 0.004 + maxf(h, 0.0)


func _buckle_mesh(b: Burst) -> void:
	var im := b.im
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array = []
	for ri in b.rings + 1:
		var row: Array[Vector3] = []
		var r := b.R * pow(float(ri) / b.rings, 0.85)
		for si in b.segs:
			var a := TAU * si / b.segs
			var h := _buckle_h(b, r, a, ri * b.segs + si)
			row.append(Vector3(cos(a) * r, h, sin(a) * r))
		pts.append(row)
	for ri in b.rings:
		for si in b.segs:
			var s2 := (si + 1) % b.segs
			var a: Vector3 = pts[ri][si]
			var b0: Vector3 = pts[ri][s2]
			var c: Vector3 = pts[ri + 1][s2]
			var d: Vector3 = pts[ri + 1][si]
			_flat_tri(im, a, b0, c, b.light, b.power)
			_flat_tri(im, a, c, d, b.light, b.power)
	im.surface_end()


## 위를 보는 앞면 + 면 법선 (주름이 각진 면으로 보이게)
static func _flat_tri(im: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, light: Vector3, power: float) -> void:
	var fn := (b - a).cross(c - a)
	if fn.length_squared() < 1e-14:
		return
	fn = fn.normalized()
	if fn.y < 0.0:
		fn = -fn
	# 평평하면 1 (바닥과 같은 색). 해를 향할수록 밝게, 등질수록 어둡게, 높이 솟은 둔덕 꼭대기는 조금 더 밝게
	var hgt := (a.y + b.y + c.y) / 3.0
	var k := 1.0 + 2.6 * (fn.dot(light) - light.y) + 1.1 * hgt / maxf(power, 0.3)
	im.surface_set_color(Color.WHITE * clampf(k, 0.42, 1.7))
	im.surface_set_normal(fn)
	if (c - a).cross(b - a).dot(fn) > 0.0:
		im.surface_add_vertex(a); im.surface_add_vertex(b); im.surface_add_vertex(c)
	else:
		im.surface_add_vertex(a); im.surface_add_vertex(c); im.surface_add_vertex(b)


# ── 지나간 자리 흔적 ─────────────────────────────────────

## Player 가 매 틱 부른다: 돌진 · 휠윈드 중이면 지나간 거리마다(제자리에서 돌면 시간마다) 흔적을 남긴다
static func follow(p: Player, dt: float) -> void:
	if str(STYLES[style].id) == "off" or not is_instance_valid(Main.inst) or not is_instance_valid(p):
		return
	# 출처 → [세기, 간격(m), 제자리 간격(초)]
	var src := {}
	if p.lunge_t > 0.0:
		src["lunge"] = [0.42, 1.15, 0.0]                  # 대시 중 일격참 · 관통 일격
	if p.tech and p.tech.rushing():
		src["rush"] = [0.5 if p.tech.whirl() else 0.36, 1.05, 0.0]   # 기 모으기 돌진 (최대 = TEMPEST 회오리)
	if p.whirl and p.whirl.active():
		src["dash_whirl"] = [0.32, 0.95, 0.16]             # 2단 대시 휠윈드
	var d := PartnerDrone.inst
	if is_instance_valid(d) and d.whirl_t >= 0.0 and d.player == p:
		src["q_whirl"] = [0.36, 1.0, 0.22]               # Q 합체 휠윈드
	if src.is_empty() and (not is_instance_valid(inst) or inst._trail_last.is_empty()):
		return
	if not is_instance_valid(inst):
		inst = GroundBreak.new()
		inst.name = "GroundBreak"
		Main.inst.add_child(inst)
	inst._follow(p, dt, src)


func _follow(p: Player, dt: float, src: Dictionary) -> void:
	for k in _trail_last.keys():
		if not src.has(k):
			_trail_last.erase(k)
			_trail_tick.erase(k)
	if p.gy < -50.0 or absf(p.global_position.y - Main.gy(p.global_position)) > 0.9:
		return                       # 공중(점프 · 낙하)에서는 바닥에 닿지 않는다
	var at := p.global_position
	for k in src:
		var cfg: Array = src[k]
		if not _trail_last.has(k):
			_trail_last[k] = at
			_trail_tick[k] = 0.0
			trail_mark(at, float(cfg[0]), p.aim_dir)      # 시작 자리
			continue
		var last: Vector3 = _trail_last[k]
		var mv := at - last
		mv.y = 0
		var gap := float(cfg[1])
		if mv.length() >= gap:
			var dir := mv.normalized()
			var n := mini(int(mv.length() / gap), 4)     # 한 틱에 멀리 가면(빠른 돌진) 사이를 메운다
			for i in n:
				var side := Vector3(-dir.z, 0, dir.x) * randf_range(-0.3, 0.3)
				trail_mark(last + dir * gap * (i + 1) * randf_range(0.85, 1.0) + side, float(cfg[0]) * randf_range(0.7, 1.1), dir)
			_trail_last[k] = last + dir * gap * n
			_trail_tick[k] = 0.0
		elif float(cfg[2]) > 0.0:
			_trail_tick[k] = float(_trail_tick[k]) + dt
			if float(_trail_tick[k]) >= float(cfg[2]):
				_trail_tick[k] = 0.0
				var off := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(0.6, 1.4)
				trail_mark(at + off, float(cfg[0]) * 0.8, off.normalized())   # 제자리 회전: 둘레 바닥이 조금씩 깨진다


## 흔적 하나: 작은 찌그러짐 + 작은 파편 몇 개 + 짧은 금 (판정 없음)
func trail_mark(pos: Vector3, power: float, dir: Vector3) -> void:
	if _trail_budget < 1.0 or WorldFlow.active():
		return
	_trail_budget -= 1.0
	var g := Vector3(pos.x, Main.gy(pos), pos.z)
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.ZERO
	var b := Burst.new()
	b.trail = true
	b.center = g
	b.power = power
	b.life = TRAIL_LIFE
	b.rings = TRAIL_RINGS
	b.segs = TRAIL_SEGS
	var fmat := _floor_mat(g)
	b.fmat = fmat
	var decal := ImmediateMesh.new()
	decal.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_buckle(b, fmat, decal, g, power)
	_chunks(b, _piece_mat(fmat), g, power * 0.35, dir, 0.3)
	decal.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = decal
	mi.material_override = _decal_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	b.decal = mi
	bursts.append(b)
	if randf() < 0.35:
		FX.puffs(g + Vector3(0, 0.08, 0), 1, DUST, 0.4, 0.18, 0.4)
	_trim()


# ── 매 프레임 ───────────────────────────────────────────

static func _ease_back(x: float) -> float:
	var c1 := 2.4
	var c3 := c1 + 1.0
	var y := x - 1.0
	return 1.0 + c3 * y * y * y + c1 * y * y


func _process(dt: float) -> void:
	_budget = minf(BUDGET, _budget + dt * BUDGET)
	_trail_budget = minf(TRAIL_BUDGET, _trail_budget + dt * TRAIL_BUDGET)
	var i := 0
	while i < bursts.size():
		var b := bursts[i]
		b.t += dt
		if b.t >= b.life:
			_free_burst(b)
			bursts.remove_at(i)
			continue
		var e := smoothstep(b.life - SINK, b.life, b.t)      # 끝 가라앉음 0→1
		for pc in b.pieces:
			match pc.kind:
				SLAB: _step_slab(pc, b.t, e)
				SPIKE: _step_spike(pc, b.t, e, b.life)
				CHUNK: _step_chunk(pc, b.t, e, dt)
		if is_instance_valid(b.decal):
			b.decal.set_instance_shader_parameter("fade", (1.0 - e) * minf(b.t / 0.04, 1.0))
		if b.im:
			# 움직이는 동안(물결·굳음·펴짐)만 다시 만든다
			var moving := b.t < 0.6 or b.t > b.life - SINK - 0.4
			if moving or not b.built_final:
				_buckle_mesh(b)
				b.built_final = not moving
		i += 1


func _step_slab(pc: Piece, t: float, e: float) -> void:
	var lt := t - pc.delay
	var k := 0.0
	if lt > 0.0:
		k = _ease_back(clampf(lt / POP, 0.0, 1.0))
		k += 0.05 * sin(lt * 34.0) * exp(-lt * 9.0)         # 들린 뒤 잠깐 덜컹
	var ang := pc.ang * k * (1.0 - e)
	var y := pc.lift * k * (1.0 - e) - e * 0.28
	pc.node.global_transform = Transform3D(Basis(pc.axis, ang), pc.base + Vector3(0, y, 0))


func _step_spike(pc: Piece, t: float, e: float, life: float) -> void:
	var lt := t - pc.delay
	var k := 0.0
	if lt > 0.0:
		k = _ease_back(clampf(lt / 0.08, 0.0, 1.0))
	# 끝: 판보다 일찍(0.3초 전부터) 바닥으로 빠르게 들어간다
	var back := smoothstep(life - SINK - 0.15, life - 0.1, t)
	k *= 1.0 - back
	k = maxf(k, 0.0)
	var wob := 0.04 * sin(lt * 40.0) * exp(-maxf(lt, 0.0) * 10.0)
	var bs := pc.basis * Basis(Vector3.RIGHT, wob)
	pc.node.global_transform = Transform3D(bs, pc.base - bs.y * (pc.lift + 0.1) * (1.0 - k))
	pc.node.visible = k > 0.001 and e < 0.999


func _step_chunk(pc: Piece, t: float, e: float, dt: float) -> void:
	if t < pc.delay:
		return
	pc.node.visible = true
	if not pc.rest:
		pc.vel.y -= GRAV * dt
		var np := pc.base + pc.vel * dt
		if is_instance_valid(Main.inst) and Main.inst.is_blocked(np):
			pc.vel.x *= -0.35
			pc.vel.z *= -0.35
			np = pc.base + Vector3(0, pc.vel.y * dt, 0)
		var gy := Main.gy(np) + pc.size * 0.45
		if np.y < gy:
			np.y = gy
			if absf(pc.vel.y) < 2.0 and Vector2(pc.vel.x, pc.vel.z).length() < 0.8:
				pc.rest = true
				pc.vel = Vector3.ZERO
			else:
				pc.vel.y = -pc.vel.y * 0.32
				pc.vel.x *= 0.55
				pc.vel.z *= 0.55
				pc.spin *= 0.55
		pc.base = np
		pc.basis = (Basis(pc.spin_axis, pc.spin * dt) * pc.basis).orthonormalized()
	var sink := Vector3(0, -e * (pc.size * 1.4 + 0.05), 0)
	pc.node.global_transform = Transform3D(pc.basis, pc.base + sink)
