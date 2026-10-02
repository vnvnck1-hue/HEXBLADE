class_name RushFX
extends RefCounted
## 돌진 공격 연출 전용 (판정과 무관, 모두 스스로 수명을 끝낸다).
## 초속 수십 m 로 파고드는 동안 강철 발이 바닥을 긁는다:
## - scrape(): 긁힌 구간을 따라 뒤·위로 튀는 마찰 불꽃 (속도 방향으로 길게 늘어난 가는 불티)
## - heat(): 긁힌 자리에 남는 달아오른 쇳자국. 흰빛 → 노랑 → 주황 → 검붉게 식고 그을음만 남았다 사라진다.
## - brake(): 멈춰 서는 순간 앞으로 쏟아지는 불꽃과 짧은 섬광
## Player 가 돌진 틱마다 발 아래 바닥 위치의 이전 → 현재 구간을 넘긴다.

const HEAT_TIME := 1.5          # 흰빛에서 완전히 식을 때까지
const SOOT_TIME := 0.8          # 식은 뒤 그을음이 사라지는 시간
const MARK_W := 0.16            # 쇳자국 폭

static var _spark_pm: ParticleProcessMaterial
static var _spark_mesh: BoxMesh
static var _heat_mat: ShaderMaterial
static var _plane: PlaneMesh


static func _setup() -> void:
	if _spark_pm:
		return
	# 불티: 속도 방향으로 몸을 늘인 가는 막대, 강한 중력으로 포물선을 그리며 떨어진다
	_spark_pm = ParticleProcessMaterial.new()
	_spark_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_spark_pm.direction = Vector3(0, 0.45, 1)       # 로컬 +Z = 돌진 반대쪽 (뒤)
	_spark_pm.spread = 28.0
	_spark_pm.initial_velocity_min = 6.0
	_spark_pm.initial_velocity_max = 15.0
	_spark_pm.gravity = Vector3(0, -22.0, 0)
	_spark_pm.damping_min = 2.0
	_spark_pm.damping_max = 5.0
	_spark_pm.particle_flag_align_y = true
	_spark_pm.scale_min = 0.5
	_spark_pm.scale_max = 1.3
	var cv := Curve.new()
	cv.add_point(Vector2(0, 1))
	cv.add_point(Vector2(0.6, 0.7))
	cv.add_point(Vector2(1, 0))
	var ct := CurveTexture.new()
	ct.curve = cv
	_spark_pm.scale_curve = ct
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 0.55, 1.0])
	grad.colors = PackedColorArray([Color(1.0, 0.97, 0.85), Color(1.0, 0.8, 0.35), Color(1.0, 0.42, 0.08), Color(0.6, 0.08, 0.02)])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	_spark_pm.color_ramp = gt
	_spark_mesh = BoxMesh.new()
	_spark_mesh.size = Vector3(0.022, 0.26, 0.022)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(2.2, 2.2, 2.2)
	_spark_mesh.material = m

	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;
