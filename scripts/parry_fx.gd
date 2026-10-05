class_name ParryFX
extends CanvasLayer
## 패링 연출.
## - 화면 오버레이 (실제 시간, 아주 짧게): 옅은 섬광 · 접촉점 집중선 · 색수차 · 화면을 거의 가로지르는 얇은 섬광선.
##   전투 속도감을 위해 글자·레터박스·그레이딩 없이 0.25초 안에 끝난다. HUD(10)와 임팩트 프레임(9) 아래 층에 둔다.
## - 3D 연출 (정적 함수): 패링 공격 알림(크고 얇은 십자 별빛), 판정 창 신호, 성공 폭발.
## 판정과 무관하며 모두 스스로 수명을 끝낸다.

static var inst: ParryFX
static var _glint_mat: ShaderMaterial
static var _star_mat: ShaderMaterial
static var _quad: QuadMesh
static var _box: BoxMesh        # 반격 빛줄기 (단위 상자, 크기는 scale 로)
static var _prism: PrismMesh    # 경직 별 조각

const GOLD := Color(1.0, 0.78, 0.18)
const HOT := Color(1.0, 0.96, 0.82)
const DURATION := 0.3
## 알림 별빛: 한 변 길이(월드) · 가로 → 세로 트윈 한 번씩 · 사라짐 (게임 초).
## 공격이 0.4초 만에 닿으므로 두 축의 트윈은 그 안에 끝나고, 사라짐만 조금 더 남는다.
## 패링 공격 별빛은 붉은 위험 섬광(패링 불가)의 절반 크기다.
const STAR_SIZE := 12.0
const DANGER_STAR_SIZE := 24.0
const STAR_AXIS := 0.1
const STAR_FADE := 0.16

var rect: ColorRect
var mat: ShaderMaterial
## 화면을 가르는 얇은 섬광선: [글로우, 심지]
var streaks: Array[Line2D] = []
var _start := -1
var _contact := Vector3.ZERO
var _kind := "melee"
var _tilt := 0.0

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 center = vec2(0.5);
uniform float aspect = 1.6;
uniform float seed = 0.0;
uniform float lines = 0.0;
uniform float chroma = 0.0;
uniform float flash = 0.0;

float hash(float n) { return fract(sin(n * 127.1 + seed * 311.7) * 43758.5453); }

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 to_c = uv - center;
	vec2 p = to_c;
	p.x *= aspect;
	float r = length(p);
	vec2 rd = to_c / max(length(to_c), 1e-4);
	// 접촉점을 향한 색수차
	float ca = chroma * 0.01 * smoothstep(0.03, 0.7, r);
	vec3 c = vec3(texture(screen_tex, uv - rd * ca).r, texture(screen_tex, uv).g, texture(screen_tex, uv + rd * ca).b);
	// 집중선: 접촉점에서 뻗는 흰 쐐기. 프레임마다 배치가 바뀐다
	float a = atan(p.y, p.x) / 6.2831853 + 0.5;
	float n = 140.0;
	float cell = floor(a * n);
	float f = fract(a * n);
	float on = step(0.72, hash(cell));
	float w = mix(0.1, 0.45, hash(cell + 7.0));
	float st = mix(0.22, 0.48, hash(cell + 3.0));
	float ln = on * step(abs(f - 0.5), w * 0.5) * smoothstep(st, st + 0.12, r);
	c = mix(c, vec3(1.0, 0.98, 0.9), ln * lines * 0.6);
	c = mix(c, vec3(1.0, 0.99, 0.94), flash);
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

## 알림 십자 별빛: 가로·세로 두 줄기만 있는 아주 얇고 긴 빛살.
## lx / ly = 각 줄기의 길이(쿼드 반폭 기준), wx / wy = 굵기 배율. 줄기마다 따로 트윈한다.
const STAR := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_test_disabled, depth_draw_never, blend_add;
instance uniform float k = 1.0;
instance uniform float lx = 0.0;
instance uniform float ly = 0.0;
instance uniform float wx = 1.0;
instance uniform float wy = 1.0;
instance uniform vec4 tint : source_color = vec4(1.0, 0.78, 0.18, 1.0);
void vertex() {
%s
}
float ray(float along, float across, float len, float w) {
	float l = max(len, 1e-3);
	float fall = pow(max(1.0 - along / l, 0.0), 1.5) * step(1e-3, len);
	float th = 190.0 / max(w, 0.05);
	return (exp(-across * th) + exp(-across * th * 0.14) * 0.45 + exp(-across * th * 0.04) * 0.12) * fall;
}
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float ax = abs(p.x);
	float ay = abs(p.y);
	float h = ray(ax, ay, lx, wx);
	float v = ray(ay, ax, ly, wy);
	float r = length(p);
	float core = (exp(-r * 30.0) * 2.0 + exp(-r * 7.0) * 0.35) * max(lx, ly);
	float s = (h + v + core) * k;
	vec3 col = mix(tint.rgb, vec3(1.0), clamp(core + max(exp(-ay * 190.0 / max(wx, 0.05)) * h, exp(-ax * 190.0 / max(wy, 0.05)) * v) * 0.9, 0.0, 1.0));
	ALBEDO = col * s * 5.0;
	ALPHA = clamp(s, 0.0, 1.0);
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
	# 화면을 거의 가로지르는 얇은 섬광선: 양 끝이 가늘어지는 금빛 글로우 위에 흰 심지
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 0.0))
	taper.add_point(Vector2(0.5, 1.0))
	taper.add_point(Vector2(1.0, 0.0))
	for i in 2:
		var l := Line2D.new()
		l.width_curve = taper
		l.antialiased = true
		l.default_color = Color(GOLD, 0.55) if i == 0 else Color(1.0, 0.99, 0.95)
		l.points = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT])
		add_child(l)
		streaks.append(l)
	_hide()


