class_name SaberTrail
extends MeshInstance3D
## 광선검 잔상 리본 (연출 전용, 판정과 무관).
## 칼날 손잡이·칼끝 위치를 매 프레임 기록해 지나간 자리를 초승달 띠로 잇는다.
## - 수명이 TRAIL_LIFE(≈5프레임)로 매우 짧다: 빠르게 휘두른 순간에만 번쩍 남고 곧바로 사라진다.
## - 오래된 부분일수록 안쪽이 먼저 깎여 칼끝 쪽 가는 꼬리만 남는다 → 끝이 뾰족한 초승달.
## - 칼끝 속도가 느리면 기록은 이어가되 보이지 않는다 (느린 동작엔 잔상이 없다).
## - 게임 시간(히트스탑 반영)으로 늙으므로, 적중 순간 히트스탑 동안 호가 화면에 얼어붙는다.
## 흰 심 → 분홍 → 보라 테두리 순으로 물들고, 칼끝 너머로 가는 실선(wisp)이 흩날린다.
##
## 같은 리본을 몸 파츠에도 쓴다 (body()): 어깨→손, 엉덩이→발처럼 파츠 위 두 점을 잇고,
## 몸체 장갑과 같은 크림 톤으로 은은하게 물든다. 대시 드릴 회전·돌진 중에만 active 로 켠다.

const SAMPLE_GAP := 1.0 / 240.0  # 기록 간격 하한
const SUBDIV := 3                # 기록 사이 곡선 보간 분할

static var _shaders := {}         # 혼합 방식별 셰이더 ("mix" / "add")

var life := 0.038                # 잔상 수명 (게임 초, ≈2프레임: 스윙 순간에만 번쩍)
var reach := 1.65                # 끝점보다 이만큼 (길이 배) 더 뻗어 호를 크고 넓게 그린다
var speed_lo := 7.0              # 끝점 속도 (m/s) 이 이하면 잔상 없음
var speed_hi := 22.0
var active := true               # false 면 기록만 이어가고 보이지 않는다
var blade: Node3D                # 리본을 붙일 파츠 (광선검이면 칼 피벗)
var p_base := Vector3(0, 0, 0.05)    # 파츠 기준 리본 뿌리 (칼: 손잡이 끝, 로컬 -Z 가 칼끝 방향)
var p_tip := Vector3(0, 0, -1.43)    # 파츠 기준 리본 끝 (칼: 칼끝)
var boost := 0.0                 # 외부에서 올리는 세기 (콤보 스윙 중 1)
var tint := 0.0                  # 0 분홍·보라 / 1 불꽃빛 (관통 일격 준비 중)
var bright := 1.0                # 밝기 배율 (가산 혼합이라 0.5 면 빛이 절반). 기본 광선검은 Player 가 0.5 로 둔다
var gust := false                # 켜면 빠르게 휘두른 칼이 지나간 면을 따라 기체가 흩날린다 (GustFX)

var _pts: Array = []             # [hilt, tip, time, weight]
var _time := 0.0
var _last_add := -1.0
var _im: ImmediateMesh
var _prev_tip := Vector3.ZERO
var _prev_anchor := Vector3.ZERO
var anchor: Node3D               # 몸 기준점: 몸이 통째로 움직이는 것(돌진)은 칼 속도에서 뺀다
var _w := 0.0
var _gust_prev: Array = []       # 지난 틱 [손잡이, 칼끝]
var _gust_anchor := Vector3.ZERO


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_im = ImmediateMesh.new()
	mesh = _im
	custom_aabb = AABB(Vector3(-2000, -50, -2000), Vector3(4000, 100, 4000))
	if material_override == null:
		material_override = saber_material()
		# 광선검만: 같은 리본 메시로 뒤 화면을 굴절시켜 칼이 지나간 공기가 휜다 (몸 리본은 제외)
		var dm := MeshInstance3D.new()
		dm.mesh = _im
		dm.material_override = Distortion.trail_material()
		dm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dm.custom_aabb = custom_aabb
		add_child(dm)


