extends Node3D
## 연출 전용: 용광로 쇳물이 액체처럼 튀어 오르고 흘러내리는 스플래시.
## 게임 판정과 무관하며, 위치만 받아 스스로 시뮬레이션·수명을 끝낸다.
##
## 관성 표현 요소
##  - 줄기(tendril): 같은 방향 · 서로 다른 속도의 방울 사슬. 이웃 방울 사이를 '목'으로 이어 그리므로
##    처음엔 한 줄기 액체였다가, 늘어날수록 목이 가늘어지고 결국 끊어져 방울로 흩어진다.
##  - 방울은 속도 방향으로 늘어나고(속도 ∝ 길이, 부피 보존으로 가늘어짐) 막 튀어나온 순간 출렁인다.
##  - 공기 저항 + 무거운 중력: 꼭짓점에서 잠깐 머물다 가속하며 떨어진다.
##  - 착지하면 수평 속도를 이어받아 바닥을 미끄러지고, 스프링처럼 넘쳐 퍼졌다가 굳는다.

@export var gravity := -30.0
@export var air_drag := 0.9          # 초당 감쇠 (클수록 꼭짓점에서 오래 머문다)
@export var stretch_k := 0.07        # 속도당 늘어나는 비율
@export var stretch_max := 3.0
@export var cool_rate := 0.75        # 방울 식는 속도 (초당 heat 감소)
@export var neck_break := 3.3        # 목 길이가 두 방울 반지름 합의 몇 배가 되면 끊어지나
@export var slide_friction := 4.5    # 바닥 미끄럼 감쇠
@export var splat_spring := 190.0
@export var splat_damp := 11.0

const DROP_CAP := 1600
const SPLAT_CAP := 700
const STRIDE := 16                   # 3x4 변환 12 + custom 4

## 바닥 높이 (위치 → y). 발판 밖이면 용암 높이 등을 돌려준다.
var ground_fn: Callable = func(_p: Vector3) -> float: return 0.0

var _drop_mm: MultiMesh
var _splat_mm: MultiMesh
var _drop_buf := PackedFloat32Array()
var _splat_buf := PackedFloat32Array()

# 방울 상태: 고정 슬롯 풀 (목 연결이 슬롯 번호를 가리키므로 자리를 옮기지 않는다)
var _hi := 0                         # 사용한 적 있는 최고 슬롯 + 1
var _free := PackedInt32Array()
var _live := PackedByteArray()
var _gen := PackedInt32Array()       # 슬롯 재사용 세대 (끊긴 연결 판별)
var _dp := PackedVector3Array()
var _dv := PackedVector3Array()
var _dr := PackedFloat32Array()
var _dh := PackedFloat32Array()
var _da := PackedFloat32Array()      # 나이
var _lk := PackedInt32Array()        # 앞 방울 슬롯 (-1: 연결 없음)
var _lg := PackedInt32Array()        # 연결 당시 앞 방울 세대
var _lb := PackedFloat32Array()      # 이 연결이 끊어지는 배율

# 바닥 자국 상태 (순서 무관, swap-remove)
var _sn := 0
var _sp := PackedVector3Array()      # y 는 바닥 높이
var _sv := PackedVector3Array()      # 미끄럼 속도 (xz)
var _ss := PackedFloat32Array()      # 현재 크기
var _ssv := PackedFloat32Array()     # 크기 변화 속도 (스프링)
var _st := PackedFloat32Array()      # 목표 크기
var _sh := PackedFloat32Array()      # heat
var _sl := PackedFloat32Array()      # 남은 수명
var _sL := PackedFloat32Array()      # 전체 수명
var _sd := PackedFloat32Array()      # 늘어난 방향 각
var _sk := PackedFloat32Array()      # 시드

var _dome_mesh: SphereMesh
var _dome_mat: ShaderMaterial