func _hide() -> void:
	visible = false
	_start = -1


## 성공 순간 재생 (contact: 부딪힌 월드 지점)
func play(contact: Vector3, kind: String) -> void:
	_start = Parry.now_ms()
	_contact = contact
	_kind = kind
	_tilt = deg_to_rad(randf_range(6.0, 11.0) * (-1.0 if kind == "melee" else 1.0))
	visible = true
	mat.set_shader_parameter("seed", randf() * 100.0)
	_process(0.0)


func _process(_dt: float) -> void:
	if _start < 0:
		return
	# 흑백 임팩트 프레임(위층)이 도는 동안은 가려지므로, 끝난 뒤부터 타임라인을 시작한다
	if ImpactFrame.inst and ImpactFrame.inst.active():
		_start = Parry.now_ms()
	var e := (Parry.now_ms() - _start) * 0.001
	if e >= DURATION:
		_hide()
		return
	var vs := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_3d()
	var c := Vector2(0.5, 0.5)
	if cam and not cam.is_position_behind(_contact):
		c = cam.unproject_position(_contact) / vs
		c = c.clamp(Vector2(0.1, 0.1), Vector2(0.9, 0.9))
	mat.set_shader_parameter("center", c)
	mat.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
	if Engine.get_process_frames() % 2 == 0:
		mat.set_shader_parameter("seed", randf() * 100.0)
	mat.set_shader_parameter("flash", (1.0 - smoothstep(0.0, 0.05, e)) * 0.35)
	mat.set_shader_parameter("lines", 1.0 - smoothstep(0.02, 0.16, e))
	mat.set_shader_parameter("chroma", 1.0 - smoothstep(0.0, 0.14, e))
	# 섬광선: 접촉점 높이에서 화면 폭의 대부분을 순식간에 긋고, 길이는 남긴 채 가늘어지며 사라진다
	var grow := 1.0 - pow(1.0 - clampf(e / 0.04, 0.0, 1.0), 3.0)
	var thin := 1.0 - smoothstep(0.07, 0.28, e)
	var mid := Vector2(vs.x * 0.5, c.y * vs.y)
	var half := Vector2(cos(_tilt), sin(_tilt)) * vs.x * 0.47 * grow * (1.0 + e * 0.15)
	for i in streaks.size():
		var l := streaks[i]
		# 너비 곡선은 점마다 샘플링되므로 중간 점을 촘촘히 둔다 (양 끝만 두면 너비가 0)
		var pts := PackedVector2Array()
		for q in 17:
			pts.append(mid - half + half * 2.0 * (q / 16.0))
		l.points = pts
		l.width = (16.0 if i == 0 else 3.5) * thin
		l.visible = thin > 0.02


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


static func _star_material() -> ShaderMaterial:
	if _star_mat == null:
		var sh := Shader.new()
		sh.code = STAR % FX.BILLBOARD
		_star_mat = ShaderMaterial.new()
		_star_mat.shader = sh
		_glint_material()
	return _star_mat


