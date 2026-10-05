class_name SlimeTrail
extends MeshInstance3D
## 애벌레가 지나간 자리에 남는 투명한 점액 흔적 (달팽이 자국). 연출 전용, 판정 없음.
##
##  · 기어가는 꼬리 끝을 따라 점을 찍고(SPACING 마다), 점 둘씩 좌우로 벌려 바닥에 붙은 리본 띠를 만든다.
##  · 셰이더: 거의 투명한 몸 + 가장자리가 도톰한 물기 테(메니스커스) + 흐르는 듯한 굴곡 노멀로 젖은 반사 + 작은 기포 반짝임.
##    갓 나온 쪽은 조금 더 진하고 반짝이다가, 시간이 지나면 가장자리 은빛 자국만 남기고 말라 사라진다.
##  · 점마다 태어난 시각을 UV2 에 넣고 셰이더가 나이를 계산한다 → 메시는 점이 늘거나 지워질 때만 다시 만든다.
##  · 주인이 죽어도 흔적은 남아 마른 뒤 스스로 사라진다.

const SPACING := 0.09          ## 점 간격 (m)
const LIFE := 9.0              ## 흔적이 완전히 마르는 시간 (초)
const DRY := 4.0               ## 마지막 이만큼 동안 말라 간다
const MAX_POINTS := 150
const BREAK := 0.9             ## 이보다 멀리 튀면(넉백·돌진) 띠를 끊고 새로 시작

var width := 0.6
var pts: Array = []            ## [pos, side(수평 단위), birth, 폭 배율, 끊김 여부(true = 이 점에서 새 띠), 누적 길이]
var clock := 0.0
var owner_alive := true
var _len := 0.0                ## 누적 길이 (UV.y — 무늬가 띠를 따라 이어진다)
var _dirty := false
var _lift := 0.0
var _seed := randf() * TAU

static var _mat: ShaderMaterial
static var _n := 0


static func make(w: float) -> SlimeTrail:
	var s := SlimeTrail.new()
	s.width = w
	FX.root.add_child(s)
	return s


func _ready() -> void:
	name = "SlimeTrail"
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	global_transform = Transform3D.IDENTITY
	material_override = _material()
	set_meta("keep_mat", true)
	mesh = ArrayMesh.new()
	_n = (_n + 1) % 6
	_lift = 0.012 + _n * 0.0011          # 흔적끼리 겹쳐도 깜빡이지 않게 높이를 조금씩 다르게


## 꼬리 끝 월드 위치와 몸의 앞 방향을 매 프레임 넘긴다. 충분히 앞으로 나아갔으면 점을 하나 찍는다.
## 띠의 좌우는 몸 방향에서 정한다 — 넉백으로 꼬리가 뒤로 밀려도 띠가 꼬이지 않고, 뒤로 밀리는 동안은 찍지 않는다.
func feed(p: Vector3, fwd := Vector3.ZERO) -> void:
	var floor_p := Vector3(p.x, Main.gy(p), p.z)
	fwd.y = 0.0
	var side_hint := Vector3(-fwd.z, 0, fwd.x).normalized() if fwd.length() > 0.01 else Vector3.ZERO
	if pts.is_empty():
		_add(floor_p, side_hint if side_hint != Vector3.ZERO else Vector3.RIGHT, true)
		return
	var last: Vector3 = pts[-1][0]
	var d := floor_p - last
	d.y = 0.0
	var l := d.length()
	if l > BREAK:
		_add(floor_p, side_hint if side_hint != Vector3.ZERO else Vector3.RIGHT, true)
	elif l >= SPACING:
		if fwd.length() > 0.01 and d.dot(fwd) < 0.0:
			return
		var side := side_hint if side_hint != Vector3.ZERO else Vector3(-d.z, 0, d.x) / l
		var prev: Vector3 = pts[-1][1]
		if not pts[-1][4] and prev.dot(side) > 0.0:
			side = (prev + side * 2.0).normalized()      # 갑자기 꺾이지 않게 이전 방향과 섞는다
		if pts[-1][4]:
			pts[-1][1] = side          # 띠의 첫 점은 다음 점이 생길 때 방향을 정한다
		_len += l
		_add(floor_p, side, false)


func _add(p: Vector3, side: Vector3, brk: bool) -> void:
	# 폭은 길이를 따라 매끈하게 굽이친다 (점마다 무작위면 가장자리가 톱니가 된다)
	var wob := 0.95 + 0.07 * sin(_len * 6.3 + _seed) + 0.04 * sin(_len * 15.7 + _seed * 2.0)
	pts.append([p, side, clock, wob, brk, _len])
	while pts.size() > MAX_POINTS:
		pts.pop_front()
		if not pts.is_empty():
			pts[0][4] = true
	_dirty = true


func _process(dt: float) -> void:
	clock += dt
	set_instance_shader_parameter("now", clock)
	# 다 마른 점 지우기
	var n := 0
	while n < pts.size() and clock - float(pts[n][2]) > LIFE:
		n += 1
	if n > 0:
		pts = pts.slice(n)
		if not pts.is_empty():
			pts[0][4] = true
		_dirty = true
	if _dirty:
		_dirty = false
		_rebuild()
	if not owner_alive and pts.is_empty():
		queue_free()


