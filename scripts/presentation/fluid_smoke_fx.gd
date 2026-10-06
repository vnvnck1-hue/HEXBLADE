class_name FluidSmokeFX
extends CompositorEffect
## 유체 연기 그리기 (카메라 컴포지터 효과, 투명 패스 뒤 · MSAA 해소된 색/깊이).
##  1단계 (절반 해상도): 화소마다 장면 깊이를 읽어 광선을 만들고, 바닥 위 연기 높이장(FluidSmoke 화면용 A)에 닿을 때까지 행진 →
##     닿은 곳의 스타일 비율(B)로 명암 · 역광 테두리 · 하이라이트 · 발광 · 외곽선을 칠해 미리 곱한 색 + 투명도, 그 화소의 장면 깊이를 적는다.
##  2단계 (원 해상도): 둘레 4칸을 쌍선형 + 깊이 닮은 정도로 섞어 올려 붙인다 (캐릭터 윤곽에서 연기가 번지지 않게) → 장면 색에 덮는다.
## 품질 FULL 이면 1단계를 원 해상도로 돌리고 2단계는 그대로 덮기만 한다.
## params 는 FluidSmoke._fx_params 가 매 프레임 채운다 (vec4 33개).

const PARAMS := 33

var smoke_a := RID()
var smoke_b := RID()
var smoke_c := RID()            # 부스터 배기 밀도 (r16f)
var params := PackedFloat32Array()
var measure := false

var _rd: RenderingDevice
var _shader := RID()
var _pipe := RID()
var _lin := RID()
var _near := RID()
var _pbuf := RID()
var _hr := RID()
var _hrd := RID()
var _hr_size := Vector2i.ZERO

static var _spirv := {}         # 이름 → RDShaderSPIRV (컴파일 결과는 씬을 다시 불러도 다시 쓴다)


## GLSL 컴퓨트 셰이더를 컴파일해 셰이더 RID 를 만든다 (SPIR-V 는 이름별로 한 번만)
static func compile(rd: RenderingDevice, code: String, name: String) -> RID:
	var spirv: RDShaderSPIRV = _spirv.get(name)
	if spirv == null:
		var src := RDShaderSource.new()
		src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
		src.source_compute = code
		spirv = rd.shader_compile_spirv_from_source(src)
		if spirv.compile_error_compute != "":
			push_error("%s 셰이더: %s" % [name, spirv.compile_error_compute])
			return RID()
		_spirv[name] = spirv
	return rd.shader_create_from_spirv(spirv, name)


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	access_resolved_depth = true
	needs_motion_vectors = false
	enabled = true
	_rd = RenderingServer.get_rendering_device()
	if _rd:
		RenderingServer.call_on_render_thread(_init_rt)


func _init_rt() -> void:
	_shader = compile(_rd, DRAW, "FluidSmokeFX")
	if not _shader.is_valid():
		return
	_pipe = _rd.compute_pipeline_create(_shader)
	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_lin = _rd.sampler_create(ss)
	var sn := RDSamplerState.new()
	_near = _rd.sampler_create(sn)
	var z := PackedByteArray()
	z.resize(PARAMS * 16)
	_pbuf = _rd.storage_buffer_create(z.size(), z)


## 끝낼 때 FluidSmoke 가 부른다
func release() -> void:
	enabled = false
	if _rd:
		RenderingServer.call_on_render_thread(_free_rt)


func _free_rt() -> void:
	for r in [_hr, _hrd, _pbuf, _lin, _near, _pipe, _shader]:
		if r.is_valid():
			_rd.free_rid(r)
	_hr = RID()
	_hrd = RID()
	_pbuf = RID()
	_pipe = RID()
	_shader = RID()


func _ensure_hr(size: Vector2i) -> void:
	if size == _hr_size and _hr.is_valid():
		return
	for r in [_hr, _hrd]:
		if r.is_valid():
			_rd.free_rid(r)
	var tf := RDTextureFormat.new()
	tf.width = size.x
	tf.height = size.y
	tf.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	_hr = _rd.texture_create(tf, RDTextureView.new())
	tf.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	_hrd = _rd.texture_create(tf, RDTextureView.new())
	_hr_size = size


