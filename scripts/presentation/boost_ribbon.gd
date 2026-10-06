class_name BoostRibbon
extends MeshInstance3D
## 부스터 연기 꼬리 (연출 전용, 판정 없음). 분사구마다 하나씩, 불꽃이 나오는 자리(분사구 원점)에 머리가 붙은 회색 연기 띠.
## 지나간 분사구 위치를 기록해 카메라를 보는 띠(ImmediateMesh)로 잇고, 셰이더가 모양을 정한다:
##  UV.x = 나이 0(분사구) ~ 1(꼬리 끝), UV.y = 띠를 가로지름, UV2.x = 띠를 따라 쌓인 거리 (연기 결 노이즈가 띠에 붙어 미끄러지지 않게).
##  머리가 가장 두껍고 꼬리로 갈수록 가늘어지며, 가장자리는 부드럽고 끝으로 갈수록 투명도가 서서히 0 으로.
## 시계는 게임 시간(time_scale)을 따른다. 흐르는 씬(WorldFlow)에서는 남은 띠가 도로를 따라 흘러간다.

const SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;
uniform vec3 light : source_color = vec3(0.86, 0.86, 0.9);
uniform vec3 mid : source_color = vec3(0.66, 0.66, 0.72);
uniform vec3 dark : source_color = vec3(0.44, 0.44, 0.52);
uniform float opacity = 0.95;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float age = clamp(UV.x, 0.0, 1.0);
	float body = 1.0 - abs(UV.y * 2.0 - 1.0);     // 0 가장자리 · 1 가운데
	float dist = UV2.x;
	// 띠를 따라 늘어난 결 → 연기 결이 길게 흐른다 (노이즈는 띠에 붙어 미끄러지지 않음)
	float n = vnoise(vec2(dist * 2.4, UV.y * 5.0)) * 0.6 + vnoise(vec2(dist * 6.0, UV.y * 11.0)) * 0.4;
	// 가장자리는 부드럽게, 결 노이즈로 살짝 일렁임
	float edge = smoothstep(0.0, 0.3, body + (n - 0.5) * 0.45 * (0.4 + age));
	// 끝으로 갈수록 부드럽게 사라짐
	float fade = pow(1.0 - age, 1.3);
	vec3 col = mix(dark, mid, smoothstep(0.05, 0.5, body));
	col = mix(col, light, smoothstep(0.45, 0.95, body) * (0.6 + 0.4 * n));
	ALBEDO = col;
	ALPHA = clamp(edge * fade * opacity, 0.0, 1.0);
}
"""

const LIFE := 0.26         ## 한 점이 꼬리 끝까지 가는 시간 (게임 초) — 짧은 꼬리
const GAP := 0.05          ## 이만큼 움직일 때마다 점 하나
const WIDTH := 0.66        ## 머리(분사구) 폭 (m). 꼬리로 갈수록 가늘어진다
const MAX_PTS := 64

static var _mat: ShaderMaterial

## 켜져 있는 동안만 새 점을 잇는다. 꺼도 남은 띠는 늙어 사라진다
var emitting := false
var source: Callable        ## 리본 머리 월드 위치를 돌려준다
var _pts: Array = []        ## [위치, 나이, 쌓인 거리, 물결 위상]
var _dist := 0.0
var _im: ImmediateMesh
var _phase := randf() * TAU


static func material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
	return _mat


static func make(head: Callable) -> BoostRibbon:
	var r := BoostRibbon.new()
	r.source = head
	return r


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_im = ImmediateMesh.new()
	mesh = _im
	material_override = material()
	custom_aabb = AABB(Vector3(-2000, -50, -2000), Vector3(4000, 100, 4000))


func count() -> int:
	return _pts.size()


func _process(dt: float) -> void:
	var road := WorldFlow.road_v()
	var i := _pts.size() - 1
	while i >= 0:
		_pts[i][1] += dt
		if road != 0.0:
			_pts[i][0] += Vector3(0, 0, road * dt)
		if _pts[i][1] >= LIFE:
			_pts.remove_at(i)
		i -= 1
	var head := Vector3.ZERO
	if emitting and source.is_valid():
		head = source.call()
		if _pts.is_empty() or (head - _pts[0][0]).length() >= GAP:
			if not _pts.is_empty():
				_dist += (head - _pts[0][0]).length()
			_pts.push_front([head, 0.0, _dist, _phase])
			_phase += 0.55
			if _pts.size() > MAX_PTS:
				_pts.pop_back()
	_build(head if emitting and source.is_valid() else Vector3.INF)


func _build(head: Vector3) -> void:
	_im.clear_surfaces()
	# 머리는 지금 분사구 자리 (기록 간격 사이에서도 띠가 분사구에 붙어 있게)
	var pts: Array = _pts.duplicate()
	if head != Vector3.INF and not pts.is_empty() and (head - pts[0][0]).length() > 0.005:
		pts.push_front([head, 0.0, _dist + (head - pts[0][0]).length(), _phase])
	if pts.size() < 2:
		return
	var cam := get_viewport().get_camera_3d()
	var t := Time.get_ticks_msec() * 0.001
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for n in pts.size():
		var p: Vector3 = pts[n][0]
		var k: float = clampf(pts[n][1] / LIFE, 0.0, 1.0)
		var a: Vector3 = pts[maxi(n - 1, 0)][0]
		var b: Vector3 = pts[mini(n + 1, pts.size() - 1)][0]
		var tan := (a - b)
		if tan.length() < 0.0001:
			tan = Vector3.FORWARD
		var view := (cam.global_position - p).normalized() if cam else Vector3.UP
		var side := tan.cross(view).normalized()
		# 머리(분사구)가 가장 두껍고 꼬리로 갈수록 가늘어진다. 연기라 나이 들며 살짝 퍼진다
		var u := float(n) / float(pts.size() - 1)
		var w := WIDTH * pow(1.0 - u, 0.5) * (1.0 + 0.4 * k)
		# 늙을수록 옆으로 물결쳐 나풀거림
		var wave := side * sin(float(pts[n][3]) + t * 9.0) * 0.08 * k
		var c := p + wave
		_im.surface_set_uv2(Vector2(pts[n][2], 0.0))
		_im.surface_set_uv(Vector2(k, 0.0))
		_im.surface_add_vertex(c - side * w * 0.5)
		_im.surface_set_uv2(Vector2(pts[n][2], 0.0))
		_im.surface_set_uv(Vector2(k, 1.0))
		_im.surface_add_vertex(c + side * w * 0.5)
	_im.surface_end()
