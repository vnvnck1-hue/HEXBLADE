class_name DroneFX
extends RefCounted
## 파트너 드론 연출: 흡입(원뿔 기류 + 빨려 드는 알갱이) · 청소 끝 반짝임 · 체액 거품 · 돌파 보호막 · 연결 빔 · 볼텍스.
## 텍스처는 코드로 그린 두 장(별 · 둥근 점)뿐이고 머티리얼은 정적 캐시(고정 개수)라 씬을 다시 불러도 늘지 않는다.

const MINT := Color("62ffc4")
const MINT_SOFT := Color("bffff0")

static var _star_mat: StandardMaterial3D
static var _dot_mat: StandardMaterial3D
static var _quad: QuadMesh
static var _cone_shader: Shader
static var _shield_shader: Shader
static var _shield_moco: Shader
static var _beam_mesh: CylinderMesh


static func _tex(kind: String) -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := (y + 0.5) / n * 2.0 - 1.0
			var a := 0.0
			if kind == "star":
				# 네 갈래 반짝임: 가는 십자 + 가운데 둥근 빛
				var cross := maxf(maxf(0.0, 1.0 - absf(u) * 9.0) * (1.0 - absf(v)), maxf(0.0, 1.0 - absf(v) * 9.0) * (1.0 - absf(u)))
				a = clampf(cross * 1.4 + maxf(0.0, 1.0 - sqrt(u * u + v * v) * 3.0), 0.0, 1.0)
			else:
				a = clampf(1.0 - sqrt(u * u + v * v), 0.0, 1.0)
				a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


static func _billboard(kind: String, c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.no_depth_test = false
	m.albedo_texture = _tex(kind)
	m.render_priority = 4
	return m


static func _init_mats() -> void:
	if _quad:
		return
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE
	_star_mat = _billboard("star", Color(0.85, 1.0, 0.95))
	_dot_mat = _billboard("dot", MINT_SOFT)


## 청소 끝: 별 3~4개가 톡톡 피었다 진다
static func twinkle(pos: Vector3, r: float) -> void:
	_init_mats()
	var parent := FX.root if is_instance_valid(FX.root) else null
	if parent == null:
		return
	for i in 4:
		var mi := MeshInstance3D.new()
		mi.mesh = _quad
		mi.material_override = _star_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		var a := randf() * TAU
		mi.global_position = pos + Vector3(cos(a) * r * 0.7, randf_range(0.0, 0.5), sin(a) * r * 0.7)
		mi.scale = Vector3.ZERO
		var s := randf_range(0.35, 0.6)
		var tw := mi.create_tween()
		tw.tween_interval(i * 0.06)
		tw.tween_property(mi, "scale", Vector3.ONE * s, 0.1).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3.ZERO, 0.28).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.queue_free)


## 체액 웅덩이 거품: 부풀었다 톡 터진다
static func bubble(pos: Vector3, mat: Material) -> void:
	var parent := FX.root if is_instance_valid(FX.root) else null
	if parent == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = DroneMess._ball
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.02
	var s := randf_range(0.08, 0.15)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * s, 0.45).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "scale", Vector3.ONE * s * 1.3, 0.05)
	tw.tween_callback(mi.queue_free)


