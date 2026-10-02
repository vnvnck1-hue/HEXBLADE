class_name PaintedLook
extends RefCounted
## 핸드 페인팅 질감 실험 모듈. 모델은 기본 도형 + 단색 머티리얼이라 UV 텍스처를 칠할 수 없으므로
## 모든 질감을 셰이더 안에서 절차적으로 만든다(오브젝트 공간 트라이플래너 붓결 노이즈).
## 판정·게임 진행과 무관하며, apply()/restore() 로 이미 만든 모델의 머티리얼만 바꿔 끼운다.
##
## 프리셋 (docs/hand-painted-look.md 참고)
##   NONE    : 지금 그대로
##   STROKE  : 붓결 색 얼룩 + 위에서 내려오는 칠한 빛 그라디언트 (조명 계산은 엔진 기본)
##   PAINTED : STROKE + 붓으로 끊은 3단 음영 경계 + 그림자 색조 이동 + 붓 하이라이트
##   EDGE    : PAINTED + 볼록 모서리 밝은 칠(엣지 하이라이트) 후처리
##   OIL     : STROKE + 화면 쿠와하라 유화 필터 + 캔버스 결
##   HEARTH  : 하스스톤(블리자드 핸드 페인팅) 식 — 파츠마다 위 밝고 아래 어둡게 칠한 그라디언트, 윗모서리 밝은 선 ·
##             아랫모서리 짙은 갈색 선, 칠 벗겨진 모서리, 채도 높은 따뜻한 그림자, 점 하이라이트. 외곽선 없음.
##             파츠의 메시 경계 상자(AABB)를 인스턴스 파라미터로 넘겨 셰이더가 '이 파츠의 위·아래·모서리'를 안다.

enum { NONE, STROKE, PAINTED, EDGE, OIL, HEARTH }
const NAMES := ["NONE", "STROKE", "PAINTED", "EDGE", "OIL", "HEARTH"]

const COMMON := """
varying vec3 o_pos;
varying vec3 o_nrm;
varying vec3 w_pos;
varying float v_stroke;

uniform vec3 base : source_color = vec3(0.8);
uniform float brush = 0.3;           // 붓결 명도·색조 흔들림 세기
uniform float stroke_scale = 3.2;    // 1m 당 붓결 밀도
uniform float hemi = 0.6;            // 위=밝고 따뜻 / 아래=어둡고 차가운 칠한 빛
uniform float height_grad = 0.35;    // 발치로 갈수록 어두워짐 (WoW 식 그라디언트)
uniform float grad_top = 2.2;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 g2(vec2 i) { float a = h21(i) * 6.2831853; return vec2(cos(a), sin(a)); }
float gnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(dot(g2(i), f), dot(g2(i + vec2(1, 0)), f - vec2(1, 0)), u.x),
			mix(dot(g2(i + vec2(0, 1)), f - vec2(0, 1)), dot(g2(i + vec2(1, 1)), f - vec2(1, 1)), u.x), u.y);
}
// 한 방향으로 길게 늘인 노이즈 = 붓자국. 큰 얼룩(c)이 덧칠한 면적을 만든다.
float strokes(vec2 uv) {
	// 큰 노이즈로 좌표를 휘게 해서 획이 곧은 줄무늬(헤어라인 금속)처럼 보이지 않게 한다
	uv += vec2(gnoise(uv * 0.45 + 1.7), gnoise(uv * 0.45 - 4.2)) * 1.4;
	vec2 q = mat2(vec2(0.866, 0.5), vec2(-0.5, 0.866)) * uv;
	float a = gnoise(vec2(q.x * 1.1, q.y * 5.0));
	float b = gnoise(vec2(q.x * 2.4 + 5.1, q.y * 11.0));
	float c = gnoise(uv * 0.6 + 9.3);
	return a * 0.5 + b * 0.14 + c * 0.7;
}
float tri_strokes(vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return strokes(p.zy) * w.x + strokes(p.xz + 3.7) * w.y + strokes(p.xy + 7.1) * w.z;
}

void vertex() {
	o_pos = VERTEX;
	o_nrm = NORMAL;
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 painted_albedo(vec3 wn, float s) {
	vec3 col = base;
	float up = wn.y * 0.5 + 0.5;
	col *= mix(1.0 - hemi * 0.38, 1.0 + hemi * 0.22, up);
	col = mix(col, col * vec3(0.82, 0.88, 1.18), hemi * (1.0 - up) * 0.55);
	col = mix(col, col * vec3(1.08, 1.02, 0.9), hemi * up * 0.35);
	float h = clamp(w_pos.y / grad_top, 0.0, 1.0);
	col *= mix(1.0 - height_grad * 0.45, 1.0, h);
	// 붓결: 밝은 획은 따뜻하게, 어두운 획은 차갑게 (실제 덧칠은 명도와 색조가 같이 흔들린다)
	col *= 1.0 + s * brush;
	col = mix(col, col * vec3(1.07, 1.0, 0.86), clamp(s, 0.0, 1.0) * brush * 1.6);
	col = mix(col, col * vec3(0.88, 0.94, 1.14), clamp(-s, 0.0, 1.0) * brush * 1.6);
	return clamp(col, 0.0, 1.0);
}
"""

