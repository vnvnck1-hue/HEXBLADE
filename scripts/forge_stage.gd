extends Node3D
## 용광로 보스전 전장 (형상 + 연출). 판정은 forge_main.gd / forge_boss.gd 가 이 파일의 반경(radius)을 읽는다.
## 팔각 발판(안쪽 판 + 바깥 고리 8조각)이 사방의 용암 위에 떠 있고, 둘레에 용광로 벽·쇳물 통·쇠사슬 도가니·용암 폭포가 선다.
## 2페이즈: 바깥 고리 조각이 달아올라 차례로 용암에 가라앉고 전장이 좁아진다 (collapse()).
## 불길·연기·튀는 부품(fling)·바닥 경고(부채꼴/원)도 여기서 그린다. 모두 판정과 무관하다.

const BT := preload("res://scripts/boss_tank.gd")

const R_OUTER := 12.0             # 처음 발판 반경 (팔각형 중심 ~ 변 거리)
const R_INNER := 8.0              # 붕괴 후 남는 안쪽 발판
const DEPTH := 3.4                # 발판 두께
const LAVA_Y := -1.1
const COS8 := 0.9238795           # cos(22.5°) : 변 거리 → 꼭짓점 거리

var radius := R_OUTER             # 지금 걸을 수 있는 반경
var segments: Array[Node3D] = []  # 바깥 고리 8조각 (k: 변 법선 각도 45°·k, +X 부터 +Z 쪽으로)
var seg_meshes: Array[MeshInstance3D] = []
var lava_mat: ShaderMaterial
var floor_mat: ShaderMaterial
var side_mat: ShaderMaterial
var fall_mat: ShaderMaterial
var pool_mat: ShaderMaterial
var fan_mat: ShaderMaterial
var crucibles: Array = []         # {pivot, bucket, phase, amp, tip}
var fires: Array = []             # [node, vel, life, max_life, grav, s0, s1]
var flings: Array = []            # [node, vel, spin, life]
var rim_lights: Array[OmniLight3D] = []
var heat := 0.0                   # 용암 활성도 (2페이즈에 오른다)
var t := 0.0
var _smoke_t := 0.0
var _puff_mesh: SphereMesh
var _puff_mats: Array[ShaderMaterial] = []
var _quad: QuadMesh


# ── 팔각형 계산 ─────────────────────────────────────────

## 중심에서의 팔각 거리 (변이 ±X·±Z 를 향한 팔각형)
static func oct_dist(p: Vector3) -> float:
	var ax := absf(p.x)
	var az := absf(p.z)
	return maxf(maxf(ax, az), (ax + az) * 0.70710678)


## 팔각형 안으로 밀어 넣는다 (y 는 그대로)
static func clamp_inside(p: Vector3, apothem: float) -> Vector3:
	for _pass in 2:
		for k in 8:
			var a := k * PI / 4.0
			var n := Vector3(cos(a), 0, sin(a))
			var d := p.x * n.x + p.z * n.z - apothem
			if d > 0.0:
				p -= n * d
	return p


# ── 셰이더 ──────────────────────────────────────────────

const NOISE := """
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float s = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { s += vnoise(p) * a; p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return s;
}
"""

