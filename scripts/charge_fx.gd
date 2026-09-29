class_name ChargeFX
extends Node3D
## 레이저 충전 연출: 총구 앞 발광 구체 + 빨려드는 링·입자 + 주변을 비추는 빛.
## set_charge(k) 로 0~1 충전량을 받는다. 판정과 무관.

static var _ring_shader: Shader
static var _sphere: SphereMesh
static var _bit: BoxMesh
static var _quad: QuadMesh

## 충전 단계 색: 청록 → 파랑 → 자홍 → 최대(흰금)
const STAGE_COLORS := [Color("35e8ff"), Color("5a7cff"), Color("ff3ac8"), Color("fff0a0")]

var k := 0.0
var stage := 0
var active := false
var full := false
var orb: MeshInstance3D
var halo: MeshInstance3D
var light: OmniLight3D
var ring_t := 0.0
var bit_t := 0.0
var t := 0.0


func _ready() -> void:
	if _ring_shader == null:
		_ring_shader = Shader.new()
		_ring_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
instance uniform float radius = 1.0;
instance uniform vec4 tint : source_color = vec4(0.4, 1.0, 1.0, 1.0);
void vertex() {
%s
}
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float w = 0.025 + 0.035 * radius;
	if (abs(r - radius) > w) discard;
	ALBEDO = tint.rgb * 1.6;
}
""" % FX.BILLBOARD
		_sphere = SphereMesh.new()
		_sphere.radius = 0.5
		_sphere.height = 1.0
		_bit = BoxMesh.new()
		_bit.size = Vector3(0.05, 0.05, 0.22)
		_quad = QuadMesh.new()
	orb = Pal.flat_mesh(_sphere, Pal.CYAN, 2.0)
	add_child(orb)
	halo = MeshInstance3D.new()
	halo.mesh = _sphere
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hm.albedo_color = Color(0.3, 0.9, 1.0, 0.35)
	halo.material_override = hm
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)
	light = OmniLight3D.new()
	light.light_color = Color(0.4, 0.95, 1.0)
	light.omni_range = 4.0
	light.light_energy = 0.0
	add_child(light)
	visible = false


func begin() -> void:
	active = true
	full = false
	k = 0.0
	stage = 0
	visible = true


func end() -> void:
	active = false
	visible = false
	light.light_energy = 0.0
	for c in get_children():
		if c.has_meta("fx_bit"):
			c.queue_free()


func set_charge(v: float, dt: float) -> void:
	k = v
	t += dt
	var pulse := sin(t * (18.0 + 30.0 * k)) * 0.08 * k
	var s := lerpf(0.12, 0.62, k) * (1.0 + pulse)
	if full:
		s *= 1.0 + sin(t * 50.0) * 0.12
	orb.scale = Vector3.ONE * s
	halo.scale = Vector3.ONE * s * (1.9 + sin(t * 23.0) * 0.15)
	var c: Color = STAGE_COLORS[stage]
	orb.set_instance_shader_parameter("tint", c.lerp(Color.WHITE, 0.25 + 0.15 * sin(t * 30.0)))
	orb.set_instance_shader_parameter("energy", 2.0 + stage * 0.5)
	(halo.material_override as StandardMaterial3D).albedo_color = Color(c.r, c.g, c.b, 0.3 + stage * 0.06)
	light.light_color = c
	light.light_energy = 0.6 + k * 3.5 + stage * 0.8
	light.omni_range = 2.5 + k * 3.0
	# 빨려드는 링
	ring_t -= dt
	if ring_t <= 0.0:
		ring_t = lerpf(0.2, 0.1, k)
		_spawn_ring()
	# 빨려드는 입자
	bit_t -= dt
	if bit_t <= 0.0:
		bit_t = lerpf(0.05, 0.015, k)
		_spawn_bit()


func _spawn_ring() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	var m := ShaderMaterial.new()
	m.shader = _ring_shader
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("fx_bit", true)
	mi.scale = Vector3.ONE * (2.2 + k * 1.2)
	mi.set_instance_shader_parameter("tint", (STAGE_COLORS[stage] as Color).lerp(Color.WHITE, randf() * 0.3))
	mi.set_instance_shader_parameter("radius", 0.9)
	add_child(mi)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): mi.set_instance_shader_parameter("radius", v), 0.9, 0.1, 0.28).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(mi.queue_free)


func _spawn_bit() -> void:
	var col: Color = Color.WHITE if randf() < 0.4 else STAGE_COLORS[stage]
	var mi := Pal.flat_mesh(_bit, col, 1.8)
	mi.set_meta("fx_bit", true)
	var dir := Vector3(randf_range(-1, 1), randf_range(-0.6, 1), randf_range(-1, 1)).normalized()
	var dist := randf_range(1.0, 1.8) + k
	mi.position = dir * dist
	add_child(mi)
	mi.look_at(global_position, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT)
	var tw := mi.create_tween()
	tw.tween_property(mi, "position", Vector3.ZERO, 0.22).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(mi, "scale", Vector3(1, 1, 2.5), 0.22)
	tw.tween_callback(mi.queue_free)


## 단계 상승: 색이 바뀌며 번쩍, 링이 바깥으로 터진다
func stage_up(st: int) -> void:
	stage = mini(st, 3)
	var c: Color = STAGE_COLORS[stage]
	FX.flash(global_position, c.lerp(Color.WHITE, 0.5), 0.9 + stage * 0.35, 0.1)
	FX.sparks(global_position, 8 + stage * 6, [Color.WHITE, c], 5.0 + stage * 2.0, 0.3, -4.0, 0.07)
	var pos := global_position
	FX.ring(Vector3(pos.x, 0.3, pos.z), 1.6 + stage * 0.9, [c, c.darkened(0.3), Color.WHITE], 0.25)
	FX.shockwave(pos, c, 1.5 + stage * 0.8, 0.25, 0.05)
	if stage >= 3:
		flash_full()


func flash_full() -> void:
	full = true
	var tw := orb.create_tween()
	orb.scale *= 1.8
	tw.tween_property(orb, "scale", orb.scale / 1.8, 0.12)
	FX.flash(global_position, Color.WHITE, 1.4, 0.12)