func _u(type: int, binding: int, ids: Array) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = type
	u.binding = binding
	for id in ids:
		u.add_id(id)
	return u


func _render_callback(_type: int, render_data: RenderData) -> void:
	if not enabled or not _pipe.is_valid() or not smoke_a.is_valid() or not smoke_c.is_valid() or params.size() < PARAMS * 4:
		return
	var rsb := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var sd := render_data.get_render_scene_data() as RenderSceneDataRD
	if rsb == null or sd == null:
		return
	var size := rsb.get_internal_size()
	if size.x <= 0 or size.y <= 0:
		return
	var scale := maxi(int(params[14]), 1)
	var hs := Vector2i(ceili(size.x / float(scale)), ceili(size.y / float(scale)))
	_ensure_hr(hs)
	var pb := params.to_byte_array()
	_rd.buffer_update(_pbuf, 0, pb.size(), pb)
	var ubo := sd.get_uniform_buffer()
	if measure:
		_rd.capture_timestamp("fluid_draw_begin")
	for view in rsb.get_view_count():
		var color := rsb.get_color_layer(view)
		var depth := rsb.get_depth_layer(view)
		var us: Array[RDUniform] = [
			_u(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 0, [ubo]),
			_u(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, [_near, depth]),
			_u(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [_lin, smoke_a]),
			_u(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3, [_lin, smoke_b]),
			_u(RenderingDevice.UNIFORM_TYPE_IMAGE, 4, [_hr]),
			_u(RenderingDevice.UNIFORM_TYPE_IMAGE, 5, [_hrd]),
			_u(RenderingDevice.UNIFORM_TYPE_IMAGE, 6, [color]),
			_u(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 7, [_pbuf]),
			_u(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 8, [_lin, smoke_c]),
		]
		var set := UniformSetCacheRD.get_cache(_shader, 0, us)
		for mode in 2:
			var pc := PackedFloat32Array([mode, size.x, size.y, 0.0]).to_byte_array()
			var groups := hs if mode == 0 else size
			var cl := _rd.compute_list_begin()
			_rd.compute_list_bind_compute_pipeline(cl, _pipe)
			_rd.compute_list_bind_uniform_set(cl, set, 0)
			_rd.compute_list_set_push_constant(cl, pc, pc.size())
			_rd.compute_list_dispatch(cl, ceili(groups.x / 8.0), ceili(groups.y / 8.0), 1)
			_rd.compute_list_end()
	if measure:
		_rd.capture_timestamp("fluid_draw_end")