const FRAG := """
void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_stroke = tri_strokes(o_pos * stroke_scale, o_nrm);
	ALBEDO = painted_albedo(wn, v_stroke);
	ROUGHNESS = 0.9;   // 0 이 아니어야 ToonOutline 이 외곽선을 긋는다
	SPECULAR = 0.15;
}
"""

## 붓으로 끊은 음영: 반사광 대신 3단(그림자·중간·밝음) 칠. 경계선이 붓결 노이즈로 흔들린다.
const LIGHT := """
uniform vec3 shadow_tint : source_color = vec3(0.42, 0.36, 0.78);
uniform float term_noise = 0.22;   // 음영 경계가 붓결 따라 흔들리는 폭
uniform float spec_paint = 0.18;   // 붓으로 찍은 하이라이트 세기

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float n = v_stroke * term_noise;
	float sh = smoothstep(0.35, 0.65, ATTENUATION);
	float t1 = smoothstep(-0.06, 0.06, ndl + 0.05 + n) * sh;
	float t2 = smoothstep(-0.05, 0.05, ndl - 0.55 + n * 1.4) * sh;
	float lit = t1 * 0.62 + t2 * 0.38;
	vec3 lc = LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += lc * (lit + shadow_tint * 0.28 * (1.0 - t1));
	vec3 hv = normalize(LIGHT + VIEW);
	float sp = smoothstep(0.0, 0.04, dot(NORMAL, hv) - 0.93 + v_stroke * 0.05) * t1;
	SPECULAR_LIGHT += lc * sp * spec_paint;
}
"""

static var _shaders := {}
static var _mats := {}
static var _post: Array[Node] = []


static func _shader(p: int) -> Shader:
	if not _shaders.has(p):
		var sh := Shader.new()
		if p == HEARTH:
			sh.code = HEARTH_SHADER
		else:
			sh.code = "shader_type spatial;\nrender_mode cull_back;\n" + COMMON + FRAG \
					+ (LIGHT if p == PAINTED or p == EDGE else "")
		_shaders[p] = sh
	return _shaders[p]


## 색 하나에 대한 칠 머티리얼 (프리셋별로 캐시)
## env: 바닥·벽처럼 큰 면은 붓결을 크고 옅게 (같은 밀도면 빗줄기처럼 보인다)
static func material(c: Color, p: int, env := false) -> ShaderMaterial:
	var key := "%s_%d_%s" % [c.to_html(), p, env]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = _shader(p)
	m.set_shader_parameter("base", c)
	if p == HEARTH:
		if env:
			m.set_shader_parameter("blotch_scale", 0.35)
			m.set_shader_parameter("rivets", 0.0)
	elif env:
		m.set_shader_parameter("stroke_scale", 0.9)
		m.set_shader_parameter("brush", 0.2)
		m.set_shader_parameter("height_grad", 0.0)
	_mats[key] = m
	return m


