class_name Distortion
extends RefCounted
## 공간 왜곡 연출 전용 (판정과 무관, 모두 스스로 수명을 끝낸다).
## 불투명 패스까지 그려진 화면(hint_screen_texture)을 어긋나게 다시 찍어 공기가 일그러지는 듯 보이게 한다.
## - burst(): 폭발·강타 지점에서 퍼지는 굴절 충격파 고리 + 안쪽 아지랑이. 카메라를 향한 판 한 장.
## - trail_material(): 광선검 잔상 리본과 같은 메시에 겹쳐 그리는 굴절 띠. 칼이 지나간 자리의 공기가 휜다.
## 화면 기준 픽셀 세기는 높이 800px 기준이며 해상도에 맞춰 늘어난다.
## 그리는 순서: 외곽선(-128) 바로 다음(-127). 다른 반투명 이펙트(불꽃·링·잔상)는 왜곡 위에 덮여 흐트러지지 않는다.
## 트윈(게임 시간)으로 진행하므로 히트스탑 동안 충격파가 얼어붙는다.

const PRIORITY := Material.RENDER_PRIORITY_MIN + 1

static var _burst_mat: ShaderMaterial
static var _quad: QuadMesh
static var _trail_shader: Shader

const NOISE := """
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
"""

const BURST_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled, blend_mix;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
instance uniform float progress = 0.0;   // 0 → 1
instance uniform float strength = 1.0;   // 굴절 세기 배율
instance uniform float haze = 0.0;       // 안쪽 아지랑이 세기 (폭발 열기)
instance uniform float seed = 0.0;
%s
void vertex() {
%s
}
void fragment() {
	vec2 d = UV - 0.5;
	float r = length(d) * 2.0;           // 0 중심 · 1 판 가장자리
	vec2 dir = r > 0.0001 ? d / (r * 0.5) : vec2(0.0);
	float t = clamp(progress, 0.0, 1.0);
	float fade = 1.0 - smoothstep(0.55, 1.0, t);
	// 충격파 앞머리: 빠르게 튀어나갔다가 가장자리에서 느려진다
	float front = mix(0.06, 0.92, 1.0 - pow(1.0 - t, 3.0));
	float w = mix(0.1, 0.22, t);
	float x = (r - front) / w;
	// 볼록렌즈 고리: 앞머리 바깥은 밀어내고 안쪽은 당긴다 → 투명한 유리 띠처럼 보인다
	float prof = x * exp(-x * x * 1.6) * 1.9;
	vec2 ofs = -dir * prof * strength * fade;
	// 안쪽 아지랑이: 위로 흘러가는 잔물결
	vec2 q = UV * 7.0 + vec2(seed * 13.0, t * 5.0 + seed * 7.0);
	vec2 wob = vec2(vnoise(q) - 0.5, vnoise(q + 17.3) - 0.5);
	float inner = (1.0 - smoothstep(0.1, max(front, 0.2), r)) * haze * (1.0 - smoothstep(0.2, 1.0, t));
	ofs += wob * inner * strength * 1.6;
	ofs *= 1.0 - smoothstep(0.85, 1.0, r);
	// 판 UV 방향 → 화면 픽셀 방향: dUV = J · d픽셀 이므로 d픽셀 = J⁻¹ · dUV
	mat2 ij = inverse(mat2(dFdx(UV), dFdy(UV)));
	vec2 sp = ij * ofs;
	vec2 px = (length(sp) > 1e-6 ? normalize(sp) : vec2(0.0)) * length(ofs) * 22.0 * (VIEWPORT_SIZE.y / 800.0);
	vec2 suv = SCREEN_UV + px / VIEWPORT_SIZE;
	// 고리 부분에 옅은 색수차
	vec2 sd = ij * dir;
	vec2 cdir = (length(sd) > 1e-6 ? normalize(sd) : vec2(0.0)) * abs(prof) * fade * 2.5 * strength / VIEWPORT_SIZE;
	vec3 c;
	c.r = texture(screen_tex, suv + cdir).r;
	c.g = texture(screen_tex, suv).g;
	c.b = texture(screen_tex, suv - cdir).b;
	// 앞머리에 아주 옅은 광택
	c += vec3(0.9, 0.95, 1.0) * exp(-x * x * 6.0) * 0.06 * fade * strength;
	ALBEDO = c;
	ALPHA = clamp(length(px) * 0.8, 0.0, 1.0);
}
"""

const TRAIL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_mix;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount = 14.0;       // 최대 어긋남 (800px 기준 픽셀)
uniform float inner_lo = 0.08;     // 굴절 띠 안쪽 경계: 광선검 리본보다 조금 넓게
uniform float inner_hi = 0.72;
uniform float tip_edge = 0.97;
%s
void fragment() {
	float age = clamp(UV.x, 0.0, 1.0);
	float v = UV.y;
	float w = COLOR.a;
	float inner = mix(inner_lo, inner_hi, pow(age, 0.65));
	float band = smoothstep(inner, inner + 0.18, v) * (1.0 - smoothstep(tip_edge - 0.12, tip_edge, v));
	// 칼이 지나간 방향(나이 기울기)으로 화면을 끌고 간다. 띠 폭을 따라 한 번 물결쳐 굴절 경계가 선다.
	vec2 g = vec2(dFdx(age), dFdy(age));
	vec2 dir = length(g) > 1e-6 ? normalize(g) : vec2(0.0);
	float wave = sin(clamp((v - inner) / max(tip_edge - inner, 0.05), 0.0, 1.0) * 3.14159);
	float grain = 0.7 + 0.6 * vnoise(vec2(v * 18.0, age * 5.0));
	float k = band * wave * grain * pow(1.0 - age, 1.2) * w;
	vec2 px = dir * k * amount * (VIEWPORT_SIZE.y / 800.0);
	vec2 suv = SCREEN_UV + px / VIEWPORT_SIZE;
	vec2 cdir = dir * k * 1.5 / VIEWPORT_SIZE;
	vec3 c;
	c.r = texture(screen_tex, suv + cdir).r;
	c.g = texture(screen_tex, suv).g;
	c.b = texture(screen_tex, suv - cdir).b;
	ALBEDO = c;
	ALPHA = clamp(length(px) * 0.8, 0.0, 1.0);
}
"""