const LAVA_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float heat = 0.0;
uniform float r_edge = 12.0;
varying vec3 wp;
NOISE
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wp.xz;
	vec2 q = vec2(fbm(p * 0.07 + vec2(TIME * 0.03, 0.0)), fbm(p * 0.07 + vec2(5.2, TIME * 0.025)));
	float n = fbm(p * 0.2 + q * 3.2 + vec2(-TIME * 0.05, TIME * 0.035));
	float hot = smoothstep(0.36, 0.7, n);
	float vein = smoothstep(0.64, 0.86, n);
	vec3 crust = vec3(0.32, 0.05, 0.02);
	vec3 orange = vec3(1.0, 0.3, 0.04);
	vec3 yellow = vec3(1.0, 0.76, 0.25);
	vec3 c = mix(crust, orange, hot);
	c = mix(c, yellow, vein);
	// 발판 가장자리에 닿는 곳은 더 달아오른다
	float o = max(max(abs(p.x), abs(p.y)), (abs(p.x) + abs(p.y)) * 0.7071);
	float edge = smoothstep(2.6, 0.0, abs(o - r_edge));
	c = mix(c, mix(orange, yellow, 0.35), edge * 0.55);
	float pulse = 0.85 + 0.15 * sin(TIME * 1.7 + n * 9.0);
	float fog = smoothstep(32.0, 75.0, length(p));
	ALBEDO = c * 0.2;
	EMISSION = c * (0.95 + heat * 0.55) * pulse * (1.0 - fog * 0.75);
	ROUGHNESS = 0.35;
	SPECULAR = 0.6;
}
"""

const FLOOR_SHADER := """
shader_type spatial;
uniform float edge_r = 12.0;
uniform float heat = 0.0;
instance uniform float crack = 0.0;
varying vec3 wp;
NOISE
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float line(float d, float w) { return 1.0 - smoothstep(0.0, w, abs(d)); }
void fragment() {
	vec2 p = wp.xz;
	float ang = atan(p.y, p.x);
	float k = floor(ang / 0.785398 + 0.5);
	float a = k * 0.785398;
	vec2 n = vec2(cos(a), sin(a));
	vec2 tg = vec2(-n.y, n.x);
	float u = dot(p, n);                  // 팔각 반경
	float v = dot(p, tg);                 // 변 방향 좌표
	float kk = mod(k + 8.0, 8.0);
	// 판마다 조금씩 다른 음영
	float ring = u < 3.2 ? 0.0 : (u < 5.6 ? 1.0 : (u < 8.0 ? 2.0 : (u < 10.2 ? 3.0 : 4.0)));
	float cell = floor(v / 2.6 + 0.5);
	float sh = hash2(vec2(kk * 7.0 + ring, cell)) * 0.045;
	vec3 col = vec3(0.19, 0.175, 0.22) + vec3(sh, sh * 0.9, sh * 1.2);
	if (u < 3.2) col = vec3(0.23, 0.215, 0.26);
	col *= 0.9 + 0.18 * vnoise(p * 5.0);
	// 이음선: 팔각 동심 고리 · 변 방향 칸 · 모서리 대각선
	float seam = 0.0;
	seam = max(seam, line(u - 2.6, 0.04) * 0.7);
	seam = max(seam, line(u - 3.2, 0.06));
	seam = max(seam, line(u - 5.6, 0.05));
	seam = max(seam, line(u - 8.0, 0.08));
	seam = max(seam, line(u - 10.2, 0.05));
	float vv = (fract(v / 2.6 + 0.5) - 0.5) * 2.6;
	seam = max(seam, line(vv, 0.045) * step(3.2, u) * (1.0 - step(10.2, u)));
	float c1 = a + 0.392699;
	float c2 = a - 0.392699;
	float dc = min(abs(dot(p, vec2(-sin(c1), cos(c1)))), abs(dot(p, vec2(-sin(c2), cos(c2)))));
	seam = max(seam, line(dc, 0.06));
	col = mix(col, vec3(0.06, 0.055, 0.075), seam * 0.85);
	vec3 em = vec3(0.0);
	// 대각선 구역의 격자 창살 (아래로 용암 빛이 비친다)
	if (mod(kk, 2.0) > 0.5 && u > 8.6 && u < 10.0 && abs(v) < 2.1) {
		float g = step(0.45, fract((u + v) * 2.6));
		col = mix(vec3(0.05, 0.03, 0.035), vec3(0.24, 0.22, 0.27), g);
		em += vec3(1.0, 0.3, 0.05) * (1.0 - g) * 0.35;
	}
	// 남·북 가장자리 경고 빗금
	if ((kk == 2.0 || kk == 6.0) && u > 10.5 && u < 11.3 && abs(v) < 3.4) {
		float stripe = step(0.5, fract((v + u) * 0.8));
		col = mix(vec3(0.06, 0.05, 0.05), vec3(0.95, 0.62, 0.08), stripe);
	}
	// 가장자리 황색 경고등
	float lamp = step(11.45, u) * (1.0 - step(11.85, u)) * step(abs(fract(v / 3.0) - 0.5), 0.1);
	em += vec3(1.0, 0.62, 0.12) * lamp * 2.6;
	col = mix(col, vec3(0.1, 0.09, 0.11), step(11.85, u));
	// 지금 가장자리 근처는 달아오른다
	float e = smoothstep(1.6, 0.0, edge_r - u);
	em += vec3(1.0, 0.25, 0.04) * e * (0.25 + 0.12 * sin(TIME * 3.0 + v)) * (1.0 + heat);
	// 붕괴 직전: 갈라진 틈에서 쇳물이 빛난다
	float cn = vnoise(p * 0.8) * 0.6 + vnoise(p * 2.2) * 0.4;
	float cr = line(cn - 0.5, 0.025 + 0.03 * crack) * crack;
	col *= 1.0 - crack * 0.35;
	em += mix(vec3(1.0, 0.3, 0.04), vec3(1.0, 0.8, 0.3), cr) * cr * 3.5 + vec3(1.0, 0.2, 0.02) * crack * 0.25;
	ALBEDO = col;
	EMISSION = em;
	ROUGHNESS = 0.72;
	METALLIC = 0.35;
}
"""

const SIDE_SHADER := """
shader_type spatial;
uniform float lava_y = -1.1;
instance uniform float crack = 0.0;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float h = clamp((wp.y - lava_y) / 1.5, 0.0, 1.0);
	vec3 col = vec3(0.12, 0.105, 0.14);
	float rib = step(0.82, fract((wp.x + wp.z) * 0.7));
	col *= 0.75 + rib * 0.5;
	float lip = smoothstep(-0.3, -0.08, wp.y);
	col = mix(col, vec3(0.26, 0.24, 0.29), lip);
	vec3 em = vec3(1.0, 0.32, 0.05) * pow(1.0 - h, 2.2) * 1.8 + vec3(1.0, 0.35, 0.05) * crack * 0.8;
	ALBEDO = col;
	EMISSION = em;
	ROUGHNESS = 0.8;
}
"""

const FALL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
NOISE
void fragment() {
	vec2 uv = UV;
	float n = vnoise(vec2(uv.x * 5.0, uv.y * 4.0 - TIME * 2.2)) * 0.6 + vnoise(vec2(uv.x * 13.0, uv.y * 9.0 - TIME * 3.6)) * 0.4;
	float edge = smoothstep(0.0, 0.22, uv.x) * smoothstep(1.0, 0.78, uv.x);
	if (n * edge < 0.12) discard;
	vec3 c = mix(vec3(1.0, 0.28, 0.04), vec3(1.0, 0.82, 0.32), smoothstep(0.45, 0.85, n));
	ALBEDO = c * (1.4 + n * 0.8);
}
"""

