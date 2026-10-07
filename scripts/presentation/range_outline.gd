class_name RangeOutline
extends Node3D
## 범위 공격 시전 전: 범위 안에 든 적의 실루엣 바깥에 굵은 붉은 외곽선을 두른다 (판정 없음, 연출 전용).
##
## 쓰는 법: 조준하는 동안 매 틱 RangeOutline.mark(태그, 적 배열) — 태그마다 지금 범위 안 적 목록을 넘긴다.
##          조준이 끝나면 RangeOutline.clear(태그). 여러 태그가 같은 적을 겹쳐 잡아도 외곽선은 하나.
##
## 방식 (스텐실):
##   ① 마스크: 적 파츠와 같은 메시를 그대로 그리며 스텐실에 STENCIL_REF 를 쓴다 (색은 옅은 붉은 림만).
##   ② 외곽: 같은 메시를 화면 공간에서 THICK 픽셀만큼 바깥으로 부풀려, 스텐실이 비어 있는 곳(몸 바깥)에만 칠한다.
##      → 몸 안쪽 파츠 사이에는 선이 생기지 않고 실루엣 바깥 테두리만 남는다.
##   부풀리는 방향은 파츠 중심 → 정점 방향(오브젝트 공간)이라 각진 로우폴리 모서리에도 틈이 벌어지지 않는다.
##   마스크를 모든 외곽보다 먼저 그리도록 render_priority 를 나눈다.
## 복사 메시는 적 노드 아래가 아니라 이 노드 아래에 두고 매 프레임 원본 파츠의 변환을 따라간다
## (적 몸 아래에 두면 피격 섬광 · 잔상이 복사본까지 잡는다).

const STENCIL_REF := 77
const COL := Color(1.0, 0.13, 0.12)    # 레퍼런스의 붉은 테두리
const THICK := 4.6                     # 외곽선 두께 (화면 높이 800px 기준 픽셀, 해상도 따라 늘어남)
const POP_T := 0.2                     # 범위에 들어온 순간 굵게 튀었다 자리 잡는 시간
const OUT_T := 0.1                     # 범위를 벗어나면 이만큼 동안 가늘어지며 사라짐
const NEAR := 0.45                     # 외곽을 카메라 쪽으로 당기는 거리 (발밑 테두리가 바닥에 묻히지 않게)

static var inst: RangeOutline
static var _mask_mat: ShaderMaterial
static var _hull_mat: ShaderMaterial

var _req: Dictionary = {}              # 태그 → { 적 instance id: 적 }
var _on: Dictionary = {}               # 적 instance id → { "e": 적, "parts": [[원본, 마스크, 외곽]], "t": 나이, "out": 사라지는 중 시간(-1 = 아님) }


## 이 태그로 지금 범위 안에 있는 적들. 매 틱 불러 준다.
static func mark(tag: String, enemies: Array) -> void:
	var o := _inst()
	if o == null:
		return
	var d := {}
	for e in enemies:
		if is_instance_valid(e):
			d[(e as Object).get_instance_id()] = e
	o._req[tag] = d


static func clear(tag: String) -> void:
	if is_instance_valid(inst):
		inst._req.erase(tag)


## 이 적에 외곽선이 켜져 있나 (확인용)
static func is_marked(e: Node) -> bool:
	if not is_instance_valid(inst) or not is_instance_valid(e):
		return false
	var s = inst._on.get(e.get_instance_id())
	return s != null and float(s.out) < 0.0


static func count() -> int:
	if not is_instance_valid(inst):
		return 0
	var n := 0
	for s in inst._on.values():
		if float(s.out) < 0.0:
			n += 1
	return n


static func _inst() -> RangeOutline:
	if is_instance_valid(inst):
		return inst
	var root: Node = FX.root if is_instance_valid(FX.root) else (Main.inst if is_instance_valid(Main.inst) else null)
	if root == null:
		return null
	inst = RangeOutline.new()
	inst.name = "RangeOutline"
	root.add_child(inst)
	return inst


func _exit_tree() -> void:
	if inst == self:
		inst = null


func _ready() -> void:
	top_level = true
	process_priority = 100              # 적 · 리그가 자세를 잡은 뒤에 따라간다
	set_process(true)


func _process(dt: float) -> void:
	# 실제 시간으로 움직인다 (조준 중 슬로모션 · 히트스탑과 상관없이 또렷하게)
	var rdt := dt / maxf(Engine.time_scale, 0.001)
	var want := {}
	for tag in _req:
		for id in _req[tag]:
			var e = _req[tag][id]
			if is_instance_valid(e) and e.alive:
				want[id] = e
	for id in want:
		var s = _on.get(id)
		if s == null:
			_attach(want[id])
		elif float(s.out) >= 0.0:
			s.out = -1.0                 # 나가다 다시 들어옴: 다시 튀게
			s.t = 0.0
	for id in _on.keys():
		var s: Dictionary = _on[id]
		var e = s.e
		if not is_instance_valid(e) or not e.alive:
			_drop(id)
			continue
		if not want.has(id) and float(s.out) < 0.0:
			s.out = 0.0
		s.t = float(s.t) + rdt
		var k: float
		if float(s.out) >= 0.0:
			s.out = float(s.out) + rdt
			if float(s.out) >= OUT_T:
				_drop(id)
				continue
			k = 1.0 - float(s.out) / OUT_T
		else:
			k = _pop(float(s.t))
		var px := THICK * k
		var rim := clampf(float(s.t) / 0.08, 0.0, 1.0) * (1.0 if float(s.out) < 0.0 else k)
		var parts: Array = s.parts
		for pr in parts:
			var src = pr[0]
			var mask := pr[1] as MeshInstance3D
			var hull := pr[2] as MeshInstance3D
			if not is_instance_valid(src):
				mask.visible = false
				hull.visible = false
				continue
			var vis: bool = (src as MeshInstance3D).is_visible_in_tree()
			mask.visible = vis
			hull.visible = vis
			if not vis:
				continue
			var g: Transform3D = (src as MeshInstance3D).global_transform
			mask.global_transform = g
			hull.global_transform = g
			hull.set_instance_shader_parameter("px", px)
			mask.set_instance_shader_parameter("rim", rim)


