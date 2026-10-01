class_name AbyssFX
extends RefCounted
## 심연 성소 전용 연출 (판정과 무관, 모두 스스로 수명을 끝낸다).
##  - 체액 얼룩: 바닥에 투영되는 진홍·흑적 데칼 (젖은 광택). 적이 맞고 죽을 때 남고, 오래된 것부터 사라진다
##  - 체액 분사 · 파열(갑각 참회자의 폭발) · 순간 조명(어두운 전장에 폭발 빛을 실제 광원으로 비춘다)
##  - 초승달 탄 메시 · 레이저 빔/예고선 · 소환 문양

const ICHOR := Color(0.42, 0.015, 0.04)
const ICHOR_HOT := Color(1.0, 0.1, 0.16)
const ABYSS := Color(1.0, 0.07, 0.13)
const MAX_DECALS := 150

static var _splat_tex: Array[ImageTexture] = []
static var _splat_orm: ImageTexture
static var _decals: Array = []
static var _crescent: ArrayMesh
static var _crescent_mat: ShaderMaterial
static var _beam_mat: ShaderMaterial
static var _sigil_mat: ShaderMaterial
static var _warn_mat: ShaderMaterial
static var _box: BoxMesh
static var _quad: QuadMesh
static var _sphere: SphereMesh


static func setup() -> void:
	_decals.clear()
	if _splat_tex.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 913
		for i in 6:
			_splat_tex.append(_make_splat(rng, 64))
		var orm := Image.create(4, 4, false, Image.FORMAT_RGB8)
		orm.fill(Color(1.0, 0.16, 0.0))
		_splat_orm = ImageTexture.create_from_image(orm)
	if _crescent == null:
		_crescent = _build_crescent()
		var sh := Shader.new()
		sh.code = CRESCENT_SHADER
		_crescent_mat = ShaderMaterial.new()
		_crescent_mat.shader = sh
		var bs := Shader.new()
		bs.code = BEAM_SHADER
		_beam_mat = ShaderMaterial.new()
		_beam_mat.shader = bs
		var ss := Shader.new()
		ss.code = SIGIL_SHADER
		_sigil_mat = ShaderMaterial.new()
		_sigil_mat.shader = ss
		var ws := Shader.new()
		ws.code = WARN_SHADER
		_warn_mat = ShaderMaterial.new()
		_warn_mat.shader = ws
		_box = BoxMesh.new()
		_box.size = Vector3.ONE
		_quad = QuadMesh.new()
		_quad.orientation = PlaneMesh.FACE_Y
		_sphere = SphereMesh.new()
		_sphere.radius = 0.5
		_sphere.height = 1.0
		_sphere.radial_segments = 10
		_sphere.rings = 5


## 흩뿌린 얼룩 한 장: 큰 덩어리 몇 개 + 바깥으로 튄 방울 + 가장자리 번짐
static func _make_splat(rng: RandomNumberGenerator, sz: int) -> ImageTexture:
	var blobs: Array = []
	for i in rng.randi_range(3, 5):
		blobs.append([Vector2(rng.randf_range(0.35, 0.65), rng.randf_range(0.35, 0.65)) * sz, rng.randf_range(0.1, 0.2) * sz])
	for i in rng.randi_range(8, 14):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.22, 0.46) * sz
		blobs.append([Vector2(0.5, 0.5) * sz + Vector2(cos(a), sin(a)) * d, rng.randf_range(0.015, 0.05) * sz])
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	for y in sz:
		for x in sz:
			var p := Vector2(x + 0.5, y + 0.5)
			var v := 0.0
			for b in blobs:
				var r: float = b[1]
				var dd := p.distance_to(b[0]) / r
				v += maxf(0.0, 1.0 - dd * dd) * 1.4
			var a2 := clampf((v - 0.35) * 3.0, 0.0, 1.0)
			# 가운데는 짙고 가장자리는 조금 밝은 진홍
			var c := Color(0.55, 0.03, 0.06).lerp(Color(0.22, 0.0, 0.02), clampf(v - 0.6, 0.0, 1.0))
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a2))
	return ImageTexture.create_from_image(img)


