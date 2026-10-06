shader_type spatial;
// 1번 설비실 바닥 (ClaudeServiceDress): 벽 밖 비플레이 공간의 한 층 낮은 바닥.
// F01 4m 핸드페인팅 텍스처의 명암만 빌려 어두운 남색으로 칠하고(통로보다 어둡고 저채도), 2m 타일 일부에 배수 격자를 그린다.
// 꼭짓점 색(COLOR.r) = 바깥으로 갈수록 어두워지는 정도 → 원래의 어둠으로 녹아든다.
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// mo.co 무드 배경 톤 (docs/moco-bg-claude.md): SERVICE_BASE #26334F 에 F01 명암을 약 10% 만 남긴다.
// 예전 값: base_col (0.165, 0.19, 0.30) · 명암 비율 0.45~1.6 · grate_rate 0.32
uniform vec3 base_col : source_color = vec3(0.149020, 0.2, 0.309804);
uniform vec3 grate_col : source_color = vec3(0.04, 0.045, 0.08);
uniform float grate_rate = 0.20;
uniform float detail_strength = 0.10;
uniform float detail_mean = 0.06699;
uniform vec3 cool = vec3(0.92, 1.0, 1.3);   // 화면에서 시안의 푸른 남색이 나오게 (해가 따뜻해 회색으로 기움)
uniform bool old_tone = false;
// 플레이어 조명 풀 (BrawlLook.track_pool 이 pool_use = 1, 위치는 전역 값 bl_pool)
global uniform vec4 bl_pool;      // BrawlLook.update_pool: xyz 플레이어 위치, w 켜짐
uniform float pool_use = 0.0;
#define pool_on (pool_use * bl_pool.w)
#define pool_pos (bl_pool.xyz)
uniform float pool_r0 = 6.5;
uniform float pool_r1 = 14.0;
uniform float pool_dark = 0.28;               // 예전 톤 비교용 (--bgtone=old → ClaudeServiceDress.floor_material)

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec3 t = texture(albedo_tex, wpos.xz / 4.0).rgb;
	float l = dot(t, vec3(0.2126, 0.7152, 0.0722));
	vec3 col = base_col * cool * clamp(1.0 + (l / detail_mean - 1.0) * detail_strength, 0.8, 1.2);
	if (old_tone) col = base_col * clamp(l / 0.085, 0.45, 1.6);
	vec2 tile = floor(wpos.xz / 2.0);
	vec2 f = fract(wpos.xz / 2.0);
	if (hash(tile) < grate_rate) {
		vec2 g = abs(f - 0.5);
		float m = max(g.x, g.y);
		float inside = 1.0 - smoothstep(0.335, 0.345, m);
		float frame = (1.0 - smoothstep(0.375, 0.385, m)) - inside;
		float s = fract((hash(tile + 7.3) < 0.5 ? f.y : f.x) * 11.0);
		float gap = smoothstep(0.42, 0.5, s) * (1.0 - smoothstep(0.86, 0.94, s));
		col = mix(col, col * 1.35, frame);
		col = mix(col, grate_col, inside * gap * 0.9);
	}
	ALBEDO = col * COLOR.r;
	vec2 pd = wpos.xz - pool_pos.xz;
	pd.y *= 1.25;
	float pt = smoothstep(pool_r0, pool_r1, length(pd));
	float pk = mix(1.0, pool_dark, pt * pt * (3.0 - 2.0 * pt) * pool_on);
	ALBEDO *= pk;           // 기본 조명 셰이더라 해·환경광을 따로 줄일 수 없어 바탕색으로 같은 비율을 준다
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
