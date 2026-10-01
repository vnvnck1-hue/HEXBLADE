class_name StylizedExplosion
extends Node3D
## 스타일라이즈드 화염 폭발 (연출 전용, 게임 판정과 무관).
## 진행: 흰 섬광 → 불덩이와 불꽃 혀 → 반투명 돔과 바닥 링 → 불붙은 파편이 연기 꼬리를 끌며 튐
##       → 불덩이가 식어 검은 연기로 바뀌고 부서지며 사라짐 → 잔불이 떠다니다 꺼짐.
## 불·연기 구체는 MultiMesh 한 개로 그린다. 인스턴스 데이터 = (열기, 소멸도, 시드, 0).
## 열기 1 이상 흰빛 → 0.8 노랑 → 0.55 주황 → 0.35 빨강 → 0 검은 연기.
## 호출: StylizedExplosion.spawn(parent, pos, k) 또는 FX.fire_explosion(pos, k). k = 크기 배율(1 ≈ 반경 1.6m).
## 게임 시간(_process delta)으로 진행하므로 히트스탑·슬로모션에 함께 느려진다.

const BASE_R := 1.6
const MAX_PUFFS := 320
const EMBER := 1

static var _puff_mesh: SphereMesh
static var _fire_mat: ShaderMaterial
static var _dome_mesh: SphereMesh
static var _dome_mat: ShaderMaterial
static var _quad: QuadMesh
static var _ring_mat: ShaderMaterial
static var _scorch_mat: ShaderMaterial

const NOISE := """
float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
"""

const FIRE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
varying vec4 v_data;
varying vec3 v_np;
varying vec3 v_wn;
%s
// 열기 → 색. 뜨거울수록 1.1 을 넘겨 글로우가 걸린다.
vec3 ramp(float h) {
	vec3 c = vec3(0.011, 0.01, 0.013);
	c = mix(c, vec3(0.032, 0.027, 0.033), smoothstep(0.0, 0.14, h));
	c = mix(c, vec3(0.42, 0.045, 0.02), smoothstep(0.16, 0.3, h));
	c = mix(c, vec3(1.0, 0.22, 0.04), smoothstep(0.3, 0.45, h));
	c = mix(c, vec3(1.0, 0.5, 0.06), smoothstep(0.45, 0.63, h));
	c = mix(c, vec3(1.0, 0.8, 0.18), smoothstep(0.63, 0.83, h));
	c = mix(c, vec3(1.0, 0.97, 0.8), smoothstep(0.83, 1.05, h));
	return c * (1.0 + 1.7 * smoothstep(0.5, 1.2, h));
}
void vertex() {
	v_data = INSTANCE_CUSTOM;
	vec3 sp = NORMAL * 2.1 + vec3(v_data.z * 37.0, v_data.z * 11.0, v_data.z * 23.0);
	v_np = sp;
	// 울퉁불퉁한 덩어리 실루엣
	VERTEX += NORMAL * (noise3(sp) - 0.5) * 0.26;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	float heat = v_data.x;
	float dis = v_data.y;
	float n = noise3(v_np * 1.1);
	if (n < dis) discard;
	// 2단 툰 음영: 위쪽이 밝고 아래쪽이 어둡다
	float nl = dot(normalize(v_wn), normalize(vec3(-0.35, 1.0, 0.45)));
	float band = nl > 0.3 ? 1.0 : (nl > -0.3 ? 0.55 : 0.22);
	vec3 c = ramp(heat + (band - 0.55) * 0.24);
	float smoke = 1.0 - smoothstep(0.1, 0.28, heat);
	c *= mix(1.0, mix(0.5, 1.6, band), smoke);
	// 식어 가는 덩어리가 부서지는 경계에 불씨 테두리
	float edge = step(n, dis + 0.06) * step(0.02, dis) * smoothstep(0.12, 0.3, heat);
	c = mix(c, vec3(1.0, 0.42, 0.07) * 1.9, edge);
	ALBEDO = c;
}
"""

const DOME_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, depth_draw_never, blend_mix;
instance uniform float fade = 1.0;
void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(f, 2.4);
	ALBEDO = mix(vec3(1.0, 0.45, 0.1), vec3(1.0, 0.85, 0.45), rim) * (1.0 + rim * 1.3);
	ALPHA = clamp((0.1 + rim * 0.85) * fade, 0.0, 1.0);
}
"""