# ── 체액 얼룩 ───────────────────────────────────────────

## 바닥 얼룩. size = 지름(m). 판이 가라앉으면 투영 범위를 벗어나 자연히 보이지 않는다.
static func splat(pos: Vector3, size: float, glow := 0.0) -> void:
	if FX.root == null or _splat_tex.is_empty():
		return
	var d := Decal.new()
	d.texture_albedo = _splat_tex[randi() % _splat_tex.size()]
	# 젖은 광택은 ORM 대신 얼룩 색으로만 표현한다 (ORM·발광 텍스처는 사각형 테두리가 드러난다)
	d.size = Vector3(size, 1.6, size)
	d.albedo_mix = 1.0
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	d.normal_fade = 0.4
	d.cull_mask = 2              # 석판(2번 층)에만 투영: 지나가는 기체 위에는 묻지 않는다
	FX.root.add_child(d)
	d.global_position = Vector3(pos.x, 0.2, pos.z)
	d.rotation.y = randf() * TAU
	d.modulate = Color(1, 1, 1, 0.0)
	var tw := d.create_tween()
	tw.tween_property(d, "modulate:a", 1.0, 0.08)
	_decals.append(d)
	while _decals.size() > MAX_DECALS:
		var old = _decals.pop_front()
		if is_instance_valid(old):
			var o := old as Decal
			var ft := o.create_tween()
			ft.tween_property(o, "modulate:a", 0.0, 1.5)
			ft.tween_callback(o.queue_free)


# ── 체액 분사 · 파열 ────────────────────────────────────

## 피격·사망 체액 분사: dir 쪽으로 튀고 바닥에 얼룩을 남긴다
static func ichor_burst(pos: Vector3, dir: Vector3, k := 1.0) -> void:
	var d := Vector3(dir.x, 0, dir.z)
	d = d.normalized() if d.length() > 0.01 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	FX.sparks(pos, int(10 * k) + 4, [Color(1.0, 0.3, 0.32), ICHOR_HOT, ICHOR], 7.0 * sqrt(k), 0.5, -16.0, 0.1 * sqrt(k))
	for i in int(2 + 3 * k):
		var p := pos + d * randf_range(0.3, 1.8) * k + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6)) * k
		splat(p, randf_range(0.7, 1.6) * sqrt(k), 0.6)
	splat(pos, 1.2 * k + 0.6, 1.0)


## 파열: 크게 부풀었던 살덩이가 터진다 (주변을 해치는 판정은 호출한 쪽이 처리)
static func rupture(pos: Vector3, r: float) -> void:
	var g := Vector3(pos.x, 0.05, pos.z)
	FX.flash(pos, Color(1.0, 0.85, 0.8), r * 0.9, 0.1)
	FX.flash(pos, ICHOR_HOT, r * 1.6, 0.18)
	FX.shockwave(g + Vector3(0, 0.1, 0), ICHOR_HOT, r * 2.0, 0.35, 0.12)
	FX.shockwave(g + Vector3(0, 0.1, 0), Color(1.0, 0.6, 0.55), r * 1.3, 0.22, 0.05)
	FX.ring(g + Vector3(0, 0.3, 0), r * 1.8, [ICHOR_HOT, Color(0.6, 0.02, 0.08), Color(1.0, 0.7, 0.65)], 0.4)
	FX.sparks(pos, 40, [Color.WHITE, Color(1.0, 0.35, 0.35), ICHOR_HOT, ICHOR], 13.0, 0.75, -18.0, 0.14)
	FX.puffs(pos, 9, [Color(0.55, 0.03, 0.08), Color(0.8, 0.06, 0.12), Color(0.12, 0.01, 0.03), Color(0.2, 0.02, 0.05)], r * 0.5, r * 0.7, 0.9)
	Distortion.burst(pos, r * 2.4, 0.45, 1.3, 1.0)
	for i in 8:
		var a := TAU * i / 8.0 + randf() * 0.5
		splat(g + Vector3(cos(a), 0, sin(a)) * randf_range(0.4, r), randf_range(1.0, 2.2), 0.8)
	splat(g, r * 1.6, 1.6)
	light_flash(pos + Vector3(0, 1.0, 0), ICHOR_HOT, 9.0, r * 4.0, 0.45)