# ═══════════════════════════════════════════════════
#  흡입: 흡입구(노즐) ← 원뿔 기류 ← 오염. 알갱이가 나선을 그리며 빨려 든다.
# ═══════════════════════════════════════════════════
class Suction extends Node3D:
	const POOL := 26
	var on := 0.0                  ## 세기 0~1
	var from := Vector3.ZERO       ## 오염 자리 (월드)
	var nozzle: Node3D             ## 빨아들이는 곳
	var col := MINT
	var width := 0.6
	var cone: MeshInstance3D
	var mat: ShaderMaterial
	var bits: Array = []           ## [mesh, t, life, 시작 오프셋, 위상, 색]
	var _emit := 0.0

	func _ready() -> void:
		top_level = true
		DroneFX._init_mats()
		if DroneFX._cone_shader == null:
			DroneFX._cone_shader = Shader.new()
			DroneFX._cone_shader.code = DroneFX.CONE_CODE
		mat = ShaderMaterial.new()
		mat.shader = DroneFX._cone_shader
		var cm := CylinderMesh.new()
		cm.top_radius = 0.07
		cm.bottom_radius = 0.5
		cm.height = 1.0
		cm.radial_segments = 20
		cm.rings = 1
		cm.cap_top = false
		cm.cap_bottom = false
		cone = MeshInstance3D.new()
		cone.mesh = cm
		cone.material_override = mat
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cone)
		for i in POOL:
			var mi := MeshInstance3D.new()
			mi.mesh = DroneFX._quad
			mi.material_override = DroneFX._dot_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visible = false
			add_child(mi)
			bits.append([mi, 1.0, 0.4, Vector3.ZERO, 0.0])

	func _process(dt: float) -> void:
		if not is_instance_valid(nozzle):
			visible = false
			return
		# 꺼져 있고 날아가는 알갱이도 없으면 할 일이 없다 (드론에 흡입 줄기가 10개 붙어 있어 쉬는 동안의 비용을 없앤다)
		if on <= 0.01 and not _bits_live:
			if visible:
				visible = false
			return
		var to := nozzle.global_position
		visible = on > 0.01 or _any_bits()
		_bits_live = visible
		cone.visible = on > 0.01
		if cone.visible:
			var d := to - from
			var l := d.length()
			if l > 0.05:
				var y := d / l
				var x := y.cross(Vector3.UP)
				if x.length() < 0.01:
					x = Vector3.RIGHT
				x = x.normalized()
				var z := x.cross(y)
				cone.global_transform = Transform3D(Basis(x * width * 2.0, y * l, z * width * 2.0), from + d * 0.5)
			mat.set_shader_parameter("k", on)
			mat.set_shader_parameter("tint", col)
		# 알갱이: 오염 위 흩어진 자리에서 나선을 그리며 노즐로
		_emit += dt * 40.0 * on
		for b: Array in bits:
			var mi: MeshInstance3D = b[0]
			if float(b[1]) >= 1.0:
				if _emit >= 1.0:
					_emit -= 1.0
					b[1] = 0.0
					b[2] = randf_range(0.25, 0.42)
					var a := randf() * TAU
					b[3] = Vector3(cos(a), randf_range(0.05, 0.5), sin(a)) * randf_range(0.2, width * 1.1)
					b[4] = randf() * TAU
					mi.visible = true
				else:
					mi.visible = false
					continue
			b[1] = float(b[1]) + dt / float(b[2])
			var k := minf(float(b[1]), 1.0)
			var e := k * k
			var start: Vector3 = from + (b[3] as Vector3)
			var p := start.lerp(to, e)
			var ax := (to - start).normalized()
			var side := ax.cross(Vector3.UP).normalized()
			var up := side.cross(ax)
			var r := (1.0 - e) * 0.18
			var ph := float(b[4]) + k * 9.0
			p += (side * cos(ph) + up * sin(ph)) * r
			mi.global_position = p
			mi.scale = Vector3.ONE * lerpf(0.16, 0.05, e)
			if k >= 1.0:
				mi.visible = false

	var _bits_live := true

	func _any_bits() -> bool:
		for b: Array in bits:
			if float(b[1]) < 1.0:
				return true
		return false


