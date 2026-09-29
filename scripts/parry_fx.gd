class_name ParryFX
extends CanvasLayer
## 패링 연출.
## - 화면 오버레이 (실제 시간): 흰 섬광 → 레터박스 · 접촉점을 소실점으로 하는 집중선 · 색수차 · 금빛 그레이딩
##   · 비스듬히 긋는 섬광 띠 · PARRY 타이포. HUD(10)와 임팩트 프레임(9) 아래 층에 둔다.
## - 3D 연출 (정적 함수): 패링 공격 예고(금빛 별 섬광 · 조여드는 링 · 느낌표), 판정 창 신호, 성공 폭발.
## 판정과 무관하며 모두 스스로 수명을 끝낸다.

static var inst: ParryFX
static var _glint_mat: ShaderMaterial
static var _quad: QuadMesh

const GOLD := Color(1.0, 0.78, 0.18)
const HOT := Color(1.0, 0.96, 0.82)
const DURATION := 1.25

var rect: ColorRect
var mat: ShaderMaterial
var title: Label
var sub: Label
var stripes: Array[ColorRect] = []
var _start := -1
var _contact := Vector3.ZERO
var _kind := "melee"

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 center = vec2(0.5);
uniform float aspect = 1.6;
uniform float seed = 0.0;
uniform float lines = 0.0;
uniform float blur = 0.0;
uniform float chroma = 0.0;
uniform float grade = 0.0;
uniform float flash = 0.0;
uniform float bars = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 0.78, 0.2, 1.0);

float hash(float n) { return fract(sin(n * 127.1 + seed * 311.7) * 43758.5453); }

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 to_c = uv - center;
	vec2 p = to_c;
	p.x *= aspect;
	float r = length(p);
	vec2 rd = to_c / max(length(to_c), 1e-4);
	// 접촉점을 향한 방사형 번짐 + 색수차
	float ca = chroma * 0.014 * smoothstep(0.03, 0.7, r);
	vec3 c = vec3(texture(screen_tex, uv - rd * ca).r, texture(screen_tex, uv).g, texture(screen_tex, uv + rd * ca).b);
	if (blur > 0.001) {
		vec3 acc = c;
		float amt = blur * 0.035 * smoothstep(0.08, 0.8, r);
		for (int i = 1; i < 7; i++) {
			acc += texture(screen_tex, uv - to_c * amt * float(i)).rgb;
		}
		c = acc / 7.0;
	}
	// 금빛 그레이딩: 채도를 빼고 금색으로 물들이되 밝은 곳은 살린다
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 g = mix(vec3(l), c, 0.4) * mix(vec3(1.0), tint.rgb * 1.1, 0.45);
	g = mix(g, vec3(1.0, 0.97, 0.9), smoothstep(0.9, 1.3, l) * 0.5);
	c = mix(c, g, grade);
	c *= 1.0 - smoothstep(0.35, 1.1, r) * 0.65 * grade;
	// 집중선: 접촉점에서 뻗는 흰 쐐기. 프레임마다 배치가 바뀐다
	float a = atan(p.y, p.x) / 6.2831853 + 0.5;
	float n = 140.0;
	float cell = floor(a * n);
	float f = fract(a * n);
	float on = step(0.66, hash(cell));
	float w = mix(0.12, 0.6, hash(cell + 7.0));
	float st = mix(0.16, 0.42, hash(cell + 3.0));
	float ln = on * step(abs(f - 0.5), w * 0.5) * smoothstep(st, st + 0.12, r);
	c = mix(c, vec3(1.0, 0.98, 0.9), ln * lines * 0.75);
	c = mix(c, vec3(1.0, 0.99, 0.94), flash);
	float bh = bars * 0.115;
	if (uv.y < bh || uv.y > 1.0 - bh) c = vec3(0.0);
	COLOR = vec4(c, 1.0);
}
"""

const GLINT := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_test_disabled, depth_draw_never, blend_add;
instance uniform float k = 1.0;
instance uniform float rot = 0.0;
instance uniform vec4 tint : source_color = vec4(1.0, 0.78, 0.18, 1.0);
void vertex() {
%s
}
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float cs = cos(rot);
	float sn = sin(rot);
	p = vec2(cs * p.x - sn * p.y, sn * p.x + cs * p.y);
	vec2 q = vec2(p.x + p.y, p.y - p.x) * 0.7071;
	float ax = abs(p.x);
	float ay = abs(p.y);
	// 네 갈래 긴 빛살 + 대각선 짧은 빛살 + 둥근 핵
	float star = max(exp(-ay * 34.0) * pow(max(1.0 - ax, 0.0), 1.6), exp(-ax * 34.0) * pow(max(1.0 - ay, 0.0), 1.6));
	float diag = max(exp(-abs(q.y) * 40.0) * pow(max(1.0 - abs(q.x) * 1.7, 0.0), 2.0), exp(-abs(q.x) * 40.0) * pow(max(1.0 - abs(q.y) * 1.7, 0.0), 2.0));
	float r = length(p);
	float core = exp(-r * 9.0);
	float halo = exp(-r * 3.2) * 0.35;
	float v = (star + diag * 0.55 + core * 1.6 + halo) * k;
	vec3 col = mix(tint.rgb, vec3(1.0), clamp(core * 1.4 + star * 0.4, 0.0, 1.0));
	ALBEDO = col * v * 2.6;
	ALPHA = clamp(v, 0.0, 1.0);
}
"""