## 어두운 전장을 실제로 비추는 짧은 섬광 조명
static func light_flash(pos: Vector3, c: Color, energy: float, range_m: float, dur: float) -> void:
	if FX.root == null:
		return
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = range_m
	l.omni_attenuation = 1.6
	l.shadow_enabled = false
	FX.root.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(l.queue_free)


# ── 초승달 탄 ───────────────────────────────────────────

## 진행 방향(-Z)으로 볼록한 초승달. UV.x = 호를 따라, UV.y = 안쪽(0) → 바깥(1)
static func _build_crescent() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 14
	var span := deg_to_rad(150.0)
	for i in seg:
		var u0 := float(i) / seg
		var u1 := float(i + 1) / seg
		var a0 := -span * 0.5 + span * u0
		var a1 := -span * 0.5 + span * u1
		# 두께가 가운데에서 가장 두껍고 끝으로 가늘어진다
		var w0 := sin(u0 * PI) * 0.55 + 0.05
		var w1 := sin(u1 * PI) * 0.55 + 0.05
		var d0 := Vector3(sin(a0), 0, -cos(a0))
		var d1 := Vector3(sin(a1), 0, -cos(a1))
		var o := Vector3(0, 0, 0.5)
		var p0o := d0 * 1.0 - o
		var p0i := d0 * (1.0 - w0) - o
		var p1o := d1 * 1.0 - o
		var p1i := d1 * (1.0 - w1) - o
		st.set_uv(Vector2(u0, 0)); st.add_vertex(p0i)
		st.set_uv(Vector2(u0, 1)); st.add_vertex(p0o)
		st.set_uv(Vector2(u1, 1)); st.add_vertex(p1o)
		st.set_uv(Vector2(u0, 0)); st.add_vertex(p0i)
		st.set_uv(Vector2(u1, 1)); st.add_vertex(p1o)
		st.set_uv(Vector2(u1, 0)); st.add_vertex(p1i)
	return st.commit()


const CRESCENT_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_add, depth_draw_never;
instance uniform vec4 tint : source_color = vec4(1.0, 0.1, 0.25, 1.0);
instance uniform float energy = 3.0;
void fragment() {
	float edge = sin(UV.x * 3.14159);
	float v = UV.y;
	float core = smoothstep(0.35, 0.95, v) * edge;
	vec3 c = mix(tint.rgb, vec3(1.0, 0.92, 0.95), core * core);
	float a = smoothstep(0.0, 0.3, v) * edge;
	ALBEDO = c * energy * a;
}
"""


static func crescent_mesh(c: Color, size: float, energy := 3.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _crescent
	mi.material_override = _crescent_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("tint", c)
	mi.set_instance_shader_parameter("energy", energy)
	mi.scale = Vector3(size, 1.0, size)
	return mi


# ── 레이저 빔 / 예고선 ──────────────────────────────────

## 길이 방향은 -Z. mode 0 = 예고선(가늘게 깜빡이는 점선), 1 = 빔(굵고 흐르는 빛)
const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_add, depth_draw_never;
instance uniform vec4 tint : source_color = vec4(1.0, 0.08, 0.15, 1.0);
instance uniform float mode = 1.0;
instance uniform float power = 1.0;
instance uniform float len = 20.0;
void fragment() {
	float x = abs(UV.x - 0.5) * 2.0;
	float along = UV.y * len;
	vec3 c;
	float a;
	if (mode < 0.5) {
		float dash = step(0.35, fract(along * 0.6 - TIME * 6.0));
		float flick = 0.6 + 0.4 * step(0.5, fract(TIME * 18.0));
		a = (1.0 - smoothstep(0.2, 1.0, x)) * dash * flick * power;
		c = tint.rgb * 2.2;
	} else {
		float core = 1.0 - smoothstep(0.0, 0.32, x);
		float body = 1.0 - smoothstep(0.2, 1.0, x);
		float flow = 0.75 + 0.25 * sin(along * 1.7 - TIME * 40.0) * sin(along * 0.43 + TIME * 13.0);
		c = mix(tint.rgb * 3.0 * flow, vec3(1.0, 0.9, 0.92) * 3.2, core * 0.85);
		a = max(core, body * flow) * power;
	}
	ALBEDO = c * a;
}
"""


