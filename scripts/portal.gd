class_name SectorPortal
extends Node3D
## 방 출구의 육각 포탈. 바닥 발판 + 세워진 육각 틀 + 안쪽 소용돌이 막 + 떠 있는 다음 방 표식.
## open() 으로 바닥에서 솟아오르고, 플레이어가 발판에 올라서면 entered 가 한 번 울린다.

signal entered(portal: SectorPortal)

const G := preload("res://scripts/sector_graph.gd")
const HEX_R := 1.05
const CENTER_Y := 1.45
const TRIGGER_R := 1.05

var node_id := -1
var kind := 0
var title := ""
var detail := ""
var color := Color.WHITE
var is_open := false
var used := false
var frame: Node3D
var membrane: MeshInstance3D
var inner: Node3D
var pad: MeshInstance3D
var label: Label3D
var light: OmniLight3D
var _t := 0.0

const MEMBRANE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, blend_add;
uniform vec4 tint : source_color = vec4(1.0);
uniform float open = 1.0;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	vec2 p = lp.xz;
	float r = length(p);
	float a = atan(p.y, p.x);
	float swirl = sin(a * 3.0 + r * 9.0 - TIME * 5.0) * 0.5 + 0.5;
	float rings = sin(r * 22.0 - TIME * 9.0) * 0.5 + 0.5;
	float core = 1.0 - smoothstep(0.0, 1.0, r);
	float k = (swirl * 0.55 + rings * 0.25) * (0.35 + r) + core * 0.6;
	ALBEDO = mix(tint.rgb, vec3(1.0), core * 0.5) * k * 1.6 * open;
	ALPHA = 1.0;
	ROUGHNESS = 0.0;
}
"""


func setup(p_node_id: int, p_kind: int, p_title: String, p_detail: String) -> void:
	node_id = p_node_id
	kind = p_kind
	title = p_title
	detail = p_detail
	color = G.KIND_COLORS[kind]


func _ready() -> void:
	# 바닥 발판 (평평한 헥스)
	var pm := CylinderMesh.new()
	pm.radial_segments = 6
	pm.rings = 1
	pm.top_radius = 1.25
	pm.bottom_radius = 1.35
	pm.height = 0.08
	pad = MeshInstance3D.new()
	pad.mesh = pm
	pad.material_override = Pal.lit(Color(0.12, 0.12, 0.22))
	pad.position.y = 0.04
	pad.rotation.y = PI / 6.0
	add_child(pad)
	var rim := TorusMesh.new()
	rim.inner_radius = 1.12
	rim.outer_radius = 1.22
	rim.ring_segments = 6
	rim.rings = 6
	var rim_mi := Pal.flat_mesh(rim, color, 1.4)
	rim_mi.position.y = 0.09
	rim_mi.scale = Vector3(1, 0.3, 1)
	rim_mi.rotation.y = PI / 6.0
	add_child(rim_mi)

	frame = Node3D.new()
	add_child(frame)
	# 세워진 육각 틀: 막대 6개
	for i in 6:
		var a0 := deg_to_rad(60.0 * i + 30.0)
		var a1 := deg_to_rad(60.0 * (i + 1) + 30.0)
		var p0 := Vector3(cos(a0), sin(a0), 0) * HEX_R
		var p1 := Vector3(cos(a1), sin(a1), 0) * HEX_R
		var bm := BoxMesh.new()
		bm.size = Vector3(p0.distance_to(p1) + 0.12, 0.16, 0.22)
		var bar := MeshInstance3D.new()
		bar.mesh = bm
		bar.material_override = Pal.lit(Color(0.22, 0.2, 0.36))
		bar.position = (p0 + p1) * 0.5 + Vector3(0, CENTER_Y, 0)
		bar.rotation.z = atan2(p1.y - p0.y, p1.x - p0.x)
		frame.add_child(bar)
		var gm := BoxMesh.new()
		gm.size = Vector3(bm.size.x - 0.1, 0.05, 0.25)
		var glow := Pal.flat_mesh(gm, color, 2.2)
		glow.position = bar.position - Vector3(cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5), 0) * 0.07
		glow.rotation = bar.rotation
		frame.add_child(glow)
	# 안쪽 소용돌이 막: 헥스 원판을 세운다
	var dm := CylinderMesh.new()
	dm.radial_segments = 6
	dm.rings = 1
	dm.top_radius = HEX_R * 0.92
	dm.bottom_radius = HEX_R * 0.92
	dm.height = 0.01
	membrane = MeshInstance3D.new()
	membrane.mesh = dm
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = MEMBRANE_SHADER
	mat.shader = sh
	mat.set_shader_parameter("tint", color)
	membrane.material_override = mat
	membrane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	membrane.rotation = Vector3(PI / 2.0, 0, PI / 6.0)
	membrane.position.y = CENTER_Y
	frame.add_child(membrane)
	# 안쪽에서 도는 작은 헥스 링
	inner = Node3D.new()
	inner.position.y = CENTER_Y
	frame.add_child(inner)
	var ir := TorusMesh.new()
	ir.inner_radius = 0.5
	ir.outer_radius = 0.56
	ir.ring_segments = 6
	ir.rings = 6
	var ir_mi := Pal.flat_mesh(ir, color.lightened(0.4), 2.0)
	ir_mi.rotation.x = PI / 2.0
	inner.add_child(ir_mi)

	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	label.pixel_size = 0.006
	label.font = SectorMapView.make_font()
	label.font_size = 64
	label.outline_size = 14
	label.outline_modulate = Color(0.02, 0.02, 0.06, 0.9)
	label.modulate = color.lightened(0.35)
	label.text = title
	label.position.y = CENTER_Y + HEX_R + 0.55
	add_child(label)
	var sub := Label3D.new()
	sub.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sub.no_depth_test = true
	sub.pixel_size = 0.006
	sub.font = label.font
	sub.font_size = 38
	sub.outline_size = 10
	sub.outline_modulate = Color(0.02, 0.02, 0.06, 0.9)
	sub.modulate = Color(0.85, 0.88, 1.0)
	sub.text = detail
	sub.position.y = CENTER_Y + HEX_R + 0.12
	label.add_child(sub)
	sub.position = Vector3(0, -0.42, 0)

	light = OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.0
	light.omni_range = 5.0
	light.position = Vector3(0, CENTER_Y, 0.6)
	add_child(light)

	# 닫힌 상태: 바닥 아래에 숨긴다
	frame.scale = Vector3(1, 0.001, 1)
	frame.visible = false
	label.visible = false


func open(delay := 0.0) -> void:
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func():
		frame.visible = true
		FX.shockwave(global_position + Vector3(0, 0.1, 0), color, 2.6, 0.4)
		FX.sparks(global_position + Vector3(0, 0.2, 0), 14, [color, Color.WHITE], 6.0, 0.5, -10.0, 0.07)
		Sfx.play("hrise", 0.05, -4.0))
	tw.tween_property(frame, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(light, "light_energy", 2.2, 0.45)
	tw.tween_callback(func():
		is_open = true
		label.visible = true
		label.scale = Vector3(0.6, 0.6, 0.6)
		label.create_tween().tween_property(label, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Sfx.play("charged", 0.05, -6.0))


## 고르지 않은 포탈은 닫는다
func close() -> void:
	is_open = false
	var tw := create_tween()
	tw.tween_property(frame, "scale", Vector3(1, 0.001, 1), 0.3).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(light, "light_energy", 0.0, 0.3)
	tw.tween_callback(func():
		frame.visible = false
		label.visible = false)


func _process(dt: float) -> void:
	_t += dt
	if inner:
		inner.rotation.z = _t * 1.6
		var s := 1.0 + sin(_t * 4.0) * 0.06
		inner.scale = Vector3(s, s, s)
	if light and is_open:
		light.light_energy = 2.0 + sin(_t * 7.0) * 0.4
	if label and label.visible:
		label.position.y = CENTER_Y + HEX_R + 0.55 + sin(_t * 2.2) * 0.06


func _physics_process(_dt: float) -> void:
	if not is_open or used:
		return
	var m := Main.inst
	if m == null or m.player == null or not m.player.alive:
		return
	var d := m.player.global_position - global_position
	d.y = 0
	if d.length() < TRIGGER_R:
		used = true
		entered.emit(self)
