class_name BrawlLook
extends RefCounted
const BLUE_PAINT := preload("res://scripts/claude_background/blue_handpaint.gd")
## 브롤스타즈(Supercell) 식 화면: 리서치·관찰 근거는 docs/brawl-look.md.
##  1. 카메라 — 멀리서 좁은 화각(망원)으로 50° 내려다본다. 원근이 약해 벽 앞면이 거의 평행하게 보이고 캐릭터는 정면에 가깝다.
##     (CameraRig 의 BRAWL 프리셋. 보이는 바닥 넓이는 기존 TACTICAL 과 같게 거리를 맞췄다)
##  2. 조명 — 밝고 따뜻한 해 + 강한 하늘색 환경광(그림자 쪽도 밝다), 옅고 부드러운 그림자, 채도 보정. 어두운 반사·짙은 AO 없음.
##  3. 셰이딩 — 경계가 살짝 부드러운 2단 셀 음영. 그림자 쪽은 회색이 아니라 보라·파랑으로 색조가 옮겨 간다.
##     윗면은 조금 밝게, 캐릭터·소품은 위쪽 테두리에 하늘빛 림라이트, 작은 둥근 하이라이트.
##  4. 외곽선 — 캐릭터 실루엣에만 얇고 짙은 선. 바닥·벽(월드)에는 긋지 않고, 파츠 안쪽 꺾임선도 없다.
##  5. 발밑 — 캐릭터마다 부드러운 둥근 접지 그림자, 적은 붉은 원(아군·자신은 기존 청록 링).
## 판정·게임 진행과 무관하며 머티리얼만 바꿔 끼운다(원본은 메타에 보관, N 키로 되돌림).
## 기본 켜짐. 실행 인자 --look=classic 이면 예전 화면으로 시작. PaintedLook(K)과는 동시에 켜지지 않는다.

static var on := not (OS.get_cmdline_user_args().has("--look=classic") or OS.get_cmdline_user_args().has("--look=hearth"))

# ── 조명 · 색 기준값 ────────────────────────────────────
## 해는 화면 왼쪽 위에서 — 그림자가 물체 오른쪽(살짝 위)으로 떨어져 망원 부감에서도 보인다. 정면은 반쯤 밝다.
const SUN_ROT := Vector3(-56, -104, 0)
const SUN_COLOR := Color(1.0, 0.95, 0.86)
const SUN_ENERGY := 1.15
const SHADOW_OPACITY := 0.5        # mo.co 무드 (--bgtone=old 면 예전 0.62)
const AMBIENT := Color(0.74, 0.76, 0.92)
const AMBIENT_ENERGY := 0.72
const BG := Color(0.07, 0.06, 0.14)
const RIM := 0.68
## 배경(바닥·벽·맵 소품)과 캐릭터(플레이어·적)의 톤 분리 — 배경은 명도·채도를 눌러 살짝 차갑게 가라앉히고,
## 캐릭터는 채도를 올려 앞으로 띄운다 (_capture/brawl_tone_probe.gd 로 밝기·채도 비를 잰다)
const WORLD_VALUE := 0.6          # 배경 명도 배율
const WORLD_SAT := 0.5           # 배경 채도 배율
const WORLD_TINT := Color(0.93, 0.95, 1.06)   # 배경을 살짝 차갑게 (캐릭터의 따뜻한 빛과 갈라지게)
const CHAR_SAT := 1.32            # 캐릭터 채도
const CHAR_VALUE := 1.06          # 캐릭터 명도
const CHAR_SHADE := Color(0.74, 0.64, 0.92)   # 캐릭터 그림자 쪽 색조 — 배경(보라·파랑)보다 덜 푸르게, 따뜻한 몸색이 회색으로 죽지 않게
const LINE_COLOR := Color(0.09, 0.06, 0.13, 0.92)

## mo.co 무드 배경 톤 (docs/moco-vfx-claude-handoff.md 의 시작안 → 실제 화면에서 조정, 기록은 docs/moco-bg-claude.md).
## 통로 바닥 · 벽(윗면/옆면) · 벽 밖 설비를 같은 WORLD 배율로 누르지 않고 역할별로 칠한다:
## 바닥과 벽은 정해진 기본색 위에 원본 붓질 명암만 약하게 남기고, 설비는 더 어둡게 가라앉힌다.
## 실행 인자 --bgtone=old 면 예전(WORLD 배율 하나) 톤.
static var moco := not OS.get_cmdline_user_args().has("--bgtone=old")
const FLOOR_BASE := Color("6f7ba4")        # 통로 바닥 기본 입력색 (sRGB)
const FLOOR_VALUE := 0.55                 # (1단계 0.78 → 캐릭터 시인성을 위해 더 낮춤)
## 따뜻한 해(SUN_COLOR)가 기본색을 회색 쪽으로 끌어내려 화면에서 시안의 푸른 라벤더가 안 나온다 → 바닥·벽 입력에 차가운 보정 (화면 비교로 정함)
const BG_COOL := Color(0.95, 1.0, 1.22)
const FLOOR_DETAIL := 0.12                 # 원본 F01 명암을 남기는 세기
const FLOOR_DETAIL_MEAN := 0.06699         # F01 선형 휘도 평균 (64×64 표본, 핸드오프 texture_measurements.json)
const WALL_TOP := Color("a0a7d1")
const WALL_SIDE := Color("68719d")
const WALL_VALUE := 0.60                  # (1단계 0.80)
const WALL_TOP_K := 0.66                   # 윗면만 더 누름 (0.80 그대로면 해를 정면으로 받아 흰색으로 날아가고 붓질이 사라짐)
const WALL_MIX := 0.65                     # 기본색 비중. 나머지는 원본 텍스처(저채도)의 명암·색
const WALL_MEAN := Vector2(0.09, 0.13)     # 벽 텍스처의 실제 UV 영역 선형 휘도 평균 (윗면, 옆면) — _capture/moco_uv_mean.gd
const SERVICE_VALUE := 0.30                # 벽 밖 설비 프랍 명도 (1단계 0.38)
const SERVICE_LAMP_K := 1.0 / 2.2          # 설비 상태등 세기 배율 (ClaudeServiceDress.LAMP_ENERGY 2.2 → 1.0)
const FALLBACK_SAT := 0.35                 # 역할이 없는 월드(작업대·수납장 등)의 채도
const FALLBACK_VALUE := 0.42               # 역할이 없는 월드(벽면 캐비닛·작업대 등)의 명도 (예전 WORLD_VALUE 0.6)