const CONE_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform float k = 1.0;
uniform vec4 tint : source_color = vec4(0.38, 1.0, 0.77, 1.0);
void fragment() {
	// v: 0 = 노즐(위) → 1 = 오염(아래). 줄무늬가 노즐 쪽으로 빨려 올라가며 나선으로 꼬인다
	float v = UV.y;
	float s = fract(UV.x * 3.0 + v * 2.2 + TIME * 4.5);
	float band = smoothstep(0.0, 0.25, s) * smoothstep(0.75, 0.45, s);
	float rings = 0.5 + 0.5 * sin((v * 9.0 + TIME * 14.0));
	float ends = smoothstep(0.0, 0.18, v) * smoothstep(1.0, 0.7, v);
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 1.5);
	float a = (band * 0.55 + rings * 0.25) * ends * (0.35 + rim * 0.65) * k;
	ALBEDO = mix(tint.rgb, vec3(1.0), 0.25 + 0.4 * band) * a * 1.4;
}
"""


# ═══════════════════════════════════════════════════
#  돌파 보호막: 플레이어를 감싸는 민트 구체 (가장자리만 빛나는 fresnel + 위로 흐르는 육각 줄)
# ═══════════════════════════════════════════════════
class Shield extends Node3D:
	var mi: MeshInstance3D
	var mat: ShaderMaterial
	var life := 10.0
	var t := 0.0
	var hit := 0.0
	var broken := false

	func _ready() -> void:
		if MocoFX.on:
			if DroneFX._shield_moco == null:
				DroneFX._shield_moco = Shader.new()
				DroneFX._shield_moco.code = DroneFX.SHIELD_MOCO
			mat = ShaderMaterial.new()
			mat.shader = DroneFX._shield_moco
		else:
			if DroneFX._shield_shader == null:
				DroneFX._shield_shader = Shader.new()
				DroneFX._shield_shader.code = DroneFX.SHIELD_CODE
			mat = ShaderMaterial.new()
			mat.shader = DroneFX._shield_shader
		var sm := SphereMesh.new()
		sm.radius = 1.15
		sm.height = 2.3
		sm.radial_segments = 40
		sm.rings = 20
		mi = MeshInstance3D.new()
		mi.mesh = sm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position.y = 0.95
		add_child(mi)
		mi.scale = Vector3.ONE * 0.2
		create_tween().tween_property(mi, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	func _process(dt: float) -> void:
		t += dt
		hit = move_toward(hit, 0.0, dt * 3.0)
		var fade := clampf(life / 1.5, 0.0, 1.0)
		# 꺼지기 직전엔 깜빡여 알린다
		var blink: float = 1.0 if life > 1.5 else (1.0 if sin(t * 26.0) > 0.0 else 0.45)
		if broken:
			return
		if MocoFX.on:
			mat.set_shader_parameter("k", blink * maxf(fade, 0.3))
			return
		mat.set_shader_parameter("k", (0.75 + 0.25 * sin(t * 5.0)) * blink * maxf(fade, 0.3) + hit)
		mat.set_shader_parameter("hit", hit)

	## 맞은 방향(월드, 맞은 쪽 → 몸 중심)을 알려 주면 그쪽 면만 SOFT 로 100ms 강조한 뒤 깨진다
	func pop(from_dir := Vector3.ZERO) -> void:
		broken = true
		if from_dir != Vector3.ZERO:
			mat.set_shader_parameter("hit_dir", -from_dir.normalized())
		var tw := create_tween()
		if MocoFX.on:
			# 맞은 쪽 강조 100ms (크기 그대로) → 짧게 부풀며 사라짐
			mat.set_shader_parameter("hit", 1.0)
			tw.tween_interval(0.1)
			tw.tween_property(mi, "scale", Vector3.ONE * 1.25, 0.12).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_method(func(v: float): mat.set_shader_parameter("k", v), 1.0, 0.0, 0.12)
		else:
			tw.tween_property(mi, "scale", Vector3.ONE * 1.35, 0.12).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_method(func(v: float): mat.set_shader_parameter("k", v), 2.5, 0.0, 0.18)
		tw.tween_callback(queue_free)


const SHIELD_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
uniform float k = 1.0;
uniform float hit = 0.0;
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.4);
	// 육각 느낌의 사선 격자가 위로 흐른다
	vec2 g = vec2(UV.x * 28.0, UV.y * 16.0 - TIME * 1.2);
	g.x += floor(g.y) * 0.5;
	vec2 f = abs(fract(g) - 0.5);
	float cell = smoothstep(0.42, 0.5, max(f.x, f.y));
	float scan = smoothstep(0.96, 1.0, sin(UV.y * 40.0 - TIME * 6.0) * 0.5 + 0.5);
	vec3 mint = vec3(0.38, 1.0, 0.77);
	float a = (rim * 0.85 + cell * 0.18 * (0.3 + rim) + scan * 0.12 + hit * 0.6) * k;
	ALBEDO = mix(mint, vec3(1.0), rim * 0.4 + hit * 0.6) * a;
}
"""


