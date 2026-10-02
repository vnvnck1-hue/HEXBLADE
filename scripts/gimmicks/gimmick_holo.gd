class_name GimmickHolo
extends RefCounted
## 연기 속 은신 표현 (연출 전용): 기체 파츠를 빗금 홀로그램으로 바꾼다.
## 깊이 검사를 끄고 연기보다 늦게 그려서 연기 너머에서도 자기 기체 윤곽이 보인다.
## 원래 material_override 와 그림자 설정은 메타에 기억했다가 remove 에서 되돌린다.
## (피격 섬광은 material_overlay 를 쓰므로 겹치지 않는다)

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, depth_test_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.35, 0.9, 1.0, 1.0);
uniform float fade = 1.0;
void fragment() {
	vec2 fc = FRAGCOORD.xy;
	// 45° 빗금이 천천히 흘러내린다
	float s = fract((fc.x + fc.y) / 7.0 + TIME * 1.4);
	float hatch = smoothstep(0.62, 0.5, s) * smoothstep(0.0, 0.12, s);
	// 가로 주사선 띠가 아래로 지나간다
	float scan = smoothstep(0.04, 0.0, abs(fract(fc.y / 260.0 - TIME * 0.35) - 0.5));
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.2);
	float flick = 0.9 + 0.1 * sin(TIME * 37.0) * sin(TIME * 11.0);
	float k = (hatch * 0.32 + rim * 0.95 + scan * 0.35 + 0.035) * flick * fade;
	ALBEDO = tint.rgb * k;
	ROUGHNESS = 0.0;
}
"""

static var _mat: ShaderMaterial


static func material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_mat.render_priority = 20
	return _mat


static func apply(p: Player) -> void:
	if p.has_meta("_holo"):
		return
	var saved := []
	for mi: MeshInstance3D in p.visual.find_children("*", "MeshInstance3D", true, false):
		saved.append([mi, mi.material_override, mi.cast_shadow])
		mi.material_override = material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.set_meta("_holo", saved)
	if is_instance_valid(p.shadow):
		p.shadow.visible = false
	FX.flash(p.global_position + Vector3(0, 0.9, 0), Color("8ad8ff"), 1.0, 0.1)
	Sfx.play("slowin", 0.05, -14.0)


static func remove(p: Player) -> void:
	if not p.has_meta("_holo"):
		return
	for s in p.get_meta("_holo"):
		var mi = s[0]
		if is_instance_valid(mi):
			(mi as MeshInstance3D).material_override = s[1]
			(mi as MeshInstance3D).cast_shadow = s[2]
	p.remove_meta("_holo")
	if is_instance_valid(p.shadow):
		p.shadow.visible = true
	FX.flash(p.global_position + Vector3(0, 0.9, 0), Color("b8c8ff"), 0.8, 0.08)


static func active(p: Player) -> bool:
	return p.has_meta("_holo")