## 바꿔도 되는 머티리얼인가: Pal.lit/mech 의 불투명·비발광 셀 머티리얼만
static func _convertible(m: Material) -> bool:
	var sm := m as StandardMaterial3D
	return sm != null and sm.has_meta("toon") and not sm.emission_enabled \
			and sm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED


## root 아래 모델들의 머티리얼을 프리셋으로 바꾼다 (원본은 메타에 보관해 되돌릴 수 있다)
static func apply(root: Node, p: int) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		convert_one(mi, p)


## ── 게임 연결 ───────────────────────────────────────
## Main 이 씬마다 attach() 한 번 부르고, K 키로 toggle(). 켠 상태는 static 이라 씬을 다시 불러도 유지된다.
## 실행 인자 --look=hearth 로 켠 채 시작. 나중에 생기는 적·파편도 SceneTree.node_added 로 잡아 바꾼다.
static var game_preset := HEARTH if OS.get_cmdline_user_args().has("--look=hearth") else NONE
static var _game: Node
static var _env: Environment
static var _sun: DirectionalLight3D
static var _env_orig := {}


static func attach(scene: Node, env: Environment, sun: DirectionalLight3D) -> void:
	_game = scene
	_env = env
	_sun = sun
	_env_orig = {}
	if env:
		_env_orig.ambient = env.ambient_light_color
		_env_orig.adj = env.adjustment_enabled
		_env_orig.sat = env.adjustment_saturation
		_env_orig.con = env.adjustment_contrast
	if sun:
		_env_orig.sun_c = sun.light_color
		_env_orig.sun_e = sun.light_energy
	var w := Watcher.new()
	w.name = "PaintedLookWatcher"
	scene.add_child(w)
	_apply_game()


## NONE ↔ HEARTH. 바뀐 상태 이름을 돌려준다
static func toggle() -> String:
	game_preset = NONE if game_preset == HEARTH else HEARTH
	_apply_game()
	return NAMES[game_preset]


static func _apply_game() -> void:
	if not is_instance_valid(_game):
		return
	apply(_game, game_preset)
	grade(game_preset == HEARTH)
	var cam := _game.get_viewport().get_camera_3d()
	if cam:
		set_post(cam, game_preset)


## 하스스톤 식 조명 보정: 노란 주광 · 자줏빛 환경광 · 채도 약간 (끄면 원래 값)
static func grade(on: bool) -> void:
	if _env and _env_orig.has("ambient"):
		_env.ambient_light_color = Color(0.58, 0.5, 0.8) if on else _env_orig.ambient
		_env.adjustment_enabled = true if on else _env_orig.adj
		_env.adjustment_saturation = 1.1 if on else _env_orig.sat
		_env.adjustment_contrast = 1.04 if on else _env_orig.con
	if is_instance_valid(_sun) and _env_orig.has("sun_c"):
		_sun.light_color = Color(1.0, 0.94, 0.84) if on else _env_orig.sun_c
		_sun.light_energy = _env_orig.sun_e * (1.04 if on else 1.0)


## 하나의 메시: 바꿀 수 있으면 바꾸고, 이미 HEARTH 머티리얼을 복사해 온 파편이면 경계 상자만 맞춘다
static func convert_one(mi: MeshInstance3D, p: int) -> void:
	if mi.material_override == null and mi.mesh != null:
		_convert_surfaces(mi, p)
		return
	var cur := mi.material_override
	if p == HEARTH and cur is ShaderMaterial and (cur as ShaderMaterial).shader == _shaders.get(HEARTH):
		_set_box(mi)
		return
	if cur is ShaderMaterial and _is_map_floor(cur as ShaderMaterial):
		_warm_floor(cur as ShaderMaterial, p == HEARTH)
		return
	var orig: Material = mi.get_meta("pl_orig") if mi.has_meta("pl_orig") else cur
	if not _convertible(orig):
		return
	mi.set_meta("pl_orig", orig)
	var bb: AABB = mi.get_aabb()
	var big: bool = bb.size[bb.size.max_axis_index()] > 4.0
	mi.material_override = orig if p == NONE else material((orig as StandardMaterial3D).albedo_color, p, big)
	if p == HEARTH:
		_set_box(mi)