## 몸 파츠 리본: node 위 base → tip 을 잇는 몸체 톤 리본. 대시 회전·돌진 중에만 켠다.
static func body(node: Node3D, base: Vector3, tip: Vector3, shade := 0.0) -> SaberTrail:
	var t := SaberTrail.new()
	t.blade = node
	t.p_base = base
	t.p_tip = tip
	t.reach = 1.45
	t.life = 0.3
	t.speed_lo = 4.0
	t.speed_hi = 13.0
	t.active = false
	var m := make_material()
	# 몸체와 같은 보라 계열. 바닥(짙은 남보라)과 구분되도록 명도만 올린 라벤더 → 몸 보라 → 짙은 보라.
	# 흰 테·실선 없이, 빛 번짐이 거의 없는 밝기로.
	var fresh := Color("cbc2ff").lerp(Pal.P_LIGHT, shade * 0.4)
	var mid := Pal.P_LIGHT.lerp(Color("9d8cf0"), 0.4)
	m.set_shader_parameter("c_new", Vector3(fresh.r, fresh.g, fresh.b))
	m.set_shader_parameter("c_mid", Vector3(mid.r, mid.g, mid.b))
	m.set_shader_parameter("c_old", Vector3(Pal.P_BODY.r, Pal.P_BODY.g, Pal.P_BODY.b))
	m.set_shader_parameter("c_deep", Vector3(Pal.P_DARK.r, Pal.P_DARK.g, Pal.P_DARK.b))
	m.set_shader_parameter("tip_edge", 1.0)
	m.set_shader_parameter("inner_lo", 0.05)
	m.set_shader_parameter("inner_hi", 0.7)
	m.set_shader_parameter("rim_amt", 0.5)
	m.set_shader_parameter("glow_amt", 0.12)
	m.set_shader_parameter("strand_amt", 0.0)
	m.set_shader_parameter("opacity", 0.95)
	t.material_override = m
	return t


## 광선검 리본: 가산 혼합 형광색. 흰 심 → 형광 분홍 → 전기 보라, 빛 번짐이 크게 날 만큼 밝다.
static func saber_material() -> ShaderMaterial:
	var m := make_material(true)
	m.set_shader_parameter("c_new", Vector3(1.0, 0.85, 1.0))
	m.set_shader_parameter("c_mid", Vector3(1.0, 0.12, 0.78))
	m.set_shader_parameter("c_old", Vector3(0.55, 0.16, 1.0))
	m.set_shader_parameter("c_deep", Vector3(0.22, 0.04, 0.55))
	m.set_shader_parameter("tip_edge", 0.86)
	m.set_shader_parameter("inner_lo", 0.12)
	m.set_shader_parameter("inner_hi", 0.8)
	m.set_shader_parameter("glow_amt", 1.6)
	m.set_shader_parameter("opacity", 1.0)
	return m


static func make_material(additive := false) -> ShaderMaterial:
	var key := "add" if additive else "mix"
	if not _shaders.has(key):
		var sh := Shader.new()
		sh.code = SHADER.replace("blend_mix", "blend_add" if additive else "blend_mix")
		_shaders[key] = sh
	var m := ShaderMaterial.new()
	m.shader = _shaders[key]
	return m