func _rebuild() -> void:
	var am := mesh as ArrayMesh
	am.clear_surfaces()
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var nrm := PackedVector3Array()
	var idx := PackedInt32Array()
	var run := 0
	for i in pts.size():
		var pt: Array = pts[i]
		var brk: bool = pt[4]
		if brk:
			run = 0
		var p: Vector3 = pt[0] + Vector3(0, _lift, 0)
		var side: Vector3 = pt[1]
		# 폭: 갓 찍은 끝은 가늘게 모였다가 (꼬리 끝 모양), 띠의 처음도 둥글게
		var w: float = width * float(pt[3]) * 0.5
		var to_end := pts.size() - 1 - i
		w *= lerpf(0.55, 1.0, clampf(float(to_end) / 3.0, 0.0, 1.0))
		w *= lerpf(0.6, 1.0, clampf(float(run) / 2.0, 0.0, 1.0))
		var base := v.size()
		v.append(p - side * w)
		v.append(p + side * w)
		var acc: float = pt[5]
		uv.append(Vector2(0.0, acc))
		uv.append(Vector2(1.0, acc))
		var birth: float = pt[2]
		uv2.append(Vector2(birth, float(i % 7)))
		uv2.append(Vector2(birth, float(i % 7)))
		nrm.append(Vector3.UP)
		nrm.append(Vector3.UP)
		if run > 0:
			idx.append_array([base - 2, base, base - 1, base - 1, base, base + 1])
		run += 1
	if idx.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)


## 주인이 죽거나 사라질 때: 더 찍지 않고 남은 흔적이 마르면 지워진다
func release() -> void:
	owner_alive = false


static func _material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_mat.set_shader_parameter("life", LIFE)
		_mat.set_shader_parameter("dry", DRY)
		_mat.render_priority = -2
	return _mat


const SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_schlick_ggx;

instance uniform float now = 0.0;
uniform float life = 9.0;
uniform float dry = 4.0;
uniform vec3 tint : source_color = vec3(0.9, 0.93, 0.84);

varying float v_age;
varying vec2 v_uv;
varying float v_seed;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i), b = hash(i + vec2(1, 0)), c = hash(i + vec2(0, 1)), d = hash(i + vec2(1, 1));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	v_age = now - UV2.x;
	v_uv = UV;
	v_seed = UV2.y;
}

void fragment() {
	float age = max(v_age, 0.0);
	float alive = 1.0 - smoothstep(life - dry, life, age);      // 마르며 사라짐
	float wet = 1.0 - smoothstep(1.0, life - dry * 0.5, age);   // 물기 (반사·두께)
	float fresh = 1.0 - smoothstep(0.0, 0.7, age);              // 갓 나온 점액
	float x = v_uv.x * 2.0 - 1.0;
	float ax = abs(x);
	float n = vnoise(vec2(v_uv.x * 2.0, v_uv.y * 3.2));
	float n2 = vnoise(vec2(v_uv.x * 6.0, v_uv.y * 9.0) + 17.0);
	// 울퉁불퉁한 가장자리 (마를수록 안쪽으로 오그라든다)
	float edge = (0.8 + 0.2 * n) * mix(0.86, 1.0, wet);
	float mask = 1.0 - smoothstep(edge - 0.07, edge, ax);
	// 가장자리 물기 테: 점액이 가장자리로 도톰하게 몰려 빛을 모은다
	float rim = smoothstep(edge - 0.32, edge - 0.05, ax) * mask;
	// 가운데로 흐른 줄무늬 · 작은 기포 반짝임
	float streak = smoothstep(0.55, 0.9, vnoise(vec2(v_uv.x * 9.0, v_uv.y * 1.2))) * mask;
	float bubble = smoothstep(0.86, 0.95, n2) * mask * wet;
	// 젖은 표면 노멀: 테 쪽은 바깥으로 기울고, 안쪽은 잔물결
	float slope = sign(x) * rim * 0.9;
	float rip_x = (vnoise(vec2(v_uv.x * 5.0, v_uv.y * 6.0)) - 0.5) * 0.5;
	float rip_y = (vnoise(vec2(v_uv.x * 5.0 + 9.0, v_uv.y * 6.0)) - 0.5) * 0.5;
	NORMAL_MAP = normalize(vec3(0.5 + (slope + rip_x) * 0.5 * wet, 0.5 + rip_y * 0.5 * wet, 1.0));
	NORMAL_MAP_DEPTH = 1.0;
	ALBEDO = tint;
	METALLIC = 0.0;
	SPECULAR = 0.85;
	ROUGHNESS = mix(0.35, 0.03, wet);
	// 반사가 약한 각도에서도 물기가 보이게 테·기포·갓 나온 쪽에 아주 약한 자체 빛
	EMISSION = tint * (rim * 0.08 * wet + bubble * 0.25 + fresh * 0.06 + streak * 0.03);
	// 마른 자리는 은빛 테만 희미하게 남는다
	float body = 0.1 * wet + 0.025;
	ALPHA = mask * alive * clamp(body + rim * (0.15 + 0.08 * wet) + bubble * 0.3 + streak * 0.05 * wet + fresh * 0.07, 0.0, 0.7);
}
"""