## mo.co 무드 보호막 (MocoFX.on): 매우 옅은 면(blend_mix, alpha 0.04~0.10) + 테두리(0.35~0.55) + 큰 육각 셀 테두리선.
## 육각 선은 가장자리 쪽에서만 진하고 앞쪽 넓은 면은 비워 실루엣·무기가 읽히게 한다. hit = 맞은 방향 면만 SOFT 강조.
const SHIELD_MOCO := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;
uniform float k = 1.0;
uniform float hit = 0.0;
uniform vec3 hit_dir = vec3(0.0, 0.0, 1.0);
uniform vec4 support : source_color = vec4(0.208, 0.933, 0.843, 1.0);   // #35EED7
uniform vec4 soft : source_color = vec4(0.749, 1.0, 0.941, 1.0);        // #BFFFF0
varying vec3 wn;
void vertex() {
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
float hex_edge(vec2 p) {
	const vec2 s = vec2(1.0, 1.7320508);
	vec4 hc = floor(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
	vec4 h = vec4(p - hc.xy * s, p - (hc.zw + 0.5) * s);
	vec2 q = dot(h.xy, h.xy) < dot(h.zw, h.zw) ? h.xy : h.zw;
	q = abs(q);
	return max(dot(q, s * 0.5), q.x);     // 0 가운데 → 0.5 테두리
}
void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - ndv, 2.2);
	// 큰 육각: 구 둘레 약 6칸 (화면에 5~8개)
	float e = smoothstep(0.43, 0.48, hex_edge(vec2(UV.x * 6.0, UV.y * 3.4)));
	float edge_w = mix(0.08, 1.0, smoothstep(0.15, 0.75, 1.0 - ndv));   // 앞쪽 넓은 면에선 선도 거의 안 보이게
	float side = clamp(dot(normalize(wn), normalize(hit_dir)), 0.0, 1.0);
	float hk = hit * smoothstep(0.2, 0.8, side);
	float a = 0.06 + rim * 0.45 + e * 0.3 * edge_w + hk * 0.5;
	ALBEDO = mix(support.rgb, soft.rgb, clamp(rim * 0.35 + hk, 0.0, 1.0));
	ALPHA = clamp(a, 0.0, 0.9) * k;
}
"""


# ═══════════════════════════════════════════════════
#  연결 빔: 드론 노즐 → 플레이어 (보호막 걸기 · 회수 직전)
# ═══════════════════════════════════════════════════
static func tether(from: Node3D, to: Node3D, dur: float, c := MINT) -> void:
	if not is_instance_valid(FX.root):
		return
	if MocoFX.on:
		var lk := Link.new()
		lk.from = from
		lk.to = to
		lk.life = dur
		FX.root.add_child(lk)
		return
	if _beam_mesh == null:
		_beam_mesh = CylinderMesh.new()
		_beam_mesh.top_radius = 0.5
		_beam_mesh.bottom_radius = 0.5
		_beam_mesh.height = 1.0
		_beam_mesh.radial_segments = 8
		_beam_mesh.rings = 1
	var mi := Pal.flat_mesh(_beam_mesh, c, 2.2)
	mi.top_level = true
	FX.root.add_child(mi)
	var tw := mi.create_tween()
	tw.tween_method(func(k: float):
		if not (is_instance_valid(from) and is_instance_valid(to) and is_instance_valid(mi)):
			return
		var a := from.global_position
		var b := to.global_position + Vector3(0, 0.95, 0)
		var d := b - a
		var l := d.length()
		if l < 0.05:
			return
		var y := d / l
		var x := y.cross(Vector3.UP)
		x = (x if x.length() > 0.01 else Vector3.RIGHT).normalized()
		var w := 0.09 * (1.0 - k) + 0.02
		mi.global_transform = Transform3D(Basis(x * w, y * l, x.cross(y).normalized() * w), a + d * 0.5), 0.0, 1.0, dur)
	tw.tween_callback(mi.queue_free)


## 바닥에 깔리는 큰 소용돌이 원판 (볼텍스 끌어당김). 반지름 r, 지속 dur. 회전하는 고리 세 겹.
static func vortex_disc(center: Node3D, r: float, dur: float) -> void:
	if not is_instance_valid(FX.root):
		return
	if MocoFX.on:
		var v := Vortex.new()
		v.center = center
		v.r = r
		v.life = dur
		FX.root.add_child(v)
		return
	for i in 3:
		var mi := Pal.flat_mesh(FX._ring_mesh(), MINT if i != 1 else MINT_SOFT, 1.6)
		mi.top_level = true
		FX.root.add_child(mi)
		var r0 := r * (1.0 - i * 0.25)
		var tw := mi.create_tween()
		tw.tween_method(func(k: float):
			if not (is_instance_valid(center) and is_instance_valid(mi)):
				return
			var p := center.global_position
			p.y = Main.gy(p) + 0.06 + i * 0.03
			var rr := r0 * (1.0 - k * 0.75)
			mi.global_transform = Transform3D(Basis(Vector3.UP, k * TAU * (2.0 + i) * (1 if i % 2 == 0 else -1)).scaled(Vector3(rr, 0.04, rr)), p), 0.0, 1.0, dur)
		tw.tween_callback(mi.queue_free)


# ═══════════════════════════════════════════════════
#  mo.co 무드 연결선: 노즐 → 플레이어 몸체. 가는 점선(선분 0.18m · 빈칸 0.12m)이 플레이어 쪽으로 흐르고
#  밝은 마름모 펄스 3개가 지나간다. 양 끝은 매 프레임 갱신, 수명이 끝나면 지운다 (보호막 350ms · 회수 250ms).
# ═══════════════════════════════════════════════════
class Link extends MeshInstance3D:
	const WIDTH := 0.06        # 문서 범위 0.03~0.06 의 상한 (BRAWL 망원 카메라에서 0.045 는 1~2px)
	const DASH := 0.18
	const GAP := 0.12
	var from: Node3D
	var to: Node3D
	var life := 0.35
	var age := 0.0
	var _im := ImmediateMesh.new()

	func _ready() -> void:
		top_level = true
		mesh = _im
		material_override = MocoFX.vc_material()
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		extra_cull_margin = 16384.0

	func _process(dt: float) -> void:
		age += dt
		_im.clear_surfaces()
		if age >= life or not (is_instance_valid(from) and is_instance_valid(to)):
			queue_free()
			return
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		global_transform = Transform3D.IDENTITY
		var a := from.global_position
		var b := to.global_position + Vector3(0, 0.95, 0)
		var d := b - a
		var l := d.length()
		if l < 0.05:
			return
		var y := d / l
		var side := y.cross((cam.global_position - (a + b) * 0.5).normalized())
		side = (side if side.length() > 0.01 else Vector3.RIGHT).normalized()
		var k := age / life
		var fade := 1.0 - smoothstep(0.7, 1.0, k)
		var reach := l * minf(k / 0.25, 1.0)        # 노즐에서 뻗어 나간다
		var col := MocoFX.lin(MocoFX.SUPPORT)
		col.a = 0.9 * fade
		_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		var period := DASH + GAP
		var s0 := -period + fmod(age * 3.0, period)     # 점선이 플레이어 쪽으로 흐른다
		while s0 < reach:
			var p0 := maxf(s0, 0.0)
			var p1 := minf(s0 + DASH, reach)
			if p1 > p0:
				_quad(a + y * p0, a + y * p1, side * WIDTH * 0.5, col)
			s0 += period
		# 마름모 펄스 (SOFT): 노즐 → 플레이어
		var soft := MocoFX.lin(MocoFX.SOFT)
		soft.a = fade
		for i in 3:
			var u := fmod(k * 1.6 + i * 0.33, 1.0)
			if u * l > reach:
				continue
			var m := a + y * (u * l)
			var sz := 0.09
			_tri(m + y * sz * 1.4, m + side * sz * 0.6, m - y * sz, soft)
			_tri(m + y * sz * 1.4, m - y * sz, m - side * sz * 0.6, soft)
		_im.surface_end()

	func _quad(p0: Vector3, p1: Vector3, h: Vector3, c: Color) -> void:
		_tri(p0 - h, p0 + h, p1 + h, c)
		_tri(p0 - h, p1 + h, p1 - h, c)

	func _tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
		for v: Vector3 in [a, b, c]:
			_im.surface_set_color(col)
			_im.surface_add_vertex(v)


# ═══════════════════════════════════════════════════
#  mo.co 무드 볼텍스: 바닥(Main.gy + 0.05)에 실제 끌어당김 범위(반지름 r)의 가는 끊어진 호 3개가 돌고,
#  안쪽에 작은 삼각 파편 7개가 플레이어 중심으로 빨려 든다. 16m 전체를 칠하지 않는다. 판정은 PartnerDrone 그대로.
# ═══════════════════════════════════════════════════
class Vortex extends MeshInstance3D:
	var center: Node3D
	var r := 8.0
	var life := 0.75
	var age := 0.0
	var _im := ImmediateMesh.new()
	var _bits: Array = []

	func _ready() -> void:
		top_level = true
		mesh = _im
		material_override = MocoFX.vc_material()
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		extra_cull_margin = 16384.0
		for i in 7:
			_bits.append([randf() * TAU, randf(), randf_range(0.7, 1.0), i % 2 == 0])

	func _process(dt: float) -> void:
		age += dt
		_im.clear_surfaces()
		if age >= life + 0.12 or not is_instance_valid(center):
			queue_free()
			return
		global_transform = Transform3D.IDENTITY
		var c := center.global_position
		var k := clampf(age / life, 0.0, 1.0)
		var fade := (1.0 - smoothstep(life, life + 0.12, age)) * minf(age / 0.08, 1.0)
		var sup := MocoFX.lin(MocoFX.SUPPORT)
		var soft := MocoFX.lin(MocoFX.SOFT)
		_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		# 바깥 범위: 끊어진 호 3개 (각 약 95°), 두께 = 반지름의 0.02
		var th := r * 0.02
		var rot := age * 1.6
		sup.a = 0.85 * fade
		for i in 3:
			_arc(c, r, th, rot + i * TAU / 3.0, deg_to_rad(95.0), sup)
		# 안쪽 고리 (가늘게, 반대로 돈다): 끌어당김 진행에 따라 조여든다
		var sa := soft
		sa.a = 0.6 * fade
		var ri := r * lerpf(0.55, 0.3, k)
		for i in 3:
			_arc(c, ri, th * 0.8, -rot * 1.4 + i * TAU / 3.0 + 0.5, deg_to_rad(70.0), sa)
		# 흡입 파편: 바깥 → 중심으로 (나선), 중심에 가까울수록 작아짐
		for bt: Array in _bits:
			var u := fmod(float(bt[1]) + age * 1.7, 1.0)
			var rr := r * 0.62 * (1.0 - u) * float(bt[2]) + 0.4
			var a := float(bt[0]) + u * 1.4
			var p := c + Vector3(cos(a) * rr, 0, sin(a) * rr)
			p.y = Main.gy(p) + 0.07
			var to_c := (Vector3(c.x, p.y, c.z) - p).normalized()
			var sd := to_c.cross(Vector3.UP)
			var sz := lerpf(0.32, 0.12, u)
			var col: Color = sup if bt[3] else soft
			col.a = fade * (1.0 - u * u)
			_tri(p + to_c * sz * 1.5, p + sd * sz * 0.5, p - sd * sz * 0.5, col)
		_im.surface_end()

	func _arc(c: Vector3, rad: float, w: float, a0: float, span: float, col: Color) -> void:
		var seg := 14
		for i in seg:
			var t0 := a0 + span * i / seg
			var t1 := a0 + span * (i + 1) / seg
			var e0 := 1.0 - absf(float(i) / seg * 2.0 - 1.0)       # 호 끝으로 갈수록 가늘게
			var e1 := 1.0 - absf(float(i + 1) / seg * 2.0 - 1.0)
			var d0 := Vector3(cos(t0), 0, sin(t0))
			var d1 := Vector3(cos(t1), 0, sin(t1))
			var p0o := _g(c + d0 * (rad + w * e0))
			var p0i := _g(c + d0 * (rad - w * e0))
			var p1o := _g(c + d1 * (rad + w * e1))
			var p1i := _g(c + d1 * (rad - w * e1))
			_tri(p0i, p0o, p1o, col)
			_tri(p0i, p1o, p1i, col)

	## 바닥 높이 + 0.05 (경사 지형에 묻히거나 뜨지 않게 꼭짓점마다)
	func _g(p: Vector3) -> Vector3:
		return Vector3(p.x, Main.gy(p) + 0.05, p.z)

	func _tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
		for v: Vector3 in [a, b, c]:
			_im.surface_set_color(col)
			_im.surface_add_vertex(v)