const DROP_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
varying float heat;
void vertex() { heat = INSTANCE_CUSTOM.r; }
void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float h = clamp(heat, 0.0, 1.0);
	vec3 white = vec3(1.0, 0.9, 0.45);
	vec3 yel = vec3(1.0, 0.66, 0.1);
	vec3 ora = vec3(1.0, 0.36, 0.05);
	vec3 red = vec3(0.72, 0.12, 0.03);
	vec3 crust = vec3(0.24, 0.05, 0.03);
	vec3 core = mix(ora, mix(yel, white, smoothstep(0.8, 1.0, h)), smoothstep(0.25, 0.8, h));
	vec3 mid = mix(red, ora, smoothstep(0.1, 0.6, h));
	vec3 rim = mix(crust, red * 0.7, smoothstep(0.1, 0.6, h));
	float b1 = smoothstep(0.34, 0.40, f);
	float b2 = smoothstep(0.74, 0.80, f);
	vec3 col = mix(mix(core, mid, b1), rim, b2);
	float e = mix(0.9, 1.7, h) * mix(1.0, 0.75, b1);
	ALBEDO = col * e;
	ROUGHNESS = 0.0;
}
"""

const SPLAT_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, blend_mix;
varying vec4 cd;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() { cd = INSTANCE_CUSTOM; }
void fragment() {
	vec2 c = (UV - 0.5) * 2.0;
	float r = length(c);
	float ang = atan(c.y, c.x);
	float n = vnoise(vec2(cos(ang), sin(ang)) * 1.8 + cd.g * 37.0) * 0.6 + vnoise(c * 3.2 + cd.g * 11.0) * 0.4;
	float edge = 0.58 + 0.42 * n;
	if (r > edge) discard;
	float rr = r / edge;
	float h = clamp(cd.r, 0.0, 1.0);
	vec3 hot = mix(vec3(1.0, 0.34, 0.05), vec3(1.0, 0.8, 0.3), smoothstep(0.8, 0.1, rr) * h);
	vec3 col = mix(vec3(0.3, 0.07, 0.04), hot, smoothstep(0.0, 0.45, h));
	col = mix(col, vec3(0.45, 0.08, 0.03) * (0.4 + h), smoothstep(0.8, 0.86, rr));
	float cn = vnoise(c * 4.5 + cd.g * 5.0);
	col = mix(col, vec3(0.11, 0.06, 0.06), smoothstep(0.55, 0.7, (1.0 - h) * 0.9 + cn * 0.35));
	ALBEDO = col * (1.0 + 1.1 * h);
	ALPHA = cd.b;
	ROUGHNESS = 0.0;
}
"""

