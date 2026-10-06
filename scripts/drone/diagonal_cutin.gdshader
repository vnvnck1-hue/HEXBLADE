shader_type canvas_item;
// 사선 DOCKING 컷인의 포트레이트 (docs/diagonal-docking-cutin-study.md §4).
// ① 하단 반평면 마스크: 화면(Canvas) 좌표의 하단 기준선 아래(d > 0)를 1px 안티앨리어싱으로 지운다. 머리·어깨 쪽은 자르지 않는다.
// ② 가슴 흔들림 UV 모핑: cutin_jiggle.gdshader 와 같은 방식(타원 두 개 안의 UV 만 민다). 오프셋은 DiagonalDockingCutin 의 스프링이 넣는다.
// ③ 머리카락 흔들림: 머리카락 마스크(tools/cutin_portraits.py, 흐린 256²) 영역의 UV 만 민다. 뿌리(hair_root)는 고정, 끝으로 갈수록(거리²) 크게 —
//    관성 스프링 변위(hair_off) + 잔잔한 물결(hair_time · hair_wave).
// ④ 치마 · 옷가지 (motion > 0 인 캐릭터만, 민트 메이드): 움직임 마스크의 G(치마, 허리 0 → 밑단 1) · B(리본 꼬리)를
//    각자 스프링 변위(skirt_off · cloth_off) + 밑단 펄럭임(flutter)으로 민다. 이때 hair_mask 는 RGB 움직임 마스크(R = 머리카락).
// ⑤ silhouette > 0: 같은 모양(같은 변형)을 단색으로 — 캐릭터 뒤 그림자.
// bust = 0 이면 가슴 모핑을 끈다.

uniform vec2 clip_origin;                 // 하단선의 왼쪽 기준점 O (Canvas 좌표)
uniform vec2 clip_normal = vec2(0.0, 1.0); // 단위 법선, 선 아래가 양수
uniform float flash = 0.0;                // 합체 순간 흰빛

uniform vec2 c_l = vec2(0.403, 0.618);
uniform vec2 c_r = vec2(0.574, 0.622);
uniform vec2 r_l = vec2(0.16, 0.16);  // 과한 변위에서도 접히지 않게 조금 넓게
uniform vec2 r_r = vec2(0.16, 0.16);
uniform vec2 off_l = vec2(0.0);
uniform vec2 off_r = vec2(0.0);
uniform float sq_l = 0.0;
uniform float sq_r = 0.0;
uniform float tilt = -0.05;
uniform sampler2D hair_mask : filter_linear, hint_default_black;
uniform vec2 hair_root = vec2(0.5, 0.2);
uniform float hair_len = 0.3;
uniform vec2 hair_off = vec2(0.0);
uniform float hair_time = 0.0;
uniform float hair_wave = 0.0035;
uniform float bust = 1.0;
uniform float motion = 0.0;
uniform vec2 skirt_off = vec2(0.0);
uniform vec2 cloth_off = vec2(0.0);
uniform float flutter = 0.0;
uniform float silhouette = 0.0;
uniform vec4 sil_color : source_color = vec4(0.1, 0.06, 0.14, 0.6);

varying float clip_d;
varying vec4 vcol;

void vertex() {
	vec2 p = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	clip_d = dot(p - clip_origin, clip_normal);
	vcol = COLOR;
}

vec2 _bounce(vec2 uv, vec2 c, vec2 r, vec2 off, float sq) {
	vec2 rel = uv - c;
	float cs = cos(tilt);
	float sn = sin(tilt);
	vec2 q = vec2(cs * rel.x + sn * rel.y, -sn * rel.x + cs * rel.y) / r;
	float d2 = dot(q, q);
	if (d2 >= 1.0) {
		return vec2(0.0);
	}
	float w = (1.0 - d2) * (1.0 - d2);
	w *= mix(0.35, 1.0, smoothstep(-1.0, 0.45, q.y));
	return w * (off + rel * vec2(-0.5 * sq, sq));
}

vec2 _hair(vec2 uv) {
	float m = texture(hair_mask, uv).r;
	if (m <= 0.002) {
		return vec2(0.0);
	}
	float d = clamp(length(uv - hair_root) / hair_len, 0.0, 1.0);
	float w = m * d * d;
	vec2 wave = vec2(sin(hair_time * 2.3 + uv.y * 11.0), 0.45 * sin(hair_time * 1.7 + uv.x * 9.0 + 1.3)) * hair_wave;
	return w * (hair_off + wave);
}

vec2 _cloth(vec2 uv) {
	vec3 m = texture(hair_mask, uv).rgb;
	if (m.g + m.b <= 0.002) {
		return vec2(0.0);
	}
	// 밑단 펄럭임: 가로로 번지는 물결 (밑단일수록 크게) — 리본은 더 잘게
	vec2 fs = vec2(sin(hair_time * 13.0 - uv.x * 38.0), 0.6 * sin(hair_time * 10.0 - uv.x * 27.0 + 0.8)) * flutter;
	vec2 fc = vec2(sin(hair_time * 17.0 - uv.y * 30.0), 0.4 * sin(hair_time * 14.0 + uv.y * 21.0)) * flutter * 1.4;
	return m.g * (skirt_off + fs) + m.b * (cloth_off + fc);
}

void fragment() {
	vec2 uv = UV;
	uv -= _hair(UV);
	if (motion > 0.0) {
		uv -= motion * _cloth(UV);
	}
	if (bust > 0.0) {
		uv -= bust * _bounce(UV, c_l, r_l, off_l, sq_l);
		uv -= bust * _bounce(UV, c_r, r_r, off_r, sq_r);
	}
	vec4 c = texture(TEXTURE, uv) * vcol;
	c.rgb = mix(c.rgb, vec3(1.0), flash);
	if (silhouette > 0.0) {
		c = vec4(sil_color.rgb, c.a * sil_color.a * silhouette);
	}
	float aa = max(fwidth(clip_d), 0.001);
	c.a *= 1.0 - smoothstep(-0.5 * aa, 0.5 * aa, clip_d);
	COLOR = c;
}