func _exit_tree() -> void:
	if inst == self:
		inst = null


func _ready() -> void:
	inst = self
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	mat.shader = sh
	rect.material = mat
	add_child(rect)
	# 화면을 비스듬히 가르는 섬광 띠 (반격의 궤적)
	for i in 2:
		var s := ColorRect.new()
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.color = HOT
		add_child(s)
		stripes.append(s)
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Impact", "Arial Black", "Malgun Gothic", "sans-serif"])
	f.font_weight = 900
	f.font_italic = true
	title = Label.new()
	title.add_theme_font_override("font", f)
	title.add_theme_font_size_override("font_size", 104)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.3))
	title.add_theme_color_override("font_outline_color", Color(0.12, 0.04, 0.0))
	title.add_theme_constant_override("outline_size", 16)
	title.add_theme_color_override("font_shadow_color", Color(1.0, 0.35, 0.05, 0.85))
	title.add_theme_constant_override("shadow_offset_x", 7)
	title.add_theme_constant_override("shadow_offset_y", 6)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	sub = Label.new()
	sub.add_theme_font_override("font", f)
	sub.add_theme_font_size_override("font_size", 34)
	sub.add_theme_color_override("font_color", Color(1.0, 0.97, 0.88))
	sub.add_theme_color_override("font_outline_color", Color(0.12, 0.04, 0.0))
	sub.add_theme_constant_override("outline_size", 10)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sub)
	_hide()


func _hide() -> void:
	visible = false
	_start = -1


## 성공 순간 재생 (contact: 부딪힌 월드 지점)
func play(contact: Vector3, kind: String) -> void:
	_start = Parry.now_ms()
	_contact = contact
	_kind = kind
	visible = true
	mat.set_shader_parameter("seed", randf() * 100.0)
	title.text = "PARRY!"
	sub.text = "REFLECT  ·  되받아치기" if kind == "ranged" else "STAGGER  ·  적 경직"
	title.reset_size()
	sub.reset_size()
	_process(0.0)


