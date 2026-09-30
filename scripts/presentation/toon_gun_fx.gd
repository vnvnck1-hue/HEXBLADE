class_name ToonGunFX
extends Node3D
## 연출 전용: 손그림 플립북(Adobe Animate 시트) 느낌의 총기 이펙트. 게임 판정과 무관하다.
## 시트 텍스처 대신 모양을 셰이더로 그리고, 시간을 프레임 단위로 끊어(계단식 phase) 손으로 그린 장면처럼 넘긴다.
##
## 모양 (레퍼런스 시트 대응)
##  STAR    4갈래 섬광 (흐린 가장자리)          — 착탄 첫 순간
##  ARROW   톱니 달린 창 모양 불꽃              — 총구 화염 (넓은 톱니가 총구 쪽, 가는 끝이 전방)
##  SHARD   작은 톱니 파편                      — 총구 옆·착탄에서 튀는 조각
##  RING    울퉁불퉁한 구름 테두리 고리          — 착탄 충격파
##  PUFF    구름 연기: 부풀었다가 안쪽부터 먹혀 초승달 → 소멸
##  CROWN   왕관 불꽃: 가시 → 둥근 덩어리 → 아래에서 파여 아치 → 갈고리로 흩어짐
##  SPINDLE 예광 방추: 궤적 위 무작위 자리에 번쩍이는 짧은 탄 줄기
##  LINE    탄이 지나간 자리의 옅은 연기 선

enum { STAR, ARROW, SHARD, RING, PUFF, CROWN, SPINDLE, LINE }

const ORANGE := Color(1.0, 0.5, 0.1)
const AMBER := Color(1.0, 0.68, 0.2)
const HOT := Color(1.0, 0.93, 0.62)
const FLAME := Color(1.0, 0.42, 0.07)
const FLAME_CORE := Color(1.0, 0.76, 0.24)
const WHITE := Color(1.0, 0.98, 0.9)
const SMOKE_LIT := Color("d6b28b")
const SMOKE_SHADE := Color("94704f")
const TRAIL := Color(0.78, 0.72, 0.64, 0.12)

## 모양별: 정렬 우선순위, 카메라 쪽으로 당기는 거리(벽에 파묻히지 않게), 축 정렬 여부
const PRIORITY := [5, 3, 3, 1, 0, 2, 2, 0]
const PULL := [0.9, 0.2, 0.3, 0.6, 0.5, 0.7, 0.1, 0.0]
const AXIS := [false, true, true, false, false, false, true, true]

## 트레이서: 최대 연기 선 길이, 머리 방추 길이
const TRAIL_MAX := 9.0

static var inst: ToonGunFX

var _quad: QuadMesh
var _mats: Array[ShaderMaterial] = []
var _live: Array = []   # {mi, t, dur, vel, drag, grav, size, grow}


const COMMON := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;
instance uniform float phase = 0.0;
instance uniform float seed = 0.0;
instance uniform float frames = 0.0;
instance uniform float energy = 1.0;
instance uniform float spin = 0.0;
instance uniform vec2 size = vec2(1.0);
instance uniform vec2 anchor = vec2(0.0);
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform vec4 tint2 : source_color = vec4(1.0);
uniform int axis_mode = 0;
uniform float pull = 0.5;
varying vec2 P;

void vertex() {
	vec2 q = VERTEX.xy;
	P = q * 2.0;
	vec3 c = MODEL_MATRIX[3].xyz;
	vec3 tc = normalize(INV_VIEW_MATRIX[3].xyz - c);
	vec3 r;
	vec3 u;
	if (axis_mode == 0) {
		// 화면을 향한 판. spin 만큼 화면 안에서 돈다
		vec3 r0 = INV_VIEW_MATRIX[0].xyz;
		vec3 u0 = INV_VIEW_MATRIX[1].xyz;
		r = r0 * cos(spin) + u0 * sin(spin);
		u = -r0 * sin(spin) + u0 * cos(spin);
	} else {
		// 축(노드 +Y) 방향으로 길게, 카메라를 향해 옆으로 벌어진 판
		u = normalize(MODEL_MATRIX[1].xyz);
		r = normalize(cross(u, tc));
	}
	vec2 o = (q + anchor) * size;
	vec3 w = c + tc * pull + r * o.x + u * o.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(w, 1.0);
}

