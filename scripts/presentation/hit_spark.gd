class_name HitSpark
extends RefCounted
## 적 피격 섬광 (연출 전용). 카툰풍 3프레임 스프라이트 시트를 카메라를 향한 판에 한 장씩 끊어 넘긴다.
##  1프레임  임팩트: 흰 심지 네 갈래 별 + 긴 대각 줄기 + 두꺼운 노란 초승달
##  2프레임  확산: 줄기가 길고 가늘어지고, 고리가 커지며 가시가 돋고 파편이 튄다
##  3프레임  소멸: 끊어진 고리 조각 · 줄기 끝 조각 · 흩어진 파편
## 외곽선 없이 평면 채색 + 같은 색 번짐으로 그려 게임의 다른 연출과 결을 맞춘다. 다른 물체에 가려지지 않게 맨 위에 그린다.
## 시트는 tools/make_hit_spark_sheet.py 로 만든다.

const SHEET := preload("res://assets/fx/hit_spark_sheet.png")
const FRAMES := 3
## 각 프레임을 보여 줄 게임 시간 (60fps 기준 3 · 2 · 2 프레임). 임팩트 프레임을 가장 길게 잡는다.
const HOLD: Array[float] = [0.05, 0.034, 0.034]
const BASE_ANG := -0.61         # 시트 속 긴 줄기의 방향 (-35°, 화면 오른쪽 위)
const SIZE := 2.0               # 총알 한 발 기준 판 한 변 (m)
const MIN_GAP := 0.045          # 같은 적이 연사로 맞을 때 이보다 촘촘하게는 새로 띄우지 않는다

static var _mat: ShaderMaterial
static var _quad: QuadMesh
static var _last := {}


static func _setup() -> void:
	if _mat != null:
		return
	_quad = QuadMesh.new()
	var sh := Shader.new()
	sh.code = SHADER % FX.BILLBOARD
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("sheet", SHEET)
	_mat.set_shader_parameter("frames", float(FRAMES))
	_mat.set_shader_parameter("base_ang", BASE_ANG)
	_mat.render_priority = 9


## pos: 맞은 지점 · dir: 맞은 방향(월드) · k: 세기 (총알 1, 검·강공격일수록 크게) · key: 연사 간격 판정용
static func spawn(pos: Vector3, dir: Vector3, k := 1.0, key: Object = null) -> void:
	if FX.root == null or not is_instance_valid(FX.root) or not FX.root.is_inside_tree():
		return
	_setup()
	if key != null:
		var now := Time.get_ticks_msec() * 0.001
		var id := key.get_instance_id()
		if now - float(_last.get(id, -1.0)) < MIN_GAP:
			return
		_last[id] = now
		if _last.size() > 64:
			_last.clear()
	# 긴 줄기를 맞은 방향(화면에 투영한 기울기)으로 돌린다
	var cam := FX.root.get_viewport().get_camera_3d()
	var ang := BASE_ANG + randf_range(-0.4, 0.4)
	var at := pos
	if cam:
		at = pos + (cam.global_position - pos).normalized() * 0.6   # 기체 앞쪽에 띄운다
		var d := Vector3(dir.x, 0, dir.z)
		if d.length() > 0.01:
			var sd := cam.global_basis.inverse() * d.normalized()
			if Vector2(sd.x, sd.y).length() > 0.2:
				ang = atan2(-sd.y, sd.x)   # 판의 UV 는 y 가 아래쪽
		ang += randf_range(-0.2, 0.2)
	var mi := _Player.new()
	mi.mesh = _quad
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("frame", 0.0)
	mi.set_instance_shader_parameter("rot", ang - BASE_ANG)
	mi.set_instance_shader_parameter("flip", 1.0 if randf() < 0.5 else -1.0)
	FX.root.add_child(mi)
	mi.global_position = at
	mi.scale = Vector3.ONE * SIZE * sqrt(k)


## 시트 재생: 한 장씩 끊어 넘기되 렌더 프레임마다 최대 한 장만 넘긴다 (프레임이 떨어져도 세 장이 모두 보인다).
## 게임 시간으로 흐르므로 히트스탑 동안에는 임팩트 프레임에 멈춰 있다.
class _Player extends MeshInstance3D:
	var i := 0
	var t := 0.0
	var _drawn := false

	func _process(dt: float) -> void:
		# 생긴 프레임에는 넘기지 않는다 (임팩트 프레임이 최소 한 번은 그려지도록)
		if not _drawn:
			_drawn = true
			return
		t += dt
		if t < HOLD[i]:
			return
		t = 0.0
		i += 1
		if i >= FRAMES:
			queue_free()
			return
		set_instance_shader_parameter("frame", float(i))


const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, shadows_disabled, depth_draw_never, depth_test_disabled;
uniform sampler2D sheet : source_color, filter_linear, repeat_disable;
uniform float frames = 3.0;
uniform float base_ang = 0.0;
instance uniform float frame = 0.0;
instance uniform float rot = 0.0;
instance uniform float flip = 1.0;
void vertex() {
%s
}
vec2 rotate(vec2 p, float a) {
	float c = cos(a), s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}
void fragment() {
	// 판 좌표 → 시트 칸 좌표: rot 만큼 돌려 긴 줄기를 맞은 방향에 맞추고, 줄기 축을 기준으로 가끔 뒤집는다
	vec2 p = UV - 0.5;
	p = rotate(p, -rot);
	p = rotate(p, -base_ang);
	p.y *= flip;
	p = rotate(p, base_ang);
	vec2 uv = p + 0.5;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) discard;
	vec4 c = texture(sheet, vec2((floor(frame + 0.5) + uv.x) / frames, uv.y));
	if (c.a < 0.01) discard;
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
"""