## 플레이어 조명 풀: 배경(바닥·벽·설비·맵 소품) 전체에 부드러운 어둠을 깔고 플레이어 둘레만 해·환경광을 남긴다.
## 캐릭터(플레이어·적) 재질은 어두워지지 않아 어둠 속에서도 또렷하다. 점광원(레이저·폭발·총구)과 상태등 발광도 그대로라
## 어둠 속에서 빛이 살아난다. 실행 인자 --pool=off 로 끔. 거리는 XZ 평면, 앞뒤(Z)는 화면에서 짧아 보여 1.25 배로 잰다.
static var pool := moco and not OS.get_cmdline_user_args().has("--pool=off")
const POOL_R0 := 3.5        # 이 안은 완전히 밝다 (m)
const POOL_R1 := 10.5       # 여기서 가장 어둡다 (BRAWL 화면 가장자리쯤)
const POOL_DARK := 0.2      # 가장 어두운 곳에 남는 해·환경광 비율

## 플레이어 조명 풀 (배경 재질만 pool_use = 1). fragment 에서 v_pool 을 쓰고 light() 가 해의 빛에 곱한다. 환경광은 AO 로 줄인다
const POOL := """
// 플레이어 위치·켜짐은 전역 셰이더 값 하나(bl_pool = xyz 위치, w 켜짐)로 매 프레임 한 번만 넣는다 (예전엔 추적하는 배경 재질마다 두 값씩).
// pool_use = 이 재질이 조명 풀을 쓰는지 (track_pool 이 1 로). 아래 #define 덕에 셰이더 본문은 예전 이름(pool_on · pool_pos) 그대로.
global uniform vec4 bl_pool;
uniform float pool_use = 0.0;
#define pool_on (pool_use * bl_pool.w)
#define pool_pos (bl_pool.xyz)
uniform float pool_r0 = 6.5;
uniform float pool_r1 = 14.0;
uniform float pool_dark = 0.28;
varying float v_pool;
float pool_k(vec3 p) {
	vec2 d = p.xz - pool_pos.xz;
	d.y *= 1.25;
	float t = smoothstep(pool_r0, pool_r1, length(d));
	return mix(1.0, pool_dark, t * t * (3.0 - 2.0 * t) * pool_on);
}
"""

## 공통 조명 함수: 부드러운 2단 셀 + 그림자 색조 이동 + 작은 둥근 하이라이트
const LIGHT := """
uniform vec3 shade_tint : source_color = vec3(0.56, 0.52, 0.98);
uniform float shade_floor = 0.36;   // 그림자 쪽에 남는 해의 몫 (색조 입힘)
uniform float band = 0.14;          // 명암 경계 부드러움
// 작은 둥근 하이라이트. 기본 0 = 무광 — 바닥·벽에 켜면 지형 굴곡을 따라 넓은 흰 반사 얼룩이 번진다
// (완만한 굴곡의 법선이 반사 방향과 맞는 넓은 구간이 한꺼번에 하이라이트를 받음). 캐릭터·소품만 켠다.
uniform float spec_k = 0.0;
uniform float shadow_k = 1.0;       // 드리운 그림자 세기. 캐릭터는 낮춰 울퉁불퉁한 몸의 자기 그림자 얼룩을 없앤다

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float s = smoothstep(-0.02, band, ndl + 0.06);
	vec3 lc = LIGHT_COLOR / PI;
	vec3 hv = normalize(LIGHT + VIEW);
	float hl = smoothstep(0.93, 0.965, dot(NORMAL, hv)) * spec_k;
	if (LIGHT_IS_DIRECTIONAL) {
		// 해: ATTENUATION = 그림자뿐. 셀 2단 + 그림자 쪽에도 색조 입힌 해의 몫을 남긴다
		float sh = mix(1.0, smoothstep(0.15, 0.85, ATTENUATION), shadow_k);
		float lit = s * sh;
		// 조명 풀: 배경은 플레이어에서 멀수록 해의 빛이 줄어든다 (캐릭터는 v_pool = 1)
		DIFFUSE_LIGHT += lc * mix(shade_tint * shade_floor, vec3(1.0), lit) * v_pool;
		SPECULAR_LIGHT += lc * hl * lit * v_pool;
		// 림라이트도 해에서 나온다 — 강력 레이저 연출(Main.dramatic)로 해가 꺼지면 테두리빛도 같이 꺼진다
		SPECULAR_LIGHT += lc * v_rim;
	} else {
		// 점·스포트 조명(총구 섬광·폭발·레이저): 예전 화면과 같은 램버트(입사각) × 거리 감쇠.
		// 셀처럼 입사각을 무시하면 낮게 뜬 레이저 조명이 범위 안 바닥 전체를 평평하게 밝혀 어둠 연출이 깨진다.
		float ndl_c = clamp(ndl, 0.0, 1.0);
		DIFFUSE_LIGHT += lc * ATTENUATION * ndl_c;
		SPECULAR_LIGHT += lc * ATTENUATION * hl * ndl_c;
	}
}
"""

