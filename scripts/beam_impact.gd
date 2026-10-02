extends Node3D
## 강력 레이저가 적에 닿는 지점의 피격 연출 (연출 전용, 판정 없음).
## 지속 레이저: touch() 를 매 프레임 불러 유지하고 finish() 로 끝낸다. 충전 레이저: burst() 한 번.
## 흰 심 + 청록 광채 + 쏜 쪽으로 튀어 나오는 초승달 칼날 + 물보라 줄기 + 빔에 수직인 충격파 + 십자 플레어 + 점광원.

const WHITE := Color(0.95, 1.0, 1.0)
const CYAN := Color("35e8ff")
const BLUE := Color("7a9cff")
const BIG_RADIUS := 3.3     # 이 반지름 이상인 적에서 연출이 최대 크기
const MIN_SIZE := 0.35

static var _arc: ArrayMesh
static var _add_mat: ShaderMaterial      # 초승달 칼날 (가산)
static var _glow_mat: ShaderMaterial     # 부드러운 광채 구 (가산)
static var _ball: SphereMesh
static var _streak: BoxMesh
static var _flare: BoxMesh
# 지속 레이저는 칼날·물보라를 초당 수백 개 만든다. 다 쓴 조각은 지우지 않고 숨겨 두었다가 다시 쓴다
static var _pool_blade: Array = []
static var _pool_spray: Array = []

var dir := Vector3.FORWARD
var active_t := 0.0
var dying := false
var power := 1.0
var t := 0.0
var blade_t := 0.0
var streak_t := 0.0
var ring_t := 0.0
var spark_t := 0.0
var snd_t := 0.0
var core: MeshInstance3D
var halo: MeshInstance3D
var flare_h: MeshInstance3D
var flare_v: MeshInstance3D
var light: OmniLight3D
var fans: Array[MeshInstance3D] = []   # 접점 양옆으로 크게 펼쳐지는 물보라 날개
var fan_t := 0.0
var k := 0.0            # 켜짐 정도 0~1


static func _res() -> void:
	if _arc != null:
		return
	_arc = _build_swoosh(0.55, 20)
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, shadows_disabled, depth_draw_never;
instance uniform float fade = 1.0;
instance uniform vec4 tint : source_color = vec4(0.2, 0.9, 1.0, 1.0);
void fragment() {
	float u = UV.x;                 // 0 접점 → 1 끝
	float v = abs(UV.y - 0.5) * 2.0; // 0 중심선 → 1 가장자리
	// 중심선은 흰색으로 달아오르고 가장자리는 청록, 끝으로 갈수록 옅어진다
	float core = 1.0 - smoothstep(0.0, 0.55, v);
	vec3 col = mix(tint.rgb, vec3(1.0), core * (1.0 - u * 0.6));
	float edge = 1.0 - smoothstep(0.75, 1.0, v);
	ALBEDO = col * (1.1 + 2.2 * core) * edge * (1.0 - u * 0.55) * fade;
}
"""
	_add_mat = ShaderMaterial.new()
	_add_mat.shader = sh
	var gs := Shader.new()
	gs.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, shadows_disabled, depth_draw_never;
instance uniform float fade = 1.0;
instance uniform vec4 tint : source_color = vec4(0.2, 0.9, 1.0, 1.0);
void fragment() {
	float r = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = tint.rgb * pow(r, 2.2) * 1.8 * fade;
}
"""
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = gs
	_ball = SphereMesh.new()
	_ball.radius = 0.5
	_ball.height = 1.0
	_ball.radial_segments = 16
	_ball.rings = 8
	_streak = BoxMesh.new()
	_streak.size = Vector3(0.07, 0.07, 1.0)
	_flare = BoxMesh.new()
	_flare.size = Vector3(1.0, 0.07, 0.07)