## 맵 바닥(ArenaMap 의 격자 셰이더)은 무늬를 살리고 바탕색만 따뜻하게 옮긴다
static func _is_map_floor(m: ShaderMaterial) -> bool:
	if m.shader == null:
		return false
	# 셰이더 원문 검색은 비싸서 셰이더마다 한 번만 하고 결과를 기억한다
	var id := m.shader.get_instance_id()
	if not _floor_shader.has(id):
		_floor_shader[id] = m.shader.code.contains("line_col") and m.shader.code.contains("grid(")
	return _floor_shader[id]


static var _floor_shader := {}   # 셰이더 instance id → 맵 바닥 격자 셰이더인가


static func _warm_floor(m: ShaderMaterial, on: bool) -> void:
	if not m.has_meta("pl_base"):
		m.set_meta("pl_base", m.get_shader_parameter("base"))
	var c: Color = m.get_meta("pl_base")
	if on:
		var w := Color(c.r * 1.16, c.g * 0.97, c.b * 0.8)
		c = c.lerp(w, 0.55)
	m.set_shader_parameter("base", c)


## 맵 벽처럼 메시 표면마다 머티리얼이 붙은 지형: 표면 덮어쓰기로 바꾼다 (메시 자체는 건드리지 않음)
static func _convert_surfaces(mi: MeshInstance3D, p: int) -> void:
	for s in mi.mesh.get_surface_count():
		var orig := mi.mesh.surface_get_material(s)
		if not _convertible(orig):
			continue
		if p != HEARTH:
			mi.set_surface_override_material(s, null)
			continue
		var arr := mi.mesh.surface_get_arrays(s)
		var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var top := nrm.size() > 0 and nrm[0].y > 0.7
		mi.set_surface_override_material(s, world_material((orig as StandardMaterial3D).albedo_color, top))


static func world_material(c: Color, top: bool) -> ShaderMaterial:
	var key := "world_%s_%s" % [c.to_html(), top]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = _shader(HEARTH)
	m.set_shader_parameter("base", c)
	m.set_shader_parameter("world_mode", 1.0)
	m.set_shader_parameter("blotch_scale", 0.5)
	m.set_shader_parameter("face_k", 1.12 if top else 0.72)
	_mats[key] = m
	return m


static func _set_box(mi: MeshInstance3D) -> void:
	var bb: AABB = mi.get_aabb()
	mi.set_instance_shader_parameter("aabb_lo", bb.position)
	mi.set_instance_shader_parameter("aabb_hi", bb.end)
	mi.set_instance_shader_parameter("boxy", 1.0 if mi.mesh is BoxMesh or mi.mesh is ArrayMesh else 0.0)


## 씬에 새로 들어오는 메시(웨이브로 생기는 적, 파편)를 현재 룩으로 바꾼다
class Watcher extends Node:
	func _enter_tree() -> void:
		get_tree().node_added.connect(_on_added)

	func _ready() -> void:
		# 카메라·맵이 다 만들어진 뒤 한 번 더 (후처리는 카메라가 있어야 붙는다)
		PaintedLook._apply_game.call_deferred()

	func _exit_tree() -> void:
		if get_tree().node_added.is_connected(_on_added):
			get_tree().node_added.disconnect(_on_added)

	func _on_added(n: Node) -> void:
		if PaintedLook.game_preset != PaintedLook.NONE and n is MeshInstance3D:
			# 연출 조각(초당 수백 개)은 조명 무시 단색 공용 머티리얼이라 바꿀 것이 없다
			if (n as MeshInstance3D).material_override == Pal.flat():
				return
			# 머티리얼을 add_child 뒤에 넣는 코드도 있으니 한 박자 늦게
			_late.call_deferred(n)

	func _late(n: Node) -> void:
		if is_instance_valid(n) and n.is_inside_tree():
			PaintedLook.convert_one(n, PaintedLook.game_preset)