float h(float n) { return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453); }
// 계단식 시간: 프레임 수가 있으면 0..1 을 frames 칸으로 끊는다
float ft() {
	if (frames < 1.5) return clamp(phase, 0.0, 1.0);
	return clamp(floor(phase * frames) / (frames - 1.0), 0.0, 1.0);
}
// 같은 그림을 매 프레임 조금씩 흔드는 '보일링' 시드
float fs() { return floor(phase * max(frames, 1.0)); }
float circ(vec2 p, vec2 c, float r) { return length(p - c) - r; }
float ell(vec2 p, vec2 c, vec2 r) { vec2 d = (p - c) / r; return (length(d) - 1.0) * min(r.x, r.y); }
float box(vec2 p, vec2 c, vec2 b) { vec2 d = abs(p - c) - b; return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0); }
float tri_iso(vec2 p, vec2 q) {
	p.x = abs(p.x);
	vec2 a = p - q * clamp(dot(p, q) / dot(q, q), 0.0, 1.0);
	vec2 b = p - q * vec2(clamp(p.x / q.x, 0.0, 1.0), 1.0);
	float s = -sign(q.y);
	vec2 d = min(vec2(dot(a, a), s * (p.x * q.y - p.y * q.x)), vec2(dot(b, b), s * (p.y - q.y)));
	return -sqrt(d.x) * sign(d.y);
}
// 끝이 위를 향한 가시 (tip 에서 아래로 h 만큼 밑변)
float spike_up(vec2 p, vec2 tip, float hw, float hh) { return tri_iso(vec2(p.x - tip.x, tip.y - p.y), vec2(hw, hh)); }
// 끝이 아래를 향한 물방울 꼬리
float spike_dn(vec2 p, vec2 tip, float hw, float hh) { return tri_iso(vec2(p.x - tip.x, p.y - tip.y), vec2(hw, hh)); }
float aa(float d) { return smoothstep(0.018, -0.018, d); }
"""

const FRAG := [
# STAR
"""
void fragment() {
	float t = ft();
	float sc = mix(0.8, 1.0, smoothstep(0.0, 0.5, t)) * mix(1.0, 0.4, smoothstep(0.5, 1.0, t));
	float sharp = mix(9.0, 24.0, t);
	float r = length(P) / sc;
	float a = atan(P.y, P.x);
	float R = 0.17;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float ai = fi * 1.5708 + (h(fi) - 0.5) * 0.4;
		float L = mix(0.55, 1.0, h(fi + 7.0));
		R = max(R, L * pow(max(cos(a - ai), 0.0), sharp));
		float bi = ai + 0.785 + (h(fi + 3.0) - 0.5) * 0.5;
		R = max(R, 0.34 * h(fi + 11.0) * pow(max(cos(a - bi), 0.0), sharp * 1.8));
	}
	float al = smoothstep(R, R * 0.7, r);
	float core = smoothstep(R * 0.55, R * 0.15, r);
	if (al < 0.01) discard;
	ALBEDO = mix(tint.rgb, tint2.rgb, core) * energy;
	ALPHA = al * tint.a;
}
""",
# ARROW
"""
void fragment() {
	float t = ft();
	float L = mix(0.7, 1.0, smoothstep(0.0, 0.5, t));
	float W = mix(1.2, 0.5, smoothstep(0.4, 1.0, t));
	float v = (P.y + 1.0) * 0.5 / L;
	if (v > 1.0 || v < 0.0) discard;
	float up = P.x >= 0.0 ? 1.0 : 0.0;
	float ph = mix(h(2.0) * 0.4 + 0.2, h(1.0) * 0.4, up);
	float taper = 0.17 * pow(1.0 - v, 1.1);
	float zone = 1.0 - smoothstep(0.06, 0.52, v);
	float saw = pow(fract(v * mix(3.0, 3.6, up) + ph), 1.6);
	float w = (taper + zone * mix(0.58, 0.85, up) * saw * mix(0.7, 1.0, h(up + 4.0))) * smoothstep(0.0, 0.1, v) * W;
	float d = abs(P.x) - w;
	// 마지막 칸: 총구 쪽부터 조각나며 사라진다
	float cut = smoothstep(0.5, 1.0, t) * 0.45;
	d = max(d, cut - v + 0.04 * sin(P.x * 38.0 + seed * 9.0));
	float al = aa(d);
	if (al < 0.01) discard;
	float core = step(abs(P.x), w * 0.4) * step(0.06, v);
	ALBEDO = mix(tint.rgb, tint2.rgb, core) * energy;
	ALPHA = al * tint.a;
}
""",
# SHARD
"""
void fragment() {
	float t = ft();
	float v = (P.y + 1.0) * 0.5;
	float side = P.x >= 0.0 ? 1.0 : -1.0;
	float teeth = step(fract(v * 2.0 + h(side + 2.0) * 0.5), 0.55);
	float w = 0.7 * (1.0 - v) * mix(0.55, 1.0, teeth) * mix(1.0, 0.35, step(0.0, side * (h(5.0) - 0.5)));
	w *= mix(1.0, 0.5, t) * smoothstep(0.0, 0.12, v);
	float d = abs(P.x) - w;
	float al = aa(d);
	if (al < 0.01) discard;
	float core = step(abs(P.x), w * 0.35);
	ALBEDO = mix(tint.rgb, tint2.rgb, core) * energy;
	ALPHA = al * tint.a;
}
""",
# RING
"""
void fragment() {
	float t = ft();
	float e = 1.0 - pow(1.0 - t, 2.0);
	float R = mix(0.35, 0.95, e);
	float a = atan(P.y, P.x);
	float b = fs() * 0.7;
	float Ro = R * (1.0 + 0.07 * sin(a * 6.0 + seed * 9.0 + b) + 0.04 * sin(a * 11.0 - seed * 5.0));
	vec2 off = vec2(0.07, -0.06) * R * (1.0 + t);
	float Ri = R * mix(0.84, 0.99, t) * (1.0 + 0.05 * sin(a * 5.0 + seed * 3.0 - b));
	float d = max(length(P) - Ro, -(length(P - off) - Ri));
	float al = aa(d);
	if (al < 0.01) discard;
	ALBEDO = tint.rgb * energy;
	ALPHA = al * tint.a;
}
""",
# PUFF
"""
float body(vec2 p, float g) {
	float b = fs() * 1.3;
	float d = circ(p, vec2(-0.45, -0.12) + (vec2(h(1.0), h(2.0)) - 0.5) * 0.14, 0.40 * g);
	d = min(d, circ(p, vec2(0.0, 0.16) + (vec2(h(3.0), h(4.0)) - 0.5) * 0.14, (0.5 + 0.015 * sin(b)) * g));
	d = min(d, circ(p, vec2(0.46, -0.08) + (vec2(h(5.0), h(6.0)) - 0.5) * 0.14, 0.39 * g));
	d = min(d, circ(p, vec2(-0.16, -0.38) + (vec2(h(7.0), h(8.0)) - 0.5) * 0.1, 0.38 * g));
	d = min(d, circ(p, vec2(0.28, -0.4) + (vec2(h(9.0), h(10.0)) - 0.5) * 0.1, (0.34 + 0.015 * cos(b)) * g));
	return max(d, -(p.y + 0.74 * g));
}
void fragment() {
	float t = ft();
	float g = mix(0.6, 1.0, smoothstep(0.0, 0.3, t)) * mix(1.0, 0.92, t);
	float e = pow(smoothstep(0.22, 1.0, t), 0.85);
	vec2 ec = vec2((h(20.0) - 0.5) * 0.5, -0.85);
	float er = min(circ(P, ec, e * 1.3), circ(P, ec + vec2(0.45 * sign(h(21.0) - 0.5), 0.3), e * 0.75));
	float d = max(body(P, g), -er);
	float al = aa(d);
	if (al < 0.01) discard;
	// 2톤 음영: 빛(왼쪽 위) 반대편 가장자리에 그림자 띠
	float sh = step(0.0, body(P - normalize(vec2(-0.5, 0.85)) * 0.17, g));
	ALBEDO = mix(tint.rgb, tint2.rgb, sh) * energy;
	ALPHA = al * tint.a;
}
""",
# CROWN
"""
void fragment() {
	float t = ft();
	vec2 p = P;
	float d;
	if (t < 0.2) {
		// 가시 왕관: 불꽃 혀가 위로 솟는다
		float g = mix(0.45, 0.78, t / 0.2);
		d = box(p, vec2(0.0, -1.0 + 0.2 * g), vec2(0.5 * g, 0.2 * g));
		d = min(d, spike_up(p, vec2(0.02, -1.0 + 1.3 * g), 0.21 * g, 1.05 * g));
		d = min(d, spike_up(p, vec2(-0.36 * g, -1.0 + 0.9 * g), 0.17 * g, 0.7 * g));
		d = min(d, spike_up(p, vec2(0.4 * g, -1.0 + 0.82 * g), 0.15 * g, 0.62 * g));
		d = max(d, -spike_up(p, vec2(0.0, -1.0 + 0.2 * g), 0.13 * g, 0.22 * g));
	} else {
		float s = (t - 0.2) / 0.8;
		p /= mix(1.0, 0.86, smoothstep(0.6, 1.0, s));
		// 부푼 덩어리 + 아래로 흘러내린 꼬리
		d = circ(p, vec2(-0.36, -0.06 + 0.3 * s), 0.36);
		d = min(d, circ(p, vec2(0.04, 0.12 + 0.36 * s), 0.44));
		d = min(d, circ(p, vec2(0.42, -0.1 + 0.28 * s), 0.34));
		d = min(d, ell(p, vec2(0.0, -0.36), vec2(0.62, 0.5)));
		d = min(d, spike_dn(p, vec2(-0.52, -0.98 + 0.12 * s), 0.17, 0.62));
		d = min(d, spike_dn(p, vec2(0.5, -0.9 + 0.12 * s), 0.15, 0.55));
		// 아래에서 파고드는 아치 → 위에서도 갈라져 갈고리 두 개로
		float e = smoothstep(0.02, 0.72, s);
		float e2 = smoothstep(0.55, 1.0, s);
		float er = ell(p, vec2(0.03, -1.05), vec2(0.58 * e + 0.001, 1.22 * e + 0.001));
		er = min(er, circ(p, vec2(0.08, 1.08), 0.95 * e2));
		d = max(d, -er);
	}
	float al = aa(d);
	if (al < 0.01) discard;
	float inner = step(d, -0.09);
	ALBEDO = mix(tint.rgb, tint2.rgb, inner) * energy * mix(1.0, 0.65, t);
	ALPHA = al * tint.a;
}
""",
# SPINDLE
"""
void fragment() {
	float v = P.y;
	float u = v < 0.3 ? (v - 0.3) / 1.3 : (v - 0.3) / 0.7;
	float prof = pow(max(1.0 - u * u, 0.0), 1.2);
	float fade = 1.0 - phase;
	float w = 0.26 * prof * mix(1.0, 0.35, phase) + 0.001;
	float dx = abs(P.x) / w;
	float bodyv = smoothstep(1.0, 0.72, dx);
	float core = smoothstep(0.6, 0.2, dx);
	float glow = exp(-abs(P.x) * 4.5) * prof * 0.4;
	float al = max(bodyv, glow) * fade;
	if (al < 0.01) discard;
	ALBEDO = mix(tint.rgb, tint2.rgb, core) * energy * mix(0.55, 1.0, bodyv);
	ALPHA = al * tint.a;
}
""",
# LINE
"""
void fragment() {
	float al = tint.a * (1.0 - phase) * smoothstep(1.0, 0.0, abs(P.x)) * smoothstep(-1.0, 0.3, P.y) * smoothstep(1.0, 0.85, P.y);
	if (al < 0.005) discard;
	ALBEDO = tint.rgb * energy;
	ALPHA = al;
}
""",
]


func _ready() -> void:
	inst = self
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE
	for i in FRAG.size():
		var sh := Shader.new()
		sh.code = COMMON + FRAG[i]
		var m := ShaderMaterial.new()
		m.shader = sh
		m.render_priority = PRIORITY[i]
		m.set_shader_parameter("axis_mode", 1 if AXIS[i] else 0)
		m.set_shader_parameter("pull", PULL[i])
		_mats.append(m)


## 모양 하나를 띄운다. axis: 축 정렬 모양의 길이 방향. o: vel, drag, grav, grow, delay, anchor, spin, seed, tint2, manual
func spawn(shape: int, pos: Vector3, dur: float, frames: float, size: Vector2, tint: Color, energy: float, axis := Vector3.ZERO, o := {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	mi.material_override = _mats[shape]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	add_child(mi)
	mi.global_transform = Transform3D(axis_basis(axis) if axis != Vector3.ZERO else Basis.IDENTITY, pos)
	mi.set_instance_shader_parameter("seed", o.get("seed", randf() * 100.0))
	mi.set_instance_shader_parameter("frames", frames)
	mi.set_instance_shader_parameter("energy", energy)
	mi.set_instance_shader_parameter("spin", o.get("spin", 0.0))
	mi.set_instance_shader_parameter("size", size)
	mi.set_instance_shader_parameter("anchor", o.get("anchor", Vector2.ZERO))
	mi.set_instance_shader_parameter("tint", tint)
	mi.set_instance_shader_parameter("tint2", o.get("tint2", tint))
	mi.set_instance_shader_parameter("phase", 0.0)
	var delay: float = o.get("delay", 0.0)
	mi.visible = delay <= 0.0
	if not o.get("manual", false):
		_live.append({"mi": mi, "t": -delay / dur, "dur": dur, "vel": o.get("vel", Vector3.ZERO),
			"drag": o.get("drag", 0.0), "grav": o.get("grav", 0.0), "size": size, "grow": o.get("grow", 0.0)})
	return mi


## 수동으로 붙들고 있던 모양(연기 선 등)을 dur 동안 옅어지게 한 뒤 지운다
func fade_out(mi: MeshInstance3D, dur: float) -> void:
	if not is_instance_valid(mi):
		return
	_live.append({"mi": mi, "t": 0.0, "dur": dur, "vel": Vector3.ZERO, "drag": 0.0, "grav": 0.0, "size": Vector2.ZERO, "grow": 0.0})


static func axis_basis(axis: Vector3) -> Basis:
	var y := axis.normalized()
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	return Basis(x, y, x.cross(y))


func _process(dt: float) -> void:
	var i := _live.size() - 1
	while i >= 0:
		var s: Dictionary = _live[i]
		var mi: MeshInstance3D = s.mi
		if not is_instance_valid(mi):
			_live.remove_at(i)
			i -= 1
			continue
		s.t += dt / float(s.dur)
		if s.t >= 1.0:
			mi.queue_free()
			_live.remove_at(i)
			i -= 1
			continue
		if s.t >= 0.0:
			mi.visible = true
			mi.set_instance_shader_parameter("phase", s.t)
			var v: Vector3 = s.vel
			if v != Vector3.ZERO or s.grav != 0.0:
				v.y -= float(s.grav) * dt
				mi.global_position += v * dt
				s.vel = v * exp(-float(s.drag) * dt)
			if s.grow != 0.0:
				s.size = (s.size as Vector2) * (1.0 + float(s.grow) * dt)
				mi.set_instance_shader_parameter("size", s.size)
		i -= 1


# ── 조합 연출 ───────────────────────────────────────────

## 총구 화염: 톱니 창 불꽃(앞) + 옆으로 벌어지는 작은 창 둘 + 큰 섬광 + 튀는 파편
static func muzzle(pos: Vector3, fwd: Vector3, k := 1.0) -> void:
	if inst == null:
		return
	var g := inst
	var f := Vector3(fwd.x, 0, fwd.z).normalized()
	var side := f.cross(Vector3.UP).normalized()
	var ln := randf_range(0.85, 1.2)
	# 주 불꽃: 길고 굵게 앞으로 뻗는다
	g.spawn(ARROW, pos - f * 0.1 * k, 0.085, 3, Vector2(1.0 * k * randf_range(0.85, 1.15), 2.6 * k * ln),
		ORANGE, 2.8, f.rotated(Vector3.UP, randf_range(-0.05, 0.05)), {"anchor": Vector2(0, 0.5), "tint2": HOT})
	# 옆 불꽃: 총구 앞에서 비스듬히 벌어지는 짧은 창 (십자형 총구 화염)
	for sgn: float in [-1.0, 1.0]:
		var sd := f.rotated(Vector3.UP, sgn * randf_range(1.0, 1.35))
		g.spawn(ARROW, pos + f * 0.12 * k, 0.065, 3, Vector2(0.5, 0.95) * k * randf_range(0.8, 1.15),
			ORANGE, 2.5, sd, {"anchor": Vector2(0, 0.5), "tint2": HOT})
	# 파편: 총구 양옆에서 뒤쪽·바깥으로 튄다 (레퍼런스의 두 조각)
	for sgn: float in [-1.0, 1.0]:
		if randf() < 0.2:
			continue
		var a := (side * sgn + f * randf_range(-0.5, 0.35) + Vector3(0, randf_range(0.0, 0.3), 0)).normalized()
		g.spawn(SHARD, pos + side * sgn * 0.12 * k, randf_range(0.08, 0.11), 3, Vector2(0.34, 0.7) * k * randf_range(0.8, 1.2),
			AMBER, 2.2, a, {"anchor": Vector2(0, 0.5), "tint2": HOT, "vel": a * randf_range(4.0, 6.0) * k, "drag": 10.0})
	# 섬광: 총구 앞 큰 별 + 가운데 흰 심
	g.spawn(STAR, pos + f * 0.15 * k, 0.06, 3, Vector2.ONE * 1.3 * k * randf_range(0.9, 1.1), HOT, 3.4, Vector3.ZERO,
		{"spin": randf() * TAU, "tint2": WHITE})
	g.spawn(STAR, pos + f * 0.05 * k, 0.045, 2, Vector2.ONE * 0.7 * k, WHITE, 4.5, Vector3.ZERO,
		{"spin": randf() * TAU, "tint2": Color.WHITE})


## 착탄: 섬광 → 충격 고리 → 왕관 불꽃 + 구름 연기 + 튀는 파편.
## face: 맞은 면에서 쏜 쪽으로 향하는 방향. smoke: 연기 색 (적 몸체에 맞으면 몸체색이 섞인다)
static func impact(pos: Vector3, face: Vector3, k := 1.0, smoke := SMOKE_LIT) -> void:
	if inst == null:
		return
	var g := inst
	var fc := Vector3(face.x, 0, face.z)
	fc = fc.normalized() if fc.length() > 0.01 else Vector3.BACK
	var side := fc.cross(Vector3.UP).normalized()
	var flip := -1.0 if randf() < 0.5 else 1.0
	var p := pos + fc * 0.08
	g.spawn(STAR, p, 0.07, 3, Vector2.ONE * 1.05 * k * randf_range(0.9, 1.1), HOT, 3.0, Vector3.ZERO,
		{"spin": randf() * TAU, "tint2": WHITE})
	g.spawn(RING, p, 0.15, 4, Vector2.ONE * 1.3 * k, Color(1.0, 0.72, 0.36, 0.7), 1.3, Vector3.ZERO,
		{"spin": randf() * TAU})
	# 구름 연기: 큰 덩어리 하나는 왕관 한쪽 옆, 작은 덩어리는 반대쪽. 살짝 늦게 피어난다
	var sh := smoke.lerp(SMOKE_SHADE, 0.55)
	sh.a = 1.0
	g.spawn(PUFF, p + side * flip * 0.32 * k + Vector3(0, 0.12, 0) * k, 0.48, 8, Vector2(1.3, 1.2) * k * randf_range(0.9, 1.1),
		smoke, 1.0, Vector3.ZERO, {"tint2": sh, "vel": (fc * 0.8 + Vector3(0, 0.9, 0) + side * flip * 0.6) * k, "drag": 4.0, "delay": 0.02})
	g.spawn(PUFF, p - side * flip * 0.3 * k + Vector3(0, 0.3, 0) * k, 0.4, 7, Vector2(0.8, 0.75) * k * randf_range(0.85, 1.1),
		smoke, 1.0, Vector3.ZERO, {"tint2": sh, "vel": (fc * 0.5 + Vector3(0, 1.1, 0) - side * flip * 0.5) * k, "drag": 4.0, "delay": 0.05})
	# 왕관 불꽃: 착탄점에서 화면 위로 솟는다 (연기 위에 겹쳐 그린다)
	g.spawn(CROWN, p, 0.32, 9, Vector2(0.82 * flip, 1.0) * k * randf_range(0.9, 1.1), FLAME, 1.8, Vector3.ZERO,
		{"anchor": Vector2(0, 0.38), "tint2": FLAME_CORE})
	# 튀는 파편 조각: 대부분 위·쏜 쪽으로
	for i in randi_range(2, 3):
		var a := (fc * randf_range(0.2, 1.0) + side * randf_range(-1.0, 1.0) + Vector3(0, randf_range(0.6, 1.6), 0)).normalized()
		g.spawn(SHARD, p + a * 0.25 * k, randf_range(0.1, 0.16), 3, Vector2(0.2, 0.42) * k * randf_range(0.7, 1.2),
			AMBER, 2.2, a, {"anchor": Vector2(0, 0.5), "tint2": HOT, "vel": a * randf_range(5.0, 8.0) * k, "drag": 9.0})


func _exit_tree() -> void:
	if inst == self:
		inst = null


## 플레이어 탄에 붙이는 예광 연출. 탄 노드의 자식으로 넣으면 탄을 따라 스스로 그린다.
static func tracer() -> Tracer:
	return Tracer.new()


## 예광 연출: 탄 머리의 방추가 매 프레임 길이·옆 위치를 바꿔 깜빡이고,
## 지나온 궤적 위 무작위 자리에 짧은 방추가 번쩍였다 사라져 "빠르게 지나간" 속도감을 만든다.
## 뒤로는 옅은 연기 선이 남는다. 게임 판정과 무관하다.
class Tracer extends Node3D:
	var dir := Vector3.FORWARD
	var origin := Vector3.ZERO
	var last := Vector3.ZERO
	## 1 = 보통, 작을수록 가늘다 (사라지기 직전의 도탄)
	var thin := 1.0
	var head: MeshInstance3D
	var line: MeshInstance3D

	func setup(d: Vector3) -> Tracer:
		dir = Vector3(d.x, 0, d.z).normalized() if Vector2(d.x, d.z).length() > 0.01 else d.normalized()
		return self

	func _ready() -> void:
		origin = global_position
		last = origin
		_make_parts()

	func _make_parts() -> void:
		var g := ToonGunFX.inst
		if g == null:
			return
		if head == null:
			head = g.spawn(ToonGunFX.SPINDLE, global_position, 1.0, 0, Vector2(0.4, 0.2), ToonGunFX.ORANGE, 3.0, dir, {"manual": true, "tint2": ToonGunFX.WHITE})
			head.reparent(self)
		head.transform = Transform3D(ToonGunFX.axis_basis(dir), Vector3.ZERO)
		line = g.spawn(ToonGunFX.LINE, global_position, 1.0, 0, Vector2(0.07, 0.01), ToonGunFX.TRAIL, 1.0, dir, {"manual": true})

	## 도탄: pos 에서 d 방향으로 다시 날아간다. 이전 연기 선은 흩어지게 둔다.
	func redirect(pos: Vector3, d: Vector3) -> void:
		dir = d.normalized()
		origin = pos
		last = pos
		if ToonGunFX.inst:
			ToonGunFX.inst.fade_out(line, 0.12)
		_make_parts()

	func _physics_process(_dt: float) -> void:
		var g := ToonGunFX.inst
		if g == null or head == null:
			return
		var now := global_position
		var dist := (now - origin).length()
		var side := dir.cross(Vector3.UP)
		side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
		# 머리: 길이·옆 위치·밝기가 매번 달라 깜빡이듯 날아간다
		var ln := minf(randf_range(0.75, 1.35), dist + 0.25)
		head.visible = randf() < 0.85
		head.position = -dir * ln * 0.42 + side * randf_range(-0.05, 0.05)
		head.set_instance_shader_parameter("size", Vector2(0.42 * thin, ln))
		head.set_instance_shader_parameter("energy", randf_range(2.4, 3.6))
		# 궤적 잔광: 지나온 자리 무작위 위치에 짧게 번쩍인다
		var n := (1 if randf() < 0.75 else 0) + (1 if randf() < 0.3 else 0)
		for i in n:
			var along := randf_range(-2.2, -0.5)
			if dist + along < 0.5:
				continue
			var p := now + dir * along + side * randf_range(-0.17, 0.17) + Vector3(0, randf_range(-0.07, 0.07), 0)
			g.spawn(ToonGunFX.SPINDLE, p, randf_range(0.035, 0.075), 0, Vector2(randf_range(0.26, 0.4) * thin, randf_range(0.45, 1.1)),
				ToonGunFX.ORANGE if randf() < 0.7 else ToonGunFX.AMBER, randf_range(1.6, 2.6), dir.rotated(Vector3.UP, randf_range(-0.04, 0.04)), {"tint2": ToonGunFX.HOT})
		# 연기 선: 총구(또는 최근 TRAIL_MAX)부터 머리까지
		var tl := minf(dist, ToonGunFX.TRAIL_MAX)
		if is_instance_valid(line):
			line.global_position = now - dir * tl * 0.5
			line.set_instance_shader_parameter("size", Vector2(0.07 * thin, maxf(tl, 0.01)))
		last = now

	func _exit_tree() -> void:
		if ToonGunFX.inst and is_instance_valid(line):
			ToonGunFX.inst.fade_out(line, 0.14)
			line = null
