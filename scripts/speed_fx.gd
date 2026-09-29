extends CanvasLayer
## 추격 보스전 화면 속도감 (연출 전용).
## 소실점(진행 방향)으로 모이는 방사형 모션 블러 + 가장자리에서 깜빡이는 집중선 + 약한 색수차.

var rect: ColorRect
var mat: ShaderMaterial
var intensity := 1.0
var target_intensity := 1.0
var focus := Vector2(0.5, 0.1)

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float intensity = 1.0;
uniform vec2 focus = vec2(0.5, 0.1);
uniform float aspect = 1.6;
float hash(float n) { return fract(sin(n * 127.1) * 43758.5453); }
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - focus;
	vec2 da = vec2(d.x * aspect, d.y);
	float r = length(da);
	// 화면 가장자리만 번지게 한다 (가운데 전투 영역은 선명하게)
	vec2 cv = (uv - vec2(0.5, 0.52)) * vec2(1.0, 1.3);
	float ce = length(cv);
	float edge = smoothstep(0.34, 0.75, ce);
	float amt = 0.055 * intensity * edge;
	vec3 acc = vec3(0.0);
	float wsum = 0.0;
	for (int i = 0; i < 10; i++) {
		float k = float(i) / 9.0;
		float w = 1.0 - k * 0.6;
		vec2 suv = uv - d * amt * k;
		acc += texture(screen_tex, suv).rgb * w;
		wsum += w;
	}
	vec3 col = acc / wsum;
	// 색수차: 가장자리에서 R·B 를 반대로 밀어낸다
	float ca = 0.004 * intensity * edge;
	col.r = mix(col.r, texture(screen_tex, uv + d * ca).r, 0.6);
	col.b = mix(col.b, texture(screen_tex, uv - d * ca).b, 0.6);
	// 집중선: 각도 칸마다 무작위로 켜지고, 1/15초마다 바뀐다
	float ang = atan(da.y, da.x);
	float cells = 150.0;
	float ci = floor((ang + 3.14159) / 6.28318 * cells);
	float frame = floor(TIME * 15.0);
	float on = step(0.8, hash(ci * 7.13 + frame * 3.1));
	float within = abs(fract((ang + 3.14159) / 6.28318 * cells) - 0.5);
	float thin = smoothstep(0.5, 0.15, within);
	float start = 0.45 + hash(ci + frame) * 0.35;
	float line = on * thin * smoothstep(start, start + 0.35, r) * smoothstep(0.3, 0.6, ce);
	col += vec3(0.85, 0.95, 1.0) * line * 0.22 * intensity;
	// 가장자리를 살짝 어둡게 해 앞쪽에 시선을 모은다
	col *= 1.0 - smoothstep(0.45, 0.85, ce) * 0.3 * intensity;
	COLOR = vec4(col, 1.0);
}
"""


func _ready() -> void:
	layer = 5
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	rect.material = mat
	add_child(rect)


## 진행 방향의 월드 지점을 화면에 투영해 소실점으로 쓴다
func track(cam: Camera3D, world_point: Vector3) -> void:
	var vs := get_viewport().get_visible_rect().size
	if cam.is_position_behind(world_point):
		return
	var sp := cam.unproject_position(world_point) / vs
	focus = focus.lerp(sp, 0.2)


func _process(dt: float) -> void:
	intensity = lerpf(intensity, target_intensity, 1.0 - exp(-4.0 * dt))
	var vs := get_viewport().get_visible_rect().size
	mat.set_shader_parameter("intensity", intensity)
	mat.set_shader_parameter("focus", focus)
	mat.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
	rect.visible = intensity > 0.02
