class_name ToonOutline
extends MeshInstance3D
## 카툰 렌더링 외곽선: 카메라 앞에 화면 전체 사각형을 깔고 깊이·노멀 버퍼에서 경계를 찾아 진한 선을 그린다.
## - 깊이 차가 크면 실루엣, 노멀이 꺾이면 로우폴리 파츠의 모서리로 보고 선을 긋는다
## - 선 두께는 화면 높이 800px 기준 픽셀이며 해상도에 맞춰 늘어난다
## - 러프니스 0 으로 그린 파츠(Pal.flat 발광 단색: 예광탄·속도선 등)는 선을 긋지 않는다
## - 투명 패스에서 가장 먼저 그려서(render_priority -128) 빔·폭발 같은 반투명 이펙트는 선 위에 덮인다
## Pal.set_toon() 으로 셀 음영과 함께 켜고 끈다(O 키). 판정과 무관.

static var inst: ToonOutline

const SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;
uniform vec4 line_color : source_color = vec4(0.035, 0.025, 0.07, 1.0);
uniform float thickness = 1.6;
uniform float depth_threshold = 0.045;
uniform float normal_threshold = 0.55;
uniform float max_distance = 120.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float lin_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

vec3 view_normal(vec2 uv) {
	return normalize(texture(normal_tex, uv).xyz * 2.0 - 1.0);
}

uniform float brawl = 0.0;   // 1: BrawlLook 규칙 — 캐릭터 실루엣만, 월드(러프니스 0.5) 끼리는 긋지 않고 꺾임선 없음

float rough_at(vec2 uv) {
	float r = texture(normal_tex, uv).w;
	if (r > 0.5) r = 1.0 - r;
	return r / (127.0 / 255.0);
}

// 러프니스가 0 이면 외곽선 제외 표식. 동적 물체는 w 가 1 - r 로 뒤집혀 저장된다.
float outlined(vec2 uv) {
	return step(0.02, rough_at(uv));
}

// 분류: 0 제외(발광 단색) · 1 월드 · 2 캐릭터
float cls(vec2 uv) {
	float r = rough_at(uv);
	if (r < 0.02) return 0.0;
	return (r > 0.42 && r < 0.58) ? 1.0 : 2.0;
}

void fragment() {
	vec2 px = thickness * (VIEWPORT_SIZE.y / 800.0) / VIEWPORT_SIZE;
	vec2 uv = SCREEN_UV;
	float dc = lin_depth(uv, INV_PROJECTION_MATRIX);
	vec3 nc = view_normal(uv);
	vec2 offs[4] = { vec2(px.x, 0.0), vec2(-px.x, 0.0), vec2(0.0, px.y), vec2(0.0, -px.y) };
	float edge = 0.0;
	float near_d = dc;
	float keep_c = outlined(uv);
	float cls_c = cls(uv);
	for (int i = 0; i < 4; i++) {
		vec2 u = uv + offs[i];
		float d = lin_depth(u, INV_PROJECTION_MATRIX);
		float keep = keep_c * outlined(u);
		if (brawl > 0.5) {
			float cn = cls(u);
			// 둘 다 그릴 대상이고 적어도 한쪽이 캐릭터일 때만
			keep = step(0.5, cls_c) * step(0.5, cn) * step(1.5, max(cls_c, cn));
		}
		near_d = min(near_d, mix(1e6, d, keep));
		// 가까운 쪽 기준 상대 깊이 차 → 실루엣
		float e = step(depth_threshold, abs(d - dc) / max(min(d, dc), 0.01));
		// 같은 면 위라면 노멀이 거의 같다 → 꺾이면 모서리
		e = max(e, step(dot(nc, view_normal(u)), normal_threshold) * step(abs(d - dc) / max(dc, 0.01), 0.5) * (1.0 - brawl));
		edge = max(edge, e * keep);
	}
	// 배경(원거리)만 있는 곳은 긋지 않는다
	edge *= step(near_d, max_distance);
	ALBEDO = line_color.rgb;
	ALPHA = edge * line_color.a;
}
"""

var mat: ShaderMaterial
var brawl_on := false   # BrawlLook 규칙으로 그리는 중 (켜져 있으면 O 키로 셀 음영을 꺼도 외곽선은 남는다)


## 카메라에 외곽선 후처리를 붙인다
static func attach(cam: Camera3D) -> ToonOutline:
	var o := ToonOutline.new()
	cam.add_child(o)
	return o


func _exit_tree() -> void:
	if inst == self:
		inst = null


func _ready() -> void:
	inst = self
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	q.flip_faces = true
	mesh = q
	var sh := Shader.new()
	sh.code = SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	mat.render_priority = Material.RENDER_PRIORITY_MIN
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 화면 전체를 덮으므로 절두체 컬링에 걸리지 않게 한다
	extra_cull_margin = 16384.0
	position = Vector3(0, 0, -1)
	visible = Pal.toon_on
	# 브롤 룩 규칙은 그 룩이 걸린 씬에서만 BrawlLook 이 켠다 (보스전 등 다른 씬 카메라는 그대로)


## BrawlLook: 캐릭터 실루엣만 얇고 짙게. 끄면 원래 카툰 외곽선 값으로 (보임 여부는 Pal.toon_on)
func set_brawl(v: bool) -> void:
	if mat == null:
		return
	brawl_on = v
	mat.set_shader_parameter("brawl", 1.0 if v else 0.0)
	mat.set_shader_parameter("line_color", BrawlLook.LINE_COLOR if v else Color(0.035, 0.025, 0.07, 1.0))
	mat.set_shader_parameter("thickness", 1.25 if v else 1.6)
	mat.set_shader_parameter("depth_threshold", 0.02 if v else 0.045)
	visible = v or Pal.toon_on

