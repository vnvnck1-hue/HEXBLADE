class_name BladeFX
extends Node3D
## 광선검 연출 전용: 평소에 칼날이 이글거리는 불꽃 막(노이즈로 일렁임)·밝기 떨림·떠오르는 불티,
## 휘두르는 동안에는 칼날 잔상을 매 프레임 남겨 길게 끌리는 궤적을 만든다. 판정과 무관하다.
## 검 피벗(Build.robot 의 j.blade) 아래에 붙인다.

const BLADE_Z := -0.76          # 칼날 중심 (피벗 기준)
const BLADE_LEN := 1.35
const GHOST_LIFE := 0.34        # 휘두르기 잔상 하나가 사라지는 시간
const GHOST_EVERY := 0.012

static var _aura_mat: ShaderMaterial
static var _ghost_mat: ShaderMaterial

var player: Player
var glows: Array[MeshInstance3D] = []
var base_energy: Array[float] = []
var aura: MeshInstance3D
var embers: GPUParticles3D
var ghost_t := 0.0
var t := 0.0


func _ready() -> void:
	var blade := get_parent() as Node3D
	for n in blade.get_children():
		var mi := n as MeshInstance3D
		if mi and mi.material_override == Pal.flat():
			glows.append(mi)
			base_energy.append(float(mi.get_instance_shader_parameter("energy")))
	_build_aura()
	_build_embers()


func _build_aura() -> void:
	if _aura_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float boost = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
varying float v_along;
void vertex() {
	// 캡슐 축(Y)을 따라 물결치듯 부풀었다 줄었다 한다
	v_along = VERTEX.y;
	float w = noise(vec2(VERTEX.y * 5.0 - TIME * 9.0, atan(VERTEX.x, VERTEX.z) * 1.5 + TIME * 3.0));
	VERTEX.xz *= 0.75 + w * (0.75 + boost * 0.6);
}
void fragment() {
	float rim = 1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float n = noise(vec2(UV.x * 10.0 + TIME * 2.0, UV.y * 14.0 - TIME * 11.0));
	float n2 = noise(vec2(UV.x * 23.0 - TIME * 4.0, UV.y * 31.0 - TIME * 17.0));
	float flame = smoothstep(0.35, 0.95, n * 0.65 + n2 * 0.45);
	// 끝으로 갈수록 가늘고 옅게
	float tip = 1.0 - smoothstep(0.35, 0.72, abs(v_along));
	vec3 green = vec3(0.25, 1.0, 0.2);
	vec3 hot = vec3(0.9, 1.0, 0.55);
	ALBEDO = mix(green, hot, flame) * (0.6 + flame * 1.4) * (1.0 + boost);
	ALPHA = clamp((0.3 + flame * 1.1) * (0.5 + rim) * tip, 0.0, 1.0);
}
"""
		_aura_mat = ShaderMaterial.new()
		_aura_mat.shader = sh
	var cap := CapsuleMesh.new()
	cap.radius = 0.12
	cap.height = BLADE_LEN + 0.25
	cap.radial_segments = 12
	cap.rings = 14
	aura = MeshInstance3D.new()
	aura.mesh = cap
	aura.material_override = _aura_mat.duplicate()
	aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	aura.rotation_degrees.x = 90.0
	aura.position = Vector3(0, 0, BLADE_Z)
	add_child(aura)


## 칼날을 따라 피어올라 흩어지는 불티. 전역 좌표로 남아서 휘두르면 궤적처럼 뿌려진다.
func _build_embers() -> void:
	embers = GPUParticles3D.new()
	embers.amount = 56
	embers.lifetime = 0.55
	embers.local_coords = false
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.04, 0.04, BLADE_LEN * 0.5)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 50.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0, 2.2, 0)
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
	grad.colors = PackedColorArray([Color("f4ffc0"), Pal.BLADE, Color("1f7a20")])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	embers.process_material = pm
	var box := BoxMesh.new()
	box.size = Vector3(0.04, 0.04, 0.04)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.6, 1.6, 1.6)
	box.material = m
	embers.draw_pass_1 = box
	embers.position = Vector3(0, 0, BLADE_Z)
	add_child(embers)
	embers.emitting = true


func _process(dt: float) -> void:
	t += dt
	var swinging := player != null and (player.slash_anim > 0.0 or player.lunge_t > 0.0)
	# 밝기 떨림: 서로 다른 주기의 사인을 겹쳐 불규칙하게
	var flick := 1.0 + 0.16 * sin(t * 37.0) * sin(t * 13.0 + 1.3) + 0.08 * sin(t * 71.0)
	for i in glows.size():
		glows[i].set_instance_shader_parameter("energy", base_energy[i] * (flick * (1.25 if swinging else 1.0)))
	(aura.material_override as ShaderMaterial).set_shader_parameter("boost", 0.6 if swinging else 0.0)
	embers.amount_ratio = 1.0 if swinging else 0.6
	if swinging:
		ghost_t -= dt
		if ghost_t <= 0.0:
			ghost_t = GHOST_EVERY
			_ghost()
	else:
		ghost_t = 0.0


## 현재 칼날 모양을 그대로 복제해 제자리에 남기고, 점점 옅어지며 가늘어진다
func _ghost() -> void:
	if _ghost_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
instance uniform float fade = 1.0;
void fragment() {
	ALBEDO = mix(vec3(0.1, 0.55, 0.12), vec3(0.75, 1.0, 0.45), fade) * (0.5 + fade);
	ALPHA = fade * 0.85;
}
"""
		_ghost_mat = ShaderMaterial.new()
		_ghost_mat.shader = sh
	var holder := Node3D.new()
	FX.root.add_child(holder)
	for g in glows:
		var mi := MeshInstance3D.new()
		mi.mesh = g.mesh
		mi.material_override = _ghost_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_instance_shader_parameter("fade", 1.0)
		holder.add_child(mi)
		mi.global_transform = g.global_transform
		# 잔상은 칼날보다 조금 넓게 펴서 궤적 사이 틈을 메운다
		mi.scale = mi.scale * Vector3(1.8, 1.6, 1.0)
		var tw := mi.create_tween()
		tw.tween_method(func(v: float): mi.set_instance_shader_parameter("fade", v), 1.0, 0.0, GHOST_LIFE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(mi, "scale", mi.scale * Vector3(0.3, 0.3, 0.9), GHOST_LIFE).set_ease(Tween.EASE_IN)
	holder.get_tree().create_timer(GHOST_LIFE + 0.05).timeout.connect(holder.queue_free)