## 화면 후처리(엣지 하이라이트·유화)를 카메라에 붙이거나 뗀다
static func set_post(cam: Camera3D, p: int) -> void:
	for n in _post:
		if is_instance_valid(n):
			n.queue_free()
	_post.clear()
	if p == EDGE:
		_post.append(_screen_quad(cam, EDGE_SHADER, Material.RENDER_PRIORITY_MIN + 1))
	elif p == OIL:
		_post.append(_screen_quad(cam, OIL_SHADER, Material.RENDER_PRIORITY_MAX))
	elif p == HEARTH:
		# 지형(러프니스 0.95 표식)의 볼록 모서리만 밝게 — 캐릭터 파츠는 셰이더가 직접 칠한다
		var q := _screen_quad(cam, EDGE_SHADER, Material.RENDER_PRIORITY_MIN + 1)
		var m := q.material_override as ShaderMaterial
		m.set_shader_parameter("only_rough", 0.95)
		m.set_shader_parameter("strength", 0.6)
		m.set_shader_parameter("radius", 2.6)
		_post.append(q)


static func set_preset(root: Node, cam: Camera3D, p: int) -> void:
	apply(root, p)
	set_post(cam, p)


static func _screen_quad(cam: Camera3D, code: String, prio: int) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	q.flip_faces = true
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	m.render_priority = prio
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	mi.position = Vector3(0, 0, -1)
	cam.add_child(mi)
	return mi


## 볼록 모서리 하이라이트: 깊이로 이웃 픽셀의 위치를 복원해 '접평면 뒤로 꺾여 내려가는' 모서리만 밝게 칠한다.
## 손으로 칠한 텍스처에서 모서리를 밝게 긁어 형태를 세우는 기법을 화면 공간으로 흉내낸다.
const EDGE_SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec3 warm : source_color = vec3(1.0, 0.93, 0.78);
uniform float strength = 0.55;
uniform float radius = 2.2;
uniform float only_rough = -1.0;   // 0 이상이면 이 러프니스로 칠한 면에만

void vertex() { POSITION = vec4(VERTEX.xy, 1.0, 1.0); }

