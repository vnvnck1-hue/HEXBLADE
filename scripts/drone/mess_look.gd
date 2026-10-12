class_name MessLook
extends Node3D
## 처치된 적의 사체(잔해 · 체액 = DroneMess)가 어두운 바닥에 묻혀 잘 안 보이는 문제의 해결 프리셋 (연출 전용, 판정 없음).
##
##   0 BASE     기본 (예전 그대로)
##   1 RING     바닥 고리: 사체 둘레 바닥에 가산 발광 고리 + 안으로 퍼지는 물결 + 바깥 점선. 어두운 바닥에서 위치가 읽힌다
##   2 OUTLINE  실루엣 외곽선: 조각 · 웅덩이 실루엣 바깥에 굵은 밝은 테두리(스텐실) + 옅은 림. 형태 자체가 배경과 갈라진다
##   3 BEACON   아이콘 · 빛기둥: 사체 위에 떠서 까딱이는 핀 아이콘(벽 뒤에서도 보임) + 바닥에서 솟는 가는 빛기둥
##
## 색: 기계 잔해 = 호박색, 체액 = 그 체액 색을 밝게. 청소가 진행될수록 옅어지고, 다 치우면 사라진다.
## 프리셋은 static 이라 씬을 다시 불러도 유지. 허수아비 씬 9 / Shift+9, 실행 인자 --messlook=ring|outline|beacon.
## 재질은 프리셋마다 정적 하나씩(색 · 세기는 인스턴스 값) → 사체가 아무리 생겨도 캐시가 늘지 않는다.

enum { BASE, RING, OUTLINE, BEACON }
const IDS := ["base", "ring", "outline", "beacon"]
const NAMES := ["BASE 기본", "RING 바닥 고리", "OUTLINE 실루엣 외곽선", "BEACON 아이콘 · 빛기둥"]
const DESCS := [
	"예전 그대로 (어두운 조각 · 얼룩)",
	"사체 둘레 바닥에 발광 고리 · 물결 — 어두운 바닥에서도 자리가 읽힌다",
	"조각 · 웅덩이 실루엣에 굵은 밝은 테두리 — 형태가 배경과 갈라진다",
	"사체 위 핀 아이콘(벽 뒤에서도 보임) + 바닥 빛기둥 — 멀리서도 찾는다",
]
const SCRAP_COL := Color(1.0, 0.7, 0.18)
const STENCIL_REF := 61               ## RangeOutline(77) 과 다른 값
const OUTLINE_PX := 4.2               ## 화면 높이 800px 기준

static var preset := BASE
static var _args_read := false
static var _ring_mat: ShaderMaterial
static var _mask_mat: ShaderMaterial
static var _hull_mat: ShaderMaterial
static var _pin_mat: ShaderMaterial
static var _beam_mat: ShaderMaterial
static var _plane: PlaneMesh
static var _quad: QuadMesh
static var _beam: CylinderMesh

var mess: DroneMess
var mode := BASE
var col := SCRAP_COL
var phase := 0.0
var geoms: Array[GeometryInstance3D] = []    ## 인스턴스 값을 갱신할 것 (fade)
var hulls: Array[GeometryInstance3D] = []    ## 외곽선 두께를 갱신할 것
var pin: Node3D
var _built := false


# ── 프리셋 ──────────────────────────────────────────

static func read_args() -> void:
	if _args_read:
		return
	_args_read = true
	for a in Main.cmd_args:
		if String(a).begins_with("--messlook="):
			var i := IDS.find(String(a).substr(11))
			if i >= 0:
				preset = i


## 다음/이전 프리셋으로 바꾸고 지금 있는 사체 전부에 바로 적용
static func cycle(tree: SceneTree, dir := 1) -> int:
	set_preset(tree, posmod(preset + dir, IDS.size()))
	return preset


static func set_preset(tree: SceneTree, i: int) -> void:
	preset = i
	if tree == null:
		return
	for m in tree.get_nodes_in_group(DroneMess.GROUP):
		apply(m as DroneMess)


## 사체에 지금 프리셋의 표시를 붙인다 (이미 있으면 바꿔 단다). DroneMess._ready 가 부른다.
static func apply(m: DroneMess) -> void:
	read_args()
	if m == null or not is_instance_valid(m):
		return
	var old := m.get_node_or_null("MessLook")
	if old:
		(old as MessLook).teardown()
		m.remove_child(old)
		old.queue_free()
	if preset == BASE:
		return
	var l := MessLook.new()
	l.name = "MessLook"
	l.mess = m
	l.mode = preset
	m.add_child(l)


