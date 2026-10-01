extends Node3D
## 심연 성소의 배경과 소품. 모두 판정과 무관하다 (전장 격자는 abyss_stage.gd).
## 심연에서 솟은 거석 무리 · 북쪽 고딕 아치 실루엣 · 비스듬히 솟은 거대 가시 · 부서진 거대 후광 · 떠다니는 바위 ·
## 위에서 늘어진 사슬과 영혼 우리 · 거석을 타고 오르는 살덩이 관 · 가장자리를 떠도는 붉은 성유물 등불 ·
## 기둥 위 화로 · 바닥 가장자리의 촛대·뼈·잔해.
## 카메라가 남쪽 위에서 내려다보므로 남쪽 배경은 낮게 두어 전장을 가리지 않게 한다.

const ABYSS := Color(1.0, 0.07, 0.13)
const FLAME := Color(1.0, 0.32, 0.12)

var stage: Node3D
var rock_mat: ShaderMaterial
var flesh_mat: ShaderMaterial
var halo_mat: ShaderMaterial
var shaft_mat: ShaderMaterial
var iron_mat: StandardMaterial3D
var bone_mat: StandardMaterial3D
var t := 0.0
var _floaters: Array = []      # [node, base, phase, amp, spin]
var _swing: Array = []         # [pivot, phase, amp]
var _lanterns: Array = []      # [node, base, phase, light]
var _flames: Array = []        # [node(Node3D, 불꽃 위치), timer, size]
var _halo: Node3D
var _souls: Array = []         # 우리 속 혼불 [mesh, phase]

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

## 거석: 결이 거친 흑회색 판석. 아래로 갈수록 심연 빛을 받고, 윤곽은 진홍빛 테두리로 떠오른다.
const ROCK_SHADER := """
shader_type spatial;
uniform vec3 glow_col : source_color = vec3(1.0, 0.07, 0.13);
varying vec3 wp;
varying vec3 wn;
NOISE
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec2 q = abs(wn.x) > abs(wn.z) ? vec2(wp.z, wp.y) : vec2(wp.x, wp.y);
	if (abs(wn.y) > 0.7) q = wp.xz;
	float n = fbm(q * 0.28);
	float n2 = vnoise(q * 2.4);
	vec3 base = mix(vec3(0.035, 0.038, 0.045), vec3(0.09, 0.095, 0.105), n) * (0.85 + 0.3 * n2);
	float slab = step(0.965, fract(q.y * 0.22 + hash2(floor(q * 0.05)) * 0.3));
	float seam = step(0.975, fract(q.x * 0.31));
	base *= 1.0 - max(slab, seam) * 0.6;
	float under = smoothstep(-2.0, -26.0, wp.y);
	float down = clamp(-wn.y, 0.0, 1.0);
	float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 em = glow_col * (under * 0.16 + down * under * 0.35 + fr * (0.08 + under * 0.4));
	float vein = smoothstep(0.7, 0.82, vnoise(q * vec2(0.6, 0.25) + 3.0)) * under;
	em += glow_col * vein * 0.6;
	ALBEDO = base;
	EMISSION = em;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
}
"""

## 살덩이 관: 짙은 고동색 위로 맥동하는 핏줄
const FLESH_SHADER := """
shader_type spatial;
uniform vec3 glow_col : source_color = vec3(1.0, 0.07, 0.13);
varying vec3 wp;
NOISE
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float n = fbm(vec2(wp.x + wp.z, wp.y) * 1.3);
	vec3 base = mix(vec3(0.16, 0.035, 0.045), vec3(0.32, 0.08, 0.08), n);
	float pulse = 0.5 + 0.5 * sin(TIME * 2.2 - wp.y * 0.7);
	float vein = smoothstep(0.58, 0.72, vnoise(vec2((wp.x - wp.z) * 2.0, wp.y * 0.6)));
	float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = base;
	EMISSION = glow_col * (vein * (0.4 + pulse * 1.4) + fr * 0.15);
	ROUGHNESS = 0.35;
	SPECULAR = 0.6;
}
"""

