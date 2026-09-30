class_name BladeFX
extends Node3D
## 광선검 연출 전용. 판정과 무관하다. 검 피벗(Build.robot 의 j.blade) 아래에 붙인다.
## - 평소: 붉은 칼날이 가볍게 떨리며 빛난다. 휘두르기 궤적은 SaberTrail 이 그린다.
## - 관통 일격 준비 중(2단 대시·패링 성공 후 몇 초): 칼날이 불타오른다.
##   칼끝으로 빠르게 쏟아지는 불꽃 막 두 겹 · 움직임 반대쪽으로 뿜어지는 불꽃 줄기(속도선) · 불티 ·
##   움직일 때 남는 불꽃 잔상 · 붉은 조명. 꺼지기 직전에는 깜빡이며 알린다.
## Player 가 ignite() / douse() / release() 로 켜고 끈다.

const BLADE_Z := -0.76          # 칼날 중심 (피벗 기준)
const BLADE_LEN := 1.35
const GHOST_LIFE := 0.14        # 불타는 칼 휘두르기 잔상 하나가 사라지는 시간
const GHOST_EVERY := 0.012
const FLAME_GHOST_LIFE := 0.2   # 불타는 동안 움직이면 남는 불꽃 잔상
const FLAME_GHOST_EVERY := 0.018
const WARN_TIME := 0.8          # 꺼지기 전 이만큼 남으면 깜빡인다

static var _aura_mat: ShaderMaterial
static var _ghost_mat: ShaderMaterial

var player: Player
var glows: Array[MeshInstance3D] = []
var base_energy: Array[float] = []
var aura: MeshInstance3D           # 안쪽: 칼날에 붙어 빠르게 흐르는 불꽃 막
var aura_out: MeshInstance3D       # 바깥: 크게 일렁이는 불꽃 혀
var streaks: GPUParticles3D        # 움직임 반대쪽으로 뿜어지는 긴 불꽃 줄기
var streak_pm: ParticleProcessMaterial
var embers: GPUParticles3D
var light: OmniLight3D
var ghost_t := 0.0
var flame_ghost_t := 0.0
var t := 0.0
var lit := false
var flame_k := 0.0                 # 0 꺼짐 ~ 1 활활
var flare := 0.0                   # 점화·재점화 순간 치솟는 세기
var tip_prev := Vector3.ZERO
var blade_vel := Vector3.ZERO


func _ready() -> void:
	var blade := get_parent() as Node3D
	for n in blade.get_children():
		var mi := n as MeshInstance3D
		if mi and mi.material_override == Pal.flat():
			glows.append(mi)
			base_energy.append(float(mi.get_instance_shader_parameter("energy")))
	aura = _build_aura(0.075, 0.0)
	aura_out = _build_aura(0.13, 1.0)
	_build_streaks()
	_build_embers()
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.3, 0.15)
	light.omni_range = 3.2
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.position = Vector3(0, 0, BLADE_Z)
	add_child(light)
	_apply(0.0)


func _build_aura(radius: float, outer: float) -> MeshInstance3D:
	if _aura_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float heat = 0.0;       // 전체 세기 (0 이면 보이지 않는다)