static func count(tree: SceneTree) -> int:
	var n := 0
	for m in tree.get_nodes_in_group(DroneMess.GROUP):
		if (m as Node).get_node_or_null("MessLook"):
			n += 1
	return n


# ── 한 사체의 표시 ─────────────────────────────────────

func _ready() -> void:
	phase = randf()
	col = SCRAP_COL
	if mess.kind == DroneMess.Kind.GOO:
		col = mess.goo_col.lerp(Color.WHITE, 0.3)
		col = Color.from_hsv(col.h, minf(col.s * 1.15, 1.0), maxf(col.v, 0.95))
	# InfestRemains 는 조각을 _ready 다음에 넘겨받는다 → 한 프레임 미뤄서 짓는다
	_build.call_deferred()


func _build() -> void:
	if _built or not is_instance_valid(mess):
		return
	_built = true
	_meshes()
	match mode:
		RING:
			var mi := MeshInstance3D.new()
			mi.mesh = _plane
			mi.material_override = _ring()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var s := mess.radius * 2.9
			mi.scale = Vector3(s, 1.0, s)
			mi.position.y = 0.035
			add_child(mi)
			_track(mi)
		OUTLINE:
			for mi in _parts(mess):
				var mask := MeshInstance3D.new()
				mask.mesh = mi.mesh
				mask.material_override = _mask()
				mask.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mask.set_meta("mess_look", true)
				mi.add_child(mask)
				var hull := MeshInstance3D.new()
				hull.mesh = mi.mesh
				hull.material_override = _hull()
				hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				hull.set_meta("mess_look", true)
				mi.add_child(hull)
				hull.set_instance_shader_parameter("oc", mi.mesh.get_aabb().get_center())
				_track(mask)
				_track(hull)
				hulls.append(hull)
		BEACON:
			pin = Node3D.new()
			add_child(pin)
			var q := MeshInstance3D.new()
			q.mesh = _quad
			q.material_override = _pin()
			q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			q.set_instance_shader_parameter("kind", 0.0 if mess.kind == DroneMess.Kind.SCRAP else 1.0)
			q.set_instance_shader_parameter("size", 0.95 + 0.15 * clampf(mess.size_k - 1.0, -0.3, 1.0))
			pin.add_child(q)
			_track(q)
			var b := MeshInstance3D.new()
			b.mesh = _beam
			b.material_override = _beam_m()
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			b.position.y = _beam.height * 0.5
			add_child(b)
			_track(b)
	_refresh(0.0)


func _track(g: GeometryInstance3D) -> void:
	g.set_instance_shader_parameter("col", col)
	g.set_instance_shader_parameter("phase", phase)
	geoms.append(g)


## 외곽선을 두를 메시들: 사체 아래 모든 MeshInstance3D (얼룩 판 · 이 표시 자신 · 이미 날아가 숨은 것 제외)
static func _parts(m: DroneMess) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [m]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MessLook:
			continue
		if n is MeshInstance3D and n != m.stain and not n.has_meta("mess_look") and (n as MeshInstance3D).mesh:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


## 표시를 뗄 때: 조각 밑에 붙인 외곽선 복사본도 지운다
func teardown() -> void:
	for g in geoms:
		if is_instance_valid(g) and g.get_parent() != self and not is_ancestor_of(g):
			g.queue_free()
	geoms.clear()
	hulls.clear()


func _exit_tree() -> void:
	teardown()


func _process(dt: float) -> void:
	if not is_instance_valid(mess) or not _built:
		return
	if mess.done:
		# 다 치우면 짧게 줄어들며 사라진다
		for g in geoms:
			if is_instance_valid(g):
				g.visible = false
		return
	if Cull.far(global_position) and mess.sucking <= 0.0:
		return
	_refresh(dt)


func _refresh(_dt: float) -> void:
	var f := 1.0 - mess.progress() * 0.75
	var t := mess.age
	for g in geoms:
		if is_instance_valid(g):
			g.set_instance_shader_parameter("fade", f)
	if mode == OUTLINE:
		# 생기는 순간 굵게 튀었다 자리 잡고, 그 뒤엔 숨 쉬듯 살짝 굵어졌다 가늘어진다
		var pop := 1.0 + 0.9 * exp(-t * 7.0)
		var px := OUTLINE_PX * pop * (0.9 + 0.12 * sin(t * 3.4 + phase * TAU)) * (0.55 + 0.45 * f)
		for h in hulls:
			if is_instance_valid(h):
				h.set_instance_shader_parameter("px", px)
	elif mode == BEACON and pin:
		pin.position.y = 1.75 + 0.12 * sin(t * 3.0 + phase * TAU) + 0.25 * mess.size_k * 0.4
		var s := 1.0 + 0.6 * exp(-t * 6.0) * cos(t * 22.0)
		pin.scale = Vector3.ONE * s


