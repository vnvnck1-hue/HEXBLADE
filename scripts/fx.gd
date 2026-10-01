class_name FX
extends RefCounted
## 연출 전용: 원호 참격, 폭발 원형파, 연기 구체, 불꽃 파티클, 섬광, 잔상.
## 게임 판정과 무관하며 모두 스스로 수명을 끝낸다.

static var root: Node3D
static var _ring_mat: ShaderMaterial
static var _slash_mat: ShaderMaterial
static var _shadow_mat: ShaderMaterial
static var _ghost_mat: StandardMaterial3D
static var _slash_mesh: ArrayMesh
static var _sphere: SphereMesh
static var _quad: QuadMesh
static var _spark_mesh: BoxMesh
static var _spark_mat: StandardMaterial3D

const GHOST := Color(0.45, 0.55, 1.0, 0.28)

const BILLBOARD := """
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
"""


static func setup(parent: Node3D) -> void:
	root = parent
	_sphere = SphereMesh.new()
	_sphere.radius = 0.5
	_sphere.height = 1.0
	_sphere.radial_segments = 16
	_sphere.rings = 8
	_quad = QuadMesh.new()
	_spark_mesh = BoxMesh.new()
	_spark_mesh.size = Vector3(0.09, 0.09, 0.09)
	_spark_mat = StandardMaterial3D.new()
	_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_mat.vertex_color_use_as_albedo = true
	_spark_mesh.material = _spark_mat

	# 폭발 원형파: 카메라를 향한 판. 중심을 바닥 근처에 두면 아래 절반이 바닥에 가려져
	# 참고 GIF 처럼 밑면이 평평한 반원 띠가 된다.
	var rs := Shader.new()
	rs.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
instance uniform float progress = 0.0;
instance uniform vec4 c_outer : source_color = vec4(1.0, 0.55, 0.15, 1.0);
instance uniform vec4 c_mid : source_color = vec4(0.9, 0.35, 0.1, 1.0);
instance uniform vec4 c_inner : source_color = vec4(1.0, 0.9, 0.1, 1.0);
void vertex() {
%s
}
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float t = clamp(progress, 0.0, 1.0);
	float R = 0.3 + 0.7 * (1.0 - pow(1.0 - t, 3.0));
	float thick = mix(0.55, 0.0, pow(t, 0.8));
	float inner_edge = R - thick;
	vec3 col;
	if (r > R) discard;
	if (r > inner_edge) {
		float k = (r - inner_edge) / max(thick, 0.0001);
		col = mix(c_mid.rgb, c_outer.rgb, step(0.3, k));
		col *= 0.86 + 0.14 * step(0.5, fract(k * 3.0));
	} else {
		float core = R * mix(0.72, 0.0, smoothstep(0.0, 0.55, t));
		if (r > core) discard;
		col = c_inner.rgb;
	}
	ALBEDO = col;
}
""" % BILLBOARD
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = rs

	# 검 원호: UV.x = 호를 따라, UV.y = 안쪽(0)→바깥(1)
	var ss := Shader.new()
	ss.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
uniform float progress = 0.0;
uniform vec3 deep = vec3(0.78, 0.06, 0.1);
uniform vec3 light = vec3(1.0, 0.72, 0.55);
void fragment() {
	float u = UV.x;
	float v = UV.y;
	float head = progress * 1.45;
	float len = 0.62;
	float tail = head - len;
	if (u > head || u < tail) discard;
	float along = (u - tail) / len;
	float shape = sin(clamp(u, 0.0, 1.0) * 3.14159);
	float vmin = 1.0 - shape * mix(0.25, 0.95, along);
	if (v < vmin) discard;
	float edge = smoothstep(vmin, 1.0, v);
	ALBEDO = mix(deep, light, edge) * 1.35;
	ALPHA = clamp(along * 1.8, 0.0, 1.0) * (1.0 - smoothstep(0.7, 1.0, progress)) * 0.95;
}
"""
	_slash_mat = ShaderMaterial.new()
	_slash_mat.shader = ss
	_slash_mesh = _build_arc_mesh(0.45, 2.7, deg_to_rad(150.0), 28)

	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, shadows_disabled, depth_draw_never;
