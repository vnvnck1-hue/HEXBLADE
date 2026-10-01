extends CanvasLayer
## 심연 성소 화면 후처리 (HUD 아래 층): 90년대 아케이드풍 저해상 질감.
## 가장자리 색수차 · 짙은 비네트 · 필름 그레인 · 아주 옅은 주사선 · 그림자는 진홍, 밝은 곳은 청록으로 가르는 분할 톤.
## 피격·파열 때 kick() 으로 색수차와 붉은 맥동을 잠깐 키운다. P 키로 끈다.

var rect: ColorRect
var mat: ShaderMaterial
var pulse := 0.0
var on := true

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float pulse = 0.0;
uniform float strength = 1.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	// 색수차: 가장자리로 갈수록 R/B 가 벌어진다
	float ca = (0.0018 + r2 * 0.012 + pulse * 0.008) * strength;
	vec3 col;
	col.r = texture(screen_tex, uv + c * ca).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - c * ca).b;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	// 분할 톤: 어두운 곳은 진홍, 밝은 곳은 차가운 청록 쪽으로 아주 살짝
	vec3 shadow_t = vec3(0.12, 0.0, 0.03);
	vec3 high_t = vec3(-0.02, 0.02, 0.04);
	col += mix(shadow_t, high_t, smoothstep(0.05, 0.6, lum)) * 0.35 * strength;
	// 비네트
	float vig = smoothstep(0.85, 0.18, r2 * 2.2);
	col *= mix(1.0, vig, 0.72 * strength);
	col += vec3(0.6, 0.0, 0.05) * pulse * smoothstep(0.1, 0.6, r2 * 2.0) * 0.4;
	// 그레인 · 주사선
	float g = h(uv * vec2(1920.0, 1080.0) + fract(TIME * 7.3) * 113.0) - 0.5;
	col += g * 0.035 * strength;
	col *= 1.0 - 0.035 * strength * step(0.5, fract(FRAGCOORD.y * 0.5));
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
"""


func _ready() -> void:
	layer = 4
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	rect.material = mat
	add_child(rect)
	on = not OS.get_cmdline_user_args().has("--nopost")
	rect.visible = on


func kick(k: float) -> void:
	pulse = maxf(pulse, k)


func toggle() -> bool:
	on = not on
	rect.visible = on
	return on


func _process(dt: float) -> void:
	var rdt := dt / maxf(Engine.time_scale, 0.01)
	pulse = move_toward(pulse, 0.0, rdt * 2.2)
	mat.set_shader_parameter("pulse", pulse)