## 접점에서 시작해 -Z 로 뻗으며 +X 로 휘는 칼날 리본 (길이 1, 가운데가 두껍고 양끝이 뾰족).
## UV.x = 길이 방향, UV.y = 폭 방향
static func _build_swoosh(bend: float, seg: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	var nrm: Array[Vector3] = []
	var wid: Array[float] = []
	for i in seg + 1:
		var u := float(i) / seg
		var c := Vector3(bend * u * u, 0, -u)
		var tg := Vector3(2.0 * bend * u, 0, -1).normalized()
		pts.append(c)
		nrm.append(Vector3(-tg.z, 0, tg.x))
		wid.append(pow(sin(clampf(u * 0.92 + 0.08, 0.0, 1.0) * PI), 0.7) * 0.24 * (1.0 - u * 0.3))
	for i in seg:
		var u0 := float(i) / seg
		var u1 := float(i + 1) / seg
		var a0 := pts[i] + nrm[i] * wid[i]
		var b0 := pts[i] - nrm[i] * wid[i]
		var a1 := pts[i + 1] + nrm[i + 1] * wid[i + 1]
		var b1 := pts[i + 1] - nrm[i + 1] * wid[i + 1]
		st.set_uv(Vector2(u0, 0)); st.add_vertex(a0)
		st.set_uv(Vector2(u0, 1)); st.add_vertex(b0)
		st.set_uv(Vector2(u1, 1)); st.add_vertex(b1)
		st.set_uv(Vector2(u0, 0)); st.add_vertex(a0)
		st.set_uv(Vector2(u1, 1)); st.add_vertex(b1)
		st.set_uv(Vector2(u1, 0)); st.add_vertex(a1)
	return st.commit()


# ── 판정 보조: 빔이 처음 닿는 적 ─────────────────────────

## origin 에서 dir 로 length 만큼 뻗은 폭 width 의 빔이 처음 닿는 적의 표면 지점.
## blocks=true 인 적(보스처럼 blocks_beam 을 가진 기체)은 빔을 막는다.
static func find_contact(tree: SceneTree, origin: Vector3, dir: Vector3, length: float, width: float) -> Dictionary:
	var best := {}
	var best_d := 1e9
	for e in tree.get_nodes_in_group("enemies"):
		var en := e as Enemy
		if not en.alive or not en.landed:
			continue
		var rel := en.global_position - origin
		rel.y = 0
		var along := rel.dot(dir)
		if along < 0.0 or along > length + en.radius:
			continue
		var perp := (rel - dir * along).length()
		if perp > en.radius + width * 0.5:
			continue
		var p := minf(perp, en.radius)
		var entry := maxf(0.3, along - sqrt(maxf(0.0, en.radius * en.radius - p * p)))
		if entry < best_d and entry <= length:
			best_d = entry
			# size: 연출 크기 배율. 보스(반지름 3.3)=1, 작은 적은 최소 0.35
			best = {"pos": origin + dir * entry, "enemy": en, "dist": entry, "blocks": en.get("blocks_beam") == true,
				"size": clampf(en.radius / BIG_RADIUS, MIN_SIZE, 1.0)}
	return best


# ── 지속 레이저 ─────────────────────────────────────────

func _ready() -> void:
	_res()
	core = Pal.flat_mesh(_ball, WHITE, 3.2)
	add_child(core)
	halo = _glow_ball(CYAN)
	add_child(halo)
	flare_h = Pal.flat_mesh(_flare, WHITE, 2.8)
	add_child(flare_h)
	flare_v = Pal.flat_mesh(_flare, Color(0.8, 1.0, 1.0), 2.4)
	add_child(flare_v)
	light = OmniLight3D.new()
	light.light_color = Color(0.55, 0.95, 1.0)
	light.omni_range = 8.0
	light.light_energy = 0.0
	add_child(light)
	for i in 4:
		var f := _blade_mesh()
		add_child(f)
		fans.append(f)
	scale = Vector3.ONE
	_apply_k()


static func _blade_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _arc
	mi.material_override = _add_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("tint", CYAN)
	mi.set_instance_shader_parameter("fade", 1.0)
	return mi


## 칼날 방향: 쏜 쪽으로 튀되 바깥으로 휘도록 side 에 맞춰 뒤집는다
static func _orient_blade(mi: MeshInstance3D, pos: Vector3, s: Vector3, side: float, length: float) -> void:
	var up := Vector3.UP if absf(s.y) < 0.95 else Vector3.RIGHT
	var b := Basis.looking_at(s, up) * Basis(Vector3.BACK, randf_range(-0.35, 0.35))
	mi.global_transform = Transform3D(b, pos)
	# 가로(X)를 뒤집으면 휘는 방향이 바뀐다. 폭은 길이에 맞춰 키운다
	mi.scale = Vector3(side * length * 0.9, 1.0, length)


static func _glow_ball(c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _ball
	mi.material_override = _glow_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("tint", c)
	mi.set_instance_shader_parameter("fade", 1.0)
	return mi


## 매 프레임: 빔이 적 표면 pos 에 닿아 있다
func touch(pos: Vector3, d: Vector3, pw := 1.0) -> void:
	global_position = pos
	dir = Vector3(d.x, 0, d.z).normalized()
	power = pw
	light.omni_range = 8.0 * maxf(pw, 0.5)
	active_t = 0.1
	dying = false


func finish() -> void:
	dying = true
	active_t = 0.0


func _process(dt: float) -> void:
	t += dt
	active_t -= dt
	var on := active_t > 0.0
	k = move_toward(k, 1.0 if on else 0.0, dt * (14.0 if on else 6.0))
	_apply_k()
	if on:
		_emit(dt)
	elif dying and k <= 0.0:
		queue_free()


func _apply_k() -> void:
	var flick := 0.85 + 0.3 * sin(t * 90.0) * sin(t * 37.0)
	core.scale = Vector3.ONE * (0.9 + 0.35 * flick) * k * power
	halo.scale = Vector3.ONE * (2.8 + 0.8 * flick) * k * power
	halo.set_instance_shader_parameter("fade", k)
	# 십자 플레어: 빔에 수직인 가로 줄 + 세로 줄
	var side := dir.cross(Vector3.UP).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var b := Basis(side, Vector3.UP, side.cross(Vector3.UP))
	flare_h.global_basis = b
	flare_h.scale = Vector3(maxf((4.5 + 2.0 * flick) * k * power, 0.001), maxf(k, 0.001), maxf(k, 0.001))
	flare_v.global_basis = Basis(Vector3.UP, -side, Vector3.UP.cross(-side))
	flare_v.scale = Vector3(maxf((2.2 + 1.0 * flick) * k * power, 0.001), maxf(k, 0.001), maxf(k, 0.001))
	light.light_energy = 6.0 * k * flick * power
	visible = k > 0.001
	# 날개: 좌우 두 장씩, 1/20초마다 모양을 새로 잡아 거칠게 일렁인다
	fan_t -= get_process_delta_time()
	if fan_t <= 0.0 and k > 0.0:
		fan_t = 0.05
		for i in fans.size():
			var fs := -1.0 if i % 2 == 0 else 1.0
			var sd := (-dir).rotated(Vector3.UP, fs * deg_to_rad(randf_range(22.0, 48.0) + (i / 2) * 26.0))
			sd.y = randf_range(0.15, 0.55)
			var L := randf_range(3.2, 5.0) * k * power * (1.0 if i < 2 else 0.7)
			_orient_blade(fans[i], global_position, sd.normalized(), -fs, maxf(L, 0.01))
			fans[i].set_instance_shader_parameter("fade", k * randf_range(0.75, 1.0))
			fans[i].set_instance_shader_parameter("tint", CYAN if randf() < 0.75 else BLUE)


func _emit(dt: float) -> void:
	blade_t -= dt
	if blade_t <= 0.0:
		blade_t = 0.035
		_blade(global_position, dir, power, 0.2)
	streak_t -= dt
	if streak_t <= 0.0:
		streak_t = 0.02
		for i in 3:
			_spray(global_position, dir, power)
	ring_t -= dt
	if ring_t <= 0.0:
		ring_t = 0.18
		_ring(global_position, dir, 1.9 * power, 0.18)
	spark_t -= dt
	if spark_t <= 0.0:
		spark_t = 0.05
		FX.sparks(global_position - dir * 0.3, 6, [WHITE, CYAN, BLUE], 13.0 * sqrt(power), 0.3, -8.0, 0.1 * sqrt(power))
	snd_t -= dt
	if snd_t <= 0.0:
		snd_t = 0.09
		Sfx.play("hit", 0.25, -5.0)
		if Main.inst:
			Main.inst.shake(0.05 * power)


# ── 연출 조각 ───────────────────────────────────────────

## 튀는 방향: 쏜 쪽(-dir)을 중심으로 좌우 30~85°, 위로 조금
static func _splash_dir(d: Vector3) -> Vector3:
	var side := 1.0 if randf() < 0.5 else -1.0
	var s := (-d).rotated(Vector3.UP, side * deg_to_rad(randf_range(20.0, 80.0)))
	s.y = randf_range(0.05, 0.6)
	return s.normalized()


## 초승달 칼날: 접점에서 바깥으로 날아가며 커지고 사라진다
static func _blade(pos: Vector3, d: Vector3, pw: float, life: float) -> void:
	_res()
	var s := _splash_dir(d)
	var mi := _take(_pool_blade)
	if mi == null:
		mi = _blade_mesh()
		FX.root.add_child(mi)
	else:
		mi.set_instance_shader_parameter("fade", 1.0)
	mi.set_instance_shader_parameter("tint", CYAN if randf() < 0.7 else BLUE)
	# 쏜 방향 기준 왼쪽으로 튀면 왼쪽으로, 오른쪽이면 오른쪽으로 휜다
	var side := -signf((-d).cross(s).y + 0.0001)
	var L := randf_range(1.8, 3.4) * pw
	_orient_blade(mi, pos, s, side, L * 0.35)
	var end_scale := Vector3(side * L * 0.9, 1.0, L)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "global_position", pos + s * randf_range(0.6, 1.4) * pw, life).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mi, "scale", end_scale, life * 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(func(v: float): mi.set_instance_shader_parameter("fade", v), 1.0, 0.0, life).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func() -> void: _give(_pool_blade, mi))