func _process(_dt: float) -> void:
	if _start < 0:
		return
	var e := (Parry.now_ms() - _start) * 0.001
	if e >= DURATION:
		_hide()
		if Main.inst and Main.inst.hud:
			Main.inst.hud.root.modulate.a = 1.0
		return
	var vs := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_3d()
	var c := Vector2(0.5, 0.5)
	if cam and not cam.is_position_behind(_contact):
		c = cam.unproject_position(_contact) / vs
		c = c.clamp(Vector2(0.1, 0.1), Vector2(0.9, 0.9))
	mat.set_shader_parameter("center", c)
	mat.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
	# 프레임마다 집중선 배치를 바꿔 떨리게 한다 (처음 0.5초만)
	if e < 0.5 and Engine.get_process_frames() % 2 == 0:
		mat.set_shader_parameter("seed", randf() * 100.0)
	var flash := 1.0 - smoothstep(0.0, 0.13, e)
	var bars := smoothstep(0.0, 0.1, e) * (1.0 - smoothstep(0.85, 1.2, e))
	var lines := (1.0 - smoothstep(0.05, 0.75, e)) * 1.0
	var grade := smoothstep(0.02, 0.1, e) * (1.0 - smoothstep(0.6, 1.05, e))
	var chroma := (1.0 - smoothstep(0.0, 0.8, e))
	var blur := (1.0 - smoothstep(0.0, 0.35, e)) * 0.8
	mat.set_shader_parameter("flash", flash * 0.85)
	mat.set_shader_parameter("bars", bars)
	mat.set_shader_parameter("lines", lines)
	mat.set_shader_parameter("grade", grade)
	mat.set_shader_parameter("chroma", chroma)
	mat.set_shader_parameter("blur", blur)
	if Main.inst and Main.inst.hud:
		Main.inst.hud.root.modulate.a = 1.0 - bars * 0.8
	# 비스듬한 섬광 띠: 접촉점을 지나 화면을 가르며 좁아진다
	var cp := c * vs
	for i in stripes.size():
		var s := stripes[i]
		var d := e - i * 0.035
		var k := clampf(d / 0.16, 0.0, 1.0)
		var th := (1.0 - smoothstep(0.08, 0.3, d)) * (26.0 if i == 0 else 9.0)
		s.visible = d > 0.0 and th > 0.3
		var ln := vs.length() * 1.3 * (1.0 - pow(1.0 - k, 3.0))
		s.size = Vector2(ln, th)
		s.pivot_offset = Vector2(ln * 0.5, th * 0.5)
		s.position = cp - s.pivot_offset + Vector2(0, (i * 2 - 1) * 22.0)
		s.rotation = deg_to_rad(-24.0 if _kind == "melee" else 18.0) + i * 0.06
		s.color = HOT if i == 0 else GOLD
	# 타이포: 크게 박히며 들어와 살짝 밀리다 사라진다
	var tk := clampf(e / 0.12, 0.0, 1.0)
	var sc := lerpf(2.4, 1.0, 1.0 - pow(1.0 - tk, 4.0)) * (1.0 + e * 0.06)
	title.pivot_offset = title.size * 0.5
	title.scale = Vector2(sc, sc)
	title.rotation = deg_to_rad(-6.0)
	var anchor := Vector2(vs.x * 0.5, vs.y * 0.3)
	title.position = anchor - title.size * 0.5 + Vector2(e * 40.0, 0)
	var fade := 1.0 - smoothstep(0.85, 1.15, e)
	title.modulate = Color(1, 1, 1, fade * (0.0 if e < 0.02 else 1.0))
	var sk := clampf((e - 0.1) / 0.15, 0.0, 1.0)
	sub.pivot_offset = sub.size * 0.5
	sub.position = anchor + Vector2(-sub.size.x * 0.5 + lerpf(-80.0, 0.0, 1.0 - pow(1.0 - sk, 3.0)) + e * 25.0, title.size.y * 0.42)
	sub.rotation = deg_to_rad(-6.0)
	sub.modulate = Color(1, 1, 1, sk * fade)


# ── 3D 연출 ─────────────────────────────────────────────

static func _glint_material() -> ShaderMaterial:
	if _glint_mat == null:
		var sh := Shader.new()
		sh.code = GLINT % FX.BILLBOARD
		_glint_mat = ShaderMaterial.new()
		_glint_mat.shader = sh
		_quad = QuadMesh.new()
	return _glint_mat