## 부서진 후광: 흑철 위 안쪽 테두리를 따라 진홍 빛이 흐른다
const HALO_SHADER := """
shader_type spatial;
uniform vec3 glow_col : source_color = vec3(1.0, 0.07, 0.13);
varying vec3 lp;
NOISE
void vertex() { lp = VERTEX; }
void fragment() {
	float a = atan(lp.z, lp.x);
	float r = length(lp.xz);
	float flow = 0.5 + 0.5 * sin(a * 12.0 - TIME * 1.5);
	float inner = 1.0 - smoothstep(0.0, 0.6, abs(r - INNER_R));
	vec3 base = vec3(0.05, 0.05, 0.06) * (0.7 + 0.6 * vnoise(vec2(a * 20.0, r)));
	ALBEDO = base;
	EMISSION = glow_col * (inner * (0.6 + flow * 1.6) + 0.05);
	ROUGHNESS = 0.5;
	METALLIC = 0.6;
}
"""


## 빛기둥: 위 틈에서 떨어지는 빛. 볼류메트릭 안개의 계단 무늬 없이 부드럽게 보이도록 메시로 그린다.
## 높이 방향으로 아래가 옅어지고, 가장자리(시선과 비스듬한 면)는 사라지며, 먼지가 천천히 흘러내린다.
const SHAFT_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_add, depth_draw_never;
instance uniform vec4 tint : source_color = vec4(0.7, 0.8, 1.0, 1.0);
instance uniform float power = 1.0;
varying vec3 lp;
NOISE
void vertex() { lp = VERTEX; }
void fragment() {
	float h = clamp(lp.y + 0.5, 0.0, 1.0);      // 0 = 바닥, 1 = 꼭대기
	float fr = abs(dot(NORMAL, VIEW));
	float soft = pow(fr, 2.2);
	float a = atan(lp.z, lp.x);
	float streak = 0.7 + 0.3 * sin(a * 7.0 + sin(a * 3.0 + TIME * 0.2) * 2.0) * sin(h * 4.0 - TIME * 0.3);
	float fade = smoothstep(0.0, 0.3, h) * (1.0 - smoothstep(0.7, 1.0, h));
	ALBEDO = tint.rgb * soft * streak * 0.1 * fade * power;
}
"""


## 위에서 내려오는 빛기둥 (top → bottom, 아래 반지름 r)
func shaft(top: Vector3, bottom: Vector3, r: float, c: Color, power := 1.0) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r * 0.35
	cm.bottom_radius = r
	cm.height = 1.0
	cm.radial_segments = 24
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = shaft_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("tint", c)
	mi.set_instance_shader_parameter("power", power)
	add_child(mi)
	var d := top - bottom
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	mi.global_transform = Transform3D(Basis(x, y * d.length(), z), (top + bottom) * 0.5)
	return mi


func _shader(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code.replace("NOISE", NOISE)
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


func _ready() -> void:
	rock_mat = _shader(ROCK_SHADER)
	flesh_mat = _shader(FLESH_SHADER)
	halo_mat = _shader(HALO_SHADER.replace("INNER_R", "13.6"))
	shaft_mat = _shader(SHAFT_SHADER)
	iron_mat = Pal.lit(Color(0.09, 0.085, 0.09))
	bone_mat = Pal.lit(Color(0.5, 0.45, 0.38))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7041
	_monoliths(rng)
	_arches()
	_thorns(rng)
	_broken_halo()
	_floating_rocks(rng)
	_chains()
	_lanterns_ring()


# ── 기본 도형 ───────────────────────────────────────────

func _rock(size: Vector3, pos: Vector3, rot := Vector3.ZERO, taper := 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Build.bevel_mesh(size, minf(0.35, size.x * 0.08), taper)
	mi.material_override = rock_mat
	add_child(mi)
	mi.position = pos
	mi.rotation = rot
	return mi


func _spike(base: Vector3, dir: Vector3, length: float, r: float) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = length
	c.radial_segments = 6
	c.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = rock_mat
	add_child(mi)
	var d := dir.normalized()
	var b := Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.95 else Vector3.FORWARD)
	# 원기둥의 +Y 를 dir 쪽으로
	b = b * Basis(Vector3.RIGHT, -PI * 0.5)
	mi.global_transform = Transform3D(b, base + d * length * 0.5)
	return mi


# ── 거석 무리 ───────────────────────────────────────────

func _monoliths(rng: RandomNumberGenerator) -> void:
	var count := 22
	for k in count:
		var a := TAU * k / count + rng.randf_range(-0.12, 0.12)
		var r := rng.randf_range(23.0, 40.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		# 남쪽(카메라 쪽)은 낮게: 화면 아래에서 전장을 가리지 않는다
		var south := clampf(p.z / r, 0.0, 1.0)
		var top := lerpf(rng.randf_range(4.0, 24.0), rng.randf_range(-9.0, -4.0), smoothstep(0.1, 0.55, south))
		var bottom := -48.0
		var w := rng.randf_range(3.0, 7.5)
		var d := rng.randf_range(3.0, 7.0)
		var h := top - bottom
		var lean := Vector3(rng.randf_range(-0.07, 0.07), rng.randf_range(-0.4, 0.4), rng.randf_range(-0.07, 0.07))
		var m := _rock(Vector3(w, h, d), Vector3(p.x, bottom + h * 0.5, p.z), lean, rng.randf_range(0.75, 1.0))
		# 부서진 머리: 기울어진 덩어리 하나를 얹는다
		if rng.randf() < 0.55:
			var cap := Vector3(w * rng.randf_range(0.5, 0.9), rng.randf_range(1.5, 4.0), d * rng.randf_range(0.5, 0.9))
			_rock(cap, Vector3(p.x + rng.randf_range(-1, 1), top + cap.y * 0.4, p.z + rng.randf_range(-1, 1)),
				Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(0, TAU), rng.randf_range(-0.4, 0.4)))
		# 곁기둥
		if rng.randf() < 0.7:
			var off := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * (w * 0.5 + rng.randf_range(1.5, 3.0))
			var top2 := top - rng.randf_range(3.0, 10.0)
			var h2 := top2 - bottom
			_rock(Vector3(w * 0.5, h2, d * 0.5), Vector3(p.x + off.x, bottom + h2 * 0.5, p.z + off.z), lean * 1.5)
		# 거석을 타고 오르는 살덩이 관
		if rng.randf() < 0.45 and top > -2.0:
			_tendril(Vector3(p.x, -18.0, p.z) - p.normalized() * (d * 0.5 + 0.2), top - rng.randf_range(1.0, 5.0), p.normalized(), rng)
		m.name = "Monolith%d" % k


## 굵은 관 하나: 거석 안쪽 면을 구불구불 타고 오른다
func _tendril(from: Vector3, top_y: float, out: Vector3, rng: RandomNumberGenerator) -> void:
	var side := Vector3(-out.z, 0, out.x)
	var segs := 14
	var prev := from
	var ph := rng.randf() * TAU
	for i in segs:
		var k := float(i + 1) / segs
		var y := lerpf(from.y, top_y, k)
		var p := Vector3(from.x, y, from.z) + side * sin(k * 7.0 + ph) * 1.1 - out * sin(k * 3.0) * 0.6
		var c := CylinderMesh.new()
		var r := lerpf(0.42, 0.16, k)
		c.top_radius = r * 0.9
		c.bottom_radius = r
		c.height = prev.distance_to(p) + 0.2
		c.radial_segments = 7
		c.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = c
		mi.material_override = flesh_mat
		add_child(mi)
		var d := (p - prev).normalized()
		var b := Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.95 else Vector3.FORWARD) * Basis(Vector3.RIGHT, -PI * 0.5)
		mi.global_transform = Transform3D(b, (prev + p) * 0.5)
		prev = p


# ── 북쪽 고딕 아치 ──────────────────────────────────────

func _arches() -> void:
	for spec in [[-17.0, -44.0, 8.0, 30.0], [0.0, -54.0, 12.0, 40.0], [17.0, -46.0, 8.0, 32.0], [-34.0, -34.0, 6.0, 22.0], [34.0, -36.0, 6.0, 24.0]]:
		var x: float = spec[0]
		var z: float = spec[1]
		var w: float = spec[2]
		var h: float = spec[3]
		var pw := w * 0.16
		var bottom := -40.0
		for s in [-1.0, 1.0]:
			var ph := h - bottom
			_rock(Vector3(pw, ph, pw * 1.2), Vector3(x + s * w * 0.5, bottom + ph * 0.5, z))
			# 뾰족 아치: 기울인 두 판이 위에서 만난다
			var arm := w * 0.62
			var mi := _rock(Vector3(pw * 0.9, arm, pw), Vector3(x + s * w * 0.25, h + arm * 0.38, z), Vector3(0, 0, -s * 0.62))
			mi.name = "ArchArm"
		# 꼭대기 첨탑
		_spike(Vector3(x, h + w * 0.55, z), Vector3.UP, w * 0.7, pw * 0.5)
		# 아치 사이 가로 보
		_rock(Vector3(w, pw * 0.6, pw * 0.8), Vector3(x, h * 0.55, z))


# ── 거대 가시 ───────────────────────────────────────────

func _thorns(rng: RandomNumberGenerator) -> void:
	for k in 16:
		var a := TAU * k / 16.0 + rng.randf_range(-0.15, 0.15)
		var r := rng.randf_range(19.0, 30.0)
		var base := Vector3(cos(a) * r, rng.randf_range(-26.0, -12.0), sin(a) * r)
		var south := clampf(base.z / r, 0.0, 1.0)
		# 안쪽 위로 비스듬히. 남쪽 가시는 짧게.
		var inward := -Vector3(cos(a), 0, sin(a))
		var dir := (inward * rng.randf_range(0.25, 0.6) + Vector3.UP + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))).normalized()
		var length := lerpf(rng.randf_range(18.0, 30.0), rng.randf_range(6.0, 10.0), south)
		_spike(base, dir, length, rng.randf_range(0.9, 2.2))
		# 곁가시
		if rng.randf() < 0.6:
			var b2 := base + dir * length * rng.randf_range(0.3, 0.5)
			var d2 := (dir + Vector3(rng.randf_range(-1, 1), 0.2, rng.randf_range(-1, 1)) * 0.8).normalized()
			_spike(b2, d2, length * 0.35, 0.45)


# ── 부서진 거대 후광 (북쪽 하늘) ────────────────────────

func _broken_halo() -> void:
	_halo = Node3D.new()
	add_child(_halo)
	_halo.position = Vector3(0, 18.0, -52.0)
	_halo.rotation = Vector3(deg_to_rad(68.0), 0, deg_to_rad(8.0))
	var pieces := 22
	for i in pieces:
		if i == 5 or i == 6 or i == 15:
			continue                 # 부서져 빠진 조각
		var a0 := TAU * i / pieces
		var seg := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(4.1, 1.1, 1.6)
		seg.mesh = b
		seg.material_override = halo_mat
		_halo.add_child(seg)
		var r := 14.4 + (randf_range(-0.4, 0.4) if i % 4 == 0 else 0.0)
		seg.position = Vector3(cos(a0) * r, randf_range(-0.2, 0.2), sin(a0) * r)
		seg.rotation = Vector3(randf_range(-0.05, 0.05), -a0 + PI * 0.5, randf_range(-0.06, 0.06))
		# 바깥쪽 칼날 장식
		if i % 2 == 0:
			var fin := MeshInstance3D.new()
			var fb := BoxMesh.new()
			fb.size = Vector3(0.5, 0.5, 3.4)
			fin.mesh = fb
			fin.material_override = halo_mat
			_halo.add_child(fin)
			fin.position = Vector3(cos(a0) * (r + 2.2), 0, sin(a0) * (r + 2.2))
			fin.rotation = Vector3(0, -a0, 0)
	# 후광 뒤의 희미한 빛
	var l := OmniLight3D.new()
	l.light_color = ABYSS
	l.light_energy = 1.4
	l.omni_range = 30.0
	l.shadow_enabled = false
	add_child(l)
	l.position = Vector3(0, 14.0, -46.0)


# ── 떠다니는 바위 ───────────────────────────────────────

func _floating_rocks(rng: RandomNumberGenerator) -> void:
	for k in 34:
		var a := rng.randf() * TAU
		var r := rng.randf_range(17.5, 30.0)
		var p := Vector3(cos(a) * r, rng.randf_range(-9.0, -1.5), sin(a) * r)
		if p.z > 8.0:
			p.y -= 5.0
		var s := rng.randf_range(0.5, 2.2)
		var mi := _rock(Vector3(s, s * rng.randf_range(0.5, 1.2), s * rng.randf_range(0.6, 1.3)), p,
			Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU), rng.randf_range(0.5, 1.0))
		_floaters.append([mi, p, rng.randf() * TAU, rng.randf_range(0.2, 0.7), Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.3, 0.3), 0)])


# ── 사슬과 영혼 우리 ────────────────────────────────────

func _chains() -> void:
	for spec in [[-15.5, -12.0, 9.0], [15.5, -12.0, 7.5], [-17.0, 6.0, 5.0], [17.0, 7.0, 6.0], [0.0, -19.5, 12.0]]:
		var pivot := Node3D.new()
		add_child(pivot)
		pivot.position = Vector3(spec[0], 36.0, spec[1])
		var bottom: float = spec[2]
		var length := 36.0 - bottom
		var links := int(length / 0.55)
		for i in links:
			var lk := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(0.12, 0.6, 0.32) if i % 2 == 0 else Vector3(0.32, 0.6, 0.12)
			lk.mesh = b
			lk.material_override = iron_mat
			pivot.add_child(lk)
			lk.position = Vector3(0, -i * 0.55, 0)
		var cage := _cage()
		pivot.add_child(cage)
		cage.position = Vector3(0, -length - 1.4, 0)
		_swing.append([pivot, randf() * TAU, randf_range(0.015, 0.03)])


func _cage() -> Node3D:
	var c := Node3D.new()
	var h := 2.6
	var r := 0.95
	for i in 8:
		var a := TAU * i / 8.0
		var bar := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.08, h, 0.08)
		bar.mesh = b
		bar.material_override = iron_mat
		c.add_child(bar)
		bar.position = Vector3(cos(a) * r, 0, sin(a) * r)
	for y in [-h * 0.5, h * 0.5, 0.0]:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r - 0.06
		tm.outer_radius = r + 0.06
		ring.mesh = tm
		ring.material_override = iron_mat
		c.add_child(ring)
		ring.position = Vector3(0, y, 0)
	var top := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.1
	cm.bottom_radius = r + 0.1
	cm.height = 0.8
	top.mesh = cm
	top.material_override = iron_mat
	c.add_child(top)
	top.position = Vector3(0, h * 0.5 + 0.4, 0)
	# 우리 안의 혼불 (생체 조직에 갇힌 붉은 빛)
	var soul := Pal.flat_mesh(SphereMesh.new(), Color(1.0, 0.25, 0.3), 3.0)
	soul.scale = Vector3.ONE * 0.55
	c.add_child(soul)
	_souls.append([soul, randf() * TAU])
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.2, 0.25)
	l.light_energy = 2.2
	l.omni_range = 7.0
	c.add_child(l)
	return c


# ── 성유물 등불 (전장 둘레를 떠돈다) ────────────────────

func _lanterns_ring() -> void:
	for k in 8:
		var a := TAU * k / 8.0 + 0.3
		var r := 17.5
		var n := Node3D.new()
		add_child(n)
		var base := Vector3(cos(a) * r, 1.6, sin(a) * r)
		n.position = base
		# 가는 철 틀 + 붉은 심지
		for s in [-1.0, 1.0]:
			var f := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(0.06, 0.9, 0.06)
			f.mesh = b
			f.material_override = iron_mat
			n.add_child(f)
			f.position = Vector3(s * 0.22, 0, 0)
		var capm := CylinderMesh.new()
		capm.top_radius = 0.0
		capm.bottom_radius = 0.34
		capm.height = 0.42
		var cap := MeshInstance3D.new()
		cap.mesh = capm
		cap.material_override = iron_mat
		n.add_child(cap)
		cap.position = Vector3(0, 0.62, 0)
		var core := Pal.flat_mesh(SphereMesh.new(), Color(1.0, 0.3, 0.2), 4.0)
		core.scale = Vector3(0.24, 0.42, 0.24)
		n.add_child(core)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.16, 0.14)
		l.light_energy = 2.4
		l.omni_range = 9.0
		l.omni_attenuation = 1.3
		n.add_child(l)
		_lanterns.append([n, base, randf() * TAU, l])


# ── 기둥 위 화로 (abyss_stage 가 기둥이 솟으면 부른다) ───

func brazier(parent: Node3D) -> Node3D:
	var n := Node3D.new()
	parent.add_child(n)
	n.position = Vector3(0, 0.02, 0)
	var bowl := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.62
	cm.bottom_radius = 0.32
	cm.height = 0.45
	cm.radial_segments = 8
	bowl.mesh = cm
	bowl.material_override = iron_mat
	n.add_child(bowl)
	bowl.position = Vector3(0, 0.25, 0)
	for k in 4:
		var a := TAU * k / 4.0 + PI * 0.25
		var leg := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(0.08, 0.5, 0.08)
		leg.mesh = lb
		leg.material_override = iron_mat
		n.add_child(leg)
		leg.position = Vector3(cos(a) * 0.4, 0.15, sin(a) * 0.4)
		leg.rotation = Vector3(sin(a) * 0.3, 0, -cos(a) * 0.3)
	var ember := Pal.flat_mesh(SphereMesh.new(), Color(0.85, 0.16, 0.06), 1.0)
	ember.scale = Vector3(0.6, 0.12, 0.6)
	n.add_child(ember)
	ember.position = Vector3(0, 0.45, 0)
	var fl := Node3D.new()
	n.add_child(fl)
	fl.position = Vector3(0, 0.55, 0)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.3, 0.12)
	l.light_energy = 2.4
	l.omni_range = 8.5
	l.shadow_enabled = true
	n.add_child(l)
	l.position = Vector3(0, 1.2, 0)
	stage.call("add_brazier_light", l, 2.4)
	_flames.append([fl, 0.0, 1.0])
	return n


## 바닥 가장자리 장식 (판과 함께 움직인다): 녹은 촛대 무리 · 뼈 · 굵은 케이블 잔해
func floor_decor(parent: Node3D, kind: int, out: Vector3) -> Node3D:
	var n := Node3D.new()
	parent.add_child(n)
	var side := Vector3(-out.z, 0, out.x)
	match kind:
		0:
			# 녹아내린 초 무리: 가장자리 쪽 모서리
			n.position = out * 0.62 + side * randf_range(-0.5, 0.5)
			for i in randi_range(3, 6):
				var c := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				var r := randf_range(0.05, 0.09)
				cm.top_radius = r
				cm.bottom_radius = r * 1.3
				cm.height = randf_range(0.15, 0.5)
				cm.radial_segments = 6
				c.mesh = cm
				c.material_override = bone_mat
				n.add_child(c)
				var off := Vector3(randf_range(-0.3, 0.3), cm.height * 0.5, randf_range(-0.3, 0.3))
				c.position = off
				var fl := Pal.flat_mesh(SphereMesh.new(), Color(1.0, 0.55, 0.3), 3.0)
				fl.scale = Vector3(0.06, 0.12, 0.06)
				n.add_child(fl)
				fl.position = off + Vector3(0, cm.height * 0.5 + 0.06, 0)
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.45, 0.25)
			l.light_energy = 0.9
			l.omni_range = 3.2
			n.add_child(l)
			l.position = Vector3(0, 0.6, 0)
		1:
			# 흩어진 뼈와 갈비
			n.position = out * 0.4 + side * randf_range(-0.4, 0.4)
			for i in randi_range(2, 4):
				var b := MeshInstance3D.new()
				b.mesh = Build.bevel_mesh(Vector3(0.07, 0.07, randf_range(0.35, 0.7)), 0.02)
				b.material_override = bone_mat
				n.add_child(b)
				b.position = Vector3(randf_range(-0.4, 0.4), 0.04, randf_range(-0.4, 0.4))
				b.rotation = Vector3(0, randf() * TAU, randf_range(-0.2, 0.2))
			var skull := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.13
			sm.height = 0.24
			skull.mesh = sm
			skull.material_override = bone_mat
			n.add_child(skull)
			skull.position = Vector3(randf_range(-0.2, 0.2), 0.1, randf_range(-0.2, 0.2))
		2:
			# 굵은 케이블이 가장자리 너머로 늘어진다
			n.position = out * 0.55
			var segs := 6
			var prev := Vector3(-out.x * 0.6, 0.06, -out.z * 0.6) + side * randf_range(-0.4, 0.4)
			for i in segs:
				var k := float(i + 1) / segs
				var p := prev.lerp(out * 0.9 + Vector3(0, -k * k * 2.4, 0), 1.0 / (segs - i))
				var c := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.07
				cm.bottom_radius = 0.07
				cm.height = prev.distance_to(p) + 0.05
				cm.radial_segments = 6
				c.mesh = cm
				c.material_override = flesh_mat if i % 2 == 0 else iron_mat
				n.add_child(c)
				var d := (p - prev).normalized()
				var bas := Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.95 else Vector3.FORWARD) * Basis(Vector3.RIGHT, -PI * 0.5)
				c.transform = Transform3D(bas, (prev + p) * 0.5)
				prev = p
	return n


# ── 매 프레임 ───────────────────────────────────────────

func _process(dt: float) -> void:
	t += dt
	for f in _floaters:
		var mi := f[0] as Node3D
		var base: Vector3 = f[1]
		mi.position = base + Vector3(0, sin(t * 0.5 + float(f[2])) * float(f[3]), 0)
		var sp: Vector3 = f[4]
		mi.rotation += sp * dt
	for s in _swing:
		var pv := s[0] as Node3D
		var ph: float = s[1]
		var amp: float = s[2]
		pv.rotation = Vector3(sin(t * 0.6 + ph) * amp, 0, cos(t * 0.45 + ph) * amp)
	for l in _lanterns:
		var n := l[0] as Node3D
		var base2: Vector3 = l[1]
		var ph2: float = l[2]
		n.position = base2 + Vector3(0, sin(t * 0.9 + ph2) * 0.35, 0)
		n.rotation.y = sin(t * 0.4 + ph2) * 0.4
		(l[3] as OmniLight3D).light_energy = 2.4 * (0.85 + 0.15 * sin(t * 7.0 + ph2 * 3.0))
	for s in _souls:
		var sm := s[0] as Node3D
		sm.scale = Vector3.ONE * (0.5 + 0.08 * sin(t * 3.0 + float(s[1])))
	if is_instance_valid(_halo):
		_halo.rotate_object_local(Vector3.UP, dt * 0.05)
	# 화로 불꽃: 가산 혼합 연기 구체를 위로 흘린다
	var i := _flames.size() - 1
	while i >= 0:
		var f2: Array = _flames[i]
		if not is_instance_valid(f2[0]):
			_flames.remove_at(i)
			i -= 1
			continue
		var fl := f2[0] as Node3D
		f2[1] = float(f2[1]) - dt
		if float(f2[1]) <= 0.0 and fl.is_visible_in_tree():
			f2[1] = 0.05
			var p := fl.global_position + Vector3(randf_range(-0.25, 0.25), 0, randf_range(-0.25, 0.25))
			stage.call("dust", p, randf_range(0.35, 0.6), Color(0.9, randf_range(0.12, 0.25), 0.06, 0.55), true, Vector3(0, randf_range(1.4, 2.2), 0), randf_range(0.3, 0.45))
			if randf() < 0.25:
				stage.call("dust", p + Vector3(0, 0.6, 0), 0.9, Color(0.12, 0.08, 0.09, 0.3), false, Vector3(0, 1.5, 0), 1.2)
		i -= 1