## 쇳물 웅덩이 (내려찍기·슬래그가 남기는 위험 지대)
const POOL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, blend_mix;
instance uniform float fade = 1.0;
NOISE
void fragment() {
	vec2 c = UV - 0.5;
	float r = length(c) * 2.0;
	float n = vnoise(UV * 7.0 + vec2(TIME * 0.6, -TIME * 0.4));
	float shape = 1.0 - smoothstep(0.72 + n * 0.22, 0.98, r);
	if (shape < 0.02) discard;
	vec3 col = mix(vec3(1.0, 0.28, 0.03), vec3(1.0, 0.85, 0.35), smoothstep(0.6, 0.0, r) * (0.6 + 0.4 * n));
	float crust = smoothstep(0.35, 0.95, 1.0 - fade + n * 0.5);
	col = mix(col, vec3(0.12, 0.05, 0.04), crust * 0.85);
	ALBEDO = col * 1.9;
	ALPHA = shape * clamp(fade * 3.0, 0.0, 1.0);
}
"""

## 바닥 부채꼴·원 경고. 중심 방향 dir_a 는 +Z 기준, +X 쪽으로 양수.
const FAN_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, blend_add;
instance uniform float progress = 0.0;
instance uniform float dir_a = 0.0;
instance uniform float half_a = 0.5;
instance uniform float r_in = 0.0;
instance uniform float r_out = 10.0;
instance uniform vec4 tint : source_color = vec4(1.0, 0.28, 0.1, 1.0);
varying vec2 lp;
void vertex() { lp = VERTEX.xz; }
void fragment() {
	float r = length(lp);
	float a = atan(lp.x, lp.y);
	float da = abs(mod(a - dir_a + 3.14159265, 6.2831853) - 3.14159265);
	if (r > r_out || r < r_in || da > half_a) discard;
	float er = smoothstep(r_out - 0.3, r_out, r) + (r_in > 0.01 ? 1.0 - smoothstep(r_in, r_in + 0.3, r) : 0.0);
	float ea = half_a < 3.1 ? smoothstep(half_a - 0.3 / max(r, 0.6), half_a, da) : 0.0;
	float edge = clamp(max(er, ea), 0.0, 1.0);
	float p = clamp(progress, 0.0, 1.0);
	float fill = step((r - r_in) / max(r_out - r_in, 0.01), smoothstep(0.0, 0.85, p));
	float wave = step(0.84, fract(r * 0.55 - TIME * 2.4));
	float blink = mix(1.0, 0.45 + 0.55 * step(0.5, fract(TIME * 14.0)), step(0.8, p));
	float i = (0.1 + 0.12 * p + fill * (0.2 + 0.25 * p) + wave * 0.1 + edge * (1.0 + 0.8 * p)) * blink;
	ALBEDO = tint.rgb * i;
}
"""

const PUFF_SHADER := """
shader_type spatial;
render_mode unshaded, MODE, depth_draw_never, cull_back, shadows_disabled;
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float fade = 1.0;
void fragment() {
	float rim = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = tint.rgb * (1.0 + 0.6 * rim);
	ALPHA = tint.a * fade * pow(rim, 1.5);
}
"""