## 캐릭터·소품·벽(파츠) 공용. world 머티리얼은 림라이트를 끄고 러프니스 0.5 로 '외곽선 없음' 표시를 한다.
const BODY := """
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_tex = false;
uniform float tex_gamma = 1.0;      // <1: 텍스처에 구워진 짙은 명암을 들어 올려 넓은 색면에 가깝게
uniform bool use_vcol = false;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal = false;
uniform float normal_scale = 1.0;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform vec3 emission : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform sampler2D emission_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float rim = 0.55;
uniform vec3 rim_color : source_color = vec3(0.86, 0.93, 1.0);
uniform float sat = 1.12;
uniform float value_k = 1.0;        // 명도 배율 (배경은 눌러서 캐릭터와 톤을 가른다)
uniform vec3 tint : source_color = vec3(1.0);
uniform float top_lift = 0.12;      // 위를 향한 면을 밝게 (칠한 하늘빛)
uniform float out_rough = 0.9;      // ToonOutline 분류: 0.9 캐릭터(실루엣 선) · 0.5 월드(선 없음)
// 벽 역할 (mo.co 무드): 윗면/옆면 기본색 위에 원본 텍스처 명암을 (1 - role_mix) 만큼만 남긴다. role_mix 0 = 끔
uniform float role_mix = 0.0;
uniform vec3 role_top : source_color = vec3(1.0);
uniform vec3 role_side : source_color = vec3(1.0);
uniform vec2 role_mean = vec2(0.1);  // 원본 텍스처의 실제 UV 영역 선형 휘도 평균 (윗면, 옆면)
uniform float role_top_k = 1.0;     // 윗면 명도 배율
uniform vec3 role_tint = vec3(1.0);  // 선형 배율 (source_color 아님 — 1 넘는 값을 그대로 곱한다)

#include "res://scripts/claude_background/blue_handpaint_common.gdshaderinc"
#include "res://scripts/claude_background/blue_handpaint_wall.gdshaderinc"

varying vec3 wn;
varying vec3 v_rim;   // 림라이트 색·세기 (light() 에서 해의 빛으로 곱한다)
varying vec3 wpos;

void vertex() {
	UV = UV * uv_scale.xy + uv_offset.xy;
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 c = albedo;
	if (use_tex) {
		vec4 t = texture(albedo_tex, UV);
		c *= vec4(pow(t.rgb, vec3(tex_gamma)), t.a);
	}
	if (use_vcol) c *= COLOR;
	vec3 col = c.rgb;
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = max(mix(vec3(l), col, sat), vec3(0.0)) * value_k * tint;
	vec3 n = normalize(wn);
	if (handpaint && role_mix > 0.0) {
		col = hp_wall(c.rgb, wpos, n) * value_k;
	} else if (role_mix > 0.0) {
		// 윗면 비중: 월드 법선 y. 원본 색을 평균 1 로 맞춘 '명암·색 변화'만 남겨 기본색에 곱한다
		float top = smoothstep(0.35, 0.80, n.y);
		vec3 base = mix(role_side, role_top, top);
		float mean = mix(role_mean.y, role_mean.x, top);
		float tl = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
		vec3 var_c = clamp(mix(vec3(tl), c.rgb, sat) / max(mean, 0.001), vec3(0.35), vec3(1.8));
		col = base * mix(vec3(1.0), var_c, 1.0 - role_mix) * value_k * mix(1.0, role_top_k, top) * role_tint;
	}
	col *= 1.0 + top_lift * n.y;
	ALBEDO = clamp(col, 0.0, 1.0);
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	// 림라이트: 시선과 비스듬한 테두리, 위·뒤쪽일수록 강하게 (하늘빛이 윤곽을 감싼다)
	float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float up = smoothstep(-0.35, 0.55, n.y);
	v_rim = (ALBEDO * 0.55 + rim_color * 0.45) * fr * rim * up;
	vec3 e = vec3(0.0);
	if (emission_energy > 0.0) e += emission * emission_energy * texture(emission_tex, UV).rgb;
	EMISSION = e;
	ROUGHNESS = out_rough;
	SPECULAR = 0.2;
	METALLIC = 0.0;
	v_pool = pool_k(wpos);
	if (pool_on > 0.0) {
		AO = v_pool;              // 환경광도 같은 비율로 (발광·점광원은 그대로)
		AO_LIGHT_AFFECT = 0.0;
	}
}
"""