## 패링 공격 알림: 준비동작이 끝나는 순간 공격 지점에 크고 얇은 십자 별빛.
## 가로 줄기가 먼저 과장되게 쭉 뻗었다 튕겨 돌아오고, 이어서 세로 줄기가 똑같이 한 번. 그 뒤 사라진다.
## parent 를 주면 그 노드를 따라다닌다.
## kind 가 "danger" 면 패링이 안 되는 공격의 붉은 섬광이다 (DangerFX.warn 이 부른다): 색 · 조명 · 소리만 바뀐다.
static func warn(pos: Vector3, kind: String, parent: Node3D = null) -> MeshInstance3D:
	var danger := kind == "danger"
	var tint := DangerFX.RED if danger else GOLD
	var mi := MeshInstance3D.new()
	mi.material_override = _star_material()
	mi.mesh = _quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.sorting_offset = 12.0
	mi.set_instance_shader_parameter("tint", tint)
	mi.set_instance_shader_parameter("k", 1.0)
	mi.set_instance_shader_parameter("lx", 0.0)
	mi.set_instance_shader_parameter("ly", 0.0)
	(parent if parent else FX.root).add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * (DANGER_STAR_SIZE if danger else STAR_SIZE)
	var setp := func(v: float, key: String) -> void:
		mi.set_instance_shader_parameter(key, v)
	var tw := mi.create_tween()
	for key in ["x", "y"]:
		var len_key: String = "l" + key
		var w_key: String = "w" + key
		# 과장된 한 번: 쿼드 끝까지 순식간에 뻗으며 굵어졌다가, 되튕기며 가늘게 제자리를 찾는다
		tw.tween_method(setp.bind(len_key), 0.0, 1.0, STAR_AXIS * 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_method(setp.bind(w_key), 0.4, 3.4, STAR_AXIS * 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.tween_method(setp.bind(len_key), 1.0, 0.6, STAR_AXIS * 0.65).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_method(setp.bind(w_key), 3.4, 1.4, STAR_AXIS * 0.65).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(setp.bind("k"), 1.0, 0.0, STAR_FADE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_method(setp.bind("lx"), 0.6, 0.35, STAR_FADE)
	tw.parallel().tween_method(setp.bind("ly"), 0.6, 0.35, STAR_FADE)
	tw.tween_callback(mi.queue_free)
	# 별빛 중심의 강한 섬광과 순간 조명
	FX.flash(pos, Color.WHITE, 1.3, 0.06)
	FX.flash(pos, tint, 2.2, 0.12)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.25, 0.22) if danger else Color(1.0, 0.82, 0.4)
	light.light_energy = 7.0
	light.omni_range = 8.0
	FX.root.add_child(light)
	light.global_position = pos
	var ltw := light.create_tween()
	ltw.tween_property(light, "light_energy", 0.0, 0.22).set_ease(Tween.EASE_IN)
	ltw.tween_callback(light.queue_free)
	var snd := Sfx.play("pwarn", 0.02, 1.0)
	if danger and snd:
		# 붉은 섬광은 한 옥타브 가까이 낮게: 색을 못 봐도 소리로 구분된다
		snd.pitch_scale = 0.62
	return mi


## 판정 창이 열리는 순간의 신호: 공격 지점에서 하얗게 한 번 더 번쩍인다
static func cue(pos: Vector3) -> void:
	glint(pos, 2.4, HOT, 0.16)
	FX.flash(pos, HOT, 0.55, 0.05)
	Sfx.play("pcue", 0.0, -2.0)


## 패링 성공 폭발 (접촉점 · 반격 방향)
static func burst(pos: Vector3, dir: Vector3, kind: String) -> void:
	# 슬로우모션은 몇 프레임뿐이라 거의 정상 속도로 재생된다: 번쩍 터지고 빠르게 걷힌다
	glint(pos, 3.4, GOLD, 0.16)
	glint(pos, 1.9, HOT, 0.1)
	FX.flash(pos, Color.WHITE, 0.8, 0.05)
	FX.flash(pos, GOLD, 0.5, 0.09)
	FX.ring(Vector3(pos.x, Main.gy(pos), pos.z), 2.2, [GOLD, Color(1.0, 0.5, 0.1), HOT], 0.3)
	for i in 3:
		FX.shockwave(pos, [HOT, GOLD, Color(1.0, 0.5, 0.15)][i], 3.5 + i * 2.0, 0.25 + i * 0.1, 0.08 - i * 0.02)
	FX.sparks(pos, 40, [Color.WHITE, HOT, GOLD, Color(1.0, 0.45, 0.1)], 18.0, 0.4, -9.0, 0.04)
	FX.sparks(pos, 10, [Color.WHITE, GOLD], 9.0, 0.5, -3.0, 0.06)
	# 반격 궤적: 접촉점을 가로지르는 날카로운 빛줄기
	var side := Vector3(-dir.z, 0, dir.x)
	for i in 2:
		if _box == null:
			_box = BoxMesh.new()
			_box.size = Vector3(1.0, 1.0, 1.0)
		var mi := Pal.flat_mesh(_box, HOT if i == 0 else GOLD, 3.2)
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
	if _prism == null:
		_prism = PrismMesh.new()
		_prism.size = Vector3(0.16, 0.2, 0.05)
	var pm := _prism
	for i in 4:
		var a := TAU * i / 4.0
		var mi := Pal.flat_mesh(pm, GOLD if i % 2 == 0 else HOT, 2.2)
		h.add_child(mi)
		mi.position = Vector3(cos(a), 0, sin(a)) * 0.55
		mi.rotation = Vector3(0, -a, 0.4)
	return h
