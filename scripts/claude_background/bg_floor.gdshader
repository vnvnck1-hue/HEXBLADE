shader_type spatial;
// F01 바닥 (Claude 배경 첫 제작): 4m(2048px) 핸드페인팅 텍스처를 월드 XZ 로 읽어 2m 타일끼리 그림을 잇는다.
// 타일 위치·90도 회전과 무관하게 4m 주기가 유지된다. 옆면(타일 옆·지형 단차)은 월드 좌표 옆 투영.
// 시험 씬(F01 16장)과 본편 아레나 바닥(ClaudeBgDress) 이 같은 셰이더를 쓴다.
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float period = 4.0;
uniform vec2 offset = vec2(0.0);   // 줄눈 위상 (본편: 방 벽에서 2m 줄눈이 시작되게 0 또는 1m)
uniform float roughness_v = 0.85;
uniform float specular_v = 0.25;

#include "res://scripts/claude_background/blue_handpaint_common.gdshaderinc"
#include "res://scripts/claude_background/blue_handpaint_floor.gdshaderinc"

varying vec3 wpos;
varying vec3 wn;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = (wpos.xz - offset) / period;
	if (abs(wn.y) < 0.5) {
		uv = vec2(abs(wn.x) > abs(wn.z) ? wpos.z : wpos.x, -wpos.y) / period;
	}
	ALBEDO = handpaint ? hp_floor(uv, wpos, wn, offset) : texture(albedo_tex, uv).rgb;
	ROUGHNESS = roughness_v;
	SPECULAR = specular_v;
}