## 아레나 바닥 (ClaudeBgDress F01 텍스처를 같은 방식으로 읽는다)
const FLOOR := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float period = 4.0;
uniform vec2 offset = vec2(0.0);
uniform float lift = 1.04;
uniform float sat = 1.12;
uniform vec3 warm : source_color = vec3(1.04, 1.0, 0.96);
// mo.co 무드: 기본색 × 명도 × 압축한 원본 명암. 줄눈은 2m 격자 경계 마스크로 따로 (압축으로 사라지지 않게)
uniform bool use_base = false;
uniform vec3 floor_base : source_color = vec3(0.435294, 0.482353, 0.643137);
uniform float floor_value = 0.78;
uniform vec3 floor_tint = vec3(1.0);
uniform float detail_strength = 0.12;
uniform float detail_mean = 0.06699;
uniform float seam_dark = 0.82;     // 줄눈 선 밝기 배율 (화면 Y 차 약 0.05)
uniform float seam_w = 0.03;        // 줄눈 선 폭 (m, 경계 한쪽)
uniform float lip_light = 1.05;     // 줄눈 바로 옆 밝은 턱 (타일 모서리)

#include "res://scripts/claude_background/blue_handpaint_common.gdshaderinc"
#include "res://scripts/claude_background/blue_handpaint_floor.gdshaderinc"
varying vec3 wpos;
varying vec3 wn;
varying vec3 v_rim;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec2 uv = (wpos.xz - offset) / period;
	if (abs(wn.y) < 0.5) uv = vec2(abs(wn.x) > abs(wn.z) ? wpos.z : wpos.x, -wpos.y) / period;
	vec3 col = texture(albedo_tex, uv).rgb;
	if (handpaint) {
		col = hp_floor(uv, wpos, wn, offset) * lift;
	} else if (use_base) {
		float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
		float detail = clamp(1.0 + (luma / max(detail_mean, 0.001) - 1.0) * detail_strength, 0.78, 1.18);
		col = floor_base * floor_value * floor_tint * detail;
		if (abs(wn.y) >= 0.5) {
			// 2m 타일 경계 (offset = 방마다 줄눈 위상). 경계 두께는 화면 미분으로 부드럽게
			vec2 g = (wpos.xz - offset) / 2.0;
			vec2 e = abs(fract(g + 0.5) - 0.5) * 2.0;     // 경계에서 0 (m 단위: × 1)
			float d = min(e.x, e.y);
			float aa = max(fwidth(d), 0.0005);
			float line = 1.0 - smoothstep(seam_w - aa, seam_w + aa, d);
			float lip = (1.0 - smoothstep(seam_w * 2.6 - aa, seam_w * 2.6 + aa, d)) - line;
			col *= mix(1.0, seam_dark, line) * mix(1.0, lip_light, lip);
		}
	} else {
		float l = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(vec3(l), col, sat) * lift * warm;
	}
	ALBEDO = clamp(col, 0.0, 1.0);
	v_rim = vec3(0.0);
	ROUGHNESS = 0.5;
	SPECULAR = 0.15;
	v_pool = pool_k(wpos);
	if (pool_on > 0.0) {
		AO = v_pool;
		AO_LIGHT_AFFECT = 0.0;
	}
}
"""

## 발밑 접지 그림자 + (적) 붉은 팀 원
const BLOB := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;
instance uniform vec4 ring_col : source_color = vec4(0.0);
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float blob = (1.0 - smoothstep(0.15, 0.62, r)) * 0.42;
	float ring = smoothstep(0.7, 0.8, r) * (1.0 - smoothstep(0.88, 0.98, r)) * ring_col.a;
	float disc = (1.0 - smoothstep(0.75, 0.9, r)) * ring_col.a * 0.16;
	vec3 col = mix(vec3(0.08, 0.05, 0.16), ring_col.rgb, clamp((ring + disc) / max(blob + ring + disc, 0.001), 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = 0.0;   // ToonOutline 제외
	ALPHA = clamp(blob + ring + disc, 0.0, 0.9);
}
"""

static var _shaders := {}
static var _game: Node
static var _env: Environment
static var _sun: DirectionalLight3D
static var _orig := {}
static var _floor_mats := {}


static func _shader(kind: String) -> Shader:
	if not _shaders.has(kind):
		var sh := Shader.new()
		match kind:
			"floor": sh.code = FLOOR.replace("render_mode cull_disabled;", "render_mode cull_disabled;\n" + POOL).replace("void fragment()", LIGHT + "\nvoid fragment()")
			"blob": sh.code = BLOB
			"body_nocull": sh.code = "shader_type spatial;\nrender_mode cull_disabled;\n" + POOL + BODY + LIGHT
			_: sh.code = "shader_type spatial;\nrender_mode cull_back;\n" + POOL + BODY + LIGHT
		_shaders[kind] = sh
	return _shaders[kind]


# ── 머티리얼 변환 ───────────────────────────────────────

## 바꿀 수 있는 머티리얼: 조명을 받는 불투명 StandardMaterial3D (단색·텍스처 모두)
static func convertible(m: Material) -> bool:
	var b := m as BaseMaterial3D
	return b != null and b.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
			and b.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED \
			and b.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED and not b.no_depth_test


## 머티리얼 역할: 캐릭터·소품 / 역할 없는 월드 / 벽 / 벽 밖 설비 (벽·설비는 moco 가 꺼지면 월드로)
enum { R_BODY, R_WORLD, R_WALL, R_SERVICE }
const ROLE_KEY := ["bl_body", "bl_world", "bl_moco_wall", "bl_moco_service"]