## 빔 노드: origin 에서 dir 로 length. 갱신은 set_beam() 으로 한다.
static func beam(c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.orientation = PlaneMesh.FACE_Y
	q.size = Vector2(1, 1)
	q.center_offset = Vector3(0, 0, -0.5)
	mi.mesh = q
	mi.material_override = _beam_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("tint", c)
	mi.set_instance_shader_parameter("mode", 0.0)
	mi.set_instance_shader_parameter("power", 1.0)
	FX.root.add_child(mi)
	return mi


static func set_beam(mi: MeshInstance3D, origin: Vector3, dir: Vector3, length: float, width: float, mode: float, power := 1.0) -> void:
	var d := Vector3(dir.x, 0, dir.z).normalized()
	var b := Basis.looking_at(d, Vector3.UP)
	mi.global_transform = Transform3D(b.scaled(Vector3(width, 1.0, length)), origin)
	mi.set_instance_shader_parameter("mode", mode)
	mi.set_instance_shader_parameter("power", power)
	mi.set_instance_shader_parameter("len", length)


## 빔이 훑고 간 자리의 그을음 (얼룩보다 가늘고 붉게 식는다)
static func scorch(origin: Vector3, dir: Vector3, length: float, w: float) -> void:
	var sm := Pal.flat_mesh(_box, ICHOR_HOT, 1.4)
	var d := Vector3(dir.x, 0, dir.z).normalized()
	FX.root.add_child(sm)
	sm.global_transform = Transform3D(Basis.looking_at(d, Vector3.UP).scaled(Vector3(w, 0.01, length)), Vector3(origin.x, 0.03, origin.z) + d * length * 0.5)
	var tw := sm.create_tween()
	tw.tween_method(func(v: Color): sm.set_instance_shader_parameter("tint", v), ICHOR_HOT, Color(0.08, 0.0, 0.01), 1.0)
	tw.tween_callback(sm.queue_free)


# ── 소환 문양 ───────────────────────────────────────────

const SIGIL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_add, depth_draw_never;
instance uniform float progress = 0.0;
instance uniform vec4 tint : source_color = vec4(1.0, 0.08, 0.15, 1.0);
void fragment() {
	vec2 c = UV - 0.5;
	float r = length(c) * 2.0;
	float a = atan(c.y, c.x);
	float p = clamp(progress, 0.0, 1.0);
	float ring = 1.0 - smoothstep(0.0, 0.05, abs(r - 0.92));
	float ring2 = 1.0 - smoothstep(0.0, 0.03, abs(r - 0.7));
	float spokes = step(0.82, fract(a * 6.0 / 6.2831853 + TIME * 0.4)) * step(r, 0.92) * step(0.3, r);
	float swirl = smoothstep(0.55, 0.9, sin(a * 3.0 + r * 9.0 - TIME * 6.0)) * (1.0 - smoothstep(0.0, 0.7, r));
	float i = (ring + ring2 * 0.7 + spokes * 0.5 + swirl * 0.8 * p) * smoothstep(0.0, 0.25, p);
	if (r > 1.0) discard;
	ALBEDO = tint.rgb * i * 2.4 * (1.0 - smoothstep(0.85, 1.0, p) * 0.0);
}
"""


## 바닥 소환 문양. dur 동안 빛이 차오르고 끝에 사라진다.
static func sigil(pos: Vector3, r: float, dur: float, c := ABYSS) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	mi.material_override = _sigil_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("tint", c)
	mi.set_instance_shader_parameter("progress", 0.0)
	FX.root.add_child(mi)
	mi.global_position = Vector3(pos.x, 0.04, pos.z)
	mi.scale = Vector3(r * 2.0, 1, r * 2.0)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): mi.set_instance_shader_parameter("progress", v), 0.0, 1.0, dur)
	tw.tween_property(mi, "scale", Vector3(r * 2.6, 1, r * 2.6), 0.25)
	tw.parallel().tween_method(func(v: Color): mi.set_instance_shader_parameter("tint", v), c, Color.BLACK, 0.25)
	tw.tween_callback(mi.queue_free)
	return mi


## 위로 솟는 체액 기둥 (분출구 · 보스 착지)
static func geyser(pos: Vector3, h: float, stage: Node3D) -> void:
	for i in 10:
		var k := float(i) / 10.0
		stage.call("dust", pos + Vector3(randf_range(-0.3, 0.3), 0.2 + k * 0.5, randf_range(-0.3, 0.3)), randf_range(0.6, 1.1),
			Color(1.0, randf_range(0.04, 0.14), 0.12, 0.85), true, Vector3(randf_range(-0.5, 0.5), h * randf_range(2.2, 3.6), randf_range(-0.5, 0.5)), randf_range(0.35, 0.6))
	for i in 4:
		stage.call("dust", pos + Vector3(0, 0.5 + i * 0.6, 0), 1.4, Color(0.25, 0.02, 0.05, 0.4), false, Vector3(randf_range(-0.6, 0.6), 2.4, randf_range(-0.6, 0.6)), 1.3)
	FX.sparks(pos + Vector3(0, 0.3, 0), 18, [Color(1.0, 0.6, 0.6), ICHOR_HOT, ICHOR], 9.0, 0.7, -14.0, 0.09)
	light_flash(pos + Vector3(0, 1.0, 0), ICHOR_HOT, 5.0, 6.0, 0.5)


# ── 바닥 위험 원 ────────────────────────────────────────

## 공격 예고 원: 바깥 고리가 먼저 그려지고 안쪽이 progress 만큼 차오른다. 끝 무렵 빠르게 깜빡인다.
const WARN_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_add, depth_draw_never;
instance uniform float progress = 0.0;
instance uniform vec4 tint : source_color = vec4(1.0, 0.1, 0.16, 1.0);
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	if (r > 1.0) discard;
	float p = clamp(progress, 0.0, 1.0);
	float edge = 1.0 - smoothstep(0.0, 0.06, 1.0 - r);
	float fill = step(r, p);
	float front = 1.0 - smoothstep(0.0, 0.05, abs(r - p));
	float hatch = step(0.5, fract((UV.x + UV.y) * 9.0 - TIME * 2.0)) * 0.25;
	float blink = mix(1.0, 0.4 + 0.6 * step(0.5, fract(TIME * 16.0)), step(0.75, p));
	float i = (0.08 + edge * (0.9 + p) + fill * (0.18 + hatch) + front * 0.9) * blink;
	ALBEDO = tint.rgb * i * 1.6;
}
"""


static func warn_disc(pos: Vector3, r: float, c := ICHOR_HOT) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	mi.material_override = _warn_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("tint", c)
	mi.set_instance_shader_parameter("progress", 0.0)
	FX.root.add_child(mi)
	mi.global_position = Vector3(pos.x, 0.05, pos.z)
	mi.scale = Vector3(r * 2.0, 1, r * 2.0)
	return mi


static func set_warn(mi: MeshInstance3D, k: float) -> void:
	mi.set_instance_shader_parameter("progress", k)