const RING_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, blend_mix;
instance uniform float progress = 0.0;
instance uniform float fade = 1.0;
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	if (r > 1.0) discard;
	float p = clamp(progress, 0.0, 1.0);
	float R = 0.15 + 0.85 * (1.0 - pow(1.0 - p, 3.0));
	float w = mix(0.1, 0.025, p);
	float band = 1.0 - smoothstep(w * 0.5, w, abs(r - R));
	float band2 = (1.0 - smoothstep(w * 0.3, w * 0.6, abs(r - R * 0.9))) * 0.5;
	float inner = (1.0 - smoothstep(0.0, R, r)) * 0.3 * (1.0 - p);
	ALBEDO = vec3(1.0, 0.5, 0.14) * (1.0 + band * 1.3);
	ALPHA = clamp(max(band, band2) + inner, 0.0, 1.0) * fade;
}
"""

const SCORCH_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, blend_mix;
instance uniform float fade = 1.0;
instance uniform float hot = 1.0;
instance uniform float seed = 0.0;
%s
void fragment() {
	vec2 d = UV - 0.5;
	float r = length(d) * 2.0;
	float n = noise3(vec3(d * 7.0, seed * 13.0));
	float shape = 1.0 - smoothstep(0.35, 0.95, r + (n - 0.5) * 0.45);
	float core = (1.0 - smoothstep(0.0, 0.45, r + (n - 0.5) * 0.3)) * hot;
	ALBEDO = mix(vec3(0.03, 0.025, 0.035), vec3(1.0, 0.45, 0.08) * 2.0, core);
	ALPHA = clamp(shape * 0.6 + core, 0.0, 1.0) * fade;
}
"""


class Puff:
	var pos: Vector3
	var vel: Vector3
	var rot: Basis
	var age := 0.0         # 음수면 대기 중
	var life := 1.0
	var size := 1.0
	var grow := 0.2        # 수명 중 최대 크기까지 커지는 구간 비율
	var shrink_from := 0.6 # 이 비율부터 작아진다
	var end_scale := 0.3
	var heat0 := 1.0
	var heat1 := 0.0
	var cool := 1.0        # 열기 감소 곡선 지수 (작을수록 빨리 식음)
	var dis_from := 0.5    # 이 비율부터 부서지며 사라진다
	var drag := 2.0
	var grav := 0.0
	var buoy := 0.0
	var stretch := 0.0     # 속도 방향으로 늘어나는 정도 (불꽃 혀)
	var seed := 0.0
	var trail := 0.0       # 연기 꼬리 생성 간격(초). 0 이면 없음
	var trail_t := 0.0
	var kind := 0
	var heat := 1.0


var k := 1.0
var floor_y := 0.0
var t := 0.0
var puffs: Array[Puff] = []
var mm: MultiMesh
var dome: MeshInstance3D
var ring: MeshInstance3D
var scorch: MeshInstance3D
var light: OmniLight3D
var R := BASE_R
var rng := RandomNumberGenerator.new()
var _scorch_z := 0.0       # 흐르는 씬: 폭발 본체(공기처럼 늦게 흐름)보다 그을음(도로와 함께 흐름)이 앞서 간 거리


static func spawn(parent: Node3D, pos: Vector3, scale_k := 1.0, ground_y := 0.0, seed := -1) -> StylizedExplosion:
	var e := StylizedExplosion.new()
	e.k = scale_k
	e.floor_y = ground_y
	if seed >= 0:
		e.rng.seed = seed
	else:
		e.rng.randomize()
	parent.add_child(e)
	e.global_position = pos
	e._start()
	return e


static func _shared() -> void:
	if _fire_mat != null:
		return
	_puff_mesh = SphereMesh.new()
	_puff_mesh.radius = 0.5
	_puff_mesh.height = 1.0
	_puff_mesh.radial_segments = 22
	_puff_mesh.rings = 11
	var fs := Shader.new()
	fs.code = FIRE_SHADER % NOISE
	_fire_mat = ShaderMaterial.new()
	_fire_mat.shader = fs
	_dome_mesh = SphereMesh.new()
	_dome_mesh.radius = 0.5
	_dome_mesh.height = 1.0
	_dome_mesh.radial_segments = 40
	_dome_mesh.rings = 20
	var ds := Shader.new()
	ds.code = DOME_SHADER
	_dome_mat = ShaderMaterial.new()
	_dome_mat.shader = ds
	_quad = QuadMesh.new()
	_quad.orientation = PlaneMesh.FACE_Y
	var rs := Shader.new()
	rs.code = RING_SHADER
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = rs
	var ss := Shader.new()
	ss.code = SCORCH_SHADER % NOISE
	_scorch_mat = ShaderMaterial.new()
	_scorch_mat.shader = ss