const DOME_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, blend_add;
instance uniform float fade = 1.0;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	if (lp.y < 0.0) discard;
	float f = 1.0 - abs(dot(NORMAL, VIEW));
	float a = smoothstep(0.72, 0.97, f) * 0.9 + pow(f, 3.0) * 0.12;
	a *= smoothstep(0.0, 0.06, lp.y);
	vec3 col = mix(vec3(1.0, 0.25, 0.04), vec3(1.0, 0.55, 0.15), f);
	ALBEDO = col * a * fade * 1.3;
	ROUGHNESS = 0.0;
}
"""


func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 12
	sphere.rings = 7
	var dm := ShaderMaterial.new()
	dm.shader = Shader.new()
	dm.shader.code = DROP_SHADER
	sphere.material = dm
	# 방울 + 목 브리지를 같은 멀티메시에 그린다
	_drop_mm = _make_mm(sphere, DROP_CAP * 2)
	_drop_buf.resize(DROP_CAP * 2 * STRIDE)

	var quad := QuadMesh.new()
	quad.orientation = PlaneMesh.FACE_Y
	quad.size = Vector2(1, 1)
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = SPLAT_SHADER
	sm.render_priority = 1
	quad.material = sm
	_splat_mm = _make_mm(quad, SPLAT_CAP)
	_splat_buf.resize(SPLAT_CAP * STRIDE)

	# Packed 배열은 값 타입이라 하나씩 직접 늘린다
	_live.resize(DROP_CAP); _gen.resize(DROP_CAP)
	_dp.resize(DROP_CAP); _dv.resize(DROP_CAP)
	_dr.resize(DROP_CAP); _dh.resize(DROP_CAP); _da.resize(DROP_CAP)
	_lk.resize(DROP_CAP); _lg.resize(DROP_CAP); _lb.resize(DROP_CAP)
	_sp.resize(SPLAT_CAP); _sv.resize(SPLAT_CAP)
	_ss.resize(SPLAT_CAP); _ssv.resize(SPLAT_CAP); _st.resize(SPLAT_CAP); _sh.resize(SPLAT_CAP)
	_sl.resize(SPLAT_CAP); _sL.resize(SPLAT_CAP); _sd.resize(SPLAT_CAP); _sk.resize(SPLAT_CAP)

	_dome_mesh = SphereMesh.new()
	_dome_mesh.radius = 0.5
	_dome_mesh.height = 1.0
	_dome_mesh.radial_segments = 40
	_dome_mesh.rings = 20
	_dome_mat = ShaderMaterial.new()
	_dome_mat.shader = Shader.new()
	_dome_mat.shader.code = DOME_SHADER


func _make_mm(mesh: Mesh, cap: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = cap
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-200, -50, -200), Vector3(400, 150, 400))
	add_child(mi)
	return mm


# ── 공개 연출 ───────────────────────────────────────────

## 큰 내려찍기: 가운데 기둥 + 왕관 줄기 + 낮게 깔리는 막 + 미세 비말 + 반구 충격막.
## push 는 내려친 쪽의 수평 방향 (그쪽으로 쇳물이 더 많이, 더 멀리 쏠린다).
func burst(pos: Vector3, k := 1.0, push := Vector3.ZERO) -> void:
	var o := Vector3(pos.x, ground_fn.call(pos) + 0.15, pos.z)
	var sk := sqrt(k)
	push.y = 0.0
	if push.length() > 0.01:
		push = push.normalized()
	# 가운데로 솟는 굵은 기둥
	for i in 3:
		var d := _cone_dir(Vector3.UP, deg_to_rad(randf_range(3.0, 18.0)))
		_tendril(o, d, randf_range(15.0, 19.5) * sk, 0.36 * sk, 11, 1.0, 0.42)
	# 왕관처럼 휘어 떨어지는 줄기
	var n_arc := 12
	var off := randf() * TAU
	for i in n_arc:
		var a := off + TAU * (i + randf_range(-0.3, 0.3)) / n_arc
		var h := Vector3(cos(a), 0, sin(a))
		var bias := 1.0 + 0.35 * maxf(0.0, h.dot(push))
		var el := deg_to_rad(randf_range(34.0, 66.0))
		_tendril(o, _elev(h, el), randf_range(10.0, 15.0) * sk * bias, 0.27 * sk, 8, 0.9, 0.45)
	# 바닥 가까이 쏜살같이 퍼지는 막 (착지 후 미끄러진다)
	var n_low := 14
	for i in n_low:
		var a := off + TAU * (i + 0.5 + randf_range(-0.35, 0.35)) / n_low
		var h := Vector3(cos(a), 0, sin(a))
		var bias := 1.0 + 0.45 * maxf(0.0, h.dot(push))
		_tendril(o, _elev(h, deg_to_rad(randf_range(8.0, 24.0))), randf_range(11.0, 18.0) * sk * bias, 0.19 * sk, 5, 0.85, 0.5)
	# 미세 비말
	for i in 26:
		var d := _cone_dir(Vector3.UP, deg_to_rad(randf_range(10.0, 82.0)))
		_drop(o, d * randf_range(7.0, 23.0) * sk, randf_range(0.06, 0.13) * sk, randf_range(0.6, 0.95))
	# 바닥으로 밀려 나가는 쇳물 물결
	for i in 14:
		var a := randf() * TAU
		var h := Vector3(cos(a), 0, sin(a))
		var bias := 1.0 + 0.5 * maxf(0.0, h.dot(push))
		_splat(o + h * 0.5, h * randf_range(6.0, 11.0) * sk * bias, randf_range(0.7, 1.2) * sk, 1.0, randf_range(1.6, 2.4))
	_splat(o, Vector3.ZERO, 3.6 * sk, 1.0, 2.6, 0.25)
	_dome(o, 5.0 * k, 0.42)
	_light(o + Vector3(0, 1.2, 0), 9.0 * k, 7.0, 0.45)


## 위에서 떨어진 쇳물 덩이가 바닥에 부딪혀 터지는 중간 크기 스플래시.
func impact(pos: Vector3, k := 1.0) -> void:
	var o := Vector3(pos.x, ground_fn.call(pos) + 0.1, pos.z)
	var sk := sqrt(k)
	var off := randf() * TAU
	for i in 10:
		var a := off + TAU * (i + randf_range(-0.3, 0.3)) / 10.0
		var h := Vector3(cos(a), 0, sin(a))
		_tendril(o, _elev(h, deg_to_rad(randf_range(38.0, 72.0))), randf_range(6.5, 10.0) * sk, 0.19 * sk, 6, 0.95, 0.45)
	for i in 8:
		var a := off + TAU * (i + 0.5) / 8.0
		_tendril(o, _elev(Vector3(cos(a), 0, sin(a)), deg_to_rad(randf_range(8.0, 20.0))), randf_range(8.0, 12.0) * sk, 0.15 * sk, 4, 0.9, 0.5)
	for i in 12:
		_drop(o, _cone_dir(Vector3.UP, deg_to_rad(randf_range(10.0, 75.0))) * randf_range(5.0, 15.0) * sk, randf_range(0.05, 0.1) * sk, 0.85)
	for i in 8:
		var a := randf() * TAU
		var h := Vector3(cos(a), 0, sin(a))
		_splat(o + h * 0.3, h * randf_range(4.0, 7.5) * sk, randf_range(0.5, 0.85) * sk, 1.0, randf_range(1.4, 2.0))
	_splat(o, Vector3.ZERO, 2.6 * sk, 1.0, 2.2, 0.25)
	_dome(o, 2.8 * k, 0.3)
	_light(o + Vector3(0, 1.0, 0), 5.0 * k, 5.0, 0.3)


## 바닥에서 솟구치는 쇳물 기둥 (용암 분출). 올라갔다 무겁게 되떨어지며 주변에 흩뿌린다.
func column(pos: Vector3, k := 1.0) -> void:
	var o := Vector3(pos.x, ground_fn.call(pos) + 0.1, pos.z)
	var sk := sqrt(k)
	for i in 2:
		_tendril(o, _cone_dir(Vector3.UP, deg_to_rad(randf_range(3.0, 14.0))), randf_range(13.0, 17.0) * sk, 0.27 * sk, 8, 1.0, 0.45)
	for i in 4:
		var a := randf() * TAU
		_tendril(o, _elev(Vector3(cos(a), 0, sin(a)), deg_to_rad(randf_range(50.0, 70.0))), randf_range(7.0, 10.0) * sk, 0.17 * sk, 4, 0.9, 0.5)
	for i in 6:
		_drop(o, _cone_dir(Vector3.UP, deg_to_rad(randf_range(5.0, 45.0))) * randf_range(6.0, 16.0) * sk, randf_range(0.05, 0.1) * sk, 0.85)
	_splat(o, Vector3.ZERO, 2.0 * sk, 1.0, 1.8, 0.3)


# ── 생성 ────────────────────────────────────────────────

## 방울 사슬 한 줄기: 맨 앞 방울이 가장 크고 빠르다(끝 방울). 뒤로 갈수록 느리고 가늘어서
## 날아가는 동안 사슬이 늘어나며 목이 가늘어지고 끊어진다. tail 은 맨 뒤 방울의 속도 비율.
func _tendril(o: Vector3, dir: Vector3, speed: float, r0: float, n: int, heat: float, tail: float) -> void:
	var prev := -1
	var wav := Vector3(randf_range(-1, 1), randf_range(-0.4, 0.4), randf_range(-1, 1)) * 0.16
	for i in n:
		var t := float(i) / maxf(1.0, n - 1)
		var sp := speed * lerpf(1.0, tail, pow(t, 0.9))
		var rr := r0 * (1.0 if i == 0 else lerpf(0.62, 0.34, t))
		# 줄기 전체가 살짝 휘도록 방향을 한쪽으로 조금씩 흘린다
		var d := (dir + wav * sin(t * PI) + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.01).normalized()
		var s := _drop(o + dir * 0.08 * (n - 1 - i), d * sp, rr, heat * lerpf(1.0, 0.8, t))
		if s >= 0 and prev >= 0:
			_lk[s] = prev
			_lg[s] = _gen[prev]
			_lb[s] = neck_break * randf_range(0.75, 1.25)
		prev = s


func _drop(p: Vector3, v: Vector3, r: float, heat: float) -> int:
	var s: int
	if not _free.is_empty():
		s = _free[_free.size() - 1]
		_free.resize(_free.size() - 1)
	elif _hi < DROP_CAP:
		s = _hi
		_hi += 1
	else:
		return -1
	_live[s] = 1
	_gen[s] += 1
	_dp[s] = p
	_dv[s] = v
	_dr[s] = r
	_dh[s] = heat
	_da[s] = 0.0
	_lk[s] = -1
	return s


func _kill(s: int) -> void:
	_live[s] = 0
	_gen[s] += 1
	_free.append(s)


func _splat(p: Vector3, slide: Vector3, size: float, heat: float, life: float, start := 0.3) -> void:
	if _sn >= SPLAT_CAP:
		# 수명이 가장 적게 남은 자리를 빼앗는다
		var worst := 0
		for i in _sn:
			if _sl[i] < _sl[worst]:
				worst = i
		_splat_remove(worst)
	var i := _sn
	_sp[i] = Vector3(p.x, ground_fn.call(p), p.z)   # 바닥 높이는 생성 때 한 번만
	slide.y = 0.0
	_sv[i] = slide
	_st[i] = size
	_ss[i] = size * start
	_ssv[i] = size * 6.0
	_sh[i] = heat
	_sl[i] = life
	_sL[i] = life
	_sd[i] = atan2(slide.x, slide.z) if slide.length() > 0.05 else randf() * TAU
	_sk[i] = randf()
	_sn += 1


func _dome(o: Vector3, size: float, dur: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _dome_mesh
	mi.material_override = _dome_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = Vector3(o.x, o.y - 0.15, o.z)
	mi.scale = Vector3.ONE * size * 0.25
	mi.set_instance_shader_parameter("fade", 1.0)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(size * 2.0, size * 1.5, size * 2.0), dur).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(v: float): mi.set_instance_shader_parameter("fade", v), 1.0, 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)


func _light(p: Vector3, energy: float, rng: float, dur: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.2)
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	add_child(l)
	l.global_position = p
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(l.queue_free)


func _cone_dir(axis: Vector3, ang: float) -> Vector3:
	var a := randf() * TAU
	var side := Vector3(cos(a), 0, sin(a))
	return (axis * cos(ang) + side * sin(ang)).normalized()


func _elev(h: Vector3, el: float) -> Vector3:
	return (h * cos(el) + Vector3.UP * sin(el)).normalized()


# ── 시뮬레이션 ──────────────────────────────────────────

func _process(dt: float) -> void:
	if dt <= 0.0:
		return
	_step_drops(dt)
	_step_splats(dt)


func _step_drops(dt: float) -> void:
	var drag := exp(-air_drag * dt)
	for i in _hi:
		if _live[i] == 0:
			continue
		var v := _dv[i]
		v.y += gravity * dt
		v *= drag
		var p := _dp[i] + v * dt
		var r := _dr[i]
		var h := maxf(0.0, _dh[i] - cool_rate * dt)
		var gy: float = ground_fn.call(p)
		if v.y < 0.0 and p.y - r * 0.4 <= gy:
			_land(Vector3(p.x, gy, p.z), v, r, h)
			_kill(i)
			continue
		var age := _da[i] + dt
		if age > 4.0 or p.y < -30.0:
			_kill(i)
			continue
		_dp[i] = p
		_dv[i] = v
		_da[i] = age
		_dh[i] = h
	var hi0 := _hi
	while _hi > 0 and _live[_hi - 1] == 0:
		_hi -= 1
	# 줄어든 _hi 위쪽 빈 슬롯은 풀 목록에서 뺀다 (다시 _hi 로 새로 받는다)
	if _hi == 0:
		_free.clear()
	elif _hi < hi0:
		var keep := PackedInt32Array()
		for s in _free:
			if s < _hi:
				keep.append(s)
		_free = keep

	var n := 0
	for j in _hi:
		if _live[j] == 0:
			continue
		var v := _dv[j]
		var sp := v.length()
		var age := _da[j]
		# 막 떨어져 나온 순간의 출렁임 (감쇠 진동)
		var wob := sin(age * 34.0 + float(j)) * exp(-age * 7.0) * 0.3
		var s := clampf(1.0 + sp * stretch_k, 1.0, stretch_max) * (1.0 + wob)
		var d := _dr[j] * 2.0
		_put(n, _dp[j], v / sp if sp > 0.01 else Vector3.UP, d / sqrt(s), d * s, _dh[j])
		n += 1
		# 앞 방울과 이어진 목
		var q := _lk[j]
		if q < 0:
			continue
		if _live[q] == 0 or _gen[q] != _lg[j]:
			_lk[j] = -1
			continue
		var a := _dp[j]
		var b := _dp[q]
		var ab := b - a
		var ln := ab.length()
		var rest := _dr[j] + _dr[q]
		var ratio := ln / maxf(0.001, rest)
		if ratio > _lb[j]:
			_lk[j] = -1          # 끊어짐: 이후로는 따로 나는 방울
			continue
		if ln < 0.01:
			continue
		# 늘어날수록 가늘어진다 (끊어지기 직전엔 실처럼)
		var thin := 1.0 - clampf((ratio - 1.0) / maxf(0.01, _lb[j] - 1.0), 0.0, 1.0)
		var w := minf(_dr[j], _dr[q]) * 2.0 * lerpf(0.28, 0.95, sqrt(thin))
		_put(n, (a + b) * 0.5, ab / ln, w, ln + w * 0.3, (_dh[j] + _dh[q]) * 0.5)
		n += 1
	_drop_mm.buffer = _drop_buf
	_drop_mm.visible_instance_count = n


## y 축을 dir 로 세운 타원체 하나를 버퍼 n 번째에 기록한다
func _put(n: int, p: Vector3, y: Vector3, width: float, length: float, heat: float) -> void:
	var ref := Vector3.RIGHT if absf(y.y) > 0.9 else Vector3.UP
	var x := y.cross(ref).normalized()
	var z := x.cross(y)
	var o := n * STRIDE
	_drop_buf[o] = x.x * width; _drop_buf[o + 1] = y.x * length; _drop_buf[o + 2] = z.x * width; _drop_buf[o + 3] = p.x
	_drop_buf[o + 4] = x.y * width; _drop_buf[o + 5] = y.y * length; _drop_buf[o + 6] = z.y * width; _drop_buf[o + 7] = p.y
	_drop_buf[o + 8] = x.z * width; _drop_buf[o + 9] = y.z * length; _drop_buf[o + 10] = z.z * width; _drop_buf[o + 11] = p.z
	_drop_buf[o + 12] = heat
	_drop_buf[o + 13] = 0.0
	_drop_buf[o + 14] = 0.0
	_drop_buf[o + 15] = 0.0


## 착지: 수평 속도를 이어받아 미끄러지는 자국을 남기고, 세게 부딪힌 굵은 방울은 작은 왕관을 튀긴다.
func _land(p: Vector3, v: Vector3, r: float, h: float) -> void:
	var hv := Vector3(v.x, 0, v.z)
	var impact := -v.y
	var size := r * 2.4 * (1.0 + minf(impact, 22.0) * 0.035)
	_splat(p, hv * 0.38, size, maxf(h, 0.3), randf_range(1.2, 1.9) + r * 3.0)
	if r > 0.15 and impact > 8.0:
		for k in 2 + randi() % 2:
			var a := randf() * TAU
			var d := Vector3(cos(a), 0, sin(a))
			_drop(p + Vector3(0, 0.05, 0), hv * 0.25 + d * randf_range(1.5, 3.0) + Vector3(0, randf_range(3.0, 5.5), 0), r * randf_range(0.25, 0.4), h)


func _step_splats(dt: float) -> void:
	var fr := exp(-slide_friction * dt)
	var i := 0
	while i < _sn:
		var l := _sl[i] - dt
		if l <= 0.0:
			_splat_remove(i)
			continue
		_sl[i] = l
		var v := _sv[i] * fr
		_sv[i] = v
		_sp[i] += v * dt
		# 스프링: 넘쳐 퍼졌다가 되돌아와 자리 잡는다
		var acc := splat_spring * (_st[i] - _ss[i]) - splat_damp * _ssv[i]
		_ssv[i] += acc * dt
		_ss[i] = maxf(0.02, _ss[i] + _ssv[i] * dt)
		_sh[i] = maxf(0.0, _sh[i] - 0.32 * dt)
		i += 1
	for j in _sn:
		var p := _sp[j]
		var gy := p.y
		var sp := _sv[j].length()
		var s := _ss[j]
		var el := 1.0 + minf(sp * 0.22, 1.6)
		var w := s / sqrt(el)
		var ln := s * el
		var a := _sd[j]
		var ca := cos(a)
		var sa := sin(a)
		# 로컬 z 축을 미끄럼 방향으로
		var xa := Vector3(ca, 0, -sa) * w
		var za := Vector3(sa, 0, ca) * ln
		var o := j * STRIDE
		_splat_buf[o] = xa.x; _splat_buf[o + 1] = 0.0; _splat_buf[o + 2] = za.x; _splat_buf[o + 3] = p.x
		_splat_buf[o + 4] = 0.0; _splat_buf[o + 5] = 1.0; _splat_buf[o + 6] = 0.0; _splat_buf[o + 7] = gy + 0.035 + float(j % 16) * 0.0012
		_splat_buf[o + 8] = xa.z; _splat_buf[o + 9] = 0.0; _splat_buf[o + 10] = za.z; _splat_buf[o + 11] = p.z
		_splat_buf[o + 12] = _sh[j]
		_splat_buf[o + 13] = _sk[j]
		_splat_buf[o + 14] = clampf(_sl[j] / minf(1.1, _sL[j]), 0.0, 1.0)
		_splat_buf[o + 15] = 0.0
	_splat_mm.buffer = _splat_buf
	_splat_mm.visible_instance_count = _sn


func _splat_remove(i: int) -> void:
	_sn -= 1
	if i != _sn:
		_sp[i] = _sp[_sn]; _sv[i] = _sv[_sn]; _ss[i] = _ss[_sn]; _ssv[i] = _ssv[_sn]; _st[i] = _st[_sn]
		_sh[i] = _sh[_sn]; _sl[i] = _sl[_sn]; _sL[i] = _sL[_sn]; _sd[i] = _sd[_sn]; _sk[i] = _sk[_sn]
