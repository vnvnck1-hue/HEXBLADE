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
## 플레이어 기체(컨셉 원화): 크림 장갑 · 회베이지 보조 패널 · 짙은 금속 관절 · 노란 두 눈.
## 무광 도장이라 하이라이트를 거의 끈 mech() 머티리얼로 칠한다.
const M_CREAM := Color("dccda0")
const M_PANEL := Color("aeaca0")
const M_MID := Color("7c7a72")
const M_DARK := Color("3d3c39")
const M_DEEP := Color("252422")
const M_EYE := Color("ffd21a")
const BLADE := Color("ff2e3a")      # 붉은 광선검
const BLADE_CORE := Color("ffd8cc")
const JET := Color("ff3a24")        # 백팩 부스터 불꽃
const JET_CORE := Color("ffd2a0")

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

## 중력 크롤러: 황토색 장갑 · 짙은 금속 뚜껑과 관절 · 파란 삼안 · 약점 코어(붉은 발광)
const CR_YELLOW := Color("d99a26")
const CR_YELLOW_DARK := Color("a8701a")
const CR_METAL := Color("4c4e58")
const CR_METAL_DARK := Color("2a2b32")
const CR_EYE := Color("3d8cff")

const E_BULLETS:Array[Color] = [Color("ff2a1c"), Color("ff6a12"), Color("ffae10"), Color("ffe83a")]

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
static var _parry_mat: ShaderMaterial
static var _parry_flash_mat: ShaderMaterial
static var _parry_charge_mat: ShaderMaterial
## 카툰 렌더링(셀 음영 + 외곽선) 켜짐 여부. 기본 꺼짐. O 키로 전환, 실행 인자 --toon 으로 켠 채 시작
static var toon_on := OS.get_cmdline_user_args().has("--toon")
static var _toon_mats: Array[StandardMaterial3D] = []


## 조명을 받는 저폴리곤 파츠용 머티리얼. 카툰 렌더링: 명암을 두 단으로 끊고 하이라이트도 뚝 끊는다.
## 외곽선은 ToonOutline 후처리가 그린다.
static func lit(c: Color, emission := 0.0) -> StandardMaterial3D:
	var key := "%s_%s" % [c.to_html(), emission]
	if _lit.has(key):
		return _lit[key]
	var m := StandardMaterial3D.new()
	toon(m)
	m.albedo_color = c
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	_lit[key] = m
	return m


## 플레이어 기체용 무광 셀 음영 (하이라이트가 번져 빛나지 않게 반사를 낮춘다)
static func mech(c: Color) -> StandardMaterial3D:
	var key := "mech_%s" % c.to_html()
	if _lit.has(key):
		return _lit[key]
	var m := StandardMaterial3D.new()
	m.set_meta("nospec", true)
	toon(m, 0.95, 0.1, 0.0)
	m.albedo_color = c
	_lit[key] = m
	return m


## 툰 음영 설정. 거칠기가 명암 경계의 부드러움을 정하므로 낮게 둔다.
## plain_* 는 카툰을 껐을 때 돌아갈 일반 음영 값이다.
static func toon(m: StandardMaterial3D, plain_rough := 0.95, plain_spec := 0.2, cel_spec := 0.12) -> void:
	m.set_meta("toon", [plain_rough, plain_spec, cel_spec])
	_toon_mats.append(m)
	_apply_toon(m)


static func _apply_toon(m: StandardMaterial3D) -> void:
	var v: Array = m.get_meta("toon")
	if toon_on:
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		m.specular_mode = BaseMaterial3D.SPECULAR_TOON
		m.roughness = 0.22
		m.metallic_specular = v[2]
		if m.has_meta("nospec"):
			m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	else:
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
		m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		m.roughness = v[0]
		m.metallic_specular = v[1]


## 카툰 렌더링 전체(셀 음영 + 외곽선)를 켜고 끈다
static func set_toon(on: bool) -> void:
	toon_on = on
	for m in _toon_mats:
		_apply_toon(m)
	if is_instance_valid(ToonOutline.inst):
		ToonOutline.inst.visible = on or ToonOutline.inst.brawl_on


## 조명 무시 단색. 색은 인스턴스 파라미터 tint / energy 로 지정한다.
static func flat() -> ShaderMaterial:
	if _flat_mat == null:
		_flat_shader = Shader.new()
		_flat_shader.code = """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float energy = 1.0;
// ROUGHNESS 0 은 ToonOutline 에게 '외곽선 제외' 표식이다
void fragment() { ALBEDO = tint.rgb * energy; ROUGHNESS = 0.0; }
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


## 패링 공격 예고 중인 적 위에 덮는 금빛 발광 (가장자리가 강하고 빠르게 맥동한다)
## 패링 공격 알림 순간 몸체 전체를 덮는 강한 금백색 섬광 (블룸이 걸리게 HDR 로 밝게)
static func parry_flash() -> ShaderMaterial:
	if _parry_flash_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.2);
	ALBEDO = mix(vec3(1.0, 0.86, 0.4), vec3(1.0), 0.45 + rim * 0.55) * 4.0;
	ALPHA = 0.97;
}
"""
		_parry_flash_mat = ShaderMaterial.new()
		_parry_flash_mat.shader = sh
	return _parry_flash_mat


## 패링 공격 준비동작 중인 적 위에 덮는 흰 전신 발광. 인스턴스 값 charge(0~1, 준비 진행도)를 따라
## 처음부터 또렷하게 하얘지고, 끝으로 갈수록 더 밝고 빠르게 맥동한다 (블룸이 걸리게 HDR).
static func parry_charge() -> ShaderMaterial:
	if _parry_charge_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;
instance uniform float charge = 0.0;
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.4);
	float pulse = 0.5 + 0.5 * sin(TIME * mix(16.0, 46.0, charge));
	float k = 0.45 + 0.55 * smoothstep(0.0, 0.7, charge);
	ALBEDO = vec3(1.0, 0.99, 0.96) * (1.6 + charge * 2.4 + rim * 1.4 + pulse * 0.6);
	ALPHA = clamp(k * (0.55 + pulse * 0.2) + rim * 0.6, 0.0, 0.97);
}
"""
		_parry_charge_mat = ShaderMaterial.new()
		_parry_charge_mat.shader = sh
	return _parry_charge_mat


static func parry_glow() -> ShaderMaterial:
	if _parry_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.6);
	float pulse = 0.5 + 0.5 * sin(TIME * 42.0);
	ALBEDO = mix(vec3(1.0, 0.7, 0.12), vec3(1.0, 0.97, 0.85), rim) * 2.2;
	ALPHA = clamp(0.28 + pulse * 0.22 + rim * 0.9, 0.0, 1.0);
}
"""
		_parry_mat = ShaderMaterial.new()
		_parry_mat.shader = sh
	return _parry_mat