## 원본 머티리얼 하나에 대응하는 브롤 머티리얼. 원본의 메타에 역할별로 붙여 두므로 원본이 사라지면 같이 사라진다
## (정적 사전에 쌓지 않음 — 씬을 다시 불러도 늘지 않는다). 역할 키가 유한(4개)이라 같은 원본을 벽·설비가 나눠 써도 따로 칠한다.
static func material_for(src: BaseMaterial3D, role: int) -> ShaderMaterial:
	if not moco and role >= R_WALL:
		role = R_WORLD
	var key: String = ROLE_KEY[role]
	if role == R_WALL and BLUE_PAINT.enabled:
		key += "_bluepaint"
	if src.has_meta(key):
		return src.get_meta(key)
	var m := ShaderMaterial.new()
	m.shader = _shader("body_nocull" if src.cull_mode == BaseMaterial3D.CULL_DISABLED else "body")
	m.set_shader_parameter("albedo", src.albedo_color)
	if src.albedo_texture:
		m.set_shader_parameter("albedo_tex", src.albedo_texture)
		m.set_shader_parameter("use_tex", true)
	m.set_shader_parameter("use_vcol", src.vertex_color_use_as_albedo)
	if src.normal_enabled and src.normal_texture:
		m.set_shader_parameter("normal_tex", src.normal_texture)
		m.set_shader_parameter("use_normal", true)
		m.set_shader_parameter("normal_scale", src.normal_scale)
	m.set_shader_parameter("uv_scale", src.uv1_scale)
	m.set_shader_parameter("uv_offset", src.uv1_offset)
	if src.emission_enabled:
		m.set_shader_parameter("emission", src.emission)
		m.set_shader_parameter("emission_energy", src.emission_energy_multiplier * (SERVICE_LAMP_K if role == R_SERVICE else 1.0))
		if src.emission_texture:
			m.set_shader_parameter("emission_tex", src.emission_texture)
	if role == R_BODY:
		m.set_shader_parameter("rim", RIM)
		m.set_shader_parameter("value_k", CHAR_VALUE)
		m.set_shader_parameter("sat", CHAR_SAT)
		m.set_shader_parameter("shade_tint", CHAR_SHADE)
		m.set_shader_parameter("spec_k", 0.22)
		m.set_shader_parameter("shadow_k", 0.45)
		m.set_shader_parameter("tex_gamma", 0.78)
		m.set_shader_parameter("band", 0.2)
	else:
		# 월드 계약: 림 0 · 러프니스 0.5 (ToonOutline 이 0.42~0.58 을 월드로 분류 — 바꾸면 벽에 캐릭터 외곽선이 생긴다)
		m.set_shader_parameter("rim", 0.0)
		m.set_shader_parameter("out_rough", 0.5)
		m.set_shader_parameter("top_lift", 0.08)
		m.set_shader_parameter("tint", WORLD_TINT)
		match role:
			R_WALL:
				m.set_shader_parameter("top_lift", 0.0)
				m.set_shader_parameter("value_k", WALL_VALUE)
				m.set_shader_parameter("sat", FALLBACK_SAT)
				m.set_shader_parameter("role_mix", WALL_MIX)
				m.set_shader_parameter("role_top", WALL_TOP)
				m.set_shader_parameter("role_side", WALL_SIDE)
				m.set_shader_parameter("role_mean", WALL_MEAN)
				m.set_shader_parameter("role_top_k", WALL_TOP_K)
				m.set_shader_parameter("role_tint", Vector3(BG_COOL.r, BG_COOL.g, BG_COOL.b))
				BLUE_PAINT.configure(m, true)
			R_SERVICE:
				m.set_shader_parameter("value_k", SERVICE_VALUE)
				m.set_shader_parameter("sat", FALLBACK_SAT)
			_:
				m.set_shader_parameter("value_k", FALLBACK_VALUE if moco else WORLD_VALUE)
				m.set_shader_parameter("sat", FALLBACK_SAT if moco else WORLD_SAT)
		track_pool(m)
	m.render_priority = src.render_priority
	src.set_meta(key, m)
	return m


## 노드의 역할: 배경 키트 메타(claude_bg · claude_service)를 부모 쪽으로 찾는다. 없으면 맵 아래·큰 메시 = 월드, 그 밖 = 캐릭터
static func _role(node: Node3D) -> int:
	var n: Node = node
	var in_map := false
	for i in 8:
		if n == null:
			break
		if n.has_meta("claude_service"):
			return R_SERVICE
		if n.has_meta("claude_bg"):
			var k := str(n.get_meta("claude_bg"))
			if k in ["w01", "half", "jamb"] or k.begins_with("blocks_"):
				return R_WALL
		if n is ArenaMap:
			in_map = true
		n = n.get_parent()
	if in_map or node is MultiMeshInstance3D:
		return R_WORLD
	var mi := node as MeshInstance3D
	if mi:
		var bb: AABB = mi.get_aabb()
		if bb.size[bb.size.max_axis_index()] * mi.global_basis.get_scale().x > 4.5:
			return R_WORLD
	return R_BODY


