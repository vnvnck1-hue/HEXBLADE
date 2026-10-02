class_name GustFX
extends Node3D
## 연출 전용: 대시·부스터·광선검이 밀어낸 공기가 부채꼴로 흩뿌려지는 짧고 빠른 기체 (판정과 무관).
## 손그림 연기 시트 애니메이션의 흐름을 부채꼴 '메시' 위에서 재현한다 (수명 6~15프레임):
##  - 가시형(style 0): 뾰족한 왕관 → 둥근 봉우리 덩어리 + 뿌리 쪽으로 흘러내리는 가닥
##                    → 뿌리 쪽부터 파여 말굽·초승달 → 가늘어지며 사라진다
##  - 구름형(style 1): 둥근 봉우리 → 뿌리 쪽부터 파여 초승달 → 실처럼 가늘어진다
## 부채꼴의 꼭짓점(뿌리)이 뿜어진 자리, 바깥 호가 뻗어 나가는 쪽이다. 실루엣은 셰이더가 극좌표로 깎는다.
## 수명 후반부에는 투명해지며 사라지고, 일부(LINGER_CHANCE)는 수명이 몇 배 길어 오래 남는다.
## 부피감: 부채꼴 메시는 가운데가 부풀고 끝이 말려 올라간 곡면이라 3단 셀 음영이 굴곡을 따라 지고,
## 파여 들어간 안쪽 경계는 한 단 짙게 칠해 두께가 보인다. 짙은 뒷겹을 겹쳐 뿜으면 층이 생긴다.
## 모든 부채꼴을 MultiMesh 한 번으로 그린다. 장면마다 FX.root 아래에 저절로 하나 생긴다.

const CAP := 400
const STRIDE := 20                   # 변환 12 + 색 4 + custom 4
const U_SEG := 40
const R_SEG := 14
const SPIKY := 0.0
const CLOUD := 1.0
const LINGER_CHANCE := 0.12          # 이 확률로 오래 남는 기체가 섞인다
const LINGER_LIFE := Vector2(2.5, 4.0)  # 그때 수명 배율
const THROW := 2.6                  # 흩뿌려진 방향으로 나아가는 초속 = 다 뻗은 반지름 × 이 값 (관성)
const BLADE := 2.0                  # 구름형이지만 처음부터 속이 빈 초승달 (칼바람)

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_always;
uniform vec3 c_hi = vec3(0.61, 0.6, 0.73);    // 바닥(짙은 남보라)에 녹아드는 차분한 연회색
uniform vec3 c_mid = vec3(0.5, 0.49, 0.64);
uniform vec3 c_lo = vec3(0.4, 0.39, 0.55);
uniform vec3 light_dir = vec3(-0.5, 1.0, 0.35);
varying vec2 v_uv;
// 덩어리마다 같은 값은 flat 으로 넘긴다: 보간되면 미세한 오차가 해시에서 증폭돼 경계가 지글거린다
varying flat float v_k;
varying flat float v_seed;
varying flat float v_style;
varying flat float v_span;
varying flat vec4 v_col;

// 인자를 작게 유지한다 (큰 값의 sin 은 GPU 에서 정밀도가 무너져 픽셀마다 지글거린다)
float hash1(float x) { return fract(sin(mod(x, 61.0) * 12.9898 + 1.7) * 43758.5453); }

// 부채꼴 곡면: 가운데가 부풀고 바깥으로 갈수록 살짝 말려 올라간다
vec3 fan_pos(vec2 uv, float span) {
	float a = (uv.x - 0.5) * span;
	float r = uv.y;
	float y = 0.17 * sin(3.14159 * uv.x) * sin(3.14159 * r) + 0.1 * r * r;
	return vec3(sin(a) * r, y, -cos(a) * r);
}

