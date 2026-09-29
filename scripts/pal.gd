class_name Pal
extends RefCounted
## 색 규칙과 공용 머티리얼. 플레이어=보라·청록, 적=흰색·빨강, 적탄=주황·노랑.

const FLOOR := Color(0.175, 0.175, 0.29)
const FLOOR_LINE := Color(0.07, 0.07, 0.13)
const OBSTACLE := Color(0.2, 0.2, 0.34)

const P_BODY := Color("5a47b0")
const P_DARK := Color("382b78")
const P_LIGHT := Color("7e6ad8")
const P_GREY := Color("4c4a5e")
const CYAN := Color("35e8ff")
const BLADE := Color("6dff4a")

const E_WHITE := Color("e8e6f0")
const E_GREY := Color("6a6878")
const E_RED := Color("ff1f4a")

## 고정 포탑: 파란 포탑 머리 · 짙은 회색 받침 · 갈색 탄약 상자 · 주황 탄피
const T_BLUE := Color("3f8ee6")
const T_BLUE_LIGHT := Color("6ab4f8")
const T_METAL := Color("5e5c6e")
const T_METAL_LIGHT := Color("8a889a")
const T_DARK := Color("363444")
const T_CRATE := Color("8c4a2c")
const T_CRATE_LIGHT := Color("a8603a")
const T_SHELL := Color("f2c22e")

const E_BULLETS:Array[Color] = [Color("ff2a1c"), Color("ff6a12"), Color("ffae10"), Color("ffe83a")]
const P_BULLET := Color("d8fbff")
## 소총 예광탄: 흰 노랑 심 · 주황 광채
const TRACER_CORE := Color("fff6c0")
const TRACER_GLOW := Color("ffae1e")

const RING_ORANGE: Array[Color] = [Color("ff8a2a"), Color("f0601c"), Color("ffe21a")]
const RING_PINK: Array[Color] = [Color("ff3a8c"), Color("d81a6a"), Color("ff1030")]
const RING_CYAN: Array[Color] = [Color("46f0f0"), Color("ff9a30"), Color("fff030")]
const PUFF_RED: Array[Color] = [Color("ff1848"), Color("ff0f3c"), Color("d0105e"), Color("8a0c5c")]
const PUFF_MAGENTA: Array[Color] = [Color("d4126c"), Color("b80e62"), Color("900c5a"), Color("5e0a4c")]

static var _lit := {}
static var _flat_shader: Shader
static var _flat_mat: ShaderMaterial
static var _flash_mat: StandardMaterial3D
static var _lock_mat: ShaderMaterial


## 조명을 받는 저폴리곤 파츠용 머티리얼
static func lit(c: Color, emission := 0.0) -> StandardMaterial3D:
	var key := "%s_%s" % [c.to_html(), emission]
	if _lit.has(key):
		return _lit[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	m.metallic_specular = 0.2
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	_lit[key] = m
	return m


## 조명 무시 단색. 색은 인스턴스 파라미터 tint / energy 로 지정한다.
static func flat() -> ShaderMaterial:
	if _flat_mat == null:
		_flat_shader = Shader.new()
		_flat_shader.code = """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float energy = 1.0;
void fragment() { ALBEDO = tint.rgb * energy; }
"""
		_flat_mat = ShaderMaterial.new()
		_flat_mat.shader = _flat_shader
	return _flat_mat


static func flat_mesh(mesh: Mesh, c: Color, energy := 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = flat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("tint", c)
	mi.set_instance_shader_parameter("energy", energy)
	return mi


## 피격 순간 파츠 위에 덮어씌우는 흰색 섬광
static func flash() -> StandardMaterial3D:
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.albedo_color = Color(1, 1, 1, 1)
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_mat.albedo_color.a = 0.85
	return _flash_mat


## 락온된 적 위에 덮는 붉은 빗금 (화면 좌표 기준 사선이 흘러간다)
static func lock_hatch() -> ShaderMaterial:
	if _lock_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;
void fragment() {
	float d = (FRAGCOORD.x + FRAGCOORD.y) / 9.0 - TIME * 6.0;
	float stripe = step(0.55, fract(d));
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = mix(vec3(1.0, 0.08, 0.12), vec3(1.0, 0.55, 0.5), rim) * 1.6;
	ALPHA = clamp(mix(0.12, 0.85, stripe) + rim * 0.6, 0.0, 1.0);
}
"""
		_lock_mat = ShaderMaterial.new()
		_lock_mat.shader = sh
	return _lock_mat
