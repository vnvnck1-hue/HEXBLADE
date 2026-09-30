class_name LaserWarning
extends Node3D
## 적 차지 레이저 예고 (연출 전용, 판정 없음).
## 바닥에 붉은 띠로 공격 범위를 그리고, 충전이 차오를수록 띠가 포구에서 끝까지 채워지며 빨라지게 깜빡인다.

static var _mat: ShaderMaterial
static var _quad: QuadMesh
static var _line: BoxMesh

var strip: MeshInstance3D
var sight: MeshInstance3D


func _ready() -> void:
	if _mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, blend_add;
instance uniform float progress = 0.0;
instance uniform float blen = 10.0;
instance uniform float wid = 1.0;
varying vec2 lp;
void vertex() { lp = VERTEX.xz; }
void fragment() {
	float across = abs(lp.x) * 2.0;           // 0 중앙 → 1 가장자리
	float along = 0.5 - lp.y;                 // 0 포구 → 1 끝
	float dist = along * blen;
	float p = clamp(progress, 0.0, 1.0);
	float edge = step(1.0 - 0.14 / wid, across);
	float filled = step(along, smoothstep(0.0, 0.8, p));
	// 포구에서 끝으로 흘러가는 화살표 무늬
	float chev = step(fract(dist * 0.7 - across * 0.35 - TIME * 3.5), 0.16) * (1.0 - edge);
	float blink = mix(1.0, 0.45 + 0.55 * step(0.5, fract(TIME * mix(4.0, 16.0, p))), step(0.55, p));
	float lock = step(0.8, p);
	float i = 0.1 + 0.2 * p;
	i += filled * (0.22 + 0.3 * p);
	i += chev * (0.25 + 0.35 * p);
	i += edge * (0.9 + 1.1 * p);
	i += lock * 0.5;
	i *= blink;
	i *= 1.0 - smoothstep(0.93, 1.0, along) * 0.6;
	ALBEDO = vec3(1.0, 0.07, 0.12) * i;
}
"""
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_quad = QuadMesh.new()
		_quad.orientation = PlaneMesh.FACE_Y
		_line = BoxMesh.new()
	strip = MeshInstance3D.new()
	strip.mesh = _quad
	strip.material_override = _mat
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(strip)
	# 포구 높이의 가는 조준선
	sight = Pal.flat_mesh(_line, Pal.E_RED, 1.6)
	add_child(sight)


## origin·dir 은 수평 기준, length 는 벽까지의 거리
func set_pose(origin: Vector3, dir: Vector3, length: float, width: float, beam_y := 0.95) -> void:
	var d := Vector3(dir.x, 0, dir.z).normalized()
	global_position = Vector3(origin.x, Main.gy(origin) + 0.035, origin.z)
	global_basis = Basis.looking_at(d, Vector3.UP)
	strip.scale = Vector3(width, 1, length)
	strip.position = Vector3(0, 0, -length * 0.5)
	strip.set_instance_shader_parameter("blen", length)
	strip.set_instance_shader_parameter("wid", width)
	sight.position = Vector3(0, beam_y - 0.035, -length * 0.5)


func set_progress(k: float) -> void:
	strip.set_instance_shader_parameter("progress", k)
	# 조준선은 점점 굵고 밝아지고, 발사 직전에는 깜빡인다
	var th := lerpf(0.015, 0.05, k)
	sight.scale = Vector3(th, th, strip.scale.z)
	var on := k < 0.8 or fmod(Time.get_ticks_msec() / 1000.0, 0.08) < 0.04
	sight.set_instance_shader_parameter("energy", lerpf(0.8, 2.6, k) if on else 0.4)