# ── 정적 재질 · 메시 ────────────────────────────────────

static func _meshes() -> void:
	if _plane:
		return
	_plane = PlaneMesh.new()
	_plane.size = Vector2.ONE
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE
	_beam = CylinderMesh.new()
	_beam.top_radius = 0.07
	_beam.bottom_radius = 0.13
	_beam.height = 2.6
	_beam.radial_segments = 10
	_beam.rings = 1
	_beam.cap_top = false
	_beam.cap_bottom = false


static func _ring() -> ShaderMaterial:
	if _ring_mat == null:
		var sh: Shader = ResCache.shader("""
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
instance uniform vec3 col = vec3(1.0);
instance uniform float fade = 1.0;
instance uniform float phase = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) discard;
	float pulse = 0.78 + 0.22 * sin(TIME * 4.2 + phase * 6.2832);
	float ring = smoothstep(0.075, 0.0, abs(r - 0.66));
	float core = smoothstep(0.03, 0.0, abs(r - 0.66));
	float t = fract(TIME * 0.55 + phase);
	float rip = 0.66 + 0.3 * t;                     // 고리에서 바깥으로 퍼지며 옅어지는 물결
	float wave = smoothstep(0.05, 0.0, abs(r - rip)) * (1.0 - t);
	float a = atan(p.y, p.x) / 6.2832;
	float dash = step(0.45, fract(a * 14.0 - TIME * 0.18 + phase));
	float outer = smoothstep(0.025, 0.0, abs(r - 0.9)) * dash;
	float fill = smoothstep(0.66, 0.0, r) * 0.16;
	float v = ring * 0.85 * pulse + core * 0.6 + wave * 0.75 + outer * 0.55 + fill;
	ALBEDO = mix(col, vec3(1.0), core * 0.45) * 1.7;
	ALPHA = clamp(v * fade, 0.0, 1.0);
}
""")
		_ring_mat = ShaderMaterial.new()
		_ring_mat.shader = sh
		_ring_mat.render_priority = 2
	return _ring_mat


## 외곽선 ① 마스크: 보이는 조각 픽셀에 스텐실 + 옅은 밝은 림
static func _mask() -> ShaderMaterial:
	if _mask_mat == null:
		var sh: Shader = ResCache.shader("""
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;
stencil_mode write, compare_always, %d;
instance uniform vec3 col = vec3(1.0);
instance uniform float fade = 1.0;
void fragment() {
	float r = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = col * 1.3;
	ALPHA = r * 0.5 * fade;
}
""" % STENCIL_REF)
		_mask_mat = ShaderMaterial.new()
		_mask_mat.shader = sh
		_mask_mat.render_priority = 36
	return _mask_mat


## 외곽선 ② 화면 공간 일정 두께로 부풀린 실루엣, 스텐실이 없는(실루엣 바깥) 곳에만
## (RangeOutline 과 같은 방식: 4.7.2 의 compare_not_equal 은 통과하지 않아 compare_greater 로 거른다)
static func _hull() -> ShaderMaterial:
	if _hull_mat == null:
		var sh: Shader = ResCache.shader("""
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
stencil_mode read, compare_greater, %d;
instance uniform vec3 oc = vec3(0.0);
instance uniform float px = 0.0;
instance uniform vec3 col = vec3(1.0);
instance uniform float fade = 1.0;
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
	vec4 vn = v0;
	vn.xyz -= normalize(v0.xyz) * 0.3;              // 바닥에 붙은 웅덩이 테두리가 바닥에 묻히지 않게 깊이만 당긴다
	vec4 cn = PROJECTION_MATRIX * vn;
	vec2 ndc = c0.xy / c0.w + s * vec2(1.0 / asp, 1.0) * (px * 2.0 / 800.0);
	POSITION = vec4(ndc * cn.w, cn.z, cn.w);
}
void fragment() {
	float pulse = 0.85 + 0.15 * sin(TIME * 5.0);
	ALBEDO = mix(col, vec3(1.0), 0.18) * 1.35 * pulse;
	ALPHA = clamp(0.35 + 0.65 * fade, 0.0, 1.0);
}
""" % STENCIL_REF)
		_hull_mat = ShaderMaterial.new()
		_hull_mat.shader = sh
		_hull_mat.render_priority = 37
	return _hull_mat