## 메시 하나를 현재 상태(on)에 맞춘다
static func convert_one(mi: MeshInstance3D) -> void:
	if not is_instance_valid(mi) or mi.mesh == null:
		return
	var use := on and PaintedLook.game_preset == PaintedLook.NONE
	# 1) material_override
	var cur := mi.material_override
	if mi.has_meta("bl_orig") or cur != null:
		var orig: Material = mi.get_meta("bl_orig") if mi.has_meta("bl_orig") else cur
		var sm := orig as ShaderMaterial
		if sm and sm.shader == ClaudeBgDress.FLOOR_SHADER:
			mi.set_meta("bl_orig", orig)
			mi.material_override = _floor_for(sm) if use else orig
		elif convertible(orig):
			mi.set_meta("bl_orig", orig)
			mi.material_override = material_for(orig, _role(mi)) if use else orig
		return
	# 2) 표면 머티리얼 (GLB 모델·맵 벽): 표면 덮어쓰기로 바꾼다. 메시 자체는 건드리지 않는다
	var n := mi.mesh.get_surface_count()
	var saved: Array = mi.get_meta("bl_surf") if mi.has_meta("bl_surf") else []
	var role := -1
	for s in n:
		# saved[s]: 처음 바꿀 때의 원래 표면 덮어쓰기 (없었으면 false, 아직 안 봤으면 null)
		var orig_ov: Variant = saved[s] if s < saved.size() else null
		var src: Material
		if orig_ov == null:
			src = mi.get_surface_override_material(s)
			if src == null:
				src = mi.mesh.surface_get_material(s)
		else:
			src = orig_ov if orig_ov is Material else mi.mesh.surface_get_material(s)
		if not convertible(src):
			continue
		if saved.is_empty():
			saved.resize(n)
		if orig_ov == null:
			var ov := mi.get_surface_override_material(s)
			saved[s] = ov if ov != null else false
		if role < 0:
			role = _role(mi)
		var keep: Material = saved[s] if saved[s] is Material else null
		mi.set_surface_override_material(s, material_for(src, role) if use else keep)
	if not saved.is_empty():
		mi.set_meta("bl_surf", saved)


# ── 플레이어 조명 풀 ─────────────────────────────────────

static var _pool_mats := {}     # 재질 id → WeakRef (배경 재질만. 원본 메타에 붙은 유한한 재질이라 늘지 않고, 사라진 것은 지운다)


## 조명 풀을 받을 배경 재질 등록 (BrawlLook 배경 재질 · 설비 바닥)
static func track_pool(m: ShaderMaterial) -> void:
	_pool_mats[m.get_instance_id()] = weakref(m)
	m.set_shader_parameter("pool_use", 1.0)
	m.set_shader_parameter("pool_r0", POOL_R0)
	m.set_shader_parameter("pool_r1", POOL_R1)
	m.set_shader_parameter("pool_dark", POOL_DARK)


## 매 프레임: 플레이어 위치를 배경 재질에 넣는다. 룩이 꺼지거나 풀이 꺼져 있으면 0 (어둠 없음).
## 전역 셰이더 값 하나만 바꾼다 (재질 수와 무관). _pool_mats 는 어떤 재질이 풀을 쓰는지 기록·검사용으로만 남는다.
static var _pool_last := Vector4(INF, 0, 0, -1)


static func update_pool(pos: Vector3, on_now: bool) -> void:
	var v := Vector4(pos.x, pos.y, pos.z, 1.0 if on_now else 0.0)
	if v.is_equal_approx(_pool_last):
		return
	_pool_last = v
	RenderingServer.global_shader_parameter_set(&"bl_pool", v)


## 검사용: 마지막으로 셰이더에 넣은 (위치, 켜짐)
static func pool_state() -> Vector4:
	return _pool_last


static func _floor_for(src: ShaderMaterial) -> ShaderMaterial:
	var id := src.get_instance_id()
	if not _floor_mats.has(id):
		var m := ShaderMaterial.new()
		m.shader = _shader("floor")
		m.set_shader_parameter("albedo_tex", src.get_shader_parameter("albedo_tex"))
		var pr: Variant = src.get_shader_parameter("period")
		m.set_shader_parameter("period", pr if pr != null else 4.0)
		var off: Variant = src.get_shader_parameter("offset")      # ClaudeBgDress: 방마다 줄눈 위상
		m.set_shader_parameter("offset", off if off != null else Vector2.ZERO)
		m.set_shader_parameter("lift", WORLD_VALUE)
		m.set_shader_parameter("sat", WORLD_SAT)
		m.set_shader_parameter("warm", WORLD_TINT)
		if moco:
			# 새 기본색 바닥: WORLD 배율·채도·tint 를 다시 곱하지 않는다
			m.set_shader_parameter("use_base", true)
			m.set_shader_parameter("floor_base", FLOOR_BASE)
			m.set_shader_parameter("floor_value", FLOOR_VALUE)
			m.set_shader_parameter("floor_tint", Vector3(BG_COOL.r, BG_COOL.g, BG_COOL.b))
			m.set_shader_parameter("detail_strength", FLOOR_DETAIL)
			m.set_shader_parameter("detail_mean", FLOOR_DETAIL_MEAN)
		BLUE_PAINT.configure(m, false)
		if BLUE_PAINT.enabled:
			m.set_shader_parameter("lift", 0.82)
		track_pool(m)
		_floor_mats[id] = m
	return _floor_mats[id]