vec3 vpos(vec2 uv, mat4 ip) {
	float d = texture(depth_tex, uv).r;
	vec4 v = ip * vec4(uv * 2.0 - 1.0, d, 1.0);
	return v.xyz / v.w;
}
vec3 vnrm(vec2 uv) { return normalize(texture(normal_tex, uv).xyz * 2.0 - 1.0); }
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 px = radius * (VIEWPORT_SIZE.y / 800.0) / VIEWPORT_SIZE;
	vec2 uv = SCREEN_UV;
	vec3 pc = vpos(uv, INV_PROJECTION_MATRIX);
	vec3 nc = vnrm(uv);
	vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float e = 0.0;
	if (only_rough >= 0.0) {
		// ToonOutline 과 같은 해독: 동적 물체는 w 가 1 - r 로 뒤집혀 저장된다
		float r = texture(normal_tex, uv).w;
		if (r > 0.5) { r = 1.0 - r; }
		r /= (127.0 / 255.0);
		if (abs(r - only_rough) > 0.03) { discard; }
	}
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398;
		vec2 u = uv + vec2(cos(a), sin(a)) * px;
		vec3 pu = vpos(u, INV_PROJECTION_MATRIX);
		vec3 nu = vnrm(u);
		float crease = 1.0 - smoothstep(0.75, 0.92, dot(nc, nu));
		float near = 1.0 - smoothstep(0.03, 0.08, length(pu - pc) / max(-pc.z, 0.01));
		float convex = step(dot(pu - pc, nc), 0.0);
		// 모서리의 위쪽(빛 받는) 면에만 칠한다
		float upper = step(0.05, dot(nc - nu, up));
		e = max(e, crease * near * convex * upper);
	}
	// 붓이 지나간 듯 띄엄띄엄 끊는다
	vec2 cell = floor(FRAGCOORD.xy / vec2(7.0, 3.0));
	e *= 0.55 + 0.45 * step(0.3, h21(cell));
	e *= step(-pc.z, 120.0);
	// 칠한 면의 색을 밝고 따뜻하게 올린 색 (흰 선이 아니라 같은 색의 밝은 획)
	vec3 c = texture(screen_tex, uv).rgb;
	ALBEDO = mix(c * 1.7 + 0.05, warm, 0.25);
	ALPHA = e * strength;
}
"""

## 쿠와하라 필터: 네 사분면 중 분산이 가장 작은 쪽 평균을 고른다 → 면은 평평한 붓칠, 경계는 살아 있다.
const OIL_SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform int radius = 4;
uniform float canvas = 0.06;

void vertex() { POSITION = vec4(VERTEX.xy, 1.0, 1.0); }
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 px = (VIEWPORT_SIZE.y / 720.0) / VIEWPORT_SIZE;
	vec2 uv = SCREEN_UV;
	vec3 m[4]; vec3 s[4];
	for (int k = 0; k < 4; k++) { m[k] = vec3(0.0); s[k] = vec3(0.0); }
	float n = float((radius + 1) * (radius + 1));
	for (int j = -radius; j <= 0; j++) for (int i = -radius; i <= 0; i++) {
		vec3 c0 = texture(screen_tex, uv + vec2(float(i), float(j)) * px).rgb;
		vec3 c1 = texture(screen_tex, uv + vec2(float(-i), float(j)) * px).rgb;
		vec3 c2 = texture(screen_tex, uv + vec2(float(i), float(-j)) * px).rgb;
		vec3 c3 = texture(screen_tex, uv + vec2(float(-i), float(-j)) * px).rgb;
		m[0] += c0; s[0] += c0 * c0; m[1] += c1; s[1] += c1 * c1;
		m[2] += c2; s[2] += c2 * c2; m[3] += c3; s[3] += c3 * c3;
	}
	vec3 best = vec3(0.0); float bv = 1e9;
	for (int k = 0; k < 4; k++) {
		vec3 mu = m[k] / n;
		vec3 v = abs(s[k] / n - mu * mu);
		float vs = v.r + v.g + v.b;
		if (vs < bv) { bv = vs; best = mu; }
	}
	// 캔버스 결: 가로·세로 실이 엮인 미세 요철
	vec2 f = FRAGCOORD.xy;
	float weave = sin(f.x * 1.9) * sin(f.y * 1.9) * 0.5 + (h21(floor(f / 2.0)) - 0.5) * 0.6;
	best *= 1.0 + weave * canvas;
	ALBEDO = best;
	ALPHA = 1.0;
}
"""