## 핀 아이콘: 카메라를 보는 판, 깊이 무시(벽 뒤에서도 보임). 잔해 = 별 모양, 체액 = 물방울
static func _pin() -> ShaderMaterial:
	if _pin_mat == null:
		var sh: Shader = ResCache.shader("""
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
instance uniform vec3 col = vec3(1.0);
instance uniform float fade = 1.0;
instance uniform float phase = 0.0;
instance uniform float kind = 0.0;
instance uniform float size = 0.95;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX *= size * length(MODEL_MATRIX[0].xyz);
}
float tail_d(vec2 p, float grow) {
	// 원 머리 아래로 뻗는 뾰족한 꼬리 (0.25 ~ 0.98)
	float y0 = 0.2, y1 = 0.98 + grow * 1.3;
	float k = clamp((p.y - y0) / (y1 - y0), 0.0, 1.0);
	float hw = (0.48 + grow) * (1.0 - k);
	return (p.y > y0 - 0.2 && p.y < y1) ? abs(p.x) - hw : 1.0;
}
void fragment() {
	vec2 p = (UV - vec2(0.5, 0.4)) * vec2(2.0, 2.2);
	float head = length(p) - 0.6;
	float body = min(head, tail_d(p, 0.0));
	float edge = min(length(p) - 0.75, tail_d(p, 0.13));
	if (edge > 0.0) discard;
	vec3 navy = vec3(0.08, 0.06, 0.16);
	vec3 c = navy;
	if (body < 0.0) {
		// 위가 밝은 2단 칠
		c = mix(col, col * 0.72, step(0.08, p.y + p.x * 0.3));
		c = mix(c, vec3(1.0), smoothstep(-0.05, -0.0, -length(p - vec2(-0.25, -0.3)) + 0.12) * 0.6);
		// 안쪽 기호
		vec2 q = p;
		float glyph;
		if (kind < 0.5) {
			// 4갈래 별 (기계 잔해 반짝임)
			q = abs(q);
			glyph = pow(q.x, 0.55) + pow(q.y, 0.55) - 0.62;
		} else {
			// 물방울
			vec2 o = q - vec2(0.0, 0.08);
			float drop = length(o) - 0.24;
			float k = clamp((-o.y) / 0.42, 0.0, 1.0);
			float cone = (o.y < 0.0 && o.y > -0.46) ? abs(o.x) - 0.24 * (1.0 - k) : 1.0;
			glyph = min(drop, cone);
		}
		if (glyph < 0.0) c = navy;
		if (glyph < -0.07 && kind < 0.5) c = vec3(1.0);
		if (glyph < -0.06 && kind > 0.5) c = vec3(1.0);
	}
	float blink = 0.9 + 0.1 * sin(TIME * 6.0 + phase * 6.2832);
	ALBEDO = c * blink;
	ALPHA = clamp(0.25 + 0.75 * fade, 0.0, 1.0);
}
""")
		_pin_mat = ShaderMaterial.new()
		_pin_mat.shader = sh
		_pin_mat.render_priority = 30
	return _pin_mat


static func _beam_m() -> ShaderMaterial:
	if _beam_mat == null:
		var sh: Shader = ResCache.shader("""
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
instance uniform vec3 col = vec3(1.0);
instance uniform float fade = 1.0;
instance uniform float phase = 0.0;
void fragment() {
	float up = 1.0 - UV.y;                           // 0 바닥 → 1 꼭대기
	float a = pow(1.0 - up, 1.6);
	float run = smoothstep(0.12, 0.0, abs(fract(up * 1.2 - TIME * 0.9 + phase) - 0.5) - 0.32);
	float side = pow(1.0 - abs(dot(NORMAL, VIEW)), 1.5);
	ALBEDO = mix(col, vec3(1.0), 0.35) * 1.6;
	ALPHA = clamp(a * (0.45 + 0.35 * run) * (1.0 - side * 0.6) * fade, 0.0, 1.0);
}
""")
		_beam_mat = ShaderMaterial.new()
		_beam_mat.shader = sh
		_beam_mat.render_priority = 3
	return _beam_mat