const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;
uniform float fire = 0.0;
uniform vec3 c_new = vec3(1.0, 0.95, 0.98);    // 방금 지나간 자리 (흰 심)
uniform vec3 c_mid = vec3(1.0, 0.28, 0.56);    // 분홍
uniform vec3 c_old = vec3(0.36, 0.14, 0.95);   // 보라
uniform vec3 c_deep = vec3(0.1, 0.04, 0.32);   // 안쪽 경계
uniform float tip_edge = 0.82;                 // 실제 끝점 (그 너머는 실선 영역)
uniform float inner_lo = 0.34;                 // 초승달 안쪽 경계: 새 부분 → 늙은 부분
uniform float inner_hi = 0.9;
uniform float rim_amt = 1.0;
uniform float glow_amt = 1.0;
uniform float strand_amt = 1.0;
uniform float opacity = 1.0;
uniform float bright = 1.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	float age = clamp(UV.x, 0.0, 1.0);   // 0 방금 · 1 사라지기 직전
	float v = UV.y;                      // 0 손잡이 · 1 뻗은 칼끝
	float w = COLOR.a;                   // 칼끝 속도 가중
	// 초승달: 늙을수록 안쪽 경계가 칼끝 쪽으로 올라온다
	float inner = mix(inner_lo, inner_hi, pow(age, 0.65));
	float core_edge = tip_edge;
	float body = smoothstep(inner, inner + 0.1, v) * (1.0 - smoothstep(core_edge, core_edge + 0.05, v + (tip_edge >= 1.0 ? 0.04 : 0.0)));
	// 칼끝 가장자리의 밝은 테
	float rim = exp(-pow((v - (core_edge - 0.02 - (tip_edge >= 1.0 ? 0.06 : 0.0))) * 28.0, 2.0)) * rim_amt;
	// 칼끝 너머 가는 실선: 칼 길이 방향으로 촘촘한 줄무늬 중 일부만 남긴다
	float strand = strand_amt * step(0.78, vnoise(vec2(v * 46.0, age * 2.5 + 3.1))) * step(core_edge, v) * (1.0 - smoothstep(0.93, 1.0, v));
	// 띠 안쪽의 결 (속도선)
	float grain = 0.75 + 0.25 * vnoise(vec2(v * 30.0, age * 4.0));
	vec3 white = c_new;
	vec3 pink = mix(c_mid, vec3(1.0, 0.45, 0.12), fire);
	vec3 violet = mix(c_old, vec3(0.75, 0.05, 0.03), fire);
	vec3 deep = mix(c_deep, vec3(0.25, 0.02, 0.02), fire);
	// 새 부분은 흰빛, 늙을수록 분홍 → 보라. 안쪽 경계 근처는 짙은 남보라 (배경을 어둡게 눌러 윤곽이 선다)
	float edge_in = 1.0 - smoothstep(inner, inner + 0.22, v);
	vec3 col = mix(white, pink, smoothstep(0.0, 0.35, age));
	col = mix(col, violet, smoothstep(0.35, 0.85, age));
	col = mix(col, deep, edge_in * 0.85);
	col = mix(col, white, rim * (1.0 - age * 0.6));
	float glow = 1.0 + ((1.0 - age) * 1.6 + rim * 1.2) * glow_amt;
	ALBEDO = col * glow * grain * bright;
	float fade = pow(1.0 - age, 1.4);
	float a = max(body * (0.55 + 0.45 * (1.0 - edge_in)), rim * 0.95) + strand * 0.85 * (1.0 - age);
	ALPHA = clamp(a * fade * w * opacity, 0.0, 1.0);
}
"""


func clear() -> void:
	_pts.clear()
	_im.clear_surfaces()


## 지금 칼의 손잡이·(뻗은) 칼끝 위치
func sample_now() -> Array:
	var hilt := blade.to_global(p_base)
	var tip := blade.to_global(p_tip)
	return [hilt, hilt + (tip - hilt) * reach, tip]


## 물리 틱마다 Player 가 부른다. subs: 지난 틱과 이번 틱 사이 칼 위치들 (시간 순, 스윙 중에만)
func feed(dt: float, subs: Array) -> void:
	if blade == null or not is_instance_valid(blade):
		return
	var t0 := _time
	_time += dt
	var now := sample_now()
	var tip_raw: Vector3 = now[2]
	if dt > 0.0005:
		# 히트스탑 중(dt≈0)에는 속도를 갱신하지 않아 얼어붙은 호가 그대로 남는다
		var an := anchor.global_position if anchor else Vector3.ZERO
		var spd := ((tip_raw - an) - (_prev_tip - _prev_anchor)).length() / dt
		_w = clampf((spd - speed_lo) / (speed_hi - speed_lo), 0.0, 1.0)
	_prev_tip = tip_raw
	_prev_anchor = anchor.global_position if anchor else Vector3.ZERO
	var w := _w
	if w > 0.05:
		w = maxf(w, boost * 0.8)
	if not blade.is_visible_in_tree() or not active:
		w = 0.0
	# 오래된 기록 제거
	while _pts.size() > 0 and _time - float(_pts[0][2]) > life:
		_pts.pop_front()
	var n := subs.size()
	if gust:
		_emit_gust(dt, subs, now, w)
	for i in n:
		var sp: Array = subs[i]
		_pts.append([sp[0], sp[1], lerpf(t0, _time, float(i + 1) / (n + 1)), w])
	if n > 0 or _time - _last_add >= SAMPLE_GAP or _pts.is_empty():
		_pts.append([now[0], now[1], _time, w])
		_last_add = _time
	else:
		var head: Array = _pts[_pts.size() - 1]
		head[0] = now[0]
		head[1] = now[1]
		head[3] = maxf(float(head[3]), w)
	_rebuild()


## 지난 틱 → 지금 칼 위치: 이번 틱에 칼이 쓸고 간 면을 덮는 부채꼴 기체를 뿜는다
func _emit_gust(dt: float, subs: Array, now: Array, w: float) -> void:
	var chain: Array = []
	if not _gust_prev.is_empty():
		chain.append(_gust_prev)
	for sp in subs:
		chain.append([sp[0], sp[2]])
	chain.append([now[0], now[2]])
	_gust_prev = [now[0], now[2]]
	var an := anchor.global_position if anchor else Vector3.ZERO
	var carrier := (an - _gust_anchor) / dt if dt > 0.0005 else Vector3.ZERO
	_gust_anchor = an
	if w < 0.3 or dt <= 0.0005 or chain.size() < 2:
		return
	var c := Color(1.0, 0.25, 0.7).lerp(Color(1.0, 0.5, 0.15), tint)
	var a: Array = chain[0]
	var b: Array = chain[chain.size() - 1]
	GustFX.blade_fan(a[0], a[1], b[0], b[1], dt, c, w, carrier)


func _rebuild() -> void:
	_im.clear_surfaces()
	var n := _pts.size()
	if n < 2:
		return
	var any := false
	for p in _pts:
		if float(p[3]) > 0.01:
			any = true
			break
	if not any:
		return
	(material_override as ShaderMaterial).set_shader_parameter("fire", tint)
	(material_override as ShaderMaterial).set_shader_parameter("bright", bright)
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	# 휠윈드·TEMPEST 처럼 틱마다 표본이 10여 개씩 들어와 점이 촘촘하면 곡선 보간 분할이 필요 없다 (정점 수 1/3)
	var sub := SUBDIV if n <= 48 else 1
	for i in n - 1:
		var p0: Array = _pts[maxi(i - 1, 0)]
		var p1: Array = _pts[i]
		var p2: Array = _pts[i + 1]
		var p3: Array = _pts[mini(i + 2, n - 1)]
		var steps := sub if i < n - 2 else sub + 1
		for s in steps:
			var f := float(s) / sub
			# 손잡이는 곡선 보간, 칼 방향은 단위 벡터를 곡선 보간 후 정규화 → 칼 길이를 지키며 호를 그린다
			var h := _cr(p0[0], p1[0], p2[0], p3[0], f)
			var d0: Vector3 = p0[1] - p0[0]
			var d1: Vector3 = p1[1] - p1[0]
			var d2: Vector3 = p2[1] - p2[0]
			var d3: Vector3 = p3[1] - p3[0]
			var ln := lerpf(d1.length(), d2.length(), f)
			var d := _cr(d0.normalized(), d1.normalized(), d2.normalized(), d3.normalized(), f)
			d = d.normalized() * ln if d.length() > 0.0001 else d1
			var tt := lerpf(float(p1[2]), float(p2[2]), f)
			var age := clampf((_time - tt) / life, 0.0, 1.0)
			var w := lerpf(float(p1[3]), float(p2[3]), f)
			var c := Color(1, 1, 1, w)
			_im.surface_set_color(c)
			_im.surface_set_uv(Vector2(age, 0.0))
			_im.surface_add_vertex(h)
			_im.surface_set_color(c)
			_im.surface_set_uv(Vector2(age, 1.0))
			_im.surface_add_vertex(h + d)
	_im.surface_end()


static func _cr(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * b) + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t2 + (-a + 3.0 * b - 3.0 * c + d) * t3)