func _rf(a: float, b: float) -> float:
	return rng.randf_range(a, b)


func _dir_up(min_y: float, max_y: float) -> Vector3:
	var a := rng.randf() * TAU
	var y := _rf(min_y, max_y)
	var h := sqrt(maxf(0.0, 1.0 - y * y))
	return Vector3(cos(a) * h, y, sin(a) * h)


func _rand_basis() -> Basis:
	return Basis(Quaternion.from_euler(Vector3(_rf(-PI, PI), _rf(-PI, PI), _rf(-PI, PI))))


func _add(p: Puff) -> void:
	if puffs.size() >= MAX_PUFFS:
		return
	if p.seed == 0.0:
		p.seed = rng.randf()
	p.rot = _rand_basis()
	puffs.append(p)


func _start() -> void:
	_shared()
	R = BASE_R * k
	var g := Vector3(0, floor_y - global_position.y, 0)  # 로컬 좌표의 바닥
	var c0 := g + Vector3(0, R * 0.5, 0)                # 불덩이 중심

	var mmi := MultiMeshInstance3D.new()
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _puff_mesh
	mm.instance_count = MAX_PUFFS
	mm.visible_instance_count = 0
	mmi.multimesh = mm
	mmi.material_override = _fire_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-R * 5, g.y - 1.0, -R * 5), Vector3(R * 10, R * 8, R * 10))
	add_child(mmi)

	# 1. 흰 섬광 핵
	var p := Puff.new()
	p.pos = c0
	p.size = R * 1.15
	p.life = 0.16
	p.grow = 0.3
	p.shrink_from = 0.45
	p.end_scale = 0.5
	p.heat0 = 1.35
	p.heat1 = 1.0
	p.dis_from = 2.0
	_add(p)

	# 2. 불덩이: 섬광 뒤로 부풀었다가 식어 검은 연기가 되어 부서진다
	for i in 16:
		var d := _dir_up(0.05, 1.0)
		p = Puff.new()
		p.pos = c0 + d * R * _rf(0.05, 0.4)
		p.vel = d * R * _rf(2.2, 4.2)
		p.drag = 6.5
		p.buoy = R * 0.5
		p.size = R * _rf(0.55, 0.85)
		p.age = -_rf(0.0, 0.05)
		p.life = _rf(0.9, 1.25)
		p.grow = 0.08
		p.heat0 = _rf(1.05, 1.2)
		p.heat1 = -0.12
		p.cool = 0.55
		p.shrink_from = 0.45
		p.end_scale = 0.2
		p.dis_from = 0.6
		_add(p)

	# 3. 불꽃 혀: 빠르게 뻗으며 늘어나는 붉은 화염
	for i in 12:
		var d := _dir_up(0.15, 0.95)
		p = Puff.new()
		p.pos = c0 + d * R * 0.3
		p.vel = d * R * _rf(7.0, 11.0)
		p.drag = 7.5
		p.stretch = 2.8
		p.size = R * _rf(0.18, 0.28)
		p.age = -_rf(0.02, 0.06)
		p.life = _rf(0.3, 0.45)
		p.grow = 0.15
		p.heat0 = _rf(0.42, 0.54)
		p.heat1 = 0.28
		p.shrink_from = 0.3
		p.end_scale = 0.1
		p.dis_from = 0.35
		_add(p)

	# 4. 불붙은 파편: 포물선으로 튀며 연기 꼬리를 남긴다
	for i in 7:
		var d := _dir_up(0.55, 0.95)
		p = Puff.new()
		p.pos = c0 + d * R * 0.25
		p.vel = d * R * _rf(3.8, 6.2)
		p.drag = 0.6
		p.grav = -9.0 * sqrt(k)
		p.size = R * _rf(0.15, 0.21)
		p.age = -_rf(0.05, 0.12)
		p.life = _rf(0.85, 1.25)
		p.grow = 0.08
		p.heat0 = 1.0
		p.heat1 = 0.5
		p.shrink_from = 0.7
		p.end_scale = 0.2
		p.dis_from = 2.0
		p.trail = 0.022
		_add(p)

	# 5. 바닥 연기: 조금 늦게 퍼져 오래 남는 어두운 덩어리
	for i in 10:
		var d := _dir_up(0.0, 0.25)
		p = Puff.new()
		p.pos = g + Vector3(d.x, 0, d.z) * R * _rf(0.2, 0.9) + Vector3(0, R * _rf(0.2, 0.45), 0)
		p.vel = Vector3(d.x, 0.2, d.z) * R * _rf(0.5, 1.1)
		p.drag = 1.6
		p.buoy = R * 0.25
		p.size = R * _rf(0.38, 0.62)
		p.age = -_rf(0.15, 0.3)
		p.life = _rf(1.5, 2.1)
		p.grow = 0.12
		p.heat0 = _rf(0.2, 0.3)
		p.heat1 = -0.05
		p.cool = 0.3
		p.shrink_from = 0.45
		p.end_scale = 0.15
		p.dis_from = 0.65
		_add(p)

	# 6. 잔불: 떠다니며 깜빡이는 작은 불씨
	for i in 28:
		var d := _dir_up(0.1, 1.0)
		p = Puff.new()
		p.kind = EMBER
		p.pos = c0 + d * R * _rf(0.1, 0.6)
		p.vel = d * R * _rf(1.5, 5.5)
		p.drag = 1.8
		p.grav = -2.0
		p.buoy = 1.2
		p.size = _rf(0.06, 0.12) * sqrt(k)
		p.age = -_rf(0.05, 0.45)
		p.life = _rf(0.9, 2.2)
		p.grow = 0.05
		p.heat0 = 1.15
		p.heat1 = 0.6
		p.shrink_from = 0.6
		p.end_scale = 0.0
		p.dis_from = 2.0
		_add(p)

	# 7. 폭심에 남는 불씨 덩어리
	for i in 3:
		p = Puff.new()
		p.kind = EMBER
		p.pos = g + Vector3(_rf(-0.3, 0.3) * R, R * 0.06, _rf(-0.3, 0.3) * R)
		p.size = R * _rf(0.09, 0.15)
		p.age = -_rf(0.3, 0.5)
		p.life = _rf(1.8, 2.4)
		p.heat0 = 1.1
		p.heat1 = 0.55
		p.shrink_from = 0.7
		p.end_scale = 0.0
		p.dis_from = 2.0
		_add(p)

	dome = MeshInstance3D.new()
	dome.mesh = _dome_mesh
	dome.material_override = _dome_mat
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dome.position = g
	dome.visible = false
	add_child(dome)

	ring = MeshInstance3D.new()
	ring.mesh = _quad
	ring.material_override = _ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = g + Vector3(0, 0.04, 0)
	ring.scale = Vector3.ONE * R * 2.6 * 2.0
	ring.visible = false
	add_child(ring)

	scorch = MeshInstance3D.new()
	scorch.mesh = _quad
	scorch.material_override = _scorch_mat
	scorch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scorch.position = g + Vector3(0, 0.03, 0)
	scorch.scale = Vector3.ONE * R * 2.4
	scorch.set_instance_shader_parameter("seed", rng.randf())
	scorch.visible = false
	add_child(scorch)

	light = OmniLight3D.new()
	light.position = c0
	light.light_color = Color(1.0, 0.6, 0.25)
	light.omni_range = R * 4.5
	light.light_energy = 0.0
	add_child(light)


