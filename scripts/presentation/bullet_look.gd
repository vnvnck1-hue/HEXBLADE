class_name BulletLook
extends Node3D
## 적 투사체(적탄 · 푸른 경직탄 등 Main.add_bullet 으로 들어오는 적 Bullet) 시인성 프리셋 (연출 전용, 판정 없음).
##
##   0 BASE     기본 (작은 빨강→주황→노랑 깜빡이는 구체)
##   1 CORE     테두리 + 흰 심: 구체 대신 1.45배 큰 카툰 탄 — 바깥 광채 · 짙은 남색 테두리 · 2단 색 몸통 · 흰 심.
##              밝은 바닥 · 어두운 바닥 · 불꽃 이펙트 위 어디서나 탄 하나하나가 또렷하다 (탄막 게임식 고대비 탄)
##   2 TRAIL    진행 방향 꼬리: 속도만큼 늘어나는 꼬리(머리 흰빛 → 탄 색 → 짙은 붉은 꼬리, 가장자리 어두운 테) —
##              어디로 얼마나 빨리 오는지가 한눈에 읽힌다
##   3 GROUND   바닥 그림자 + 예상 경로: 탄 바로 아래 바닥에 그림자 점 · 붉은 고리, 앞으로 진행 방향 점선 —
##              쿼터뷰에서 헷갈리는 탄의 바닥 위치(높이)와 진로가 바닥에 찍힌다
##
## 프리셋은 static 이라 씬을 다시 불러도 유지. 허수아비 씬 Y / Shift+Y, 실행 인자 --bulletlook=core|trail|ground.
## 재질은 프리셋마다 정적 하나(색은 인스턴스 값) → 탄이 아무리 생겨도 캐시가 늘지 않는다.

enum { BASE, CORE, TRAIL, GROUND }
const IDS := ["base", "core", "trail", "ground"]
const NAMES := ["BASE 기본", "CORE 테두리 + 흰 심", "TRAIL 진행 방향 꼬리", "GROUND 바닥 그림자 + 경로"]
const DESCS := [
	"예전 그대로 (작은 깜빡이는 구체)",
	"1.45배 카툰 탄: 광채 · 짙은 테두리 · 흰 심 — 어떤 배경에서도 또렷",
	"속도만큼 늘어나는 꼬리 — 방향 · 속도가 한눈에",
	"탄 아래 바닥 그림자 · 앞쪽 점선 — 바닥 위치와 진로가 바닥에 찍힘",
]
const GROUP := "enemy_bullets"

static var preset := BASE
static var _args_read := false
static var _core_mat: ShaderMaterial
static var _trail_mat: ShaderMaterial
static var _ground_mat: ShaderMaterial
static var _quad: QuadMesh
static var _plane: PlaneMesh
static var _stem: CylinderMesh
static var _stem_mat: StandardMaterial3D

var bullet: Bullet
var mode := BASE
var geo: MeshInstance3D
var lane_len := 3.2
var stem: MeshInstance3D             ## GROUND: 탄과 바닥 표시를 잇는 수직선


static func read_args() -> void:
	if _args_read:
		return
	_args_read = true
	for a in Main.cmd_args:
		if String(a).begins_with("--bulletlook="):
			var i := IDS.find(String(a).substr(13))
			if i >= 0:
				preset = i


static func cycle(tree: SceneTree, dir := 1) -> int:
	set_preset(tree, posmod(preset + dir, IDS.size()))
	return preset


static func set_preset(tree: SceneTree, i: int) -> void:
	preset = i
	if tree == null:
		return
	for b in tree.get_nodes_in_group(GROUP):
		if b is Bullet:
			apply(b as Bullet)


## 적 탄에 지금 프리셋의 표시를 붙인다 (이미 있으면 바꿔 단다). Main.add_bullet 이 부른다.
static func apply(b: Bullet) -> void:
	read_args()
	if b == null or not is_instance_valid(b) or b.from_player or b.mesh == null:
		return
	var old := b.get_node_or_null("BulletLook")
	if old:
		b.remove_child(old)
		old.queue_free()
	b.mesh.visible = true
	if preset == BASE:
		return
	var l := BulletLook.new()
	l.name = "BulletLook"
	l.bullet = b
	l.mode = preset
	b.add_child(l)


static func count(tree: SceneTree) -> int:
	var n := 0
	for b in tree.get_nodes_in_group(GROUP):
		if (b as Node).get_node_or_null("BulletLook"):
			n += 1
	return n