static func _setup() -> void:
	if _burst_mat:
		return
	var bs := Shader.new()
	bs.code = BURST_SHADER % [NOISE, FX.BILLBOARD]
	_burst_mat = ShaderMaterial.new()
	_burst_mat.shader = bs
	_burst_mat.render_priority = PRIORITY
	_quad = QuadMesh.new()
	_trail_shader = Shader.new()
	_trail_shader.code = TRAIL_SHADER % NOISE


## 굴절 충격파. radius = 고리가 다 퍼졌을 때 반경(m), strength = 휘는 세기, haze = 안쪽 아지랑이(0~1+)
static func burst(pos: Vector3, radius: float, dur := 0.4, strength := 1.0, haze := 0.0) -> void:
	FluidSmoke.blast(pos, radius, strength, haze)   # 유체 연기가 있는 씬이면 충격 바람으로 연기를 민다
	if FX.root == null:
		return
	_setup()
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	mi.material_override = _burst_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * radius * 2.0
	# 흐르는 씬에서는 폭발 본체와 같은 곡선으로 함께 흐른다 (WorldFlow, 아니면 FX.root)
	WorldFlow.holder(WorldFlow.AIR).add_child(mi)
	mi.global_position = pos
	mi.set_instance_shader_parameter("strength", strength)
	mi.set_instance_shader_parameter("haze", haze)
	mi.set_instance_shader_parameter("seed", randf())
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): mi.set_instance_shader_parameter("progress", v), 0.0, 1.0, dur)
	tw.tween_callback(mi.queue_free)


## 광선검 리본 위에 겹쳐 그리는 굴절 머티리얼 (SaberTrail 이 같은 메시를 공유해 쓴다)
static func trail_material(amount := 14.0) -> ShaderMaterial:
	_setup()
	var m := ShaderMaterial.new()
	m.shader = _trail_shader
	m.render_priority = PRIORITY
	m.set_shader_parameter("amount", amount)
	return m
