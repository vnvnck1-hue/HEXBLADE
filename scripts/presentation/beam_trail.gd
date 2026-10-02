class_name BeamTrail
extends Node3D
## 빔 끝점이 바닥을 긁고 지나간 궤적에 남는 얇은 잔상 라인. 판정과 무관.
## 매 프레임 push(끝점) 로 점을 쌓고, 각 점은 LIFE 초 동안 빛나다 가늘어지며 사라진다.
## 끝점이 순간이동(가로막는 적이 바뀜 등)하면 선을 끊어 새 가닥으로 잇는다.
## finish() 이후 남은 점이 모두 사라지면 스스로 해제된다.

const LIFE := 2.2          # 점 하나가 남아 있는 시간
const WIDTH := 0.4         # 잔상 선 굵기 (바닥 기준)
const GLOW_WIDTH := 1.0    # 바깥 은은한 번짐 폭
const Y := 0.045           # 바닥 위 높이 (z-fighting 방지)
const MIN_STEP := 0.06     # 이만큼 움직여야 점을 추가
const BREAK_DIST := 2.5    # 한 프레임에 이보다 멀리 튀면 선을 끊는다

@export var core_color := Color("1ff0ff")
@export var glow_color := Color("2fb8ff")

var strands: Array = []    # Array[Array[[Vector3 pos, float birth]]]
var t := 0.0
var ending := false
var _mesh := ArrayMesh.new()
# 매 프레임 다시 채우는 정점 배열 (정점마다 부르는 ImmediateMesh 대신 한 번에 넘긴다)
var _verts := PackedVector3Array()
var _cols := PackedColorArray()
var _uvs := PackedVector2Array()
var _arrays := []
var _mi := MeshInstance3D.new()
var _last := Vector3.INF

static var _shader: Shader


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float energy = 1.25;
void fragment() {
	// UV.x: 선 가로 방향 0..1. 가운데가 밝은 심, 가장자리는 부드럽게 사라진다
	float d = abs(UV.x - 0.5) * 2.0;
	float core = 1.0 - smoothstep(0.55, 1.0, d);
	ALBEDO = COLOR.rgb * energy * core * COLOR.a;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _shader
	_mi.mesh = _mesh
	_mi.material_override = m
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)


## 현재 빔 끝점을 궤적에 추가
func push(p: Vector3) -> void:
	if ending:
		return
	p.y = Y
	if _last == Vector3.INF or p.distance_to(_last) > BREAK_DIST:
		strands.append([])
	elif p.distance_to(_last) < MIN_STEP:
		# 거의 멈춰 있으면 마지막 점만 새로 고쳐 끝이 늘 빔에 붙어 있게 한다
		var s: Array = strands.back()
		if s.size() > 1:
			s[s.size() - 1] = [p, t]
			return
	(strands.back() as Array).append([p, t])
	_last = p


func finish() -> void:
	ending = true


func _process(dt: float) -> void:
	t += dt
	# 수명이 다한 점 제거 (각 가닥은 오래된 점부터 쌓여 있다)
	var i := strands.size() - 1
	while i >= 0:
		var s: Array = strands[i]
		while not s.is_empty() and t - float(s[0][1]) > LIFE:
			s.pop_front()
		if s.is_empty() and (ending or i < strands.size() - 1):
			strands.remove_at(i)
		i -= 1
	if ending and strands.is_empty():
		queue_free()
		return
	_rebuild()


func _rebuild() -> void:
	_mesh.clear_surfaces()
	var any := false
	for s in strands:
		if (s as Array).size() >= 2:
			any = true
			break
	if not any:
		return
	_verts.clear()
	_cols.clear()
	_uvs.clear()
	for s in strands:
		if (s as Array).size() < 2:
			continue
		_strip(s, GLOW_WIDTH, glow_color, 0.35)
		_strip(s, WIDTH, core_color, 1.0)
	if _arrays.is_empty():
		_arrays.resize(Mesh.ARRAY_MAX)
	_arrays[Mesh.ARRAY_VERTEX] = _verts
	_arrays[Mesh.ARRAY_COLOR] = _cols
	_arrays[Mesh.ARRAY_TEX_UV] = _uvs
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays)


## 한 가닥을 바닥에 눕힌 띠로 그린다. 나이에 따라 가늘어지고 흐려진다
func _strip(s: Array, width: float, col: Color, strength: float) -> void:
	var n := s.size()
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_c := Color.BLACK
	for k in n:
		var p: Vector3 = s[k][0]
		var a := clampf(1.0 - (t - float(s[k][1])) / LIFE, 0.0, 1.0)
		# 막 그어진 점은 짧게 번쩍이고, 수명 절반까지 또렷이 남았다가 식는다
		var heat := smoothstep(0.0, 0.5, a) * (1.0 + 1.2 * clampf((a - 0.92) * 12.5, 0.0, 1.0))
		var tan: Vector3 = (s[mini(k + 1, n - 1)][0] as Vector3) - (s[maxi(k - 1, 0)][0] as Vector3)
		tan.y = 0.0
		var side := Vector3(-tan.z, 0.0, tan.x).normalized() if tan.length() > 0.0001 else Vector3.RIGHT
		var w := width * (0.3 + 0.7 * smoothstep(0.0, 0.6, a)) * 0.5
		var l := p - side * w
		var r := p + side * w
		var c := Color(col.r, col.g, col.b, heat * strength)
		if k > 0:
			_quad(prev_l, prev_r, l, r, prev_c, c)
		prev_l = l
		prev_r = r
		prev_c = c


func _quad(l0: Vector3, r0: Vector3, l1: Vector3, r1: Vector3, c0: Color, c1: Color) -> void:
	_v(l0, 0.0, c0); _v(r0, 1.0, c0); _v(r1, 1.0, c1)
	_v(l0, 0.0, c0); _v(r1, 1.0, c1); _v(l1, 0.0, c1)


func _v(p: Vector3, u: float, c: Color) -> void:
	_verts.append(p)
	_cols.append(c)
	_uvs.append(Vector2(u, 0.0))