## 물보라 줄기: 가늘고 긴 빛줄기가 빠르게 튀어 나간다
static func _spray(pos: Vector3, d: Vector3, pw: float) -> void:
	_res()
	var s := _splash_dir(d)
	s = (s + Vector3(randf_range(-0.2, 0.2), randf_range(-0.1, 0.3), randf_range(-0.2, 0.2))).normalized()
	var c := WHITE if randf() < 0.45 else CYAN
	var mi := _take(_pool_spray)
	if mi == null:
		mi = Pal.flat_mesh(_streak, c, 2.6)
		FX.root.add_child(mi)
	else:
		mi.set_instance_shader_parameter("tint", c)
	var l := randf_range(0.8, 1.8) * pw
	var up := Vector3.UP if absf(s.y) < 0.95 else Vector3.RIGHT
	mi.global_transform = Transform3D(Basis.looking_at(s, up), pos + s * (0.3 + l * 0.5))
	mi.scale = Vector3(1, 1, l)
	var dist := randf_range(2.5, 4.5) * pw
	var life := randf_range(0.1, 0.17)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "global_position", pos + s * (dist + l * 0.5), life).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "scale", Vector3(0.2, 0.2, l * 0.4), life).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func() -> void: _give(_pool_spray, mi))


## 숨겨 둔 조각 하나를 꺼낸다 (FX.root 가 바뀌어 지워진 것은 버린다). 없으면 null
static func _take(pool: Array) -> MeshInstance3D:
	while not pool.is_empty():
		var n = pool.pop_back()
		if is_instance_valid(n) and n.get_parent() == FX.root:
			var mi := n as MeshInstance3D
			mi.visible = true
			return mi
	return null


