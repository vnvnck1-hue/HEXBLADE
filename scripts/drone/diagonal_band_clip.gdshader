shader_type canvas_item;
// 사선 DOCKING 띠 안의 글자: 하단선 아래(d_bottom > 0)와 위 경계 위(d_top < 0)를 지운다 (docs/diagonal-docking-cutin-study.md §4).
// 글자 색은 COLOR 에 이미 들어 있으므로 텍스처를 다시 곱하지 않는다.

uniform vec2 bottom_origin;
uniform vec2 bottom_normal = vec2(0.0, 1.0);
uniform vec2 top_origin;
uniform vec2 top_normal = vec2(0.0, 1.0);

varying float d_bottom;
varying float d_top;

void vertex() {
	vec2 p = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	d_bottom = dot(p - bottom_origin, bottom_normal);
	d_top = dot(p - top_origin, top_normal);
}

void fragment() {
	float ab = max(fwidth(d_bottom), 0.001);
	float at = max(fwidth(d_top), 0.001);
	float keep = (1.0 - smoothstep(-0.5 * ab, 0.5 * ab, d_bottom)) * smoothstep(-0.5 * at, 0.5 * at, d_top);
	COLOR.a *= keep;
}