func _process(dt: float) -> void:
	t += dt
	# 그을음은 도로에 붙어 있어 운반 노드(WorldFlow.AIR)보다 먼저 도로 속도로 흘러간다
	_scorch_z += WorldFlow.road_v() * exp(-WorldFlow.AIR * t) * dt
	scorch.position.z = _scorch_z
	_update_layers()
	var i := 0
	while i < puffs.size():
		var p := puffs[i]
		p.age += dt
		if p.age >= p.life:
			puffs.remove_at(i)
			continue
		if p.age >= 0.0:
			p.vel.y += (p.grav + p.buoy) * dt
			p.vel *= exp(-p.drag * dt)
			p.pos += p.vel * dt
			var u := p.age / p.life
			p.heat = lerpf(p.heat0, p.heat1, pow(u, p.cool))
			if p.trail > 0.0:
				p.trail_t -= dt
				if p.trail_t <= 0.0:
					p.trail_t += p.trail
					_trail(p, u)
		i += 1
	_draw_puffs()
	if t > 0.5 and puffs.is_empty() and t > 2.6:
		queue_free()


func _trail(h: Puff, u: float) -> void:
	var p := Puff.new()
	p.pos = h.pos + Vector3(_rf(-0.05, 0.05), _rf(-0.05, 0.05), _rf(-0.05, 0.05)) * R
	p.vel = h.vel * 0.06 + Vector3(0, 0.3, 0)
	p.drag = 3.0
	p.buoy = 0.4
	p.size = h.size * _rf(0.75, 1.15) * (1.0 - u * 0.4)
	p.life = _rf(0.4, 0.7)
	p.grow = 0.25
	p.heat0 = h.heat * 0.7
	p.heat1 = -0.1
	p.cool = 0.35
	p.shrink_from = 0.3
	p.end_scale = 0.1
	p.dis_from = 0.7
	_add(p)