## 네 갈래 별 섬광 (벽·몸체에 가려지지 않게 깊이 검사 없이 그린다)
static func glint(pos: Vector3, size: float, c: Color, dur := 0.32, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.material_override = _glint_material()
	mi.mesh = _quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.sorting_offset = 10.0
	mi.set_instance_shader_parameter("tint", c)
	mi.set_instance_shader_parameter("k", 1.0)
	var r0 := randf_range(-0.2, 0.2)
	mi.set_instance_shader_parameter("rot", r0)
	if parent:
		parent.add_child(mi)
		mi.global_position = pos
	else:
		FX.root.add_child(mi)
		mi.global_position = pos
	mi.scale = Vector3.ONE * size * 0.05
	var tw := mi.create_tween()
	# 번쩍 커졌다가 (2프레임) 빛살이 돌며 가늘게 사라진다
	tw.tween_property(mi, "scale", Vector3.ONE * size, 0.035).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "scale", Vector3.ONE * size * 0.55, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_method(func(v: float): mi.set_instance_shader_parameter("k", v), 1.0, 0.0, dur).set_ease(Tween.EASE_IN)
	tw.parallel().tween_method(func(v: float): mi.set_instance_shader_parameter("rot", v), r0, r0 + 0.5, dur)
	tw.tween_callback(mi.queue_free)
	return mi


## 패링 공격 예고: 금빛 별 섬광 · 조여드는 금빛 링 · 느낌표 · 경고음
static func warn(pos: Vector3, kind: String) -> void:
	glint(pos, 3.2, GOLD, 0.34)
	glint(pos, 1.6, HOT, 0.2)
	FX.flash(pos, HOT, 0.7, 0.07)
	var ground := Vector3(pos.x, 0.06, pos.z)
	# 바닥 링이 바깥에서 조여든다 (2겹)
	for i in 2:
		var mi := Pal.flat_mesh(FX._ring_mesh(), GOLD if i == 0 else HOT, 2.4)
		FX.root.add_child(mi)
		mi.global_position = ground
		var s0 := 3.4 + i * 0.9
		mi.scale = Vector3(s0, 0.05, s0)
		var tw := mi.create_tween()
		tw.tween_interval(i * 0.04)
		tw.tween_property(mi, "scale", Vector3(0.7, 0.05, 0.7), 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.queue_free)
	# 느낌표: 머리 위로 튀어 오른다
	var l := Label3D.new()
	l.text = "!" if kind == "melee" else "!!"
	l.font_size = 170
	l.outline_size = 34
	l.modulate = Color(1.0, 0.86, 0.25)
	l.outline_modulate = Color(0.25, 0.05, 0.0)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	l.pixel_size = 0.006
	l.render_priority = 10
	FX.root.add_child(l)
	l.global_position = pos + Vector3(0, 1.1, 0)
	l.scale = Vector3.ONE * 0.2
	var tw2 := l.create_tween()
	tw2.tween_property(l, "scale", Vector3.ONE * 1.25, 0.06).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw2.tween_property(l, "scale", Vector3.ONE, 0.08)
	tw2.tween_interval(0.25)
	tw2.tween_property(l, "modulate:a", 0.0, 0.15)
	tw2.parallel().tween_property(l, "outline_modulate:a", 0.0, 0.15)
	tw2.tween_callback(l.queue_free)
	Sfx.play("pwarn", 0.02, 1.0)


## 판정 창이 열리는 순간의 신호: 공격 지점에서 하얗게 한 번 더 번쩍인다
static func cue(pos: Vector3) -> void:
	glint(pos, 2.4, HOT, 0.16)
	FX.flash(pos, HOT, 0.55, 0.05)
	Sfx.play("pcue", 0.0, -2.0)


## 근접 돌진 경로 예고: 바닥에 금빛 띠 (돌진 직전 빠르게 깜빡인다)
static func lunge_marker() -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 0.02, 1.0)
	var mi := Pal.flat_mesh(bm, GOLD, 1.2)
	FX.root.add_child(mi)
	return mi