func _ready() -> void:
	_meshes()
	geo = MeshInstance3D.new()
	geo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match mode:
		CORE:
			geo.mesh = _quad
			geo.material_override = _core()
			bullet.mesh.visible = false
		TRAIL:
			geo.mesh = _quad
			geo.material_override = _trail()
		GROUND:
			geo.mesh = _plane
			geo.material_override = _ground()
			geo.top_level = true
			stem = MeshInstance3D.new()
			stem.mesh = _stem
			stem.material_override = _stem_mat
			stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			stem.top_level = true
			add_child(stem)
	geo.set_instance_shader_parameter("rad", bullet.radius)
	geo.set_instance_shader_parameter("blue", 1.0 if bullet.unslashable else 0.0)
	add_child(geo)
	_update()


func _process(_dt: float) -> void:
	_update()


func _update() -> void:
	if not is_instance_valid(bullet) or not is_instance_valid(geo):
		return
	var tint: Variant = bullet.mesh.get_instance_shader_parameter("tint")
	var col: Color = tint if tint is Color else Pal.E_BULLETS[0]
	geo.set_instance_shader_parameter("col", col)
	var fade := clampf(bullet.life / 0.25, 0.0, 1.0)
	geo.set_instance_shader_parameter("fade", fade)
	var v := bullet.vel
	v.y = 0.0
	var spd := v.length()
	var dir := v / spd if spd > 0.01 else Vector3.FORWARD
	match mode:
		CORE:
			geo.set_instance_shader_parameter("size", bullet.radius * 2.2 * 1.45 * 1.6)
		TRAIL:
			geo.set_instance_shader_parameter("dir", dir)
			geo.set_instance_shader_parameter("len", clampf(spd * 0.11, 0.6, 2.4) * minf(1.0, bullet.age / 0.08 + 0.15))
			geo.set_instance_shader_parameter("wid", bullet.radius * 2.2)
		GROUND:
			var p := bullet.global_position
			var g := Vector3(p.x, Main.gy(p) + 0.045, p.z)
			# 높이 차가 클수록(멀리 떠 있을수록) 그림자가 옅고 넓다
			geo.set_instance_shader_parameter("lift", clampf((p.y - g.y) / 3.0, 0.0, 1.0))
			geo.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), g) * Transform3D(Basis.IDENTITY, Vector3(0, 0, -(lane_len * 0.5 - 0.6)))
			geo.scale = Vector3(1.6, 1.0, lane_len)
			geo.set_instance_shader_parameter("len", lane_len)
			var hgt := maxf(p.y - g.y - bullet.radius, 0.02)
			stem.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3(1, hgt, 1)), g + Vector3(0, hgt * 0.5, 0))
			stem.transparency = 1.0 - 0.7 * fade


static func _meshes() -> void:
	if _quad:
		return
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE
	_plane = PlaneMesh.new()
	_plane.size = Vector2.ONE
	_stem = CylinderMesh.new()
	_stem.top_radius = 0.022
	_stem.bottom_radius = 0.022
	_stem.height = 1.0
	_stem.radial_segments = 6
	_stem.rings = 1
	_stem_mat = StandardMaterial3D.new()
	_stem_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_stem_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_stem_mat.albedo_color = Color(1.0, 0.3, 0.2, 1.0)


## 카메라를 보는 카툰 탄: 광채 → 남색 테두리 → 2단 색 몸통 → 흰 심 (깊이는 탄 자리, 다른 물체 뒤로는 가려짐)
static func _core() -> ShaderMaterial:
	if _core_mat == null:
		var sh: Shader = ResCache.shader("""
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
instance uniform vec4 col : source_color = vec4(1.0, 0.2, 0.1, 1.0);
instance uniform float fade = 1.0;
instance uniform float size = 0.6;
instance uniform float blue = 0.0;
instance uniform float rad = 0.15;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX *= size;
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) discard;
	vec3 navy = vec3(0.07, 0.04, 0.14);
	vec3 c = col.rgb;
	float a = 1.0;
	float beat = 0.5 + 0.5 * sin(TIME * 20.0);
	if (r > 0.66) {
		// 바깥 광채 (탄 색, 맥동)
		c = mix(c, vec3(1.0), 0.25);
		a = (1.0 - smoothstep(0.66, 1.0, r)) * (0.45 + 0.25 * beat);
	} else if (r > 0.5) {
		c = navy;                                         // 짙은 테두리
	} else {
		// 2단 몸통: 왼쪽 위 밝게, 가운데 흰 심
		float lit = step(0.0, -(p.x + p.y) * 0.7 + 0.08);
		c = mix(col.rgb * 0.72, mix(col.rgb, vec3(1.0), 0.25), lit);
		float core = 1.0 - smoothstep(0.17, 0.24, length(p - vec2(-0.05, -0.05)));
		c = mix(c, vec3(1.0), core);
	}
	ALBEDO = c;
	ALPHA = a * fade;
}
""")
		_core_mat = ShaderMaterial.new()
		_core_mat.shader = sh
		_core_mat.render_priority = 20
	return _core_mat