func _size_curve(p: Puff, u: float) -> float:
	var s := 1.0
	if u < p.grow:
		var x := u / p.grow
		s = 1.0 - pow(1.0 - x, 3.0) + sin(x * PI) * 0.12
	if u > p.shrink_from:
		var x := (u - p.shrink_from) / (1.0 - p.shrink_from)
		s *= lerpf(1.0, p.end_scale, x * x)
	return s


func _draw_puffs() -> void:
	var n := 0
	for p in puffs:
		if p.age < 0.0:
			continue
		var u := p.age / p.life
		var s := p.size * _size_curve(p, u)
		var heat := p.heat
		if p.kind == EMBER:
			heat += sin(p.age * 38.0 + p.seed * 20.0) * 0.18
		var b: Basis
		var speed := p.vel.length()
		if p.stretch > 0.0 and speed > 0.01:
			var el := 1.0 + p.stretch * clampf(speed / (R * 6.0), 0.0, 1.2)
			var dir := p.vel / speed
			b = Basis(Quaternion(Vector3(0.0001, 1, 0).normalized(), dir)) * Basis.from_scale(Vector3(s, s * el, s))
		else:
			b = p.rot.scaled(Vector3.ONE * s)
		var dis := smoothstep(p.dis_from, 1.0, u) * 0.95 if p.dis_from < 1.0 else 0.0
		mm.set_instance_transform(n, Transform3D(b, p.pos))
		mm.set_instance_custom_data(n, Color(heat, dis, p.seed, 0.0))
		n += 1
	mm.visible_instance_count = n


func _update_layers() -> void:
	# 돔: 빠르게 부풀며 가장자리만 남기고 사라진다
	var dt0 := t - 0.03
	var dd := 0.6
	dome.visible = dt0 > 0.0 and dt0 < dd
	if dome.visible:
		var x := dt0 / dd
		var r := R * lerpf(0.7, 2.2, 1.0 - pow(1.0 - x, 3.0))
		dome.scale = Vector3.ONE * r * 2.0
		dome.set_instance_shader_parameter("fade", minf(1.0, x * 8.0) * pow(1.0 - x, 1.6))
	# 바닥 링
	var rt := t - 0.02
	var rd := 0.85
	ring.visible = rt > 0.0 and rt < rd
	if ring.visible:
		var x := rt / rd
		ring.set_instance_shader_parameter("progress", x)
		ring.set_instance_shader_parameter("fade", pow(1.0 - x, 1.3))
	# 그을음: 달아올랐다가 식고, 천천히 옅어진다
	var st := t - 0.05
	var sd := 3.0
	scorch.visible = st > 0.0 and st < sd
	if scorch.visible:
		var x := st / sd
		scorch.set_instance_shader_parameter("hot", pow(maxf(0.0, 1.0 - x * 3.0), 2.0))
		scorch.set_instance_shader_parameter("fade", 1.0 - smoothstep(0.55, 1.0, x))
	# 조명
	var lt := clampf(t / 0.7, 0.0, 1.0)
	light.light_energy = 9.0 * pow(1.0 - lt, 2.2) * minf(1.0, t * 40.0)