instance uniform float heat = 1.0;   // 1 막 긁힘 → 0 식음
instance uniform float soot = 1.0;   // 식은 뒤 그을음 (1 → 0 으로 사라짐)
instance uniform float seed = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	float across = abs(UV.x - 0.5) * 2.0;           // 0 가운데 · 1 가장자리
	float along = UV.y;
	// 들쭉날쭉한 가장자리와 길게 파인 결
	float edge = 0.45 + 0.4 * vnoise(vec2(along * 9.0 + seed, 1.7));
	float shape = 1.0 - smoothstep(edge - 0.25, edge + 0.1, across);
	float groove = 0.62 + 0.38 * vnoise(vec2(UV.x * 16.0 + seed, along * 1.5));
	float ends = 1.0;                                // 조각끼리 이어 붙어 한 줄로 보인다
	// 가운데가 가장 뜨겁고 늦게 식는다
	float t = clamp(heat * (0.7 + 0.45 * (1.0 - across)) * groove, 0.0, 1.0);
	vec3 soot_c = vec3(0.07, 0.055, 0.08);
	vec3 red = vec3(0.6, 0.05, 0.02);
	vec3 orange = vec3(1.0, 0.36, 0.06);
	vec3 yellow = vec3(1.0, 0.78, 0.3);
	vec3 white = vec3(1.0, 0.96, 0.85);
	vec3 col = mix(soot_c, red, smoothstep(0.02, 0.28, t));
	col = mix(col, orange, smoothstep(0.28, 0.58, t));
	col = mix(col, yellow, smoothstep(0.58, 0.84, t));
	col = mix(col, white, smoothstep(0.84, 1.0, t));
	// 뜨거운 동안은 빛 번짐이 날 만큼 밝다
	ALBEDO = col * (1.0 + smoothstep(0.25, 1.0, t) * 2.4);
	float a = mix(0.5 * soot, 1.0, smoothstep(0.02, 0.3, t));
	ALPHA = clamp(shape * ends * a, 0.0, 1.0);
}
"""
	_heat_mat = ShaderMaterial.new()
	_heat_mat.shader = sh
	_heat_mat.render_priority = -1
	_plane = PlaneMesh.new()
	_plane.size = Vector2(1, 1)


## 긁힌 구간 from → to (바닥 높이) 를 따라 뒤·위로 튀는 마찰 불꽃
static func scrape(from: Vector3, to: Vector3, k := 1.0) -> void:
	_setup()
	var d := to - from
	d.y = 0
	var l := d.length()
	if l < 0.02:
		return
	var p := GPUParticles3D.new()
	p.amount = clampi(int(l * 7.0 * k) + 3, 3, 40)
	p.one_shot = true
	p.explosiveness = 0.85
	p.lifetime = 0.34
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.process_material = _scrape_pm(l, k)
	p.draw_pass_1 = _spark_mesh
	FX.root.add_child(p)
	var mid := (from + to) * 0.5
	mid.y = Main.gy(mid) + 0.06
	# 로컬 -Z 가 돌진 방향 → 불꽃 방향(로컬 +Z)은 뒤쪽
	p.global_transform = Transform3D(Basis.looking_at(d / l, Vector3.UP), mid)
	p.emitting = true
	p.get_tree().create_timer(0.7).timeout.connect(p.queue_free)
	# 발끝이 긁히는 곳의 작고 뜨거운 섬광
	FX.flash(Vector3(to.x, Main.gy(to) + 0.08, to.z), Color(1.0, 0.72, 0.35), 0.28, 0.04)


## 달아오른 쇳자국 from → to (바닥)
static func heat(from: Vector3, to: Vector3, width := MARK_W) -> void:
	_setup()
	var d := to - from
	d.y = 0
	var l := d.length()
	if l < 0.02:
		return
	var dir := d / l
	var right := Vector3.UP.cross(dir).normalized()
	var mi := MeshInstance3D.new()
	mi.mesh = _plane
	mi.material_override = _heat_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	FX.root.add_child(mi)
	var mid := (from + to) * 0.5
	mid.y = Main.gy(mid) + 0.018 + randf() * 0.004      # 겹친 조각끼리 깜빡이지 않게 높이를 조금씩 다르게
	# 이어 붙인 조각 사이 틈이 없도록 살짝 길게
	mi.global_transform = Transform3D(Basis(right * width, Vector3.UP, dir * (l + width * 0.6)), mid)
	mi.set_instance_shader_parameter("heat", 1.0)
	mi.set_instance_shader_parameter("soot", 1.0)
	mi.set_instance_shader_parameter("seed", randf() * 50.0)
	var tw := mi.create_tween()
	# 처음엔 빠르게 흰빛이 빠지고, 붉은 기는 오래 남는다
	tw.tween_method(func(v: float): mi.set_instance_shader_parameter("heat", v), 1.0, 0.0, HEAT_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_method(func(v: float): mi.set_instance_shader_parameter("soot", v), 1.0, 0.0, SOOT_TIME)
	tw.tween_callback(mi.queue_free)
	# 식는 동안 피어오르는 불티 몇 개
	if randf() < 0.5:
		FX.sparks(Vector3(mid.x, Main.gy(mid) + 0.08, mid.z), 2, [Color(1.0, 0.6, 0.2), Color(0.7, 0.12, 0.04)], 1.6, 0.5, 1.5, 0.035)


## 멈춰 서는 순간: 앞으로 쏟아지는 불꽃
static func brake(pos: Vector3, dir: Vector3) -> void:
	_setup()
	var d := Vector3(dir.x, 0, dir.z)
	if d.length() < 0.01:
		return
	d = d.normalized()
	var p := GPUParticles3D.new()
	p.amount = 22
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.4
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _brake_pm == null:
		_brake_pm = _spark_pm.duplicate() as ParticleProcessMaterial
		_brake_pm.emission_box_extents = Vector3(0.25, 0.02, 0.1)
		_brake_pm.direction = Vector3(0, 0.55, -1)          # 앞으로 (관성)
		_brake_pm.spread = 38.0
		_brake_pm.initial_velocity_min = 5.0
		_brake_pm.initial_velocity_max = 13.0
	p.process_material = _brake_pm
	p.draw_pass_1 = _spark_mesh
	FX.root.add_child(p)
	p.global_transform = Transform3D(Basis.looking_at(d, Vector3.UP), Vector3(pos.x, Main.gy(pos) + 0.06, pos.z) + d * 0.3)
	p.emitting = true
	p.get_tree().create_timer(0.8).timeout.connect(p.queue_free)
	FX.flash(Vector3(pos.x, Main.gy(pos) + 0.12, pos.z) + d * 0.3, Color(1.0, 0.75, 0.4), 0.55, 0.05)
	Sfx.play("clank", 0.1, -12.0)


static var _brake_pm: ParticleProcessMaterial
static var _scrape_pms := {}


## 긁힘 불꽃 머티리얼: 구간 길이 0.1m · 세기 0.1 단위로 묶어 공유한다 (돌진 틱마다 머티리얼을 복제하지 않게)
static func _scrape_pm(l: float, k: float) -> ParticleProcessMaterial:
	var lq := snappedf(l, 0.1)
	var kq := snappedf(clampf(k, 0.6, 1.4), 0.1)
	var key := Vector2(lq, kq)
	var pm: ParticleProcessMaterial = _scrape_pms.get(key)
	if pm == null:
		if _scrape_pms.size() >= 128:
			_scrape_pms.clear()
		pm = _spark_pm.duplicate() as ParticleProcessMaterial
		pm.emission_box_extents = Vector3(0.05, 0.02, maxf(lq, 0.05) * 0.5)
		pm.initial_velocity_max = 15.0 * kq
		_scrape_pms[key] = pm
	return pm
