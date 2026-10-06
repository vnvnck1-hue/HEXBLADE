class_name SmokeZone
extends Node3D
## 연기 구역: 바닥 통풍구에서 연기가 끊임없이 피어오른다. 판정은 반지름 radius 원기둥 (contains).
## 연기 덩이는 MultiMesh 하나(빌보드 사각형)로 그리고 CPU 에서 움직인다.
##  - 기본 덩이: 원 안 바닥에서 솟아 부풀며 올라가다 흩어진다
##  - 끌림: 플레이어가 지나가면 가까운 덩이가 움직임 방향으로 밀린다
##  - 꼬리: 구역을 빠져나가는 순간부터 잠깐 동안 몸에서 연기 가닥이 떨어져 나와 움직임을 따라 끌려 나온다
## 인스턴스 색 = 명도, 인스턴스 데이터 = (불투명도, 시드, 회전, 0)

const BASE := 64                  # 구역 안에 떠 있는 기본 덩이 수 (반지름 2.7m 기준)
const WISPS := 48                 # 꼬리 가닥 최대 수
const RISE := Vector2(0.35, 0.75)
const LIFE := Vector2(3.6, 5.2)
const TOP := 3.2                  # 이보다 높이 올라간 덩이는 흩어진다
const TRAIL_TIME := 0.8           # 빠져나온 뒤 꼬리가 나오는 시간
const TRAIL_GAP := 0.045

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear, repeat_disable;
uniform vec4 lit_col : source_color = vec4(0.62, 0.64, 0.74, 1.0);
uniform vec4 dark_col : source_color = vec4(0.2, 0.2, 0.27, 1.0);
varying vec4 v_data;
varying float v_shade;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++) { v += noise(p) * a; p *= 2.03; a *= 0.5; } return v; }
void vertex() {
	v_data = INSTANCE_CUSTOM;
	v_shade = COLOR.r;
	float c = cos(v_data.z); float s = sin(v_data.z);
	UV = (mat2(vec2(c, -s), vec2(s, c)) * (UV - 0.5)) + 0.5;
%s
}
void fragment() {
	vec2 q = UV - 0.5;
	float r = length(q) * 2.0;
	float n = fbm(UV * 3.1 + v_data.y * 17.0 + vec2(0.0, TIME * 0.12));
	float body = smoothstep(1.0, 0.25, r + (n - 0.5) * 0.9);
	// 위쪽이 밝고 아래가 어두운 가짜 조명 (덩이 안쪽 결)
	float top = clamp(0.5 - q.y * 1.1 + (n - 0.5) * 0.5, 0.0, 1.0);
	vec3 col = mix(dark_col.rgb, lit_col.rgb, top) * v_shade;
	float a = body * v_data.x;
	// 바닥·벽과 만나는 곳은 부드럽게
	float d = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 wp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	wp.xyz /= wp.w;
	a *= clamp(1.0 - smoothstep(wp.z + 0.6, wp.z, VERTEX.z), 0.0, 1.0);
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
	ROUGHNESS = 0.0;
}
"""

static var _mat: ShaderMaterial
static var _quad: QuadMesh
static var _vent_mat: StandardMaterial3D

var radius := 2.7
var _mm: MultiMesh
var _puffs: Array = []            # {p, v, age, life, s0, s1, seed, rot, spin, shade, wisp}
var _spawn_acc := 0.0
var _was_in := false
var _trail_t := 0.0
var _trail_acc := 0.0
var _t := 0.0


static func _shared() -> void:
	if _mat:
		return
	var sh := Shader.new()
	sh.code = SHADER % FX.BILLBOARD
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.render_priority = 2
	_quad = QuadMesh.new()
	_quad.size = Vector2(1, 1)
	_vent_mat = StandardMaterial3D.new()
	_vent_mat.albedo_color = Color(0.09, 0.09, 0.12)
	_vent_mat.roughness = 0.8


func _ready() -> void:
	_shared()
	add_to_group("smoke_zones")
	_build_vent()
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = _quad
	_mm.instance_count = _base_count() + WISPS
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.material_override = _mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-radius - 6, -1, -radius - 6), Vector3(radius * 2 + 12, TOP + 3, radius * 2 + 12))
	add_child(mmi)
	# 처음부터 가득 찬 상태로 시작한다
	for i in _base_count():
		var pf := _new_puff()
		pf.age = randf() * pf.life
		pf.p.y += pf.v.y * pf.age
		_puffs.append(pf)


func _base_count() -> int:
	return int(BASE * clampf(radius * radius / 7.3, 0.6, 1.6))


## 바닥 통풍구: 어두운 원판 + 격자 살 + 희미한 테두리 고리
func _build_vent() -> void:
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.75
	cm.bottom_radius = 0.82
	cm.height = 0.06
	cm.radial_segments = 20
	disc.mesh = cm
	disc.material_override = _vent_mat
	disc.position.y = 0.03
	add_child(disc)
	for i in 5:
		Build.box(self, Vector3(1.25 - absf(i - 2) * 0.25, 0.03, 0.07), Vector3(0, 0.075, (i - 2) * 0.24), Color(0.28, 0.28, 0.33))
	var glow := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.6
	dm.bottom_radius = 0.6
	dm.height = 0.01
	glow.mesh = dm
	glow.material_override = Pal.flat()
	glow.set_instance_shader_parameter("tint", Color(0.55, 0.6, 0.85))
	glow.set_instance_shader_parameter("energy", 0.5)
	glow.position.y = 0.065
	add_child(glow)
	# 구역 경계: 바닥의 점선 고리 (판정 범위를 읽을 수 있게)
	for i in 28:
		var a := TAU * i / 28.0
		var seg := Build.box(self, Vector3(0.32, 0.012, 0.05), Vector3(sin(a), 0.012, cos(a)) * radius, Color(0.55, 0.6, 0.8), Vector3(0, rad_to_deg(a) + 90.0, 0), 0.6)
		seg.position.y = 0.012


func contains(p: Vector3, margin := 0.0) -> bool:
	var d := p - global_position
	return Vector2(d.x, d.z).length() < radius + margin and d.y < TOP


func _new_puff(wisp := false) -> Dictionary:
	var a := randf() * TAU
	var rr := sqrt(randf()) * radius * 0.85
	return {
		"p": Vector3(cos(a) * rr, randf_range(0.0, 0.25), sin(a) * rr),
		"v": Vector3(cos(a), 0, sin(a)) * randf_range(0.02, 0.12) + Vector3(0, randf_range(RISE.x, RISE.y), 0),
		"age": 0.0, "life": randf_range(LIFE.x, LIFE.y),
		"s0": randf_range(0.9, 1.3), "s1": randf_range(2.0, 2.8),
		"seed": randf(), "rot": randf() * TAU, "spin": randf_range(-0.25, 0.25),
		"shade": randf_range(0.82, 1.05), "wisp": wisp, "a": randf_range(0.82, 0.95),
	}


## 플레이어 몸에서 떨어져 나오는 연기 가닥: 움직이는 방향으로 끌려가다 느려지며 흩어진다
func _new_wisp(at: Vector3, vel: Vector3) -> Dictionary:
	var pf := _new_puff(true)
	pf.p = at - global_position + Vector3(randf_range(-0.25, 0.25), randf_range(0.2, 1.3), randf_range(-0.25, 0.25))
	pf.v = vel * randf_range(0.35, 0.55) + Vector3(randf_range(-0.2, 0.2), randf_range(0.15, 0.45), randf_range(-0.2, 0.2))
	pf.life = randf_range(0.8, 1.3)
	pf.s0 = randf_range(0.7, 1.0)
	pf.s1 = randf_range(1.5, 2.2)
	pf.a = randf_range(0.65, 0.85)
	return pf


func _process(dt: float) -> void:
	# 화면 밖 먼 구역은 덩이를 멈춰 둔다 (맵 전체 구역이 매 프레임 덩이 100여 개씩 계산·업로드하던 것)
	if not _was_in and _trail_t <= 0.0 and Cull.far(global_position, radius):
		return
	_t += dt
	var player: Player = Main.inst.player if is_instance_valid(Main.inst) else null
	var pp := Vector3.INF
	var pv := Vector3.ZERO
	if is_instance_valid(player) and player.alive:
		pp = player.global_position
		pv = Vector3(player.velocity.x, 0, player.velocity.z) + player.carry
	# 꼬리: 구역을 빠져나가는 순간부터 TRAIL_TIME 동안
	var inside := pp != Vector3.INF and contains(pp)
	if _was_in and not inside and pp != Vector3.INF:
		_trail_t = TRAIL_TIME
		for i in 6:
			_puffs.append(_new_wisp(pp, pv))
	_was_in = inside
	if _trail_t > 0.0 and pp != Vector3.INF:
		_trail_t -= dt
		_trail_acc += dt
		var speed := pv.length()
		if speed > 1.0 and _trail_acc >= TRAIL_GAP:
			_trail_acc = 0.0
			# 처음엔 두툼하게 끌려 나오고 점점 가늘어진다
			var k := _trail_t / TRAIL_TIME
			for i in (2 if k > 0.5 else 1):
				_puffs.append(_new_wisp(pp - pv.normalized() * randf_range(0.0, 0.5), pv))
	elif inside and pv.length() > 2.0:
		# 안에서 움직이면 몸 둘레 연기가 휘저어진다
		_trail_acc += dt
		if _trail_acc >= TRAIL_GAP * 2.5:
			_trail_acc = 0.0
			_puffs.append(_new_wisp(pp, pv * 0.6))
	# 기본 덩이 보충
	var base := 0
	for pf in _puffs:
		if not pf.wisp:
			base += 1
	_spawn_acc += dt * _base_count() / ((LIFE.x + LIFE.y) * 0.5)
	while _spawn_acc >= 1.0:
		_spawn_acc -= 1.0
		if base < _base_count():
			_puffs.append(_new_puff())
			base += 1
	var local_p := pp - global_position if pp != Vector3.INF else Vector3.INF
	var keep: Array = []
	var wisps := 0
	for pf in _puffs:
		pf.age += dt
		if pf.age >= pf.life or pf.p.y > TOP + 0.5:
			continue
		if pf.wisp:
			wisps += 1
			if wisps > WISPS:
				continue
			pf.v.x *= exp(-2.4 * dt)
			pf.v.z *= exp(-2.4 * dt)
			pf.v.y = lerpf(pf.v.y, 0.35, 1.0 - exp(-2.0 * dt))
		elif local_p != Vector3.INF:
			# 끌림: 지나가는 몸이 가까운 덩이를 밀고 간다
			var d: Vector3 = pf.p - local_p
			d.y = (pf.p.y - 0.9) * 0.6
			var l := d.length()
			if l < 1.5:
				var push: Vector3 = pv * 0.9 * (1.0 - l / 1.5)
				pf.v.x = lerpf(pf.v.x, push.x, 1.0 - exp(-4.0 * dt))
				pf.v.z = lerpf(pf.v.z, push.z, 1.0 - exp(-4.0 * dt))
			else:
				pf.v.x *= exp(-0.8 * dt)
				pf.v.z *= exp(-0.8 * dt)
		pf.p += pf.v * dt
		pf.rot += pf.spin * dt
		keep.append(pf)
	_puffs = keep
	_draw()


func _draw() -> void:
	var n := mini(_puffs.size(), _mm.instance_count)
	_mm.visible_instance_count = n
	for i in n:
		var pf: Dictionary = _puffs[i]
		var u: float = pf.age / pf.life
		var s: float = lerpf(pf.s0, pf.s1, 1.0 - pow(1.0 - u, 2.0))
		var a: float = pf.a * smoothstep(0.0, 0.12, u) * (1.0 - smoothstep(0.6, 1.0, u))
		if not pf.wisp:
			a *= 1.0 - smoothstep(TOP - 0.9, TOP, pf.p.y)
		_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * s), pf.p))
		_mm.set_instance_color(i, Color(pf.shade, 0, 0, 1))
		_mm.set_instance_custom_data(i, Color(a, pf.seed, pf.rot, 0))
