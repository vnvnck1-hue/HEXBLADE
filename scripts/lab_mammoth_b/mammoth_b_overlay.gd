extends CanvasLayer
## B안 화면 후처리: 레터박스 · 충격 지점으로 모이는 방사형 블러 · 색수차 · 섬광 · 비네트.
## 값은 연출 감독(director)이 매 프레임 넣고, 이 노드는 그리기만 한다. 판정과 무관.

var rect: ColorRect
var mat: ShaderMaterial
var bars := 0.0            # 0~1 레터박스
var blur := 0.0            # 방사형 블러 강도
var aberr := 0.0           # 색수차 강도
var vignette := 0.0
var flash := Color(1, 1, 1, 0)
var center := Vector2(0.5, 0.5)

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float bars = 0.0;
uniform float blur = 0.0;
uniform float aberr = 0.0;
uniform float vignette = 0.0;
uniform vec4 flash = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec2 center = vec2(0.5);
uniform float aspect = 1.6;
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - center;
	float r = length(vec2(d.x * aspect, d.y));
	vec3 col = vec3(0.0);
	float wsum = 0.0;
	// 충격 지점에서 멀수록 크게 번지는 줌 블러
	float amt = blur * 0.09 * smoothstep(0.03, 0.6, r);
	for (int i = 0; i < 12; i++) {
		float k = float(i) / 11.0;
		float w = 1.0 - k * 0.7;
		col += texture(screen_tex, uv - d * amt * k).rgb * w;
		wsum += w;
	}
	col /= wsum;
	float ca = aberr * 0.012 * smoothstep(0.0, 0.7, r);
	col.r = mix(col.r, texture(screen_tex, uv + d * ca).r, 0.8);
	col.b = mix(col.b, texture(screen_tex, uv - d * ca).b, 0.8);
	col *= 1.0 - smoothstep(0.35, 0.95, r) * vignette;
	col = mix(col, flash.rgb, flash.a);
	float h = 0.105 * bars;
	float edge = step(uv.y, h) + step(1.0 - h, uv.y);
	col = mix(col, vec3(0.0), clamp(edge, 0.0, 1.0));
	COLOR = vec4(col, 1.0);
}
"""


func _ready() -> void:
	layer = 12
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	rect.material = mat
	add_child(rect)
	rect.visible = false


## 화면 좌표(0~1)로 충격 중심을 맞춘다
func aim(cam: Camera3D, world: Vector3) -> void:
	if cam == null or cam.is_position_behind(world):
		return
	var vs := get_viewport().get_visible_rect().size
	center = cam.unproject_position(world) / vs


func _process(_dt: float) -> void:
	var on := bars > 0.001 or blur > 0.001 or aberr > 0.001 or flash.a > 0.001 or vignette > 0.001
	rect.visible = on
	if not on:
		return
	var vs := get_viewport().get_visible_rect().size
	mat.set_shader_parameter("bars", bars)
	mat.set_shader_parameter("blur", blur)
	mat.set_shader_parameter("aberr", aberr)
	mat.set_shader_parameter("vignette", vignette)
	mat.set_shader_parameter("flash", flash)
	mat.set_shader_parameter("center", center)
	mat.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