void vertex() {
	v_k = INSTANCE_CUSTOM.r;
	v_seed = floor(INSTANCE_CUSTOM.g * 40.0);
	v_style = INSTANCE_CUSTOM.b;
	v_span = INSTANCE_CUSTOM.a;
	v_col = COLOR;
	v_uv = UV;
	vec3 p0 = fan_pos(UV, v_span);
	vec3 p1 = fan_pos(UV + vec2(0.01, 0.0), v_span);
	vec3 p2 = fan_pos(UV + vec2(0.0, 0.01), v_span);
	NORMAL = normalize(cross(p1 - p0, p2 - p0));
	VERTEX = p0;
}

void fragment() {
	float k = clamp(v_k, 0.0, 1.0);
	float u = v_uv.x;
	float r = v_uv.y;
	float cloud = min(v_style, 1.0);
	float hollow = step(1.5, v_style) * 0.55;   // 칼바람: 처음부터 속이 빈 초승달
	float seed = v_seed;
	// ── 바깥 실루엣: 봉우리(둥근 반원) ↔ 가시(뾰족). 가시형은 처음 몇 프레임만 왕관처럼 뾰족하다 ──
	float n_lobe = mix(4.0, 3.0, cloud) + floor(hash1(seed) * 2.0);
	float x = u * n_lobe + hash1(seed + 3.0) * 0.4;
	float cell = floor(x);
	float f = fract(x);
	float h = 0.55 + 0.45 * hash1(cell + seed * 1.37);
	float sf = 2.0 * f - 1.0;
	float lobe = sqrt(max(1.0 - sf * sf, 0.0));   // pow() 에 음수 밑을 넣으면 정의되지 않아 픽셀이 튄다
	float spike = pow(1.0 - abs(2.0 * f - 1.0), 2.4);
	float spiky = (1.0 - cloud) * (1.0 - smoothstep(0.05, 0.4, k));
	float bump = mix(lobe, spike, spiky) * h;
	float side = pow(max(sin(3.14159 * u), 0.0), 0.45);   // 양 옆은 둥근 어깨로 좁아진다
	float grow = 1.0 - pow(1.0 - k, 3.0);
	float amp = mix(0.3, 0.55, spiky);
	float outer = (1.0 - amp + amp * bump) * side * mix(0.4, 1.0, grow);
	// ── 뿌리 쪽: 가시형은 몸통 아래로 가는 가닥이 흘러내리고, 구름형은 아래도 봉우리 ──
	float dx = fract(u * 6.0 + hash1(seed + 9.0));
	float drip = pow(1.0 - abs(2.0 * dx - 1.0), 3.0) * hash1(floor(u * 6.0) + seed * 2.1);
	float fl = fract(u * n_lobe * 1.6 + 0.3);
	float sl = 2.0 * fl - 1.0;
	float low_lobe = sqrt(max(1.0 - sl * sl, 0.0));
	float inner_s = outer * 0.42 * (1.0 - drip * 0.9 * (1.0 - smoothstep(0.35, 0.8, k)));
	float inner_c = outer * (0.3 - 0.14 * low_lobe);
	float inner = max(mix(inner_s, inner_c, cloud), outer * hollow);
	// ── 속이 파여 초승달로: 뿌리 근처에서 자라는 구멍 (경계도 봉우리 모양) ──
	float a = (u - 0.5) * v_span;
	vec2 q = vec2(sin(a), cos(a)) * r;
	vec2 c = vec2((hash1(seed + 5.0) - 0.5) * 0.3, 0.02);
	float ang = atan(q.x - c.x, q.y - c.y);
	float d = length(q - c) + 0.045 * sin(ang * 7.0 + seed * 0.37);
	float hk = clamp((k - mix(0.3, 0.2, cloud)) / 0.7, 0.0, 1.0);
	// 구멍은 바깥 봉우리보다 조금 늦게 따라가 끝까지 가는 초승달이 남는다
	float R = pow(hk, 1.2) * mix(0.62, 0.66, cloud);
	if (r > outer || r < inner || d < R) discard;

	// ── 3단 셀 음영 + 파인 경계는 한 단 짙게 (두께) ──
	vec3 L = normalize((VIEW_MATRIX * vec4(normalize(light_dir), 0.0)).xyz);
	float ndl = dot(NORMAL, L);
	float thick = (1.0 - smoothstep(0.0, 0.09, d - R)) * step(0.001, R);
	float inner_edge = 1.0 - smoothstep(0.0, 0.06, r - inner);
	// 봉우리마다 부피: 봉우리 사이 골(주름)과 봉우리 한쪽 가장자리에 그늘이 진다
	float rr = r / max(outer, 0.001);
	float crease = (1.0 - smoothstep(0.0, 0.1, min(f, 1.0 - f))) * smoothstep(0.55, 0.8, rr) * (1.0 - spiky);
	float lobe_shadow = smoothstep(0.55, 0.75, f) * smoothstep(0.8, 0.9, rr) * (1.0 - spiky);
	float t = ndl - thick * 0.9 - inner_edge * 0.5 - v_col.a * 0.8 - crease * 0.55 - lobe_shadow * 0.55;
	vec3 col = c_lo;
	col = mix(col, c_mid, step(-0.35, t));
	col = mix(col, c_hi, step(0.15, t));
	// 갓 뿜어진 기체는 원인의 빛을 머금는다 (색 = 빛 × 세기)
	float hs = max(v_col.r, max(v_col.g, v_col.b));
	vec3 hc = v_col.rgb / max(hs, 0.001);
	col = mix(col, mix(col, hc, 0.6), clamp(hs, 0.0, 1.0) * (0.25 + 0.5 * max(thick, inner_edge)));
	ALBEDO = col;
	// 수명 후반부: 파여 들어가는 동시에 투명해지며 사라진다
	ALPHA = 1.0 - smoothstep(0.55, 1.0, k);
	ROUGHNESS = 0.0;   // ToonOutline 제외 표식
}
"""

static var inst: GustFX
static var _mesh: ArrayMesh
static var _mat: ShaderMaterial
static var _side_flip := 1.0
## 한 번의 분출(대시 한 번 · 부스터 한 번 · 스윙 한 번) 안에서 처음 것만 크고 뒤로 갈수록 작아진다
static var _clock := 0.0             # 게임 시간
static var _seq_k := 1.0             # 지금 뿜는 부채꼴 크기 배율 (각 분출 함수가 정한다)
static var _dash_t0 := -10.0
static var _boost_t0 := -10.0
static var _blade_t0 := -10.0
static var _blade_last := -10.0

var _mm: MultiMesh
var _buf := PackedFloat32Array()
var _n := 0
var _p := PackedVector3Array()
var _v := PackedVector3Array()
var _bx := PackedVector3Array()      # 방향 기저 (크기 없음)
var _by := PackedVector3Array()
var _bz := PackedVector3Array()
var _hc := PackedColorArray()        # 머금은 빛 색
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _s0 := PackedFloat32Array()      # 처음 반지름
var _s1 := PackedFloat32Array()      # 다 뻗은 반지름
var _drag := PackedFloat32Array()
var _span := PackedFloat32Array()    # 부채꼴 벌어진 각 (rad)
var _spin := PackedFloat32Array()    # 부채꼴 면 안에서 도는 각속도 (휘두른 기세를 잇는다)
var _style := PackedFloat32Array()
var _heat := PackedFloat32Array()
var _shade := PackedFloat32Array()   # 짙은 뒷겹 (0 밝음 · 1 짙음)
var _seed := PackedFloat32Array()


static func _host() -> GustFX:
	if inst and is_instance_valid(inst) and inst.is_inside_tree() and inst.get_parent() == FX.root:
		return inst
	if FX.root == null or not is_instance_valid(FX.root) or not FX.root.is_inside_tree():
		return null
	inst = GustFX.new()
	FX.root.add_child(inst)
	return inst


func _exit_tree() -> void:
	if inst == self:
		inst = null


## 부채꼴 격자: UV.x = 각도(0~1), UV.y = 반지름(0~1). 실제 자리는 셰이더가 벌어진 각에 맞춰 잡는다.
static func _build_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iy in R_SEG + 1:
		for ix in U_SEG + 1:
			var uv := Vector2(float(ix) / U_SEG, 0.02 + 0.98 * float(iy) / R_SEG)
			st.set_uv(uv)
			var a := (uv.x - 0.5) * 2.0
			st.add_vertex(Vector3(sin(a) * uv.y, 0.0, -cos(a) * uv.y))
	for iy in R_SEG:
		for ix in U_SEG:
			var i0 := iy * (U_SEG + 1) + ix
			var i1 := i0 + 1
			var i2 := i0 + U_SEG + 1
			var i3 := i2 + 1
			st.add_index(i0); st.add_index(i2); st.add_index(i1)
			st.add_index(i1); st.add_index(i2); st.add_index(i3)
	return st.commit()


func _ready() -> void:
	if _mesh == null:
		_mesh = _build_mesh()
		var sh := Shader.new()
		sh.code = SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = _mesh
	_mm.instance_count = CAP
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.material_override = _mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-2000, -50, -2000), Vector3(4000, 100, 4000))
	add_child(mmi)
	_buf.resize(CAP * STRIDE)
	for arr in [_p, _v, _bx, _by, _bz]:
		arr.resize(CAP)
	_hc.resize(CAP)
	for arr in [_age, _life, _s0, _s1, _drag, _span, _spin, _style, _heat, _shade, _seed]:
		arr.resize(CAP)


## 부채꼴 하나. fwd = 가운데 뻗는 방향, nrm = 부채꼴 면의 윗면 방향.
func _fan(pos: Vector3, fwd: Vector3, nrm: Vector3, span: float, r0: float, r1: float, life: float,
		style: float, vel := Vector3.ZERO, heat_c := Color.WHITE, heat := 0.0, shade := 0.0,
		spin := 0.0, drag := 3.0) -> void:
	if fwd.length() < 0.001:
		return
	var z := -fwd.normalized()
	var y := (nrm - z * nrm.dot(z))
	if y.length() < 0.001:
		y = Vector3.UP if absf(z.y) < 0.9 else Vector3.RIGHT
		y = (y - z * y.dot(z))
	y = y.normalized()
	var x := y.cross(z)
	r0 *= _seq_k
	r1 *= _seq_k
	# 관성: 뿜어진 방향 그대로 미끄러져 나가다 공기 저항으로 서서히 멈춘다
	vel += fwd.normalized() * r1 * THROW
	if randf() < LINGER_CHANCE:
		# 가끔은 기류가 흩어지지 않고 비교적 오래 머물며 천천히 떠오른다
		var m := randf_range(LINGER_LIFE.x, LINGER_LIFE.y)
		life *= m
		r1 *= 1.15
		spin /= m                     # 도는 총량은 같게 (오래 산다고 더 돌지 않는다)
		vel = vel * 0.6 + Vector3(0, 0.35, 0)
	var i := _n
	if i >= CAP:
		i = randi() % CAP
	else:
		_n += 1
	_p[i] = pos
	_v[i] = vel
	_bx[i] = x
	_by[i] = y
	_bz[i] = z
	_hc[i] = heat_c
	_age[i] = 0.0
	_life[i] = life
	_s0[i] = r0
	_s1[i] = r1
	_drag[i] = drag
	_span[i] = clampf(span, 0.3, 3.0)
	_spin[i] = spin
	_style[i] = style
	_heat[i] = heat
	_shade[i] = shade
	_seed[i] = randf()


func _kill(i: int) -> void:
	_n -= 1
	if i == _n:
		return
	_p[i] = _p[_n]; _v[i] = _v[_n]; _bx[i] = _bx[_n]; _by[i] = _by[_n]; _bz[i] = _bz[_n]
	_hc[i] = _hc[_n]; _age[i] = _age[_n]; _life[i] = _life[_n]; _s0[i] = _s0[_n]; _s1[i] = _s1[_n]
	_drag[i] = _drag[_n]; _span[i] = _span[_n]; _spin[i] = _spin[_n]; _style[i] = _style[_n]
	_heat[i] = _heat[_n]; _shade[i] = _shade[_n]; _seed[i] = _seed[_n]


func _process(dt: float) -> void:
	_clock += dt
	var i := 0
	while i < _n:
		var a := _age[i] + dt
		if a >= _life[i]:
			_kill(i)
			continue
		_age[i] = a
		var v := _v[i] * exp(-_drag[i] * dt)
		_v[i] = v
		_p[i] += v * dt
		i += 1
	_write()


func _write() -> void:
	for i in _n:
		var k := _age[i] / _life[i]
		# 순식간에 뻗고(첫 몇 프레임) 이후엔 거의 그 자리에서 파여 사라진다
		var s := lerpf(_s0[i], _s1[i], 1.0 - pow(1.0 - k, 4.0))
		var b := Basis(_bx[i], _by[i], _bz[i])
		if _spin[i] != 0.0:
			b = b * Basis(Vector3.UP, _spin[i] * _age[i] * (1.0 - k * 0.5))
		b = b.scaled_local(Vector3.ONE * s)
		var p := _p[i]
		var o := i * STRIDE
		_buf[o] = b.x.x; _buf[o + 1] = b.y.x; _buf[o + 2] = b.z.x; _buf[o + 3] = p.x
		_buf[o + 4] = b.x.y; _buf[o + 5] = b.y.y; _buf[o + 6] = b.z.y; _buf[o + 7] = p.y
		_buf[o + 8] = b.x.z; _buf[o + 9] = b.y.z; _buf[o + 10] = b.z.z; _buf[o + 11] = p.z
		var ht := _heat[i] * pow(maxf(1.0 - k * 1.6, 0.0), 2.0)
		var c := _hc[i]
		_buf[o + 12] = c.r * ht; _buf[o + 13] = c.g * ht; _buf[o + 14] = c.b * ht; _buf[o + 15] = _shade[i]
		_buf[o + 16] = k
		_buf[o + 17] = _seed[i]
		_buf[o + 18] = _style[i]
		_buf[o + 19] = _span[i]
	_mm.visible_instance_count = _n
	if _n > 0:
		RenderingServer.multimesh_set_buffer(_mm.get_rid(), _buf)


## 분출 시작 후 t 초: 1 에서 바닥값 lo 까지 빠르게 줄어든다
static func _decay(t: float, tau: float, lo: float) -> float:
	return lo + (1.0 - lo) * exp(-maxf(t, 0.0) / tau)


static func _flat(d: Vector3, fallback := Vector3.FORWARD) -> Vector3:
	d.y = 0.0
	return d.normalized() if d.length() > 0.001 else fallback


## 수평 방향 d 를 위로 pitch 만큼 들어 올린 방향
static func _lift(d: Vector3, pitch: float) -> Vector3:
	return (d * cos(pitch) + Vector3.UP * sin(pitch)).normalized()


## 부채꼴 면을 진행축 둘레로 roll 만큼 기울인 윗면 방향
static func _roll(fwd: Vector3, roll: float) -> Vector3:
	var side := Vector3.UP.cross(fwd).normalized()
	return (Vector3.UP * cos(roll) + side * sin(roll)).normalized()


# ── 대시 ─────────────────────────────────────────────

## 대시 출발: 박찬 자리에서 뒤로 크게 흩뿌려지는 가시 부채꼴 + 좌우로 튀는 날개
static func dash_burst(pos: Vector3, dir: Vector3, tint: Color) -> void:
	var g := _host()
	if g == null:
		return
	_dash_t0 = _clock
	_seq_k = 1.0
	var f := _flat(dir)
	var back := -f
	var base := Vector3(pos.x, Main.gy(pos) + 0.08, pos.z)   # 높은 바닥 위에서도 발밑에 깔린다
	# 뒤로 낮게 넓게 펼쳐지는 주 부채꼴 (짙은 뒷겹 + 밝은 앞겹)
	g._fan(base - Vector3(0, 0.03, 0), _lift(back, 0.18), Vector3.UP, 2.4, 0.5, 2.5, 0.22, SPIKY,
		back * 2.0, tint, 0.5, 1.0)
	g._fan(base + back * 0.1, _lift(back, 0.32), _roll(back, randf_range(-0.2, 0.2)), 2.0, 0.45, 2.2, 0.2, SPIKY,
		back * 2.5, tint, 0.9)
	# 좌우 날개: 비스듬히 세워져 옆·위로 튄다
	for sgn in [-1.0, 1.0]:
		var d := back.rotated(Vector3.UP, sgn * randf_range(0.9, 1.25))
		g._fan(base + d * 0.25, _lift(d, randf_range(0.45, 0.7)), _roll(d, sgn * randf_range(0.4, 0.7)),
			randf_range(1.1, 1.5), 0.35, randf_range(1.4, 1.8), randf_range(0.16, 0.2), SPIKY,
			d * 3.0, tint, 0.7)
	# 박찬 자리에서 수직으로 솟는 작은 가시
	g._fan(base, _lift(back, 1.2), _roll(back, 1.35), 1.2, 0.3, 1.2, 0.15, SPIKY, Vector3.ZERO, tint, 0.6)


## 대시 중 매 틱: 발밑에서 좌우 번갈아 뒤·옆으로 찢겨 나가는 짧은 부채꼴
static func dash_trail(from: Vector3, to: Vector3, tint: Color, k := 1.0) -> void:
	var g := _host()
	if g == null:
		return
	var d := to - from
	d.y = 0.0
	var l := d.length()
	if l < 0.01:
		return
	var f := d / l
	_seq_k = _decay(_clock - _dash_t0, 0.08, 0.38)
	_side_flip = -_side_flip
	var sgn := _side_flip
	var out := (-f).rotated(Vector3.UP, sgn * randf_range(0.5, 1.0))
	var p := Vector3(to.x, Main.gy(to) + 0.1, to.z) - f * 0.25
	g._fan(p, _lift(out, randf_range(0.2, 0.5)), _roll(out, sgn * randf_range(0.2, 0.6)),
		randf_range(0.9, 1.4), 0.3, randf_range(1.0, 1.5) * k, randf_range(0.12, 0.16),
		SPIKY if randf() < 0.55 else CLOUD, -f * 3.0 + Vector3.UP.cross(f) * sgn * 1.5, tint, 0.6,
		randf() * 0.6)
	# 지나온 자리에 낮게 남는 구름 부채꼴
	if randf() < 0.5:
		g._fan(Vector3(from.x, Main.gy(from) + 0.05, from.z), _lift(-f, 0.12), Vector3.UP, randf_range(1.6, 2.2), 0.4,
			randf_range(1.1, 1.5) * k, 0.14, CLOUD, -f * 1.5, tint, 0.3, 0.7)


## 대시 제동: 관성으로 앞으로 쏟아지는 낮은 구름 부채꼴
static func dash_stop(pos: Vector3, dir: Vector3) -> void:
	var g := _host()
	if g == null:
		return
	_seq_k = 0.5
	var f := _flat(dir)
	var base := Vector3(pos.x, Main.gy(pos) + 0.06, pos.z)
	g._fan(base, _lift(f, 0.2), Vector3.UP, 2.0, 0.35, 1.5, 0.18, CLOUD, f * 2.5, Color.WHITE, 0.0, 0.6)
	g._fan(base + f * 0.15, _lift(f, 0.35), _roll(f, randf_range(-0.3, 0.3)), 1.6, 0.3, 1.3, 0.16, CLOUD, f * 3.0)


# ── 부스터 ───────────────────────────────────────────

## 부스터 점화: 분사가 바닥을 때려 사방으로 깔리는 부채꼴 고리
static func boost_burst(pos: Vector3, dir: Vector3) -> void:
	var g := _host()
	if g == null:
		return
	_boost_t0 = _clock
	_seq_k = 1.0
	var off := randf() * TAU
	var gy := Main.gy(pos)
	for i in 5:
		var a := off + TAU * i / 5.0
		var d := Vector3(sin(a), 0, cos(a))
		var p := Vector3(pos.x, gy + 0.05, pos.z) + d * 0.15
		g._fan(p, _lift(d, randf_range(0.12, 0.3)), Vector3.UP, 1.5, 0.4, randf_range(1.6, 2.1), randf_range(0.18, 0.22),
			SPIKY if i % 2 == 0 else CLOUD, d * 3.0, Pal.JET, 0.9, 0.3 if i % 2 else 0.0)


## 부스터 비행 중: 분사구 아래 바닥을 때린 배기가 뒤로 부채꼴로 찢겨 나간다
static func boost_wash(jet_pos: Vector3, carrier: Vector3) -> void:
	if randf() < 0.45:
		return
	var g := _host()
	if g == null:
		return
	_seq_k = _decay(_clock - _boost_t0, 0.15, 0.4)
	var sp := Vector3(carrier.x, 0, carrier.z)
	var back := _flat(-sp, Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU))
	var d := back.rotated(Vector3.UP, randf_range(-0.8, 0.8))
	var p := Vector3(jet_pos.x, Main.gy(jet_pos) + 0.06, jet_pos.z)
	var hot := Pal.JET.lerp(Pal.JET_CORE, randf() * 0.4)
	g._fan(p, _lift(d, randf_range(0.1, 0.35)), _roll(d, randf_range(-0.4, 0.4)), randf_range(0.9, 1.4), 0.25,
		randf_range(0.8, 1.2), randf_range(0.1, 0.14), SPIKY if randf() < 0.5 else CLOUD,
		sp * 0.35 + d * 2.0, hot, 1.0, randf() * 0.5)


# ── 광선검 ───────────────────────────────────────────

## 이번 틱에 칼이 쓸고 간 면 (손잡이 h0→h1, 칼끝 t0→t1) 을 덮는 초승달 부채꼴.
## 뿌리는 손잡이, 바깥 호는 칼끝 너머로 뻗고, 휘두른 방향으로 조금 더 돌며 파여 사라진다.
## carrier: 몸이 통째로 움직이는 속도 (돌진)
static func blade_fan(h0: Vector3, t0: Vector3, h1: Vector3, t1: Vector3, dt: float,
		tint: Color, w := 1.0, carrier := Vector3.ZERO) -> void:
	var g := _host()
	if g == null or dt <= 0.0001:
		return
	var d0 := t0 - h0
	var d1 := t1 - h1
	var bl := (d0.length() + d1.length()) * 0.5
	if bl < 0.1:
		return
	d0 = d0.normalized()
	d1 = d1.normalized()
	var ang := d0.angle_to(d1)
	if ang < 0.2:
		return
	# 잠시 끊겼다 다시 휘두르면 새 스윙: 첫 부채꼴만 크고 이어지는 것은 작다
	if _clock - _blade_last > 0.1:
		_blade_t0 = _clock
	_blade_last = _clock
	_seq_k = _decay(_clock - _blade_t0, 0.05, 0.45)
	var nrm := d0.cross(d1).normalized()
	var mid := (d0 + d1).normalized()
	var root := (h0 + h1) * 0.5
	var rate := clampf(ang / dt, 0.0, 60.0)
	var span := clampf(ang * 1.2, 0.5, 2.6)
	# 칼이 돌던 방향(접선)으로 기체가 계속 밀려 나간다
	var tangent := nrm.cross(mid) * minf(rate * bl * 0.12, 9.0)
	g._fan(root, mid, nrm, span, bl * 1.0, bl * randf_range(1.35, 1.55) * (0.8 + w * 0.2), randf_range(0.12, 0.15),
		BLADE, carrier * 0.5 + tangent, tint, 0.9, 0.0, rate * 0.06, 3.5)
	# 칼끝 바깥으로 흩어지는 가시 겹 (짙은 뒷겹)
	if w > 0.6:
		g._fan(root, mid.rotated(nrm, ang * 0.2), nrm, span * 0.7, bl * 0.8, bl * randf_range(1.4, 1.65),
			randf_range(0.1, 0.13), SPIKY, carrier * 0.5 + tangent * 1.2, tint, 0.5, 0.8, rate * 0.09, 3.5)


## 살아있는 부채꼴 수 (확인용)
static func count() -> int:
	return inst._n if inst and is_instance_valid(inst) else 0