const DRAW := """#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
// 엔진 장면 데이터 블록의 앞부분 (Godot 4.7: 투영 두 개는 mat4, 뷰 두 개는 행 우선 3×4 — 열 i 가 변환의 i 번째 행)
layout(set = 0, binding = 0, std140) uniform SceneDataBlock {
	mat4 projection_matrix;
	mat4 inv_projection_matrix;
	mat3x4 inv_view_matrix;
	mat3x4 view_matrix;
} scene;
layout(set = 0, binding = 1) uniform sampler2D depth_tex;
layout(set = 0, binding = 2) uniform sampler2D smoke_a;
layout(set = 0, binding = 3) uniform sampler2D smoke_b;
layout(rgba16f, set = 0, binding = 4) uniform image2D hr_img;
layout(r32f, set = 0, binding = 5) uniform image2D hr_depth;
layout(rgba16f, set = 0, binding = 6) uniform image2D color_img;
layout(set = 0, binding = 7, std430) restrict readonly buffer Params { vec4 p[]; } prm;
layout(push_constant, std430) uniform PC { vec4 a; } pc;
layout(set = 0, binding = 8) uniform sampler2D smoke_c;

float hash(vec2 q) { return fract(sin(dot(q, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 q) {
	vec2 i = floor(q); vec2 f = fract(q); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
vec2 ORIGIN() { return prm.p[0].xy; }
vec2 SIZE() { return prm.p[0].zw; }
float HMAX() { return prm.p[1].x; }
float TIME() { return prm.p[1].y; }
mat4 M(int k) { int b = 4 + k * 4; return mat4(prm.p[b], prm.p[b + 1], prm.p[b + 2], prm.p[b + 3]); }
vec4 SV(int k) { return prm.p[24 + k]; }   // 0 soft 1 line_k 2 rim 3 spec 4 glow_k 5 alo 6 ahi 7 lump_spd

vec2 uv_of(vec2 xz) { return (xz - ORIGIN()) / SIZE(); }

// ── 독가스 속 알갱이: 작은 둥근 점이 드문드문, 천천히 흔들리며 떠다니고 숨쉬듯 커졌다 작아진다 ──
// 세계 좌표 격자(MOTE_CELL)마다 많아야 하나 (칸의 MOTE_FILL 만), 밝은 점 / 어두운 점.
// 따로 칠한 색이 아니라 그 자리 독가스 색을 살짝 밝히거나 어둡게 해서 은은하게 (x = 밝은 점 덮임, y = 어두운 점)
const float MOTE_CELL = 0.85;
const float MOTE_FILL = 0.42;
vec2 motes(vec2 xz) {
	vec2 base = floor(xz / MOTE_CELL);
	vec2 res = vec2(0.0);
	float t = TIME();
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 id = base + vec2(float(i), float(j));
			float h = hash(id * 1.37 + 11.0);
			if (h > MOTE_FILL) continue;
			float h2 = hash(id + 3.1);
			float h3 = hash(id + 7.7);
			float h4 = hash(id + 5.3);
			vec2 c = (id + vec2(0.2 + 0.6 * h2, 0.2 + 0.6 * h3)) * MOTE_CELL
				+ vec2(sin(t * (0.25 + 0.2 * h4) + h2 * 6.283), cos(t * (0.2 + 0.18 * h2) + h3 * 6.283)) * 0.24;
			float r = mix(0.05, 0.11, h4 * h4) * (0.8 + 0.2 * sin(t * (0.4 + 0.3 * h3) + h4 * 6.283));
			float k = 1.0 - smoothstep(r - 0.022, r + 0.01, length(xz - c));
			if (h < MOTE_FILL * 0.55) res.x = max(res.x, k); else res.y = max(res.y, k);
		}
	}
	return res;
}
// 미리 곱한 색에 알갱이를 얹는다 (tox = 그 자리 독가스 짙기 — 옅은 가장자리에선 사라짐)
vec4 with_motes(vec4 src, vec2 xz, float tox) {
	float pres = smoothstep(0.1, 0.4, tox);
	if (pres <= 0.0 || src.a <= 0.0) return src;
	vec2 m = motes(xz) * pres;
	vec3 c = src.rgb;
	c = mix(c, mix(src.rgb * 1.3, vec3(0.78, 1.0, 0.8) * src.a, 0.5), m.x * 0.85);   // 밝은 점: 옅은 흰빛 연두
	c = mix(c, src.rgb * 0.45, m.y * 0.8);
	return vec4(c, src.a);
}

// ── 부스터 배기: 짙기에 따라 부드러운 색 그라데이션 (막 나온 짙은 배기 = 뜨거운 색 → 옅어지며 식은 색), 옅은 반투명 ──
vec3 lin(vec3 s) { return pow(s, vec3(2.2)); }
float ex_at(vec2 xz) { return textureLod(smoke_c, uv_of(xz), 0.0).r; }
vec3 ex_band(float v) {
	vec3 c = lin(vec3(0.66, 0.46, 0.96));                              // 보라 (식은 가장자리)
	c = mix(c, lin(vec3(1.0, 0.50, 0.70)), smoothstep(0.04, 0.14, v)); // 분홍
	c = mix(c, lin(vec3(1.0, 0.66, 0.36)), smoothstep(0.12, 0.26, v)); // 주황
	c = mix(c, lin(vec3(1.0, 0.92, 0.66)), smoothstep(0.24, 0.45, v)); // 크림 노랑
	return c;
}
// 미리 곱한 색 + 투명도: 외곽선 · 명암 단계 없이 가장자리까지 부드럽게 사그라진다
vec4 ex_toon(vec2 xz) {
	float v = ex_at(xz);
	float al = smoothstep(0.01, 0.2, v) * 0.68;
	return vec4(ex_band(v) * al, al);
}
float lump_at(vec2 xz, float spd) {
	float tt = TIME() * spd;
	return noise(xz * 0.55 + vec2(tt * 0.05, -tt * 0.04)) * 0.75 + noise(xz * 1.4 - tt * 0.07) * 0.25;
}
// 행진 한 걸음 = 텍스처 한 번: A = (높이 단면, 결 세기, 결 속도, 밀도)
float height(vec2 xz) {
	vec4 a = textureLod(smoke_a, uv_of(xz), 0.0);
	if (a.w < 0.02) return -1.0;
	return HMAX() * a.x * (1.0 - a.y * 0.5 + a.y * lump_at(xz, a.z));
}
// 화소의 장면까지 시선 깊이 (올려 붙이기에서 깊이가 닮았는지 볼 때)
float view_z(ivec2 fp, vec2 full) {
	vec2 uv = (vec2(fp) + 0.5) / full;
	float z = texelFetch(depth_tex, fp, 0).r;
	vec4 vp = scene.inv_projection_matrix * vec4(uv * 2.0 - 1.0, max(z, 1e-4), 1.0);
	return abs(vp.z / vp.w);
}

vec3 to_world(vec3 v) {
	vec4 h = vec4(v, 1.0);
	return vec3(dot(scene.inv_view_matrix[0], h), dot(scene.inv_view_matrix[1], h), dot(scene.inv_view_matrix[2], h));
}
vec3 world_at(vec2 uv, float z) {
	vec4 vp = scene.inv_projection_matrix * vec4(uv * 2.0 - 1.0, z, 1.0);
	return to_world(vp.xyz / vp.w);
}

vec4 march(ivec2 fp, vec2 full) {
	vec2 uv = (vec2(fp) + 0.5) / full;
	float z = texelFetch(depth_tex, fp, 0).r;
	vec3 cam = vec3(scene.inv_view_matrix[0].w, scene.inv_view_matrix[1].w, scene.inv_view_matrix[2].w);
	// 광선 = 카메라 → 이 화소의 장면 점 (투영 행렬의 부호 관례에 기대지 않는다). 하늘(깊이 0)이면 먼 점 쪽으로
	vec3 ps = world_at(uv, z > 0.0 ? z : 1e-4);
	vec3 dir = normalize(ps - cam);
	float scene_t = z > 0.0 ? length(ps - cam) : 1e9;
	float top = HMAX() + 0.4;
	if (dir.y > -1e-4) return vec4(0.0);
	float t0 = cam.y > top ? (cam.y - top) / -dir.y : 0.0;
	float t1 = min(cam.y / -dir.y, scene_t);
	if (t1 <= t0) return vec4(0.0);
	// 빈 곳 버리기: 광선이 지나는 바닥 자리 4곳이 모두 비었으면 행진하지 않는다
	if (prm.p[3].w > 0.5) {
		float m = 0.0;
		for (int i = 0; i <= 3; i++) {
			vec3 q = cam + dir * mix(t0, t1, float(i) / 3.0);
			m = max(m, textureLod(smoke_a, uv_of(q.xz), 0.0).w);
		}
		if (m < 0.02) return vec4(0.0);
	}
	if (prm.p[2].w > 0.5) {
		// 확인용: 바닥 자리의 밀도 × 스타일 색
		vec3 fq = cam + dir * t1;
		vec4 a = textureLod(smoke_a, uv_of(fq.xz), 0.0);
		vec4 w = textureLod(smoke_b, uv_of(fq.xz), 0.0);
		float ex = textureLod(smoke_c, uv_of(fq.xz), 0.0).r;
		// 배기를 뺀 나머지 연기: 스타일 비율을 배기 몫을 뺀 것으로 다시 맞춘다 (안 그러면 배기가 그을음처럼 검게 섞임)
		float rest = max(a.w - ex, 0.0);
		vec4 wb = w * (a.w / max(rest, 1e-4));
		float al = clamp(rest * 1.5, 0.0, 0.9);
		// 장면 점이 그 자리 연기 윗면보다 높으면(위에 떠 있는 오염 입자 · 서 있는 몸의 윗부분) 연기가 덮지 않는다
		float gtop = HMAX() * a.x;
		float under = 1.0 - smoothstep(gtop + 0.1, gtop + 0.45, fq.y);
		al *= under;
		vec4 base = vec4((M(0) * wb).rgb * clamp(rest, 0.0, 1.0) * al, al);
		base = with_motes(base, fq.xz, w.z * a.w);
		vec4 exl = ex > 0.02 ? ex_toon(fq.xz) * under : vec4(0.0);
		return exl + base * (1.0 - exl.a);
	}
	int steps = int(prm.p[1].z);
	int bisect = int(prm.p[1].w);
	float st = (t1 - t0) / float(steps);
	float t = t0;
	bool hit = false;
	for (int i = 0; i < steps; i++) {
		t += st;
		vec3 q = cam + dir * t;
		if (q.y < height(q.xz)) { hit = true; break; }
	}
	if (!hit) return vec4(0.0);
	float lo = t - st;
	float hi = t;
	for (int i = 0; i < bisect; i++) {
		float m = (lo + hi) * 0.5;
		vec3 q = cam + dir * m;
		if (q.y < height(q.xz)) hi = m; else lo = m;
	}
	vec3 q = cam + dir * hi;
	float e = 0.12;
	vec3 nrm = normalize(vec3(height(q.xz - vec2(e, 0)) - height(q.xz + vec2(e, 0)), 2.0 * e, height(q.xz - vec2(0, e)) - height(q.xz + vec2(0, e))));
	vec4 a = textureLod(smoke_a, uv_of(q.xz), 0.0);
	vec4 w = textureLod(smoke_b, uv_of(q.xz), 0.0);
	float wsum = max(dot(w, vec4(1.0)), 1e-4);
	vec4 wn = w / wsum;
	float exq = textureLod(smoke_c, uv_of(q.xz), 0.0).r;
	float exf = clamp(exq / max(a.w, 1e-4), 0.0, 1.0);
	float soot = clamp(1.0 - dot(w, vec4(1.0)) - exf, 0.0, 1.0);
	vec3 L = normalize(prm.p[2].xyz);
	float ndl = dot(nrm, L);
	float soft = dot(wn, SV(0)) + 0.02;
	vec3 lit = (M(0) * wn).rgb;
	vec3 mid = (M(1) * wn).rgb;
	vec3 dark = (M(2) * wn).rgb;
	// 명암: 경계 부드러움(soft)이 크면 그라데이션, 작으면 만화 단
	vec3 col = mix(dark, mid, smoothstep(0.08 - soft, 0.08 + soft, ndl));
	col = mix(col, lit, smoothstep(0.5 - soft, 0.5 + soft, ndl));
	col *= mix(0.9, 1.0, smoothstep(0.0, HMAX() * 0.5, q.y));
	float facing = clamp(dot(nrm, -dir), 0.0, 1.0);
	// 역광 테두리
	col += lit * dot(wn, SV(2)) * pow(1.0 - facing, 2.5) * 0.7;
	// 해 쪽 하이라이트 (증기)
	vec3 hv = normalize(L - dir);
	float sp = pow(max(dot(nrm, hv), 0.0), 28.0);
	col += vec3(1.0) * dot(wn, SV(3)) * (smoothstep(0.35, 0.45, sp) * 0.55 + sp * 0.25);
	// 안쪽 발광 (독가스): 짙은 곳일수록, 결을 따라 맥박친다
	float lump = lump_at(q.xz, dot(wn, SV(7)));
	col += (M(4) * wn).rgb * dot(wn, SV(4)) * smoothstep(0.25, 1.4, a.w) * (0.7 + 0.3 * sin(TIME() * 2.6 + lump * 9.0));
	// 그을음
	col = mix(col, prm.p[32].rgb * mix(0.85, 1.2, step(0.3, ndl)), soot * 0.85);
	// 부스터 배기: 짙기 색 그라데이션 (명암 단계 없음)
	col = mix(col, ex_band(exq), exf);
	// 실루엣 외곽선
	float sty = clamp(1.0 - soot - exf, 0.0, 1.0);   // 스타일 연기 몫
	float lk = dot(wn, SV(1)) * sty + soot * 0.5;
	col = mix(col, (M(3) * wn).rgb, step(facing, 0.2) * lk);
	float alo = dot(wn, SV(5)) * sty + soot * 0.5 + exf * 0.2;
	float ahi = dot(wn, SV(6)) * sty + soot * 0.8 + exf * 0.5;
	float alpha = smoothstep(0.02, 0.16, a.w) * mix(alo, ahi, smoothstep(0.15, 1.1, a.w));
	return with_motes(vec4(col * alpha, alpha), q.xz, w.z * a.w);
}

void main() {
	int mode = int(pc.a.x);
	vec2 full = pc.a.yz;
	ivec2 fs = ivec2(full);
	int scale = max(int(prm.p[3].z), 1);
	ivec2 hs = ivec2(ceil(full / float(scale)));
	ivec2 g = ivec2(gl_GlobalInvocationID.xy);
	if (mode == 0) {
		if (g.x >= hs.x || g.y >= hs.y) return;
		ivec2 fp = min(ivec2((vec2(g) + 0.5) * float(scale)), fs - 1);
		imageStore(hr_img, g, march(fp, full));
		imageStore(hr_depth, g, vec4(view_z(fp, full)));
	} else {
		if (g.x >= fs.x || g.y >= fs.y) return;
		vec4 src;
		if (scale == 1) {
			src = imageLoad(hr_img, g);
		} else {
			// 깊이를 보는 올려 붙이기: 쌍선형 무게 × 깊이가 닮은 정도
			float zf = view_z(g, full);
			vec2 hp = (vec2(g) + 0.5) / float(scale) - 0.5;
			ivec2 i0 = ivec2(floor(hp));
			vec2 f = hp - vec2(i0);
			src = vec4(0.0);
			float wsum = 0.0;
			float best = 1e9;
			vec4 nearest = vec4(0.0);
			for (int k = 0; k < 4; k++) {
				ivec2 o = ivec2(k & 1, k >> 1);
				ivec2 h = clamp(i0 + o, ivec2(0), hs - 1);
				vec4 c = imageLoad(hr_img, h);
				float zh = imageLoad(hr_depth, h).r;
				float dz = abs(zh - zf);
				float bw = (o.x == 1 ? f.x : 1.0 - f.x) * (o.y == 1 ? f.y : 1.0 - f.y);
				float wd = bw * exp(-dz / max(zf * 0.04, 0.05));
				src += c * wd;
				wsum += wd;
				if (dz < best) { best = dz; nearest = c; }
			}
			src = wsum > 1e-4 ? src / wsum : nearest;
		}
		if (src.a < 0.002) return;
		vec4 col = imageLoad(color_img, g);
		col.rgb = col.rgb * (1.0 - src.a) + src.rgb;
		imageStore(color_img, g, col);
	}
}
"""