static func set_lunge_marker(mi: MeshInstance3D, from: Vector3, dir: Vector3, length: float, w: float, k: float) -> void:
	if not is_instance_valid(mi):
		return
	var mid := from + dir * length * 0.5
	mi.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(mid.x, 0.045, mid.z))
	mi.scale = Vector3(w * lerpf(0.4, 1.0, k), 1.0, length * lerpf(0.3, 1.0, sqrt(k)))
	var blink := k > 0.7 and fmod(Parry.now_ms() * 0.001, 0.07) < 0.035
	mi.set_instance_shader_parameter("tint", HOT if blink else GOLD.lerp(Color(1.0, 0.45, 0.1), 0.3))
	mi.set_instance_shader_parameter("energy", lerpf(0.8, 2.4, k))


## 패링 성공 폭발 (접촉점 · 반격 방향)
static func burst(pos: Vector3, dir: Vector3, kind: String) -> void:
	# 슬로우모션(0.12배) 중에 재생되므로 게임 시간으로는 짧게 잡는다. 카메라가 바로 옆까지 파고들어도 화면을 덮지 않는 크기.
	glint(pos, 3.2, GOLD, 0.1)
	glint(pos, 1.8, HOT, 0.06)
	FX.flash(pos, Color.WHITE, 0.8, 0.04)
	FX.flash(pos, GOLD, 0.5, 0.07)
	FX.ring(Vector3(pos.x, 0.0, pos.z), 2.2, [GOLD, Color(1.0, 0.5, 0.1), HOT], 0.3)
	for i in 3:
		FX.shockwave(pos, [HOT, GOLD, Color(1.0, 0.5, 0.15)][i], 3.5 + i * 2.0, 0.25 + i * 0.1, 0.08 - i * 0.02)
	FX.sparks(pos, 40, [Color.WHITE, HOT, GOLD, Color(1.0, 0.45, 0.1)], 18.0, 0.4, -9.0, 0.04)
	FX.sparks(pos, 10, [Color.WHITE, GOLD], 9.0, 0.5, -3.0, 0.06)
	# 반격 궤적: 접촉점을 가로지르는 날카로운 빛줄기
	var side := Vector3(-dir.z, 0, dir.x)
	for i in 2:
		var bm := BoxMesh.new()
		bm.size = Vector3(1.0, 1.0, 1.0)
		var mi := Pal.flat_mesh(bm, HOT if i == 0 else GOLD, 3.2)
		FX.root.add_child(mi)
		var tilt := Basis(dir, (0.55 if kind == "melee" else -0.35) + i * 0.25)
		var b := tilt * Basis(side, Vector3.UP, -dir)
		mi.global_transform = Transform3D(b.orthonormalized(), pos)
		mi.scale = Vector3(0.2, 0.05, 0.05)
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3(4.5 - i * 1.2, 0.05, 0.05), 0.03).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3(5.5 - i * 1.2, 0.004, 0.004), 0.12).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.queue_free)
	# 순간 조명
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.35)
	light.light_energy = 8.0
	light.omni_range = 9.0
	FX.root.add_child(light)
	light.global_position = pos + Vector3(0, 0.4, 0)
	var ltw := light.create_tween()
	ltw.tween_property(light, "light_energy", 0.0, 0.25).set_ease(Tween.EASE_IN)
	ltw.tween_callback(light.queue_free)


## 경직 머리 위 별: 금빛 조각이 빙글빙글 돈다 (노드를 돌려주면 호출 쪽이 돌리고 지운다)
static func stun_halo(parent: Node3D) -> Node3D:
	var h := Node3D.new()
	parent.add_child(h)
	var pm := PrismMesh.new()
	pm.size = Vector3(0.16, 0.2, 0.05)
	for i in 4:
		var a := TAU * i / 4.0
		var mi := Pal.flat_mesh(pm, GOLD if i % 2 == 0 else HOT, 2.2)
		h.add_child(mi)
		mi.position = Vector3(cos(a), 0, sin(a)) * 0.55
		mi.rotation = Vector3(0, -a, 0.4)
	return h
