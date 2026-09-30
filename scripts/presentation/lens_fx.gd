extends CanvasLayer
## 연출 전용: 광각 렌즈 느낌의 배럴 왜곡 + 가장자리 색수차 · 비네트.
## 3D 화면(반투명 이펙트·글로우 포함)만 휘고, 그 위 층(임팩트 프레임 9 · HUD 10 · 보스 바 11)은 그대로 둔다.
## 세기는 카메라(CameraRig.lens_k)가 정하고, 화면 좌표 변환도 CameraRig 가 같은 식으로 맞춘다.

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float k = 0.0;
uniform float aspect = 1.7778;
uniform float ca = 0.0;
uniform float vig = 0.0;
void fragment() {
	vec2 q = (SCREEN_UV - 0.5) * vec2(aspect, 1.0);
	float r2 = dot(q, q);
	float rm2 = aspect * aspect * 0.25 + 0.25;
	// 가운데는 부풀고 가장자리는 눌린다. 화면 모서리는 모서리 그대로 (검은 테두리 없음)
	vec2 src = q * (1.0 + k * r2) / (1.0 + k * rm2);
	vec2 uv = src / vec2(aspect, 1.0) + 0.5;
	vec2 dir = uv - 0.5;
	float e = ca * r2 / rm2;
	vec3 col;
	col.r = texture(screen_tex, uv + dir * e).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - dir * e).b;
	col *= 1.0 - vig * smoothstep(0.25, 1.0, r2 / rm2);
	COLOR = vec4(col, 1.0);
}
"""

var cam: CameraRig
var _rect: ColorRect
var _mat: ShaderMaterial


func _ready() -> void:
	layer = 5
	_mat = ShaderMaterial.new()
	_mat.shader = Shader.new()
	_mat.shader.code = SHADER
	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


func _process(_dt: float) -> void:
	var k := cam.lens_k if is_instance_valid(cam) else 0.0
	visible = k > 0.001
	if not visible:
		return
	var vs := get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("k", k)
	_mat.set_shader_parameter("aspect", vs.x / maxf(1.0, vs.y))
	_mat.set_shader_parameter("ca", k * 0.05)
	_mat.set_shader_parameter("vig", minf(0.35, k * 2.2))
