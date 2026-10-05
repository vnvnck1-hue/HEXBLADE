shader_type canvas_item;
// 조종석 컷인 원화의 가슴 흔들림 (UV 변형 모핑). 원화 한 장을 자르지 않고, 타원 두 개 안의 UV 만 밀어서 흔든다.
// 바깥(테두리 밖)은 무게 0 이라 원화 그대로. 위쪽(가슴 뿌리)은 덜, 아래쪽은 더 움직여 매달린 느낌을 준다.
// 오프셋·늘임은 CockpitCutin 의 스프링이 매 프레임 넣는다 (단위: UV).

uniform vec2 c_l = vec2(0.386, 0.635);   // 화면 왼쪽 가슴 중심 (UV)
uniform vec2 c_r = vec2(0.567, 0.655);   // 화면 오른쪽 가슴 중심
uniform vec2 r_l = vec2(0.135, 0.135);   // 영향 반경 (가슴보다 조금 크게: 외곽선이 같이 움직인다)
uniform vec2 r_r = vec2(0.140, 0.140);
uniform vec2 off_l = vec2(0.0);           // 스프링 변위 (UV)
uniform vec2 off_r = vec2(0.0);
uniform float sq_l = 0.0;                 // 세로 늘임(+) / 눌림(-) 비율
uniform float sq_r = 0.0;
uniform float tilt = -0.18;               // 원화 몸이 기울어 있어 타원도 같이 기울인다 (rad)

varying vec4 vcol;

void vertex() {
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
	// 뿌리(위)는 35%, 아래 끝은 100%
	w *= mix(0.35, 1.0, smoothstep(-1.0, 0.45, q.y));
	// 역매핑: 그려질 자리 = 원래 + off → 원래 = 지금 - off. 늘임은 중심 기준 세로 sq, 가로 -sq/2 (부피 유지)
	return w * (off + rel * vec2(-0.5 * sq, sq));
}

void fragment() {
	vec2 uv = UV;
	uv -= _bounce(UV, c_l, r_l, off_l, sq_l);
	uv -= _bounce(UV, c_r, r_r, off_r, sq_r);
	COLOR = texture(TEXTURE, uv) * vcol;
}