## 진행 방향으로 늘어나는 꼬리 (탄 자리에서 뒤로). 축 = 속도, 폭 방향 = 축 × 시선
static func _trail() -> ShaderMaterial:
	if _trail_mat == null:
		var sh: Shader = ResCache.shader("""
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;
instance uniform vec4 col : source_color = vec4(1.0, 0.2, 0.1, 1.0);
instance uniform float fade = 1.0;
instance uniform vec3 dir = vec3(0.0, 0.0, -1.0);
instance uniform float len = 1.0;
instance uniform float wid = 0.3;
instance uniform float rad = 0.15;
instance uniform float blue = 0.0;
void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 side = normalize(cross(dir, normalize(cam - c)));
	float along = VERTEX.y + 0.5;                     // 1 = 머리 (탄 자리), 0 = 꼬리 끝
	float w = wid * mix(0.25, 1.15, along);
	vec3 wp = c + dir * (along - 1.0) * len + dir * wid * 0.45 + side * VERTEX.x * w;
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}
void fragment() {
	float along = 1.0 - UV.y;
	float edge = abs(UV.x - 0.5) * 2.0;
	vec3 c = mix(vec3(0.35, 0.03, 0.05), col.rgb, smoothstep(0.0, 0.6, along));
	c = mix(c, vec3(1.0), smoothstep(0.7, 1.0, along) * (1.0 - edge));
	c = mix(c, vec3(0.08, 0.03, 0.1), smoothstep(0.62, 0.9, edge) * 0.85);   // 어두운 테두리 = 밝은 바닥에서도 보임
	float a = pow(along, 1.3) * (1.0 - smoothstep(0.9, 1.0, edge));
	ALBEDO = c;
	ALPHA = clamp(a * fade, 0.0, 1.0);
}
""")
		_trail_mat = ShaderMaterial.new()
		_trail_mat.shader = sh
		_trail_mat.render_priority = 4
	return _trail_mat


## 바닥: 탄 아래 그림자 점 + 붉은 고리, 앞쪽 진행 점선 (평면 로컬 -Z = 진행 방향)
static func _ground() -> ShaderMaterial:
	if _ground_mat == null:
		var sh: Shader = ResCache.shader("""
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
instance uniform vec4 col : source_color = vec4(1.0, 0.2, 0.1, 1.0);
instance uniform float fade = 1.0;
instance uniform float len = 3.2;
instance uniform float rad = 0.15;
instance uniform float lift = 0.3;
instance uniform float blue = 0.0;
void fragment() {
	float y = (1.0 - UV.y) * len - 0.6;               // 탄 바로 아래 = 0, 앞쪽 +
	float x = (UV.x - 0.5) * 1.6;
	float r = length(vec2(x, y));
	vec3 red = blue > 0.5 ? vec3(0.3, 0.65, 1.0) : vec3(1.0, 0.18, 0.12);
	float sr = rad * (1.5 + lift * 1.2);
	float shadow = (1.0 - smoothstep(sr * 0.7, sr * 1.05, r)) * (0.8 - lift * 0.3);
	float ring = 1.0 - smoothstep(0.02, 0.055, abs(r - sr * 1.35 - 0.04 * sin(TIME * 12.0)));
	float dash = step(0.5, fract(y / 0.42 - TIME * 2.2));
	float lane = (1.0 - smoothstep(0.06, 0.09, abs(x))) * dash * step(sr * 1.6, y) * (1.0 - smoothstep(len * 0.45, len - 0.6, y));
	vec3 c = vec3(0.05, 0.02, 0.09);
	float a = shadow;
	if (ring > 0.01) { c = mix(c, mix(red, col.rgb, 0.4), ring); a = max(a, ring * 0.95); }
	if (lane > 0.01) { c = mix(c, red, lane); a = max(a, lane * 0.95); }
	ALBEDO = c;
	ALPHA = clamp(a * fade, 0.0, 1.0);
}
""")
		_ground_mat = ShaderMaterial.new()
		_ground_mat.shader = sh
		_ground_mat.render_priority = 3
	return _ground_mat