## 들어온 순간 굵게 튀었다가(1.7배) 자리 잡고, 그 뒤엔 은은하게 숨 쉰다
func _pop(t: float) -> float:
	if t < POP_T:
		var u := t / POP_T
		if u < 0.35:
			return lerpf(0.0, 1.7, u / 0.35)
		return lerpf(1.7, 1.0, 1.0 - pow(1.0 - (u - 0.35) / 0.65, 2.0))
	return 1.0 + 0.08 * sin((t - POP_T) * 9.0)


func _attach(e: Node) -> void:
	var body = e.j.get("body") if e.get("j") is Dictionary else null
	if not is_instance_valid(body):
		return
	var parts: Array = []
	for m in (body as Node3D).find_children("*", "MeshInstance3D", true, false):
		var src := m as MeshInstance3D
		if src.mesh == null:
			continue
		var mask := _copy(src, _mask())
		var hull := _copy(src, _hull())
		hull.set_instance_shader_parameter("oc", src.mesh.get_aabb().get_center())
		hull.set_instance_shader_parameter("px", 0.0)
		parts.append([src, mask, hull])
	if parts.is_empty():
		return
	_on[e.get_instance_id()] = {"e": e, "parts": parts, "t": 0.0, "out": -1.0}


func _copy(src: MeshInstance3D, mat: Material) -> MeshInstance3D:
	var c := MeshInstance3D.new()
	c.mesh = src.mesh
	c.material_override = mat
	c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.extra_cull_margin = 1.0
	add_child(c)
	if src.skin:
		c.skin = src.skin
		var sk := src.get_node_or_null(src.skeleton)
		if sk:
			c.skeleton = c.get_path_to(sk)
	c.global_transform = src.global_transform
	return c


func _drop(id) -> void:
	var s = _on.get(id)
	_on.erase(id)
	if s == null:
		return
	for pr in s.parts:
		for i in [1, 2]:
			if is_instance_valid(pr[i]):
				(pr[i] as Node).queue_free()


## ① 마스크: 보이는 몸 픽셀에 스텐실을 찍는다. 색은 가장자리만 옅게 붉게.
static func _mask() -> ShaderMaterial:
	if _mask_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;
stencil_mode write, compare_always, %d;
instance uniform float rim = 0.0;
uniform vec3 col : source_color;
void fragment() {
	float r = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	ALBEDO = col * 1.4;
	ALPHA = r * 0.45 * rim;
}
""" % STENCIL_REF
		_mask_mat = ShaderMaterial.new()
		_mask_mat.shader = sh
		_mask_mat.set_shader_parameter("col", COL)
		_mask_mat.render_priority = 40
	return _mask_mat


## ② 외곽: 화면 공간에서 일정한 픽셀 두께로 부풀린 실루엣, 스텐실이 없는(몸 바깥) 곳에만
static func _hull() -> ShaderMaterial:
	if _hull_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// 몸 바깥(스텐실 0)에서만. compare_not_equal 은 4.7.2 에서 아무 데도 통과하지 않아 ref(77) > 값 으로 거른다
stencil_mode read, compare_greater, %d;
instance uniform vec3 oc = vec3(0.0);
instance uniform float px = 0.0;
uniform vec3 col : source_color;
uniform float near_pull = %.3f;
void vertex() {
	vec3 d = VERTEX - oc;
	vec3 dir = length(d) > 1e-4 ? normalize(d) : NORMAL;
	vec4 v0 = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 v1 = MODELVIEW_MATRIX * vec4(VERTEX + dir * 0.05, 1.0);
	vec4 c0 = PROJECTION_MATRIX * v0;
	vec4 c1 = PROJECTION_MATRIX * v1;
	float asp = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	vec2 s = (c1.xy / c1.w - c0.xy / c0.w) * vec2(asp, 1.0);
	s = length(s) > 1e-6 ? normalize(s) : vec2(0.0);
	// 카메라 쪽으로 조금 당긴 위치로 투영 (깊이만 앞으로)
	vec4 vn = v0;
	vn.xyz -= normalize(v0.xyz) * near_pull;
	vec4 cn = PROJECTION_MATRIX * vn;
	vec2 ndc = c0.xy / c0.w + s * vec2(1.0 / asp, 1.0) * (px * 2.0 / 800.0);
	POSITION = vec4(ndc * cn.w, cn.z, cn.w);
}
void fragment() {
	ALBEDO = col * 1.25;
	ALPHA = 1.0;
}
""" % [STENCIL_REF, NEAR]
		_hull_mat = ShaderMaterial.new()
		_hull_mat.shader = sh
		_hull_mat.set_shader_parameter("col", COL)
		_hull_mat.render_priority = 41
	return _hull_mat