uniform float boost = 0.0;      // 휘두르는 중
uniform float outer = 0.0;      // 0 안쪽 막 · 1 바깥 불꽃 혀
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
varying float v_along;
varying float v_ang;
void vertex() {
	// 캡슐 축(Y, -Y 가 칼끝)을 따라 불꽃 덩어리가 칼끝으로 빠르게 쏟아져 나간다
	v_along = VERTEX.y;
	v_ang = atan(VERTEX.x, VERTEX.z);
	float spd = mix(26.0, 38.0, outer) * (1.0 + boost * 0.5);
	float w = noise(vec2(VERTEX.y * mix(5.0, 3.2, outer) + TIME * spd, v_ang * 1.6 + outer * 7.0));
	float w2 = noise(vec2(VERTEX.y * 11.0 + TIME * spd * 1.4, v_ang * 3.0 - TIME * 4.0));
	float grow = mix(0.55, 1.0, heat);
	VERTEX.xz *= grow * (0.55 + w * mix(0.8, 1.5, outer) + w2 * 0.35 + boost * 0.35);
	// 바깥 불꽃 혀는 위(월드 +Y 쪽 로컬 방향과 무관하게 칼날 둘레)로 살짝 치솟는다
	VERTEX.y -= outer * w * 0.12;
}
void fragment() {
	float rim = 1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float spd = mix(24.0, 34.0, outer) * (1.0 + boost * 0.5);
	// 축 방향으로 길게 늘어난 줄무늬: 칼끝으로 흐르는 속도감
	float s1 = noise(vec2(v_ang * 5.0, v_along * 4.0 + TIME * spd));
	float s2 = noise(vec2(v_ang * 11.0 + 3.0, v_along * 9.0 + TIME * spd * 1.6));
	float streak = smoothstep(0.35, 0.9, s1 * 0.6 + s2 * 0.55);
	float lick = smoothstep(0.55, 1.0, noise(vec2(v_ang * 3.0, v_along * 2.0 + TIME * spd * 0.7)));
	float flame = clamp(streak * 0.8 + lick * 0.6, 0.0, 1.0);
	// 칼끝으로 갈수록 가늘고, 손잡이 쪽은 짧게 사라진다
	float tip = 1.0 - smoothstep(0.3, 0.74, abs(v_along));
	vec3 red = vec3(1.0, 0.05, 0.04);
	vec3 orange = vec3(1.0, 0.32, 0.08);
	vec3 white = vec3(1.0, 0.8, 0.6);
	vec3 col = mix(red, orange, flame * flame);
	col = mix(col, white, pow(flame, 4.0) * 0.45 * (1.0 - outer));
	ALBEDO = col * (0.7 + flame * 1.1) * (1.0 + boost * 0.6) * mix(1.1, 0.85, outer);
	float a = (mix(0.25, 0.0, outer) + flame * mix(1.1, 0.9, outer)) * (0.45 + rim * mix(0.8, 1.2, outer)) * tip;
	ALPHA = clamp(a * heat, 0.0, 1.0);
}
"""
		_aura_mat = ShaderMaterial.new()
		_aura_mat.shader = sh
	var cap := CapsuleMesh.new()
	cap.radius = radius
	cap.height = BLADE_LEN + 0.3
	cap.radial_segments = 14
	cap.rings = 18
	var mi := MeshInstance3D.new()
	mi.mesh = cap
	var mat := _aura_mat.duplicate() as ShaderMaterial
	mat.set_shader_parameter("outer", outer)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation_degrees.x = 90.0
	mi.position = Vector3(0, 0, BLADE_Z)
	add_child(mi)
	return mi


## 긴 불꽃 줄기: 속도 방향으로 몸을 늘인 가는 막대. 전역 좌표에 남으므로 움직이면 뒤로 길게 끌린다.
func _build_streaks() -> void:
	streaks = GPUParticles3D.new()
	streaks.amount = 120
	streaks.lifetime = 0.24
	streaks.local_coords = false
	streaks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	streak_pm = ParticleProcessMaterial.new()
	streak_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	streak_pm.emission_box_extents = Vector3(0.04, 0.04, BLADE_LEN * 0.48)
	streak_pm.direction = Vector3(0, 1, 0)
	streak_pm.spread = 22.0
	streak_pm.initial_velocity_min = 2.5
	streak_pm.initial_velocity_max = 5.0
	streak_pm.gravity = Vector3(0, 4.0, 0)
	streak_pm.damping_min = 3.0
	streak_pm.damping_max = 6.0
	streak_pm.particle_flag_align_y = true
	streak_pm.scale_min = 0.6
	streak_pm.scale_max = 1.4
	var cv := Curve.new()
	cv.add_point(Vector2(0, 0.6))
	cv.add_point(Vector2(0.25, 1.0))
	cv.add_point(Vector2(1, 0))
	var ct := CurveTexture.new()
	ct.curve = cv
	streak_pm.scale_curve = ct
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
	grad.colors = PackedColorArray([Color(1.0, 0.7, 0.45, 1.0), Color(1.0, 0.3, 0.08, 0.95), Color(0.95, 0.06, 0.04, 0.7), Color(0.3, 0.0, 0.02, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	streak_pm.color_ramp = gt
	streaks.process_material = streak_pm
	var box := BoxMesh.new()
	box.size = Vector3(0.028, 0.36, 0.028)
	box.material = _add_mat(1.5)
	streaks.draw_pass_1 = box
	streaks.position = Vector3(0, 0, BLADE_Z)
	add_child(streaks)
	streaks.emitting = false


## 칼날을 따라 피어올라 흩어지는 불티
func _build_embers() -> void:
	embers = GPUParticles3D.new()
	embers.amount = 48
	embers.lifetime = 0.5
	embers.local_coords = false
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.05, 0.05, BLADE_LEN * 0.5)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0, 3.0, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	var cv := Curve.new()
	cv.add_point(Vector2(0, 1))
	cv.add_point(Vector2(1, 0))
	var ct := CurveTexture.new()
	ct.curve = cv
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	grad.colors = PackedColorArray([Color("ffc080"), Color("ff4a20"), Color("7a1010")])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	embers.process_material = pm
	var box := BoxMesh.new()
	box.size = Vector3(0.045, 0.045, 0.045)
	box.material = _add_mat(1.6)
	embers.draw_pass_1 = box
	embers.position = Vector3(0, 0, BLADE_Z)
	add_child(embers)
	embers.emitting = false


func _add_mat(energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(energy, energy, energy)
	return m


# ── 켜고 끄기 (Player 가 부른다) ─────────────────────────

## 관통 일격 준비: 칼날이 확 타오른다 (이미 타고 있으면 다시 치솟는다)
func ignite() -> void:
	var was := lit
	lit = true
	flare = 1.0
	var c := _blade_center()
	FX.flash(c, Color(1.0, 0.55, 0.25), 1.1 if not was else 0.7, 0.08)
	for i in 5:
		var p := _blade_point(float(i) / 4.0)
		FX.sparks(p, 3, [Color.WHITE, Color("ffb040"), Pal.BLADE], 6.0, 0.25, 4.0, 0.05)
	var s := Sfx.play("charge", 0.05, -9.0)
	if s:
		s.pitch_scale = 2.2
		get_tree().create_timer(0.18, true, false, true).timeout.connect(func():
			if is_instance_valid(s):
				s.stop())


## 시간이 다 되어 불이 꺼진다: 연기와 식은 불티
func douse() -> void:
	if not lit:
		return
	lit = false
	for i in 4:
		var p := _blade_point(float(i) / 3.0)
		FX.smoke(p)
		FX.sparks(p, 2, [Color("ff6a30"), Color("5a1010")], 2.0, 0.3, 2.0, 0.04)
	var s := Sfx.play("powerdown", 0.1, -12.0)
	if s:
		s.pitch_scale = 1.6


## 관통 일격을 썼다: 불꽃이 칼끝 방향으로 한 번에 뿜어지며 꺼진다
func release() -> void:
	if not lit:
		return
	lit = false
	flare = 1.0
	FX.flash(_blade_center(), Color(1.0, 0.7, 0.4), 1.4, 0.06)


func _blade_point(k: float) -> Vector3:
	return to_global(Vector3(0, 0, BLADE_Z + BLADE_LEN * (0.5 - k)))


func _blade_center() -> Vector3:
	return to_global(Vector3(0, 0, BLADE_Z))


# ── 갱신 ────────────────────────────────────────────────

func _process(dt: float) -> void:
	t += dt
	var swinging := player != null and (player.slash_anim > 0.0 or player.lunge_t > 0.0 or (player.combo != null and player.combo.swinging()))
	# 칼끝 속도 (불꽃 줄기 방향 · 잔상 여부에 쓴다)
	var tip := _blade_point(1.0)
	if dt > 0.0:
		blade_vel = blade_vel.lerp((tip - tip_prev) / dt, 0.5)
	tip_prev = tip
	# 불꽃 세기: 켜질 때 빠르게 치솟고, 꺼질 때 더 빠르게 사그라든다
	flame_k = move_toward(flame_k, 1.0 if lit else 0.0, dt * (6.0 if lit else 9.0))
	flare = maxf(0.0, flare - dt * 3.5)
	var heat := flame_k * (1.0 + flare * 0.6)
	# 꺼지기 직전: 점점 빨라지는 깜빡임
	if lit and player != null and player.phantom_t < WARN_TIME:
		var w := 1.0 - player.phantom_t / WARN_TIME
		var blink := 0.5 + 0.5 * sin(t * lerpf(18.0, 46.0, w))
		heat *= lerpf(1.0, 0.25 + 0.75 * blink, w)
	_apply(heat)

	# 칼날 밝기 떨림: 서로 다른 주기의 사인을 겹쳐 불규칙하게. 불타는 동안 더 밝고 거칠게 떤다.
	var flick := 1.0 + (0.16 + heat * 0.18) * sin(t * 37.0) * sin(t * 13.0 + 1.3) + 0.08 * sin(t * 71.0)
	for i in glows.size():
		glows[i].set_instance_shader_parameter("energy", base_energy[i] * flick * (1.25 if swinging else 1.0) * (1.0 + heat * 0.35))
	var boost := 0.6 if swinging else 0.0
	(aura.material_override as ShaderMaterial).set_shader_parameter("boost", boost)
	(aura_out.material_override as ShaderMaterial).set_shader_parameter("boost", boost)

	# 불꽃 줄기: 칼이 움직이는 반대쪽으로 뿜어져 속도선처럼 끌린다 (가만히 있으면 위로 피어오른다)
	var spd := blade_vel.length()
	var back := -blade_vel / maxf(spd, 0.001) if spd > 1.0 else Vector3.ZERO
	var want := (back * clampf(spd / 8.0, 0.0, 1.0) + Vector3.UP * 0.7).normalized()
	streak_pm.direction = (global_basis.inverse() * want).normalized()
	streak_pm.initial_velocity_min = 2.5 + minf(spd, 20.0) * 0.25
	streak_pm.initial_velocity_max = 5.0 + minf(spd, 20.0) * 0.45
	light.light_energy = heat * (1.3 + 0.4 * sin(t * 31.0) * sin(t * 17.0))

	# 평소 휘두르기 잔상은 SaberTrail(아주 짧은 초승달 리본)이 맡는다. 불타는 동안에만 불꽃 복제 잔상을 더한다.
	if swinging and flame_k > 0.3:
		ghost_t -= dt
		if ghost_t <= 0.0:
			ghost_t = GHOST_EVERY
			_ghost(true, GHOST_LIFE)
	else:
		ghost_t = 0.0
	# 불타는 칼을 들고 움직이면 불꽃 잔상이 뒤로 길게 남는다
	if flame_k > 0.3 and not swinging and spd > 3.0:
		flame_ghost_t -= dt
		if flame_ghost_t <= 0.0:
			flame_ghost_t = FLAME_GHOST_EVERY
			_ghost(true, FLAME_GHOST_LIFE)


func _apply(heat: float) -> void:
	var on := heat > 0.01
	aura.visible = on
	aura_out.visible = on
	(aura.material_override as ShaderMaterial).set_shader_parameter("heat", clampf(heat, 0.0, 1.6))
	(aura_out.material_override as ShaderMaterial).set_shader_parameter("heat", clampf(heat * 0.85, 0.0, 1.4))
	streaks.emitting = flame_k > 0.4
	streaks.amount_ratio = clampf(heat, 0.2, 1.0)
	embers.emitting = flame_k > 0.4
	light.visible = on


## 현재 칼날 모양을 그대로 복제해 제자리에 남기고, 점점 옅어지며 가늘어진다. hot 이면 불꽃빛으로 더 넓게.
func _ghost(hot: bool, life: float) -> void:
	if _ghost_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
instance uniform float fade = 1.0;
instance uniform float hot = 0.0;
void fragment() {
	vec3 saber = mix(vec3(0.5, 0.04, 0.06), vec3(1.0, 0.55, 0.5), fade);
	vec3 fire = mix(vec3(0.7, 0.03, 0.02), vec3(1.0, 0.4, 0.15), fade * fade);
	ALBEDO = mix(saber, fire, hot) * (0.5 + fade);
	ALPHA = fade * mix(0.85, 0.7, hot);
}
"""
		_ghost_mat = ShaderMaterial.new()
		_ghost_mat.shader = sh
	var holder := Node3D.new()
	FX.root.add_child(holder)
	var widen := Vector3(3.0, 2.4, 1.05) if hot else Vector3(1.8, 1.6, 1.0)
	for g in glows:
		var mi := MeshInstance3D.new()
		mi.mesh = g.mesh
		mi.material_override = _ghost_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_instance_shader_parameter("fade", 1.0)
		mi.set_instance_shader_parameter("hot", 1.0 if hot else 0.0)
		holder.add_child(mi)
		mi.global_transform = g.global_transform
		# 잔상은 칼날보다 넓게 펴서 궤적 사이 틈을 메운다
		mi.scale = mi.scale * widen
		var tw := mi.create_tween()
		tw.tween_method(func(v: float): mi.set_instance_shader_parameter("fade", v), 1.0, 0.0, life).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(mi, "scale", mi.scale * Vector3(0.3, 0.3, 0.9), life).set_ease(Tween.EASE_IN)
		if hot:
			# 불꽃 잔상은 식으면서 살짝 떠오른다
			tw.parallel().tween_property(mi, "global_position", mi.global_position + Vector3(0, 0.25, 0), life)
	holder.get_tree().create_timer(life + 0.05).timeout.connect(holder.queue_free)