## 하스스톤 식 칠. 관찰한 규칙(docs/hearthstone-look.md):
## 1) 파츠 하나하나가 '위에서 빛을 받는 덩어리'로 칠해져 있다 — 위쪽 밝고 노랗게, 아래로 갈수록 어둡고 채도가 오른다.
## 2) 형태는 외곽선이 아니라 모서리의 명암으로 세운다 — 위를 향한 모서리는 밝은 선, 아래를 향한 모서리·틈은 짙은 갈색.
## 3) 모서리는 칠이 벗겨져 들쭉날쭉하고, 면 안은 깨끗하다(잔 노이즈 대신 큰 얼룩과 보색 얼룩만).
## 4) 그림자는 회색이 아니라 따뜻한 갈색·자주로 채도가 높다. 둥근 부분엔 흰 점 하이라이트.
const HEARTH_SHADER := """
shader_type spatial;
render_mode cull_back;

instance uniform vec3 aabb_lo = vec3(-0.5);
instance uniform vec3 aabb_hi = vec3(0.5);
instance uniform float boxy = 0.0;      // 상자·판재 메시면 1 (리벳은 평평한 면에만)
uniform vec3 base : source_color = vec3(0.8);
uniform float blotch_scale = 1.6;
uniform float edge_w = 0.045;          // 모서리 칠 폭 (메시 단위 m)
uniform float rivets = 1.0;            // 넓은 면 네 귀퉁이 리벳 (바닥 등 큰 면은 0)
// 지형(맵 벽처럼 한 메시에 여러 블록이 합쳐진 것): 파츠 경계 상자가 의미 없으므로 월드 좌표 얼룩 + 면별 밝기만
uniform float world_mode = 0.0;
const vec3 WARM = vec3(1.16, 0.97, 0.8);
uniform float face_k = 1.0;            // 지형 면 밝기 (윗면 밝게 · 옆면 어둡게)
uniform vec3 light_tint : source_color = vec3(1.0, 0.93, 0.72);
uniform vec3 dark_tint : source_color = vec3(0.30, 0.16, 0.12);
uniform vec3 shade_tint : source_color = vec3(0.55, 0.32, 0.45);

varying vec3 o_pos;
varying vec3 o_nrm;
varying vec3 up_o;
varying vec3 w_pos;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 g2(vec2 i) { float a = h21(i) * 6.2831853; return vec2(cos(a), sin(a)); }
float gnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(dot(g2(i), f), dot(g2(i + vec2(1, 0)), f - vec2(1, 0)), u.x),
			mix(dot(g2(i + vec2(0, 1)), f - vec2(0, 1)), dot(g2(i + vec2(1, 1)), f - vec2(1, 1)), u.x), u.y);
}
float tri(vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return gnoise(p.zy) * w.x + gnoise(p.xz + 3.7) * w.y + gnoise(p.xy + 7.1) * w.z;
}
vec3 saturate_col(vec3 c, float k) {
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	return clamp(mix(vec3(l), c, k), 0.0, 1.0);
}

void vertex() {
	o_pos = VERTEX;
	o_nrm = NORMAL;
	// 월드 위쪽을 이 파츠의 로컬 좌표로 (회전한 파츠도 '자기 위'가 아니라 '세상의 위'를 밝힌다)
	up_o = normalize(transpose(mat3(MODEL_MATRIX)) * vec3(0.0, 1.0, 0.0));
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 lo = aabb_lo;
	vec3 hi = max(aabb_hi, aabb_lo + vec3(0.001));
	vec3 size = hi - lo;
	vec3 ctr = (lo + hi) * 0.5;
	vec3 on = normalize(o_nrm);
	// 칠은 화가가 보는 색(감마 공간)에서 한다. 선형 공간에서 곱하면 채도·명도가 과하게 튄다.
	vec3 col = saturate_col(sqrt(base), 1.1);
	if (world_mode > 0.5) {
		vec3 wn0 = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		float c1 = tri(w_pos * blotch_scale, wn0);
		float c2 = tri(w_pos * blotch_scale * 2.3 + 11.0, wn0);
		col *= 1.0 + c1 * 0.1;
		col += vec3(0.022, -0.01, 0.02) * c2;
		// 하스스톤 색감: 차가운 남보라 지형을 따뜻한 자두·갈색 쪽으로
		col = mix(col, col * WARM, 0.55);
		col = face_k >= 1.0 ? mix(col * face_k, sqrt(light_tint), 0.06)
				: saturate_col(col * face_k, 1.15) * mix(vec3(1.0), sqrt(shade_tint) * 1.25, 0.2);
		col = clamp(col, 0.0, 1.0);
		ALBEDO = col * col;
		ROUGHNESS = 0.95;   // 0.95 = 지형 표식: 모서리 하이라이트 후처리가 지형에만 걸린다
		SPECULAR = 0.2;
	} else {

	// 1) 파츠 안 세로 그라디언트: -1(아래) ~ 1(위)
	float ext = max(dot(abs(up_o), size) * 0.5, 0.001);
	float g = clamp(dot(o_pos - ctr, up_o) / ext, -1.0, 1.0);
	// 큰 얼룩 + 보색 얼룩 (명도는 조금, 색조는 조금 더)
	float b1 = tri(o_pos * blotch_scale, on);
	float b2 = tri(o_pos * blotch_scale * 2.3 + 11.0, on);
	col *= 1.0 + b1 * 0.07;
	col += vec3(0.022, -0.01, 0.02) * b2;
	col = mix(col, col * WARM, rivets < 0.5 ? 0.55 : 0.0);
	vec3 top = mix(col * 1.07, sqrt(light_tint), 0.07);
	vec3 bot = saturate_col(col * 0.64, 1.2) * mix(vec3(1.0), sqrt(shade_tint) * 1.25, 0.22);
	col = mix(bot, top, smoothstep(-1.05, 0.9, g));
	// 면 방향: 윗면은 한 단 더 밝게
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	col *= 0.95 + 0.08 * smoothstep(0.2, 0.9, wn.y);

	// 2) 모서리: 이 면을 이루는 축을 뺀 두 축 중 경계에 가장 가까운 쪽
	int f = 0;
	vec3 an = abs(on);
	if (an.y > an.x && an.y >= an.z) { f = 1; } else if (an.z > an.x && an.z > an.y) { f = 2; }
	float e = 1e5;
	vec3 nn = vec3(0.0);
	for (int i = 0; i < 3; i++) {
		if (i == f) { continue; }
		float dl = o_pos[i] - lo[i];
		float dh = hi[i] - o_pos[i];
		vec3 ax = vec3(0.0);
		ax[i] = 1.0;
		if (dl < e) { e = dl; nn = -ax; }
		if (dh < e) { e = dh; nn = ax; }
	}
	float w = min(edge_w, min(min(size.x, size.y), size.z) * 0.22);
	// 칠 벗겨짐: 모서리 폭이 노이즈로 들쭉날쭉
	float chip = gnoise(o_pos.xz * 9.0 + o_pos.y * 7.0) * 0.5 + 0.5;
	float band = 1.0 - smoothstep(w * (0.45 + chip * 0.9), w * (0.6 + chip * 1.1), e);
	float upness = dot(nn, up_o) + dot(on, up_o) * 0.6;
	float hi_e = band * smoothstep(-0.15, 0.25, upness);
	float lo_e = band * (1.0 - smoothstep(-0.45, -0.1, upness));
	col = mix(col, mix(col, sqrt(light_tint), 0.45), hi_e * 0.8);
	col = mix(col, col * sqrt(dark_tint) * 0.8, lo_e * 0.75);

	// 3) 리벳: 면의 두 축이 모두 충분히 넓으면 귀퉁이 안쪽에 볼트 머리를 칠한다 (어두운 테 + 위쪽 점 하이라이트)
	if (rivets > 0.5 && boxy > 0.5 && an[f] > 0.97) {
		int a0 = f == 0 ? 1 : 0;
		int a1 = f == 2 ? 1 : 2;
		float inset = 0.065;
		float r = 0.016;
		if (size[a0] > 0.3 && size[a1] > 0.3) {
			float u = o_pos[a0];
			float v = o_pos[a1];
			float cu = u - lo[a0] < hi[a0] - u ? lo[a0] + inset : hi[a0] - inset;
			float cv = v - lo[a1] < hi[a1] - v ? lo[a1] + inset : hi[a1] - inset;
			vec3 d3 = vec3(0.0);
			d3[a0] = u - cu;
			d3[a1] = v - cv;
			float d = length(d3);
			float ring = 1.0 - smoothstep(r * 0.85, r, d);
			float head = 1.0 - smoothstep(r * 0.55, r * 0.7, d);
			// 볼트 머리의 위쪽 절반이 밝다
			float topside = smoothstep(-0.2, 0.5, dot(normalize(d3 + vec3(1e-5)), up_o));
			col = mix(col, col * 0.62, ring * 0.85);
			col = mix(col, mix(col * 0.9, mix(col, sqrt(light_tint), 0.55), topside), head);
		}
	}

	col = clamp(col, 0.0, 1.0);
	ALBEDO = col * col;
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
	}
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float sh = smoothstep(0.2, 0.8, ATTENUATION);
	// 칠에 이미 빛이 들어 있으므로 실시간 조명은 넓고 부드럽게, 그림자는 따뜻한 자줏빛으로
	float lit = smoothstep(-0.25, 0.45, ndl) * mix(0.25, 1.0, sh);
	vec3 lc = LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += lc * mix(shade_tint * 0.6, vec3(1.0), lit);
	// 둥근 면의 흰 점 하이라이트
	vec3 hv = normalize(LIGHT + VIEW);
	SPECULAR_LIGHT += lc * smoothstep(0.975, 0.99, dot(NORMAL, hv)) * lit * 0.3;
}
"""