static func apply(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		convert_one(mi)
	for mmi in root.find_children("*", "MultiMeshInstance3D", true, false):
		convert_multi(mmi)


## MultiMesh (배경 블록 W01 · 설비 프랍 등 반복 배치): 메시가 표면 하나면 그 머티리얼을 덮어쓰기로 바꾼다. 메타로 벽/설비, 아니면 월드
static func convert_multi(mmi: MultiMeshInstance3D) -> void:
	if not is_instance_valid(mmi) or mmi.multimesh == null or mmi.multimesh.mesh == null:
		return
	if mmi.multimesh.mesh.get_surface_count() != 1:
		return
	var keep: Variant = mmi.get_meta("bl_orig") if mmi.has_meta("bl_orig") else mmi.material_override
	var orig: Material = keep if keep is Material else null
	var src: Material = orig if orig != null else mmi.multimesh.mesh.surface_get_material(0)
	if not convertible(src):
		return
	if not mmi.has_meta("bl_orig"):
		mmi.set_meta("bl_orig", orig if orig != null else false)
	mmi.material_override = material_for(src, _role(mmi)) if active() else orig


# ── 게임 연결 ───────────────────────────────────────────

## Main 이 씬마다 한 번 부른다 (PaintedLook.attach 다음)
static func attach(scene: Node, env: Environment, sun: DirectionalLight3D) -> void:
	_game = scene
	_env = env
	_sun = sun
	_orig = {}
	if env:
		_orig.env = {
			"bg": env.background_color, "amb": env.ambient_light_color, "amb_e": env.ambient_light_energy,
			"ssao": env.ssao_intensity, "ssao_r": env.ssao_radius, "adj": env.adjustment_enabled,
			"sat": env.adjustment_saturation, "con": env.adjustment_contrast, "bri": env.adjustment_brightness,
			"glow": env.glow_intensity,
		}
	if sun:
		_orig.sun = {"rot": sun.rotation_degrees, "c": sun.light_color, "e": sun.light_energy,
				"op": sun.shadow_opacity, "blur": sun.shadow_blur, "dist": sun.directional_shadow_max_distance}
	var w := Watcher.new()
	w.name = "BrawlLookWatcher"
	scene.add_child(w)
	_grade()


## 켜기/끄기. 켜면 PaintedLook 을 끈다. 바뀐 상태 이름을 돌려준다
static func toggle() -> String:
	set_on(not on)
	return "ON" if on else "OFF"


## instant: 카메라를 옮겨 가는 연출 없이 바로 (비교 캡처용)
static func set_on(v: bool, instant := false) -> void:
	on = v
	if on and PaintedLook.game_preset != PaintedLook.NONE:
		PaintedLook.toggle()
	refresh(instant)


## 상태를 다시 적용 (PaintedLook 이 켜지고 꺼질 때도 부른다)
static func refresh(instant := false) -> void:
	if not is_instance_valid(_game):
		return
	_grade()
	apply(_game)
	_camera(instant)
	for b in _game.get_tree().get_nodes_in_group("brawl_blob"):
		(b as Node3D).visible = active()


## Main.dramatic(false) 가 되돌아올 조명값. 이 씬에 브롤 룩이 걸려 있으면 브롤 값, 아니면 null (씬 기본값을 쓴다)
static func base_light(scene: Node) -> Variant:
	if not active() or _game != scene:
		return null
	return {"sun_e": SUN_ENERGY, "amb_e": AMBIENT_ENERGY, "bg": BG, "glow": _glow(), "glow_thr": 1.1}


## 평상시 glow 세기 (mo.co 무드는 넓은 빛 번짐을 줄인다). 레이저 암전에서 돌아올 값과 _grade 가 같은 값을 쓴다
static func _glow() -> float:
	return 0.25 if moco else 0.4


static func active() -> bool:
	return on and PaintedLook.game_preset == PaintedLook.NONE


static func _grade() -> void:
	var a := active()
	if _env and _orig.has("env"):
		var o: Dictionary = _orig.env
		_env.background_color = BG if a else o.bg
		_env.ambient_light_color = AMBIENT if a else o.amb
		_env.ambient_light_energy = AMBIENT_ENERGY if a else o.amb_e
		_env.ssao_intensity = (0.45 if moco else 0.7) if a else o.ssao   # 벽 옆에 붙는 진한 AO 를 줄인다
		_env.ssao_radius = 0.7 if a else o.ssao_r
		_env.adjustment_enabled = true if a else o.adj
		_env.adjustment_saturation = 1.0 if a else o.sat   # 화면 전체가 아니라 캐릭터 머티리얼(CHAR_SAT)에서 채도를 올린다
		_env.adjustment_contrast = 1.03 if a else o.con
		_env.adjustment_brightness = 1.02 if a else o.bri
		_env.glow_intensity = _glow() if a else o.glow
	if _sun and _orig.has("sun"):
		var s: Dictionary = _orig.sun
		_sun.rotation_degrees = SUN_ROT if a else s.rot
		_sun.light_color = SUN_COLOR if a else s.c
		_sun.light_energy = SUN_ENERGY if a else s.e
		_sun.shadow_opacity = (SHADOW_OPACITY if moco else 0.62) if a else s.op
		_sun.shadow_blur = 2.2 if a else s.blur
		# 망원 카메라는 멀리 있어서 그림자 거리도 늘린다
		_sun.directional_shadow_max_distance = 70.0 if a else s.dist


## 외곽선 규칙. 카메라 시야는 모든 씬이 TACTICAL 로 통일돼 브롤 룩도 바꾸지 않는다 (CameraRig.set_preset 참고).
static func _camera(_instant: bool) -> void:
	if is_instance_valid(ToonOutline.inst):
		ToonOutline.inst.set_brawl(active())


## 캐릭터 발밑 그림자 (적은 붉은 팀 원)
static func add_blob(body: Node3D, radius: float, ring := Color(0, 0, 0, 0)) -> void:
	if body.has_node("BrawlBlob"):
		return
	var b := Blob.new()
	b.name = "BrawlBlob"
	var q := QuadMesh.new()
	q.size = Vector2.ONE * radius * 2.6
	q.orientation = PlaneMesh.FACE_Y
	b.mesh = q
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.material_override = _blob_mat()
	b.ring = ring
	b.set_instance_shader_parameter("ring_col", ring)
	b.top_level = true
	b.add_to_group("brawl_blob")
	body.add_child(b)


static var _blob_m: ShaderMaterial


static func _blob_mat() -> ShaderMaterial:
	if _blob_m == null:
		_blob_m = ShaderMaterial.new()
		_blob_m.shader = _shader("blob")
		_blob_m.render_priority = -10
	return _blob_m


class Blob extends MeshInstance3D:
	var ring := Color(0, 0, 0, 0)
	var _k := 1.0

	func _process(_dt: float) -> void:
		var p := get_parent() as Node3D
		if p == null:
			return
		visible = BrawlLook.active() and p.visible
		var g := p.global_position
		g.y = Main.gy(g) + 0.035
		global_position = g
		# 강력 레이저 어둠 연출(해가 꺼짐) 동안은 팀 원도 함께 어두워진다 (빔 광원이 돋보이게)
		var k := 1.0
		if is_instance_valid(BrawlLook._sun):
			k = clampf(BrawlLook._sun.light_energy / BrawlLook.SUN_ENERGY, 0.3, 1.0)
		if ring.a > 0.0 and absf(k - _k) > 0.02:
			_k = k
			set_instance_shader_parameter("ring_col", Color(ring.r * k, ring.g * k, ring.b * k, ring.a * lerpf(0.5, 1.0, k)))


## 씬에 새로 들어오는 메시·캐릭터를 현재 상태로 맞춘다
class Watcher extends Node:
	func _enter_tree() -> void:
		get_tree().node_added.connect(_on_added)

	func _ready() -> void:
		# 카메라·맵·플레이어가 다 만들어진 뒤 한 번 더
		_late_all.call_deferred()

	func _late_all() -> void:
		if is_instance_valid(BrawlLook._game):
			BrawlLook._camera(true)
		BrawlLook.refresh()
		for n in get_tree().get_nodes_in_group("enemies"):
			_dress(n)
		var g := BrawlLook._game
		if g and g.get("player") is Player:
			BrawlLook.add_blob(g.get("player"), 0.5)

	func _process(_dt: float) -> void:
		var g := BrawlLook._game
		var p: Variant = g.get("player") if is_instance_valid(g) else null
		if p is Node3D and is_instance_valid(p):
			BrawlLook.update_pool((p as Node3D).global_position, BrawlLook.pool and BrawlLook.active())

	func _exit_tree() -> void:
		BrawlLook.update_pool(Vector3.ZERO, false)     # 다른 씬(보스전 등)으로 어둠이 새지 않게
		if get_tree().node_added.is_connected(_on_added):
			get_tree().node_added.disconnect(_on_added)

	func _on_added(n: Node) -> void:
		if n is MultiMeshInstance3D:
			if BrawlLook.on:
				_late_multi.call_deferred(n)
		elif n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.material_override == Pal.flat() or n is Blob:
				return
			# 이펙트(총구 · 착탄 · 잔상 · 파편 …)는 초당 수백 개씩 생기는데 대부분 셰이더·투명 재질이라 바꿀 것이 없다.
			# convert_one 이 그대로 돌려보낼 노드는 지연 호출을 아예 만들지 않는다
			var ov := mi.material_override
			if ov != null and not mi.has_meta("bl_orig") and not BrawlLook.convertible(ov):
				var sm := ov as ShaderMaterial
				if sm == null or sm.shader != ClaudeBgDress.FLOOR_SHADER:
					return
			if BrawlLook.on:
				_late.call_deferred(n)
		elif n is Enemy:
			_dress.call_deferred(n)

	# 지연 호출 사이에 지워진 노드가 올 수 있어 인자는 타입 없이 받고 먼저 유효성을 본다 (타입을 걸면 변환 오류가 난다)
	func _late_multi(n) -> void:
		if is_instance_valid(n) and (n as Node).is_inside_tree():
			BrawlLook.convert_multi(n)

	func _late(n) -> void:
		if is_instance_valid(n) and (n as Node).is_inside_tree():
			BrawlLook.convert_one(n)

	func _dress(n) -> void:
		if not is_instance_valid(n):
			return
		var e := n as Enemy
		if e == null or not e.is_inside_tree():
			return
		if e.get("prop"):
			BrawlLook.add_blob(e, e.radius)
		else:
			BrawlLook.add_blob(e, e.radius, Color(1.0, 0.24, 0.3, 0.75))