func _shader(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code.replace("NOISE", NOISE)
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


# ── 구성 ────────────────────────────────────────────────

func _ready() -> void:
	lava_mat = _shader(LAVA_SHADER)
	floor_mat = _shader(FLOOR_SHADER)
	side_mat = _shader(SIDE_SHADER)
	fall_mat = _shader(FALL_SHADER)
	pool_mat = _shader(POOL_SHADER)
	fan_mat = _shader(FAN_SHADER)
	_quad = QuadMesh.new()
	_quad.orientation = PlaneMesh.FACE_Y
	_quad.size = Vector2(1, 1)
	_puff_mesh = SphereMesh.new()
	_puff_mesh.radius = 0.5
	_puff_mesh.height = 1.0
	_puff_mesh.radial_segments = 12
	_puff_mesh.rings = 6
	for i in 2:
		var m := _shader(PUFF_SHADER.replace("MODE", "blend_add" if i == 1 else "blend_mix"))
		_puff_mats.append(m)

	var lava := MeshInstance3D.new()
	var lp := PlaneMesh.new()
	lp.size = Vector2(180, 180)
	lp.subdivide_width = 0
	lava.mesh = lp
	lava.material_override = lava_mat
	lava.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lava.position = Vector3(0, LAVA_Y, -10)
	add_child(lava)

	_build_platform()
	_build_boss_pit()
	_build_back_wall()
	for side in [-1, 1]:
		_build_side(side)
	_build_front()
	_build_embers()
	_build_lights()


## 발판: 안쪽 팔각 판 1개 + 바깥 고리 사다리꼴 8조각. 윗면은 월드 좌표 셰이더라 조각이 달라도 무늬가 이어진다.
func _build_platform() -> void:
	var inner := MeshInstance3D.new()
	inner.mesh = _prism_mesh(0.0, R_INNER, 0, 8)
	add_child(inner)
	for k in 8:
		var seg := Node3D.new()
		seg.name = "Seg%d" % k
		add_child(seg)
		var mi := MeshInstance3D.new()
		mi.mesh = _prism_mesh(R_INNER, R_OUTER, k, 1)
		mi.set_instance_shader_parameter("crack", 0.0)
		seg.add_child(mi)
		segments.append(seg)
		seg_meshes.append(mi)
		# 가장자리 턱과 받침 기둥 (조각과 함께 가라앉는다)
		var a := k * PI / 4.0
		var n := Vector3(cos(a), 0, sin(a))
		var tg := Vector3(-n.z, 0, n.x)
		var yaw := atan2(n.x, n.z)
		for s in [-1, 1]:
			var p: Vector3 = n * (R_OUTER + 0.25) + tg * s * 3.3
			BT.rbox(seg, Vector3(1.2, 0.5, 0.7), 0.15, p + Vector3(0, -0.1, 0), Color("2e2a36"), Vector3(0, rad_to_deg(yaw), 0))
			BT.glow(seg, Vector3(0.5, 0.14, 0.2), p + Vector3(0, 0.2, 0) + n * 0.15, Color("ffb030"), 2.4, Vector3(0, rad_to_deg(yaw), 0))
		BT.rbox(seg, Vector3(2.2, 3.0, 1.4), 0.3, n * (R_OUTER - 0.3) + Vector3(0, -2.6, 0), Color("25222c"), Vector3(0, rad_to_deg(yaw), 0))


## 팔각 기둥(ring_k 조각) 메시. r_in = 0 이면 속이 찬 팔각판. 윗면은 floor_mat, 옆면은 side_mat.
func _prism_mesh(r_in: float, r_out: float, k0: int, count: int) -> ArrayMesh:
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	var side := SurfaceTool.new()
	side.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ci := r_in / COS8
	var co := r_out / COS8
	for kk in count:
		var k := k0 + kk
		var a0 := k * PI / 4.0 - PI / 8.0
		var a1 := k * PI / 4.0 + PI / 8.0
		var o0 := Vector3(cos(a0), 0, sin(a0)) * co
		var o1 := Vector3(cos(a1), 0, sin(a1)) * co
		var i0 := Vector3(cos(a0), 0, sin(a0)) * ci
		var i1 := Vector3(cos(a1), 0, sin(a1)) * ci
		var dn := Vector3(0, -DEPTH, 0)
		# 윗면 (위에서 볼 때 앞면)
		_tri(top, i0, o1, o0, Vector3.UP)
		_tri(top, i0, i1, o1, Vector3.UP)
		# 바깥 옆면
		var nout := Vector3(cos(k * PI / 4.0), 0, sin(k * PI / 4.0))
		_quad_face(side, o0, o1, o1 + dn, o0 + dn, nout)
		if r_in > 0.0:
			_quad_face(side, i1, i0, i0 + dn, i1 + dn, -nout)
			# 조각 양 끝 (가라앉을 때 보인다)
			var n0 := (o0 - i0).cross(Vector3.UP).normalized()
			_quad_face(side, i0, o0, o0 + dn, i0 + dn, n0)
			var n1 := Vector3.UP.cross(o1 - i1).normalized()
			_quad_face(side, o1, i1, i1 + dn, o1 + dn, n1)
	var m := ArrayMesh.new()
	top.commit(m)
	m.surface_set_material(0, floor_mat)
	side.commit(m)
	m.surface_set_material(1, side_mat)
	return m


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	# Godot 은 시계 방향(바깥에서 볼 때)이 앞면
	var fn := (b - a).cross(c - a)
	if fn.dot(n) > 0.0:
		var tmp := b
		b = c
		c = tmp
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_uv(Vector2(v.x, v.z))
		st.add_vertex(v)


func _quad_face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_tri(st, a, b, c, n)
	_tri(st, a, c, d, n)


## 보스가 솟아오르는 용광로 구덩이: 발판 북쪽 뒤 반원형 둑 + 달아오른 안쪽 테
func _build_boss_pit() -> void:
	var c := Vector3(0, 0, -17.0)
	for i in 15:
		var a := deg_to_rad(lerpf(-200.0, 20.0, i / 14.0))
		var p := c + Vector3(cos(a), 0, sin(a)) * 11.5
		var yaw := rad_to_deg(atan2(cos(a), sin(a)))
		var h := 3.0 + (i % 3) * 0.6
		BT.rbox(self, Vector3(4.6, h, 3.0), 0.5, p + Vector3(0, LAVA_Y + h * 0.5 - 0.6, 0), Color("2a2631"), Vector3(0, yaw, 0))
		BT.glow(self, Vector3(3.8, 0.14, 0.14), p + Vector3(0, LAVA_Y + h - 0.35, 0) - Vector3(cos(a), 0, sin(a)) * 1.55, Color("ff6a14"), 2.2, Vector3(0, yaw, 0))
		if i % 2 == 0:
			BT.rbox(self, Vector3(1.1, 1.8, 1.1), 0.25, p + Vector3(0, LAVA_Y + h + 0.6, 0), Color("38333f"), Vector3(0, yaw, 0))


## 북쪽 뒤 용광로 벽: 계단형 벽체 + 발광 틈 + 쇳물이 쏟아지는 주둥이와 용암 폭포
func _build_back_wall() -> void:
	for i in 13:
		var x := lerpf(-36.0, 36.0, i / 12.0)
		var h := 10.0 + fmod(i * 5.3, 6.0) + (4.0 if absf(x) < 8.0 else 0.0)
		var z := -31.0 - fmod(i * 2.7, 3.0)
		BT.rbox(self, Vector3(6.2, h, 6.0), 0.6, Vector3(x, LAVA_Y + h * 0.5, z), Color("221f29"))
		for k in 3:
			BT.glow(self, Vector3(3.6, 0.16, 0.1), Vector3(x, LAVA_Y + h * (0.3 + 0.22 * k), z + 3.02), Color("ff5a14") if (i + k) % 2 == 0 else Color("ffa030"), 1.6)
	for x in [-15.0, 14.0, 26.0]:
		var top := 11.0
		BT.rbox(self, Vector3(2.4, 1.4, 3.0), 0.4, Vector3(x, top, -27.2), Color("3a3440"))
		BT.cyl(self, 0.8, 0.8, 1.2, Vector3(x, top - 0.3, -25.8), Color("2c2833"), Vector3(90, 0, 0))
		_lava_fall(Vector3(x, top - 0.5, -25.2), top - 0.5 - LAVA_Y, 1.7)
	# 벽 앞 수평 배관
	for y in [3.0, 6.5]:
		BT.cyl(self, 0.55, 0.55, 64.0, Vector3(0, y, -27.8), Color("3a3542"), Vector3(0, 0, 90), 14)


## 용암 폭포: 위에서 아래로 흐르는 무늬의 세로 판 + 떨어지는 곳의 불꽃
func _lava_fall(top: Vector3, h: float, w: float) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = fall_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.position = top + Vector3(0, -h * 0.5, 0)
	var q2 := mi.duplicate() as MeshInstance3D
	add_child(q2)
	q2.rotation.y = PI * 0.5
	q2.scale = Vector3(0.7, 1, 1)
	_falls.append(Vector3(top.x, LAVA_Y, top.z))


var _falls: Array[Vector3] = []


## 좌우: 쇳물 통, 기계 블록, 끊긴 통로, 쇠사슬 도가니, 기둥
func _build_side(side: int) -> void:
	var sx := float(side)
	# 쇳물 통 (윗면이 용암)
	var vat := Vector3(sx * 21.5, 0, -6.5)
	BT.cyl(self, 3.5, 3.7, 5.0, vat + Vector3(0, LAVA_Y + 2.5, 0), Color("2d2934"), Vector3.ZERO, 28)
	BT.cyl(self, 3.75, 3.75, 0.5, vat + Vector3(0, LAVA_Y + 4.9, 0), Color("3c3746"), Vector3.ZERO, 28)
	for k in 3:
		BT.cyl(self, 3.78, 3.78, 0.2, vat + Vector3(0, LAVA_Y + 1.0 + k * 1.3, 0), Color("1f1c24"), Vector3.ZERO, 28)
	var top := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 3.3
	disc.bottom_radius = 3.3
	disc.height = 0.1
	disc.radial_segments = 28
	top.mesh = disc
	top.material_override = lava_mat
	add_child(top)
	top.position = vat + Vector3(0, LAVA_Y + 4.85, 0)
	_vats.append(top.position)
	_lava_fall(vat + Vector3(-sx * 3.6, LAVA_Y + 4.9, 1.0), 4.9, 1.4)
	# 기계 블록과 배관
	for b in [[Vector3(26.0, 0, 5.0), Vector3(6.0, 7.0, 8.0)], [Vector3(24.0, 0, 15.5), Vector3(7.0, 4.5, 6.0)], [Vector3(27.5, 0, -17.0), Vector3(6.0, 9.5, 7.0)]]:
		var p: Vector3 = b[0] * Vector3(sx, 1, 1)
		var s: Vector3 = b[1]
		BT.rbox(self, s, 0.5, p + Vector3(0, LAVA_Y + s.y * 0.5, 0), Color("27232e"))
		BT.rbox(self, s * Vector3(0.8, 0.12, 0.8), 0.2, p + Vector3(0, LAVA_Y + s.y + 0.2, 0), Color("3a3543"))
		for k in 2:
			BT.glow(self, Vector3(0.12, 0.2, s.z * 0.6), p + Vector3(-sx * (s.x * 0.5 + 0.02), LAVA_Y + s.y * (0.4 + k * 0.3), 0), Color("ff7a20"), 1.8)
	BT.cyl(self, 0.45, 0.45, 20.0, Vector3(sx * 22.8, 5.2, 0), Color("3b3644"), Vector3(90, 0, 0), 12)
	BT.cyl(self, 0.3, 0.3, 12.0, Vector3(sx * 23.4, 3.2, 8.0), Color("4a4454"), Vector3(90, 0, 0), 10)
	# 끊긴 통로: 발판 동·서쪽 변에서 설비 쪽으로 이어지던 다리 (난간 포함)
	var cz := 3.0
	var x0 := sx * (R_OUTER + 0.6)
	var x1 := sx * 21.0
	var mid := (x0 + x1) * 0.5
	var ln := absf(x1 - x0)
	BT.rbox(self, Vector3(ln, 0.35, 2.8), 0.1, Vector3(mid, -0.35, cz), Color("34303c"))
	BT.rbox(self, Vector3(ln, 0.8, 0.5), 0.12, Vector3(mid, -0.9, cz), Color("25222b"))
	for s in [-1, 1]:
		BT.rbox(self, Vector3(ln, 0.1, 0.1), 0.04, Vector3(mid, 0.75, cz + s * 1.3), Color("6a6272"))
		for i in 5:
			BT.rbox(self, Vector3(0.1, 0.9, 0.1), 0.04, Vector3(lerpf(x0, x1, i / 4.0), 0.3, cz + s * 1.3), Color("5a5262"))
	# 붉은 차단막 (전장 밖으로 나갈 수 없다)
	for y in [0.35, 0.75]:
		BT.glow(self, Vector3(0.1, 0.1, 2.5), Vector3(sx * (R_OUTER + 1.3), y, cz), Color("ff2a3a"), 1.8)
	for s in [-1, 1]:
		BT.rbox(self, Vector3(0.22, 1.1, 0.22), 0.06, Vector3(sx * (R_OUTER + 1.3), 0.35, cz + s * 1.3), Color("2a2630"))
	# 기둥 + 가로 보 + 쇠사슬 도가니
	# 북쪽은 높은 기둥, 카메라에 가까운 남쪽은 낮은 기둥 (시야를 가리지 않게)
	for spot in [[Vector3(17.5, 0, -15.0), 17.0, 9.0], [Vector3(21.0, 0, 12.0), 9.5, 3.2]]:
		var base: Vector3 = (spot[0] as Vector3) * Vector3(sx, 1, 1)
		var top_y: float = spot[1]
		BT.rbox(self, Vector3(1.4, top_y - LAVA_Y + 3.0, 1.4), 0.3, base + Vector3(sx * 2.4, (top_y + LAVA_Y + 3.0) * 0.5, 0), Color("2b2732"))
		BT.rbox(self, Vector3(5.0, 0.8, 1.0), 0.2, base + Vector3(sx * 0.4, top_y, 0), Color("36313e"))
		_crucible(base + Vector3(-sx * 1.4, top_y - 0.4, 0), spot[2])


var _vats: Array[Vector3] = []


## 쇠사슬에 매달린 도가니. 흔들리고, 슬래그 패턴에서 기울어 쇳물을 쏟는다.
func _crucible(hang: Vector3, chain_len := 9.0) -> void:
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.position = hang
	for i in 16:
		var y := -0.3 - i * (chain_len / 16.0)
		BT.rbox(pivot, Vector3(0.14, 0.62, 0.34) if i % 2 == 0 else Vector3(0.34, 0.62, 0.14), 0.06, Vector3(0, y, 0), Color("4a4450"))
	var bucket := Node3D.new()
	pivot.add_child(bucket)
	bucket.position = Vector3(0, -chain_len - 1.4, 0)
	BT.rbox(bucket, Vector3(2.4, 0.3, 0.3), 0.1, Vector3(0, 1.35, 0), Color("3a3542"))
	BT.cyl(bucket, 1.35, 1.0, 2.2, Vector3.ZERO, Color("2e2a35"), Vector3.ZERO, 18)
	BT.cyl(bucket, 1.42, 1.42, 0.25, Vector3(0, 1.0, 0), Color("423c4c"), Vector3.ZERO, 18)
	var molten := Pal.flat_mesh(_disc(1.2), Color("ffa030"), 2.2)
	molten.position = Vector3(0, 0.95, 0)
	bucket.add_child(molten)
	crucibles.append({"pivot": pivot, "bucket": bucket, "phase": randf() * TAU, "amp": randf_range(0.03, 0.06), "tip": 0.0, "tip_to": 0.0})


func _disc(r: float) -> CylinderMesh:
	var d := CylinderMesh.new()
	d.top_radius = r
	d.bottom_radius = r
	d.height = 0.06
	d.radial_segments = 18
	return d


## 화면 아래쪽(남쪽) 앞 구조물: 발판 남쪽 턱 아래 계단형 받침과 앞 난간 조각
func _build_front() -> void:
	for sx in [-1.0, 1.0]:
		BT.rbox(self, Vector3(8.0, 3.0, 4.0), 0.5, Vector3(sx * 16.0, LAVA_Y + 1.2, 17.5), Color("26222c"))
		BT.glow(self, Vector3(6.0, 0.14, 0.12), Vector3(sx * 16.0, LAVA_Y + 2.4, 15.48), Color("ff8a2a"), 1.8)
	BT.rbox(self, Vector3(6.0, 0.5, 5.0), 0.15, Vector3(0, -0.5, 14.5), Color("302c38"))
	BT.glow(self, Vector3(5.0, 0.12, 0.12), Vector3(0, -0.22, 12.1), Color("ffb030"), 2.0)


## 용암에서 끊임없이 피어오르는 불티
func _build_embers() -> void:
	var p := GPUParticles3D.new()
	p.amount = 260
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-40, -5, -40), Vector3(80, 30, 80))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(34, 0.3, 26)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 3.2
	pm.gravity = Vector3(0.2, 0.35, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.4
	pm.turbulence_noise_scale = 4.0
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 0.75, 1.0])
	grad.colors = PackedColorArray([Color(1, 0.9, 0.5, 0), Color(1, 0.75, 0.3, 1), Color(1, 0.35, 0.05, 1), Color(0.5, 0.1, 0.02, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var box := BoxMesh.new()
	box.size = Vector3(0.07, 0.07, 0.07)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(3.0, 2.0, 1.2)
	box.material = m
	p.draw_pass_1 = box
	add_child(p)
	p.position = Vector3(0, LAVA_Y + 0.2, -6)


## 용암 빛이 발판 옆면과 보스를 아래에서 비춘다
func _build_lights() -> void:
	for k in 8:
		var a := k * PI / 4.0 + PI / 8.0
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.42, 0.14)
		l.light_energy = 2.2
		l.omni_range = 11.0
		l.omni_attenuation = 1.4
		add_child(l)
		l.position = Vector3(cos(a), 0, sin(a)) * (R_OUTER / COS8 + 1.5) + Vector3(0, -0.2, 0)
		rim_lights.append(l)
	var back := OmniLight3D.new()
	back.light_color = Color(1.0, 0.45, 0.12)
	back.light_energy = 4.0
	back.omni_range = 26.0
	add_child(back)
	back.position = Vector3(0, 1.0, -21.0)
	for sx in [-1.0, 1.0]:
		var v := OmniLight3D.new()
		v.light_color = Color(1.0, 0.5, 0.16)
		v.light_energy = 3.0
		v.omni_range = 12.0
		add_child(v)
		v.position = Vector3(sx * 21.5, 5.5, -6.5)


# ── 매 프레임 ───────────────────────────────────────────

func _process(dt: float) -> void:
	t += dt
	lava_mat.set_shader_parameter("heat", heat)
	lava_mat.set_shader_parameter("r_edge", radius)
	floor_mat.set_shader_parameter("edge_r", radius)
	floor_mat.set_shader_parameter("heat", heat)
	for i in rim_lights.size():
		rim_lights[i].light_energy = (2.0 + heat * 1.2) * (0.85 + 0.15 * sin(t * 2.3 + i * 1.7))
	for c in crucibles:
		c.tip = move_toward(c.tip, c.tip_to, dt * 1.4)
		var sw: float = sin(t * 0.9 + c.phase) * c.amp
		(c.pivot as Node3D).rotation = Vector3(sw, 0, sw * 0.6)
		(c.bucket as Node3D).rotation.z = c.tip * 1.1 * (1.0 if (c.pivot as Node3D).position.x > 0.0 else -1.0)
		if c.tip > 0.5 and randf() < 0.5:
			var lip: Vector3 = (c.bucket as Node3D).to_global(Vector3(0, 1.0, 0))
			fire(lip, Vector3(randf_range(-0.5, 0.5), -6.0, randf_range(-0.5, 0.5)), 0.5, 0.55, Color(1.0, 0.55, 0.12, 0.9), true, -18.0)
	# 용암 기포 · 연기 · 폭포 불꽃
	_smoke_t -= dt
	if _smoke_t <= 0.0:
		_smoke_t = 0.12
		var a := randf() * TAU
		var r := randf_range(radius / COS8 + 1.0, 30.0)
		var p := Vector3(cos(a) * r, LAVA_Y + 0.1, sin(a) * r - 4.0)
		if randf() < 0.55:
			fire(p, Vector3(randf_range(-0.3, 0.3), randf_range(1.2, 2.2), 0), randf_range(1.8, 3.2), randf_range(1.6, 2.6), Color(0.25, 0.12, 0.1, 0.32), false, 0.3)
		else:
			FX.sparks(p, 5, [Color("ffe080"), Color("ff7a20")], 4.0, 0.6, -9.0, 0.07)
			fire(p, Vector3(0, 1.0, 0), 0.9, 0.5, Color(1.0, 0.45, 0.1, 0.8), true, 0.0)
		if not _falls.is_empty() and randf() < 0.6:
			var f: Vector3 = _falls[randi() % _falls.size()]
			fire(f + Vector3(randf_range(-0.6, 0.6), 0.2, 0.4), Vector3(randf_range(-1, 1), randf_range(2, 4), randf_range(0, 1.5)), 1.4, 0.7, Color(1.0, 0.5, 0.12, 0.7), true, -3.0)
			fire(f + Vector3(0, 0.4, 0.5), Vector3(0, 2.0, 0.5), 2.6, 1.8, Color(0.3, 0.15, 0.12, 0.3), false, 0.2)
		if not _vats.is_empty() and randf() < 0.3:
			var vp: Vector3 = _vats[randi() % _vats.size()]
			fire(vp + Vector3(randf_range(-2, 2), 0.3, randf_range(-2, 2)), Vector3(0, 1.6, 0), 2.4, 2.0, Color(0.35, 0.2, 0.18, 0.28), false, 0.3)
	_update_fires(dt)
	_update_flings(dt)


# ── 붕괴 ────────────────────────────────────────────────

## 바깥 고리 8조각을 달궜다가 order 순서대로 가라앉힌다. 전장 반경은 R_OUTER → R_INNER 로 줄어든다.
func collapse(order: Array, crack_time := 1.0, gap := 0.22) -> void:
	for i in order.size():
		var k: int = order[i]
		var seg := segments[k]
		var mi := seg_meshes[k]
		var tw := seg.create_tween()
		tw.tween_method(func(v: float): mi.set_instance_shader_parameter("crack", v), 0.0, 1.0, crack_time)
		tw.tween_interval(i * gap)
		tw.tween_callback(func(): _sink_fx(k))
		tw.tween_property(seg, "position:y", -DEPTH - 1.0, 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(seg, "rotation:x", randf_range(-0.12, 0.12), 1.4)
		tw.parallel().tween_property(seg, "rotation:z", randf_range(-0.12, 0.12), 1.4)
		tw.tween_callback(seg.hide)
	var rt := create_tween()
	rt.tween_interval(crack_time)
	rt.tween_property(self, "radius", R_INNER, gap * order.size() + 0.9).set_trans(Tween.TRANS_SINE)
	var ht := create_tween()
	ht.tween_property(self, "heat", 1.0, crack_time + gap * order.size() + 1.0)


func _sink_fx(k: int) -> void:
	var a := k * PI / 4.0
	var n := Vector3(cos(a), 0, sin(a))
	var tg := Vector3(-n.z, 0, n.x)
	for i in 5:
		var p := n * randf_range(R_INNER + 0.5, R_OUTER) + tg * randf_range(-3.5, 3.5)
		FX.sparks(p + Vector3(0, 0.3, 0), 10, [Color("fff0a0"), Color("ffa030"), Color("ff4a10")], 9.0, 0.6, -14.0, 0.09)
		fire(p + Vector3(0, 0.2, 0), Vector3(randf_range(-1, 1), randf_range(3, 6), randf_range(-1, 1)), 1.6, 0.8, Color(1.0, 0.45, 0.1, 0.85), true, -4.0)
		fire(p + Vector3(0, 0.6, 0), Vector3(0, 2.5, 0), 3.0, 1.6, Color(0.28, 0.14, 0.12, 0.4), false, 0.3)
	Sfx.play("boom", 0.2, -4.0)
	Main.inst.shake(0.25)


# ── 경고 표시 ───────────────────────────────────────────

## 바닥 부채꼴 경고. center 는 꼭짓점, dir_a 는 +Z 기준 각도(+X 쪽 양수). half ≥ PI 면 원.
func fan_warning(center: Vector3, dir_a: float, half: float, r_out: float, r_in := 0.0, tint := Color(1.0, 0.28, 0.1)) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.orientation = PlaneMesh.FACE_Y
	q.size = Vector2(r_out * 2.0, r_out * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = fan_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = Vector3(center.x, 0.04, center.z)
	mi.set_instance_shader_parameter("r_out", r_out)
	mi.set_instance_shader_parameter("r_in", r_in)
	mi.set_instance_shader_parameter("dir_a", dir_a)
	mi.set_instance_shader_parameter("half_a", half)
	mi.set_instance_shader_parameter("tint", tint)
	mi.set_instance_shader_parameter("progress", 0.0)
	return mi


func circle_warning(center: Vector3, r: float, tint := Color(1.0, 0.3, 0.08)) -> MeshInstance3D:
	return fan_warning(center, 0.0, PI + 0.1, r, 0.0, tint)


## 쇳물 웅덩이 표시 (수명 끝에 식어 사라진다)
func pool(center: Vector3, r: float, life: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	mi.material_override = pool_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = Vector3(center.x, 0.03 + randf() * 0.01, center.z)
	mi.scale = Vector3.ONE * 0.2
	mi.rotation.y = randf() * TAU
	mi.set_instance_shader_parameter("fade", 1.0)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(r * 2.2, 1, r * 2.2), 0.18).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): mi.set_instance_shader_parameter("fade", v), 1.0, 0.0, life)
	tw.tween_callback(mi.queue_free)
	return mi


# ── 불길 · 연기 ─────────────────────────────────────────

## 가장자리가 부드러운 구체 불길/연기. add=true 면 가산 혼합(빛나는 불), grav 는 위(+) 가속.
func fire(pos: Vector3, vel: Vector3, size: float, life: float, c: Color, add := true, grav := 1.5) -> void:
	if fires.size() > 900:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _puff_mesh
	mi.material_override = _puff_mats[1 if add else 0]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("tint", c)
	mi.set_instance_shader_parameter("fade", 1.0)
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * size * 0.35
	fires.append([mi, vel, life, life, grav, size * 0.35, size])


func _update_fires(dt: float) -> void:
	for i in range(fires.size() - 1, -1, -1):
		var f: Array = fires[i]
		var mi: MeshInstance3D = f[0]
		f[2] -= dt
		if f[2] <= 0.0 or not is_instance_valid(mi):
			if is_instance_valid(mi):
				mi.queue_free()
			fires.remove_at(i)
			continue
		var v: Vector3 = f[1]
		v.y += f[4] * dt
		v *= 1.0 - minf(1.0, 1.6 * dt)
		f[1] = v
		mi.global_position += v * dt
		var k: float = 1.0 - f[2] / f[3]
		mi.scale = Vector3.ONE * lerpf(f[5], f[6], 1.0 - pow(1.0 - k, 2.0))
		mi.set_instance_shader_parameter("fade", 1.0 - k * k)


## 떨어져 나간 부품: 포물선으로 날아가 발판에서는 튕기고, 용암에 닿으면 불꽃을 튀기며 가라앉는다.
func fling(n: Node3D, vel: Vector3, spin := Vector3.ZERO, life := 7.0) -> void:
	flings.append([n, vel, spin, life])


func _update_flings(dt: float) -> void:
	for i in range(flings.size() - 1, -1, -1):
		var e: Array = flings[i]
		var n: Node3D = e[0]
		if not is_instance_valid(n):
			flings.remove_at(i)
			continue
		var v: Vector3 = e[1]
		v.y -= 22.0 * dt
		var p := n.global_position + v * dt
		var on_floor := oct_dist(p) < radius
		var floor_y := 0.3 if on_floor else LAVA_Y - 0.2
		if p.y < floor_y and v.y < 0.0:
			if on_floor and v.y < -3.0:
				v.y = -v.y * 0.35
				v.x *= 0.6
				v.z *= 0.6
				e[2] = (e[2] as Vector3) * 0.6
				FX.sparks(p, 6, [Color("ffd060"), Color("ff6a20")], 5.0, 0.3, -8.0, 0.06)
				Sfx.play("land", 0.2, -8.0)
			elif on_floor:
				v = v * Vector3(0.9, 0.0, 0.9)
				p.y = floor_y
			else:
				# 용암에 빠진다
				_splash(Vector3(p.x, LAVA_Y, p.z), 1.0)
				var tw := n.create_tween()
				tw.tween_property(n, "global_position:y", LAVA_Y - 4.0, 1.6).set_ease(Tween.EASE_IN)
				tw.tween_callback(n.queue_free)
				flings.remove_at(i)
				continue
		n.global_position = p
		var sp: Vector3 = e[2]
		if sp.length() > 0.01:
			n.rotate(sp.normalized(), sp.length() * dt)
		e[1] = v
		e[3] -= dt
		if e[3] <= 0.0:
			n.queue_free()
			flings.remove_at(i)


## 용암이 튀어 오른다
func _splash(p: Vector3, k := 1.0) -> void:
	FX.sparks(p + Vector3(0, 0.2, 0), int(14 * k), [Color("fff0a0"), Color("ffa030"), Color("ff4a10")], 8.0 * sqrt(k), 0.7, -16.0, 0.1)
	for i in int(4 * k):
		fire(p + Vector3(randf_range(-1, 1), 0.2, randf_range(-1, 1)) * k, Vector3(randf_range(-1.5, 1.5), randf_range(2.5, 5.5), randf_range(-1.5, 1.5)) * sqrt(k), 1.2 * k, 0.6, Color(1.0, 0.5, 0.1, 0.85), true, -8.0)
	fire(p + Vector3(0, 0.5, 0), Vector3(0, 2.0, 0), 3.0 * k, 1.5, Color(0.3, 0.14, 0.12, 0.4), false, 0.3)


func splash(p: Vector3, k := 1.0) -> void:
	_splash(p, k)


## 슬래그 패턴: 도가니가 기울어 쇳물을 쏟는다
func tip_crucibles(on: bool) -> void:
	for c in crucibles:
		c.tip_to = 1.0 if on else 0.0