static func _give(pool: Array, mi: MeshInstance3D) -> void:
	mi.visible = false
	pool.append(mi)


## 빔에 수직으로 퍼지는 충격파 고리
static func _ring(pos: Vector3, d: Vector3, size: float, life: float) -> void:
	var mi := Pal.flat_mesh(FX._ring_mesh(), Color(0.75, 1.0, 1.0), 2.2)
	FX.root.add_child(mi)
	var b := Basis.looking_at(d, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)
	mi.global_transform = Transform3D(b, pos - d * 0.25)
	mi.scale = Vector3(0.3, 0.05, 0.3)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(size, 0.02, size), life).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(func(c: Color): mi.set_instance_shader_parameter("tint", c), Color(0.75, 1.0, 1.0), Color(0.05, 0.2, 0.4), life)
	tw.chain().tween_callback(mi.queue_free)


## 충전 레이저 한 방: 한꺼번에 터지는 피격 (k = 충전량 0~1)
static func burst(pos: Vector3, d: Vector3, k: float, size := 1.0) -> void:
	_res()
	d = Vector3(d.x, 0, d.z).normalized()
	var pw := lerpf(0.7, 1.25, k) * size
	for i in maxi(3, int(lerpf(5.0, 11.0, k) * size)):
		_blade(pos, d, pw, randf_range(0.16, 0.26))
	for i in maxi(5, int(lerpf(10.0, 22.0, k) * size)):
		_spray(pos, d, pw)
	_ring(pos, d, 3.2 * pw, 0.24)
	_ring(pos, d, 1.8 * pw, 0.16)
	FX.flash(pos, WHITE, 1.4 * pw, 0.1)
	FX.sparks(pos - d * 0.3, maxi(6, int(lerpf(12.0, 26.0, k) * size)), [WHITE, CYAN, BLUE], 15.0 * sqrt(size), 0.35, -8.0, 0.1 * sqrt(size))
	var halo := _glow_ball(CYAN)
	FX.root.add_child(halo)
	halo.global_position = pos
	halo.scale = Vector3.ONE * 4.0 * pw
	var tw := halo.create_tween().set_parallel(true)
	tw.tween_property(halo, "scale", Vector3.ONE * 0.5, 0.22).set_ease(Tween.EASE_IN)
	tw.tween_method(func(v: float): halo.set_instance_shader_parameter("fade", v), 1.0, 0.0, 0.22)
	tw.chain().tween_callback(halo.queue_free)
	var light := OmniLight3D.new()
	light.light_color = Color(0.55, 0.95, 1.0)
	light.omni_range = 8.0
	light.light_energy = 8.0 * pw
	FX.root.add_child(light)
	light.global_position = pos
	var ltw := light.create_tween()
	ltw.tween_property(light, "light_energy", 0.0, 0.25)
	ltw.tween_callback(light.queue_free)