uniform float strength = 0.55;
uniform vec4 tint : source_color = vec4(0.03, 0.02, 0.09, 1.0);
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	ALBEDO = tint.rgb;
	ALPHA = (1.0 - smoothstep(0.15, 1.0, r)) * strength;
}
"""
	_shadow_mat = ShaderMaterial.new()
	_shadow_mat.shader = sh

	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(0.45, 0.55, 1.0, 0.28)


static func _build_arc_mesh(r_in: float, r_out: float, span: float, seg: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in seg:
		var u0 := float(i) / seg
		var u1 := float(i + 1) / seg
		# u=0 이 오른쪽(+X), u=1 이 왼쪽. 정면은 -Z.
		var a0: float = -span * 0.5 + span * u0
		var a1: float = -span * 0.5 + span * u1
		# a<0 → +X 쪽, a>0 → -X 쪽
		var d0 := Vector3(-sin(a0), 0, -cos(a0))
		var d1 := Vector3(-sin(a1), 0, -cos(a1))
		var p0i := d0 * r_in
		var p0o := d0 * r_out
		var p1i := d1 * r_in
		var p1o := d1 * r_out
		st.set_uv(Vector2(u0, 0)); st.add_vertex(p0i)
		st.set_uv(Vector2(u0, 1)); st.add_vertex(p0o)
		st.set_uv(Vector2(u1, 1)); st.add_vertex(p1o)
		st.set_uv(Vector2(u0, 0)); st.add_vertex(p0i)
		st.set_uv(Vector2(u1, 1)); st.add_vertex(p1o)
		st.set_uv(Vector2(u1, 0)); st.add_vertex(p1i)
	return st.commit()


## flow > 0: 흐르는 씬(추격 보스전)에서 공간을 따라 흘러간다 (WorldFlow.AIR / GROUND). 흐르지 않는 씬에서는 무시된다
static func _add(n: Node3D, pos: Vector3, flow := 0.0) -> void:
	(WorldFlow.holder(flow) if flow > 0.0 else root).add_child(n)
	n.global_position = pos


# ── 기본 요소 ───────────────────────────────────────────

static func blob_shadow(parent: Node3D, size: float, strength := 0.55) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	var mat := _shadow_mat.duplicate() as ShaderMaterial
	mat.set_shader_parameter("strength", strength)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.position = Vector3(0, 0.015, 0)
	return mi


static func ring(pos: Vector3, size: float, colors: Array[Color], duration := 0.42, flow := WorldFlow.AIR) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	mi.material_override = _ring_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("c_outer", colors[0])
	mi.set_instance_shader_parameter("c_mid", colors[1])
	mi.set_instance_shader_parameter("c_inner", colors[2])
	mi.set_instance_shader_parameter("progress", 0.0)
	mi.scale = Vector3.ONE * size
	_add(mi, pos, flow)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): mi.set_instance_shader_parameter("progress", v), 0.0, 1.0, duration)
	tw.tween_callback(mi.queue_free)


static func puffs(pos: Vector3, count: int, colors: Array[Color], spread: float, size: float, life := 0.7) -> void:
	for i in count:
		var c: Color = colors[randi() % 2]
		var mi := Pal.flat_mesh(_sphere, c)
		var off := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).limit_length(1.0) * spread
		off.y = randf_range(0.1, 0.9) * size
		_add(mi, pos + off, WorldFlow.AIR)
		mi.scale = Vector3.ONE * 0.01
		var s := size * randf_range(0.55, 1.15)
		var l := life * randf_range(0.7, 1.25)
		var drift := off.normalized() * spread * randf_range(0.4, 1.2) + Vector3(0, randf_range(0.1, 0.6), 0)
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3.ONE * s, 0.07 + randf() * 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(mi, "position", mi.position + drift, l).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		var dark: Color = colors[2 + randi() % 2]
		tw.parallel().tween_method(func(v: Color): mi.set_instance_shader_parameter("tint", v), c, dark, l)
		tw.parallel().tween_property(mi, "scale", Vector3.ONE * 0.01, l * 0.45).set_delay(l * 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.queue_free)


static func sparks(pos: Vector3, count: int, colors: Array[Color], speed := 6.0, life := 0.45, gravity := -14.0, box := 0.09) -> void:
	var p := GPUParticles3D.new()
	p.amount = count
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = life
	# 흐르는 씬에서는 운반 노드와 함께 흐르도록 로컬 좌표로 시뮬레이션한다
	p.local_coords = WorldFlow.active()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, gravity, 0)
	pm.damping_min = 2.0
	pm.damping_max = 5.0
	pm.scale_min = box / 0.09 * 0.6
	pm.scale_max = box / 0.09 * 1.4
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	var curve := CurveTexture.new()
	var cv := Curve.new()
	cv.add_point(Vector2(0, 1))
	cv.add_point(Vector2(0.7, 0.8))
	cv.add_point(Vector2(1, 0))
	curve.curve = cv
	pm.scale_curve = curve
	var grad := Gradient.new()
	var offs := PackedFloat32Array()
	for i in colors.size():
		offs.append(float(i) / max(1, colors.size() - 1))
	grad.offsets = offs
	grad.colors = PackedColorArray(colors)
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_initial_ramp = gt
	p.process_material = pm
	p.draw_pass_1 = _spark_mesh
	_add(p, pos, WorldFlow.AIR)
	p.emitting = true
	p.get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)


static func flash(pos: Vector3, c: Color, size := 0.6, dur := 0.08, flow := WorldFlow.AIR) -> void:
	var mi := Pal.flat_mesh(_sphere, c, 1.6)
	_add(mi, pos, flow)
	mi.scale = Vector3.ONE * size
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 0.01, dur).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)


# ── 조합 연출 ───────────────────────────────────────────

static func muzzle(pos: Vector3, dir: Vector3) -> void:
	flash(pos, Color(0.85, 1.0, 1.0), 0.42, 0.055, 0.0)
	flash(pos + dir * 0.18, Pal.CYAN, 0.28, 0.07, 0.0)


static func bullet_hit(pos: Vector3, c: Color) -> void:
	flash(pos, Color.WHITE, 0.55, 0.07)
	sparks(pos, 6, [Color.WHITE, c], 5.0, 0.25, -6.0, 0.07)


static func enemy_explosion(pos: Vector3, k := 1.0) -> void:
	fire_explosion(pos, 0.6 * k)
	sparks(pos, int(10 * k), [Color("fff0c0"), Color("ffb040"), Color("ff5a20")], 9.0 * sqrt(k), 0.5, -12.0, 0.08)


## 스타일라이즈드 화염 폭발 (explosion_fx.gd). k = 크기 배율, 1 ≈ 반경 1.6m
static func fire_explosion(pos: Vector3, k := 1.0) -> void:
	StylizedExplosion.spawn(WorldFlow.holder(WorldFlow.AIR), pos, k, Main.gy(pos))
	# 공기가 휘는 굴절 충격파 + 불덩이 안쪽 아지랑이
	Distortion.burst(pos, StylizedExplosion.BASE_R * k * 2.4, 0.4 + 0.12 * sqrt(k), clampf(0.7 + 0.3 * k, 0.7, 1.6), 1.0)


## 추락하는 적이 뿜는 연기
static func smoke(pos: Vector3) -> void:
	var c := Color("5a2a50") if randf() < 0.5 else Color("ff5a3a")
	var mi := Pal.flat_mesh(_sphere, c)
	_add(mi, pos + Vector3(randf_range(-0.1, 0.1), 0, randf_range(-0.1, 0.1)), WorldFlow.AIR)
	mi.scale = Vector3.ONE * randf_range(0.25, 0.45)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 0.01, 0.45).set_ease(Tween.EASE_IN)
	tw.parallel().tween_method(func(v: Color): mi.set_instance_shader_parameter("tint", v), c, Color("2a1a30"), 0.3)
	tw.parallel().tween_property(mi, "position", mi.position + Vector3(0, 0.5, 0), 0.45)
	tw.tween_callback(mi.queue_free)


static func player_hurt(pos: Vector3) -> void:
	var ground := Vector3(pos.x, Main.gy(pos) + 0.25, pos.z)
	ring(ground, 4.2, Pal.RING_PINK, 0.4)
	puffs(pos, 7, Pal.PUFF_RED, 0.7, 0.8, 0.55)


static func player_death(pos: Vector3) -> void:
	ring(Vector3(pos.x, Main.gy(pos) + 0.25, pos.z), 6.0, Pal.RING_PINK, 0.6)
	puffs(pos, 14, Pal.PUFF_MAGENTA, 1.4, 1.3, 1.1)
	sparks(pos, 24, [Pal.P_LIGHT, Pal.P_BODY, Pal.CYAN], 10.0, 0.9, -16.0, 0.14)


static func victory(pos: Vector3) -> void:
	ring(Vector3(pos.x, Main.gy(pos) + 0.2, pos.z), 5.0, Pal.RING_CYAN, 0.7)
	for i in 10:
		var a := TAU * i / 10.0
		var d := Vector3(cos(a), 0, sin(a))
		var bar := BoxMesh.new()
		bar.size = Vector3(0.12, 0.12, 0.45)
		var mi := Pal.flat_mesh(bar, Color("7cf0b0"), 1.2)
		_add(mi, pos + d * 1.8 + Vector3(0, 0.9, 0))
		mi.look_at(mi.global_position + d, Vector3.UP)
		var tw := mi.create_tween()
		tw.tween_property(mi, "global_position", mi.global_position + d * 1.4, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.parallel().tween_property(mi, "scale", Vector3(0.1, 0.1, 0.1), 0.6).set_delay(0.25)
		tw.tween_callback(mi.queue_free)


static func spawn_marker(pos: Vector3, dur: float) -> void:
	var t := TorusMesh.new()
	t.inner_radius = 0.7
	t.outer_radius = 0.82
	t.rings = 24
	var mi := Pal.flat_mesh(t, Pal.E_RED, 1.2)
	mi.scale = Vector3(1.6, 0.06, 1.6)
	_add(mi, Vector3(pos.x, Main.gy(pos) + 0.03, pos.z))
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(0.7, 0.06, 0.7), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)


static func land_dust(pos: Vector3) -> void:
	sparks(Vector3(pos.x, Main.gy(pos) + 0.1, pos.z), 10, [Color("8a8ac8"), Color("4a4a80")], 4.0, 0.35, -4.0, 0.1)


## 검 원호. style: 0 가로 베기 · 1 역베기(좌우 반전) · 2 내려찍기(세로 호) · 3 회전 베기(호 3개 연속)
static func slash(owner: Node3D, yaw: float, style := 0) -> void:
	var up := Basis(Vector3.UP, yaw)
	var pos := owner.global_position + Vector3(0, 0.95, 0)
	match style:
		1:
			_slash_arc(pos, up * Basis.from_scale(Vector3(-1, 1, 1)), 0.05)
		2:
			# 호를 세워 위 → 아래로 긋고, 앞바닥을 내려친 충격을 더한다
			_slash_arc(pos + Vector3(0, 0.3, 0), up * Basis(Vector3.BACK, PI * 0.5) * Basis.from_scale(Vector3(0.9, 1, 1.1)), 0.06)
			var fwd := -up.z
			var hit := Vector3(pos.x, Main.gy(pos) + 0.05, pos.z) + fwd * 2.2
			shockwave(hit, Pal.BLADE, 2.2, 0.25, 0.07)
			sparks(hit + Vector3(0, 0.1, 0), 14, [Color.WHITE, Pal.BLADE, Pal.BLADE_CORE], 7.0, 0.35, -12.0, 0.08)
		3:
			for i in 3:
				_slash_arc(pos, Basis(Vector3.UP, yaw + i * TAU / 3.0) * Basis.from_scale(Vector3(1.05, 1, 1.05)), 0.045, i * 0.033)
			shockwave(Vector3(pos.x, Main.gy(pos) + 0.05, pos.z), Pal.BLADE, 3.2, 0.28, 0.06)
		_:
			_slash_arc(pos, up, 0.05)
	# 바닥의 옅은 붉은 원 (GIF 36 프레임)
	var disc := CylinderMesh.new()
	disc.top_radius = 1.9
	disc.bottom_radius = 1.9
	disc.height = 0.01
	disc.radial_segments = 32
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(0.95, 0.25, 0.22, 0.12)
	disc.material = gm
	var dm := MeshInstance3D.new()
	dm.mesh = disc
	dm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(dm, Vector3(owner.global_position.x, Main.gy(owner.global_position) + 0.02, owner.global_position.z))
	var tw2 := dm.create_tween()
	tw2.tween_property(gm, "albedo_color:a", 0.0, 0.2)
	tw2.tween_callback(dm.queue_free)


static func _slash_arc(pos: Vector3, b: Basis, swing: float, delay := 0.0) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _slash_mesh
	var mat := _slash_mat.duplicate() as ShaderMaterial
	mat.set_shader_parameter("progress", 0.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(mi, pos)
	mi.basis = b
	var tw := mi.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	# swing 초 만에 호가 완성되고, 짧게 잔광이 남았다 사라진다
	tw.tween_property(mat, "shader_parameter/progress", 0.72, swing)
	tw.tween_property(mat, "shader_parameter/progress", 1.0, 0.4).set_ease(Tween.EASE_OUT)
	tw.tween_callback(mi.queue_free)


## 검술 콤보용 짧은 초승달 섬광: 분홍·보라빛 호가 swing 초 만에 그어지고 life 초 안에 사라진다.
## 쿼터뷰에서 옆으로 누워 보이는 세로 베기도 호 모양이 읽히도록 기울여 겹쳐 쓴다.
static func crescent(pos: Vector3, b: Basis, swing := 0.035, life := 0.11) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _slash_mesh
	var mat := _slash_mat.duplicate() as ShaderMaterial
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("deep", Vector3(0.42, 0.12, 0.95))
	mat.set_shader_parameter("light", Vector3(1.0, 0.82, 0.95))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(mi, pos)
	mi.basis = b
	var tw := mi.create_tween()
	tw.tween_property(mat, "shader_parameter/progress", 0.72, swing).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(mat, "shader_parameter/progress", 1.0, life).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)


## 관통 일격의 일섬: 지나간 경로를 따라 가는 빛줄기가 번쩍였다가 가늘어지며 사라진다
static func phantom_cut(from: Vector3, to: Vector3, tint: Color) -> void:
	var d := to - from
	d.y = 0
	var length := d.length()
	if length < 0.1:
		return
	var dir := d / length
	var mid := Vector3(from.x, Main.gy(from) + 0.95, from.z) + dir * length * 0.5
	var b := Basis.looking_at(dir, Vector3.UP)
	var line := BoxMesh.new()
	line.size = Vector3(1, 1, 1)
	for L in [[Color(1.0, 0.45, 0.35), 2.2, 0.22, 0.08], [Color.WHITE, 3.2, 0.07, 0.035]]:
		var mi := Pal.flat_mesh(line, L[0], L[1])
		_add(mi, mid)
		mi.basis = b * Basis.from_scale(Vector3(L[2], L[3], length + 1.2))
		var w: float = L[2]
		var h: float = L[3]
		var tw := mi.create_tween()
		tw.tween_method(func(v: float): mi.basis = b * Basis.from_scale(Vector3(w * v, h * v, length + 1.2)), 1.6, 1.0, 0.05)
		tw.tween_interval(0.06)
		tw.tween_method(func(v: float): mi.basis = b * Basis.from_scale(Vector3(maxf(w * v, 0.001), maxf(h * v, 0.001), length + 1.2)), 1.0, 0.0, 0.22).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.queue_free)
	# 바닥에 남는 칼자국
	var scar := BoxMesh.new()
	scar.size = Vector3(0.18, 0.01, length)
	var sm := Pal.flat_mesh(scar, tint, 1.6)
	_add(sm, Vector3(mid.x, Main.gy(mid) + 0.03, mid.z))
	sm.basis = b
	var stw := sm.create_tween()
	stw.tween_method(func(v: Color): sm.set_instance_shader_parameter("tint", v), tint, Color(0.09, 0.08, 0.16), 0.8).set_ease(Tween.EASE_OUT)
	stw.tween_callback(sm.queue_free)
	var step := 1.0
	var t := 0.5
	while t < length:
		sparks(Vector3(from.x, Main.gy(from) + 0.95, from.z) + dir * t, 3, [Color.WHITE, Pal.BLADE, tint], 5.0, 0.3, -8.0, 0.06)
		t += step
	flash(Vector3(to.x, Main.gy(to) + 0.95, to.z), Color(1.0, 0.85, 0.8), 1.3, 0.1)


## 회피 잔상: 현재 로봇 파츠를 반투명하게 복제 (기본 보라, 2단 대시는 무지개빛)
static func afterimage(visual: Node3D, tint := GHOST, life := 0.0) -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var mat := _ghost_mat.duplicate() as StandardMaterial3D
	mat.albedo_color = tint
	for mi in visual.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.is_visible_in_tree() or m.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			continue
		var g := MeshInstance3D.new()
		g.mesh = m.mesh
		g.material_override = mat
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(g)
		g.global_transform = m.global_transform
	var tw := holder.create_tween()
	if life <= 0.0:
		life = 0.16 if tint == GHOST else 0.24
	tw.tween_property(mat, "albedo_color:a", 0.0, life)
	tw.tween_callback(holder.queue_free)


# ── 레이저 · 부스터 · 대시 · 파괴 ───────────────────────

static var _cyl: CylinderMesh
static var _torus: TorusMesh


static func _cylinder() -> CylinderMesh:
	if _cyl == null:
		_cyl = CylinderMesh.new()
		_cyl.top_radius = 0.5
		_cyl.bottom_radius = 0.5
		_cyl.height = 1.0
		_cyl.radial_segments = 16
		_cyl.rings = 1
	return _cyl


static func _ring_mesh() -> TorusMesh:
	if _torus == null:
		_torus = TorusMesh.new()
		_torus.inner_radius = 0.9
		_torus.outer_radius = 1.0
		_torus.rings = 40
		_torus.ring_segments = 4
	return _torus


## 바닥에 퍼지는 원형 충격파
static func shockwave(pos: Vector3, c: Color, size: float, dur := 0.35, thick := 0.08, flow := WorldFlow.AIR) -> void:
	var mi := Pal.flat_mesh(_ring_mesh(), c, 1.3)
	mi.scale = Vector3(0.2, thick, 0.2)
	_add(mi, Vector3(pos.x, Main.gy(pos) + 0.04, pos.z), flow)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(size, thick * 0.3, size), dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_method(func(v: Color): mi.set_instance_shader_parameter("tint", v), c, Pal.FLOOR, dur).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)


## 부스터 배기 구체
static func boost_puff(pos: Vector3, vel: Vector3) -> void:
	var c := Pal.JET if randf() < 0.6 else Color("ff8a3a")
	var mi := Pal.flat_mesh(_sphere, c, 1.3)
	_add(mi, pos)
	var s := randf_range(0.16, 0.28)
	mi.scale = Vector3.ONE * s
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_position", pos + vel * 0.25 + Vector3(0, -0.15, 0), 0.25)
	tw.parallel().tween_property(mi, "scale", Vector3.ONE * 0.01, 0.25).set_ease(Tween.EASE_IN)
	tw.parallel().tween_method(func(v: Color): mi.set_instance_shader_parameter("tint", v), c, Color("5a1420"), 0.25)
	tw.tween_callback(mi.queue_free)


## 충전 레이저 빔. k = 충전량(0~1), w = 빔 폭
static func laser(origin: Vector3, dir: Vector3, length: float, w: float, k: float) -> void:
	_beam(origin, dir, length, w, k, [[Pal.CYAN, 1.8, 1.0], [Color("b0fbff"), 2.4, 0.62], [Color.WHITE, 3.0, 0.32]],
		Pal.RING_CYAN, [Pal.CYAN, Color("5a8cff"), Color.WHITE], [Color.WHITE, Pal.CYAN, Color("8a70ff")], Pal.CYAN, Color(0.6, 1.0, 1.0))
	# 빔 몸통이 가늘어질 무렵 잔상이 이어받아 일렁이다 부서진다
	BeamAfterimage.spawn(origin, dir, length, clampf(w * 0.14, 0.1, 0.19), Color("1ff0ff"), 0.16 + 0.06 * k)


## 적 차지 레이저 빔 (붉은색)
static func enemy_laser(origin: Vector3, dir: Vector3, length: float, w: float) -> void:
	_beam(origin, dir, length, w, 0.6, [[Pal.E_RED, 1.9, 1.0], [Color("ff9a8a"), 2.4, 0.6], [Color.WHITE, 3.0, 0.3]],
		Pal.RING_PINK, [Pal.E_RED, Color("ff7a30"), Color.WHITE], [Color.WHITE, Pal.E_RED, Color("ffae10")], Pal.E_RED, Color(1.0, 0.55, 0.5))


static func _beam(origin: Vector3, dir: Vector3, length: float, w: float, k: float, layers: Array,
		ring_a: Array[Color], ring_b: Array[Color], spark_c: Array[Color], main_c: Color, scorch_c: Color) -> void:
	var holder := Node3D.new()
	_add(holder, origin)
	holder.look_at(origin + dir, Vector3.UP)
	for L in layers:
		var mi := Pal.flat_mesh(_cylinder(), L[0], L[1])
		mi.rotation_degrees.x = -90.0
		mi.position = Vector3(0, 0, -length * 0.5)
		var r: float = w * L[2]
		mi.scale = Vector3(r * 1.7, length, r * 1.7)
		holder.add_child(mi)
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3(r, length, r), 0.06).set_ease(Tween.EASE_OUT)
		for i in 2:
			tw.tween_property(mi, "scale", Vector3(r * 0.8, length, r * 0.8), 0.025)
			tw.tween_property(mi, "scale", Vector3(r * 1.05, length, r * 1.05), 0.025)
		tw.tween_property(mi, "scale", Vector3(0.001, length, 0.001), 0.14 + 0.06 * k).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	var htw := holder.create_tween()
	htw.tween_interval(0.6)
	htw.tween_callback(holder.queue_free)
	# 총구·끝점 폭발
	var end := origin + dir * length
	ring(Vector3(origin.x, Main.gy(origin) + 0.3, origin.z), 2.4 + 2.0 * k, ring_a, 0.35, 0.0)
	flash(origin, Color.WHITE, 1.2 + k, 0.12, 0.0)
	ring(Vector3(end.x, Main.gy(end) + 0.3, end.z), 2.0 + 2.5 * k, ring_b, 0.4)
	sparks(end, 16 + int(16 * k), spark_c, 10.0, 0.5, -10.0, 0.1)
	shockwave(origin, main_c, 2.5 + 2.0 * k, 0.35, 0.08, 0.0)
	# 빔을 따라 튀는 불꽃
	var step := 1.6
	var d := step
	while d < length:
		sparks(origin + dir * d, 4, [Color.WHITE, main_c], 5.0 + 4.0 * k, 0.35, -6.0, 0.07)
		d += step
	# 바닥에 남는 그을린 궤적
	var scorch := BoxMesh.new()
	scorch.size = Vector3(w * 0.7, 0.01, length)
	var sm := Pal.flat_mesh(scorch, main_c, 1.2)
	_add(sm, Vector3(origin.x, Main.gy(origin) + 0.025, origin.z) + Vector3(dir.x, 0, dir.z) * length * 0.5, WorldFlow.GROUND)
	sm.look_at(sm.global_position + Vector3(dir.x, 0, dir.z), Vector3.UP)
	var stw := sm.create_tween()
	stw.tween_method(func(v: Color): sm.set_instance_shader_parameter("tint", v), scorch_c, Color(0.09, 0.08, 0.16), 1.2).set_ease(Tween.EASE_OUT)
	stw.parallel().tween_property(sm, "scale", Vector3(0.3, 1, 1), 1.2)
	stw.tween_callback(sm.queue_free)


## 충전 부족 시 불발
static func fizzle(pos: Vector3) -> void:
	sparks(pos, 8, [Pal.CYAN, Color("5040a0")], 3.0, 0.3, -4.0, 0.06)
	flash(pos, Pal.CYAN, 0.4, 0.08)


## 로봇이 부서지며 파츠가 흩어짐
static func shatter(visual: Node3D, push: Vector3) -> void:
	for n in visual.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if not m.is_visible_in_tree():
			continue
		var g := MeshInstance3D.new()
		g.mesh = m.mesh
		g.material_override = m.material_override
		root.add_child(g)
		g.global_transform = m.global_transform
		var v := push * randf_range(2.0, 5.0) + Vector3(randf_range(-4, 4), randf_range(4, 9), randf_range(-4, 4))
		var spin := Vector3(randf_range(-15, 15), randf_range(-15, 15), randf_range(-15, 15))
		var start := g.global_position
		var dur := randf_range(0.7, 1.1)
		var tw := g.create_tween()
		tw.tween_method(func(tt: float):
			var p := start + v * tt + Vector3(0, -16.0, 0) * tt * tt * 0.5
			p.y = maxf(p.y, 0.08)
			g.global_position = p
			g.rotation = spin * tt, 0.0, dur, dur)
		tw.tween_property(g, "scale", Vector3.ONE * 0.01, 0.5).set_delay(0.6)
		tw.tween_callback(g.queue_free)


## 드릴 회피 소용돌이: 진행 축에 수직인 링이 퍼지며 사라짐
static func vortex(pos: Vector3, axis_basis: Basis, c: Color) -> void:
	var mi := Pal.flat_mesh(_ring_mesh(), c, 1.5)
	_add(mi, pos)
	mi.basis = axis_basis * Basis.from_scale(Vector3(0.5, 0.06, 0.5))
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): mi.basis = axis_basis * Basis.from_scale(Vector3(v, 0.06, v)), 0.5, 1.3, 0.2).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(v: Color): mi.set_instance_shader_parameter("tint", v), c, Color(0.2, 0.15, 0.45), 0.2)
	tw.tween_callback(mi.queue_free)
